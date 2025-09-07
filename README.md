# Tracy Overtime Kiosk

Multi-screen Raspberry Pi kiosk for OT signup + wallboard.

## TL;DR install (Raspberry Pi)

```bash
# One-time: clone to target path used by service file
sudo apt update && sudo apt install -y git
mkdir -p /home/tracymaint && cd /home/tracymaint
git clone <YOUR_REPO_URL> overtime_pi_kiosk_full
cd overtime_pi_kiosk_full

# Setup
chmod +x scripts/setup.sh
scripts/setup.sh

# Initialize DB (idempotent)
python3 init_db.py   # or: .venv/bin/python init_db.py

# Start service
sudo systemctl start overtime-kiosk.service
systemctl status overtime-kiosk.service
