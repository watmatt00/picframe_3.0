#!/bin/bash
set -euo pipefail
# t_chk_sync.sh
# Purpose: Quickly compare Google Drive folder vs. local directory using file counts by default.
# Use --d for a detailed rclone check.

# -------------------------------------------------------------------
# CONFIGURATION
# -------------------------------------------------------------------
RCLONE_REMOTE="kfgdrive:dframe"
LOCAL_DIR="/home/pi/Pictures/gdt_frame"
RCLONE_OPTS="--one-way --log-level NOTICE"

# -------------------------------------------------------------------
# FUNCTIONS
# -------------------------------------------------------------------
print_header() {
    echo
    echo "--------------------------------------------"
    echo "   Google Drive vs Local Directory Check"
    echo "--------------------------------------------"
    echo
    echo -e "\e[33mTIP:\e[0m Run with \e[32m--d\e[0m for detailed mismatch report."
    echo
}

print_footer() {
    echo ""
    echo "--------------------------------------------"
    echo "End of Difference Report"
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

# -------------------------------------------------------------------
# MAIN SCRIPT
# -------------------------------------------------------------------
clear
print_header

default_mode=true
if [[ "${1:-}" == "--d" ]]; then
    default_mode=false
fi

if $default_mode; then
    quick_check
else
    detailed_check
fi

print_footer