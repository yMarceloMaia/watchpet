"""python -m catwatch [--data-dir PASTA] [--port N]   (ou catwatch-server.exe, empacotado)

Códigos de saída (o app de PC usa para explicar o que houve):
  10  outro servidor Catwatch já está usando esta pasta de dados
  11  a porta já está ocupada
"""
import argparse
import os
import shutil
import socket
import sys
from pathlib import Path

EXIT_DATA_BUSY = 10
EXIT_PORT_BUSY = 11
LOCK_NAME = ".catwatch.lock"   # o app de PC lê o PID daqui para esperar um servidor que está iniciando

# Empacotado (PyInstaller): o programa e os modelos ficam em sys._MEIPASS, que é só leitura.
FROZEN = getattr(sys, "frozen", False)
BUNDLE = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent.parent))


def default_data_dir() -> str:
    if not FROZEN:
        return "."
    if os.name == "nt":  # C:\Users\<voce>\AppData\Local\Catwatch
        return str(Path(os.environ.get("LOCALAPPDATA", Path.home())) / "Catwatch")
    return str(Path.home() / ".local" / "share" / "catwatch" / "server")


parser = argparse.ArgumentParser(prog="catwatch", description="Servidor do Catwatch")
parser.add_argument("--data-dir", default=default_data_dir(),
                    help="pasta com config.yaml, banco e fotos (padrão: a atual; no executável, a pasta do usuário)")
parser.add_argument("--port", type=int, help="porta HTTP (sobrepõe o config.yaml)")
args = parser.parse_args()


def fail(code: int, message: str):
    print(f"catwatch: {message}", file=sys.stderr, flush=True)
    sys.exit(code)


# O pacote precisa continuar importável depois do chdir para a pasta de dados.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
data_dir = Path(args.data_dir).expanduser().resolve()
data_dir.mkdir(parents=True, exist_ok=True)
os.chdir(data_dir)

if FROZEN:
    # Modelos embutidos no executável: funciona sem internet desde a primeira vez.
    models = BUNDLE / "models"
    os.environ.setdefault("TORCH_HOME", str(models / "torch"))  # pesos da ResNet50
    if (models / "yolov8n.pt").exists() and not Path("yolov8n.pt").exists():
        shutil.copy(models / "yolov8n.pt", "yolov8n.pt")       # o config aponta para a pasta de dados

# Um servidor por pasta de dados: dois olhando as mesmas câmeras contariam cada visita duas
# vezes no mesmo banco. A trava é do sistema operacional, então some sozinha se o processo morrer.
lock = open(LOCK_NAME, "a+")
try:
    import fcntl
except ImportError:  # Windows
    import msvcrt
    try:
        # Trava um byte longe do começo: o PID fica no começo, legível por quem quiser esperar.
        lock.seek(4096)
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        lock.seek(0)
        fail(EXIT_DATA_BUSY, f"outro servidor Catwatch (PID {lock.read(32).strip() or '?'}) já está usando esta pasta de dados: {data_dir}")
else:
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        lock.seek(0)
        fail(EXIT_DATA_BUSY, f"outro servidor Catwatch (PID {lock.read().strip() or '?'}) já está usando esta pasta de dados: {data_dir}")
lock.seek(0)
lock.truncate()
lock.write(str(os.getpid()))
lock.flush()

from catwatch import config as cfgm  # noqa: E402  (leve: só lê o config.yaml)

s = cfgm.load()["server"]
host, port = s.get("host", "0.0.0.0"), args.port or s.get("port", 8000)

# Confere a porta ANTES de carregar os modelos (uns 20 s): se estiver ocupada, avisa já.
# No Windows, SO_REUSEADDR deixaria abrir uma porta ocupada; lá o certo é o uso exclusivo.
probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
if os.name == "nt":
    probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
else:
    probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    probe.bind((host, port))
except OSError:
    fail(EXIT_PORT_BUSY, f"a porta {port} já está em uso (outro servidor Catwatch ou outro programa).")
finally:
    probe.close()

import uvicorn  # noqa: E402

from catwatch import web  # noqa: E402  (carrega modelos e câmeras)

web.cfg["_port"] = port
uvicorn.run(web.app, host=host, port=port, log_level="warning")
