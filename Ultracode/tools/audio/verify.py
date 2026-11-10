#!/usr/bin/env python
"""HALCYON BAY - independent verification of the generated audio.

Reads every WAV back from gta/generated/audio/ (it does not trust the synthesizer's own numbers)
and checks, numerically, the things nobody can hear on a build server:

  * every canonical sound id (docs/ARCHITECTURE.md 6.11) exists, is mono 16-bit PCM, is not
    clipped (no samples at full scale), has no DC offset and is not silent;
  * loops: wrap discontinuity (first difference across the seam against the typical step),
    one-shots: start and end at silence, transients: attack time;
  * ambience beds are 6-12 s, radio loops 30-50 s;
  * radio music: tempo (autocorrelation of the spectral-flux onset envelope) against the
    sequencer's BPM, key fit (share of tonal energy that lies on the notes of the configured
    scale) and loop length = whole number of bars.

    python tools/audio/verify.py            # exit code 0 = everything passed
"""
from __future__ import annotations

import math
import os
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import music  # noqa: E402
import synth  # noqa: E402

AUDIO_DIR = synth.OUT_DIR
BEDS = ["rain_loop", "rain_heavy_loop", "wind_loop", "ocean_loop", "city_loop", "industrial_loop",
        "park_birds_loop", "night_crickets_loop", "airport_loop", "harbor_loop"]
TRANSIENTS = ["pistol_shot", "heavy_pistol_shot", "smg_shot", "rifle_shot", "shotgun_shot", "sniper_shot",
              "explosion_small", "explosion_large", "impact_metal", "impact_concrete", "glass_break"]


def read_wav(path: str):
    with wave.open(path, "rb") as w:
        ch, width, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    x = np.frombuffer(raw, dtype="<i2").astype(np.float64)
    return x, sr, ch, width


def onset_envelope(x: np.ndarray, sr: int, hop: int = 256, win: int = 1024) -> np.ndarray:
    frames = 1 + (len(x) - win) // hop
    w = np.hanning(win)
    prev = None
    out = np.zeros(frames)
    for i in range(frames):
        mag = np.abs(np.fft.rfft(x[i * hop:i * hop + win] * w))
        mag = np.log1p(mag / 2000.0)
        if prev is not None:
            out[i] = float(np.sum(np.maximum(mag - prev, 0.0)))
        prev = mag
    out -= out.mean()
    return out


def tempo_report(x: np.ndarray, sr: int, bpm: float) -> dict:
    hop = 256
    env = onset_envelope(x, sr, hop)
    spec = np.fft.rfft(env, 2 * len(env))
    acf = np.fft.irfft(np.abs(spec) ** 2)[:len(env)]
    acf /= acf[0] + 1e-12
    fps = sr / hop

    def at(period_s: float) -> float:
        lag = period_s * fps
        i = int(round(lag))
        return float(np.max(acf[max(i - 1, 1):i + 2]))

    beat = 60.0 / bpm
    lo, hi = int(fps * 60.0 / 200.0), int(fps * 60.0 / 55.0)
    best = lo + int(np.argmax(acf[lo:hi]))
    detected = 60.0 * fps / best
    ratio = detected / bpm
    nearest = min((0.5, 2.0 / 3.0, 0.75, 1.0, 4.0 / 3.0, 1.5, 2.0), key=lambda r: abs(math.log(ratio / r)))
    return {"detected_bpm": detected, "ratio": ratio, "ratio_err": abs(ratio / nearest - 1.0), "nearest": nearest,
            "acf_beat": at(beat), "acf_bar": at(beat * 4.0), "acf_half_beat": at(beat * 0.5)}


def key_report(x: np.ndarray, sr: int, root_midi: int, scale) -> dict:
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    sel = (f >= 60.0) & (f <= 2000.0)
    f, spec = f[sel], spec[sel]
    midi = 69.0 + 12.0 * np.log2(f / 440.0)
    rel = (midi - root_midi) % 12.0
    nearest = np.round(rel) % 12
    cents = np.abs(rel - np.round(rel)) * 100.0
    tonal = cents <= 30.0
    classes = np.array([float(np.sum(spec[tonal & (nearest == k)])) for k in range(12)])
    total = float(np.sum(classes)) + 1e-20
    in_scale = float(sum(classes[k] for k in scale)) / total
    top = [int(k) for k in np.argsort(classes)[::-1][:4]]
    return {"in_scale": in_scale, "top_classes": top, "tonal_share": total / (float(np.sum(spec)) + 1e-20)}


