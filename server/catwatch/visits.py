"""Lógica pura (sem IA): transforma a presença de gatos nas zonas em visitas registradas.

Uma visita só conta quando o MESMO gato FICOU na zona por um tempo mínimo, que depende
do que ele foi fazer (usar a caixa demora mais que beber água). O tempo que conta é o de
presença real, somando só os intervalos em que ele foi visto quadro após quadro: passar
pela zona, ou aparecer duas vezes com segundos de diferença, não vira visita.
"""
import threading
from collections import Counter
from dataclasses import dataclass, field

UNKNOWN = "desconhecido"

# Padrões por tipo de zona (segundos). Ver config.DEFAULTS["visits"].
MIN_SECONDS = {"litter": 15, "food": 8, "water": 5}
GAP_SECONDS = {"litter": 30, "food": 15, "water": 10}
# Buraco máximo entre dois quadros para ainda contar como "o gato estava ali" (a detecção
# falha um quadro ou outro). Acima disso, o tempo não soma, mas a visita segue aberta.
HOLD_SECONDS = 2.5
# Um nome que aparece em menos que isso dos quadros da visita é tratado como erro de
# identificação do gato que lidera, a não ser que os dois apareçam juntos na mesma imagem.
MINORITY_SHARE = 0.25

# Decisão pela visita inteira. Cada quadro sozinho precisa passar do limite de similaridade,
# o que falha quando as fotos do cadastro são de outro ângulo (câmera de cima): o gato certo
# é o mais parecido em quase todos os quadros, mas com nota baixa, e tudo virava
# "desconhecido". Somando os quadros, o nome sai se o mesmo gato for o mais parecido em boa
# parte deles, com folga sobre o segundo, e a nota média dele não estiver longe do limite.
AGG_MIN_FRAMES = 5      # quadros com nota, no mínimo
AGG_SHARE = 0.5         # o gato é o mais parecido em pelo menos metade dos quadros
AGG_LEAD = 0.25         # e ganha do segundo por um quarto dos quadros
AGG_SLACK = 0.2         # nota média até 0,2 abaixo do limite de um quadro só
# Recortes do gato guardados por visita: material para aprender com a câmera quando o
# usuário confirma ou corrige o gato da visita.
MAX_CROPS = 6
CROP_SPACING = 2.0      # segundos entre recortes (dobra quando enche, para cobrir a visita toda)
# Suavização do nome quadro a quadro: cada quadro olha este tanto de vizinhos de cada lado.
SMOOTH = 3


def visit_identity(score_list: list[dict], threshold: float):
    """(nome ou None, nota média do gato escolhido, votos) a partir das notas de cada quadro.

    votos: em quantos quadros cada gato foi o mais parecido.
    """
    votes = Counter(max(sc, key=sc.get) for sc in score_list if sc)
    n = sum(votes.values())
    if not n:
        return None, None, votes
    ranked = votes.most_common(2)
    best, k = ranked[0]
    second = ranked[1][1] if len(ranked) > 1 else 0
    mean = sum(sc[best] for sc in score_list if best in sc) / sum(1 for sc in score_list if best in sc)
    if n >= AGG_MIN_FRAMES and k / n >= AGG_SHARE and (k - second) / n >= AGG_LEAD and mean >= threshold - AGG_SLACK:
        return best, mean, votes
    return None, mean, votes


def point_in_polygon(x: float, y: float, poly: list[list[float]]) -> bool:
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def presence_seconds(times: list[float], hold: float = HOLD_SECONDS) -> float:
    """Soma os intervalos entre quadros consecutivos de até `hold` segundos."""
    ts = sorted(times)
    return sum(b - a for a, b in zip(ts, ts[1:]) if b - a <= hold)


