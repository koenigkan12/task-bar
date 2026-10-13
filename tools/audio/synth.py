"""Biblioteca de síntese do módulo de áudio de *Quantos Dias?*.

Tudo é gerado por código (numpy/scipy), mono, 22,05 kHz. Princípios:
- Filtros "de fábrica" no domínio da frequência (zero-fase). Como a FFT é circular, qualquer sinal
  filtrado assim continua periódico: é isso que garante os loops SEM emenda (ver `circular=True`).
- Nada de agudos duros: todo som passa por low-pass (SFX ~3,5-4,5 kHz; música/rádio 300-3400 Hz).
"""
from __future__ import annotations
import os
import subprocess
import wave
import numpy as np
from scipy import signal as sg

SR = 22050
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WAV_DIR = os.path.join(HERE, "_wav")
AUDIO_DIR = os.path.join(ROOT, "assets", "audio")


# ----------------------------------------------------------------------------- básicos
def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def n_of(seconds: float) -> int:
    return int(round(seconds * SR))


def tt(n: int) -> np.ndarray:
    return np.arange(n) / SR


def db(x: float) -> float:
    return 10.0 ** (x / 20.0)


def to_db(x: float) -> float:
    return 20.0 * np.log10(max(x, 1e-12))


def peak(x: np.ndarray) -> float:
    return float(np.max(np.abs(x))) if len(x) else 0.0


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x * x))) if len(x) else 0.0


# ----------------------------------------------------------------------------- filtros (FFT, zero-fase)
def mag_lp(f, fc, order=4):
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def mag_hp(f, fc, order=2):
    f = np.maximum(f, 1e-9)
    return 1.0 / np.sqrt(1.0 + (fc / f) ** (2 * order))


def fft_filter(x: np.ndarray, fn) -> np.ndarray:
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    return np.fft.irfft(X * fn(f), n)


def lp(x, fc, order=4):
    return fft_filter(x, lambda f: mag_lp(f, fc, order))


def hp(x, fc, order=2):
    return fft_filter(x, lambda f: mag_hp(f, fc, order))


def bp(x, lo, hi, order=2):
    return fft_filter(x, lambda f: mag_hp(f, lo, order) * mag_lp(f, hi, order))


def resonator(x: np.ndarray, f0: float, q: float) -> np.ndarray:
    """Passa-faixa estreito (ressonância de cano/caixa). Causal, para SFX."""
    b, a = sg.iirpeak(f0, q, fs=SR)
    return sg.lfilter(b, a, x)


def white(n: int, r: np.random.Generator) -> np.ndarray:
    return r.standard_normal(n)


def pink(n: int, r: np.random.Generator) -> np.ndarray:
    """Ruído rosa por filtragem 1/sqrt(f) no domínio da frequência (circular)."""
    x = r.standard_normal(n)
    return fft_filter(x, lambda f: 1.0 / np.sqrt(np.maximum(f, 20.0) / 20.0))


def brown(n: int, r: np.random.Generator) -> np.ndarray:
    x = r.standard_normal(n)
    return fft_filter(x, lambda f: 1.0 / (np.maximum(f, 20.0) / 20.0))


def norm_rms(x: np.ndarray, target=1.0) -> np.ndarray:
    r = rms(x)
    return x * (target / r) if r > 0 else x


# ----------------------------------------------------------------------------- envelopes e osciladores
def env_decay(n: int, tau: float) -> np.ndarray:
    return np.exp(-tt(n) / tau)


def env_ad(n: int, attack: float, tau: float) -> np.ndarray:
    """Ataque linear curto + queda exponencial (sem clique no início)."""
    t = tt(n)
    a = np.minimum(1.0, t / max(attack, 1.0 / SR))
    return a * np.exp(-t / tau)


def env_swell(n: int, a: float, r: float) -> np.ndarray:
    """Subida e descida em cosseno (a, r em segundos), sustenta no meio."""
    e = np.ones(n)
    na, nr = min(n // 2, n_of(a)), min(n // 2, n_of(r))
    if na > 0:
        e[:na] = 0.5 - 0.5 * np.cos(np.pi * np.arange(na) / na)
    if nr > 0:
        e[n - nr:] = 0.5 + 0.5 * np.cos(np.pi * np.arange(nr) / nr)
    return e


def fade_edges(x: np.ndarray, a=0.005, r=0.01) -> np.ndarray:
    return x * env_swell(len(x), a, r)


def osc(freq, n: int | None = None, phase=0.0) -> np.ndarray:
    """Seno com frequência constante ou array (glide), por acumulação de fase."""
    if np.isscalar(freq):
        return np.sin(2 * np.pi * freq * tt(n) + phase)
    return np.sin(2 * np.pi * np.cumsum(freq) / SR + phase)


def lfo(n: int, cycles: float, phase=0.0) -> np.ndarray:
    """LFO com número INTEIRO de ciclos no buffer => periódico (loops)."""
    return np.sin(2 * np.pi * cycles * np.arange(n) / n + phase)


def add(buf: np.ndarray, sig: np.ndarray, start: int, gain=1.0, circular=False) -> None:
    n = len(buf)
    if circular:
        idx = (start + np.arange(len(sig))) % n
        np.add.at(buf, idx, sig * gain)
        return
    if start >= n or start + len(sig) <= 0:
        return
    s0 = max(0, -start)
    e0 = min(len(sig), n - start)
    buf[start + s0:start + e0] += sig[s0:e0] * gain


def hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


_NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name: str) -> int:
    """'A4' -> 69, 'G#4', 'Bb3'."""
    s = name.strip()
    p = _NOTE[s[0]]
    i = 1
    while i < len(s) and s[i] in "#b":
        p += 1 if s[i] == "#" else -1
        i += 1
    return 12 * (int(s[i:]) + 1) + p


