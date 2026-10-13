# Skills de Godot (trazidas do Four Wardens em 13/10/2026)

Manuais de terceiros que o Claude consulta ao escrever para o Godot. São só texto e exemplos; nenhuma roda código sozinha.
Copiadas de `koenigkan12/four-wardens` (instaladas lá em 01/10/2026, versões fixadas abaixo). Para atualizar, pegue de novo na origem.

| Skill | Origem | Versão (commit) | Licença | Para quê |
|---|---|---|---|---|
| godot-animation | gamedev-skills/awesome-gamedev-agent-skills | d4b0e35 | Apache 2.0 | AnimationPlayer, AnimationTree e Tween |
| godot-shaders | gamedev-skills/awesome-gamedev-agent-skills | d4b0e35 | Apache 2.0 | contorno, clarão, dissolver |
| godot-audio | gamedev-skills/awesome-gamedev-agent-skills | d4b0e35 | Apache 2.0 | AudioStreamPlayer, buses e música |
| godot-tilemap | gamedev-skills/awesome-gamedev-agent-skills | d4b0e35 | Apache 2.0 | TileMapLayer, TileSet e terrenos |
| godot-gdscript-patterns | wshobson/agents | 156b7a5 | MIT | sinais, cenas, máquinas de estado, organização do código |
| godot-interactive, godot-live-edit | alexmeckes/godot-claude-skills | 881ff9d | MIT | controlar o editor e rodar o jogo |

`godot-interactive` e `godot-live-edit` só funcionam com o programa `godot-mcp` (github.com/alexmeckes/godot-mcp) e o plugin AI Bridge no editor, que **não estão instalados**: são código de terceiros que roda na máquina, e a instalação fica com o Vinícius.

## Ficaram de fora (e por quê)
- `godot-ui` (zate/cc-godot, d9796f7): a origem não tem arquivo de licença, então não dá para redistribuir num repositório público.
- `godot-particles` (thedivergentai/gd-agentic-skills, 4c4d0ff): LGPL; entra se o repositório for privado ou se aceitarmos cumprir a LGPL aqui.
- Do pacote do alexmeckes, `godot-code-gen`, `godot-scene-design` e `godot-shader` já ficavam de fora no Four Wardens porque repetem as outras.

Os textos de licença completos estão nos repositórios de origem, nos commits acima.
