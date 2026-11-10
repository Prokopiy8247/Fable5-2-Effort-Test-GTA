"""HALCYON BAY - seamless loops: engines, rotors, sirens, tyre/metal loops and ambience beds.

Seamlessness is by construction, never by a crossfade patch:
  * every tone runs a whole number of cycles over the loop (`pphase` scales swept tones),
  * noise is shaped with circular FFT filters (periodic over the loop length),
  * events (engine firings, bird calls, clanks) are mixed with wrap-around (`add_wrap`),
  * envelopes are folded around the loop (`cenv`) and reverb is a circular convolution.
The synth tool still measures the seam of every file and prints it.
"""
from __future__ import annotations

import math

import numpy as np

from dsp import (SR, TAU, add_wrap, additive, band_noise, bell, bp, colored, env_ad, env_exp,
                 formant_filter, g_bell, g_bp, g_hp, g_lp, g_mul, g_sum, g_tilt, hann, lp, hp,
                 modal, norm, peak, phase_of, reverb_circ, rms, saw_amps, secs, slow_noise,
                 smoothstep, soft_clip, spec_filter, square_amps, tt, white, echo_circ)
from sfx import sound, voice, bird_chirp, gull_call, click, ping, thump, nburst, bell_note


def cenv(n: int, center: float, shape, before: float, after: float) -> np.ndarray:
    """Envelope event folded around the loop. shape(d) with d = seconds from `center`."""
    d = np.arange(-secs(before), secs(after)) / SR
    out = np.zeros(n)
    add_wrap(out, shape(d), int(round((center - before) * SR)))
    return out


def asym(attack: float, decay: float):
    return lambda d: np.where(d < 0.0, np.exp(-(d / attack) ** 2 * 3.0), np.exp(-np.maximum(d, 0.0) / decay))


def gauss(width: float):
    return lambda d: np.exp(-0.5 * (d / width) ** 2)


def pphase_freq(freq: np.ndarray) -> np.ndarray:
    """Scale a per-sample frequency curve so it completes a whole number of cycles."""
    total = float(np.sum(freq)) / SR
    return freq * (round(total) / total)


def wrap_event(buf: np.ndarray, sig: np.ndarray, t: float, gain: float = 1.0) -> None:
    add_wrap(buf, sig, int(round(t * SR)), gain)


def impulses(n: int, r, count: int, lo: float, hi: float, gain_pow: float = 2.0) -> np.ndarray:
    """Random impulse train band-passed to [lo, hi] = many tiny clicks (rain drops, crackle)."""
    imp = np.zeros(n)
    idx = r.randint(0, n, count)
    imp[idx] += r.choice([-1.0, 1.0], count) * r.uniform(0.05, 1.0, count) ** gain_pow
    return bp(imp, lo, hi)


# --------------------------------------------------------------------------------------------
# engines: granular firing-pulse model
# --------------------------------------------------------------------------------------------

def engine(r, dur, fire_hz, cyl, res, spread=0.12, timing=None, jitter=0.012, amp_var=0.07,
           snap=(0.4, 1.4), noise=(0.25, 300.0, 3500.0), gate_ms=7.0, shape=None, drive=1.6,
           hiss=0.0):
    """Granular firing-pulse engine. Every cylinder firing excites a set of damped exhaust /
    block resonances `res` = [(freq, tau, gain), ...] plus a short broadband combustion snap
    (`snap` = (gain, milliseconds)); cylinders differ slightly in level, tuning and timing
    (that is where the half-order burble comes from) and every firing gets a little random
    variation, so the loop is rich in harmonics yet never sounds like a single-cycle buzz.
    Firing-synchronous noise adds intake / valve-train texture. Exactly `dur` seconds long,
    with a whole number of engine cycles, so it loops seamlessly and pitch-shifts cleanly."""
    n = secs(dur)
    fires = int(round(fire_hz * dur))
    fires -= fires % cyl
    period = n / fires
    buf = np.zeros(n)
    gate = np.zeros(n)
    c_amp = 1.0 + spread * r.uniform(-1.0, 1.0, cyl)
    c_tune = 1.0 + 0.05 * r.uniform(-1.0, 1.0, cyl)
    c_off = np.zeros(cyl) if timing is None else np.asarray(timing, dtype=np.float64)
    length = secs(max(tau for (_f, tau, _g) in res) * 7.0)
    tp = tt(length)
    g_len = secs(gate_ms / 1000.0)
    g_win = hann(g_len)
    s_len = secs(snap[1] / 1000.0)
    s_win = np.sin(TAU * np.arange(s_len) / s_len) * hann(s_len)        # one bipolar cycle
    for e in range(fires):
        c = e % cyl
        pos = int(round((e + c_off[c] + jitter * r.standard_normal()) * period))
        a = c_amp[c] * (1.0 + amp_var * r.standard_normal())
        pulse = np.zeros(length)
        for (f, tau, g) in res:
            pulse += g * np.exp(-tp / tau) * np.sin(TAU * f * c_tune[c] * (1.0 + 0.02 * r.standard_normal()) * tp)
        add_wrap(buf, pulse, pos, a)
        add_wrap(buf, s_win, pos, a * snap[0] * 2.0)
        add_wrap(gate, g_win, pos, a)
    x = norm(buf)
    if noise[0] > 0.0:
        x = x + noise[0] * norm(band_noise(n, r, noise[1], noise[2]) * gate)
    if hiss > 0.0:
        x = x + hiss * 0.2 * band_noise(n, r, 1500.0, 7000.0)
    if shape is not None:
        x = spec_filter(x, shape)
    return soft_clip(norm(x), drive)


