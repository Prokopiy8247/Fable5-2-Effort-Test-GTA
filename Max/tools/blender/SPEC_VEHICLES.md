# SPEC — Vehicles (cars, two-wheelers, boats, helicopters, airplanes, train) and mod parts

Read `tools/blender/SPEC_COMMON.md` first. Manifest: `gta/resources/data/manifests/vehicles.json`.
Vehicles are THE headline feature of the game: silhouettes must be distinct and convincing, never the same mesh rescaled.
Suggested modules: `tools/blender/veh_cars.py` (generator + data), `veh_bikes.py`, `veh_boats.py`, `veh_air.py`,
`veh_parts.py`, `veh_train.py`.

Common: front = +Y, left = −X, wheels touch z = 0 (boats: z = 0 is the waterline; train: z = 0 is the beam top).
Origin at the centre of the footprint. Export `vehicles/<id>` (parts: `vehicles/parts/<id>`).

## Contract for every wheeled vehicle (exact part / marker names)

Parts (objects `<id>__<part>`):
- `body` — shell, fixed details, fixed glass, interior. Materials: `@Paint1` main paint, `@Paint2` secondary
  (roof/stripe/doors where sensible), `@Glass` windows, palette colours (`plastic_black`, `chrome`, `rubber`,
  `fabric_dark`, `leather_black`...), lamp lenses: `@LightHead`, `@LightTail`, `@LightReverse`, `@LightIndL`
  (left indicators front+rear), `@LightIndR`, emergency: `@LightSirenA` (red), `@LightSirenB` (blue), `@LightAux`.
- `door_fl`, `door_fr` (and `door_rl`, `door_rr` for 4-door cars) — separate meshes, **origin on the hinge line**
  (front vertical edge of the door, at mid height). Closed pose = rest. Include the door's window glass, inner
  trim panel and handle. Opening is a rotation about the object's local Z.
- `wheel_fl`, `wheel_fr`, `wheel_rl`, `wheel_rr` — origin at the wheel centre, axle along X. Build ONE wheel mesh
  (tyre + rim + hub, outer face toward −X) and use `K.link_copy` for the others (right side rotated 180° about Z).
- `steering` — steering wheel, origin at its hub; the object is tilted so that **its local Y axis is the steering
  column axis** (the wheel spins about local Y).
- `lod1` — ONE simplified mesh of the whole vehicle (body silhouette, `@Paint1`, windows as opaque `glass_dark`,
  wheels as 8-sided cylinders, lamps as plain `emis_always_*`-free coloured faces) ≤ 350 tris.
- `col_body`, `col_cabin` — simple convex collision hulls (≤ 24 vertices each): lower body (bottom raised to
  ground clearance + 0.1) and greenhouse. Any palette colour.
Markers:
- `seat_driver`, `seat_passenger` (+ `seat_rl`, `seat_rr` when a rear bench exists): hip point of the seated
  character (≈ 0.25 above the seat cushion), identity rotation (forward +Y). Driver sits on the LEFT (−X).
- `light_head_l`, `light_head_r` (centre of each headlamp, on the lens), `light_tail_l`, `light_tail_r`.
- `exhaust` (tip of the tail pipe), `engine` (centre of the engine bay, top), `siren` (centre of the roof light bar,
  emergency vehicles only), `mod_spoiler` (rear edge of the boot lid / roof end, centre, on the surface),
  `mod_hood` (centre of the bonnet, on the surface), `mod_roof` (centre of the roof, on the surface),
  `mod_front` (front bumper centre at its lower edge), `mod_rear` (rear bumper centre at its lower edge),
  `mod_skirt_l`, `mod_skirt_r` (sill centre on each side, bottom outer edge).

## Recommended construction method for car bodies (it gives clean chamfered low-poly cars with real cabins)

Write ONE parametric generator `build_car(spec)` and drive every car from a data dict, e.g.
`dict(id, L, W, H, wheel_r, wheel_w, axle_f_y, axle_r_y, track, clearance, upper=[(y,z,tag)...], belt_z, roof=...,
doors=[...], ...)`.

1. **Lower body = side profile extruded across the width.** Define the upper outline as (y, z) points from the front
   bottom, up the nose, along the bonnet to the windscreen base (cowl), along the flat beltline to the rear deck,
   boot lid, tail, down to the rear bottom. The generator adds the underside (z = clearance) with two semicircular
   wheel-arch notches (radius = wheel_r + 0.07, 8 segments) centred on the axles. Extrude with `mb.prism(..., plane="YZ")`
   using `side_colors` per outline segment (bonnet/boot/nose/tail → `@Paint1`, underside + arches → `plastic_black`).
   Skip the top face over the cabin (the cabin must be open so seats and occupants are visible through the glass):
   keep only ~0.12 wide shoulder ledges at the sides.
