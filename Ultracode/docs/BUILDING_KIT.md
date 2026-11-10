# Building kit and generic buildings

Author: building-kit artist (Blender MCP). Art direction: "Sunlit Low-Poly" (ARCHITECTURE.md section 7).

| What | Where |
|---|---|
| Reusable kit (Blender, bmesh only) | `tools/blender/assets/building_kit.py` (`import building_kit as K`) |
| The 30 generic buildings | `tools/blender/assets/buildings_generic.py` (`import buildings_generic as B`) |
| Exports | `gta/generated/models/buildings/<id>.glb` |
| Manifest | `gta/generated/models/buildings/manifest_generic.json` |
| Godot verification tool | `gta/code/editor/bld_check_generic.gd` |
| Godot look-dev scene | `gta/tests/scenes/bld_showcase.tscn` (+ `gta/tests/bld_showcase.gd`) |
| Blender previews | `qa/blender_previews/bld_<id>.png`, `group_downtown.png`, `group_residential.png`, `group_industrial.png` |
| Godot screenshots | `qa/screenshots/bld_downtown.png`, `bld_residential.png`, `bld_industrial.png`, `bld_street.png`, `bld_dusk.png` |

Blender: collection `GTA_GODOT/Buildings`, slot region `buildings`, slots 0..29 (order = `B.ORDER`).

---------------------------------------------------------------------------------------------------

## 1. What the game gets (contract for the city builder)

### 1.1 GLB structure

```
<FileRoot> (Node3D)
  <id> (Node3D)                 asset root, origin = centre of the footprint on the ground
    Building         (mesh)     opaque shell. Always present. Defines the footprint.
    Building_Glass   (mesh)     every window pane; single material M_Window
    Building_Detail  (mesh)     small parts: awnings, sign boards, rails, fire escapes, AC units, antennas
    Building_Neon    (mesh)     emissive P_Neon* strips and block letters
```

- Front facade faces **-Z** in Godot (+Y in Blender). 1 unit = 1 m. Ground floor 4.0 m, upper floors
  3.2 m, 4 m module grid (houses use their own 2.75 m storeys).
- The shell continues 0.8 m below y = 0 (foundation skirt) so slightly uneven lots do not show gaps.
- Glass / Detail / Neon nodes are optional (a node is omitted when a building has nothing in it); the
  manifest lists the nodes of each building in `"nodes"`.
- Flat shading, palette materials only (`P_<PaletteKey>`), one shared material per colour, no textures.
- **Night windows:** all glass is `M_Window` and lives only in `Building_Glass`. Each pane is one quad
  with its own UV cell: `floor(UV)` is a per-pane id (cell k -> (k % 64, k / 64)), `fract(UV)` runs
  0..1 across the pane. A lit-window shader can pick lit / unlit panes with a hash of `floor(UV)`.
- **Neon:** `Building_Neon` only uses emissive `P_Neon*` materials (Blender strength 4.0, imported with
  emission enabled - verified). It can be dimmed by day with one material override per building.
- **LOD strategy:** `Building_Detail` and `Building_Neon` are separate so they can get a
  `visibility_range_end` (suggested 150-200 m, 60-90 m for houses); `Building` + `Building_Glass`
  stay visible. Tri counts are low enough that no extra LOD meshes were authored.

### 1.2 Manifest (`manifest_generic.json`)

```json
{"buildings": [{"id": "office_a", "file": "office_a.glb", "category": "office",
  "footprint": [24.04, 20.04], "height": 46.36, "landmark": "", "collision": "box",
  "entrance": [0.0, -9.7], "tags": ["downtown", "tall", "shops"],
  "roof_height": 39.2, "floors": 12, "tris": 4450, "center_offset": [0.0, 0.0],
  "collision_boxes": [[0.0, 19.6, 0.0, 23.4, 39.2, 19.4]],
  "nodes": ["Building", "Building_Detail", "Building_Glass", "Building_Neon"]}]}
```

Contract keys (ARCHITECTURE.md 8.4): `id, file, category, footprint [x, z], height, landmark, collision,
entrance [x, z], tags`. All numbers are measured from the built meshes, not typed by hand.

- `footprint` = bounding box of the `Building` node (the solid shell). Awnings, signs and canopies in
  `Building_Detail` / `Building_Neon` may stick out up to ~1.6 m in front of it (never solid).
