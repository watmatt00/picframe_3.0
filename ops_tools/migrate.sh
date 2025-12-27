#!/bin/bash
#
# migrate.sh - PicFrame 3.0 Migration Tool
# Migrates legacy flat installations to git-managed structure
#
# Recommended Workflow:
#   1. ssh to your Raspberry Pi
#   2. git clone https://github.com/watmatt00/picframe_3.0.git
#   3. cd picframe_3.0/ops_tools
#   4. ./migrate.sh              (runs Phase 1 - prep)
#   5. Test new installation
#   6. ./migrate.sh              (runs Phase 2 - cleanup)
#
# Usage:
#   ./migrate.sh              Auto-detect state and run next phase
#   ./migrate.sh --status     Show current migration state
#   ./migrate.sh --force-prep Force run preparation phase
#   ./migrate.sh --force-cleanup Force run cleanup phase
#   ./migrate.sh --help       Show usage information
#
# Note: Script supports both manual git clone (recommended) and automatic clone
#

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LEGACY_SYNC_SCRIPT="$HOME/frame_sync.sh"
NEW_APP_ROOT="$HOME/picframe_3.0"
MIGRATION_CACHE="$HOME/.picframe_migration_cache"
REPO_URL="https://github.com/watmatt00/picframe_3.0"

# ==========================================
# STATE DETECTION
# ==========================================

detect_state() {
    # State 1: Legacy installation (not migrated yet)
    # Check for legacy files first, regardless of repo state
    # This handles both: manual clone before migration, and no clone yet
    if [[ -f "$LEGACY_SYNC_SCRIPT" ]] && [[ ! -d "$MIGRATION_CACHE" ]]; then
        echo "legacy"
        return 0
    fi
    
    # State 2: Prep completed, needs testing/cleanup
    if [[ -d "$MIGRATION_CACHE" ]] && [[ -d "$NEW_APP_ROOT/.git" ]]; then
        echo "testing"
        return 0
    fi
    
    # State 3: Already migrated and cleaned
    # Must have repo, no cache, AND no legacy files
    if [[ -d "$NEW_APP_ROOT/.git" ]] && [[ ! -d "$MIGRATION_CACHE" ]] && [[ ! -f "$LEGACY_SYNC_SCRIPT" ]]; then
        echo "complete"
        return 0
    fi
    
    # State 4: Unknown/inconsistent
    echo "unknown"
    return 1
}

show_status() {
    local state=$(detect_state)
    
    echo "========================================"
    echo "PicFrame Migration Status"
    echo "========================================"
    echo ""
    
    case "$state" in
        legacy)
            echo "Status: LEGACY INSTALLATION"
            echo "  → Migration has not started"
            echo ""
            if [[ -d "$NEW_APP_ROOT/.git" ]]; then
                echo "  ✓ Repository already cloned (manual setup detected)"
                echo ""
            fi
            echo "Next step: Run ./migrate.sh to begin migration"
            ;;
        testing)
            echo "Status: TESTING PHASE"
            echo "  → New system installed, awaiting validation"
            echo ""
            echo "Next steps:"
            echo "  1. Test the new installation"
            echo "  2. Run ./migrate.sh to complete cleanup"
            echo ""
            echo "Rollback available at: $MIGRATION_CACHE/crontab.bak"
            ;;
        complete)
            echo "Status: MIGRATION COMPLETE"
            echo "  → System fully migrated to picframe_3.0"
            ;;
        unknown)
            echo "Status: UNKNOWN STATE"
            echo ""
            echo "System state is inconsistent:"
            echo "  - Legacy sync: $([ -f "$LEGACY_SYNC_SCRIPT" ] && echo "EXISTS" || echo "missing")"
            echo "  - New repo:    $([ -d "$NEW_APP_ROOT/.git" ] && echo "EXISTS" || echo "missing")"
            echo "  - Cache:       $([ -d "$MIGRATION_CACHE" ] && echo "EXISTS" || echo "missing")"
            echo ""
            echo "Manual intervention may be required."
            ;;
    esac
    echo "========================================"
}

# ==========================================
# PHASE 1: PREPARATION
# ==========================================

