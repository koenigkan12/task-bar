#!/usr/bin/env python3
"""Vista composta do corte do bunker (88 px de altura; 208 e 408 de largura) usando só os PNGs de assets/art/env.

Uso: python3 tools/art/preview_env.py   (rode make_env.py antes)
Escreve assets/art/env/_preview_bunker.png (x4; as duas larguras empilhadas) e
_preview_bunker_lit.png (mesma cena com um cone de luz da lâmpada e do poço, só para ver o clima).
O céu aqui é uma aproximação feita por código (no jogo é gerado pela cena).
"""
import json
import os
import random
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from palette import RGB, snap_image, check_image  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ENV = os.path.join(ROOT, "assets", "art", "env")
MAN = json.load(open(os.path.join(ROOT, "assets", "art", "manifest_env.json"), encoding="utf-8"))
ZOOM = 4

_cache = {}


def frame(name, i=0):
    key = (name, i)
    if key not in _cache:
        m = MAN[name]
        im = Image.open(os.path.join(ENV, m["file"].split("/")[-1])).convert("RGBA")
        fw, fh = m["frame_w"], m["frame_h"]
        _cache[key] = im.crop((i * fw, 0, (i + 1) * fw, fh))
    return _cache[key]


def put(canvas, name, x, y, i=0):
    canvas.alpha_composite(frame(name, i), (x, y))


def sky(canvas, w, tod="day"):
    """Céu em faixas (cloth2 -> conc4) com dither de Bayer e uma silhueta de ruínas ao longe."""
    bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    top, bot = RGB["cloth2"], RGB["conc4"]
    px = canvas.load()
    for y in range(24):
        t = y / 23.0
        for x in range(w):
            thr = (bayer[y % 4][x % 4] + 0.5) / 16.0
            px[x, y] = (bot if t * 1.15 - 0.1 > thr else top) + (255,)
    r = random.Random(4)
    x = 0
    while x < w:
        bw = r.randint(5, 14)
        bh = r.randint(2, 8)
        col = RGB["conc2"] if r.random() < 0.6 else RGB["conc3"]
        for xx in range(x, min(w, x + bw)):
            for yy in range(24 - bh, 24):
                px[xx, yy] = col + (255,)
        # janelas partidas
        x += bw + r.randint(0, 6)


