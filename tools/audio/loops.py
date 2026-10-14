"""Loops de 20-30 s SEM emenda. Todos são periódicos por construção:
- ruído filtrado só por filtros FFT (circulares);
- LFOs com número inteiro de ciclos por buffer (`lfo`) e senoides com frequência inteira*1/T;
- eventos (cliques, pingos) somados em modo circular (a cauda de um evento no fim volta ao início).
Assim o último amostra encadeia no primeiro como se fosse continuação do sinal."""
import numpy as np
from synth import *

T = 24.0
N = n_of(T)


def pk(x, w=1.0):
    p = peak(x)
    return x / p * w if p > 0 else x


def band(r, n, lo, hi, order=2):
    return bp(white(n, r), lo, hi, order)


def fm_phase(n, f0, depth_hz, cycles):
    """Fase periódica de uma senoide com FM senoidal (frequência f0 +- depth, `cycles` ciclos de LFO)."""
    k = np.arange(n)
    T_ = n / SR
    return 2 * np.pi * f0 * k / SR - depth_hz * T_ / cycles * np.cos(2 * np.pi * cycles * k / n)


def tick(r, kind="click", f=900.0, tau=0.006, length=0.12):
    m = n_of(length)
    if kind == "click":
        return lp(white(m, r), f, 2) * env_decay(m, tau)
    return osc(f, m) * env_ad(m, 0.001, tau)


def finish(x, fc=3200.0):
    return lp(x, fc, 4)


def amb_room():
    r = rng(101)
    n = N
    out = pk(lp(brown(n, r), 380, 2), 1.0) * 0.5
    k = np.arange(n)
    hum = (np.sin(2 * np.pi * 50 * k / SR) + 0.5 * np.sin(2 * np.pi * 100 * k / SR + 0.7) + 0.2 * np.sin(2 * np.pi * 150 * k / SR + 1.9))
    hum *= (1.0 + 0.08 * lfo(n, 2))
    out = out + pk(hum, 0.22)
    air = band(r, n, 180, 1200) * (0.55 + 0.45 * lfo(n, 3, 1.1))
    out = out + pk(air, 0.14)
    for t0 in (5.3, 12.1, 19.4):  # tique de cano, bem raro
        m = n_of(0.25)
        s = (osc(255, m) + 0.4 * osc(640, m)) * env_ad(m, 0.002, 0.04)
        add(out, s, n_of(t0), 0.035, circular=True)
    return finish(out, 3000)


def bike():
    r = rng(102)
    n = N
    out = np.zeros(n)
    rev = 24  # 1 rotação por segundo
    # catraca: 6 estalos por volta, acento no primeiro
    for i in range(rev):
        for j in range(6):
            c = tick(r, "click", 2200, 0.005, 0.05)
            a = 1.0 if j == 0 else 0.55 + 0.1 * r.random()
            add(out, pk(c, 0.5) * a, n_of(i + j / 6.0 + 0.02 * r.random()), 1.0, circular=True)
        # rangido do pedal: uma vez por volta
        m = n_of(0.22)
        f = np.linspace(170, 215, m)
        creak = osc(f) * env_swell(m, 0.04, 0.1)
        add(out, creak, n_of(i + 0.42), 0.12, circular=True)
    # dínamo: zumbido que sobe e desce a cada pedalada (2 por volta)
    strokes = 0.65 + 0.35 * lfo(n, rev * 2, -1.57)
    k = np.arange(n)
    whirr = (np.sin(2 * np.pi * 144 * k / SR) + 0.5 * np.sin(2 * np.pi * 288 * k / SR + 0.4)) * strokes
    out += pk(whirr, 0.3)
    out += pk(band(r, n, 200, 900), 0.18) * strokes
    return finish(out, 3200)


def windmill():
    r = rng(103)
    n = N
    pulses = 36  # 3 pás x 0,5 rot/s
    p = 0.5 + 0.5 * lfo(n, pulses, -1.57)
    whoosh = band(r, n, 150, 900, 2) * (0.25 + 0.75 * p ** 1.5)
    gust = 0.8 + 0.2 * lfo(n, 2, 0.4)
    out = pk(whoosh, 0.7) * gust
    out += pk(lp(brown(n, r), 220, 2), 0.35)
    ph = fm_phase(n, 175.0, 12.0, 12)  # rangido do eixo: 1 por rotação
    out += 0.05 * np.sin(ph) * (0.5 + 0.5 * lfo(n, 12, 0.3))
    return finish(out, 2800)


