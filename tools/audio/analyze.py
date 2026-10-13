#!/usr/bin/env python3
"""Análise numérica dos áudios (não dá para ouvir, então medimos).
Para cada arquivo (WAV de origem E o OGG decodificado): duração, pico, RMS, LUFS, clipping, DC,
energia acima de 5/7 kHz relativa ao total, centroide espectral e, nos loops, a EMENDA:
razão entre o salto |x[0]-x[-1]| e o salto típico entre amostras vizinhas (p99,9 de |diff|),
e a diferença de nível RMS entre os 50 ms antes e depois da emenda.
Uso: python3 tools/audio/analyze.py"""
import os
import subprocess
import numpy as np
import synth
from synth import SR, to_db

LOOPS = {"loops", }
SEAMED = {"station_1", "station_2", "station_3"}


def decode_ogg(path):
    p = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                       capture_output=True, check=True)
    return np.frombuffer(p.stdout, dtype="<f4").astype(np.float64)


def read_wav(path):
    import wave
    with wave.open(path) as w:
        d = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
    return d


def hf_ratio(x, f0):
    X = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    tot = X.sum() + 1e-30
    return 10 * np.log10(X[f >= f0].sum() / tot + 1e-30)


def centroid(x):
    X = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    return float((X * f).sum() / (X.sum() + 1e-30))


def seam(x):
    """Teste de emenda em duas medidas:
    1) burst de alta frequência: gira o sinal para a emenda ficar no meio, passa um high-pass circular
       (1 kHz) e compara o maior |hf| a +-8 amostras da emenda com o p99,9 do |hf| no resto
       (um salto/estalo vira um pico de HF; ~1 = indistinguível do interior, >2 = estalo);
    2) salto de nível RMS (janelas de 50 ms): posição (percentil) da diferença de nível entre a última e a
       primeira janela entre as diferenças de janelas vizinhas do interior (>99% = suspeito)."""
    n = len(x)
    y = np.roll(x, n // 2)
    hf = synth.hp(y, 1000.0, 4)
    c = n // 2
    near = np.abs(hf[c - 8:c + 8]).max()
    far = np.abs(np.concatenate([hf[:c - 4000], hf[c + 4000:]]))
    burst = near / (np.percentile(far, 99.9) + 1e-12)
    w = int(0.05 * SR)
    k = n // w
    r = np.sqrt(np.mean(x[:k * w].reshape(k, w) ** 2, axis=1)) + 1e-9
    lv = 20 * np.log10(r)
    inner = np.abs(np.diff(lv))
    sd = abs(lv[-1] - lv[0])
    pct = 100.0 * np.mean(inner <= sd)
    return burst, pct, sd


def main():
    rows = []
    bad = []
    for group in ("sfx", "loops", "music"):
        for fn in sorted(os.listdir(os.path.join(synth.WAV_DIR, group))):
            name = fn[:-4]
            wav = read_wav(os.path.join(synth.WAV_DIR, group, fn))
            ogg = decode_ogg(os.path.join(synth.AUDIO_DIR, group, name + ".ogg"))
            for tag, x in (("wav", wav), ("ogg", ogg)):
                dur = len(x) / SR
                pk = to_db(np.max(np.abs(x)))
                r = to_db(np.sqrt(np.mean(x ** 2)))
                try:
                    l = synth.lufs(x) if dur > 0.5 else float("nan")
                except Exception:
                    l = float("nan")
                clip = int(np.sum(np.abs(x) >= 0.999))
                dc = float(np.mean(x))
                h5, h7 = hf_ratio(x, 5000), hf_ratio(x, 7000)
                row = dict(g=group, n=name, t=tag, dur=dur, pk=pk, rms=r, lufs=l, clip=clip, dc=dc, h5=h5, h7=h7, c=centroid(x))
                if group == "loops" or name in SEAMED:
                    row["seam"] = seam(x)
                rows.append(row)
            # OGG vs WAV: mesmo comprimento
            tol = 2 if group != "sfx" else 700   # SFX curtos: o encoder Vorbis pode deslocar/arredondar
            if abs(len(ogg) - len(wav)) > tol:
                bad.append(f"{name}: comprimento ogg {len(ogg)} != wav {len(wav)}")
    print(f"{'grupo':6}{'nome':13}{'':4}{'dur':>6}{'pico':>7}{'rms':>7}{'LUFS':>7}{'clip':>5}{'DC':>8}{'>5k':>7}{'>7k':>7}{'centr':>7}  emenda")
    for r in rows:
        s = ""
        if "seam" in r:
            a, b, c = r["seam"]
            s = f"  burstHF={a:4.2f}  nivel:{c:4.1f} dB (pct {b:4.1f})"
            if a > 2.0:   # o degrau de nível (c) é só informativo: loops rítmicos têm ataques na emenda
                bad.append(f"EMENDA suspeita em {r['n']} ({r['t']}): burstHF {a:.2f}, nivel pct {b:.1f}")
        print(f"{r['g']:6}{r['n']:13}{r['t']:>4}{r['dur']:6.1f}{r['pk']:7.1f}{r['rms']:7.1f}{r['lufs']:7.1f}{r['clip']:5d}{r['dc']:8.4f}{r['h5']:7.1f}{r['h7']:7.1f}{r['c']:7.0f}{s}")
        if r["clip"] > 0:
            bad.append(f"clipping em {r['n']} ({r['t']}): {r['clip']} amostras")
        if r["h7"] > -50 and r["t"] == "wav":
            bad.append(f"energia acima de 7 kHz em {r['n']}: {r['h7']:.1f} dB")
    print("\nPROBLEMAS:" if bad else "\nSem problemas.")
    for b in bad:
        print(" -", b)


if __name__ == "__main__":
    main()
