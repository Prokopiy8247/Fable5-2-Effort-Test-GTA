# HALCYON BAY - Vehicle framework (`gta/code/vehicles/`)

Owner: vehicle programmer. Audience: everybody who spawns, drives, damages, customises or
subclasses vehicles (player, traffic, police, AI, garage / mod shop, UI, next-wave bikes / boats /
aircraft). Contract: `docs/ARCHITECTURE.md` 6.5. Model contract: 8.2 and `docs/VEHICLE_KIT.md`.

---------------------------------------------------------------------------------------------------

## 1. Files

| file | class | what it is |
|---|---|---|
| `vehicle_spec.gd` | `VehicleSpec` (Resource) | data of one vehicle type, Registry kind `vehicles` |
| `vehicle_manager.gd` | `VehicleManager` | world system `vehicles`: spawn, list, caps, wreck clean-up, detail levels, pooled real lights, personal vehicle save hook |
| `vehicle_base.gd` | `VehicleBase` (RigidBody3D) | everything that is not force integration: model indexing, collision hull, paint, mods, seats / occupants / doors / lids, inputs, lights + audio + damage helpers, collisions, running people over, water stall, self-righting, save data |
| `car.gd` | `Car` | raycast suspension + tyre model + drivetrain for 4 and 6 wheelers |
| `vehicle_wheel.gd` | `VehicleWheel` | plain per-wheel data (setup + simulation state) |
| `vehicle_lights.gd` | `VehicleLights` | per-instance emissive lamp materials, indicator shader, siren bar |
| `vehicle_audio.gd` | `VehicleAudio` | engine / skid / horn / siren loops, crash, door, start sounds |
| `vehicle_damage.gd` | `VehicleDamage` | health, glass, tyres, smoke, fire, explosion, wreck, debris, repair |
| `vehicle_mods.gd` | `VehicleMods` | applies Registry `vehicle_mods` definitions (stats + visuals) |
| `vehicle_crime.gd` | `VehicleCrime` | the one place that reports hit-and-run / major collisions to `Wanted` |
| `resources/registries/vehicles_registry.gd` | - | the 13 car specs |
| `resources/registries/vehicle_mods_registry.gd` | - | 59 mod definitions in 22 slots |
| `tests/veh_testbed.gd`, `veh_drive.gd`, `veh_systems.gd`, `veh_shots.gd` | - | proving ground + tests (section 14) |

No `.tscn` wrappers are needed: a vehicle is always assembled at runtime from spec + GLB, so a new
export from Blender is picked up without touching any scene.

---------------------------------------------------------------------------------------------------

## 2. How a vehicle is built

`Game.spawn_vehicle(spec_id, xform, opts)` -> `VehicleManager.spawn_vehicle()`:

1. Spec from `Registry.get_def("vehicles", id)`. Unknown id, class script not implemented yet or
   **GLB missing -> returns `null`** with one warning per spec (never a placeholder).
2. The class script is chosen by `spec.vehicle_class` (`VehicleManager.CLASS_SCRIPTS`: car ->
   `car.gd`; `bike.gd`, `boat.gd`, `helicopter.gd`, `plane.gd` are picked up as soon as the files
   exist).
3. `VehicleBase.build(spec, model, opts)` - before the node enters the tree:
   * indexes every `Node3D` of the GLB by name (`get_part("Wheel_FL")`, `has_part()`),
   * measures the `Body` AABB (`body_aabb`, body space) - bounds for sweeps, exits, camera,
   * **collision**: one `ConvexPolygonShape3D` per `Col_*` helper mesh (`Col_Body`, `Col_Cabin`,
     `Col_Box` ...), points below `spec.hull_clearance` are lifted so the hull never drags on
     kerbs; fallback without helpers: two boxes from the Body AABB. Shapes are cached per GLB,
   * hides `Col_*` and `Mod_*`, sets visibility ranges: detailed parts 0-75 m, `Body_LOD1` from
     75 m, wheels to 260 m (LOD swap is done by the renderer, no script per frame),
   * seats from `Seat_Driver`, `Seat_Passenger_1..` (at most `spec.seats`), exits from `Exit_*`,
     doors `Door_FL/FR/RL/RR` (+ any other `Door_*`), lids `Hood`, `Trunk`, `Roof_Convertible`,
     `SteeringWheel` (its spin axis is fitted from the mesh),
   * `_build_drive()` (subclass hook): `Car` reads `Wheel_FL/FR/ML/MR/RL/RR` - position, radius
     (from the mesh unless `spec.wheel_radius` > 0), width,
   * mass, custom centre of mass (`spec.com_height`, `com_offset`, measured from the middle of
     the wheelbase), box inertia scaled by `spec.inertia_scale`,
   * helpers: `VehicleLights`, `VehicleAudio`, `VehicleDamage`.
4. Added under `Game.get_entities_root()` (or `opts.parent`), group `vehicle` + `damageable`,
   layer `Layers.VEHICLE`, mask `Layers.VEHICLE_MASK`, paint / mods / state options applied,
   caps enforced, `EventBus.vehicle_spawned`.

### Spawn options (`opts`, all optional)

