"""SFX curtos: macios, grave dominante, sempre com low-pass (sem agudos duros).
Cada função devolve um array float; `make_all.py` normaliza o pico em -6 dBFS e codifica em OGG.
Os níveis relativos entre sons (click bem baixo etc.) são aplicados em runtime pelo AudioManager
(tabela SFX_GAIN_DB), então aqui todos têm o mesmo pico."""
import numpy as np
from synth import *


def pk(x, w=1.0):
    p = peak(x)
    return x / p * w if p > 0 else x


def finish(x, fc=4000.0, a=0.002, r=0.012):
    return fade_edges(lp(x, fc, 6), a, r)


def glide(n, f0, f1, tau):
    t = tt(n)
    return osc(f1 + (f0 - f1) * np.exp(-t / tau))


def click():
    r = rng(11)
    n = n_of(0.05)
    nz = lp(white(n, r), 1800, 2) * env_decay(n, 0.004)
    body = osc(190, n) * env_ad(n, 0.0006, 0.008)
    return finish(pk(nz, 0.6) + pk(body, 0.7), 2600)


def hover():
    r = rng(12)
    n = n_of(0.04)
    body = osc(330, n) * env_ad(n, 0.006, 0.010)
    nz = lp(white(n, r), 900, 2) * env_ad(n, 0.004, 0.008)
    return finish(pk(body, 0.7) + pk(nz, 0.2), 2000)


def buy():
    r = rng(13)
    n = n_of(0.55)
    out = np.zeros(n)
    # clique de caixa registradora de lata
    c = lp(white(n_of(0.05), r), 1500, 2) * env_decay(n_of(0.05), 0.006)
    add(out, pk(c, 0.5), 0)
    add(out, pk(osc(150, n_of(0.05)) * env_ad(n_of(0.05), 0.001, 0.012), 0.5), 0)

    def ting(f, tau, n_len):
        t = tt(n_len)
        s = (osc(f, n_len) * 1.0 + osc(f * 1.47, n_len) * 0.45 + osc(f * 2.13, n_len) * 0.2)
        return s * env_ad(n_len, 0.001, tau)
    add(out, pk(ting(1180, 0.09, n_of(0.4)), 0.8), n_of(0.035))
    add(out, pk(ting(1570, 0.12, n_of(0.45)), 0.9), n_of(0.115))
    return finish(out, 3600, 0.001, 0.05)


def _hammer(v):
    r = rng(20 + v)
    n = n_of(0.7)
    f_pipe = [205.0, 250.0, 175.0][v]
    thump = glide(n, 115 + 12 * v, 55, 0.025) * env_ad(n, 0.0008, 0.035)
    impact = lp(white(n, r), 800, 2) * env_decay(n, 0.006)
    kick = np.zeros(n)
    kick[:n_of(0.004)] = r.standard_normal(n_of(0.004))
    ring1 = resonator(kick, f_pipe, 55)
    ring2 = resonator(kick, f_pipe * 2.76, 35)
    out = pk(thump, 0.9) + pk(impact, 0.35) + pk(ring1, 0.8) * 1.0 + pk(ring2, 0.25)
    out = out * (0.4 + 0.6 * env_decay(n, 0.25))  # ressonância morre abafada
    return finish(out, 2800, 0.0006, 0.08)


def hammer_1(): return _hammer(0)
def hammer_2(): return _hammer(1)
def hammer_3(): return _hammer(2)


def dig():
    r = rng(30)
    n = n_of(0.75)
    t = tt(n)
    grains = lp(white(n, r), 35, 2)
    grains = np.abs(grains) / max(np.abs(grains).max(), 1e-9)
    scrape = lp(white(n, r), 1300, 3) * (0.35 + 0.65 * grains) * env_swell(n, 0.06, 0.22) * (t < 0.5)
    drop = np.zeros(n)
    add(drop, glide(n_of(0.2), 100, 55, 0.03) * env_ad(n_of(0.2), 0.002, 0.05), n_of(0.5))
    add(drop, lp(white(n_of(0.15), r), 700, 2) * env_decay(n_of(0.15), 0.025), n_of(0.5), 0.5)
    return finish(pk(scrape, 0.6) + pk(drop, 0.8), 2600, 0.01, 0.05)


def knock():
    r = rng(31)
    n = n_of(0.55)
    out = np.zeros(n)
    for i, t0 in enumerate([0.0, 0.19, 0.42]):
        m = n_of(0.25)
        a = 0.9 if i < 2 else 0.6
        body = glide(m, 170, 105, 0.02) * env_ad(m, 0.001, 0.045)
        kick = np.zeros(m)
        kick[:n_of(0.003)] = r.standard_normal(n_of(0.003))
        box = resonator(kick, 340 + 20 * i, 18)
        click_ = lp(white(m, r), 1100, 2) * env_decay(m, 0.004)
        add(out, (pk(body, 0.8) + pk(box, 0.5) + pk(click_, 0.3)) * a, n_of(t0))
    return finish(out, 2600, 0.0006, 0.06)


