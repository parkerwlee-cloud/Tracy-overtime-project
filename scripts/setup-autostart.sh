#!/usr/bin/env bash
# scripts/setup-autostart.sh
# Dual-screen autostart with proper geometry for HDMI-1 (wallboard) and HDMI-2 (touchscreen).

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

EXTRA_FLAGS="--kiosk --incognito --new-window --noerrdialogs --disable-translate --disable-session-crashed-bubble --no-first-run --overscroll-history-navigation=0"

PROFILE_DIR_A="${HOME}/.kiosk/profile-a"
PROFILE_DIR_B="${HOME}/.kiosk/profile-b"
mkdir -p "$PROFILE_DIR_A" "$PROFILE_DIR_B"

# Detect screen geometry with xrandr
HDMI1_GEOM=$(xrandr | awk '/HDMI-1 connected/{print $3}')
HDMI2_GEOM=$(xrandr | awk '/HDMI-2 connected/{print $3}')

LEFT_POS="0,0"
RIGHT_POS="1920,0"

if [[ -n "$HDMI1_GEOM" && -n "$HDMI2_GEOM" ]]; then
  LEFT_POS=$(echo "$HDMI1_GEOM" | cut -d'+' -f2,3 --output-delimiter=,)
  RIGHT_POS=$(echo "$HDMI2_GEOM" | cut -d'+' -f2,3 --output-delimiter=,)
fi

mkdir -p "${HOME}/.config/lxsession/LXDE-pi" "${HOME}/.config/autostart"

if [[ "$MODE" == "dual" ]]; then
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
else
  echo "Only dual mode updated in this version."
fi

echo "✅ Autostart configured (dual)"
echo "  HDMI-1 → Wallboard at ${LEFT_POS}"
echo "  HDMI-2 → Kiosk at ${RIGHT_POS}"
