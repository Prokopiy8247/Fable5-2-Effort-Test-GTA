# Cinder Bay — Final Report (Claude Fable 5.2 · Godot + Blender MCP GTA benchmark)

## What was built

**Cinder Bay** is a missionless, GTA-style single-player free-roam sandbox on a compact ~600 × 600 m map. It runs in
**Godot 4.7.2 (Forward+, Vulkan, Jolt)**, and all of its gameplay code is GDScript (~14,000 lines in 42 scripts).
Every important 3D asset was modelled procedurally in **Blender 5.2.2** through the project-bound MCP connection
(`blender-gta-extra`, `localhost:9880`, `GodotFable5.2GTAExtra.blend`) and exported as 35 GLB files. The art
direction is "sunwashed low-poly": flat-coloured, bevel-free shapes with a warm, saturated palette, night-lit
windows, wet roads in rain and wind-animated foliage.

The game starts straight into free roam. It has **no missions, quests or objective markers**. The optional
activities are a shooting-range challenge, five named stunt jumps and a ring-road time trial, and the player
starts each one.

See `DEVELOPMENT.md` for the architecture, controls and Blender workflow, and `FEATURE_MATRIX.md` for the status of
each feature.

## What works (summary)

* **On foot:** walk, run, sprint, jump, crouch-stealth and stealth takedowns, the cover system (low/high cover,
  peek-aim, blind fire), climbing ledges, ladders, combat roll and melee (fists, knife, bat, crowbar, nightstick).
  You can also swim and dive (breath meter, scuba gear), use a parachute, aim in third person or switch to first
  person, and get knocked down (ragdoll-lite).
* **NPCs:** pedestrians with varied looks walk a sidewalk graph and react to danger by fleeing, cowering,
  investigating, calling the police as witnesses or fighting back. Shops have clerks, gangs occupy Ironworks and
  the Docks, and the AI uses distance-based simulation tiers.
* **Traffic:** cars follow a lane graph through intersections with traffic signals, park at kerbs, in lots and in
  emergency bays, and yield to sirens.
* **Vehicles:** 21 vehicles in total: 13 cars (including emergency vehicles), a motorcycle, a bicycle, 2 boats,
  2 helicopters and 2 airplanes. Cars use project-owned raycast suspension and tyre physics. You can carjack, do
  drive-bys, use the siren, lights, radio and convertible roof, pop tyres, set cars on fire, blow them up and
  flood them in deep water.
* **Vehicle shops:** Torque Bay Customs offers 21 cosmetic and performance mod slots, paint and finishes, plus
  repairs. The personal garage stores cars, and the mechanic can deliver them on request.
* **Weapons:** 17 weapons plus fists in 8 slots, a weapon wheel, attachments (suppressor, flashlight, optic, grip,
  extended magazine) and tints. The gun shop sells weapons and ammo, and there is a workbench for attachments.
  Explosives and molotov fire zones work.
* **Wanted system (0–5 stars):** witnesses phone it in, police need line of sight, there is a pursuit state and a
  search state, and the escape timer only runs while you are unseen. Police chase in cars and dismount, set
  roadblocks with spike strips, send a helicopter with a searchlight and bring SWAT vans. Getting busted sends you
  to the police station and costs bail; dying sends you to the hospital and costs a fee.
* **World:** a day/night cycle; 5 weather types; physics props that get knocked over; shops (store, clothes,
  barber, guns, mods, ATM); and a safehouse (the bed saves and skips time, plus a wardrobe and the garage). The
  phone calls a taxi, the mechanic or paramedics, sets waypoints and has a photo mode and the radio. There is a
  minimap, a full map with GPS route, taxi rides, an elevated train, wildlife (land, birds, fish, sharks),
  ambulance and fire-engine response, and an underwater wreck with treasure.
* **Presentation:** a full HUD, a pooled VFX system, procedural audio (weapons, engines, sirens, ambience and
  5 procedural radio stations), pause/settings/stats menus, save/load, and the **F1 admin/benchmark menu**.

## What is partial / not implemented

* There is no navmesh. Pedestrians use a sidewalk graph and steering instead of `NavigationRegion3D`. **NOT
  IMPLEMENTED**
