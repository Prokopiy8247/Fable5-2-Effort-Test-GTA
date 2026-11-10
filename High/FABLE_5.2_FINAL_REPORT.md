# Fable 5.2 final report — Marlow Bay (Godot + Blender MCP GTA-style sandbox)

## What was built

An original, missionless open-world crime sandbox called **Marlow Bay**: a compact (~600 × 600 m) coastal
city island you can explore on foot, by car, motorcycle, boat, helicopter and airplane, with traffic,
pedestrians, a 0–5 star police system, shops, a safehouse, weather, day/night and a benchmark menu.
Everything visible is authored through the Blender MCP connection (173 asset roots, 166 exported GLBs) and
assembled by ~13,200 lines of GDScript. Art direction: bright flat-shaded low-poly, no image textures.

The game starts in free roam inside the safehouse. There is no mission system, no quest markers, no story.

## Build result

- `tools/check.sh` (headless parse of every script): **0 errors**.
- Headless and windowed boot: clean (only an engine "ObjectDB instances leaked at exit" notice in headless).
- 16 scripted runs of the real game passed without script errors after fixes
  (boot, tour, drive, combat, wanted, air, water, ui, night, systems, chute, flows, flows2, perf, assets, final).
- No export/packaged build was produced; the project runs from the Godot 4.7.2 editor or `--path`.

## What works (verified in scripted runs)

- On foot: third-person movement, sprint/stamina, jump, crouch, ladders, aim camera, fall damage, death and
  hospital respawn, arrest and police-station respawn.
- Driving: raycast-suspension cars (54 km/h in 4 s in the sedan test), steering, handbrake, enter/exit,
  carjacking with the driver pulled out, traffic that follows lanes and signals, parked cars.
- Flying and boating: helicopter take-off and forward flight, plane take-off and climb, speedboat at 56 km/h,
  parachute deploy/steer/glide from 160 m.
- Combat: rifle kill on an NPC, rocket, grenade, melee hit, pedestrians cowering when aimed at, cover attach,
  weapon wheel, weapon purchase / ammo / all attachments / finishes.
- Police: stars, officers and cruisers arriving, pursuit ↔ search, escape after staying unseen, BUSTED.
- World: 8 districts, day/night with lit windows and pooled street lights, rain/fog/storm with wet roads,
  swimming and diving with breath, monorail ride, wildlife spawning, shooting range start.
- Services and UI: HUD, rotating minimap, full map with waypoint, gun shop interior with clerk, Torque House
  (all 103 customisation option paths), clothing, barber, food, safehouse garage store/retrieve, save/load,
  pause/stats/settings, F1 benchmark menu.
- Performance: 60 fps (capped) in all four sampled districts and during a 5-star pursuit at 1280×720;
  minimum sample 47 fps; ~1,630 draw calls; ~156 MB static memory, ~138 MB video memory reported by the engine.

## What is partial

See `FEATURE_MATRIX.md` for the full table. The main ones:

- Implemented but **not exercised or visually verified** in a run: first-person view, vault, dodge roll, heavy
  melee and block, blind fire and corner wrap in cover, drive-by shooting, scope overlay, bicycle, jet,
  tyre puncture and glass break, store robbery, phone actions, emergency vehicles, time trial, stunt jumps,
  precision landing, radio audio, controller input.
- Roadblocks and spike strips are coded but did not trigger during the test window.
- The taxi was called and arrived in one run; the full paid ride and skip were not completed in a run.
- Wildlife spawned (13 animals) but fleeing and predator attacks were not observed.
- Ragdoll is a tumbling single body with a limp pose. Animation is procedural only.
- Audio is synthesised (72 clips) and wired up, but was never listened to.

## Not implemented

Lane changes mid-block, bullet penetration, convertible roofs, trunk/hood interaction, liveries, interiors
beyond the gun shop / mod garage / safehouse, elevators and automatic doors, tattoo shop, per-entity `.tscn`
scenes (the world is assembled in code from GLBs).

## Known bugs / rough edges

- Shop-sign letters (Blender text meshes) are thick and can look cramped at grazing angles.
- Teleporting or spawning a vehicle onto the player can push the player under the map; a safety net lifts
  the player back to the surface.
