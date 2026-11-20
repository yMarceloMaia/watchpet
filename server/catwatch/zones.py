"""Em qual zona está um gato detectado: no máximo uma por gato.

Os pés do gato (base da caixa) são o melhor indício com a câmera de lado. Com a câmera vista
de cima, os pés podem cair fora do polígono mesmo com o gato dentro da caixa de areia; por
isso também conta quanto da metade de baixo do gato está dentro da zona. Se duas zonas
disputam o mesmo gato (comedouro e bebedouro lado a lado), vence a que cobre mais dele,
para uma parada não contar como "comeu" e "bebeu" ao mesmo tempo.
"""
import cv2
import numpy as np

from .visits import point_in_polygon

MASK_WIDTH = 160        # máscaras em baixa resolução: rápidas e precisas o bastante
MIN_COVERAGE = 0.35     # fração da metade de baixo do gato dentro da zona para contar


class ZoneMap:
    def __init__(self):
        self._key = None
        self._masks = []

    def _build(self, zones, w, h):
        key = (w, h, tuple((z["name"], tuple(map(tuple, z["polygon"]))) for z in zones))
        if key == self._key:
            return
        mh = max(1, round(MASK_WIDTH * h / w))
        self._masks = []
        for z in zones:
            m = np.zeros((mh, MASK_WIDTH), np.uint8)
            if len(z["polygon"]) >= 3:
                pts = np.array([[x * MASK_WIDTH, y * mh] for x, y in z["polygon"]], np.int32)
                cv2.fillPoly(m, [pts], 1)
            self._masks.append(m)
        self._key = key

    def coverage(self, i, box, w, h):
        """Fração da metade de baixo da caixa do gato que está dentro da zona i."""
        m = self._masks[i]
        mh, mw = m.shape
        x1, y1, x2, y2 = box
        ymid = (y1 + y2) / 2
        c1, c2 = int(max(0, x1) / w * mw), int(np.ceil(min(w, x2) / w * mw))
        r1, r2 = int(max(0, ymid) / h * mh), int(np.ceil(min(h, y2) / h * mh))
        region = m[r1:max(r1 + 1, r2), c1:max(c1 + 1, c2)]
        return float(region.mean()) if region.size else 0.0

    def zone_for(self, box, zones, w, h):
        """A zona do gato nesta caixa (x1, y1, x2, y2 em pixels), ou None."""
        if not zones:
            return None
        self._build(zones, w, h)
        x1, y1, x2, y2 = box
        fx, fy = (x1 + x2) / 2 / w, y2 / h
        best, best_score = None, 0.0
        for i, z in enumerate(zones):
            cov = self.coverage(i, box, w, h)
            feet = point_in_polygon(fx, fy, z["polygon"])
            if not feet and cov < MIN_COVERAGE:
                continue
            score = cov + (1.0 if feet else 0.0)   # pés dentro pesam mais; empate decide pela cobertura
            if score > best_score:
                best, best_score = z, score
        return best
