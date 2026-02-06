# Zigbee2MQTT: one Zigbee network (robust setup)
> Note: This repo is currently configured for MULTIPLE independent Zigbee networks too.
> See `docs/zigbee2mqtt-multi-network.md`.

## Reality check (important)
Zigbee mesh cannot be extended over LAN by running multiple coordinators and "linking them". A Zigbee network has exactly **one coordinator**.

If you want coverage across distant buildings/zones, you have two robust options:
1) **One coordinator + Zigbee routers/repeaters** (recommended, what this repo is moving toward).
2) **Multiple independent Zigbee networks** (multiple coordinators) and accept that it is not "one network" (still totally viable, just different).

## What was wrong in this setup
This config tree contains many Zigbee2MQTT instances (`zigbee2mqtt1..11`) that were all configured with the same:
- `pan_id`
- `ext_pan_id`
- `network_key`
- (and effectively the same channel)

That is a recipe for devices becoming unstable / â€œdisappearingâ€ because multiple coordinators advertise what looks like the *same* network.

## What was changed in this repo
- `zigbee2mqtt/configuration.yaml` is marked as the **PRIMARY** Zigbee2MQTT instance.
- All other Zigbee2MQTT configs (`zigbee2mqtt1..11`) are marked **LEGACY** and have HA discovery + frontend disabled to prevent â€œmulti-bridge clutterâ€ while you migrate.

## Migration checklist (to get to one network)
1) **Pick one coordinator** and keep only that Zigbee2MQTT add-on running.
   - This repo assumes the primary one is `zigbee2mqtt/` (TCP bridge at `192.168.2.162:8888`).
2) **Power off / stop all other coordinators** (or at minimum stop their Zigbee2MQTT add-ons).
   - With cloned network parameters, leaving other coordinators up can keep causing instability.
3) **Build the mesh outward with routers**
   - Add at least 1â€“2 mains-powered Zigbee routers (IKEA repeaters, smart plugs, in-wall relays) per â€œhopâ€ area.
   - Pair routers close to the coordinator first, then move them to their final locations.
4) **Re-pair end devices in waves**
   - Start with routers, then sleepy end-devices (battery) last.
   - After re-pairing, verify `last_seen` and LQI in Zigbee2MQTT.
5) **Only after migration:** remove the legacy Zigbee2MQTT add-ons and delete legacy folders.

## Practical tips (helps with â€œdevices offlineâ€)
- Avoid placing the coordinator next to Wiâ€‘Fi APs, USB3 disks, metal racks, or electrical cabinets.
- Keep Zigbee channel away from your Wiâ€‘Fi channel (e.g., Wiâ€‘Fi 1/6/11 often pairs well with Zigbee 15/20/25, but measure your RF environment).
- Make sure the TCP bridge stays up after reboot (Tasmota): `Rule1 ON System#Boot DO TCPStart 8888 ENDON` + `Rule1 1`.


