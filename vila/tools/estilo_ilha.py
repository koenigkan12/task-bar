#!/usr/bin/env python3
"""Estilo da ilha (angrysnail, sem borda): passa a arte da vila para a paleta de 12 cores.

1. Gera a arte antiga (gerar_arte.py) numa pasta temporária.
2. Converte cada sprite: tira o contorno quase preto (vira o tom escuro da cor vizinha, ou some na
   beira de fora) e troca cada cor pela da paleta, escolhida pelo matiz e pelo brilho.
3. Troca as peças que já existem no estilo novo (árvores, barraca, escotilha, píer, sucata, naufrágios)
   pelas de vila/estilo-overworld/pecas_b, copiadas para tools/pecas_ilha/.
4. Desenha o chão da ilha (grama, beira de terra, espuma, sombra na água) pela máscara do balance.json.

Uso: python3 vila/tools/estilo_ilha.py   (depois: godot --headless --path vila --import)
"""
import colorsys
import json
import os
import random
import sys
import tempfile

from PIL import Image, ImageDraw

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.normpath(os.path.join(AQUI, '..'))
ARTE = os.path.join(RAIZ, 'assets', 'art')
PECAS = os.path.join(AQUI, 'pecas_ilha')
TILE = 16
MARGEM = 192   # água desenhada além do mapa, para a câmera não ver o fim do mundo


def hx(s):
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


# ---------------------------------------------------------------- a paleta (12 cores)
G = hx('93a166')    # grama
GS = hx('638473')   # sombra, mato
Y = hx('c8ab5d')    # outono, fogo
CR = hx('ccc6ba')   # creme: pedra, espuma, destaque
MC = hx('c18d75')   # madeira clara, pele
ME = hx('8d6269')   # madeira escura, terra
D = hx('433455')    # o "preto" do estilo
AC = hx('7ca5c5')   # água
AE = hx('416aa2')   # água funda
LI = hx('665f92')   # metal, telha
LC = hx('a592a5')   # lilás
VM = hx('c9655b')   # vermelho pontual
# Janela acesa: as duas cores que o jogo apaga de dia (world_view.tex_day) ficam fora da paleta de
# propósito, porque só aparecem à noite.
ACESO = {(255, 179, 71): (240, 196, 104), (255, 211, 107): (250, 226, 150)}
SOMBRA = {CR: LC, LC: LI, LI: D, MC: ME, ME: D, Y: MC, AC: AE, AE: LI, G: GS, GS: D, VM: ME, D: D}


def lum(c):
    return (c[0] + c[1] + c[2]) / 3


def rampa(c, pessoa=False):
    """Escolhe a rampa da paleta pelo matiz e o degrau pelo brilho (a arte antiga é escura)."""
    r, g, b = c
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    h *= 360
    L = lum(c)
    if s < .14 or l < .07:
        ram = [D, LI, LC, CR]
    elif 165 <= h < 200 and s > .45:
        ram = [AE, AE, AC, AC]               # ciano (vidro, luz fria)
    elif 165 <= h < 260:
        ram = [D, LI, LC, CR] if s < .35 else [D, AE, AC, CR]
    elif 260 <= h < 345:
        ram = [D, LI, LC, CR] if s < .5 else [LI, LC, LC, LC]   # rosa (cristal, flor): lilás
    elif h >= 345 or h < 14:
        ram = [D, ME, VM, MC] if s > .45 else [D, ME, ME, MC]
    elif h < 40:
        ram = [D, ME, MC, CR] if not (s > .7 and L > 120) else [ME, VM, VM, Y]
    elif h < 70:
        ram = [D, ME, Y, CR] if s > .3 else [D, ME, MC, CR]
    else:
        ram = [D, GS, G, CR] if s > .2 else [D, GS, GS, G]
    if pessoa:   # roupa do jogo é escura: sobe um degrau para as pessoas não virarem todas roxas
        k = 0 if L < 16 else 1 if L < 40 else 2 if L < 100 else 3
    else:
        k = 0 if L < 30 else 1 if L < 62 else 2 if L < 112 else 3
    return ram[k]


