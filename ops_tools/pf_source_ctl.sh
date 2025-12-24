#!/bin/bash
set -euo pipefail

# -------------------------------------------------------------------
# pf_source_ctl.sh
#
# Unified controller for PicFrame photo source selection.
# - Manages the frame_live symlink (path from config)
# - Reads available sources from config/frame_sources.conf
# - Restarts picframe.service when the source changes
#
# Usage:
#   pf_source_ctl.sh                 # Interactive mode (prompt with numbered options)
#   pf_source_ctl.sh list            # List sources (non-interactive)
#   pf_source_ctl.sh current         # Show current source
#   pf_source_ctl.sh set <source_id> # Switch to specific source
#
# Example:
#   pf_source_ctl.sh set gdt
#   pf_source_ctl.sh set kfr
# -------------------------------------------------------------------

# -------------------------------------------------------------------
# LOAD CONFIGURATION
# -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/config_loader.sh
source "${SCRIPT_DIR}/../lib/config_loader.sh"

if ! load_config; then
    echo "ERROR: Failed to load config. Run setup first." >&2
    exit 1
fi

# -------------------------------------------------------------------
# CONFIGURATION (from config file)
# -------------------------------------------------------------------
# APP_ROOT - loaded from config
# FRAME_SOURCES_CONF - derived in config_loader.sh
CONFIG_FILE="${FRAME_SOURCES_CONF}"
SYMLINK_PATH="${FRAME_LIVE_PATH:-/home/pi/Pictures/frame_live}"
PF_SERVICE_NAME="picframe.service"

# -------------------------------------------------------------------
# Safety: check allowed user/host from config
# -------------------------------------------------------------------
if ! check_allowed_context; then
    exit 1
fi

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------

usage() {
    cat <<EOF
Usage:
  $0                 # Interactive mode (numbered menu)
  $0 list            # List all sources from config and show which is active
  $0 current         # Show currently active source
  $0 set <source_id> # Switch frame_live symlink to the specified source and restart ${PF_SERVICE_NAME}

Examples:
  $0
  $0 list
  $0 current
  $0 set gdt
  $0 set kfr
EOF
    exit 1
}

log() {
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "${ts} pf_source_ctl.sh - $*"
}

ensure_config_exists() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log "ERROR: Config file not found: ${CONFIG_FILE}"
        exit 1
    fi
}

