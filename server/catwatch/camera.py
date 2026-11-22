import os
import threading
import time

# RTSP por TCP: por UDP, os pacotes perdidos (mais comuns à noite, quando o ruído do
# infravermelho aumenta o tamanho dos quadros) viram imagens borradas ou travam o stream.
# setdefault: quem precisar de outra opção define a variável antes de abrir o servidor.
os.environ.setdefault("OPENCV_FFMPEG_CAPTURE_OPTIONS", "rtsp_transport;tcp")

import cv2  # noqa: E402  (precisa ler a variável acima)
import numpy as np  # noqa: E402

# Quadros por segundo guardados de cada câmera (o máximo que a análise usa). A câmera manda
# 25-30; converter todos para BGR só gastava CPU, que faz falta para a análise e os apps.
KEEP_FPS = 15
# Sem quadro novo nesse tempo, a câmera está fora do ar (e a conexão é refeita).
TIMEOUT_MS = 10000


class Camera:
    """Lê o stream numa thread e guarda só o frame mais recente (evita atraso acumulado).

    source == "push": não abre nada; o celular envia frames por POST /api/push/<nome>.
    """

    def __init__(self, name: str, source):
        self.name = name
        self.push = str(source) == "push"
        self.source = int(source) if str(source).isdigit() else source
        # (quadro, hora) trocados juntos numa atribuição só: quem lê em outra thread nunca
        # vê o quadro novo com a hora do antigo.
        self.latest: tuple = (None, 0.0)
        self._stop = False
        if not self.push:
            threading.Thread(target=self._run, daemon=True, name=f"camera-{name}").start()

    @property
    def frame(self):
        return self.latest[0]

    @property
    def ts(self) -> float:
        return self.latest[1]

    @property
    def online(self) -> bool:
        frame, ts = self.latest
        return frame is not None and time.time() - ts < 10

    def set_jpeg(self, data: bytes) -> bool:
        if not data:
            return False
        try:
            img = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
        except cv2.error:
            return False
        if img is None:
            return False
        self.latest = (img, time.time())
        return True

    def _open(self):
        if isinstance(self.source, str):
            # Sem estes limites, uma câmera que para de responder segura a leitura por 30 s.
            return cv2.VideoCapture(self.source, cv2.CAP_ANY, [
                cv2.CAP_PROP_OPEN_TIMEOUT_MSEC, TIMEOUT_MS, cv2.CAP_PROP_READ_TIMEOUT_MSEC, TIMEOUT_MS])
        return cv2.VideoCapture(self.source)

    def _run(self):
        while not self._stop:
            cap = None
            try:
                cap = self._open()
                while not self._stop and cap.isOpened():
                    if not cap.grab():
                        break
                    now = time.time()
                    if now - self.latest[1] < 1 / KEEP_FPS:
                        continue  # descarta sem converter: só o mais recente interessa
                    ok, frame = cap.retrieve()
                    if not ok or frame is None:
                        break
                    self.latest = (frame, now)
            except Exception as e:  # um erro do OpenCV não pode matar a câmera de vez
                print(f"[camera] {self.name}: {e}", flush=True)
            finally:
                if cap is not None:
                    cap.release()
            if not self._stop:
                time.sleep(3)  # reconecta se a câmera/celular caiu

    def stop(self):
        self._stop = True