* World streaming is static: chunks are built at start and culled by distance. **PARTIAL**
* No reusable `.tscn` prefabs; everything is assembled at runtime from GLB kits and data. **NOT IMPLEMENTED**
* Ragdoll is single-body ("ragdoll-lite"). **PARTIAL**
* Vehicle damage has no mesh deformation or detachable panels. **PARTIAL**
* Interiors are only shop counters and the safehouse room. **PARTIAL**
* First-person mode has no dedicated arms. **PARTIAL**
* PIT and box-in tactics are implemented but were not verified. **PARTIAL**
* Police boats are drivable but are never dispatched. **NOT IMPLEMENTED**
* Gamepad support is untested. **PARTIAL**
* Frame-time spikes occur while populations spawn (see Performance). **PARTIAL**

## Known bugs / rough edges

* There are short frame-time spikes (hitches) when many NPCs or vehicles spawn at once, for example at the start
  of a 4–5 star chase.
* Hard landings from stunt ramps can roll the car (physics, not scripted).
* The Skylark light plane bleeds speed in very steep climbs (simple stall model). The jet was not tested
  automatically.
* An AI taxi takes a moment to pull away after the player boards.
* Burning wrecks also burn out on their own (~22 s). The test confirmed that the fire engine arrives and its crew
  deploys, but it did not separate extinguishing from the fire burning out.
* Godot sometimes prints a harmless "ObjectDB instances leaked at exit" warning (an AudioStreamWAV playback) on
  quit.

## Controls (short)

| Context | Controls |
|---|---|
| On foot | WASD move · Shift sprint · Space jump/climb · C crouch · RMB aim · LMB fire · R reload · X melee · G grenade · Q cover |
| Interact | E interact · F enter/exit/carjack · Tab weapon wheel · M map · T phone · P stats · V camera · F12 photo · Esc pause |
| Admin / save | **F1 admin menu** · F5/F9 quick save/load |
| Car | W/S throttle/brake · A/D steer · Space handbrake · H horn · L lights · N radio · K roof · Q siren · RMB+LMB drive-by |
| Helicopter | Space/C up/down · W/S pitch · A/D roll · Q/E yaw |
| Airplane | Shift/C throttle · W/S pitch · A/D roll · Q/E rudder |
| Boat | W/S throttle · A/D rudder |
| Parachute | Space deploy · A/D steer · W dive · S flare |

## Build result

* All 42 GDScript files load with **no parse errors** (`tools/check.ps1`).
* **35 GLB exports import cleanly** (headless `--import`: no errors, 35/35 `.import` files).
* A normal launch at 1280×720 builds the world in ~1.1 s and reaches free roam in ~3.6 s, then quits cleanly with
  `--quit-after`. No console errors.
* Automated scenarios in `test_harness.gd` that were run successfully in the final pass: `systems`, `misc`,
  `police`, `verify`, `verify2`, `stunt`, `final`, `world`.
* No standalone executable was exported (no export presets). The game runs from the Godot 4.7.2 editor or runtime.
* Git history: baseline → world/kits/player/vehicles → NPCs/traffic/police/HUD/services → FX rewrite →
  parked-car rest state/flooding/stunt ramps → stability fixes → routing/wanted fixes → documentation (final
  commit).

## Major assets created in Blender (via MCP)

| Group | Assets |
|---|---|
| Vehicles (21 GLBs) | compact, sedan, sports (convertible), muscle, SUV, pickup, van, taxi, box truck, police cruiser, ambulance, fire engine, SWAT van, motorcycle, bicycle, speedboat, police boat, utility helicopter, police helicopter, prop plane, jet. All have doors, seats, steering, LOD1, collision helpers, light/seat/exhaust markers and `Mod_*` customisation parts. Plus a wheel-rim kit (5 styles). |
| Characters | rigged male and female human (17 bones, LOD1); hair, beards, hats, glasses, vests, packs, scuba set; parachute canopy |
| Weapons | 17 weapon models with attachment parts; projectiles, pickups, muzzle flash and VFX helpers |
| Buildings | 24 modular facade pieces (office, apartment, brick, shop, industrial); 26 landmarks: houses, shop shell, garage, safehouse, police HQ, hospital, gas canopy, hangar, control tower, parking deck, lighthouse, water tower, crane, pier, elevated rail pieces, train car, container, billboard, stunt ramp, helipad, sunken wreck |
| Street & world props | ~64 street props (lamps, signals, signs, hydrants, benches, bins, fences, barriers, spike strip…), 16 interior props, 19 nature assets (trees with LODs, palms, bushes, rocks, kelp, coral…), 11 animal species, animated airport radar |

