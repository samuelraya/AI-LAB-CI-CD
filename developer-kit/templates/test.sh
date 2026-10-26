#!/usr/bin/env bash
# Runs on GitHub's machine before every deploy; a non-zero exit stops the deploy.
set -euo pipefail
# Examples:
#   pip install -r requirements.txt && python -m pytest -q
#   npm ci && npm test
echo "No tests configured in .cicd/test.sh"
