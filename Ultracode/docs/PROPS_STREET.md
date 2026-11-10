# Street furniture props (STREET FURNITURE ARTIST)

73 Blender-authored props for Halcyon Bay, all in the "Sunlit Low-Poly" style (flat-shaded facets,
chamfers, palette colours only, no image textures). Total 31668 triangles, 104 - 884 per prop
(budget 30 - 900).

| what | where |
|---|---|
| GLB exports | `gta/generated/models/props/<id>.glb` (73 files) |
| manifest | `gta/generated/models/props/manifest_street.json` |
| Blender source | master .blend, collection `GTA_GODOT/StreetProps`, slot region `props` indices 0 - 83 |
| builder code | `tools/blender/assets/props_street.py` (helpers, registry, signals / lamps / signs) + family modules `props_street_road.py`, `props_street_furniture.py`, `props_street_utility.py`, `props_street_fences.py`, `props_street_crates.py`, `props_street_signage.py` |
| Blender previews | `qa/blender_previews/prop_<id>.png` (one per prop), `qa/blender_previews/props_family_<family>.png` (10 family sheets) |
| Godot verification tool | `gta/code/editor/props_street_verify.gd` |
| Godot look-dev scene | `gta/tests/scenes/props_street_showcase.tscn` -> `qa/screenshots/props_street_<category>.png` |

## 1. Conventions (what the game can rely on)

- **Scale / axes:** real-world metres. Blender front = +Y, so in Godot every prop **faces -Z**; right side = +X.
- **Origin:** bottom centre on the ground (`anchor: "ground"`), on the roof surface (`"roof"`), or the
  centre of the wall plate with the wall plane at local z = 0 and the prop sticking out toward -Z (`"wall"`:
  `wall_lamp`, `neon_sign_a/b/c`; `fire_escape_ladder` has its origin at the bottom of the ladder plane with
  the wall 0.20 m behind it at Godot z = +0.20).
- **Node structure:** `FileRoot (Node3D) -> <id> (Node3D) -> Mesh (MeshInstance3D)` plus, only where parts
  move or light up, extra `MeshInstance3D` children and marker `Node3D`s (table below). Find them with
  `find_child("Mesh", true, false)`, `find_child("Lamp_Red", true, false)` ...
- **Materials:** shared palette materials `P_<PaletteKey>` (59 materials over the whole set, one per colour)
  and these contract names:
  - `M_LampGlow` - lamp lenses (emissive, warm). The environment module's night hook
    (`env.apply_night_materials(root)`) swaps it by name; used by `street_lamp_a`, `street_lamp_b`,
    `wall_lamp`, `bollard_light`, `billboard`, `billboard_roof`.
  - `P_Neon*` - emissive neon tubes (also swapped by the night hook): `neon_sign_a/b/c`, `billboard_roof`,
    a small indicator on `atm`.
  - `M_ScreenGlow` - lit screens / light boxes (emissive, always on): `vending_machine`, `atm`,
    `phone_kiosk`, the advert panel of `bus_stop`.
  - `M_Signal_Red`, `M_Signal_Yellow`, `M_Signal_Green` - traffic-signal lenses, **unlit by default** (dark
    tinted, no emission). To light a lamp, give its node a surface-override material (emissive
    red / amber / green); to switch it off remove the override.
  - `M_Glass` - shelter glazing (alpha 0.45), only on the `Glass` child of `bus_stop`.
  - `M_Billboard_A` (billboard) / `M_Billboard_B` (billboard_roof) - the advert face. Those polygons have a
    0 - 1 UV square (u left-to-right as read from the front, v up), so the game may override the material
    with its own advert texture / shader. The default artwork is separate geometry 2.5 cm in front of the
    face; hide nothing, it simply covers the face.
  - `P_SirenBlue` - beacons on `roadblock_police` (mildly emissive).
- **Collision:** not included in the GLBs. Use the manifest `size` + `center` (Godot axes, relative to the
  origin) for a box; `collision` hints: `"none"` (flush ground plates: `manhole`, `drain`, `tree_grate`),
  `"trimesh"` (`bus_stop`, `billboard`, `billboard_roof`, `speed_bump`), otherwise a box / convex hull is fine.
