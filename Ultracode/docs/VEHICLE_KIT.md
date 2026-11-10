# HALCYON BAY — Vehicle Kit (`car_kit.py`)

Owner: lead vehicle artist. Audience: every artist who builds a road vehicle, and the vehicle
programmer / integrator who consumes the GLBs.

| file | what it is |
|---|---|
| `tools/blender/assets/car_kit.py` | the parametric toolkit (`Car`, `MB`, wheels, export, QA helpers) |
| `tools/blender/assets/cars_sedan.py` | the reference car `sedan` + the four shared wheels — **copy this file's shape** |
| `tools/blender/assets/car_kit_examples.py` | unpolished starter parameter sets: `hatch`, `suv`, `wedge`, `pickup`, `van` |
| `gta/generated/models/vehicles/sedan.glb` | reference export |
| `gta/generated/models/vehicles/parts/wheel_{sport,classic,offroad,deep}.glb` | shared alternative wheels |

The module docstring of `car_kit.py` repeats the essentials; this file adds the reasoning, the
conventions the game code relies on, and what we learned while building the sedan.

---------------------------------------------------------------------------------------------------

## 1. Quick start

```python
import sys, importlib
P = r"G:\YouTube\Fable 5.2 Effort Test GTA\Ultracode\tools\blender"
if P not in sys.path: sys.path.append(P)
A = P + r"\assets"
if A not in sys.path: sys.path.append(A)
import gta_bl as G; importlib.reload(G)
G.assert_master()
import car_kit as K; importlib.reload(K)

params = dict(K.DEFAULTS)                 # DEFAULTS = the 4.6 m sedan
params.update(name="compact", width=1.68, ...)
car = K.build_car(params, G.slot("cars", 1), extras=my_extras)   # my_extras(car) is optional
car.report()                              # tri count per part
K.check_contract(car.name, mods=params["mods"])                   # missing contract nodes?
G.preview(car.name, "veh_compact", views=("three_quarter", "rear_quarter", "side", "front", "top", "back"))
K.preview_mods(car.name, "veh_compact_mods")                      # Mod_* parts visible
G.validate(car.name, max_tris=9000)
K.export_glb(car.name, "vehicles/compact.glb")                    # <- NOT G.export_glb (see §4)
G.save()
```

`K.build_car` = `K.Car(params, location)` → `car.build()` → `extras(car)` → `car.finish()`.
Everything is re-runnable: building a car of the same name replaces the old one.

Look at every preview with the Read tool. Use `K.preview_only(name, out, ["Body_LOD1", "Wheel_FL", ...])`
for the LOD / collision helpers and pose the doors (rotate `sedan:Door_FL` about Z, preview, rotate
back) to check what is visible when they open.

---------------------------------------------------------------------------------------------------

## 2. How a car is described

Car-local Blender space: **+Y nose, +X right, Z up, origin on the ground under the centre**.
`_L` = left = −X = driver side (right-hand traffic).

Three polylines, tail (−Y) → nose (+Y):

```
 z                      roof_r        roof_f
 ^                        ________________                       height
 |                       /                \
 |            deck_y    /                  \   cowl_y
 |  top:  *------------*....belt line.......*-------------*
 |        |  trunk                              hood       \*      <- top[-1] = nose top
 |        |        ___                         ___          |
 |  bottom:*______/   \_______________________/   \________*       <- arches cut automatically
 +-----------------axle_r----------------------axle_f-------------> y
```

* `top` — the shoulder line of the **lower body**: tail top, trunk deck, rear-glass base (must contain
  `deck_y`), belt line, windshield base (`cowl_y`), hood edge, nose top. The shell runs from
  `top[0].y` to `top[-1].y`; bumpers add ~5 cm at each end. The second-last key is the front edge of
  the hood (`hood="auto"`).
* `bottom` — lower edge of the body side. Wheel arches are cut as true semicircles of radius
  `wheel_r + arch_gap` around every axle; you never model them.
* `plan` — half-width factor seen from above. Keep it at 1.0 over both axles and taper only the last
  ~45 cm of nose and tail.

Cross-section at every station (`Car.section(y)`, +X half, mirrored automatically):

