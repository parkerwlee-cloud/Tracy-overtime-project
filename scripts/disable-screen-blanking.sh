#!/usr/bin/env bash
# Disable screen blanking & DPMS for LightDM and LXDE session
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Run with sudo: sudo $0"; exit 1; fi

LIGHTDM_DIR="/etc/lightdm/lightdm.conf.d"
mkdir -p "$LIGHTDM_DIR"
cat > "${LIGHTDM_DIR}/99-noblank.conf" <<'EOF'
[Seat:*]
xserver-command=X -s 0 -dpms
EOF
echo "✓ LightDM no-blank configured"

USER_HOME="$(eval echo ~${SUDO_USER:-$USER})"
LXDE_AUTOSTART="${USER_HOME}/.config/lxsession/LXDE-pi/autostart"
mkdir -p "$(dirname "$LXDE_AUTOSTART")"
touch "$LXDE_AUTOSTART"
grep -q "^@xset s off$"      "$LXDE_AUTOSTART" || sed -i '1i @xset s off' "$LXDE_AUTOSTART"
grep -q "^@xset -dpms$"     "$LXDE_AUTOSTART" || sed -i '1i @xset -dpms' "$LXDE_AUTOSTART"
grep -q "^@xset s noblank$" "$LXDE_AUTOSTART" || sed -i '1i @xset s noblank' "$LXDE_AUTOSTART"
echo "✓ LXDE autostart xset lines ensured"