| key | meaning |
|---|---|
| `owner_tag` | `"civilian"` (default from the spec flags), `"player"`, `"police"`, `"parked"`, `"emergency"`, `"taxi"` |
| `color`, `color2` | primary / secondary paint. Default: random from `spec.default_colors` (`Game.rng`) unless `spec.fixed_livery` |
| `mods` | Dictionary slot -> mod id |
| `engine_on`, `headlights` (0/1/2), `siren`, `locked`, `health` | initial state |
| `asleep` | spawn sleeping at ride height, tagged `parked` (wakes when touched or driven) |
| `velocity` | initial linear velocity (traffic spawned at speed) |
| `personal` | mark as the player's personal vehicle (saved) |
| `roof_open` | convertibles: default is random (40 % open) for civilian spawns in dry weather |
| `with_driver` | archetype id, stored as meta `with_driver` for the AI / traffic module |
| `parent` | parent node (default `Game.get_entities_root()`) |
| `wheel_rays` | cars: force 1 or 3 suspension rays per wheel |
| `model_instance` | TEST ONLY: use this node tree instead of the GLB |

---------------------------------------------------------------------------------------------------

## 3. Public API

Contract members (ARCHITECTURE 6.5) - all implemented with the exact names:

```gdscript
var spec_id; var vehicle_class; var health; var max_health; var destroyed
var driver; var is_player_driven; var owner_tag; var is_police; var is_emergency
var engine_on; var siren_on; var speed_kmh; var paint_primary; var paint_secondary; var mods
func set_inputs(throttle, steer, brake, handbrake := false)      # AI; steer +1 = right; ignored while the player drives
func set_flight_inputs(pitch, roll, yaw, power)                  # aircraft AI (stored in in_pitch / in_roll / in_yaw / in_power)
func can_enter(who) -> bool;  func get_free_seat() -> int
func occupant_enter(who, seat := 0);  func occupant_exit(seat := 0) -> Transform3D
func eject_occupants(impulse := Vector3.ZERO)
func get_seat_node(seat := 0) -> Node3D;  func get_exit_transform(seat := 0) -> Transform3D
func apply_damage(info);  func repair();  func explode(instigator := null)
func set_paint(primary, secondary := Color(0,0,0,0))
func apply_mods(mods);  func get_mod_options() -> Dictionary     # slot -> Array of mod ids
func set_headlights(mode)  # 0 off, 1 low, 2 high
func set_siren(on);  func honk(on)
func get_forward_speed() -> float;  func get_camera_params() -> Dictionary
func pop_tire(index);  func get_occupants() -> Array
```

Additions (stable, use them):

| member | use |
|---|---|
| `spec: VehicleSpec`, `model`, `body_aabb`, `is_taxi`, `personal`, `locked`, `in_water`, `stalled`, `on_fire`, `detail_level`, `headlight_mode`, `horn_on`, `indicator` | read-only state |
| `release_inputs()` | AI lets go: inputs neutral, the car brakes itself to a stop when it has no driver |
| `teleport(xform)` | move instantly (garage, admin); velocities cleared |
| `start_engine()`, `stop_engine()`, `has_siren()` | - |
| `set_indicator(dir)` | 0 off, -1 left, 1 right, 2 hazards |
| `is_braking()`, `is_reversing()` | lamps / AI |
| `get_seat_count()`, `get_occupant(seat)`, `get_seat_of(who)`, `get_door_position(seat)` | seats |
| `swing_door(seat)`, `open_door("Door_RL", seconds)` | doors (rear doors of van / ambulance by part name) |
| `has_lid(w)`, `set_lid_open(w, amount, instant := false)`, `get_lid_open(w)` | `w` = `"hood"`, `"trunk"`, `"roof"`; the pickup's bottom-hinged `Tailgate` serves as its `"trunk"` (folds flat, 1.5 rad) |
| `taxi_for_hire`, `set_taxi_sign(on)`, `has_fare()` | taxis: the `TaxiSign` neon (per-instance `P_NeonYellow`) is lit while for hire, with no passenger aboard and the engine running or `owner_tag == "taxi"` (waiting on the rank) |
| `get_exhaust_positions()`, `exhaust_puff(kind, scale)` | tail pipes (`Exhaust_L` + `Exhaust_R` when both exist, else `Exhaust`); cosmetic puffs on engine start, loaded upshifts and full-throttle launches (near vehicles only) |
| `has_convertible_roof()`, `set_roof_open(open, instant := false)`, `is_roof_open()`, `toggle_roof()` | cars with a `Roof_Convertible` part (sports) |
| `get_part(name)`, `has_part(name)`, `marker_local(name, fallback)`, `get_engine_position()`, `get_center_position()` | model access |
| `get_health_ratio()`, `get_power_factor()`, `get_last_instigator()` | damage state |
| `get_wheel_count()`, `get_wheel_position(i)`, `get_wheel_radius(i)`, `get_wheel_node(i)`, `is_tire_flat(i)` | wheels |
| `get_save_data()`, `apply_save_data(d)` | one vehicle (spec id, colours, mods, health, transform, roof) |
| `Car`: `gear`, `rpm`, `steer_norm`, `grounded_wheels`, `airborne_time`, `wheelbase`, `track_width`, `get_telemetry()`, `get_body_lean_degrees()`, `detach_wheel(i)` | HUD / debug |
| `VehicleManager`: `get_vehicles()`, `get_vehicle_count()`, `can_spawn(id)`, `get_spawnable_ids(filter)`, `get_random_civilian_id()`, `get_nearest_vehicle(pos, max_dist, who)`, `despawn_vehicle(v)`, `clear_all(include_player_vehicle)`, `repair_all()`, `set_enabled(on)`, `get_debug_info()`, `max_vehicles`, `max_wrecks`, `wreck_lifetime`, `detail_override`, `set_personal_vehicle(v)`, `get_personal_vehicle()`, `spawn_from_save(data)`, `get_save_data()`, `load_save_data(d)` | system |
| `VehicleMods`: `install(v, mod_id)`, `remove(v, slot)`, `price_of(mods)`, `slot_name(slot)`, `get_def(id)`, `supports(v, def)`, `PERFORMANCE_SLOTS`, `VISUAL_SLOTS` | mod shop |
| `VehicleBase.now_msec()` | game-time clock of the module (pause / time-scale aware) |

