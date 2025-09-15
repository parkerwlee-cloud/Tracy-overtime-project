#!/usr/bin/env bash
set -euo pipefail
source .venv/bin/activate 2>/dev/null || true
python scripts/migrate.py
