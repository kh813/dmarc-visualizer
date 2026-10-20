#!/usr/bin/env bash
# ==============================================================================
# DMARC Visualizer Management Wrapper Script (app.sh)
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for friendly output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Ensure .env exists
if [ ! -f .env ] && [ -f .env.example ]; then
    echo -e "${YELLOW}[!] .env file not found. Creating from .env.example...${NC}"
    cp .env.example .env
fi

# Auto-detect parsedmarc.ini in root directory and copy to parsedmarc/
if [ -f parsedmarc.ini ] && [ ! -f parsedmarc/parsedmarc.ini ]; then
    echo -e "${YELLOW}[!] Found parsedmarc.ini in project root. Copying to parsedmarc/parsedmarc.ini...${NC}"
    cp parsedmarc.ini parsedmarc/parsedmarc.ini
fi

# Load environment variables
if [ -f .env ]; then
    # shellcheck disable=SC2046
    export $(grep -v '^#' .env | xargs)
fi

POSTGRES_DB="${POSTGRES_DB:-dmarc}"
POSTGRES_USER="${POSTGRES_USER:-parsedmarc}"
GRAFANA_BIND_IP="${GRAFANA_BIND_IP:-0.0.0.0}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
POSTGRES_BIND_IP="${POSTGRES_BIND_IP:-127.0.0.1}"
POSTGRES_PORT="${POSTGRES_PORT:-5433}"
GRAFANA_ROOT_URL="${GRAFANA_ROOT_URL:-http://localhost:${GRAFANA_PORT}}"

# Build Docker Compose arguments
COMPOSE_ARGS=("-f" "docker-compose.yml")
if [ -n "$CLOUDFLARE_TUNNEL_NETWORK" ]; then
    COMPOSE_ARGS+=("-f" "docker-compose.tunnel.yml")
fi

dc() {
    docker compose "${COMPOSE_ARGS[@]}" "$@"
}

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

print_header() {
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}         DMARC Visualizer Management Script           ${NC}"
    echo -e "${CYAN}======================================================${NC}"
}

print_network_info() {
    if [ "$GRAFANA_BIND_IP" == "0.0.0.0" ]; then
        echo -e "${CYAN}👉 Web Access (Grafana):   ${GREEN}Accessible from LAN & local host (http://<LAN-IP>:${GRAFANA_PORT} or http://localhost:${GRAFANA_PORT})${NC}"
    elif [ "$GRAFANA_BIND_IP" == "127.0.0.1" ]; then
        echo -e "${CYAN}👉 Web Access (Grafana):   ${YELLOW}Local host only (http://127.0.0.1:${GRAFANA_PORT}) — LAN blocked${NC}"
    else
        echo -e "${CYAN}👉 Web Access (Grafana):   ${GREEN}Bound to http://${GRAFANA_BIND_IP}:${GRAFANA_PORT}${NC}"
    fi

    echo -e "${CYAN}👉 DB Access (PostgreSQL): ${GREEN}Internal-only (No host ports exposed — 100% isolated to Docker network)${NC}"

    if [ -n "$CLOUDFLARE_TUNNEL_NETWORK" ]; then
        echo -e "${CYAN}👉 Cloudflare Tunnel:       ${GREEN}Connected to Docker network '${CLOUDFLARE_TUNNEL_NETWORK}'${NC}"
        echo -e "${CYAN}   - Internal URL:          ${GREEN}http://grafana:3000${NC}"
        if [ "$GRAFANA_ROOT_URL" != "http://localhost:${GRAFANA_PORT}" ]; then
            echo -e "${CYAN}   - Public URL:            ${GREEN}${GRAFANA_ROOT_URL}${NC}"
        fi
    fi
}

usage() {
    print_header
    echo -e "Usage: ${GREEN}./app.sh [command]${NC}\n"
    echo -e "Commands:"
    echo -e "  ${GREEN}start | up${NC}         Start all services in background"
    echo -e "  ${GREEN}stop | down${NC}        Stop all running services"
    echo -e "  ${GREEN}restart${NC}            Restart all services"
    echo -e "  ${GREEN}status | ps${NC}        Show service status and resource (RAM) usage"
    echo -e "  ${GREEN}logs [service]${NC}     View service logs in real time (e.g. ./app.sh logs grafana)"
    echo -e "  ${GREEN}parse${NC}              Parse all report files in ./files/ into PostgreSQL"
    echo -e "  ${GREEN}prune [days] [-y]${NC}  Delete reports older than [days] (default: 90 days, -y for cron)"
    echo -e "  ${GREEN}clean-files${NC}        Delete temporary files from ./files/ and ./output_files/"
    echo -e "  ${GREEN}clean-all${NC}          Destroy all containers and purge all database volume data"
    echo -e "  ${GREEN}psql${NC}               Open an interactive PostgreSQL terminal session"
    echo -e "  ${GREEN}help${NC}               Show this help message"
    echo ""
}