Occupant notifications: when a vehicle throws somebody out (`eject_occupants`, carjacking a seat
that is taken, explosion) it calls `who.on_vehicle_ejected(vehicle, exit_transform, impulse)` if
the occupant implements it; otherwise `who.exit_vehicle()` (player) or it re-parents a child
occupant to the entities root at the exit transform and calls `knock_down(impulse)`.

`can_enter()` is true for a free seat **or** an NPC driver that can be pulled out; false for
wrecks, locked cars, flooded cars, cars on their roof and above 50 km/h.

Signals / events emitted: `EventBus.vehicle_spawned`, `vehicle_collision(v, other, impulse N s,
position)`, `vehicle_damaged`, `vehicle_destroyed`, `vehicle_modified`, `fire_started`,
`noise_emitted` (`crash` 15-45 m, `horn` 30 m, `siren` 70 m).

---------------------------------------------------------------------------------------------------

## 4. Car physics (`car.gd`)

Everything runs in `_integrate_forces` at 60 Hz (Jolt), forces only - no kinematic cheats.

1. **Drivetrain** (`_update_drivetrain`): torque curve (`spec.torque_curve` or the built-in
   parabola peaking at 55 % rpm) -> automatic gearbox (up at 93 % rpm, kick-down under full
   throttle, `shift_time` torque cut) -> drive force at the wheels. The final drive is derived so
   the top gear hits the rev limiter exactly at `spec.top_speed` (a governor: every spec reaches
   its top speed and stays there). Reverse is first gear, limited to `reverse_speed`.
   `move_back` while rolling forward brakes first, then selects reverse.
2. **Steering** (`_update_steering`): rate limited (`steer_rate`, `steer_return_rate`), lock
   reduced with speed to the angle that uses the available grip + `high_speed_steer_slip` degrees,
   automatic counter-steer while sliding (`drift_assist`), steering pull from damage.
3. **Wheels**: one ray per wheel on `Layers.GROUND_MASK` (three per wheel for the player's car so
   kerbs are climbed smoothly; light dynamic clutter is looked through). The spring works around
   the **modelled pose**: at rest every wheel carries its static load and sits exactly where the
   artist put it. Spring + bump / rebound damper + bump stop + anti-roll bar.
   Tyres: slip-angle curve (`VehicleWheel.slip_curve`: linear, peak at `peak_slip_angle`, then
   down to `slide_grip`), friction-ellipse coupling (`power_slide`), launch traction
   (`traction`), ABS-like brake cap, limited-slip differential (`LSD_BIAS`), kinetic friction for
   handbrake-locked rear wheels (`handbrake_grip`), surface grip from the collider's `surface`
   meta (`VehicleWheel.SURFACE_GRIP`), `Weather.get_grip_multiplier()`, the player's driving skill
   (0.97-1.05), flat tyres (55 % grip + drag on that corner = pull to that side).
   Tandem rear axles (fire truck) get a tiny passive steer so six-wheelers do not scrub.
   Wheels standing on another rigid body push it down (cars can sit on car carriers / props).
4. **Aero**: quadratic drag derived from the stock top speed, downforce, gentle levelling torque
   in the air so jumps land on the wheels.
5. **Rest**: with a closed throttle below 0.7 m/s each tyre holds a static-friction anchor (no
   creep on slopes); after 0.9 s without motion the body is put to sleep (zero cost, zero jitter).
6. **Self-righting** (`VehicleBase`): on the roof / side and nearly still for 3 s -> a 0.9 s
   scripted roll back onto the wheels.
7. **Visuals** (`_update_visuals`): wheel spin (rolls with the ground speed, wheelspin and locked
   wheels are visible), steer, suspension travel, steering wheel, tyre smoke / dust, and
   **visual body lean**: the shell exaggerates the physical roll / squat / dive by
   `spec.body_lean` (capped at 2.3 / 1.1 degrees extra) while the wheels stay where the
   simulation has them. Vehicles further than 110 m from the camera skip all of this.

---------------------------------------------------------------------------------------------------

## 5. `VehicleSpec` fields

