import json
import threading
import time
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


class Pipeline:
    def __init__(self, cfg, detector, identifier):
        self.cfg, self.detector, self.identifier = cfg, detector, identifier
        self.db = dbm.connect(cfg["db"])
        self.photo_dir = Path(cfg["db"]).parent / "snapshots"
        self.tracker = VisitTracker(*visit_rules(cfg))
        self.cams: dict[str, Camera] = {}
        self.last_annotated = {}
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

    def camera_cfg(self, name):
        return next((c for c in self.cfg["cameras"] if c["name"] == name), None)

    # --- pipeline ---
    def _loop(self, cam, ccfg):
        seen_ts = 0
        zmap = ZoneMap()
        next_at = time.monotonic()
        while self.cams.get(cam.name) is cam:
            # Ritmo pelo relógio, não "dorme 1/fps depois de analisar": assim o tempo de análise
            # não come os quadros por segundo configurados (lido a cada volta: muda na hora).
            period = 1 / self.cfg["detection"]["fps"]
            next_at = max(next_at + period, time.monotonic())
            time.sleep(max(0.0, next_at - time.monotonic()))
            # Sem quadros vizinhos a menos de 1 período, a presença não somaria nada.
            self.tracker.hold = max(HOLD_SECONDS, 3 * period)
            if cam.frame is None or cam.ts == seen_ts:
                self._save_flush(time.time())
                continue
            seen_ts, frame, now = cam.ts, cam.frame.copy(), cam.ts
            h, w = frame.shape[:2]
            zones = ccfg["zones"]
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
            self.last_annotated[cam.name] = frame
            self._save_flush(now)

    def _save_flush(self, now, force=False):
        for v in self.tracker.flush(now, force):
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
        if cam is None or cam.frame is None:
            return None
        frame = cam.frame.copy()
        with self._infer:
            boxes = self.detector(frame)
        if not boxes:
            return None
        x1, y1, x2, y2, _ = max(boxes, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]))
        return frame[max(y1, 0):y2, max(x1, 0):x2]
