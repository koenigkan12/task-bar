#!/usr/bin/env python3
"""Gera toda a arte pixel original da vila (Pillow puro, determinístico).

Uso: python3 vila/tools/gerar_arte.py
Saída: vila/assets/art/*.png e vila/tools/preview.png / preview_3x.png
"""
import math
import os
import random

from PIL import Image

AQUI = os.path.dirname(os.path.abspath(__file__))
SAIDA = os.path.normpath(os.path.join(AQUI, '..', 'assets', 'art'))
SEED = 1337

# ---------------------------------------------------------------- paleta
OUT = '#0d0b10'
# corpos escuros azul/teal
D0, D1, D2, D3, D4 = '#141a22', '#1d2630', '#26323c', '#34444e', '#4a5e66'
# ferrugem / marrons escuros
R0, R1, R2, R3, R4 = '#2b1c1c', '#3a2622', '#5a3226', '#7a4430', '#9a5a3a'
# madeira
W0, W1, W2, W3, W4 = '#2a1c1c', '#3e2a24', '#56382a', '#744c34', '#946644'
# pedra mauve
S0, S1, S2, S3 = '#2e2630', '#3e3440', '#544652', '#6c5c68'
# aço
ST0, ST1, ST2, ST3 = '#3a4450', '#56626e', '#7a8894', '#a8b4bc'
# acentos
CY, CY2, CYD = '#6fe3d8', '#3fb8c9', '#1f5f6a'
PK, PK2, PKD = '#f08ce0', '#c45bc0', '#5e2a62'
OR, YE, OR2, ORD = '#ffb347', '#ffd36b', '#e2622b', '#8a3a1e'
WH = '#fff3c8'
RED = '#d8423a'
# chão
G0, G1, G2, G3 = '#463439', '#4e3a3f', '#5a4448', '#644e50'
P0, P1, P2 = '#533f40', '#5c4645', '#67504d'
# vegetação seca
GR0, GR1, GR2, GR3 = '#3a3a2c', '#5a5a3a', '#6e6c44', '#4e6e62'
TEAL_GR = '#3e5a52'
# copa escura das árvores
T0, T1, T2, T3 = '#162224', '#1f3032', '#2b4442', '#3f6458'
# plantas da horta
PL0, PL1, PL2, PL3 = '#24463a', '#3b7458', '#5aa070', '#8fd08a'
SOIL0, SOIL1, SOIL2 = '#22181b', '#2e2024', '#3e2c2c'

SHADOW = (0, 0, 0, 90)

_cache = {}


def hx(c):
    if c is None:
        return None
    if isinstance(c, tuple):
        return c if len(c) == 4 else c + (255,)
    if c in _cache:
        return _cache[c]
    s = c.lstrip('#')
    v = (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16),
         255 if len(s) == 6 else int(s[6:8], 16))
    _cache[c] = v
    return v


