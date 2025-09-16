#!/usr/bin/env bash
# scripts/update-kiosk.sh — safe updater
set -euo pipefail

APPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$APPDIR"

SERVICE_NAME="overtime-kiosk"
VENV="${APPDIR}/.venv"
DO_HARD=0
DO_SELFTEST=0

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

command -v git >/dev/null || { echo "git required"; exit 1; }

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)"
[[ -z "$UPSTREAM" ]] && UPSTREAM="origin/${CURRENT_BRANCH}"

say "Updating from $UPSTREAM"
git fetch --all --prune
if [[ $DO_HARD -eq 1 ]]; then
  warn "HARD reset (discarding local edits)"
  git reset --hard "$UPSTREAM"
else
  STASHED=0
  if ! git diff --quiet || ! git diff --cached --quiet; then
    say "Stashing local changes"
    git stash push -u -m "update-kiosk $(date -Iseconds)"; STASHED=1
  fi
  git rebase "$UPSTREAM" || { warn "Rebase failed, resetting hard"; git rebase --abort || true; git reset --hard "$UPSTREAM"; STASHED=0; }
  if [[ $STASHED -eq 1 ]]; then git stash pop || warn "Conflicts applying stash"; fi
fi
ok "Repo updated"

say "Ensure scripts executable"
find "${APPDIR}/scripts" -type f -name "*.sh" -exec chmod +x {} \; || true
ok "Scripts executable"

say "Python venv & deps (conditionally)"
python3 -m venv "$VENV"
source "$VENV/bin/activate"
REQ_HASH_FILE="${APPDIR}/.requirements.sha"
REQ_HASH_NEW="$(sha256sum "${APPDIR}/requirements.txt" | awk '{print $1}')"
REQ_HASH_OLD="$(cat "${REQ_HASH_FILE}" 2>/dev/null || true)"
if [[ "$REQ_HASH_NEW" != "$REQ_HASH_OLD" ]]; then
  pip install --upgrade pip
  pip install -r "${APPDIR}/requirements.txt"
  echo "$REQ_HASH_NEW" > "${REQ_HASH_FILE}"
  ok "Dependencies installed"
else
  ok "requirements.txt unchanged"
fi

say "DB init/migrations"
python "${APPDIR}/init_db.py"
ok "DB ready"

if [[ $DO_SELFTEST -eq 1 ]]; then
  if [[ -x "${APPDIR}/scripts/self-test.sh" ]]; then
    "${APPDIR}/scripts/self-test.sh"
    ok "Self-test passed"
  else
    warn "self-test not found"
  fi
fi

say "Restart service"
sudo systemctl daemon-reload
sudo systemctl restart "${SERVICE_NAME}"
sleep 1
sudo systemctl status "${SERVICE_NAME}" --no-pager || true
ok "Update complete"
