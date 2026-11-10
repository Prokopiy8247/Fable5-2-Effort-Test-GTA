#!/usr/bin/env python3
"""NEON TIDE: Vesper Bay -- procedural audio library generator.

Every sound of the game is synthesised from scratch here (numpy + standard library only):
no samples, no downloads, no speech.  The generator is deterministic (every sound owns a
fixed RNG seed derived from its name), so re-running it reproduces identical files.

    python tools/audio/gen_audio.py                 generate everything + manifest + verify
    python tools/audio/gen_audio.py name1 name2     regenerate only those sounds
    python tools/audio/gen_audio.py --family radio  regenerate one family (weapons, player, vehicles,
                                                    ui, world, radio; repeatable)
    python tools/audio/gen_audio.py --verify        verify the files on disk (prints a table)
    python tools/audio/gen_audio.py --verify --quiet   summary + failing rows only
    python tools/audio/gen_audio.py --list          list all registered sounds (with per-family counts)
    python tools/audio/audio_probe.py bands|env|pitch|rep NAME...   listen-by-numbers diagnostics

Verification (per file): no NaN/Inf, format, duration, peak <= -1 dBFS; one-shots: peak -3..-1 dBFS,
silent last 5 ms, no step at the start, not cut off by the closing fade; loops: 'smpl' chunk + guard
sample, wrap step / curvature below the signal's own mean step / 99.9th-percentile curvature, RMS
-20..-14 dBFS; optional per-sound checks: no repeating sub-pattern (engines, textures), f0 track in
band (sirens), no energy that would alias when pitched up x2.2 (vehicle loops).

Output: gta/generated/audio/<name>.wav (16-bit PCM) and gta/resources/data/manifests/audio.json

Layout of this file
    1. constants
    2. shared DSP helpers (oscillators, noise colours, envelopes, spectral biquads, STFT
       time-varying filters, saturation, reverbs/delays, FM, modal, Karplus-Strong, loop tools)
    3. Kit: per-sound context (sample rate, seeded RNG, loop awareness)
    4. registry + shared sound recipes
    5. one small function per sound, grouped by family (weapons, player, vehicles, world, UI, radio)
    6. finalisation, WAV I/O, manifest, verification, CLI

Design notes
  * All static filters are applied in the frequency domain using exact 2nd-order ("biquad")
    transfer functions.  For loops the FFT is circular, so a loop that is built from periodic
    ingredients stays *exactly* periodic through every filter, delay and reverb: loops are
    seamless by construction instead of being patched afterwards with a crossfade.
  * Time-varying filters use an STFT overlap-add scheme (vectorised, no per-sample loops).
  * Loops are written with one guard sample (a copy of the first sample) and a RIFF 'smpl'
    chunk holding the loop points, so samplers that interpolate across the loop end read the
    correct value.  The loop region itself is sample 0 .. N-1.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys
import time
import wave
import zlib

import numpy as np

# ----------------------------------------------------------------------------------------------
# 1. CONSTANTS
# ----------------------------------------------------------------------------------------------
SR_ONE = 44100            # one-shots: mono 44.1 kHz
SR_LOOP = 32000           # loops: mono 32 kHz; radio: stereo 32 kHz
MASTER_SEED = 0x4E54      # "NT"
TAU = 2.0 * np.pi

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(ROOT, "gta", "generated", "audio")
MANIFEST = os.path.join(ROOT, "gta", "resources", "data", "manifests", "audio.json")

PEAK_CEIL_DB = -1.0       # nothing may exceed this
ONESHOT_PEAK_RANGE = (-3.0, -1.0)
LOOP_RMS_RANGE = (-20.0, -14.0)
SILENT_TAIL_MS = 5.0
SILENT_TAIL_DB = -50.0
END_MAX_DB = -20.0        # one-shots: level just before the closing fade (re peak) -> must have decayed
REPEAT_MAX = 0.6          # aperiodic loops: max repetition score (see repetition_score)
HF_MAX_DB = -40.0         # pitched loops: max energy share above 10.9 kHz

# ----------------------------------------------------------------------------------------------
# 2. SHARED DSP HELPERS
# ----------------------------------------------------------------------------------------------


def db(v):
    """Amplitude -> decibels."""
    return 20.0 * np.log10(np.maximum(np.abs(v), 1e-12))


def amp(d):
    """Decibels -> amplitude."""
    return 10.0 ** (np.asarray(d, dtype=float) / 20.0)


def fast_len(n):
    """Smallest 5-smooth integer >= n (fast FFT size)."""
    n = int(max(1, n))
    best = 1 << (n - 1).bit_length()
    p5 = 1
    while p5 < best:
        p35 = p5
        while p35 < best:
            q = -(-n // p35)
            m = p35 << max(0, (q - 1).bit_length())
            if m < best:
                best = m
            p35 *= 3
        p5 *= 5
    return best


def tvec(n, sr):
    return np.arange(n) / float(sr)


def _fit(a, n):
    """Stretch a control array to n samples (linear)."""
    a = np.asarray(a, dtype=float)
    if a.ndim == 0:
        return np.full(n, float(a))
    if len(a) == n:
        return a
    return np.interp(np.linspace(0.0, len(a) - 1.0, n), np.arange(len(a)), a)


def peak_of(x):
    return float(np.max(np.abs(x))) if x.size else 0.0


def rms_of(x):
    return float(np.sqrt(np.mean(np.square(x)))) if x.size else 0.0


def norm_peak(x, target_db=-1.5):
    p = peak_of(x)
    return x * (float(amp(target_db)) / p) if p > 1e-12 else x


def norm_rms(x, target_db=-17.0):
    r = rms_of(x)
    return x * (float(amp(target_db)) / r) if r > 1e-12 else x


# ---- envelopes -------------------------------------------------------------------------------

def env_exp(n, sr, tau, attack=0.0):
    """Exponential decay exp(-t/tau) with an optional raised-cosine attack (seconds)."""
    t = tvec(n, sr)
    e = np.exp(-t / max(tau, 1e-6))
    if attack > 0.0:
        m = min(n, max(1, int(round(attack * sr))))
        e[:m] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(m) / m)
    return e


def env_adsr(n, sr, a=0.005, d=0.1, s=0.7, r=0.1):
    """ADSR over a note of n samples (release included): linear attack, exponential decay,
    quadratic release that reaches exactly zero."""
    t = tvec(n, sr)
    gate = max(n / sr - r, a)
    e = np.where(t < a, t / max(a, 1e-9), s + (1.0 - s) * np.exp(-(t - a) / max(d / 4.0, 1e-6)))
    rel = np.clip((t - gate) / max(r, 1e-9), 0.0, 1.0)
    return e * (1.0 - rel) ** 2


def env_pts(n, sr, pts, smooth=False):
    """Break-point envelope from [(time_s, value), ...]; smooth=True uses smoothstep segments."""
    t = tvec(n, sr)
    tp = np.array([p[0] for p in pts], dtype=float)
    vp = np.array([p[1] for p in pts], dtype=float)
    if not smooth:
        return np.interp(t, tp, vp)
    i = np.clip(np.searchsorted(tp, t, side="right") - 1, 0, len(tp) - 2)
    u = np.clip((t - tp[i]) / np.maximum(tp[i + 1] - tp[i], 1e-9), 0.0, 1.0)
    u = u * u * (3.0 - 2.0 * u)
    return vp[i] + (vp[i + 1] - vp[i]) * u


def fade(x, sr, fin=0.0, fout=0.0):
    """Raised-cosine fade in / out (seconds). Works on mono or (n, ch) arrays."""
    x = np.array(x, dtype=float, copy=True)
    n = x.shape[0]
    if fin > 0.0:
        m = min(n, max(1, int(round(fin * sr))))
        w = 0.5 - 0.5 * np.cos(np.pi * np.arange(m) / m)
        x[:m] *= w if x.ndim == 1 else w[:, None]
    if fout > 0.0:
        m = min(n, max(1, int(round(fout * sr))))
        w = 0.5 + 0.5 * np.cos(np.pi * (np.arange(m) + 1) / m)
        x[n - m:] *= w if x.ndim == 1 else w[:, None]
    return x


def sweep(n, sr, f0, f1, tau=None, curve="exp"):
    """Pitch sweep (instantaneous frequency array). tau -> exponential approach f0 => f1."""
    t = tvec(n, sr)
    if tau is not None:
        return f1 + (f0 - f1) * np.exp(-t / tau)
    u = t / max(t[-1], 1e-9) if n > 1 else t
    if curve == "lin":
        return f0 + (f1 - f0) * u
    return f0 * (f1 / f0) ** u


# ---- oscillators (band-limited) --------------------------------------------------------------

def phase_of(freq, n, sr, wrap=False):
    """Running phase in cycles, starting at 0. With wrap=True the frequency is nudged so the
    total phase advance over n samples is a whole number of cycles (seamless loops)."""
    f = np.asarray(freq, dtype=float)
    if f.ndim == 0:
        fv = float(f)
        if wrap and fv > 0.0:
            fv = max(1.0, round(fv * n / sr)) * sr / n
        return fv * np.arange(n) / sr
    f = _fit(f, n)
    if wrap:
        cyc = f.sum() / sr
        f = f + (round(cyc) - cyc) * sr / n
    ph = np.cumsum(f) / sr
    return ph - ph[0]


def decimate(y, factor):
    """Band-limited decimation by an integer factor (FFT brick-wall with a short taper)."""
    m = len(y)
    n = m // factor
    Y = np.fft.rfft(y[: n * factor])[: n // 2 + 1].copy()
    k = max(2, len(Y) // 24)
    Y[-k:] *= 0.5 + 0.5 * np.cos(np.pi * (np.arange(k) + 1) / k)
    return np.fft.irfft(Y, n) / factor


def upsample(x, factor):
    """Band-limited interpolation by an integer factor (FFT zero padding)."""
    n = len(x)
    X = np.fft.rfft(x)
    Y = np.zeros(n * factor // 2 + 1, dtype=complex)
    Y[: len(X)] = X
    return np.fft.irfft(Y, n * factor) * factor


def _polyblep(ph, dt):
    out = np.zeros_like(ph)
    m = ph < dt
    x = ph[m] / dt[m]
    out[m] = x + x - x * x - 1.0
    m = ph > 1.0 - dt
    x = (ph[m] - 1.0) / dt[m]
    out[m] = x * x + x + x + 1.0
    return out


def _osc_phase(freq, n, sr, phase0, wrap, os):
    f = np.asarray(freq, dtype=float)
    if f.ndim:
        f = np.repeat(_fit(f, n), os)
    cyc = phase_of(f, n * os, sr * os, wrap) + phase0
    dt = np.empty(n * os)
    dt[:-1] = np.diff(cyc)
    dt[-1] = dt[-2] if n * os > 1 else 0.0
    return cyc - np.floor(cyc), np.clip(dt, 1e-9, 0.49)


def osc_sine(freq, n, sr, phase0=0.0, wrap=False):
    return np.sin(TAU * (phase_of(freq, n, sr, wrap) + phase0))


def osc_saw(freq, n, sr, phase0=0.0, wrap=False, os=2):
    """PolyBLEP sawtooth (+ optional oversampling) in [-1, 1]."""
    ph, dt = _osc_phase(freq, n, sr, phase0, wrap, os)
    y = 2.0 * ph - 1.0 - _polyblep(ph, dt)
    return decimate(y, os) if os > 1 else y


def osc_pulse(freq, n, sr, pw=0.5, phase0=0.0, wrap=False, os=2):
    """PolyBLEP pulse wave (difference of two saws), DC free. pw may be an array (PWM)."""
    ph, dt = _osc_phase(freq, n, sr, phase0, wrap, os)
    w = np.repeat(_fit(pw, n), os) if np.ndim(pw) else pw
    ph2 = ph + w
    ph2 = ph2 - np.floor(ph2)
    y = (2.0 * ph - _polyblep(ph, dt)) - (2.0 * ph2 - _polyblep(ph2, dt))
    return decimate(y, os) if os > 1 else y


def osc_tri(freq, n, sr, phase0=0.0, wrap=False, os=2):
    ph, _ = _osc_phase(freq, n, sr, phase0 + 0.25, wrap, os)
    y = 1.0 - 4.0 * np.abs(ph - 0.5)
    return decimate(y, os) if os > 1 else y


def osc_supersaw(freq, n, sr, rng, voices=7, detune=0.01, wrap=False, stereo=False, os=2):
    """Stack of detuned saws. stereo=True spreads the voices across the field -> (n, 2)."""
    offs = np.linspace(-1.0, 1.0, voices) if voices > 1 else np.zeros(1)
    out = np.zeros((n, 2)) if stereo else np.zeros(n)
    f = np.asarray(freq, dtype=float)
    for i, o in enumerate(offs):
        y = osc_saw(f * (1.0 + detune * o), n, sr, rng.random(), wrap, os)
        if stereo:
            p = 0.5 + 0.5 * o * (1 if i % 2 else -1) * 0.9
            out[:, 0] += y * math.cos(p * np.pi / 2)
            out[:, 1] += y * math.sin(p * np.pi / 2)
        else:
            out += y
    return out / math.sqrt(voices)


def osc_fm(fc, fm, index, n, sr, wrap=False, phase0=0.0):
    """Two-operator FM: sin(2pi*phc + index*sin(2pi*phm)). index may be an envelope array."""
    pc = phase_of(fc, n, sr, wrap)
    pm = phase_of(fm, n, sr, wrap)
    return np.sin(TAU * (pc + phase0) + _fit(index, n) * np.sin(TAU * pm))


def osc_harm(f0, amps, n, sr, wrap=False, phases=None):
    """Additive harmonic stack: sum_k amps[k] * sin(2pi*(k+1)*phase). Partials above ~0.45 sr are dropped."""
    ph = phase_of(f0, n, sr, wrap)
    fmax = float(np.max(f0))
    y = np.zeros(n)
    for i, a in enumerate(amps):
        k = i + 1
        if a == 0.0 or k * fmax > 0.45 * sr:
            continue
        y += a * np.sin(TAU * (k * ph + (phases[i] if phases is not None else 0.0)))
    return y


def modal(n, sr, modes, attack=0.0004):
    """Modal bank: modes = [(freq_hz, t60_s, amp[, phase]), ...] -> sum of decaying sinusoids."""
    t = tvec(n, sr)
    y = np.zeros(n)
    for m in modes:
        f, t60, a = m[0], m[1], m[2]
        if f >= 0.47 * sr or a == 0.0:
            continue
        y += a * np.exp(-6.908 * t / max(t60, 1e-4)) * np.sin(TAU * f * t + (m[3] if len(m) > 3 else 0.0))
    if attack > 0.0:
        m = min(n, max(1, int(attack * sr)))
        y[:m] *= np.arange(m) / m
    return y


# ---- noise -----------------------------------------------------------------------------------

def noise_shaped(n, sr, rng, *resps):
    """White noise shaped in the frequency domain (circular => loopable), unit RMS."""
    X = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / sr)
    for r in resps:
        X = X * r(f, sr)
    y = np.fft.irfft(X, n)
    return y / (rms_of(y) + 1e-12)


def lfo_noise(n, sr, rng, rate):
    """Smooth random modulator in [-1, 1] (Gaussian low-pass of white noise, circular)."""
    X = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / sr)
    X *= np.exp(-0.5 * (f / max(rate, 1e-3)) ** 2)
    X[0] = 0.0
    y = np.fft.irfft(X, n)
    return y / (peak_of(y) + 1e-12)


def sparse_impulses(n, sr, rng, rate, power=2.0, bipolar=True):
    """Poisson impulse train (velvet-style crackle source). Amplitudes ~ u**power (heavy tail)."""
    cnt = int(rng.poisson(max(rate, 0.0) * n / sr))
    y = np.zeros(n)
    if cnt:
        pos = rng.integers(0, n, cnt)
        a = rng.random(cnt) ** power
        if bipolar:
            a *= rng.choice([-1.0, 1.0], cnt)
        np.add.at(y, pos, a)
    return y


# ---- filter responses (2nd-order "biquad" sections evaluated on the FFT grid) -----------------
# Each r_* takes frequencies f (Hz) and returns the complex response.  With sr given the
# s-plane prototype is evaluated on the bilinear-warped axis, i.e. it is the exact response of
# the corresponding digital biquad (causal, no pre-ringing); all arguments broadcast, so the
# same functions serve the static filters and the STFT time-varying filter.

def _sv(f, fc, sr=None):
    """s = j*W/Wc (bilinear-warped when sr is given, plain analog axis otherwise)."""
    if sr is None:
        return 1j * (f / fc)
    return 1j * (np.tan(np.pi * np.minimum(f, 0.49995 * sr) / sr) / np.tan(np.pi * np.minimum(fc, 0.49 * sr) / sr))


def r_lp(f, fc, order=2, q=None, sr=None):
    """Butterworth low-pass of any order (one-pole for order 1, else a cascade of biquads);
    q overrides the resonant section."""
    s = _sv(f, fc, sr)
    if order == 1:
        return 1.0 / (1.0 + s)
    H = 1.0
    for k in range(order // 2):
        qk = 1.0 / (2.0 * math.sin(math.pi * (2 * k + 1) / (2 * order)))
        if q is not None and k == 0:
            qk = q
        H = H / (s * s + s / qk + 1.0)
    if order % 2:
        H = H / (1.0 + s)
    return H


def r_hp(f, fc, order=2, q=None, sr=None):
    s = _sv(f, fc, sr)
    if order == 1:
        return s / (1.0 + s)
    H = 1.0
    for k in range(order // 2):
        qk = 1.0 / (2.0 * math.sin(math.pi * (2 * k + 1) / (2 * order)))
        if q is not None and k == 0:
            qk = q
        H = H * (s * s) / (s * s + s / qk + 1.0)
    if order % 2:
        H = H * s / (1.0 + s)
    return H


def r_bp(f, fc, q=1.0, sr=None):
    """Resonant band-pass, unity gain at fc."""
    s = _sv(f, fc, sr)
    return (s / q) / (s * s + s / q + 1.0)


def r_peak(f, fc, gain_db, q=1.0, sr=None):
    a = 10.0 ** (gain_db / 40.0)
    s = _sv(f, fc, sr)
    return (s * s + s * a / q + 1.0) / (s * s + s / (a * q) + 1.0)


def r_notch(f, fc, q=4.0, sr=None):
    s = _sv(f, fc, sr)
    return (s * s + 1.0) / (s * s + s / q + 1.0)


def r_lowshelf(f, fc, gain_db, sr=None):
    a = 10.0 ** (gain_db / 40.0)
    s = _sv(f, fc, sr)
    k = math.sqrt(a) / 0.7071
    return a * (s * s + k * s + a) / (a * s * s + k * s + 1.0)


def r_highshelf(f, fc, gain_db, sr=None):
    a = 10.0 ** (gain_db / 40.0)
    s = _sv(f, fc, sr)
    k = math.sqrt(a) / 0.7071
    return a * (a * s * s + k * s + 1.0) / (s * s + k * s + a)


def r_tilt(f, db_per_oct, pivot=1000.0):
    """Zero-phase spectral tilt (noise colouring): -3 = pink, -6 = brown, +3 = blue."""
    return (np.maximum(f, 10.0) / pivot) ** (db_per_oct / 6.0206)


def r_curve(f, pts):
    """Zero-phase magnitude curve through [(freq_hz, gain_db), ...] (log-frequency interpolation)."""
    fp = np.log(np.array([p[0] for p in pts], dtype=float))
    gp = np.array([p[1] for p in pts], dtype=float)
    return 10.0 ** (np.interp(np.log(np.maximum(f, 1.0)), fp, gp) / 20.0)


def r_bank(f, modes, sr=None):
    """Parallel resonator bank: modes = [(fc, q, gain), ...]."""
    H = 0.0
    for fc, q, g in modes:
        H = H + g * r_bp(f, fc, q, sr)
    return H


def r_formants(f, forms, sr=None):
    """Cascade all-pole formant filter (vocal-tract style): forms = [(F_hz, bandwidth_hz), ...]."""
    H = 1.0
    for F, bw in forms:
        s = _sv(f, F, sr)
        H = H / (s * s + s * (bw / F) + 1.0)
    return H


def r_delay(f, seconds):
    return np.exp(-TAU * 1j * f * seconds)


def r_comb(f, seconds, fb, damp=None, sr=None):
    """Feedback comb / echo: z^-D / (1 - g(w) z^-D), optional one-pole damping in the loop."""
    z = np.exp(-TAU * 1j * f * seconds)
    g = fb * (r_lp(f, damp, 1, None, sr) if damp else 1.0)
    return z / (1.0 - g * z)


def r_schroeder(f, rt60=1.0, size=1.0, damp=4500.0, sr=None):
    """Classic Schroeder/Moorer reverb (6 damped feedback combs in parallel -> 3 all-passes),
    evaluated in closed form on the FFT grid."""
    H = 0.0
    for d in (0.0297, 0.0371, 0.0411, 0.0437, 0.0473, 0.0531):
        d *= size
        H = H + r_comb(f, d, 10.0 ** (-3.0 * d / rt60), damp, sr)
    H = H / 6.0
    for d, g in ((0.0051, 0.7), (0.0017, 0.7), (0.00063, 0.65)):
        z = np.exp(-TAU * 1j * f * d * size)
        H = H * (z - g) / (1.0 - g * z)
    return H


def r_spring(f, rt60=1.8, td=(0.033, 0.041, 0.047), fc=4300.0, chirp=1.6, sr=None):
    """Spring-reverb tank: dispersive (chirping) feedback delay lines, closed form."""
    H = 0.0
    u = np.minimum(f / fc, 1.2)
    lp = r_lp(f, fc * 0.82, 4, None, sr)
    for i, d in enumerate(td):
        phi = TAU * d * (f + chirp * fc * u ** 3 / 3.0)
        z = np.exp(-1j * phi) * lp
        g = 10.0 ** (-3.0 * d / rt60) * (1.0 if i % 2 == 0 else -1.0)
        H = H + z / (1.0 - g * z)
    return H / len(td)


# closures so filters read like a signal chain:  k.f(x, HP(80), PK(1200, 4, 2), LP(6000))
def LP(fc, order=2, q=None): return lambda f, sr=None: r_lp(f, fc, order, q, sr)
def HP(fc, order=2, q=None): return lambda f, sr=None: r_hp(f, fc, order, q, sr)
def BP(fc, q=1.0): return lambda f, sr=None: r_bp(f, fc, q, sr)
def PK(fc, gain_db, q=1.0): return lambda f, sr=None: r_peak(f, fc, gain_db, q, sr)
def NOTCH(fc, q=4.0): return lambda f, sr=None: r_notch(f, fc, q, sr)
def LS(fc, gain_db): return lambda f, sr=None: r_lowshelf(f, fc, gain_db, sr)
def HS(fc, gain_db): return lambda f, sr=None: r_highshelf(f, fc, gain_db, sr)
def TILT(db_per_oct, pivot=1000.0): return lambda f, sr=None: r_tilt(f, db_per_oct, pivot)
def CURVE(pts): return lambda f, sr=None: r_curve(f, pts)
def BANK(modes, direct=0.0): return lambda f, sr=None: direct + r_bank(f, modes, sr)
def FORMANTS(forms): return lambda f, sr=None: r_formants(f, forms, sr)
def DELAY(seconds): return lambda f, sr=None: r_delay(f, seconds)
def COMB(seconds, fb, damp=None): return lambda f, sr=None: r_comb(f, seconds, fb, damp, sr)
def SCHROEDER(rt60=1.0, size=1.0, damp=4500.0): return lambda f, sr=None: r_schroeder(f, rt60, size, damp, sr)
def SPRING(rt60=1.8, **kw): return lambda f, sr=None: r_spring(f, rt60, sr=sr, **kw)


def filt(x, sr, *resps, wrap=False, tail=0.06):
    """Apply a chain of responses. wrap=True -> circular (steady-state, loop-safe);
    otherwise the block is zero-padded by `tail` seconds so the filters can ring out."""
    n = x.shape[0]
    m = n if wrap else fast_len(n + int(tail * sr) + 8)
    f = np.fft.rfftfreq(m, 1.0 / sr)
    H = np.ones(len(f), dtype=complex)
    for r in resps:
        H = H * r(f, sr)
    X = np.fft.rfft(x, m, axis=0)
    if x.ndim == 2:
        H = H[:, None]
    return np.fft.irfft(X * H, m, axis=0)[:n]


def tv_filter(x, sr, resp_fn, block=256, wrap=False, ring=0.02):
    """Time-varying filter by STFT overlap-add.  resp_fn(f[1,B], t[J,1]) -> H[J,B] gives the
    response of every frame (t = frame-centre time in seconds).  Windows are normalised to a
    partition of unity, so a constant response reproduces the static filter exactly."""
    if x.ndim == 2:
        return np.stack([tv_filter(x[:, c], sr, resp_fn, block, wrap, ring) for c in range(x.shape[1])], axis=1)
    n = len(x)
    hop = block // 2
    M = fast_len(block + int(ring * sr))
    win = 0.5 - 0.5 * np.cos(TAU * (np.arange(block) + 0.5) / block)
    if wrap:
        J = max(2, int(round(n / hop)))
        starts = np.round(np.arange(J) * (n / J)).astype(np.int64)      # frame j covers start-hop ..
        src = x
        off = hop
        idx = (starts[:, None] - hop + np.arange(block)[None, :]) % n
    else:
        src = np.concatenate([np.zeros(block), x, np.zeros(2 * block)])
        J = (n + block) // hop + 2
        starts = np.arange(J) * hop
        off = 0
        idx = starts[:, None] + np.arange(block)[None, :]
    wsum = np.zeros(len(src))
    np.add.at(wsum, idx, np.broadcast_to(win, idx.shape))
    wsum = np.maximum(wsum, 1e-9)
    f = np.fft.rfftfreq(M, 1.0 / sr)[None, :]
    out = np.zeros(len(src) + M + block)
    for c0 in range(0, J, 512):
        ii = idx[c0:c0 + 512]
        fr = src[ii] * (win[None, :] / wsum[ii])
        if wrap:
            tc = starts[c0:c0 + 512] / sr
        else:
            tc = (starts[c0:c0 + 512] + hop - block) / sr
        H = resp_fn(f, tc[:, None])
        y = np.fft.irfft(np.fft.rfft(fr, M, axis=1) * H, M, axis=1)
        for j in range(y.shape[0]):
            s = int(starts[c0 + j])
            out[s:s + M] += y[j]
    if not wrap:
        return out[block:block + n]
    # circular fold: frame j was written at starts[j] but belongs at starts[j] - hop
    res = np.zeros(n)
    tot = out[: n + M + block]
    k = 0
    while k * n < len(tot):
        seg = tot[k * n:(k + 1) * n]
        res[: len(seg)] += seg
        k += 1
    return np.roll(res, -off)


# ---- non-linearities -------------------------------------------------------------------------

def softclip(x, drive=1.0):
    """tanh soft clipper; unity small-signal gain is NOT kept (output peak -> 1 for big drive)."""
    return np.tanh(x * drive) / math.tanh(drive)


def saturate(x, drive=2.0, bias=0.0, os=2):
    """Oversampled tanh saturation (bias > 0 adds even harmonics); level is normalised by the caller."""
    if os > 1 and x.ndim == 1:
        u = upsample(x, os)
        y = np.tanh(u * drive + bias) - math.tanh(bias)
        return decimate(y, os)
    if os > 1:
        return np.stack([saturate(x[:, c], drive, bias, os) for c in range(x.shape[1])], axis=1)
    return np.tanh(x * drive + bias) - math.tanh(bias)


def bitcrush(x, bits=8, hold=1):
    y = np.round(x * (2 ** (bits - 1))) / (2 ** (bits - 1))
    if hold > 1:
        y = np.repeat(y[::hold], hold)[: len(x)]
    return y


# ---- delays, modulation, resampling ----------------------------------------------------------

def interp_cubic(x, pos, wrap=False):
    """Catmull-Rom read of x at fractional positions."""
    n = len(x)
    i = np.floor(pos).astype(np.int64)
    u = pos - i
    if wrap:
        p0, p1, p2, p3 = x[(i - 1) % n], x[i % n], x[(i + 1) % n], x[(i + 2) % n]
    else:
        c = lambda k: x[np.clip(i + k, 0, n - 1)]
        p0, p1, p2, p3 = c(-1), c(0), c(1), c(2)
    y = p1 + 0.5 * u * (p2 - p0 + u * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3 + u * (3.0 * (p1 - p2) + p3 - p0)))
    if not wrap:
        y = np.where((pos >= 0) & (pos <= n - 1), y, 0.0)
    return y


def vdelay(x, delay_samples, wrap=False):
    """Variable delay line: y[n] = x(n - d[n])."""
    return interp_cubic(x, np.arange(len(x)) - delay_samples, wrap)


def resample(x, ratio):
    """Play x back `ratio` times faster (pitch up for ratio > 1)."""
    return interp_cubic(x, np.arange(int(len(x) / ratio)) * ratio)


def chorus(x, sr, depth=0.003, base=0.012, rate=0.6, mix=0.5, voices=2, wrap=False, stereo=False, phase=0.0):
    """Chorus / ensemble from modulated delay lines. Mono in -> mono or stereo out."""
    n = len(x)
    t = tvec(n, sr)
    if wrap:
        rate = max(1.0, round(rate * n / sr)) * sr / n
    outs = []
    for ch in range(2 if stereo else 1):
        wet = np.zeros(n)
        for v in range(voices):
            ph = phase + v / voices + 0.25 * ch
            wet += vdelay(x, (base + depth * np.sin(TAU * (rate * t + ph))) * sr, wrap)
        outs.append(x * (1.0 - mix) + wet * (mix / voices))
    return np.stack(outs, axis=1) if stereo else outs[0]


def pan(x, p):
    """Equal-power pan of a mono signal: p = -1 (left) .. +1 (right) -> (n, 2)."""
    a = (float(p) + 1.0) * np.pi / 4.0
    return np.stack([x * math.cos(a), x * math.sin(a)], axis=1)


def to_stereo(x):
    return x if x.ndim == 2 else np.stack([x, x], axis=1)


def put(buf, sig, start, gain=1.0, wrap=False):
    """Mix `sig` into `buf` at sample `start` (in place). wrap=True folds the overhang back
    to the beginning (events crossing the loop point)."""
    n = buf.shape[0]
    m = sig.shape[0]
    start = int(start)
    if wrap:
        start %= n
        pos = 0
        while pos < m:
            a = (start + pos) % n
            c = min(m - pos, n - a)
            buf[a:a + c] += gain * sig[pos:pos + c]
            pos += c
    else:
        a = max(0, start)
        b = min(n, start + m)
        if b > a:
            buf[a:b] += gain * sig[a - start:b - start]
    return buf


# ---- reverbs ---------------------------------------------------------------------------------

def convolve(x, h, wrap=False):
    """FFT convolution along axis 0, output length = len(x). wrap=True -> circular (the impulse
    response is folded onto the loop), which is the exact steady state of a looping sound."""
    n = x.shape[0]
    if x.ndim == 1 and h.ndim == 2:
        return np.stack([convolve(x, h[:, c], wrap) for c in range(h.shape[1])], axis=1)
    if x.ndim == 2:
        return np.stack([convolve(x[:, c], h[:, c] if h.ndim == 2 else h, wrap) for c in range(x.shape[1])], axis=1)
    if wrap:
        hf = np.zeros(n)
        for k in range(0, len(h), n):
            seg = h[k:k + n]
            hf[: len(seg)] += seg
        return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(hf), n)
    m = fast_len(n + len(h))
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(h, m), m)[:n]


def make_ir(sr, rng, rt60=1.0, hf=0.5, lo=200.0, hi=7000.0, pre=0.0, early=0.5, diffuse=0.012, channels=1):
    """Synthetic room impulse response: sparse early reflections + exponentially decaying noise
    whose high band dies `hf` times faster than the low band. Energy-normalised."""
    L = int(sr * (rt60 * 1.25 + pre)) + 64
    p0 = int(pre * sr)
    out = []
    for _ in range(channels):
        m = L - p0
        t = tvec(m, sr)
        W = np.fft.rfft(rng.standard_normal(m))
        f = np.fft.rfftfreq(m, 1.0 / sr)
        split = 1.0 / (1.0 + (f / 1800.0) ** 4)
        lo_b = np.fft.irfft(W * split, m) * np.exp(-6.908 * t / rt60)
        hi_b = np.fft.irfft(W * (1.0 - split), m) * np.exp(-6.908 * t / (rt60 * hf))
        h = lo_b + hi_b
        d = max(1, int(diffuse * sr))
        if d < m:
            h[:d] *= (np.arange(d) / d) ** 1.5
        h /= math.sqrt(float(np.sum(h * h))) + 1e-12
        if early > 0.0:
            ne = 7
            tt = np.sort(rng.uniform(0.004, 0.055 + 0.03 * min(rt60, 2.0), ne))
            er = np.zeros(m)
            for j, te in enumerate(tt):
                i = int(te * sr)
                if i < m - 1:
                    er[i] += rng.choice([-1.0, 1.0]) * (0.75 ** j) * (0.6 + 0.4 * rng.random())
            er /= math.sqrt(float(np.sum(er * er))) + 1e-12
            h = h * math.sqrt(1.0 - 0.5 * early) + er * (0.7 * early)
        h = filt(h, sr, HP(lo, 2), LP(hi, 2), tail=0.02)
        h /= math.sqrt(float(np.sum(h * h))) + 1e-12
        out.append(np.concatenate([np.zeros(p0), h]))
    return out[0] if channels == 1 else np.stack(out, axis=1)


def reverb(x, sr, rng, rt60=0.8, wet=0.25, dry=1.0, wrap=False, stereo=False, **kw):
    """Convolution reverb with a synthetic IR. stereo=True returns (n, 2) with decorrelated tails."""
    ch = 2 if (stereo or x.ndim == 2) else 1
    ir = make_ir(sr, rng, rt60, channels=ch, **kw)
    w = convolve(x, ir, wrap)
    d = to_stereo(x) if (ch == 2 and x.ndim == 1) else x
    return dry * d + wet * w


def echo(x, sr, seconds, fb=0.4, wet=0.5, damp=3000.0, wrap=False):
    """Feedback delay (damped comb)."""
    return x + wet * filt(x, sr, COMB(seconds, fb, damp), wrap=wrap, tail=min(6.0, seconds * (1 + 7 * fb) + 0.2))


def pingpong(x, sr, seconds, fb=0.45, wet=0.4, damp=3500.0, wrap=False):
    """Stereo ping-pong delay of a mono source (closed form): L taps at D, 3D, ..; R at 2D, 4D, .."""
    def left(f, fs=None):
        z = np.exp(-TAU * 1j * f * seconds) * r_lp(f, damp, 1, None, fs)
        return z / (1.0 - (fb * z) ** 2)

    def right(f, fs=None):
        z = np.exp(-TAU * 1j * f * seconds) * r_lp(f, damp, 1, None, fs)
        return fb * z * z / (1.0 - (fb * z) ** 2)
    tail = min(8.0, seconds * (2 + 10 * fb) + 0.2)
    return np.stack([wet * filt(x, sr, left, wrap=wrap, tail=tail), wet * filt(x, sr, right, wrap=wrap, tail=tail)], axis=1)


# ---- physical-ish sources --------------------------------------------------------------------

def karplus_strong(f0, n, sr, rng, t60=3.0, fd=2500.0, pick=0.15, bright=4500.0, stiff=0.0, noise_mix=0.3):
    """Karplus-Strong plucked string.  The KS recursion y[n] = x[n] + g * LP{y[n - D]} is solved
    in closed form on the FFT grid, Y = X / (1 - G(w) e^{-j phi(w)}): no per-sample loop, exact
    (fractional-delay) tuning, frequency-dependent decay T60(f) = t60 / (1 + (f/fd)^2), optional
    stiffness (inharmonic partials) and a pick-position comb in the excitation."""
    L = fast_len(int(max(n, min(t60, 7.0) * sr * 1.15)) + 64)
    f = np.fft.rfftfreq(L, 1.0 / sr)
    ne = max(2, int(math.ceil(sr / f0)))
    exc = np.zeros(L)
    burst = rng.standard_normal(ne)
    burst -= burst.mean()
    exc[:ne] = noise_mix * burst / (peak_of(burst) + 1e-9)
    exc[0] += 1.0 - noise_mix
    X = np.fft.rfft(exc) * r_lp(f, bright, 2, None, sr) * (1.0 - np.exp(-TAU * 1j * f * pick / f0)) * r_hp(f, f0 * 0.6, 2, None, sr)
    t60f = t60 / (1.0 + (f / fd) ** 2)
    G = np.exp(-6.908 / (f0 * t60f))
    k = f / f0
    if stiff > 0.0:
        k = np.sqrt((np.sqrt(1.0 + 4.0 * stiff * k * k) - 1.0) / (2.0 * stiff))
    y = np.fft.irfft(X / (1.0 - G * np.exp(-TAU * 1j * k)), L)[:n]
    return y / (peak_of(y) + 1e-12)


def pulse_train(n, sr, times, amps, tau1, tau2, wrap=False, os=4):
    """Band-limited train of pressure pulses p(t) = e^{-t/tau1}/tau1 - e^{-t/tau2}/tau2 (DC free)
    at arbitrary (fractional) times -- the exhaust-pulse source of the engine models."""
    mo = n if wrap else fast_len(n + int(6 * tau2 * sr) + 16)
    m = mo * os
    pos = np.asarray(times, dtype=float) * sr * os
    a = np.asarray(amps, dtype=float)
    i0 = np.floor(pos).astype(np.int64)
    fr = pos - i0
    buf = np.zeros(m)
    if wrap:
        np.add.at(buf, i0 % m, a * (1.0 - fr))
        np.add.at(buf, (i0 + 1) % m, a * fr)
    else:
        ok = (i0 >= 0) & (i0 < m - 1)
        np.add.at(buf, i0[ok], (a * (1.0 - fr))[ok])
        np.add.at(buf, i0[ok] + 1, (a * fr)[ok])
    w = TAU * np.fft.rfftfreq(m, 1.0 / (sr * os))
    P = 1.0 / (1.0 + 1j * w * tau1) - 1.0 / (1.0 + 1j * w * tau2)
    Y = (np.fft.rfft(buf) * P)[: mo // 2 + 1].copy()
    Y[-max(2, len(Y) // 24):] = 0.0
    return np.fft.irfft(Y, mo)[:n] * (sr / 1000.0)


# ---- dynamics --------------------------------------------------------------------------------

def _shift(a, s, wrap, fill):
    """result[i] = a[i + s]"""
    if wrap:
        return np.roll(a, -s)
    out = np.full_like(a, fill)
    if s > 0:
        out[:-s] = a[s:]
    elif s < 0:
        out[-s:] = a[:s]
    else:
        out[:] = a
    return out


def _sliding_min(g, w, wrap):
    """Centred sliding minimum over w samples (log-doubling, vectorised)."""
    out = g.copy()
    span = 1
    while span * 2 <= w:
        out = np.minimum(out, _shift(out, span, wrap, 1.0))
        span *= 2
    if span < w:
        out = np.minimum(out, _shift(out, w - span, wrap, 1.0))
    return _shift(out, -(w // 2), wrap, 1.0)


def limiter(x, sr, ceiling_db=-1.0, look=0.005, wrap=False):
    """Transparent look-ahead peak limiter: the gain curve is the sliding minimum of the required
    gain, smoothed by a window no wider than the look-ahead, so the ceiling is never exceeded."""
    a = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=1)
    c = float(amp(ceiling_db))
    g = np.minimum(1.0, c / np.maximum(a, 1e-9))
    if float(g.min()) >= 1.0:
        return x
    L = max(1, int(look * sr))
    if wrap:
        gm = _sliding_min(g, 2 * L + 1, True)
    else:
        one = np.ones(L)
        gm = _sliding_min(np.concatenate([one, g, one]), 2 * L + 1, False)[L:-L]
    k = np.hanning(2 * L + 3)[1:-1]
    k /= k.sum()
    if wrap:
        ext = np.concatenate([gm[-L:], gm, gm[:L]])
    else:
        ext = np.concatenate([np.full(L, gm[0]), gm, np.full(L, gm[-1])])
    gs = np.convolve(ext, k, mode="valid")
    return x * (gs if x.ndim == 1 else gs[:, None])


def duck_env(n, sr, hits, depth=0.6, attack=0.004, hold=0.03, release=0.22, wrap=True):
    """Side-chain style gain curve: dips by `depth` at every hit position (samples) and recovers."""
    m = int((attack + hold + release) * sr) + 1
    t = tvec(m, sr)
    rel = np.exp(-np.maximum(t - attack - hold, 0.0) / (release / 3.0))
    rel = (rel - rel[-1]) / (1.0 - rel[-1])                  # release lands exactly on 0 (no gain step)
    shape = np.where(t < attack, t / attack, np.where(t < attack + hold, 1.0, rel))
    dip = np.zeros(n)
    ar = np.arange(m)
    for h in hits:
        idx = int(h) - int(attack * sr) + ar
        if wrap:
            idx = idx % n
            dip[idx] = np.maximum(dip[idx], shape)
        else:
            ok = (idx >= 0) & (idx < n)
            dip[idx[ok]] = np.maximum(dip[idx[ok]], shape[ok])
    return 1.0 - depth * dip


# ---- loop tools ------------------------------------------------------------------------------

def loop_crossfade(x, n_loop, equal_power=False):
    """Classic seamless-loop repair for material that is NOT periodic by construction:
    x is longer than the loop; the overhang x[n_loop:] is cross-faded into the head."""
    x = np.asarray(x, dtype=float)
    k = len(x) - n_loop
    out = x[:n_loop].copy()
    if k <= 0:
        return out
    u = (np.arange(k) + 0.5) / k
    fi, fo = (np.sin(u * np.pi / 2), np.cos(u * np.pi / 2)) if equal_power else (u, 1.0 - u)
    out[:k] = out[:k] * fi + x[n_loop:] * fo
    return out


def loop_rotate_zero(x, search):
    """Rotate a mono loop so the wrap falls on the quietest zero crossing in the first `search`
    samples (a rotation does not change a loop; it makes the wrap robust to any player)."""
    if x.ndim != 1:
        return x
    s = min(len(x) - 1, max(2, int(search)))
    cost = np.abs(x[:s]) + np.abs(np.roll(x, 1)[:s])
    return np.roll(x, -int(np.argmin(cost)))


def loop_rotate_stereo(x, search):
    """Stereo counterpart of loop_rotate_zero: rotate so the wrap falls where, within the first
    `search` samples, both channels step least (relative to their mean step) and sit near zero."""
    if x.ndim != 2:
        return loop_rotate_zero(x, search)
    s = min(x.shape[0] - 1, max(2, int(search)))
    prev = np.roll(x, 1, axis=0)[:s]
    head = x[:s]
    mstep = np.mean(np.abs(np.diff(x, axis=0)), axis=0) + 1e-12
    rms = np.sqrt(np.mean(x * x, axis=0)) + 1e-12
    cost = (np.abs(head - prev) / mstep).sum(axis=1) + 0.25 * ((np.abs(head) + np.abs(prev)) / rms).sum(axis=1)
    return np.roll(x, -int(np.argmin(cost)), axis=0)


def loop_seam(x):
    """(wrap step / mean step, wrap curvature / 99.9th-percentile curvature) -- both should be < 1."""
    x = np.asarray(x, dtype=float)
    if x.ndim == 2:
        r = [loop_seam(x[:, c]) for c in range(x.shape[1])]
        return max(v[0] for v in r), max(v[1] for v in r)
    d = np.abs(np.diff(x))
    step = abs(x[0] - x[-1]) / (float(d.mean()) + 1e-12)
    c2 = np.abs(np.diff(x, 2))
    w = max(abs(x[-2] - 2 * x[-1] + x[0]), abs(x[-1] - 2 * x[0] + x[1]))
    return step, w / (float(np.percentile(c2, 99.9)) + 1e-12)


# ----------------------------------------------------------------------------------------------
# 3. KIT -- per-sound synthesis context
# ----------------------------------------------------------------------------------------------

class Kit:
    """Binds sample rate, a seeded RNG and loop awareness to the DSP helpers.

    Any buffer whose length equals the loop length of a looping sound is processed circularly
    (oscillators snap to whole cycles, filters/reverbs wrap), so loops stay exactly periodic.
    Shorter event buffers (made with .sub()) are processed with normal zero-padded tails and are
    mixed in with .put(), which wraps around the loop point."""

    def __init__(self, sr, seed, dur, loop=False, rng=None):
        self.sr = int(sr)
        self.dur = float(dur)
        self.n = max(1, int(round(dur * sr)))
        self.loop = bool(loop)
        self.rng = rng if rng is not None else np.random.default_rng(seed)

    def sub(self, sec):
        """Event kit (never circular) sharing this kit's RNG."""
        return Kit(self.sr, 0, sec, False, self.rng)

    def N(self, sec=None):
        return self.n if sec is None else max(1, int(round(sec * self.sr)))

    def _c(self, n):
        return self.loop and n == self.n

    def t(self, sec=None):
        return tvec(self.N(sec), self.sr)

    def zeros(self, sec=None):
        return np.zeros(self.N(sec))

    def u(self, lo, hi):
        """Uniform random scalar."""
        return float(self.rng.uniform(lo, hi))

    # -- oscillators
    def sine(self, f, sec=None, ph=0.0):
        n = self.N(sec); return osc_sine(f, n, self.sr, ph, self._c(n))

    def saw(self, f, sec=None, ph=0.0, os=2):
        n = self.N(sec); return osc_saw(f, n, self.sr, ph, self._c(n), os)

    def pulse(self, f, pw=0.5, sec=None, ph=0.0, os=2):
        n = self.N(sec); return osc_pulse(f, n, self.sr, pw, ph, self._c(n), os)

    def tri(self, f, sec=None, ph=0.0):
        n = self.N(sec); return osc_tri(f, n, self.sr, ph, self._c(n))

    def supersaw(self, f, sec=None, voices=7, detune=0.01, stereo=False):
        n = self.N(sec); return osc_supersaw(f, n, self.sr, self.rng, voices, detune, self._c(n), stereo)

    def fm(self, fc, fm, index, sec=None):
        n = self.N(sec); return osc_fm(fc, fm, index, n, self.sr, self._c(n))

    def harm(self, f0, amps, sec=None, phases=None):
        n = self.N(sec); return osc_harm(f0, amps, n, self.sr, self._c(n), phases)

    def sweep(self, f0, f1, sec=None, tau=None, curve="exp"):
        return sweep(self.N(sec), self.sr, f0, f1, tau, curve)

    def modal(self, modes, sec=None, attack=0.0004):
        return modal(self.N(sec), self.sr, modes, attack)

    def thump(self, f0, f1, sweep_tau, decay_tau, sec=None, attack=0.0015):
        """Low sine 'thud' whose pitch drops f0 -> f1 (the body of kicks, impacts, blasts)."""
        n = self.N(sec)
        return osc_sine(sweep(n, self.sr, f0, f1, sweep_tau), n, self.sr) * env_exp(n, self.sr, decay_tau, attack)

    # -- noise
    def white(self, sec=None):
        return self.rng.standard_normal(self.N(sec))

    def cnoise(self, slope=-3.0, sec=None, lo=20.0, hi=None):
        """Coloured noise: slope in dB/oct (-3 pink, -6 brown, +3 blue), band-limited lo..hi, unit RMS."""
        r = [TILT(slope), HP(lo, 2)] + ([LP(hi, 2)] if hi else [])
        return noise_shaped(self.N(sec), self.sr, self.rng, *r)

    def bnoise(self, lo, hi, sec=None, order=2):
        """Band-limited white noise, unit RMS."""
        return noise_shaped(self.N(sec), self.sr, self.rng, HP(lo, order), LP(hi, order))

    def snoise(self, *resps, sec=None):
        """Noise with an arbitrary spectral shape, unit RMS."""
        return noise_shaped(self.N(sec), self.sr, self.rng, *resps)

    def lfo(self, rate, ph=0.0, sec=None):
        """Sine LFO in [-1, 1]; in a loop the rate snaps to whole cycles per loop."""
        n = self.N(sec)
        if self._c(n):
            rate = max(1.0, round(rate * n / self.sr)) * self.sr / n
        return np.sin(TAU * (rate * tvec(n, self.sr) + ph))

    def lfon(self, rate, sec=None):
        """Smooth random modulator in [-1, 1] (periodic over the buffer)."""
        return lfo_noise(self.N(sec), self.sr, self.rng, rate)

    def wander(self, rate, lo, hi, sec=None):
        """Smooth random walk between lo and hi."""
        return lo + (hi - lo) * (0.5 + 0.5 * self.lfon(rate, sec))

    def sparks(self, rate, sec=None, power=2.0):
        return sparse_impulses(self.N(sec), self.sr, self.rng, rate, power)

    # -- envelopes
    def exp(self, tau, sec=None, a=0.0):
        return env_exp(self.N(sec), self.sr, tau, a)

    def adsr(self, a=0.005, d=0.1, s=0.7, r=0.1, sec=None):
        return env_adsr(self.N(sec), self.sr, a, d, s, r)

    def pts(self, pts, sec=None, smooth=False):
        return env_pts(self.N(sec), self.sr, pts, smooth)

    def fade(self, x, fin=0.0, fout=0.0):
        return fade(x, self.sr, fin, fout)

    def burst(self, tau, sec=None, a=0.0):
        """White-noise burst with exponential decay."""
        n = self.N(sec)
        return self.rng.standard_normal(n) * env_exp(n, self.sr, tau, a)

    # -- filters
    def f(self, x, *resps, tail=0.06):
        return filt(x, self.sr, *resps, wrap=self._c(x.shape[0]), tail=tail)

    def lp(self, x, fc, order=2, q=None):
        return self.f(x, LP(fc, order, q))

    def hp(self, x, fc, order=2, q=None):
        return self.f(x, HP(fc, order, q))

    def bp(self, x, fc, q=1.0):
        return self.f(x, BP(fc, q))

    def tvf(self, x, fn, block=256, ring=0.02):
        """Time-varying filter; fn(f, t) -> response (see tv_filter)."""
        return tv_filter(x, self.sr, fn, block, self._c(x.shape[0]), ring)

    def _ctl(self, v, n):
        """Turn a scalar / per-sample array into a function of frame time."""
        if np.ndim(v) == 0:
            return lambda t: float(v)
        a = _fit(v, n)
        tg = tvec(n, self.sr)
        return lambda t: np.interp(t, tg, a)

    def tvlp(self, x, fc, q=0.7071, order=2, block=256, ring=0.02):
        c, r = self._ctl(fc, len(x)), self._ctl(q, len(x))
        return self.tvf(x, lambda f, t: r_lp(f, c(t), order, r(t), self.sr), block, ring)

    def tvhp(self, x, fc, q=0.7071, order=2, block=256, ring=0.02):
        c, r = self._ctl(fc, len(x)), self._ctl(q, len(x))
        return self.tvf(x, lambda f, t: r_hp(f, c(t), order, r(t), self.sr), block, ring)

    def tvbp(self, x, fc, q=2.0, block=256, ring=0.03):
        c, r = self._ctl(fc, len(x)), self._ctl(q, len(x))
        return self.tvf(x, lambda f, t: r_bp(f, c(t), r(t), self.sr), block, ring)

    # -- effects
    def sat(self, x, drive=2.0, bias=0.0, os=2):
        return saturate(x, drive, bias, os)

    def rev(self, x, rt=0.8, wet=0.25, dry=1.0, stereo=False, **kw):
        return reverb(x, self.sr, self.rng, rt, wet, dry, self._c(x.shape[0]), stereo, **kw)

    def echo(self, x, seconds, fb=0.4, wet=0.5, damp=3000.0):
        return echo(x, self.sr, seconds, fb, wet, damp, self._c(x.shape[0]))

    def chorus(self, x, **kw):
        return chorus(x, self.sr, wrap=self._c(len(x)), **kw)

    def put(self, buf, sig, at, gain=1.0):
        """Mix an event into a buffer at `at` seconds (wraps around the loop point in loops)."""
        return put(buf, sig, int(round(at * self.sr)), gain, self._c(buf.shape[0]))