- **Tiling pieces** carry `tile` (pitch in metres along X): fences / wall / hedge / curb / guardrail 4.0,
  `barrier_concrete` 3.0, `barrier_plastic` 2.0, `barrier_fence` 2.3. Fence end posts are centred on
  x = +-2, so neighbouring segments share a post.
- **LOD / draw distance:** every entry has `vis_range` (suggested `visibility_range_end`: 70 m for props
  under 1 m, 120 m under 2.6 m, 260 m for tall ones). The meshes are small enough that no second LOD mesh
  was authored; use `MultiMeshInstance3D` for anything repeated often (cones, bollards, fences, curbs).

## 2. Manifest format

`{"author": "street_furniture", "props": [ ... ]}`; one entry per prop:

| key | meaning |
|---|---|
| `id`, `file` | prop id and GLB file name (same folder) |
| `category` | `signal`, `lamp`, `sign`, `barrier`, `road`, `furniture`, `utility`, `fence`, `container`, `signage` |
| `size` | AABB size `[x, y, z]` in Godot axes (y = height) |
| `center` | AABB centre relative to the origin, Godot axes |
| `physics` | `static`, `dynamic` or `breakable` |
| `mass` | kg |
| `surface` | one of `Fx.SURFACES` (`metal`, `wood`, `concrete`, `rubber`, `foliage`) |
| `anchor` | `ground`, `wall` or `roof` |
| `tris` | triangle count of the whole prop |
| `children` | mesh child names (`Mesh` + extras) |
| `markers` | marker `Node3D` names |
| `vis_range` | suggested visibility range (m) |
| `tile`, `collision`, `emissive`, `notes` | optional hints |

## 3. Prop list

Size is width x height x depth in Godot axes (metres).

