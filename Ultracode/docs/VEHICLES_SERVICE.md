# HALCYON BAY — Service vehicles (`cars_service.py`)

Owner: vehicle artist `cars_service`. Audience: vehicle programmer / integrator.
Assets: `ambulance`, `firetruck`, `swat_van`, `box_truck` → `gta/generated/models/vehicles/<id>.glb`.
Builder: `tools/blender/assets/cars_service.py` (uses `car_kit.py`, see `docs/VEHICLE_KIT.md`).
Everything in `docs/VEHICLE_KIT.md` §4 (names, pivots, opening signs, markers) also holds here;
this file only lists what is different.

## Rebuild

```python
# inside an execute_blender_code call, after the gta_bl header with tools/blender/assets on sys.path
import car_kit as K, cars_service as S
importlib.reload(K); importlib.reload(S)
S.build("firetruck")        # one vehicle (rebuilds in place at its slot) + 6-view preview
S.export("firetruck")       # G.validate + K.export_glb
S.build_all(); S.export_all(); S.group_preview(); G.save()
```
Blender slots: region `service` 0 ambulance, 1 firetruck, 2 swat_van, 3 box_truck.
Collections: `Vehicles/Service` (ambulance, firetruck, swat_van), `Vehicles/Cars` (box_truck).
Godot checks: `tools\godot.ps1 -Mode script -Script res://gta/code/editor/cars_service_verify.gd`
(contract + pivots of all four) and
`tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/svc_showcase.tscn -Frames 400` (screenshots
`qa/screenshots/svc_*.png`).

## The four vehicles

| id | what | L × W × H (m) | wheels | visible tris | LOD1 |
|---|---|---|---|---|---|
| `ambulance` | van-chassis cab + modular box, fairing over the cab, teal band, plus-in-circle emblem | 6.15 × 2.26 (2.42 over mirrors) × 2.87 | r 0.42, front track 1.71, rear twin, wheelbase 3.40 | 7030 | 316 |
| `firetruck` | cab-over crew-cab pumper, tandem rear axles, pump panel, hose reels, deck gun, ladder, suction hoses, shutters | 8.30 × 2.50 (2.83 over mirrors) × 3.15 | r 0.50, 3 axles (F single, M + R twin) | 8534 | 408 |
| `swat_van` | armoured tactical truck: long angular hood, one-piece hull, port windows, raised troop roof, hatch, ram bar, running boards | 6.30 × 2.30 (2.76 over mirrors / boards) × 2.75 | r 0.48 block-tread singles, wheelbase 3.40 | 7264 | 392 |
| `box_truck` | low-cab-forward delivery truck, separate cab and cargo box, roll-up rear door, exhaust stack, tank, under-run guards | 7.18 × 2.40 (2.45 over mirrors) × 3.20 | r 0.44, front single, rear twin, wheelbase 4.22 | 5666 | 294 |

Wheel centres in Godot space (x, y, z): ambulance F (±0.855, 0.42, −1.95) R (±0.815, 0.42, 1.45);
firetruck F (±1.05, 0.50, −2.50) M (±0.91, 0.50, 1.44) R (±0.91, 0.50, 2.76);
swat_van F (±0.96, 0.48, −1.85) R (±0.96, 0.48, 1.55); box_truck F (±0.89, 0.44, −2.52) R (±0.89, 0.44, 1.70).

## Differences to a kit car

* **Paint.** `ambulance`, `firetruck`, `swat_van` are fixed liveries (the registry never repaints
  them), so their bodies use palette materials instead of `M_Paint_Primary`:
  `P_AmbulanceWhite` + `P_Teal`; `P_FireRed` + `P_White` (roof, band) + `P_HazardYellow` (rear
  chevrons) + `P_BadgeGold`; `P_UniformNavy` + `P_TacticalBlack` + `P_White` (pin stripe) + `P_BadgeGold`.
  They have **no `M_Paint_Primary` surface**. `box_truck` is repaintable: `M_Paint_Primary` = cab and
  the band + chevrons on the box, `M_Paint_Secondary` = the cargo box itself.
* **Twin rear wheels.** `Wheel_RL/RR` (and `Wheel_ML/MR`) of ambulance, firetruck and box_truck are
  one node holding both tyres (mesh `WheelTwin`, 0.55–0.61 m wide, origin in the middle of the pair,
  mirror-symmetric). Front wheels use mesh `Wheel`.
* **`Col_Box`.** Box vehicles have three convex helpers: `Col_Body` (lower cab), `Col_Cabin`
  (greenhouse) and `Col_Box` (the whole rear body, 12 verts). `vehicle_base.gd` already turns every
  `Col_*` into a shape. `swat_van` has the usual two.
* **Rear barn doors** of ambulance and swat_van are `Door_RL` / `Door_RR`: hinge origin on the outer
  rear corner, same sign convention as side doors (left negative `rotation.y`, right positive). Their
  panes are **nested** children `Glass_Rear_L` / `Glass_Rear_R` and swing with the doors; these two
  vehicles have no root-level `Glass_Rear`. The ambulance box has two more panes, `Glass_Box_L` /
  `Glass_Box_R`. Firetruck `Door_RL/RR` are the crew-cab side doors.
* **swat_van seats 2 / 3** sit on the rear bench; `Exit_Passenger_2/3` are on the ground 0.75 m behind
  the rear step, so the rear doors are the right doors for them.
* **box_truck `Trunk`** = the roll-up door, origin on its top edge (opens like a hatch with
  −`rotation.x`); a dark panel behind it stands in for the cargo space. No `Hood` on the two cab-overs
  (firetruck, box_truck); ambulance and swat_van have one.
* **Markers.** `Siren` on the three emergency vehicles (centre of the light bar). `Exhaust`: ambulance
  right rear flank, firetruck under the cab on the right, swat_van rear left, box_truck = top of the
  vertical stack behind the cab (2.7 m up). `Engine`: hood centre (ambulance, swat_van) or behind the
  grille (firetruck, box_truck).
* Light bars use `M_Siren_Red` / `M_Siren_Blue` as surfaces of `Body`; the extra warning lamps on
  the box corners, cab face and rear headers are `M_Siren_Red` too, so they flash with the bar.

## Previews

`qa/blender_previews/veh_<id>.png` (six views), `veh_<id>_a.png` (close three-quarter pair),
`veh_<id>_open.png` (doors / hood / roll-up door posed open), `veh_<id>_lod.png`, `veh_<id>_col.png`,
`veh_service_group.png` (all four side by side). In-engine: `qa/screenshots/svc_group_front.png`,
`svc_group_rear.png`, `svc_<id>_a.png`, `svc_<id>_b.png`, `svc_<id>_lod1.png`.
Workbench previews draw `M_Chrome` (metal 1.0) dark grey; in Godot it is bright chrome.
