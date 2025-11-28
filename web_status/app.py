#!/usr/bin/env python3
import os
from pathlib import Path
from datetime import datetime

from flask import Flask, jsonify, render_template_string

app = Flask(__name__)

# -------------------------------------------------------------------
# Paths / service names
# -------------------------------------------------------------------
LOG_PATH = Path("/home/pi/logs/frame_sync.log")
CHK_SCRIPT = Path("/home/pi/picframe_3.0/ops_tools/chk_sync.sh")

CONFIG_FILE = Path("/home/pi/picframe_3.0/config/frame_sources.conf")
FRAME_LIVE = Path("/home/pi/Pictures/frame_live")

WEB_SERVICE_NAME = "pf-web-status.service"   # system service
PF_SERVICE_NAME = "picframe.service"         # user service (systemctl --user)

# -------------------------------------------------------------------
# HTML template
# -------------------------------------------------------------------

DASHBOARD_HTML = """
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>PicFrame Sync Dashboard</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">

    <style>
        :root {
            color-scheme: dark;
        }
        body {
            margin: 0;
            padding: 0;
            font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            background: radial-gradient(circle at top, #1f2933 0, #020617 55%);
            color: #e5e7eb;
        }
        .page {
            max-width: 1100px;
            margin: 0 auto;
            padding: 1.5rem 1.25rem 3rem;
        }
        h1 {
            font-size: 1.8rem;
            margin: 0 0 0.5rem;
        }
        .subtitle {
            font-size: 0.9rem;
            color: #9ca3af;
            margin-bottom: 1.5rem;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
            gap: 1rem;
        }
        .card {
            background: rgba(15, 23, 42, 0.92);
            border-radius: 0.75rem;
            padding: 1rem 1.1rem;
            box-shadow: 0 18px 45px rgba(0, 0, 0, 0.45);
            border: 1px solid rgba(148, 163, 184, 0.18);
        }
        .card-header {
            display: flex;
            justify-content: space-between;
            align-items: baseline;
            margin-bottom: 0.5rem;
        }
        .card-title {
            font-size: 1rem;
            font-weight: 600;
        }
        .card-subtitle {
            font-size: 0.8rem;
            color: #9ca3af;
        }
        .status-pill {
            display: inline-flex;
            align-items: center;
            padding: 0.2rem 0.55rem;
            border-radius: 999px;
            font-size: 0.7rem;
            font-weight: 600;
            letter-spacing: 0.03em;
            text-transform: uppercase;
        }
        .status-ok {
            background: rgba(22, 163, 74, 0.15);
            color: #4ade80;
            border: 1px solid rgba(34, 197, 94, 0.45);
        }
        .status-warn {
            background: rgba(202, 138, 4, 0.15);
            color: #facc15;
            border: 1px solid rgba(234, 179, 8, 0.45);
        }
        .status-bad {
            background: rgba(220, 38, 38, 0.16);
            color: #f97373;
            border: 1px solid rgba(248, 113, 113, 0.55);
        }

        .metric-row {
            display: flex;
            flex-wrap: wrap;
            gap: 0.75rem;
            margin-top: 0.4rem;
        }
        .metric {
            min-width: 120px;
        }
        .metric-label {
            font-size: 0.75rem;
            color: #9ca3af;
            margin-bottom: 0.1rem;
        }
        .metric-value {
            font-size: 1.2rem;
            font-weight: 600;
        }
        .metric-value.small {
            font-size: 0.9rem;
            font-weight: 500;
        }

        .mono {
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
        }
        .log-box {
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
            font-size: 0.75rem;
            background: rgba(15, 23, 42, 0.85);
            border-radius: 0.6rem;
            padding: 0.75rem 0.85rem;
            max-height: 260px;
            overflow: auto;
            white-space: pre-wrap;
            border: 1px solid rgba(51, 65, 85, 0.9);
        }

        .btn-row {
            display: flex;
            flex-wrap: wrap;
            gap: 0.5rem;
            margin-top: 0.75rem;
        }
        button {
            cursor: pointer;
            border-radius: 999px;
            border: 1px solid rgba(148, 163, 184, 0.35);
            background: radial-gradient(circle at top left, #1e293b, #020617);
            color: #e5e7eb;
            font-size: 0.78rem;
            font-weight: 500;
            padding: 0.4rem 0.9rem;
        }
        button:hover {
            border-color: rgba(248, 250, 252, 0.65);
        }
        button:disabled {
            opacity: 0.5;
            cursor: default;
        }

        .footer {
            margin-top: 2rem;
            font-size: 0.7rem;
            color: #6b7280;
            text-align: right;
        }
    </style>
</head>
<body>
<div class="page">
    <h1>PicFrame Status</h1>
    <div class="subtitle">
        Overall sync health, source selection, and recent activity.
    </div>

    <div class="grid">
        <!-- Overall status + current source -->
        <div class="card">
            <div class="card-header">
                <div>
                    <div class="card-title">Overall Status</div>
                    <div class="card-subtitle" id="last-sync-text">
                        Loading…
                    </div>
                </div>
                <div id="overall-pill" class="status-pill status-warn">
                    Pending
                </div>
            </div>

            <div class="metric-row">
                <div class="metric">
                    <div class="metric-label">Current Source</div>
                    <div class="metric-value small" id="current-source-label">–</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Source Directory</div>
                    <div class="metric-value small mono" id="current-source-path">–</div>
                </div>
            </div>

            <div class="metric-row" style="margin-top: 0.5rem;">
                <div class="metric">
                    <div class="metric-label">Files in Source Directory</div>
                    <div class="metric-value" id="current-source-count">–</div>
                </div>
            </div>

            <div class="btn-row">
                <button id="btn-refresh" type="button" onclick="refreshStatus()">Refresh</button>
            </div>
        </div>

        <!-- Counts (Remote / Local) -->
        <div class="card">
            <div class="card-header">
                <div class="card-title">Counts</div>
                <div class="card-subtitle">Latest from logs</div>
            </div>
            <div class="metric-row">
                <div class="metric">
                    <div class="metric-label">Remote Count</div>
                    <div class="metric-value" id="remote-count">–</div>
                </div>
                <div class="metric">
                    <div class="metric-label">Local Count</div>
                    <div class="metric-value" id="local-count">–</div>
                </div>
            </div>
            <div class="metric-row" style="margin-top: 0.6rem;">
                <div class="metric">
                    <div class="metric-label">Remote − Local</div>
                    <div class="metric-value small" id="count-delta">–</div>
                </div>
            </div>
        </div>

        <!-- Log snippet -->
        <div class="card">
            <div class="card-header">
                <div class="card-title">Recent Log</div>
                <div class="card-subtitle mono" id="log-file-name"></div>
            </div>
            <div class="log-box" id="log-box">
                Loading log…
            </div>
        </div>
    </div>

    <div class="footer">
        PicFrame 3.0 – web status
    </div>
</div>

<script>
async function refreshStatus() {
    const btn = document.getElementById("btn-refresh");
    if (btn) {
        btn.disabled = true;
        btn.textContent = "Refreshing…";
    }

    try {
        const resp = await fetch("/api/status");
        if (!resp.ok) {
            throw new Error("HTTP " + resp.status);
        }
        const data = await resp.json();

        // Overall pill
        const pill = document.getElementById("overall-pill");
        if (pill) {
            pill.textContent = data.overall_status_label || "Unknown";

            pill.classList.remove("status-ok", "status-warn", "status-bad");
            if (data.overall_status_level === "ok") {
                pill.classList.add("status-ok");
            } else if (data.overall_status_level === "warn") {
                pill.classList.add("status-warn");
            } else if (data.overall_status_level === "bad") {
                pill.classList.add("status-bad");
            } else {
                pill.classList.add("status-warn");
            }
        }

        const lastSyncText = document.getElementById("last-sync-text");
        if (lastSyncText) {
            lastSyncText.textContent = data.last_sync_text || "No sync info found.";
        }

        // Current source
        const csLabel = document.getElementById("current-source-label");
        const csPath = document.getElementById("current-source-path");
        const csCount = document.getElementById("current-source-count");

        if (csLabel) {
            if (data.current_source_id && data.current_source_label) {
                csLabel.textContent = data.current_source_id + " – " + data.current_source_label;
            } else {
                csLabel.textContent = "Unknown";
            }
        }
        if (csPath) {
            csPath.textContent = data.current_source_path || "–";
        }
        if (csCount) {
            csCount.textContent = (data.current_source_count !== null && data.current_source_count !== undefined)
                ? data.current_source_count
                : "–";
        }

        // Counts
        const remoteCountEl = document.getElementById("remote-count");
        const localCountEl = document.getElementById("local-count");
        const deltaEl = document.getElementById("count-delta");

        if (remoteCountEl) {
            remoteCountEl.textContent = (data.remote_count !== null && data.remote_count !== undefined)
                ? data.remote_count
                : "–";
        }
        if (localCountEl) {
            localCountEl.textContent = (data.local_count !== null && data.local_count !== undefined)
                ? data.local_count
                : "–";
        }

        if (deltaEl) {
            if (data.remote_count !== null && data.local_count !== null &&
                data.remote_count !== undefined && data.local_count !== undefined) {
                const delta = data.remote_count - data.local_count;
                let txt = delta;
                if (delta > 0) {
                    txt = "+" + delta;
                }
                deltaEl.textContent = txt;
            } else {
                deltaEl.textContent = "–";
            }
        }

        // Log box
        const logBox = document.getElementById("log-box");
        const logFileName = document.getElementById("log-file-name");
        if (logBox) {
            logBox.textContent = data.log_tail || "No log data.";
        }
        if (logFileName) {
            logFileName.textContent = data.log_path || "";
        }
    } catch (err) {
        console.error(err);
        const pill = document.getElementById("overall-pill");
        if (pill) {
            pill.textContent = "Error";
            pill.classList.remove("status-ok");
            pill.classList.add("status-bad");
        }
        const logBox = document.getElementById("log-box");
        if (logBox) {
            logBox.textContent = "Failed to fetch status: " + err;
        }
    } finally {
        if (btn) {
            btn.disabled = false;
            btn.textContent = "Refresh";
        }
    }
}

// Auto-refresh on load
window.addEventListener("load", () => {
    refreshStatus();
    // Optional: periodic refresh
    setInterval(refreshStatus, 30000);
});
</script>
</body>
</html>
"""

