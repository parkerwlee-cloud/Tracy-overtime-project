#!/usr/bin/env bash
# scripts/setup-autostart.sh
# Configure LXDE and .desktop autostart for Chromium in kiosk mode.
# Usage:
#   ./scripts/setup-autostart.sh display   # one screen: /display
#   ./scripts/setup-autostart.sh kiosk     # one screen: /
#   ./scripts/setup-autostart.sh dual      # two screens (default)

set -euo pipefail

MODE="${1:-dual}"  # default: dual
URL_DISPLAY="http://localhost:5000/display"
URL_KIOSK="http://localhost:5000/"

# --- Detect Chromium binary ---
CMD=""
if command -v chromium-browser >/dev/null 2>&1; then
  CMD="chromium-browser"
elif command -v chromium >/dev/null 2>&1; then
  CMD="chromium"
else
  echo "ERROR: Chromium is not installed."
  echo "Try: sudo apt install -y chromium-browser || sudo apt install -y chromium"
  exit 1
fi

EXTRA_FLAGS="--kiosk --incognito --noerrdialogs --disable-translate"

# --- Compute window positions for dual-screen (fallback to 1920 offset) ---
LEFT_POS="0,0"
RIGHT_POS="1920,0"
if [[ "${MODE}" == "dual" ]] && command -v xrandr >/dev/null 2>&1; then
  XR=$(xrandr --current | awk '/ connected/{print $1, $3}')
  PRIM_LINE=$(echo "$XR" | awk '/\+0\+0$/ {print $0; exit}')
  if [[ -n "${PRIM_LINE}" ]]; then
    PRIM_W=$(echo "$PRIM_LINE" | awk '{print $2}' | cut -d'x' -f1)
    [[ "$PRIM_W" =~ ^[0-9]+$ ]] && RIGHT_POS="${PRIM_W},0"
  fi
fi

# --- Ensure autostart directories ---
mkdir -p "${HOME}/.config/lxsession/LXDE-pi"
mkdir -p "${HOME}/.config/autostart"

# --- Write LXDE autostart and .desktop based on mode ---
case "$MODE" in
  display)
    cat > "${HOME}/.config/lxsession/LXDE-pi/autostart" <<EOF
@${CMD} ${EXTRA_FLAGS} ${URL_DISPLAY}
EOF
    cat > "${HOME}/.config/autostart/kiosk.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Overtime Kiosk (Display)
Exec=${CMD} ${EXTRA_FLAGS} ${URL_DISPLAY}
X-GNOME-Autostart-enabled=true
EOF
    ;;
  kiosk)
    cat > "${HOME}/.config/lxsession/LXDE-pi/autostart" <<EOF
@${CMD} ${EXTRA_FLAGS} ${URL_KIOSK}
EOF
    cat > "${HOME}/.config/autostart/kiosk.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Overtime Kiosk (Signup)
Exec=${CMD} ${EXTRA_FLAGS} ${URL_KIOSK}
X-GNOME-Autostart-enabled=true
EOF
    ;;
  dual)
    cat > "${HOME}/.config/lxsession/LXDE-pi/autostart" <<EOF
@${CMD} ${EXTRA_FLAGS} --window-position=${LEFT_POS} ${URL_DISPLAY}
@${CMD} ${EXTRA_FLAGS} --window-position=${RIGHT_POS} ${URL_KIOSK}
EOF
    cat > "${HOME}/.config/autostart/kiosk.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Overtime Kiosk (Dual Screen)
Exec=sh -c '${CMD} ${EXTRA_FLAGS} --window-position=${LEFT_POS} ${URL_DISPLAY} & ${CMD} ${EXTRA_FLAGS} --window-position=${RIGHT_POS} ${URL_KIOSK}'
X-GNOME-Autostart-enabled=true
EOF
    ;;
  *)
    echo "Unknown mode: ${MODE} (use: display | kiosk | dual)" >&2
    exit 2
    ;;
esac

echo "✅ Autostart configured (${MODE})"
echo "   LXDE:    ${HOME}/.config/lxsession/LXDE-pi/autostart"
echo "   Desktop: ${HOME}/.config/autostart/kiosk.desktop"
echo "➡ Log out/in or reboot to apply."
