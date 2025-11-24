#!/usr/bin/env python3
import subprocess
import socket
from pathlib import Path
from datetime import datetime
from flask import Flask, jsonify, render_template_string

app = Flask(__name__)

# --- Paths you may edit if needed ---
LOG_PATH = Path("/home/pi/logs/frame_sync.log")
CHK_SCRIPT = Path("/home/pi/picframe_3.0/ops_tools/chk_sync.sh")
# ------------------------------------

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
            background: radial-gradient(circle at top, #111827 0, #020617 55%, #000 100%);
            color: #e5e7eb;
        }
        .banner {
            padding: 0.55rem 1.5rem;
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 0.75rem;
            font-size: 0.9rem;
            border-bottom: 1px solid rgba(15,23,42,0.9);
        }
        .banner-ok {
            background: linear-gradient(90deg, #065f46, #16a34a);
        }
        .banner-warn {
            background: linear-gradient(90deg, #92400e, #d97706);
        }
        .banner-err {
            background: linear-gradient(90deg, #7f1d1d, #b91c1c);
        }
        .banner-left {
            font-weight: 500;
        }
        .banner-right {
            font-size: 0.78rem;
            opacity: 0.9;
        }
        .shell {
            max-width: 1100px;
            margin: 0 auto;
            padding: 1.4rem 1.5rem 1.5rem;
        }
        .header {
            display: flex;
            flex-wrap: wrap;
            justify-content: space-between;
            align-items: center;
            gap: 1rem;
            margin-bottom: 1.25rem;
        }
        .title {
            font-size: 1.6rem;
            font-weight: 600;
            display: flex;
            align-items: center;
            gap: 0.75rem;
        }
        .badge {
            font-size: 0.75rem;
            text-transform: uppercase;
            letter-spacing: 0.07em;
            padding: 0.15rem 0.6rem;
            border-radius: 999px;
            border: 1px solid #4b5563;
            color: #e5e7eb;
        }
        .meta {
            font-size: 0.8rem;
            color: #9ca3af;
        }
        .grid {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(0, 3fr);
            gap: 1.25rem;
        }
        @media (max-width: 900px) {
            .grid {
                grid-template-columns: minmax(0, 1fr);
            }
        }
        .card {
            background: rgba(15,23,42,0.96);
            border-radius: 0.9rem;
            padding: 1.25rem 1.4rem;
            border: 1px solid rgba(55,65,81,0.9);
            box-shadow: 0 10px 35px rgba(0,0,0,0.6);
        }
        .card-title {
            font-size: 0.9rem;
            font-weight: 600;
            color: #d1d5db;
            margin-bottom: 0.5rem;
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 0.5rem;
        }
        .card-title span {
            font-size: 0.75rem;
            font-weight: 400;
            color: #9ca3af;
        }
        .traffic-container {
            display: flex;
            align-items: center;
            gap: 1.5rem;
        }
        .traffic {
            display: flex;
            flex-direction: column;
            gap: 0.35rem;
            padding: 0.6rem 0.7rem;
            background: radial-gradient(circle at top, #020617 0, #020617 60%, #000 100%);
            border-radius: 999px;
            border: 1px solid #111827;
            box-shadow: inset 0 0 10px rgba(0,0,0,0.7);
        }
        .light {
            width: 1.25rem;
            height: 1.25rem;
            border-radius: 999px;
            background: #111827;
            box-shadow: 0 0 0 1px #020617;
            opacity: 0.25;
        }
        .light.on-green {
            background: radial-gradient(circle at 30% 20%, #bbf7d0, #22c55e);
            box-shadow: 0 0 18px #22c55e;
            opacity: 1;
        }
        .light.on-yellow {
            background: radial-gradient(circle at 30% 20%, #fef3c7, #facc15);
            box-shadow: 0 0 18px #facc15;
            opacity: 1;
        }
        .light.on-red {
            background: radial-gradient(circle at 30% 20%, #fecaca, #ef4444);
            box-shadow: 0 0 20px #ef4444;
            opacity: 1;
        }
        .status-text-main {
            font-size: 1.1rem;
            font-weight: 500;
        }
        .status-chip {
            display: inline-flex;
            padding: 0.15rem 0.5rem;
            border-radius: 999px;
            font-size: 0.75rem;
            font-weight: 600;
            margin-left: 0.4rem;
        }
        .chip-ok { background:#065f46; color:#bbf7d0; }
        .chip-warn { background:#92400e; color:#fed7aa; }
        .chip-err { background:#7f1d1d; color:#fecaca; }
        .metrics {
            display: grid;
            grid-template-columns: repeat(3, minmax(0,1fr));
            gap: 0.65rem;
            margin-top: 0.9rem;
        }
        @media (max-width: 700px) {
            .metrics {
                grid-template-columns: repeat(2, minmax(0,1fr));
            }
        }
        .metric {
            padding: 0.55rem 0.7rem;
            border-radius: 0.7rem;
            background: #020617;
            border: 1px solid #111827;
        }
        .metric-label {
            font-size: 0.7rem;
            color: #9ca3af;
            text-transform: uppercase;
            letter-spacing: 0.08em;
            margin-bottom: 0.25rem;
        }
        .metric-value {
            font-size: 0.88rem;
            font-variant-numeric: tabular-nums;
        }
        .metric-value.mono {
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
        }
        pre {
            margin: 0.4rem 0 0;
            padding: 0.7rem 0.8rem;
            border-radius: 0.6rem;
            background: #020617;
            border: 1px solid #111827;
            font-size: 0.78rem;
            line-height: 1.4;
            overflow-x: auto;
            white-space: pre-wrap;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
        }
        .controls {
            display: flex;
            flex-wrap: wrap;
            gap: 0.5rem;
            align-items: center;
        }
        button {
            appearance: none;
            border: none;
            border-radius: 999px;
            padding: 0.45rem 0.9rem;
            font-size: 0.8rem;
            font-weight: 500;
            background: #1d4ed8;
            color: white;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 0.4rem;
            box-shadow: 0 4px 12px rgba(37,99,235,0.45);
        }
        button:hover {
            filter: brightness(1.05);
        }
        button[disabled] {
            opacity: 0.5;
            cursor: default;
            box-shadow: none;
        }
        .note {
            font-size: 0.75rem;
            color: #9ca3af;
        }
        .pill {
            font-size: 0.75rem;
            padding: 0.15rem 0.5rem;
            border-radius: 999px;
            border: 1px solid #374151;
        }
        .pill span {
            opacity: 0.7;
        }
        .footer {
            margin-top: 1rem;
            font-size: 0.7rem;
            color: #6b7280;
        }
        .log-toggle {
            font-size: 0.78rem;
            cursor: pointer;
            padding: 0.25rem 0.5rem;
            border-radius: 999px;
            border: 1px solid #374151;
        }
    </style>
</head>
<body>
<div id="statusBanner" class="banner banner-err">
    <div class="banner-left" id="bannerHeadline">Sync status</div>
    <div class="banner-right">
        <span id="bannerLabel">ERROR</span> · <span id="lastUpdated">Loading…</span>
    </div>
</div>

<div class="shell">
    <div class="header">
        <div>
            <div class="title">
                PicFrame Sync Dashboard
                <span class="badge">host: {{ hostname }}</span>
            </div>
            <div class="meta">
                Script: {{ script_path }} · Log: {{ log_path }}
            </div>
        </div>
    </div>

    <div class="grid">
        <!-- LEFT: Summary / traffic light -->
        <div class="card">
            <div class="card-title">
                Overall status
                <span id="statusLabelChip" class="pill"><span>Status:</span> <strong id="statusLabelText">—</strong></span>
            </div>
            <div class="traffic-container">
                <div class="traffic">
                    <div id="lightRed" class="light"></div>
                    <div id="lightYellow" class="light"></div>
                    <div id="lightGreen" class="light"></div>
                </div>
                <div>
                    <div class="status-text-main">
                        <span id="statusHeadline">Waiting for data…</span>
                        <span id="statusChip" class="status-chip chip-err" style="display:none;"></span>
                    </div>
                    <div class="meta" style="margin-top:0.35rem;">
                        Last sync result: <span id="statusRaw">—</span><br>
                        Last sync timestamp: <span id="lastSync">—</span>
                    </div>
                    <div class="metrics">
                        <div class="metric">
                            <div class="metric-label">Google count</div>
                            <div id="gCount" class="metric-value mono">—</div>
                        </div>
                        <div class="metric">
                            <div class="metric-label">Local count</div>
                            <div id="lCount" class="metric-value mono">—</div>
                        </div>
                        <div class="metric">
                            <div class="metric-label">Match status</div>
                            <div id="matchStatus" class="metric-value mono">—</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- RIGHT: log + detailed check -->
        <div class="card">
            <div class="card-title">
                Activity & tools
                <span>Uses log; chk_sync on demand</span>
            </div>
            <div class="controls" style="margin-bottom:0.5rem;">
                <button id="btnRefresh" type="button">↻ Refresh from log</button>
                <button id="btnRunCheck" type="button">▶ Run chk_sync.sh --d</button>
                <span class="note">
                    Log-only view · chk_sync.sh --d runs only when requested.
                </span>
            </div>

            <div class="metric" style="margin:0.75rem 0 1rem;">
                <div class="metric-label">Service restart</div>
                <div id="lastRestart" class="metric-value mono">—</div>
            </div>

            <div style="margin-top:0.5rem;">
                <div class="meta" style="display:flex;justify-content:space-between;align-items:center;gap:0.5rem;">
                    <span>Log tail (from frame_sync.log)</span>
                    <span id="logToggle" class="log-toggle">Show log ▼</span>
                </div>
                <div id="logSection" style="display:none;">
                    <pre id="logTail">Loading…</pre>
                </div>
            </div>
            <div style="margin-top:0.6rem;">
                <div class="meta">chk_sync.sh --d output:</div>
                <pre id="checkOutput">(not run yet)</pre>
            </div>
        </div>
    </div>

    <div class="footer">
        Auto-refreshes every 15 seconds · Designed for Pi on your LAN
    </div>
</div>

<script>
function applyStatusLights(level) {
    const red   = document.getElementById('lightRed');
    const yellow= document.getElementById('lightYellow');
    const green = document.getElementById('lightGreen');
    red.className = 'light';
    yellow.className = 'light';
    green.className = 'light';

    if (level === 'ok') {
        green.classList.add('on-green');
    } else if (level === 'warn') {
        yellow.classList.add('on-yellow');
    } else {
        red.classList.add('on-red');
    }
}

function applyStatusChip(level, label) {
    const chip = document.getElementById('statusChip');
    chip.style.display = 'inline-flex';
    chip.textContent = label || '';
    chip.className = 'status-chip';
    if (level === 'ok') {
        chip.classList.add('chip-ok');
    } else if (level === 'warn') {
        chip.classList.add('chip-warn');
    } else {
        chip.classList.add('chip-err');
    }
}

function applyBanner(level, headline, label, updatedAt) {
    const banner = document.getElementById('statusBanner');
    banner.className = 'banner';
    if (level === 'ok') {
        banner.classList.add('banner-ok');
    } else if (level === 'warn') {
        banner.classList.add('banner-warn');
    } else {
        banner.classList.add('banner-err');
    }
    document.getElementById('bannerHeadline').textContent = headline || 'Sync status';
    document.getElementById('bannerLabel').textContent = label || '';
    document.getElementById('lastUpdated').textContent = 'Updated: ' + (updatedAt || '—');
}

function updateMatchStatus(g, l) {
    const m = document.getElementById("matchStatus");

    if (g === null || l === null || g === undefined || l === undefined) {
        m.textContent = "NO DATA";
        return;
    }

    if (g === l) {
        m.textContent = "MATCH (✔)";
    } else {
        m.textContent = "MISMATCH (✖)";
    }
}

function refreshStatus() {
    fetch('/api/status')
        .then(r => r.json())
        .then(data => {
            const level = data.level || 'err';

            document.getElementById('statusHeadline').textContent = data.status_headline || 'Status unknown';
            document.getElementById('statusRaw').textContent = data.status_raw || '—';
            document.getElementById('lastSync').textContent = data.last_sync || '—';
            document.getElementById('lastRestart').textContent = data.last_restart || '—';
            document.getElementById('gCount').textContent = (data.google_count ?? '—');
            document.getElementById('lCount').textContent = (data.local_count ?? '—');

            document.getElementById('statusLabelText').textContent = data.status_label || '—';
            const labelChip = document.getElementById('statusLabelChip');
            labelChip.className = 'pill';
            if (level === 'ok') {
                labelChip.style.borderColor = '#22c55e';
            } else if (level === 'warn') {
                labelChip.style.borderColor = '#facc15';
            } else if (level === 'err') {
                labelChip.style.borderColor = '#ef4444';
            }

            document.getElementById('logTail').textContent = data.log_tail || '(log is empty or missing)';

            applyStatusLights(level);
            applyStatusChip(level, data.status_label || '');
            applyBanner(level, data.status_headline, data.status_label, data.generated_at);

            const g = (typeof data.google_count === "number") ? data.google_count : parseInt(data.google_count, 10);
            const l = (typeof data.local_count === "number") ? data.local_count : parseInt(data.local_count, 10);
            updateMatchStatus(isNaN(g) ? null : g, isNaN(l) ? null : l);
        })
        .catch(err => {
            document.getElementById('logTail').textContent = 'Error loading status: ' + err;
            applyStatusLights('err');
            applyStatusChip('err', 'ERROR');
            applyBanner('err', 'Error loading status', 'ERROR', '');
        });
}

function runCheck() {
    const btn = document.getElementById('btnRunCheck');
    btn.disabled = true;
    btn.textContent = 'Running chk_sync.sh --d…';
    fetch('/api/run-check')
        .then(r => r.json())
        .then(data => {
            const out = [];
            out.push('# chk_sync.sh --d run');
            out.push('Exit code: ' + data.exit_code);
            if (data.stdout) {
                out.push('');
                out.push('[stdout]');
                out.push(data.stdout);
            }
            if (data.stderr) {
                out.push('');
                out.push('[stderr]');
                out.push(data.stderr);
            }
            document.getElementById('checkOutput').textContent = out.join('\\n');
            refreshStatus();
        })
        .catch(err => {
            document.getElementById('checkOutput').textContent = 'Error running chk_sync: ' + err;
        })
        .finally(() => {
            btn.disabled = false;
            btn.textContent = '▶ Run chk_sync.sh --d';
        });
}

function setupLogToggle() {
    const toggle = document.getElementById('logToggle');
    const section = document.getElementById('logSection');
    let open = false;
    toggle.addEventListener('click', () => {
        open = !open;
        section.style.display = open ? 'block' : 'none';
        toggle.textContent = open ? 'Hide log ▲' : 'Show log ▼';
    });
}

document.addEventListener('DOMContentLoaded', () => {
    document.getElementById('btnRefresh').addEventListener('click', refreshStatus);
    document.getElementById('btnRunCheck').addEventListener('click', runCheck);
    setupLogToggle();
    refreshStatus();
    setInterval(refreshStatus, 15000);
});
</script>
</body>
</html>
"""

def parse_status_from_log():
    """
    Read the frame_sync.log and derive:
      - google/local counts
      - last sync line (SYNC_RESULT)
      - last restart line
      - match status drives green/red:
          * MATCH -> level 'ok'
          * MISMATCH -> level 'err'
      - fallback to SYNC_RESULT if counts missing
    """
    data = {
        "level": "err",
        "status_label": "NO DATA",
        "status_headline": "No log data available",
        "status_raw": None,
        "last_sync": None,
        "last_restart": None,
        "google_count": None,
        "local_count": None,
        "log_tail": None,
    }

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

    lines = text.splitlines()
    if not lines:
        data["status_headline"] = "Log is empty"
        data["log_tail"] = "(log file is empty)"
        return data

    # tail for display
    tail_lines = lines[-80:]
    data["log_tail"] = "\n".join(tail_lines)

    last_sync_line = None
    last_restart_line = None
    gcount_line = None
    lcount_line = None

    for line in reversed(lines):
        if last_sync_line is None and "SYNC_RESULT:" in line:
            last_sync_line = line
        if last_restart_line is None and "restart" in line.lower():
            last_restart_line = line
        if gcount_line is None and "Google count" in line:
            gcount_line = line
        if lcount_line is None and "Local count" in line:
            lcount_line = line
        if last_sync_line and gcount_line and lcount_line and last_restart_line:
            break

    # parse helper for counts
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

    # parse last sync line + timestamp
    if last_sync_line:
        data["status_raw"] = last_sync_line
        ts = last_sync_line[:19]
        try:
            dt = datetime.fromisoformat(ts.replace(" ", "T"))
            data["last_sync"] = dt.strftime("%Y-%m-%d %H:%M:%S")
        except Exception:
            data["last_sync"] = ts.strip() or None

        try:
            status_token = last_sync_line.split("SYNC_RESULT:")[1].strip()
        except IndexError:
            status_token = "UNKNOWN"
    else:
        status_token = "UNKNOWN"

    # parse restart timestamp if any
    if last_restart_line:
        ts = last_restart_line[:19]
        try:
            dt = datetime.fromisoformat(ts.replace(" ", "T"))
            data["last_restart"] = dt.strftime("%Y-%m-%d %H:%M:%S")
        except Exception:
            data["last_restart"] = ts.strip() or None

    status_upper = status_token.upper()

    # main rule: counts drive green/red when present
    if gcount is not None and lcount is not None:
        if gcount == lcount:
            data["level"] = "ok"
            data["status_label"] = "MATCH"
            data["status_headline"] = "Counts match"
        else:
            data["level"] = "err"
            data["status_label"] = "MISMATCH"
            data["status_headline"] = "Counts do not match"
    else:
        # fallback to SYNC_RESULT if we don't have both counts
        if "OK" in status_upper and "RESTART" not in status_upper:
            data["level"] = "ok"
            data["status_label"] = "OK"
            data["status_headline"] = "Sync is healthy"
        elif "RESTART" in status_upper or "WARN" in status_upper:
            data["level"] = "warn"
            data["status_label"] = "RESTART NEEDED"
            data["status_headline"] = "Attention required"
        elif "ERROR" in status_upper or "FAIL" in status_upper:
            data["level"] = "err"
            data["status_label"] = "ERROR"
            data["status_headline"] = "Sync errors detected"
        else:
            data["level"] = "warn"
            data["status_label"] = status_upper or "UNKNOWN"
            data["status_headline"] = "Status unclear"

    return data


@app.route("/")
def dashboard():
    hostname = socket.gethostname()
    return render_template_string(
        DASHBOARD_HTML,
        hostname=hostname,
        script_path=str(CHK_SCRIPT),
        log_path=str(LOG_PATH),
    )


@app.route("/api/status")
def api_status():
    status = parse_status_from_log()
    status["generated_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    return jsonify(status)


@app.route("/api/run-check")
def api_run_check():
    if not CHK_SCRIPT.exists():
        return jsonify(
            {
                "exit_code": -1,
                "stdout": "",
                "stderr": f"chk_sync.sh not found at {CHK_SCRIPT}",
            }
        )
    try:
        # run chk_sync.sh --d for detailed mode
        result = subprocess.run(
            [str(CHK_SCRIPT), "--d"],
            capture_output=True,
            text=True,
            check=False,
        )
        return jsonify(
            {
                "exit_code": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
            }
        )
    except Exception as e:
        return jsonify(
            {
                "exit_code": -1,
                "stdout": "",
                "stderr": str(e),
            }
        )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
