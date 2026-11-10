#!/usr/bin/env python
"""HALCYON BAY - procedural audio synthesizer.

Generates EVERY sound of the game (ids of docs/ARCHITECTURE.md 6.11 plus the radio music loops)
as 16-bit mono WAV files in gta/generated/audio/. Deterministic: fixed seeds derived from the
sound id, so re-running reproduces the same files bit for bit.

    python tools/audio/synth.py                 # everything
    python tools/audio/synth.py --only pistol_shot,rain_loop
    python tools/audio/synth.py --family engine,siren
    python tools/audio/synth.py --list
    python tools/audio/synth.py --no-radio --jobs 4

For every file it prints: duration, sample rate, peak and RMS (dBFS), DC offset, the loop-seam
discontinuity (loops only) and a 5-band energy split, and flags clipping / DC / seam problems.
Measured values are also written to tools/audio/metrics.json and tools/audio/metrics.md.

Dependencies: Python 3 standard library + numpy (already present on this machine; nothing is
installed or downloaded, and no audio material is read from anywhere).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import dsp  # noqa: E402
import sfx  # noqa: E402  (registers one-shots)
import loops  # noqa: E402,F401  (registers loops)
import music  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(ROOT, "gta", "generated", "audio")
METRICS_JSON = os.path.join(HERE, "metrics.json")
METRICS_MD = os.path.join(HERE, "metrics.md")

# Canonical id list - docs/ARCHITECTURE.md section 6.11 (kept in the same order).
CANON = """pistol_shot heavy_pistol_shot smg_shot rifle_shot shotgun_shot sniper_shot
suppressed_shot rocket_launch grenade_launcher_shot dry_fire reload weapon_switch
melee_swing melee_hit punch_hit knife_hit grenade_bounce pin_pull
impact_concrete impact_metal impact_glass impact_flesh impact_wood impact_dirt
impact_water ricochet glass_break explosion_small explosion_large fire_loop
footstep_concrete footstep_grass footstep_sand footstep_metal footstep_wood footstep_water
jump_land body_fall splash_small splash_large swim_stroke underwater_loop breath_gasp
grunt_hit_m grunt_hit_f scream_m scream_f death_m death_f chatter_loop
engine_car_loop engine_sport_loop engine_truck_loop engine_bike_loop engine_boat_loop
heli_rotor_loop plane_prop_loop jet_loop bicycle_loop tire_skid_loop tire_roll_loop
crash_small crash_large metal_scrape_loop horn_car horn_truck horn_bike door_open
door_close engine_start tire_pop siren_police_loop siren_ambulance_loop siren_fire_loop
tram_bell tram_loop parachute_open parachute_loop wind_fall_loop
ui_click ui_hover ui_open ui_close ui_error ui_buy ui_tab pickup_cash pickup_weapon
pickup_health wanted_up wanted_down wanted_clear arrested player_down camera_shutter
phone_open cash_register spray_paint wrench target_hit activity_start activity_win
rain_loop rain_heavy_loop thunder_1 thunder_2 wind_loop ocean_loop city_loop
industrial_loop park_birds_loop night_crickets_loop airport_loop harbor_loop
radio_static animal_deer animal_dog_bark animal_bird animal_gull animal_growl""".split()

RADIO_LEVEL = ("rms", -16.5, -1.5)


def all_ids(include_radio: bool = True):
    ids = list(CANON)
    for extra in sfx.REGISTRY:
        if extra not in ids:
            ids.append(extra)
    if include_radio:
        ids += music.track_ids()
    return ids


def family_of(sound_id: str) -> str:
    if sound_id.startswith("radio_") and sound_id != "radio_static":
        return "music"
    return sfx.REGISTRY.get(sound_id, {}).get("family", "")


def build(sound_id: str, out_dir: str = OUT_DIR) -> dict:
    t0 = time.time()
    if sound_id.startswith("radio_") and sound_id not in sfx.REGISTRY:
        raw = music.render(sound_id)
        sr, loop, level, attack, release = music.MSR, True, RADIO_LEVEL, 0.0, 0.0
    else:
        spec = sfx.REGISTRY[sound_id]
        raw = spec["fn"](dsp.rng(sound_id))
        sr, loop, level = spec["sr"], spec["loop"], spec["level"]
        attack, release = spec["attack"], spec["release"]
    raw = np.asarray(raw, dtype=np.float64)
    if not np.all(np.isfinite(raw)):
        raise ValueError("%s: non-finite samples" % sound_id)
    x = dsp.finalize(raw, level, sr, loop, attack, release)
    pcm = dsp.write_wav(os.path.join(out_dir, sound_id + ".wav"), x, sr, seed=sound_id, loop=loop)
    m = dsp.analyse(pcm, sr, loop)
    d2 = np.diff(pcm, 2)
    typ2 = float(np.sqrt(np.mean(d2 * d2))) + 1e-12
    m["seam_d2_ratio"] = abs(float(pcm[0] - 2.0 * pcm[-1] + pcm[-2])) / typ2
    m["id"] = sound_id
    m["family"] = family_of(sound_id)
    m["secs"] = time.time() - t0
    flags = []
    if m["peak_db"] > -0.2:
        flags.append("CLIP")
    if abs(m["dc"]) > 0.003:
        flags.append("DC")
    if loop and (m["seam_ratio"] > 5.0 and m["seam_jump"] > 0.004):
        flags.append("SEAM")
    if loop and m["seam_d2_ratio"] > 6.0 and m["seam_jump"] > 0.004:
        flags.append("SEAM2")
    if loop and m["seam_hf_vs_p95_db"] > 6.0:
        flags.append("SEAMHF")
    if not loop and m["edge"] > 0.004:
        flags.append("EDGE")
    if m["rms_db"] < -60.0:
        flags.append("SILENT")
    m["flags"] = flags
    return m


IMPORT_TEMPLATE = """[remap]

