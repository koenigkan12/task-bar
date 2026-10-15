"""Prédios redesenhados no estilo da ilha (sem contorno, paleta de 12 cores, luz de cima à esquerda).

Cada função devolve a imagem no mesmo tamanho da arte antiga (o jogo posiciona pelo tamanho).
Janela acesa usa as duas cores ACESO_A/ACESO_B: de dia o jogo troca por vidro escuro (tex_day).
Usado por estilo_ilha.py (TROCA); dá para ver sozinho: python3 vila/tools/predios_ilha.py
"""
import os
import random

from PIL import Image

from estilo_ilha import G, GS, Y, CR, MC, ME, D, AC, AE, LI, LC, VM

ACESO_A = (240, 196, 104)
ACESO_B = (250, 226, 150)


class Tela:
    def __init__(s, w, h):
        s.im = Image.new('RGBA', (w, h))
        s.px = s.im.load()
        s.w, s.h = w, h

    def p(s, x, y, c):
        if 0 <= x < s.w and 0 <= y < s.h:
            s.px[x, y] = c + (255,)

    def r(s, x0, y0, x1, y1, c):          # retângulo cheio, pontas inclusas
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                s.p(x, y, c)

    def hl(s, x0, x1, y, c):
        s.r(x0, y, x1, y, c)

    def vl(s, x, y0, y1, c):
        s.r(x, y0, x, y1, c)

    def ell(s, cx, cy, rx, ry, c):
        for y in range(int(cy - ry), int(cy + ry) + 1):
            for x in range(int(cx - rx), int(cx + rx) + 1):
                if ((x - cx) / max(rx, .5)) ** 2 + ((y - cy) / max(ry, .5)) ** 2 <= 1.0:
                    s.p(x, y, c)

    def tem(s, x, y):
        return 0 <= x < s.w and 0 <= y < s.h and s.px[x, y][3] > 0


# ---------------------------------------------------------------- peças comuns
def sombra(t, x0, x1, y):
    """Sombra no chão embaixo do prédio (tom de mato)."""
    t.r(x0 + 1, y, x1 + 1, y + 1, GS)


def tabuas(t, x0, y0, x1, y1, base=MC, risco=ME, passo=4, luz=None):
    """Parede de tábua em pé: cor base, fresta escura a cada `passo`, beirada de cima mais clara."""
    t.r(x0, y0, x1, y1, base)
    for x in range(x0 + passo - 1, x1, passo):
        t.vl(x, y0 + 1, y1, risco)
    if luz:
        t.hl(x0, x1, y0, luz)
    t.hl(x0, x1, y1, risco)


def tabuas_deitadas(t, x0, y0, x1, y1, base=MC, risco=ME, passo=3):
    t.r(x0, y0, x1, y1, base)
    for y in range(y0 + passo - 1, y1, passo):
        t.hl(x0, x1, y, risco)
    t.hl(x0, x1, y1, risco)


def telhado(t, x0, y0, x1, y1, base=LI, luz=LC, sombra_=D, passo=3):
    """Telhado visto de cima, inclinado para a frente: fileiras de telha, cumeeira clara, beiral escuro."""
    t.r(x0, y0, x1, y1, base)
    for y in range(y0 + 2, y1 - 1, passo):
        for x in range(x0, x1 + 1):
            if (x + y) % 4 != 0:
                t.p(x, y, luz if y == y0 + 2 else base)
            else:
                t.p(x, y, sombra_ if base == LI else ME)
    t.hl(x0, x1, y0, luz)
    t.hl(x0, x1, y0 + 1, luz)
    t.hl(x0, x1, y1, sombra_)


def chapa(t, x0, y0, x1, y1, base=LI, luz=LC, risco=D):
    """Chapa ondulada (telhado ou parede de barraco): listras verticais."""
    t.r(x0, y0, x1, y1, base)
    for x in range(x0, x1 + 1):
        if (x - x0) % 3 == 0:
            t.vl(x, y0, y1, luz)
        elif (x - x0) % 3 == 2:
            t.vl(x, y0, y1, risco if base == LI else ME)
    t.hl(x0, x1, y1, risco)


