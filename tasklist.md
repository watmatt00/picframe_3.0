# PicFrame 3.0 Task List

**Last Updated:** 2025-12-09  
**Project Status:** Active Development  
**Critical Security Issues:** 4 identified  

---

## 📋 LEGEND

- 🔴 **CRITICAL** - Security risk or system-breaking bug
- 🟠 **HIGH** - Reliability issue or important feature
- 🟡 **MEDIUM** - Enhancement or refactoring
- 🔵 **LOW** - Nice-to-have or future consideration
- ✅ **DONE** - Already implemented
- 🔄 **IN PROGRESS** - Currently being worked on
- ⚠️ **PARTIAL** - Partially implemented, needs completion

**Issue ID Format:** `[CATEGORY-###]` where category is SEC/REL/FEAT/TECH/DOC

---

## 🔴 CRITICAL PRIORITY (Fix Immediately)

### Security

- [ ] **[SEC-001]** Add authentication to web dashboard
  - **Current State:** Port 5050 open with NO auth - anyone on LAN has full control
  - **Files:** `web_status/app.py:269`
  - **Options:** 
    - Quick: HTTP Basic Auth (2-4 hours)
    - Better: Token-based API auth (1 day)
  - **Effort:** 4 hours
  - **Risk if not fixed:** High - malicious config changes, unauthorized access
  - **Blocks:** Production use, external access

- [ ] **[SEC-002]** Implement HTTPS/TLS for dashboard
  - **Current State:** HTTP only, credentials sent in clear text
  - **Relates to:** Existing task "Investigate and implement cert"
  - **Files:** `web_status/app.py`, systemd service config
  - **Options:**
    - Self-signed cert (1 hour)
    - Let's Encrypt with certbot (2-3 hours)
  - **Effort:** 2-3 hours
  - **Depends on:** SEC-001 (auth must exist first)
  - **Risk:** Medium - credential sniffing on LAN

- [ ] **[SEC-003]** Fix config file code injection vulnerability
  - **Current State:** `source "$PICFRAME_CONFIG"` executes arbitrary bash
  - **Files:** `lib/config_loader.sh:39`
  - **Fix:** Rewrite parser to read as data, not execute as code
  - **Effort:** 4-6 hours
  - **Impacts:** All scripts that use config_loader.sh
  - **Risk:** High - attacker with file access can run any command
  - **Blocks:** SEC-004, SEC-005

- [ ] **[SEC-004]** Add input validation to subprocess calls
  - **Current State:** User input passed to shell without sanitization
  - **Files:** 
    - `web_status/app.py:237` (source_id)
    - `web_status/app.py:147` (rclone remote)
  - **Fix:** Whitelist/regex validation before subprocess
  - **Effort:** 3-4 hours
  - **Risk:** Medium - command injection possible
  - **Depends on:** SEC-003

---

## 🟠 HIGH PRIORITY (Next Sprint)

### Reliability

- [ ] **[REL-001]** Add file locking to prevent race conditions
  - **Current State:** Multiple frame_sync.sh can run concurrently
  - **Files:** 
    - `ops_tools/frame_sync.sh` (primary)
    - `web_status/config_manager.py` (config writes)
  - **Fix:** Use flock for mutual exclusion
  - **Effort:** 2-3 hours
  - **Impact:** Prevents corrupt syncs, duplicate work
  - **Risk if not fixed:** Medium - sync corruption, wasted CPU

- [ ] **[REL-002]** Implement atomic config file writes
  - **Current State:** Config writes can be interrupted = corruption
  - **Files:** `web_status/config_manager.py:146`
  - **Fix:** Write to temp, atomic rename, backup old
  - **Effort:** 2 hours
  - **Impact:** Prevents config loss on power failure
  - **Risk if not fixed:** Low - rare but catastrophic

- [ ] **[REL-003]** Add rate limiting to API endpoints
  - **Current State:** API can be hammered, no protection
  - **Files:** `web_status/app.py` (all routes)
  - **Fix:** Add Flask-Limiter (5 req/sec per IP)
  - **Effort:** 1 hour
  - **Impact:** Prevents DoS, resource exhaustion
  - **Risk if not fixed:** Low - requires malicious actor on LAN

- [ ] **[REL-004]** Add monitoring/alerting system
  - **Current State:** Must manually check logs for failures
  - **Relates to:** Existing task "Investigate slack or discord for alerts"
  - **Options:**
    - Email notifications (simple)
    - Slack/Discord webhooks (better)
    - Prometheus + Grafana (enterprise)
  - **Effort:** 4-6 hours for Slack integration
  - **Priority:** Medium-High for production deployment

### Features

- [ ] **[FEAT-001]** Dashboard UI improvements
  - **Current State:** Source switcher exists but could be more intuitive
  - **Originally:** "Build button to change display folders"
  - **Files:** `web_status/templates/dashboard.html`
  - **Enhancements:** 
    - More prominent source switcher on main dashboard
    - Preview thumbnails for each source
    - Source metadata display (file count, last sync time)
    - Quick-switch buttons vs dropdown
  - **Effort:** 3-4 hours
  - **Nice-to-have:** Drag-and-drop source ordering

