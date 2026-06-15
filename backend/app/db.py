"""Database connection plumbing (SQLAlchemy)."""
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import get_settings

engine = create_engine(get_settings().database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    """Base class all ORM models will inherit from (used later)."""


def get_db() -> Session:
    """FastAPI dependency: hands a DB session to a request, closes it after."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
