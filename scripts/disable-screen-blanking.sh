#!/usr/bin/env bash
# Disable screen blanking & DPMS at both the display manager (LightDM) and user session (LXDE).
# Safe to run multiple times.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run with sudo:  sudo $0"
  exit 1
fi

LIGHTDM_DIR="/etc/lightdm/lightdm.conf.d"
mkdir -p "$LIGHTDM_DIR"

# Force X to never blank / never use DPMS
NOBLANK_CONF="${LIGHTDM_DIR}/99-noblank.conf"
cat > "$NOBLANK_CONF" <<'EOF'
[Seat:*]
# Don't blank the screen, don't use DPMS power saving
xserver-command=X -s 0 -dpms
EOF
echo "✓ Wrote ${NOBLANK_CONF}"

# Ensure user autostart disables screensaver/DPMS too (LXDE session)
USER_HOME="$(eval echo ~${SUDO_USER:-$USER})"
LXDE_AUTOSTART="${USER_HOME}/.config/lxsession/LXDE-pi/autostart"
mkdir -p "$(dirname "$LXDE_AUTOSTART")"
# Insert if not present (order matters: do these before launching Chromium)
grep -q "^@xset s off$"        "$LXDE_AUTOSTART" 2>/dev/null || sed -i '1i @xset s off' "$LXDE_AUTOSTART" || echo -e "@xset s off\n$(cat "$LXDE_AUTOSTART" 2>/dev/null)" > "$LXDE_AUTOSTART"
grep -q "^@xset -dpms$"       "$LXDE_AUTOSTART" 2>/dev/null || sed -i '1i @xset -dpms' "$LXDE_AUTOSTART"
grep -q "^@xset s noblank$"   "$LXDE_AUTOSTART" 2>/dev/null || sed -i '1i @xset s noblank' "$LXDE_AUTOSTART"

echo "✓ Ensured xset lines in ${LXDE_AUTOSTART}"
echo "ℹ Reboot is recommended for LightDM changes to take effect."
