"""Verificações periódicas: câmeras fora do ar e alertas sobre os gatos.

Cada alerta vira um evento com uma `key`; a mesma key não se repete no mesmo dia,
então reiniciar o servidor não dispara o mesmo aviso de novo.
"""
import threading
import time
from datetime import datetime
from pathlib import Path

from . import db as dbm

KIND_NAME = {"litter": "caixa de areia", "food": "comida", "water": "água"}


def day_start(now: float) -> float:
    return datetime.fromtimestamp(now).replace(hour=0, minute=0, second=0, microsecond=0).timestamp()


class Monitor:
    def __init__(self, cfg, pipe, interval: float = 20):
        self.cfg, self.pipe, self.interval = cfg, pipe, interval
        self.started = time.time()
        self.offline_since: dict[str, float] = {}
        self.alerted: set[str] = set()
        self._last_prune = 0.0

    def start(self):
        threading.Thread(target=self._run, daemon=True).start()

    def _run(self):
        while True:
            time.sleep(self.interval)
            try:
                self.check(time.time())
            except Exception as e:  # um erro aqui não pode derrubar o monitoramento
                print(f"[erro] monitor: {e}", flush=True)
                try:
                    dbm.add_event(self.pipe.db, "error", f"Erro no monitor: {e}", "error")
                except Exception:
                    pass  # nem registrar deu (banco ocupado?): tenta de novo na próxima volta

    def _alert(self, key: str, message: str, now: float, cat=None, camera=None, level="warn", type_="alert"):
        if dbm.event_exists(self.pipe.db, key, day_start(now)):
            return
        dbm.add_event(self.pipe.db, type_, message, level, cat=cat, camera=camera, key=key, ts=now)
        print(f"[alerta] {message}", flush=True)

    # ---------- câmeras ----------
    def check_cameras(self, now: float):
        limit = self.cfg["alerts"]["camera_offline_minutes"] * 60
        for name, cam in list(self.pipe.cams.items()):
            if cam.online:
                self.offline_since.pop(name, None)
                if name in self.alerted:
                    self.alerted.discard(name)
                    dbm.add_event(self.pipe.db, "camera_online", f"Câmera {name} voltou", "info", camera=name, ts=now)
                continue
            since = self.offline_since.setdefault(name, max(cam.ts or self.started, self.started))
            if now - since >= limit and name not in self.alerted:
                self.alerted.add(name)
                mins = int((now - since) // 60)
                dbm.add_event(self.pipe.db, "camera_offline", f"Câmera {name} sem imagem há {mins} min",
                              "warn", camera=name, ts=now)
        for name in list(self.offline_since):
            if name not in self.pipe.cams:  # câmera removida
                self.offline_since.pop(name, None)
                self.alerted.discard(name)

    # ---------- gatos ----------
    def _kinds_online(self) -> set[str]:
        """Tipos de zona com pelo menos uma câmera funcionando agora; sem câmera, não dá pra afirmar nada."""
        kinds = set()
        for c in self.cfg["cameras"]:
            cam = self.pipe.cams.get(c["name"])
            if cam and cam.online:
                kinds |= {z["kind"] for z in c["zones"]}
        return kinds

    def check_cats(self, now: float):
        a = self.cfg["alerts"]
        if not a.get("enabled", True):
            return
        db, today = self.pipe.db, day_start(now)
        hour = datetime.fromtimestamp(now).hour
        kinds = self._kinds_online()
        gallery = Path(self.cfg["gallery"])
        cats = [d.name for d in gallery.iterdir() if d.is_dir()] if gallery.exists() else []
        week = today - 7 * 86400
        for cat in cats:
            # Gato sem nenhuma visita na última semana: provavelmente recém-cadastrado; não alarmar.
            if not any(dbm.count_since(db, cat, k, week) for k in KIND_NAME):
                continue
            for kind, by_hour, verb in (("water", a["water_by_hour"], "bebeu água"), ("food", a["food_by_hour"], "comeu")):
                if kind in kinds and hour >= by_hour and dbm.count_since(db, cat, kind, today) == 0:
                    self._alert(f"{kind}:{cat}", f"{cat} ainda não {verb} hoje", now, cat=cat)
            if "litter" in kinds:
                last = dbm.last_visit(db, cat, "litter")
                hours = a["litter_max_hours"]
                if last and now - last > hours * 3600:
                    self._alert(f"litter-none:{cat}", f"{cat} não vai à caixa de areia há {int((now - last) // 3600)} h",
                                now, cat=cat)
                n = dbm.count_since(db, cat, "litter", today)
                avg, days = dbm.daily_avg(db, cat, "litter", week, today)
                if days >= 3 and n >= 5 and n >= a["litter_spike_factor"] * avg:
                    self._alert(f"litter-spike:{cat}",
                                f"{cat} foi {n} vezes à caixa hoje (média {avg:.1f}/dia) — fique de olho",
                                now, cat=cat, level="error")

    def check(self, now: float):
        self.check_cameras(now)
        self.check_cats(now)
        if now - self._last_prune > 3600:
            self._last_prune = now
            dbm.prune_events(self.pipe.db, now - 60 * 86400)
