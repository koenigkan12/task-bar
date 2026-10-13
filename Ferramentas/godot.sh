#!/bin/bash
# Roda o Godot do projeto com os argumentos dados (ex.: --headless --path Godot --quit-after 60).
# Existe para o Claude Code poder liberar o Godot numa regra só (.claude/settings.json).
# Caminho do executável: variável GODOT_BIN, ou o `godot` que estiver no PATH.
G="${GODOT_BIN:-$(command -v godot || command -v godot4)}"
if [ -z "$G" ]; then
  echo "Godot não encontrado: defina GODOT_BIN com o caminho do executável (Godot 4.x) ou ponha 'godot' no PATH." >&2
  exit 127
fi
exec "$G" "$@"