@sound("engine_car_loop", ("rms", -17.0, -4.0), loop=True, family="engine")
def engine_car_loop(r):
    # inline four, mid revs (78 Hz firing): smooth, slightly boxy
    return engine(r, 2.0, 78.0, 4, [(165.0, 0.009, 1.0), (410.0, 0.0045, 0.6), (980.0, 0.0022, 0.35)],
                  snap=(0.45, 1.5), noise=(0.4, 350.0, 3600.0), drive=1.7,
                  shape=g_mul(g_sum(g_bell(240.0, 700.0, 1.0), g_bell(1000.0, 1800.0, 0.8), g_bell(2800.0, 3000.0, 0.45)),
                              g_tilt(3.5, 250.0), g_hp(48.0, 2), g_lp(7000.0, 2)))


@sound("engine_sport_loop", ("rms", -16.5, -4.0), loop=True, family="engine")
def engine_sport_loop(r):
    # six cylinders at 108 Hz firing: brighter, raspier, more exhaust bark
    return engine(r, 2.0, 108.0, 6, [(230.0, 0.007, 1.0), (640.0, 0.0032, 0.8), (1450.0, 0.0016, 0.5)],
                  spread=0.09, snap=(0.6, 0.9), noise=(0.45, 500.0, 5500.0), drive=2.8, hiss=0.35,
                  shape=g_mul(g_sum(g_bell(320.0, 700.0, 1.0), g_bell(1100.0, 1500.0, 1.0), g_bell(2800.0, 2800.0, 0.6)),
                              g_tilt(2.0, 300.0), g_hp(58.0, 2), g_lp(8000.0, 2)))


@sound("engine_truck_loop", ("rms", -16.5, -4.0), loop=True, family="engine")
def engine_truck_loop(r):
    # big diesel six at 51 Hz firing: heavy low end plus injector clatter
    n = secs(2.0)
    base = engine(r, 2.0, 51.0, 6, [(128.0, 0.012, 1.0), (310.0, 0.007, 0.8), (780.0, 0.003, 0.5)],
                  spread=0.2, snap=(0.6, 2.2), noise=(0.55, 1200.0, 4500.0), gate_ms=4.0, drive=2.2,
                  shape=g_mul(g_sum(g_bell(170.0, 480.0, 1.0), g_bell(650.0, 1100.0, 0.75), g_bell(2300.0, 2600.0, 0.5)),
                              g_tilt(2.6, 150.0), g_hp(38.0, 2), g_lp(6000.0, 2)))
    rumble = colored(n, r, -6.0, 40.0, 180.0) * (0.8 + 0.2 * slow_noise(n, r, 4.0))
    return base + 0.16 * rumble / (peak(rumble) + 1e-9)


@sound("engine_bike_loop", ("rms", -17.0, -4.0), loop=True, family="engine")
def engine_bike_loop(r):
    # twin with uneven firing at 88 Hz: buzzy, mid-forward
    return engine(r, 2.0, 88.0, 2, [(280.0, 0.006, 1.0), (820.0, 0.003, 0.9), (1900.0, 0.0014, 0.5)],
                  spread=0.2, timing=[0.0, 0.16], snap=(0.7, 0.8), noise=(0.5, 700.0, 6500.0), drive=3.2, hiss=0.3,
                  shape=g_mul(g_sum(g_bell(400.0, 800.0, 1.0), g_bell(1500.0, 2000.0, 1.0), g_bell(3400.0, 3000.0, 0.6)), g_hp(72.0, 2)))


@sound("engine_boat_loop", ("rms", -17.0, -4.0), loop=True, family="engine")
def engine_boat_loop(r):
    # three-cylinder outboard at 66 Hz with water gurgle around the exhaust
    n = secs(2.0)
    base = engine(r, 2.0, 66.0, 3, [(145.0, 0.012, 1.0), (480.0, 0.0045, 0.6), (1100.0, 0.002, 0.3)],
                  spread=0.18, snap=(0.45, 1.6), noise=(0.45, 300.0, 3000.0), drive=2.0,
                  shape=g_mul(g_sum(g_bell(200.0, 520.0, 1.0), g_bell(900.0, 1500.0, 0.75), g_bell(2600.0, 2800.0, 0.4)),
                              g_tilt(3.5, 220.0), g_hp(42.0, 2), g_lp(7000.0, 2)))
    gurgle = band_noise(n, r, 250.0, 1800.0) * (0.45 + 0.55 * np.abs(slow_noise(n, r, 13.0)))
    wash = band_noise(n, r, 1500.0, 6000.0) * (0.8 + 0.2 * slow_noise(n, r, 3.0))
    return base + 0.28 * gurgle / peak(gurgle) + 0.1 * wash / peak(wash)


@sound("heli_rotor_loop", ("rms", -15.5, -3.5), loop=True, family="engine")
def heli_rotor_loop(r):
    dur = 2.0
    n = secs(dur)
    t = tt(n)
    x = np.zeros(n)
    passes = 26                                                          # 13 Hz blade pass
    for i in range(passes):
        at = i * dur / passes + r.uniform(-0.0015, 0.0015)
        g = (1.0 if i % 2 == 0 else 0.88) * r.uniform(0.94, 1.0)
        wrap_event(x, thump(120.0, 70.0, 0.06, 0.02, 0.016, 0.006), at, 0.6 * g)        # low whop
        sw = colored(secs(0.07), r, -4.0, 110.0, 2400.0) * env_ad(secs(0.07), 0.009, 0.016)
        wrap_event(x, norm(sw), at - 0.004, 1.0 * g)                                    # blade slap
    x = norm(x)
    whine = (np.sin(TAU * 1486.0 * t) + 0.6 * np.sin(TAU * 2230.5 * t + 1.0) + 0.3 * np.sin(TAU * 4458.0 * t))
    whine *= 0.85 + 0.15 * slow_noise(n, r, 2.0)
    hiss = band_noise(n, r, 1200.0, 7000.0) * (0.75 + 0.25 * np.sin(TAU * 13.0 * t))
    tail = spec_filter(additive(96.0, n, saw_amps(28, 1.0)), g_bp(250.0, 1800.0))
    tail *= 0.7 + 0.3 * np.sin(TAU * 13.0 * t + 0.8)
    low = colored(n, r, -6.0, 30.0, 140.0)
    out = x + 0.1 * whine + 0.22 * hiss / peak(hiss) + 0.2 * norm(tail) + 0.08 * norm(low)
    return soft_clip(norm(out), 1.5)


