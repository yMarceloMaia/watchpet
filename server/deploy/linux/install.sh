#!/usr/bin/env bash
# Instala o Catwatch neste Linux: o servidor (Python + IA) e o app de PC.
#
#   ./install.sh                 instala tudo (detecta placa NVIDIA sozinho)
#   ./install.sh --cpu           servidor sem placa de vídeo (download bem menor)
#   ./install.sh --restore ARQ   traz gatos, histórico e fotos de um backup .zip do app
#   ./install.sh --help          todas as opções
#
# Pode rodar de novo para atualizar: config.yaml e data/ (gatos, histórico, fotos) são mantidos.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${CATWATCH_PREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/catwatch}"
SERVER="$PREFIX/server"
BIN_DIR="${CATWATCH_BIN_DIR:-$HOME/.local/bin}"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
DEVICE=auto   # auto | gpu | cpu
APP=auto      # auto | pkg | source | none
RESTORE=""
YES=0

say()  { printf '\n\033[1;33m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31mErro:\033[0m %s\n' "$*" >&2; exit 1; }
ask()  {
    [ "$YES" = 1 ] && return 0
    local a; read -r -p "  $1 [S/n] " a || true
    [[ -z "$a" || "$a" =~ ^[sSyY] ]]
}

usage() {
    cat <<EOF
Uso: ./install.sh [opções]

  --cpu               servidor só com CPU (PyTorch ~1 GB em vez de ~5 GB)
  --gpu               força a versão com placa de vídeo NVIDIA (CUDA)
  --restore ARQUIVO   restaura um backup (.zip gerado em Servidor → Backup completo,
                      ou uma pasta data/ de outra instalação)
  --no-app            instala só o servidor
  --app-from-source   compila o app de PC em vez de usar o pacote do Arch
  -y, --yes           não pergunta nada (aceita tudo)

Servidor em: $SERVER
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --cpu) DEVICE=cpu ;;
        --gpu) DEVICE=gpu ;;
        --restore) shift; RESTORE="${1:-}"; [ -n "$RESTORE" ] || die "--restore precisa de um arquivo" ;;
        --no-app) APP=none ;;
        --app-from-source) APP=source ;;
        -y|--yes) YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; die "opção desconhecida: $1" ;;
    esac
    shift
done

[ "$(uname -s)" = Linux ] || die "este instalador é para Linux."
[ -f "$HERE/server/catwatch/__main__.py" ] || die "pacote incompleto: falta server/catwatch (extraia o .tar.gz inteiro)."
if [ -n "$RESTORE" ]; then
    RESTORE="$(cd "$(dirname "$RESTORE")" && pwd)/$(basename "$RESTORE")"
    [ -e "$RESTORE" ] || die "backup não encontrado: $RESTORE"
fi

printf '\033[1m🐱 Catwatch — instalação\033[0m\n'
echo "  Servidor:  $SERVER"

# ---------------------------------------------------------------- servidor rodando?
PY="$SERVER/.venv/bin/python"
if pgrep -f "$SERVER/.venv/bin/python -m catwatch" >/dev/null 2>&1; then
    say "Um servidor Catwatch desta instalação está rodando"
    ask "Encerrar para atualizar?" || die "feche o servidor e rode de novo."
    pkill -INT -f "$SERVER/.venv/bin/python -m catwatch" || true
    for _ in $(seq 1 20); do pgrep -f "$SERVER/.venv/bin/python -m catwatch" >/dev/null || break; sleep 0.5; done
    ok "servidor encerrado"
fi

# ---------------------------------------------------------------- uv (Python)
say "Python"
if ! command -v uv >/dev/null 2>&1; then
    [ -x "$HOME/.local/bin/uv" ] && export PATH="$HOME/.local/bin:$PATH"
