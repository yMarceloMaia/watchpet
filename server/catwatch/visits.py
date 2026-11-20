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

    def absorb(self, other: "_Seen"):
        self.times += other.times
        self.sim_sum += other.sim_sum
        self.sim_n += other.sim_n
        self.conf_max = max(self.conf_max, other.conf_max)
        if other.best_quality > self.best_quality:
            self.best_quality, self.best_frame = other.best_quality, other.best_frame


@dataclass
class _Open:
    last: float
    kind: str | None = None
    votes: Counter = field(default_factory=Counter)
    seen: dict = field(default_factory=dict)  # nome -> _Seen


def _per_kind(value, defaults: dict) -> dict:
    """Aceita um número (vale para todos os tipos) ou um dict por tipo."""
    if isinstance(value, dict):
        return {**defaults, **value}
    return {k: value for k in defaults}


class VisitTracker:
    """Uma visita aberta por (câmera, zona); ao fechar, vira uma visita por gato que ficou o bastante."""

    def __init__(self, min_seconds=None, gap_seconds=None, hold: float = HOLD_SECONDS):
        self.min_seconds = _per_kind(MIN_SECONDS if min_seconds is None else min_seconds, MIN_SECONDS)
        self.gap_seconds = _per_kind(GAP_SECONDS if gap_seconds is None else gap_seconds, GAP_SECONDS)
        self.hold = hold
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
               score: float | None = None, frame=None, conf: float | None = None) -> None:
        """Chame para cada gato visto dentro da zona num quadro (todos os gatos do mesmo quadro com o mesmo `now`).

        score = similaridade da identificação; frame = imagem já anotada. Guardamos o quadro
        com a melhor evidência (maior similaridade, ou maior confiança de detecção) como foto.
        """
        with self._lock:
            self._update(camera, zone, cat, now, kind, score, frame, conf)

    def _update(self, camera, zone, cat, now, kind, score, frame, conf):
        v = self.open.setdefault((camera, zone), _Open(now))
        v.last = max(v.last, now)
        v.kind = kind or v.kind
        name = cat or UNKNOWN
        v.votes[name] += 1
        s = v.seen.setdefault(name, _Seen())
        s.times.append(now)
        if score:
            s.sim_sum += score
            s.sim_n += 1
        s.conf_max = max(s.conf_max, conf or 0.0)
        quality = score if score else (conf or 0.0)
        if frame is not None and quality > s.best_quality:
            s.best_quality, s.best_frame = quality, frame

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
            for cat, s in self._resolve(v).items():
                stayed = presence_seconds(s.times, self.hold)
                if stayed < self._min(v.kind):
                    continue
                done.append({
                    "camera": key[0], "zone": key[1], "cat": cat, "kind": v.kind,
                    "start": min(s.times), "end": max(s.times), "presence": stayed,
                    "votes": dict(v.votes), "frames": len(s.times),
                    "score": s.sim_sum / s.sim_n if s.sim_n else None,  # similaridade média do gato
                    "conf": s.conf_max, "frame": s.best_frame,
                })
        return done
