#!/usr/bin/env python3
"""
Wrapper to start picframe with HEIF/HEIC support.

This registers the pillow-heif opener before starting picframe,
enabling support for iPhone HEIC photos.
"""
import sys

# Register HEIF opener before any image loading
try:
    from pillow_heif import register_heif_opener
    register_heif_opener()
except ImportError:
    print("Warning: pillow-heif not installed, HEIC support disabled", file=sys.stderr)

# Now start picframe
from picframe.start import main
sys.exit(main())
