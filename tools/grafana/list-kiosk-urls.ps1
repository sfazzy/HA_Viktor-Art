#requires -version 5.1
param(
  [Parameter(Mandatory = $false)]
  [string]$GrafanaUrl = 'http://192.168.2.108:3000',

  [Parameter(Mandatory = $false)]
  [string]$Token = $env:GRAFANA_TOKEN,

  [Parameter(Mandatory = $false)]
  [int]$OrgId = 1,

  [switch]$InsecureTls
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg) { Write-Host "[grafana] $msg" }

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

function Invoke-Grafana([string]$method, [string]$url) {
  $curl = @('curl.exe', '-sS')
  if ($InsecureTls) { $curl += '-k' }
  $curl += @('-H', 'Accept: application/json')
  if ($Token) { $curl += @('-H', "Authorization: Bearer $Token") }
  if ($method -ne 'GET') { $curl += @('-X', $method) }

  $exe = $curl[0]
  $args = @()
  if ($curl.Length -gt 1) { $args = $curl[1..($curl.Length - 1)] }

  $out = & $exe @args $url 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "curl failed (exit $LASTEXITCODE): $out"
  }
  if (-not $out) { return $null }
  try { return ($out | ConvertFrom-Json) } catch { return $out }
}

function Resolve-BaseUrl([string]$base) {
  $base = $base.TrimEnd('/')
  # Reject ingress redirects explicitly (requirement)
  $resp = curl.exe -sS -D - -o NUL ($base + '/api/health') 2>$null
  $loc = ($resp | Select-String -Pattern '^Location:\s*(.+)$' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_[0].Groups[1].Value } | Select-Object -First 1)
  if ($loc -and $loc -match '/api/hassio_ingress/') {
    throw "GrafanaUrl '$base' redirects to Home Assistant ingress ($loc). Expose Grafana directly on LAN and re-run."
  }
  return $base
}

function Add-Query([string]$url, [hashtable]$q) {
  $u = [System.Uri]$url
  $qs = [System.Web.HttpUtility]::ParseQueryString($u.Query)
  foreach ($k in $q.Keys) { $qs[$k] = [string]$q[$k] }
  $builder = New-Object System.UriBuilder($u)
  $builder.Query = $qs.ToString()
  return $builder.Uri.AbsoluteUri
}

if (-not $Token) { $Token = Get-TokenFromSecureFile }

$base = Resolve-BaseUrl $GrafanaUrl
Write-Info "Base URL: $base"

$searchUrl = "$base/api/search?type=dash-db&limit=5000"
$items = Invoke-Grafana 'GET' $searchUrl
if ($items -is [string]) { throw "Unexpected response from ${searchUrl}: $items" }

if (-not $items) {
  Write-Info 'No dashboards returned.'
  exit 0
}

$rows = @()
$tvUrls = @()
foreach ($it in $items) {
  if (-not $it.uid -or -not $it.url) { continue }

  $normal = "$base$($it.url)"
  $normal = Add-Query $normal @{ orgId = $OrgId }

  $kioskFull = Add-Query $normal @{ kiosk = 1; refresh = '30s' }
  $kioskTv = Add-Query $normal @{ kiosk = 'tv'; refresh = '30s' }

  $rows += [PSCustomObject]@{
    Title = $it.title
    Normal = $normal
    KioskFull = $kioskFull
    KioskTV = $kioskTv
  }
  $tvUrls += $kioskTv
}

Write-Host ''
foreach ($row in ($rows | Sort-Object Title)) {
  Write-Host "Title: $($row.Title)"
  Write-Host "Normal: $($row.Normal)"
  Write-Host "Kiosk full: $($row.KioskFull)"
  Write-Host "Kiosk TV: $($row.KioskTV)"
  Write-Host ''
}

Write-Host "`nKiosk TV URLs (copy/paste):" 
$tvUrls | Sort-Object | Get-Unique | ForEach-Object { $_ }
