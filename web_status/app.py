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
    run_restart_pf_service,
    run_restart_web_service,
    get_sources_from_conf,
    add_source_to_conf,
    delete_source_from_conf,
    get_frame_live_target,
    set_frame_live_target,
    validate_source_data,
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


@app.route("/api/restart-pf", methods=["POST"])
def api_restart_pf():
    """Trigger pf_restart_svc.sh and return its output as JSON."""
    result = run_restart_pf_service()
    return jsonify(result)


@app.route("/api/restart-web", methods=["POST"])
def api_restart_web():
    """Trigger pf_web_restart_svc.sh and return its output as JSON."""
    result = run_restart_web_service()
    return jsonify(result)


@app.route("/api/sync-now", methods=["POST"])
def api_sync_now():
    """Trigger frame_sync.sh immediately and return its output as JSON."""
    from status_backend import run_sync_now
    result = run_sync_now()
    return jsonify(result)


@app.route("/api/current-image")
def api_current_image():
    """Proxy the current image from picframe's web interface (port 9000)."""
    import urllib.request
    try:
        with urllib.request.urlopen("http://localhost:9000/current_image", timeout=5) as response:
            image_data = response.read()
            return Response(image_data, mimetype="image/jpeg")
    except Exception as e:
        # Return a placeholder or error response
        return jsonify({"error": str(e)}), 500


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
# Rclone and Directory Management API Routes
# ---------------------------------------------------------------------------

@app.route("/api/rclone/remotes")
def api_get_rclone_remotes():
    """
    List configured rclone remotes.
    
    Response:
        {"ok": true, "remotes": ["kfgdrive:", "kfrphotos:"]} or {"ok": false, "error": "..."}
    """
    env = os.environ.copy()
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
    
    try:
        result = subprocess.run(
            ["rclone", "listremotes"],
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
        )
        
        if result.returncode != 0:
            error_msg = result.stderr.strip() or "Failed to list remotes"
            return jsonify({"ok": False, "error": error_msg}), 500
        
        # Parse output - each line is a remote name ending with ":"
        remotes = [line.strip() for line in result.stdout.strip().splitlines() if line.strip()]
        return jsonify({"ok": True, "remotes": remotes})
        
    except subprocess.TimeoutExpired:
        return jsonify({"ok": False, "error": "Command timed out"}), 500
    except FileNotFoundError:
        return jsonify({"ok": False, "error": "rclone not found - is it installed?"}), 500
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


def _has_problematic_spaces(dirname):
    """
    Check if directory name has leading or trailing spaces.

    Args:
        dirname: The directory name to check

    Returns:
        tuple: (has_problem, trimmed_name)
            - has_problem: True if directory has leading/trailing spaces
            - trimmed_name: The directory name with spaces stripped
    """
    if not dirname:
        return False, dirname

    trimmed = dirname.strip()
    has_problem = (dirname != trimmed)

    return has_problem, trimmed


