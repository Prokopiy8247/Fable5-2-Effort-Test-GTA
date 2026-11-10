# HALCYON BAY - Aircraft (helicopters and airplanes)

Owner: aircraft programmer (Wave 2). Contract: `docs/ARCHITECTURE.md` 6.5, `docs/ARCHITECTURE_WAVE2.md` W2.8.
Builds on the vehicle framework (`docs/VEHICLES.md`) and the aircraft art (`docs/AIRCRAFT_ASSETS.md`).

## 1. Files

| file | class | what it is |
|---|---|---|
| `gta/code/vehicles/helicopter.gd` | `Helicopter` (extends `VehicleBase`) | heli_civil, heli_police: rotor model, collective / cyclic / pedals, autopilot, searchlight, rotor strikes |
| `gta/code/vehicles/plane.gd` | `VehiclePlane` (extends `VehicleBase`) | plane_prop, plane_jet: lift / drag / stall model, 3-leg gear, brakes, flaps, spoilers |
| `gta/code/vehicles/aircraft_spawner.gd` | - (node "AircraftSpawner") | parks aircraft at the world's heli / plane points at boot, brings them back later |
| `gta/resources/registries/vehicles_air_registry.gd` | - | the four `VehicleSpec`s + flight tuning in the spec metadata `"air"`; adds the spawner node |
| `gta/tests/air_heli.gd`, `air_plane.gd`, `air_shots.gd` | - | tests (section 9). `air_showcase.gd` belongs to the aircraft ARTIST, not to this module |

**Class name note:** the contract reserved `Plane`, but `Plane` is a built-in Godot type (the math plane),
so a script cannot use it as `class_name` ("Class Plane hides a built-in type"). The class is
`VehiclePlane` (inside the VEHICLE prefix `Vehicle*`). `VehicleManager` loads both scripts by path
(`CLASS_SCRIPTS["heli" / "plane"]`), so nothing else changes. Neighbours should not type against either
class: use `vehicle_class == "heli" / "plane"` and `has_method()`.

No edits were made to `vehicle_base.gd`, `car.gd`, `vehicle_manager.gd` or `vehicle_spec.gd`.

## 2. Controls (keyboard; `InputSetup` air_* actions)

| action | helicopter | airplane |
|---|---|---|
| W / S (`air_throttle_up/down`) | collective: hold W = climb, S = descend, neither = hold height | throttle lever (persistent; moves 0.5 / s). S with the lever closed on the ground = wheel brakes |
| arrows / numpad 8 5 4 6 (`air_pitch_*`, `air_roll_*`) | cyclic: tilt toward the target pitch / bank; release = level out and stop | pitch rate / roll rate (stick); release roll = gentle wings-level |
| A / D (`air_yaw_*`) | pedals: yaw rate | rudder in the air, nose-wheel steering on the ground |
| Space (`handbrake`) | - | wheel brakes |
| L (`headlights`) | landing lights | landing lights |
| T (`siren`) | heli_police: searchlight on / off (straight ahead-down) | - |
| G (`air_gear`) | - | notifies "Fixed landing gear" (both GLBs have fixed gear, see section 10) |
| F (`enter_vehicle`) | enter / leave. Leaving above 2.5 m puts the player beside the door in the air (fall / parachute) | same |

Mouse look orbits the aircraft camera (player camera rig mode `aircraft`). Mouse flight control was not
added: the mouse already drives the camera.

## 3. Helicopter model (`helicopter.gd`)

All forces in `_integrate_vehicle` (60 Hz, Jolt), no kinematic cheats.

* **Rotor rpm** `rotor_rpm` 0..1 spools up in `spool_up` s (4 s civil, 3.5 police) after `start_engine()`
  (entering the pilot seat starts it) and winds down in `spool_down` s. Thrust scales with rpm^2, so it
  only lifts off at ~80 % rpm.
