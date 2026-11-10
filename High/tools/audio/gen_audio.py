"""Procedural, project-owned audio for Marlow Bay. Pure numpy synthesis -> 16-bit mono WAV.
Usage: python tools/audio/gen_audio.py   (writes gta/generated/audio/*.wav)"""
import numpy as np, wave, os, sys

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "gta", "generated", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(52)


def save(name, x, peak=0.9):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * peak
    d = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(d.tobytes())


def t(dur):
    return np.arange(int(SR * dur)) / SR


def noise(dur, lo=20, hi=10000, tilt=0.0):
    """Band-limited noise (periodic, so it loops seamlessly)."""
    n = int(SR * dur)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    mask = (f >= lo) & (f <= hi)
    shape = np.where(mask, 1.0, 0.0) * np.power(np.maximum(f, 1.0), tilt)
    return np.fft.irfft(spec * shape, n)


def env(dur, a=0.002, d=0.2, curve=4.0):
    x = t(dur)
    e = np.exp(-x / max(d, 1e-4) * curve / 4.0 * 4.0)
    e *= np.clip(x / a, 0, 1)
    return e


def sine(f, dur, ph=0.0):
    return np.sin(2 * np.pi * f * t(dur) + ph)


def sweep(f0, f1, dur):
    x = t(dur)
    f = f0 * (f1 / f0) ** (x / dur)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def pad(x, n):
    out = np.zeros(n)
    out[:min(n, len(x))] = x[:n]
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    return sum(pad(p, n) for p in parts)


def shot(name, dur, body_f, crack_hi, tail, boom=0.6, snap=1.0):
    n1 = noise(dur, 300, crack_hi) * env(dur, 0.0005, tail * 0.25) * snap
    n2 = noise(dur, 60, 900) * env(dur, 0.001, tail)
    b = sweep(body_f * 2.2, body_f * 0.5, dur) * env(dur, 0.001, tail * 0.6) * boom
    x = mix(n1, n2 * 0.9, b)
    save(name, np.tanh(x * 2.2))


shot("shot_pistol", 0.35, 190, 7000, 0.10)
shot("shot_heavy", 0.5, 120, 6000, 0.16, boom=1.0)
shot("shot_smg", 0.25, 240, 8000, 0.07, boom=0.4)
shot("shot_shotgun", 0.7, 90, 5000, 0.22, boom=1.2)
shot("shot_rifle", 0.45, 150, 9000, 0.12, boom=0.7)
shot("shot_sniper", 0.9, 80, 9000, 0.28, boom=1.3)
save("shot_suppressed", mix(noise(0.18, 800, 6000) * env(0.18, 0.001, 0.035), sweep(500, 200, 0.18) * env(0.18, 0.001, 0.03) * 0.3), 0.5)
save("shot_rocket", mix(noise(1.2, 100, 5000, -0.3) * env(1.2, 0.02, 0.5), sweep(300, 90, 1.2) * env(1.2, 0.01, 0.4) * 0.6))
save("shot_gl", mix(sweep(260, 90, 0.3) * env(0.3, 0.002, 0.08), noise(0.3, 200, 3000) * env(0.3, 0.001, 0.05) * 0.5))
save("dry_fire", noise(0.06, 2000, 8000) * env(0.06, 0.0005, 0.01), 0.4)
rl = np.zeros(int(SR * 0.9))
for (at, f, a) in ((0.05, 2400, 0.7), (0.32, 1500, 1.0), (0.62, 3000, 0.8), (0.70, 1800, 0.6)):
    c = (noise(0.08, f * 0.5, f * 2.5) * env(0.08, 0.0005, 0.018)) * a
    i = int(at * SR)
    rl[i:i + len(c)] += c
