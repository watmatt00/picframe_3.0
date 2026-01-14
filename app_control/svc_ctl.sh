#!/bin/bash
# Unified Service Control Script for PicFrame 3.0
# Manages both picframe.service (user-level) and pf-web-status.service (system-level)
#
# Usage: svc_ctl.sh <service><action>
# Examples:
#   svc_ctl.sh -wr              # Web restart (compact)
#   svc_ctl.sh -web-restart     # Web restart (verbose)
#   svc_ctl.sh -pr              # PicFrame restart (compact)
#   svc_ctl.sh -picframe-start  # PicFrame start (verbose)
#
# Service identifiers: -p, -pf, -picframe (picframe) | -w, -web (web)
# Action identifiers: -s, -start (start) | -x, -stop (stop) | -r, -restart (restart)

set -euo pipefail

# Constants
PF_SERVICE="picframe.service"
WEB_SERVICE="pf-web-status.service"
LOG_FILE="$HOME/logs/frame_sync.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') svc_ctl.sh - $message" | tee -a "$LOG_FILE" >&2
}

# Function to clean up rogue processes on port 5050
cleanup_port_5050() {
    log_message "Checking for processes on port 5050"
    if sudo ss -tulpn | grep -q ':5050'; then
        log_message "Found process on port 5050, killing it"
        PID=$(sudo ss -tulpn | grep ':5050' | grep -oP 'pid=\K\d+' | head -1)
        if [ -n "$PID" ]; then
            sudo kill "$PID" 2>/dev/null || true
            sleep 1
        fi
    fi
}

# PicFrame service functions (user-level service)
start_picframe() {
    log_message "Starting ${PF_SERVICE}"
    if systemctl --user start "${PF_SERVICE}"; then
        echo "Service ${PF_SERVICE} started successfully"
        log_message "Service ${PF_SERVICE} started successfully"
    else
        echo "Failed to start ${PF_SERVICE}"
        log_message "Failed to start ${PF_SERVICE}"
        exit 1
    fi
}

stop_picframe() {
    log_message "Stopping ${PF_SERVICE}"
    if systemctl --user stop "${PF_SERVICE}"; then
        echo "Service ${PF_SERVICE} stopped successfully"
        log_message "Service ${PF_SERVICE} stopped successfully"
    else
        echo "Failed to stop ${PF_SERVICE}"
        log_message "Failed to stop ${PF_SERVICE}"
        exit 1
    fi
}

restart_picframe() {
    log_message "Restarting ${PF_SERVICE}"
    if systemctl --user restart "${PF_SERVICE}"; then
        echo "Service ${PF_SERVICE} restarted successfully"
        log_message "Service ${PF_SERVICE} restarted successfully"
    else
        echo "Failed to restart ${PF_SERVICE}"
        log_message "Failed to restart ${PF_SERVICE}"
        exit 1
    fi
}

# Web service functions (system-level service with port cleanup)
start_web() {
    cleanup_port_5050
    log_message "Starting ${WEB_SERVICE}"
    if sudo systemctl start "${WEB_SERVICE}"; then
        echo "Service ${WEB_SERVICE} started successfully"
        log_message "Service ${WEB_SERVICE} started successfully"
    else
        echo "Failed to start ${WEB_SERVICE}"
        log_message "Failed to start ${WEB_SERVICE}"
        exit 1
    fi
}

stop_web() {
    log_message "Stopping ${WEB_SERVICE}"
    if sudo systemctl stop "${WEB_SERVICE}"; then
        echo "Service ${WEB_SERVICE} stopped successfully"
        log_message "Service ${WEB_SERVICE} stopped successfully"
    else
        echo "Failed to stop ${WEB_SERVICE}"
        log_message "Failed to stop ${WEB_SERVICE}"
        exit 1
    fi
    cleanup_port_5050
}

restart_web() {
    log_message "Restarting ${WEB_SERVICE}"
    # Stop first (includes cleanup)
    log_message "Stopping ${WEB_SERVICE}"
    sudo systemctl stop "${WEB_SERVICE}" || true
    cleanup_port_5050
    # Then start (includes cleanup)
    log_message "Starting ${WEB_SERVICE}"
    if sudo systemctl start "${WEB_SERVICE}"; then
        echo "Service ${WEB_SERVICE} restarted successfully"
        log_message "Service ${WEB_SERVICE} restarted successfully"
    else
        echo "Failed to restart ${WEB_SERVICE}"
        log_message "Failed to restart ${WEB_SERVICE}"
        exit 1
    fi
}

