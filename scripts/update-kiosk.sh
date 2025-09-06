#!/usr/bin/env bash
# scripts/update-kiosk.sh
# Pull latest repo changes safely, refresh venv/deps, migrate DB, restart service, show logs.
# Usage:
#   ./scripts/update-kiosk.sh           # stash-safe pull --rebase
#   ./scripts/update-kiosk.sh --force   # hard reset to remote default branch (DANGER: discards local edits)

set -euo pipefail

APPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$APPDIR"

SERVICE_NAME="overtime-kiosk"
VENV="$APPDIR/.venv"

force=0
if [[ "${1:-}" == "--force" ]]; then
  force=1
fi

echo "▶ Repo: $APPDIR"
echo "▶ Branch & remote detection"
# Determine default remote branch (main/master)
default_branch="$(git remote show origin | awk '/HEAD branch/ {print $NF}')"
default_branch="${default_branch:-main}"
current_branch="$(git rev-parse --abbrev-ref HEAD || echo "$default_branch")"

if [[ $force -eq 1 ]]; then
  echo "⚠ FORCE mode: discarding local changes and resetting to origin/${default_branch}"
  git fetch --all
  git reset --hard "origin/${default_branch}"
  git clean -fd
else
  echo "▶ Stash-safe update"
  dirty=0
  git diff --quiet || dirty=1
  git diff --cached --quiet || dirty=1
  stashed=0
  if [[ $dirty -eq 1 ]]; then
    echo "  • Local changes detected → stashing"
    git stash push -u -m "update-kiosk autostash"
    stashed=1
  fi
  # Rebase on upstream
  if git rev-parse --abbrev-ref "@{upstream}" >/dev/null 2>&1; then
    git pull --rebase
  else
    echo "  • No upstream set; pulling from origin/${current_branch}"
    git pull --rebase origin "$current_branch" || git pull --rebase origin "$default_branch"
  fi
  if [[ $stashed -eq 1 ]]; then
    echo "  • Re-applying stashed changes (may conflict)"
    git stash pop || true
  fi
fi

echo "▶ Ensure Python venv & deps"
python3 -m venv "$VENV"
# shellcheck disable=SC1090
source "$VENV/bin/activate"
pip install --upgrade pip
pip install -r "$APPDIR/requirements.txt"

echo "▶ Database migrate/init"
python "$APPDIR/init_db.py" || {
  echo "❌ init_db.py failed. Check for duplicate rows or schema conflicts."
  exit 2
}

echo "▶ Restart systemd service: ${SERVICE_NAME}"
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE_NAME"
sleep 1
sudo systemctl status "$SERVICE_NAME" --no-pager || true

echo "▶ Last 60 log lines"
sudo journalctl -u "$SERVICE_NAME" -n 60 --no-pager || true

echo "✅ Update complete"
