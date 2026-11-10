"""HALCYON BAY - one-shot sound recipes (weapons, impacts, body, voices, UI, stingers, animals).

Each recipe is a function `fn(r) -> np.ndarray` registered with @sound(id, level, ...).
`r` is a RandomState seeded from the sound id, so every run produces identical files.
"""
from __future__ import annotations

import math

import numpy as np

from dsp import (SR, TAU, Mix, additive, band_noise, bell, bp, chirp, colored, echo, env_ad,
                 env_adsr, env_exp, env_pts, fade, formant_filter, glide, hann, hp, lp, modal,
                 norm, peak, phase_of, reverb, saw_amps, secs, sine, slow_noise, smoothstep,
                 soft_clip, square_amps, svf, tt, white, mtof)

REGISTRY: dict = {}

LOUD = ("peak", -3.0)       # gunshots, explosions, crashes
MID = ("peak", -6.0)        # impacts, doors, body sounds
SOFT = ("peak", -9.0)       # footsteps, small foley
UI = ("peak", -10.0)        # interface blips
STING = ("peak", -6.0)      # musical stingers
VOICE = ("peak", -5.0)


def sound(sound_id: str, level=MID, sr: int = SR, loop: bool = False, attack: float = 0.0003,
          release: float = 0.01, family: str = ""):
    def deco(fn):
        REGISTRY[sound_id] = {"fn": fn, "level": level, "sr": sr, "loop": loop,
                              "attack": attack, "release": release, "family": family}
        return fn
    return deco


# --------------------------------------------------------------------------------------------
# shared building blocks
# --------------------------------------------------------------------------------------------

def nburst(r, dur, lo, hi, attack, tau, order=2):
    """Band-limited noise burst with attack/decay envelope, unit peak."""
    n = secs(dur)
    return norm(band_noise(n, r, lo, hi, SR, order) * env_ad(n, attack, tau))


def thump(f0, f1, dur, tau_f, tau_a, attack=0.001):
    """Pitched-down sine 'body' (kick-drum style), unit peak."""
    n = secs(dur)
    return norm(chirp(f0, f1, n, tau_f) * env_ad(n, attack, tau_a))


def click(r, ms=2.0, lo=1500.0, hi=12000.0):
    n = secs(max(ms * 6.0, 6.0) / 1000.0)
    return norm(band_noise(n, r, lo, hi) * env_exp(n, ms / 1000.0))


def ping(freqs, taus, amps, dur, r):
    return norm(modal(freqs, taus, amps, dur, r))


def tone(freq, dur, a=0.004, d=0.08, s=0.0, rel=0.02, harm=(1.0,)):
    n = secs(dur)
    return additive(freq, n, list(harm)) * env_adsr(n, a, d, s, rel)


def bell_note(freq, dur, tau, r=None, bright=1.0):
    """Soft FM-free bell: a few slightly inharmonic partials with faster-decaying highs."""
    ratios = (1.0, 2.0, 3.01, 4.2, 5.4)
    amps = (1.0, 0.45 * bright, 0.22 * bright, 0.12 * bright, 0.06 * bright)
    taus = [tau / (1.0 + 0.9 * i) for i in range(len(ratios))]
    n = secs(dur)
    x = modal([freq * q for q in ratios], taus, amps, dur, r)
    return x * np.minimum(1.0, tt(n) / 0.002)


# --------------------------------------------------------------------------------------------
# gunshots
# --------------------------------------------------------------------------------------------

def gunshot(r, crack=(2200.0, 11000.0), crack_ms=3.5, crack_gain=1.0,
            body=(260.0, 3600.0), body_tau=0.045, body_gain=1.0,
            boom=(110.0, 520.0), boom_tau=0.05, boom_gain=0.6,
            thump_f=(170.0, 65.0), thump_tau=0.03, thump_gain=0.35,
            mech_f=0.0, mech_gain=0.0, mech_t=0.02,
            tail_rt=0.5, tail_gain=0.22, tail_lp=4200.0, slap=0.0, slap_gain=0.0,
            drive=1.8, seed=1):
    """Transient crack + pink-noise body + low-mid boom + short sine thump (+ action clatter)
    -> saturation -> outdoor tail (+ slap-back echoes for the long guns)."""
    m = Mix(0.05)
    n_c = secs(0.03)
    c = norm(band_noise(n_c, r, crack[0], crack[1]) * env_exp(n_c, crack_ms / 1000.0))
    m.add(c, 0.0, crack_gain)
    n_b = secs(body_tau * 9.0)
    m.add(norm(colored(n_b, r, -3.0, body[0], body[1]) * env_ad(n_b, 0.0006, body_tau)), 0.0, body_gain)
    n_o = secs(boom_tau * 9.0)
    m.add(norm(colored(n_o, r, -3.0, boom[0], boom[1]) * env_ad(n_o, 0.0015, boom_tau)), 0.0, boom_gain)
    m.add(thump(thump_f[0], thump_f[1], thump_tau * 7.0, thump_tau * 0.6, thump_tau, 0.0008),
          0.0, thump_gain)
    if mech_gain > 0.0:
        mech = ping([mech_f, mech_f * 1.71, mech_f * 2.63], [0.012, 0.009, 0.006], [1.0, 0.6, 0.4], 0.07, r)
        m.add(mech, mech_t, mech_gain)
        m.add(click(r, 1.2, 2500.0, 9000.0), mech_t, mech_gain * 0.6)
    dry = soft_clip(norm(m.b), drive)
    out = reverb(dry, tail_rt, tail_gain, seed, lp_hz=tail_lp, hp_hz=180.0, predelay=0.018)
    if slap > 0.0:
        mm = Mix(len(out) / SR)
        mm.add(out)
        mm.add(bp(dry, 250.0, 2600.0, 1, pad=256), slap, slap_gain)
        mm.add(bp(dry, 250.0, 1500.0, 1, pad=256), slap * 2.15, slap_gain * 0.45)
        out = mm.b
    return out


@sound("pistol_shot", LOUD, family="weapon")
def pistol_shot(r):
    return gunshot(r, crack=(2400.0, 11000.0), crack_ms=3.0, body=(320.0, 4200.0), body_tau=0.04,
                   boom=(140.0, 600.0), boom_tau=0.04, boom_gain=0.55,
                   thump_f=(190.0, 80.0), thump_tau=0.026, thump_gain=0.3,
                   mech_f=3100.0, mech_gain=0.12, mech_t=0.03,
                   tail_rt=0.42, tail_gain=0.2, drive=1.8, seed=11)


@sound("heavy_pistol_shot", LOUD, family="weapon")
def heavy_pistol_shot(r):
    return gunshot(r, crack=(1800.0, 9500.0), crack_ms=4.5, body=(220.0, 3400.0), body_tau=0.06,
                   boom=(100.0, 480.0), boom_tau=0.065, boom_gain=0.8,
                   thump_f=(150.0, 62.0), thump_tau=0.04, thump_gain=0.45,
                   mech_f=2400.0, mech_gain=0.1, mech_t=0.04,
                   tail_rt=0.65, tail_gain=0.26, tail_lp=3600.0, drive=2.2, seed=12)


@sound("smg_shot", LOUD, family="weapon")
def smg_shot(r):
    return gunshot(r, crack=(3000.0, 12000.0), crack_ms=2.2, body=(450.0, 5200.0), body_tau=0.028,
                   boom=(170.0, 700.0), boom_tau=0.026, boom_gain=0.45,
                   thump_f=(210.0, 95.0), thump_tau=0.018, thump_gain=0.22,
                   mech_f=3800.0, mech_gain=0.16, mech_t=0.022,
                   tail_rt=0.28, tail_gain=0.15, tail_lp=5200.0, drive=1.6, seed=13)


@sound("rifle_shot", LOUD, family="weapon")
def rifle_shot(r):
    return gunshot(r, crack=(2600.0, 12000.0), crack_ms=3.2, crack_gain=1.1,
                   body=(300.0, 4600.0), body_tau=0.05, body_gain=1.0,
                   boom=(120.0, 560.0), boom_tau=0.05, boom_gain=0.6,
                   thump_f=(160.0, 68.0), thump_tau=0.03, thump_gain=0.32,
                   mech_f=2900.0, mech_gain=0.12, mech_t=0.035,
                   tail_rt=0.75, tail_gain=0.26, tail_lp=4600.0, slap=0.11, slap_gain=0.1,
                   drive=2.0, seed=14)


@sound("shotgun_shot", LOUD, family="weapon")
def shotgun_shot(r):
    return gunshot(r, crack=(1500.0, 9000.0), crack_ms=6.0, crack_gain=0.9,
                   body=(180.0, 3800.0), body_tau=0.095, body_gain=1.3,
                   boom=(85.0, 420.0), boom_tau=0.1, boom_gain=0.95,
                   thump_f=(125.0, 58.0), thump_tau=0.055, thump_gain=0.5,
                   tail_rt=0.95, tail_gain=0.3, tail_lp=3400.0, slap=0.14, slap_gain=0.1,
                   drive=2.6, seed=15)


@sound("sniper_shot", LOUD, family="weapon")
def sniper_shot(r):
    return gunshot(r, crack=(2800.0, 13000.0), crack_ms=3.0, crack_gain=1.2,
                   body=(220.0, 4200.0), body_tau=0.075, body_gain=1.05,
                   boom=(90.0, 460.0), boom_tau=0.09, boom_gain=0.85,
                   thump_f=(140.0, 55.0), thump_tau=0.06, thump_gain=0.5,
                   tail_rt=1.7, tail_gain=0.34, tail_lp=3800.0, slap=0.19, slap_gain=0.16,
                   drive=2.4, seed=16)


