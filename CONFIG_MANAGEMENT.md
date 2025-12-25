# Configuration Management

This project follows the **Template Pattern** for configuration management, separating code from user data.

## How It Works

### Template Files (Version Controlled)
These are example/template files stored in git:
- `config/frame_sources.conf.example` - Template for photo sources

### Local Config Files (NOT Version Controlled)
These are your personal configurations, excluded from git:
- `config/frame_sources.conf` - Your actual photo sources (gitignored)

## First Time Setup

On first deployment, `update_app.sh` automatically:
1. Checks if `config/frame_sources.conf` exists
2. If not, copies from `config/frame_sources.conf.example`
3. You can then edit it or add sources via the dashboard

## Adding Photo Sources

**Via Dashboard (Recommended):**
1. Go to http://kframe.local:5050/beta
2. Click "Switch Photos" tab
3. Use "Add New Photo Source" form
4. Changes are saved to `config/frame_sources.conf` automatically

**Manually:**
1. Edit `config/frame_sources.conf`
2. Add line: `id|Label|/path/to/photos|1|remote:path`
3. Restart dashboard or wait for auto-refresh

## Deployments

When running `ops_tools/update_app.sh`:
- ✅ Code updates are pulled from git
- ✅ Your `config/frame_sources.conf` is **preserved**
- ✅ No manual backups needed
- ✅ Sources added via dashboard persist automatically

## Why This Approach?

**Industry Best Practice:**
- **Code** = version controlled (shared across users)
- **User Data/Config** = local only (specific to your instance)

**Benefits:**
- ✅ Clean separation of concerns
- ✅ No accidental data loss on deployments
- ✅ Easier collaboration (no merge conflicts on configs)
- ✅ Simpler .gitignore (standard pattern)

## Migration from Old System

If you previously had sources in the repo:
1. They're now in `config/frame_sources.conf` (local)
2. Template has examples in `config/frame_sources.conf.example`
3. Old deployments overwrote your changes ❌
4. New deployments preserve your changes ✅