def pele(c):
    h, l, s = colorsys.rgb_to_hls(*(v / 255 for v in c))
    return 5 <= h * 360 < 40 and s > .25 and lum(c) > 45


def converter(im, pessoa=False):
    """Sprite antigo -> estilo novo: sem contorno escuro e na paleta.
    Pessoas (16 px) guardam o contorno, no roxo escuro da paleta: sem ele somem na grama."""
    im = im.convert('RGBA')
    w, h = im.size
    s = im.load()
    out = Image.new('RGBA', (w, h))
    o = out.load()
    contorno = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = s[x, y]
            if a == 0:
                continue
            if a < 200:   # sombra no chão: sombra chapada da grama
                o[x, y] = GS + (255,) if a >= 60 else (0, 0, 0, 0)
                continue
            if (r, g, b) in ACESO:
                o[x, y] = ACESO[(r, g, b)] + (255,)
            elif lum((r, g, b)) < 22:
                if pessoa:
                    o[x, y] = D + (255,)
                else:
                    contorno.append((x, y))
            elif pessoa and pele((r, g, b)):
                o[x, y] = (MC if lum((r, g, b)) > 100 else ME) + (255,)
            else:
                o[x, y] = rampa((r, g, b), pessoa) + (255,)
    # Contorno: na beira de fora some; dentro vira a sombra da cor que ele contorna.
    for x, y in contorno:
        viz = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        fora = any(not (0 <= a < w and 0 <= b < h) or s[a, b][3] < 60 for a, b in viz)
        cores = [o[a, b][:3] for a, b in viz if 0 <= a < w and 0 <= b < h and o[a, b][3] == 255]
        if fora:
            continue
        if not cores:
            o[x, y] = D + (255,)
            continue
        c = max(set(cores), key=cores.count)
        o[x, y] = SOMBRA.get(c, D) + (255,)
    return out


# ---------------------------------------------------------------- pessoas
def h(c):
    return '#%02x%02x%02x' % c


# Mesmo desenho do gerar_arte (cabeçudos 16x16, 3 direções x 5 quadros), cores da paleta.
PESSOAS = [
    # Joaquim: casaco verde, cachecol vermelho, cabelo e barba brancos
    dict(skin=MC, skin_d=ME, hair=LC, hair_d=LI, style='balding', beard=CR,
         jacket=GS, jacket_l=G, jacket_d=D, pants=LI, shoes=D, accent=VM, accent_l=MC, acc='scarf'),
    dict(skin=ME, skin_d=D, hair=D, hair_d=D, style='cap', cap=AE,
         jacket=AE, jacket_l=AC, jacket_d=LI, pants=LI, shoes=D, accent=AC, accent_l=CR, acc='zip'),
    dict(skin=MC, skin_d=ME, hair=ME, hair_d=D, style='hood', hood=LI,
         jacket=LI, jacket_l=LC, jacket_d=D, pants=D, shoes=D, accent=LC, accent_l=CR, acc='trim'),
    dict(skin=MC, skin_d=ME, hair=D, hair_d=D, style='bun',
         jacket=ME, jacket_l=MC, jacket_d=D, pants=LI, shoes=D, accent=Y, accent_l=CR, acc='belt'),
    dict(skin=ME, skin_d=D, hair=D, hair_d=D, style='bald',
         jacket=GS, jacket_l=G, jacket_d=D, pants=ME, shoes=D, accent=Y, accent_l=CR, acc='vest'),
    dict(skin=MC, skin_d=ME, hair=ME, hair_d=D, style='beanie', cap=VM,
         jacket=LI, jacket_l=LC, jacket_d=D, pants=AE, shoes=D, accent=VM, accent_l=MC, acc='scarf'),
    # Ela: cabelo comprido escuro, cachecol azul, mochila
    dict(skin=MC, skin_d=ME, hair=D, hair_d=D, hair_l=LI, style='long',
         jacket=LC, jacket_l=CR, jacket_d=LI, pants=D, shoes=D, accent=AC, accent_l=CR, acc='scarf',
         pack='small', pack_c=(ME, MC, D)),
]
MASCATE = dict(skin=MC, skin_d=ME, hair=LC, hair_d=LI, style='hat', beard=CR, cap=ME, cap_l=MC, cap_d=D, band=VM,
               jacket=GS, jacket_l=G, jacket_d=D, pants=LI, shoes=D, accent=Y, accent_l=CR, acc='belt',
               pack='big', pack_c=(ME, MC, D))


