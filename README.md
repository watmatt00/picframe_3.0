🖼️ PicFrame 3.0 — Raspberry Pi Digital Picture Frame

PicFrame 3.0 is a DIY digital picture frame project built on a Raspberry Pi.
It syncs photos from one or more cloud folders using rclone, displays them via
the PicFrame viewer service, and includes tools for syncing, verification,
promotion, and Git-based updates.

⚙️ Setup

First-Time Setup (Recommended)

1. Configure rclone (if not already done):
   rclone config
   
   Follow the prompts to add your cloud storage (Google Drive, Dropbox, etc.)

2. Start the web dashboard:
   bash ~/picframe_3.0/app_control/svc_ctl.sh -ws

3. Open the dashboard in a browser:
   http://<your-pi-ip>:5050

4. Complete the setup wizard that appears automatically on first run:
   - Configure your rclone remote
   - Set local directory path
   - Choose active photo source
   - Test connection before saving

Manual Configuration (Alternative)

1. Copy the example config:
   mkdir -p ~/.picframe
   cp ~/picframe_3.0/config/config.example ~/.picframe/config

2. Edit with your settings:
   nano ~/.picframe/config

3. Validate your configuration:
   bash ~/picframe_3.0/ops_tools/validate_config.sh

Configuration Options

| Setting | Required | Description |
|---------|----------|-------------|
| RCLONE_REMOTE | Yes | Your rclone remote and path (e.g., gdrive:photos) |
| LOCAL_DIR | Yes | Local directory for synced photos |
| APP_ROOT | No | PicFrame installation directory (default: /home/pi/picframe_3.0) |
| LOG_DIR | No | Log file directory (default: /home/pi/logs) |
| ALLOWED_HOST | No | Hostname for safety checks (empty = no check) |
| ALLOWED_USER | No | Username for safety checks (default: pi) |
| ACTIVE_SOURCE | No | Active source ID from frame_sources.conf |
| FRAME_LIVE_PATH | No | Symlink path (default: /home/pi/Pictures/frame_live) |
| FRAME_SOURCES_CONF | No | Path to sources config (default: APP_ROOT/config/frame_sources.conf) |

The web dashboard also provides a Settings panel where you can update these
values, test your rclone connection, switch photo sources, and export your config.

Photo Sources Configuration

PicFrame supports multiple photo sources defined in `config/frame_sources.conf`.

Format: `id|label|absolute_path|enabled|rclone_remote`

Example:
gdt|Google Drive|/home/pi/Pictures/gdt_frame|1|gdrive:photos
kfr|Koofr|/home/pi/Pictures/kfr_frame|1|koofr:kframe

• Add unlimited sources without code changes
• Toggle enabled/disabled per source
• Override global RCLONE_REMOTE per source (optional)
• Switch sources via CLI or web dashboard

📁 Project Structure

picframe_3.0/
├── app_control/
│ ├── svc_ctl.sh – Unified service control (picframe & web)
│ ├── frame_sync_cron.sh – Cron wrapper for scheduled syncs
│ └── start_picframe_app.sh – Initial app launcher
│
├── config/
│ ├── crontab – Template cron installed by update_app.sh
│ ├── config.example – Template user config file
│ └── frame_sources.conf – Source definitions for gdt/kfr
│
├── lib/
│ └── config_loader.sh – Shared config loading for all scripts
│
├── web_status/
│ ├── app.py – Flask backend with API endpoints
│ ├── status_backend.py – Status and sync checking logic
│ ├── config_manager.py – Configuration read/write module
│ ├── static/
│ │ ├── css/
│ │ │ └── dashboard.css – Dashboard styling
│ │ └── js/
│ │   └── dashboard.js – Dashboard interactivity
│ └── templates/
│   └── dashboard.html – Dashboard UI with settings panel
│
├── ops_tools/
│ ├── archive/ – Backed up production scripts
│ ├── migrate.sh – Migrate from legacy flat installation to git structure
│ ├── frame_sync.sh – Main sync script with SAFE_MODE
│ ├── chk_status.sh – Parses log for last sync / restart / download
│ ├── chk_sync.sh – Source-aware count checker
│ ├── pf_source_ctl.sh – Photo source selection controller
│ ├── validate_config.sh – Configuration validator
│ ├── t_frame_sync.sh – Test sync script
│ ├── t_chk_sync.sh – Test chk script
│ ├── promote_to_prod.sh – Promote test scripts to production
│ └── update_app.sh – Pull GitHub updates & restart services
│
├── CONTRIBUTING.md – Contributor guidelines and standards
├── tasklist.md – Project task tracking and priorities
└── README.md

🛠️ Common Commands

Service Control (Unified Script):
# PicFrame service
bash ~/picframe_3.0/app_control/svc_ctl.sh -ps      # Start
bash ~/picframe_3.0/app_control/svc_ctl.sh -px      # Stop
bash ~/picframe_3.0/app_control/svc_ctl.sh -pr      # Restart

# Web dashboard
bash ~/picframe_3.0/app_control/svc_ctl.sh -ws      # Start
bash ~/picframe_3.0/app_control/svc_ctl.sh -wx      # Stop
bash ~/picframe_3.0/app_control/svc_ctl.sh -wr      # Restart

