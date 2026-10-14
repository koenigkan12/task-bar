#!/usr/bin/env python3
"""ARTE-OBJETOS: gera os sprites dos objetos comprados (assets/art/obj + manifest_obj.json).
Reproduzivel: python3 tools/art/make_obj.py   (so usa a paleta fixa de palette.py)

Convencoes: luz de cima/esquerda (realce amber/claro no topo e esquerda, sombra embaixo/direita);
Crops: ancora [6,12] (base-centro); plots do manifesto = onde essa ancora cai na estrutura.
Cor 'signal' NUNCA e usada aqui.
"""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from palette import RGB, snap_image, check_image  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "art", "obj")
MANIFEST = os.path.join(ROOT, "assets", "art", "manifest_obj.json")

# legenda do ASCII (um caractere por cor da paleta)
LEG = {
    "k": "ink", "1": "dark1", "2": "dark2", "3": "dark3",
    "a": "conc1", "b": "conc2", "c": "conc3", "d": "conc4",
    "r": "rust1", "s": "rust2", "t": "rust3", "u": "rust4",
    "e": "amber1", "f": "amber2", "g": "amber3", "h": "amber4",
    "i": "leaf1", "j": "leaf2", "l": "leaf3", "m": "leaf4",
    "n": "skin1", "o": "skin2", "p": "cloth1", "q": "cloth2",
    "w": "paper", "x": "tomato", "y": "bean",
}


