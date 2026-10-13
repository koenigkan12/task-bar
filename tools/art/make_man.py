#!/usr/bin/env python3
"""Gerador do homem do bunker (ARTE-PERSONAGEM).

Escreve assets/art/man/*.png (tiras horizontais 32x32) + assets/art/manifest_man.json
+ assets/art/man/_contact_man.png e _preview_man_anim.png (fora do manifesto).

Abordagem: corpo por peças paramétricas (esqueleto + IK de dois ossos). Cada quadro é uma
"pose" (dict de articulações); o renderizador desenha costas-braço, perna de trás, tronco,
perna da frente, cabeça, braço da frente e adereços (ferramentas) nas mãos.
Coordenadas em pixels "de fronteira": o pixel (x,y) cobre [x,x+1]x[y,y+1]. Pés em y=32.
Luz quente de cima/esquerda. Tudo passa por palette.snap_image.

Convenção de alinhamento com os móveis (a cena posiciona o quadro com a âncora [16,31] sobre a
linha dos pés, y=80 do mundo; ajuste fino de 1-2 px na cena se o móvel pedir):
 - man_walk: 3 px de passada por quadro a 8 fps = 24 px/s sem escorregar o pé (man_carry: 2 px = 16 px/s);
   os valores vão no manifesto como "speed_px_s".
 - man_sit_read/listen/nap: quadril em y~25.6 (assento ~5-6 px acima do chão), costas em x~11-12,
   joelhos em x~18, pés em y=31. A poltrona deve ter o assento nessa altura.
 - man_pedal: quadril em (13, 21) (selim ~10 px acima do chão), pedivela centrado em (17, 25) raio 3.2,
   mãos no guidão em (21, 19). Só o corpo; a bicicleta é outro sprite.
 - man_sleep: de costas, cabeça à direita, costas apoiadas em y=26 (colchão ~5 px acima do chão);
   o cobertor (rust) faz parte do quadro. Largura ocupada: x 1..28.
 - man_write: mão com lápis em (24, 22.5) (tampo da mesinha ~y 23). man_photo/man_eat: adereços na mão.
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from palette import RGB, check_image, snap_image  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "art", "man")
MANIFEST = os.path.join(ROOT, "assets", "art", "manifest_man.json")
S = 32

# ---------------------------------------------------------------- materiais (hl, mid, sh)
MAT = {
    "shirt":     ("cloth2", "cloth2", "cloth1"),
    "shirt_far": ("cloth1", "cloth1", "dark3"),
    "sleeve":    ("cloth2", "cloth1", "cloth1"),
    "sleeve_far": ("cloth1", "cloth1", "dark3"),
    "skin":      ("skin2", "skin2", "skin1"),
    "skin_far":  ("skin1", "skin1", "skin1"),
    "pants":     ("dark3", "dark2", "dark2"),
    "pants_far": ("conc1", "dark3", "dark3"),
    "boot":      ("dark3", "ink", "ink"),
    "boot_far":  ("dark3", "dark1", "dark1"),
    "hair":      ("dark3", "dark2", "dark1"),
}


class Cv:
    def __init__(self):
        self.p = {}
        self.mat = {}

    def put(self, x, y, c):
        x = int(math.floor(x))
        y = int(math.floor(y))
        if 0 <= x < S and 0 <= y < S:
            if c is None:
                self.p.pop((x, y), None)
            else:
                self.p[(x, y)] = c

    def rect(self, x, y, w, h, c):
        for j in range(h):
            for i in range(w):
                self.put(x + i, y + j, c)

    def line(self, x0, y0, x1, y1, c):
        x0, y0, x1, y1 = [int(round(v)) for v in (x0, y0, x1, y1)]
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.put(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def pix(self, pts, c):
        for (x, y) in pts:
            self.put(x, y, c)

    def image(self):
        im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        px = im.load()
        for (x, y), c in self.p.items():
            r, g, b = RGB[c]
            px[x, y] = (r, g, b, 255)
        return im


def capsule(a, b, ra, rb=None):
    rb = ra if rb is None else rb
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    m = set()
    R = max(ra, rb) + 1
    for y in range(int(min(ay, by) - R), int(max(ay, by) + R) + 1):
        for x in range(int(min(ax, bx) - R), int(max(ax, bx) + R) + 1):
            px, py = x + 0.5, y + 0.5
            t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L2))
            cx, cy = ax + t * dx, ay + t * dy
            r = ra + (rb - ra) * t
            if (px - cx) ** 2 + (py - cy) ** 2 <= r * r:
                m.add((x, y))
    return m


def paint(cv, mask, mat, edge=False, tone=None):
    """Pinta a máscara com sombreamento por vizinhança (luz de cima/esquerda)."""
    hl, mid, sh = MAT[mat]
    for (x, y) in mask:
        up = (x, y - 1) in mask
        lf = (x - 1, y) in mask
        rt = (x + 1, y) in mask
        dn = (x, y + 1) in mask
        lit = (not up) or (not lf)
        dark = (not rt) or (not dn)
        if lit and dark:
            c = mid
        elif lit:
            c = hl
        elif dark:
            c = sh
        else:
            c = mid
        if tone:
            c = {"hl": hl, "mid": mid, "sh": sh}[tone]
        cv.put(x, y, c)
        cv.mat[(x, y)] = mat
    if edge:
        only = edge if isinstance(edge, (set, frozenset)) else None
        for (x, y) in mask:
            for (nx, ny) in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if (nx, ny) not in mask and (nx, ny) in cv.p and (only is None or cv.p[(nx, ny)] in only):
                    cv.p[(nx, ny)] = "ink"


def ik(root, target, a, b, bend):
    """IK de dois ossos. bend: 'fwd','back','down','up' = lado para onde o cotovelo/joelho aponta."""
    rx, ry = root
    tx, ty = target
    dx, dy = tx - rx, ty - ry
    d = math.hypot(dx, dy)
    d = max(abs(a - b) + 0.01, min(a + b - 0.01, d))
    if math.hypot(dx, dy) > 0:
        ux, uy = dx / math.hypot(dx, dy), dy / math.hypot(dx, dy)
    else:
        ux, uy = 1, 0
    x = (a * a - b * b + d * d) / (2 * d)
    h = math.sqrt(max(0.0, a * a - x * x))
    bx, by = rx + ux * x, ry + uy * x
    cands = [(bx - uy * h, by + ux * h), (bx + uy * h, by - ux * h)]
    key = {
        "fwd": lambda p: p[0],
        "back": lambda p: -p[0],
        "down": lambda p: p[1],
        "up": lambda p: -p[1],
    }[bend]
    knee = max(cands, key=key)
    # alvo efetivo (se esticou demais)
    end = (rx + ux * d, ry + uy * d)
    return knee, end


# ---------------------------------------------------------------- cabeça (grade 10x10)
# a,b,c = cabelo (claro, médio, escuro); S/s pele; e sobrancelha; E olho; w branco do olho;
# d barba (dark3); D barba (pele+barba xadrez, tratada à parte); m boca; n nariz; r orelha
HEADS = {
    "fwd": [
        "..bbbb....",
        ".abbbbbb..",
        "abbbbbbbb.",
        "bbbbbbSSS.",
        "bbbbsSSSS.",
        "bbbrsSSESn",
        "bbbrsSDSSn",
        ".bbdDdDdd.",
        "..bdddmmd.",
        "...ddddd..",
    ],
    "down": [
        "..aabbb...",
        ".bbbbbbb..",
        ".bbbbbbbb.",
        "bbbbbbbbb.",
        "bbbrsSSSSb",
        ".bbrsSSSS.",
        ".bdDsSSES.",
        ".bdDdDSSn.",
        ".ddddgdd..",
        "...dddmd..",
    ],
    "up": [
        "...bbb....",
        ".bbbbbbb..",
        "bbbbbbSS..",
        "abbbbSSSS.",
        "bbbbsSSESn",
        "bbbbsSDSSn",
        "bbbrsSdDdm",
        "bbbbdDdgdd",
        ".bbbddddd.",
        "....bdd...",
    ],
}


def _closed(grid):
    out = []
    for row in grid:
        if "E" in row:
            k = row.index("E")
            row = row[:k - 1] + "yz" + row[k + 1:]
        out.append(row)
    return out


def _antitranspose(grid):
    n = len(grid)
    new = [["."] * n for _ in range(n)]
    for r in range(n):
        for c in range(n):
            new[n - 1 - c][n - 1 - r] = grid[r][c]
    return ["".join(r) for r in new]


for _k in list(HEADS):
    HEADS[_k + "_c"] = _closed(HEADS[_k])
HEADS["lie"] = _antitranspose(HEADS["fwd"])
HEADS["lie_c"] = _antitranspose(HEADS["fwd_c"])

HEAD_COL = {
    "z": "dark1", "y": "dark3",
    "a": "dark3", "b": "dark2", "c": "dark1",
    "S": "skin2", "s": "skin1", "e": "dark1", "E": "ink", "w": "paper",
    "d": "dark3", "D": "skin1", "g": "conc1", "m": "rust1", "n": "skin2", "r": "skin1",
}


def draw_head(cv, ox, oy, mode="fwd", eyes="open"):
    grid = HEADS[mode + ("_c" if eyes == "closed" else "")]
    for j, row in enumerate(grid):
        for i, ch in enumerate(row):
            if ch == ".":
                continue
            c = HEAD_COL[ch]
            cv.put(ox + i, oy + j, c)


# ---------------------------------------------------------------- renderização

UARM, FARM = 4.0, 3.8


def boot(cv, ax, ay, kind="flat", far=False):
    """Bota 4x2 com a ponta para a direita. (ax, ay) = canto sup. esq. da bota (pés = ay+2 no chão)."""
    mat = "boot_far" if far else "boot"
    ax, ay = int(round(ax)), int(round(ay))
    if kind == "flat":
        m = {(ax + i, ay + j) for i in range(4) for j in range(2)}
    elif kind == "toe":  # calcanhar levantado, ponta no chão
        m = {(ax, ay), (ax + 1, ay), (ax + 1, ay + 1), (ax + 2, ay + 1), (ax + 3, ay + 1), (ax + 2, ay)}
    elif kind == "up":  # ponta levantada (contato do calcanhar)
        m = {(ax, ay + 1), (ax + 1, ay + 1), (ax + 2, ay + 1), (ax + 2, ay), (ax + 3, ay), (ax, ay)}
    else:
        raise ValueError(kind)
    paint(cv, m, mat)
    return m


def torso_details(cv, hip, sh):
    hip = (hip[0] + (sh[0]-hip[0])/math.hypot(sh[0]-hip[0], sh[1]-hip[1])*1.5, hip[1] + (sh[1]-hip[1])/math.hypot(sh[0]-hip[0], sh[1]-hip[1])*1.5)
    ux, uy = sh[0] - hip[0], sh[1] - hip[1]
    L = math.hypot(ux, uy)
    ux, uy = ux / L, uy / L
    fx, fy = -uy, ux

    def at(t, q):
        return hip[0] + (sh[0] - hip[0]) * t + fx * q, hip[1] + (sh[1] - hip[1]) * t + fy * q

    # cinto (linha dark1 + fivela amber)
    for q in (-2, -1, 0, 1, 2):
        x, y = at(0.12, q)
        if (int(math.floor(x)), int(math.floor(y))) in cv.p:
            cv.put(x, y, "dark1")
    x, y = at(0.12, 2)
    cv.put(x, y, "amber2")
    # gola aberta (pele) e bolso
    x, y = at(1.0, 1.5)
    cv.put(x, y, "skin1")
    x, y = at(0.72, 1.2)
    cv.put(x, y, "cloth1")
    x, y = at(0.72, 2.2)
    cv.put(x, y, "cloth1")
    # prega da camisa
    x, y = at(0.45, 0.5)
    cv.put(x, y, "cloth1")


THIGH, SHIN = 4.7, 4.7
UARM, FARM = 4.0, 3.8
FLOOR = 30.0  # tornozelo (topo da bota); sola em 32


class Grid:
    """Sprite de adereço desenhado por código numa grade de caracteres; pode ser girado ao carimbar."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.g = [["."] * w for _ in range(h)]

    def put(self, x, y, ch):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.g[y][x] = ch

    def rect(self, x, y, w, h, ch):
        for j in range(h):
            for i in range(w):
                self.put(x + i, y + j, ch)

    def line(self, x0, y0, x1, y1, ch):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for k in range(n + 1):
            self.put(round(x0 + (x1 - x0) * k / n), round(y0 + (y1 - y0) * k / n), ch)

    def pts(self, lst, ch):
        for (x, y) in lst:
            self.put(x, y, ch)