@sound("suppressed_shot", ("peak", -8.0), family="weapon")
def suppressed_shot(r):
    m = Mix(0.3)
    m.add(nburst(r, 0.12, 900.0, 3800.0, 0.0015, 0.018), 0.0, 1.0)      # muffled gas "thwip"
    m.add(nburst(r, 0.2, 180.0, 900.0, 0.002, 0.03), 0.0, 0.6)          # soft body
    m.add(thump(140.0, 70.0, 0.12, 0.02, 0.025), 0.0, 0.45)
    m.add(ping([3300.0, 5200.0, 7100.0], [0.012, 0.008, 0.006], [1.0, 0.6, 0.35], 0.06, r), 0.012, 0.35)
    m.add(nburst(r, 0.2, 2500.0, 8000.0, 0.01, 0.045), 0.01, 0.1)       # gas hiss after the shot
    return lp(m.b, 6500.0, 2, pad=512)


@sound("rocket_launch", LOUD, family="weapon")
def rocket_launch(r):
    dur = 1.5
    n = secs(dur)
    t = tt(n)
    src = white(n, r)
    cut = 500.0 + 4200.0 * smoothstep(0.0, 0.35, t) * np.exp(-np.maximum(t - 0.35, 0.0) / 0.9)
    whoosh = svf(src, cut, 1.6, "bp")
    env = env_pts(n, [(0, 0), (0.015, 1.0), (0.25, 0.75), (0.6, 0.45), (dur, 0.0)])
    roar = colored(n, r, -5.0, 50.0, 900.0) * env_pts(n, [(0, 0), (0.03, 1), (0.5, 0.5), (dur, 0)])
    m = Mix(dur)
    m.add(norm(whoosh * env), 0.0, 0.9)
    m.add(norm(roar), 0.0, 0.7)
    m.add(thump(180.0, 55.0, 0.3, 0.03, 0.06), 0.0, 1.0)                # ignition pop
    m.add(nburst(r, 0.1, 1200.0, 9000.0, 0.0005, 0.012), 0.0, 0.8)
    return reverb(soft_clip(norm(m.b), 1.6), 0.9, 0.18, 21, lp_hz=3500.0)


@sound("grenade_launcher_shot", LOUD, family="weapon")
def grenade_launcher_shot(r):
    m = Mix(0.4)
    m.add(thump(240.0, 95.0, 0.3, 0.035, 0.05, 0.002), 0.0, 0.75)        # hollow tube "thoomp"
    tube = ping([410.0, 830.0, 1270.0], [0.05, 0.03, 0.02], [1.0, 0.5, 0.25], 0.25, r)
    m.add(tube, 0.0, 0.45)
    m.add(nburst(r, 0.25, 400.0, 5000.0, 0.001, 0.035), 0.0, 1.0)        # air puff
    m.add(ping([2600.0, 4100.0], [0.015, 0.01], [1.0, 0.5], 0.08, r), 0.05, 0.15)
    return reverb(soft_clip(norm(m.b), 1.4), 0.45, 0.16, 22, lp_hz=3200.0)


@sound("dry_fire", ("peak", -9.0), family="weapon")
def dry_fire(r):
    m = Mix(0.12)
    m.add(click(r, 1.0, 2000.0, 10000.0), 0.0, 0.8)
    m.add(ping([2700.0, 4350.0, 6900.0], [0.014, 0.01, 0.007], [1.0, 0.7, 0.4], 0.09, r), 0.0, 0.9)
    m.add(ping([1500.0, 3100.0], [0.01, 0.008], [1.0, 0.5], 0.06, r), 0.028, 0.35)
    return m.b


def metal_clack(r, f, gain_click=0.8, tau=0.02, dur=0.12):
    x = Mix(dur)
    x.add(click(r, 1.5, 1200.0, 9000.0), 0.0, gain_click)
    x.add(ping([f, f * 1.48, f * 2.31, f * 3.4], [tau, tau * 0.8, tau * 0.55, tau * 0.4],
               [1.0, 0.7, 0.45, 0.3], dur, r), 0.0, 1.0)
    x.add(thump(f * 0.12, f * 0.07, dur, 0.01, 0.018), 0.0, 0.5)
    return norm(x.b)


@sound("reload", MID, family="weapon")
def reload(r):
    m = Mix(1.15)
    m.add(metal_clack(r, 2100.0), 0.02, 0.7)                             # magazine release
    slide_out = nburst(r, 0.16, 1500.0, 6000.0, 0.03, 0.05) * 0.35
    m.add(slide_out, 0.05, 1.0)                                          # mag sliding out
    m.add(nburst(r, 0.14, 1200.0, 5000.0, 0.05, 0.03), 0.42, 0.3)        # mag sliding in
    m.add(metal_clack(r, 1500.0, tau=0.028), 0.53, 1.0)                  # mag seated
    m.add(nburst(r, 0.1, 2000.0, 7000.0, 0.04, 0.02), 0.82, 0.4)         # slide pulled
    m.add(metal_clack(r, 2600.0, tau=0.016), 0.86, 0.75)
    m.add(metal_clack(r, 1850.0, tau=0.024), 0.985, 0.95)                # slide released
    return reverb(m.b, 0.18, 0.08, 31, lp_hz=5000.0)


@sound("weapon_switch", SOFT, family="weapon")
def weapon_switch(r):
    m = Mix(0.28)
    m.add(nburst(r, 0.2, 700.0, 4500.0, 0.05, 0.05), 0.0, 0.55)          # cloth / sling rustle
    m.add(metal_clack(r, 2300.0, 0.5, 0.014, 0.08), 0.13, 0.8)
    m.add(click(r, 1.0, 3000.0, 9000.0), 0.19, 0.35)
    return m.b


@sound("melee_swing", SOFT, family="weapon")
def melee_swing(r):
    dur = 0.3
    n = secs(dur)
    t = tt(n)
    cut = 500.0 + 1700.0 * np.exp(-((t - 0.13) / 0.07) ** 2)
    x = svf(white(n, r), cut, 2.2, "bp") * np.exp(-((t - 0.13) / 0.075) ** 2)
    return x


@sound("melee_hit", MID, family="impact")
def melee_hit(r):
    m = Mix(0.25)
    m.add(thump(200.0, 95.0, 0.16, 0.02, 0.03), 0.0, 0.6)
    m.add(nburst(r, 0.12, 400.0, 3500.0, 0.0008, 0.024), 0.0, 1.0)
    m.add(ping([330.0, 710.0, 1180.0], [0.05, 0.035, 0.02], [1.0, 0.6, 0.35], 0.2, r), 0.0, 0.5)
    return soft_clip(norm(m.b), 1.3)


@sound("punch_hit", MID, family="impact")
def punch_hit(r):
    m = Mix(0.2)
    m.add(thump(200.0, 100.0, 0.14, 0.018, 0.028), 0.0, 0.6)
    m.add(nburst(r, 0.11, 250.0, 2200.0, 0.001, 0.026), 0.0, 1.0)        # fleshy slap
    m.add(nburst(r, 0.06, 1500.0, 5000.0, 0.0005, 0.008), 0.0, 0.3)
    return soft_clip(norm(m.b), 1.2)


@sound("knife_hit", MID, family="impact")
def knife_hit(r):
    m = Mix(0.22)
    m.add(nburst(r, 0.08, 2500.0, 10000.0, 0.0005, 0.012), 0.0, 0.8)     # sharp "shk"
    m.add(nburst(r, 0.14, 300.0, 1500.0, 0.004, 0.03), 0.008, 0.9)       # wet body
    m.add(thump(170.0, 90.0, 0.12, 0.02, 0.025), 0.008, 0.3)
    m.add(ping([4200.0, 6800.0], [0.02, 0.012], [1.0, 0.5], 0.08, r), 0.0, 0.2)
    return m.b


@sound("grenade_bounce", MID, family="impact")
def grenade_bounce(r):
    m = Mix(0.3)
    m.add(click(r, 1.2, 1800.0, 9000.0), 0.0, 0.7)
    m.add(ping([1250.0, 2140.0, 3370.0, 4900.0, 6300.0], [0.05, 0.04, 0.03, 0.02, 0.015],
               [1.0, 0.8, 0.5, 0.35, 0.2], 0.28, r), 0.0, 1.0)
    m.add(thump(190.0, 110.0, 0.1, 0.015, 0.02), 0.0, 0.6)
    return m.b


@sound("pin_pull", SOFT, family="weapon")
def pin_pull(r):
    m = Mix(0.3)
    m.add(click(r, 1.0, 3000.0, 11000.0), 0.0, 0.6)
    m.add(nburst(r, 0.05, 2500.0, 8000.0, 0.01, 0.012), 0.005, 0.4)      # ring scraping out
    m.add(ping([4700.0, 7350.0, 9900.0], [0.09, 0.06, 0.04], [1.0, 0.55, 0.3], 0.28, r), 0.035, 0.9)
    return m.b


# --------------------------------------------------------------------------------------------
# bullet impacts, glass, explosions
# --------------------------------------------------------------------------------------------

