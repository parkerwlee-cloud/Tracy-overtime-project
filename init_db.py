# init_db.py
from app import create_app
from app.models import init_db

if __name__ == "__main__":
    app = create_app()
    # init_db is already called inside create_app, but this makes the script idempotent and explicit.
    init_db(app)
    print("✅ Database initialized (SQLAlchemy)")
