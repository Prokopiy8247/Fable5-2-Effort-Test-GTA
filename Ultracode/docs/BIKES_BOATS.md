# Two-wheelers and boats - asset notes for integrators

Author: two-wheel and boat artist; revised by the art-critic pass (jetski deck rebuilt, speedboat
restyled, bicycle / dinghy refined - numbers below are the current ones).
Builder: `tools/blender/assets/bikes_boats.py`
(`BB.build_<id>()`, `BB.qa(id)`, `BB.qa_all()`, `BB.check_normals(id)`, `BB.check_contract(id)`,
`BB.export(id)`, `BB.build_all()`). Blender roots `motorcycle`, `bicycle` (collection Vehicles/Motorcycles, slots
bikes[0..1]) and `speedboat`, `jetski`, `dinghy` (Vehicles/Boats, slots boats[0..2]).
GLBs: `res://gta/generated/models/vehicles/<id>.glb`. Look-dev / structure test:
`tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/bb_showcase.tscn -Frames 420`
(headless = structure check only) -> `qa/screenshots/bb_<id>_{a,b,c,lod1}.png`.
Contract audit of the exported GLBs (node kinds, facing, wheel / steering / crank / motor pivots,
waterline origin, hull vertex count, tri budget, material names):
`tools\godot.ps1 -Mode script -Script res://gta/code/editor/bb_audit.gd` -> `BB_AUDIT: PASS failures=0`.

`jetski` and `dinghy` are stretch assets and are NOT in the spec-id roster of ARCHITECTURE 6.5.
They follow the same boat contract as `speedboat`, so a `VehicleSpec` with class "boat" can use them.

Blender object names are `<asset>:<Part>` (names are global in the shared .blend); the contract name
is stored in the custom property `gta_name` and `BB.export()` rewrites the GLB node names from it.
Always export with `BB.export(id)`. In Godot every node carries the plain contract name.

## Common to all five

Godot axes after import: -Z forward, +X right, +Y up. Structure `FileRoot -> <id> -> parts`.

| node | kind | notes |
|---|---|---|
| `Body` | mesh | paint = `M_Paint_Primary` (+ `M_Paint_Secondary` accents) |
| `Body_LOD1` | mesh | distance shell that replaces EVERY mesh except the wheels (136-388 tris) |
| `Col_Body` | mesh | convex hull, 10-29 verts, `P_Collision` |
| `Seat_Driver`, `Seat_Passenger_N` | marker | hip point of the seated character, facing -Z |
| `Exit_Driver`, `Exit_Passenger_N` | marker | where the character stands after leaving (see per asset) |
| `Light_Head`, `Light_Head_L/R`, `Light_Tail`, `Light_Tail_L/R` | marker | centre + a narrow L/R pair (single lamps) |
| `Engine` | marker | smoke / fire origin |

## motorcycle (sport-naked, 2.08 x 0.87 x 1.27 m, wheelbase 1.43 m, 6336 tris in total)

- `Wheel_F` r 0.31, `Wheel_R` r 0.32: origin at the wheel centre, spin about local X (forward roll =
  negative `rotation.x`). Tyre bottoms at y = 0, so the bike stands on its wheels at the origin.
- `Handlebar` (fork, front fender, headlight mask, fly screen, bars, mirrors, front indicators): origin
  on the steering axis. The axis is raked 25 deg: marker `Steer_Axis` sits at the same point and its
  local +Y is the axis. Steer with
  `handlebar.transform = Transform3D(Basis(steer_axis.transform.basis.y, -angle), rest_origin)`
  (positive angle = right). `Wheel_F` is a sibling: rotate it about the same axis / point.
- Children of `Handlebar`: `Grip_L`, `Grip_R` (grip centres, hand targets; they turn with the bars).
- `Footrest_L`, `Footrest_R` (rider pegs), `Exhaust` (muffler tip, facing back), `Seat_Passenger_1`,
  `Exit_Driver` (left side, on the ground), `Exit_Passenger_1` (right side).
