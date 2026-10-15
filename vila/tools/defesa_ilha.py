"""Arte da defesa da vila (zumbis, muros, torres, mina) no estilo da ilha: paleta de 12 cores,
sem contorno nos prédios, luz de cima à esquerda. Zumbis guardam o contorno roxo (como as pessoas).

Uso: python3 vila/tools/defesa_ilha.py   (depois: godot --headless --path vila --import)
"""
import os

from PIL import Image

from estilo_ilha import G, GS, Y, CR, MC, ME, D, AC, AE, LI, LC, VM
from predios_ilha import Tela, sombra, tabuas, telhado, chapa, pedras, barril

AQUI = os.path.dirname(os.path.abspath(__file__))
ARTE = os.path.normpath(os.path.join(AQUI, '..', 'assets', 'art'))

PELE_Z = (138, 160, 118)    # pele de zumbi: verde apagado (perto da grama, mais cinza)
PELE_ZS = (101, 122, 98)


def salvar(im, nome):
    im.save(os.path.join(ARTE, nome + '.png'))


def contorno(t):
    """Contorno roxo escuro em volta do que foi desenhado (zumbis, como as pessoas)."""
    w, h = t.w, t.h
    marca = []
    for y in range(h):
        for x in range(w):
            if t.px[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if t.tem(x + dx, y + dy):
                        marca.append((x, y))
                        break
    for x, y in marca:
        t.p(x, y, D)


# ---------------------------------------------------------------- zumbis
def _zumbi_quadro(t, ox, f, grande=False):
    """Um quadro de zumbi andando para a direita, braços esticados. f = 0..3."""
    k = 1.5 if grande else 1.0
    def r(x0, y0, x1, y1, c):
        t.r(ox + int(x0 * k), int(y0 * k), ox + int((x1 + 1) * k) - 1, int((y1 + 1) * k) - 1, c)
    bob = (0, 1, 0, 1)[f]
    passo = (0, 1, 0, -1)[f]
    # pernas
    r(6 + passo, 12, 7 + passo, 14, ME)
    r(9 - passo, 12, 10 - passo, 14, ME)
    r(6 + passo, 15, 7 + passo, 15, D)
    r(9 - passo, 15, 10 - passo, 15, D)
    # tronco com roupa rasgada
    r(5, 7 + bob, 10, 12, LI)
    r(5, 7 + bob, 6, 11, LC)
    r(8, 11, 9, 12, PELE_ZS)          # rasgo
    # cabeça caída para a frente
    r(6, 2 + bob, 10, 6 + bob, PELE_Z)
    r(6, 2 + bob, 7, 3 + bob, (170, 188, 150))
    r(9, 4 + bob, 9, 4 + bob, VM)      # olho
    r(7, 6 + bob, 9, 6 + bob, PELE_ZS)
    r(6, 1 + bob, 9, 1 + bob, ME)      # cabelo ralo
    # braços esticados
    r(10, 8 + bob, 13, 9 + bob, PELE_Z)
    r(10, 9 + bob, 12, 9 + bob, PELE_ZS)


def zumbi():
    t = Tela(64, 16)
    for f in range(4):
        _zumbi_quadro(t, f * 16, f)
    contorno(t)
    return t.im


def zumbi_chefe():
    t = Tela(96, 24)
    for f in range(4):
        _zumbi_quadro(t, f * 24, f, grande=True)
        # cicatriz e ombreira de sucata
        t.r(f * 24 + 7, 10, f * 24 + 11, 11, LC)
        t.r(f * 24 + 8, 4, f * 24 + 9, 4, VM)
    contorno(t)
    return t.im


# ---------------------------------------------------------------- muros (miniatura do menu)
def muro(nivel):
    """16x16: um pedaço de muro com dois postes. 1 arame, 2 madeira, 3 concreto, 4 aço."""
    t = Tela(16, 16)
    sombra(t, 1, 14, 14)
    if nivel == 1:
        for x in (2, 13):
            t.r(x, 5, x + 1, 13, ME)
            t.p(x, 5, MC)
        for y in (7, 10):
            for x in range(3, 13):
                t.p(x, y + (x % 2), LC)
            for x in range(4, 13, 3):
                t.p(x, y - 1, CR)
    elif nivel == 2:
        tabuas(t, 1, 5, 14, 13, MC, ME, 3, luz=CR)
        for x in range(1, 15, 3):
            t.p(x, 4, MC)
    elif nivel == 3:
        pedras(t, 1, 5, 14, 13, seed=3)
        t.hl(1, 14, 4, CR)
    else:
        t.r(1, 4, 14, 13, LI)
        t.hl(1, 14, 4, CR)
        for x in (2, 7, 12):
            t.r(x, 5, x + 1, 12, LC)
            t.p(x, 7, D)
            t.p(x, 10, D)
        t.hl(1, 14, 13, D)
    return t.im


# ---------------------------------------------------------------- torres
def torre_arq(nivel):
    """Torre arqueira 2x2: plataforma de madeira alta, arqueiro com o arco, bandeira."""
    t = Tela(32, 44)
    sombra(t, 3, 28, 42)
    base = 42
    # pernas (madeira; nível 3 em pedra)
    if nivel >= 3:
        pedras(t, 6, 24, 25, base, seed=8)
    else:
        for x in (6, 24):
            t.r(x, 20, x + 2, base, ME)
            t.vl(x, 20, base, MC)
        for y in range(24, base, 6):     # travessas em X
            for i in range(0, 16):
                t.p(8 + i, y + i * 5 // 16, ME)
                t.p(23 - i, y + i * 5 // 16, ME)
    # plataforma
    tabuas(t, 3, 14, 28, 20, MC, ME, 3, luz=CR)
    if nivel >= 2:
        chapa(t, 3, 17, 28, 20)
    # telhadinho
    telhado(t, 4, 2, 27, 7, LI if nivel < 3 else VM, LC if nivel < 3 else MC, D)
    t.r(6, 8, 7, 13, ME)
    t.r(24, 8, 25, 13, ME)
    # arqueiro
    t.r(14, 9, 17, 13, LI)
    t.r(14, 6, 17, 8, MC)
    t.p(16, 7, D)
    for i in range(5):                   # arco
        t.p(19, 8 + i, ME if i in (0, 4) else Y)
    t.p(20, 9, ME)
    t.p(20, 11, ME)
    t.hl(17, 19, 10, CR)                 # flecha
    # bandeira
    t.vl(27, 0, 4, ME)
    t.r(28, 0, 30, 2, VM if nivel < 3 else Y)
    return t.im


def canhao(nivel):
    """Canhão 2x2: base de sacos/pedra, cano de metal apontando para a frente."""
    t = Tela(32, 32)
    sombra(t, 2, 29, 30)
    if nivel >= 2:
        pedras(t, 2, 18, 29, 30, seed=11)
    else:
        for i, x in enumerate(range(2, 30, 7)):    # sacos de areia
            t.r(x, 20, x + 6, 30, MC if i % 2 else Y)
            t.hl(x, x + 6, 20, CR)
            t.hl(x, x + 6, 30, ME)
    # rodas
    for x in (7, 22):
        t.ell(x, 20, 4, 4, ME)
        t.ell(x, 20, 2, 2, MC)
        t.p(x, 20, D)
    # cano
    t.r(9, 10, 22, 18, LI)
    t.r(9, 10, 22, 11, LC)
    t.r(20, 8, 24, 18, LI if nivel < 3 else D)
    t.r(20, 8, 24, 9, CR)
    t.ell(22, 13, 1, 2, D)
    if nivel >= 3:
        t.hl(9, 22, 14, Y)
    return t.im


def choque(nivel):
    """Torre de choque 2x2: poste de metal com bobina e bola no topo (gasta energia)."""
    t = Tela(32, 44)
    sombra(t, 4, 27, 42)
    t.r(5, 34, 26, 42, LI)
    t.hl(5, 26, 34, LC)
    t.r(13, 8, 18, 34, LI)
    t.vl(13, 8, 34, LC)
    for y in range(12, 33, 3):           # bobina
        t.hl(11, 20, y, Y if nivel < 2 else MC)
        t.hl(11, 20, y + 1, ME)
    t.ell(15.5, 5, 5, 5, AE)
    t.ell(14.5, 4, 3, 3, AC)
    t.p(13, 2, CR)
    t.r(8, 37, 10, 39, VM)               # luz de aviso
    return t.im


def holofote():
    """Holofote 1x1: tripé com o farol virado para cima."""
    t = Tela(16, 24)
    sombra(t, 2, 13, 22)
    t.vl(4, 14, 22, ME)
    t.vl(11, 14, 22, ME)
    t.vl(8, 14, 22, ME)
    t.r(3, 6, 12, 13, LI)
    t.hl(3, 12, 6, LC)
    t.r(5, 3, 10, 6, CR)
    t.r(6, 4, 9, 5, (250, 226, 150))
    t.p(6, 4, (255, 255, 240))
    return t.im


def mina():
    """Mina 1x1: tampa redonda enterrada, com pino e luzinha."""
    t = Tela(16, 16)
    t.ell(8, 11, 5, 3, GS)
    t.ell(8, 10, 4, 2.5, LI)
    t.ell(7, 9, 2, 1, LC)
    t.r(7, 6, 8, 8, ME)
    t.p(8, 6, VM)
    return t.im


def tudo():
    salvar(zumbi(), 'zumbi')
    salvar(zumbi_chefe(), 'zumbi_chefe')
    for n in range(1, 5):
        salvar(muro(n), 'muro_%d' % n)
    for n in range(1, 4):
        salvar(torre_arq(n), 'torre_arq_%d' % n)
        salvar(canhao(n), 'canhao_%d' % n)
    for n in range(1, 3):
        salvar(choque(n), 'choque_%d' % n)
    salvar(holofote(), 'holofote')
    salvar(mina(), 'mina')


if __name__ == '__main__':
    tudo()
    print('defesa: arte salva em', ARTE)
