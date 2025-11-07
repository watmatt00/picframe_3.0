# 🖼️ PicFrame 3.0 — Raspberry Pi Digital Picture Frame

PicFrame 3.0 is a DIY digital picture frame project built on a Raspberry Pi.  
It automatically syncs photos from a Google Drive folder using **rclone**,  
displays them via the **PicFrame** viewer service, and includes tools  
for syncing, verification, promotion, and Git-based updates.

---

## 📁 Project Structure

```
picframe_3.0/
├── app_control/
│   ├── crontab                # Reference: linked system crontab file
│   ├── pf_start_svc.sh        # Starts picframe.service
│   ├── pf_stop_svc.sh         # Stops picframe.service
│   ├── pf_restart_svc.sh      # Restarts picframe.service
│
├── ops_tools/
│   ├── frame_sync.sh          # Main operational sync script
│   ├── chk_sync.sh            # Manual sync verification tool
│   ├── t_frame_sync.sh        # Test/Beta version of frame_sync.sh
│   ├── t_chk_sync.sh          # Test/Beta version of chk_sync.sh
│   ├── promote_to_prod.sh     # Promotion tool: t_ → production scripts
│   └── update_picframe.sh     # Updates local repository from GitHub
│
└── README.md
```

---

## 🛠️ Typical Usage

| **Task** | **Command** |
|-----------|--------------|
| Start picframe | `bash ~/picframe_3.0/app_control/pf_start_svc.sh` |
| Stop picframe | `bash ~/picframe_3.0/app_control/pf_stop_svc.sh` |
| Restart picframe | `bash ~/picframe_3.0/app_control/pf_restart_svc.sh` |
| Check sync | `bash ~/picframe_3.0/ops_tools/chk_sync.sh` |
| Force sync | `bash ~/picframe_3.0/ops_tools/frame_sync.sh` |
| Update & restart | `bash ~/picframe_3.0/ops_tools/update_picframe.sh` |
| Promote test scripts to production | `bash ~/picframe_3.0/ops_tools/promote_to_prod.sh` |

---

## ⚙️ Script Overview

### 🔄 `frame_sync.sh`
Main operational sync script that compares file counts between Google Drive and the local photo directory.  
If differences exist, it performs an `rclone sync`, restarts `picframe.service`, and logs results.

---

### 🧮 `chk_sync.sh`
Manual verification script to check file count differences or perform detailed file mismatch analysis.

**Usage:**
```bash
./chk_sync.sh        # Summary only
./chk_sync.sh --d    # Detailed difference report
```

---

### 🧪 `t_frame_sync.sh` & `t_chk_sync.sh`
Development/test versions used for beta validation of sync logic or performance before promotion.

---

### 🚀 `promote_to_prod.sh`
Automates the promotion of tested (`t_`) scripts into production versions.  
Provides a pre-promotion summary of changes and confirmation prompt before archiving or renaming scripts.  

**Features:**
- Detects test scripts ready for promotion (`t_frame_sync.sh`, `t_chk_sync.sh`)
- Displays exact file changes and archive names
- Requests confirmation before proceeding
- Temporarily disables cron during promotion
- Archives replaced production scripts with timestamps
- Commits, tags, and pushes changes to GitHub automatically
- Restores cron once complete

---

### 🔁 `update_picframe.sh`
Pulls updates from GitHub and ensures all scripts are executable.

**Usage:**
```bash
cd ~/picframe_3.0
bash ops_tools/update_picframe.sh
```

---

## 🧩 Notes

- Logs are stored in `~/logs/frame_sync.log` (rotated weekly)  
- All scripts assume the repository root: `/home/pi/picframe_3.0`  
- `picframe.service` runs as a **user-level service** — no `sudo` required  
- The `app_control/crontab` file defines scheduled tasks and is **linked to the active crontab** for version control  
- `rclone.conf` must be owned and readable by `pi`:
  ```bash
  sudo chown pi:pi /home/pi/.config/rclone/rclone.conf
  sudo chmod 600 /home/pi/.config/rclone/rclone.conf
  ```

---

## 🧠 Git Shortcuts

A universal set of custom Git aliases configured for both PC and Pi.

### 🔄 Custom Git Commands

```bash
git sync   = git fetch origin && git pull --rebase origin main && git push origin main
git quick  = git add . && git commit -m "quick update" && git push
git commit = git commit -am
```

These shortcuts streamline common Git operations for fast, consistent updates across systems.

---

## 🧠 Best Practices

- Always test using `t_*.sh` scripts before promoting to production  
- Avoid editing production scripts directly; use GitHub workflow  
- Run `git sync` before testing or promoting to ensure latest code  
- Use Git tags (`prod_YYYY-MM-DD_HHMM`) created during promotion for rollback or history tracking:
  ```bash
  git tag
  git checkout <tag_name>
  ```

---

© 2025 Matt P. — *DIY PicFrame 3.0*
