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
# Twilio placeholders (kept for future use)
TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN = os.getenv("TWILIO_AUTH_TOKEN", "")
TWILIO_FROM = os.getenv("TWILIO_FROM", "")
# Email placeholders (kept for future use)
SMTP_HOST=os.getenv("SMTP_HOST","")
SMTP_PORT=os.getenv("SMTP_PORT","587")
SMTP_USER=os.getenv("SMTP_USER","")
SMTP_PASS=os.getenv("SMTP_PASS","")
SMTP_FROM=os.getenv("SMTP_FROM","overtime@example.com")
SUMMARY_TO=os.getenv("SUMMARY_TO","boss@example.com,hr@example.com")

# Time rules (24h format)
PRIOR_DAY_FREEZE="14:00"     # 2E hard freeze day-prior
TODAY_2L_CLOSE="15:30"       # today 2L closes at this time

SLOT_TYPES = [("2E","2E (Early)"), ("2L","2L (Late)")]
SLOT_CODES = [code for code, _ in SLOT_TYPES]
CATEGORIES = {"Electrical","Mechanical","Programming","Mobile Equipment","Batch","Inspection"}

app = Flask(__name__)
ensure_schema()
app.secret_key = SECRET_KEY
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="eventlet")

CLOCK_RE = re.compile(r"^\d{4}$")


def ensure_schema():
    with get_db() as db:
        cols = [r[1] for r in db.execute("PRAGMA table_info(signups)")]
        if 'part' not in cols:
            db.execute("ALTER TABLE signups ADD COLUMN part TEXT")
            db.commit()

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    # Enforce foreign keys on every connection
    conn.execute("PRAGMA foreign_keys = ON;")
    return conn

def start_of_week(d=None):
    d = d or date.today()
    return d - timedelta(days=d.weekday())

def this_week_dates():
    ws = start_of_week()
    return [(ws + timedelta(days=i)).isoformat() for i in range(7)]

def parse_hhmm(s):
    h, m = s.split(":")
    return time(int(h), int(m))

def is_2e_frozen(slot_date_iso):
    """2E frozen after 14:00 on the prior day, for today and future."""
    try:
        d = date.fromisoformat(slot_date_iso)
    except Exception:
        return False
    now = datetime.now()
    if d < date.today():
        return False
    cutoff = datetime.combine(d - timedelta(days=1), parse_hhmm(PRIOR_DAY_FREEZE))
    return now >= cutoff

def today_2l_window_state(slot_date_iso):
    """
    For a 2L slot that is for TODAY:
      - before 14:00 -> "pre1400"
      - 14:00..15:30 -> "win_1400_1530" (bump only second-2L)
      - after 15:30  -> "post1530" (closed)
    For non-today -> "other"
    """
    try:
        d = date.fromisoformat(slot_date_iso)
    except Exception:
        return "other"
    if d != date.today():
        return "other"
    now = datetime.now().time()
    t1400 = parse_hhmm("14:00")
    t1530 = parse_hhmm(TODAY_2L_CLOSE)
    if now < t1400:
        return "pre1400"
    if now <= t1530:
        return "win_1400_1530"
    return "post1530"

def ensure_week_slots():
    with get_db() as db:
        c = db.cursor()
        ws = start_of_week()
        for i in range(7):
            d = (ws + timedelta(days=i)).isoformat()
            for code in SLOT_CODES:
                c.execute("INSERT OR IGNORE INTO slots (slot_date, slot_code, capacity) VALUES (?,?,?)",(d, code, 0))
        db.commit()

def slot_categories(db, slot_id):
    rows = db.execute("SELECT category FROM slot_categories WHERE slot_id=?", (slot_id,)).fetchall()
    return {r["category"] for r in rows}

def employee_categories(db, emp_id):
    rows = db.execute("SELECT category FROM employee_categories WHERE employee_id=?", (emp_id,)).fetchall()
    return {r["category"] for r in rows}

