param(
  [string]$OutPath = "docs/HANDOFF.md"
)

$ErrorActionPreference = 'Stop'

Set-Location (Split-Path -Parent $PSCommandPath) | Out-Null
Set-Location .. | Out-Null

function Sha256Hex([string]$text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $hash = $sha.ComputeHash($bytes)
    return ($hash | ForEach-Object { $_.ToString("x2") }) -join ""
  } finally {
    $sha.Dispose()
  }
}

function Parse-Z2mAdvanced([string]$configPath) {
  $lines = (Get-Content -Path $configPath -Raw) -split "\r?\n"

  $channel = $null
  $panId = $null
  $netKey = @()
  $extPan = @()
  $mode = $null
  $inAdvanced = $false

  foreach ($l in $lines) {
    if ($l -match '^advanced:\s*$') { $inAdvanced = $true; continue }
    if ($inAdvanced -and $l -match '^[A-Za-z0-9_]+:\s*.*$' -and $l -notmatch '^\s') { $inAdvanced = $false; $mode = $null }
    if (-not $inAdvanced) { continue }

    if ($l -match '^\s{2}channel:\s*(\d+)\s*$') { $channel = [int]$Matches[1] }
    if ($l -match '^\s{2}pan_id:\s*(\d+)\s*$') { $panId = [int]$Matches[1] }

    if ($l -match '^\s{2}network_key:\s*$') { $mode = 'key'; $netKey = @(); continue }
    if ($l -match '^\s{2}ext_pan_id:\s*$') { $mode = 'ext'; $extPan = @(); continue }

    if ($mode -and $l -match '^\s{4}-\s*(\d+)\s*$') {
      if ($mode -eq 'key') { $netKey += [int]$Matches[1] } else { $extPan += [int]$Matches[1] }
      continue
    }
    if ($mode -and $l -match '^\s{2}[A-Za-z0-9_]+:\s*') { $mode = $null }
  }

  $keyText = if ($netKey.Count -gt 0) { $netKey -join ',' } else { '' }
  $extText = if ($extPan.Count -gt 0) { $extPan -join ',' } else { '' }

  [pscustomobject]@{
    channel = $channel
    pan_id = $panId
    ext_pan_id = $extText
    network_key = $keyText
    fingerprint = if ($channel -and $panId -and $keyText) { Sha256Hex("ch=$channel;pan=$panId;ext=$extText;key=$keyText") } else { '' }
  }
}

function Get-ConfigValue([string]$configPath, [string]$regex) {
  $m = Select-String -Path $configPath -Pattern $regex | Select-Object -First 1
  if (-not $m) { return "" }
  return ($m.Line -replace $regex, '$1').Trim()
}

New-Item -ItemType Directory -Path (Split-Path -Parent $OutPath) -Force | Out-Null

$now = Get-Date
$tick = [char]96

# HA core config highlights
$haConfig = Join-Path (Get-Location) 'configuration.yaml'
$haInfluxHost = Get-ConfigValue $haConfig '^\s{2}host:\s*(.+?)\s*$'
$haInfluxDb = Get-ConfigValue $haConfig '^\s{2}database:\s*(.+?)\s*$'
$haInfluxUser = Get-ConfigValue $haConfig '^\s{2}username:\s*(.+?)\s*$'

# Z2M instances
$instances = Get-ChildItem -Directory -Filter 'zigbee2mqtt*' | Sort-Object Name
$rows = @()
foreach ($inst in $instances) {
  $configPath = Join-Path $inst.FullName 'configuration.yaml'
  if (-not (Test-Path $configPath)) { continue }

  $permitJoin = Get-ConfigValue $configPath '^permit_join:\s*(.+?)\s*$'
  $mqttServer = Get-ConfigValue $configPath '^\s{2}server:\s*(mqtt://.+?)\s*$'
  $mqttUser = Get-ConfigValue $configPath '^\s{2}user:\s*(.+?)\s*$'
  $baseTopic = Get-ConfigValue $configPath '^\s{2}base_topic:\s*(.+?)\s*$'
  $frontendPort = Get-ConfigValue $configPath '^\s{2}port:\s*(\d+)\s*$'
  $serialPort = Get-ConfigValue $configPath '^\s{2}port:\s*((tcp://|/dev/).+?)\s*$'
  $serialAdapter = Get-ConfigValue $configPath '^\s{2}adapter:\s*(.+?)\s*$'
  $adv = Parse-Z2mAdvanced $configPath

  $backupPath = Join-Path $inst.FullName 'coordinator_backup.json'
  $coordinatorIeee = ''
  $backupPanHex = ''
  $backupExt = ''
  $backupKeyHint = ''
  if (Test-Path $backupPath) {
    try {
      $bk = Get-Content $backupPath -Raw | ConvertFrom-Json
      $coordinatorIeee = $bk.coordinator_ieee
      $backupPanHex = $bk.pan_id
      $backupExt = $bk.extended_pan_id
      $k = $bk.network_key.key
      if ($k) {
        $backupKeyHint = ($k.Substring(0, 6) + "..." + $k.Substring($k.Length - 6))
      }
    } catch {}
  }

  $rows += [pscustomobject]@{
    instance = $inst.Name
    base_topic = $baseTopic
    mqtt_server = $mqttServer
    mqtt_user = $mqttUser
    permit_join = $permitJoin
    serial_port = $serialPort
    serial_adapter = $serialAdapter
    frontend_port = $frontendPort
    channel = $adv.channel
    pan_id = $adv.pan_id
    fingerprint = $adv.fingerprint
    coordinator_ieee = $coordinatorIeee
    backup_pan_id_hex = $backupPanHex
    backup_ext_pan_id_hex = $backupExt
    backup_net_key_hint = $backupKeyHint
    config_path = $configPath
    backup_path = if (Test-Path $backupPath) { $backupPath } else { "" }
  }
}

