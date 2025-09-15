from datetime import date, timedelta
from flask import Blueprint, render_template, request, jsonify
from .models import session, Week, Slot, Employee
from .utils import monday_of
from .services import assign_slot

bp = Blueprint("kiosk", __name__)

def get_current_and_next_weeks():
    s = session()
    today = date.today()
    cur_start = monday_of(today)
    cur_end = cur_start + timedelta(days=6)
    cur_week = s.query(Week).filter(Week.start_date==cur_start).one_or_none()
    if not cur_week:
        cur_week = Week(start_date=cur_start, end_date=cur_end, status="published")
        s.add(cur_week); s.commit()
    nxt_start = cur_start + timedelta(days=7)
    nxt_week = s.query(Week).filter(Week.start_date==nxt_start).one_or_none()
    return cur_week, nxt_week

@bp.route("/")
def kiosk():
    cur_week, nxt_week = get_current_and_next_weeks()
    s = session()
    cur_slots = s.query(Slot).filter(Slot.week_id==cur_week.id).all()
    nxt_slots = []
    if nxt_week and nxt_week.status == "published":
        nxt_slots = s.query(Slot).filter(Slot.week_id==nxt_week.id).all()
    employees = s.query(Employee).all()
    return render_template("kiosk.html", cur_week=cur_week, nxt_week=nxt_week, cur_slots=cur_slots, nxt_slots=nxt_slots, employees=employees)

@bp.route("/wallboard")
def wallboard():
    cur_week, nxt_week = get_current_and_next_weeks()
    s = session()
    cur_slots = s.query(Slot).filter(Slot.week_id==cur_week.id).all()
    nxt_slots = []
    if nxt_week:
        nxt_slots = s.query(Slot).filter(Slot.week_id==nxt_week.id).all()
    return render_template("wallboard.html", cur_week=cur_week, nxt_week=nxt_week, cur_slots=cur_slots, nxt_slots=nxt_slots)

@bp.post("/api/signup")
def api_signup():
    data = request.get_json(force=True)
    slot_id = int(data.get("slot_id", 0))
    employee_id = int(data.get("employee_id", 0))
    body, code = assign_slot(slot_id, employee_id)
    return jsonify(body), code

@bp.get("/api/roster")
def api_roster():
    s = session()
    emps = s.query(Employee).order_by(Employee.last_name.asc(), Employee.first_name.asc()).all()
    return jsonify([{ "id": e.id, "name": f"{e.first_name} {e.last_name}", "tag": e.display_tag()} for e in emps])
