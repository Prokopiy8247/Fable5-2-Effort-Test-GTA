# NEON TIDE: Vesper Bay — Final Report

Claude Fable 5.2 Godot + Blender MCP GTA-style benchmark (Max), project folder `G:\YouTube\Fable 5.2 Effort Test GTA\Max`.

## What was built

An original, missionless GTA-style open-world sandbox in **Godot 4.7.2 (Forward+, Jolt Physics, GDScript)**: a
≈600 × 600 m island city ("Vesper Bay", art direction *sun-bleached low-poly coast, neon after dark*) with eight
districts, traffic and pedestrians, a full 0–5 star wanted system with witnesses, pursuit / search and arrests, 17
weapons, 19 drivable vehicles including helicopters, a plane, a boat and two-wheelers, shops and services, a
safehouse with garage, emergency services, wildlife, stunt jumps, a shooting range, synthesised audio with radio
stations, save / load and a complete admin / benchmark menu. **Every 3D asset was authored through the Blender MCP**
(`blender-gta-max`, localhost:9881, master file `GodotFable5.2GTAMax.blend`) as Python-built low-poly geometry and
exported as GLB; no downloaded, library or AI-generated assets were used.

## How to launch

Open the folder in Godot 4.7.2 and press **F5** (or `Godot_v4.7.2-stable_win64.exe --path "G:\YouTube\Fable 5.2 Effort Test GTA\Max"`).
The game starts directly in free roam outside the safehouse on Coral Beach, next to the player's teal Meridian sedan.
No exported executable was produced (none was required); the project imports with 0 errors and runs from the editor
or the command line. Automated checks: `tools/run_godot.ps1 -Mode window -UserArgs "--gta-test=<scenarios>"`.

## Controls (full table in DEVELOPMENT.md §6)

WASD + mouse move / look · Shift sprint · Space jump / vault / climb · C crouch · Q cover · E interact · F enter /
exit / hijack / ride · LMB fire / punch · RMB aim / block · MMB or X heavy melee / takedown · R reload · G grenade ·
Tab weapon wheel · 1–8 weapon slots · V camera · in vehicles W/S/A/D, Space handbrake, H horn, L lights, J siren,
B look back, , / . radio · aircraft W/S pitch, A/D roll, Q/E yaw, Shift/Ctrl collective / throttle · Space in free
fall: parachute · M map · P phone · Esc pause · F1 admin / benchmark menu · F3 FPS · F5 / F9 quick save / load ·
F8 photo mode.

## Map regions

| District | What is there |
|---|---|
| Lookout Hill (NW) | winding hill road, pine and oak woods, radio tower with a climbable ladder (70 m base jump), viewpoint, deer, rabbits, coyotes at night |
| Downtown | office towers, Meridian Square (fountain, statue), VBPD headquarters with rooftop police helicopter, Vesper General hospital, parking garage |
| Ironworks | warehouses and yards, Ironworks shooting range, fire station, Torque House Customs, scrapyard stunt jump, water tower |
| Vesper Airfield (E) | runway, taxiway, hangar, control tower, terminal, helipads, parked planes, two stunt jumps |
| Palm Row | suburban houses with gardens and fences, Palm Park with gazebo, dogs and cats |
| Midtown | storefront blocks: Bulwark Arms (weapons + gunsmith), Threadline (clothing), Fade Factory (barber), QuikNook 24 |
| Coral Beach | beach and promenade, pier with ferris wheel, lighthouse, The Hideout (safehouse), hotel and motel, Gull Gas, beach stunt jump, gulls |
| Saltline Docks | marina with speedboats, boathouse, ZipCab depot, port with crane and containers |
| Sea | reefs, kelp, a sunken boat and car, underwater treasure, fish schools and a shark |

## Vehicle roster (all Blender models)

