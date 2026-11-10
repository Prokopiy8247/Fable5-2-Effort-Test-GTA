# SPEC — Modular building kits, roof props, feature fronts, signs, billboards

Read `tools/blender/SPEC_COMMON.md` first. Manifest: `gta/resources/data/manifests/buildings.json`.
Category for `K.begin_asset`: `"Buildings"`. Export path: `buildings/<id>` (signs: `buildings/signs/<id>`).
Suggested module files: `tools/blender/bld_facades.py`, `bld_house.py`, `bld_roof.py`, `bld_fronts_signs.py`.

Godot assembles every ordinary building at runtime by tiling these modules along the 4 facades of a box footprint
and merging them into one mesh. So the tiling contract below matters more than anything else.

## Facade module contract

- A module occupies **X ∈ [−W/2, +W/2], Z ∈ [0, H]**; the exterior wall plane is **Y = 0**, outside is +Y.
- The wall surface must reach exactly x = ±W/2 and z = 0 / H at Y = 0 with straight edges so neighbours tile with
  no gaps. No faces on the building-interior side (Y < 0) and no caps at x = ±W/2, z = 0, z = H (hidden by neighbours).
  Geometry stays within Y ∈ [−0.3, +0.35] unless the description says it protrudes further.
- Wall surfaces: `tint_a` (per-building colour). Accent surfaces: `tint_b`. Frames: `charcoal`/`steel_dark`/`white`.
  Sills/caps: `concrete_light`. Plinths: `concrete_dark`.
- Glass: `@Window` **flat quads**, recessed to Y = −0.12 with reveal faces around the recess. Build each pane with
  `mb.quad((+x,y,z0), (−x,y,z0), (−x,y,z1), (+x,y,z1), "@Window")` (bottom-left → bottom-right → top-right → top-left
  as seen from outside) so the UVs run 0..1 across the pane.
- Ground-floor glass must start at z ≥ 0.45; upper-floor panes stay inside their own module (not touching z=0/H).
- Each module asset has TWO mesh parts:
  - `mesh` — full detail (≤ 350 tris);
  - `lod1` — far version, ≤ 12 tris: flat `tint_a` wall quads at Y = 0 arranged AROUND flat `@Window` quads at Y = 0
    (no overlapping coplanar faces), same silhouette (parapets/caps as a simple box).
- Verify tiling: build a temporary asset `zz_tile_<kit>` from `K.link_copy` duplicates (e.g. 4 wide × 3 floors + ground
  + parapet), `look` at it, then delete it with `K.remove_asset("zz_tile_<kit>")`. Do the same for one small house.

## P1 — Office kit (W = 4.0; upper floors H = 3.5; ground floor H = 4.5)

| id | description |
|---|---|
| `off_win_a` | Curtain wall: glass z 0.55–3.2 over x ±1.85 split in 3 panes by two 0.08 mullions (`steel_dark`); `tint_a` spandrels below/above; thin `tint_b` line at the floor edge. |
| `off_win_b` | Punched window: `tint_a` wall, one opening 2.4 × 1.9 (z 0.9–2.8), `charcoal` frame, projecting sill. |
| `off_win_c` | Ribbon window: glass band z 1.0–2.7 across the FULL width (x ±2.0 so neighbours form a continuous ribbon), `tint_b` spandrel bands with a small ledge above and below. |
| `off_solid` | Blank `tint_a` panel with shallow panel joints/grooves. |
| `off_ground_glass` | H 4.5. Plinth 0–0.5, lobby glazing 0.5–3.6 with slim frames, `tint_b` header band 3.6–4.5 with a 0.3 canopy lip. |
| `off_ground_door` | H 4.5. Double glass doors 2.0 × 2.5 with steel frame + handles, side lights, canopy slab 1.2 deep at z 3.0 (`steel_dark`) with two `emis_lamp` downlights. |
| `off_ground_solid` | H 4.5. Solid wall, plinth, wall lamp (`emis_lamp`) or vent grille. |
| `off_parapet` | H 1.0. Roof parapet: full box Y −0.25…0 (it is seen from the roof side too) with `concrete_light` cap overhanging 0.05. |

