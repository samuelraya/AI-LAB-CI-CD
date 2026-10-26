#!/usr/bin/env bash
# Sourced by the numbered scripts: loads and validates the project env file given as $1.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo." >&2
    exit 1
fi
ENV_FILE="${1:-}"
if [[ -z "$ENV_FILE" || ! -f "$ENV_FILE" ]]; then
    echo "Usage: sudo bash $0 path/to/project.env" >&2
    exit 1
fi
# Strip Windows line endings in case the file was edited on a Windows laptop.
# shellcheck source=/dev/null
source <(tr -d '\r' <"$ENV_FILE")

if [[ ! "${PROJECT:-}" =~ ^[a-z][a-z0-9-]{0,29}$ ]]; then
    echo "PROJECT must be lowercase letters, digits or '-' (max 30), starting with a letter." >&2
    exit 1
fi

GROUP="grp_${PROJECT}"
FOLDER="/srv/projects/${PROJECT}"
CI_USER="ci-${PROJECT}"
APP_USER="app-${PROJECT}"
SERVICE="app-${PROJECT}.service"
RUNTIME_ENV="/etc/projects/${PROJECT}.env"
export GROUP FOLDER CI_USER APP_USER SERVICE RUNTIME_ENV