def battery():
    r = rng(104)
    n = N
    k = np.arange(n)
    hum = sum(a * np.sin(2 * np.pi * f * k / SR + ph) for f, a, ph in
              ((100, 1.0, 0), (100.25, 0.6, 0.5), (200, 0.5, 1.1), (300, 0.28, 2.0), (400, 0.12, 0.3)))
    hum *= 1.0 + 0.06 * lfo(n, 5)
    out = pk(hum, 0.5)
    out += pk(band(r, n, 90, 700), 0.1)
    for t0 in (3.0, 9.4, 15.2, 21.1):  # relé / clique da carga
        c = tick(r, "click", 1400, 0.004, 0.05)
        add(out, pk(c, 1.0), n_of(t0), 0.12, circular=True)
    return finish(out, 1800)


def pump():
    r = rng(105)
    n = N
    out = np.zeros(n)
    for i in range(48):  # 2 pulsos por segundo
        m = n_of(0.16)
        thump = osc(np.linspace(110, 78, m)) * env_ad(m, 0.003, 0.05)
        nz = lp(white(m, r), 600, 2) * env_decay(m, 0.02)
        add(out, pk(thump, 0.7) + pk(nz, 0.25), n_of(i * 0.5), 1.0, circular=True)
    g = (0.45 + 0.55 * (0.5 + 0.5 * lfo(n, 48, -1.0)))
    out += pk(band(r, n, 250, 900), 0.22) * g
    k = np.arange(n)
    out += 0.06 * np.sin(2 * np.pi * 120 * k / SR) * g
    return finish(out, 2600)


def conveyor():
    r = rng(106)
    n = N
    out = pk(lp(brown(n, r), 500, 2), 0.5)
    for i in range(72):  # emenda da correia: 3 por segundo
        m = n_of(0.08)
        c = lp(white(m, r), 1500, 2) * env_decay(m, 0.007)
        b = osc(110, m) * env_ad(m, 0.001, 0.02)
        a = 1.0 if i % 3 == 0 else 0.55
        add(out, (pk(c, 0.35) + pk(b, 0.45)) * a, n_of(i / 3.0), 1.0, circular=True)
    ph = fm_phase(n, 262.0, 6.0, 5)
    out += 0.07 * np.sin(ph)
    out += pk(band(r, n, 150, 700), 0.18)
    return finish(out, 2400)


def greenhouse():
    r = rng(107)
    n = N
    out = pk(band(r, n, 140, 900), 0.4) * (0.7 + 0.3 * lfo(n, 3))
    k = np.arange(n)
    out += 0.08 * np.sin(2 * np.pi * 80 * k / SR)
    out += pk(lp(brown(n, r), 300, 2), 0.2)
    pos = np.sort(r.uniform(0.5, T - 0.5, 9))
    for t0 in pos:
        m = n_of(0.12)
        f = r.uniform(620, 980)
        s = (osc(f, m) + 0.35 * osc(f * 2.4, m)) * env_ad(m, 0.002, 0.03)
        add(out, s, n_of(t0), r.uniform(0.05, 0.12), circular=True)
    return finish(out, 2600)


def solar():
    r = rng(108)
    n = N
    k = np.arange(n)
    hum = sum(a * np.sin(2 * np.pi * f * k / SR + ph) for f, a, ph in
              ((150, 1.0, 0), (150.25, 0.7, 1.0), (300, 0.35, 0.2), (450, 0.15, 2.2)))
    out = pk(hum, 0.4) * (1 + 0.1 * lfo(n, 1))
    out += pk(lp(brown(n, r), 260, 2), 0.18)
    out += pk(band(r, n, 300, 1500), 0.04)
    for t0 in (4.0, 12.0, 20.0):
        add(out, pk(tick(r, "click", 1300, 0.004, 0.04), 1.0), n_of(t0), 0.1, circular=True)
    return finish(out, 1800)


