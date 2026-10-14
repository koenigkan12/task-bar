#!/usr/bin/env python3
"""Gera data/i18n/_index.json (lista dos strings_*.csv) e os .csv.import "keep".

Por que: em build exportado o Godot trata .csv como tradução e NÃO exporta o arquivo
original, e DirAccess pode não listar a pasta. O índice dá a lista; o importador "keep"
(arquivo .import ao lado de cada CSV) faz o CSV ir cru para o pacote, onde o I18n lê.
Rode sempre que criar/remover um strings_*.csv.   Uso: python3 tools/content/make_i18n_index.py [raiz]
"""
import json
import sys
from pathlib import Path

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
d = root / "data" / "i18n"
files = sorted(p.name for p in d.glob("strings_*.csv"))
(d / "_index.json").write_text(json.dumps({"files": files}, indent=2) + "\n", encoding="utf-8")
for name in files:
    imp = d / (name + ".import")
    imp.write_text('[remap]\n\nimporter="keep"\n', encoding="utf-8")
print("índice:", ", ".join(files) or "(vazio)")