# ----------------------------------------------------------------------------------------------
# 4. REGISTRY + SHARED RECIPES
# ----------------------------------------------------------------------------------------------

REGISTRY = {}      # name -> (function, options)
FAMILIES = ("weapons", "player", "vehicles", "ui", "world", "radio")
_FAMILY = ["weapons"]


def family(name):
    """Every sound registered after this call belongs to `name` (used by --family and the report)."""
    assert name in FAMILIES, name
    _FAMILY[0] = name


def sound(name, dur, loop=False, sr=None, ch=1, level=None, check=None, **params):
    """Register a sound.  level = peak dBFS for one-shots, RMS dBFS for loops.
    check = extra listen-by-numbers checks run by --verify (see analyse()):
      aperiodic=True   loop must not contain a repeating pattern shorter than the loop (engines, textures)
      band=(lo, hi)    fundamental-frequency track must stay in / sweep across lo..hi Hz (sirens)
      hf=True          little energy above 10.9 kHz (loops Godot pitch-shifts up to x2.2 at 48 kHz)"""
    def deco(fn):
        REGISTRY[name] = (fn, dict(
            dur=float(dur), loop=bool(loop), sr=int(sr or (SR_LOOP if loop else SR_ONE)), ch=int(ch),
            level=float(level if level is not None else (-17.0 if loop else -1.5)), check=dict(check or {}),
            family=_FAMILY[0], params=params))
        return fn
    return deco


def r_click(k, f=3000.0, tau=0.004, q=3.0, body=0.0, body_f=200.0, metal=0.0, sec=None):
    """Mechanical click / clack: a noise tick through three resonances, with an optional low
    'clunk' body and a few short metallic modes."""
    e = k.sub(sec or (max(tau, 0.004) * 9.0 + 0.03 + (0.06 if metal else 0.0)))
    y = e.f(e.burst(tau), BANK([(f, q, 1.0), (f * 1.83, q * 1.3, 0.6), (f * 2.9, q * 1.5, 0.35)]))
    y /= peak_of(y) + 1e-9
    if body:
        y += body * e.thump(body_f * 1.7, body_f, 0.008, max(tau * 2.5, 0.012))
    if metal:
        fm = f * k.u(0.85, 1.15)
        y += metal * e.modal([(fm, 0.07, 1.0), (fm * 1.52, 0.05, 0.6), (fm * 2.31, 0.035, 0.45), (fm * 3.41, 0.022, 0.3)])
    return y


def r_scrape(k, sec, f0, f1, q=2.0, grain=140.0):
    """Short sliding / scraping friction: gritty band noise whose centre glides f0 -> f1."""
    e = k.sub(sec)
    x = e.white() * (0.45 + 0.55 * np.abs(e.lfon(grain)))
    y = e.tvbp(x, e.sweep(f0, f1), q)
    return y / (peak_of(y) + 1e-9) * np.sin(np.pi * e.t() / sec) ** 0.6


def r_whoosh(k, f0, f1, f2, sec, q=1.6, peak=0.45, air=0.25):
    """Air whoosh: a noise band whose centre sweeps f0 -> f1 -> f2 under a bell envelope."""
    e = k.sub(sec)
    u = np.clip(e.t() / sec, 0.0, 1.0)
    fc = np.where(u < peak, f0 * (f1 / f0) ** (u / peak), f1 * (f2 / f1) ** ((u - peak) / (1.0 - peak)))
    env = np.sin(np.pi * u ** (math.log(0.5) / math.log(peak))) ** 2
    x = e.white()
    y = e.tvbp(x, fc, q) + air * e.tvbp(x, np.minimum(fc * 2.7, 0.45 * e.sr), q * 0.7)
    y *= env
    return y / (peak_of(y) + 1e-9)


def r_bubbles(k, count, f_lo, f_hi, sec, t_pow=1.6, span=1.0):
    """Bubble cloud: every bubble is a short decaying sine whose pitch rises as it shrinks."""
    e = k.sub(sec)
    out = e.zeros()
    for _ in range(int(count)):
        fb = f_lo * (f_hi / f_lo) ** k.rng.random()
        d = 0.13 * fb + 0.0072 * fb ** 1.5
        nb = min(e.n, int(7.0 / d * e.sr) + 8)
        t = np.arange(nb) / e.sr
        b = np.sin(TAU * fb * t * (1.0 + k.u(0.05, 0.25) * d * t * 0.5)) * np.exp(-d * t) * np.minimum(1.0, t * e.sr / 6.0)
        put(out, b, int(e.n * span * k.rng.random() ** t_pow), (f_lo / fb) ** 0.7 * k.u(0.3, 1.0))
    return out / (peak_of(out) + 1e-9)


def r_rustle(k, sec, lo, hi, grain=45.0, sharp=2.0):
    """Cloth / foliage / grit rustle: band noise under a random granular envelope."""
    e = k.sub(sec)
    y = e.bnoise(lo, hi) * np.abs(e.lfon(grain)) ** sharp
    return y / (peak_of(y) + 1e-9)


def r_tail(k, x, rt=0.5, wet=0.3, taps=(), lp=3500.0, pre=0.0):
    """Outdoor tail: discrete slap echoes [(time_s, gain), ...] plus a dark diffuse reverb."""
    src = k.f(x, LP(lp, 2))
    y = x.copy()
    for tt, gg in taps:
        put(y, src, int(tt * k.sr), gg)
    return y + wet * convolve(src, make_ir(k.sr, k.rng, rt, hf=0.45, lo=160.0, hi=lp * 1.3, pre=pre), False)


def r_voice(k, sec, f0, forms, breath=0.12, rough=0.0, sub=0.0, tilt=1400.0, jitter=0.015, shimmer=0.08, hpc=False):
    """Non-verbal voice: glottal pulse train (jitter, shimmer, sub-harmonic roughness, aspiration
    noise) through a time-varying cascade formant filter.
    f0: per-sample array or [(t, hz), ...]; forms: [(F_start, F_end, bandwidth), ...], where F_start may
    also be a break-point track [(t_s, F), ...] (F_end is then ignored).
    hpc=True adds the higher-pole correction of a real tract: the missing poles F5..F8 (spaced ~1 kHz
    above the top formant, like a uniform tube) keep the 3-8 kHz region alive instead of the
    truncated cascade's -48 dB/oct fall above F4, and the aspiration source gets a -6 dB/oct slope."""
    e = k.sub(sec)
    n = e.n
    f0 = e.pts(f0, smooth=True) if isinstance(f0, list) else _fit(f0, n)
    f0 = f0 * (1.0 + jitter * e.lfon(35.0) + 0.4 * jitter * e.lfon(180.0))
    ph = phase_of(f0, n, e.sr)
    src = e.f(e.saw(f0), LP(tilt, 1))
    am = 1.0 + shimmer * e.lfon(45.0)
    if sub:
        am = am * (1.0 + sub * np.sin(np.pi * ph))
    if rough:
        am = am * (1.0 + rough * e.lfon(95.0))
    asp = e.f(e.white(), HP(1200.0, 2), LP(7000.0, 2)) * (0.6 + 0.4 * np.cos(TAU * ph))
    if hpc:      # a corrected (bright) tract needs a natural -6 dB/oct turbulence source
        asp = e.f(asp, LP(1500.0, 1)) * 2.0
    x = src * am + breath * asp
    sr = e.sr

    def resp(f, t):
        u = np.clip(t / sec, 0.0, 1.0)
        H = 1.0
        for fa, fb_, bw in forms:
            if isinstance(fa, (list, tuple)):          # break-point track [(t_s, F), ...] (fb_ ignored)
                F = np.interp(t.ravel(), [p[0] for p in fa], [p[1] for p in fa]).reshape(t.shape)
            else:
                F = fa + (fb_ - fa) * u
            s = _sv(f, F, sr)
            H = H / (s * s + s * (bw / F) + 1.0)
        if hpc:
            top = max((max(p[1] for p in fa) if isinstance(fa, (list, tuple)) else max(fa, fb_)) for fa, fb_, _ in forms)
            for m in range(1, 5):
                F = top + 1050.0 * m
                if F < 0.45 * sr:
                    s = _sv(f, F, sr)
                    H = H / (s * s + s * ((250.0 + 100.0 * m) / F) + 1.0)
        return H
    y = e.tvf(x, resp, 256, 0.04)
    return y / (peak_of(y) + 1e-9)


# ----------------------------------------------------------------------------------------------
# 5a. WEAPONS
# ----------------------------------------------------------------------------------------------

def r_gunshot(k, crack=1.0, crack_hp=2200.0, crack_tau=0.008, body=1.0, body_f=750.0, body_q=0.8, body_tau=0.035,
              thump=0.8, thump_f=(170.0, 70.0), thump_tau=0.06, drive=2.2, tail_rt=0.35, tail_wet=0.32,
              taps=((0.045, 0.2), (0.085, 0.1)), mech=0.0, mech_at=0.06, presence=0.0, lp=11000.0):
    """Layered gunshot: transient click + bright crack + mid-band blast + pitch-dropping low thump,
    saturated for density, then an outdoor slap/reverb tail and an optional action clack."""
    t = k.t()
    y = 0.8 * crack * k.white() * np.exp(-t / 0.0007)
    y += crack * k.f(k.burst(crack_tau), HP(crack_hp, 2))
    y += 1.6 * body * k.f(k.burst(body_tau, a=0.0004), BP(body_f, body_q), LP(6500.0, 1))
    y += 2.4 * thump * k.thump(thump_f[0], thump_f[1], 0.018, thump_tau, attack=0.001)
    y = k.sat(norm_peak(y, 0.0), drive)
    y = k.f(y, HP(45.0, 2), PK(3800.0, presence, 1.2), LP(lp, 2))
    y = r_tail(k, y, tail_rt, tail_wet, taps, lp=3600.0)
    if mech:
        k.put(y, r_click(k, 2700.0, 0.003, metal=0.5), mech_at, mech * peak_of(y))
    return y


@sound("shot_pistol", 0.5)
def shot_pistol(k):
    return r_gunshot(k, crack_hp=2000.0, crack_tau=0.007, body_f=850.0, body_tau=0.03, thump=0.75,
                     thump_f=(190.0, 85.0), thump_tau=0.045, tail_rt=0.3, tail_wet=0.3,
                     taps=((0.04, 0.2), (0.075, 0.1)), mech=0.1, mech_at=0.07)


@sound("shot_revolver", 0.7)
def shot_revolver(k):
    return r_gunshot(k, crack=0.9, crack_hp=1700.0, crack_tau=0.010, body=1.2, body_f=560.0, body_tau=0.05, thump=1.1,
                     thump_f=(150.0, 58.0), thump_tau=0.085, drive=2.6, tail_rt=0.48, tail_wet=0.36,
                     taps=((0.05, 0.25), (0.11, 0.14), (0.19, 0.07)))


@sound("shot_smg", 0.35)
def shot_smg(k):
    return r_gunshot(k, crack=1.15, crack_hp=2600.0, crack_tau=0.0045, body=0.9, body_f=1150.0, body_tau=0.018, thump=0.55,
                     thump_f=(230.0, 110.0), thump_tau=0.028, drive=2.0, tail_rt=0.2, tail_wet=0.22,
                     taps=((0.03, 0.15),), mech=0.12, mech_at=0.035)


@sound("shot_shotgun", 0.9)
def shot_shotgun(k):
    return r_gunshot(k, crack=0.8, crack_hp=1400.0, crack_tau=0.014, body=1.4, body_f=420.0, body_q=0.6, body_tau=0.075,
                     thump=1.25, thump_f=(130.0, 48.0), thump_tau=0.12, drive=3.0, tail_rt=0.62, tail_wet=0.4,
                     taps=((0.055, 0.28), (0.12, 0.16), (0.21, 0.09)), lp=9000.0)


@sound("shot_rifle", 0.6)
def shot_rifle(k):
    return r_gunshot(k, crack=1.4, crack_hp=3000.0, crack_tau=0.006, body=0.95, body_f=950.0, body_tau=0.028, thump=0.7,
                     thump_f=(180.0, 75.0), thump_tau=0.05, drive=2.4, tail_rt=0.42, tail_wet=0.34,
                     taps=((0.035, 0.3), (0.08, 0.15), (0.15, 0.08)), presence=3.0)


@sound("shot_sniper", 1.4)
def shot_sniper(k):
    return r_gunshot(k, crack=1.5, crack_hp=2400.0, crack_tau=0.009, body=1.3, body_f=600.0, body_tau=0.055, thump=1.3,
                     thump_f=(140.0, 45.0), thump_tau=0.13, drive=3.0, tail_rt=1.05, tail_wet=0.45,
                     taps=((0.07, 0.32), (0.16, 0.22), (0.29, 0.15), (0.47, 0.09), (0.70, 0.05)), presence=2.0)


@sound("shot_suppressed", 0.3, level=-2.0)
def shot_suppressed(k):
    """'Pfft': soft low-passed gas puff, almost no crack, plus the slide cycling."""
    y = 1.5 * k.f(k.burst(0.022, a=0.002), BP(900.0, 0.7), LP(2600.0, 2))
    y += 0.5 * k.thump(130.0, 70.0, 0.012, 0.03)
    y += 0.25 * k.f(k.burst(0.05, a=0.004), HP(4000.0, 2))
    y = k.sat(norm_peak(y, 0.0), 1.5)
    k.put(y, r_click(k, 2900.0, 0.0025, metal=0.6), 0.024, 0.5)
    k.put(y, r_click(k, 3600.0, 0.002, metal=0.4), 0.062, 0.38)
    return k.rev(y, 0.18, 0.15, hi=5000.0)


@sound("shot_rocket", 1.2)
def shot_rocket(k):
    """Launch: ignition 'fwoomp', then a roaring whoosh that tears away."""
    t = k.t()
    y = 1.2 * k.thump(120.0, 48.0, 0.05, 0.12, attack=0.004)
    y += 0.8 * k.f(k.burst(0.03, a=0.002), BP(600.0, 0.7))
    env = k.pts([(0, 0), (0.05, 1.0), (0.3, 0.8), (1.15, 0.0)], smooth=True)
    roar = k.tvbp(k.white(), k.pts([(0, 500), (0.25, 1700), (1.2, 380)]), 1.1)
    roar += 0.6 * k.f(k.cnoise(-5.0), LP(500.0, 2)) * (0.75 + 0.25 * k.lfon(30.0))
    hiss = k.f(k.white(), HP(3200.0, 2)) * (0.6 + 0.4 * k.lfon(55.0))
    y += (norm_peak(roar, 0.0) * 1.1 + 0.16 * hiss * np.exp(-t / 0.5)) * env
    y = k.sat(norm_peak(y, 0.0), 2.0)
    return k.rev(y, 0.5, 0.2, hi=5000.0)


@sound("shot_launcher", 0.5)
def shot_launcher(k):
    """Grenade launcher 'thoomp': hollow tube resonance + air pop + action click."""
    y = 1.6 * k.thump(190.0, 96.0, 0.02, 0.06, attack=0.002)
    y += 1.0 * k.f(k.burst(0.035, a=0.001), BP(310.0, 3.0))
    y += 0.5 * k.f(k.burst(0.018), LP(1500.0, 2))
    y += 0.3 * k.f(k.burst(0.004), HP(2500.0, 2))
    y = k.sat(norm_peak(y, 0.0), 1.8)
    k.put(y, r_click(k, 2200.0, 0.003, metal=0.5), 0.085, 0.12)
    return k.rev(k.f(y, HP(50.0, 2)), 0.3, 0.2, hi=4000.0)


@sound("dry_fire", 0.12, level=-2.5)
def dry_fire(k):
    y = k.zeros()
    k.put(y, r_click(k, 2400.0, 0.0025, body=0.5, body_f=320.0, metal=0.6), 0.002, 1.0)
    k.put(y, r_click(k, 3900.0, 0.0015, metal=0.3), 0.021, 0.35)
    return y


@sound("reload_pistol", 0.7, level=-2.0)
def reload_pistol(k):
    """Mag release -> mag slides out -> new mag in -> slide racked."""
    y = k.zeros()
    k.put(y, r_click(k, 3200.0, 0.002, metal=0.4), 0.015, 0.6)
    k.put(y, r_scrape(k, 0.11, 1800.0, 3200.0), 0.03, 0.3)
    k.put(y, r_scrape(k, 0.06, 2600.0, 1700.0), 0.29, 0.3)
    k.put(y, r_click(k, 1500.0, 0.004, body=0.9, body_f=180.0, metal=0.3), 0.345, 1.0)
    k.put(y, r_scrape(k, 0.05, 2200.0, 3000.0, q=3.0), 0.5, 0.35)
    k.put(y, r_click(k, 2000.0, 0.003, body=0.4, body_f=260.0, metal=0.5), 0.545, 0.75)
    k.put(y, r_click(k, 2700.0, 0.003, body=0.5, body_f=230.0, metal=0.7), 0.612, 0.95)
    return k.rev(y, 0.15, 0.1, hi=6000.0)


@sound("reload_rifle", 1.1, level=-2.0)
def reload_rifle(k):
    y = k.zeros()
    k.put(y, r_click(k, 2600.0, 0.0025, metal=0.5), 0.02, 0.6)
    k.put(y, r_scrape(k, 0.13, 1300.0, 2400.0), 0.04, 0.35)
    k.put(y, r_click(k, 900.0, 0.006, body=0.7, body_f=140.0), 0.17, 0.45)
    k.put(y, r_scrape(k, 0.07, 2000.0, 1300.0), 0.43, 0.35)
    k.put(y, r_click(k, 1200.0, 0.005, body=1.0, body_f=150.0, metal=0.3), 0.495, 1.0)
    k.put(y, r_click(k, 3100.0, 0.002, metal=0.5), 0.55, 0.45)
    k.put(y, r_scrape(k, 0.07, 1700.0, 2600.0, q=3.0), 0.76, 0.4)
    k.put(y, r_click(k, 1700.0, 0.004, body=0.5, body_f=210.0, metal=0.6), 0.83, 0.8)
    k.put(y, r_click(k, 2300.0, 0.0035, body=0.7, body_f=190.0, metal=0.8), 0.94, 1.0)
    return k.rev(y, 0.16, 0.1, hi=6000.0)


@sound("reload_shotgun", 0.4, level=-2.0)
def reload_shotgun(k):
    """One shell thumbed into the tube."""
    y = k.zeros()
    k.put(y, r_scrape(k, 0.1, 1200.0, 2300.0, q=2.5), 0.015, 0.4)
    k.put(y, r_click(k, 1400.0, 0.004, body=0.8, body_f=220.0, metal=0.3), 0.125, 1.0)
    k.put(y, r_click(k, 3300.0, 0.002, metal=0.5), 0.2, 0.3)
    return k.rev(y, 0.14, 0.1, hi=6000.0)


@sound("pump_shotgun", 0.45)
def pump_shotgun(k):
    """'Chk-chk': fore-end back, fore-end forward."""
    y = k.zeros()
    k.put(y, r_scrape(k, 0.07, 1500.0, 900.0, q=2.0), 0.005, 0.5)
    k.put(y, r_click(k, 1500.0, 0.005, body=0.9, body_f=160.0, metal=0.5), 0.075, 1.0)
    k.put(y, r_scrape(k, 0.06, 1000.0, 1900.0, q=2.0), 0.2, 0.5)
    k.put(y, r_click(k, 1900.0, 0.004, body=0.7, body_f=200.0, metal=0.7), 0.262, 0.95)
    return k.rev(y, 0.16, 0.1, hi=6000.0)


@sound("weapon_switch", 0.25, level=-2.5)
def weapon_switch(k):
    y = k.zeros()
    k.put(y, r_rustle(k, 0.16, 500.0, 4000.0, grain=30.0), 0.0, 0.5)
    k.put(y, r_click(k, 2300.0, 0.003, body=0.5, body_f=240.0, metal=0.4), 0.115, 1.0)
    k.put(y, 0.5 * k.sub(0.08).thump(160.0, 90.0, 0.01, 0.02), 0.12)
    return y


@sound("melee_swing", 0.3, level=-2.5)
def melee_swing(k):
    y = k.zeros()
    k.put(y, r_whoosh(k, 420.0, 2300.0, 760.0, 0.27, q=1.8), 0.0)
    return y


@sound("melee_hit", 0.25)
def melee_hit(k):
    y = 1.5 * k.thump(160.0, 58.0, 0.015, 0.045)
    y += 0.9 * k.f(k.burst(0.02, a=0.0005), BP(320.0, 1.0))
    y += 0.35 * k.f(k.burst(0.004), BP(1800.0, 1.2))
    return k.sat(norm_peak(y, 0.0), 1.6)


@sound("melee_hit_metal", 0.35)
def melee_hit_metal(k):
    f1 = 540.0
    modes = []
    for r, t60, a in ((1.0, 0.26, 1.0), (2.76, 0.2, 0.75), (5.4, 0.14, 0.55), (8.93, 0.09, 0.35), (13.34, 0.06, 0.2)):
        modes += [(f1 * r, t60, a), (f1 * r * 1.013, t60 * 0.8, 0.6 * a, 1.0)]
    y = k.modal(modes)
    y += 0.8 * k.f(k.burst(0.003), BP(2500.0, 0.8))
    y += 0.7 * k.thump(190.0, 110.0, 0.01, 0.025)
    return k.rev(y, 0.25, 0.12, hi=7000.0)


@sound("knife_stab", 0.25, level=-2.0)
def knife_stab(k):
    y = k.zeros()
    k.put(y, r_scrape(k, 0.035, 3500.0, 6500.0, q=2.0), 0.0, 0.55)
    k.put(y, 1.3 * k.sub(0.12).thump(140.0, 62.0, 0.012, 0.03), 0.03)
    sq = k.sub(0.1)
    k.put(y, sq.f(sq.white() * np.abs(sq.lfon(60.0)) ** 2 * sq.exp(0.03), BP(1000.0, 1.5)), 0.035, 3.0)
    return y


@sound("grenade_pin", 0.25, level=-2.5)
def grenade_pin(k):
    y = k.zeros()
    k.put(y, r_click(k, 3400.0, 0.002, metal=0.3), 0.0, 0.7)
    e = k.sub(0.06)
    k.put(y, e.sine(e.sweep(2200.0, 5200.0)) * np.sin(np.pi * e.t() / 0.06) ** 2, 0.012, 0.3)
    k.put(y, k.sub(0.2).modal([(3150.0, 0.16, 1.0), (4730.0, 0.12, 0.7), (6320.0, 0.09, 0.5), (3190.0, 0.14, 0.6), (8900.0, 0.05, 0.3)]), 0.05, 0.9)
    return y


@sound("grenade_bounce", 0.2)
def grenade_bounce(k):
    y = 1.2 * k.thump(240.0, 115.0, 0.008, 0.018)
    y += k.modal([(870.0, 0.05, 1.0), (1460.0, 0.045, 0.8), (2310.0, 0.035, 0.6), (3800.0, 0.02, 0.35)])
    y += 0.6 * k.f(k.burst(0.003), BP(2600.0, 1.0))
    return y


