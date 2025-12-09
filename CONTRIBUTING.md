# Contributing to PicFrame 3.0

Thank you for considering contributing to PicFrame 3.0! This document provides guidelines and standards for contributing to the project.

## 📋 Before You Start

- Review the [README.md](README.md) for project overview and setup
- Check [tasklist.md](tasklist.md) for current priorities and known issues
- Read the security guidelines below before making changes

## 🔒 Security Guidelines

**IMPORTANT:** This project has identified critical security issues (see `tasklist.md`). All contributions must follow secure coding practices:

### Input Validation
- **Always validate user input** before passing to subprocess calls, shell commands, or file operations
- Use whitelists/regex validation for IDs, paths, and remote names
- Never directly interpolate user input into shell commands
- Sanitize all data received from web forms or API endpoints

### Command Injection Prevention
```bash
# ❌ BAD - vulnerable to injection
rclone ls "$user_provided_remote"

# ✅ GOOD - validate first
if [[ "$user_provided_remote" =~ ^[a-zA-Z0-9_-]+:[a-zA-Z0-9_/.-]+$ ]]; then
    rclone ls "$user_provided_remote"
else
    echo "Invalid remote format"
    exit 1
fi
```

### Configuration File Safety
- **Never use `source` on user-editable config files** (code injection risk)
- Parse config files as data, not executable code
- Use `grep`, `awk`, or Python's `configparser` instead of bash `source`
- The current `config_loader.sh` has a known vulnerability (SEC-003 in tasklist)

### File Operations
- Use **atomic writes** for config files (write to temp, then rename)
- Implement **file locking** (`flock`) to prevent race conditions
- Set proper permissions (600 for sensitive files like configs)
- Validate paths to prevent directory traversal attacks

### Web Dashboard Security
- Add authentication before deploying to production (SEC-001)
- Implement HTTPS/TLS for any external access (SEC-002)
- Use rate limiting on API endpoints
- Never log sensitive data (passwords, tokens, API keys)

## 🎯 Code Quality Standards

### Bash Scripts

All bash scripts must include:
```bash
#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures
```

### Required Elements for Service Control Scripts
- ✅ Status verification after systemctl commands
- ✅ Error logging with details on command failures
- ✅ Success confirmation messages
- ✅ Proper exit codes (0=success, 1=error)
- ✅ Consistent timestamp format: `YYYY-MM-DD HH:MM:SS`

### Logging Pattern
```bash
# Success format
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Service {name} {action} successfully"

# Error format
echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Failed to {action} {name}: {details}" >&2
```

### Error Handling
```bash
if systemctl start picframe.service; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Service picframe.service started successfully"
    exit 0
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Failed to start picframe.service" >&2
    systemctl status picframe.service >&2
    exit 1
fi
```

