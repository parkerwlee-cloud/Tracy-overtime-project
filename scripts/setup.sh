#!/usr/bin/env bash
# One-stop setup: scripts executable, deps, DB, service, autostart, touch calibration, logs helper.

set -euo pipefail

MODE="${1:-dual}"
APPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
VENV="${APPDIR}/.venv"

echo "▶ Make all repo scripts executable"
find "${APPDIR}/scripts" -type f -name "*.sh" -exec chmod +x {} \; || true

if [[ "${XDG_SESSION_TYPE:-}" != "x11" ]]; then
  echo "ℹ Session is ${XDG_SESSION_TYPE:-unknown}. Dual-screen placement & CTM work best on X11."
  echo "  If placement is wrong, run: sudo ${APPDIR}/scripts/force-x11.sh"
fi

echo "▶ Python venv & dependencies"
python3 -m venv "$VENV"
# shellcheck disable=SC1090
source "$VENV/bin/activate"
pip install --upgrade pip
pip install -r "$APPDIR/requirements.txt"

echo "▶ Initialize / migrate database"
python "$APPDIR/init_db.py"

echo "▶ Install/enable service (auto-detect user)"
sudo "${APPDIR}/scripts/install-service.sh"

echo "▶ Configure autostart (mode: $MODE)"
"${APPDIR}/scripts/setup-autostart.sh" "$MODE"

# Auto-calibrate touch when dual and HDMI-2 connected
if [[ "$MODE" == "dual" ]] && xrandr | grep -q "^HDMI-2 connected"; then
  if command -v xinput >/dev/null 2>&1; then
    echo "▶ Calibrating touchscreen to HDMI-2 (CTM)"
    "${APPDIR}/scripts/setup-touchscreen.sh" || echo "  (non-fatal) touchscreen calibration script reported an error."
  else
    echo "ℹ xinput not installed; skipping touch calibration. Try: sudo apt install -y xinput"
  fi
fi

echo "▶ Install logs helper (/usr/local/bin/kiosk-logs)"
sudo bash -c 'cat >/usr/local/bin/kiosk-logs' <<'EOF'
#!/usr/bin/env bash
exec sudo journalctl -u overtime-kiosk -f -n 80 --no-pager
EOF
sudo chmod +x /usr/local/bin/kiosk-logs

echo
echo "✅ Setup complete"
echo "   • Follow logs: kiosk-logs"
echo "   • Update:      ./scripts/update-kiosk.sh"
echo "   • Change mode: ./scripts/setup-autostart.sh display|kiosk|dual && logout/reboot"
