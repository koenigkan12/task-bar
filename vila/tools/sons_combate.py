#!/usr/bin/env python3
"""Gera os sons do ataque (tiros, zumbi caindo, mordida, muro caindo, chefe, "pronto").

Síntese simples em Python puro, no mesmo formato dos sfx da vila: mono, 22050 Hz, pico -6 dBFS,
convertidos para .ogg com o ffmpeg. Uso (da pasta vila/): python3 tools/sons_combate.py
"""
import math
import os
import random
import struct
import subprocess
import tempfile
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")
PEAK = 10 ** (-6 / 20)


def env(t, a, d):
    """Ataque linear a, queda exponencial com constante d."""
    if t < a:
        return t / a if a > 0 else 1.0
    return math.exp(-(t - a) / d)


def lowpass(xs, k):
    out, y = [], 0.0
    for x in xs:
        y += k * (x - y)
        out.append(y)
    return out


def noise(n, seed):
    r = random.Random(seed)
    return [r.uniform(-1, 1) for _ in range(n)]


def square(f, t):
    return 1.0 if math.sin(2 * math.pi * f * t) >= 0 else -1.0


def shot_arrow():
    # "fwip": ruído filtrado com tom descendo, curto.
    n = int(SR * 0.16)
    nz = lowpass(noise(n, 1), 0.35)
    out = []
    for i in range(n):
        t = i / SR
        f = 1400 - 5000 * t
        out.append((0.6 * nz[i] + 0.4 * math.sin(2 * math.pi * f * t)) * env(t, 0.005, 0.04))
    return out


def shot_cannon():
    # "bum" grave: seno que despenca + ruído grave.
    n = int(SR * 0.5)
    nz = lowpass(noise(n, 2), 0.08)
    out, ph = [], 0.0
    for i in range(n):
        t = i / SR
        f = 140 * math.exp(-t * 6) + 40
        ph += 2 * math.pi * f / SR
        out.append((0.7 * math.sin(ph) + 0.6 * nz[i]) * env(t, 0.004, 0.12))
    return out


def shot_zap():
    # choque: quadrada aguda tremendo + chiado.
    n = int(SR * 0.22)
    nz = noise(n, 3)
    r = random.Random(4)
    out = []
    f = 900
    for i in range(n):
        t = i / SR
        if i % 200 == 0:
            f = r.uniform(700, 1500)
        out.append((0.45 * square(f, t) + 0.35 * nz[i]) * env(t, 0.002, 0.06))
    return lowpass(out, 0.6)


def shot_gun():
    # espingarda: estalo de ruído com corpo médio.
    n = int(SR * 0.3)
    nz = lowpass(noise(n, 5), 0.25)
    out = []
    for i in range(n):
        t = i / SR
        body = math.sin(2 * math.pi * (220 * math.exp(-t * 10) + 60) * t)
        out.append((0.8 * nz[i] + 0.35 * body) * env(t, 0.002, 0.055))
    return out


def zdie():
    # zumbi caindo: gemido curto descendo e um baque no chão.
    n = int(SR * 0.55)
    nz = lowpass(noise(n, 6), 0.1)
    out = []
    for i in range(n):
        t = i / SR
        f = 260 - 260 * t
        groan = (0.5 * math.sin(2 * math.pi * f * t) + 0.25 * math.sin(2 * math.pi * f * 1.5 * t)) * env(t, 0.03, 0.15) * (1 if t < 0.35 else 0)
        thud_t = t - 0.32
        thud = 0.0
        if thud_t >= 0:
            thud = (0.6 * math.sin(2 * math.pi * 70 * thud_t) + 0.5 * nz[i]) * env(thud_t, 0.002, 0.06)
        out.append(groan + thud)
    return out


def bite():
    # mordida: dois estalos secos (dentes) e um rasgo curto.
    n = int(SR * 0.3)
    nz = noise(n, 7)
    out = []
    for i in range(n):
        t = i / SR
        v = 0.0
        for t0 in (0.0, 0.07):
            dt = t - t0
            if dt >= 0:
                v += nz[i] * env(dt, 0.001, 0.012) * 0.9
        rt = t - 0.1
        if rt >= 0:
            v += lowpass([nz[i]], 1.0)[0] * env(rt, 0.01, 0.06) * 0.4 * (0.5 + 0.5 * math.sin(2 * math.pi * 40 * rt))
        out.append(v)
    return lowpass(out, 0.5)


def wall_fall():
    # muro caindo: estrondo + pedaços batendo (mais forte que a pancada).
    n = int(SR * 0.6)
    nz = lowpass(noise(n, 8), 0.15)
    r = random.Random(9)
    hits = sorted(r.uniform(0.08, 0.45) for _ in range(5))
    out = []
    for i in range(n):
        t = i / SR
        v = (0.7 * nz[i] + 0.4 * math.sin(2 * math.pi * 80 * t)) * env(t, 0.004, 0.14)
        for h in hits:
            dt = t - h
            if dt >= 0:
                v += 0.35 * math.sin(2 * math.pi * 300 * dt) * env(dt, 0.001, 0.02)
        out.append(v)
    return out


def boss():
    # chefe: rugido grave com vibrato, subindo e descendo.
    n = int(SR * 0.6)
    nz = lowpass(noise(n, 10), 0.05)
    out, ph = [], 0.0
    for i in range(n):
        t = i / SR
        f = 70 + 30 * math.sin(math.pi * t / 0.6) + 6 * math.sin(2 * math.pi * 9 * t)
        ph += 2 * math.pi * f / SR
        saw = (ph / math.pi) % 2 - 1
        out.append((0.5 * saw + 0.5 * nz[i]) * min(1.0, t / 0.08) * min(1.0, (0.6 - t) / 0.2))
    return lowpass(out, 0.3)


def done():
    # pronto: duas notinhas subindo (dó-sol), suaves.
    n = int(SR * 0.32)
    out = []
    for i in range(n):
        t = i / SR
        v = 0.0
        for t0, f in ((0.0, 523.25), (0.1, 783.99)):
            dt = t - t0
            if dt >= 0:
                v += (0.6 * math.sin(2 * math.pi * f * dt) + 0.15 * math.sin(4 * math.pi * f * dt)) * env(dt, 0.006, 0.08)
        out.append(v)
    return out


SOUNDS = {
    "shot_arrow": shot_arrow, "shot_cannon": shot_cannon, "shot_zap": shot_zap, "shot_gun": shot_gun,
    "zdie": zdie, "bite": bite, "wall_fall": wall_fall, "boss": boss, "done": done,
}


def write(name, xs):
    m = max(abs(x) for x in xs) or 1.0
    xs = [x / m * PEAK for x in xs]
    fade = int(SR * 0.01)   # sem estalo no fim
    for i in range(fade):
        xs[-1 - i] *= i / fade
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        tmp = tf.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in xs))
    dst = os.path.abspath(os.path.join(OUT, name + ".ogg"))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", dst], check=True)
    os.remove(tmp)
    print(dst)


if __name__ == "__main__":
    for k, fn in SOUNDS.items():
        write(k, fn())
