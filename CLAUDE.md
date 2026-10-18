# Quantos Dias?: instruções para o Claude

Idle cozy em Godot 4.6 (GDScript tipado), janela baixa grudada no rodapé da tela. Design em `docs/analise-de-design.md`; interfaces entre módulos em `docs/CONTRATOS.md`.

- **Responda sempre em português (PT-BR).**
- Pergunte antes de implementar quando o Vinícius pedir só opinião ("me fala se faz sentido", "antes de implementar"). Nesses casos, proponha e espere.
- Todo balanceamento fica em `data/balance.json`; texto visível só via `I18n` (CSV em `data/i18n/`).

## Interface
- Ícone + número em vez de frase: camas `🛏 3`, estoque `🍅 16/20`, produção `🪵 1.5/min`, energia `⚡ +3`. A frase que explica vai na dica do mouse (`tooltip_text`), não no cartão.
- Texto no cartão só quando ícone + número não der conta (descrição de uma linha do prédio, motivos de bloqueio, falas).
- Nunca mostrar linha com valor zero ou sem sentido para aquele prédio (ex.: "0 camas" no bunker).

## Godot
- As skills de Godot estão em `.claude/skills/` (origem e licenças em `.claude/skills/ORIGEM.md`); consulte a que se aplica antes de escrever cena, shader, animação, áudio ou tilemap.
- Chame o Godot por `bash Ferramentas/godot.sh <args>` (usa `GODOT_BIN` ou o `godot` do PATH). A raiz do projeto é a raiz do repositório: `--path .`.
- Antes de dizer que está pronto: `--headless --path . --check-only --script <arquivo.gd>` em cada .gd alterado e uma carga `--headless --path . --quit-after 60`.
- Depois de acrescentar imagens/áudio: `--headless --path . --import`.
- Captura de tela não funciona com `--headless`; use `xvfb-run -a` com `--rendering-driver opengl3`.
- `godot-interactive` e `godot-live-edit` exigem o `godot-mcp` e o plugin AI Bridge, que não estão instalados.
