#!/bin/bash
#
# t_chk_sync.sh — Verify sync state between Google Drive and local photo folder
# This script checks for count differences and (optionally) lists file mismatches.
#
# Usage:
#   ./t_chk_sync.sh       → Summary only
#   ./t_chk_sync.sh --d   → Detailed difference report using rclone check
#

set -euo pipefail

# -------------------------------------------------------------------
# CONFIGURATION
# -------------------------------------------------------------------
RCLONE_REMOTE="kfgdrive:dframe"
LDIR="$HOME/Pictures/gdt_frame"
PATH=/usr/local/bin:/usr/bin:/bin

# -------------------------------------------------------------------
# FUNCTIONS
# -------------------------------------------------------------------

get_directory_count() {
    local dir_type="$1"
    local count=0
    if [ "$dir_type" = "google" ]; then
        count=$(rclone lsf "$RCLONE_REMOTE" --files-only | wc -l)
    elif [ "$dir_type" = "local" ]; then
        count=$(find "$LDIR" -type f | wc -l)
    else
        echo "ERROR: Invalid directory type '$dir_type'" >&2
        exit 1
    fi
    echo "$count"
}

show_details() {
    echo
    echo "--------------------------------------------"
    echo -e "\e[36m   Detailed Sync Difference Report\e[0m"
    echo "--------------------------------------------"
    echo
    echo "Comparing Google Drive vs Local Directory..."
    echo "(This may take a minute for large collections)"
    echo

    # Show actual file differences and mismatches
    rclone check "$RCLONE_REMOTE" "$LDIR" --one-way --size-only --verbose

    echo
    echo "--------------------------------------------"
    echo -e "\e[36mEnd of Difference Report\e[0m"
    echo "--------------------------------------------"
    echo
}

# -------------------------------------------------------------------
# MAIN SCRIPT
# -------------------------------------------------------------------

clear
echo
echo "--------------------------------------------"
echo "   Google Drive vs Local Directory Check"
echo "--------------------------------------------"
echo
echo -e "\e[33mTIP:\e[0m Run with \e[32m--d\e[0m for detailed mismatch report."
echo

# Ensure local directory exists
if [ ! -d "$LDIR" ]; then
    echo "ERROR: Local directory '$LDIR' not found."
    exit 1
fi

# Get counts
gdir_count=$(get_directory_count "google")
ldir_count=$(get_directory_count "local")

echo "Google Drive file count : $gdir_count"
echo "Local directory file count : $ldir_count"
echo

# Compare counts
if [ "$gdir_count" -eq "$ldir_count" ]; then
    echo -e "\e[32m✅ Directories are in sync.\e[0m"
else
    echo -e "\e[31m❌ Directories are NOT in sync.\e[0m"
fi

# Optional detailed comparison
if [ "${1:-}" = "--d" ]; then
    show_details
else
    echo
fi

exit 0



