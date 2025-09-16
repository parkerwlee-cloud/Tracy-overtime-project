# app/models.py
from datetime import date, datetime, timedelta
from sqlalchemy import create_engine, Column, Integer, String, Date, ForeignKey, DateTime
from sqlalchemy.orm import declarative_base, relationship, sessionmaker, scoped_session

Base = declarative_base()
SessionLocal = scoped_session(sessionmaker())

class Week(Base):
    __tablename__ = "weeks"
    id = Column(Integer, primary_key=True)
    start_date = Column(Date, nullable=False, unique=True)  # Monday
    end_date = Column(Date, nullable=False)                 # Sunday
    status = Column(String, default="published")            # draft|published|closed
    slots = relationship("Slot", back_populates="week", cascade="all, delete-orphan")

class Slot(Base):
    __tablename__ = "slots"
    id = Column(Integer, primary_key=True)
    week_id = Column(Integer, ForeignKey("weeks.id"), nullable=False)
    date = Column(Date, nullable=False)
    code = Column(String, nullable=False)   # "First 4" | "Full 8" | "Last 4"
    label = Column(String, nullable=False)
    capacity = Column(Integer, default=0)
    categories = Column(String, default="")  # comma-separated
    signups = relationship("Signup", back_populates="slot", cascade="all, delete-orphan")
    week = relationship("Week", back_populates="slots")

class Employee(Base):
    __tablename__ = "employees"
    id = Column(Integer, primary_key=True)
    first_name = Column(String, nullable=False)
    last_name = Column(String, nullable=False)
    clock_number = Column(String, nullable=False, unique=True)  # 4 digits
    phone = Column(String, nullable=True)
    categories = Column(String, default="")  # comma-separated
    shift_type = Column(String, default="DAY")     # DAY | ROTATING
    seniority_rank = Column(Integer, default=0)

    def display_tag(self):
        fi = (self.first_name[:1].upper() + ".") if self.first_name else ""
        return f"{fi} {self.last_name} - {self.clock_number}"

class Signup(Base):
    __tablename__ = "signups"
    id = Column(Integer, primary_key=True)
    slot_id = Column(Integer, ForeignKey("slots.id"), nullable=False)
    employee_id = Column(Integer, ForeignKey("employees.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    slot = relationship("Slot", back_populates="signups")

def get_engine(db_url: str):
    if db_url.startswith("sqlite:///"):
        path = db_url.replace("sqlite:///", "")
        return create_engine(
            f"sqlite:///{path}",
            echo=False, future=True,
            connect_args={"check_same_thread": False}
        )
    return create_engine(db_url, echo=False, future=True)

def init_db(app):
    engine = get_engine(app.config["DATABASE_URL"])
    SessionLocal.configure(bind=engine)
    Base.metadata.create_all(engine)

    # Seed this week if missing
    s = SessionLocal()
    try:
        today = date.today()
        monday = today - timedelta(days=today.weekday())
        sunday = monday + timedelta(days=6)
        wk = s.query(Week).filter(Week.start_date == monday).one_or_none()
        if not wk:
            wk = Week(start_date=monday, end_date=sunday, status="published")
            s.add(wk); s.flush()
            labels = ["First 4", "Full 8", "Last 4"]
            for i in range(7):
                d = monday + timedelta(days=i)
                for lab in labels:
                    s.add(Slot(week_id=wk.id, date=d, code=lab, label=lab))
            s.commit()
    finally:
        s.close()

def session():
    return SessionLocal()
