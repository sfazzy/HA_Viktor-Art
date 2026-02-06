# bring up the custom Grafana container compatible with HA add-on data
param (
  [string]$HostPort = '3001',
  [string]$DataDir = 'C:\ProgramData\docker\volumes\grafana_data',
  [string]$Image = 'grafana/grafana:12.3.0'
)

$env:GF_SECURITY_ALLOW_EMBEDDING = 'true'
$env:GF_AUTH_ANONYMOUS_ENABLED = 'true'
$env:GF_AUTH_ANONYMOUS_ORG_ROLE = 'Viewer'
$env:GF_SERVER_ROOT_URL = "http://192.168.2.108:$HostPort/"
$env:GF_SERVER_SERVE_FROM_SUB_PATH = 'false'
$env:GF_SECURITY_CSRF_TRUSTED_ORIGINS = "http://192.168.2.108:$HostPort"

Write-Host "Starting grafana_custom ($Image) on port $HostPort ..."
docker rm -f grafana_custom -v 2>$null | Out-Null
docker run -d `
  --name grafana_custom `
  --restart unless-stopped `
  -p "$HostPort":3000 `
  -v "$DataDir:/var/lib/grafana" `
  -e GF_SECURITY_ALLOW_EMBEDDING `
  -e GF_AUTH_ANONYMOUS_ENABLED `
  -e GF_AUTH_ANONYMOUS_ORG_ROLE `
  -e GF_SERVER_ROOT_URL `
  -e GF_SERVER_SERVE_FROM_SUB_PATH `
  -e GF_SECURITY_CSRF_TRUSTED_ORIGINS `
  $Image | Write-Host