| group | field (default) | meaning |
|---|---|---|
| Identity | `id`, `display_name`, `description`, `vehicle_class` ("car"), `model_path` ("" = `models/vehicles/<id>.glb`), `price`, `seats`, `max_health` (1000), `is_police`, `is_emergency`, `is_taxi`, `traffic_weight` (0 = never ambient traffic) | - |
| Body | `mass`, `com_height` (0.5), `com_offset` (x right, y up, z back), `inertia_scale` (pitch, yaw, roll), `hull_clearance` (0.27), `hull_friction` (0.25), `collision_damage_scale` | rigid body |
| Engine | `engine_power` kW, `torque_curve`, `idle_rpm`, `redline_rpm`, `top_speed` m/s, `reverse_speed`, `gear_ratios` or `gear_count` + `gear_spread`, `final_drive` (0 = auto), `shift_time`, `drivetrain_efficiency`, `drivetrain` ("fwd" / "rwd" / "awd"), `awd_front_bias`, `engine_braking` | powertrain |
| Brakes | `brake_force` N, `brake_bias_front` | stock values sit below the tyre limit so brake mods matter |
| Steering | `max_steer_angle` deg, `high_speed_steer_slip` deg, `steer_rate`, `steer_return_rate`, `drift_assist` | - |
| Tyres | `grip_front`, `grip_rear`, `peak_slip_angle` deg, `slide_grip`, `handbrake_grip`, `handbrake_brake_assist` (0.5: a held handbrake with a closed throttle also drags the front brakes, so it stops the car), `power_slide`, `traction`, `rolling_resistance` | - |
| Suspension | `suspension_rest_length` (droop), `suspension_travel`, `suspension_stiffness` (Hz), `suspension_damping` (ratio), `suspension_rebound`, `anti_roll`, `roll_influence`, `body_lean` | - |
| Aero | `drag_coefficient` (0 = from top speed), `downforce` | - |
| Wheels | `wheel_radius` (0 = measured from the mesh) | - |
| Camera | `cam_distance`, `cam_height`, `cam_fov`, `cam_look_height` | `get_camera_params()` |
| Audio | `sound_engine`, `sound_horn`, `sound_siren`, `engine_pitch_min`, `engine_pitch_max` | sound ids of the audio module |
| Appearance | `default_colors`, `secondary_colors`, `fixed_livery`, `roof_fold_angle`, `allowed_mods` (`["*"]` = everything the model supports) | - |

Helpers: `VehicleSpec.make(id, name, props)`, `get_model_path()`, `has_model()`, `get_flags()`,
`allows_mod_slot(slot)`, `get_camera_params()`, `to_summary()` (plain data for UIs).

---------------------------------------------------------------------------------------------------

## 6. Roster and measured handling

Measured by `veh_drive` on the real GLBs (flat dry asphalt, AI inputs). See section 14 for the
command; the table is printed as `VEH_TABLE` lines.

| id | name | model | mass kg | kW | drive | seats | health | 0-100 km/h s | km/h after 6 s | top km/h | 100-0 m | reverse km/h | yaw deg / 1.25 s | handbrake slip deg | ramp air s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `compact` | Pip | GLB | 1050 | 94 | fwd | 4 | 850 | 7.78 | 84.0 | 143.6 | 41.9 | 39.4 | 51.5 | 148.6 | 0.80 |
| `sedan` | Meridian | GLB | 1450 | 152 | rwd | 4 | 1000 | 6.67 | 93.4 | 161.5 | 41.6 | 39.4 | 43.4 | 147.4 | 0.85 |
| `sports` | Vanta RS | GLB | 1300 | 335 | rwd | 2 | 900 | 4.05 | 137.6 | 208.1 | 33.3 | 39.5 | 43.6 | 174.8 | 1.00 |
| `muscle` | Galeforce 426 | GLB | 1650 | 290 | rwd | 4 | 1050 | 4.87 | 117.2 | 193.8 | 45.0 | 39.4 | 41.2 | 149.6 | 0.95 |
| `suv` | Summit | GLB | 2100 | 205 | awd | 4 | 1200 | 6.47 | 95.7 | 157.9 | 44.3 | 39.4 | 41.5 | 147.0 | 0.85 |
| `pickup` | Dustrunner | GLB | 1900 | 172 | rwd | 4 | 1250 | 8.30 | 78.3 | 150.5 | 46.5 | 38.5 | 47.4 | 107.6 | 0.77 |
| `van` | Cargomate | GLB | 2300 | 140 | rwd | 2 | 1300 | 11.53 | 71.0 | 122.0 | 48.3 | 34.5 | 44.1 | 124.8 | 0.72 |
| `box_truck` | Tidewater 7.5t | GLB | 4800 | 240 | rwd | 2 | 1700 | 15.20 | 59.4 | 107.7 | 53.2 | 21.9 | 37.0 | 31.4 | 0.60 |
| `taxi` | Meridian Cab | GLB | 1550 | 150 | rwd | 4 | 1050 | 6.97 | 91.1 | 161.2 | 42.7 | 39.3 | 42.8 | 143.6 | 0.87 |
| `police_cruiser` | HBPD Patrol | GLB | 1750 | 285 | rwd | 4 | 1400 | 4.72 | 115.4 | 193.8 | 36.6 | 39.5 | 42.6 | 155.3 | 0.95 |
| `swat_van` | HBPD Bulwark | GLB | 5200 | 350 | awd | 4 | 3200 | 9.87 | 78.4 | 135.8 | 45.2 | 33.0 | 41.7 | 93.5 | 0.77 |
| `ambulance` | Bayside Medic | GLB | 3200 | 230 | rwd | 2 | 1600 | 9.55 | 77.0 | 140.9 | 48.6 | 37.4 | 40.2 | 99.0 | 0.77 |
| `firetruck` | Engine 9 | GLB | 9000 | 460 | rwd | 4 | 2600 | 14.55 | 60.2 | 114.4 | 51.9 | 21.3 | 35.5 | 15.9 | 0.58 |