Cars: Pico (compact), Meridian (sedan), Vanta GT (sports), Brawler (muscle), Ridgeback (SUV), Mule (pickup), Hauler
(van), ZipCab (taxi). Service: Interceptor (police), Lifeline (ambulance), Blazeguard (fire engine), Packmaster
(box truck), Bulwark (SWAT truck). Two wheels: Wasp 600 (motorbike), BMX. Water: Marlin (speedboat). Air: Dragonfly
(civil helicopter), Skywatch (police helicopter with searchlight and gunner seats), Kestrel (prop plane).
18 Torque House body parts (spoilers, hoods, roof parts, bumpers, skirts, exhausts, 5 rim styles) mount on cars.

## Weapon roster

Fists, Combat Knife, Baseball Bat, Crowbar, Nightstick, P9 Pistol, .44 Longhorn revolver, Wasp SMG, Pump Shotgun,
Riot Auto-12, AR-7 Assault Rifle, Vector Carbine, Ranger DMR, Longbow Sniper, Rocket Launcher, Thumper grenade
launcher, Frag Grenade. Attachments: suppressor (small / large), extended magazine, reflex sight, 4× scope, foregrip,
flashlight; 9 finishes.

## Wanted level and police

- Crimes (gunfire, assault, murder, carjacking, theft, hit-and-run, explosions, assaulting / killing officers,
  robbery, threatening officers) only count when **witnessed**: officers who see or hear them report at once,
  civilians must finish a phone call (kill or scare the caller to stop it).
- **0–5 stars** by accumulated heat; shooting alone never goes beyond 2 stars.
- **Pursuit** while any officer (or the helicopter) sees you; **search** around the last known position (shown on
  the minimap) when hidden; the level cools down after 20–62 s unseen. A fresh vehicle works as a disguise until an
  officer gets close; a Torque House respray while unseen clears the level.
- Response escalates: 1★ one patrol car trying to **arrest** (stand still near an officer → BUSTED, released at
  VBPD HQ with a fine and half the ammo confiscated), 2★ more cars and return fire, 3★ lethal force, roadblocks,
  helicopter with searchlight, 4★ SWAT trucks, spike strips, helicopter gunner, 5★ maximum units and aggression.
- Units drive on the road network with sirens (traffic pulls over), chase directly when they see you, dismount to
  fight or arrest, search on foot, and get back in when you drive off. Police beat officers stand outside HQ.

## Major assets created in Blender

311 GLB assets in `gta/generated/models/`, all built by Python through the Blender MCP and checked with the MCP
`look` tool before export:

| Family | Count | Contents |
|---|---|---|
| Building kits | 72 | office, apartment, storefront, industrial and house modules, roof props, police / hospital / hotel / fire-station / cinema fronts, 19 neon signs, 5 billboards |
| Landmarks | 25 | 4 enterable shops, safehouse, Torque House, gas station, hangar, control tower, terminal, radio / water towers, lighthouse, crane, parking garage, fountain, statue, viewpoint, gazebo, boathouse, ferris wheel, rail kit, basketball court |
| Props and nature | 126 | street furniture and signals, fences, yard and industrial props, beach / pier props, trees, palms, bushes, rocks, grass, underwater set, activity props (ramps, targets), debris |
| Vehicles | 37 | 19 vehicles + 18 mod parts |
| Characters | 2 | male and female bodies on one 19-bone rig with 28 accessories and 51 animation clips |
| Weapons and held items | 28 | 17 weapons and projectiles, 8 attachments, phone, parachute canopy |
| Animals | 9 | seagull, dog, cat, deer, rabbit, coyote, two fish, shark |
| Pickups | 12 | health, armour, ammo, cash, parachute, scuba, snack, repair, bribe, crate, treasure |

Plus 174 synthesised sounds (Python / numpy, `tools/audio/gen_audio.py`) including five original radio stations.

## What works (details in FEATURE_MATRIX.md)

