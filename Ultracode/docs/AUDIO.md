# HALCYON BAY — Audio

Everything you hear in the game is synthesised by project code. There are no recordings, no
sample packs, no downloaded files and no quoted melodies: the only inputs of the pipeline are
numbers and seeds.

| Part | Where |
|---|---|
| Synthesis tool | `tools/audio/synth.py` (+ `dsp.py`, `sfx.py`, `loops.py`, `music.py`) |
| Independent verification | `tools/audio/verify.py` |
| Generated files | `gta/generated/audio/*.wav` (130 files: 120 canonical ids + 10 radio loops) |
| Measurements | `tools/audio/metrics.json`, `tools/audio/metrics.md` (written by every run) |
| Playback service | `gta/code/audio/audio_manager.gd` (autoload `Audio`) |
| Radio | `gta/code/audio/radio_system.gd` (system `radio`), `gta/resources/registries/radio_registry.gd` |
| Ambience | `gta/code/audio/ambience_system.gd` (system `ambience`) |
| Tests | `gta/tests/aud_api.gd`, `gta/tests/aud_ingame.gd` |

## 1. Pipeline

```
python tools/audio/synth.py                    # all 130 files, ~1 minute with --jobs 6
python tools/audio/synth.py --only pistol_shot,rain_loop
python tools/audio/synth.py --family engine,siren     # weapon impact explosion footstep water voice
                                                      # vehicle engine siren ui stinger ambience animal radio music
python tools/audio/synth.py --list
python tools/audio/synth.py --fix-imports      # only rewrite the Godot import settings
python tools/audio/verify.py                   # re-reads the files and re-checks them (exit 0 = ok)
```

- Python 3.12 standard library + numpy (numpy was already installed on the build machine;
  nothing was installed or downloaded for this).
- Output: 16-bit mono PCM WAV. Effects and beds 44.1 kHz, radio music 32 kHz.
- **Deterministic**: every recipe gets a `RandomState` seeded from the crc32 of its sound id.
  Re-running reproduces the files byte for byte (checked with md5 on 7 files, including two
  music loops).
- Every file is finished the same way: 18 Hz high-pass (DC removal), edge fades for one-shots,
  level normalisation (peak target for one-shots, RMS target with a soft peak ceiling for loops),
  TPDF dither, then it is measured from the quantised samples and the row is printed.
- Godot import settings are written by the tool into the `.wav.import` files: uncompressed PCM
  for effects / loops / beds (pure tones and loop seams stay untouched), Godot's built-in QOA
  compression for the long radio loops (saves about 20 MB of memory), never trim, never
  normalise.

### Why the loops are seamless

Loops are seamless by construction, not by patching the seam afterwards:

1. every tone completes a whole number of cycles in the loop (swept tones such as sirens are
   rescaled so the integral of their frequency curve is an integer);
2. noise is shaped with circular FFT filters, so it is periodic over exactly the loop length;
3. events (engine firings, bird calls, clanks, drum hits, notes) are mixed with wrap-around;
4. envelopes are folded around the loop and reverb / echo are circular convolutions / rolls.

The tool still measures every seam three ways (columns `d1 / d2 / HF excess` below): the jump
between the last and the first sample relative to the RMS sample-to-sample step, the same for
the second difference, and the high-frequency energy of a window that straddles the wrap point
relative to the median window of the file (a click shows up as tens of dB there; the music
loops read +6…+35 dB only because bar 1 beat 1 carries a kick / crash transient, and are below
the 95th percentile + 6 dB limit that flags a real click). `aud_api.gd` repeats the first
measurement inside Godot on the imported data (worst loop: 3.7 × the typical step, i.e. no
discontinuity).

## 2. Synthesis design per family

Building blocks (`dsp.py`): phase-accumulating sine / band-limited additive oscillators, modal
(struck) partial banks, white / tilted / band noise, attack-decay and breakpoint envelopes,
zero-phase FFT filters (low / high / band-pass, resonant bells, formant banks), a time-varying
state-variable filter for sweeps, tanh waveshaping, convolution reverb with a synthetic impulse
response (decaying noise whose highs die faster, plus sparse early reflections), feedback echo.

