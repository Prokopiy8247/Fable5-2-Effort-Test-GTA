"""HALCYON BAY - audio synthesis primitives (numpy only, deterministic).

Everything in the game's soundscape is built from the handful of blocks in this file:
oscillators (phase-accumulating, band-limited additive), spectrally shaped noise, envelopes,
FFT-domain zero-phase filters (circular by default, which is what makes seamless loops trivial),
a time-varying state-variable filter, convolution reverb with a synthetic impulse response,
feedback echo and soft-clip waveshaping.

No external audio material of any kind is read: the only inputs are seeds and numbers.
"""
from __future__ import annotations

import math
import os
import struct
import zlib

import numpy as np

SR = 44100
TAU = 2.0 * math.pi


# --------------------------------------------------------------------------------------------
# basics
# --------------------------------------------------------------------------------------------

def rng(seed) -> np.random.RandomState:
    """Deterministic generator. Accepts an int or a string (hashed with crc32)."""
    if isinstance(seed, str):
        seed = zlib.crc32(seed.encode("utf-8")) & 0x7FFFFFFF
    return np.random.RandomState(int(seed) & 0x7FFFFFFF)


def secs(dur: float, sr: int = SR) -> int:
    return max(1, int(round(dur * sr)))


def tt(n: int, sr: int = SR) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / sr


def db(x: float) -> float:
    return 20.0 * math.log10(max(x, 1e-12))


def undb(d: float) -> float:
    return 10.0 ** (d / 20.0)


def peak(x: np.ndarray) -> float:
    return float(np.max(np.abs(x))) if len(x) else 0.0


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x * x))) if len(x) else 0.0


def norm(x: np.ndarray, level: float = 1.0) -> np.ndarray:
    p = peak(x)
    return x * (level / p) if p > 1e-12 else x


def mtof(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


# --------------------------------------------------------------------------------------------
# spectral (FFT) filters - zero phase, circular unless pad > 0
# --------------------------------------------------------------------------------------------

def spec_filter(x: np.ndarray, gain_fn, sr: int = SR, pad: int = 0) -> np.ndarray:
    n = len(x)
    if pad > 0:
        x = np.concatenate([np.zeros(pad), x, np.zeros(pad)])
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    y = np.fft.irfft(spec * gain_fn(f), len(x))
    return y[pad:pad + n] if pad > 0 else y


def g_lp(fc: float, order: int = 2):
    return lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def g_hp(fc: float, order: int = 2):
    return lambda f: 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-6)) ** (2 * order))


def g_bp(lo: float, hi: float, order: int = 2):
    a, b = g_hp(lo, order), g_lp(hi, order)
    return lambda f: a(f) * b(f)


def g_bell(f0: float, bw: float, gain: float = 1.0):
    """Resonance-like bell: 1 at f0, -3 dB at f0 +- bw/2, 6 dB/oct skirts."""
    return lambda f: gain / np.sqrt(1.0 + ((f - f0) / (bw * 0.5)) ** 2)


def g_tilt(db_per_oct: float, ref: float = 1000.0):
    e = db_per_oct / 6.0206
    return lambda f: (np.maximum(f, 20.0) / ref) ** e


def g_sum(*fns):
    return lambda f: sum(fn(f) for fn in fns)


def g_mul(*fns):
    def _g(f):
        out = np.ones_like(f)
        for fn in fns:
            out = out * fn(f)
        return out
    return _g


def lp(x, fc, order=2, sr=SR, pad=0):
    return spec_filter(x, g_lp(fc, order), sr, pad)


def hp(x, fc, order=2, sr=SR, pad=0):
    return spec_filter(x, g_hp(fc, order), sr, pad)


def bp(x, lo, hi, order=2, sr=SR, pad=0):
    return spec_filter(x, g_bp(lo, hi, order), sr, pad)


def bell(x, f0, bw, sr=SR, pad=0):
    return spec_filter(x, g_bell(f0, bw), sr, pad)