importer="wav"
type="AudioStreamWAV"

[deps]

source_file="res://gta/generated/audio/%s.wav"

[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode=0
edit/loop_begin=0
edit/loop_end=-1
compress/mode=%d
"""


def fix_import(sound_id: str, out_dir: str = OUT_DIR) -> str:
    """Godot import settings for our files: effects, loops and ambience stay uncompressed PCM
    (pure tones and loop seams survive untouched), the long radio music loops use Godot's
    built-in QOA compression (mode 2) to save memory. Never trims or normalises.
    Returns what happened: "ok", "changed" or "created"."""
    mode = 2 if family_of(sound_id) == "music" else 0
    path = os.path.join(out_dir, sound_id + ".wav.import")
    if not os.path.exists(path):
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(IMPORT_TEMPLATE % (sound_id, mode))
        return "created"
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    lines = text.split("\n")
    changed = False
    for i, line in enumerate(lines):
        want = None
        if line.startswith("compress/mode="):
            want = "compress/mode=%d" % mode
        elif line.startswith("edit/trim="):
            want = "edit/trim=false"
        elif line.startswith("edit/normalize="):
            want = "edit/normalize=false"
        if want is not None and line.strip() != want:
            lines[i] = want
            changed = True
    if changed:
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines))
        return "changed"
    return "ok"


def row(m: dict) -> str:
    bands = " ".join("%3d" % round(b * 100.0) for b in m["bands"])
    seam = ("%4.1f/%4.1f/%+5.1f" % (m["seam_ratio"], m["seam_d2_ratio"], m["seam_hf_db"])) if m["loop"] else "       -       "
    return "%-24s %6.2fs %5d %6.1f %6.1f %+8.5f %s %6.0f  %s  %s" % (
        m["id"], m["dur"], m["sr"], m["peak_db"], m["rms_db"], m["dc"], seam, m["centroid"], bands,
        " ".join(m["flags"]))


HEADER = "%-24s %7s %5s %6s %6s %8s %15s %6s  %s" % (
    "id", "dur", "sr", "peak", "rms", "dc", "seam d1/d2/hfdB", "centr", "sub low mid  hi air (%)")


def write_reports(metrics: dict) -> None:
    with open(METRICS_JSON, "w", encoding="utf-8") as fh:
        json.dump(metrics, fh, indent=1, sort_keys=True)
    order = [i for i in all_ids(True) if i in metrics]
    lines = ["| id | family | dur s | sr | peak dBFS | RMS dBFS | DC | loop seam (d1 / d2 / HF excess) | centroid Hz | sub / low / mid / hi / air % | flags |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    for i in order:
        m = metrics[i]
        seam = "%.2f / %.2f / %+.1f dB" % (m["seam_ratio"], m["seam_d2_ratio"], m["seam_hf_db"]) if m["loop"] else "-"
        lines.append("| %s | %s | %.2f | %d | %.1f | %.1f | %+.5f | %s | %.0f | %s | %s |" % (
            i, m["family"], m["dur"], m["sr"], m["peak_db"], m["rms_db"], m["dc"], seam, m["centroid"],
            " / ".join("%d" % round(b * 100.0) for b in m["bands"]), " ".join(m["flags"]) or "ok"))
    with open(METRICS_MD, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description="Halcyon Bay procedural audio synthesizer")
    ap.add_argument("--only", default="", help="comma separated sound ids")
    ap.add_argument("--family", default="", help="comma separated families (weapon, impact, engine, siren, ambience, music, ...)")
    ap.add_argument("--no-radio", action="store_true", help="skip the radio music loops")
    ap.add_argument("--list", action="store_true", help="list ids and exit")
    ap.add_argument("--jobs", type=int, default=1, help="worker processes")
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--no-report", action="store_true", help="do not touch metrics.json / metrics.md")
    ap.add_argument("--fix-imports", action="store_true",
                    help="only (re)write the Godot .import settings of the existing files and exit")
    args = ap.parse_args()

    ids = all_ids(not args.no_radio)
    missing = [i for i in CANON if i not in sfx.REGISTRY]
    if missing:
        print("ERROR: no recipe for canonical ids: " + ", ".join(missing))
        return 2
    if args.only:
        want = [s.strip() for s in args.only.split(",") if s.strip()]
        unknown = [w for w in want if w not in all_ids(True)]
        if unknown:
            print("ERROR: unknown ids: " + ", ".join(unknown))
            return 2
        ids = want
    if args.family:
        fams = set(s.strip() for s in args.family.split(","))
        ids = [i for i in ids if family_of(i) in fams]
    if args.list:
        for i in ids:
            print("%-26s %s" % (i, family_of(i)))
        print("%d ids" % len(ids))
        return 0

    os.makedirs(args.out, exist_ok=True)
    is_project_dir = os.path.abspath(args.out) == os.path.abspath(OUT_DIR)
    if args.fix_imports:
        res = [fix_import(i, args.out) for i in ids if os.path.exists(os.path.join(args.out, i + ".wav"))]
        print("import settings: %d ok, %d changed, %d created" % (res.count("ok"), res.count("changed"), res.count("created")))
        return 0
    metrics = {}
    if os.path.exists(METRICS_JSON):
        try:
            with open(METRICS_JSON, "r", encoding="utf-8") as fh:
                metrics = json.load(fh)
        except Exception:
            metrics = {}
    print("output: %s   (%d sounds, numpy %s)" % (args.out, len(ids), np.__version__))
    print(HEADER)
    t0 = time.time()
    results = []
    if args.jobs > 1:
        import functools
        import multiprocessing as mp
        with mp.Pool(args.jobs) as pool:
            for m in pool.imap(functools.partial(build, out_dir=args.out), ids):
                print(row(m), flush=True)
                results.append(m)
    else:
        for i in ids:
            m = build(i, args.out)
            print(row(m), flush=True)
            results.append(m)
    if not args.no_report:
        for m in results:
            metrics[m["id"]] = m
        write_reports(metrics)
    if is_project_dir:
        res = [fix_import(m["id"], args.out) for m in results]
        print("import settings: %d ok, %d changed, %d created (PCM for effects/loops, QOA for radio music)" % (
            res.count("ok"), res.count("changed"), res.count("created")))
    flagged = [m["id"] + ":" + "+".join(m["flags"]) for m in results if m["flags"]]
    total = sum(m["dur"] for m in results)
    print("done: %d files, %.1f s of audio, %.1f s wall. flagged: %s" % (
        len(results), total, time.time() - t0, ", ".join(flagged) if flagged else "none"))
    return 1 if flagged else 0


if __name__ == "__main__":
    sys.exit(main())
