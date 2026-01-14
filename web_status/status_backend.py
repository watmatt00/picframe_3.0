#!/usr/bin/env python3
"""
Robust backend for the PicFrame Sync Dashboard.

Goals:
  - Always return valid JSON from get_status_payload() (no 500s).
  - Drive counts/severity from a live chk_sync.sh quick run when possible.
  - Fall back gracefully and expose enough debug info to see what went wrong.
"""

import os
import subprocess
from collections import deque
from datetime import datetime
from pathlib import Path

from config_manager import (
    config_exists,
    read_config,
    get_derived_paths,
    get_config_with_defaults,
)

# --- Paths / service names ---------------------------------------------------

def _get_paths():
    """Get paths from config, with fallback defaults for backwards compatibility."""
    if config_exists():
        return get_derived_paths()
    # Fallback to hardcoded defaults if no config exists yet
    return {
        "log_file": Path("/home/pi/logs/frame_sync.log"),
        "chk_script": Path("/home/pi/picframe_3.0/ops_tools/chk_sync.sh"),
        "frame_sources_conf": Path("/home/pi/picframe_3.0/config/frame_sources.conf"),
        "frame_live": Path("/home/pi/Pictures/frame_live"),
        "app_root": Path("/home/pi/picframe_3.0"),
        "log_dir": Path("/home/pi/logs"),
    }

# Service names
WEB_SERVICE_NAME = "pf-web-status.service"   # system service
PF_SERVICE_NAME = "picframe.service"         # user service (systemctl --user)


# ---------------------------------------------------------------------------
# Quick check helper
# ---------------------------------------------------------------------------

def run_quick_check():
    """
    Run chk_sync.sh in quick (default) mode and parse:

      Remote file count: N
      Local  file count: M
      Quick check: File counts match. / Counts differ. / etc.

    Returns a dict:
      {
        "remote_count": int|None,
        "local_count": int|None,
        "quick_status": "match"|"differ"|"error"|"unknown",
        "raw_output": [lines...],
        "error": optional error string
      }
    """
    remote_count = None
    local_count = None
    quick_status = "unknown"
    raw_lines = []
    error_msg = None

    env = os.environ.copy()
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")

    paths = _get_paths()
    chk_script = paths["chk_script"]

    try:
        result = subprocess.run(
            [str(chk_script)],
            text=True,
            capture_output=True,
            check=False,
            timeout=120,
            env=env,
        )
    except Exception as e:
        return {
            "remote_count": None,
            "local_count": None,
            "quick_status": "error",
            "raw_output": [],
            "error": f"Failed to run chk_sync.sh: {e}",
        }

    combined = ""
    if result.stdout:
        combined += result.stdout
    if result.stderr:
        if combined:
            combined += "\n"
        combined += result.stderr

    raw_lines = combined.splitlines()

    for line in raw_lines:
        stripped = line.strip()
        lower = stripped.lower()

        # Count lines (case-insensitive, tolerant of extra text)
        if "remote file count" in lower:
            try:
                after = stripped.split(":", 1)[1].strip()
                remote_count = int(after.split()[0])
            except Exception:
                pass

        elif "local" in lower and "file count" in lower:
            try:
                after = stripped.split(":", 1)[1].strip()
                local_count = int(after.split()[0])
            except Exception:
                pass

        # Quick check line
        if "quick check" in lower:
            # Check mismatch/differ BEFORE match to avoid substring match
            if "mismatch" in lower or "differ" in lower:
                quick_status = "differ"
            elif "file counts match" in lower or "match" in lower:
                quick_status = "match"
            elif "error" in lower or "failed" in lower:
                quick_status = "error"

    # Script failed and we got nothing useful -> error
    if result.returncode != 0 and (remote_count is None and local_count is None):
        if quick_status == "unknown":
            quick_status = "error"
        error_msg = f"chk_sync.sh exited {result.returncode}"

    # If we have counts but no status, infer from counts
    if quick_status == "unknown" and remote_count is not None and local_count is not None:
        quick_status = "match" if remote_count == local_count else "differ"

    return {
        "remote_count": remote_count,
        "local_count": local_count,
        "quick_status": quick_status,
        "raw_output": raw_lines,
        "error": error_msg,
    }


# ---------------------------------------------------------------------------
# Log helpers
# ---------------------------------------------------------------------------