@sound("plane_prop_loop", ("rms", -16.0, -4.0), loop=True, family="engine")
def plane_prop_loop(r):
    dur = 2.0
    n = secs(dur)
    t = tt(n)
    prop = additive(80.0, n, saw_amps(50, 0.5), phases=[0.0, 1.3, 2.1, 0.4])
    prop2 = additive(80.5, n, saw_amps(34, 0.6), phases=[0.9, 0.2, 1.7])                # slow beat
    prop = spec_filter(prop + 0.55 * prop2, g_mul(g_bp(60.0, 5000.0), g_sum(g_bell(300.0, 800.0, 1.0), g_bell(1500.0, 2600.0, 0.9))))
    eng = engine(r, dur, 60.0, 6, [(150.0, 0.009, 1.0), (420.0, 0.004, 0.6), (900.0, 0.002, 0.3)],
                 snap=(0.4, 1.4), noise=(0.3, 400.0, 3200.0), drive=1.6,
                 shape=g_mul(g_sum(g_bell(220.0, 600.0, 1.0), g_bell(1000.0, 1600.0, 0.6)), g_hp(45.0, 2)))
    air = colored(n, r, -2.0, 300.0, 6500.0) * (0.8 + 0.2 * np.sin(TAU * 80.0 * t))
    out = norm(prop) + 0.5 * eng + 0.25 * air / peak(air)
    return soft_clip(norm(out), 1.8)


@sound("jet_loop", ("rms", -16.0, -4.0), loop=True, family="engine")
def jet_loop(r):
    dur = 4.0
    n = secs(dur)
    t = tt(n)
    roar = colored(n, r, -3.0, 70.0, 6500.0) * (0.85 + 0.15 * slow_noise(n, r, 1.2))
    rumble = colored(n, r, -6.0, 28.0, 180.0) * (0.8 + 0.2 * slow_noise(n, r, 2.5))
    whine = np.zeros(n)
    for (f, g, rate) in ((2637.0, 1.0, 0.8), (3951.25, 0.6, 1.1), (5274.0, 0.35, 0.6), (7902.5, 0.15, 0.9)):
        fr = pphase_freq(f * (1.0 + 0.0025 * slow_noise(n, r, rate)))
        whine += g * np.sin(phase_of(fr, n)) * (0.8 + 0.2 * slow_noise(n, r, 1.5))
    fan = spec_filter(additive(310.0, n, saw_amps(40, 0.9)), g_bp(1400.0, 6000.0))
    out = norm(roar) + 0.5 * norm(rumble) + 0.16 * norm(whine) + 0.1 * norm(fan)
    return soft_clip(norm(out), 1.3)


@sound("bicycle_loop", ("rms", -26.0, -10.0), loop=True, family="engine")
def bicycle_loop(r):
    dur = 2.0
    n = secs(dur)
    x = np.zeros(n)
    ticks = 28                                                           # freewheel pawls
    for i in range(ticks):
        at = i * dur / ticks + r.uniform(-0.0012, 0.0012)
        tick = ping([3150.0, 5100.0, 7300.0], [0.004, 0.003, 0.002], [1.0, 0.7, 0.4], 0.02, r)
        wrap_event(x, tick, at, r.uniform(0.75, 1.0))
    chain = band_noise(n, r, 1500.0, 5500.0) * (0.6 + 0.4 * np.sin(TAU * 7.0 * tt(n)) ** 2)
    tyre = colored(n, r, -4.0, 150.0, 1400.0) * (0.85 + 0.15 * slow_noise(n, r, 3.0))
    return norm(x) + 0.18 * chain / peak(chain) + 0.3 * tyre / peak(tyre)


# --------------------------------------------------------------------------------------------
# tyres, scraping, fire, water
# --------------------------------------------------------------------------------------------

@sound("tire_skid_loop", ("rms", -16.0, -4.0), loop=True, family="vehicle")
def tire_skid_loop(r):
    dur = 2.0
    n = secs(dur)
    src = white(n, r)
    squeal = np.zeros(n)
    for (f, bw, g, rate) in ((1180.0, 90.0, 1.0, 5.0), (1690.0, 130.0, 0.8, 7.0), (2450.0, 260.0, 0.5, 9.0), (880.0, 110.0, 0.5, 4.0)):
        band = spec_filter(src, g_bell(f, bw))
        band = spec_filter(band, g_bp(f * 0.6, f * 1.6, 3))
        squeal += g * norm(band) * (0.55 + 0.45 * np.abs(slow_noise(n, r, rate)))
    fr = pphase_freq(1235.0 * (1.0 + 0.035 * slow_noise(n, r, 11.0)))
    howl = additive(fr, n, [1.0, 0.5, 0.3, 0.15]) * (0.5 + 0.5 * np.abs(slow_noise(n, r, 6.0)))
    grit = colored(n, r, -1.0, 500.0, 7000.0) * (0.7 + 0.3 * slow_noise(n, r, 20.0))
    out = norm(squeal) + 0.35 * norm(howl) + 0.3 * norm(grit)
    return soft_clip(norm(out), 1.6)


