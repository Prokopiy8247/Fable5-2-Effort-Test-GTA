# HALCYON BAY - City builder ("city" world system)

Owner: city builder programmer (WORLD module, Wave 2). Contract: `docs/ARCHITECTURE_WAVE2.md` W2.4.
Fills every lot of `Game.world.get_lots()` with the Blender-authored buildings of
`gta/generated/models/buildings` (30 generic + 18 landmark / infrastructure GLBs), with collision, night
materials, distance culling, occluders, landmark markers, ladders, automatic landmark doors, a pooled room
light for shop interiors and a GLB visitor pier in the marina.

| File | What |
|---|---|
| `gta/code/world/city_builder.gd` | `CityBuilder` = system `city` (BootManifest), placement, doors, room light, API |
| `gta/code/world/building_catalog.gd` | `BuildingCatalog`: loads + merges every `manifest*.json` of the buildings folder |
| `gta/code/world/city/city_planner.gd` | which building goes on which lot (pure data, deterministic) |
| `gta/code/world/city/city_proto.gd` | one prototype per building type: shared meshes, shapes, occluders, markers, LOD rules |
| `gta/tests/city_api.gd` | headless API / placement / collision / doorway / door / ladder-fit / spawn-point test (198 checks) |
| `gta/tests/city_play.gd` | the REAL player driven by Input actions: walks into every walk-in landmark, climbs the safehouse stair to the bed, the radio-mast ladder (up and down) and the pier swim ladder |
| `gta/tests/city_shots.gd` | windowed screenshots `qa/screenshots/city_*.png` + render cost per view |

## 1. Boot

`setup()` runs after `world` and `environment` (BootManifest order). Measured (headless, 2026-11-10):
**about 270 ms** (plan 28, GLB load 180, placement 56, post 3) for **175 buildings** (18 landmarks,
123 buildings, 30 small fillers, 4 pier pieces) from **all 48 catalogue types**, **1418 nodes**,
357,751 triangles in total (interiors included), 0 empty lots. The line `[City] built ...` prints it.

GLBs are loaded synchronously once each (threaded loading raced on material RIDs in the renderer:
"Initializing already initialized RID" - do not switch it back on).

## 2. How the lots are filled (`city_planner.gd`)

- **Landmark lots** (`lot.landmark != ""`) get the building whose manifest `landmark` is that name, or
  that lists it in `serves` (`tram_stop` serves `tram_stop_1..3`). `parking_garage` has no landmark entry
  and uses `parking_a`. Origin = lot centre on the ground, yaw = lot yaw (front -Z faces the street).
- **Generic lots** (zones `office, apartment, house, storefront, warehouse, hangar`) of one block row
  form a *run* along the street. The run is cut into units of **one lot or two neighbouring lots**.
  A unit holds one or two main buildings of the zone's category (hangar zone: `tag:hangar` = the
  airport hangar, then warehouses) plus optionally one small filler (`kiosk_a` for offices /
  storefronts / apartments, `garage_row` / `shed_a` for industrial; houses get a back-yard `shed_a`
  when the lot is deep enough). Two-lot units are what lets the wide buildings appear at all:
  `office_c` (35.8 m), `office_e`, `warehouse_b` (39.9 m), `storefront_a/c/f` are wider than any
  single lot of their zone. 40 of the units are merged pairs.
- Fit rules: full width (footprint + side overhangs) <= unit width - 2 x 0.1 m, 0.25 m between two
  buildings of a unit, depth (footprint + front / back overhang) <= lot depth + 0.3 m.
- Scoring: frontage fill (x4), catalogue novelty (+1.6 for an unused type, -0.5 per earlier use), +0.45
  for a district tag match, +0.35 for `tall` downtown, +2.5 for hangars in the hangar zone, -6 for the
  same building as the previous one in the row (never happens in the current layout - tested),
  houses are penalised above 90 % fill (side yards), +0..0.6 seeded jitter. Greedy with one-lot
  lookahead (single + next single vs. merged pair).
