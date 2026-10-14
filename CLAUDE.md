# Quantos Dias?: instruções para o Claude

Idle cozy em Godot 4.6 (GDScript tipado), janela baixa grudada no rodapé da tela. Design em `docs/analise-de-design.md`; interfaces entre módulos em `docs/CONTRATOS.md`.

- **Responda sempre em português (PT-BR).**
- Pergunte antes de implementar quando o Vinícius pedir só opinião ("me fala se faz sentido", "antes de implementar"). Nesses casos, proponha e espere.
- Todo balanceamento fica em `data/balance.json`; texto visível só via `I18n` (CSV em `data/i18n/`).

## Godot
- As skills de Godot estão em `.claude/skills/` (origem e licenças em `.claude/skills/ORIGEM.md`); consulte a que se aplica antes de escrever cena, shader, animação, áudio ou tilemap.
- Chame o Godot por `bash Ferramentas/godot.sh <args>` (usa `GODOT_BIN` ou o `godot` do PATH). A raiz do projeto é a raiz do repositório: `--path .`.
- Antes de dizer que está pronto: `--headless --path . --check-only --script <arquivo.gd>` em cada .gd alterado e uma carga `--headless --path . --quit-after 60`.
- Depois de acrescentar imagens/áudio: `--headless --path . --import`.
- Captura de tela não funciona com `--headless`; use `xvfb-run -a` com `--rendering-driver opengl3`.
- `godot-interactive` e `godot-live-edit` exigem o `godot-mcp` e o plugin AI Bridge, que não estão instalados.

## Mercado
- Antes de propor ou dar como pronto um sistema, tela ou versão, confira `docs/regras-do-mercado.md` (as reclamações do nicho que o jogo tem que cobrir) e diga se algum ponto fica descoberto.