@sound("tire_roll_loop", ("rms", -23.0, -8.0), loop=True, family="vehicle")
def tire_roll_loop(r):
    n = secs(3.0)
    road = colored(n, r, -4.5, 50.0, 2200.0) * (0.85 + 0.15 * slow_noise(n, r, 5.0))
    tread = spec_filter(white(n, r), g_bell(720.0, 260.0)) * (0.8 + 0.2 * slow_noise(n, r, 3.0))
    return norm(road) + 0.25 * norm(tread)


@sound("metal_scrape_loop", ("rms", -17.0, -4.0), loop=True, family="vehicle")
def metal_scrape_loop(r):
    dur = 2.5
    n = secs(dur)
    t = tt(n)
    src = white(n, r)
    x = np.zeros(n)
    for (f, bw, g) in ((620.0, 60.0, 0.8), (1340.0, 90.0, 1.0), (2150.0, 140.0, 0.9), (3480.0, 220.0, 0.7), (5100.0, 400.0, 0.5)):
        x += g * norm(spec_filter(src, g_bell(f, bw))) * (0.4 + 0.6 * np.abs(slow_noise(n, r, 8.0)))
    rough = 0.55 + 0.45 * np.sin(TAU * 42.0 * t) * np.sin(TAU * 3.2 * t + 0.5)
    grit = colored(n, r, 0.0, 800.0, 9000.0)
    out = norm(x) * rough + 0.4 * norm(grit) * (0.6 + 0.4 * np.abs(slow_noise(n, r, 25.0)))
    return soft_clip(norm(out), 2.0)


@sound("fire_loop", ("rms", -21.0, -5.0), loop=True, family="ambience")
def fire_loop(r):
    dur = 6.0
    n = secs(dur)
    roar = colored(n, r, -4.0, 80.0, 2600.0) * (0.65 + 0.35 * slow_noise(n, r, 3.5))
    flutter = band_noise(n, r, 200.0, 900.0) * (0.5 + 0.5 * np.abs(slow_noise(n, r, 11.0)))
    hiss = band_noise(n, r, 2500.0, 9000.0) * (0.7 + 0.3 * slow_noise(n, r, 2.0))
    crack = impulses(n, r, 260, 900.0, 8000.0, 3.5)
    pops = np.zeros(n)
    for _ in range(26):                                                  # bigger wood pops
        wrap_event(pops, nburst(r, 0.03, 600.0, 5000.0, 0.0004, 0.004), r.uniform(0.0, dur), r.uniform(0.3, 1.0))
    return norm(roar) + 0.45 * norm(flutter) + 0.2 * norm(hiss) + 0.9 * norm(crack) + 0.7 * norm(pops)


@sound("underwater_loop", ("rms", -22.0, -8.0), loop=True, family="ambience")
def underwater_loop(r):
    dur = 8.0
    n = secs(dur)
    rumble = colored(n, r, -5.0, 32.0, 520.0) * (0.75 + 0.25 * slow_noise(n, r, 0.7))
    drone = spec_filter(white(n, r), g_sum(g_bell(108.0, 12.0), g_bell(171.0, 16.0, 0.7), g_bell(262.0, 24.0, 0.4)))
    drone *= 0.7 + 0.3 * slow_noise(n, r, 0.5)
    bub = np.zeros(n)
    for _ in range(34):
        nn = secs(r.uniform(0.04, 0.1))
        f0 = r.uniform(260.0, 700.0)
        f = f0 * (1.0 + 1.4 * (tt(nn) / (nn / SR)) ** 2)
        b = np.sin(phase_of(f, nn)) * np.sin(np.pi * np.arange(nn) / nn) ** 2
        wrap_event(bub, b, r.uniform(0.0, dur), r.uniform(0.15, 1.0))
    out = norm(rumble) + 0.5 * norm(drone) + 0.28 * norm(bub)
    return lp(out, 1800.0, 2)


@sound("chatter_loop", ("rms", -25.0, -8.0), loop=True, family="ambience")
def chatter_loop(r):
    """Crowd murmur: several formant voices babbling vowel-only syllables. No words."""
    dur = 8.0
    n = secs(dur)
    out = np.zeros(n)
    vowels = ("a", "uh", "o", "e", "ae", "m")
    for v in range(9):
        female = v % 2 == 1
        base = r.uniform(175.0, 240.0) if female else r.uniform(95.0, 140.0)
        scale = 1.16 if female else 1.0
        gain = r.uniform(0.35, 1.0)
        at = r.uniform(0.0, dur)
        end = at + dur
        while at < end - 0.3:
            syl = r.uniform(0.11, 0.3)
            f_a = base * r.uniform(0.9, 1.25)
            f_b = f_a * r.uniform(0.82, 1.12)
            a, b = r.choice(len(vowels), 2)
            s = voice(r, syl, [(0, f_a), (syl, f_b)], vowels[a], vowels[b],
                      [(0, 0), (syl * 0.25, 1.0), (syl * 0.7, 0.8), (syl, 0.0)], scale, 0.02, 0.12)
            wrap_event(out, norm(s), at, gain * r.uniform(0.5, 1.0))
            at += syl * r.uniform(0.85, 1.05)
            if r.uniform() < 0.22:                                       # pause between phrases
                at += r.uniform(0.25, 0.9)
    out = lp(out, 4600.0, 2)
    return reverb_circ(out, 0.9, 0.5, 201, lp_hz=4000.0)


# --------------------------------------------------------------------------------------------
# sirens
# --------------------------------------------------------------------------------------------