```
   C0----C1                 C0/C1  centre + crown edge   (crown, crown_w)
           \                P1     belt / shoulder edge  (shoulder_inset)     <- glass stands here
            P1              P2     crease                (crease_drop, crease_inset)
             \              Psw    swage line = max width (swage_z)            <- rub strip here
              P2            Prk    rocker top            (rocker_z, rocker_inset) <- door bottom
              |             Psl    sill                  (sill_inset, `bottom`)
              Psw           Wt/Wb  wheel-well wall, F0 floor
              |
              Prk
               \
   F0---Wb-Wt--Psl
```

Which strip of the loft becomes which part is decided per station range:

| strips | range | part |
|---|---|---|
| top (C0–P1) | hood range | `Hood` object (own slab, 1 cm seam) |
| top | trunk range | `Trunk` object |
| top | `deck_y`…`cowl_y` | left open — the interior tub and the greenhouse sit here |
| top | `open_top` ranges | left open (pickup bed; add your own tub) |
| shoulder + side (P1–Prk) | door ranges | `Door_*` objects (closed 5.5 cm slabs with inner card) |
| rocker (Prk–Psl) | everywhere | `Body` (`rocker_mat`) |
| under (Psl–F0) | everywhere | `Body`, `M_Underbody` |

The cabin is four numbers on top of that: `cowl_y`, `roof_f`, `roof_r`, `deck_y` (+ `height`,
`tumble`). Pillars are closed beams (`a_pillar`, `b_pillar`, `c_pillar`, `pillars_extra`), the roof
is a chamfered slab, the four panes are separate one-quad objects sitting 1.4 cm inside the frame.

### Build steps (`car.build()`)

`skin` → `greenhouse` → `interior` → `bays` → `front_fascia` → `rear_fascia` → `details` →
`closures` → `wheels` → `collision` → `lod` → `mods`; `finish()` creates the objects and markers.
Call the steps yourself when you want to skip or replace one (e.g. no `rear_fascia()` for a box
truck). Setting a fascia dictionary to `None` (`grille=None`, `head=None`, `bumper_r=None`,
`exhaust=None` …) skips just that piece.

### Own geometry

`car.body` is the `MB` (mesh builder) of the Body mesh; `car.mb("Name")` creates / returns the
builder of another child object (`car.mb("Mod_Spoiler_A")`, `car.mb("Door_Sliding_R")` …).

| `MB` method | use |
|---|---|
| `box(size, center, mat, rot=None, mirror=False, bevel=0)` | boxes, optionally mirrored to −X and chamfered |
| `cyl(radius, depth, center, mat, axis, segments, radius2, mirror)` | cylinders / cones |
| `loft(sections, mat, mats=, cap_mat=, mirror=, bevel=)` | closed solid through cross-sections |
| `prism(profile, lo, hi, mat, axis)` | extrude a 2D profile |
| `sweep(path, profile, mat)` | profile `(d, z)` along a plan path — bumpers, skirts (`car.u_path()` gives the nose / tail path) |
| `revolve(profile, mat, axis, segs)` | lathe — tyres, caps, steering wheel rim |
| `face(points, mat, mirror=, want=(nx,ny,nz))` | one polygon of an open shell, oriented by `want` |

Solids get outward normals immediately; shells keep the winding you give (or `want`).
Useful car queries: `car.w(y)` half-width, `car.zt(y)` shoulder height, `car.belt_x(y)`,
`car.side_x(y, z)` (x of the body side at a height), `car.arch_z(y)`, `car._gh()` (cabin corners),
`car.M["paint"|"paint2"|"trim"|"chrome"|"glass"|"interior"|"under"|"head"|"tail"|"indicator"|"reverse"|"plate"|"tire"|"rim"|"seat"]`.

---------------------------------------------------------------------------------------------------

## 3. Parameter reference

All lengths in metres. Sedan values in brackets.

