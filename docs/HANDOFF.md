# Home Assistant handoff

Generated: 2026-02-05 04:02:07

This repo contains a Home Assistant configuration with multiple Zigbee2MQTT instances (separate Zigbee networks).

## Home Assistant highlights

- Core config: `configuration.yaml`
- Zigbee2MQTT sidebar panels: configured via custom integration `custom_components/ingress` (see `configuration.yaml:411`)
- InfluxDB: host=`192.168.2.108`, db=`homeassistant`, user=`homeassistant` (password is in `secrets.yaml`)
- Virtual silence button: `script.z2m_safety_silence` publishes MQTT topic `ha/z2m_safety/silence`
- Node-RED safety flow export: `docs/node-red/z2m_safety_alarms.json`

## Node-RED safety system

- Import flow: `docs/node-red/z2m_safety_alarms.json`
- MQTT control topics:
  - Virtual silence: `ha/z2m_safety/silence` (1× = silence; 3× within 5s = reset loops + pump restore attempt)
  - Sirens enable: `ha/z2m_safety/sirens` payload `{ "enabled": true|false }`
- Email: Node-RED built-in `e-mail` (SMTP) node is included and prefilled with server/user/port (password is stored in Node-RED credentials and is not exported in JSON by design)
- Siren repeat escalation (while alarm remains active):
  - Starts at `floodRepeatSeconds` / `smokeRepeatSeconds` / `heatRepeatSeconds`
  - Each repeat halves the pause until `repeatMinSeconds` (default 10s), then repeats every `repeatMinSeconds`
- Push reminder escalation (no email escalation):
  - While alarm is still active, the repeat ticks also send push reminders via `notifyPushService`
  - Throttled by `pushRepeatMinSeconds` (default 60s) to avoid notification spam when siren repeat reaches 10s

## Zigbee2MQTT layout

Notes:
- Each Zigbee2MQTT instance must have a unique Zigbee network identity (channel + PAN ID + Extended PAN ID + network key).
- Do not share network keys publicly. This handoff stores a `fingerprint` (SHA-256) of the identity for collision detection.
- MQTT passwords exist in the Z2M config files but are intentionally not copied here.

| instance | base_topic | serial | adapter | ch | pan_id | fingerprint | coordinator_ieee | backup pan/ext/key | permit_join |
|---|---|---|---|---:|---:|---|---|---|---|
| `zigbee2mqtt1` | `tasmota_g1` | `tcp://192.168.2.161:6688` | `ezsp` | 11 | 25253 | `0ab57f94e413e8557fd690e540711c54174ae09a7a5a449ad640ca71ce4655cc` | `1cc089fffece2548` | `pan=62a5, ext=00039f71a6953db3, key=28d9b6...1e11f6` | false |
| `zigbee2mqtt10` | `tasmota_g10` | `tcp://192.168.2.170:8888` | `ezsp` | 17 | 13434 | `b5d949f5f40ac6ca23bcc54c519534a33503aa86e01b604aafc10987fbbceed5` | `1cc089fffecdeb58` | `pan=347a, ext=ee419f1364b81639, key=a64628...0ff934` | false |
| `zigbee2mqtt11` | `tasmota_g11` | `tcp://192.168.2.171:8888` | `ezsp` | 22 | 57741 | `2aaa07c5f74516819688be0f0683a3affea68d362e22e9c69e41298f4647aa30` | `1cc089fffece0e60` | `pan=e18d, ext=009cbfffc10e7054, key=6f016e...51569b` | false |
| `zigbee2mqtt12` | `tasmota_g12` | `tcp://192.168.2.172:8888` | `ezsp` | 25 | 50001 | `59b8f5e3347c02f959af4ffbf2313cbdc64b6b064c329aa422f8889a66b1ff27` | `9035eafffe4bd03b` | `pan=c351, ext=16212c37424d5863, key=102030...e0f00f` | false |
| `zigbee2mqtt2` | `tasmota_g2` | `tcp://192.168.2.162:8888` | `ezsp` | 12 | 41234 | `e8c70e71fcb0f36524817d1cf0ebbda1884b37efc0d020201808ca1fd04189ef` | `04cd15fffec07096` | `pan=a112, ext=c97a212c37424d58, key=0cde5b...11be49` | false |
| `zigbee2mqtt3` | `tasmota_g3` | `tcp://192.168.2.163:8888` | `ezsp` | 20 | 30003 | `b69d70ecb449087118e681c1315d2b4906dc8bcc95c2bbf1fdae5d151722b624` | `9035eafffe4bc558` | `pan=7533, ext=952a25ab8d9c1c52, key=91928b...c8fe18` | false |
| `zigbee2mqtt4` | `tasmota_g4` | `tcp://192.168.2.164:8888` | `ezsp` | 25 | 26386 | `9fc452cdd69a964a8c375987506ab2a264556f04e0bf31331982324776ed277f` | `1cc089fffeceaae0` | `pan=6712, ext=1ccc9cfe00b1c9eb, key=6185a6...c8c0bb` | false |
| `zigbee2mqtt5` | `tasmota_g5` | `tcp://192.168.2.165:8888` | `ezsp` | 11 | 29739 | `9f233a9953a1a0ac3768a6b360fe33c62b9acc110d93459982534ce1cd800a3f` | `1cc089fffeceb11c` | `pan=742b, ext=658c9c5bffe29678, key=404dcc...a5ef01` | false |
| `zigbee2mqtt6` | `tasmota_g6` | `tcp://192.168.2.166:8888` | `ezsp` | 16 | 20711 | `19e18f4b2205c00daf864c4cb7b7e9a1d914da8334db24da4a57e3654794e155` | `1cc089fffece9b10` | `pan=50e7, ext=3b6afeae5de6be5c, key=6fcfa4...9951ad` | false |
| `zigbee2mqtt7` | `tasmota_g7` | `tcp://192.168.2.167:8888` | `ezsp` | 21 | 13270 | `99f67b6ba183d7898801bbcff68c23847858ee888c2bc1eadabb92b27829e538` | `1cc089fffece1008` | `pan=33d6, ext=243a5699310302a8, key=9c0958...22409e` | false |
| `zigbee2mqtt8` | `tasmota_g8` | `tcp://192.168.2.168:8888` | `ezsp` | 26 | 48348 | `a69329fad865f7d7cbd56e523e5a21e8365d8e2b1e96b7c71f9c4c55c700d473` | `1cc089fffece9db8` | `pan=bcdc, ext=3306c87f3d3928de, key=f73745...ff1cef` | false |
| `zigbee2mqtt9` | `tasmota_g9` | `tcp://192.168.2.169:8888` | `ezsp` | 13 | 14364 | `a1b405e464d62def9b68b673cb58cbf56062d2b710651024b6a6f1119b59ba7a` | `08b95ffffe593eb7` | `pan=381c, ext=3168fac5f70a0179, key=374da4...e1183a` | false |