| Family | Recipe |
|---|---|
| **Gunshots** (`*_shot`) | Five layers: a 2–6 ms broadband *crack*, a pink-noise *body*, a low-mid *boom*, a short sine *thump* that falls in pitch, and a metallic *action clatter* a few ms later → tanh saturation → outdoor reverb tail; long guns add two slap-back echoes. Each weapon class has its own band limits, decay times and tail: SMG short and bright, pistol tight, heavy pistol and shotgun low and long, rifle hard mid-range, sniper a huge 1.7 s tail. `suppressed_shot` has no crack and no tail: a muffled gas burst plus the action click. |
| `rocket_launch`, `grenade_launcher_shot` | Ignition pop + noise through a swept band-pass (whoosh) + low roar; hollow tube "thoomp" from a falling sine and tube resonances. |
| **Weapon handling** | `reload`: magazine release, slide-out scrape, seat, rack and release built from modal metal clacks at different tunings; `dry_fire`, `weapon_switch`, `pin_pull`, `melee_swing` (noise through a bell-shaped band sweep). |
| **Impacts** | Per surface: concrete (crack + dust + grit ticks), metal (inharmonic ringing partials), glass (high pings), flesh (low thud + squelch), wood (hollow knock), dirt (soft puff), water (rising "plip" + splash); `ricochet` is a falling whine with vibrato; `glass_break` a crash plus ~70 scattered tinkles whose density decays. |
| **Explosions** | Pressure crack, short sub thump, noise through a low-pass that closes as the fireball cools, mid-range roar, rolling rumble, random debris crackles → saturation → long reverb. Small 3.2 s, large 5.5 s. |
| **Footsteps / body** | Per surface (concrete, grass, sand, metal, wood, water) from a heel tick, a sole body and a later scuff with surface-specific spectra; `jump_land` (two feet), `body_fall`, `splash_small/large` (swept noise + bubbles), `swim_stroke`. |
| **Voices** | Strictly non-verbal. A Rosenberg-style glottal pulse train (with jitter and aspiration noise) through parallel vowel formants, crossfading between two vowels; pitch and loudness contours make grunts, screams, death groans, a gasp. Female voices use a higher pitch and formants scaled by ~1.17. `chatter_loop` is nine such voices babbling random vowel syllables under a room reverb. |
| **Engines** (`engine_*_loop`) | Granular firing-pulse model: every cylinder firing excites three damped exhaust / block resonances plus a short broadband combustion snap; cylinders differ slightly in level, tuning and timing (the half-order burble) and every firing varies a little; firing-synchronous noise adds intake / valve-train texture; then a body EQ and saturation. A whole number of engine cycles per 2 s loop, so they loop seamlessly and pitch-shift cleanly (0.5×–2.1×). Car: inline four at 78 Hz firing; sport: six at 108 Hz, brighter and raspier; truck: diesel six at 51 Hz with clatter and rumble; bike: uneven twin at 88 Hz; boat: three-cylinder outboard with water gurgle. |
| **Aircraft** | `heli_rotor_loop`: 13 Hz blade-pass "whop" (low thump + noise slap, alternate blades differ) + turbine whine + tail-rotor buzz; `plane_prop_loop`: 80 Hz blade-pass harmonic stack beating against a 80.5 Hz copy + flat-six engine + air; `jet_loop`: broadband roar + compressor whine partials + fan buzz. |
| **Tyres / metal** | `tire_skid_loop` (narrow noise resonances + a wandering howl), `tire_roll_loop`, `metal_scrape_loop`, `crash_small/large` (crunch, sheet-metal partials, secondary hits, glass tinkles), `door_open/close`, `engine_start` (starter whirr with cranking pulse, then firing pulses that speed up), `tire_pop`. |
| **Horns** | Two- and three-tone chords of rich harmonic stacks through a diaphragm formant and saturation: car 420 + 500 Hz, truck 156 + 196 + 234 Hz, bike 620 + 780 Hz. All partials are integer Hz, so the middle of each file is exactly periodic and can be held as a loop (see `SUSTAIN_SECTIONS`). |
| **Sirens** | A horn-loaded electronic siren voice (harmonic stack → speaker formant → overdrive → short street echo) driven by three different pitch programs: **wail** `siren_police_loop` (610–1480 Hz, 3.2 s cycle), **yelp** `siren_ambulance_loop` (680–1620 Hz, 0.34 s cycle), **hi-lo** `siren_fire_loop` (455 / 606 Hz alternating, with a mechanical sub-octave growl). |
| **Tram / parachute** | `tram_bell` (two strikes of an inharmonic bell), `tram_loop` (motor whine, hum, rail rumble, rail-joint "da-dum"), `parachute_open` (fabric whump), `parachute_loop`, `wind_fall_loop`. |
| **UI / pickups** | Short, soft plucks and small bells on consonant intervals (fifths, octaves), −10 dBFS peak: `ui_click`, `ui_hover`, `ui_open` (rising), `ui_close` (falling), `ui_error` (low double buzz), `ui_buy`, `ui_tab`, `pickup_*`, `phone_open`, `camera_shutter`, `cash_register`, `spray_paint`, `wrench`, `target_hit`. |
| **Stingers** | Detuned saw "brass" stabs and bells: `wanted_up` (tense rising semitone), `wanted_down`, `wanted_clear` (major arpeggio), `arrested` (cuff ratchet + falling line), `player_down` (falling drone + slowing heartbeat), `activity_start`, `activity_win`. |
| **Weather / world beds** | 6–12 s loops. `rain_loop` / `rain_heavy_loop`: tilted hiss + patter + thousands of band-passed impulse "drops"; `wind_loop`: three noise bands crossfaded by slow gust controls; `ocean_loop`: two waves per loop, each a swell, a break and a receding fizz; `city_loop`: traffic hum, passing-car swells, mains hum, far horns in a long reverb; `industrial_loop`: 50/100 Hz drone, pneumatic press cycle, clanks, steam; `park_birds_loop`: four synthetic bird species (chips, rising sweeps, two-note calls, trills) at random distances; `night_crickets_loop`: six crickets with their own pitch and chirp rate + a tree-cricket trill; `airport_loop`: distant jet swell, apron hum, terminal chime; `harbor_loop`: water slapping hulls, rigging pings, buoy bell, far gulls, a distant diesel; `fire_loop`, `underwater_loop`. |
| **Thunder** | `thunder_1` (close: ripping crack + rolling rumble), `thunder_2` (distant roll). Triggered by the environment system. |
| **Animals** | `animal_bird` (FM chirps + trill), `animal_gull` (formant-filtered harmonic cry), `animal_dog_bark`, `animal_deer`, `animal_growl` (pulse voice with sub-harmonic roughness). |
| `radio_static` | Band noise with crackle modulation, a falling tuning whistle and pops. |

A numeric balance pass was done on every family with the 5-band energy split printed by the
tool (sub < 120 Hz, low < 500 Hz, mid < 2 kHz, hi < 6 kHz, air): the first versions of the
gunshots, explosions, body sounds, engines and several beds carried 70–90 % of their energy
below 120 Hz or 500 Hz and were rebuilt until they carry real mid-range (see the table).

## 3. Radio music

Five original stations, two seamless loops each (`radio_<station_id>_<n>.wav`). The music is
composed by a small step sequencer (`music.py`): drums from sine sweeps and filtered noise,
synth voices by additive emulation of a subtractive synth (each harmonic is weighted by a
low-pass whose cutoff follows an envelope — alias-free), FM electric piano and bells, circular
echo / reverb, kick side-chain, tanh bus saturation. Chord progressions are generic diatonic
cycles; melodies come from a seeded motif-and-variation generator (a two-bar cell of scale-degree
offsets is stated, answered, varied and resolved; strong beats snap to chord tones) — no
existing tune is quoted.

| id | Station | Genre | Loop 1 | Loop 2 | Character |
|---|---|---|---|---|---|
| `neon_tide` | Neon Tide FM 101.5 | Synthwave | 100 BPM, A minor, 16 bars, 38.4 s | 104 BPM, E minor, 16 bars, 36.9 s | four-on-the-floor, gated snare, pulsing octave bass, detuned pads, 16th arps with dotted echo, square lead |
| `low_tide` | Low Tide Lounge 88.3 | Lo-fi hip-hop | 78 BPM, F major, 12 bars, 36.9 s | 72 BPM, D dorian, 12 bars, 40.0 s | swung drums, rolled 9th chords on electric piano, soft bass with approach tones, vinyl crackle, tape wow, rolled-off top |
| `boogie_bay` | Boogie Bay 98.7 | Funk / disco | 116 BPM, E dorian, 16 bars, 33.1 s | 120 BPM, A minor, 16 bars, 32.0 s | disco hats, claps, octave-jumping bass, muted guitar "chicks", strings, brass punctuation |
| `breakwater` | Breakwater 107.9 | Drum & bass | 172 BPM, F minor, 24 bars, 33.5 s | 174 BPM, D minor, 24 bars, 33.1 s | two-step break with ghost notes, reese bass, airy pads, plucks, a breakdown and snare-roll build |
| `drift` | Halcyon Drift 93.1 | Ambient / chill | 70 BPM, C lydian, 12 bars, 41.1 s | 66 BPM, F major, 12 bars, 43.6 s | slow pad chords, sub drone, FM bell constellations with long echoes, sparse piano motif |

