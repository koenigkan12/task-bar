#!/bin/bash
# Roda todos os testes de tests/ e mostra um resumo. Sai com 1 se algum falhar.
#   bash tests/run_all.sh            # todos
#   bash tests/run_all.sh sim_       # só os que contêm "sim_" no nome
# Tipos de teste:
#   - script `extends SceneTree` (ou MainLoop): roda headless com --script; passa se sair com 0.
#   - cena tests/<nome>.tscn ao lado do .gd, ou nome shot_*: precisa de tela; roda com
#     xvfb-run + opengl3 se houver xvfb-run, senão é pulado. Capturas vão para build/tests/.
#   - outros .gd (ajudantes, extends Node sem cena): ignorados.
# Falha também se a saída tiver "SCRIPT ERROR" ou "Parse Error".
# Godot: GODOT_BIN ou `godot` no PATH (ver Ferramentas/godot.sh). Tempo por teste: TEST_TIMEOUT (padrão 300 s).
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"
FILTRO="${1:-}"
LIMITE="${TEST_TIMEOUT:-300}"
SAIDA="build/tests"
mkdir -p "$SAIDA"
GODOT=(bash Ferramentas/godot.sh)

if [ ! -d .godot/imported ]; then
  echo "== Primeira execução: importando recursos"
  "${GODOT[@]}" --headless --path . --import > "$SAIDA/_import.log" 2>&1
fi

TEM_XVFB=0
command -v xvfb-run > /dev/null && TEM_XVFB=1

ok=(); falhou=(); pulado=()
for gd in tests/*.gd; do
  nome="$(basename "$gd" .gd)"
  [ -n "$FILTRO" ] && [[ "$nome" != *"$FILTRO"* ]] && continue
  log="$SAIDA/$nome.log"
  cabeca="$(grep -m1 -E '^extends ' "$gd" | awk '{print $2}')"
  if [ -f "tests/$nome.tscn" ] || [[ "$nome" == shot_* ]]; then
    if [ "$TEM_XVFB" = 0 ]; then pulado+=("$nome (sem xvfb-run)"); continue; fi
    alvo="res://tests/$nome.gd"
    if [ -f "tests/$nome.tscn" ]; then alvo="res://tests/$nome.tscn"; modo=(); else modo=(--script); fi
    [ "$cabeca" != "SceneTree" ] && [ "$cabeca" != "MainLoop" ] && modo=()
    OUT_PNG="$RAIZ/$SAIDA/$nome.png" OUT_DIR="$RAIZ/$SAIDA" timeout "$LIMITE" \
      xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT[@]}" --path . --rendering-driver opengl3 \
      "${modo[@]}" "$alvo" --quit-after 3000 > "$log" 2>&1
    codigo=$?
  elif [ "$cabeca" = "SceneTree" ] || [ "$cabeca" = "MainLoop" ]; then
    timeout "$LIMITE" "${GODOT[@]}" --headless --path . --script "res://tests/$nome.gd" > "$log" 2>&1
    codigo=$?
  else
    continue
  fi
  if [ "$codigo" = 0 ] && ! grep -q -E "SCRIPT ERROR|Parse Error" "$log"; then
    ok+=("$nome")
    printf '  ok      %s\n' "$nome"
  else
    [ "$codigo" = 124 ] && motivo="tempo esgotado (${LIMITE}s)" || motivo="código $codigo"
    falhou+=("$nome: $motivo, log em $log")
    printf '  FALHOU  %s (%s)\n' "$nome" "$motivo"
    grep -E "FALHOU|SCRIPT ERROR|Parse Error|ERROR" "$log" | head -5 | sed 's/^/          /'
  fi
done

echo
echo "Resumo: ${#ok[@]} ok, ${#falhou[@]} falharam, ${#pulado[@]} pulados"
for p in "${pulado[@]}"; do echo "  pulado: $p"; done
for f in "${falhou[@]}"; do echo "  falhou: $f"; done
[ "${#falhou[@]}" = 0 ]