# ----------------------------------------------------------------------------- reverb
def reverb_ir(rt60: float, r: np.random.Generator, damp_hz=2200.0) -> np.ndarray:
    n = n_of(rt60)
    ir = r.standard_normal(n) * np.exp(-6.91 * tt(n) / rt60)
    ir = lp(ir, damp_hz, 2)
    ir[:n_of(0.012)] *= np.linspace(0, 1, n_of(0.012))  # pré-atraso suave
    return ir / np.sqrt(np.sum(ir ** 2))


def reverb(x: np.ndarray, rt60=0.9, wet=0.25, seed=7, circular=False, damp_hz=2200.0) -> np.ndarray:
    r = rng(seed)
    ir = reverb_ir(rt60, r, damp_hz)
    n = len(x)
    if circular:
        w = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(ir, n), n)
    else:
        w = sg.fftconvolve(x, ir)[:n]
    # mantém a energia: parte seca + parte molhada
    return x * (1.0 - wet) + w * wet * 1.6


# ----------------------------------------------------------------------------- cadeia "rádio AM"
def am_radio(x: np.ndarray, r: np.random.Generator, lo=300.0, hi=3400.0, drive=1.8,
             hiss_db=-30.0, crackle=0.0, tide: np.ndarray | None = None, hum_db=None) -> np.ndarray:
    """Timbre de rádio de bateria: banda estreita, saturação suave, chiado, estalos raros.
    `tide` (0..1) é a intensidade do sinal ao longo do tempo (o chiado fica constante)."""
    n = len(x)
    y = x / max(peak(x), 1e-9) * 0.8
    y = np.tanh(drive * y) / np.tanh(drive)
    y = bp(y, lo, hi, 3)
    if tide is not None:
        y = y * tide
    base = max(rms(y), 1e-4)
    h = bp(white(n, r), lo, hi, 2)
    h = norm_rms(h, base * db(hiss_db))
    out = y + h
    if hum_db is not None:  # zumbido de 100 Hz bem baixo (fonte de alimentação)
        out = out + osc(100.0, n) * base * db(hum_db) * 0.6
    if crackle > 0:
        k = int(crackle * n / SR)
        for _ in range(k):
            p = int(r.integers(0, n - 80))
            pop = r.standard_normal(40) * np.exp(-np.arange(40) / 5.0)
            add(out, bp(pop, 300, 3000, 1), p, base * r.uniform(0.15, 0.5) * db(hiss_db + 14))
    return lp(out, 4600, 8)  # chiado também sem agudos duros


def slow_tide(n: int, r: np.random.Generator, lo=0.35, hi=1.0, cycles=(3, 5, 8), circular=True) -> np.ndarray:
    """Força do sinal que vai e volta (rádio distante)."""
    s = sum(lfo(n, c, r.uniform(0, 6.28)) * (1.0 / (i + 1)) for i, c in enumerate(cycles))
    s = s / np.max(np.abs(s))
    return lo + (hi - lo) * (0.5 + 0.5 * s)


# ----------------------------------------------------------------------------- medição
def lufs(x: np.ndarray) -> float:
    import pyloudnorm as pyln
    m = pyln.Meter(SR)
    return float(m.integrated_loudness(x.astype(np.float64)))


def normalize_peak(x: np.ndarray, peak_db=-6.0) -> np.ndarray:
    p = peak(x)
    return x * (db(peak_db) / p) if p > 0 else x


def soft_limit(x: np.ndarray, ceiling: float, knee: float = 0.6) -> np.ndarray:
    """Limitador de joelho macio, amostra a amostra (preserva a periodicidade dos loops)."""
    th = ceiling * knee
    a = np.abs(x)
    over = a > th
    y = x.copy()
    y[over] = np.sign(x[over]) * (th + (ceiling - th) * np.tanh((a[over] - th) / (ceiling - th)))
    return y


def normalize_lufs(x: np.ndarray, target: float, max_peak_db=-1.0) -> tuple[np.ndarray, float]:
    """Leva ao LUFS alvo; picos acima de max_peak_db passam por limitador macio e o ganho é refeito
    (até 4 iterações). Devolve (sinal, LUFS real) -- o relatório mostra o LUFS real."""
    ceil = db(max_peak_db)
    y = x * db(target - lufs(x))
    cur = lufs(y)
    for _ in range(4):
        y = soft_limit(y, ceil)
        cur = lufs(y)
        if abs(cur - target) < 0.15:
            break
        y = y * db(target - cur)
    y = soft_limit(y, ceil)
    return y, lufs(y)


# ----------------------------------------------------------------------------- saída
def write_wav(x: np.ndarray, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = np.clip(x, -1.0, 1.0)
    pcm = (pcm * 32767.0).round().astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def write_ogg(x: np.ndarray, group: str, name: str) -> tuple[str, str]:
    """Escreve WAV (para análise, em tools/audio/_wav) e OGG q3 mono em assets/audio/<grupo>/."""
    wav = os.path.join(WAV_DIR, group, name + ".wav")
    ogg = os.path.join(AUDIO_DIR, group, name + ".ogg")
    os.makedirs(os.path.dirname(ogg), exist_ok=True)
    write_wav(x, wav)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-ac", "1", "-ar", str(SR),
                    "-c:a", "libvorbis", "-q:a", "3", ogg], check=True)
    return wav, ogg
