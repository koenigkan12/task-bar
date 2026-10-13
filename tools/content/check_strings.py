#!/usr/bin/env python3
"""Confere as chaves de texto usadas no projeto contra os CSV de data/i18n/.

Varre scripts/**/*.gd, scenes/**/*.tscn e data/*.json por:
  I18n.t("chave"), I18n.has_key("chave"), text_key / name_key / desc_key / label_key /
  title_key / tooltip_key (= ou :) e chaves derivadas dos dados (balance.json, radio.json,
  journey.json). Chaves montadas em tempo de execução ("item.%s.name" % id) viram padrões:
  não dão falta, e as chaves que casam com o padrão não contam como órfãs.

Relatório: FALTANTES (usadas e sem linha no CSV) e ÓRFÃS (no CSV, sem uso). Além disso,
confere PT-BR/EN preenchidos, placeholders iguais nos dois idiomas, chaves repetidas entre
arquivos, botões/abas <= 14 caracteres e descrições de item <= 60 caracteres.

Uso: python3 tools/content/check_strings.py [--root DIR] [--strict]
  Sai com 1 se houver faltantes ou erros de qualidade (órfãs só avisam; --strict as torna erro).
  As faltantes da história (radio.*, speaker.*, journey.*, note.*, ending.*, diary.*) aparecem
  separadas: elas só existem quando strings_story.csv chega.
"""
import argparse
import csv
import json
import re
import sys
from pathlib import Path

STORY_PREFIXES = ("radio.", "speaker.", "journey.", "note.", "ending.", "diary.")

RE_T = re.compile(r'\b[Ii]18n\w*\s*(?:\)|\])?\s*\.\s*(?:t|has_key)\(\s*(["\'])(.+?)\1(\s*[%+])?')
RE_FIELD = re.compile(
    r'["\']?\b(?:text|name|desc|label|title|tooltip)_key["\']?\s*[:=]\s*(["\'])([A-Za-z0-9_.{}%]+)\1')


def read_csvs(d: Path):
    """Devolve {arquivo: {chave: {coluna: texto}}} e a lista de colunas de idioma."""
    out = {}
    for f in sorted(d.glob("strings_*.csv")):
        with open(f, encoding="utf-8-sig", newline="") as fh:
            rows = list(csv.reader(fh))
        if not rows:
            out[f.name] = {}
            continue
        header = [h.strip() for h in rows[0]]
        table = {}
        for r in rows[1:]:
            if not r or not r[0].strip() or r[0].startswith("#"):
                continue
            table.setdefault(r[0].strip(), dict(zip(header[1:], r[1:] + [""] * len(header))))
        out[f.name] = table
    return out


def collect_code_keys(root: Path):
    """Chaves literais e padrões encontrados no código/cenas/json."""
    literal, patterns = {}, {}

    def note(key, where, dynamic):
        if dynamic or "%" in key or "{" in key:
            parts = re.split(r"%[sd]|\{\w*\}", key)
            patterns.setdefault("^" + "[^.]+".join(re.escape(x) for x in parts) + "$", where)
        else:
            literal.setdefault(key, where)

    for glob in ("scripts/**/*.gd", "scenes/**/*.tscn"):
        for f in sorted(root.glob(glob)):
            text = f.read_text(encoding="utf-8", errors="replace")
            for i, line in enumerate(text.splitlines(), 1):
                if line.lstrip().startswith("#"):
                    continue  # comentário
                where = f"{f.relative_to(root)}:{i}"
                for m in RE_T.finditer(line):
                    note(m.group(2), where, bool(m.group(3)))
                for m in RE_FIELD.finditer(line):
                    note(m.group(2), where, False)
    for f in sorted((root / "data").glob("*.json")):
        text = f.read_text(encoding="utf-8")
        for i, line in enumerate(text.splitlines(), 1):
            for m in RE_FIELD.finditer(line):
                note(m.group(2), f"{f.relative_to(root)}:{i}", False)
    return literal, patterns