- `height` = top of everything (antennas, signs); `roof_height` = main roof deck.
- `entrance` = main door on the footprint edge, Godot local space (x, z). Not always centred.
- `center_offset` = centre of the shell relative to the origin (|offset| < 0.5 m, usually 0).
- `collision_boxes` (extra) = optional tighter boxes `[cx, cy, cz, sx, sy, sz]` in Godot local space, one
  per mass (stepped towers, house + garage, porch slabs, docks). A simple `footprint x height` box
  also works; the boxes are better for stepped towers (`office_c`) and for helicopters.
- Extra keys on `parking_a`: `levels` (deck heights), `clear_height`, `entrance_width`, `ramps`
  (`from` / `to` centre-line points in Godot local space, `width`), `collision_nodes`.

### 1.3 Parking structure (`parking_a`, collision `trimesh`)

Three parking levels (ground slab y 0.12, deck 1 y 3.12, roof deck y 6.12), 32 x 28 m.
Use **only the `Building` node** for the trimesh collider (every face is single sided, slabs are closed).
Route up (Godot local space, front = -Z): enter through the 5.8 m wide opening in the middle of the
front, turn right along the front aisle, left down the west lane, left onto the back ramp (z = +10.8,
running toward +X) up to deck 1, left along the east lane, left onto the front ramp (z = -10.8, running
toward -X) up to the roof deck. Every turn is 90 degrees; lanes and ramps are 5.6-5.8 m wide.
Geometric check `B.drive_test()` (2 m wide probe along that route over the `Building` mesh):
continuous surface, biggest step 4.7 cm, steepest slope 18.8 %, smallest headroom 2.63 m (the entrance
beam; 2.7 m under the decks). It has not been driven with the game's vehicle physics yet.

---------------------------------------------------------------------------------------------------

## 2. The 30 buildings

Tri counts and sizes are the values verified in Godot (`bld_check_generic.gd`). Total 67,152 tris.

| id | category | footprint x, z (m) | height (m) | tris | description |
|---|---|---|---|---|---|
| office_a | office | 24.0 x 20.0 | 46.4 | 4450 | cream 12-storey commercial block, stone base with shops ("Bay Trust"), punched paired windows, cornice |
| office_b | office | 28.1 x 24.1 | 71.5 | 4108 | sky-blue glass curtain-wall tower on a white two-storey podium, "Azure" roof sign |
| office_c | office | 35.8 x 27.8 | 76.1 | 7070 | peach / coral stepped art-deco tower (3 tiers), teal crown and spire ("Coral Tower") |
| office_d | office | 20.0 x 20.0 | 59.8 | 2633 | slim glass tower with a cut corner (entrance on the chamfer), sloped coral crown ("Pelican") |
| office_e | office | 32.2 x 24.2 | 32.4 | 3868 | wide 7-storey brick newspaper block, ribbon windows, big "The Herald" roof sign |
| office_f | office | 24.2 x 24.6 | 74.0 | 4362 | concrete-fin slab tower with a taller mustard service core and a vertical "Talma" sign |
| apartment_a | apartment | 24.1 x 16.1 | 24.7 | 4232 | coral 6-storey block, cream stair tower, white colour-block balconies ("Sandpiper") |
| apartment_b | apartment | 28.0 x 19.9 | 38.0 | 4348 | white 9-storey slab, loggias between fins with teal / mustard checkerboard panels ("Marlin Court") |
| apartment_c | apartment | 20.3 x 16.0 | 20.8 | 3644 | 5-storey brick walk-up, stoop, cream lintels + cornice, front fire escape, water tank |
| apartment_d | apartment | 26.1 x 18.1 | 26.9 | 5118 | mint 7-storey mansion block, white bay stacks, railed balconies, penthouse under a red hip roof |
| house_a | house | 11.9 x 9.5 | 6.1 | 604 | cream ranch house, red gable roof, front-gabled garage, porch, brick chimney |
| house_b | house | 11.0 x 9.9 | 8.9 | 758 | two-storey sky-blue house, navy hip roof, bay window, portico, lean-to garage |
| house_c | house | 13.8 x 11.3 | 5.8 | 679 | peach L-shaped ranch, terracotta cross-gable roof, corner porch, integral garage |
| house_d | house | 11.8 x 9.7 | 7.6 | 448 | modern two-box house, white render + timber, charcoal slab roofs, carport, solar panel |
| house_e | house | 8.6 x 9.7 | 9.5 | 920 | tall mustard gable-front house, two storeys + attic, full-width porch, steep charcoal roof |
| house_f | house | 12.8 x 9.6 | 5.9 | 790 | lavender bungalow, grey hip roof, wrap-around porch, side garage |
| storefront_a | storefront | 20.4 x 12.4 | 9.8 | 1784 | peach 2-storey terrace of three shops (Koi Noodle, Moon Laundry, Vinyl Vault), flats above |
| storefront_b | storefront | 11.8 x 12.3 | 14.7 | 1404 | narrow 3-storey gable-front bookshop (Palm Books), teal shopfront, vertical blade sign |
| storefront_c | storefront | 23.8 x 14.1 | 8.6 | 1168 | single-storey supermarket (Bayfresh Market), red fascia band, glazed front, sign pylon |
| storefront_d | storefront | 15.9 x 14.1 | 12.8 | 1016 | art-deco arcade / picture house (Comet), lavender stepped facade, neon marquee and pylon |
| storefront_e | storefront | 13.9 x 12.5 | 10.5 | 1050 | mustard taqueria (Playa Tacos), coral base, serving hatch, railed balcony, red hip roof |
| storefront_f | storefront | 18.6 x 12.6 | 14.1 | 2360 | 3-storey brick block (Harbor Hardware, Bloom Florist), flats above, fire escape, water tank |
| warehouse_a | warehouse | 31.6 x 19.6 | 10.4 | 1902 | teal corrugated freight shed (Halcyon Freight), raised dock with 3 roll-up doors, roof lights |
| warehouse_b | warehouse | 39.9 x 28.0 | 27.9 | 3136 | brick cannery, saw-tooth hall, cream office annex, boiler house with two banded chimney stacks |
| warehouse_c | warehouse | 23.5 x 17.6 | 9.2 | 1348 | mustard barrel-roofed depot (Depot 7), big sliding door, lean-to office, fuel tank |
| warehouse_d | warehouse | 35.8 x 23.8 | 10.5 | 1760 | white logistics box (Bluefin Cargo), navy dado, orange stripe, 5 dock doors, glazed office corner |
| parking_a | parking | 32.0 x 28.0 | 10.4 | 1022 | open 3-level car park, two drivable ramps, stair core with a neon P (collision `trimesh`) |
| garage_row | misc | 16.0 x 6.7 | 3.2 | 446 | row of five lock-up garages with colour-coded numbered doors |
| shed_a | misc | 5.0 x 4.1 | 3.1 | 368 | olive board-and-batten tool shed with a flower box |
| kiosk_a | misc | 3.8 x 3.8 | 3.9 | 356 | street kiosk, serving hatch, striped awning, neon "Snacks" sign |

