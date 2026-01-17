#!/bin/bash
set -euo pipefail

LOG_FILE="$HOME/logs/frame_sync.log"
REPO_DIR="$HOME/picframe_3.0"
CRONTAB_FILE="$REPO_DIR/config/crontab"
SVC_CTL="$REPO_DIR/app_control/svc_ctl.sh"
SYSTEMD_USER_SRC="$REPO_DIR/systemd/user"
SYSTEMD_USER_DEST="$HOME/.config/systemd/user"
XSERVERRC_SRC="$REPO_DIR/config/xserverrc"
XSERVERRC_DEST="$HOME/.xserverrc"

log_message() {
    local message="$1"
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$(date '+%Y-%m-%d %H:%M:%S') update_app.sh - $message" | tee -a "$LOG_FILE" >&2
}

cleanup_pycache() {
    local target_dir="$REPO_DIR/web_status"

    if [[ -d "$target_dir" ]]; then
        log_message "Removing Python __pycache__ directories under $target_dir"
        # Print the directories we are removing to the log, then delete them
        find "$target_dir" -type d -name "__pycache__" -print -exec rm -rf {} +
    else
        log_message "web_status directory not found at $target_dir (skipping __pycache__ cleanup)"
    fi
}

install_xserverrc() {
    if [[ ! -f "$XSERVERRC_SRC" ]]; then
        log_message "No xserverrc in repo; skipping."
        return
    fi

    if [[ ! -f "$XSERVERRC_DEST" ]] || ! cmp -s "$XSERVERRC_SRC" "$XSERVERRC_DEST"; then
        log_message "Installing xserverrc to suppress Xorg log bloat..."
        cp "$XSERVERRC_SRC" "$XSERVERRC_DEST"
        chmod +x "$XSERVERRC_DEST"
    fi
}

install_systemd_user_services() {
    if [[ ! -d "$SYSTEMD_USER_SRC" ]]; then
        log_message "No systemd/user directory in repo; skipping systemd install."
        return
    fi

    # Create destination directory if needed
    mkdir -p "$SYSTEMD_USER_DEST"

    local updated=0
    for service_file in "$SYSTEMD_USER_SRC"/*.service; do
        [[ -f "$service_file" ]] || continue
        local filename
        filename=$(basename "$service_file")
        local dest_file="$SYSTEMD_USER_DEST/$filename"

        # Only update if file differs or doesn't exist
        if [[ ! -f "$dest_file" ]] || ! cmp -s "$service_file" "$dest_file"; then
            log_message "Installing systemd user service: $filename"
            cp "$service_file" "$dest_file"
            updated=1
        fi
    done

    if [[ $updated -eq 1 ]]; then
        log_message "Reloading systemd user daemon..."
        systemctl --user daemon-reload
    fi
}

log_message "===== Starting app update ====="

# Make sure the repo exists
if [[ ! -d "$REPO_DIR/.git" ]]; then
    log_message "Repository directory $REPO_DIR does not look like a git repo. Aborting."
    exit 1
fi

cd "$REPO_DIR"

# Initialize config files from templates if they don't exist
initialize_configs() {
    local config_file="$REPO_DIR/config/frame_sources.conf"
    local template_file="$REPO_DIR/config/frame_sources.conf.example"

    if [[ ! -f "$config_file" && -f "$template_file" ]]; then
        log_message "First run: Creating config/frame_sources.conf from template..."
        cp "$template_file" "$config_file"
        log_message "Config file created. Edit it to add your photo sources."
    fi
}

# Update repo from origin/main
log_message "Fetching latest changes from origin..."
if git fetch --all >>"$LOG_FILE" 2>&1; then
    log_message "git fetch completed."
else
    log_message "git fetch failed."
    exit 1
fi

log_message "Resetting to origin/main (preserving ignored config files)..."
# Use reset --hard to force update, ignored files (configs) are preserved automatically
if git reset --hard origin/main >>"$LOG_FILE" 2>&1; then
    log_message "Repository updated successfully."
else
    log_message "git reset failed. Manual intervention may be needed."
    exit 1
fi

# Initialize configs if needed (for first-time setup)
initialize_configs

# Clean up any stale Python bytecode in the web_status app
cleanup_pycache

# Ensure all control and ops scripts are executable
log_message "Ensuring shell scripts in app_control and ops_tools are executable..."
find "$REPO_DIR/app_control" -type f -name "*.sh" -exec chmod +x {} \; >>"$LOG_FILE" 2>&1 || log_message "chmod failed under app_control"
find "$REPO_DIR/ops_tools"   -type f -name "*.sh" -exec chmod +x {} \; >>"$LOG_FILE" 2>&1 || log_message "chmod failed under ops_tools"

# Install crontab from repo, if present
if [[ -f "$CRONTAB_FILE" ]]; then
    log_message "Installing crontab from $CRONTAB_FILE"
    if crontab "$CRONTAB_FILE" >>"$LOG_FILE" 2>&1; then
        log_message "Crontab install completed."
    else
        log_message "Crontab install failed."
    fi
else
    log_message "Crontab file $CRONTAB_FILE not found; skipping cron install."
fi

# Install systemd user services from repo
install_systemd_user_services

# Install xserverrc to suppress Xorg log bloat
install_xserverrc

# Restart picframe viewer service (user service via wrapper)
if [[ -x "$SVC_CTL" ]]; then
    log_message "Restarting PicFrame service via $SVC_CTL -pr..."
    if "$SVC_CTL" -pr; then
        log_message "PicFrame service restart completed."
    else
        log_message "PicFrame restart script returned non-zero exit code."
    fi
else
    log_message "Service control script not found or not executable."
fi

# Restart web status dashboard (system service via wrapper)
if [[ -x "$SVC_CTL" ]]; then
    log_message "Restarting web status dashboard via $SVC_CTL -wr..."
    if "$SVC_CTL" -wr; then
        log_message "Dashboard restart completed."
    else
        log_message "Dashboard restart script returned non-zero exit code."
    fi
else
    log_message "Service control script not found or not executable."
fi

log_message "===== App update completed successfully ====="
exit 0
