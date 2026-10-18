"""Barcos desenhados em 8 direções (pixel a pixel, sem girar sprite).

Gera assets/art/bote_8d.png e assets/art/barco_mascate_8d.png: 8 quadros lado a lado, na ordem
L, SE, S, SO, O, NO, N, NE (ângulo de tela = índice * 45°, y para baixo). Cada pixel é testado
contra o casco em 3/4 (o eixo y encolhe por K e a altura z sobe na tela), então a borda sai limpa
em qualquer direção. Constantes iguais às de scripts/view/boat_view.gd (K, âncora, tamanho do quadro).

Roda: python3 tools/barcos_8dir.py
"""
import math
from pathlib import Path
from PIL import Image

K = 0.72
WOOD = (193, 141, 117, 255)
RIM = (141, 98, 105, 255)
BLUE = (65, 106, 162, 255)
DARK = (67, 52, 85, 255)
SAIL = (204, 198, 186, 255)
SAIL2 = (165, 146, 165, 255)
RED = (201, 101, 91, 255)
YEL = (200, 171, 93, 255)
GRN = (147, 161, 102, 255)

ROOT = Path(__file__).resolve().parent.parent


def basis(d):
    a = d * math.pi / 4.0
    f = (math.cos(a), math.sin(a))
    r = (-math.sin(a), math.cos(a))
    return f, r


def to_local(sx, sy, z, f, r):
    wx, wy = sx, (sy + z) / K
    return wx * f[0] + wy * f[1], wx * r[0] + wy * r[1]


def proj(u, v, z, f, r):
    wx = u * f[0] + v * r[0]
    wy = u * f[1] + v * r[1]
    return wx, wy * K - z


def half_w(u, L, B):
    h = L / 2.0
    if abs(u) >= h:
        return -1.0
    if u > 0:   # proa fina
        return B / 2.0 * (1.0 - (u / h) ** 2) ** 0.8
    return B / 2.0 * (1.0 - (abs(u) / h) ** 6) ** 0.5   # popa cheia


def seg_dist(px, py, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
    qx, qy = ax + t * dx, ay + t * dy
    return math.hypot(px - qx, py - qy)


def in_tri(px, py, a, b, c):
    def s(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
    p = (px, py)
    d1, d2, d3 = s(p, a, b), s(p, b, c), s(p, c, a)
    neg = d1 < 0 or d2 < 0 or d3 < 0
    pos = d1 > 0 or d2 > 0 or d3 > 0
    if not (neg and pos):
        return True
    return min(seg_dist(px, py, a, b), seg_dist(px, py, b, c), seg_dist(px, py, c, a)) <= 0.45


def hull_frame(img, ox, d, fw, fh, ax, ay, L, B, zg, seats, crates=()):
    f, r = basis(d)
    for py in range(fh):
        for px in range(fw):
            sx, sy = px + 0.5 - ax, py + 0.5 - ay
            col = None
            # convés: dentro da borda de cima (altura zg)
            u, v = to_local(sx, sy, zg, f, r)
            hw = half_w(u, L, B)
            if hw > 0 and abs(v) <= hw:
                col = RIM if hw - abs(v) < 1.15 or u > L / 2.0 - 2.2 else WOOD
                for s in seats:
                    if abs(u - s) < 0.75 and hw - abs(v) >= 1.15:
                        col = RIM
            else:
                # costado: o casco entre a água (z=0) e a borda
                for zz in [zg * k / 6.0 for k in range(6)]:
                    u2, v2 = to_local(sx, sy, zz, f, r)
                    hw2 = half_w(u2, L, B) * (0.82 + 0.18 * zz / max(zg, 1))
                    if hw2 > 0 and abs(v2) <= hw2:
                        col = BLUE if zz < zg * 0.55 else RIM
                        break
            if col is not None:
                img.putpixel((ox + px, py), col)
            # caixas no convés (mascate)
            for (cu, cv, cs, cc) in crates:
                for hz, shade in ((zg + 3, cc), (zg + 1, RIM)):
                    u3, v3 = to_local(sx, sy, hz, f, r)
                    if abs(u3 - cu) <= cs and abs(v3 - cv) <= cs:
                        img.putpixel((ox + px, py), shade)
                        break
                else:
                    continue
                break


def sail_frame(img, ox, d, fw, fh, ax, ay, zg):
    f, r = basis(d)
    P = lambda u, z: proj(u, 0.0, z, f, r)
    main = (P(4, zg + 28), P(4, zg + 4), P(-17, zg + 4))
    jib = (P(4.5, zg + 26), P(4.5, zg + 5), P(20, zg + 3))
    near = math.sin(d * math.pi / 4.0)   # de frente/de costas a vela vira um risco
    for py in range(fh):
        for px in range(fw):
            sx, sy = px + 0.5 - ax, py + 0.5 - ay
            if in_tri(sx, sy, *jib):
                img.putpixel((ox + px, py), SAIL2)
            if in_tri(sx, sy, *main):
                img.putpixel((ox + px, py), SAIL)
    # mastro
    for z in range(zg, zg + 31):
        x, y = P(4, z)
        img.putpixel((ox + int(math.floor(ax + x)), int(math.floor(ay + y))), DARK)
    # bandeira no topo, sempre para trás (vento aparente de quem anda)
    for k in range(1, 5):
        x, y = P(4 - k, zg + 30)
        for dy in (0, 1):
            img.putpixel((ox + int(math.floor(ax + x)), int(math.floor(ay + y)) + dy), RED)
    _ = near


def make(name, fw, fh, ax, ay, L, B, zg, seats, crates=(), sail=False):
    img = Image.new("RGBA", (fw * 8, fh), (0, 0, 0, 0))
    for d in range(8):
        hull_frame(img, d * fw, d, fw, fh, ax, ay, L, B, zg, seats, crates)
        if sail:
            sail_frame(img, d * fw, d, fw, fh, ax, ay, zg)
    out = ROOT / "assets" / "art" / name
    img.save(out)
    print(out, img.size)


if __name__ == "__main__":
    make("bote_8d.png", 36, 26, 18, 15, 26, 10, 3, seats=(-3.5, 4.5))
    make("barco_mascate_8d.png", 64, 76, 32, 56, 46, 18, 5, seats=(-12, 11),
         crates=((-6, -4, 2.4, YEL), (-6, 4, 2.4, GRN)), sail=True)