@sound("impact_concrete", MID, family="impact")
def impact_concrete(r):
    m = Mix(0.3)
    m.add(nburst(r, 0.06, 1800.0, 9000.0, 0.0004, 0.008), 0.0, 1.0)      # crack
    m.add(nburst(r, 0.25, 400.0, 2600.0, 0.002, 0.045), 0.002, 0.6)      # dust / chips
    m.add(thump(210.0, 110.0, 0.08, 0.012, 0.018), 0.0, 0.5)
    for _ in range(4):                                                    # falling grit
        m.add(click(r, 0.8, 2500.0, 8000.0), r.uniform(0.04, 0.2), r.uniform(0.05, 0.16))
    return m.b


@sound("impact_metal", MID, family="impact")
def impact_metal(r):
    m = Mix(0.45)
    m.add(click(r, 0.8, 2500.0, 12000.0), 0.0, 0.9)
    m.add(ping([870.0, 1730.0, 2480.0, 3690.0, 5210.0, 7400.0],
               [0.16, 0.12, 0.1, 0.07, 0.05, 0.03], [0.8, 1.0, 0.7, 0.55, 0.4, 0.25], 0.42, r), 0.0, 1.0)
    return m.b


@sound("impact_glass", MID, family="impact")
def impact_glass(r):
    m = Mix(0.3)
    m.add(click(r, 0.6, 4000.0, 14000.0), 0.0, 1.0)
    m.add(ping([3150.0, 4720.0, 6480.0, 8900.0], [0.05, 0.04, 0.03, 0.02], [1.0, 0.8, 0.6, 0.35], 0.25, r), 0.0, 0.8)
    for _ in range(5):
        f = r.uniform(4500.0, 11000.0)
        m.add(ping([f, f * 1.37], [0.02, 0.012], [1.0, 0.5], 0.07, r), r.uniform(0.02, 0.18), r.uniform(0.08, 0.22))
    return m.b


@sound("impact_flesh", MID, family="impact")
def impact_flesh(r):
    m = Mix(0.25)
    m.add(thump(170.0, 85.0, 0.14, 0.02, 0.028), 0.0, 0.5)
    m.add(nburst(r, 0.15, 200.0, 1400.0, 0.002, 0.03), 0.0, 1.0)
    n = secs(0.12)
    squelch = band_noise(n, r, 700.0, 2600.0) * env_ad(n, 0.01, 0.025) * (0.6 + 0.4 * sine(38.0, n))
    m.add(norm(squelch), 0.012, 0.35)
    return m.b


@sound("impact_wood", MID, family="impact")
def impact_wood(r):
    m = Mix(0.25)
    m.add(click(r, 1.0, 1200.0, 7000.0), 0.0, 0.7)
    m.add(ping([310.0, 690.0, 1140.0, 1820.0], [0.05, 0.035, 0.022, 0.014], [1.0, 0.8, 0.5, 0.3], 0.22, r), 0.0, 1.0)
    m.add(nburst(r, 0.1, 900.0, 4000.0, 0.001, 0.02), 0.0, 0.4)          # splinters
    return m.b


@sound("impact_dirt", MID, family="impact")
def impact_dirt(r):
    m = Mix(0.3)
    m.add(thump(150.0, 80.0, 0.1, 0.015, 0.022), 0.0, 0.4)
    m.add(nburst(r, 0.22, 250.0, 2000.0, 0.003, 0.04), 0.0, 1.0)
    m.add(nburst(r, 0.25, 1500.0, 5000.0, 0.02, 0.05), 0.01, 0.22)       # scattering soil
    return m.b


@sound("impact_water", MID, family="impact")
def impact_water(r):
    m = Mix(0.4)
    n = secs(0.09)
    plip = sine(glide(520.0, 1500.0, n, 0.03), n) * env_ad(n, 0.002, 0.022)
    m.add(norm(plip), 0.0, 0.8)
    m.add(nburst(r, 0.3, 1200.0, 7000.0, 0.004, 0.06), 0.0, 0.8)
    n2 = secs(0.07)
    m.add(norm(sine(glide(700.0, 1900.0, n2, 0.025), n2) * env_ad(n2, 0.002, 0.016)), 0.07, 0.35)
    return m.b


@sound("ricochet", MID, family="impact")
def ricochet(r):
    dur = 0.5
    n = secs(dur)
    t = tt(n)
    f = glide(4200.0, 1100.0, n, 0.14) * (1.0 + 0.025 * np.sin(TAU * 31.0 * t))
    whine = additive(f, n, [1.0, 0.35, 0.18, 0.08]) * env_ad(n, 0.002, 0.13)
    m = Mix(dur)
    m.add(norm(whine), 0.0, 0.9)
    m.add(click(r, 0.7, 2500.0, 12000.0), 0.0, 0.9)
    m.add(ping([2900.0, 5300.0], [0.03, 0.02], [1.0, 0.6], 0.1, r), 0.0, 0.4)
    return reverb(m.b, 0.35, 0.1, 41, lp_hz=6000.0)


def tinkles(m: Mix, r, count, t0, t1, f_lo=2500.0, f_hi=11000.0, gain=0.3, decay=2.5):
    """Scatter small glassy/metallic pings; density and level fall off with time."""
    for _ in range(count):
        u = r.uniform(0.0, 1.0) ** decay
        at = t0 + (t1 - t0) * u
        f = math.exp(r.uniform(math.log(f_lo), math.log(f_hi)))
        tau = r.uniform(0.008, 0.04)
        g = gain * (1.0 - 0.75 * u) * r.uniform(0.3, 1.0)
        m.add(ping([f, f * r.uniform(1.3, 1.6), f * r.uniform(2.0, 2.6)], [tau, tau * 0.7, tau * 0.5],
                   [1.0, 0.5, 0.25], tau * 6.0, r), at, g)


@sound("glass_break", MID, family="impact")
def glass_break(r):
    m = Mix(1.1)
    m.add(nburst(r, 0.12, 2200.0, 13000.0, 0.0005, 0.02), 0.0, 1.0)      # initial crash
    m.add(nburst(r, 0.35, 3500.0, 12000.0, 0.01, 0.09), 0.01, 0.5)       # shard wash
    m.add(ping([1900.0, 3100.0, 4650.0, 6200.0], [0.05, 0.04, 0.03, 0.02], [1, 0.8, 0.6, 0.4], 0.25, r), 0.0, 0.5)
    tinkles(m, r, 70, 0.02, 0.95, gain=0.4)
    return reverb(m.b, 0.3, 0.06, 43, lp_hz=8000.0, hp_hz=600.0)


def explosion(r, big: bool):
    dur = 2.8 if big else 1.6
    n = secs(dur)
    m = Mix(dur)
    # initial pressure crack
    m.add(nburst(r, 0.08, 700.0, 9000.0, 0.0004, 0.014), 0.0, 1.0)
    # sub-bass thump (kept short so it punches instead of swamping the mix)
    if big:
        m.add(thump(95.0, 34.0, 1.0, 0.12, 0.22, 0.003), 0.0, 0.8)
        m.add(thump(150.0, 55.0, 0.4, 0.05, 0.09, 0.002), 0.0, 0.5)
    else:
        m.add(thump(125.0, 45.0, 0.6, 0.07, 0.13, 0.002), 0.0, 0.7)
    # roaring body: noise through a low-pass that closes as the fireball cools
    src = white(n, r)
    f_hi, f_lo, tau_f = (6000.0, 260.0, 0.45) if big else (7000.0, 340.0, 0.25)
    body = svf(src, glide(f_hi, f_lo, n, tau_f), 0.8, "lp")
    body *= env_ad(n, 0.004, 0.5 if big else 0.26)
    m.add(norm(body), 0.0, 1.2)
    # mid-range roar that carries on small speakers
    roar = colored(n, r, -3.0, 150.0, 2200.0) * (0.6 + 0.4 * np.abs(slow_noise(n, r, 9.0)))
    roar *= env_ad(n, 0.01, 0.6 if big else 0.3)
    m.add(norm(roar), 0.0, 0.8)
    # rolling low rumble with irregular bumps
    rumble = colored(n, r, -5.0, 35.0, 260.0 if big else 320.0)
    rumble *= (0.55 + 0.45 * np.abs(slow_noise(n, r, 5.0))) * env_ad(n, 0.03, 0.8 if big else 0.36)
    m.add(norm(rumble), 0.0, 0.5 if big else 0.35)
    # debris: crackles and falling bits
    for _ in range(60 if big else 30):
        at = 0.12 + (dur - 0.5) * r.uniform(0.0, 1.0) ** 1.7
        lo = r.uniform(700.0, 3500.0)
        g = r.uniform(0.05, 0.2) * (1.0 - at / dur)
        m.add(nburst(r, 0.05, lo, lo * r.uniform(1.8, 3.2), 0.0006, r.uniform(0.004, 0.02)), at, g)
    dry = soft_clip(norm(m.b), 2.6 if big else 2.2)
    return reverb(dry, 2.3 if big else 1.4, 0.3 if big else 0.24, 51 if big else 52,
                  lp_hz=3200.0 if big else 3800.0, hp_hz=70.0, predelay=0.03)


@sound("explosion_small", LOUD, family="explosion", release=0.05)
def explosion_small(r):
    return explosion(r, False)


@sound("explosion_large", ("peak", -2.0), family="explosion", release=0.08)
def explosion_large(r):
    return explosion(r, True)