All business names are original and fictional. A lot must be at least as large as the footprint; leave
~1.6 m in front for awnings / marquees.

---------------------------------------------------------------------------------------------------

## 3. Using the kit (for the next artist)

Header of every MCP call:

```python
import sys, importlib
P = r"G:\YouTube\Fable 5.2 Effort Test GTA\Ultracode\tools\blender"
for p in (P, P + r"\assets"):
    if p not in sys.path: sys.path.append(p)
import gta_bl as G; importlib.reload(G)
import building_kit as K; importlib.reload(K)
G.assert_master()
```

A complete small building:

```python
b = K.Builder("my_shop", slot=40, scheme=dict(wall="Peach", base="Terracotta", trim="White"))
m = b.mass(-8, 8, -6, 6)                               # x0, x1, y0, y1; front = +Y
W = K.win(1.6, 1.5, frame="trim", sill_bar="trim")
sp = m.front.row(0.0, 4.0, [K.shop(door="center"), K.shop(door="none")], "base")
m.front.row(4.0, 3.2, [W] * 4)
for f in (m.right, m.back, m.left):
    f.stack(0.0, [(4.0, None, "base"), (3.2, [W] * f.nb)])
m.front.dress_shop(sp[0], "CAFE", "NeonMagenta")       # fascia sign + striped awning
b.belt(m.pts, 4.0)
b.flat_roof(m.pts, 7.2, parapet=0.7)
b.ac_unit(2.0, 0.0, 7.2)
b.entrance = (0.0, 6.0)
b.finish(category="storefront", tags=["midtown"])
K.preview("my_shop"); K.audit("my_shop"); K.measure("my_shop")
K.export("my_shop"); G.save()
```

Landmarks: `K.Builder(name, slot, scheme, region="landmarks", collection="Buildings/Landmarks")`,
`b.finish("landmark", tags, collision="trimesh", landmark="gun_shop")`, then
`K.write_manifest(path, [names])` for your own `manifest_<author>.json`.

