#!/usr/bin/env bash
# Monta dist/catwatch-linux-<versão>.tar.gz: servidor + app de PC + instalador.
# Roda num Arch (precisa do makepkg para gerar o pacote do app).
#
#   deploy/make-linux-bundle.sh            (usa ../desktop, o app de PC do repositório)
#   DESKTOP_DIR=/outro/caminho deploy/make-linux-bundle.sh
set -euo pipefail

PET="$(cd "$(dirname "$0")/.." && pwd)"
DESKTOP="${DESKTOP_DIR:-$PET/../desktop}"
[ -f "$DESKTOP/catwatch.pro" ] || { echo "app de PC não encontrado em $DESKTOP (defina DESKTOP_DIR)"; exit 1; }
DESKTOP="$(cd "$DESKTOP" && pwd)"
VERSION="$(sed -n 's/^pkgver=//p' "$DESKTOP/pkgbuild/PKGBUILD")"
NAME="catwatch-linux-$VERSION"
STAGE="$PET/build/$NAME"
OUT="$PET/dist/$NAME.tar.gz"

echo "==> Gerando o pacote do app de PC ($VERSION)"
(cd "$DESKTOP/pkgbuild" && makepkg -f >/dev/null)
PKG="$(ls "$DESKTOP"/pkgbuild/catwatch-"$VERSION"-*-x86_64.pkg.tar.zst | grep -v debug | head -1)"

echo "==> Montando $NAME"
rm -rf "$STAGE"; mkdir -p "$STAGE"/{server,app,app-src/pkgbuild}
cp "$PET"/deploy/linux/{install.sh,uninstall.sh,LEIA-ME.txt} "$STAGE/"
# Servidor: só o código e o modelo de detecção; nunca config.yaml, data/ ou token (são do usuário).
cp -r "$PET/catwatch" "$STAGE/server/"
find "$STAGE/server" -name __pycache__ -prune -exec rm -rf {} +
cp "$PET/requirements.txt" "$STAGE/server/"
# O modelo de detecção não vai para o git; o servidor baixa na primeira execução.
[ -f "$PET/yolov8n.pt" ] || (cd "$PET" && .venv/bin/python -c "from ultralytics import YOLO; YOLO('yolov8n.pt')" >/dev/null)
cp "$PET/yolov8n.pt" "$STAGE/server/"
cp "$PKG" "$STAGE/app/"
# Fonte do app, para compilar em distros que não são Arch.
cp -r "$DESKTOP/src" "$DESKTOP/catwatch.pro" "$DESKTOP/LICENSE" "$STAGE/app-src/"
cp "$DESKTOP"/pkgbuild/catwatch.{svg,desktop} "$STAGE/app-src/pkgbuild/"

mkdir -p "$PET/dist"
tar -C "$PET/build" -czf "$OUT" "$NAME"
rm -rf "$STAGE"
echo "==> Pronto: $OUT ($(du -h "$OUT" | cut -f1))"
