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

# Load environment variables
if [ -f .env ]; then
    # shellcheck disable=SC2046
    export $(grep -v '^#' .env | xargs)
fi

POSTGRES_DB="${POSTGRES_DB:-dmarc}"
POSTGRES_USER="${POSTGRES_USER:-parsedmarc}"
GRAFANA_PORT="${GRAFANA_PORT:-3001}"
POSTGRES_PORT="${POSTGRES_PORT:-5433}"

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

print_header() {
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}         DMARC Visualizer Management Script           ${NC}"
    echo -e "${CYAN}======================================================${NC}"
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
    echo -e "  ${GREEN}prune [days]${NC}       Delete reports older than [days] (default: 90 days)"
    echo -e "  ${GREEN}clean-files${NC}        Delete temporary files from ./files/ and ./output_files/"
    echo -e "  ${GREEN}clean-all${NC}          Destroy all containers and purge all database volume data"
    echo -e "  ${GREEN}psql${NC}               Open an interactive PostgreSQL terminal session"
    echo -e "  ${GREEN}help${NC}               Show this help message"
    echo ""
}

cmd_start() {
    echo -e "${BLUE}[*] Starting DMARC Visualizer services...${NC}"
    mkdir -p files output_files
    docker compose up -d
    echo -e "${GREEN}[✔] Services started successfully!${NC}"
    echo -e "${CYAN}👉 Grafana Dashboard: ${GREEN}http://localhost:${GRAFANA_PORT}${NC}"
    echo -e "${CYAN}👉 PostgreSQL Port:   ${GREEN}${POSTGRES_PORT}${NC}"
}

cmd_stop() {
    echo -e "${BLUE}[*] Stopping DMARC Visualizer services...${NC}"
    docker compose down
    echo -e "${GREEN}[✔] Services stopped.${NC}"
}

cmd_restart() {
    echo -e "${BLUE}[*] Restarting DMARC Visualizer services...${NC}"
    docker compose restart
    echo -e "${GREEN}[✔] Services restarted!${NC}"
    echo -e "${CYAN}👉 Grafana Dashboard: ${GREEN}http://localhost:${GRAFANA_PORT}${NC}"
}

cmd_status() {
    print_header
    echo -e "${BLUE}[*] Container Status:${NC}"
    docker compose ps
    echo ""
    echo -e "${BLUE}[*] Memory & CPU Resource Usage:${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" \
        $(docker compose ps -q) 2>/dev/null || echo "No running containers found."
    echo ""
    echo -e "${CYAN}👉 Grafana Dashboard: ${GREEN}http://localhost:${GRAFANA_PORT}${NC}"
}

cmd_logs() {
    local service="$1"
    if [ -n "$service" ]; then
        echo -e "${BLUE}[*] Streaming logs for ${service}...${NC}"
        docker compose logs -f "$service"
    else
        echo -e "${BLUE}[*] Streaming logs for all services...${NC}"
        docker compose logs -f
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
    docker compose run --rm parsedmarc
    echo -e "${GREEN}[✔] Parsing complete! Check updated reports at: http://localhost:${GRAFANA_PORT}${NC}"
}

cmd_prune() {
    local days="${1:-90}"
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[✗] Error: Days parameter must be an integer.${NC}"
        exit 1
    fi

    echo -e "${YELLOW}[!] Pruning reports older than ${days} days...${NC}"
    read -rp "Are you sure you want to delete reports older than ${days} days from PostgreSQL? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[yY]([eE][sS])?$ ]]; then
        echo -e "${BLUE}[*] Cancelled.${NC}"
        exit 0
    fi

    # Execute deletion in PostgreSQL using CASCADE
    docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<EOF
BEGIN;
DELETE FROM dmarc_aggregate_report WHERE end_date < NOW() - INTERVAL '${days} days';
DELETE FROM dmarc_failure_report WHERE arrival_date_utc < NOW() - INTERVAL '${days} days';
DELETE FROM smtp_tls_report WHERE end_date < NOW() - INTERVAL '${days} days';
COMMIT;
EOF
    echo -e "${GREEN}[✔] Old reports older than ${days} days successfully pruned!${NC}"
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
        docker compose down -v
        echo -e "${GREEN}[✔] Database and containers have been completely purged.${NC}"
    else
        echo -e "${BLUE}[*] Cancelled.${NC}"
    fi
}

cmd_psql() {
    echo -e "${BLUE}[*] Connecting to PostgreSQL CLI (type '\\q' to exit)...${NC}"
    docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
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