### 3.1 Concepts

- **Builder** - one building. Collects faces into four parts (`body`, `glass`, `detail`, `neon`) that
  become the four mesh objects. Blender names carry the asset prefix (`my_shop_Building`);
  `K.export()` strips it for the export so the GLB has the clean contract names.
- **Mass** - `b.mass(x0, x1, y0, y1, z0=0)`: box volume with `.front` (+Y) `.back` `.left` (-X)
  `.right` faces and `.pts` (CCW plan). `b.faces(pts)` gives one Face per edge of any CCW polygon
  (cut corners, L shapes). Each mass also becomes one `collision_boxes` entry; `b.solid(...)` adds
  more (porch slabs, docks).
- **Face** - a facade frame: `u` to the right *as seen from outside*, `v` up, `d` outward. On the front
  face `u = x1 - x`. `f.sub(u0, u1)` is a coplanar part of a face, `f.side_face(...)` a perpendicular one.
- **Bay specs** - `K.win`, `K.door`, `K.shop`, `K.rollup`, `K.garage_door`, `K.louvre`; `None` = blank bay.
  `f.row(v0, h, bays, mat, widths=[...])` builds one storey and returns the bay spans;
  `f.stack(v0, [(h, bays, mat, kwargs), ...])` several storeys.
- **Materials** - every `mat` argument is a scheme role (`wall, wall2, base, trim, roof, door, metal,
  awning, awning2, sign, neon, accent, concrete`) or a `gta_bl.PALETTE` key. `M_Window` always goes to
  the glass part and `Neon*` keys to the neon part automatically.
- **Windings** - all faces are created with explicit outward windings and no normal recalculation, so
  open shells are safe. `K.preview()` renders with backface culling: a flipped face shows as a hole.

### 3.2 Catalogue

| Need | Call |
|---|---|
| wall panel, wall with openings | `f.rect`, `f.wall(u0, u1, v0, v1, mat, [K.Op(...)])`, `f.row`, `f.stack` |
| corrugated cladding | `f.row(..., corr=dict(pitch=1.0, depth=0.12))` or `f.corrugated(...)`; base course `f.dado(spans)` |
| window module | `K.win(w, h, sill, frame=, sill_bar=, bars=(nx, ny), panes=, shutters=, lintel=, planter=, awning=, balcony=)` |
| curtain wall | `f.curtain(v0, floors, floor_h, bay, spandrel, spandrel_mat, mull)` |
| storefront glazing | `K.shop(door="center"/"left"/"right"/"none", head=, margin=, riser=)` + `f.dress_shop(span, text, neon, mats)` |
| doors | `K.door(w, h, glass=, double=, transom=, frame=, canopy=dict(...))`; open doorway: section 3.3 |
| roll-up / garage doors | `K.rollup(w, h, mat=, slat=, lights=, sill=)`, `K.garage_door()` |
| awnings, canopies | `f.awning(u0, u1, v, depth, drop, stripes=, mats=)`, `f.canopy(u0, u1, v, depth, rods=True)` |
| signs | `f.sign(u0, u1, v0, v1, text, color=, border=)`, `f.text(...)`, `f.blade_sign(u, v0, v1, text=)`, `f.neon_line(...)`, `b.roof_sign(text, xc, y, z)` |
| cornices, belts, parapets | `b.cornice`, `b.belt`, `b.plinth`, `f.band`, `b.flat_roof(pts, z, parapet=)` |
| pilasters, fins | `f.pilaster`, `f.pilasters`, `f.fin` |
| balconies, fire escapes | `f.balcony(u0, u1, v, style="solid"/"rail"/"panel")`, `f.fire_escape(u0, u1, levels)` |
| porches, steps, docks | `f.porch(...)`, `f.steps(...)`, `f.dock(u0, u1, h, depth)` |
| bay / applied windows | `f.bay_window(...)`, `f.applied_window(uc, vc, w, h)` |
| roofs | `b.flat_roof`, `b.slab_roof`, `b.gable_roof`, `b.hip_roof`, `b.shed_roof`, `b.sawtooth_roof`, `b.barrel_roof`, `b.roof_lights` |
| rooftop details | `b.ac_unit`, `b.water_tank`, `b.antenna`, `b.dish`, `b.stair_box`, `b.skylight`, `b.vent`, `b.solar`, `b.planter`, `b.lamp_post` |
| chimneys, industry | `b.chimney`, `b.stack` (banded factory stack), `b.silo`, `b.tank_h` |
| drivable structure | `b.deck(x0, x1, y0, y1, z)`, `b.ramp(a0, a1, za, zb, b0, b1, axis)` (see `parking_a`) |
| free geometry | `b.box`, `b.poly`, `b.poly_dir`, `b.prism`, `b.extrude`, `b.tube`, `b.cyl`, `b.taper`, `b.ring`, `f.box`, `f.prism` |
| QA / export | `K.preview`, `K.closeup`, `K.audit`, `K.measure`, `K.export`, `K.manifest_entry`, `K.write_manifest` |

