import sqlite3
import zipfile

import pytest

from catwatch import backup as bk
from catwatch import db as dbm


def make_data(tmp_path):
    db = dbm.connect(str(tmp_path / "catwatch.db"))
    dbm.add_visit(db, "Leona", "water", "bebedouro", "cozinha", 100, 110, presence=9)
    gallery = tmp_path / "cats"
    (gallery / "Leona").mkdir(parents=True)
    (gallery / "Leona" / "1.jpg").write_bytes(b"jpeg")
    snaps = tmp_path / "snapshots"
    snaps.mkdir()
    (snaps / "1.jpg").write_bytes(b"jpeg")
    config = tmp_path / "config.yaml"
    config.write_text("cameras:\n  - {name: cozinha, source: push, zones: []}\n", encoding="utf-8")
    return db, config, gallery, snaps


def test_round_trip(tmp_path):
    db, config, gallery, snaps = make_data(tmp_path)
    z = tmp_path / "b.zip"
    bk.write_backup(z, db, config, gallery, snaps)
    b = bk.read_backup(z, tmp_path / "out")
    assert b["counts"] == {"visits": 1, "cats": 1, "photos": 1, "snapshots": 1, "cameras": 1}
    assert (b["cats"] / "Leona" / "1.jpg").read_bytes() == b"jpeg"
    assert b["config"]["cameras"][0]["name"] == "cozinha"


def test_backup_from_older_version_is_accepted(tmp_path):
    # Banco antigo: só a tabela de visitas, sem as colunas de fotos e presença.
    old = tmp_path / "old.db"
    con = sqlite3.connect(old)
    con.execute("CREATE TABLE visits(id INTEGER PRIMARY KEY, cat TEXT, kind TEXT, zone TEXT, camera TEXT, start REAL, end REAL)")
    con.execute("INSERT INTO visits(cat,kind,zone,camera,start,end) VALUES('Leona','litter','caixa','c',1,2)")
    con.commit(); con.close()
    z = tmp_path / "b.zip"
    with zipfile.ZipFile(z, "w") as zf:
        zf.write(old, "data/catwatch.db")
    b = bk.read_backup(z, tmp_path / "out")
    assert b["counts"]["visits"] == 1 and b["config"] is None and b["cats"] is None
    # A migração completa o banco importado.
    con = sqlite3.connect(b["db"])
    dbm.migrate(con)
    assert "presence" in {r[1] for r in con.execute("PRAGMA table_info(visits)")}


def test_paths_outside_the_backup_are_never_written(tmp_path):
    db, config, gallery, snaps = make_data(tmp_path)
    z = tmp_path / "b.zip"
    bk.write_backup(z, db, config, gallery, snaps)
    with zipfile.ZipFile(z, "a") as zf:
        zf.writestr("../../fora.txt", "x")
        zf.writestr("/etc/fora.txt", "x")
        zf.writestr("data/cats/../../../fora.txt", "x")
        zf.writestr("data/cats/nome;rm -rf/1.jpg", "x")    # nome de gato inválido
        zf.writestr("qualquer/outra/coisa.exe", "x")
    out = tmp_path / "out"
    b = bk.read_backup(z, out)
    written = {p.relative_to(out).as_posix() for p in out.rglob("*") if p.is_file()}
    assert written == {"data/catwatch.db", "config.yaml", "data/cats/Leona/1.jpg", "data/snapshots/1.jpg"}
    assert not (tmp_path / "fora.txt").exists() and b["counts"]["cats"] == 1


def test_zip_without_database_is_refused(tmp_path):
    z = tmp_path / "b.zip"
    with zipfile.ZipFile(z, "w") as zf:
        zf.writestr("data/cats/Leona/1.jpg", "x")
    with pytest.raises(bk.BadBackup, match="catwatch.db"):
        bk.read_backup(z, tmp_path / "out")


def test_corrupt_database_and_not_a_zip_are_refused(tmp_path):
    z = tmp_path / "b.zip"
    with zipfile.ZipFile(z, "w") as zf:
        zf.writestr("data/catwatch.db", "isto não é um banco")
    with pytest.raises(bk.BadBackup, match="corrompido"):
        bk.read_backup(z, tmp_path / "out")
    other = tmp_path / "foto.jpg"
    other.write_bytes(b"\xff\xd8 jpeg")
    with pytest.raises(bk.BadBackup, match="zip"):
        bk.read_backup(other, tmp_path / "out2")
