# SPEC — Landmarks, enterable shops, safehouse, airfield / port / transit structures

Read `tools/blender/SPEC_COMMON.md` first. Manifest: `gta/resources/data/manifests/landmarks.json`.
Suggested modules: `tools/blender/lm_shops.py`, `lm_airfield.py`, `lm_towers.py`, `lm_misc.py`, `lm_transit.py`.
Category `"Landmarks"` (interiors are part of the same asset). Export path `landmarks/<id>`.

Unlike the modular facade kits (another agent), these are complete one-off structures placed whole by Godot.

## Common contract

- Origin at ground centre of the footprint, entrance / front toward **+Y**.
- Parts: `shell` (structure + exterior detail + signage), `fixtures` (interior furniture/fixtures, enterable
  buildings only), moving parts as listed, and **`col`** — a simplified collision mesh made ONLY of boxes / simple
  convex solids (walls, floor slab, roof, stairs as sloped boxes, big fixtures like counters and shelves). Door and
  bay openings must stay open in `col`. Godot turns `col` into a triangle-mesh collider and hides it.
- Enterable buildings: exterior walls 0.25 thick, interior floor top at z = 0.02 (no step at the door), ceiling at
  3.2 unless stated, flat roof with parapet. Interior surfaces use `"@D:<palette>"` colours (never rain-wet).
  Storefront/large windows use `@Glass` so the interior is visible from the street. Entrance door opening 1.6 wide ×
  2.4 high with two sliding glass leaves as separate parts `door_l`, `door_r` (closed pose; each slides 0.8 along X).
  Ceiling lamps: small `emis_warm_always` fixtures + markers `light_1` … `light_n` (2–4) just below them.
  Exterior 3D sign text with `K.add_text` (readable from +Y) in the stated neon colour.
- Markers (enterable shops): `entrance` (outside, 1.5 m in front of the door, on the ground), `counter` (where the
  customer stands, on the floor, +Y of the marker facing the counter), `staff` (shopkeeper standing point behind the
  counter, facing the customer), `spawn` (free floor spot inside).
- Budget: ≤ 6000 tris per landmark including fixtures (parking garage / radio tower may reach 8000).
- QA: exterior three-quarter, front, top; then interior views with `distance` small, or hide nothing and use
  `shading: "xray"`. Check that a 1.8 m person fits through doors and aisles (≥ 1.2 m clear), counters ≈ 1.05 high.

## P1 — Enterable shops and the safehouse

