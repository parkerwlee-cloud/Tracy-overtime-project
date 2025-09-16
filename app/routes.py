# app/routes.py
from datetime import date, timedelta
from flask import render_template, request, jsonify
from .models import session, Week, Slot, Employee
from .utils import monday_of
from .services import assign_slot

def _grid_for_week(week: Week):
    # Build grid structure templates expect: list of days => rows
    rows = []
    by_date = {}
    for sl in week.slots:
        by_date.setdefault(sl.date, []).append(sl)
    grid = []
    for i in range(7):
        d = week.start_date + timedelta(days=i)
        slots = sorted(by_date.get(d, []), key=lambda s: ["First 4","Full 8","Last 4"].index(s.code) if s.code in ["First 4","Full 8","Last 4"] else 99)
        day = {
            "date": d.isoformat(),
            "rows": [{
                "slot_id": s.id,
                "label": s.label,
                "capacity": s.capacity or 0,
                "taken": len(s.signups),
                "disabled": False,
                "state_hint": ""
            } for s in slots]
        }
        grid.append(day)
    return grid

def register_kiosk(app):
    @app.get("/")
    def kiosk():
        s = session()
        try:
            today = date.today()
            start = monday_of(today)
            week = s.query(Week).filter(Week.start_date == start).one_or_none()
            if not week:
                return render_template("kiosk.html", grid=[], roster=[])
            grid = _grid_for_week(week)
            emps = s.query(Employee).order_by(Employee.last_name.asc(), Employee.first_name.asc()).all()
            roster = [{"id": e.id, "name": f"{e.first_name} {e.last_name}", "tag": e.display_tag()} for e in emps]
            return render_template("kiosk.html", grid=grid, roster=roster)
        finally:
            s.close()

    @app.get("/wallboard")
    def wallboard():
        s = session()
        try:
            today = date.today()
            start = monday_of(today)
            week = s.query(Week).filter(Week.start_date == start).one_or_none()
            grid = _grid_for_week(week) if week else []
            return render_template("display.html", grid=grid)
        finally:
            s.close()

    @app.post("/api/signup")
    def api_signup():
        data = request.get_json(force=True) if request.is_json else request.form
        slot_id = int(data.get("slot_id", 0))
        employee_id = int(data.get("employee_id", 0))
        body, code = assign_slot(slot_id, employee_id)
        return jsonify(body), code

    @app.get("/api/roster")
    def api_roster():
        s = session()
        try:
            emps = s.query(Employee).order_by(Employee.last_name.asc(), Employee.first_name.asc()).all()
            return jsonify([{ "id": e.id, "name": f"{e.first_name} {e.last_name}", "tag": e.display_tag()} for e in emps])
        finally:
            s.close()
