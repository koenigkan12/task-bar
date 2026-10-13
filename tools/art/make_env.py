#!/usr/bin/env python3
"""Gerador da arte de AMBIENTE (terra, grama, sala, escada, escotilha, antenas, rádio, cama, lâmpada, fx).

Uso: python3 tools/art/make_env.py   (idempotente: mesma semente => mesmos PNGs)
Escreve assets/art/env/*.png, assets/art/manifest_env.json e a folha de contato
assets/art/env/_contact_env.png (fora do manifesto). Toda cor vem de palette.py.
"""
import json
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from palette import RGB, snap_image, check_image  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "art", "env")

# letra -> cor da paleta (para os mapas ASCII e para o código)
KEY = {
    "k": "ink", "1": "dark1", "2": "dark2", "3": "dark3",
    "a": "conc1", "b": "conc2", "c": "conc3", "d": "conc4",
    "r": "rust1", "R": "rust2", "u": "rust3", "U": "rust4",
    "e": "amber1", "E": "amber2", "F": "amber3", "G": "amber4",
    "g": "leaf1", "h": "leaf2", "i": "leaf3", "j": "leaf4",
    "s": "skin1", "S": "skin2", "o": "cloth1", "O": "cloth2",
    "p": "paper", "t": "tomato", "n": "bean", "x": "signal",
}


