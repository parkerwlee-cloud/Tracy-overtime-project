import os, re, sqlite3, io, csv
from datetime import datetime, date, time, timedelta
from flask import Flask, render_template, request, redirect, url_for, jsonify, session, abort, make_response
from flask_socketio import SocketIO, emit
from dotenv import load_dotenv

load_dotenv()

DB_PATH = os.path.join(os.path.dirname(__file__), "overtime.db")
SECRET_KEY = os.getenv("FLASK_SECRET", "dev-secret")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "admin123")
PRIOR_DAY_FREEZE = os.getenv("PRIOR_DAY_FREEZE", "14:00")
TODAY_2L_CLOSE = os.getenv("TODAY_2L_CLOSE", "15:30")

SLOT_TYPES = [("2 Early","2E"), ("2 Late","2L")]
CATEGORIES = {"Electrical","Mechanical","Programming","Mobile Equipment","Batch","Inspection"}

app = Flask(__name__)
app.secret_key = SECRET_KEY
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="eventlet")

CLOCK_RE = re.compile(r"^\d{4}$")

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def start_of_week(d=None):
    d = d or date.today()
    return d - timedelta(days=d.weekday())

def parse_hhmm(s, default_h=0, default_m=0):
    try:
        h,m = [int(x) for x in s.split(":")]
        return time(h,m)
    except:
        return time(default_h, default_m)

def prior_day_cutoff(slot_date_iso):
    sd = datetime.fromisoformat(slot_date_iso).date()
    return datetime.combine(sd - timedelta(days=1), parse_hhmm(PRIOR_DAY_FREEZE,14,0))

def today_2l_close_dt(slot_date_iso):
    sd = datetime.fromisoformat(slot_date_iso).date()
    return datetime.combine(sd, parse_hhmm(TODAY_2L_CLOSE,15,30))

def is_2e_frozen(slot_date_iso):
    return datetime.now() >= prior_day_cutoff(slot_date_iso)

def today_2l_window_state(slot_date_iso):
    sd = datetime.fromisoformat(slot_date_iso).date()
    if sd != date.today():
        return "not_today"
    now = datetime.now()
    cut_1400 = datetime.combine(sd, parse_hhmm(PRIOR_DAY_FREEZE,14,0))
    cut_1530 = today_2l_close_dt(slot_date_iso)
    if now < cut_1400:
        return "pre1400"
    elif now < cut_1530:
        return "win_1400_1530"
    else:
        return "post1530"

def employee_categories(db, emp_id):
    rows = db.execute("SELECT category FROM employee_categories WHERE employee_id=?", (emp_id,)).fetchall()
    return {r["category"] for r in rows}

def slot_categories(db, slot_id):
    rows = db.execute("SELECT category FROM slot_categories WHERE slot_id=?", (slot_id,)).fetchall()
    return {r["category"] for r in rows}

def employee_day_counts(db, emp_id, iso_date):
    cnt_2e = db.execute("""SELECT COUNT(*) c FROM signups x
                           JOIN slots s ON s.id=x.slot_id
                           WHERE x.employee_id=? AND s.slot_date=? AND s.slot_code='2E'""",
                        (emp_id, iso_date)).fetchone()["c"]
    cnt_2l = db.execute("""SELECT COUNT(*) c FROM signups x
                           JOIN slots s ON s.id=x.slot_id
                           WHERE x.employee_id=? AND s.slot_date=? AND s.slot_code='2L'""",
                        (emp_id, iso_date)).fetchone()["c"]
    return cnt_2e, cnt_2l

def second_2l_signup_ids_for_emp_on_date(db, emp_id, iso_date):
    rows = db.execute("""SELECT x.id FROM signups x
                         JOIN slots s ON s.id=x.slot_id
                         WHERE x.employee_id=? AND s.slot_date=? AND s.slot_code='2L'
                         ORDER BY x.created_at ASC""", (emp_id, iso_date)).fetchall()
    if len(rows) >= 2:
        return { rows[-1]["id"] }
    return set()

def is_second_2l_for_signup(db, signup_id):
    row = db.execute("""SELECT x.employee_id, s.slot_date FROM signups x
                        JOIN slots s ON s.id=x.slot_id WHERE x.id=?""",(signup_id,)).fetchone()
    if not row:
        return False
    second_ids = second_2l_signup_ids_for_emp_on_date(db, row["employee_id"], row["slot_date"])
    return signup_id in second_ids