def siren_voice(freq: np.ndarray, r, growl: float = 0.0) -> np.ndarray:
    """Horn-loaded electronic siren: harmonic stack, speaker formant, mild overdrive."""
    n = len(freq)
    fr = pphase_freq(freq)
    if growl > 0.0:                                   # the sub-octave needs an even cycle count
        total = float(np.sum(freq)) / SR
        fr = freq * (2.0 * round(total / 2.0) / total)
    x = additive(fr, n, saw_amps(16, 1.15), phases=[0.0, 0.6, 1.4])
    if growl > 0.0:
        x = x + growl * additive(fr * 0.5, n, saw_amps(12, 1.0))         # mechanical sub-octave
    x = spec_filter(x, g_mul(g_sum(g_bell(1500.0, 1500.0, 1.0), g_bell(3100.0, 1800.0, 0.6)), g_hp(350.0, 2), g_lp(6500.0, 2)))
    x = soft_clip(norm(x), 1.7)
    return reverb_circ(x, 0.7, 0.14, 301, lp_hz=4000.0)


@sound("siren_police_loop", ("rms", -14.5, -3.5), loop=True, family="siren")
def siren_police_loop(r):
    # WAIL: one slow rise and fall per 3.2 s
    n = secs(3.2)
    u = np.arange(n) / n
    w = u + 0.06 * np.sin(TAU * u)
    s = 0.5 - 0.5 * np.cos(TAU * w)
    return siren_voice(np.exp(math.log(610.0) + (math.log(1480.0) - math.log(610.0)) * s), r)


@sound("siren_ambulance_loop", ("rms", -14.5, -3.5), loop=True, family="siren")
def siren_ambulance_loop(r):
    # YELP: fast sweep, six cycles of 0.34 s
    n = secs(2.04)
    u = (np.arange(n) / n * 6.0) % 1.0
    w = u + 0.09 * np.sin(TAU * u)
    s = 0.5 - 0.5 * np.cos(TAU * w)
    return siren_voice(np.exp(math.log(680.0) + (math.log(1620.0) - math.log(680.0)) * s), r)


@sound("siren_fire_loop", ("rms", -14.0, -3.5), loop=True, family="siren")
def siren_fire_loop(r):
    # HI-LO: two alternating tones (0.55 s each), lower and rougher
    n = secs(2.2)
    u = (np.arange(n) / n * 2.0) % 1.0
    edge = 0.02
    s = smoothstep(0.0, edge, u) - smoothstep(0.5, 0.5 + edge, u)        # 1 = high tone
    return siren_voice(455.0 + (606.0 - 455.0) * s, r, growl=0.35)


# --------------------------------------------------------------------------------------------
# tram, parachute, wind
# --------------------------------------------------------------------------------------------

@sound("tram_loop", ("rms", -20.0, -6.0), loop=True, family="vehicle")
def tram_loop(r):
    dur = 4.0
    n = secs(dur)
    t = tt(n)
    motor = additive(296.0, n, saw_amps(14, 1.3)) * (0.85 + 0.15 * np.sin(TAU * 0.5 * t))
    motor = spec_filter(motor, g_bp(200.0, 2600.0))
    hum = np.sin(TAU * 100.0 * t) + 0.5 * np.sin(TAU * 200.0 * t + 0.4) + 0.25 * np.sin(TAU * 300.0 * t + 1.1)
    rumble = colored(n, r, -3.5, 50.0, 1400.0) * (0.75 + 0.25 * slow_noise(n, r, 3.0))
    clack = np.zeros(n)
    for i in range(4):                                                   # rail joints: da-dum
        for (off, g) in ((0.0, 1.0), (0.12, 0.8)):
            at = 0.3 + i * 1.0 + off
            wrap_event(clack, thump(140.0, 70.0, 0.09, 0.012, 0.02), at, g)
            wrap_event(clack, ping([640.0, 1380.0, 2210.0], [0.03, 0.02, 0.012], [1.0, 0.6, 0.3], 0.1, r), at, 0.5 * g)
    flange = spec_filter(white(n, r), g_bell(2450.0, 120.0)) * np.abs(slow_noise(n, r, 1.0)) ** 2
    out = norm(rumble) + 0.6 * norm(motor) + 0.15 * norm(hum) + 0.8 * norm(clack) + 0.2 * norm(flange)
    return reverb_circ(out, 0.5, 0.1, 311, lp_hz=3500.0)


@sound("parachute_loop", ("rms", -21.0, -6.0), loop=True, family="vehicle")
def parachute_loop(r):
    dur = 4.0
    n = secs(dur)
    flap = band_noise(n, r, 140.0, 1700.0) * (0.3 + 0.7 * np.abs(slow_noise(n, r, 9.0)) ** 1.5)
    wind = colored(n, r, -3.0, 180.0, 3000.0) * (0.8 + 0.2 * slow_noise(n, r, 0.8))
    snaps = np.zeros(n)
    for _ in range(14):
        wrap_event(snaps, nburst(r, 0.05, 700.0, 4000.0, 0.002, 0.01), r.uniform(0.0, dur), r.uniform(0.3, 1.0))
    return norm(flap) + 0.7 * norm(wind) + 0.3 * norm(snaps)


@sound("wind_fall_loop", ("rms", -19.0, -5.0), loop=True, family="ambience")
def wind_fall_loop(r):
    dur = 4.0
    n = secs(dur)
    t = tt(n)
    rush = colored(n, r, -2.0, 140.0, 7000.0) * (0.8 + 0.2 * slow_noise(n, r, 1.6))
    roar = colored(n, r, -5.0, 45.0, 320.0) * (0.75 + 0.25 * slow_noise(n, r, 2.5))
    whistle = spec_filter(white(n, r), g_bell(2600.0, 500.0)) * (0.5 + 0.5 * np.abs(slow_noise(n, r, 1.2)))
    buffet = 0.85 + 0.15 * np.sin(TAU * 11.0 * t) * slow_noise(n, r, 2.0)
    return (norm(rush) + 0.6 * norm(roar) + 0.25 * norm(whistle)) * buffet


