"""HALCYON BAY - radio music: a small step sequencer + synth rack that composes five original
stations procedurally (two seamless loops each). No samples, no quoted melodies: chord
progressions are generic diatonic cycles and every melody is generated from a seeded
motif-and-variation walk over the scale.

Loops are seamless because every event is mixed with wrap-around into a buffer that is exactly
a whole number of bars long, and all effects (echo, reverb, filters, side-chain) are circular.
"""
from __future__ import annotations

import math

import numpy as np

from dsp import (TAU, add_wrap, band_noise, bp, chirp, colored, echo_circ, env_ad, env_exp, hp, lp,
                 mtof, norm, peak, reverb_circ, rms, rng, secs, slow_noise, soft_clip, tt, db, undb,
                 spec_filter, g_bell, g_bp, g_hp, g_lp, g_mul)

MSR = 32000

MINOR = (0, 2, 3, 5, 7, 8, 10)
MAJOR = (0, 2, 4, 5, 7, 9, 11)
DORIAN = (0, 2, 3, 5, 7, 9, 10)
LYDIAN = (0, 2, 4, 6, 7, 9, 11)
MIXO = (0, 2, 4, 5, 7, 9, 10)

VEL = {"X": 1.0, "x": 0.72, "o": 0.42, "-": 0.22}