fi
if ! command -v uv >/dev/null 2>&1; then
    warn "o uv (gerenciador de Python da Astral) não está instalado"
    ask "Instalar o uv em ~/.local/bin?" || die "instale o uv (https://docs.astral.sh/uv/) e rode de novo."
    command -v curl >/dev/null || die "preciso do curl para baixar o uv."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi
ok "uv $(uv --version | awk '{print $2}')"

# ---------------------------------------------------------------- código do servidor
say "Copiando o servidor"
mkdir -p "$SERVER"
rm -rf "$SERVER/catwatch"
cp -r "$HERE/server/catwatch" "$SERVER/catwatch"
find "$SERVER/catwatch" -name __pycache__ -prune -exec rm -rf {} +
cp "$HERE/server/requirements.txt" "$SERVER/requirements.txt"
[ -f "$SERVER/yolov8n.pt" ] || cp "$HERE/server/yolov8n.pt" "$SERVER/yolov8n.pt"
ok "código em $SERVER (config.yaml e data/ preservados)"

# ---------------------------------------------------------------- ambiente Python
say "Instalando bibliotecas (a primeira vez demora: PyTorch é grande)"
if [ "$DEVICE" = auto ]; then
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
        DEVICE=gpu; ok "placa NVIDIA encontrada: $(nvidia-smi -L | head -1 | sed 's/ (UUID.*//')"
    else
        DEVICE=cpu; ok "sem placa NVIDIA: instalando a versão para CPU"
    fi
fi
[ -x "$PY" ] || uv venv --quiet --python 3.12 "$SERVER/.venv"
if [ "$DEVICE" = cpu ]; then
    # A versão CPU do PyTorch vem de um índice próprio e é ~5× menor que a CUDA.
    reinstall=()
    if "$PY" -c "import torch,sys; sys.exit(0 if torch.version.cuda else 1)" 2>/dev/null; then
        reinstall=(--reinstall-package torch --reinstall-package torchvision)
    fi
    uv pip install -p "$PY" "${reinstall[@]}" torch torchvision --index-url https://download.pytorch.org/whl/cpu
fi
uv pip install -p "$PY" -r "$SERVER/requirements.txt"

ACCEL=$("$PY" - <<'EOF'
import torch, torchvision, ultralytics, cv2, fastapi, qrcode, psutil  # noqa: F401  (tudo importa?)
print("placa de vídeo (" + torch.cuda.get_device_name(0) + ")" if torch.cuda.is_available() else "CPU")
EOF
) || die "as bibliotecas não carregaram; veja as mensagens acima."
ACCEL="$(tail -1 <<<"$ACCEL")"  # o Ultralytics imprime um aviso de primeiro uso antes
ok "bibliotecas ok — processamento: $ACCEL"

# Baixa agora o modelo de identificação (~100 MB), para o primeiro início não demorar.
"$PY" -c "import torchvision; torchvision.models.resnet50(weights='DEFAULT')" >/dev/null 2>&1 \
    && ok "modelo de identificação pronto" || warn "não baixei o modelo agora; o servidor baixa ao iniciar"

