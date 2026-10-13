"""Música "dentro do mundo": tudo sai pelo rádio, com timbre de AM abafado (banda 300-3400 Hz,
saturação suave, chiado leve). Melodias escritas à mão em notação simples ("E5:2 C5:1 r:1" =
nota:duração em tempos). Sem trilha não-diegética.

- far        valsa distante (A menor, 3/4), sinal que vai e volta         ~52 s   (antena 2)
- 18h        melodia calorosa do velho (ré dórico, 4/4)                    60 s    (antena 4)
- numbers    estação de números: tom de abertura, bipes por dígito         ~58 s
- station_1..3  ambientes calmos de 90 s, CIRCULARES (loopam sem emenda)
- epilogue   tema curto da chegada (ré maior, o motivo do velho "abrindo")  ~30 s
- her_voice  >>> PLACEHOLDER <<< motivo de dois tons com chiado abrindo (~8 s).
             A voz real dela (fala do nível 5, "Eu tô viva. Tô a caminho...") será GRAVADA depois por uma
             pessoa e substituirá este arquivo (mesmo nome: assets/audio/music/her_voice.ogg).
"""
import numpy as np
from synth import *

NOTE_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def pk(x, w=1.0):
    p = peak(x)
    return x / p * w if p > 0 else x


# ----------------------------------------------------------------------------- notação
def parse(seq: str, start: float = 0.0):
    """'E5:2 C5:1 r:1' -> [(inicio_em_tempos, duração, midi)], descartando pausas."""
    out, t = [], start
    for tok in seq.split():
        name, d = tok.split(":")
        d = float(d)
        if name != "r":
            out.append((t, d, midi(name)))
        t += d
    return out


def chord_midis(name: str):
    """'Am' 'E7' 'G7' 'Dm' 'C' -> (raiz_pc, [midi...]) em oitava confortável (acordes na faixa 55-72)."""
    root = NOTE_PC[name[0]]
    q = name[1:]
    third = 3 if q.startswith("m") else 4
    seventh = q.endswith("7")
    base = 48 + root if root >= 7 else 60 + root
    notes = [base, base + third, base + 7] + ([base + 10] if seventh else [])
    return root, notes


# ----------------------------------------------------------------------------- instrumentos (aditivos)
def env_ar(n, a, hold, r):
    e = np.ones(n)
    na = min(n, max(1, n_of(a)))
    e[:na] = 0.5 - 0.5 * np.cos(np.pi * np.arange(na) / na)
    nh = n_of(hold)
    nr = max(1, n - nh)
    if nh < n:
        e[nh:] = 0.5 + 0.5 * np.cos(np.pi * np.arange(nr) / nr)
    return e


def tone(f, dur, harm, a=0.02, r=0.1, vib=None, detune=(0.0,), breath=0.0, seed=0):
    n = n_of(dur + r)
    t = tt(n)
    if vib:
        rate, depth, delay = vib
        vd = depth * np.clip((t - delay) / 0.3, 0, 1) * np.sin(2 * np.pi * rate * t)
    else:
        vd = 0.0
    s = np.zeros(n)
    for dt in detune:
        ph = 2 * np.pi * f * (1 + dt) * np.cumsum(1 + vd * np.ones(n)) / SR
        for h, w in enumerate(harm, 1):
            if f * h < 4200:
                s += w * np.sin(h * ph)
    s = s / max(1, len(detune))
    if breath > 0:
        s += breath * bp(white(n, rng(seed)), 900, 3000, 1)
    return s * env_ar(n, a, dur, r)


def reed(f, dur):  # acordeão/gaita: palhetas levemente desafinadas (musette)
    return tone(f, dur, [1, .5, .65, .3, .35, .15, .1, .05], a=0.035, r=0.09, vib=(5.3, 0.0035, 0.18),
                detune=(-0.0035, 0.0035))


