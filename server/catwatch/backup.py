"""Backup (.zip) dos dados do servidor: gravar e ler de volta.

Formato (o mesmo desde a primeira versão do backup):
  data/catwatch.db            banco (visitas e eventos)
  config.yaml                 câmeras, zonas e configurações (sem o token)
  data/cats/<gato>/<foto>     galeria de cada gato
  data/snapshots/<id>.jpg     foto de cada visita

A leitura não confia no arquivo: só extrai os caminhos acima, recusa nomes que saiam da
pasta, limita o tamanho e confere se o banco é um SQLite íntegro do Catwatch.
"""
import re
import sqlite3
import zipfile
from pathlib import Path, PurePosixPath

import yaml

MAX_TOTAL_BYTES = 8 * 1024**3   # 8 GB descompactados: defesa contra "bomba de zip"
CAT_NAME = re.compile(r"[\w \-]{1,40}")


class BadBackup(ValueError):
    """O arquivo não é um backup do Catwatch utilizável; a mensagem explica para o usuário."""


def write_backup(zpath: Path, db: sqlite3.Connection, config_path, gallery: Path, snapshots: Path, lock=None):
    """Grava o .zip. `lock` (opcional) protege a cópia do banco enquanto o servidor grava."""
    zpath = Path(zpath)
    db_copy = zpath.with_suffix(".db.tmp")
    dst = sqlite3.connect(db_copy)
    if lock:
        with lock:
            db.backup(dst)       # cópia consistente mesmo com o servidor gravando
    else:
        db.backup(dst)
    dst.close()
    try:
        with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
            z.write(db_copy, "data/catwatch.db")
            if config_path and Path(config_path).exists():
                z.write(config_path, "config.yaml")
            for folder, arc in ((Path(gallery), "data/cats"), (Path(snapshots), "data/snapshots")):
                for f in sorted(folder.rglob("*")) if folder.exists() else []:
                    if f.is_file():
                        z.write(f, f"{arc}/{f.relative_to(folder).as_posix()}")
    finally:
        db_copy.unlink(missing_ok=True)


def _target(name: str, out: Path):
    """Onde um membro do .zip vai parar, ou None se não é algo que o backup deveria ter."""
    p = PurePosixPath(name)
    if p.is_absolute() or ".." in p.parts or not p.parts:
        return None
    parts = p.parts
    if parts == ("data", "catwatch.db") or parts == ("config.yaml",):
        return out.joinpath(*parts)
    if len(parts) == 4 and parts[:2] == ("data", "cats") and CAT_NAME.fullmatch(parts[2]) and parts[3] not in (".", ""):
        return out.joinpath(*parts)
    if len(parts) == 3 and parts[:2] == ("data", "snapshots") and re.fullmatch(r"\d+\.jpg", parts[2]):
        return out.joinpath(*parts)
    return None


def read_backup(zpath: Path, out: Path) -> dict:
    """Confere e extrai o backup em `out`. Devolve {db, config, cats, snapshots, counts}."""
    try:
        z = zipfile.ZipFile(zpath)
    except zipfile.BadZipFile:
        raise BadBackup("o arquivo não é um .zip válido") from None
    out.mkdir(parents=True, exist_ok=True)
    with z:
        members = [(m, _target(m.filename, out)) for m in z.infolist() if not m.is_dir()]
        wanted = [(m, t) for m, t in members if t is not None]
        if not any(t.name == "catwatch.db" for _, t in wanted):
            raise BadBackup("o .zip não tem data/catwatch.db; é um backup do Catwatch?")
        if sum(m.file_size for m, _ in wanted) > MAX_TOTAL_BYTES:
            raise BadBackup("o backup é grande demais")
        for m, t in wanted:
            t.parent.mkdir(parents=True, exist_ok=True)
            with z.open(m) as src, open(t, "wb") as dst:
                while chunk := src.read(1 << 20):
                    dst.write(chunk)

    db = out / "data" / "catwatch.db"
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        ok = con.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        visits = con.execute("SELECT COUNT(*) FROM visits").fetchone()[0] if "visits" in tables else 0
        con.close()
    except sqlite3.DatabaseError:
        raise BadBackup("o banco do backup está corrompido") from None
    if not ok or "visits" not in tables:
        raise BadBackup("o banco do backup não é do Catwatch ou está corrompido")

    config = None
    cfg_file = out / "config.yaml"
    if cfg_file.exists():
        try:
            config = yaml.safe_load(cfg_file.read_text(encoding="utf-8")) or {}
        except (yaml.YAMLError, UnicodeDecodeError):
            config = None        # config ilegível: restaura os dados e mantém a configuração atual
        if not isinstance(config, dict):
            config = None

    cats = out / "data" / "cats"
    snaps = out / "data" / "snapshots"
    return {
        "db": db, "config": config,
        "cats": cats if cats.exists() else None,
        "snapshots": snaps if snaps.exists() else None,
        "counts": {
            "visits": visits,
            "cats": len([d for d in cats.iterdir() if d.is_dir()]) if cats.exists() else 0,
            "photos": len([f for f in cats.rglob("*") if f.is_file()]) if cats.exists() else 0,
            "snapshots": len(list(snaps.glob("*.jpg"))) if snaps.exists() else 0,
            "cameras": len((config or {}).get("cameras") or []),
        },
    }