Block letters: `K.FONT` has A-Z, 0-9 and `& - + . ! ' : / *`; every pixel run is one quad.

### 3.3 Walk-in rooms (recipe, tested in Blender: preview `qa/blender_previews/zz_kit_walkin_test.png`)

Bay doors are closed panels. For an open doorway cut the hole with `K.Op` and line the room with an
inward-facing shell (a plan polygon wound clockwise makes `b.faces()` look into the room):

```python
T = 0.3                                                 # wall thickness
m = b.mass(-4, 4, -3, 3)
m.front.wall(0.0, m.front.w, 0.0, 3.2, "wall", [K.Op(3.0, 5.0, 0.0, 2.4, rec=T)]); m.front.top = 3.2
inner = list(reversed(K.rect_pts(-4 + T, 4 - T, -3 + T, 3 - T)))
room = b.faces(inner, 0.0, skirt=False)                 # room[0] = inside of the front wall
room[0].wall(0.0, room[0].w, 0.0, 3.0, "wall2", [K.Op(2.7, 4.7, 0.0, 2.4, rec=0.0)])
for f in room[1:]: f.rect(0.0, f.w, 0.0, 3.0, "wall2")
b.poly_dir([(x, y, 0.02) for x, y in inner], (0, 0, 1), "Wood")       # floor
b.poly_dir([(x, y, 3.0) for x, y in inner], (0, 0, -1), "White")      # ceiling
```

Use `collision="trimesh"` for such buildings.

### 3.4 Gotchas

- Things in the `body` part count for the footprint (roof overhangs, porches, docks, balconies): pull
  the mass in so the total hits the target. `K.measure()` prints the real numbers.
- Corrugated ribs stick out `depth` from the wall plane: stop eave-side walls ~10 cm below a pitched
  roof plane (see `warehouse_a`) or cover the rib tops with a `b.belt` gutter (`warehouse_c`).
- In corrugated rows do not pass `frame=` to `K.win` / `K.door`; the row adds its own chunky frames.
- A base band that is a separate storey cannot have ground-level doors through it: use one storey +
  `f.dado([(u0, u1), ...])` around the doors.
- `K.audit()` "suspect" faces are informational (faces buried in open-backed trims); duplicates and
  degenerate faces must be 0.
- Never re-use a slot index of another asset: `Builder(name)` rebuilds only the asset with that name.

---------------------------------------------------------------------------------------------------

## 4. Reproducing / QA

```python
import buildings_generic as B; importlib.reload(B)
B.run(["office_a"])          # rebuild + audit + measure + preview, one summary line
B.run(B.ORDER, preview=False, export=True)     # everything -> GLBs
B.write_manifest()           # manifest_generic.json from live measurements
B.drive_test()               # parking_a route / slope / headroom check
B.group_preview("downtown")  # also "residential", "industrial"
G.save()
```

Godot:

```powershell
tools\godot.ps1 -Mode script -Script res://gta/code/editor/bld_check_generic.gd      # all 30 GLBs vs manifest
tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/bld_showcase.tscn -Frames 300   # 5 screenshots
```

`bld_check_generic.gd` checks node structure and names, materials (M_Window only in `Building_Glass`,
emissive P_Neon* only in `Building_Neon`), glass UVs, footprint / height / centre / tri count against
the manifest. Last run: `BLD_CHECK_SUMMARY ok=30 bad=0 total_tris=67152`.

## 5. Known limits

- No interiors in the generic set (solid shells, box colliders); only `parking_a` is enterable.
- `apartment_d` (5118 tris) is slightly over the 5 k guide; `office_c` (7070) uses the tall-tower allowance.
- `house_e` is narrower (8.6 m) than the 10-14 m guide on purpose (tall gable-front type).
- `parking_a` was verified geometrically (`B.drive_test`), not yet with the vehicle physics.
- M_Window is a plain dark glass material in the GLBs; the lit-window shader is the game's job.