# Parse config and output: id|label|path|enabled  (one line per source)
# Skips comments and blank lines.
iterate_sources() {
    ensure_config_exists
    while IFS='|' read -r sid label path enabled || [[ -n "${sid:-}" ]]; do
        # Skip comments / blank lines
        [[ -z "${sid}" ]] && continue
        [[ "${sid}" =~ ^# ]] && continue
        echo "${sid}|${label}|${path}|${enabled}"
    done < "${CONFIG_FILE}"
}

# Get the canonical real path of the current symlink target (or empty if not a symlink)
get_current_target_path() {
    if [[ -L "${SYMLINK_PATH}" || -e "${SYMLINK_PATH}" ]]; then
        readlink -f "${SYMLINK_PATH}" || true
    else
        echo ""
    fi
}

# Restart picframe user service
restart_picframe_service() {
    log "Restarting ${PF_SERVICE_NAME} (user service)..."

    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

    if ! systemctl --user restart "${PF_SERVICE_NAME}"; then
        log "ERROR: Failed to restart ${PF_SERVICE_NAME} via systemctl --user."
        exit 1
    fi

    log "Service ${PF_SERVICE_NAME} restarted successfully."
}

# -------------------------------------------------------------------
# Command implementations
# -------------------------------------------------------------------

cmd_list() {
    local current_target
    current_target="$(get_current_target_path)"

    log "Available sources (from ${CONFIG_FILE}):"
    iterate_sources | while IFS='|' read -r sid label path enabled; do
        local status="DISABLED"
        [[ "${enabled}" == "1" ]] && status="ENABLED"

        local active=""
        if [[ -n "${current_target}" && "${current_target}" == "${path}" ]]; then
            active=" (ACTIVE)"
        fi

        echo "  - ${sid}: ${label}"
        echo "      path:    ${path}"
        echo "      enabled: ${status}${active}"
    done
}

cmd_current() {
    local current_target
    current_target="$(get_current_target_path)"

    if [[ -z "${current_target}" ]]; then
        log "No current source: ${SYMLINK_PATH} does not exist or is not a symlink."
        exit 1
    fi

    local found=0
    # Use process substitution instead of a pipe so 'found' is in the same shell
    while IFS='|' read -r sid label path enabled; do
        if [[ "${current_target}" == "${path}" ]]; then
            echo "Current source:"
            echo "  id:      ${sid}"
            echo "  label:   ${label}"
            echo "  path:    ${path}"
            echo "  enabled: ${enabled}"
            found=1
            break
        fi
    done < <(iterate_sources)

    if [[ "${found}" -eq 0 ]]; then
        echo "Current source path (not found in config):"
        echo "  path: ${current_target}"
    fi
}

cmd_set() {
    local target_id="${1:-}"

    if [[ -z "${target_id}" ]]; then
        log "ERROR: 'set' requires a <source_id> argument."
        usage
    fi

    ensure_config_exists

    local match_line=""
    while IFS='|' read -r sid label path enabled; do
        [[ -z "${sid}" ]] && continue
        [[ "${sid}" =~ ^# ]] && continue

        if [[ "${sid}" == "${target_id}" ]]; then
            match_line="${sid}|${label}|${path}|${enabled}"
            break
        fi
    done < "${CONFIG_FILE}"

    if [[ -z "${match_line}" ]]; then
        log "ERROR: Source id '${target_id}' not found in ${CONFIG_FILE}."
        exit 1
    fi

    IFS='|' read -r sid label path enabled <<< "${match_line}"

    if [[ "${enabled}" != "1" ]]; then
        log "ERROR: Source '${sid}' is disabled (enabled=${enabled})."
        exit 1
    fi

    if [[ ! -d "${path}" ]]; then
        log "ERROR: Target directory does not exist: ${path}"
        exit 1
    fi

    local current_target
    current_target="$(get_current_target_path)"

    if [[ -n "${current_target}" && "${current_target}" == "${path}" ]]; then
        log "Source '${sid}' is already active (symlink already points to ${path}). No change."
        return 0
    fi

    log "Switching frame source to '${sid}' (${label})"
    log "  New target path: ${path}"

    mkdir -p "$(dirname "${SYMLINK_PATH}")"

    ln -sfn "${path}" "${SYMLINK_PATH}"

    log "Updated symlink:"
    log "  ${SYMLINK_PATH} -> $(readlink -f "${SYMLINK_PATH}")"

    restart_picframe_service

    # Trigger immediate sync of the new source
    log "Triggering sync for new source..."
    local sync_script="${SCRIPT_DIR}/frame_sync.sh"
    if [[ -x "${sync_script}" ]]; then
        if bash "${sync_script}" >> "${LOG_DIR:-/home/pi/logs}/frame_sync_$(date +%Y-%m-%d).log" 2>&1; then
            log "Sync completed successfully for new source '${sid}'"
        else
            log "WARNING: Sync failed for new source '${sid}' - check logs"
        fi
    else
        log "WARNING: Sync script not found or not executable: ${sync_script}"
    fi

    log "Done."

    return 0
}

cmd_interactive() {
    log "Interactive source selection (numbered menu)."
    echo

    local current_target
    current_target="$(get_current_target_path)"

    # Collect sources into arrays so we can use numeric indexes
    local -a IDS=()
    local -a LABELS=()
    local -a PATHS=()
    local -a ENABLED=()

    while IFS='|' read -r sid label path enabled; do
        IDS+=("${sid}")
        LABELS+=("${label}")
        PATHS+=("${path}")
        ENABLED+=("${enabled}")
    done < <(iterate_sources)

    local count="${#IDS[@]}"
    if [[ "${count}" -eq 0 ]]; then
        log "ERROR: No sources defined in ${CONFIG_FILE}."
        exit 1
    fi

    # Figure out which index (if any) is currently active
    local current_idx=-1
    if [[ -n "${current_target}" ]]; then
        for i in "${!PATHS[@]}"; do
            if [[ "${current_target}" == "${PATHS[i]}" ]]; then
                current_idx="${i}"
                break
            fi
        done
    fi

    echo "Current selection:"
    if (( current_idx >= 0 )); then
        local cur_sid="${IDS[current_idx]}"
        local cur_label="${LABELS[current_idx]}"
        local cur_path="${PATHS[current_idx]}"

        echo "  ${cur_sid} - ${cur_label}"
        echo "    path: ${cur_path}"
    else
        if [[ -z "${current_target}" ]]; then
            echo "  none (frame_live not set)"
        else
            echo "  path: ${current_target} (not found in config)"
        fi
    fi
    echo

    echo "Available sources:"
    for i in "${!IDS[@]}"; do
        local idx=$((i + 1))
        local sid="${IDS[i]}"
        local label="${LABELS[i]}"
        local path="${PATHS[i]}"
        local enabled="${ENABLED[i]}"

        local active=""
        if [[ -n "${current_target}" && "${current_target}" == "${path}" ]]; then
            active=" (ACTIVE)"
        fi

        local status="DISABLED"
        [[ "${enabled}" == "1" ]] && status="ENABLED"

        echo "  ${idx}) ${sid} - ${label}${active}"
        echo "       path:    ${path}"
        echo "       enabled: ${status}"
    done
    echo

    while true; do
        read -rp "Select option [1-${count}] or 'c' to cancel: " choice

        if [[ -z "${choice}" ]]; then
            echo "No input. Please enter a number between 1 and ${count} or 'c' to cancel."
            continue
        fi

        case "${choice}" in
            c|C)
                log "Selection cancelled by user."
                return 0
                ;;
        esac

        # Must be integer between 1 and count
        if [[ "${choice}" =~ ^[0-9]+$ ]]; then
            local num_choice="${choice}"

            if (( num_choice < 1 || num_choice > count )); then
                echo "Invalid option. Please enter a number between 1 and ${count}, or 'c' to cancel."
                continue
            fi

            local idx=$((num_choice - 1))
            local sid="${IDS[idx]}"

            echo
            log "Attempting to switch to source '${sid}' (option ${num_choice})..."
            echo

            if cmd_set "${sid}"; then
                echo
                log "Interactive selection completed successfully."
                return 0
            else
                echo
                echo "Failed to switch to source '${sid}'. Please try again (or 'c' to cancel)."
                echo
            fi
        else
            echo "Invalid input. Please enter a number between 1 and ${count} or 'c' to cancel."
        fi
    done
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------

main() {
    local cmd="${1:-}"

    case "${cmd}" in
        "")   # No args -> interactive menu
            cmd_interactive
            ;;
        list)
            shift || true
            cmd_list
            ;;
        current)
            shift || true
            cmd_current
            ;;
        set)
            shift || true
            cmd_set "${1:-}"
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            log "ERROR: Unknown command '${cmd}'"
            usage
            ;;
    esac
}

main "$@"