def stamp(cv, grid, cmap, pivot, at, deg=0.0, flipx=False):
    """Carimba a grade no canvas: o ponto `pivot` (coord. contínua na grade) vai para `at`; gira `deg` graus (horário)."""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    R = int(math.hypot(grid.w, grid.h)) + 2
    for Y in range(int(at[1]) - R, int(at[1]) + R + 1):
        for X in range(int(at[0]) - R, int(at[0]) + R + 1):
            rx, ry = X + 0.5 - at[0], Y + 0.5 - at[1]
            sx = rx * ca + ry * sa + pivot[0]
            sy = -rx * sa + ry * ca + pivot[1]
            c, r = int(math.floor(sx)), int(math.floor(sy))
            if 0 <= c < grid.w and 0 <= r < grid.h:
                ch = grid.g[r][c]
                if ch != ".":
                    cv.put(X, Y, cmap[ch])


def xf(pivot, at, deg, pt):
    """Onde cai o ponto `pt` (coord. da grade) depois de girar em torno do pivot."""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    dx, dy = pt[0] - pivot[0], pt[1] - pivot[1]
    return at[0] + dx * ca - dy * sa, at[1] + dx * sa + dy * ca


# ---------------------------------------------------------------- adereços
def _mk_can():
    g = Grid(14, 9)
    g.rect(3, 3, 6, 5, "b")
    g.rect(3, 3, 6, 1, "h")
    g.rect(3, 4, 1, 4, "h")
    g.rect(8, 4, 1, 4, "B")
    g.rect(3, 6, 6, 1, "B")
    g.rect(3, 7, 6, 1, "D")
    g.pts([(5, 5), (6, 5), (5, 4)], "r")
    g.pts([(3, 2), (3, 1), (4, 0), (5, 0), (6, 1), (6, 2)], "k")
    g.pts([(9, 5), (10, 4), (11, 3), (12, 2)], "B")
    g.pts([(9, 6), (10, 5), (11, 4)], "D")
    g.pts([(12, 1), (13, 1), (13, 2)], "h")
    return g


