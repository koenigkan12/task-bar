#!/usr/bin/env python3
"""Valida o conteúdo de história: radio.json, journey.json e strings_story.csv.
Uso: python3 tools/content/validate_content.py [raiz_do_projeto]   (padrão: dois níveis acima deste arquivo)
Sai com código 1 se houver erro; avisos não falham."""
import csv, json, os, re, sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAX_SENT = 140          # caracteres por frase
MAX_SENTS = 3           # frases por fala
MAX_TOTAL = 320         # aviso: balão grande demais
SPEAKERS = {"ruido", "sementes", "caravana", "numeros", "velho", "norte", "ela", "ele"}
CUES = {"static", "tone", "music_far", "music_18h", "numbers", "voice_her", "none"}
KINDS = {"arrival", "program", "reaction", "ambient"}
errors, warns = [], []
err = errors.append
warn = warns.append


def load_json(rel):
    try:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:  # noqa: BLE001
        err(f"{rel}: não carregou ({e})")
        return None


def load_csv(rel):
    tab = {}
    path = os.path.join(ROOT, rel)
    try:
        with open(path, encoding="utf-8", newline="") as f:
            rd = csv.reader(f)
            head = next(rd)
            if head != ["key", "pt_BR", "en"]:
                err(f"{rel}: cabeçalho deve ser key,pt_BR,en (veio {head})")
            for n, row in enumerate(rd, start=2):
                if len(row) != 3:
                    err(f"{rel}:{n}: esperava 3 colunas, veio {len(row)} ({row[:1]})")
                    continue
                k, pt, en = row
                if k in tab:
                    err(f"{rel}:{n}: chave duplicada {k}")
                tab[k] = (pt.replace("\\n", "\n"), en.replace("\\n", "\n"))
    except FileNotFoundError:
        err(f"{rel}: não existe")
    return tab


def sentences(text):
    """Quebra em frases; interjeições curtas (<15 chars, ex.: 'Telhado!') grudam na anterior."""
    out = []
    for seg in text.split("\n"):
        for s in re.split(r"(?<=[.!?])\s+", seg.strip()):
            if not s:
                continue
            if out and len(s) < 15:
                out[-1] += " " + s
            else:
                out.append(s)
    return out


def placeholders(s):
    return sorted(re.findall(r"\{(\w+)\}", s))


def check_text(key, tab, what, limit_sents=True):
    if key not in tab:
        err(f"{what}: chave ausente no CSV: {key}")
        return
    pt, en = tab[key]
    if not pt.strip():
        err(f"{what}: {key} sem texto em pt_BR")
    if not en.strip():
        err(f"{what}: {key} sem texto em en")
    for lang, txt in (("pt_BR", pt), ("en", en)):
        ss = sentences(txt)
        for s in ss:
            if len(s) > MAX_SENT:
                err(f"{key} [{lang}]: frase com {len(s)} > {MAX_SENT}: {s[:50]}...")
        if limit_sents and len(ss) > MAX_SENTS:
            err(f"{key} [{lang}]: {len(ss)} frases (máx. {MAX_SENTS})")
        if len(txt) > MAX_TOTAL:
            warn(f"{key} [{lang}]: fala longa ({len(txt)} caracteres)")
    if placeholders(pt) != placeholders(en):
        err(f"{key}: placeholders diferentes entre pt_BR e en")
    if len(en) > 1.45 * len(pt) + 10:
        warn(f"{key}: en bem maior que pt ({len(en)} vs {len(pt)}); balão pode estourar")


tab = load_csv("data/i18n/strings_story.csv")
radio = load_json("data/radio.json")
journey = load_json("data/journey.json")
balance = load_json("data/balance.json") or {}
used = set()

# ---------- rádio ----------
if radio:
    ids, by_level = set(), {}
    for ln in radio.get("lines", []):
        i = ln.get("id", "?")
        if i in ids:
            err(f"radio: id duplicado {i}")
        ids.add(i)
        for f in ("id", "level", "kind", "speaker", "day_offset", "hour", "text_key", "cue"):
            if f not in ln:
                err(f"radio {i}: falta campo {f}")
        if ln.get("speaker") not in SPEAKERS:
            err(f"radio {i}: speaker inválido {ln.get('speaker')}")
        if ln.get("cue") not in CUES:
            err(f"radio {i}: cue inválido {ln.get('cue')}")
        if ln.get("kind") not in KINDS:
            err(f"radio {i}: kind inválido {ln.get('kind')}")
        if ln.get("level") not in (1, 2, 3, 4, 5):
            err(f"radio {i}: level fora de 1..5")
        k, h = ln.get("kind"), ln.get("hour")
        if k in ("program", "ambient"):
            if not isinstance(h, (int, float)) or not (0 <= h < 24):
                err(f"radio {i}: {k} precisa de hour em [0,24)")
        elif h is not None:
            err(f"radio {i}: {k} deve ter hour null")
        if not isinstance(ln.get("day_offset"), int) or ln.get("day_offset") < 0:
            err(f"radio {i}: day_offset deve ser inteiro >= 0")
        if k in ("arrival", "reaction") and ln.get("day_offset") != 0:
            err(f"radio {i}: {k} deve ter day_offset 0")
        if ln.get("text_key") != "radio." + i:
            err(f"radio {i}: text_key deveria ser radio.{i}")
        used.add(ln.get("text_key"))
        check_text(ln.get("text_key", ""), tab, f"radio {i}")
        by_level.setdefault(ln.get("level"), []).append(ln)
    for lv in range(1, 6):
        L = by_level.get(lv, [])
        arr = [x for x in L if x["kind"] == "arrival"]
        rea = [x for x in L if x["kind"] == "reaction"]
        if not L:
            err(f"nível {lv} sem nenhuma linha")
        if len(arr) != 1:
            err(f"nível {lv}: precisa de exatamente 1 arrival (tem {len(arr)})")
        if len(rea) > 1:
            err(f"nível {lv}: mais de 1 reaction (todas sairiam 20 min depois da arrival)")
        for r in rea:
            if r["speaker"] != "ele":
                err(f"{r['id']}: reaction deve ser do 'ele'")
            if not arr:
                err(f"{r['id']}: reaction sem arrival no mesmo nível")
        for x in L:
            if x["speaker"] == "ele" and x["kind"] != "reaction":
                warn(f"{x['id']}: 'ele' fora de reaction (ele fala pouco)")
    l5 = next((x for x in by_level.get(5, []) if x["id"] == "l5_arrival"), None)
    if not l5:
        err("falta l5_arrival")
    else:
        if l5["speaker"] != "ela" or l5["cue"] != "voice_her":
            err("l5_arrival deve ser speaker ela, cue voice_her")
        if "tô a caminho" not in tab.get("radio.l5_arrival", ("", ""))[0].lower():
            warn("l5_arrival: não contém 'tô a caminho' (fidelidade à fala do conceito)")
    spk_used = {x["speaker"] for x in radio["lines"]}
    for s in SPEAKERS - spk_used:
        warn(f"speaker nunca usado no rádio: {s}")
    n = len(radio["lines"])
    if not 28 <= n <= 38:
        warn(f"{n} linhas de rádio (alvo ~30-36)")