- Lean: roll the whole model about the Z axis through the tyre contact line (y = 0).

## bicycle (urban hardtail, 1.75 x 0.67 x 1.05 m, wheels r 0.34, wheelbase 1.07 m, 4008 tris in total)

- `Wheel_F`, `Wheel_R` as above (16 simplified spokes each).
- `Handlebar` (bars, stem, suspension fork, lamp, bell) + `Steer_Axis` (19.3 deg) + `Grip_L/R`: as on
  the motorcycle.
- `Crank` (chainring, arms, pedals): origin on the bottom-bracket axle, spin about local X (forward
  pedalling = negative `rotation.x`). Children `Pedal_L`, `Pedal_R` = pedal tops (foot targets, they
  orbit with the crank; keep the feet level yourself).
- No engine markers. `Exit_Driver` on the left, on the ground. The kickstand is modelled folded
  (part of `Body`); pedal reflectors use `M_Indicator`.

## speedboat (open sport boat, hull 6.98 m, 7.79 m with the outboard, beam 2.43 m, 4634 tris in total)

- Origin at the WATERLINE under the centre: the keel is at y = -0.35; the sheer is curved - gunwale
  +0.61 at its lowest (aft quarter), +0.64 at the transom, sweeping up to +1.16 at the bow (z = -3.78).
- Sport arch over the aft cockpit (part of `Body`, builder flag `SPEEDBOAT_ARCH`): feet on the
  gunwales at z = +1.66 / +2.16, crossbar at y = 2.04 above z = +0.98 .. +1.22 (1.94 m above the cockpit
  floor, so a standing character clears it), white fairing with two flood lamps and the all-round
  light (`M_Headlight`), whip antenna up to y = 2.46. It has no collision (the hull is `Col_Body`).
- Hull colours: `M_Paint_Primary` topsides, `M_Paint_Secondary` wedge stripe under the rub rail,
  `P_Charcoal` boot stripe at the waterline, `P_CarWhite` bottom with lifting strakes, trim tabs.
- `Motor` (outboard): origin on its steering pivot at the transom. Steer about local Y (about +-30 deg);
  optional trim / tilt about local X. Its propeller is part of the mesh (no separate spin).
- `SteeringWheel`: origin at the hub, node tilted -24.8 deg about X; turn it with `rotation.z`
  (same convention as the cars). Helm is on the starboard (+X) side.
- `Glass_Windshield` (`M_Glass`, separate so it can break).
- Seats: `Seat_Driver` (+X helm seat), `Seat_Passenger_1` (-X helm seat), `Seat_Passenger_2/3` (rear
  bench, -X / +X). `Exit_Driver` and `Exit_Passenger_1/2` are standing spots ON the aft deck
  (y = +0.63), `Exit_Passenger_3` on the foredeck - not on the ground.
- `Prop` (thrust point, at the propeller, y = -0.57), `Wake_L`, `Wake_R` (stern corners at the
  waterline), `Light_Head` at the bow (nav lights are geometry: green / red at the bow, white stern
  light on a pole).
- `Col_Body`: 23-vert convex hull of the hull only (keel, chines, gunwales).

## jetski (personal watercraft, 3.49 x 1.28 x 1.28 m, draws 0.22 m, 2426 tris in total)

- Rebuilt by the critic pass: wedge hood rising to an instrument cowl, tapered seat pedestal,
  stepped two-up saddle, footwells with mats, rear boarding platform. Bow tip at z = -1.76,
  transom at z = +1.55 (unchanged), cowl top y = 0.97, bars y = 1.0, driver seat top y = 0.70.
- Origin at the waterline. `Handlebar` + `Steer_Axis` (24 deg) + `Grip_L/R` as on the motorcycle
  (origin (0, 0.86, -0.44), unchanged).
- `Motor` = steerable jet nozzle at the stern (steer about local Y). `Prop` = thrust point behind it.
- `Seat_Driver` (0, 0.79, 0.14), `Seat_Passenger_1` (0, 0.90, 0.68) (stepped tandem saddle),
  `Footrest_L/R` (footwell floors, (+-0.38, 0.165, 0.12)), `Wake_L/R`.
