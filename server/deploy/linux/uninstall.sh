#!/usr/bin/env bash
# Remove o Catwatch. Por padrão mantém os dados (gatos, histórico, fotos, config).
#   --tudo          apaga também os dados
#   --so-servidor   remove só o servidor; o app de PC fica
set -euo pipefail

PREFIX="${CATWATCH_PREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/catwatch}"
SERVER="$PREFIX/server"
BIN_DIR="${CATWATCH_BIN_DIR:-$HOME/.local/bin}"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/catwatch.desktop"
ALL=0; YES=0; APP=1
for a in "$@"; do
    case "$a" in
        --tudo|--all) ALL=1 ;;
        --so-servidor|--server-only) APP=0 ;;
        -y|--yes) YES=1 ;;
        -h|--help) echo "Uso: uninstall.sh [--tudo] [--so-servidor] [-y]"; exit 0 ;;
    esac
done
ask() { [ "$YES" = 1 ] && return 0; local a; read -r -p "$1 [s/N] " a || true; [[ "$a" =~ ^[sSyY] ]]; }

[ "$APP" = 1 ] && echo "Isto remove o app de PC e o servidor do Catwatch." || echo "Isto remove o servidor do Catwatch (o app de PC fica)."
[ "$ALL" = 1 ] && echo "ATENÇÃO: --tudo apaga também gatos cadastrados, histórico e fotos ($SERVER/data)."
ask "Continuar?" || exit 0

pkill -INT -f "$SERVER/.venv/bin/python -m catwatch" 2>/dev/null || true

if [ "$APP" = 1 ]; then
    # Só os binários instalados por este instalador (não um Catwatch compilado em outra pasta).
    for exe in "$BIN_DIR/catwatch" /usr/bin/catwatch; do
        pkill -f "^$exe( |$)" 2>/dev/null || true
    done
    if command -v pacman >/dev/null 2>&1 && pacman -Q catwatch >/dev/null 2>&1; then
        sudo pacman -R --noconfirm catwatch
    fi
    rm -f "$BIN_DIR/catwatch" "$APPS_DIR/catwatch.desktop" "$ICONS_DIR/catwatch.svg" "$AUTOSTART"
fi

if [ "$ALL" = 1 ]; then
    rm -rf "$PREFIX"
    echo "Catwatch removido, incluindo os dados."
else
    rm -rf "$SERVER/.venv" "$SERVER/catwatch" "$SERVER/requirements.txt" "$SERVER/yolov8n.pt" "$PREFIX/app-build"
    echo "Catwatch removido. Dados mantidos em $SERVER (config.yaml e data/)."
    echo "Reinstalar depois os reaproveita; para apagar: rm -rf \"$PREFIX\""
fi