def _hexar(d):
    out = {}
    for k, v in d.items():
        if isinstance(v, tuple) and len(v) == 3 and all(isinstance(q, int) for q in v):
            out[k] = h(v)
        elif isinstance(v, tuple):
            out[k] = tuple(h(q) for q in v)
        else:
            out[k] = v
    return out


def sombra_chapada(im):
    """Sombra translúcida do jogo -> sombra chapada da grama (o estilo não tem transparência)."""
    p = im.load()
    for y in range(im.height):
        for x in range(im.width):
            a = p[x, y][3]
            if 0 < a < 200:
                p[x, y] = GS + (255,) if a >= 60 else (0, 0, 0, 0)
    return im


def pessoas(g):
    g.PEOPLE = [_hexar(d) for d in PESSOAS]
    g.MERCHANT = _hexar(MASCATE)
    g.EYE = h(D)
    velho = g.outline
    g.outline = lambda im, col=h(D): velho(im, col)
    try:
        folhas = g.people()
    finally:
        g.outline = velho
    return [sombra_chapada(f) for f in folhas]


# ---------------------------------------------------------------- peças prontas (pecas_ilha/)
def peca(nome):
    return Image.open(os.path.join(PECAS, nome + '.png')).convert('RGBA')


def folha(quadros, fw, fh, dy=0):
    """Quadros lado a lado, cada um centrado embaixo num quadro fw x fh."""
    sh = Image.new('RGBA', (fw * len(quadros), fh))
    for i, q in enumerate(quadros):
        sh.alpha_composite(q, (i * fw + (fw - q.width) // 2, fh - q.height - dy))
    return sh


def arvores():
    a1, a2, l1 = peca('arvore_amarela_1'), peca('arvore_amarela_2'), peca('arvore_lilas_1')
    return folha([a1, a2, l1, l1.transpose(Image.FLIP_LEFT_RIGHT)], 34, 44)


def sombra_arvore():
    im = Image.new('RGBA', (30, 10))
    ImageDraw.Draw(im).ellipse([0, 0, 29, 9], GS + (255,))
    return im


def toco():
    im = Image.new('RGBA', (16, 16))
    d = ImageDraw.Draw(im)
    d.ellipse([3, 10, 13, 15], GS + (255,))       # sombra
    d.rectangle([5, 8, 11, 13], ME + (255,))      # tronco
    d.rectangle([5, 8, 6, 13], MC + (255,))
    d.ellipse([4, 6, 12, 10], MC + (255,))        # corte
    d.ellipse([6, 7, 10, 9], Y + (255,))
    im.putpixel((8, 8), ME + (255,))
    for x, y in ((3, 13), (12, 13), (4, 14)):     # raízes
        im.putpixel((x, y), ME + (255,))
    return im


def pneu_solto():
    """Pneu deitado que o rio largou."""
    im = Image.new('RGBA', (16, 10))
    d = ImageDraw.Draw(im)
    d.ellipse([1, 2, 15, 9], GS + (255,))      # sombra
    d.ellipse([0, 0, 14, 8], D + (255,))
    d.ellipse([1, 0, 13, 6], LI + (255,))
    d.ellipse([4, 2, 10, 5], D + (255,))
    return im


def barco_encalhado():
    """Casco de barco virado e furado, encalhado na beira (não navega: é resto do mundo de antes)."""
    im = Image.new('RGBA', (28, 16))
    d = ImageDraw.Draw(im)
    d.ellipse([2, 6, 27, 15], GS + (255,))     # sombra
    d.polygon([(1, 7), (5, 2), (20, 1), (26, 5), (24, 11), (6, 12)], ME + (255,))
    d.polygon([(3, 7), (6, 3), (19, 2), (24, 5), (22, 9), (7, 10)], MC + (255,))
    for x in (8, 12, 16, 20):                  # tábuas do casco
        d.line([(x, 3), (x - 1, 10)], ME + (255,))
    d.polygon([(11, 4), (15, 4), (14, 7), (11, 7)], D + (255,))   # furo
    d.line([(13, 5), (14, 6)], LI + (255,))
    d.line([(24, 10), (27, 13)], CR + (255,))  # corda solta
    d.point((26, 14), CR + (255,))
    return im


def com(*partes, w=30, h=28):
    """Junta peças num quadro: (imagem, x, y) com y medido de baixo."""
    im = Image.new('RGBA', (w, h))
    for p, x, y in partes:
        im.alpha_composite(p, (x, h - p.height - y))
    return im


# Quadros do entulho (rubble.png, 30x28 cada). Os 2 últimos são de beira d'água: a vista usa eles nas
# células encostadas no rio (o que o rio trouxe), os outros no resto da ilha.
ENTULHO_BEIRA = 2


def entulho():
    pn = pneu_solto()
    quadros = [
        peca('sucata'), peca('chapa_ondulada'), peca('caixa_e_chapa'), peca('sucata_nova'), peca('pneus'),
        com((peca('barril'), 4, 2), (pn, 12, 0)),
        com((pn, 2, 6), (pn.transpose(Image.FLIP_LEFT_RIGHT), 11, 0)),
        com((peca('chapa_ondulada'), 0, 4), (peca('barril'), 19, 0)),
        # beira d'água
        barco_encalhado(),
        com((peca('boia_2'), 3, 1), (pn, 13, 0)),
    ]
    assert ENTULHO_BEIRA == 2
    return folha(quadros, 30, 28)


def fogueira():
    """Fogueira desenhada à mão em 4 quadros: pedras, duas toras cruzadas e a chama que balança.
    (Recortar o meio da peça do PixelLab trazia pedaços das toras de fora e cortava a chama.)"""
    W, H = 20, 26
    # chama: (linha a partir da base, meia-largura) por quadro; desloca o topo para dar o balanço
    formas = [
        [4, 4, 3, 3, 2, 2, 1, 1, 0],
        [4, 4, 4, 3, 2, 2, 1, 0, 0],
        [4, 4, 3, 3, 3, 2, 1, 1, 0, 0],
        [4, 3, 3, 3, 2, 1, 1, 0],
    ]
    balanco = [[0, 0, 0, 0, 1, 1, 1, 1, 2], [0, 0, 0, -1, -1, -1, -1, -2, -2],
               [0, 0, 0, 0, 0, 1, 1, 0, 0, -1], [0, 0, -1, -1, 0, 0, 1, 1]]
    fumaca = [[(11, 6), (12, 3)], [(9, 5), (10, 2)], [(10, 4), (9, 1)], [(12, 5), (11, 2)]]
    quadros = []
    for k in range(4):
        im = Image.new('RGBA', (W, H))
        d = ImageDraw.Draw(im)
        d.ellipse([3, H - 6, W - 4, H - 1], GS + (255,))               # sombra
        for x, y in ((2, H - 5), (5, H - 3), (9, H - 3), (13, H - 3), (16, H - 5), (3, H - 7), (15, H - 7)):
            d.rectangle([x, y, x + 1, y + 1], CR + (255,))             # pedras
            im.putpixel((x + 1, y + 1), LC + (255,))
        d.line([(4, H - 5), (15, H - 9)], ME + (255,), 2)                # toras cruzadas
        d.line([(4, H - 9), (15, H - 5)], MC + (255,), 2)
        cx, base = 10, H - 9
        for i, hw in enumerate(formas[k]):
            y = base - i
            x0 = cx - hw + balanco[k][i]
            x1 = cx + hw - 1 + balanco[k][i] if hw else x0
            d.line([(x0, y), (x1, y)], VM + (255,))
            if hw >= 2:
                d.line([(x0 + 1, y), (x1 - 1, y)], Y + (255,))
            if hw >= 3 and i < 4:
                d.line([(x0 + 2, y), (x1 - 2, y)], CR + (255,))
        for x, y in fumaca[k]:                                         # fagulha e fumaça
            im.putpixel((x, y + 4), Y + (255,))
            im.putpixel((x, y), LC + (255,))
        quadros.append(im)
    return folha(quadros, W, H)


def bote():
    """O bote que traz quem chega (de cima: casco de madeira, dois bancos, remo)."""
    im = Image.new('RGBA', (26, 12))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 2, 25, 11], AE + (255,))         # sombra na água
    d.ellipse([1, 0, 24, 9], ME + (255,))          # casco
    d.ellipse([3, 1, 22, 8], MC + (255,))
    d.rectangle([8, 2, 9, 7], ME + (255,))         # bancos
    d.rectangle([15, 2, 16, 7], ME + (255,))
    d.line([(11, 0), (14, 11)], CR + (255,))       # remo
    return im