def build(n_rooms, lit=False):
    w = 8 + n_rooms * 200
    H = 88
    c = Image.new("RGBA", (w, H), (0, 0, 0, 255))
    sky(c, w)
    rr = random.Random(11)
    # grama e terra
    for x in range(0, w, 16):
        put(c, "grass_%d" % [0, 1, 0, 2, 1, 0, 2, 0][(x // 16) % 8], x, 24)
    for y in range(32, H, 16):
        for x in range(0, w, 16):
            put(c, "earth_%d" % rr.randrange(4), x, y)
    # decoração de terra: algumas
    for (x, y, k) in ((216, 40, 1), (232, 40, 0), (360, 40, 2), (0, 40, 0), (200 if n_rooms == 1 else 392, 56, 1)):
        if x + 16 <= w:
            put(c, "earth_deco_%d" % k, x, y)
    # salas
    for i in range(n_rooms):
        x0 = 8 + i * 200
        for x in range(x0, x0 + 192, 16):
            put(c, "ceiling_%d" % ((x // 16 + i) % 2 if (x // 16) % 3 == 0 else 0), x, 32)
            put(c, "ceiling_0", x, 32) if False else None
        for x in range(x0, x0 + 192, 16):
            k = [0, 0, 1, 0, 0, 2, 0, 3, 0, 0, 1, 0][((x - x0) // 16 + i * 5) % 12]
            put(c, "wall_%d" % k, x, 40)
            put(c, "wall_%d" % ((k + 0) % 2 if k in (0, 1) else k), x, 56) if False else None
        for x in range(x0, x0 + 192, 16):
            k = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11][(x - x0) // 16]
            kk = [0, 2, 0, 1, 0, 0, 3, 0, 2, 0, 0, 1][(k + i * 3) % 12]
            put(c, "wall_%d" % kk, x, 56)
            put(c, "floor_0", x, 80)
        # a linha de baixo da parede: corta em 72..80 (parede só vai até y 80)
        # (o floor foi pintado depois; wall rows 40, 56 e 72)
        for x in range(x0, x0 + 192, 16):
            kk = [1, 0, 0, 2, 0, 0, 0, 3, 0, 1, 0, 0][((x - x0) // 16 + i * 7) % 12]
            put(c, "wall_%d" % kk, x, 72)
        for x in range(x0, x0 + 192, 16):
            put(c, "floor_0", x, 80)
    # divisórias entre salas (com vão de porta)
    for i in range(n_rooms - 1):
        # limpa a terra do vão: parede de fundo atrás do vão
        xd = 8 + i * 200 + 192
        for y in (40, 56, 72):
            put(c, "wall_0", xd, y) if False else None
        # parede de fundo do vão: usa recortes de wall_0 (8 px)
        for y in (48, 64):
            c.alpha_composite(frame("wall_0").crop((0, 0, 8, 16)), (xd, y))
        put(c, "divider", xd, 32)
    # poço da escada: coluna 0 da sala 1 (x 8..24), do teto ao chão
    for y in (32, 48, 64):
        put(c, "ladder", 8, y)
    # escotilha (fechada) sobre a grama, x 8..40, base em y 32
    put(c, "hatch", 8, 16, 0)
    # caixa da escotilha (col. 1), mesa do rádio (col. 2), cama (cols 10-11)
    put(c, "hatch_box", 24, 64, 2)
    put(c, "radio_table", 40, 64, 1)
    put(c, "radio_glow", 40, 64, 1)
    put(c, "bed", 8 + 160, 64)
    put(c, "scrap_pile", 8 + 16 * 5, 64, 0)
    put(c, "fx_zzz", 8 + 170, 56, 2)
    # lâmpadas (acesas)
    lamp_x = 8 + 16 * 5 + 0
    put(c, "lamp", lamp_x, 40, 1)
    lamps = [(lamp_x + 8, 46)]
    if n_rooms >= 2:
        x1 = 8 + 200
        put(c, "lamp", x1 + 16 * 6, 40, 1)
        put(c, "scrap_pile", x1 + 16 * 3, 64, 1)
        put(c, "scrap_pile", x1 + 16 * 9, 64, 2)
        put(c, "hatch_box", x1 + 16 * 2, 64, 3)
        put(c, "fx_drip", x1 + 16 * 8 + 6, 52, 1)
        put(c, "fx_steam", x1 + 16 * 5, 56, 1)
        lamps.append((x1 + 16 * 6 + 8, 46))
    # antena 1 (base em y 24, x ~ 56)
    put(c, "antenna_1", 56 - 12, 0)
    if lit:
        c = light_pass(c, lamps, w)
    return snap_image(c)


def light_pass(c, lamps, w):
    """Aproximação do cone de luz: escurece com dither longe das lâmpadas e esquenta perto (só preview)."""
    bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    px = c.load()
    amber = RGB["amber2"]
    for y in range(32, 88):
        for x in range(w):
            r, g, b, a = px[x, y]
            best = 0.0
            for (lx, ly) in lamps:
                d = ((x - lx) ** 2 + ((y - ly) * 1.3) ** 2) ** 0.5
                best = max(best, max(0.0, 1.0 - d / 70.0))
            # poço de luz do dia na coluna da escada
            if 8 <= x < 24:
                best = max(best, max(0.0, 0.8 - (y - 32) / 70.0))
            lum = 0.55 + 0.5 * best
            warm = 0.22 * best
            thr = ((bayer[y % 4][x % 4] + 0.5) / 16.0 - 0.5) * 0.08
            nr = min(255, (r * (lum + thr)) + amber[0] * warm)
            ng = min(255, (g * (lum + thr)) + amber[1] * warm * 0.9)
            nb = min(255, (b * (lum + thr)) + amber[2] * warm * 0.5)
            px[x, y] = (int(nr), int(ng), int(nb), 255)
    return c


def main():
    a = build(1)
    b = build(2)
    W = b.width * ZOOM
    pad = 8
    sheet = Image.new("RGBA", (W, a.height * ZOOM + b.height * ZOOM + pad), RGB["ink"] + (255,))
    sheet.alpha_composite(a.resize((a.width * ZOOM, a.height * ZOOM), Image.NEAREST), (0, 0))
    sheet.alpha_composite(b.resize((b.width * ZOOM, b.height * ZOOM), Image.NEAREST), (0, a.height * ZOOM + pad))
    sheet.save(os.path.join(ENV, "_preview_bunker.png"))
    al, bl = build(1, True), build(2, True)
    sheet = Image.new("RGBA", (W, al.height * ZOOM + bl.height * ZOOM + pad), RGB["ink"] + (255,))
    sheet.alpha_composite(al.resize((al.width * ZOOM, al.height * ZOOM), Image.NEAREST), (0, 0))
    sheet.alpha_composite(bl.resize((bl.width * ZOOM, bl.height * ZOOM), Image.NEAREST), (0, al.height * ZOOM + pad))
    sheet.save(os.path.join(ENV, "_preview_bunker_lit.png"))
    for n in ("_preview_bunker", "_preview_bunker_lit"):
        bad = check_image(os.path.join(ENV, n + ".png"))
        print(n, "OK" if not bad else bad)


if __name__ == "__main__":
    main()
