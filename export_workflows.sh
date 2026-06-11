#!/usr/bin/env bash
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

CONTAINER="n8n"
BACKUP_DIR="$(dirname "$0")/build/n8n/workflows_backup"
REDACT_SCRIPT="$(dirname "$0")/build/n8n/redact_workflow.js"

CONTAINER_EXPORT_DIR="/tmp/workflows_export"
CONTAINER_REDACTED_DIR="/tmp/workflows_redacted"
CONTAINER_REDACT_SCRIPT="/tmp/redact_workflow.js"

STAGING_DIR="$(mktemp -d)"

print_header() {
    echo
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║      n8n — Export Workflows          ║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${RESET}"
    echo
}

print_usage() {
    echo -e "${BOLD}Usage:${RESET} ./export_workflows.sh [--all | --active]"
    echo
    echo "  --all     Export every workflow, including archived ones"
    echo "  --active  Export only workflows that are not archived"
    echo
    echo -e "${BOLD}Example:${RESET}"
    echo "  ./export_workflows.sh --all"
    echo
}

cleanup() {
    rm -rf "$STAGING_DIR"
    docker exec "$CONTAINER" rm -rf "$CONTAINER_EXPORT_DIR" "$CONTAINER_REDACTED_DIR" "$CONTAINER_REDACT_SCRIPT" 2>/dev/null || true
}
trap cleanup EXIT

print_header

# ── Parse arguments ───────────────────────────────────────────────────────────
if [[ $# -ne 1 ]]; then
    print_usage
    exit 1
fi

case "$1" in
    --all)
        ONLY_ACTIVE=false
        ;;
    --active)
        ONLY_ACTIVE=true
        ;;
    *)
        print_usage
        exit 1
        ;;
esac

# ── Entry point ───────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo -e "${RED}Error: docker not found. Please install Docker before continuing.${RESET}"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo -e "${RED}Error: jq not found. Install it with 'sudo apt install jq' (or your package manager) before continuing.${RESET}"
    exit 1
fi

if [[ ! -f "$REDACT_SCRIPT" ]]; then
    echo -e "${RED}Error: redaction script not found at ${REDACT_SCRIPT}${RESET}"
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo -e "${RED}Error: the '${CONTAINER}' container is not running.${RESET}"
    echo -e "Start it first with ${BOLD}./start_services.sh${RESET}"
    exit 1
fi

echo -e "${YELLOW}▶ Exporting workflows from n8n...${RESET}"
docker exec "$CONTAINER" rm -rf "$CONTAINER_EXPORT_DIR" "$CONTAINER_REDACTED_DIR"
docker exec "$CONTAINER" n8n export:workflow --all --separate --output="$CONTAINER_EXPORT_DIR"

echo -e "${YELLOW}▶ Masking sensitive values inside the n8n container...${RESET}"
docker cp "$REDACT_SCRIPT" "${CONTAINER}:${CONTAINER_REDACT_SCRIPT}"
report_json="$(docker exec "$CONTAINER" node "$CONTAINER_REDACT_SCRIPT" "$CONTAINER_EXPORT_DIR" "$CONTAINER_REDACTED_DIR")"

docker cp "${CONTAINER}:${CONTAINER_REDACTED_DIR}/." "$STAGING_DIR"

echo -e "${YELLOW}▶ Saving workflows to build/n8n/workflows_backup...${RESET}"
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

count=0
skipped=0
while IFS= read -r entry; do
    is_archived="$(echo "$entry" | jq -r '.isArchived')"

    if [[ "$ONLY_ACTIVE" == true && "$is_archived" == true ]]; then
        skipped=$((skipped + 1))
        continue
    fi

    file="$(echo "$entry" | jq -r '.file')"
    name="$(echo "$entry" | jq -r '.name')"
    id="$(echo "$entry" | jq -r '.id')"

    # Replace characters that are invalid in filenames on Linux/Mac/Windows
    safe_name="$(echo "$name" | sed -e 's@[/\\:*?"<>|]@-@g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    dest="$BACKUP_DIR/${safe_name}.json"
    if [[ -e "$dest" ]]; then
        # Avoid overwriting when two workflows share the same name
        dest="$BACKUP_DIR/${safe_name} (${id}).json"
    fi

    cp "$STAGING_DIR/$file" "$dest"

    redacted_keys="$(echo "$entry" | jq -r '.redactedKeys[]')"
    pattern_matches="$(echo "$entry" | jq -r '.patternMatches')"

    if [[ -n "$redacted_keys" || "$pattern_matches" -gt 0 ]]; then
        echo -e "${YELLOW}  ⚠ Masked sensitive value(s) in '$(basename "$dest")':${RESET}"
        while IFS= read -r key; do
            [[ -n "$key" ]] && echo "      - $key"
        done <<< "$redacted_keys"
        if [[ "$pattern_matches" -gt 0 ]]; then
            echo "      - ${pattern_matches} additional value(s) matched known secret formats"
        fi
    fi

    count=$((count + 1))
done < <(echo "$report_json" | jq -c '.[]')

echo -e "${GREEN}✔ Exported ${count} workflow(s) to build/n8n/workflows_backup/${RESET}"
if [[ "$skipped" -gt 0 ]]; then
    echo -e "  (skipped ${skipped} archived workflow(s))"
fi
echo
echo -e "${BOLD}Note:${RESET} masked values are replaced with *******. Before re-importing a workflow,"
echo "open its JSON file and fill in the real value for each masked field listed above."
echo
