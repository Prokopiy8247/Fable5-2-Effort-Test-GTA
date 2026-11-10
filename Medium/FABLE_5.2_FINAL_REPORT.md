# Port Cinder — Claude Fable 5.2 Godot GTA benchmark (Medium) — final report

## What was built

An original, missionless GTA-style free-roam sandbox in Godot 4.7.2 (Forward+, GDScript only). The game boots straight
into the safehouse on **Port Cinder**, a compact ~600 × 600 m island city generated in code from ~150 GLB assets that
were authored in Blender through the Blender MCP connection on `localhost:9878`. No external models, textures, audio
or add-ons are used; all sound is synthesised at start-up.

Art direction: flat-shaded low-poly coastal city with solid colours, chamfered silhouettes, 3D sign lettering and
emissive night windows.

## What works (see `FEATURE_MATRIX.md` for the full, honest table)

- On foot: run/sprint/crouch/jump, vault/mantle, ladders, cover with blind fire, stealth with takedowns, swimming and
  diving with breath/scuba, parachute, first-person toggle, melee and 15 weapons with attachments.
- Vehicles: 15 land vehicles (incl. motorcycle and bicycle), 2 boats, 2 helicopters, prop plane and jet; hijacking,
  drive-bys, damage/smoke/fire/explosions, tyre punctures, repair and a full customisation garage whose upgrades change
  the physics.
- City life: lane-graph traffic that obeys signals, pedestrians with panic and witness behaviour, gang turf, wildlife,
  an elevated metro you can ride, taxis with destination choice and trip skip, ambulance / fire-engine dispatch.
- Police: witnessed crimes, 0–5 stars, pursuit vs search with line of sight and a growing search area, patrol and
  tactical dispatch, roadblocks, spike strips, helicopter, arrest ("BUSTED") and death/respawn.
- Systems: shops and economy, clothing/barber, safehouse with wardrobe/bed/garage, phone, map with waypoint and GPS
  line, day/night, five weather states, save/load, seven use-based skills, shooting range and other optional
  activities, and an F1 benchmark menu covering every item the specification lists.

## What is partial or missing

- Ragdolls are procedural poses; no door/trunk animation, convertible roofs, mesh deformation or glass breakage.
- Only the safehouse, the mod garage bay and the hangar have interiors; shops are used from their door markers.
- No traffic lane changes, no officers commandeering cars, no tattoo shop, no liveries, no wet-surface rendering.
- PIT/boxing tactics, the emergency-service work cycle, stunt jumps, time trial, boat race, photo mode, the dodge roll,
  aircraft landings and shark attacks are implemented but were **not** exercised by an automated scenario.
- Audio could not be listened to in automated runs.

## Validation actually performed

All checks were scripted (simulated input + state assertions + screenshots in `screenshots/`); the game has not been
hand-played. Final regression sweep results are recorded at the end of this file.

## Known bugs / rough edges

- Engine log shows `Lambda capture … was freed` when a delayed callback outlives a despawned object (guarded, harmless)
  and one navmesh-bake message at start-up.
- Police vehicles can wedge themselves in cluttered industrial yards; they reverse or deploy officers on foot.
- Flight and handling values are first-pass arcade tuning.

## Controls

```text
WASD move / drive      Mouse look, RMB aim, LMB fire or punch     Shift sprint     Space jump / climb / handbrake
C crouch   Ctrl stealth   Q cover   X heavy melee   Alt block   R reload   G grenade   Tab weapon wheel   1-8 classes
F enter / exit / hijack    E interact    H horn   J siren   L lights   N radio   B flip vehicle   Z look back
V first / third person     M map    P phone    I status    Esc pause    F5 / F9 quick save / load    F1 benchmark menu
Helicopter: Space up, Ctrl down, W/S pitch, A/D yaw, Q/E roll
Airplane:   Shift / Ctrl throttle, S pull up, W nose down, A/D roll, Q/E rudder, Space wheel brake
Parachute:  Space in free fall, A/D steer, S flare          Swim: Ctrl dive, Space surface
```

## Build result

