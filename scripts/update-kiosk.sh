#!/usr/bin/env bash
# scripts/update-kiosk.sh
# Robust updater for the Overtime Kiosk repo.
# - Safely updates from git (stash by default; supports --hard to reset)
# - Ensures all scripts are executable
# - Reinstalls deps only if requirements.txt changed
# - Runs DB init/migrations
# - Optional self-test
# - Restarts systemd service

set -euo pipefail

APPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$APPDIR"

SERVICE_NAME="overtime-kiosk"
VENV="${APPDIR}/.venv"
DO_HARD=0
DO_SELFTEST=0

# Parse flags
for arg in "$@"; do
  case "$arg" in
    --hard) DO_HARD=1 ;;
    --self-test|--selftest) DO_SELFTEST=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

say()  { echo -e "\033[1;34m▶\033[0m $*"; }
ok()   { echo -e "\033[1;32m✓\033[0m $*"; }
warn() { echo -e "\033[1;33m⚠\033[0m $*"; }

# 0) Ensure git available
command -v git >/dev/null || { echo "git is required"; exit 1; }

# 1) Determine current branch & upstream (fallback to origin/main)
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)"
if [[ -z "$UPSTREAM" ]]; then
  # Try origin/<branch>, else origin/main
  if git ls-remote --exit-code origin "refs/heads/${CURRENT_BRANCH}" >/dev/null 2>&1; then
    UPSTREAM="origin/${CURRENT_BRANCH}"
  else
    UPSTREAM="origin/main"
  fi
fi
say "Updating from: $UPSTREAM"

# 2) Update repo
if [[ $DO_HARD -eq 1 ]]; then
  warn "Using HARD reset (local changes will be discarded)"
  git fetch --all --prune
  git reset --hard "$UPSTREAM"
else
  # Stash local changes, rebase onto upstream, then try to reapply stash
  git fetch --all --prune
  STASHED=0
  if ! git diff --quiet || ! git diff --cached --quiet; then
    say "Stashing local changes"
    git stash push -u -m "update-kiosk.sh auto-stash $(date -Iseconds)"
    STASHED=1
  fi
  git rebase "$UPSTREAM" || { warn "Rebase failed; attempting a safe reset to $UPSTREAM"; git rebase --abort || true; git reset --hard "$UPSTREAM"; STASHED=0; }
  if [[ $STASHED -eq 1 ]]; then
    say "Reapplying stashed changes"
    git stash pop || warn "Conflicts applying stash; resolve manually if needed"
  fi
fi
ok "Repo updated"

# 3) Make all scripts executable
say "Ensuring all repo scripts are executable"
find "${APPDIR}/scripts" -type f -name "*.sh" -exec chmod +x {} \; || true
ok "Scripts are executable"

# 4) Python venv & deps (only if requirements changed)
say "Preparing Python environment"
python3 -m venv "$VENV"
# shellcheck disable=SC1090
source "$VENV/bin/activate"

REQ_HASH_FILE="${APPDIR}/.requirements.sha"
REQ_HASH_NEW="$(sha256sum "${APPDIR}/requirements.txt" | awk '{print $1}')"
REQ_HASH_OLD="$(cat "${REQ_HASH_FILE}" 2>/dev/null || true)"

if [[ "$REQ_HASH_NEW" != "$REQ_HASH_OLD" ]]; then
  say "requirements.txt changed — installing dependencies"
  pip install --upgrade pip
  pip install -r "${APPDIR}/requirements.txt"
  echo "$REQ_HASH_NEW" > "${REQ_HASH_FILE}"
  ok "Dependencies installed"
else
  ok "requirements.txt unchanged — skipping reinstall"
fi

# 5) Initialize / migrate database
say "Running DB init/migrations"
python "${APPDIR}/init_db.py"
ok "Database ready"

# 6) Optional self-test
if [[ $DO_SELFTEST -eq 1 ]]; then
  if [[ -x "${APPDIR}/scripts/self-test.sh" ]]; then
    say "Running self-test"
    "${APPDIR}/scripts/self-test.sh"
    ok "Self-test passed"
  else
    warn "scripts/self-test.sh not found (skipping)"
  fi
fi

# 7) Restart service
say "Restarting service: ${SERVICE_NAME}"
sudo systemctl daemon-reload
sudo systemctl restart "${SERVICE_NAME}"
sleep 1
sudo systemctl status "${SERVICE_NAME}" --no-pager || true
ok "Update complete"

echo
echo "Tips:"
echo "  • Follow logs: kiosk-logs"
echo "  • Hard reset next time (discard local edits): scripts/update-kiosk.sh --hard"
echo "  • Include self-test: scripts/update-kiosk.sh --self-test"