| id | category | size | tris | physics | mass kg | surface | anchor | extra children / markers |
|---|---|---|---|---|---|---|---|---|
| `traffic_light` | signal | 5.57 x 6.92 x 0.91 | 812 | static | 340 | metal | ground | Lamp_Green, Lamp_Red, Lamp_Yellow |
| `traffic_light_ped` | signal | 0.34 x 2.96 x 0.55 | 536 | breakable | 45 | metal | ground | Lamp_Stop, Lamp_Walk |
| `street_lamp_a` | lamp | 0.54 x 8.82 x 3.55 | 368 | breakable | 180 | metal | ground | Light |
| `street_lamp_b` | lamp | 0.64 x 4.64 x 0.61 | 494 | breakable | 70 | metal | ground | Light |
| `wall_lamp` | lamp | 0.40 x 0.42 x 0.75 | 324 | static | 4 | metal | wall | Light |
| `sign_stop` | sign | 0.78 x 2.95 x 0.17 | 248 | breakable | 14 | metal | ground | - |
| `sign_yield` | sign | 0.90 x 2.95 x 0.17 | 104 | breakable | 12 | metal | ground | - |
| `sign_speed` | sign | 0.80 x 2.95 x 0.17 | 380 | breakable | 12 | metal | ground | - |
| `sign_oneway` | sign | 0.98 x 2.98 x 0.17 | 156 | breakable | 11 | metal | ground | - |
| `sign_parking` | sign | 0.62 x 2.95 x 0.17 | 164 | breakable | 12 | metal | ground | - |
| `sign_street` | sign | 0.96 x 3.50 x 0.96 | 406 | breakable | 13 | metal | ground | - |
| `sign_noentry` | sign | 0.80 x 2.95 x 0.17 | 272 | breakable | 12 | metal | ground | - |
| `barrier_concrete` | barrier | 2.98 x 0.85 x 0.61 | 212 | static | 1800 | concrete | ground | - |
| `barrier_plastic` | barrier | 2.14 x 0.93 x 0.55 | 304 | dynamic | 60 | rubber | ground | - |
| `barrier_fence` | barrier | 2.31 x 1.10 x 0.62 | 468 | dynamic | 18 | metal | ground | - |
| `roadblock_police` | barrier | 2.60 x 1.21 x 0.74 | 628 | dynamic | 22 | wood | ground | - |
| `cone` | barrier | 0.40 x 0.75 x 0.40 | 200 | dynamic | 3.5 | rubber | ground | - |
| `delineator` | barrier | 0.30 x 1.10 x 0.30 | 182 | dynamic | 4 | rubber | ground | - |
| `bollard` | barrier | 0.27 x 0.96 x 0.26 | 178 | static | 60 | metal | ground | - |
| `bollard_light` | barrier | 0.25 x 0.90 x 0.24 | 334 | static | 25 | metal | ground | Light |
| `curb_straight` | road | 3.99 x 0.15 x 0.30 | 192 | static | 320 | concrete | ground | - |
| `curb_corner` | road | 1.14 x 0.15 x 1.14 | 228 | static | 130 | concrete | ground | - |
| `speed_bump` | road | 3.00 x 0.07 x 0.42 | 196 | static | 45 | rubber | ground | - |
| `guardrail` | road | 4.00 x 0.80 x 0.23 | 196 | static | 110 | metal | ground | - |
| `jersey_end` | road | 1.49 x 0.83 x 0.60 | 172 | static | 700 | concrete | ground | - |
| `parking_stop` | road | 1.80 x 0.11 x 0.19 | 120 | static | 95 | concrete | ground | - |
| `bench` | furniture | 1.72 x 0.86 x 0.70 | 732 | breakable | 55 | wood | ground | - |
| `bench_park` | furniture | 2.00 x 0.91 x 0.59 | 380 | breakable | 120 | wood | ground | - |
| `bin` | furniture | 0.58 x 1.10 x 0.55 | 462 | dynamic | 28 | metal | ground | - |
| `dumpster` | furniture | 1.96 x 1.20 x 1.24 | 644 | static | 380 | metal | ground | Lid |
| `recycling_bins` | furniture | 1.76 x 1.00 x 0.74 | 672 | dynamic | 42 | rubber | ground | - |
| `hydrant` | furniture | 0.49 x 0.80 x 0.43 | 552 | breakable | 65 | metal | ground | - |
| `mailbox` | furniture | 0.55 x 1.18 x 0.52 | 232 | breakable | 70 | metal | ground | - |
| `newspaper_box` | furniture | 0.48 x 1.25 x 0.43 | 208 | breakable | 38 | metal | ground | - |
| `parking_meter` | furniture | 0.43 x 1.39 x 0.17 | 408 | breakable | 22 | metal | ground | - |
| `bike_rack` | furniture | 2.30 x 0.90 x 0.64 | 592 | static | 60 | metal | ground | - |
| `bus_stop` | furniture | 4.00 x 2.95 x 1.84 | 828 | breakable | 420 | metal | ground | Glass |
| `phone_kiosk` | furniture | 0.96 x 2.20 x 0.64 | 584 | static | 160 | metal | ground | - |
| `vending_machine` | furniture | 1.01 x 1.86 x 0.83 | 868 | static | 260 | metal | ground | - |
| `atm` | furniture | 0.90 x 1.94 x 0.97 | 564 | static | 300 | metal | ground | - |
| `planter` | furniture | 1.10 x 1.17 x 1.10 | 382 | static | 450 | concrete | ground | - |
| `tree_grate` | furniture | 1.20 x 0.03 x 1.20 | 372 | static | 90 | metal | ground | - |
| `manhole` | furniture | 0.88 x 0.04 x 0.88 | 376 | static | 80 | metal | ground | - |
| `drain` | furniture | 0.72 x 0.03 x 0.46 | 156 | static | 45 | metal | ground | - |
| `utility_box` | utility | 1.25 x 1.43 x 0.56 | 364 | static | 180 | metal | ground | - |
| `transformer` | utility | 1.90 x 1.75 x 1.50 | 884 | static | 1400 | metal | ground | - |
| `power_pole` | utility | 2.50 x 9.54 x 0.87 | 666 | static | 520 | wood | ground | Wire_1, Wire_2, Wire_3, Wire_4 |
| `ac_unit` | utility | 1.20 x 0.71 x 0.50 | 764 | static | 55 | metal | roof | - |
| `satellite_dish` | utility | 1.27 x 1.71 x 0.90 | 344 | static | 18 | metal | roof | - |
| `water_tank` | utility | 2.50 x 4.25 x 2.53 | 730 | static | 2200 | wood | roof | - |
| `vent_pipe` | utility | 1.27 x 1.42 x 0.72 | 448 | static | 30 | metal | roof | - |
| `fire_escape_ladder` | utility | 0.57 x 4.00 x 0.21 | 324 | static | 45 | metal | wall | Ladder_Bottom, Ladder_Top |
| `fence_chainlink` | fence | 4.10 x 2.08 x 0.12 | 522 | breakable | 60 | metal | ground | - |
| `fence_wood` | fence | 4.12 x 1.85 x 0.16 | 416 | breakable | 85 | wood | ground | - |
| `fence_metal` | fence | 4.13 x 1.19 x 0.13 | 456 | breakable | 70 | metal | ground | - |
| `wall_low` | fence | 4.00 x 1.00 x 0.38 | 376 | static | 1900 | concrete | ground | - |
| `hedge` | fence | 4.00 x 1.21 x 1.02 | 268 | static | 120 | foliage | ground | - |
| `gate_chainlink` | fence | 4.18 x 2.23 x 0.18 | 752 | breakable | 110 | metal | ground | Gate_L, Gate_R |
| `crate_wood` | container | 0.91 x 0.90 x 0.91 | 216 | dynamic | 45 | wood | ground | - |
| `crate_stack` | container | 1.87 x 1.60 x 1.54 | 816 | dynamic | 150 | wood | ground | - |
| `pallet` | container | 1.20 x 0.14 x 1.00 | 228 | dynamic | 22 | wood | ground | - |
| `barrel` | container | 0.58 x 0.89 x 0.58 | 480 | dynamic | 30 | metal | ground | - |
| `barrel_explosive` | container | 0.58 x 0.89 x 0.58 | 540 | dynamic | 60 | metal | ground | - |
| `gas_canister` | container | 0.33 x 0.60 x 0.33 | 392 | dynamic | 24 | metal | ground | - |
| `tire_stack` | container | 1.04 x 0.84 x 0.72 | 636 | dynamic | 45 | rubber | ground | - |
| `trash_bags` | container | 1.20 x 0.60 x 0.97 | 312 | dynamic | 14 | rubber | ground | - |
| `cardboard_boxes` | container | 1.42 x 0.71 x 1.11 | 192 | dynamic | 9 | wood | ground | - |
| `shopping_cart` | container | 0.57 x 1.01 x 1.02 | 664 | dynamic | 22 | metal | ground | - |
| `neon_sign_a` | signage | 1.33 x 1.85 x 0.11 | 364 | static | 14 | metal | wall | - |
| `neon_sign_b` | signage | 1.64 x 1.74 x 0.11 | 464 | static | 16 | metal | wall | - |
| `neon_sign_c` | signage | 2.10 x 1.07 x 0.11 | 656 | static | 18 | metal | wall | - |
| `billboard` | signage | 7.20 x 7.58 x 2.07 | 880 | static | 2600 | metal | ground | - |
| `billboard_roof` | signage | 6.14 x 3.68 x 2.66 | 628 | static | 900 | metal | roof | - |

