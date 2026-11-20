import time
from datetime import datetime
from types import SimpleNamespace

import pytest

from catwatch import config as cfgm
from catwatch import db as dbm
from catwatch.monitor import Monitor


@pytest.fixture
def cfg(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    return cfgm.load()


def test_first_load_writes_defaults_and_token(cfg, tmp_path):
    assert (tmp_path / "config.yaml").exists()
    assert len(cfg["server"]["token"]) > 10
    assert "token" not in (tmp_path / "config.yaml").read_text()


def test_settings_validation_and_restart_flag(cfg):
    errors, restart = cfgm.apply_settings(cfg, {"detection": {"fps": 99}})
    assert errors and cfg["detection"]["fps"] == 3          # nada aplicado quando há erro
    errors, restart = cfgm.apply_settings(cfg, {"detection": {"fps": "5", "device": "cpu"}, "visits": {"gap_litter": 45}})
    assert not errors and restart                            # trocar o device exige reiniciar
    assert cfg["detection"]["fps"] == 5 and isinstance(cfg["detection"]["fps"], int)
    errors, _ = cfgm.apply_settings(cfg, {"cameras": {"x": 1}})
    assert errors                                            # só campos conhecidos


def test_regenerate_token(cfg):
    old = cfg["server"]["token"]
    new = cfgm.regenerate_token(cfg)
    assert new != old and cfgm.token_path(cfg).read_text() == new


class FakeCam:
    def __init__(self, online, ts=0.0):
        self.online, self.ts = online, ts


def make_monitor(cfg, cams, tmp_path):
    (tmp_path / "data/cats/Leona").mkdir(parents=True, exist_ok=True)
    pipe = SimpleNamespace(db=dbm.connect(cfg["db"]), cams=cams)
    return Monitor(cfg, pipe), pipe


def at(hour):
    return datetime.now().replace(hour=hour, minute=0, second=0, microsecond=0).timestamp()


def test_water_alert_once_per_day(cfg, tmp_path):
    cfg["cameras"] = [{"name": "cozinha", "source": "push", "zones": [{"name": "b", "kind": "water", "polygon": []}]}]
    mon, pipe = make_monitor(cfg, {"cozinha": FakeCam(True)}, tmp_path)
    dbm.add_visit(pipe.db, "Leona", "food", "c", "cozinha", at(8) - 86400, at(8) - 86400 + 10)  # tem histórico
    mon.check_cats(at(10))
    assert dbm.events(pipe.db, type_="alert") == []                  # antes das 18h, não avisa
    mon.check_cats(at(19))
    mon.check_cats(at(20))
    alerts = dbm.events(pipe.db, type_="alert")
    assert [a["message"] for a in alerts] == ["Leona ainda não bebeu água hoje"]


def test_no_alert_when_camera_offline_or_cat_has_no_history(cfg, tmp_path):
    cfg["cameras"] = [{"name": "cozinha", "source": "push", "zones": [{"name": "b", "kind": "water", "polygon": []}]}]
    mon, pipe = make_monitor(cfg, {"cozinha": FakeCam(False)}, tmp_path)
    dbm.add_visit(pipe.db, "Leona", "food", "c", "cozinha", at(8) - 86400, at(8) - 86400 + 10)
    mon.check_cats(at(19))                                           # câmera fora: não dá pra afirmar
    mon.pipe.cams["cozinha"].online = True
    pipe.db.execute("DELETE FROM visits")
    mon.check_cats(at(19))                                           # gato sem histórico: recém-cadastrado
    assert dbm.events(pipe.db, type_="alert") == []


def test_litter_spike(cfg, tmp_path):
    cfg["cameras"] = [{"name": "cx", "source": "push", "zones": [{"name": "c", "kind": "litter", "polygon": []}]}]
    mon, pipe = make_monitor(cfg, {"cx": FakeCam(True)}, tmp_path)
    for d in range(1, 5):                                            # 2 por dia nos últimos 4 dias
        for h in (8, 16):
            t = at(h) - d * 86400
            dbm.add_visit(pipe.db, "Leona", "litter", "c", "cx", t, t + 30)
    for h in range(1, 7):                                            # 6 hoje
        dbm.add_visit(pipe.db, "Leona", "litter", "c", "cx", at(h), at(h) + 30)
    mon.check_cats(at(7))
    msgs = [a["message"] for a in dbm.events(pipe.db, type_="alert")]
    assert len(msgs) == 1 and "6 vezes" in msgs[0]


def test_camera_offline_then_back(cfg, tmp_path):
    cam = FakeCam(False)
    mon, pipe = make_monitor(cfg, {"cx": cam}, tmp_path)
    now = time.time()
    mon.started = now - 10
    mon.check_cameras(now)
    assert dbm.events(pipe.db, type_="camera_offline") == []        # ainda dentro dos 3 min
    mon.check_cameras(now + 200)
    mon.check_cameras(now + 400)                                     # não repete
    assert len(dbm.events(pipe.db, type_="camera_offline")) == 1
    cam.online = True
    mon.check_cameras(now + 500)
    assert len(dbm.events(pipe.db, type_="camera_online")) == 1


def test_old_single_rule_is_replaced_per_kind(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "config.yaml").write_text("visits:\n  min_seconds: 3\n  gap_seconds: 10\n")
    cfg = cfgm.load()
    assert "min_seconds" not in cfg["visits"] and cfg["visits"]["min_litter"] == 15
    assert "min_seconds" not in (tmp_path / "config.yaml").read_text()
    mins, gaps = cfgm.visit_rules(cfg)
    assert mins == {"litter": 15, "food": 8, "water": 5} and gaps["litter"] == 30