def barco_mascate():
    """O barco do mascate (maior que o bote): casco, caixotes no convés, mastro com vela e bandeirinha.
    Folha de 2 quadros (a vela enfunada muda um pouco)."""
    W, H = 36, 34
    quadros = []
    for k in range(2):
        im = Image.new('RGBA', (W, H))
        d = ImageDraw.Draw(im)
        d.ellipse([1, 22, 34, 33], AE + (255,))          # sombra na água
        d.ellipse([2, 19, 33, 31], ME + (255,))          # casco
        d.ellipse([4, 20, 31, 28], MC + (255,))
        d.line([(5, 26), (30, 26)], ME + (255,))         # tábuas
        d.rectangle([7, 21, 12, 25], ME + (255,))        # caixotes
        d.rectangle([8, 21, 11, 23], Y + (255,))
        d.rectangle([22, 21, 27, 25], ME + (255,))
        d.rectangle([23, 21, 26, 23], G + (255,))
        d.line([(17, 3), (17, 24)], D + (255,))          # mastro
        b = k                                             # vela enfunando
        d.polygon([(18, 4), (18, 19), (28 + b, 19)], CR + (255,))
        d.line([(18, 19), (28 + b, 19)], LC + (255,))
        d.line([(19, 12), (23 + b, 16)], LC + (255,))
        d.polygon([(16, 6), (16, 18), (9 - b, 18)], LC + (255,))
        d.line([(17, 1), (17, 3)], D + (255,))
        d.line([(18, 1), (21 + b, 2)], VM + (255,))       # bandeirinha
        d.line([(18, 2), (20 + b, 2)], VM + (255,))
        quadros.append(im)
    return folha(quadros, W, H)


