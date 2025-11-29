#!/bin/bash
set -euo pipefail
# t_chk_sync.sh
# Purpose: Quickly compare *current active* remote folder vs. local directory
# using file counts by default. Use --d for a detailed rclone check.
# When run in default (quick) mode, also shows a status summary via chk_status.sh.
#
# Detects the active source (Google vs Koofr) from frame_live symlink.

# -------------------------------------------------------------------
# TTY / ENV SAFETY
# -------------------------------------------------------------------
IS_TTY=0
if [[ -t 1 ]]; then
    IS_TTY=1
fi

# -------------------------------------------------------------------
# CONFIGURATION
# -------------------------------------------------------------------
FRAME_LIVE="/home/pi/Pictures/frame_live"

GDT_LOCAL="/home/pi/Pictures/gdt_frame"
KFR_LOCAL="/home/pi/Pictures/kfr_frame"

GDT_REMOTE="kfgdrive:dframe"
KFR_REMOTE="kfrphotos:KFR_kframe"

RCLONE_REMOTE="$GDT_REMOTE"
LOCAL_DIR="$GDT_LOCAL"
ACTIVE_SOURCE_ID="gdt"
ACTIVE_SOURCE_LABEL="gdt - Google Drive (gdt_frame)"

LOG_FILE="${LOG_FILE:-$HOME/logs/frame_sync.log}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_SCRIPT="$SCRIPT_DIR/chk_status.sh"

# -------------------------------------------------------------------
# SOURCE DETECTION
# -------------------------------------------------------------------
detect_active_source() {
    local target=""

    if [[ -L "$FRAME_LIVE" ]]; then
        target=$(readlink -f "$FRAME_LIVE" || true)
    fi

    case "$target" in
        "$GDT_LOCAL")
            ACTIVE_SOURCE_ID="gdt"
            ACTIVE_SOURCE_LABEL="gdt - Google Drive (gdt_frame)"
            RCLONE_REMOTE="$GDT_REMOTE"
            LOCAL_DIR="$GDT_LOCAL"
            ;;
        "$KFR_LOCAL")
            ACTIVE_SOURCE_ID="kfr"
            ACTIVE_SOURCE_LABEL="kfr - Koofr (kfr_frame)"
            RCLONE_REMOTE="$KFR_REMOTE"
            LOCAL_DIR="$KFR_LOCAL"
            ;;
        "")
            ACTIVE_SOURCE_ID="unknown"
            ACTIVE_SOURCE_LABEL="frame_live not found or not a symlink"
            ;;
        *)
            ACTIVE_SOURCE_ID="unknown"
            ACTIVE_SOURCE_LABEL="unknown source backing: $target"
            ;;
    esac
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
