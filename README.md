# dmarc-visualizer

Analyse and visualize DMARC results using lightweight, modern open-source tools.

- **[parsedmarc](https://github.com/domainaware/parsedmarc)** for parsing DMARC and SMTP-TLS reports.
- **[PostgreSQL](https://www.postgresql.org/)** for lightweight, persistent data storage (replaces Elasticsearch for minimal RAM usage and zero Java dependencies).
- **[Grafana](https://grafana.com/)** for dashboards and visual reporting.

---

## Features

- **Ultra-lightweight & Low Memory**: Uses PostgreSQL (`postgres:16-alpine`), consuming less than 100 MB RAM in total (over 90% reduction compared to Elasticsearch). No Java/JVM required.
- **Side-by-side Testing**: Ports and database credentials are fully configurable via `.env` (defaults to Grafana on port `3001` and PostgreSQL on port `5433` so you can test alongside existing services without port conflicts).
- **Official Dashboard Included**: Pre-configured with the official Grafana 10/11 DMARC dashboard for PostgreSQL.
- **Auto-adapts Legacy Configs**: You can directly copy your existing `parsedmarc.ini` — legacy `[elasticsearch]` sections are automatically disabled, and PostgreSQL connections are configured seamlessly.
- **Convenient Management Script (`app.sh`)**: Start, stop, restart, check memory status, parse reports, and prune old data with single commands.

---

## Quick Start

### 1. Start Services
```bash
./app.sh start
```
By default, this will spin up PostgreSQL (port `5433`) and Grafana (port `3001`).

### 2. Parse DMARC Reports
Place your DMARC XML/zip/gz reports into the `files/` directory, then run:
```bash
./app.sh parse
```
`parsedmarc` will parse all files in `files/`, save records to PostgreSQL, and update Grafana.

### 3. Open Grafana Dashboard
Access Grafana in your web browser at:
👉 **http://localhost:3001** (or your configured `GRAFANA_PORT`)
- Navigate to **Dashboards > DMARC Reports — PostgreSQL**

---

## Configuration

### Environment Variables (`.env`)
Configuration is managed via `.env`. A template is provided in `.env.example`:

```bash
# Grafana Web UI Port (Default: 3001 to prevent conflicts with legacy 3000)
# ------------------------------------------------------------------------------
# Access Control & Port Settings
# ------------------------------------------------------------------------------
# IP Address to bind Grafana Web UI
# - "127.0.0.1" (Default): Accessible ONLY from this local machine (loopback).
#                          Completely blocks external LAN, WAN, and direct container access.
# - "192.168.x.x"        : Accessible only from your specific local LAN IP.
# - "0.0.0.0"            : Accessible from all network interfaces (LAN + Host IP).
GRAFANA_BIND_IP=127.0.0.1
GRAFANA_PORT=3001

POSTGRES_BIND_IP=127.0.0.1
POSTGRES_PORT=5433

# PostgreSQL Database Credentials
POSTGRES_DB=dmarc
POSTGRES_USER=parsedmarc
POSTGRES_PASSWORD=parsedmarc_password

# Grafana Admin Credentials
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin

# ------------------------------------------------------------------------------
# Cloudflare Tunnel Integration (Optional)
# ------------------------------------------------------------------------------
# Public URL when accessed via Cloudflare Tunnel or reverse proxy (e.g. https://dmarc.example.com)
# GRAFANA_ROOT_URL=https://dmarc.example.com

# If your cloudflared container runs in Docker, specify its external Docker network name:
# CLOUDFLARE_TUNNEL_NETWORK=cloudflared_net
```

---

## Network & Access Control (Local-only vs Cloudflare Tunnel)

You can easily configure whether this visualizer is strictly isolated to your local machine, or securely accessible via Cloudflare Tunnel.

### Option A: Strict Local-Only Access (Default)
In `.env`:
```bash
GRAFANA_BIND_IP=127.0.0.1
```
- **How it works:** Grafana and PostgreSQL bind strictly to the loopback interface (`127.0.0.1`).
- **Security:** External devices on your local network (LAN) and other isolated Docker containers (including `cloudflared`) **cannot** access the web UI directly via the host's LAN IP.
- Only users sitting at the host machine or using SSH port forwarding can access `http://127.0.0.1:3001`.

### Option B: Access via Cloudflare Tunnel (Recommended Method: Docker Shared Network)
If `cloudflared` is running as a Docker container, you can route directly through Docker's internal network **without opening any host ports to the LAN or internet**.

1. In `.env`, set your Cloudflare Tunnel Docker network and your public domain:
   ```bash
   CLOUDFLARE_TUNNEL_NETWORK=my_tunnel_network
   GRAFANA_ROOT_URL=https://dmarc.example.com
   ```
2. Restart services:
   ```bash
   ./app.sh restart
   ```
   `app.sh` automatically attaches Grafana to your tunnel network.
3. In your Cloudflare Zero Trust Dashboard (or `config.yml`), add an ingress rule routing to the internal container address:
   ```yaml
   ingress:
     - hostname: dmarc.example.com
       service: http://grafana:3000
   ```
   *Notice you connect to port `3000` via internal Docker DNS `grafana`, while `GRAFANA_BIND_IP=127.0.0.1` stays secure on the host!*

### Option C: Access via Cloudflare Tunnel (Host Networking Method)
If your `cloudflared` container connects to host ports or runs on bare metal:
1. In `.env`:
   ```bash
   GRAFANA_BIND_IP=0.0.0.0
   GRAFANA_ROOT_URL=https://dmarc.example.com
   ```
2. In Cloudflare Tunnel ingress rules:
   ```yaml
   ingress:
     - hostname: dmarc.example.com
       service: http://host.docker.internal:3001
   ```

### Custom `parsedmarc.ini` (Optional)
If you do not provide a `parsedmarc.ini`, one will be automatically generated from your `.env` settings.

If you need advanced settings (such as **automated IMAP email fetching**), place your `parsedmarc.ini` in `parsedmarc/parsedmarc.ini`.

```ini
[general]
save_aggregate = True
save_forensic = True
output = /output/

# Optional: Fetch DMARC reports automatically from an IMAP mailbox
[imap]
host = imap.example.com
user = dmarc@example.com
password = your-imap-password
ssl = True
watch = True
delete = False
```

> **Note:** You do not need to configure `[postgresql]` inside `parsedmarc.ini`. The startup script will automatically append the PostgreSQL settings from `.env`.

---

## Management Script (`./app.sh`)

`app.sh` is a wrapper script designed to simplify everyday operations and maintenance.

### Commands Reference

| Command | Description |
| :--- | :--- |
| **`./app.sh start`** (or `up`) | Starts PostgreSQL and Grafana containers in the background. |
| **`./app.sh stop`** (or `down`) | Stops all running containers. |
| **`./app.sh restart`** | Restarts all services. |
| **`./app.sh status`** (or `ps`) | Displays container status and real-time RAM/CPU resource consumption. |
| **`./app.sh logs [service]`** | Follows container logs in real time (e.g., `./app.sh logs grafana`). |
| **`./app.sh parse`** | Parses all DMARC reports in `./files/` into the database. |
| **`./app.sh prune [days]`** | Prunes reports older than N days (default: 90 days) from the database. |
| **`./app.sh clean-files`** | Clears temporary files from `./files/` and `./output_files/`. |
| **`./app.sh clean-all`** | Completely purges containers and database volumes (factory reset). |
| **`./app.sh psql`** | Opens an interactive `psql` command-line shell to the PostgreSQL database. |

### Periodic Execution (Cron)
To automatically process new reports placed into `files/` or periodically fetch from IMAP:
```bash
# Process incoming reports every hour
0 * * * * cd /path/to/dmarc-visualizer && ./app.sh parse >/dev/null 2>&1
```

---

## Migration Guide (From Legacy DMARC Visualizer)

If you are currently running the older Elasticsearch-based `dmarc-visualizer`, follow this guide to migrate safely with zero downtime.

### Q: Will copying my old `parsedmarc.ini` work directly?
**Yes, you can copy it directly.**
- The startup entrypoint automatically detects legacy `[elasticsearch]` sections and disables them so they won't cause connection errors.
- It automatically appends the new `[postgresql]` connection settings from `.env`.
- Any custom `[general]`, `[imap]`, or `[mailbox]` settings from your old config will be completely preserved.

---

### Step-by-Step Migration

#### Step 1: Deploy Side-by-Side (Keep Legacy Running)
Do not stop your old DMARC Visualizer yet. Clone or place this repository in a separate directory:
```bash
git clone https://github.com/kh813/dmarc-visualizer.git dmarc-visualizer-new
cd dmarc-visualizer-new
```
Because this stack defaults to **Grafana Port `3001`** and **PostgreSQL Port `5433`**, it will not conflict with your existing setup running on port `3000`.

#### Step 2: Copy Your Existing Configuration
Copy your old `parsedmarc.ini` into `parsedmarc/`:
```bash
cp /path/to/old/dmarc-visualizer/parsedmarc/parsedmarc.ini parsedmarc/parsedmarc.ini
```

#### Step 3: Start the New Stack
```bash
./app.sh start
```
Check that the containers are healthy:
```bash
./app.sh status
```

#### Step 4: Import Historical Reports
If you saved your old XML/zip/gz report files, copy them into the `files/` directory:
```bash
cp /path/to/old/dmarc-visualizer/files/* files/
./app.sh parse
```
`parsedmarc` will parse all historical files and index them into PostgreSQL.

#### Step 5: Verify in Grafana
Open **http://localhost:3001** in your browser.
Open **Dashboards > DMARC Reports — PostgreSQL** and verify your domain data and statistics appear accurately.

#### Step 6: Retire the Legacy Stack
Once you have confirmed that the new stack works as expected:

1. Stop the legacy stack:
   ```bash
   cd /path/to/old/dmarc-visualizer
   docker compose down -v  # Frees up several gigabytes of Elasticsearch memory & storage
   ```
2. (Optional) Switch the new stack to port `3000`:
   Edit `.env` in the new stack directory:
   ```bash
   GRAFANA_PORT=3000
   ```
   Apply changes:
   ```bash
   ./app.sh restart
   ```
   The new lightweight visualizer is now serving on **http://localhost:3000**!
