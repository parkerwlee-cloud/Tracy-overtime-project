import os, sqlite3, glob, sys

DB_URL = os.getenv("DATABASE_URL", "sqlite:///overtime.db")
assert DB_URL.startswith("sqlite:///")
DB_PATH = DB_URL.replace("sqlite:///", "")

def ensure_core_tables(conn):
    conn.execute("""CREATE TABLE IF NOT EXISTS employees (
        id INTEGER PRIMARY KEY,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        clock_number TEXT,
        seniority_rank INTEGER DEFAULT 0
    );""")
    conn.execute("""CREATE TABLE IF NOT EXISTS slots (
        id INTEGER PRIMARY KEY,
        date DATE NOT NULL,
        label TEXT NOT NULL,
        is_closed INTEGER DEFAULT 0
    );""")

def main():
    os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    ensure_core_tables(conn)
    cur = conn.cursor()

    cur.execute("CREATE TABLE IF NOT EXISTS migrations (name TEXT PRIMARY KEY);")
    applied = {row[0] for row in cur.execute("SELECT name FROM migrations").fetchall()}

    for path in sorted(glob.glob("migrations/*.sql")):
        name = os.path.basename(path)
        if name in applied:
            continue
        sql = open(path, "r", encoding="utf-8").read()
        try:
            cur.executescript(sql)
            cur.execute("INSERT INTO migrations(name) VALUES (?)", (name,))
            conn.commit()
            print(f"Applied {name}")
        except Exception as e:
            print(f"Failed {name}: {e}")
            sys.exit(1)

    conn.close()
    print("Migrations complete.")

if __name__ == "__main__":
    main()
