param(
  # By default, scans the latest log per instance.
  # Set -Days to scan all logs newer than N days (can be noisy).
  [int]$Days = 0,
  # Fail the audit only if an error-pattern match occurs in logs written within the last N days.
  # (Older errors are kept as historical signal but won't fail CI/audits.)
  [int]$ErrorDays = 7,
  [switch]$All
)

$ErrorActionPreference = 'Stop'

Set-Location (Split-Path -Parent $PSCommandPath) | Out-Null
Set-Location .. | Out-Null

$warnPatterns = @(
  'Failed to ping'
)

$errorPatterns = @(
  'Configuration is not consistent with adapter backup',
  'configuration-adapter mismatch',
  'Failed to start zigbee-herdsman',
  'Error while starting zigbee-herdsman',
  'Adapter disconnected',
  'Failed to connect',
  'startup failed'
)

$patterns = @($warnPatterns + $errorPatterns)

$allLogFiles = Get-ChildItem -Path . -Recurse -File -Filter log.log |
  Where-Object { $_.FullName -match 'zigbee2mqtt\d*\\log\\' } |
  Sort-Object FullName

if (-not $allLogFiles) {
  Write-Host "No Zigbee2MQTT log.log files found under zigbee2mqtt*/log/"
  exit 0
}

if ($All) {
  $logFiles = $allLogFiles
} else {
  if ($Days -gt 0) {
    $cutoff = (Get-Date).AddDays(-[double]$Days)
    $logFiles = $allLogFiles | Where-Object { $_.LastWriteTime -ge $cutoff }
  } else {
    $logFiles = $allLogFiles |
      Group-Object { ($_.FullName -split '\\log\\', 2)[0] } |
      ForEach-Object { $_.Group | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
  }
}

Write-Host "Scanning $($logFiles.Count) Zigbee2MQTT log files..."

$hits = @()
foreach ($f in $logFiles) {
  foreach ($p in $patterns) {
    $m = Select-String -Path $f.FullName -Pattern $p -SimpleMatch -ErrorAction SilentlyContinue
    if ($m) {
      foreach ($line in $m) {
        $hits += [pscustomobject]@{
          file = $f.FullName
          file_time = $f.LastWriteTime
          pattern = $p
          line = $line.LineNumber
          text = $line.Line.Trim()
        }
      }
    }
  }
}

if (-not $hits) {
  Write-Host "OK: no matching error patterns found."
  exit 0
}

Write-Host ""
Write-Host "Findings (first 200):"
$hits | Select-Object -First 200 | Format-Table -AutoSize file,line,pattern,text

Write-Host ""
Write-Host "Summary:"
$hits | Group-Object pattern | Sort-Object Count -Descending | Format-Table -AutoSize Count,Name

$errorCutoff = (Get-Date).AddDays(-[double]$ErrorDays)
$hasRecentError = $hits | Where-Object { ($errorPatterns -contains $_.pattern) -and ($_.file_time -ge $errorCutoff) } | Select-Object -First 1
if ($hasRecentError) { exit 1 }
exit 0
