#!/usr/bin/env python3
"""Listen-by-numbers probe for files written by gen_audio.py (diagnostics only, writes nothing).

    python tools/audio/audio_probe.py bands  name [name ...]   energy share per band (dB re total)
    python tools/audio/audio_probe.py env    name [name ...]   RMS envelope in 12 slices (dB re peak)
    python tools/audio/audio_probe.py pitch  name lo hi        f0 track percentiles (harmonic sum)
    python tools/audio/audio_probe.py rep    name [name ...]   repetition score of loops

Names may use shell-style wildcards ('engine_*').
"""
import fnmatch
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_audio as G  # noqa: E402

BANDS = ((20, 150), (150, 400), (400, 1000), (1000, 2500), (2500, 6000), (6000, 12000), (12000, 22050))


def load(nm):
    x, sr, ch, loop, _ = G.read_wav(os.path.join(G.OUT_DIR, nm + ".wav"))
    return (x if x.ndim == 1 else x.mean(axis=1)), sr


def expand(pats):
    out = []
    for p in pats:
        out += [nm for nm in G.REGISTRY if fnmatch.fnmatch(nm, p)] or [p]
    return out


def bands(names):
    print(f"{'name':<26}" + "".join(f"{f'{a}-{b}':>11}" for a, b in BANDS))
    for nm in names:
        x, sr = load(nm)
        S = np.abs(np.fft.rfft(x)) ** 2
        f = np.fft.rfftfreq(len(x), 1.0 / sr)
        tot = S.sum() + 1e-30
        print(f"{nm:<26}" + "".join(f"{10 * np.log10(S[(f >= a) & (f < b)].sum() / tot + 1e-12):>11.1f}" for a, b in BANDS))


def env(names):
    for nm in names:
        x, sr = load(nm)
        seg = np.array_split(x, 12)
        pk = np.max(np.abs(x)) + 1e-12
        print(f"{nm:<26}" + " ".join(f"{20 * np.log10(np.sqrt(np.mean(s ** 2)) / pk + 1e-12):6.0f}" for s in seg))


def main():
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "bands":
        bands(expand(args))
    elif cmd == "env":
        env(expand(args))
    elif cmd == "pitch":
        x, sr = load(args[0])
        tr = G.pitch_track(x, sr, float(args[1]), float(args[2]))
        print(args[0], "f0 percentiles 5/25/50/75/95:", np.round(np.percentile(tr, [5, 25, 50, 75, 95])).astype(int))
    elif cmd == "rep":
        for nm in expand(args):
            x, sr = load(nm)
            s, lag = G.repetition_score(x, sr)
            print(f"{nm:<26} repetition {s:.2f} at lag {lag:.2f}s")


if __name__ == "__main__":
    main()
