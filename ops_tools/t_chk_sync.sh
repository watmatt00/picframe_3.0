#!/bin/bash
set -euo pipefail
# t_chk_sync.sh
# Purpose: Compare Google Drive folder vs. local directory and report differences clearly

# --------------------------------------------
# Configuration
# --------------------------------------------
LOCAL_DIR="/home/pi/Pictures/gdt_frame"
REMOTE_DIR="gdrive:gdt_frame"
RCLONE_OPTS="--one-way --log-level NOTICE"

# --------------------------------------------
# Functions
# --------------------------------------------
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

# --------------------------------------------
# Main Script
# --------------------------------------------
clear
print_header

# Run comparison and suppress redundant output lines
set +e  # temporarily disable exit-on-error for grep handling
rclone check "$REMOTE_DIR" "$LOCAL_DIR" $RCLONE_OPTS 2>&1 | \
    grep -v -E "matching files|INFO  :" || true
RESULT=${PIPESTATUS[0]}
set -e  # re-enable strict mode

# Display summary
if [ $RESULT -eq 0 ]; then
    echo "✅ All files match between Google Drive and Local Directory."
else
    echo "⚠️ Differences detected — review logs or rerun with higher verbosity for details."
fi

print_footer