- [ ] **[FEAT-002]** Automated remote Pi updates via Git push hook
  - **Current State:** Manual SSH required to run update_app.sh
  - **Originally:** "Update pi remotely after code change"
  - **Goal:** After push to GitHub, automatically SSH to Pi and trigger update
  - **Implementation:**
    - GitHub Actions workflow with SSH key
    - Or: GitHub webhook → server → SSH to Pi
    - Or: Pi polls GitHub every N minutes
  - **Files:** 
    - New: `.github/workflows/deploy-to-pi.yml`
    - Modify: `ops_tools/update_app.sh` (add webhook listener option)
  - **Effort:** 4-6 hours
  - **Security considerations:** 
    - SSH key management
    - Only trigger on main branch
    - Validate commit signatures
  - **Depends on:** SEC-005 (git signature verification)

---

## 🟡 MEDIUM PRIORITY (This Quarter)

### Technical Debt

- [ ] **[TECH-001]** Consolidate duplicate service control scripts
  - **Current State:** 6 nearly-identical scripts in app_control/
  - **Files:** 
    - `pf_start_svc.sh`, `pf_stop_svc.sh`, `pf_restart_svc.sh`
    - `pf_web_start_svc.sh`, `pf_web_stop_svc.sh`, `pf_web_restart_svc.sh`
  - **Fix:** Single `service_ctl.sh <service> <action>` script
  - **Effort:** 3-4 hours
  - **Impact:** Easier maintenance, less duplication
  - **Priority:** Low urgency but high value

- [ ] **[TECH-002]** Remove hardcoded paths
  - **Current State:** `/home/pi/` hardcoded in 50+ locations
  - **Files:** Throughout codebase
  - **Fix:** Use config variables or `$HOME` consistently
  - **Effort:** 6-8 hours (find all instances, test)
  - **Impact:** Portability, easier testing
  - **Priority:** Do alongside other refactoring

- [ ] **[TECH-003]** Add automated test suite
  - **Current State:** No tests, manual verification only
  - **Framework:** pytest for Python, bats for bash
  - **Effort:** 2-3 days initial setup + ongoing
  - **Impact:** Catch regressions, confidence in changes
  - **Priority:** High value but can be incremental

- [ ] **[TECH-004]** Extract inline JavaScript to separate file
  - **Current State:** 1200 lines of JS in dashboard.html
  - **Files:** `web_status/templates/dashboard.html`
  - **Fix:** Move to `static/js/dashboard.js`
  - **Effort:** 1-2 hours
  - **Impact:** Easier debugging, better caching
  - **Priority:** Low urgency, good refactoring practice

- [ ] **[TECH-005]** Add caching to status backend
  - **Current State:** Every /api/status call runs chk_sync.sh (60s+)
  - **Files:** `web_status/status_backend.py:353`
  - **Fix:** Cache results for 10-15 seconds
  - **Effort:** 2 hours
  - **Impact:** Reduces CPU, faster API responses
  - **Priority:** Do before enabling external access

- [ ] **[TECH-006]** Schedule automatic updates via cron
  - **Current State:** update_app.sh exists but requires manual execution
  - **Status:** ⚠️ PARTIAL - Script exists, automation missing
  - **Originally:** "Add auto update from github"
  - **Action:** Add monthly cron job to run update_app.sh
  - **Implementation:**
    ```bash
    # Add to crontab (first Sunday of month at 3:30am)
    30 3 1-7 * 0 /home/pi/picframe_3.0/ops_tools/update_app.sh
    ```
  - **Files:** 
    - `config/crontab` (add entry)
    - `ops_tools/update_app.sh` (verify safe for unattended use)
  - **Effort:** 1 hour
  - **Considerations:**
    - Test mode first (dry-run)
    - Log rotation for update logs
    - Email notification on failure
    - Skip if disable flag exists
  - **Depends on:** SEC-005 (signature verification for safety)

### Security

- [ ] **[SEC-005]** Add git commit signature verification
  - **Current State:** update_app.sh blindly trusts origin/main
  - **Files:** `ops_tools/update_app.sh:49`
  - **Fix:** Verify GPG signatures before applying updates
  - **Effort:** 4-6 hours (setup signing, update script)
  - **Impact:** Prevents supply chain attacks
  - **Priority:** Important for production but low immediate risk
  - **Blocks:** TECH-006, FEAT-002

---

## 🔵 LOW PRIORITY (Future / Nice-to-Have)

### Features

- [ ] **[FEAT-003]** Implement kiosk mode
  - **Current State:** Not implemented
  - **From:** Existing task list
  - **Requirements:** Browser fullscreen, auto-start, no UI chrome
  - **Effort:** 3-4 hours
  - **Priority:** Enhancement for clean installation

