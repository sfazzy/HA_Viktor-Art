# Grafana + InfluxDB (Home Assistant) quick start

## What you already have
- Home Assistant writes states to InfluxDB (`configuration.yaml` -> `influxdb:`).
- InfluxDB is reachable at `http://192.168.2.108:8086`.

## How Home Assistant data looks in InfluxDB (typical)
- Measurement: `state` (because `default_measurement: state`)
- Field: `value`
- Tags: `entity_id`, `domain` (and sometimes `friendly_name`, `unit_of_measurement`, … depending on integration/config)

In your database, many numeric sensors are stored under their **unit** as the measurement name:
- Power: `W`
- Energy: `kWh`
- Apparent power: `VA`
- Power factor: often ends up in `state` (no unit), not `%`
- Current: `A` (but only if the entity is enabled in HA)

## InfluxQL examples (Grafana panel queries)
Replace `sensor.some_entity` with your real entity id.

### Time-series (average)
```sql
SELECT mean("value")
FROM "state"
WHERE ("entity_id" = 'sensor.some_entity') AND $timeFilter
GROUP BY time($__interval) fill(null)
```

### Time-series (last value each interval)
```sql
SELECT last("value")
FROM "state"
WHERE ("entity_id" = 'sensor.some_entity') AND $timeFilter
GROUP BY time($__interval) fill(null)
```

### Multiple entities at once (regex)
```sql
SELECT mean("value")
FROM "state"
WHERE ("entity_id" =~ /^sensor\\.shelly_3em_.*_power$/) AND $timeFilter
GROUP BY time($__interval), "entity_id" fill(null)
```

## Importable dashboard (template)
Import `docs/grafana-shelly3em-dashboard.json` in Grafana.
- When importing, select your InfluxDB datasource.
- Then edit the `entity_id` variables to match your Shelly 3EM entities.
