#!/usr/bin/env python3
"""
Simpler, defensive backend for the PicFrame Sync Dashboard.

Key goals:
  - Always derive remote/local counts + severity from a live chk_sync.sh quick run
  - Keep JSON shape stable for the existing dashboard.js
  - Be very tolerant of output formatting (leading spaces, emojis, colours, etc.)
"""

import os
import subprocess
from collections import deque
from datetime import datetime
from pathlib import Path

# --- Paths / service names ---------------------------------------------------

LOG_PATH = Path("/home/pi/logs/frame_sync.log")
CHK_SCRIPT = Path("/home/pi/picframe_3.0/ops_tools/chk_sync.sh")
FRAME_SOURCES_CONF = Path("/home/pi/picframe_3.0/config/frame_sources.conf")

WEB_SERVICE_NAME = "pf-web-status.service"   # system service
PF_SERVICE_NAME = "picframe.service"         # user service (systemctl --user)


# ---------------------------------------------------------------------------
# Helpers for chk_sync.sh quick mode
# ---------------------------------------------------------------------------

def run_quick_check():
    """
    Run chk_sync.sh in quick (default) mode and parse:

      Remote file count: N
      Local  file count: M
      Quick check: File counts match. / Counts differ. / etc.

    Returns a dict with:
      remote_count, local_count, quick_status, raw_output
    """
    remote_count = None
    local_count = None
    quick_status = "unknown"

    env = os.environ.copy()
    # Ensure a reasonable PATH for systemd service context
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")

    try:
        result = subprocess.run(
            [str(CHK_SCRIPT)],
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
            "error": "Failed to run chk_sync.sh: %s" % e,
            "raw_output": [],
        }

    # Combine stdout + stderr (non-TTY runs may print to stderr)
    combined = ""
    if result.stdout:
        combined += result.stdout
    if result.stderr:
        if combined:
            combined += "\n"
        combined += result.stderr

    lines = combined.splitlines()

    for line in lines:
        stripped = line.strip()
        lower = stripped.lower()

        # --- counts ---
        if "remote file count" in lower:
            # tolerate extra text, emojis, etc.
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

        # --- quick status line ---
        if "quick check" in lower:
            if "match" in lower:
                quick_status = "match"
            elif "differ" in lower:
                quick_status = "differ"
            elif "error" in lower or "failed" in lower:
                quick_status = "error"

    # If chk_sync.sh failed and we got no counts, it's an error
    if result.returncode != 0 and (remote_count is None or local_count is None):
        quick_status = "error"

    # If we have counts but no explicit quick_status, infer it from the counts
    if quick_status == "unknown" and remote_count is not None and local_count is not None:
        if remote_count == local_count:
            quick_status = "match"
        else:
            quick_status = "differ"

    return {
        "remote_count": remote_count,
        "local_count": local_count,
        "quick_status": quick_status,
        "raw_output": lines,
    }


# ---------------------------------------------------------------------------
# Log parsing helpers
# ---------------------------------------------------------------------------

def _tail_lines(path, max_lines=60):
    """Return the last `max_lines` lines of a text file, joined by newlines."""
    if not path.exists():
        return ""
    dq = deque(maxlen=max_lines)
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            dq.append(line.rstrip("\n"))
    return "\n".join(dq)


def _last_matching_timestamp(path, needle):
    """
    Scan the log for the last line containing `needle` and return the leading
    YYYY-MM-DD HH:MM:SS timestamp (if present).
    """
    if not path.exists():
        return None

    last_line = None
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if needle in line:
                last_line = line

    if not last_line:
        return None

    ts_str = last_line[:19]  # "2025-11-29 08:00:05"
    try:
        datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
        return ts_str
    except ValueError:
        return None


def parse_log(path):
    """
    Pull structured info out of frame_sync.log:

      - last_service_restart: last time picframe.service restarted successfully
      - last_file_download:  last time rclone sync completed successfully
      - log_tail:            last N lines of the log for display
    """
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
# Service + current-remote detection
# ---------------------------------------------------------------------------

def _systemctl_status(service, user=False):
    """
    Wrap `systemctl is-active` (optionally with --user) and return a short status.
    """
    cmd = ["systemctl"]
    if user:
        cmd.append("--user")
    cmd.extend(["is-active", service])

    env = os.environ.copy()
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")

    try:
        out = subprocess.run(
            cmd,
            text=True,
            capture_output=True,
            check=False,
            timeout=10,
            env=env,
        )
        status = out.stdout.strip() or out.stderr.strip()
        return status or "unknown"
    except Exception:
        return "unknown"


def _current_remote_from_conf(conf_path):
    """
    Read config/frame_sources.conf and return the human label for ACTIVE_SOURCE.

    Expects entries like:

        ACTIVE_SOURCE="kfr"
        SOURCE_kfr_LABEL="Koofr (kfr_frame)"
        SOURCE_gdt_LABEL="Google Drive (gdt_frame)"
    """
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
                    # ACTIVE_SOURCE="kfr"
                    _, val = line.split("=", 1)
                    active_source = val.strip().strip('"').strip("'")
                elif line.startswith("SOURCE_") and "_LABEL" in line:
                    key, val = line.split("=", 1)
                    labels[key.strip()] = val.strip().strip('"').strip("'")
    except Exception:
        return "--"

    if not active_source:
        return "--"

    label_key = "SOURCE_%s_LABEL" % active_source
    return labels.get(label_key, active_source)


# ---------------------------------------------------------------------------
# Primary payload builder for /api/status
# ---------------------------------------------------------------------------

def get_status_payload():
    """
    Build the JSON payload returned by /api/status.

    This is what the dashboard JavaScript consumes. Key points:

      * Remote/local counts and overall severity are derived from a live
        quick run of chk_sync.sh (NOT from the log).
      * The log is used for last service restart, last file download, and the
        log tail preview.
    """
    # 1. Live quick check
    quick = run_quick_check()
    remote_count = quick.get("remote_count")
    local_count = quick.get("local_count")
    quick_status = quick.get("quick_status")

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

    # 2. Log-derived information
    log_info = parse_log(LOG_PATH)

    # 3. Service states + current remote
    web_status = _systemctl_status(WEB_SERVICE_NAME, user=False)
    pf_status = _systemctl_status(PF_SERVICE_NAME, user=True)
    current_remote = _current_remote_from_conf(FRAME_SOURCES_CONF)

    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    return {
        "now": now_str,
        "script_path": str(CHK_SCRIPT),
        "log_path": str(LOG_PATH),
        "overall": {
            "remote_count": remote_count,
            "local_count": local_count,
            "severity": severity,
            "status_text": overall_text,
        },
        "web_status": web_status,
        "pf_status": pf_status,
        "current_remote": current_remote,
        "activity": {
            "last_service_restart": log_info["last_service_restart"],
            "last_file_download": log_info["last_file_download"],
            "log_tail": log_info["log_tail"],
        },
    }


# ---------------------------------------------------------------------------
# Detailed chk_sync.sh --d runner for the "Run chk_sync.sh --d" button
# ---------------------------------------------------------------------------

def run_chk_sync_detailed():
    """
    Run chk_sync.sh --d and return its stdout/stderr.

    Used by /api/run-check (POST).
    """
    env = os.environ.copy()
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")

    try:
        result = subprocess.run(
            [str(CHK_SCRIPT), "--d"],
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
            "output": "Error running chk_sync.sh --d: %s" % e,
        }