def r_explosion(k, crack=1.0, boom_f=(95.0, 30.0), boom_tau=0.5, body_tau=(0.16, 0.7), lp_from=7000.0, lp_to=220.0,
                lp_time=1.1, debris=0.25, rumble=0.6, rt=1.8, wet=0.3, drive=3.0, attack=0.0):
    """Explosion: blast front + saturated sub boom + noise body whose low-pass closes over time +
    rolling low rumble + falling debris crackle, in a dark reverb."""
    t = k.t()
    y = 1.2 * crack * k.white() * np.exp(-t / 0.004)
    y += 0.8 * crack * k.f(k.burst(0.02), HP(900.0, 2))
    y += 2.4 * k.thump(boom_f[0], boom_f[1], 0.12, boom_tau, attack=0.003)
    body = k.cnoise(-4.5) * (0.6 * np.exp(-t / body_tau[0]) + 0.4 * np.exp(-t / body_tau[1]))
    y += 1.5 * k.tvlp(body, lp_to + (lp_from - lp_to) * np.exp(-t / (lp_time / 3.0)), q=0.8)
    rum = k.f(k.white(), LP(110.0, 4))
    y += rumble * 2.0 * rum / (rms_of(rum) + 1e-9) * (0.6 + 0.4 * k.lfon(6.0)) * k.exp(boom_tau * 1.6, a=0.03)
    y = k.sat(norm_peak(y, 0.0), drive)
    if debris:
        dens = np.clip((t - 0.12) / 0.3, 0.0, 1.0) * np.exp(-t / (0.35 * k.dur))
        d = k.f(k.sparks(900.0, power=3.0) * dens, BP(2600.0, 0.9), LP(7000.0, 1))
        y += debris * 6.0 * d
        for _ in range(4):
            e = k.sub(0.12)
            k.put(y, e.thump(k.u(90, 160), 60.0, 0.01, 0.03) + 0.4 * e.f(e.burst(0.01), BP(k.u(700, 1500), 1.0)),
                  k.u(0.25, 0.6) * k.dur, debris * k.u(0.3, 0.7))
    if attack:
        y = k.fade(y, fin=attack)
    y = k.f(y, HP(28.0, 2))
    return k.rev(y, rt, wet, hf=0.4, hi=3500.0, lo=90.0)


@sound("explosion_big", 2.8)
def explosion_big(k):
    return r_explosion(k)


@sound("explosion_small", 1.6)
def explosion_small(k):
    return r_explosion(k, boom_f=(130.0, 46.0), boom_tau=0.24, body_tau=(0.09, 0.36), lp_from=8000.0, lp_to=320.0,
                       lp_time=0.6, debris=0.2, rumble=0.35, rt=1.0, wet=0.26, drive=2.6)


@sound("explosion_distant", 2.5, level=-2.0)
def explosion_distant(k):
    """Far-off blast: no crack, soft onset, everything rolled off, echoes rolling in."""
    y = r_explosion(k, crack=0.0, boom_f=(80.0, 34.0), boom_tau=0.6, body_tau=(0.25, 0.8), lp_from=900.0, lp_to=160.0,
                    lp_time=1.0, debris=0.0, rumble=0.9, rt=2.2, wet=0.5, drive=2.0, attack=0.05)
    y = k.f(y, LP(420.0, 2))
    d = y.copy()
    put(y, d, int(0.31 * k.sr), 0.45)
    put(y, k.f(d, LP(240.0, 2)), int(0.74 * k.sr), 0.3)
    return y


@sound("rocket_fly", 2.0, loop=True, level=-16.0)
def rocket_fly(k):
    roar = k.cnoise(-5.0, lo=45.0, hi=1100.0) * (0.75 + 0.25 * k.lfon(28.0))
    hiss = k.bnoise(2500.0, 9000.0) * (0.6 + 0.4 * k.lfon(60.0))
    whistle = k.tvbp(k.white(), k.wander(1.5, 850.0, 1350.0), 6.0)
    y = roar + 0.3 * hiss + 0.25 * whistle / (rms_of(whistle) + 1e-9)
    y *= 1.0 + 0.15 * k.lfon(11.0)
    return k.f(k.sat(y * 0.35, 1.6), LP(10000.0, 4))


@sound("bullet_impact_concrete", 0.25)
def bullet_impact_concrete(k):
    y = 1.2 * k.f(k.burst(0.0015), HP(1500.0, 2))
    y += k.f(k.burst(0.012), BP(2600.0, 0.9))
    y += 0.7 * k.thump(260.0, 120.0, 0.006, 0.015)
    y += 0.5 * k.f(k.burst(0.05, a=0.004), LP(1300.0, 2))
    chips = k.f(k.sparks(160.0, power=2.0) * k.pts([(0, 0), (0.03, 1), (0.2, 0)]), BP(4200.0, 1.5))
    return y + 2.5 * chips


@sound("bullet_impact_metal", 0.3)
def bullet_impact_metal(k):
    """Sharp 'tink' on plate + ringing partials + a ricochet whine falling away."""
    y = 0.9 * k.f(k.burst(0.0012), HP(2000.0, 2))
    modes = []
    for f, t60, a in ((2380.0, 0.2, 1.0), (3910.0, 0.16, 0.8), (5730.0, 0.12, 0.6), (8120.0, 0.08, 0.4), (1190.0, 0.07, 0.5)):
        modes += [(f, t60, a), (f * 1.009, t60 * 0.9, 0.5 * a, 1.3)]
    y += 0.8 * k.modal(modes)
    e = k.sub(0.26)
    whine = e.sine(e.sweep(3300.0, 1250.0) * (1.0 + 0.02 * e.lfo(34.0)))
    k.put(y, whine * e.pts([(0, 0), (0.012, 1), (0.25, 0)]) ** 1.5, 0.008, 0.5)
    return k.rev(y, 0.25, 0.12, hi=8000.0)


@sound("bullet_impact_flesh", 0.2, level=-2.0)
def bullet_impact_flesh(k):
    y = 1.4 * k.thump(170.0, 68.0, 0.01, 0.025)
    y += 0.9 * k.f(k.burst(0.016, a=0.0005), LP(750.0, 2))
    y += 1.2 * k.f(k.white() * np.abs(k.lfon(70.0)) ** 2 * k.exp(0.03), BP(1250.0, 2.0))
    return y


@sound("bullet_impact_glass", 0.3)
def bullet_impact_glass(k):
    y = 1.1 * k.f(k.burst(0.004), HP(3000.0, 2))
    modes = [(k.u(2000, 9500), k.u(0.03, 0.13), k.u(0.3, 1.0), k.u(0, 6.28)) for _ in range(12)]
    y += 0.9 * k.modal(modes)
    for _ in range(6):
        e = k.sub(0.09)
        f = k.u(3500, 10500)
        k.put(y, e.modal([(f, k.u(0.02, 0.07), 1.0), (f * 1.47, 0.03, 0.5)]), k.u(0.03, 0.2), k.u(0.15, 0.45))
    return y


@sound("bullet_impact_dirt", 0.25, level=-2.0)
def bullet_impact_dirt(k):
    y = 1.4 * k.thump(150.0, 62.0, 0.012, 0.03)
    y += 1.0 * k.f(k.burst(0.024, a=0.001), LP(950.0, 2))
    spray = k.f(k.white() * np.abs(k.lfon(90.0)) ** 2 * k.pts([(0, 0), (0.02, 1), (0.2, 0)]), BP(2100.0, 0.8))
    return y + 0.5 * spray


@sound("bullet_impact_water", 0.35, level=-2.0)
def bullet_impact_water(k):
    y = k.zeros()
    e = k.sub(0.06)
    k.put(y, e.sine(e.sweep(500.0, 1900.0)) * e.exp(0.014, a=0.001), 0.0, 1.0)
    k.put(y, 0.7 * k.f(k.burst(0.03, a=0.003), BP(2600.0, 0.8)), 0.0)
    k.put(y, r_bubbles(k, 26, 500.0, 3200.0, 0.3, t_pow=1.3), 0.02, 0.8)
    return y


@sound("bullet_whiz", 0.3, level=-2.5)
def bullet_whiz(k):
    """Supersonic pass-by: a tight noise band + a 'zing' that both drop in pitch (Doppler)."""
    env = k.pts([(0, 0), (0.035, 1.0), (0.11, 0.25), (0.28, 0.0)], smooth=True)
    fc = k.pts([(0, 5200.0), (0.05, 3800.0), (0.12, 1500.0), (0.3, 1100.0)])
    y = k.tvbp(k.white(), fc, 5.0)
    y = y / (peak_of(y) + 1e-9) + 0.35 * k.sine(fc * 0.8)
    return k.rev(y * env, 0.2, 0.12, hi=7000.0)


@sound("glass_break", 0.9)
def glass_break(k):
    """Pane shatters: crash transient + plate modes, then a cascade of falling shards."""
    y = 1.3 * k.f(k.burst(0.012), HP(1800.0, 2))
    y += 0.6 * k.f(k.burst(0.05, a=0.002), BP(3200.0, 0.6))
    y += 0.9 * k.modal([(k.u(700, 6500), k.u(0.04, 0.2), k.u(0.3, 1.0), k.u(0, 6.28)) for _ in range(18)])
    for _ in range(46):
        e = k.sub(0.1)
        f = k.u(2400, 11500)
        at = 0.03 + 0.68 * k.rng.random() ** 1.5
        sh = e.modal([(f, k.u(0.02, 0.09), 1.0), (f * k.u(1.3, 1.7), 0.03, 0.5), (f * k.u(2.1, 2.6), 0.02, 0.3)])
        sh += 0.3 * e.f(e.burst(0.0015), HP(3000.0, 2))
        k.put(y, sh, at, k.u(0.12, 0.5) * (1.0 - 0.6 * at))
    return k.rev(y, 0.3, 0.12, hi=9000.0)


@sound("shell_drop", 0.3, level=-2.5)
def shell_drop(k):
    """Brass casing: a few bounces with shrinking gaps, each a tiny bright ring."""
    y = k.zeros()
    for at, g in ((0.0, 1.0), (0.072, 0.6), (0.126, 0.42), (0.165, 0.28), (0.193, 0.18), (0.212, 0.1)):
        e = k.sub(0.085)
        f = 4250.0 * k.u(0.94, 1.06)
        ring = e.modal([(f, 0.05, 1.0), (f * 1.012, 0.045, 0.6, 1.0), (f * 1.63, 0.035, 0.7), (f * 2.31, 0.025, 0.45), (f * 0.52, 0.02, 0.3)])
        k.put(y, ring + 0.4 * e.f(e.burst(0.001), HP(3500.0, 2)), at, g)
    return y


# ----------------------------------------------------------------------------------------------
# 5b. PLAYER / CHARACTERS  (non-verbal: grunts and screams are formant-filtered pulse trains)
# ----------------------------------------------------------------------------------------------

family("player")

V_UH = [(700.0, 620.0, 95.0), (1220.0, 1130.0, 110.0), (2600.0, 2480.0, 160.0), (3450.0, 3350.0, 220.0)]
V_AH = [(780.0, 720.0, 110.0), (1250.0, 1150.0, 125.0), (2600.0, 2500.0, 175.0), (3600.0, 3500.0, 240.0)]


def r_tick(k, fc, tau, q=1.0):
    """Hard contact transient: a short noise burst through one resonance (normalised)."""
    e = k.sub(tau * 14.0 + 0.012)
    y = e.f(e.burst(tau), BP(fc, q))
    return y / (peak_of(y) + 1e-9)


def r_grit(k, sec, rate, lo, hi, rise=0.004, tau=0.03, power=2.0):
    """Granular crunch / grit / grass blades: Poisson micro-impacts under an attack-decay density."""
    e = k.sub(sec)
    t = e.t()
    dens = np.minimum(1.0, t / max(rise, 1e-4)) * np.exp(-t / tau)
    y = e.f(e.sparks(rate, power=power) * dens, HP(lo, 2), LP(hi, 2))
    return y / (peak_of(y) + 1e-9)


def r_thud(k, f0, f1, tau, lp=500.0, noise=0.4, attack=0.0015):
    """Soft body impact: pitch-dropping sine + low-passed noise puff."""
    e = k.sub(tau * 7.0 + 0.03)
    y = e.thump(f0, f1, tau * 0.3, tau, attack=attack)
    y += noise * e.f(e.burst(tau * 0.6, a=attack), LP(lp, 2)) * 1.5
    return y / (peak_of(y) + 1e-9)


def band_energy(x, sr, lo, hi):
    S = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    return float(S[(f >= lo) & (f < hi)].sum())


def r_vocal(k, sec, f0, forms, env, presence=14.0, air=-30.0, **kw):
    """r_voice (higher-pole corrected) under a smooth break-point envelope [(t, a), ...], normalised.
    Calibrated against long-term speech spectra (bands re the 400-1000 Hz band; grunt / scream):
    1-2.5 kHz ~ -8 / -1, 2.5-6 kHz ~ -18 / -9, 6-12 kHz ~ -30 / -20 dB.  `presence` is the high shelf
    of the missing pole tail (+14 dB modal voice, ~+18 shouted); `air` sets the parallel aspiration
    bypass (Klatt-style, follows the voice envelope) as its 6-12 kHz energy in dB re the F1 band."""
    kw.setdefault("tilt", 600.0)
    y = r_voice(k, sec, f0, forms, hpc=True, **kw) * env_pts(int(round(sec * k.sr)), k.sr, env, smooth=True)
    y = filt(y, k.sr, HS(1800.0, presence), LP(9000.0, 2), tail=0.01)
    if air is not None:
        e = k.sub(sec)
        follow = np.maximum(filt(np.abs(y), k.sr, LP(40.0, 2), tail=0.01), 0.0)
        nz = e.f(e.white(), HP(3200.0, 2), LP(11000.0, 2)) * follow
        g = math.sqrt(band_energy(y, k.sr, 400.0, 1000.0) * 10.0 ** (air / 10.0) / (band_energy(nz, k.sr, 6000.0, 12000.0) + 1e-20))
        y = y + g * nz
    return y / (peak_of(y) + 1e-9)


def r_breath(k, sec, forms, env, hp=400.0, lp=9000.0, air=0.12):
    """Unvoiced breath (inhale / exhale): noise through a parallel formant bank (Klatt's frication
    path: forms = [(F, bandwidth), ...], falling gains) plus a little broadband air, under an envelope."""
    e = k.sub(sec)
    bank = [(F, F / max(bw, 1.0), 1.0 / (1.0 + 0.45 * i)) for i, (F, bw) in enumerate(forms)]
    y = e.f(e.white(), BANK(bank, direct=air), HP(hp, 2), LP(lp, 2))
    y = y / (peak_of(y) + 1e-9) * e.pts(env, smooth=True)
    return y / (peak_of(y) + 1e-9)


# ---- footsteps: heel strike + toe roll per surface; every numbered variant draws its own seed ----

STEP_LOWCUT = 115.0       # game-style low cut: footsteps keep their weight in 150-400 Hz, not in the sub


def r_sole(k, fc, tau, q=1.0):
    """Shoe sole slap: short mid-band noise burst (what makes a step audible on small speakers)."""
    e = k.sub(tau * 10.0 + 0.012)
    y = e.f(e.burst(tau, a=0.0004), BP(fc, q))
    return y / (peak_of(y) + 1e-9)


def footstep_concrete(k):
    y = k.zeros()
    p = k.u(0.9, 1.12)
    e = k.sub(0.12)
    heel = 0.55 * e.thump(205.0 * p, 120.0 * p, 0.004, 0.012, attack=0.0008)
    heel += 0.9 * e.f(e.burst(0.0022), BP(2300.0 * p, 1.1)) + 0.3 * e.f(e.burst(0.0008), HP(3500.0, 2))
    k.put(y, heel, 0.004)
    k.put(y, r_sole(k, 620.0 * p, 0.006, 1.1), 0.004, 0.35)
    k.put(y, r_grit(k, 0.05, 900.0, 2500.0, 9000.0, tau=0.012), 0.006, 0.12)
    toe_at = k.u(0.038, 0.058)
    e = k.sub(0.1)
    toe = 0.3 * e.thump(230.0 * p, 135.0 * p, 0.004, 0.008) + 0.55 * e.f(e.burst(0.0016), BP(2900.0 * p, 1.3))
    k.put(y, toe, toe_at, k.u(0.35, 0.55))
    k.put(y, r_sole(k, 800.0 * p, 0.004, 1.2), toe_at, 0.15)
    k.put(y, r_scrape(k, 0.045, 2600.0, 4200.0, q=1.8), toe_at + 0.004, k.u(0.04, 0.1))
    y = k.f(y, HP(STEP_LOWCUT, 2))
    return r_tail(k, y, 0.16, 0.07, ((0.011, 0.12), (0.019, 0.06)), lp=5000.0)


def footstep_grass(k):
    y = k.zeros()
    p = k.u(0.9, 1.1)
    k.put(y, r_thud(k, 150.0 * p, 85.0 * p, 0.018, lp=500.0, noise=0.6, attack=0.003), 0.004, 0.55)
    k.put(y, r_grit(k, 0.13, 2600.0, 1800.0, 8500.0, rise=0.006, tau=0.035, power=1.6), 0.002, 0.55)
    e = k.sub(0.12)
    k.put(y, r_rustle(k, 0.12, 1200.0, 6500.0, grain=70.0, sharp=1.5) * np.sin(np.pi * e.t() / 0.12) ** 2, 0.0, 0.32)
    k.put(y, r_sole(k, 480.0 * p, 0.01, 0.8), 0.006, 0.2)
    toe_at = k.u(0.045, 0.065)
    k.put(y, r_grit(k, 0.09, 2000.0, 2200.0, 9000.0, rise=0.004, tau=0.022, power=1.6), toe_at, 0.32)
    k.put(y, r_thud(k, 170.0 * p, 100.0 * p, 0.01, lp=600.0, attack=0.002), toe_at, 0.22)
    return k.f(y, HP(STEP_LOWCUT, 2))


def footstep_sand(k):
    y = k.zeros()
    p = k.u(0.92, 1.08)
    k.put(y, r_thud(k, 130.0 * p, 75.0 * p, 0.022, lp=450.0, noise=0.7, attack=0.006), 0.003, 0.55)
    k.put(y, r_grit(k, 0.13, 5200.0, 700.0, 5200.0, rise=0.01, tau=0.04, power=1.3), 0.002, 0.7)
    e = k.sub(0.1)
    sh = e.bnoise(900.0, 4200.0) * e.pts([(0, 0), (0.012, 1.0), (0.1, 0.0)], smooth=True)
    k.put(y, sh / (peak_of(sh) + 1e-9), 0.004, 0.22)
    toe_at = k.u(0.05, 0.07)
    k.put(y, r_grit(k, 0.09, 4200.0, 900.0, 6000.0, rise=0.006, tau=0.025, power=1.3), toe_at, 0.38)
    return k.f(y, HP(STEP_LOWCUT, 2))


def footstep_metal(k):
    y = k.zeros()
    p = k.u(0.92, 1.1)
    for at, g, f1 in ((0.004, 1.0, 410.0 * p), (k.u(0.04, 0.055), k.u(0.4, 0.55), 455.0 * p)):
        e = k.sub(0.16)
        modes = [(f1 * r, t60 * k.u(0.85, 1.15), a, k.u(0, 6.28)) for r, t60, a in
                 ((1.0, 0.13, 1.0), (1.59, 0.1, 0.7), (2.14, 0.085, 0.55), (2.65, 0.075, 0.45), (3.56, 0.06, 0.35),
                  (4.07, 0.05, 0.3), (5.93, 0.04, 0.2))]
        hit = 0.5 * e.thump(190.0 * p, 120.0 * p, 0.004, 0.012) + 0.8 * e.f(e.burst(0.0018), BP(3100.0, 1.0))
        hit += 0.45 * e.modal(modes) + 0.22 * e.modal([(k.u(2200, 5200), k.u(0.02, 0.05), k.u(0.3, 1.0), k.u(0, 6.28)) for _ in range(6)])
        k.put(y, hit, at, g)
    y = k.f(y, HP(STEP_LOWCUT, 2))
    return r_tail(k, y, 0.15, 0.06, ((0.013, 0.1),), lp=6000.0)


def footstep_wood(k):
    y = k.zeros()
    p = k.u(0.92, 1.1)
    for at, g in ((0.004, 1.0), (k.u(0.042, 0.06), k.u(0.35, 0.5))):
        e = k.sub(0.14)
        hit = 0.55 * e.thump(165.0 * p, 100.0 * p, 0.005, 0.015, attack=0.001)
        hit += 0.9 * e.f(e.burst(0.01, a=0.0005), BP(240.0 * p, 4.0)) * 1.5
        hit += 0.7 * e.f(e.burst(0.002), BP(1700.0 * p, 1.2))
        hit += 0.6 * e.modal([(640.0 * p, 0.06, 1.0), (1050.0 * p, 0.045, 0.6), (1720.0 * p, 0.03, 0.4), (2600.0 * p, 0.02, 0.25)])
        k.put(y, hit, at, g)
    y = k.f(y, HP(STEP_LOWCUT - 15.0, 2))
    return r_tail(k, y, 0.18, 0.08, ((0.009, 0.12), (0.016, 0.07)), lp=4500.0)


for _i in range(1, 5):
    sound(f"footstep_concrete_{_i}", 0.18, level=-2.0)(footstep_concrete)
for _i in range(1, 4):
    sound(f"footstep_grass_{_i}", 0.18, level=-2.5)(footstep_grass)
for _surf, _fn in (("sand", footstep_sand), ("metal", footstep_metal), ("wood", footstep_wood)):
    for _i in (1, 2):
        sound(f"footstep_{_surf}_{_i}", 0.18, level=-2.0 if _surf != "sand" else -2.5)(_fn)


@sound("jump", 0.2, level=-2.5)
def jump(k):
    """Push-off scuff + cloth swish + a small breathy 'hup'."""
    y = k.zeros()
    k.put(y, r_scrape(k, 0.05, 2200.0, 3600.0, q=1.6), 0.0, 0.3)
    k.put(y, r_thud(k, 150.0, 90.0, 0.012), 0.002, 0.4)
    k.put(y, r_whoosh(k, 500.0, 1700.0, 800.0, 0.16, q=1.1, peak=0.35, air=0.4), 0.012, 0.55)
    k.put(y, r_rustle(k, 0.12, 900.0, 6000.0, grain=50.0), 0.02, 0.18)
    k.put(y, r_breath(k, 0.11, [(650.0, 180.0), (1300.0, 220.0), (2500.0, 300.0)], [(0, 0), (0.015, 1.0), (0.11, 0.0)], hp=500.0), 0.03, 0.2)
    k.put(y, r_vocal(k, 0.09, [(0, 170.0), (0.03, 192.0), (0.09, 150.0)], V_UH, [(0, 0), (0.01, 1.0), (0.05, 0.6), (0.09, 0.0)],
                     breath=0.45, rough=0.15), 0.035, 0.22)
    return y


@sound("land", 0.25, level=-2.0)
def land(k):
    y = k.zeros()
    k.put(y, r_thud(k, 135.0, 62.0, 0.035, lp=550.0, noise=0.5), 0.003, 0.8)
    k.put(y, r_sole(k, 520.0, 0.012, 0.9), 0.003, 0.45)
    for at, g in ((0.002, 0.6), (0.016, 0.42)):
        k.put(y, r_tick(k, k.u(1600.0, 2200.0), 0.0025, 1.0), at, g)
    k.put(y, r_rustle(k, 0.14, 700.0, 5000.0, grain=40.0), 0.0, 0.22)
    k.put(y, r_grit(k, 0.08, 1200.0, 2500.0, 9000.0, tau=0.02), 0.004, 0.14)
    y = k.f(y, HP(70.0, 2))
    return r_tail(k, y, 0.18, 0.06, ((0.012, 0.1),), lp=4000.0)


@sound("land_hard", 0.4)
def land_hard(k):
    y = k.zeros()
    e = k.sub(0.3)
    thud = 1.0 * e.thump(118.0, 48.0, 0.014, 0.07, attack=0.002)
    thud += 0.8 * e.f(e.burst(0.05, a=0.001), LP(700.0, 2)) + 0.9 * e.f(e.burst(0.04), BP(260.0, 1.2))
    thud += 0.7 * e.f(e.burst(0.018, a=0.0005), BP(480.0, 0.9))
    k.put(y, thud, 0.003)
    for at, g in ((0.0, 0.55), (0.011, 0.45)):
        k.put(y, r_tick(k, k.u(1400.0, 2000.0), 0.003, 0.9), at, g)
    for _ in range(5):
        k.put(y, r_click(k, k.u(2500.0, 4500.0), 0.0015, metal=0.6), k.u(0.03, 0.13), k.u(0.04, 0.09))
    k.put(y, r_rustle(k, 0.25, 400.0, 3500.0, grain=30.0), 0.0, 0.32)
    k.put(y, r_grit(k, 0.12, 1500.0, 2000.0, 8000.0, tau=0.03), 0.004, 0.18)
    k.put(y, r_vocal(k, 0.16, [(0, 135.0), (0.04, 150.0), (0.16, 105.0)], V_UH, [(0, 0), (0.012, 1.0), (0.07, 0.6), (0.16, 0.0)],
                     breath=0.3, rough=0.3, sub=0.3), 0.035, 0.3)
    y = k.sat(norm_peak(y, 0.0), 1.3)
    return r_tail(k, y, 0.22, 0.07, ((0.014, 0.1),), lp=4000.0)


@sound("body_fall", 0.6)
def body_fall(k):
    """Torso, then limbs and head settling, cloth, a short slide."""
    y = k.zeros()
    for at, f0, f1, tau, g in ((0.0, 110.0, 50.0, 0.065, 1.0), (0.085, 150.0, 75.0, 0.03, 0.45), (0.15, 130.0, 62.0, 0.04, 0.6),
                               (0.26, 160.0, 80.0, 0.025, 0.3), (0.31, 140.0, 70.0, 0.02, 0.18)):
        k.put(y, r_thud(k, f0, f1, tau, lp=650.0, noise=0.6), at + 0.003, g)
        k.put(y, r_sole(k, k.u(380.0, 520.0), tau * 0.35, 0.9), at + 0.003, 0.45 * g)
        k.put(y, r_tick(k, k.u(900.0, 1400.0), 0.004, 0.8), at + 0.002, 0.3 * g)
    k.put(y, r_rustle(k, 0.45, 500.0, 4000.0, grain=35.0) * np.sin(np.pi * k.sub(0.45).t() / 0.45), 0.0, 0.3)
    k.put(y, r_scrape(k, 0.18, 700.0, 450.0, q=1.2), 0.3, 0.1)
    for _ in range(3):
        k.put(y, r_click(k, k.u(2000.0, 4000.0), 0.0015, metal=0.5), k.u(0.02, 0.2), k.u(0.03, 0.06))
    return r_tail(k, y, 0.28, 0.08, ((0.015, 0.08),), lp=3500.0)


HURT = {
    1: dict(f0=[(0, 150.0), (0.035, 178.0), (0.16, 128.0), (0.26, 98.0)], forms=V_UH, breath=0.18, rough=0.25, sub=0.3,
            env=[(0, 0), (0.008, 1.0), (0.09, 0.75), (0.25, 0.0)]),
    2: dict(f0=[(0, 195.0), (0.03, 235.0), (0.14, 175.0), (0.22, 135.0)],
            forms=[(560.0, 500.0, 85.0), (1750.0, 1600.0, 120.0), (2600.0, 2500.0, 150.0), (3600.0, 3500.0, 210.0)],
            breath=0.14, rough=0.2, sub=0.2, env=[(0, 0), (0.006, 1.0), (0.07, 0.7), (0.21, 0.0)]),
    3: dict(f0=[(0, 125.0), (0.05, 142.0), (0.18, 100.0), (0.27, 82.0)],
            forms=[(480.0, 400.0, 90.0), (900.0, 800.0, 100.0), (2400.0, 2300.0, 150.0), (3300.0, 3200.0, 210.0)],
            breath=0.35, rough=0.4, sub=0.35, env=[(0, 0), (0.012, 1.0), (0.1, 0.8), (0.27, 0.0)]),
}


def hurt(k, v):
    """Short pained grunt (closed-mouth / open-mouth / breathy variants)."""
    p = HURT[v]
    y = k.zeros()
    g = r_vocal(k, 0.27, p["f0"], p["forms"], p["env"], breath=p["breath"], rough=p["rough"], sub=p["sub"], jitter=0.02)
    k.put(y, g, 0.004)
    return k.rev(y, 0.2, 0.08, hi=6000.0)


for _i in (1, 2, 3):
    sound(f"hurt_{_i}", 0.3, v=_i)(hurt)


@sound("death", 0.9, level=-2.0)
def death(k):
    """Falling, weakening groan that closes from 'ah' to 'uh', then a last exhale."""
    y = k.zeros()
    g = r_vocal(k, 0.68, [(0, 160.0), (0.06, 182.0), (0.3, 150.0), (0.52, 112.0), (0.68, 86.0)],
                [(760.0, 520.0, 100.0), (1220.0, 980.0, 120.0), (2550.0, 2380.0, 170.0), (3500.0, 3300.0, 230.0)],
                [(0, 0), (0.03, 1.0), (0.25, 0.85), (0.5, 0.5), (0.68, 0.0)], breath=0.25, rough=0.35, sub=0.3, jitter=0.02, shimmer=0.12)
    k.put(y, g, 0.005)
    k.put(y, r_breath(k, 0.3, [(520.0, 200.0), (1000.0, 240.0), (2400.0, 320.0)], [(0, 0), (0.06, 1.0), (0.3, 0.0)], hp=300.0, lp=4000.0), 0.5, 0.25)
    return k.rev(y, 0.3, 0.1, hi=5500.0)


SCREAM = {
    1: dict(sec=1.0, f0=[(0, 380.0), (0.07, 620.0), (0.25, 690.0), (0.55, 650.0), (0.72, 520.0), (0.8, 430.0)], vib=(5.8, 0.022),
            forms=[(900.0, 820.0, 130.0), (1500.0, 1400.0, 160.0), (3000.0, 2850.0, 240.0), (4200.0, 4100.0, 320.0)],
            breath=0.3, rough=0.18, sub=0.12, tilt=700.0),
    2: dict(sec=0.85, f0=[(0, 470.0), (0.05, 760.0), (0.25, 830.0), (0.48, 760.0), (0.65, 610.0)], vib=(6.5, 0.025),
            forms=[(700.0, 640.0, 120.0), (2100.0, 1950.0, 180.0), (3100.0, 3000.0, 250.0), (4300.0, 4200.0, 320.0)],
            breath=0.28, rough=0.15, sub=0.1, tilt=750.0),
    3: dict(sec=1.2, f0=[(0, 205.0), (0.09, 330.0), (0.4, 362.0), (0.72, 335.0), (0.9, 255.0), (1.0, 205.0)], vib=(5.2, 0.02),
            forms=[(820.0, 740.0, 110.0), (1300.0, 1180.0, 130.0), (2600.0, 2480.0, 180.0), (3600.0, 3500.0, 250.0)],
            breath=0.32, rough=0.3, sub=0.22, tilt=650.0),
}


def scream(k, v):
    """Panic yelp: fast pitch rise, wavering held cry, falling release; outdoor slap + tail."""
    p = SCREAM[v]
    sec = p["f0"][-1][0]
    n = int(round(sec * k.sr))
    t = tvec(n, k.sr)
    rate, depth = p["vib"]
    f0 = env_pts(n, k.sr, p["f0"], smooth=True)
    f0 = f0 * (1.0 + depth * np.clip(t / 0.25, 0.0, 1.0) * np.sin(TAU * rate * t + k.u(0, 6.28)))
    env = [(0, 0), (0.035, 0.8), (0.12, 1.0), (sec * 0.7, 0.9), (sec, 0.0)]
    g = r_vocal(k, sec, f0, p["forms"], env, presence=18.0, air=-20.0, breath=p["breath"], rough=p["rough"], sub=p["sub"],
                tilt=p["tilt"], jitter=0.025, shimmer=0.1)
    y = k.zeros()
    k.put(y, g, 0.005)
    return r_tail(k, y, 0.45, 0.16, ((0.09, 0.14), (0.17, 0.07)), lp=4500.0)


for _i in (1, 2, 3):
    sound(f"scream_{_i}", SCREAM[_i]["sec"], level=-1.5, v=_i)(scream)


@sound("swim_stroke", 0.5, level=-2.5)
def swim_stroke(k):
    """Hand entry, the pull's water swoosh, a few bubbles and drips."""
    y = k.zeros()
    e = k.sub(0.12)
    entry = e.f(e.burst(0.025, a=0.002), BP(2300.0, 0.7)) + 0.4 * e.sine(e.sweep(380.0, 1100.0)) * e.exp(0.015, a=0.002)
    k.put(y, entry / (peak_of(entry) + 1e-9), 0.01, 0.7)
    e = k.sub(0.36)
    sw = e.tvbp(e.white() * (0.6 + 0.4 * np.abs(e.lfon(30.0))), e.pts([(0, 280.0), (0.15, 650.0), (0.36, 260.0)]), 1.1)
    sw *= np.sin(np.pi * e.t() / 0.36) ** 1.5
    k.put(y, sw / (peak_of(sw) + 1e-9), 0.05, 0.75)
    k.put(y, r_bubbles(k, 16, 420.0, 2400.0, 0.3, t_pow=1.4), 0.07, 0.35)
    for _ in range(5):
        e = k.sub(0.05)
        f = k.u(1300.0, 3200.0)
        k.put(y, e.sine(e.sweep(f, f * 1.4)) * e.exp(0.008, a=0.0005), k.u(0.25, 0.4), k.u(0.06, 0.15))
    return r_tail(k, y, 0.22, 0.08, ((0.02, 0.08),), lp=6000.0)


def r_splash(k, scale=1.0):
    """Body / object into water: slap, cavity thoomp, spray, bubble cloud and falling droplets."""
    y = k.zeros()
    s = scale
    e = k.sub(0.3)
    slap = e.f(e.burst(0.012 * s, a=0.0008), HP(300.0 / s, 2)) + 0.6 * e.f(e.burst(0.004), BP(1400.0 / s ** 0.5, 0.8))
    k.put(y, slap / (peak_of(slap) + 1e-9), 0.0, 1.0)
    e = k.sub(0.55 * s)
    k.put(y, e.thump(125.0 / s ** 0.6, 52.0 / s ** 0.6, 0.03 * s, 0.11 * s, attack=0.008), 0.02, 1.1 * min(1.0, s))
    e = k.sub(0.85 * s)
    spray = e.f(e.white(), HP(1400.0, 2), LP(9500.0, 2)) * (0.4 + 0.6 * np.abs(e.lfon(140.0)))
    spray *= e.pts([(0, 0), (0.02, 1.0), (0.15 * s, 0.55), (0.85 * s, 0.0)], smooth=True)
    k.put(y, spray / (peak_of(spray) + 1e-9), 0.01, 0.55)
    body = e.f(e.white(), BP(650.0 / s ** 0.5, 0.6)) * e.exp(0.14 * s, a=0.006)
    k.put(y, body / (peak_of(body) + 1e-9), 0.01, 0.6)
    k.put(y, r_bubbles(k, int(110 * s), 170.0 / s, 1500.0 / s ** 0.5, 0.8 * s, t_pow=1.5), 0.04, 0.45)
    for i in range(int(30 * s)):
        e = k.sub(0.06)
        f = k.u(700.0, 3200.0)
        at = k.u(0.22, 0.85) * s
        d = e.sine(e.sweep(f, f * k.u(1.2, 1.5))) * e.exp(k.u(0.005, 0.011), a=0.0005)
        k.put(y, d, at, k.u(0.05, 0.16) * (1.0 - 0.6 * at / s))
    return r_tail(k, y, 0.4 * s ** 0.5, 0.12, ((0.06 * s, 0.1),), lp=6000.0)


@sound("splash_big", 1.2)
def splash_big(k):
    return r_splash(k, 1.0)


@sound("splash_small", 0.5)
def splash_small(k):
    return r_splash(k, 0.42)


@sound("underwater_loop", 6.0, loop=True, check=dict(aperiodic=True))
def underwater_loop(k):
    """Muffled pressure rumble, slow swells, distant hiss and drifting bubble streams."""
    y = k.cnoise(-6.0, lo=25.0, hi=500.0) * (0.75 + 0.25 * k.lfon(0.35))
    y += 0.25 * k.bnoise(120.0, 900.0) * (0.6 + 0.4 * k.lfon(1.2))
    y += 0.06 * k.cnoise(-3.0, lo=900.0, hi=2500.0) * (0.5 + 0.5 * k.lfon(0.8))
    for _ in range(10):
        sec = k.u(0.4, 0.9)
        b = r_bubbles(k, int(k.u(5, 14)), 140.0, 650.0, sec, t_pow=1.0)
        k.put(y, k.sub(sec).f(b, LP(1100.0, 2)), k.u(0.0, 6.0), k.u(0.15, 0.4))
    return k.f(y, LP(1600.0, 2))


@sound("breath_gasp", 0.8, level=-2.0)
def breath_gasp(k):
    """Surfacing gasp: sharp inhale with a little voicing, a second catch-breath, an exhale."""
    y = k.zeros()
    open_mouth = [(820.0, 220.0), (1500.0, 260.0), (2600.0, 320.0), (3600.0, 400.0)]
    k.put(y, r_breath(k, 0.36, open_mouth, [(0, 0), (0.025, 1.0), (0.09, 0.8), (0.25, 0.4), (0.36, 0.0)], hp=500.0), 0.01, 1.0)
    k.put(y, r_vocal(k, 0.2, [(0, 330.0), (0.2, 390.0)], [(850.0, 800.0, 150.0), (1600.0, 1500.0, 200.0), (2700.0, 2600.0, 260.0)],
                     [(0, 0), (0.03, 1.0), (0.2, 0.0)], breath=2.5, rough=0.1), 0.02, 0.16)
    k.put(y, r_breath(k, 0.14, open_mouth, [(0, 0), (0.02, 1.0), (0.14, 0.0)], hp=600.0), 0.37, 0.5)
    k.put(y, r_breath(k, 0.26, [(600.0, 200.0), (1150.0, 240.0), (2400.0, 320.0)], [(0, 0), (0.05, 1.0), (0.26, 0.0)], hp=300.0, lp=3500.0),
          0.5, 0.38)
    return k.rev(y, 0.22, 0.08, hi=6000.0)


