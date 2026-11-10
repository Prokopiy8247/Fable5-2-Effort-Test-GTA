# SPEC — Procedural audio library (original, synthesised; no samples, no downloads)

You are the sound designer for **NEON TIDE: Vesper Bay**, an original GTA-style sandbox built in Godot 4.7
(project root `G:\YouTube\Fable 5.2 Effort Test GTA\Max`). Every sound must be **synthesised from scratch in code**
(Python 3.12 + numpy 2.x are installed; `python` is on PATH; standard library `wave` for output). No external audio
files, no copyrighted material, no speech.

## Deliverables

1. `tools/audio/gen_audio.py` — deterministic (fixed RNG seeds) generator. `python tools/audio/gen_audio.py` writes
   every file below into `gta/generated/audio/<name>.wav`; `python tools/audio/gen_audio.py name1 name2` regenerates
   only those. Keep it organised: shared DSP helpers (oscillators, noise colours, ADSR/exp envelopes, one-pole and
   biquad filters, resonant band-pass, soft clip/saturation, simple feedback-delay/comb reverb, pitch sweeps, FM,
   Karplus-Strong pluck, seamless-loop crossfade, normalise) + one small function per sound.
2. The WAV files (16-bit PCM). Mono 44.1 kHz for one-shots; loops mono 32 kHz unless stated; radio music stereo 32 kHz.
3. `gta/resources/data/manifests/audio.json`: `{"sounds": [{"name", "seconds", "loop": bool, "channels", "rate",
   "peak_db", "rms_db"}]}` for every file.
4. A verification pass in the script (`--verify`): no NaN/Inf, no clipping (peak ≤ −1 dBFS), one-shots end in
   silence (last 5 ms < −50 dB), **loops are seamless** (no click at the wrap: crossfade the tail into the head and
   check the sample discontinuity at the loop point is below the average inter-sample step), sensible loudness
   (one-shots peak −3…−1 dBFS; loops RMS about −20…−14 dBFS). Print a table and fix anything that fails.

Do not launch Godot, do not edit anything outside `tools/audio/`, `gta/generated/audio/` and your manifest, do not
run git. Do not stop until all sounds exist and verify. Finish with a short report (what each family sounds like,
anything you are not happy with).

## Quality bar

These are heard constantly on a YouTube recording, so make them pleasant and believable rather than raw:
layer components (e.g. gunshot = sharp transient click + noise burst with fast decay + low thump + short tail
reverb), shape spectra with filters, use short reverbs/tails for space, vary pitch/timbre between numbered variants.
Engines must loop seamlessly and still sound right when Godot pitch-shifts them between ×0.5 and ×2.2 (build them at
idle-ish RPM from a pulse train / harmonic stack with firing-order unevenness + filtered noise + slight wobble; no
audible loop period shorter than ~2 s). Avoid harsh aliasing: band-limit bright oscillators.

## Sound list (file name = `<name>.wav`; L = seamless loop; seconds are guides)

### Weapons
`shot_pistol` (0.5), `shot_revolver` (0.7, heavier), `shot_smg` (0.35, snappy), `shot_shotgun` (0.9, boomy),
`shot_rifle` (0.6, cracky), `shot_sniper` (1.4, big crack + long tail), `shot_suppressed` (0.3, pfft + mechanical),
`shot_rocket` (1.2, whoosh launch), `shot_launcher` (0.5, hollow thump), `dry_fire` (0.12), `reload_pistol` (0.7,
mag out/in + slide), `reload_rifle` (1.1), `reload_shotgun` (0.4, single shell insert), `pump_shotgun` (0.45),
`weapon_switch` (0.25), `melee_swing` (0.3 whoosh), `melee_hit` (0.25 thud), `melee_hit_metal` (0.35 clank),
`knife_stab` (0.25), `grenade_pin` (0.25), `grenade_bounce` (0.2), `explosion_big` (2.8, deep, debris tail),
`explosion_small` (1.6), `explosion_distant` (2.5, muffled rumble), `rocket_fly` (L 2.0, hissing roar),
`bullet_impact_concrete` (0.25), `bullet_impact_metal` (0.3, ping/ricochet), `bullet_impact_flesh` (0.2),
`bullet_impact_glass` (0.3), `bullet_impact_dirt` (0.25), `bullet_impact_water` (0.35), `bullet_whiz` (0.3),
`glass_break` (0.9), `shell_drop` (0.3, tiny brass tinkle).

### Player / characters (non-verbal)
`footstep_concrete_1..4` (0.18 each), `footstep_grass_1..3`, `footstep_sand_1..2`, `footstep_metal_1..2`,
`footstep_wood_1..2`, `jump` (0.2 cloth/effort), `land` (0.25), `land_hard` (0.4), `body_fall` (0.6),
`hurt_1..3` (0.3 short grunts made from formant-filtered pulse/noise, clearly non-verbal), `death` (0.9),
`scream_1..3` (0.8–1.2 panic yelps, formant synthesis, 1–2 higher pitched), `swim_stroke` (0.5),
`splash_big` (1.2), `splash_small` (0.5), `underwater_loop` (L 6), `breath_gasp` (0.8), `heartbeat` (L 1.6, two
beats), `roll` (0.5 cloth scuffle), `climb` (0.3), `parachute_open` (1.0 fabric whump), `parachute_loop` (L 4,
flutter + wind), `wind_fall_loop` (L 4, rushing air), `punch_whoosh` (0.2).

