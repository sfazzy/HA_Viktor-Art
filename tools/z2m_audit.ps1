$ErrorActionPreference = 'Stop'

Set-Location (Split-Path -Parent $PSCommandPath) | Out-Null
Set-Location .. | Out-Null

function Parse-Z2mConfig([string]$path) {
  $lines = (Get-Content -Path $path -Raw) -split "\r?\n"

  $obj = [ordered]@{
    path = $path
    base_topic = $null
    mqtt_server = $null
    mqtt_user = $null
    frontend_port = $null
    serial_port = $null
    serial_adapter = $null
    permit_join = $null
    channel = $null
    pan_id = $null
    ext_pan_id = $null
    network_key = $null
  }

  $context = $null
  $mode = $null
  $netKey = @()
  $extPan = @()

  foreach ($lineRaw in $lines) {
    $line = $lineRaw.TrimEnd()

    if ($line -match '^\s*#') { continue }

    if ($line -match '^permit_join:\s*(.+?)\s*$') { $obj.permit_join = $Matches[1] }

    if ($line -match '^(mqtt|frontend|serial|advanced|homeassistant|availability):\s*$') {
      $context = $Matches[1]
      if ($context -ne 'advanced') { $mode = $null }
      continue
    }

    if ($line -match '^[A-Za-z0-9_]+:\s*.*$' -and $line -notmatch '^\s') {
      $context = $null
      $mode = $null
    }

    if ($context -eq 'mqtt') {
      if ($line -match '^\s{2}server:\s*(.+?)\s*$') { $obj.mqtt_server = $Matches[1] }
      if ($line -match '^\s{2}user:\s*(.+?)\s*$') { $obj.mqtt_user = $Matches[1] }
      if ($line -match '^\s{2}base_topic:\s*(.+?)\s*$') { $obj.base_topic = $Matches[1] }
    }

    if ($context -eq 'frontend') {
      if ($line -match '^\s{2}port:\s*(\d+)\s*$') { $obj.frontend_port = [int]$Matches[1] }
    }

    if ($context -eq 'serial') {
      if ($line -match '^\s{2}port:\s*(.+?)\s*$') { $obj.serial_port = $Matches[1] }
      if ($line -match '^\s{2}adapter:\s*(.+?)\s*$') { $obj.serial_adapter = $Matches[1] }
    }

    if ($context -eq 'advanced') {
      if ($line -match '^\s{2}channel:\s*(\d+)\s*$') { $obj.channel = [int]$Matches[1] }
      if ($line -match '^\s{2}pan_id:\s*(\d+)\s*$') { $obj.pan_id = [int]$Matches[1] }

      if ($line -match '^\s{2}network_key:\s*$') { $mode = 'key'; $netKey = @(); continue }
      if ($line -match '^\s{2}ext_pan_id:\s*$') { $mode = 'ext'; $extPan = @(); continue }

      if ($mode -and $line -match '^\s{4}-\s*(\d+)\s*$') {
        if ($mode -eq 'key') { $netKey += [int]$Matches[1] } else { $extPan += [int]$Matches[1] }
        continue
      }

      if ($mode -and $line -match '^\s{2}[A-Za-z0-9_]+:\s*') { $mode = $null }
    }
  }

  if ($netKey.Count -gt 0) { $obj.network_key = ($netKey -join ',') }
  if ($extPan.Count -gt 0) { $obj.ext_pan_id = ($extPan -join ',') }

  [pscustomobject]$obj
}

function Write-Section([string]$title) {
  Write-Host ""
  Write-Host $title
  Write-Host ("-" * $title.Length)
}

$cfgFiles = Get-ChildItem -Directory -Filter 'zigbee2mqtt*' | ForEach-Object {
  $p = Join-Path $_.FullName 'configuration.yaml'
  if (Test-Path $p) { Get-Item $p }
} | Sort-Object FullName

$configs = foreach ($f in $cfgFiles) { Parse-Z2mConfig $f.FullName }

Write-Section "Zigbee2MQTT configs"
$configs | Select-Object path,base_topic,serial_port,frontend_port,channel,pan_id,permit_join | Format-Table -AutoSize

$errors = @()
$warnings = @()

