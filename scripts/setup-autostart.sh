#!/usr/bin/env bash
# scripts/setup-autostart.sh
# Set up kiosk autostart for single-screen (display/kiosk) or dual-screen.
# Usage:
#   ./scripts/setup-autostart.sh display
#   ./scripts/setup-autostart.sh kiosk
#   ./scripts/setup-autostart.sh dual

set -euo pipefail

MODE="${1:-dual}"  # default to dual since you want both screens
URL_DISPLAY="http://localhost:5000/display"
URL_KIOSK="http://localhost:5000/"

# --- detect chromium command ---
CMD=""
if command -v chromium-browser >/dev/null 2>&1; then
  CMD="chromium-browser"
elif command -v chromium >/dev/null 2>&1; then
  CMD="chromium"
else
  echo "ERROR: Chromium is not installed. Try: sudo apt install -y chromium-browser || sudo apt install -y chromium" >&2
  exit 1
fi

EXTRA_FLAGS="--kiosk --incognito --noerrdialogs --disable-translate"

# --- detect screens / geometry for dual ---
LEFT_POS="0,0"
RIGHT_POS="1024,0"  # fallback
if [[ "${MODE}" == "dual" ]]; then
  if command -v xrandr >/dev/null 2>&1; then
    # detect primary origin and second output origin
    XR=$(xrandr --current | awk '/ connected/{print $1, $3}')
    # Example lines:
    # HDMI-1 1920x1080+0+0
    # HDMI-2 1920x1080+1920+0
    PRIM_LINE=$(echo "$XR" | awk '/\+0\+0$/ {print $0; exit}')
    if [[ -n "${PRIM_LINE}" ]]; then
      PRIM_ORIGIN="0,0"
      # get width of the primary line (e.g., 1920x1080+0+0 -> 1920)
      PRIM_W=$(echo "$PRIM_LINE" | awk '{print $2}' | cut -d'x' -f1)
      RIGHT_POS="${PRIM_W},0"
    fi
  fi
fi

mkdir -p ~/.config/lxsession/LXDE-pi
mkdir -p ~/.config/autostart

if [[ "${MODE}" == "display" ]]; then
  # LXDE
  cat > ~/.config/lxsession/LXDE-pi/autostart <<EOF
@${CMD} ${EXTRA_FLAGS} ${URL_DISPLAY}
EOF
  # .desktop
  cat > ~/.config/autostart/kiosk.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Overtime Kiosk (Display)
Exec=${CMD} ${EXTRA_FLAGS} ${URL_DISPLAY}
X-GNOME-Autostart-enabled=true
EOF

elif [[ "${MODE}" == "kiosk" ]]; then
  # LXDE
  cat > ~/.config/lxsession/LXDE-pi/autostart <<EOF
@${CMD} ${EXTRA_FLAGS} ${URL_KIOSK}
EOF
  # .desktop
  cat > ~/.config/autostart/kiosk.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Overtime Kiosk (Signup)
Exec=${CMD} ${EXTRA_FLAGS} ${URL_KIOSK}
X-GNOME-Autostart-enabled=true
EOF

elif [[ "${MODE}" == "dual" ]]; then
  # LXDE (two windows → two screens)
  cat > ~/.config/lxsession/LXDE-pi/autostart <<EOF
@${CMD} ${EXTRA_FLAGS} --window-position=${LEFT_POS} ${URL_DISPLAY}
@${CMD} ${EXTRA_FLAGS} --window-position=${RIGHT_POS} ${URL_KIOSK}
EOF
  # .desktop (launch both in a single Exec)
  cat > ~/.config/autostart/kiosk.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Overtime Kiosk (Dual Screen)
Exec=sh -c '${CMD} ${EXTRA_FLAGS} --window-position=${LEFT_POS} ${URL_DISPLAY} & ${CMD} ${EXTRA_FLAGS} --window-position=${RIGHT_POS} ${URL_KIOSK}'
X-GNOME-Autostart-enabled=true
EOF

else
  echo "Unknown mode: ${MODE} (use: display | kiosk | dual)" >&2
  exit 2
fi

echo "✅ Autostart configured:"
echo "   Mode: ${MODE}"
echo "   Chromium: ${CMD}"
if [[ "${MODE}" == "dual" ]]; then
  echo "   Left window @ ${LEFT_POS} → ${URL_DISPLAY}"
  echo "   Right window @ ${RIGHT_POS} → ${URL_KIOSK}"
else
  echo "   URL: ${URL_DISPLAY} (display) or ${URL_KIOSK} (kiosk) based on your mode"
fi
echo "➡ Reboot or log out/in to apply."
