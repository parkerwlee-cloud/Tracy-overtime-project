#!/usr/bin/env bash
# scripts/setup.sh — one-stop setup for Raspberry Pi (Pi 4/5)
set -euo pipefail

MODE="${1:-dual}"   # display | kiosk | dual
APPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
VENV="${APPDIR}/.venv"
SERVICE_NAME="overtime-kiosk"

say() { echo -e "\033[1;34m▶\033[0m $*"; }
warn() { echo -e "\033[1;33m⚠\033[0m $*"; }
ok() { echo -e "\033[1;32m✓\033[0m $*"; }

say "Repository: $APPDIR"
say "Mode: $MODE"

say "Making all repo scripts executable"
find "${APPDIR}/scripts" -type f -name "*.sh" -exec chmod +x {} \; || true
ok "Scripts are executable"

if [[ "${XDG_SESSION_TYPE:-}" != "x11" ]]; then
  warn "Session is '${XDG_SESSION_TYPE:-unknown}'. Dual-screen placement & CTM work best on X11."
  warn "If windows land wrong, run:  sudo ${APPDIR}/scripts/force-x11.sh"
fi

say "Python venv & requirements"
python3 -m venv "$VENV"
source "$VENV/bin/activate"
pip install --upgrade pip
pip install -r "$APPDIR/requirements.txt"
ok "Dependencies installed"

say "Initialize DB"
python "$APPDIR/init_db.py"
ok "Database ready"

say "Install systemd service"
sudo "${APPDIR}/scripts/install-service.sh"
ok "Service installed"

say "Configure autostart (${MODE})"
"${APPDIR}/scripts/setup-autostart.sh" "$MODE"
ok "Autostart configured"

say "Disable screen blanking & DPMS"
if [[ -x "${APPDIR}/scripts/disable-screen-blanking.sh" ]]; then
  sudo "${APPDIR}/scripts/disable-screen-blanking.sh" || warn "noblank script reported a non-fatal issue"
else
  warn "scripts/disable-screen-blanking.sh not found (skipping)"
fi

if [[ "$MODE" == "dual" ]] && xrandr 2>/dev/null | grep -q "^HDMI-2 connected"; then
  if command -v xinput >/dev/null 2>&1; then
    say "Calibrating touchscreen to HDMI-2 (CTM)"
    if [[ -x "${APPDIR}/scripts/setup-touchscreen.sh" ]]; then
      "${APPDIR}/scripts/setup-touchscreen.sh" || warn "touch calibration non-fatal issue"
      ok "Touchscreen calibrated"
    else
      warn "scripts/setup-touchscreen.sh missing"
    fi
  else
    warn "xinput not installed; try: sudo apt install -y xinput"
  fi
else
  warn "Touch calibration skipped (not dual or HDMI-2 not detected)"
fi

say "Install logs helper"
sudo bash -c 'cat >/usr/local/bin/kiosk-logs' <<'EOF'
#!/usr/bin/env bash
exec sudo journalctl -u overtime-kiosk -f -n 80 --no-pager
EOF
sudo chmod +x /usr/local/bin/kiosk-logs

say "Restart service"
sudo systemctl daemon-reload
sudo systemctl restart "${SERVICE_NAME}"
sleep 1
sudo systemctl status "${SERVICE_NAME}" --no-pager || true

echo
ok "Setup complete"
echo "   • Logs: kiosk-logs"
echo "   • Update: ./scripts/update-kiosk.sh"
echo "   • Change mode: ./scripts/setup-autostart.sh display|kiosk|dual && reboot"