- `Exit_Driver` / `Exit_Passenger_1` are beside the craft at water level (the rider drops into the sea).

## dinghy (inflatable tender, 3.71 x 1.72 m, draws 0.14 m at the keel, 2268 tris in total)

- Origin at the waterline. The bow tube sweeps up (tube centre +0.20 at the stern, +0.44 at the bow). `Motor` = small tiller outboard (origin on its pivot, steer about local Y).
- `Seat_Driver` on the stern thwart (starboard, next to the tiller), `Seat_Passenger_1` on the mid
  thwart, `Exit_Driver` / `Exit_Passenger_1` are standing spots on the floor inside the boat.
- `Prop`, `Wake_L/R`, `Engine`, `Light_Head` (bow).

## Material names that arrive in Godot

Contract: `M_Paint_Primary`, `M_Paint_Secondary`, `M_Glass`, `M_Trim`, `M_Chrome`, `M_Interior`
(saddles), `M_Plate`, `M_Headlight`, `M_Taillight`, `M_Indicator`, `M_Tire`, `M_Rim`.
Palette: `P_Steel`, `P_SteelDark`, `P_Charcoal`, `P_Brass`, `P_CarYellow`, `P_WindowDark`, `P_Leather`,
`P_Teal`, `P_White`, `P_CarWhite`, `P_Wood`, `P_WoodDark`, `P_Cream`, `P_NeonGreen`, `P_SirenRed`,
`P_FireRed`, `P_SafetyOrange`, `P_Collision`.

---------------------------------------------------------------------------------------------------

# Gameplay: two-wheelers and boats (Wave 2: `bike.gd`, `boat.gd`)

Owner: bike + boat programmer. Contract: ARCHITECTURE 6.5, ARCHITECTURE_WAVE2 W2.8, `docs/VEHICLES.md`.
Everything in VEHICLES.md section 3 (health, damage, wreck, lights, audio, paint, mods, save data,
collisions, running people over, crime hooks, detail levels) is inherited from `VehicleBase`.

| file | what |
|---|---|
| `gta/code/vehicles/bike.gd` | `class_name Bike extends VehicleBase`: motorcycle (`vehicle_class "bike"`) and bicycle (`"bicycle"`) |
| `gta/code/vehicles/boat.gd` | `class_name Boat extends VehicleBase`: speedboat, jetski, dinghy (`"boat"`) |
| `gta/code/vehicles/boat_spawner.gd` | marina moorings (no class_name) |
| `gta/resources/registries/vehicles_bikeboat_registry.gd` | the five specs + the mooring hook |
| `gta/tests/bkb_bike.gd`, `bkb_boat.gd`, `bkb_shots.gd` | tests (commands below) |

`VehicleManager` picks the scripts by `spec.vehicle_class`; no shared file was changed.

## Specs (Registry kind `vehicles`)

| id | name | class | mass kg | seats | health | top speed | notes |
|---|---|---|---|---|---|---|---|
| `motorcycle` | Kestrel 690 | bike | 260 (incl. rider) | 2 | 450 | 52 m/s (governed) | 75 kW, `engine_bike_loop`, `horn_bike`, traffic_weight 0.5 |
| `bicycle` | Spoke Urban | bicycle | 95 (incl. rider) | 1 | 300 (never below 50 %) | 8.6 m/s pedalling | 420 W, 820 W sprinting, `bicycle_loop`, no horn sample |
| `speedboat` | Tidecutter 23 | boat | 1400 | 4 | 1100 | 19.5 m/s | outboard, `engine_boat_loop`, `horn_truck` |
| `jetski` | Wavehopper | boat | 420 | 2 | 500 | 21 m/s | jet nozzle, straddle seat (`get_rider_pose()` = `"seated_bike"`) |
| `dinghy` | Bay Tender | boat | 330 | 2 | 600 | 9 m/s | tiller outboard, no horn |

