#!/bin/bash
# ============================================
# validate_config.sh
# Validate PicFrame configuration
# ============================================
#
# Usage:
#   ./validate_config.sh        # Check config and report issues
#   ./validate_config.sh -q     # Quiet mode (exit code only)
#
# Exit codes:
#   0 = Config is valid
#   1 = Config errors found
#   2 = Config file not found
# ============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUIET=false

if [[ "${1:-}" == "-q" ]]; then
    QUIET=true
fi

log() {
    if [[ "$QUIET" == "false" ]]; then
        echo "$@"
    fi
}

# -------------------------------------------------------------------
# Load config
# -------------------------------------------------------------------

# shellcheck source=../lib/config_loader.sh
source "${SCRIPT_DIR}/../lib/config_loader.sh"

log "=== PicFrame Config Validator ==="
log ""

if ! load_config 2>/dev/null; then
    log "ERROR: Config file not found at: $PICFRAME_CONFIG"
    log ""
    log "To set up PicFrame:"
    log "  1. Open the web dashboard at http://$(hostname -I 2>/dev/null | awk '{print $1}'):5050"
    log "  2. Complete the setup wizard"
    log ""
    log "Or configure manually:"
    log "  mkdir -p ~/.picframe"
    log "  cp ${SCRIPT_DIR}/../config/config.example ~/.picframe/config"
    log "  nano ~/.picframe/config"
    exit 2
fi

log "Config file: $PICFRAME_CONFIG"
log ""

# -------------------------------------------------------------------
# Validation
# -------------------------------------------------------------------

errors=0
warnings=0

log "Checking required settings..."

# RCLONE_REMOTE
if [[ -z "${RCLONE_REMOTE:-}" ]]; then
    log "  [ERROR] RCLONE_REMOTE is not set"
    ((errors++))
else
    log "  [OK] RCLONE_REMOTE = $RCLONE_REMOTE"
fi

# LOCAL_DIR
if [[ -z "${LOCAL_DIR:-}" ]]; then
    log "  [ERROR] LOCAL_DIR is not set"
    ((errors++))
else
    log "  [OK] LOCAL_DIR = $LOCAL_DIR"
fi

# APP_ROOT
if [[ -z "${APP_ROOT:-}" ]]; then
    log "  [WARN] APP_ROOT is not set (using default)"
    ((warnings++))
else
    log "  [OK] APP_ROOT = $APP_ROOT"
fi

log ""
log "Checking directories..."

# Check LOCAL_DIR exists
if [[ -n "${LOCAL_DIR:-}" ]]; then
    if [[ -d "$LOCAL_DIR" ]]; then
        log "  [OK] LOCAL_DIR exists"
    else
        log "  [WARN] LOCAL_DIR does not exist: $LOCAL_DIR"
        log "         It will be created on first sync"
        ((warnings++))
    fi
fi

# Check LOG_DIR exists
if [[ -n "${LOG_DIR:-}" ]]; then
    if [[ -d "$LOG_DIR" ]]; then
        log "  [OK] LOG_DIR exists"
    else
        log "  [WARN] LOG_DIR does not exist: $LOG_DIR"
        log "         It will be created on first sync"
        ((warnings++))
    fi
fi

# Check APP_ROOT exists
if [[ -n "${APP_ROOT:-}" ]]; then
    if [[ -d "$APP_ROOT" ]]; then
        log "  [OK] APP_ROOT exists"
    else
        log "  [ERROR] APP_ROOT does not exist: $APP_ROOT"
        ((errors++))
    fi
fi

log ""
log "Testing rclone remote..."

# Check if rclone is installed
if ! command -v rclone &>/dev/null; then
    log "  [ERROR] rclone is not installed"
    ((errors++))
else
    log "  [OK] rclone is installed"
    
    # Test rclone remote connectivity
    if [[ -n "${RCLONE_REMOTE:-}" ]]; then
        if rclone lsf "$RCLONE_REMOTE" --max-depth 1 &>/dev/null; then
            file_count=$(rclone lsf "$RCLONE_REMOTE" --files-only 2>/dev/null | wc -l)
            log "  [OK] Rclone remote is accessible ($file_count files)"
        else
            log "  [ERROR] Cannot access rclone remote: $RCLONE_REMOTE"
            log "         Check your rclone configuration with: rclone listremotes"
            ((errors++))
        fi
    fi
fi

log ""
log "Checking optional settings..."

# ALLOWED_HOST
if [[ -n "${ALLOWED_HOST:-}" ]]; then
    current_host="$(hostname -s 2>/dev/null || hostname 2>/dev/null)"
    if [[ "$current_host" == "$ALLOWED_HOST" ]]; then
        log "  [OK] ALLOWED_HOST = $ALLOWED_HOST (matches current host)"
    else
        log "  [WARN] ALLOWED_HOST = $ALLOWED_HOST (current host is $current_host)"
        ((warnings++))
    fi
else
    log "  [INFO] ALLOWED_HOST not set (hostname check disabled)"
fi

# ALLOWED_USER
if [[ -n "${ALLOWED_USER:-}" ]]; then
    current_user="$(id -un 2>/dev/null)"
    if [[ "$current_user" == "$ALLOWED_USER" ]]; then
        log "  [OK] ALLOWED_USER = $ALLOWED_USER (matches current user)"
    else
        log "  [WARN] ALLOWED_USER = $ALLOWED_USER (current user is $current_user)"
        ((warnings++))
    fi
else
    log "  [INFO] ALLOWED_USER not set (user check disabled)"
fi

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------

log ""
log "========================================="
if [[ $errors -eq 0 ]]; then
    log "Configuration is valid!"
    [[ $warnings -gt 0 ]] && log "($warnings warning(s) - see above)"
    exit 0
else
    log "Found $errors error(s) and $warnings warning(s)"
    log "Please fix the errors above and try again."
    exit 1
fi
