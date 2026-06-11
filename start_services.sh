#!/usr/bin/env bash
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

# ── Available services ─────────────────────────────────────────────────────────
# To add a new service: append the exact service name from docker-compose.yml
SERVICES=(
    "postgres"
    "redis"
    "n8n"
    "pgadmin"
)

COMPOSE_FILE="$(dirname "$0")/build/docker-compose.yml"
ENV_FILE="$(dirname "$0")/.env"

# ── Functions ─────────────────────────────────────────────────────────────────
print_header() {
    echo
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║      n8n + WhatsApp — Services       ║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${RESET}"
    echo
}

running_services() {
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps --services --filter status=running 2>/dev/null || true
}

print_menu() {
    local running
    running="$(running_services)"

    echo -e "${BOLD}Choose a service to start:${RESET}"
    echo

    local idx=1
    for svc in "${SERVICES[@]}"; do
        if echo "$running" | grep -qx "$svc"; then
            echo -e "  ${CYAN}${idx})${RESET} ${svc}  ${GREEN}● running${RESET}"
        else
            echo -e "  ${CYAN}${idx})${RESET} ${svc}  ${RED}● stopped${RESET}"
        fi
        (( idx++ ))
    done

    echo
    echo -e "  ${GREEN}a)${RESET} All services"
    echo -e "  ${RED}q)${RESET} Quit"
    echo
}

start_service() {
    local svc="$1"
    echo
    echo -e "${YELLOW}▶ Starting:${RESET} ${BOLD}${svc}${RESET}"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d "$svc"
    echo -e "${GREEN}✔ ${svc} started.${RESET}"
}

start_all() {
    echo
    echo -e "${YELLOW}▶ Starting all services...${RESET}"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
    echo -e "${GREEN}✔ All services started.${RESET}"
}

show_status() {
    echo
    echo -e "${BOLD}Current status:${RESET}"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
    echo
}

# ── Entry point ───────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo -e "${RED}Error: docker not found. Please install Docker before continuing.${RESET}"
    exit 1
fi

print_header

while true; do
    print_menu
    read -rp "$(echo -e "${BOLD}Option:${RESET} ")" choice
    echo

    case "$choice" in
        q|Q)
            echo -e "${CYAN}Exiting.${RESET}"
            exit 0
            ;;
        a|A)
            start_all
            show_status
            ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#SERVICES[@]} )); then
                start_service "${SERVICES[$((choice - 1))]}"
                show_status
            else
                echo -e "${RED}Invalid option. Please try again.${RESET}"
            fi
            ;;
    esac
done