- **Setback from the lot front** (generic buildings are aligned to the street, not centred in the lot):
  offices / storefronts 0.25 m (awnings / marquees stay inside the lot), apartments 25 % of the spare
  depth (0.5..2.5 m), houses 55 % (2..6 m front yard), warehouses / hangars 50 % (0.5..7 m apron).
- Deterministic: own `RandomNumberGenerator` seeded per run (`SEED = 520017 + 9173`, block, row, first
  lot id) - never `Game.rng`, so `--seed` does not change the city.
- Lots too small for any main building become a paved yard with a filler (none in the current layout).
- Ground fit (builder): the ground is sampled at 9 points of the footprint; the building is raised to
  the highest one (never sunken); if the ground falls more than 0.6 m under the footprint a concrete
  plinth (flat-shaded box + box collider) is added. The current layout has no sloped lot (0 plinths):
  the lighthouse knoll and the hill-top pad are flat. Measured (city_api): worst ground above a floor
  corner 0.06 m, worst gap under a footprint corner 0.01 m.
- `SINK` (builder): `tram_stop` is set 0.22 m into its lot so the platform edge is 0.08 m. Its sharp 0.30 m
  edge stopped the real player dead (see section 11); the concrete body reaches 0.4 m below the origin, so
  nothing opens up, the end ramps just start ~0.9 m later.

Current usage: office_a 6, office_d 6, office_c 2, office_b/e/f 1, storefront_d 9, _e 8, _b 8, _c 8,
_a 7, _f 7, apartment_a/c 5, _b/_d 2, warehouse_a/c 8, _d 5, _b 3, houses 2-4 each, airport_hangar 2
(landmark + one copy), kiosk_a 19, shed_a 8, garage_row 3, every landmark once (tram_stop 3).

## 3. Special placements

| What | Where |
|---|---|
| lighthouse | lot `lighthouse` (8, 274), front to the lane; lens `M_LampGlow` glows at night |
| radio mast | lot `radio_mast` (229, -131.5) on the hill-top pad (alias `hill_top`) |
| tram stops | lots `tram_stop_1..3`, platform edge toward the tracks |
| airport tower / hangar | lots `airport_tower`, `airport_hangar`; one more hangar copy in the hangar row |
| shooting range | lot `shooting_range` |
| **visitor pier** | GLB marina kit at **x = -45** (east end of the marina, where WORLD has no procedural pier): `pier_ramp` (quay deck 2.52 -> deck 1.15, z 252-260), 2 x `pier_straight`, `pier_end` (z 290), trimesh collision, surface `wood`, swim ladder. The procedural piers at x = -210 / -150 / -90 are left alone (lead decision). The spot is chosen by code: quay deck height at the ramp start and water depth >= 1.2 m under every piece (candidates -45, -120, -180, -240) |
| rooftop helipad | `world.set_location("rooftop_helipad", ...)` = the hospital roof pad (manifest `helipad`, world (-100, 20.85, 9.5)); also `add_spawn_point("heli", ...)` there |
| parachute | `add_spawn_point("parachute", ...)` at the radio-mast platform (`Parachute_Spot`, y 26 m above the hill top) |

## 4. API (`Game.get_system("city")`)

W2.4 contract, exact:

```gdscript
func has_landmark(landmark: String) -> bool
func get_landmark_node(landmark: String) -> Node3D
func get_landmark_transform(landmark: String) -> Transform3D              # building origin, world space
func has_landmark_marker(landmark: String, marker: String) -> bool
func get_landmark_marker(landmark: String, marker: String) -> Transform3D # world space
func get_landmark_markers(landmark: String) -> Dictionary                 # marker name -> Transform3D
func get_buildings() -> Array[Dictionary]                                 # {id, lot_id, category, transform, footprint: Vector2, height}
```

- Landmark names = the lot names: `police_station, hospital, gun_shop, shooting_range, mod_garage,
  clothing_store, barber, general_store, gas_station, safehouse, parking_garage, airport_hangar,
  airport_tower, lighthouse, radio_mast, tram_stop_1, tram_stop_2, tram_stop_3` + `marina_pier` (the
  GLB pier end). Aliases: `hill_top` -> `radio_mast`, `tram_stop` -> `tram_stop_1`.