@sound("wind_loop", ("rms", -24.0, -8.0), loop=True, family="ambience")
def wind_loop(r):
    dur = 10.0
    n = secs(dur)
    src = white(n, r)
    bands = ((120.0, 420.0), (300.0, 1000.0), (700.0, 2300.0))
    ctl = [0.5 + 0.5 * slow_noise(n, r, 0.35) for _ in bands]
    x = np.zeros(n)
    for (lo, hi), c, g in zip(bands, ctl, (1.0, 0.8, 0.5)):
        x += g * norm(bp(src, lo, hi, 2)) * (0.25 + 0.75 * c ** 1.5)
    gust = 0.55 + 0.45 * slow_noise(n, r, 0.22)
    whistle = spec_filter(white(n, r), g_bell(1850.0, 260.0)) * np.clip(slow_noise(n, r, 0.3), 0.0, 1.0) ** 2
    return norm(x) * gust + 0.12 * norm(whistle)


# --------------------------------------------------------------------------------------------
# weather and district beds
# --------------------------------------------------------------------------------------------

@sound("rain_loop", ("rms", -25.0, -9.0), loop=True, family="ambience")
def rain_loop(r):
    dur = 8.0
    n = secs(dur)
    hiss = colored(n, r, -2.0, 700.0, 11000.0) * (0.9 + 0.1 * slow_noise(n, r, 0.6))
    patter = band_noise(n, r, 400.0, 2800.0) * (0.85 + 0.15 * slow_noise(n, r, 1.0))
    drops = impulses(n, r, 2600, 1500.0, 8000.0, 2.5)
    plops = impulses(n, r, 320, 400.0, 2000.0, 2.0)
    return norm(hiss) + 0.45 * norm(patter) + 0.7 * norm(drops) + 0.45 * norm(plops)


@sound("rain_heavy_loop", ("rms", -21.0, -6.0), loop=True, family="ambience")
def rain_heavy_loop(r):
    dur = 8.0
    n = secs(dur)
    gust = 0.8 + 0.2 * slow_noise(n, r, 0.4)
    hiss = colored(n, r, -2.0, 450.0, 11000.0) * gust
    roar = colored(n, r, -3.0, 140.0, 1100.0) * (0.8 + 0.2 * slow_noise(n, r, 0.5))
    drops = impulses(n, r, 7000, 1200.0, 8500.0, 2.0)
    plops = impulses(n, r, 900, 300.0, 1800.0, 1.8)
    return norm(hiss) + 0.45 * norm(roar) + 0.6 * norm(drops) * gust + 0.45 * norm(plops)


@sound("ocean_loop", ("rms", -23.0, -8.0), loop=True, family="ambience")
def ocean_loop(r):
    dur = 12.0
    n = secs(dur)
    swell_n = colored(n, r, -5.0, 50.0, 520.0)
    break_n = colored(n, r, -1.5, 350.0, 6500.0)
    fizz_n = band_noise(n, r, 2600.0, 10000.0)
    bed = colored(n, r, -3.0, 180.0, 3200.0) * (0.85 + 0.15 * slow_noise(n, r, 0.3))
    swell = np.zeros(n)
    brk = np.zeros(n)
    fizz = np.zeros(n)
    for (c, g) in ((2.2, 1.0), (8.6, 0.8)):                              # two waves per loop
        swell += g * cenv(n, c - 0.5, asym(1.5, 1.6), 4.0, 6.0)
        brk += g * cenv(n, c, asym(0.45, 1.5), 2.0, 7.0)
        fizz += g * cenv(n, c + 1.0, asym(0.9, 2.2), 3.0, 8.0)
    return 0.35 * norm(bed) + 0.9 * norm(swell_n * swell) + norm(break_n * brk) + 0.35 * norm(fizz_n * fizz)


def far_horn(r, f1, f2, dur):
    n = secs(dur)
    x = additive(f1, n, saw_amps(12, 1.0)) + additive(f2, n, saw_amps(12, 1.0))
    e = np.minimum(1.0, np.minimum(tt(n) / 0.02, (dur - tt(n)) / 0.05))
    return lp(x * np.clip(e, 0.0, 1.0), 1100.0, 2, pad=512)


@sound("city_loop", ("rms", -25.0, -9.0), loop=True, family="ambience")
def city_loop(r):
    dur = 12.0
    n = secs(dur)
    t = tt(n)
    hum = colored(n, r, -4.0, 60.0, 1100.0) * (0.8 + 0.2 * slow_noise(n, r, 0.4))
    wash = colored(n, r, -3.5, 280.0, 3600.0) * (0.7 + 0.3 * slow_noise(n, r, 0.3))
    passes = np.zeros(n)
    pn = band_noise(n, r, 180.0, 2000.0)
    for _ in range(5):                                                   # distant cars passing
        passes += r.uniform(0.4, 1.0) * cenv(n, r.uniform(0.0, dur), gauss(r.uniform(0.7, 1.4)), 4.0, 4.0)
    mains = np.sin(TAU * 100.0 * t) * 0.6 + np.sin(TAU * 150.0 * t + 0.7) * 0.3 + np.sin(TAU * 50.0 * t) * 0.5
    events = np.zeros(n)
    wrap_event(events, far_horn(r, 392.0, 494.0, 0.32), 3.4, 1.0)
    wrap_event(events, far_horn(r, 392.0, 494.0, 0.18), 3.85, 0.8)
    wrap_event(events, far_horn(r, 330.0, 415.0, 0.45), 9.1, 0.6)
    for _ in range(3):                                                   # far door / thud
        wrap_event(events, thump(110.0, 60.0, 0.12, 0.02, 0.03), r.uniform(0.0, dur), 0.8)
    events = reverb_circ(events, 1.6, 1.4, 321, lp_hz=1500.0)
    out = norm(hum) + 0.55 * norm(wash) + 0.45 * norm(pn * passes) + 0.03 * mains + 0.12 * norm(events)
    return out