def banca():
    """A banca do mascate na praça: dois postes, toldo listrado e balcão de caixotes com mercadoria."""
    im = Image.new('RGBA', (30, 28))
    d = ImageDraw.Draw(im)
    d.ellipse([1, 23, 28, 27], GS + (255,))              # sombra
    d.rectangle([3, 8, 4, 24], ME + (255,))              # postes
    d.rectangle([25, 8, 26, 24], ME + (255,))
    for i in range(7):                                   # toldo listrado
        c = VM if i % 2 == 0 else CR
        d.rectangle([1 + i * 4, 3, 4 + i * 4, 9], c + (255,))
    d.line([(1, 9), (28, 9)], ME + (255,))
    for i in range(7):                                   # franja
        im.putpixel((2 + i * 4, 10), (VM if i % 2 == 0 else CR) + (255,))
    d.rectangle([4, 16, 25, 24], ME + (255,))            # balcão
    d.rectangle([5, 16, 24, 19], MC + (255,))
    d.line([(14, 16), (14, 24)], ME + (255,))
    for x, c in ((7, Y), (10, VM), (17, AC), (20, G), (23, Y)):   # mercadoria
        d.rectangle([x, 13, x + 1, 15], c + (255,))
    return im


def farol():
    """O farol perto do porto (sprite à parte, não vai no chão): quadro 0 com a lâmpada acesa, 1 apagada.
    Aceso = tem cama livre (o jogo gira o facho de luz)."""
    on = peca('farol_ilhota')
    off = on.copy()
    px = off.load()
    for y in range(off.height):
        for x in range(off.width):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in (Y, CR) and y < 20:
                px[x, y] = LI + (a,) if (r, g, b) == Y else LC + (a,)
    return folha([on, off], on.width, on.height)


