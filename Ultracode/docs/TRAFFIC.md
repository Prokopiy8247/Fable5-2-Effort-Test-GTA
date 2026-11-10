# HALCYON BAY - TRAFFIC module (`gta/code/traffic/`)

Owner: traffic programmer (Wave 2). Contracts: `docs/ARCHITECTURE.md` 6.8, `docs/ARCHITECTURE_WAVE2.md`
W2.1. Builds on `RoadGraph` (`docs/WORLD.md` section 6), `VehicleBase` (`docs/VEHICLES.md`), `CharacterVisual` +
`HumanoidAnimator` (`docs/CHARACTERS.md`, `docs/PLAYER.md` section 6). Soft dependencies only: the RoadGraph,
vehicles, characters and NPCs are reached untyped (`Game.world.roads`, `Game.get_system("vehicles")`,
`Game.spawn_vehicle`, `Game.spawn_npc`, `has_method`), never by their class names.

---------------------------------------------------------------------------------------------------

## 1. Files

| file | class | what it is |
|---|---|---|
| `traffic_system.gd` | `TrafficSystem` (Node3D) | world system `traffic`: the one manager loop (decisions, spawning, tiers, reactions, visuals, API) |
| `traffic_driver.gd` | `TrafficDriver` (RefCounted) | plain per-car state: lane cursor (lane -> junction curve -> next lane), personality, timers |
| `traffic_lanes.gd` | `TrafficLanes` (RefCounted) | typed cache of the RoadGraph lanes + junction connection paths, turn directions, movement conflict tests |
| `traffic_dummy.gd` | `TrafficDummy` (Node3D) | the seated driver node (= `vehicle.driver`), hosts the pooled humanoid visual when near |
| `traffic_parking.gd` | `TrafficParking` (RefCounted) | parked cars on the world's `parking` bays |
| `gta/tests/trf_flow.gd` | - | headless flow test (section 9) |
| `gta/tests/trf_react.gd` | - | headless reactions test |
| `gta/tests/trf_junction.gd` | - | headless junction stress: unsignalised permits, a van in the box, signals, a motorcycle (review) |
| `gta/tests/trf_police.gd` | - | headless, the REAL police system: 2 stars downtown, cruisers with sirens through traffic (review) |
| `gta/tests/trf_player.gd` | - | headless, the REAL player: ride along, carjack (stopped / moving), aim, dead driver, teleport cut (review) |
| `gta/tests/trf_shots.gd` | - | windowed screenshots |

`taxi_system.gd` / `transit_system.gd` are next-wave files of this module (not written yet).

---------------------------------------------------------------------------------------------------

## 2. Public API (`Game.get_system("traffic")`)

ARCHITECTURE 6.8:

```gdscript
func set_enabled(on: bool) -> void            # off = everything we created is removed, no spawning
func get_vehicle_count() -> int                # simulated traffic cars (with an AI driver, frozen far ones included)
func spawn_traffic_vehicle(lane_id: int, offset: float, spec_id := "") -> Node3D   # ignores view / distance rules, respects the cap;
                                               # null when a vehicle / person occupies the spot; starts at a speed it
                                               # can stop from behind whatever stands ahead
func clear_all() -> void                       # traffic + parked + abandoned cars we spawned (not the player's; a car the
                                               # player rides in stays - its driver gets out)
func set_density(mult: float) -> void          # extra multiplier on top of Settings "traffic_density" (0..2)
```

W2.1 + brief:

```gdscript
func release_vehicle(vehicle: Node3D, reason: String) -> Node3D
	# "carjacked" / "abandon" / "crash" (+ traffic-internal "surrender", "flee"): the driver gets out beside the
	# driver door as a real NPC (Game.spawn_npc, returned; null when the peds system is missing).
	# "despawn" / "destroyed": clean up only. Afterwards: no "ai_controller" meta, vehicle.driver == null.
func set_focus_override(pos: Vector3) -> void  # spawn / despawn around pos instead of the player; Vector3.INF clears
func clear_focus_override() -> void
func get_debug_info() -> Dictionary            # see section 8
func reset_for_respawn() -> void               # forget panic / pending reactions, refill around the new focus
```

Extras (stable): `get_active_count()`, `get_parked_count()`, `get_target_count()`, `get_density_factor()`,
`get_focus()`, `get_drivers() -> Array[TrafficDriver]`, `get_driver(vehicle) -> TrafficDriver`, `is_flowing(d)`,
`is_seen(pos)`, `pick_spec(district, parked) -> String`, `adopt_orphan(v)`, `despawn_vehicle_node(v)`,
`stats` (Dictionary of counters), constants `CAP`, `BASE_TARGET`, `SPAWN_MIN/MAX`, `DESPAWN_DIST`, ...

Every traffic vehicle carries `set_meta("ai_controller", traffic_system)` and `set_meta("traffic_driver_uid", n)`,
`vehicle.driver` is its `TrafficDummy`, `owner_tag` `"civilian"`. Parked cars carry `set_meta("traffic_parked", true)`,
`owner_tag "parked"`.