def hum(f, dur, seed=0):  # assobio/flauta do velho: quase senoidal, vibrato tardio, um sopro
    return tone(f, dur, [1, .22, .09, .04], a=0.09, r=0.18, vib=(4.8, 0.005, 0.35), breath=0.025, seed=seed)


def pad(f, dur, a=2.0, r=2.0):
    return tone(f, dur, [1, .35, .15, .06], a=a, r=r, vib=None, detune=(-0.0025, 0.0, 0.0025))


def pluck(f, dur=None, tau=0.7, nh=10, bright=1.0):
    n = n_of(min(tau * 5.0, 8.0))
    t = tt(n)
    s = np.zeros(n)
    for h in range(1, nh + 1):
        if f * h > 4200:
            break
        w = 1.0 / h ** (0.9 / bright)
        s += w * np.sin(2 * np.pi * f * h * t + 0.3 * h) * np.exp(-t / (tau / (1 + 0.55 * (h - 1))))
    a = np.minimum(1.0, t / 0.0015)
    return s * a


def bass(f, dur=None):
    return pluck(f, tau=0.38, nh=8, bright=0.6)


def ep(f, dur=None, tau=1.4, idx=1.6):  # piano elétrico de tines (FM suave)
    n = n_of(min(tau * 5, 9.0))
    t = tt(n)
    mod = idx * np.exp(-t / 0.35) * np.sin(2 * np.pi * f * t)
    s = np.sin(2 * np.pi * f * t + mod) * np.exp(-t / tau)
    s += 0.25 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t / (tau * 0.4))
    return s * np.minimum(1.0, t / 0.003)


def musicbox(f, dur=None, tau=1.5):
    n = n_of(min(tau * 4.5, 8.0))
    t = tt(n)
    s = np.zeros(n)
    for ratio, w, d in ((1.0, 1.0, 1.0), (2.76, 0.4, 0.45), (5.4, 0.15, 0.2)):
        if f * ratio < 4200:
            s += w * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / (tau * d))
    return s * np.minimum(1.0, t / 0.002)


def warble(x, depth_ms=1.2, rate=0.5, seed=0):
    """Wow & flutter de fita/rádio: modula levemente o tempo de leitura."""
    n = len(x)
    t = np.arange(n)
    d = depth_ms * 1e-3 * SR * (np.sin(2 * np.pi * rate * t / SR) + 0.4 * np.sin(2 * np.pi * rate * 2.7 * t / SR + 1.0))
    return np.interp(t + d, t, x)


def jit(r, ms=8.0):
    return r.normal(0, ms * 1e-3)


