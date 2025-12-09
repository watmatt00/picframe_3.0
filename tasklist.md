# Control Script Standards

## Required Elements

- [ ] **Status verification** - Check if systemctl commands succeeded
- [ ] **Error logging** - Log failures with details when commands fail
- [ ] **Success confirmation** - Log success messages for visibility
- [ ] **Proper exit codes** - Return appropriate exit codes for success/failure
- [ ] **Consistent logging format** - Use `YYYY-MM-DD HH:MM:SS` timestamp format
- [ ] **Error handling** - Use `set -euo pipefail` but also log before exit

## Logging Pattern

Success messages should follow this pattern for service operations:
```
Service {service-name} {action} successfully
```

Examples:
- "Service picframe.service restarted successfully"
- "Service pf-web-status.service stopped successfully"

## Script Template

```bash
#!/bin/bash
set -euo pipefail

LOG_FILE="$HOME/logs/frame_sync.log"
mkdir -p "$HOME/logs"

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $(basename $0) - $message" | tee -a "$LOG_FILE" >&2
}

log_message "Starting operation"

if sudo systemctl restart service.name; then
    log_message "Service service.name restarted successfully"
    exit 0
else
    log_message "ERROR: Failed to restart service.name"
    exit 1
fi
```

## Tasks

- [ ] Build button to change display folders
- [ ] Investigate slack or discord for alerts and warnings
- [ ] Add auto update from github
- [ ] Add sync config control to dashboard
- [ ] Update pi remotely after code change
- [ ] Investigate and implement Raspberry Pi Connect to base pi install/config
- [ ] Implement kiosk mode
- [ ] Investigate and implement cert