- Markers: the manifest `markers` (Godot building-local) + `marker_yaw` (yaw 0 = facing -Z); GLB empties
  fill in names the manifest lacks. World transform = building transform * marker, -Z = the marker's
  facing. Two synthesized markers: **`Entrance`** (on the doorway from the manifest `entrance`, -Z
  pointing INTO the building; a doorway more than 1.5 m inside the footprint - the gas-station kiosk behind
  its forecourt - faces the street, so its inward is +Z; tested for all 13 walk-ins) and **`Helipad`**
  (hospital roof pad). An unknown marker returns the
  building transform; an unknown landmark returns the world's named location of that name.
- `get_buildings()` extras: `landmark`, `role` (`landmark | building | filler | pier`), `lot_ids`
  (both lots of a merged unit), `node`, `rect` (Rect2 x / z of the solid footprint), `zone`,
  `district`, `collision`, `walk_in`, `plinth`, `markers` (building-local).
- Additions: `is_built()`, signal `city_built`, `get_landmark_names()`, `get_landmark_building(lm)`,
  `get_building_at(pos)`, `get_ladders()`, `get_doors()`, `get_debug_info()` (= `stats`),
  `set_enabled(on)` (shows / hides the city and stops / restarts the door + room-light loop; collision stays).

## 5. Rendering, collision, cost

- **Instancing**: each GLB is instantiated once into a prototype; every copy is a `Node3D` with plain
  `MeshInstance3D` children that reference the shared `Mesh` resources (no GLB sub-scene per lot, no
  marker nodes). Helper meshes (`Col_*`, `*Collision*`) are never created.
- **Night materials**: `M_Window*` -> `env.get_window_material_mode(1 if UVs else 2)` (building-kit pane
  UV cells), `M_LampGlow` / `P_LampWarm` -> `get_lamp_material()`, `P_Neon*` ->
  `get_neon_material(colour)`; swapped **once on the shared mesh resource** per surface, never per
  instance. The instances are in group `env_no_night_hook`, so the environment's automatic per-instance
  hook skips them. `M_Glass`, metals and every other material keep the imported look.
- **Walk-in windows** (trimesh buildings with a `Building_Interior`): the panes are double (one faces out,
  one in) and the lit-window shader is opaque, so from inside a shop the player looked at solid blue
  panels. The inward-facing `M_Window` triangles (normal toward the footprint centre) get one shared,
  lightly tinted transparent `City_InteriorGlass`; the outward ones keep the lit-window hook (`cull_back`),
  so from inside you see the street and from outside nothing changes. A new mesh per type (the cached GLB
  mesh is untouched); 210 inner-pane triangles city-wide (`stats.interior_glass_tris`).
- **Collision**: manifest `box` -> one `StaticBody3D` ("Body", `Layers.WORLD`, mask 0, meta
  `surface` = `concrete`, `building_id`) with the manifest `collision_boxes` (tight stepped boxes) or a
  footprint x roof-height box; `trimesh` -> one `ConcavePolygonShape3D` (backface collision on) per
  building type, built from the manifest `collision_nodes` (`Building`, `Building_Interior`,
  `Building_Glass`; never Detail / Neon), shared by every copy. A manifest `stair` ({bottom, top, width},
  safehouse) adds a walkable box ramp under the flight (top surface 0.09 m above the bottom->top line =
  through the middle of the 0.18 m risers, clipped to floor and landing; 29.6 deg): the safehouse treads
  are `Building_Detail`, so without it the mezzanine bed (`Use_Bed`) could not be reached. Piers: `surface = wood`. Gas pumps
  `Pump_1..4` get their own small box bodies (meta `surface = metal`, `explosive_object = Pump_n`).
  Shapes are shared resources: 48 types, not 175 copies.