* **Collective**: the stick (`in_power` 0..1, player W/S = 0.5 +- 0.5) is a **vertical-speed command**
  (0.5 = hold, 1 = `climb_rate`, 0 = `descent_rate`). A P-loop with drag feed-forward turns it into blade
  pitch `collective` (rate limited). Landing assist: within 8 m of the ground the commanded descent is
  limited to `1.1 + 0.7 * agl` m/s. On the ground a neutral stick stays at flat pitch (`GROUND_IDLE`).
* **Thrust** = collective x weight x `lift_ratio` x rpm^2 x damage power factor (`get_power_factor()`,
  plus a surging engine below 25 % health) x density factor (falls to below 1 g at the service ceiling
  `ceiling`, ~350 m) x (1 + **ground effect** up to +16 % within ~0.9 rotor diameters + **translational
  lift** up to +11 % from 4-13 m/s, -4 % at very high speed). The two bonuses are outside the loop, so
  you feel the cushion on landing and the climb when accelerating.
* **Cyclic** = attitude command: target pitch `in_pitch * max_pitch`, bank `in_roll * max_roll`; a PD
  law (gain `attitude_gain`, damping `attitude_damp`) computes angular acceleration, torque = inertia x
  that, so tuning does not depend on the GLB's box inertia. Released stick: **self-levelling** with a
  gain of 50-100 % (Skills "flying") minus up to 25 % in bad weather, plus a hover assist that leans
  against the ground speed below ~18-40 m/s (stops drift, flares to a stop).
* **Pedals**: yaw-rate command; above ~6 m/s the tail weathervanes into the relative wind.
* **Drag**: horizontal quadratic (derived so full forward cyclic reaches `top_speed`) + linear, vertical
  disc drag. **Wind**: `Weather.get_wind_vector()` (x4 m/s) drifts it a little.
* **Turbulence**: smooth pseudo-random angular accelerations, amplitude 0.22 x (1 - flying skill) +
  wind / storm / rain terms; only in the air. AI pilots fly with skill 0.75.
* **Contacts**: the skids are part of the `Col_Body` hull (`hull_clearance` 0, friction 0.85).
* **Damage**: hull impacts through the shared `VehicleDamage.on_collision` (x `collision_damage_scale`);
  touchdown sink above `hard_landing_sink` (4.5 m/s) adds `(sink - 4.5) * 45`; **rotor strikes**: two rays
  sweep the disc each physics step (`STRIKE_MASK` = world, vehicles, props, characters): 70 x rpm damage,
  the rotor loses 22 % rpm, sparks + metal impact + a yaw / roll jolt, whatever was hit takes damage too;
  an impact with a velocity change above `crash_explode_dv` (17 / 18 m/s) **explodes** it; water entry
  above 14 m/s damages it; the base water check floods the engine (stall, sinks, auto-exit).
* **Rotor visuals**: `Rotor_Main` (local Y) and `Rotor_Tail` (local X) spin with rpm; between 32 % and
  80 % rpm the blades fade (`GeometryInstance3D.transparency`) into the `RotorBlur_Main` disc (shadow
  casting off). Far helicopters (detail level 2) still spin their rotors (cheap transform writes only).
* **FX**: `Fx.rotor_wash(ground_point, strength)` under the disc within 22 m of ground or water
  (dust ring / white spray), dust puff on a hard touchdown, sparks on rotor strikes.
* **Lights**: red anti-collision beacon (the `M_Taillight` material) flashes while the engine runs;
  heli_police belly strobes (`M_Siren_Red/Blue`) flash; landing lights through `set_headlights()`.
* **Searchlight** (heli_police `Searchlight` part): `set_searchlight(on, target)` creates one
  `SpotLight3D` (no shadows, 140 m, energy by daylight) and a faint additive beam cone (procedural VFX
  mesh + shader, brighter at night via `gta_night`); the gimbal slews toward `target` (never up into the
  fuselage), `Vector3.INF` = rest pose (forward-down).
* **Soft world limit**: a player helicopter beyond `Game.WORLD_SOFT_LIMIT` (1500 m) is pushed back,
  its nose is turned toward the island, and `UI.notify("Airspace limit - turning back to Halcyon Bay")`
  appears (every 8 s while outside).

