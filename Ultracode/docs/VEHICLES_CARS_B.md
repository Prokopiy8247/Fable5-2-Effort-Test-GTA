# HALCYON BAY — vehicles of artist cars_b (`suv`, `pickup`, `van`, `police_cruiser`, `taxi`)

Builder: `tools/blender/assets/cars_b.py` (on top of `car_kit.py`, see `docs/VEHICLE_KIT.md` — every
kit convention applies unchanged: flat node list, pivots, rotation signs, hidden helper meshes).
Verifier: `tools\godot.ps1 -Mode script -Script res://gta/code/editor/cars_b_verify.gd`.

```python
import car_kit as K, cars_b as B; importlib.reload(K); importlib.reload(B)
B.build("suv"); B.shots("suv"); B.check("suv"); B.export("suv"); G.save()
B.build_all(); B.export_all(); B.group_preview()
```

| id | Blender slot / collection | stock size L × W(mirrors) × roof | wheel r | hull clearance | visible tris | whole file |
|---|---|---|---|---|---|---|
| `suv` | cars/10, Vehicles/Cars | 4.89 (4.72 bumper to bumper + spare) × 2.14 × 1.80 (1.87 rails) | 0.38 | 0.26 floor | 6816 | 8878 |
| `pickup` | cars/11, Vehicles/Cars | 5.42 × 2.22 × 1.84 | 0.40 | 0.33 floor | 6964 | 9078 |
| `van` | cars/12, Vehicles/Cars | 5.07 × 2.20 × 2.02 | 0.36 | 0.26 floor | 6502 | 6884 |
| `police_cruiser` | cars/13, Vehicles/Service | 5.05 (4.92 + push bumper) × 2.10 × 1.47 (1.60 light bar) | 0.35 | 0.18 floor | 6970 | 7344 |
| `taxi` | cars/14, Vehicles/Service | 4.84 × 2.10 × 1.74 (1.96 sign) | 0.34 | 0.20 floor | 6826 | 7260 |

## Nodes beyond the kit contract

| vehicle | node | what / pivot |
|---|---|---|
| `pickup` | `Tailgate` (mesh) | origin on the bottom hinge line (0, 0.69, 2.57 in Godot). Opens with **+`rotation.x`** (≈ 1.5 rad = flat). There is a real bed behind it (floor, inner walls, wheel houses). |
| `van` | `Door_RearL`, `Door_RearR` (meshes) | origin on the outer vertical edge at the door bottom. Hinge axis Godot Y: **L opens with negative `rotation.y`, R positive** (≈ ±1.75). The cargo bay behind them is open (floor, walls, bulkhead behind the seats). |
| `taxi` | `TaxiSign` (mesh) | roof sign, origin at its foot on the roof. Surfaces `P_NeonYellow` (emissive, strength 3 — switch it by overriding that surface), `P_Black`, `M_Trim`. |
| `police_cruiser` | `Siren` (marker) | centre of the light bar. The bar is part of `Body`: `M_Siren_Red` = left half, `M_Siren_Blue` = right half, plus one red and one blue strobe in the grille. |

`suv`, `police_cruiser`, `taxi` have 4 doors / 4 seats, `pickup` 4 doors / 4 seats, `van` 2 doors /
2 seats (no `Door_RL/RR`, no `Seat_Passenger_2/3`). `suv`, `pickup`, `van` have no `Trunk`.
Mod parts (all nine `Mod_*`): `suv` and `pickup` only. Two of them are class specific:
`Mod_BumperF_A` = tubular bull bar with two spot lamps (both), pickup `Mod_Roof_A` = sport bar with
four spot lamps behind the cab, pickup `Mod_Spoiler_B` = wing across the tail of the bed.
`Glass_Rear` of the van is one pane that stays in the body frame behind the two door windows.

## Liveries (fixed_livery specs)

The game reads the authored colour of `M_Paint_Primary`. In the .blend the taxi body uses the shared
palette material `P_TaxiYellow` and the cruiser body `P_PoliceBlue`; `B.export()` renames that
material to **`M_Paint_Primary`** inside the GLB (and sets roughness 0.35 / metallic 0.15), so:

* `taxi.glb`: `M_Paint_Primary` = TaxiYellow `#F5C518`; checker band = `P_White` + `P_Black` quads on
  body and doors; "TAXI" lettering `P_Black`.
* `police_cruiser.glb`: `M_Paint_Primary` = PoliceBlue `#1E3A6E` (fenders, hood, trunk, shield field,
  "HBPD" letters, roof number "07"); doors, pillars and roof = `P_PoliceWhite`; shield rim, sun and
  pinstripe = `P_BadgeGold`. No `M_Paint_Secondary` in this file.

All livery graphics are geometry: flat quads 4–11 mm off the panel, split per panel so the door
graphics are part of the `Door_*` meshes and swing with them. Repainting `M_Paint_Primary` keeps
the white / black / gold parts.

`Body_LOD1` carries the liveries in simplified form (white doors + red / blue bar on the cruiser,
sign block + coarse checker band on the taxi, dark bed cover on the pickup, blank side panels on the
van, spare wheel disc on the SUV).
