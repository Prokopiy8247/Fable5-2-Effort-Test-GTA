# HALCYON BAY - Activities (`activities` world system)

Owner: ACTIVITIES programmer (Wave 3). Spec 47 / 47A / 46A. Free-roam hobbies only: **no missions, no
story, no dialogue, no unlock chains, no objective markers**. An activity starts only when the player
deliberately uses its activity point (an `Interactable`) - or, for stunt jumps, drives off a ramp fast
enough. Each run gives a score or a time, a medal against fixed thresholds, a small cash reward and skill
XP, and keeps personal bests (SaveSystem provider `activities`).

| file | what |
|---|---|
| `gta/code/world/activity_system.gd` | the `activities` world system: definitions, activity points, one `_physics_process` that ticks the running controller + the stunt watcher, results, records, save provider, HUD hook |
| `gta/code/world/activities/activity_range.gd` | Ironsight Range courses (turning / pop-up / moving targets, scoring, weapon hand-out, lawful-fire session) |
| `gta/code/world/activities/activity_race.gd` | checkpoint races / time trials: route building, grid, vehicle, countdown, checkpoints, arch + columns + blip |
| `gta/code/world/activities/activity_stunts.gd` | stunt jump watcher (ramp footprint, launch, airtime, landing, safe-landing window, slow motion) |
| `gta/code/world/activities/activity_target_body.gd` | the hit collider of one pooled target (forwards the `Dmg` contract to the range controller) |
| `gta/code/world/activities/activity_ring.gdshader` | additive checkpoint column on the Blender `vfx_checkpoint_ring` mesh |
| `gta/code/world/activities/activity_hud.gd` | fallback tracker panel, only created when the HUD has no activity card (the UI's `HudActivity` exists, so normally unused) |
| `gta/resources/registries/activities_registry.gd` | Registry kind `activities` (8 definitions) |
| `gta/tests/act_api.gd`, `gta/tests/act_shots.gd` | headless API / gameplay test, windowed screenshots |

## 1. The activities

| id | kind | where | what |
|---|---|---|---|
| `range_handgun` | shooting range | Ironsight Range, `Use_Start` marker (just inside the door) | "Ironsight Challenge - Handgun course": pistol, 3 rounds (Turners, Pop-ups, Movers), ~60 s |
| `range_carbine` | shooting range | same shed, by the counter (building-local (-12.3, 0.06, 2.3)) | carbine course: shorter windows, 3 plates per volley, faster movers |
| `stunt_foundry` | stunt jump | `stunt_ramp_1` (Foundry Yard, big ramp, faces east) | >= 13 m/s off the lip, >= 16 m, >= 0.9 s, $500 first time |
| `stunt_docks` | stunt jump | `stunt_ramp_2` (docks deck, small kicker) | >= 11 m/s, >= 9 m, >= 0.45 s, $300 first time |
| `stunt_apron` | stunt jump | `stunt_ramp_3` (airport apron, big ramp) | >= 13 m/s, >= 16 m, >= 0.9 s, $500 first time |
| `race_coral_loop` | street race | `race_start` (Coral Ring south, flag on the south sidewalk) | 964 m city loop, 8 checkpoints, `sports` car if needed |
| `race_harbor_sprint` | sea race | `marina_dock` pier (flag + minimap blip) | 815 m loop along the south coast, 10 checkpoints, `speedboat` at `boat_spawn` |
| `race_hill_trail` | off-road trail | bottom of Signal Hill Road (flag + blip) | 254 m climb on the dirt road to the hill top, `motorcycle` |

Route lengths / checkpoint counts are the measured values from `act_api` (setup part).

### 1.1 Shooting range (spec 47A "highest priority")

Geometry comes from the city landmark (W2.4 API): `Lane_1..5` world markers (firing positions, -Z =
down-range) and the building transform (manifest coordinates: down-range = local +X, lanes along local Z,
yard floor y 0.03, firing line x -9.0). Targets are pooled GLB instances created on first use under
`Activities/RangeTargets` (17 for the handgun course: 5 turners, 15 plates in 3 rows, 2 movers - only the
ones a course uses):

- **Turners** - `target_round` easels at 8 m (row x -1.0, between the shooter and the baked hanging
  targets). The `Target` ring face turns face-on (quarter turn about the vertical through the bullseye) for
  `window` s, then edge-on. Score by ring: radius 0.09 / 0.18 / 0.27 / 0.36 / 0.45 m -> 10 / 8 / 6 / 4 / 2.
  A hit turns the face away.
- **Pop-ups** - `target_silhouette` steel plates (bottle-shaped, not a figure) in rows x -3.5 / 5.0 / 9.0
  (6.7 / 15.2 / 19.2 m from the shooter). The `Target` child flips up on its hinge (local X, 0.18 s) and lies
  back down when the window ends (0.28 s) or when it is hit (knocked flat in 0.12 s, sparks, `target_hit`).
  Points 10 + speed bonus (0..5, remaining window) + distance bonus (0 / 3 / 6) + 3 for a hit within 0.16 m
  of the `Hit_Center` marker.
- **Movers** - plates that slide across the yard on a track (rows x -4.5 and 8.0, from one side wall to the
  other at 1.5-2.3 m/s, carbine 2.2-3.2 m/s): 15 + speed + centre bonus.
- Volleys are generated per round from the definition (`exposures`, `together`, `window`, `gap`, `rows`)
  with `Game.rng` (`--seed` makes a course repeatable); the same lane is not repeated right away.
- **Score** = target points + accuracy bonus (`hits / shots * 40`). Medal = score / maximum possible
  (gold 0.78 / silver 0.58 / bronze 0.38 handgun; 0.8 / 0.6 / 0.4 carbine). Rewards $300 / 150 / 60
  (carbine $400 / 200 / 80). Skills `shooting` XP: 0.05 per hit + 0.8 / 0.5 / 0.25 by medal.
- **Session**: refused while wanted; the inventory is snapshotted (`get_save_data`), the course weapon is
  given with ammo and equipped (re-equipped every 0.25 s if the player switches), the reserve is topped up
  every round; the player is teleported onto the lane (camera snapped down-range). Leaving the booth (> 5 m
  from the lane, stepping past the firing line, entering a vehicle) or dying aborts. At the end / abort the
  inventory snapshot is restored, so the player keeps exactly what he had.
- **Lawful gunfire**: `Combat` reports every player gunshot as the crime `gunfire`; at a range this would
  call the police. The session sets `Wanted.enabled = false` and restores the previous value afterwards
  (refused while wanted, so this can never clear stars). See "requests" below for the cleaner hook.
- Shots are counted from `EventBus.weapon_fired` (shooter = player, course weapon); hits arrive through the
  normal Dmg path (`Combat.fire_hitscan` -> collider on `Layers.WORLD`, meta `surface` metal / wood ->
  `activity_target_body.gd.apply_damage` -> controller). Only `bullet` damage from the player counts.

### 1.2 Stunt jumps

`activity_stunts.gd` uses the ramp transform exactly as the dressing places the model (named location
basis, origin on the ground) and the `Entry` / `Lip` markers + width from the props manifest
(`props.get_prop_def`), with built-in fallbacks. Idle cost: a 4 Hz scan while the player drives a car /
bike / bicycle; within 30 m of a ramp it scans every physics frame (a car crosses an 8 m ramp in ~0.3 s).

- ARMED: vehicle origin inside the ramp footprint (|x| <= half width + 0.8, between Entry + 1.5 and
  Lip - 0.4), moving forward.
- LAUNCH: passes the lip plane at >= `min_speed` -> `EventBus.activity_started(<jump id>)`, slow motion
  (`Game.request_time_scale("activity_stunt", 0.35)`, released after 1.1 s of real time or at touchdown), a
  little camera trauma.
- AIR -> LANDING when >= 2 wheels touch (`grounded_wheels`, ray fallback) after 0.25 s. Fails when the
  vehicle is wrecked, the player bails out, it lands in water, or after 10 s.
- **Safe landing** = upright (`basis.y.y > 0.75`) with wheels down for 0.4 s within 2 s of touchdown.
- The jump counts when it is safe AND distance (horizontal launch -> touchdown) >= `min_distance` AND
  airtime >= `min_airtime`. First success: banner "STUNT JUMP" + "x m - y s airtime", toast with progress
  (n / 3) and the reward, `driving` XP, record `done`; later successes report personal bests. Every attempt
  emits `EventBus.activity_finished(id, result)` with `result_screen = false` (no pausing panel).
- Measured (`act_api`): sports car at ~17 m/s off `stunt_ramp_1`: 41.2 m, 2.47 s airtime, safe landing.

### 1.3 Races / time trials

No AI opponents: every race is a time trial against par times computed from the real route length
(`par_speed` = average m/s per medal; Coral Loop gold 50.7 s / silver 64.3 s / bronze 87.6 s). The par
speeds are **estimates** (gold = 68 km/h average in the city) - they were not tuned by driving the routes.

- **Routes** (built at setup, cached): `road` joins `RoadGraph.find_route` legs over the `via` list
  (named locations or [x, z]) so the polyline follows the right-hand lanes; checkpoints every `spacing` m
  (>= 45 m from the finish) + the finish. Note: RoadGraph routes are lane-strict (a 2-lane road keeps its
  lane through junctions), so the Coral Loop starts / ends on the kerb-side westbound lane at (60, 154.6),
  1.75 m from `race_start`; with `race_start` itself the router picked the opposite carriageway.
  `trail` uses the RoadGraph segment named `Signal Hill Road` bottom -> top (start 22 m up the track, finish
  10 m before the dead end). `water` uses explicit sea points pushed away from the island until the water is
  >= 2.5 m deep (the test also samples every leg for land).
- **Activity point**: Interactable (radius 3 m, also usable from a vehicle) + a `race_flag` prop on the kerb
  to the right of the start line (sidewalk / roadside from the segment half width), the sea race on the pier
  at `marina_dock`. The map already draws `race_start`; the other two points carry a `minimap_blip`.
- **Start** (coroutine): refused while wanted or in an aircraft. A suitable vehicle the player sits in
  (`classes`) is kept and moved to the grid, otherwise the definition's vehicle is spawned there
  (`owner_tag = "player"`, badly damaged ones are repaired) and the player is put in instantly. Fade, grid,
  camera snapped along the route, `checkpoint_arch` spawned with `props.spawn_prop` over the start line for
  the duration of the race (on a wide road its opening spans the grid's carriageway from the centre line to
  the kerb, feet on the sidewalk / centre line - it blocks the opposite inner lane only while the race
  runs; centred on narrow roads), 3 s countdown with `Game.lock_input()` (banner 3-2-1-GO).
- **Running**: the checkpoint registers when the segment between the vehicle's previous and current
  position passes within `radius` (9 m street, 11 m sea, 7 m trail) of it in XZ and within 12 m in height.
  The next two checkpoints show additive columns (`vfx_checkpoint_ring` mesh, sun-yellow next, teal after,
  coral finish); a `minimap_blip` (flag, clamped to the rim) marks the next one. Aborts: out of the vehicle
  for 10 s, vehicle wrecked, player down / arrested, > 450 m from the next checkpoint, 15 min.
- **Finish**: time, medal, best time, reward ($500 / 250 / 100 street, $450 / 220 / 90 sea, $400 / 200 / 80
  trail), `driving` XP, arch removed, result screen.

## 2. API (`Game.get_system("activities")`)

```gdscript
func start_activity(id: String) -> bool            # coroutine (fades / spawns); false + toast when refused
func retry_last() -> bool                          # result screen "retry"
func abort_activity(reason := "cancelled") -> void
func can_start(id: String) -> bool                 # also the Interactable condition (prompt hidden while busy)
func is_active() -> bool;  func get_active_id() -> String
func get_hud_info() -> Dictionary                  # polled by the HUD card, see below
func get_activity_list() -> Array                  # {id, kind, display_name, subtitle, position, record}
func get_record(id: String) -> Dictionary          # plays, completions, best_score, best_time, best_medal, best_accuracy, done, best_distance, best_airtime, attempts
func get_stunt_progress() -> Vector2i              # (completed, total)
func get_point(id) -> Dictionary;  func reset_records() -> void
func get_save_data() -> Dictionary;  func load_save_data(d: Dictionary) -> void     # SaveSystem provider "activities"
func set_enabled(on: bool) -> void;  func reset_for_respawn() -> void
var last_refusal: String;  var last_result: Dictionary;  var show_results: bool     # tests / debug
```

Signals: `EventBus.activity_started(id)` (course / race running, stunt launch) and
`EventBus.activity_finished(id, result)` (complete, aborted - `aborted: true, reason` - or a stunt attempt).

**`get_hud_info()`** always has `active, id, kind, title, timer, checkpoint, total, phase`; per kind only the
keys that mean something (the UI card draws a chip per key):
range `subtitle` ("Round n/m  name"), `time`, `time_mode`, `score`, `round`, `rounds`, `hits`, `shots`,
`hint`, `countdown`, `color`; race `subtitle`, `time`, `checkpoint` (= passed), `checkpoints`, `lap`, `laps`,
`par_gold`, `distance_to_checkpoint`, `hint`, `countdown`, `color`; stunt `time` (= airtime), `distance`,
`airtime`, `min_distance`, `hint`, `color`. The same Dictionary is reused between calls.

**Result screen** (`UI.open_screen("activity_result", args)`, owned by the UI module): `id, kind, title,
subtitle, passed, medal` (`gold | silver | bronze | ""`), `medal_id` (incl. `none`), `fail_reason`,
`lines: [{label, value, best: bool}]`, `reward`, `xp: {skill: points}`, `new_record`, `can_retry`,
`retry: Callable(activities.retry_last)`, plus `score / max_score / accuracy / hits / shots / time /
best_score` (range) or `time / best_time / par / top_speed_kmh` (race). The UI also opens the panel itself
on `activity_finished`; results that must not open it carry `result_screen = false` (stunt attempts,
aborts). When the screen file is missing the system falls back to `UI.banner` + `UI.notify`.

## 3. Tests

```powershell
tools\godot.ps1 -Mode headless -Frames 30000 -TimeoutSec 420 -UserArgs '--test=act_api','--test-timeout=400'
tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 420 -UserArgs '--test=act_api','--act_only=setup,range','--test-timeout=400'
tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 220 -UserArgs '--test=act_shots','--act_only=range','--test-timeout=200','--hour=13','--freeze-time','--weather=clear','--disable=traffic,peds,police,emergency,wildlife,taxi,transit'
```
(`--act_only=` parts of `act_api`: setup, range, stunt, race, abort, save; of `act_shots`: range | stunt | race.)

`act_api` (full game, real player / inventory / Combat / vehicles): registry and activity points; routes
(length, checkpoint count, no reversal between checkpoints, sea checkpoints and every sampled leg point on
>= 2.4 m / 0.8 m deep water); the handgun course started with the real `interact` key at `Use_Start`, a
real `Combat.fire_hitscan` at the centre of every exposed target + a few deliberate misses -> all three
target kinds, hits = scripted hits, every shot counted, accuracy < 1, medal, cash, shooting XP, best score,
result args, Wanted back on with 0 stars, inventory / ammo identical to before; a sports car launched at
19 m/s at `stunt_ramp_1` -> launch detected, slow motion, safe landing, distance / airtime, completion,
first-time reward, progress 1/3, time scale restored; the street race started on foot -> car spawned and
entered, input locked during the countdown, arch + columns, each checkpoint registers when the car rolls
through it, finish, best time, reward = medal, arch removed, input free; the carbine course aborted by
walking away restores weapon / ammo / Wanted and packs the targets away; save data JSON round trip and a
garbage-tolerant load.

`act_shots` -> `qa/screenshots/act_range_popups.png`, `act_range_turners.png`, `act_stunt_air.png`,
`act_race_start.png`, `act_race_checkpoint.png`.

## 4. Integration notes / requests

- **Lawful fire hook (request)**: a cleaner way than switching Wanted off would be for `Combat` to skip the
  `gunfire` crime (and use a smaller noise radius) while the shooter has meta `lawful_fire` (or a
  `Combat.lawful_zones` list). AI hearing still makes nearby pedestrians react to range gunfire.
- **Stunt landing zones (request to the dressing owner)**: the Foundry Yard loose-cargo cluster at
  lot (hx - 9, hz - 4) ~ (-137.6, 138.5) contains a `barrel_explosive` right in the landing line of
  `stunt_ramp_1` (a 61 km/h launch lands ~41 m out at x ~ -135): the jump counts, then the barrel explodes
  and the police come (seen in `act_api`). The run-out reservation (30 m) is shorter than real jumps
  (40-60 m); please keep a ~70 x 10 m corridor past `stunt_ramp_1` / `_3` free of explosives.
- The arch blocks the opposite inner lane of the Coral Ring while the street race runs (traffic bypasses
  through the outer lane); it is removed at the finish / abort.
- Saving mid-session stores the range loadout (weapon + ammo) in the inventory snapshot of the save; it is
  restored when the course ends, not when such a save is loaded later (minor).

## 5. Known limits

- No AI opponents in races (time trials vs. par times); par times are estimates from the route length.
- One lap per race; no ghost / replay.
- Stunt jumps exist only at the three dressing ramps (no extra ramps placed).
- Turners are plain ring faces on easels; the baked hanging targets of the building are decoration only.