## 4. Airplane model (`plane.gd`, class `VehiclePlane`)

* **Throttle** `throttle` 0..1: player W/S move the lever; AI `in_power` (or `set_throttle()`) sets
  the wanted lever. `engine_power` spools after it (prop 0.45 s, jet 1.3 s); `prop_rpm` 0.2 idle .. 1.
  Thrust along the nose = `thrust` x engine_power x damage power factor x (1 - `thrust_fade` x v / top).
* **Lift** = k x CL(alpha) x V^2 perpendicular to the airflow, k = m g / (`cl_max` x `stall_speed`^2)
  (so the 1 g stall speed is exact). CL = `cl0` + `cl_alpha` x alpha (+ `flap_cl` x flaps) up to the stall
  angle, then it collapses to ~50 % and keeps falling with alpha (also a negative stall). Capped at
  5.5 g. A little ground effect (+10 % at zero height over a span) helps the flare.
* **Stall**: `stall_amount` 0..1 (smooth over ~4 degrees past the stall angle): CL drops, drag rises,
  control authority falls by up to 55 %, a nose-down moment drops the nose, a wing rocks. `is_stalled`.
  The player gets `UI.notify("STALL - lower the nose")` (every 6 s at most).
* **Drag**: parasite `drag` x (1 + 0.8 flaps^2 + 0.6 spoilers) x V^2 + induced k x `induced` x CL^2 x V^2
  + stall drag; fuselage side force against sideslip.
* **Controls**: pitch-rate / roll-rate / yaw-rate commands with authority = airspeed / `authority_speed`
  (and the flying skill +-5 %); pitch stability (the nose follows the airflow - weak while the wheels are
  down so the elevator can rotate about the main gear, max 11 degrees nose-up on the ground = no tail
  strike); yaw stability + automatic turn coordination in a bank; gentle wings-level without roll input.
* **Flaps** (automatic): full below 1.3 x stall speed, retracted above 1.75 x; a take-off setting (60 %)
  while the throttle is above 60 %. `Flap_L/R` move with them. **Spoilers** (jet, `ground_spoilers`):
  on the ground with the nose wheel down and the throttle closed they dump lift and add drag.
* **Gear**: one suspension ray per leg (`Wheel_Nose`, `Wheel_L`, `Wheel_R`, radius from the mesh). The
  spring is built around the modelled pose (each leg carries its static share at rest -> the plane
  stands exactly as authored), 2.2-2.3 Hz, damping ratio 0.55 / rebound x1.4, bump stop. Tyres: rolling
  resistance, brakes on the main wheels (`brake_decel`, ABS-like cap at the tyre grip, `Weather` grip),
  side grip, nose-wheel steering with `in_yaw` (`steer_deg`, fading to 5 degrees at 30 m/s). Parking
  brake while stopped with the throttle closed. Sleeps when parked (zero cost), wakes on throttle.
* **Damage**: touchdown sink above `touchdown_sink` (3.2 / 3.6 m/s) adds `(sink - limit) * 85` + crash
  sound + shake; wing / tail / belly strikes through the hull collisions; explosion above
  `crash_explode_dv`; **ditching**: water entry above 22 m/s damages it, the base water code floods the
  engine, it floats low with heavy water drag and sinks (`UI.notify("Ditched in the sea")`).
* **Visuals**: `Propeller` (local Z) spins with `prop_rpm` and fades into `PropBlur` (shadow off);
  `Aileron_L/R`, `Elevator`, `Rudder`, `Flap_L/R` deflect about their local axes on top of the rest
  transform (aileron 18, elevator 20, rudder 22, flaps 26 degrees); wheels roll and show +-5 cm of
  suspension travel; the jet `Canopy` opens (38 degrees) while parked with the engine off and briefly for
  boarding; red beacon flashes while the engine runs. No brake lamps (`is_braking()` false).
* **Soft world limit**: as the helicopter, but by banking back toward the island.

## 5. Specs (`vehicles_air_registry.gd`) and measured behaviour