`jetski` and `dinghy` are outside the ARCHITECTURE 6.5 roster (stretch GLBs; the brief asked for them
"when their GLBs exist"). Tuning that `VehicleSpec` has no field for is spec meta:
`spec.get_meta("bike")` / `spec.get_meta("boat")` (Dictionaries; keys and defaults = `Bike.DEFAULTS` /
`Boat.DEFAULTS`). The usual VehicleSpec fields keep their meaning (brakes, tyres, suspension, steering,
camera, audio, colours, allowed mods).

## Bike (`bike.gd`)

* Two in-line raycast wheels (`Wheel_F`, `Wheel_R`; three rays each so kerbs are climbed), spring +
  damper around the modelled pose, the Car tyre model (slip angle, friction ellipse, ABS-capped
  brakes, rear lock on `handbrake`, static anchors when parked, sleep after 0.9 s at rest).
* **Upright controller**: the rigid body is held upright by a roll PD (`upright_hz`, `upright_damping`).
  Tyre side forces act at the height of the centre of mass, so cornering never tips the hull;
  braking / drive forces act at half that height (the fork dives, no wheelies).
* **Lean**: the whole visual model (wheels, handlebar, rider) rolls about the tyre contact line by
  `atan(v * yaw_rate / g)` - the lean the turn really needs - smoothed and capped at `max_lean_deg`
  (52 motorcycle, 40 bicycle). `get_lean_degrees()` (+ = right side down). Hull and camera stay level.
* **Steering visual**: `Handlebar` turns about the raked `Steer_Axis` (its local +Y); `Wheel_F` turns
  with it and its suspension travel slides along that axis (telescopic fork). Wheels spin with the
  ground speed (a locked wheel stops). The bicycle `Crank` turns with the rear wheel while pedalling
  (`crank_ratio` 2.7) and freewheels (stops) when coasting.
* **Engine**: drive force `min(P / v, mass * max_drive_accel)` with a governor at the top speed; drag
  derived from the top speed. Engine note: virtual sequential gearbox (`gears` 6) for
  `engine_bike_loop`. Reverse = slow paddling up to `reverse_speed`.
* **Bicycle**: pedal power `pedal_watts`; the `sprint` key gives `sprint_watts` while the rider has
  stamina: the bike calls `driver.update_stamina(delta, draining)` (player API: drains while
  sprinting, regenerates otherwise, stamina XP) and adds a little stamina XP for normal pedalling;
  pedal power scales with the stamina skill (x1.0 .. 1.15). Driving XP comes from VehicleBase.
  `engine_on` = rolling with a rider, so `bicycle_loop` only plays while moving; no exhaust puffs, no
  engine-start sound. Bicycles are never destroyed: damage stops at 50 % health (no smoke / fire);
  a blast knocks them over.
* **Crashes** (`fallen`, `crash_count`, `last_crash_reason`): hull impact with a velocity change above
  `crash_dv` (8.5 m/s motorcycle, 6 bicycle; `crash_dv_ground` 14 / 10 for hits from below) ->
  `"crash"`; a tyre sliding beyond `lowside_slip_deg` (30) above `lowside_speed` for 0.3 s ->
  `"lowside"`; tipped past 35 deg -> `"knocked"`; rider leaving above 4 m/s -> `"bailed"`; blast.
  Riders leave from their seats with the pre-impact velocity: `on_vehicle_ejected(vehicle,
  seat_xform, impulse)` (the player ragdolls), NPCs without that hook get `knock_down(impulse)`.
  The bike tips over towards its lean, slides on a grippy hull material (sparks on hard ground) and
  sleeps. It **stays down until somebody mounts it**: `can_enter()` accepts a fallen bike,
  `get_exit_transform()` gives a spot beside it and `occupant_enter()` stands it up with the base
  0.9 s scripted roll. `repair()` also stands it up. `self_righting` is off for bikes.
* A bike left at rest stays standing (there is no deployable stand in the model; it balances).
* Head-on hits stop at the tyre: thin box colliders over the upper half of each wheel are added at
  build (`WheelHull0/1`, above the hull clearance, so kerbs stay a suspension matter).