def trepadeira():
    """Trepadeira que toma prédio largado: 3 tufos de 16x22 (0 pende do canto esquerdo, 1 do direito,
    2 sobe do chão), folha verde com florzinha lilás."""
    R = random.Random(11)
    quadros = []
    for k in range(3):
        im = Image.new('RGBA', (16, 22))
        px = im.load()
        fios = 7 if k < 2 else 7
        for f in range(fios):
            if k == 2:
                x, y, dy = R.randrange(2, 14), 21, -1
                comp = R.randrange(9, 20)
            else:
                x, y, dy = (R.randrange(0, 7) if k == 0 else R.randrange(9, 16)), 0, 1
                comp = R.randrange(6, 19)
            for i in range(comp):
                if 0 <= x < 16 and 0 <= y < 22:
                    px[x, y] = (D if R.random() < .15 else GS) + (255,)
                    if R.random() < .7:                     # folha
                        lx = x + R.choice((-1, 1))
                        if 0 <= lx < 16:
                            px[lx, y] = G + (255,)
                    if R.random() < .1:                      # flor
                        px[x, y] = LC + (255,)
                y += dy
                if R.random() < .3:
                    x += R.choice((-1, 1))
        quadros.append(im)
    return folha(quadros, 16, 22)


def flor_brilho():
    """Flor da Floração que brilha de noite: 2 quadros de 7x7 (lilás e creme)."""
    quadros = []
    for petala, miolo in ((LC, Y), (CR, Y)):
        im = Image.new('RGBA', (7, 7))
        px = im.load()
        px[3, 6] = GS + (255,)
        px[3, 5] = GS + (255,)
        px[2, 5] = G + (255,)
        for x, y in ((3, 1), (2, 2), (4, 2), (3, 3)):
            px[x, y] = petala + (255,)
        px[3, 2] = miolo + (255,)
        quadros.append(im)
    return folha(quadros, 7, 7)


def _nove(fill, borda, luz=None, sombra_=None, alfa=255, cantos=True):
    """Peça de 9 fatias 16x16 da interface (painel e botões)."""
    im = Image.new('RGBA', (16, 16))
    d = ImageDraw.Draw(im)
    d.rectangle([1, 1, 14, 14], fill + (alfa,))
    d.line([(1, 0), (14, 0)], borda + (255,))
    d.line([(1, 15), (14, 15)], borda + (255,))
    d.line([(0, 1), (0, 14)], borda + (255,))
    d.line([(15, 1), (15, 14)], borda + (255,))
    if not cantos:
        for xy in ((0, 0), (15, 0), (0, 15), (15, 15)):
            im.putpixel(xy, borda + (255,))
    if luz:
        d.line([(1, 1), (14, 1)], luz + (255,))
    if sombra_:
        d.line([(1, 14), (14, 14)], sombra_ + (255,))
    return im


def ui_panel():
    """Painel da interface na paleta da ilha: roxo escuro, borda lilás."""
    return _nove(D, LI, alfa=242, cantos=False)


def ui_button():
    """Botão: normal, mouse em cima (borda dourada), apertado."""
    sh = Image.new('RGBA', (48, 16))
    sh.alpha_composite(_nove(LI, D, LC, D), (0, 0))
    sh.alpha_composite(_nove(LI, Y, LC, D), (16, 0))
    sh.alpha_composite(_nove(D, LI, D, LI), (32, 0))
    return sh


def ui_button_off():
    return _nove(D, LI, D, D)


