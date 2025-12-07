#!/usr/bin/env python3
"""
PicFrame Sync Dashboard - Web Application

Provides a web interface for monitoring and configuring PicFrame sync status.
"""

import socket
import subprocess
import os
from flask import Flask, jsonify, render_template, request, Response

from status_backend import (
    get_status_payload,
    run_chk_sync_detailed,
    get_sources_from_conf,
    _get_paths,
)

from config_manager import (
    read_config,
    write_config,
    validate_config,
    config_exists,
    get_config_path,
    CONFIG_SCHEMA,
)

app = Flask(__name__)


# ---------------------------------------------------------------------------
# Dashboard Routes
# ---------------------------------------------------------------------------

@app.route("/")
def dashboard():
    """Render the main dashboard page."""
    host_name = socket.gethostname().upper()
    paths = _get_paths()
    return render_template(
        "dashboard.html",
        host_name=host_name,
        script_path=str(paths["chk_script"]),
        log_path=str(paths["log_file"]),
    )


@app.route("/api/status")
def api_status():
    """Return current status JSON for the dashboard."""
    status = get_status_payload()
    return jsonify(status)


@app.route("/api/run-check", methods=["POST"])
def api_run_check():
    """Trigger chk_sync.sh --d and return its output as JSON."""
    result = run_chk_sync_detailed()
    return jsonify(result)


# Alias used by earlier JS versions, so both URLs work
@app.route("/api/run-chk-syncd", methods=["POST"])
def api_run_chk_syncd():
    result = run_chk_sync_detailed()
    return jsonify(result)


# ---------------------------------------------------------------------------
# Config API Routes
# ---------------------------------------------------------------------------

@app.route("/api/config")
def api_get_config():
    """
    Return current config and schema for the settings form.
    
    Response:
        {
            "exists": bool,
            "config": {...},
            "schema": {...},
            "config_path": str
        }
    """
    return jsonify({
        "exists": config_exists(),
        "config": read_config() if config_exists() else {},
        "schema": CONFIG_SCHEMA,
        "config_path": str(get_config_path()),
    })


@app.route("/api/config", methods=["POST"])
def api_save_config():
    """
    Save config from settings form.
    
    Request body: JSON object with config key-value pairs
    
    Response:
        {"ok": true} or {"ok": false, "errors": [...]}
    """
    data = request.json or {}
    
    validation = validate_config(data)
    if validation["errors"]:
        return jsonify({
            "ok": False,
            "errors": validation["errors"],
        }), 400
    
    try:
        write_config(data)
        return jsonify({
            "ok": True,
            "warnings": validation.get("warnings", []),
        })
    except Exception as e:
        return jsonify({
            "ok": False,
            "errors": [str(e)],
        }), 500


@app.route("/api/config/test-remote", methods=["POST"])
def api_test_remote():
    """
    Test rclone remote connectivity.
    
    Request body: {"remote": "mydrive:path"}
    
    Response:
        {"ok": true, "file_count": N} or {"ok": false, "error": "..."}
    """
    data = request.json or {}
    remote = data.get("remote", "").strip()
    
    if not remote:
        return jsonify({"ok": False, "error": "No remote specified"})
    
    env = os.environ.copy()
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
    
    try:
        result = subprocess.run(
            ["rclone", "lsf", remote, "--max-depth", "1"],
            capture_output=True,
            text=True,
            timeout=30,
            env=env,
        )
        
        if result.returncode != 0:
            error_msg = result.stderr.strip() or "Connection failed"
            return jsonify({"ok": False, "error": error_msg})
        
        file_count = len(result.stdout.strip().splitlines()) if result.stdout.strip() else 0
        return jsonify({"ok": True, "file_count": file_count})
        
    except subprocess.TimeoutExpired:
        return jsonify({"ok": False, "error": "Connection timed out (30s)"})
    except FileNotFoundError:
        return jsonify({"ok": False, "error": "rclone not found - is it installed?"})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})


@app.route("/api/config/export")
def api_export_config():
    """
    Download current config as a file.
    
    Response: Plain text file download
    """
    if not config_exists():
        return jsonify({"error": "No config to export"}), 404
    
    try:
        config_content = get_config_path().read_text(encoding="utf-8")
        hostname = socket.gethostname()
        filename = f"picframe-config-{hostname}.txt"
        
        return Response(
            config_content,
            mimetype="text/plain",
            headers={"Content-Disposition": f"attachment; filename={filename}"}
        )
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ---------------------------------------------------------------------------
# Source Management API Routes
# ---------------------------------------------------------------------------

@app.route("/api/sources")
def api_get_sources():
    """
    List available sources from frame_sources.conf.
    
    Response:
        {"sources": [{"id": "...", "label": "...", "path": "...", "enabled": bool, "active": bool}, ...]}
    """
    sources = get_sources_from_conf()
    return jsonify({"sources": sources})


@app.route("/api/sources/active", methods=["POST"])
def api_set_active_source():
    """
    Switch the active source by calling pf_source_ctl.sh.
    
    Request body: {"source_id": "kfr"}
    
    Response:
        {"ok": true, "output": "..."} or {"ok": false, "output": "..."}
    """
    data = request.json or {}
    source_id = data.get("source_id", "").strip()
    
    if not source_id:
        return jsonify({"ok": False, "output": "No source_id specified"}), 400
    
    paths = _get_paths()
    script = paths["app_root"] / "ops_tools" / "pf_source_ctl.sh"
    
    if not script.exists():
        return jsonify({"ok": False, "output": f"Script not found: {script}"}), 500
    
    env = os.environ.copy()
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
    
    try:
        result = subprocess.run(
            [str(script), "set", source_id],
            capture_output=True,
            text=True,
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
        
        return jsonify({
            "ok": result.returncode == 0,
            "output": output,
        })
        
    except subprocess.TimeoutExpired:
        return jsonify({"ok": False, "output": "Command timed out"})
    except Exception as e:
        return jsonify({"ok": False, "output": str(e)})


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    # Bind to all interfaces on port 5050 (same as before)
    app.run(host="0.0.0.0", port=5050)
