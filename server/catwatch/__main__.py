"""python -m catwatch [--data-dir PASTA] [--port N]

Códigos de saída (o app de PC usa para explicar o que houve):
  10  outro servidor Catwatch já está usando esta pasta de dados
  11  a porta já está ocupada
"""
import argparse
import os
import socket
import sys
from pathlib import Path

EXIT_DATA_BUSY = 10
EXIT_PORT_BUSY = 11
LOCK_NAME = ".catwatch.lock"   # o app de PC lê o PID daqui para esperar um servidor que está iniciando

parser = argparse.ArgumentParser(prog="catwatch", description="Servidor do Catwatch")
parser.add_argument("--data-dir", default=".", help="pasta com config.yaml, banco, fotos e modelos (padrão: a atual)")
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

# Um servidor por pasta de dados: dois olhando as mesmas câmeras contariam cada visita duas
# vezes no mesmo banco. A trava é do sistema operacional, então some sozinha se o processo morrer.
lock = open(LOCK_NAME, "a+")
try:
    import fcntl
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except ImportError:  # Windows: sem fcntl
    import msvcrt
    try:
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        fail(EXIT_DATA_BUSY, "outro servidor Catwatch já está usando esta pasta de dados.")
except OSError:
    lock.seek(0)
    other = lock.read().strip() or "?"
    fail(EXIT_DATA_BUSY, f"outro servidor Catwatch (PID {other}) já está usando esta pasta de dados: {data_dir}")
lock.seek(0)
lock.truncate()
lock.write(str(os.getpid()))
lock.flush()

from catwatch import config as cfgm  # noqa: E402  (leve: só lê o config.yaml)

s = cfgm.load()["server"]
host, port = s.get("host", "0.0.0.0"), args.port or s.get("port", 8000)

# Confere a porta ANTES de carregar os modelos (uns 20 s): se estiver ocupada, avisa já.
probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
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
