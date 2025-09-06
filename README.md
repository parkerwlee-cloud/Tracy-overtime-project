# Overtime Kiosk

This project provides a dual-screen kiosk system to manage overtime sign-ups:

- **Wallboard display** (left screen) → `/display` roster
- **Touchscreen kiosk** (right screen) → `/` sign-up form
- Runs automatically on a Raspberry Pi 5 (or Pi 4) at startup
- Self-heals under systemd, logs available with one command

---

## 1. What you need

- Raspberry Pi 5 (or Pi 4) running Raspberry Pi OS Desktop (Bookworm or newer)  
- Two monitors (HDMI connections)  
- USB keyboard/mouse (for setup only)  
- Network connection (Ethernet or Wi-Fi)  

---

## 2. Prepare the Pi (first time only)

1. Boot Pi to the desktop and connect it to the internet.  
2. Open a Terminal (black icon on the top bar).  
3. Install git, Python tools, and Chromium:

   ```bash
   sudo apt update
   sudo apt install -y git python3-venv chromium