| parameter | meaning |
|---|---|
| `name` | asset / root name = spec id (`sedan`) |
| `width` [1.80], `height` [1.45] | body width (without mirrors), roof height |
| `axle_f` [1.40], `axle_r` [−1.35], `axle_m` [None] | axle Y positions; `axle_m` adds `Wheel_ML/MR` |
| `wheel_r` [0.34], `wheel_w` [0.23], `track` [1.52] | wheel radius, tyre width, track (centre to centre) |
| `wheel_style` ["stock"] | `stock, sport, classic, offroad, deep, steel, truck` (`K.WHEEL_STYLES`) |
| `arch_gap` [0.05], `arch_segs` [8], `arch_lip` ["paint"] | arch clearance, segments, lip material (`"paint"`, `"trim"`, `None`) |
| `top`, `bottom`, `plan` | the three polylines (§2) |
| `crown` [0.03], `crown_w` [0.30] | centre rise of hood / trunk and half-width of the flat middle facet |
| `shoulder_inset` [0.09], `crease_drop` [0.10], `crease_inset` [0.02] | belt chamfer |
| `swage_z` [0.60], `rocker_z` [0.34], `rocker_inset`, `sill_inset` | max-width line, door bottom, tuck-under |
| `rocker_mat` ["trim"], `side_strip` ["trim"] | dark lower band; rub strip on the swage line (`None` = off) |
| `cowl_y` [0.95], `roof_f` [0.30], `roof_r` [−0.90], `deck_y` [−1.46] | cabin stations |
| `tumble` [0.13], `roof_t` [0.055], `roof_drop` [0.035] | glass lean-in, roof thickness, roof edge drop |
| `a_pillar` [0.13], `b_pillar` [0.09], `c_pillar` [(0.30, 0.20)], `pillar_w` [0.06] | pillar footprints |
| `pillars_extra` [[]] | `(y_base0, y_base1, y_top0, y_top1)` extra pillars or blank side panels |
| `roof_mat` ["paint"] | `"paint"`, `"paint2"` (two-tone roof), `"trim"` |
| `doors` | `[("F", y_rear, y_front), ("R", y_rear, y_front)]` → `Door_FL/FR`, `Door_RL/RR` |
| `door_hinge` | `{"F": "front", "R": "front"}`; `"rear"` = rear-hinged |
| `door_t` [0.055], `seam` [0.012] | door thickness, seam width |
| `hood`, `trunk` | `"auto"`, `(y_rear, y_front)` or `None` |
| `open_top` | `[(y0, y1)]` body top left open |
| `tub_z` [0.24], `seat_x` [0.37], `seat_f_y` [−0.10], `seat_r_y` [−0.95], `seat_z` [0.47] | cabin floor, hip points (`seat_r_y=None`: two-seater) |
| `seat_color` ["Khaki"] | palette key of the seat material |
| `head`, `tail` | `dict(w, h, inset, z)` lamp size; `z=None` = just under the shoulder |
| `grille` | `dict(bars=3)` between the head lamps, or `None` |
| `bumper_f`, `bumper_r` | `dict(h, out, wrap)` (+ optional `z0`) |
| `plate_f`, `plate_r`, `exhaust` | plates on/off, `dict(x, r)` tail pipe |
| `mods` | list of `Mod_*` names (`K.FULL_MODS` for compact, sedan, sports, muscle, suv, pickup) |
| `spoiler_at` ["deck"] | `"deck"` or `"roof"` (hatchbacks / SUVs) |
| `engine_y`, `siren` | `Engine` marker override; `siren=True` adds the `Siren` marker (`car.light_bar()` builds the bar) |

Rules of thumb that keep a parameter set healthy:

* **Fender must clear the tyre:** `zt(axle) − crease_drop > 2·wheel_r + arch_gap`. Otherwise the kit
  prints `ARCH CLAMPED` and flattens the arch — raise `top` over the axle, lower `crease_drop`
  (0.05 for low sports cars) or shrink the wheel.
* Doors start ≥ 10 cm behind the front arch (`axle_f − wheel_r − arch_gap − 0.1`) and end before the
  rear arch. The B pillar is placed at the rear edge of the first door automatically.
* Tyre outer face 2–3 cm inside the body side: `track ≈ width − wheel_w − 0.05`.
* `swage_z` a little below the arch top reads best (the rub strip is interrupted by the arches).
* Glass height (`height − belt`) of 0.45–0.52 m looks friendly; lower looks like a bunker.