class Lay:
    """Camada RGBA com primitivas de pixel (sem antialias)."""

    def __init__(s, w, h):
        s.w, s.h = w, h
        s.im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        s.px = s.im.load()

    def p(s, x, y, c):
        if c is None:
            return
        x, y = int(x), int(y)
        if 0 <= x < s.w and 0 <= y < s.h:
            s.px[x, y] = hx(c)

    def a(s, x, y):
        if 0 <= x < s.w and 0 <= y < s.h:
            return s.px[x, y][3]
        return 0

    def rect(s, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                s.p(x, y, c)

    def hl(s, x0, x1, y, c):
        s.rect(x0, y, x1, y, c)

    def vl(s, x, y0, y1, c):
        s.rect(x, y0, x, y1, c)

    def line(s, x0, y0, x1, y1, c):
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
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

    def ell(s, cx, cy, rx, ry, c):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1:
                    s.p(x, y, c)

    def box(s, x0, y0, x1, y1, base, lt=None, dk=None):
        s.rect(x0, y0, x1, y1, base)
        if dk:
            s.hl(x0, x1, y1, dk)
            s.vl(x1, y0, y1, dk)
        if lt:
            s.hl(x0, x1, y0, lt)
            s.vl(x0, y0, y1, lt)

    def corr(s, x0, y0, x1, y1, ca, cb, rim=None, bot=None, per=2):
        """Chapa corrugada vertical."""
        for x in range(x0, x1 + 1):
            c = ca if ((x - x0) % per) == 0 else cb
            s.vl(x, y0, y1, c)
        if rim:
            s.hl(x0, x1, y0, rim)
        if bot:
            s.hl(x0, x1, y1, bot)

    def planks(s, x0, y0, x1, y1, cols, ph=3, seam=None, rng=None):
        """Tábuas horizontais."""
        rng = rng or random.Random(5)
        i = 0
        for y in range(y0, y1 + 1, ph):
            c = cols[i % len(cols)]
            s.rect(x0, y, x1, min(y + ph - 1, y1), c)
            if seam:
                s.hl(x0, x1, min(y + ph - 1, y1), seam)
                jx = rng.randint(x0 + 2, max(x0 + 2, x1 - 2))
                s.vl(jx, y, min(y + ph - 2, y1), seam)
            i += 1

    def blit(s, other, ox, oy):
        s.im.alpha_composite(other if isinstance(other, Image.Image) else other.im, (ox, oy))
        s.px = s.im.load()


def outline(im, col=OUT):
    w, h = im.size
    src = im.load()
    res = im.copy()
    dst = res.load()
    oc = hx(col)
    for y in range(h):
        for x in range(w):
            if src[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 0:
                        dst[x, y] = oc
                        break
    return res


def finish(body, fx=None, drop=(1, 1), shadows=(), do_outline=True):
    """Contorno + sombra (silhueta deslocada + elipses/retângulos) + camada fx."""
    w, h = body.w, body.h
    b = outline(body.im) if do_outline else body.im.copy()
    bp = b.load()
    sh = Lay(w, h)
    if drop:
        dx, dy = drop
        for y in range(h):
            for x in range(w):
                if bp[x, y][3] > 0:
                    sh.p(x + dx, y + dy, SHADOW)
    for sd in shadows:
        if sd[0] == 'e':
            sh.ell(sd[1], sd[2], sd[3], sd[4], SHADOW)
        else:
            sh.rect(sd[1], sd[2], sd[3], sd[4], SHADOW)
    res = sh.im
    res.alpha_composite(b)
    if fx is not None:
        res.alpha_composite(fx.im)
    return res


def glow(L, x, y, core, mid, halo=None, big=False):
    """Luz em pixels duros: núcleo + halo de acento escuro."""
    if halo:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if L.a(x + dx, y + dy) == 0 or big:
                L.p(x + dx, y + dy, halo)
    L.p(x, y, core)
    if big:
        L.p(x + 1, y, mid)
        L.p(x, y + 1, mid)
        L.p(x + 1, y + 1, mid)


def window(L, x0, y0, x1, y1, frame=W0, cross=True):
    L.rect(x0 - 1, y0 - 1, x1 + 1, y1 + 1, frame)
    L.rect(x0, y0, x1, y1, OR)
    L.hl(x0, x1, y1, OR2)
    L.p(x0, y0, YE)
    L.p(x0 + 1, y0, YE)
    L.p(x0, y0 + 1, YE)
    if cross:
        mx = (x0 + x1) // 2
        L.vl(mx, y0, y1, frame)
        L.hl(x0, x1, (y0 + y1) // 2, frame)
    L.hl(x0 - 1, x1 + 1, y1 + 2, W2)  # parapeito


def save(im, name):
    im.save(os.path.join(SAIDA, name))


# ================================================================ chão
def ground():
    L = Lay(128, 32)

    def speck(ox, oy, seed, base, lt, dk, dl=.05, dd=.06, lt2=None):
        r = random.Random(seed)
        for y in range(16):
            for x in range(16):
                v = r.random()
                c = base
                if v < dl:
                    c = lt
                elif v < dl + dd:
                    c = dk
                L.p(ox + x, oy + y, c)
        # alguns traços horizontais suaves (dois pixels)
        for _ in range(3):
            x, y = r.randint(0, 14), r.randint(0, 15)
            c = r.choice([lt, dk])
            L.p(ox + x, oy + y, c)
            L.p(ox + x + 1, oy + y, c)
        if lt2:
            for _ in range(2):
                L.p(ox + r.randint(0, 15), oy + r.randint(0, 15), lt2)

    def pebble(ox, oy, x, y, big=False):
        L.p(ox + x, oy + y, S3)
        L.p(ox + x + 1, oy + y, S2)
        L.hl(ox + x, ox + x + 1, oy + y + 1, '#2a1f24')
        if big:
            L.p(ox + x - 1, oy + y, S2)
            L.p(ox + x, oy + y - 1, '#7c6a74')
            L.p(ox + x + 1, oy + y - 1, S3)
            L.hl(ox + x - 1, ox + x + 2, oy + y + 1, '#2a1f24')
            L.p(ox + x + 2, oy + y, S1)

    def tuft(ox, oy, x, y, cols, n=5, r=None):
        r = r or random.Random(x * 31 + y)
        L.hl(ox + x - 1, ox + x + 3, oy + y + 1, '#3a2a2e')
        blades = [(0, -2), (1, -3), (2, -2), (-1, -1), (3, -1), (1, -1), (2, -3)][:n]
        for bx, h in blades:
            c = r.choice(cols)
            for k in range(-h + 1):
                L.p(ox + x + bx, oy + y - k, c)
            L.p(ox + x + bx, oy + y + h, cols[-1] if r.random() < .5 else c)

    plain = [(G1, G2, G0)] * 4
    for i in range(4):
        speck(i * 16, 0, SEED + i, G1, G2, G0)
    # col 4: pedrinhas
    speck(64, 0, SEED + 4, G1, G2, G0)
    pebble(64, 0, 4, 5, True)
    pebble(64, 0, 10, 10)
    pebble(64, 0, 7, 12)
    pebble(64, 0, 12, 3)
    # col 5: tufo de grama seca
    speck(80, 0, SEED + 5, G1, G2, G0)
    tuft(80, 0, 6, 9, [GR1, GR2, GR1, GR0], 7)
    # col 6: mancha escura
    speck(96, 0, SEED + 6, G1, G2, G0)
    r = random.Random(66)
    for y in range(3, 13):
        for x in range(2, 14):
            d = ((x - 7.5) / 5.5) ** 2 + ((y - 7.8) / 4.2) ** 2
            if d < 1 - r.random() * .35:
                L.p(96 + x, y, G0 if r.random() > .12 else '#3e2e33')
    # col 7: ossinhos / detritos
    speck(112, 0, SEED + 7, G1, G2, G0)
    bone, bone_d = '#b8a89a', '#7c6e66'
    L.hl(112 + 4, 112 + 8, 6, bone)
    L.p(112 + 3, 5, bone)
    L.p(112 + 3, 7, bone)
    L.p(112 + 9, 5, bone)
    L.p(112 + 9, 7, bone)
    L.hl(112 + 4, 112 + 8, 7, bone_d)
    L.p(112 + 10, 11, R3)
    L.p(112 + 11, 11, R2)
    L.p(112 + 11, 12, R1)
    L.p(112 + 10, 12, '#2a1f24')
    L.p(112 + 5, 12, ST1)
    L.p(112 + 6, 12, ST0)
    # linha 1: caminho batido
    for i in range(4):
        speck(i * 16, 16, SEED + 20 + i, P1, P2, P0, .06, .05)
    # col 4: chão limpo/achatado
    r = random.Random(77)
    for y in range(16):
        for x in range(16):
            v = r.random()
            L.p(64 + x, 16 + y, '#524040' if v > .05 else '#5a4646')
    for y in (4, 9, 13):
        for x in range(16):
            if r.random() < .3:
                L.p(64 + x, 16 + y, '#4c3a3c')
    # col 5..7: mais tufos
    speck(80, 16, SEED + 30, G1, G2, G0)
    tuft(80, 16, 5, 8, [TEAL_GR, GR3, TEAL_GR, '#2e423c'], 6)
    tuft(80, 16, 11, 13, [GR1, GR2], 3)
    speck(96, 16, SEED + 31, G1, G2, G0)
    tuft(96, 16, 9, 10, [GR2, GR1, '#7c784c', GR0], 7)
    speck(112, 16, SEED + 32, G1, G2, G0)
    tuft(112, 16, 4, 6, [GR1, GR3, GR0], 4)
    tuft(112, 16, 10, 12, [GR3, TEAL_GR, '#2e423c'], 5)
    pebble(112, 16, 12, 4)
    save(L.im, 'ground.png')
    return L.im


# ================================================================ árvores
def trees():
    sheet = Image.new('RGBA', (64, 32))
    # 0: árvore seca com copa escura
    L = Lay(16, 32)
    L.rect(7, 14, 8, 29, R1)
    L.vl(7, 14, 29, R2)
    L.p(6, 29, R1)
    L.p(9, 29, R1)
    L.p(5, 30, R0)
    L.p(10, 30, R0)
    L.hl(6, 9, 30, R0)
    L.line(7, 18, 3, 12, R1)
    L.line(8, 16, 12, 10, R1)
    L.line(7, 14, 6, 7, R1)
    for cx, cy, rx, ry in ((4, 10, 3.2, 2.6), (12, 8, 3.4, 2.8), (7.5, 5.5, 4.2, 3.2), (9.5, 11, 2.6, 2)):
        L.ell(cx, cy, rx, ry, T1)
    r = random.Random(3)
    for y in range(32):
        for x in range(16):
            if L.px[x, y][:3] == hx(T1)[:3]:
                if L.a(x, y - 1) == 0 or L.a(x - 1, y) == 0:
                    L.p(x, y, T2)
                elif L.a(x, y + 1) == 0 or L.a(x + 1, y) == 0:
                    L.p(x, y, T0)
                elif r.random() < .12:
                    L.p(x, y, T2)
    L.p(6, 3, T3)
    L.p(7, 3, T3)
    L.p(11, 6, T3)
    L.p(3, 8, T3)
    sheet.alpha_composite(finish(L, shadows=[('e', 8.5, 30.5, 6, 1.6)]), (0, 0))

    # 1: galhos nus retorcidos
    L = Lay(16, 32)
    L.rect(7, 16, 8, 29, R1)
    L.vl(7, 16, 29, R2)
    L.hl(5, 10, 30, R0)
    L.line(7, 22, 3, 17, R1)
    L.line(3, 17, 2, 13, R1)
    L.line(4, 18, 5, 14, R2)
    L.line(8, 19, 12, 15, R1)
    L.line(12, 15, 13, 10, R1)
    L.line(12, 15, 14, 14, R1)
    L.line(7, 16, 6, 9, R1)
    L.line(6, 9, 4, 6, R1)
    L.line(7, 12, 9, 6, R2)
    L.line(9, 6, 10, 3, R1)
    L.line(6, 9, 7, 5, R1)
    L.p(8, 21, R0)
    L.p(7, 25, R0)
    # trapo pendurado
    L.p(13, 11, PKD)
    L.p(13, 12, PK2)
    L.p(14, 12, PKD)
    sheet.alpha_composite(finish(L, shadows=[('e', 8.5, 30.5, 5, 1.4)]), (16, 0))

    # 2/3: pinheiro mirrado
    def pine(lean, tiers, top, seed):
        L = Lay(16, 32)
        L.rect(7, 24, 8, 29, R1)
        L.vl(7, 24, 29, R2)
        L.hl(6, 9, 30, R0)
        r = random.Random(seed)
        for (y0, y1, hw) in tiers:
            for y in range(y0, y1 + 1):
                t = (y - y0) / max(1, (y1 - y0))
                w = 1 + t * hw
                cx = 7.5 + lean * (1 - (y - top) / (30 - top))
                xl, xr = int(round(cx - w)), int(round(cx + w))
                for x in range(xl, xr + 1):
                    c = T1
                    if x <= xl + 1:
                        c = T2
                    if x >= xr - 1:
                        c = T0
                    if y == y1:
                        c = T0 if x > cx - 2 else T1
                    L.p(x, y, c)
                if t > .3 and r.random() < .6:
                    L.p(xl + 1, y, T3)
        sheet_im = finish(L, shadows=[('e', 8.5, 30.5, 5.5, 1.5)])
        return sheet_im

    sheet.alpha_composite(pine(0.6, [(4, 11, 3.2), (9, 18, 4.8), (15, 25, 6.0)], 4, 9), (32, 0))
    sheet.alpha_composite(pine(-1.2, [(9, 15, 3.0), (13, 21, 4.5), (18, 26, 5.6)], 9, 11), (48, 0))
    save(sheet, 'tree.png')
    return sheet


def stump():
    L = Lay(16, 16)
    L.rect(4, 8, 11, 12, R1)
    L.vl(4, 8, 12, R2)
    L.vl(5, 8, 12, R2)
    L.vl(10, 8, 12, R0)
    L.vl(11, 8, 12, R0)
    L.p(3, 12, R1)
    L.p(12, 12, R0)
    L.hl(3, 12, 13, R0)
    L.ell(8, 8, 4, 2.2, W3)
    L.ell(8, 8, 2.6, 1.3, W2)
    L.p(7, 8, W4)
    L.p(8, 8, W3)
    L.p(5, 7, W4)
    L.p(6, 6, W4)
    # lascas
    L.p(13, 13, W3)
    L.p(2, 14, W2)
    im = finish(L, shadows=[('e', 8.5, 13.5, 6, 1.6)])
    save(im, 'stump.png')
    return im


def rubble():
    sheet = Image.new('RGBA', (48, 16))
    # 0: chapas encostadas
    L = Lay(16, 16)
    fx = Lay(16, 16)
    L.rect(2, 9, 13, 13, D1)
    L.line(3, 4, 7, 13, D2)
    for y in range(4, 14):
        x = 3 + (y - 4) * 4 // 9
        L.rect(x, y, x + 4, y, D2 if y % 2 else D3)
    for y in range(6, 14):
        L.rect(8, y, 12, y, R2 if (y % 2) else R1)
    L.hl(8, 12, 6, R3)
    L.vl(12, 6, 13, R0)
    L.hl(2, 13, 13, D0)
    L.p(3, 11, ST1)
    L.p(10, 10, R3)
    glow(fx, 5, 6, CY, CY2)
    sheet.alpha_composite(finish(L, fx, shadows=[('e', 8.5, 13.5, 7, 1.8)]), (0, 0))
    # 1: pneus
    L = Lay(16, 16)
    fx = Lay(16, 16)
    for cy in (12, 9):
        L.ell(8, cy, 5, 2.2, '#16141a')
        L.ell(8, cy - .5, 5, 1.6, '#24222a')
        L.ell(8, cy - .6, 2.2, .9, OUT)
    L.p(5, 7, ST0)
    L.p(6, 7, ST0)
    L.rect(11, 3, 13, 7, R2)
    L.vl(11, 3, 7, R3)
    L.p(13, 7, R0)
    glow(fx, 4, 11, OR, OR2)
    sheet.alpha_composite(finish(L, fx, shadows=[('e', 8.5, 13.6, 7, 1.7)]), (16, 0))
    # 2: barril tombado + sucata
    L = Lay(16, 16)
    fx = Lay(16, 16)
    L.rect(3, 8, 10, 13, R2)
    L.hl(3, 10, 8, R3)
    L.hl(3, 10, 13, R0)
    L.vl(5, 8, 13, R1)
    L.vl(8, 8, 13, R1)
    L.ell(11.5, 10.5, 1.8, 3, R1)
    L.ell(11.5, 10.5, 1, 2, R0)
    L.p(11, 9, R3)
    L.rect(1, 11, 3, 13, ST0)
    L.p(1, 11, ST1)
    L.line(10, 4, 13, 7, ST1)
    L.p(14, 13, D3)
    L.p(13, 13, D2)
    glow(fx, 6, 10, CY, CY2)
    sheet.alpha_composite(finish(L, fx, shadows=[('e', 8.5, 13.6, 7, 1.7)]), (32, 0))
    save(sheet, 'rubble.png')
    return sheet


# ================================================================ escotilha
def hatch():
    L = Lay(32, 32)
    fx = Lay(32, 32)
    # laje de concreto
    L.rect(2, 7, 28, 28, S1)
    L.hl(2, 28, 7, S2)
    L.vl(2, 7, 28, S2)
    L.hl(2, 28, 28, S0)
    L.vl(28, 7, 28, S0)
    L.rect(2, 26, 28, 28, S0)  # borda frontal (espessura)
    L.hl(2, 28, 26, '#352c36')
    r = random.Random(12)
    for _ in range(18):
        L.p(r.randint(4, 26), r.randint(9, 24), r.choice([S0, S2]))
    # faixas de aviso
    for x in range(4, 27, 4):
        L.p(x, 25, ORD)
        L.p(x + 1, 25, ORD)
    # escotilha redonda
    L.ell(15.5, 16.5, 10, 7.5, D0)
    L.ell(15.5, 16, 9, 6.6, D2)
    L.ell(15.5, 16, 7.4, 5.2, D1)
    L.ell(15.5, 15.6, 7.4, 4.8, D2)
    L.ell(15.5, 15.6, 6.4, 4.0, D1)
    for i in range(10):
        a = i / 10 * 2 * math.pi
        x = 15.5 + math.cos(a) * 8.2
        y = 16 + math.sin(a) * 5.8
        L.p(int(x), int(y), D4)
    # volante
    L.ell(15.5, 15.5, 3.2, 2.2, ST0)
    L.ell(15.5, 15.5, 2.2, 1.3, D1)
    L.hl(12, 19, 15, ST1)
    L.vl(15, 13, 18, ST1)
    L.p(15, 15, ST3)
    L.hl(10, 14, 11, D3)
    # lampião num poste
    L.rect(25, 1, 26, 12, D1)
    L.vl(25, 1, 12, D3)
    L.rect(23, 1, 27, 2, D2)
    L.hl(23, 27, 1, D3)
    L.rect(23, 3, 25, 5, ORD)
    glow(fx, 24, 4, YE, OR)
    fx.p(23, 4, OR)
    fx.p(25, 4, OR)
    fx.p(24, 3, OR)
    fx.p(24, 5, OR2)
    # luz cyan de status
    glow(fx, 5, 10, CY, CY2, CYD)
    im = finish(L, fx, drop=(2, 1), shadows=[('r', 4, 29, 30, 30)])
    save(im, 'hatch.png')
    return im


# ================================================================ torre de rádio
def tower_base(L, fx, lvl):
    # laje de base 2x2 na parte de baixo
    L.rect(2, 45, 28, 60, S1)
    L.hl(2, 28, 45, S2)
    L.vl(2, 45, 60, S2)
    L.rect(2, 58, 28, 60, S0)
    L.vl(28, 45, 60, S0)
    r = random.Random(40 + lvl)
    for _ in range(14):
        L.p(r.randint(4, 26), r.randint(47, 56), r.choice([S0, S2]))
    # cabine de equipamento
    L.rect(4, 47, 12, 56, D1)
    L.hl(4, 12, 47, D3)
    L.vl(4, 47, 56, D2)
    L.vl(12, 47, 56, D0)
    L.rect(3, 45, 13, 46, D2)
    L.hl(3, 13, 45, D3)
    L.rect(6, 50, 10, 52, D0)
    glow(fx, 7, 51, CY if lvl > 1 else CY2, CY2)
    if lvl >= 2:
        glow(fx, 9, 51, PK, PK2)
    L.p(6, 54, ST1)
    L.p(8, 54, ST1)


def lattice(L, xb0, xb1, yb, xt0, xt1, yt, step, c=R2, cd=R1, cl=R3):
    L.line(xb0, yb, xt0, yt, cl)
    L.line(xb1, yb, xt1, yt, cd)
    y = yb
    flip = False
    while y - step >= yt:
        t0 = (yb - y) / (yb - yt)
        t1 = (yb - (y - step)) / (yb - yt)
        xl0 = round(xb0 + (xt0 - xb0) * t0)
        xr0 = round(xb1 + (xt1 - xb1) * t0)
        xl1 = round(xb0 + (xt0 - xb0) * t1)
        xr1 = round(xb1 + (xt1 - xb1) * t1)
        L.hl(xl0, xr0, y, c)
        if flip:
            L.line(xl0, y, xr1, y - step, cd)
        else:
            L.line(xr0, y, xl1, y - step, cd)
        flip = not flip
        y -= step
    L.hl(round(xt0), round(xt1), yt, cl)


def dish(L, cx, cy, rx, ry, facing=1):
    L.ell(cx, cy, rx, ry, D4)
    L.ell(cx + facing * .8, cy, rx - .6, ry - .8, D1)
    L.ell(cx + facing * 1.2, cy, rx - 1.6, ry - 1.8, D2)
    L.p(int(cx - facing * (rx - 1)), int(cy - ry + 2), ST2)
    L.line(int(cx), int(cy), int(cx + facing * (rx + 1)), int(cy), ST1)
    L.p(int(cx + facing * (rx + 1)), int(cy), ST2)


def crystal(L, fx, x0, y0, heights, main, mid, dark, seed):
    """Blocos de néon empilhados (barras de alturas variadas)."""
    r = random.Random(seed)
    for i, hgt in enumerate(heights):
        x = x0 + i
        for k in range(hgt):
            y = y0 - k
            v = r.random()
            if v < .12:
                continue
            c = mid if v < .55 else main
            if k == hgt - 1:
                c = main
            fx.p(x, y, c)
        if r.random() < .5:
            fx.p(x, y0 - hgt - 1 - r.randint(0, 2), mid)
    # base escura
    for i in range(len(heights)):
        fx.p(x0 + i, y0 + 1, dark)


def tower(lvl):
    L = Lay(32, 64)
    fx = Lay(32, 64)
    tower_base(L, fx, lvl)
    if lvl == 1:
        # mastro curto enferrujado
        L.rect(17, 22, 18, 56, R2)
        L.vl(17, 22, 56, R3)
        for y in range(26, 56, 6):
            L.hl(16, 19, y, R1)
        L.rect(15, 54, 20, 57, R1)
        L.hl(15, 20, 54, R3)
        L.rect(16, 18, 19, 22, D2)
        L.hl(16, 19, 18, D3)
        L.vl(19, 18, 22, D0)
        L.vl(18, 12, 17, ST1)
        L.p(18, 11, ST2)
        # remendo de pano
        L.rect(19, 30, 20, 33, PKD)
        # fios (sem contorno)
        for (ax, ay) in ((4, 57), (27, 57), (27, 46)):
            fx.line(18, 24, ax, ay, '#1a1218')
        fx.line(12, 49, 17, 40, '#1a1218')
        glow(fx, 18, 10, CY2, CY2, CYD)
        fx.p(18, 10, '#5fb0b4')
    elif lvl == 2:
        lattice(L, 13, 23, 57, 16, 20, 12, 5)
        L.rect(16, 8, 20, 12, D2)
        L.hl(16, 20, 8, D3)
        L.vl(20, 8, 12, D0)
        L.vl(18, 1, 7, ST1)
        L.vl(17, 3, 7, ST0)
        dish(L, 12, 22, 3, 4, 1)
        L.rect(15, 21, 17, 22, D2)
        dish(L, 24, 34, 3, 4, -1)
        for (ax, ay) in ((3, 58), (28, 58)):
            fx.line(18, 14, ax, ay, '#1a1218')
        glow(fx, 18, 1, CY, CY2, CYD)
        glow(fx, 21, 10, PK, PK2, PKD)
        glow(fx, 15, 30, CY, CY2, CYD)
        glow(fx, 22, 44, PK, PK2, PKD)
        crystal(fx, fx, 15, 56, [2, 3, 1, 2], CY, CY2, CYD, 71)
    else:
        lattice(L, 11, 25, 57, 16, 20, 6, 4)
        L.rect(15, 4, 21, 8, D2)
        L.hl(15, 21, 4, D3)
        L.vl(21, 4, 8, D0)
        L.vl(18, 0, 3, ST2)
        dish(L, 10, 16, 3, 4, 1)
        dish(L, 25, 24, 3, 4, -1)
        dish(L, 10, 33, 3, 4, 1)
        L.rect(13, 15, 16, 16, D2)
        L.rect(20, 23, 23, 24, D2)
        # caixas de néon (estrutura de cristal rosa/cyan)
        for (x0, y0, w, h, m, mi, dk) in ((13, 49, 10, 6, PK, PK2, PKD), (19, 28, 4, 4, CY, CY2, CYD),
                                           (12, 10, 3, 3, PK, PK2, PKD)):
            L.rect(x0, y0, x0 + w - 1, y0 + h - 1, dk)
            fx.rect(x0 + 1, y0 + 1, x0 + w - 2, y0 + h - 2, mi)
            fx.p(x0 + 1, y0 + 1, m)
            fx.hl(x0 + 1, x0 + w - 2, y0 + 1, m)
        crystal(fx, fx, 13, 48, [4, 7, 5, 11, 8, 13, 9, 6, 3, 2], PK, PK2, PKD, 91)
        crystal(fx, fx, 23, 56, [3, 5, 2, 4], CY, CY2, CYD, 93)
        crystal(fx, fx, 3, 44, [2, 4, 3], CY, CY2, CYD, 95)
        crystal(fx, fx, 15, 3, [1, 3, 2, 0, 4, 2, 1], CY, CY2, CYD, 97)
        rr = random.Random(99)
        for k in range(9):
            y = 12 + k * 4
            t = (57 - y) / 51
            xl = round(11 + 5 * t)
            xr = round(25 - 5 * t)
            x = xl if k % 2 else xr
            m, mi, dk = (PK, PK2, PKD) if rr.random() < .5 else (CY, CY2, CYD)
            fx.p(x, y, mi)
            fx.p(x + (1 if k % 2 else -1), y, dk)
            fx.p(x, y - 1, m)
        for (ax, ay) in ((2, 58), (29, 58)):
            fx.line(18, 9, ax, ay, '#1a1218')
        glow(fx, 18, 0, WH, CY, CYD)
        glow(fx, 14, 6, CY, CY2, CYD)
        glow(fx, 22, 6, PK, PK2, PKD)
        glow(fx, 26, 30, CY, CY2, CYD)
        glow(fx, 8, 21, PK, PK2, PKD)
        glow(fx, 26, 46, PK, PK2, PKD)
    im = finish(L, fx, drop=(1, 1), shadows=[('r', 3, 61, 29, 62), ('e', 18, 61, 10, 2)])
    save(im, 'tower_%d.png' % lvl)
    return im


# ================================================================ construções
def roof_corr(L, x0, y0, x1, y1, inset, ca, cb, rim, eave):
    """Telhado de chapa visto em 3/4: trapézio que alarga até o beiral."""
    for y in range(y0, y1 + 1):
        t = (y - y0) / max(1, y1 - y0)
        d = round(inset * (1 - min(1, t * 3)))
        for x in range(x0 + d, x1 - d + 1):
            L.p(x, y, ca if (x % 2) == 0 else cb)
        if y == y0:
            L.hl(x0 + d, x1 - d, y, rim)
    L.hl(x0, x1, y1, eave)


def barraco():
    L = Lay(32, 40)
    fx = Lay(32, 40)
    r = random.Random(21)
    # parede corrugada
    L.corr(3, 21, 27, 36, R2, R1, bot=R0)
    L.rect(15, 23, 20, 31, D2)
    for x in range(15, 21, 2):
        L.vl(x, 23, 31, D1)
    L.hl(15, 20, 23, D3)
    L.p(16, 25, ST1)
    L.p(19, 25, ST1)
    L.p(5, 30, R3)
    L.p(25, 27, R3)
    L.hl(3, 27, 21, OUT)  # sombra sob o beiral
    L.hl(3, 27, 22, R0)
    # telhado
    roof_corr(L, 1, 8, 29, 20, 2, D2, D1, D4, D0)
    L.rect(1, 18, 29, 20, D1)
    for x in range(1, 30, 2):
        L.vl(x, 18, 19, D0)
    L.hl(1, 29, 18, D3)
    L.hl(1, 29, 20, D0)
    # remendo de lona e pneu de peso
    L.rect(6, 11, 12, 15, '#3e2a3a')
    L.hl(6, 12, 11, '#5a3e52')
    L.vl(12, 11, 15, '#2a1c28')
    L.ell(21, 13, 2.6, 1.6, '#16141a')
    L.p(21, 13, OUT)
    L.p(20, 12, ST0)
    for _ in range(6):
        L.p(r.randint(3, 27), r.randint(10, 17), R2)
    # chaminé de lata
    L.rect(23, 3, 24, 10, D2)
    L.vl(23, 3, 10, D4)
    L.rect(22, 2, 25, 3, D3)
    L.hl(22, 25, 2, ST1)
    # porta
    L.rect(6, 25, 11, 36, R0)
    L.vl(6, 25, 36, W1)
    for y in range(27, 36, 3):
        L.hl(7, 11, y, W0)
    L.hl(6, 11, 25, W2)
    L.p(10, 31, ST2)
    # janela quente
    window(L, 19, 26, 23, 29)
    # lampião
    L.p(4, 23, ST0)
    glow(fx, 4, 24, YE, OR, None)
    fx.p(4, 25, OR2)
    im = finish(L, fx, drop=(2, 1), shadows=[('r', 4, 37, 30, 38), ('e', 16, 38, 13, 1.3)])
    save(im, 'barraco.png')
    return im


def casa():
    L = Lay(48, 48)
    fx = Lay(48, 48)
    r = random.Random(31)
    # paredes de tábua
    L.planks(3, 27, 44, 44, [W1, W2, W1, '#4a3228'], 3, W0, r)
    L.vl(3, 27, 44, W3)
    L.vl(44, 27, 44, W0)
    L.hl(3, 44, 45, R0)
    L.hl(2, 45, 45, W0)
    L.hl(3, 44, 27, OUT)
    L.hl(3, 44, 28, W0)
    # vigas de canto
    L.rect(3, 27, 4, 45, W2)
    L.rect(43, 27, 44, 45, W1)
    # telhado de tábuas + lona
    for y in range(6, 27):
        t = (y - 6) / 20
        d = round(4 * (1 - min(1, t * 2.5)))
        for x in range(1 + d, 47 - d):
            c = R1 if (x // 3) % 2 else R2
            if (x % 3) == 2:
                c = R0
            L.p(x, y, c)
    L.hl(5, 42, 6, R4)
    L.hl(4, 43, 7, R3)
    L.rect(1, 24, 46, 26, R0)
    L.hl(1, 46, 24, R3)
    for x in range(1, 47, 3):
        L.p(x, 25, W2)
    # lona azul-escura com cordas
    L.rect(9, 11, 24, 21, D2)
    L.hl(9, 24, 11, D4)
    L.vl(9, 11, 21, D3)
    L.vl(24, 11, 21, D1)
    L.hl(9, 24, 21, D1)
    for x in range(11, 24, 4):
        L.vl(x, 12, 20, D1)
    L.line(9, 11, 6, 24, W3)
    L.line(24, 11, 28, 24, W3)
    L.p(16, 16, D3)
    for _ in range(8):
        L.p(r.randint(27, 44), r.randint(10, 22), R3)
    # chaminé de pedra
    L.rect(34, 1, 38, 14, S1)
    L.vl(34, 1, 14, S3)
    L.vl(38, 1, 14, S0)
    for y in range(3, 14, 3):
        L.hl(35, 37, y, S0)
        L.p(35 + (y % 2), y + 1, S2)
    L.rect(33, 0, 39, 1, S2)
    L.hl(33, 39, 0, S3)
    fx.p(36, 0, ORD)
    fx.p(37, 0, OR2)
    # janelas e porta
    window(L, 8, 31, 13, 35)
    window(L, 34, 31, 39, 35)
    L.rect(20, 31, 26, 44, R0)
    L.rect(21, 32, 25, 44, W0)
    for x in (22, 24):
        L.vl(x, 32, 44, R0)
    L.hl(19, 27, 30, W3)
    L.vl(19, 30, 44, W2)
    L.vl(27, 30, 44, W1)
    L.p(25, 38, OR)
    L.rect(18, 45, 28, 46, S2)
    L.hl(18, 28, 45, S3)
    # luz da porta
    glow(fx, 23, 29, YE, OR, None)
    fx.p(22, 29, OR)
    fx.p(24, 29, OR)
    im = finish(L, fx, drop=(2, 1), shadows=[('r', 3, 46, 47, 47)])
    save(im, 'casa.png')
    return im


def barrel(L, x0, y0, h=7, body=R2, lt=R3, dk=R0, band=R1, top=None):
    L.rect(x0, y0, x0 + 3, y0 + h, body)
    L.vl(x0, y0, y0 + h, lt)
    L.vl(x0 + 3, y0, y0 + h, dk)
    L.hl(x0, x0 + 3, y0 + 2, band)
    L.hl(x0, x0 + 3, y0 + h - 2, band)
    L.hl(x0, x0 + 3, y0, top or lt)


def crate(L, x0, y0, x1, y1):
    L.rect(x0, y0, x1, y1, W2)
    L.hl(x0, x1, y0, W4)
    L.vl(x0, y0, y1, W3)
    L.hl(x0, x1, y1, W0)
    L.vl(x1, y0, y1, W1)
    L.line(x0 + 1, y0 + 1, x1 - 1, y1 - 1, W1)
    L.line(x1 - 1, y0 + 1, x0 + 1, y1 - 1, W1)
    L.rect(x0 + 1, y0 + 1, x1 - 1, y0 + 1, W3)


def deposito_1():
    L = Lay(32, 40)
    fx = Lay(32, 40)
    L.planks(2, 22, 21, 37, [W1, '#4a3228'], 3, W0, random.Random(41))
    L.vl(2, 22, 37, W3)
    L.hl(2, 21, 22, OUT)
    L.hl(2, 21, 23, W0)
    roof_corr(L, 1, 12, 22, 21, 1, R2, R1, R4, R0)
    L.hl(1, 22, 19, R3)
    L.rect(1, 20, 22, 21, R1)
    L.hl(1, 22, 21, R0)
    # porta de duas folhas com X
    L.rect(6, 26, 16, 37, R0)
    L.rect(7, 27, 15, 37, D1)
    L.vl(11, 27, 37, R0)
    L.line(7, 27, 10, 37, D3)
    L.line(12, 27, 15, 37, D3)
    L.hl(6, 16, 26, W3)
    # caixotes e barris ao lado
    crate(L, 22, 23, 29, 29)
    crate(L, 24, 17, 29, 22)
    barrel(L, 22, 30, 7)
    barrel(L, 27, 30, 7, D2, D3, D0, D1)
    L.p(4, 30, ST1)
    # lâmpada sobre a porta
    L.p(11, 24, ST0)
    glow(fx, 11, 25, YE, OR, None)
    fx.p(10, 25, OR)
    fx.p(12, 25, OR)
    glow(fx, 28, 33, CY, CY2)
    im = finish(L, fx, drop=(2, 1), shadows=[('r', 3, 38, 31, 39)])
    save(im, 'deposito_1.png')
    return im


def deposito_2():
    # 32x48, 2x2: galpão reforçado, mais alto, telhado de metal, mais caixotes
    L = Lay(32, 48)
    fx = Lay(32, 48)
    L.corr(2, 24, 23, 45, D2, D1, bot=D0)
    for y in (31, 38):
        L.hl(2, 23, y, D3)
    L.rect(2, 24, 3, 45, ST0)
    L.rect(22, 24, 23, 45, D0)
    L.rect(2, 36, 7, 42, R2)       # remendo ferrugem
    for x in range(2, 8, 2):
        L.vl(x, 36, 42, R1)
    L.hl(2, 7, 36, R3)
    L.hl(2, 23, 24, OUT)
    L.hl(2, 23, 25, D0)
    # telhado metálico com nervuras e rebites
    roof_corr(L, 1, 6, 24, 23, 2, ST0, D2, ST2, D0)
    L.hl(1, 24, 20, ST1)
    L.rect(1, 21, 24, 23, D1)
    for x in range(1, 25, 2):
        L.vl(x, 21, 22, D0)
    L.hl(1, 24, 23, D0)
    for x in range(4, 23, 5):
        L.p(x, 9, ST3)
        L.p(x, 16, ST3)
    # porta de correr
    L.hl(8, 22, 27, ST2)
    L.rect(9, 28, 21, 45, R1)
    for x in range(9, 22, 3):
        L.vl(x, 28, 45, R0)
    L.vl(10, 28, 45, R2)
    L.rect(9, 28, 12, 45, OUT)       # fresta aberta
    L.p(11, 37, OR2)
    L.p(13, 36, ST2)
    L.p(13, 37, ST2)
    # vigas de reforço
    L.line(14, 29, 20, 44, R3)
    L.hl(12, 21, 36, R2)
    # caixotes empilhados à direita
    crate(L, 24, 39, 30, 45)
    crate(L, 24, 32, 30, 38)
    crate(L, 25, 26, 30, 31)
    barrel(L, 4, 43, 2, D3, D4, D1, D2)
    # lâmpada e janela
    L.rect(6, 27, 7, 28, ST0)
    glow(fx, 7, 29, YE, OR, None)
    fx.p(6, 29, OR)
    fx.p(7, 30, OR2)
    window(L, 4, 32, 6, 33, D0, cross=False)
    glow(fx, 19, 3, OR, OR2)   # luz no topo da antena
    L.vl(19, 3, 6, ST1)
    im = finish(L, fx, drop=(2, 1), shadows=[('r', 3, 46, 31, 47)])
    save(im, 'deposito_2.png')
    return im


def bed(L, x0, y0, x1, y1, seed):
    r = random.Random(seed)
    L.rect(x0, y0, x1, y1, W2)
    L.hl(x0, x1, y0, W4)
    L.hl(x0, x1, y0 + 1, W3)
    L.vl(x0, y0, y1, W3)
    L.vl(x1, y0, y1, W1)
    L.rect(x0, y1 - 1, x1, y1, W1)    # face frontal da tábua
    L.hl(x0, x1, y1, W0)
    for x in range(x0 + 3, x1, 6):
        L.p(x, y1 - 1, W0)
    L.rect(x0 + 2, y0 + 2, x1 - 2, y1 - 3, SOIL1)
    for y in range(y0 + 2, y1 - 2):
        if (y - y0) % 3 == 2:
            L.hl(x0 + 2, x1 - 2, y, SOIL2)
        elif (y - y0) % 3 == 1:
            L.hl(x0 + 2, x1 - 2, y, SOIL0)
    for _ in range((x1 - x0) * (y1 - y0) // 14):
        L.p(r.randint(x0 + 2, x1 - 2), r.randint(y0 + 2, y1 - 3), r.choice([SOIL2, SOIL0, '#4a3434']))
    L.hl(x0 + 2, x1 - 2, y0 + 2, SOIL0)


def horta_1():
    L = Lay(32, 32)
    bed(L, 1, 3, 29, 29, 51)
    # estacas nos cantos
    for x in (1, 29):
        L.rect(x, 1, x, 4, W3)
    im = finish(L, drop=(2, 1), shadows=[('r', 2, 30, 31, 31)])
    save(im, 'horta_1.png')
    return im


def horta_2():
    # 32x32, 2x2: mesmo canteiro, mais cheio, barril de água com cano e lampião
    L = Lay(32, 32)
    fx = Lay(32, 32)
    bed(L, 1, 3, 29, 29, 52)
    # cerquinha baixa nos fundos
    for x in range(2, 29, 4):
        L.rect(x, 0, x, 3, W3)
    L.hl(2, 28, 1, W2)
    # barril de água no canto superior direito
    L.rect(23, 0, 29, 8, D2)
    L.vl(23, 0, 8, D3)
    L.vl(29, 0, 8, D0)
    L.hl(23, 29, 3, D1)
    L.hl(23, 29, 7, D1)
    L.hl(23, 29, 0, D4)
    fx.hl(24, 28, 1, CYD)
    fx.p(25, 1, CY)
    fx.p(26, 1, CY2)
    # cano de irrigação na borda frontal
    L.rect(22, 9, 22, 11, ST1)
    L.hl(2, 22, 26, ST1)
    L.hl(2, 22, 25, ST2)
    for x in range(5, 22, 5):
        fx.p(x, 24, CY2)
    # lampião num poste
    L.rect(2, 0, 2, 6, W1)
    L.p(1, 0, ST0)
    L.p(3, 0, ST0)
    glow(fx, 2, 1, YE, OR, None)
    im = finish(L, fx, drop=(2, 1), shadows=[('r', 2, 30, 31, 31)])
    save(im, 'horta_2.png')
    return im


def crops():
    sheet = Image.new('RGBA', (64, 16))
    # 0: sementes
    L = Lay(16, 16)
    for (x, y) in ((4, 10), (8, 9), (12, 10), (6, 12), (10, 12)):
        L.p(x, y, '#8a7a5a')
        L.p(x, y + 1, '#4a3a2a')
    sheet.alpha_composite(L.im, (0, 0))
    # 1: broto
    L = Lay(16, 16)
    for (x, y) in ((5, 11), (11, 11)):
        L.vl(x, y - 2, y, PL1)
        L.p(x - 1, y - 3, PL2)
        L.p(x + 1, y - 3, PL3)
        L.p(x - 1, y - 2, PL1)
        L.p(x + 1, y - 2, PL2)
    sheet.alpha_composite(outline(L.im), (16, 0))
    # 2: folhoso
    L = Lay(16, 16)
    for (cx, cy) in ((5, 10), (11, 10)):
        L.ell(cx, cy, 3, 2.6, PL1)
        L.ell(cx - .5, cy - .8, 2, 1.4, PL2)
        L.p(cx - 1, cy - 2, PL3)
        L.p(cx + 1, cy + 1, PL0)
        L.p(cx, cy + 2, PL0)
    sheet.alpha_composite(outline(L.im), (32, 0))
    # 3: maduro com frutos
    L = Lay(16, 16)
    for (cx, cy) in ((5, 9.5), (11, 9.5)):
        L.ell(cx, cy, 3.4, 3, PL1)
        L.ell(cx - .5, cy - 1, 2.2, 1.6, PL2)
        L.p(cx - 1, cy - 2.5, PL3)
        L.p(cx + 1, cy + 1.5, PL0)
    for (x, y) in ((4, 10), (6, 8), (11, 11), (12, 8), (9, 9)):
        L.p(x, y, OR2)
        L.p(x + 1, y, RED)
        L.p(x, y - 1, OR)
    sheet.alpha_composite(outline(L.im), (48, 0))
    save(sheet, 'crop.png')
    return sheet


def poco():
    L = Lay(32, 32)
    fx = Lay(32, 32)
    # cilindro de pedra
    cx, top, bot = 15.5, 19, 26
    L.rect(5, top, 26, bot, S1)
    L.ell(cx, bot, 10.5, 4, S1)
    r = random.Random(61)
    for y in range(top, bot + 4):
        for x in range(5, 27):
            if L.a(x, y) and ((y - top) % 3 == 2 or (x + (y // 3) * 2) % 6 == 0):
                L.p(x, y, S0)
    for _ in range(14):
        L.p(r.randint(6, 25), r.randint(top + 1, bot + 2), S2)
    L.vl(5, top, bot, S2)
    L.vl(6, top, bot, S2)
    L.vl(26, top, bot + 1, S0)
    L.vl(25, top, bot + 1, S0)
    # aro superior
    L.ell(cx, top, 10.5, 4.5, S2)
    L.ell(cx, top - .3, 10.5, 4.2, S3)
    L.ell(cx, top, 8.2, 3.0, S0)
    L.ell(cx, top + .4, 7.2, 2.4, '#0f1a22')
    fx.hl(11, 14, 20, CYD)
    fx.p(12, 20, CY2)
    fx.p(13, 20, CY)
    fx.p(18, 21, CY2)
    for i in range(12):
        a = i / 12 * 2 * math.pi
        L.p(int(cx + math.cos(a) * 9.5), int(top + math.sin(a) * 3.8), S1)
    # postes, travessa e manivela
    for x in (4, 26):
        L.rect(x, 3, x + 1, 19, W2)
        L.vl(x, 3, 19, W3)
    L.rect(3, 4, 28, 5, W1)
    L.hl(3, 28, 4, W3)
    L.rect(27, 5, 28, 8, ST1)
    L.rect(28, 8, 30, 8, ST1)
    L.p(30, 9, ST2)
    L.rect(11, 2, 20, 3, D2)  # telhadinho
    L.hl(11, 20, 2, D3)
    # corda e balde
    L.vl(15, 6, 10, '#9a8a70')
    L.rect(13, 11, 18, 15, R2)
    L.vl(13, 11, 15, R3)
    L.vl(18, 11, 15, R0)
    L.hl(13, 18, 11, R4)
    L.hl(13, 18, 13, R1)
    L.hl(14, 17, 15, R1)
    im = finish(L, fx, drop=(2, 1), shadows=[('e', 17, 29.5, 12, 2)])
    save(im, 'poco.png')
    return im


def serraria():
    L = Lay(48, 40)
    fx = Lay(48, 40)
    # pilha de tábuas ao fundo
    for i, y in enumerate(range(15, 23, 2)):
        L.rect(29, y, 45, y + 1, W3 if i % 2 else W2)
        L.hl(29, 45, y, W4 if i % 2 else W3)
        L.p(45, y + 1, W0)
        L.p(29, y + 1, W1)
    L.rect(29, 23, 45, 24, W1)
    # pilha de toras
    for (cx, cy) in ((31.5, 33), (37.5, 33), (43.5, 33), (34.5, 28), (40.5, 28), (37.5, 23.5)):
        L.ell(cx, cy, 3.2, 3, R1)
        L.ell(cx, cy, 2.4, 2.2, W3)
        L.ell(cx, cy, 1.2, 1.1, W2)
        L.p(int(cx) - 1, int(cy) - 1, W4)
    # postes do telheiro
    for x in (3, 25):
        L.rect(x, 17, x + 1, 36, W2)
        L.vl(x, 17, 36, W3)
    # telheiro de chapa
    roof_corr(L, 0, 5, 28, 16, 2, R2, R1, R4, R0)
    L.rect(0, 15, 28, 17, R1)
    L.hl(0, 28, 15, R3)
    L.hl(0, 28, 17, R0)
    L.rect(9, 8, 15, 12, D2)
    L.hl(9, 15, 8, D3)
    # mesa de serra
    L.rect(6, 27, 22, 29, W2)
    L.hl(6, 22, 27, W4)
    L.hl(6, 22, 29, W0)
    L.rect(7, 30, 8, 36, W1)
    L.rect(20, 30, 21, 36, W1)
    L.hl(7, 21, 33, W0)
    # lâmina circular
    L.ell(14.5, 25, 4, 3.6, ST1)
    L.ell(14.5, 25, 2.8, 2.5, ST2)
    L.p(14, 24, ST3)
    L.p(13, 23, ST3)
    L.rect(14, 25, 15, 25, ST0)
    for i in range(8):
        a = i / 8 * 2 * math.pi
        L.p(int(14.5 + math.cos(a) * 4.3), int(25 + math.sin(a) * 3.9), ST0)
    L.rect(9, 27, 13, 27, W3)
    # serragem
    for (x, y) in ((10, 37), (13, 38), (17, 37), (19, 38), (8, 38)):
        L.p(x, y, W4)
    # lâmpada pendurada e faísca
    fx.vl(19, 18, 19, '#1a1218')
    glow(fx, 19, 20, YE, OR, None)
    fx.p(18, 20, OR)
    fx.p(20, 20, OR)
    fx.p(19, 21, OR2)
    fx.p(19, 23, YE)
    fx.p(20, 22, OR)
    im = finish(L, fx, drop=(2, 1), shadows=[('r', 2, 37, 47, 38)])
    save(im, 'serraria.png')
    return im


def scrap_pile(L, x0, y0, x1, y1, seed):
    r = random.Random(seed)
    cx, cy = (x0 + x1) / 2, y1
    rx, ry = (x1 - x0) / 2, (y1 - y0)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1:
                L.p(x, y, r.choice([D1, D1, D2, R1, R1, D0]))
    for _ in range(int(rx * ry / 4)):
        x, y = r.randint(x0, x1), r.randint(y0, y1)
        if L.a(x, y):
            c = r.choice([R2, R3, D3, ST1, ST0])
            L.p(x, y, c)
            if L.a(x + 1, y):
                L.p(x + 1, y, c)
    # bordas de cima claras
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            if L.a(x, y):
                L.p(x, y, r.choice([D3, R3, ST1]))
                break


def ferrovelho():
    L = Lay(48, 40)
    fx = Lay(48, 40)
    r = random.Random(71)
    # cerca de chapas com topos irregulares
    x = 1
    i = 0
    while x <= 45:
        w = r.randint(4, 6)
        top = 9 + r.randint(0, 5)
        ca, cb = ((R2, R1) if i % 2 == 0 else (D2, D1))
        L.corr(x, top, min(x + w - 1, 46), 26, ca, cb, rim=(R3 if i % 2 == 0 else D3), bot=OUT)
        L.vl(min(x + w - 1, 46), top, 26, R0 if i % 2 == 0 else D0)
        L.p(x + 1, top + 2, ST1)
        x += w
        i += 1
    L.hl(1, 46, 20, R0)
    # guindaste
    L.rect(20, 3, 21, 33, D2)
    L.vl(20, 3, 33, D4)
    for y in range(6, 33, 4):
        L.p(21, y, D0)
    L.rect(10, 2, 38, 3, D2)
    L.hl(10, 38, 2, D4)
    for xx in range(12, 38, 3):
        L.p(xx, 3, D0)
    L.rect(9, 3, 13, 7, S1)        # contrapeso
    L.hl(9, 13, 3, S3)
    L.line(21, 4, 12, 3, ST0)
    L.rect(18, 32, 23, 34, D1)
    # cabo e gancho (cabo na fx, sem contorno)
    fx.vl(35, 4, 15, '#1a1218')
    L.rect(34, 16, 36, 17, ST1)
    L.vl(35, 18, 20, ST2)
    L.p(34, 20, ST2)
    L.p(33, 19, ST2)
    L.p(36, 18, ST3)
    # pilhas na frente
    scrap_pile(L, 2, 26, 18, 37, 73)
    scrap_pile(L, 25, 27, 45, 37, 74)
    L.ell(10, 34.5, 3, 1.6, '#16141a')
    L.ell(10, 34.3, 1.4, .7, OUT)
    barrel(L, 39, 24, 7)
    L.rect(26, 22, 31, 29, ST0)
    L.hl(26, 31, 22, ST2)
    # lâmpada laranja no poste
    glow(fx, 21, 1, YE, OR, None)
    fx.p(20, 1, OR)
    fx.p(22, 1, OR)
    fx.p(21, 0, OR2)
    glow(fx, 31, 31, CY, CY2)
    glow(fx, 6, 30, OR, OR2)
    im = finish(L, fx, drop=(2, 1), shadows=[('r', 2, 38, 47, 39)])
    save(im, 'ferrovelho.png')
    return im


def fogueira():
    sheet = Image.new('RGBA', (64, 16))
    flames = [
        ["....o...", "...oo...", "..oyo.o.", "..oyyo..", ".oyyyoo.", ".oywyyo.", "oyywwyo.", "oyywwyyo"],
        ["...o....", "...oo..o", "..oyo.o.", ".ooyyo..", ".oyyyyo.", ".oyywyo.", ".oywwyyo", "oyywwyyo"],
        [".....o..", "..o.oo..", "..ooyo..", "..oyyoo.", ".oyyyyo.", "ooywyyo.", "oyywwyo.", "oyywwyyo"],
        ["..o.....", "..oo.o..", ".oyo.oo.", ".oyyoyo.", ".oyyyyo.", ".oywwyoo", "oyywwyyo", "oyywwyyo"],
    ]
    cmap = {'o': OR2, 'y': OR, 'w': YE}
    for f in range(4):
        L = Lay(16, 16)
        fx = Lay(16, 16)
        # toras cruzadas
        L.line(4, 12, 11, 10, W2)
        L.line(4, 11, 11, 9, W1)
        L.line(4, 9, 11, 12, W1)
        L.line(4, 10, 11, 13, W2)
        L.p(4, 10, W3)
        # anel de pedras
        stones = [(2, 12), (4, 14), (7, 14), (10, 14), (13, 12), (12, 10), (3, 10)]
        for i, (sx, sy) in enumerate(stones):
            L.rect(sx, sy, sx + 1, sy, S2)
            L.p(sx, sy, S3)
            L.p(sx + 1, sy + 1 if sy < 14 else sy, S1)
        for y, row in enumerate(flames[f]):
            for x, ch in enumerate(row):
                if ch in cmap:
                    fx.p(4 + x, 3 + y, cmap[ch])
        # brasas
        r = random.Random(100 + f)
        for _ in range(2):
            fx.p(r.randint(4, 11), r.randint(0, 3), OR if r.random() < .5 else YE)
        fx.hl(6, 9, 11, YE)
        fx.p(7, 12, OR2)
        sheet.alpha_composite(finish(L, fx, drop=None, shadows=[('e', 8, 14, 7, 1.6)]), (f * 16, 0))
    save(sheet, 'fogueira.png')
    return sheet


def obra(w):
    W = w * 16
    L = Lay(W, 32)
    fx = Lay(W, 32)
    r = random.Random(80 + w)
    # andaime nos fundos
    posts = [3, W // 2 - 1, W - 5] if w == 3 else [3, W - 5]
    for x in posts:
        L.rect(x, 1, x + 1, 22, W2)
        L.vl(x, 1, 22, W3)
    for y in (2, 11):
        L.rect(2, y, W - 3, y + 1, W2)
        L.hl(2, W - 3, y, W4)
    L.line(5, 10, W // 2 - 2 if w == 3 else W - 6, 3, W1)
    if w == 3:
        L.line(W // 2 + 1, 3, W - 6, 10, W1)
    # tábuas no chão (frente esquerda)
    for i in range(3):
        y = 25 + i * 2
        L.rect(2 + i, y, 13 + i, y + 1, W3 if i % 2 == 0 else W2)
        L.hl(2 + i, 13 + i, y, W4 if i % 2 == 0 else W3)
    # pilha de material (frente direita)
    scrap_pile(L, W - 13, 21, W - 3, 28, 90 + w)
    L.rect(W - 11, 26, W - 6, 28, S2)
    L.hl(W - 11, W - 6, 26, S3)
    # estacas
    stakes = [(1, 14), (W - 2, 14), (1, 30), (W - 2, 30)]
    for (x, y) in stakes:
        L.rect(x, y - 3, x, y, W3)
        L.p(x, y - 3, W4)
    # barbante (fx)
    sc = '#d8c8a8'
    for x in range(2, W - 2):
        if x % 3 != 2:
            fx.p(x, 12 + 0, sc)
            fx.p(x, 28, sc)
    for y in range(12, 29):
        if y % 3 != 2:
            fx.p(1, y, sc)
            fx.p(W - 2, y, sc)
    im = finish(L, fx, drop=(1, 1))
    save(im, 'obra_%d.png' % w)
    return im


def gate():
    L = Lay(32, 32)
    fx = Lay(32, 32)
    # dois postes
    for x in (3, 26):
        L.rect(x, 3, x + 2, 29, W2)
        L.vl(x, 3, 29, W3)
        L.vl(x + 2, 3, 29, W1)
        L.hl(x - 1, x + 3, 29, W0)
        L.rect(x - 1, 27, x + 3, 29, S1)
        L.hl(x - 1, x + 3, 27, S3)
    # travessa
    L.rect(1, 4, 30, 6, W2)
    L.hl(1, 30, 4, W4)
    L.hl(1, 30, 6, W0)
    L.p(4, 5, ST2)
    L.p(27, 5, ST2)
    # placa pendurada (chapa)
    fx.vl(10, 7, 9, '#1a1218')
    fx.vl(21, 7, 9, '#1a1218')
    L.rect(8, 10, 23, 16, D2)
    L.hl(8, 23, 10, D4)
    L.vl(8, 10, 16, D3)
    L.vl(23, 10, 16, D0)
    L.hl(8, 23, 16, D0)
    L.rect(19, 13, 22, 15, R2)
    # "letras" pintadas em cyan
    for x in (10, 11, 13, 15, 16, 18):
        fx.p(x, 12, CY2)
    for x in (10, 12, 13, 15, 17):
        fx.p(x, 14, CY2)
    fx.p(11, 13, CY)
    # lanterna quente no poste esquerdo
    L.rect(0, 8, 2, 8, ST0)
    L.rect(0, 9, 2, 12, ORD)
    L.hl(0, 2, 13, ST0)
    glow(fx, 1, 10, YE, OR, None)
    fx.p(1, 11, OR)
    # trapo pink amarrado no poste direito
    L.rect(29, 8, 29, 11, PK2)
    L.p(30, 9, PKD)
    L.p(29, 8, PK)
    im = finish(L, fx, drop=(2, 1), shadows=[('e', 5, 30.5, 4, 1.2), ('e', 28, 30.5, 3.5, 1.2)])
    save(im, 'gate.png')
    return im


# ================================================================ pessoas
PEOPLE = [
    # Joaquim
    dict(skin='#c08a6a', skin_d='#9a6a50', hair='#9a9aa0', hair_d='#6e6e78', style='balding', beard='#b4b4ba',
         jacket='#1f3a3a', jacket_l='#2e5250', jacket_d='#14262a', pants='#2a2228', shoes='#1a1216',
         accent=OR2, accent_l=OR, acc='scarf'),
    dict(skin='#6b4430', skin_d='#4e3022', hair='#1a1416', hair_d='#120e10', style='cap', cap='#1f2c36',
         jacket='#26323c', jacket_l='#36485a', jacket_d='#18202a', pants='#2a2630', shoes='#141018',
         accent=CY2, accent_l=CY, acc='zip'),
    dict(skin='#e0b89a', skin_d='#b88e74', hair='#4a2a2a', hair_d='#321c1e', style='hood', hood='#4e2c4a',
         jacket='#2a2032', jacket_l='#3c2e48', jacket_d='#1a1420', pants='#22202a', shoes='#141018',
         accent=PK2, accent_l=PK, acc='trim'),
    dict(skin='#a8704e', skin_d='#84543a', hair='#18121a', hair_d='#0f0b10', style='bun',
         jacket='#3a2622', jacket_l='#5a3a30', jacket_d='#2a1a18', pants='#26242c', shoes='#141018',
         accent=OR2, accent_l=OR, acc='belt'),
    dict(skin='#4e3024', skin_d='#382218', hair='#2a1c18', hair_d='#1a1210', style='bald',
         jacket='#1d2630', jacket_l='#2c3a48', jacket_d='#121820', pants='#30282a', shoes='#141018',
         accent='#d8a830', accent_l=YE, acc='vest'),
    dict(skin='#d09a78', skin_d='#a87658', hair='#5a2a1a', hair_d='#3a1a12', style='beanie', cap='#9a2a28',
         jacket='#2b2a30', jacket_l='#3e3c46', jacket_d='#1a1a20', pants='#1f2630', shoes='#141018',
         accent=RED, accent_l='#f07060', acc='scarf'),
]

EYE = '#140c12'


def draw_person(L, P, d, f):
    bob = [0, 0, -1, 0, -1][f]
    lift = {1: 'L', 3: 'R'}.get(f, None)
    sk, skd = P['skin'], P['skin_d']
    hr, hrd = P['hair'], P['hair_d']
    jk, jkl, jkd = P['jacket'], P['jacket_l'], P['jacket_d']
    ac, acl = P['accent'], P['accent_l']
    st = P['style']
    b = bob
    if d in (0, 1):
        # pernas
        for side, xs in (('L', (5, 6)), ('R', (9, 10))):
            up = lift == side
            L.rect(xs[0], 12, xs[1], 13 - (1 if up else 0), P['pants'])
            L.rect(xs[0], 14 - (1 if up else 0), xs[1], 14 - (1 if up else 0), P['shoes'])
        L.p(5, 12, P['pants'])
        # torso
        L.rect(4, 9 + b, 11, 11 + b, jk)
        L.vl(4, 9 + b, 11 + b, jkd)
        L.vl(11, 9 + b, 11 + b, jkd)
        L.vl(5, 9 + b, 11 + b, jkl)
        L.hl(5, 10, 12 + b, jkd) if b < 0 else None
        # mãos
        hl_y = 12 + b - (1 if lift == 'R' else 0)
        hr_y = 12 + b - (1 if lift == 'L' else 0)
        L.p(4, hl_y, sk)
        L.p(11, hr_y, sk)
        # acento
        acc = P['acc']
        if acc == 'scarf':
            L.hl(5, 10, 9 + b, ac)
            L.p(6, 9 + b, acl)
            L.p(9 if d == 0 else 6, 10 + b, ac)
        elif acc == 'zip' and d == 0:
            L.vl(8, 9 + b, 11 + b, ac)
            L.p(8, 9 + b, acl)
        elif acc == 'zip':
            L.hl(5, 10, 10 + b, ac)
        elif acc == 'trim':
            L.hl(5, 10, 11 + b, ac)
        elif acc == 'belt':
            L.hl(5, 10, 11 + b, ac)
            if d == 0:
                L.p(8, 11 + b, acl)
        elif acc == 'vest':
            L.vl(5, 9 + b, 11 + b, ac)
            L.vl(10, 9 + b, 11 + b, ac)
            L.p(5, 10 + b, acl)
            L.p(10, 10 + b, acl)
        # cabeça
        hy = 2 + b
        L.rect(4, hy, 11, hy + 6, sk)
        for (cx, cy) in ((4, hy), (11, hy), (4, hy + 6), (11, hy + 6)):
            if 0 <= cy < 16:
                L.px[cx, cy] = (0, 0, 0, 0)
        L.vl(11, hy + 1, hy + 5, skd)
        if d == 0:
            if st in ('short', 'balding', 'bun'):
                if st == 'balding':
                    L.hl(5, 10, hy, sk)
                    L.p(6, hy, '#d8a888')
                    L.vl(4, hy + 1, hy + 4, hr)
                    L.vl(11, hy + 1, hy + 4, hrd)
                    L.hl(5, 10, hy + 1, sk)
                else:
                    L.hl(5, 10, hy, hr)
                    L.hl(4, 11, hy + 1, hr)
                    L.hl(4, 11, hy + 2, hr)
                    L.p(5, hy + 3, hr)
                    L.vl(4, hy + 3, hy + 4, hr)
                    L.vl(11, hy + 3, hy + 4, hrd)
                    L.p(6, hy, hrd)
                    if st == 'bun':
                        L.hl(6, 9, hy - 1, hr)
                        L.p(7, hy - 1, hrd)
            elif st == 'cap':
                L.hl(5, 10, hy, P['cap'])
                L.rect(4, hy + 1, 11, hy + 2, P['cap'])
                L.p(5, hy, '#2e4050')
                L.hl(4, 11, hy + 3, ac)
                L.p(5, hy + 3, acl)
                L.p(4, hy + 4, hr)
                L.p(11, hy + 4, hr)
            elif st == 'hood':
                L.hl(5, 10, hy, P['hood'])
                L.rect(4, hy + 1, 11, hy + 2, P['hood'])
                L.vl(4, hy + 3, hy + 6, P['hood'])
                L.vl(11, hy + 3, hy + 6, P['jacket_d'])
                L.hl(5, 10, hy + 3, ac)
                L.p(6, hy + 3, acl)
                L.p(5, hy + 4, hr)
                L.p(10, hy + 4, hr)
            elif st == 'bald':
                L.p(6, hy + 1, '#7a5040')
                L.p(5, hy + 2, '#6a4434')
                L.hl(5, 10, hy + 3, ac)  # óculos de proteção na testa
                L.p(6, hy + 3, acl)
                L.p(9, hy + 3, acl)
                L.p(4, hy + 4, hr)
                L.p(11, hy + 4, hr)
            elif st == 'beanie':
                L.hl(5, 10, hy, P['cap'])
                L.rect(4, hy + 1, 11, hy + 2, P['cap'])
                L.hl(4, 11, hy + 3, '#6e1e1e')
                L.p(5, hy + 1, '#c04040')
                L.hl(7, 8, hy - 1, '#c04040')
                L.p(4, hy + 4, hr)
                L.p(11, hy + 4, hr)
                L.p(5, hy + 4, hr)
            # olhos
            L.p(6, hy + 4, EYE)
            L.p(9, hy + 4, EYE)
            L.p(5, hy + 5, '#d88a7a' if st not in ('bald', 'cap') else skd)
            if P.get('beard'):
                L.hl(5, 10, hy + 5, P['beard'])
                L.hl(5, 10, hy + 6, P['beard'])
                L.p(4, hy + 5, P['beard'])
                L.p(11, hy + 5, '#8a8a92')
                L.hl(7, 8, hy + 5, '#5a4a4a')
                L.p(6, hy + 4, EYE)
        else:  # costas
            if st == 'balding':
                L.rect(4, hy + 2, 11, hy + 5, hr)
                L.hl(5, 10, hy + 6, hrd)
                L.p(6, hy, '#d8a888')
            elif st in ('short', 'bun'):
                L.rect(4, hy, 11, hy + 5, hr)
                L.hl(5, 10, hy + 6, hrd)
                L.p(6, hy + 1, hrd)
                if st == 'bun':
                    L.hl(6, 9, hy - 1, hr)
                    L.rect(7, hy + 1, 8, hy + 2, hrd)
            elif st == 'cap':
                L.rect(4, hy, 11, hy + 3, P['cap'])
                L.rect(4, hy + 4, 11, hy + 5, hr)
                L.hl(6, 9, hy + 3, ac)
            elif st == 'hood':
                L.rect(4, hy, 11, hy + 6, P['hood'])
                L.vl(5, hy, hy + 5, '#64395e')
                L.vl(10, hy + 1, hy + 6, '#3a2036')
                L.hl(5, 10, hy + 6, '#3a2036')
                L.p(7, hy + 6, ac)
                L.p(8, hy + 6, acl)
                # mochila nas costas
                L.rect(6, 9 + b, 9, 11 + b, R2)
                L.hl(6, 9, 9 + b, R3)
                L.vl(9, 9 + b, 11 + b, R1)
                L.p(7, 10 + b, ST1)
            elif st == 'bald':
                L.p(6, hy + 1, '#7a5040')
                L.hl(5, 10, hy + 3, '#2a2a2a')
                L.vl(11, hy + 1, hy + 5, skd)
            elif st == 'beanie':
                L.rect(4, hy, 11, hy + 3, P['cap'])
                L.hl(4, 11, hy + 3, '#6e1e1e')
                L.rect(4, hy + 4, 11, hy + 5, hr)
                L.hl(7, 8, hy - 1, '#c04040')
            L.vl(11, hy + 1, hy + 5, None)
    else:  # lado (direita)
        # pernas
        if f in (1, 3):
            back, front = ((5, 6), (9, 10))
            near_front = f == 1
        else:
            back, front = ((6, 7), (8, 9))
            near_front = True
        pdark = '#1a161c'
        L.rect(back[0], 12, back[1], 13, pdark if near_front else P['pants'])
        L.hl(back[0], back[1] + (1 if f not in (1, 3) else 0), 14, P['shoes'])
        L.rect(front[0], 12, front[1], 13, P['pants'] if near_front else pdark)
        L.hl(front[0], front[1] + 1, 14, P['shoes'])
        # torso
        L.rect(6, 9 + b, 10, 11 + b, jk)
        L.vl(6, 9 + b, 11 + b, jkd)
        L.vl(10, 9 + b, 11 + b, jkl)
        acc = P['acc']
        if acc == 'scarf':
            L.hl(6, 10, 9 + b, ac)
            L.p(5, 10 + b, ac)
            L.p(9, 9 + b, acl)
        elif acc in ('zip',):
            L.vl(10, 9 + b, 11 + b, ac)
        elif acc in ('trim', 'belt'):
            L.hl(6, 10, 11 + b, ac)
        elif acc == 'vest':
            L.vl(9, 9 + b, 11 + b, ac)
            L.p(9, 10 + b, acl)
        # braço
        if f == 1:
            hx_, hy_ = 10, 11
        elif f == 3:
            hx_, hy_ = 6, 11
        else:
            hx_, hy_ = 8, 12
        L.vl(8, 9 + b, 10 + b, jkd)
        L.p(hx_, hy_ + b, sk)
        # cabeça
        hy = 2 + b
        L.rect(5, hy, 11, hy + 6, sk)
        for (cx, cy) in ((5, hy), (11, hy), (5, hy + 6), (11, hy + 6)):
            if 0 <= cy < 16:
                L.px[cx, cy] = (0, 0, 0, 0)
        if st == 'balding':
            L.rect(5, hy + 2, 7, hy + 5, hr)
            L.p(8, hy + 2, hr)
        elif st in ('short', 'bun'):
            L.hl(6, 10, hy, hr)
            L.hl(5, 11, hy + 1, hr)
            L.rect(5, hy + 2, 7, hy + 5, hr)
            L.p(8, hy + 2, hr)
            if st == 'bun':
                L.rect(3, hy + 1, 4, hy + 2, hr)
                L.p(4, hy + 1, hrd)
        elif st == 'cap':
            L.hl(6, 10, hy, P['cap'])
            L.rect(5, hy + 1, 11, hy + 2, P['cap'])
            L.hl(9, 12, hy + 3, ac)
            L.p(12, hy + 3, acl)
            L.rect(5, hy + 3, 7, hy + 5, hr)
        elif st == 'hood':
            L.hl(6, 10, hy, P['hood'])
            L.rect(5, hy + 1, 11, hy + 2, P['hood'])
            L.rect(5, hy + 3, 8, hy + 6, P['hood'])
            L.vl(8, hy + 3, hy + 6, ac)
            L.p(8, hy + 3, acl)
        elif st == 'bald':
            L.p(7, hy + 1, '#7a5040')
            L.hl(7, 11, hy + 3, ac)
            L.p(11, hy + 3, acl)
            L.p(5, hy + 3, '#2a2a2a')
        elif st == 'beanie':
            L.hl(6, 10, hy, P['cap'])
            L.rect(5, hy + 1, 11, hy + 2, P['cap'])
            L.hl(5, 11, hy + 3, '#6e1e1e')
            L.p(6, hy + 1, '#c04040')
            L.hl(7, 8, hy - 1, '#c04040')
            L.rect(5, hy + 4, 6, hy + 5, hr)
        L.p(10, hy + 4, EYE)
        L.p(12, hy + 4, sk)  # nariz
        L.p(8, hy + 5, skd)  # orelha/sombra
        if P.get('beard'):
            L.rect(8, hy + 5, 11, hy + 6, P['beard'])
            L.p(12, hy + 5, P['beard'])
            L.p(11, hy + 5, '#5a4a4a')


def people():
    sheets = []
    for i, P in enumerate(PEOPLE):
        sheet = Image.new('RGBA', (80, 48))
        for d in range(3):
            for f in range(5):
                L = Lay(16, 16)
                draw_person(L, P, d, f)
                fr = finish(L, drop=None, shadows=[('e', 8, 14.6, 4.5, 1.4)])
                sheet.alpha_composite(fr, (f * 16, d * 16))
        save(sheet, 'person_%d.png' % i)
        sheets.append(sheet)
    return sheets


def person_sleep():
    L = Lay(16, 16)
    bub, bubd = '#e8e0f0', '#b8a8c8'
    L.rect(3, 2, 13, 10, bub)
    for (x, y) in ((3, 2), (13, 2), (3, 10), (13, 10)):
        L.px[x, y] = (0, 0, 0, 0)
    L.hl(4, 12, 10, bubd)
    L.vl(13, 3, 9, bubd)
    L.p(5, 11, bub)
    L.p(4, 12, bub)
    zc = '#3a2e58'
    L.hl(5, 9, 4, zc)
    L.p(8, 5, zc)
    L.p(7, 6, zc)
    L.p(6, 7, zc)
    L.hl(5, 9, 8, zc)
    L.hl(10, 12, 3, '#6a5a98')
    L.p(11, 4, '#6a5a98')
    L.hl(10, 12, 5, '#6a5a98')
    im = outline(L.im)
    save(im, 'person_sleep.png')
    return im


# ================================================================ ícones
ICONS = [
    # 0 comida (batata/maçã)
    ["........",
     "....g...",
     "..rrgr..",
     ".rRrrrr.",
     ".rRrrrr.",
     ".rrrrrd.",
     "..rddd..",
     "........"],
    # 1 água
    ["...c....",
     "...cc...",
     "..cccc..",
     "..CCcc..",
     ".cCcccc.",
     ".ccccbc.",
     "..cbbc..",
     "........"],
    # 2 madeira
    ["........",
     "........",
     ".wwwwOO.",
     ".WWWOyyO",
     ".wwwOyOO",
     ".dddOOO.",
     "........",
     "........"],
    # 3 sucata (engrenagem)
    ["........",
     "..s..s..",
     ".sSSSSs.",
     "..S..S..",
     "..S..S..",
     ".sSSSSs.",
     "..s..s..",
     "........"],
    # 4 pessoa
    ["........",
     "...kk...",
     "..kkkk..",
     "..kkkk..",
     "...kk...",
     ".jjjjjj.",
     ".jJjjjj.",
     "........"],
    # 5 cama
    ["........",
     "........",
     "w.......",
     "wpp.....",
     "wbbbbbbw",
     "wBBBBBBw",
     "w......w",
     "........"],
    # 6 relógio
    [".......",
     "..aaaa..",
     ".aWWWWa.",
     ".aWWkWa.",
     ".aWkkWa.",
     ".aWWWWa.",
     "..aaaa..",
     "........"],
    # 7 torre (antena)
    ["...C....",
     "...s....",
     "..sss...",
     "..s.s...",
     "..sSs...",
     ".sSSSs..",
     ".s...s..",
     "........"],
    # 8 martelo
    ["........",
     ".SSSS...",
     ".SssS...",
     "...w....",
     "...w....",
     "...w....",
     "...W....",
     "........"],
    # 9 seta cima
    ["...g....",
     "..ggg...",
     ".ggggg..",
     "...g....",
     "...g....",
     "...g....",
     "........",
     "........"],
    # 10 cadeado
    ["........",
     "..sss...",
     ".s...s..",
     ".s...s..",
     "yYYYYYy.",
     "yYYkYYy.",
     "yYYYYYy.",
     "........"],
    # 11 check
    ["........",
     "......g.",
     ".....gg.",
     "g...gg..",
     "gg.gg...",
     ".ggg....",
     "..g.....",
     "........"],
    # 12 estrela
    ["...y....",
     "...y....",
     "yyyYyyy.",
     ".yYYYy..",
     "..yyy...",
     ".yy.yy..",
     ".y...y..",
     "........"],
    # 13 sol
    ["........",
     ".y.y.y..",
     "..YYY...",
     ".yYYYy..",
     "..YYY...",
     ".y.y.y..",
     "........",
     "........"],
    # 14 lua
    ["........",
     "..mmm...",
     ".mmM....",
     ".mM.....",
     ".mM.....",
     ".mmM..m.",
     "..mmmm..",
     "........"],
    # 15 alerta
    ["........",
     "...oo...",
     "...oo...",
     "...oo...",
     "...oo...",
     "........",
     "...oo...",
     "........"],
]
ICON_COLORS = {
    'r': OR2, 'R': OR, 'd': '#a03a20', 'g': '#5ad6a0', 'c': CY2, 'C': CY, 'b': '#2a8aa0',
    'w': W3, 'W': W4, 'O': '#a8784c', 'y': YE, 'Y': '#fff0a0', 's': ST2, 'S': ST3, 'k': '#e0b89a',
    'j': CY2, 'J': CY, 'p': '#e8e0f0', 'B': PK2, 'a': ST2, 'm': '#c8c8e0', 'M': '#f0f0ff',
    'o': OR, 'D': W2,
}


def icons():
    sheet = Image.new('RGBA', (128, 8))
    fixes = {2: {'d': W2, 'O': W2, 'y': W4}, 4: {'k': '#d8c8b8'}, 5: {'w': W3, 'b': PK2, 'B': PKD},
             9: {'g': '#5ad6a0'}}
    for i, rows in enumerate(ICONS):
        L = Lay(8, 8)
        cm = dict(ICON_COLORS)
        cm.update(fixes.get(i, {}))
        if i == 0:
            cm['g'] = PL2
        for y, row in enumerate(rows):
            for x, ch in enumerate(row[:8]):
                if ch in cm:
                    L.p(x, y, cm[ch])
        sheet.alpha_composite(outline(L.im), (i * 8, 0))
    save(sheet, 'icons.png')
    return sheet


# ================================================================ UI e auxiliares
def ui():
    def nine(fill, border, hi=None, lo=None, round_=True):
        L = Lay(16, 16)
        L.rect(1, 1, 14, 14, fill)
        L.hl(1, 14, 0, border)
        L.hl(1, 14, 15, border)
        L.vl(0, 1, 14, border)
        L.vl(15, 1, 14, border)
        if not round_:
            for (x, y) in ((0, 0), (15, 0), (0, 15), (15, 15)):
                L.p(x, y, border)
        if hi:
            L.hl(1, 14, 1, hi)
        if lo:
            L.hl(1, 14, 14, lo)
        return L.im

    save(nine((0x17, 0x13, 0x1b, 235), '#5c4a5e', '#3e3242', round_=False), 'ui_panel.png')
    sheet = Image.new('RGBA', (48, 16))
    sheet.alpha_composite(nine('#3a2a36', '#5c4a5e', '#56425a', '#2a1e28'), (0, 0))
    sheet.alpha_composite(nine('#48323f', '#e2a050', '#6a4c5e', '#2e2028'), (16, 0))
    sheet.alpha_composite(nine('#2a1e28', '#5c4a5e', '#1c141c', '#3a2a36'), (32, 0))
    save(sheet, 'ui_button.png')
    save(nine('#2c2a2e', '#48464c', '#38363a', '#222024'), 'ui_button_off.png')


def light():
    im = Image.new('RGBA', (64, 64))
    px = im.load()
    for y in range(64):
        for x in range(64):
            d = math.hypot(x + .5 - 32, y + .5 - 32) / 32
            a = max(0.0, 1 - d)
            px[x, y] = (255, 255, 255, int(round(255 * a * a)))
    save(im, 'light.png')


def ghosts():
    for name, fill, border in (('ghost_ok.png', (63, 184, 201, 90), (111, 227, 216, 210)),
                               ('ghost_bad.png', (216, 60, 58, 90), (255, 112, 104, 220))):
        L = Lay(16, 16)
        L.rect(0, 0, 15, 15, fill)
        L.hl(0, 15, 0, border)
        L.hl(0, 15, 15, border)
        L.vl(0, 0, 15, border)
        L.vl(15, 0, 15, border)
        save(L.im, name)
    L = Lay(16, 16)
    wc = (255, 255, 255, 255)
    for (x, y, sx, sy) in ((0, 0, 1, 1), (15, 0, -1, 1), (0, 15, 1, -1), (15, 15, -1, -1)):
        for k in range(4):
            L.p(x + sx * k, y, wc)
            L.p(x, y + sy * k, wc)
    save(L.im, 'selecao.png')


# ================================================================ prévia
def preview(gr, art):
    W, H = 320, 208
    cols, rows = W // 16, H // 16
    im = Image.new('RGBA', (W, H))
    r = random.Random(SEED + 999)

    def tile(c, rr):
        return gr.crop((c * 16, rr * 16, c * 16 + 16, rr * 16 + 16))

    path_row = 9
    for ty in range(rows):
        for tx in range(cols):
            if ty == path_row or (tx == 10 and ty > path_row):
                t = tile(r.randint(0, 3), 1)
            else:
                v = r.random()
                if v < .80:
                    t = tile(r.randint(0, 3), 0)
                elif v < .86:
                    t = tile(4, 0)
                elif v < .91:
                    t = tile(r.choice([5, 5, 6]), r.choice([0, 1]) if True else 0)
                    if t.getpixel((0, 0))[:3] != t.getpixel((0, 0))[:3]:
                        pass
                elif v < .95:
                    t = tile(6, 0)
                elif v < .97:
                    t = tile(7, 0)
                else:
                    t = tile(r.choice([5, 6, 7]), 1)
            im.paste(t, (tx * 16, ty * 16))

    def cleared(tx, ty, fw, fh):
        for y in range(fh):
            for x in range(fw):
                im.paste(tile(4, 1), ((tx + x) * 16, (ty + y) * 16))

    # objetos: (img, tile_x, tile_y_do_rodapé, fw, fh)
    objs = []

    def put(img, tx, ty_bottom, fw=1, fh=1, clear=False):
        if clear:
            cleared(tx, ty_bottom - fh + 1, fw, fh)
        objs.append((ty_bottom, tx, img))

    def fr(img, i, w=16, h=None):
        h = h or img.height
        return img.crop((i * w, 0, i * w + w, h))

    put(art['hatch'], 8, 8, 2, 2, True)
    put(art['tower_2'], 12, 8, 2, 2, True)
    put(art['barraco'], 1, 3, 2, 2, True)
    put(art['casa'], 4, 3, 3, 2, True)
    put(art['deposito_1'], 15, 4, 2, 2, True)
    put(art['horta_1'], 1, 7, 2, 2, True)
    put(art['poco'], 4, 7, 2, 2, True)
    put(art['serraria'], 1, 12, 3, 2, True)
    put(art['ferrovelho'], 13, 12, 3, 2, True)
    put(fr(art['fogueira'], 1), 7, 6)
    put(art['gate'], 18, 9, 2, 2, False)
    put(art['horta_2'], 17, 7, 2, 2, True)
    put(art['deposito_2'], 7, 3, 2, 2, True)
    put(art['obra_2'], 5, 12, 2, 2, True)
    for (tx, ty, i) in ((10, 2, 0), (11, 3, 2), (17, 2, 3), (0, 9, 1), (19, 12, 2), (9, 12, 0), (16, 10, 3),
                        (14, 1, 1)):
        put(fr(art['tree'], i, 16, 32), tx, ty)
    for (tx, ty, i) in ((11, 10, 0), (7, 11, 1), (17, 11, 2)):
        put(fr(art['rubble'], i), tx, ty)
    put(art['stump'], 12, 5)
    objs.sort(key=lambda o: o[0])
    crop_im = art['crop']
    for ty_b, tx, img in objs:
        x = tx * 16
        y = (ty_b + 1) * 16 - img.height
        im.alpha_composite(img, (x, y))
        if img is art['horta_1']:
            for k, (cx, cy) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1))):
                im.alpha_composite(fr(crop_im, [3, 2, 1, 3][k]), ((tx + cx) * 16, (ty_b - 1 + cy) * 16))
        if img is art['horta_2']:
            for k, (cx, cy) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1))):
                im.alpha_composite(fr(crop_im, 3), ((tx + cx) * 16, (ty_b - 1 + cy) * 16))
    # pessoas
    for k, (px, py, d, f) in enumerate(((120, 136, 0, 1), (152, 128, 2, 3), (104, 104, 1, 2), (200, 140, 0, 0),
                                        (60, 140, 2, 0))):
        sheet = art['people'][k]
        im.alpha_composite(sheet.crop((f * 16, d * 16, f * 16 + 16, d * 16 + 16)), (px, py))
    im.alpha_composite(art['sleep'], (200, 124))
    # ícones
    im.alpha_composite(art['icons'], (4, 198))
    im.save(os.path.join(AQUI, 'preview.png'))
    im.resize((W * 3, H * 3), Image.NEAREST).save(os.path.join(AQUI, 'preview_3x.png'))
    # patch grande de chão para checar costura
    patch = Image.new('RGBA', (160, 96))
    for ty in range(6):
        for tx in range(10):
            if ty in (2, 3) and tx > 2:
                t = tile(r.randint(0, 3), 1)
            else:
                t = tile(r.randint(0, 3), 0)
            patch.paste(t, (tx * 16, ty * 16))
    patch.resize((480, 288), Image.NEAREST).save(os.path.join(AQUI, 'preview_chao_3x.png'))


def main():
    os.makedirs(SAIDA, exist_ok=True)
    art = {}
    gr = ground()
    art['tree'] = trees()
    art['stump'] = stump()
    art['rubble'] = rubble()
    art['hatch'] = hatch()
    for lvl in (1, 2, 3):
        art['tower_%d' % lvl] = tower(lvl)
    art['barraco'] = barraco()
    art['casa'] = casa()
    art['deposito_1'] = deposito_1()
    art['deposito_2'] = deposito_2()
    art['horta_1'] = horta_1()
    art['horta_2'] = horta_2()
    art['crop'] = crops()
    art['poco'] = poco()
    art['serraria'] = serraria()
    art['ferrovelho'] = ferrovelho()
    art['fogueira'] = fogueira()
    art['obra_2'] = obra(2)
    art['obra_3'] = obra(3)
    art['gate'] = gate()
    art['people'] = people()
    art['sleep'] = person_sleep()
    art['icons'] = icons()
    ui()
    light()
    ghosts()
    preview(gr, art)


if __name__ == '__main__':
    main()