@sound("industrial_loop", ("rms", -24.0, -8.0), loop=True, family="ambience")
def industrial_loop(r):
    dur = 9.0
    n = secs(dur)
    t = tt(n)
    drone = (np.sin(TAU * 50.0 * t) + 0.8 * np.sin(TAU * 100.0 * t + 0.3) + 0.5 * np.sin(TAU * (100.0 + 1.0 / 9.0) * t)
             + 0.4 * np.sin(TAU * 150.0 * t + 1.2) + 0.25 * np.sin(TAU * 200.0 * t + 2.0) + 0.12 * np.sin(TAU * 300.0 * t))
    rumble = colored(n, r, -3.5, 45.0, 1000.0) * (0.75 + 0.25 * np.sin(TAU * 4.0 * t) ** 2)
    steam = band_noise(n, r, 1500.0, 6500.0) * (0.6 + 0.4 * slow_noise(n, r, 0.5))
    ev = np.zeros(n)
    for i in range(6):                                                   # pneumatic press cycle
        at = 0.2 + i * 1.5
        hiss = band_noise(secs(0.5), r, 2000.0, 9000.0) * env_ad(secs(0.5), 0.02, 0.11)
        wrap_event(ev, norm(hiss), at, 0.5)
        f = 280.0 * r.uniform(0.9, 1.1)
        clank = ping([f, f * 1.9, f * 3.2, f * 5.1, f * 7.4], [0.16, 0.12, 0.08, 0.05, 0.03], [1.0, 0.8, 0.6, 0.4, 0.25], 0.5, r)
        wrap_event(ev, clank, at + 0.72, r.uniform(0.6, 1.0))
        wrap_event(ev, thump(90.0, 45.0, 0.2, 0.03, 0.05), at + 0.72, 0.9)
    for _ in range(7):                                                   # distant hammering
        f = r.uniform(700.0, 1600.0)
        wrap_event(ev, ping([f, f * 2.3, f * 3.7], [0.05, 0.03, 0.02], [1.0, 0.6, 0.3], 0.2, r), r.uniform(0.0, dur), r.uniform(0.1, 0.3))
    ev = reverb_circ(ev, 1.5, 0.5, 331, lp_hz=3500.0)
    whirr = spec_filter(white(n, r), g_bell(1240.0, 70.0)) * (0.8 + 0.2 * slow_noise(n, r, 0.6))
    return norm(rumble) + 0.13 * norm(drone) + 0.75 * norm(ev) + 0.16 * norm(whirr) + 0.07 * norm(steam)


def bird_phrase(r, kind: int) -> np.ndarray:
    buf = np.zeros(secs(1.4))
    if kind == 0:                                                        # sparrow: quick chips
        at = 0.0
        for _ in range(r.randint(3, 7)):
            f = r.uniform(3800.0, 5200.0)
            buf_add(buf, bird_chirp(f, f * r.uniform(0.8, 1.25), r.uniform(0.04, 0.07), r), at)
            at += r.uniform(0.08, 0.15)
    elif kind == 1:                                                      # warbler: rising sweeps
        at = 0.0
        for i in range(3):
            buf_add(buf, bird_chirp(2400.0 + 200.0 * i, 3900.0 + 250.0 * i, 0.16, r, 0.7), at)
            at += 0.22
    elif kind == 2:                                                      # tit: two-note call
        for i in range(r.randint(2, 4)):
            buf_add(buf, bird_chirp(3900.0, 3850.0, 0.11, r, 1.0, 0.0, 0.2), i * 0.32)
            buf_add(buf, bird_chirp(3050.0, 3000.0, 0.13, r, 1.0, 0.0, 0.2), i * 0.32 + 0.14)
    else:                                                                # trill
        buf_add(buf, bird_chirp(5000.0, 4700.0, r.uniform(0.4, 0.8), r, 1.0, r.uniform(24.0, 34.0)), 0.0)
    return buf


def buf_add(buf: np.ndarray, sig: np.ndarray, t: float, gain: float = 1.0) -> None:
    i = int(round(t * SR))
    if i >= len(buf):
        return
    m = min(len(sig), len(buf) - i)
    buf[i:i + m] += sig[:m] * gain


@sound("park_birds_loop", ("rms", -28.0, -9.0), loop=True, family="ambience")
def park_birds_loop(r):
    dur = 10.0
    n = secs(dur)
    leaves = colored(n, r, 0.0, 1400.0, 9000.0) * (0.5 + 0.5 * np.clip(slow_noise(n, r, 0.3), -1.0, 1.0) ** 2)
    air = colored(n, r, -5.0, 60.0, 600.0)
    birds = np.zeros(n)
    for _ in range(30):
        g = r.uniform(0.12, 1.0) ** 1.5
        ph = bird_phrase(r, r.randint(0, 4))
        if g < 0.35:
            ph = lp(ph, 4200.0, 1)                                       # far birds are duller
        wrap_event(birds, ph, r.uniform(0.0, dur), g)
    birds = reverb_circ(birds, 0.9, 0.35, 341, lp_hz=7000.0, hp_hz=900.0)
    return norm(birds) + 0.055 * norm(leaves) + 0.05 * norm(air)