---------------------------------------------------------------------------------------------------

## 4. Conventions the game code relies on

**Names.** Blender object names are global, so parts are called `<asset>:<part>` in the .blend
(`sedan:Body`). `K.export_glb()` = `G.export_glb()` + a rewrite of the GLB JSON chunk that strips
the `<asset>:` prefix, so Godot sees the exact contract names. Verified with
`tools\godot.ps1 -Mode script -Script res://gta/code/editor/print_scene_tree.gd`.

Imported structure: `FileRoot (Node3D) → sedan (Node3D) → flat list of parts` — everything is a
direct child of the asset root.

| node | type | pivot / orientation |
|---|---|---|
| `Body` | mesh | origin = car origin (ground, centre). Contains shell, pillars, roof, interior, seats, lamps, bumpers |
| `Wheel_FL/FR/RL/RR` | mesh (one shared mesh) | origin at wheel centre, **spin about local X**, steer about Y. Mirror-symmetric mesh: no flipping needed left/right |
| `Door_FL/FR/RL/RR` | mesh | origin on the hinge line (front edge, door bottom). Hinge axis = Godot Y. **Left doors open with negative `rotation.y`, right doors positive** (≈ ±1.0 rad) |
| `Hood` | mesh | origin at the rear edge (cowl). Opens with **+`rotation.x`** (≈ 0.9) |
| `Trunk` | mesh | origin at its front edge. Opens with **−`rotation.x`** (≈ −1.0) |
| `SteeringWheel` | mesh | origin at the hub, node is tilted −24° about X; **turn it with `rotation.z`** (steer right = negative) |
| `Glass_Windshield/Rear/L/R` | mesh, `M_Glass` | direct children of the root. `Glass_L/R` cover all side windows of that side and stay in the cabin frame when a door opens (the doors are the panels below the belt line) |
| `Seat_Driver`, `Seat_Passenger_1..3` | marker | hip point of the seated character, facing −Z. Driver = left front, 1 = right front, 2 = left rear, 3 = right rear |
| `Exit_Driver`, `Exit_Passenger_1..3` | marker | on the ground (y = 0), 0.75 m outside the body side at the door centre |
| `Light_Head_L/R` | marker | on the lamp, −Z = forward |
| `Light_Tail_L/R`, `Exhaust` | marker | rotated 180° about Y, so their −Z points backwards |
| `Engine` | marker | hood centre, at hood height (smoke / fire origin) |
| `Col_Body`, `Col_Cabin` | mesh, `P_Collision` | convex, 18 and 8 verts; build `ConvexPolygonShape3D` from them and hide them |
| `Body_LOD1` | mesh | whole car body in ~300 tris (paint, trim, glass, lamps). At distance show it and hide `Body`, `Door_*`, `Hood`, `Trunk`, `Glass_*`, `SteeringWheel`; wheels stay |
| `Mod_*` | mesh | authored in place, hide by default |

Hidden in Blender (eye icon + render) but always exported: `Mod_*`, `Col_*`, `Body_LOD1`.
Visibility is not stored in the GLB — **the game must hide them**.

**Materials** (shared contract materials, by `resource_name`): `M_Paint_Primary` (Body, doors,
hood, trunk, mods, LOD), `M_Paint_Secondary` (mods: wing end plates, roof box, diffuser fins, grille
badge), `M_Glass`, `M_Trim`, `M_Chrome`, `M_Interior`, `M_Underbody`, `M_Plate`, `M_Headlight`,
`M_Taillight`, `M_Indicator`, `M_ReverseLight`, `M_Tire`, `M_Rim`, `P_Khaki` (seats),
`P_Collision`; emergency vehicles add `M_Siren_Red` / `M_Siren_Blue`. To repaint, override every
surface whose material is named `M_Paint_Primary` on all meshes of the car. Lamps are surfaces of
`Body` — switch them by overriding the `M_Headlight` / `M_Taillight` / … surface material.
All materials export double-sided (Blender default); `M_Glass` is alpha-blended (0.45).
`G.mat()` never alters an existing material, so the stored values are those of the first author
that created each contract material in the shared .blend (at export time the lamp materials carry an
emission colour, chrome is metal 1.0 / rough 0.2).

