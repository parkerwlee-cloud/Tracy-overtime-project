from datetime import datetime
from sqlalchemy import create_engine, Column, Integer, String, Date, ForeignKey, DateTime, Boolean
from sqlalchemy.orm import declarative_base, relationship, sessionmaker, scoped_session

Base = declarative_base()
SessionLocal = scoped_session(sessionmaker())

def get_engine(db_url):
    if db_url.startswith("sqlite:///"):
        path = db_url.replace("sqlite:///", "")
        connect_args = {"check_same_thread": False}
        return create_engine(f"sqlite:///{path}", echo=False, future=True, connect_args=connect_args)
    return create_engine(db_url, echo=False, future=True)

def init_db(app):
    engine = get_engine(app.config["DATABASE_URL"])
    SessionLocal.configure(bind=engine)
    Base.metadata.create_all(engine)

class Week(Base):
    __tablename__ = "weeks"
    id = Column(Integer, primary_key=True)
    start_date = Column(Date, nullable=False)
    end_date = Column(Date, nullable=False)
    status = Column(String, nullable=False, default="draft")  # draft|published|closed
    created_at = Column(DateTime, default=datetime.utcnow)
    slots = relationship("Slot", back_populates="week")

class Employee(Base):
    __tablename__ = "employees"
    id = Column(Integer, primary_key=True)
    first_name = Column(String, nullable=False)
    last_name = Column(String, nullable=False)
    clock_number = Column(String, nullable=True)
    seniority_rank = Column(Integer, default=0)  # smaller = more senior
    shift_type = Column(String, nullable=False, default="ROTATING")  # DAY|ROTATING
    phone = Column(String, nullable=True)
    updated_at = Column(DateTime, default=datetime.utcnow)

    def display_tag(self):
        initial = (self.first_name or "")[:1].upper()
        return f"{initial}. {self.last_name} - {self.clock_number or '----'}"

class Slot(Base):
    __tablename__ = "slots"
    id = Column(Integer, primary_key=True)
    date = Column(Date, nullable=False)
    label = Column(String, nullable=False)  # e.g., "First 4" | "Full 8" | "Last 4" | "OT"
    is_closed = Column(Boolean, default=False)
    week_id = Column(Integer, ForeignKey("weeks.id"), nullable=True)
    assigned_employee_id = Column(Integer, ForeignKey("employees.id"), nullable=True)

    week = relationship("Week", back_populates="slots")
    assigned_employee = relationship("Employee")
    signups = relationship("Signup", back_populates="slot")

class Signup(Base):
    __tablename__ = "signups"
    id = Column(Integer, primary_key=True)
    slot_id = Column(Integer, ForeignKey("slots.id"), nullable=False)
    employee_id = Column(Integer, ForeignKey("employees.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    slot = relationship("Slot", back_populates="signups")
    employee = relationship("Employee")


def session():
    return SessionLocal()
