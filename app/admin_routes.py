from datetime import date, timedelta
from functools import wraps
from flask import Blueprint, render_template, request, redirect, url_for, current_app, session as flask_session, flash
from .models import session, Week, Slot, Employee
from .utils import monday_of

bp = Blueprint("admin", __name__)

def check_auth(username, password):
    return username == current_app.config["ADMIN_USERNAME"] and password == current_app.config["ADMIN_PASSWORD"]

def login_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if not flask_session.get("admin_ok"):
            return redirect(url_for("admin.login"))
        return f(*args, **kwargs)
    return wrapper

@bp.route("/login", methods=["GET","POST"])
def login():
    if request.method == "POST":
        if check_auth(request.form.get("username"), request.form.get("password")):
            flask_session["admin_ok"] = True
            return redirect(url_for("admin.weeks"))
        flash("Invalid credentials", "error")
    return render_template("admin_login.html")

@bp.route("/logout")
def logout():
    flask_session.clear()
    return redirect(url_for("admin.login"))

@bp.route("/weeks")
def weeks():
    s = session()
    all_weeks = s.query(Week).order_by(Week.start_date.desc()).limit(6).all()
    return render_template("admin_weeks.html", weeks=all_weeks)

@bp.post("/weeks/create-next")
def create_next_week():
    s = session()
    today = date.today()
    cur_start = monday_of(today)
    nxt_start = cur_start + timedelta(days=7)
    nxt_end = nxt_start + timedelta(days=6)
    ex = s.query(Week).filter(Week.start_date==nxt_start).one_or_none()
    if ex:
        flash("Next week already exists.", "info")
        return redirect(url_for("admin.weeks"))
    wk = Week(start_date=nxt_start, end_date=nxt_end, status="draft")
    s.add(wk); s.commit()

    labels = ["First 4","Full 8","Last 4"]
    for i in range(7):
        d = nxt_start + timedelta(days=i)
        if d.weekday() >= 5:
            for lab in labels:
                sl = Slot(date=d, label=lab, week_id=wk.id)
                s.add(sl)
        else:
            sl = Slot(date=d, label="OT", week_id=wk.id)
            s.add(sl)
    s.commit()
    flash("Next week created as draft. You can edit and save without publishing.", "success")
    return redirect(url_for("admin.weeks"))

@bp.post("/weeks/<int:week_id>/save")
def save_week(week_id):
    s = session()
    wk = s.get(Week, week_id)
    if not wk:
        flash("Week not found.", "error")
        return redirect(url_for("admin.weeks"))
    s.commit()
    flash("Changes saved (not published).", "success")
    return redirect(url_for("admin.weeks"))

@bp.post("/weeks/<int:week_id>/publish")
def publish_week(week_id):
    s = session()
    wk = s.get(Week, week_id)
    if not wk:
        flash("Week not found.", "error")
        return redirect(url_for("admin.weeks"))
    wk.status = "published"
    s.commit()
    flash("Week published.", "success")
    return redirect(url_for("admin.weeks"))

@bp.post("/weeks/<int:week_id>/close")
def close_week(week_id):
    s = session()
    wk = s.get(Week, week_id)
    if not wk:
        flash("Week not found.", "error")
        return redirect(url_for("admin.weeks"))
    wk.status = "closed"
    for sl in s.query(Slot).filter(Slot.week_id==wk.id).all():
        sl.is_closed = True
    s.commit()
    flash("Week closed and all slots locked.", "success")
    return redirect(url_for("admin.weeks"))

@bp.route("/roster", methods=["GET","POST"])
def roster():
    s = session()
    if request.method == "POST"]:
        for key, val in request.form.items():
            if key.startswith("shift_type_"):
                emp_id = int(key.split("_", 2)[2])
                e = s.get(Employee, emp_id)
                if e:
                    e.shift_type = val
        s.commit()
        flash("Roster updated.", "success")
        return redirect(url_for("admin.roster"))
    emps = s.query(Employee).order_by(Employee.last_name.asc(), Employee.first_name.asc()).all()
    return render_template("admin_roster.html", employees=emps)