| id | name | mass kg | health | seats | measured (headless tests on the real map) |
|---|---|---|---|---|---|
| `heli_civil` | Bayflyer 204 | 1500 | 900 | 4 | rotor spool 4 s; 0 -> 30 m AGL in 4.7 s (8 m/s); 150 m forward in 9.8 s (98 km/h); slows to 27 km/h 7 s after releasing the cyclic; 180 degree pedal turn ~2.4 s; hover drift 1.9 m in 6 s; touchdown 1.6 m/s with no damage; 9 m drop: 900 -> 427 hp |
| `heli_police` | HBPD Air One | 2300 | 1400 | 4 (+ gunner bays in the GLB) | tuned stronger (lift ratio 1.75, climb 10 m/s, top 56 m/s - not separately measured), searchlight (tested), strobes, fixed livery |
| `plane_prop` | Bayhopper 318 | 1100 | 850 | 4 | stall speed 24 m/s; lift-off after **164 m** at 27.6 m/s; climbs ~3.5 m/s at 40 m/s; idle + 16 degree nose-up stalls at 20.3 m/s (AoA 15.7); recovers in 2.9 s losing 11 m; 180 degree turn in 17 s at ~40 degree bank; touchdown 1.1 m/s at 32.5 m/s, stops after 173 m |
| `plane_jet` | Swiftline 900 | 4500 | 1000 | 2 | stall speed 38 m/s; lift-off after **242 m** at 44.6 m/s; designed top speed ~112 m/s (thrust = drag, not measured); short-final touchdown 2.4 m/s at 50.2 m/s, stops after 229 m (ground spoilers) |

Runway 09-27 is 380 m (x -170..210, z -264); `airport_runway_start` is at x -150, so 360 m are available.

### `air` metadata fields (defaults in the class scripts)

Helicopter: `lift_ratio`, `climb_rate`, `descent_rate`, `max_pitch_deg`, `max_roll_deg`, `yaw_rate_deg`,
`attitude_gain`, `attitude_damp`, `yaw_gain`, `top_speed`, `spool_up`, `spool_down`, `ceiling`,
`weathervane`, `crash_explode_dv`, `hard_landing_sink`, `searchlight`.

Airplane: `stall_speed`, `cl_max`, `cl0`, `cl_alpha`, `flap_cl`, `thrust`, `thrust_fade`, `drag`, `induced`,
`pitch_rate_deg`, `roll_rate_deg`, `yaw_rate_deg`, `authority_speed`, `throttle_rate`, `brake_decel`,
`steer_deg`, `gear_hz`, `gear_bump`, `gear_droop`, `crash_explode_dv`, `touchdown_sink`, `prop`,
`ground_spoilers`. Generic `VehicleSpec` fields used: `mass`, `com_height`, `inertia_scale`,
`hull_clearance`, `hull_friction`, `collision_damage_scale`, `top_speed` (plane thrust fade), `max_health`,
`seats`, `cam_*`, `sound_engine`, `engine_pitch_min/max`, colours, `fixed_livery`, `allowed_mods` (none).

Tuning hints: take-off distance -> `thrust`, `cl0`, `stall_speed`; landing roll -> `brake_decel`, `cl0`,
`drag`, spoilers; glide angle / approach speed control -> `drag` (L/D); stall character -> `cl_alpha`,
`cl_max`; heli climb / hover margin -> `lift_ratio`, `climb_rate`; heli twitchiness -> `attitude_gain` /
`attitude_damp`; how fast a released heli stops -> the hover assist in `_integrate_vehicle`.

## 6. Public API (in addition to the `VehicleBase` contract)

