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
   O RTSP é lido por TCP (por UDP, pacotes perdidos borram ou travam a imagem); para outra
   opção, defina `OPENCV_FFMPEG_CAPTURE_OPTIONS` antes de abrir o servidor.
3. **Editar zonas**: desenhe sobre a imagem a caixa de areia, o comedouro e o bebedouro.
4. **Gatos**: cadastre cada gato com 15–30 fotos (ou "foto da câmera" com o gato à vista).
5. As visitas aparecem em *Hoje* e *Histórico*. Se errar o gato, corrija em *Histórico → trocar gato*.

## Como conta
Uma visita só conta quando o **mesmo gato fica** na zona pelo tempo mínimo do tipo:
15 s na caixa de areia, 8 s na comida, 5 s na água. O tempo que vale é o de presença
real (quadros seguidos com o gato), então passar pela zona não conta. A visita acaba
depois de um tempo sem ver o gato: 30 s na caixa (ele some ao se agachar), 15 s na
comida e 10 s na água.

Quadros em que a identificação falha ("desconhecido") e trocas de nome contam para o gato
que lidera a visita: um nome que oscila entre dois gatos parecidos não parte a visita (um
trecho curto demais para ser visita sozinho se junta ao vizinho). Dois gatos seguidos, cada
um com o tempo mínimo, são duas visitas; dois gatos juntos na mesma imagem também.

O detector procura gatos na resolução da câmera (até 1280 px de lado). Na resolução padrão
dele (640), um gato pequeno numa câmera HD vista de cima quase nunca era achado.

## Quem é o gato
Cada quadro compara o recorte do gato com as fotos do cadastro, mas o nome sai da visita
inteira: o gato que foi o mais parecido em pelo menos metade dos quadros, com folga sobre o
segundo, leva a visita, mesmo que nenhum quadro sozinho tenha passado do limite de
similaridade. Os votos no histórico contam em quantos quadros cada gato foi o mais parecido.

Fotos do cadastro de outro ângulo (de lado, com o celular) comparadas com uma câmera vista de
cima dão notas baixas. No histórico, **Está certo** e **Trocar gato** ensinam o servidor: até 6
recortes do gato naquela visita entram no cadastro dele (no máximo 40 por gato, os mais
novos). Algumas confirmações por gato bastam para a câmera de cima reconhecê-los bem. Os
recortes de visitas não confirmadas são apagados depois de 30 dias.

**Em qual zona:** os pés do gato dentro do polígono, ou boa parte da metade de baixo dele
(câmera vista de cima). Cada gato conta em uma zona só por vez; com comedouro e bebedouro
lado a lado, vence a zona onde ele está mais.

**Quem é o gato:** o recorte do gato inteiro (sem cortar as pontas), comparado também
espelhado, contra cada foto da galeria. Ganha o gato da foto mais parecida, se passar do
limite de similaridade e ganhar do segundo por uma margem; senão, "desconhecido". Gatos
muito pequenos na imagem (longe da câmera) não recebem nome.
Tudo ajustável no app de PC (Servidor → Configurações → Visitas) ou em `visits:` no `config.yaml`.

## Limites
A câmera não distingue "comendo" de "parado ao lado": vale o tempo dentro da zona. Gatos de pelagem parecida exigem mais fotos.
O token protege a API na rede local; para acesso de fora de casa use uma VPN (ex.: Tailscale) em vez de abrir a porta.

## Testes
`PYTHONPATH=. .venv/bin/python -m pytest tests`