def scrap():
    r = rng(32)
    n = n_of(0.6)
    out = np.zeros(n)
    for t0, f, a in [(0.0, 760, 1.0), (0.08, 1310, 0.7), (0.15, 940, 0.8), (0.27, 1720, 0.5), (0.36, 610, 0.6)]:
        m = n_of(0.3)
        ff = f * r.uniform(0.96, 1.04)
        s = osc(ff, m) + 0.6 * osc(ff * 1.52, m) + 0.35 * osc(ff * 2.31, m)
        s = s * env_ad(m, 0.0008, r.uniform(0.04, 0.08))
        nz = lp(white(m, r), 2200, 2) * env_decay(m, 0.01)
        add(out, pk(s, 0.8) * a + pk(nz, 0.25) * a, n_of(t0))
    return finish(out, 3300, 0.001, 0.05)


def harvest():
    r = rng(33)
    n = n_of(0.35)
    env = np.abs(lp(white(n, r), 45, 2))
    env = env / env.max()
    rustle = bp(white(n, r), 500, 2400, 2) * (0.3 + 0.7 * env) * env_swell(n, 0.03, 0.15)
    pop = glide(n_of(0.2), 380, 250, 0.03) * env_ad(n_of(0.2), 0.002, 0.045)
    out = pk(rustle, 0.5)
    add(out, pk(pop, 0.8), n_of(0.1))
    return finish(out, 3000, 0.005, 0.06)


def pour():
    r = rng(34)
    n = n_of(1.0)
    flow = bp(white(n, r), 280, 1500, 2)
    mod = 0.65 + 0.35 * lp(white(n, r), 14, 2) / 0.35
    flow = flow * np.clip(mod, 0.2, 1.4) * env_swell(n, 0.12, 0.3)
    out = pk(flow, 0.6)
    for _ in range(14):
        m = n_of(0.05)
        f0 = r.uniform(420, 900)
        b = osc(np.linspace(f0, f0 * 1.7, m)) * env_ad(m, 0.004, 0.015)
        add(out, b, int(r.integers(n_of(0.05), n - m - 1)), r.uniform(0.08, 0.22))
    return finish(out, 3000, 0.02, 0.1)


def radio_on():
    r = rng(35)
    n = n_of(1.0)
    t = tt(n)
    out = np.zeros(n)
    # clique do botão + estrondo baixo
    add(out, pk(glide(n_of(0.15), 90, 60, 0.02) * env_ad(n_of(0.15), 0.001, 0.04), 0.8), 0)
    add(out, pk(lp(white(n_of(0.05), r), 1200, 2) * env_decay(n_of(0.05), 0.006), 0.4), 0)
    # válvulas esquentando: chiado que sobe e desce
    hiss = bp(white(n, r), 300, 3200, 2) * (1 - np.exp(-t / 0.12)) * np.exp(-t / 0.7)
    out += pk(hiss, 0.45)
    # apito de aquecimento (afina de baixo para cima)
    m = n_of(0.5)
    f = 220 + 300 * (1 - np.exp(-np.arange(m) / SR / 0.12))
    whistle = osc(f) * env_swell(m, 0.05, 0.3)
    add(out, pk(whistle, 0.35), n_of(0.08))
    out += osc(100, n) * 0.12 * np.exp(-t / 0.8)
    return finish(out, 3200, 0.001, 0.12)


def tune():
    r = rng(36)
    n = n_of(1.3)
    t = tt(n)
    f = 330 + 1500 * np.exp(-t / 0.4)
    whistle = osc(f) * np.minimum(1, t / 0.08) * np.exp(-t / 0.55)
    # estações passando: pedaços de ruído/garbled
    nz = bp(white(n, r), 400, 2200, 2)
    gate = 0.5 + 0.5 * lfo(n, 7)
    sweep = nz * (0.35 + 0.65 * np.exp(-((t - 0.35) / 0.25) ** 2)) * (0.5 + 0.5 * gate)
    out = pk(whistle, 0.45) + pk(sweep, 0.45)
    out *= env_swell(n, 0.03, 0.25)
    add(out, pk(osc(660, n_of(0.08)) * env_swell(n_of(0.08), 0.01, 0.04), 0.5), n_of(1.0))  # "travou"
    return finish(out, 3000, 0.01, 0.15)


def blip():
    r = rng(37)
    n = n_of(0.28)
    out = np.zeros(n)
    m1, m2 = n_of(0.07), n_of(0.1)
    add(out, osc(880, m1) * env_swell(m1, 0.008, 0.03), n_of(0.0), 0.8)
    add(out, osc(660, m2) * env_swell(m2, 0.01, 0.05), n_of(0.075), 0.8)
    out += pk(bp(white(n, r), 400, 2500, 2), 0.1) * env_swell(n, 0.01, 0.1)
    return finish(out, 2400, 0.002, 0.06)


