# app/utils.py
from datetime import datetime, timedelta, date
import pytz, pathlib

def load_version():
    try:
        return pathlib.Path(__file__).resolve().parents[1].joinpath("VERSION").read_text().strip()
    except Exception:
        return "0.0.0"

def tz_now(tzname: str):
    tz = pytz.timezone(tzname)
    return datetime.now(tz)

def monday_of(d: date):
    return d - timedelta(days=d.weekday())

def is_weekend(d: date):
    return d.weekday() >= 5

def parse_categories(val: str) -> list[str]:
    return [x.strip() for x in (val or "").split(",") if x.strip()]

def cats_to_str(items) -> str:
    return ",".join(sorted(set([x.strip() for x in items if x.strip()])))