### Python Code Standards
- Follow PEP 8 style guide
- Use type hints where appropriate
- Add docstrings to all functions/classes
- Handle exceptions explicitly (don't use bare `except:`)
- Use `subprocess.run()` with explicit arguments (never `shell=True` with user input)

## 🧪 Testing Requirements

### Before Submitting
1. **Test on PC/tablet first** using test scripts (`t_frame_sync.sh`, `t_chk_sync.sh`)
2. Validate configuration: `bash ops_tools/validate_config.sh`
3. Check for linter errors (shellcheck for bash, pylint/flake8 for Python)
4. Test both success and failure cases
5. Verify log output is clear and actionable

### Test Script Usage
- Use `t_*.sh` scripts for development/testing
- Only promote to production after thorough testing
- Run `promote_to_prod.sh` from PC/tablet (never on Pi)

## 🔄 Development Workflow

### Branch Strategy
- `main` - Production-ready code, deployed to Pi
- Feature branches - For new features or bug fixes
- Test thoroughly before merging to `main`

### Git Workflow Aliases
Three custom git shortcuts are available:
- **`git quick`** - Auto-commit + sync workflow  
- **`git commit`** - Add all changes and auto-commit  
- **`git sync`** - Fetch, rebase, and push to main  

### Development Environment Rules

#### PC/Tablet (Development)
- ✅ Use test scripts: `t_frame_sync.sh`, `t_chk_sync.sh`
- ✅ Promote to production using: `promote_to_prod.sh`
- ❌ **Never run `update_app.sh` on PC/tablet**

#### Raspberry Pi (Production)
- ❌ **Never run `promote_to_prod.sh` on the Pi** (hard-blocked)
- ✅ Only update using: `update_app.sh`
- Pulls from GitHub and restarts services

## 📝 Commit Message Format

Use this standard format:
```
Brief descriptive title (50 chars or less)

Detailed explanation of changes:
- What was changed
- Why it was changed
- Any side effects or considerations

Closes: #issue-number (if applicable)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Commit Message Guidelines
- Use imperative mood ("Add feature" not "Added feature")
- First line is a summary, keep under 50 characters
- Reference issue numbers when applicable
- Explain *why* the change was made, not just *what* changed

## 📁 Project Structure

```
picframe_3.0/
├── app_control/         - Service control scripts (start/stop/restart)
│   ├── pf_*_svc.sh     - PicFrame service controls
│   └── pf_web_*_svc.sh - Web dashboard service controls
│
├── config/              - Configuration templates and source definitions
│   ├── config.example   - Template for user config
│   └── frame_sources.conf - Photo source definitions
│
├── lib/                 - Shared libraries
│   └── config_loader.sh - Config loading (⚠️ has known security issue)
│
├── ops_tools/           - Operational and maintenance tools
│   ├── migrate.sh       - Migration script for legacy installs
│   ├── frame_sync.sh    - Main sync script (production)
│   ├── chk_sync.sh      - Verification script (production)
│   ├── t_*.sh           - Test versions of scripts
│   ├── promote_to_prod.sh - Promote test scripts to production
│   └── update_app.sh    - Update Pi from GitHub
│
└── web_status/          - Flask dashboard application
    ├── app.py           - Flask backend with API endpoints
    ├── status_backend.py - Status checking logic
    ├── config_manager.py - Configuration read/write (⚠️ needs atomic writes)
    └── templates/       - HTML templates
```

## 🛠️ Common Development Tasks

### Adding a New Feature
1. Check `tasklist.md` to see if it's already planned
2. Create a test version first (e.g., `t_new_feature.sh`)
3. Test thoroughly on development machine
4. Add appropriate error handling and logging
5. Update documentation (README.md, CONTRIBUTING.md, or tasklist.md)
6. Promote to production using `promote_to_prod.sh`
7. Create pull request with clear description

### Fixing a Bug
1. Reproduce the issue in development environment
2. Check logs in `~/logs/` for error details
3. Fix in test script first
4. Verify fix resolves the issue
5. Check for similar issues in other scripts
6. Update with proper error handling
7. Add comments explaining the fix

### Modifying Configuration
1. Test config changes with `validate_config.sh`
2. Document new config options in README.md
3. Update `config/config.example` if adding new settings
4. Consider backward compatibility with existing configs

## 📊 Pull Request Process

1. **Create a descriptive PR title** - Summarize the change
2. **Fill out PR description** with:
   - What changed and why
   - Testing performed
   - Any breaking changes
   - Screenshots (if UI changes)
3. **Reference related issues** - Use `Closes #123` or `Relates to #456`
4. **Ensure CI passes** - All checks must be green
5. **Request review** - Wait for approval before merging

## 🎯 Priority Areas for Contribution

See `tasklist.md` for full details. High-priority items include:

### 🔴 Critical (Security)
- SEC-001: Add authentication to web dashboard
- SEC-002: Implement HTTPS/TLS
- SEC-003: Fix config file code injection vulnerability
- SEC-004: Add input validation to subprocess calls

### 🟠 High Priority (Reliability)
- REL-001: Add file locking to prevent race conditions
- REL-002: Implement atomic config file writes
- REL-003: Add rate limiting to API endpoints

### Quick Wins (< 2 hours each)
- Extract inline JavaScript to separate file
- Add rate limiting to API
- Implement atomic writes for config
- Add cron job for auto-updates

## 📚 Documentation Standards

When adding or modifying features:
- Update README.md if user-facing behavior changes
- Update CONTRIBUTING.md if development process changes
- Add inline comments for complex logic
- Update tasklist.md if completing or discovering issues
- Keep code comments current (remove outdated comments)

## 🔧 Development Tools

### Required
- `bash` 4.0+ (for array support)
- `python3` (for Flask dashboard)
- `rclone` (for cloud sync)
- `systemctl` (for service management)

### Recommended
- `shellcheck` - Bash linter (`sudo apt install shellcheck`)
- `pylint` or `flake8` - Python linters
- `git` with configured aliases (see Git Workflow section)

## ⚙️ Configuration

### Project Conventions
- Logs: `~/logs/frame_sync_YYYY-MM-DD.log`
- Config: `~/.picframe/config`
- Service port: **5050** (web dashboard)
- Test scripts: Use `t_` prefix
- Production scripts: No prefix

### File Permissions
```bash
# Config files (sensitive data)
chmod 600 ~/.picframe/config
chmod 600 ~/.config/rclone/rclone.conf

# Scripts (executable)
chmod 755 ops_tools/*.sh
chmod 755 app_control/*.sh
```

## 🤖 Claude Code Permissions

The project has auto-approval configured for specific commands (`.claude/settings.local.json`):
- `Bash(grep:*)` - All grep commands
- `Bash(git quick:*)` - Git quick workflow
- `Bash(git add:*)` - Git staging
- `Bash(git commit:*)` - Git commits (with specific format)
- `Bash(git push)` - Git push operations

## 💬 Getting Help

- Check existing issues on GitHub
- Review `tasklist.md` for known issues and priorities
- Look at similar scripts for examples
- Test changes in development environment first
- Ask questions in pull request discussions

## 📄 License

By contributing, you agree that your contributions will be licensed under the same license as the project.

---

**Thank you for contributing to PicFrame 3.0!** 🖼️