run_prep_phase() {
    echo "========================================"
    echo "PicFrame Migration - Phase 1: PREP"
    echo "========================================"
    echo ""

    preflight_checks
    check_legacy_exists
    extract_legacy_config
    verify_rclone_config
    check_or_clone_repo
    generate_new_config_files
    initialize_frame_live_symlink
    setup_flask_service
    set_proper_permissions
    update_crontab_entries
    show_testing_instructions
}

preflight_checks() {
    echo "Running pre-flight checks..."
    
    local errors=0
    
    # Check if sudo is available
    if ! command -v sudo &>/dev/null; then
        echo "  ✗ sudo not found (needed for service setup)"
        ((errors++))
    else
        echo "  ✓ sudo available"
    fi
    
    # Check if systemctl is available
    if ! command -v systemctl &>/dev/null; then
        echo "  ✗ systemctl not found (systemd required)"
        ((errors++))
    else
        echo "  ✓ systemd available"
    fi
    
    # Check if apt-get is available
    if ! command -v apt-get &>/dev/null; then
        echo "  ✗ apt-get not found (Debian/Ubuntu required)"
        ((errors++))
    else
        echo "  ✓ apt-get available"
    fi
    
    if [[ $errors -gt 0 ]]; then
        echo ""
        echo "ERROR: $errors pre-flight check(s) failed"
        echo "Please install missing dependencies and try again."
        exit 1
    fi
    
    echo "✓ All pre-flight checks passed"
    echo ""
}

check_legacy_exists() {
    if [[ ! -f "$LEGACY_SYNC_SCRIPT" ]]; then
        echo "ERROR: Cannot find legacy frame_sync.sh at $LEGACY_SYNC_SCRIPT"
        echo ""
        echo "This script is for migrating from old flat installations."
        echo "If you're setting up fresh, use the web dashboard instead."
        exit 1
    fi
    
    echo "✓ Detected legacy installation at $LEGACY_SYNC_SCRIPT"
}

check_or_clone_repo() {
    echo ""
    
    # Check if repository already exists
    if [[ -d "$NEW_APP_ROOT/.git" ]]; then
        echo "✓ Repository already exists at $NEW_APP_ROOT"
        echo "  Skipping git clone (assuming manual installation)"
        
        # Verify it's actually the picframe_3.0 repo
        if [[ -f "$NEW_APP_ROOT/ops_tools/migrate.sh" ]]; then
            echo "✓ Repository structure verified"
        else
            echo "ERROR: Directory exists but doesn't appear to be picframe_3.0"
            echo "  Missing: $NEW_APP_ROOT/ops_tools/migrate.sh"
            echo ""
            echo "Please remove and re-clone:"
            echo "  rm -rf $NEW_APP_ROOT"
            echo "  git clone $REPO_URL"
            exit 1
        fi
        
        return 0
    fi
    
    # Repository doesn't exist, need to clone it
    echo "Repository not found. Will clone from GitHub..."
    ensure_git_installed
    setup_git_and_clone_repo
}

