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
