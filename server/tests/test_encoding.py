"""No Windows, abrir texto sem encoding usa cp1252: acentos do painel e do config.yaml quebram."""
import re
from pathlib import Path

import pytest

from catwatch import config as cfgm

SRC = Path(__file__).resolve().parent.parent / "catwatch"


def test_text_io_always_says_utf8():
    bad = []
    for f in SRC.glob("*.py"):
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if re.search(r"\.(read_text|write_text)\(", line) and "encoding=" not in line:
                bad.append(f"{f.name}:{n}")
    assert bad == []


def test_accented_zone_survives_save_and_load(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    cfg = cfgm.load()
    cfg["cameras"] = [{"name": "cozinha", "source": "push", "zones": [{"name": "água", "kind": "water", "polygon": []}]}]
    cfgm.save(cfg)
    assert "água" in (tmp_path / "config.yaml").read_bytes().decode("utf-8")
    assert cfgm.load()["cameras"][0]["zones"][0]["name"] == "água"
