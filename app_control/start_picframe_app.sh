#!/bin/bash
set -euo pipefail

LOG_FILE="$HOME/logs/frame_sync.log"
APP_LOG="$HOME/logs/picframe_app.log"

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') start_picframe_app.sh  - $message" | tee -a "$LOG_FILE" >&2
}

log_message "Starting picframe app"

# Make sure logs directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Configure display power and screensaver; don't crash if xset fails
if ! xset -display :0 dpms 0 0 0 &>/dev/null; then
    log_message "WARNING: xset dpms failed (display may not be ready)."
fi
if ! xset -display :0 s off &>/dev/null; then
    log_message "WARNING: xset s off failed (display may not be ready)."
fi

# Activate virtualenv
if [[ -f /home/pi/venv_picframe/bin/activate ]]; then
    # shellcheck disable=SC1091
    source /home/pi/venv_picframe/bin/activate
    log_message "Activated venv at /home/pi/venv_picframe"
else
    log_message "ERROR: /home/pi/venv_picframe/bin/activate not found."
    exit 1
fi

# Confirm picframe is on PATH
if ! command -v picframe >/dev/null 2>&1; then
    log_message "ERROR: 'picframe' command not found in venv PATH."
    log_message "       Try reinstalling picframe inside the venv."
    exit 1
fi

log_message "Launching picframe (logging to $APP_LOG)..."

# Run picframe and capture its stdout/stderr
picframe >>"$APP_LOG" 2>&1 || {
    rc=$?
    log_message "ERROR: picframe exited with code $rc. See $APP_LOG for details."
    exit $rc
}

log_message "picframe exited cleanly."