@dataclass
class _Seen:
    """O que se viu de um nome (gato) dentro de uma visita."""
    times: list = field(default_factory=list)
    sim_sum: float = 0.0
    sim_n: int = 0
    conf_max: float = 0.0
    best_quality: float = -1.0
    best_frame: object = None
    best_t: float = 0.0
    scores: list = field(default_factory=list)   # nota de cada gato, quadro a quadro
    crops: list = field(default_factory=list)    # (hora, recorte do gato)
    crop_spacing: float = CROP_SPACING

    def absorb(self, other: "_Seen"):
        self.times += other.times
        self.sim_sum += other.sim_sum
        self.sim_n += other.sim_n
        self.conf_max = max(self.conf_max, other.conf_max)
        if other.best_quality > self.best_quality:
            self.best_quality, self.best_frame, self.best_t = other.best_quality, other.best_frame, other.best_t
        self.scores += other.scores
        self.crops = sorted(self.crops + other.crops, key=lambda c: c[0])
        while len(self.crops) > MAX_CROPS:
            self.crops = self.crops[::2]

    def add_crop(self, now, crop):
        if self.crops and now - self.crops[-1][0] < self.crop_spacing:
            return
        self.crops.append((now, crop))
        if len(self.crops) > MAX_CROPS:  # cheio: fica com um sim, um não, e espaça os próximos
            self.crops = self.crops[::2]
            self.crop_spacing *= 2


@dataclass
class _Open:
    last: float
    kind: str | None = None
    votes: Counter = field(default_factory=Counter)
    seen: dict = field(default_factory=dict)  # nome -> _Seen
    frames: list = field(default_factory=list)  # (hora, nome, notas, similaridade, confiança), quadro a quadro


def _per_kind(value, defaults: dict) -> dict:
    """Aceita um número (vale para todos os tipos) ou um dict por tipo."""
    if isinstance(value, dict):
        return {**defaults, **value}
    return {k: value for k in defaults}