$devicesExport = Join-Path (Split-Path -Parent $OutPath) 'z2m_devices.md'

$logIssues = @()
foreach ($r in ($rows | Where-Object { $_.instance -match '^zigbee2mqtt\d+$' })) {
  $instDir = Split-Path -Parent $r.config_path
  $logRoot = Join-Path $instDir 'log'
  if (-not (Test-Path $logRoot)) { continue }

  $latestLog = Get-ChildItem -Path $logRoot -Recurse -File -Filter log.log -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $latestLog) { continue }

  $content = Get-Content -Path $latestLog.FullName -ErrorAction SilentlyContinue
  if (-not $content) { continue }

  $errLine = $content | Where-Object { $_ -match '\]\s+error:\s+' } | Select-Object -First 1
  $mismatch = $content | Where-Object { $_ -match 'configuration-adapter mismatch|Configuration is not consistent with adapter backup|EHOSTUNREACH|Failure to connect|Failed to start zigbee-herdsman|Adapter disconnected' } | Select-Object -First 1
  $pingCount = ($content | Where-Object { $_ -match 'Failed to ping' }).Count

  if ($errLine -or $mismatch -or $pingCount -gt 0) {
    $logIssues += [pscustomobject]@{
      instance = $r.instance
      log = $latestLog.FullName
      log_time = $latestLog.LastWriteTime
      error_sample = if ($mismatch) { $mismatch.Trim() } elseif ($errLine) { $errLine.Trim() } else { "" }
      failed_ping_count = $pingCount
    }
  }
}

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Home Assistant handoff")
$md.Add("")
$md.Add("Generated: $($now.ToString('yyyy-MM-dd HH:mm:ss'))")
$md.Add("")
$md.Add("This repo contains a Home Assistant configuration with multiple Zigbee2MQTT instances (separate Zigbee networks).")
$md.Add("")
$md.Add("## Home Assistant highlights")
$md.Add("")
$md.Add("- Core config: " + $tick + "configuration.yaml" + $tick)
$md.Add("- Zigbee2MQTT sidebar panels: configured via custom integration " + $tick + "custom_components/ingress" + $tick + " (see " + $tick + "configuration.yaml:411" + $tick + ")")
$md.Add("- InfluxDB: host=" + $tick + $haInfluxHost + $tick + ", db=" + $tick + $haInfluxDb + $tick + ", user=" + $tick + $haInfluxUser + $tick + " (password is in " + $tick + "secrets.yaml" + $tick + ")")

