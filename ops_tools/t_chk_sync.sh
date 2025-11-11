#!/bin/bash
set -euo pipefail
# t_chk_sync.sh
# Purpose: Compare Google Drive folder vs. local directory and report differences clearly
# This script checks for differences but does not modify or log results.

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
    echo "--------------------------------------------"
    echo "   Detailed Sync Difference Report"
    echo "--------------------------------------------"
    echo ""
    echo "Comparing Google Drive vs Local Directory..."
    echo "(This may take a minute for large collections)"
    echo ""
}

print_footer() {
    echo ""
    echo "--------------------------------------------"
    echo "End of Difference Report"
    echo "--------------------------------------------"
}

# -------------------------------------------------------------------
# MAIN SCRIPT
# -------------------------------------------------------------------
clear
print_header

# Run comparison and suppress redundant output lines while preserving rclone's exit code
set +e
OUTPUT=$(rclone check "$RCLONE_REMOTE" "$LOCAL_DIR" $RCLONE_OPTS 2>&1)
RESULT=$?
set -e

# Print filtered output (hide redundant “matching files” and “INFO” lines)
echo "$OUTPUT" | grep -v -E "matching files|INFO  :" || true

# Handle known outcomes
if echo "$OUTPUT" | grep -q "Failed to create file system"; then
    echo "❌ Rclone remote '$RCLONE_REMOTE' not found. Verify with:  rclone listremotes"
elif [ $RESULT -eq 0 ]; then
    echo "✅ All files match between remote and local directory."
else
    echo "⚠️ Differences detected — review logs or rerun with higher verbosity for details."
fi

print_footer
