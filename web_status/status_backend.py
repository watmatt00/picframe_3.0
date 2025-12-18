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
