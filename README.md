# Overtime Kiosk

Dual-screen Raspberry Pi kiosk for employee overtime sign-ups (touchscreen) and a wallboard (monitor).  
Flask + SQLAlchemy with a systemd service and Chromium autostart. Touchscreen calibrated automatically.

## Features
- **Two screens, one Pi**: HDMI-1 = Wallboard, HDMI-2 = Touchscreen Kiosk
- **Admin**: login, employee CRUD, slot capacity & categories
- **Weekend freeze**: Sat/Sun lock after Friday 15:30 (configurable TZ)
- **Always-on**: screen blanking/DPMS disabled
- **One-command setup** for fresh Pis

## First-time Setup (Pi)
```bash
sudo apt update
sudo apt install -y git python3-venv xinput chromium
git clone https://github.com/<you>/tracy-overtime-project.git overtime_pi_kiosk_full
cd overtime_pi_kiosk_full
cp .env.example .env
nano .env   # set ADMIN_USERNAME, ADMIN_PASSWORD, SECRET_KEY, etc.
bash scripts/setup.sh dual
sudo reboot
