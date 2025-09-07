#!/usr/bin/env bash
# Unifies Pi setup: packages, venv, autostart, touchscreen mapping, service.
set -euo pipefail

log() { printf "\n\033[1;36m%s\033[0m\n" "$*"; }
ensure_dir() { mkdir -p "$1"; }
append_once() { local line="$1" file="$2"; touch "$file"; grep -Fqx "$line" "$file" || echo "$line" >> "$file"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

log "==> Overtime Kiosk Setup — starting"

# --- System packages -------------------------------------------------------
log "Updating apt & installing packages..."
sudo apt update
sudo apt install -y \
  python3 python3-venv python3-pip \
  git curl \
  x11-xserver-utils xinput xinput-calibrator \
  unclutter

# --- Python venv -----------------------------------------------------------
if [ -f "requirements.txt" ]; then
  log "Creating Python venv & installing requirements..."
  python3 -m venv .venv
  # shellcheck disable=SC1091
  source .venv/bin/activate
  pip install --upgrade pip
  pip install -r requirements.txt
  deactivate
else
  log "No requirements.txt found — skipping venv install."
fi

# --- Make repo scripts executable -----------------------------------------
log "Ensuring repo scripts are executable..."
if [ -d "scripts" ]; then
  chmod +x scripts/* 2>/dev/null || true
fi

# --- Touchscreen: install robust map-by-name script -----------------------
log "Installing touchscreen mapping script..."
ensure_dir "scripts"
if [ ! -f "scripts/map-touch-by-name.sh" ]; then
  cat > scripts/map-touch-by-name.sh <<'EOS'
#!/bin/bash
# Map the touchscreen input to the correct HDMI display on Raspberry Pi (X11)
set -euo pipefail
TOUCH_NAME="Yldzkj USB2IIC_CTP_CONTROL"
sleep 2
TOUCH_ID="$(xinput list --id-only "$TOUCH_NAME" 2>/dev/null || true)"
if [ -z "${TOUCH_ID:-}" ]; then
  TOUCH_ID="$(xinput list | awk -F'id=' '/USB2IIC|CTP|Touch/ && /pointer/ {sub(/].*/,"",$2); print $2; exit}')"
fi
OUTPUT="$(xrandr | awk '/ connected/{out=$1} /1024x600/{print out; exit}')"
[ -z "${OUTPUT:-}" ] && OUTPUT="HDMI-2"
[ -z "${OUTPUT:-}" ] && OUTPUT="HDMI-1"
if [ -n "${TOUCH_ID:-}" ]; then
  xinput map-to-output "$TOUCH_ID" "$OUTPUT"
fi
EOS
fi
sudo cp scripts/map-touch-by-name.sh /usr/local/bin/map-touch-by-name.sh
sudo chmod +x /usr/local/bin/map-touch-by-name.sh

# --- Autostart (LXDE) ------------------------------------------------------
log "Adding LXDE autostart entries..."
ensure_dir "${HOME}/.config/lxsession/LXDE-pi"
append_once "@/usr/local/bin/map-touch-by-name.sh" "${HOME}/.config/lxsession/LXDE-pi/autostart"
append_once "@unclutter -idle 1 -root"             "${HOME}/.config/lxsession/LXDE-pi/autostart"

# Fallback .desktop for other sessions
ensure_dir "${HOME}/.config/autostart"
cat > "${HOME}/.config/autostart/map-touchscreen.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Exec=/usr/local/bin/map-touch-by-name.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Map Touchscreen
EOF

# --- Systemd service -------------------------------------------------------
SERVICE_SRC="systemd/overtime-kiosk.service"
if [ -f "$SERVICE_SRC" ]; then
  log "Installing systemd service..."
  sudo cp "$SERVICE_SRC" /etc/systemd/system/overtime-kiosk.service
  sudo systemctl daemon-reload
  sudo systemctl enable overtime-kiosk.service || true
else
  log "systemd/overtime-kiosk.service not found — skipping service install."
fi

# --- Deprecate older overlapping scripts ----------------------------------
log "Marking older overlapping scripts as deprecated (kept for reference)..."
for f in scripts/setup-touchscreen.sh scripts/setup-autostart.sh scripts/install-service.sh; do
  [ -f "$f" ] && sed -i '1s;^;# DEPRECATED: unified into scripts/setup.sh — kept for history\n;' "$f" || true
done

log "==> Setup complete."
echo "Test touch now:  /usr/local/bin/map-touch-by-name.sh"
echo "Start service:   sudo systemctl start overtime-kiosk.service"
echo "Status:          systemctl status overtime-kiosk.service"