def derived_keys(root: Path):
    """Chaves que os dados exigem por convenção (CONTRATOS seção 6)."""
    need = {}

    def req(k, why):
        need.setdefault(k, why)

    bal = root / "data" / "balance.json"
    if bal.exists():
        b = json.loads(bal.read_text(encoding="utf-8"))
        for iid, it in b.get("items", {}).items():
            req(f"item.{iid}.name", "balance.json items")
            req(f"item.{iid}.desc", "balance.json items")
            for pq in it.get("pra_que", []):
                req(f"pra_que.{pq}", f"balance.json items.{iid}.pra_que")
                req(f"pra_que.{pq}.help", f"balance.json items.{iid}.pra_que")
        for c in b.get("crops", {}):
            req(f"crop.{c}.name", "balance.json crops")
        for line in b.get("lines", {}):
            req(f"line.{line}", "balance.json lines")
        for line in ("decor", "casa", "escavacao"):
            req(f"line.{line}", "catalog filters")
        for n in range(1, 6):
            req(f"antenna.{n}.name", "5 níveis de antena")
        for beh in b.get("behaviors", {}):
            req(f"behavior.{beh}", "balance.json behaviors")
        for room in b.get("rooms", {}).get("fixed", {}).values():
            for fx in room:
                req(f"fixed.{fx['id']}", "balance.json rooms.fixed")
        for n in b.get("rooms", {}).get("dig_cost", {}):
            req(f"room.dig{n}", "balance.json rooms.dig_cost")
    rad = root / "data" / "radio.json"
    if rad.exists():
        for ln in json.loads(rad.read_text(encoding="utf-8")).get("lines", []):
            if ln.get("speaker"):
                req(f"speaker.{ln['speaker']}", "radio.json speaker")
    jou = root / "data" / "journey.json"
    if jou.exists():
        for n in json.loads(jou.read_text(encoding="utf-8")).get("epilogue_notes", []):
            req(n, "journey.json epilogue_notes")
    return need


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
    ap.add_argument("--strict", action="store_true", help="órfãs também viram erro")
    args = ap.parse_args()
    root = Path(args.root)
    csvs = read_csvs(root / "data" / "i18n")
    if not csvs:
        print("nenhum strings_*.csv em data/i18n/")
        return 1

    keys = {}          # chave -> arquivo
    errors = []
    for fname, table in csvs.items():
        for k in table:
            if k in keys:
                errors.append(f"chave repetida entre arquivos: {k} ({keys[k]} e {fname})")
            keys.setdefault(k, fname)
    langs = sorted({c for t in csvs.values() for row in t.values() for c in row})
    base = "pt_BR" if "pt_BR" in langs else langs[0]

    literal, patterns = collect_code_keys(root)
    needed = {k: w for k, w in literal.items()}
    for k, why in derived_keys(root).items():
        needed.setdefault(k, why)
    pat_res = [re.compile(p) for p in patterns]

    missing = sorted(k for k in needed if k not in keys)
    missing_story = [k for k in missing if k.startswith(STORY_PREFIXES)]
    missing_other = [k for k in missing if k not in missing_story]

    used = set(needed)
    orphans = sorted(k for k in keys if k not in used and not any(p.match(k) for p in pat_res))

    # qualidade
    for fname, table in csvs.items():
        for k, row in table.items():
            for lang in langs:
                if lang not in row or not row[lang].strip():
                    errors.append(f"{fname}: {k} sem texto em {lang}")
            ph = {lang: sorted(re.findall(r"\{(\w+)\}", row.get(lang, ""))) for lang in langs}
            if len({tuple(v) for v in ph.values()}) > 1:
                errors.append(f"{fname}: {k} com placeholders diferentes entre idiomas: {ph}")
            for lang in langs:
                txt = row.get(lang, "")
                is_btn = k.endswith(".btn") or ".btn." in k or k.startswith("tab.")
                if is_btn and len(txt) > 14:
                    errors.append(f"{fname}: {k} ({lang}) tem {len(txt)} caracteres (limite 14 para botão/aba)")
                if re.fullmatch(r"item\.[^.]+\.desc", k):
                    name = table.get(k[:-5] + ".name", {}).get(lang, "")
                    if len(txt) > 60:
                        errors.append(f"{fname}: {k} ({lang}) tem {len(txt)} caracteres (limite 60)")
                    if name and name.lower() in txt.lower():
                        errors.append(f"{fname}: {k} ({lang}) repete o nome '{name}'")

    total = len(keys)
    print(f"CSV: {', '.join(f'{f} ({len(t)})' for f, t in csvs.items())}; total {total} chaves; idiomas {langs}")
    print(f"Chaves usadas no código/dados: {len(literal)} literais, {len(patterns)} padrões dinâmicos; "
          f"exigidas por convenção: {len(needed) - len(literal)}")
    if missing_other:
        print(f"\nFALTANTES ({len(missing_other)}):")
        for k in missing_other:
            print(f"  {k}   <- {needed[k]}")
    if missing_story:
        print(f"\nFaltantes da história (aguardam strings_story.csv) ({len(missing_story)}):")
        for k in missing_story[:15]:
            print(f"  {k}   <- {needed[k]}")
        if len(missing_story) > 15:
            print(f"  ... +{len(missing_story) - 15}")
    if orphans:
        print(f"\nÓrfãs (no CSV, sem uso ainda) ({len(orphans)}): "
              + ", ".join(orphans[:12]) + (f" ... +{len(orphans) - 12}" if len(orphans) > 12 else ""))
    if errors:
        print(f"\nERROS DE QUALIDADE ({len(errors)}):")
        for e in errors:
            print("  " + e)
    bad = bool(missing_other or errors or (args.strict and orphans))
    print("\nRESULTADO:", "FALHOU" if bad else "OK")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
