# Claude Fable 5.2 — Godot GTA-style Sandbox: Final Report

**Halcyon Bay** is an original, missionless free-roam crime sandbox on a ~600×600 m island, built with
Godot 4.7.2 (GDScript, Forward+, Jolt) and Blender 5.2 driven through the MCP server on port 9882.
The art direction is "Sunlit Low-Poly": faceted flat-shaded models, palette colours, warm sun, neon
nights. The work was done by a lead agent orchestrating parallel sub-agents in waves (foundation →
assets + core modules → sandbox systems → breadth). The user asked to finish early, so the planned
final QA wave was skipped and the last wave was stopped during its verification pass — see
`FEATURE_MATRIX.md` for the honest per-feature status.

## How to launch

Open the folder in Godot 4.7.2 and press F5, or run
`W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --path "<this folder>"`.
The game starts directly in free roam (it continues the newest save if one exists; `--new-game` skips it).

## Controls

WASD move / drive · mouse look / aim · Shift sprint · Space jump / handbrake · C crouch · Ctrl stealth ·
Q cover · F enter / exit / carjack · LMB fire / melee · RMB aim · X heavy melee · R reload · G grenade ·
1–9 / wheel weapons · Tab weapon wheel · E interact · H horn · L headlights · T siren · K roof ·
, / . radio · Y radio wheel · V camera · M map · P phone · Esc pause · F1 admin menu · F2 photo mode ·
F3 debug overlay · F5 / F9 quick save / load. Aircraft: W/S power, A/D yaw, arrows pitch / roll, G gear.

## What was built

- **Map regions:** Downtown (towers, plaza, tram), Midtown (shops, services), Residential
  ("Sandpiper Heights", park), Industrial (warehouses, yards), Waterfront / marina / docks, Beach,
  Signal Hill (wooded, viewpoint, radio mast), Airport (runway, hangars, tower, helipad). Ring arterial
  plus avenues and streets: 75 segments, 174 lanes, 41 intersections (23 signalised).
- **Landmarks:** police station, hospital, gun shop ("Bay Arms"), shooting range, mod garage
  ("Torque Garage"), clothing store ("Tide Threads"), barber, corner store, gas station, safehouse,
  parking garage, airport hangar and tower, lighthouse, tram stops, radio mast, piers.
- **Vehicles (all Blender-authored):** compact, sedan, sports, muscle, SUV, pickup, van, police cruiser,
  taxi, ambulance, fire truck, SWAT van, box truck, motorcycle, bicycle, speedboat, jetski, dinghy,
  civil helicopter, police helicopter, prop plane, jet.
- **Weapons (all Blender-authored):** fists, knife, bat, crowbar, pistol, heavy pistol, SMG, pump
  shotgun, auto shotgun, assault rifle, carbine, marksman rifle, sniper rifle, grenade, molotov, rocket
  launcher, grenade launcher; attachments (suppressor, scope, flashlight, grip, extended magazine, tints).
- **Wanted / police:** 0–5 stars driven by crime heat; crimes become known through police sightings,
  civilian witness phone calls or loud-noise reports; pursuit → search (flashing stars, growing search
  area around the last known position) → escape only while unseen; arrests ("ARRESTED") at low levels,
  lethal force from 2 stars, cruisers with PIT / ramming / boxing, roadblocks from 3 stars, spike strips
  and SWAT from 4, helicopter written in the last wave.
- **Other systems:** traffic, pedestrians, gangs, wildlife, ambulance / fire response, taxi, tram,
  shops, wardrobe, barber, garages, mod shop, safehouse, save / load, skills, activities, radio, phone,
  photo mode, admin menu.

## Major Blender assets

~275 asset roots in `GodotFable5.2GTAUltracode.blend` under `GTA_GODOT/` (characters, vehicles, weapons,
buildings, landmarks, street props, nature, animals, misc). They include a rigged modular humanoid
(20 bones, 64 parts, 10 outfits and archetypes, Idle / Walk / Run clips), 22 vehicles plus 4 wheel
sets, 17 weapons plus projectiles and pickups, 48 buildings, ~80 street props, ~45 nature assets,
11 animals and ~45 set pieces (tram, shipwreck, harbour crane, containers, stunt ramps, parachute).
Every asset has builder code in `tools/blender/assets/` and a GLB in `gta/generated/models/`.

## What is partial / known issues

Parachute, police helicopter, taxi, tram full loop, phone / photo / radio wheel, activities and
the skills audit were written in the last wave but not fully re-verified (agents stopped on request).
Other known issues:
- Headless runs print dummy-renderer RID errors from loading animal and terminal models.
- AI awareness counts stealth twice.
- The in-cabin drive-by camera is not tuned for vans, the box truck and the sports car.
- Chases were tested without traffic.
- Audio was never listened to by a human.
- The whole-game performance tour (Wave 4) was not run.
- The remaining backlog is in `docs/QA_BACKLOG.md`.

## Build result

`tools/godot.ps1 -Mode check` → 404 scripts, 0 failures. Full headless boot plus 60 s of play: no
script errors. The lead integration test `int_slice` (walk, shoot, drive, night, island tour, wanted
HUD, map) passes. A city screenshot tour shows buildings, traffic, pedestrians, vegetation and
lit windows at night.