def _tail_lines(path: Path, max_lines: int = 60) -> str:
    if not path.exists():
        return ""
    dq = deque(maxlen=max_lines)
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            dq.append(line.rstrip("\n"))
    return "\n".join(dq)


def _last_matching_timestamp(path: Path, needle: str):
    if not path.exists():
        return None

    last_line = None
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if needle in line:
                last_line = line

    if not last_line:
        return None

    ts_str = last_line[:19]
    try:
        datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
        return ts_str
    except ValueError:
        return None


def parse_log(path: Path):
    last_restart = _last_matching_timestamp(
        path, "Service picframe.service restarted successfully"
    )
    last_download = _last_matching_timestamp(
        path, "rclone sync completed successfully"
    )
    log_tail = _tail_lines(path, max_lines=60)

    return {
        "last_service_restart": last_restart or "--",
        "last_file_download": last_download or "--",
        "log_tail": log_tail,
    }


# ---------------------------------------------------------------------------
# Service + current-remote helpers
# ---------------------------------------------------------------------------

def _systemctl_status(service: str, user: bool = False) -> str:
    """
    Service status helper.

    For system services (pf-web-status.service):
        systemctl is-active SERVICE

    For user services (picframe.service):
        1) try:  loginctl enable-linger pi
        2) try:  systemctl --user --machine=pi@ is-active SERVICE
        3) fallback: if that fails or returns unknown, use pgrep
           (any 'picframe' process owned by pi => treat as 'active')
    """
    env = os.environ.copy()
    env.setdefault("PATH",
        "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
    # Set XDG_RUNTIME_DIR for systemctl --user commands
    env.setdefault("XDG_RUNTIME_DIR", "/run/user/1000")

    try:
        if not user:
            # Normal system-level service
            cmd = ["systemctl", "is-active", service]
            out = subprocess.run(
                cmd,
                text=True,
                capture_output=True,
                check=False,
                timeout=10,
                env=env,
            )
            status = out.stdout.strip() or out.stderr.strip() or "unknown"
            if "failed to connect" in status.lower():
                status = "unknown"
            return status

        # User service branch (picframe.service)
        # Try to ensure linger (so user services run without a login session)
        subprocess.run(
            ["loginctl", "enable-linger", "pi"],
            text=True,
            capture_output=True,
            timeout=5,
            check=False,
            env=env,
        )

        cmd_user = [
            "systemctl",
            "--user",
            "--machine=pi@",
            "is-active",
            service,
        ]
        out = subprocess.run(
            cmd_user,
            text=True,
            capture_output=True,
            check=False,
            timeout=10,
            env=env,
        )
        status = out.stdout.strip() or out.stderr.strip() or "unknown"
        if "failed to connect" in status.lower():
            status = "unknown"

        # Fallback: if still unknown, check for a running picframe process
        if status == "unknown":
            try:
                p = subprocess.run(
                    ["pgrep", "-u", "pi", "-f", "picframe"],
                    text=True,
                    capture_output=True,
                    check=False,
                    timeout=5,
                    env=env,
                )
                if p.returncode == 0 and (p.stdout or p.stderr):
                    status = "active"
            except Exception:
                pass

        return status

    except Exception:
        return "unknown"


def _current_remote_from_conf(conf_path: Path) -> str:
    if not conf_path.exists():
        return "--"

    active_source = None
    labels = {}

    try:
        with conf_path.open("r", encoding="utf-8", errors="ignore") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("ACTIVE_SOURCE"):
                    _, val = line.split("=", 1)
                    active_source = val.strip().strip('"').strip("'")
                elif line.startswith("SOURCE_") and "_LABEL" in line:
                    key, val = line.split("=", 1)
                    labels[key.strip()] = val.strip().strip('"').strip("'")
    except Exception:
        return "--"

    if not active_source:
        return "--"

    label_key = f"SOURCE_{active_source}_LABEL"
    return labels.get(label_key, active_source)


def _current_remote_from_quick(raw_lines) -> str:
    """
    Fallback: parse "Active source: kfr - Koofr (kfr_frame)"
    from chk_sync.sh output if the config file doesn't give us a label.
    """
    if not raw_lines:
        return "--"

    for line in raw_lines:
        stripped = line.strip()
        lower = stripped.lower()
        if lower.startswith("active source:"):
            try:
                after = stripped.split(":", 1)[1].strip()
                if " - " in after:
                    parts = after.split(" - ", 1)
                    label = parts[1].strip()
                else:
                    label = after
                return label or "--"
            except Exception:
                continue

    return "--"


def _parse_source_details_from_quick(raw_lines) -> dict:
    """
    Parse detailed source information from chk_sync.sh output.
    Returns dict with: source_name, remote_path, local_path

    Example output from chk_sync.sh:
      Active source: kfr - Koofr (kfr_frame)
        Source ID : kfr
        Remote    : kfrphotos:KFR_kframe
        Local dir : /home/pi/Pictures/kfr_frame
    """
    result = {
        "source_name": "--",
        "remote_path": "--",
        "local_path": "--",
    }

    if not raw_lines:
        return result

    for line in raw_lines:
        stripped = line.strip()
        lower = stripped.lower()

        # Parse active source name
        if lower.startswith("active source:"):
            try:
                after = stripped.split(":", 1)[1].strip()
                result["source_name"] = after
            except Exception:
                continue

        # Parse remote path - look for "Remote    :" or "Remote:"
        elif "remote" in lower and ":" in stripped and "active source" not in lower:
            try:
                # Split on first colon and take everything after
                parts = stripped.split(":", 1)
                if len(parts) == 2:
                    after = parts[1].strip()
                    # Only set if it looks like a path (contains ":" for rclone remote)
                    if after and ":" in after:
                        result["remote_path"] = after
            except Exception:
                continue

        # Parse local directory - look for "Local dir :" or "Local directory:"
        elif "local" in lower and ("dir" in lower or "directory" in lower) and ":" in stripped:
            try:
                after = stripped.split(":", 1)[1].strip()
                if after and after.startswith("/"):
                    result["local_path"] = after
            except Exception:
                continue

    return result


# ---------------------------------------------------------------------------
# Public API used by app.py
# ---------------------------------------------------------------------------

def get_status_payload():
    """
    Build the JSON payload returned by /api/status.

    Never raises; on any error, returns a best-effort payload with
    severity="ERROR" and a debug.error field.
    """
    debug = {}
    paths = _get_paths()
    log_path = paths["log_file"]
    chk_script = paths["chk_script"]
    frame_sources_conf = paths["frame_sources_conf"]

    try:
        quick = run_quick_check()
        debug["quick_error"] = quick.get("error")
        debug["quick_raw_output"] = quick.get("raw_output")

        remote_count = quick.get("remote_count")
        local_count = quick.get("local_count")
        quick_status = quick.get("quick_status") or "unknown"

        if quick_status == "match":
            severity = "OK"
            overall_text = "Last sync succeeded"
        elif quick_status == "differ":
            severity = "WARN"
            overall_text = "Counts differ – check needed"
        elif quick_status == "error":
            severity = "ERROR"
            overall_text = "Error running chk_sync.sh"
        else:
            severity = "UNKNOWN"
            overall_text = "Status unknown"

        log_info = parse_log(log_path)
        web_status = _systemctl_status(WEB_SERVICE_NAME, user=False)
        pf_status = _systemctl_status(PF_SERVICE_NAME, user=True)

        # Primary source: config file
        current_remote = _current_remote_from_conf(frame_sources_conf)
        # Fallback: parse from chk_sync.sh output if config is missing/empty
        if not current_remote or current_remote == "--":
            current_remote = _current_remote_from_quick(quick.get("raw_output"))

        # Extract detailed path info from quick check output
        source_details = _parse_source_details_from_quick(quick.get("raw_output"))

        now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        return {
            "now": now_str,
            "script_path": str(chk_script),
            "log_path": str(log_path),
            "overall": {
                "remote_count": remote_count,
                "local_count": local_count,
                "severity": severity,
                "status_text": overall_text,
            },
            "web_status": web_status,
            "pf_status": pf_status,
            "current_remote": current_remote or "--",
            "source_details": source_details,
            "activity": {
                "last_service_restart": log_info["last_service_restart"],
                "last_file_download": log_info["last_file_download"],
                "log_tail": log_info["log_tail"],
            },
            "debug": debug,
        }

    except Exception as e:
        now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        debug["top_level_error"] = str(e)

        return {
            "now": now_str,
            "script_path": str(chk_script),
            "log_path": str(log_path),
            "overall": {
                "remote_count": None,
                "local_count": None,
                "severity": "ERROR",
                "status_text": "Backend error",
            },
            "web_status": "unknown",
            "pf_status": "unknown",
            "current_remote": "--",
            "source_details": {
                "source_name": "--",
                "remote_path": "--",
                "local_path": "--",
            },
            "activity": {
                "last_service_restart": "--",
                "last_file_download": "--",
                "log_tail": "",
            },
            "debug": debug,
        }


def run_chk_sync_detailed():
    """
    Run chk_sync.sh --d and return its stdout/stderr for the tools card.
    """
    paths = _get_paths()
    chk_script = paths["chk_script"]

    env = os.environ.copy()
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")

    try:
        result = subprocess.run(
            [str(chk_script), "--d"],
            text=True,
            capture_output=True,
            check=False,
            timeout=600,
            env=env,
        )
        output = ""
        if result.stdout:
            output += result.stdout
        if result.stderr:
            if output:
                output += "\n"
            output += result.stderr

        return {
            "ok": (result.returncode == 0),
            "output": output,
        }
    except Exception as e:
        return {
            "ok": False,
            "output": f"Error running chk_sync.sh --d: {e}",
        }


def run_restart_pf_service():
    """
    Run svc_ctl.sh to restart PicFrame service and return its stdout/stderr.
    """
    paths = _get_paths()
    app_root = paths["app_root"]
    svc_ctl_script = app_root / "app_control" / "svc_ctl.sh"

    env = os.environ.copy()
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
    # Set XDG_RUNTIME_DIR for systemctl --user to work from system service context
    env.setdefault("XDG_RUNTIME_DIR", "/run/user/1000")

    try:
        result = subprocess.run(
            [str(svc_ctl_script), "-pr"],
            text=True,
            capture_output=True,
            check=False,
            timeout=60,
            env=env,
        )
        output = ""
        if result.stdout:
            output += result.stdout
        if result.stderr:
            if output:
                output += "\n"
            output += result.stderr

        return {
            "ok": (result.returncode == 0),
            "output": output,
        }
    except Exception as e:
        return {
            "ok": False,
            "output": f"Error running svc_ctl.sh: {e}",
        }


def run_restart_web_service():
    """
    Run svc_ctl.sh to restart web service and return its stdout/stderr.
    """
    paths = _get_paths()
    app_root = paths["app_root"]
    svc_ctl_script = app_root / "app_control" / "svc_ctl.sh"

    env = os.environ.copy()
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")

    try:
        result = subprocess.run(
            [str(svc_ctl_script), "-wr"],
            text=True,
            capture_output=True,
            check=False,
            timeout=60,
            env=env,
        )
        output = ""
        if result.stdout:
            output += result.stdout
        if result.stderr:
            if output:
                output += "\n"
            output += result.stderr

        return {
            "ok": (result.returncode == 0),
            "output": output,
        }
    except Exception as e:
        return {
            "ok": False,
            "output": f"Error running svc_ctl.sh: {e}",
        }


def run_sync_now():
    """
    Run frame_sync.sh immediately to trigger a manual sync.
    """
    paths = _get_paths()
    app_root = paths["app_root"]
    sync_script = app_root / "ops_tools" / "frame_sync.sh"

    env = os.environ.copy()
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
    # Set XDG_RUNTIME_DIR for systemctl --user commands (pi user is UID 1000)
    env.setdefault("XDG_RUNTIME_DIR", "/run/user/1000")

    try:
        result = subprocess.run(
            [str(sync_script)],
            text=True,
            capture_output=True,
            check=False,
            timeout=300,  # 5 minutes - sync can take longer than restart
            env=env,
        )
        output = ""
        if result.stdout:
            output += result.stdout
        if result.stderr:
            if output:
                output += "\n"
            output += result.stderr

        return {
            "ok": (result.returncode == 0),
            "output": output,
        }
    except Exception as e:
        return {
            "ok": False,
            "output": f"Error running sync script: {e}",
        }


def check_github_updates():
    """
    Check for GitHub updates without applying them.

    Returns:
        {
            "ok": bool,
            "updates_available": bool,
            "current_commit": str,
            "current_tag": str,
            "remote_commit": str,
            "remote_tag": str,
            "commits_behind": int,
            "output": str
        }
    """
    paths = _get_paths()
    repo_dir = paths["app_root"]

    # Verify git repo exists
    git_dir = repo_dir / ".git"
    if not git_dir.exists():
        return {
            "ok": False,
            "updates_available": False,
            "current_commit": "N/A",
            "current_tag": "N/A",
            "remote_commit": "N/A",
            "remote_tag": "N/A",
            "commits_behind": 0,
            "output": f"ERROR: Not a git repository: {repo_dir}"
        }

    env = os.environ.copy()
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")

    output_lines = []

    try:
        # Get current commit
        result = subprocess.run(
            ["git", "-C", str(repo_dir), "log", "-1", "--format=%h - %s"],
            text=True,
            capture_output=True,
            check=False,
            timeout=10,
            env=env,
        )
        current_commit = result.stdout.strip() if result.returncode == 0 else "Unknown"

        # Get current tag (if any)
        result = subprocess.run(
            ["git", "-C", str(repo_dir), "describe", "--tags", "--exact-match", "HEAD"],
            text=True,
            capture_output=True,
            check=False,
            timeout=10,
            env=env,
        )
        current_tag = result.stdout.strip() if result.returncode == 0 else ""

        # Fetch from remote
        output_lines.append("Fetching latest from GitHub...")
        result = subprocess.run(
            ["git", "-C", str(repo_dir), "fetch", "--all"],
            text=True,
            capture_output=True,
            check=False,
            timeout=30,
            env=env,
        )

        if result.returncode != 0:
            error_msg = result.stderr.strip() or "Failed to fetch"
            output_lines.append(f"ERROR: {error_msg}")
            return {
                "ok": False,
                "updates_available": False,
                "current_commit": current_commit,
                "current_tag": current_tag,
                "remote_commit": "N/A",
                "remote_tag": "N/A",
                "commits_behind": 0,
                "output": "\n".join(output_lines)
            }

        output_lines.append("Fetch completed successfully.")

        # Get remote commit
        result = subprocess.run(
            ["git", "-C", str(repo_dir), "log", "-1", "--format=%h - %s", "origin/main"],
            text=True,
            capture_output=True,
            check=False,
            timeout=10,
            env=env,
        )
        remote_commit = result.stdout.strip() if result.returncode == 0 else "Unknown"

        # Get remote tag
        result = subprocess.run(
            ["git", "-C", str(repo_dir), "describe", "--tags", "origin/main"],
            text=True,
            capture_output=True,
            check=False,
            timeout=10,
            env=env,
        )
        remote_tag = result.stdout.strip() if result.returncode == 0 else ""

        # Count commits behind
        result = subprocess.run(
            ["git", "-C", str(repo_dir), "rev-list", "--count", "HEAD..origin/main"],
            text=True,
            capture_output=True,
            check=False,
            timeout=10,
            env=env,
        )
        commits_behind = int(result.stdout.strip()) if result.returncode == 0 else 0

        # Build output
        output_lines.append("")
        output_lines.append("Current Version:")
        output_lines.append(f"  {current_commit}")
        if current_tag:
            output_lines.append(f"  Tag: {current_tag}")

        output_lines.append("")
        output_lines.append("Latest Available:")
        output_lines.append(f"  {remote_commit}")
        if remote_tag:
            output_lines.append(f"  Tag: {remote_tag}")

        output_lines.append("")
        if commits_behind > 0:
            output_lines.append(f"Status: {commits_behind} commit(s) behind - UPDATE AVAILABLE")
        else:
            output_lines.append("Status: Up to date")

        return {
            "ok": True,
            "updates_available": commits_behind > 0,
            "current_commit": current_commit,
            "current_tag": current_tag,
            "remote_commit": remote_commit,
            "remote_tag": remote_tag,
            "commits_behind": commits_behind,
            "output": "\n".join(output_lines)
        }

    except subprocess.TimeoutExpired:
        output_lines.append("ERROR: Operation timed out")
        return {
            "ok": False,
            "updates_available": False,
            "current_commit": current_commit if 'current_commit' in locals() else "Unknown",
            "current_tag": current_tag if 'current_tag' in locals() else "",
            "remote_commit": "N/A",
            "remote_tag": "N/A",
            "commits_behind": 0,
            "output": "\n".join(output_lines)
        }
    except Exception as e:
        output_lines.append(f"ERROR: {str(e)}")
        return {
            "ok": False,
            "updates_available": False,
            "current_commit": current_commit if 'current_commit' in locals() else "Unknown",
            "current_tag": current_tag if 'current_tag' in locals() else "",
            "remote_commit": "N/A",
            "remote_tag": "N/A",
            "commits_behind": 0,
            "output": "\n".join(output_lines)
        }


def apply_github_update():
    """
    Apply GitHub update by running update_app.sh.

    Returns:
        {
            "ok": bool,
            "output": str
        }
    """
    paths = _get_paths()
    app_root = paths["app_root"]
    update_script = app_root / "ops_tools" / "update_app.sh"

    if not update_script.exists():
        return {
            "ok": False,
            "output": f"ERROR: Update script not found: {update_script}"
        }

    if not os.access(update_script, os.X_OK):
        return {
            "ok": False,
            "output": f"ERROR: Update script not executable: {update_script}"
        }

    env = os.environ.copy()
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")

    try:
        result = subprocess.run(
            [str(update_script)],
            text=True,
            capture_output=True,
            check=False,
            timeout=600,  # 10 minutes - same as deep check
            env=env,
        )

        output = ""
        if result.stdout:
            output += result.stdout
        if result.stderr:
            if output:
                output += "\n"
            output += result.stderr

        return {
            "ok": (result.returncode == 0),
            "output": output or "Update script completed"
        }

    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "output": "ERROR: Update timed out after 10 minutes. This may indicate a problem.\nCheck logs at: $HOME/logs/frame_sync.log"
        }
    except Exception as e:
        return {
            "ok": False,
            "output": f"ERROR: Failed to run update script: {str(e)}"
        }