@app.route("/")
def index():
    ws = start_of_week()
    days = [(ws + timedelta(days=i)).isoformat() for i in range(7)]
    with get_db() as db:
        for d in days:
            for _, code in SLOT_TYPES:
                db.execute("INSERT OR IGNORE INTO slots (slot_date, slot_code, capacity) VALUES (?,?,0)", (d, code))
        db.commit()
        slots = db.execute("""
            SELECT s.id, s.slot_date, s.slot_code, s.capacity, COUNT(x.id) taken
            FROM slots s LEFT JOIN signups x ON x.slot_id=s.id
            WHERE s.slot_date BETWEEN ? AND ?
            GROUP BY s.id
            ORDER BY s.slot_date, s.slot_code
        """,(days[0], days[-1])).fetchall()
        roster = db.execute("""
            SELECT x.id signup_id, s.id slot_id, s.slot_date, s.slot_code, e.name, e.clock_number
            FROM signups x
            JOIN employees e ON e.id=x.employee_id
            JOIN slots s ON s.id=x.slot_id
            WHERE s.slot_date BETWEEN ? AND ?
            ORDER BY s.slot_date, s.slot_code, x.created_at
        """,(days[0], days[-1])).fetchall()
        slot_cats_map = {}
        for r in db.execute("SELECT slot_id, category FROM slot_categories").fetchall():
            slot_cats_map.setdefault(r["slot_id"], []).append(r["category"])
    grid = {}
    for s in slots:
        grid.setdefault(s["slot_date"], {})[s["slot_code"]] = {
            "id": s["id"],
            "slot_date": s["slot_date"],
            "slot_code": s["slot_code"],
            "capacity": s["capacity"],
            "taken": s["taken"],
            "categories": slot_cats_map.get(s["id"], []),
            "people": [],
        }
    with get_db() as db:
        for r in roster:
            is_second = is_second_2l_for_signup(db, r["signup_id"])
            grid[r["slot_date"]][r["slot_code"]]["people"].append({
                "name": r["name"],
                "clock": r["clock_number"],
                "is_second_2l": bool(is_second)
            })
    for day, day_slots in grid.items():
        for label, code in SLOT_TYPES:
            s = day_slots.get(code)
            if not s: continue
            disabled = False
            hint = ""
            if code == "2E":
                if datetime.fromisoformat(day).date() >= date.today():
                    if is_2e_frozen(day):
                        disabled = True
                        hint="Frozen after 14:00 day prior"
            else:
                st = today_2l_window_state(day)
                if st == "pre1400":
                    hint = "Bumping allowed"
                elif st == "win_1400_1530":
                    hint = "2nd-2L forfeiture active; new signups allowed if space"
                    if s["taken"] >= s["capacity"]:
                        disabled = True
                elif st == "post1530":
                    hint = "Closed at 15:30"
                    disabled = True
                else:
                    hint = "Bumping allowed" if datetime.fromisoformat(day).date() > date.today() else hint
            s["state_hint"] = hint
            if s["capacity"] == 0:
                disabled = True
            s["disabled"] = disabled
    return render_template("kiosk.html", grid=grid, SLOT_TYPES=SLOT_TYPES)

@app.route("/display")
def display_wallboard():
    ws = start_of_week()
    days = [(ws + timedelta(days=i)).isoformat() for i in range(7)]
    with get_db() as db:
        slots = db.execute("""
            SELECT s.id, s.slot_date, s.slot_code, s.capacity, COUNT(x.id) taken
            FROM slots s LEFT JOIN signups x ON x.slot_id=s.id
            WHERE s.slot_date BETWEEN ? AND ?
            GROUP BY s.id
            ORDER BY s.slot_date, s.slot_code
        """,(days[0], days[-1])).fetchall()
        roster = db.execute("""
            SELECT x.id signup_id, s.id slot_id, s.slot_date, s.slot_code, e.name, e.clock_number
            FROM signups x
            JOIN employees e ON e.id=x.employee_id
            JOIN slots s ON s.id=x.slot_id
            WHERE s.slot_date BETWEEN ? AND ?
            ORDER BY s.slot_date, s.slot_code, x.created_at
        """,(days[0], days[-1])).fetchall()
        slot_cats_map = {}
        for r in db.execute("SELECT slot_id, category FROM slot_categories").fetchall():
            slot_cats_map.setdefault(r["slot_id"], []).append(r["category"])
    grid = {}
    for s in slots:
        grid.setdefault(s["slot_date"], {})[s["slot_code"]] = {
            "id": s["id"],
            "capacity": s["capacity"],
            "taken": s["taken"],
            "categories": slot_cats_map.get(s["id"], []),
            "people":[]
        }
    with get_db() as db:
        for r in roster:
            is_second = is_second_2l_for_signup(db, r["signup_id"])
            grid[r["slot_date"]][r["slot_code"]]["people"].append({
                "name": r["name"],
                "clock": r["clock_number"],
                "is_second_2l": bool(is_second)
            })
    return render_template("display.html", grid=grid, SLOT_TYPES=SLOT_TYPES)

