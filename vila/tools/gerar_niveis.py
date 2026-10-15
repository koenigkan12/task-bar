#!/usr/bin/env python3
"""Níveis novos de prédios: parte do desenho do nível anterior e acrescenta peças por cima
(mais pilha, telhado, máquina, luz), para a melhoria aparecer na vila.

Chamado pelo gerar_arte.py no fim (precisa das imagens que ele acabou de desenhar).
"""
import math

from PIL import Image

from gerar_arte import (Lay, finish, glow, roof_corr, save, OUT,
                        W0, W1, W2, W3, W4, R0, R1, R2, R3, R4, D0, D1, D2, D3, D4,
                        S0, S1, S2, S3, ST0, ST1, ST2, ST3, CY, CY2, CYD, OR, YE, OR2,
                        PL1, PL2, PL3, PK, PK2)


def grow(im, top=0, w=None):
    """Mesma arte com espaço livre em cima (o prédio cresce para o alto) e/ou mais largo."""
    w = w or im.width
    out = Image.new('RGBA', (w, im.height + top), (0, 0, 0, 0))
    out.alpha_composite(im, (0, top))
    return out


def add(base, L, fx=None, drop=(1, 1)):
    """Cola as peças novas (com contorno e sombra) por cima do prédio."""
    out = base.copy()
    out.alpha_composite(finish(L, fx, drop=drop))
    return out


def planks(L, x0, x1, y0, n):
    for i in range(n):
        y = y0 + i * 2
        L.rect(x0, y, x1, y + 1, W3 if i % 2 else W2)
        L.hl(x0, x1, y, W4 if i % 2 else W3)
        L.p(x1, y + 1, W0)


# ---------------------------------------------------------------- serraria
def serraria_2(base):
    im = grow(base, 6)
    L = Lay(im.width, im.height)
    # pilha de tábuas bem mais alta (mais madeira saindo)
    planks(L, 30, 45, 9, 6)
    # segundo cavalete com tora sendo cortada, na frente do telheiro
    L.rect(1, 36, 2, 42, W1)
    L.rect(9, 36, 10, 42, W1)
    L.ell(6, 35, 5, 2.2, R1)
    L.ell(6, 35, 4.2, 1.5, W3)
    L.p(2, 34, W4)
    return add(im, L)


def serraria_3(base):
    im = grow(base, 6)
    L = Lay(im.width, im.height)
    fx = Lay(im.width, im.height)
    planks(L, 30, 45, 13, 4)
    # telheiro novo sobre a madeira empilhada
    for x in (29, 45):
        L.rect(x, 6, x + 1, 13, W2)
        L.vl(x, 6, 13, W3)
    roof_corr(L, 27, 1, 47, 6, 1, R2, R1, R4, R0)
    # motor com correia ao lado da mesa de serra
    L.box(0, 31, 5, 38, D2, D3, D1)
    L.rect(1, 33, 4, 35, ST1)
    L.line(5, 32, 13, 30, OUT)
    glow(fx, 2, 32, CY, CY2)
    # lampião embaixo do telheiro novo
    fx.vl(37, 7, 8, '#1a1218')
    glow(fx, 37, 9, YE, OR)
    fx.p(36, 9, OR)
    fx.p(38, 9, OR)
    return add(im, L, fx)


# ---------------------------------------------------------------- ferro-velho
def ferrovelho_2(base):
    L = Lay(base.width, base.height)
    # fardos de sucata prensada em cima da pilha da direita
    for (x0, y0) in ((30, 20), (37, 21), (33, 15)):
        L.box(x0, y0, x0 + 6, y0 + 5, R2, R3, R1)
        L.hl(x0, x0 + 6, y0 + 2, D2)
        L.p(x0 + 2, y0 + 1, ST1)
        L.p(x0 + 4, y0 + 4, D3)
    return add(base, L)


def ferrovelho_3(base):
    im = ferrovelho_2(base)
    L = Lay(im.width, im.height)
    fx = Lay(im.width, im.height)
    # cabine do guindaste, com janela acesa
    L.box(14, 8, 24, 15, D2, D3, D1)
    L.hl(14, 24, 8, D4)
    L.rect(16, 10, 19, 12, OR)
    L.p(16, 10, YE)
    L.p(17, 10, YE)
    L.vl(21, 9, 14, D1)
    # carcaça de carro no gancho
    L.box(30, 20, 41, 24, R3, R4, R1)
    L.rect(32, 18, 38, 20, R2)
    L.rect(33, 19, 34, 19, D1)
    L.rect(36, 19, 37, 19, D1)
    L.ell(32.5, 25, 1.6, 1.2, OUT)
    L.ell(39.5, 25, 1.6, 1.2, OUT)
    glow(fx, 44, 12, CY, CY2)
    return add(im, L, fx)