def employee_day_counts(db, emp_id, slot_date_iso):
    r2e = db.execute("""SELECT COUNT(*) c
                        FROM signups s JOIN slots sl ON sl.id=s.slot_id
                        WHERE s.employee_id=? AND sl.slot_date=? AND sl.slot_code='2E'""",(emp_id, slot_date_iso)).fetchone()["c"]
    r2l = db.execute("""SELECT COUNT(*) c
                        FROM signups s JOIN slots sl ON sl.id=s.slot_id
                        WHERE s.employee_id=? AND sl.slot_date=? AND sl.slot_code='2L'""",(emp_id, slot_date_iso)).fetchone()["c"]
    return r2e, r2l

def is_second_2l_for_signup(db, signup_id):
    row = db.execute("""
        SELECT e.id emp_id, sl.slot_date
        FROM signups s
        JOIN employees e ON e.id = s.employee_id
        JOIN slots sl ON sl.id = s.slot_id
        WHERE s.id=?
    """,(signup_id,)).fetchone()
    if not row:
        return False
    emp_id=row["emp_id"]; d=row["slot_date"]
    cnt = db.execute("""
        SELECT COUNT(*) c
        FROM signups s JOIN slots sl ON sl.id=s.slot_id
        WHERE s.employee_id=? AND sl.slot_date=? AND sl.slot_code='2L'
    """,(emp_id, d)).fetchone()["c"]
    return cnt >= 2

def grid_for_week():
    ensure_week_slots()
    with get_db() as db:
        dates = this_week_dates()
        grid = []
        for d in dates:
            day = {"date": d, "rows": []}
            for code, label in SLOT_TYPES:
                slot = db.execute("SELECT id, capacity FROM slots WHERE slot_date=? AND slot_code=?", (d, code)).fetchone()
                if not slot:
                    slot_id, capacity = None, 0
                else:
                    slot_id, capacity = slot["id"], slot["capacity"]
                taken = 0
                if slot_id:
                    taken = db.execute("SELECT COUNT(*) c FROM signups WHERE slot_id=?", (slot_id,)).fetchone()["c"]
                disabled = False
                state_hint = ""
                if code == "2E" and is_2e_frozen(d) and date.fromisoformat(d) >= date.today():
                    disabled = True
                    state_hint = "2E frozen after 14:00 day prior"
                elif code == "2L":
                    state = today_2l_window_state(d)
                    if state == "post1530" and date.fromisoformat(d) == date.today():
                        disabled = True
                        state_hint = "Today's 2L closed at 15:30"
                btn_disabled = disabled or capacity <= taken
                day["rows"].append({
                    "slot_id": slot_id,
                    "slot_code": code,
                    "label": label,
                    "capacity": capacity,
                    "taken": taken,
                    "disabled": btn_disabled,
                    "state_hint": state_hint
                })
            grid.append(day)
        return grid

@app.get("/")
def kiosk():
    ensure_week_slots()
    grid = grid_for_week()
    return render_template("kiosk.html", grid=grid, SLOT_TYPES=SLOT_TYPES)

@app.get("/display")

def choose_weekend_winners(rows):
    """Weekend winners: any 'full8' beats any combo of 4s; else up to two 4s (prefer first+last)."""
    full8 = [r for r in rows if (r.get('part') or '').lower() == 'full8']
    if full8:
        return [sorted(full8, key=lambda x: x.get('submitted_at'))[0]]
    first4 = [r for r in rows if (r.get('part') or '').lower() in ('first4','early','first')]
    last4  = [r for r in rows if (r.get('part') or '').lower() in ('last4','late','last')]
    if first4 and last4:
        return [sorted(first4, key=lambda x: x.get('submitted_at'))[0],
                sorted(last4,  key=lambda x: x.get('submitted_at'))[0]]
    both = sorted(first4 + last4, key=lambda x: x.get('submitted_at'))
    return both[:2]