# ---------------------------------------------------------------- chão da ilha
def chao_ilha(rows, seed=3):
    import numpy as np
    R = random.Random(seed)
    th, tw = len(rows), len(rows[0])
    M = MARGEM
    W, H = tw * TILE + 2 * M, th * TILE + 2 * M
    ilha = np.zeros((H, W), bool)
    for ty, r in enumerate(rows):
        for tx, ch in enumerate(r):
            if ch == '#':
                ilha[M + ty * TILE:M + (ty + 1) * TILE, M + tx * TILE:M + (tx + 1) * TILE] = True
    # Beira em degraus de 8 px: alguns meios-tiles de terra a mais (só desenho, ninguém pisa ali).
    terra = ilha.copy()
    for ty in range(-1, th + 1):
        for tx in range(-1, tw + 1):
            for sy in (0, 1):
                for sx in (0, 1):
                    y0, x0 = M + ty * TILE + sy * 8, M + tx * TILE + sx * 8
                    if terra[y0:y0 + 8, x0:x0 + 8].any():
                        continue
                    viz = ilha[max(0, y0 - 8):y0 + 16, max(0, x0 - 8):x0 + 16]
                    if viz.sum() > 64 and R.random() < .28:
                        terra[y0:y0 + 8, x0:x0 + 8] = True

    def em(dx, dy):   # terra deslocada: em(dx,dy)[y,x] = terra[y-dy, x-dx]
        out = np.zeros_like(terra)
        ys = slice(max(0, dy), H + min(0, dy))
        xs = slice(max(0, dx), W + min(0, dx))
        yo = slice(max(0, -dy), H + min(0, -dy))
        xo = slice(max(0, -dx), W + min(0, -dx))
        out[ys, xs] = terra[yo, xo]
        return out

    im = np.zeros((H, W, 3), np.uint8)
    im[:] = AC
    agua = ~terra
    sombra = np.zeros_like(terra)
    for dx in range(0, 11):
        sombra |= em(dx, 3)
    im[sombra & agua] = AE
    BEIRA = 6
    face = np.zeros((H, W), np.int8)
    for k in range(BEIRA, 0, -1):
        face[em(0, k) & agua] = k
    im[(face == 1)] = D
    im[(face > 1)] = ME
    solido = terra | (face > 0)
    viz = em(1, 0) | em(-1, 0) | em(0, 1) | em(0, -1)
    s2 = np.zeros_like(terra)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        o = np.zeros_like(terra)
        ys = slice(max(0, dy), H + min(0, dy)); xs = slice(max(0, dx), W + min(0, dx))
        yo = slice(max(0, -dy), H + min(0, -dy)); xo = slice(max(0, -dx), W + min(0, -dx))
        o[ys, xs] = solido[yo, xo]
        s2 |= o
    espuma = s2 & ~solido
    rnd = np.random.default_rng(seed)
    # espuma com 2 px, recortada
    e2 = np.zeros_like(espuma)
    for dx, dy in ((1, 0), (-1, 0), (0, 1)):
        o = np.zeros_like(espuma)
        ys = slice(max(0, dy), H + min(0, dy)); xs = slice(max(0, dx), W + min(0, dx))
        yo = slice(max(0, -dy), H + min(0, -dy)); xo = slice(max(0, -dx), W + min(0, -dx))
        o[ys, xs] = espuma[yo, xo]
        e2 |= o
    e2 &= ~solido & (rnd.random((H, W)) < .55)
    im[espuma | e2] = CR
    # grama, com a beira de mato mais escura
    im[terra] = G
    baixo1 = terra & ~em(0, -1)
    baixo2 = terra & ~em(0, -2) & (rnd.random((H, W)) < .6)
    lados = terra & (~em(1, 0) | ~em(-1, 0)) & (rnd.random((H, W)) < .5)
    im[baixo1 | baixo2 | lados] = GS
    # tufos
    n = int(terra.sum() / 260)
    ys, xs = np.nonzero(terra)
    for i in R.sample(range(len(ys)), n):
        y, x = ys[i], xs[i]
        if y + 2 < H and terra[y + 2, x]:
            im[y, x] = GS; im[y + 1, x] = GS
            if R.random() < .5 and x + 2 < W and terra[y, x + 2]:
                im[y + 1, x + 2] = GS
        elif R.random() < .3:
            im[y, x] = CR if R.random() < .5 else Y      # florzinha
    # marquinhas de onda
    for _ in range(int(W * H / 9000)):
        x, y = R.randrange(4, W - 8), R.randrange(4, H - 4)
        if (im[y, x - 2:x + 8] == AC).all() and (im[y + 1, x - 2:x + 8] == AC).all():
            im[y, x + 1:x + 5] = CR; im[y + 1, x] = CR; im[y + 1, x + 5] = CR
    out = Image.fromarray(im, 'RGB').convert('RGBA')
    # naufrágios e enfeites na água (só desenho), longe da ilha
    lugares = []
    for nome in ('mastro_afundado', 'veleiro_virado', 'boia_1', 'boia_2', 'boia_1', 'mastro_afundado',
                 'barril', 'pneus', 'caixa_e_chapa', 'veleiro_virado', 'barril', 'boia_2', 'pneus', 'caixa_e_chapa'):
        s = peca(nome)
        if nome in ('mastro_afundado', 'veleiro_virado', 'pneus') and lugares.count(nome) == 1:
            s = s.transpose(Image.FLIP_LEFT_RIGHT)
        for _ in range(4000):
            x, y = R.randrange(8, W - s.width - 8), R.randrange(8, H - s.height - 8)
            if solido[max(0, y - 14):y + s.height + 14, max(0, x - 14):x + s.width + 14].any():
                continue
            # perto o bastante para a câmera ver (até ~10 tiles da beira)
            perto = solido[max(0, y - 150):y + s.height + 150, max(0, x - 150):x + s.width + 150].any()
            longe = any(abs(x - a) < 90 and abs(y - b) < 90 for a, b, _ in lugares_xy) if (lugares_xy := [l for l in lugares if isinstance(l, tuple)]) else False
            if perto and not longe:
                out.alpha_composite(s, (x, y))
                lugares.append((x, y, nome))
                break
        lugares.append(nome)
    return out


