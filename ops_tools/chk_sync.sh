#!/bin/bash
set -euo pipefail
# chk_sync.sh
# Purpose: Quickly compare *current active* remote folder vs. local directory
# using file counts by default. Use --d for a detailed rclone check.
# When run in default (quick) mode, also shows a status summary via chk_status.sh.
#
# Detects the active source dynamically from frame_live symlink and frame_sources.conf.

# -------------------------------------------------------------------
# SCRIPT SETUP
# -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------------------------------------------------------------------
# LOAD CONFIGURATION
# -------------------------------------------------------------------
# shellcheck source=../lib/config_loader.sh
source "${SCRIPT_DIR}/../lib/config_loader.sh"

if ! load_config; then
    echo "ERROR: Failed to load config. Run setup first." >&2
    exit 1
fi

# -------------------------------------------------------------------
# TTY / ENV SAFETY
# -------------------------------------------------------------------
IS_TTY=0
if [[ -t 1 ]]; then
    IS_TTY=1
fi

# -------------------------------------------------------------------
# CONFIGURATION (from config file)
# -------------------------------------------------------------------
FRAME_LIVE="${FRAME_LIVE_PATH:-/home/pi/Pictures/frame_live}"
STATUS_SCRIPT="$SCRIPT_DIR/chk_status.sh"

# These will be set by detect_active_source()
RCLONE_REMOTE=""
LOCAL_DIR=""
ACTIVE_SOURCE_ID=""
ACTIVE_SOURCE_LABEL=""

# -------------------------------------------------------------------
# SOURCE DETECTION (dynamic from frame_sources.conf)
# -------------------------------------------------------------------
detect_active_source() {
    local target=""
    local conf_file="${FRAME_SOURCES_CONF:-${APP_ROOT}/config/frame_sources.conf}"

    # Get the symlink target
    if [[ -L "$FRAME_LIVE" ]]; then
        target=$(readlink -f "$FRAME_LIVE" 2>/dev/null || true)
    fi

    if [[ -z "$target" ]]; then
        ACTIVE_SOURCE_ID="unknown"
        ACTIVE_SOURCE_LABEL="frame_live not found or not a symlink"
        return 1
    fi

    # Search frame_sources.conf for matching path
    if [[ -f "$conf_file" ]]; then
        while IFS='|' read -r sid label path enabled remote || [[ -n "$sid" ]]; do
            # Skip comments and empty lines
            [[ -z "$sid" || "$sid" =~ ^# ]] && continue

            if [[ "$target" == "$path" ]]; then
                ACTIVE_SOURCE_ID="$sid"
                ACTIVE_SOURCE_LABEL="$sid - $label"
                LOCAL_DIR="$path"
                # Use remote from config if available (5th field), otherwise use global RCLONE_REMOTE
                if [[ -n "${remote:-}" ]]; then
                    RCLONE_REMOTE="$remote"
                else
                    RCLONE_REMOTE="${RCLONE_REMOTE:-}"
                fi
                return 0
            fi
        done < "$conf_file"
    fi

    # No match found in config
    ACTIVE_SOURCE_ID="unknown"
    ACTIVE_SOURCE_LABEL="unknown source backing: $target"
    LOCAL_DIR="$target"
    return 1
}

# -------------------------------------------------------------------
# PRINT HELPERS
# -------------------------------------------------------------------
print_header() {
    if [[ "$IS_TTY" -eq 1 ]]; then
        clear
    fi

    echo
    echo "--------------------------------------------"
    echo "   Remote vs Local Directory Check"
    echo "--------------------------------------------"
    echo
    echo "Active source: $ACTIVE_SOURCE_LABEL"
    echo "  Source ID : $ACTIVE_SOURCE_ID"
    echo "  Remote    : $RCLONE_REMOTE"
    echo "  Local dir : $LOCAL_DIR"
    echo
    [[ "$IS_TTY" -eq 1 ]] \
        && echo -e "\e[33mTIP:\e[0m Run with \e[32m--d\e[0m for detailed mismatch report." \
        || echo "TIP: Run with --d for detailed mismatch report."
    echo
}

print_footer() {
    echo
    echo "--------------------------------------------"
    echo "End of Remote vs Local Directory Check"
    echo "--------------------------------------------"
}

# -------------------------------------------------------------------
# CHECK FUNCTIONS
# -------------------------------------------------------------------
quick_check() {
    echo "Performing quick file count comparison..."
    remote_count=$(rclone lsf "$RCLONE_REMOTE" --files-only | wc -l)
    local_count=$(find "$LOCAL_DIR" -type f | wc -l)

    echo "Remote file count: $remote_count"
    echo "Local  file count: $local_count"

    if [ "$remote_count" -eq "$local_count" ]; then
        echo "✅ Quick check: File counts match."
    else
        echo "⚠️ Quick check mismatch: remote=$remote_count local=$local_count"
    fi
}

detailed_check() {
    echo "Performing detailed rclone check (may take several minutes)..."
    set +e
    OUTPUT=$(rclone check "$RCLONE_REMOTE" "$LOCAL_DIR" 2>&1)
    RESULT=$?
    set -e

    echo "$OUTPUT" | grep -v -E "matching files|INFO  :" || true

    if echo "$OUTPUT" | grep -q "Failed to create file system"; then
        echo "❌ Rclone remote '$RCLONE_REMOTE' not found. Verify with:  rclone listremotes"
    elif [ $RESULT -eq 0 ]; then
        echo "✅ All files match between remote and local directory."
    else
        echo "⚠️ Differences detected — review logs or rerun with higher verbosity for details."
    fi
}

show_status_summary() {
    if [[ -x "$STATUS_SCRIPT" ]]; then
        "$STATUS_SCRIPT" "$LOG_FILE" || {
            echo "WARNING: chk_status.sh returned a non-zero exit code." >&2
        }
    else
        echo "NOTE: chk_status.sh not found or not executable at:" >&2
        echo "      $STATUS_SCRIPT" >&2
        echo "      Skipping status summary." >&2
    fi
}

# -------------------------------------------------------------------
# MAIN
# -------------------------------------------------------------------
detect_active_source
print_header

default_mode=true
if [[ "${1:-}" == "--d" ]]; then
    default_mode=false
fi

if $default_mode; then
    quick_check
    echo
    echo "===== Log status summary (via chk_status.sh) ====="
    echo
    show_status_summary
else
    detailed_check
fi

print_footer