# Alternative verbose syntax
bash ~/picframe_3.0/app_control/svc_ctl.sh -picframe-restart
bash ~/picframe_3.0/app_control/svc_ctl.sh -web-restart

Run quick sync check:
bash ~/picframe_3.0/ops_tools/chk_sync.sh

Run detailed sync check:
bash ~/picframe_3.0/ops_tools/chk_sync.sh --d

Manual sync:
bash ~/picframe_3.0/ops_tools/frame_sync.sh

Validate configuration:
bash ~/picframe_3.0/ops_tools/validate_config.sh

List available photo sources:
bash ~/picframe_3.0/ops_tools/pf_source_ctl.sh list

Show current active source:
bash ~/picframe_3.0/ops_tools/pf_source_ctl.sh current

Switch photo source:
bash ~/picframe_3.0/ops_tools/pf_source_ctl.sh set <source_id>

Update from GitHub (Pi only):
bash ~/picframe_3.0/ops_tools/update_app.sh

Promote tests to prod (PC/tablet only):
bash ~/picframe_3.0/ops_tools/promote_to_prod.sh

🔄 frame_sync.sh — Main Sync Script

Responsibilities:

• Detect active source (gdt_frame or kfr_frame)
• Compare remote vs local file counts
• Run rclone sync if needed
• Restart picframe.service after successful sync
• Log actions to: ~/logs/frame_sync_YYYY-MM-DD.log

Each run ends with:

SYNC_RESULT: OK
SYNC_RESULT: NOOP
SYNC_RESULT: RESTART

These are used for SAFE_MODE decisions.

🛑 SAFE_MODE – Restart Loop Protection

SAFE_MODE triggers if the last 3 run results are:

SYNC_RESULT: RESTART
SYNC_RESULT: RESTART
SYNC_RESULT: RESTART

When triggered:
• Restart is suppressed
• A disable flag file is created:
ops_tools/frame_sync.disabled

Manual runs can override SAFE_MODE.

🔍 chk_sync.sh — Source-Aware Verification

Features:

• Detect active remote using frame_live symlink
• Load metadata from config/frame_sources.conf
• Quick file count comparison
• Detailed mode (--d) uses rclone check
• Appends results via chk_status.sh:
– Last sync
– Last service restart
– Last file download

These values appear on the dashboard.

🌐 Web Dashboard — Flask (port 5050)

Accessible at:

http://<pi-ip>:5050
http://kframe.local:5050

Dashboard architecture:

The dashboard uses separate CSS and JS files for better maintainability:
• static/css/dashboard.css – Modern dark theme styling
• static/js/dashboard.js – Interactive features and API calls

Dashboard API endpoints:

• /api/status – JSON status for all displayed data
• /api/run-check – Execute chk_sync.sh --d on demand
• /api/config (GET) – Retrieve current configuration
• /api/config (POST) – Save configuration changes
• /api/config/test-remote – Test rclone remote connectivity
• /api/config/export – Download config file as backup
• /api/sources – List available photo sources
• /api/sources/active – Switch active photo source

Dashboard sections:

✔ Banner

• MATCH / MISMATCH / ERROR
• Color-coded
• Last updated timestamp

✔ File Counts

• Remote file count
• Local file count
• Current source (gdt/kfr)

✔ Services

• Web dashboard service status
• picframe.service status
• Colored dots

✔ Activity & Tools

• Last run (timestamp)
• Last service restart (timestamp only)
• Last file download (timestamp only)
• Log tail (show/hide)
• Run chk_sync.sh --d with full output

✔ Settings Panel

• Configuration editor with validation
• Test rclone connection before saving
• Export config as backup file
• Live validation feedback
• Secure config file management

✔ Source Switcher

• Toggle between photo sources (Google Drive, Koofr, etc.)
• View enabled sources from frame_sources.conf
• Switch sources with single click
• Automatic service restart after switch

🧱 frame_sync_cron.sh

Used by cron.
Behavior:

• Prevents running if SAFE_MODE disable file exists
• Runs production sync script
• Logs output

Recommended cron entry:

*/15 * * * * /home/pi/picframe_3.0/app_control/frame_sync_cron.sh

🧪 Test Scripts

t_frame_sync.sh — safe testable version
t_chk_sync.sh — safe testable version

Promote to production:

promote_to_prod.sh

🚀 promote_to_prod.sh (PC Only)

Performs:

• Archives old production scripts (keeps 10)
• Promotes all t_*.sh to production versions
• Commits + pushes to GitHub
• Hard-blocks execution on the Pi

After running promotion, update Pi using update_app.sh.

🔁 update_app.sh — Update Pi from GitHub

Runs on the Pi only.

Tasks:

• Pull newest GitHub code
• Install crontab template
• Restart picframe.service
• Restart pf-web-status.service

This is the only supported update mechanism on the Pi.

🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for:
• Security guidelines and best practices
• Code quality standards
• Testing requirements
• Development workflow
• Pull request process

Priority areas: Authentication, HTTPS/TLS, input validation, atomic file writes

📝 Notes

Logs are stored in:

~/logs/frame_sync_YYYY-MM-DD.log

Ensure rclone permissions:

sudo chown pi:pi ~/.config/rclone/rclone.conf
sudo chmod 600 ~/.config/rclone/rclone.conf

🧠 Git Shortcuts

git sync
git quick
git commit

© 2025 Matt P. – PicFrame 3.0 Project
