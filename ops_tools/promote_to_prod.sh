#!/bin/bash
set -euo pipefail

# -------------------------------------------------------------------
# promote_to_prod.sh
# Run on DEV PC (not on Pi) to:
#   1. Archive current prod scripts with timestamp
#   2. Copy test scripts (t_*.sh) to prod names
#   3. Remove executable bit from archived files
#   4. Ensure prod and test scripts are executable
#   5. Commit + tag + push
#
# Logging: All promotion messages go to the main app log (frame_sync.log)
# -------------------------------------------------------------------

REPO_ROOT="$HOME/Downloads/GitHub/picframe_3.0"
OPS_DIR="$REPO_ROOT/ops_tools"
ARCHIVE_DIR="$OPS_DIR/archive"
LOG_FILE="$HOME/logs/frame_sync.log"
mkdir -p "$HOME/logs"

TIMESTAMP="$(date '+%Y%m%d-%H%M')"

# Safety: never run on the Pi
HOSTNAME="$(hostname)"
if [[ "$HOSTNAME" == "kframe" ]]; then
    echo "ERROR: Do NOT run promote_to_prod.sh on the Pi." | tee -a "$LOG_FILE" >&2
    exit 1
fi

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') promote_to_prod.sh - $1" | tee -a "$LOG_FILE" >&2
}

log_message "=== Starting promotion to production on PC ==="

# Ensure archive directory exists
mkdir -p "$ARCHIVE_DIR"

# Prod scripts we manage
PROD_FILES=(
    "chk_sync.sh"
    "frame_sync.sh"
)

# Test versions
TEST_FILES=(
    "t_chk_sync.sh"
    "t_frame_sync.sh"
)

# -------------------------------------------------------------------
# 1. Archive current prod scripts
# -------------------------------------------------------------------
log_message "Archiving current prod files..."

for i in "${!PROD_FILES[@]}"; do
    PROD="${OPS_DIR}/${PROD_FILES[$i]}"
    ARCHIVE="${ARCHIVE_DIR}/${PROD_FILES[$i]%.*}_${TIMESTAMP}.sh"

    if [[ -f "$PROD" ]]; then
        # Use install to copy with known safe permissions (644)
        install -m 644 "$PROD" "$ARCHIVE"
        log_message "Archived $PROD → $ARCHIVE"
    else
        log_message "WARNING: Prod file missing: $PROD"
    fi
done

# -------------------------------------------------------------------
# 2. Copy test scripts to prod scripts
# -------------------------------------------------------------------
log_message "Promoting test scripts to production..."

for i in "${!TEST_FILES[@]}"; do
    TEST="${OPS_DIR}/${TEST_FILES[$i]}"
    PROD="${OPS_DIR}/${PROD_FILES[$i]}"

    if [[ ! -f "$TEST" ]]; then
        log_message "ERROR: Missing test script: $TEST"
        exit 1
    fi

    # Copy and set executable bit
    install -m 755 "$TEST" "$PROD"
    log_message "Promoted $TEST → $PROD"
done

# -------------------------------------------------------------------
# 3. Ensure archive files are NOT executable
# -------------------------------------------------------------------
log_message "Removing executable bit from all archived scripts..."

find "$ARCHIVE_DIR" -type f -name "*.sh" -exec chmod 644 {} \;

# -------------------------------------------------------------------
# 4. Ensure prod + test scripts ARE executable
# -------------------------------------------------------------------
log_message "Ensuring all prod/test scripts are executable..."

find "$OPS_DIR" -maxdepth 1 -type f -name "*.sh" -exec chmod 755 {} \;

# This intentionally *does not* recurse into archive

# -------------------------------------------------------------------
# 5. Commit + tag + push
# -------------------------------------------------------------------
cd "$REPO_ROOT"

log_message "Committing changes to Git..."

git add .
git commit -m "Promote to prod: $TIMESTAMP"
git tag "prod-$TIMESTAMP"
git push
git push --tags

log_message "=== Promotion completed successfully ==="
