#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "==> Update-all: pulling latest..."
if git diff --quiet; then
  git pull --rebase --autostash
else
  echo "⚠️ Local changes detected. Stashing..."
  git stash push -u -m "update-all-$(date +%F-%H%M%S)"
  git pull --rebase
  echo "Re-applying stash (if clean)..."
  git stash pop || true
fi

echo "==> Re-running setup steps..."
chmod +x setup.sh
./setup.sh

echo "==> Restarting service (if installed)..."
if systemctl list-unit-files | grep -q "^overtime-kiosk.service"; then
  sudo systemctl restart overtime-kiosk.service || true
fi

echo "==> Re-mapping touchscreen..."
/usr/local/bin/map-touch-by-name.sh || true

echo "✅ Update-all complete."