`tools/audio/verify.py` reads the finished files back and estimates tempo (autocorrelation of
the spectral-flux onset envelope) and key fit (share of the tonal energy between 60 Hz and
2 kHz that lies within ±30 cents of a note of the configured scale; unpitched noise alone would
give 58 %):

```
radio loop              dur s    bars    bpm detected  acf beat   acf bar  in-scale    tonal  top pitch classes (0 = root)
radio_neon_tide_1       38.40  16.000  100.0    100.0      0.72      0.90       85%      79%  [3, 10, 0, 8]
radio_neon_tide_2       36.92  16.000  104.0    104.2      0.71      0.78       86%      78%  [7, 3, 8, 0]
radio_low_tide_1        36.92  12.000   78.0     78.1      0.85      0.80       93%      88%  [7, 9, 0, 4]
radio_low_tide_2        40.00  12.000   72.0     72.1      0.85      0.81       92%      88%  [7, 9, 2, 5]
radio_boogie_bay_1      33.10  16.000  116.0     58.1      0.73      0.82       83%      74%  [7, 3, 0, 5]
radio_boogie_bay_2      32.00  16.000  120.0     60.0      0.70      0.92       85%      68%  [2, 7, 10, 3]
radio_breakwater_1      33.49  24.000  172.0     86.2      0.64      0.74       79%      76%  [3, 10, 8, 7]
radio_breakwater_2      33.10  24.000  174.0     87.2      0.72      0.75       79%      73%  [7, 0, 3, 5]
radio_drift_1           41.14  12.000   70.0    138.9      0.24      0.50       98%      99%  [7, 11, 4, 2]
radio_drift_2           43.64  12.000   66.0    131.6      0.56      0.17       99%     100%  [7, 4, 9, 0]
```

Detected tempi equal the sequencer tempo or exactly half / double of it, every loop is a whole
number of bars, and the four strongest pitch classes of every loop belong to its scale.

## 4. Measured table

Snapshot of `tools/audio/metrics.md` (regenerated by every run of `synth.py`). `seam`: first
difference / second difference across the loop point relative to their RMS inside the file, and
the high-frequency excess of the wrap window in dB (loops only). Band split in % of energy:
sub < 120 Hz / low < 500 Hz / mid < 2 kHz / hi < 6 kHz / air. No file is flagged (flags:
CLIP, DC, SEAM, SEAM2, SEAMHF, EDGE, SILENT).

Level targets: loud one-shots (gunshots, explosions, big crashes) peak −3 dBFS; ordinary
one-shots −6; footsteps and small foley −9; UI −10 and lower; engines / sirens / horns
RMS −14…−17 dBFS; ambience beds RMS −21…−28 dBFS; radio RMS −16.5 dBFS with a −1.5 dBFS ceiling.

