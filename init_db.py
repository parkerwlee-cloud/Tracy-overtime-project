import os, sqlite3
from datetime import date, timedelta

DB_PATH = os.path.join(os.path.dirname(__file__), "overtime.db")
CATEGORIES = ["Electrical","Mechanical","Programming","Mobile Equipment","Batch","Inspection"]

def start_of_week(d=None):
    d = d or date.today()
    return d - timedelta(days=d.weekday())

def migrate(conn):
    c = conn.cursor()
    c.execute("""CREATE TABLE IF NOT EXISTS employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT, phone TEXT, clock_number TEXT UNIQUE
    )""")
    c.execute("""CREATE TABLE IF NOT EXISTS employee_categories (
        employee_id INTEGER NOT NULL, category TEXT NOT NULL,
        UNIQUE(employee_id, category),
        FOREIGN KEY(employee_id) REFERENCES employees(id)
    )""")
    c.execute("""CREATE TABLE IF NOT EXISTS slots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        slot_date TEXT NOT NULL, slot_code TEXT NOT NULL,
        capacity INTEGER NOT NULL DEFAULT 0,
        UNIQUE(slot_date, slot_code)
    )""")
    c.execute("""CREATE TABLE IF NOT EXISTS slot_categories (
        slot_id INTEGER NOT NULL, category TEXT NOT NULL,
        UNIQUE(slot_id, category),
        FOREIGN KEY(slot_id) REFERENCES slots(id)
    )""")
    c.execute("""CREATE TABLE IF NOT EXISTS signups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL,
        slot_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(employee_id) REFERENCES employees(id),
        FOREIGN KEY(slot_id) REFERENCES slots(id)
    )""")
    c.execute("""CREATE TABLE IF NOT EXISTS bump_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        slot_id INTEGER NOT NULL,
        new_employee_id INTEGER NOT NULL,
        bumped_employee_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        reason TEXT,
        FOREIGN KEY(slot_id) REFERENCES slots(id)
    )""")
    conn.commit()

def seed_week(conn):
    ws = start_of_week()
    c = conn.cursor()
    for i in range(7):
        d = (ws + timedelta(days=i)).isoformat()
        for code in ("2E","2L"):
            c.execute("INSERT OR IGNORE INTO slots (slot_date, slot_code, capacity) VALUES (?,?,?)", (d, code, 0))
    conn.commit()

def main():
    conn = sqlite3.connect(DB_PATH)
    migrate(conn)
    seed_week(conn)
    conn.close()
    print("✅ DB ready at", DB_PATH)

if __name__ == "__main__":
    main()