Project imports and runs with Godot 4.7.2 stable; all 29 GDScript files load; no export template build was made.

## Major Blender assets (all authored through MCP, exported as GLB)

- **Characters:** rigged human with male/female bodies and 14 swappable parts (hair ×4, beard, cap, beanie, police cap,
  helmet, glasses, vest, parachute pack, scuba set, jacket).
- **Vehicles (22) + 5 wheel styles + 6 mod parts per car.**
- **Weapons (16 models) with suppressor / magazine / flashlight / optic / grip parts.**
- **Wildlife (7):** deer, dog, rabbit, cow, seagull, fish, shark (separate legs / wings / tails for animation).
- **Buildings and structures (44):** 3 towers, office, hotel, bank, 6 shops, 3 apartments, 4 houses, 2 warehouses,
  factory, police station, hospital, fire station, terminal, safehouse interior, mod garage, hangar, gas station,
  parking garage, metro station, track kit, pier, lighthouse, control tower, crane, container, silo, billboard, water
  tower, gazebo, lifeguard tower.
- **Props (58):** signals, lamps, signs, barriers, benches, bins, hydrant, bus stop, fences, crates, barrels, ladders,
  stunt ramp, pickups, parachute canopy, trees, palms, rocks, wrecks, coral and more.

## Vehicle roster

Halcyon Sedan, Pip Hatch, Vireo GT (sports), Brawler 427 (muscle), Ridgeback SUV, Dusty Hauler (pickup), Courier Van,
Cinder Cab, Police Cruiser, Ambulance, Fire Engine, Tactical Carrier, Box Truck, Hornet 650 motorcycle, Commuter Bike,
Marlin Speedboat, Patrol Dinghy, Skylark Helicopter, Police Helicopter, Sparrow Prop Plane, Kestrel Jet, Skyline Metro
(rideable train, not drivable).

## Weapon roster

Fists, Combat Knife, Ash Bat, Crowbar, K9 Pistol, Brute .44, Wasp SMG, Gatekeeper Pump, Riot Auto-12, AR-Vanta,
Courier Carbine, Longview DMR, Hush-90 Sniper, Thumper GL, Ram-7 Launcher, Frag Grenade.

## Map regions

Downtown · Civic North · Larkspur (residential, safehouse) · Signal Hill (park, viewpoint) · Ironside (industrial,
Torque Bay) · Southshore · Saltline Beach · Anchor Docks & marina · Westwood (woodland, wildlife) · Rustyard (gang
turf, shooting range) · Cinder Airfield · Cinder Bay (open water, wreck dive sites).

## Wanted / police implementation

Crimes carry a severity and become known only if an officer sees them or a civilian witness with line of sight finishes
a phone call (or, for gunfire and explosions, an indirect report). Heat converts to stars; assaulting or killing
officers sets minimum levels. While any unit (foot, vehicle, helicopter) has line of sight the state is **pursuit**;
otherwise it is **search** around the last known position with a growing radius, blinking stars and radar cones, and
the escape timer (16–70 s by level) only runs while unseen. Switching vehicle or appearance unseen shortens it. Dispatch
scales from one cruiser to four cruisers plus two tactical carriers; 3★ adds a helicopter and roadblocks, 4★ adds spike
strips and helicopter gunfire. Officers arrest at 1★ if you stand still and shoot from 2★.

## Performance notes

Frame-capped at 60 fps (V-Sync + `Engine.max_fps`). Capped measurement, 1280×720, downtown, 4★ chase in a storm:
60.0 fps average, worst frame 30 ms, ~1 400 draw calls, ~395 k primitives. No uncapped measurement was taken.

## Final regression sweep (automated, 60 fps cap, 1280×720, one instance at a time)

