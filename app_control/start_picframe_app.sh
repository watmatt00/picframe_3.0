#!/bin/bash
set -euo pipefail

LOG_FILE="$HOME/logs/frame_sync.log"
APP_LOG="$HOME/logs/picframe_app.log"

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') start_picframe_app.sh  - $message" | tee -a "$LOG_FILE" >&2
}

# Make sure logs directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log_message "Starting picframe app"

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

# Confirm picframe is installed
if ! python -c "import picframe" 2>/dev/null; then
    log_message "ERROR: picframe module not found in venv."
    log_message "       Run: source /home/pi/venv_picframe/bin/activate && pip install picframe"
    exit 1
fi

# Use wrapper script to enable HEIC support
WRAPPER_SCRIPT="$HOME/picframe_3.0/app_control/picframe_wrapper.py"

log_message "Launching picframe with HEIC support (logging to $APP_LOG)..."

# Run picframe via wrapper and capture its stdout/stderr
python "$WRAPPER_SCRIPT" >>"$APP_LOG" 2>&1 || {
    rc=$?
    log_message "ERROR: picframe exited with code $rc. See $APP_LOG for details."
    exit $rc
}

log_message "picframe exited cleanly."
