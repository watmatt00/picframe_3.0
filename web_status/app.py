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
            font-weight:
