# Infrastructure landmarks (landmark artist B)

Author: landmark artist B (`art:landmarks-infra`). Art direction "Sunlit Low-Poly" (ARCHITECTURE.md section 7).
Built in Blender 5.2 through MCP on top of `landmark_kit.py` (LK) and `building_kit.py` (K).

| What | Where |
|---|---|
| Builder module (all 8 assets, reproducible) | `tools/blender/assets/buildings_landmarks_infra.py` (`BUILD`, `VIEWS`) |
| Entry / QA runner (artist A's, shared) | `tools/blender/assets/buildings_landmarks.py` (`LM.run`, `LM.write_manifest`) |
| Exports | `gta/generated/models/buildings/<id>.glb` |
| Manifest (shared with artist A, all 18 landmarks) | `gta/generated/models/buildings/manifest_landmarks.json` |
| Previews | `qa/blender_previews/lm_<id>.png` (exterior), `lm_<id>_cut.png` (dollhouse), `lm_<id>_in.png` (camera shots) |

Blender: collection `GTA_GODOT/Buildings/Landmarks`, slot region `landmarks`, slot = index in `LM.ORDER`
(hangar 10, tower 11, lighthouse 12, tram_stop 13, radio_mast 14, pier_straight 15, pier_end 16, pier_ramp 17).

## 1. Assets

Numbers are measured from the meshes (`K.measure`) and match the manifest. Footprint = the solid `Building` node.

| id | landmark | collision | footprint x, z (m) | height (m) | tris | markers |
|---|---|---|---|---|---|---|
| airport_hangar | airport_hangar | trimesh | 29.86 x 29.98 | 14.29 | 8172 | Spawn_Plane |
| airport_tower | airport_tower | trimesh | 12.00 x 11.02 | 21.66 | 3346 | - |
| lighthouse | lighthouse | box (+ collision_boxes) | 6.33 x 7.22 | 26.25 | 1542 | Gallery, Door |
| tram_stop | tram_stop | trimesh | 12.00 x 4.00 | 3.55 | 924 | Use_Bench, Board |
| radio_mast | radio_mast | box (+ collision_boxes) | 6.00 x 6.00 | 31.00 | 3680 | Parachute_Spot, Ladder_Bottom, Ladder_Top |
| pier_straight | - (category misc) | trimesh | 4.00 x 12.00 | 3.90 (piles to -6) | 758 | - |
| pier_end | - (category misc) | trimesh | 4.00 x 6.00 | 3.10 (piles to -6) | 966 | Ladder_Top, Ladder_Bottom |
| pier_ramp | - (category misc) | trimesh | 4.00 x 8.05 | 2.36 (piles to -6) | 438 | - |

Total 19,826 tris. All names / businesses are original ("Hangar One", "Halcyon Airfield", "Bay Tram", "Halcyon Light").

- **airport_hangar - "Hangar One"**: steel hangar under a 12-segment barrel roof with standing ribs and six roof
  lights. Open front 24.6 x 8.6 m (clear width between the parked door leaves 24.3 m), sliding door leaves parked
  in front of the corner piers under a steel track beam, "HANGAR ONE / HALCYON AIRFIELD" on the gable, corrugated
  side walls (navy base course, teal band, downpipes), clerestory glazing, personnel doors with canopies on the
  right and back walls. Interior: concrete floor with taxi lead-in line and stop bar, arch trusses + tie rods +
  hanging lamps (clear height 10.3 m under the ties), ops cabin, parts racks, workbenches, tool chests, lockers, tyre
  rack, drums, crates, a spare propeller on the wall, a maintenance work stand and an aircraft tug.
  `Spawn_Plane` = floor centre (Godot (0, 0.06, 1.5)), facing out of the door.
- **airport_tower**: white square shaft with a window stack and teal floor bands, octagonal cab with outward-raked
  glazing on a railed gallery, roof radar bar, antenna mast with red beacon, dish. Low terminal wing in front: open
  2.0 x 2.5 m doorway, 3.3 m ceiling, check-in desk with two tills, departures board, staff door, two seat rows,
  vending machine, plants, rug. Yard: windsock, generator. Only the wing is enterable (the shaft is solid).
- **lighthouse - "Halcyon Light"**: octagonal stone plinth with steps and a pedimented porch, 16-sided tapered
  tower in 7 red / white bands with small windows, corbelled gallery with railing, lantern with glazing bars and
  `M_Glass` panes around a glowing lens drum in **`M_LampGlow`** (lamp centre at y = 22.25), red cone roof,
  ventilator ball, lightning rod and vane. Collision "box" with tight `collision_boxes` (plinth, tower, gallery,
  lantern) in the manifest.
- **tram_stop - "Bay Tram"**: raised 0.30 m platform with 1.2 m end ramps, yellow tactile strip and white edge
  line on the **+Y / Godot -Z (track) side**, cantilever shelter (teal sloped canopy with fascia sign and under-canopy
  light strips), glass back wall + wind screen, route map, advertising light box, slatted bench, hanging
  "TRAM STOP" sign, totem with the tram logo, ticket machine, bin.
- **radio_mast**: red / white banded square lattice tower (base 2.6 m, top 0.9 m, 9 sections of X bracing) on a
  fenced concrete pad, caged ladder up the front face through a hatch into the railed 2.8 x 2.8 m top platform at
  y = 26.0, panel antennas, microwave dish, dipoles, red obstruction beacons (`M_Beacon_Red`, top + mid height),
  equipment cabinet with cable tray, "DANGER HV" sign at the gate gap. Collision "box" with stepped
  `collision_boxes` (pad, 3 trunk steps, platform, cabinet).
- **pier_straight / pier_end / pier_ramp**: marina kit, 4 m wide (world `PIER_HALF_W` 2). Plank deck in two wood
  tones on stringers, pile bents every 4 m (2 m from each end, so pieces tile), X bracing, kerbs, cleats.
  Straight: lamp post + life buoy. End: end railing with a gap, swim ladder down into the water (to -2.6), green
  navigation light, bollards, bench facing the sea, life buoy. Ramp: sloped gangway with anti-slip battens, steel
  handrails, quay abutment.

## 2. Placement contract (city builder)

- Same as every building: origin = footprint centre on the ground, front = Godot -Z (street side), Godot
  coordinates of markers in the manifest `markers` (+ `marker_yaw`, yaw 0 = facing -Z).
- Walk-in landmarks (`trimesh`): build the collider from `collision_nodes` (Building, Building_Interior,
  Building_Glass). Detail / Neon nodes are visual only.
- **tram_stop**: world lots are `tram_stop_1..3`; the manifest entry has `"landmark": "tram_stop"` and
  `"serves": ["tram_stop_1", "tram_stop_2", "tram_stop_3"]` - map any `tram_stop_N` lot to this model.
  Platform top at +0.30 m (`platform_height`), boarding edge on the front side.
- **Pier pieces** (origin at **deck top** = walking level, not at the sea bed): place them at
  `y = WorldLayout.PIER_DECK_Y (1.15)`, yaw 0, x = each `PIER_X`:
  - `pier_ramp` centre at z = (QUAY_Z + PIER_RAMP_Z) / 2 = 256: its +Y/Godot -Z end (north, quay) is +1.37 m higher
    (= quay deck 2.52), its south end is level with the pier deck.
  - `pier_straight` (12 m) pieces from z 260 southward, then `pier_end` (6 m) with its closed end toward the sea
    (Godot +Z). Lengths: ramp 8 + 12 n + end 6. The current 24 m between PIER_RAMP_Z 260 and PIER_END_Z 284 fits
    two straights (centres 266, 278) without an end piece, or one straight (266) + pier_end (centre 275, deck end
    278); for straight + straight + end set PIER_END_Z to 290 (end centre 287). Decision left to WORLD.
    `pier_end` `Ladder_Top` sits 0.45 m inside the closed end; the ladder itself hangs on the end face
    (the world `ladder` spawn point is at PIER_END_Z + 0.05).
  - `world_citymesh.gd` currently draws simple procedural piers at the same place; use one or the other.
- radio_mast: the lot is on Signal Hill (229, -131.5). `Parachute_Spot` is on the top platform (y 26.0);
  `Ladder_Bottom` / `Ladder_Top` give the climb ends for the interaction system (the ladder is a visual mesh in
  `Building_Detail`; with "box" collision the climb itself must be scripted).
- lighthouse: `Gallery` marker is on the gallery deck (y 20.25) for the parachute / cash pickup the pickup system
  places at the lighthouse.

## 3. Reproduce / QA

```python
import buildings_landmarks as LM; importlib.reload(LM); LM.reload()
LM.run(["airport_hangar"])                                    # rebuild + audit + measure + previews
LM.run(LM.ORDER[10:], preview=False, export=True)             # the 8 infra GLBs
LM.write_manifest(); G.save()
```
Godot check (done, all names / materials / markers intact):
`tools\godot.ps1 -Mode script -Script res://gta/code/editor/print_scene_tree.gd -UserArgs '--scene=res://gta/generated/models/buildings/airport_hangar.glb'`
(also run for radio_mast, lighthouse, pier_end).

## 4. Known limits

- The tower shaft, lighthouse and mast are not enterable (by design / brief); the mast ladder is visual.
- The lantern glass uses the shared vehicle glass material `M_Glass` (alpha ~0.45) so the `M_LampGlow` lens shows.
- Audit "suspect" faces (informational heuristic) are non-zero on the larger assets (buried trim faces);
  duplicate and degenerate faces are 0 everywhere.
- Not yet seen in the running game (no city builder placement exists yet) - only verified as imported scenes.
