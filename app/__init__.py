# app/__init__.py
import os
from flask import Flask
from dotenv import load_dotenv
from .utils import load_version, tz_now
from .models import init_db
from .routes import register_kiosk
from .admin_routes import register_admin

def create_app():
    load_dotenv()
    app = Flask(__name__, static_url_path="/static", static_folder="../static", template_folder="../templates")

    # Core config
    app.config["SECRET_KEY"] = os.getenv("SECRET_KEY", "dev-key")
    app.config["DATABASE_URL"] = os.getenv("DATABASE_URL", "sqlite:///overtime.db")
    app.config["TIMEZONE"] = os.getenv("TIMEZONE", "America/Los_Angeles")
    app.config["APP_VERSION"] = load_version()

    # Admin creds
    app.config["ADMIN_USERNAME"] = os.getenv("ADMIN_USERNAME", "admin")
    app.config["ADMIN_PASSWORD"] = os.getenv("ADMIN_PASSWORD", "admin123")

    # Twilio (optional; kept for later)
    app.config["TWILIO_ENABLED"] = str(os.getenv("TWILIO_ENABLED", "false")).lower() == "true"
    app.config["TWILIO_ACCOUNT_SID"] = os.getenv("TWILIO_ACCOUNT_SID", "")
    app.config["TWILIO_AUTH_TOKEN"] = os.getenv("TWILIO_AUTH_TOKEN", "")
    app.config["TWILIO_FROM_NUMBER"] = os.getenv("TWILIO_FROM_NUMBER", "")

    # DB
    init_db(app)

    # Inject globals for templates
    @app.context_processor
    def inject_globals():
        return {
            "APP_VERSION": app.config["APP_VERSION"],
            "now": tz_now(app.config["TIMEZONE"])
        }

    # Register routes that match your templates' url_for() names
    register_kiosk(app)
    register_admin(app)

    return app