# ---------- speakers ----------
for s in SPEAKERS:
    check_text("speaker." + s, tab, "speaker", limit_sents=False)
    used.add("speaker." + s)

# ---------- jornada ----------
if journey:
    house = (balance.get("journey") or {}).get("house_items") or \
        ["cama_dela", "cantinho", "planta_dela", "cabide", "segunda_caneca", "foto_dela"]
    oi = journey.get("on_item", {})
    for it in house:
        if it not in oi:
            err(f"journey.on_item: falta {it}")
        else:
            if oi[it].get("cue") not in CUES:
                err(f"journey.on_item.{it}: cue inválido")
            used.add(oi[it].get("text_key"))
            check_text(oi[it].get("text_key", ""), tab, f"on_item {it}")
    for it in oi:
        if it not in house:
            warn(f"journey.on_item: {it} não está em balance.journey.house_items")
    tids, last = set(), 0
    tr = journey.get("travel", [])
    if not 8 <= len(tr) <= 12:
        warn(f"{len(tr)} falas de viagem (alvo ~10)")
    for t in tr:
        if t["id"] in tids:
            err(f"travel: id duplicado {t['id']}")
        tids.add(t["id"])
        if t.get("cue") not in CUES:
            err(f"travel {t['id']}: cue inválido")
        if not isinstance(t.get("hour"), (int, float)) or not (0 <= t["hour"] < 24):
            err(f"travel {t['id']}: hour inválido")
        if t["day_offset"] < last:
            err(f"travel {t['id']}: day_offset fora de ordem")
        last = t["day_offset"]
        used.add(t["text_key"])
        check_text(t["text_key"], tab, f"travel {t['id']}")
    arr = journey.get("arrival", {})
    if arr.get("cue") not in CUES:
        err("journey.arrival: cue inválido")
    used.add(arr.get("text_key"))
    check_text(arr.get("text_key", ""), tab, "journey.arrival")
    notes = journey.get("epilogue_notes", [])
    if len(notes) < 24:
        err(f"epilogue_notes: {len(notes)} < 24")
    if len(set(notes)) != len(notes):
        err("epilogue_notes: chaves repetidas")
    for k in notes:
        if not k.startswith("note."):
            err(f"epilogue_notes: {k} deveria começar com note.")
        used.add(k)
        check_text(k, tab, "nota")
    # notas distintas entre si
    txts = [tab[k][0] for k in notes if k in tab]
    if len(set(txts)) != len(txts):
        err("epilogue_notes: textos repetidos")

# ---------- ending / diary ----------
for need in ("ending.title", "ending.nextday.title", "ending.continue", "diary.title", "diary.empty",
             "diary.away.summary", "diary.away.line"):
    if need not in tab:
        err(f"CSV: falta {need}")
s = tab.get("diary.away.summary", ("", ""))
for lang, txt in zip(("pt_BR", "en"), s):
    for ph in ("hours", "visits", "scrap", "nights"):
        if "{" + ph + "}" not in txt:
            err(f"diary.away.summary [{lang}] sem {{{ph}}}")
for k in tab:
    if not re.match(r"^(radio|speaker|journey|note|ending|diary)\.", k):
        err(f"CSV: chave fora dos prefixos da história: {k}")
    if k.startswith(("ending.", "diary.")):
        check_text(k, tab, "ui-história", limit_sents=False)
# chaves órfãs (no CSV mas não usadas por JSON) só entre radio/journey/note
for k in tab:
    if k.startswith(("radio.", "journey.", "note.")) and k not in used:
        err(f"CSV: chave sem uso nos JSON: {k}")

for w in warns:
    print("AVISO:", w)
for e in errors:
    print("ERRO:", e)
n_r = len(radio["lines"]) if radio else 0
print(f"{n_r} falas de rádio, {len((journey or {}).get('epilogue_notes', []))} bilhetes, {len(tab)} strings; "
      f"{len(errors)} erro(s), {len(warns)} aviso(s).")
sys.exit(1 if errors else 0)
