import base64
import csv
import io
import json
import os
import re
import shutil
import signal
import socket
import sqlite3
import tempfile
import threading
import time
import zipfile
from urllib.parse import quote
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np
import psutil
import qrcode
from fastapi import Depends, FastAPI, File, Header, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, Response, StreamingResponse
from pydantic import BaseModel
from starlette.background import BackgroundTask

from . import config as cfgm
from . import db as dbm
from .monitor import Monitor
from .vision import CatDetector, CatIdentifier, gpu_memory_mb, gpu_name, resolve_device
from .worker import Pipeline

VERSION = "1.1"
STARTED = time.time()
cfg = cfgm.load()
det = cfg["detection"]
DEVICE = resolve_device(det.get("device", "auto"))
pipe = Pipeline(cfg, CatDetector(det["model"], det["confidence"], DEVICE),
                CatIdentifier(cfg["gallery"], det["identify_threshold"], DEVICE))
monitor = Monitor(cfg, pipe)
monitor.start()
GALLERY = Path(cfg["gallery"])
dbm.add_event(pipe.db, "server", f"Servidor iniciado ({'placa de vídeo' if DEVICE == 'cuda' else 'CPU'})")
print(f"\n  Token de acesso: {cfg['server']['token']}\n", flush=True)


def auth(request: Request, x_token: str | None = Header(None), token: str | None = Query(None)):
    # Lido a cada requisição: o token pode ser trocado em tempo de execução.
    if (x_token or token) != cfg["server"]["token"]:
        raise HTTPException(401, "token inválido")


app = FastAPI(title="catwatch")


@app.on_event("shutdown")
def save_open_visits():
    """Servidor encerrando: grava as visitas em andamento (quem estava na caixa ainda conta)."""
    pipe._save_flush(time.time(), force=True)
api = Depends(auth)


def safe_name(name: str) -> str:
    name = name.strip()
    if not re.fullmatch(r"[\w \-]{1,40}", name):
        raise HTTPException(400, "nome inválido (use letras, números, espaço, - e _)")
    return name


def day_start(date: str | None) -> float:
    d = datetime.fromisoformat(date) if date else datetime.now()
    return d.replace(hour=0, minute=0, second=0, microsecond=0).timestamp()


# ---------- info / auth ----------
@app.get("/api/info")
def info():
    return {"app": "catwatch", "version": VERSION, "cameras": len(pipe.cams)}


@app.get("/api/check", dependencies=[api])
def check():
    return {"ok": True}


# ---------- estatísticas ----------
@app.get("/api/today", dependencies=[api])
def today(date: str | None = None):
    s = day_start(date)
    return dbm.daily_counts(pipe.db, s, s + 86400)


@app.get("/api/stats", dependencies=[api])
def stats(days: int = Query(7, ge=1, le=365)):
    return dbm.stats(pipe.db, day_start(None) - (days - 1) * 86400)


@app.get("/api/recent", dependencies=[api])
def recent(limit: int = Query(50, le=500), cat: str | None = None, kind: str | None = None):
    rows = dbm.recent(pipe.db, limit, cat, kind)
    for r in rows:
        r["votes"] = json.loads(r["votes"]) if r.get("votes") else {}
        r["photo"] = bool(r.get("photo"))
    return rows


@app.get("/api/visits/{vid}/photo", dependencies=[api])
def visit_photo(vid: int):
    p = pipe.photo_path(vid)
    if not p.exists():
        raise HTTPException(404)
    return FileResponse(p, media_type="image/jpeg")


class CatBody(BaseModel):
    cat: str


@app.patch("/api/visits/{vid}", dependencies=[api])
def fix_visit(vid: int, body: CatBody):
    if not dbm.set_cat(pipe.db, vid, safe_name(body.cat)):
        raise HTTPException(404)
    return {"ok": True}


@app.delete("/api/visits/{vid}", dependencies=[api])
def del_visit(vid: int):
    if not dbm.delete_visit(pipe.db, vid):
        raise HTTPException(404)
    pipe.photo_path(vid).unlink(missing_ok=True)
    return {"ok": True}


# ---------- câmeras ----------
class Zone(BaseModel):
    name: str
    kind: str  # litter | food | water
    polygon: list[list[float]]


class CameraBody(BaseModel):
    name: str
    source: str  # rtsp://, http://, índice USB ou "push"
    zones: list[Zone] = []