# ----------------------------------------------------------------------------- far: valsa distante
def far():
    r = rng(201)
    bpm = 126.0
    beat = 60.0 / bpm
    total = 32 * 3 * beat + 3.5
    n = n_of(total)
    buf = np.zeros(n)
    mel = (
        # A (1-8)
        "E5:2 C5:1  A4:2 C5:1  B4:1.5 G#4:.5 B4:1  A4:3  D5:2 F5:1  E5:2 C5:1  B4:1 D5:1 G#4:1  A4:3 "
        # A' (9-16)
        "E5:1.5 F5:.5 E5:1  G5:2 E5:1  D5:1.5 B4:.5 G#4:1  A4:2 r:1  D5:1.5 E5:.5 F5:1  E5:1.5 D5:.5 C5:1  B4:1 C5:1 D5:1  A4:3 "
        # B (17-24)
        "G5:2 E5:1  D5:2 B4:1  C5:1 E5:1 G5:1  E5:3  A5:2 F5:1  D5:2 F5:1  E5:1 G#4:1 B4:1  E5:3 "
        # A'' (25-32)
        "E5:2 C5:1  A4:2 C5:1  B4:1.5 G#4:.5 B4:1  A4:2 r:1  D5:2 F5:1  B4:1 G#4:1 B4:1  C5:1.5 B4:.5 A4:1  A4:3"
    )
    chords = ("Am Am E7 Am Dm Am E7 Am  Am C E7 Am Dm Am E7 Am  C G7 C C F Dm E7 E7  Am Am E7 Am Dm E7 Am Am").split()
    assert len(chords) == 32
    for (b, d, m) in parse(mel):
        add(buf, reed(hz(m), d * beat * 0.97), n_of(b * beat + jit(r, 10)), 0.9 * (1 + 0.05 * r.standard_normal()))
    for i, c in enumerate(chords):
        root, notes = chord_midis(c)
        b0 = i * 3
        bassm = 36 + root if root >= 4 else 48 + root   # raiz grave (a faixa AM corta o fundamental; os harmônicos ficam)
        add(buf, bass(hz(bassm + 12)), n_of(b0 * beat + jit(r, 6)), 0.55)
        for k in (1, 2):
            for m in notes:
                add(buf, pluck(hz(m), tau=0.22, nh=7), n_of((b0 + k) * beat + jit(r, 6)), 0.14 * (1 + 0.05 * r.standard_normal()))
    x = reverb(buf, rt60=1.8, wet=0.32, seed=3)
    x = warble(x, 1.4, 0.45)
    tide = slow_tide(n, r, lo=0.28, hi=1.0, cycles=(3, 5, 9))
    tide *= env_swell(n, 3.0, 4.0)
    x = am_radio(x, r, lo=320, hi=3000, drive=1.7, hiss_db=-22, crackle=1.5, tide=tide, hum_db=-30)
    return fade_edges(x, 0.8, 3.0)


# ----------------------------------------------------------------------------- 18h: melodia do velho
def _h18():
    r = rng(202)
    bpm = 76.0
    beat = 60.0 / bpm
    bars = 19
    n = n_of(bars * 4 * beat)  # 60,0 s
    buf = np.zeros(n)
    mel = (
        "D5:2 A4:1 C5:1  B4:2 G4:1 B4:1  A4:1.5 C5:.5 D5:1 F5:1  E5:3 r:1 "
        "F5:2 D5:1 A4:1  B4:1.5 D5:.5 G5:2  E5:2 C5:2  D5:4 "
        "B4:1 E5:1 G5:2  D5:1.5 B4:.5 G4:2  C5:1 E5:1 G5:1 E5:1  E5:3 r:1 "
        "D5:2 A4:1 C5:1  B4:2 G4:1 B4:1  C5:1.5 E5:.5 D5:1 C5:1  D5:4 "
        "B4:2 A4:2  D5:4  r:4"
    )
    chords = "Dm G Dm Am  Dm G C Dm  Em G C Am  Dm G C Dm  G Dm Dm".split()
    assert len(chords) == bars
    for (b, d, m) in parse(mel):
        add(buf, hum(hz(m), d * beat * 0.95, seed=int(b * 10)), n_of(b * beat + jit(r, 14)), 0.9 * (1 + 0.04 * r.standard_normal()))
    pat = [0, 2, 1, 2, 0, 2, 1, 2]
    for i, c in enumerate(chords):
        root, notes = chord_midis(c)
        b0 = i * 4
        add(buf, bass(hz(36 + root + 12)), n_of(b0 * beat), 0.5)
        add(buf, bass(hz(36 + root + 12)), n_of((b0 + 2) * beat + jit(r, 8)), 0.35)
        for j, p in enumerate(pat):
            add(buf, pluck(hz(notes[p]), tau=0.55, nh=9), n_of((b0 + j * 0.5) * beat + jit(r, 8)), 0.2 * (1 + 0.06 * r.standard_normal()))
        for m in notes:
            add(buf, pad(hz(m), 4 * beat, a=0.8, r=1.2), n_of(b0 * beat), 0.07)
    x = reverb(buf, rt60=1.5, wet=0.28, seed=5)
    x = warble(x, 0.7, 0.3)
    tide = 0.9 + 0.1 * lfo(n, 4)
    x = am_radio(x, r, lo=280, hi=3300, drive=1.5, hiss_db=-31, crackle=0.5, tide=tide, hum_db=-34)
    return fade_edges(x, 0.6, 2.0)