# ---------------------------------------------------------------- tudo
TROCA = {'tree': arvores, 'tree_sombra': sombra_arvore, 'stump': toco, 'rubble': entulho,
         'fogueira': fogueira, 'bote': bote, 'barco_mascate': barco_mascate, 'banca': banca, 'farol': farol, 'trepadeira': trepadeira, 'flor_brilho': flor_brilho,
         'ui_panel': ui_panel, 'ui_button': ui_button, 'ui_button_off': ui_button_off,
         'hatch': lambda: peca('bunker'), 'moradia_1': lambda: peca('barraca'), 'gate': lambda: peca('pier')}
MANTER = ('icons', 'light', 'ghost_ok', 'ghost_bad', 'selecao',
          'ground', 'person_sleep')


def main():
    sys.path.insert(0, AQUI)
    import gerar_arte as g
    tmp = tempfile.mkdtemp(prefix='arte_antiga_')
    g.SAIDA = tmp
    g.main()                       # arte antiga inteira, fora do projeto
    novas = {}
    for f in sorted(os.listdir(tmp)):
        if not f.endswith('.png'):
            continue
        nome = f[:-4]
        im = Image.open(os.path.join(tmp, f)).convert('RGBA')
        if nome in MANTER:
            novas[nome] = im
        elif nome.startswith('person_') or nome == 'merchant':
            continue
        else:
            novas[nome] = converter(im)
    g.SAIDA = tmp
    for f, im in zip(['person_%d' % i for i in range(len(PESSOAS))] + ['merchant'], pessoas(g)):
        novas[f] = im
    for nome, fn in TROCA.items():
        novas[nome] = fn()
    bal = json.load(open(os.path.join(RAIZ, 'data', 'balance.json')))
    novas['ilha'] = chao_ilha(bal['map']['island'])
    for nome, im in novas.items():
        im.save(os.path.join(ARTE, nome + '.png'))
    print('%d imagens em %s' % (len(novas), ARTE))


if __name__ == '__main__':
    main()