@app.route("/admin", methods=["GET","POST"])
def admin_login():
    if request.method == "POST":
        if request.form.get("password") == ADMIN_PASSWORD:
            session["admin"] = True
            return redirect(url_for("admin_panel"))
        return render_template("admin_login.html", error="Invalid password")
    return render_template("admin_login.html")

def require_admin():
    if not session.get("admin"):
        abort(403)

@app.route("/admin/panel")
def admin_panel():
    if not session.get("admin"):
        return redirect(url_for("admin_login"))
    with get_db() as db:
        rows = db.execute("""
            SELECT s.id, s.slot_date, s.slot_code, s.capacity, COUNT(x.id) taken
            FROM slots s LEFT JOIN signups x ON x.slot_id=s.id
            GROUP BY s.id ORDER BY s.slot_date, s.slot_code
        """).fetchall()
        roster = db.execute("""
            SELECT x.id signup_id, s.id slot_id, s.slot_date, s.slot_code, e.name, e.clock_number
            FROM signups x
            JOIN employees e ON e.id=x.employee_id
            JOIN slots s ON s.id=x.slot_id
            ORDER BY s.slot_date, s.slot_code, x.created_at
        """).fetchall()
        slot_cats = {}
        for r in db.execute("SELECT slot_id, category FROM slot_categories").fetchall():
            slot_cats.setdefault(r["slot_id"], []).append(r["category"])
    grouped = {}
    with get_db() as db:
        for r in roster:
            is_second = is_second_2l_for_signup(db, r["signup_id"])
            grouped.setdefault(r["slot_id"], []).append({
                "name":r["name"],
                "clock":r["clock_number"],
                "is_second_2l":bool(is_second)
            })
    rows2 = [{**dict(r), "cats": slot_cats.get(r["id"], [])} for r in rows]
    return render_template("admin_panel.html", rows=rows2, roster=grouped, categories=list(CATEGORIES))

@app.post("/admin/slot/<int:slot_id>/capacity")
def admin_set_capacity(slot_id):
    require_admin()
    cap = max(0, int(request.form.get("capacity","0")))
    with get_db() as db:
        db.execute("UPDATE slots SET capacity=? WHERE id=?", (cap, slot_id))
        db.commit()
    socketio.emit("refresh", {"msg":"admin_update"})
    return redirect(url_for("admin_panel"))

@app.post("/admin/slot/<int:slot_id>/categories")
def admin_set_slot_categories(slot_id):
    require_admin()
    sel = [c for c in request.form.getlist("categories") if c in CATEGORIES]
    with get_db() as db:
        db.execute("DELETE FROM slot_categories WHERE slot_id=?", (slot_id,))
        for c in sel:
            db.execute("INSERT OR IGNORE INTO slot_categories (slot_id, category) VALUES (?,?)",(slot_id, c))
        db.commit()
    socketio.emit("refresh", {"msg":"admin_update"})
    return redirect(url_for("admin_panel"))

@app.route("/admin/employees")
def admin_employees():
    require_admin()
    with get_db() as db:
        employees = db.execute("SELECT id, name, phone, clock_number FROM employees ORDER BY clock_number").fetchall()
        emp_cats = {}
        for r in db.execute("SELECT employee_id, category FROM employee_categories").fetchall():
            emp_cats.setdefault(r["employee_id"], []).append(r["category"])
    emps = [{**dict(e), "cats": emp_cats.get(e["id"], [])} for e in employees]
    return render_template("employees.html", employees=emps, categories=list(CATEGORIES))