save("reload", rl, 0.6)
save("equip", mix(noise(0.14, 1500, 6000) * env(0.14, 0.001, 0.03), sweep(900, 1400, 0.1) * env(0.1, 0.001, 0.03) * 0.3), 0.4)
ex = mix(noise(2.4, 30, 2500, -0.6) * env(2.4, 0.003, 0.9), sweep(110, 28, 1.6) * env(1.6, 0.002, 0.7) * 1.4, noise(0.3, 500, 9000) * env(0.3, 0.0005, 0.06))
save("explosion", np.tanh(ex / np.max(np.abs(ex)) * 3.0))
save("thunder", mix(noise(4.0, 25, 600, -0.8) * env(4.0, 0.05, 1.8), noise(0.5, 200, 4000) * env(0.5, 0.002, 0.1) * 0.5))
save("impact_metal", mix(sine(2100, 0.2) * env(0.2, 0.0005, 0.05), sine(3350, 0.2) * env(0.2, 0.0005, 0.03) * 0.6, noise(0.05, 2000, 9000) * env(0.05, 0.0003, 0.01)), 0.6)
save("impact_concrete", mix(noise(0.16, 300, 5000) * env(0.16, 0.0005, 0.035), sweep(300, 120, 0.1) * env(0.1, 0.001, 0.03) * 0.4), 0.6)
save("impact_flesh", mix(noise(0.14, 80, 900) * env(0.14, 0.001, 0.04), sweep(180, 70, 0.12) * env(0.12, 0.001, 0.04)), 0.7)
gl = np.zeros(int(SR * 0.9))
for i in range(26):
    f = rng.uniform(2500, 7500)
    at = rng.uniform(0, 0.45) ** 1.5
    c = sine(f, 0.25) * env(0.25, 0.0005, rng.uniform(0.02, 0.09)) * rng.uniform(0.3, 1)
    j = int(at * SR)
    gl[j:j + len(c)] += c[:len(gl) - j]
save("glass_break", mix(gl, noise(0.25, 3000, 10000) * env(0.25, 0.0005, 0.05)), 0.7)
save("punch", mix(noise(0.12, 100, 1400) * env(0.12, 0.0008, 0.03), sweep(220, 70, 0.12) * env(0.12, 0.001, 0.04) * 1.2), 0.8)
save("swing", noise(0.22, 500, 3500) * np.sin(np.pi * t(0.22) / 0.22) ** 2, 0.35)
for i, (lo, hi) in enumerate(((200, 2400), (160, 2000))):
    save("step_%d" % i, mix(noise(0.11, lo, hi) * env(0.11, 0.001, 0.025), sweep(160, 80, 0.07) * env(0.07, 0.001, 0.02) * 0.5), 0.5)
save("step_grass", noise(0.14, 900, 6000) * env(0.14, 0.004, 0.04), 0.3)
save("splash", mix(noise(0.8, 300, 7000, -0.2) * env(0.8, 0.01, 0.25), noise(0.8, 80, 500) * env(0.8, 0.005, 0.15)), 0.7)
save("swim", noise(0.5, 400, 4000) * np.sin(np.pi * t(0.5) / 0.5) ** 2, 0.3)


def engine_loop(name, base, harm, dur=1.0, rough=0.25, noise_amt=0.12):
    x = t(dur)
    cyc = int(round(base * dur))
    f = cyc / dur
    y = np.zeros_like(x)
    for k, a in enumerate(harm, start=1):
        y += a * np.sin(2 * np.pi * f * k * x + k * 0.7)
    pulse = 1.0 + rough * np.sign(np.sin(2 * np.pi * f * 0.5 * x))
    y = y * pulse + noise(dur, 80, 2500) * noise_amt
    save(name, np.tanh(y * 1.4), 0.7)


engine_loop("engine_loop", 55, [1, 0.7, 0.5, 0.42, 0.3, 0.2, 0.14, 0.1])
engine_loop("engine_bike_loop", 82, [1, 0.9, 0.3, 0.5, 0.2, 0.3, 0.1], rough=0.4)
engine_loop("engine_truck_loop", 38, [1, 0.8, 0.7, 0.4, 0.4, 0.2, 0.2, 0.1], rough=0.35, noise_amt=0.2)
engine_loop("boat_loop", 46, [1, 0.6, 0.6, 0.3, 0.3, 0.2], rough=0.5, noise_amt=0.3)
engine_loop("plane_loop", 64, [1, 0.5, 0.8, 0.3, 0.4, 0.15, 0.2], rough=0.15, noise_amt=0.25)
x = t(1.0)
chop = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 14 * x)) * np.abs(np.sin(2 * np.pi * 14 * x)) ** 0.4
save("heli_loop", noise(1.0, 60, 1800, -0.3) * (0.35 + chop) + 0.4 * np.sin(2 * np.pi * 42 * x) * chop, 0.75)
save("jet_loop", noise(2.0, 200, 9000, -0.25) * 0.8 + 0.25 * np.sin(2 * np.pi * 1400 * t(2.0)) + 0.2 * np.sin(2 * np.pi * 2110 * t(2.0)), 0.6)
save("skid_loop", noise(1.0, 900, 3200) * (0.7 + 0.3 * np.sin(2 * np.pi * 31 * t(1.0))), 0.5)
save("wind_loop", noise(4.0, 80, 1400, -0.5) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.25 * t(4.0))), 0.5)
save("crash_small", mix(noise(0.4, 150, 5000) * env(0.4, 0.001, 0.1), sine(700, 0.3) * env(0.3, 0.001, 0.06) * 0.4), 0.8)
save("crash_big", np.tanh(mix(noise(0.9, 60, 6000, -0.2) * env(0.9, 0.001, 0.25), sweep(200, 50, 0.6) * env(0.6, 0.001, 0.2), gl[:int(SR * 0.9)] * 0.25) * 2.0), 0.9)