def formant_filter(x, formants, sr=SR, pad=0, floor=0.0):
    """Parallel formant bank. formants = [(freq, bandwidth, amplitude), ...]."""
    def gain(f):
        g = np.full_like(f, floor)
        for (f0, bw, a) in formants:
            g = g + a / np.sqrt(1.0 + ((f - f0) / (bw * 0.5)) ** 2)
        return g * (1.0 / np.sqrt(1.0 + (40.0 / np.maximum(f, 1e-6)) ** 4))
    return spec_filter(x, gain, sr, pad)


# --------------------------------------------------------------------------------------------
# noise
# --------------------------------------------------------------------------------------------

def white(n: int, r: np.random.RandomState) -> np.ndarray:
    return r.standard_normal(n)


def colored(n: int, r, tilt_db_oct: float = -3.0, lo: float = 20.0, hi: float = 20000.0,
            sr: int = SR, order: int = 2) -> np.ndarray:
    """Band-limited noise with a spectral tilt (-3 pink, -6 brown). Periodic over n samples."""
    hi = min(hi, sr * 0.49)
    x = spec_filter(r.standard_normal(n), g_mul(g_tilt(tilt_db_oct), g_bp(lo, hi, order)), sr)
    return x / (rms(x) + 1e-12)


def band_noise(n: int, r, lo: float, hi: float, sr: int = SR, order: int = 2) -> np.ndarray:
    """White noise band-passed to [lo, hi], unit RMS, periodic over n samples."""
    hi = min(hi, sr * 0.49)
    x = bp(r.standard_normal(n), lo, hi, order, sr)
    return x / (rms(x) + 1e-12)


def slow_noise(n: int, r, rate_hz: float, sr: int = SR) -> np.ndarray:
    """Smooth random control signal in [-1, 1]-ish (unit peak), periodic over n samples."""
    x = lp(r.standard_normal(n), rate_hz, 3, sr)
    return x / (peak(x) + 1e-12)


# --------------------------------------------------------------------------------------------
# envelopes
# --------------------------------------------------------------------------------------------

def env_exp(n: int, tau: float, sr: int = SR) -> np.ndarray:
    return np.exp(-tt(n, sr) / max(tau, 1e-6))


def env_ad(n: int, attack: float, tau: float, sr: int = SR) -> np.ndarray:
    """Linear attack then exponential decay."""
    t = tt(n, sr)
    a = max(attack, 1.0 / sr)
    return np.where(t < a, t / a, np.exp(-(t - a) / max(tau, 1e-6)))


def env_pts(n: int, pts, sr: int = SR) -> np.ndarray:
    """Piecewise-linear envelope from [(time_s, value), ...]."""
    ts = [p[0] for p in pts]
    vs = [p[1] for p in pts]
    return np.interp(tt(n, sr), ts, vs)


def env_adsr(n: int, a: float, d: float, s: float, rel: float, sr: int = SR) -> np.ndarray:
    """ADSR where the release occupies the last `rel` seconds of the buffer."""
    t = tt(n, sr)
    total = n / sr
    hold_end = max(total - rel, a + 1e-4)
    e = np.where(t < a, t / max(a, 1e-5), s + (1.0 - s) * np.exp(-(t - a) / max(d, 1e-5)))
    r_env = np.clip((total - t) / max(rel, 1e-5), 0.0, 1.0)
    return e * np.where(t > hold_end, r_env, 1.0)


def hann(n: int) -> np.ndarray:
    return 0.5 - 0.5 * np.cos(TAU * (np.arange(n) + 0.5) / n)


