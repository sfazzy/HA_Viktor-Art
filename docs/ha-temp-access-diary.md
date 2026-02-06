# Temporary SSH access diary (Home Assistant Supervised on Debian/RPi)

This document records the exact steps used to grant short‑lived SSH access for troubleshooting/config changes, and how to remove that access afterwards.

## 1) Create a temporary SSH user

Run on the HA Debian host (as `root` or via existing admin access):

- Create user:
  - `sudo adduser ha-temp`
- Create SSH folder:
  - `sudo mkdir -p /home/ha-temp/.ssh`
  - `sudo chmod 700 /home/ha-temp/.ssh`
  - `sudo chown -R ha-temp:ha-temp /home/ha-temp/.ssh`

## 2) Add public key(s)

- Add the public key(s) into:
  - `/home/ha-temp/.ssh/authorized_keys`
- Permissions:
  - `sudo chmod 600 /home/ha-temp/.ssh/authorized_keys`
  - `sudo chown ha-temp:ha-temp /home/ha-temp/.ssh/authorized_keys`

Verify login from a LAN machine:

- `ssh -i ~/.ssh/<your_key> ha-temp@192.168.2.108`

## 3) Minimal sudo rights (what was granted)

We used `/etc/sudoers.d/` drop-ins so we can remove them cleanly.

Create (or edit) a file such as:

- `/etc/sudoers.d/ha-temp`

Example contents (edit as needed):

```
Defaults:ha-temp !requiretty

# Allow controlling add-ons/services via HA CLI wrapper (uses docker exec under the hood)
ha-temp ALL=(ALL) NOPASSWD: /usr/bin/ha

# WARNING: granting docker is effectively root access (containers + mounts).
# Only do this for very short-lived sessions.
ha-temp ALL=(ALL) NOPASSWD: /usr/bin/docker
```

Validate sudoers syntax before exiting editor:

- `sudo visudo -c`

## 4) Notes about HA Supervised specifics (why this was needed)

- `/usr/bin/ha` is a thin wrapper: it runs `docker exec hassio_cli ha ...`.
- Many add-on settings can only be changed via the Supervisor API.
- `ha --log-level debug ...` prints the Supervisor API token in logs (sensitive). Avoid using debug unless you are on a trusted console and you understand the risk.

## 5) Cleanup (remove access after the session)

On the HA Debian host:

- Remove the sudoers drop-in:
  - `sudo rm -f /etc/sudoers.d/ha-temp`
  - `sudo visudo -c`
- Remove the SSH key(s):
  - `sudo nano /home/ha-temp/.ssh/authorized_keys` (delete the lines you added)
- Remove the temporary user (optional):
  - `sudo deluser --remove-home ha-temp`

## 6) Grafana LAN exposure (for HMI) – what was changed

Problem:
- The Grafana add-on was still being advertised in Supervisor (Server Controls → Grafana) via the ingress tunnel, so clicking it landed on `…/api/hassio_ingress/...` and triggered the “failed to load its application files” warning.

Solution used:
- Disable the Grafana add-on so Supervisor no longer renders that broken sidebar entry.
- Run Grafana as a plain Docker container (`grafana_custom`) that only answers on the proxy port (`http://192.168.2.108:3001`), using the same database directory and plugins from the add-on.

What’s running on the host now:

- Docker container: `grafana_custom` exposing `3001/tcp`
- Data directory: `/var/lib/homeassistant/addons/data/a0d7b954_grafana`
- Environment (re-create with):

  ```bash
  sudo docker run -d --name grafana_custom --restart unless-stopped \
    -p 3001:3000 \
    -v /var/lib/homeassistant/addons/data/a0d7b954_grafana:/var/lib/grafana \
    -e GF_SECURITY_ALLOW_EMBEDDING=true \
    -e GF_AUTH_ANONYMOUS_ENABLED=true \
    -e GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer \
    -e GF_SERVER_ROOT_URL=http://192.168.2.108:3001/ \
    -e GF_SERVER_SERVE_FROM_SUB_PATH=false \
    -e GF_SECURITY_CSRF_TRUSTED_ORIGINS=http://192.168.2.108:3001 \
    grafana/grafana:12.3.0
  ```

How to remove it later:

- `sudo docker rm -f grafana_custom`
- The same data directory can be re-used when you run the container again.

## 7) Easy re-create

- Use `tools/grafana/run-grafana-custom.ps1` (the PowerShell script accepts port/path overrides) or rerun the `docker run …` command above.

Grafana add-on:

- Uninstalled via `ha addons uninstall a0d7b954_grafana`, which removes the Server Controls shortcut (the persistence data was preserved and reused by the custom container).
 
 ## 8) Grafana admin login
 
 - Reset the Grafana admin password inside the running container whenever you need to log in:
 
   ```bash
   sudo docker exec grafana_custom grafana-cli admin reset-admin-password 'GrafanaReset123!'
   ```

 - After that command completes, open `http://192.168.2.108:3001/login` and use:
 
   - User: `admin`
   - Password: `GrafanaReset123!` (change it once you’re logged in).
