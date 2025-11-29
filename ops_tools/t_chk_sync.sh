#!/bin/bash
set -euo pipefail
# t_chk_sync.sh
# Purpose: Quickly compare *current active* remote folder vs. local directory
# using file counts by default. Use --d for a detailed rclone check.
# When run in default (quick) mode, also shows a status summary via chk_status.sh.
#
# This version detects the active source (Google vs Koofr) based on the
# frame_live symlink and adjusts REMOTE + LOCAL_DIR automatically.

# -------------------------------------------------------------------
# TTY / ENV SAFETY
# -------------------------------------------------------------------
# IS_TTY=1 when stdout is a real terminal, 0 otherwise (e.g. systemd / Flask)
IS_TTY=0
if [[ -t 1 ]]; then
    IS_TTY=1
fi

# -------------------------------------------------------------------
# CONFIGURATION (STATIC PATHS + REMOTES)
# -------------------------------------------------------------------
# Symlink PicFrame always reads from
FRAME_LIVE="/home/pi/Pictures/frame_live"

# Concrete local backing folders
GDT_LOCAL="/home/pi/Pictures/gdt_frame"
KFR_LOCAL="/home/pi/Pictures/kfr_frame"

# Rclone remotes for each source
GDT_REMOTE="kfgdrive:dframe"
KFR_REMOTE="kfrphotos:KFR_kframe"

# Defaults (if detection fails, fall back to Google)
RCLONE_REMOTE="$GDT_REMOTE"
LOCAL_DIR="$GDT_LOCAL"
ACTIVE_SOURCE_ID="gdt"
ACTIVE_SOURCE_LABEL="gdt - Google Drive (gdt_frame)"

# Log file used by chk_status.sh
LOG_FILE="${LOG_FILE:-$HOME/logs/frame_sync.log}"

# Locate chk_status.sh in the same directory as this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_SCRIPT="$SCRIPT_DIR/chk_status.sh"

# -------------------------------------------------------------------
# SOURCE DETECTION
# -------------------------------------------------------------------
detect_active_source() {
    local target=""

    if [[ -L "$FRAME_LIVE" ]]; then
        # Resolve final target (handles nested symlinks if any)
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
            # Keep defaults (Google) as a safe fallback
            ;;
        *)
            ACTIVE_SOURCE_ID="unknown"
            ACTIVE_SOURCE_LABEL="unknown source backing: $target"
            # Keep defaults (Google) as a safe fallback
            ;;
    esac
}

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
    echo "   Remote vs Local Directory Check"
    echo "--------------------------------------------"
    echo
    echo "Active source: $ACTIVE_SOURCE_LABEL"
    echo "  Source ID : $ACTIVE_SOURCE_ID"
    echo "  Remote    : $RCLONE_REMOTE"
    echo "  Local dir : $LOCAL_DIR"
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
    echo "
