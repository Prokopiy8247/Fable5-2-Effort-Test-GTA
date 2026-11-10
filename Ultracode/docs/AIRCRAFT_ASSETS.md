# Aircraft assets — integration notes (author: aircraft artist; revised by the aircraft critic pass)

GLBs: `res://gta/generated/models/vehicles/{heli_civil,heli_police,plane_prop,plane_jet}.glb`
Builder (reproducible): `tools/blender/assets/aircraft.py` (`A.build(id)`, `A.sheet(id, id, views, cols=3)` for the
tight QA contact sheet in `qa/blender_previews/<id>.png`, `A.export(id)`).
Checks: `tools\godot.ps1 -Mode script -Script res://gta/code/editor/aircraft_verify.gd` (contract nodes,
materials, pivots, hinge lines, glass parenting, seat / exit pairing, gear layout, tri budget, sizes) and `tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/air_showcase.tscn
-Frames 400` (screenshots `qa/screenshots/air_*.png`, incl. every moving part driven about its pivot).

All positions below are **Godot** coordinates in the asset root's space (nose = −Z, up = +Y, right = +X).
Origin = on the ground under the centre of gravity (helicopters: under the rotor mast); lowest point y = 0.

| id | size (x, y, z) m | tris | seats | notes |
|---|---|---|---|---|
| heli_civil | fuselage 2.30 × 3.12 × 9.38, rotor Ø 9.50 (2 blades, parked fore-aft) | 3370 | 4 | paint M_Paint_Primary / _Secondary (default orange / white); registration HB204 on boom and belly |
| heli_police | fuselage 2.59 × 3.64 × 10.69, rotor Ø 10.40 (4 blades, parked as an X) | 5058 | 2 + 2 gunners + 2 | fixed HBPD livery (POLICE on boom and belly, HBPD on the rear quarter panels, shield on the doors), **no** M_Paint_* slots — set `fixed_livery` in its VehicleSpec |
| plane_prop | 10.63 × 3.07 × 8.03 | 4142 | 4 | high wing, tricycle gear with wheel pants; wheelbase 2.17, track 2.60 |
| plane_jet | 8.82 × 3.40 × 11.41 | 4390 | 2 (tandem) | T-tail, aft engine pods, opening canopy; fixed (non-retracting) oleo gear in `Body`, wheelbase 4.61, track 2.60 |

## Moving parts (separate nodes; rotate about the node's LOCAL axis on top of its rest transform)

Several of these nodes have a non-identity rest rotation (dihedral, sweep, raked fin), so always do
`node.transform = rest * Transform3D(Basis(axis, angle), Vector3.ZERO)` — never write `rotation.x` directly.

| node | local axis | sense / remarks |
|---|---|---|
| `Rotor_Main`, `RotorBlur_Main` | Y | hub at (0, 2.99, 0) civil / (0, 3.42, 0) police. **Rotor diameter = `RotorBlur_Main` AABB (9.50 / 10.40)** — the `Rotor_Main` AABB is not the diameter (civil blades are parked fore-aft, police blades at 45°, AABB 7.6 m) |
| `Rotor_Tail` | X | civil: open 2-blade rotor at (−0.215, 1.935, 5.78); police: shrouded 8-blade fan at (0, 1.98, 6.62) |
| `Propeller`, `PropBlur` (plane_prop) | Z | at (0, 1.27, −2.72), Ø 1.9 |
| `Wheel_Nose`, `Wheel_L`, `Wheel_R` | X | radii: prop 0.19 / 0.22 / 0.22, jet 0.19 / 0.24 / 0.24; origin at the wheel centre, tyre touches y = 0 exactly. The legs / forks / doors are static geometry in `Body` (sized for the rest pose: keep visual suspension travel within about ±0.06 m) |
| `Aileron_L/R`, `Flap_L/R`, `Elevator` | X | + angle = trailing edge DOWN (roll right = Aileron_L +, Aileron_R −) |
| `Rudder` | Y | + angle = trailing edge toward +X |
| `Door_FL/FR` (+ `Door_RL/RR` on heli_civil) | Y | front-edge hinge; `VehicleBase._update_doors()` works unchanged. Door windows `Glass_L/R` (`Glass_RL/RR`) are children of their door |
| `Canopy` (plane_jet) | X | rear-edge hinge, + angle opens (≈ 38° looks right); `Glass_Canopy` is its child |
| `Searchlight` (heli_police) | — | origin at the gimbal (−0.50, 0.58, −2.28); the beam leaves along local −Z, so `look_at(target)` aims it; rest pose pitched 32° down; child marker `Searchlight_Beam` sits on the lens (spot light position) |
| `SensorBall` (heli_police) | any | origin at the ball centre |

## Helpers inside the GLB (plain visible meshes — game code must manage them)

- `Col_Body`, `Col_Tail` (+ `Col_Wing` on planes): convex hulls ≤ 32 verts, material `P_Collision`.
  `VehicleBase` already hides them and builds `ConvexPolygonShape3D`s from them.
  Helicopters: `Col_Body` includes the skid footprint down to y = 0, so use `hull_clearance = 0` and the
  helicopter rests on its hull. Planes: the hulls cover fuselage / wing / tail only (lowest point ≈ 0.75 m
  prop, 0.79 m jet) — the gear needs wheel raycasts or sphere shapes at `Wheel_*` (radii above).
- `RotorBlur_Main`, `PropBlur`: flat discs, material `M_RotorBlur` (alpha 0.25, imported as alpha
  depth-pre-pass, double sided). **Hide them while the rotor is stopped, show them above ~40 % rpm, and set
  `cast_shadow = SHADOW_CASTING_SETTING_OFF`** — otherwise the disc throws a solid circular shadow
  (visible in `qa/screenshots/air_heli_civil_pose.png`). The jet has no blur helper.
- `VehicleBase._measure_body()` uses the `Body` node only, so `body_aabb` excludes rotors and helpers.

## Markers (Node3D)

`Seat_Driver` (left seat; jet: front seat), `Seat_Passenger_1..3` (jet: only `_1`), heli_police additionally
`Seat_Gunner_L/R` on the outward-facing benches in the open side bays (their basis faces outward; the rear
bench places `Seat_Passenger_2/3` face outward too). `Exit_Driver`, `Exit_Passenger_1..3`,
`Exit_Gunner_L/R` are on the ground beside the matching door. `Engine` (smoke / fire), `Exhaust` or
`Exhaust_L/R`, `Light_Head` + `Light_Head_L/R` (landing lights; `VehicleLights` reads the `_L/_R` pair),
`Light_Tail` + `Light_Tail_L/R`, `Light_Beacon`, `Light_Nav_L/R` (planes), `Siren` (heli_police belly strobes).

## Materials

Contract materials used: `M_Paint_Primary`, `M_Paint_Secondary` (not on heli_police), `M_Glass`, `M_Trim`,
`M_Chrome`, `M_Interior`, `M_Tire`, `M_Rim`, `M_Headlight` (landing lights, searchlight lens), `M_Taillight`
(red beacons, left nav light), `M_Siren_Red` / `M_Siren_Blue` (heli_police strobes), `M_RotorBlur`,
`P_Collision`, plus palette `P_*` colours. `P_NeonGreen` (right nav light) and `P_NeonCyan` (cockpit
screens) are emissive. Fictional registrations (`HB204`, `HB318`, `HB900`), the HBPD shield and the
`POLICE` / `HBPD` lettering are raised geometry (6–12 mm proud), not textures.
