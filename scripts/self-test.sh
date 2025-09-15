#!/usr/bin/env bash
set -euo pipefail
echo "Initializing database (idempotent)..."
python scripts/migrate.py
DB="overtime.db"
if [ -f "$DB" ]; then
  echo "✅ DB ready at $(pwd)/$DB"
else
  echo "❌ DB missing"; exit 1; fi
echo "Importing Flask app..."
python - <<'PY'
from app import create_app
app = create_app()
print("✅ Flask app loaded, version", app.config["APP_VERSION"])
PY
echo "ℹ️ Service not installed."
echo "Run dev server with:"
echo "  source .venv/bin/activate && python run.py"
echo "Or install the service (once):"
echo "  sudo cp systemd/overtime-kiosk.service /etc/systemd/system/"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl enable overtime-kiosk.service"
echo "  sudo systemctl start overtime-kiosk.service"
