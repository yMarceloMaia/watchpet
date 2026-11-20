# watchpet

Monitora os gatos pelas câmeras da casa e conta, para cada gato, as idas à caixa de
areia, as vezes que comeu e que bebeu água. Reconhece qual gato é, guarda uma foto de
cada visita e avisa quando algo foge do normal (não bebeu água hoje, foi à caixa muito
mais que o costume, câmera fora do ar).

| Pasta | O que é |
|-------|---------|
| [`server/`](server) | Servidor em Python: lê as câmeras, detecta (YOLO) e reconhece (ResNet50) os gatos, conta as visitas e serve a API e um painel web. |
| [`desktop/`](desktop) | App de PC em Qt Quick (C++/QML): painel, câmeras, zonas, gatos, histórico, e liga e controla o servidor deste PC. |
| [`mobile/`](mobile) | App de celular em Expo/React Native: o mesmo painel, cadastro de gatos pela câmera e o celular como câmera de monitoramento. |

## Como funciona
1. As câmeras são câmeras IP (RTSP), celulares com IP Webcam, webcams USB ou o próprio app do celular.
2. Em cada câmera você desenha as zonas: caixa de areia, comida e água.
3. Cada gato é cadastrado com fotos (15 a 30, de ângulos e luz variados).
4. Uma visita conta quando o mesmo gato fica na zona pelo tempo mínimo do tipo
   (15 s na caixa, 8 s na comida, 5 s na água, ajustáveis); passadas rápidas não contam.

## Começar
**Instalar num Linux** (servidor + app de PC): gere o pacote com
`server/deploy/make-linux-bundle.sh` e rode o `install.sh` dele no outro PC
(detalhes em [`server/deploy/linux/LEIA-ME.txt`](server/deploy/linux/LEIA-ME.txt)).

**Desenvolvimento:**
```sh
# servidor
cd server
uv venv --python 3.12 .venv && uv pip install -p .venv/bin/python -r requirements.txt
PYTHONPATH=. .venv/bin/python -m catwatch          # mostra o token; painel em http://localhost:8000

# app de PC (Qt 6): acha o servidor em ../server e liga ele sozinho
cd desktop && bin/build && build/catwatch

# app de celular (no mesmo Wi-Fi do PC)
cd mobile && npm install && npx expo start          # conecte lendo o QR code da aba Servidor do app de PC
```

Testes do servidor: `cd server && PYTHONPATH=. .venv/bin/python -m pytest tests`.

## Licenças
O código deste repositório é MIT. A detecção usa o [Ultralytics YOLO](https://github.com/ultralytics/ultralytics),
que é AGPL-3.0: para distribuir o servidor junto com ele, siga a AGPL ou use outro detector.
As fontes embutidas no app de PC são Recursive (OFL) e Material Design Icons (Apache 2.0).
