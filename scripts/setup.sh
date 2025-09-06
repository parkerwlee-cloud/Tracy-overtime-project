#!/usr/bin/env bash
# scripts/setup.sh
# One-stop setup (Pi 5 / Pi 4). Makes scripts executable, installs deps, DB, service, autostart, logs helper.
# Usage:
#   bash scripts/setup.sh           # defaults to dual-screen autostart
#   bash scripts/setup.sh display   # single-screen wallboard
#   bash scripts/setup.sh kiosk     # single-screen sign-up kiosk
#   bash scripts/setup.sh dual      # two screens

set -euo pipefail

MODE="${1:-dual}"   # default autostart mode
APPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
VENV="${APPDIR}/.venv"
SERVICE_NAME="overtime-kiosk"

echo "▶ Make all scripts executable"
find "${APPDIR}/scripts" -type f -name "*.sh" -exec chmod +x {} \; || true

echo "▶ Python venv & dependencies"
python3 -m venv "$VENV"
# shellcheck disable=SC1090
source "$VENV/bin/activate"
pip install --upgrade pip
pip install -r "$APPDIR/requirements.txt"

echo "▶ Initialize / migrate database"
python "$APPDIR/init_db.py"

echo "▶ Install/enable systemd service (auto-detect user)"
# Needs sudo to write to /etc/systemd/system
sudo "${APPDIR}/scripts/install-service.sh"

echo "▶ Configure autostart (mode: $MODE)"
"${APPDIR}/scripts/setup-autostart.sh" "$MODE"

echo "▶ Install logs helper (/usr/local/bin/kiosk-logs)"
sudo bash -c 'cat >/usr/local/bin/kiosk-logs' <<'EOF'
#!/usr/bin/env bash
exec journalctl -u overtime-kiosk -f -n 50 --no-pager
EOF
sudo chmod +x /usr/local/bin/kiosk-logs

echo
echo "✅ Setup complete"
echo "   • Follow logs: kiosk-logs"
echo "   • Service:     sudo systemctl status overtime-kiosk --no-pager"
echo "   • Update:      ./scripts/update-kiosk.sh"
echo "   • Change mode: ./scripts/setup-autostart.sh display|kiosk|dual && logout/reboot"
