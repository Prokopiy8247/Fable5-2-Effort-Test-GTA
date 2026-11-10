# DEVELOPMENT — Port Fable (Fable 5.2 GTA, Low)

Run ID: `run-20261109-214834`. Segment 1 started 2026-11-09T21:48:34+01:00 and stopped at about 21:50, blocked because no Blender MCP was registered. Segment 2 (all implementation) started 2026-11-09T21:57+01:00 after the user registered the server. Timestamps are in `.fable-5.2-gta-runs/run-20261109-214834/`.

## Environment (verified)
- Project: `G:\YouTube\Fable 5.2 Effort Test GTA\Low` (the existing `project.godot`; no nested project).
- Godot: `W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe` (4.7.2 stable), renderer **Forward+**, GDScript only, no addons.
- Blender MCP: tool namespace `mcp__blender-gta-low__*` (server `blender-gta-low`, `uvx mcp-for-blender --port 9877`, localhost:9877), Blender 5.2.2 LTS.
- A read-only call (`bpy.data.filepath`) returned `G:\YouTube\Fable 5.2 Effort Test GTA\Low\GodotFable5.2GTALow.blend`, which is the assigned master file. Before the first write it was backed up to `.fable-5.2-gta-runs/run-20261109-214834/GodotFable5.2GTALow.backup_original.blend`.
- The add-on reports protocol 13 against an expected 15; code execution, scene info and viewport capture all worked. Asset libraries and 3D generators are off and were not used.

## Art direction
Clean flat-shaded low-poly "toy city": saturated flat colours, no textures, emissive signs and windows, blocky articulated characters. The same palette (`tools/blender/gta_lib.py`, `PAL`) is used for every asset. Square particle sprites and solid-colour UI follow the same look.

## Blender asset workflow
All meshes are authored by `bpy` scripts executed through the MCP connection, inspected with viewport captures, saved into the master `.blend` and exported as one GLB per asset.

| Script (`tools/blender/`) | Produces |
|---|---|
| `gta_lib.py` | Shared builder: palette materials, box/tube/profile/loft geometry, UVs, vertex groups, collections, GLB export |
| `build_cars.py` | 13 road vehicles with separate wheels and 6 mod parts each |
| `build_vehicles2.py` | Motorcycle, bicycle, speedboat, 2 helicopters (separate rotors), prop plane (separate propeller), jet |
| `build_chars_weapons.py` | 2 rigged humans (13-bone armature), 12 accessories, 6 animals, 12 weapons with attachment parts and muzzle empties, rocket projectile |
| `build_world.py` | 30 buildings (text signs converted to mesh), 43 street/world props, 4 interior props, 8 nature assets, 2 VFX helper meshes |

To rebuild: in Blender (through MCP) add `tools/blender` to `sys.path`, reload `gta_lib`, then `exec` a build script. Each script replaces its own assets and re-exports to `gta/generated/models/<category>/`. Conventions: forward is +Y in Blender (−Z in Godot), origin on the ground, child parts named `<asset>__<part>` (`__wheel_fl`, `__mod_spoiler`, `__att_scope`, `__muzzle`). Collections live under `GTA_GODOT/` (Characters, NPCs, Vehicles/…, Weapons, Buildings, StreetProps, Interiors, Nature, VFX_HelperMeshes, CollisionHelpers). `CollisionHelpers` is empty: collision is generated in Godot (trimesh for buildings, boxes for props and vehicles).

Then run `Godot --headless --import --path .` so Godot imports the GLBs. Direct `.blend` import is disabled in `project.godot`; the `.blend` is the source only.

## Project architecture (`res://gta/`)
The main scene `scenes/bootstrap/main.tscn` has one script, `code/core/main.gd`, which builds everything in code. Autoload `G` (`code/core/game.gd`) holds global references and helpers.

