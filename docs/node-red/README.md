# Node-RED: Flood + Smoke Safety Automations (Zigbee2MQTT)

Files:
- Importable flow: `docs/node-red/z2m_safety_alarms.json`
- Device inventory source (from this repo): `docs/z2m_devices.md`

## What it does

- **Flood (water leak)**
  - Trigger: any Z2M leak sensor reports `water_leak: true`
  - Actions (immediate):
    - HA push notification (service configurable)
    - Email notification via Node-RED `e-mail` node (SMTP)
    - Turn off configured pump outlets (HA `switch.turn_off` with your entity list)
    - Start a repeating short siren “beep” every ~150 seconds until silenced

- **Smoke**
  - Trigger: any smoke sensor reports `smoke/alarm: true` (best-effort field detection)
  - Actions (immediate):
    - HA push + email via Node-RED `e-mail` node (SMTP)
    - Start a repeating short siren “beep sequence” every ~120 seconds until silenced
    - Workshop-origin smoke uses **2 beeps**, home-origin uses **3 beeps** (based on which Z2M network the detector is in)

- **Heat**
  - Trigger: any configured temperature sensor reports `temperature >= 45°C`
  - Actions (immediate):
    - HA push + email via Node-RED `e-mail` node (SMTP)
    - Start a repeating short siren beep every ~180 seconds until silenced

- **Silence / acknowledge**
  - Trigger: pressing any configured `B*` button (Aqara `lumi.remote.b1acn01`) publishes an `action`
  - Actions:
    - Stops flood/smoke repeating siren loops
    - Sends an “acknowledged” push + email
  - Multi-press:
    - **1 press**: silence sirens and suppress beeps for `silenceMinutes`
    - **3 presses within 5 seconds**: reset repeating loops (stops future beeps after silence expires)

- **Virtual silence button (Home Assistant dashboard)**
  - Entity: `script.z2m_safety_silence` (defined in `scripts.yaml`)
  - When pressed, publishes MQTT to `ha/z2m_safety/silence` which the flow treats like a silence button.

- **Smoke detector hush/test buttons**
  - If your smoke detector publishes an `action`/`test`/`selftest` field on its MQTT topic, the flow treats it as a silence input (config: `smokeHushAsSilence`).

- **Production/Test mode buttons (Home Assistant dashboard)**
  - `script.z2m_safety_test_mode`: disables sirens (notifications still work)
  - `script.z2m_safety_production_mode`: enables sirens

## Requirements

- Node-RED with:
  - MQTT access to the same broker your Zigbee2MQTT uses (`core-mosquitto:1883` by default)
  - Outbound HTTP access to Home Assistant Core API
- Home Assistant notify services:
  - Push: default `notify.notify` (change if you want a specific phone)
  - Email: handled by Node-RED `e-mail` node (SMTP)

## How it calls Home Assistant (no HA-specific Node-RED nodes required)

The flow uses the Home Assistant REST API and expects one of these to work:

- **HA add-on Node-RED**: uses `SUPERVISOR_TOKEN` and `http://supervisor/core`
- **External Node-RED**: set environment variables:
  - `HA_BASE_URL` (e.g. `http://192.168.2.108:8123`)
  - `HA_TOKEN` (Home Assistant long-lived access token)

## Customize

Open the “CONFIG” function node in the flow and edit:

- **Test mode (no sirens):** Sirens are disabled by default. Use the inject nodes **Sirens ON** / **Sirens OFF (test mode)** to toggle.
- **Test buttons:** Use **TEST: Flood / TEST: Flood (pumps off) / TEST: Smoke (workshop) / TEST: Smoke (home) / TEST: Heat** inject nodes and **TEST: Reset/clear alarms** to clear state between runs.
- **Output diagnostics:** Use **TEST: Outputs (ALL)** (or the per-output buttons) to verify push/email/sirens/pumps without waiting for a real sensor event.

- `pumpSwitchEntities`: HA entity IDs to turn off (e.g. `switch.pump_1`, `switch.pump_2`)
- `pumpOutletsZ2M`: Z2M MQTT pump outlets to turn off (uses `<base_topic>/<name>/set` with `{"state":"OFF"}`)
- `notifyPushService`: e.g. `notify.notify` or `notify.mobile_app_your_phone`
- `emailTo`: recipient email(s) for the Node-RED email node
- `silenceMinutes`: how long “B button silence” lasts
- `autoClearFlood` / `autoClearSmoke`: whether to auto-clear when sensors report normal (recommended `false`)
- `heatThresholdC` + `heatSensors`: heat alarm threshold and list of temp sensors used
- `pumpRestoreDryMinutes` + `pumpRestoreDryReportMinutes`: when pumps can be restored after triple-press (no wet recently + recent dry confirmations)
- Siren payload templates for flood vs smoke (Z2M sirens can differ by model/firmware)

## Notes / limitations

- “Currently connected” is approximated by Zigbee2MQTT traffic; this flow reacts to incoming MQTT messages. Battery devices may not publish again until they wake up.
- Some smoke sensors may use different payload fields; the smoke detection function checks multiple common keys but may need tweaking for your models.

## Troubleshooting (nothing happens)

- Open the Node-RED right sidebar **Debug** tab to see:
  - `DEBUG events` (incoming classified/test events)
  - `DEBUG alarm/title` (when an alarm starts)
  - `DEBUG HA response` (HTTP results from Home Assistant notify calls)
  - `DEBUG status` / `DEBUG errors` (MQTT/HTTP connection issues)

- If you see `ReferenceError: process is not defined` in the `CONFIG` node, update to the latest flow version (this repo uses `env.get(...)` instead of `process.env`).
- If you see `401: Unauthorized` in `DEBUG HA response`, your HA token is missing/invalid:
  - HA add-on Node-RED: ensure `SUPERVISOR_TOKEN` is available to Node-RED
  - External Node-RED: set `HA_BASE_URL` and `HA_TOKEN`, or hardcode `haBaseUrl` + `haToken` in the `CONFIG` node.
