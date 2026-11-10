# EMERGENCY services - ambulances and fire trucks (spec 35A) + Wave 3 shared-AI changes

Owner: emergency-services programmer (Wave 3). Contracts: `docs/ARCHITECTURE.md` (system `emergency`),
`docs/ARCHITECTURE_WAVE2.md` W2.1 (ai_controller) and W2.2 (NPC body / brain).
Atmospheric, bounded, never touches the wanted system.

| File | Class | What it is |
|---|---|---|
| `gta/code/ai/emergency_system.gd` | (none) | world system `emergency`: incidents -> dispatch -> responses (one manager loop) |
| `gta/code/ai/emergency_driver.gd` | `AiEmergencyDriver` | RefCounted driving brain of one vehicle = its W2.1 `ai_controller` |
| `gta/code/ai/emergency_responder_brain.gd` | `AiResponderBrain` | W2.2 brain of a medic / firefighter (orders from the system, own danger reactions) |
| `gta/code/ai/emergency_fx.gd` | (none) | pooled water jets (GPUParticles3D, procedural faceted droplets) |
| `gta/tests/emg_api.gd` | test | headless, full game: medical + fire responses, traffic yield, despawn, caps, AI fixes |
| `gta/tests/emg_shots.gd` | test | windowed: ambulance at a body (day), fire truck at a burning wreck (night) |
| `gta/tests/emg_leak_probe.gd` | diagnostic | orphan-node dump for the props + peds exit-leak item |

---------------------------------------------------------------------------------------------------

## 1. Public API (`Game.get_system("emergency")`)

```gdscript
func set_enabled(on: bool) -> void                 # off = everything of ours is removed, incidents ignored
func get_active_responses() -> Array[Dictionary]    # {id, kind ("medical"|"fire"), state, vehicle, crew: Array,
                                                    #  scene: Vector3, patients: [{node, dead, treated}], fire_out,
                                                    #  arrived, time_on_scene, age, remaining_route (m), siren, spawn_dist}
func get_pending_incidents() -> Array[Dictionary]   # {kind, position, severity, patients, age, dispatch_in}
func reset_for_respawn() -> void                    # = clear_all(): responses, incidents, held corpses, smoulder fires
func clear_all() -> void
func dispatch(kind: String, position: Vector3) -> bool   # admin / tests: incident now (adopts bodies within 14 m)
func get_debug_info() -> Dictionary                 # stats + one line per response
var enabled: bool; var stats: Dictionary
var spawn_range: Vector2 = Vector2(85, 170)         # spawn band from the scene (tests narrow it)
var spawn_player_min: float = 60.0                  # never spawn closer than this to the player
```
`state` names: `driving, arrived, working, returning, leaving, stranded, done`.
Vehicles of a response carry `set_meta("ai_controller", <AiEmergencyDriver>)`, `set_meta("emergency_response", id)`,
group `emergency_vehicle`, `owner_tag "emergency"` (spec flag `is_emergency`).

---------------------------------------------------------------------------------------------------

## 2. Incidents

All only within `RESPOND_RADIUS` 110 m of the player; a pending incident is dropped when the player is
190 m away or after 150 s. Same-kind incidents within 30 m merge. At most 4 pending per kind (more are
ignored), at most 4 patients per incident, at most 5 corpses held at once.

| kind | source (EventBus) | notes |
|---|---|---|
| medical | `npc_died` | the corpse is HELD (`npc.hold_corpse(true)`: node + ragdoll stay) until the medics are done; not for medics / firefighters, not for bodies slumped in a seat or in the water |
| medical | `npc_injured` | a takedown knock-out (`info.knockout`) - the victim stays unconscious until treated (`extend_knockout`, capped at 120 s) - or a body that is down with < 40 % health |
| fire | `vehicle_destroyed` | severity 1.0; the wreck SMOULDERS (see below) |
| fire | `fire_started` | 0.6 from a vehicle, 0.45 otherwise (molotov) |
| fire | `explosion` | radius >= 4.5: 0.6, >= 2.5: 0.3 |

A fire truck comes when the severities of an area add up to 0.9 (a car wreck, two molotovs, a big blast
+ fire...); a small fire nobody made bigger is dropped after 25 s.

