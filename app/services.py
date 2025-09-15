from datetime import datetime, time, timedelta, date
from flask import current_app
import pytz
from .models import session, Slot, Employee, Signup
from .utils import tz_now, is_weekend

SHIFT_PRIORITY = {"DAY": 2, "ROTATING": 1}

def is_weekend_frozen(slot_date: date) -> bool:
    tz = pytz.timezone(current_app.config["TIMEZONE"])
    if not is_weekend(slot_date):
        return False
    weekday = slot_date.weekday()
    days_back = (weekday - 4) if weekday >= 5 else 0
    friday = slot_date - timedelta(days=days_back)
    freeze_dt = tz.localize(datetime.combine(friday, time(15, 30)))
    return tz_now(current_app.config["TIMEZONE"]) >= freeze_dt

def notify_sms(to_number: str, body: str):
    if not current_app.config.get("TWILIO_ENABLED", False):
        current_app.logger.info(f"[SMS disabled] To {to_number}: {body}")
        return
    from twilio.rest import Client
    sid = current_app.config["TWILIO_ACCOUNT_SID"]
    token = current_app.config["TWILIO_AUTH_TOKEN"]
    from_num = current_app.config["TWILIO_FROM_NUMBER"]
    client = Client(sid, token)
    try:
        client.messages.create(to=to_number, from_=from_num, body=body)
    except Exception as e:
        current_app.logger.error(f"Twilio send error: {e}")

def record_signup(slot_id: int, employee_id: int):
    s = session()
    su = Signup(slot_id=slot_id, employee_id=employee_id)
    s.add(su)
    s.commit()
    return su

def assign_slot(slot_id: int, employee_id: int):
    s = session()
    slot = s.get(Slot, slot_id)
    if not slot:
        return {"error": "Slot not found"}, 404
    week = slot.week
    if not week or week.status != "published":
        return {"error": "Week not published"}, 400
    if slot.is_closed:
        return {"error": "Slot closed"}, 400
    if is_weekend_frozen(slot.date):
        return {"error": "Weekend signups closed at 15:30 Fri"}, 400

    new_emp = s.get(Employee, employee_id)
    if not new_emp:
        return {"error": "Employee not found"}, 400

    record_signup(slot.id, new_emp.id)

    cur_emp = slot.assigned_employee
    if cur_emp is None:
        slot.assigned_employee = new_emp
        s.commit()
        _notify_assignment(new_emp, slot, was_bump=False, bumped=None)
        return {"assigned_to": _emp_dict(new_emp), "was_bump": False}, 200

    # 1) Shift priority
    new_p = SHIFT_PRIORITY.get(new_emp.shift_type, 1)
    cur_p = SHIFT_PRIORITY.get(cur_emp.shift_type, 1)
    if new_p > cur_p:
        bumped = cur_emp
        slot.assigned_employee = new_emp
        s.commit()
        _notify_assignment(new_emp, slot, was_bump=True, bumped=bumped)
        return {"assigned_to": _emp_dict(new_emp), "was_bump": True, "bumped_employee": _emp_dict(bumped)}, 200
    if new_p < cur_p:
        return {"error": "Higher-priority employee already holds this slot"}, 400

    # 2) Seniority (smaller rank value = more senior)
    if (new_emp.seniority_rank or 0) < (cur_emp.seniority_rank or 0):
        bumped = cur_emp
        slot.assigned_employee = new_emp
        s.commit()
        _notify_assignment(new_emp, slot, was_bump=True, bumped=bumped)
        return {"assigned_to": _emp_dict(new_emp), "was_bump": True, "bumped_employee": _emp_dict(bumped)}, 200
    if (new_emp.seniority_rank or 0) > (cur_emp.seniority_rank or 0):
        return {"error": "More-senior employee already holds this slot"}, 400

    # 3) Signup timestamp: current holder is earlier
    return {"error": "Slot already held by same-priority employee"}, 400

def _emp_dict(emp: Employee):
    return {"id": emp.id, "first_name": emp.first_name, "last_name": emp.last_name, "clock_number": emp.clock_number, "shift_type": emp.shift_type}

def _notify_assignment(new_emp: Employee, slot: Slot, was_bump: bool, bumped: Employee | None):
    if new_emp.phone:
        notify_sms(new_emp.phone, f"You are assigned to {slot.label} on {slot.date.isoformat()}.")
    if was_bump and bumped and bumped.phone:
        notify_sms(bumped.phone, f"You were bumped from {slot.label} on {slot.date.isoformat()}.")