check_port_conflict() {
    local port="$1"
    local our_grafana_id
    our_grafana_id=$(dc ps -q grafana 2>/dev/null || true)

    # 1. Check if another Docker container is publishing this port
    local docker_matches
    docker_matches=$(docker ps --no-trunc --filter "publish=${port}" --format '{{.ID}} {{.Names}} ({{.Image}})' 2>/dev/null || true)

    local our_grafana_using_port=false
    local conflicting_docker=""

    if [ -n "$docker_matches" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local cid
            cid=$(echo "$line" | awk '{print $1}')
            if [ -n "$our_grafana_id" ] && [ "$cid" == "$our_grafana_id" ]; then
                our_grafana_using_port=true
            else
                conflicting_docker="${conflicting_docker}${line}"$'\n'
            fi
        done <<< "$docker_matches"
    fi

    local conflict_found=false
    local conflict_detail=""

    if [ -n "$conflicting_docker" ]; then
        conflict_found=true
        conflict_detail=$(echo "$conflicting_docker" | sed '/^$/d' | awk '{names[NR]=$2 " " $3} END {for(i=1;i<=NR;i++) printf "%s%s", names[i], (i<NR?", ":"")}')
    elif [ "$our_grafana_using_port" = false ]; then
        # Our Grafana is not using this port, check if a host process or another service is listening
        local host_proc=""
        if command -v lsof >/dev/null 2>&1; then
            host_proc=$(lsof -iTCP:"${port}" -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR>1 {print $1, "(PID: " $2 ")"}' | head -n 1 || true)
        elif command -v ss >/dev/null 2>&1; then
            host_proc=$(ss -tulpn "sport = :${port}" 2>/dev/null | awk 'NR>1 {print $0}' | head -n 1 || true)
        elif command -v nc >/dev/null 2>&1; then
            if nc -z 127.0.0.1 "${port}" 2>/dev/null; then
                host_proc="Active service on port ${port}"
            fi
        fi

        if [ -n "$host_proc" ]; then
            conflict_found=true
            conflict_detail="$host_proc"
        fi
    fi

    if [ "$conflict_found" = true ]; then
        echo -e "${RED}========================================================================${NC}"
        echo -e "${RED}[✗] ポート競合エラー: ポート ${port} は既に使用されています${NC}"
        echo -e "${RED}    Port Conflict: Port ${port} is already in use!${NC}"
        echo -e "${RED}========================================================================${NC}"
        echo -e "${YELLOW}Grafanaに割り当てようとしたポート ${port} は、以下のプロセス/コンテナで使用中です:${NC}"
        echo -e "  👉 ${CYAN}${conflict_detail}${NC}\n"
        echo -e "${YELLOW}原因 (Cause):${NC}"
        echo -e "  旧バージョンのDMARC Visualizer、別のGrafana、またはホスト上の他のWebアプリが"
        echo -e "  既にポート ${port} をリッスンしています。\n"
        echo -e "${YELLOW}解決方法 (Resolution):${NC}"
        echo -e "  1. 競合しているコンテナまたはプロセスを停止する"
        echo -e "     (Stop the conflicting container or process)"
        echo -e "  2. または、${GREEN}.env${NC} 内でGrafanaのポートを空いている番号に変更する:"
        echo -e "     ${GREEN}GRAFANA_PORT=3001${NC}  (または他の空きポート)\n"
        echo -e "${RED}[!] Docker Composeの起動を中断しました。ポートを確認の上、再度実行してください。${NC}"
        exit 1
    fi
}

cmd_start() {
    check_port_conflict "$GRAFANA_PORT"
    echo -e "${BLUE}[*] Starting DMARC Visualizer services...${NC}"
    mkdir -p files output_files
    dc up -d
    echo -e "${GREEN}[✔] Services started successfully!${NC}"
    print_network_info
}

cmd_stop() {
    echo -e "${BLUE}[*] Stopping DMARC Visualizer services...${NC}"
    dc down
    echo -e "${GREEN}[✔] Services stopped.${NC}"
}

cmd_restart() {
    check_port_conflict "$GRAFANA_PORT"
    echo -e "${BLUE}[*] Restarting DMARC Visualizer services...${NC}"
    dc restart
    echo -e "${GREEN}[✔] Services restarted!${NC}"
    print_network_info
}

cmd_status() {
    print_header
    echo -e "${BLUE}[*] Container Status:${NC}"
    dc ps
    echo ""
    echo -e "${BLUE}[*] Memory & CPU Resource Usage:${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" \
        $(dc ps -q) 2>/dev/null || echo "No running containers found."
    echo ""
    print_network_info
}

cmd_logs() {
    local service="$1"
    if [ -n "$service" ]; then
        echo -e "${BLUE}[*] Streaming logs for ${service}...${NC}"
        dc logs -f "$service"
    else
        echo -e "${BLUE}[*] Streaming logs for all services...${NC}"
        dc logs -f
    fi
}

cmd_parse() {
    echo -e "${BLUE}[*] Parsing DMARC reports in ./files/...${NC}"
    mkdir -p files output_files
    file_count=$(find files/ -type f ! -name ".*" | wc -l | tr -d ' ')
    if [ "$file_count" -eq 0 ]; then
        echo -e "${YELLOW}[!] Warning: No report files found in ./files/.${NC}"
        echo -e "${YELLOW}    Please place .xml, .zip, or .gz files in ./files/ first.${NC}"
    fi
    dc run --rm parsedmarc
    echo -e "${GREEN}[✔] Parsing complete! Check updated reports at: http://${GRAFANA_BIND_IP}:${GRAFANA_PORT}${NC}"
}

cmd_prune() {
    local days="90"
    local auto_confirm=false

    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes|-f|--force)
                auto_confirm=true
                shift
                ;;
            *)
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    days="$1"
                else
                    echo -e "${RED}[✗] Error: Invalid argument '$1'. Expected number of days or -y/--yes.${NC}"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # If stdin is not a terminal (e.g., cron job), auto confirm
    if [ ! -t 0 ]; then
        auto_confirm=true
    fi

    echo -e "${YELLOW}[!] Pruning reports older than ${days} days...${NC}"
    if [ "$auto_confirm" != "true" ]; then
        read -rp "Are you sure you want to delete reports older than ${days} days from PostgreSQL? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[yY]([eE][sS])?$ ]]; then
            echo -e "${BLUE}[*] Cancelled.${NC}"
            exit 0
        fi
    fi

    # Execute deletion in PostgreSQL using CASCADE
    dc exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<EOF
BEGIN;
DELETE FROM dmarc_aggregate_report WHERE end_date < NOW() - INTERVAL '${days} days';
DELETE FROM dmarc_failure_report WHERE arrival_date_utc < NOW() - INTERVAL '${days} days';
DELETE FROM smtp_tls_report WHERE end_date < NOW() - INTERVAL '${days} days';
COMMIT;
EOF
    echo -e "${GREEN}[✔] Reports older than ${days} days successfully pruned!${NC}"
}