# ----------------------------------------------------------------------------- numbers
def numbers():
    r = rng(203)
    total = 59.0
    n = n_of(total)
    buf = np.zeros(n)
    t = tt(n)

    def beep(f, dur, a=0.012):
        m = n_of(dur + 0.03)
        return (osc(f, m) + 0.25 * osc(2 * f, m)) * env_ar(m, a, dur, 0.03)

    # tom de abertura "interval signal": motivo de caixa de música, duas vezes
    motif = "E5:1 G5:1 A5:1 G5:1 E5:1 D5:2 r:1 E5:1 A4:1 B4:1 D5:1 E5:2"
    for rep in range(2):
        for (b, d, m) in parse(motif):
            add(buf, musicbox(hz(m), tau=0.55), n_of(5.0 + rep * 7.0 + b * 0.42), 0.55)
    # "atenção": três tons longos
    for i in range(3):
        add(buf, beep(1000, 0.5, 0.03), n_of(19.0 + i * 0.85), 0.5)
    # dígitos: 6 grupos de 5, lidos duas vezes
    digits = r.integers(0, 10, size=(6, 5))
    for rep in range(2):
        base = 21.5 + rep * 15.2
        for g in range(6):
            for k in range(5):
                f = 340 + 70 * int(digits[g, k])
                add(buf, beep(f, 0.2), n_of(base + g * 2.2 + k * 0.3), 0.55)
    add(buf, beep(1400, 0.15), n_of(51.8), 0.35)
    # fim de mensagem: três tons descendo
    for i, f in enumerate((660, 495, 365)):
        add(buf, beep(f, 0.4, 0.02), n_of(53.0 + i * 0.5), 0.45)
    # interferência: um assobio lento e dois chiados mais fortes
    wh = osc(900 + 260 * np.sin(2 * np.pi * 0.07 * t)) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.11 * t)) ** 4
    buf += 0.05 * wh
    x = reverb(buf, rt60=0.6, wet=0.15, seed=6)
    tide = slow_tide(n, r, lo=0.45, hi=1.0, cycles=(4, 7, 11)) * env_swell(n, 3.0, 3.0)
    x = am_radio(x, r, lo=300, hi=3300, drive=2.0, hiss_db=-21, crackle=2.0, tide=tide, hum_db=-28)
    return fade_edges(x, 0.5, 2.5)


# ----------------------------------------------------------------------------- epilogue
def epilogue():
    r = rng(204)
    bpm = 72.0
    beat = 60.0 / bpm
    bars = 8
    total = bars * 4 * beat + 3.8
    n = n_of(total)
    buf = np.zeros(n)
    mel = ("D5:2 A4:1 B4:1  D5:1.5 F#5:.5 E5:1 D5:1  B4:1 D5:1 G5:2  E5:2 C#5:2  "
           "D5:2 A4:1 B4:1  B4:1 D5:1 G5:2  F#5:1 E5:1 C#5:2  D5:4")
    chords = "D Bm G A D G A D".split()
    for (b, d, m) in parse(mel):
        add(buf, ep(hz(m), tau=1.5, idx=1.4), n_of(b * beat + jit(r, 10)), 0.8 * (1 + 0.04 * r.standard_normal()))
    pat = [0, 1, 2, 1]
    for i, c in enumerate(chords):
        root, notes = chord_midis(c)
        b0 = i * 4
        add(buf, bass(hz(36 + root + 12)), n_of(b0 * beat), 0.45)
        for j in range(8):
            add(buf, pluck(hz(notes[pat[j % 4]] + (0 if j < 4 else 0)), tau=0.7, nh=8), n_of((b0 + j * 0.5) * beat + jit(r, 6)), 0.14)
        for m in notes:
            add(buf, pad(hz(m), 4 * beat, a=1.0, r=1.5), n_of(b0 * beat), 0.09)
    x = reverb(buf, rt60=2.2, wet=0.35, seed=8)
    # o sinal "abre": começa com mais chiado e vai ficando limpo
    tide = 0.55 + 0.45 * (1 - np.exp(-tt(n) / 4.0))
    x = am_radio(x, r, lo=280, hi=3400, drive=1.4, hiss_db=-36, crackle=0.2, tide=tide, hum_db=-40)
    return fade_edges(x, 0.5, 2.5)