@sound("tire_pop", LOUD, family="vehicle")
def tire_pop(r):
    m = Mix(0.7)
    m.add(nburst(r, 0.05, 700.0, 8000.0, 0.0004, 0.007), 0.0, 1.0)
    m.add(thump(260.0, 90.0, 0.15, 0.02, 0.03), 0.0, 0.9)
    n = secs(0.6)
    hiss = svf(white(n, r), glide(7000.0, 1800.0, n, 0.2), 1.2, "bp") * env_ad(n, 0.01, 0.14)
    m.add(norm(hiss), 0.02, 0.4)
    return reverb(soft_clip(norm(m.b), 1.5), 0.4, 0.12, 53, lp_hz=4000.0)


# --------------------------------------------------------------------------------------------
# footsteps and body foley
# --------------------------------------------------------------------------------------------

@sound("footstep_concrete", SOFT, family="footstep")
def footstep_concrete(r):
    m = Mix(0.2)
    m.add(nburst(r, 0.05, 900.0, 4200.0, 0.0008, 0.008), 0.0, 1.0)       # heel tick
    m.add(thump(190.0, 110.0, 0.06, 0.012, 0.012), 0.0, 0.3)
    m.add(nburst(r, 0.06, 300.0, 1400.0, 0.001, 0.012), 0.0, 0.6)        # sole body
    m.add(nburst(r, 0.09, 1200.0, 5500.0, 0.012, 0.02), 0.055, 0.35)     # sole scuff
    return m.b


@sound("footstep_grass", SOFT, family="footstep")
def footstep_grass(r):
    m = Mix(0.25)
    m.add(nburst(r, 0.2, 1200.0, 6000.0, 0.02, 0.04), 0.0, 1.0)          # blades brushing
    m.add(thump(150.0, 90.0, 0.07, 0.012, 0.014, 0.004), 0.004, 0.18)
    m.add(nburst(r, 0.12, 500.0, 2400.0, 0.012, 0.03), 0.0, 0.5)         # stems compressing
    m.add(nburst(r, 0.12, 1800.0, 7000.0, 0.015, 0.03), 0.07, 0.4)
    return m.b


@sound("footstep_sand", SOFT, family="footstep")
def footstep_sand(r):
    n = secs(0.24)
    grain = band_noise(n, r, 600.0, 3200.0) * env_ad(n, 0.03, 0.055)
    grain *= 0.55 + 0.45 * np.abs(slow_noise(n, r, 70.0))                # crunchy granularity
    m = Mix(0.25)
    m.add(norm(grain), 0.0, 1.0)
    m.add(thump(140.0, 85.0, 0.07, 0.015, 0.016, 0.006), 0.0, 0.15)
    return m.b


@sound("footstep_metal", SOFT, family="footstep")
def footstep_metal(r):
    m = Mix(0.3)
    m.add(click(r, 1.0, 1500.0, 8000.0), 0.0, 0.7)
    m.add(thump(160.0, 95.0, 0.08, 0.012, 0.02), 0.0, 0.7)
    m.add(ping([540.0, 1160.0, 1890.0, 2740.0], [0.07, 0.05, 0.035, 0.022], [1.0, 0.8, 0.5, 0.3], 0.28, r), 0.0, 0.9)
    return m.b


@sound("footstep_wood", SOFT, family="footstep")
def footstep_wood(r):
    m = Mix(0.22)
    m.add(click(r, 1.2, 900.0, 5000.0), 0.0, 0.9)
    m.add(ping([175.0, 410.0, 760.0, 1320.0], [0.04, 0.03, 0.02, 0.012], [0.8, 0.8, 0.5, 0.3], 0.2, r), 0.0, 1.0)
    m.add(nburst(r, 0.07, 500.0, 3200.0, 0.001, 0.014), 0.0, 0.5)
    m.add(nburst(r, 0.06, 700.0, 3000.0, 0.01, 0.015), 0.05, 0.25)
    return m.b


@sound("footstep_water", SOFT, family="footstep")
def footstep_water(r):
    m = Mix(0.35)
    n = secs(0.3)
    sp = band_noise(n, r, 900.0, 6000.0) * env_ad(n, 0.008, 0.06) * (0.6 + 0.4 * np.abs(slow_noise(n, r, 45.0)))
    m.add(norm(sp), 0.0, 1.0)
    for i in range(3):
        nn = secs(0.06)
        f0 = r.uniform(450.0, 800.0)
        m.add(norm(sine(glide(f0, f0 * 2.4, nn, 0.02), nn) * env_ad(nn, 0.002, 0.014)), 0.02 + 0.06 * i + r.uniform(0, 0.02), 0.3)
    m.add(thump(120.0, 70.0, 0.08, 0.012, 0.02), 0.0, 0.35)
    return m.b


@sound("jump_land", MID, family="footstep")
def jump_land(r):
    m = Mix(0.32)
    for (at, g) in ((0.0, 1.0), (0.028, 0.8)):                           # two feet
        m.add(thump(175.0, 85.0, 0.12, 0.02, 0.026), at, 0.45 * g)
        m.add(nburst(r, 0.09, 250.0, 1800.0, 0.001, 0.02), at, 0.9 * g)
        m.add(nburst(r, 0.06, 900.0, 4200.0, 0.001, 0.012), at, 0.55 * g)
    m.add(nburst(r, 0.2, 500.0, 3000.0, 0.03, 0.05), 0.02, 0.3)          # clothing
    return m.b


@sound("body_fall", MID, family="footstep")
def body_fall(r):
    m = Mix(0.6)
    m.add(thump(150.0, 70.0, 0.22, 0.03, 0.04), 0.0, 0.55)
    m.add(nburst(r, 0.22, 160.0, 1600.0, 0.003, 0.045), 0.0, 1.0)
    m.add(thump(160.0, 80.0, 0.14, 0.025, 0.028), 0.17, 0.3)             # limbs settle
    m.add(nburst(r, 0.3, 600.0, 3500.0, 0.04, 0.07), 0.05, 0.3)          # cloth
    m.add(nburst(r, 0.1, 300.0, 1500.0, 0.004, 0.025), 0.17, 0.35)
    return m.b


def splash(r, big: bool):
    dur = 1.6 if big else 0.7
    n = secs(dur)
    m = Mix(dur)
    src = white(n, r)
    cut = glide(5200.0 if big else 6500.0, 900.0 if big else 1400.0, n, 0.3 if big else 0.14)
    body = svf(src, cut, 0.9, "bp") * env_ad(n, 0.006, 0.32 if big else 0.12)
    m.add(norm(body), 0.0, 1.0)
    m.add(thump(170.0 if big else 210.0, 75.0 if big else 100.0, 0.25, 0.04, 0.045 if big else 0.03), 0.0, 0.4 if big else 0.3)
    low = colored(n, r, -3.0, 120.0, 900.0) * env_ad(n, 0.01, 0.25 if big else 0.08)
    m.add(norm(low), 0.0, 0.7 if big else 0.4)
    spray = band_noise(n, r, 3500.0, 12000.0) * env_pts(n, [(0, 0), (0.05, 1.0), (dur * 0.5, 0.25), (dur, 0.0)])
    m.add(norm(spray), 0.03, 0.3)
    for _ in range(14 if big else 6):                                    # bubbles / droplets
        nn = secs(r.uniform(0.03, 0.07))
        f0 = r.uniform(350.0, 1100.0)
        at = r.uniform(0.05, dur * 0.8)
        m.add(norm(sine(glide(f0, f0 * r.uniform(1.8, 2.8), nn, 0.02), nn) * env_ad(nn, 0.002, 0.012)),
              at, r.uniform(0.08, 0.25) * (1.0 - at / dur))
    return m.b


@sound("splash_small", MID, family="water")
def splash_small(r):
    return splash(r, False)


@sound("splash_large", ("peak", -4.0), family="water", release=0.05)
def splash_large(r):
    return reverb(splash(r, True), 0.5, 0.08, 61, lp_hz=5000.0)


@sound("swim_stroke", SOFT, family="water", attack=0.01)
def swim_stroke(r):
    dur = 0.55
    n = secs(dur)
    t = tt(n)
    swoosh = svf(white(n, r), 500.0 + 1900.0 * np.exp(-((t - 0.2) / 0.12) ** 2), 1.2, "bp")
    swoosh *= np.exp(-((t - 0.22) / 0.14) ** 2)
    m = Mix(dur)
    m.add(norm(swoosh), 0.0, 1.0)
    for _ in range(5):
        nn = secs(0.05)
        f0 = r.uniform(400.0, 900.0)
        m.add(norm(sine(glide(f0, f0 * 2.2, nn, 0.018), nn) * env_ad(nn, 0.002, 0.012)), r.uniform(0.15, 0.45), r.uniform(0.1, 0.25))
    return m.b


# --------------------------------------------------------------------------------------------
# voices - formant-filtered glottal pulses, strictly non-verbal
# --------------------------------------------------------------------------------------------