# ---------------------------------------------------------------------------
# Source helpers (for API endpoints)
# ---------------------------------------------------------------------------

def get_sources_from_conf():
    """
    Parse frame_sources.conf and return list of sources.
    
    Returns list of dicts with: id, label, path, enabled, active, remote
    """
    sources = []
    paths = _get_paths()
    conf_path = paths["frame_sources_conf"]
    frame_live = paths["frame_live"]
    
    if not conf_path.exists():
        return sources
    
    # Determine current active source from symlink
    current_target = None
    if frame_live.is_symlink():
        try:
            current_target = str(frame_live.resolve())
        except Exception:
            pass
    
    try:
        for line in conf_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            
            parts = line.split("|")
            if len(parts) >= 4:
                src_id = parts[0]
                label = parts[1]
                path = parts[2]
                enabled = parts[3]
                remote = parts[4] if len(parts) > 4 else ""
                
                sources.append({
                    "id": src_id,
                    "label": label,
                    "path": path,
                    "enabled": enabled == "1",
                    "active": current_target == path,
                    "remote": remote,
                })
    except Exception:
        pass
    
    return sources


def validate_source_data(source_id, label, path, rclone_remote):
    """
    Validate source data before adding to frame_sources.conf.
    
    Returns: (is_valid, error_message)
    """
    # Validate source_id
    if not source_id or not source_id.strip():
        return False, "Source ID is required"
    
    if not source_id.replace("_", "").replace("-", "").isalnum():
        return False, "Source ID must contain only letters, numbers, hyphens, and underscores"
    
    # Check if source_id already exists
    sources = get_sources_from_conf()
    if any(s["id"] == source_id for s in sources):
        return False, f"Source ID '{source_id}' already exists"
    
    # Validate label
    if not label or not label.strip():
        return False, "Label is required"
    
    # Validate path
    if not path or not path.strip():
        return False, "Local path is required"
    
    if not path.startswith("/"):
        return False, "Local path must be an absolute path"
    
    # Validate rclone_remote
    if not rclone_remote or not rclone_remote.strip():
        return False, "Rclone remote is required"
    
    if ":" not in rclone_remote:
        return False, "Rclone remote must include ':' (e.g., remote:path)"

    # Validate rclone_remote for problematic spaces
    if rclone_remote.strip() != rclone_remote:
        return False, "Rclone remote path has leading or trailing spaces - please check the path"

    # Extract the path component and check for spaces in directory names
    if ":" in rclone_remote:
        _, path_part = rclone_remote.split(":", 1)
        if path_part:
            # Check each path component for leading/trailing spaces
            path_components = path_part.split("/")
            for component in path_components:
                if component and component.strip() != component:
                    return False, f"Directory '{component}' has leading or trailing spaces - rename it in your cloud storage first"

    return True, None