def _mk_hammer():
    g = Grid(5, 11)
    g.rect(0, 0, 5, 3, "b")
    g.rect(0, 0, 5, 1, "h")
    g.rect(0, 2, 5, 1, "B")
    g.pts([(4, 1), (4, 2)], "B")
    g.pts([(0, 2)], "D")
    for y in range(3, 10):
        g.put(2, y, "w" if y % 2 else "W")
    g.pts([(1, 10), (2, 10), (3, 10)], "k")
    return g


def _mk_shovel():
    g = Grid(5, 13)
    g.pts([(1, 0), (2, 0), (3, 0)], "k")
    for y in range(1, 8):
        g.put(2, y, "w" if y % 2 else "W")
    g.rect(1, 8, 3, 4, "b")
    g.pts([(1, 8), (1, 9), (1, 10)], "h")
    g.pts([(3, 9), (3, 10), (3, 11)], "B")
    g.pts([(2, 12)], "B")
    g.put(2, 8, "B")
    return g


def _mk_basket():
    g = Grid(9, 8)
    g.rect(0, 3, 9, 1, "R")
    for y in range(4, 7):
        for x in range(9):
            g.put(x, y, "w" if (x + y) % 2 == 0 else "W")
    g.rect(1, 7, 7, 1, "D")
    g.rect(0, 4, 1, 3, "W")
    g.rect(8, 4, 1, 3, "D")
    # batatas
    g.pts([(1, 1), (2, 1), (1, 2), (2, 2), (3, 2)], "p")
    g.pts([(4, 0), (5, 0), (4, 1), (5, 1), (6, 1), (3, 1), (4, 2), (5, 2), (6, 2)], "q")
    g.pts([(7, 1), (7, 2), (8, 2), (6, 2)], "p")
    g.pts([(1, 1), (4, 0)], "h")
    return g


def _mk_book():
    g = Grid(6, 5)
    g.rect(0, 0, 4, 4, "P")
    g.rect(4, 0, 2, 5, "c")
    g.rect(0, 4, 6, 1, "d")
    g.pts([(1, 1), (2, 1), (1, 2)], "p")
    return g


def _mk_photo():
    g = Grid(5, 5)
    g.rect(0, 0, 5, 5, "P")
    g.rect(1, 1, 3, 2, "s")
    g.rect(1, 3, 3, 1, "l")
    g.put(3, 1, "a")
    return g