VOW = {
    "a": [(780.0, 90.0, 1.0), (1220.0, 110.0, 0.55), (2600.0, 170.0, 0.28), (3500.0, 220.0, 0.12)],
    "uh": [(620.0, 80.0, 1.0), (1080.0, 100.0, 0.5), (2450.0, 160.0, 0.22), (3400.0, 220.0, 0.1)],
    "o": [(480.0, 75.0, 1.0), (860.0, 95.0, 0.5), (2500.0, 160.0, 0.18), (3300.0, 220.0, 0.08)],
    "e": [(520.0, 75.0, 1.0), (1750.0, 110.0, 0.45), (2550.0, 160.0, 0.25), (3500.0, 220.0, 0.1)],
    "ae": [(700.0, 90.0, 1.0), (1650.0, 120.0, 0.55), (2500.0, 170.0, 0.3), (3500.0, 220.0, 0.12)],
    "m": [(280.0, 60.0, 1.0), (1000.0, 120.0, 0.12), (2300.0, 200.0, 0.06)],
}


def vowel(name, scale=1.0):
    return [(f * scale, bw * scale, a) for (f, bw, a) in VOW[name]]


def glottal(f0, n, r, jitter=0.01, breath=0.08, sr=SR):
    """Rosenberg-style glottal pulse train (differentiated) + aspiration noise."""
    f = np.asarray(f0, dtype=np.float64) * (1.0 + jitter * slow_noise(n, r, 18.0, sr))
    ph = (phase_of(f, n, sr) / TAU) % 1.0
    op, cl = 0.42, 0.16
    g = np.where(ph < op, 0.5 * (1.0 - np.cos(np.pi * ph / op)),
                 np.where(ph < op + cl, np.cos(0.5 * np.pi * (ph - op) / cl), 0.0))
    src = np.diff(g, prepend=g[0]) * (sr / 2000.0)
    asp = band_noise(n, r, 1500.0, 7000.0, sr) * (0.4 + 0.6 * g)
    return src + breath * asp


def voice(r, dur, f0_pts, v0, v1=None, env=None, scale=1.0, jitter=0.012, breath=0.08,
          rough=0.0, noise_mix=0.0):
    n = secs(dur)
    f0 = env_pts(n, f0_pts)
    src = glottal(f0, n, r, jitter, breath)
    if rough > 0.0:                                   # sub-harmonic growl / strained screams
        sub = 0.5 + 0.5 * np.sin(phase_of(f0 * 0.5, n))
        src = src * (1.0 - rough + rough * sub) + rough * 0.3 * band_noise(n, r, 400.0, 3500.0)
    a = formant_filter(src, vowel(v0, scale), pad=1024)
    if v1 is not None:
        b = formant_filter(src, vowel(v1, scale), pad=1024)
        w = np.linspace(0.0, 1.0, n)
        a = a * (1.0 - w) + b * w
    if noise_mix > 0.0:
        a = norm(a) + noise_mix * norm(formant_filter(band_noise(n, r, 300.0, 6000.0), vowel(v0, scale)))
    e = env_pts(n, env) if env is not None else env_adsr(n, 0.01, 0.1, 0.8, 0.05)
    return a * e


@sound("grunt_hit_m", VOICE, family="voice")
def grunt_hit_m(r):
    return voice(r, 0.26, [(0, 135), (0.04, 128), (0.26, 92)], "uh", "o",
                 [(0, 0), (0.012, 1.0), (0.08, 0.7), (0.26, 0.0)], 1.0, 0.02, 0.12, 0.15)


@sound("grunt_hit_f", VOICE, family="voice")
def grunt_hit_f(r):
    return voice(r, 0.24, [(0, 255), (0.04, 240), (0.24, 185)], "a", "uh",
                 [(0, 0), (0.012, 1.0), (0.08, 0.7), (0.24, 0.0)], 1.17, 0.02, 0.12, 0.1)


@sound("scream_m", ("peak", -6.5), family="voice")
def scream_m(r):
    x = voice(r, 0.95, [(0, 210), (0.12, 330), (0.5, 345), (0.95, 250)], "a", "ae",
              [(0, 0), (0.04, 1.0), (0.6, 0.9), (0.95, 0.0)], 1.0, 0.03, 0.15, 0.3)
    return reverb(soft_clip(norm(x), 1.3), 0.5, 0.1, 71, lp_hz=4500.0)


@sound("scream_f", ("peak", -7.0), family="voice")
def scream_f(r):
    x = voice(r, 1.05, [(0, 480), (0.1, 720), (0.55, 760), (1.05, 560)], "a", "ae",
              [(0, 0), (0.04, 1.0), (0.7, 0.9), (1.05, 0.0)], 1.18, 0.025, 0.14, 0.18)
    return reverb(soft_clip(norm(x), 1.2), 0.5, 0.1, 72, lp_hz=5500.0)


@sound("death_m", VOICE, family="voice")
def death_m(r):
    return voice(r, 1.0, [(0, 150), (0.15, 138), (0.6, 100), (1.0, 78)], "a", "uh",
                 [(0, 0), (0.03, 1.0), (0.3, 0.75), (0.7, 0.35), (1.0, 0.0)], 1.0, 0.03, 0.25, 0.2)


@sound("death_f", VOICE, family="voice")
def death_f(r):
    return voice(r, 0.95, [(0, 300), (0.12, 285), (0.55, 215), (0.95, 165)], "a", "uh",
                 [(0, 0), (0.03, 1.0), (0.3, 0.75), (0.65, 0.35), (0.95, 0.0)], 1.17, 0.03, 0.25, 0.12)


@sound("breath_gasp", MID, family="voice", attack=0.01)
def breath_gasp(r):
    dur = 0.75
    n = secs(dur)
    air = formant_filter(colored(n, r, -2.0, 300.0, 8000.0), [(900.0, 400.0, 1.0), (1900.0, 500.0, 0.8), (3200.0, 700.0, 0.4)])
    e = env_pts(n, [(0, 0), (0.1, 0.5), (0.32, 1.0), (0.42, 0.25), (0.5, 0.1), (dur, 0.0)])
    v = voice(r, dur, [(0, 150), (0.3, 205), (dur, 180)], "ae", None,
              [(0, 0), (0.15, 0.3), (0.32, 0.5), (0.42, 0.0), (dur, 0.0)], 1.0, 0.03, 0.4)
    return norm(air * e) + 0.3 * norm(v)


# --------------------------------------------------------------------------------------------
# vehicle one-shots
# --------------------------------------------------------------------------------------------

def crash(r, big: bool):
    dur = 1.7 if big else 0.7
    m = Mix(dur)
    m.add(nburst(r, 0.12, 300.0, 7000.0, 0.0005, 0.02 if big else 0.012), 0.0, 1.0)
    m.add(thump(150.0 if big else 190.0, 60.0 if big else 85.0, 0.35, 0.05, 0.07 if big else 0.04), 0.0, 0.5 if big else 0.4)
    n = secs(dur)
    crunch = band_noise(n, r, 250.0, 5000.0) * env_ad(n, 0.004, 0.28 if big else 0.1)
    crunch *= 0.35 + 0.65 * np.abs(slow_noise(n, r, 55.0))               # tearing sheet metal
    m.add(norm(crunch), 0.0, 0.9)
    base = [410.0, 730.0, 1180.0, 1930.0, 2870.0, 4100.0]
    m.add(ping(base, [0.14, 0.12, 0.09, 0.07, 0.05, 0.03], [1.0, 0.9, 0.7, 0.5, 0.4, 0.25], 0.5, r), 0.0, 0.6)
    hits = 6 if big else 2
    for i in range(hits):                                                # secondary impacts
        at = r.uniform(0.06, dur * 0.55)
        f = r.uniform(300.0, 900.0)
        g = r.uniform(0.2, 0.5) * (1.0 - at / dur)
        m.add(ping([f, f * 1.7, f * 2.9, f * 4.3], [0.07, 0.05, 0.035, 0.02], [1.0, 0.8, 0.5, 0.3], 0.3, r), at, g)
        m.add(nburst(r, 0.06, 500.0, 6000.0, 0.0006, 0.012), at, g * 0.9)
    tinkles(m, r, 45 if big else 14, 0.05, dur * 0.9, gain=0.22 if big else 0.14)
    return reverb(soft_clip(norm(m.b), 2.0 if big else 1.6), 0.9 if big else 0.45, 0.16, 81 if big else 82, lp_hz=4200.0)


@sound("crash_small", ("peak", -4.0), family="vehicle")
def crash_small(r):
    return crash(r, False)


@sound("crash_large", LOUD, family="vehicle", release=0.05)
def crash_large(r):
    return crash(r, True)


@sound("door_open", MID, family="vehicle")
def door_open(r):
    m = Mix(0.32)
    m.add(metal_clack(r, 1700.0, 0.6, 0.014, 0.08), 0.0, 0.9)            # latch
    m.add(thump(150.0, 90.0, 0.1, 0.015, 0.025), 0.004, 0.5)
    n = secs(0.2)
    creak = additive(glide(380.0, 520.0, n, 0.12), n, [1.0, 0.5, 0.35, 0.2]) * env_pts(n, [(0, 0), (0.05, 1), (0.2, 0)])
    creak *= 0.5 + 0.5 * np.abs(slow_noise(n, r, 60.0))
    m.add(norm(creak), 0.07, 0.12)
    m.add(nburst(r, 0.2, 400.0, 2500.0, 0.05, 0.06), 0.06, 0.15)         # seal releasing
    return m.b


