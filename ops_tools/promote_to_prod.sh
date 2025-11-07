#!/bin/bash
#
# promote_to_prod.sh — Safely promote tested t_ scripts to production
# Includes preview with exact archive filenames, user confirmation,
# cron disable/restore, backups, and Git tagging.
#

set -euo pipefail

BASE_DIR="$HOME/picframe_3.0/ops_tools"
ARCHIVE_DIR="$BASE_DIR/archive"
CRON_BACKUP="$HOME/cron_backup_$(date +%Y%m%d_%H%M).txt"
DATE_TAG=$(date +%Y-%m-%d_%H%M)

cd "$BASE_DIR"

echo
echo "🚀 PicFrame Promotion Utility"
echo "──────────────────────────────────────────────"
echo "This script will promote your test scripts to production."
echo "Working directory: $BASE_DIR"
echo

# -------------------------------------------------------------------
# 1. Detect files to promote
# -------------------------------------------------------------------
declare -a PROMOTIONS=()

for base in frame_sync chk_sync; do
    TEST_FILE="t_${base}.sh"
    PROD_FILE="${base}.sh"
    if [ -f "$TEST_FILE" ]; then
        ARCHIVE_NAME="archive/${base}_${DATE_TAG}.sh"
        if [ -f "$PROD_FILE" ]; then
            PROMOTIONS+=("$TEST_FILE → $PROD_FILE (old version will be archived as $ARCHIVE_NAME)")
        else
            PROMOTIONS+=("$TEST_FILE → $PROD_FILE (new file will be created)")
        fi
    fi
done

if [ ${#PROMOTIONS[@]} -eq 0 ]; then
    echo "⚠️  No test files (t_*.sh) found to promote."
    echo "Nothing to do. Exiting."
    exit 0
fi

echo "🧾 The following promotions will occur:"
for p in "${PROMOTIONS[@]}"; do
    echo "   • $p"
done

echo
read -rp "❓ Proceed with promotion and cron restart? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ Promotion canceled by user."
    exit 0
fi

echo
echo "🔄 Starting promotion process at $(date)"
echo

# -------------------------------------------------------------------
# 2. Backup and disable cron
# -------------------------------------------------------------------
echo "📦 Backing up current crontab to $CRON_BACKUP"
crontab -l > "$CRON_BACKUP" || echo "# Empty crontab" > "$CRON_BACKUP"

echo "⏸️  Temporarily disabling cron jobs..."
crontab -r
sleep 2

# -------------------------------------------------------------------
# 3. Prepare archive folder
# -------------------------------------------------------------------
mkdir -p "$ARCHIVE_DIR"

# -------------------------------------------------------------------
# 4. Promote scripts
# -------------------------------------------------------------------
for base in frame_sync chk_sync; do
    TEST_FILE="t_${base}.sh"
    PROD_FILE="${base}.sh"

    if [ -f "$TEST_FILE" ]; then
        echo "➡️  Promoting $TEST_FILE → $PROD_FILE"
        ARCHIVE_FILE="${ARCHIVE_DIR}/${base}_${DATE_TAG}.sh"

        if [ -f "$PROD_FILE" ]; then
            mv "$PROD_FILE" "$ARCHIVE_FILE"
            echo "   ↳ Archived old version as $ARCHIVE_FILE"
        fi

        mv "$TEST_FILE" "$PROD_FILE"
        chmod +x "$PROD_FILE"
        echo "   ✅ Promotion complete for $PROD_FILE"
    fi
done

# -------------------------------------------------------------------
# 5. Git commit and tag
# -------------------------------------------------------------------
if [ -d "$BASE_DIR/../.git" ]; then
    cd "$BASE_DIR/.."
    git add ops_tools/frame_sync.sh ops_tools/chk_sync.sh || true
    git add ops_tools/archive || true
    git commit -m "Promoted tested scripts to production on $DATE_TAG"
    git tag -a "prod_${DATE_TAG}" -m "Promote t_ scripts to production"
    git push && git push --tags
    echo "📤 Changes committed and pushed to GitHub."
else
    echo "⚠️  Git repo not detected — skipping commit/tag step."
fi

# -------------------------------------------------------------------
# 6. Restore cron
# -------------------------------------------------------------------
echo "🔁 Restoring cron jobs..."
crontab "$CRON_BACKUP"

echo
echo "✅ Promotion completed successfully at $(date)"
echo "──────────────────────────────────────────────"
echo "Cron has been re-enabled and production scripts are live."
echo