class Spr:
    """Quadro de pixels com nomes de cor (letras de KEY); None = transparente."""

    def __init__(self, w, h, fill=None):
        self.w, self.h = w, h
        self.p = [[fill] * w for _ in range(h)]

    # --- primitivas -------------------------------------------------
    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.p[y][x] = c

    def setw(self, x, y, c):  # com emenda (wrap) — para tiles
        self.p[y % self.h][x % self.w] = c

    def get(self, x, y):
        return self.p[y % self.h][x % self.w]

    def fill(self, c):
        for y in range(self.h):
            for x in range(self.w):
                self.p[y][x] = c

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, c)

    def hl(self, x, y, n, c):
        for i in range(n):
            self.set(x + i, y, c)

    def vl(self, x, y, n, c):
        for i in range(n):
            self.set(x, y + i, c)

    def line(self, x0, y0, x1, y1, c):
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.set(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def ellipse(self, cx, cy, rx, ry, c, wrap=False):
        for dy in range(-ry, ry + 1):
            for dx in range(-rx, rx + 1):
                if (dx * dx) / (rx * rx + 0.01) + (dy * dy) / (ry * ry + 0.01) <= 1.0:
                    (self.setw if wrap else self.set)(cx + dx, cy + dy, c)

    def stamp(self, rows, ox=0, oy=0):
        """Aplica um mapa ASCII ('.' = não mexe)."""
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                if ch != "." and ch != " ":
                    self.set(ox + i, oy + j, ch)

    def outline(self, c="k"):
        """Contorno externo de 1 px (só em pixels vazios vizinhos de pixels cheios)."""
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.p[y][x] is None:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        xx, yy = x + dx, y + dy
                        if 0 <= xx < self.w and 0 <= yy < self.h and self.p[yy][xx] not in (None, c):
                            add.append((x, y))
                            break
        for x, y in add:
            self.p[y][x] = c

    def copy(self):
        n = Spr(self.w, self.h)
        n.p = [row[:] for row in self.p]
        return n

    def image(self):
        im = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        px = im.load()
        for y in range(self.h):
            for x in range(self.w):
                c = self.p[y][x]
                if c is not None:
                    name = KEY.get(c, c)
                    r, g, b = RGB[name]
                    px[x, y] = (r, g, b, 255)
        return im


def ascii_spr(rows):
    w = len(rows[0])
    for r in rows:
        assert len(r) == w, ("largura inconsistente", r, len(r), w)
    s = Spr(w, len(rows))
    s.stamp(rows)
    return s


def strip(frames):
    w = sum(f.w for f in frames)
    h = frames[0].h
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    x = 0
    for f in frames:
        assert f.h == h
        im.paste(f.image(), (x, 0))
        x += f.w
    return im


# ======================================================================
# TILES: terra, grama, parede, chão, teto
# ======================================================================
def blob(s, r, cx, cy, rx, ry, c):
    s.ellipse(cx, cy, rx, ry, c, wrap=True)


def earth_base(seed, tone=0):
    """Terra maciça 16x16, emenda perfeita (tudo com wrap). Lentes horizontais dão a ideia de camadas."""
    r = random.Random(seed)
    s = Spr(16, 16, "2")
    # manchas de tom (lentes achatadas = camadas)
    for _ in range(3):
        blob(s, r, r.randrange(16), r.randrange(16), r.randint(3, 6), r.randint(0, 1), "3")
    for _ in range(3):
        blob(s, r, r.randrange(16), r.randrange(16), r.randint(2, 5), r.randint(0, 1), "1")
    for _ in range(4):
        blob(s, r, r.randrange(16), r.randrange(16), r.randint(1, 2), 1, "1")
    # grão
    for _ in range(14):
        s.setw(r.randrange(16), r.randrange(16), r.choice("3311"))
    # raspas de ferrugem/raiz podre
    for _ in range(3 + tone):
        s.setw(r.randrange(16), r.randrange(16), "r")
    return s


def earth(i):
    s = earth_base(100 + i, tone=i % 2)
    r = random.Random(900 + i)
    # pedrinha pequena com sombra, em posição diferente em cada variante
    px, py = r.randrange(2, 13), r.randrange(2, 13)
    if i in (0, 2):
        s.set(px, py, "a"); s.set(px + 1, py, "a"); s.set(px, py + 1, "3"); s.set(px + 1, py + 1, "3")
        s.set(px - 1, py + 1, "1"); s.set(px + 2, py + 1, "1")
    return s


def earth_deco(i):
    s = earth_base(200 + i)
    if i == 0:  # pedra
        s.stamp([
            "..kkkk..",
            ".kcbbbak",
            "kcbbaaak",
            "kbbaaa3k",
            "kbaaa33k",
            ".k3333k.",
            "..kkkk..",
        ], 4, 4)
        s.set(5, 6, "d")
    elif i == 1:  # raízes
        rt = "n"
        for (x0, y0, x1, y1) in ((0, 3, 5, 5), (5, 5, 9, 8), (9, 8, 11, 13), (9, 8, 15, 9), (5, 5, 7, 11)):
            s.line(x0, y0, x1, y1, rt)
        for (x, y) in ((1, 3), (6, 5), (10, 9), (12, 8)):
            s.set(x, y, "s")
        s.set(7, 12, "n"); s.set(11, 14, "n")
    else:  # lata enterrada
        s.stamp([
            ".kkkkkkkk.",
            "kbcccccbrk",
            "kbbbaaabrk",
            "kaRRRRRrak",
            "kaRuRRRrak",
            "kaRRRRrrak",
            "kaaaaaa3ak",
            ".k333333k.",
            "..kkkkkk..",
        ], 3, 4)
        s.hl(5, 5, 6, "d")
    return s


def grass(i):
    """16x8: lâminas em cima, raízes/terra embaixo. Emenda horizontal garantida (colunas independentes por wrap)."""
    r = random.Random(300 + i)
    s = Spr(16, 8)
    # corpo
    s.rect(0, 3, 16, 2, "h")
    s.rect(0, 5, 16, 1, "g")
    # terra por baixo (continua em earth)
    s.rect(0, 6, 16, 2, "2")
    for x in range(16):
        if r.random() < 0.5:
            s.set(x, 6, "r")
        if r.random() < 0.4:
            s.set(x, 7, "3")
        if r.random() < 0.35:
            s.set(x, 5, "h")
    # lâminas: altura por coluna, com grupos
    heights = [0] * 16
    for _ in range(5 + i):
        cx = r.randrange(16)
        hgt = r.randint(2, 4)
        for d in (-1, 0, 1):
            heights[(cx + d) % 16] = max(heights[(cx + d) % 16], hgt - (1 if d else 0))
    for x in range(16):
        top = 3 - heights[x]
        for y in range(max(top, 0), 3):
            s.set(x, y, "i" if (x + y) % 3 else "h")
        if heights[x] >= 2:
            s.set(x, max(top, 0), "j")
    # algumas hastes secas (apocalipse) e uma florzinha
    if i >= 1:
        x = r.randrange(16)
        s.set(x, 0, "e"); s.set(x, 1, "n")
    if i == 2:
        x = (r.randrange(16) + 5) % 16
        s.set(x, 1, "F"); s.set(x, 2, "h")
    # tufos do chão
    for x in range(16):
        s.set(x, 4, "g" if r.random() < 0.3 else s.p[4][x])
    return s


def wall_base(seed, rich=True):
    """Concreto de painéis: só junta vertical à esquerda (painéis altos), manchas suaves com wrap."""
    r = random.Random(seed)
    s = Spr(16, 16, "a")
    for _ in range(2):
        blob(s, r, r.randrange(16), r.randrange(16), r.randint(2, 3), 1, "b")
    for _ in range(2):
        blob(s, r, r.randrange(16), r.randrange(16), r.randint(2, 3), 1, "3")
    for _ in range(8):
        s.setw(r.randrange(16), r.randrange(16), r.choice("b3"))
    # junta vertical: sombra + brilho
    s.vl(0, 0, 16, "3")
    s.vl(1, 0, 16, "b")
    # furo de fôrma
    tx, ty = r.randrange(5, 11), r.randrange(4, 12)
    s.set(tx, ty, "2"); s.set(tx + 1, ty, "3"); s.set(tx, ty + 1, "3"); s.set(tx + 1, ty + 1, "2")
    s.set(tx - 1, ty - 1, "b")
    return s


def wall(i):
    s = wall_base(400 + i)
    if i == 1:  # umidade escorrida
        for y in range(2, 14):
            w = 1 + (y % 3 == 0)
            s.hl(6, y, w + 1, "3")
            if y > 5:
                s.set(5 + (y % 2), y, "3")
        s.hl(5, 14, 5, "3"); s.hl(6, 15, 3, "2")
        s.set(7, 13, "c"); s.set(8, 14, "c")
        for (x, y) in ((11, 8), (12, 9), (11, 10), (12, 11)):
            s.set(x, y, "3")
    elif i == 2:  # rachadura e ferro aparecendo
        pts = [(4, 2), (5, 4), (4, 6), (6, 8), (7, 10), (6, 12), (8, 14)]
        for a, b in zip(pts, pts[1:]):
            s.line(a[0], a[1], b[0], b[1], "2")
        s.line(6, 8, 10, 9, "2"); s.set(11, 10, "2")
        s.set(5, 3, "b"); s.set(7, 9, "b")
        s.set(9, 5, "R"); s.set(10, 5, "r"); s.set(9, 6, "r")  # ferrugem escorrida de um vergalhão
        s.set(10, 6, "R"); s.set(10, 7, "r")
        s.rect(3, 12, 2, 2, "2")
    elif i == 3:  # contagem de dias riscada na parede (2 grupos de 5)
        for k in range(4):
            s.vl(5 + k * 2, 4, 4, "3")
        s.line(4, 7, 12, 4, "3")
        for k in range(2):
            s.vl(5 + k * 2, 10, 4, "3")
    return s


def floor_tile(i):
    """16x8: borda de cima iluminada, corpo, base escura. Tiles de 8 px de altura."""
    r = random.Random(500 + i)
    if i == 0:  # concreto
        s = Spr(16, 8, "a")
        for _ in range(3):
            blob(s, r, r.randrange(16), r.randrange(8), r.randint(2, 4), 1, "b")
        for _ in range(3):
            blob(s, r, r.randrange(16), r.randrange(8), r.randint(2, 3), 1, "3")
        for _ in range(10):
            s.setw(r.randrange(16), r.randint(2, 6), r.choice("b3a"))
        s.hl(0, 0, 16, "c")
        s.hl(0, 1, 16, "b")
        s.hl(0, 7, 16, "2")
        s.hl(0, 6, 16, "3")
        for x in range(16):
            if r.random() < 0.3:
                s.set(x, 0, "d")
        # trinca no piso
        s.line(9, 2, 11, 5, "2")
        s.set(12, 6, "2")
    else:  # tábuas de pallet
        s = Spr(16, 8, "R")
        s.hl(0, 0, 16, "U")
        s.hl(0, 3, 16, "r")  # fresta
        s.hl(0, 7, 16, "r")
        for x in range(16):
            if r.random() < 0.4:
                s.set(x, 1, "u")
            if r.random() < 0.3:
                s.set(x, 5, "r")
        s.hl(0, 4, 16, "u")
        s.hl(0, 2, 16, "R"); s.hl(0, 5, 16, "R"); s.hl(0, 6, 16, "R")
        for x in range(16):
            if r.random() < 0.3:
                s.set(x, 6, "r")
        # emendas de tábua e pregos
        for (x, y0, y1) in ((4, 0, 3), (11, 4, 7)):
            s.vl(x, y0, y1 - y0, "r")
        for (x, y) in ((1, 1), (14, 1), (8, 5), (14, 5)):
            s.set(x, y, "c")
        s.set(6, 2, "r"); s.set(7, 2, "r"); s.set(13, 6, "r")
    return s


def ceiling(i):
    """16x8: laje, cano horizontal contínuo (mesma altura nas duas variantes), cabo na 1."""
    r = random.Random(600 + i)
    s = Spr(16, 8)
    s.hl(0, 0, 16, "2")
    s.hl(0, 1, 16, "3")
    s.hl(0, 2, 16, "a")
    for x in range(16):
        s.set(x, 1, "3" if r.random() < 0.7 else "a")
        if r.random() < 0.25:
            s.set(x, 2, "3")
    # cano
    s.hl(0, 3, 16, "c")
    s.hl(0, 4, 16, "b")
    s.hl(0, 5, 16, "3")
    s.hl(0, 6, 16, "2")  # sombra do cano na laje
    s.hl(0, 7, 16, "1")
    # abraçadeira
    xc = 3 if i == 0 else 12
    s.vl(xc, 2, 5, "3"); s.vl(xc + 1, 2, 5, "b")
    s.set(xc, 3, "d")
    # emenda do cano (flange) em x=8 na 0
    if i == 0:
        s.vl(9, 3, 3, "a"); s.set(9, 3, "c")
        s.set(8, 6, "3")
    else:
        # cabo preto pendurado em arco por baixo + fita
        for x in range(16):
            y = 6 + (1 if 3 <= x <= 12 else 0)
            s.set(x, y, "k")
        s.set(2, 7, "1"); s.set(14, 7, "1")
        s.set(5, 7, "k"); s.set(10, 7, "k")
        s.set(7, 7, "k"); s.set(8, 7, "k")
        # mancha de ferrugem
        s.set(6, 2, "r"); s.set(6, 1, "R")
    return s


def divider():
    """8x56: viga sobre o vão (y 0..16), vão transparente (16..48), soleira (48..56). Continua cano do teto."""
    s = Spr(8, 56)
    # teto (y0..8): igual ceiling_0
    for y in range(8):
        for x in range(8):
            s.set(x, y, ceiling(0).get(x + 4, y))
    # viga de concreto/ferro sobre o vão (y8..16)
    s.rect(0, 8, 8, 8, "a")
    s.hl(0, 8, 8, "2")
    s.hl(0, 9, 8, "c")
    s.hl(0, 10, 8, "b")
    s.hl(0, 13, 8, "3")
    s.hl(0, 14, 8, "2")
    s.hl(0, 15, 8, "k")
    for (x, y) in ((1, 11), (6, 11)):
        s.set(x, y, "c"); s.set(x, y + 1, "2")  # rebites
    s.set(3, 12, "R"); s.set(4, 12, "r"); s.set(4, 11, "R")
    # soleira (y48..56) igual ao piso 0
    for y in range(8):
        for x in range(8):
            s.set(x, 48 + y, floor_tile(0).get(x, y))
    return s


# ======================================================================
# Escada, escotilha, caixa, sucata
# ======================================================================
def ladder():
    """16x16 com poço escuro atrás (precisa ler sobre terra e dentro da sala). Trilhos de cano, degraus de vergalhão."""
    s = Spr(16, 16, "1")
    r = random.Random(700)
    for _ in range(10):
        s.set(r.randrange(16), r.randrange(16), "2")
    s.vl(0, 0, 16, "k"); s.vl(15, 0, 16, "k")
    s.vl(1, 0, 16, "2"); s.vl(14, 0, 16, "2")
    # trilhos
    for y in range(16):
        s.set(3, y, "c"); s.set(4, y, "b"); s.set(5, y, "3")
        s.set(10, y, "c"); s.set(11, y, "b"); s.set(12, y, "3")
    # degraus
    for y in (2, 6, 10, 14):
        s.hl(5, y, 5, "R")
        s.hl(5, y + 1, 5, "r") if y + 1 < 16 else None
        s.set(5, y, "u")
    # solda nos trilhos
    for y in (2, 6, 10, 14):
        s.set(3, y, "d"); s.set(10, y, "d")
    return s


def hatch():
    """32x16 x2. Fechada: tampa de chapa deitada sobre a grama. Aberta: tampa erguida e buraco escuro."""
    closed = Spr(32, 16)
    closed.stamp([
        "..kkkkkkkkkkkkkkkkkkkkkkkkkkkk..",
        ".kddcccccccccccccccccccccccbbbk.",
        "kdcccbbbbbbbbbbbbbbbbbbbbbbbbbak",
        "kcbbbbbbbbbbbbbbbbbbbbbbbbbbbbak",
        "kbbbbbbbbbbbbbbbbbbbbbbbbbbbbaak",
        "kbbaaaaaaaaaaaaaaaaaaaaaaaaaaaak",
        "k3333333333333333333333333333332k",
    ][:0], 0, 8)
    # desenho manual: tampa (y 6..13), batente (y 13..15)
    c = closed
    c.rect(2, 6, 28, 5, "b")           # face de cima
    c.hl(2, 6, 28, "d")                # realce amber/branco do topo
    c.hl(2, 7, 28, "c")
    c.rect(2, 11, 28, 3, "a")          # espessura da chapa
    c.hl(2, 11, 28, "3")
    c.hl(2, 13, 28, "2")
    c.rect(0, 14, 32, 2, "3")          # batente de concreto
    c.hl(0, 14, 32, "a")
    c.hl(0, 15, 32, "1")
    # contorno
    c.hl(2, 5, 28, "k")
    c.vl(1, 6, 8, "k"); c.vl(30, 6, 8, "k")
    c.set(0, 14, "k"); c.set(31, 14, "k")
    c.hl(0, 13, 1, "k"); c.hl(31, 13, 1, "k")
    # alça e dobradiça
    c.stamp(["kkkk", "k..k", "kbbk"][:0])
    c.rect(13, 7, 6, 1, "k"); c.vl(13, 8, 2, "k"); c.vl(18, 8, 2, "k"); c.hl(14, 8, 4, "c")
    c.rect(4, 7, 3, 3, "3"); c.set(4, 7, "c"); c.set(5, 7, "c")      # dobradiça
    c.rect(25, 7, 3, 3, "3"); c.set(25, 7, "c"); c.set(26, 7, "c")
    # ferrugem e remendo
    for (x, y) in ((9, 9), (10, 9), (10, 10), (21, 8), (22, 9), (23, 9)):
        c.set(x, y, "R")
    c.set(10, 10, "r"); c.set(22, 9, "r")
    c.set(8, 8, "u")

    o = Spr(32, 16)
    # colar de concreto
    o.rect(0, 14, 32, 2, "3"); o.hl(0, 14, 32, "a"); o.hl(0, 15, 32, "1")
    o.set(0, 14, "k"); o.set(31, 14, "k")
    # buraco escuro e borda
    o.rect(3, 9, 26, 5, "k")
    o.hl(2, 8, 28, "k")
    o.hl(3, 9, 26, "3")
    for x in (8, 15):
        o.vl(x, 10, 4, "c"); o.vl(x + 1, 10, 4, "3")
    o.hl(8, 12, 8, "R")
    # tampa erguida, inclinada para trás (dobradiça à esquerda)
    for y in range(0, 9):
        x0 = 3 + int((8 - y) * 0.35)
        o.hl(x0, y, 8, "b")
        o.set(x0, y, "d"); o.set(x0 + 1, y, "c")
        o.set(x0 + 7, y, "3"); o.set(x0 + 6, y, "a")
        o.set(x0 - 1, y, "k"); o.set(x0 + 8, y, "k")
    o.hl(3, 0, 8, "k")
    o.hl(3, 8, 9, "k")
    o.set(6, 4, "k"); o.set(7, 4, "3"); o.set(6, 5, "R"); o.set(5, 6, "r"); o.set(7, 3, "R")
    # escora (haste) da tampa ao colar
    o.line(13, 8, 11, 2, "c")
    return strip_pair(closed, o)


def strip_pair(a, b):
    return [a, b]


HATCH_BOX_ITEMS = {
    "tomate": [("t", "t"), ("U", "t")],
}


def produce(s, x, y, kind):
    """Pequenos produtos 3x3 (tomate, batata, vagem) para a caixa."""
    if kind == "t":
        s.rect(x, y, 3, 3, "t"); s.set(x, y, "k") if False else None
        s.set(x, y, "t"); s.set(x + 2, y, "t")
        s.set(x + 1, y, "U"); s.set(x, y + 2, "r"); s.set(x + 2, y + 2, "r")
        s.set(x + 1, y - 1, "h")
    elif kind == "b":
        s.rect(x, y, 3, 2, "n"); s.set(x, y, "S"); s.set(x + 2, y + 1, "s"); s.set(x + 1, y + 2, "s")
    else:
        s.hl(x, y, 3, "i"); s.hl(x, y + 1, 3, "h"); s.set(x, y, "j")


def hatch_box():
    frames = []
    for state in range(4):
        s = Spr(16, 16)
        # conteúdo (atrás da frente da caixa)
        if state >= 1:
            produce(s, 4, 3, "t") if state == 1 else None
            if state == 1:
                produce(s, 8, 4, "b")
        if state >= 2:
            s.rect(3, 5, 10, 2, "n")
            produce(s, 3, 2, "t"); produce(s, 6, 3, "b"); produce(s, 9, 2, "i"); produce(s, 11, 3, "t")
            s.rect(4, 5, 8, 2, "h")
        if state == 3:
            s.rect(2, 3, 12, 4, "h")
            produce(s, 2, 1, "t"); produce(s, 5, 0, "b"); produce(s, 8, 0, "t"); produce(s, 11, 1, "i")
            produce(s, 3, 3, "i"); produce(s, 7, 3, "t"); produce(s, 10, 3, "b")
            # caiu um pouco para fora
            produce(s, 13, 13, "t"); produce(s, 0, 13, "b")
            s.set(15, 15, "n")
        # caixa
        s.rect(2, 7, 12, 9, "R")
        s.hl(2, 7, 12, "U")
        s.hl(2, 8, 12, "u")
        s.hl(2, 11, 12, "r")
        s.hl(2, 15, 12, "r")
        for x in (3, 12):
            s.vl(x, 7, 9, "b"); s.vl(x + 1, 8, 8, "3") if x == 3 else s.vl(x - 1, 8, 8, "3")
        s.vl(2, 7, 9, "1"); s.vl(13, 7, 9, "1")
        s.hl(2, 15, 12, "k")
        for (x, y) in ((3, 9), (12, 9), (3, 13), (12, 13)):
            s.set(x, y, "c")
        # rótulo de trocas
        s.rect(6, 10, 4, 2, "p"); s.hl(6, 10, 4, "d"); s.set(7, 11, "3"); s.set(8, 11, "3")
        # interior escuro visível quando vazia/pouca
        if state == 0:
            s.hl(3, 6, 10, "r"); s.hl(2, 6, 1, "1"); s.hl(13, 6, 1, "1")
            s.hl(3, 5, 10, "k") if False else None
        else:
            s.set(2, 6, None); s.set(13, 6, None)
        frames.append(s)
    return frames


def can_item(s, x, y, body="b", band="R"):
    s.rect(x, y, 3, 4, body)
    s.vl(x, y, 4, "c"); s.hl(x, y, 3, "d")
    s.hl(x, y + 3, 3, "3")
    s.hl(x, y + 2, 3, band)
    s.vl(x + 2, y + 1, 3, "3") if False else None


def scrap_pile():
    frames = []
    # 1: pequena
    a = Spr(16, 16)
    # sombra de chão
    a.hl(3, 15, 10, "2")
    can_item(a, 5, 11)                        # lata
    a.rect(8, 13, 5, 2, "R"); a.hl(8, 13, 5, "U"); a.hl(8, 14, 5, "r")   # chapa enferrujada
    a.line(3, 14, 6, 12, "c"); a.line(3, 15, 5, 14, "3")                 # cano
    a.outline("k")
    frames.append(a)
    # 2: média
    b = Spr(16, 16)
    b.hl(1, 15, 14, "2")
    b.rect(2, 12, 6, 3, "R"); b.hl(2, 12, 6, "U"); b.hl(2, 14, 6, "r")  # tábua
    b.ellipse(11, 12, 3, 3, "3"); b.ellipse(11, 12, 1, 1, "k")          # pneu pequeno
    b.set(9, 10, "a"); b.set(10, 9, "a")
    can_item(b, 5, 8)
    can_item(b, 2, 9, "c", "t")
    b.rect(6, 13, 5, 2, "b"); b.hl(6, 13, 5, "d"); b.hl(6, 14, 5, "3")  # chapa
    b.line(12, 9, 14, 6, "c")                                           # cano torto
    b.line(13, 9, 15, 6, "3")
    b.outline("k")
    frames.append(b)
    # 3: grande
    c = Spr(16, 16)
    c.hl(0, 15, 16, "2")
    c.ellipse(4, 11, 4, 4, "3"); c.ellipse(4, 11, 2, 2, "k"); c.set(2, 8, "a")  # pneu
    c.rect(8, 11, 7, 4, "R"); c.hl(8, 11, 7, "U"); c.hl(8, 14, 7, "r")         # barril/chapa
    c.vl(10, 11, 4, "r"); c.vl(13, 11, 4, "r")
    c.rect(4, 5, 7, 3, "R"); c.hl(4, 5, 7, "u"); c.hl(4, 7, 7, "r")             # tábua em cima
    can_item(c, 9, 7)
    can_item(c, 2, 12, "c", "t")
    c.rect(6, 8, 5, 3, "b"); c.hl(6, 8, 5, "d"); c.hl(6, 10, 5, "3")           # chapa
    c.line(11, 7, 14, 1, "c"); c.line(12, 7, 15, 1, "3")                        # cano em pé
    c.line(2, 6, 5, 2, "c"); c.line(5, 2, 7, 2, "c")                            # cano dobrado
    c.ellipse(7, 12, 2, 2, "E"); c.ellipse(7, 12, 1, 1, "k")                    # engrenagem
    c.set(7, 10, "F"); c.set(5, 12, "E"); c.set(9, 12, "e")
    c.outline("k")
    frames.append(c)
    return frames


# ======================================================================
# Antenas
# ======================================================================
def wood(s, x, y0, y1, w=2):
    for y in range(y0, y1 + 1):
        s.set(x, y, "u")
        if w > 1:
            s.set(x + 1, y, "r" if y % 5 == 0 else "R")


def pole_metal(s, x, y0, y1):
    for y in range(y0, y1 + 1):
        s.set(x, y, "d" if y % 7 else "c")
        s.set(x + 1, y, "2" if y % 4 else "3")


def antenna(n):
    s = Spr(24, 24)
    cx = 12
    if n == 1:
        # mastro de varal (esq.) + cabo de vassoura (dir.) amarrados com fita
        wood(s, 6, 6, 23)
        s.line(5, 5, 6, 8, "R"); s.line(9, 5, 8, 8, "R")      # forquilha
        s.set(5, 4, "u"); s.set(9, 4, "u")
        wood(s, 14, 4, 23)
        # cerdas da vassoura no topo
        s.rect(13, 0, 4, 4, "e"); s.hl(13, 0, 4, "E"); s.set(13, 3, "n"); s.set(16, 3, "n"); s.set(14, 3, "e")
        s.hl(13, 4, 4, "k")
        # fios
        s.line(5, 4, 9, 4, "3"); s.line(9, 4, 13, 2, "3")
        s.line(15, 5, 18, 12, "3"); s.line(18, 12, 19, 19, "3")      # fio que desce
        # trapo no varal
        s.rect(7, 5, 2, 4, "O"); s.set(7, 8, "o"); s.set(8, 8, "o"); s.set(8, 5, "d")
        # fita
        s.hl(14, 12, 2, "k"); s.hl(14, 13, 2, "E")
        s.hl(6, 12, 2, "k") if False else None
        s.line(8, 13, 13, 12, "3")
        # base: balde de concreto + pedras
        s.rect(5, 21, 12, 3, "a"); s.hl(5, 21, 12, "b"); s.hl(5, 23, 12, "3")
        s.rect(4, 22, 2, 2, "b"); s.rect(17, 22, 2, 2, "b")
        s.hl(5, 20, 3, "b"); s.hl(13, 20, 4, "b")
    elif n == 2:
        # mastro de cano + dipolo de varal com isoladores de garrafa
        pole_metal(s, 11, 3, 23)
        s.rect(1, 3, 22, 1, "R"); s.hl(1, 2, 22, "u")             # cruzeta de madeira
        s.hl(1, 4, 22, "r") if False else None
        for x in (2, 21):
            s.rect(x, 4, 1, 2, "O"); s.set(x, 6, "d")             # isoladores de garrafa
        s.line(2, 6, 0, 10, "3"); s.line(21, 6, 23, 10, "3")      # pontas do dipolo caindo
        s.hl(10, 2, 4, "k") if False else None
        # estais
        s.line(11, 8, 4, 22, "3"); s.line(12, 8, 20, 22, "3")
        s.hl(11, 9, 2, "E")
        s.set(3, 22, "a"); s.set(21, 22, "a")
        # cabo coaxial descendo com fita
        s.vl(13, 6, 10, "k")
        s.set(13, 9, "E")
        # base
        s.rect(8, 21, 8, 3, "a"); s.hl(8, 21, 8, "b"); s.hl(8, 23, 8, "3")
        s.hl(7, 22, 1, "b"); s.hl(16, 22, 1, "b")
        s.rect(10, 1, 4, 1, "k") if False else None
        s.set(12, 1, "c"); s.set(12, 0, "c")                      # pontinha
    elif n == 3:
        # antena de TV (espinha de peixe) + caixa de rotor
        pole_metal(s, 11, 4, 23)
        for i, (y, half) in enumerate(((2, 3), (5, 5), (8, 7), (11, 9), (14, 6))):
            s.hl(12 - half, y, half * 2, "c")
            s.hl(12 - half, y + 1, half * 2, "b") if half > 4 and False else None
            s.set(12 - half, y, "d"); s.set(11 + half, y, "d")
            s.set(12 - half, y + 1, "3"); s.set(11 + half, y + 1, "3")
        s.rect(10, 17, 4, 3, "a"); s.hl(10, 17, 4, "b"); s.hl(10, 19, 4, "3")  # rotor
        s.set(12, 18, "E")
        s.vl(14, 17, 6, "k")                                               # cabo
        # estais
        s.line(11, 15, 3, 23, "3"); s.line(12, 15, 21, 23, "3")
        # base
        s.rect(7, 21, 10, 3, "a"); s.hl(7, 21, 10, "b"); s.hl(7, 23, 10, "3")
        s.set(12, 0, "c"); s.set(12, 1, "b")
    elif n == 4:
        # torre treliçada baixa + yagi de perfil (pente) + caixa com luz
        for y in range(8, 24):
            s.set(9, y, "d"); s.set(10, y, "c")
            s.set(14, y, "2"); s.set(15, y, "1")
        for y in range(8, 23, 4):
            s.line(11, y, 13, y + 4, "3"); s.line(13, y, 11, y + 4, "3")
            s.hl(11, y, 3, "c")
        # yagi: lança horizontal com elementos verticais
        s.hl(3, 6, 18, "c"); s.hl(3, 7, 18, "3")
        for x, h in ((4, 3), (8, 5), (12, 7), (16, 5), (20, 3)):
            s.vl(x, 6 - h // 2 - 1, h + 1, "d" if x != 12 else "d")
            s.set(x, 6 - h // 2 - 1, "d")
        s.set(12, 0, "d")
        s.rect(9, 8, 7, 1, "k") if False else None
        # estais
        s.line(10, 12, 2, 23, "3"); s.line(14, 12, 22, 23, "3")
        # caixa de equipamento + luz
        s.rect(2, 19, 6, 4, "a"); s.hl(2, 19, 6, "c"); s.hl(2, 22, 6, "3")
        s.set(3, 20, "E"); s.set(5, 20, "3")
        s.line(7, 21, 9, 21, "k")
        # base
        s.rect(7, 22, 10, 2, "a"); s.hl(7, 22, 10, "b"); s.hl(7, 23, 10, "3")
    else:
        # torre alta + refletor de tampa de panela + yagi + fios + luz
        for y in range(8, 24):
            s.set(9, y, "d"); s.set(10, y, "c")
            s.set(14, y, "2"); s.set(15, y, "1")
        for y in range(8, 23, 4):
            s.line(11, y, 13, y + 4, "3"); s.line(13, y, 11, y + 4, "3")
            s.hl(11, y, 3, "c")
        # prato (tampa de panela) apontado para cima/direita
        s.ellipse(7, 6, 7, 5, "k")
        s.ellipse(7, 6, 6, 4, "d")
        s.ellipse(8, 7, 5, 3, "c")
        s.ellipse(9, 7, 3, 2, "b")
        s.ellipse(10, 8, 2, 1, "a")
        s.hl(6, 5, 3, "p")
        s.set(10, 7, "k")
        # braço do foco (cabo de panela) até a luz
        s.line(10, 7, 17, 2, "R"); s.line(10, 6, 17, 1, "u")
        s.rect(17, 0, 3, 3, "E"); s.set(17, 0, "G"); s.set(19, 2, "e")
        # suporte sob o prato
        s.line(5, 10, 9, 9, "3"); s.vl(11, 9, 0, "3")
        s.rect(9, 9, 6, 1, "3")
        # yagi pequena
        s.hl(11, 11, 12, "c")
        for x, h in ((13, 4), (16, 6), (19, 4), (22, 3)):
            s.vl(x, 11 - h // 2, h + 1, "d")
        # fios caindo para os lados
        s.line(9, 8, 2, 14, "3"); s.line(2, 14, 1, 23, "3")
        s.line(15, 12, 23, 18, "3")
        s.set(1, 23, "k")
        # faixa de pano (bandeira)
        s.rect(20, 12, 3, 2, "O"); s.set(22, 13, "o")
        s.vl(23, 11, 3, "c") if False else None
        # caixas + base
        s.rect(3, 19, 6, 4, "a"); s.hl(3, 19, 6, "c"); s.hl(3, 22, 6, "3")
        s.set(4, 20, "E"); s.set(6, 20, "E"); s.set(5, 20, "3")
        s.rect(16, 20, 5, 3, "R"); s.hl(16, 20, 5, "U"); s.hl(16, 22, 5, "r")
        s.rect(7, 22, 10, 2, "a"); s.hl(7, 22, 10, "b"); s.hl(7, 23, 10, "3")
    return s


# ======================================================================
# Rádio, cama, lâmpada, balão
# ======================================================================
RADIO = [
    "...........c....",
    "............d...",
    "............b...",
    "...........b....",
    "..........b.....",
    "..kkkkkkkkkkkk..",
    "..kUUUUUUUUUUk..",
    "..k1a1aRdddRuk..",
    "..ka1a1R1ddRuk..",
    "..k1a1aRuc.uuk..",
    "..krrrrrrrrrrk..",
    ".kuuuuuuuuuuuuk.",
    ".kRRRRRRRRRRRRk.",
    "..kRk........kRk."[:16],
    "..kRk........kRk.",
    "..kkk........kkk.",
]


def radio_frame(state):
    rows = [list(r.ljust(16, ".")[:16]) for r in RADIO]
    s = Spr(16, 16)
    s.stamp(["".join(r) for r in rows])
    # janela do mostrador (x9..12, y7..9)
    # off: vidro apagado
    if state == 0:
        s.set(9, 7, "1"); s.set(10, 7, "1"); s.set(11, 7, "1"); s.set(10, 8, "1")
        s.set(9, 8, "1"); s.set(11, 8, "1")
        s.set(9, 9, "u"); s.set(10, 9, "c"); s.set(11, 9, "u")
    else:
        # mostrador aceso (âmbar) e agulha em posição diferente a cada estado
        for x in range(9, 12):
            s.set(x, 7, "E"); s.set(x, 8, "e")
        s.set(9 + (state - 1) * 2, 7, "G"); s.set(9 + (state - 1) * 2, 8, "G")
        # botão
        s.set(9, 9, "c"); s.set(10, 9, "u"); s.set(11, 9, "c")
        # grelha vibra: A = barras claras em cima, B = embaixo
        if state == 1:
            s.set(3, 7, "b"); s.set(5, 7, "b"); s.set(4, 8, "b"); s.set(6, 8, "b")
        else:
            s.set(4, 7, "b"); s.set(6, 7, "b"); s.set(3, 8, "b"); s.set(5, 8, "b")
        # chiado: fagulhas pequenas saindo do alto-falante
        if state == 1:
            s.set(3, 4, "d"); s.set(5, 3, "c"); s.set(2, 2, "b")
        else:
            s.set(4, 4, "c"); s.set(6, 3, "d"); s.set(3, 2, "b")
    # topo do rádio com realce de lâmpada
    s.set(3, 6, "u")
    return s


def radio_table():
    return [radio_frame(0), radio_frame(1), radio_frame(2)]


def radio_glow():
    frames = []
    for st in range(2):
        s = Spr(16, 16)
        for x in range(9, 12):
            s.set(x, 7, "x"); s.set(x, 8, "x")
        if st == 1:
            # halo verde em volta do mostrador e fagulhas
            for (x, y) in ((8, 6), (12, 6), (8, 9), (12, 9), (10, 5), (9, 5), (11, 5)):
                s.set(x, y, "i")
            for (x, y) in ((10, 10), (8, 8), (12, 8)):
                s.set(x, y, "h")
            for x in range(9, 12):
                s.set(x, 7, "x")
        else:
            s.set(10, 6, "h")
        frames.append(s)
    return frames


def bed():
    s = Spr(32, 16)
    # lona (esticada) + armação
    s.rect(1, 11, 30, 2, "a")
    s.hl(1, 11, 30, "c")
    s.hl(1, 12, 30, "3")
    s.hl(1, 13, 30, "k")
    s.vl(0, 11, 3, "k"); s.vl(31, 11, 3, "k")
    # colchão fino
    s.rect(2, 9, 28, 2, "d")
    s.hl(2, 9, 28, "p")
    s.hl(2, 10, 28, "c")
    # cobertor azul-acinzentado com remendo
    s.rect(11, 5, 19, 5, "o")
    s.hl(11, 5, 19, "O")
    s.hl(12, 6, 17, "O") if False else None
    s.hl(11, 9, 19, "k")
    s.vl(29, 6, 4, "k"); s.set(30, 9, "k")
    for x in range(12, 29, 3):
        s.set(x, 7, "O")
    s.rect(20, 6, 4, 3, "R"); s.hl(20, 6, 4, "u"); s.hl(20, 8, 4, "r")        # remendo laranja
    s.set(11, 6, "O"); s.set(12, 7, "o")
    # dobra do cobertor
    s.hl(11, 8, 19, "o") if False else None
    # travesseiro
    s.rect(3, 6, 8, 3, "p")
    s.hl(4, 5, 6, "p"); s.hl(3, 6, 8, "d")
    s.hl(3, 8, 8, "c"); s.hl(4, 9, 6, "k") if False else None
    s.set(2, 7, "k"); s.set(11, 6, "k")
    s.hl(4, 4, 6, "k"); s.set(3, 5, "k"); s.set(10, 5, "k")
    s.set(3, 8, "c"); s.set(10, 8, "c")
    # contorno do cobertor topo
    s.hl(11, 4, 19, "k") if False else None
    s.hl(12, 4, 17, "k")
    s.set(11, 5, "k"); s.set(30, 5, "k")
    # sobe o corpo 2 px e desenha as pernas em X (campanha) por baixo
    body = s.copy()
    s = Spr(32, 16)
    for y in range(16):
        for x in range(32):
            if y + 2 < 16:
                s.p[y][x] = body.p[y + 2][x]
    for x0 in (3, 23):
        s.line(x0, 12, x0 + 4, 15, "c"); s.line(x0 + 4, 12, x0, 15, "3")
        s.set(x0 - 1, 15, "k"); s.set(x0, 15, "k"); s.set(x0 + 4, 15, "k"); s.set(x0 + 5, 15, "k")
        s.hl(x0, 11, 5, "1")
    return s


LAMP = {
    "off": [
        "........1.......",
        "........1.......",
        ".......kak......",
        "......kcbbk.....",
        ".....kcbbb3k....",
        "....kkkkkkkkk...",
        ".....k.ccc.k....",
        "......k.d.k.....",
    ],
}


def lamp():
    frames = []
    base = [
        "........1.......",
        "........1.......",
        "......kkckk.....",
        "....kkcdbbbkk...",
        "...kcccbbbb33k..",
        "...kkkkkkkkkkk..",
        "................",
        "................",
    ]
    base = [r[:16].ljust(16, ".") for r in base]
    # apagada: bulbo escuro de vidro
    s = Spr(16, 8)
    s.stamp(base)
    s.set(7, 6, "b"); s.set(8, 6, "c"); s.set(9, 6, "3")
    s.set(8, 7, "3"); s.set(7, 7, "k"); s.set(9, 7, "k")
    s.set(8, 6, "d")
    frames.append(s)
    # acesa
    s = Spr(16, 8)
    s.stamp(base)
    s.hl(6, 6, 5, "F"); s.hl(5, 6, 1, "E"); s.hl(11, 6, 1, "E")
    s.set(8, 6, "G"); s.set(7, 6, "G"); s.set(9, 6, "G")
    s.hl(6, 7, 5, "E"); s.set(8, 7, "G"); s.set(7, 7, "F"); s.set(9, 7, "F")
    for (x, y) in ((4, 7), (12, 7), (3, 6), (13, 6), (2, 5), (14, 5)):
        s.set(x, y, "e") if y >= 5 and (x, y) not in ((2, 5), (14, 5)) else None
    s.set(5, 4, "R") if False else None
    s.set(5, 4, "c")
    frames.append(s)
    # piscando: mais fraca, com faísca
    s = Spr(16, 8)
    s.stamp(base)
    s.hl(6, 6, 5, "e"); s.set(8, 6, "E"); s.set(7, 6, "E"); s.set(9, 6, "e")
    s.hl(7, 7, 3, "e"); s.set(8, 7, "k")
    s.set(10, 7, "G"); s.set(11, 7, "F"); s.set(5, 7, "F")
    s.set(4, 6, "G")
    frames.append(s)
    return frames


def bubble_thought():
    s = Spr(24, 20)
    # nuvem: retângulo arredondado de 24x15
    s.stamp([
        "....kkkkkkkkkkkkkkkk....",
        "..kkpppppppppppppppppkk.",
        ".kppppppppppppppppppppdk",
        ".kpppppppppppppppppppdck",
        "kpppppppppppppppppppppdk",
        "kpppppppppppppppppppppdk",
        "kpppppppppppppppppppppdk",
        "kpppppppppppppppppppppdk",
        "kpppppppppppppppppppppck",
        "kpppppppppppppppppppppck",
        ".kpppppppppppppppppppdk.",
        ".kdppppppppppppppppdcck.",
        "..kkddppppppppppddcckk..",
        "....kkkkkkkkkkkkkkkk....",
    ], 0, 0)
    # arremates dos cantos para a nuvem ficar levemente ondulada
    for x in (0, 23):
        s.set(x, 3, None)
    # rabinho: duas bolhas descendo para a esquerda
    s.stamp([
        ".kkk.",
        "kpppk",
        "kpppk",
        ".kck.",
    ][:0], 0, 0)
    s.ellipse(8, 16, 2, 1, "p"); s.hl(6, 15, 5, "k") if False else None
    s.stamp([
        ".kkkk.",
        "kppppk",
        "kppppk",
        ".kkkk.",
    ], 5, 14)
    s.stamp([
        "kkk",
        "kpk",
        "kkk",
    ], 3, 18) if False else None
    s.stamp([
        ".kk.",
        "kppk",
        ".kk.",
    ], 2, 17)
    return s


# ======================================================================
# Partículas (4 quadros cada)
# ======================================================================
def fx_zzz():
    fr = []
    z3 = ["ddd", "..d", ".d.", "ddd"]
    z4 = ["dddd", "...d", "..d.", ".d..", "dddd"]
    spec = [
        [(z3, 0, 4, "d")],
        [(z3, 0, 4, "d"), (z4, 4, 1, "d")],
        [(z3, 0, 4, "c"), (z4, 4, 0, "d")],
        [(z4, 4, 0, "c")],
    ]
    for lst in spec:
        s = Spr(8, 8)
        for z, ox, oy, col in lst:
            s.stamp([r.replace("d", col) for r in z], ox, oy)
        fr.append(s)
    return fr


def fx_drip():
    fr = []
    a = Spr(4, 8); a.set(1, 0, "O"); a.set(2, 0, "O"); a.set(1, 1, "O"); a.set(2, 1, "d")
    fr.append(a)
    b = Spr(4, 8); b.set(1, 1, "O"); b.set(2, 1, "d"); b.set(1, 2, "O"); b.set(2, 2, "O"); b.set(1, 3, "O"); b.set(2, 3, "o")
    fr.append(b)
    c = Spr(4, 8); c.set(1, 4, "O"); c.set(2, 4, "d"); c.set(1, 5, "O"); c.set(2, 5, "o")
    c.set(1, 3, "O") if False else None
    fr.append(c)
    d = Spr(4, 8)
    d.hl(0, 7, 4, "O"); d.set(0, 6, "d"); d.set(3, 6, "O"); d.set(1, 5, "d") if False else None
    d.set(0, 5, "O") if False else None
    fr.append(d)
    return fr


def fx_spark():
    fr = []
    a = Spr(8, 8); a.set(3, 3, "G"); a.set(4, 4, "G"); a.set(3, 4, "F"); a.set(4, 3, "F")
    fr.append(a)
    b = Spr(8, 8)
    for (x, y) in ((3, 3), (4, 3), (3, 4), (4, 4)):
        b.set(x, y, "G")
    for (x, y) in ((3, 1), (4, 1), (3, 6), (4, 6), (1, 3), (1, 4), (6, 3), (6, 4)):
        b.set(x, y, "F")
    for (x, y) in ((3, 2), (4, 2), (3, 5), (4, 5), (2, 3), (2, 4), (5, 3), (5, 4)):
        b.set(x, y, "E")
    fr.append(b)
    c = Spr(8, 8)
    for (x, y) in ((1, 1), (6, 1), (1, 6), (6, 6)):
        c.set(x, y, "F")
    for (x, y) in ((2, 2), (5, 2), (2, 5), (5, 5)):
        c.set(x, y, "E")
    for (x, y) in ((3, 0), (0, 4), (7, 3), (4, 7)):
        c.set(x, y, "G")
    fr.append(c)
    d = Spr(8, 8)
    for (x, y) in ((0, 1), (7, 0), (0, 7), (7, 7), (3, 7), (4, 0)):
        d.set(x, y, "e")
    for (x, y) in ((1, 2), (6, 5)):
        d.set(x, y, "E")
    fr.append(d)
    return fr


def fx_dust():
    fr = []
    r = random.Random(77)
    # pontinhos de poeira que sobem devagar e se espalham
    pts = [(2, 6), (5, 7), (4, 5)]
    for i in range(4):
        s = Spr(8, 8)
        for k, (x, y) in enumerate(pts):
            yy = y - i * 1 - (k % 2)
            xx = x + (1 if (i + k) % 2 else -1) * (1 if i > 1 else 0)
            col = "c" if i < 2 else ("b" if i == 2 else "a")
            if 0 <= yy < 8:
                s.set(xx, yy, col)
                if i == 0 and k == 0:
                    s.set(xx + 1, yy, "b")
        if i >= 1:
            s.set(3 + i % 2, 6 - i, "b")
        fr.append(s)
    return fr


def fx_steam():
    fr = []
    for i in range(4):
        s = Spr(8, 8)
        for k in range(2):
            y = (6 - (i * 2 + k * 4)) % 8
            x = 2 + (1 if (y // 2 + i) % 2 else 0) + k
            tone = "d" if y > 4 else ("c" if y > 2 else "b")
            s.rect(x, y, 2, 2, tone)
            s.set(x + 2, y, tone) if y > 3 else None
            s.set(x - 1, y + 1, tone) if y > 4 else None
        fr.append(s)
    return fr


def fx_scrap_pop():
    fr = []
    # porca/engrenagem que pula, brilha e some
    def nut(s, x, y, tone):
        s.set(x, y, tone); s.set(x + 1, y, tone)
        s.set(x - 1, y + 1, tone); s.set(x + 2, y + 1, tone)
        s.set(x, y + 1, "k"); s.set(x + 1, y + 1, "k")
        s.set(x, y + 2, tone); s.set(x + 1, y + 2, tone)
    a = Spr(8, 8); nut(a, 3, 5, "c")
    fr.append(a)
    b = Spr(8, 8); nut(b, 3, 3, "d"); b.set(3, 3, "G")
    fr.append(b)
    c = Spr(8, 8); nut(c, 3, 1, "d"); c.set(1, 1, "F"); c.set(6, 3, "F"); c.set(5, 0, "G"); c.set(2, 5, "E")
    fr.append(c)
    d = Spr(8, 8)
    for (x, y) in ((1, 0), (6, 1), (0, 3), (7, 4), (3, 2), (4, 6)):
        d.set(x, y, "F" if (x + y) % 2 else "E")
    d.set(3, 3, "c"); d.set(4, 3, "b")
    fr.append(d)
    return fr


# ======================================================================
# Montagem, manifesto e folha de contato
# ======================================================================
def sheet_tile(spr_list, name_fn=None):
    return spr_list


def build_all():
    os.makedirs(OUT, exist_ok=True)
    manifest = {}
    items = []  # (name, [frames Spr], fps, anchor)

    def add(name, frames, fps=0, anchor=None, **extra):
        if isinstance(frames, Spr):
            frames = [frames]
        fw, fh = frames[0].w, frames[0].h
        img = snap_image(strip(frames))
        path = os.path.join(OUT, name + ".png")
        img.save(path)
        entry = {"file": "env/%s.png" % name, "frame_w": fw, "frame_h": fh, "frames": len(frames),
                 "fps": fps, "anchor": anchor if anchor is not None else [fw // 2, fh]}
        entry.update(extra)
        manifest[name] = entry
        items.append((name, frames))

    for i in range(4):
        add("earth_%d" % i, earth(i), anchor=[0, 0])
    for i in range(3):
        add("earth_deco_%d" % i, earth_deco(i), anchor=[0, 0])
    for i in range(3):
        add("grass_%d" % i, grass(i), anchor=[0, 0])
    for i in range(4):
        add("wall_%d" % i, wall(i), anchor=[0, 0])
    for i in range(2):
        add("floor_%d" % i, floor_tile(i), anchor=[0, 0])
    for i in range(2):
        add("ceiling_%d" % i, ceiling(i), anchor=[0, 0])
    add("divider", divider(), anchor=[0, 0])
    add("ladder", ladder(), anchor=[0, 0])
    add("hatch", hatch(), anchor=[0, 16], note="quadro 0 fechada, quadro 1 aberta; base alinhada ao fundo da grama (y 32)")
    add("hatch_box", hatch_box(), anchor=[8, 16], note="vazia, 1/3, 2/3, transbordando")
    add("scrap_pile", scrap_pile(), anchor=[8, 16], note="pequena, media, grande")
    for n in range(1, 6):
        add("antenna_%d" % n, antenna(n), anchor=[12, 24])
    add("radio_table", radio_table(), anchor=[8, 16], note="desligado, chiado A, chiado B")
    add("radio_glow", radio_glow(), fps=2, anchor=[8, 16], note="overlay do sinal sobre radio_table (mesmas coordenadas)")
    add("bed", bed(), anchor=[16, 16])
    add("lamp", lamp(), anchor=[8, 0], note="apagada, acesa, piscando")
    add("fx_zzz", fx_zzz(), fps=3, anchor=[4, 8])
    add("fx_drip", fx_drip(), fps=8, anchor=[2, 0])
    add("fx_spark", fx_spark(), fps=12, anchor=[4, 4])
    add("fx_dust", fx_dust(), fps=6, anchor=[4, 8])
    add("fx_steam", fx_steam(), fps=5, anchor=[4, 8])
    add("fx_scrap_pop", fx_scrap_pop(), fps=10, anchor=[4, 8])
    add("bubble_thought", bubble_thought(), anchor=[2, 20], note="rabinho no canto inferior esquerdo; icone 8x8 cabe em x8..16,y3..11")

    with open(os.path.join(ROOT, "assets", "art", "manifest_env.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    return manifest, items


def contact_sheet(manifest):
    """Folha de contato x6, fora do manifesto: cada PNG ampliado com rótulo, mais amostras de emenda dos tiles."""
    from PIL import ImageFont
    Z = 6
    bg = RGB["conc1"]
    names = list(manifest.keys())
    font = ImageFont.load_default()
    cells = []
    for n in names:
        im = Image.open(os.path.join(OUT, n + ".png")).convert("RGBA")
        cells.append((n, im))
    colw = 0
    pad = 8
    maxw = 1500
    x = pad
    y = pad
    rowh = 0
    pos = []
    for n, im in cells:
        w, h = im.width * Z, im.height * Z
        w = max(w, len(n) * 6 + 4)
        if x + w + pad > maxw:
            x = pad
            y += rowh + pad
            rowh = 0
        pos.append((n, im, x, y))
        x += w + pad
        rowh = max(rowh, im.height * Z + 12)
    H = y + rowh + pad
    # amostras de emenda (tiles 4x3 repetidos, ampliação x3)
    seam_y = H + 4
    seam = []
    S = 3

    def tiled(names_, cols, rows, tw, th, seed):
        r = random.Random(seed)
        out = Image.new("RGBA", (cols * tw, rows * th))
        ims = [Image.open(os.path.join(OUT, n + ".png")).convert("RGBA") for n in names_]
        for j in range(rows):
            for i in range(cols):
                out.paste(ims[r.randrange(len(ims))], (i * tw, j * th))
        return out
    seam.append(("earth x4 aleatorio", tiled(["earth_0", "earth_1", "earth_2", "earth_3"], 12, 6, 16, 16, 1)))
    seam.append(("wall x4 aleatorio", tiled(["wall_0", "wall_1", "wall_2", "wall_3"], 12, 5, 16, 16, 2)))
    seam.append(("floor 0/1", tiled(["floor_0"], 12, 1, 16, 8, 3)))
    seam.append(("floor 1", tiled(["floor_1"], 12, 1, 16, 8, 3)))
    seam.append(("ceiling 0/1", tiled(["ceiling_0", "ceiling_1"], 12, 1, 16, 8, 4)))
    seam.append(("grass 0..2", tiled(["grass_0", "grass_1", "grass_2"], 12, 1, 16, 8, 5)))
    total_h = H
    sh = 0
    for n, im in seam:
        sh += im.height * S + 14
    canvas = Image.new("RGBA", (maxw, total_h + sh + 8), bg + (255,))
    d = ImageDraw.Draw(canvas)
    lab = RGB["paper"]
    for n, im, px, py in pos:
        big = im.resize((im.width * Z, im.height * Z), Image.NEAREST)
        # moldura para ver o limite do quadro
        d.rectangle([px - 1, py + 11, px + big.width, py + 11 + big.height], outline=RGB["dark3"])
        canvas.alpha_composite(big, (px, py + 12))
        d.text((px, py), n, fill=lab, font=font)
    yy = total_h + 4
    for n, im in seam:
        big = im.resize((im.width * S, im.height * S), Image.NEAREST)
        d.text((pad, yy), n, fill=lab, font=font)
        canvas.alpha_composite(big, (pad, yy + 12))
        yy += big.height + 14
    canvas = snap_image(canvas)
    canvas.save(os.path.join(OUT, "_contact_env.png"))


def main():
    manifest, _ = build_all()
    contact_sheet(manifest)
    bad = {}
    for n in list(manifest.keys()) + ["_contact_env"]:
        res = check_image(os.path.join(OUT, n + ".png"))
        if res:
            bad[n] = res
    if bad:
        print("PROBLEMAS DE PALETA:", bad)
        sys.exit(1)
    print("OK -", len(manifest), "PNGs; paleta validada")


if __name__ == "__main__":
    main()