def horn(name, freqs, dur=0.8):
    x = t(dur)
    y = sum(np.sign(np.sin(2 * np.pi * f * x)) * 0.5 + np.sin(2 * np.pi * f * x) for f in freqs)
    e = np.clip(x / 0.01, 0, 1) * np.clip((dur - x) / 0.04, 0, 1)
    save(name, y * e, 0.55)


horn("horn_0", [420, 525])
horn("horn_1", [190, 240, 285], 1.1)
mel = np.concatenate([np.sign(np.sin(2 * np.pi * f * t(0.16))) * np.clip((0.16 - t(0.16)) / 0.02, 0, 1) for f in (523, 659, 784, 1047, 784, 1047)])
save("horn_2", mel, 0.5)
x = t(3.0)
fs = 650 + 550 * (0.5 - 0.5 * np.cos(2 * np.pi * x / 3.0))
save("siren_loop", np.sign(np.sin(2 * np.pi * np.cumsum(fs) / SR)) * 0.5 + np.sin(2 * np.pi * np.cumsum(fs) / SR), 0.5)
x = t(0.6)
fs = 700 + 600 * (0.5 - 0.5 * np.cos(2 * np.pi * x / 0.3))
save("siren_yelp", np.sign(np.sin(2 * np.pi * np.cumsum(fs) / SR)) * 0.5 + np.sin(2 * np.pi * np.cumsum(fs) / SR), 0.5)
x = t(1.2)
save("siren_ems", np.where((x % 1.2) < 0.6, np.sin(2 * np.pi * 960 * x), np.sin(2 * np.pi * 770 * x)) + 0.3 * np.sign(np.sin(2 * np.pi * 865 * x)), 0.45)

# ambience loops
save("amb_city", noise(8.0, 40, 900, -0.7) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.125 * t(8.0))) + noise(8.0, 900, 3000, -0.5) * 0.12, 0.5)
w = t(8.0)
swell = (0.5 + 0.5 * np.sin(2 * np.pi * w / 8.0 * 2 - 1.3)) ** 2
save("amb_ocean", noise(8.0, 150, 5000, -0.45) * (0.25 + swell) + noise(8.0, 40, 200) * 0.3, 0.55)
save("amb_rain", noise(4.0, 1200, 9500, -0.1) * 0.8 + noise(4.0, 200, 1200) * 0.25, 0.5)
ind = noise(8.0, 50, 400, -0.5) + 0.25 * np.sin(2 * np.pi * 100 * t(8.0)) + 0.15 * np.sin(2 * np.pi * 150 * t(8.0))
for at in (1.0, 3.5, 5.2, 7.1):
    c = sine(900 + at * 60, 0.4) * env(0.4, 0.001, 0.08) * 0.5
    i = int(at * SR)
    ind[i:i + len(c)] += c
save("amb_industrial", ind, 0.45)
bd = np.zeros(int(SR * 8.0))
for i in range(22):
    at = rng.uniform(0, 7.4)
    f0 = rng.uniform(2200, 4200)
    c = sweep(f0, f0 * rng.uniform(0.75, 1.35), 0.12) * np.sin(np.pi * t(0.12) / 0.12) ** 2 * rng.uniform(0.3, 1)
    j = int(at * SR)
    bd[j:j + len(c)] += c
    if rng.random() < 0.6:
        j2 = j + int(0.16 * SR)
        bd[j2:j2 + len(c)] += c[:len(bd) - j2] * 0.8
