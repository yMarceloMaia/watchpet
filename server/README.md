# Catwatch

Monitora os gatos por câmeras na rede local (IP cams, celulares, webcams USB):
detecta quem é cada gato e conta quantas vezes foi à caixa de areia, comeu ou bebeu.

- **Servidor** (esta pasta): Python, YOLO + embeddings, SQLite, API REST e painel web.
- **App de celular**: `../mobile` (Expo / React Native).
- **App de PC**: `../desktop` (Qt Quick).

## Rodar o servidor
O jeito mais fácil é pelo app de PC (aba **Servidor** → Iniciar), que também cuida
da bandeja, de iniciar com o sistema e das notificações. Pelo terminal:
```
uv venv --python 3.12 .venv && uv pip install -p .venv/bin/python -r requirements.txt
PYTHONPATH=. .venv/bin/python -m catwatch [--data-dir PASTA] [--port N]
```
`--data-dir` é onde ficam `config.yaml`, banco, fotos e modelos (padrão: a pasta atual).
Sem o app, para iniciar com o PC: `deploy/catwatch.service` (systemd --user).

## Instalar em outro Linux
`deploy/make-linux-bundle.sh` gera `dist/catwatch-linux-<versão>.tar.gz` (servidor + app de PC
+ instalador, ~6 MB). No outro PC: extrair e rodar `./install.sh` (veja `deploy/linux/LEIA-ME.txt`).
Para levar gatos e histórico: backup .zip pela aba Servidor e `./install.sh --restore backup.zip`.

## O que o servidor oferece
- Detecção (YOLO) e identificação (ResNet50) na placa de vídeo NVIDIA quando existe.
- Foto de cada visita, certeza da identificação e votos por gato.
- Alertas: não bebeu água ou não comeu até certa hora, sem ir à caixa há muitas horas,
  excesso de idas à caixa no dia, câmera sem imagem. Não repetem no mesmo dia.
- Log de eventos, configurações pela API, QR code de pareamento, exportação CSV e backup .zip.

## Passo a passo
1. Abra o painel (web, celular ou PC) e informe o token.
2. **Câmeras → Adicionar**: `rtsp://...`, `http://IP:8080/video` (app *IP Webcam*), `0` (USB) ou `push` (celular com o app Catwatch, aba Câmera).
3. **Editar zonas**: desenhe sobre a imagem a caixa de areia, o comedouro e o bebedouro.
4. **Gatos**: cadastre cada gato com 15–30 fotos (ou "foto da câmera" com o gato à vista).
5. As visitas aparecem em *Hoje* e *Histórico*. Se errar o gato, corrija em *Histórico → trocar gato*.

## Como conta
Uma visita só conta quando o **mesmo gato fica** na zona pelo tempo mínimo do tipo:
15 s na caixa de areia, 8 s na comida, 5 s na água. O tempo que vale é o de presença
real (quadros seguidos com o gato), então passar pela zona não conta. A visita acaba
depois de um tempo sem ver o gato: 30 s na caixa (ele some ao se agachar), 15 s na
comida e 10 s na água.

Quadros em que a identificação falha ("desconhecido") e trocas raras de nome contam para
o gato que lidera a visita. Dois gatos juntos na mesma imagem são contados cada um.
Tudo ajustável no app de PC (Servidor → Configurações → Visitas) ou em `visits:` no `config.yaml`.

## Limites
A câmera não distingue "comendo" de "parado ao lado": vale o tempo dentro da zona. Gatos de pelagem parecida exigem mais fotos.
O token protege a API na rede local; para acesso de fora de casa use uma VPN (ex.: Tailscale) em vez de abrir a porta.

## Testes
`PYTHONPATH=. .venv/bin/python -m pytest tests`