| Area | File | Role |
|---|---|---|
| core | `defs.gd` | Data registries: vehicles, weapons, attachments, upgrades, clothing, building footprints, districts |
| core | `game.gd` | Autoload: model cache, shared materials, raycasts, damage routing, explosions, skills, money |
| world | `world_builder.gd` | Terrain heightmap, road plate and markings, block fill, landmarks, props, water shader, MultiMesh nature, navmesh bake, pickups, interact points |
| world | `road_graph.gd` | 5×5 intersection lane graph, signal phases, routing |
| world | `prop.gd` | Knockable/destructible props (frozen until disturbed, despawn after waking) |
| world | `sky.gd` | Day/night, 5 weather states, rain, lightning, pooled lamp lights, wet roads |
| world | `activities.gd` | Shooting range, stunt jumps, street time trial |
| player | `humanoid.gd` | Shared character base: rig, procedural animation, weapons, melee, damage, knockdown |
| player | `player.gd`, `camera_rig.gd` | Player controller and camera |
| ai | `npc.gd`, `population.gd`, `animal.gd` | NPC brains, spawn tiers, wildlife |
| traffic | `ai_driver.gd`, `traffic.gd` | Lane-following/goto/pursuit/helicopter drivers, traffic spawn, taxi, ambulance, fire engine |
| vehicles | `vehicle.gd` | Raycast-suspension cars and bikes, boats, helicopters, planes, damage, mods |
| police | `wanted.gd` | Wanted levels, witnesses, search/pursuit, dispatch, roadblocks, arrest |
| combat | `fx.gd` | Pooled particles, tracers, decals, lights, grenades, rockets |
| audio | `audio.gd` | Every sound synthesized at startup, including three radio loops |
| ui | `hud.gd`, `menus.gd` | HUD, minimap, map, weapon wheel; shop/phone/pause/admin menus |
| save | `save.gd` | JSON save in `user://fable52_gta_low_save.json` |
| debug | `autotest.gd` | Scripted validation runs |

Collision layers: 1 world, 2 vehicles, 3 characters, 4 props. Vehicles do not collide with characters; hits on pedestrians are resolved by an oriented-box test in `vehicle.gd`.

Performance measures: pooled FX, MultiMesh vegetation, frozen props and parked vehicles, NPC update tiers (every frame under 55 m, every 3rd frame under 110 m, every 10th beyond), spawn/despawn rings for pedestrians and traffic, animation skipped beyond the near tier, capped light counts (10 lamp lights, 5 FX lights), V-Sync on and `max_fps=60`.

## Scene layout
Island of about 580×510 m of land (`x` −288…288, `z` −292…212) inside open sea.
- 4×4 city blocks between roads at −200, −120, −40, 40, 120 on both axes; the outer ring is a four-lane arterial.
- North row: Ironworks (factory, warehouses, mod garage, gas station, shooting range, parking deck, gang yard).
- Centre/east: Downtown (offices, Skyline Tower with roof elevator, police station, hospital with helipad, weapon and clothing shops).
- West: Maple Heights (houses, safehouse with interior and garage) and Central Park.
- South: Harbor Row, promenade, beach, two piers, container quay with crane, sunken wreck offshore.
- East: airport (406 m runway, two hangars, tower, two helipads).
- North edge: Northridge Hills (24 m ridge, pines, viewpoint, wildlife).

## Controls
WASD move/drive · mouse camera · Shift sprint · Alt walk · Space jump/vault/handbrake/parachute · C crouch (stealth) · LMB fire/punch · RMB aim/block · MMB heavy melee · R reload · Q cover (A/D slide, RMB peek, Shift+A/D round a corner) · X roll while aiming · F enter/exit/carjack · E interact · Tab weapon wheel · 1–8 weapon slots · wheel next/previous weapon · V first person · H horn · L lights · G siren · Z radio · P or Up phone · M map · Esc pause · F1 admin menu · F5 quick save · F12 hide HUD.
Aircraft: W/S pitch, A/D roll, Q/E yaw, Shift/Ctrl lift or throttle. Swimming: Space up, Ctrl or C dive. Parachute: W dive, S flare, A/D steer, F cut away.

## Build / run
- Play: open the folder in Godot 4.7.2 and press F5, or `Godot_v4.7.2-stable_win64.exe --path .`.
- Parse/boot check without GPU: `tools/check.sh`.
- Scripted tests: `tools/run_test.sh <plan> [headless|window] [timeout]`, where plan is a comma list of `boot,tour,night,drive,fly,boat,combat,police,ui,traffic,misc,death,input,stunt,perf`. Every run has an OS-level timeout and a 30 fps cap; windowed runs use 1280×720 and write screenshots to the run `tmp/` folder.

## GPU safety
No Cycles renders were made; Blender QA used the viewport only. Godot ran one instance at a time, each with a hard timeout, a 30 fps cap in tests and `nvidia-smi` checked before windowed runs (GPU utilisation was 1 % each time). No uncapped benchmark was run. No stress signals were observed.

## Known limitations
See `FEATURE_MATRIX.md` and `FABLE_5.2_FINAL_REPORT.md`.
