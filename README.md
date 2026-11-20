# Catwatch (desktop)

Painel leve em Qt Quick com as mesmas funções do app de celular: contagem do dia e
dos últimos 7 dias por gato, câmeras ao vivo (adicionar, remover, editar zonas),
cadastro de gatos (fotos do disco ou da câmera) e histórico com correção.
É só um cliente: a detecção e a identificação rodam no servidor (`../pet`).

Build: `bin/build` e `build/catwatch`. Instalar no launcher: `bin/install`.
Na primeira vez informe o endereço do servidor e o token (impresso no terminal
do servidor, também em `pet/data/token.txt`).

| Tecla | Ação |
|-------|------|
| 1 / 2 / 3 / 4 | Hoje · Câmeras · Gatos · Histórico |
| R | Atualizar |
| ? | Atalhos |
| Q | Sair |