def janela(t, x0, y0, w=4, h=4, moldura=ME):
    t.r(x0 - 1, y0 - 1, x0 + w, y0 + h, moldura)
    t.r(x0, y0, x0 + w - 1, y0 + h - 1, ACESO_A)
    t.r(x0, y0, x0 + w // 2 - 1, y0 + h // 2 - 1, ACESO_B)
    if w >= 4:
        t.vl(x0 + w // 2, y0, y0 + h - 1, moldura)


def porta(t, x0, y0, w, h, cor=D, moldura=ME, macaneta=Y):
    t.r(x0 - 1, y0 - 1, x0 + w, y0 + h - 1, moldura)
    t.r(x0, y0, x0 + w - 1, y0 + h - 1, cor)
    t.p(x0 + w - 2, y0 + h // 2, macaneta)


def barril(t, x0, y0, w=6, h=8, base=ME, luz=MC, aro=D, tampa=None):
    t.r(x0, y0 + 1, x0 + w - 1, y0 + h - 1, base)
    t.vl(x0 + 1, y0 + 1, y0 + h - 2, luz)
    t.hl(x0, x0 + w - 1, y0 + 2, aro)
    t.hl(x0, x0 + w - 1, y0 + h - 3, aro)
    t.hl(x0 + 1, x0 + w - 2, y0, tampa or luz)
    t.hl(x0, x0 + w - 1, y0 + h - 1, D)


def caixote(t, x0, y0, x1, y1, base=MC, risco=ME):
    t.r(x0, y0, x1, y1, base)
    t.hl(x0, x1, y0, CR)
    t.r(x0, y0, x0, y1, risco)
    t.r(x1, y0, x1, y1, risco)
    t.hl(x0, x1, y1, risco)
    for i in range(1, min(x1 - x0, y1 - y0)):     # travessa em diagonal
        t.p(x0 + i, y1 - i, risco)


def tronco(t, x0, y0, comp, base=ME, luz=MC, ponta=Y):
    """Tora deitada vista de frente (ponta redonda mostrando os anéis)."""
    t.r(x0, y0, x0 + comp - 1, y0 + 3, base)
    t.hl(x0, x0 + comp - 1, y0, luz)
    t.r(x0 + comp - 3, y0, x0 + comp - 1, y0 + 3, ponta)
    t.p(x0 + comp - 2, y0 + 1, ME)


def pedras(t, x0, y0, x1, y1, seed=0):
    """Parede de pedra: blocos claros com junta lilás."""
    R = random.Random(seed)
    t.r(x0, y0, x1, y1, LC)
    for y in range(y0, y1 + 1, 3):
        off = R.randrange(0, 4)
        x = x0 - off
        while x <= x1:
            w = R.randrange(3, 6)
            t.r(max(x0, x), y, min(x1, x + w - 2), min(y1, y + 1), R.choice((CR, CR, LC)))
            x += w
    t.hl(x0, x1, y1, LI)


def solo(t, x0, y0, x1, y1):
    t.r(x0, y0, x1, y1, ME)
    for x in range(x0, x1 + 1, 2):
        t.p(x, y0, D)
    t.hl(x0, x1, y1, D)


# ---------------------------------------------------------------- poço
def poco_1():
    """Barril de chuva: lona esticada em quatro paus juntando água em dois barris."""
    t = Tela(32, 32)
    sombra(t, 4, 28, 30)
    for x in (5, 26):                                  # paus
        t.vl(x, 6, 29, ME)
        t.vl(x + 1, 6, 29, MC)
    for y in range(5, 12):                              # lona azul caída no meio
        sag = 0 if y < 7 else 1
        t.hl(5 + sag * (y - 6), 27 - sag * (y - 6), y, AC if y % 2 else AE)
    t.hl(5, 27, 5, CR)
    t.r(14, 11, 17, 14, AE)                             # bico
    barril(t, 8, 17, 7, 12, base=LI, luz=LC, aro=D, tampa=AC)
    barril(t, 17, 17, 7, 12, base=LI, luz=LC, aro=D, tampa=AC)
    t.r(15, 15, 16, 17, AE)
    t.p(15, 18, AC)
    return t.im


def poco_2():
    """Poço de pedra com telhadinho e manivela."""
    t = Tela(32, 32)
    sombra(t, 4, 28, 30)
    t.ell(16, 22, 11, 7, LC)                            # boca de pedra
    t.ell(16, 21, 11, 6, CR)
    for a in range(0, 22, 4):
        t.p(5 + a, 21 + (1 if a % 8 else 0), LC)
    t.ell(16, 21, 7, 4, D)                              # água lá no fundo
    t.ell(16, 22, 5, 2, AE)
    t.p(14, 22, AC)
    t.r(5, 26, 27, 28, LC)                              # frente da mureta
    for x in range(6, 27, 4):
        t.vl(x, 26, 28, LI)
    t.hl(5, 27, 29, LI)
    for x in (6, 25):                                   # postes
        t.r(x, 6, x + 1, 25, ME)
        t.vl(x, 6, 25, MC)
    t.hl(7, 25, 12, ME)                                 # eixo e corda
    t.vl(16, 13, 19, CR)
    t.r(15, 18, 17, 20, MC)                             # balde
    t.r(26, 11, 28, 13, D)                              # manivela
    for y in range(2, 8):                               # telhadinho
        t.hl(4 + (7 - y), 27 - (7 - y) + 1, y, LI if y % 2 else LC)
    t.hl(4, 28, 8, D)
    return t.im


def poco_3():
    """Cisterna: caixa d'água redonda em cima de pernas, cano até a torneira."""
    t = Tela(32, 42)
    sombra(t, 4, 28, 40)
    for x in (7, 24):                                   # pernas
        t.r(x, 18, x + 1, 39, ME)
        t.vl(x, 18, 39, MC)
    t.hl(8, 24, 29, ME)
    t.p(10, 28, ME); t.p(22, 28, ME)
    t.r(5, 7, 26, 19, LI)                               # tanque
    t.r(5, 7, 8, 19, LC)
    t.hl(5, 26, 10, D)
    t.hl(5, 26, 15, D)
    t.ell(15.5, 6, 10.5, 3, LC)                         # tampa
    t.ell(15.5, 5, 9, 2, CR)
    t.r(14, 2, 17, 4, LI)
    t.hl(5, 26, 19, D)
    t.r(20, 19, 21, 34, LI)                             # cano
    t.r(20, 34, 25, 35, LI)
    t.p(25, 36, AC)
    barril(t, 23, 33, 6, 7, base=ME, luz=MC, tampa=AC)
    return t.im


# ---------------------------------------------------------------- horta
def _pneu(t, cx, cy):
    t.ell(cx, cy, 7, 4.5, D)
    t.ell(cx, cy - 1, 7, 4, LI)
    t.ell(cx, cy - 1, 4.5, 2.5, ME)
    t.ell(cx, cy, 4, 2, D if False else ME)
    t.hl(int(cx) - 3, int(cx) + 3, int(cy) - 3, LC)


def horta_1():
    """Horta de pneu: quatro pneus com terra (as plantas o jogo desenha por cima)."""
    t = Tela(32, 32)
    for row in range(2):
        for col in range(2):
            _pneu(t, 9 + col * 14, 13 + row * 12)
    return t.im


def horta_2():
    """Canteiro: dois caixotes compridos de tábua com terra."""
    t = Tela(32, 32)
    sombra(t, 1, 30, 30)
    for row in range(2):
        y = 9 + row * 12
        t.r(1, y, 30, y + 6, MC)
        t.hl(1, 30, y, CR)
        solo(t, 3, y + 1, 28, y + 3)
        t.hl(1, 30, y + 6, ME)
        for x in (1, 15, 30):
            t.vl(x, y, y + 6, ME)
    return t.im


def horta_3():
    """Horta: três leiras com cerquinha e regador."""
    t = Tela(32, 32)
    sombra(t, 0, 31, 30)
    for row in range(2):
        y = 11 + row * 12
        solo(t, 1, y, 30, y + 4)
        t.hl(1, 30, y - 1, GS)
    for x in range(0, 32, 4):                           # cerca
        t.vl(x, 27, 30, MC)
        t.p(x, 27, CR)
    t.hl(0, 31, 28, ME)
    t.r(26, 3, 30, 6, LI)                               # regador
    t.r(27, 2, 29, 2, LC)
    t.p(25, 3, LI); t.p(24, 2, LI)
    return t.im


# ---------------------------------------------------------------- depósito
def deposito_1():
    """Caixotes: pilha de caixotes e barris debaixo de uma lona."""
    t = Tela(32, 32)
    sombra(t, 2, 29, 30)
    caixote(t, 3, 18, 13, 29)
    caixote(t, 14, 21, 22, 29)
    caixote(t, 6, 10, 13, 17)
    barril(t, 23, 21, 6, 9)
    for y in range(6, 11):                              # lona por cima de metade
        t.hl(13 - (10 - y), 30 - (10 - y) // 2, y, VM if y % 2 else ME)
    t.hl(16, 29, 11, ME)
    return t.im


def deposito_2():
    """Galpão: telhado de chapa, frente aberta com prateleira cheia."""
    t = Tela(32, 40)
    sombra(t, 1, 30, 38)
    chapa(t, 1, 6, 30, 17)
    t.hl(1, 30, 6, CR)
    t.hl(0, 31, 17, D)
    tabuas(t, 2, 18, 29, 37, luz=None)
    t.r(6, 21, 25, 37, D)                               # vão aberto
    for y in (25, 31):
        t.hl(6, 25, y, ME)
    for x, c in ((8, Y), (11, VM), (14, AC), (19, G), (22, Y)):
        t.r(x, 22, x + 1, 24, c)
    caixote(t, 8, 32, 13, 37)
    barril(t, 18, 29, 5, 8)
    return t.im


def deposito_3():
    """Depósito: celeiro de tábua com telhado de duas águas e portão duplo."""
    t = Tela(32, 48)
    sombra(t, 1, 30, 46)
    for y in range(4, 22):                              # telhado em empena
        meio = 15.5
        lar = min(15, 3 + (y - 4))
        x0, x1 = int(meio - lar), int(meio + lar)
        for x in range(x0, x1 + 1):
            c = ME if (x + y) % 3 == 0 else (VM if x < meio else ME)
            t.p(x, y, c if y > 5 else MC)
    t.hl(0, 31, 22, D)
    tabuas(t, 1, 23, 30, 45, luz=None)
    t.r(9, 31, 22, 45, ME)                              # portão
    t.r(10, 32, 15, 45, MC)
    t.r(16, 32, 21, 45, MC)
    for i in range(6):
        t.p(10 + i, 32 + i * 2, ME)
        t.p(21 - i, 32 + i * 2, ME)
    janela(t, 14, 15, 4, 3)
    t.r(3, 26, 6, 29, D)
    return t.im


# ---------------------------------------------------------------- moradia
def moradia_2():
    """Barraco: parede de tábua e chapa, telhado de chapa torto, janelinha e cano de fumaça."""
    t = Tela(32, 40)
    sombra(t, 1, 30, 38)
    chapa(t, 1, 10, 30, 19)
    t.hl(1, 30, 10, CR)
    t.r(23, 3, 25, 10, LI)                              # cano
    t.hl(22, 26, 3, D)
    t.hl(0, 31, 19, D)
    tabuas(t, 2, 20, 17, 37)
    chapa(t, 18, 20, 29, 37, base=LC, luz=CR, risco=LI)
    porta(t, 6, 27, 6, 10)
    janela(t, 21, 25, 5, 4)
    return t.im


def moradia_3():
    """Casa: tábua clara, telhado vermelho-terra, duas janelas e chaminé."""
    t = Tela(32, 48)
    sombra(t, 1, 30, 46)
    t.r(22, 4, 25, 14, LC)                              # chaminé
    t.r(22, 4, 25, 5, CR)
    t.hl(21, 26, 3, LI)
    for y in range(8, 25):
        lar = min(15, 6 + (y - 8))
        for x in range(int(15.5 - lar), int(15.5 + lar) + 1):
            linha = (y - 8) % 3 == 2
            t.p(x, y, ME if linha else (VM if x < 16 else ME if (x + y) % 5 == 0 else VM))
    t.hl(0, 31, 25, D)
    tabuas_deitadas(t, 1, 26, 30, 45, base=MC, risco=ME)
    porta(t, 13, 35, 6, 11)
    janela(t, 4, 30, 5, 5)
    janela(t, 23, 30, 5, 5)
    return t.im


def moradia_4():
    """Casa de pedra: parede de pedra, telhado de telha cinza, chaminé de pedra, janelas largas."""
    t = Tela(32, 52)
    sombra(t, 1, 30, 50)
    pedras(t, 22, 3, 26, 14, seed=4)
    t.hl(21, 27, 2, LI)
    telhado(t, 1, 10, 30, 27)
    pedras(t, 1, 28, 30, 49, seed=9)
    porta(t, 13, 38, 6, 12, cor=ME, moldura=LI)
    t.r(14, 39, 17, 41, MC)
    janela(t, 4, 32, 6, 5, moldura=LI)
    janela(t, 22, 32, 6, 5, moldura=LI)
    t.r(2, 46, 5, 49, G)                                # mato no pé
    t.p(3, 45, G)
    return t.im


# ---------------------------------------------------------------- serraria
def _serraria(t, nivel):
    w = 48
    y_teto = 8 if nivel == 1 else 10
    alto = t.h
    sombra(t, 1, w - 2, alto - 2)
    base = alto - 3
    # cobertura sobre a bancada
    if nivel == 1:
        for y in range(y_teto, y_teto + 9):
            t.hl(2, 30, y, MC if (y - y_teto) % 3 else ME)
        t.hl(2, 30, y_teto, CR)
    else:
        chapa(t, 1, y_teto, 33, y_teto + 11)
        t.hl(1, 33, y_teto, CR)
    yb = y_teto + (9 if nivel == 1 else 12)
    t.hl(1, 32, yb, D)
    for x in (3, 29):                                   # postes
        t.r(x, yb, x + 1, base, ME)
        t.vl(x, yb, base, MC)
    # bancada com a lâmina
    t.r(6, base - 9, 27, base - 6, MC)
    t.hl(6, 27, base - 9, CR)
    t.hl(6, 27, base - 6, ME)
    t.vl(8, base - 5, base, ME)
    t.vl(25, base - 5, base, ME)
    t.ell(17, base - 10, 3, 3, LC)
    t.ell(17, base - 10, 1.5, 1.5, LI)
    tronco(t, 9, base - 13, 9)
    # pilha de toras do lado
    toras = 3 if nivel == 1 else 4
    for i in range(toras):
        for j in range(toras - i):
            cx, cy = 36 + j * 4 + i * 2, base - 3 - i * 4
            t.ell(cx, cy, 2, 2, ME)
            t.ell(cx, cy, 1.4, 1.4, Y)
            t.p(cx, cy, MC)
    if nivel == 3:                                      # motor
        t.r(28, base - 8, 33, base - 2, LI)
        t.r(28, base - 8, 33, base - 8, LC)
        t.r(30, base - 6, 31, base - 5, VM)
        t.vl(31, base - 13, base - 9, D)
        t.p(31, base - 14, LC)
    return t.im


def serraria():
    return _serraria(Tela(48, 40), 1)


def serraria_2():
    return _serraria(Tela(48, 46), 2)


def serraria_3():
    return _serraria(Tela(48, 46), 3)


LOTE_1 = {'poco_1': poco_1, 'poco_2': poco_2, 'poco_3': poco_3,
          'horta_1': horta_1, 'horta_2': horta_2, 'horta_3': horta_3,
          'deposito_1': deposito_1, 'deposito_2': deposito_2, 'deposito_3': deposito_3,
          'moradia_2': moradia_2, 'moradia_3': moradia_3, 'moradia_4': moradia_4,
          'serraria': serraria, 'serraria_2': serraria_2, 'serraria_3': serraria_3}


def prancha(nomes_antigos, pasta_antiga, saida):
    """Antes (em cima) e depois (embaixo), no chão de grama, ampliado 3x."""
    novas = [(n, f()) for n, f in LOTE_1.items()]
    cw = max(i.width for _, i in novas) + 8
    ch = max(i.height for _, i in novas) + 6
    W = cw * len(novas)
    sheet = Image.new('RGBA', (W, ch * 2), G + (255,))
    for k, (n, im) in enumerate(novas):
        velho = os.path.join(pasta_antiga, n + '.png')
        if os.path.exists(velho):
            v = Image.open(velho).convert('RGBA')
            sheet.alpha_composite(v, (k * cw + 4, ch - 3 - v.height))
        sheet.alpha_composite(im, (k * cw + 4, ch * 2 - 3 - im.height))
    sheet.resize((W * 3, ch * 6), Image.NEAREST).save(saida)


if __name__ == '__main__':
    import sys
    aqui = os.path.dirname(os.path.abspath(__file__))
    prancha(None, os.path.join(aqui, '..', 'assets', 'art'), sys.argv[1] if len(sys.argv) > 1 else '/tmp/predios.png')