def add_source_to_conf(source_id, label, path, enabled, rclone_remote, create_directory=False):
    """
    Add a new source to frame_sources.conf.

    Args:
        source_id: Short identifier (e.g., "mycloud")
        label: Human-friendly name (e.g., "My Cloud Photos")
        path: Local directory path (e.g., "/home/pi/Pictures/mycloud_frame")
        enabled: 1 for enabled, 0 for disabled
        rclone_remote: Rclone remote and path (e.g., "mydrive:photos")
        create_directory: If True, create the directory if it doesn't exist

    Returns: (success, error_message)
    """
    # Create directory if requested
    if create_directory:
        try:
            from pathlib import Path
            dir_path = Path(path)
            if not dir_path.exists():
                dir_path.mkdir(parents=True, exist_ok=True)
        except Exception as e:
            return False, f"Failed to create directory: {str(e)}"

    # Validate first
    is_valid, error = validate_source_data(source_id, label, path, rclone_remote)
    if not is_valid:
        return False, error

    paths = _get_paths()
    conf_path = paths["frame_sources_conf"]

    if not conf_path.exists():
        return False, f"Config file not found: {conf_path}"

    try:
        # Create backup
        backup_path = conf_path.with_suffix(".conf.backup")
        import shutil
        shutil.copy2(conf_path, backup_path)

        # Format new source line
        enabled_str = "1" if enabled else "0"
        new_line = f"{source_id}|{label}|{path}|{enabled_str}|{rclone_remote}\n"

        # Append to file
        with conf_path.open("a", encoding="utf-8") as f:
            f.write(new_line)

        return True, None

    except Exception as e:
        return False, f"Failed to write to config: {str(e)}"


