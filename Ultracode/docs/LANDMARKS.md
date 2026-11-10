# Landmark and walk-in buildings

Authors: landmark artist A (shops, civic, service landmarks) and landmark artist B (infrastructure:
airport hangar / tower, lighthouse, tram stop, radio mast, pier pieces). Art direction "Sunlit
Low-Poly" (ARCHITECTURE.md section 7); built on top of the building kit (docs/BUILDING_KIT.md).

| What | Where |
|---|---|
| Entry module (order, slots, run, export, manifest) | `tools/blender/assets/buildings_landmarks.py` (`import buildings_landmarks as LM`) |
| Landmark helpers (thick walls, rooms, furniture, markers, QA renders) | `tools/blender/assets/landmark_kit.py` (`LK`) |
| Builders, artist A | `buildings_landmarks_shops.py` (gun_shop, clothing_store, general_store, barber), `buildings_landmarks_civic.py` (police_station, hospital, safehouse), `buildings_landmarks_service.py` (mod_garage, gas_station, shooting_range) |
| Builders, artist B | `buildings_landmarks_infra.py` (airport_hangar, airport_tower, lighthouse, tram_stop, radio_mast, pier_straight / pier_end / pier_ramp) |
| Exports | `gta/generated/models/buildings/<id>.glb` |
| Manifest | `gta/generated/models/buildings/manifest_landmarks.json` (merged with the other `manifest*.json` by the loader) |
| Blender previews | `qa/blender_previews/lm_<id>.png` (exterior: three-quarter, front, side, top), `lm_<id>_cut.png` (roof clipped away: plan + three dollhouse views), `lm_<id>_in.png` (four perspective camera shots from inside / doorways) |

Blender: collection `GTA_GODOT/Buildings/Landmarks`, slot region `landmarks`, slot = index in `LM.ORDER`.

---------------------------------------------------------------------------------------------------

## 1. What the game gets

### 1.1 GLB structure

```
<FileRoot> (Node3D)
  <id> (Node3D)                origin = centre of the lot on the ground, front faces -Z (street side)
    Building           (mesh)  shell: walls WITH thickness (0.3 m), floors, ceilings, roofs, stairs
    Building_Glass     (mesh)  window panes, M_Window only, double-sided (one pane faces out, one in)
    Building_Detail    (mesh)  signs, trims, lamps, cables, awnings, small dressing (non-solid)
    Building_Neon      (mesh)  emissive P_Neon* letters / strips only
    Building_Interior  (mesh)  furniture and fit-out: counters, shelves, racks, benches, beds ...
    Pump_1..4 / Door_1 (mesh)  separate objects with their own origin (gas pumps, hinged door leaf)
    <Marker>           (Node3D) gameplay points (Empties), e.g. Use_Counter, Spawn_Car_1, Lane_3
```

- Same conventions as the generic kit: 1 unit = 1 m, flat shading, shared palette materials `P_<Key>`,
  contract materials `M_Window`, `M_ScreenGlow` (small emissive screens), `M_Beacon_Red`, no textures.
- Interior floors sit at y = 0.06 (6 cm above the lot); the shell continues 0.8 m below y = 0.
- Doorways are real openings (>= 1.6 m wide, >= 2.4 m high, no door leaf in the way). The only door
  leaf is the safehouse front door `Door_1`, a separate mesh with its origin on the hinge, exported
  standing open (rotation -100 deg); the game may animate / close it.

### 1.2 Collision

All walk-in landmarks use `"collision": "trimesh"`. Build the trimesh from the nodes listed in the
manifest key `collision_nodes` (`Building`, `Building_Interior`, `Building_Glass`) - never from
`Building_Detail` / `Building_Neon` (cables, letters and lamps would snag the player and cars).
`Pump_1..4` (gas station) need their own small colliders (they are damageable / explosive).
Walls are 0.3 m thick (outer face, inner face and reveals) so a trimesh never lets the player
clip through; stairs (police station, hospital, safehouse) are solid flights.

### 1.3 Manifest keys

Contract keys (ARCHITECTURE.md 8.4) `id, file, category ("landmark"), footprint [x, z], height,
landmark, collision, entrance [x, z], tags` plus the building-kit extras (`roof_height, floors, tris,
center_offset, collision_boxes, nodes, overhang`) and the landmark extras:

| key | meaning |
|---|---|
| `markers` | `{name: [x, y, z]}` gameplay points in **Godot local coordinates** relative to the building origin (the same positions as the marker nodes in the GLB) |
| `marker_yaw` | `{name: yaw}` in radians, Godot convention (rotation about +Y, 0 = facing -Z / out of the front) |
| `collision_nodes` | mesh nodes that form the trimesh collider |
| `separate_objects` | separate mesh nodes (`Pump_1..4`, `Door_1`) |
| `sign` | the business name on the building |
| misc | `bay` (mod garage drive-in bay), `firing_line_x`, `lanes`, `lane_pitch`, `target_distance_max`, `static_targets_x` (range), `canopy_clearance`, `explosive_objects` (gas station), `helipad` [x, y, z, size] (hospital roof), `mezzanine_y`, `garage_bay` [w, d, h], `stair` (safehouse) |

All numbers are measured from the built meshes (`LM.write_manifest()`), not typed by hand.

---------------------------------------------------------------------------------------------------

## 2. The landmarks (artist A)

Footprint = solid shell (`Building`) in metres, x by z; tris = whole GLB.

| id | business | footprint | height | tris | description |
|---|---|---|---|---|---|
| police_station | HBPD | 27.9 x 22.8 | 14.3 | 3454 | two-storey L-shaped station, portico entrance with the original gold/blue shield emblem, walk-in ground-floor lobby with front desk, shield wall emblem, waiting seats, notice board, vending machine, plants; motor-pool canopy with four parking bays in the notch of the L |
| hospital | Halcyon General | 30.3 x 26.0 | 25.3 | 6588 | five-storey ward tower with mint bands and a teal emblem fin (original heart + pulse-line emblem, not a red cross), walk-in lobby podium with reception desks, waiting seats, vending machines, lift doors, plants; ambulance drive-through canopy, rooftop helipad |
| gun_shop | Bay Arms | 15.3 x 12.3 | 6.1 | 5332 | brick shop with a stepped false front, barred windows, target roundels; inside: counters with register, two gun wall racks, glass display cases, workbench with tool chest, shelving, body-armour stand |
| shooting_range | Ironsight Range | 30.0 x 12.0 | 8.2 | 2924 | covered firing line (shed) with five lane booths, counter, gun wall, lockers, seating; 23 m open target yard between concrete walls (dark dado, orange band) with overhead baffles, carrier cables, targets and two floodlight masts; earth berm and timber-faced 5.2 m bullet-stop wall |
| mod_garage | Torque Garage | 22.0 x 17.5 | 8.0 | 4266 | steel workshop hall under a gable roof; drive-in bay 5.2 m wide x 3.84 m high x 16.3 m deep with lift outline, extraction hood with booth lights (paint-booth look), colour sample wall, tool benches, tool chests, tyre racks, engine stand; parts annex with roll-up door |
| clothing_store | Tide Threads | 15.2 x 12.2 | 7.9 | 4298 | white boutique with a teal corner fin, striped awnings, big display windows with mannequins; clothes racks, shelves, folded stacks on a table, counter with register, changing booths with curtains, wall mirror |
| barber | Harbor Cuts | 11.9 x 11.9 | 6.8 | 2758 | cream pavilion under a red hip roof with a barber pole; checkerboard floor, barber chairs, mirror stations, waiting seats, counter with register, wash station, coat stand |
| general_store | Corner 24 | 15.3 x 13.1 | 6.7 | 6424 | cream corner shop with a red wrap-around fascia and a neon "24" corner tower; gondola shelves, fridge wall, chest freezer, counter with register and snack stand, coffee corner, forecourt vending machine |
| gas_station | Halcyon Fuel | 25.8 x 20.7 | 7.1 | 6382 | 21 x 9 m canopy (4.7 m clearance) over two pump islands, four pumps as separate objects, kiosk shop (Halcyon Fuel Mart) with counter, fridges, gondolas; price pylon, air post, ice chest |
| safehouse | (home, no sign) | 18.0 x 14.6 | 8.2 | 3718 | white two-storey loft under a mono-pitch roof: living room with sofas, TV unit and rug, kitchen run with fridge and breakfast counter, desk, wardrobe, stair to a mezzanine bedroom (bed, wardrobe, sofa); attached timber-clad single garage (open front, bay 4.8 x 7.4 x 2.8 m) with workbench, shelf, tyres |

### 2.1 Markers (Godot local coordinates; see the manifest for exact values)

