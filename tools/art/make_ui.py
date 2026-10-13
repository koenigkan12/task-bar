#!/usr/bin/env python3
"""ARTE-UI: molduras 9-slice, botões, barras, abas e ícones 8x8 (paleta fixa).

Escreve PNGs em assets/art/ui/ e assets/art/manifest_ui.json; folha de contato em
assets/art/ui/_contact_ui.png (fora do manifesto). Idempotente. Uso: python3 tools/art/make_ui.py
"""
import json
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from palette import RGB, check_image, snap_image  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "art", "ui")
MANIFEST = os.path.join(ROOT, "assets", "art", "manifest_ui.json")

# ---------------------------------------------------------------- utilidades


def canvas(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def put(img, x, y, name):
    if name is None:
        return
    img.putpixel((x, y), RGB[name] + (255,))


def rect(img, x0, y0, x1, y1, name):
    """Retângulo preenchido, inclusivo."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(img, x, y, name)


def from_rows(rows, legend):
    """Monta imagem a partir de linhas de texto ('.' = transparente)."""
    h, w = len(rows), len(rows[0])
    img = canvas(w, h)
    for y, row in enumerate(rows):
        assert len(row) == w, (row, w)
        for x, ch in enumerate(row):
            if ch != ".":
                put(img, x, y, legend[ch])
    return img


# ---------------------------------------------------------------- 9-slice


def make_panel():
    """16x16, margens 5. Chapa de bunker: contorno ink, moldura ferrugem, rebites, miolo dark2.
    Bordas constantes ao longo do eixo de esticar; rebites só nos cantos (margem)."""
    s = 16
    im = canvas(s, s)
    rect(im, 0, 0, s - 1, s - 1, "ink")
    # moldura ferrugem 3 px (luz no alto/esquerda)
    rect(im, 1, 1, s - 2, s - 2, "rust2")
    rect(im, 1, 1, s - 2, 1, "rust3")      # topo claro
    rect(im, 1, 1, 1, s - 2, "rust3")      # esquerda clara
    rect(im, 2, s - 2, s - 2, s - 2, "rust1")  # base escura
    rect(im, s - 2, 2, s - 2, s - 2, "rust1")  # direita escura
    rect(im, 2, 2, 2, s - 3, "rust2")
    rect(im, 2, 2, s - 3, 2, "rust2")
    rect(im, 3, s - 3, s - 3, s - 3, "rust1")
    rect(im, s - 3, 3, s - 3, s - 3, "rust1")
    # miolo
    rect(im, 3, 3, s - 4, s - 4, "dark2")
    # lábio interno (sombra no alto/esquerda, luz na base/direita): margem de 5 => 4 px de moldura
    rect(im, 3, 3, s - 4, 3, "dark1")
    rect(im, 3, 3, 3, s - 4, "dark1")
    rect(im, 4, s - 4, s - 4, s - 4, "dark3")
    rect(im, s - 4, 4, s - 4, s - 4, "dark3")
    rect(im, 4, 4, s - 5, s - 5, "dark2")
    # cantos arredondados
    for cx, cy in ((0, 0), (s - 1, 0), (0, s - 1), (s - 1, s - 1)):
        im.putpixel((cx, cy), (0, 0, 0, 0))
    # rebites nos cantos (dentro da margem 5)
    for cx, cy in ((2, 2), (s - 3, 2), (2, s - 3), (s - 3, s - 3)):
        put(im, cx, cy, "conc3")
    return im


def make_button(state):
    """12x12, margens 4."""
    s = 12
    pal = {
        "normal":   dict(line="ink", hl="conc3", face="conc1", sh="dark3", sh2="dark2"),
        "hover":    dict(line="amber1", hl="conc4", face="conc2", sh="conc1", sh2="dark3"),
        "pressed":  dict(line="ink", hl="dark1", face="dark3", sh="conc1", sh2="dark3"),
        "disabled": dict(line="dark3", hl="dark3", face="dark1", sh="dark1", sh2="dark1"),
    }[state]
    im = canvas(s, s)
    rect(im, 0, 0, s - 1, s - 1, pal["line"])
    rect(im, 1, 1, s - 2, s - 2, pal["face"])
    # luz: alto/esquerda = hl, base/direita = sh
    rect(im, 1, 1, s - 2, 1, pal["hl"])
    rect(im, 1, 1, 1, s - 2, pal["hl"])
    rect(im, 2, s - 2, s - 2, s - 2, pal["sh"])
    rect(im, s - 2, 2, s - 2, s - 2, pal["sh"])
    if state in ("normal", "hover"):
        rect(im, 2, s - 3, s - 3, s - 3, pal["sh2"] if state == "normal" else pal["sh"])
        rect(im, s - 3, 3, s - 3, s - 3, pal["sh2"] if state == "normal" else pal["sh"])
    if state == "pressed":
        rect(im, 2, 2, s - 3, 2, pal["hl"])  # sombra interna no alto
        rect(im, 2, 2, 2, s - 3, pal["hl"])
    for cx, cy in ((0, 0), (s - 1, 0), (0, s - 1), (s - 1, s - 1)):
        im.putpixel((cx, cy), (0, 0, 0, 0))
    # com o canto livre, o pixel diagonal ganha o realce
    if state != "disabled":
        put(im, 1, 1, pal["hl"] if state != "pressed" else "dark1")
    return im


def make_bar_back():
    """8x6, margens 3. Calha escura; o preenchimento cobre o mesmo retângulo."""
    im = canvas(8, 6)
    rect(im, 0, 0, 7, 5, "ink")
    rect(im, 1, 1, 6, 4, "dark1")
    rect(im, 1, 4, 6, 4, "dark2")
    for cx, cy in ((0, 0), (7, 0), (0, 5), (7, 5)):
        im.putpixel((cx, cy), (0, 0, 0, 0))
    return im


def make_bar_fill():
    """8x6, margens 3. Mesmo retângulo da calha; contorno ink + enchimento âmbar."""
    im = canvas(8, 6)
    rect(im, 0, 0, 7, 5, "ink")
    rect(im, 1, 1, 6, 1, "amber3")
    rect(im, 1, 2, 6, 3, "amber2")
    rect(im, 1, 4, 6, 4, "amber1")
    for cx, cy in ((0, 0), (7, 0), (0, 5), (7, 5)):
        im.putpixel((cx, cy), (0, 0, 0, 0))
    return im


def make_tab(active):
    """12x10, margens 3. Aba sem borda de baixo quando ativa (cola no painel)."""
    w, h = 12, 10
    im = canvas(w, h)
    if active:
        rect(im, 0, 0, w - 1, h - 1, "ink")
        rect(im, 1, 1, w - 2, h - 1, "dark2")
        rect(im, 1, 1, w - 2, 1, "rust3")
        rect(im, 1, 2, w - 2, 2, "rust2")
        rect(im, 1, 3, 1, h - 1, "dark1")
        rect(im, w - 2, 3, w - 2, h - 1, "dark3")
        rect(im, 0, h - 1, 0, h - 1, "ink")
        # base aberta: o centro/base é o mesmo tom do miolo do painel
        rect(im, 2, h - 1, w - 3, h - 1, "dark2")
        rect(im, 2, 3, w - 3, h - 2, "dark2")
        im.putpixel((1, h - 1), RGB["dark2"] + (255,))
        im.putpixel((w - 2, h - 1), RGB["dark2"] + (255,))
        put(im, 1, h - 1, "dark2")
        put(im, w - 2, h - 1, "dark2")
    else:
        rect(im, 0, 0, w - 1, h - 1, "ink")
        rect(im, 1, 1, w - 2, h - 2, "dark1")
        rect(im, 1, 1, w - 2, 1, "dark3")
        rect(im, 1, h - 2, w - 2, h - 2, "dark2")
    for cx, cy in ((0, 0), (w - 1, 0)):
        im.putpixel((cx, cy), (0, 0, 0, 0))
    return im


# ---------------------------------------------------------------- ícones 8x8
# Legenda: K ink, D dark3, c conc2, C conc3, W conc4, P paper, A amber2, a amber1, B amber3,
# R rust3, r rust2, x rust1, Q rust4, T tomato, N bean, q skin1, s skin2, L leaf3, l leaf2,
# G leaf4, S signal (SÓ estrela e check).
LEG = dict(K="ink", D="dark3", c="conc2", C="conc3", W="conc4", P="paper", A="amber2", a="amber1",
           B="amber3", R="rust3", r="rust2", x="rust1", Q="rust4", T="tomato", N="bean", q="skin1",
           s="skin2", L="leaf3", l="leaf2", G="leaf4", S="signal", k="ink", d="dark2")

ICONS = {
    "sucata": [  # porca sextavada enferrujada
        ".RRRRRR.",
        "RQQQQQQr",
        "RQQQQQQr",
        "RQQkkQQr",
        "RQQkkQQr",
        "rQQQQQQx",
        "rQQQQQxx",
        ".xxxxxx.",
    ],
    "cesto": [
        "..NNNN..",
        ".N....N.",
        ".N....N.",
        "NNNNNNNN",
        "NRNRNRNx",
        "NNRNRNRx",
        ".NRNRNx.",
        "..xxxx..",
    ],
    "energia": [
        "....BBB.",
        "...BBA..",
        "..BBA...",
        ".BBBBBB.",
        "..AAABA.",
        "...BA...",
        "..BA....",
        ".aA.....",
    ],
    "radio": [
        ".....CW.",
        "....C...",
        "CCCCCCCC",
        "CkkkkWAC",
        "CkWkkWWC",
        "CkkkkWAC",
        "CCCCCCCC",
        ".D....D.",
    ],
    "antena": [
        "...WW...",
        "W..WW..W",
        "WW.WW.WW",
        ".WWWWWW.",
        "...CC...",
        "..CCCC..",
        "...CC...",
        ".CCCCCC.",
    ],
    "espaco": [
        "WWW..WWW",
        "W......W",
        "W......W",
        "...cc...",
        "...cc...",
        "W......W",
        "W......W",
        "WWW..WWW",
    ],
    "tempo": [
        "..CCCC..",
        ".CPPPPC.",
        "CPPPkPPC",
        "CPPPkPPC",
        "CPPPkkPC",
        "CPPPPPPC",
        ".CPPPPC.",
        "..CCCC..",
    ],
    "porta": [
        ".CCCCCC.",
        ".CRRRRC.",
        ".CRRRRC.",
        ".CRRRRC.",
        ".CRRARC.",
        ".CRRRRC.",
        ".CRRRRC.",
        "CCCCCCCC",
    ],
    "historia": [
        ".PPPPPP.",
        "PPPPPPPP",
        "PKKKKKKP",
        "PPPPPPPP",
        "PKKKKPPP",
        "PPPPPPPP",
        ".PPP....",
        "..P.....",
    ],
    "renda": [
        "..AAAA..",
        ".ABBBBa.",
        "ABBBaBBa",
        "ABBaaaBa",
        "ABBBaBBa",
        "ABBaaBBa",
        ".aBBBBa.",
        "..aaaa..",
    ],
    "estrela": [
        "...SS...",
        "..SSSS..",
        "SSSSSSSS",
        ".SSSSSS.",
        "..SSSS..",
        ".SSSSSS.",
        ".SS..SS.",
        "........",
    ],
    "check": [
        "........",
        "......SS",
        ".....SSS",
        "S...SSS.",
        "SS.SSS..",
        "SSSSS...",
        ".SSS....",
        "..S.....",
    ],
    "lock": [
        "..WWWW..",
        ".W....W.",
        ".W....W.",
        "AAAAAAAA",
        "ABBBBBBa",
        "ABBkkBBa",
        "ABBkkBBa",
        "aaaaaaaa",
    ],
    "arrow_up": [
        "...WW...",
        "..WWWW..",
        ".WWWWWW.",
        "WW.WW.WW",
        "...WW...",
        "...WW...",
        "...WW...",
        "........",
    ],
    "arrow_down": [
        "........",
        "...WW...",
        "...WW...",
        "...WW...",
        "WW.WW.WW",
        ".WWWWWW.",
        "..WWWW..",
        "...WW...",
    ],
    "close": [
        "........",
        ".WW..WW.",
        "..WWWW..",
        "...WW...",
        "...WW...",
        "..WWWW..",
        ".WW..WW.",
        "........",
    ],
    "speaker_on": [
        "........",
        "...W..W.",
        "..WW...W",
        "WWWW.W.W",
        "WWWW.W.W",
        "..WW...W",
        "...W..W.",
        "........",
    ],
    "speaker_off": [
        "........",
        "...W....",
        "..WW.W.W",
        "WWWW..W.",
        "WWWW..W.",
        "..WW.W.W",
        "...W....",
        "........",
    ],
    "hide": [  # olho fechado
        "........",
        "........",
        "WW....WW",
        ".WWWWWW.",
        ".W.WW.W.",
        "...WW...",
        "........",
        "........",
    ],
    "show": [  # olho aberto
        "........",
        "..WWWW..",
        ".WPPPPW.",
        "WPPkkPPW",
        "WPPkkPPW",
        ".WPPPPW.",
        "..WWWW..",
        "........",
    ],
    "gear": [
        "...WW...",
        ".W.WW.W.",
        "..WWWW..",
        "WWWkkWWW",
        "WWWkkWWW",
        "..WWWW..",
        ".W.WW.W.",
        "...WW...",
    ],
    "book": [
        ".xRRRRR.",
        ".xRRRRR.",
        ".xRAAAR.",
        ".xRRRRR.",
        ".xRAARR.",
        ".xRRRRR.",
        ".PPPPPP.",
        "..xxxxx.",
    ],
    "hammer": [
        ".CCCCCC.",
        "CWWWWWWc",
        ".CCCCCC.",
        "...NN...",
        "...NN...",
        "...NN...",
        "...NN...",
        "...xx...",
    ],
    "home": [
        "...RR...",
        "..RRRR..",
        ".RRRRRR.",
        "RRRRRRRR",
        ".PPPPPP.",
        ".PPKKPP.",
        ".PPKKPP.",
        ".PPKKPP.",
    ],
    "plus": [
        "........",
        "...WW...",
        "...WW...",
        ".WWWWWW.",
        ".WWWWWW.",
        "...WW...",
        "...WW...",
        "........",
    ],
    "crop_batata": [
        "........",
        "..qqqq..",
        ".qsssqq.",
        "qssNsssq",
        "qsssssNq",
        "qsNsssqq",
        ".qsssqq.",
        "..qqqq..",
    ],
    "crop_feijao": [
        "......LL",
        ".....LGL",
        "....LGLl",
        "...LGGLl",
        "..LGNGLl",
        ".LGGLLl.",
        "LGLLl...",
        "LLl.....",
    ],
    "crop_tomate": [
        "...L.L..",
        "..LLLL..",
        ".TTLLTT.",
        "TQQTTTTT",
        "TQTTTTTT",
        "TTTTTTTx",
        ".TTTTTx.",
        "..xxxx..",
    ],
    "grab": [
        ".C.C.C..",
        ".C.C.C.C",
        ".CWCWCWC",
        ".CWWWWWC",
        ".CWWWWWC",
        "..CWWWC.",
        "..CWWWC.",
        "...CCC..",
    ],
}

ICON_ORDER = ["sucata", "cesto", "energia", "radio", "antena", "espaco", "tempo", "porta", "historia", "renda",
              "estrela", "check", "lock", "arrow_up", "arrow_down", "close", "speaker_on", "speaker_off", "hide",
              "show", "gear", "book", "hammer", "home", "plus", "crop_batata", "crop_feijao", "crop_tomate", "grab"]
assert set(ICON_ORDER) == set(ICONS) and len(ICON_ORDER) == len(ICONS)


# ---------------------------------------------------------------- principal


def contact_sheet(files):
    """Folha ampliada: ícones x6 sobre dark2 e sobre botão; amostras x1 e x3; mock de painel."""
    Z = 6
    cols = 10
    cell = 8 * Z + 10
    rows = (len(ICON_ORDER) + cols - 1) // cols
    W = max(cols * cell + 10, 640)
    # parte 1: ícones x6
    sheet = Image.new("RGBA", (W, rows * (cell + 12) + 10 + 400), RGB["dark1"] + (255,))
    d = ImageDraw.Draw(sheet)
    for i, name in enumerate(ICON_ORDER):
        ic = Image.open(files["icon_" + name]).convert("RGBA")
        cx = 10 + (i % cols) * cell
        cy = 10 + (i // cols) * (cell + 12)
        d.rectangle([cx - 2, cy - 2, cx + 8 * Z + 1, cy + 8 * Z + 1], fill=RGB["dark2"] + (255,))
        sheet.alpha_composite(ic.resize((8 * Z, 8 * Z), Image.NEAREST), (cx, cy))
        d.text((cx, cy + 8 * Z + 1), name[:10], fill=RGB["conc3"] + (255,))
    base = rows * (cell + 12) + 20
    # parte 2: x1 e x3 numa tira, sobre painel e sobre botão
    panel = Image.open(files["panel_9s"]).convert("RGBA")
    btn = Image.open(files["button_9s_normal"]).convert("RGBA")

    def nine(src, w, h, m):
        out = canvas(w, h)
        sw, sh = src.size
        xs = [(0, m[0], 0, m[0]), (m[0], sw - m[2], m[0], w - m[2]), (sw - m[2], sw, w - m[2], w)]
        ys = [(0, m[1], 0, m[1]), (m[1], sh - m[3], m[1], h - m[3]), (sh - m[3], sh, h - m[3], h)]
        for sx0, sx1, dx0, dx1 in xs:
            for sy0, sy1, dy0, dy1 in ys:
                piece = src.crop((sx0, sy0, sx1, sy1))
                if dx1 > dx0 and dy1 > dy0:
                    out.alpha_composite(piece.resize((dx1 - dx0, dy1 - dy0), Image.NEAREST), (dx0, dy0))
        return out

    # mock x1 (tamanho real) e x3
    mock = canvas(200, 76)
    mock.alpha_composite(nine(panel, 200, 76, (5, 5, 5, 5)), (0, 0))
    x = 8
    for name in ICON_ORDER:
        if x + 9 > 192:
            break
        mock.alpha_composite(Image.open(files["icon_" + name]).convert("RGBA"), (x, 8))
        x += 9
    # linha de ícones sobre botão
    x = 8
    for name in ("gear", "plus", "close", "speaker_on", "hide", "home", "hammer", "book"):
        b = nine(btn, 14, 14, (4, 4, 4, 4))
        b.alpha_composite(Image.open(files["icon_" + name]).convert("RGBA"), (3, 3))
        mock.alpha_composite(b, (x, 22))
        x += 16
    # botões 4 estados
    x = 8
    for st in ("normal", "hover", "pressed", "disabled"):
        b = nine(Image.open(files["button_9s_" + st]).convert("RGBA"), 36, 14, (4, 4, 4, 4))
        mock.alpha_composite(b, (x, 40))
        x += 40
    # barras
    back = Image.open(files["bar_back_9s"]).convert("RGBA")
    fill = Image.open(files["bar_fill_9s"]).convert("RGBA")
    mock.alpha_composite(nine(back, 60, 6, (3, 3, 3, 3)), (8, 58))
    mock.alpha_composite(nine(fill, 36, 6, (3, 3, 3, 3)), (8, 58))
    # abas
    mock.alpha_composite(nine(Image.open(files["tab_active"]).convert("RGBA"), 36, 10, (3, 3, 3, 3)), (84, 56))
    mock.alpha_composite(nine(Image.open(files["tab_normal"]).convert("RGBA"), 36, 10, (3, 3, 3, 3)), (122, 58))
    mock.alpha_composite(nine(Image.open(files["tab_normal"]).convert("RGBA"), 36, 10, (3, 3, 3, 3)), (160, 58))
    y = base
    bg1 = Image.new("RGBA", mock.size, RGB["dark1"] + (255,))
    bg1.alpha_composite(mock)
    sheet.alpha_composite(bg1, (10, y))                       # x1 (tamanho real)
    sheet.alpha_composite(bg1.resize((200 * 3, 76 * 3), Image.NEAREST), (10, y + 86))  # x3
    sheet = sheet.crop((0, 0, sheet.width, y + 86 + 76 * 3 + 10))
    path = os.path.join(OUT, "_contact_ui.png")
    sheet.convert("RGB").save(path)
    return path


def main():
    os.makedirs(OUT, exist_ok=True)
    files, manifest = {}, {}

    def save(name, img, **extra):
        img = snap_image(img)
        path = os.path.join(OUT, name + ".png")
        img.save(path)
        files[name] = path
        entry = {"file": "ui/%s.png" % name, "frame_w": img.width, "frame_h": img.height, "frames": 1, "fps": 0,
                 "anchor": [0, 0]}
        entry.update(extra)
        manifest[name] = entry

    save("panel_9s", make_panel(), margins=[5, 5, 5, 5])
    for st in ("normal", "hover", "pressed", "disabled"):
        save("button_9s_" + st, make_button(st), margins=[4, 4, 4, 4])
    save("bar_back_9s", make_bar_back(), margins=[3, 3, 3, 3])
    save("bar_fill_9s", make_bar_fill(), margins=[3, 3, 3, 3])
    save("tab_normal", make_tab(False), margins=[3, 3, 3, 3])
    save("tab_active", make_tab(True), margins=[3, 3, 3, 3])
    for name in ICON_ORDER:
        ic = from_rows(ICONS[name], LEG)
        if name == "hide":  # olho aberto com risco diagonal (halo ink + traço claro)
            ic = from_rows(ICONS["show"], LEG)
            slash = [(0, 7), (1, 6), (2, 5), (3, 4), (4, 3), (5, 2), (6, 1), (7, 0)]
            for x, y in slash:
                inside = ic.getpixel((x, y))[3] != 0
                put(ic, x, y, "ink" if inside else "conc4")
            for x, y in ((1, 7), (6, 0)):  # prolonga o traço fora do olho
                put(ic, x, y, "conc4")
        save("icon_" + name, ic, anchor=[4, 4])
    manifest["icon_estrela"]["note"] = "cor signal (sinal)"
    manifest["icon_check"]["note"] = "cor signal (sinal)"

    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=1)

    # verificação: paleta + signal só em estrela/check
    problems = []
    sig = RGB["signal"]
    for name, p in files.items():
        bad = check_image(p)
        if bad:
            problems.append((name, bad))
        im = Image.open(p).convert("RGBA")
        has_sig = any(px[:3] == sig and px[3] == 255 for px in im.get_flattened_data()) if hasattr(im,'get_flattened_data') else any(px[:3] == sig and px[3] == 255 for px in im.getdata())
        if has_sig and name not in ("icon_estrela", "icon_check"):
            problems.append((name, "usa signal"))
        if not has_sig and name in ("icon_estrela", "icon_check"):
            problems.append((name, "faltou signal"))
    contact_sheet(files)
    print("OK" if not problems else problems)
    print(len(files), "arquivos")


if __name__ == "__main__":
    main()