def _mk_foodcan():
    g = Grid(4, 5)
    g.rect(0, 0, 4, 1, "h")
    g.rect(0, 1, 4, 4, "b")
    g.rect(0, 2, 4, 2, "a")
    g.rect(0, 2, 1, 2, "A")
    g.put(1, 3, "r")
    g.rect(3, 1, 1, 4, "B")
    g.rect(0, 4, 4, 1, "B")
    return g


def _mk_pencil():
    g = Grid(5, 1)
    g.pts([(0, 0)], "r")
    g.pts([(1, 0), (2, 0), (3, 0)], "a")
    g.pts([(4, 0)], "i")
    return g


CAN, HAMMER, SHOVEL = _mk_can(), _mk_hammer(), _mk_shovel()
BASKET, BOOK, PHOTO, FOODCAN, PENCIL = _mk_basket(), _mk_book(), _mk_photo(), _mk_foodcan(), _mk_pencil()
CM = {
    "b": "conc3", "h": "conc4", "B": "conc2", "D": "conc1", "r": "rust3", "k": "dark3",
    "w": "rust3", "W": "rust2", "R": "rust4", "p": "amber2", "q": "rust4", "P": "paper", "c": "rust2",
    "d": "rust1", "s": "conc3", "l": "leaf2", "a": "amber2", "A": "amber1", "i": "ink",
}
CM_FOODCAN = dict(CM, a="amber2", A="amber1")
CM_BASKET = dict(CM, p="amber1", q="rust4", h="amber3", D="rust1")
CM_SHOVEL = dict(CM, w="rust3", W="rust2")


# ---------------------------------------------------------------- renderização
def boot(cv, ax, ay, kind="flat", far=False):
    """Bota de 4x2, ponta para a direita; (ax, ay) = canto sup. esq."""
    mat = "boot_far" if far else "boot"
    ax, ay = int(round(ax)), int(round(ay))
    if kind == "flat":
        m = {(ax + i, ay + j) for i in range(4) for j in range(2)}
    elif kind == "toe":  # calcanhar levantado
        m = {(ax, ay), (ax + 1, ay), (ax + 1, ay + 1), (ax + 2, ay + 1), (ax + 3, ay + 1), (ax + 2, ay)}
    elif kind == "up":  # ponta levantada
        m = {(ax, ay + 1), (ax + 1, ay + 1), (ax + 2, ay + 1), (ax + 2, ay), (ax + 3, ay), (ax, ay)}
    else:
        raise ValueError(kind)
    paint(cv, m, mat)
    return m


def ik(root, target, a, b, bend):
    """IK de dois ossos. bend: lado para onde o joelho/cotovelo aponta (fwd/back/down/up)."""
    rx, ry = root
    tx, ty = target
    dx, dy = tx - rx, ty - ry
    dist = math.hypot(dx, dy)
    d = max(abs(a - b) + 0.01, min(a + b - 0.01, dist))
    ux, uy = (dx / dist, dy / dist) if dist > 0 else (1.0, 0.0)
    x = (a * a - b * b + d * d) / (2 * d)
    h = math.sqrt(max(0.0, a * a - x * x))
    bx, by = rx + ux * x, ry + uy * x
    cands = [(bx - uy * h, by + ux * h), (bx + uy * h, by - ux * h)]
    key = {"fwd": lambda p: p[0], "back": lambda p: -p[0], "down": lambda p: p[1], "up": lambda p: -p[1]}[bend]
    knee = max(cands, key=key)
    return knee, (rx + ux * d, ry + uy * d)


def torso_details(cv, hip, sh, belly=1):
    ux, uy = sh[0] - hip[0], sh[1] - hip[1]
    L = math.hypot(ux, uy)
    ux, uy = ux / L, uy / L
    lo = (hip[0] + ux * 1.5, hip[1] + uy * 1.5)
    fx, fy = -uy * belly, ux * belly

    def at(t, q):
        return lo[0] + (sh[0] - lo[0]) * t + fx * q, lo[1] + (sh[1] - lo[1]) * t + fy * q

    for q in (-2, -1, 0, 1, 2):
        x, y = at(0.1, q)
        if (int(math.floor(x)), int(math.floor(y))) in cv.p:
            cv.put(x, y, "dark1")
    x, y = at(0.1, 2)
    cv.put(x, y, "amber2")           # fivela
    x, y = at(1.0, 1.5)
    cv.put(x, y, "skin1")            # gola aberta
    for q in (1.2, 2.2):
        x, y = at(0.7, q)
        cv.put(x, y, "cloth1")       # bolso
    x, y = at(0.45, 0.5)
    cv.put(x, y, "cloth1")           # prega


DARKS = {"ink"}


def outline(cv):
    """Contorno externo de 1 px: ink em geral; dark1 em volta da calça (mais leve para as pernas lerem)."""
    add = {}
    for (x, y), c in cv.p.items():
        if c in DARKS:
            continue
        oc = "dark1" if cv.mat.get((x, y), "").startswith("pants") else "ink"
        for (nx, ny) in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if (nx, ny) not in cv.p and 0 <= nx < S and 0 <= ny < S:
                if add.get((nx, ny)) != "ink":
                    add[(nx, ny)] = oc
    cv.p.update(add)