def wallboard():
    ensure_week_slots()
    grid = grid_for_week()

    # Attach assignees per slot; weekend winners chosen by rule
    with get_db() as db:
        for day in grid:
            try:
                day_date = date.fromisoformat(day.get('date'))
            except Exception:
                day_date = None
            for r in day.get('rows', []):
                sid = r.get('slot_id') if isinstance(r, dict) else None
                if not sid:
                    r['assignees'] = []
                    continue
                rows = db.execute(
                    """
                    SELECT e.name, e.clock_number, s.created_at as submitted_at, s.part as part
                    FROM signups s JOIN employees e ON e.id=s.employee_id
                    WHERE s.slot_id=?
                    ORDER BY s.created_at
                    """,
                    (sid,)
                ).fetchall()
                people = [dict(name=row['name'], clock_number=row['clock_number'], submitted_at=row['submitted_at'], part=row['part']) for row in rows]
                if day_date and day_date.weekday() in (5,6):
                    winners = choose_weekend_winners(people)
                else:
                    cap = r.get('capacity') or 0
                    winners = [dict(name=p['name'], clock_number=p['clock_number']) for p in people][:cap]
                r['assignees'] = winners

    return render_template("display.html", grid=grid, SLOT_TYPES=SLOT_TYPES)
  # ASSIGNEES_ATTACHED

@app.route("/admin", methods=["GET","POST"])
def admin_login():
    if request.method == "POST":
        if request.form.get("password") == ADMIN_PASSWORD:
            session["admin"] = True
            return redirect(url_for("admin_panel"))
        return render_template("admin_login.html", error="Invalid password")
    return render_template("admin_login.html")

@app.get("/admin/logout")
def admin_logout():
    session.clear()
    return redirect(url_for("admin_login"))

def require_admin():
    if not session.get("admin"):
        abort(403)

@app.route("/admin/panel")
def admin_panel():
    if not session.get("admin"):
        return redirect(url_for("admin_login"))
    with get_db() as db:
        rows = db.execute("""
            SELECT s.id, s.slot_date, s.slot_code, s.capacity,
                   (SELECT COUNT(*) FROM signups x WHERE x.slot_id=s.id) taken
            FROM slots s
            ORDER BY s.slot_date, s.slot_code
        """).fetchall()
        scats = {}
        for r in db.execute("SELECT slot_id, category FROM slot_categories").fetchall():
            scats.setdefault(r["slot_id"], set()).add(r["category"])
        data = []
        for r in rows:
            data.append({
                "id": r["id"],
                "date": r["slot_date"],
                "code": r["slot_code"],
                "capacity": r["capacity"],
                "taken": r["taken"],
                "categories": sorted(scats.get(r["id"], []))
            })
    return render_template("admin_panel.html", slots=data, categories=sorted(CATEGORIES))

@app.post("/admin/slot/capacity")
def admin_set_capacity():
    require_admin()
    slot_id = request.form.get("slot_id")
    cap = request.form.get("capacity")
    if not (slot_id and cap and cap.isdigit()):
        abort(400)
    with get_db() as db:
        db.execute("UPDATE slots SET capacity=? WHERE id=?", (int(cap), int(slot_id)))
        db.commit()
    socketio.emit("refresh", {"msg":"admin_update"})
    return redirect(url_for("admin_panel"))

@app.post("/admin/slot/categories")
def admin_set_slot_categories():
    require_admin()
    slot_id = request.form.get("slot_id")
    sel = [c for c in request.form.getlist("categories") if c in CATEGORIES]
    if not slot_id:
        abort(400)
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
            emp_cats.setdefault(r["employee_id"], set()).add(r["category"])
    return render_template("employees.html", employees=employees, emp_cats=emp_cats, categories=list(CATEGORIES))

