#!/usr/bin/env bash
# scripts/setup-autostart.sh
# Configure LXDE autostart for two Chromium *instances* (separate profiles) in kiosk mode.
# Usage:
#   ./scripts/setup-autostart.sh display   # one screen: /display
#   ./scripts/setup-autostart.sh kiosk     # one screen: /
#   ./scripts/setup-autostart.sh dual      # two screens (default)

set -euo pipefail

MODE="${1:-dual}"

URL_DISPLAY="http://localhost:5000/display"
URL_KIOSK="http://localhost:5000/"

# Detect Chromium binary
if command -v chromium-browser >/dev/null 2>&1; then
  CMD="chromium-browser"
elif command -v chromium >/dev/null 2>&1; then
  CMD="chromium"
else
  echo "ERROR: Chromium is not installed. Try: sudo apt install -y chromium"
  exit 1
fi

# Extra flags: force isolated instances and “clean” kiosk behavior
EXTRA_FLAGS="--kiosk --incognito --new-window --noerrdialogs --disable-translate --disable-session-crashed-bubble --no-first-run --overscroll-history-navigation=0"

# Two separate profiles so the second launch doesn't merge into the first process
PROFILE_DIR_A="${HOME}/.kiosk/profile-a"
PROFILE_DIR_B="${HOME}/.kiosk/profile-b"
mkdir -p "$PROFILE_DIR_A" "$PROFILE_DIR_B"

# Compute right-screen offset for dual-screen
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

mkdir -p "${HOME}/.config/lxsession/LXDE-pi" "${HOME}/.config/autostart"

case "$MODE" in
  display)
    cat > "${HOME}/.config/lxsession/LXDE-pi/autostart" <<EOF
@${CMD} ${EXTRA_FLAGS} --user-data-dir=${PROFILE_DIR_A} ${URL_DISPLAY}
EOF
    cat > "${HOME}/.config/autostart/kiosk.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Overtime Kiosk (Display)
Exec=${CMD} ${EXTRA_FLAGS} --user-data-dir=${PROFILE_DIR_A} ${URL_DISPLAY}
X-GNOME-Autostart-enabled=true
EOF
    ;;
  kiosk)
    cat > "${HOME}/.config/lxsession/LXDE-pi/autostart" <<EOF
@${CMD} ${EXTRA_FLAGS} --user-data-dir=${PROFILE_DIR_A} ${URL_KIOSK}
EOF
    cat > "${HOME}/.config/autostart/kiosk.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Overtime Kiosk (Signup)
Exec=${CMD} ${EXTRA_FLAGS} --user-data-dir=${PROFILE_DIR_A} ${URL_KIOSK}
X-GNOME-Autostart-enabled=true
EOF
    ;;
  dual)
    # Launch two *separate* Chromium instances with different profiles and positions.
    # Small delay ensures the first window is fully up before starting the second.
    cat > "${HOME}/.config/lxsession/LXDE-pi/autostart" <<EOF
@${CMD} ${EXTRA_FLAGS} --window-position=${LEFT_POS} --user-data-dir=${PROFILE_DIR_A} ${URL_DISPLAY}
@sh -c 'sleep 2; exec ${CMD} ${EXTRA_FLAGS} --window-position=${RIGHT_POS} --user-data-dir=${PROFILE_DIR_B} ${URL_KIOSK}'
EOF

    cat > "${HOME}/.config/autostart/kiosk.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Overtime Kiosk (Dual Screen)
Exec=sh -c '${CMD} ${EXTRA_FLAGS} --window-position=${LEFT_POS} --user-data-dir=${PROFILE_DIR_A} ${URL_DISPLAY} & sleep 2; ${CMD} ${EXTRA_FLAGS} --window-position=${RIGHT_POS} --user-data-dir=${PROFILE_DIR_B} ${URL_KIOSK}'
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
echo "   Profiles: ${PROFILE_DIR_A}, ${PROFILE_DIR_B}"
echo "➡ Log out/in or reboot to apply."
