# Migration Script Updates

## Changes Made

### Problem
The original migration script had a circular dependency:
- Script needs to be run from the cloned repo
- But script errors if repo already exists
- But how else would user get the script?

### Solution
Updated script to support **both workflows**:

#### Workflow 1: Manual Clone (Recommended)
```bash
ssh pi@your-pi
git clone https://github.com/watmatt00/picframe_3.0.git
cd picframe_3.0/ops_tools
./migrate.sh
```

#### Workflow 2: Automatic Clone (Fallback)
```bash
ssh pi@your-pi
wget https://raw.githubusercontent.com/watmatt00/picframe_3.0/main/ops_tools/migrate.sh
./migrate.sh
# Script clones repo automatically
```

## Code Changes

### 0. Fixed: `detect_state()` Logic (CRITICAL BUG FIX)
**Location:** Lines 36-61

**Problem:** 
State detection incorrectly identified "complete" when:
- Legacy files still exist
- Repo manually cloned
- No migration cache yet

This caused the script to think migration was complete when it hadn't even started!

**Fix:**
```bash
# State 1: Legacy (NOW checks for legacy files regardless of repo)
if [[ -f "$LEGACY_SYNC_SCRIPT" ]] && [[ ! -d "$MIGRATION_CACHE" ]]; then
    echo "legacy"
fi

# State 3: Complete (NOW requires legacy files to be gone)
if [[ -d "$NEW_APP_ROOT/.git" ]] && [[ ! -d "$MIGRATION_CACHE" ]] && [[ ! -f "$LEGACY_SYNC_SCRIPT" ]]; then
    echo "complete"
fi
```

**Result:** Properly handles manual git clone before running migration!

### 1. New Function: `check_or_clone_repo()`
**Location:** After `check_legacy_exists()` function

**Purpose:** 
- Checks if repo already exists
- If YES: Validates structure and continues (no error!)
- If NO: Installs git and clones repo

**Behavior:**
```bash
# If repo exists:
✓ Repository already exists at /home/pi/picframe_3.0
  Skipping git clone (assuming manual installation)
✓ Repository structure verified

# If repo doesn't exist:
Repository not found. Will clone from GitHub...
[proceeds with git installation and clone]
```

### 2. Updated: `check_legacy_exists()`
**Removed:** Error check for existing repo (lines 165-173)

**Before:**
```bash
if [[ -d "$NEW_APP_ROOT/.git" ]]; then
    echo "ERROR: picframe_3.0 repo already exists"
    exit 1
fi
```

**After:**
```bash
# Check removed - repo can already exist
```

### 3. Updated: `run_prep_phase()`
**Changed:** Call sequence

**Before:**
```bash
ensure_git_installed
setup_git_and_clone_repo
```

**After:**
```bash
check_or_clone_repo
# (which internally calls ensure_git_installed and setup_git_and_clone_repo if needed)
```

### 4. Updated: Documentation
- Added recommended workflow to header comments
- Updated `--help` output with step-by-step instructions
- Clarified that manual clone is recommended but automatic works too

## Benefits

✅ **More Transparent:** Users can review script before running
✅ **More Reliable:** Uses standard git (always available on Pi)
✅ **Version Tracked:** User knows exactly which version they're running
✅ **Idempotent:** Can run multiple times safely
✅ **Flexible:** Works both ways (manual or automatic)
✅ **Better UX:** Clear, logical workflow

## Testing

Test both workflows in the Docker simulator:

```bash
# Test 1: Manual clone (recommended)
./pf_sim.sh start
docker exec --user pi pf_sim_dev bash -c "
  git clone https://github.com/watmatt00/picframe_3.0.git &&
  cd picframe_3.0/ops_tools &&
  ./migrate.sh --help
"

# Test 2: Full migration test
cd pf_pi_sim
docker exec --user pi pf_sim_dev bash test_scripts/test_migration.sh
```

## Backward Compatibility

✅ **Fully backward compatible**
- Old workflow (automatic clone) still works
- New workflow (manual clone) now supported
- No breaking changes

## Related Files

- `/ops_tools/migrate.sh` - Main migration script (updated)
- `/pf_pi_sim/test_scripts/test_migration.sh` - Test suite (updated)
- `/pf_pi_sim/docs/TESTING-MIGRATION.md` - Test documentation

## Summary

The script is now **idempotent and flexible**, supporting the natural workflow where users:
1. Clone the repo first (to review and inspect)
2. Run the migration script from the cloned repo
3. Script detects repo exists and continues without error

This matches standard DevOps practices and improves user experience.
