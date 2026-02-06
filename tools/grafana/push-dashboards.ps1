param(
  [Parameter(Mandatory = $false)]
  [string]$GrafanaUrl = "https://192.168.2.108:3000",

  [Parameter(Mandatory = $false)]
  [string]$Token = $env:GRAFANA_TOKEN,

  [Parameter(Mandatory = $false)]
  [string]$DatasourceName = "InfluxDB",

  [Parameter(Mandatory = $false)]
  [string[]]$DashboardPaths = @(),

  [switch]$InsecureTls,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Info([string]$msg) { Write-Host "[grafana] $msg" }

function Ensure-Tls12 {
  try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
  } catch {}
}

function Get-ScriptRoot {
  if ($PSScriptRoot) { return $PSScriptRoot }
  if ($MyInvocation.MyCommand.Path) { return (Split-Path -Parent $MyInvocation.MyCommand.Path) }
  return (Get-Location).Path
}

function Get-TokenFromSecureFile {
  $paths = @()
  try { $paths += (Join-Path (Get-ScriptRoot) '.token.secure') } catch {}
  try { if ($env:USERPROFILE) { $paths += (Join-Path $env:USERPROFILE '.grafana_token.secure') } } catch {}

  foreach ($p in @($paths | Where-Object { $_ -and (Test-Path $_) })) {
    try {
      $enc = Get-Content -Raw -Path $p
      if (-not $enc) { continue }
      $sec = ConvertTo-SecureString $enc
      $plain = (New-Object System.Net.NetworkCredential('', $sec)).Password
      if ($plain) { return $plain }
    } catch {}
  }
  return $null
}


function Set-TlsPolicy {
  Ensure-Tls12
  if (-not $InsecureTls) { return }
  Write-Info "Using insecure TLS (self-signed certs allowed)."
  add-type @"
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy {
  public static bool TrustAll(object sender, X509Certificate cert, X509Chain chain, SslPolicyErrors errors) { return true; }
}
"@ | Out-Null
  [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { param($sender, $cert, $chain, $errors) return [TrustAllCertsPolicy]::TrustAll($sender,$cert,$chain,$errors) }
}

function Resolve-GrafanaBaseUrl([string]$base) {
  $health = "$base/api/health"
  try {
    $resp = curl.exe -k -sS -D - $health -o NUL
  } catch {
    throw "Cannot reach Grafana at $health"
  }

  # If Grafana is behind HA ingress, the endpoint redirects to /api/hassio_ingress/<slug>/.
  $loc = ($resp | Select-String -Pattern '^Location:\s*(.+)$' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_[0].Groups[1].Value } | Select-Object -First 1)
  if ($loc) {
    if ($loc -match '/api/hassio_ingress/') {
      if ($loc -match '^https?://') { return $loc.TrimEnd('/') }
      return ($base.TrimEnd('/') + '/' + $loc.TrimStart('/')).TrimEnd('/')
    }
  }
  return $base.TrimEnd('/')
}

function Invoke-Grafana([string]$method, [string]$url, $body = $null) {
  # Use curl.exe instead of Invoke-RestMethod because Grafana behind HA ingress often breaks .NET TLS/redirect handling.
  $curl = @("curl.exe", "-sS")
  if ($InsecureTls) { $curl += "-k" }
  $curl += @("-H", "Accept: application/json")
  if ($Token) { $curl += @("-H", "Authorization: Bearer $Token") }

  if ($method -ne "GET") { $curl += @("-X", $method) }

  $tmp = $null
  if ($body -ne $null) {
    $tmp = [System.IO.Path]::GetTempFileName()
    $json = ($body | ConvertTo-Json -Depth 50)
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    $curl += @("-H", "Content-Type: application/json", "--data-binary", ("@" + $tmp))
  }

  try {
    $exe = $curl[0]
    $args = @()
    if ($curl.Length -gt 1) { $args = $curl[1..($curl.Length - 1)] }
    $out = & $exe @args $url 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw "curl failed (exit $LASTEXITCODE): $out"
    }
    if (-not $out) { return $null }
    try { return ($out | ConvertFrom-Json) } catch { return $out }
  } finally {
    if ($tmp -and (Test-Path $tmp)) { Remove-Item -Force $tmp -ErrorAction SilentlyContinue }
  }
}

function Get-DatasourceUid([string]$baseUrl, [string]$name) {
  # Try name endpoint first (Grafana 8+)
  try {
    $ds = Invoke-Grafana "GET" "$baseUrl/api/datasources/name/$name"
    if ($ds.uid) { return $ds.uid }
  } catch {}

  $all = Invoke-Grafana "GET" "$baseUrl/api/datasources"
  $match = $all | Where-Object { $_.name -eq $name } | Select-Object -First 1
  if (-not $match) { throw "Datasource '$name' not found in Grafana. Available: $($all.name -join ', ')" }
  if (-not $match.uid) { throw "Datasource '$name' found but missing uid (Grafana too old?)" }
  return $match.uid
}