* **Rider pose**: the player module uses `seated_bike` for classes bike / bicycle. One frame after a
  rider sits down the bike writes the rider animator's seated tuning from the model markers (soft:
  only if the `animator` has these fields): `bar_pos` + `bar_half_width` from `Grip_L/R`, `peg_pos`
  from `Footrest_R` (motorcycle) or the crank axle (bicycle), `bike_lean_fwd` from `rider_lean_fwd`.
* The base door one-shots are muted for bikes and boats (the player state still plays its own door
  sounds, see "Requests").

Measured by `bkb_bike` (flat dry asphalt): motorcycle 0-100 km/h 4.3 s, top 184 km/h, 184-0 km/h in
109 m (11.5 m/s^2); at 15.7 m/s with steer 0.7: 61 deg of yaw in 1.6 s and 47 deg of lean; a locked
rear thrown into a turn at 20 m/s lowsides after 0.7 s; head-on into a wall at 90 km/h throws the
player (ragdoll) and drops the bike. Bicycle 30 km/h pedalling, 36-38 km/h sprinting (a 10 s sprint
drains stamina 1.00 -> 0.25).

## Boat (`boat.gd`)

* **Buoyancy**: `samples_z` x `samples_x` hull points from the `Col_Body` bounds (forward ones pulled
  in), acting at the waterline, depth measured from the bottom (`draft`). Each is a spring-damper
  against `Game.get_system("environment").get_wave_height(x, z)` (fallback `Game.WATER_LEVEL`). The
  spring rates are solved so the weight is carried with the hull level and the model origin on the
  surface (zero net moment about the centre of mass); each is capped at `draft + freeboard`.
* **Planing**: speed-dependent virtual lift offsets per point raise the hull (`plane_rise`) and lift
  the bow (`bow_rise_deg`: a hump around 55 % of `plane_speed`, settling to ~45 % of it on the plane,
  more with throttle). Bank into turns: a righting moment `W * righting_gm * sin(roll - target)` with
  the target `-yaw_rate * v * 0.06`, capped at `bank_deg`.
* **Drag** (scaled by the wet share of the hull): along the keel linear (`coast_drag`, 65 % less on
  the plane) + quadratic (derived so the thrust holds `spec.top_speed`); sideways strong
  (`lateral_drag`), applied behind the centre of mass so the hull tracks like a keel; yaw / roll /
  pitch damping.
* **Thrust** at the `Prop` marker, only while the propeller is under the wave surface (else the
  engine races). Its direction follows the steerable `Motor` (outboard leg / jet nozzle, rotated about
  its local Y; the jetski `Handlebar` turns about its `Steer_Axis`, the speedboat `SteeringWheel`
  turns too). A rudder force from the flow over the leg keeps a coasting boat steerable. Reverse
  thrust (`reverse_thrust`) brakes and backs up to `reverse_speed`. Input: `move_*` actions (same keys
  as the `air_*` ones on the keyboard, and they also work on a gamepad).
* **Aground**: hull contacts with an upward normal while part of the hull is dry -> sand drag
  (`ground_drag`); reversing while aground makes the hull slippery and, with the prop in the air,
  still pushes (`beach_push`), so a beached boat backs off slowly.
* Boats never flood (`_check_water` / `_integrate_water` replaced). Wrecks keep 70 % buoyancy and
  settle low. Capsized for 3 s -> scripted roll back upright at the surface (not on the seabed).
* **Boarding / exits** (`get_exit_transform`): a dry spot right beside the hull (pier, quay, beach)
  if there is one; else the deck spot of the seat's `Exit_*` marker (speedboat, dinghy); else the
  water beside the boat (jetski). A swimming player near the boat is given the deck spot, so the
  existing enter flow climbs over the side from the water; on a pier the pier spot is used.