@sound("door_close", MID, family="vehicle")
def door_close(r):
    m = Mix(0.4)
    m.add(thump(165.0, 80.0, 0.2, 0.03, 0.035), 0.0, 0.6)                # cabin thunk
    m.add(nburst(r, 0.12, 140.0, 900.0, 0.001, 0.03), 0.0, 0.9)
    m.add(nburst(r, 0.1, 400.0, 2800.0, 0.0008, 0.016), 0.0, 0.7)
    m.add(metal_clack(r, 1450.0, 0.5, 0.014, 0.08), 0.004, 0.45)
    m.add(ping([230.0, 470.0, 810.0], [0.06, 0.04, 0.025], [1.0, 0.6, 0.3], 0.25, r), 0.0, 0.35)
    m.add(nburst(r, 0.08, 1500.0, 6000.0, 0.002, 0.015), 0.03, 0.12)     # window rattle
    return m.b


@sound("engine_start", ("peak", -5.0), family="vehicle", release=0.06)
def engine_start(r):
    dur = 1.45
    m = Mix(dur)
    # starter motor: whirring gear with a cranking pulse
    n = secs(0.72)
    t = tt(n)
    whirr = additive(glide(190.0, 260.0, n, 0.4), n, saw_amps(22, 1.1))
    whirr = bp(whirr, 300.0, 3200.0)
    crank = 0.45 + 0.55 * np.maximum(0.0, np.sin(TAU * 8.5 * t)) ** 2
    m.add(norm(whirr * crank * env_pts(n, [(0, 0), (0.03, 1), (0.66, 1), (0.72, 0)])), 0.0, 0.55)
    m.add(norm(band_noise(n, r, 900.0, 4500.0) * crank * env_pts(n, [(0, 0), (0.03, 1), (0.66, 1), (0.72, 0)])), 0.0, 0.2)
    # engine catches: firing pulses speeding up, then settling to idle
    t0 = 0.6
    at = t0
    fire = 24.0
    while at < dur - 0.05:
        u = (at - t0) / (dur - t0)
        rate = 30.0 + 60.0 * math.sin(min(u * 1.6, 1.0) * math.pi * 0.5) - 22.0 * max(0.0, u - 0.6) / 0.4
        nn = secs(0.035)
        tp = tt(nn)
        pulse = np.exp(-tp / 0.009) * np.sin(TAU * r.uniform(170.0, 210.0) * tp)
        pulse += 0.5 * np.exp(-tp / 0.005) * np.sin(TAU * r.uniform(420.0, 520.0) * tp)
        g = min(1.0, 0.4 + u * 2.0) * (1.0 - smoothstep(0.82, 1.0, u)) * r.uniform(0.85, 1.0)
        m.add(pulse, at, g * 0.9)
        m.add(click(r, 1.5, 600.0, 3500.0), at, g * 0.2)
        at += 1.0 / max(rate, fire)
    return soft_clip(norm(lp(m.b, 5500.0, 2, pad=512)), 1.4)


def horn(freqs, dur, attack, nh, rolloff, formant, drive, vib=0.0):
    """Multi-tone horn: rich harmonic stacks -> diaphragm formant -> mild saturation.
    All partials are integer Hz and the sustain section is cut on a whole number of
    cycles, so the game can loop the middle of the file while the horn is held."""
    n = secs(dur)
    t = tt(n)
    x = np.zeros(n)
    for i, f in enumerate(freqs):
        fr = f * (1.0 + vib * np.sin(TAU * 5.0 * t)) if vib > 0.0 else f
        x += additive(fr, n, saw_amps(nh, rolloff), phases=[0.7 * i, 1.9 * i, 0.3]) * (1.0 if i == 0 else 0.85)
    x = formant_filter(x, formant, pad=0)
    x = soft_clip(norm(x), drive)
    return x * env_pts(n, [(0, 0), (attack, 1.0), (dur - 0.06, 1.0), (dur, 0.0)])


@sound("horn_car", ("rms", -15.0, -4.0), family="vehicle", attack=0.002, release=0.03)
def horn_car(r):
    return horn([420.0, 500.0], 0.9, 0.012, 30, 1.0,
                [(1900.0, 900.0, 1.0), (3200.0, 1200.0, 0.7), (700.0, 500.0, 0.6)], 1.8)


@sound("horn_truck", ("rms", -14.0, -4.0), family="vehicle", attack=0.004, release=0.05)
def horn_truck(r):
    return horn([156.0, 196.0, 234.0], 1.3, 0.05, 44, 0.9,
                [(650.0, 500.0, 1.0), (1500.0, 800.0, 0.8), (2600.0, 1200.0, 0.4)], 2.2)


@sound("horn_bike", ("rms", -16.0, -5.0), family="vehicle", attack=0.002, release=0.03)
def horn_bike(r):
    return horn([620.0, 780.0], 0.55, 0.008, 22, 1.1,
                [(2600.0, 900.0, 1.0), (3900.0, 1200.0, 0.6), (1200.0, 600.0, 0.5)], 1.5)


@sound("tram_bell", MID, family="vehicle", release=0.08)
def tram_bell(r):
    m = Mix(1.5)
    for (at, g) in ((0.0, 1.0), (0.33, 0.85)):
        f = 932.0
        ratios = (0.5, 1.0, 1.183, 1.506, 2.0, 2.514, 3.011, 4.166, 5.433)
        amps = (0.25, 1.0, 0.45, 0.5, 0.6, 0.3, 0.25, 0.15, 0.08)
        taus = (0.9, 0.7, 0.5, 0.45, 0.35, 0.25, 0.2, 0.12, 0.08)
        m.add(ping([f * q for q in ratios], taus, amps, 1.15, r), at, g)
        m.add(click(r, 1.0, 2500.0, 9000.0), at, 0.35 * g)
    return reverb(m.b, 0.6, 0.06, 91, lp_hz=6000.0)


@sound("parachute_open", MID, family="vehicle", release=0.06)
def parachute_open(r):
    dur = 0.9
    n = secs(dur)
    m = Mix(dur)
    whump = svf(white(n, r), glide(2600.0, 260.0, n, 0.12), 0.8, "lp") * env_ad(n, 0.012, 0.16)
    m.add(norm(whump), 0.0, 1.0)
    m.add(thump(150.0, 70.0, 0.3, 0.05, 0.06, 0.008), 0.0, 0.4)
    flut = band_noise(n, r, 300.0, 2800.0) * env_pts(n, [(0, 0), (0.1, 0.6), (0.5, 0.25), (dur, 0)])
    flut *= 0.5 + 0.5 * np.sin(TAU * 17.0 * tt(n)) ** 2
    m.add(norm(flut), 0.05, 0.3)
    m.add(nburst(r, 0.2, 1500.0, 6000.0, 0.02, 0.04), 0.0, 0.25)         # cords snapping taut
    return m.b


# --------------------------------------------------------------------------------------------
# UI, pickups, stingers
# --------------------------------------------------------------------------------------------

def pluck(freq, dur, tau, bright=0.35):
    n = secs(dur)
    x = additive(freq, n, [1.0, bright, bright * 0.45, bright * 0.2])
    return x * env_ad(n, 0.002, tau)


@sound("ui_click", UI, family="ui")
def ui_click(r):
    m = Mix(0.09)
    m.add(pluck(1175.0, 0.09, 0.018), 0.0, 1.0)
    m.add(pluck(1760.0, 0.06, 0.01, 0.2), 0.0, 0.35)
    m.add(click(r, 0.6, 2500.0, 9000.0), 0.0, 0.15)
    return m.b


@sound("ui_hover", ("peak", -16.0), family="ui")
def ui_hover(r):
    return pluck(1568.0, 0.05, 0.009, 0.15)


@sound("ui_open", UI, family="ui")
def ui_open(r):
    m = Mix(0.3)
    m.add(pluck(659.3, 0.2, 0.05), 0.0, 0.8)
    m.add(pluck(987.8, 0.26, 0.07), 0.07, 1.0)
    n = secs(0.22)
    m.add(norm(band_noise(n, r, 2500.0, 9000.0) * env_pts(n, [(0, 0), (0.12, 1), (0.22, 0)])), 0.0, 0.06)
    return m.b


@sound("ui_close", UI, family="ui")
def ui_close(r):
    m = Mix(0.28)
    m.add(pluck(987.8, 0.18, 0.045), 0.0, 0.9)
    m.add(pluck(659.3, 0.22, 0.06), 0.065, 0.9)
    return m.b


@sound("ui_error", ("peak", -13.0), family="ui")
def ui_error(r):
    m = Mix(0.34)
    for at in (0.0, 0.15):
        n = secs(0.12)
        buzz = additive(196.0, n, square_amps(15, 1.2)) + 0.5 * additive(207.7, n, square_amps(11, 1.3))
        m.add(lp(buzz * env_adsr(n, 0.004, 0.05, 0.8, 0.03), 2600.0, 2, pad=256), at, 1.0)
    return m.b


@sound("ui_buy", UI, family="ui")
def ui_buy(r):
    m = Mix(0.5)
    m.add(bell_note(1318.5, 0.3, 0.09, r), 0.0, 0.8)
    m.add(bell_note(1975.5, 0.42, 0.14, r), 0.075, 1.0)
    m.add(bell_note(2637.0, 0.3, 0.1, r, 0.6), 0.15, 0.4)
    return m.b


@sound("ui_tab", UI, family="ui")
def ui_tab(r):
    m = Mix(0.09)
    m.add(ping([523.3, 1046.5, 1580.0], [0.022, 0.014, 0.008], [1.0, 0.4, 0.2], 0.09, None), 0.0, 1.0)
    m.add(click(r, 0.6, 1500.0, 6000.0), 0.0, 0.2)
    return m.b


