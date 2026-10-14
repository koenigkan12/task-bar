#!/usr/bin/env python3
"""Gera o ícone do executável Windows a partir da arte do jogo.

Base 16x16: o rádio aceso (quadro 3 de assets/art/env/radio_table.png) sobre o
fundo escuro do bunker. Ampliado sem suavização para 16..256 px.
Saída: tools/build/icon.ico (multi-tamanho) e tools/build/icon_256.png.
Rodar da raiz do repositório: python3 tools/build/make_icon.py
"""
from pathlib import Path

from PIL import Image

RAIZ = Path(__file__).resolve().parents[2]
RADIO = RAIZ / "assets/art/env/radio_table.png"
SAIDA = Path(__file__).resolve().parent
FUNDO = (61, 53, 46, 255)      # parede do bunker (3d352e)
BORDA = (20, 17, 15, 255)      # cor de fundo do projeto (140f0f)
TAMANHOS = [16, 24, 32, 48, 64, 128, 256]


def base_16() -> Image.Image:
    folha = Image.open(RADIO).convert("RGBA")
    quadro = folha.width // 3 if folha.width >= 48 else folha.width
    radio = folha.crop((folha.width - quadro, 0, folha.width, folha.height))
    img = Image.new("RGBA", (16, 16), FUNDO)
    # moldura de 1 px com cantos vazios (fica com cara de botão)
    for i in range(16):
        for p in ((i, 0), (i, 15), (0, i), (15, i)):
            img.putpixel(p, BORDA)
    for p in ((0, 0), (15, 0), (0, 15), (15, 15)):
        img.putpixel(p, (0, 0, 0, 0))
    radio = radio.crop(radio.getbbox() or (0, 0, radio.width, radio.height))
    x = (16 - radio.width) // 2
    y = 16 - 1 - radio.height
    img.alpha_composite(radio, (max(x, 0), max(y, 1)))
    return img


def main() -> None:
    base = base_16()
    grandes = {n: base.resize((n, n), Image.NEAREST) for n in TAMANHOS}
    grandes[256].save(SAIDA / "icon_256.png")
    grandes[256].save(SAIDA / "icon.ico", sizes=[(n, n) for n in TAMANHOS])
    print("icon.ico e icon_256.png gerados em", SAIDA)


if __name__ == "__main__":
    main()
