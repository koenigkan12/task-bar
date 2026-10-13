"""Paleta fixa do jogo (28 cores). TODA arte passa por aqui: `snap_image(img)` troca cada pixel
pela cor mais próxima da paleta (alfa preservado, só 0 ou 255). Nada de cor fora da paleta.

A cor SIGNAL (verde de mostrador de rádio) é RESERVADA: só aparece em sinais de atenção
(luz do rádio, balão de objetivo pago, ícones de aviso). Objetos comuns NUNCA usam essa cor.
"""
from PIL import Image

PALETTE = {
    "ink":    "#14110f",
    "dark1":  "#2a2420",
    "dark2":  "#3d352e",
    "dark3":  "#554a40",
    "conc1":  "#6e6359",
    "conc2":  "#8c8174",
    "conc3":  "#a99f90",
    "conc4":  "#c9bfae",
    "rust1":  "#5a2e1f",
    "rust2":  "#8a4a2a",
    "rust3":  "#b5683a",
    "rust4":  "#d98c4f",
    "amber1": "#a8741c",
    "amber2": "#e0a52e",
    "amber3": "#f6d36b",
    "amber4": "#fff0b8",
    "leaf1":  "#2f4a2a",
    "leaf2":  "#4f7a37",
    "leaf3":  "#7fa650",
    "leaf4":  "#b2c978",
    "skin1":  "#a9704f",
    "skin2":  "#d9a37a",
    "cloth1": "#3a4a5c",
    "cloth2": "#6f8aa3",
    "paper":  "#e9e2d0",
    "tomato": "#b8402e",
    "bean":   "#8a5a3c",
    "signal": "#5dff8a",
}


def _hex(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


RGB = {k: _hex(v) for k, v in PALETTE.items()}
_LIST = list(RGB.items())


def nearest(rgb):
    best, bd = None, 1e18
    for name, c in _LIST:
        d = (c[0] - rgb[0]) ** 2 + (c[1] - rgb[1]) ** 2 + (c[2] - rgb[2]) ** 2
        if d < bd:
            best, bd = name, d
    return best


def snap_image(img):
    """Devolve uma cópia RGBA com cores só da paleta e alfa binário."""
    img = img.convert("RGBA")
    px = img.load()
    cache = {}
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a < 128:
                px[x, y] = (0, 0, 0, 0)
                continue
            key = (r, g, b)
            if key not in cache:
                cache[key] = RGB[nearest(key)]
            c = cache[key]
            px[x, y] = (c[0], c[1], c[2], 255)
    return img


def check_image(path):
    """Retorna lista de cores fora da paleta (vazia = ok)."""
    img = Image.open(path).convert("RGBA")
    bad = set()
    allowed = set(RGB.values())
    for r, g, b, a in img.getdata():
        if a == 0:
            continue
        if a != 255 or (r, g, b) not in allowed:
            bad.add((r, g, b, a))
    return sorted(bad)
