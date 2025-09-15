import os
from flask import Flask
from dotenv import load_dotenv
from .utils import load_version, tz_now
from .models import init_db
from .routes import bp as kiosk_bp
from .admin_routes import bp as admin_bp

def create_app():
    load_dotenv()
    app = Flask(__name__, static_url_path="/static", static_folder="../static", template_folder="../templates")

    app.config["SECRET_KEY"] = os.getenv("SECRET_KEY", "dev-key")
    app.config["DATABASE_URL"] = os.getenv("DATABASE_URL", "sqlite:///overtime.db")
    app.config["TIMEZONE"] = os.getenv("TIMEZONE", "America/Los_Angeles")
    app.config["APP_VERSION"] = load_version()

    # Twilio config
    app.config["TWILIO_ENABLED"] = os.getenv("TWILIO_ENABLED", "false").lower() == "true"
    app.config["TWILIO_ACCOUNT_SID"] = os.getenv("TWILIO_ACCOUNT_SID", "")
    app.config["TWILIO_AUTH_TOKEN"] = os.getenv("TWILIO_AUTH_TOKEN", "")
    app.config["TWILIO_FROM_NUMBER"] = os.getenv("TWILIO_FROM_NUMBER", "")

    # Admin creds
    app.config["ADMIN_USERNAME"] = os.getenv("ADMIN_USERNAME", "admin")
    app.config["ADMIN_PASSWORD"] = os.getenv("ADMIN_PASSWORD", "admin123")

    # DB
    init_db(app)

    # Inject globals
    @app.context_processor
    def inject_globals():
        return {"APP_VERSION": app.config["APP_VERSION"], "now": tz_now(app.config["TIMEZONE"])}

    # Blueprints
    app.register_blueprint(kiosk_bp)
    app.register_blueprint(admin_bp, url_prefix="/admin")

    return app