| id | family | dur s | sr | peak dBFS | RMS dBFS | DC | loop seam (d1 / d2 / HF excess) | centroid Hz | sub / low / mid / hi / air % | flags |
|---|---|---|---|---|---|---|---|---|---|---|
| pistol_shot | weapon | 0.86 | 44100 | -3.0 | -23.2 | +0.00009 | - | 1432 | 7 / 46 / 28 / 13 / 6 | ok |
| heavy_pistol_shot | weapon | 1.35 | 44100 | -3.0 | -24.2 | +0.00020 | - | 893 | 17 / 45 / 28 / 8 / 2 | ok |
| smg_shot | weapon | 0.59 | 44100 | -3.0 | -25.0 | +0.00027 | - | 2265 | 4 / 27 / 32 / 28 / 9 | ok |
| rifle_shot | weapon | 1.33 | 44100 | -3.0 | -23.7 | +0.00015 | - | 1533 | 9 / 31 / 36 / 21 / 4 | ok |
| shotgun_shot | weapon | 2.01 | 44100 | -3.0 | -21.5 | +0.00002 | - | 743 | 23 / 47 / 20 / 9 / 1 | ok |
| sniper_shot | weapon | 2.78 | 44100 | -3.0 | -23.5 | +0.00005 | - | 1024 | 22 / 35 / 29 / 12 / 2 | ok |
| suppressed_shot | weapon | 0.30 | 44100 | -8.0 | -28.4 | +0.00026 | - | 1445 | 24 / 17 / 27 / 31 / 1 | ok |
| rocket_launch | weapon | 2.55 | 44100 | -3.0 | -18.0 | +0.00009 | - | 2607 | 25 / 17 / 8 / 39 / 11 | ok |
| grenade_launcher_shot | weapon | 0.93 | 44100 | -3.0 | -22.6 | +0.00006 | - | 955 | 6 / 72 / 6 / 12 / 4 | ok |
| dry_fire | weapon | 0.12 | 44100 | -9.0 | -27.1 | -0.00002 | - | 3228 | 0 / 0 / 13 / 81 / 6 | ok |
| reload | weapon | 1.37 | 44100 | -6.0 | -28.3 | +0.00000 | - | 2408 | 2 / 24 / 27 / 39 / 8 | ok |
| weapon_switch | weapon | 0.28 | 44100 | -9.0 | -28.3 | -0.00000 | - | 3139 | 0 / 14 / 20 / 55 / 11 | ok |
| melee_swing | weapon | 0.30 | 44100 | -9.0 | -26.1 | +0.00000 | - | 2622 | 0 / 0 / 41 / 54 / 5 | ok |
| melee_hit | impact | 0.25 | 44100 | -6.0 | -22.0 | +0.00038 | - | 913 | 10 / 61 / 13 / 14 / 2 | ok |
| punch_hit | impact | 0.20 | 44100 | -6.0 | -22.6 | +0.00046 | - | 807 | 7 / 59 / 22 / 11 / 1 | ok |
| knife_hit | impact | 0.22 | 44100 | -6.0 | -24.5 | +0.00016 | - | 2070 | 4 / 17 / 53 / 17 / 9 | ok |
| grenade_bounce | impact | 0.30 | 44100 | -6.0 | -26.3 | +0.00024 | - | 1370 | 2 / 28 / 40 / 29 / 1 | ok |
| pin_pull | weapon | 0.32 | 44100 | -9.0 | -24.7 | +0.00000 | - | 5360 | 0 / 0 / 0 / 79 / 21 | ok |
| impact_concrete | impact | 0.30 | 44100 | -6.0 | -27.1 | +0.00023 | - | 2052 | 2 / 45 / 21 / 22 / 10 | ok |
| impact_metal | impact | 0.45 | 44100 | -6.0 | -24.4 | +0.00000 | - | 1842 | 0 / 0 / 73 / 26 / 1 | ok |
| impact_glass | impact | 0.30 | 44100 | -6.0 | -24.4 | -0.00001 | - | 4788 | 0 / 0 / 0 / 77 / 23 | ok |
| impact_flesh | impact | 0.25 | 44100 | -6.0 | -23.2 | +0.00031 | - | 805 | 13 / 39 / 39 / 8 / 0 | ok |
| impact_wood | impact | 0.25 | 44100 | -6.0 | -25.5 | -0.00014 | - | 867 | 0 / 56 / 35 / 7 / 2 | ok |
| impact_dirt | impact | 0.30 | 44100 | -6.0 | -26.0 | +0.00027 | - | 1485 | 11 / 13 / 50 / 24 / 2 | ok |
| impact_water | impact | 0.40 | 44100 | -6.0 | -26.2 | +0.00001 | - | 2396 | 0 / 1 / 69 / 18 / 12 | ok |
| ricochet | impact | 0.91 | 44100 | -6.0 | -23.7 | -0.00000 | - | 3785 | 0 / 0 / 6 / 84 / 10 | ok |
| glass_break | impact | 1.50 | 44100 | -6.0 | -28.5 | -0.00000 | - | 5945 | 0 / 0 / 5 / 52 / 43 | ok |
| explosion_small | explosion | 3.24 | 44100 | -3.0 | -21.0 | +0.00006 | - | 1073 | 42 / 21 / 20 / 14 / 3 | ok |
| explosion_large | explosion | 5.47 | 44100 | -2.0 | -20.5 | +0.00007 | - | 974 | 50 / 15 / 18 / 15 / 2 | ok |
| fire_loop | ambience | 6.00 | 44100 | -5.6 | -21.0 | +0.00000 | 0.26 / 0.14 / -0.6 dB | 837 | 16 / 42 / 34 / 6 / 2 | ok |
| footstep_concrete | footstep | 0.20 | 44100 | -9.0 | -31.1 | +0.00020 | - | 2673 | 1 / 22 / 23 / 43 / 10 | ok |
| footstep_grass | footstep | 0.25 | 44100 | -9.0 | -28.1 | -0.00001 | - | 4301 | 2 / 2 / 19 / 55 / 22 | ok |
| footstep_sand | footstep | 0.25 | 44100 | -9.0 | -28.9 | -0.00003 | - | 2465 | 3 / 3 / 44 / 45 / 5 | ok |
| footstep_metal | footstep | 0.30 | 44100 | -9.0 | -28.3 | +0.00029 | - | 619 | 19 / 22 / 57 / 2 / 0 | ok |
| footstep_wood | footstep | 0.22 | 44100 | -9.0 | -31.1 | +0.00008 | - | 766 | 1 / 72 / 18 / 8 / 1 | ok |
| footstep_water | footstep | 0.35 | 44100 | -9.0 | -27.3 | +0.00022 | - | 3482 | 10 / 1 / 30 / 40 / 19 | ok |
| jump_land | footstep | 0.32 | 44100 | -6.0 | -24.6 | +0.00036 | - | 1158 | 14 / 37 / 31 / 16 / 2 | ok |
| body_fall | footstep | 0.60 | 44100 | -6.0 | -28.5 | +0.00017 | - | 762 | 33 / 28 / 29 / 9 / 1 | ok |
| splash_small | water | 0.73 | 44100 | -6.0 | -27.5 | +0.00005 | - | 4874 | 2 / 21 / 9 / 33 / 35 | ok |
| splash_large | water | 2.22 | 44100 | -4.0 | -26.5 | +0.00004 | - | 3649 | 6 / 26 / 14 / 31 / 23 | ok |
| swim_stroke | water | 0.55 | 44100 | -9.0 | -24.7 | +0.00000 | - | 3134 | 0 / 1 / 34 / 56 / 10 | ok |
| underwater_loop | ambience | 8.00 | 44100 | -9.8 | -22.0 | +0.00000 | 1.82 / 0.58 / -0.2 dB | 137 | 62 / 35 / 3 / 0 / 0 | ok |
| breath_gasp | voice | 0.75 | 44100 | -6.0 | -23.9 | -0.00000 | - | 1457 | 0 / 8 / 69 / 23 / 0 | ok |
| grunt_hit_m | voice | 0.26 | 44100 | -5.0 | -21.5 | -0.00003 | - | 555 | 3 / 39 / 56 / 2 / 0 | ok |
| grunt_hit_f | voice | 0.24 | 44100 | -5.0 | -19.4 | -0.00001 | - | 848 | 0 / 21 / 78 / 1 / 0 | ok |
| scream_m | voice | 1.54 | 44100 | -6.5 | -18.2 | -0.00000 | - | 736 | 0 / 5 / 93 / 1 / 0 | ok |
| scream_f | voice | 1.64 | 44100 | -7.0 | -17.6 | +0.00000 | - | 1116 | 0 / 0 / 96 / 4 / 0 | ok |
| death_m | voice | 1.00 | 44100 | -5.0 | -23.0 | -0.00000 | - | 889 | 2 / 24 / 65 / 9 / 0 | ok |
| death_f | voice | 0.95 | 44100 | -5.0 | -21.0 | -0.00000 | - | 903 | 0 / 11 / 86 / 2 / 0 | ok |
| chatter_loop | ambience | 8.00 | 44100 | -9.9 | -25.0 | +0.00000 | 0.05 / 0.48 / -1.1 dB | 516 | 2 / 54 / 44 / 1 / 0 | ok |
| engine_car_loop | engine | 2.00 | 44100 | -6.9 | -17.0 | +0.00000 | 2.00 / 0.49 / -0.6 dB | 705 | 1 / 64 / 26 / 9 / 0 | ok |
| engine_sport_loop | engine | 2.00 | 44100 | -8.4 | -16.5 | -0.00000 | 1.46 / 0.66 / -1.0 dB | 901 | 1 / 51 / 36 / 11 / 1 | ok |
| engine_truck_loop | engine | 2.00 | 44100 | -5.5 | -16.5 | +0.00000 | 2.53 / 1.43 / +2.7 dB | 445 | 19 / 63 / 14 / 4 / 0 | ok |
| engine_bike_loop | engine | 2.00 | 44100 | -9.1 | -17.0 | +0.00000 | 0.25 / 0.57 / -0.4 dB | 728 | 1 / 61 / 30 / 8 / 0 | ok |
| engine_boat_loop | engine | 2.00 | 44100 | -7.1 | -17.0 | +0.00000 | 0.12 / 1.03 / +2.3 dB | 663 | 1 / 63 / 28 / 8 / 0 | ok |
| heli_rotor_loop | engine | 2.00 | 44100 | -3.9 | -15.5 | +0.00000 | 1.58 / 0.57 / +0.3 dB | 1017 | 35 / 25 / 26 / 12 / 3 | ok |
| plane_prop_loop | engine | 2.00 | 44100 | -6.4 | -16.0 | +0.00000 | 1.04 / 0.45 / -1.0 dB | 460 | 14 / 66 / 16 / 4 / 1 | ok |
| jet_loop | engine | 4.00 | 44100 | -5.8 | -16.0 | +0.00000 | 0.84 / 1.60 / +0.3 dB | 1332 | 29 / 24 / 22 / 21 / 3 | ok |
| bicycle_loop | engine | 2.00 | 44100 | -10.5 | -26.0 | -0.00000 | 3.74 / 2.38 / +7.1 dB | 2465 | 3 / 26 / 17 / 49 / 5 | ok |
| tire_skid_loop | vehicle | 2.00 | 44100 | -6.6 | -16.0 | -0.00000 | 1.04 / 0.62 / -2.0 dB | 1621 | 0 / 0 / 82 / 16 / 1 | ok |
| tire_roll_loop | vehicle | 3.00 | 44100 | -10.8 | -23.0 | -0.00000 | 0.94 / 2.00 / +0.1 dB | 375 | 40 / 37 / 21 / 2 / 0 | ok |
| crash_small | vehicle | 1.31 | 44100 | -4.0 | -23.4 | +0.00004 | - | 2265 | 1 / 26 / 37 / 26 / 10 | ok |
| crash_large | vehicle | 2.77 | 44100 | -3.0 | -23.1 | +0.00005 | - | 2369 | 12 / 17 / 33 / 27 / 11 | ok |
| metal_scrape_loop | vehicle | 2.50 | 44100 | -6.4 | -17.0 | +0.00000 | 1.46 / 1.31 / +0.1 dB | 3013 | 0 / 2 / 42 / 45 / 11 | ok |
| horn_car | vehicle | 0.90 | 44100 | -8.2 | -15.0 | -0.00000 | - | 940 | 0 / 32 / 56 / 12 / 0 | ok |
| horn_truck | vehicle | 1.30 | 44100 | -6.7 | -14.0 | -0.00000 | - | 588 | 0 / 57 / 39 / 3 / 0 | ok |
| horn_bike | vehicle | 0.55 | 44100 | -8.5 | -16.0 | -0.00000 | - | 1428 | 0 / 0 / 77 / 23 / 0 | ok |
| door_open | vehicle | 0.32 | 44100 | -6.0 | -25.1 | +0.00050 | - | 583 | 25 / 53 / 14 / 7 / 0 | ok |
| door_close | vehicle | 0.40 | 44100 | -6.0 | -26.1 | +0.00034 | - | 696 | 15 / 52 / 25 / 7 / 1 | ok |
| engine_start | vehicle | 1.45 | 44100 | -5.0 | -16.0 | +0.00002 | - | 301 | 7 / 83 / 9 / 1 / 0 | ok |
| tire_pop | vehicle | 1.17 | 44100 | -3.0 | -24.6 | +0.00010 | - | 1516 | 9 / 69 / 1 / 10 / 10 | ok |
| siren_police_loop | siren | 3.20 | 44100 | -8.9 | -14.5 | +0.00000 | 2.05 / 2.09 / -7.1 dB | 1419 | 0 / 0 / 89 / 10 / 0 | ok |
| siren_ambulance_loop | siren | 2.04 | 44100 | -8.7 | -14.5 | +0.00000 | 2.12 / 1.75 / -6.8 dB | 1536 | 0 / 0 / 90 / 10 / 1 | ok |
| siren_fire_loop | siren | 2.20 | 44100 | -8.4 | -14.0 | -0.00000 | 3.45 / 3.65 / -3.4 dB | 936 | 0 / 28 / 65 / 7 / 0 | ok |
| tram_bell | vehicle | 2.20 | 44100 | -6.0 | -20.0 | +0.00000 | - | 1050 | 0 / 3 / 94 / 3 / 0 | ok |
| tram_loop | vehicle | 4.00 | 44100 | -7.3 | -20.0 | -0.00000 | 3.42 / 0.82 / -2.7 dB | 411 | 12 / 64 / 23 / 1 / 0 | ok |
| parachute_open | vehicle | 0.95 | 44100 | -6.0 | -27.6 | +0.00002 | - | 1176 | 15 / 23 / 46 / 15 / 1 | ok |
| parachute_loop | vehicle | 4.00 | 44100 | -6.2 | -21.0 | -0.00000 | 0.91 / 1.24 / +3.8 dB | 1238 | 1 / 25 / 58 / 16 / 1 | ok |
| wind_fall_loop | ambience | 4.00 | 44100 | -5.7 | -19.0 | -0.00000 | 0.74 / 1.16 / +1.1 dB | 1717 | 27 / 24 / 19 / 23 / 7 | ok |
| ui_click | ui | 0.09 | 44100 | -10.0 | -24.6 | -0.00002 | - | 1423 | 0 / 0 / 86 / 14 / 0 | ok |
| ui_hover | ui | 0.05 | 44100 | -16.0 | -28.5 | -0.00001 | - | 1621 | 0 / 0 / 97 / 3 / 0 | ok |
| ui_open | ui | 0.33 | 44100 | -10.0 | -22.8 | +0.00000 | - | 1025 | 0 / 0 / 98 / 2 / 0 | ok |
| ui_close | ui | 0.28 | 44100 | -10.0 | -21.8 | -0.00000 | - | 925 | 0 / 0 / 98 / 2 / 0 | ok |
| ui_error | ui | 0.34 | 44100 | -13.0 | -19.7 | -0.00004 | - | 254 | 0 / 91 / 8 / 0 / 0 | ok |
| ui_buy | ui | 0.50 | 44100 | -10.0 | -25.3 | +0.00000 | - | 2077 | 0 / 0 / 82 / 17 / 0 | ok |
| ui_tab | ui | 0.09 | 44100 | -10.0 | -23.7 | +0.00034 | - | 584 | 0 / 8 / 91 / 0 / 0 | ok |
| pickup_cash | ui | 0.50 | 44100 | -8.0 | -24.2 | -0.00000 | - | 2909 | 0 / 0 / 37 / 58 / 5 | ok |
| pickup_weapon | ui | 0.45 | 44100 | -8.0 | -22.4 | +0.00007 | - | 1045 | 0 / 7 / 86 / 7 / 0 | ok |
| pickup_health | ui | 1.07 | 44100 | -8.0 | -22.5 | +0.00000 | - | 849 | 0 / 0 / 98 / 2 / 0 | ok |
| wanted_up | stinger | 1.82 | 44100 | -6.0 | -26.2 | +0.00004 | - | 481 | 13 / 70 / 14 / 2 / 1 | ok |
| wanted_down | stinger | 1.50 | 44100 | -6.0 | -24.5 | +0.00000 | - | 470 | 0 / 77 / 22 / 0 / 0 | ok |
| wanted_clear | stinger | 2.56 | 44100 | -6.0 | -22.5 | -0.00000 | - | 1027 | 0 / 1 / 95 / 4 / 0 | ok |
| arrested | stinger | 2.75 | 44100 | -6.0 | -24.6 | +0.00000 | - | 448 | 10 / 70 / 17 / 3 / 0 | ok |
| player_down | stinger | 3.82 | 44100 | -6.0 | -21.5 | +0.00006 | - | 167 | 63 / 32 / 5 / 0 / 0 | ok |
| camera_shutter | ui | 0.22 | 44100 | -8.0 | -27.7 | +0.00003 | - | 2189 | 0 / 57 / 3 / 32 / 8 | ok |
| phone_open | ui | 0.40 | 44100 | -10.0 | -23.7 | -0.00001 | - | 1366 | 0 / 0 / 98 / 2 / 0 | ok |
| cash_register | ui | 1.00 | 44100 | -6.0 | -20.6 | +0.00004 | - | 2294 | 3 / 1 / 1 / 93 / 2 | ok |
| spray_paint | ui | 1.30 | 44100 | -9.0 | -22.9 | -0.00000 | - | 6356 | 0 / 1 / 6 / 48 / 45 | ok |
| wrench | ui | 0.95 | 44100 | -6.0 | -25.3 | +0.00002 | - | 1721 | 0 / 27 / 34 / 38 / 2 | ok |
| target_hit | ui | 0.60 | 44100 | -6.0 | -23.0 | +0.00002 | - | 2035 | 0 / 0 / 59 / 40 / 1 | ok |
| activity_start | stinger | 1.47 | 44100 | -9.0 | -20.6 | -0.00000 | - | 1043 | 0 / 0 / 98 / 2 / 0 | ok |
| activity_win | stinger | 2.67 | 44100 | -6.0 | -23.7 | -0.00000 | - | 1684 | 0 / 5 / 52 / 42 / 1 | ok |
| rain_loop | ambience | 8.00 | 44100 | -11.1 | -25.0 | +0.00000 | 0.37 / 0.80 / -0.1 dB | 4565 | 0 / 2 / 30 / 41 / 27 | ok |
| rain_heavy_loop | ambience | 8.00 | 44100 | -6.3 | -21.0 | -0.00000 | 1.12 / 0.52 / +0.4 dB | 3883 | 1 / 14 / 31 / 30 / 24 | ok |
| thunder_1 | ambience | 8.30 | 44100 | -3.0 | -16.9 | -0.00001 | - | 402 | 45 / 39 / 13 / 3 / 1 | ok |
| thunder_2 | ambience | 9.30 | 44100 | -6.0 | -21.2 | +0.00000 | - | 155 | 58 / 38 / 3 / 0 / 0 | ok |
| wind_loop | ambience | 10.00 | 44100 | -8.1 | -24.0 | -0.00000 | 1.05 / 2.34 / +0.8 dB | 947 | 1 / 35 / 55 / 9 / 0 | ok |
| ocean_loop | ambience | 12.00 | 44100 | -8.1 | -23.0 | +0.00000 | 0.49 / 0.07 / -3.9 dB | 1691 | 27 / 28 / 20 / 18 / 8 | ok |
| city_loop | ambience | 12.00 | 44100 | -11.3 | -25.0 | -0.00000 | 0.79 / 0.79 / -2.3 dB | 517 | 28 / 42 / 25 / 4 / 0 | ok |
| industrial_loop | ambience | 9.00 | 44100 | -11.1 | -24.0 | -0.00000 | 0.78 / 0.31 / -3.4 dB | 339 | 39 / 41 / 19 / 1 / 0 | ok |
| park_birds_loop | ambience | 10.00 | 44100 | -10.1 | -28.0 | -0.00000 | 0.72 / 0.24 / -1.9 dB | 4302 | 0 / 0 / 0 / 97 / 3 | ok |
| night_crickets_loop | ambience | 8.00 | 44100 | -10.4 | -28.0 | +0.00000 | 0.01 / 0.02 / -0.1 dB | 4479 | 2 / 2 / 0 / 96 / 0 | ok |
| airport_loop | ambience | 12.00 | 44100 | -8.9 | -24.0 | -0.00000 | 0.57 / 0.30 / -0.4 dB | 625 | 31 / 36 / 25 / 8 / 0 | ok |
| harbor_loop | ambience | 12.00 | 44100 | -8.5 | -25.0 | +0.00000 | 0.20 / 0.42 / -2.6 dB | 1517 | 4 / 16 / 55 / 24 / 2 | ok |
| radio_static | radio | 0.42 | 44100 | -10.0 | -24.7 | +0.00000 | - | 3694 | 0 / 2 / 38 / 41 / 19 | ok |
| animal_deer | animal | 0.60 | 44100 | -8.0 | -20.9 | -0.00000 | - | 884 | 0 / 18 / 76 / 6 / 0 | ok |
| animal_dog_bark | animal | 1.23 | 44100 | -6.0 | -23.5 | +0.00002 | - | 975 | 0 / 11 / 85 / 4 / 0 | ok |
| animal_bird | animal | 1.49 | 44100 | -9.0 | -21.2 | -0.00000 | - | 4283 | 0 / 0 / 0 / 98 / 2 | ok |
| animal_gull | animal | 2.65 | 44100 | -8.0 | -22.4 | -0.00000 | - | 2300 | 0 / 0 / 55 / 45 / 0 | ok |
| animal_growl | animal | 1.20 | 44100 | -7.0 | -18.1 | -0.00000 | - | 782 | 3 / 37 / 50 / 9 / 0 | ok |
| radio_neon_tide_1 | music | 38.40 | 32000 | -4.3 | -16.5 | -0.00000 | 0.85 / 0.75 / +16.2 dB | 763 | 53 / 20 / 18 / 5 / 3 | ok |
| radio_neon_tide_2 | music | 36.92 | 32000 | -3.7 | -16.5 | +0.00000 | 0.18 / 0.24 / +15.3 dB | 739 | 55 / 23 / 15 / 5 / 4 | ok |
| radio_low_tide_1 | music | 36.92 | 32000 | -5.9 | -16.5 | +0.00000 | 0.24 / 0.28 / +29.1 dB | 244 | 58 / 28 / 13 / 1 / 0 | ok |
| radio_low_tide_2 | music | 40.00 | 32000 | -5.3 | -16.5 | +0.00000 | 0.18 / 0.21 / +34.7 dB | 256 | 60 / 26 / 12 / 1 / 0 | ok |
| radio_boogie_bay_1 | music | 33.10 | 32000 | -3.9 | -16.5 | -0.00000 | 0.50 / 0.30 / +8.2 dB | 801 | 63 / 11 / 17 / 4 / 4 | ok |
| radio_boogie_bay_2 | music | 32.00 | 32000 | -3.7 | -16.5 | +0.00000 | 0.38 / 0.29 / +7.6 dB | 915 | 59 / 12 / 20 / 4 / 5 | ok |
| radio_breakwater_1 | music | 33.49 | 32000 | -5.6 | -16.5 | +0.00000 | 0.70 / 0.10 / +6.7 dB | 840 | 60 / 20 / 11 / 4 / 5 | ok |
| radio_breakwater_2 | music | 33.10 | 32000 | -4.7 | -16.5 | -0.00000 | 0.97 / 0.69 / +6.4 dB | 846 | 59 / 23 / 9 / 3 / 5 | ok |
| radio_drift_1 | music | 41.14 | 32000 | -3.8 | -16.5 | +0.00000 | 0.03 / 0.22 / -1.6 dB | 419 | 30 / 42 / 27 / 1 / 0 | ok |
| radio_drift_2 | music | 43.64 | 32000 | -4.7 | -16.5 | -0.00000 | 0.18 / 0.04 / -7.1 dB | 616 | 28 / 27 / 41 / 3 / 0 | ok |

