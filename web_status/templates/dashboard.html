#!/usr/bin/env python3
import os
import subprocess
from pathlib import Path
from datetime import datetime
import re

# --- Paths / service names you may edit if needed ---
LOG_PATH = Path("/home/pi/logs/frame_sync.log")
CHK_SCRIPT = Path("/home/pi/picframe_3.0/ops_tools/chk_sync.sh")
WEB_SERVICE_NAME = "pf-web-status.service"   # system service
PF_SERVICE_NAME = "picframe.service"         # user service (systemctl --user)

# New: config for current source
CONFIG_FILE = Path("/home/pi/picframe_3.0/config/frame_sources.conf")
FRAME_LIVE = Path("/home/pi/Pictures/frame_live")
# ----------------------------------------------------


def load_sources_from_config():
    """Read frame_sources.conf and return list of {id,label,path,enabled}."""
    sources = []
    if not CONFIG_FILE.exists():
        return sources
    try:
        with CONFIG_FILE.open("r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split("|")
                if len(parts) != 4:
                    continue
                sid, label, path, enabled = parts
                sources.append(
                    {
                        "id": sid.strip(),
                        "label": label.strip(),
                        "path": path.strip(),
                        "enabled": enabled.strip() == "1",
                    }
                )
    except Exception:
        pass
    return sources


def get_current_remote_label():
    """
    Determine which source is currently pointed to by /home/pi/Pictures/frame_live.

    Uses the FRAME_LIVE symlink and the frame_sources.conf config to produce a
    friendly label like 'kfr - Koofr (kfr_frame)'.
    """
    current = None
    if FRAME_LIVE.exists() and FRAME_LIVE.is_symlink():
        try:
            target = FRAME_LIVE.resolve()
            current = str(target)
        except Exception:
            current = None

    sources = load_sources_from_config()
    for s in sources:
        if current and s["path"] == current:
            return s["label"]

    # Fallback: show raw symlink target if we have it
    if current:
        return current

    return "Unknown (no active source)"


def parse_status_from_log():
    """
    Parse LOG_PATH and return a dict with:

      - level: ok/warn/err
      - status_label: short label
      - status_headline: one-line summary
      - status_raw: raw last sync line
      - last_sync: timestamp of last sync run
      - last_restart: timestamp of last 'picframe service restarted' line
      - last_file_download: timestamp/log source of last 'rclone sync completed'
      - google_count/local_count: counts parsed from latest 'Initial/Remote/Local count' lines
      - current_remote: human label derived from FRAME_LIVE symlink/config
      - log_tail: last ~40 lines of the log for display
    """
    data = {
        "level": "err",
        "status_label": "NO DATA",
        "status_headline": "No log data available",
        "status_raw": None,
        "last_sync": None,
        "last_restart": None,
        "last_file_download": None,
        "google_count": None,
        "local_count": None,
        "current_remote": None,
        "log_tail": None,
    }

    # Always put the current remote label in, even if log missing
    data["current_remote"] = get_current_remote_label()

    if not LOG_PATH.exists():
        data["status_headline"] = "Log file not found"
        data["status_raw"] = str(LOG_PATH)
        data["log_tail"] = f"(log file not found: {LOG_PATH})"
        return data

    try:
        text = LOG_PATH.read_text(encoding="utf-8", errors="ignore")
    except Exception as e:
        data["status_headline"] = "Error reading log"
        data["status_raw"] = str(e)
        data["log_tail"] = f"(error reading {LOG_PATH}: {e})"
        return data

    if not text.strip():
        data["status_headline"] = "Log empty"
        data["status_raw"] = ""
        data["log_tail"] = "(log file empty)"
        return data

    lines = text.splitlines()
    tail_len = 40
    data["log_tail"] = "\n".join(lines[-tail_len:])

    last_sync_line = None
    last_restart_line = None
    gcount_line = None
    lcount_line = None
    last_dl_line = None

    for line in reversed(lines):
        if not last_sync_line and "SYNC_RESULT:" in line:
            last_sync_line = line
        if not last_restart_line and "picframe service restarted" in line:
            last_restart_line = line
        if not gcount_line and ("Initial Google count:" in line or "Initial Remote count:" in line):
            gcount_line = line
        if not lcount_line and ("Initial Local count:" in line or "Initial Local frames count:" in line):
            lcount_line = line
        if last_dl_line is None and "rclone sync completed successfully." in line:
            last_dl_line = line

        if (
            last_sync_line
            and last_restart_line
            and gcount_line
            and lcount_line
            and last_dl_line
        ):
            break

    def parse_count(line):
        if not line:
            return None
        parts = line.rsplit(":", 1)
        if len(parts) != 2:
            return None
        try:
            return int(parts[1].strip())
        except ValueError:
            return None

    gcount = parse_count(gcount_line)
    lcount = parse_count(lcount_line)
    data["google_count"] = gcount
    data["local_count"] = lcount

    # Last sync
    if last_sync_line:
        data["status_raw"] = last_sync_line
        ts = last_sync_line[:19]
        try:
            dt = datetime.fromisoformat(ts.replace(" ", "T"))
            data["last_sync"] = dt.strftime("%Y-%m-%d %H:%M:%S")
        except Exception:
            data["last_sync"] = ts

        if "SYNC_RESULT: OK" in last_sync_line:
            data["level"] = "ok"
            data["status_label"] = "OK"
            data["status_headline"] = "Last sync succeeded"
        elif "SYNC_RESULT: RESTART" in last_sync_line:
            data["level"] = "warn"
            data["status_label"] = "RESTART"
            data["status_headline"] = "Last sync requested service restart"
        elif "SYNC_RESULT: FAIL" in last_sync_line:
            data["level"] = "err"
            data["status_label"] = "FAIL"
            data["status_headline"] = "Last sync failed"
        else:
            data["level"] = "warn"
            data["status_label"] = "UNKNOWN"
            data["status_headline"] = "Last sync status unknown"

    # Last restart
    if last_restart_line:
        ts = last_restart_line[:19]
        try:
            dt = datetime.fromisoformat(ts.replace(" ", "T"))
            data["last_restart"] = dt.strftime("%Y-%m-%d %H:%M:%S")
        except Exception:
            data["last_restart"] = ts

    # Last file download
    if last_dl_line:
        ts = last_dl_line[:19]
        try:
            dt = datetime.fromisoformat(ts.replace(" ", "T"))
            ts_fmt = dt.strftime("%Y-%m-%d %H:%M:%S")
        except Exception:
            ts_fmt = ts
        data["last_file_download"] = {
            "time": ts_fmt,
            "source": "frame_sync.sh",
            "line": last_dl_line.strip(),
        }

    return data


def get_counts_from_chk_sync():
    """
    Run chk_sync.sh in quick mode and parse the "Remote file count" and
    "Local  file count" from its output.

    Returns (remote_count, local_count), each possibly None if parsing fails.
    """
    if not CHK_SCRIPT.exists():
        return None, None

    try:
        result = subprocess.run(
            [str(CHK_SCRIPT)],
            capture_output=True,
            text=True,
            check=False,
        )
    except Exception:
        return None, None

    if result.returncode != 0:
        return None, None

    remote_count = None
    local_count = None

    for line in result.stdout.splitlines():
        m = re.search(r"Remote file count:\\s*(\\d+)", line)
        if m:
            remote_count = int(m.group(1))
        m = re.search(r"Local  file count:\\s*(\\d+)", line)
        if m:
            local_count = int(m.group(1))

    return remote_count, local_count


def get_web_service_status():
    info = {
        "web_status_level": "warn",
        "web_status_label": "UNKNOWN",
        "web_status_raw": None,
    }
    try:
        result = subprocess.run(
            ["systemctl", "is-active", WEB_SERVICE_NAME],
            capture_output=True,
            text=True,
            check=False,
        )
        state = (result.stdout or "").strip()

        if state == "active":
            info["web_status_level"] = "ok"
            info["web_status_label"] = "RUNNING"
            info["web_status_raw"] = state
        elif state in ("activating", "reloading"):
            info["web_status_level"] = "warn"
            info["web_status_label"] = state.upper()
            info["web_status_raw"] = state
        else:
            info["web_status_level"] = "err"
            info["web_status_label"] = (state or "unknown").upper()
            info["web_status_raw"] = state or "unknown"
    except Exception as e:
        info["web_status_level"] = "err"
        info["web_status_label"] = "ERROR"
        info["web_status_raw"] = str(e)
    return info


def get_picframe_service_status():
    info = {
        "pf_status_level": "warn",
        "pf_status_label": "UNKNOWN",
        "pf_status_raw": None,
    }
    try:
        env = os.environ.copy()
        env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")

        result = subprocess.run(
            ["systemctl", "--user", "is-active", PF_SERVICE_NAME],
            capture_output=True,
            text=True,
            check=False,
            env=env,
        )
        state = (result.stdout or "").strip()

        if state == "active":
            info["pf_status_level"] = "ok"
            info["pf_status_label"] = "RUNNING"
            info["pf_status_raw"] = state
        elif state in ("activating", "reloading"):
            info["pf_status_level"] = "warn"
            info["pf_status_label"] = state.upper()
            info["pf_status_raw"] = state
        else:
            info["pf_status_level"] = "err"
            info["pf_status_label"] = (state or "unknown").upper()
            info["pf_status_raw"] = state or "unknown"
    except Exception as e:
        info["pf_status_level"] = "err"
        info["pf_status_label"] = "ERROR"
        info["pf_status_raw"] = str(e)
    return info


def get_status_payload():
    """Compose the full status payload for the dashboard API."""
    # Base info from log (last run, restart, file download, status label, etc.)
    status = parse_status_from_log()
    # Live counts from chk_sync.sh for the *current* remote
    rc, lc = get_counts_from_chk_sync()
    if rc is not None:
        # Semantic: this is actually the remote count, but keep original key name for compatibility
        status["google_count"] = rc
    if lc is not None:
        status["local_count"] = lc

    status["generated_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    status.update(get_web_service_status())
    status.update(get_picframe_service_status())
    return status


def run_chk_sync_detailed():
    """Run chk_sync.sh --d and return a dict with exit_code/stdout/stderr."""
    if not CHK_SCRIPT.exists():
        return {
            "exit_code": -1,
            "stdout": "",
            "stderr": f"chk_sync.sh not found at {CHK_SCRIPT}",
        }

    try:
        result = subprocess.run(
            [str(CHK_SCRIPT), "--d"],
            capture_output=True,
            text=True,
            check=False,
        )
        return {
            "exit_code": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    except Exception as e:
        return {
            "exit_code": -1,
            "stdout": "",
            "stderr": str(e),
        }