In total there are ≈240 distinct authored assets/modules, 671 mesh objects in the `GTA_GODOT` collection tree and
35 GLB files.

## Vehicle roster

| Class | Vehicles |
|---|---|
| Cars | Pico (compact), Meridian (sedan), Vanta GT (sports, convertible), Brawler 440 (muscle), Ridgeline (SUV), Dustcutter (pickup), Hauler (van), Cabbie (taxi), Mule Box Truck |
| Emergency | Enforcer Cruiser (police), Lifeline Ambulance, Blaze Engine (fire), Bulwark Tactical (SWAT) |
| Two-wheel | Wasp 600 (motorcycle), Cruiser Bike (bicycle) |
| Water | Marlin 21 (speedboat), Harbor Patrol (police boat) |
| Air | Kestrel Utility and Skywatch (helicopters), Skylark 172 (prop plane), Stiletto (jet) |

## Weapon roster

| Slot | Weapons |
|---|---|
| Melee | Fists, Field Knife, Ash Bat, Crowbar, Nightstick |
| Handguns | P9 Sidearm, Magnus .44 |
| SMG | Stinger SMG |
| Shotguns | Breacher 12, Sweeper A12 |
| Rifles | AR-7 Vandal, Kestrel C Bullpup, Longbow DMR |
| Sniper | Widow LR |
| Heavy | Hornet Launcher (RPG), Thumper GL |
| Thrown | Frag Grenade, Firebottle (molotov) |

## Map regions

| Area | What is there |
|---|---|
| Financial Core | Cinder Tower with rooftop helipad and elevator |
| Midtown | Mercy General Hospital |
| Civic Square | CBPD HQ, parking deck, train station |
| Market Street | shops, gun shop, barber |
| Lantern Park | park, second train station |
| Maple Flats / Sandy Row | houses and the safehouse |
| Bayfront | hotels and promenade |
| Ironworks | warehouses, gas station, Torque Bay Customs, shooting range |
| Harbor Docks & Marina | cranes, containers, piers with boats |
| Coral Beach | beach, pier to the Ember Point Lighthouse island |
| Cinder Field Airport | runway, hangar, tower with animated radar |
| Ember Hill | dirt track, viewpoint, wildlife |
| Sea floor | Sunken Trawler wreck |
| Loop Line | elevated train around the city |

## Wanted / police implementation

* **Crime bus:** `G.report_crime(kind, pos, severity, culprit)`. Only crimes that the player caused count.
* **Detection:** a crime counts when police see it directly (on foot or in a car, with a LOS raycast) or when a
  civilian witness phones it in (3–5 s on the phone). Killing or knocking the witness down before the call ends
  stops the report. Loud crimes (gunfire, explosions) can be reported by people who only heard them.
* **Escalation:** heat thresholds map to 0–5 stars.

| Stars | Response | Escape time while unseen |
|---|---|---|
| 1 | 1 cruiser; non-lethal, officers try to arrest you | 14 s |
| 2 | 2 cruisers; still non-lethal | 22 s |
| 3 | 3 units; lethal force, roadblocks, helicopter with searchlight | 32 s |
| 4 | 4 units; SWAT vans and tactical officers, spike strips, two roadblocks | 44 s |
| 5 | 5 units; mixed cruisers and SWAT vans, roadblocks with spikes, helicopter | 58 s |

* **Pursuit vs search:** after 1.5 s unseen the police switch to *search* around the last known position, and the
  stars flash. The escape timer only advances while you are unseen. It runs faster if you change vehicle or
  outfit, or hide underwater. Being spotted again resets it.
* **Police AI:** cars route over the road grid and drive straight at you when close. They attempt PIT and box-in
  manoeuvres, officers dismount when you are slow or on foot, and on-foot officers use cover-seeking combat AI.
  Spike strips pop tyres, and civilian traffic pulls aside for sirens.