```gdscript
# Helicopter
var rotor_rpm: float; var collective: float; var lift_force: float; var altitude_agl: float
var vertical_speed: float; var airspeed: float; var on_ground: bool; var rotor_diameter: float
var ground_effect: float; var translational_lift: float; var turbulence: float
var searchlight_on: bool; var searchlight_target: Vector3; var autopilot_mode: String  # "", "fly_to", "hover", "orbit"
var last_touchdown_sink: float; var rotor_strikes: int
func set_flight_inputs(pitch, roll, yaw, power)      # power 0.5 = hold height (cancels the autopilot)
func fly_to(position: Vector3, altitude := INF, cruise_speed := 24.0)   # altitude = world Y; INF = current
func hover_at(position: Vector3, altitude := INF)
func orbit(target_position: Vector3, radius := 40.0, altitude := INF, speed := 14.0, direction := 1.0)  # nose toward the target
func set_autopilot_target(position: Vector3, altitude := INF)   # move the target without resetting the mode
func set_autopilot_heading(heading: float)                       # radians, 0 = north; INF = automatic
func stop_autopilot(); func is_autopilot_active() -> bool
func set_searchlight(on: bool, target_position := Vector3.INF); func has_searchlight() -> bool
func get_telemetry() -> Dictionary;  func get_camera_params() -> Dictionary   # distance grows with speed

# VehiclePlane
var throttle: float; var engine_power: float; var prop_rpm: float; var airspeed: float
var vertical_speed: float; var altitude_agl: float; var angle_of_attack: float (deg); var sideslip: float (deg)
var stall_amount: float; var is_stalled: bool; var on_ground: bool; var gear_contacts: int
var flaps: float; var spoilers: float; var brake: float; var gear_down: bool (always true)
var lift_force: float; var thrust_force: float; var last_touchdown_sink: float; var stall_speed: float
func set_flight_inputs(pitch, roll, yaw, power)      # power = wanted throttle 0..1
func set_throttle(value: float); func set_brakes(amount: float)
func get_attitude_degrees() -> Vector2               # (pitch + nose up, bank + right wing down)
func get_heading() -> float; func get_telemetry() -> Dictionary
```

Both report `speed_kmh` as the total speed (not only the forward component), `get_rpm_factor()` =
rotor / propeller speed, `get_engine_load()` = collective / engine power.

## 7. AI hooks - next wave's police helicopter

```gdscript
var heli := Game.spawn_vehicle("heli_police", xform, {"owner_tag": "police"})
heli.set_meta("ai_controller", self)          # W2.1
heli.driver = pilot_npc                       # or a seated dummy (occupant_enter(npc, 0) starts the engine)
heli.call("orbit", Wanted.last_known_position, 45.0, Wanted.last_known_position.y + 40.0)
heli.call("set_searchlight", true, Wanted.last_known_position)   # call again with the new target each tick
heli.call("set_autopilot_target", new_target)                    # chase without resetting the orbit
heli.call("fly_to", base_pad.origin, base_pad.origin.y + 30.0); heli.call("hover_at", pad, pad.y)  # return + land
```
The autopilot keeps the engine running, never descends faster than 1.5 m/s in the last 6 m and lands
when the target altitude is the ground (neutral collective on the ground = flat pitch). It writes
`in_*` every physics frame while `autopilot_mode != ""` and the player is not flying; `release_inputs()`
or `set_flight_inputs()` stop it. Orbit speed is clamped so the circle stays flyable (~12 m/s at 35 m).

## 8. Free-roam access - parked aircraft (`aircraft_spawner.gd`)

At `EventBus.game_ready` (+2 physics frames) the spawner (child "AircraftSpawner" of the Registry
autoload, created by the registrar) parks, with `owner_tag "parked"`, asleep:

| slot | spec |
|---|---|
| heli point at `airport_helipad` (95, -217) | heli_police (police air unit; taking it is police vehicle theft - reported by the player module) |
| heli point at the harbour helipad (-262, 240) and any other heli point | heli_civil |
| `rooftop_helipad` (only if a roof is really there and no heli point covers it) | heli_civil |
| plane points on the apron (-215 / -185, -247) | plane_prop, plane_jet |
| 12 m inside the `airport_hangar` door (only if the space is free) | plane_prop |