save("amb_birds", bd + noise(8.0, 300, 3000, -0.6) * 0.05, 0.35)
cr = np.zeros(int(SR * 8.0))
for i in range(60):
    at = rng.uniform(0, 7.5)
    f0 = rng.uniform(140, 320)
    d = rng.uniform(0.15, 0.4)
    c = (np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.15 * np.sin(2 * np.pi * 3 * t(d)))) / SR) + 0.5 * noise(d, 600, 2600)) * np.sin(np.pi * t(d) / d) ** 2
    j = int(at * SR)
    cr[j:j + len(c)] += c[:len(cr) - j] * rng.uniform(0.2, 0.7)
save("amb_crowd", cr, 0.3)
save("amb_underwater", noise(6.0, 30, 400, -0.8) * (0.7 + 0.3 * np.sin(2 * np.pi * t(6.0) / 3.0)), 0.5)

# voices (non-verbal formant grunts)
def grunt(name, f0, dur, form):
    x = t(dur)
    f = f0 * (1.0 - 0.35 * x / dur)
    src = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * 0.6 + np.sin(2 * np.pi * np.cumsum(f) / SR)
    spec = np.fft.rfft(src + noise(dur, 300, 5000) * 0.3)
    fr = np.fft.rfftfreq(len(src), 1 / SR)
    shape = sum(np.exp(-((fr - c) / bw) ** 2) for c, bw in form) + 0.02
    y = np.fft.irfft(spec * shape, len(src)) * np.sin(np.pi * x / dur) ** 0.7
    save(name, y, 0.6)


grunt("pain_m", 150, 0.32, [(700, 150), (1150, 200), (2600, 400)])
grunt("pain_f", 280, 0.30, [(850, 180), (1400, 250), (3000, 400)])
grunt("scream_m", 260, 0.7, [(800, 200), (1300, 300), (2800, 500)])
grunt("scream_f", 520, 0.8, [(950, 220), (1700, 300), (3200, 500)])
grunt("bark", 320, 0.16, [(600, 200), (1500, 400)])

# UI
save("ui_click", sine(1200, 0.05) * env(0.05, 0.001, 0.012), 0.35)
save("ui_move", sine(820, 0.04) * env(0.04, 0.001, 0.01), 0.25)
save("ui_buy", mix(sine(880, 0.12) * env(0.12, 0.001, 0.04), pad(np.concatenate([np.zeros(int(0.07 * SR)), sine(1320, 0.2) * env(0.2, 0.001, 0.06)]), int(0.3 * SR))), 0.4)
save("ui_deny", mix(np.sign(sine(180, 0.22)) * env(0.22, 0.001, 0.08)), 0.3)
save("pickup", np.concatenate([sine(f, 0.07) * env(0.07, 0.001, 0.03) for f in (784, 988, 1175)]), 0.4)
save("wanted_up", np.concatenate([np.sign(sine(f, 0.09)) * env(0.09, 0.001, 0.05) for f in (440, 554)]), 0.35)
save("wanted_clear", np.concatenate([sine(f, 0.12) * env(0.12, 0.001, 0.06) for f in (659, 523, 784)]), 0.35)
save("sting_fail", np.concatenate([(sine(f, 0.4) + 0.5 * sine(f * 1.5, 0.4)) * env(0.4, 0.004, 0.25) for f in (220, 196, 147)]), 0.5)
save("sting_good", np.concatenate([(sine(f, 0.18) + 0.4 * sine(f * 2, 0.18)) * env(0.18, 0.003, 0.1) for f in (523, 659, 784, 1047)]), 0.45)
save("chute_open", mix(noise(0.6, 150, 3000, -0.3) * env(0.6, 0.02, 0.15), sweep(200, 90, 0.3) * env(0.3, 0.005, 0.1)), 0.6)
save("phone_beep", np.concatenate([sine(1400, 0.06) * env(0.06, 0.001, 0.03), np.zeros(int(0.03 * SR)), sine(1750, 0.08) * env(0.08, 0.001, 0.04)]), 0.3)
save("train_loop", noise(2.0, 60, 1500, -0.4) * (0.7 + 0.3 * np.sign(np.sin(2 * np.pi * 4 * t(2.0)))) + 0.2 * np.sin(2 * np.pi * 220 * t(2.0)), 0.45)
save("fire_loop", noise(2.0, 200, 5000, -0.5) * (0.6 + 0.4 * np.abs(noise(2.0, 2, 14))/np.max(np.abs(noise(2.0, 2, 14)))), 0.45)
save("tick", sine(2000, 0.03) * env(0.03, 0.0005, 0.008), 0.3)