cmd_clean_files() {
    echo -e "${YELLOW}[!] Cleaning ./files/ and ./output_files/...${NC}"
    read -rp "Delete all files in ./files/ and ./output_files/? [y/N]: " confirm
    if [[ "$confirm" =~ ^[yY]([eE][sS])?$ ]]; then
        rm -rf files/* output_files/*
        echo -e "${GREEN}[✔] Files cleaned.${NC}"
    else
        echo -e "${BLUE}[*] Cancelled.${NC}"
    fi
}

cmd_clean_all() {
    echo -e "${RED}[!] WARNING: This will completely delete all containers AND all database volumes (all parsed data will be lost)!${NC}"
    read -rp "Are you ABSOLUTELY sure? Type 'yes' to proceed: " confirm
    if [ "$confirm" == "yes" ]; then
        echo -e "${BLUE}[*] Removing all containers and volumes...${NC}"
        dc down -v
        echo -e "${GREEN}[✔] Database and containers have been completely purged.${NC}"
    else
        echo -e "${BLUE}[*] Cancelled.${NC}"
    fi
}

cmd_psql() {
    echo -e "${BLUE}[*] Connecting to PostgreSQL CLI (type '\\q' to exit)...${NC}"
    dc exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
}

# ------------------------------------------------------------------------------
# Command Dispatcher
# ------------------------------------------------------------------------------

case "$1" in
    start|up)
        cmd_start
        ;;
    stop|down)
        cmd_stop
        ;;
    restart)
        cmd_restart
        ;;
    status|ps)
        cmd_status
        ;;
    logs)
        shift
        cmd_logs "$@"
        ;;
    parse|run)
        cmd_parse
        ;;
    prune)
        shift
        cmd_prune "$@"
        ;;
    clean-files)
        cmd_clean_files
        ;;
    clean-all)
        cmd_clean_all
        ;;
    psql)
        cmd_psql
        ;;
    help|--help|-h|"")
        usage
        ;;
    *)
        echo -e "${RED}[✗] Unknown command: $1${NC}\n"
        usage
        exit 1
        ;;
esac