| id | markers |
|---|---|
| police_station | `Use_Desk` (lobby, in front of the front desk), `Spawn_Car_1..4` (canopy bays, cars face the street), `Spawn_Officer_1..2` (in front of the entrance / car park) |
| hospital | `Respawn` (pavement in front of the entrance), `Use_Reception`, `Spawn_Ambulance` (under the ambulance canopy) |
| gun_shop | `Use_Counter`, `Use_Workbench`, `Staff` (behind the counter) |
| shooting_range | `Use_Start` (by the range counter in the shed), `Lane_1..5` (firing positions behind the bench, yaw faces down-range = +X), `Target_Area_Min` / `Target_Area_Max` (opposite corners of the target yard box, y 0..4) |
| mod_garage | `Use_Bay` (centre of the bay floor, on the lift), `Staff`, `Exit_Bay` (driveway in front of the bay door, facing out) |
| clothing_store | `Use_Counter`, `Use_Wardrobe` (changing booth), `Staff` |
| barber | `Use_Chair` (barber chair), `Staff` |
| general_store | `Use_Counter`, `Staff`, `Register` (on the counter, y 1.08) |
| gas_station | `Use_Kiosk` (kiosk counter), `Staff`, `Pump_1..4` (the pump objects themselves; origin on the island top, y 0.2) |
| safehouse | `Use_Bed` (mezzanine, y 3.3), `Use_Wardrobe`, `Use_Save` (desk), `Garage_Spot` (garage bay, car faces out), `Spawn_Inside` (just inside the front door), `Door_Front` (outside the front door) |

---------------------------------------------------------------------------------------------------

## 3. Integration notes

- City builder: place each landmark on a lot with `landmark` = the named location (`World.get_lots()`
  zone `landmark`); lot >= footprint, front (-Z) to the street. Gun shop / clothing store / barber put
  awnings and signs up to 1.35 m in front of the shell (`overhang.front`).
- World / shops / activities: turn `markers` into world transforms with the building's transform
  (`building_xform * Vector3(marker)`, yaw = building yaw + `marker_yaw`). Interactables go on the
  `Use_*` markers, staff NPCs on `Staff`, vehicle spawns on `Spawn_Car_*` / `Spawn_Ambulance` /
  `Garage_Spot`, respawn on `Respawn`, range lanes on `Lane_n` (`Target_Area_Min/Max` bound the yard
  for target spawning).
- Gas station: `Pump_1..4` are separate MeshInstance3D nodes (`explosive_objects`); the game can hide
  a pump and spawn an explosion at its origin.
- Mod garage: the bay is centred on x = -4.0 (Godot), door 5.2 m x 3.84 m; a car driven to `Use_Bay`
  is fully inside the hall.
- Night: windows are `M_Window` (lit-window shader), neon is `Building_Neon` (P_Neon*), interior
  ceiling lights and lamps are `P_LampWarm`.

---------------------------------------------------------------------------------------------------

## 4. Reproducing / QA

```python
import buildings_landmarks as LM; importlib.reload(LM); LM.reload()
LM.run(["gun_shop"])                          # rebuild + audit + measure + exterior / cutaway / interior previews
LM.run(LM.ORDER, preview=False, export=True)  # everything -> GLBs
LM.write_manifest()                           # every built AND exported landmark -> manifest_landmarks.json
G.save()
```

Godot checks (run 2026-11-10, last run 08:46: 10 GLBs, 46,144 tris in total):

```powershell
tools\godot.ps1 -Mode script -Script res://gta/code/editor/bld_check_generic.gd -UserArgs '--manifest=manifest_landmarks.json'
tools\godot.ps1 -Mode script -Script res://gta/code/editor/print_scene_tree.gd -UserArgs '--scene=res://gta/generated/models/buildings/gas_station.glb'
```

The building-kit checker confirms footprint, height, centre, tri count, overhangs, glass / neon
material rules and the foundation skirt of all 10 landmark GLBs against the manifest. Its only
complaints are "unexpected mesh node name" for `Building_Interior`, `Pump_n` and `Door_1`: the generic
checker only knows the four generic node names, these extra nodes are intentional. `print_scene_tree`
on `gas_station.glb` and `safehouse.glb` shows `Pump_1..4`, `Door_1` and every marker with clean names
at the manifest positions.

## 5. Known limits

- The infrastructure pieces (airport_hangar, airport_tower, lighthouse, tram_stop, radio_mast,
  pier_*) are artist B's; they are added to the same manifest when B exports them.
- Police station and hospital: only the ground-floor lobbies are walk-in; the upper storeys / ward tower
  are closed shells (windows only). The rooftop stair boxes are dressing, not access.
- Interiors are not baked for navmesh here; the world module bakes the navmesh.
- The safehouse door leaf is exported open; no door script is shipped with the asset.
