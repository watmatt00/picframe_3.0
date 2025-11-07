# picframe_3.0

A modular Raspberry Pi digital photo frame system with automated file sync, service control, and remote update capability.

---

## 📁 Directory Structure

```
picframe_3.0/
├── app_control/       # Application & service control scripts
│   ├── pf_start_svc.sh     # Starts the picframe service
│   ├── pf_stop_svc.sh      # Stops the picframe service
│   ├── pf_restart_svc.sh   # Restarts the picframe service
│   └── crontab             # system crontab example
│
├── ops_tools/          # Operational tools and maintenance scripts
│   ├── frame_sync.sh        # Syncs local/remote photo directories
│   ├── chk_sync.sh          # Verifies file sync status
│   ├── t_frame_sync.sh      # Test version of frame_sync.sh
│   ├── t_chk_sync.sh        # Test version of chk_sync.sh
│   └── update_picframe.sh   # Pulls updates from GitHub and restarts service
│
└── logs/               # (not versioned) Runtime logs are written here
```

---

## ⚙️ Service Overview

The **picframe** display app runs as a *user-level* `systemd` service:

```bash
systemctl --user status picframe.service
```

- **Service file:** `~/.config/systemd/user/picframe.service`  
- **Startup script:** `/home/pi/start_picframe_app.sh`  
- **Virtual environment:** `/home/pi/venv_picframe/`  
- **Config directory:** `/home/pi/picframe_data/config/`

---

## 🔁 Update Workflow

Run this command on the Pi to update the repo, set permissions, and restart the service:

```bash
~/picframe_3.0/ops_tools/update_picframe.sh
```

This script:
1. Calls `git sync` (fetch + rebase + push)
2. Resets permissions
3. Invokes `app_control/pf_restart_svc.sh`

Logs are appended to `~/logs/frame_sync.log`.

---

## 🧠 Git Shortcuts

A custom alias `git sync` has been configured for both PC and Pi:

```bash
git sync
```

Equivalent to:
```bash
git fetch origin && git pull --rebase origin main && git push origin main
```

---

## 🛠️ Typical Usage

| Task | Command |
|------|----------|
| Start picframe | `bash ~/picframe_3.0/app_control/pf_start_svc.sh` |
| Stop picframe | `bash ~/picframe_3.0/app_control/pf_stop_svc.sh` |
| Restart picframe | `bash ~/picframe_3.0/app_control/pf_restart_svc.sh` |
| Check sync | `bash ~/picframe_3.0/ops_tools/chk_sync.sh` |
| Force sync | `bash ~/picframe_3.0/ops_tools/frame_sync.sh` |
| Update & restart | `bash ~/picframe_3.0/ops_tools/update_picframe.sh` |

---

## 🧩 Notes

- Logs are stored in `~/logs/frame_sync.log`
- All scripts assume repository root: `/home/pi/picframe_3.0`
- `picframe.service` is a *user-level* service — no `sudo` required

---

**Author:** [@watmatt00](https://github.com/watmatt00)  
**License:** MIT (optional — add if desired)