extract_legacy_config() {
    echo ""
    echo "Extracting configuration from $LEGACY_SYNC_SCRIPT..."
    
    mkdir -p "$MIGRATION_CACHE"
    
    # Parse RCLONE_REMOTE (case-insensitive, handles Rclone_remote, RCLONE_REMOTE)
    local remote=$(grep -iE '^\s*(RCLONE_REMOTE|Rclone_remote)\s*=' "$LEGACY_SYNC_SCRIPT" | \
                   grep -v '^#' | \
                   head -1 | \
                   sed -E 's/.*=\s*"?([^"[:space:]]+)"?.*/\1/' || true)
    
    # Parse LDIR
    local ldir=$(grep -iE '^\s*LDIR\s*=' "$LEGACY_SYNC_SCRIPT" | \
                 grep -v '^#' | \
                 head -1 | \
                 sed -E 's/.*=\s*"?([^"[:space:]]+)"?.*/\1/' || true)
    
    # Fallback 1: Extract from hardcoded rclone commands
    if [[ -z "$remote" ]]; then
        remote=$(grep -oE 'rclone (sync|ls|lsf) [^[:space:]]+:[^[:space:]]+' "$LEGACY_SYNC_SCRIPT" | \
                 head -1 | \
                 awk '{print $3}' || true)
    fi
    
    # Fallback 2: Get most common hardcoded remote
    if [[ -z "$remote" ]]; then
        remote=$(grep -oE '[a-zA-Z0-9_]+:[a-zA-Z0-9_/]+' "$LEGACY_SYNC_SCRIPT" | \
                 sort | uniq -c | sort -rn | head -1 | awk '{print $2}' || true)
    fi
    
    # Convert relative path to absolute
    if [[ "$ldir" == ./* ]]; then
        ldir="$HOME/${ldir#./}"
    elif [[ "$ldir" != /* ]]; then
        ldir="$HOME/$ldir"
    fi
    
    # Validation
    if [[ -z "$remote" ]] || [[ -z "$ldir" ]]; then
        echo "ERROR: Could not extract configuration from legacy script"
        echo ""
        echo "Found:"
        echo "  RCLONE_REMOTE: ${remote:-<not found>}"
        echo "  LOCAL_DIR: ${ldir:-<not found>}"
        echo ""
        echo "Please check $LEGACY_SYNC_SCRIPT and try again."
        exit 1
    fi
    
    # Save to cache
    cat > "$MIGRATION_CACHE/extracted.conf" <<EOF
RCLONE_REMOTE="$remote"
LOCAL_DIR="$ldir"
EOF
    
    echo "✓ Configuration extracted:"
    echo "    RCLONE_REMOTE = $remote"
    echo "    LOCAL_DIR     = $ldir (converted to absolute)"
}

verify_rclone_config() {
    echo ""
    echo "Verifying rclone configuration..."
    
    local rclone_conf="$HOME/.config/rclone/rclone.conf"
    
    if [[ ! -f "$rclone_conf" ]]; then
        echo "✗ ERROR: rclone config not found at $rclone_conf"
        echo ""
        echo "You must configure rclone before migration:"
        echo "  rclone config"
        exit 1
    fi
    
    # Check permissions
    local perms=$(stat -c "%a" "$rclone_conf" 2>/dev/null || echo "unknown")
    if [[ "$perms" != "600" ]]; then
        echo "⚠ WARNING: rclone.conf has insecure permissions: $perms"
        echo "  Fixing permissions to 600..."
        chmod 600 "$rclone_conf"
    fi
    
    echo "✓ rclone configuration exists with secure permissions (600)"
    
    # Test if the remote is accessible
    source "$MIGRATION_CACHE/extracted.conf"
    echo "  Testing remote access: $RCLONE_REMOTE"
    if rclone lsf "$RCLONE_REMOTE" --max-depth 1 &>/dev/null; then
        local file_count=$(rclone lsf "$RCLONE_REMOTE" --files-only 2>/dev/null | wc -l)
        echo "✓ rclone remote accessible ($file_count files found)"
    else
        echo "✗ WARNING: Cannot access remote: $RCLONE_REMOTE"
        echo "  Check your rclone configuration"
        echo ""
        read -p "Continue anyway? [y/N] " -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

ensure_git_installed() {
    echo ""
    
    if command -v git &>/dev/null; then
        echo "✓ Git already installed ($(git --version))"
        return 0
    fi
    
    echo "Git not found. Installing..."
    
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y git
    else
        echo "ERROR: Cannot auto-install git. Please install manually:"
        echo "  sudo apt-get install git"
        exit 1
    fi
    
    echo "✓ Git installed successfully"
}

setup_git_and_clone_repo() {
    echo ""
    echo "Setting up git repository..."
    
    # Configure git if not already done
    if [[ -z "$(git config --global user.email 2>/dev/null || true)" ]]; then
        echo ""
        read -p "Enter your email for git: " git_email
        git config --global user.email "$git_email"
        echo "✓ Git email configured"
    fi
    
    if [[ -z "$(git config --global user.name 2>/dev/null || true)" ]]; then
        echo ""
        read -p "Enter your name for git: " git_name
        git config --global user.name "$git_name"
        echo "✓ Git name configured"
    fi
    
    # Clone repo
    echo ""
    echo "Cloning repository from $REPO_URL..."
    cd "$HOME"
    
    if ! git clone "$REPO_URL" picframe_3.0; then
        echo ""
        echo "ERROR: Failed to clone repository"
        echo "Please check your internet connection and try again."
        exit 1
    fi
    
    echo "✓ Repository cloned to $NEW_APP_ROOT"
}

generate_new_config_files() {
    echo ""
    echo "Generating new configuration files..."

    # Source extracted config
    source "$MIGRATION_CACHE/extracted.conf"

    # Determine current hostname and user
    local current_host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "")
    local current_user=$(whoami)

    # 1. Create ~/.picframe/config with ALL keys Flask expects
    mkdir -p "$HOME/.picframe"

    cat > "$HOME/.picframe/config" <<EOF
# ~/.picframe/config - PicFrame Configuration
# Migrated from legacy installation on $(date)
#
# This file is read by:
#   - Flask web dashboard (config_manager.py)
#   - All ops_tools scripts (config_loader.sh)

# ============================================================
# REQUIRED SETTINGS (Flask will not start without these)
# ============================================================

RCLONE_REMOTE="$RCLONE_REMOTE"
LOCAL_DIR="$LOCAL_DIR"

# ============================================================
# OPTIONAL SETTINGS (Flask has defaults for these)
# ============================================================

# Where picframe_3.0 is installed
APP_ROOT="$NEW_APP_ROOT"

# Where logs are stored
LOG_DIR="$HOME/logs"

# Safety checks (empty = disabled)
ALLOWED_HOST="$current_host"
ALLOWED_USER="$current_user"

# Active photo source (set via pf_source_ctl.sh)
ACTIVE_SOURCE=""

# Symlink for active photo directory
FRAME_LIVE_PATH="$HOME/Pictures/frame_live"
EOF

    echo "✓ Created ~/.picframe/config"

    # 2. Verify Flask can parse the config
    if python3 -c "
import sys
sys.path.insert(0, '$NEW_APP_ROOT/web_status')
from config_manager import config_exists, read_config, validate_config

if not config_exists():
    print('ERROR: Config file not found')
    sys.exit(1)

config = read_config()
validation = validate_config(config)

if validation['errors']:
    print('ERROR: Config validation failed:')
    for error in validation['errors']:
        print('  -', error)
    sys.exit(1)

print('✓ Config validated successfully')
" 2>&1 | grep -q "✓"; then
        echo "✓ Flask config validated"
    else
        echo "⚠ WARNING: Flask config validation had issues (may still work)"
    fi

    # 3. Generate frame_sources.conf (Flask reads this for source list)
    local dirname=$(basename "$LOCAL_DIR")
    local source_id="${dirname%%_*}"

    # If source_id is empty or same as dirname, use first 3 chars
    if [[ -z "$source_id" ]] || [[ "$source_id" == "$dirname" ]]; then
        source_id="${dirname:0:3}"
    fi

    cat > "$NEW_APP_ROOT/config/frame_sources.conf" <<EOF
# -------------------------------------------------------------------
# frame_sources.conf
#
# Defines all available photo sources for PicFrame.
# Format: id|label|absolute_path|enabled|rclone_remote
#
# This file is read by:
#   - Flask web dashboard (status_backend.py)
#   - chk_sync.sh (ops_tools)
#   - pf_source_ctl.sh (ops_tools)
# -------------------------------------------------------------------

${source_id}|Migrated Source (${dirname})|${LOCAL_DIR}|1|${RCLONE_REMOTE}

# Add more sources here as needed:
# example|Example Source|/home/pi/Pictures/example|0|remote:path
EOF

    echo "✓ Created $NEW_APP_ROOT/config/frame_sources.conf"

    # 4. Ensure log directory exists (Flask needs to read logs)
    mkdir -p "$HOME/logs"
    echo "✓ Ensured log directory exists: $HOME/logs"

    # 5. Create initial log file if it doesn't exist
    if [[ ! -f "$HOME/logs/frame_sync.log" ]]; then
        cat > "$HOME/logs/frame_sync.log" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') migrate.sh - Initial log file created by migration
$(date '+%Y-%m-%d %H:%M:%S') migrate.sh - Flask web dashboard will read from this file
EOF
        echo "✓ Created initial log file"
    fi
}

initialize_frame_live_symlink() {
    echo ""
    echo "Initializing frame_live symlink..."

    # Source extracted config to get LOCAL_DIR
    source "$MIGRATION_CACHE/extracted.conf"

    local pictures_dir="$HOME/Pictures"
    local frame_live_path="$HOME/Pictures/frame_live"

    # Ensure Pictures directory exists
    if [[ ! -d "$pictures_dir" ]]; then
        mkdir -p "$pictures_dir"
        echo "  Created $pictures_dir"
    fi

    # Create frame_live symlink pointing to migrated source
    if [[ -L "$frame_live_path" ]] || [[ -e "$frame_live_path" ]]; then
        echo "  Removing existing frame_live..."
        rm -f "$frame_live_path"
    fi

    if [[ -d "$LOCAL_DIR" ]]; then
        ln -s "$LOCAL_DIR" "$frame_live_path"
        echo "✓ Created frame_live symlink: $frame_live_path -> $LOCAL_DIR"
    else
        echo "⚠ WARNING: LOCAL_DIR does not exist yet: $LOCAL_DIR"
        echo "  Creating directory structure..."
        mkdir -p "$LOCAL_DIR"
        ln -s "$LOCAL_DIR" "$frame_live_path"
        echo "✓ Created frame_live symlink: $frame_live_path -> $LOCAL_DIR"
        echo "  Note: Directory is empty - run sync to populate with photos"
    fi
}

setup_flask_service() {
    echo ""
    echo "Setting up Flask web dashboard service..."
    
    # 1. Verify Python3 and find its location
    local python_path=$(command -v python3 || true)
    if [[ -z "$python_path" ]] || [[ ! -x "$python_path" ]]; then
        echo "ERROR: python3 not found in PATH"
        echo "Please install Python 3: sudo apt-get install python3"
        exit 1
    fi
    echo "  Using Python: $python_path ($(python3 --version))"
    
    # 2. Install Flask via apt (matching working Pi)
    if python3 -c "import flask" 2>/dev/null; then
        local flask_version=$(python3 -c "import flask; print(flask.__version__)" 2>/dev/null || echo "unknown")
        echo "✓ Flask already installed (version $flask_version)"
    else
        echo "  Installing Flask via apt..."
        
        if sudo apt-get update -qq && sudo apt-get install -y python3-flask; then
            echo "✓ Flask installed via apt"
        else
            echo "ERROR: Failed to install python3-flask"
            echo "Try manually: sudo apt-get install python3-flask"
            exit 1
        fi
    fi
    
    # 3. Verify Flask app can load
    echo "  Verifying Flask app dependencies..."
    if python3 -c "
import sys
sys.path.insert(0, '$NEW_APP_ROOT/web_status')
from config_manager import read_config
from status_backend import get_status_payload
print('OK')
" 2>&1 | grep -q "OK"; then
        echo "✓ Flask app dependencies verified"
    else
        echo "ERROR: Flask app cannot load properly"
        echo "Check Python environment and dependencies"
        exit 1
    fi
    
    # 4. Create systemd service file (matching working Pi exactly)
    local service_file="/etc/systemd/system/pf-web-status.service"
    local current_user=$(whoami)
    
    echo "  Creating systemd service: $service_file"
    
    sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=PicFrame Web Status Dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$current_user
WorkingDirectory=$NEW_APP_ROOT/web_status
ExecStart=$python_path app.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # 5. Set proper permissions (match working Pi: 644 root:root)
    sudo chown root:root "$service_file"
    sudo chmod 644 "$service_file"
    echo "✓ Service file permissions set (644 root:root)"
    
    # 6. Reload systemd
    sudo systemctl daemon-reload
    
    # 7. Enable service
    echo ""
    read -p "Enable web dashboard to start on boot? [Y/n] " -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        sudo systemctl enable pf-web-status.service
        echo "✓ Service enabled (will start on boot)"
    else
        echo "  Service not enabled (manual start only)"
    fi
    
    # 8. Start service
    echo "  Starting web dashboard service..."
    if sudo systemctl start pf-web-status.service; then
        sleep 3  # Give it time to start
        
        # 9. Verify it's running
        if sudo systemctl is-active --quiet pf-web-status.service; then
            echo "✓ Web dashboard service started successfully"
            
            # Show URL
            local ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "<your-ip>")
            echo ""
            echo "  Dashboard URL: http://$ip:5050"
            echo ""
        else
            echo "WARNING: Service started but may not be running properly"
            echo "  Check status: sudo systemctl status pf-web-status.service"
            echo "  Check logs:   sudo journalctl -u pf-web-status.service -n 50"
        fi
    else
        echo "ERROR: Failed to start service"
        echo "  Check logs: sudo journalctl -u pf-web-status.service -n 50"
        exit 1
    fi
}

set_proper_permissions() {
    echo ""
    echo "Setting file permissions (matching known good configuration)..."
    
    local current_user=$(whoami)
    
    # Config directory and file (755 dir, 644 file)
    chmod 755 "$HOME/.picframe"
    chmod 644 "$HOME/.picframe/config"
    chown -R $current_user:$current_user "$HOME/.picframe"
    echo "✓ Config permissions set (755 dir, 644 file)"
    
    # Rclone config (CRITICAL: must be 600)
    if [[ -f "$HOME/.config/rclone/rclone.conf" ]]; then
        chmod 600 "$HOME/.config/rclone/rclone.conf"
        chown $current_user:$current_user "$HOME/.config/rclone/rclone.conf"
        echo "✓ Rclone config secured (600 owner-only)"
    fi
    
    # Log directory (755 dir, 644 files)
    chmod 755 "$HOME/logs"
    if [[ -f "$HOME/logs/frame_sync.log" ]]; then
        chmod 644 "$HOME/logs/frame_sync.log"
    fi
    chown -R $current_user:$current_user "$HOME/logs"
    echo "✓ Log permissions set (755 dir, 644 files)"
    
    # Pictures directory (755)
    if [[ -d "$HOME/Pictures" ]]; then
        chmod 755 "$HOME/Pictures"
        find "$HOME/Pictures" -type d -exec chmod 755 {} \; 2>/dev/null || true
        chown -R $current_user:$current_user "$HOME/Pictures"
        echo "✓ Pictures directory permissions set (755)"
    fi
    
    # App directory (755)
    chmod 755 "$NEW_APP_ROOT"
    
    # Shell scripts: executable (755)
    find "$NEW_APP_ROOT/ops_tools" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
    find "$NEW_APP_ROOT/app_control" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
    echo "✓ Shell scripts set executable (755)"
    
    # Python files: not executable (644)
    find "$NEW_APP_ROOT/web_status" -type f -name "*.py" -exec chmod 644 {} \; 2>/dev/null || true
    echo "✓ Python files set readable (644)"
    
    # Config files (644)
    chmod 644 "$NEW_APP_ROOT/config/frame_sources.conf"
    if [[ -f "$NEW_APP_ROOT/config/config.example" ]]; then
        chmod 644 "$NEW_APP_ROOT/config/config.example"
    fi
    echo "✓ Config files set readable (644)"
    
    # Set ownership of entire app
    chown -R $current_user:$current_user "$NEW_APP_ROOT"
    echo "✓ App directory ownership set ($current_user:$current_user)"
}

update_crontab_entries() {
    echo ""
    echo "Updating crontab..."
    
    # Backup current crontab
    crontab -l > "$MIGRATION_CACHE/crontab.bak" 2>/dev/null || touch "$MIGRATION_CACHE/crontab.bak"
    
    local current_user=$(whoami)
    local uid=$(id -u)
    
    # Build new crontab
    {
        echo "# =========================================="
        echo "# PicFrame 3.0 Crontab - Migrated $(date '+%Y-%m-%d')"
        echo "# =========================================="
        echo ""
        echo "# Weekly reboot (Sunday 3am)"
        echo "0 3 * * 0 /sbin/reboot"
        echo ""
        echo "# Frame sync (every 15 minutes - recommended)"
        echo "*/15 * * * * $NEW_APP_ROOT/app_control/frame_sync_cron.sh"
        echo ""
        echo "# Display control (optional - uncomment to enable)"
        echo "# Sun-Thu: turn OFF at 22:45"
        echo "# 45 22 * * 0-4 DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/$uid /usr/bin/xrandr --output HDMI-1 --off"
        echo ""
        echo "# Fri-Sat: turn OFF at 23:45"
        echo "# 45 23 * * 5,6 DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/$uid /usr/bin/xrandr --output HDMI-1 --off"
        echo ""
        echo "# Mon-Fri: turn ON at 06:00"
        echo "# 0 6 * * 1-5 DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/$uid /usr/bin/xrandr --output HDMI-1 --mode 1920x1080 --rate 60"
        echo ""
        echo "# Sat-Sun: turn ON at 07:00"
        echo "# 0 7 * * 6,0 DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/$uid /usr/bin/xrandr --output HDMI-1 --mode 1920x1080 --rate 60"
        echo ""
        echo "# Legacy crontab backed up to: $MIGRATION_CACHE/crontab.bak"
    } | crontab -
    
    echo "✓ Crontab updated (15-minute sync, weekly reboot)"
    echo "  Backup saved to: $MIGRATION_CACHE/crontab.bak"
    echo "  Note: Changed from hourly to 15-minute sync (recommended)"
}

show_testing_instructions() {
    echo ""
    echo "=========================================="
    echo "Phase 1 Complete - Testing Required"
    echo "=========================================="
    echo ""
    echo "NEXT STEPS:"
    echo ""
    echo "1. Test sync manually:"
    echo "   cd $NEW_APP_ROOT/ops_tools"
    echo "   ./chk_sync.sh"
    echo ""
    echo "2. Check web dashboard:"
    echo "   Service: sudo systemctl status pf-web-status.service"
    echo "   URL:     http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo '<your-ip>'):5050"
    echo ""
    echo "3. Verify picframe service (if installed):"
    echo "   systemctl --user status picframe.service"
    echo ""
    echo "4. Monitor logs:"
    echo "   tail -f $HOME/logs/frame_sync.log"
    echo "   sudo journalctl -u pf-web-status.service -f"
    echo ""
    echo "5. When confirmed working, complete migration:"
    echo "   cd $NEW_APP_ROOT/ops_tools"
    echo "   ./migrate.sh"
    echo ""
    echo "ROLLBACK (if needed):"
    echo "   crontab $MIGRATION_CACHE/crontab.bak"
    echo "   sudo systemctl stop pf-web-status.service"
    echo "   (Old scripts remain in $HOME for safety)"
    echo "=========================================="
}

# ==========================================
# PHASE 2: CLEANUP
# ==========================================

run_cleanup_phase() {
    echo "========================================"
    echo "PicFrame Migration - Phase 2: CLEANUP"
    echo "========================================"
    echo ""
    
    verify_migration_cache
    confirm_working_or_exit
    cleanup_legacy_files
    cleanup_migration_cache
    
    echo ""
    echo "=========================================="
    echo "✓ Migration Complete!"
    echo "=========================================="
    echo ""
    echo "Your PicFrame 3.0 installation is ready."
    echo ""
    echo "Quick reference:"
    echo "  Status:     $NEW_APP_ROOT/ops_tools/chk_status.sh"
    echo "  Dashboard:  http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo '<your-ip>'):5050"
    echo "  README:     $NEW_APP_ROOT/README.md"
    echo "=========================================="
}

verify_migration_cache() {
    if [[ ! -d "$MIGRATION_CACHE" ]]; then
        echo "ERROR: No migration cache found at $MIGRATION_CACHE"
        echo ""
        echo "This suggests Phase 1 was not completed or already cleaned up."
        echo "Run './migrate.sh --status' to check current state."
        exit 1
    fi
    
    echo "✓ Found migration cache from Phase 1"
}

confirm_working_or_exit() {
    echo ""
    echo "This will DELETE legacy files from your home directory:"
    echo "  - $HOME/frame_sync.sh"
    echo "  - $HOME/chk_sync.sh"
    echo "  - $HOME/pf_restart_svc.sh"
    echo "  - $HOME/pf_start_svc.sh"
    echo "  - $HOME/pf_stop_svc.sh"
    echo "  - $HOME/frame_sync_cron.sh"
    echo ""
    echo "Before proceeding, confirm you have:"
    echo "  - Tested sync manually (./ops_tools/chk_sync.sh)"
    echo "  - Verified web dashboard works"
    echo "  - Checked cron is running"
    echo ""
    read -p "Confirmed everything works? [y/N] " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "No problem - keeping legacy files for now."
        echo ""
        echo "To rollback if needed:"
        echo "  crontab $MIGRATION_CACHE/crontab.bak"
        echo "  sudo systemctl stop pf-web-status.service"
        echo ""
        echo "Run './migrate.sh --status' to check current state."
        echo "Run './migrate.sh' again when ready to complete cleanup."
        exit 0
    fi
}

cleanup_legacy_files() {
    echo ""
    echo "Removing legacy files from home directory..."
    
    local files=(
        "$HOME/frame_sync.sh"
        "$HOME/chk_sync.sh"
        "$HOME/chk_status.sh"
        "$HOME/pf_restart_svc.sh"
        "$HOME/pf_start_svc.sh"
        "$HOME/pf_stop_svc.sh"
        "$HOME/frame_sync_cron.sh"
    )
    
    local removed=0
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            rm "$file"
            echo "  ✓ Removed $(basename "$file")"
            ((removed++))
        fi
    done
    
    if [[ $removed -eq 0 ]]; then
        echo "  (No legacy files found to remove)"
    else
        echo ""
        echo "✓ Removed $removed legacy file(s)"
    fi
}

cleanup_migration_cache() {
    echo ""
    echo "Removing migration cache..."
    rm -rf "$MIGRATION_CACHE"
    echo "✓ Migration cache removed"
}

# ==========================================
# MAIN ROUTER
# ==========================================

main() {
    local state=$(detect_state)
    local force_mode="${1:-}"
    
    # Handle flags
    case "$force_mode" in
        --status)
            show_status
            exit 0
            ;;
        --force-prep)
            run_prep_phase
            exit 0
            ;;
        --force-cleanup)
            run_cleanup_phase
            exit 0
            ;;
        --help|-h)
            echo "Usage: $SCRIPT_NAME [OPTIONS]"
            echo ""
            echo "PicFrame 3.0 Migration Tool"
            echo "Migrates legacy flat installations to git-managed structure"
            echo ""
            echo "Recommended Workflow:"
            echo "  1. ssh pi@your-raspberry-pi"
            echo "  2. git clone https://github.com/watmatt00/picframe_3.0.git"
            echo "  3. cd picframe_3.0/ops_tools"
            echo "  4. ./migrate.sh              # Phase 1: Prep"
            echo "  5. Test new installation (test sync, web dashboard, etc.)"
            echo "  6. ./migrate.sh              # Phase 2: Cleanup"
            echo ""
            echo "Options:"
            echo "  (none)            Auto-detect state and run next phase"
            echo "  --status          Show current migration state"
            echo "  --force-prep      Force run preparation phase"
            echo "  --force-cleanup   Force run cleanup phase"
            echo "  --help, -h        Show this help"
            echo ""
            echo "Notes:"
            echo "  - Script works whether you clone the repo manually or let it clone"
            echo "  - Manual clone is recommended (more transparent, easier to review)"
            echo "  - Legacy files are preserved until Phase 2 (safe rollback)"
            echo ""
            echo "For more information, see: $NEW_APP_ROOT/README.md"
            exit 0
            ;;
        "")
            # No flag, continue to auto-routing
            ;;
        *)
            echo "ERROR: Unknown option: $force_mode"
            echo "Run '$SCRIPT_NAME --help' for usage information."
            exit 1
            ;;
    esac
    
    # Auto-route based on state
    case "$state" in
        legacy)
            echo "Detected: Legacy installation"
            echo "Starting: Preparation phase"
            echo ""
            run_prep_phase
            ;;
        testing)
            echo "Detected: Testing phase"
            echo "Starting: Cleanup phase"
            echo ""
            run_cleanup_phase
            ;;
        complete)
            echo "Migration already complete!"
            echo ""
            show_status
            ;;
        unknown)
            echo "ERROR: Cannot determine migration state"
            echo ""
            show_status
            exit 1
            ;;
    esac
}

main "$@"