## 5. Runtime: the `Audio` autoload

### Bus layout (created at boot, idempotent)

```
Master  [AudioEffectHardLimiter, ceiling -0.5 dB]
 ├─ SFX        [low-pass, off]      <- Weapons, Engine
 │   ├─ Weapons
 │   └─ Engine   (-2 dB)
 ├─ Music      [low-pass, off]
 ├─ Ambience   [low-pass, off]
 └─ UI         (-3 dB)
```

`Settings` owns the volumes of Master / SFX / Music / Ambience; they are applied again when the
buses exist and on `EventBus.settings_changed`. `Audio.set_underwater(on)` (called by the
environment system; `EventBus.player_submerged` works too) glides the low-pass on SFX / Music /
Ambience from 18 kHz down to 560 Hz in about 0.2 s; the UI bus is never filtered.

### API

```gdscript
Audio.play(id, volume_db = 0.0, pitch = 1.0, bus = "SFX", pitch_variation = -1.0)
Audio.play_at(id, position, volume_db = 0.0, pitch = 1.0, max_distance = 80.0, bus = "SFX", pitch_variation = -1.0)
Audio.make_loop_player(id, parent, max_distance = 70.0, bus = "SFX") -> AudioStreamPlayer3D
Audio.make_loop_player_2d(id, bus = "Ambience") -> AudioStreamPlayer
Audio.get_stream(id) -> AudioStream          # null for unknown ids
Audio.has_sound(id) -> bool
# additions
Audio.play_ui(id, volume_db = 0.0, pitch = 1.0)   # UI bus, keeps sounding while the tree is paused
Audio.stop_all(include_loops = false)
Audio.set_underwater(on) / Audio.is_underwater()  # signal underwater_changed(on)
Audio.get_stats() -> Dictionary                    # played / stolen / culled / dropped / deduped / active voices
Audio.get_sound_ids() -> PackedStringArray         # everything on disk (for the admin sound browser)
Audio.get_category(id), Audio.is_loop_id(id), Audio.get_bus_names(), Audio.set_bus_volume(bus, linear)
Audio.SOUND_IDS                                    # the 120 canonical ids
Audio.auto_event_sounds = true                     # see "event glue"
```