- **Distance culling** (`visibility_range_end`, fade SELF, 8 % margin): towers (height >= 18 m or
  footprint >= 500 m2) shell + glass always visible; mid buildings 900 / 700 m; small (< 9 m, < 160 m2)
  520 / 380 m; Detail 160 / 230 / 320 m; Neon 420 m (towers always); **interiors 55 m**; doors 140 m;
  pumps 160 m.
- **Shadows**: only the shell casts (plus Detail of buildings >= 30 m); glass, neon, interiors, doors,
  pumps and fillers' details do not.
- **Occluders**: an `OccluderInstance3D` with a shared `BoxOccluder3D` (inset 0.6 m) inside every
  collision box >= 7 x 5 x 7 m of the `box` buildings. **Inert until the lead enables
  `rendering/occlusion_culling/use_occlusion_culling=true` in project.godot** (requested).
- **Room light**: one pooled warm `OmniLight3D` (no shadows, energy 1.4, range 6-12 m) placed under the
  ceiling lamps (`P_LampWarm` faces between 1.8 and 6 m) of the walk-in landmark nearest to the camera
  (within 24 m), fades over 0.4 s. 12 walk-in landmarks have a spot. Costs 1 positional light of the
  shared budget of 16, by day too (shops have their lights on).
- **Measured render cost** (`city_shots`, 1280x720, RTX 5070, day, no traffic / peds / props):
  380-1500 draw calls in city views (incl. shadow passes), 0.26-0.60 M primitives in view (incl.
  terrain + ocean), **GPU 0.51-0.71 ms, render CPU 0.4-1.6 ms per frame**.

## 6. Landmark doors and ladders

- **Doors**: every `MeshInstance3D` named `Door_*` in a building (today only the safehouse `Door_1`;
  `Door_Front` there is a marker, not a door) is managed by **one loop** in `CityBuilder._process`:
  10 Hz scan of the player (on foot) and - only while the player is within 60 m of a door - the
  nodes of group `npc`; a character within **2.5 m** (horizontal, |dy| < 2.5) opens it (100 degree swing
  about its hinge = the node origin, smoothstep, 0.31 s), it closes again when nobody is near.
  Exported-open leaves (|yaw| > 20 degrees) close to yaw 0; leaves exported closed open by -100 degrees.
  Plays `door_open` / `door_close` through `/root/Audio.play_at` if present. Doors have **no collision**
  (they open before anyone reaches them; bullets pass a closed door).
- **Ladders** (W2.4): `Ladder_Bottom` + `Ladder_Top` markers become a `Node3D` "Ladder" in group
  `ladder` under the building: climber facing local -Z (the `Ladder_Bottom` yaw), meta `height`
  (`Ladder_Top`.y - foot.y), extra metas `top` (world position of `Ladder_Top`, where a climber steps off),
  `building`, `line_bottom` / `line_top` (world points of the real rail line).
  The `Ladder_Bottom` marker is where a climber STANDS, but `PlayerStateLadder` keeps the body 0.36 m
  behind the node and climbs straight up, so the node is put on the rail line measured from the GLB
  (`CityBuilder.LADDER_FIT`):
  - radio mast: rails at z -1.36 (foot) .. -0.66 (platform) building-local - the caged ladder leans 0.7 m
    with the tapering mast. Node at z -1.15 = vertical best fit (body inside the cage at the foot, clear
    of the platform slab at the top, top exit 0.55 m in = on the 2.8 m platform). Height 25.85 m.
    With the marker position (z -2.25) the player climbed 1.2-1.9 m outside the cage.
  - pier end: swim-ladder rails at z 3.0 .. 3.17; node at z 3.12 (was 3.6: the top exit landed 0.05 m
    past the end of the deck). Height 1.2 m, foot at sea level.
  The dressing system skips the mast because a ladder node already stands within 1.5 m of the marker.

## 7. Navigation

