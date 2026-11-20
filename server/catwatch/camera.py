import threading
import time

import cv2
import numpy as np


class Camera:
    """Lê o stream numa thread e guarda só o frame mais recente (evita atraso acumulado).

    source == "push": não abre nada; o celular envia frames por POST /api/push/<nome>.
    """

    def __init__(self, name: str, source):
        self.name = name
        self.push = str(source) == "push"
        self.source = int(source) if str(source).isdigit() else source
        self.frame = None
        self.ts = 0.0
        self._stop = False
        if not self.push:
            threading.Thread(target=self._run, daemon=True).start()

    @property
    def online(self) -> bool:
        return self.frame is not None and time.time() - self.ts < 10

    def set_jpeg(self, data: bytes) -> bool:
        img = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
        if img is None:
            return False
        self.frame, self.ts = img, time.time()
        return True

    def _run(self):
        while not self._stop:
            cap = cv2.VideoCapture(self.source)
            while not self._stop and cap.isOpened():
                ok, frame = cap.read()
                if not ok:
                    break
                self.frame, self.ts = frame, time.time()
            cap.release()
            time.sleep(3)  # reconecta se a câmera/celular caiu

    def stop(self):
        self._stop = True