# ----------------------------------------------------------------------------- her_voice (PLACEHOLDER)
def her_voice():
    """PLACEHOLDER: a voz real (gravação de uma pessoa) substitui este arquivo depois.
    Aqui: o chiado "abre" (squelch) e entra um motivo de dois tons (mi4 -> la4), como um chamado."""
    r = rng(205)
    total = 8.5
    n = n_of(total)
    t = tt(n)
    buf = np.zeros(n)
    add(buf, tone(hz(64), 1.0, [1, .45, .2, .1], a=0.12, r=0.25, vib=(4.6, 0.006, 0.3), breath=0.04, seed=1), n_of(1.9), 0.7)
    add(buf, tone(hz(69), 2.2, [1, .45, .2, .1], a=0.1, r=0.9, vib=(4.6, 0.007, 0.4), breath=0.04, seed=2), n_of(3.2), 0.8)
    x = reverb(buf, rt60=1.3, wet=0.25, seed=2)
    x = am_radio(x, r, lo=290, hi=3400, drive=1.3, hiss_db=-40, crackle=0.0, tide=np.ones(n), hum_db=None)
    # chiado que abre: sobe até ~1,6 s e cai quando o tom entra
    sq = bp(white(n, r), 250, 3200, 2)
    sq *= (np.exp(-((t - 1.2) / 0.9) ** 2) * 0.9 + 0.12 * np.exp(-np.maximum(t - 2.0, 0) / 2.0) + 0.035)
    sq = sq * (rms(x) * 0.55 / max(rms(sq), 1e-9))
    for _ in range(14):
        add(sq, bp(white(40, r) * np.exp(-np.arange(40) / 5.0), 300, 3000, 1), int(r.integers(0, n - 60)), rms(x) * r.uniform(0.2, 0.7))
    return fade_edges(lp(x + sq, 4600, 8), 0.05, 1.8)


# ----------------------------------------------------------------------------- stations (circulares, 90 s)
NS = n_of(90.0)


def _station_finish(buf, r, rt60, hiss_db, crackle, lo=300, hi=3300):
    x = reverb(buf, rt60=rt60, wet=0.4, seed=11, circular=True)
    tide = 0.86 + 0.14 * lfo(NS, 5, 0.4) * (0.6 + 0.4 * lfo(NS, 11, 1.0))
    # am_radio com estalos circulares
    x = am_radio_circ(x, r, lo, hi, hiss_db, crackle, tide)
    return x


def am_radio_circ(x, r, lo, hi, hiss_db, crackle, tide):
    n = len(x)
    y = x / max(peak(x), 1e-9) * 0.8
    y = np.tanh(1.4 * y) / np.tanh(1.4)
    y = bp(y, lo, hi, 3) * tide
    base = rms(y)
    out = y + norm_rms(bp(white(n, r), lo, hi, 2), base * db(hiss_db))
    for _ in range(int(crackle * n / SR)):
        pop = bp(white(40, r) * np.exp(-np.arange(40) / 5.0), 300, 3000, 1)
        add(out, pop, int(r.integers(0, n)), base * r.uniform(0.15, 0.5) * db(hiss_db + 14), circular=True)
    return lp(out, 4600, 8)


