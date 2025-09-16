# app/services.py
from datetime import datetime, time, timedelta, date
from flask import current_app
import pytz
from .models import session, Slot, Employee, Signup
from .utils import is_weekend, parse_categories

# Simple priority rules
SHIFT_PRIORITY = {"DAY": 2, "ROTATING": 1}

def _is_weekend_frozen(slot_date: date) -> bool:
    """Example rule: Weekend slots freeze Friday 15:30 local time."""
    if not is_weekend(slot_date):
        return False
    tz = pytz.timezone(current_app.config["TIMEZONE"])
    wkday = slot_date.weekday()
    days_back = (wkday - 4) if wkday >= 5 else 0  # back to Friday
    freeze_dt = tz.localize(datetime.combine(slot_date - timedelta(days=days_back), time(15, 30)))
    return datetime.now(tz) >= freeze_dt

def assign_slot(slot_id: int, employee_id: int):
    s = session()
    try:
        slot = s.get(Slot, slot_id)
        emp = s.get(Employee, employee_id)
        if not slot or not emp:
            return {"error": "Invalid slot or employee"}, 400

        if _is_weekend_frozen(slot.date):
            return {"error": "Weekend slots are frozen"}, 400

        # Capacity check
        if len(slot.signups) >= (slot.capacity or 0):
            return {"error": "Slot is full"}, 400

        # Category gating (if slot has categories, employee must have one)
        slot_cats = set(parse_categories(slot.categories))
        emp_cats = set(parse_categories(emp.categories))
        if slot_cats and not (slot_cats & emp_cats):
            return {"error": "Employee not in required category"}, 400

        # Deduplicate
        exists = s.query(Signup).filter(Signup.slot_id == slot.id, Signup.employee_id == emp.id).one_or_none()
        if exists:
            return {"ok": True, "message": "Already signed up"}, 200

        s.add(Signup(slot_id=slot.id, employee_id=emp.id))
        s.commit()
        return {"ok": True}, 200
    finally:
        s.close()