All systems listed above work and are covered by automated scenarios. Final regression on the final build:
145 checks in 22 scenarios (smoke, walk, drive, look, peds, traffic, traffic soak, police, ui, shops, services,
ragdoll, moves, roster, air, misc, audio, extras, landmarks, night, chaos, bench), **0 failures, 0 script errors**.

## What is partial or missing

- **Not implemented**: monorail / train (rail kit pieces exist in Blender, no train or track in the game); jet,
  dinghy and police-boat models; races.
- **Partial**: building interiors (shops, safehouse, Torque House and hangar only); combat AI has no cover-graph
  search; controller bindings exist but were not tested with a pad.

## Known bugs / rough edges

- Ragdoll joints are cone joints without hinge limits: limbs can occasionally fold unnaturally.
- Radio stations loop every ~40 s; synthesised voices (screams, crowd) are clearly synthetic.
- Boot takes about 10 s (the whole city is generated at start).
- Traffic AI can occasionally queue for a long time behind an obstacle it cannot pass; it is removed when out of sight.

## Performance notes

- RTX 5070, 1600×900 window, medium preset, V-Sync + 60 FPS cap: benchmark tour through 10 viewpoints on the
  final build **60.0 FPS average, 1% low 60 FPS, worst frame 16.7 ms** (`user://benchmark.txt`; an earlier run
  before the streaming fix had 1% lows of 20 FPS).
- Five-star night storm firefight with 63 vehicles and 57 NPCs: 59.6 FPS average, 45 FPS minimum.
- Techniques: one palette-atlas shader for nearly all surfaces, merged facade meshes with LOD per building,
  MultiMesh vegetation, NPC simulation tiers, streamed traffic / pedestrians / parked cars (spawn spikes capped),
  async navigation-mesh bake, game-time clock.
- No GPU instability; all automated runs used time limits, a single instance and GPU-load back-off.

## Development notes

- The run was interrupted twice by the account's usage limit (pauses 23:28–23:47 and 01:21–05:50). All work,
  before and after the pauses, ran on Fable 5.2. See `.fable-5.2-gta-runs/run-20261109-215759/`.
- Delegation: 15 asset / audio agents (Blender work shared one MCP connection on disjoint assets) and one page-fetch
  agent for the pricing lookup; their reports and rebuild snippets are summarised in `delegation.md`.
- Two real engine pitfalls found and fixed late: Godot's glTF importer turned `*_col` collision proxies into visible
  auto-collision nodes (fixed by disabling name-suffix hints for all GLBs), and `Control.set_anchors_preset()` alone
  left full-screen UI with zero size.

## Claude Fable 5.2 GTA Session Metrics

Project: Godot GTA sandbox
Run/session identifier: run `run-20261109-215759`; Claude Code session `7ffba212-fbb2-4c22-ae3c-4c496a3b0a08`
Working-directory full path: G:\YouTube\Fable 5.2 Effort Test GTA\Max
Start timestamp and timezone: 2026-11-09T21:57:59.979+01:00 (Central European Standard Time, UTC+01:00)
End timestamp and timezone: 2026-11-10T07:56:30.285+01:00 (Central European Standard Time, UTC+01:00)
Elapsed wall-clock time (HH:MM:SS): 09:58:31 (includes the two pauses below)
Elapsed minutes: 598.5
Elapsed hours: 9.98
Known pauses / resumed segments: (1) 2026-11-09 23:28:32 → 23:45:18, 00:16:46, usage limit (HTTP 429), resumed by the user ("Try again"); (2) 2026-11-10 01:20:53 → 05:49:06, 04:28:13, usage limit again, resumed by the user ("продолжай"). Wall-clock minus these pauses ≈ 05:13:32 (derived, not separately tracked active time). An earlier aborted attempt `run-20261109-214907` (21:49:07, no work products, no usable usage log) is preserved and not included.