**Smouldering wrecks.** A vehicle's own wreck fire burns 14 s, a fire truck needs ~20-30 s. So once the
wreck's own fire is out, the system lights its OWN fire handle on the wreck (`Fx.spawn_fire(engine,
140 s, wreck, 0.8)`, 5 dps, no vehicle damage, radius 1.3 m) - the brigade has something to put out, and
it burns out by itself after 140 s if no truck comes. Design decision, documented here.

Dispatch delay: medical 5-9 s, fire 4-7 s. Gunfire within 60 m of the scene in the last 12 s delays the
dispatch (max 40 s); explosions do not (they are what the fire trucks come for).

---------------------------------------------------------------------------------------------------

## 3. Responses

**One ambulance and one fire truck at a time** (one slot per kind). A dispatch:

1. Spawn spot: `RoadGraph.random_lane_point(scene, 85, 170)` (wider retries), no dirt / runway / alley,
   not within 8 m of the lane ends, **out of the camera's view** (frustum + line of sight), >= 60 m from
   the player, no vehicle within 8 m, lane route to the scene <= 460 m; prefers lanes heading to the scene.
2. `Game.spawn_vehicle("ambulance" | "firetruck", xf, {owner_tag "emergency", engine_on, siren, headlights
   at night})`, two responders seated through `Game.spawn_npc("medic" | "firefighter", ..., {"vehicle", "seat",
   "persistent": true, "brain": AiResponderBrain})`.
3. `AiEmergencyDriver.drive_to(scene, urgent = true, stop_before = 9 m / 11 m)`.

**Driving** (`AiEmergencyDriver`, same model as the police driver): lane route by A* on the RoadGraph
(start options: the lane under the car, a same-direction lane change, a three-point turn), pure-pursuit
steering (reference point a quarter wheelbase ahead of the centre for long vehicles, like traffic),
curve-speed and stop-point speed planning, lane limit x1.35 (max 22 m/s) with the siren, red lights
crossed at ~8 m/s; calm driving (leaving) obeys signals at x0.85. Obstacles: a forward ray (slower cars
-> follow / pass on the left, stopped cars -> swerve, but NOT round the wreck / car at the stopping point)
and a swept "person box" (brake for anybody in the path; a person who does not move -> back up and steer
round). Stuck -> reverse with opposite lock; 4 recoveries in 30 s or 95 s of driving -> close to the scene
(< 75 m) the crew walks the rest, else the response is despawned out of view and the incident re-queued.
Over the last 22 m it eases 1.1 m towards the kerb so traffic can pass on the left.

**Traffic yields on its own**: the traffic module scans `siren_on` vehicles (TRAFFIC.md section 3) and
pulls over; `emg_api` counts the traffic drivers with `siren_t > 0` while our vehicles drive (5-9 per run).

**On scene**
- *Ambulance*: crew out, rear barn doors open (`open_door("Door_RL"/"Door_RR")`), each medic runs to a
  patient (two medics, one patient: both sides of the body), paths round the ambulance (the navmesh has no
  cars in it), kneels (`set_service_pose("kneel", body)`: deep crouch, body lowered 0.24 m, both hands on
  the chest doing compressions ~1.8 per second) for 8-11 s (dead) / 5.5-7.5 s (alive). A living patient
  is then `treat()`ed: full health, a knocked-out / knocked-down body gets up at once (the civilian brain
  wakes up dazed). Corpses are released to the normal clean-up when the crew goes back (ragdoll +18 s).
- *Fire truck*: firefighters take spots 6.5 m from the fire (±38 deg either side of the truck), spray
  (`set_service_pose("spray", fire)`: two-handed aim pose, water jet from the right hand along a ballistic
  arc onto the fire, steam puffs + an occasional splash from Fx, hiss = the synthesized `rain_loop`). After
  16 spray-seconds (two sprayers: 8 s) the fire is out: our smoulder handle and every fire handle attached
  to the wreck (`fx_kind == "fire"` children, `FxHandle.stop()`) are stopped, `Fx.extinguish(pos, 7)` is
  called when Fx offers it, big steam puffs; 2.5 s more douse, then back to the truck.
- Then: everybody boards (door chosen by seat, path round the vehicle), siren off, `drive_away()` (calm
  random ~400 m lane walk), despawned when > 150 m from the player and unseen, > 260 m always, after
  120 s unseen, or hopelessly stuck unseen.

**Danger / interference** (`AiResponderBrain`): gunfire within 38 m, an explosion within 30 m, being hurt
(not a traffic accident), a gun pointed at them, panic -> `aborted`: that responder flees / puts the hands
up and walks off; the rest of the crew goes back to the vehicle and leaves. A responder knocked over by a
passing car (not the player's) gets up and the system re-issues its job (`needs_orders`). Responders never
report crimes (`saw_crime` ignored; their faction is `medic` / `fire`, so the PedSystem never makes them
callers either) and never fight. Harming them is a crime like harming anybody (NpcBase reports it).

**Theft**: the PLAYER module's carjack calls our `release_vehicle(v, "carjacked")` (the driver is handed
back and pulled out, the passenger gets out) - a normal `vehicle_theft` (not a police vehicle). Entering
the empty vehicle at a scene -> we let go of it (`release_vehicle "abandon"`). Either way the crew walks
off (`stranded`) and is despawned out of view (> 45 m and unseen, or > 150 m).

`release_vehicle(vehicle, reason)` (W2.1): "carjacked" / "abandon" / "crash" -> our seated crew gets out,
the driver is returned; "despawn" / "destroyed" -> clean-up (seated crew gets out first). Afterwards no
`ai_controller` meta, `driver == null`, siren off (unless the player drives it).

**Performance**: one `_physics_process` for the whole module; driver ticks at 15 Hz within 90 m of the
player, 5 Hz beyond; response state machine at 4 Hz; incident queue at 2 Hz; the responders are normal
PedSystem bodies (tiers, pooled updates); 3 pooled water-jet emitters x 56 particles (created once, on the
first fire); no per-frame allocations in the loops (one Response object per dispatch). Caps: 2 vehicles,
4 responders, 4 pending incidents per kind, 5 held corpses, 1 smoulder fire per wreck.

---------------------------------------------------------------------------------------------------

## 4. Shared AI changes in Wave 3 (npc_base, ped_system, ai_senses, brains) - the INTEGRATION_WAVE2 items

Every W2.2 public name is unchanged. Additions (please fold into `docs/AI.md`):

| item | change |
|---|---|
| `ped_system.count_near(pos, radius)` | already existed (living civilians); Wanted's `count_listeners_near` uses it. Now covered by `emg_api` |
| brain event `carjacked` | `AiBrainCivilian` handles `"carjacked" {attacker}` AND the current traffic signal (`"damaged"` with `info.carjacked`): tough locals fight the thief (after getting up when knocked down) and ignore the theft's `saw_crime` while doing so; others shout, run and may phone the theft in |
| takedown knock-out | `NpcBase.apply_damage` honours `info.knockout` / `knockout_seconds` (default 30, max 120): `knocked_out = true`, stays down; `got_up {"knockout": true}` -> civilian brain mode `dazed` (hand on the head, slow stagger 7-11 s, no scream / flee / call). No pain grunt for `info.silent` hits |
| silent harm by sight only | `_report_harm` wraps the `Wanted.report_crime` of an `info.silent` harm in `peds.set_crime_sight_only(true/false)`: `PedSystem._on_crime` then uses an earshot of 0 (sight only) - `stats.silent_crimes` |
| awareness double count | `AiSenses.update`: when the player exposes `visibility_factor` it is the ONLY posture / light factor (no extra in_stealth x0.45, crouch x0.6, darkness); the old multipliers remain the fallback |
| corpses vanished after 6 s | a dead NPC node freed by the PedSystem (CORPSE_FREE_DELAY) dismissed its non-persistent ragdoll in PREDELETE. Now the corpse ragdoll lives its own lifetime (20 s); knocked-down (persistent) ragdolls still go with the node |
| `is_dead` on foreign nodes | `TrafficDummy.is_dead` is a METHOD, so `x.get("is_dead") == true` raised "Invalid operands 'Callable' and 'bool'" when a traffic car hit a gang member. `NpcBase.is_dead_node(n)` (static, safe for methods / missing members) is used in the gang / combat / civilian brains; `_resolve_attacker` blames the CAR (not the stand-in dummy) when a dummy drives |

New NpcBase members: `knocked_out`, `corpse_held`, `set_service_pose(pose, focus)` (`"kneel"`, `"spray"`, `""`),
`get_hand_position()` (world, from the animator's wrist point), `knock_out_time_left()`, `extend_knockout(s)`,
`treat(by) -> bool`, `hold_corpse(on, linger := 18)`, `get_body_position()`, `static is_dead_node(n)`.
New PedSystem member: `set_crime_sight_only(on)`. New civilian brain mode: `dazed` (+ `carjacked_by`, `knocked_out`).

**Exit-time leak with props + peds**: see section 6 (probe results).

---------------------------------------------------------------------------------------------------

## 5. Tests

```powershell
tools\godot.ps1 -Mode headless -Frames 36000 -TimeoutSec 420 -UserArgs '--test=emg_api','--test-timeout=400','--seed=7','--disable=police,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
tools\godot.ps1 -Mode window -Frames 720 -TimeoutSec 200 -UserArgs '--test=emg_shots','--emg_part=1','--test-timeout=150','--seed=7','--disable=police,wildlife,shops,garage,transit,taxi,activities,radio,respawn,debug'
tools\godot.ps1 -Mode window -Frames 720 -TimeoutSec 200 -UserArgs '--test=emg_shots','--emg_part=2','--test-timeout=150','--seed=7','--disable=police,wildlife,shops,garage,transit,taxi,activities,radio,respawn,debug'
tools\godot.ps1 -Mode headless -Frames 2400 -TimeoutSec 240 -UserArgs '--test=emg_leak_probe','--test-timeout=200','--disable=police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
```

`emg_api` (46 checks) - see the header of the file; results are in the final report.

---------------------------------------------------------------------------------------------------

## 6. Known limits / missing assets

- **No hose / nozzle model** and no stretcher / medical bag: the spray pose holds an empty two-handed grip
  with the water jet from the right hand; medics do CPR on the spot, bodies are not loaded into the
  ambulance (missing assets - not substituted).
- **No dedicated sounds**: the jet hiss reuses `rain_loop`; there is no radio chatter / medic voice.
- `set_siren(on)` switches lights AND sound together (VEHICLE module): at a scene the siren keeps
  wailing while the lights flash. A lights-only mode would need a vehicle API (request to lead).
- Free-standing ground fires (molotov, explosion `fire: true`) are not reachable through a public Fx API:
  they burn out by themselves (6-9 s); the brigade cools the spot. `Fx.extinguish(position, radius) -> int`
  is called if the Fx module adds it (request to lead).
- Responders exit through the vehicle's own exit markers: the driver steps out on the traffic side.
- The kneel pose sinks the visual 0.24 m on a crouch: the shins go slightly into the ground (reads as
  kneeling from normal camera heights).
