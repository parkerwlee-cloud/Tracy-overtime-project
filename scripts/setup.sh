#!/usr/bin/env bash
# scripts/setup.sh
# One-stop setup for the Overtime Kiosk on a Raspberry Pi (or any Debian-ish Linux).
# Ensures all scripts are executable, installs deps, migrates DB, installs service, configures autostart.
# Usage:
#   bash scripts/setup.sh           # defaults to dual-screen autostart
#   bash scripts/setup.sh display   # single-screen wallboard
#   bash scripts/setup.sh kiosk     # single-screen sign-up kiosk
#   bash scripts/setup.sh dual      # two screens: left=/display, right=/

set -euo pipefail

MODE="${1:-dual}"   # default autostart mode

APPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
VENV="${APPDIR}/.venv"
SERVICE_NAME="overtime-kiosk"
SERVICE_FILE_SRC="${APPDIR}/systemd/overtime-kiosk.service"
SERVICE_FILE_DST="/etc/systemd/system/overtime-kiosk.service"

echo "▶ Making all repo scripts executable"
find "${APPDIR}/scripts" -type f -name "*.sh" -exec chmod +x {} \; || true

echo "▶ Python venv & dependencies"
python3 -m venv "$VENV"
# shellcheck disable=SC1090
source "$VENV/bin/activate"
pip install --upgrade pip
pip install -r "$APPDIR/requirements.txt"

echo "▶ Initialize / migrate database"
python "$APPDIR/init_db.py"

echo "▶ Install/enable systemd service"
if [[ ! -f "$SERVICE_FILE_SRC" ]]; then
  echo "ERROR: Missing $SERVICE_FILE_SRC" >&2
  exit 1
fi
sudo cp "$SERVICE_FILE_SRC" "$SERVICE_FILE_DST"
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

echo "▶ Configure autostart (mode: $MODE)"
chmod +x "$APPDIR/scripts/setup-autostart.sh" || true
"$APPDIR/scripts/setup-autostart.sh" "$MODE"

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
echo "   • Update:      ./scripts/update-kiosk.sh   (use --force to discard local edits)"
echo "   • Change mode: ./scripts/setup-autostart.sh display|kiosk|dual && logout/reboot"