- **Unknown ids are silent** (counted in `get_stats().unknown`), never an error.
- **Pools**: 12 `AudioStreamPlayer` + 32 `AudioStreamPlayer3D` voices are created once; `play`
  / `play_at` never allocate. When all voices are busy, `play` steals the oldest voice;
  `play_at` steals the voice with the highest "distance relative to its range + age" score, and
  drops the new sound instead if it is even less important than that. Positional sounds beyond
  their audible range are not started at all (culled).
- **De-duplication**: the same non-positional id within 45 ms, or the same positional id within
  25 ms and 1.5 m, is played once (protects against double triggers and shotgun-pellet spam).
- **Loops**: ids ending in `_loop` and the radio tracks get `LOOP_FORWARD` over the whole file
  when they are loaded. `play` / `play_at` always use a non-looping copy (a loop id played as a
  one-shot plays once and frees its voice); `make_loop_player*` always returns a looping stream.
  For the horns (one-shots) the loop player sustains the exactly periodic middle section of the
  sample (`SUSTAIN_SECTIONS`), so a held horn does not pulse.
- **Pitch variation**: `pitch_variation` is a ± fraction; negative (default) means "category
  default" (footsteps ±6 %, impacts ±7 %, weapons ±3 %, voices ±4 %, UI / stingers 0).
