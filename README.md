# Overtime Kiosk (Full Build)

## Quick Start (Dev)
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # edit ADMIN_PASSWORD, times
python init_db.py
python app.py
# http://127.0.0.1:5000
