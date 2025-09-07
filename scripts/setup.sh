#!/usr/bin/env bash
set -euo pipefail

echo "==> Overtime Kiosk Setup (Pi) — starting..."

# --- Helpers ---------------------------------------------------------------
log() { printf "\n\033[1;36m%s\033[0m\n" "$*"; }
ensure_dir() { mkdir -p "$1"; }
append_once() {
  local line="$1" file="$2"
  touch "$file"
  grep -Fqx "$line" "$file" || echo "$line" >> "$file"
}

# --- System packages -------------------------------------------------------
log "Updating apt and installing dependencies..."
sudo apt update
sudo apt install -y \
  python3 python3-venv python3-pip \
  git curl \
  x11-xserver-utils xinput xinput-calibrator \
  unclutter

# --- Python venv (if your app uses it) ------------------------------------
if [ -f "requirements.txt" ]; then
  log "Creating Python venv and installing requirements..."
  python3 -m venv .venv
  # shellcheck disable=SC1091
  source .venv/bin/activate
  pip install --upgrade pip
  pip install -r requirements.txt
  deactivate
else
  log "No requirements.txt found — skipping venv step."
fi

# --- Make repo scripts executable -----------------------------------------
log "Making repo scripts executable (if present)..."
if [ -d "scripts" ]; then
  chmod +x scripts/* 2>/dev/null || true
fi

# --- Install systemd service (if present) ---------------------------------
if [ -f "systemd/overtime-kiosk.service" ]; then
  log "Installing systemd service..."
  sudo cp systemd/overtime-kiosk.service /etc/systemd/system/overtime-kiosk.service
  sudo systemctl daemon-reload
  sudo systemctl enable overtime-kiosk.service || true
else
  log "systemd/overtime-kiosk.service not found — skipping service install."
fi

# --- Touchscreen mapping script -------------------------------------------
log "Installing touchscreen mapping script..."
ensure_dir "scripts"

# Write the script from repo to /usr/local/bin (if it exists in repo)
if [ -f "scripts/map-touch-by-name.sh" ]; then
  sudo cp scripts/map-touch-by-name.sh /usr/local/bin/map-touch-by-name.sh
else
  # If someone forgot to commit it, write a fresh copy so setup is idempotent.
  sudo tee /usr/local/bin/map-touch-by-name.sh >/dev/null <<'EOF'
#!/bin/bash
# Map the touchscreen input to the correct HDMI display on Raspberry Pi (X11)

set -euo pipefail

TOUCH_NAME="Yldzkj USB2IIC_CTP_CONTROL"

# Give X time to enumerate devices after login
sleep 2

# Resolve device ID by exact name (fallback to partial match)
TOUCH_ID="$(xinput list --id-only "$TOUCH_NAME" 2>/dev/null || true)"
if [ -z "${TOUCH_ID:-}" ]; then
  TOUCH_ID="$(xinput list | awk -F'id=' '/USB2IIC|CTP|Touch/ && /pointer/ {sub(/].*/,"",$2); print $2; exit}')"
fi

# Pick the connected output that offers 1024x600 (typical for this panel)
OUTPUT="$(xrandr | awk '
  / connected/ {out=$1}
  /1024x600/  {print out; exit}
')"

# Fallbacks if mode probing failed
[ -z "${OUTPUT:-}" ] && OUTPUT="HDMI-2"
[ -z "${OUTPUT:-}" ] && OUTPUT="HDMI-1"

if [ -n "${TOUCH_ID:-}" ]; then
  xinput map-to-output "$TOUCH_ID" "$OUTPUT"
fi
EOF
fi

sudo chmod +x /usr/local/bin/map-touch-by-name.sh

# --- Autostart (LXDE) -----------------------------------------------------
log "Enabling autostart under LXDE..."
ensure_dir "${HOME}/.config/lxsession/LXDE-pi"
append_once "@/usr/local/bin/map-touch-by-name.sh" "${HOME}/.config/lxsession/LXDE-pi/autostart"

# Optional generic desktop autostart as a fallback (helps if session changes)
log "Adding generic desktop autostart entry (fallback)..."
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

# --- Optional kiosk UX niceties -------------------------------------------
log "Hiding mouse cursor after 1s idle (unclutter)..."
append_once "@unclutter -idle 1 -root" "${HOME}/.config/lxsession/LXDE-pi/autostart"

# --- Finish ---------------------------------------------------------------
log "Setup complete."

if systemctl list-unit-files | grep -q "^overtime-kiosk.service"; then
  log "To start the service now:    sudo systemctl start overtime-kiosk.service"
  log "To check status:             systemctl status overtime-kiosk.service"
fi

log "You can test touch mapping immediately by running:"
echo "    /usr/local/bin/map-touch-by-name.sh"
