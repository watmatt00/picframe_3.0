#!/usr/bin/env python3
"""
read_auto_update_config.py - Output auto-update config for shell scripts

This helper script reads the PicFrame config and outputs auto-update settings
in a format that can be easily parsed by bash scripts.

Output format (one key=value per line):
    ENABLED=true
    FREQUENCY=monthly
    DAY=0
    HOUR=3
    MINUTE=30

Usage:
    python3 read_auto_update_config.py
"""

import sys
from pathlib import Path

# Add web_status to path for config_manager import
script_dir = Path(__file__).resolve().parent
web_status_dir = script_dir.parent / "web_status"
sys.path.insert(0, str(web_status_dir))

from config_manager import get_config_with_defaults


def main():
    """Read config and output auto-update settings."""
    config = get_config_with_defaults()

    # Output in shell-friendly format
    print(f"ENABLED={config.get('AUTO_UPDATE_ENABLED', 'false')}")
    print(f"FREQUENCY={config.get('AUTO_UPDATE_FREQUENCY', 'monthly')}")
    print(f"DAY={config.get('AUTO_UPDATE_DAY', '0')}")
    print(f"HOUR={config.get('AUTO_UPDATE_HOUR', '3')}")
    print(f"MINUTE={config.get('AUTO_UPDATE_MINUTE', '30')}")


if __name__ == "__main__":
    main()