- Boats and the pier use box collision, so you cannot swim under the pier.
- Traffic that gets stuck is reversed or despawned rather than re-routed.
- Vehicles pass through traffic-light poles and light street furniture by design (furniture is knocked over).

## Controls

On foot: WASD, Shift sprint, Space jump/vault/parachute, C crouch+stealth, Q cover, RMB aim, LMB fire,
R reload, Tab weapon wheel, 1–8, F enter/exit, E interact, V first person.
Vehicles: WASD, Space handbrake, H horn, L lights, G siren, `,` `.` radio, B look back, T flip.
Helicopter: W/S pitch, A/D yaw, Q/E roll, Space/C up/down. Plane: W/S throttle, A/D roll, Q/E rudder,
Space/C pitch. Menus: M map, P phone, Esc pause, **F1 benchmark menu**, F5/F9 save/load, F12 photo mode.

## Map regions

Downtown, Midtown Market, Palm Court + Founders Park, Ironworks, Bayfront / Coral Beach, Port Marlow,
Signal Hill, Marlow Airfield, plus Lighthouse Rock and a dive-able shipwreck offshore.
Locations: safehouse, police station, Bayside Medical, Brass & Bolt Arms, Torque House, Fuelio gas,
Threadline, Fade Room, Bite Box, central parking, Skyline stations, marina pier, shooting range.

## Vehicle roster (21, all Blender-authored, distinct meshes)

Pico (compact), Marlow (sedan), Vanta GT (sports), Brawler (muscle), Ridgeback (SUV), Drover (pickup),
Hauler (van), Cabbie (taxi), Interceptor (police), Bulwark (tactical), Lifeline (ambulance), Blaze Engine
(fire truck), Freightliner (box truck), Wasp 600 (motorcycle), City Bike, Skimmer (speedboat), Harbor Patrol,
Dragonfly (helicopter), Skywatch (police helicopter), Kestrel (prop plane), Arrow J1 (jet).

## Weapon roster (16 + fists)

Knife, baseball bat, crowbar, P9 pistol, Bulldog .50, Viper SMG, pump shotgun, Riot Auto-12, AR-7 rifle,
tactical carbine, marksman rifle, Longshot sniper, rocket launcher, Thumper grenade launcher, frag grenade,
fire bottle. Attachments: suppressor, extended magazine, flashlight, optic, foregrip, 7 finishes.

## Wanted / police implementation

Heat-based 0–5 stars. Crimes are known immediately only if an officer sees them or the crime is against
police; otherwise civilians who see it start a phone call that reports it if they finish, and unseen
gunfire produces a delayed 1-star "shots reported". Pursuit while any officer, cruiser or helicopter has
line of sight; otherwise Search around the last known position with flashing stars, a shrinking escape bar
and an escape time of 16–60 s by level. Dispatch by level: cruisers (1–2), + helicopter and roadblocks (3),
+ tactical van and helicopter gunner (4), more of everything (5). Cruisers route over the road graph, chase
directly with PIT/ram/box-in logic when they see you, and crews dismount. Officers arrest at 1–2 stars if
you are unarmed and cornered (BUSTED), otherwise shoot.

## Major Blender assets (all created through MCP)

21 vehicles + 5 wheel/rim meshes, 2 rigged characters with 22 attachments each, 17 weapon/projectile models
with attachment parts, 7 façade kit modules, 42 buildings (towers, apartments, shop rows, houses, warehouses,
gun shop, mod garage, safehouse, police station, hospital, gas station, hangar, terminal, control tower,
parking deck, lighthouse, station), 54 street props, 7 pickups, parachute canopy, 14 nature pieces, 7 animals.

## Performance notes

Frame cap 60 with V-Sync; GPU utilisation stayed at 0–13 % during tests. Static props are MultiMeshes,
dynamic props are pooled (max 34 rigid bodies), particles and lights are pooled and bounded, NPCs and traffic
run in distance tiers. No uncapped FPS measurement was taken (not needed, and avoided for GPU safety).

## Claude Fable 5.2 GTA Session Metrics

Project: Godot GTA sandbox
Run/session identifier: run-20261109-215733 (Claude session a453750e-3bbc-4b05-85c1-f01dcace680a)
Working-directory full path: G:\YouTube\Fable 5.2 Effort Test GTA\High
Start timestamp and timezone: 2026-11-09T21:57:33.920+01:00 (Central European Standard Time)
End timestamp and timezone: 2026-11-10T00:16:38.030+01:00 (Central European Standard Time)
Elapsed wall-clock time (HH:MM:SS): 02:19:04 (measured from the two OS timestamps)
Elapsed minutes: 139.1
Elapsed hours: 2.32
Known pauses / resumed segments: one idle gap of 1056 s (17 min 36 s) from 23:27:53 to 23:45:29 local time, when the turn had stopped and the session waited for the user's "Try again"; identified from consecutive timestamps in the session log. Wall-clock minus that gap = 02:01:28 (derived, not separately tracked active time). Single segment otherwise.

Requested model: Claude Fable 5.2
Actual model identifier(s): claude-fable-5-2 (all 134 main-session requests); one delegated web-fetch subagent ran on claude-haiku-5-5 (2 requests)
Thinking/effort setting (if exposed): effort "high" as selected for this session; no separate thinking-token counter exposed
Input tokens (state whether uncached or inclusive): 270 (uncached only; excludes cache reads and cache writes)
Cache-read tokens: 70,932,068
Cache-write tokens: 756,683
Cache-write duration breakdown (if exposed): 1-hour: 756,683; 5-minute: 0
Output tokens: 567,685
Thinking/reasoning tokens (included / separate / unavailable): not reported separately; treated as included in output tokens (not independently confirmed)
Deduplicated total tokens: 72,256,706 (input + cache-read + cache-write + output, one record per message id)
Usage source and observation cutoff: local session log for this exact session (`usage` metadata per assistant message, deduplicated by message id, largest snapshot kept); cutoff = last logged request at 2026-11-09T23:16:20.832Z UTC
Unmeasured work / limitations: the request that produced the final chat message (and this metrics step's own response) is after the cutoff. Delegated subagent (claude-haiku-5-5): input 4, cache-read 3,197, cache-write 32,967 (5-minute), output 2,362 — counted separately, not in the totals above.

Token-only API-equivalent cost (USD): $49.00 (Fable 5.2 main session, measured usage x verified standard rates)
Per-model subtotals (if applicable): claude-fable-5-2 $49.00; claude-haiku-5-5 subagent not priced (its rates were not verified; ~39k tokens, negligible)
Official pricing source, verification date and comparison tier: https://platform.claude.com/docs/en/about-claude/pricing, fetched 2026-11-10, Standard Claude API tier (log reports service_tier "standard")
Rates and formula used: input $8.00, 1-hour cache write $16.00, 5-minute cache write $10.00, cache read $0.20, output $40.00 per million tokens; cost = sum(tokens x rate) / 1,000,000 = (270 x 8 + 756,683 x 16 + 70,932,068 x 0.20 + 567,685 x 40) / 1e6
Cache/context/tier adjustments or explicit assumptions: no long-context premium applies to Fable 5.2 per the pricing page; cache-read rate is the page's Fable-specific $0.20; the three input categories are treated as mutually exclusive per the prompt-caching documentation
External tool/API fees (known / excluded / unknown): none known; Blender and Godot are local; web fetch fees unknown and excluded
Measured / estimated / unavailable, with reasons: time measured; tokens measured from the session log up to the cutoff; cost calculated from measured tokens and fetched official rates (a benchmark equivalent, not a bill)

Blender MCP server/tool namespace actually used: blender-gta-high (mcp__blender-gta-high__*)
Blender host: localhost
Blender port: 9879
Blender master file: GodotFable5.2GTAHigh.blend
Verified full path of master file: G:\YouTube\Fable 5.2 Effort Test GTA\High\GodotFable5.2GTAHigh.blend
Approximate number of major Blender assets created: 173 asset roots (166 exported GLBs + 7 kit modules), 661 objects