---------------------------------------------------------------------------------------------------

## 3. Driving

One manager loop in `_physics_process`; **no node and no script per decision**. Every car has a think timer:
15 Hz near (< 60 m from the focus), 5 Hz mid (< 165 m, and far cars that the camera sees), and 15 Hz in any
driving tier while it is faster than 13 m/s, approaches a stop point / junction / leader (< 30 m) or crosses a
junction, so stops and gaps are exact. Between decisions the inputs stay as set (the car's own steering rate
limit smooths them).

**Path**: `TrafficDriver` keeps a cursor (`lane`, `s`) on the RoadGraph lane polyline, the chosen `next_lane`,
and the junction connection curve between them (`RoadGraph.get_connection`, cached in `TrafficLanes`). The car
position is projected onto the current element every decision (local segment search, no allocation); passing the
stop line enters the connection, leaving it enters the next lane and picks the one after. `point_ahead(dist)`
walks lane -> connection -> next lane.

**Next lane** (random turns): weights straight 1.6, right 0.75, left 0.6, U-turn 0.05; arterial x1.3, alley x0.3,
dirt x0.03; lanes into dead ends x0.02 (the hill top / lighthouse U-turns are avoided); panicking drivers prefer
lanes that lead away from the threat. Turn indicators blink 35 m before a turn and during lane changes.

**Steering**: pure pursuit on a look-ahead point 5.5..17 m ahead (+5 m while changing lanes, shorter while off
the path), measured from the rear axle for cars and from a point a quarter wheelbase ahead of the centre for long
vehicles (half length > 2.9 m: box trucks), so a truck's nose does not swing into the opposite stop line when it
turns; road-wheel angle `atan(2 L y / ld^2)` divided by the car's own speed-dependent steering limit (same formula
as `Car._update_steering` / `Bike._update_steering`). A smoothed lateral offset shifts the look-ahead point for
lane-change blending, pulling over for sirens and going around obstacles.

**Target speed** = min of:
- lane limit x personality (0.82..1.1) x weather (`Weather.get_grip_multiplier()`), x1.3 when panicking;
- curve speed: heading change over 5 m chords up to 20..45 m ahead, `sqrt(3.2 m/s^2 / curvature)` (x0.7 on two
  wheels), reachable with 2.4 m/s^2 of braking;
- tracking: while the car is more than 0.35 m off its path or > 10 degrees off its heading (e.g. swinging wide out
  of a turn) it does not accelerate beyond 4.5..20 m/s until it is back on line;
- the leader from the **lane-occupancy table** (rebuilt at 15 Hz into packed arrays: every traffic car on its lane,
  cars inside a junction on both their lanes, cars changing lanes on both lanes, and foreign vehicles - player,
  police, wrecks - projected onto the nearest lane): `min(sqrt(v_lead^2 + 2 b gap'), gap'/headway + 0.3 v_lead)`
  with a 2.3 m standstill gap and 1.0 / 1.3 / 1.6 s headway (aggressive / normal / timid);
- junction control (below) with a stop point 1.0 m before the stop line (`STOP_BACK`; 0.4 m before the review - a car turning right into a side road swept the waiting head car of that road with its front corner);
- the obstacle boxes (below);
- reactions (bump brake, pending exit).

**Pedals**: a feed-forward brake whenever a stop point is close (`a = v^2 / 2d`, about 8 m/s^2 at full brake),
otherwise a P controller. Civilians pull away gently (throttle capped at 0.55 / 0.68 / 0.85 by personality, 1.0
when panicking).

**Obstacles**: one or two box queries (`intersect_shape`, mask VEHICLE | PLAYER | NPC | PROP) that follow the path
ahead of the front bumper (lane -> junction curve), shifted by the lateral offset, 4..22 m long depending on
speed. Because they follow the path, parked cars at the kerb and pedestrians on the sidewalk never stop a car;
pedestrians crossing, the player standing in the road, stopped or crossing vehicles and dynamic props do.

**Junctions** (3+ legs; `TrafficLanes.is_junction`):
1. Signals: red = stop at the line; yellow = stop if it can be done at 4.5 m/s^2, else go; a permit is revoked when
   the light turns red while the car can still stop at 6 m/s^2. Calm drivers never enter on red (counted in
   `stats.red_violations`; panicking drivers may run a red when nothing conflicts, `stats.panic_red_runs`).
