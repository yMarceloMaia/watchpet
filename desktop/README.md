# Catwatch (desktop)

App leve em Qt Quick para acompanhar os gatos e controlar o servidor Catwatch deste PC.

- **Hoje**: alertas do dia, contagem por gato e últimos 7 dias.
- **Câmeras**: ao vivo, adicionar, remover e editar zonas.
- **Gatos**: cadastro com fotos do disco ou da câmera, com progresso do envio.
- **Histórico**: foto de cada visita, certeza da identificação, votos e correção.
- **Servidor**: liga, para e reinicia o servidor deste PC; QR code para conectar o
  celular; uso de CPU, memória e placa de vídeo; configurações; exportar CSV e
  backup; log ao vivo e saída do processo.

Fechar a janela deixa o app na bandeja, com o servidor monitorando. Com
"Iniciar com o sistema", o app abre no login direto na bandeja (`catwatch --background`)
e liga o servidor. Alertas (gato sem beber água, excesso de idas à caixa, câmera
fora do ar) viram notificações do sistema.

## Servidor
O app procura o servidor (pasta com `catwatch/` e `.venv`) em `CATWATCH_SERVER_DIR`,
em `~/.local/share/catwatch/server` (onde o `install.sh` instala) ou em `../server`
(no repositório); dá para escolher outra pasta na aba Servidor. Um servidor já rodando na porta (pelo
terminal ou systemd) é reconhecido e usado.

## Build
`bin/build` e `build/catwatch`. Instalar no launcher: `bin/install`.

| Tecla | Ação |
|-------|------|
| 1 a 5 | Hoje · Câmeras · Gatos · Histórico · Servidor |
| R | Atualizar |
| ? | Atalhos |
| Q | Sair (pergunta antes se o servidor deste PC estiver rodando) |