2. **Door openings**: the side polygon gets a rectangular notch from the beltline down to the sill between the
   door's front and rear Y (both doors of a 4-door car share one notch). The doors are separate slabs that fill the
   notch exactly (≈ 5 cm thick, outer face flush with the body side, 1 cm seam gaps), plus inner trim, handle and
   the side window pane with a thin frame above the belt.
3. **Chamfer** the perimeter edge loops between the side polygons and the top surfaces (bonnet edges, shoulders, boot,
   nose/tail corners) with `mb.bevel_edges(edges, 0.04–0.07, segments=1)` — this is what makes the car read as a
   chunky stylised model instead of a box. Apply the same chamfer to the door tops so they line up.
4. **Plan taper**: bisect the mesh at 2 planes (≈ 0.5 m from the nose, 0.4 m from the tail; `bmesh.ops.bisect_plane`)
   and scale X of the vertices beyond them linearly down to ≈ 0.86–0.92 at the ends, so the car is not a brick from
   above. Apply the identical function to bumpers/lamps/doors if they are affected.
5. **Greenhouse from bars and panes**: roof slab (thin tapered/bevelled box, `@Paint1` or `@Paint2`, with a headliner
   underside), A/B/C pillars as slim slanted boxes between the belt corner points and roof corner points (roof is
   0.10–0.18 narrower per side than the belt = tumblehome), and `@Glass` quads for windscreen, rear window and fixed
   quarter windows. Front side windows belong to the doors.
6. **Interior tub**: floor at sill height, firewall, rear wall, inner side walls where there is no door, dashboard
   block, centre console, 2 front seats (base + back + headrest) and a rear bench where it fits. Dark palette colours.
7. **Details that sell it**: bumpers (bevelled boxes, `plastic_black`, body colour or `chrome` depending on class),
   grille (dark inset with bars), headlamp + tail-lamp lens blocks at the corners wrapping slightly around,
   indicator lenses, reverse lamps, number plates (white plates, no text needed), mirrors on stalks, door handles,
   wiper stubs, rocker strip, exhaust tip(s), fuel flap line, antenna. Wheels: tyre with chamfered shoulders
   (12–14 sides), rim disc recessed with 5 chunky spokes or a steel dish, centre cap.
8. `lod1` and `col_*` can come from the same generator with a `lod=True` flag (plain prism, no notches/interior).

Look at every car from front-3/4, rear-3/4, side and top (`views: ["three_quarter", [-0.6,-1,0.35], "right", "top"]`),
check the stance (wheels fill the arches, no floating/clipping), then also `look` with `shading: "xray"` or a view
through the side glass to confirm the cabin is visible and doors/steering/seats are where they should be.
Finally open one door by rotating it ±60° to verify the hinge pivot, then reset it to 0.

## P1 — Cars (id, name, L × W × H, wheel radius, notes)

| id | name | L × W × H | r | silhouette |
|---|---|---|---|---|
| `car_sedan` | Meridian | 4.70 × 1.86 × 1.46 | 0.33 | Classic 3-box, 4 doors. Do this one FIRST and get it right. |
| `car_compact` | Pico | 3.75 × 1.68 × 1.50 | 0.30 | Short 2-box hatchback, 2 doors, upright tail. |
| `car_sports` | Vanta GT | 4.45 × 1.96 × 1.22 | 0.34 | Low wedge nose, cab set back, fastback, 2 doors, side intakes, lip spoiler, wide stance. |
| `car_muscle` | Brawler | 4.95 × 1.96 × 1.36 | 0.36 | Long flat bonnet with bulge, short deck, 2 doors, `chrome` bumpers, fat rear tyres, twin exhausts. |
| `car_suv` | Ridgeback | 4.85 × 2.02 × 1.86 | 0.42 | Tall 2-box, 4 doors, roof rails, clearance 0.30, chunky arches. |
| `car_pickup` | Mule | 5.40 × 2.02 × 1.86 | 0.42 | 2-door cab + open load bed (bed floor, inner walls, tailgate), clearance 0.32. |
| `car_van` | Hauler | 5.20 × 2.04 × 2.25 | 0.37 | One-box panel van: short sloped nose, cab glass only, tall windowless cargo body (`@Paint1`), 2 cab doors, rear door lines. |
| `car_police` | Interceptor | 4.95 × 1.92 × 1.50 | 0.35 | Big 4-door sedan (own profile, not the Meridian): body `@Paint1`, all four doors `@Paint2` (two-tone livery), push bar, roof light bar (`@LightSirenA` left half, `@LightSirenB` right half), pillar spotlights, small 3D "POLICE" on the front doors (`police_blue`), marker `siren`. |
| `car_taxi` | ZipCab | 4.60 × 1.84 × 1.62 | 0.33 | Tall-roof cab, 4 doors, `@Paint1` body, black/white checker band along the belt (small boxes), roof sign box (`@LightAux`) with 3D "TAXI". |