After placement the builder calls `world.rebuild_navigation(rects, false)` with the real footprints
(axis-aligned world rectangles) of every building except `gas_station` (open forecourt), `parking_a`
(walkable ground floor), tram stops and pier pieces, so the yards and alleys behind buildings become
walkable (WORLD's default carves whole lots). The first bake after a change runs ~0.9 s on a worker
thread, later boots load the cache. User flag `--city_keep_nav` skips the rebuild.

## 8. Tests

`city_api` runs with every system enabled; the others keep only moving traffic / pedestrians / police out of the
way (props, shops, garage, pickups and respawn stay on):

```powershell
tools\godot.ps1 -Mode headless -Frames 1800 -TimeoutSec 300 -UserArgs '--test=city_api','--test-timeout=250'
tools\godot.ps1 -Mode headless -Frames 6000 -TimeoutSec 300 -UserArgs '--test=city_play','--test-timeout=250','--disable=traffic,peds,police,emergency,wildlife,taxi,transit,activities,radio,ambience'
tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 200 -UserArgs '--test=city_shots','--test-timeout=150','--no_player','--hour=13','--freeze-time','--weather=clear','--disable=traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 200 -UserArgs '--test=city_play','--test-timeout=150','--city_play_quick','--hour=13','--freeze-time','--weather=clear','--disable=traffic,peds,police,emergency,wildlife,taxi,transit,activities,radio,ambience'
```

`city_api` (PASS, 198 checks): API methods; every landmark lot has its building at the lot centre facing
the lot yaw (18); every landmark of LANDMARKS.md / LANDMARKS_INFRA.md has a transform and all manifest
markers at `xform * marker`; no footprint on a road segment, no two footprints overlap, every footprint
on its lot(s); a ray from above hits every building's own body on `Layers.WORLD`; no building sunken
> 0.3 m or floating > 0.65 m without a plinth; all 48 catalogue types used; no identical buildings side by
side in a row; ladders (mast 25.85 m, pier 1.2 m) on their rail lines with a solid top exit where
`PlayerStateLadder` puts the climber; the GLB pier deck is walkable and continuous; `rooftop_helipad`
on the hospital roof and solid; office windows use the lit-window hook; gun-shop interior range-culled,
office_c always visible; every `Entrance` marker faces into its building; no gameplay spawn point
(peds, pickups, gangs, parking, police, taxi, roadblocks ...) inside a solid building (3 tram-stop
benches lie inside the open shelters - fine); **a capsule (r 0.3 m, 0.35 m step, 1.8 m tall) walks
from 1.8 m in front of the street facade through the doorway to every ground-floor `Use_*` marker**
(grid search, 16 markers in 13 landmarks); the safehouse door opens with the player 1.3 m away and
closes when he leaves; `set_enabled(false/true)`; boot time < 2.5 s.

`city_play` (PASS headless, 26 checks): the real player, `Input.action_press`:
`move_forward` from 3.5 m in front of every walk-in landmark (13) through the doorway 1.8 m inside
(the capsule search above ignores step height - this does not: it found the tram-stop edge); the
safehouse door swings open on the way in; up the safehouse stair to the mezzanine (1.6 s) and to the
bed; `interact` at the radio-mast foot, `move_forward` 25.85 m (16.5 s) onto the platform, `interact`
at the top exit and `move_back` down to the ground (15.6 s); swim to the pier-end swim ladder,
`interact`, climb onto the deck. `--city_play_only=tram,stair,mast,pier,walk:<landmark>` runs parts.
Windowed it mounts the ladders directly at the heights it photographs (runs must stay <= 20 s):
`qa/screenshots/city_play_*.png`.

`city_shots`: 23 screenshots - skyline from the bay, downtown canyon + aerial, midtown street,
two residential streets, industrial, docks row, police station, gun shop, mod garage, safehouse, gas
station, hospital, gun-shop and safehouse interiors, marina pier, airport, hill mast, lighthouse,
night downtown / street / skyline - plus a `PERF` line per view.

## 9. Integration notes

- **Shops / activities / respawn / garage**: put Interactables on `get_landmark_marker(lm, "Use_*")`,
  staff on `Staff`, cars on `Spawn_Car_n` / `Spawn_Ambulance` / `Garage_Spot`, respawn on hospital
  `Respawn`, range lanes on `Lane_n`. All transforms are world space, -Z = facing.
- **Interaction system** (`interactions`): landmark doors are already animated by the city (do not
  animate `Door_*` again); ladders are in group `ladder` with the W2.4 metas.
- **Props / dressing**: building footprints are `get_buildings()[i].rect`; the downtown plaza, park,
  industrial yard and marina promenade lots are left empty for you; `kiosk_a` / `shed_a` /
  `garage_row` fillers already stand on some lots.
- **Gas station explosions**: pump bodies carry meta `explosive_object` (`Pump_1..4`), the pump meshes
  are the sibling `MeshInstance3D` of the same name under the gas-station node.
- **Light budget**: the city uses 1 positional light (room light) near walk-in landmarks.

## 10. Known limits

- The hangar copy in the hangar row carries the same "HANGAR ONE" sign as the landmark hangar (the sign is
  merged into its `Building_Detail`).
- Doors have no collider; only the safehouse has a door leaf at all (asset content).
- Plinth code path exists but no current lot needs one, so it has not been seen in game.
- Occlusion culling is off in the project: the occluders cost nothing and do nothing until enabled.
- Interior lighting: by day the room light is the only warm light. The inner window panes are see-through,
  the outer panes stay opaque (lit-window shader): you can look out of a shop, not into it.
- The radio-mast ladder leans 0.7 m, `PlayerStateLadder` climbs vertically: with the best-fit node the
  hands are ~0.15 m from the rails at the foot and ~0.8 m at the top. A player module that interpolates
  between the `line_bottom` and `line_top` metas would follow the cage exactly.
- The GLB visitor pier is not in `World.get_minimap_data()["piers"]` (WORLD owns that cache).

## 11. Review (independent reviewer, 2026-11-10)

Fixed (all covered by tests above):
1. **Radio-mast ladder** node stood on the `Ladder_Bottom` marker 0.9 m in front of the rails: the
   player (vertical climb 0.36 m behind the node) climbed 1.2-1.9 m outside the cage. Now on the
   measured rail line (`LADDER_FIT`), metas `line_bottom` / `line_top` added; climbs up and down in
   city_play.
2. **Pier-end swim ladder**: the top exit (node - 0.55 m) landed 0.05 m past the end of the deck, so a
   swimmer who climbed out fell straight back. Node moved onto the rails (z 3.12); city_play climbs out.
3. **Safehouse stair** had no collision (treads in `Building_Detail`): the mezzanine bed `Use_Bed` (sleep /
   save) was unreachable on foot. Walkable ramp from the manifest `stair`.
4. **Tram stops**: the real player could not get onto the 0.30 m platform from the street (capsule
   search passed because it ignores step height). `SINK` 0.22 m.
5. `set_enabled(true)` restarted `_process` only when doors existed (the room light stopped updating);
   `set_enabled(false)` left the room light on. Fixed + tested.
6. `Entrance` marker of the gas station faced the street (door inside the footprint). Fixed + tested.
7. Planner look-ahead used the FIRST building of an option as the next lot's neighbour instead of the
   last one (`_last_main`), so "same building twice in a row" could be mis-scored. Fixed.
8. `city_shots` docks camera stood behind the dressing's signal poles; moved.
9. Walk-in interiors looked out through opaque blue panels (lit-window shader on the inner panes):
   inner panes are now transparent glass (section 5). Tested in city_api, seen in
   `city_interior_gun_shop.png` / `city_interior_safehouse.png`.
10. `get_doors()` / the door loop cast a possibly freed door node before checking it; now checked first.

Checked and fine: W2.4 names / signatures / return types, group `ladder` + `height`, layers
(`Layers.WORLD`, mask 0), `env_no_night_hook`, no `Game.rng`, soft dependencies only (environment via
`has_method`, Audio via `/root/Audio`, world via `has_method`), no per-frame allocations in `_process`
(door scan 10 Hz, room light 4 Hz), pause / time scale (scaled `delta`), player in a vehicle (doors
ignore him), far teleport (doors close, room light fades), no save state needed, no growing pools.
