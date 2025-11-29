#!/usr/bin/env python3
import socket
from flask import Flask, jsonify, render_template

from status_backend import (
    LOG_PATH,
    CHK_SCRIPT,
    get_status_payload,
    run_chk_sync_detailed,
)

app = Flask(__name__)


@app.route("/")
def dashboard():
    hostname = socket.gethostname()
    return render_template(
        "dashboard.html",
        hostname=hostname,
        script_path=str(CHK_SCRIPT),
        log_path=str(LOG_PATH),
    )


@app.route("/api/status")
def api_status():
    """Return overall sync + service status as JSON for the dashboard."""
    status = get_status_payload()
    return jsonify(status)


@app.route("/api/run-check", methods=["POST"])
def api_run_check():
    """Trigger chk_sync.sh --d and return its output as JSON."""
    result = run_chk_sync_detailed()
    return jsonify(result)


if __name__ == "__main__":
    # Bind to all interfaces on port 5050 (same as before)
    app.run(host="0.0.0.0", port=5050)