# ------------------------------------------------------------------ radio stations (original procedural loops)
def note(f, dur, kind="saw", a=0.005, d=0.3):
    x = t(dur)
    if kind == "saw":
        y = 2 * ((f * x) % 1.0) - 1
    elif kind == "sq":
        y = np.sign(np.sin(2 * np.pi * f * x)) * 0.7
    elif kind == "tri":
        y = 2 * np.abs(2 * ((f * x) % 1.0) - 1) - 1
    else:
        y = np.sin(2 * np.pi * f * x)
    return y * np.clip(x / a, 0, 1) * np.exp(-x / d)


def kick():
    return sweep(150, 42, 0.22) * env(0.22, 0.001, 0.09)


def snare():
    return mix(noise(0.18, 400, 7000) * env(0.18, 0.001, 0.05), sine(190, 0.1) * env(0.1, 0.001, 0.03) * 0.5)


def hat():
    return noise(0.05, 6000, 10000) * env(0.05, 0.0005, 0.012)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def station(name, bpm, bars, root, scale, bass_pat, lead_kind, drums, chord_prog, swing=0.0, lead_density=0.6, seed=1):
    r = np.random.default_rng(seed)
    beat = 60.0 / bpm
    total = int(SR * beat * 4 * bars)
    y = np.zeros(total + SR)

    def put(sig, at, gain=1.0):
        i = int(at * SR)
        if i < total:
            seg = sig[:len(y) - i]
            y[i:i + len(seg)] += seg * gain
    for bar in range(bars):
        ch = chord_prog[bar % len(chord_prog)]
        t0 = bar * 4 * beat
        for step in range(16):
            at = t0 + step * beat / 4 + (swing * beat / 4 if step % 2 else 0)
            if drums[0][step % len(drums[0])] == "x":
                put(kick(), at, 0.9)
            if drums[1][step % len(drums[1])] == "x":
                put(snare(), at, 0.55)
            if drums[2][step % len(drums[2])] == "x":
                put(hat(), at, 0.25)
            b = bass_pat[step % len(bass_pat)]
            if b is not None:
                put(note(midi(root - 24 + ch + b), beat * 0.45, "tri", d=0.25), at, 0.6)
            if r.random() < lead_density and step % 2 == 0:
                deg = scale[r.integers(0, len(scale))]
                put(note(midi(root + ch + deg + (12 if r.random() < 0.3 else 0)), beat * 0.5, lead_kind, d=0.18), at, 0.22)
        for deg in (0, scale[2], scale[4]):
            put(note(midi(root - 12 + ch + deg), beat * 3.8, "sine", a=0.05, d=1.8), t0, 0.16)
    y[:SR] += y[total:total + SR]   # wrap the tail for a seamless loop
    save(name, np.tanh(y[:total] * 1.3), 0.6)


MAJ = [0, 2, 4, 5, 7, 9, 11]
MIN = [0, 2, 3, 5, 7, 8, 10]
PEN = [0, 3, 5, 7, 10, 12, 15]
station("radio_0", 112, 8, 57, MIN, [0, None, 0, None, 7, None, 0, 12, 0, None, 0, None, 7, None, 10, None], "saw",
        ["x...x...x...x...", "....x.......x...", "..x...x...x...x."], [0, 0, -4, -2], seed=3)
station("radio_1", 88, 8, 60, MAJ, [0, None, None, 7, None, None, 4, None, 0, None, None, 7, None, 4, None, None], "sine",
        ["x.....x...x.....", "....x.......x...", "x.x.x.x.x.x.x.x."], [0, 5, 7, 5], swing=0.5, lead_density=0.5, seed=5)
station("radio_2", 128, 8, 54, PEN, [0, 0, 12, 0, 0, 12, 0, 0, 0, 0, 12, 0, 3, 3, 15, 3], "sq",
        ["x...x...x...x...", "....x.......x..x", "x.xxx.xxx.xxx.xx"], [0, 0, 3, -2], lead_density=0.8, seed=9)
station("radio_3", 72, 8, 62, MIN, [0, None, None, None, 7, None, None, None, 3, None, None, None, 7, None, 5, None], "tri",
        ["x.......x.......", "........x.......", "....x.......x..."], [0, -2, -4, -5], lead_density=0.45, seed=11)
print("audio files:", len([f for f in os.listdir(OUT) if f.endswith(".wav")]))