* **FX**: `Fx.attach_trail(Wake_L/R, "wake")` with strength = speed / top speed while running near
  the camera (released when slow / far); for the player's boat expanding `Fx.water_ring`s behind the
  transom; alternating bow spray (`Fx.splash`) above 6 m/s; a slam splash after wave jumps; a splash
  when dropped into the water. No exhaust puffs. `engine_boat_loop` (rpm from throttle + speed).
* Sleep: boats only sleep further than 110 m from the camera (`detail_level` 2) without a driver;
  near the camera they stay awake so the waves move them.
* Moored boats (`set_moored(xform)`, `moored`): a soft, damped line to the berth until somebody
  boards (or the boat is pushed 8 m away).

Measured by `bkb_boat` (real world, waves): floats with the origin within 5-30 mm of the surface;
0-15 m/s 6.8 s, top 20.3 m/s (73 km/h); bow rise peak 6.5-7.1 deg, 3.4-4.6 deg on the plane; full
lock at speed turns 104 deg right / 90 deg left in 4 s with 7-8 deg of bank; coasts to < 0.5 m/s in
19 s; min up.y 0.994 through 30 s without input; beached at 19.5 m/s it stops ~11 m up the sand with
~1 hp of damage and reverses 9.4 m back into the water in 10 s. AI-driven (`set_inputs`, which also
casts off a mooring line): jetski 19.8 m/s and 91 deg of right turn in 3 s, dinghy 8.9 m/s and 55 deg.

## Marina moorings (`boat_spawner.gd`)

At `EventBus.game_ready` the registrar hook creates `BoatMoorings` under `Game.get_entities_root()`
(skipped when the vehicles system is disabled, when a world system named `boats` exists, or with
`--no_moorings`). It moors up to 5 boats: a `speedboat` at the named location `boat_spawn`, then
`jetski, speedboat, dinghy, jetski` spread over the world's `boat` spawn points (points within 9 m of
a used slip are skipped), `owner_tag "parked"`, slid sideways to lie 0.4 m off the nearest pier face,
on a soft line. Every 20 s a slip whose boat is destroyed, gone or > 60 m away (and is not the
player's / personal vehicle) gets a fresh boat while the player is > 120 m away. API: `slips`,
`get_slip_vehicle(i)`. It also works as a BootManifest world system (`setup()`).

## Tests

```powershell
$dis = '--disable=world,environment,city,interactions,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
tools\godot.ps1 -Mode headless -Frames 12000 -TimeoutSec 400 -UserArgs '--test=bkb_bike','--test-timeout=380',$dis
tools\godot.ps1 -Mode headless -Frames 14000 -TimeoutSec 560 -UserArgs '--test=bkb_boat','--test-timeout=520','--disable=traffic,peds,police,emergency,wildlife,props'
tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 120 -UserArgs '--test=bkb_shots','--test-timeout=100','--bkb_only=moto,boat','--disable=traffic,peds,police,emergency,wildlife,props,city'
```
`BKB_TABLE:` lines carry the measured numbers. `bkb_shots` writes `qa/screenshots/bkb_moto_lean.png`,
`bkb_bicycle_ride.png`, `bkb_marina.png`, `bkb_boat_planing.png`; `--bkb_only=moto,bicycle,marina,boat`
picks shots (a windowed run of 600 frames fits about two of them: game time runs at about half speed
in the capped window). `props` is disabled in the world runs only because the prop system was being
rewritten by its owner during this wave and broke the boot.

## Known limitations

* The lean is visual (the collision hull stays upright): at full lean the hull does not follow the
  silhouette.
* No deployable stand: a parked two-wheeler balances upright on its own.
* Bicycle feet sit on the crank axle: the humanoid animator has a single mirrored foot target
  (`peg_pos`), so the feet cannot follow the orbiting pedals.
* No bicycle bell sample exists; the bicycle horn is silent (it still emits the `horn` noise event).
* Waves exist only within 76 m of the camera (environment), so far boats float on a flat sea.
* The jetski rider uses `seated_car` until the player module honours `get_rider_pose()`.
* The Fx wake trail is a sparse line of foam blobs (3 pooled emitters, 20 particles each).
