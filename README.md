# 🖼️ PicFrame 3.0 — Raspberry Pi Digital Picture Frame

PicFrame 3.0 is a DIY digital picture frame project built on a Raspberry Pi.
It syncs photos from a Google Drive folder using **rclone**, displays them via
the **PicFrame** viewer service, and includes tools for syncing, verification,
promotion, and Git-based updates.

---

## 📁 Project Structure

```bash
picframe_3.0/
├── app_control/
│   ├── crontab                 # Template crontab (deployed by update_picframe.sh)
│   ├── pf_start_svc.sh
│   ├── pf_stop_svc.sh
│   ├── pf_restart_svc.sh
│   └── frame_sync_cron.sh      # Cron wrapper for scheduled frame_sync.sh runs
│
├── ops_tools/
│   ├── frame_sync.sh           # Main operational sync script (SAFE_MODE + auto-disable)
│   ├── chk_sync.sh             # Manual sync verification / diff tool
│   ├── t_frame_sync.sh         # Test/Beta version of frame_sync.sh
│   ├── t_chk_sync.sh           # Test/Beta version of chk_sync.sh
│   ├── promote_to_prod.sh      # Promote t_* scripts into production
│   └── update_picframe.sh      # Pulls updates, refreshes crontab, restarts service
│
└── README.md
```

**Notes:**
- `app_control/crontab` is a **template**, not the live system crontab.
  The `update_picframe.sh` script installs this template into the user's actual crontab.
- `frame_sync.sh` is the **production** sync script. New behavior is first
  developed and tested in `t_frame_sync.sh` and then promoted using
  `promote_to_prod.sh`.

---

## 🛠️ Typical Usage

| Task | Command |
|------|---------|
| Start picframe service | `bash ~/picframe_3.0/app_control/pf_start_svc.sh` |
| Stop picframe service | `bash ~/picframe_3.0/app_control/pf_stop_svc.sh` |
| Restart picframe service | `bash ~/picframe_3.0/app_control/pf_restart_svc.sh` |
| Check sync status | `bash ~/picframe_3.0/ops_tools/chk_sync.sh` |
| Manual sync run | `bash ~/picframe_3.0/ops_tools/frame_sync.sh` |
| Update repository & restart | `bash ~/picframe_3.0/ops_tools/update_picframe.sh` |
| Promote test scripts to prod | `bash ~/picframe_3.0/ops_tools/promote_to_prod.sh` |

---

## 🔄 frame_sync.sh — Main Sync Script (with SAFE_MODE)

`frame_sync.sh` is responsible for keeping the local photo directory in sync
with a Google Drive folder and restarting the PicFrame service when needed.

High-level behavior:

1. Compares file counts between:
   - **Remote:** `kfgdrive:dframe` (Google Drive via rclone)
   - **Local:** `$HOME/Pictures/gdt_frame`
2. If counts match:
   - No sync is performed.
3. If counts differ:
   - Runs `rclone sync` with limited retries.
   - Restarts `picframe.service` on success (unless SAFE_MODE is active).
4. Logs all actions to `~/logs/frame_sync_YYYY-MM-DD.log`.

### SYNC_RESULT Summary Lines

Every run of `frame_sync.sh` logs **exactly one** summary line beginning with
`SYNC_RESULT:`. This line describes the overall effect of the run:

- `SYNC_RESULT: RESTART - …`  
  Sync succeeded **and** `picframe.service` was restarted successfully.

- `SYNC_RESULT: NO_RESTART - …`  
  All other cases:
  - Counts matched (no sync required).
  - Sync failed.
  - Service restart failed.
  - SAFE_MODE suppressed a restart.
  - Sync was disabled via flag file.

These summary lines are used to detect repeated service restarts.

### SAFE_MODE — Protect Against Restart Storms

To prevent the service from repeatedly restarting ("flapping"), the script
tracks the last 3 `SYNC_RESULT:` entries for the current day.

- If the **last three** `SYNC_RESULT:` lines are all `RESTART`, then on the
  next run:
  - SAFE_MODE is enabled.
  - A disable flag file is created:

    ```bash
    ~/picframe_3.0/ops_tools/frame_sync.disabled
    ```

  - The script still runs sync as needed, but **does not restart** the service.
  - The summary line is:

    ```text
    SYNC_RESULT: NO_RESTART - Sync succeeded in SAFE_MODE; service restart suppressed.
    ```

This makes SAFE_MODE both automatic and self-documenting in the log.

---

## 🧱 Cron Wrapper — frame_sync_cron.sh

Scheduled runs should **not** call `frame_sync.sh` directly.  
Instead, `app_control/frame_sync_cron.sh` is used as a lightweight wrapper.

Responsibilities:

- Checks for the SAFE_MODE flag: `ops_tools/frame_sync.disabled`
- If the flag exists:
  - Logs that sync is disabled.
  - Exits without running `frame_sync.sh`.
- If no flag exists:
  - Calls the production sync script.

Example contents of **`app_control/frame_sync_cron.sh`**:

```bash
#!/bin/bash

DISABLE_FILE="$HOME/picframe_3.0/ops_tools/frame_sync.disabled"
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/frame_sync_$(date +%Y-%m-%d).log"

mkdir -p "$LOG_DIR"

# If disabled, log and exit quietly
if [ -f "$DISABLE_FILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') frame_sync_cron.sh - Frame sync disabled via $DISABLE_FILE; skipping frame_sync.sh" >>"$LOG_FILE"
    exit 0
fi

# Otherwise run the main sync script
/home/pi/picframe_3.0/ops_tools/frame_sync.sh
```

Suggested cron entry (every 15 minutes):

```cron
*/15 * * * * /home/pi/picframe_3.0/app_control/frame_sync_cron.sh
```

---

## 🧑‍💻 Manual Override of SAFE_MODE

When you run `frame_sync.sh` manually in a terminal:

```bash
cd ~/picframe_3.0/ops_tools
./frame_sync.sh
```

- If `frame_sync.disabled` is **absent**, the script behaves normally.
- If `frame_sync.disabled` **exists**, the script:
  - Detects that it is running interactively.
  - Prompts:

    ```text
    Frame sync is currently DISABLED.
    Disable flag detected at: /home/pi/picframe_3.0/ops_tools/frame_sync.disabled
    Delete disable flag and run sync anyway? [y/N]:
    ```

  - If you answer **Y**:
    - The flag file is removed.
    - The script continues with a normal run (including potential restarts).
  - If you answer **N** (or press Enter):
    - The script logs a `SYNC_RESULT: NO_RESTART` summarizing that sync was
      skipped due to the disable flag.
    - Then exits without further action.

This allows SAFE_MODE to be bypassed intentionally only when you are present.

---

## 🧪 Test Scripts — t_frame_sync.sh & t_chk_sync.sh

The `t_*.sh` scripts are used for development & testing:

- `t_frame_sync.sh` – test harness for new sync and SAFE_MODE features.
- `t_chk_sync.sh` – test harness for new check logic.

The typical workflow is:

1. Implement and test changes in `t_frame_sync.sh` and/or `t_chk_sync.sh`.
2. Once validated on the Pi, use `promote_to_prod.sh` to:
   - Archive the current production script(s).
   - Copy the tested `t_*.sh` into their production names.
   - Optionally commit/tag the change in Git.

---

## 🚀 promote_to_prod.sh

Promotion Workflow (New – PC Only)
Picframe now uses a clean two-stage workflow:

  1. Development & testing (PC)
  All code changes, including updates to test scripts (t_frame_sync.sh, t_chk_sync.sh, etc.), are done on your PC repo:
```bash
~/Downloads/GitHub/picframe_3.0
```

The Pi should not be used for editing scripts inside the repo.
2. Promotion to Production (PC Only)
  Once changes are tested and working, run:
```bash  
./ops_tools/promote_to_prod.sh
```

This script (PC-only):
  Archives existing production scripts (frame_sync.sh, chk_sync.sh)
  Prunes the archive to the most recent 10 versions
  Copies all t_*.sh files → production filenames
  (e.g., t_frame_sync.sh → frame_sync.sh)
  Leaves the t_*.sh test scripts intact
  Performs a Git add, commit, tag, and push to GitHub
  Blocks execution on the Pi (kframe) to keep Pi read-only
  After running this promotion script, GitHub contains the new production scripts.

Updating the Pi After Promotion
  The Pi never edits code.
  It only pulls updates.

On the Pi, run:
```bash
~/picframe_3.0/ops_tools/update_picframe.sh
```

This script:
  Performs a pull/rebase (no committing or tagging)
  Refreshes the Pi crontab from app_control/crontab
  Restarts picframe.service

The Pi repo stays consistent with GitHub and remains read-only.

---

## 🔁 update_picframe.sh

Handles bringing the local repository up-to-date and ensuring the automation
is wired correctly.

Typical responsibilities:

- Run `git sync` to pull from GitHub and push any committed local changes.
- Apply correct execute permissions to key scripts.
- Install `app_control/crontab` into the user's crontab.
- Restart the PicFrame service as needed.

Usage:

```bash
bash ~/picframe_3.0/ops_tools/update_picframe.sh
```

---

## 📝 Notes

- Sync logs are stored as daily files:

  ```bash
  ~/logs/frame_sync_YYYY-MM-DD.log
  ```

- SAFE_MODE flag file lives at:

  ```bash
  ~/picframe_3.0/ops_tools/frame_sync.disabled
  ```

- To fully clear SAFE_MODE for scheduled runs, either:
  - Remove the flag by hand:

    ```bash
    rm ~/picframe_3.0/ops_tools/frame_sync.disabled
    ```

  - Or answer **Y** at the manual override prompt.

- Ensure `rclone.conf` is owned and readable by user `pi`:

  ```bash
  sudo chown pi:pi /home/pi/.config/rclone/rclone.conf
  sudo chmod 600 /home/pi/.config/rclone/rclone.conf
  ```

---

## 🧠 Git Shortcuts

Common custom Git aliases (defined in your global `~/.gitconfig`):

```bash
git sync   # fetch, rebase from origin/main, then push
git quick  # add all changes, commit "quick update", and push
git commit # runs "git commit -am" (add tracked files + commit)
```

These commands streamline keeping the Pi and your PC repo in sync.

---

© 2025 Matt P. — DIY PicFrame 3.0