| Scenario | Result |
|---|---|
| parse (29 scripts) | pass |
| basic (walk, enter, drive, steer, brake, exit) | 11/11 |
| combat (rifle, melee, rocket vs car, reload, weapon wheel) | 8/8 after the last tuning pass |
| wanted (unwitnessed ignored, witness call, dispatch, helicopter, hide to escape, busted) | 12/12 |
| vehicles (15 land vehicles, helicopter, plane take-off, boat, swim) | 14/14 |
| extras (parachute, dive, metro, taxi + skip, wildlife, shooting range) | 18/18 |
| menus (shops, workbench, clothes, mods, garage, map, phone, pause, save/load) | 20/20 |
| misc (hijack, drive-by, roadblock, spikes, cover, mantle, takedown, services, ladder, robbery, gang, sleep) | 22/22 |
| city / look / perf | traffic 15, pedestrians 16 downtown; 60.0 fps capped |

## Claude Fable 5.2 GTA Session Metrics

```text
Project: Godot GTA sandbox
Run/session identifier: run-20261109-214834 / Claude Code session 50b5d4e7-5c62-4517-bb45-65ed404d78c4
Working-directory full path: G:\YouTube\Fable 5.2 Effort Test GTA\Medium
Start timestamp and timezone: 2026-11-09T21:57:19.678+01:00 (CET) — first OS clock read by this session
End timestamp and timezone: 2026-11-09T23:57:07.061+01:00 (CET)
Elapsed wall-clock time (HH:MM:SS): 01:59:47
Elapsed minutes: 119.8
Elapsed hours: 2.00
Known pauses / resumed segments: A start_time.txt of 21:48:34 already existed in the run folder when this session
  began (not written by this session; preserved unchanged). Measured from that file the span is 02:08:33.
  One user "Try again" message arrived mid-session; any idle time around it is included, not measured separately.

Requested model: Claude Fable 5.2
Actual model identifier(s): claude-fable-5-2 (main session); one web-fetch subagent for the pricing page (18,898 tokens
  reported by the harness, model and category split not exposed, NOT included below)
Thinking/effort setting (if exposed): not exposed to the session (folder name suggests "Medium"; unverified)
Input tokens (state whether uncached or inclusive): 186 (uncached only)
Cache-read tokens: 41,181,279
Cache-write tokens: 607,476
Cache-write duration breakdown (if exposed): 1-hour: 607,476; 5-minute: 0
Output tokens: 465,199
Thinking/reasoning tokens (included / separate / unavailable): not separately exposed; included in output if counted at all
Deduplicated total tokens: 42,254,140
Usage source and observation cutoff: local Claude Code session log for this session id, usage fields only, de-duplicated
  by (message id, request id), 91 requests; cutoff 2026-11-09T22:57:03Z (23:57:03 local)
Unmeasured work / limitations: the final report edits, final commit and final chat message after the cutoff; the
  web-fetch subagent; the log's field semantics are taken as the raw Anthropic usage fields without independent
  confirmation from the host.

Token-only API-equivalent cost (USD): $36.57 (measured tokens × published rates; estimate of an equivalent, not a bill)
Per-model subtotals (if applicable): claude-fable-5-2 only
Official pricing source, verification date and comparison tier: https://platform.claude.com/docs/en/about-claude/pricing,
  read 2026-11-09, Standard API tier, row "Claude Fable 5.2" (the page shows the display name, not the model id)
Rates and formula used: input $8, 1h cache write $16, cache read $0.20, output $40 per MTok
  (186×8 + 607,476×16 + 41,181,279×0.20 + 465,199×40) / 1e6 = 0.00 + 9.72 + 8.24 + 18.61 = 36.57
Cache/context/tier adjustments or explicit assumptions: no long-context premium (page states 1M context at standard
  pricing); not Fast or Batch tier
External tool/API fees (known / excluded / unknown): none known; local Blender and Godot carry no API fee
Measured / estimated / unavailable, with reasons: time measured (OS clock); tokens measured from the session log up to
  the cutoff; cost calculated from those measurements and the published price table

Blender MCP server/tool namespace actually used: blender-gta-medium (mcp__blender-gta-medium__*)
Blender host: localhost
Blender port: 9878
Blender master file: GodotFable5.2GTAMedium.blend
Verified full path of master file: G:\YouTube\Fable 5.2 Effort Test GTA\Medium\GodotFable5.2GTAMedium.blend
Approximate number of major Blender assets created: ~150 exported GLB assets (544 objects, 338 meshes in the .blend)
```