## P2 — Service vehicles (same contract; 4 wheels each, rear wheels may be wider "duals")

| id | name | L × W × H | r | notes |
|---|---|---|---|---|
| `car_ambulance` | Lifeline | 6.20 × 2.20 × 2.75 | 0.40 | Van cab + box body, `@Paint1` body, `@Paint2` side stripe, light bars front + rear, rear doors, marker `siren`. Blue six-point-free generic "AMBULANCE" text (no red cross / star of life). |
| `car_firetruck` | Blazeguard | 8.60 × 2.50 × 3.20 | 0.50 | Cab-over engine, pump panel with gauges, hose reels, ladder rack on top, light bar, `chrome` bumper, marker `siren`. |
| `car_truck` | Packmaster | 7.40 × 2.40 × 3.30 | 0.48 | Box truck: cab `@Paint1`, cargo box `@Paint2` with roll door at the rear. |
| `car_swat` | Bulwark | 6.40 × 2.40 × 2.70 | 0.50 | Armoured truck: angular plates, small slit windows, ram bumper, running boards, roof hatch, light bar, marker `siren`. |

## P1 — Two-wheelers

`bike_sport` "Wasp" (length 2.05, seat height 0.80, wheel r 0.31): parts `body` (frame, engine block, tank `@Paint1`,
seat, tail, exhaust, rear swing-arm), `fork` (front fork tubes + handlebar + headlamp `@LightHead` + front fender;
origin at the steering head on the steering axis; the object is tilted so its **local Z axis is the steering axis**
(rake ≈ 25°)), `wheel_f`, `wheel_r` (origin centre, axle X), `lod1`, `col_body`. Markers `seat_driver` (hip point),
`seat_passenger`, `light_head_l` (single lamp), `light_tail_l`, `exhaust`, `engine`, `hand_l`, `hand_r` (grip
positions on the bars), `foot_l`, `foot_r` (peg positions).

`bicycle` "BMX" (length 1.70, wheel r 0.28): parts `body` (tube frame `@Paint1`, saddle, chain ring), `fork`
(fork + handlebar, same axis rule), `wheel_f`, `wheel_r`, `crank` (crank arms + pedals, origin at the bottom bracket,
spins about X), `lod1`, `col_body`. Markers `seat_driver`, `hand_l`, `hand_r`, `foot_l`, `foot_r`.

## P1 — Boat

`boat_speed` "Marlin" (7.4 × 2.5, hull depth: keel at z −0.45, gunwale at +0.75, windscreen top +1.6): parts `body`
(V-hull loft `@Paint1` with `@Paint2` stripe/deck trim, non-slip deck `offwhite`, cockpit with 4 seats, console,
`@Glass` wrap windscreen with frame, cleats, bow rail tubes, nav lamps), `steering`, `motor` (twin outboards as one
part, origin at the transom pivot, turns about local Z), `prop` (propeller pair, spins about Y, origin at the
propeller hub line — may be one object), `lod1`, `col_body` (convex hull of the hull). Markers `seat_driver`
(left front), `seat_passenger`, `seat_rl`, `seat_rr`, `wake` (stern centre at the waterline), `engine`,
`light_head_l` (bow light).

P2: `boat_dinghy` (3.4 × 1.6 inflatable with small outboard; same part names, 2 seats).
P3: `boat_police` (8.2 × 2.8 patrol boat with small cabin, light bar `@LightSirenA/B`, `@Paint1`/`@Paint2` livery).

## P1 — Aircraft

`heli_civil` "Dragonfly" (fuselage 9.6 long incl. tail boom, cabin 1.7 wide, total height 3.1, main rotor ⌀9.4,
skids): parts `body` (egg cabin with large `@Glass` bubble + frames, `@Paint1` with `@Paint2` stripe, engine cowl,
tail boom, fins, skids on struts, 4 seats + instrument console inside), `rotor_main` (hub + 3 blades, origin at the
mast top, spins about Z), `rotor_tail` (2 blades, origin at the tail hub, spins about X), `door_fl`, `door_fr`
(hinged at the front, same rule as cars), `lod1`, `col_body`, `col_tail`. Markers `seat_driver` (front left),
`seat_passenger`, `seat_rl`, `seat_rr`, `engine`, `light_head_l` (nose landing light), `light_tail_l` (tail beacon).
z = 0 at the bottom of the skids.

