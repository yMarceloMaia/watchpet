import json
import threading
import time
import traceback
from pathlib import Path

import cv2
import numpy as np

from . import db as dbm
from . import overlay
from .camera import Camera
from .config import visit_rules
from .vision import UNKNOWN
from .visits import HOLD_SECONDS, VisitTracker
from .zones import ZoneMap

# Quadro anotado mais velho que isso em relação ao ao vivo: a análise está atrasada.
STALE_ANNOTATED = 5.0


class Pipeline:
    def __init__(self, cfg, detector, identifier):
        self.cfg, self.detector, self.identifier = cfg, detector, identifier
        self.db = dbm.connect(cfg["db"])
        self.photo_dir = Path(cfg["db"]).parent / "snapshots"
        self.tracker = VisitTracker(*visit_rules(cfg))
        self.cams: dict[str, Camera] = {}
        self.last_annotated: dict[str, tuple] = {}  # câmera -> (quadro anotado, hora do quadro)
        self._jpeg: dict[tuple, tuple] = {}          # (câmera, anotado?) -> (quadro, bytes do JPEG)
        self._error_at: dict[str, float] = {}        # última vez que cada câmera registrou erro
        self._infer = threading.Lock()  # a GPU/CPU é compartilhada; serializa a inferência
        self.infer_ms = 0.0             # média móvel do tempo de análise de um quadro
        self.frames_analyzed = 0
        for c in cfg["cameras"]:
            self._start(c)

    # --- gerência de câmeras em tempo de execução ---
    def _start(self, ccfg):
        cam = Camera(ccfg["name"], ccfg["source"])
        self.cams[ccfg["name"]] = cam
        threading.Thread(target=self._loop, args=(cam, ccfg), daemon=True).start()

    def add_camera(self, ccfg):
        self.cfg["cameras"].append(ccfg)
        self._start(ccfg)

    def remove_camera(self, name):
        cam = self.cams.pop(name, None)
        if cam:
            cam.stop()
        self.cfg["cameras"][:] = [c for c in self.cfg["cameras"] if c["name"] != name]
        self.last_annotated.pop(name, None)
        for key in [k for k in self._jpeg if k[0] == name]:
            self._jpeg.pop(key, None)

    def camera_cfg(self, name):
        return next((c for c in self.cfg["cameras"] if c["name"] == name), None)

    # --- pipeline ---
    def _loop(self, cam, ccfg):
        state = {"seen_ts": 0.0, "zmap": ZoneMap()}
        next_at = time.monotonic()
        while self.cams.get(cam.name) is cam:
            # Ritmo pelo relógio, não "dorme 1/fps depois de analisar": assim o tempo de análise
            # não come os quadros por segundo configurados (lido a cada volta: muda na hora).
            period = 1 / self.cfg["detection"]["fps"]
            next_at = max(next_at + period, time.monotonic())
            time.sleep(max(0.0, next_at - time.monotonic()))
            # Um erro num quadro (imagem estranha, banco ocupado) não pode parar a câmera de vez:
            # antes, a thread morria calada e a imagem dos apps congelava no último quadro.
            try:
                self._step(cam, ccfg, period, state)
            except Exception as e:
                self._report_error(cam.name, e)
                time.sleep(1)

    def _report_error(self, name, e):
        print(f"[erro] câmera {name}: {e}", flush=True)
        traceback.print_exc()
        now = time.time()
        if now - self._error_at.get(name, 0) >= 600:  # no máximo um aviso a cada 10 min por câmera
            self._error_at[name] = now
            try:
                dbm.add_event(self.db, "error", f"Erro ao analisar a câmera {name}: {e}", "error", camera=name)
            except Exception:
                pass

    def _step(self, cam, ccfg, period, state):
        # Sem quadros vizinhos a menos de 1 período, a presença não somaria nada.
        self.tracker.hold = max(HOLD_SECONDS, 3 * period)
        frame, now = cam.latest
        if frame is None or now == state["seen_ts"]:
            self._save_flush(time.time())
            return
        state["seen_ts"], frame = now, frame.copy()
        h, w = frame.shape[:2]
        zones = ccfg["zones"]
        zmap = state["zmap"]
        updates, cats = [], []
        with self._infer:
            t0 = time.perf_counter()
            for x1, y1, x2, y2, conf in self.detector(frame):
                box = (x1, y1, x2, y2)
                zone = zmap.zone_for(box, zones, w, h)   # no máximo uma zona por gato
                name, sim = None, 0.0
                if zone:
                    crop = frame[max(y1, 0):y2, max(x1, 0):x2]
                    if crop.size:
                        name, sim = self.identifier(crop)
                    if name == UNKNOWN:
                        name = None
                    updates.append((zone, name, sim, conf))
                cats.append((box, name, sim, zone is not None))
            ms = (time.perf_counter() - t0) * 1000
            self.infer_ms = ms if not self.frames_analyzed else self.infer_ms * 0.9 + ms * 0.1
            self.frames_analyzed += 1
        stamp = f"{cam.name}  {time.strftime('%d/%m/%Y %H:%M:%S', time.localtime(now))}"
        overlay.draw(frame, zones, {z["name"] for z, *_ in updates}, cats, stamp)
        # O quadro anotado vira a foto da visita (o tracker guarda o melhor).
        for z, name, sim, conf in updates:
            self.tracker.update(cam.name, z["name"], name, now, z["kind"], sim, frame, conf)
        if self.cams.get(cam.name) is cam:  # câmera removida durante a análise: não ressuscita a imagem
            self.last_annotated[cam.name] = (frame, now)
        self._save_flush(now)

    def jpeg(self, name: str, annotated: bool = True) -> bytes | None:
        """O quadro mais recente da câmera em JPEG, com as marcações da análise se `annotated`.

        Se a análise ficou para trás (processador sobrecarregado ou com erro), mostra o quadro
        ao vivo sem marcações em vez de uma imagem parada. Cada quadro é codificado uma vez só,
        por mais apps que estejam olhando.
        """
        cam = self.cams.get(name)
        raw, raw_ts = cam.latest if cam else (None, 0.0)
        frame = raw
        if annotated:
            ann = self.last_annotated.get(name)
            if ann is not None and (raw is None or raw_ts - ann[1] <= STALE_ANNOTATED):
                frame = ann[0]
        if frame is None:
            return None
        key = (name, frame is not raw)
        cached = self._jpeg.get(key)
        if cached is not None and cached[0] is frame:
            return cached[1]
        ok, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 80])
        if not ok:
            return None
        data = buf.tobytes()
        self._jpeg[key] = (frame, data)
        return data

    def _save_flush(self, now, force=False):
        for v in self.tracker.flush(now, force):
            # Cada visita por si: um erro numa (disco cheio na foto) não apaga as outras do lote.
            try:
                self._save_visit(v)
            except Exception as e:
                self._report_error(v["camera"], e)

    def _save_visit(self, v):
        frame = v.pop("frame")
        vid = dbm.add_visit(self.db, v["cat"], v["kind"] or "litter", v["zone"], v["camera"],
                            v["start"], v["end"], v["score"], v["conf"], v["frames"],
                            json.dumps(v["votes"], ensure_ascii=False), int(frame is not None), v["presence"])
        if frame is not None:
            self.save_photo(vid, frame)
        kind_name = {"litter": "caixa de areia", "food": "comida", "water": "água"}.get(v["kind"], v["kind"])
        dbm.add_event(self.db, "visit", f"{v['cat']} → {v['zone']} ({kind_name}), ficou {v['presence']:.0f} s",
                      cat=v["cat"], camera=v["camera"], visit_id=vid, ts=v["end"])
        print(f"[visita] {v['cat']} -> {v['zone']} ({v['kind']}) ficou {v['presence']:.0f}s de {v['end']-v['start']:.0f}s "
              f"similaridade={v['score'] or 0:.2f} quadros={v['frames']}", flush=True)

    def photo_path(self, vid: int) -> Path:
        return self.photo_dir / f"{vid}.jpg"

    def save_photo(self, vid: int, frame):
        self.photo_dir.mkdir(parents=True, exist_ok=True)
        h, w = frame.shape[:2]
        if w > 800:
            frame = cv2.resize(frame, (800, int(h * 800 / w)))
        cv2.imwrite(str(self.photo_path(vid)), frame, [cv2.IMWRITE_JPEG_QUALITY, 82])

    def cat_crop(self, name):
        """Recorte do maior gato visto agora na câmera (para cadastrar sem sair do app)."""
        cam = self.cams.get(name)
        frame = cam.frame if cam else None
        if frame is None:
            return None
        frame = frame.copy()
        with self._infer:
            boxes = self.detector(frame)
        if not boxes:
            return None
        x1, y1, x2, y2, _ = max(boxes, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]))
        return frame[max(y1, 0):y2, max(x1, 0):x2]
