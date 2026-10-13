#!/bin/bash
# Exporta o jogo para Windows x64 (exe com o .pck embutido) e gera o .zip.
#   bash tools/build/export_windows.sh            # exporta, valida e empacota
#   bash tools/build/export_windows.sh --debug    # usa o template de debug
#   bash tools/build/export_windows.sh --sem-validar
# Precisa do Godot 4.6 (GODOT_BIN ou `godot` no PATH) e dos export templates 4.6.stable
# (Editor > Gerenciar modelos de exportação, ou extraia o .tpz em
#  ~/.local/share/godot/export_templates/4.6.stable no Linux,
#  %APPDATA%\Godot\export_templates\4.6.stable no Windows).
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$RAIZ"
GODOT=(bash Ferramentas/godot.sh)
PRESET="Windows Desktop"
SAIDA="build/windows"
EXE="$SAIDA/QuantosDias.exe"
ZIP="build/QuantosDias-windows-x64.zip"
MODO="--export-release"
VALIDAR=1
for a in "$@"; do
  case "$a" in
    --debug) MODO="--export-debug" ;;
    --sem-validar) VALIDAR=0 ;;
    *) echo "opção desconhecida: $a" >&2; exit 2 ;;
  esac
done

# Ícone: regenera a partir da arte se o Pillow estiver instalado; senão usa o que está no repositório.
if python3 -c "import PIL" 2>/dev/null; then
  python3 tools/build/make_icon.py
fi

echo "== Importando recursos"
"${GODOT[@]}" --headless --path . --import

echo "== Exportando $PRESET ($MODO)"
rm -rf "$SAIDA"
mkdir -p "$SAIDA"
"${GODOT[@]}" --headless --path . "$MODO" "$PRESET" "$RAIZ/$EXE"
if [ ! -s "$EXE" ]; then
  echo "ERRO: $EXE não foi gerado (faltam os export templates 4.6.stable?)" >&2
  exit 1
fi
rm -f "$SAIDA"/*.pck   # o pck vai embutido no exe

if [ "$VALIDAR" = 1 ]; then
  echo "== Validando: exporta o .pck e roda a cena principal headless com --main-pack"
  CHECK="build/check"
  rm -rf "$CHECK"; mkdir -p "$CHECK"
  "${GODOT[@]}" --headless --path . --export-pack "$PRESET" "$RAIZ/$CHECK/QuantosDias.pck"
  LOG="$CHECK/run.log"
  # roda fora do projeto, para provar que tudo vem do pck
  ( cd "$CHECK" && bash "$RAIZ/Ferramentas/godot.sh" --headless --main-pack QuantosDias.pck --quit-after 120 ) > "$LOG" 2>&1 || {
    echo "ERRO: o pck não rodou (veja $LOG)" >&2; tail -20 "$LOG" >&2; exit 1; }
  # avisos de vazamento ao sair (recursos/ObjectDB) não contam como falha
  if grep -E "SCRIPT ERROR|ERROR:|Parse Error|Failed to load" "$LOG" \
      | grep -v -E "still in use at exit|ObjectDB instances leaked|^\s+at: "; then
    echo "ERRO: o pck rodou com erros (acima; log completo em $LOG)" >&2
    exit 1
  fi
  echo "pck OK: $(du -h "$CHECK/QuantosDias.pck" | cut -f1), sem erros em 120 quadros"
fi

echo "== Empacotando $ZIP"
rm -f "$ZIP"
( cd "$SAIDA" && zip -q -9 "$RAIZ/$ZIP" QuantosDias.exe )
ls -lh "$EXE" "$ZIP"