class VisitTracker:
    """Uma visita aberta por (câmera, zona); ao fechar, vira uma visita por gato que ficou o bastante."""

    def __init__(self, min_seconds=None, gap_seconds=None, hold: float = HOLD_SECONDS, threshold: float = 0.70):
        self.min_seconds = _per_kind(MIN_SECONDS if min_seconds is None else min_seconds, MIN_SECONDS)
        self.gap_seconds = _per_kind(GAP_SECONDS if gap_seconds is None else gap_seconds, GAP_SECONDS)
        self.hold = hold
        self.threshold = threshold  # o mesmo limite da identificação (o pipeline mantém igual)
        self.open: dict[tuple[str, str], _Open] = {}
        # Cada câmera roda numa thread e todas atualizam e fecham visitas aqui.
        self._lock = threading.Lock()

    def configure(self, min_seconds, gap_seconds):
        self.min_seconds = _per_kind(min_seconds, MIN_SECONDS)
        self.gap_seconds = _per_kind(gap_seconds, GAP_SECONDS)

    def _min(self, kind):
        return self.min_seconds.get(kind, min(self.min_seconds.values()))

    def _gap(self, kind):
        return self.gap_seconds.get(kind, max(self.gap_seconds.values()))

    def update(self, camera: str, zone: str, cat: str | None, now: float, kind: str | None = None,
               score: float | None = None, frame=None, conf: float | None = None,
               scores: dict | None = None, crop=None) -> None:
        """Chame para cada gato visto dentro da zona num quadro (todos os gatos do mesmo quadro com o mesmo `now`).

        score = similaridade da identificação; frame = imagem já anotada. Guardamos o quadro
        com a melhor evidência (maior similaridade, ou maior confiança de detecção) como foto.
        scores = nota de cada gato neste quadro; crop = recorte do gato (sem as marcações).
        """
        with self._lock:
            self._update(camera, zone, cat, now, kind, score, frame, conf, scores, crop)

    def _update(self, camera, zone, cat, now, kind, score, frame, conf, scores=None, crop=None):
        v = self.open.setdefault((camera, zone), _Open(now))
        v.last = max(v.last, now)
        v.kind = kind or v.kind
        name = cat or UNKNOWN
        v.votes[name] += 1
        v.frames.append((now, name, scores or None, score or 0.0, conf or 0.0))
        s = v.seen.setdefault(name, _Seen())
        s.times.append(now)
        if score:
            s.sim_sum += score
            s.sim_n += 1
        s.conf_max = max(s.conf_max, conf or 0.0)
        quality = score if score else (conf or 0.0)
        if frame is not None and quality > s.best_quality:
            s.best_quality, s.best_frame, s.best_t = quality, frame, now
        if scores:
            s.scores.append(scores)
        if crop is not None:
            s.add_crop(now, crop)

    def _resolve(self, v: _Open) -> dict:
        """Junta os nomes que são o mesmo gato: 'desconhecido' e trocas esporádicas de nome vão para o líder."""
        known = {n: s for n, s in v.seen.items() if n != UNKNOWN}
        if not known:
            return dict(v.seen)
        leader = max(known, key=lambda n: len(known[n].times))
        out = {leader: _Seen()}
        out[leader].absorb(known[leader])
        total_known = sum(len(s.times) for s in known.values())
        leader_times = set(known[leader].times)
        for name, s in known.items():
            if name == leader:
                continue
            together = len(leader_times & set(s.times))  # os dois na mesma imagem: são gatos diferentes
            if len(s.times) / total_known < MINORITY_SHARE and together < 3:
                out[leader].absorb(s)
            else:
                out[name] = _Seen()
                out[name].absorb(s)
        if UNKNOWN in v.seen:
            out[leader].absorb(v.seen[UNKNOWN])
        return out

    def reset(self) -> None:
        """Descarta as visitas em andamento (os dados foram substituídos por um backup)."""
        with self._lock:
            self.open.clear()

    def flush(self, now: float, force: bool = False) -> list[dict]:
        """Fecha as visitas sem o gato há gap_seconds (do tipo da zona) e devolve as que valem.
        force=True fecha todas (servidor encerrando: quem estava na caixa ainda conta)."""
        with self._lock:
            return self._flush(now, force)

    def _flush(self, now: float, force: bool) -> list[dict]:
        done = []
        for key in list(self.open):
            v = self.open[key]
            if not (force or now - v.last >= self._gap(v.kind)):
                continue
            del self.open[key]
            for cat, s, votes, score in self._name(v):
                stayed = presence_seconds(s.times, self.hold)
                if stayed < self._min(v.kind):
                    if stayed > 0:  # ajuda a entender uma visita "que não contou"
                        print(f"[descartada] {key[0]}/{key[1]}: {cat} visto {stayed:.0f} s de "
                              f"{self._min(v.kind)} s mínimos ({len(s.times)} quadros)", flush=True)
                    continue
                done.append({
                    "camera": key[0], "zone": key[1], "cat": cat, "kind": v.kind,
                    "start": min(s.times), "end": max(s.times), "presence": stayed,
                    "votes": votes, "frames": len(s.times),
                    "score": score, "conf": s.conf_max, "frame": s.best_frame,
                    "crops": [c for _, c in s.crops],
                })
        return done

    def _name(self, v: _Open):
        """Quem foi cada gato da visita: (nome, o que se viu, votos, nota).

        Dois gatos na mesma imagem (comendo lado a lado): separados pelo nome de cada quadro.
        Um gato por vez: os quadros em ordem de tempo, cortados onde o gato muda. Um trecho curto
        demais para ser visita sozinho se junta ao vizinho: um nome que oscila entre dois gatos
        parecidos não pode partir a visita em pedaços que não contam (antes ela sumia). Dois
        gatos seguidos, cada um com o tempo mínimo, continuam sendo duas visitas.
        """
        if self._simultaneous(v):
            groups = [(cat, s, dict(v.votes)) for cat, s in self._resolve(v).items()]
        else:
            groups = [self._segment_seen(v, fr) for fr in self._segments(v)]
        named: dict[str, list] = {}
        for cat, s, fallback_votes in groups:
            agg, mean, top = visit_identity(s.scores, self.threshold)
            if agg:
                cat, score, votes = agg, mean, dict(top)
            else:
                score = s.sim_sum / s.sim_n if s.sim_n else None   # similaridade média do gato
                votes = dict(top) if top else fallback_votes
            if cat in named:                                       # o mesmo gato em dois trechos
                prev = named[cat]
                prev[0].absorb(s)
                prev[1] = dict(Counter(prev[1]) + Counter(votes))
            else:
                named[cat] = [s, votes, score]
        return [(cat, s, votes, score) for cat, (s, votes, score) in named.items()]

    @staticmethod
    def _simultaneous(v: _Open) -> bool:
        """Dois gatos na zona na mesma imagem, em 3 quadros ou mais."""
        per_t = Counter(f[0] for f in v.frames)
        return sum(1 for n in per_t.values() if n >= 2) >= 3

    def _segments(self, v: _Open) -> list[list]:
        """Os quadros em ordem de tempo, em trechos de um gato só."""
        fr = sorted(v.frames, key=lambda f: f[0])
        # Nome de cada quadro: o gato mais parecido (sem limite), ou o que a identificação deu.
        labels = [max(sc, key=sc.get) if sc else (n if n != UNKNOWN else None) for _, n, sc, _, _ in fr]
        smooth = []
        for i in range(len(fr)):
            win = [lb for lb in labels[max(0, i - SMOOTH): i + SMOOTH + 1] if lb]
            smooth.append(Counter(win).most_common(1)[0][0] if win else None)
        for order in (range(len(smooth)), reversed(range(len(smooth)))):   # sem nome: herda do vizinho
            last = None
            for i in order:
                if smooth[i] is None:
                    smooth[i] = last
                else:
                    last = smooth[i]
        runs: list[list[int]] = []
        for i, lb in enumerate(smooth):
            if runs and smooth[runs[-1][0]] == lb:
                runs[-1][1] = i
            else:
                runs.append([i, i])
        minimum = self._min(v.kind)

        def stayed(r):
            return presence_seconds([fr[i][0] for i in range(r[0], r[1] + 1)], self.hold)

        while len(runs) > 1:
            short = [k for k, r in enumerate(runs) if stayed(r) < minimum]
            if not short:
                break
            k = min(short, key=lambda k: stayed(runs[k]))
            if k == 0:
                j = 1
            elif k == len(runs) - 1:
                j = k - 1
            else:   # junta ao vizinho mais perto no tempo
                before = fr[runs[k][0]][0] - fr[runs[k - 1][1]][0]
                after = fr[runs[k + 1][0]][0] - fr[runs[k][1]][0]
                j = k - 1 if before <= after else k + 1
            a, b = sorted((k, j))
            runs[a] = [runs[a][0], runs[b][1]]
            del runs[b]
        return [fr[r[0]: r[1] + 1] for r in runs]

    @staticmethod
    def _segment_seen(v: _Open, frames: list):
        """(nome pelos quadros, o que se viu no trecho, votos pelos quadros)."""
        s = _Seen()
        names = Counter()
        for t, n, sc, sim, conf in frames:
            s.times.append(t)
            names[n] += 1
            if sim:
                s.sim_sum += sim
                s.sim_n += 1
            s.conf_max = max(s.conf_max, conf)
            if sc:
                s.scores.append(sc)
        t0, t1 = frames[0][0], frames[-1][0]
        # Foto: a melhor evidência guardada dentro do trecho (ou, se não houver, a da visita).
        withframe = [x for x in v.seen.values() if x.best_frame is not None]
        inside = [x for x in withframe if t0 <= x.best_t <= t1]
        if withframe:
            best = max(inside or withframe, key=lambda x: x.best_quality)
            s.best_quality, s.best_frame, s.best_t = best.best_quality, best.best_frame, best.best_t
        s.crops = sorted((c for x in v.seen.values() for c in x.crops if t0 <= c[0] <= t1), key=lambda c: c[0])
        while len(s.crops) > MAX_CROPS:
            s.crops = s.crops[::2]
        known = Counter({n: k for n, k in names.items() if n != UNKNOWN})
        cat = known.most_common(1)[0][0] if known else UNKNOWN   # quem lidera; "desconhecido" vai com ele
        return cat, s, dict(names)
