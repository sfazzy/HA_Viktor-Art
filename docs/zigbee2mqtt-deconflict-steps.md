# Zigbee2MQTT deconflict steps (G02/G03/G05)

## What was wrong
- `zigbee2mqtt2` (G02), `zigbee2mqtt3` (G03) and `zigbee2mqtt5` (G05) shared the same Zigbee network identity:
  - same `advanced.pan_id`
  - same `advanced.ext_pan_id`
  - same `advanced.network_key`
  - and the same channel from coordinator backups (`channel: 11`)
- When networks overlap (even partially), devices can join/roam to the "wrong" coordinator and appear offline/flaky.

## What was changed (files on Z:\)
- `Z:\zigbee2mqtt2\configuration.yaml`:
  - Set `advanced.channel: 11` to match the coordinator backup (prevents startup mismatch).
  - No other network identity changes here (G02 keeps the original network).
- `Z:\zigbee2mqtt3\configuration.yaml`:
  - Set a NEW `advanced.channel`, `pan_id`, `ext_pan_id`, `network_key` (G03 becomes a separate network).
  - Archived `coordinator_backup.json`, `database.db`, `state.json` into `*.bak-recommission-<timestamp>`.
- `Z:\zigbee2mqtt5\configuration.yaml`:
  - Set a NEW `advanced.channel`, `pan_id`, `ext_pan_id`, `network_key` (G05 becomes a separate network).
  - Archived `coordinator_backup.json`, `database.db`, `state.json` into `*.bak-recommission-<timestamp>`.

## What you must do in Home Assistant now
1) Restart ONLY these Zigbee2MQTT add-ons:
   - G03 (the add-on pointing to `Z:\zigbee2mqtt3`)
   - G05 (the add-on pointing to `Z:\zigbee2mqtt5`)

2) Expect this consequence:
   - G03 and G05 are now **new networks** -> devices that used to be on them will need to be **re-paired**.
   - G02 (zigbee2mqtt2) should keep working as before.

3) If an add-on fails to start with a "configuration-adapter mismatch":
   - It usually means there is still a `coordinator_backup.json` in that instance folder or the add-on is using a different `data_path` than expected.
   - Confirm the add-on `data_path` matches the folder you intended (e.g. `/config/zigbee2mqtt3` for G03).

## If you need to revert (emergency)
- Stop the affected add-on.
- Restore the archived files by renaming back:
  - `coordinator_backup.json.bak-recommission-...` -> `coordinator_backup.json`
  - `database.db.bak-recommission-...` -> `database.db`
  - `state.json.bak-recommission-...` -> `state.json`
- Restore previous values in `configuration.yaml` (use the `configuration.yaml.bak-*` files in that folder).