# -------------------------------------------------------------------
# Backend helpers
# -------------------------------------------------------------------

def read_log_tail(max_bytes: int = 8000) -> str:
    """Return the last ~max_bytes from the log file as a string."""
    if not LOG_PATH.exists():
        return "Log file not found: {}".format(LOG_PATH)

    try:
        size = LOG_PATH.stat().st_size
        start = max(0, size - max_bytes)
        with LOG_PATH.open("rb") as f:
            f.seek(start)
            data = f.read().decode(errors="replace")
        return data
    except Exception as e:
        return f"Error reading log file: {e}"


def parse_counts_from_log():
    """
    Parse remote/local counts from the log.

    Assumes frame_sync.sh logs lines like:
      "... Post-sync Google count: 123"
      "... Post-sync Local count:  123"
    If not found, returns (None, None).
    """
    if not LOG_PATH.exists():
        return None, None

    remote = None
    local = None

    try:
        with LOG_PATH.open("r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except Exception:
        return None, None

    # Walk backwards to find the latest occurrences
    for line in reversed(lines):
        if remote is None and "Post-sync Google count:" in line:
            try:
                remote = int(line.strip().split(":")[-1])
            except ValueError:
                remote = None
        if local is None and "Post-sync Local count:" in line:
            try:
                local = int(line.strip().split(":")[-1])
            except ValueError:
                local = None
        if remote is not None and local is not None:
            break

    return remote, local


def parse_last_sync_text():
    """
    Pull a simple 'last sync' summary from the log.

    Looks for a line containing 'SYNC_RESULT' or falls back to last line.
    """
    if not LOG_PATH.exists():
        return "Log file not found."

    try:
        with LOG_PATH.open("r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except Exception as e:
        return f"Error reading log file: {e}"

    last_line = lines[-1].strip() if lines else ""
    sync_line = None

    for line in reversed(lines):
        if "SYNC_RESULT" in line:
            sync_line = line.strip()
            break

    if sync_line:
        return sync_line
    elif last_line:
        return last_line
    else:
        return "No log entries found."


def determine_overall_status(remote_count, local_count):
    """
    Decide 'ok' / 'warn' / 'bad' based on counts.
    """
    if remote_count is None or local_count is None:
        return "warn", "Unknown"

    if remote_count == local_count:
        return "ok", "In Sync"

    # Simple heuristic: mismatch -> warn
    return "warn", "Mismatch"


def load_sources_from_config():
    """
    Load sources from frame_sources.conf.
    Returns list of dicts: {id, label, path, enabled}.
    """
    sources = []
    if not CONFIG_FILE.exists():
        return sources

    try:
        with CONFIG_FILE.open("r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split("|")
                if len(parts) != 4:
                    continue
                sid, label, path, enabled = parts
                sources.append({
                    "id": sid.strip(),
                    "label": label.strip(),
                    "path": path.strip(),
                    "enabled": enabled.strip() == "1",
                })
    except Exception:
        # Fail silently; caller will see no sources
        pass

    return sources


def get_current_source_info():
    """
    Return (source_id, label, path, file_count) for current source.

    - path is from the frame_live symlink target (readlink -f).
    - id/label are matched via frame_sources.conf (if possible).
    - file_count is a filesystem walk count under that dir.
    """
    if not FRAME_LIVE.exists() and not FRAME_LIVE.is_symlink():
        return None, None, None, None

    try:
        source_path = FRAME_LIVE.resolve()
    except Exception:
        return None, None, None, None

    # Map to config if possible
    sources = load_sources_from_config()
    source_id = None
    source_label = None
    for s in sources:
        try:
            if Path(s["path"]).resolve() == source_path:
                source_id = s["id"]
                source_label = s["label"]
                break
        except Exception:
            continue

    # Count files under the directory
    file_count = None
    if source_path.is_dir():
        try:
            total = 0
            for _, _, files in os.walk(source_path):
                total += len(files)
            file_count = total
        except Exception:
            file_count = None

    return source_id, source_label, str(source_path), file_count


# -------------------------------------------------------------------
# Routes
# -------------------------------------------------------------------

@app.route("/")
def index():
    return render_template_string(DASHBOARD_HTML)


@app.route("/api/status")
def api_status():
    # Counts from log
    remote_count, local_count = parse_counts_from_log()
    status_level, status_label = determine_overall_status(remote_count, local_count)

    last_sync = parse_last_sync_text()
    log_tail = read_log_tail()

    # Current source info
    src_id, src_label, src_path, src_count = get_current_source_info()

    payload = {
        "overall_status_level": status_level,
        "overall_status_label": status_label,
        "last_sync_text": last_sync,

        "remote_count": remote_count,
        "local_count": local_count,

        "current_source_id": src_id,
        "current_source_label": src_label,
        "current_source_path": src_path,
        "current_source_count": src_count,

        "log_tail": log_tail,
        "log_path": str(LOG_PATH),
    }

    return jsonify(payload)


if __name__ == "__main__":
    # Typically managed by systemd, but this is fine for manual runs
    app.run(host="0.0.0.0", port=5000, debug=False)