def render(P):
    """Desenha uma pose. Chaves de P: hip, sh, head=(ox,oy,modo,olhos), nl/fl (tornozelo), nlk/flk (bota),
    nlb/flb (joelho), na/fa (mão), nab/fab (cotovelo), belly, props_back/far/mid/front = [f(cv, pts)]."""
    cv = Cv()
    pts = {}
    hip, sh = P["hip"], P["sh"]
    legs, arms = {}, {}
    for side in ("fl", "nl"):
        if side in P:
            root = (hip[0] + (0.4 if side == "nl" else -0.4), hip[1] + 0.5)
            legs[side] = ik(root, P[side], THIGH, SHIN, P.get(side + "b", "fwd"))
    for side in ("fa", "na"):
        if side in P:
            s0 = (sh[0] + (0.3 if side == "na" else -0.7), sh[1] - 0.8)
            elb, end = ik(s0, P[side], UARM, FARM, P.get(side + "b", "back"))
            arms[side] = (s0, elb, end)
            pts[side] = end
    for k in ("nl", "fl"):
        if k in legs:
            pts[k] = legs[k][1]
    for f in P.get("props_back", []):
        f(cv, pts)
    if "fa" in arms:
        s0, elb, end = arms["fa"]
        paint(cv, capsule(s0, elb, 1.2), "sleeve_far")
        paint(cv, capsule(elb, end, 1.0), "skin_far")
        paint(cv, capsule(end, end, 1.1), "skin_far")
    for f in P.get("props_far", []):
        f(cv, pts)
    if "fl" in legs:
        knee, end = legs["fl"]
        paint(cv, capsule((hip[0] - 0.4, hip[1] + 0.5), knee, 1.4, 1.3), "pants_far")
        paint(cv, capsule(knee, end, 1.3, 1.1), "pants_far")
        boot(cv, end[0] - 1.5, end[1] - 0.2 - P.get("flh", 0), P.get("flk", "flat"), far=True)
    ux, uy = sh[0] - hip[0], sh[1] - hip[1]
    ul = math.hypot(ux, uy)
    lo = (hip[0] + ux / ul * 1.5, hip[1] + uy / ul * 1.5)
    paint(cv, capsule(lo, sh, 3.0, 3.4), "shirt")
    torso_details(cv, hip, sh, P.get("belly", 1))
    if "nl" in legs:
        knee, end = legs["nl"]
        paint(cv, capsule((hip[0] + 0.4, hip[1] + 0.5), knee, 1.5, 1.4), "pants", edge={"dark3", "conc1"})
        paint(cv, capsule(knee, end, 1.4, 1.2), "pants", edge={"dark3", "conc1"})
        boot(cv, end[0] - 1.5, end[1] - 0.2 - P.get("nlh", 0), P.get("nlk", "flat"))
    hx, hy, hm, he = P["head"]
    if P.get("neck", True):
        paint(cv, capsule((sh[0] + 0.5, sh[1] - 1.5), (hx + 5, hy + 8), 1.4), "skin")
    draw_head(cv, hx, hy, hm, he)
    for f in P.get("props_mid", []):
        f(cv, pts)
    if "na" in arms:
        s0, elb, end = arms["na"]
        paint(cv, capsule(s0, elb, 1.3), "sleeve")
        paint(cv, capsule(elb, end, 1.0), "skin")
        paint(cv, capsule(end, end, 1.1), "skin")
    for f in P.get("props_front", []):
        f(cv, pts)
    outline(cv)
    return cv


# ---------------------------------------------------------------- poses
def torso_pts(hx, hy, lean=0.0, spine=4.5, dy=0.0):
    """Quadril (raiz das pernas), ombro e origem da cabeça de pé/inclinado."""
    a = math.radians(lean)
    sh = (hx + 0.5 + spine * math.sin(a), hy - spine * math.cos(a) + dy)
    return (hx, hy), sh


def head_for(sh, dx=0.0, dy=0.0, mode="fwd", eyes="open"):
    return (int(round(sh[0] - 4.5 + dx)), int(round(sh[1] - 13.5 + dy)), mode, eyes)


def idle(i):
    br = [0, 0, 1, 1][i]
    hip, sh = torso_pts(15, 21.0, 0, dy=br * 0.6)
    return dict(
        hip=hip, sh=sh, head=head_for(sh, 0, br * 0.4, "fwd", "closed" if i == 3 else "open"),
        nl=(17.5, FLOOR), fl=(14.0, FLOOR), na=(15.5 + (0.5 if i == 1 else 0), 23 - (br * 0.3)), fa=(14, 22.5),
    )


def _foot(j, A, lift):
    """Trajetória do pé no ciclo de 6 quadros: (dx, elevação, tipo de bota)."""
    return [
        (A, 0, "up"), (0, 0, "flat"), (-A, 0, "toe"),
        (-A, lift * 0.5, "toe"), (0, lift, "flat"), (A, lift * 0.5, "up"),
    ][j % 6]


def walk(i, A=3.0, lift=2.6, carry=False):
    bob = [0.7, -0.3, 0.2, 0.7, -0.3, 0.2][i]
    hip, sh = torso_pts(15, 21.0 + bob, -4 if carry else 4)
    dn, hn, kn = _foot(i, A, lift)
    df, hf, kf = _foot(i + 3, A, lift)
    P = dict(
        hip=hip, sh=sh, head=head_for(sh, 0.5, 0, "fwd"),
        nl=(16 + dn, FLOOR - hn), nlk=kn, nlh=0, fl=(15 + df, FLOOR - hf), flk=kf,
    )
    if not carry:
        k = 0.8
        P.update(na=(16 - k * dn + 0.5, 22.6 - max(0, -dn) * 0.2), fa=(15 + k * dn, 22.6 - max(0, dn) * 0.2),
                 nab="back", fab="back")
    return P


def carry(i):
    P = walk(i, A=2.0, lift=2.2, carry=True)
    bob = [0.7, -0.3, 0.2, 0.7, -0.3, 0.2][i]
    by = 17.5 + bob * 1.2
    bx = 19.5
    P["head"] = head_for(P["sh"], 0.0, 0, "fwd")
    P["na"] = (bx + 3.5, by + 5.0)
    P["fa"] = (bx + 5.5, by + 4.5)
    P["nab"] = "down"
    P["fab"] = "down"

    def basket_mid(cv, pts, bx=bx, by=by):
        stamp(cv, BASKET, CM_BASKET, (0, 0), (bx, by))
    P["props_mid"] = [basket_mid]
    return P


