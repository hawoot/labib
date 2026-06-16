"""Database connection plumbing (SQLAlchemy)."""
from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import get_settings

_url = get_settings().sqlalchemy_url
# SQLite needs this flag when used across FastAPI's threadpool; Postgres ignores it.
_connect_args = {"check_same_thread": False} if _url.startswith("sqlite") else {}
engine = create_engine(_url, pool_pre_ping=True, connect_args=_connect_args)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)

if _url.startswith("sqlite"):
    @event.listens_for(engine, "connect")
    def _sqlite_pragmas(dbapi_conn, _record):
        # WAL lets the API read while the crunch worker writes; busy_timeout
        # makes brief lock contention wait instead of erroring.
        cur = dbapi_conn.cursor()
        cur.execute("PRAGMA journal_mode=WAL")
        cur.execute("PRAGMA busy_timeout=5000")
        cur.close()


class Base(DeclarativeBase):
    """Base class all ORM models will inherit from (used later)."""


def get_db() -> Session:
    """FastAPI dependency: hands a DB session to a request, closes it after."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