### Deprecated placeholder
- `zigbee2mqtt/configuration.yaml` is marked deprecated/not used and points serial to `tcp://192.0.2.1:8888` to avoid touching a real coordinator.

## Device inventory

- Export file: `docs\z2m_devices.md`
- Regenerate: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/z2m_export_devices.ps1`

## Audits

- Config audit: `tools/z2m_audit.ps1`
- Log audit (latest per instance): `tools/z2m_log_audit.ps1`

## Recent Z2M log notes (latest log per instance)

These are best-effort extracts from log files stored in this repo (not live state).
- `zigbee2mqtt1` latest log: `A:\zigbee2mqtt1\log\2026-01-28.23-23-02\log.log` (2026-02-05 03:53:14)
  - sample: `[2026-02-04 08:07:39] error: 	zh:ezsp:uart: --> Error: Error: {"sequence":5} after 4000ms`
- `zigbee2mqtt10` latest log: `A:\zigbee2mqtt10\log\2026-01-28.23-22-35\log.log` (2026-02-05 04:00:30)
  - sample: `[2026-01-31 14:50:49] error: 	zh:ezsp:uart: --> Error: Error: {"sequence":5} after 4000ms`
- `zigbee2mqtt11` latest log: `A:\zigbee2mqtt11\log\2026-02-03.00-39-12\log.log` (2026-02-05 04:01:56)
  - sample: `[2026-02-03 09:33:58] error: 	zh:ezsp:uart: --> Error: Error: {"sequence":1} after 4000ms`
- `zigbee2mqtt12` latest log: `A:\zigbee2mqtt12\log\2026-02-03.00-41-16\log.log` (2026-02-05 04:01:28)
  - sample: `[2026-02-03 02:52:56] error: 	zh:ezsp:uart: --> Error: Error: {"sequence":5} after 4000ms`
  - failed pings in that log: 2
- `zigbee2mqtt3` latest log: `A:\zigbee2mqtt3\log\2026-02-04.08-09-07\log.log` (2026-02-05 04:01:34)
  - sample: `[2026-02-04 08:09:08] error: 	zh:ezsp:ezsp: Connection attempt 1 error: Error: connect ECONNREFUSED 192.168.2.163:8888`
- `zigbee2mqtt6` latest log: `A:\zigbee2mqtt6\log\2026-01-31.00-19-29\log.log` (2026-02-05 04:01:34)
  - sample: `[2026-01-31 14:50:30] error: 	zh:ezsp:uart: --> Error: Error: {"sequence":5} after 4000ms`
- `zigbee2mqtt9` latest log: `A:\zigbee2mqtt9\log\2026-01-31.16-02-00\log.log` (2026-02-05 03:52:28)
  - failed pings in that log: 5

## Operational recovery notes

- If Zigbee2MQTT fails with `configuration-adapter mismatch`, stop that instance and remove its `coordinator_backup.json` (and usually `database.db` + `state.json`) to re-commission; this requires re-pairing all devices for that instance.
- If HA sidebar opens the wrong Zigbee2MQTT, check the custom `ingress:` mapping in `configuration.yaml:411` (work_mode: hassio uses Supervisor ingress tokens, not raw host ports).
