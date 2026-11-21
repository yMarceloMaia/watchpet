# -*- mode: python -*-
# PyInstaller: pyinstaller deploy/windows/catwatch-server.spec  (rode dentro de server/,
# depois de deploy/windows/prepare_models.py). Gera dist/catwatch-server/ (pasta, não arquivo
# único: com o PyTorch, um .exe único descompactaria ~1 GB a cada vez que abrisse).
import os
from PyInstaller.utils.hooks import collect_all, collect_data_files, collect_submodules

root = os.path.abspath(os.path.join(SPECPATH, "..", ".."))

datas = [
    (os.path.join(root, "catwatch", "static"), "catwatch/static"),   # painel web
    (os.path.join(root, "models"), "models"),                         # YOLO e ResNet50
]
datas += collect_data_files("ultralytics")                            # configurações dos modelos
hiddenimports = collect_submodules("uvicorn") + collect_submodules("catwatch")
binaries = []
# O torchvision traz uma biblioteca nativa (_C: o NMS que o YOLO usa) que o PyInstaller não
# acha sozinho; sem ela o servidor morre com "operator torchvision::nms does not exist".
tv_datas, tv_binaries, tv_hidden = collect_all("torchvision")
datas += tv_datas
binaries += tv_binaries
hiddenimports += tv_hidden

a = Analysis(
    [os.path.join(root, "deploy", "windows", "entry.py")],
    pathex=[root],
    datas=datas,
    binaries=binaries,
    hiddenimports=hiddenimports,
    excludes=["tkinter", "IPython", "jupyter", "notebook", "tensorboard"],
)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name="catwatch-server", console=True)
coll = COLLECT(exe, a.binaries, a.datas, name="catwatch-server")