## P1 — Apartment kit (W = 4.0; upper H = 3.2; ground H = 4.0)

| id | description |
|---|---|
| `apt_win_a` | `tint_a` wall; window 1.6 × 1.5 (z 0.95–2.45), white frame + cross bar, sill, `tint_b` shutters. |
| `apt_win_b` | Two narrow windows 0.8 × 1.6 with frames; flower box (`flower_red`, `@F:leaf_green`) under one. |
| `apt_balcony` | Glass balcony door 1.4 × 2.2; slab 3.2 × 1.1 deep, 0.15 thick (protrudes to Y +1.1); railing 1.0 high (steel bars + `tint_b` panel); small plant or AC unit. |
| `apt_solid` | Plain wall with a downpipe (`steel_dark`). |
| `apt_ground_door` | H 4.0. Entrance door 1.2 × 2.2 (`wood_dark`), 2 steps (protrude 0.6), small pitched canopy (`tint_b`), intercom, `emis_lamp` wall lamp. |
| `apt_ground_win` | H 4.0. Window with security grille; plinth band 0–0.6. |
| `apt_parapet` | H 0.8. Stepped cornice (full box like `off_parapet`). |

## P1 — Storefront kit (W = 4.0; H = 4.5; ground floors of mixed-use buildings)

| id | description |
|---|---|
| `shop_glass` | Plinth 0–0.45 (`tile_dark`), display window 0.45–3.0, sign fascia band z 3.2–4.2 in `tint_b` (blank: sign assets mount on it), top trim. |
| `shop_door` | Recessed entrance: glass door 1.0 × 2.3 + side light + transom, same fascia band. |
| `shop_solid` | Closed bay: ribbed roller shutter (`steel`), same fascia band. |
| `shop_awning` | Attachment, W 4.0, depth 1.2: sloped fabric awning striped `tint_b`/white with valance. Origin on the wall plane at the awning's top-back edge (z = 0 there, awning hangs down/out). Single part `mesh`. |

## P1 — Industrial kit (W = 4.0; H = 4.0)

| id | description |
|---|---|
| `ind_wall` | Corrugated metal sheet (8–10 vertical trapezoid ribs) in `tint_a_metal`; concrete base 0–0.5. |
| `ind_wall_win` | Same + high strip window z 2.6–3.5 (4 panes, steel frames). |
| `ind_door_roll` | Roll-up door 3.4 × 3.6 (horizontal `steel` slats), `tint_b` frame, yellow/black hazard posts. |
| `ind_door_man` | Corrugated panel + steel personnel door 1.0 × 2.1, bulkhead lamp (`emis_lamp`), small plate. |
| `ind_parapet` | H 0.6. Metal roof-edge flashing (full box). |
| `ind_dock` | PROP (single part `mesh`, no lod1): loading dock 4.0 × 2.5 deep × 1.2 high with rubber bumpers and steps; origin on the wall plane at ground. |

## P1 — House kit (W = 3.0; H = 3.0)

| id | description |
|---|---|
| `house_wall` | Horizontal lap siding (5–6 boards, slight stepped offsets), `tint_a`. |
| `house_wall_win` | Siding + sash window 1.2 × 1.4, white frame, sill, `tint_b` shutters. |
| `house_wall_door` | Siding + front door 0.95 × 2.1 (`tint_b`, small window, handle), one step, porch lamp (`emis_lamp`). |
| `house_wall_garage` | **W 6.0.** Siding + sectional garage door 4.8 × 2.3 (white panels). |
| `house_roof_9` | Roof slice: 3.0 long along X, spans Y −4.5…+4.5 plus 0.45 eaves; ridge along X, 2.4 above the eave line; z = 0 at the wall top. 0.15 thick, shingles `tint_b`, white fascia, underside closed, end caps included. Parts `mesh`, `lod1`. |
| `house_roof_6` | Same for a 6.0 deep house (Y ±3.0), ridge 1.6 high. |
| `house_gable_9` / `house_gable_6` | Triangular gable-end infill (siding `tint_a`, small vent), X ∈ ±4.5 (±3.0), Z from 0 to ridge height, face at Y = 0, 0.2 thick. |
| `house_porch` | W 3.0, depth 2.0 (toward +Y): deck 0.3 high, 2 steps, 2 posts, railing, small shed roof (`tint_b`). Origin on the wall plane. |
| `house_chimney` | Brick chimney 0.7 × 0.7 × 2.2 with cap; origin base centre. |

