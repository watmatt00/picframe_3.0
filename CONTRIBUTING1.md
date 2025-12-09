# Contributing to PicFrame 3.0

## Claude Code Permissions

The project has auto-approval configured for specific commands (`.claude/settings.local.json`):
- `Bash(grep:*)` - All grep commands
- `Bash(git quick:*)` - Git quick workflow
- `Bash(git add:*)` - Git staging
- `Bash(git commit:*)` - Git commits (with specific format)
- `Bash(git push)` - Git push operations

## Git Workflow Aliases

Three custom git shortcuts are configured:
- **`git quick`** - Auto-commit + sync workflow
- **`git commit`** - Add all changes and auto-commit
- **`git sync`** - Fetch, rebase, and push to main

## Development Environment Rules

### PC/Tablet (Development)
- Use test scripts: `t_frame_sync.sh`, `t_chk_sync.sh`
- Promote to production using: `promote_to_prod.sh`
- Never run `update_app.sh` on PC/tablet

### Raspberry Pi (Production)
- Never run `promote_to_prod.sh` on the Pi (hard-blocked)
- Only update using: `update_app.sh`
- Pulls from GitHub and restarts services

## Commit Message Format

Standard format includes:
```
Brief title

Detailed explanation of changes

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Project-Specific Conventions

- Logs stored in: `~/logs/frame_sync_YYYY-MM-DD.log`
- Config files in: `config/` directory
- Operational tools in: `ops_tools/` directory
- Web dashboard runs on port **5050**

## Project Structure

```
picframe_3.0/
├── app_control/      - Service control scripts
├── config/           - Configuration files
├── ops_tools/        - Operational and maintenance tools
└── web_status/       - Flask dashboard application
```
