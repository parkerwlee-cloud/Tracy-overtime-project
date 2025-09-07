# Overtime Kiosk

A Raspberry Pi–based dual-screen kiosk system for employee overtime sign-ups and wallboard display.  
Runs as a Flask + Socket.IO web app with a systemd service, auto-starting Chromium kiosks on boot.

---

## Features

- **Two screens, one Pi**
  - **HDMI-1 (main monitor):** Wallboard (read-only view of overtime slots)  
  - **HDMI-2 (touchscreen):** Kiosk (interactive sign-up form)

- **Automatic setup**
  - Installs Python dependencies in a virtual environment  
  - Initializes the SQLite database  
  - Installs and enables the `overtime-kiosk` systemd service  
  - Configures autostart for one or two screens  
  - Detects touchscreen and applies calibration (fixes cursor offset)

- **Admin panel**
  - Edit capacities, assign categories, manage employees  

- **Live updates**
  - All screens auto-refresh when signups or capacities change  

---

## Initial Startup (New Pi)

1. Install Raspberry Pi OS (Bookworm **with Desktop**).  
   Dual-screen placement and touchscreen calibration work best on **X11** (not Wayland).  
   Check your session type:
   ```bash
   echo $XDG_SESSION_TYPE

   If it prints wayland, switch to X11 with:

cd ~/overtime_pi_kiosk_full
sudo ./scripts/force-x11.sh


Install git + Python tools:

sudo apt update
sudo apt install -y git python3-venv xinput


Clone this repo:

git clone https://github.com/<your-username>/tracy-overtime-project.git overtime_pi_kiosk_full
cd overtime_pi_kiosk_full


Run the setup (defaults to dual-screen mode):

bash scripts/setup.sh dual


This will:

Make all scripts executable

Create a Python virtual environment & install dependencies

Initialize the database (overtime.db)

Install and enable the systemd service

Configure dual-screen autostart (HDMI-1 wallboard, HDMI-2 kiosk)

Calibrate the touchscreen → HDMI-2

Install kiosk-logs helper

Reboot:

sudo reboot

Usage

Kiosk (touchscreen, HDMI-2): interactive sign-up form

Wallboard (HDMI-1): read-only slot overview

Admin panel: http://localhost:5000/admin

Common Commands

Follow logs live:

kiosk-logs


Update from GitHub + restart service:

cd ~/overtime_pi_kiosk_full
./scripts/update-kiosk.sh


Switch mode (display | kiosk | dual):

./scripts/setup-autostart.sh dual
sudo reboot


Re-calibrate touchscreen manually:

./scripts/setup-touchscreen.sh

Troubleshooting

Internal Server Error (500):
Run kiosk-logs and check traceback.

Black second screen:
Make sure you’re on X11, then re-run:

./scripts/setup-autostart.sh dual
sudo reboot


Touch offset grows across screen:
Run:

./scripts/setup-touchscreen.sh


Service not running:

sudo systemctl status overtime-kiosk --no-pager

Development Notes

App code: app.py

Templates: templates/

Database: overtime.db (SQLite)

Systemd unit: systemd/overtime-kiosk.service

Scripts: scripts/

✅ A brand-new Pi goes from blank to fully working dual-screen kiosk in one command:

bash scripts/setup.sh dual