- **Pause**: positional voices and non-UI one-shots pause with the scene tree; `ui_*` ids,
  anything on the UI bus and anything requested while the tree is paused keep playing. Loop
  players from `make_loop_player_2d` are pausable; 3D loop players inherit from their parent.
- **Routing**: with the default bus `"SFX"` gunshots and explosions go to `Weapons`, engine-type
  loops to `Engine`, `ui_*` to `UI`; an explicit bus is always respected (falls back to Master
  if it does not exist).

### Categories (falloff, range, trim)

3D voices use inverse-distance attenuation; `unit` is the distance of 0 dB, `min range` raises a
caller's `max_distance` when it is shorter, `cutoff` is the distance low-pass.

| Category | ids | unit m | min range m | cutoff Hz | trim dB | pitch var |
|---|---|---|---|---|---|---|
| weapon | `*_shot`, `rocket_launch` | 14 | 150 | 9000 | 0 | ±3 % |
| explosion | `explosion_*` | 30 | 280 | 7000 | +1.5 | ±5 % |
| impact | `impact_*`, `ricochet`, `glass_break`, melee, reload… | 5 | – | 6000 | −1 | ±7 % |
| footstep | `footstep_*`, `jump_land`, `body_fall`, `splash_*`, `swim_stroke` | 3 | – | 5000 | −2 | ±6 % |
| voice | `grunt_*`, `scream_*`, `death_*`, `breath_gasp` | 6 | – | 5000 | −1 | ±4 % |
| vehicle | `crash_*`, `door_*`, `engine_start`, `tire_pop`, `parachute_*`, `metal_scrape_loop` | 8 | – | 5500 | 0 | ±3 % |
| engine | `engine_*`, `heli_*`, `plane_*`, `jet_*`, `bicycle_*`, `tire_*`, `tram_loop` | 6.5 | – | 5000 | 0 | 0 |
| siren | `siren_*` | 18 | 150 | 6500 | −2 | 0 |
| horn | `horn_*`, `tram_bell` | 12 | – | 6000 | −1 | 0 |
| animal | `animal_*` | 8 | – | 6000 | −3 | ±6 % |
| ui | `ui_*`, `pickup_*`, `wanted_*`, `activity_*`, stingers | – | – | – | −2 | 0 |

### Event glue