class Cv:
    def __init__(s, w, h):
        s.w, s.h = w, h
        s.im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        s.px = s.im.load()

    def p(s, x, y, c):
        x, y = int(x), int(y)
        if c and 0 <= x < s.w and 0 <= y < s.h:
            s.px[x, y] = RGB[LEG.get(c, c)] + (255,)

    def clr(s, x, y):
        if 0 <= x < s.w and 0 <= y < s.h:
            s.px[x, y] = (0, 0, 0, 0)

    def get(s, x, y):
        if 0 <= x < s.w and 0 <= y < s.h:
            return s.px[x, y]
        return (0, 0, 0, 0)

    def rect(s, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                s.p(x, y, c)

    def hl(s, x0, x1, y, c):
        for x in range(x0, x1 + 1):
            s.p(x, y, c)

    def vl(s, x, y0, y1, c):
        for y in range(y0, y1 + 1):
            s.p(x, y, c)

    def line(s, x0, y0, x1, y1, c):
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            s.p(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def art(s, x, y, rows):
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                if ch != ".":
                    s.p(x + i, y + j, ch)

    def box(s, x0, y0, x1, y1, base, hi, lo):
        """caixa com realce em cima/esquerda e sombra embaixo/direita."""
        s.rect(x0, y0, x1, y1, base)
        s.hl(x0, x1, y0, hi)
        s.vl(x0, y0, y1, hi)
        s.hl(x0, x1, y1, lo)
        s.vl(x1, y0, y1, lo)

    def outline(s, c="ink", inner_only=False):
        """contorno de 1px por fora (pixels transparentes vizinhos de opacos)."""
        marks = []
        for y in range(s.h):
            for x in range(s.w):
                if s.px[x, y][3] == 0:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        if s.get(x + dx, y + dy)[3] == 255:
                            marks.append((x, y))
                            break
        for x, y in marks:
            s.p(x, y, c)

    def paste(s, o, x, y):
        s.im.alpha_composite(o.im, (x, y))


def strip(frames):
    w, h = frames[0].w, frames[0].h
    im = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        im.alpha_composite(f.im, (i * w, 0))
    return im


def disc(c, cx, cy, r0, r1, col):
    """pixels com distancia ao centro (cx,cy; centros de pixel em +0.5) em [r0,r1]."""
    for y in range(c.h):
        for x in range(c.w):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if r0 <= d <= r1:
                c.p(x, y, col)


def spokes(c, cx, cy, ang_deg, rad, col, n=2):
    """n diametros (2n raios) girando; usa Bresenham a partir do centro."""
    for k in range(n):
        a = math.radians(ang_deg + k * 180.0 / n)
        for sgn in (1, -1):
            x1 = cx + sgn * math.cos(a) * rad
            y1 = cy + sgn * math.sin(a) * rad
            c.line(int(math.floor(cx)), int(math.floor(cy)), int(round(x1 - 0.5)), int(round(y1 - 0.5)), col)


# ---------------------------------------------------------------- plantio
def soil_row(c, y, x0, x1):
    c.hl(x0, x1, y, "3")
    c.hl(x0 + 1, x1 - 1, y, "3")
    for x in range(x0, x1 + 1):
        if (x * 7 + y * 3) % 5 == 0:
            c.p(x, y, "r")
        if (x * 5 + y) % 7 == 0:
            c.p(x, y, "2")


def make_vaso():
    c = Cv(16, 16)
    # balde de tinta cortado: paredes laterais altas, frente baixa; terra no meio
    for (x0, x1, hi, lo) in ((1, 3, "d", "a"), (12, 14, "c", "a")):
        c.rect(x0, 9, x1, 15, "b")
        c.vl(x0, 9, 15, hi)
        c.vl(x1, 9, 15, lo)
        c.hl(x0, x1, 9, "d")
        c.p(x0 + 1, 12, "a")
        c.p(x0 + 1, 11, "c")
    c.p(1, 9, "c"); c.p(14, 9, "b")
    c.hl(2, 2, 10, "c")
    # terra
    for x in range(4, 12):
        c.p(x, 12, "3" if x % 3 else "r")
        c.p(x, 13, "3")
        if x % 4 == 1:
            c.p(x, 13, "r")
    c.hl(5, 10, 11, "3")
    c.p(5, 11, "r"); c.p(9, 11, "2")
    # frente do balde (enferrujada, com resto de tinta amber)
    c.rect(1, 14, 14, 15, "t")
    c.hl(1, 14, 14, "u")
    c.hl(1, 14, 15, "r")
    c.p(5, 14, "f"); c.p(6, 14, "f"); c.p(7, 15, "s"); c.p(11, 14, "s")
    c.p(1, 14, "d"); c.p(1, 15, "a")
    return c


def make_canteiro():
    c = Cv(32, 16)
    # terra
    for x in range(2, 30):
        c.p(x, 11, "3" if x % 4 else "r")
        c.p(x, 12, "3")
    for x in range(2, 30):
        if (x * 3) % 7 == 0:
            c.p(x, 12, "r")
    # tabua da frente
    c.box(1, 13, 30, 15, "s", "t", "r")
    c.hl(1, 30, 13, "u")
    for x in (6, 15, 24):
        c.p(x, 14, "r")     # pregos
    for x in (10, 20, 27):
        c.p(x, 14, "t")
    c.hl(2, 30, 14, "s")
    for x in (6, 15, 24):
        c.p(x, 14, "k")
    # cantos (montantes)
    c.box(0, 9, 2, 15, "s", "t", "r")
    c.box(29, 9, 31, 15, "s", "t", "r")
    c.vl(1, 10, 15, "s")
    c.vl(30, 10, 15, "s")
    c.vl(0, 9, 15, "u")
    c.vl(29, 9, 15, "t")
    c.hl(0, 2, 9, "u")
    c.hl(29, 31, 9, "u")
    c.hl(0, 31, 15, "r")
    c.p(31, 9, "t")
    return c


def make_prateleira():
    c = Cv(32, 32)
    # montantes de tabua
    for (x0, x1) in ((0, 2), (29, 31)):
        c.box(x0, 6, x1, 31, "s", "t", "r")
    c.vl(0, 6, 31, "u")
    c.vl(29, 6, 31, "t")
    c.hl(0, 2, 6, "u")
    c.hl(29, 31, 6, "u")
    # prateleira de cima (y14-15) e de baixo (y28-29)
    for y0 in (14, 28):
        c.box(0, y0, 31, y0 + 1, "s", "u", "r")
        c.hl(0, 31, y0, "u")
        c.hl(1, 30, y0 + 1, "r")
        for x in range(4, 29, 7):
            c.p(x, y0 + 1, "s")
        # terra
        for x in range(3, 29):
            c.p(x, y0 - 2, "3" if (x % 5) else "r")
            c.p(x, y0 - 1, "3")
            if (x * 3) % 7 == 0:
                c.p(x, y0 - 1, "r")
    # blocos de cimento de pe
    c.box(1, 30, 4, 31, "b", "d", "a")
    c.box(27, 30, 30, 31, "b", "d", "a")
    c.p(2, 31, "a")
    # fita/arame no montante
    c.hl(0, 2, 20, "d")
    c.hl(29, 31, 20, "c")
    return c


def make_estufa():
    c = Cv(48, 32)
    c.rect(3, 3, 44, 18, "2")
    # parede de garrafas PET deitadas (tampinhas coloridas), em fileiras alternadas
    caps = ["q", "j", "g", "q", "t", "j"]
    n = 0
    for row in range(5):
        by = 3 + row * 3
        off = 0 if row % 2 == 0 else -4
        for bx in range(3 + off, 45, 9):
            body = [("d", "d"), ("c", "c"), ("b", "a")]
            for i in range(6):
                for j, (a_, b_) in enumerate(body):
                    x = bx + i
                    if 3 <= x <= 44:
                        c.p(x, by + j, a_ if i < 4 else b_)
            for (x, y, col) in ((bx + 6, by, "c"), (bx + 6, by + 1, "c"), (bx + 6, by + 2, "b"),
                                (bx + 7, by + 1, "b"),
                                (bx + 8, by, caps[n % 6]), (bx + 8, by + 1, caps[n % 6]), (bx + 8, by + 2, "1")):
                if 3 <= x <= 44:
                    c.p(x, y, col)
            n += 1
        # sombra entre fileiras
    # estrutura: telhado de plastico e postes
    c.hl(0, 47, 0, "u")
    c.hl(0, 47, 1, "s")
    c.hl(0, 47, 2, "r")
    for (x0, x1) in ((0, 2), (45, 47)):
        c.box(x0, 0, x1, 31, "s", "t", "r")
    c.vl(0, 0, 31, "u")
    c.vl(45, 0, 31, "t")
    c.hl(0, 47, 0, "u")
    # plastico fixado com fita no alto
    c.hl(3, 44, 2, "d")
    for x in range(4, 44, 6):
        c.p(x, 1, "g")
    # prateleira de tras (y19-20) e cama da frente (y29-31)
    c.box(0, 19, 47, 20, "s", "u", "r")
    c.hl(1, 46, 20, "r")
    for x in range(3, 45):
        c.p(x, 17, "3" if x % 5 else "r")
        c.p(x, 18, "3")
        c.p(x, 27, "3" if x % 5 else "r")
        c.p(x, 28, "3")
    c.box(0, 29, 47, 31, "s", "u", "r")
    c.hl(0, 47, 31, "r")
    for x in (8, 23, 38):
        c.p(x, 30, "k")
    # fita nos montantes
    c.hl(0, 2, 11, "d"); c.hl(45, 47, 11, "c")
    return c


# plantas 12x12: estagios 0..3. ancora [6,12].
MOUND = [
    "....r33r....",
    "..r3333332r.",
]


def mound(c, extra=None):
    c.art(0, 10, MOUND)
    c.p(4, 11, "2")
    c.p(8, 11, "r")


def crop(kind, stage):
    c = Cv(12, 12)
    mound(c)
    if kind == "batata":
        if stage == 0:
            c.p(5, 9, "t")
            c.p(6, 10, "t")
            c.p(6, 9, "o")
            c.p(7, 10, "o")
        elif stage == 1:
            c.art(0, 5, [
                "....m..m....",
                "....lj.lj...",
                ".....jlj....",
                ".....rj.....",
                "......j.....",
            ])
            c.p(6, 10, "r")
        elif stage == 2:
            c.art(0, 2, [
                "......m.....",
                "....m.lj.m..",
                "...mlljjllm.",
                "..lljjljjjl.",
                "..ljjjljjjj.",
                "...ijjjjji..",
                "....ijjji...",
                ".....rjr....",
            ])
        else:
            c.art(0, 0, [
                ".....m..m...",
                "....lj.ljm..",
                "..mljjmjjlm.",
                ".mljjlmjjjl.",
                ".ljwjljjwjl.",
                ".ljjjljjjjj.",
                "..jjljjljj..",
                "..ijjjjjji..",
                "...ijjjji...",
                "....ijji....",
            ])
            c.art(0, 9, [
                "..to.rj.ot..",
            ])
            c.p(3, 10, "o")
            c.p(9, 10, "t")
            c.p(9, 11, "u")
            c.p(2, 11, "t")
    elif kind == "feijao":
        stake = "s"
        if stage == 0:
            c.p(5, 9, "y")
            c.p(6, 10, "y")
            c.p(7, 9, "y")
            c.p(4, 10, "y")
        elif stage == 1:
            c.vl(6, 5, 9, stake)
            c.art(0, 5, [
                "...lm..ml...",
                "..lljl.jll..",
                "...ij.jji...",
                "....ij.i....",
            ])
            c.p(6, 9, "j")
        elif stage == 2:
            c.vl(6, 2, 9, stake)
            c.p(6, 1, "u")
            c.art(0, 2, [
                "...m.....m..",
                "..ljm..ml.l.",
                "..jllj.jlj..",
                "...ijjljji..",
                "..ljljjljl..",
                "...ijjjji...",
                "....ijji....",
                ".....rj.....",
            ])
            c.vl(6, 2, 9, stake)
            c.p(6, 3, "j"); c.p(6, 6, "j")
        else:
            c.art(0, 0, [
                "......u.....",
                ".....mlm....",
                "..mljjsjjlm.",
                "..ljjjsjjjl.",
                ".mjjmljjmjjl",
                ".mm.ijsji.mm",
                ".ml..jsj..lm",
                ".ml..jsj..lm",
                "..m..jsj..ml",
                "..j..rsj..j.",
            ])
            c.p(3, 6, "m"); c.p(3, 7, "l"); c.p(8, 6, "m"); c.p(8, 7, "l")
    else:  # tomate
        stake = "s"
        if stage == 0:
            c.p(5, 9, "g")
            c.p(6, 10, "g")
            c.p(7, 9, "h")
        elif stage == 1:
            c.vl(7, 4, 9, stake)
            c.art(0, 5, [
                "...ml.......",
                "..ljj.......",
                "...ij.jl....",
                "....ijjj....",
                ".....ij.....",
            ])
            c.p(6, 10, "j")
        elif stage == 2:
            c.vl(8, 1, 9, stake)
            c.art(0, 2, [
                "....m.m.....",
                "...ljjmj.m..",
                "..ljjljljj..",
                ".ljjjljjjl..",
                "..ijjjjji...",
                "...ijjji....",
                "....ijj.....",
                ".....rj.....",
            ])
            c.p(3, 5, "m")
            c.p(8, 1, "u")
            c.vl(8, 6, 9, stake)
            c.p(9, 7, "l"); c.p(9, 8, "l")   # tomate verde
        else:
            c.vl(8, 0, 9, stake)
            c.art(0, 0, [
                "....m.m.....",
                "...ljjmjlm..",
                "..ljjljjjl..",
                ".ljjjljljj..",
                "..ijjjjji...",
                "...ijjjji...",
                "....ijj.....",
                ".....rj.....",
            ])
            for (x, y) in ((2, 5), (9, 4), (6, 7), (3, 8)):
                c.p(x, y, "t"); c.p(x + 1, y, "x")
                c.p(x, y + 1, "x"); c.p(x + 1, y + 1, "r")
            c.p(2, 5, "u")
            c.p(9, 4, "u"); c.p(6, 7, "u"); c.p(3, 8, "u")
            c.p(8, 0, "u")
            c.vl(8, 1, 3, "s")
    return c


# ---------------------------------------------------------------- agua
def make_gotejador(f):
    c = Cv(16, 16)
    # estaca de madeira
    c.vl(1, 0, 15, "t"); c.vl(2, 0, 15, "s"); c.vl(3, 0, 15, "r")
    c.p(1, 0, "u")
    # garrafa PET de cabeca para baixo: fundo em cima, gargalo embaixo
    for y in range(0, 9):
        c.p(5, y, "d")
        for x in range(6, 10):
            c.p(x, y, "c" if y < 4 else "q")
        c.p(10, y, "b" if y < 4 else "p")
    c.hl(5, 10, 0, "b")
    c.hl(5, 10, 3, "d"); c.p(10, 3, "c")          # nivel da agua
    c.p(6, 5, "d"); c.p(6, 6, "d")                 # brilho
    c.p(6, 1, "d")
    c.hl(6, 9, 9, "q"); c.p(5, 9, "d"); c.p(10, 9, "p")
    c.hl(7, 8, 10, "q")
    c.hl(7, 8, 11, "c")
    c.hl(7, 8, 12, "f"); c.p(7, 12, "g")           # tampa amarela com furo
    # arame prendendo a garrafa na estaca
    c.hl(4, 5, 2, "c"); c.hl(4, 5, 7, "c")
    c.p(3, 2, "c"); c.p(3, 7, "c")
    # pingo
    if f == 0:
        c.p(7, 13, "d")
        c.hl(5, 10, 15, "3")
        c.hl(6, 9, 15, "p")
    else:
        c.p(7, 14, "q")
        c.hl(5, 10, 15, "3")
        c.hl(6, 9, 15, "q")
        c.p(5, 14, "d"); c.p(10, 14, "d")
        c.p(7, 15, "d")
    return c


def make_cisterna(f):
    c = Cv(32, 32)
    # tambor azul de plastico (barril) em cima de cavaletes
    # cavaletes
    c.box(3, 24, 6, 31, "s", "t", "r")
    c.box(25, 24, 28, 31, "s", "t", "r")
    c.hl(2, 29, 23, "r")
    c.box(2, 22, 29, 23, "s", "u", "r")
    # barril
    c.rect(4, 3, 27, 21, "p")
    c.vl(4, 5, 19, "q")
    c.vl(5, 4, 20, "q")
    c.hl(6, 25, 3, "q")
    c.vl(27, 5, 19, "1")
    c.vl(26, 4, 20, "1")
    c.hl(6, 25, 21, "1")
    # cantos arredondados
    for (x, y) in ((4, 3), (27, 3), (4, 21), (27, 21)):
        c.clr(x, y)
    c.p(5, 3, "q")
    c.p(4, 4, "q")
    # aros de metal
    for y in (7, 17):
        c.hl(4, 27, y, "b")
        c.hl(5, 26, y + 1, "a")
        c.p(4, y, "d"); c.p(5, y, "d")
        c.p(27, y + 1, "2")
    # tampa/bocal
    c.box(11, 0, 20, 2, "b", "d", "a")
    c.hl(12, 19, 1, "c")
    c.p(11, 2, "a")
    # indicador de nivel: tubo transparente lateral
    c.rect(22, 9, 24, 16, "k")
    for y in range(10, 16):
        lvl = 12 if f == 0 else 11
        c.p(23, y, "q" if y >= lvl else "2")
    c.p(23, 10 if f else 11, "d")
    # mancha de agua/ferrugem
    c.p(9, 12, "p"); c.p(10, 13, "p"); c.p(8, 11, "q")
    # torneira
    c.rect(13, 19, 15, 20, "b")
    c.p(13, 19, "d")
    c.rect(13, 21, 14, 23, "a")
    c.p(14, 24, "a")
    c.p(15, 18, "t"); c.p(16, 18, "t")   # registro (cabo)
    # pingo e poca
    if f == 0:
        c.p(14, 25, "q")
    else:
        c.p(14, 26, "q")
        c.p(14, 27, "d")
    c.hl(10, 18, 31, "3")
    c.hl(11, 17, 31, "p")
    if f == 1:
        c.p(12, 31, "q"); c.p(16, 31, "q")
    # bolhas no bocal
    return c


def make_bomba(f):
    c = Cv(16, 16)
    dy = [0, 1, 0][f]
    ang = [0, 30, 60][f]
    c.box(0, 14, 15, 15, "s", "t", "r")
    m = Cv(16, 16)
    # motor (tambor) com aletas
    m.box(6, 7, 9, 13, "a", "c", "1")
    for y in (8, 10, 12):
        m.hl(7, 8, y, "b")
    # carcaca da bomba enferrujada
    m.rect(9, 6, 14, 13, "s")
    m.hl(9, 14, 6, "u"); m.vl(9, 6, 13, "t")
    m.hl(9, 14, 13, "r"); m.vl(14, 7, 13, "r")
    m.rect(11, 9, 12, 10, "1")
    m.p(10, 7, "u"); m.p(13, 8, "r")
    # cano de saida
    m.vl(12, 3, 5, "c"); m.vl(13, 3, 5, "a")
    m.hl(12, 15, 2, "c"); m.hl(13, 15, 3, "a")
    m.p(12, 2, "d")
    m.hl(10, 11, 14, "b")
    # volante (disco) na esquerda
    disc(m, 3.0, 10.0, 0, 3.0, "1")
    disc(m, 3.0, 10.0, 2.2, 3.0, "c")
    m.p(5, 10, "a"); m.p(5, 9, "a"); m.p(5, 11, "a")
    c.paste(m, 0, dy)
    sp = Cv(16, 16)
    spokes(sp, 3.0, 10.0 + dy, ang, 2.0, "d", 2)
    for y in range(16):
        for x in range(16):
            if sp.px[x, y][3] and math.hypot(x + .5 - 3.0, y + .5 - 10.0 - dy) < 2.3:
                c.p(x, y, "d")
    c.p(2, 9 + dy, "g")
    y = [4, 8, 12][f]
    c.p(15, y, "q")
    if f == 2:
        c.p(15, y + 1, "d")
    return c


# ---------------------------------------------------------------- energia
def make_bicicleta(f):
    c = Cv(16, 16)
    ring = ["..ccc..",
            ".c...b.",
            "c.....b",
            "c.....b",
            "c.....b",
            ".b...b.",
            "..bbb.."]
    for hx in (3, 12):
        c.art(hx - 3, 9, ring)
    # raios so na roda de tras (a do gerador)
    a = math.radians(45 * f)
    dx = max(-2, min(2, int(round(2.6 * math.cos(a)))))
    dy = max(-2, min(2, int(round(2.6 * math.sin(a)))))
    c.line(3 - dx, 12 - dy, 3 + dx, 12 + dy, "d")
    c.p(3, 12, "g")
    c.p(12, 12, "a")
    # quadro de cano enferrujado
    R, F, BB, S, H = (3, 12), (12, 12), (7, 13), (5, 7), (11, 7)
    c.line(*R, *BB, "s")
    c.line(*BB, *S, "t")
    c.line(*S, *H, "u")
    c.line(*BB, *H, "t")
    c.line(*H, *F, "t")
    # banco e guidao
    c.hl(3, 7, 5, "a"); c.hl(3, 4, 5, "c")
    c.p(5, 6, "t")
    c.vl(11, 4, 6, "b")
    c.hl(11, 14, 3, "c"); c.p(14, 4, "a")
    # dinamo (lata) apertando a roda de tras
    c.rect(0, 7, 1, 8, "f"); c.p(0, 7, "g"); c.p(1, 8, "e")
    # pedal girando
    a = math.radians(90 * f)
    px_, py_ = 7 + int(round(2.2 * math.cos(a))), 13 + int(round(2.2 * math.sin(a)))
    c.line(7, 13, px_, py_, "d")
    c.rect(px_, py_, px_, py_, "g")
    c.p(7, 13, "c")
    c.hl(2, 5, 15, "r"); c.hl(10, 13, 15, "r")
    return c


def make_moinho(f):
    c = Cv(16, 32)
    cx, cy = 8.0, 9.0
    # duto de ar (cano quadrado) com flange
    c.box(5, 17, 10, 31, "b", "d", "a")
    c.vl(6, 18, 30, "c")
    c.vl(9, 18, 30, "a")
    c.hl(4, 11, 17, "d")
    c.hl(4, 11, 18, "a")
    c.p(4, 17, "d")
    c.hl(3, 12, 30, "a"); c.hl(3, 12, 31, "1")
    c.hl(3, 12, 30, "b"); c.p(3, 30, "d")
    # fita e ferrugem no duto
    c.hl(5, 10, 24, "g"); c.hl(5, 10, 25, "e")
    c.p(7, 21, "s"); c.p(8, 22, "s"); c.p(7, 22, "t")
    # gaiola do ventilador (ferro) + aro
    disc(c, cx, cy, 6.3, 7.5, "b")
    for (x, y) in ((3, 4), (4, 3)):
        c.p(x, y, "c")
    c.p(2, 8, "c"); c.p(2, 9, "c"); c.p(8, 2, "c")
    disc(c, cx, cy, 0, 6.2, "2")
    # pas (3), girando 30 graus por quadro
    for k in range(3):
        th = math.radians(f * 30 + k * 120 - 90)
        ux, uy = math.cos(th), math.sin(th)
        for y in range(18):
            for x in range(16):
                rx, ry = x + 0.5 - cx, y + 0.5 - cy
                al = rx * ux + ry * uy
                pe = -rx * uy + ry * ux
                if 1.4 <= al <= 6.0 and -0.6 - 0.22 * al <= pe <= 0.2 + 0.28 * al:
                    # sombra na ponta/lado direito-baixo
                    c.p(x, y, "c" if (rx < 0 or ry < -1) else "b")
    disc(c, cx, cy, 0, 1.6, "e")
    c.p(7, 8, "g")
    # suporte diagonal entre gaiola e duto
    c.line(5, 15, 5, 17, "a"); c.line(10, 15, 10, 17, "a")
    # arames
    c.p(4, 14, "c")
    return c


def make_bateria(f):
    c = Cv(32, 16)
    # base/estrado
    c.hl(1, 30, 15, "r")
    # bateria de carro
    c.box(2, 5, 21, 14, "3", "a", "2")
    c.hl(3, 20, 5, "a")
    c.hl(2, 21, 4, "3"); c.hl(2, 21, 3, "2")
    c.box(2, 3, 21, 5, "3", "a", "1")
    # tampas de celula
    for x in (6, 10, 14, 18):
        c.p(x, 4, "2")
    # rotulo
    c.rect(5, 8, 17, 12, "w")
    c.hl(5, 17, 8, "d"); c.vl(5, 8, 12, "d")
    c.hl(6, 16, 10, "c")
    c.hl(6, 12, 9, "b"); c.hl(6, 14, 11, "b")
    c.rect(14, 12, 16, 12, "e")
    c.hl(5, 17, 12, "c")
    # alca
    c.hl(8, 15, 2, "c"); c.p(8, 3, "b"); c.p(15, 3, "a")
    # terminais
    c.rect(4, 1, 6, 2, "c"); c.p(4, 1, "d"); c.p(5, 0, "x"); c.p(6, 0, "x")
    c.rect(17, 1, 19, 2, "a"); c.p(17, 1, "c"); c.p(18, 0, "1"); c.p(19, 0, "1")
    c.hl(2, 21, 14, "k")
    # cabos
    c.line(6, 1, 6, 0, "x")
    # caixinha de controle (lata)
    c.box(23, 7, 30, 14, "t", "u", "r")
    c.hl(23, 30, 8, "u")
    c.rect(24, 12, 29, 13, "r")
    c.hl(24, 29, 12, "s")
    # fita
    c.hl(23, 30, 11, "d")
    # LED
    if f == 0:
        c.rect(26, 9, 27, 9, "h")
        c.p(26, 9, "h"); c.p(27, 9, "g")
        for (x, y) in ((25, 9), (28, 9), (26, 8), (27, 8)):
            c.p(x, y, "f")
        c.p(25, 8, "e"); c.p(28, 8, "e")
    else:
        c.p(26, 9, "r"); c.p(27, 9, "r")
    # cabo curto da bateria para a caixa
    c.p(22, 9, "x"); c.p(22, 11, "a"); c.p(21, 9, "x"); c.p(21, 11, "a")
    return c


def make_painel():
    c = Cv(32, 16)
    # pernas e base
    c.vl(8, 12, 15, "t"); c.vl(9, 12, 15, "s")
    c.vl(23, 12, 15, "t"); c.vl(24, 12, 15, "s")
    c.hl(5, 12, 15, "r"); c.hl(20, 27, 15, "r")
    # moldura
    c.rect(1, 1, 30, 11, "a")
    c.hl(1, 30, 1, "d"); c.vl(1, 1, 11, "c")
    c.hl(1, 30, 11, "1"); c.vl(30, 1, 11, "2")
    # celulas azuis (2 fileiras x 4 colunas)
    for row, y0 in enumerate((3, 7)):
        for col in range(4):
            x0 = 3 + col * 7
            c.rect(x0, y0, x0 + 5, y0 + 2, "p")
            c.hl(x0, x0 + 5, y0, "q") if (col + row) % 2 == 0 else None
            c.p(x0, y0, "q")
            c.hl(x0, x0 + 5, y0 + 2, "1")
    # reflexo do sol (diagonal)
    for k in range(0, 7):
        x, y = 5 + k * 2, 3 + (k % 2) * 0
    for (x, y) in ((4, 4), (5, 3), (11, 4), (12, 3), (18, 4), (19, 3), (25, 4), (26, 3)):
        c.p(x, y, "d")
    # rachadura e fita
    c.line(17, 7, 21, 9, "k")
    c.line(21, 9, 20, 10, "k")
    c.hl(2, 5, 6, "g")
    return c


# ---------------------------------------------------------------- transporte
def make_calha(f):
    c = Cv(16, 16)

    def surf(x):
        return int(round(3 + (15 - x) * 0.55))
    c.vl(13, surf(13) + 3, 15, "s"); c.vl(12, surf(12) + 3, 15, "t")
    c.vl(3, surf(3) + 3, 15, "s"); c.vl(2, surf(2) + 3, 15, "t")
    c.hl(1, 4, 15, "r"); c.hl(11, 14, 15, "r")
    # calha de zinco
    for x in range(0, 16):
        y = surf(x)
        c.p(x, y, "d")
        c.p(x, y + 1, "c")
        c.p(x, y + 2, "a")
    xs = [13, 11, 8, 6, 4, 2]
    for slot in (f, f + 3):
        cx = xs[slot % 6]
        y0 = surf(cx) - 4
        c.rect(cx - 2, y0 + 1, cx + 2, y0 + 3, "t")
        c.hl(cx - 2, cx + 2, y0 + 1, "u")
        c.hl(cx - 2, cx + 2, y0 + 3, "r")
        c.p(cx - 2, y0 + 2, "u")
        c.p(cx + 2, y0 + 2, "s")
        c.p(cx, y0 + 2, "r")
        c.hl(cx - 1, cx + 1, y0, "o")
        c.p(cx + 1, y0, "n")
        c.p(cx - 2, y0 + 1, "u"); c.p(cx + 2, y0 + 1, "s")
    return c


def make_roldana(f):
    c = Cv(16, 32)
    d = [0, 2, 4, 2][f]
    # viga e suportes
    c.box(0, 0, 15, 3, "s", "u", "r")
    c.hl(1, 14, 2, "t")
    c.p(2, 2, "k"); c.p(13, 2, "k")
    c.vl(7, 4, 5, "a"); c.vl(8, 4, 5, "a")   # ferragem
    # roldana
    disc(c, 8.0, 8.0, 3.0, 4.0, "b")
    disc(c, 8.0, 8.0, 0, 2.9, "2")
    c.p(5, 5, "d"); c.p(6, 4, "d"); c.p(4, 7, "c")
    spokes(c, 8.0, 8.0, -d * 16.0, 2.6, "c", 2)
    c.rect(7, 7, 8, 8, "e")
    c.p(7, 7, "g")
    # cordas: esquerda (x=4) com cesto e direita (x=11) com contrapeso
    yl = 17 + d      # topo do cesto
    yr = 21 - d
    for y in range(9, yl):
        c.p(4, y, "w" if (y + d) % 4 else "d")
    for y in range(9, yr):
        c.p(11, y, "w" if (y + d) % 4 else "d")
    # cesto
    c.rect(2, yl, 7, yl + 5, "t")
    c.hl(2, 7, yl, "u"); c.vl(2, yl, yl + 5, "u")
    c.hl(2, 7, yl + 5, "r"); c.vl(7, yl + 1, yl + 5, "s")
    for k in (1, 3):
        c.hl(3, 6, yl + k + 1, "s")
    c.p(3, yl - 1, "o"); c.p(5, yl - 1, "n"); c.p(4, yl - 1, "o"); c.p(6, yl - 1, "o")
    c.p(3, yl, "t"); c.p(6, yl, "t")
    # contrapeso: lata cheia de pedras
    c.rect(9, yr, 13, yr + 6, "a")
    c.vl(9, yr, yr + 6, "c"); c.hl(9, 13, yr, "d")
    c.hl(9, 13, yr + 6, "1"); c.vl(13, yr, yr + 6, "2")
    c.hl(9, 13, yr + 2, "b"); c.hl(9, 13, yr + 4, "b")
    c.p(11, yr - 1, "d")
    return c


def make_esteira(f):
    c = Cv(32, 16)
    sh = f * 2
    # correia de cima com taliscas; rolos nas pontas; correia de volta embaixo
    for x in range(5, 28):
        c.p(x, 6, "a")
        c.p(x, 7, "3")
    for x in range(5, 28):
        if (x + sh) % 8 in (0, 1):
            c.p(x, 4, "d"); c.p(x, 5, "c")
            c.p(x, 6, "b")
    for x in range(5, 28):
        c.p(x, 12, "3")
        c.p(x, 13, "2")
        if (x - sh) % 8 in (3, 4):
            c.p(x, 12, "a")
    for cx in (5.5, 26.5):
        disc(c, cx, 9.5, 0, 3.6, "2")
        disc(c, cx, 9.5, 2.7, 3.6, "b")
        disc(c, cx, 9.5, 0, 2.6, "1")
        sp = Cv(32, 16)
        spokes(sp, cx, 9.5, -33.0 * f, 2.3, "c", 2)
        for y in range(16):
            for x in range(32):
                if sp.px[x, y][3] and math.hypot(x + .5 - cx, y + .5 - 9.5) < 2.7:
                    c.p(x, y, "c")
        c.p(int(cx - 0.5), 9, "g")
    # pes e longarina
    c.box(3, 14, 5, 15, "s", "t", "r")
    c.box(26, 14, 28, 15, "s", "t", "r")
    c.hl(6, 25, 14, "r")
    # motor (lata) na ponta direita e fio
    c.box(28, 7, 31, 13, "t", "u", "r")
    c.p(30, 9, "k"); c.p(29, 11, "f")
    return c


# ---------------------------------------------------------------- casa / decor
def make_estante():
    c = Cv(16, 32)
    c.rect(1, 1, 14, 30, "2")        # fundo
    # laterais (caixotes)
    for (x0, x1) in ((0, 1), (14, 15)):
        c.box(x0, 0, x1, 31, "s", "t", "r")
    c.vl(0, 0, 31, "u")
    c.vl(15, 1, 31, "r")
    # tabuas
    for y in (10, 20, 30):
        c.hl(0, 15, y, "u")
        c.hl(0, 15, y + 1, "s") if y < 30 else None
        if y < 30:
            c.hl(1, 14, y + 1, "r")
    c.hl(0, 15, 31, "r")
    c.hl(0, 15, 30, "t")
    c.hl(0, 15, 0, "u")
    # livros nivel 1 (y1..9)
    books1 = [("p", 5), ("t", 6), ("f", 4), ("q", 5), ("j", 6), ("w", 3), ("s", 5)]
    x = 2
    for col, h in books1:
        wd = 2 if col != "w" else 1
        if x + wd > 14:
            break
        c.rect(x, 10 - h, x + wd - 1, 9, col)
        c.p(x, 10 - h, "d" if col not in ("w",) else "d")
        c.p(x + wd - 1, 9, "k")
        x += wd
    # um livro deitado em cima de pe
    # nivel 2 (y12..19)
    c.rect(2, 16, 9, 19, "p")      # pilha deitada
    c.hl(2, 9, 16, "q"); c.hl(2, 9, 18, "d"); c.hl(2, 9, 19, "1")
    c.rect(3, 13, 10, 15, "t")
    c.hl(3, 10, 13, "u")
    c.hl(3, 10, 15, "w")
    c.p(10, 14, "s")
    c.rect(11, 12, 12, 19, "j")
    c.p(11, 12, "l"); c.vl(11, 13, 19, "l"); c.p(12, 19, "i")
    c.p(13, 14, "g")
    # nivel 3 (y22..29): caixote, livros em pe e lata de lampiao
    for xx, col, h in ((2, "t", 6), (4, "x", 5), (6, "q", 6), (8, "f", 4)):
        c.rect(xx, 30 - h, xx + 1, 29, col)
        c.p(xx, 30 - h, "d" if col != "q" else "d")
        c.p(xx + 1, 29, "k")
    c.rect(11, 25, 13, 29, "b")    # lata
    c.hl(11, 13, 25, "d"); c.hl(11, 13, 29, "a")
    c.p(12, 27, "f")
    c.p(12, 24, "g")
    return c


def make_poltrona():
    c = Cv(16, 16)
    # pes de caixote
    c.box(3, 13, 5, 15, "s", "t", "r")
    c.box(11, 13, 13, 15, "s", "t", "r")
    # encosto (tecido azul-cinza remendado)
    c.rect(2, 2, 6, 12, "q")
    c.hl(2, 6, 2, "d"); c.vl(2, 2, 12, "d")
    c.vl(6, 3, 12, "p")
    # manta amber jogada no topo do encosto
    c.rect(2, 3, 6, 4, "f")
    c.hl(2, 6, 3, "g"); c.hl(2, 6, 4, "e")
    c.rect(2, 5, 3, 7, "f"); c.vl(2, 3, 7, "g"); c.vl(3, 5, 7, "e")
    # remendo
    c.rect(4, 8, 5, 10, "t")
    c.p(4, 8, "u"); c.p(5, 10, "r")
    # assento e braco
    c.rect(7, 9, 14, 12, "q")
    c.hl(7, 14, 9, "d"); c.hl(7, 14, 12, "p")
    c.vl(14, 9, 12, "p")
    c.p(10, 10, "d")
    c.rect(7, 6, 13, 8, "q")
    c.hl(7, 13, 6, "d"); c.hl(7, 13, 8, "p"); c.vl(13, 7, 8, "p")
    c.p(8, 7, "d")
    c.outline("1")
    return c


def make_mesinha():
    c = Cv(16, 16)
    # tampo, gaveta e pernas
    c.box(0, 8, 15, 9, "s", "u", "r")
    c.hl(0, 15, 8, "u")
    c.hl(1, 14, 9, "r")
    c.rect(4, 10, 11, 11, "s")
    c.hl(4, 11, 10, "r"); c.hl(4, 11, 11, "r")
    c.p(7, 11, "g"); c.p(8, 11, "e")
    c.box(2, 10, 3, 15, "s", "t", "r")
    c.box(12, 10, 13, 15, "s", "t", "r")
    # folha de papel com rabiscos e lapis
    c.rect(1, 6, 6, 7, "w")
    c.hl(1, 6, 5, "d")
    c.rect(1, 5, 5, 5, "d")
    c.hl(2, 5, 6, "c"); c.hl(2, 4, 7, "c")
    c.line(5, 7, 8, 7, "f"); c.p(9, 7, "o"); c.p(8, 7, "g")
    return c


def make_foto():
    c = Cv(16, 16)
    # moldura de madeira
    c.box(1, 2, 14, 13, "s", "t", "r")
    c.rect(3, 4, 12, 11, "d")
    # paisagem desbotada: ceu, sol, colinas, uma arvore
    c.rect(3, 4, 12, 7, "d")
    c.rect(3, 8, 12, 11, "c")
    for x in range(3, 13):
        top = 8 - (1 if x in (6, 7, 8) else 0) + (1 if x in (11, 12) else 0)
        for y in range(top, 12):
            c.p(x, y, "b" if y == top else "c")
    c.p(10, 5, "g"); c.p(11, 5, "g")
    c.p(5, 7, "a"); c.p(5, 6, "a")  # arvore ao longe
    c.hl(3, 12, 4, "w")
    c.vl(3, 4, 11, "w")
    c.hl(3, 12, 11, "a")
    # fita/prego
    c.p(7, 1, "k"); c.p(8, 1, "k")
    c.p(7, 2, "c"); c.p(8, 2, "c")
    c.p(2, 2, "u")
    return c


def make_foto_dela():
    c = Cv(16, 16)
    # moldura mais cuidada (ambar) com passe-partout
    c.box(0, 1, 15, 14, "e", "g", "r")
    c.hl(0, 15, 1, "h")
    c.rect(2, 3, 13, 12, "w")
    # paisagem: ceu quente, campo, arvore e casinha com janela acesa
    c.rect(3, 4, 12, 11, "g")
    c.rect(3, 4, 12, 6, "h")
    c.hl(3, 12, 7, "g")
    c.rect(3, 9, 12, 11, "l")
    c.hl(3, 12, 9, "m")
    # colina
    for x in range(3, 13):
        c.p(x, 9 - (1 if x in (4, 5, 6, 7) else 0), "l")
    c.hl(8, 12, 9, "j")
    # arvore
    c.vl(5, 7, 10, "s")
    c.rect(4, 5, 6, 6, "j"); c.p(5, 4, "j"); c.p(4, 5, "l")
    # casa
    c.rect(9, 7, 11, 9, "t")
    c.hl(9, 11, 6, "r"); c.p(10, 5, "r")
    c.p(10, 8, "h")
    # sol
    c.p(12, 4, "f")
    c.hl(3, 12, 11, "i")
    # laco de fita no canto
    c.p(13, 0, "x"); c.p(14, 0, "x"); c.p(14, 1, "x")
    return c


def make_cama_dela():
    c = Cv(32, 16)
    # estrado de paletes
    c.hl(1, 30, 15, "1")
    c.box(1, 12, 30, 14, "s", "t", "r")
    c.hl(1, 30, 12, "u")
    for x in (7, 15, 23):
        c.vl(x, 13, 14, "r")
    c.box(2, 14, 4, 15, "s", "t", "r")
    c.box(27, 14, 29, 15, "s", "t", "r")
    # colchao e cobertor de retalhos arrumado
    c.rect(2, 8, 29, 11, "q")
    c.hl(2, 29, 8, "d")
    c.hl(2, 29, 11, "p")
    # retalhos (patchwork em duas fileiras desencontradas)
    pal = ["f", "j", "t", "q", "e", "l"]
    for i in range(6):
        x0 = 8 + i * 4
        c.rect(x0, 9, min(x0 + 3, 29), 9, pal[i % 6])
        c.rect(x0 + 2, 10, min(x0 + 5, 29), 10, pal[(i + 3) % 6])
        c.rect(x0, 10, x0 + 1, 10, pal[(i + 2) % 6])
    c.hl(8, 29, 8, "d")
    c.hl(8, 29, 11, "p")
    # travesseiro
    c.rect(2, 5, 8, 8, "w")
    c.hl(2, 8, 5, "d")
    c.rect(2, 6, 3, 7, "d")
    c.hl(3, 8, 8, "c")
    c.p(2, 8, "d")
    c.p(8, 6, "c"); c.p(8, 7, "c")
    c.p(5, 6, "c")
    # cabeceira
    c.box(0, 3, 1, 15, "s", "t", "r")
    c.hl(0, 1, 2, "u")
    c.vl(0, 3, 15, "u")
    # manta dobrada no pe
    c.rect(26, 6, 30, 8, "j")
    c.hl(26, 30, 6, "l"); c.hl(26, 30, 8, "i")
    c.vl(26, 6, 8, "l")
    return c


def make_cantinho():
    c = Cv(32, 16)
    # tapete de retalhos (franjas nas pontas), mais claro sob o abajur
    c.rect(1, 13, 30, 14, "t")
    c.hl(1, 30, 15, "r")
    c.hl(1, 30, 13, "s")
    for x in range(1, 31):
        pool = 2 <= x <= 14
        c.p(x, 13, "u" if pool else "t")
        c.p(x, 14, "t" if pool else "s")
    for x in range(2, 30, 4):
        c.p(x, 13, "g"); c.p(x + 1, 13, "g"); c.p(x, 14, "f"); c.p(x + 1, 14, "f")
    for y in (13, 14):
        c.p(0, y, "w" if y == 13 else "d")
        c.p(31, y, "d" if y == 13 else "w")
    # almofada amarela
    c.rect(19, 9, 25, 12, "f")
    c.hl(19, 25, 9, "g"); c.vl(19, 9, 12, "g")
    c.hl(19, 25, 12, "e"); c.vl(25, 10, 12, "e")
    for x in (21, 23):
        c.p(x, 10, "g"); c.p(x, 11, "e")
    c.p(19, 9, "h")
    # banquinho + abajur
    c.box(3, 9, 8, 12, "s", "t", "r")
    c.hl(3, 8, 9, "u")
    c.p(4, 12, "r"); c.p(7, 12, "r")
    c.vl(6, 5, 8, "b"); c.vl(5, 5, 8, "c"); c.p(6, 8, "a")
    c.art(2, 0, [
        "...gg...",
        "..ghhg..",
        ".gghhgg.",
        "fghhhhgf",
        "eeffffee",
    ])
    # luz no chao
    # livro e caneca ao lado do banquinho
    c.rect(11, 11, 15, 12, "j"); c.hl(11, 15, 11, "l"); c.hl(11, 15, 12, "i")
    return c


def make_planta_dela():
    c = Cv(16, 16)
    # vaso de lata pintada (azul-cinza) com aro claro
    c.rect(4, 11, 11, 15, "q")
    c.hl(4, 11, 11, "d")
    c.vl(4, 12, 15, "d")
    c.hl(4, 11, 15, "p")
    c.vl(11, 12, 15, "p")
    c.hl(5, 10, 13, "p")
    c.p(5, 12, "d")
    # terra
    c.hl(5, 10, 10, "3")
    # folhagem (jiboia)
    c.art(0, 0, [
        "....m...l.......",
        "..ml.lj.jlm.....",
        ".mljjjljjjlm....",
        ".ljjjmjjmjjl....",
        "..ijljjjjjl.....",
        "...ijjjjji......",
        "....ijjji.......",
        ".....ijj........",
    ])
    c.vl(7, 7, 10, "j")
    c.vl(8, 8, 10, "i")
    # folhas caidas
    c.art(10, 8, [
        "..l.",
        ".ljl",
        ".jji",
        "..j.",
    ])
    c.p(12, 7, "i")
    # flor pequena
    c.p(3, 2, "x")
    c.p(10, 3, "g"); c.p(11, 3, "f")
    # luz
    return c


def make_cabide():
    c = Cv(16, 32)
    # pe de madeira
    c.box(4, 29, 11, 31, "s", "t", "r")
    c.hl(4, 11, 29, "u")
    c.p(3, 31, "r"); c.p(12, 31, "r")
    # haste
    c.box(7, 2, 8, 29, "s", "u", "r")
    c.vl(7, 2, 29, "u")
    c.p(7, 1, "u"); c.p(8, 1, "t")
    # ganchos
    c.line(7, 4, 4, 2, "s"); c.line(8, 4, 11, 2, "s")
    c.p(4, 1, "u"); c.p(11, 1, "t")
    # casaco (cinza-azulado) sobre um cabide
    for y in range(5, 25):
        if y == 5:
            hw = 1
        elif y == 6:
            hw = 3
        elif y == 7:
            hw = 4
        elif y == 8:
            hw = 5
        else:
            hw = 6
        for x in range(8 - hw, 8 + hw):
            c.p(x, y, "q")
    # costuras das mangas e sombra
    for y in range(9, 24):
        c.p(5, y, "p")
        c.p(10, y, "p")
        c.p(13, y, "p")
        c.p(12, y, "p") if y > 12 else None
    c.vl(2, 9, 23, "d")
    c.hl(2, 13, 24, "1")
    c.hl(3, 12, 23, "p")
    # fecho de botoes
    c.vl(8, 8, 23, "p")
    for y in (11, 14, 17, 20):
        c.p(9, y, "g")
    # bolsos
    c.hl(11, 12, 19, "p"); c.hl(3, 4, 19, "p")
    # gola
    c.p(6, 7, "p"); c.p(7, 8, "p"); c.p(9, 8, "p"); c.p(10, 7, "p")
    # cachecol (amber) no gancho direito
    c.rect(11, 3, 12, 9, "f")
    c.vl(11, 3, 9, "g")
    c.vl(12, 4, 9, "e")
    c.p(11, 10, "f"); c.p(12, 10, "e")
    c.hl(11, 12, 6, "e")
    c.p(11, 11, "f"); c.p(12, 11, "e")
    return c


def make_caneca(n):
    c = Cv(8, 8)
    def mug(x, body, hi, lo):
        c.rect(x, 4, x + 2, 7, body)
        c.vl(x, 4, 7, hi)
        c.vl(x + 2, 5, 7, lo)
        c.hl(x, x + 2, 7, lo)
        c.p(x + 3, 5, hi)
        c.p(x + 3, 6, hi)
        c.hl(x + 1, x + 1, 4, "2")   # cafe
    mug(0, "t", "u", "r")
    c.p(1, 2, "d"); c.p(1, 1, "c") if n == 2 else None
    if n == 2:
        mug(4, "q", "d", "p")
        c.p(5, 2, "d")
        c.p(5, 1, "c")
    return c


# ---------------------------------------------------------------- build
SPECS = []   # (nome, frame_w, frame_h, [frames], fps, anchor, extra)


def add(name, frames, fps=0, anchor=None, **extra):
    f0 = frames[0]
    anchor = anchor or [f0.w // 2, f0.h]
    SPECS.append((name, f0.w, f0.h, frames, fps, anchor, extra))


def build_all():
    add("vaso", [make_vaso()], plots=[[8, 14]])
    add("canteiro", [make_canteiro()], plots=[[6, 14], [16, 14], [26, 14]])
    add("prateleira", [make_prateleira()],
        plots=[[6, 28], [16, 28], [26, 28], [11, 14], [21, 14]])
    add("estufa", [make_estufa()],
        plots=[[8, 19], [21, 19], [34, 19], [14, 29], [27, 29], [40, 29]])
    for k in ("batata", "feijao", "tomate"):
        add("crop_" + k, [crop(k, s) for s in range(4)], anchor=[6, 12])
    add("gotejador", [make_gotejador(i) for i in range(2)], fps=2)
    add("cisterna", [make_cisterna(i) for i in range(2)], fps=1)
    add("bomba", [make_bomba(i) for i in range(3)], fps=6)
    add("bicicleta", [make_bicicleta(i) for i in range(4)], fps=8)
    add("moinho", [make_moinho(i) for i in range(4)], fps=8)
    add("bateria", [make_bateria(i) for i in range(2)], fps=2)
    add("painel", [make_painel()])
    add("calha", [make_calha(i) for i in range(3)], fps=4)
    add("roldana", [make_roldana(i) for i in range(4)], fps=6)
    add("esteira", [make_esteira(i) for i in range(4)], fps=8)
    add("estante", [make_estante()])
    add("poltrona", [make_poltrona()])
    add("mesinha", [make_mesinha()])
    add("foto", [make_foto()])
    add("cama_dela", [make_cama_dela()])
    add("cantinho", [make_cantinho()])
    add("planta_dela", [make_planta_dela()])
    add("cabide", [make_cabide()])
    add("caneca", [make_caneca(1), make_caneca(2)], anchor=[4, 8],
        overlay_on="mesinha", overlay_pos=[8, 0])
    add("foto_dela", [make_foto_dela()])


def contact(path, items, scale=6, anim=False):
    """folha de contato ampliada com rotulos."""
    font = ImageFont.load_default()
    pad = 10
    cells = []
    for name, imgs in items:
        cells.append((name, imgs))
    # layout em linhas de largura max
    maxw = 1500
    x = pad
    y = pad
    rowh = 0
    placed = []
    for name, imgs in cells:
        w = sum(i.width * scale + 4 for i in imgs) - 4
        h = max(i.height for i in imgs) * scale
        w = max(w, len(name) * 6 + 4)
        if x + w + pad > maxw:
            x = pad
            y += rowh + 24
            rowh = 0
        placed.append((name, imgs, x, y))
        x += w + 18
        rowh = max(rowh, h)
    H = y + rowh + 24 + pad
    sheet = Image.new("RGBA", (maxw, H), RGB["dark2"] + (255,))
    d = ImageDraw.Draw(sheet)
    for name, imgs, x, y in placed:
        d.text((x, y), name, fill=RGB["conc4"], font=font)
        xx = x
        for im in imgs:
            big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
            bg = Image.new("RGBA", big.size, RGB["dark1"] + (255,))
            # tabuleiro sutil para ver o recorte
            sheet.alpha_composite(bg, (xx, y + 14))
            sheet.alpha_composite(big, (xx, y + 14))
            d.rectangle((xx - 1, y + 13, xx + big.width, y + 14 + big.height), outline=RGB["dark3"] + (255,))
            xx += big.width + 4
    sheet.convert("RGB").save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    build_all()
    manifest = {}
    items_static, items_anim = [], []
    for name, w, h, frames, fps, anchor, extra in SPECS:
        im = snap_image(strip(frames))
        rel = "obj/%s.png" % name
        im.save(os.path.join(OUT, name + ".png"))
        e = {"file": rel, "frame_w": w, "frame_h": h, "frames": len(frames), "fps": fps, "anchor": anchor}
        e.update(extra)
        manifest[name] = e
        splitted = [im.crop((i * w, 0, (i + 1) * w, h)) for i in range(len(frames))]
        items_static.append((name, [splitted[-1] if name.startswith("crop") is False else im]))
        if len(frames) > 1:
            items_anim.append((name + (" @%dfps" % fps if fps else ""), splitted))
    with open(MANIFEST, "w") as fh:
        json.dump(manifest, fh, indent=2, ensure_ascii=False)
    contact(os.path.join(OUT, "_contact_obj.png"), [(n, [i]) if True else None for n, i in
            [(n, im[0]) for n, im in items_static]], 6)
    contact(os.path.join(OUT, "_contact_obj_anim.png"), items_anim, 6, True)
    bad = {}
    for fn in sorted(os.listdir(OUT)):
        if fn.endswith(".png") and not fn.startswith("_"):
            r = check_image(os.path.join(OUT, fn))
            if r:
                bad[fn] = r
    print("OK" if not bad else "PROBLEMAS: %s" % bad)


if __name__ == "__main__":
    main()
