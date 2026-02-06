# Zigbee2MQTT: multiple independent Zigbee networks (Dom + Firma)

## What this means
- You run multiple Zigbee2MQTT instances.
- Each instance has its **own coordinator** and its **own Zigbee network**.
- All networks feed the same Home Assistant via MQTT discovery.

This is the correct approach when Dom/Firma are far apart and a single Zigbee mesh cannot cover the distance.

## Hard rules (stability)
For every Zigbee2MQTT instance:
1) Unique Zigbee network parameters:
   - `advanced.network_key`
   - `advanced.pan_id`
   - `advanced.ext_pan_id`
   - (recommended) `advanced.channel`
2) Unique MQTT base topic:
   - `mqtt.base_topic`
3) (Recommended) Unique frontend port:
   - `frontend.port`

## What was fixed in this repo
Your repo contained many instances (`zigbee2mqtt1..11`) that all used the same PAN/key/channel.
That makes devices unstable because multiple coordinators advertised what looked like the same network.

Now each network (`g1`, `g2`, `g3`, …) has unique:
- `channel`
- `pan_id`
- `ext_pan_id`
- `network_key`

## Pairing / migration reality
Changing `network_key` / `pan_id` / `ext_pan_id` creates a **new Zigbee network**.
Previously paired devices will NOT magically reappear; they must be paired again to the correct network.

## If Zigbee2MQTT refuses to start (configuration-adapter mismatch)
You may see errors like:
- `startup failed - configuration-adapter mismatch`
- `Configuration is not consistent with adapter backup!`

This happens when the coordinator still contains the *old* network and Zigbee2MQTT has a different network configured.

To re-commission that network (will require re-pairing devices on that coordinator):
1) Stop that Zigbee2MQTT instance/add-on.
2) In the corresponding folder (e.g. `zigbee2mqtt8/`) rename/remove:
   - `coordinator_backup.json`
   - `database.db`
   - `state.json`
3) Start the instance again. It should form the network from `configuration.yaml` and recreate those files.

Recommended workflow per network:
1) Start the Zigbee2MQTT instance and verify the coordinator is reachable.
2) Set `permit_join: true` temporarily.
3) Pair routers (mains powered) first, then battery devices.
4) Set `permit_join: false` again.

## Coordinator reachability
Your Zigbee2MQTT configs use TCP serial bridges (Tasmota ZB-GW03): `tcp://<ip>:8888` (or `:6688`).
If a coordinator IP/port is down, the whole instance will fail to start.

For Tasmota ZB-GW03 make sure the TCP bridge starts on boot:
- `Rule1 ON System#Boot DO TCPStart 8888 ENDON`
- `Rule1 1`
- `Restart 1`

## Network map (your naming)

| Instance | Title | Site | Folder | MQTT base_topic |
|---|---|---|---|---|
| g1 | G01 W5 Laser | COMPANY | `zigbee2mqtt1/` | `tasmota_g1` |
| g2 | G02 Biuro Patryk | HOME | `zigbee2mqtt/` | `tasmota_g2` |
| g3 | G03 Pompownia | COMPANY | `zigbee2mqtt3/` | `tasmota_g3` |
| g4 | G04 W3 | COMPANY | `zigbee2mqtt4/` | `tasmota_g4` |
| g5 | G05 W4 6AX | COMPANY | `zigbee2mqtt5/` | `tasmota_g5` |
| g6 | G06 Mal | COMPANY | `zigbee2mqtt6/` | `tasmota_g6` |
| g7 | G07 Garaz | HOME | `zigbee2mqtt7/` | `tasmota_g7` |
| g8 | G08 Rodzice Dom | HOME | `zigbee2mqtt8/` | `tasmota_g8` |
| g9 | G09 Patryk Dom | HOME | `zigbee2mqtt9/` | `tasmota_g9` |
| g10 | G10 Bartek Biuro | COMPANY | `zigbee2mqtt10/` | `tasmota_g10` |
| g11 | G11 Zapasowy | SPARE (disabled) | `zigbee2mqtt11/` | `tasmota_g11_spare` |
