"""Database connection plumbing (SQLAlchemy)."""
import logging

from sqlalchemy import create_engine, event, inspect, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import get_settings

log = logging.getLogger("labib.db")

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


def ensure_columns() -> None:
    """Poor-man's migration: add any model columns missing from existing tables.

    `create_all` creates missing *tables* but never ALTERs an existing one, so
    adding a column to a model would otherwise 500 every query against that
    table on an already-deployed database (the column is in the SELECT but not
    in the table). This adds each missing column — nullable, with the model's
    scalar default — for SQLite and Postgres. Best-effort: a failure on one
    column never blocks startup. Real migrations (Alembic) replace this once the
    schema stabilises.
    """
    insp = inspect(engine)
    for table in Base.metadata.sorted_tables:
        if not insp.has_table(table.name):
            continue  # create_all will make brand-new tables
        existing = {c["name"] for c in insp.get_columns(table.name)}
        for col in table.columns:
            if col.name in existing:
                continue
            coltype = col.type.compile(dialect=engine.dialect)
            default_sql = ""
            d = getattr(col.default, "arg", None) if col.default is not None else None
            if d is not None and not callable(d):
                if isinstance(d, bool):
                    default_sql = f" DEFAULT {1 if d else 0}"
                elif isinstance(d, (int, float)):
                    default_sql = f" DEFAULT {d}"
                elif isinstance(d, str):
                    default_sql = " DEFAULT '" + d.replace("'", "''") + "'"
            ddl = (
                f"ALTER TABLE {table.name} ADD COLUMN {col.name} "
                f"{coltype}{default_sql}"
            )
            try:
                with engine.begin() as conn:
                    conn.execute(text(ddl))
                log.warning("ensure_columns: added %s.%s", table.name, col.name)
            except Exception as e:  # noqa: BLE001 - best effort
                log.warning("ensure_columns: could not add %s.%s: %s",
                            table.name, col.name, e)


def get_db() -> Session:
    """FastAPI dependency: hands a DB session to a request, closes it after."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