The runway-start plane point is skipped on purpose (the runway stays clear for take-offs). Every
placement is ray-checked (ground within 1.6 m, flat) and box-checked (clearance); blocked slots are
skipped. Wrecked / removed slot aircraft come back after 45 s, flown-away ones after 120 s, never within
120 m of the player. `get_parked()`, `get_slots()`, `respawn_all()`, `set_enabled(on)`.
Skip it with `--flag=no_parked_aircraft` (or `--no_parked_aircraft`) or `--disable=aircraft`.
Boot log line: `[AircraftSpawner] parked 6 aircraft in 6 slots` (full boot, all systems).

## 9. Tests

```powershell
$dis = '--disable=traffic,peds,police,props,respawn,emergency,wildlife,shops,garage,transit,taxi,activities,debug,pickups'
tools\godot.ps1 -Mode check -Dirs 'gta/code/vehicles,gta/resources/registries,gta/tests'
tools\godot.ps1 -Mode headless -Frames 9600  -TimeoutSec 400 -Tag air_heli  -UserArgs '--test=air_heli','--test-timeout=380',$dis
tools\godot.ps1 -Mode headless -Frames 17000 -TimeoutSec 420 -Tag air_plane -UserArgs '--test=air_plane','--test-timeout=400',$dis
tools\godot.ps1 -Mode window   -Frames 600   -TimeoutSec 120 -Tag air_shots -UserArgs '--test=air_shots','--test-timeout=100','--flag=no_parked_aircraft',$dis
```
(The brief's disable list is `traffic,peds,police`; the longer list keeps neighbours that were mid-edit
during this wave - props, respawn, player - from breaking the boot. The world, environment, city,
vehicles and the player are always on.)

* `air_heli` (34 checks, PASS): parked aircraft exist; the PLAYER flies heli_civil through the real
  input path: spool, climb to 30 m, hover drift, 150 m forward, self-stop, 180 degree yaw, soft landing
  with no damage, camera params, flying XP, soft world limit (pushed back + nose turned + UI.notify),
  exit; a 9 m drop damages a second heli; autopilot hover_at (0.3 m / 0.7 m error), fly_to arrives and
  stops, orbit keeps 35 m +- 1; police searchlight.
* `air_plane` (32 checks, PASS): plane_prop rests on 3 wheels at the modelled height; take-off roll
  164 m; climb to 60 m; stall with idle power + nose up, the nose drops, recovery; banked 180 degree turn;
  **full scripted circuit**: turns back about 2 km east of the runway, intercepts the extended centre line, 4 degree glide path, flare,
  touchdown on the runway (1.1 m/s), brakes, stops on the runway, no damage. plane_jet: take-off roll
  242 m, climb-out, landing from a short final (teleported 900 m out on the glide path) to a stop on
  the runway. Player input path in a plane: W opens the throttle, it rolls, S closes it, brakes stop it.
* `air_shots` (window, PASS): `qa/screenshots/air_fly_heli_bay.png`, `air_fly_plane_runway.png`,
  `air_fly_plane_turn.png`, `air_fly_jet_turn.png`, `air_fly_police_night.png` (looked at).

## 10. Known limitations

* The jet's landing gear is static geometry inside `Body` (art), so it cannot retract; `air_gear` only
  says so. `gear_down` is always true.
* Mouse flight control is not implemented (the mouse orbits the camera).
* The HUD shows altitude above sea level (`hud_root.gd` uses `global_position.y`); `altitude_agl` is
  available for a radar-altimeter readout (request to the UI owner).
* Helicopters have no autorotation: an engine-off helicopter falls. Planes have no autopilot (the test's
  approach guidance lives in `air_plane.gd` and only uses the public hooks).
* Rotor strike rays see world / vehicles / props / characters; a strike on a thin pole between the two
  sweeping rays can be missed for a few frames.
* Water is not a collider: aircraft settle into the sea through the shared water code (stall, buoyancy
  0.72 g, sink) rather than floating on pontoons.
* `heli_police` gunner seats (`Seat_Gunner_L/R`) are not used: `VehicleBase` seats only
  `Seat_Driver` + `Seat_Passenger_1..`.