# Optional: virtual safety silence script (dashboard button)
$scriptsPath = Join-Path (Get-Location) 'scripts.yaml'
if (Test-Path $scriptsPath) {
  $lines = Get-Content -Path $scriptsPath
  $start = ($lines | Select-String -Pattern '^z2m_safety_silence:\s*$' | Select-Object -First 1).LineNumber
  if ($start) {
    $startIdx = $start - 1
    $blockLines = New-Object System.Collections.Generic.List[string]
    for ($i = $startIdx; $i -lt $lines.Count; $i++) {
      $line = $lines[$i]
      if ($i -gt $startIdx -and ($line -match '^\S')) { break }
      $blockLines.Add($line)
    }

    $block = ($blockLines -join "`n")
    $topic = ''
    if ($block -match '(?m)^\s*topic:\s*(.+?)\s*$') { $topic = $Matches[1] }
    if ($topic) {
      $md.Add("- Virtual silence button: " + $tick + "script.z2m_safety_silence" + $tick + " publishes MQTT topic " + $tick + $topic + $tick)
    } else {
      $md.Add("- Virtual silence button: " + $tick + "script.z2m_safety_silence" + $tick)
    }
  }
}
$md.Add("")
$md.Add("## Zigbee2MQTT layout")
$md.Add("")
$md.Add("Notes:")
$md.Add("- Each Zigbee2MQTT instance must have a unique Zigbee network identity (channel + PAN ID + Extended PAN ID + network key).")
$md.Add("- Do not share network keys publicly. This handoff stores a " + $tick + "fingerprint" + $tick + " (SHA-256) of the identity for collision detection.")
$md.Add("- MQTT passwords exist in the Z2M config files but are intentionally not copied here.")
$md.Add("")
$md.Add("| instance | base_topic | serial | adapter | ch | pan_id | fingerprint | coordinator_ieee | backup pan/ext/key | permit_join |")
$md.Add("|---|---|---|---|---:|---:|---|---|---|---|")

foreach ($r in ($rows | Where-Object { $_.instance -ne 'zigbee2mqtt' } | Sort-Object instance)) {
  $backupSummary = ""
  if ($r.backup_pan_id_hex) {
    $backupSummary = "pan=" + $r.backup_pan_id_hex + ", ext=" + $r.backup_ext_pan_id_hex + ", key=" + $r.backup_net_key_hint
  }
  $md.Add("| " + $tick + $r.instance + $tick + " | " + $tick + $r.base_topic + $tick + " | " + $tick + $r.serial_port + $tick + " | " + $tick + $r.serial_adapter + $tick + " | $($r.channel) | $($r.pan_id) | " + $tick + $r.fingerprint + $tick + " | " + $tick + $r.coordinator_ieee + $tick + " | " + $tick + $backupSummary + $tick + " | $($r.permit_join) |")
}

$md.Add("")
$md.Add("### Deprecated placeholder")
$deprecated = $rows | Where-Object { $_.instance -eq 'zigbee2mqtt' } | Select-Object -First 1
if ($deprecated) {
  $md.Add("- " + $tick + "zigbee2mqtt/configuration.yaml" + $tick + " is marked deprecated/not used and points serial to " + $tick + $deprecated.serial_port + $tick + " to avoid touching a real coordinator.")
}
$md.Add("")
$md.Add("## Device inventory")
$md.Add("")
$md.Add("- Export file: " + $tick + $devicesExport.Replace('\\','/') + $tick)
$md.Add("- Regenerate: " + $tick + "powershell -NoProfile -ExecutionPolicy Bypass -File tools/z2m_export_devices.ps1" + $tick)
$md.Add("")
$md.Add("## Audits")
$md.Add("")
$md.Add("- Config audit: " + $tick + "tools/z2m_audit.ps1" + $tick)
$md.Add("- Log audit (latest per instance): " + $tick + "tools/z2m_log_audit.ps1" + $tick)
$md.Add("")
$md.Add("## Recent Z2M log notes (latest log per instance)")
$md.Add("")
$md.Add("These are best-effort extracts from log files stored in this repo (not live state).")

if (-not $logIssues) {
  $md.Add("- No issues detected in stored logs.")
} else {
  foreach ($li in ($logIssues | Sort-Object instance)) {
    $md.Add("- " + $tick + $li.instance + $tick + " latest log: " + $tick + $li.log + $tick + " (" + $li.log_time.ToString('yyyy-MM-dd HH:mm:ss') + ")")
    if ($li.error_sample) { $md.Add("  - sample: " + $tick + $li.error_sample + $tick) }
    if ($li.failed_ping_count -gt 0) { $md.Add("  - failed pings in that log: $($li.failed_ping_count)") }
  }
}
$md.Add("")
$md.Add("## Operational recovery notes")
$md.Add("")
$md.Add("- If Zigbee2MQTT fails with " + $tick + "configuration-adapter mismatch" + $tick + ", stop that instance and remove its " + $tick + "coordinator_backup.json" + $tick + " (and usually " + $tick + "database.db" + $tick + " + " + $tick + "state.json" + $tick + ") to re-commission; this requires re-pairing all devices for that instance.")
$md.Add("- If HA sidebar opens the wrong Zigbee2MQTT, check the custom " + $tick + "ingress:" + $tick + " mapping in " + $tick + "configuration.yaml:411" + $tick + " (work_mode: hassio uses Supervisor ingress tokens, not raw host ports).")

$md | Set-Content -Path $OutPath -Encoding UTF8

Write-Host "Wrote $OutPath"