@app.post("/admin/employees/create")
def admin_emp_create():
    require_admin()
    name = request.form.get("name","").strip()
    clock = request.form.get("clock_number","").strip()
    phone = request.form.get("phone","").strip()
    if not (name and re.fullmatch(r"\d{4}", clock)):
        abort(400)
    cats = [c for c in request.form.getlist("categories") if c in CATEGORIES]
    with get_db() as db:
        try:
            db.execute("INSERT INTO employees (name, phone, clock_number) VALUES (?,?,?)",(name, phone, clock))
            emp_id = db.execute("SELECT last_insert_rowid() id").fetchone()["id"]
            for c in cats:
                db.execute("INSERT INTO employee_categories (employee_id, category) VALUES (?,?)",(emp_id, c))
            db.commit()
        except sqlite3.IntegrityError:
            return "Clock number must be unique", 400
    return redirect(url_for("admin_employees"))

@app.post("/admin/employees/update/<int:emp_id>")
def admin_emp_update(emp_id):
    require_admin()
    name = request.form.get("name","").strip()
    phone = request.form.get("phone","").strip()
    clock = request.form.get("clock_number","").strip()
    cats = [c for c in request.form.getlist("categories") if c in CATEGORIES]
    if not re.fullmatch(r"\d{4}", clock):
        abort(400)
    with get_db() as db:
        db.execute("UPDATE employees SET name=?, phone=?, clock_number=? WHERE id=?", (name, phone, clock, emp_id))
        db.execute("DELETE FROM employee_categories WHERE employee_id=?", (emp_id,))
        for c in cats:
            db.execute("INSERT OR IGNORE INTO employee_categories (employee_id, category) VALUES (?,?)",(emp_id,c))
        db.commit()
    socketio.emit("refresh", {"msg":"roster_update"})
    return redirect(url_for("admin_employees"))

@app.post("/admin/employees/delete/<int:emp_id>")
def admin_emp_delete(emp_id):
    require_admin()
    with get_db() as db:
        has = db.execute("SELECT 1 FROM signups WHERE employee_id=? LIMIT 1",(emp_id,)).fetchone()
        if has:
            return "Cannot delete: employee has signups.", 400
        db.execute("DELETE FROM employee_categories WHERE employee_id=?", (emp_id,))
        db.execute("DELETE FROM employees WHERE id=?", (emp_id,))
        db.commit()
    return redirect(url_for("admin_employees"))

def seniority_key(clock_number):
    try:
        return int(clock_number)
    except:
        return 9999

