#!/bin/bash
set -euo pipefail

# -------------------------------------------------------------------
# promote_to_prod.sh
# Run on DEV PC (not on Pi) to:
#   - Safely promote test scripts (t_*.sh) to production names
#   - Archive selected prod files and prune old archives
#   - Commit repo state, create git tag, and push to GitHub
#
# Pi stays read-only: it will only ever pull these changes via
# update_picframe.sh and never commit/tag/push.
# -------------------------------------------------------------------

REPO_ROOT="$HOME/Downloads/GitHub/picframe_3.0"
OPS_DIR="$REPO_ROOT/ops_tools"
ARCHIVE_DIR="$OPS_DIR/archive"
LOG_FILE="$HOME/logs/frame_sync.log"

# Safety: never run this on the Pi (kframe)
HOSTNAME="$(hostname)"
if [[ "$HOSTNAME" == "kframe" ]]; then
    echo "ERROR: promote_to_prod.sh must NOT be run on Pi (kframe)."
    echo "       Run this script on your PC repo only."
    exit 1
fi

# Scripts that should be archived & pruned
ARCHIVE_LIST=("chk_sync.sh" "frame_sync.sh")

log_message() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [PROMOTE] $msg" | tee -a "$LOG_FILE"
}

cd "$REPO_ROOT" || { echo "Cannot cd to $REPO_ROOT"; exit 1; }
mkdir -p "$ARCHIVE_DIR"

log_message "=== Starting promotion to production (PC) ==="

TIMESTAMP=$(date '+%Y%m%d-%H%M')

# -------------------------------------------------------------------
# SAFETY: Pre-pull to prevent divergence issues
# -------------------------------------------------------------------
log_message "Checking for remote changes..."
git pull --rebase --autostash || {
    log_message "ERROR: Unable to sync with remote repo. Aborting promotion."
    exit 1
}

# -------------------------------------------------------------------
# PREVIEW OF ACTIONS
# -------------------------------------------------------------------
echo
echo "The following promotions will occur:"
echo

# 1. Archive actions
echo "Archive + prune for:"
for SCRIPT in "${ARCHIVE_LIST[@]}"; do
    echo "  - $SCRIPT → archive with timestamp $TIMESTAMP (keep latest 10)"
done
echo

# 2. Promotion actions
echo "Test → Prod promotions:"
for TFILE in "$OPS_DIR"/t_*.sh; do
    [ -f "$TFILE" ] || continue
    BASE=$(basename "$TFILE" | sed 's/^t_//')
    echo "  - $(basename "$TFILE") → $BASE"
done
echo

# -------------------------------------------------------------------
# Step 1: Archive + prune selected files
# -------------------------------------------------------------------
for SCRIPT in "${ARCHIVE_LIST[@]}"; do
    SRC="$OPS_DIR/$SCRIPT"
    if [ -f "$SRC" ]; then
        DEST="$ARCHIVE_DIR/${SCRIPT%.sh}_$TIMESTAMP.sh"
        cp "$SRC" "$DEST"
        chmod 644 "$DEST"
        log_message "Archived $SCRIPT → archive/${SCRIPT%.sh}_$TIMESTAMP.sh"

        FILE_PATTERN="${SCRIPT%.sh}_*.sh"
        FILES=($(ls -1t "$ARCHIVE_DIR"/$FILE_PATTERN 2>/dev/null || true))

        if [ "${#FILES[@]}" -gt 10 ]; then
            for ((i=10; i<${#FILES[@]}; i++)); do
                rm -f "${FILES[$i]}"
                log_message "Pruned old archive: $(basename "${FILES[$i]}")"
            done
        fi
    else
        log_message "WARNING: $SCRIPT missing — skipping archive"
    fi
done

# -------------------------------------------------------------------
# Step 2: Promote test → prod (copy, keep test files)
# -------------------------------------------------------------------
for TFILE in "$OPS_DIR"/t_*.sh; do
    [ -f "$TFILE" ] || continue
    BASE=$(basename "$TFILE" | sed 's/^t_//')

    cp "$TFILE" "$OPS_DIR/$BASE"
    chmod +x "$OPS_DIR/$BASE"

    log_message "Promoted (copied) $TFILE → $BASE (test preserved)"
done

# -------------------------------------------------------------------
# Step 3: Git commit repo state
# -------------------------------------------------------------------
git add -A
git commit -m "Production promotion on $(date '+%Y-%m-%d %H:%M')" || \
    log_message "No changes to commit (clean repo)"
log_message "Git commit complete"

# -------------------------------------------------------------------
# Step 4: Git tag
# -------------------------------------------------------------------
TAG="prod-$TIMESTAMP"
git tag -a "$TAG" -m "Promotion on $(date)"
log_message "Created tag: $TAG"

# -------------------------------------------------------------------
# Step 5: Push
# -------------------------------------------------------------------
git push
git push --tags
log_message "Pushed commit + tag to GitHub"

log_message "=== Promotion complete on PC: Tag $TAG ==="
log_message "Next step: on pi@kframe run update_picframe.sh to pull latest and restart Picframe."
echo