@app.get("/api/cameras", dependencies=[api])
def cameras():
    return [{"name": c["name"], "source": c["source"], "zones": c["zones"],
             "online": pipe.cams[c["name"]].online if c["name"] in pipe.cams else False}
            for c in cfg["cameras"]]


@app.post("/api/cameras", dependencies=[api])
def add_camera(body: CameraBody):
    name = safe_name(body.name)
    if pipe.camera_cfg(name):
        raise HTTPException(409, "já existe uma câmera com esse nome")
    pipe.add_camera({"name": name, "source": body.source, "zones": [z.model_dump() for z in body.zones]})
    cfgm.save(cfg)
    return {"ok": True}


@app.delete("/api/cameras/{name}", dependencies=[api])
def del_camera(name: str):
    if not pipe.camera_cfg(name):
        raise HTTPException(404)
    pipe.remove_camera(name)
    cfgm.save(cfg)
    return {"ok": True}


@app.put("/api/cameras/{name}/zones", dependencies=[api])
def set_zones(name: str, zones: list[Zone]):
    c = pipe.camera_cfg(name)
    if c is None:
        raise HTTPException(404)
    for z in zones:
        if z.kind not in ("litter", "food", "water") or len(z.polygon) < 3:
            raise HTTPException(400, "zona inválida")
    c["zones"][:] = [z.model_dump() for z in zones]   # in-place: o pipeline enxerga na hora
    cfgm.save(cfg)
    return {"ok": True}


def _frame_jpeg(name: str, annotated: bool = True):
    frame = pipe.last_annotated.get(name) if annotated else None
    if frame is None and name in pipe.cams:
        frame = pipe.cams[name].frame
    if frame is None:
        return None
    ok, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 80])
    return buf.tobytes() if ok else None


@app.get("/snapshot/{camera}.jpg", dependencies=[api])
def snapshot(camera: str, raw: bool = False):
    data = _frame_jpeg(camera, annotated=not raw)
    if data is None:
        raise HTTPException(404, "câmera sem imagem")
    return Response(data, media_type="image/jpeg", headers={"Cache-Control": "no-store"})


@app.get("/stream/{camera}", dependencies=[api])
def stream(camera: str):
    def gen():
        while camera in pipe.cams:
            data = _frame_jpeg(camera)
            if data:
                yield b"--f\r\nContent-Type: image/jpeg\r\n\r\n" + data + b"\r\n"
            time.sleep(0.3)
    return StreamingResponse(gen(), media_type="multipart/x-mixed-replace; boundary=f")


@app.post("/api/push/{camera}", dependencies=[api])
async def push(camera: str, request: Request):
    """O app do celular envia JPEGs aqui; a câmera é criada (source=push) se não existir."""
    if camera not in pipe.cams:
        pipe.add_camera({"name": safe_name(camera), "source": "push", "zones": []})
        cfgm.save(cfg)
    data = await request.body()
    if not request.headers.get("content-type", "").startswith("image/"):
        # O app do celular manda base64 (mais confiável que Blob no React Native); aceita data URL.
        try:
            data = base64.b64decode(data.split(b",", 1)[-1], validate=False)
        except Exception:
            raise HTTPException(400, "base64 inválido")
    if not pipe.cams[camera].set_jpeg(data):
        raise HTTPException(400, f"JPEG inválido ({len(data)} bytes)")
    return {"ok": True}


# ---------- gatos ----------
def _imgs(d: Path):
    return sorted(p for p in d.glob("*.jpg"))


@app.get("/api/cats", dependencies=[api])
def cats():
    GALLERY.mkdir(parents=True, exist_ok=True)
    return [{"name": d.name, "photos": len(_imgs(d))} for d in sorted(GALLERY.iterdir()) if d.is_dir()]


def _save_cat_image(name: str, img) -> int:
    d = GALLERY / safe_name(name)
    d.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(d / f"{int(time.time() * 1000)}.jpg"), img)
    with pipe._infer:
        pipe.identifier.add(d.name, img)
    return len(_imgs(d))


@app.post("/api/cats/{name}/photos", dependencies=[api])
async def add_photo(name: str, photo: UploadFile = File(...)):
    img = cv2.imdecode(np.frombuffer(await photo.read(), np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(400, "imagem inválida")
    # Se a foto tem um gato, recorta; senão usa inteira.
    with pipe._infer:
        boxes = pipe.detector(img)
    if boxes:
        x1, y1, x2, y2, _ = max(boxes, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]))
        img = img[max(y1, 0):y2, max(x1, 0):x2]
    return {"photos": _save_cat_image(name, img)}


