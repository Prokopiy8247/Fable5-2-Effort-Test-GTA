# Marlow Bay — development notes

Missionless GTA-style free-roam sandbox on a compact ~600 × 600 m island. Built by Claude Fable 5.2 in one
autonomous session with Godot 4.7.2 and Blender 5.2 (through the `blender-gta-high` MCP connection).

## Engine and renderer

| Item | Value |
| --- | --- |
| Godot | 4.7.2.stable.official (`W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`) |
| Renderer | Forward+ (Vulkan), RTX 5070 |
| Physics | Jolt Physics, 60 Hz |
| Language | GDScript only (no C#, no add-ons, no Asset Library packs) |
| Safety defaults | V-Sync on, `run/max_fps = 60`, 3D scale 1.0, 2048 shadow atlas, MSAA 2x, bounded particles/lights |

Render pipeline: custom sky shader (gradient, sun/moon disc, stars, procedural clouds), one shadowed
DirectionalLight (2 splits, 140 m), sky ambient + filmic tonemap, glow, SSAO, exponential fog,
shader-drawn road markings with a global `wetness` uniform, depth-fading water shader.

## Blender connection (Section 0 verification)

| Item | Value |
| --- | --- |
| MCP server / tool namespace | `blender-gta-high` (`mcp__blender-gta-high__*`), stdio `uvx mcp-for-blender --port 9879` |
| Endpoint | localhost:9879 |
| Verified by | read-only `execute_blender_code` returning `bpy.data.filepath` before any change |
| Master file | `G:\YouTube\Fable 5.2 Effort Test GTA\High\GodotFable5.2GTAHigh.blend` (Blender 5.2.2 LTS) |
| Backup of the untouched original | `backups/blender/GodotFable5.2GTAHigh_original_20261109.blend` |
| Pre-existing content | default `Collection` (Cube, Light, Camera) left untouched |

The add-on reported protocol 13 vs. expected 15; it was **not** patched or updated (per the rules) and every
call used worked through its fallbacks. No external asset library or generator was used (all were off).

## Blender asset workflow

All geometry is authored by Python executed inside the live Blender through MCP. The scripts are kept in
`tools/blender/` so every asset can be regenerated:

| Script | Produces |
| --- | --- |
| `gta_lib.py` | mesh builder (boxes, lofts, limbs, prisms), materials, collections, GLB export helper |
| `a01_materials.py` | shared flat-colour palette (~125 materials) |
| `a02_cars.py` | wheel library (5 rims) + 13 lofted road vehicles with doors, interiors, mod parts, markers |
| `a03_vehicles_other.py` | motorcycle, bicycle, 2 boats, 2 helicopters, prop plane, jet |
| `a04_characters.py` | male + female rigged humanoids (17 bones) with 22 skinned attachments each |
| `a05_weapons.py` | 14 weapons + 3 projectiles, with suppressor / optic / light / grip / magazine parts |
| `a06_buildings.py` | 7-piece façade kit + 42 assembled buildings with `-colonly` collision helpers |
| `a07_props.py` | 54 street props, 7 pickups, parachute canopy, 14 nature pieces, 7 animals |
| `a08_export.py` | GLB export per asset root + `manifest.json` (bounds, triangle counts) |

Flow: MCP edit → viewport check with the MCP `look` tool (Workbench/EEVEE only, ≤1500 px) → save master →
GLB to `gta/generated/models/<category>/` → `godot --headless --import` → runtime material unification
(`Assets.unify`) → gameplay setup in code. The master `.blend` is marked `importer="skip"` so Godot never
imports it directly.

Collections in the master file: `GTA_GODOT / {Vehicles/{Cars,Motorcycles,Boats,Helicopters,Airplanes,Wheels},
Characters, NPCs/Animals, Weapons, Buildings/Kit, StreetProps, Interiors, Nature, VFX_HelperMeshes,
CollisionHelpers}` — 661 named objects, no `Cube.001`-style leftovers.

Art direction (chosen): bright flat-shaded low-poly "sunny coastal city" — solid palette colours, no image
textures, readable silhouettes, emissive windows/neon at night.

## Project architecture

```
res://gta/
  code/core      game.gd (state, input map, UI stack), data.gd (registries), assets.gd (GLB + material library)
  code/world     city.gd (layout, lane + sidewalk graphs, terrain fn), ground.gd, day_night.gd, props.gd,
                 pickups.gd, services.gd (taxi, EMS, fire), train.gd, activities.gd, world.gd (assembly)
  code/player    player.gd, char_rig.gd (procedural animation + arm IK), camera_rig.gd, inventory.gd
  code/vehicles  vehicle.gd (car/bike/boat/heli/plane physics), vehicle_def.gd
  code/traffic   traffic.gd (ambient, parked, showcase), driver_ai.gd (lane, pursuit, go-to)
  code/ai        npc.gd, ped_manager.gd, animal.gd, wildlife.gd
  code/police    wanted.gd, heli_ai.gd, spike_strip.gd
  code/weapons   weapon_def.gd      code/combat  combat.gd, projectile.gd, fx.gd
  code/ui        hud.gd, hud_canvas.gd, minimap.gd, weapon_wheel.gd, menu.gd, shops.gd
  code/audio     sfx.gd, ambient.gd     code/save  save_game.gd
  code/debug     admin.gd (F1 benchmark menu), autotest.gd (scripted validation)
  generated/     models/ (GLB + manifest), audio/ (72 synthesised WAVs), nav/ (baked NavigationMesh)
  resources/     data/weapons/*.tres, data/vehicles/*.tres, themes/menu_theme.tres
  scenes/bootstrap/main.tscn
```

Autoloads: `Game`, `Data`, `Assets`, `Sfx`, `Fx`, `Wanted`, `SaveGame`.
`main.tscn` is a single root whose script (`world.gd`) builds the city from `City` data and the Blender GLBs,
so there is no hand-assembled scene to maintain. Repeated props are MultiMeshes (2,045 prop instances in
~60 draw groups); light props become pooled rigid bodies only when hit.

Simulation tiers: NPCs near (<45 m) full, mid (<95 m) reduced think/animation rate, far simplified movement;
ambient traffic and pedestrians spawn 40–140 m away outside the view frustum and despawn at 125–175 m.

## Scene layout (districts)

Downtown (4 central blocks, towers up to 22 floors), Midtown Market (shops, gun store, clothing, barber, food),
Palm Court (houses, safehouse, Founders Park), Ironworks (warehouses, Torque House, gas station, container
yards, shooting range), Bayfront / Coral Beach (promenade, Skyline monorail, pier, lighthouse rock),
Port Marlow (quay, crane, containers), Signal Hill (wooded hill, viewpoint, radio tower, wildlife),
Marlow Airfield (560 m runway, apron, hangars, tower, two helipads).

## Controls

| Context | Keys |
| --- | --- |
| On foot | WASD move, Shift sprint, Space jump / vault / parachute, C crouch + stealth, Q cover, F enter/exit, E interact |
| Combat | RMB aim (melee: block), LMB fire / punch (hold = heavy), R reload, Tab weapon wheel, 1–8 / wheel switch, aim + Space roll |
| Vehicles | WASD, Space handbrake, H horn, L lights, G siren, `,` `.` radio, B look back, T flip, RMB + LMB drive-by |
| Helicopter | W/S pitch, A/D yaw, Q/E roll, Space climb, C descend |
| Airplane | W/S throttle, A/D roll, Q/E rudder, Space or ↓ pull up, C or ↑ push down |
| Other | V first person, M map (click = waypoint), P phone, Esc pause, F1 benchmark menu, F5/F9 quick save/load, F12 photo mode |

## Build / run

1. Open the folder in Godot 4.7.2 and press F5, or run
   `Godot_v4.7.2-stable_win64_console.exe --path "<this folder>"`.
2. First launch after cloning: `godot --headless --path . --import` (imports GLB/WAV, builds the class cache).
3. Regenerate audio: `python tools/audio/gen_audio.py`. Regenerate the navmesh / data resources:
   `tools/run_godot.ps1 -Test bake_nav -Headless`, `-Test export_data -Headless`.
4. Validation runs: `tools/run_godot.ps1 -Test <boot|tour|drive|combat|wanted|air|water|ui|night|systems|chute|flows|perf|assets|final> -Seconds N`
   (1280×720, 60 fps cap, `--quit-after`, OS-level timeout and kill, GPU check before start).
   `tools/check.sh` parses all scripts headlessly.

## GPU-safety log (Section 3A)

Every run went through `tools/run_godot.ps1`: one instance, 60 fps cap, hard frame limit, timeout + kill,
`nvidia-smi` gate at 85 %. Observed GPU utilisation during tests: 0–13 %, VRAM ~4.6–5.3 GB total across
all agents. No device-lost, TDR or stutter events occurred. Blender used only Workbench/EEVEE viewport
captures; no Cycles, no bakes. No uncapped benchmark was run.

## Known limitations

- Animation is fully procedural (FK layers + arm IK); no authored clips. "Ragdoll" is a tumbling single body
  with a limp pose, not per-bone physics.
- Vehicles do not physically collide with characters; fast vehicles knock them down through a proximity test.
- Traffic picks lanes at intersections but does not change lanes mid-block.
- Only the gun shop, mod garage and safehouse have interiors; other buildings are solid.
- Vehicle doors are hinged skins over the body shell (no opening behind them); no convertible roofs, liveries,
  trunk/hood interaction, elevators or automatic doors.
- Audio is synthesised and was validated for loading/playback paths, not auditioned by ear.
- Controller bindings exist for the basics but were not tested.
- Several systems are implemented but were not covered by an automated run — see `FEATURE_MATRIX.md`.
