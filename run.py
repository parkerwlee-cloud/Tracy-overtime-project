# run.py
import os
from app import create_app

if __name__ == "__main__":
    app = create_app()
    port = int(os.environ.get("PORT", "5000"))
    # For local kiosk usage the built-in server is fine.
    # If you later want Socket.IO or gunicorn, we can swap this line.
    app.run(host="0.0.0.0", port=port)