@sound("heartbeat", 1.6, loop=True, level=-19.0)
def heartbeat(k):
    """'Lub-dub' twice (75 bpm); the two beats differ slightly."""
    y = k.zeros()
    for i, at in enumerate((0.04, 0.84)):
        g, p = (1.0, 1.0) if i == 0 else (0.92, 0.97)
        e = k.sub(0.3)
        lub = e.thump(74.0 * p, 54.0 * p, 0.02, 0.05, attack=0.008) + 0.5 * e.f(e.burst(0.035, a=0.004), BP(150.0 * p, 1.4))
        dub = e.thump(92.0 * p, 68.0 * p, 0.012, 0.032, attack=0.005) + 0.45 * e.f(e.burst(0.02, a=0.003), BP(190.0 * p, 1.4))
        k.put(y, lub, at, g)
        k.put(y, dub, at + 0.29, 0.72 * g)
    # chest-wall saturation: harmonics at 150-600 Hz keep the beat audible on small speakers
    y = k.f(k.sat(norm_peak(y, 0.0), 2.2, bias=0.15), LP(700.0, 2))
    return y + 0.004 * k.cnoise(-6.0, lo=30.0, hi=200.0)


@sound("roll", 0.5, level=-2.0)
def roll(k):
    """Combat roll: cloth scuffle, shoulder / back / knee contacts, a little grit."""
    y = k.zeros()
    e = k.sub(0.45)
    k.put(y, r_rustle(k, 0.45, 500.0, 5000.0, grain=35.0, sharp=1.6) * np.sin(np.pi * e.t() / 0.45) ** 0.7, 0.0, 0.55)
    for at, f0, f1, tau, g in ((0.03, 110.0, 55.0, 0.04, 0.9), (0.17, 100.0, 50.0, 0.05, 0.8), (0.33, 140.0, 70.0, 0.03, 0.55)):
        k.put(y, r_thud(k, f0, f1, tau, lp=450.0, noise=0.5, attack=0.003), at, g)
    k.put(y, r_scrape(k, 0.25, 900.0, 600.0, q=1.2), 0.1, 0.14)
    k.put(y, r_grit(k, 0.15, 900.0, 2000.0, 8000.0, tau=0.04), 0.18, 0.12)
    return r_tail(k, y, 0.2, 0.06, ((0.013, 0.08),), lp=4000.0)


@sound("climb", 0.3, level=-2.0)
def climb(k):
    """Hands slap onto a ledge, shoes scuff the wall, effort grunt."""
    y = k.zeros()
    for at, g in ((0.0, 0.8), (0.055, 0.6)):
        k.put(y, r_tick(k, k.u(1200.0, 1600.0), 0.004, 0.8), at + 0.002, g)
        k.put(y, r_thud(k, 180.0, 90.0, 0.015, lp=700.0), at + 0.002, 0.6 * g)
    k.put(y, r_rustle(k, 0.22, 700.0, 5000.0, grain=45.0), 0.02, 0.3)
    k.put(y, r_scrape(k, 0.12, 1800.0, 2600.0, q=2.0), 0.12, 0.32)
    k.put(y, r_vocal(k, 0.13, [(0, 150.0), (0.04, 165.0), (0.13, 130.0)], V_UH, [(0, 0), (0.015, 1.0), (0.13, 0.0)],
                     breath=0.5, rough=0.2), 0.1, 0.22)
    return r_tail(k, y, 0.18, 0.06, ((0.012, 0.08),), lp=4000.0)


@sound("parachute_open", 1.0)
def parachute_open(k):
    """Canopy unfurls (accelerating flutter), inflates with a big fabric whump, lines snap taut."""
    y = k.zeros()
    e = k.sub(0.4)
    t = e.t()
    flap = 0.5 + 0.5 * np.sin(TAU * np.cumsum(18.0 + 45.0 * (t / 0.4) ** 1.5) / e.sr)
    unf = e.tvbp(e.white(), e.pts([(0, 400.0), (0.4, 1300.0)]), 0.9) * flap ** 2 * e.pts([(0, 0), (0.3, 1.0), (0.4, 0.3)], smooth=True)
    k.put(y, unf / (peak_of(unf) + 1e-9), 0.0, 0.55)
    e = k.sub(0.6)
    whump = e.f(e.burst(0.08, a=0.012), LP(500.0, 2)) * 1.3 + e.f(e.burst(0.06, a=0.01), BP(250.0, 0.8))
    whump = whump / (peak_of(whump) + 1e-9) + 0.9 * e.thump(90.0, 45.0, 0.03, 0.1, attack=0.012)
    k.put(y, whump, 0.3, 1.0)
    for at in (0.32, 0.345):
        k.put(y, r_click(k, k.u(1800.0, 2600.0), 0.003, body=0.5, body_f=200.0, metal=0.3), at, 0.25)
    e = k.sub(0.55)
    t = e.t()
    sf = 0.5 + 0.5 * np.sin(TAU * np.cumsum(14.0 + 6.0 * e.lfon(3.0)) / e.sr)
    settle = e.bnoise(150.0, 1100.0) * sf ** 2 * np.exp(-t / 0.15) + 0.25 * e.cnoise(-3.0, lo=200.0, hi=3000.0) * np.exp(-t / 0.2)
    k.put(y, settle / (peak_of(settle) + 1e-9), 0.4, 0.35)
    return k.rev(y, 0.3, 0.08, hi=5000.0)


@sound("parachute_loop", 4.0, loop=True, check=dict(aperiodic=True))
def parachute_loop(k):
    """Steady descent: wind past the canopy, irregular fabric flutter, a few stronger luffs."""
    wind = k.f(k.cnoise(-3.0, lo=150.0, hi=4000.0), PK(800.0, 4.0, 0.7)) * (0.75 + 0.25 * k.lfon(0.8))
    rate = k.wander(1.5, 9.0, 14.0)
    ph = phase_of(rate, k.n, k.sr, wrap=True)
    flap = (0.5 + 0.5 * np.sin(TAU * ph)) ** 3
    flutter = k.bnoise(120.0, 900.0) * flap * (0.4 + 0.6 * (0.5 + 0.5 * k.lfon(1.2)))
    hf = k.bnoise(2000.0, 7000.0) * np.abs(k.lfon(40.0)) ** 2
    y = wind + 0.8 * flutter + 0.15 * hf
    for _ in range(4):
        e = k.sub(0.5)
        t = e.t()
        luff = e.bnoise(100.0, 700.0) * (0.5 + 0.5 * np.sin(TAU * 11.0 * t)) ** 2 * np.sin(np.pi * t / 0.5) ** 2
        k.put(y, luff, k.u(0.0, 4.0), k.u(0.6, 1.0))
    return y


@sound("wind_fall_loop", 4.0, loop=True, check=dict(aperiodic=True))
def wind_fall_loop(k):
    """Free fall: broadband rushing air, low buffeting, wandering whistles, clothes flapping."""
    roar = k.cnoise(-2.0, lo=80.0, hi=9000.0) * (0.7 + 0.3 * k.lfon(2.0))
    buffet = k.cnoise(-6.0, lo=30.0, hi=300.0) * (0.5 + 0.5 * k.lfon(6.0))
    w1 = k.tvbp(k.white(), k.wander(0.7, 700.0, 1500.0), 8.0)
    w2 = k.tvbp(k.white(), k.wander(0.9, 2200.0, 3400.0), 10.0)
    whistle = w1 / (rms_of(w1) + 1e-9) * (0.5 + 0.5 * k.lfon(0.9)) + 0.5 * w2 / (rms_of(w2) + 1e-9) * (0.5 + 0.5 * k.lfon(1.1))
    flap = k.bnoise(300.0, 2000.0) * np.abs(k.lfon(25.0)) ** 2
    return roar + 0.8 * buffet + 0.22 * whistle + 0.3 * flap


@sound("punch_whoosh", 0.2, level=-2.5)
def punch_whoosh(k):
    y = k.zeros()
    k.put(y, r_whoosh(k, 550.0, 2600.0, 900.0, 0.18, q=1.5, peak=0.4, air=0.35), 0.0)
    return y


# ----------------------------------------------------------------------------------------------
# 5c. VEHICLES
# ----------------------------------------------------------------------------------------------
family("vehicles")

ENGINE_LP = 8500.0        # pitched loops: nothing that would alias at x2.2 into a 48 kHz mix


def impulse_train(n, sr, times, amps, wrap=False):
    """Unit impulses at fractional times (linear split between the two neighbouring samples)."""
    pos = np.asarray(times, dtype=float) * sr
    a = np.asarray(amps, dtype=float)
    i0 = np.floor(pos).astype(np.int64)
    fr = pos - i0
    buf = np.zeros(n)
    if wrap:
        np.add.at(buf, i0 % n, a * (1.0 - fr))
        np.add.at(buf, (i0 + 1) % n, a * fr)
    else:
        ok = (i0 >= 0) & (i0 < n - 1)
        np.add.at(buf, i0[ok], (a * (1.0 - fr))[ok])
        np.add.at(buf, i0[ok] + 1, (a * fr)[ok])
    return buf


def engine_phase(k, cyc_hz, wobble=0.0, wobble_rate=1.0):
    """Engine-cycle phase (in cycles) per sample with a smooth random RPM wander.  In a loop the
    total is a whole number of cycles, so every firing pattern derived from it wraps seamlessly.
    -> (phase[n], total phase at sample n)."""
    f = _fit(cyc_hz, k.n) * (1.0 + wobble * k.lfon(wobble_rate)) if wobble else _fit(cyc_hz, k.n)
    ph = phase_of(f, k.n, k.sr, wrap=k.loop)
    total = float(ph[-1] + f[-1] / k.sr)
    return ph, (float(round(total)) if k.loop else total)


def engine_events(k, ph, total, angles, weights=None, jit_t=0.0002, jit_a=0.06, lope=0.0):
    """Firing events of an engine: one per cylinder per cycle at its firing angle (cycle fraction).
    Fixed per-cylinder unevenness, cycle-to-cycle combustion variation (`lope`: lumpy idle), random
    per-event amplitude and timing jitter. -> (times_s, amps, cylinder_index)."""
    ang = np.asarray(angles, dtype=float)
    w = np.ones(len(ang)) if weights is None else np.asarray(weights, dtype=float)
    ncyc = int(math.floor(total)) + 1
    tgt = (np.arange(ncyc)[:, None] + ang[None, :]).ravel()
    cyl = np.tile(np.arange(len(ang)), ncyc)
    cidx = np.repeat(np.arange(ncyc), len(ang))
    keep = tgt < total
    tgt, cyl, cidx = tgt[keep], cyl[keep], cidx[keep]
    times = np.interp(tgt, np.append(ph, total), np.arange(k.n + 1) / k.sr)
    times = times + jit_t * k.rng.standard_normal(len(times))
    cv = 1.0 + lope * k.rng.standard_normal(ncyc)
    a = w[cyl] * (1.0 + jit_a * k.rng.standard_normal(len(times))) * cv[cidx]
    return times, np.maximum(a, 0.05), cyl


def r_engine(k, cyc_hz, angles, weights=None, banks=None, tau=(0.0004, 0.0025), jit_t=0.0002, jit_a=0.06, lope=0.0,
             wobble=0.01, wobble_rate=1.2, lp=3000.0, drive=1.6, rasp=0.0, rasp_band=(900.0, 3200.0), rasp_tau=0.003,
             intake=0.0, intake_f=700.0, knock=0.0, knock_f=2400.0, mech=0.0, mech_f=3000.0, whine=0.0, whine_order=0,
             amp_env=None, ph=None, total=None):
    """Exhaust-pulse engine model.  Band-limited pressure pulses at the firing events go through one
    exhaust resonance bank per bank of cylinders (banks = [(cylinder indices, [(fc, q, gain), ...]),
    ...]) and the muffler low-pass, then a gentle saturation; added layers: firing-synchronous
    combustion rasp noise, intake howl, diesel knock clatter, valve-train ticks, an engine-order
    whine.  Works for loops (seamless, cycle-locked) and for one-shots (cyc_hz may be an RPM curve,
    amp_env a per-sample load envelope)."""
    n, sr = k.n, k.sr
    if ph is None:
        ph, total = engine_phase(k, cyc_hz, wobble, wobble_rate)
    times, a, cyl = engine_events(k, ph, total, angles, weights, jit_t, jit_a, lope)
    if amp_env is not None:
        a = a * np.interp(times, tvec(n, sr), _fit(amp_env, n))
    banks = banks or [(list(range(len(angles))), [(120.0, 1.5, 1.0)])]
    ex = np.zeros(n)
    for members, res in banks:
        m = np.isin(cyl, members)
        ex += k.f(pulse_train(n, sr, times[m], a[m], tau[0], tau[1], wrap=k.loop), BANK(res, direct=0.35))
    ex = k.f(ex, HP(25.0, 2), LP(lp, 2))
    y = ex / (rms_of(ex) + 1e-12)

    def fire_env(t_c, delay=0.0, amps=None):
        imp = impulse_train(n, sr, times + delay, a if amps is None else amps, wrap=k.loop)
        fc = 1.0 / (TAU * t_c)
        return k.f(imp, LP(fc, 1), LP(fc * 3.0, 1))
    if rasp:
        r = k.f(k.white() * fire_env(rasp_tau), HP(rasp_band[0], 2), LP(rasp_band[1], 2))
        y += rasp * r / (rms_of(r) + 1e-12)
    if intake:
        r = k.f(k.white() * fire_env(0.006, 0.002), BP(intake_f, 2.2))
        y += intake * r / (rms_of(r) + 1e-12)
    if knock:
        kn = impulse_train(n, sr, times + 0.0004, a * (1.0 + 0.25 * k.rng.standard_normal(len(a))), wrap=k.loop)
        r = k.f(kn, BANK([(knock_f, 7.0, 1.0), (knock_f * 1.37, 9.0, 0.7), (knock_f * 0.71, 6.0, 0.5)]), LP(5000.0, 2))
        y += knock * r / (rms_of(r) + 1e-12)
    if mech:
        tk = np.concatenate([times + 0.31 / max(float(np.mean(_fit(cyc_hz, n))), 1.0), times + 0.57 / max(float(np.mean(_fit(cyc_hz, n))), 1.0)])
        r = k.f(impulse_train(n, sr, tk, np.tile(a, 2) * (1.0 + 0.3 * k.rng.standard_normal(2 * len(a))), wrap=k.loop),
                BP(mech_f, 5.0), BP(mech_f * 1.3, 3.0))
        y += mech * r / (rms_of(r) + 1e-12)
    if whine:
        y += whine * math.sqrt(2.0) * np.sin(TAU * whine_order * ph)
    y = k.sat(y / (peak_of(y) + 1e-12), drive)
    return k.f(y, HP(28.0, 2), LP(ENGINE_LP, 4))


ENG_LOOP = dict(aperiodic=True, hf=True)
I4 = [0.0, 0.25, 0.5, 0.75]
I6 = [i / 6.0 for i in range(6)]
V8_FLAT = [i / 8.0 for i in range(8)]
V8_CROSS_A = [0.0, 0.375, 0.625, 0.75]       # firing order 1-8-4-3-6-5-7-2: odd bank 0/270/450/540 deg
V8_CROSS_B = [0.125, 0.25, 0.5, 0.875]       # even bank 90/180/360/630 deg (uneven per-bank spacing)


@sound("engine_small_loop", 2.5, loop=True, check=ENG_LOOP)
def engine_small_loop(k):
    """Buzzy little three-cylinder (2200 rpm, 55 Hz firing): uneven 1.5-order thrum, thin pipe."""
    return r_engine(k, 18.33, [0.0, 1 / 3, 2 / 3], weights=[1.0, 0.9, 1.07],
                    banks=[([0, 1, 2], [(180.0, 2.0, 0.6), (520.0, 3.0, 0.45), (1250.0, 2.2, 0.25)])],
                    tau=(0.0003, 0.002), jit_t=0.00025, jit_a=0.08, wobble=0.012, wobble_rate=1.4, lp=3800.0, drive=1.8,
                    rasp=0.25, rasp_band=(1000.0, 3000.0), mech=0.05, mech_f=3200.0)


@sound("engine_sedan_loop", 2.5, loop=True, check=ENG_LOOP)
def engine_sedan_loop(k):
    """Smooth, well-muffled inline four (1800 rpm, 60 Hz firing)."""
    return r_engine(k, 15.0, I4, weights=[1.0, 0.95, 1.04, 0.98],
                    banks=[([0, 1, 2, 3], [(110.0, 1.5, 0.8), (330.0, 2.5, 0.35), (800.0, 2.0, 0.12)])],
                    tau=(0.0005, 0.003), jit_t=0.00015, jit_a=0.05, wobble=0.008, wobble_rate=1.1, lp=2400.0, drive=1.3,
                    rasp=0.08, rasp_band=(800.0, 2500.0), intake=0.06, intake_f=550.0, mech=0.03, mech_f=2800.0)


@sound("engine_sport_loop", 2.5, loop=True, check=ENG_LOOP)
def engine_sport_loop(k):
    """Raspy flat-plane V8 (2400 rpm, 160 Hz firing): two even banks with different pipes, sharp
    pulses, combustion rasp, intake howl, hard saturation."""
    return r_engine(k, 20.0, V8_FLAT, weights=[1.0, 0.93, 1.06, 0.97, 1.03, 0.92, 1.05, 0.98],
                    banks=[([0, 2, 4, 6], [(240.0, 1.8, 0.6), (720.0, 2.6, 0.5), (1650.0, 2.0, 0.3)]),
                           ([1, 3, 5, 7], [(262.0, 1.8, 0.6), (680.0, 2.6, 0.5), (1760.0, 2.0, 0.3)])],
                    tau=(0.0002, 0.0013), jit_t=0.00012, jit_a=0.07, wobble=0.01, wobble_rate=1.6, lp=6500.0, drive=2.6,
                    rasp=0.5, rasp_band=(1200.0, 4000.0), rasp_tau=0.002, intake=0.25, intake_f=820.0, mech=0.06, mech_f=3400.0)


@sound("engine_muscle_loop", 3.0, loop=True, check=ENG_LOOP)
def engine_muscle_loop(k):
    """Lumpy cross-plane V8 burble (1240 rpm): each bank hears uneven 90/180/270-degree pulse gaps
    through its own pipe, a long-overlap cam makes the combustion lope from cycle to cycle."""
    return r_engine(k, 10.33, V8_CROSS_A + V8_CROSS_B, weights=[1.0, 0.86, 1.12, 0.95, 1.06, 0.9, 1.15, 0.97],
                    banks=[([0, 1, 2, 3], [(85.0, 1.4, 0.9), (240.0, 2.5, 0.5), (620.0, 2.0, 0.22)]),
                           ([4, 5, 6, 7], [(96.0, 1.4, 0.9), (266.0, 2.5, 0.5), (575.0, 2.0, 0.22)])],
                    tau=(0.00055, 0.0038), jit_t=0.00045, jit_a=0.1, lope=0.2, wobble=0.015, wobble_rate=0.9, lp=2800.0,
                    drive=2.2, rasp=0.18, rasp_band=(500.0, 1800.0), rasp_tau=0.004, intake=0.08, intake_f=420.0, mech=0.04)


@sound("engine_truck_loop", 3.0, loop=True, check=ENG_LOOP)
def engine_truck_loop(k):
    """Inline-six diesel (1040 rpm): deep muffled pulses, combustion-knock clatter on every firing,
    rattly valve train, a quiet turbo whistle and hiss."""
    y = r_engine(k, 8.67, I6, weights=[1.0, 0.96, 1.05, 0.98, 1.03, 0.94],
                 banks=[(list(range(6)), [(75.0, 1.2, 1.0), (190.0, 2.0, 0.4), (450.0, 2.5, 0.25)])],
                 tau=(0.0006, 0.0045), jit_t=0.0003, jit_a=0.06, lope=0.05, wobble=0.01, wobble_rate=0.8, lp=2200.0,
                 drive=1.8, rasp=0.12, rasp_band=(700.0, 2200.0), knock=0.55, knock_f=2300.0, mech=0.1, mech_f=2600.0)
    turbo = k.sine(3050.0 * (1.0 + 0.012 * k.lfon(0.6))) * (0.7 + 0.3 * k.lfon(1.5))
    hiss = k.bnoise(1800.0, 6000.0) * (0.8 + 0.2 * k.lfon(2.0))
    y = y / (rms_of(y) + 1e-12) + 0.035 * turbo + 0.05 * hiss
    return k.f(y, LP(ENGINE_LP, 4))


@sound("engine_bike_loop", 2.5, loop=True, check=ENG_LOOP)
def engine_bike_loop(k):
    """600 cc sport-bike inline four (4200 rpm, 141 Hz firing): short open pipe, airbox howl,
    clattery valve train."""
    return r_engine(k, 35.2, I4, weights=[1.0, 0.92, 1.07, 0.96],
                    banks=[([0, 1, 2, 3], [(350.0, 1.8, 0.6), (900.0, 2.5, 0.45), (2100.0, 2.0, 0.25)])],
                    tau=(0.00018, 0.0012), jit_t=0.00012, jit_a=0.09, wobble=0.012, wobble_rate=1.8, lp=6000.0, drive=2.3,
                    rasp=0.4, rasp_band=(1500.0, 4500.0), rasp_tau=0.0015, intake=0.3, intake_f=700.0, mech=0.12, mech_f=3100.0)


@sound("engine_boat_loop", 3.0, loop=True, check=ENG_LOOP)
def engine_boat_loop(k):
    """Outboard: three-cylinder two-stroke (2500 rpm, one firing per cylinder per revolution) with
    the exhaust bubbling out under water, gear-case whine, hull slap and splashing."""
    ph, total = engine_phase(k, 41.67, 0.012, 1.3)
    y = r_engine(k, 41.67, [0.0, 1 / 3, 2 / 3], weights=[1.0, 0.93, 1.06],
                 banks=[([0, 1, 2], [(160.0, 1.5, 0.6), (420.0, 2.0, 0.4)])], tau=(0.0003, 0.0018), jit_t=0.0002,
                 jit_a=0.08, lp=1600.0, drive=1.6, rasp=0.2, rasp_band=(700.0, 2500.0), mech=0.06, ph=ph, total=total)
    y = y / (rms_of(y) + 1e-12) * (0.8 + 0.2 * np.abs(k.lfon(14.0)))          # gurgling under-water exhaust
    gear = np.sin(TAU * 13.0 * ph) + 0.35 * np.sin(TAU * 26.0 * ph)            # 13th order of the crank
    water = k.f(k.white() * (0.35 + 0.65 * np.abs(k.lfon(9.0)) ** 1.5), BP(900.0, 0.6), LP(4500.0, 2))
    slosh = k.cnoise(-6.0, lo=40.0, hi=260.0) * (0.6 + 0.4 * k.lfon(0.8))
    y = y + 0.05 * gear + 0.35 * water / (rms_of(water) + 1e-12) + 0.3 * slosh
    return k.f(y, LP(ENGINE_LP, 4))


@sound("heli_rotor_loop", 3.0, loop=True, check=ENG_LOOP)
def heli_rotor_loop(k):
    """Four-blade main rotor at 4 rev/s (16 Hz blade slap, 12 revolutions per loop), blade-to-blade
    differences, tail-rotor buzz, turbine whine + hiss, gearbox whine."""
    n, sr = k.n, k.sr
    ph, total = engine_phase(k, 4.0, 0.004, 0.7)
    times, a, bl = engine_events(k, ph, total, [0.0, 0.25, 0.5, 0.75], [1.0, 0.92, 1.06, 0.96], 0.0008, 0.07)
    imp = impulse_train(n, sr, times, a, wrap=True)
    env = k.f(imp, LP(1.0 / (TAU * 0.011), 1), LP(1.0 / (TAU * 0.006), 1))
    env /= peak_of(env) + 1e-12
    chop = k.f(k.white() * env, BP(650.0, 0.7), LP(2600.0, 2))
    slap = k.f(k.white() * env ** 3, HP(900.0, 2), LP(5000.0, 2))
    thump = k.sine(68.0) * env ** 1.5
    swish = k.bnoise(300.0, 6000.0) * (0.55 + 0.45 * np.cos(TAU * 4.0 * ph))
    tail = k.f(k.saw(86.4 * (1.0 + 0.004 * k.lfon(0.7))), LP(900.0, 2))
    turb = k.sine(1150.0 * (1.0 + 0.003 * k.lfon(0.5))) + 0.4 * k.sine(2300.0 * (1.0 + 0.003 * k.lfon(0.5)))
    hiss = k.bnoise(2500.0, 8000.0)
    gear = k.sine(640.0)
    y = (chop / rms_of(chop) + 0.45 * slap / (rms_of(slap) + 1e-12) + 0.9 * thump / rms_of(thump) + 0.3 * swish
         + 0.14 * tail / rms_of(tail) + 0.07 * turb + 0.07 * hiss + 0.03 * gear)
    return k.f(k.sat(y / peak_of(y), 1.3), LP(ENGINE_LP, 4))


@sound("plane_prop_loop", 3.0, loop=True, check=ENG_LOOP)
def plane_prop_loop(k):
    """Light aircraft: flat-six (2400 rpm) + two-blade propeller buzz at 80 Hz locked to the crank,
    ground-reflection phasing, wind."""
    ph, total = engine_phase(k, 20.0, 0.006, 0.6)
    eng = r_engine(k, 20.0, I6, weights=[1.0, 0.95, 1.05, 0.97, 1.02, 0.94],
                   banks=[(list(range(6)), [(150.0, 1.5, 0.7), (420.0, 2.0, 0.4), (900.0, 2.0, 0.2)])], tau=(0.0004, 0.0025),
                   jit_t=0.00015, jit_a=0.06, lp=2600.0, drive=1.6, rasp=0.15, ph=ph, total=total)
    prop = np.zeros(k.n)
    for h in range(1, 40):
        if 80.0 * h > 3200.0:
            break
        prop += (1.0 / h ** 0.95) * np.sin(TAU * 4.0 * h * ph + k.u(0, 6.28))      # 4 blade passes per cycle
    prop = k.f(prop, PK(240.0, 4.0, 1.5), LP(2400.0, 2))
    y = eng / rms_of(eng) + 0.8 * prop / rms_of(prop)
    d = (0.0022 + 0.0012 * k.lfo(0.34)) * k.sr
    y = y + 0.55 * vdelay(y, d, wrap=True)
    y += 0.15 * k.cnoise(-3.0, lo=200.0, hi=4000.0) * (0.8 + 0.2 * k.lfon(0.8))
    return k.f(y, HP(35.0, 2), LP(ENGINE_LP, 4))


@sound("jet_loop", 4.0, loop=True, check=ENG_LOOP)
def jet_loop(k):
    """Jet: broadband exhaust roar with turbulent swells and a little crackle, low rumble, fan
    blade-pass whine with buzz-saw shaft orders, compressor whine."""
    roar = k.snoise(TILT(-4.0, 500.0), HP(70.0, 2), PK(420.0, 5.0, 0.6), LP(7000.0, 2)) * (0.82 + 0.18 * k.lfon(4.0))
    rumble = k.cnoise(-6.0, lo=25.0, hi=180.0) * (0.7 + 0.3 * k.lfon(2.5))
    crack = k.f(k.sparks(45.0, power=3.0), HP(700.0, 2), LP(5000.0, 2))
    fw = 1.0 + 0.002 * k.lfon(0.4)
    fan = k.sine(1850.0 * fw) + 0.45 * k.sine(3700.0 * fw)
    saw = np.zeros(k.n)
    for m in range(18, 41):
        saw += k.u(0.2, 1.0) * k.sine(61.7 * m * fw, ph=k.u(0, 1))
    comp = k.sine(4300.0 * (1.0 + 0.003 * k.lfon(0.5)))
    y = roar + 0.5 * rumble + 0.6 * crack / (rms_of(crack) + 1e-12) + 0.09 * fan + 0.18 * saw / rms_of(saw) + 0.035 * comp
    return k.f(y, LP(ENGINE_LP, 4))


@sound("train_loop", 4.0, loop=True, check=ENG_LOOP)
def train_loop(k):
    """Electric train: traction-motor hum + inverter whine, rolling rumble, irregular rail-joint
    double clacks from the bogies."""
    w = 1.0 + 0.003 * k.lfon(0.3)
    hum = k.harm(120.0 * w, [1.0, 0.5, 0.35, 0.2, 0.12, 0.08])
    inv = k.sine(1340.0 * w) + 0.35 * k.sine(1220.0 * w) + 0.35 * k.sine(1460.0 * w) + 0.3 * k.sine(2680.0 * w)
    rumble = k.cnoise(-6.0, lo=25.0, hi=400.0) * (0.8 + 0.2 * k.lfon(1.5))
    roll_ = k.cnoise(-3.0, lo=150.0, hi=3000.0) * (0.85 + 0.15 * k.lfon(3.0))
    y = 0.22 * hum / rms_of(hum) + 0.06 * inv / rms_of(inv) + rumble + 0.35 * roll_
    for at, g in ((0.21, 1.0), (1.47, 0.8), (2.38, 0.95), (3.52, 0.7)):
        for dt, gg in ((0.0, 1.0), (0.118 + k.u(-0.01, 0.01), 0.85)):
            e = k.sub(0.25)
            c = e.thump(135.0, 70.0, 0.008, 0.03) + 0.6 * e.f(e.burst(0.004), BP(k.u(1800.0, 2500.0), 1.5))
            c += 0.3 * e.modal([(k.u(900, 1400), 0.12, 1.0), (k.u(2000, 2800), 0.08, 0.6)])
            k.put(y, c, at + dt, 1.6 * g * gg)
    return k.f(y, LP(ENGINE_LP, 4))


@sound("engine_start", 1.0)
def engine_start(k):
    """Starter motor cranks against compression (~4 Hz lurches), the engine catches, flares to
    ~1900 rpm and settles towards idle."""
    n, sr = k.n, k.sr
    t = k.t()
    y = k.zeros()
    e = k.sub(0.5)
    te = e.t()
    crank = 0.5 + 0.5 * np.cos(TAU * 8.0 * te)
    mot = e.f(e.saw(e.pts([(0, 120.0), (0.08, 190.0), (0.5, 205.0)]) * (1.0 - 0.12 * crank)), LP(900.0, 2))
    mot = mot * (0.55 + 0.45 * crank) + 0.25 * e.sine(1150.0 * (1.0 - 0.05 * crank)) * (0.5 + 0.5 * crank)
    mot += 0.4 * e.f(e.white() * (0.3 + 0.7 * crank ** 4), BP(500.0, 1.2))
    mot *= e.pts([(0, 0), (0.03, 1.0), (0.42, 1.0), (0.48, 0.0)], smooth=True)
    k.put(y, mot / (peak_of(mot) + 1e-9), 0.0, 0.55)
    k.put(y, r_click(k, 1500.0, 0.004, body=0.8, body_f=150.0, metal=0.4), 0.0, 0.5)     # solenoid
    rpm = k.pts([(0, 250.0), (0.42, 300.0), (0.5, 900.0), (0.62, 1900.0), (0.78, 1250.0), (1.0, 950.0)], smooth=True)
    load = k.pts([(0, 0.0), (0.41, 0.0), (0.44, 0.6), (0.55, 1.0), (0.7, 0.8), (0.86, 0.45), (0.98, 0.0)], smooth=True)
    eng = r_engine(k, rpm / 120.0, I4, weights=[1.0, 0.9, 1.08, 0.95], banks=[([0, 1, 2, 3], [(110.0, 1.5, 0.8), (330.0, 2.5, 0.4)])],
                   tau=(0.0005, 0.003), jit_t=0.0004, jit_a=0.15, lope=0.15, lp=2600.0, drive=1.6, rasp=0.15, amp_env=load)
    y += 0.9 * eng * load
    return r_tail(k, y, 0.3, 0.1, ((0.03, 0.12),), lp=3000.0)


@sound("engine_off", 0.6)
def engine_off(k):
    """Ignition off: the idle stumbles down to a stop, a last shudder clunk."""
    rpm = k.pts([(0, 850.0), (0.15, 600.0), (0.32, 260.0), (0.42, 90.0), (0.6, 40.0)], smooth=True)
    load = k.pts([(0, 0.9), (0.1, 0.8), (0.3, 0.45), (0.42, 0.1), (0.48, 0.0)], smooth=True)
    eng = r_engine(k, rpm / 120.0, I4, weights=[1.0, 0.9, 1.08, 0.95], banks=[([0, 1, 2, 3], [(110.0, 1.5, 0.8), (330.0, 2.5, 0.4)])],
                   tau=(0.0005, 0.003), jit_t=0.0006, jit_a=0.2, lope=0.2, lp=2200.0, drive=1.5, rasp=0.1, amp_env=load)
    y = eng * k.fade(load, 0.01)
    k.put(y, r_thud(k, 95.0, 55.0, 0.04, lp=600.0, noise=0.7), 0.38, 0.45)
    for _ in range(3):
        k.put(y, r_click(k, k.u(1200.0, 2600.0), 0.002, metal=0.6), k.u(0.39, 0.45), k.u(0.05, 0.12))
    return r_tail(k, y, 0.18, 0.07, ((0.03, 0.1),), lp=3000.0)


@sound("skid_loop", 2.0, loop=True, check=dict(aperiodic=True, hf=True))
def skid_loop(k):
    """Tyre squeal: two tyres' stick-slip tones (wandering ~900 / ~1030 Hz with harmonics and flutter)
    over gritty scrub noise."""
    y = k.zeros()
    for base, g in ((880.0, 1.0), (1010.0, 0.7)):
        f = base * (1.0 + 0.05 * k.lfon(2.5) + 0.015 * k.lfon(18.0))
        tone = k.harm(f, [1.0, 0.45, 0.25, 0.12])
        y += g * tone * (0.55 + 0.45 * np.abs(k.lfon(35.0))) * (0.7 + 0.3 * k.lfon(1.5))
    scrub = k.f(k.white() * (0.5 + 0.5 * np.abs(k.lfon(60.0))), BP(2200.0, 0.8), LP(6500.0, 2))
    y = y / rms_of(y) + 0.5 * scrub / rms_of(scrub) + 0.2 * k.cnoise(-4.0, lo=80.0, hi=800.0)
    return k.f(k.sat(y / peak_of(y), 1.4), LP(ENGINE_LP, 4))


@sound("tire_roll_loop", 3.0, loop=True, check=dict(aperiodic=True, hf=True))
def tire_roll_loop(k):
    """Rolling on asphalt: tread-noise hump around 900 Hz, road texture rumble, wind-ish hiss."""
    tread = k.snoise(TILT(-2.0), HP(150.0, 2), PK(900.0, 6.0, 1.2), LP(3500.0, 2)) * (0.85 + 0.15 * k.lfon(1.2))
    rumble = k.cnoise(-6.0, lo=30.0, hi=180.0) * (0.75 + 0.25 * k.lfon(4.0))
    grit = k.f(k.sparks(900.0, power=1.5), BP(2500.0, 1.0)) * (0.7 + 0.3 * k.lfon(2.0))
    y = tread + 0.6 * rumble + 0.3 * grit / (rms_of(grit) + 1e-12)
    return k.f(y, LP(ENGINE_LP, 4))


def r_horn_tone(k, sec, freqs, buzz=0.5, attack=0.015, release=0.05, scoop=0.02, horn=(2400.0, 6.0), lp=6000.0, drive=1.6,
                breath=0.0):
    """Electric / air horn: band-limited diaphragm buzz (pulse + saw) per tone, a small pitch scoop
    at the onset, horn-bell resonance, saturation."""
    e = k.sub(sec)
    t = e.t()
    y = e.zeros()
    for i, f in enumerate(freqs):
        fr = f * (1.0 - scoop * np.exp(-t / 0.03)) * (1.0 + 0.0015 * e.lfon(6.0))
        y += e.pulse(fr, 0.35 + 0.05 * i) * (1.0 - buzz) + e.saw(fr, ph=e.u(0, 1)) * buzz
    if breath:
        y += breath * e.f(e.white(), BP(freqs[0] * 3.0, 2.0)) * (0.5 + 0.5 * np.abs(e.lfon(40.0)))
    y = e.f(y, HP(freqs[0] * 0.7, 2), PK(horn[0], horn[1], 1.2), PK(horn[0] * 0.45, 3.0, 1.5), LP(lp, 2))
    y = e.sat(y / (peak_of(y) + 1e-9), drive)
    env = e.pts([(0, 0), (attack, 1.0), (sec - release, 0.92), (sec, 0.0)], smooth=True)
    return e.f(y * env, LP(lp, 2))


@sound("horn_car", 0.6)
def horn_car(k):
    """Classic dual-tone car horn (~405 + 508 Hz)."""
    y = k.zeros()
    k.put(y, r_horn_tone(k, 0.52, [405.0, 508.0], buzz=0.4, attack=0.012, release=0.05), 0.004)
    return r_tail(k, y, 0.3, 0.1, ((0.045, 0.12),), lp=4000.0)


