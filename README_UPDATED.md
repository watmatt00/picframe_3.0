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
│   ├── crontab
│   ├── pf_start_svc.sh
│   ├── pf_stop_svc.sh
│   ├── pf_restart_svc.sh
│   └── frame_sync_cron.sh
│
├── ops_tools/
│   ├── frame_sync.sh
│   ├── chk_sync.sh
│   ├── t_frame_sync.sh
│   ├── t_chk_sync.sh
│   ├── promote_to_prod.sh
│   └── update_picframe.sh
│
└── README.md
```

---

## 🔍 chk_sync.sh — Manual Sync Verification & Status Report

`chk_sync.sh` is the production sync verification tool.  
It now performs:

### 1. Quick File Count Comparison
- Remote: `kfgdrive:dframe`
- Local:  `~/Pictures/gdt_frame`

### 2. Embedded Log Status Summary
Calls `chk_status.sh` to display:
- Last successful sync
- Last file download
- Last service restart

### ✔️ Example Output

```
--------------------------------------------
   Google Drive vs Local Directory Check
--------------------------------------------

Performing quick file count comparison...
Remote file count: 1234
Local  file count: 1234
✓ Quick check: File counts match.

===== Log status summary (via chk_status.sh) =====
...
--------------------------------------------
End of Google Drive vs Local Directory Check
--------------------------------------------
```

---

## 🚀 promote_to_prod.sh

Handles promoting:
- `t_frame_sync.sh` → `frame_sync.sh`
- `t_chk_sync.sh` → `chk_sync.sh`

And archives old versions.

---

## 🔁 update_picframe.sh

Pulls updates, installs crontab, restarts services.

---

© 2025 Matt P. — DIY PicFrame 3.0
