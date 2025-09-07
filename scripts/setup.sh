#!/usr/bin/env bash
# scripts/setup.sh
# One-stop setup for the Overtime Kiosk on Raspberry Pi OS (Pi 4/5).
# - Makes repo scripts executable
# - Creates Python venv and installs requirements
# - Initializes/migrates the SQLite DB
# - Installs/starts the systemd service with the correct user/path
# - Configures autostart (display | kiosk | dual) with two Chromium instances
# - Disables screen blanking / DPMS (always-on)
# - Calibrates touchscreen to HDMI-2 via CTM (X11 recommended)
# - Installs a kiosk-logs helper

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

# 1) Ensure all repo scripts are executable
say "Making all repo scripts executable"
find "${APPDIR}/scripts" -type f -name "*.sh" -exec chmod +x {} \; || true
ok "Scripts are executable"

# 2) Environment note (Wayland vs X11)
if [[ "${XDG_SESSION_TYPE:-}" != "x11" ]]; then
  warn "Session is '${XDG_SESSION_TYPE:-unknown}'. Dual-screen placement & CTM work best on X11."
  warn "If windows land on the wrong screens, run:  sudo ${APPDIR}/scripts/force-x11.sh"
fi

# 3) Python venv & dependencies
say "Creating Python venv and installing requirements"
python3 -m venv "$VENV"
# shellcheck disable=SC1090
source "$VENV/bin/activate"
pip install --upgrade pip
pip install -r "$APPDIR/requirements.txt"
ok "Dependencies installed"

# 4) Initialize / migrate database
say "Initializing/migrating database"
python "$APPDIR/init_db.py"
ok "Database ready"

# 5) Install/enable systemd service (auto-detects user & path)
say "Installing systemd service (${SERVICE_NAME})"
sudo "${APPDIR}/scripts/install-service.sh"
ok "Service installed"

# 6) Configure autostart
say "Configuring autostart (${MODE})"
"${APPDIR}/scripts/setup-autostart.sh" "$MODE"
ok "Autostart configured"

# 7) Disable screen blanking & DPMS (always-on)
say "Disabling screen blanking and DPMS"
if [[ -x "${APPDIR}/scripts/disable-screen-blanking.sh" ]]; then
  sudo "${APPDIR}/scripts/disable-screen-blanking.sh" || warn "disable-screen-blanking script reported a non-fatal issue"
else
  warn "scripts/disable-screen-blanking.sh not found (skipping)."
fi

# 8) Touchscreen calibration to HDMI-2 using CTM (only for dual mode if HDMI-2 connected)
if [[ "$MODE" == "dual" ]] && xrandr 2>/dev/null | grep -q "^HDMI-2 connected"; then
  if command -v xinput >/dev/null 2>&1; then
    say "Calibrating touchscreen to HDMI-2 (CTM)"
    if [[ -x "${APPDIR}/scripts/setup-touchscreen.sh" ]]; then
      "${APPDIR}/scripts/setup-touchscreen.sh" || warn "Touchscreen calibration reported a non-fatal issue"
      ok "Touchscreen calibrated (persisted in ~/.xsessionrc)"
    else
      warn "scripts/setup-touchscreen.sh not found (skipping calibration)."
    fi
  else
    warn "xinput not installed; skipping touchscreen calibration. Try: sudo apt install -y xinput"
  fi
else
  warn "Touch calibration skipped (not dual mode or HDMI-2 not detected)."
fi

# 9) Install logs helper
say "Installing logs helper (/usr/local/bin/kiosk-logs)"
sudo bash -c 'cat >/usr/local/bin/kiosk-logs' <<'EOF'
#!/usr/bin/env bash
exec sudo journalctl -u overtime-kiosk -f -n 80 --no-pager
EOF
sudo chmod +x /usr/local/bin/kiosk-logs
ok "Logs helper installed"

# 10) Start/verify service
say "Restarting service and showing status"
sudo systemctl daemon-reload
sudo systemctl restart "${SERVICE_NAME}"
sleep 1
sudo systemctl status "${SERVICE_NAME}" --no-pager || true

echo
ok "Setup complete"
echo "   • Follow logs: kiosk-logs"
echo "   • Update:      ./scripts/update-kiosk.sh"
echo "   • Change mode: ./scripts/setup-autostart.sh display|kiosk|dual && logout/reboot"
echo "📺 Installing touchscreen mapping script..."

# Copy to /usr/local/bin and make it executable
sudo cp scripts/map-touch-by-name.sh /usr/local/bin/map-touch-by-name.sh
sudo chmod +x /usr/local/bin/map-touch-by-name.sh

# Ensure autostart on Raspberry Pi OS
mkdir -p ~/.config/lxsession/LXDE-pi
grep -q "map-touch-by-name.sh" ~/.config/lxsession/LXDE-pi/autostart 2>/dev/null || \
echo "@/usr/local/bin/map-touch-by-name.sh" >> ~/.config/lxsession/LXDE-pi/autostart
