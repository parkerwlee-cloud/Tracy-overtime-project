# Tracy Overtime Kiosk — v0.9.0

**Two-week view, simplified sign-in, Day vs Rotating priority, weekend freeze.**

## What’s in v0.9.0
- Always-visible wallboard showing **Current Week** and **Next Week** (Mon–Sun).
- Large toggle to focus **Current** or **Next**; default to **Current**.
- Kiosk flow: **Select slot → type name → pick from roster → confirm.**
- Admin: **Create Next Week (draft)**, **Save draft without publishing**, **Publish**, **Close**.
- **Weekend freeze**: Sat/Sun signups locked after **Friday 15:30** (configurable TZ).
- **Priority**: Day-shift > Rotating; existing **seniority** and existing rules preserved;
  on weekends **Full 8 auto-bumps partials** (after shift priority). Deterministic tie-breaks.

## Quick start (fresh Pi or local)
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Initialize .env
cp .env.example .env
# (Edit ADMIN_PASSWORD, TWILIO creds if needed)

# Initialize DB & run migrations
bash scripts/migrate.sh

# Run dev server
python run.py
```

## Systemd service (optional)
```bash
sudo cp systemd/overtime-kiosk.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable overtime-kiosk.service
sudo systemctl start overtime-kiosk.service
```

## Self-test
```bash
bash scripts/self-test.sh
```

## Versioning
Single source of truth in `VERSION`. The app footer and admin UI display `v0.9.0`.