def drip():
    r = rng(109)
    n = N
    out = pk(lp(brown(n, r), 260, 2), 0.05)
    gaps = r.uniform(0.9, 2.6, 40)
    t = 0.4
    for g in gaps:
        if t > T - 0.4:
            break
        m = n_of(0.3)
        f0 = r.uniform(700, 1100)
        f = np.maximum(f0 * np.exp(-tt(m) / 0.05) + f0 * 0.45, 200)
        s = osc(f) * env_ad(m, 0.001, 0.04)
        s += 0.3 * osc(f * 2.05) * env_ad(m, 0.001, 0.015)
        add(out, s, n_of(t), r.uniform(0.5, 1.0), circular=True)
        t += g
    out = reverb(out, rt60=1.1, wet=0.45, seed=9, circular=True, damp_hz=1800.0)  # circular: cauda volta ao início
    return finish(out, 2800)


def wind_surface():
    r = rng(110)
    n = n_of(30.0)
    T_ = 30.0
    a = band(r, n, 90, 420) * (0.55 + 0.45 * lfo(n, 3, 0.2))
    b = band(r, n, 280, 900) * (0.35 + 0.65 * (0.5 + 0.5 * lfo(n, 5, 2.0)) ** 1.5)
    c = band(r, n, 600, 1500) * (0.15 + 0.85 * (0.5 + 0.5 * lfo(n, 8, 4.0)) ** 2)
    out = pk(a, 0.6) + pk(b, 0.35) + pk(c, 0.16)
    out *= 0.8 + 0.2 * lfo(n, 2, 1.0)
    ph = fm_phase(n, 390.0, 30.0, 4)
    out += 0.025 * np.sin(ph) * (0.5 + 0.5 * lfo(n, 7, 0.5)) ** 3  # um assobio rarefeito na fresta
    return finish(out, 2500)


def static():
    r = rng(111)
    n = n_of(20.0)
    wash = band(r, n, 150, 3400, 2)
    wash *= 0.75 + 0.25 * lfo(n, 3, 0.3) * (0.6 + 0.4 * lfo(n, 7, 1.0))
    out = pk(wash, 0.6)
    k = np.arange(n)
    out += 0.015 * np.sin(2 * np.pi * 100 * k / SR)
    for _ in range(26):  # estalos
        m = n_of(0.02)
        pop = bp(white(m, r), 300, 3000, 1) * env_decay(m, 0.003)
        add(out, pk(pop, 1.0), int(r.integers(0, n)), r.uniform(0.08, 0.3), circular=True)
    return lp(out, 3800, 8)


def amb_night():
    r = rng(112)
    n = N
    k = np.arange(n)
    out = pk(lp(brown(n, r), 220, 2), 0.7)
    out += 0.12 * np.sin(2 * np.pi * 45 * k / SR) * (1 + 0.1 * lfo(n, 1))
    out += pk(band(r, n, 100, 500), 0.12) * (0.3 + 0.7 * (0.5 + 0.5 * lfo(n, 3, -1.57)) ** 2)  # a ventilação "respira"
    m = n_of(0.3)
    f = np.maximum(850 * np.exp(-tt(m) / 0.05) + 380, 200)
    drop = osc(f) * env_ad(m, 0.001, 0.04)
    tmp = np.zeros(n)
    add(tmp, drop, n_of(14.0), 1.0, circular=True)
    out += reverb(tmp, rt60=1.4, wet=0.6, seed=4, circular=True, damp_hz=1500.0) * 0.05
    return finish(out, 1800)


# nome -> (função, LUFS alvo). Máquinas ~ -14; ambientes mais baixos.
SPEC = {
    "amb_room": (amb_room, -26.0),
    "bike": (bike, -14.0),
    "windmill": (windmill, -14.0),
    "battery": (battery, -16.0),
    "pump": (pump, -14.0),
    "conveyor": (conveyor, -14.0),
    "greenhouse": (greenhouse, -20.0),
    "solar": (solar, -22.0),
    "drip": (drip, -20.0),
    "wind_surface": (wind_surface, -26.0),
    "static": (static, -22.0),
    "amb_night": (amb_night, -28.0),
}