So that the stingers exist even if no gameplay module plays them, `Audio` listens to EventBus:
`wanted_level_changed` → `wanted_up` / `wanted_down`, `wanted_cleared` → `wanted_clear`
(`"busted"` → `arrested`, `"died"` → nothing), `ui_screen_opened/closed` → `ui_open` /
`ui_close` (`phone_open` for the phone), `item_purchased` → `ui_buy`. The UI ones are skipped
when another module played a UI-category sound within the last 120 ms (so a module that plays
its own sound does not get a double); the glue's own stingers (e.g. a `wanted_up` just before a
screen opens) do not count for that test. Set `Audio.auto_event_sounds = false` to turn all of
it off.

## 6. Radio system (`Game.get_system("radio")`)

- Stations: Registry kind `radio_stations` (dictionaries: `id, name, display_name, genre,
  frequency, tagline, color, tracks, volume_db, order`; the HUD caption shows `display_name`
  with "genre - frequency FM" below it and switches off the radio's own toast).
- Plays on the **Music** bus while the player sits in a vehicle with a radio: not
  `vehicle_class == "bicycle"`, not `is_police` / `is_emergency`, not `destroyed`.
- Input actions `radio_next` / `radio_prev` cycle `off → neon_tide → low_tide → boogie_bay →
  breakwater → drift → off`.
- Each station is a continuous broadcast: its two loops alternate (two plays each) on a shared
  clock, so tuning in lands mid-song and switching back does not restart the music. Station
  changes get a short static blip; loop changes inside a station crossfade over 1.4 s.
- The last station is stored in `Settings` (`radio_station`; `"off"` is remembered too, an
  empty value means "first station"). `EventBus.radio_station_changed(id)` is emitted on change.
- The players are pausable: the radio pauses with the game.

```gdscript
radio.get_stations(include_off = false) -> Array[Dictionary]
radio.get_station_ids(include_off = true) -> PackedStringArray
radio.get_station() -> String            # "off" or a station id
radio.set_station(id)                    # "off" / "" = off, unknown ids ignored
radio.next_station() / radio.prev_station()
radio.get_station_info(id = "") -> Dictionary
radio.is_listening() / radio.is_playing() / radio.get_now_playing() -> Dictionary
radio.force_listening(mode)              # debug: 1 on, 0 off, -1 automatic
radio.announce = true                    # UI.notify toast with the station name on change
signals: station_changed(id), listening_changed(on)
```

## 7. Ambience system (`Game.get_system("ambience")`)

Twelve looping beds on the Ambience bus, created on demand and crossfaded (2.4 s full scale;
rain and the underwater switch are faster). Four times per second the system samples:

| Input | Source | Effect |
|---|---|---|
| district | `Game.world.get_district(listener)` | base mix: downtown/midtown → city + chatter; residential → birds/crickets + some city; industrial → machinery; waterfront → harbour + ocean; beach / ocean → ocean; hill → birds/crickets + wind; airport → apron bed |
| time | `WorldClock.get_daylight()` | birds by day, crickets at night, city and machinery quieter at night, chatter only by day |
| sea | terrain / district probes on rings of 14–85 m | ocean bed comes in near open water in any district |
| altitude | height above ground / sea level | wind rises from 12 m, ground beds fall away above 40 m |
| weather | `Weather.rain_intensity`, `wind_strength` | `rain_loop` up to moderate rain, crossfading to `rain_heavy_loop`; wind bed; rain silences birds and crickets |
| state | player vehicle class, `is_underwater` | enclosed cabin (car, heli, plane) ducks to 60 %; underwater ducks everything to 6 % and brings in `underwater_loop` |

Thunder is not played here (the environment system triggers `thunder_1/2`). A sparse positional
"life" layer places an occasional gull (near the sea, by day), bird or far dog bark 28–60 m
around the listener (`spot_sounds = false` turns it off).

```gdscript
AmbienceSystem.compute_targets(ctx) -> Dictionary   # pure: layer -> gain, ctx keys: district, daylight,
                                                    # rain, wind, altitude, sea, in_vehicle, underwater
ambience.get_layer_gains() / get_target_gains() / get_context() / get_dominant_layer()
ambience.set_context_override(ctx) / clear_context_override()   # photo mode, tests
ambience.snap()                                     # jump to the target mix after a teleport
ambience.set_enabled(on)
```

## 8. Tests and verification

| What | Command | Result |
|---|---|---|
| Synthesis run | `python tools/audio/synth.py --jobs 6` | 130 files, 644 s of audio, no flags |
| Determinism | re-run of 7 ids incl. 2 music loops, md5 compared | identical |
| File verification | `python tools/audio/verify.py` | `VERIFY_OK: 130 files, no problems` |
| Parse check | `tools\godot.ps1 -Mode check -Dirs 'gta/code/audio,gta/resources/registries,gta/tests'` | 63 files, 0 fails |
| API test | `tools\godot.ps1 -Mode headless -Frames 3000 -UserArgs '--test=aud_api','--no_player','--disable=world,traffic,peds,police'` | `TEST_RESULT: PASS aud_api checks=103` (clean stderr apart from the engine's exit-time leak note that every module's runs show) |
| In-game test | `tools\godot.ps1 -Mode headless -Frames 2600 -UserArgs '--test=aud_ingame'` | `TEST_RESULT: PASS aud_ingame checks=9` (real world, 7 districts, player in a real sedan, `radio_next`, exit, police cruiser stays silent) |
| Integration scan | every literal sound id used by other modules' code (`Audio.play*`, weapon `sound_*` fields) compared with `gta/generated/audio/*.wav` | none missing |

`aud_api` covers: all 120 canonical ids resolve (it prints `AUD_MISSING: (none)`), loop flags,
bed and radio lengths, unknown ids, bus layout / sends / limiter, underwater filter on and off,
pool size constant under a burst of 400 requests, stealing, culling, de-duplication, pitch
variation, routing, loop players, horn sustain loops (sample-exact periodicity, ≤ 2 LSB),
in-engine loop seams, the radio with a simulated player + vehicle (cycling with the input
actions, Settings, EventBus, emergency vehicle, bicycle, exit, pause measured on the playback
position), the ambience mix function for fake districts / times / weather and a live crossfade,
the positional animal-call layer, and the EventBus glue (wanted stingers, `ui_open` on screen
open, no double sound when the UI module already played one, `auto_event_sounds = false`).

## 9. Honest limits

- Nobody has listened to these sounds: the build ran headless with the Dummy audio driver, so
  the quality argument rests on well-understood recipes and on the numeric checks above (levels,
  spectra, seams, attack times, tempo and key of the music). Timbre is stylised, not realistic.
- The whole pipeline is mono; positional panning comes from Godot.
- Voices are deliberately vowel-only synthetic sounds; `chatter_loop` is a murmur, not speech.
- Radio stations have two loops each (about 70–85 s of music per station before it repeats).
- Dedupe windows are real-time milliseconds; in accelerated headless runs many game frames fit
  into one window (tests account for it).
