#!/usr/bin/env bash
# scripts/install-service.sh
# Render & install a systemd unit that runs as the repo owner (not hardcoded "pi").
# Usage: sudo ./scripts/install-service.sh

set -euo pipefail

APPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
SERVICE_NAME="overtime-kiosk"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# Detect the user we should run as:
# 1) who owns the repo directory, else 2) the invoking non-root user, else 3) current user
RUNUSER="$(stat -c '%U' "$APPDIR" || true)"
if [[ -z "${RUNUSER}" || "${RUNUSER}" == "root" ]]; then
  RUNUSER="$(logname 2>/dev/null || id -un)"
fi

# Ensure venv exists so ExecStart points to something valid
if [[ ! -x "${APPDIR}/.venv/bin/python" ]]; then
  echo "Creating venv at ${APPDIR}/.venv..."
  python3 -m venv "${APPDIR}/.venv"
  "${APPDIR}/.venv/bin/pip" install --upgrade pip
  "${APPDIR}/.venv/bin/pip" install -r "${APPDIR}/requirements.txt"
fi

echo "Installing systemd unit to ${SERVICE_PATH}"
cat > "${SERVICE_PATH}" <<EOF
[Unit]
Description=Overtime Kiosk (Flask / Socket.IO)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUNUSER}
WorkingDirectory=${APPDIR}
Environment=FLASK_ENV=production
Environment=PORT=5000
Environment=PYTHONUNBUFFERED=1
ExecStart=${APPDIR}/.venv/bin/python app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

echo "✅ Service installed and started as user: ${RUNUSER}"
systemctl status "${SERVICE_NAME}" --no-pager || true
