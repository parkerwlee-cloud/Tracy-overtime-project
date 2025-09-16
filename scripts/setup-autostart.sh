#!/usr/bin/env bash
# scripts/setup-autostart.sh — dual/single screen Chromium autostart
set -euo pipefail
MODE="${1:-dual}"

URL_DISPLAY="http://localhost:5000/wallboard"
URL_KIOSK="http://localhost:5000/"

if command -v chromium-browser >/dev/null 2>&1; then
  CMD="chromium-browser"
elif command -v chromium >/dev/null 2>&1; then
  CMD="chromium"
else
  echo "ERROR: Chromium not installed (sudo apt install -y chromium)"; exit 1
fi

FLAGS="--kiosk --incognito --new-window --noerrdialogs --disable-translate --disable-session-crashed-bubble --no-first-run --overscroll-history-navigation=0"
PROFILE_A="${HOME}/.kiosk/profile-a"
PROFILE_B="${HOME}/.kiosk/profile-b"
mkdir -p "$PROFILE_A" "$PROFILE_B"

HDMI1_GEOM=$(xrandr | awk '/^HDMI-1 connected/{print $3}')
HDMI2_GEOM=$(xrandr | awk '/^HDMI-2 connected/{print $3}')
LEFT_POS="0,0"; RIGHT_POS="1920,0"
[[ -n "$HDMI1_GEOM" ]] && LEFT_POS=$(echo "$HDMI1_GEOM" | cut -d'+' -f2,3 --output-delimiter=,)
[[ -n "$HDMI2_GEOM" ]] && RIGHT_POS=$(echo "$HDMI2_GEOM" | cut -d'+' -f2,3 --output-delimiter=,)

mkdir -p "${HOME}/.config/lxsession/LXDE-pi" "${HOME}/.config/autostart"

case "$MODE" in
  display)
    cat > "${HOME}/.config/lxsession/LXDE-pi/autostart" <<EOF
@${CMD} ${FLAGS} --user-data-dir=${PROFILE_A} ${URL_DISPLAY}
EOF
    ;;
  kiosk)
    cat > "${HOME}/.config/lxsession/LXDE-pi/autostart" <<EOF
@${CMD} ${FLAGS} --user-data-dir=${PROFILE_A} ${URL_KIOSK}
EOF
    ;;
  dual)
    cat > "${HOME}/.config/lxsession/LXDE-pi/autostart" <<EOF
@${CMD} ${FLAGS} --window-position=${LEFT_POS} --user-data-dir=${PROFILE_A} ${URL_DISPLAY}
@sh -c 'sleep 2; exec ${CMD} ${FLAGS} --window-position=${RIGHT_POS} --user-data-dir=${PROFILE_B} ${URL_KIOSK}'
EOF
    ;;
  *)
    echo "Unknown mode: $MODE (use: display|kiosk|dual)"; exit 2;;
esac

echo "✅ Autostart (${MODE}) configured"
echo "   HDMI-1 → ${LEFT_POS}  |  HDMI-2 → ${RIGHT_POS}"