@sound("night_crickets_loop", ("rms", -28.0, -10.0), loop=True, family="ambience")
def night_crickets_loop(r):
    dur = 8.0
    n = secs(dur)
    t = tt(n)
    out = np.zeros(n)
    for c in range(6):
        carrier = r.uniform(4000.0, 5300.0)
        chirps = int(round(dur / r.uniform(0.38, 0.7)))
        gain = r.uniform(0.25, 1.0)
        phase0 = r.uniform(0.0, dur)
        pulses = r.randint(2, 5)
        for k in range(chirps):
            base = phase0 + k * dur / chirps + r.uniform(-0.01, 0.01)
            for p in range(pulses):
                nn = secs(0.017)
                tp = tt(nn)
                pulse = np.sin(TAU * carrier * tp) * np.sin(np.pi * np.arange(nn) / nn) ** 2
                wrap_event(out, pulse, base + p * 0.021, gain * (0.7 + 0.3 * p / pulses))
    trill = np.sin(TAU * 3300.0 * t) * np.sin(TAU * 22.0 * t) ** 2 * (0.6 + 0.4 * slow_noise(n, r, 0.25))
    air = colored(n, r, -5.0, 60.0, 900.0)
    out = reverb_circ(out, 0.5, 0.2, 351, lp_hz=8000.0, hp_hz=1500.0)
    return norm(out) + 0.1 * norm(trill) + 0.09 * norm(air)


@sound("airport_loop", ("rms", -24.0, -8.0), loop=True, family="ambience")
def airport_loop(r):
    dur = 12.0
    n = secs(dur)
    t = tt(n)
    swell = 0.25 + cenv(n, 5.0, gauss(1.9), 6.0, 6.0)
    jet = colored(n, r, -3.5, 120.0, 3000.0) * swell
    whine = spec_filter(white(n, r), g_sum(g_bell(2900.0, 160.0), g_bell(4350.0, 240.0, 0.5))) * swell ** 1.5
    apron = colored(n, r, -5.5, 40.0, 520.0) * (0.8 + 0.2 * slow_noise(n, r, 0.4))
    apu = np.sin(TAU * 400.0 * t) * (0.7 + 0.3 * slow_noise(n, r, 0.5)) + 0.4 * np.sin(TAU * 800.0 * t)
    chime = np.zeros(n)
    for i, f in enumerate((659.3, 523.3, 392.0)):                        # terminal chime, no voice
        wrap_event(chime, bell_note(f, 1.2, 0.4, r, 0.6), 9.2 + 0.42 * i, 0.9)
    chime = reverb_circ(chime, 1.8, 0.9, 361, lp_hz=2600.0)
    wind = band_noise(n, r, 250.0, 1800.0) * (0.5 + 0.5 * slow_noise(n, r, 0.25))
    return norm(jet) + 0.2 * norm(whine) + 0.55 * norm(apron) + 0.025 * apu + 0.14 * norm(chime) + 0.2 * norm(wind)


@sound("harbor_loop", ("rms", -25.0, -8.0), loop=True, family="ambience")
def harbor_loop(r):
    dur = 12.0
    n = secs(dur)
    wash = colored(n, r, -3.0, 250.0, 4200.0) * (0.75 + 0.25 * slow_noise(n, r, 0.35))
    lap_n = band_noise(n, r, 180.0, 1700.0)
    lap = np.zeros(n)
    ev = np.zeros(n)
    for _ in range(10):                                                  # water slapping hulls
        c = r.uniform(0.0, dur)
        lap += r.uniform(0.4, 1.0) * cenv(n, c, asym(0.09, 0.3), 1.0, 2.5)
        nn = secs(0.06)
        f0 = r.uniform(300.0, 700.0)
        plip = np.sin(phase_of(f0 * (1.0 + 1.2 * tt(nn) / 0.06), nn)) * env_ad(nn, 0.003, 0.014)
        wrap_event(ev, plip, c + 0.05, 0.25)
    for _ in range(16):                                                  # rigging against masts
        f = r.uniform(2100.0, 4600.0)
        wrap_event(ev, ping([f, f * 1.52, f * 2.4], [0.11, 0.07, 0.04], [1.0, 0.5, 0.3], 0.4, r), r.uniform(0.0, dur), r.uniform(0.05, 0.3))
    for at in (1.5, 7.3):                                                # buoy bell
        f = 587.3
        wrap_event(ev, ping([f, f * 2.0, f * 2.4, f * 3.0, f * 4.5], [1.4, 0.9, 0.7, 0.5, 0.3], [1.0, 0.6, 0.4, 0.35, 0.2], 2.6, r), at, 0.28)
    wrap_event(ev, lp(gull_call(r, 0.4, 1500.0, 950.0), 3500.0, 1), 4.6, 0.3)
    wrap_event(ev, lp(gull_call(r, 0.28, 1620.0, 1000.0), 3500.0, 1), 5.1, 0.25)
    wrap_event(ev, lp(gull_call(r, 0.33, 1450.0, 900.0), 3000.0, 1), 10.4, 0.18)
    ev = reverb_circ(ev, 1.3, 0.35, 371, lp_hz=5000.0)
    chug = np.zeros(n)
    for i in range(108):                                                 # far diesel boat, 9 Hz
        wrap_event(chug, thump(95.0, 60.0, 0.07, 0.015, 0.02), i * dur / 108.0, r.uniform(0.8, 1.0))
    chug *= 0.3 + cenv(n, 9.0, gauss(2.5), 6.0, 6.0)
    return 0.5 * norm(wash) + 0.6 * norm(lap_n * lap) + 0.6 * norm(ev) + 0.16 * norm(chug)