* **Busted:** standing still near an officer at 1–2 stars gets you arrested. You respawn at CBPD HQ, pay bail and
  lose the stars.

## Performance notes

* RTX 5070, 1280×720, V-Sync on, 60 fps cap. The city runs at 45–60 fps. A 4–5 star chase with ~60–75 vehicles
  runs at ~43–58 fps.
* Draw calls are ~1,000–3,600 per frame and there are ~0.6–1.6 M primitives on screen. The figures come from
  `Performance` monitors in the `perf`/`verify2` scenarios.
* Measures in place: MultiMesh props, LOD1 meshes, visibility ranges, shared materials, pooled VFX, AI simulation
  tiers, population caps, and frozen parked or abandoned cars (no suspension raycasts while parked).
* Remaining issue: frame-time spikes when NPCs or vehicles spawn (character setup and material assignment run on
  the main thread).
* GPU safety (spec §3A) was followed for every run: `nvidia-smi` checked first, one instance at a time, a hard
  `--quit-after` plus an OS timeout, 1280×720, and no uncapped loops. No uncapped benchmark was run. Blender work
  used only Workbench/EEVEE viewport captures.

---

## Claude Fable 5.2 GTA Session Metrics

```text
Project: Godot GTA sandbox
Run/session identifier: run-20261109-215741 (Claude Code session f7e674d9-2f56-4cc6-af92-015da2d4e3f7);
  earlier aborted segment run-20261109-214843 (session f60740c6-1a86-41e3-b52a-9f57ee880252, 2 requests, no project work)
Working-directory full path: G:\YouTube\Fable 5.2 Effort Test GTA\Extra
Start timestamp and timezone: 2026-11-09T21:57:41.742+01:00 (Central European Standard Time, UTC+01:00)
End timestamp and timezone: 2026-11-10T06:00:05.188+01:00 (Central European Standard Time, UTC+01:00)
Elapsed wall-clock time (HH:MM:SS): 08:02:23
Elapsed minutes: 482.39
Elapsed hours: 8.040
Known pauses / resumed segments:
  - Pause 1: 2026-11-09 23:29:07 -> 23:44:58 (+01:00), 00:15:51 / 15.86 min - a turn ended on an API error;
    resumed after the user's "Try again".
  - Pause 2: 2026-11-10 01:19:45 -> 05:48:38 (+01:00), 04:28:53 / 268.88 min - a turn ended on an API error;
    resumed after the user switched the model (/model claude-opus-5-5) and wrote "continue".
  - Wall-clock excluding these two idle pauses: 03:17:38 (197.65 min, 3.294 h). Derived from session-log
    timestamps; active time was not tracked separately.
  - Earlier aborted segment: 2026-11-09 21:48:43 start file / 21:55:53-21:55:59 (+01:00) requests, before this run's
    start; not included in the elapsed time above.

Requested model: Claude Fable 5.2
Actual model identifier(s): claude-fable-5-2 (231 requests: run start -> 2026-11-10 01:19 +01:00, plus the
  aborted segment); claude-opus-5-5 (35 requests from 2026-11-10 05:49 +01:00 after the user's /model switch;
  covers the final verification, documentation and this report). 2 failed requests are logged as <synthetic>
  API-error entries with zero usage.
Thinking/effort setting (if exposed): request params show effort = "xhigh", thinking = "adaptive",
  max_tokens = 128000 for every request of both models; service_tier = standard, speed = standard,
  inference_geo = global for all requests.
Input tokens (state whether uncached or inclusive): 536 uncached (input_tokens = tokens after the last cache
  breakpoint; exclusive of cache reads/writes)  [fable-5-2: 464 | opus-5-5: 72]
Cache-read tokens: 105,125,654  [fable-5-2: 93,540,054 | opus-5-5: 11,585,600]
Cache-write tokens: 2,251,127  [fable-5-2: 1,915,688 | opus-5-5: 335,439]
Cache-write duration breakdown (if exposed): 1-hour writes 2,251,127; 5-minute writes 0
Output tokens: 875,401  [fable-5-2: 808,335 | opus-5-5: 67,066]
Thinking/reasoning tokens (included / separate / unavailable): included in output - 323,828 reported in
  output_tokens_details.thinking_tokens (fable-5-2: 297,914 | opus-5-5: 25,914); not added again.
Deduplicated total tokens: 108,252,718 (input + cache-read + cache-write + output)
  [fable-5-2: 96,264,541 | opus-5-5: 11,988,177]
Usage source and observation cutoff: Claude Code local session logs for this project
  (~/.claude/projects/G--YouTube-Fable-5-2-Effort-Test-GTA-Extra/<session>.jsonl), assistant-message usage
  metadata only, deduplicated by message id (streamed duplicates of a message carry identical usage; each
  usage has a single iteration whose counts equal the top-level counts). No sub-agents/sidechains were used.
  Observation cutoff: last log record 2026-11-10T05:07:24Z.
Unmeasured work / limitations: requests after the cutoff (the last report edits, the final git commit and the
  final chat response) are not included. The end_time.txt timestamp (06:00:05 +01:00) was taken just before the
  report was written, so the token cutoff is a few minutes later than the end time. Prices are computed from
  the logged counters, not from an account bill.

Token-only API-equivalent cost (USD): $92.06 - ALL project tokens priced at Claude Fable 5.2
  Standard rates (pricing basis chosen by the user; the 11,988,177 tokens that were actually served by
  claude-opus-5-5 after the /model switch are priced as if they were Fable 5.2 tokens)
Per-model subtotals (if applicable): not used - single pricing basis (Fable 5.2) for every token.
  Cost by category: input $0.0043 + cache-read $21.0251 + 1h cache-write $36.0180
  + 5m cache-write $0.0000 + output $35.0160 = $92.06
  (aborted segment $0.43 included; tokens served by claude-fable-5-2 = $81.70,
  tokens served by claude-opus-5-5 but priced at Fable rates = $10.37)
Official pricing source, verification date and comparison tier: https://platform.claude.com/docs/en/about-claude/pricing
  and https://platform.claude.com/docs/en/build-with-claude/prompt-caching, read 2026-11-10;
  Standard Claude API (first-party, global inference, no Batch / Fast mode).
Rates and formula used (USD per million tokens, claude-fable-5-2, Standard API, applied to all tokens):
  input 8.00 | 5m cache write 10.00 | 1h cache write 16.00 | cache read 0.20 | output 40.00
  cost = (input*8.00 + cache_read*0.20 + cw_5m*10.00 + cw_1h*16.00 + output*40.00) / 1e6
Cache/context/tier adjustments or explicit assumptions: the full context window is billed at standard rates
  (no long-context surcharge for these models); inference_geo = global, so no 1.1x data-residency multiplier;
  thinking tokens are part of output_tokens; total input per request = input + cache_read + cache_write
  (per the caching documentation).
External tool/API fees (known / excluded / unknown): none known. No server-side web search was used
  (server_tool_use web_search_requests = 0). Blender, Godot and the documentation page fetches ran locally /
  in the built-in browser at no API fee.
Measured / estimated / unavailable, with reasons: elapsed time MEASURED (OS timestamps); pauses DERIVED from
  log timestamps; tokens MEASURED from logged usage up to the cutoff; cost CALCULATED from the measured tokens
  at the verified Claude Fable 5.2 list prices for ALL tokens (user-chosen basis, including the Opus-served share). The work after the cutoff is unmeasured (small).

Blender MCP server/tool namespace actually used: blender-gta-extra (mcp__blender-gta-extra__*:
  execute_blender_code, look, get_addon_status, get_scene_info)
Blender host: localhost
Blender port: 9880
Blender master file: GodotFable5.2GTAExtra.blend
Verified full path of master file: G:\YouTube\Fable 5.2 Effort Test GTA\Extra\GodotFable5.2GTAExtra.blend
  (bpy.data.filepath checked through MCP; saved, not dirty; backup in _blender_backups/)
Approximate number of major Blender assets created: ~240 distinct assets/modules (21 vehicles + wheel kit,
  2 rigged humans + ~24 clothing/hair parts + parachute, 17 weapons, 24 facade modules, 26 landmarks, ~64 street
  props, 16 interior props, 19 nature assets, 11 animal species, radar, VFX/pickup helpers); 671 mesh objects;
  35 GLB exports
```