foreach ($c in $configs) {
  if ($null -eq $c.base_topic -or $c.base_topic -eq '') { $errors += "Missing mqtt.base_topic: $($c.path)" }
  if ($null -eq $c.serial_port -or $c.serial_port -eq '') { $errors += "Missing serial.port: $($c.path)" }
  if ($null -eq $c.serial_adapter -or $c.serial_adapter -eq '') { $warnings += "Missing serial.adapter (recommended): $($c.path)" }
  if ($c.permit_join -ne 'false') { $errors += "permit_join should be false: $($c.path) (got '$($c.permit_join)')" }
  if ($null -eq $c.channel) { $warnings += "Missing advanced.channel (recommended): $($c.path)" }
  if ($null -eq $c.pan_id) { $warnings += "Missing advanced.pan_id (recommended): $($c.path)" }
  if ($null -eq $c.ext_pan_id) { $warnings += "Missing advanced.ext_pan_id (recommended): $($c.path)" }
  if ($null -eq $c.network_key) { $warnings += "Missing advanced.network_key (recommended): $($c.path)" }
}

Write-Section "Collisions (configs)"

$dupBase = $configs | Group-Object base_topic | Where-Object { $_.Name -and $_.Count -gt 1 }
foreach ($g in $dupBase) { $errors += "Duplicate mqtt.base_topic '$($g.Name)': $($g.Group.path -join '; ')" }

$dupSerial = $configs | Group-Object serial_port | Where-Object { $_.Name -and $_.Count -gt 1 }
foreach ($g in $dupSerial) { $errors += "Duplicate serial.port '$($g.Name)': $($g.Group.path -join '; ')" }

$dupFrontend = $configs | Group-Object frontend_port | Where-Object { $_.Name -and $_.Count -gt 1 }

$configsWithId = $configs | ForEach-Object {
  $id = "ch=$($_.channel);pan=$($_.pan_id);ext=$($_.ext_pan_id);key=$($_.network_key)"
  $_ | Add-Member -PassThru -NotePropertyName net_id -NotePropertyValue $id
}
$dupNet = $configsWithId | Group-Object net_id | Where-Object { $_.Name -and $_.Count -gt 1 }
foreach ($g in $dupNet) { $errors += "Duplicate Zigbee network identity '$($g.Name)': $($g.Group.path -join '; ')" }

if (-not $dupBase) { Write-Host "- mqtt.base_topic: OK" }
if (-not $dupSerial) { Write-Host "- serial.port: OK" }
if ($dupFrontend) {
  Write-Host "- frontend.port: INFO (duplicates are normal for HA add-on Ingress; required unique only if exposed on host):"
  $dupFrontend | ForEach-Object { Write-Host "    $($_.Name): $($_.Group.path -join '; ')" }
} else { Write-Host "- frontend.port: OK" }
if (-not $dupNet) { Write-Host "- Zigbee identity: OK" }

$bkFiles = Get-ChildItem -Directory -Filter 'zigbee2mqtt*' | ForEach-Object {
  $p = Join-Path $_.FullName 'coordinator_backup.json'
  if (Test-Path $p) { $p }
} | Sort-Object

if ($bkFiles.Count -gt 0) {
  Write-Section "Coordinator backups"
  $bks = foreach ($p in $bkFiles) {
    $j = Get-Content $p -Raw | ConvertFrom-Json
    [pscustomobject]@{
      file = $p
      coordinator_ieee = $j.coordinator_ieee
      channel = $j.channel
      pan_id = $j.pan_id
      extended_pan_id = $j.extended_pan_id
      network_key = $j.network_key.key
    }
  }

  $bks | Select-Object file,coordinator_ieee,channel,pan_id,extended_pan_id | Format-Table -AutoSize

  $dupBkIeee = $bks | Group-Object coordinator_ieee | Where-Object { $_.Name -and $_.Count -gt 1 }
  foreach ($g in $dupBkIeee) { $warnings += "Duplicate coordinator_ieee '$($g.Name)' in backups: $($g.Group.file -join '; ')" }

  $bksWithId = $bks | ForEach-Object {
    $id = "ch=$($_.channel);pan=$($_.pan_id);ext=$($_.extended_pan_id);key=$($_.network_key)"
    $_ | Add-Member -PassThru -NotePropertyName net_id -NotePropertyValue $id
  }
  $dupBkNet = $bksWithId | Group-Object net_id | Where-Object { $_.Name -and $_.Count -gt 1 }
  foreach ($g in $dupBkNet) { $warnings += "Duplicate Zigbee network identity in backups '$($g.Name)': $($g.Group.file -join '; ')" }
}

Write-Section "Results"
if ($warnings.Count -gt 0) {
  Write-Host "WARNINGS:"
  $warnings | ForEach-Object { Write-Host " - $_" }
}

if ($errors.Count -gt 0) {
  Write-Host "ERRORS:"
  $errors | ForEach-Object { Write-Host " - $_" }
  exit 1
}

Write-Host "OK"