@sound("horn_truck", 0.9)
def horn_truck(k):
    """Low two-tone air horn: slower onset, pitch scoop, brassy, a little air noise."""
    y = k.zeros()
    k.put(y, r_horn_tone(k, 0.74, [220.0, 277.0], buzz=0.75, attack=0.06, release=0.11, scoop=0.07, horn=(1300.0, 5.0),
                         lp=4500.0, drive=2.2, breath=0.12), 0.005)
    return r_tail(k, y, 0.45, 0.14, ((0.07, 0.14),), lp=3500.0)


@sound("horn_bike", 0.4)
def horn_bike(k):
    """Thin single-tone motorbike horn."""
    y = k.zeros()
    k.put(y, r_horn_tone(k, 0.3, [532.0], buzz=0.2, attack=0.008, release=0.04, scoop=0.015, horn=(2900.0, 7.0), lp=7000.0,
                         drive=1.4), 0.004)
    y = k.f(y, HP(450.0, 2))
    return r_tail(k, y, 0.22, 0.08, ((0.035, 0.1),), lp=5000.0)


@sound("train_horn", 1.5)
def train_horn(k):
    """Multi-chime air horn (C#m7-ish chord: 277 / 330 / 415 / 494 Hz), slow bloom, detuned beating."""
    y = k.zeros()
    for f in (277.0, 330.0, 415.0, 494.0):
        k.put(y, r_horn_tone(k, 1.22, [f, f * 1.004], buzz=0.8, attack=0.12, release=0.18, scoop=0.05, horn=(1100.0, 4.0),
                             lp=4200.0, drive=1.8, breath=0.1), 0.006, 0.6)
    return r_tail(k, y, 0.9, 0.22, ((0.12, 0.18), (0.31, 0.08)), lp=3000.0)


@sound("bicycle_bell", 0.6)
def bicycle_bell(k):
    """Thumb-lever bell: 'ding-ding' on a thin steel dome."""
    y = k.zeros()
    for at, g in ((0.0, 1.0), (0.14, 0.8)):
        f1 = 2480.0 * k.u(0.995, 1.005)
        modes = [(f1, 0.42, 1.0), (f1 * 1.005, 0.4, 0.6, 1.2), (f1 * 1.46, 0.3, 0.55), (f1 * 2.06, 0.22, 0.4),
                 (f1 * 2.71, 0.16, 0.3), (f1 * 0.52, 0.35, 0.25)]
        k.put(y, k.sub(0.45).modal(modes), at + 0.002, g)
        k.put(y, r_click(k, 3500.0, 0.001, metal=0.3), at + 0.001, 0.3 * g)
    return r_tail(k, y, 0.2, 0.06, (), lp=8000.0)


def r_siren(k, f, timbre="electronic"):
    """Siren over a loop from a per-sample frequency curve (whole cycles -> seamless).  'electronic':
    square-ish driver through a compression horn speaker; 'mech': rotor-chopped air (pulse + air
    noise synchronous with the tone + a sub-octave growl)."""
    f = _fit(f, k.n)
    cyc = f.sum() / k.sr
    f = f + (2.0 * round(cyc / 2.0) - cyc) * k.sr / k.n           # even cycle count: the sub-octave wraps too
    ph = phase_of(f, k.n, k.sr, wrap=True)
    if timbre == "mech":
        x = osc_pulse(f, k.n, k.sr, 0.42, wrap=True) * 0.6 + osc_saw(f, k.n, k.sr, wrap=True) * 0.4
        x += 0.35 * k.f(k.white(), BP(1800.0, 0.8)) * (0.5 + 0.5 * np.cos(TAU * ph)) ** 2
        x += 0.25 * np.sin(np.pi * ph + 0.3)                       # sub-octave growl
        y = k.f(x, HP(300.0, 2), PK(1500.0, 4.0, 1.0), PK(2700.0, 2.0, 1.4), LP(5000.0, 2))
        y = k.sat(y / peak_of(y), 2.0)
    else:
        x = osc_pulse(f, k.n, k.sr, 0.5, wrap=True) * 0.8 + osc_saw(f, k.n, k.sr, wrap=True) * 0.2
        y = k.f(x, HP(450.0, 2), PK(1800.0, 4.0, 1.0), PK(3100.0, 3.0, 1.5), LP(5500.0, 2))
        y = k.sat(y / peak_of(y), 1.6)
    y = k.f(y, LP(6500.0, 2))
    return k.rev(y, 0.9, 0.18, hf=0.5, hi=4500.0) + 0.25 * k.f(np.roll(y, int(0.11 * k.sr)), LP(2500.0, 2))


def wail_curve(u, rise):
    """Periodic smooth up/down sweep shape in [0, 1] over one period (u in [0, 1))."""
    return np.where(u < rise, 0.5 - 0.5 * np.cos(np.pi * u / rise), 0.5 + 0.5 * np.cos(np.pi * (u - rise) / (1.0 - rise)))


@sound("siren_police_loop", 4.0, loop=True, level=-15.0, check=dict(band=(680.0, 1480.0)))
def siren_police_loop(k):
    """Wail: one slow rise (1.6 s) and fall (2.4 s) per loop, 680-1480 Hz."""
    u = k.t() / k.dur
    return r_siren(k, 680.0 + 800.0 * wail_curve(u, 0.4))


@sound("siren_police_yelp_loop", 1.2, loop=True, level=-15.0, check=dict(band=(700.0, 1500.0)))
def siren_police_yelp_loop(k):
    """Yelp: four fast sweeps per loop (3.3 Hz), 700-1500 Hz."""
    u = (k.t() * 4.0 / k.dur) % 1.0
    return r_siren(k, 700.0 + 800.0 * wail_curve(u, 0.55))


@sound("siren_ambulance_loop", 2.4, loop=True, level=-15.0, check=dict(band=(720.0, 960.0)))
def siren_ambulance_loop(k):
    """Hi-lo two-tone: 960 / 720 Hz, 0.6 s each, short glides between."""
    u = k.t() * 2.0 / k.dur
    s = 0.5 + 0.5 * np.tanh(12.0 * np.sin(TAU * (u - 0.5))) / math.tanh(12.0)      # periodic soft square
    return r_siren(k, 960.0 - 240.0 * s)


@sound("siren_fire_loop", 4.8, loop=True, level=-15.0, check=dict(band=(430.0, 1150.0)))
def siren_fire_loop(k):
    """Slow mechanical wail: the rotor spins up for 2.6 s (ease-out) and coasts down, 430-1150 Hz,
    with breathy air-horn character and a sub-octave growl."""
    u = k.t() / k.dur
    r = 2.6 / 4.8
    up = 1.0 - (1.0 - np.clip(u / r, 0.0, 1.0)) ** 2.2
    down = np.exp(-3.2 * np.clip((u - r) / (1.0 - r), 0.0, 1.0))
    down = (down - math.exp(-3.2)) / (1.0 - math.exp(-3.2))
    s = np.where(u < r, up, down)
    s = filt(s, k.sr, LP(3.0, 2), wrap=True)          # round the corners (periodic smoothing)
    s = (s - s.min()) / (s.max() - s.min())
    return r_siren(k, 430.0 + 720.0 * s, "mech")


@sound("car_alarm_loop", 2.0, loop=True, level=-15.0)
def car_alarm_loop(k):
    """Alarm pattern: 1 s two-tone warble (10 Hz, 1650 / 2250 Hz), then three rising whoops."""
    t = k.t()
    warb = 0.5 + 0.5 * np.tanh(6.0 * np.sin(TAU * 10.0 * t))
    f_a = 1650.0 + 600.0 * warb
    u = np.clip((t - 1.0) * 3.0, 0.0, 3.0) % 1.0
    f_b = 900.0 * (2600.0 / 900.0) ** (u ** 0.8)
    blend = np.clip((t - 1.0) / 0.02, 0.0, 1.0) * np.clip((2.0 - t) / 0.02, 0.0, 1.0)
    f = f_a * (1.0 - blend) + f_b * blend
    x = osc_pulse(f, k.n, k.sr, 0.5, wrap=True)
    y = k.f(x, HP(700.0, 2), PK(2400.0, 5.0, 1.2), LP(5500.0, 2))
    y = k.sat(y / peak_of(y), 1.5)
    return k.rev(k.f(y, LP(6000.0, 2)), 0.6, 0.15, hi=5000.0)


def r_metal_cluster(k, sec, n_modes, f_lo, f_hi, t60, spread=1.0):
    """Struck car-body panel: random inharmonic modes (log-uniform), decay shortening with pitch."""
    e = k.sub(sec)
    modes = []
    for _ in range(n_modes):
        f = f_lo * (f_hi / f_lo) ** k.rng.random()
        modes.append((f, t60 * k.u(0.5, 1.2) * (f_lo / f) ** (0.35 * spread), k.u(0.3, 1.0) * (f_lo / f) ** 0.25, k.u(0, 6.28)))
    y = e.modal(modes)
    return y / (peak_of(y) + 1e-9)


def r_crunch(k, sec, rate, lo=300.0, hi=5000.0, power=2.5, tau=0.08):
    """Crumpling sheet metal: a burst of irregular micro-buckles through random metallic resonances."""
    e = k.sub(sec)
    t = e.t()
    dens = np.exp(-t / tau) * np.minimum(1.0, t / 0.003)
    src = e.sparks(rate, power=power) * dens + 0.15 * e.white() * dens
    res = [(lo * (hi / lo) ** k.rng.random(), k.u(8.0, 25.0), k.u(0.3, 1.0)) for _ in range(14)]
    y = e.f(src, BANK(res, direct=0.25), HP(lo * 0.6, 2))
    return y / (peak_of(y) + 1e-9)


def r_shards(k, sec, count, start=0.02, spread=0.6, f_lo=2400.0, f_hi=11000.0):
    """Falling glass shards: tiny bright modal pings, denser at first."""
    e = k.sub(sec)
    y = e.zeros()
    for _ in range(count):
        f = k.u(f_lo, f_hi)
        at = start + spread * k.rng.random() ** 1.6
        s = k.sub(0.1)
        sh = s.modal([(f, k.u(0.02, 0.08), 1.0), (f * k.u(1.3, 1.7), 0.03, 0.5), (f * k.u(2.1, 2.6), 0.02, 0.3)])
        sh += 0.3 * s.f(s.burst(0.0015), HP(3000.0, 2))
        e.put(y, sh, at, k.u(0.15, 0.5) * (1.0 - 0.6 * min(1.0, (at - start) / max(spread, 1e-3))))
    return y / (peak_of(y) + 1e-9)


def r_debris(k, y, count, t0, t1, g=0.2):
    """Small parts bouncing / skittering after an impact (plastic + metal pings, little thuds)."""
    for _ in range(count):
        e = k.sub(0.12)
        f = k.u(700.0, 3200.0)
        d = 0.6 * e.modal([(f, k.u(0.03, 0.08), 1.0), (f * k.u(1.4, 2.2), 0.03, 0.5)]) + e.thump(k.u(120, 220), 80.0, 0.005, 0.012)
        k.put(y, d, k.u(t0, t1), g * k.u(0.3, 1.0))
    return y


def r_crash(k, size):
    """Vehicle impact.  size 0..1 scales mass (thud pitch / length), crumple, metal ring, glass, debris."""
    s = size
    y = k.zeros()
    e = k.sub(0.6)
    thud = e.thump(115.0 - 45.0 * s, 52.0 - 20.0 * s, 0.015 + 0.02 * s, 0.05 + 0.11 * s, attack=0.001)
    thud += 0.9 * e.f(e.burst(0.04 + 0.08 * s, a=0.001), LP(500.0 + 300.0 * s, 2))
    thud += 0.6 * e.f(e.burst(0.02 + 0.03 * s), BP(380.0, 1.0))
    k.put(y, thud / (peak_of(thud) + 1e-9), 0.003, 0.7)
    k.put(y, r_crunch(k, 0.2 + 0.4 * s, 900.0 + 2500.0 * s, tau=0.03 + 0.12 * s), 0.002, 0.75 + 0.3 * s)
    k.put(y, r_metal_cluster(k, 0.3 + 0.8 * s, int(10 + 18 * s), 160.0 - 40.0 * s, 2600.0 + 1400.0 * s, 0.14 + 0.4 * s), 0.004,
          0.55 + 0.25 * s)
    k.put(y, r_tick(k, 1600.0, 0.003, 0.8), 0.001, 0.4)                       # plastic crack
    if s > 0.3:
        k.put(y, r_shards(k, 0.6 + 0.4 * s, int(10 + 30 * s), start=0.03, spread=0.25 + 0.4 * s), 0.0, 0.15 + 0.35 * s)
    r_debris(k, y, int(3 + 8 * s), 0.08, 0.25 + 0.8 * s, 0.12 + 0.1 * s)
    if s > 0.6:
        k.put(y, r_scrape(k, 0.5, 900.0, 600.0, q=2.5), 0.3, 0.12)
    y = k.sat(norm_peak(y, 0.0), 1.6 + s)
    y = k.f(y, HP(55.0, 2), LP(10000.0, 2))
    return r_tail(k, y, 0.3 + 0.5 * s, 0.1 + 0.08 * s, ((0.05, 0.12), (0.12, 0.06)), lp=3500.0)


@sound("crash_small", 0.5)
def crash_small(k):
    return r_crash(k, 0.15)


@sound("crash_medium", 0.8)
def crash_medium(k):
    return r_crash(k, 0.5)


@sound("crash_big", 1.4)
def crash_big(k):
    return r_crash(k, 1.0)


@sound("metal_scrape_loop", 2.0, loop=True, check=dict(aperiodic=True, hf=True))
def metal_scrape_loop(k):
    """Car body grinding along a wall: stick-slip friction exciting metal modes, gritty band noise,
    spark crackle, body rumble."""
    slip = np.abs(k.lfon(45.0)) ** 1.5 + 0.3 * np.abs(k.lfon(9.0))
    exc = k.white() * slip
    res = [(k.u(600.0, 5000.0), k.u(15.0, 40.0), k.u(0.3, 1.0)) for _ in range(9)]
    ring = k.f(exc, BANK(res), LP(7000.0, 2))
    grit = k.f(exc, BP(2400.0, 0.9))
    spark = k.f(k.sparks(300.0, power=2.5), HP(3000.0, 2), LP(8000.0, 2))
    body = k.cnoise(-6.0, lo=40.0, hi=300.0) * (0.7 + 0.3 * k.lfon(5.0))
    y = ring / rms_of(ring) + 0.7 * grit / rms_of(grit) + 0.25 * spark / (rms_of(spark) + 1e-12) + 0.45 * body
    return k.f(y, LP(ENGINE_LP, 4))


@sound("door_open", 0.3, level=-2.0)
def door_open(k):
    """Handle click, latch release clunk, door seal unsticking, a short hinge creak."""
    y = k.zeros()
    k.put(y, r_click(k, 2600.0, 0.002, metal=0.45), 0.004, 0.55)
    k.put(y, r_click(k, 950.0, 0.005, body=0.9, body_f=170.0, metal=0.25), 0.05, 1.0)
    k.put(y, r_thud(k, 120.0, 80.0, 0.03, lp=500.0, noise=0.5), 0.065, 0.4)
    e = k.sub(0.08)
    creak = e.sine(e.sweep(760.0, 690.0)) * (0.5 + 0.5 * np.abs(e.lfon(70.0))) * np.sin(np.pi * e.t() / 0.08) ** 2
    k.put(y, e.f(creak, BP(700.0, 2.0)) * 3.0, 0.13, 0.12)
    return r_tail(k, y, 0.2, 0.08, ((0.01, 0.1),), lp=4000.0)


@sound("door_close", 0.35)
def door_close(k):
    """Slam: hollow panel thunk, latch click, window-glass rattle, cabin pressure thump."""
    y = k.zeros()
    e = k.sub(0.25)
    th = 0.7 * e.thump(120.0, 62.0, 0.01, 0.05, attack=0.001) + 0.8 * e.f(e.burst(0.035, a=0.0005), BP(240.0, 3.0)) * 2.0
    th += 0.8 * e.f(e.burst(0.02), BP(520.0, 1.2))
    k.put(y, th / (peak_of(th) + 1e-9), 0.004, 1.0)
    k.put(y, r_click(k, 2200.0, 0.0025, body=0.4, body_f=300.0, metal=0.6), 0.012, 0.55)
    k.put(y, r_metal_cluster(k, 0.12, 6, 1400.0, 3200.0, 0.06), 0.02, 0.16)
    y = k.f(y, HP(60.0, 2))
    return r_tail(k, y, 0.22, 0.08, ((0.012, 0.1),), lp=3500.0)


@sound("tire_pop", 0.5)
def tire_pop(k):
    """Blow-out: a hard bang, the air rushing out with flutter, the flapping carcass."""
    y = k.zeros()
    e = k.sub(0.2)
    bang = e.f(e.burst(0.003), LP(9000.0, 2)) + 1.1 * e.thump(170.0, 70.0, 0.01, 0.04) + 0.9 * e.f(e.burst(0.02), BP(700.0, 0.8))
    k.put(y, e.f(k.sat(norm_peak(bang, 0.0), 2.2), LP(10000.0, 2)), 0.002, 1.0)
    e = k.sub(0.42)
    air = e.f(e.white(), HP(1500.0, 2), LP(9000.0, 2)) * (0.6 + 0.4 * np.abs(e.lfon(50.0))) * e.exp(0.12, a=0.004)
    k.put(y, air / (peak_of(air) + 1e-9), 0.006, 0.35)
    for at, g in ((0.12, 0.35), (0.22, 0.25), (0.31, 0.15)):
        k.put(y, r_thud(k, 140.0, 80.0, 0.02, lp=600.0, noise=0.7), at, g)
    return r_tail(k, y, 0.35, 0.12, ((0.05, 0.15), (0.11, 0.07)), lp=4000.0)


@sound("handbrake", 0.3, level=-2.0)
def handbrake(k):
    """Lever pulled up: a run of ratchet clicks, then the lever's end-stop clunk."""
    y = k.zeros()
    at = 0.005
    for i in range(7):
        k.put(y, r_click(k, 2900.0 * k.u(0.95, 1.05), 0.0015, metal=0.5), at, 0.4 + 0.05 * i)
        at += 0.032 - 0.003 * i
    k.put(y, r_click(k, 1200.0, 0.004, body=0.9, body_f=160.0, metal=0.4), at + 0.01, 1.0)
    return r_tail(k, y, 0.15, 0.06, (), lp=5000.0)


@sound("fire_loop", 4.0, loop=True, check=dict(aperiodic=True))
def fire_loop(k):
    """Burning wreck: low turbulent roar, flame whoosh, wood/plastic crackles and occasional pops."""
    roar = k.cnoise(-6.0, lo=30.0, hi=450.0) * (0.65 + 0.35 * k.lfon(3.0))
    whoosh = k.tvbp(k.white(), k.wander(1.2, 500.0, 1500.0), 1.2) * (0.5 + 0.5 * k.lfon(2.0))
    crk = np.zeros(k.n)
    for lo_, hi_, rate in ((1200.0, 6000.0, 30.0), (2500.0, 8000.0, 60.0), (600.0, 2500.0, 12.0)):
        crk += k.f(k.sparks(rate, power=3.0), BP(math.sqrt(lo_ * hi_), 1.2))
    y = roar + 0.5 * whoosh / rms_of(whoosh) + 0.9 * crk / (rms_of(crk) + 1e-12)
    for _ in range(9):
        e = k.sub(0.12)
        pop = e.thump(k.u(120, 200), 70.0, 0.005, 0.02) + 0.6 * e.f(e.burst(0.004), BP(k.u(900, 2500), 1.0))
        k.put(y, pop, k.u(0.0, 4.0), k.u(1.0, 2.5))
    return k.f(y, LP(9000.0, 2))


@sound("boat_wake_loop", 4.0, loop=True, check=dict(aperiodic=True))
def boat_wake_loop(k):
    """Hull through water: rushing splashy noise, low slosh swells, bursts of spray, bubbles."""
    rush = k.f(k.white() * (0.4 + 0.6 * np.abs(k.lfon(22.0)) ** 1.5 + 0.3 * np.abs(k.lfon(7.0))), BP(1300.0, 0.5), LP(6000.0, 2))
    slosh = k.cnoise(-6.0, lo=40.0, hi=300.0) * (0.55 + 0.45 * k.lfon(0.7))
    y = rush / rms_of(rush) + 0.6 * slosh
    for _ in range(7):
        e = k.sub(0.5)
        sp = e.f(e.white(), HP(1500.0, 2), LP(8000.0, 2)) * e.pts([(0, 0), (0.05, 1.0), (0.5, 0.0)], smooth=True)
        k.put(y, sp, k.u(0.0, 4.0), k.u(0.3, 0.7))
    for _ in range(5):
        k.put(y, r_bubbles(k, 12, 300.0, 1800.0, 0.4), k.u(0.0, 4.0), k.u(0.4, 0.9))
    return k.f(y, LP(9000.0, 2))


@sound("spray_paint", 1.2)
def spray_paint(k):
    """Can shaken (mixing ball rattles), then the nozzle hiss."""
    y = k.zeros()
    for i, at in enumerate((0.01, 0.1, 0.19, 0.28)):
        for dt in (0.0, k.u(0.012, 0.02)):
            f = k.u(3600.0, 4800.0)
            e = k.sub(0.06)
            k.put(y, e.modal([(f, 0.03, 1.0), (f * 1.52, 0.02, 0.5), (f * 0.61, 0.025, 0.4)]) + 0.4 * e.f(e.burst(0.001), HP(3000.0, 2)),
                  at + dt, k.u(0.35, 0.6))
        k.put(y, r_rustle(k, 0.05, 1500.0, 6000.0, grain=60.0), at, 0.08)
    e = k.sub(0.72)
    hiss = e.f(e.white(), HP(2600.0, 2), PK(6500.0, 4.0, 1.0), LP(13000.0, 2)) * (0.9 + 0.1 * e.lfon(20.0))
    hiss *= e.pts([(0, 0), (0.02, 1.0), (0.66, 0.95), (0.72, 0.0)], smooth=True)
    k.put(y, hiss / peak_of(hiss), 0.42, 0.55)
    k.put(y, r_click(k, 2000.0, 0.002, metal=0.2), 0.415, 0.25)
    return r_tail(k, y, 0.2, 0.06, (), lp=8000.0)


@sound("wrench_ratchet", 0.9, level=-2.0)
def wrench_ratchet(k):
    """Three strokes of a ratchet wrench, each a quick run of pawl clicks."""
    y = k.zeros()
    for s0 in (0.01, 0.31, 0.6):
        at = s0
        for i in range(8):
            f = 3300.0 * k.u(0.96, 1.04)
            k.put(y, r_click(k, f, 0.0012, metal=0.7), at, k.u(0.5, 0.8))
            at += k.u(0.017, 0.024)
        k.put(y, r_rustle(k, 0.2, 800.0, 4000.0, grain=30.0), s0, 0.05)
    return r_tail(k, y, 0.18, 0.06, ((0.015, 0.08),), lp=6000.0)


@sound("garage_door", 2.0)
def garage_door(k):
    """Roll-up door: motor hum with whine, chain rattle, panel rumble and roller clicks, end clunk."""
    y = k.zeros()
    e = k.sub(1.82)
    t = e.t()
    env = e.pts([(0, 0), (0.12, 1.0), (1.7, 1.0), (1.82, 0.0)], smooth=True)
    mot = e.harm(100.0 * (1.0 + 0.01 * e.lfon(2.0)), [1.0, 0.6, 0.45, 0.25, 0.15, 0.1]) + 0.25 * e.sine(820.0 * (1.0 + 0.01 * e.lfon(2.0)))
    rumble = e.cnoise(-5.0, lo=60.0, hi=500.0) * (0.6 + 0.4 * np.abs(e.lfon(6.0)))
    chain = e.f(e.sparks(55.0, power=1.5), BANK([(2600.0, 12.0, 1.0), (3900.0, 15.0, 0.6), (1700.0, 10.0, 0.5)]))
    m = mot / rms_of(mot) * 0.35 + rumble / rms_of(rumble) * 0.6 + chain / (rms_of(chain) + 1e-12) * 0.35
    k.put(y, m * env, 0.04)
    at = 0.15
    while at < 1.75:
        k.put(y, r_click(k, k.u(1500.0, 2400.0), 0.003, body=0.4, body_f=220.0, metal=0.4), at, k.u(0.15, 0.3))
        at += k.u(0.1, 0.16)
    k.put(y, r_thud(k, 110.0, 60.0, 0.05, lp=600.0), 1.83, 0.9)
    k.put(y, r_metal_cluster(k, 0.15, 8, 300.0, 2500.0, 0.1), 1.835, 0.35)
    return r_tail(k, y, 0.4, 0.1, ((0.02, 0.1),), lp=4000.0)


# ----------------------------------------------------------------------------------------------
# 5d. UI  (one palette: FM bells / soft tones in A major for positive cues; brass-synth stabs,
#          clusters and pitch dives for tense / negative stings)
# ----------------------------------------------------------------------------------------------
family("ui")


def midi_hz(m):
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


NOTE = {nm: i for i, nm in enumerate(("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"))}


def hz(name):
    """'A4' -> 440.0, 'C#6' -> 1108.7 ..."""
    return midi_hz(12 * (int(name[-1]) + 1) + NOTE[name[:-1]])


def r_note(k, f, sec, timbre="bell", attack=0.002, decay=0.25, bright=1.0, vib=0.0):
    """One pitched UI / music note (normalised, ends at zero).  Timbres: bell (FM 1:2, index decays),
    glass (FM 1:3.5 chime), soft (sine + few harmonics), pluck (bright Karplus-Strong), square
    (band-limited pulse, low-passed), brass (detuned saws through an opening/closing low-pass)."""
    e = k.sub(sec)
    t = e.t()
    fr = f * (1.0 + vib * np.sin(TAU * 5.5 * t) * np.clip(t / 0.15, 0.0, 1.0)) if vib else f
    env = np.exp(-t / max(decay, 1e-4))
    if attack > 0.0:
        m = min(e.n, max(1, int(attack * e.sr)))
        env[:m] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(m) / m)
    if timbre == "bell":
        y = e.fm(fr, 2.0 * f, 2.2 * bright * np.exp(-t / (0.35 * decay + 0.01))) + 0.25 * e.sine(f * 1.003 * 2.0)
    elif timbre == "glass":
        y = e.fm(fr, 3.5 * f, 1.6 * bright * np.exp(-t / (0.25 * decay + 0.01))) + 0.5 * e.sine(fr)
    elif timbre == "soft":
        y = e.sine(fr) + 0.25 * bright * e.sine(2.0 * f) + 0.08 * bright * e.sine(3.0 * f)
    elif timbre == "pluck":
        y = karplus_strong(f, e.n, e.sr, k.rng, t60=decay * 3.0, fd=3000.0 * bright, pick=0.2, bright=6000.0 * bright)
    elif timbre == "square":
        y = e.f(e.pulse(fr, 0.4), LP(1500.0 * bright + 2.0 * f, 2))
    elif timbre == "brass":
        y = sum(e.saw(fr * d, ph=e.u(0, 1)) for d in (0.996, 1.0, 1.004))
        cut = f * (1.5 + 5.0 * bright * np.exp(-t / (0.5 * decay + 0.02)) * np.minimum(1.0, t / max(attack * 2.0, 0.01)))
        y = e.tvlp(y, np.minimum(cut, 0.45 * e.sr), q=0.9)
    else:
        raise ValueError(timbre)
    y = y * env
    y = fade(y, e.sr, 0.0, min(0.02, sec * 0.3))
    return y / (peak_of(y) + 1e-12)


def r_chord(k, names, sec, timbre="brass", gain=1.0, spread=0.0, **kw):
    """Several notes (names or Hz) summed, optionally strummed by `spread` seconds."""
    e = k.sub(sec + spread * len(names))
    y = e.zeros()
    for i, nm in enumerate(names):
        f = hz(nm) if isinstance(nm, str) else float(nm)
        e.put(y, r_note(k, f, sec, timbre, **kw), i * spread, 1.0 / (1.0 + 0.15 * i))
    return gain * y / (peak_of(y) + 1e-12)


def r_sparkle(k, sec, count=10, lo=3500.0, hi=7500.0):
    """High glassy twinkles (normalised)."""
    e = k.sub(sec)
    y = e.zeros()
    for _ in range(count):
        e.put(y, r_note(k, k.u(lo, hi), 0.25, "glass", decay=0.06), k.u(0.0, sec - 0.25), k.u(0.3, 1.0))
    return y / (peak_of(y) + 1e-12)


def ui_finish(k, y, rt=0.35, wet=0.12):
    """Shared UI space: a small bright room."""
    return k.rev(y, rt, wet, hi=9000.0, lo=250.0)


@sound("ui_click", 0.06, level=-3.0)
def ui_click(k):
    y = k.zeros()
    e = k.sub(0.05)
    y_ = e.sine(1760.0) * e.exp(0.007, a=0.0005) + 0.4 * e.sine(880.0) * e.exp(0.005, a=0.0005)
    k.put(y, y_ + 0.25 * e.f(e.burst(0.0015), HP(4000.0, 2)), 0.001)
    return y


@sound("ui_hover", 0.04, level=-3.0)
def ui_hover(k):
    y = k.zeros()
    e = k.sub(0.03)
    k.put(y, e.sine(2637.0) * e.exp(0.0045, a=0.0008) + 0.3 * e.sine(1318.5) * e.exp(0.004, a=0.0008), 0.001)
    return y


@sound("ui_open", 0.25, level=-2.5)
def ui_open(k):
    y = k.zeros()
    k.put(y, r_whoosh(k, 800.0, 4000.0, 3000.0, 0.15, q=1.4, peak=0.7, air=0.3), 0.0, 0.22)
    k.put(y, r_note(k, hz("E6"), 0.16, "bell", decay=0.05), 0.005, 0.8)
    k.put(y, r_note(k, hz("A6"), 0.16, "bell", decay=0.055), 0.065, 1.0)
    return ui_finish(k, y, 0.25, 0.1)


@sound("ui_close", 0.2, level=-2.5)
def ui_close(k):
    y = k.zeros()
    k.put(y, r_whoosh(k, 3000.0, 1800.0, 700.0, 0.13, q=1.4, peak=0.3, air=0.3), 0.0, 0.2)
    k.put(y, r_note(k, hz("A6"), 0.12, "bell", decay=0.04), 0.004, 0.8)
    k.put(y, r_note(k, hz("E6"), 0.13, "bell", decay=0.045), 0.055, 0.9)
    return ui_finish(k, y, 0.2, 0.08)


@sound("ui_deny", 0.25, level=-2.5)
def ui_deny(k):
    """Two low buzzy 'bonk' tones: nuh-uh."""
    y = k.zeros()
    k.put(y, r_note(k, hz("A#3"), 0.09, "square", attack=0.003, decay=0.06, bright=0.7), 0.004, 1.0)
    k.put(y, r_note(k, hz("G3"), 0.11, "square", attack=0.003, decay=0.045, bright=0.6), 0.1, 1.0)
    k.put(y, k.sub(0.08).thump(140.0, 90.0, 0.01, 0.02), 0.004, 0.3)
    return ui_finish(k, y, 0.2, 0.08)


@sound("ui_buy", 0.4, level=-2.0)
def ui_buy(k):
    """Bright confirm arpeggio C#6-E6-A6 with a coin shimmer."""
    y = k.zeros()
    for i, nm in enumerate(("C#6", "E6", "A6")):
        k.put(y, r_note(k, hz(nm), 0.3, "bell", decay=0.09 + 0.03 * i), 0.004 + 0.05 * i, 0.75 + 0.1 * i)
    k.put(y, r_sparkle(k, 0.3, 6, 4500.0, 7500.0), 0.1, 0.18)
    return ui_finish(k, y, 0.3, 0.1)


@sound("ui_cash", 0.35)
def ui_cash(k):
    """'Ka-ching': mechanical 'ka', then a bright bell cluster and coin pings."""
    y = k.zeros()
    k.put(y, r_click(k, 1800.0, 0.004, body=0.6, body_f=260.0, metal=0.5), 0.003, 0.6)
    e = k.sub(0.3)
    ching = e.modal([(2349.0, 0.32, 1.0), (2361.0, 0.3, 0.6, 1.1), (3520.0, 0.26, 0.7), (4698.0, 0.18, 0.5), (5920.0, 0.12, 0.35)])
    k.put(y, ching, 0.045, 0.9)
    for at in (0.06, 0.09, 0.13, 0.17):
        f = k.u(4200.0, 6500.0)
        k.put(y, k.sub(0.1).modal([(f, 0.06, 1.0), (f * 1.41, 0.04, 0.5)]), at, k.u(0.15, 0.3))
    return ui_finish(k, y, 0.25, 0.08)


@sound("ui_notify", 0.3, level=-2.5)
def ui_notify(k):
    y = k.zeros()
    k.put(y, r_note(k, hz("G#5"), 0.22, "bell", decay=0.08, bright=0.8), 0.004, 0.85)
    k.put(y, r_note(k, hz("C#6"), 0.2, "bell", decay=0.08, bright=0.8), 0.085, 1.0)
    return ui_finish(k, y, 0.25, 0.1)


@sound("ui_wheel_tick", 0.04, level=-3.0)
def ui_wheel_tick(k):
    y = k.zeros()
    k.put(y, r_click(k, 3200.0, 0.0008)[: int(0.035 * k.sr)], 0.001, 0.6)
    e = k.sub(0.02)
    k.put(y, e.sine(1500.0) * e.exp(0.003, a=0.0004), 0.001, 0.5)
    return y


@sound("ui_map_ping", 0.3, level=-2.5)
def ui_map_ping(k):
    """Sonar-like ping with a quieter echo."""
    y = k.zeros()
    e = k.sub(0.16)
    p = e.sine(e.sweep(1250.0, 1180.0)) * e.exp(0.045, a=0.002) + 0.2 * e.sine(2500.0) * e.exp(0.02, a=0.002)
    k.put(y, p, 0.003, 1.0)
    k.put(y, e.f(p, LP(1800.0, 2)), 0.11, 0.3)
    return ui_finish(k, y, 0.2, 0.06)


@sound("ui_wanted_up", 0.7)
def ui_wanted_up(k):
    """Tense sting: low dissonant brass cluster, timpani hit, a short riser and a nervous high
    minor-second tremolo."""
    y = k.zeros()
    k.put(y, r_chord(k, ["D3", "D#3", "A3", "D4"], 0.62, "brass", attack=0.01, decay=0.3, bright=1.2), 0.004, 1.0)
    k.put(y, r_thud(k, 95.0, 60.0, 0.12, lp=400.0, noise=0.4), 0.004, 0.8)
    e = k.sub(0.5)
    trem = (e.sine(hz("A5")) + e.sine(hz("A#5"))) * (0.6 + 0.4 * np.sin(TAU * 13.0 * e.t()))
    trem *= e.pts([(0, 0), (0.08, 1.0), (0.5, 0.0)], smooth=True)
    k.put(y, trem, 0.02, 0.12)
    k.put(y, r_whoosh(k, 600.0, 3500.0, 3000.0, 0.2, q=1.0, peak=0.9, air=0.3), 0.0, 0.15)
    return ui_finish(k, y, 0.6, 0.16)


@sound("ui_wanted_clear", 0.9)
def ui_wanted_clear(k):
    """Relief: a soft D major swell with a resolving bell figure A5-F#5-D5."""
    y = k.zeros()
    e = k.sub(0.85)
    pad = sum(e.tri(hz(nm)) * w for nm, w in (("D4", 1.0), ("F#4", 0.8), ("A4", 0.8), ("D5", 0.6)))
    pad *= e.pts([(0, 0), (0.15, 1.0), (0.45, 0.7), (0.85, 0.0)], smooth=True)
    k.put(y, e.f(pad, LP(2500.0, 2)) / 3.2, 0.0, 0.8)
    for i, nm in enumerate(("A5", "F#5", "D5")):
        k.put(y, r_note(k, hz(nm), 0.5, "bell", decay=0.18, bright=0.7), 0.02 + 0.12 * i, 0.55)
    return ui_finish(k, y, 0.8, 0.2)


@sound("ui_busted", 2.0)
def ui_busted(k):
    """Three descending low brass hits (D, C#, C minor-ish) over a boom, the last one held."""
    y = k.zeros()
    for at, root, sec, g in ((0.0, 50, 0.38, 0.9), (0.42, 49, 0.24, 0.8), (0.68, 48, 1.15, 1.0)):
        names = [midi_hz(root - 12), midi_hz(root - 5), midi_hz(root), midi_hz(root + 3)]
        k.put(y, r_chord(k, names, sec, "brass", attack=0.008, decay=0.25 if sec < 0.5 else 0.6, bright=1.3), at + 0.004, g)
        k.put(y, r_thud(k, 90.0, 50.0, 0.1 if sec < 0.5 else 0.25, lp=350.0, noise=0.5), at + 0.004, 0.7 * g)
    e = k.sub(1.1)
    cym = e.f(e.white(), HP(3000.0, 2), LP(11000.0, 2)) * e.exp(0.35, a=0.004)
    k.put(y, cym, 0.69, 0.08)
    return ui_finish(k, y, 1.0, 0.2)


