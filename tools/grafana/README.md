# Grafana automation (push dashboards)

This repo stores Grafana dashboards as JSON files in `docs/`.

Use `tools/grafana/push-dashboards.ps1` to update dashboards in Grafana via the HTTP API.

## 1) Create a Grafana API token
In Grafana:
- Administration -> Users and access -> Service accounts (or API keys)
- Create a token with **Editor** or **Admin** permissions

## 2) Run the script
## 2a) Save token locally (recommended)
Store the token encrypted (DPAPI, current Windows user) so you don't need to export `GRAFANA_TOKEN` each time:

```powershell
.\tools\grafana\set-token.ps1
```

This writes `tools/grafana/.token.secure` (ignored by git).

PowerShell example (recommended: use env var so you don't paste the token into history):

```powershell
$env:GRAFANA_TOKEN = 'PASTE_TOKEN_HERE'
.\tools\grafana\push-dashboards.ps1 -GrafanaUrl 'https://192.168.2.108:3000' -InsecureTls
```

If your Grafana datasource is not named `InfluxDB`, pass:
```powershell
.\tools\grafana\push-dashboards.ps1 -DatasourceName 'homeassistant'
```

## Notes (Home Assistant ingress)
Your Grafana appears to be behind Home Assistant ingress on `https://192.168.2.108:3000` and redirects to `/api/hassio_ingress/...`.
The script auto-detects that and uses the correct base path.



## Kiosk URLs (Weintek HMI)
After Grafana is reachable directly on LAN (NOT via Home Assistant ingress), list kiosk URLs:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\grafana\list-kiosk-urls.ps1 -GrafanaUrl 'http://192.168.2.108:3001'
```

If Grafana anonymous viewing is enabled, `list-kiosk-urls.ps1` works without a token.

## Zigbee2MQTT ultimate dashboard

- Import `docs/grafana-z2m-ultimate.json` from this repo (or run `.\tools\grafana\push-dashboards.ps1 -GrafanaUrl 'http://192.168.2.108:3001'` to push it automatically).  
- Once imported, the dashboard is reachable at `http://192.168.2.108:3001/d/z2m-ultimate/zigbee2mqtt-ultimate?orgId=1`.  
- Embed that dashboard in Lovelace via a `panel_iframe` (or an iframe card) pointing to the URL above to keep the Z2M overview inside HA without using the broken ingress link, or click the Grafana tab you already added to access it full screen.

