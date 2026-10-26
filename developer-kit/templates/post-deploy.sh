#!/usr/bin/env bash
# Runs on the VM inside the new release before it goes live (install dependencies, build).
set -euo pipefail
# Examples (see README.md Part B for full recipes):
#   python3 -m venv .venv && .venv/bin/pip install -r requirements.txt     # Python / Flask / FastAPI / Django
#   .venv/bin/python manage.py migrate --noinput                            # Django
#   npm ci --omit=dev                                                       # Node.js server
#   npm ci && npm run build                                                 # React / Vite / Next.js