@sound("ui_wasted", 2.5)
def ui_wasted(k):
    """Dark sting: sub boom, a D minor (b6) chord diving in pitch like a stopping tape, long dark tail."""
    y = k.zeros()
    e = k.sub(1.6)
    k.put(y, e.thump(62.0, 34.0, 0.15, 0.5, attack=0.004), 0.004, 1.0)
    e = k.sub(2.1)
    t = e.t()
    dive = 1.0 - 0.22 * (t / 2.1) ** 1.6
    ch = e.zeros()
    for nm, w in (("D3", 1.0), ("F3", 0.8), ("A3", 0.7), ("A#3", 0.5), ("D2", 0.9)):
        ch += w * sum(e.saw(hz(nm) * dive * d, ph=e.u(0, 1)) for d in (0.997, 1.003))
    ch = e.tvlp(ch, 420.0 + 2400.0 * np.exp(-t / 0.5), q=0.8)
    ch *= e.pts([(0, 0), (0.03, 1.0), (1.0, 0.6), (2.1, 0.0)], smooth=True)
    k.put(y, ch / (peak_of(ch) + 1e-9), 0.004, 1.0)
    e = k.sub(1.2)
    k.put(y, e.f(e.white(), BP(900.0, 0.7)) * e.exp(0.3, a=0.002), 0.004, 0.12)
    y = r_tail(k, y, 1.2, 0.25, ((0.25, 0.12),), lp=2500.0)
    return k.fade(y, 0.0, 0.25)


@sound("ui_skill_up", 0.8)
def ui_skill_up(k):
    """Ascending A major pentatonic arpeggio with sparkle."""
    y = k.zeros()
    for i, nm in enumerate(("A5", "B5", "C#6", "E6", "F#6", "A6")):
        k.put(y, r_note(k, hz(nm), 0.4, "bell", decay=0.12, bright=0.9), 0.004 + 0.055 * i, 0.6 + 0.07 * i)
    k.put(y, r_sparkle(k, 0.45, 10), 0.2, 0.2)
    return ui_finish(k, y, 0.5, 0.16)


@sound("ui_checkpoint", 0.4)
def ui_checkpoint(k):
    y = k.zeros()
    k.put(y, r_note(k, hz("E6"), 0.25, "bell", decay=0.07), 0.004, 0.85)
    k.put(y, r_note(k, hz("A6"), 0.28, "bell", decay=0.09), 0.08, 1.0)
    k.put(y, r_note(k, hz("A4"), 0.25, "soft", decay=0.08), 0.08, 0.3)
    return ui_finish(k, y, 0.3, 0.1)


@sound("ui_success", 1.2)
def ui_success(k):
    """Short fanfare: I - IV - V - I (A major) brass stabs, the last chord held with sparkle + timpani."""
    y = k.zeros()
    for at, ch, sec in ((0.0, ["A3", "E4", "A4", "C#5"], 0.13), (0.15, ["D4", "F#4", "A4", "D5"], 0.13),
                        (0.3, ["E4", "G#4", "B4", "E5"], 0.13), (0.45, ["A3", "E4", "A4", "C#5", "E5"], 0.65)):
        k.put(y, r_chord(k, ch, sec, "brass", attack=0.006, decay=0.15 if sec < 0.2 else 0.45, bright=1.4), at + 0.004, 0.9)
    k.put(y, r_thud(k, 110.0, 75.0, 0.2, lp=400.0, noise=0.3), 0.454, 0.6)
    k.put(y, r_sparkle(k, 0.5, 12), 0.5, 0.2)
    return ui_finish(k, y, 0.7, 0.18)


@sound("ui_fail", 1.0)
def ui_fail(k):
    """Descending minor figure E5-C5-A4 on a muted square, the last note sagging a semitone, low bwom."""
    y = k.zeros()
    for i, (nm, sec) in enumerate((("E5", 0.16), ("C5", 0.16), ("A4", 0.55))):
        if i < 2:
            k.put(y, r_note(k, hz(nm), sec, "square", attack=0.005, decay=0.1, bright=0.5), 0.004 + 0.17 * i, 0.8)
    e = k.sub(0.55)
    t = e.t()
    sag = hz("A4") * (1.0 - 0.056 * np.clip((t - 0.12) / 0.35, 0.0, 1.0)) * (1.0 + 0.008 * np.sin(TAU * 5.0 * t))
    last = e.f(e.pulse(sag, 0.4), LP(1100.0, 2)) * e.pts([(0, 0), (0.01, 1.0), (0.35, 0.7), (0.55, 0.0)], smooth=True)
    k.put(y, last / peak_of(last), 0.344, 0.9)
    k.put(y, r_thud(k, 80.0, 50.0, 0.18, lp=300.0, noise=0.3), 0.344, 0.5)
    return ui_finish(k, y, 0.4, 0.12)


@sound("ui_countdown", 0.2, level=-2.5)
def ui_countdown(k):
    y = k.zeros()
    e = k.sub(0.15)
    b = (e.sine(880.0) + 0.15 * e.sine(2640.0)) * e.pts([(0, 0), (0.004, 1.0), (0.1, 0.8), (0.15, 0.0)], smooth=True)
    k.put(y, b, 0.002)
    return ui_finish(k, y, 0.15, 0.05)


@sound("ui_go", 0.5)
def ui_go(k):
    y = k.zeros()
    e = k.sub(0.38)
    b = (e.sine(1760.0) + 0.5 * e.sine(880.0) + 0.12 * e.sine(5280.0)) * e.pts([(0, 0), (0.004, 1.0), (0.22, 0.75), (0.38, 0.0)], smooth=True)
    k.put(y, b, 0.002, 0.9)
    k.put(y, r_chord(k, ["A5", "C#6", "E6"], 0.35, "bell", decay=0.12, bright=0.6), 0.002, 0.4)
    k.put(y, r_whoosh(k, 1000.0, 5000.0, 4000.0, 0.12, q=1.2, peak=0.8, air=0.3), 0.0, 0.15)
    return ui_finish(k, y, 0.35, 0.1)


# ----------------------------------------------------------------------------------------------
# 5e. WORLD / AMBIENCE
# ----------------------------------------------------------------------------------------------
family("world")

AMB = dict(aperiodic=True)


def r_passby(k, sec, bright=1500.0, engine_hz=0.0, doppler=0.04):
    """One vehicle passing at a distance: road noise swelling and fading (brighter at its closest),
    optionally an engine drone whose pitch drops through the pass (Doppler)."""
    e = k.sub(sec)
    u = e.t() / sec
    env = np.sin(np.pi * u) ** 3
    y = e.tvlp(e.cnoise(-3.0, lo=60.0), 250.0 + bright * env, q=0.6)
    y = y / (rms_of(y) + 1e-12)
    if engine_hz:
        f = engine_hz * (1.0 + doppler * np.tanh(6.0 * (0.5 - u)))
        tone = e.f(e.saw(f) + 0.5 * e.saw(f * 0.5), LP(320.0, 2))
        y += 0.7 * tone / (rms_of(tone) + 1e-12)
    return y * env


def r_chirp(k, sec, f0, f1, curve=1.0, trill=0.0, trill_rate=25.0, harm=0.12):
    """Bird note: a pure tone gliding f0 -> f1 (curve shapes the glide), optional trill AM."""
    e = k.sub(sec)
    t = e.t()
    u = t / sec
    f = f0 + (f1 - f0) * u ** curve
    y = e.sine(f) + harm * e.sine(2.0 * f)
    env = np.sin(np.pi * u) ** 0.8
    if trill:
        env = env * ((1.0 - trill) + trill * (0.5 + 0.5 * np.sin(TAU * trill_rate * t)) ** 2)
    return y * env


def r_bird_phrase(k, kind):
    """One phrase of synthetic birdsong: 'warble' (fast random chirps), 'whistle' (2-3 slow glides),
    'trill' (amplitude-modulated buzz), 'twitter' (short up-chirps)."""
    out = []
    t = 0.0
    if kind == "warble":
        for _ in range(int(k.u(6, 12))):
            d = k.u(0.03, 0.09)
            f0 = k.u(2600.0, 5800.0)
            out.append((t, r_chirp(k, d, f0, f0 * k.u(0.7, 1.35), curve=k.u(0.5, 2.0))))
            t += d + k.u(0.015, 0.05)
    elif kind == "whistle":
        f = k.u(2300.0, 3400.0)
        for _ in range(int(k.u(2, 4))):
            d = k.u(0.14, 0.32)
            out.append((t, r_chirp(k, d, f, f * k.u(0.85, 1.18), curve=0.7, harm=0.05)))
            t += d + k.u(0.06, 0.14)
            f *= k.u(0.85, 1.12)
    elif kind == "trill":
        d = k.u(0.45, 0.9)
        f0 = k.u(3600.0, 5200.0)
        out.append((0.0, r_chirp(k, d, f0, f0 * k.u(0.85, 0.97), trill=0.9, trill_rate=k.u(18.0, 32.0))))
        t = d
    else:
        for _ in range(int(k.u(3, 7))):
            d = k.u(0.02, 0.05)
            f0 = k.u(3800.0, 6500.0)
            out.append((t, r_chirp(k, d, f0 * 0.8, f0 * 1.2, curve=0.6)))
            t += d + k.u(0.04, 0.09)
    e = k.sub(t + 0.05)
    y = e.zeros()
    for at, s in out:
        e.put(y, s, at)
    return y / (peak_of(y) + 1e-12)


def r_cricket(k, y, carrier, period, pulses=4, rate=32.0, gain=1.0):
    """Field cricket: chirps of `pulses` short tone pulses every `period` s (snapped so that the
    rhythm wraps exactly around a loop)."""
    N = max(1, int(round(k.dur / period)))
    per = k.dur / N
    t0 = k.u(0.0, per)
    for i in range(N):
        e = k.sub(pulses / rate + 0.02)
        t = e.t()
        env = np.zeros(e.n)
        for j in range(pulses):
            u = (t - j / rate) * rate / 0.6
            env += np.where((u >= 0.0) & (u <= 1.0), np.sin(np.pi * np.clip(u, 0.0, 1.0)) ** 2, 0.0)
        k.put(y, e.sine(carrier * (1.0 + 0.004 * np.sin(TAU * 9.0 * t))) * env, t0 + i * per + k.u(-0.004, 0.004), gain * k.u(0.8, 1.0))
    return y


def r_traffic(k, count, bright=(800.0, 2500.0), gain=(0.25, 1.0), engines=0.5):
    """Distant traffic wash: overlapping pass-bys spread around the loop."""
    y = k.zeros()
    for _ in range(count):
        sec = k.u(3.0, 7.0)
        eh = k.u(38.0, 90.0) if k.rng.random() < engines else 0.0
        k.put(y, r_passby(k, sec, k.u(*bright), eh), k.u(0.0, k.dur), k.u(*gain))
    return y


@sound("amb_city_day_loop", 16.0, loop=True, check=AMB)
def amb_city_day_loop(k):
    """Daytime downtown: traffic wash and pass-bys, low city hum, faint distant horns, a clank,
    a few sparrows; everything sits in a big outdoor reverb."""
    y = r_traffic(k, 15)
    y += 0.9 * k.cnoise(-4.5, lo=40.0, hi=1800.0) * (0.85 + 0.15 * k.lfon(0.05))
    y += 0.5 * k.cnoise(-6.0, lo=25.0, hi=150.0) + 0.04 * k.harm(60.0, [1.0, 0.5, 0.3])
    for at, fs in ((3.1, [405.0, 508.0]), (11.7, [350.0, 440.0]), (13.2, [350.0, 440.0])):
        h = r_horn_tone(k, k.u(0.18, 0.4), fs, buzz=0.4, lp=2500.0)
        k.put(y, k.sub(len(h) / k.sr).f(h, LP(1500.0, 2)), at, 0.35)
    k.put(y, k.sub(0.4).f(r_metal_cluster(k, 0.4, 8, 200.0, 2000.0, 0.3), LP(2500.0, 2)), 7.4, 0.25)
    for _ in range(4):
        k.put(y, k.sub(0.6).f(r_bird_phrase(k, "twitter")[: int(0.6 * k.sr)], LP(6000.0, 2)), k.u(0.0, 16.0), 0.08)
    return k.rev(y, 1.4, 0.25, hi=4000.0, lo=80.0)


@sound("amb_city_night_loop", 16.0, loop=True, check=AMB)
def amb_city_night_loop(k):
    """Night: sparse darker traffic, the hum, a distant siren wail drifting in, crickets, a far dog."""
    y = 0.7 * r_traffic(k, 6, (500.0, 1200.0), (0.2, 0.7), 0.6)
    y += 0.55 * k.cnoise(-5.0, lo=40.0, hi=900.0) * (0.75 + 0.25 * k.lfon(0.08))
    y += 0.5 * k.cnoise(-6.0, lo=25.0, hi=150.0) + 0.05 * k.harm(60.0, [1.0, 0.5, 0.3])
    e = k.sub(5.0)
    f = 650.0 + 600.0 * wail_curve((e.t() / 2.5) % 1.0, 0.4)
    sir = e.f(e.pulse(f, 0.5), LP(1100.0, 2)) * e.pts([(0, 0), (1.5, 1.0), (3.5, 0.8), (5.0, 0.0)], smooth=True)
    k.put(y, sir / peak_of(sir), 4.0, 0.06)
    for c, per, g in ((4300.0, 0.42, 0.18), (4650.0, 0.55, 0.12), (4900.0, 0.37, 0.08), (4100.0, 0.66, 0.1), (5200.0, 0.48, 0.05)):
        r_cricket(k, y, c, per, pulses=int(k.u(3, 6)), gain=g)
    k.put(y, k.sub(0.4).f(dog_bark(k, 2)[: int(0.4 * k.sr)], LP(1200.0, 2)), 9.3, 0.08)
    return k.rev(y, 1.6, 0.25, hi=4500.0, lo=80.0)


@sound("amb_park_loop", 16.0, loop=True, check=AMB)
def amb_park_loop(k):
    """Park: birdsong from several synthetic 'species', leaves in a light breeze, a faint city."""
    gust = 0.5 + 0.5 * k.lfon(0.15)
    leaves = k.bnoise(1500.0, 7000.0) * np.abs(k.lfon(30.0)) ** 1.5 * (0.3 + 0.7 * gust)
    y = 0.5 * leaves + 0.35 * k.cnoise(-5.0, lo=40.0, hi=600.0) * (0.8 + 0.2 * k.lfon(0.1))
    for kind, count, g in (("warble", 6, 0.35), ("whistle", 5, 0.3), ("trill", 3, 0.2), ("twitter", 6, 0.22)):
        for _ in range(count):
            ph = r_bird_phrase(k, kind)
            k.put(y, ph, k.u(0.0, 16.0), g * k.u(0.5, 1.0))
    return k.rev(y, 0.9, 0.16, hi=8000.0, lo=150.0)


def r_wave(k, sec, size=1.0):
    """One surf wave: rising swell, crash, fizzing foam wash, receding backwash."""
    e = k.sub(sec)
    t = e.t()
    b = 1.3 * size
    up = np.clip(t / b, 0.0, 1.0)
    swell = e.tvlp(e.cnoise(-4.0, lo=40.0), 200.0 + 1300.0 * up ** 2, q=0.7)
    swell = swell / rms_of(swell) * np.where(t < b, up ** 2, np.exp(-(t - b) / 0.8))
    crash = e.f(e.cnoise(-2.5, lo=150.0), LP(7000.0, 2))
    crash = crash / rms_of(crash) * np.where(t < b, 0.0, (1.0 - np.exp(-(t - b) / 0.06)) * np.exp(-(t - b) / (0.7 * size)))
    foam = e.f(e.white(), HP(1500.0, 2), LP(9000.0, 2)) * np.abs(e.lfon(40.0)) ** 1.2
    foam = foam / rms_of(foam) * np.clip((t - b - 0.1) / 0.6, 0.0, 1.0) * np.exp(-np.maximum(t - b - 0.7, 0.0) / (1.3 * size))
    back = e.f(e.cnoise(-3.0, lo=200.0), LP(2500.0, 2))
    bu = np.clip((t - b - 1.4) / max(sec - b - 1.4, 0.1), 0.0, 1.0)
    back = back / rms_of(back) * np.sin(np.pi * bu) ** 2
    y = 0.8 * swell + 1.0 * crash + 0.5 * foam + 0.35 * back
    return y * fade(np.ones(e.n), e.sr, 0.05, 0.3)


@sound("amb_ocean_loop", 16.0, loop=True, check=AMB)
def amb_ocean_loop(k):
    """Beach: four irregular surf swells over a constant low surf rumble and distant wash."""
    y = 0.6 * k.cnoise(-6.0, lo=25.0, hi=220.0) * (0.75 + 0.25 * k.lfon(0.2))
    y += 0.3 * k.cnoise(-3.0, lo=200.0, hi=2500.0) * (0.7 + 0.3 * k.lfon(0.15))
    for at, size, g in ((0.4, 1.0, 1.0), (3.7, 0.65, 0.55), (8.9, 1.2, 1.0), (12.3, 0.8, 0.7), (14.6, 0.5, 0.35)):
        k.put(y, r_wave(k, 5.2 * size, size), at, g)
    return k.rev(y, 1.2, 0.2, hi=6000.0, lo=60.0)


@sound("amb_industrial_loop", 12.0, loop=True)
def amb_industrial_loop(k):
    """Factory hall: two beating motor drones, machine noise, conveyor rattle, a press stamping every
    1.5 s, distant clanks, a steam release and a reversing beeper, all in a long hall reverb."""
    y = 0.25 * k.harm(50.0, [1.0, 0.7, 0.5, 0.45, 0.3, 0.25, 0.2, 0.12]) + 0.18 * k.harm(50.7, [1.0, 0.5, 0.4, 0.2, 0.15])
    y += 0.7 * k.cnoise(-3.0, lo=80.0, hi=3000.0) * (0.85 + 0.15 * k.lfon(0.5))
    rat = k.f(k.sparks(80.0, power=1.5), BANK([(1800.0, 10.0, 1.0), (2700.0, 12.0, 0.6), (950.0, 8.0, 0.5)]))
    y += 0.35 * rat / (rms_of(rat) + 1e-12)
    for i in range(8):
        e = k.sub(0.5)
        hit = e.thump(70.0, 40.0, 0.02, 0.12) + 0.4 * r_metal_cluster(k, 0.5, 8, 180.0, 1800.0, 0.25)
        k.put(y, hit, 0.3 + 1.5 * i, 1.8 * k.u(0.9, 1.1))
    for _ in range(4):
        k.put(y, k.sub(0.8).f(r_metal_cluster(k, 0.8, 10, 250.0, 3000.0, 0.5), LP(3000.0, 2)), k.u(0.0, 12.0), 0.5)
    e = k.sub(1.3)
    k.put(y, e.f(e.white(), HP(1800.0, 2), LP(9000.0, 2)) * e.pts([(0, 0), (0.05, 1.0), (1.3, 0.0)], smooth=True), 6.3, 0.45)
    for i in range(5):
        e = k.sub(0.25)
        k.put(y, e.f(e.sine(1050.0) * e.pts([(0, 0), (0.01, 1.0), (0.24, 1.0), (0.25, 0.0)]), LP(3000.0, 2)), 9.0 + 0.5 * i, 0.12)
    return k.rev(y, 2.0, 0.3, hi=3500.0, lo=60.0)


@sound("amb_wind_loop", 12.0, loop=True, check=AMB)
def amb_wind_loop(k):
    """Strong wind: gusting broadband roar, whistling around edges, rustle, low buffeting."""
    gust = 0.5 + 0.5 * k.lfon(0.18)
    roar = k.cnoise(-4.0, lo=40.0, hi=6000.0) * (0.35 + 0.65 * gust)
    w1 = k.tvbp(k.white(), k.wander(0.12, 500.0, 1100.0) * (1.0 + 0.2 * gust), 12.0)
    w2 = k.tvbp(k.white(), k.wander(0.15, 1400.0, 2200.0) * (1.0 + 0.15 * gust), 14.0)
    whistle = (w1 / rms_of(w1) + 0.5 * w2 / rms_of(w2)) * gust ** 2
    rustle = k.bnoise(1500.0, 8000.0) * np.abs(k.lfon(25.0)) ** 2 * gust
    low = k.cnoise(-6.0, lo=20.0, hi=120.0) * (0.5 + 0.5 * gust)
    return roar + 0.25 * whistle + 0.3 * rustle + 0.6 * low


@sound("amb_interior_loop", 8.0, loop=True, check=AMB)
def amb_interior_loop(k):
    """Room tone: soft air, ventilation, a faint fridge hum and very distant muffled traffic."""
    room = k.cnoise(-4.5, lo=60.0, hi=2500.0) * 0.5
    fridge = k.harm(120.0 * (1.0 + 0.0005 * k.lfon(0.2)), [1.0, 0.6, 0.35, 0.2, 0.15, 0.1]) * (0.9 + 0.1 * k.lfon(0.3))
    hvac = k.cnoise(-2.0, lo=200.0, hi=5000.0) * (0.9 + 0.1 * k.lfon(0.3))
    traffic = k.cnoise(-6.0, lo=40.0, hi=300.0) * (0.6 + 0.4 * k.lfon(0.15))
    return room + 0.06 * fridge + 0.15 * hvac + 0.35 * traffic


def r_rain(k, density, heavy=0.0):
    """Rain: thousands of tiny drop impacts, broadband hiss, distinct drips / plinks, gutter trickle
    (heavy > 0 adds a low roar and denser splatter)."""
    drops = k.f(k.sparks(density, power=3.0), BP(3500.0, 0.7), LP(11000.0, 2))
    hiss = k.snoise(TILT(-1.0), HP(500.0, 2), LP(11000.0, 2)) * (0.85 + 0.15 * k.lfon(0.5))
    y = drops / (rms_of(drops) + 1e-12) + 0.8 * hiss
    gutter = k.f(k.white() * np.abs(k.lfon(18.0)) ** 2, BP(700.0, 1.2))
    y += 0.25 * gutter / (rms_of(gutter) + 1e-12)
    for _ in range(int(40 - 20 * heavy)):
        e = k.sub(0.06)
        f = k.u(1500.0, 4200.0)
        k.put(y, e.sine(e.sweep(f, f * 1.3)) * e.exp(k.u(0.008, 0.025), a=0.0005), k.u(0.0, k.dur), k.u(0.4, 1.2))
    if heavy:
        roar = k.cnoise(-3.0, lo=80.0, hi=1500.0) * (0.8 + 0.2 * k.lfon(0.3))
        splat = k.f(k.sparks(density * 0.3, power=2.0), BP(1100.0, 0.8))
        y += heavy * (1.1 * roar + 0.6 * splat / (rms_of(splat) + 1e-12))
    return k.f(y, LP(12000.0, 2))


@sound("rain_loop", 8.0, loop=True, check=AMB)
def rain_loop(k):
    return r_rain(k, 2200.0)


@sound("rain_heavy_loop", 8.0, loop=True, check=AMB)
def rain_heavy_loop(k):
    return r_rain(k, 7000.0, heavy=1.0)


def r_thunder(k, close):
    """Thunder: (close) a ripping crackle front, then rolling low rumble built from several random
    swells whose brightness closes over time, in a huge reverb."""
    t = k.t()
    y = k.zeros()
    if close:
        crack = k.f(k.sparks(4000.0, power=2.0) * k.pts([(0, 0), (0.02, 1.0), (0.12, 0.6), (0.45, 0.0)]), HP(600.0, 2), LP(9000.0, 2))
        rip = k.tvbp(k.white(), k.pts([(0, 3000.0), (0.3, 900.0)]), 0.8) * k.pts([(0, 0), (0.015, 1.0), (0.35, 0.0)], smooth=True)
        y += crack / (peak_of(crack) + 1e-12) + 0.6 * rip / (peak_of(rip) + 1e-12)
    env = np.zeros(k.n)
    for i in range(6):
        t0 = (0.05 if close else 0.25) + (k.u(0.0, 0.6) if i == 0 else k.u(0.3, k.dur * 0.6))
        rise, dec = k.u(0.05, 0.3), k.u(0.4, 1.2)
        env += k.u(0.4, 1.0) * np.where(t < t0, 0.0, (1.0 - np.exp(-(t - t0) / rise)) * np.exp(-np.maximum(t - t0 - rise, 0.0) / dec))
    env = env / (peak_of(env) + 1e-12) * np.exp(-t / (0.45 * k.dur))
    cut = (900.0 if close else 650.0) * np.exp(-t / 1.5) + 110.0
    rumble = k.tvlp(k.cnoise(-6.0, lo=20.0), cut, q=0.7)
    y += (1.4 if close else 1.0) * rumble / (peak_of(rumble) + 1e-12) * env
    body = k.f(k.cnoise(-3.0, lo=150.0), BP(450.0, 0.8))
    y += 0.25 * body / (peak_of(body) + 1e-12) * env * (1.0 if close else 0.8)
    y = k.sat(norm_peak(y, 0.0), 1.5)
    y = k.rev(y, 3.0, 0.35, hf=0.35, hi=3000.0, lo=40.0)
    return k.fade(y, 0.0, 0.6)


@sound("thunder_1", 4.2)
def thunder_1(k):
    return r_thunder(k, True)


@sound("thunder_2", 4.8)
def thunder_2(k):
    return r_thunder(k, False)


def r_babble_voice(k, sec, male=True):
    """One voice of unintelligible chatter: phrases of vowel-like syllables with random formants and
    falling pitch (no consonants, no words)."""
    e = k.sub(sec)
    y = e.zeros()
    t = k.u(0.0, 0.6)
    f0 = k.u(95.0, 140.0) if male else k.u(170.0, 240.0)
    sc = 1.0 if male else 1.15
    while t < sec - 0.4:
        end = t + k.u(0.8, 2.6)
        decl = 1.0
        while t < end and t < sec - 0.3:
            d = k.u(0.1, 0.24)
            F1, F2, F3 = k.u(300.0, 800.0) * sc, k.u(900.0, 2300.0) * sc, k.u(2300.0, 3000.0) * sc
            g = r_voice(k, d, [(0, f0 * decl * k.u(0.97, 1.12)), (d, f0 * decl * k.u(0.85, 1.0))],
                        [(F1, F1 * k.u(0.85, 1.15), 90.0), (F2, F2 * k.u(0.85, 1.15), 120.0), (F3, F3, 180.0)],
                        breath=0.25, jitter=0.02, hpc=True)
            g *= np.sin(np.pi * np.arange(len(g)) / len(g)) ** 1.2
            e.put(y, g, t, k.u(0.4, 1.0))
            t += d + k.u(0.0, 0.07)
            decl *= 0.97
        t += k.u(0.3, 1.4)
    return y


@sound("crowd_murmur_loop", 10.0, loop=True, check=AMB)
def crowd_murmur_loop(k):
    """Wordless crowd babble: ~22 overlapping synthetic voices + formant-filtered noise bursts,
    blurred by distance and a room-ish reverb."""
    y = k.zeros()
    for i in range(22):
        v = r_babble_voice(k, k.dur, male=(i % 3 != 0))
        k.put(y, v, k.u(0.0, k.dur), k.u(0.4, 1.0))
    for _ in range(40):
        e = k.sub(k.u(0.1, 0.3))
        F1, F2 = k.u(350.0, 800.0), k.u(1000.0, 2200.0)
        b = e.f(e.white(), BANK([(F1, 5.0, 1.0), (F2, 7.0, 0.6)]), LP(3500.0, 2)) * np.sin(np.pi * e.t() / e.dur) ** 2
        k.put(y, b / (peak_of(b) + 1e-12), k.u(0.0, k.dur), k.u(0.03, 0.08) * peak_of(y))
    y = k.f(y, HP(120.0, 2), HS(1800.0, 9.0), LP(6500.0, 2))
    return k.rev(y, 1.0, 0.3, hi=5000.0)


def r_radio_talk(k, sec, f0=115.0):
    """Garbled dispatcher-style radio chatter: vowel syllables crushed into a 300-3000 Hz band with
    hard clipping, sample-rate reduction and dropouts (never intelligible)."""
    e = k.sub(sec)
    y = e.zeros()
    t = 0.0
    while t < sec - 0.12:
        d = k.u(0.07, 0.2)
        F1, F2 = k.u(350.0, 800.0), k.u(1000.0, 2200.0)
        g = r_voice(k, d, [(0, f0 * k.u(0.95, 1.25)), (d, f0 * k.u(0.85, 1.05))], [(F1, F1 * k.u(0.8, 1.2), 100.0), (F2, F2 * k.u(0.8, 1.2), 130.0),
                    (2600.0, 2500.0, 200.0)], breath=0.4, rough=0.3, jitter=0.03, hpc=True)
        e.put(y, g * np.sin(np.pi * np.arange(len(g)) / len(g)) ** 0.7, t, k.u(0.5, 1.0))
        t += d + (k.u(0.1, 0.25) if k.rng.random() < 0.2 else k.u(0.0, 0.04))
    y = np.clip(4.0 * y / (peak_of(y) + 1e-12), -1.0, 1.0)
    y = bitcrush(y, 7, 4)
    y *= 0.75 + 0.25 * np.sign(e.lfon(12.0))
    return e.f(y, HP(350.0, 2), PK(1800.0, 5.0, 1.0), LP(2900.0, 4))


def r_police_radio(k, talks):
    y = k.zeros()
    end = talks[-1][0] + talks[-1][1]
    e = k.sub(end + 0.05)
    k.put(y, e.f(e.white(), BP(1500.0, 0.6)) * e.pts([(0, 0), (0.005, 1.0), (end, 0.8), (end + 0.05, 0.0)]) * 0.08, 0.0)
    e = k.sub(0.06)
    k.put(y, e.f(e.white(), HP(300.0, 2), LP(3500.0, 2)) * e.exp(0.02, a=0.001), 0.0, 0.7)
    for at, sec in talks:
        k.put(y, r_radio_talk(k, sec, k.u(105.0, 135.0)), at, 0.9)
    e = k.sub(0.12)
    k.put(y, e.f(e.white(), HP(300.0, 2), LP(3500.0, 2)) * e.exp(0.04, a=0.002), end + 0.01, 0.6)
    e = k.sub(0.07)
    k.put(y, e.sine(1250.0) * e.pts([(0, 0), (0.004, 1.0), (0.06, 1.0), (0.07, 0.0)]), end + 0.03, 0.25)
    return y


@sound("police_radio_1", 1.2)
def police_radio_1(k):
    return r_police_radio(k, [(0.06, 0.95)])


@sound("police_radio_2", 1.2)
def police_radio_2(k):
    return r_police_radio(k, [(0.05, 0.42), (0.6, 0.38)])


GULL_FORMS = [(1700.0, 1900.0, 260.0), (3300.0, 3200.0, 380.0), (4500.0, 4400.0, 450.0)]


def r_gull_note(k, sec, f0):
    return r_vocal(k, sec, f0, GULL_FORMS, [(0, 0), (0.015, 1.0), (sec * 0.6, 0.8), (sec, 0.0)], presence=6.0, air=-24.0,
                   breath=0.3, rough=0.45, sub=0.25, jitter=0.03, tilt=2500.0)


@sound("seagull_1", 0.9)
def seagull_1(k):
    """'Kyow-kyow-kyow': three descending harsh calls."""
    y = k.zeros()
    for at, s, g in ((0.0, 1.0, 1.0), (0.29, 0.95, 0.85), (0.55, 0.9, 0.7)):
        k.put(y, r_gull_note(k, 0.22, [(0, 700.0 * s), (0.07, 1250.0 * s), (0.22, 800.0 * s)]), at + 0.005, g)
    return r_tail(k, y, 0.4, 0.12, ((0.12, 0.08),), lp=5000.0)


@sound("seagull_2", 0.9)
def seagull_2(k):
    """Long 'kee-aaah' followed by short laughing 'ha-ha-ha' notes."""
    y = k.zeros()
    k.put(y, r_gull_note(k, 0.4, [(0, 900.0), (0.08, 1350.0), (0.25, 1250.0), (0.4, 800.0)]), 0.005, 1.0)
    for i, at in enumerate((0.48, 0.57, 0.655, 0.735)):
        k.put(y, r_gull_note(k, 0.07, [(0, 1050.0 - 30 * i), (0.07, 820.0 - 30 * i)]), at, 0.75 - 0.12 * i)
    return r_tail(k, y, 0.35, 0.1, ((0.11, 0.07),), lp=5000.0)


def dog_bark(k, v):
    """One bark: rough, noisy, fast rise-fall pitch; v=1 medium dog, v=2 big dog."""
    if v == 1:
        return r_vocal(k, 0.13, [(0, 420.0), (0.02, 560.0), (0.07, 500.0), (0.13, 330.0)],
                       [(800.0, 650.0, 140.0), (1650.0, 1400.0, 180.0), (2800.0, 2600.0, 250.0)],
                       [(0, 0), (0.008, 1.0), (0.05, 0.8), (0.13, 0.0)], presence=8.0, air=-22.0,
                       breath=0.5, rough=0.6, sub=0.4, jitter=0.04)
    return r_vocal(k, 0.18, [(0, 240.0), (0.03, 330.0), (0.1, 290.0), (0.18, 190.0)],
                   [(600.0, 480.0, 120.0), (1150.0, 950.0, 150.0), (2400.0, 2200.0, 220.0)],
                   [(0, 0), (0.01, 1.0), (0.08, 0.8), (0.18, 0.0)], presence=8.0, air=-22.0,
                   breath=0.45, rough=0.7, sub=0.5, jitter=0.04)


@sound("dog_bark_1", 0.4)
def dog_bark_1(k):
    y = k.zeros()
    k.put(y, dog_bark(k, 1), 0.005)
    return r_tail(k, y, 0.35, 0.12, ((0.09, 0.12), (0.17, 0.05)), lp=4000.0)


@sound("dog_bark_2", 0.4)
def dog_bark_2(k):
    y = k.zeros()
    k.put(y, dog_bark(k, 2), 0.005)
    return r_tail(k, y, 0.3, 0.12, ((0.1, 0.12),), lp=3500.0)


@sound("cat_meow", 0.6)
def cat_meow(k):
    """'Mi-a-ow': rising-falling pitch while the mouth opens (i -> a) and closes (-> u)."""
    y = k.zeros()
    m = r_vocal(k, 0.52, [(0, 520.0), (0.12, 700.0), (0.3, 680.0), (0.52, 450.0)],
                [([(0, 450.0), (0.15, 950.0), (0.52, 600.0)], None, 110.0), ([(0, 2300.0), (0.15, 1700.0), (0.52, 1000.0)], None, 150.0),
                 ([(0, 3300.0), (0.52, 2900.0)], None, 220.0)],
                [(0, 0), (0.04, 1.0), (0.4, 0.7), (0.52, 0.0)], presence=12.0, air=-24.0, breath=0.25, rough=0.1, jitter=0.015)
    k.put(y, m, 0.005)
    return k.rev(y, 0.25, 0.08, hi=7000.0)


@sound("deer_snort", 0.4)
def deer_snort(k):
    """Forceful nasal blast (and a weaker second one)."""
    y = k.zeros()
    for at, g in ((0.0, 1.0), (0.2, 0.55)):
        e = k.sub(0.18)
        x = e.white() * e.pts([(0, 0), (0.004, 1.0), (0.05, 0.6), (0.18, 0.0)], smooth=True)
        s = e.f(x, BANK([(320.0, 2.5, 1.0), (1050.0, 3.5, 0.7), (2300.0, 4.0, 0.4)], direct=0.1), HP(150.0, 2), LP(6000.0, 2))
        s = s / peak_of(s) + 0.5 * e.f(x, LP(400.0, 2)) / (peak_of(e.f(x, LP(400.0, 2))) + 1e-9)
        k.put(y, e.sat(s / peak_of(s), 1.6), at + 0.003, g)
    return k.rev(y, 0.3, 0.1, hi=6000.0)


@sound("bird_flap", 0.5, level=-2.0)
def bird_flap(k):
    """A pigeon taking off: a run of wing beats, weakening as it climbs away."""
    y = k.zeros()
    for i in range(6):
        e = k.sub(0.09)
        w = e.tvbp(e.white() * (0.5 + 0.5 * np.abs(e.lfon(120.0))), e.sweep(600.0, 1800.0), 1.0) * np.sin(np.pi * e.t() / 0.09) ** 2
        w = e.f(w, LP(5000.0 - 500.0 * i, 2))
        k.put(y, w / (peak_of(w) + 1e-9), 0.003 + 0.072 * i, 0.82 ** i)
    return k.rev(y, 0.3, 0.08, hi=7000.0)


@sound("hydrant_spray_loop", 3.0, loop=True, check=AMB)
def hydrant_spray_loop(k):
    """Burst hydrant: high-pressure jet roar, water splattering on the street, a low gurgle."""
    jet = k.snoise(TILT(0.0), HP(300.0, 2), PK(2800.0, 5.0, 0.8), LP(10000.0, 2)) * (0.9 + 0.1 * k.lfon(6.0))
    splat = k.f(k.white() * (0.4 + 0.6 * np.abs(k.lfon(30.0)) ** 1.5), BP(1500.0, 0.7))
    gurgle = k.cnoise(-6.0, lo=40.0, hi=350.0) * (0.6 + 0.4 * np.abs(k.lfon(4.0)))
    drops = k.f(k.sparks(500.0, power=2.0), BP(2500.0, 1.0))
    return jet + 0.7 * splat / rms_of(splat) + 0.5 * gurgle + 0.3 * drops / (rms_of(drops) + 1e-12)