def deg_to_midi(root: int, scale, deg: int) -> int:
    return root + 12 * (deg // 7) + scale[deg % 7]


def chord(root: int, scale, deg: int, tones=(0, 2, 4, 6)):
    return [deg_to_midi(root, scale, deg + t) for t in tones]


# --------------------------------------------------------------------------------------------
# instruments (all return mono arrays at MSR, roughly unit peak)
# --------------------------------------------------------------------------------------------

def kick(f0=165.0, f1=47.0, tau_f=0.032, tau_a=0.19, click_g=0.3, drive=1.6, dur=0.45):
    n = secs(dur, MSR)
    x = chirp(f0, f1, n, tau_f, MSR) * env_ad(n, 0.0012, tau_a, MSR)
    nc = secs(0.012, MSR)
    x[:nc] += click_g * band_noise(nc, rng(5), 1500.0, 9000.0, MSR) * env_exp(nc, 0.002, MSR) * 0.5
    x *= np.minimum(1.0, (n - np.arange(n)) / (0.02 * MSR))
    return soft_clip(norm(x), drive)


def snare(tone=188.0, noise_lo=1400.0, noise_hi=11000.0, tau=0.1, tone_g=0.55, seed=7, dur=0.32):
    n = secs(dur, MSR)
    r = rng(seed)
    t = tt(n, MSR)
    body = (np.sin(TAU * tone * t) + 0.6 * np.sin(TAU * tone * 1.78 * t)) * np.exp(-t / 0.045)
    nz = band_noise(n, r, noise_lo, noise_hi, MSR) * env_ad(n, 0.001, tau, MSR)
    x = tone_g * body + norm(nz)
    x *= np.minimum(1.0, (n - np.arange(n)) / (0.02 * MSR))
    return soft_clip(norm(x), 1.4)


def clap(seed=9, tau=0.09):
    n = secs(0.3, MSR)
    r = rng(seed)
    x = np.zeros(n)
    for i, off in enumerate((0.0, 0.011, 0.023)):
        m = secs(0.2, MSR)
        b = band_noise(m, r, 900.0, 4200.0, MSR) * env_exp(m, 0.006 if i < 2 else tau, MSR)
        i0 = secs(off, MSR)
        x[i0:i0 + m] += b[:n - i0] * (0.7 if i < 2 else 1.0)
    return norm(x)


def hat(tau=0.022, lo=6500.0, seed=11, dur=None, metal=0.3):
    dur = dur if dur is not None else max(0.06, tau * 6.0)
    n = secs(dur, MSR)
    r = rng(seed)
    t = tt(n, MSR)
    x = band_noise(n, r, lo, 15000.0, MSR)
    ring = sum(np.sign(np.sin(TAU * f * t)) for f in (5230.0, 6870.0, 8120.0, 9370.0, 11200.0))
    x = norm(x) + metal * hp(ring, 7000.0, 2, MSR) / 5.0
    x *= env_ad(n, 0.0006, tau, MSR) * np.minimum(1.0, (n - np.arange(n)) / (0.004 * MSR))
    return norm(x)


def shaker(seed=13):
    n = secs(0.09, MSR)
    x = band_noise(n, rng(seed), 4500.0, 12000.0, MSR) * np.sin(np.pi * np.arange(n) / n) ** 1.5
    return norm(x)


def rim(seed=15):
    n = secs(0.07, MSR)
    t = tt(n, MSR)
    x = (np.sin(TAU * 820.0 * t) + 0.6 * np.sin(TAU * 1730.0 * t)) * np.exp(-t / 0.012)
    x[:secs(0.004, MSR)] += 0.5 * band_noise(secs(0.004, MSR), rng(seed), 2000.0, 9000.0, MSR)
    return norm(x)


def tom(freq=120.0):
    n = secs(0.35, MSR)
    x = chirp(freq * 1.6, freq, n, 0.03, MSR) * env_ad(n, 0.002, 0.11, MSR)
    return norm(x * np.minimum(1.0, (n - np.arange(n)) / (0.02 * MSR)))


def crash(seed=17, tau=0.7):
    n = secs(2.2, MSR)
    r = rng(seed)
    t = tt(n, MSR)
    x = band_noise(n, r, 3500.0, 15000.0, MSR)
    ring = sum(np.sin(TAU * f * t + i) for i, f in enumerate((3420.0, 4810.0, 5930.0, 7250.0, 8840.0, 10300.0)))
    x = (norm(x) + 0.25 * ring / 6.0) * env_ad(n, 0.002, tau, MSR)
    return norm(x * np.minimum(1.0, (n - np.arange(n)) / (0.1 * MSR)))


def synth(freq, dur, wave="saw", nh=40, cutoff=(3000.0, 900.0, 0.15), q=0.0,
          adsr=(0.005, 0.12, 0.7, 0.08), detune=(0.0,), sub=0.0, vib=(0.0, 0.0)):
    """Additive emulation of a subtractive voice: harmonic k is weighted by a 12 dB/oct
    low-pass whose cutoff follows an envelope (start, end, tau). Alias-free by design."""
    a, d, s, rel = adsr
    n = secs(dur + rel, MSR)
    t = tt(n, MSR)
    fc = cutoff[1] + (cutoff[0] - cutoff[1]) * np.exp(-t / max(cutoff[2], 1e-4))
    fc_max = max(cutoff[0], cutoff[1])
    out = np.zeros(n)
    for di, cents in enumerate(detune):
        f = freq * 2.0 ** (cents / 1200.0)
        ph = TAU * f * t + 1.7 * di
        if vib[1] > 0.0:
            ph = ph + (f * vib[1] / max(vib[0], 0.1)) * np.sin(TAU * vib[0] * t) * np.minimum(1.0, t / 0.25)
        kmax = int(min(MSR * 0.45, 9.0 * fc_max) / f)
        for k in range(1, max(1, min(nh, kmax)) + 1):
            if wave == "square" and k % 2 == 0:
                continue
            amp = 1.0 / k if wave != "tri" else (1.0 / (k * k) if k % 2 == 1 else 0.0)
            if amp == 0.0:
                continue
            h = 1.0 / np.sqrt(1.0 + (k * f / fc) ** 4)
            if q > 0.0:
                h = h * (1.0 + q * np.exp(-((k * f - fc) / (0.3 * fc)) ** 2))
            out += amp * h * np.sin(k * ph)
    out /= len(detune)
    if sub > 0.0:
        out += sub * np.sin(TAU * freq * 0.5 * t)
    hold = dur
    env = np.where(t < a, t / max(a, 1e-4), s + (1.0 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    env = np.where(t > hold, env * np.clip(1.0 - (t - hold) / max(rel, 1e-4), 0.0, 1.0) ** 2, env)
    return out * env


def epiano(freq, dur, bright=1.0):
    """FM electric piano: decaying modulation index plus a short 'tine' partial."""
    rel = 0.25
    n = secs(dur + rel, MSR)
    t = tt(n, MSR)
    idx = 1.5 * bright * np.exp(-t / 0.3) + 0.25
    x = np.sin(TAU * freq * t + idx * np.sin(TAU * freq * t))
    x += 0.2 * bright * np.exp(-t / 0.05) * np.sin(TAU * freq * 7.0 * t + 0.5 * np.sin(TAU * freq * t))
    env = np.minimum(1.0, t / 0.004) * np.exp(-t / 1.4)
    env = np.where(t > dur, env * np.clip(1.0 - (t - dur) / rel, 0.0, 1.0) ** 2, env)
    return x * env * (1.0 + 0.05 * np.sin(TAU * 4.6 * t))


def fm_bell(freq, dur, tau=1.6, ratio=3.5, index=2.2):
    n = secs(dur, MSR)
    t = tt(n, MSR)
    x = np.sin(TAU * freq * t + index * np.exp(-t / (tau * 0.5)) * np.sin(TAU * freq * ratio * t))
    env = np.minimum(1.0, t / 0.003) * np.exp(-t / tau) * np.clip((dur - t) / 0.15, 0.0, 1.0)
    return x * env


# --------------------------------------------------------------------------------------------
# sequencer
# --------------------------------------------------------------------------------------------

class Song:
    def __init__(self, bpm: float, bars: int, seed, swing: float = 0.0):
        self.bpm = bpm
        self.bars = bars
        self.beat = 60.0 / bpm
        self.n = int(round(bars * 4.0 * self.beat * MSR))
        self.dur = self.n / MSR
        self.r = rng(seed)
        self.swing = swing
        self.tracks: dict = {}
        self.cache: dict = {}
        self.kicks: list = []

    def buf(self, track: str) -> np.ndarray:
        if track not in self.tracks:
            self.tracks[track] = np.zeros(self.n)
        return self.tracks[track]

    def pos(self, bar: float, step: float) -> int:
        sw = self.swing * 0.25 if (float(step).is_integer() and int(step) % 2 == 1) else 0.0
        return int(round((bar * 4.0 + step / 4.0 + sw) * self.beat * MSR))

    def steps(self, k: float) -> float:
        return k * self.beat / 4.0

    def put(self, track: str, sig: np.ndarray, bar: float, step: float, gain: float = 1.0) -> None:
        add_wrap(self.buf(track), sig, self.pos(bar, step), gain)

    def pattern(self, track: str, sig: np.ndarray, pat: str, gain: float = 1.0, bars=None,
                human: float = 0.0, is_kick: bool = False) -> None:
        for b in (range(self.bars) if bars is None else bars):
            for s, ch in enumerate(pat):
                if ch in VEL:
                    g = gain * VEL[ch] * (1.0 + human * self.r.uniform(-1.0, 1.0))
                    self.put(track, sig, b, s, g)
                    if is_kick:
                        self.kicks.append(self.pos(b, s))

    def play(self, track: str, name: str, fn, midi: float, bar: float, step: float,
             len_steps: float, gain: float = 1.0) -> None:
        key = (name, round(float(midi), 3), round(float(len_steps), 3))
        if key not in self.cache:
            self.cache[key] = fn(mtof(midi), self.steps(len_steps))
        self.put(track, self.cache[key], bar, step, gain)

    def sidechain(self, tracks, depth: float = 0.5, tau: float = 0.16) -> None:
        if not self.kicks:
            return
        env = np.zeros(self.n)
        shape = np.exp(-tt(secs(tau * 6.0, MSR), MSR) / tau)
        for p in self.kicks:
            add_wrap(env, shape, p)
        gain = 1.0 - depth * np.clip(env, 0.0, 1.0)
        for tname in tracks:
            if tname in self.tracks:
                self.tracks[tname] *= gain

    def fx(self, track: str, fn) -> None:
        if track in self.tracks:
            self.tracks[track] = fn(self.tracks[track])

    def mix(self, levels: dict, drive: float = 1.3) -> np.ndarray:
        """levels: track -> dB. Each track is balanced on its 'active' RMS first."""
        out = np.zeros(self.n)
        for tname, level_db in levels.items():
            if tname not in self.tracks:
                continue
            x = self.tracks[tname]
            p = peak(x)
            if p < 1e-9:
                continue
            active = x[np.abs(x) > 0.02 * p]
            a_rms = float(np.sqrt(np.mean(active * active))) if len(active) else rms(x)
            out += x * (undb(level_db) / max(a_rms, 1e-9))
        return soft_clip(norm(out), drive)


def make_motif(r, onsets, total_steps=32, span=(-3, 9), start=None, max_len=6):
    """Seeded melodic cell. Notes are (step, length, scale-degree offset from the chord root).
    Strong beats snap to chord tones so the cell fits any diatonic chord it is transposed to."""
    cur = int(start if start is not None else r.choice([0, 2, 4, 7]))
    notes = []
    for i, st in enumerate(onsets):
        nxt = onsets[i + 1] if i + 1 < len(onsets) else total_steps
        length = min(nxt - st, max_len)
        if st % 8 == 0:
            cur = min((c for c in (-3, 0, 2, 4, 7, 9) if span[0] <= c <= span[1]), key=lambda c: abs(c - cur))
        notes.append((st, length, cur))
        step = int(r.choice([-2, -1, -1, 1, 1, 2, 3, -3], p=[0.14, 0.22, 0.12, 0.2, 0.12, 0.12, 0.04, 0.04]))
        cur = int(np.clip(cur + step, span[0], span[1]))
    return notes


def vary(r, motif, amount=0.35, span=(-3, 9)):
    out = []
    for i, (st, ln, off) in enumerate(motif):
        if i >= len(motif) // 2 and r.uniform() < amount and st % 8 != 0:
            off = int(np.clip(off + r.choice([-1, 1, 2, -2]), span[0], span[1]))
        out.append((st, ln, off))
    return out


def resolve(motif, last_len=8):
    """End the phrase on a long chord tone."""
    out = list(motif)
    st, ln, off = out[-1]
    target = min((0, 2, 4, 7), key=lambda c: abs(c - off))
    out[-1] = (st, max(ln, last_len), target)
    return out


def play_motif(song: Song, track, name, fn, motif, bar0, degs, root, scale, octave=0, gain=1.0,
               gate=0.92, lo=-4, hi=16):
    for (st, ln, off) in motif:
        b = st // 16
        d = degs[b % len(degs)] + off
        while d > hi:
            d -= 7
        while d < lo:
            d += 7
        song.play(track, name, fn, deg_to_midi(root, scale, d) + 12 * octave, bar0 + b, st % 16, ln * gate, gain)


# --------------------------------------------------------------------------------------------
# station 1 - NEON TIDE FM (synthwave)
# --------------------------------------------------------------------------------------------

def synthwave(cfg):
    s = Song(cfg["bpm"], 16, cfg["seed"])
    r, root, scale = s.r, cfg["root"], MINOR
    prog = cfg["prog"]                                                   # 16 chord degrees
    k, sn, hc, ho = kick(155.0, 46.0, 0.035, 0.2), snare(180.0, 1200.0, 9000.0, 0.16, 0.5), hat(0.02), hat(0.16, 6000.0, 12)
    cr = crash()
    s.pattern("kick", k, "X...X...X...X...", is_kick=True)
    s.pattern("snare", sn, "....X.......X...")
    s.pattern("hat", hc, "x-x-x-x-x-x-x-x-", human=0.08)
    s.pattern("hat", ho, "..............x.", 0.7, bars=[3, 7, 11, 15])
    for b in (0, 8):
        s.put("crash", cr, b, 0, 1.0)
    for i, (st, f) in enumerate(((8, 150.0), (10, 125.0), (12, 100.0), (14, 82.0))):   # tom fill
        s.put("tom", tom(f), 15, st, 0.9)
        if cfg.get("fill2"):
            s.put("tom", tom(f * 1.2), 7, st, 0.7)

    bass_fn = lambda f, d: synth(f, d, "saw", 30, (1400.0, 260.0, 0.07), 0.6, (0.003, 0.08, 0.5, 0.03), (-6.0, 6.0), 0.5)
    pad_fn = lambda f, d: synth(f, d, "saw", 30, (1500.0, 1100.0, 1.0), 0.0, (0.25, 0.6, 0.8, 0.5), (-11.0, 0.0, 10.0))
    arp_fn = lambda f, d: synth(f, d, "saw", 30, (4200.0, 700.0, 0.09), 0.5, (0.002, 0.1, 0.25, 0.08), (-5.0, 5.0))
    lead_fn = lambda f, d: synth(f, d, "square", 30, (3600.0, 1900.0, 0.2), 0.3, (0.012, 0.15, 0.75, 0.1), (-4.0, 4.0), 0.0, (5.4, 0.006))

    bass_pat = cfg.get("bass_pat", "x.xxx.xxx.xxx.xx")
    for b in range(16):
        d = prog[b]
        base = deg_to_midi(root, scale, d) - 24
        for st, ch in enumerate(bass_pat):
            if ch == ".":
                continue
            octave = 12 if st in cfg.get("bass_oct", (6, 14)) else 0
            s.play("bass", "bass", bass_fn, base + octave, b, st, 0.85, 1.0 if st % 4 == 0 else 0.78)
        for m in chord(root, scale, d, (0, 2, 4, 6) if b % 4 != 3 else (0, 2, 4, 8)):
            s.play("pad", "pad", pad_fn, m, b, 0, 16, 1.0)
        if b >= 4:
            tones = chord(root, scale, d, (0, 2, 4, 7)) + [deg_to_midi(root, scale, d + 9)]
            order = cfg.get("arp_order", (0, 1, 2, 3, 4, 3, 2, 1))
            for st in range(0, 16, 2):
                s.play("arp", "arp", arp_fn, tones[order[(st // 2) % len(order)]] + 12, b, st, 1.6, 0.9 if st % 4 == 0 else 0.7)

    cell_a = make_motif(r, cfg["rhythm_a"], 32)
    cell_b = resolve(make_motif(r, cfg["rhythm_b"], 32, start=4))
    phrase = [(8, cell_a), (10, cell_b), (12, vary(r, cell_a)), (14, resolve(vary(r, cell_b), 10))]
    for (bar0, cell) in phrase:
        play_motif(s, "lead", "lead", lead_fn, cell, bar0, [prog[bar0], prog[bar0 + 1]], root, scale, 1, 1.0)
    answer = [(st, ln, off) for (st, ln, off) in cell_a if st % 4 == 0]          # sparse echo in part A
    for bar0 in (4, 6):
        play_motif(s, "lead2", "arp", arp_fn, answer, bar0, [prog[bar0], prog[bar0 + 1]], root, scale, 2, 0.8)

    s.fx("snare", lambda x: reverb_circ(x, 1.1, 0.5, 401, MSR, lp_hz=6000.0, hp_hz=300.0))
    s.fx("arp", lambda x: echo_circ(x, s.steps(3), 0.45, 5, MSR, 3500.0, 0.4))
    s.fx("lead", lambda x: reverb_circ(echo_circ(x, s.steps(3), 0.4, 4, MSR, 3000.0, 0.3), 1.6, 0.35, 402, MSR, lp_hz=5000.0))
    s.fx("lead2", lambda x: reverb_circ(echo_circ(x, s.steps(6), 0.5, 4, MSR, 2500.0, 0.5), 1.6, 0.5, 403, MSR))
    s.fx("pad", lambda x: reverb_circ(x, 2.2, 0.5, 404, MSR, lp_hz=4500.0))
    s.fx("tom", lambda x: reverb_circ(x, 1.0, 0.4, 405, MSR))
    s.sidechain(["bass", "pad", "arp"], 0.55, 0.14)
    return s.mix({"kick": -11.0, "snare": -14.0, "hat": -24.0, "crash": -22.0, "tom": -17.0, "bass": -14.0,
                  "pad": -19.0, "arp": -21.0, "lead": -16.5, "lead2": -22.0}, 1.4)


# --------------------------------------------------------------------------------------------
# station 2 - LOW TIDE LOUNGE (lo-fi hip-hop)
# --------------------------------------------------------------------------------------------

def lofi(cfg):
    s = Song(cfg["bpm"], 12, cfg["seed"], swing=0.3)
    r, root, scale = s.r, cfg["root"], cfg.get("scale", MAJOR)
    prog = cfg["prog"]                                                   # 12 chord degrees
    k = lp(kick(120.0, 44.0, 0.04, 0.22, 0.1, 1.2), 2500.0, 2, MSR)
    sn = lp(snare(170.0, 900.0, 6000.0, 0.09, 0.7, 21), 5200.0, 2, MSR)
    hc, rm = lp(hat(0.018, 5500.0, 22, metal=0.1), 9000.0, 2, MSR), rim(23)
    kick_pats = cfg.get("kick_pats", ("X.....x...X.....", "X.....x..x.X...."))
    for b in range(12):
        s.pattern("kick", k, kick_pats[b % len(kick_pats)], bars=[b], is_kick=True)
    s.pattern("snare", sn, "....X.......X...", human=0.1)
    s.pattern("rim", rm, ".......o......o.", 0.6, bars=[1, 3, 5, 7, 9, 11])
    s.pattern("hat", hc, "x.x-x.xox.x-x.xo", human=0.25)

    keys_fn = lambda f, d: epiano(f, d, 0.8)
    bass_fn = lambda f, d: synth(f, d, "tri", 8, (900.0, 500.0, 0.2), 0.0, (0.01, 0.2, 0.7, 0.08), (0.0,), 0.6)
    lead_fn = lambda f, d: epiano(f, d, 1.3)
    for b in range(12):
        d = prog[b]
        tones = chord(root, scale, d, (0, 2, 4, 6, 8))
        voicing = [tones[0] - 12, tones[2] - 12, tones[3] - 12, tones[1], tones[4]]      # open 9th voicing
        for i, m in enumerate(voicing):
            s.play("keys", "keys", keys_fn, m, b, 0 + i * 0.18, 9.0, 0.9)                # rolled chord
            s.play("keys", "keys", keys_fn, m, b, 10 + i * 0.12, 5.0, 0.6)
        base = deg_to_midi(root, scale, d) - 24
        s.play("bass", "bass", bass_fn, base, b, 0, 5.0, 1.0)
        s.play("bass", "bass", bass_fn, base, b, 6, 2.0, 0.8)
        s.play("bass", "bass", bass_fn, base + (7 if b % 2 == 0 else 12), b, 10, 3.0, 0.85)
        nxt = deg_to_midi(root, scale, prog[(b + 1) % 12]) - 24
        s.play("bass", "bass", bass_fn, nxt - 1 if b % 2 else nxt + 2, b, 14, 1.6, 0.7)  # approach tone

    cell_a = make_motif(r, cfg["rhythm_a"], 32, span=(-2, 8), max_len=5)
    cell_b = resolve(make_motif(r, cfg["rhythm_b"], 32, span=(-2, 8), start=2, max_len=5), 6)
    for (bar0, cell) in ((2, cell_a), (4, cell_b), (6, vary(r, cell_a, 0.4, (-2, 8))), (8, resolve(vary(r, cell_b, 0.3, (-2, 8)), 8)), (10, cell_a[:max(2, len(cell_a) // 2)])):
        play_motif(s, "lead", "lead", lead_fn, cell, bar0, [prog[bar0], prog[bar0 + 1]], root, scale, 1, 1.0, 0.95)

    crackle = np.zeros(s.n)
    idx = r.randint(0, s.n, 420)
    crackle[idx] = r.choice([-1.0, 1.0], 420) * r.uniform(0.05, 1.0, 420) ** 3
    crackle = bp(crackle, 1200.0, 7000.0, 2, MSR) + 0.02 * colored(s.n, r, -2.0, 300.0, 6000.0, MSR) * 0.05
    s.tracks["vinyl"] = crackle

    s.fx("keys", lambda x: reverb_circ(x, 1.2, 0.3, 411, MSR, lp_hz=3500.0))
    s.fx("lead", lambda x: reverb_circ(echo_circ(x, s.steps(6), 0.35, 3, MSR, 2200.0, 0.35), 1.5, 0.4, 412, MSR, lp_hz=4000.0))
    s.fx("snare", lambda x: reverb_circ(x, 0.5, 0.2, 413, MSR, lp_hz=4000.0))
    s.sidechain(["keys", "bass", "lead"], 0.35, 0.18)
    x = s.mix({"kick": -12.0, "snare": -16.0, "rim": -24.0, "hat": -27.0, "keys": -17.0, "bass": -14.5,
               "lead": -18.5, "vinyl": -36.0}, 1.6)
    # tape character: gentle wow (pitch drift), rolled-off top, a little hum-free warmth
    cycles = 5
    wob = 0.0011 * MSR * np.sin(TAU * cycles * np.arange(s.n) / s.n) + 0.0003 * MSR * np.sin(TAU * 37 * np.arange(s.n) / s.n)
    src_idx = (np.arange(s.n) + wob) % s.n
    i0 = np.floor(src_idx).astype(np.int64)
    frac = src_idx - i0
    x = x[i0 % s.n] * (1.0 - frac) + x[(i0 + 1) % s.n] * frac
    return spec_filter(x, g_mul(g_lp(6200.0, 2), g_hp(35.0, 2)), MSR)


# --------------------------------------------------------------------------------------------
# station 3 - BOOGIE BAY 98.7 (funk / disco)
# --------------------------------------------------------------------------------------------

def disco(cfg):
    s = Song(cfg["bpm"], 16, cfg["seed"])
    r, root, scale = s.r, cfg["root"], cfg.get("scale", DORIAN)
    prog = cfg["prog"]
    k, sn, cl = kick(150.0, 52.0, 0.028, 0.15, 0.35, 1.5), snare(200.0, 1600.0, 10000.0, 0.09, 0.45, 31), clap(32)
    hc, ho, sh = hat(0.016, 7000.0, 33), hat(0.11, 6000.0, 34), shaker(35)
    s.pattern("kick", k, "X...X...X...X...", is_kick=True)
    s.pattern("snare", sn, "....X.......X...")
    s.pattern("clap", cl, "....X.......X...")
    s.pattern("hat", hc, "x-o-x-o-x-o-x-o-", human=0.1)
    s.pattern("ohat", ho, "..x...x...x...x.")
    s.pattern("shaker", sh, "o-x-o-x-o-x-o-x-", human=0.15)
    s.pattern("kick", k, "...........x..x.", bars=[7, 15])
    for b in (0, 8):
        s.put("crash", crash(36, 0.6), b, 0, 1.0)

    bass_fn = lambda f, d: synth(f, d, "square", 24, (1900.0, 320.0, 0.06), 0.8, (0.003, 0.07, 0.45, 0.03), (-4.0, 4.0), 0.35)
    chick_fn = lambda f, d: synth(f, d, "saw", 28, (5200.0, 1500.0, 0.03), 0.3, (0.002, 0.035, 0.0, 0.02), (0.0,))
    str_fn = lambda f, d: synth(f, d, "saw", 28, (2600.0, 2000.0, 0.8), 0.0, (0.18, 0.5, 0.85, 0.35), (-9.0, 0.0, 9.0), 0.0, (5.0, 0.003))
    brass_fn = lambda f, d: synth(f, d, "saw", 34, (900.0, 3400.0, 0.05), 0.2, (0.02, 0.12, 0.7, 0.07), (-7.0, 7.0))
    lead_fn = lambda f, d: synth(f, d, "square", 30, (2400.0, 1500.0, 0.1), 0.9, (0.004, 0.09, 0.6, 0.06), (0.0,), 0.0, (5.8, 0.004))

    bass_pats = cfg.get("bass_pats", ("R.o.R.oRR.o.RaoR", "R.o.R.oRR.oRo.aR"))
    chick_pat = cfg.get("chick_pat", "..x.x..x..x.x.x.")
    for b in range(16):
        d = prog[b]
        base = deg_to_midi(root, scale, d) - 24
        pat = bass_pats[b % len(bass_pats)]
        for st, ch in enumerate(pat):
            if ch == ".":
                continue
            note = base + {"R": 0, "o": 12, "a": 10 if scale is DORIAN else 7}[ch]
            s.play("bass", "bass", bass_fn, note, b, st, 0.8 if ch != "R" else 1.3, 1.0 if ch == "R" else 0.8)
        tones = chord(root, scale, d, (2, 4, 6, 7))
        for st, ch in enumerate(chick_pat):
            if ch == "x":
                for m in tones:
                    s.play("chick", "chick", chick_fn, m + 12, b, st, 0.6, 0.9)
        for m in chord(root, scale, d, (4, 7, 9)):
            s.play("strings", "str", str_fn, m + 12, b, 0, 16, 1.0)
        if b % 4 == 3:                                                   # brass punctuation
            for (st, ln) in ((8, 1.5), (11, 1.5), (14, 2.0)):
                for m in chord(root, scale, d, (0, 2, 4, 6)):
                    s.play("brass", "brass", brass_fn, m + 12, b, st, ln, 1.0)

    cell_a = make_motif(r, cfg["rhythm_a"], 32, span=(-2, 9), max_len=4)
    cell_b = resolve(make_motif(r, cfg["rhythm_b"], 32, span=(-2, 9), start=4, max_len=4), 6)
    for (bar0, cell) in ((8, cell_a), (10, cell_b), (12, vary(r, cell_a)), (14, resolve(vary(r, cell_b), 8))):
        play_motif(s, "lead", "lead", lead_fn, cell, bar0, [prog[bar0], prog[bar0 + 1]], root, scale, 1, 1.0, 0.8)
    for (bar0, cell) in ((0, cell_a), (4, cell_a)):                      # call figure in part A
        short = [n for n in cell if n[0] < 16]
        play_motif(s, "lead", "lead", lead_fn, short, bar0 + 2, [prog[bar0 + 2]], root, scale, 1, 0.7, 0.8)

    s.fx("chick", lambda x: hp(x, 500.0, 2, MSR))
    s.fx("strings", lambda x: reverb_circ(hp(x, 300.0, 2, MSR), 1.8, 0.4, 421, MSR, lp_hz=6000.0))
    s.fx("clap", lambda x: reverb_circ(x, 0.7, 0.3, 422, MSR, lp_hz=6000.0, hp_hz=400.0))
    s.fx("brass", lambda x: reverb_circ(x, 0.9, 0.25, 423, MSR))
    s.fx("lead", lambda x: reverb_circ(echo_circ(x, s.steps(3), 0.3, 3, MSR, 3500.0, 0.25), 0.9, 0.25, 424, MSR))
    s.sidechain(["bass", "strings"], 0.35, 0.1)
    return s.mix({"kick": -11.5, "snare": -17.0, "clap": -17.0, "hat": -26.0, "ohat": -23.0, "shaker": -28.0,
                  "crash": -23.0, "bass": -13.5, "chick": -21.0, "strings": -22.0, "brass": -18.0, "lead": -17.0}, 1.4)


# --------------------------------------------------------------------------------------------
# station 4 - BREAKWATER (drum and bass)
# --------------------------------------------------------------------------------------------

def dnb(cfg):
    s = Song(cfg["bpm"], 24, cfg["seed"])
    r, root, scale = s.r, cfg["root"], MINOR
    prog = cfg["prog"]                                                   # 24 chord degrees
    k = kick(190.0, 52.0, 0.022, 0.13, 0.4, 1.8, 0.35)
    sn = snare(215.0, 1500.0, 12000.0, 0.085, 0.75, 41, 0.26)
    gh = snare(240.0, 2000.0, 9000.0, 0.04, 0.4, 42, 0.12)
    hc, ho, sh, rd = hat(0.014, 7500.0, 43), hat(0.09, 6500.0, 44), shaker(45), hat(0.2, 5000.0, 46, 0.5, 0.8)
    breakdown = (16, 17)
    build = (18, 19)
    for b in range(24):
        if b in breakdown:
            s.pattern("hat", hc, "x.o.x.o.x.o.x.o.", bars=[b])
            continue
        if b in build:
            roll = "x.x.x.x.x.x.x.x." if b == 18 else "xxxxxxxxXXXXXXXX"
            for st, ch in enumerate(roll):
                if ch in VEL:
                    ramp = (st + (16 if b == 19 else 0)) / 32.0
                    s.put("snare", sn, b, st, (0.25 + 0.75 * ramp) * VEL[ch])
            s.pattern("kick", k, "X.......X.......", bars=[b], is_kick=True)
            continue
        kp = "X.........X....." if b % 4 != 3 else "X.....x...X..x.."
        s.pattern("kick", k, kp, bars=[b], is_kick=True)
        s.pattern("snare", sn, "....X.......X...", bars=[b])
        s.pattern("ghost", gh, ".......o.o.....o" if b % 2 == 0 else "..o....o......o.", bars=[b], human=0.2)
        s.pattern("hat", hc, "x-x-x-xox-x-x-xo", bars=[b], human=0.15)
        s.pattern("shaker", sh, "..o...o...o...o.", bars=[b])
        if b >= 8:
            s.pattern("ride", rd, "x...x...x...x...", bars=[b], gain=0.8)
        if b % 4 == 3:
            s.put("ohat", ho, b, 14, 0.9)
    for b in (0, 8, 20):
        s.put("crash", crash(47, 0.8), b, 0, 1.0)

    def reese(f, d):
        x = synth(f, d, "saw", 26, (700.0, 420.0, 0.25), 0.4, (0.006, 0.2, 0.9, 0.05), (-19.0, 0.0, 17.0), 0.9)
        return soft_clip(x, 2.0)
    pad_fn = lambda f, d: synth(f, d, "saw", 26, (2200.0, 1600.0, 1.2), 0.0, (0.5, 0.8, 0.8, 0.7), (-12.0, 0.0, 12.0))
    pluck_fn = lambda f, d: synth(f, d, "square", 26, (4800.0, 900.0, 0.06), 0.6, (0.002, 0.08, 0.15, 0.06), (-5.0, 5.0))
    stab_fn = lambda f, d: synth(f, d, "saw", 30, (3800.0, 1200.0, 0.08), 0.4, (0.003, 0.1, 0.3, 0.08), (-8.0, 8.0))

    bass_pat = cfg.get("bass_pat", ("L.....S...L.....", "L.....S...L..S.."))
    for b in range(24):
        d = prog[b]
        base = deg_to_midi(root, scale, d) - 24
        if b not in breakdown:
            pat = bass_pat[b % len(bass_pat)]
            for st, ch in enumerate(pat):
                if ch == "L":
                    s.play("bass", "reese", reese, base, b, st, 5.5, 1.0)
                elif ch == "S":
                    s.play("bass", "reese", reese, base + (12 if (b + st) % 3 == 0 else 0), b, st, 2.5, 0.85)
        else:
            s.play("bass", "reese", reese, base, b, 0, 15.0, 0.6)
        if b % 2 == 0:
            for m in chord(root, scale, d, (0, 2, 4, 6)):
                s.play("pad", "pad", pad_fn, m, b, 0, 32, 1.0)

    arp_cell = make_motif(r, cfg["rhythm_a"], 32, span=(0, 9), max_len=2)
    for b in range(0, 24, 2):
        if b in (18,):
            continue
        cell = arp_cell if (b // 2) % 4 != 3 else vary(r, arp_cell, 0.5, (0, 9))
        play_motif(s, "pluck", "pluck", pluck_fn, cell, b, [prog[b], prog[b + 1]], root, scale, 1, 0.9 if b >= 8 else 0.6, 0.8)
    stab_pat = cfg.get("stab_pat", "X.....x...x.....")
    for b in range(8, 24):
        if b in breakdown or b in build or b % 2 == 1:
            continue
        for st, ch in enumerate(stab_pat):
            if ch in VEL:
                for m in chord(root, scale, prog[b], (0, 2, 4)):
                    s.play("stab", "stab", stab_fn, m + 12, b, st, 1.5, VEL[ch])

    s.fx("bass", lambda x: lp(x, 2400.0, 2, MSR))
    s.fx("pad", lambda x: reverb_circ(hp(x, 350.0, 2, MSR), 2.4, 0.6, 431, MSR, lp_hz=6000.0))
    s.fx("pluck", lambda x: reverb_circ(echo_circ(x, s.steps(3), 0.5, 5, MSR, 4000.0, 0.45), 1.4, 0.3, 432, MSR))
    s.fx("stab", lambda x: reverb_circ(echo_circ(x, s.steps(6), 0.4, 3, MSR, 3000.0, 0.3), 1.2, 0.35, 433, MSR))
    s.fx("snare", lambda x: reverb_circ(x, 0.6, 0.18, 434, MSR, hp_hz=500.0))
    s.sidechain(["bass", "pad"], 0.45, 0.08)
    return s.mix({"kick": -11.0, "snare": -12.5, "ghost": -24.0, "hat": -24.0, "ohat": -24.0, "shaker": -28.0,
                  "ride": -27.0, "crash": -23.0, "bass": -13.0, "pad": -21.0, "pluck": -20.0, "stab": -20.0}, 1.6)


# --------------------------------------------------------------------------------------------
# station 5 - HALCYON DRIFT (ambient / chill)
# --------------------------------------------------------------------------------------------

def ambient(cfg):
    s = Song(cfg["bpm"], 12, cfg["seed"])
    r, root, scale = s.r, cfg["root"], cfg.get("scale", LYDIAN)
    prog = cfg["prog"]                                                   # 6 chords, two bars each
    pad_fn = lambda f, d: synth(f, d, "saw", 22, (700.0, 1500.0, 2.5), 0.0, (2.2, 1.0, 0.85, 2.6), (-13.0, -4.0, 5.0, 12.0))
    sub_fn = lambda f, d: synth(f, d, "tri", 4, (400.0, 400.0, 1.0), 0.0, (1.5, 1.0, 0.9, 2.0), (0.0,))
    bell_fn = lambda f, d: fm_bell(f, 3.2, 1.3, 3.5, 1.8)
    keys_fn = lambda f, d: epiano(f, d, 0.6)
    glass_fn = lambda f, d: fm_bell(f, 2.4, 0.9, 2.0, 0.9)
    for i, d in enumerate(prog):
        b = i * 2
        for m in chord(root, scale, d, (0, 4, 6, 8, 9)):
            s.play("pad", "pad", pad_fn, m, b, 0, 30, 1.0)
        s.play("sub", "sub", sub_fn, deg_to_midi(root, scale, d) - 24, b, 0, 30, 1.0)
        tones = chord(root, scale, d, (0, 2, 4, 6, 8))
        t_steps = sorted(r.choice(np.arange(0, 32, 2), cfg.get("bell_density", 4), replace=False))
        for st in t_steps:                                               # slow bell constellation
            m = tones[int(r.randint(0, len(tones)))] + 12 * int(r.choice([1, 1, 2]))
            s.play("bell", "bell", bell_fn, m, b + st // 16, st % 16, 8, r.uniform(0.5, 1.0))
    cell_a = make_motif(r, cfg["rhythm_a"], 32, span=(0, 9), max_len=8)
    cell_b = resolve(make_motif(r, cfg["rhythm_b"], 32, span=(0, 9), start=4, max_len=8), 10)
    for (bar0, cell) in ((4, cell_a), (6, cell_b), (8, vary(r, cell_a, 0.3, (0, 9))), (10, resolve(cell_b, 12))):
        degs = [prog[bar0 // 2], prog[bar0 // 2]]
        play_motif(s, "keys", "keys", keys_fn, cell, bar0, degs, root, scale, 1, 1.0, 1.0)
    for (bar0, cell) in ((0, cell_a), (2, cell_b)):
        thin = [n for i, n in enumerate(cell) if i % 2 == 0]
        play_motif(s, "glass", "glass", glass_fn, thin, bar0, [prog[bar0 // 2]] * 2, root, scale, 2, 0.8, 1.0)

    air = colored(s.n, r, -3.0, 400.0, 9000.0, MSR) * (0.5 + 0.5 * slow_noise(s.n, r, 0.12, MSR))
    s.tracks["air"] = air
    pulse = kick(90.0, 42.0, 0.05, 0.25, 0.0, 1.0, 0.5)
    if cfg.get("pulse", True):
        s.pattern("pulse", lp(pulse, 300.0, 2, MSR), "X.......o.......", bars=range(4, 12))
        s.pattern("shaker", shaker(51), "....o.......o.-.", bars=range(4, 12), human=0.2)

    s.fx("pad", lambda x: reverb_circ(x, 4.0, 0.9, 441, MSR, lp_hz=5000.0))
    s.fx("bell", lambda x: reverb_circ(echo_circ(x, s.steps(6), 0.55, 6, MSR, 3500.0, 0.5), 4.5, 0.9, 442, MSR, lp_hz=7000.0))
    s.fx("keys", lambda x: reverb_circ(echo_circ(x, s.steps(8), 0.45, 4, MSR, 2500.0, 0.4), 3.5, 0.7, 443, MSR, lp_hz=4500.0))
    s.fx("glass", lambda x: reverb_circ(echo_circ(x, s.steps(6), 0.5, 5, MSR, 4000.0, 0.5), 4.0, 0.9, 444, MSR))
    s.fx("shaker", lambda x: reverb_circ(x, 1.5, 0.5, 445, MSR))
    return s.mix({"pad": -15.0, "sub": -17.0, "bell": -21.0, "keys": -18.0, "glass": -22.0, "air": -38.0,
                  "pulse": -19.0, "shaker": -33.0}, 1.1)


# --------------------------------------------------------------------------------------------
# station table (ids must match gta/resources/registries/radio_registry.gd)
# --------------------------------------------------------------------------------------------

STATIONS = [
    {"id": "neon_tide", "name": "Neon Tide FM", "genre": "Synthwave", "fn": synthwave, "tracks": [
        {"bpm": 100.0, "seed": "neon_tide_1", "root": 57,                # A minor: i VI III VII
         "prog": [0, 5, 2, 6, 0, 5, 2, 6, 5, 6, 0, 0, 0, 5, 2, 6],
         "rhythm_a": [0, 4, 6, 8, 12, 16, 22, 24, 28], "rhythm_b": [0, 3, 6, 8, 14, 16, 20, 24]},
        {"bpm": 104.0, "seed": "neon_tide_2", "root": 52,                # E minor: i iv VI VII
         "prog": [0, 3, 5, 6, 0, 3, 5, 4, 5, 6, 0, 2, 0, 3, 5, 6], "fill2": True,
         "bass_pat": "x.x.x.xxx.x.x.xx", "bass_oct": (7, 15), "arp_order": (0, 2, 1, 3, 2, 4, 3, 1),
         "rhythm_a": [0, 2, 4, 8, 11, 14, 16, 20, 24, 27, 30], "rhythm_b": [0, 6, 8, 12, 16, 19, 22, 24]},
    ]},
    {"id": "low_tide", "name": "Low Tide Lounge", "genre": "Lo-fi Hip-Hop", "fn": lofi, "tracks": [
        {"bpm": 78.0, "seed": "low_tide_1", "root": 53, "scale": MAJOR,  # F major: ii7 V7 Imaj7 vi7
         "prog": [1, 4, 0, 5, 1, 4, 0, 5, 3, 2, 1, 4],
         "rhythm_a": [0, 6, 10, 14, 16, 22, 26], "rhythm_b": [2, 6, 8, 14, 18, 24]},
        {"bpm": 72.0, "seed": "low_tide_2", "root": 50, "scale": DORIAN,  # D dorian: i7 IV7 ...
         "prog": [0, 3, 0, 3, 5, 4, 0, 3, 2, 3, 0, 4],
         "kick_pats": ("X.......x.X.....", "X..x......X...x."),
         "rhythm_a": [0, 3, 8, 12, 14, 20, 24, 28], "rhythm_b": [0, 6, 12, 16, 22, 26]},
    ]},
    {"id": "boogie_bay", "name": "Boogie Bay 98.7", "genre": "Funk / Disco", "fn": disco, "tracks": [
        {"bpm": 116.0, "seed": "boogie_bay_1", "root": 52, "scale": DORIAN,   # E dorian vamp
         "prog": [0, 0, 3, 3, 0, 0, 3, 3, 2, 3, 0, 0, 2, 3, 4, 4],
         "rhythm_a": [0, 2, 3, 6, 8, 11, 14, 16, 18, 22, 24, 27], "rhythm_b": [0, 3, 6, 8, 10, 14, 16, 22, 24]},
        {"bpm": 120.0, "seed": "boogie_bay_2", "root": 57, "scale": MINOR,    # A minor: i VII VI v
         "prog": [0, 0, 6, 6, 5, 5, 4, 4, 0, 0, 6, 6, 5, 5, 4, 6],
         "bass_pats": ("R..oR.o.R.oRR.ao", "R.o.RoR.R.o.RaoR"), "chick_pat": "x..x..x.x..x.x..",
         "rhythm_a": [0, 3, 6, 8, 12, 14, 16, 19, 22, 24, 28], "rhythm_b": [2, 4, 6, 8, 12, 16, 20, 22, 24]},
    ]},
    {"id": "breakwater", "name": "Breakwater", "genre": "Drum & Bass", "fn": dnb, "tracks": [
        {"bpm": 172.0, "seed": "breakwater_1", "root": 53,               # F minor
         "prog": [0, 0, 5, 5, 2, 2, 6, 6] * 3,
         "rhythm_a": [0, 3, 6, 8, 11, 14, 16, 19, 22, 24, 27, 30]},
        {"bpm": 174.0, "seed": "breakwater_2", "root": 50,               # D minor
         "prog": [0, 0, 3, 3, 5, 5, 4, 4] * 3, "stab_pat": "X..x....x.....x.",
         "bass_pat": ("L.......S.L.....", "L.....S...L...S."),
         "rhythm_a": [0, 2, 6, 8, 12, 14, 16, 18, 22, 24, 28, 30]},
    ]},
    {"id": "drift", "name": "Halcyon Drift", "genre": "Ambient / Chill", "fn": ambient, "tracks": [
        {"bpm": 70.0, "seed": "drift_1", "root": 48, "scale": LYDIAN,    # C lydian
         "prog": [0, 1, 2, 0, 4, 1],
         "rhythm_a": [0, 8, 14, 16, 24], "rhythm_b": [0, 6, 12, 20]},
        {"bpm": 66.0, "seed": "drift_2", "root": 53, "scale": MAJOR, "pulse": False, "bell_density": 5,   # F major
         "prog": [0, 5, 3, 0, 2, 4],
         "rhythm_a": [0, 6, 12, 16, 22, 28], "rhythm_b": [4, 8, 16, 24]},
    ]},
]


def track_ids():
    return ["radio_%s_%d" % (st["id"], i + 1) for st in STATIONS for i in range(len(st["tracks"]))]


def render(track_id: str) -> np.ndarray:
    for st in STATIONS:
        for i, cfg in enumerate(st["tracks"]):
            if track_id == "radio_%s_%d" % (st["id"], i + 1):
                return st["fn"](cfg)
    raise KeyError(track_id)


def describe(track_id: str) -> dict:
    for st in STATIONS:
        for i, cfg in enumerate(st["tracks"]):
            if track_id == "radio_%s_%d" % (st["id"], i + 1):
                return {"station": st["name"], "genre": st["genre"], "bpm": cfg["bpm"], "root": cfg["root"]}
    return {}
