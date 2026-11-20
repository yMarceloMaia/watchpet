from catwatch.visits import VisitTracker, point_in_polygon, presence_seconds

SQ = [[0, 0], [1, 0], [1, 1], [0, 1]]
FPS = 3


def frames(t0, seconds, fps=FPS):
    """Instantes dos quadros analisados num trecho contínuo."""
    return [t0 + i / fps for i in range(int(seconds * fps) + 1)]


def see(t, cat, times, kind="water", zone="z", **kw):
    for now in times:
        t.update("cam", zone, cat, now, kind, **kw)


def test_polygon():
    assert point_in_polygon(.5, .5, SQ)
    assert not point_in_polygon(1.5, .5, SQ)


def test_presence_ignores_long_holes():
    assert presence_seconds([0, 1, 2, 10, 11]) == 3   # o buraco de 8 s não conta


def test_quick_pass_is_not_a_visit():
    t = VisitTracker()
    see(t, "Leona", frames(100, 3), kind="water")        # 3 s perto do pote: só passou
    assert t.flush(200) == []


def test_drinking_counts_but_same_time_at_litter_does_not():
    t = VisitTracker()
    see(t, "Leona", frames(100, 7), kind="water", zone="agua")
    see(t, "Leona", frames(100, 7), kind="litter", zone="caixa")
    out = t.flush(500)
    assert [(v["zone"], v["cat"]) for v in out] == [("agua", "Leona")]  # caixa exige 15 s
    assert 6.9 < out[0]["presence"] <= 7


def test_two_sightings_far_apart_do_not_add_up():
    t = VisitTracker()
    see(t, "Leona", frames(100, 3), kind="food")
    see(t, "Leona", frames(110, 3), kind="food")          # voltou 7 s depois, ainda dentro da visita
    out = t.flush(500)
    assert out == []                                       # 6 s de presença < 8 s, mesmo com 13 s entre início e fim


def test_crouching_in_litter_box_keeps_one_visit():
    t = VisitTracker()
    see(t, "Leona", frames(100, 10), kind="litter")
    # agachada, a detecção some por 20 s (menos que os 30 s de tolerância da caixa)
    see(t, "Leona", frames(130, 10), kind="litter")
    assert t.flush(161) == []                              # 21 s sem vê-la: ainda aberta (a caixa tolera 30 s)
    out = t.flush(171)
    assert len(out) == 1 and 19.9 < out[0]["presence"] <= 20 and out[0]["end"] - out[0]["start"] == 40


def test_unknown_frames_belong_to_the_leader():
    t = VisitTracker()
    times = frames(100, 9)
    for i, now in enumerate(times):                        # a identificação falha em 2 de cada 3 quadros
        t.update("cam", "z", "Leona" if i % 3 == 0 else None, now, "food")
    out = t.flush(500)
    assert [v["cat"] for v in out] == ["Leona"] and out[0]["presence"] > 8


def test_rare_wrong_name_is_absorbed():
    t = VisitTracker()
    times = frames(100, 9)
    for i, now in enumerate(times):                        # 1 em cada 10 quadros diz Sushi: erro de identificação
        t.update("cam", "z", "Sushi" if i % 10 == 5 else "Leona", now, "food")
    out = t.flush(500)
    assert [v["cat"] for v in out] == ["Leona"]
    assert out[0]["votes"]["Sushi"] > 0                    # os votos continuam visíveis no histórico


def test_two_cats_together_are_counted_separately():
    t = VisitTracker()
    for now in frames(100, 10):                            # os dois comem lado a lado, na mesma imagem
        t.update("cam", "z", "Leona", now, "food")
        t.update("cam", "z", "Sushi", now, "food")
    out = t.flush(500)
    assert sorted(v["cat"] for v in out) == ["Leona", "Sushi"]


def test_two_cats_one_after_another():
    t = VisitTracker()
    see(t, "Leona", frames(100, 9), kind="food")
    see(t, "Sushi", frames(112, 2), kind="food")           # Sushi só cheirou
    out = t.flush(500)
    assert [v["cat"] for v in out] == ["Leona"]


def test_keeps_best_frame_and_scores():
    t = VisitTracker(min_seconds=3, gap_seconds=10)
    t.update("cam", "caixa", "mimi", 100, "litter", 0.60, "frame-a", 0.9)
    t.update("cam", "caixa", "mimi", 101, "litter", 0.85, "frame-b", 0.5)
    t.update("cam", "caixa", "bolt", 102, "litter", 0.99, "frame-c", 0.5)  # 1 de 5 quadros: erro, vai para mimi
    t.update("cam", "caixa", "mimi", 103, "litter", 0.70, "frame-d", 0.6)
    t.update("cam", "caixa", "mimi", 104, "litter", 0.70, "frame-e", 0.6)
    v = t.flush(200)[0]
    assert v["cat"] == "mimi" and v["frames"] == 5
    assert v["votes"] == {"mimi": 4, "bolt": 1}
    assert abs(v["score"] - (0.60 + 0.85 + 0.99 + 0.70 + 0.70) / 5) < 1e-9
    assert v["frame"] == "frame-c"                         # melhor evidência da visita
    assert v["conf"] == 0.9


def test_numbers_apply_to_every_kind():
    t = VisitTracker(min_seconds=3, gap_seconds=10)
    assert t.min_seconds == {"litter": 3, "food": 3, "water": 3}