@app.post("/api/cats/{name}/from-camera/{camera}", dependencies=[api])
def photo_from_camera(name: str, camera: str):
    crop = pipe.cat_crop(camera)
    if crop is None or crop.size == 0:
        raise HTTPException(404, "nenhum gato visível nessa câmera agora")
    return {"photos": _save_cat_image(name, crop)}


@app.get("/api/cats/{name}/thumb", dependencies=[api])
def thumb(name: str):
    imgs = _imgs(GALLERY / safe_name(name))
    if not imgs:
        raise HTTPException(404)
    return FileResponse(imgs[-1])


@app.delete("/api/cats/{name}", dependencies=[api])
def del_cat(name: str):
    d = GALLERY / safe_name(name)
    if not d.is_dir():
        raise HTTPException(404)
    shutil.rmtree(d)
    pipe.identifier.remove(d.name)
    return {"ok": True}


# ---------- servidor: status, eventos, configurações, dados ----------
_proc = psutil.Process()
_proc.cpu_percent(None)  # a primeira leitura sempre dá 0; as seguintes medem desde a anterior


def current_port() -> int:
    return cfg.get("_port") or cfg["server"]["port"]


def lan_addresses() -> list[str]:
    """Endereços pelos quais o celular alcança este servidor; o da rota padrão vem primeiro."""
    ips = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("192.0.2.1", 9))  # não envia nada; só descobre qual interface seria usada
        ips.append(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    for name, addrs in psutil.net_if_addrs().items():
        if name.startswith(("lo", "docker", "virbr", "br-", "veth")):
            continue
        for a in addrs:
            if a.family == socket.AF_INET and not a.address.startswith("127.") and a.address not in ips:
                ips.append(a.address)
    return [f"http://{ip}:{current_port()}" for ip in ips]


@app.get("/api/status", dependencies=[api])
def status():
    s = day_start(None)
    return {
        "version": VERSION,
        "uptime": time.time() - STARTED,
        "pid": os.getpid(),
        "data_dir": os.getcwd(),
        "port": current_port(),
        "device": DEVICE,
        "device_setting": cfg["detection"]["device"],
        "gpu": gpu_name(),
        "gpu_memory_mb": gpu_memory_mb(),
        "cpu_percent": _proc.cpu_percent(None) / (psutil.cpu_count() or 1),
        "ram_mb": _proc.memory_info().rss / 2**20,
        "cameras_total": len(pipe.cams),
        "cameras_online": sum(c.online for c in pipe.cams.values()),
        "infer_ms": round(pipe.infer_ms, 1),
        "frames_analyzed": pipe.frames_analyzed,
        "visits_today": sum(r["n"] for r in dbm.daily_counts(pipe.db, s, s + 86400)),
        "cats": len([d for d in GALLERY.iterdir() if d.is_dir()]) if GALLERY.exists() else 0,
        "restart_required": bool(cfg.get("_restart")),
        "addresses": lan_addresses(),
    }


@app.get("/api/events", dependencies=[api])
def events(after: int | None = None, limit: int = Query(100, ge=1, le=500), type: str | None = None,
           since: float | None = None):
    return dbm.events(pipe.db, after, limit, type, since)


@app.get("/api/settings", dependencies=[api])
def get_settings():
    return cfgm.settings(cfg)


@app.put("/api/settings", dependencies=[api])
def put_settings(changes: dict):
    errors, restart = cfgm.apply_settings(cfg, changes)
    if errors:
        raise HTTPException(400, "; ".join(errors))
    # O que dá pra aplicar sem reiniciar, aplica na hora.
    pipe.tracker.configure(*cfgm.visit_rules(cfg))
    pipe.detector.conf = cfg["detection"]["confidence"]
    pipe.identifier.threshold = cfg["detection"]["identify_threshold"]
    if restart:
        cfg["_restart"] = True
    dbm.add_event(pipe.db, "server", "Configurações alteradas" + (" (reinicie o servidor para aplicar tudo)" if restart else ""))
    return {"restart_required": bool(cfg.get("_restart")), "settings": cfgm.settings(cfg)}


@app.post("/api/token/regenerate", dependencies=[api])
def regenerate_token():
    new = cfgm.regenerate_token(cfg)
    dbm.add_event(pipe.db, "server", "Token de acesso trocado: celulares e outros PCs precisam conectar de novo", "warn")
    return {"token": new}


def pair_uri() -> str:
    urls = lan_addresses() or [f"http://localhost:{current_port()}"]
    return f"catwatch://pair?u={quote(urls[0], safe='')}&t={quote(cfg['server']['token'], safe='')}"


@app.get("/api/pair", dependencies=[api])
def pair():
    return {"urls": lan_addresses(), "token": cfg["server"]["token"], "uri": pair_uri()}


@app.get("/api/pair.png", dependencies=[api])
def pair_png():
    """QR code que o app do celular lê para conectar sem digitar endereço e token."""
    buf = io.BytesIO()
    qrcode.make(pair_uri(), box_size=8, border=2).save(buf, format="PNG")
    return Response(buf.getvalue(), media_type="image/png", headers={"Cache-Control": "no-store"})


@app.get("/api/export/visits.csv", dependencies=[api])
def export_csv():
    out = io.StringIO()
    w = csv.writer(out)
    w.writerow(["id", "inicio", "fim", "duracao_s", "presenca_s", "gato", "tipo", "zona", "camera",
                "certeza", "deteccao", "quadros", "votos"])
    names = {"litter": "caixa de areia", "food": "comida", "water": "água"}
    fmt = lambda t: datetime.fromtimestamp(t).isoformat(sep=" ", timespec="seconds")
    for r in dbm.visits_csv_rows(pipe.db):
        w.writerow([r["id"], fmt(r["start"]), fmt(r["end"]), round(r["end"] - r["start"]),
                    "" if r["presence"] is None else round(r["presence"]), r["cat"],
                    names.get(r["kind"], r["kind"]), r["zone"], r["camera"],
                    "" if r["score"] is None else round(r["score"], 3),
                    "" if r["conf"] is None else round(r["conf"], 3), r["frames"] or "", r["votes"] or ""])
    # BOM para o Excel abrir os acentos certo.
    return Response("\ufeff" + out.getvalue(), media_type="text/csv; charset=utf-8",
                    headers={"Content-Disposition": 'attachment; filename="catwatch-visitas.csv"'})


@app.get("/api/backup.zip", dependencies=[api])
def backup():
    """Banco, fotos das visitas, galeria dos gatos e config.yaml (sem o token) num .zip."""
    tmp = Path(tempfile.mkdtemp(prefix="catwatch-backup-"))
    db_copy = tmp / "catwatch.db"
    dst = sqlite3.connect(db_copy)
    with dbm._lock:
        pipe.db.backup(dst)  # cópia consistente mesmo com o servidor gravando
    dst.close()
    zpath = tmp / "catwatch-backup.zip"
    data = Path(cfg["db"]).parent
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(db_copy, "data/catwatch.db")
        if Path(cfg["_path"]).exists():
            z.write(cfg["_path"], "config.yaml")
        for folder in (GALLERY, data / "snapshots"):
            for f in folder.rglob("*") if folder.exists() else []:
                if f.is_file():
                    # Caminhos do config são relativos à pasta de dados (o cwd); mantém a estrutura.
                    arc = f.resolve().relative_to(Path.cwd()) if f.resolve().is_relative_to(Path.cwd()) else Path(folder.name) / f.relative_to(folder)
                    z.write(f, arc.as_posix())
    name = f"catwatch-backup-{datetime.now():%Y%m%d-%H%M}.zip"
    return FileResponse(zpath, media_type="application/zip", filename=name,
                        background=BackgroundTask(shutil.rmtree, tmp, ignore_errors=True))


@app.post("/api/shutdown", dependencies=[api])
def shutdown(request: Request):
    """Encerra o servidor; só aceito do próprio PC (o app de PC usa para parar/reiniciar)."""
    if request.client is None or request.client.host not in ("127.0.0.1", "::1"):
        raise HTTPException(403, "só pode ser encerrado pelo próprio computador")
    dbm.add_event(pipe.db, "server", "Servidor encerrado")
    threading.Timer(0.5, lambda: os.kill(os.getpid(), signal.SIGINT)).start()
    return {"ok": True}


# ---------- painel web ----------
@app.get("/", response_class=HTMLResponse)
def index():
    return (Path(__file__).parent / "static" / "index.html").read_text()
