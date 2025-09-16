# app/admin_routes.py
from datetime import date, timedelta
from functools import wraps
from flask import render_template, request, redirect, url_for, current_app, session as flask_session, flash
from .models import session, Week, Slot, Employee
from .utils import monday_of, parse_categories, cats_to_str

def _auth_ok():
    return flask_session.get("admin_ok") is True

def _require_login(f):
    @wraps(f)
    def wrapper(*a, **kw):
        if not _auth_ok():
            return redirect(url_for("admin_login"))
        return f(*a, **kw)
    return wrapper

def register_admin(app):
    @app.route("/admin", methods=["GET", "POST"])
    def admin_login():
        if request.method == "POST":
            user = request.form.get("username", "")
            pw = request.form.get("password", "")
            if (user == current_app.config["ADMIN_USERNAME"]
                and pw == current_app.config["ADMIN_PASSWORD"]):
                flask_session["admin_ok"] = True
                return redirect(url_for("admin_panel"))
            flash("Invalid credentials", "error")
        return render_template("admin_login.html")

    @app.get("/admin/logout")
    def admin_logout():
        flask_session.clear()
        return redirect(url_for("admin_login"))

    @app.get("/admin/panel")
    @_require_login
    def admin_panel():
        s = session()
        try:
            today = date.today()
            start = monday_of(today)
            week = s.query(Week).filter(Week.start_date == start).one_or_none()
            rows = []
            cats = set()
            if week:
                for sl in sorted(week.slots, key=lambda x: (x.date, x.code)):
                    rows.append({
                        "id": sl.id,
                        "date": sl.date.isoformat(),
                        "code": sl.code,
                        "capacity": sl.capacity or 0,
                        "cats": parse_categories(sl.categories),
                    })
                    cats.update(parse_categories(sl.categories))
            # Suggested default categories (update as needed)
            all_cats = sorted(cats | {"Weld","Press","Paint","QA","Mill"})
            return render_template("admin_panel.html", rows=rows, categories=all_cats)
        finally:
            s.close()

    @app.post("/admin/slots/<int:slot_id>/capacity")
    @_require_login
    def admin_set_capacity(slot_id: int):
        s = session()
        try:
            sl = s.get(Slot, slot_id)
            if not sl:
                flash("Slot not found", "error")
                return redirect(url_for("admin_panel"))
            cap = int(request.form.get("capacity", sl.capacity or 0))
            sl.capacity = max(0, cap)
            s.commit()
            flash("Capacity updated", "success")
            return redirect(url_for("admin_panel"))
        finally:
            s.close()

    @app.post("/admin/slots/<int:slot_id>/categories")
    @_require_login
    def admin_set_slot_categories(slot_id: int):
        s = session()
        try:
            sl = s.get(Slot, slot_id)
            if not sl:
                flash("Slot not found", "error")
                return redirect(url_for("admin_panel"))
            cats = request.form.getlist("categories")
            sl.categories = cats_to_str(cats)
            s.commit()
            flash("Categories updated", "success")
            return redirect(url_for("admin_panel"))
        finally:
            s.close()

    @app.get("/admin/employees")
    @_require_login
    def admin_employees():
        s = session()
        try:
            emps = s.query(Employee).order_by(Employee.last_name.asc(), Employee.first_name.asc()).all()
            # Suggested master list (align with slot categories)
            categories = ["Weld","Press","Paint","QA","Mill"]
            data = []
            for e in emps:
                data.append({
                    "id": e.id,
                    "name": f"{e.first_name} {e.last_name}",
                    "first_name": e.first_name,
                    "last_name": e.last_name,
                    "clock_number": e.clock_number,
                    "phone": e.phone or "",
                    "cats": parse_categories(e.categories)
                })
            return render_template("employees.html", employees=data, categories=categories)
        finally:
            s.close()

    @app.post("/admin/employees")
    @_require_login
    def admin_emp_create():
        s = session()
        try:
            name = (request.form.get("name") or "").strip()
            parts = name.split()
            first = parts[0] if parts else ""
            last = parts[-1] if len(parts) >= 2 else ""
            clock = (request.form.get("clock_number") or "").strip()
            phone = (request.form.get("phone") or "").strip()
            cats = request.form.getlist("categories")
            if not (first and last and clock):
                flash("Name and 4-digit clock number required", "error")
                return redirect(url_for("admin_employees"))
            if len(clock) != 4 or not clock.isdigit():
                flash("Clock number must be 4 digits", "error")
                return redirect(url_for("admin_employees"))
            e = Employee(first_name=first, last_name=last, clock_number=clock, phone=phone, categories=cats_to_str(cats))
            s.add(e); s.commit()
            flash("Employee added", "success")
            return redirect(url_for("admin_employees"))
        finally:
            s.close()

    @app.post("/admin/employees/<int:emp_id>")
    @_require_login
    def admin_emp_update(emp_id: int):
        s = session()
        try:
            e = s.get(Employee, emp_id)
            if not e:
                flash("Employee not found", "error")
                return redirect(url_for("admin_employees"))
            e.first_name = (request.form.get("first_name") or request.form.get("name","")).split()[0] or e.first_name
            # for convenience, accept "name" field too in table
            if request.form.get("last_name"):
                e.last_name = request.form.get("last_name")
            elif request.form.get("name"):
                parts = request.form["name"].split()
                if len(parts) >= 2:
                    e.last_name = parts[-1]
            clock = (request.form.get("clock_number") or "").strip()
            if clock:
                e.clock_number = clock
            e.phone = (request.form.get("phone") or "").strip()
            e.categories = cats_to_str(request.form.getlist("categories"))
            s.commit()
            flash("Employee updated", "success")
            return redirect(url_for("admin_employees"))
        finally:
            s.close()

    @app.post("/admin/employees/<int:emp_id>/delete")
    @_require_login
    def admin_emp_delete(emp_id: int):
        s = session()
        try:
            e = s.get(Employee, emp_id)
            if not e:
                flash("Employee not found", "error")
                return redirect(url_for("admin_employees"))
            s.delete(e); s.commit()
            flash("Employee deleted", "success")
            return redirect(url_for("admin_employees"))
        finally:
            s.close()