## Performance notes

Boot is ~4–5 s headless and ~8.5 s windowed. Measured per module:
- City: 175 placements, 0.5–0.7 ms GPU per view.
- Dressing: MultiMesh per 75 m cell, ~1 ms GPU.
- Caps: traffic ≤ 22 moving cars, ≤ 40 pedestrians; police, ragdoll and particle caps are pooled.

Shipped defaults: V-Sync on, 60 FPS cap, render scale ≤ 1.0. All tests used the capped wrapper on a
GPU shared with five other benchmark sessions. When their runs overlapped with ours the GPU briefly
reached 96–99 %; the wrapper's GPU gate was then tightened. No driver incident occurred.

## Claude Fable 5.2 GTA Session Metrics

Project: Godot GTA sandbox
Run/session identifier: run-20261109-215759 / Claude Code session f0ccccf9-8795-4dac-a29e-5a331b39db1d
Working-directory full path: G:\YouTube\Fable 5.2 Effort Test GTA\Ultracode
Start timestamp and timezone: 2026-11-09T21:57:59.952+01:00 (Central European Standard Time)
End timestamp and timezone: 2026-11-10T15:50:52.049+01:00 (Central European Standard Time)
Elapsed wall-clock time (HH:MM:SS): 17:52:52
Elapsed minutes: 1072.9
Elapsed hours: 17.88
Known pauses / resumed segments: 3 pauses = 433.9 min (23:31–23:45 Fable usage limit; 01:21–05:49 Fable usage limit, then model switched to Opus 5.5; 06:00–08:32 user-requested stop). Working time excluding pauses ≈ 639 min (10.65 h). Details: `.fable-5.2-gta-runs/run-20261109-215759/segments.txt`

Requested model: Claude Fable 5.2
Actual model identifier(s): claude-fable-5-2 (2,643 requests, until the second usage limit) and claude-opus-5-5 (4,583 requests, after the user switched the session model)
Thinking/effort setting (if exposed): adaptive thinking (always on); session effort not exposed in the logs
Input tokens (state whether uncached or inclusive): 14,516 uncached (Fable 5,306 / Opus 9,210)
Cache-read tokens: 2,238,022,290 (Fable 743,872,178 / Opus 1,494,150,112)
Cache-write tokens: 54,671,816 (Fable 22,478,153 / Opus 32,193,663)
Cache-write duration breakdown (if exposed): 5-minute 53,330,279 · 1-hour 1,341,537
Output tokens: 14,506,089 (Fable 8,258,700 / Opus 6,247,389)
Thinking/reasoning tokens (included / separate / unavailable): included in output (7,128,551 of the output tokens)
Deduplicated total tokens: 2,307,214,711 (7,226 requests; Fable 774,614,337 / Opus 1,532,600,374)
Usage source and observation cutoff: local Claude Code transcript JSONL of this session and all of its sub-agent / workflow-agent transcripts, read by `tools/usage/collect_usage.py` (usage metadata only, de-duplicated by message id + request id); cutoff 2026-11-10T14:50:28Z (15:50:28 local)
Unmeasured work / limitations: the final report-writing turns after the cutoff are not included. Usage of the Blender/Godot processes is not token usage.

Token-only API-equivalent cost (USD): **≈ $1,582.73** (measured tokens × verified Fable 5.2 rates). Per the user's instruction, ALL tokens, Fable and Opus alike, are priced at the Fable 5.2 rates.
Per-model subtotals (if applicable): tokens produced by claude-fable-5-2 ≈ $706.75; tokens produced by claude-opus-5-5 but priced at Fable 5.2 rates ≈ $875.98 (user's pricing rule; not Opus's own price)
Official pricing source, verification date and comparison tier: Anthropic pricing as published in the official claude-api reference bundled with Claude Code (cached 2026-11-03; source page https://platform.claude.com/docs/en/about-claude/pricing), checked 2026-11-10; Standard tier
Rates and formula used: input $8.00 / MTok, cache write 5 m $10.00 (1.25×), cache write 1 h $16.00 (2×), cache read $0.20, output $40.00. Cost = Σ category tokens × rate / 1,000,000 → input $0.12 + cache-write-5m $533.30 + cache-write-1h $21.46 + cache-read $447.60 + output $580.24
Cache/context/tier adjustments or explicit assumptions: Standard tier; no batch / fast-mode / long-context adjustments; Opus 5.5 tokens priced at Fable rates as requested by the user
External tool/API fees (known / excluded / unknown): none known (local Blender and Godot; no web search / fetch requests were made)
Measured / estimated / unavailable, with reasons: token counts measured (session logs); cost computed from measured tokens and documented rates; wall-clock time measured from OS timestamps

Blender MCP server/tool namespace actually used: blender-gta-ultracode (mcp__blender-gta-ultracode__*), add-on "MCP for Blender" 1.8
Blender host: localhost
Blender port: 9882
Blender master file: GodotFable5.2GTAUltracode.blend
Verified full path of master file: G:\YouTube\Fable 5.2 Effort Test GTA\Ultracode\GodotFable5.2GTAUltracode.blend
Approximate number of major Blender assets created: ~275 asset roots, 275 exported GLBs
