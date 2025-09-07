#!/usr/bin/env bash
# Regenerate the systemd unit using *this repo's* path and venv.
# Usage: sudo ./scripts/fix-service.sh

set -euo pipefail

APPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
SERVICE="/etc/systemd/system/overtime-kiosk.service"

# Ensure venv exists (so ExecStart path is valid)
if [[ ! -x "$APPDIR/.venv/bin/python" ]]; then
  echo "Creating venv…"
  python3 -m venv "$APPDIR/.venv"
  "$APPDIR/.venv/bin/pip" install --upgrade pip
  "$APPDIR/.venv/bin/pip" install -r "$APPDIR/requirements.txt"
fi

echo "Writing $SERVICE with WorkingDirectory=$APPDIR"
cat >"$SERVICE" <<EOF
[Unit]
Description=Overtime Kiosk (Flask / Socket.IO)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SUDO_USER:-$USER}
WorkingDirectory=$APPDIR
Environment=FLASK_ENV=production
Environment=PORT=5000
Environment=PYTHONUNBUFFERED=1
ExecStart=$APPDIR/.venv/bin/python app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable overtime-kiosk
systemctl restart overtime-kiosk
systemctl status overtime-kiosk --no-pager