def main() -> int:
    problems = []
    rows = []
    ids = synth.all_ids(True)
    for sid in ids:
        path = os.path.join(AUDIO_DIR, sid + ".wav")
        if not os.path.exists(path):
            problems.append("%s: file missing" % sid)
            continue
        x, sr, ch, width = read_wav(path)
        loop = sid.endswith("_loop") or (sid.startswith("radio_") and sid != "radio_static")
        if ch != 1 or width != 2:
            problems.append("%s: not mono 16-bit (%d ch, %d bytes)" % (sid, ch, width))
        if sr not in (22050, 32000, 44100):
            problems.append("%s: unexpected sample rate %d" % (sid, sr))
        pk = float(np.max(np.abs(x)))
        if int(np.sum(np.abs(x) >= 32767)) > 0:
            problems.append("%s: %d samples at full scale (clipping)" % (sid, int(np.sum(np.abs(x) >= 32767))))
        rms = float(np.sqrt(np.mean(x * x)))
        if rms < 10.0:
            problems.append("%s: practically silent" % sid)
        if abs(float(np.mean(x))) > 100.0:
            problems.append("%s: DC offset %.1f LSB" % (sid, float(np.mean(x))))
        dur = len(x) / sr
        d = np.diff(x)
        typ = float(np.sqrt(np.mean(d * d))) + 1.0
        if loop:
            seam = abs(x[0] - x[-1]) / typ
            if seam > 6.0 and abs(x[0] - x[-1]) > 130.0:
                problems.append("%s: loop seam jump %.1f x typical step" % (sid, seam))
        else:
            if abs(x[0]) > 130.0 or abs(x[-1]) > 130.0:
                problems.append("%s: one-shot does not start/end at silence (%d, %d)" % (sid, x[0], x[-1]))
        if sid in BEDS and not (6.0 <= dur <= 12.01):
            problems.append("%s: bed length %.2f s outside 6-12 s" % (sid, dur))
        if sid in TRANSIENTS:
            first = int(np.argmax(np.abs(x) >= 0.5 * pk))
            if first / sr > 0.004:
                problems.append("%s: slow attack (%.1f ms to half peak)" % (sid, 1000.0 * first / sr))
        rows.append((sid, dur, sr, 20.0 * math.log10(pk / 32768.0), 20.0 * math.log10(rms / 32768.0)))

    print("checked %d files in %s" % (len(rows), AUDIO_DIR))
    print("")
    print("%-22s %6s %7s %6s %8s %9s %9s %9s %8s  %s" % (
        "radio loop", "dur s", "bars", "bpm", "detected", "acf beat", "acf bar", "in-scale", "tonal", "top pitch classes (0 = root)"))
    for st in music.STATIONS:
        for i, cfg in enumerate(st["tracks"]):
            sid = "radio_%s_%d" % (st["id"], i + 1)
            path = os.path.join(AUDIO_DIR, sid + ".wav")
            if not os.path.exists(path):
                continue
            x, sr, _ch, _w = read_wav(path)
            dur = len(x) / sr
            bars = dur / (240.0 / cfg["bpm"])
            scale = cfg.get("scale", music.MINOR if st["fn"] in (music.synthwave, music.dnb) else music.MAJOR)
            if st["fn"] is music.disco and "scale" not in cfg:
                scale = music.DORIAN
            if st["fn"] is music.ambient and "scale" not in cfg:
                scale = music.LYDIAN
            tr = tempo_report(x, sr, cfg["bpm"])
            kr = key_report(x, sr, cfg["root"], scale)
            print("%-22s %6.2f %7.3f %6.1f %8.1f %9.2f %9.2f %8.0f%% %7.0f%%  %s" % (
                sid, dur, bars, cfg["bpm"], tr["detected_bpm"], tr["acf_beat"], tr["acf_bar"],
                kr["in_scale"] * 100.0, kr["tonal_share"] * 100.0, kr["top_classes"]))
            if not (30.0 <= dur <= 50.0):
                problems.append("%s: length %.1f s outside 30-50 s" % (sid, dur))
            if abs(bars - round(bars)) > 0.002:
                problems.append("%s: not a whole number of bars (%.4f)" % (sid, bars))
            rhythmic = st["fn"] is not music.ambient
            if rhythmic and tr["ratio_err"] > 0.03:
                problems.append("%s: detected tempo %.1f does not relate to %.1f BPM" % (sid, tr["detected_bpm"], cfg["bpm"]))
            if rhythmic and max(tr["acf_beat"], tr["acf_bar"], tr["acf_half_beat"]) < 0.15:
                problems.append("%s: weak beat periodicity" % sid)
            # Unpitched noise (drums) spreads evenly over the 12 pitch classes, which alone would
            # give 7/12 = 58 %; overtones of scale notes also land off the scale. 72 % is a
            # conservative floor for "clearly in key"; the strongest classes must be scale notes.
            if kr["in_scale"] < 0.72:
                problems.append("%s: only %.0f%% of the tonal energy is on scale notes" % (sid, kr["in_scale"] * 100.0))
            off = [k for k in kr["top_classes"] if k not in scale]
            if off:
                problems.append("%s: strongest pitch classes %s are not all in the scale" % (sid, kr["top_classes"]))
    print("")
    if problems:
        print("PROBLEMS (%d):" % len(problems))
        for p in problems:
            print("  - " + p)
        return 1
    print("VERIFY_OK: %d files, no problems" % len(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
