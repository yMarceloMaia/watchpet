# Catwatch (desktop)

Painel leve em Qt Quick para acompanhar os gatos: contagem do dia por gato
(caixa de areia, comida, água), câmeras ao vivo e histórico de visitas.
É só um cliente: a detecção e a identificação rodam no servidor (`../pet`).

Build: `bin/build` e `build/catwatch`. Instalar no launcher: `bin/install`.
Na primeira vez informe o endereço do servidor e o token (impresso no terminal
do servidor, também em `pet/data/token.txt`).

| Tecla | Ação |
|-------|------|
| 1 / 2 / 3 | Hoje · Câmeras · Histórico |
| R | Atualizar |
| ? | Atalhos |
| Q | Sair |