@sound("auto_door", 0.8)
def auto_door(k):
    """Pneumatic sliding door: valve hiss, belt-drive slide with motor hum, soft rubber stop."""
    y = k.zeros()
    e = k.sub(0.16)
    k.put(y, e.f(e.white(), HP(2500.0, 2), LP(9000.0, 2)) * e.pts([(0, 0), (0.005, 1.0), (0.16, 0.0)], smooth=True), 0.003, 0.4)
    e = k.sub(0.62)
    t = e.t()
    env = e.pts([(0, 0), (0.08, 1.0), (0.5, 0.9), (0.62, 0.0)], smooth=True)
    hum = e.harm(118.0, [1.0, 0.5, 0.3, 0.15]) + 0.4 * e.sine(e.pts([(0, 650.0), (0.3, 760.0), (0.62, 700.0)]))
    slide = e.f(e.white(), BP(420.0, 1.2)) * 0.6 + e.f(e.white(), BP(2200.0, 2.0)) * 0.15
    s = (hum / rms_of(hum) * 0.4 + slide / rms_of(slide)) * env
    k.put(y, s / peak_of(s), 0.06, 0.6)
    k.put(y, r_thud(k, 130.0, 80.0, 0.03, lp=500.0), 0.68, 0.45)
    return k.rev(y, 0.35, 0.1, hi=6000.0)


@sound("shop_bell", 0.8)
def shop_bell(k):
    """Brass bell on a shop door jingling: three clapper strikes, ringing."""
    y = k.zeros()
    for at, g in ((0.0, 1.0), (0.11, 0.6), (0.19, 0.4)):
        f = 1890.0 * k.u(0.996, 1.004)
        modes = [(f, 0.45, 1.0), (f * 1.004, 0.42, 0.7, 1.0), (f * 1.43, 0.32, 0.6), (f * 2.17, 0.25, 0.45), (f * 2.82, 0.18, 0.35),
                 (f * 3.6, 0.12, 0.2)]
        k.put(y, k.sub(0.6).modal(modes), at + 0.003, g)
        k.put(y, r_click(k, 3000.0, 0.0012, metal=0.2), at + 0.002, 0.2 * g)
    return k.rev(y, 0.4, 0.1, hi=8000.0)


@sound("elevator_ding", 0.9)
def elevator_ding(k):
    """Soft vibraphone-like chime: E6 with a quiet A5 underneath."""
    y = k.zeros()
    k.put(y, r_note(k, hz("E6"), 0.82, "bell", decay=0.3, bright=0.6), 0.004, 1.0)
    k.put(y, r_note(k, hz("A5"), 0.8, "soft", decay=0.28), 0.004, 0.35)
    return k.rev(y, 0.5, 0.12, hi=7000.0)


@sound("cash_register", 0.7)
def cash_register(k):
    """Old till: key presses, the drawer's release clunk, bell 'ching', drawer rolling out."""
    y = k.zeros()
    for at in (0.0, 0.08, 0.15):
        k.put(y, r_click(k, k.u(1300.0, 1700.0), 0.004, body=0.6, body_f=220.0, metal=0.3), at + 0.003, 0.6)
    k.put(y, r_click(k, 900.0, 0.006, body=1.0, body_f=140.0, metal=0.4), 0.23, 1.0)
    e = k.sub(0.45)
    k.put(y, e.modal([(2093.0, 0.35, 1.0), (2101.0, 0.33, 0.6, 1.0), (3140.0, 0.25, 0.6), (4180.0, 0.18, 0.4), (5250.0, 0.12, 0.25)]), 0.24, 0.8)
    k.put(y, r_scrape(k, 0.18, 700.0, 1100.0, q=2.0), 0.25, 0.35)
    for i in range(5):
        k.put(y, r_click(k, 2200.0, 0.0015, metal=0.3), 0.26 + 0.03 * i, 0.12)
    k.put(y, r_thud(k, 150.0, 90.0, 0.02, lp=600.0), 0.44, 0.5)
    return k.rev(y, 0.3, 0.08, hi=6000.0)


@sound("phone_ring", 2.0, loop=True, level=-16.0)
def phone_ring(k):
    """Original mobile ringtone: an eight-note marimba-ish figure (E major pentatonic), then a rest."""
    y = k.zeros()
    for i, nm in enumerate(("E6", "B5", "G#5", "B5", "E6", "F#6", "E6", "B5")):
        k.put(y, r_note(k, hz(nm), 0.25, "bell", decay=0.07, bright=0.5), 0.02 + 0.125 * i, 0.9 if i % 4 == 0 else 0.7)
        k.put(y, r_note(k, hz(nm) / 2.0, 0.2, "soft", decay=0.05), 0.02 + 0.125 * i, 0.2)
    return k.rev(y, 0.4, 0.12, hi=8000.0)


@sound("phone_beep", 0.15, level=-2.5)
def phone_beep(k):
    """Keypad beep (dual tone 852 + 1477 Hz)."""
    y = k.zeros()
    e = k.sub(0.11)
    k.put(y, (e.sine(852.0) + e.sine(1477.0)) * e.pts([(0, 0), (0.004, 1.0), (0.1, 1.0), (0.11, 0.0)]), 0.003)
    return y


@sound("camera_shutter", 0.3, level=-2.0)
def camera_shutter(k):
    """Mirror slap + shutter 'click-clack', then a short film-advance whir."""
    y = k.zeros()
    k.put(y, r_click(k, 2600.0, 0.003, body=0.6, body_f=300.0, metal=0.5), 0.004, 1.0)
    k.put(y, r_click(k, 3400.0, 0.0022, body=0.3, body_f=380.0, metal=0.4), 0.062, 0.8)
    e = k.sub(0.12)
    wh = e.f(e.harm(e.pts([(0, 700.0), (0.12, 950.0)]), [1.0, 0.4, 0.25]), LP(4000.0, 2)) * (0.6 + 0.4 * np.abs(e.lfon(40.0)))
    wh *= e.pts([(0, 0), (0.01, 1.0), (0.11, 0.8), (0.12, 0.0)], smooth=True)
    k.put(y, wh / peak_of(wh), 0.12, 0.2)
    return k.rev(y, 0.15, 0.06, hi=8000.0)


@sound("pickup_item", 0.4, level=-2.0)
def pickup_item(k):
    y = k.zeros()
    k.put(y, r_note(k, hz("B5"), 0.25, "bell", decay=0.07), 0.004, 0.8)
    k.put(y, r_note(k, hz("E6"), 0.3, "bell", decay=0.1), 0.06, 1.0)
    k.put(y, r_sparkle(k, 0.28, 5), 0.07, 0.15)
    return ui_finish(k, y, 0.3, 0.1)


@sound("pickup_health", 0.5, level=-2.0)
def pickup_health(k):
    """Warm healing swell: soft A major arpeggio with a shimmering glass top."""
    y = k.zeros()
    for i, nm in enumerate(("A5", "C#6", "E6")):
        k.put(y, r_note(k, hz(nm), 0.4, "soft", attack=0.02, decay=0.15, vib=0.004), 0.004 + 0.06 * i, 0.7)
    k.put(y, r_note(k, hz("A6"), 0.35, "glass", attack=0.01, decay=0.12, bright=0.6), 0.12, 0.35)
    k.put(y, r_sparkle(k, 0.35, 8, 3000.0, 6000.0), 0.08, 0.15)
    return ui_finish(k, y, 0.35, 0.12)


@sound("pickup_weapon", 0.4)
def pickup_weapon(k):
    """Metallic 'chk-chk' plus a low confirm tone."""
    y = k.zeros()
    k.put(y, r_click(k, 1700.0, 0.004, body=0.8, body_f=200.0, metal=0.6), 0.004, 1.0)
    k.put(y, r_click(k, 2300.0, 0.003, body=0.6, body_f=240.0, metal=0.7), 0.075, 0.9)
    k.put(y, r_note(k, hz("A3"), 0.22, "square", attack=0.004, decay=0.08, bright=0.6), 0.09, 0.4)
    return ui_finish(k, y, 0.25, 0.08)


@sound("neon_buzz_loop", 3.0, loop=True)
def neon_buzz_loop(k):
    """Neon sign: 120 Hz ballast buzz rich in harmonics, transformer hum, flicker sputters."""
    buzz = k.f(k.pulse(120.0, 0.12), HP(150.0, 2), LP(4000.0, 2))
    hum = k.sine(120.0) + 0.5 * k.sine(240.0)
    y = buzz / rms_of(buzz) + 0.8 * hum / rms_of(hum)
    y *= 0.9 + 0.1 * k.lfon(2.0)
    for at in (0.7, 2.15):
        e = k.sub(0.18)
        dip = 1.0 - 0.7 * (np.abs(e.lfon(40.0)) > 0.5) * np.sin(np.pi * e.t() / 0.18)
        seg = y[int(at * k.sr):int(at * k.sr) + e.n].copy()
        y[int(at * k.sr):int(at * k.sr) + len(seg)] = seg * e.f(dip, LP(300.0, 2))[: len(seg)]
        k.put(y, e.f(e.sparks(150.0, power=2.0), HP(2500.0, 2), LP(9000.0, 2)) * 6.0, at)
    y += 0.05 * k.bnoise(3000.0, 9000.0)
    return y


@sound("shark_bite", 0.5)
def shark_bite(k):
    """Surge and thrash in the water, a crunching bite, bubbles."""
    y = k.zeros()
    e = k.sub(0.3)
    surge = e.f(e.white(), BP(900.0, 0.6)) * e.pts([(0, 0), (0.06, 1.0), (0.3, 0.0)], smooth=True)
    k.put(y, surge / peak_of(surge), 0.0, 0.6)
    k.put(y, r_thud(k, 95.0, 50.0, 0.05, lp=500.0), 0.08, 1.0)
    e = k.sub(0.1)
    cr = e.f(e.sparks(2500.0, power=2.0) * e.exp(0.03, a=0.002), BANK([(450.0, 3.0, 1.0), (900.0, 4.0, 0.7), (1600.0, 5.0, 0.5)]))
    k.put(y, cr / (peak_of(cr) + 1e-9), 0.085, 0.9)
    k.put(y, r_bubbles(k, 30, 250.0, 1500.0, 0.35), 0.12, 0.4)
    return r_tail(k, y, 0.25, 0.08, (), lp=4000.0)


@sound("sizzle", 0.6)
def sizzle(k):
    """Frying / burning: dense fizz with louder pops and steam hiss."""
    y = k.zeros()
    e = k.sub(0.58)
    env = e.pts([(0, 0), (0.015, 1.0), (0.2, 0.75), (0.58, 0.0)], smooth=True)
    fizz = e.f(e.sparks(5000.0, power=2.0), HP(2500.0, 2), LP(10000.0, 2)) * (0.6 + 0.4 * np.abs(e.lfon(30.0)))
    steam = e.f(e.white(), HP(3000.0, 2), LP(9000.0, 2))
    s = (fizz / rms_of(fizz) + 0.4 * steam) * env
    k.put(y, s / peak_of(s), 0.003, 0.9)
    for _ in range(6):
        k.put(y, r_tick(k, k.u(1500.0, 4000.0), 0.001, 1.2), k.u(0.02, 0.4), k.u(0.2, 0.5))
    return y


# ----------------------------------------------------------------------------------------------
# 5f. RADIO  (original generative music: a tiny looping step sequencer + synthesised instruments)
# ----------------------------------------------------------------------------------------------
family("radio")


class Song:
    """Step sequencer on a looping stereo buffer: tempo grid with swing, named buses, side-chain
    trigger times.  Every event is mixed with wrap-around, so notes ringing past the loop end
    continue at its start and the whole song is seamless by construction."""

    def __init__(self, k, bpm, bars, swing=0.0, swing_unit=0.25):
        self.k, self.bpm, self.bars = k, float(bpm), int(bars)
        self.beat = 60.0 / bpm
        self.swing, self.unit = swing, swing_unit
        self.bus = {}
        self.hits = []

    def at(self, bar, beat=0.0):
        """Seconds of a grid position; odd multiples of the swing unit are pushed late."""
        b = bar * 4.0 + beat
        q = b / self.unit
        if self.swing and abs(q - round(q)) < 1e-6 and int(round(q)) % 2 == 1:
            b += self.swing * self.unit
        return b * self.beat

    def beats(self, n_beats):
        return n_beats * self.beat

    def add(self, bus, sig, t, gain=1.0, pan_=0.0):
        k = self.k
        buf = self.bus.setdefault(bus, np.zeros((k.n, 2)))
        st = sig if sig.ndim == 2 else pan(sig, pan_)
        put(buf, st, int(round(t * k.sr)), gain, wrap=True)

    def get(self, bus):
        return self.bus.get(bus, np.zeros((self.k.n, 2)))

    def duck(self, depth=0.5, release=0.22, attack=0.004, hold=0.02):
        return duck_env(self.k.n, self.k.sr, [t * self.k.sr for t in self.hits], depth, attack, hold, release, wrap=True)[:, None]


def song_master(k, y, drive=1.3, lp=14000.0, hp=30.0):
    """Gentle glue: low cut, soft saturation (level-normalised), top roll-off."""
    y = k.f(y, HP(hp, 2), LP(min(lp, 0.45 * k.sr), 2))
    p = peak_of(y) + 1e-12
    return k.sat(y / p, drive) * p


# ---- drum machine ----------------------------------------------------------------------------

def d_kick(k, f0=160.0, f1=48.0, tau=0.3, click=0.5, drive=1.6, sec=0.5, sweep_tau=0.03):
    e = k.sub(sec)
    y = e.thump(f0, f1, sweep_tau, tau, attack=0.0008) + click * e.f(e.burst(0.0015), HP(1800.0, 2))
    y = e.sat(y / (peak_of(y) + 1e-12), drive)
    return fade(y, e.sr, 0.0, 0.02) / (peak_of(y) + 1e-12)


def d_snare(k, tone=185.0, tau=0.14, snap=1.0, body=0.7, sec=0.35, lp=9000.0):
    e = k.sub(sec)
    b = e.sine(tone) * e.exp(0.05, a=0.001) + 0.6 * e.sine(tone * 1.78) * e.exp(0.03, a=0.001)
    nz = e.f(e.white(), HP(1200.0, 2), LP(min(lp, 0.45 * e.sr), 2)) * e.exp(tau, a=0.0008)
    y = body * b + snap * nz / (peak_of(nz) + 1e-12)
    return fade(y, e.sr, 0.0, 0.03) / (peak_of(y) + 1e-12)


def d_gated_snare(k, sec=0.42):
    """80s gated-reverb snare: a big bright room abruptly gated after ~0.2 s."""
    s = d_snare(k, tone=200.0, tau=0.09, sec=sec)
    e = k.sub(sec)
    wet = convolve(s, make_ir(k.sr, k.rng, 1.8, hf=0.6, lo=300.0, hi=8000.0))
    y = s + 1.8 * wet / (peak_of(wet) + 1e-12) * e.pts([(0, 1.0), (0.19, 1.0), (0.24, 0.0)], smooth=True)
    return fade(y, e.sr, 0.0, 0.02) / (peak_of(y) + 1e-12)


HAT_RATIOS = (1.0, 1.4471, 1.617, 1.9265, 2.5028, 2.6637)


def d_hat(k, open_=False, sec=None, tone=0.45, decay=None):
    sec = sec or (0.34 if open_ else 0.08)
    e = k.sub(sec)
    m = sum(e.pulse(330.0 * r, 0.5) for r in HAT_RATIOS)
    x = e.f(tone * m / (peak_of(m) + 1e-12) + e.white() / 3.0, HP(6500.0, 2), LP(min(13000.0, 0.45 * e.sr), 2))
    y = x * e.exp(decay or (0.2 if open_ else 0.022), a=0.0005)
    return fade(y, e.sr, 0.0, 0.01) / (peak_of(y) + 1e-12)


def d_clap(k, sec=0.32):
    e = k.sub(sec)
    y = e.zeros()
    for dt, g in ((0.0, 0.8), (0.009, 0.9), (0.018, 1.0), (0.029, 0.9)):
        s = k.sub(0.03)
        e.put(y, s.f(s.burst(0.005), BP(1200.0, 1.2)), dt, g)
    tail = e.f(e.burst(0.09), BP(1300.0, 0.9))
    e.put(y, tail, 0.03, 0.8)
    return fade(y, e.sr, 0.0, 0.03) / (peak_of(y) + 1e-12)


def d_rim(k):
    e = k.sub(0.06)
    y = e.sine(1700.0) * e.exp(0.008, a=0.0003) + 0.6 * e.f(e.burst(0.004), BP(2500.0, 1.5))
    return y / (peak_of(y) + 1e-12)


def d_shaker(k):
    e = k.sub(0.07)
    y = e.f(e.white(), HP(5500.0, 2), LP(min(12000.0, 0.45 * e.sr), 2)) * e.pts([(0, 0), (0.012, 1.0), (0.06, 0.0)], smooth=True)
    return y / (peak_of(y) + 1e-12)


def d_tom(k, f):
    e = k.sub(0.4)
    y = e.thump(f * 1.3, f, 0.03, 0.16, attack=0.001) + 0.3 * e.f(e.burst(0.03), BP(f * 2.2, 1.5))
    return fade(y, e.sr, 0.0, 0.03) / (peak_of(y) + 1e-12)


def d_crash(k, sec=2.2):
    e = k.sub(sec)
    m = sum(e.pulse(470.0 * r, 0.5) for r in HAT_RATIOS)
    x = e.f(e.white() + 0.3 * m / (peak_of(m) + 1e-12), HP(3000.0, 2), LP(min(13000.0, 0.45 * e.sr), 2))
    y = x * e.exp(0.7, a=0.002)
    return fade(y, e.sr, 0.0, 0.3) / (peak_of(y) + 1e-12)


def d_ride(k, sec=1.0):
    e = k.sub(sec)
    modes = [(k.u(3000.0, 8000.0), k.u(0.6, 1.4), k.u(0.3, 1.0), k.u(0, 6.28)) for _ in range(12)]
    y = e.modal(modes) + 0.4 * e.f(e.white(), HP(5000.0, 2)) * e.exp(0.15, a=0.001)
    return fade(y, e.sr, 0.0, 0.2) / (peak_of(y) + 1e-12)


# ---- pitched instruments -----------------------------------------------------------------------

def i_bass(k, f, sec, cut=420.0, env=1600.0, decay=0.12, q=1.1, wave="saw", fund=0.5, drive=1.6, rel=0.03):
    """Analog-style synth bass: saw / pulse + fundamental sine through an enveloped low-pass."""
    e = k.sub(sec)
    t = e.t()
    x = e.saw(f) if wave == "saw" else e.pulse(f, 0.5)
    y = e.tvlp(x, np.minimum(cut + env * np.exp(-t / decay), 0.45 * e.sr), q=q) + fund * e.sine(f)
    y = e.sat(y / (peak_of(y) + 1e-12), drive)
    return y * env_adsr(e.n, e.sr, 0.003, 0.15, 0.8, rel) / (peak_of(y) + 1e-12)


def i_sub(k, f, sec, rel=0.06):
    """Round sub bass (sine + a little 2nd harmonic), soft attack."""
    e = k.sub(sec)
    y = e.sine(f) + 0.18 * e.sine(2.0 * f) + 0.06 * e.sine(3.0 * f)
    return y * env_adsr(e.n, e.sr, 0.008, 0.3, 0.85, rel) / 1.25


def i_pad(k, freqs, sec, cut=2200.0, attack=0.25, release=0.6, voices=5, detune=0.012, soft=0.0, hp=110.0):
    """Stereo supersaw (or, with soft -> 1, triangle) chord pad with a slow ADSR."""
    e = k.sub(sec)
    y = np.zeros((e.n, 2))
    for f in freqs:
        if soft < 1.0:
            y += (1.0 - soft) * e.supersaw(f, voices=voices, detune=detune, stereo=True)
        if soft > 0.0:
            y += soft * np.stack([e.tri(f * 0.998), e.tri(f * 1.002)], axis=1) * 1.6
    y = e.f(y, HP(hp, 2), LP(cut, 2))
    return y * env_adsr(e.n, e.sr, attack, 0.6, 0.85, release)[:, None] / (peak_of(y) + 1e-12)


def i_pluck(k, f, sec=0.24, cut=2800.0, decay=0.09, pw=0.3):
    """Arp pluck: narrow pulse through a snapping low-pass."""
    e = k.sub(sec)
    t = e.t()
    y = e.tvlp(e.pulse(f, pw), np.minimum(300.0 + cut * np.exp(-t / 0.06), 0.45 * e.sr), q=1.0) * e.exp(decay, a=0.0015)
    return fade(y, e.sr, 0.0, 0.02) / (peak_of(y) + 1e-12)


def i_lead(k, f, sec, glide_from=None, cut=3000.0, vib=0.007, soft=0.0):
    """Mono lead: saws + pulse (or a soft sine 'flute' with soft=1), glide from the previous note,
    delayed vibrato."""
    e = k.sub(sec)
    t = e.t()
    fr = np.full(e.n, float(f)) if glide_from is None else f + (glide_from - f) * np.exp(-t / 0.04)
    fr = fr * (1.0 + vib * np.sin(TAU * 5.2 * t) * np.clip((t - 0.18) / 0.2, 0.0, 1.0))
    if soft >= 1.0:
        y = e.sine(fr) + 0.12 * e.sine(2.0 * fr) + 0.04 * e.f(e.white(), BP(f * 2.0, 2.0)) * 3.0
    else:
        x = 0.6 * e.saw(fr) + 0.4 * e.pulse(fr, 0.45) + 0.3 * e.saw(fr * 1.005)
        y = e.tvlp(x, np.minimum(600.0 + cut * (0.6 + 0.4 * np.exp(-t / 0.3)), 0.45 * e.sr), q=0.9)
    return y * env_adsr(e.n, e.sr, 0.012, 0.2, 0.8, min(0.08, sec * 0.4)) / (peak_of(y) + 1e-12)


def i_epiano(k, f, sec, vel=0.8, decay=1.3, bright=1.0):
    """FM electric piano: 1:1 body with a velocity-dependent bark + 14:1 tine ping."""
    e = k.sub(sec)
    t = e.t()
    idx = bright * ((0.6 + 1.2 * vel) * np.exp(-t / 0.3) + 0.45)
    y = e.fm(f, f, idx) + 0.3 * vel * bright * e.fm(f, 14.0 * f, 0.7 * np.exp(-t / 0.012))
    y *= np.exp(-t / decay) * np.minimum(1.0, t / 0.002)
    return fade(y, e.sr, 0.0, min(0.08, sec * 0.3)) / (peak_of(y) + 1e-12)


def i_guitar(k, f, sec, t60=1.4, bright=3500.0, pick=0.18, drive=0.0):
    """Karplus-Strong electric guitar string (optionally overdriven)."""
    n = int(round(sec * k.sr))
    y = karplus_strong(f, n, k.sr, k.rng, t60=t60, fd=2600.0, pick=pick, bright=bright)
    if drive:
        y = saturate(y, drive) / math.tanh(drive)
    return fade(y, k.sr, 0.0, min(0.05, sec * 0.3))


def i_strum(k, freqs, sec, spread=0.012, **kw):
    e = k.sub(sec + spread * len(freqs))
    y = e.zeros()
    for i, f in enumerate(freqs):
        e.put(y, i_guitar(k, f, sec, **kw), i * spread * k.u(0.8, 1.2), k.u(0.8, 1.0))
    return y / (peak_of(y) + 1e-12)


def chord_hz(names):
    return [hz(nm) for nm in names]


# ---- stations ------------------------------------------------------------------------------

NEON_BPM, NEON_BARS = 100.0, 16
NEON_CHORDS = [(["A3", "C4", "E4"], "A1", ["A4", "C5", "E5", "A5"]), (["F3", "A3", "C4"], "F1", ["F4", "A4", "C5", "F5"]),
               (["G3", "C4", "E4"], "C2", ["G4", "C5", "E5", "G5"]), (["G3", "B3", "D4"], "G1", ["G4", "B4", "D5", "G5"])]
NEON_MEL_A = [[("E5", 0, 1.5), ("D5", 1.5, 0.5), ("C5", 2, 1), ("D5", 3, 1)], [("C5", 0, 1.5), ("A4", 1.5, 0.5), ("C5", 2, 2)],
              [("E5", 0, 1), ("G5", 1, 1), ("E5", 2, 1), ("D5", 3, 1)], [("D5", 0, 2), ("B4", 2, 1), ("D5", 3, 1)]]
NEON_MEL_B = [[("A5", 0, 2), ("G5", 2, 1), ("E5", 3, 1)], [("F5", 0, 2), ("E5", 2, 1), ("C5", 3, 1)],
              [("E5", 0, 1.5), ("G5", 1.5, 0.5), ("C6", 2, 2)], [("B5", 0, 2), ("D6", 2, 1), ("B5", 3, 1)]]
NEON_MEL_A2 = NEON_MEL_A[:3] + [[("D5", 0, 1), ("B4", 1, 1), ("G4", 2, 2)]]


def play_melody(s, bars_notes, bar0, bus, gain=1.0, pan_=0.0, **kw):
    """Monophonic line with glides: bars_notes = [[(note, beat, beats), ...] per bar]."""
    prev = None
    for bi, notes in enumerate(bars_notes):
        for nm, b, d in notes:
            f = hz(nm)
            sec = s.beats(d) * 0.95 + 0.06
            s.add(bus, i_lead(s.k, f, sec, glide_from=prev, **kw), s.at(bar0 + bi, b), gain, pan_)
            prev = f


@sound("radio_neon", NEON_BARS * 4 * 60.0 / NEON_BPM, loop=True, ch=2, level=-15.0)
def radio_neon(k):
    """NEON FM - synthwave, 100 bpm, A minor (Am F C G): driving octave bass, ping-pong arps,
    supersaw pads, gated-reverb snare, a gliding saw lead; side-chained to the kick."""
    s = Song(k, NEON_BPM, NEON_BARS)
    kick, snare = d_kick(k, 150.0, 46.0, 0.28, 0.5, 1.8), d_gated_snare(k)
    hat_c, hat_o, crash = d_hat(k), d_hat(k, True), d_crash(k)
    order = [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 2, 1, 3]
    for bar in range(NEON_BARS):
        pad, root, arp = NEON_CHORDS[bar % 4]
        brk = 8 <= bar < 11
        s.add("pad", i_pad(k, chord_hz(pad), s.beats(4) + 0.5, cut=1500.0 if brk else 2400.0, attack=0.2, release=0.5), s.at(bar), 0.55)
        for i in range(16):
            s.add("arp", i_pluck(k, hz(arp[order[i]]), cut=1400.0 if brk else 3200.0), s.at(bar, i * 0.25), 0.3 if i % 4 else 0.38,
                  0.35 if i % 2 else -0.35)
        if brk:
            s.add("bass", i_bass(k, hz(root), s.beats(4) - 0.05, cut=250.0, env=500.0, decay=0.5), s.at(bar), 0.8)
        else:
            for i in range(8):
                f = hz(root) * (2.0 if i % 2 else 1.0)
                s.add("bass", i_bass(k, f, s.beats(0.5) - 0.02, cut=380.0, env=1500.0), s.at(bar, i * 0.5), 0.85 if i % 2 == 0 else 0.7)
        for b in ((0.0,) if brk else (0.0, 2.0)) + ((3.5,) if bar % 2 == 1 and not brk else ()):
            s.add("drums", kick, s.at(bar, b), 1.0)
            s.hits.append(s.at(bar, b))
        for b in ((3.0,) if brk else (1.0, 3.0)):
            s.add("drums", snare, s.at(bar, b), 0.75)
        if not brk:
            for i in range(8):
                s.add("drums", hat_c, s.at(bar, i * 0.5), 0.22 if i % 2 == 0 else 0.32, 0.25)
            if bar % 2 == 1:
                s.add("drums", hat_o, s.at(bar, 3.5), 0.25, 0.25)
        if bar in (0, 12):
            s.add("drums", crash, s.at(bar), 0.4, -0.2)
        if bar == 11:
            for i, f in enumerate((220.0, 220.0, 185.0, 185.0, 155.0, 155.0, 125.0, 125.0)):
                s.add("drums", d_tom(k, f), s.at(bar, 2.0 + 0.25 * i), 0.6, 0.4 - 0.1 * i)
    play_melody(s, NEON_MEL_A, 4, "lead", 0.42)
    play_melody(s, NEON_MEL_B, 8, "lead", 0.34, cut=2200.0)
    play_melody(s, NEON_MEL_A2, 12, "lead", 0.42)
    dk = s.duck(0.55, 0.25)
    music = (s.get("pad") + s.get("bass")) * dk
    arp = s.get("arp") * dk
    arp = arp + pingpong(arp.mean(axis=1), k.sr, s.beats(0.75), 0.4, 0.5, 3000.0, wrap=True)
    lead = s.get("lead")
    lead = lead + pingpong(lead.mean(axis=1), k.sr, s.beats(0.75), 0.35, 0.35, 3500.0, wrap=True)
    y = music + 0.8 * arp + lead + s.get("drums")
    y = y + k.rev(0.6 * s.get("pad") * dk + 0.5 * lead + 0.3 * arp, 2.2, 0.45, 0.0, hi=7000.0, lo=200.0)
    return song_master(k, y, 1.35)


LOWTIDE_BPM, LOWTIDE_BARS = 78.0, 12
LOWTIDE_CHORDS = [(["F3", "A3", "C4", "E4"], "D2", "A2"), (["F3", "B3", "E4", "A4"], "G1", "D2"),
                  (["E3", "G3", "B3", "D4"], "C2", "G2"), (["G3", "C#4", "E4", "A#4"], "A1", "E2")]
LOWTIDE_MEL = [[("A4", 0, 1.5), ("G4", 1.5, 0.5), ("F4", 2, 2)], [("E4", 0, 1), ("G4", 1, 1), ("D4", 2, 2)],
               [("E4", 0, 1.5), ("G4", 1.5, 0.5), ("C5", 2, 1), ("B4", 3, 1)], [("A4", 0, 2.5), ("C#5", 2.5, 1.5)],
               [("D5", 0, 1), ("C5", 1, 0.5), ("A4", 1.5, 2.5)], [("B4", 0, 1), ("A4", 1, 1), ("G4", 2, 2)],
               [("E4", 0, 2), ("G4", 2, 1), ("B4", 3, 1)], [("A4", 0, 3), ("E4", 3, 1)]]


@sound("radio_lowtide", LOWTIDE_BARS * 4 * 60.0 / LOWTIDE_BPM, loop=True, ch=2, level=-15.5)
def radio_lowtide(k):
    """LOW TIDE - lo-fi hip-hop, 78 bpm, swung 16ths, Dm9 G13 Cmaj9 A7b9: dusty boom-bap kit, mellow
    FM electric piano with tape wow, round sub bass, a soft flute-ish line, vinyl crackle and hiss."""
    s = Song(k, LOWTIDE_BPM, LOWTIDE_BARS, swing=0.3, swing_unit=0.25)
    kick = d_kick(k, 120.0, 50.0, 0.25, 0.3, 2.0)
    snare = d_snare(k, 175.0, 0.16, 0.9, 0.8, lp=8000.0)
    hat = d_hat(k, decay=0.03)
    shaker = d_shaker(k)
    for bar in range(LOWTIDE_BARS):
        ch, root, fifth = LOWTIDE_CHORDS[bar % 4]
        vel = k.u(0.65, 0.9)
        for b, d, v in ((0.0, 1.6, vel), (2.5, 1.3, vel * 0.7)):
            for i, nm in enumerate(ch):
                s.add("keys", i_epiano(k, hz(nm), s.beats(d) + 0.3, v, bright=1.7), s.at(bar, b) + 0.012 * i + k.u(0.0, 0.008),
                      0.45 * v, -0.45 + 0.3 * i)
        s.add("bass", i_sub(k, hz(root), s.beats(1.6)), s.at(bar), 0.6)
        s.add("bass", i_sub(k, hz(fifth), s.beats(0.7)), s.at(bar, 2.75), 0.48)
        s.add("bass", i_sub(k, hz(root) * 2.0 ** (-2 / 12.0), s.beats(0.4)), s.at(bar, 3.5), 0.38)
        for b in (0.0, 1.75, 2.5):
            s.add("drums", kick, s.at(bar, b), 0.75 if b == 0.0 else 0.55)
            s.hits.append(s.at(bar, b))
        for b in (1.0, 3.0):
            s.add("drums", snare, s.at(bar, b) + 0.014, 1.5)
        for i in range(16):
            if i % 2 == 0:
                s.add("drums", hat, s.at(bar, i * 0.25), k.u(0.4, 0.55), 0.3)
            else:
                s.add("drums", hat, s.at(bar, i * 0.25), k.u(0.1, 0.2), 0.3)
            s.add("drums", shaker, s.at(bar, i * 0.25), k.u(0.05, 0.1), -0.45)
    for i in range(8):
        play_melody(s, [LOWTIDE_MEL[i]], 4 + i, "lead", 0.3, 0.15, soft=1.0, vib=0.009)
    keys = s.get("keys")
    wow = (0.004 + 0.0015 * k.lfo(0.27) + 0.0004 * k.lfon(6.0)) * k.sr
    keys = np.stack([vdelay(keys[:, c], wow, wrap=True) for c in range(2)], axis=1) * (0.92 + 0.08 * k.lfo(3.1))[:, None]
    dk = s.duck(0.3, 0.2)
    drums = k.f(s.get("drums"), LP(9000.0, 2))
    drums = np.stack([bitcrush(drums[:, c], 10, 1) for c in range(2)], axis=1)
    y = keys * dk + s.get("bass") * dk + drums + s.get("lead")
    y = y + k.rev(0.6 * keys + 0.6 * s.get("lead") + 0.15 * drums, 1.6, 0.35, 0.0, hi=5000.0, lo=200.0)
    crackle = k.f(k.sparks(12.0, power=3.0), BP(2500.0, 0.8))
    hiss = k.cnoise(-1.0, lo=500.0, hi=8000.0)
    y = y + pan(0.12 * peak_of(y) * crackle / (peak_of(crackle) + 1e-12) + 0.02 * rms_of(y) * hiss, 0.0)
    return song_master(k, k.f(y, LP(8500.0, 2)), 1.6)


PULSE_BPM, PULSE_BARS = 124.0, 20
PULSE_CHORDS = [(["C4", "D#4", "G4", "A#4"], "C2"), (["C4", "D#4", "G4", "A#4"], "C2"), (["G#3", "C4", "D#4", "G4"], "G#1"),
                (["A#3", "D4", "F4", "G#4"], "A#1")]


@sound("radio_pulse", PULSE_BARS * 4 * 60.0 / PULSE_BPM, loop=True, ch=2, level=-14.5)
def radio_pulse(k):
    """PULSE 124 - house / techno, C minor (Cm7 Cm7 Abmaj7 Bb7): four-on-the-floor, off-beat open hats,
    claps, rolling off-beat bass, filtered chord stabs on a loop-long filter sweep, a breakdown
    riser; heavy side-chain."""
    s = Song(k, PULSE_BPM, PULSE_BARS)
    kick = d_kick(k, 170.0, 50.0, 0.22, 0.6, 2.2, 0.4)
    clap, hat_o, hat_c, shaker, rim, ride = d_clap(k), d_hat(k, True, decay=0.09), d_hat(k, decay=0.018), d_shaker(k), d_rim(k), d_ride(k)
    for bar in range(PULSE_BARS):
        ch, root = PULSE_CHORDS[bar % 4]
        phrase = bar // 4
        brk = bar in (10, 11)
        if not brk:
            for b in range(4):
                s.add("drums", kick, s.at(bar, b), 1.0)
                s.hits.append(s.at(bar, b))
        for b in (1.0, 3.0):
            s.add("drums", clap, s.at(bar, b), 0.55 if not brk else 0.35, 0.05)
        for b in (0.5, 1.5, 2.5, 3.5):
            s.add("drums", hat_o, s.at(bar, b), 0.36, 0.3)
        for i in range(16):
            if i % 4 != 2:
                s.add("drums", hat_c, s.at(bar, i * 0.25), 0.14 + 0.1 * (i % 2), -0.3)
            s.add("drums", shaker, s.at(bar, i * 0.25), 0.06 + 0.05 * (i % 4 == 2), 0.5)
        if phrase == 2 and not brk:
            for b in range(4):
                s.add("drums", ride, s.at(bar, b), 0.12, -0.3)
        if phrase == 4:
            for i in (3, 10, 13):
                s.add("drums", rim, s.at(bar, i * 0.25), 0.25, 0.3)
        for b in (0.5, 1.5, 2.5, 3.5):
            s.add("bass", i_bass(k, hz(root), s.beats(0.4), cut=300.0 if not brk else 200.0, env=1100.0 if not brk else 400.0,
                                 decay=0.08, wave="pulse", fund=0.7), s.at(bar, b), 0.8)
        if not brk:
            for b in (1.75, 3.75):
                s.add("bass", i_bass(k, hz(root) * 2.0, s.beats(0.2), cut=300.0, env=900.0, decay=0.05, wave="pulse", fund=0.5),
                      s.at(bar, b), 0.5)
        if phrase in (1, 2, 3):
            for i in (3, 6, 11):
                stab = sum(i_pluck(k, hz(nm), 0.22, cut=2600.0, decay=0.1, pw=0.5) for nm in ch)
                s.add("stab", stab / 4.0, s.at(bar, i * 0.25), 0.8, 0.2 if i != 6 else -0.2)
        if phrase in (2, 3):
            s.add("pad", i_pad(k, chord_hz(ch), s.beats(4) + 0.4, cut=1800.0, attack=0.3, release=0.4, soft=0.5), s.at(bar), 0.3)
    e = k.sub(s.beats(8))
    riser = e.tvbp(e.white(), e.pts([(0, 400.0), (e.dur, 6000.0)]), 2.0) * e.pts([(0, 0), (e.dur * 0.9, 1.0), (e.dur, 0.0)], smooth=True)
    s.add("fx", riser / (peak_of(riser) + 1e-12), s.at(10), 0.25)
    s.add("drums", d_crash(k), s.at(12), 0.35)
    s.add("drums", d_crash(k), s.at(0), 0.25)
    dk = s.duck(0.65, 0.18)
    lfo = 0.5 - 0.5 * np.cos(TAU * k.t() / k.dur)
    stab = k.tvlp(s.get("stab"), 700.0 + 3800.0 * lfo, q=1.6)
    stab = stab + pingpong(stab.mean(axis=1), k.sr, s.beats(0.75), 0.35, 0.4, 3000.0, wrap=True)
    y = s.get("drums") + (s.get("bass") + stab + s.get("pad")) * dk + s.get("fx")
    y = y + k.rev(0.5 * stab + 0.5 * s.get("pad") + 0.08 * s.get("drums") + 0.5 * s.get("fx"), 1.4, 0.35, 0.0, hi=7000.0, lo=250.0)
    return song_master(k, y, 1.4)