## 4. Per-prop notes

- **`traffic_light`** - Pole at the kerb, mast arm reaches 5.3 m toward +X (Godot +X), lamps face +Y (Godot -Z). Lamp_Red/Lamp_Yellow/Lamp_Green each hold the arm lens and the pole repeater lens; node origin = arm lens centre. Lens materials M_Signal_* are unlit (dark) by default.
- **`traffic_light_ped`** - Pedestrian signal on a post, faces +Y. Lamp_Stop (upper, standing figure) and Lamp_Walk (lower, walking figure) are separate unlit lens meshes; node origin = lens centre.
- **`street_lamp_a`** - Tall road lamp; the arm reaches 3.3 m toward +Y (Godot -Z, over the road). Lens = material M_LampGlow; marker 'Light' just below the lens.
- **`street_lamp_b`** - Promenade / park lamp, 4.6 m. Lantern lens = M_LampGlow; marker 'Light' at the lens centre.
- **`wall_lamp`** - Wall-mounted gooseneck lamp. Origin = centre of the wall plate (wall plane y = 0), lamp hangs 0.56 m out toward +Y. Lens = M_LampGlow; marker 'Light' under the shade.
- **`sign_stop`** - Red octagon with a white raised-hand pictogram.
- **`sign_yield`** - Inverted white triangle with a red border.
- **`sign_speed`** - Round speed-limit sign, '40' built from geometry.
- **`sign_oneway`** - Double-sided blade on top of the post; the arrow points toward local +X (Godot +X) on both faces.
- **`sign_parking`** - Blue square with a white geometric 'P'.
- **`sign_street`** - Two crossed street-name blades (one along X, one along Y) with abstract name blocks.
- **`sign_noentry`** - Red disc with a white bar.
- **`barrier_concrete`** - Jersey barrier, 3.0 m long along X, 0.84 m high (cover). Tiles end to end at a 3.0 m pitch.
- **`barrier_plastic`** - Water-filled plastic barrier (orange with white panels), 2.0 m pitch along X.
- **`barrier_fence`** - Crowd-control barrier, 2.2 m wide tube frame with flat feet.
- **`roadblock_police`** - Police A-frame barricade, 2.6 m wide, blue / white banded boards on both sides, two blue beacons (material P_SirenBlue, mildly emissive).
- **`cone`** - Traffic cone, 0.75 m.
- **`delineator`** - Flexible lane delineator post, 1.1 m.
- **`bollard`** - Steel street bollard with a yellow band, 0.96 m.
- **`bollard_light`** - Illuminated path bollard, 0.9 m. Lit section = M_LampGlow; marker 'Light' at its centre.
- **`curb_straight`** - Kerb, 4 stones = 4.0 m along X, 0.30 deep, 0.15 high; chamfered road face toward +Y.
- **`curb_corner`** - Quarter-circle kerb, centre-line radius 1.0 m. ORIGIN = centre of the arc (not the bbox centre); the arc runs from (1,0) to (0,1) in Blender XY = Godot (1,0,0) to (0,0,-1). Road on the outside.
- **`speed_bump`** - Rubber speed bump 3.0 m (X) x 0.42 m x 0.065 m, yellow / black segments.
- **`guardrail`** - W-beam guardrail, 4.0 m along X, posts at x = -1 and +1 (2 m spacing when tiled). Road side = +Y.
- **`jersey_end`** - Sloped terminal for barrier_concrete, 1.5 m. Full profile at x = -0.75 (mates with a barrier end), nose with hazard bands at x = +0.75.
- **`parking_stop`** - Parking-bay wheel stop, 1.8 m x 0.18 m x 0.10 m, yellow bands.
- **`bench`** - Street bench 1.8 m, cast side frames + wooden slats. Sitter faces +Y; seat height 0.44 m.
- **`bench_park`** - Park bench 2.0 m, concrete pedestals + dark timber planks. Sitter faces +Y.
- **`bin`** - Round slatted litter bin with a teal rain hood, 1.1 m.
- **`dumpster`** - Steel dumpster 1.9 x 1.2 x 1.3 m (good cover). Child 'Lid' has its origin on the rear hinge line (rotate about local X to open).
- **`recycling_bins`** - Three wheelie bins in a row (blue / green / yellow lids), one rigid group.
- **`hydrant`** - Fire hydrant 0.8 m; big outlet toward +Y, two side outlets along X.
- **`mailbox`** - Street mailbox, vaulted top, pull-down flap toward +Y, white envelope pictogram.
- **`newspaper_box`** - Coin-operated newspaper box on a pedestal, window toward +Y.
- **`parking_meter`** - Twin-head parking meter, 1.4 m.
- **`bike_rack`** - Five hoops on two floor rails, 2.3 m long (X), hoops 0.9 m high.
- **`bus_stop`** - Bus shelter 3.9 x 1.8 x 2.65 m, open toward +Y (road). Child 'Glass' = rear panes (M_Glass, breakable); lit advert panel (M_ScreenGlow) on the -X end; bench inside; flag sign with a bus pictogram on a pole at the +X front corner.
- **`phone_kiosk`** - Public phone kiosk 0.95 x 0.6 x 2.2 m, open toward +Y. Small lit display (M_ScreenGlow).
- **`vending_machine`** - Drinks vending machine 1.0 x 0.8 x 1.86 m, lit front (M_ScreenGlow) toward +Y.
- **`atm`** - Free-standing cash machine 0.9 x 0.95 x 1.95 m, lit screen (M_ScreenGlow) toward +Y.
- **`planter`** - Concrete street planter 1.1 x 1.1 m with shrubs and flowers, 1.2 m high.
- **`tree_grate`** - Cast-iron tree grate 1.2 x 1.2 m, 3 cm high, open centre (r 0.24 m) for the trunk.
- **`manhole`** - Manhole cover with a concrete collar, diameter 0.88 m, 3.6 cm high.
- **`drain`** - Storm-drain grate 0.72 x 0.46 m, 3 cm high; bars run along Y.
- **`utility_box`** - Street utility cabinet 1.2 x 0.55 x 1.45 m on a concrete plinth; doors toward +Y.
- **`transformer`** - Pad-mounted transformer 1.9 x 1.5 x 1.75 m with cooling fins and three bushings.
- **`power_pole`** - Wooden power pole 9.7 m with crossarm (2.5 m along X), pole transformer and climbing pegs. Markers Wire_1..Wire_4 sit on the insulator tops (string wires between poles).
- **`ac_unit`** - AC condenser 1.05 x 0.5 x 0.72 m on two rails; fan grille toward +Y. For rooftops / alleys.
- **`satellite_dish`** - Rooftop satellite dish (diameter 1.25 m) on a mast, aimed +Y and 35 degrees up.
- **`water_tank`** - Rooftop timber water tank on a steel frame, 2.5 m wide, 4.25 m high, ladder on the +Y side.
- **`vent_pipe`** - Rooftop vent cluster: capped flue (1.45 m), gooseneck pipe and a low turbine vent.
- **`fire_escape_ladder`** - 4.0 m ladder section, 0.48 m wide, rungs every 0.30 m; stackable. Origin = bottom centre of the ladder plane; climb side is +Y, the wall is at y = -0.20 (Godot z = +0.20). Markers 'Ladder_Bottom' / 'Ladder_Top' on the climb side.
- **`fence_chainlink`** - Chain-link fence, 4.0 m x 2.05 m, posts at x = -2, 0, +2. The mesh is real geometry (lattice).
- **`fence_wood`** - Timber plank fence, 4.0 m x 1.85 m; planks on the +Y face, rails and posts behind.
- **`fence_metal`** - Steel bar railing, 4.0 m x 1.15 m, posts with ball finials at x = -2, 0, +2.
- **`wall_low`** - Low concrete wall, 4.0 m x 0.38 m x 1.0 m (cover height), four 1 m panels with cap stones.
- **`hedge`** - Clipped hedge, 4.0 m x 0.9 m x 1.2 m, faceted; flat ends so segments tile.
- **`gate_chainlink`** - Double chain-link gate for a 4.0 m opening. 'Mesh' = the two hinge posts (x = -2 / +2); leaves 'Gate_L' (-X side) and 'Gate_R' (+X side) are separate children with their origin on the hinge axis: rotate them about local Z (Godot Y) to open.
- **`crate_wood`** - Wooden shipping crate, 0.9 m cube.
- **`crate_stack`** - Stack of four crates (one rigid group), about 1.9 x 1.6 x 1.6 m.
- **`pallet`** - Timber pallet 1.2 x 1.0 x 0.15 m.
- **`barrel`** - Steel drum (200 l), 0.58 x 0.89 m, blue.
- **`barrel_explosive`** - Explosive fuel drum: red, yellow hazard band, flame diamonds front and back. The game makes it damageable / explosive.
- **`gas_canister`** - Propane cylinder 0.33 x 0.62 m, orange; meant as an explosive physics prop.
- **`tire_stack`** - Four stacked tyres plus one leaning against the stack, 0.85 m high.
- **`trash_bags`** - Pile of three tied rubbish bags (one rigid group), about 1.2 x 1.0 x 0.75 m.
- **`cardboard_boxes`** - Pile of cardboard cartons, one of them open (one rigid group), about 1.25 x 1.0 x 0.75 m.
- **`shopping_cart`** - Wire shopping trolley 0.6 x 1.0 x 1.03 m; push handle at -Y, nose toward +Y.
- **`neon_sign_a`** - Neon arrow pointing down, 1.35 x 1.75 m. Wall-mounted: origin = centre of the back face.
- **`neon_sign_b`** - Round neon star sign, diameter 1.7 m. Wall-mounted: origin = centre of the back face.
- **`neon_sign_c`** - Neon 'sun over waves' panel, 2.1 x 1.0 m. Wall-mounted: origin = centre of the back face.
- **`billboard`** - Roadside billboard: face 7.0 x 3.2 m (bottom edge 4.3 m up) on two steel posts, total 7.6 m high, catwalk, four up-lights (M_LampGlow), ladder. Face = material M_Billboard_A with 0-1 UVs; original 'sun over the bay' artwork in geometry in front of it. Front = +Y.
- **`billboard_roof`** - Rooftop billboard: face 6.0 x 2.4 m on a raked steel frame (footprint 6.2 x 2.2 m, 3.5 m high), three down-lights (M_LampGlow) and a cyan neon strip. Face = material M_Billboard_B with 0-1 UVs. Front = +Y; put the origin on the roof surface near the parapet.