# ---------------------------------------------------------------- poço → cisterna
def poco_3(base):
    im = grow(base, 10)
    L = Lay(im.width, im.height)
    fx = Lay(im.width, im.height)
    # caixa d'água de metal em cima dos postes
    L.rect(4, 2, 27, 11, ST1)
    L.hl(4, 27, 2, ST3)
    L.vl(4, 2, 11, ST2)
    L.vl(27, 2, 11, ST0)
    for y in (5, 9):
        L.hl(4, 27, y, ST0)
    L.hl(4, 27, 11, D1)
    # marcador de nível (azul) e cano descendo pelo poste
    L.rect(22, 3, 24, 9, D1)
    fx.rect(23, 5, 23, 9, CY2)
    fx.p(23, 5, CY)
    L.rect(28, 7, 29, 30, ST0)
    L.vl(28, 7, 30, ST2)
    L.p(29, 30, ST1)
    return add(im, L, fx)


# ---------------------------------------------------------------- galinheiro
def galinheiro_3(base):
    im = grow(base, 0, base.width)
    L = Lay(im.width, im.height)
    fx = Lay(im.width, im.height)
    # janela acesa e um puxadinho de ninhos na lateral
    L.box(1, 22, 8, 30, W2, W3, W1)
    L.hl(0, 9, 21, R3)
    L.hl(0, 9, 22, R1)
    for x in (2, 5):
        L.rect(x, 25, x + 1, 27, OUT)
        L.p(x, 27, '#f0e8d0')
    # lampião pendurado no beiral
    fx.vl(22, 12, 13, '#1a1218')
    glow(fx, 22, 14, YE, OR)
    fx.p(21, 14, OR)
    fx.p(23, 14, OR)
    return add(im, L, fx)


# ---------------------------------------------------------------- oficina
def oficina_3(base):
    im = grow(base, 0)
    L = Lay(im.width, im.height)
    fx = Lay(im.width, im.height)
    # segunda bancada com torno, e engrenagem grande na fachada
    L.box(34, 34, 45, 37, W2, W4, W0)
    L.rect(35, 38, 36, 42, W1)
    L.rect(43, 38, 44, 42, W1)
    L.box(38, 31, 42, 33, ST1, ST3, ST0)
    L.ell(40, 31, 1.6, 1.2, ST2)
    for i in range(10):
        a = i / 10 * 2 * math.pi
        L.p(int(10.5 + math.cos(a) * 4.5), int(15 + math.sin(a) * 4.5), ST1)
    L.ell(10.5, 15, 3.3, 3.3, ST2)
    L.ell(10.5, 15, 1.4, 1.4, D1)
    glow(fx, 40, 30, OR, OR2)
    return add(im, L, fx)


# ---------------------------------------------------------------- cozinha
def cozinha_2(base):
    im = grow(base, 0)
    L = Lay(im.width, im.height)
    fx = Lay(im.width, im.height)
    # toldo listrado na frente e panelões no fogão: refeição pra mais gente
    for x in range(0, 22):
        c = R3 if (x // 3) % 2 == 0 else '#c8b890'
        L.vl(x, 18, 20, c)
    L.hl(0, 21, 21, R1)
    for x in (0, 21):
        L.vl(x, 21, 34, W1)
    L.box(3, 31, 8, 34, ST1, ST3, ST0)
    L.box(10, 32, 14, 34, R2, R3, R1)
    fx.p(5, 29, '#c8c0c8')
    fx.p(6, 28, '#a8a0a8')
    fx.p(5, 27, '#888090')
    return add(im, L, fx)


# ---------------------------------------------------------------- estufa
def estufa_2(base):
    im = grow(base, 4)
    L = Lay(im.width, im.height)
    fx = Lay(im.width, im.height)
    # aspersores no telhado e luz rosa de crescimento em toda a fileira
    L.rect(6, 8, 40, 9, ST0)
    L.hl(6, 40, 8, ST2)
    for x in (9, 19, 29, 38):
        L.vl(x, 5, 7, ST1)
        L.p(x - 1, 5, ST2)
        L.p(x + 1, 5, ST2)
    for x in range(8, 42, 6):
        glow(fx, x, 22, PK, PK2)
    return add(im, L, fx)


def main(art):
    out = {}
    out['serraria_2'] = serraria_2(art['serraria'])
    out['serraria_3'] = serraria_3(art['serraria'])
    out['ferrovelho_2'] = ferrovelho_2(art['ferrovelho'])
    out['ferrovelho_3'] = ferrovelho_3(art['ferrovelho'])
    out['poco_3'] = poco_3(art['poco_2'])
    out['galinheiro_3'] = galinheiro_3(art['galinheiro_2'])
    out['oficina_3'] = oficina_3(art['oficina_2'])
    out['cozinha_2'] = cozinha_2(art['cozinha'])
    out['estufa_2'] = estufa_2(art['estufa'])
    for k, im in out.items():
        save(im, k + '.png')
    return out
