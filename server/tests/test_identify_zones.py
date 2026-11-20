import threading

import numpy as np

from catwatch import overlay
from catwatch.vision import UNKNOWN, CatIdentifier, pick
from catwatch.visits import VisitTracker
from catwatch.zones import ZoneMap

W, H = 640, 480


def rect(name, kind, x1, y1, x2, y2):
    return {"name": name, "kind": kind, "polygon": [[x1, y1], [x2, y1], [x2, y2], [x1, y2]]}


# ---------- zona do gato ----------

def test_feet_inside_zone():
    z = [rect("caixa", "litter", 0.2, 0.5, 0.8, 1.0)]
    assert ZoneMap().zone_for((200, 200, 300, 400), z, W, H)["name"] == "caixa"   # pés em y=400 (0,83)


def test_seen_from_above_counts_by_coverage():
    # Câmera de cima: o gato está dentro da caixa, mas a base da caixa dele passa da borda do polígono.
    z = [rect("caixa", "litter", 0.3, 0.3, 0.7, 0.7)]
    box = (220, 180, 420, 360)                       # pés em y=360 (0,75): fora; corpo quase todo dentro
    assert ZoneMap().zone_for(box, z, W, H)["name"] == "caixa"


def test_barely_touching_does_not_count():
    z = [rect("caixa", "litter", 0.3, 0.3, 0.7, 0.7)]
    box = (420, 300, 600, 470)                       # só uma quina encosta na zona
    assert ZoneMap().zone_for(box, z, W, H) is None


def test_one_zone_per_cat_when_food_and_water_are_side_by_side():
    zones = [rect("comedouro", "food", 0.1, 0.5, 0.5, 1.0), rect("bebedouro", "water", 0.5, 0.5, 0.9, 1.0)]
    box = (250, 260, 350, 450)                       # pés em x=300 (0,47): no comedouro, corpo nos dois
    got = ZoneMap().zone_for(box, zones, W, H)
    assert got["name"] == "comedouro"


def test_zone_masks_follow_edited_zones():
    zm = ZoneMap()
    z1 = [rect("a", "food", 0.0, 0.0, 0.5, 1.0)]
    z2 = [rect("a", "food", 0.5, 0.0, 1.0, 1.0)]
    box = (400, 100, 500, 400)
    assert zm.zone_for(box, z1, W, H) is None
    assert zm.zone_for(box, z2, W, H)["name"] == "a"   # zona redesenhada: máscara refeita


# ---------- quem é o gato ----------

def test_pick_needs_threshold_and_margin():
    names = ["Leona", "Sushi"]
    assert pick(names, np.array([0.90, 0.70]), 0.7) == ("Leona", 0.90)
    assert pick(names, np.array([0.65, 0.60]), 0.7) == (UNKNOWN, 0.65)        # abaixo do limite
    assert pick(names, np.array([0.81, 0.80]), 0.7) == (UNKNOWN, 0.81)        # empate técnico


def test_pick_is_fair_to_cats_with_few_photos():
    # Leona tem muitas fotos (só uma muito parecida); Sushi tem uma foto, menos parecida.
    names = ["Leona"] * 5 + ["Sushi"]
    sims = np.array([0.95, 0.60, 0.58, 0.55, 0.50, 0.85])
    assert pick(names, sims, 0.7)[0] == "Leona"   # a média das 3 melhores dava Sushi


def test_pick_with_empty_gallery():
    assert pick([], np.array([]), 0.7) == (UNKNOWN, 0.0)


def test_prepare_keeps_the_whole_cat():
    lying = np.zeros((60, 300, 3), np.uint8)
    lying[:, :20] = 255                              # "cabeça" na ponta esquerda
    x = CatIdentifier.prepare(lying)
    assert x.shape == (3, 224, 224)
    # A ponta esquerda continua na imagem (o recorte central a cortava fora).
    assert x[0, 112, 2] > x[0, 112, 150]


# ---------- várias câmeras ao mesmo tempo ----------

def test_tracker_survives_many_cameras_at_once():
    t = VisitTracker(min_seconds=1, gap_seconds=2)
    errors = []

    def camera(name):
        try:
            for i in range(3000):
                t.update(name, "z", "Leona", i * 0.3, "water")
                t.flush(i * 0.3 + (5 if i % 50 == 0 else 0))
        except Exception as e:  # noqa: BLE001
            errors.append(e)

    threads = [threading.Thread(target=camera, args=(f"cam{i}",)) for i in range(4)]
    [th.start() for th in threads]
    [th.join() for th in threads]
    assert errors == []


# ---------- desenho ----------

def test_overlay_draws_zones_and_labels():
    frame = np.full((H, W, 3), 90, np.uint8)
    zones = [rect("bebedouro", "water", 0.5, 0.5, 0.9, 0.9), rect("comedouro", "food", 0.1, 0.5, 0.4, 0.9)]
    overlay.draw(frame, zones, {"bebedouro"}, [((340, 250, 520, 420), "Leona", 0.91, True)], "cozinha  20/11/2026 14:00")
    water = np.array(overlay.KIND_RGB["water"][::-1], float)
    # Zona com gato fica mais tingida que a vazia.
    def tint(x, y, ref):
        return np.linalg.norm(frame[y, x].astype(float) - ref)
    gray = np.array([90, 90, 90], float)
    assert tint(560, 400, gray) > tint(150, 400, gray)
    assert np.linalg.norm(frame[290, 342].astype(float) - water) > 0   # contorno/caixa desenhados