## P2 — Roof props (single part `mesh`; origin base centre; category `Buildings`, path `buildings/roof/<id>`)

`roof_ac` (condenser 1.6 × 1.0 × 1.1, fan grille), `roof_vent` (mushroom vent ⌀0.5), `roof_duct` (L-shaped duct ~3 m),
`roof_tank` (water tank on legs ⌀2.4 × 3.2), `roof_antenna` (6 m mast, dishes, `led_red` tip),
`roof_stairhut` (access hut 3 × 3 × 2.6, door, lamp), `roof_skylight` (2 × 2 glass pyramid, `@Window`),
`roof_helipad` (12 × 12 pad 0.1 thick: `asphalt_dark`, white ring + "H" from thin boxes raised 5 mm, yellow edge
line, four `led_green` corner lights).

## P2 — Feature fronts (W = 12.0 = 3 modules, H = 4.5; same plane rules; parts `mesh` + `lod1` ≤ 40 tris; ≤ 1500 tris)

| id | description |
|---|---|
| `front_police` | `concrete_light` portico: 4 square columns, wide steps (protrude 1.0), glass doors, `led_blue` lamps on the outer columns, 3D text "VBPD" (large, `neon_blue`) + "VESPER BAY POLICE" (small, white). |
| `front_hospital` | Glass entrance, canopy protruding 2.5 on 2 posts, text "VESPER GENERAL" + "EMERGENCY" (`neon_red`), white block with a green "H". No red cross. |
| `front_hotel` | Canopy with rows of `emis_lamp` bulbs, `gold` trim, text "TIDELINE HOTEL" (`neon_pink`). |
| `front_firestation` | Two `fire_red` sectional bay doors 4.5 × 3.8 with a window row, central pier with door, text "VBFD ENGINE 7". |
| `front_cinema` (P3) | Marquee wedge protruding 2.5 with `emis_lamp` bulb rows, text "ASTRA", poster frames (`screen_blue`). |

## P2 — Neon signs (path `buildings/signs/<id>`; single part `mesh`; origin = bottom centre on the wall plane; ≤ 3.6 wide × 0.9 high × 0.25 deep; dark backing board + 3D text in ONE neon colour + optional simple pictogram from tubes/boxes)

`sign_cafe`, `sign_bar`, `sign_pizza`, `sign_pawn`, `sign_24h`, `sign_market`, `sign_tattoo`, `sign_arcade`,
`sign_diner`, `sign_gym`, `sign_books`, `sign_noodles`, `sign_club`, `sign_laundry`, `sign_bank`, `sign_taxi`.
Vary the neon colours (pink, cyan, orange, yellow, green, purple, red, blue) and board shapes.
Projecting blade signs (origin at the wall mount, sign extends toward +Y, text readable from ±X is NOT required —
put the text on both faces with `rot`): `sign_blade_hotel` (1.0 × 5.0 tall, "HOTEL"), `sign_blade_motel`, `sign_open`
(small 0.9 × 0.4 "OPEN").

## P3 — Billboards (path `buildings/<id>`; single part `mesh`; origin ground centre)

`billboard_a`, `billboard_b`, `billboard_c`: panel 10 × 4.5 with its bottom at z 9 on 1–2 steel posts, catwalk,
3 lamps (`emis_lamp`) aimed at the panel. Artwork = bold abstract shapes + 3D text for FICTIONAL ads, e.g.
"ZAP! SODA", "ORBIT GUM", "SUNSET RADIO 99.1", "FLY VESPER AIR". Panel faces +Y (back face plain `steel_dark`).
`roof_billboard_a`, `roof_billboard_b`: rooftop versions 8 × 4 on a low steel truss (origin base centre).

Work in the P1 → P2 → P3 order. Export and update the manifest after every kit so Godot work can start early.