# Usage information
print_usage() {
    cat << 'EOF'
Unified Service Control for PicFrame 3.0

Usage: svc_ctl.sh <service><action>

Service Identifiers:
  -p, -pf, -picframe    PicFrame display service (user-level)
  -w, -web              Web status dashboard (system-level)

Action Identifiers:
  -s, -start            Start the service
  -x, -stop             Stop the service
  -r, -restart          Restart the service

Examples (compact syntax):
  svc_ctl.sh -ps        Start PicFrame service
  svc_ctl.sh -px        Stop PicFrame service
  svc_ctl.sh -pr        Restart PicFrame service
  svc_ctl.sh -ws        Start web dashboard
  svc_ctl.sh -wx        Stop web dashboard
  svc_ctl.sh -wr        Restart web dashboard

Examples (verbose syntax):
  svc_ctl.sh -picframe-start
  svc_ctl.sh -web-restart
  svc_ctl.sh -p-restart
  svc_ctl.sh -w-stop

Note: Service and action can be combined in any order within the argument.
EOF
}

# Parse arguments to extract service and action
parse_args() {
    if [[ $# -ne 1 ]]; then
        echo "Error: Expected exactly 1 argument, got $#" >&2
        echo "" >&2
        print_usage
        exit 2
    fi

    local arg="$1"
    local service=""
    local action=""

    # Remove leading dash if present
    arg="${arg#-}"

    # Extract service identifier (check longest matches first to avoid false positives)
    if [[ "$arg" =~ picframe ]]; then
        service="picframe"
        # Remove matched service from arg for cleaner action parsing
        arg=$(echo "$arg" | sed -E 's/picframe//')
    elif [[ "$arg" =~ pf ]]; then
        service="picframe"
        arg=$(echo "$arg" | sed -E 's/pf//')
    elif [[ "$arg" =~ web ]]; then
        service="web"
        arg=$(echo "$arg" | sed -E 's/web//')
    elif [[ "$arg" =~ ^p ]]; then
        service="picframe"
        arg=$(echo "$arg" | sed -E 's/^p//')
    elif [[ "$arg" =~ ^w ]]; then
        service="web"
        arg=$(echo "$arg" | sed -E 's/^w//')
    fi

    # Clean up any leading/trailing dashes from arg
    arg=$(echo "$arg" | sed 's/^-*//' | sed 's/-*$//')

    # Extract action identifier (check longest matches first)
    if [[ "$arg" =~ restart ]]; then
        action="restart"
    elif [[ "$arg" =~ start ]]; then
        action="start"
    elif [[ "$arg" =~ stop ]]; then
        action="stop"
    elif [[ "$arg" =~ ^r ]]; then
        action="restart"
    elif [[ "$arg" =~ ^s ]]; then
        action="start"
    elif [[ "$arg" =~ ^x ]]; then
        action="stop"
    fi

    # Validate both service and action were found
    if [[ -z "$service" ]]; then
        echo "Error: No valid service identifier found in argument: $1" >&2
        echo "Valid service identifiers: -p, -pf, -picframe, -w, -web" >&2
        echo "" >&2
        print_usage
        exit 2
    fi

    if [[ -z "$action" ]]; then
        echo "Error: No valid action identifier found in argument: $1" >&2
        echo "Valid action identifiers: -s, -start, -x, -stop, -r, -restart" >&2
        echo "" >&2
        print_usage
        exit 2
    fi

    # Set global variables for use in main
    SERVICE="$service"
    ACTION="$action"
}

# Execute the requested operation
execute_operation() {
    local service="$1"
    local action="$2"

    log_message "Executing: ${service} ${action}"

    case "${service}-${action}" in
        picframe-start)
            start_picframe
            ;;
        picframe-stop)
            stop_picframe
            ;;
        picframe-restart)
            restart_picframe
            ;;
        web-start)
            start_web
            ;;
        web-stop)
            stop_web
            ;;
        web-restart)
            restart_web
            ;;
        *)
            echo "Error: Invalid service-action combination: ${service}-${action}" >&2
            exit 1
            ;;
    esac
}

# Main script logic
main() {
    # Parse arguments
    parse_args "$@"

    # Execute the operation
    execute_operation "$SERVICE" "$ACTION"
}

# Run main function
main "$@"
