# HALCYON BAY — Architecture & Collaboration Contract

**Read this file completely before writing any code or touching Blender.** It is the binding
contract between all contributors (many agents work in parallel on this project). The benchmark
specification is `Claude_Fable_5.2_Godot_GTA_BlenderMCP_Prompt.md` in the project root.

- Game: **Halcyon Bay** — an original, missionless, single-player free-roam crime sandbox on a
  compact ~600×600 m island city. No missions, quests, story, mission markers, quest givers.
- Engine: **Godot 4.7.2 stable**, Forward+, GDScript, Jolt Physics, 60 Hz physics.
- DCC: **Blender 5.2.2 LTS** driven only through the MCP server **`blender-gta-ultracode`**
  (localhost:9882), master file `GodotFable5.2GTAUltracode.blend` in the project root.
- Project root: `G:\YouTube\Fable 5.2 Effort Test GTA\Ultracode` (= `res://`).

---------------------------------------------------------------------------------------------------

## 1. Hard rules (violating these can crash the machine or corrupt other people's work)

1. **Godot is launched ONLY through `tools\godot.ps1`** (never call the Godot exe directly). It
   enforces: one instance at a time (global mutex — your call may wait in a queue for minutes,
   so give the shell call a 600000 ms timeout), hard time limits, FPS cap, GPU gate.
   Keep runs short and batch your checks; other agents are waiting for the same lock.