DUSTY_BPM, DUSTY_BARS = 92.0, 16
DUSTY_FORM = ["E", "E", "E", "E", "A", "A", "E", "E", "B", "A", "E", "B", "E", "D", "C", "B"]
DUSTY_ROOT = {"E": "E2", "A": "A2", "B": "B2", "D": "D3", "C": "C3"}
DUSTY_STRUM = {"E": ["E3", "G#3", "B3", "E4"], "D": ["D3", "F#3", "A3", "D4"], "C": ["C3", "E3", "G3", "C4"], "B": ["B2", "D#3", "F#3", "B3"]}
DUSTY_LICKS = {8: [("B4", 0, 0.5), ("D5", 0.5, 0.5), ("E5", 1, 1.5), ("D5", 2.5, 0.5), ("B4", 3, 1)],
               9: [("A4", 0, 1), ("G4", 1, 0.5), ("E4", 1.5, 1.5), ("G4", 3, 1)],
               10: [("E4", 0, 0.5), ("G4", 0.5, 0.5), ("A4", 1, 0.5), ("B4", 1.5, 2.5)],
               11: [("D5", 0, 1), ("B4", 1, 1), ("A4", 2, 1), ("F#4", 3, 1)]}
DUSTY_SURF = {12: [("B4", 0, 2), ("G#4", 2, 2)], 13: [("A4", 0, 2), ("F#4", 2, 2)], 14: [("G4", 0, 2), ("E4", 2, 2)],
              15: [("F#4", 0, 2), ("D#4", 2, 2)]}


@sound("radio_dusty", DUSTY_BARS * 4 * 60.0 / DUSTY_BPM, loop=True, ch=2, level=-15.5)
def radio_dusty(k):
    """DUSTY ROADS - surf / blues-rock shuffle, 92 bpm, E: a 12-bar blues on a crunchy Karplus-Strong
    boogie riff, walking bass, pentatonic licks, then a four-bar surf break with tremolo-picked
    lead drenched in spring reverb (E D C B) that turns around into the top."""
    s = Song(k, DUSTY_BPM, DUSTY_BARS, swing=1.0 / 3.0, swing_unit=0.5)
    kick = d_kick(k, 110.0, 55.0, 0.2, 0.4, 1.5)
    snare = d_snare(k, 195.0, 0.13, 1.0, 0.7)
    ride = d_ride(k, 0.8)
    crash = d_crash(k, 2.0)
    boogie = [7, 7, 9, 9, 10, 10, 9, 9]                        # 5th, 6th, b7th above the root in shuffle 8ths
    walk = [0, 4, 7, 9, 10, 9, 7, 4]
    for bar, chn in enumerate(DUSTY_FORM):
        r = hz(DUSTY_ROOT[chn])
        surf = bar >= 12
        if not surf:
            for i in range(8):
                fr = [r, r * 2.0 ** (boogie[i] / 12.0)]
                s.add("gtr", i_strum(k, fr, s.beats(0.5) + 0.05, 0.006, t60=0.32, bright=2600.0, pick=0.12, drive=2.0),
                      s.at(bar, i * 0.5), 0.5 if i % 2 == 0 else 0.4, -0.6)
                s.add("bass", i_guitar(k, r * 0.5 * 2.0 ** (walk[i] / 12.0), s.beats(0.5) + 0.05, t60=0.7, bright=900.0, pick=0.3),
                      s.at(bar, i * 0.5), 0.6)
        else:
            for b, d in ((0.0, 2.4), (2.5, 1.4)):
                s.add("gtr", i_strum(k, chord_hz(DUSTY_STRUM[chn]), s.beats(d), 0.014, t60=1.6, bright=3200.0, drive=1.2),
                      s.at(bar, b), 0.45, -0.6)
            for i, st in enumerate((0, 0, 7, 0)):
                s.add("bass", i_guitar(k, r * 0.5 * 2.0 ** (st / 12.0), s.beats(1.0) + 0.05, t60=0.9, bright=900.0, pick=0.3),
                      s.at(bar, i), 0.6)
        for b in (0.0, 2.0):
            s.add("drums", kick, s.at(bar, b), 0.9)
        for b in (1.0, 3.0):
            s.add("drums", snare, s.at(bar, b), 0.6)
        for i in range(8):
            s.add("drums", ride, s.at(bar, i * 0.5), 0.16 if i % 2 == 0 else 0.1, 0.3)
            if i % 2 == 1 and k.rng.random() < 0.35:
                s.add("drums", snare, s.at(bar, i * 0.5), 0.1)
        if bar in (0, 12):
            s.add("drums", crash, s.at(bar), 0.3, -0.25)
        if bar == 11:
            for j in range(6):
                s.add("drums", snare, s.at(bar, 2.0) + j * s.beats(1.0 / 3.0), 0.25 + 0.06 * j)
        if bar == 15:
            for j, f in enumerate((200.0, 170.0, 140.0, 120.0)):
                s.add("drums", d_tom(k, f), s.at(bar, 2.0 + 0.5 * j), 0.5, 0.3 - 0.2 * j)
    for bar, notes in DUSTY_LICKS.items():
        for nm, b, d in notes:
            s.add("lead", i_guitar(k, hz(nm), s.beats(d) + 0.15, t60=1.2, bright=4200.0, pick=0.15, drive=1.6), s.at(bar, b), 0.4, 0.55)
    step = s.beats(0.125)
    for bar, notes in DUSTY_SURF.items():
        for nm, b, d in notes:
            t0 = s.at(bar, b)
            for j in range(int(round(d / 0.125))):
                f = hz(nm) * (1.0 + 0.004 * math.sin(TAU * 5.0 * j * step))
                s.add("lead", i_guitar(k, f, 0.2, t60=0.5, bright=4500.0, pick=0.1, drive=1.3), t0 + j * step, 0.3 * k.u(0.8, 1.0), 0.55)
    gtr = s.get("gtr") + s.get("lead")
    gtr = gtr + 0.55 * k.f(gtr, SPRING(2.4), LP(5000.0, 2))
    y = gtr + s.get("bass") + s.get("drums")
    y = y + k.rev(0.35 * gtr + 0.25 * s.get("drums"), 1.2, 0.3, 0.0, hi=6000.0, lo=200.0)
    return song_master(k, y, 1.5, lp=11000.0)


AMBIENT_BPM, AMBIENT_BARS = 60.0, 10
AMBIENT_CHORDS = [["D3", "A3", "E4", "F#4", "C#5"], ["B2", "F#3", "A3", "D4", "E4"], ["G2", "D3", "F#3", "A3", "C#4"],
                  ["A2", "E3", "F#3", "B3", "E4"]]
AMBIENT_BELLS = ["D5", "E5", "F#5", "A5", "B5", "D6", "E6", "F#6", "A6"]


@sound("radio_ambient", AMBIENT_BARS * 4 * 60.0 / AMBIENT_BPM, loop=True, ch=2, level=-17.0)
def radio_ambient(k):
    """DRIFT - beatless ambient, D major: four slow overlapping chord pads (Dmaj9 Bm11 Gmaj9 A6/9sus)
    over a breathing drone, sparse pentatonic FM bells in long ping-pong echoes and a huge reverb."""
    s = Song(k, AMBIENT_BPM, AMBIENT_BARS)
    for i, ch in enumerate(AMBIENT_CHORDS):
        s.add("pad", i_pad(k, chord_hz(ch), 14.0, cut=1300.0, attack=3.5, release=4.5, voices=3, detune=0.006, soft=0.7, hp=80.0),
              i * 10.0 - 1.5, 0.6)
    drone = k.sine(hz("D2")) + 0.35 * k.sine(hz("A2")) + 0.12 * k.sine(hz("D3"))
    s.add("drone", drone * (0.75 + 0.25 * k.lfo(1.0 / 20.0)), 0.0, 0.22)
    t = 0.3
    while t < k.dur - 0.5:
        nm = AMBIENT_BELLS[int(k.rng.integers(0, len(AMBIENT_BELLS)))]
        s.add("bells", r_note(k, hz(nm), 3.2, "glass", attack=0.004, decay=1.1, bright=0.7), t, k.u(0.2, 0.42), k.u(-0.6, 0.6))
        t += k.u(1.2, 3.4)
    air = k.f(k.white(), HP(3000.0, 2), LP(9000.0, 2)) * (0.5 + 0.5 * k.lfon(0.15))
    pad = s.get("pad")
    pad = k.tvlp(pad, 900.0 + 700.0 * (0.5 + 0.5 * k.lfo(1.0 / 40.0)), q=0.8)
    bells = s.get("bells")
    bells = bells + pingpong(bells.mean(axis=1), k.sr, 0.75, 0.55, 0.6, 2500.0, wrap=True)
    y = pad + s.get("drone") + bells
    y = y + pan(air, 0.0) * 0.03 * rms_of(y) / (rms_of(air) + 1e-12)
    y = y + k.rev(0.8 * pad + 0.9 * bells, 4.5, 0.6, 0.0, hf=0.5, hi=6000.0, lo=150.0)
    return song_master(k, y, 1.1, lp=12000.0)


@sound("radio_static", 2.0, loop=True, level=-16.0, check=dict(aperiodic=True))
def radio_static(k):
    """Dial tuning noise: band-limited hiss with fading, crackle, wandering heterodyne whistles,
    fragments of garbled tones (no speech)."""
    hiss = k.bnoise(200.0, 7000.0) * (0.6 + 0.4 * np.abs(k.lfon(8.0)))
    crk = k.f(k.sparks(40.0, power=3.0), HP(1000.0, 2), LP(7000.0, 2))
    wh = k.sine(k.wander(1.5, 600.0, 2800.0)) * (0.5 + 0.5 * k.lfon(2.0)) ** 2
    y = hiss + 0.6 * crk / (rms_of(crk) + 1e-12) + 0.35 * wh
    for _ in range(6):
        e = k.sub(k.u(0.05, 0.2))
        f = k.u(300.0, 1500.0)
        frag = e.f(e.pulse(f, 0.3) * (0.5 + 0.5 * np.sign(e.lfon(30.0))), BP(f * 2.0, 1.5)) * np.sin(np.pi * e.t() / e.dur)
        k.put(y, frag, k.u(0.0, 2.0), 0.6)
    return k.f(y, LP(7500.0, 2))


def jingle_finish(k, y, rt=1.2, wet=0.3):
    y = to_stereo(y) if y.ndim == 1 else y
    return k.rev(y, rt, wet, stereo=True, hi=7000.0, lo=150.0)


@sound("radio_jingle_1", 2.0, sr=SR_LOOP, ch=2)
def radio_jingle_1(k):
    """NEON FM ident: rising A minor arp into a supersaw stab with a gated snare."""
    y = np.zeros((k.n, 2))
    step = 60.0 / 140.0 / 4.0
    for i, nm in enumerate(("A4", "C5", "E5", "A5", "C6", "E6")):
        put(y, pan(i_pluck(k, hz(nm), 0.3, cut=3500.0), 0.4 if i % 2 else -0.4), int(i * step * k.sr), 0.5)
    at = 6 * step
    put(y, i_pad(k, chord_hz(["A3", "C4", "E4", "A4"]), 1.3, cut=3000.0, attack=0.01, release=0.6), int(at * k.sr), 0.8)
    put(y, pan(d_gated_snare(k), 0.0), int(at * k.sr), 0.7)
    put(y, pan(d_kick(k, 150.0, 46.0, 0.28), 0.0), int(at * k.sr), 0.8)
    put(y, pan(i_bass(k, hz("A1"), 0.9, cut=400.0, env=1500.0, decay=0.2), 0.0), int(at * k.sr), 0.7)
    return jingle_finish(k, y, 1.3, 0.3)


@sound("radio_jingle_2", 2.2, sr=SR_LOOP, ch=2)
def radio_jingle_2(k):
    """LOW TIDE ident: two lazy electric-piano chords over a boom-bap, vinyl crackle."""
    y = np.zeros((k.n, 2))
    b = 60.0 / 78.0
    for at, ch in ((0.0, ["F3", "A3", "C4", "E4"]), (b, ["F3", "B3", "E4", "A4"])):
        for i, nm in enumerate(ch):
            put(y, pan(i_epiano(k, hz(nm), 1.15, 0.75, decay=0.55, bright=1.7), -0.45 + 0.3 * i), int((at + 0.015 * i) * k.sr), 0.42)
    put(y, pan(d_kick(k, 120.0, 50.0, 0.25, 0.3, 2.0), 0.0), 0, 0.8)
    put(y, pan(d_snare(k, 175.0, 0.16, 0.9, 0.8, lp=8000.0), 0.0), int(b * k.sr), 0.9)
    put(y, pan(i_sub(k, hz("D2"), b * 0.95), 0.0), 0, 0.7)
    put(y, pan(i_sub(k, hz("G1"), 0.8), 0.0), int(b * k.sr), 0.7)
    crackle = k.f(k.sparks(25.0, power=3.0), BP(2500.0, 0.8)) * k.pts([(0, 1.0), (1.6, 1.0), (2.1, 0.0)])
    y += pan(0.12 * peak_of(y) * crackle / (peak_of(crackle) + 1e-12), 0.0)
    return k.fade(jingle_finish(k, k.f(y, LP(8500.0, 2)), 1.0, 0.25), 0.0, 0.4)


@sound("radio_jingle_3", 1.6, sr=SR_LOOP, ch=2)
def radio_jingle_3(k):
    """PULSE 124 ident: kicks under a chord stab whose filter sweeps open, a clap, the final stab."""
    y = np.zeros((k.n, 2))
    b = 60.0 / 124.0
    kick = d_kick(k, 170.0, 50.0, 0.22, 0.6, 2.2, 0.4)
    for i in range(3):
        put(y, pan(kick, 0.0), int(i * b * k.sr), 0.9)
    put(y, pan(d_clap(k), 0.05), int(b * k.sr), 0.5)
    ch = ["C4", "D#4", "G4", "A#4"]
    for i, at in enumerate((0.5, 1.0, 1.5, 2.0)):
        st = sum(i_pluck(k, hz(nm), 0.25 if i < 3 else 0.6, cut=900.0 + 1200.0 * i, decay=0.1 if i < 3 else 0.3, pw=0.5) for nm in ch)
        put(y, pan(st / 4.0, 0.15), int(at * b * k.sr), 0.7 if i < 3 else 0.9)
    return jingle_finish(k, y, 1.0, 0.3)


@sound("radio_jingle_4", 2.0, sr=SR_LOOP, ch=2)
def radio_jingle_4(k):
    """DUSTY ROADS ident: tremolo-picked surf run E-D-B in spring reverb, then an E chord and a hit."""
    y = k.zeros()
    step = 60.0 / 92.0 / 8.0
    t = 0.0
    for nm, cnt in (("E4", 6), ("D4", 6), ("B3", 6)):
        for j in range(cnt):
            put(y, i_guitar(k, hz(nm), 0.2, t60=0.5, bright=4500.0, pick=0.1, drive=1.3), int(t * k.sr), 0.35)
            t += step
    put(y, i_strum(k, chord_hz(["E3", "G#3", "B3", "E4"]), 1.1, 0.012, t60=1.6, bright=3200.0, drive=1.2), int(t * k.sr), 0.8)
    put(y, d_kick(k, 110.0, 55.0, 0.2, 0.4, 1.5), int(t * k.sr), 0.6)
    put(y, d_crash(k, 0.9), int(t * k.sr), 0.25)
    y = y + 0.6 * k.f(y, SPRING(2.2), LP(5000.0, 2))
    return jingle_finish(k, k.fade(y, 0.0, 0.3), 0.9, 0.2)


@sound("radio_jingle_5", 2.5, sr=SR_LOOP, ch=2)
def radio_jingle_5(k):
    """DRIFT ident: a falling cascade of FM bells over a soft D major swell."""
    y = np.zeros((k.n, 2))
    put(y, i_pad(k, chord_hz(["D3", "A3", "F#4", "C#5"]), 2.3, cut=1400.0, attack=0.6, release=1.0, voices=3, soft=0.8), 0, 0.5)
    for i, nm in enumerate(("D6", "A5", "F#5", "E5", "D5")):
        put(y, pan(r_note(k, hz(nm), 1.6, "glass", decay=0.6, bright=0.7), 0.5 - 0.25 * i), int((0.05 + 0.16 * i) * k.sr), 0.5)
    return jingle_finish(k, k.fade(y, 0.0, 0.4), 2.0, 0.4)


# <<< SOUND DEFINITIONS END >>>

# ----------------------------------------------------------------------------------------------
# 6. FINALISATION, WAV I/O, MANIFEST, VERIFICATION, CLI
# ----------------------------------------------------------------------------------------------

def finalize_oneshot(x, sr, peak_db):
    """High-pass DC/subsonics, micro fade-in, fade to a digitally silent tail, peak-normalise."""
    x = np.array(x, dtype=float, copy=True)
    n = x.shape[0]
    x = filt(x, sr, HP(20.0, 2), tail=0.1)
    fi = max(2, int(0.0003 * sr))
    zt = int(0.006 * sr) + 1
    fo = max(8, min(int(0.012 * sr), n // 6))
    w_in = np.arange(fi) / fi
    w_out = 0.5 + 0.5 * np.cos(np.pi * (np.arange(fo) + 1) / fo)
    if x.ndim == 2:
        w_in, w_out = w_in[:, None], w_out[:, None]
    x[:fi] *= w_in
    x[n - zt - fo:n - zt] *= w_out
    x[n - zt:] = 0.0
    return norm_peak(x, peak_db)


def finalize_loop(x, sr, rms_db):
    """Remove DC/subsonics (circular), set RMS, keep peaks under the ceiling with a circular
    look-ahead limiter, rotate mono loops to a zero crossing."""
    x = np.array(x, dtype=float, copy=True)
    x = filt(x, sr, HP(20.0, 2), wrap=True)
    ceil_db = PEAK_CEIL_DB - 0.25
    for _ in range(6):
        x = norm_rms(x, rms_db)
        if db(peak_of(x)) <= ceil_db + 0.02:
            break
        x = limiter(x, sr, ceil_db, 0.006, wrap=True)
    if db(peak_of(x)) > ceil_db + 0.02:
        x = norm_peak(x, ceil_db)
    return loop_rotate_zero(x, 0.06 * sr) if x.ndim == 1 else loop_rotate_stereo(x, 0.06 * sr)


def render(name):
    """Synthesise one registered sound -> finished float array."""
    fn, o = REGISTRY[name]
    k = Kit(o["sr"], zlib.crc32(name.encode()) ^ MASTER_SEED, o["dur"], o["loop"])
    x = np.asarray(fn(k, **o["params"]), dtype=float)
    if o["ch"] == 2 and x.ndim == 1:
        x = to_stereo(x)
    if not np.all(np.isfinite(x)):
        raise FloatingPointError(f"{name}: NaN/Inf in output")
    return finalize_loop(x, o["sr"], o["level"]) if o["loop"] else finalize_oneshot(x, o["sr"], o["level"])


def write_wav(path, x, sr, loop=False):
    """16-bit PCM RIFF/WAVE.  Loops get one guard sample (= first sample) after the loop and a
    'smpl' chunk with the loop points [0, N)."""
    pcm = np.clip(np.round(np.asarray(x) * 32767.0), -32768, 32767).astype("<i2")
    nframes = pcm.shape[0]
    ch = 1 if pcm.ndim == 1 else pcm.shape[1]
    if loop:
        pcm = np.concatenate([pcm, pcm[:1]])
    raw = pcm.tobytes()
    chunks = struct.pack("<4sIHHIIHH", b"fmt ", 16, 1, ch, sr, sr * ch * 2, ch * 2, 16)
    chunks += struct.pack("<4sI", b"data", len(raw)) + raw
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(round(1e9 / sr)), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, nframes, 0, 0)
        chunks += struct.pack("<4sI", b"smpl", len(smpl)) + smpl
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(struct.pack("<4sI4s", b"RIFF", 4 + len(chunks), b"WAVE") + chunks)
    os.replace(tmp, path)


def read_wav(path):
    """-> (float array, sr, channels, loop_region or None, guard_ok). Uses the stdlib wave reader
    for the PCM data (independent check of the container) and a chunk scan for 'smpl'."""
    with wave.open(path, "rb") as w:
        ch, sw, sr, nf = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(nf)
    if sw != 2:
        raise ValueError(f"{path}: not 16-bit PCM")
    pcm = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if ch > 1:
        pcm = pcm.reshape(-1, ch)
    loop = None
    with open(path, "rb") as fh:
        blob = fh.read()
    pos = 12
    while pos + 8 <= len(blob):
        cid, size = struct.unpack("<4sI", blob[pos:pos + 8])
        if cid == b"smpl" and size >= 60:
            nloops = struct.unpack("<I", blob[pos + 8 + 28:pos + 8 + 32])[0]
            if nloops >= 1:
                _, typ, start, end = struct.unpack("<4I", blob[pos + 8 + 36:pos + 8 + 52])
                loop = (start, end)
        pos += 8 + size + (size & 1)
    guard_ok = True
    if loop is not None:
        guard_ok = pcm.shape[0] == loop[1] + 1 and bool(np.all(pcm[loop[1]] == pcm[loop[0]]))
        pcm = pcm[loop[0]:loop[1]]
    return pcm, sr, ch, loop, guard_ok


def spectral_centroid(x, sr):
    m = x if x.ndim == 1 else x.mean(axis=1)
    S = np.abs(np.fft.rfft(m)) ** 2
    f = np.fft.rfftfreq(len(m), 1.0 / sr)
    return float((S * f).sum() / (S.sum() + 1e-20))


def _circ_frames(m, size, hop):
    """Hann-windowed frames read circularly around a loop -> (frames[J, size], hop_seconds_factor)."""
    n = len(m)
    J = max(8, int(round(n / hop)))
    starts = np.round(np.arange(J) * (n / J)).astype(np.int64)
    idx = (starts[:, None] + np.arange(size)[None, :]) % n
    return m[idx] * np.hanning(size)[None, :], n / J


def _acf_peak(D, hop_s):
    """Normalised circular autocorrelation of D[J, ...] along axis 0; strongest value at lags beyond
    the first zero crossing (i.e. excluding the trivial correlation around lag 0 and lag N)."""
    J = D.shape[0]
    F = np.fft.rfft(D, axis=0)
    R = np.fft.irfft(np.abs(F) ** 2, J, axis=0)
    R = R.sum(axis=1) if R.ndim == 2 else R
    if R[0] <= 1e-20:
        return 0.0, 0.0
    R = R / R[0]
    neg = np.nonzero(R[1:] <= 0.0)[0]
    z = int(neg[0]) + 1 if len(neg) else J
    if z >= J - z:
        return 0.0, 0.0
    i = z + int(np.argmax(R[z:J - z + 1]))
    return float(R[i]), i * hop_s


def repetition_score(x, sr):
    """How strongly a loop repeats a pattern shorter than itself (0 = no repetition, 1 = tiled).
    Two views, worst one wins: the fine spectro-temporal texture (log band envelopes of 128 ms frames,
    high-passed at 1.5 Hz) and the slow broadband level contour. -> (score, lag_seconds)."""
    m = x if x.ndim == 1 else x.mean(axis=1)
    size = 1 << int(round(math.log2(0.128 * sr)))
    fr, hop = _circ_frames(m, size, size // 4)
    hop_s = hop / sr
    S = np.abs(np.fft.rfft(fr, axis=1)) ** 2
    f = np.fft.rfftfreq(size, 1.0 / sr)
    edges = np.geomspace(60.0, min(9000.0, 0.45 * sr), 25)
    B = np.stack([S[:, (f >= a) & (f < b)].sum(axis=1) for a, b in zip(edges[:-1], edges[1:])], axis=1)
    L = 10.0 * np.log10(B + 1e-9 * float(B.max()) + 1e-30)
    J = L.shape[0]
    q = np.fft.rfftfreq(J, hop_s)
    Fl = np.fft.rfft(L - L.mean(axis=0), axis=0)
    fine = np.fft.irfft(Fl * (q >= 1.5)[:, None], J, axis=0)
    lev = 10.0 * np.log10(B.sum(axis=1) + 1e-30)
    slow = np.fft.irfft(np.fft.rfft(lev - lev.mean()) * np.exp(-0.5 * (q / 6.0) ** 2), J)
    a, la = _acf_peak(fine, hop_s)
    b, lb = _acf_peak(slow, hop_s)
    return (a, la) if a >= b else (b, lb)


def pitch_track(x, sr, lo, hi):
    """Fundamental per 128 ms frame by weighted harmonic summation, searched in lo/1.6 .. hi*1.6 Hz
    (frames more than 30 dB below the loudest one are ignored). -> array of Hz."""
    m = x if x.ndim == 1 else x.mean(axis=1)
    size = 1 << int(round(math.log2(0.128 * sr)))
    fr, _ = _circ_frames(m, size, size // 4)
    S = np.abs(np.fft.rfft(fr, size * 2, axis=1))
    df = sr / (size * 2.0)
    cand = np.geomspace(lo / 1.6, min(hi * 1.6, 0.2 * sr), 480)
    hs = np.zeros((S.shape[0], len(cand)))
    for h, w in zip(range(1, 6), (1.0, 0.8, 0.6, 0.45, 0.35)):
        b = np.clip(np.round(cand * h / df).astype(np.int64), 0, S.shape[1] - 1)
        hs += w * S[:, b]
    e = (S ** 2).sum(axis=1)
    keep = e > float(e.max()) * 1e-3
    return cand[np.argmax(hs, axis=1)][keep]


def hf_ratio_db(x, sr, fc=10900.0):
    """Energy above fc relative to the total (dB): content that aliases when a 32 kHz loop is played
    x2.2 faster into a 48 kHz mix."""
    m = x if x.ndim == 1 else x.mean(axis=1)
    S = np.abs(np.fft.rfft(m)) ** 2
    f = np.fft.rfftfreq(len(m), 1.0 / sr)
    return float(db(math.sqrt(S[f >= fc].sum() / (S.sum() + 1e-30) + 1e-30)))


def end_level_db(x, sr):
    """RMS of the 15 ms (at most the last quarter of the sound) just before finalize_oneshot's closing
    fade, relative to the peak: a one-shot
    that still rings loudly there is being cut off instead of decaying into silence."""
    m = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=1)
    n = len(m)
    zt = int(0.006 * sr) + 1
    fo = max(8, min(int(0.012 * sr), n // 6))
    b = n - zt - fo
    a = max(0, b - min(int(0.015 * sr), n // 4))
    return float(db(rms_of(m[a:b]) / (peak_of(m) + 1e-12))) if b > a else -200.0


def analyse(name, path):
    """Measure a file on disk and check it against the spec. -> dict (row of the verify table)."""
    fn, o = REGISTRY[name]
    chk = o.get("check", {})
    x, sr, ch, loop, guard_ok = read_wav(path)
    n = x.shape[0]
    pk, rm = float(db(peak_of(x))), float(db(rms_of(x)))
    row = dict(name=name, seconds=round(n / sr, 4), loop=o["loop"], channels=ch, rate=sr,
               peak_db=round(pk, 2), rms_db=round(rm, 2), crest=round(pk - rm, 1),
               centroid=round(spectral_centroid(x, sr)), bytes=os.path.getsize(path), detail="", fails=[])
    f = row["fails"]
    if not np.all(np.isfinite(x)):
        f.append("NaN/Inf")
    if sr != o["sr"] or ch != o["ch"]:
        f.append(f"format {ch}ch/{sr}Hz != {o['ch']}ch/{o['sr']}Hz")
    if pk > PEAK_CEIL_DB + 0.005:
        f.append(f"clip risk: peak {pk:.2f} dBFS")
    if abs(n / sr - o["dur"]) > 0.002 + 1.0 / sr:
        f.append(f"duration {n / sr:.3f}s != {o['dur']:.3f}s")
    if o["loop"]:
        if loop is None:
            f.append("missing smpl loop chunk")
        elif not guard_ok:
            f.append("bad loop guard sample")
        step, curv = loop_seam(x)
        row["detail"] = f"seam {step:.2f}/{curv:.2f}"
        if step >= 1.0:
            f.append(f"loop step {step:.2f}x mean step")
        if curv >= 1.0:
            f.append(f"loop click {curv:.2f}x p99.9 curvature")
        if not (LOOP_RMS_RANGE[0] - 0.05 <= rm <= LOOP_RMS_RANGE[1] + 0.05):
            f.append(f"loop RMS {rm:.1f} dBFS outside {LOOP_RMS_RANGE}")
        if chk.get("aperiodic"):
            sc, lag = repetition_score(x, sr)
            row["detail"] += f" rep {sc:.2f}"
            if sc >= REPEAT_MAX:
                f.append(f"repeating pattern: {sc:.2f} at {lag:.2f}s")
    else:
        if loop is not None:
            f.append("one-shot carries a loop chunk")
        tail = x[-max(1, int(SILENT_TAIL_MS * 1e-3 * sr)):]
        tdb = float(db(peak_of(tail)))
        el = end_level_db(x, sr)
        row["detail"] = "tail " + ("-inf" if tdb < -200 else f"{tdb:.0f}") + f" end {el:.0f}"
        if tdb >= SILENT_TAIL_DB:
            f.append(f"tail not silent ({tdb:.1f} dB)")
        if el > END_MAX_DB:
            f.append(f"cut off: {el:.0f} dB re peak just before the end fade")
        if abs(float(np.ravel(x)[0])) > 0.02:
            f.append("starts with a step")
        if not (ONESHOT_PEAK_RANGE[0] - 0.05 <= pk <= ONESHOT_PEAK_RANGE[1] + 0.005):
            f.append(f"peak {pk:.2f} dBFS outside {ONESHOT_PEAK_RANGE}")
    if chk.get("band"):
        lo, hi = chk["band"]
        tr = pitch_track(x, sr, lo, hi)
        p5, p95 = (float(v) for v in np.percentile(tr, [5, 95]))
        row["detail"] += f" f0 {p5:.0f}-{p95:.0f}"
        if p5 < lo * 0.92 or p95 > hi * 1.08 or p95 / p5 < (hi / lo) ** 0.6:
            f.append(f"f0 track {p5:.0f}..{p95:.0f} Hz does not cover {lo:.0f}..{hi:.0f} Hz")
    if chk.get("hf"):
        h = hf_ratio_db(x, sr)
        row["detail"] += f" hf {h:.0f}"
        if h > HF_MAX_DB:
            f.append(f"{h:.0f} dB of energy above 10.9 kHz (aliases when pitched up)")
    return row


def _job(name):
    """Worker: render + write one sound. -> (name, seconds, error or None)."""
    t0 = time.perf_counter()
    try:
        _, o = REGISTRY[name]
        x = render(name)
        write_wav(os.path.join(OUT_DIR, name + ".wav"), x, o["sr"], o["loop"])
        return name, time.perf_counter() - t0, None
    except Exception as exc:  # report, keep going
        import traceback
        return name, time.perf_counter() - t0, traceback.format_exc() + repr(exc)


def generate(names, jobs):
    os.makedirs(OUT_DIR, exist_ok=True)
    t0 = time.perf_counter()
    order = sorted(names, key=lambda nm: -REGISTRY[nm][1]["dur"] * REGISTRY[nm][1]["sr"] * REGISTRY[nm][1]["ch"])
    errors = []
    if jobs > 1 and len(order) > 3:
        from concurrent.futures import ProcessPoolExecutor
        with ProcessPoolExecutor(max_workers=jobs) as pool:
            results = list(pool.map(_job, order, chunksize=1))
    else:
        results = [_job(nm) for nm in order]
    for nm, dt, err in results:
        if err:
            errors.append(nm)
            print(f"  FAILED {nm}:\n{err}")
    slow = sorted(results, key=lambda r: -r[1])[:5]
    print(f"generated {len(order) - len(errors)}/{len(order)} sounds in {time.perf_counter() - t0:.1f}s "
          f"(slowest: {', '.join(f'{nm} {dt:.1f}s' for nm, dt, _ in slow)})")
    return errors


def analyse_all(names):
    """-> {name: row} for every named sound that exists on disk."""
    out = {}
    for nm in names:
        p = os.path.join(OUT_DIR, nm + ".wav")
        if os.path.isfile(p):
            out[nm] = analyse(nm, p)
    return out


def verify(names, quiet=False, cache=None):
    """Analyse files on disk, print the table, return (rows, n_failed)."""
    cache = cache if cache is not None else analyse_all(names)
    rows = [cache[nm] for nm in names if nm in cache]
    missing = [nm for nm in names if nm not in cache]
    bad = [r for r in rows if r["fails"]]
    show = bad if quiet else rows
    if show:
        hdr = f"{'name':<26}{'sec':>7} {'rate':>6} ch {'peak':>7} {'rms':>7} {'crest':>6} {'cent':>6}  {'check':<34} status"
        print(hdr)
        print("-" * len(hdr))
        for r in show:
            print(f"{r['name']:<26}{r['seconds']:>7.2f} {r['rate']:>6} {r['channels']:>2} {r['peak_db']:>7.2f} {r['rms_db']:>7.2f} "
                  f"{r['crest']:>6.1f} {r['centroid']:>6}  {r['detail']:<34} {'OK' if not r['fails'] else 'FAIL: ' + '; '.join(r['fails'])}")
        print("-" * len(hdr))
    extra = []
    if os.path.isdir(OUT_DIR) and set(names) == set(REGISTRY):
        extra = sorted(f for f in os.listdir(OUT_DIR) if f.endswith(".wav") and f[:-4] not in REGISTRY)
    total = sum(r["bytes"] for r in rows)
    loops = [r for r in rows if r["loop"]]
    shots = [r for r in rows if not r["loop"]]
    print(f"files: {len(rows)}/{len(names)}  ({len(shots)} one-shots, {len(loops)} loops)   total {total / 1e6:.2f} MB ({total / 2**20:.2f} MiB)")
    if shots:
        print(f"one-shots: peak {min(r['peak_db'] for r in shots):.2f} .. {max(r['peak_db'] for r in shots):.2f} dBFS, all tails silent: "
              f"{all('tail not silent' not in ' '.join(r['fails']) for r in shots)}")
    if loops:
        print(f"loops:     rms  {min(r['rms_db'] for r in loops):.2f} .. {max(r['rms_db'] for r in loops):.2f} dBFS, peak max {max(r['peak_db'] for r in loops):.2f} dBFS, "
              f"worst seam step {max(float(r['detail'].split()[1].split('/')[0]) for r in loops):.2f}x mean step")
    if missing:
        print(f"MISSING ({len(missing)}): {', '.join(missing)}")
    if extra:
        print(f"UNREGISTERED FILES ({len(extra)}): {', '.join(extra)}")
    print(f"verification: {'PASS' if not bad and not missing and not extra else 'FAIL'} ({len(bad)} failing, {len(missing)} missing)")
    return rows, len(bad) + len(missing) + len(extra)


def write_manifest(cache):
    """Manifest of every registered sound that exists on disk (measured from the files)."""
    sounds = [{k: cache[nm][k] for k in ("name", "seconds", "loop", "channels", "rate", "peak_db", "rms_db")}
              for nm in REGISTRY if nm in cache]
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as fh:
        json.dump({"sounds": sounds}, fh, indent=1)
        fh.write("\n")
    return len(sounds)


def main(argv=None):
    ap = argparse.ArgumentParser(description="NEON TIDE procedural audio generator")
    ap.add_argument("names", nargs="*", help="sounds to (re)generate; default: all")
    ap.add_argument("--verify", action="store_true", help="only verify the files on disk")
    ap.add_argument("--list", action="store_true", help="list registered sounds")
    ap.add_argument("--jobs", type=int, default=max(1, min(8, (os.cpu_count() or 2) - 1)))
    ap.add_argument("--quiet", action="store_true", help="summary + failing rows only (no full table)")
    ap.add_argument("--family", choices=FAMILIES, action="append", help="restrict to a family (repeatable)")
    a = ap.parse_args(argv)
    unknown = [nm for nm in a.names if nm not in REGISTRY]
    if unknown:
        ap.error("unknown sound(s): " + ", ".join(unknown))
    names = a.names or list(REGISTRY)
    if a.family:
        names = [nm for nm in names if REGISTRY[nm][1]["family"] in a.family]
    if a.list:
        for nm in names:
            o = REGISTRY[nm][1]
            print(f"{nm:<26} {o['dur']:>6.2f}s {'loop' if o['loop'] else 'shot'} {o['ch']}ch {o['sr']}Hz  {o['family']}")
        print(f"{len(names)} sounds: " + ", ".join(f"{fam} {sum(REGISTRY[nm][1]['family'] == fam for nm in names)}" for fam in FAMILIES))
        return 0
    errors = []
    if not a.verify:
        errors = generate(names, a.jobs)
    cache = analyse_all(list(REGISTRY))
    if not a.verify:
        print(f"manifest: {write_manifest(cache)} entries -> {os.path.relpath(MANIFEST, ROOT)}")
    _, nbad = verify(names, a.quiet, cache)
    return 1 if (errors or nbad) else 0


if __name__ == "__main__":
    sys.exit(main())