@sound("pickup_cash", ("peak", -8.0), family="ui")
def pickup_cash(r):
    m = Mix(0.5)
    for i, f in enumerate((1975.5, 2637.0, 3136.0)):                     # coin shimmer B6 E7 G7
        m.add(bell_note(f, 0.3, 0.07, r, 1.2), 0.055 * i, 1.0 - 0.15 * i)
    tinkles(m, r, 6, 0.0, 0.25, 5000.0, 10000.0, 0.15)
    return m.b


@sound("pickup_weapon", ("peak", -8.0), family="ui")
def pickup_weapon(r):
    m = Mix(0.45)
    m.add(metal_clack(r, 1900.0, 0.7, 0.02, 0.1), 0.0, 0.9)
    m.add(metal_clack(r, 2500.0, 0.5, 0.016, 0.09), 0.09, 0.6)
    m.add(pluck(587.3, 0.2, 0.05), 0.12, 0.5)
    m.add(pluck(880.0, 0.25, 0.07), 0.19, 0.6)
    return m.b


@sound("pickup_health", ("peak", -8.0), family="ui")
def pickup_health(r):
    m = Mix(0.6)
    for i, f in enumerate((523.3, 659.3, 784.0, 1046.5)):                # C E G C, warm
        n = secs(0.3)
        x = additive(f, n, [1.0, 0.25, 0.08]) * env_adsr(n, 0.008, 0.08, 0.3, 0.12)
        m.add(x, 0.075 * i, 0.8 + 0.07 * i)
    return reverb(m.b, 0.4, 0.08, 101, lp_hz=5000.0)


def synth_stab(freqs, dur, cutoff, a=0.005, d=0.15, s=0.4, rel=0.08, detune=0.006):
    """Detuned saw stack through a low-pass: the 'brass' voice of the wanted stingers."""
    n = secs(dur)
    x = np.zeros(n)
    for f in freqs:
        for dt in (-detune, 0.0, detune):
            x += additive(f * (1.0 + dt), n, saw_amps(40))
    x = lp(x, cutoff, 2, pad=512)
    return norm(x) * env_adsr(n, a, d, s, rel)


@sound("wanted_up", STING, family="stinger", release=0.05)
def wanted_up(r):
    m = Mix(1.0)
    m.add(synth_stab([mtof(50), mtof(57), mtof(62)], 0.22, 2200.0), 0.0, 0.8)           # D2 A2 D3... tense
    m.add(synth_stab([mtof(51), mtof(58), mtof(63), mtof(69)], 0.6, 3200.0, d=0.25, s=0.5, rel=0.25), 0.2, 1.0)
    m.add(thump(140.0, 60.0, 0.25, 0.03, 0.05), 0.0, 0.3)
    m.add(thump(150.0, 58.0, 0.3, 0.04, 0.06), 0.2, 0.4)
    m.add(nburst(r, 0.2, 1500.0, 9000.0, 0.001, 0.04), 0.2, 0.3)
    return reverb(m.b, 0.7, 0.12, 111, lp_hz=4500.0)


@sound("wanted_down", STING, family="stinger", release=0.05)
def wanted_down(r):
    m = Mix(0.8)
    m.add(synth_stab([mtof(63), mtof(70)], 0.25, 1800.0, a=0.01), 0.0, 0.8)
    m.add(synth_stab([mtof(58), mtof(65)], 0.5, 1300.0, a=0.01, d=0.2, s=0.3, rel=0.25), 0.2, 0.9)
    return reverb(m.b, 0.6, 0.12, 112, lp_hz=3500.0)


@sound("wanted_clear", STING, family="stinger", release=0.08)
def wanted_clear(r):
    m = Mix(1.4)
    for i, mnote in enumerate((62, 66, 69, 74, 78)):                     # D major arpeggio
        m.add(bell_note(mtof(mnote + 12), 0.9, 0.3, r, 0.8), 0.085 * i, 0.9)
    m.add(synth_stab([mtof(50), mtof(57), mtof(62), mtof(66)], 1.1, 1500.0, a=0.06, d=0.5, s=0.5, rel=0.5), 0.0, 0.5)
    return reverb(m.b, 1.0, 0.16, 113, lp_hz=6000.0)


@sound("arrested", STING, family="stinger", release=0.08)
def arrested(r):
    m = Mix(1.7)
    for i in range(7):                                                   # handcuff ratchet
        m.add(metal_clack(r, 3100.0 + 120.0 * i, 0.6, 0.008, 0.05), 0.035 * i, 0.5)
    m.add(metal_clack(r, 1700.0, 0.8, 0.03, 0.14), 0.3, 0.8)
    for i, mnote in enumerate((57, 53, 50)):                             # A F D falling
        m.add(synth_stab([mtof(mnote), mtof(mnote + 7)], 0.45, 1500.0, a=0.01, d=0.2, s=0.4, rel=0.2), 0.45 + 0.3 * i, 0.9)
    m.add(thump(120.0, 55.0, 0.4, 0.06, 0.09), 1.05, 0.45)
    return reverb(m.b, 0.9, 0.14, 114, lp_hz=3500.0)


@sound("player_down", STING, family="stinger", release=0.15)
def player_down(r):
    dur = 2.2
    n = secs(dur)
    t = tt(n)
    f = glide(110.0, 55.0, n, 0.9)
    drone = additive(f, n, saw_amps(24, 1.2)) + additive(f * 1.498, n, saw_amps(16, 1.3)) * 0.6
    drone = svf(drone, glide(2400.0, 420.0, n, 0.8), 1.2, "lp")
    m = Mix(dur)
    m.add(norm(drone) * env_pts(n, [(0, 0), (0.03, 1), (1.2, 0.7), (dur, 0)]), 0.0, 0.8)
    m.add(synth_stab([mtof(57), mtof(60), mtof(64)], 1.7, 1300.0, a=0.05, d=0.8, s=0.3, rel=0.8), 0.0, 0.4)
    for at in (0.0, 0.28, 1.0, 1.28):                                    # heartbeat slowing
        m.add(thump(100.0, 50.0, 0.25, 0.04, 0.06), at, 0.6 if at < 0.5 else 0.4)
    return reverb(m.b, 1.4, 0.2, 115, lp_hz=2200.0)


@sound("camera_shutter", ("peak", -8.0), family="ui")
def camera_shutter(r):
    m = Mix(0.22)
    m.add(metal_clack(r, 3300.0, 0.9, 0.007, 0.05), 0.0, 1.0)
    n = secs(0.07)
    m.add(norm(band_noise(n, r, 1500.0, 7000.0) * env_pts(n, [(0, 0.6), (0.07, 0.0)])), 0.005, 0.2)
    m.add(metal_clack(r, 2500.0, 0.9, 0.009, 0.06), 0.075, 0.85)
    return m.b


@sound("phone_open", UI, family="ui")
def phone_open(r):
    m = Mix(0.4)
    for i, f in enumerate((880.0, 1318.5, 1760.0)):
        m.add(bell_note(f, 0.25, 0.06, r, 0.5), 0.06 * i, 0.9)
    return m.b


@sound("cash_register", MID, family="ui", release=0.06)
def cash_register(r):
    m = Mix(1.0)
    m.add(metal_clack(r, 1300.0, 0.8, 0.02, 0.1), 0.0, 0.6)             # key / lever
    m.add(bell_note(2093.0, 0.8, 0.28, r, 1.0), 0.07, 1.0)              # ding
    m.add(thump(140.0, 70.0, 0.15, 0.02, 0.035), 0.2, 0.6)              # drawer slides out
    m.add(nburst(r, 0.12, 400.0, 3000.0, 0.02, 0.03), 0.18, 0.3)
    tinkles(m, r, 12, 0.24, 0.55, 3500.0, 9000.0, 0.2, 1.2)             # coins
    return m.b


@sound("spray_paint", ("peak", -9.0), family="ui", attack=0.01, release=0.05)
def spray_paint(r):
    dur = 1.3
    m = Mix(dur)
    for at in (0.0, 0.07, 0.13, 0.2):                                    # rattle ball
        m.add(metal_clack(r, 2900.0, 0.5, 0.008, 0.05), at, 0.35)
    n = secs(1.0)
    hiss = colored(n, r, -1.0, 1800.0, 9500.0) * env_pts(n, [(0, 0), (0.03, 1.0), (0.9, 0.9), (1.0, 0)])
    hiss *= 0.85 + 0.15 * slow_noise(n, r, 9.0)
    m.add(norm(hiss), 0.28, 0.8)
    return m.b


@sound("wrench", MID, family="ui", release=0.03)
def wrench(r):
    m = Mix(0.95)
    at = 0.0
    for i in range(9):                                                   # ratchet strokes
        m.add(metal_clack(r, 2300.0 + 90.0 * (i % 3), 0.8, 0.01, 0.06), at, 0.6 + 0.04 * (i % 3))
        at += 0.045 if i % 3 != 2 else 0.17
    m.add(ping([1250.0, 2080.0, 3320.0, 4700.0], [0.12, 0.09, 0.06, 0.04], [1.0, 0.7, 0.5, 0.3], 0.35, r), 0.6, 0.7)
    return m.b


