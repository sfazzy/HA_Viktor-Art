# Grafana token helper
# Stores token encrypted with Windows DPAPI (current user) so the push script can reuse it.

param(
  [Parameter(Mandatory = $false)]
  [string]$Token = $env:GRAFANA_TOKEN,

  [Parameter(Mandatory = $false)]
  [string]$OutFile = '',

  [switch]$Clear
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg) { Write-Host "[grafana] $msg" }

function Get-ScriptRoot {
  if ($PSScriptRoot) { return $PSScriptRoot }
  if ($MyInvocation.MyCommand.Path) { return (Split-Path -Parent $MyInvocation.MyCommand.Path) }
  return (Get-Location).Path
}

if (-not $OutFile) {
  $OutFile = Join-Path (Get-ScriptRoot) '.token.secure'
}

if ($Clear) {
  if (Test-Path $OutFile) {
    Remove-Item -Force $OutFile
    Write-Info "Removed token file: $OutFile"
  } else {
    Write-Info "Token file not found: $OutFile"
  }
  exit 0
}

$secure = $null
if ($Token) {
  $secure = ConvertTo-SecureString $Token -AsPlainText -Force
} else {
  $secure = Read-Host -AsSecureString 'Grafana API token (input hidden)'
}

$enc = $secure | ConvertFrom-SecureString

# DPAPI-encrypted for the current Windows user on this machine.
Set-Content -Path $OutFile -Value $enc -NoNewline -Encoding ASCII
Write-Info "Saved DPAPI-encrypted token to: $OutFile"
Write-Info "Now run: powershell -ExecutionPolicy Bypass -File Z:\tools\grafana\push-dashboards.ps1 -GrafanaUrl 'https://192.168.2.108:3000' -InsecureTls"