### Vehicles
`engine_small_loop` (L 2.5, 3–4 cyl buzz), `engine_sedan_loop` (L 2.5), `engine_sport_loop` (L 2.5, raspy higher),
`engine_muscle_loop` (L 3, lumpy V8 burble), `engine_truck_loop` (L 3, diesel clatter), `engine_bike_loop` (L 2.5),
`engine_boat_loop` (L 3, outboard + water), `heli_rotor_loop` (L 3, blade chop + turbine whine),
`plane_prop_loop` (L 3), `jet_loop` (L 4, turbine whine + roar), `train_loop` (L 4, electric hum + rumble),
`engine_start` (1.0), `engine_off` (0.6), `skid_loop` (L 2, tyre squeal), `tire_roll_loop` (L 3, road hiss),
`horn_car` (0.6), `horn_truck` (0.9, low two-tone), `horn_bike` (0.4, thin), `train_horn` (1.5),
`bicycle_bell` (0.6), `siren_police_loop` (L 4, wail sweep), `siren_police_yelp_loop` (L 1.2),
`siren_ambulance_loop` (L 2.4, hi-lo), `siren_fire_loop` (L 4.8, slow wail + air-horn character),
`car_alarm_loop` (L 2), `crash_small` (0.5), `crash_medium` (0.8), `crash_big` (1.4, metal + glass),
`metal_scrape_loop` (L 2), `door_open` (0.3), `door_close` (0.35), `tire_pop` (0.5), `handbrake` (0.3),
`fire_loop` (L 4, crackle + roar), `boat_wake_loop` (L 4), `spray_paint` (1.2), `wrench_ratchet` (0.9),
`garage_door` (2.0 motor + rattle).

### World / ambience
`amb_city_day_loop` (L 16, distant traffic wash, faint horns, hum), `amb_city_night_loop` (L 16, quieter, hum,
distant siren hint, crickets layer), `amb_park_loop` (L 16, birdsong made from chirp synthesis + leaves),
`amb_ocean_loop` (L 16, slow surf swells), `amb_industrial_loop` (L 12, machinery drone, clanks), `amb_wind_loop`
(L 12), `amb_interior_loop` (L 8, room tone + faint fridge hum), `rain_loop` (L 8), `rain_heavy_loop` (L 8),
`thunder_1`, `thunder_2` (3.5–5), `crowd_murmur_loop` (L 10, wordless babble from filtered noise bursts),
`police_radio_1`, `police_radio_2` (1.2, squelch + garbled band-limited blips, no words), `seagull_1`, `seagull_2`
(0.9), `dog_bark_1`, `dog_bark_2` (0.4), `cat_meow` (0.6), `deer_snort` (0.4), `bird_flap` (0.5),
`hydrant_spray_loop` (L 3), `auto_door` (0.8 pneumatic slide), `shop_bell` (0.8), `elevator_ding` (0.9),
`cash_register` (0.7), `phone_ring` (L 2), `phone_beep` (0.15), `camera_shutter` (0.3), `pickup_item` (0.4),
`pickup_health` (0.5), `pickup_weapon` (0.4), `neon_buzz_loop` (L 3), `shark_bite` (0.5), `sizzle` (0.6).

### UI
`ui_click` (0.06), `ui_hover` (0.04), `ui_open` (0.25), `ui_close` (0.2), `ui_deny` (0.25), `ui_buy` (0.4),
`ui_cash` (0.35 coin/ka-ching), `ui_notify` (0.3), `ui_wheel_tick` (0.04), `ui_map_ping` (0.3),
`ui_wanted_up` (0.7 tense sting), `ui_wanted_clear` (0.9 relief), `ui_busted` (2.0), `ui_wasted` (2.5 dark sting),
`ui_skill_up` (0.8), `ui_checkpoint` (0.4), `ui_success` (1.2 fanfare), `ui_fail` (1.0), `ui_countdown` (0.2 beep),
`ui_go` (0.5).

### Radio (original generative music; stereo 32 kHz; each a seamless loop of 32–48 s built with a small step
sequencer: drums from synthesis, bass, chords/pads, lead/arp; sidechain-style ducking and gentle master saturation)
`radio_neon` (synthwave ≈ 100 BPM, arps + gated snare), `radio_lowtide` (lo-fi hip-hop ≈ 78 BPM, mellow keys, vinyl
crackle), `radio_pulse` (house/techno ≈ 124 BPM), `radio_dusty` (laid-back surf/blues-rock feel with Karplus-Strong
guitar ≈ 92 BPM), `radio_ambient` (beatless pads + bells), plus `radio_static` (L 2, tuning noise) and
`radio_jingle_1..5` (1.5–2.5 s station idents, melodic stingers, no voice).