**Mods** are separate direct children. If the vehicle code animates `Hood` / `Trunk` it should
re-parent `Mod_Hood_A` under `Hood` and `Mod_Spoiler_A/B` under `Trunk` at runtime.

**Shared wheels** `parts/wheel_<style>.glb`: `FileRoot → wheel_<style> → Wheel` (single mesh,
radius 0.34, width 0.23–0.25, origin at centre, axle along X, materials `M_Tire` + `M_Rim`,
symmetric). Swap by assigning its mesh to the four wheel nodes; scale by `wheel_r / 0.34` for cars
with another radius.

---------------------------------------------------------------------------------------------------

## 5. The reference sedan

4.60 m bumper to bumper (4.66 with plate and tail pipe), body 1.80 m wide (2.02 m over the mirrors),
roof at 1.45 m, wheelbase 2.75 m, track 1.52 m, wheels r 0.34 m, ground clearance 0.19 m.
Wheel centres in Godot space: FL (−0.76, 0.34, −1.40), FR (0.76, 0.34, −1.40), RL (−0.76, 0.34, 1.35),
RR (0.76, 0.34, 1.35).

| part | tris | | part | tris |
|---|---|---|---|---|
| Body | 3468 | | Mod_Spoiler_A (ducktail) | 36 |
| Door_FL / FR | 156 each | | Mod_Spoiler_B (wing) | 128 |
| Door_RL / RR | 88 each | | Mod_BumperF_A (air dam + splitter) | 168 |
| Hood / Trunk | 128 / 92 | | Mod_BumperR_A (diffuser) | 148 |
| Glass ×4 | 8 | | Mod_Hood_A (scoop) | 24 |
| SteeringWheel | 164 | | Mod_Skirts_A | 72 |
| Wheel ×4 (stock) | 456 each | | Mod_Roof_A (rack + box) | 304 |
| **visible stock car** | **6172** | | Mod_Exhaust_A (quad pipes) | 312 |
| Body_LOD1 | 306 | | Mod_Grille_A | 180 |
| Col_Body / Col_Cabin | 32 / 12 | | **whole file** | **7894** |

Shared wheels: sport 576, classic 576, offroad 648, deep 480 tris.
Example builds (visible tris, not shipped): hatch 6080, suv 6836, wedge 5988, pickup 6520, van 6132.

Previews (`qa/blender_previews/`): `veh_sedan.png` (six views), `veh_sedan_a.png`, `veh_sedan_b.png`
(close), `veh_sedan_c.png` (top + underside), `veh_sedan_open_a/b.png` (doors, hood, trunk posed
open), `veh_sedan_mods_a/b.png`, `veh_sedan_lod.png`, `veh_sedan_col.png`,
`veh_wheel_{sport,classic,offroad,deep}.png`, `kitdemo_*.png` (the example silhouettes).

---------------------------------------------------------------------------------------------------

## 6. What looked good / what looked bad

Good — keep doing it:

* **Real arches.** Semicircular cut-outs with a body-coloured lip sell "car" more than anything
  else; the dark well behind the tyre gives free contact shadow.
* **Dark base.** `rocker_mat="trim"` + dark valances under body-coloured bumpers make the car sit
  on the road instead of floating; the rub strip on the swage line breaks up the tall flat side.
* **Bezels.** Every lamp sits on a slightly larger dark box; the grille is dark with a few chrome
  bars. Light parts on dark backing read from far away.
* **Light seats** (`Khaki`) behind 45 % glass: the interior is visible from every angle. Dark seats
  disappear.
* **Facets instead of curves:** hood and trunk with a flat middle and two slopes (`crown`), a plan
  taper only at the very ends, a chamfered roof slab.
* Wheels a little too big (0.68 m on a sedan) — on-style and reads well in motion.

Bad — already fixed in the kit, do not reintroduce:

