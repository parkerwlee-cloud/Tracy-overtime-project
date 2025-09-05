#!/usr/bin/env bash
set -euo pipefail

APPDIR="$HOME/overtime_pi_kiosk_full"

if [ ! -d "$APPDIR" ]; then
  echo "❌ Project folder not found at $APPDIR"
  echo "👉 Clone it with:"
  echo "   git clone https://github.com/parkerwlee-cloud/Tracy-overtime-project.git overtime_pi_kiosk_full"
  exit 1
fi

cd "$APPDIR"

echo "🔄 Pulling latest code..."
git pull --ff-only || true

echo "🐍 Updating Python environment..."
if [ ! -d ".venv" ]; then python3 -m venv .venv; fi
source .venv/bin/activate
pip install --upgrade pip >/dev/null
pip install -r requirements.txt

echo "🗃 Initializing database (idempotent)..."
python init_db.py

SERVICE="overtime-kiosk.service"
if systemctl list-unit-files | grep -q "$SERVICE"; then
  echo "🧩 Restarting systemd service..."
  sudo systemctl restart $SERVICE
  sudo systemctl status $SERVICE --no-pager -l | sed -n '1,12p'
  echo "✅ Done. Service restarted."
else
  echo "ℹ️ Service not installed."
  echo "Run dev server with:"
  echo "  source .venv/bin/activate && python app.py"
  echo "Or install the service (once):"
  echo "  sudo cp systemd/overtime-kiosk.service /etc/systemd/system/"
  echo "  sudo systemctl daemon-reload"
  echo "  sudo systemctl enable overtime-kiosk.service"
  echo "  sudo systemctl start overtime-kiosk.service"
fi
