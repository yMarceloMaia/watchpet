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


# ---------- decisão pela visita inteira ----------

def scores(best, best_sim=0.60, other_sim=0.55):
    """Notas de um quadro: `best` é o mais parecido, mas abaixo do limite de um quadro só."""
    out = {c: other_sim for c in ("Leona", "Sushi", "Tom", "Mia")}
    out[best] = best_sim
    return out


def feed(t, frames, cat=None, start=0.0, step=1.0):
    for i, sc in enumerate(frames):
        t.update("cam", "caixa", cat, start + i * step, "litter", max(sc.values()), None, 0.8, sc)


def test_low_scores_still_name_the_cat_over_the_whole_visit():
    # Câmera de cima e cadastro com fotos de lado: nenhum quadro passa de 0,70, mas a Leona
    # é a mais parecida em quase todos. Antes, a visita ficava "desconhecido".
    t = VisitTracker(threshold=0.70)
    frames = [scores("Leona")] * 60 + [scores("Sushi")] * 10 + [scores("Tom")] * 5
    feed(t, frames)
    (v,) = t.flush(1000)
    assert v["cat"] == "Leona"
    assert v["votes"] == {"Leona": 60, "Sushi": 10, "Tom": 5}
    assert abs(v["score"] - (60 * 0.60 + 15 * 0.55) / 75) < 1e-6   # nota média da Leona


def test_split_evidence_stays_unknown():
    t = VisitTracker(threshold=0.70)
    feed(t, [scores("Leona"), scores("Sushi")] * 19)          # o mesmo gato, ora parece um, ora outro
    (v,) = t.flush(1000)
    assert v["cat"] == "desconhecido"


def test_name_flipping_between_similar_cats_does_not_lose_the_visit():
    # 20 s na caixa; o nome alterna em blocos de 6 s entre duas gatas parecidas. Antes a visita
    # virava dois "gatos" de 10 s cada, abaixo dos 15 s mínimos, e sumia.
    t = VisitTracker()
    for i, now in enumerate(frames(100, 20)):
        t.update("cam", "caixa", "Leona" if (now - 100) % 12 < 6 else "Morgana", now, "litter", 0.75)
    out = t.flush(500)
    assert len(out) == 1 and out[0]["presence"] > 19


def test_two_cats_in_a_row_each_long_enough_are_two_visits():
    t = VisitTracker(threshold=0.70)
    feed(t, [scores("Leona")] * 20)                            # 20 s de Leona
    feed(t, [scores("Sushi")] * 20, start=25.0)                # Sushi entra 5 s depois, 20 s
    out = t.flush(1000)
    assert sorted((v["cat"], round(v["presence"])) for v in out) == [("Leona", 19), ("Sushi", 19)]


def test_far_from_everyone_stays_unknown():
    # Gato de fora (ou não cadastrado): o "mais parecido" é sempre o mesmo, mas a nota é baixa demais.
    t = VisitTracker(threshold=0.70)
    feed(t, [scores("Leona", 0.40, 0.35)] * 40)
    (v,) = t.flush(1000)
    assert v["cat"] == "desconhecido"


def test_whole_visit_overrides_a_single_lucky_frame():
    # Um quadro passou do limite com o gato errado; os outros 40 apontam a Mia.
    t = VisitTracker(threshold=0.70)
    t.update("cam", "caixa", "Tom", 0.0, "litter", 0.72, None, 0.8, scores("Tom", 0.72, 0.5))
    feed(t, [scores("Mia")] * 40, start=1.0)
    (v,) = t.flush(1000)
    assert v["cat"] == "Mia"


def test_crops_are_kept_spread_over_the_visit():
    t = VisitTracker(threshold=0.70)
    for i in range(120):
        t.update("cam", "caixa", None, float(i), "litter", 0.6, None, 0.8, scores("Leona"), crop=i)
    (v,) = t.flush(1000)
    crops = v["crops"]
    assert 3 <= len(crops) <= 6
    assert crops[0] == 0 and crops[-1] > 60                          # do começo ao fim, não só os primeiros
