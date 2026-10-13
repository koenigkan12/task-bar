#!/usr/bin/env python3
"""Gera TODOS os áudios do jogo (SFX, loops, música) -> assets/audio/{sfx,loops,music}/*.ogg.
Uso:  python3 tools/audio/make_all.py [nome ...]      (sem argumentos: tudo)
Os WAV intermediários (para análise) ficam em tools/audio/_wav/. Depois rode analyze.py."""
import sys
import numpy as np
import synth
import sfx
import loops
import music


def main(only):
    rows = []
    jobs = []
    for name, fn in sfx.SPEC.items():
        jobs.append(("sfx", name, fn, ("peak", sfx.PEAK_DB)))
    for name, (fn, target) in loops.SPEC.items():
        jobs.append(("loops", name, fn, ("lufs", target)))
    for name, (fn, target) in music.SPEC.items():
        jobs.append(("music", name, fn, ("lufs", target)))
    for group, name, fn, (mode, val) in jobs:
        if only and name not in only:
            continue
        x = fn().astype(np.float64)
        x = x - np.mean(x) if group != "sfx" else x          # sem DC
        if mode == "peak":
            x = synth.normalize_peak(x, val)
            l = float("nan")
        else:
            x, l = synth.normalize_lufs(x, val)
        synth.write_ogg(x, group, name)
        rows.append((group, name, len(x) / synth.SR, synth.to_db(synth.peak(x)), l, mode, val))
    print(f"{'grupo':6} {'nome':14} {'dur(s)':>7} {'pico dBFS':>10} {'LUFS':>7} {'alvo':>8}")
    for g, n, d, p, l, m, v in rows:
        lt = "  --  " if np.isnan(l) else f"{l:7.1f}"
        tg = f"pico{v:+.0f}" if m == "peak" else f"{v:+.0f} LUFS"
        print(f"{g:6} {n:14} {d:7.2f} {p:10.1f} {lt:>7} {tg:>8}")


if __name__ == "__main__":
    main(set(sys.argv[1:]))