@app.route("/api/rclone/list-dirs", methods=["POST"])
def api_list_remote_dirs():
    """
    List directories at remote path.

    Request body: {"remote": "kfgdrive:", "path": "dframe"}

    Response:
        {"ok": true, "dirs": ["2024", "2023"]} or {"ok": false, "error": "..."}
    """
    import json

    data = request.json or {}
    remote = data.get("remote", "").strip()
    path = data.get("path", "").strip()

    if not remote:
        return jsonify({"ok": False, "error": "No remote specified"}), 400

    # Build full remote path
    if path:
        full_path = f"{remote}{path}"
    else:
        full_path = remote

    env = os.environ.copy()
    env.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")

    try:
        # Use lsjson instead of lsd to preserve exact directory names
        result = subprocess.run(
            ["rclone", "lsjson", "--dirs-only", full_path],
            capture_output=True,
            text=True,
            timeout=30,
            env=env,
        )

        if result.returncode != 0:
            error_msg = result.stderr.strip() or "Failed to list directories"
            return jsonify({"ok": False, "error": error_msg}), 500

        # Parse JSON output - preserves exact directory names
        dirs = []
        try:
            json_data = json.loads(result.stdout)
            for item in json_data:
                if item.get("IsDir", False):
                    dir_name = item.get("Name", "")

                    # Check for problematic spaces
                    has_problem, trimmed_name = _has_problematic_spaces(dir_name)

                    dirs.append({
                        "name": dir_name,
                        "valid": not has_problem,
                        "trimmed_name": trimmed_name if has_problem else None,
                        "reason": "Directory name has leading or trailing spaces" if has_problem else None
                    })
        except json.JSONDecodeError as e:
            return jsonify({"ok": False, "error": f"Failed to parse rclone output: {e}"}), 500

        return jsonify({"ok": True, "dirs": dirs})

    except subprocess.TimeoutExpired:
        return jsonify({"ok": False, "error": "Command timed out (30s)"}), 500
    except FileNotFoundError:
        return jsonify({"ok": False, "error": "rclone not found - is it installed?"}), 500
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/local/list-dirs")
def api_list_local_dirs():
    """
    List directories in /home/pi/Pictures.
    
    Response:
        {"ok": true, "dirs": ["gdt_frame", "kfr_frame"]} or {"ok": false, "error": "..."}
    """
    from pathlib import Path
    
    pictures_dir = Path.home() / "Pictures"
    
    try:
        if not pictures_dir.exists():
            return jsonify({"ok": False, "error": f"Pictures directory not found: {pictures_dir}"}), 404
        
        if not pictures_dir.is_dir():
            return jsonify({"ok": False, "error": f"Not a directory: {pictures_dir}"}), 400
        
        # List all directories (excluding symlinks for clarity)
        dirs = []
        for item in sorted(pictures_dir.iterdir()):
            if item.is_dir() and not item.is_symlink():
                dirs.append(item.name)
        
        return jsonify({"ok": True, "dirs": dirs})
        
    except PermissionError:
        return jsonify({"ok": False, "error": "Permission denied accessing Pictures directory"}), 403
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/sources/create", methods=["POST"])
def api_create_source():
    """
    Create a new source in frame_sources.conf.

    Request body: {
        "source_id": "mycloud",
        "label": "My Cloud Photos",
        "path": "/home/pi/Pictures/mycloud_frame",
        "enabled": true,
        "rclone_remote": "mydrive:photos",
        "create_directory": false
    }

    Response:
        {"ok": true} or {"ok": false, "error": "..."}
    """
    data = request.json or {}

    source_id = data.get("source_id", "").strip()
    label = data.get("label", "").strip()
    path = data.get("path", "").strip()
    enabled = data.get("enabled", True)
    rclone_remote = data.get("rclone_remote", "").strip()
    create_directory = data.get("create_directory", False)

    # Validate
    is_valid, error = validate_source_data(source_id, label, path, rclone_remote)
    if not is_valid:
        return jsonify({"ok": False, "error": error}), 400

    # Add to config
    success, error = add_source_to_conf(source_id, label, path, enabled, rclone_remote, create_directory)

    if success:
        return jsonify({"ok": True})
    else:
        return jsonify({"ok": False, "error": error}), 500


@app.route("/api/sources/delete", methods=["POST"])
def api_delete_source():
    """
    Delete a source from frame_sources.conf.

    Request body: {
        "source_id": "mycloud"
    }

    Response:
        {"ok": true} or {"ok": false, "error": "..."}
    """
    data = request.json or {}
    source_id = data.get("source_id", "").strip()

    if not source_id:
        return jsonify({"ok": False, "error": "Source ID is required"}), 400

    success, error = delete_source_from_conf(source_id)

    if success:
        return jsonify({"ok": True})
    else:
        return jsonify({"ok": False, "error": error}), 500


@app.route("/api/frame-live")
def api_get_frame_live():
    """
    Get the current frame_live symlink target.

    Response:
        {
            "exists": bool,
            "is_symlink": bool,
            "target": str,
            "target_name": str
        }
    """
    result = get_frame_live_target()
    return jsonify(result)


@app.route("/api/frame-live", methods=["POST"])
def api_set_frame_live():
    """
    Set the frame_live symlink to point to a new directory.

    Request body: {
        "target_dir": "/home/pi/Pictures/kfr_frame"
    }

    Response:
        {"ok": true} or {"ok": false, "error": "..."}
    """
    data = request.json or {}
    target_dir = data.get("target_dir", "").strip()

    if not target_dir:
        return jsonify({"ok": False, "error": "Target directory is required"}), 400

    success, error = set_frame_live_target(target_dir)

    if success:
        # Trigger sync for the new source
        from status_backend import run_sync_now
        sync_result = run_sync_now()

        # Return success with sync status
        return jsonify({
            "ok": True,
            "sync_triggered": True,
            "sync_output": sync_result.get("output", "")
        })
    else:
        return jsonify({"ok": False, "error": error}), 500


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    # Bind to all interfaces on port 5050 (same as before)
    app.run(host="0.0.0.0", port=5050)