- [ ] **[FEAT-004]** Investigate and implement API capabilities
  - **Current State:** Not implemented
  - **Originally:** "Add API integration" (vague)
  - **Updated Goal:** Explore how APIs could improve the application
  - **Questions to answer:**
    - What external services would benefit from API access?
    - What data should the API expose?
    - What code changes are needed for API support?
  - **Potential use cases:**
    - **External photo sources:** Flickr, Instagram, Unsplash APIs
    - **Home automation:** Trigger sync from Home Assistant, SmartThings
    - **Webhooks:** Notify other services when sync completes
    - **REST API:** Programmatic control of PicFrame from other apps
    - **Mobile app:** iOS/Android app to manage multiple PiFrames
    - **Calendar integration:** Display event photos automatically
  - **Code changes needed:**
    - Flask API versioning (`/api/v1/`)
    - API authentication/authorization (JWT tokens)
    - Rate limiting per API key
    - Webhook management (register/unregister endpoints)
    - Photo source plugin system
    - API documentation (Swagger/OpenAPI)
  - **Effort:** 
    - Investigation phase: 2-3 hours
    - Basic REST API: 6-8 hours
    - External service integration: 4-6 hours per service
    - Full plugin system: 2-3 days
  - **Priority:** Low - needs requirements gathering first
  - **Depends on:** SEC-001, SEC-004 (security foundation required)

- [ ] **[FEAT-005]** Add Raspberry Pi Connect integration
  - **Current State:** Not implemented
  - **From:** Existing task list
  - **Purpose:** Remote access without port forwarding
  - **Effort:** 2-3 hours (if using official RPI Connect)
  - **Priority:** Nice-to-have for remote management

### Documentation

- [ ] **[DOC-001]** Create architecture diagram
  - **Current State:** No visual documentation
  - **Format:** Mermaid.js in README.md or separate docs/
  - **Effort:** 2-3 hours
  - **Impact:** Easier onboarding for contributors

- [ ] **[DOC-002]** Write troubleshooting guide
  - **Current State:** No centralized troubleshooting docs
  - **Content:** Common failures, solutions, log interpretation
  - **Effort:** 3-4 hours
  - **Impact:** Reduces support burden

- [ ] **[DOC-003]** Document security/threat model
  - **Current State:** No security documentation
  - **Content:** Attack surfaces, mitigations, assumptions
  - **Effort:** 2-3 hours
  - **Impact:** Helps prioritize future security work

---

## ✅ COMPLETED / ALREADY IMPLEMENTED

- [x] **[FEAT-006]** Add sync config control to dashboard
  - **Status:** ✅ COMPLETE - Exists in dashboard.html settings panel
  - **Completed:** 2025-11-29 (per README updates)
  - **Features:** RCLONE_REMOTE, LOCAL_DIR, test connection, export

- [x] **[FEAT-007]** Dashboard moved to single template
  - **Status:** ✅ COMPLETE
  - **Completed:** 2025-11-29 (per README)

- [x] **[FEAT-008]** Service restart timestamp display
  - **Status:** ✅ COMPLETE
  - **Completed:** 2025-11-29 (per README)

- [x] **[FEAT-009]** Frame sync safe mode protection
  - **Status:** ✅ COMPLETE - Implemented in frame_sync.sh
  - **Completed:** 2025-11-28 (estimated from git history)

---

## 📝 CONTROL SCRIPT STANDARDS (Reference)

These are coding standards, not tasks. Keep as reference section.

### Required Elements for All Service Scripts

- ✅ Status verification after systemctl commands
- ✅ Error logging with details on failures
- ✅ Success confirmation in logs
- ✅ Proper exit codes (0=success, 1=error)
- ✅ Consistent timestamp format: `YYYY-MM-DD HH:MM:SS`
- ✅ Error handling with `set -euo pipefail`

### Standard Logging Pattern

Success messages format:
```
Service {service-name} {action} successfully
```

Examples:
- "Service picframe.service restarted successfully"
- "Service pf-web-status.service stopped successfully"

### Script Template

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

---

## 📊 SUMMARY STATISTICS

**Total Issues Identified:** 32  
**By Priority:**
- 🔴 Critical: 4 (Security focus)
- 🟠 High: 6 (Reliability + features)
- 🟡 Medium: 11 (Technical debt + automation)
- 🔵 Low: 7 (Future enhancements)
- ✅ Done: 4 (Already implemented)

**By Category:**
- Security: 5 items (4 critical, 1 medium)
- Reliability: 4 items (all high)
- Features: 5 items (2 high, 3 low)
- Technical Debt: 6 items (all medium)
- Documentation: 3 items (all low)

**Estimated Effort for Critical Items:** ~18-20 hours  
**Estimated Effort for High Priority:** ~19-26 hours  

**Recommended Sprint 1 (Next 2 Weeks):**
1. SEC-001 (Auth) - 4h
2. SEC-003 (Config injection) - 6h  
3. REL-001 (File locking) - 3h
4. TECH-005 (Status caching) - 2h

**Total Sprint 1:** ~15 hours

---

## 🎯 QUICK WINS (High Impact, Low Effort)

These can be done in < 2 hours each for immediate improvement:

1. **REL-003** - Add rate limiting (1 hour)
2. **TECH-004** - Extract inline JS (1-2 hours)
3. **SEC-002** - Self-signed cert (1 hour)
4. **REL-002** - Atomic writes (2 hours)
5. **TECH-006** - Add cron for auto-updates (1 hour)