* `bmesh.ops.bevel` paints new chamfer faces with material slot 0 unless `material=-1` is passed —
  every bevelled seat and lamp had paint-coloured edges. `MB.bevel` handles it; use it.
* A bevelled box is 44 tris instead of 12. Bevel only what the camera really sees (seats, lamps,
  mirrors, bumpers come chamfered from their profiles).
* `hide_viewport` on helper meshes freezes their world matrix and `G.validate` then reports a 40 m
  long car. The kit hides with the eye icon (`hide_set`) + `hide_render`.
* Tyre lugs made by wobbling lathe rings looked like a damaged tyre; separate staggered blocks
  (style `offroad`) read correctly.
* A belt line at 1.0 m with a 1.45 m roof looked like an armoured car; 0.93–0.97 is right for a
  family car.
* Seat cushions must sit on the tub floor (`tub_z`), or they poke through the underbody.
* First-come material values: do not rely on tweaking a contract material from your module.

Known compromises:

* Side glass does not swing with the doors (contract keeps `Glass_L/R` as root children). The door
  is the panel below the belt line; with the door open the pane stays in the pillar frame.
* Door cut lines are vertical (station based), not raked.
* The body skin has no inner flange: with a door open you see the single-sided fender edge. The
  tub, B post and sill tops hide the rest.
* Windshield and rear glass are flat single quads.

---------------------------------------------------------------------------------------------------

## 7. Recipes

Start from `car_kit_examples.py` (`E.demo("suv", G.slot("cars", 34))` builds `kitdemo_suv`;
delete it afterwards with `G.delete_hierarchy`). Then make it yours.

| vehicle | what to change |
|---|---|
| compact / hatchback | 3.7 m `top` with a short tail, `deck_y` 20 cm before the tail, `trunk=None`, one door pair, `spoiler_at="roof"`, wheels 0.31 |
| sports (wedge) | nose key z ≈ 0.54, height 1.20, `roof_f` behind the driver's knees, `tumble` 0.17, `crease_drop` 0.05, `b_pillar=None`, `seat_r_y=None`, `grille=None`, slim lamps |
| muscle | long flat hood (`cowl_y` ≈ 0.45), short deck, belt 1.0, `c_pillar=(0.45, 0.30)`, wide `track`, `wheel_style="deep"`, add a hood bulge with `car.body.loft` |
| SUV | height 1.78, belt 1.08–1.12, `wheel_r` 0.38, `rocker_z` 0.46, roof to the tail, `pillars_extra` for the C pillar, `arch_lip="trim"`, `wheel_style="offroad"` |
| pickup | cabin ends mid-car (`deck_y` just behind `roof_r`), `open_top=[(bed)]`, `trunk=None`; bed tub + tailgate in `extras` (see `pickup_extras`) |
| van | `cowl_y` 1.5, short hood, roof to the tail, `tumble` 0.07, `pillars_extra=[(-2.30, 0.42, -2.26, 0.42)]` as blank side panel |
| box truck | van cab + `car.body.loft()` cargo box; `axle_m` for a third axle; `wheel_style="truck"` |
| police / taxi / ambulance | base car + `car.light_bar()` / roof sign in `extras`, `siren=True`, livery parts as extra `P_*` materials |

Replacing a generated part: drop it from `mods` (or set its fascia dict to `None`) and build your
own into `car.mb("Mod_Spoiler_A")` / `car.body` inside `extras`.

---------------------------------------------------------------------------------------------------

## 8. QA checklist before you export

1. `car.report()` — visible tris ≤ 7 k.
2. `K.check_contract(name, mods=..., doors=..., rear_seats=...)` — `missing=[]`, `badly_named=[]`.
3. Previews: six views, mods, LOD, doors posed open. Wheels inside the arches, no `ARCH CLAMPED`
   warning, no paint-coloured chamfers, nothing floating.
4. `G.validate(name)`; `K.export_glb(name, "vehicles/<id>.glb")`; `G.save()`.
5. Godot: `tools\godot.ps1 -Mode script -Script res://gta/code/editor/print_scene_tree.gd
   -UserArgs '--scene=res://gta/generated/models/vehicles/<id>.glb'` — clean node names, contract
   material names.
