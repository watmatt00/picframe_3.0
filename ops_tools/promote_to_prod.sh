#!/bin/bash
set -euo pipefail

# -------------------------------------------------------------------
# promote_to_prod.sh
# Safely promote test scripts to production, archive selected files,
# prune old archives, commit repo state, create git tag, and push.
# -------------------------------------------------------------------

REPO_ROOT="$HOME/picframe_3.0"
OPS_DIR="$REPO_ROOT/ops_tools"
APP_CTRL_DIR="$REPO_ROOT/app_control"
ARCHIVE_DIR="$OPS_DIR/archive"
LOG_FILE="$HOME/logs/frame_sync.log"

# Scripts that should be archived & pruned
ARCHIVE_LIST=("chk_sync.sh" "frame_sync.sh")

log_message() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [PROMOTE] $msg" | tee -a "$LOG_FILE"
}

cd "$REPO_ROOT" || { echo "Cannot cd to $REPO_ROOT"; exit 1; }

log_message "=== Starting promotion to production ==="

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
for SCRIPT in "${ARCHIVE_LIST[@]}"; do
    ARCHIVE_NAME="${SCRIPT%.sh}_${TIMESTAMP}.sh"
    echo "  • $SCRIPT → archive/$ARCHIVE_NAME"
done

# 2. Test → Prod actions
for TFILE in "$OPS_DIR"/t_*.sh; do
    [ -f "$TFILE" ] || continue
    BASE=$(basename "$TFILE" | sed 's/^t_//')
    echo "  • $(basename "$TFILE") → $BASE"
done

echo
read -rp "Proceed with promotion? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Promotion cancelled."
    log_message "Promotion aborted by user."
    exit 0
fi
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

# -------------------------------------------------------------------
# Step 6: Restart picframe service
# -------------------------------------------------------------------
"$APP_CTRL_DIR/pf_restart_svc.sh"
log_message "Restarted picframe service"

log_message "=== Promotion complete: Tag $TAG ==="
echo