def fade(x: np.ndarray, fin: float = 0.0005, fout: float = 0.008, sr: int = SR) -> np.ndarray:
    y = x.copy()
    a = min(len(y) // 2, secs(fin, sr)) if fin > 0 else 0
    b = min(len(y) // 2, secs(fout, sr)) if fout > 0 else 0
    if a > 1:
        y[:a] *= np.linspace(0.0, 1.0, a)
    if b > 1:
        y[-b:] *= np.linspace(1.0, 0.0, b) ** 2
    return y


def smoothstep(e0: float, e1: float, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# --------------------------------------------------------------------------------------------
# oscillators
# --------------------------------------------------------------------------------------------

def phase_of(freq, n: int, sr: int = SR, phase0: float = 0.0) -> np.ndarray:
    """Phase (radians) for a constant or per-sample frequency."""
    if np.isscalar(freq):
        return phase0 + TAU * float(freq) * tt(n, sr)
    f = np.asarray(freq, dtype=np.float64)
    ph = np.cumsum(f) * (TAU / sr)
    return phase0 + ph - ph[0]


def sine(freq, n: int, sr: int = SR, phase0: float = 0.0) -> np.ndarray:
    return np.sin(phase_of(freq, n, sr, phase0))


def glide(f0: float, f1: float, n: int, tau: float, sr: int = SR) -> np.ndarray:
    """Frequency curve that falls/rises exponentially from f0 towards f1."""
    return f1 + (f0 - f1) * np.exp(-tt(n, sr) / max(tau, 1e-6))


def chirp(f0: float, f1: float, n: int, tau: float, sr: int = SR) -> np.ndarray:
    return sine(glide(f0, f1, n, tau, sr), n, sr)


def additive(freq, n: int, amps, sr: int = SR, phases=None) -> np.ndarray:
    """Band-limited harmonic stack. amps[k-1] is the amplitude of harmonic k.
    Harmonics that would cross 0.45 * sr are faded out per sample (no aliasing)."""
    ph = phase_of(freq, n, sr)
    fmax = float(np.max(freq)) if not np.isscalar(freq) else float(freq)
    f_arr = None if np.isscalar(freq) else np.asarray(freq, dtype=np.float64)
    out = np.zeros(n)
    lim = sr * 0.45
    for k, a in enumerate(amps, start=1):
        if a == 0.0:
            continue
        if f_arr is None:
            if k * fmax >= lim:
                break
            g = a
        else:
            if k * float(np.min(f_arr)) >= lim:
                break
            g = a * np.clip((lim - k * f_arr) / (0.05 * sr), 0.0, 1.0)
        p0 = 0.0 if phases is None else phases[(k - 1) % len(phases)]
        out += g * np.sin(k * ph + p0)
    return out


def saw_amps(nh: int, rolloff: float = 1.0):
    return [1.0 / (k ** rolloff) for k in range(1, nh + 1)]


def square_amps(nh: int, rolloff: float = 1.0):
    return [(1.0 / (k ** rolloff)) if k % 2 == 1 else 0.0 for k in range(1, nh + 1)]


def modal(freqs, taus, amps, dur: float, r=None, sr: int = SR) -> np.ndarray:
    """Sum of exponentially decaying sine partials (struck metal / wood / glass)."""
    n = secs(dur, sr)
    t = tt(n, sr)
    out = np.zeros(n)
    for i, f in enumerate(freqs):
        if f >= sr * 0.47:
            continue
        ph = r.uniform(0.0, TAU) if r is not None else 0.0
        out += amps[i % len(amps)] * np.exp(-t / taus[i % len(taus)]) * np.sin(TAU * f * t + ph)
    return out


# --------------------------------------------------------------------------------------------
# time-domain processors
# --------------------------------------------------------------------------------------------

def svf(x: np.ndarray, fc, q: float = 0.707, mode: str = "lp", sr: int = SR) -> np.ndarray:
    """Time-varying state-variable filter (trapezoidal / Cytomic form). fc: scalar or array."""
    n = len(x)
    fc_a = np.minimum(np.broadcast_to(np.asarray(fc, dtype=np.float64), (n,)), sr * 0.45)
    g = np.tan(np.pi * fc_a / sr)
    k = 1.0 / q
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    xl, a1l, a2l, a3l = x.tolist(), a1.tolist(), a2.tolist(), a3.tolist()
    out = [0.0] * n
    ic1 = 0.0
    ic2 = 0.0
    sel = {"lp": 0, "bp": 1, "hp": 2}[mode]
    for i in range(n):
        v0 = xl[i]
        v3 = v0 - ic2
        v1 = a1l[i] * ic1 + a2l[i] * v3
        v2 = ic2 + a2l[i] * ic1 + a3l[i] * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        if sel == 0:
            out[i] = v2
        elif sel == 1:
            out[i] = v1
        else:
            out[i] = v0 - k * v1 - v2
    return np.asarray(out)


def soft_clip(x: np.ndarray, drive: float = 1.0) -> np.ndarray:
    if drive <= 0.0:
        return x
    return np.tanh(x * drive) / math.tanh(drive)


def make_ir(rt60: float, sr: int = SR, seed=1, lp_hz: float = 5000.0, hp_hz: float = 120.0,
            predelay: float = 0.012, bright: float = 0.55, early: int = 5) -> np.ndarray:
    """Synthetic room/outdoor impulse response: exponentially decaying noise whose highs die
    faster than its lows, a soft diffuse onset and a few sparse early reflections."""
    r = rng(seed)
    n = secs(rt60 * 1.15, sr)
    t = tt(n, sr)
    base = r.standard_normal(n)
    low = lp(base, max(lp_hz * 0.3, 200.0), 2, sr)
    high = base - low
    ir = low * np.exp(-6.91 * t / rt60) + high * np.exp(-6.91 * t / (rt60 * bright))
    ir = bp(ir, hp_hz, min(lp_hz, sr * 0.45), 2, sr)
    ir *= 1.0 - np.exp(-t / 0.006)
    for _ in range(early):
        i = int(r.uniform(0.004, 0.07) * sr)
        if i < n:
            ir[i] += r.choice([-1.0, 1.0]) * r.uniform(0.25, 0.6) * peak(ir)
    ir /= math.sqrt(float(np.sum(ir * ir)) + 1e-12)
    return np.concatenate([np.zeros(secs(predelay, sr)), ir])


def _fft_convolve(x: np.ndarray, h: np.ndarray) -> np.ndarray:
    n = len(x) + len(h) - 1
    size = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(h, size), size)[:n]


def reverb(x: np.ndarray, rt60: float, wet: float, seed=1, sr: int = SR, **kw) -> np.ndarray:
    """One-shot reverb. Output is longer than the input (tail). `wet` = peak of the wet
    signal relative to the peak of the dry signal."""
    ir = make_ir(rt60, sr, seed, **kw)
    w = _fft_convolve(x, ir)
    out = np.zeros(len(w))
    out[:len(x)] = x
    pw = peak(w)
    if pw > 1e-12:
        out += w * (wet * peak(x) / pw)
    return out


def reverb_circ(x: np.ndarray, rt60: float, wet: float, seed=1, sr: int = SR, **kw) -> np.ndarray:
    """Loop-safe reverb (circular convolution). `wet` = RMS of wet relative to RMS of dry."""
    ir = make_ir(rt60, sr, seed, **kw)
    n = len(x)
    folded = np.zeros(n)
    for i in range(0, len(ir), n):
        seg = ir[i:i + n]
        folded[:len(seg)] += seg
    w = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(folded), n)
    rw = rms(w)
    if rw < 1e-12:
        return x.copy()
    return x + w * (wet * rms(x) / rw)


def echo(x: np.ndarray, delay: float, feedback: float = 0.4, taps: int = 5, sr: int = SR,
         damp_hz: float = 0.0, mix: float = 1.0) -> np.ndarray:
    """Feedback echo for one-shots (output is extended by the echoes)."""
    d = secs(delay, sr)
    out = np.zeros(len(x) + d * taps)
    out[:len(x)] = x
    cur = x
    g = mix
    for k in range(1, taps + 1):
        g *= feedback if k > 1 else 1.0
        if damp_hz > 0.0:
            cur = lp(cur, damp_hz, 1, sr, pad=64)
        out[d * k:d * k + len(x)] += cur * g * (feedback if k == 1 else 1.0)
    return out


def echo_circ(x: np.ndarray, delay: float, feedback: float = 0.4, taps: int = 6, sr: int = SR,
              damp_hz: float = 0.0, mix: float = 0.5) -> np.ndarray:
    """Loop-safe feedback echo: wet-only copies are rolled around the loop."""
    d = secs(delay, sr)
    out = x.copy()
    cur = x
    g = mix
    for k in range(1, taps + 1):
        if damp_hz > 0.0:
            cur = lp(cur, damp_hz, 1, sr)
        out += np.roll(cur, d * k) * g
        g *= feedback
    return out


class Mix:
    """Additive timeline. `add` extends the buffer, `wrap` folds around it (for loops)."""

    def __init__(self, dur: float = 0.0, sr: int = SR):
        self.sr = sr
        self.b = np.zeros(secs(dur, sr) if dur > 0 else 0)

    def add(self, sig: np.ndarray, t: float = 0.0, gain: float = 1.0) -> "Mix":
        i = max(0, int(round(t * self.sr)))
        need = i + len(sig)
        if need > len(self.b):
            self.b = np.concatenate([self.b, np.zeros(need - len(self.b))])
        self.b[i:need] += sig * gain
        return self

    def wrap(self, sig: np.ndarray, t: float = 0.0, gain: float = 1.0) -> "Mix":
        add_wrap(self.b, sig, int(round(t * self.sr)), gain)
        return self


def add_wrap(buf: np.ndarray, sig: np.ndarray, i0: int, gain: float = 1.0) -> None:
    """buf[(i0 + k) % N] += gain * sig[k] (sig may be longer than buf)."""
    n = len(buf)
    i0 %= n
    pos = 0
    m = len(sig)
    while pos < m:
        room = n - i0
        take = min(room, m - pos)
        buf[i0:i0 + take] += sig[pos:pos + take] * gain
        pos += take
        i0 = 0


# --------------------------------------------------------------------------------------------
# finishing, measuring, writing
# --------------------------------------------------------------------------------------------

def limit_peak(x: np.ndarray, ceiling: float) -> np.ndarray:
    """Transparent below ~70 % of the ceiling, tanh knee above it."""
    p = peak(x)
    if p <= ceiling:
        return x
    knee = ceiling * 0.7
    y = x.copy()
    over = np.abs(y) > knee
    span = ceiling - knee
    y[over] = np.sign(y[over]) * (knee + span * np.tanh((np.abs(y[over]) - knee) / span))
    return y


def finalize(x: np.ndarray, level, sr: int = SR, loop: bool = False, attack: float = 0.0003,
             release: float = 0.01) -> np.ndarray:
    """DC removal, edge fades (one-shots), level. level = ("peak", dB) or ("rms", dB, ceil_dB)."""
    if loop:
        y = spec_filter(x, g_hp(18.0, 2), sr)
        y = y - float(np.mean(y))
    else:
        y = spec_filter(x, g_hp(18.0, 2), sr, pad=secs(0.08, sr))
        y = fade(y, attack, release, sr)
    if level[0] == "peak":
        y = norm(y, undb(level[1]))
    else:
        target = undb(level[1])
        ceiling = undb(level[2]) if len(level) > 2 else undb(-3.0)
        for _ in range(4):
            cur = rms(y)
            if cur < 1e-12:
                break
            y = limit_peak(y * (target / cur), ceiling)
        if loop:
            y = y - float(np.mean(y))
    return y


BANDS = ((0.0, 120.0), (120.0, 500.0), (500.0, 2000.0), (2000.0, 6000.0), (6000.0, 1e9))
BAND_NAMES = ("sub<120", "low<500", "mid<2k", "hi<6k", "air")


def analyse(x: np.ndarray, sr: int, loop: bool) -> dict:
    n = len(x)
    spec = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(n, 1.0 / sr)
    total = float(np.sum(spec)) + 1e-20
    bands = [float(np.sum(spec[(f >= lo) & (f < hi)])) / total for (lo, hi) in BANDS]
    centroid = float(np.sum(f * spec) / total)
    d = np.diff(x)
    typ = float(np.sqrt(np.mean(d * d))) + 1e-12
    p999 = float(np.percentile(np.abs(d), 99.9)) + 1e-12
    seam_jump = abs(float(x[0]) - float(x[-1]))
    edge = max(abs(float(x[0])), abs(float(x[-1])))
    hf_excess, hf_vs_p95 = seam_hf(x) if loop else (0.0, 0.0)
    return {
        "dur": n / sr, "sr": sr, "peak_db": db(peak(x)), "rms_db": db(rms(x)),
        "dc": float(np.mean(x)), "bands": bands, "centroid": centroid,
        "seam_jump": seam_jump, "seam_ratio": seam_jump / typ, "seam_vs_p999": seam_jump / p999,
        "edge": edge, "loop": loop, "seam_hf_db": hf_excess, "seam_hf_vs_p95_db": hf_vs_p95,
    }


def seam_hf(x: np.ndarray, w: int = 1024):
    """Click detector for loops: upper-half-spectrum energy of a Hann frame that straddles the
    wrap point, in dB relative to the median (and to the 95th percentile) of the same measure
    over frames inside the file. A seamless loop gives about 0 dB vs the median."""
    if len(x) < 8 * w:
        return 0.0, 0.0
    win = np.hanning(w)

    def hf(frame):
        sp = np.abs(np.fft.rfft(frame * win)) ** 2
        return float(np.sum(sp[len(sp) // 2:])) + 1e-20

    seam = hf(np.concatenate([x[-(w // 2):], x[:w // 2]]))
    hop = max(w // 2, (len(x) - w) // 400)
    frames = np.array([hf(x[i:i + w]) for i in range(0, len(x) - w, hop)])
    return (10.0 * math.log10(seam / float(np.median(frames))),
            10.0 * math.log10(seam / float(np.percentile(frames, 95))))


def to_pcm16(x: np.ndarray, seed=0) -> np.ndarray:
    r = rng(seed)
    dither = (r.uniform(-0.5, 0.5, len(x)) + r.uniform(-0.5, 0.5, len(x)))
    q = np.round(np.clip(x, -1.0, 1.0) * 32767.0 + dither)
    return np.clip(q, -32768, 32767).astype("<i2")


def write_wav(path: str, x: np.ndarray, sr: int, seed=0, loop: bool = False) -> np.ndarray:
    """16-bit mono PCM RIFF. Loops also carry a 'smpl' chunk (whole file, forward)."""
    pcm = to_pcm16(x, seed)
    if loop:
        # no dither discontinuity matters here, but keep the first/last samples honest
        pass
    data = pcm.tobytes()
    fmt = struct.pack("<4sIHHIIHH", b"fmt ", 16, 1, 1, sr, sr * 2, 2, 16)
    chunks = fmt + struct.pack("<4sI", b"data", len(data)) + data
    if len(data) % 2:
        chunks += b"\x00"
    if loop:
        period_ns = int(round(1e9 / sr))
        smpl = struct.pack("<9I", 0, 0, period_ns, 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(pcm) - 1, 0, 0)
        chunks += struct.pack("<4sI", b"smpl", len(smpl)) + smpl
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(struct.pack("<4sI4s", b"RIFF", 4 + len(chunks), b"WAVE") + chunks)
    os.replace(tmp, path)
    return pcm.astype(np.float64) / 32767.0
