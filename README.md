Overtime Kiosk

A Raspberry Pi–based dual-screen kiosk system for employee overtime sign-ups and wallboard display.
Runs as a Flask + Socket.IO web app with a systemd service, auto-starting Chromium kiosks on boot.

Features

Two screens, one Pi

HDMI-1 (main monitor): Wallboard (read-only view of overtime slots)

HDMI-2 (touchscreen): Kiosk (interactive sign-up form)

Automatic setup

Installs dependencies, sets up Python virtualenv, initializes database

Configures and enables systemd service

Configures autostart for single or dual screens

Detects touchscreen and applies proper calibration

Admin panel

Capacity editing, slot category assignment, employee management

Live updates

All screens auto-refresh when signups or capacity change

First-Time Setup on a New Pi

Install Raspberry Pi OS (Bookworm, Desktop version recommended).
For dual-screen placement and touchscreen calibration, switch to X11 (not Wayland).

echo $XDG_SESSION_TYPE   # should print: x11


If it prints wayland, run:

cd ~/overtime_pi_kiosk_full
sudo ./scripts/force-x11.sh


Install git and clone the repo:

sudo apt update
sudo apt install -y git python3-venv xinput
git clone https://github.com/<your-username>/tracy-overtime-project.git overtime_pi_kiosk_full
cd overtime_pi_kiosk_full


Run setup (defaults to dual-screen):

bash scripts/setup.sh dual


This will:

Make scripts executable

Create Python virtual environment + install dependencies

Initialize the SQLite database

Install the systemd service (overtime-kiosk)

Configure autostart for two screens

Auto-calibrate touchscreen → HDMI-2

Install kiosk-logs helper for easy log viewing

Reboot:

sudo reboot

Usage

Kiosk (touchscreen, HDMI-2) → interactive sign-up form

Wallboard (HDMI-1) → read-only overview of slots

Admin panel → http://localhost:5000/admin

Common Commands

Check logs (live):

kiosk-logs


Update code + restart service:

cd ~/overtime_pi_kiosk_full
./scripts/update-kiosk.sh


Change screen mode (display | kiosk | dual):

./scripts/setup-autostart.sh dual
sudo reboot


Recalibrate touchscreen manually (if needed):

./scripts/setup-touchscreen.sh

Troubleshooting

Internal Server Error (500):
Check kiosk-logs for the traceback; usually means a template or DB migration needs update.

Black second screen:
Make sure you’re on X11 (echo $XDG_SESSION_TYPE). Run ./scripts/setup-autostart.sh dual again to rewrite autostart with correct geometry.

Touch offset grows across screen:
Run ./scripts/setup-touchscreen.sh — computes the proper transformation matrix based on your xrandr layout.

Service not running:

sudo systemctl status overtime-kiosk --no-pager

Development Notes

Python code lives in app.py

HTML templates in templates/

Database: SQLite file overtime.db

Service: systemd/overtime-kiosk.service

✅ With this flow, a new Pi goes from blank to a fully working dual-screen overtime kiosk in one command:

bash scripts/setup.sh dual