@app.post("/admin/employees/create")
def admin_emp_create():
    require_admin()
    name = request.form.get("name","").strip()
    clock = request.form.get("clock_number","").strip()
    part = (request.form.get(\"part\") or '').strip().lower()
    part = (request.form.get(\"part\") or '').strip().lower()
    phone = request.form.get("phone","").strip()
    if not (name and re.fullmatch(r"\d{4}", clock)):
        abort(400)
    cats = [c for c in request.form.getlist("categories") if c in CATEGORIES]
    with get_db() as db:
        try:
            db.execute("INSERT INTO employees (name, phone, clock_number) VALUES (?,?,?)",(name, phone, clock))
            emp_id = db.execute("SELECT last_insert_rowid() id").fetchone()["id"]
            for c in cats:
                db.execute("INSERT OR IGNORE INTO employee_categories (employee_id, category) VALUES (?,?)",(emp_id, c))
            db.commit()
        except sqlite3.IntegrityError:
            db.rollback()
            return "Clock number already exists", 400
    socketio.emit("refresh", {"msg":"roster_update"})
    return redirect(url_for("admin_employees"))

@app.post("/admin/employees/update/<int:emp_id>")
def admin_emp_update(emp_id):
    require_admin()
    name = request.form.get("name","").strip()
    phone = request.form.get("phone","").strip()
    clock = request.form.get("clock_number","").strip()
    part = (request.form.get(\"part\") or '').strip().lower()
    cats = [c for c in request.form.getlist("categories") if c in CATEGORIES]
    if not re.fullmatch(r"\d{4}", clock):
        abort(400)
    with get_db() as db:
        try:
            db.execute("UPDATE employees SET name=?, phone=?, clock_number=? WHERE id=?", (name, phone, clock, emp_id))
            db.execute("DELETE FROM employee_categories WHERE employee_id=?", (emp_id,))
            for c in cats:
                db.execute("INSERT OR IGNORE INTO employee_categories (employee_id, category) VALUES (?,?)",(emp_id,c))
            db.commit()
        except sqlite3.IntegrityError:
            db.rollback()
            return "Clock number must be unique", 400
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


def is_slot_weekend(db, slot_id):
    row = db.execute("SELECT date FROM slots WHERE id=?", (slot_id,)).fetchone()
    if not row: 
        return False
    try:
        d = date.fromisoformat(row["date"])
        return d.weekday() in (5,6)
    except Exception:
        return False

@app.post("/signup")
def signup():
    name = request.form.get("name","").strip()
    phone = request.form.get("phone","").strip()
    clock = request.form.get("clock_number","").strip()
    part = (request.form.get(\"part\") or '').strip().lower()
    slot_id = request.form.get("slot_id")
    if not (name and clock and slot_id):
        return jsonify(ok=False, error="Missing fields"), 400
    if not CLOCK_RE.fullmatch(clock):
        return jsonify(ok=False, error="Clock Number must be exactly 4 digits"), 400
    with get_db() as db:

        # Weekend bumping logic:
        wknd = is_slot_weekend(db, slot["id"])
        if wknd:
            # Normalize part values
            if part not in ("first4","full8","last4"):
                # try to infer from label if not provided
                pl = (slot.get("label") or "").lower()
                if "full" in pl or "8" in pl:
                    part = "full8"
            if part == "full8":
                # Full 8 automatically bumps partials on weekends
                db.execute("DELETE FROM signups WHERE slot_id=? AND (part='first4' OR part='last4')", (slot["id"],))
            elif part in ("first4","last4"):
                # If a Full 8 already exists, do not allow partial
                exists_full = db.execute("SELECT 1 FROM signups WHERE slot_id=? AND part='full8' LIMIT 1", (slot["id"],)).fetchone()
                if exists_full:
                    flash("A Full 8 signup already holds this weekend slot. Your 4-hour signup was not added.", "warning")
                    return redirect(url_for("kiosk"))
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

        # Duplicate guard
        already = db.execute(
            "SELECT 1 FROM signups WHERE employee_id=? AND slot_id=? LIMIT 1",
            (emp_id, slot["id"])
        ).fetchone()
        if already:
            return jsonify(ok=False, status="duplicate", error="You are already signed up for this slot."), 200

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
            db.execute("INSERT INTO signups (employee_id, slot_id, created_at, part) VALUES (?,?,datetime('now'), ?)", (emp_id, slot["id"], part))
            db.commit()
            socketio.emit("refresh", {"msg":"signup_changed"})
            return jsonify(ok=True, status="success"), 200

        # Full: bump logic
        occ = db.execute("""
            SELECT x.id signup_id, e.id emp_id, e.clock_number, e.name, e.phone
            FROM signups x JOIN employees e ON e.id=x.employee_id
            WHERE x.slot_id=? ORDER BY x.created_at
        """,(slot["id"],)).fetchall()

        # Special window: only second-2L bumps 14:00–15:30 today
        if slot["slot_code"] == "2L" and today_2l_window_state(slot["slot_date"]) == "win_1400_1530":
            candidates = [o for o in occ if is_second_2l_for_signup(db, o["signup_id"])]
            if not candidates:
                return jsonify(ok=False, status="full_no_bump_window", error="Slot full; only second-2L bumps allowed until 15:30."), 200
            loser = sorted(candidates, key=lambda o: seniority_key(o["clock_number"]), reverse=True)[0]
            try:
                db.execute("BEGIN")
                db.execute("DELETE FROM signups WHERE id=?", (loser["signup_id"],))
                db.execute("INSERT INTO signups (employee_id, slot_id, created_at, part) VALUES (?,?,datetime('now'), ?)", (emp_id, slot["id"], part))
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
            # second-2L first (1), then others (2);
            # non-matching cats first (0), then matching (1);
            # least senior first (negative seniority)
            return (1 if is_second else 2, 0 if not o_match else 1, -seniority_key(o["clock_number"]))

        weakest = sorted(occ, key=occ_priority)[0]
        weakest_cats = employee_categories(db, weakest["emp_id"])
        weakest_match = len(slot_cats.intersection(weakest_cats)) > 0

        challenger_better = False
        if emp_matches and not weakest_match:
            challenger_better = True
        elif emp_matches == weakest_match:
            challenger_better = seniority_key(emp["clock_number"]) > seniority_key(weakest["clock_number"])
        if not challenger_better:
            return jsonify(ok=False, status="full_no_priority", error="Slot full; your priority is not high enough to bump."), 200

        try:
            db.execute("BEGIN")
            db.execute("DELETE FROM signups WHERE id=?", (weakest["signup_id"],))
            db.execute("INSERT INTO signups (employee_id, slot_id, created_at, part) VALUES (?,?,datetime('now'), ?)", (emp_id, slot["id"], part))
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

@app.get("/healthz")
def healthz():
    return {"ok": True}

@socketio.on("connect")
def on_connect():
    emit("connected", {"ok": True})


@app.template_filter('fmt_day_date_iso')
def fmt_day_date_iso(s):
    """Input: 'YYYY-MM-DD' -> 'Monday - M/D/YY'"""
    try:
        d = date.fromisoformat(s)
        dow = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][d.weekday()]
        return f"{dow} - {d.month}/{d.day}/{str(d.year)[-2:]}"
    except Exception:
        return s

@app.template_filter('is_weekend')
def is_weekend(s):
    try:
        d = date.fromisoformat(s)
        return d.weekday() in (5,6)
    except Exception:
        return False

@app.template_filter('weekend_label_display')
def weekend_label_display(label):
    l = (label or '').lower()
    if 'full' in l or '8' in l:
        return 'Full 8'
    if 'first' in l or 'early' in l or 'first 4' in l:
        return 'First 4'
    if 'last' in l or 'late' in l or 'last 4' in l:
        return 'Last 4'
    return label

@app.template_filter('fmt_person_from_name')
def fmt_person_from_name(p):
    """p: mapping with 'name' and 'clock_number' -> 'F. Last - CLOCK'"""
    try:
        name = p.get('name') if isinstance(p, dict) else getattr(p, 'name', '')
        clock = p.get('clock_number') if isinstance(p, dict) else getattr(p, 'clock_number', '')
    except Exception:
        return ''
    parts = str(name or '').strip().split()
    first_initial = (parts[0][:1].upper() + '.') if parts else ''
    last = parts[-1] if len(parts) >= 2 else (parts[0] if parts else '')
    return f"{first_initial} {last} - {clock}".strip()

if __name__ == "__main__":
    port = int(os.environ.get("PORT","5000"))
    socketio.run(app, host="0.0.0.0", port=port)
