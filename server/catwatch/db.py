import sqlite3
import threading

_lock = threading.Lock()


def connect(path: str) -> sqlite3.Connection:
    db = sqlite3.connect(path, check_same_thread=False)
    db.row_factory = sqlite3.Row
    migrate(db)
    return db


def migrate(db: sqlite3.Connection) -> None:
    """Cria o que falta no banco; também roda depois de importar um backup de versão antiga."""
    db.execute("""CREATE TABLE IF NOT EXISTS visits(
        id INTEGER PRIMARY KEY, cat TEXT, kind TEXT, zone TEXT, camera TEXT,
        start REAL, end REAL)""")
    have = {r[1] for r in db.execute("PRAGMA table_info(visits)")}
    for col, typ in (("score", "REAL"), ("conf", "REAL"), ("frames", "INTEGER"), ("votes", "TEXT"),
                     ("photo", "INTEGER DEFAULT 0"), ("presence", "REAL")):
        if col not in have:   # migração de bancos criados antes das fotos
            db.execute(f"ALTER TABLE visits ADD COLUMN {col} {typ}")
    db.execute("CREATE INDEX IF NOT EXISTS ix_visits_start ON visits(start)")
    # Eventos: alimentam o log ao vivo, os alertas e as notificações dos apps.
    db.execute("""CREATE TABLE IF NOT EXISTS events(
        id INTEGER PRIMARY KEY, ts REAL, type TEXT, level TEXT, message TEXT,
        cat TEXT, camera TEXT, visit_id INTEGER, key TEXT)""")
    db.execute("CREATE INDEX IF NOT EXISTS ix_events_ts ON events(ts)")
    db.commit()


def _q(db, sql, args=()):
    with _lock:
        return [dict(r) for r in db.execute(sql, args)]


def _x(db, sql, args=()):
    with _lock:
        cur = db.execute(sql, args)
        db.commit()
        return cur.rowcount


def add_visit(db, cat, kind, zone, camera, start, end, score=None, conf=None, frames=0, votes=None, photo=0,
              presence=None) -> int:
    """presence: segundos em que o gato foi visto de fato (end - start inclui os sumiços)."""
    with _lock:
        cur = db.execute(
            "INSERT INTO visits(cat,kind,zone,camera,start,end,score,conf,frames,votes,photo,presence)"
            " VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
            (cat, kind, zone, camera, start, end, score, conf, frames, votes, photo, presence))
        db.commit()
        return cur.lastrowid


def daily_counts(db, day_start: float, day_end: float):
    return _q(db, """SELECT cat, kind, COUNT(*) n, ROUND(SUM(end-start)) seconds
        FROM visits WHERE start>=? AND start<? GROUP BY cat, kind ORDER BY cat""",
              (day_start, day_end))


def stats(db, since: float):
    return _q(db, """SELECT date(start,'unixepoch','localtime') day, cat, kind, COUNT(*) n
        FROM visits WHERE start>=? GROUP BY day, cat, kind ORDER BY day""", (since,))


def recent(db, limit=50, cat=None, kind=None):
    where, args = [], []
    if cat:
        where.append("cat=?"); args.append(cat)
    if kind:
        where.append("kind=?"); args.append(kind)
    sql = "SELECT * FROM visits" + (" WHERE " + " AND ".join(where) if where else "")
    return _q(db, sql + " ORDER BY start DESC LIMIT ?", (*args, limit))


def set_cat(db, visit_id: int, cat: str) -> int:
    return _x(db, "UPDATE visits SET cat=? WHERE id=?", (cat, visit_id))


def delete_visit(db, visit_id: int) -> int:
    return _x(db, "DELETE FROM visits WHERE id=?", (visit_id,))


# ---------- eventos ----------
def add_event(db, type_: str, message: str, level: str = "info", cat=None, camera=None,
              visit_id=None, key=None, ts=None) -> int:
    import time
    with _lock:
        cur = db.execute(
            "INSERT INTO events(ts,type,level,message,cat,camera,visit_id,key) VALUES(?,?,?,?,?,?,?,?)",
            (ts or time.time(), type_, level, message, cat, camera, visit_id, key))
        db.commit()
        return cur.lastrowid


def events(db, after: int | None = None, limit: int = 100, type_: str | None = None, since: float | None = None):
    """Sem `after`: os últimos `limit` eventos. Com `after`: os mais novos que esse id (para polling)."""
    where, args = [], []
    if after is not None:
        where.append("id>?"); args.append(after)
    if type_:
        where.append("type=?"); args.append(type_)
    if since is not None:
        where.append("ts>=?"); args.append(since)
    sql = "SELECT * FROM events" + (" WHERE " + " AND ".join(where) if where else "")
    if after is not None:
        return _q(db, sql + " ORDER BY id LIMIT ?", (*args, limit))
    return list(reversed(_q(db, sql + " ORDER BY id DESC LIMIT ?", (*args, limit))))


def event_exists(db, key: str, since: float) -> bool:
    return bool(_q(db, "SELECT 1 FROM events WHERE key=? AND ts>=? LIMIT 1", (key, since)))


def prune_events(db, before: float) -> int:
    return _x(db, "DELETE FROM events WHERE ts<?", (before,))


# ---------- consultas para alertas ----------
def count_since(db, cat: str, kind: str, since: float) -> int:
    return _q(db, "SELECT COUNT(*) n FROM visits WHERE cat=? AND kind=? AND start>=?", (cat, kind, since))[0]["n"]


def last_visit(db, cat: str, kind: str):
    r = _q(db, "SELECT MAX(start) t FROM visits WHERE cat=? AND kind=?", (cat, kind))[0]["t"]
    return r


def daily_avg(db, cat: str, kind: str, start: float, end: float):
    """Média diária de visitas no intervalo, contando só dias com algum registro; (média, dias)."""
    r = _q(db, """SELECT COUNT(*) n, COUNT(DISTINCT date(start,'unixepoch','localtime')) d
                  FROM visits WHERE cat=? AND kind=? AND start>=? AND start<?""", (cat, kind, start, end))[0]
    return (r["n"] / r["d"], r["d"]) if r["d"] else (0.0, 0)


def active_days(db, since: float) -> int:
    return _q(db, "SELECT COUNT(DISTINCT date(start,'unixepoch','localtime')) d FROM visits WHERE start>=?", (since,))[0]["d"]


def visits_csv_rows(db):
    return _q(db, "SELECT * FROM visits ORDER BY start")