## 5. Decisions taken (physics hints not fixed by the brief)

- `delineator`, `barrier_fence`, `roadblock_police`, `pallet`, `gas_canister`, `tire_stack`, `cardboard_boxes`
  are `dynamic`: they are light objects a car should push away, not rigid obstacles.
- `traffic_light` (mast arm) is `static`, `traffic_light_ped` and both street lamps are `breakable`;
  `wall_lamp`, `bollard`, `bollard_light`, `dumpster` stay `static`.
- `newspaper_box` and `gate_chainlink` are `breakable` like the mailbox and the fences.
- `crate_stack`, `recycling_bins`, `trash_bags`, `cardboard_boxes` are ONE rigid group each (one mesh).
- The speed-limit sign shows "40" and the parking sign a "P": both are built from boxes (geometry, no
  texture, no font). All other faces are pictograms. Everything reads correctly from the front.
- `sign_oneway` is double-sided; its arrow points toward local +X on both faces.

## 6. Rebuilding

Inside the master .blend, through the Blender MCP `execute_blender_code` tool:

```python
import sys, importlib
P = r"G:\YouTube\Fable 5.2 Effort Test GTA\Ultracode\tools\blender"
for q in (P, P + r"\assets"):
    if q not in sys.path: sys.path.append(q)
import gta_bl as G; importlib.reload(G); G.assert_master()
import props_street as S; importlib.reload(S)      # also reloads the family modules
S.build_all()              # or S.build("bench")
S.preview("bench")         # qa/blender_previews/prop_bench.png
S.preview_family("signs")  # qa/blender_previews/props_family_signs.png
S.export_all()             # validate + GLB + node-name patch, or S.export("bench")
S.write_manifest(); G.save()
```

Two implementation details worth knowing:

- Blender object names are unique per file, so the children are called `<prop>.Mesh`, `<prop>.Lamp_Red` ...
  in the .blend. `S.export()` rewrites the node names inside the GLB JSON chunk to the bare contract names
  (`Mesh`, `Lamp_Red`, `Light`, `Lid` ...). Exporting with plain `G.export_glb()` would give `bench.Mesh`.
- `gta_bl.join()` reads `matrix_world` of freshly created objects before the view layer is evaluated, which
  bakes the slot offset into the vertices. `Asset.finish()` therefore calls `view_layer.update()` first, and
  `S.export()` refuses to export a prop whose geometry is more than 12 m away from its root.

## 7. Verification

```powershell
tools\godot.ps1 -Mode script -Script res://gta/code/editor/props_street_verify.gd -Tail 100
tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/props_street_showcase.tscn -Frames 300
```

The first checks every GLB against the manifest (loads, node names, materials present, emissives, triangle
count, bounding box); the second saves one in-engine screenshot per category plus a dusk shot of everything
that glows.