@sound("target_hit", MID, family="ui", release=0.05)
def target_hit(r):
    m = Mix(0.6)
    m.add(click(r, 0.6, 3000.0, 12000.0), 0.0, 0.8)
    m.add(ping([1420.0, 2260.0, 3610.0, 5170.0, 6900.0], [0.22, 0.16, 0.12, 0.08, 0.05],
               [1.0, 0.8, 0.55, 0.35, 0.2], 0.58, r), 0.0, 1.0)
    return m.b


@sound("activity_start", ("peak", -9.0), family="stinger")
def activity_start(r):
    m = Mix(1.0)
    for at in (0.0, 0.25):
        n = secs(0.11)
        m.add(additive(660.0, n, [1.0, 0.3, 0.12]) * env_adsr(n, 0.004, 0.03, 0.8, 0.03), at, 0.7)
    n = secs(0.42)
    m.add(additive(990.0, n, [1.0, 0.35, 0.15]) * env_adsr(n, 0.004, 0.1, 0.7, 0.15), 0.5, 1.0)
    return reverb(m.b, 0.4, 0.06, 121, lp_hz=5000.0)


@sound("activity_win", STING, family="stinger", release=0.1)
def activity_win(r):
    m = Mix(1.6)
    seq = ((60, 0.0, 0.16), (64, 0.12, 0.16), (67, 0.24, 0.16), (72, 0.36, 0.3), (67, 0.6, 0.12), (72, 0.72, 0.7))
    for (mnote, at, d) in seq:
        m.add(synth_stab([mtof(mnote + 12), mtof(mnote + 24)], d, 4200.0, a=0.004, d=0.1, s=0.6, rel=min(0.1, d * 0.5)), at, 0.9)
        m.add(bell_note(mtof(mnote + 24), d + 0.2, 0.12, r, 0.6), at, 0.3)
    m.add(synth_stab([mtof(48), mtof(55), mtof(64)], 0.75, 1800.0, a=0.02, d=0.3, s=0.6, rel=0.3), 0.72, 0.6)
    return reverb(m.b, 0.9, 0.14, 122, lp_hz=6000.0)


@sound("radio_static", ("peak", -10.0), family="radio", attack=0.004, release=0.03)
def radio_static(r):
    dur = 0.42
    n = secs(dur)
    t = tt(n)
    hiss = colored(n, r, -1.0, 500.0, 7000.0)
    crackle = 0.5 + 0.5 * np.abs(slow_noise(n, r, 40.0))
    whistle = sine(glide(2600.0, 700.0, n, 0.12), n) * env_pts(n, [(0, 0.0), (0.03, 0.5), (0.2, 0.25), (dur, 0.0)])
    x = norm(hiss * crackle) * 0.9 + 0.35 * whistle
    for _ in range(10):
        i = int(r.uniform(0.02, dur - 0.03) * SR)
        x[i:i + 40] += r.choice([-1.0, 1.0]) * r.uniform(0.3, 0.9) * np.exp(-np.arange(40) / 8.0)
    return x * env_pts(n, [(0, 0), (0.01, 1.0), (dur - 0.08, 0.8), (dur, 0.0)])


# --------------------------------------------------------------------------------------------
# thunder (one-shots triggered by the environment system)
# --------------------------------------------------------------------------------------------

def thunder(r, close: bool):
    dur = 5.5 if close else 6.5
    n = secs(dur)
    t = tt(n)
    m = Mix(dur)
    rumble = colored(n, r, -4.0, 35.0, 520.0 if close else 380.0)
    bumps = np.zeros(n)
    k = 9 if close else 12
    for i in range(k):                                                   # overlapping rolls
        c = (0.15 if close else 0.6) + (dur - 1.6) * (i / k) ** 1.2 + r.uniform(-0.12, 0.12)
        w = r.uniform(0.18, 0.5)
        bumps += r.uniform(0.4, 1.0) * np.exp(-0.5 * ((t - c) / w) ** 2) * math.exp(-c / (dur * 0.55))
    env = bumps + 0.25 * env_pts(n, [(0, 0), (0.3, 1.0), (dur, 0.0)])
    m.add(norm(rumble * env), 0.0, 1.0)
    mid = colored(n, r, -3.0, 200.0, 2200.0) * env * (0.5 + 0.5 * np.abs(slow_noise(n, r, 14.0)))
    m.add(norm(mid), 0.0, 0.6 if close else 0.3)
    if close:
        for (at, g) in ((0.0, 1.0), (0.07, 0.6), (0.19, 0.45)):          # ripping crack
            m.add(nburst(r, 0.3, 500.0, 7000.0, 0.0008, 0.05), at, g)
        m.add(thump(110.0, 45.0, 0.6, 0.1, 0.14, 0.004), 0.0, 0.5)
    x = soft_clip(norm(m.b), 1.8 if close else 1.2)
    x = x * env_pts(len(x), [(0, 1.0), (dur - 1.5, 1.0), (dur, 0.0)])
    return reverb(x, 2.4, 0.2, 131 if close else 132, lp_hz=2400.0, hp_hz=50.0, predelay=0.04)


@sound("thunder_1", ("peak", -3.0), family="ambience", release=0.3)
def thunder_1(r):
    return thunder(r, True)


@sound("thunder_2", ("peak", -6.0), family="ambience", attack=0.2, release=0.4)
def thunder_2(r):
    return thunder(r, False)


# --------------------------------------------------------------------------------------------
# animals (pitched pulses + formants, FM chirps)
# --------------------------------------------------------------------------------------------

def bird_chirp(f0, f1, dur, r, curve=0.5, trill=0.0, harm=0.12):
    n = secs(dur)
    t = tt(n)
    u = (t / dur) ** curve
    f = f0 + (f1 - f0) * u
    if trill > 0.0:
        f = f * (1.0 + 0.06 * np.sin(TAU * trill * t))
    return additive(f, n, [1.0, harm, harm * 0.4]) * np.sin(np.pi * np.minimum(t / dur, 1.0)) ** 1.5


@sound("animal_bird", ("peak", -9.0), family="animal")
def animal_bird(r):
    m = Mix(0.9)
    m.add(bird_chirp(3200.0, 4600.0, 0.09, r), 0.0, 0.9)
    m.add(bird_chirp(4500.0, 3300.0, 0.08, r), 0.12, 1.0)
    m.add(bird_chirp(3400.0, 5200.0, 0.07, r), 0.24, 0.9)
    m.add(bird_chirp(4200.0, 4400.0, 0.32, r, 1.0, 28.0), 0.38, 0.8)     # trill
    return reverb(m.b, 0.5, 0.08, 141, lp_hz=8000.0, hp_hz=800.0)


def gull_call(r, dur, f_hi, f_lo):
    n = secs(dur)
    t = tt(n)
    f = f_lo + (f_hi - f_lo) * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.6
    x = additive(f, n, [1.0, 0.8, 0.55, 0.35, 0.2, 0.1])
    x = formant_filter(x, [(1800.0, 500.0, 1.0), (2900.0, 700.0, 0.8), (4200.0, 900.0, 0.35)])
    x *= 0.8 + 0.2 * np.sin(TAU * 45.0 * t)                               # raspy edge
    return norm(x * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.7)


@sound("animal_gull", ("peak", -8.0), family="animal", release=0.05)
def animal_gull(r):
    m = Mix(1.6)
    m.add(gull_call(r, 0.42, 1500.0, 900.0), 0.0, 1.0)
    m.add(gull_call(r, 0.3, 1650.0, 1000.0), 0.5, 0.9)
    m.add(gull_call(r, 0.26, 1700.0, 1050.0), 0.85, 0.8)
    m.add(gull_call(r, 0.24, 1600.0, 1000.0), 1.15, 0.6)
    return reverb(m.b, 0.9, 0.12, 142, lp_hz=6000.0, hp_hz=500.0)


@sound("animal_dog_bark", ("peak", -6.0), family="animal", release=0.04)
def animal_dog_bark(r):
    m = Mix(0.7)
    for (at, g, p) in ((0.0, 1.0, 1.0), (0.26, 0.9, 1.06)):
        b = voice(r, 0.16, [(0, 310 * p), (0.03, 420 * p), (0.16, 230 * p)], "a", "o",
                  [(0, 0), (0.008, 1.0), (0.06, 0.8), (0.16, 0.0)], 1.25, 0.04, 0.3, 0.45, 0.25)
        m.add(norm(b), at, g)
    return reverb(soft_clip(norm(m.b), 1.5), 0.45, 0.1, 143, lp_hz=4500.0)


@sound("animal_deer", ("peak", -8.0), family="animal", release=0.04)
def animal_deer(r):
    x = voice(r, 0.6, [(0, 360), (0.1, 430), (0.4, 400), (0.6, 300)], "e", "ae",
              [(0, 0), (0.04, 1.0), (0.4, 0.8), (0.6, 0.0)], 1.3, 0.03, 0.2, 0.25)
    t = tt(len(x))
    return x * (0.85 + 0.15 * np.sin(TAU * 22.0 * t))                     # bleating tremolo


@sound("animal_growl", ("peak", -7.0), family="animal", attack=0.03, release=0.1)
def animal_growl(r):
    x = voice(r, 1.2, [(0, 82), (0.3, 95), (0.9, 78), (1.2, 66)], "o", "uh",
              [(0, 0), (0.15, 0.8), (0.6, 1.0), (1.2, 0.0)], 0.85, 0.05, 0.25, 0.6, 0.3)
    t = tt(len(x))
    return soft_clip(norm(x * (0.6 + 0.4 * np.sin(TAU * 27.0 * t) ** 2)), 1.6)