function Normalize-DashboardObject($dashboard, [string]$dsUid) {
  # Remove import-only metadata if present
  $dashboard.PSObject.Properties.Remove("__inputs") | Out-Null
  $dashboard.PSObject.Properties.Remove("__requires") | Out-Null
  $dashboard.id = $null

  $dsObj = @{ type = "influxdb"; uid = $dsUid }

  function Ensure-PanelDatasource($p) {
    if ($null -eq $p) { return }
    $hasDs = $p.PSObject.Properties.Match('datasource').Count -gt 0
    if (-not $hasDs) {
      $p | Add-Member -NotePropertyName datasource -NotePropertyValue $dsObj -Force
      return
    }
    if ($p.datasource -is [string]) {
      if ($p.datasource -match 'DS_' -or $p.datasource -match '\\$\\{') {
        $p.datasource = $dsObj
      }
      return
    }
    if ($p.datasource -is [hashtable] -or $p.datasource -is [pscustomobject]) { return }
    $p.datasource = $dsObj
  }

  function Ensure-TargetsDatasource($p) {
    if ($null -eq $p) { return }
    $hasTargets = $p.PSObject.Properties.Match('targets').Count -gt 0
    if (-not $hasTargets) { return }
    foreach ($t in @($p.targets)) {
      if ($t -and ($t.PSObject.Properties.Match('datasource').Count -gt 0) -and $t.datasource -is [string] -and ($t.datasource -match 'DS_' -or $t.datasource -match '\\$\\{')) {
        $t.datasource = $dsObj
      }
    }
  }

  foreach ($panel in @($dashboard.panels)) {
    if ($null -eq $panel) { continue }
    Ensure-PanelDatasource $panel
    Ensure-TargetsDatasource $panel

    # Row panels can contain nested panels
    if ($panel.PSObject.Properties.Match('panels').Count -gt 0) {
      foreach ($sub in @($panel.panels)) {
        Ensure-PanelDatasource $sub
        Ensure-TargetsDatasource $sub
      }
    }
  }

  return $dashboard
}

Set-TlsPolicy

if (-not $Token) { $Token = Get-TokenFromSecureFile }

if (-not $DashboardPaths -or $DashboardPaths.Count -eq 0) {
  $root = Get-ScriptRoot
  $DashboardPaths = @((Join-Path $root "..\\..\\..\\docs\\grafana-*.json"))
}

$resolvedBase = Resolve-GrafanaBaseUrl $GrafanaUrl
Write-Info "Base URL: $resolvedBase"

if (-not $Token) {
  Write-Info "Missing token. Set env var GRAFANA_TOKEN or pass -Token."
  Write-Info "Connectivity check only:"
  $health = Invoke-Grafana "GET" "$resolvedBase/api/health"
  $health | ConvertTo-Json -Depth 5 | Write-Output
  exit 2
}

$dsUid = Get-DatasourceUid $resolvedBase $DatasourceName
Write-Info "Using datasource '$DatasourceName' uid=$dsUid"

$expanded = @()
foreach ($p in $DashboardPaths) { $expanded += Get-ChildItem -Path $p -ErrorAction SilentlyContinue }
$expanded = $expanded | Where-Object { $_ } | Sort-Object FullName -Unique
if (-not $expanded) { throw "No dashboard files matched: $($DashboardPaths -join ', ')" }

foreach ($file in $expanded) {
  Write-Info "Loading $($file.FullName)"
  $json = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json
  $dash = Normalize-DashboardObject $json $dsUid

  $payload = @{
    dashboard = $dash
    overwrite = $true
    message = "Updated by push-dashboards.ps1"
  }

  if ($DryRun) {
    Write-Info "Dry run: would push uid=$($dash.uid) title='$($dash.title)'"
    continue
  }

  $res = Invoke-Grafana "POST" "$resolvedBase/api/dashboards/db" $payload
  if ($null -eq $res) {
    throw "Grafana returned no response for $($dash.uid)"
  }
  if ($res -is [string]) {
    throw "Grafana returned a non-JSON response for $($dash.uid): $res"
  }
  if (($res.PSObject.Properties.Match('status').Count -eq 0) -or ($res.PSObject.Properties.Match('url').Count -eq 0)) {
    throw "Unexpected response for $($dash.uid): $($res | ConvertTo-Json -Depth 10)"
  }
  Write-Info "Pushed: $($res.status) url=$($res.url)"
}