Requested model: Claude Fable 5.2
Actual model identifier(s): claude-fable-5-2 (lead session and 15 delegated asset / audio agents); claude-haiku-5-5 (one page-fetch agent used for the pricing lookup)
Thinking/effort setting (if exposed): "Max" effort run (folder / task name); per-request effort is not exposed in the usage records
Input tokens (state whether uncached or inclusive): 2,574 uncached input tokens (`input_tokens`, exclusive of cache reads / writes)
Cache-read tokens: 480,530,434
Cache-write tokens: 13,458,607
Cache-write duration breakdown (if exposed): 5-minute writes 11,368,218 (delegated agents); 1-hour writes 2,090,389 (lead session)
Output tokens: 5,597,792
Thinking/reasoning tokens (included / separate / unavailable): included in output tokens (not separately exposed)
Deduplicated total tokens: 499,589,407 (1,283 assistant messages, deduplicated by message id; lead session + 16 delegated agents)
Usage source and observation cutoff: usage metadata of the local Claude Code session log and its sub-agent transcripts (`~/.claude/projects/G--YouTube-Fable-5-2-Effort-Test-GTA-Max/7ffba212-…`), read by `tools/metrics/usage_report.py` (counters only, no content); cutoff 2026-11-10 07:56:42 +01:00; snapshot `.fable-5.2-gta-runs/run-20261109-215759/usage_final.json`
Unmeasured work / limitations: the closing message and the final commit after the cutoff are not counted; turns that failed with the usage-limit error carry no usage; agents cut off by the limit may have lost the usage of their last unfinished request; segment `run-20261109-214907` has no accessible usage

Token-only API-equivalent cost (USD): $467.17 — all tokens of the run (Fable 5.2 work and the small Haiku page fetch) priced at Claude Fable 5.2 rates, as the user instructed
Per-model subtotals (if applicable): not computed separately at the user's request (the user asked for one total priced at Fable 5.2 rates); the model attribution of each part is listed above
Official pricing source, verification date and comparison tier: https://platform.claude.com/docs/en/about-claude/pricing and https://platform.claude.com/docs/en/build-with-claude/prompt-caching, verified 2026-11-10, Standard API tier
Rates and formula used: Claude Fable 5.2 — input $8 / MTok, 5-minute cache write $10 / MTok, 1-hour cache write $16 / MTok, cache read $0.20 / MTok, output $40 / MTok; cost = (2,574 × 8 + 11,368,218 × 10 + 2,090,389 × 16 + 480,530,434 × 0.20 + 5,597,792 × 40) / 1,000,000 = 0.02 + 113.68 + 33.45 + 96.11 + 223.91 = $467.17
Cache/context/tier adjustments or explicit assumptions: categories are mutually exclusive per the prompt-caching documentation; no long-context surcharge applies to Fable 5.2 (the pricing page lists the full context at standard pricing); no Batch, Fast-mode or data-residency multiplier applied
External tool/API fees (known / excluded / unknown): none known; Blender and Godot ran locally, the two documentation pages were fetched publicly
Measured / estimated / unavailable, with reasons: elapsed time measured (OS timestamps); pause boundaries measured from the session log; active time derived; tokens measured from the session's own usage records; USD computed from measured tokens and verified prices (priced entirely at Fable 5.2 rates per the user's instruction)

Blender MCP server/tool namespace actually used: `blender-gta-max` (execute_blender_code, look, get_scene_info, get_addon_status; asset-library / generation tools never used)
Blender host: localhost
Blender port: 9881
Blender master file: GodotFable5.2GTAMax.blend
Verified full path of master file: G:\YouTube\Fable 5.2 Effort Test GTA\Max\GodotFable5.2GTAMax.blend (saved, not dirty, 1,478 objects at the end)
Approximate number of major Blender assets created: 311 exported GLB assets (72 building-kit modules, 25 landmarks, 126 props / nature, 19 vehicles + 18 mod parts, 2 character bodies with 28 accessories and 51 animation clips, 28 weapons / held items, 9 animals, 12 pickups)