@app.post("/signup")
def signup():
    name = request.form.get("name","").strip()
    phone = request.form.get("phone","").strip()
    clock = request.form.get("clock_number","").strip()
    slot_id = request.form.get("slot_id")
    if not (name and clock and slot_id):
        return jsonify(ok=False, error="Missing fields"), 400
    if not CLOCK_RE.fullmatch(clock):
        return jsonify(ok=False, error="Clock Number must be exactly 4 digits"), 400
    with get_db() as db:
        slot = db.execute("SELECT id, slot_date, slot_code, capacity FROM slots WHERE id=?", (slot_id,)).fetchone()
        if not slot:
            return jsonify(ok=False, error="Slot not found"), 404
        emp = db.execute("SELECT id, name, phone, clock_number FROM employees WHERE clock_number=?", (clock,)).fetchone()
        if not emp:
            try:
                db.execute("INSERT INTO employees (name, phone, clock_number) VALUES (?,?,?)",(name, phone, clock))
                emp_id = db.execute("SELECT last_insert_rowid() id").fetchone()["id"]
            except sqlite3.IntegrityError:
                return jsonify(ok=False, error="Clock Number already exists"), 400
            emp = db.execute("SELECT id, name, phone, clock_number FROM employees WHERE id=?", (emp_id,)).fetchone()
        else:
            emp_id = emp["id"]
            if name and not (emp["name"] or "").strip():
                db.execute("UPDATE employees SET name=? WHERE id=?", (name, emp_id))
            if phone and not (emp["phone"] or "").strip():
                db.execute("UPDATE employees SET phone=? WHERE id=?", (phone, emp_id))
        cnt_2e, cnt_2l = employee_day_counts(db, emp_id, slot["slot_date"])
        if slot["slot_code"] == "2E" and cnt_2e >= 1:
            return jsonify(ok=False, status="limit_2e", error="You already have a 2E today (limit 1)."), 200
        if slot["slot_code"] == "2L" and cnt_2l >= 2:
            return jsonify(ok=False, status="limit_2l", error="You already have two 2L today (limit 2)."), 200
        if slot["slot_code"] == "2E" and is_2e_frozen(slot["slot_date"]) and date.fromisoformat(slot["slot_date"]) >= date.today():
            return jsonify(ok=False, status="frozen_2e", error="2E is frozen after 14:00 day prior."), 200
        if slot["slot_code"] == "2L":
            state = today_2l_window_state(slot["slot_date"])
            if state == "post1530" and date.fromisoformat(slot["slot_date"]) == date.today():
                return jsonify(ok=False, status="closed_today_2l", error="Today's 2L closed at 15:30."), 200
        taken = db.execute("SELECT COUNT(*) c FROM signups WHERE slot_id=?", (slot["id"],)).fetchone()["c"]
        if taken < slot["capacity"]:
            db.execute("INSERT INTO signups (employee_id, slot_id, created_at) VALUES (?,?,datetime('now'))",(emp_id, slot["id"]))
            db.commit()
            socketio.emit("refresh", {"msg":"signup_changed"})
            return jsonify(ok=True, status="success"), 200
        occ = db.execute("""
            SELECT x.id signup_id, e.id emp_id, e.clock_number, e.name, e.phone
            FROM signups x JOIN employees e ON e.id=x.employee_id
            WHERE x.slot_id=? ORDER BY x.created_at
        """,(slot["id"],)).fetchall()
        if slot["slot_code"] == "2L" and today_2l_window_state(slot["slot_date"]) == "win_1400_1530":
            candidates = [o for o in occ if is_second_2l_for_signup(db, o["signup_id"])]
            if not candidates:
                return jsonify(ok=False, status="full_no_bump_window", error="Slot full; only second-2L bumps allowed until 15:30."), 200
            loser = sorted(candidates, key=lambda o: seniority_key(o["clock_number"]), reverse=True)[0]
            try:
                db.execute("BEGIN")
                db.execute("DELETE FROM signups WHERE id=?", (loser["signup_id"],))
                db.execute("INSERT INTO signups (employee_id, slot_id, created_at) VALUES (?,?,datetime('now'))",(emp_id, slot["id"]))
                db.execute("INSERT INTO bump_events (slot_id, new_employee_id, bumped_employee_id, created_at, reason) VALUES (?,?,?,datetime('now'),?)",
                           (slot["id"], emp_id, loser["emp_id"], "today_2l_second_forfeiture"))
                db.commit()
            except Exception:
                db.rollback()
                return jsonify(ok=False, error="Could not complete bump"), 500
            socketio.emit("refresh", {"msg":"signup_changed"})
            return jsonify(ok=True, status="bumped_second_2l"), 200
        slot_cats = slot_categories(db, slot["id"])
        emp_cats = employee_categories(db, emp_id)
        emp_matches = len(slot_cats.intersection(emp_cats)) > 0
        def occ_priority(o):
            is_second = is_second_2l_for_signup(db, o["signup_id"]) if slot["slot_code"] == "2L" else False
            o_cats = employee_categories(db, o["emp_id"])
            o_match = len(slot_cats.intersection(o_cats)) > 0
            return (1 if is_second else 2, 0 if not o_match else 1, seniority_key(o["clock_number"]))
        weakest = sorted(occ, key=occ_priority)[0]
        weakest_cats = employee_categories(db, weakest["emp_id"])
        weakest_match = len(slot_cats.intersection(weakest_cats)) > 0
        challenger_better = False
        if emp_matches and not weakest_match:
            challenger_better = True
        elif emp_matches == weakest_match:
            challenger_better = seniority_key(emp["clock_number"]) < seniority_key(weakest["clock_number"])
        if not challenger_better:
            return jsonify(ok=False, status="full_no_priority", error="Slot full; your priority is not high enough to bump."), 200
        try:
            db.execute("BEGIN")
            db.execute("DELETE FROM signups WHERE id=?", (weakest["signup_id"],))
            db.execute("INSERT INTO signups (employee_id, slot_id, created_at) VALUES (?,?,datetime('now'))",(emp_id, slot["id"]))
            db.execute("INSERT INTO bump_events (slot_id, new_employee_id, bumped_employee_id, created_at, reason) VALUES (?,?,?,datetime('now'),?)",
                       (slot["id"], emp_id, weakest["emp_id"], "category_seniority"))
            db.commit()
        except Exception:
            db.rollback()
            return jsonify(ok=False, error="Could not complete bump"), 500
        socketio.emit("refresh", {"msg":"signup_changed"})
        return jsonify(ok=True, status="bumped"), 200

@app.get("/health")
def health():
    return {"ok": True}

@socketio.on("connect")
def on_connect():
    emit("connected", {"ok": True})

if __name__ == "__main__":
    port = int(os.environ.get("PORT","5000"))
    socketio.run(app, host="0.0.0.0", port=port)