def delete_source_from_conf(source_id):
    """
    Delete a source from frame_sources.conf.

    Args:
        source_id: The ID of the source to delete

    Returns: (success, error_message)
    """
    if not source_id or not source_id.strip():
        return False, "Source ID is required"

    paths = _get_paths()
    conf_path = paths["frame_sources_conf"]

    if not conf_path.exists():
        return False, f"Config file not found: {conf_path}"

    try:
        # Read all lines
        lines = conf_path.read_text(encoding="utf-8").splitlines()

        # Filter out the source to delete
        new_lines = []
        found = False
        for line in lines:
            stripped = line.strip()
            # Keep comments and empty lines
            if not stripped or stripped.startswith("#"):
                new_lines.append(line)
                continue

            # Parse source line
            parts = stripped.split("|")
            if len(parts) >= 4:
                src_id = parts[0]
                if src_id == source_id:
                    found = True
                    continue  # Skip this line (delete it)

            new_lines.append(line)

        if not found:
            return False, f"Source '{source_id}' not found"

        # Create backup
        backup_path = conf_path.with_suffix(".conf.backup")
        import shutil
        shutil.copy2(conf_path, backup_path)

        # Write updated content
        conf_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")

        return True, None

    except Exception as e:
        return False, f"Failed to delete source: {str(e)}"