`heli_police` "Skywatch" (11.2 long, cabin 1.9 wide, height 3.4, rotor ⌀10.6): its OWN silhouette — longer twin-engine
body, 4-blade rotor, enclosed fenestron-style or classic tail, open side-door openings to a rear cabin, skids,
search-light pod under the nose as part `searchlight` (origin at its gimbal, lens `@LightHead`), light strobes
`@LightSirenA/B`, `@Paint1`/`@Paint2` police livery with 3D "POLICE". Same parts/markers as `heli_civil` (no doors
needed) + marker `gunner_l`, `gunner_r` (hip points at the open side doors, facing outward).

`plane_prop` "Kestrel" (length 8.3, wingspan 10.8, height 2.9): high-wing single-prop 4-seater with wing struts and
fixed tricycle gear. Parts `body` (fuselage loft `@Paint1` with `@Paint2` stripe, `@Glass` cabin, wings with slight
dihedral and tip lights (`@LightIndL` red left, `@LightIndR` green right), tailplane, fin, gear legs, 4 seats),
`prop` (spinner + 2–3 blades, origin at the hub, spins about Y), `wheel_n`, `wheel_l`, `wheel_r` (origin centre, axle
X), `aileron_l`, `aileron_r`, `elevator`, `rudder` (thin control surfaces, origin on their hinge line), `door_fl`,
`lod1`, `col_body` (fuselage hull), `col_wing` (wing box). Markers `seat_driver`, `seat_passenger`, `seat_rl`,
`seat_rr`, `engine`, `exhaust`, `light_head_l`. z = 0 at the bottom of the wheels, level attitude.

P2: `plane_jet` "Arrow" (length 12.2, span 10.4, height 3.6): sleek small private jet — pointed nose, low swept wings
with winglets, two tail-mounted engine pods, T-tail, tricycle gear. Same parts as `plane_prop` minus `prop`
(add `col_wing`). Engine exhaust markers `exhaust_l`, `exhaust_r`.

## P2 — Train

`train_bayline` (12.5 × 2.6 × 3.1; z = 0 is the top of the monorail beam it straddles; skirts hang 0.6 below z = 0
on both sides of the 0.9 m wide beam): parts `body` (rounded-wedge ends, big `@Glass` side windows, `@Paint1` body
with `@Paint2` band, interior floor at z 0.55 with bench seats along the walls, grab poles, open doorway 1.6 wide on
EACH side at the centre, head/tail lamps), `lod1`, `col_body`. Markers `door_r`, `door_l` (floor level at each
doorway), `seat_1` … `seat_6` (hip points on the benches).

## P2 — Mod parts (category `VehicleParts`, path `vehicles/parts/<id>`, single part `mesh`)

Authored for a nominal 1.80 m wide car (Godot scales X to the car). Origin where the part touches the car.
- Wheels (complete wheel: tyre + rim, **radius exactly 0.5, width 0.34**, axle X, outer face −X, origin centre; rim
  metal in `tint_a_metal` so the game can recolour rims, tyre `tire`): `rim_steel` (plain dish + cap), `rim_sport5`
  (5 spokes), `rim_deep` (deep-dish multi-spoke), `rim_offroad` (chunky tyre blocks, beadlock ring), `rim_classic`
  (wire/slot style).
- `spoiler_lip`, `spoiler_wing` (pedestal wing), `spoiler_gt` (tall race wing on uprights) — origin bottom centre.
- `hood_scoop`, `hood_vents` — origin bottom centre. `roof_scoop`, `roof_rack` (bars + light pod `@LightAux`).
- `bumper_splitter` (front lip + canards), `bumper_bullbar` (tube bull bar), `bumper_diffuser` (rear diffuser fins).
- `skirt_sport` (left side skirt 2.6 long, origin centre top inner edge; mirrored in Godot).
- `exhaust_dual`, `exhaust_big` (tips, origin at the mounting end, pointing −Y).
Use `@Paint1` for body-coloured parts and `plastic_black`/`chrome`/`steel_dark` otherwise.

Order: `car_sedan` (perfect it) → rest of P1 cars → bike, bicycle → boat → heli_civil → plane_prop → heli_police →
P2 service vehicles → mod parts → train → jet → dinghy → P3. Export + manifest after every vehicle.
In the manifest add for each vehicle: `"wheel_radius"`, `"wheel_width"`, `"wheelbase"`, `"track"`, `"clearance"`,
`"doors"` (count), `"seats"` (count).
