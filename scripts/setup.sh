#!/usr/bin/env bash
# One-step Raspberry Pi setup for the Tracy overtime kiosk.
# - Installs apt packages
# - Creates/updates Python venv + installs requirements
# - Ensures scripts executable
# - Installs touchscreen map-by-name + autostart
# - Installs/enables systemd service
# - Initializes DB (idempotent)
# - Starts/restarts the service
# - Runs touchscreen mapping immediately
set -euo pipefail

log() { printf "\n\033[1;36m%s\033[0m\n" "$*"; }
ensure_dir() { mkdir -p "$1"; }
append_once() { local line="$1" file="$2"; touch "$file"; grep -Fqx "$line" "$file" || echo "$line" >> "$file"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# --- Constants for this deployment ---
KIOSK_USER="tracymaint"
KIOSK_GROUP="tracymaint"
REPO_PATH="/home/${KIOSK_USER}/overtime_pi_kiosk_full"
SERVICE_NAME="overtime-kiosk.service"
SERVICE_FILE_LOCAL="systemd/${SERVICE_NAME}"
SERVICE_FILE_SYS="/etc/systemd/system/${SERVICE_NAME}"
VENV_DIR="${REPO_ROOT}/.venv"
PYTHON="${VENV_DIR}/bin/python"

log "==> Overtime Kiosk — One-step setup starting"

# --- APT packages ----------------------------------------------------------
log "Updating apt & installing packages..."
sudo apt update
sudo apt install -y \
  python3 python3-venv python3-pip \
  git curl \
  x11-xserver-utils xinput xinput-calibrator \
  unclutter

# --- Python venv -----------------------------------------------------------
log "Ensuring Python venv & requirements..."
if [ ! -d "${VENV_DIR}" ]; then
  python3 -m venv "${VENV_DIR}"
fi
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
pip install --upgrade pip
if [ -f "requirements.txt" ]; then
  pip install -r requirements.txt
else
  log "No requirements.txt found — skipping pip installs."
fi
deactivate

# --- Make repo scripts executable -----------------------------------------
log "Ensuring repo scripts are executable..."
if [ -d "scripts" ]; then
  chmod +x scripts/* 2>/dev/null || true
fi

# --- Touchscreen mapping script -------------------------------------------
log "Installing touchscreen mapping script..."
ensure_dir "scripts"
if [ ! -f "scripts/map-touch-by-name.sh" ]; then
  cat > scripts/map-touch-by-name.sh <<'EOS'
#!/bin/bash
# Map the touchscreen input to the correct HDMI display on Raspberry Pi (X11)
set -euo pipefail
TOUCH_NAME="Yldzkj USB2IIC_CTP_CONTROL"
# Allow X to enumerate devices on login
sleep 2
# Resolve device ID by exact name (fallback to partial)
TOUCH_ID="$(xinput list --id-only "$TOUCH_NAME" 2>/dev/null || true)"
if [ -z "${TOUCH_ID:-}" ]; then
  TOUCH_ID="$(xinput list | awk -F'id=' '/USB2IIC|CTP|Touch/ && /pointer/ {sub(/].*/,"",$2); print $2; exit}')"
fi
# Prefer the output that exposes 1024x600 (the Roadom panel)
OUTPUT="$(xrandr
