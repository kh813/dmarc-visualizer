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
- **Convenient Management Script (`app.sh`)**: Start, stop, restart, check memory status, parse reports, and prune old data with single commands.

---

## Quick Start with `app.sh`

### 1. Configure Ports (Optional)
A `.env` file is provided. You can edit `.env` (or copy from `.env.example`) to change ports if needed:
```bash
# Port where Grafana Web UI will be accessible (default: 3001)
GRAFANA_PORT=3001

# Port where PostgreSQL will be exposed on host (default: 5433)
POSTGRES_PORT=5433
```

### 2. Start Services
```bash
./app.sh start
```

### 3. Parse DMARC Reports
Place your DMARC XML/zip/gz reports into the `files/` directory, then run:
```bash
./app.sh parse
```
`parsedmarc` will parse all files in `files/`, save records to PostgreSQL, and update Grafana.

### 4. Open Grafana Dashboard
Access Grafana at:
👉 **http://localhost:3001** (or your configured `GRAFANA_PORT`)
- Navigate to **Dashboards > DMARC Reports — PostgreSQL**

---

## Management Commands (`./app.sh`)

| Command | Description |
| :--- | :--- |
| `./app.sh start` | Start all services in the background |
| `./app.sh stop` | Stop all running services |
| `./app.sh restart` | Restart all services |
| `./app.sh status` | View container status and live memory/CPU usage |
| `./app.sh logs [service]` | Stream logs in real time (e.g. `./app.sh logs grafana`) |
| `./app.sh parse` | Parse all reports in `./files/` into the database |
| `./app.sh prune [days]` | Delete reports older than N days (default: 90 days) |
| `./app.sh clean-files` | Clear files from `./files/` and `./output_files/` |
| `./app.sh clean-all` | Purge all containers and all database volume data (factory reset) |
| `./app.sh psql` | Open an interactive `psql` shell into the database |