Run of 2026-11-10 08:45 on all 13 real GLBs (`qa/logs/084548_298_veh_drive.out.log`), 418 checks passed. "yaw" = heading change after 1.25 s of full right
lock at 35 % throttle from about 2.6 s of acceleration; "handbrake slip" = largest angle between the nose and the direction
of travel during a 1.8 s handbrake turn; "ramp air" = longest time with all wheels off the ground over the 1.4 m test ramp.

Character of each (what the numbers are meant to feel like):

* **compact "Pip"** - light FWD: nimble, mild understeer, runs out of breath early.
* **sedan "Meridian"** - neutral RWD all-rounder; **taxi** = same running gear in a taller
  purpose-built cab body: softer springs, higher centre of mass, slightly higher chase camera.
* **sports "Vanta RS"** - mid-engined: huge grip, flat, short gears, downforce; targa roof.
* **muscle "Galeforce 426"** - brutal launch (`traction` 1.3), stable off the throttle, tail steps
  out under power (`power_slide` 0.95).
* **suv "Summit"** - AWD: best launch on poor surfaces, tall, leans, long travel.
* **pickup "Dustrunner"** - light rear end, soft long-travel springs, slides early.
* **van "Cargomate"**, **box_truck "Tidewater"** - slow, top-heavy, long braking distances.
* **police_cruiser** - sedan with sports-car pace and grip, reinforced.
* **ambulance**, **swat_van**, **firetruck** - heavy; the fire truck is a 9 t six-wheeler that
  barely slides and needs room.

---------------------------------------------------------------------------------------------------

## 7. Tuning guide

| I want ... | change |
|---|---|
| faster 0-100 | `engine_power` up; if the driven wheels just spin (RWD / FWD) raise `traction`, move `com_offset.z` toward the driven axle |
| higher top speed | `top_speed` (the gearing and drag follow automatically); keep `engine_power` plausible or the last gear takes ages |
| snappier turn-in | `steer_rate` up, `high_speed_steer_slip` up (more lock at speed), lower `inertia_scale.y` |
| more grip | `grip_front` / `grip_rear`. Keep rear >= front for a forgiving car; rear < front spins in S-bends |
| power oversteer | `power_slide` toward 1.0 (throttle eats rear lateral grip) - muscle car |
| longer / shorter slides | `slide_grip` (grip left beyond the peak), `peak_slip_angle` (wider = lazier, more progressive) |
| handbrake turns | `handbrake_grip` lower = longer slides |
| catches slides by itself | `drift_assist` up (0 = off) |
| more body roll (physical) | `roll_influence` up, `anti_roll` down, `suspension_stiffness` down. Careful with tall vehicles |
| more body roll (visual only) | `body_lean` (1 = physical only) |
| softer ride / more travel | `suspension_stiffness` 1.4-1.6 Hz, `suspension_travel`, `suspension_rest_length` |
| bounces after bumps | `suspension_damping` up (0.5-0.6), `suspension_rebound` 1.3-1.5 |
| scrapes on kerbs | `hull_clearance` up (the hull bottom is lifted to it) |
| nose dives on jumps | move `com_offset.z` back; `inertia_scale.x` up |
| shorter braking | `brake_force` (cap is tyre grip x weight: see `brake100` in the table) |

Rules that keep a spec healthy: natural frequency 1.4 (truck) - 2.4 Hz (sports); damping ratio
0.4-0.6; `com_height` realistic (0.38 sports - 1.0 fire truck) - it drives weight transfer;
top speeds 30-58 m/s (the island is 600 m). Run `veh_drive` after every change: it fails on
cars that spin in an S-bend, flip on a kerb or land on their roof.

---------------------------------------------------------------------------------------------------

## 8. Mods (`vehicle_mods_registry.gd`, `vehicle_mods.gd`)

A mod is a Dictionary: `{id, slot, level, display_name, price, category ("performance" /
"visual"), description, effects, + one of: node, wheel_model, color, finish, tint, horn_sound /
horn_pitch}`. `vehicle.mods` is `slot -> mod id`; an absent slot is stock.