def station_1():
    """Madrugada: acordes lentos de A menor (pads) e notas esparsas de pentatônica."""
    r = rng(211)
    buf = np.zeros(NS)
    ch = [[57, 60, 64], [57, 60, 65], [55, 60, 64], [55, 59, 62], [57, 62, 65], [57, 60, 64]]
    for i, notes in enumerate(ch):
        for m in notes:
            add(buf, pad(hz(m), 15.5, a=4.5, r=5.0), n_of(i * 15.0 - 1.0), 0.16, circular=True)
        add(buf, pad(hz(notes[0]), 15.5, a=4.5, r=5.0), n_of(i * 15.0 - 1.0), 0.1, circular=True)
    scale = [69, 72, 74, 76, 79, 81]
    t = 2.0
    while t < 88.0:
        m = int(r.choice(scale))
        add(buf, ep(hz(m), tau=2.2, idx=1.1), n_of(t), 0.28 * r.uniform(0.7, 1.0), circular=True)
        t += r.uniform(4.0, 8.5)
    return _station_finish(buf, r, 2.4, -34, 0.25)


def station_2():
    """Chuva distante: mi dórico, arpejos rolados bem lentos."""
    r = rng(212)
    buf = np.zeros(NS)
    ch = [[52, 59, 64, 67], [52, 57, 61, 64], [50, 57, 62, 66], [52, 59, 64, 71]]  # Em / A / Bm / Em9
    for i, notes in enumerate(ch):
        for m in notes:
            add(buf, pad(hz(m + 12), 23.5, a=6.0, r=6.0), n_of(i * 22.5 - 2.0), 0.13, circular=True)
    arps = [[64, 67, 71, 74, 78, 71], [64, 69, 73, 76, 81, 73], [62, 66, 71, 74, 78, 74], [64, 67, 71, 74, 79, 71]]
    for k in range(12):
        notes = arps[k // 3]
        t0 = 3.0 + k * 7.5
        for j, m in enumerate(notes):
            add(buf, ep(hz(m), tau=2.4, idx=0.9), n_of(t0 + j * 0.55), 0.24 * r.uniform(0.75, 1.0), circular=True)
    return _station_finish(buf, r, 2.8, -33, 0.3)


def station_3():
    """Sala vazia: caixa de música em dó lídio sobre pads de Cmaj7/D."""
    r = rng(213)
    buf = np.zeros(NS)
    beat = 1.5  # 12 tempos = 18 s; 5 repetições = 90 s
    phrase = "E5:1 G5:1 B5:1 A5:2 F#5:1 E5:1 D5:2 G4:1 C5:2"
    ch = [[60, 64, 67, 71], [62, 66, 69, 74], [64, 67, 71, 76], [62, 66, 69, 74], [60, 64, 67, 71]]
    for rep in range(5):
        t0 = rep * 18.0
        for (b, d, m) in parse(phrase):
            if rep == 1 and int(b) in (4, 8):  # variação: omite duas notas
                continue
            tr = 12 if (rep in (3,) and b in (0.0, 6.0)) else 0
            add(buf, musicbox(hz(m + tr), tau=1.6), n_of(t0 + b * beat + jit(r, 12)), 0.42 * r.uniform(0.8, 1.0), circular=True)
        for m in ch[rep]:
            add(buf, pad(hz(m), 19.0, a=5.5, r=5.5), n_of(t0 - 1.5), 0.14, circular=True)
    return _station_finish(buf, r, 2.6, -34, 0.2)


# nome -> (função, LUFS alvo)
SPEC = {
    "far": (far, -14.0),
    "18h": (_h18, -14.0),
    "numbers": (numbers, -14.0),
    "station_1": (station_1, -14.0),
    "station_2": (station_2, -14.0),
    "station_3": (station_3, -14.0),
    "epilogue": (epilogue, -14.0),
    "her_voice": (her_voice, -14.0),
}
