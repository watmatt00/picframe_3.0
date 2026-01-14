#!/bin/bash
# Setup script to enable shared git hooks
# Run this once after cloning the repository

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Setting up shared git hooks..."

# Configure git to use the shared hooks directory
cd "$REPO_ROOT"
git config core.hooksPath .githooks

# Make hooks executable
chmod +x "$SCRIPT_DIR"/*

echo "✓ Git hooks configured"
echo ""
echo "Protected files (cannot be deleted without --no-verify):"
echo "  - .clinerules"
echo "  - CONTRIBUTING.md"
echo "  - README.md"
echo ""
echo "To disable shared hooks: git config --unset core.hooksPath"