2. Right of way at every junction (signalised or not): a car needs a **permit** to pass its stop line. Ranks: 3 a car
   that has waited > 9 s, 2 straight / right on the priority road or on green, 1 left turn across oncoming traffic,
   0 minor approach of a priority junction (`lane.yield`). A car is granted a permit when its signal allows it,
   its exit lane has room (**don't block the box**), no car with a conflicting movement holds a permit or is inside
   the junction, and no *ready* conflicting approaching car (ETA < 5 s) outranks it. Outranking is a strict total
   order `(rank desc, eta asc with 0.25 s tolerance, uid asc)`; conflicts are geometric (the two junction paths
   cross, merge into the same lane, or pass closer than 2.1 m) and cached per pair of movements. Foreign vehicles
   inside the junction box within 3.2 m of the path also block.

   Why it cannot deadlock: a car only ever waits for (a) cars holding a permit / inside the box - they drive on,
   because they were only admitted with room on their exit lane - or (b) ready cars higher in a strict total order,
   so the highest-ordered waiting car is never blocked by anyone who is waiting. The 9 s rank boost prevents
   starvation of minor roads. If an exit lane is blocked by something that never moves, the car at the front of
   that queue goes around / reverses / is despawned (below), which frees the lane. Frozen far cars never hold a
   permit or stand inside a box (they are not frozen there, and freezing clears ready / permit / eta).
3. **Stationary foreign vehicles in the box** (an abandoned or wrecked car, the player's parked car): moving foreign
   vehicles within 3.2 m of the path block the permit as before; a STATIONARY one used to block every movement
   near it for ever (a crash in a junction jammed it). Now a car that waits > 2.5 s because of one runs a physical
   sweep along its junction path + the first car length of its exit lane (`_conn_path_clear`, VEHICLE layer, our
   own moving cars excluded): if it fits past, it goes (`path_clear_ok`); otherwise it takes another exit whose
   path is clear (`_reroute_around_foreign`, dead ends / U-turns last, `stats.reroutes`); otherwise it honks and
   checks again every 2 s.

**Lane changes** (arterial: `TrafficLanes.adjacent`): when the leader is > 3 m/s slower than the car wants to go
(50 % per decision), or rarely at random; never in the last 40 m before a junction; needs a gap of 9 m behind
(+ closing speed) and 10 m ahead on the target lane, and room to finish the move before reaching the slow car
(`lead_gap > 4 m + 1.6 s x closing speed`, else it stays behind); the car is registered on both lanes while it
moves across, and **while it still overlaps its old lane (|cross-track| > 1.1 m) the leader search also covers the
old lane** (review fix: a car that started a change close behind a stopped car kept driving into it, because the
leader search and the obstacle boxes only looked at the new lane). Go-around lane changes (`lc_forced`, blocked by
something that does not move) skip the old-lane check - that obstacle is what they drive around.

**Slower road ahead**: when the next lane has a lower limit (arterial -> street) the free speed is capped by
`sqrt(v_next^2 + 2 B_COMF d)` so the car arrives at the junction at the new limit.

**Turns**: through a junction turn a car drives at most `TURN_V_RIGHT` 5.5 m/s (right turns are the tight corner in
right-hand traffic) / `TURN_V_LEFT` 7.0 m/s (x1.25 when panicking), approached with comfortable braking. Before the
review cars took right turns at up to 9 m/s and swung ~1.2 m wide into the queue of the road they turned into.

**Blocked / stuck** (`TrafficDriver.Block`: NONE, WAIT at a junction, QUEUE behind cars that wait, BLOCKED by
something that does not move): blocked > 3.5 s -> honk (then every 5..9 s); blocked > 8 s (16 s for a pedestrian)
-> go around: lane change if possible, else a bypass through the opposite lane when it is free for 25 m behind /
50 m ahead; failing that, reverse 1.6 s and retry. A bypass that comes to a standstill for 2.5 s (oncoming traffic
arrived head-on, someone stepped in) is given up and the car tucks back in (`stats.bypass_aborts`) - before, two
cars could face each other in one lane for ever. Wedged against something (wants to move, does not) for 6 s ->
reverse. Hopeless (no 4 m of real progress for 30 s while not legitimately waiting / queuing, and unseen; or 75 s
and > 40 m from the camera) -> despawned, never with the player aboard. Reversing back and forth does not count as
progress.

**The player getting in** (`_jack_watch`, every physics frame): while the player is in the PLAYER `vehicle` state
but not seated yet (walking to a door: carjack or ride-along) the traffic car whose footprint is within 4.5 m stops
(`brake_t`, kept topped up while the player is there; `stats.jack_stops`) - the PLAYER module aborts a carjack when
the car moves faster than 3.5 m/s. A driver that is already rolling (> 3 m/s) floors it instead with p 0.45
(aggressive / tough) or 0.12 (others) and leaves the player behind (`stats.jack_escapes`).

**Emergency vehicles**: any vehicle with `siren_on` within 55 m behind / approaching (5 Hz scan) -> pull right
(1.2 m on the outer arterial lane, 0.9 m on streets, 0.5 m beside a parking lane) and slow to 3 m/s; never stops
inside a junction for it and does not pull over in the last 12 m before a junction line (the offset carried into
the turn; inside a junction the offset returns at 3 m/s). Verified against the real POLICE module in `trf_police`.

**Headlights**: on while `WorldClock.get_daylight() < 0.3` (same rule as the VehicleManager). Real SpotLights come
from the VehicleManager's pool (nearest cars), everything else is emissive.

---------------------------------------------------------------------------------------------------

## 4. Population

- **Focus** = `set_focus_override` position, else the player (or the vehicle they sit in), else the camera.
- **Target** = `16 x Settings.traffic_density x set_density() x time of day`, hard **cap 22** simulated vehicles.
  Time of day: 0.32 at night (22-05 h), 1.0 by day, 1.15 at the rush hours (8 h, 17:30 h).
- **Spawn** (2 Hz, 1 car per tick, 3 when refilling): `RoadGraph.random_lane_point(focus, 70, 160)` (uses
  `Game.rng`), only on spawnable lanes (no dirt, no dead ends, arterial > street > alley 0.25), never within 6 m of
  the lane start or 12 m of the stop line, out of the camera view, > 45 m from the real player, free space
  (table + box query), at a speed it can still stop from before the next stop line. **Initial fill** when the game
  is ready (and on `set_enabled(true)`): 30..160 m, in view allowed. After a jump of the focus (> 60 m in 0.5 s)
  the refill runs at 3 per tick from 45 m; a jump of > 110 m within one 0.5 s tick is faster than any vehicle, i.e.
  a teleport / respawn **cut**: the new place is filled at once like the boot fill (in view allowed) and the parked
  bays around it too (one 5..11 ms frame, hidden by the cut).
- **Despawn**: beyond 190 m and unseen, beyond 260 m always, surplus over the target (farthest unseen beyond
  100 m), hopelessly stuck, and released / abandoned cars we spawned ("orphans": beyond 190 m unseen, unless the
  player drove them).
- **Tiers**: near < 60 m (15 Hz, driver visual), mid < 165 m (5 Hz), far: beyond 170 m and unseen the car is
  **frozen** (`RigidBody3D.freeze`, no physics, no decisions; it thaws with its speed when the focus comes within
  160 m or the camera sees it). Frozen cars do not count toward the target; at the cap the farthest frozen one
  makes room. Review fixes: a car is never frozen inside a junction, with a permit or with the player aboard;
  a frozen car that is the leader / obstacle (< 40 m) of a car that still drives is despawned after the manager
  loop (`stats.frozen_blockers`) - before, cars queued behind frozen cars at the 170 m ring for ever (and counted
  as "flowing"), and a car frozen inside a junction held every conflicting movement there.
- **Player aboard** (riding along as a passenger keeps the AI driver): such a car is never frozen, never
  despawned (hopeless / surplus / `clear_all()` / `set_enabled(false)` release the driver with `"abandon"`
  instead, the car stays with the player in it), its driver never abandons it because of gunfire (a drive-by from
  the passenger seat = getaway driving) and the player's aiming from inside it is not a hold-up.
- **Mix** (`MIX`, `DISTRICT_MIX`, only specs that `VehicleManager.can_spawn`): sedan 1.6, compact 1.3, taxi 1.1,
  suv 1.0, pickup 0.9, van 0.8, muscle 0.45, box truck 0.4, sports 0.22, motorcycle 0.15 (when its spec exists).
  Downtown / midtown / airport: more taxis; industrial: vans x2.2, box trucks x3.2, pickups x1.7; residential:
  SUVs / compacts; beach / waterfront: sports / muscle cars. Paint: the VehicleManager's random default colours.
- **Drivers**: npc archetype `taxi_driver` in taxis; `civilian_tough` 30 % in vans / trucks / pickups / sports /
  muscle cars, 12 % otherwise; `civilian_m` / `civilian_f` else. The seated look uses CharacterVisual archetypes
  (`civilian_m`, `civilian_f`, sometimes `business` in sedans / SUVs / sports cars, `beach` near the sea).

---------------------------------------------------------------------------------------------------

## 5. Parked cars (`TrafficParking`)

World `parking` spawn points (284 kerb-side bays on the six parking streets + the two lots). Every second: bays
within 115 m of the focus are filled up to **cap 40** when their stable per-bay roll is below the fill ratio
(0.5 by day, up to 0.64 at night, x density) - the same street looks the same when you come back. Bays inside the
camera view only fill beyond 85 m. Bays closer than 14 m to a junction box are never used (cars turning out of
a junction swing wide; real streets keep junction mouths clear too): 184 of the 284 bays remain. Cars are spawned `{"owner_tag": "parked", "asleep": true, "engine_on": false}`:
a sleeping Jolt body at ride height costs nothing. They wake when touched (Jolt contact), entered (`occupant_enter`)
or damaged (`EventBus.vehicle_damaged` -> `sleeping = false`). A parked car that was moved > 0.6 m, entered,
re-tagged or destroyed leaves the parking list and becomes an ordinary world vehicle (cleaned up later as an
orphan unless the player made it theirs). Untouched parked cars are despawned beyond 165 m when unseen.

---------------------------------------------------------------------------------------------------

## 6. Drivers in the seat (W2.1)

`TrafficDummy` (a plain Node3D, no `_process`) is parented to `vehicle.get_seat_node(0)` with an identity transform
and entered with `vehicle.occupant_enter(dummy, 0)` - so `vehicle.driver == dummy`, the engine runs, `can_enter()`
offers the car for carjacking. Within **60 m of the camera** (dropped beyond 70 m, at most 14, at most 2 new ones
per 0.5 s) the dummy gets a pooled `humanoid.tscn` visual with a `HumanoidAnimator` in `seated_car` (`seated_bike`
on two wheels), `update_rate_hz = 8`, `steer` from the car, hands on the `SteeringWheel` part, LOD 1. Two visuals
are prewarmed when the game is ready (the first instance loads the character part library). The look is
deterministic per driver and remembered, so the NPC that gets out looks the same.

`TrafficDummy` implements the vehicle-side hooks:
- `apply_damage(info)` - the explosion's lethal blast on occupants is remembered;
- `on_vehicle_ejected(vehicle, exit_xform, impulse)` - called by `VehicleBase._evict` (explosion, a carjack that
  calls `occupant_enter` directly, admin eject, VehicleManager despawn). Handled deferred: a despawn just cleans
  up; a car now driven by the player -> reason `carjacked` (NPC beside the door); a destroyed car -> if the driver
  was visible and killed, a real NPC takes the lethal damage (its own module plays death / ragdoll / crime);
  anything else -> `abandon`.

---------------------------------------------------------------------------------------------------

## 7. Reactions

| trigger | reaction |
|---|---|
| light bump (`vehicle_collision`, dv 1.6..6 m/s, health > 45 %) | brake 0.8..1.6 s, honk at the other vehicle / person |
| heavy crash (dv >= 6 m/s or health <= 45 %) | once per car: abandon on foot (`release_vehicle "crash"` once stopped) with p 0.4 normal / 0.7 timid / 0.2 aggressive (always if health < 30 %, burning or on its side); else 70 % drive off fast (panic 10..16 s), 30 % shaken stop 2.5 s |
| gunshot (< 45 m) / explosion (< 75 m) via `EventBus.noise_emitted`, bullets / melee / explosions hitting the car (`vehicle_damaged`) | abandon the car (p 0.25 normal / 0.5 timid / 0.1 aggressive / 0.12 tough, +0.25 when < 14 m and slow, +0.2 for a close explosion) or panic driving 12..20 s: x1.3 speed, 1.3x lateral acceleration, full throttle, turns away from the threat, honks, may run a red light when nothing conflicts |
| car at < 20 % health | abandon |
| the player aims a gun (`is_aiming`, `is_armed()`, `get_aim_ray()`) within 1.2 m of a driver's head from < 13 m for 0.45 s | slow car (< 3.5 m/s): surrender with p 0.6 (0.25 tough / aggressive) -> stops, hazards, gets out and calls `npc.surrender()`; otherwise floor it (panic) |
| siren behind / approaching | pull right, slow to 3 m/s |

NPC reactions after `release_vehicle` (`_spawn_driver_npc`), matched to the AI civilian brain
(`ai_brain_civilian.gd`): `carjacked` -> being dragged out is delivered as a zero-damage melee assault,
`brain.on_event(npc, "damaged", {"attacker": thief, "info": {"type": "melee", "amount": 0.0, "carjacked": true}})`,
so `civilian_tough` (archetype `fights_back`) fights the thief and everybody else screams and runs (without a
brain: `melee(thief)` / `panic(thief_pos)`); the thief is `Game.player` when the caller does not pass one.
`surrender` -> `npc.surrender()` + `"threatened"` `{"by": threat, "duration"}` (hands up / cower / flee);
`abandon` / `crash` / `flee` -> `npc.panic(threat)`. The NPC is spawned with `{"yaw", "appearance"}` (the seated
look) and carries meta `left_vehicle_reason`. PLAYER's `pull_out()` knocks the returned NPC down afterwards; the
brain resumes the fight / flight when it gets up.

---------------------------------------------------------------------------------------------------

## 8. Debug info (`get_debug_info()`)

`enabled, count, active, target, cap, parked, parked_asleep, orphans, tiers [near, mid, far], frozen, moving,
waiting, queue, blocked, visible_drivers, density, time_factor, focus, focus_override` + counters `spawned,
despawned, released, collisions (dv >= 2 m/s, each car of a crash counts), heavy_collisions, red_violations,
panic_red_runs, lane_changes, bypasses, bypass_aborts, reverses, honks, stuck_despawns, npcs_spawned, panics,
surrenders, frozen_blockers, reroutes, jack_stops, jack_escapes, pushed_red_entries (shoved over the line while
braking - not counted as red_violations), track_err_avg, track_err_max, think_ms_avg,
think_ms_peak` (cost of the whole manager step per physics frame; the peak includes the one-frame cut fill). `--trf_log` prints events
(collisions, bypasses, reverses, stuck despawns, red light entries) as `TRAFFIC:` lines.

---------------------------------------------------------------------------------------------------

## 9. Tests

```powershell
$dis = '--disable=police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug,pickups,interactions'
$dj  = '--disable=peds,props,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug,pickups,interactions'
tools\godot.ps1 -Mode check -Dirs 'gta/code/traffic,gta/tests'
tools\godot.ps1 -Mode headless -Frames 8000 -TimeoutSec 480 -UserArgs '--test=trf_flow','--test-timeout=460',$dis,'--seed=1'   # also 2, 3; '--trf_hour=23' for night
tools\godot.ps1 -Mode headless -Frames 6000 -TimeoutSec 300 -UserArgs '--test=trf_react','--no_player',$dis
tools\godot.ps1 -Mode headless -Frames 10000 -TimeoutSec 450 -UserArgs '--test=trf_junction','--test-timeout=430','--no_player',$dj
tools\godot.ps1 -Mode headless -Frames 6000 -TimeoutSec 380 -UserArgs '--test=trf_player','--test-timeout=350',$dis
tools\godot.ps1 -Mode headless -Frames 4200 -TimeoutSec 300 -UserArgs '--test=trf_police','--test-timeout=280','--disable=emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug,pickups,interactions'
tools\godot.ps1 -Mode window   -Frames 700  -TimeoutSec 120 -UserArgs '--test=trf_shots','--no_player',$dis
```
Add `'--trf_log'` to any run for the `TRAFFIC:` event lines (collisions, frozen blockers, reroutes, jack attempts ...).
(`$dis` keeps unrelated systems out; traffic itself needs only world + vehicles; `peds` is needed for the NPC
checks (drivers leaving cars) and makes pedestrians cross in front of the cars; `city`, `props` and `environment`
make the shots look right. During Wave 2 `props` and `player` were briefly mid-edit by neighbours: if one of them
aborts the boot, add it to `$dis` - the traffic tests do not need them.)

- `trf_flow` (`--seed=N`, `--trf_hour=H`, `--trf_secs=S`): focus override downtown (Meridian Avenue), 60 s sampled
  every 0.5 s; then the focus DRIVES a 250 m RoadGraph route at 13 m/s (phase M); then it jumps 250 m (a teleport
  cut) for 20 s. Checks: >= 8 cars all the time (night: 60 % of the target), >= 80 % flowing (moving / waiting at a
  junction / queuing behind such), >= 45 % moving, longest non-flowing stretch < 30 s, nobody upside down, no red
  light violation, cars waiting at red stand behind the stop line (<= 0.8 m over), < 0.35 impacts per
  vehicle-minute, lane keeping, manager cost < 1.5 ms; population around the moving focus; the cut fills the new
  place within 1 s; old cars despawned / population rebuilt; whole run (review): no car stands still >= 50 s (the
  phase-1 "flowing" metric counts a car waiting at a junction for ever as flowing - this one does not), longest wait
  at an unsignalised junction < 20 s, calm drivers <= 1.2 x the lane limit, heading along the lane direction,
  no driving car held up by a frozen far car, every lane right of its road centre line (right-hand traffic),
  headlights at night; `release_vehicle` contract, parked cars exist / stay asleep / tagged.
- `trf_junction` (review): the unsignalised junction with the most approaches gets a car on every approach every
  2.5 s for 50 s (crossings, longest wait, standstill, collisions); an abandoned van off-centre in its box (reroutes,
  crossings continue); a van dead in the centre (drivers honk); the same stress at a signalised junction plus a
  motorcycle (lean, lane keeping, no red violation, no collision).
- `trf_police` (review, the REAL police + peds): the invulnerable player gets 2 stars downtown for 40 s: police
  units arrive with sirens, traffic drivers yield (`siren_t`), the population stays up, no calm red-light runner,
  no gridlock; contacts between traffic and police cars are counted.
- `trf_player` (review, the REAL player + peds): ride along (hold the enter key at the passenger door -> seat 1,
  the AI keeps driving, `clear_all()` keeps the car and lets the driver out), carjack of a waiting car (NPC
  "carjacked" beside the car, player drives), carjack of a car rolling at ~8 m/s (it brakes for the entry), the
  real player aiming a pistol at a waiting driver (surrender / flee), the car exploding with a visible driver
  (a real NPC takes the lethal blast), teleport cut (traffic around the new place after 1 s, old cars gone).
- `trf_react`: gunfire, bump, heavy crash (+ forced flee on foot with hazards), siren yield, a stand-in player
  aiming at a waiting driver, carjack through `occupant_enter` (eviction path), explosion with the driver aboard,
  lane change behind a slow car on the arterial, a stalled van in a one-lane street (honk -> bypass through the
  opposite lane -> past it), release reasons; with the peds system: NPC beside the door with the driver's
  archetype, carjacked driver reacts, `civilian_tough` fights back. The NPC checks run when the peds system is
  present (it is with `$dis` above).
- `trf_shots`: `qa/screenshots/trf_junction_day.png`, `trf_queue_day.png`, `trf_driver_close.png`,
  `trf_junction_night.png`, `trf_street_night.png`.

Measured by the reviewer (2026-11-10, headless, 16 cars + up to 40 parked, ~110 simulated seconds per trf_flow run,
with pedestrians), seeds 1 / 2 / 3 by day and seed 4 at 23 h: all PASS. Manager step 0.29..0.38 ms per physics
frame on average by day (0.20 ms at night with ~7 cars; decisions, table, box queries, spawning - the vehicles' own
physics is the vehicle module's); peak 2..3 ms on frames that spawn a car or attach a driver visual (two visuals are
prewarmed at boot: before that the first attach cost 74 ms), 10..20 ms on the single frame of a teleport cut fill.
Flow: 96..98 % of the cars flowing, 73..84 % moving, 8.5..9.2 m/s average speed, 0 collisions in every review flow
run, 0 red light violations, longest standstill of any car 10.5..12 s (a red phase), calm drivers <= 1.11 x the lane
limit (after the hold-throttle fix; 1.21 before), lane tracking 0.05 m average / 0.75..0.94 m max (one seed showed
1.52 m: a muscle car swinging wide out of a tight right turn), 0 heading violations in ~2000 samples per run,
4..11 frozen blockers removed per run, 0 ring stalls. Moving focus: 14..15 cars stay active, 8..10 within 110 m.
Teleport cut: 14 cars around the new place after 1 s (7 at night = the whole target). trf_junction: unsignalised
stress 34..41 crossings per 50 s with the longest wait 1..5 s and 0 collisions; a van in the box: 22 crossings,
4 reroutes; signalised: 21..24 crossings per 40 s, 0 red violations. trf_police (real police, 2 stars, 40 s):
7..10 police units, 4..9 traffic drivers yielded to sirens, 0 traffic-police contacts, 0 calm red violations in the
two final runs (an earlier run logged one red entry at 1.4 m/s while braking - most likely shoved; such entries are
now counted separately as `pushed_red_entries`).

---------------------------------------------------------------------------------------------------

## 10. Integration notes

- **PLAYER (carjacking)**: before entering a car whose `driver` is not the player, call
  `vehicle.get_meta("ai_controller").release_vehicle(vehicle, "carjacked")` (check `has_meta` / `has_method`);
  the returned NPC stands beside the driver door (null without the peds system) - animate the pull-out with it.
  Entering through `occupant_enter` without calling release first also works (the dummy is evicted and the NPC is
  spawned one frame later) but then there is no NPC to animate. Verified end to end with the real Player in
  `trf_player` (PlayerVehicleInteraction.pull_out -> release_vehicle "carjacked" -> NPC knocked down -> player drives).
  Traffic watches the Player's public `get_state_name() == "vehicle"` + `Game.get_player_vehicle() == null` (walking
  to a door) to stop the car being entered; the PLAYER module aborts a jack above 3.5 m/s, so a car rolling faster
  than ~10 m/s cannot be stopped inside the player's abort distance (9.5 m) - only slower cars can be jacked.
  Riding along (hold the key, seat 1) keeps the traffic driver: verified, see section 4 "Player aboard".
- **AI (NpcBase / brains)**: the module only calls `Game.spawn_npc(archetype, pos, {"yaw", "appearance"})`,
  `panic(from)`, `surrender()`, `melee(target)` (fallback), `apply_damage(info)` (dead driver) and
  `brain.on_event(npc, "damaged" | "threatened", ...)` as described in section 7. A dedicated brain event
  "carjacked" would be cleaner than the zero-damage melee "damaged" event (request to the AI owner).
- **POLICE**: the police module now exists with its own `PoliceVehicleAi` (its own `ai_controller`); traffic only
  reads `siren_on` and treats police cars as foreign vehicles (lane table, junction box). `PoliceSystem.adopt_patrol`
  calls our `release_vehicle(v, "despawn")` before it takes a car (no NPC, not an orphan afterwards). Police can
  also stop a traffic car with `release_vehicle(v, "abandon")`. Verified together in `trf_police` (6 drivers yielded
  to sirens in 40 s, 0 traffic-police contacts).
- **UI / admin**: `set_enabled`, `set_density`, `clear_all`, `get_debug_info`. `set_density(mult)` is a multiplier
  ON TOP of Settings `traffic_density` (ARCHITECTURE 6.8; the PedSystem does the same). NOTE: the current
  `debug_system.set_density("traffic", x)` writes Settings `traffic_density = x` AND calls `set_density(x)`, so the
  admin slider applies x twice (0.5 -> 0.25, 1.5 -> 2.25 -> capped). Reported to the lead; traffic keeps the
  documented contract.
- **Taxi / transit (next wave)**: reuse `TrafficLanes` + `TrafficDriver` (cursor, `point_ahead`, pursuit) - a
  taxi job is a driver whose `choose_next` follows `RoadGraph.find_lane_route`. The tram shares the inner lane
  of its loop; traffic treats any body in its path as an obstacle, so a tram node on `Layers.VEHICLE` is respected.
- **Vehicle caps**: VehicleManager `max_vehicles` 90 never removes cars that have a driver; traffic keeps its own
  cap (22 + 40 parked + orphans).

## 11. Known limits

- Driver NPCs (abandon / carjack / surrender / dead driver) need the `peds` system (`Game.spawn_npc`); without it
  `release_vehicle` returns null and the driver simply disappears. Verified with peds in `trf_react` (surrender,
  carjack flee, tough fights back) and `trf_player` (real carjack, dead driver after an explosion - the corpse NPC
  carries meta `left_vehicle_reason = "killed"`; only drivers that were drawn near the camera leave a body).
- The carjacked civilian's brain currently goes into its "witness" mode after the pull-out (AI module behaviour).
- The obstacle boxes follow the path; something beside the path that the car is about to clip because it has
  drifted off the path is only handled by physics (rare: cars track within ~0.6 m; up to ~1.2 m on a few turn
  exits / lane kinks, e.g. lane 150 near (-120, -206)).
- No cooperative merging: a car waiting to change lanes does not make the neighbour slow down.
- Bypasses go through the opposite lane of two-lane streets only when it is free; on a blocked one-lane street with
  oncoming traffic the car waits / reverses and may be despawned when unseen. A bypass that meets oncoming traffic
  head-on is given up after 2.5 s (the oncoming car then has to wait / go around itself).
- A vehicle standing dead in the middle of a small junction box blocks every movement: the waiting cars honk and
  are despawned when unseen (30 s), but while the camera watches they wait (no driving over the kerb / pushing).
  Cars do not drive around such a vehicle INSIDE the box (only another exit or a physical "it fits" check).
- No traffic on the airport taxiways, the runway, dirt tracks (spawning) or the two dead-end lanes.
- Frozen far cars stand still while frozen (only beyond 170 m and outside the camera view); one that holds up a car
  that still drives is despawned.
- A teleport / respawn cut costs one ~10..20 ms frame (CUT_FILL 10 cars + 10 parked cars spawned by the vehicle
  module at ~1.5..1.8 ms each); the boosted refill adds the rest over the next 2 s.

## 12. Independent review (2026-11-10) - what was found and fixed

Found by reading the code against the contracts and by the new tests (all fixes keep the public names):
1. Freezing could happen inside a junction / with a permit -> the frozen car held every conflicting movement there.
2. Cars queued for ever behind frozen cars at the 170 m ring (counted as "flowing") -> frozen blockers despawned.
3. A car with the player riding along could be despawned under the player (clear_all, set_enabled(false),
   hopeless) -> never; the driver gets out instead. No abandoning / hold-up reactions toward the player's own ride.
4. Carjacking a rolling car always failed (the PLAYER module aborts above 3.5 m/s, traffic never reacted) ->
   drivers stop for the player walking to their door (some floor it).
5. A stationary foreign vehicle in a junction box (crash wreck, abandoned car) blocked every movement near it for
   ever -> physical path sweep, reroute to another exit, honking, not "legit" for the hopeless check.
6. Bypass standoff (two cars head-on in one lane) -> a stalled bypass is given up after 2.5 s.
7. Lane-change collision with a stopped car in the OLD lane (seen with --seed=1) -> leader search covers the old
   lane while the car still overlaps it; lane changes need room to finish.
8. spawn_traffic_vehicle() started cars at up to 9.8 m/s right behind a stopped car, or inside an abandoned car
   (dv 10 explosion apart) -> v0 limited by the free space ahead; an occupied spot returns null.
9. Speed hold band let cars sit ~0.9 m/s above the target (1.21 x the limit on 7 m/s alleys) -> stiffer hold.
10. No anticipation of a slower next lane -> capped by the braking distance.
11. Teleport / respawn cut: traffic trickled in out of view for seconds -> immediate fill (10 cars + 10 bays).
12. Turning cars swept the head car waiting at a side road's stop line / swung wide into the opposite lane ->
    cars wait 1.0 m behind the line and take turns at <= 5.5 m/s (right) / 7.0 m/s (left).
13. Panic honk probability per decision (tier dependent) -> per second.
14. Siren pull-over offset carried into a junction turn (a van clipped a pedestrian on the corner) -> no pull-over
    in the last 12 m before a junction line, faster offset return inside a junction.
15. bool(null) on optional properties (stand-in players, non-vehicle colliders) -> null-safe comparisons.
16. Go-around lane change right at the stop line could put the cursor past the neighbour lane's end -> not in the
    last 15 m before a junction. Red entries while braking (shoved) counted as `pushed_red_entries`.
Not fixed here (other owners): `debug_system.set_density` applies the traffic density twice (section 10).