2. **GPU safety (single shared RTX 5070, a driver crash destroys everybody's work):** windowed
   runs only when you need pixels (screenshots), ≤ 1280×720, ≤ 30 fps cap, ≤ ~20 s. Everything
   else `--headless`. No uncapped loops, no stress tests in Wave work. In Blender: Workbench /
   solid viewport only, previews ≤ 1024 px, **never Cycles, never GPU baking**, no heavy
   subdivision / particles. If you ever see "device lost", TDR, or a frozen tool: stop, report.
3. **Blender:** use only the `blender-gta-ultracode` MCP tools `execute_blender_code`,
   `get_scene_info`, `look`, `get_addon_status`. **Forbidden:** `search_assets`, `import_asset`,
   `generate_3d` (no external / AI-generated assets — everything is authored by us),
   `disable_telemetry`, `record_trajectory_feedback`. Always pass the `user_prompt` argument
   exactly as given in your task brief.
4. **Never modify what you do not own.** File ownership is listed in §3. Do not edit
   `project.godot`, `tools/godot.ps1`, `tools/blender/gta_bl.py`, `gta/code/core/*`,
   `docs/ARCHITECTURE.md`, or another module's files. If you need a change there, put it in your
   final report under "requests to lead". Never run `git` commands that change state (the lead
   commits). Never delete other authors' Blender objects, never purge orphans, never
   "clean the scene", never open/save-as another .blend.
5. **Autoload/contract signatures are frozen.** You may add public members; never rename or
   remove existing ones, never change parameter order. Same for EventBus signals.
6. **Soft dependencies.** Other modules are being written at the same time as yours and may not
   exist yet or may be temporarily broken. Reach them via `Game.get_system("name")`,
   groups, `has_method()`, `ResourceLoader.exists()`, EventBus — never `preload()` a file of
   another module, never reference another module's `class_name` type. Null-check everything
   that crosses a module boundary. Your module must not crash when a neighbour is missing.
7. **No fake breadth, no placeholders.** Final visible content must be Blender-authored assets
   in the project art style. Never substitute engine primitives for a missing asset silently —
   report it. A feature is WORKING only if it has a functional in-game path that you ran.
8. **No missions.** Do not add quest/mission/objective/story systems, markers or dialogue.
9. Original content only: no real brand names, no GTA/Rockstar names, logos, map shapes, UI
   layouts, wording ("WASTED"/"BUSTED" banners must use our own wording, e.g. "DOWN"/"ARRESTED").

---------------------------------------------------------------------------------------------------

## 2. Conventions

- Units: 1 unit = 1 m. Godot: **Y up, −Z forward, +X right**. Map axes: **+X = east,
  +Z = south, −Z = north**. Sea level `Game.WATER_LEVEL = 0.0`. City ground plateau ≈ y 2.5.
- Blender: Z up, assets **face +Y** (⇒ −Z forward in Godot after glTF export), right side = +X.
  Verified mapping: Blender (x, y, z) → Godot (x, z, −y).
- Heading/yaw: rotation about +Y in radians; yaw 0 faces −Z (north).
- GDScript: tabs, static typing where practical, `snake_case` files, one class per file,
  `class_name` only from your module's reserved list (§12). No `@tool` in runtime scripts.
  Avoid per-frame allocations in hot paths; avoid `get_node()` chains across modules.
- Collision layers: always via `Layers.*` constants (`gta/code/core/layers.gd`).
- Groups (exact strings): `player`, `npc`, `ped` (civilians), `police`, `gang`, `animal`,
  `vehicle`, `interactable`, `pickup`, `prop`, `cover`, `ladder`, `damageable` (optional tag),
  `street_light`, `traffic_light`, `water_surface`.
- Surfaces: static world colliders carry `set_meta("surface", "<name>")` with one of
  `Fx.SURFACES`; `Fx.surface_of(collider)` resolves it.
- Randomness: use `Game.rng` (seedable via `--seed=`) for gameplay spawning decisions.
- Time: gameplay timers use game time (respect pause / `Engine.time_scale`).

---------------------------------------------------------------------------------------------------

## 3. Directory layout and ownership

```
res://
  project.godot                      LEAD
  tools/   (gdignored)               LEAD   godot.ps1, blender/gta_bl.py ; blender/assets/*.py = asset authors
  docs/                              LEAD   (authors may ADD docs/<MODULE>.md for their module)
  qa/      (gdignored)               shared output: blender_previews/, screenshots/, logs/
  gta/
    code/
      core/        LEAD    layers, dmg, event_bus, game, registry, settings, input_setup, main, boot_manifest
      editor/      LEAD    headless tools (check_all, print_scene_tree); authors may add their own tools
      debug/       test_harness (LEAD); debug_system + admin helpers = DEBUG/ADMIN module
      world/       WORLD module (world.gd, terrain, roads, layout, city_builder, interactable(LEAD),
                   props, shops, activities) and ENVIRONMENT module (world_clock.gd, weather.gd,
                   environment_system.gd, water, sky)
      characters/  CHARACTER module (character_visual, humanoid_animator, ragdoll)
      player/      PLAYER module (player, camera rig, states, respawn) ; skills.gd = SKILLS
      vehicles/    VEHICLE module (vehicle_base, car, bike, boat, heli, plane, manager, garage, mods)
      weapons/     WEAPONS module (specs, inventory, weapon models, projectiles, pickups)
      combat/      WEAPONS/VFX module (fx.gd, combat utilities, explosions, fire)
      ai/          AI module (npc_base, ped_system, senses, combat AI, wildlife, emergency)
      traffic/     TRAFFIC module (traffic_system, traffic AI, signals, taxi, transit)
      police/      POLICE module (wanted_system.gd, police_system, units, roadblocks, heli)
      ui/          UI module (ui_manager.gd, hud, minimap, screens/, widgets/)
      audio/       AUDIO module (audio_manager.gd, synthesis tools, radio, ambience)
      save/        SAVE module (save_system.gd)
    generated/
      models/<category>/…glb         Blender exports (characters, vehicles, weapons, buildings,
                                     props, nature, animals, interiors, misc) + manifest.json files
      audio/                         synthesized .wav
      textures/, materials/, vfx/    procedurally generated resources
    scenes/        .tscn wrappers: bootstrap/, characters/, vehicles/, weapons/, world/, props/, ui/
    resources/
      data/<kind>/*.tres             Registry data (see Registry)
      registries/*.gd                code registrars: static func register_all(registry: Node)
      themes/                        UI theme
    tests/         <name>.gd test scripts for TestHarness (+ tests/scenes/ for isolated test scenes)
```

Name your test files with your module prefix (`veh_drive_basic.gd`, `plr_move.gd` …).

---------------------------------------------------------------------------------------------------

## 4. Boot flow

`res://gta/scenes/bootstrap/main.tscn` (`core/main.gd`):

1. Autoloads start (order): `InputSetup, EventBus, Settings, Registry, Game, WorldClock, Weather,
   Audio, Fx, Wanted, Skills, SaveSystem, UI, TestHarness`.
2. Main creates `Entities` (Node3D; parent for all runtime-spawned things — use
   `Game.get_entities_root()`), then instantiates every existing entry of
   `BootManifest.SYSTEMS` in order, registers it (`Game.register_system(name, node)`), and awaits
   its optional `setup()`.
3. Main instantiates `res://gta/scenes/characters/player.tscn`, calls
   `player.teleport(spawn.origin, yaw)` at `Game.get_location("spawn_start")`.
4. `Game.is_ready = true`, `EventBus.game_ready` → free roam. No menu gate.

System names/paths (fixed; create the file and it is picked up):

| name | path | owner |
|---|---|---|
| world | `code/world/world.gd` | WORLD |
| environment | `code/world/environment_system.gd` | ENVIRONMENT |
| city | `code/world/city_builder.gd` | WORLD (city dressing) |
| interactions | `code/world/interaction_system.gd` | WORLD (doors, ladders, elevators, use points) |
| vehicles | `code/vehicles/vehicle_manager.gd` | VEHICLE |
| pickups | `code/weapons/pickup_system.gd` | WEAPONS |
| props | `code/world/prop_system.gd` | WORLD (physics props / breakables) |
| traffic | `code/traffic/traffic_system.gd` | TRAFFIC |
| peds | `code/ai/ped_system.gd` | AI |
| police | `code/police/police_system.gd` | POLICE |
| emergency | `code/ai/emergency_system.gd` | AI |
| wildlife | `code/ai/wildlife_system.gd` | AI |
| shops | `code/world/shop_system.gd` | ECONOMY |
| garage | `code/vehicles/garage_system.gd` | VEHICLE |
| transit | `code/traffic/transit_system.gd` | TRAFFIC |
| taxi | `code/traffic/taxi_system.gd` | TRAFFIC |
| activities | `code/world/activity_system.gd` | ACTIVITIES |
| radio | `code/audio/radio_system.gd` | AUDIO |
| ambience | `code/audio/ambience_system.gd` | AUDIO |
| respawn | `code/player/respawn_system.gd` | PLAYER |
| debug | `code/debug/debug_system.gd` | DEBUG |

A system is a script extending `Node`/`Node3D` (or a PackedScene). Optional methods:
`setup()` (may `await`), `set_enabled(on: bool)`, `get_save_data()/load_save_data(d)`,
`reset_for_respawn()`.

---------------------------------------------------------------------------------------------------

## 5. Autoload API summary (read the stub files — they are the source of truth)

- **Game** (`core/game.gd`): `player`, `world`, `camera_rig`, `systems`, `money`, `flags`, `rng`,
  `invulnerable`; `get_system(name)`, `get_player_position()`, `get_player_velocity()`,
  `get_player_vehicle()`, `add_money/spend/set_money`, `ground_height(x,z)`, `get_location(name)`,
  `is_in_water(pos)`, `spawn_vehicle(spec_id, xform, opts)`, `spawn_npc(archetype, pos, opts)`,
  `get_entities_root()`, `set_paused`, `request_time_scale(id, s)/release_time_scale(id)`,
  `lock_input()/unlock_input()/is_input_locked()`, `set_system_enabled(name, on)`.
- **EventBus** (`core/event_bus.gd`): all cross-module signals.
- **Registry** (`core/registry.gd`): `register(kind, def)`, `get_def(kind, id)`, `ids(kind)`,
  `all(kind)`. Data = `.tres` in `resources/data/<kind>/` or registrar scripts in
  `resources/registries/`. Definitions are custom Resources (or Dictionaries) with an `id`.
- **Settings**: `get_value(key)`, `set_value(key, v)`.
- **WorldClock**: `hour` (0–24), `get_daylight()` 0–1, `is_night()`, `get_phase()`,
  `set_hour(h)`, `advance_hours(h)`, `get_time_string()`, `rate`, `paused`.
- **Weather**: `current`, `set_weather(id, sec)`, `TYPES`, blended params `cloud_cover`,
  `rain_intensity`, `fog_amount`, `wetness`, `wind_strength`, `lightning_flash`;
  `get_grip_multiplier()`, `get_visibility()`, `is_raining()`.
- **Audio**: `play(id, vol_db, pitch, bus)`, `play_at(id, pos, vol_db, pitch, max_dist, bus)`,
  `make_loop_player(id, parent, max_dist, bus)`, `make_loop_player_2d(id, bus)`, `get_stream(id)`.
  Buses: `Master, SFX, Music, Ambience, UI, Engine, Weapons` (audio module creates them at boot).
- **Fx**: `impact(pos, normal, surface, scale)`, `muzzle_flash(node, scale)`, `tracer(a, b)`,
  `explosion(pos, radius, damage, instigator, opts)`, `spawn_fire(pos, dur, parent, scale)`,
  `smoke_puff`, `sparks`, `dust`, `splash`, `tire_smoke`, `glass_shatter`, `blood`, `decal`,
  `shake_camera(amount, pos, radius)`, `surface_of(collider)`, signal `camera_shake_requested`.
- **Wanted**: `level` 0–5, `state` (`Wanted.State.NONE/PURSUIT/SEARCH`), `report_crime(id, pos,
  opts)`, `police_sighting(observer, pos)`, `set_level(n)`, `clear(reason)`,
  `last_known_position`, `search_radius`, `escape_progress`, `player_visible_to_police`,
  `CRIME_HEAT` table (crime ids).
- **Skills**: `get_level(skill)`, `get_factor(skill)`, `get_multiplier(skill, at0, at100)`,
  `add_xp(skill, amount)`, `SKILLS`.
- **SaveSystem**: `register_provider(key, obj)`, `save_game(slot)`, `load_game(slot)`,
  `has_save(slot)`, helpers `vec3_to_array` etc.
- **UI**: `notify(text, kind)`, `show_prompt(text, action)/hide_prompt()`, `banner(text, sub,
  color, dur)`, `fade_out/fade_in` (awaitable), `open_screen(id, args)`, `close_screen(id)`,
  `toggle_screen`, `is_screen_open(id)`, `SCREENS` id→path table, `set_hud_visible`.
- **TestHarness**: `--test=NAME`, `check()`, `finish()`, `shot(name)`, `wait_frames/seconds`.
- **InputSetup**: every input action (see file). `InputSetup.label(action)` for prompts.

### Shared mini-contracts

**Damage** (`core/dmg.gd`): damageable = node with `apply_damage(info: Dictionary)`.
Build infos with `Dmg.make(amount, type, instigator, position, direction, extra)`, deliver with
`Dmg.apply(collider, info)`. Player damage code must respect `Game.invulnerable`.
Baselines: characters 100 hp (+ up to 100 armor for player/police), cars ~1000 hp.

**Noise** — emit `EventBus.noise_emitted(pos, radius, kind, instigator)` for anything audible to
AI (gunshot ≈ 70 m, suppressed ≈ 12 m, explosion ≈ 120 m, sprint footstep ≈ 9 m, walk ≈ 5 m,
stealth ≈ 1.5 m, horn ≈ 30 m, crash ≈ 35 m).

**Crime** — whoever detects the player doing something illegal calls
`Wanted.report_crime(crime_id, position, {instigator, victim, direct_police_witness})`.
Wanted owns witness logic, heat and stars. Never set stars directly from gameplay code.

**Interactable** (`world/interactable.gd`, class `Interactable`): see file. The player module
drives prompts + key press; everyone else just creates Interactables and connects `interacted`.

**Vehicle entry**: player presses `enter_vehicle` → nearest node in group `vehicle` with
`can_enter(player)` → `player.enter_vehicle(vehicle, seat)` → `vehicle.occupant_enter(player,
seat)`. While `vehicle.is_player_driven` the vehicle reads driving input itself (unless
`Game.is_input_locked()`). Exit: `vehicle.occupant_exit(seat)` returns the exit Transform3D.

---------------------------------------------------------------------------------------------------

## 6. Module contracts

### 6.1 WORLD (`Game.world`, script `code/world/world.gd`, class `World`)

The island is generated in code from data in `WorldLayout` (deterministic, no manual scenes).
Required API (others rely on it — keep names exact):

```gdscript
func get_height(x: float, z: float) -> float            # terrain Y (below 0 under the sea)
func get_water_depth(x: float, z: float) -> float       # WATER_LEVEL - height (<= 0 on land)
func is_water_at(pos: Vector3) -> bool                  # point is inside the sea volume
func get_surface_at(pos: Vector3) -> String             # "asphalt","concrete","grass","sand","dirt"...
func get_district(pos: Vector3) -> String               # see districts below, "ocean" off-shore
func get_location(name: String) -> Transform3D          # named locations (below); basis = facing
func get_locations() -> Dictionary                      # name -> Transform3D
func get_lots() -> Array[Dictionary]                    # building lots (below)
func get_spawn_points(kind: String) -> Array[Transform3D]
func get_minimap_data() -> Dictionary                   # {"roads": [...], "coast": PackedVector2Array, "lots": [...], "labels": [...], "water_rects": [...]}
func get_transit_path() -> PackedVector3Array           # closed tram loop centre line
func get_transit_stops() -> Array[Dictionary]           # {"name", "position", "offset"}
var roads: RoadGraph
var walk: WalkGraph
var nav_region: NavigationRegion3D                      # baked walkable navmesh (land, off-road ok)
```

`RoadGraph`: `segments` (Array of {id, points: PackedVector3Array, width, lanes_per_dir,
speed_limit (m/s), kind: "arterial"|"street"|"alley"|"dirt"|"runway"|"taxiway", name}),
`lanes` (directed: {id, points, length, speed_limit, next: PackedInt32Array, segment_id,
end_intersection}), `intersections` ({id, position, radius, has_signal}), and methods
`get_nearest_lane(pos, max_dist) -> Dictionary {lane_id, offset, point, distance}` ({} if none),
`sample_lane(lane_id, offset) -> Transform3D` (−Z = travel direction),
`get_next_lanes(lane_id) -> PackedInt32Array`, `get_signal_state(lane_id) -> int`
(0 green, 1 yellow, 2 red, for traffic leaving that lane), `find_route(from, to) ->
PackedVector3Array` (GPS / taxi / police polyline), `find_lane_route(from_lane, to_lane) ->
PackedInt32Array`, `random_lane_point(near, min_d, max_d) -> Dictionary {lane_id, offset,
transform}`. Right-hand traffic.

`WalkGraph` (sidewalks, crosswalks, plazas, park and beach paths): `random_point(near, min_d,
max_d) -> Vector3` (`Vector3.INF` if none), `get_nearest_point(pos) -> Vector3`,
`find_path(from, to) -> PackedVector3Array`.

Lots: `{id: int, district: String, zone: "office"|"apartment"|"house"|"storefront"|"warehouse"|
"hangar"|"parking"|"park"|"landmark"|"plaza", center: Vector3 (ground), size: Vector2 (x width,
z depth before rotation), yaw: float (front faces the street), landmark: String ("" or a named
location id)}`. The city builder fills lots with buildings from the building manifest (§8.4).

**Districts** (ids): `downtown` (tall commercial core, centre-north), `midtown` (shops and
services between downtown and the waterfront), `residential` (east), `industrial` (west),
`waterfront` (south promenade + marina/docks, south-west), `beach` (south-east), `hill`
("Signal Hill": green, wooded, elevated, viewpoint, north-east), `airport` (north strip:
~380 m runway east–west, apron, hangars, helipad), `ocean`.
Fixed layout brief: island inside x,z ∈ [−300, 300]; ring arterial near the coast; N–S avenues
around x = −120, 0, 120; E–W streets around z = −200, −110, −20, 70, 160; smaller streets and
alleys inside blocks; hill peak ≈ 38 m around (225, −130); beach on the south-east shore;
marina/docks south-west; deep water (to −14 m) with a shipwreck south of the beach.
Outside the footprint: open sea only (aircraft/boats may roam; soft turn-back at 1500 m).

**Named locations** (all must exist; `get_location(name)`):
`spawn_start, safehouse, safehouse_garage, hospital, police_station, gun_shop, mod_garage,
clothing_store, barber, general_store, gas_station, parking_garage, downtown_plaza,
industrial_yard, residential_park, hill_viewpoint, hill_top, beach, marina_dock, boat_spawn,
lighthouse, airport_runway_start, airport_runway_end, airport_helipad, airport_hangar,
rooftop_helipad, shooting_range, shipwreck, tram_stop_1, tram_stop_2, tram_stop_3,
stunt_ramp_1, stunt_ramp_2, stunt_ramp_3, race_start, taxi_stand`.

**Spawn point kinds** (`get_spawn_points(kind)`): `parking` (kerb-side / lot parking bays),
`boat`, `heli`, `plane`, `police_car`, `taxi`, `ped`, `wildlife_land`, `wildlife_water`,
`pickup_weapon`, `pickup_health`, `pickup_armor`, `pickup_cash`, `parachute`, `roadblock`,
`gang`, `ladder`, `bench`.

### 6.2 ENVIRONMENT (`WorldClock`, `Weather` autoloads + `environment` system)

Owns DirectionalLight3D sun/moon, WorldEnvironment (sky, fog, SSAO, glow, tonemap), rain
particles, lightning, the ocean surface + water shader, wetness and night-light drivers.
Drives the **global shader uniforms** that are already declared in `project.godot`
(`[shader_globals]`, so any shader may use `global uniform float gta_night;` even when the
environment system is not loaded): `gta_daylight` (float 0–1), `gta_night` (1−daylight),
`gta_wetness` (0–1), `gta_rain` (0–1), `gta_time` (seconds), `gta_underwater` (0/1),
`gta_wind` (vec3), `gta_player_pos` (vec3). ENVIRONMENT updates them every frame with
`RenderingServer.global_shader_parameter_set()`; nobody else writes them.
It also exposes `get_wave_height(x, z) -> float` (ocean surface Y incl. waves; boats/swimming
use it through `Game.get_system("environment")`, fallback `Game.WATER_LEVEL`) and
`register_light_points(points: Array, color: Color, light_range: float, energy: float)` for the
pooled night street lights (the city builder registers lamp positions).
Street lamps / lit windows / neon read `gta_night` in their shaders (no per-node scripts).
Light budget: ≤ 1 shadowed directional light, ≤ 16 active positional lights near the player
(pooled, no shadows except ≤ 2), everything else emissive.

### 6.3 CHARACTER (`code/characters/`)

One shared humanoid skeleton for player and all human NPCs.
`res://gta/generated/models/characters/humanoid.glb`, wrapper scene
`res://gta/scenes/characters/humanoid.tscn` (root Node3D with `character_visual.gd`).

Skeleton contract (T-pose rest, facing −Z in Godot, feet at origin, height 1.80 m):
`Root, Hips, Spine, Chest, Neck, Head, Shoulder_L, UpperArm_L, LowerArm_L, Hand_L, Shoulder_R,
UpperArm_R, LowerArm_R, Hand_R, UpperLeg_L, LowerLeg_L, Foot_L, UpperLeg_R, LowerLeg_R, Foot_R`
(`_L` = character's left = −X). Bones point along local +Y (Blender default).

`CharacterVisual` API: `get_skeleton() -> Skeleton3D`, `apply_appearance(a: Dictionary)`,
`get_appearance() -> Dictionary`, `randomize_appearance(archetype: String, seed: int)`,
`get_bone_attachment(bone: String) -> Node3D` (creates/returns a BoneAttachment3D),
`set_lod(level: int)`, `get_part_options() -> Dictionary` (slot → ids, for wardrobe/barber UIs).
Appearance dict keys: `body` ("m"/"f"), `skin`, `hair`, `hair_color`, `beard`, `top`,
`top_color`, `bottom`, `bottom_color`, `shoes`, `shoes_color`, `hat`, `glasses`, `outfit`
(full-outfit override: "police", "tactical", "medic", "firefighter", "staff", "" …).

`HumanoidAnimator` (`humanoid_animator.gd`): procedural animation driver for that skeleton —
one node per character, driven by plain parameters, used identically by player and NPCs:
`setup(skeleton)`, properties `speed` (m/s planar), `move_dir_local: Vector2`, `state: String`
(`idle, locomotion, crouch, jump, fall, land, swim, dive, tread, seated_car, seated_bike,
aim, melee, cover_low, cover_high, climb_ladder, vault, roll, parachute, freefall, dead,
surrender, cower, takedown, carried`), `aim_pitch`, `aim_weight`, `weapon_pose` ("none",
"pistol", "rifle", "melee", "rpg", "throw"), `lean`, `update_rate_hz` (LOD), and one-shot
`play_action(name, duration)` (`reload, punch_l, punch_r, heavy, kick, hit_react, throw,
pickup, enter_car, exit_car`). Animation is computed in model space over the rest pose
(robust to bone roll). Blender-authored clips inside the GLB (if any) are optional extras.

Ragdoll: `ragdoll.gd` helper — `Ragdoll.spawn_from(visual, impulse, position) -> Node3D`
(simple physical-bone or rigid-segment ragdoll on `Layers.RAGDOLL`, auto-cleanup, capped count).

### 6.4 PLAYER (`code/player/player.gd`, class `Player`, CharacterBody3D, group `player`)

Scene `res://gta/scenes/characters/player.tscn`. Collision layer `Layers.PLAYER`, mask
`Layers.PLAYER_MASK`. Capsule r 0.35 m, h 1.8 m, origin at feet.

Public members (others rely on them):
```gdscript
var health: float; var max_health: float; var armor: float; var max_armor: float
var is_dead: bool; var current_vehicle: Node3D   # null on foot
var is_aiming: bool; var is_sprinting: bool; var is_crouching: bool; var in_stealth: bool
var in_cover: bool; var is_swimming: bool; var is_underwater: bool; var has_parachute: bool
var breath: float (0..1); var stamina: float (0..1); var noise_radius: float
var visual: Node3D (CharacterVisual); var inventory: Node (WeaponInventory, may be null)
func apply_damage(info: Dictionary) -> void
func heal(amount: float) -> void;  func add_armor(amount: float) -> void
func teleport(pos: Vector3, yaw: float = 0.0) -> void
func set_control_enabled(on: bool) -> void
func enter_vehicle(vehicle: Node3D, seat: int = 0) -> void;  func exit_vehicle() -> void
func get_aim_ray() -> Dictionary        # {"origin": Vector3, "direction": Vector3} from the camera
func get_aim_point() -> Vector3         # world point under the crosshair
func get_target_position() -> Vector3   # chest position, for AI aiming
func add_recoil(pitch: float, yaw: float) -> void
func is_armed() -> bool
func kill(cause: String = "generic") -> void;  func respawn(xform: Transform3D) -> void
func ragdoll(impulse: Vector3, duration: float = 2.0) -> void
func get_save_data() -> Dictionary;  func load_save_data(d: Dictionary) -> void
```
Camera rig (`player_camera.gd`, registered as `Game.camera_rig`): modes `third`, `aim`,
`first`, `vehicle`, `aircraft`, `scope`, `photo`; collision-aware (SpringArm3D or shape cast on
`Layers.CAMERA_MASK`); `add_trauma(amount)`; connects `Fx.camera_shake_requested`;
`set_fov_override(fov, weight)`; yaw/pitch exposed as `yaw`, `pitch`.
The player module also owns: interaction scanning (Interactable prompts), vehicle enter/exit
transitions, swimming/diving, parachute, cover, stealth, melee, ladders/vault, death → the
`respawn` system (hospital respawn, wanted reset, original "DOWN"/"ARRESTED" banners).

### 6.5 VEHICLE (`code/vehicles/`, group `vehicle`, RigidBody3D, layer `Layers.VEHICLE`)

Project-owned raycast-suspension physics. `VehicleBase` + subclasses `Car`, `Bike`, `Boat`,
`Helicopter`, `VehiclePlane` (not `Plane`: Godot built-in). Definitions: Registry kind `vehicles` (`VehicleSpec` resources). Scenes
are built from the GLB + spec by `VehicleManager.spawn_vehicle()` (`Game.spawn_vehicle`), with
`.tscn` wrappers in `scenes/vehicles/` where useful.

Spec ids (roster; do not invent ids outside this list without telling the lead):
`compact, sedan, sports, muscle, suv, pickup, van, police_cruiser, taxi, ambulance, firetruck,
swat_van, box_truck, motorcycle, bicycle, speedboat, jetski, dinghy, heli_civil, heli_police,
plane_prop, plane_jet`. GLB: `res://gta/generated/models/vehicles/<id>.glb`.

Public members of every vehicle:
```gdscript
var spec_id: String; var vehicle_class: String   # "car","bike","bicycle","boat","heli","plane"
var health: float; var max_health: float; var destroyed: bool
var driver: Node; var is_player_driven: bool; var owner_tag: String  # "civilian","player","police","parked","emergency","taxi"
var is_police: bool; var is_emergency: bool; var engine_on: bool; var siren_on: bool
var speed_kmh: float; var paint_primary: Color; var paint_secondary: Color; var mods: Dictionary
func set_inputs(throttle: float, steer: float, brake: float, handbrake: bool = false) -> void   # AI + scripted driving; steer +1 = right
func set_flight_inputs(pitch: float, roll: float, yaw: float, power: float) -> void              # aircraft AI
func can_enter(who: Node) -> bool;  func get_free_seat() -> int
func occupant_enter(who: Node, seat: int = 0) -> void;  func occupant_exit(seat: int = 0) -> Transform3D
func eject_occupants(impulse: Vector3 = Vector3.ZERO) -> void
func get_seat_node(seat: int = 0) -> Node3D;  func get_exit_transform(seat: int = 0) -> Transform3D
func apply_damage(info: Dictionary) -> void;  func repair() -> void;  func explode(instigator: Node = null) -> void
func set_paint(primary: Color, secondary: Color = Color(0,0,0,0)) -> void
func apply_mods(mods: Dictionary) -> void;  func get_mod_options() -> Dictionary
func set_headlights(mode: int) -> void   # 0 off, 1 low, 2 high
func set_siren(on: bool) -> void;  func honk(on: bool) -> void
func get_forward_speed() -> float        # m/s along -Z
func get_camera_params() -> Dictionary   # {"distance","height","fov","look_height"}
func pop_tire(index: int) -> void;  func get_occupants() -> Array
```
Vehicles emit `EventBus.vehicle_collision/vehicle_damaged/vehicle_destroyed`, emit noise, and
report nothing to Wanted themselves except through the documented crime path (hit-and-run,
major collision) — keep that logic in one place (`vehicle_crime.gd`).

### 6.6 WEAPONS / COMBAT (`code/weapons/`, `code/combat/`)

Registry kind `weapons` (`WeaponSpec`) and `attachments`. Weapon ids:
`fists, knife, bat, crowbar, pistol, heavy_pistol, smg, pump_shotgun, auto_shotgun,
assault_rifle, carbine, marksman_rifle, sniper_rifle, grenade, rocket_launcher,
grenade_launcher, molotov`. GLB: `res://gta/generated/models/weapons/<id>.glb`.
Wheel slots (1–8): `melee, handgun, smg, shotgun, rifle, sniper, heavy, thrown`.

`WeaponInventory` (Node named `Inventory` under the player; input-agnostic):
`give_weapon(id, ammo := -1)`, `remove_weapon(id)`, `has_weapon(id)`, `get_weapons() -> Array`,
`equip(id)`, `equip_slot(slot)`, `next_weapon()/prev_weapon()`, `holster()`, `current_id`,
`get_current_spec()`, `trigger_pressed()`, `trigger_released()`, `reload()`, `set_aiming(on)`,
`add_ammo(ammo_type, n)`, `get_ammo(id) -> Dictionary {in_mag, reserve}`, `refill_all()`,
`add_attachment(weapon_id, att_id)`, `has_attachment(...)`, `get_attachments(weapon_id)`,
`melee_attack(heavy: bool)`, `throw_grenade()`, `can_use_in_vehicle(id) -> bool`,
`get_save_data()/load_save_data()`. It asks its owner for `get_aim_ray()`, `add_recoil()`,
and attaches the weapon model to `owner.visual.get_bone_attachment("Hand_R")`.

`Combat` static utilities (class `Combat`, `combat/combat.gd`) — shared by player AND AI:
`Combat.fire_hitscan(origin, direction, spec_or_id, instigator, opts) -> Dictionary` (ray on
`Layers.BULLET_MASK`, spread, damage zones, impact FX, tracer, noise, returns hit info),
`Combat.melee_sweep(attacker, origin, direction, range, damage, opts)`,
`Combat.spawn_projectile(kind, origin, velocity, instigator)`,
`Combat.has_line_of_sight(from, to, exclude := []) -> bool` (on `Layers.SIGHT_MASK`).
Gunfire by the player in public → `Wanted.report_crime("gunfire", …)` is done here, once.

Pickups (`pickup_system.gd`): `spawn_pickup(kind, id, amount, position)` kinds `weapon, ammo,
health, armor, cash, parachute, scuba`; world pickups at `get_spawn_points("pickup_*")`;
NPC drops (cash, weapon).

### 6.7 AI (`code/ai/`)

`NpcBase` (CharacterBody3D, group `npc`, layer `Layers.NPC`): `faction` ("civilian", "police",
"gang", "staff", "medic", "fire"), `health`, `is_dead`, `apply_damage(info)`,
`knock_down(impulse)`, `panic(from: Vector3)`, `get_target_position()`, `archetype_id`,
`set_sim_tier(tier)` (0 full, 1 reduced, 2 minimal), weapon via the shared `Combat` utilities.
Registry kind `npc_archetypes`. `PedSystem.spawn_npc(archetype, pos, opts)`,
pooled spawning around the player from `WalkGraph`, simulation tiers by distance, caps from
`Settings.ped_density`. Senses: sight (cone + `Combat.has_line_of_sight`, range scaled by
`Weather.get_visibility()` and daylight), hearing (`EventBus.noise_emitted`).
Witness flow: civilians who see a crime panic, then (if alive and not interrupted for a few
seconds) call it in → `EventBus.crime_witnessed/crime_reported` → Wanted.

### 6.8 TRAFFIC (`code/traffic/`)

Civilian vehicles are real `VehicleBase` instances driven through `set_inputs()` by a lane
follower on `RoadGraph` (never on the navmesh): following distance, signals, intersections,
speed limits, obstacle braking, stuck recovery, honking, yielding to sirens, parked cars at
`parking` spawn points (frozen until touched). Spawn/despawn out of sight around the player;
density from `Settings.traffic_density`; hard cap on simultaneously simulated vehicles.
API: `set_enabled(on)`, `get_vehicle_count()`, `spawn_traffic_vehicle(lane_id, offset)`,
`clear_all()`, `set_density(mult)`.

### 6.9 POLICE (`code/police/`)

`Wanted` autoload (state machine, heat, witness reports, search/escape, busted conditions) and
the `police` system (dispatcher: units per star level spawned out of the player's view, patrol
cars, foot officers, SWAT at 4–5★, helicopter at 3★+, roadblocks at 3★+, pursuit tactics, search
behaviour around `Wanted.last_known_position`, arrests). API: `spawn_unit(kind, near)`,
`get_units() -> Array`, `clear_units()`, `set_enabled(on)`. Minimap reads units via group
`police` and `Wanted.search_radius`.

### 6.10 UI (`UI` autoload, `code/ui/`)

HUD (health, armor, money, wanted stars, weapon/ammo, minimap/radar, vehicle speed/health,
breath/stamina, time, district toast, interaction prompt, notifications, crosshair/hitmarker,
low-health vignette), screens from `UI.SCREENS`, one Theme (`resources/themes/game_theme.tres`),
responsive containers. Original visual identity (coral / teal / sun-yellow accents on deep navy
glass panels, rounded corners, bold condensed caps for headings). Mouse mode is owned by UI.
Minimap draws from `Game.world.get_minimap_data()` (roads, coast, lots, labels) and live blips.

### 6.11 AUDIO (`Audio` autoload, `code/audio/`)

All sounds are synthesized by project code (tool script → `.wav` in `generated/audio/`).
**Sound ids** (file basenames; gameplay code may call any of these, unknown ids are silent):
`pistol_shot, heavy_pistol_shot, smg_shot, rifle_shot, shotgun_shot, sniper_shot,
suppressed_shot, rocket_launch, grenade_launcher_shot, dry_fire, reload, weapon_switch,
melee_swing, melee_hit, punch_hit, knife_hit, grenade_bounce, pin_pull,
impact_concrete, impact_metal, impact_glass, impact_flesh, impact_wood, impact_dirt,
impact_water, ricochet, glass_break, explosion_small, explosion_large, fire_loop,
footstep_concrete, footstep_grass, footstep_sand, footstep_metal, footstep_wood, footstep_water,
jump_land, body_fall, splash_small, splash_large, swim_stroke, underwater_loop, breath_gasp,
grunt_hit_m, grunt_hit_f, scream_m, scream_f, death_m, death_f, chatter_loop,
engine_car_loop, engine_sport_loop, engine_truck_loop, engine_bike_loop, engine_boat_loop,
heli_rotor_loop, plane_prop_loop, jet_loop, bicycle_loop, tire_skid_loop, tire_roll_loop,
crash_small, crash_large, metal_scrape_loop, horn_car, horn_truck, horn_bike, door_open,
door_close, engine_start, tire_pop, siren_police_loop, siren_ambulance_loop, siren_fire_loop,
tram_bell, tram_loop, parachute_open, parachute_loop, wind_fall_loop,
ui_click, ui_hover, ui_open, ui_close, ui_error, ui_buy, ui_tab, pickup_cash, pickup_weapon,
pickup_health, wanted_up, wanted_down, wanted_clear, arrested, player_down, camera_shutter,
phone_open, cash_register, spray_paint, wrench, target_hit, activity_start, activity_win,
rain_loop, rain_heavy_loop, thunder_1, thunder_2, wind_loop, ocean_loop, city_loop,
industrial_loop, park_birds_loop, night_crickets_loop, airport_loop, harbor_loop,
radio_static, animal_deer, animal_dog_bark, animal_bird, animal_gull, animal_growl`
plus radio station music loops `radio_<station_id>_<n>`.

### 6.12 Admin / debug menu

`UI.SCREENS["admin"]` (F1): must cover the whole list in spec §38. It talks to systems only
through the public APIs above.

---------------------------------------------------------------------------------------------------

## 7. Art direction — "Sunlit Low-Poly"

A warm, sun-bleached coastal city rendered as a crisp, faceted, toy-like low-poly world.

- **Form:** low/mid-poly, **flat-shaded facets**, deliberate chamfers ("chunky" edges via small
  bevels), bold readable silhouettes, slightly exaggerated proportions (wheels a little large,
  characters with slightly large heads/hands). Cylinders 10–16 sides. Smooth shading only on
  truly round parts (tires, pipes, heads) using angle-based sharp edges.
- **Colour:** palette-driven solid-colour materials (`gta_bl.PALETTE` / `pmat()`), **no image
  textures on models**. Detail comes from geometry and separate coloured parts (trim, stripes,
  window frames), not from textures. Roads/ground/water get procedural shader detail in Godot.
- **Light:** warm key sun, cool sky fill, soft SSAO, light fog for depth, glow on emissives.
  Night = deep blue with warm street lamps, lit windows and saturated neon signage.
- **Identity:** original fictional businesses and signage (e.g. "Bay Arms", "Torque Garage",
  "Tide Threads", "HBPD" for Halcyon Bay Police Dept.). No real brands, no real-world logos.
- Consistency beats detail: an asset that is simpler but on-style is better than a detailed
  off-style one. Nothing may look like an unfinished grey box.

Tri budgets (guides): car 2.5–7 k, aircraft/boat 2–7 k, character with outfit ≤ 5 k, weapon
0.3–1.8 k, generic building 0.4–5 k, landmark ≤ 12 k, prop 30–900, tree 150–900.

---------------------------------------------------------------------------------------------------

## 8. Blender asset contract

### 8.1 Protocol (several agents share ONE live Blender)

Every `execute_blender_code` call must be **atomic and self-contained**:

```python
import sys, importlib
P = r"G:\YouTube\Fable 5.2 Effort Test GTA\Ultracode\tools\blender"
if P not in sys.path: sys.path.append(P)
import gta_bl as G; importlib.reload(G)
G.assert_master()            # aborts if the wrong .blend is open
```

- Keep your reusable builders in **your own module** `tools/blender/assets/<your_module>.py`
  (write it with the normal file tools, then `import`/`importlib.reload` it inside the MCP call:
  add `P + r"\assets"` to `sys.path`). The repo must contain the code that built every asset
  (reproducible pipeline). Executing through MCP is what creates the asset; a script that was
  never run is not an asset.
- Never depend on selection, active object or edit mode between calls; other agents' calls
  interleave with yours. Use `bpy.data` / `bmesh` APIs; avoid `bpy.ops` except export/save/render
  (the helper wraps those). Always leave Blender in Object mode.
- Each asset = one **root Empty named exactly as the asset** created with
  `G.asset_root(name, "<Collection/Path>", G.slot("<region>", index))`; all parts are children
  with clean names. Never leave objects named `Cube.001` etc.
- Slots keep assets apart in the shared scene: regions `characters, weapons, props, nature,
  animals, misc, cars, service, bikes, boats, aircraft, interiors, buildings, landmarks, kit`.
  Your brief tells you which region/index range is yours. Only touch objects under your roots.
- Collections (already created): `GTA_GODOT/` → `Characters, NPCs, Vehicles/{Cars,
  Motorcycles, Boats, Helicopters, Airplanes, Service}, Weapons, Buildings, Buildings/Landmarks,
  StreetProps, Interiors, Nature, Animals, VFX_HelperMeshes, CollisionHelpers, Misc`.
- Materials: `G.pmat("PaletteKey")` for shared palette materials (`P_<Key>`), `G.mat(name,
  G.pal("Key"), …)` for contract-named materials (`M_Paint_Primary` …). **One material per
  colour, reuse across assets** — do not create per-object duplicates. Contract materials that
  the game recolours per instance (paint, skin, clothes) are still shared in Blender.
- Visual QA is mandatory: `G.preview(root, "<name>")` writes a contact sheet PNG to
  `qa/blender_previews/` — **open it with the Read tool and look at it**, fix what looks wrong
  (proportions, silhouette, inverted faces, floating parts, wrong colours), repeat. You may also
  use the MCP `look` tool with `target=[root]`. Then `G.validate(root)`, then
  `G.export_glb(root, "<category>/<file>.glb")`, then `G.save()`.
- After exporting, verify in Godot: `tools\godot.ps1 -Mode script -Script
  res://gta/code/editor/print_scene_tree.gd -UserArgs '--scene=res://gta/generated/models/…glb'`
  (imports new files first). Imported structure is `FileRoot(Node3D) → <AssetRoot>(Node3D) →
  parts`; find parts with `find_child("Wheel_FL", true, false)`.
- Blender 5.2 API notes: look nodes up by type; `mesh.use_auto_smooth` no longer exists (use
  `G.shade_smooth(ob, angle)`); actions are slotted (use `pose_bone.keyframe_insert`, do not
  touch `action.fcurves`); read enum identifiers instead of guessing; wrap risky calls in
  try/except and print what you need to know. Work in small steps.

### 8.2 Vehicles — `Vehicles/*` collections → `models/vehicles/<id>.glb`

Real-world scale (compact ≈ 3.7 m, sedan ≈ 4.6 m, SUV ≈ 4.8 m, cruiser ≈ 4.9 m long; ground
clearance ≈ 0.18 m). Origin on the ground under the vehicle centre. Nose toward **+Y**.

Required child nodes (exact names):
- `Body` — main shell (may be several joined parts). Materials by name:
  `M_Paint_Primary` (required), `M_Paint_Secondary` (stripe/roof/bumpers; optional),
  `M_Glass` (alpha ≈ 0.45), `M_Trim`, `M_Chrome`, `M_Interior`, `M_Underbody`, `M_Plate`,
  `M_Headlight`, `M_Taillight`, `M_Indicator`, `M_ReverseLight`, emergency: `M_Siren_Red`,
  `M_Siren_Blue`, livery colours as extra `P_*` materials.
- `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR` (bikes: `Wheel_F`, `Wheel_R`; 6-wheelers add
  `Wheel_ML`, `Wheel_MR`) — separate objects, **origin at the wheel centre, axle along local X**,
  materials `M_Tire`, `M_Rim`. Wheel radius 0.30–0.40 m for cars.
- `SteeringWheel` (origin at hub; optional but wanted), bikes: `Handlebar` (origin on the
  steering axis, includes the fork).
- Doors as separate objects with the origin on the hinge line: `Door_FL`, `Door_FR`
  (+ `Door_RL`, `Door_RR` where sensible); optional `Hood`, `Trunk`.
- Window panes as separate objects (so they can break): `Glass_Windshield`, `Glass_Rear`,
  `Glass_L`, `Glass_R` (material `M_Glass`).
- Marker Empties (`G.empty`): `Seat_Driver` (hip point of the seated driver), `Seat_Passenger_1…`,
  `Exit_Driver`, `Exit_Passenger_1…` (on the ground beside the doors), `Light_Head_L/R`,
  `Light_Tail_L/R`, `Exhaust` (or `_L/_R`), `Engine` (smoke/fire origin), `Siren` (light bar).
  Aircraft: `Rotor_Main` / `Rotor_Tail` / `Propeller` are separate **mesh** objects with origin on
  their spin axis; control surfaces `Aileron_L/R`, `Elevator`, `Rudder` optional; gear wheels use
  the wheel naming (`Wheel_Nose`, `Wheel_L`, `Wheel_R`); helicopters use `Skid` geometry in Body.
  Boats: marker `Prop` (thrust point), `Wake_L/R`.
- Simple convex collision helpers, as child meshes: `Col_Body` (lower hull) and `Col_Cabin`
  (greenhouse) — ≤ 32 verts each, material `P_Collision`; the game hides them.
- Mod parts for the customisable cars (`compact, sedan, sports, muscle, suv, pickup`): child
  meshes `Mod_Spoiler_A`, `Mod_Spoiler_B`, `Mod_BumperF_A`, `Mod_BumperR_A`, `Mod_Hood_A`,
  `Mod_Skirts_A`, `Mod_Roof_A`, `Mod_Exhaust_A`, `Mod_Grille_A` (authored in place; hidden by
  default in game). Shared alternative wheels: `models/vehicles/parts/wheel_<style>.glb`
  (`sport, classic, offroad, deep`), radius 0.34, same origin/axis rules.
- Optional `Body_LOD1`: a much simpler shell (≤ 25 % tris) for distance rendering.

### 8.3 Characters, weapons

Characters: see §6.3 (skeleton, parts, appearance). Weapons → `models/weapons/<id>.glb`:
origin at the right-hand grip, barrel along **+Y**, up +Z, real scale (pistol ≈ 0.2 m, rifle ≈
0.9 m). Children: `Body` (mesh), marker `Muzzle` (barrel tip), marker `Eject`, marker `Grip_L`
(support hand), separate `Mag` mesh where visible, attachments as hidden-by-default child
meshes `Att_Suppressor`, `Att_Scope`, `Att_Flashlight`, `Att_Grip`, `Att_ExtMag`. Thrown items
and projectiles too (`grenade`, `rocket`, `grenade_round`, `molotov`). Pickup-friendly: the
same GLB is used for world pickups.

### 8.4 Buildings, props, nature — manifests

Buildings are assembled **in Blender** from reusable kit functions on a 4 m module grid
(ground floor 4.0 m, upper floors 3.2 m), exported as whole buildings.
Front façade faces **+Y** in Blender (−Z in Godot); origin = centre of the footprint on the
ground. `models/buildings/<id>.glb` and **`models/buildings/manifest.json`**:

```json
{"buildings": [{"id": "office_a", "file": "office_a.glb", "category": "office",
  "footprint": [24.0, 20.0], "height": 41.2, "landmark": "", "collision": "box",
  "entrance": [0.0, -10.0], "tags": ["downtown", "tall"]}]}
```
`category` ∈ office, apartment, house, storefront, warehouse, hangar, parking, landmark, misc.
`footprint` = [width along X, depth along Z] in metres. `collision`: `"box"` (generic solid) or
`"trimesh"` (walk-in / irregular: interiors, canopies, piers). Night windows use material
`M_Window` (the game swaps in a lit-window shader); neon/signs use emissive `P_Neon*`.
Landmark buildings set `"landmark"` to the named location they serve (`police_station`,
`hospital`, `gun_shop`, `mod_garage`, `clothing_store`, `barber`, `general_store`,
`gas_station`, `safehouse`, `parking_garage`, `airport_hangar`, `airport_tower`, `lighthouse`,
`tram_stop`). Walk-in landmarks have a real ground-floor interior and an open doorway ≥ 1.6 m
wide × 2.4 m high; `mod_garage` has a drive-in bay ≥ 4.5 m wide × 3.5 m high.

Props → `models/props/<id>.glb` + `models/props/manifest.json`
(`{"props": [{"id","file","category","size":[x,y,z],"physics":"static|dynamic|breakable",
"mass", "surface"}]}`); nature → `models/nature/` (+ manifest), animals → `models/animals/`.
Several agents append to manifests: **each author writes its own manifest file**
(`manifest_<author>.json`); loaders merge every `manifest*.json` in the folder.

---------------------------------------------------------------------------------------------------

## 9. Godot run protocol

```powershell
tools\godot.ps1 -Mode check                                   # parse-load every script/scene under res://gta
tools\godot.ps1 -Mode check -Dirs gta/code/vehicles,gta/tests # only some folders
tools\godot.ps1 -Mode headless -Frames 900 -UserArgs '--test=veh_drive_basic','--disable=traffic,peds,police'
tools\godot.ps1 -Mode headless -Scene res://gta/tests/scenes/veh_test.tscn -Frames 600
tools\godot.ps1 -Mode window  -Frames 240 -UserArgs '--test=plr_shot_idle'   # screenshots only
tools\godot.ps1 -Mode script  -Script res://gta/code/editor/print_scene_tree.gd -UserArgs '--scene=res://…glb'
tools\godot.ps1 -Mode import                                  # force an import pass
```
- Always call with a generous shell timeout (**600000 ms**): the wrapper queues behind other
  agents. It auto-runs an import pass when files changed (new GLBs, new `class_name`s).
- Headless runs use `--fixed-fps 60` (simulated time, fast). 600 frames = 10 game seconds.
- It prints flagged lines (ERROR / SCRIPT ERROR / WARNING / TEST_RESULT / CHECK_FAIL) and the
  log paths (`qa/logs/…`). Errors in files you do not own may come from a neighbour who is
  mid-edit: ignore them unless they persist, and mention persistent ones in your report.
- Tests: `gta/tests/<name>.gd` (`extends Node`), run with `--test=<name>`; see
  `code/debug/test_harness.gd`. Use `--disable=` to keep unrelated systems out of your test.
  In tests, drive input with `Input.action_press/release`.
- Screenshots: `await TestHarness.shot("name")` → `qa/screenshots/name.png`; then open the PNG
  with the Read tool and actually look at it.
- Isolated test scenes for your module are fine (`gta/tests/scenes/`); autoloads still run.

---------------------------------------------------------------------------------------------------

## 10. Performance budgets (shared)

Target: stable 60 fps at 1080p on the RTX 5070 with headroom (other apps share the GPU).
- Draw calls: use `MultiMeshInstance3D` for anything repeated > ~20 times (props, vegetation,
  façade details). `visibility_range_end` on small things (props ≤ 120 m, grass ≤ 60 m).
- Caps (defaults, scaled by settings): simulated traffic vehicles ≤ 22, parked ≤ 40 (frozen),
  pedestrians ≤ 40, police units ≤ 16 officers + 8 vehicles + 1 heli, animals ≤ 16,
  ragdolls ≤ 8, dynamic debris ≤ 60, decals ≤ 64, active particle systems ≤ 48,
  positional lights ≤ 16.
- AI tiers by distance to player: full < 45 m, reduced 45–110 m, minimal/despawn beyond.
- No per-prop `_process`. One manager with a loop beats 500 scripts.
- Shadow casting off for small props, particles, distant buildings' details.

---------------------------------------------------------------------------------------------------

## 11. Reporting format for agents

End your work with a concise report: what exists and was verified (with the exact test command
that passed), file list, public API additions, **integration notes for neighbours**, **requests
to lead** (changes needed in files you do not own), known issues / unfinished items (honest),
and for Blender work: asset list with tri counts, preview PNG paths, export paths.

---------------------------------------------------------------------------------------------------

## 12. Reserved `class_name`s per module (do not use names outside your list)

- LEAD/core: `Layers, Dmg, BootManifest, Interactable`
- WORLD: `World, WorldLayout, RoadGraph, WalkGraph, Terrain, CityBuilder, PropSystem, WorldProp, BuildingCatalog`
- ENVIRONMENT: `EnvironmentSystem, OceanSurface, SkyController`
- CHARACTER: `CharacterVisual, HumanoidAnimator, Ragdoll`
- PLAYER: `Player, PlayerCamera, PlayerInteraction, PlayerState*` (prefix)
- VEHICLE: `VehicleBase, Car, Bike, Boat, Helicopter, VehiclePlane, VehicleSpec, VehicleManager, VehicleWheel*` (prefix `Vehicle*`)
- WEAPONS/COMBAT: `WeaponSpec, AttachmentSpec, WeaponInventory, WeaponModel, Combat, Projectile, Pickup*`, prefix `Weapon*`, `Fx*`
- AI: `NpcBase, NpcArchetype, PedSystem, Ai*` (prefix), `Animal*`, `Wildlife*`
- TRAFFIC: `Traffic*` (prefix), `Taxi*`, `Transit*`
- POLICE: `Police*` (prefix)
- UI: `Hud*`, `Ui*`, `Minimap*` (prefixes)
- AUDIO: `AudioSynth*`, `Radio*`, `Ambience*`
- ECONOMY/SHOPS: `Shop*`, `Economy*`
- ACTIVITIES: `Activity*`