| slot | options | what it really does |
|---|---|---|
| `engine` (4) | +8 / 16 / 25 / 35 % | torque multiplier; governed top speed rises with the cube root |
| `turbo` (3) | +10 / 18 / 27 % power, +3 / 6 / 9 % top speed | - |
| `transmission` (3) | shift time x0.72 / 0.5 / 0.3, drive force +3 / 6 / 10 % | - |
| `brakes` (3) | brake force +14 / 28 / 45 % | shorter stopping distance (measured in `veh_systems`) |
| `suspension` (4) | ride height -2 .. -6.5 cm, stiffness +10 .. 42 %, anti-roll +15 .. 75 %, grip +1 .. 5 % | - |
| `armor` (4) | damage taken x0.85 / 0.7 / 0.55 / 0.4, +40 .. 170 kg | - |
| `tires` (3) | grip +5 / 10 %; level 3: +6 % and bullet-resistant | bullets no longer pop tyres |
| `spoiler` (2) | `Mod_Spoiler_A` / `_B`, downforce +0.5 / +1.0 N per (m/s)^2 | - |
| `bumper_f`, `bumper_r`, `hood`, `skirts`, `roof`, `grille` | `Mod_*_A` parts | visual |
| `exhaust` | `Mod_Exhaust_A`, +2 % power | - |
| `wheels` (4) | shared `parts/wheel_<style>.glb`, scaled to the car's wheel radius | visual |
| `wheel_color` (6), `plate` (3) | recolours `M_Rim` / `M_Plate` per instance | visual |
| `paint_finish` (3) | gloss / matte / metallic on both paint materials | visual |
| `tint` (3) | darkens `M_Glass` per instance | visual |
| `lights` (3) | headlamp colour: emissive + the pooled SpotLight3D | visual |
| `horn` (4) | horn sample / pitch | audio |

`get_mod_options()` only lists what the vehicle supports: the slot must be allowed by
`spec.allowed_mods`, body parts need their `Mod_*` node, wheels need the shared GLB, colour mods
need the material. Unknown / mismatched entries are dropped by `apply_mods()`.
Effects are accumulated into `vehicle.mod_stats` (`VehicleMods.DEFAULT_STATS`: multipliers,
except the additive `ride_drop`, `mass_add`, `downforce_add` and the flag `bulletproof_tires`)
and consumed by `Car._refresh_tuning()` - they change real forces.
To add a mod: append one line to the registrar. To add a stat: add it to `DEFAULT_STATS` and read
it where it matters.

---------------------------------------------------------------------------------------------------

## 9. Damage (`vehicle_damage.gd`, spec section 22)

* `apply_damage(info)`: bullets x0.35 (break the pane they hit, pop a tyre within 1.1 radii of
  a wheel centre), melee x0.5 (breaks glass), explosions x3.2 (all glass), then armor mods.
* Collisions: a velocity change above 1.5 m/s while the hull touches something ->
  `EventBus.vehicle_collision`, crash sound + noise, sparks, damage `10 d + 0.5 d^2`
  (x `collision_damage_scale`), glass above 6 m/s, hood / trunk spring ajar above 7.5 m/s,
  lamps die above 9 m/s; breakable props get a share of the hit.
* Handling: power drops below 60 % health (to 45 %), steering pulls to one side below 50 %.
* Smoke below 45 % (one looping `Fx.attach_smoke` emitter on the `Engine` marker: light ->
  heavy -> black), **fire below 15 %** (`Fx.spawn_fire`, 4.5-7 s fuse), then `explode()`:
  `Fx.explosion` (7.5 m, 220 dmg), occupants take 1000 explosion damage and are ejected, glass
  gone, lids blown open, up to two wheels + a door + sometimes the hood fly off as debris
  (layer `DEBRIS`, at most 12 alive, 9-14 s), burnt materials, burning wreck (14 s fire that
  damages neighbours -> chain reactions), wreck frozen after it settles and removed by the
  manager (55 s and out of sight, or more than 6 wrecks).
* Regular damage never pops a car instantly: at 0 hp it ignites with a short fuse.
* `repair()` restores everything (also revives a wreck: admin / garage).
* Water: a car whose engine is under water stalls (`stalled`, `in_water`), floats low for a
  moment and is despawned by the manager after 45 s when nobody is near.
* Running people over: a box sweep ahead of the moving hull damages characters (`type
  "vehicle"`), calls `knock_down(impulse)` / `ragdoll()`, and ignores the body's collider while
  it is under the car, so pedestrians never stop a car dead.

## 10. Lights and audio

* Only the lamp materials are duplicated per vehicle (`M_Headlight`, `M_Taillight`,
  `M_ReverseLight`, `M_Siren_Red`, `M_Siren_Blue`; `M_Indicator` becomes a small shader that
  lights the left or right half). Tail lamps run with the headlights and brighten on braking.
* Real lights are pooled by the manager: two `SpotLight3D` for the player's vehicle, one each
  for the four nearest other vehicles with headlights on (within 70 m), two `OmniLight3D` that
  flash red / blue on the nearest vehicle with its siren on. No shadows.
* AI traffic switches its headlights with `WorldClock.get_daylight() < 0.3`; the player's car
  turns them on when entered at night.
* Audio: engine loop pitch from rpm and volume from load (`Audio.make_loop_player`, bus
  `Engine`), skid loop from tyre slip, horn, siren, crash samples scaled by the impact,
  door / start one-shots. Players are created lazily and only within 80 m.

## 11. Crime hooks (`vehicle_crime.gd`)

Only while `is_player_driven`: striking a pedestrian above 4 m/s -> `Wanted.report_crime(
"hit_and_run", ...)`; ramming another vehicle with a velocity change above 5.5 m/s (9 m/s if it
is empty) while the player was the faster one -> `"collision_major"`. Cooldowns 0.9 s / 3.5 s.
Theft is reported by the player module, explosions by `Fx.explosion`.

## 12. Save hook

`VehicleManager` registers as SaveSystem provider `vehicles`: `{"personal": {spec_id, primary,
secondary, mods, health, position, yaw, roof_open}}`. `spawn_from_save(data)` rebuilds it
(asleep, owner_tag `player`). The garage system will call `set_personal_vehicle(v)`.