def crouch(i):
    hip, sh = torso_pts(12.5, 26.8, 48)
    P = dict(
        hip=hip, sh=sh, head=head_for(sh, 1.5, 0, "down"),
        nl=(17.0, FLOOR), fl=(15.0, FLOOR),
        na=[(22.0, 28.4), (22.5, 29.6), (21.0, 27.0), (22.3, 28.8)][i],
        fa=[(20.5, 28.0), (21.0, 28.4), (20.5, 28.2), (20.8, 28.2)][i],
        nab="back", fab="back",
    )

    def soil(cv, pts, i=i):
        hx, hy = pts["na"]
        if i in (1, 3):
            cv.pix([(hx + 1.5, 30), (hx + 2.5, 30), (hx + 2.5, 29), (hx + 3.5, 30), (hx - 0.5, 30)], "rust2")
            cv.pix([(hx + 1.5, 31), (hx + 2.5, 31)], "rust1")
        if i == 2:
            cv.pix([(hx + 1.0, hy - 1.0), (hx + 1.0, hy - 2.0)], "leaf2")
            cv.pix([(hx + 2.0, hy - 3.0), (hx + 0.0, hy - 3.0), (hx + 1.0, hy - 3.0)], "leaf3")
            cv.pix([(hx + 1.0, hy - 0.2), (hx + 0.0, hy + 0.8)], "rust2")
        if i == 3:
            cv.pix([(hx + 3.0, 29.0), (hx + 3.0, 28.0)], "leaf2")
            cv.pix([(hx + 2.0, 27.0), (hx + 4.0, 27.0), (hx + 3.0, 27.0)], "leaf3")
    P["props_front"] = [soil]
    return P


def water(i):
    tilt = [0, 16, 32, 16][i]
    hip, sh = torso_pts(14.5, 21.0, 8)
    hand = (20.4, 17.2 + [0, 0, 0.4, 0][i])
    P = dict(
        hip=hip, sh=sh, head=head_for(sh, 1.0, 0.3, "down"),
        nl=(17.0, FLOOR), fl=(13.5, FLOOR), na=hand, fa=(13.0, 22.0), nab="back", fab="back",
    )

    def can(cv, pts, tilt=tilt, i=i):
        at = pts["na"]
        stamp(cv, CAN, CM, (4.5, 0.5), (at[0], at[1] - 0.5), tilt)
        if tilt >= 16:
            tip = xf((4.5, 0.5), (at[0], at[1] - 0.5), tilt, (13.2, 2.0))
            ph = (i * 1.7) % 3.4
            for k in range(4):
                x = tip[0] + 1.0 + k * (0.5 if tilt < 30 else 0.9)
                y = tip[1] + 1.2 + ph + k * 3.3 * 0.75
                if y < 31 and x < 30:
                    cv.put(x, y, "cloth2" if k % 2 == 0 else "paper")
                    if y + 1 < 31 and k < 3:
                        cv.put(x, y + 1, "cloth2")
            cv.put(tip[0] + 0.5, tip[1] + 0.5, "cloth2")
    P["props_front"] = [can]
    return P


def hammer(i):
    lean = [-3, 4, 9, 2][i]
    hip, sh = torso_pts(14.0, 21.0, lean)
    hand = [(23.2, 13.0), (23.0, 15.5), (22.5, 21.0), (23.2, 14.5)][i]
    ang = [-6, 55, 135, 28][i]
    P = dict(
        hip=hip, sh=sh, head=head_for(sh, 0.5 + lean * 0.12, 0, "down" if i == 2 else "fwd"),
        nl=(17.5, FLOOR), fl=(12.5, FLOOR), na=hand, fa=(14.5 + lean * 0.3, 22.5), nab="back", fab="back",
    )

    def hm(cv, pts, ang=ang):
        at = pts["na"]
        stamp(cv, HAMMER, CM, (2.5, 7.5), at, ang)
    P["props_front"] = [hm]
    return P


def dig(i):
    lean = [12, 6, -2, 8][i]
    hip, sh = torso_pts(13.0, 21.0, lean)
    hand = [(19.8, 22.3), (19.0, 19.8), (16.5, 18.0), (18.5, 20.8)][i]
    ang = [-28, -45, -80, -38][i]
    P = dict(
        hip=hip, sh=sh, head=head_for(sh, 1.0 + lean * 0.1, 0.5, "down" if i in (0, 3) else "fwd"),
        nl=(16.5, FLOOR), fl=(11.5, FLOOR), na=hand, nab="back", fab="back",
        fa=xf((2.5, 3.5), hand, ang, (2.5, 0.8)),
    )

    def sh_front(cv, pts, ang=ang, i=i):
        at = pts["na"]
        stamp(cv, SHOVEL, CM_SHOVEL, (2.5, 3.5), at, ang)
        tip = xf((2.5, 3.5), at, ang, (2.5, 10.0))
        if i == 1:
            cv.pix([(tip[0] - 0.5, tip[1] - 1.5), (tip[0] + 0.5, tip[1] - 1.5), (tip[0], tip[1] - 2.5),
                    (tip[0] - 1.5, tip[1] - 1.0)], "rust2")
        if i == 2:
            cv.pix([(tip[0] + 2, tip[1] - 3), (tip[0] + 3, tip[1] - 4), (tip[0] + 4, tip[1] - 3),
                    (tip[0] + 3, tip[1] - 2)], "rust2")
            cv.pix([(tip[0] + 1, tip[1] - 1)], "rust1")
        if i in (0, 3):
            cv.pix([(tip[0] + 2, 30), (tip[0] + 3, 30), (tip[0] + 3, 29), (tip[0] - 2, 30)], "rust2")
    P["props_front"] = [sh_front]
    return P