| id | footprint (X × Y) | description |
|---|---|---|
| `shop_guns` | 12 × 10 | **"BULWARK ARMS"** (`neon_orange`). Dark industrial palette (charcoal, steel, wood, orange accent). L-shaped glass display counter, wall racks with generic long-gun silhouettes (boxes + cylinders), ammo shelves, armour mannequin torso, closed back door with small sign "RANGE", a gunsmith workbench in a corner. Extra marker `workbench`. |
| `shop_clothes` | 12 × 10 | **"THREADLINE"** (`neon_cyan`). Bright palette. Racks with hanging garments (thin coloured boxes), shelves with folded stacks, two abstract torso mannequins on stands, counter + register, fitting booth with curtain, shoe wall. Extra marker `wardrobe` (in front of the fitting booth). |
| `shop_barber` | 8 × 8 | **"FADE FACTORY"** (`neon_red`). Two barber chairs facing wall mirrors (`mirror`), counter, waiting bench, checker floor (`tile_white`/`tile_dark` quads). Outside: barber pole as part `pole` (striped cylinder, origin on its axis, spins about Z). Extra marker `chair` (seat point of the first chair). |
| `shop_market` | 12 × 10 | **"QUIKNOOK 24"** (`neon_green`). Three shelf aisles with colourful box products, fridge wall with lit interior (`emis_cool_always`), counter with register + snack display, ATM. Extra marker `register`. |
| `shop_garage` | 16 × 14, wall height 6 | **"TORQUE HOUSE"** + smaller "CUSTOMS" (`neon_yellow`, `neon_pink`). Mod/repair garage: one vehicle bay opening 5.0 wide × 4.0 high in the +Y wall with a roll-up door as part `door` (origin at its TOP edge; Godot slides it up), single bay with hazard-striped floor outline, 2-post lift (posts only, arms flat on the floor), red tool chests, workbench, tyre rack, paint-booth light bars (`emis_cool_always`), small glazed office corner. No sliding glass doors. Markers: `bay` (vehicle centre on the floor, marker +Y pointing toward the back wall, i.e. rot (0,0,180)), `entrance` (8 m in front of the bay door), `counter`, `staff` (mechanic), `light_1..4`. |
| `safehouse` | house 12 × 9 + garage 6 × 7 attached on the −X side | **The Hideout**: beach bungalow, `tint_a` walls, low hip/flat roof with overhang (`tint_b`), small porch with steps, front door leaf as part `door` (hinged, origin on the hinge), `@Glass` windows. Interior: sofa + TV (`screen_blue`) + rug, kitchenette, bed, wardrobe, desk with laptop, floor lamp. Garage with roll door as part `garage_door` (origin top edge) and an empty bay with a wall shelf. Markers: `entrance`, `spawn`, `bed`, `wardrobe`, `save` (at the desk), `garage_spot` (vehicle centre inside the garage, +Y = nose pointing out of the door), `garage_out` (driveway spot 7 m in front of the garage door), `light_1..3`. |

## P1 — Fuel, airfield

| id | size | description |
|---|---|---|
| `lm_gas_station` | canopy 14 × 9, top 5.5 | **"GULL GAS"**: canopy on 4 columns with `neon_green`/white fascia stripe and text on the +Y and −Y fascias, underside lights (`emis_lamp`) + markers `light_1..4`; two pump islands (each: 2 pumps with hose, `screen_blue` display, bollards, bin); 7 m price pylon at the +X/+Y corner. Markers `pump_1..4` (at each pump, on the ground). `col`: columns, islands, pumps, pylon. |
| `lm_hangar` | 26 (X) × 32 (Y) × 10 | Arched corrugated hangar (`tint_a_metal`), +Y end fully open (door tracks, two big door leaves parked at the sides), back wall with a row of windows, concrete floor with yellow guide line, shelving/crates/tool carts along the walls (`fixtures`), ceiling lights + markers `light_1..4`. Marker `spot` (aircraft parking point at the centre, +Y out). `col`: vault as 8–10 flat segments per side, back wall, floor. |
| `lm_control_tower` | 8 × 8 × 24 | Concrete shaft with door + exterior ladder detail, flared cab with slanted `@Glass` all round, roof antennas, `led_red` obstruction light, rotating beacon as part `beacon` (origin on its axis). `col` boxes. |
| `lm_terminal` | 18 × 10 × 5 | Small airfield terminal (not enterable): glazed front (`@Window`), canopy, text "VESPER AIRFIELD" (`neon_cyan`), benches, luggage cart. `col` box set. |

## P2 — Towers and skyline pieces