## 13. Performance

* Sleeping (parked) cars cost no physics and no script work except one cheap `_process`.
* Detail levels by camera distance (manager tick, 5 Hz): `0` < 45 m, `1` < 110 m, `2` beyond:
  level 2 skips wheel visuals, lights and FX; audio only within 80 m.
* One ray per wheel for AI cars (three for the player's), pedestrian sweep every second physics
  frame for AI cars, surface lookups 3 times per second per wheel.
* Caps: `max_vehicles` 90 (farthest driverless vehicle goes first; wrecks before everything
  else), `max_wrecks` 6, debris 12, real lights 6 + 2.
* All timers use `VehicleBase.now_msec()` (simulated time), never the wall clock.

---------------------------------------------------------------------------------------------------

## 14. Tests

```powershell
$dis = '--disable=world,environment,city,interactions,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
tools\godot.ps1 -Mode check -Dirs 'gta/code/vehicles,gta/resources/registries,gta/tests'
tools\godot.ps1 -Mode headless -Frames 7000 -TimeoutSec 300 -UserArgs '--test=veh_drive','--no_player','--rig',$dis
tools\godot.ps1 -Mode headless -Frames 9500 -TimeoutSec 300 -UserArgs '--test=veh_systems','--no_player',$dis
tools\godot.ps1 -Mode window   -Frames 620  -TimeoutSec 60  -UserArgs '--test=veh_shots','--no_player',$dis
```

* `veh_drive` - every car spec side by side on a code-built proving ground: rest (drift, ride
  height, wheel positions), wheel spin axis, 0-100 / speed at 6 s / top speed, braking, reverse,
  steering direction and steer axis, S-bend stability, handbrake slide, 0.15 m kerb straight
  (1 ray) and diagonal (3 rays), ramp jump. `--veh=a,b` limits the specs; `--rig` lets specs
  without a GLB run on a box-and-cylinder stand-in (TEST ONLY, marked `rig` in the table).
* `veh_systems` - spawn rules, occupants / exits, player input path, lights + pooled lights +
  siren, lids + convertible roof, paint, mods (measured acceleration / braking / ride height),
  damage -> smoke -> fire -> explosion -> wreck -> clean-up -> repair, glass, tyres, pop_tire
  pull, self-righting, water stall (TEST ONLY world stub for `is_water_at`), pedestrian strike + crime hooks, save / load, fallback builder, caps.
* `veh_shots` - windowed screenshots in `qa/screenshots/veh_*.png` (look at them).

---------------------------------------------------------------------------------------------------

## 15. How to add a vehicle

1. Author the GLB following ARCHITECTURE 8.2 / `docs/VEHICLE_KIT.md` and export it to
   `gta/generated/models/vehicles/<id>.glb`. The builder needs: `Body`, `Wheel_*` (origin at the
   wheel centre, axle along local X), ideally `Col_Body` + `Col_Cabin`, `Seat_*` / `Exit_*`
   markers, `Light_Head_L/R`, `Engine`, optional doors / lids / glass panes / `Body_LOD1` /
   `Mod_*`. Everything optional has a fallback (box hull, synthetic driver seat, lamp positions
   from the bounds); a model with fewer than three wheels gets invisible wheels and a warning.
2. Add one `VehicleSpec.make("<id>", "Name", {...})` block to `vehicles_registry.gd` (copy the
   closest existing spec). Roster ids are fixed by ARCHITECTURE 6.5 - tell the lead before
   inventing a new id.
3. Add a row to `RIG_DIMS` in `tests/veh_testbed.gd` only if you want to tune before the GLB
   exists.
4. Run `veh_drive` (`--veh=<id>`) and `veh_shots`, look at `veh_car_<id>.png`.

---------------------------------------------------------------------------------------------------

## 16. Subclassing notes (bikes, boats, helicopters, planes)

Create `bike.gd` / `boat.gd` / `helicopter.gd` / `plane.gd` in this folder (`class_name Bike`
... `extends VehicleBase`); `VehicleManager` instantiates them by `spec.vehicle_class` as soon as
the files exist. Register their specs in an own registrar file
(`resources/registries/vehicles_<kind>_registry.gd`). Everything in section 3 is inherited:
health / damage / wreck, occupants + doors, lights, audio, paint, mods, save data, collisions,
running people over, crime hooks, detail levels.

Override these hooks:

| hook | when | what to do |
|---|---|---|
| `_build_drive(opts)` | once, in `build()` (not in the tree yet) | read wheels / rotors / hull markers with `get_part()`, `xform_in_body()`, `aabb_in_body()` |
| `_get_reference_z()` | `_apply_mass_properties()` | body-space z the centre of mass is measured from |
| `_on_mods_changed()` or override `_apply_mass_properties()` | after `apply_mods()` | recompute tuning from `spec` + `mod_stats` |
| `_read_player_input(delta)` | every physics frame while the player drives and input is not locked | fill `in_throttle / in_steer / in_brake / in_handbrake` or `in_pitch / in_roll / in_yaw / in_power` (the `air_*` actions) |
| `_integrate_vehicle(state)` | `_integrate_forces` (not while destroyed / self-righting) | all forces: `state.apply_central_force()`, `state.apply_torque()` |
| `_update_visuals(delta)` | `_process`, detail level < 2 | wheels, rotors, handlebar, control surfaces |
| `_wants_wake()` | while sleeping | true when an input should wake the body |
| `_on_destroyed()`, `_on_repaired()`, `_on_teleported()` | state changes | reset your simulation state |
| `get_rpm_factor()`, `get_engine_load()`, `get_skid_amount()` | audio | 0..1 values for the loops |
| `get_wheel_count()` ... `is_tire_flat()`, `pop_tire()` | damage / mods | return 0 / no-op for boats and helicopters |
| `is_braking()`, `is_reversing()` | lamps | - |

Hints per class:

* **Bike / bicycle**: reuse `VehicleWheel` (two of them, `partner_index` stays -1) and the tyre
  code path of `Car` as a template; add a lean controller (target roll from lateral
  acceleration) with a balance torque, set `self_righting = true` and a shorter flip timer, and
  eject the rider on hard impacts (`eject_occupants(impulse)` from `_on_collision`).
  `Handlebar` steers about its own axis; seats use `seated_bike`.
* **Boat**: no wheels (`get_wheel_count()` 0). Buoyancy at 4+ hull points against
  `Game.get_system("environment").get_wave_height(x, z)` (fallback `Game.WATER_LEVEL`), thrust at
  the `Prop` marker, rudder torque scaled by speed, strong lateral drag. Override
  `_check_water()` so water does not stall it (it stalls / takes damage on land instead) and
  `_integrate_water()` to do nothing.
* **Helicopter / plane**: `set_flight_inputs()` already stores `in_pitch / in_roll / in_yaw /
  in_power`; `self_righting = false`; rotors (`Rotor_Main`, `Rotor_Tail`, `Propeller`) spin in
  `_update_visuals`; gear wheels (`Wheel_Nose`, `Wheel_L`, `Wheel_R`) can reuse the suspension
  part of `Car._integrate_vehicle` with one ray each. Keep `continuous_cd` on. Return
  `"aircraft"`-style camera params through the spec (`cam_*`).
* Every class must stay sleep friendly: request sleep when parked, wake in `_wants_wake()`.

---------------------------------------------------------------------------------------------------

## 17. Integration notes

* **Player**: enter with `can_enter()` -> `occupant_enter(player, seat)`; parent yourself to
  `get_seat_node(seat)`; leave with `occupant_exit(seat)` (returns a collision-tested exit
  transform: door side, other side, wider, ends, roof as the last resort). The vehicle reads
  `move_forward / move_back / move_left / move_right / handbrake / horn / headlights / siren /
  vehicle_roof` itself while `is_player_driven` and `not Game.is_input_locked()`.
  Camera: `get_camera_params()`; `vehicle_class` tells car from aircraft.
* **Traffic / police / AI drivers**: `occupant_enter(npc, 0)` (starts the engine), then
  `set_inputs()` every physics frame or whenever it changes; `release_inputs()` to let go.
  Useful: `get_forward_speed()`, `spec.top_speed`, `body_aabb`, `set_indicator()`, `honk()`,
  `set_siren()`, `is_braking()`. Parked cars: `{"asleep": true}`. An NPC that is thrown out
  should implement `on_vehicle_ejected(vehicle, exit_xform, impulse)`.
* **Weapons**: bullets hit the hull (`Layers.VEHICLE`); `Dmg.apply(collider, info)` reaches
  `apply_damage`. Pass `position` so glass and tyres react.
* **UI / HUD**: `speed_kmh`, `health / max_health`, `Car.gear`, `Car.rpm`, `spec.display_name`.
* **Garage / mod shop (next wave)**: `get_mod_options()`, `VehicleMods.install / remove /
  price_of`, `set_paint()`, `repair()`, `get_save_data()`, `VehicleManager.spawn_from_save()`.
* **Taxi system**: the roof sign follows the fare automatically (`has_fare()` = anybody in a
  passenger seat); call `set_taxi_sign(false)` for an off-duty cab and spawn rank taxis with
  `owner_tag "taxi"` so the sign stays lit with the engine off.
* **Admin menu**: `VehicleManager.get_spawnable_ids()`, `spawn_vehicle`, `clear_all()`,
  `repair_all()`, `set_enabled()`, `get_debug_info()`, `v.explode()`, `v.pop_tire(i)`.

## 18. Known limitations

* Wheels have no colliders of their own: bullets only pop a tyre when they hit the hull within
  about 37 cm of a wheel centre (the arch area); the hull bottom is flat at `hull_clearance`.
* Tyre skid marks are not drawn (the shared Fx decal pool has 64 slots; long skids would evict
  bullet holes). Tyre smoke / dust is.
* No panel deformation; damage shows as glass, lamps, lids, smoke, fire, flat tyres, wreck.
* Side glass stays in the body frame when a door opens (model contract).
* Speeds are scaled for the island; do not compare the numbers with real cars.
* Van rear doors (`Door_RearL / Door_RearR`) swing open, but the van's single `Glass_Rear` pane is
  part of the body frame (model contract), so it stays in the doorway while the doors are open.
* Exhaust puffs are cosmetic `Fx.smoke_puff` calls (no continuous emitter, no backfire flames).