def pedal(i):
    hip, sh = torso_pts(13.0, 20.8, 9)
    C = (17.0, 25.0)
    th = math.radians(i * 90)
    nf = (C[0] + 3.2 * math.cos(th), C[1] + 3.2 * math.sin(th))
    ff = (C[0] - 3.2 * math.cos(th), C[1] - 3.2 * math.sin(th))
    return dict(
        hip=hip, sh=sh, head=head_for(sh, 1.0, 0.3 + (i % 2) * 0.3, "fwd"),
        nl=nf, fl=ff, na=(21.2, 19.4 + (i % 2) * 0.3), fa=(20.6, 19.0), nab="down", fab="down",
    )


def sleep(i):
    ox = 2
    hip, sh = (9.0 + ox, 23.0), (13.8 + ox, 23.0)
    P = dict(
        hip=hip, sh=sh, head=(int(round(sh[0] + 1.5)), 16, "lie", "closed"),
        nl=(2.0 + ox, 24.5), fl=(2.0 + ox, 23.5), nlk="flat", flk="flat", nlb="up", flb="up",
        na=(11.0 + ox, 21.0), nab="down", belly=-1, neck=False,
    )

    def blanket(cv, pts, i=i):
        for x in range(0, 15):
            top = 21
            if 4 <= x <= 9:
                top = 19
            elif x >= 10:
                top = 20 - (1 if i == 1 else 0)
            if x in (0, 1):
                top += 2 - x
            for y in range(top, 26):
                c = "rust2"
                if y == top:
                    c = "rust4"
                elif y == top + 1:
                    c = "rust3"
                elif y >= 25:
                    c = "rust1"
                cv.put(x + ox, y, c)
        for x in range(1, 15):
            if x % 4 in (0, 1):
                cv.put(x + ox, 23, "amber1")
        cv.pix([(14 + ox, 22), (14 + ox, 21)], "rust1")
    P["props_mid"] = [blanket]
    return P


SIT_HIP = (13.5, 25.6)


def _sit_legs():
    return dict(nl=(19.5, FLOOR), fl=(17.5, FLOOR))


def sit_read(i):
    hip, sh = torso_pts(SIT_HIP[0], SIT_HIP[1], -5)
    dyh = [0, 0.6, 0, 0.3][i]
    P = dict(hip=hip, sh=sh, head=head_for(sh, 1.0, 0.5 + dyh, "down"), **_sit_legs())
    hand = [(19.8, 21.0), (19.8, 21.3), (19.8, 21.0), (19.8, 21.2)][i]
    P.update(na=hand, fa=(19.0, 21.4), nab="down", fab="down")

    def book(cv, pts, i=i):
        at = pts["na"]
        stamp(cv, BOOK, CM, (1.0, 4.5), (at[0] + 0.5, at[1] + 0.5), -18)
        if i == 2:
            cv.pix([(at[0] + 1.5, at[1] - 4.5), (at[0] + 2.5, at[1] - 5.5), (at[0] + 3.5, at[1] - 5.5)], "paper")
        if i == 3:
            cv.pix([(at[0] + 3.5, at[1] - 4.0), (at[0] + 3.5, at[1] - 3.0)], "paper")
    P["props_mid"] = [book]
    return P


def sit_listen(i):
    hip, sh = torso_pts(SIT_HIP[0], SIT_HIP[1], 24)
    dyh = [0, 0.5, 0, 0.5][i]
    hd = head_for(sh, 2.0, 0.6 + dyh, "fwd")
    P = dict(hip=hip, sh=sh, head=hd, **_sit_legs())
    P.update(na=(hd[0] + 6.2, hd[1] + 10.4 + dyh * 0.5), nab="down", fa=(19.8, 24.6), fab="down")
    return P


def nap(i):
    hip, sh = torso_pts(SIT_HIP[0], SIT_HIP[1], -9, dy=0.0 + i * 0.5)
    P = dict(hip=hip, sh=sh, head=head_for(sh, 0.0, 3.2 + i * 0.4, "down", "closed"), **_sit_legs())
    P.update(na=(17.0, 23.0 + i * 0.4), nab="down", fa=(18.5, 23.5), fab="down")
    return P


def write(i):
    hip, sh = torso_pts(13.5, 21.0, 12)
    wx = [23.5, 24.5, 24.0, 25.0][i]
    wy = [22.8, 22.3, 22.6, 22.2][i]
    P = dict(
        hip=hip, sh=sh, head=head_for(sh, 1.5, 0.5 + (i % 2) * 0.3, "down"),
        nl=(16.5, FLOOR), fl=(13.0, FLOOR), na=(wx, wy), nab="down", fa=(21.5, 22.8), fab="down",
    )

    def pencil(cv, pts):
        at = pts["na"]
        stamp(cv, PENCIL, CM, (0.5, 0.5), (at[0] + 0.5, at[1] - 0.2), 55)
    P["props_front"] = [pencil]
    return P


def photo(i):
    hip, sh = torso_pts(14.0, 21.0, 3, dy=0.6 * i)
    P = dict(
        hip=hip, sh=sh, head=head_for(sh, 1.0, 0.8 + i * 0.6, "down"),
        nl=(17.0, FLOOR), fl=(13.5, FLOOR), na=(20.8, 19.5 + 0.6 * i), nab="down", fa=(19.5, 20.2 + 0.6 * i), fab="down",
    )

    def ph(cv, pts):
        at = pts["na"]
        stamp(cv, PHOTO, CM, (1.5, 5.0), (at[0] + 0.5, at[1] - 0.3), -8)
    P["props_mid"] = [ph]
    return P


