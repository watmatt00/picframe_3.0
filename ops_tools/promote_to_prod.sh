#!/bin/bash
set -euo pipefail

# -------------------------------------------------------------------
# promote_to_prod.sh
# Purpose: Promote test scripts to production, archive selected files,
# prune old archives, commit repo state, create git tag, and push.
# -------------------------------------------------------------------

REPO_ROOT="$HOME/picframe_3.0"
OPS_DIR="$REPO_ROOT/ops_tools"
APP_CTRL_DIR="$REPO_ROOT/app_control"
ARCHIVE_DIR="$OPS_DIR/archive"
LOG_FILE="$HOME/logs/frame_sync.log"

# -------------------------------------------------------------------
# ARCHIVE LIST — Update this list to include any files to archive/prune
# -------------------------------------------------------------------
ARCHIVE_LIST=("chk_sync.sh" "frame_sync.sh")
# EXAMPLES FOR FUTURE:
# ARCHIVE_LIST=("chk_sync.sh" "frame_sync.sh" "new_feature.sh")

log_message() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [PROMOTE] $msg" | tee -a "$LOG_FILE"
}

cd "$REPO_ROOT" || { echo "Cannot cd to repo root: $REPO_ROOT"; exit 1; }

log_message "=== Starting promotion to production ==="

TIMESTAMP=$(date '+%Y%m%d-%H%M')

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

        # ---- PRUNE LOGIC (KEEP ONLY 10 LATEST VERSIONS FOR THIS FILE) ----
        FILE_PATTERN="${SCRIPT%.sh}_*.sh"
        FILES=($(ls -1t "$ARCHIVE_DIR"/$FILE_PATTERN 2>/dev/null || true))
        TOTAL=${#FILES[@]}

        if [ "$TOTAL" -gt 10 ]; then
            for ((i=10; i<${#FILES[@]}; i++)); do
                rm -f "${FILES[$i]}"
                log_message "Pruned old archive: $(basename "${FILES[$i]}")"
            done
        fi

    else
        log_message "WARNING: $SCRIPT not found — skipping archive"
    fi
done

# -------------------------------------------------------------------
# Step 2: Promote test → prod (dynamic for all t_*.sh files)
# -------------------------------------------------------------------
for TFILE in "$OPS_DIR"/t_*.sh; do
    [ -f "$TFILE" ] || continue
    BASE=$(basename "$TFILE" | sed 's/^t_//')
    mv "$TFILE" "$OPS_DIR/$BASE"
    chmod +x "$OPS_DIR/$BASE"
    log_message "Promoted $TFILE → $BASE"
done

# -------------------------------------------------------------------
# Step 3: Git commit full repo state
# -------------------------------------------------------------------
git add -A
git commit -m "Production promotion on $(date '+%Y-%m-%d %H:%M')" || \
    log_message "No changes to commit (Git reported clean state)"
log_message "Git commit complete"

# -------------------------------------------------------------------
# Step 4: Git tag
# -------------------------------------------------------------------
TAG="prod-$TIMESTAMP"
git tag -a "$TAG" -m "Production promotion on $(date)"
log_message "Created tag: $TAG"

# -------------------------------------------------------------------
# Step 5: Push to origin
# -------------------------------------------------------------------
git push
git push --tags
log_message "Pushed commit and tags to GitHub"

# -------------------------------------------------------------------
# Step 6: Restart picframe service
# -------------------------------------------------------------------
"$APP_CTRL_DIR/pf_restart_svc.sh"
log_message "Restarted picframe service"

log_message "=== Promotion complete: Tag $TAG ==="
echo
