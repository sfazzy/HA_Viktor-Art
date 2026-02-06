param(
  [string]$OutDir = "docs",
  [int]$OnlineWithinMinutes = 1440
)

$ErrorActionPreference = 'Stop'

Set-Location (Split-Path -Parent $PSCommandPath) | Out-Null
Set-Location .. | Out-Null

function Parse-Z2mDeviceNameMap([string]$configPath) {
  $map = @{}
  $lines = Get-Content -Path $configPath
  $inDevices = $false
  $currentIeee = $null

  foreach ($line in $lines) {
    if ($line -match '^\s*devices:\s*$') { $inDevices = $true; $currentIeee = $null; continue }
    if (-not $inDevices) { continue }

    # next top-level key ends devices block
    if ($line -match '^[A-Za-z0-9_]+:\s*.*$' -and $line -notmatch '^\s') { break }

    if ($line -match "^\s{2}'?(0x[0-9a-fA-F]{16})'?:\s*$") {
      $currentIeee = $Matches[1].ToLower()
      continue
    }

    if ($currentIeee -and $line -match '^\s{4}friendly_name:\s*(.+?)\s*$') {
      $name = $Matches[1].Trim().Trim("'").Trim('"')
      $map[$currentIeee] = $name
      $currentIeee = $null
      continue
    }
  }

  return $map
}

function Read-Z2mDatabase([string]$dbPath) {
  $rows = @()
  foreach ($line in Get-Content -Path $dbPath) {
    $l = $line.Trim()
    if (-not $l) { continue }
    try {
      $obj = $l | ConvertFrom-Json
    } catch {
      continue
    }
    $rows += $obj
  }
  return $rows
}

function Get-ConfigValue([string]$configPath, [string]$regex) {
  $m = Select-String -Path $configPath -Pattern $regex | Select-Object -First 1
  if (-not $m) { return "" }
  return ($m.Line -replace $regex, '$1').Trim()
}

function EpochMsToLocal([object]$ms) {
  if ($null -eq $ms) { return $null }
  try {
    $v = [int64]$ms
    if ($v -le 0) { return $null }
    return ([DateTimeOffset]::FromUnixTimeMilliseconds($v)).LocalDateTime
  } catch {
    return $null
  }
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$instances = Get-ChildItem -Directory -Filter 'zigbee2mqtt*' | Sort-Object Name | Where-Object { $_.Name -ne 'zigbee2mqtt' }
$now = Get-Date
$onlineCutoff = $now.AddMinutes(-[double]$OnlineWithinMinutes)

$all = @()

foreach ($inst in $instances) {
  $configPath = Join-Path $inst.FullName 'configuration.yaml'
  $dbPath = Join-Path $inst.FullName 'database.db'
  if (-not (Test-Path $configPath)) { continue }
  if (-not (Test-Path $dbPath)) { continue }

  $baseTopic = Get-ConfigValue $configPath '^\s{2}base_topic:\s*(.+?)\s*$'
  $serialPort = Get-ConfigValue $configPath '^\s{2}port:\s*((tcp://|/dev/).+?)\s*$'
  $channel = Get-ConfigValue $configPath '^\s{2}channel:\s*(\d+)\s*$'
  $panId = Get-ConfigValue $configPath '^\s{2}pan_id:\s*(\d+)\s*$'

  $nameMap = Parse-Z2mDeviceNameMap $configPath
  $db = Read-Z2mDatabase $dbPath

  foreach ($d in $db | Where-Object { $_.type -and $_.ieeeAddr }) {
    $ieee = ($d.ieeeAddr.ToString()).ToLower()
    $friendly = if ($nameMap.ContainsKey($ieee)) { $nameMap[$ieee] } else { "" }
    $lastSeen = EpochMsToLocal $d.lastSeen
    $online = $false
    if ($lastSeen) { $online = ($lastSeen -ge $onlineCutoff) }

    $all += [pscustomobject]@{
      instance = $inst.Name
      base_topic = $baseTopic
      serial_port = $serialPort
      channel = $channel
      pan_id = $panId
      ieee_addr = $ieee
      friendly_name = $friendly
      device_type = $d.type
      manufacturer = $d.manufName
      model = $d.modelId
      nwk_addr = $d.nwkAddr
      last_seen = $lastSeen
      online_guess = $online
    }
  }
}

$csvPath = Join-Path $OutDir 'z2m_devices.csv'
$mdPath = Join-Path $OutDir 'z2m_devices.md'
$tick = [char]96

$all |
  Sort-Object instance, device_type, friendly_name, ieee_addr |
  Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Zigbee2MQTT devices export")
$md.Add("")
$md.Add("Generated: $($now.ToString('yyyy-MM-dd HH:mm:ss'))")
$md.Add("")
$md.Add("`online_guess` = last_seen within $OnlineWithinMinutes minutes (best-effort; not authoritative).")
$md.Add("")

foreach ($g in ($all | Group-Object instance | Sort-Object Name)) {
  $sample = $g.Group | Select-Object -First 1
  $md.Add("## $($g.Name) (" + $tick + "$($sample.base_topic)" + $tick + ")")
  $md.Add("")
  $md.Add("- serial: " + $tick + "$($sample.serial_port)" + $tick)
  $md.Add("- channel: " + $tick + "$($sample.channel)" + $tick)
  $md.Add("- pan_id: " + $tick + "$($sample.pan_id)" + $tick)
  $md.Add("- devices: $($g.Group.Count)")
  $md.Add("")
  $md.Add("| friendly_name | ieee_addr | type | model | manufacturer | last_seen | online_guess |")
  $md.Add("|---|---|---|---|---|---:|---:|")
  foreach ($r in ($g.Group | Sort-Object @{Expression='device_type';Descending=$true}, friendly_name, ieee_addr)) {
    $fn = if ($r.friendly_name) { $r.friendly_name } else { "" }
    $ls = if ($r.last_seen) { $r.last_seen.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
    $md.Add("| $fn | " + $tick + "$($r.ieee_addr)" + $tick + " | $($r.device_type) | $($r.model) | $($r.manufacturer) | $ls | $($r.online_guess) |")
  }
  $md.Add("")
}

$md | Set-Content -Path $mdPath -Encoding UTF8

Write-Host "Wrote:"
Write-Host " - $csvPath"
Write-Host " - $mdPath"
