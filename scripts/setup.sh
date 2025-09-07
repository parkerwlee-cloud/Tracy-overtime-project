#!/usr/bin/env bash
# One-stop setup (Pi 5 / Pi 4). Makes scripts executable, installs deps, DB, service,
# configures dual-screen autostart, auto-calibrates touchscreen → HDMI-2, installs logs helper.
# Usage:
#   bash scripts/setup.sh            # defaults to dual-screen autostart
#   bash scripts/setup.sh display    # single-screen wallboard
#   bash scripts/setup.sh kiosk      # single-screen sign-up kiosk
#   bash scripts/setup.sh dual       # two screens (HDMI-1 wallboard, HDMI-2 kiosk)

set -euo pipefail

MODE="${1:-dual}"
APPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
VENV="${APPDIR}/.venv"
SERVICE_NAME="overtime-kiosk"

echo "▶ Make all repo scripts executable"
find "${APPDIR}/scripts" -type f -name "*.sh" -exec chmod +x {} \; || true

# Warn if still on Wayland (best results on X11 for window placement)
if [[ "${XDG_SESSION_TYPE:-}" != "x11" ]]; then
  echo "⚠ Detected session type: ${XDG_SESSION_TYPE:-unknown}. Dual-screen placement is most reliable on X11."
  echo "  If windows don't land on the intended monitors, run:  sudo ${APPDIR}/scripts/force-x11.sh"
fi

echo "▶ Python venv & dependencies"
python3 -m venv "$VENV"
# shellcheck disable=SC1090
source "$VENV/bin/activate"
pip install --upgrade pip
pip install -r "$APPDIR/requirements.txt"

echo "▶ Initialize / migrate database"
python "$APPDIR/init_db.py"

echo "▶ Install/enable systemd service (auto-detect user)"
sudo "${APPDIR}/scripts/install-service.sh"

echo "▶ Configure autostart (mode: $MODE)"
"${APPDIR}/scripts/setup-autostart.sh" "$MODE"

# --- Auto-calibrate touchscreen to HDMI-2 when in dual mode ---
if [[ "$MODE" == "dual" ]]; then
  echo "▶ Auto-calibrating touchscreen to HDMI-2 (if present)"
  if command -v xinput >/dev/null 2>&1; then
    if xrandr | grep -q "^HDMI-2 connected"; then
      # Check if any device with 'Touch' in its name exists
      if xinput list | grep -qi "Touch"; then
        "${APPDIR}/scripts/setup-touchscreen.sh" || echo "  (non-fatal) Touchscreen calibration script returned an error."
      else
        echo "  No touchscreen device found via xinput."
      fi
    else
      echo "  HDMI-2 not detected as connected; skipping touchscreen mapping."
    fi
  else
    echo "  xinput not installed; skipping touchscreen mapping. Try: sudo apt install -y xinput"
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
echo "   • Service:     sudo systemctl status overtime-kiosk --no-pager"
echo "   • Update:      ./scripts/update-kiosk.sh"
echo "   • Change mode: ./scripts/setup-autostart.sh display|kiosk|dual && logout/reboot"