def get_frame_live_target():
    """
    Get the current target of the frame_live symlink.

    Returns: {
        "exists": bool,
        "is_symlink": bool,
        "target": str or None,
        "target_name": str or None (just the directory name)
    }
    """
    paths = _get_paths()
    frame_live = paths["frame_live"]

    result = {
        "exists": frame_live.exists(),
        "is_symlink": frame_live.is_symlink(),
        "target": None,
        "target_name": None
    }

    if frame_live.is_symlink():
        try:
            target = frame_live.resolve()
            result["target"] = str(target)
            result["target_name"] = target.name
        except Exception:
            pass

    return result


def set_frame_live_target(target_dir):
    """
    Set the frame_live symlink to point to a new directory.

    Args:
        target_dir: Full path to the target directory (e.g., "/home/pi/Pictures/kfr_frame")

    Returns: (success, error_message)
    """
    from pathlib import Path

    paths = _get_paths()
    frame_live = paths["frame_live"]
    target_path = Path(target_dir)

    # Validate target exists and is a directory
    if not target_path.exists():
        return False, f"Target directory does not exist: {target_dir}"

    if not target_path.is_dir():
        return False, f"Target is not a directory: {target_dir}"

    # Validate target is under /home/pi/Pictures
    pictures_dir = Path.home() / "Pictures"
    try:
        target_path.relative_to(pictures_dir)
    except ValueError:
        return False, f"Target must be under {pictures_dir}"

    try:
        # Remove existing symlink if it exists
        if frame_live.exists() or frame_live.is_symlink():
            frame_live.unlink()

        # Create new symlink
        frame_live.symlink_to(target_path)

        return True, None

    except Exception as e:
        return False, f"Failed to update symlink: {str(e)}"
