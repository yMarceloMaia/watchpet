"""Pipeline das câmeras: a análise sobrevive a erros e a imagem dos apps nunca congela."""
import time

import cv2
import numpy as np
import pytest

from catwatch import config as cfgm
from catwatch import db as dbm
from catwatch.camera import Camera
from catwatch.worker import STALE_ANNOTATED, Pipeline


@pytest.fixture
def cfg(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    c = cfgm.load()
    c["detection"]["fps"] = 15
    return c


class FlakyDetector:
    """Falha nas primeiras chamadas, depois acha um gato no meio da imagem."""

    def __init__(self, fail_times):
        self.fail_times, self.calls = fail_times, 0

    def __call__(self, frame):
        self.calls += 1
        if self.calls <= self.fail_times:
            raise RuntimeError("falha simulada")
        h, w = frame.shape[:2]
        return [(w // 4, h // 4, 3 * w // 4, 3 * h // 4, 0.9)]


def identifier(crop):
    return "Leona", 0.9


def push_frame(cam, value=80):
    ok, buf = cv2.imencode(".jpg", np.full((120, 160, 3), value, np.uint8))
    assert cam.set_jpeg(buf.tobytes())


def wait_for(cond, timeout=5.0):
    end = time.time() + timeout
    while time.time() < end:
        if cond():
            return True
        time.sleep(0.02)
    return False


def test_analysis_survives_errors(cfg):
    cfg["cameras"] = [{"name": "cozinha", "source": "push", "zones": []}]
    det = FlakyDetector(fail_times=2)
    pipe = Pipeline(cfg, det, identifier)
    cam = pipe.cams["cozinha"]
    # Antes, a primeira exceção matava a thread da câmera para sempre.
    end = time.time() + 6
    while "cozinha" not in pipe.last_annotated and time.time() < end:
        push_frame(cam, int(time.time() * 10) % 200)
        time.sleep(0.1)
    assert "cozinha" in pipe.last_annotated
    assert det.calls > 2
    errors = dbm.events(pipe.db, type_="error")
    assert len(errors) == 1 and "cozinha" in errors[0]["message"]   # avisa uma vez, não a cada quadro
    pipe.remove_camera("cozinha")


def test_snapshot_falls_back_to_live_when_analysis_lags(cfg):
    pipe = Pipeline(cfg, lambda f: [], identifier)
    cam = Camera("sala", "push")
    pipe.cams["sala"] = cam           # sem thread de análise: simula a análise parada
    assert pipe.jpeg("sala") is None
    push_frame(cam, 10)
    frame, ts = cam.latest
    annotated = np.full_like(frame, 200)
    pipe.last_annotated["sala"] = (annotated, ts)
    first = pipe.jpeg("sala")
    assert first is pipe.jpeg("sala")                               # codificado uma vez só
    assert cv2.imdecode(np.frombuffer(first, np.uint8), cv2.IMREAD_GRAYSCALE).mean() > 150
    # Quadro ao vivo bem mais novo que o anotado: mostra o ao vivo em vez de congelar.
    cam.latest = (frame, ts + STALE_ANNOTATED + 1)
    live = pipe.jpeg("sala")
    assert cv2.imdecode(np.frombuffer(live, np.uint8), cv2.IMREAD_GRAYSCALE).mean() < 60
    raw = pipe.jpeg("sala", annotated=False)
    assert cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_GRAYSCALE).mean() < 60


def test_camera_reads_video_file(tmp_path):
    path = str(tmp_path / "v.avi")
    out = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"MJPG"), 30, (160, 120))
    for i in range(90):
        out.write(np.full((120, 160, 3), i, np.uint8))
    out.release()
    cam = Camera("arquivo", path)
    try:
        assert wait_for(lambda: cam.online)
        assert cam.frame.shape == (120, 160, 3)
    finally:
        cam.stop()


def test_camera_bad_source_does_not_raise():
    cam = Camera("nada", "rtsp://127.0.0.1:1/nao-existe")
    time.sleep(0.5)
    assert not cam.online
    cam.stop()


def test_push_rejects_empty_or_broken_jpeg():
    cam = Camera("celular", "push")
    assert not cam.set_jpeg(b"")
    assert not cam.set_jpeg(b"nao e jpeg")
    assert cam.frame is None