def eat(i):
    hip, sh = torso_pts(14.0, 21.0, 4, dy=[0, 0, 0, 0.5][i])
    hand = [(22.6, 17.2), (22.4, 14.6), (21.8, 12.2), (22.2, 14.0)][i]
    fang = [95, 140, 172, 150][i]
    P = dict(
        hip=hip, sh=sh, head=head_for(sh, 1.0, [0, 0, 0, 0.8][i], "fwd", "open"),
        nl=(17.0, FLOOR), fl=(13.5, FLOOR), na=hand, nab="down", fa=(20.0, 21.5), fab="down",
    )

    def foodcan(cv, pts):
        stamp(cv, FOODCAN, CM_FOODCAN, (2.0, 2.5), (20.0, 19.5), 0)

    def fork(cv, pts, fang=fang):
        at = pts["na"]
        stamp(cv, PENCIL, dict(CM, r="conc3", a="conc3", i="conc4"), (0.5, 0.5), (at[0] + 0.3, at[1]), fang)
    P["props_mid"] = [foodcan]
    P["props_front"] = [fork]
    return P


def look_up(i):
    hip, sh = torso_pts(14.0, 21.0, -5)
    P = dict(
        hip=hip, sh=sh, head=head_for(sh, -0.5, 0.0 - i * 0.0, "up"),
        nl=(17.0, FLOOR), fl=(13.0, FLOOR),
    )
    if i == 0:
        P.update(na=(15.0, 23.0), fa=(14.0, 22.5))
    else:
        P.update(na=(17.6, 18.8), nab="down", fa=(14.0, 22.5))
    return P


POSES = [
    ("man_idle", idle, 4, 3), ("man_walk", walk, 6, 8), ("man_carry", carry, 6, 8),
    ("man_crouch", crouch, 4, 4), ("man_water", water, 4, 5), ("man_hammer", hammer, 4, 6),
    ("man_dig", dig, 4, 6), ("man_pedal", pedal, 4, 8), ("man_sleep", sleep, 2, 1),
    ("man_sit_read", sit_read, 4, 2), ("man_sit_listen", sit_listen, 4, 2), ("man_nap", nap, 2, 1),
    ("man_write", write, 4, 4), ("man_photo", photo, 2, 1), ("man_eat", eat, 4, 4),
    ("man_look_up", look_up, 2, 1),
]


# ---------------------------------------------------------------- saída
SPEED = {"man_walk": 24.0, "man_carry": 16.0}  # px/s sem escorregar o pé (px por quadro x fps)


def build_strip(fn, n):
    frames = [render(fn(i)) for i in range(n)]
    strip = Image.new("RGBA", (S * n, S), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f.image(), (S * i, 0))
    return snap_image(strip), frames


def _label(draw, xy, text, fill=(233, 226, 208)):
    draw.text(xy, text, fill=fill, font=ImageFont.load_default())


def contact_sheet(all_frames, path, z=6, cols=8):
    flat = [(name, i, f) for name, frs in all_frames for i, f in enumerate(frs)]
    rows = (len(flat) + cols - 1) // cols
    cw = S * z + 6
    ch = S * z + 16
    bg = RGB["dark3"]
    sheet = Image.new("RGB", (cols * cw, rows * ch), bg)
    d = ImageDraw.Draw(sheet)
    for k, (name, i, f) in enumerate(flat):
        cx, cy = (k % cols) * cw, (k // cols) * ch
        d.rectangle([cx + 3, cy + 14, cx + 3 + S * z - 1, cy + 14 + S * z - 1], fill=RGB["conc1"])
        # linha do chão (y=32) e centro (x=16)
        d.line([cx + 3, cy + 14 + 31 * z + z, cx + 3 + S * z, cy + 14 + 31 * z + z], fill=RGB["dark2"], width=1)
        d.line([cx + 3 + 16 * z, cy + 14, cx + 3 + 16 * z, cy + 14 + S * z], fill=RGB["conc2"], width=1)
        a = f.image().resize((S * z, S * z), Image.NEAREST)
        sheet.paste(a, (cx + 3, cy + 14), a)
        _label(d, (cx + 3, cy + 1), f"{name[4:]} {i}")
    snap_image(sheet).save(path)


def preview_anim(all_frames, path, z=4):
    cols = 2
    cw = S * z * 6 + 12
    ch = S * z + 16
    rows = (len(all_frames) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cw, rows * ch), RGB["dark3"])
    d = ImageDraw.Draw(sheet)
    for k, (name, frs) in enumerate(all_frames):
        cx, cy = (k % cols) * cw, (k // cols) * ch
        _label(d, (cx + 4, cy + 2), name)
        d.rectangle([cx + 4, cy + 14, cx + 4 + S * z * len(frs) - 1, cy + 14 + S * z - 1], fill=RGB["conc1"])
        for i, f in enumerate(frs):
            a = f.image().resize((S * z, S * z), Image.NEAREST)
            sheet.paste(a, (cx + 4 + i * S * z, cy + 14), a)
    snap_image(sheet).save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {}
    allf = []
    problems = []
    for name, fn, n, fps in POSES:
        strip, frames = build_strip(fn, n)
        path = os.path.join(OUT, name + ".png")
        strip.save(path)
        allf.append((name, frames))
        entry = {"file": "man/%s.png" % name, "frame_w": S, "frame_h": S, "frames": n, "fps": fps,
                 "anchor": [16, 31]}
        if name in SPEED:
            entry["speed_px_s"] = SPEED[name]
        manifest[name] = entry
        bad = check_image(path)
        if bad:
            problems.append((name, bad))
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    contact_sheet(allf, os.path.join(OUT, "_contact_man.png"))
    preview_anim(allf, os.path.join(OUT, "_preview_man_anim.png"))
    for fn_ in ("_contact_man.png", "_preview_man_anim.png"):
        bad = check_image(os.path.join(OUT, fn_))
        if bad:
            problems.append((fn_, bad))
    print("OK" if not problems else "PROBLEMAS: %r" % problems)


if __name__ == "__main__":
    main()