# ---------------------------------------------------------------- restaurar backup
if [ -n "$RESTORE" ]; then
    say "Restaurando backup"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    if [ -d "$RESTORE" ]; then
        src="$RESTORE"; [ -d "$src/data" ] || { mkdir -p "$tmp/data" && cp -r "$src/." "$tmp/data/" && src="$tmp"; }
    else
        "$PY" -m zipfile -e "$RESTORE" "$tmp" || die "não consegui abrir $RESTORE como .zip"
        src="$tmp"
    fi
    [ -f "$src/data/catwatch.db" ] || die "o backup não tem data/catwatch.db"
    if [ -d "$SERVER/data" ]; then
        old="$SERVER/data.antes-$(date +%Y%m%d-%H%M%S)"
        mv "$SERVER/data" "$old"
        warn "dados que já existiam guardados em $old"
    fi
    cp -r "$src/data" "$SERVER/data"
    if [ -f "$src/config.yaml" ]; then
        [ -f "$SERVER/config.yaml" ] && cp "$SERVER/config.yaml" "$SERVER/config.yaml.antes-restore"
        cp "$src/config.yaml" "$SERVER/config.yaml"
    fi
    n_cats=$(find "$SERVER/data/cats" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    ok "restaurado: $n_cats gatos, histórico e fotos"
    warn "o backup não leva o token: celulares conectam de novo pelo QR code (aba Servidor)"
fi

# ---------------------------------------------------------------- app de PC
find_qmake() {
    for q in qmake6 qmake-qt6 /usr/lib/qt6/bin/qmake /usr/lib64/qt6/bin/qmake /usr/lib/x86_64-linux-gnu/qt6/bin/qmake; do
        command -v "$q" >/dev/null 2>&1 && { echo "$q"; return; }
    done
}
PKG="$(ls "$HERE"/app/catwatch-[0-9]*.pkg.tar.zst 2>/dev/null | head -1 || true)"
if [ "$APP" = auto ]; then
    if command -v pacman >/dev/null 2>&1 && [ -n "$PKG" ] && [ "$(uname -m)" = x86_64 ]; then APP=pkg
    elif [ -n "$(find_qmake)" ]; then APP=source
    else APP=missing
    fi
fi

case "$APP" in
pkg)
    say "Instalando o app de PC (pacote do Arch)"
    if ask "Instalar $(basename "$PKG") com sudo pacman?"; then
        sudo pacman -U --needed --noconfirm "$PKG"
        ok "app instalado (procure “Catwatch” no launcher)"
    else
        warn "app não instalado; depois: sudo pacman -U $PKG"
    fi
    ;;
source)
    say "Compilando o app de PC"
    QMAKE="$(find_qmake)"
    [ -n "$QMAKE" ] || die "não achei o qmake do Qt 6 (instale os pacotes de desenvolvimento do Qt 6)."
    build="$PREFIX/app-build"
    rm -rf "$build"; mkdir -p "$build"
    (cd "$build" && "$QMAKE" "$HERE/app-src/catwatch.pro" >/dev/null && make -j"$(nproc)" >/dev/null) \
        || die "a compilação falhou. Faltam pacotes do Qt 6? Veja LEIA-ME.txt."
    install -Dm755 "$build/catwatch" "$BIN_DIR/catwatch"
    install -Dm644 "$HERE/app-src/pkgbuild/catwatch.svg" "$ICONS_DIR/catwatch.svg"
    mkdir -p "$APPS_DIR"
    sed "s|^Exec=.*|Exec=$BIN_DIR/catwatch|" "$HERE/app-src/pkgbuild/catwatch.desktop" > "$APPS_DIR/catwatch.desktop.tmp"
    mv "$APPS_DIR/catwatch.desktop.tmp" "$APPS_DIR/catwatch.desktop"
    command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" 2>/dev/null || true
    rm -rf "$build"
    ok "app instalado em $BIN_DIR/catwatch (e no launcher)"
    ;;
missing)
    warn "não instalei o app de PC: este sistema não é Arch e não tem o Qt 6 para compilar."
    warn "Veja LEIA-ME.txt para instalar o Qt 6, ou use o painel web do servidor."
    ;;
none) ;;
esac

# ---------------------------------------------------------------- fim
# O desinstalador fica junto da instalação: a pasta do pacote pode ser apagada depois.
cp "$HERE/uninstall.sh" "$PREFIX/uninstall.sh" && chmod +x "$PREFIX/uninstall.sh"
say "Pronto!"
cat <<EOF
  1. Abra o Catwatch (launcher ou: catwatch).
  2. Clique em “Iniciar o servidor deste PC”.
  3. Na aba Servidor, leia o QR code com o app do celular.

  Servidor sem o app (terminal ou systemd):
    PYTHONPATH="$SERVER" "$PY" -m catwatch --data-dir "$SERVER"

  Para desinstalar: $PREFIX/uninstall.sh
EOF
