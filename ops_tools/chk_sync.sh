#!/bin/bash
set -euo pipefail
# chk_sync.sh / t_chk_sync.sh
# Purpose: Quickly compare Google Drive folder vs. local directory using file counts by default.
# Use --d for a detailed rclone check.
# When run in default (quick) mode, also shows a status summary via chk_status.sh.

# -------------------------------------------------------------------
# TTY / ENV SAFETY
# -------------------------------------------------------------------
# IS_TTY=1 when stdout is a real terminal, 0 otherwise (e.g. systemd / Flask)
IS_TTY=0
if [[ -t 1 ]]; then
    IS_TTY=1
fi

# -------------------------------------------------------------------
# CONFIGURATION 
# -------------------------------------------------------------------
RCLONE_REMOTE="kfgdrive:dframe"
LOCAL_DIR="/home/pi/Pictures/gdt_frame"
RCLONE_OPTS="--one-way --log-level NOTICE"

# Log file used by chk_status.sh
LOG_FILE="${LOG_FILE:-$HOME/logs/frame_sync.log}"

# Locate chk_status.sh in the same directory as this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_SCRIPT="$SCRIPT_DIR/chk_status.sh"

# -------------------------------------------------------------------
# FUNCTIONS
# -------------------------------------------------------------------
print_header() {
    # Only clear the screen if we have a real terminal
    if [[ "$IS_TTY" -eq 1 ]]; then
        clear
    fi

    echo
    echo "--------------------------------------------"
    echo "   Google Drive vs Local Directory Check"
    echo "--------------------------------------------"
    echo

    if [[ "$IS_TTY" -eq 1 ]]; then
        # Colored tip when running interactively
        echo -e "\e[33mTIP:\e[0m Run with \e[32m--d\e[0m for detailed mismatch report."
    else
        # Plain text tip when running non-interactively (e.g. from web UI)
        echo "TIP: Run with --d for detailed mismatch report."
    fi

    echo
}

print_footer() {
    echo
    echo "--------------------------------------------"
    echo "End of Google Drive vs Local Directory Check"
    echo "--------------------------------------------"
}

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
    OUTPUT=$(rclone check "$RCLONE_REMOTE" "$LOCAL_DIR" $RCLONE_OPTS 2>&1)
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
# MAIN SCRIPT
# -------------------------------------------------------------------
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
