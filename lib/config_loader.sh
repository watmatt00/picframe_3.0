#!/bin/bash
# ============================================
# lib/config_loader.sh
# Shared config loading for all PicFrame scripts
# ============================================
#
# Usage in scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/../lib/config_loader.sh"
#   load_config || exit 1
#
# ============================================

# Default config location (can be overridden via environment)
PICFRAME_CONFIG="${PICFRAME_CONFIG:-$HOME/.picframe/config}"

# -------------------------------------------------------------------
# load_config
# Load configuration from the config file
# Returns 0 on success, 1 on failure
# -------------------------------------------------------------------
load_config() {
    if [[ ! -f "$PICFRAME_CONFIG" ]]; then
        echo "ERROR: Config file not found at $PICFRAME_CONFIG" >&2
        echo "" >&2
        echo "To set up PicFrame:" >&2
        echo "  1. Open the web dashboard at http://$(hostname -I | awk '{print $1}'):5050" >&2
        echo "  2. Complete the setup wizard" >&2
        echo "" >&2
        echo "Or configure manually:" >&2
        echo "  mkdir -p ~/.picframe" >&2
        echo "  cp \$(dirname \$0)/../config/config.example ~/.picframe/config" >&2
        echo "  nano ~/.picframe/config" >&2
        return 1
    fi

    # Source the config file
    # shellcheck source=/dev/null
    source "$PICFRAME_CONFIG"

    # Set derived paths (these depend on config values)
    LOG_FILE="${LOG_DIR:-$HOME/logs}/frame_sync.log"
    FRAME_SOURCES_CONF="${APP_ROOT:-$HOME/picframe_3.0}/config/frame_sources.conf"

    return 0
}

# -------------------------------------------------------------------
# validate_config
# Validate that required config values are set
# Returns 0 if valid, number of errors otherwise
# -------------------------------------------------------------------
validate_config() {
    local errors=0

    # Check required values
    if [[ -z "${RCLONE_REMOTE:-}" ]]; then
        echo "ERROR: RCLONE_REMOTE is not set in config" >&2
        ((errors++))
    fi

    if [[ -z "${LOCAL_DIR:-}" ]]; then
        echo "ERROR: LOCAL_DIR is not set in config" >&2
        ((errors++))
    fi

    if [[ -z "${APP_ROOT:-}" ]]; then
        echo "ERROR: APP_ROOT is not set in config" >&2
        ((errors++))
    fi

    return $errors
}

# -------------------------------------------------------------------
# check_allowed_context
# Verify we're running as the allowed user on the allowed host
# Returns 0 if allowed, 1 if not
# -------------------------------------------------------------------
check_allowed_context() {
    local current_host current_user

    current_host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")"
    current_user="$(id -un 2>/dev/null || echo "unknown")"

    # Check hostname if ALLOWED_HOST is set
    if [[ -n "${ALLOWED_HOST:-}" && "$current_host" != "$ALLOWED_HOST" ]]; then
        echo "ERROR: This script must be run on host '$ALLOWED_HOST'" >&2
        echo "       Current host: '$current_host'" >&2
        return 1
    fi

    # Check user if ALLOWED_USER is set
    if [[ -n "${ALLOWED_USER:-}" && "$current_user" != "$ALLOWED_USER" ]]; then
        echo "ERROR: This script must be run as user '$ALLOWED_USER'" >&2
        echo "       Current user: '$current_user'" >&2
        return 1
    fi

    return 0
}

# -------------------------------------------------------------------
# get_source_info
# Parse frame_sources.conf and return info for a given source ID
# Usage: get_source_info <source_id> <field>
#   field: label, path, enabled, or remote (if 5th field exists)
# -------------------------------------------------------------------
get_source_info() {
    local source_id="$1"
    local field="$2"
    local conf_file="${FRAME_SOURCES_CONF:-}"

    if [[ ! -f "$conf_file" ]]; then
        echo ""
        return 1
    fi

    while IFS='|' read -r sid label path enabled remote || [[ -n "$sid" ]]; do
        # Skip comments and empty lines
        [[ -z "$sid" || "$sid" =~ ^# ]] && continue

        if [[ "$sid" == "$source_id" ]]; then
            case "$field" in
                label)   echo "$label" ;;
                path)    echo "$path" ;;
                enabled) echo "$enabled" ;;
                remote)  echo "${remote:-}" ;;
                *)       echo "" ;;
            esac
            return 0
        fi
    done < "$conf_file"

    echo ""
    return 1
}

# -------------------------------------------------------------------
# get_active_source_from_symlink
# Determine which source is active by checking where frame_live points
# Returns the source ID, or empty string if not found
# -------------------------------------------------------------------
get_active_source_from_symlink() {
    local frame_live="${FRAME_LIVE_PATH:-/home/pi/Pictures/frame_live}"
    local conf_file="${FRAME_SOURCES_CONF:-}"
    local current_target=""

    # Get the real path of the symlink
    if [[ -L "$frame_live" ]]; then
        current_target="$(readlink -f "$frame_live" 2>/dev/null || true)"
    fi

    if [[ -z "$current_target" || ! -f "$conf_file" ]]; then
        echo ""
        return 1
    fi

    # Find which source matches this path
    while IFS='|' read -r sid label path enabled remote || [[ -n "$sid" ]]; do
        [[ -z "$sid" || "$sid" =~ ^# ]] && continue

        if [[ "$current_target" == "$path" ]]; then
            echo "$sid"
            return 0
        fi
    done < "$conf_file"

    echo ""
    return 1
}