| id | size | description |
|---|---|---|
| `lm_radio_tower` | base 5 × 5, h 42 | Red/white banded steel lattice (tubes), platforms with railings at 14, 28 and 40 m, a ladder up the +Y face, antennas, `led_red` beacons. Markers `ladder_bottom` (ground, 0.5 m in front of the ladder), `ladder_top` (on the 40 m platform), `jump` (edge of the top platform). `col`: platform boxes + 4 leg boxes. |
| `lm_water_tower` | h 20 | Tank on four braced legs, text "VESPER BAY", ladder, `rust` streak accents. `col`: legs + tank cylinder (octagonal). |
| `lm_lighthouse` | base ⌀6, h 22 | White tower with `red` bands, gallery + railing, `@Glass` lantern room, rotating beacon core as part `lamp` (origin on the axis; `emis_always_white` lens blocks) + marker `light`, rock base, door. `col`: octagonal prism + base. |
| `lm_crane` | h 30, boom 40 | Port gantry crane on four legs (rail gauge 22), boom reaching −Y over the water, trolley + hanging spreader, machinery house, `tint_a_metal` structure, stairs detail. `col`: leg boxes only. |
| `lm_parking_garage` | 32 × 24, decks at z 0 / 3.2 / 6.4 | Drivable 3-level parking structure: columns on a grid, perimeter barrier walls 1.1 high with horizontal slots, straight ramps 4.5 wide (rise 3.2 over ≥ 13 m) linking the levels, bay lines (thin `line_white` boxes 5 mm above the deck), entrance 6 m wide on +Y with a small booth, stair core with text "PARKING" (`neon_blue`). Clear height ≥ 2.6, lanes ≥ 6 m. `col`: slabs, sloped ramp boxes, barrier walls, columns. Markers `entrance`, `top` (centre of the top deck). |
| `lm_fountain` | ⌀8 | Plaza fountain: stepped basin, tiered centre piece, water as `ice_blue` discs. `col` basin ring. |
| `lm_statue` | 3 × 3 × 6 | ABSTRACT sculpture (twisted stacked prisms in `bronze` on a `granite` plinth). |
| `lm_viewpoint` | 9 × 6 | Hilltop viewing deck: timber platform with railings, two coin binoculars, bench, info board. `col` deck + rails. |
| `lm_gazebo` | ⌀5 | Octagonal park gazebo with steps and roof finial. |
| `lm_boathouse` | 7 × 5 × 4 | Marina shack with text "MARINA" (`neon_cyan`), life rings, fuel pump for boats. Not enterable. |

## P2 — Transit (monorail "BayLine"; the train car itself is built by the vehicles agent)

| id | description |
|---|---|
| `rail_beam_8` | Guideway beam segment, 8.0 long on Y, 0.9 wide, 1.2 deep; **origin at the centre of its TOP face** (z = 0 = running surface). `concrete_light` with a `steel` power rail strip on each side. |
| `rail_pier` | T-pier column: origin at ground; shaft to z 5.8 with flared head 2.2 wide (supports the beam underside at 5.8, so the beam top is at 7.0). |
| `rail_station` | Elevated station, 24 long (Y) × 7 wide: platform floor at **z 7.55** on the +X side of the track (x 1.45 … 6.6), tactile edge strip, canopy roof on posts, benches, ticket machine, sign "BAYLINE" (`neon_cyan`), a stair run 1.8 wide along Y with a mid landing from the ground (at +X, +Y corner) up to the platform, railings. Track beam passes at x = 0 (do not model the beam). `col`: platform, stair as sloped boxes, roof posts. Markers `entrance` (foot of the stairs), `board` (platform edge at the train door, x ≈ 1.6, y = 0, z 7.55), `wait` (platform centre). |

## P3 — Pier fun

| id | description |
|---|---|
| `lm_ferris_wheel` | Wheel ⌀22 on an A-frame base (axle at z 13). Parts: `base` (supports, boarding platform, booth), `wheel` (rim rings, spokes, hub; the wheel faces +Y: wheel plane = XZ, axle along Y, origin at the axle, spins about its local Y), `gondola_01` … `gondola_12` (origin at each hanging pivot so Godot keeps them upright). `neon_pink`/`neon_cyan` strips on the spokes. `col`: base only. |
| `lm_basketball` | Half court 15 × 14 slab with lines + one hoop on a post. |

Order: shop_garage → shop_guns → safehouse → shop_clothes → shop_market → shop_barber → gas station → hangar →
control tower → terminal → P2 → P3. Export + update the manifest after every asset.
In the manifest include each marker with its position and rotation.