def error():
    n = n_of(0.4)
    t = tt(n)
    saw = 2 * ((110 * t) % 1.0) - 1
    saw = lp(saw, 520, 2)
    g = np.zeros(n)
    for t0 in (0.0, 0.17):
        m = n_of(0.11)
        g[n_of(t0):n_of(t0) + m] += env_swell(m, 0.01, 0.04)
    return finish(saw * g, 900, 0.002, 0.05)


def _step(v):
    r = rng(40 + v)
    n = n_of(0.16)
    body = glide(n, 85 - 12 * v, 52, 0.02) * env_ad(n, 0.001, 0.035)
    nz = lp(white(n, r), 720 - 150 * v, 2) * env_decay(n, 0.015) * (1 + 0.6 * np.sin(2 * np.pi * (30 + 10 * v) * tt(n)))
    grit = bp(white(n, r), 800, 2000, 2) * env_decay(n, 0.008)
    return finish(pk(body, 0.8) + pk(nz, 0.6) + pk(grit, 0.12), 1800, 0.0008, 0.04)


def step_1(): return _step(0)
def step_2(): return _step(1)


def hatch_open():
    r = rng(38)
    n = n_of(1.7)
    t = tt(n)
    # rangido de dobradiça: serrilha com frequência subindo, tremida
    f = 150 + 110 * np.clip(t / 1.0, 0, 1) ** 1.3
    ph = 2 * np.pi * np.cumsum(f) / SR
    saw = sum(np.sin((h + 1) * ph) / (h + 1) for h in range(10))
    jitter = np.clip(0.55 + 0.45 * lp(white(n, r), 22, 2) / 0.12, 0.1, 1.3)
    creak = lp(saw, 1100, 3) * jitter * env_swell(n, 0.15, 0.1) * (t < 1.1)
    rust = bp(white(n, r), 300, 1700, 2) * env_swell(n, 0.2, 0.3) * 0.25 * (t < 1.2)
    out = pk(creak, 0.55) + pk(rust, 0.18)
    clunk = glide(n_of(0.3), 75, 42, 0.05) * env_ad(n_of(0.3), 0.002, 0.08)
    add(out, pk(clunk, 0.95), n_of(1.15))
    add(out, pk(lp(white(n_of(0.2), r), 700, 2) * env_decay(n_of(0.2), 0.03), 0.4), n_of(1.15))
    k = np.zeros(n_of(0.3)); k[:n_of(0.003)] = r.standard_normal(n_of(0.003))
    add(out, pk(resonator(k, 190, 40), 0.4), n_of(1.15))
    return finish(out, 2400, 0.02, 0.15)


def page():
    r = rng(39)
    n = n_of(0.4)
    t = tt(n)
    nz = bp(white(n, r), 800, 3000, 2)
    flick = np.exp(-((t - 0.12) / 0.07) ** 2) + 0.45 * np.exp(-((t - 0.27) / 0.05) ** 2)
    rough = 0.6 + 0.4 * np.abs(lp(white(n, r), 90, 2)) / 0.3
    return finish(nz * flick * np.clip(rough, 0.2, 1.3), 3300, 0.01, 0.1)


def place():
    r = rng(41)
    n = n_of(0.26)
    out = np.zeros(n)
    add(out, pk(glide(n_of(0.18), 140, 75, 0.03) * env_ad(n_of(0.18), 0.001, 0.045), 0.9), 0)
    add(out, pk(lp(white(n_of(0.08), r), 600, 2) * env_decay(n_of(0.08), 0.01), 0.45), 0)
    add(out, pk(glide(n_of(0.1), 125, 80, 0.03) * env_ad(n_of(0.1), 0.001, 0.03), 0.35), n_of(0.085))
    return finish(out, 2000, 0.0008, 0.05)


def switch():
    r = rng(42)
    n = n_of(0.17)
    out = np.zeros(n)
    for t0, a in ((0.0, 1.0), (0.055, 0.6)):
        m = n_of(0.03)
        c = lp(white(m, r), 2400, 2) * env_decay(m, 0.003)
        add(out, pk(c, 0.7) * a, n_of(t0))
        add(out, pk(osc(170 - 40 * a, m) * env_ad(m, 0.0005, 0.009), 0.7) * a, n_of(t0))
    return finish(out, 2800, 0.0005, 0.04)


SPEC = {k: v for k, v in dict(
    click=click, hover=hover, buy=buy, hammer_1=hammer_1, hammer_2=hammer_2, hammer_3=hammer_3,
    dig=dig, knock=knock, scrap=scrap, harvest=harvest, pour=pour, radio_on=radio_on, tune=tune,
    blip=blip, error=error, step_1=step_1, step_2=step_2, hatch_open=hatch_open, page=page,
    place=place, switch=switch).items()}
PEAK_DB = -6.0
