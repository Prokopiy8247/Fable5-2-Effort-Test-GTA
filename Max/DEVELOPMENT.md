# NEON TIDE: Vesper Bay — Development Notes

Original missionless open-world crime sandbox built for the **Claude Fable 5.2 Godot + Blender MCP GTA benchmark (Max effort)**.
This file is the living technical reference. It is updated as systems land.

## 1. Environment (verified at session start)

| Item | Value |
|---|---|
| Run ID | `run-20261109-215759` (start `2026-11-09T21:57:59+01:00`, see `.fable-5.2-gta-runs/`) |
| Project directory | `G:\YouTube\Fable 5.2 Effort Test GTA\Max` |
| Godot | `4.7.2.stable.official.ed1daf0bf` — `W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe` |
| Renderer | Forward+ (Vulkan 1.4, RenderingDevice) |
| Physics | Jolt Physics (built-in), 60 Hz |
| Language | GDScript only (no C#/.NET) |
| Installed add-ons / packages | none (no `addons/`, no Asset Library content) |
| GPU | NVIDIA GeForce RTX 5070, 12 GB — **shared with other agents**, see §9 |
| Blender | 5.2.2 LTS (`W:\Blender\blender.exe`, PID 29612 at verification time) |
| Blender MCP namespace | `blender-gta-max` (tools `mcp__blender-gta-max__*`) |
| Blender MCP endpoint | `localhost:9881` (listener owned by the Blender PID above; scene prop `blendermcp_port = 9881`) |
| Master Blender file | `G:\YouTube\Fable 5.2 Effort Test GTA\Max\GodotFable5.2GTAMax.blend` (verified through `bpy.data.filepath` over MCP) |
| Master file backup | `_blender_backups/GodotFable5.2GTAMax_ORIGINAL_20261109-2157.blend` (taken before first modification) |

Notes
- The Blender add-on reports protocol 13 while the MCP server expects 15. It works through fallbacks; the add-on was **not** patched or updated (spec §0 forbids it).
- An earlier aborted attempt left `.fable-5.2-gta-runs/run-20261109-214907/` (start 21:49:07, no work products, no accessible usage log). It is preserved untouched and reported as a separate segment.
- Only `execute_blender_code`, `get_scene_info`, `get_addon_status` and `look` are used. The asset-library / AI-generation tools of the connector (`search_assets`, `import_asset`, `generate_3d`) are **never** used (spec §2).
- Godot's automatic `.blend` importer is disabled for this project (`filesystem/import/blender/enabled=false`): the master `.blend` is an editable source, runtime assets are explicit GLB exports (spec §41).
- The run was interrupted twice by the account's usage limit (see `.fable-5.2-gta-runs/run-20261109-215759/segments.md`).

## 2. Art direction (chosen autonomously)

**"Sun-bleached low-poly coast, neon after dark."**
Clean stylised low-poly forms, hard chamfered edges, flat colours from one shared 16×16 palette atlas, no photographic textures.
Daylight is warm and slightly hazy; at night emissive windows, signs and vehicle lamps carry the image (glow + wet reflective asphalt in rain).
The same language is applied to characters (chunky articulated low-poly figures, region-coloured clothing), vehicles (chamfered profile-extruded bodies with real cabins, doors and separate wheels), weapons, buildings (modular facade kit), props, UI (flat cards, cyan/pink accents) and VFX (chunky stylised particles).

## 3. Asset pipeline

```
GodotFable5.2GTAMax.blend  (collections GTA_GODOT/…)
  └─ tools/blender/*.py  executed THROUGH the Blender MCP (execute_blender_code)
       └─ visual QA with the MCP `look` tool (Workbench/EEVEE viewport, small images)
            └─ per-asset GLB export → res://gta/generated/models/<category>/<asset>.glb
                 └─ `godot --headless --import`
                      └─ Assets autoload: Blender material names → shared project shaders
                           └─ factories (vehicles/characters/weapons/world) add physics + gameplay
```

Conventions
- 1 Blender unit = 1 m. Assets face **+Y in Blender = −Z (forward) in Godot**. Origins on the ground at the asset centre unless noted.
- Faces are coloured by pointing their UVs at a palette cell (`gta/resources/data/palette.json`, append-only).
- Blender material names are a contract: `Palette`, `PaletteDry`, `Window`, `Glass`, `Paint1`, `Paint2`, `LightHead`, `LightTail`, `LightReverse`, `LightIndL`, `LightIndR`, `LightSirenA`, `LightSirenB`, `LightAux`, `SignalR/A/G`, `Character`, `Foliage`.

## 4. Running

- Open the folder in Godot 4.7.2 and press **F5**, or: `Godot_v4.7.2-stable_win64.exe --path "<project>"`. The game starts directly in free roam at the safehouse.
- Automated runs always go through `tools/run_godot.ps1` (frame limit + OS timeout + GPU back-off + single instance).
  - `tools/run_godot.ps1 -Mode import` — headless import / class scan
  - `tools/run_godot.ps1 -Mode headless -Frames 1200 -UserArgs '--gta-test=<scenario>'`
  - `tools/run_godot.ps1 -Mode window -Frames 300 -UserArgs '--gta-test=<scenario>'` (1280×720, 60 FPS cap, screenshots in `_test_output/`)

## 5. Project architecture

### Boot sequence
`res://gta/scenes/bootstrap/main.tscn` → `core/main.gd` builds the `World` (terrain, roads, ground, sea, city, lane graph;
≈6.4 s; whole boot ≈10 s) and then `core/boot_systems.gd::boot()` creates the gameplay layer: entity containers, FX, skills, player +
camera, the `UI` CanvasLayer (HUD + UIManager) and every optional system **only if its script exists** (so partial
builds always run). The navigation mesh bakes on a worker thread right after the world is built (≈0.8 s, ~11k polygons).

### Autoloads
| Name | Script | Role |
|---|---|---|
| `Events` | `core/events.gd` | global signal bus (crime, noise, wanted, deaths, cash, UI ...) |
| `Settings` | `core/settings.gd` | `user://settings.cfg`, GPU-safe defaults (V-Sync, 60 FPS cap, render scale ≤ 1) |
| `Assets` | `core/assets.gd` | palette textures, Blender-material → shader mapping, model cache / instancing |
| `Audio` | `audio/audio_manager.gd` | pooled 3D/2D players, loops, buses (SFX, Ambient, Music, UI), underwater low-pass, name aliases |
| `Game` | `core/game.gd` | service locator (`Game.player`, `.wanted`, `.traffic` ...), cash / stats / cheats / flags, game-time `clock`, slow motion, ray helpers |
| `SaveSystem` | `save/save_system.gd` | JSON slots in `user://saves/` (providers: player, time, weather, skills, garage, wanted, activities) |
| `TestRunner` | `debug/test_runner.gd` | `--gta-test=<a,b>` scenario runner + screenshots (`_test_output/`) |

### Runtime scene tree
```
Main
├─ World (world/world.gd)          terrain chunks, Roads, Ground, Sea, Bounds, City (buildings, landmarks, props,
│                                   scatter MultiMeshes, Signals), Nav (NavigationRegion3D)
├─ Entities/{Vehicles, NPCs, Pickups}
├─ FX (combat/fx.gd) · CameraRig · Player
├─ Systems/ Skills, Pickups, Wanted, Police, Traffic, Peds, Wildlife, Services, Garage, Activities, Transit,
│           Locations, Ambience
└─ UI (CanvasLayer) HUD (+ MiniMapView) · UIManager (MenuList, MapScreen, WeaponWheel, photo mode)
```

### Code layout (`res://gta/code/`)
| Folder | Contents |
|---|---|
| `core/` | autoloads above, `main.gd`, `boot_systems.gd`, `input_setup.gd` (every input action is created in code), `phys.gd` (collision layers) |
| `world/` | `terrain.gd`, `city_layout.gd` (nodes / roads / blocks / districts), `road_builder.gd`, `ground_builder.gd`, `geo_buf.gd`, `building_factory.gd` (merges the Blender facade kits per building, LOD), `city_builder.gd` + `city_blocks.gd` + `city_special.gd` (district content), `prop.gd` / `prop_factory.gd` / `scatter.gd`, `world_env.gd` (time, weather, sky, rain, lightning), `interactable.gd`, `locations.gd` (shops, safehouse, Torque House bay, hospital, range), `pickups.gd`, `garage_system.gd`, `transit.gd` (ZipCab) |
| `traffic/` | `road_graph.gd` (lanes, junction connectors with conflict sets, signal phases, routing), `signal_controller.gd`, `ai_driver.gd`, `traffic_manager.gd` |
| `ai/` | `npc.gd`, `ped_graph.gd` (sidewalk network), `ped_manager.gd`, `wildlife_manager.gd` |
| `police/` | `wanted_system.gd`, `police_dispatch.gd`, `emergency_services.gd` |
| `player/` | `character.gd` (shared humanoid base), `character_visual.gd` (skinned model, animation library, procedural pose layer, ragdoll), `pose_modifier.gd`, `appearance.gd`, `player.gd`, `player_moves.gd` (cover, vault / mantle, ladders, roll, takedown, free fall / parachute), `camera_rig.gd`, `skills.gd` |
| `weapons/` | `weapon_db.gd` (17 weapons, attachments, tints), `inventory.gd`, `gunner.gd`, `ballistics.gd`, `projectile.gd` |
| `vehicles/` | `vehicle_db.gd`, `vehicle.gd` (base RigidBody3D: seats, doors, lamps, damage, fire), `car.gd` (ray-cast wheels, two-wheelers), `boat.gd`, `heli.gd`, `plane.gd`, `vehicle_factory.gd`, `vehicle_mods.gd` |
| `combat/` | `fx.gd` (particles, tracers, decals, explosions, fire, water jets) |
| `ui/` | `hud.gd`, `map_draw.gd`, `menu_list.gd` (data-driven list menus), `map_screen.gd`, `weapon_wheel.gd`, `ui_manager.gd`, `shop_menus.gd`, `admin_menu.gd` |
| `activities/` | `activities.gd` (stunt jumps, shooting range) |
| `audio/` | `audio_manager.gd`, `ambience.gd` (soundscape + radio) |
| `debug/` | `test_runner.gd`, `test_scenarios.gd`, `benchmark.gd` |

### Render pipeline
Forward+ (Vulkan). One directional light plays sun by day and moon by night (PSSM shadows), sky shader (gradient keys by
sun height, clouds, stars, moon), exponential fog, FXAA, filmic tonemapping. Almost every authored surface uses **one
palette-atlas shader** (`shaders/palette.gdshader`: nearest-filtered 16×16 cells, per-instance tints, wetness response,
night-gated emission), which keeps the material count tiny and batches well. Specialised shaders: `window` (procedurally
lit windows at night), `glass`, `paint` (two paint slots, finish, damage, dirt), `vehicle_light` (8 lamp channels),
`signal_light`, `road` (procedural markings), `ground`, `water` (waves mirrored on the CPU for buoyancy), `sky`,
`character` (16 colour regions), `foliage` (double-sided, wind sway, back-lighting).
Global shader uniforms: `night_factor`, `wetness`, `window_lit_ratio`, `wind_strength`, `rain_amount`, `water_time`, `wave_amp`.

**Per-instance uniform slots** are shared per MeshInstance3D, so they are allocated project-wide with `instance_index`:

| idx | uniform | shader |
|---|---|---|
| 0 / 1 | `tint_a` / `tint_b` | palette, foliage |
| 2 / 3 | `emission_scale` / `damage` | palette (damage also in paint) |
| 4–8 | `paint_a`, `paint_b`, `finish_a`, `finish_b`, `dirt` | paint |
| 9 / 10 | `glass_tint` / `crack` | glass |
| 11 / 12 | `lights_a` / `lights_b` | vehicle_light |
| 13 | `win_cell` | window |
| 14 | `signal_state` | signal_light |

Instance colours are passed linear (`Color.srgb_to_linear()`).

## 6. Controls (keyboard + mouse; most actions also have gamepad bindings in `input_setup.gd`)

| On foot | | In vehicles | |
|---|---|---|---|
| WASD / mouse | move / look | W / S, A D | throttle, brake-reverse, steer |
| Shift | sprint | Space | handbrake |
| Space | jump · vault · climb · roll while aiming | F | enter / exit (moving: bail out) |
| C / Ctrl | crouch (stealth) | H / L / J | horn / headlights / siren |
| Q | take cover | RMB / LMB | drive-by aim / fire |
| E | interact (shops, ladders, range, safehouse) | B | look behind |
| F | enter / hijack / ride in a taxi | , / . | radio previous / next |
| LMB / RMB | fire · punch / aim · block | **Aircraft** | W S pitch, A D roll, Q E yaw |
| MMB or X | heavy melee / takedown | Shift / Ctrl | collective (heli) · throttle (plane) |
| R / G | reload / grenade | Space (free fall) | open parachute |
| Tab (hold) | weapon wheel (slow motion) | | |
| 1–8, wheel, 0 | weapon slots, holster | | |
| V | third / first person | | |

Menus: **M** map · **P / ↑** phone · **Esc** pause · **F1** admin / benchmark · **F3** FPS · **F5 / F9** quick save / load · **F8** photo mode.

## 7. Systems overview

- **World**: ≈600 × 600 m island city in 8 districts (Lookout Hill, Downtown, Ironworks, Vesper Airfield, Palm Row,
  Midtown, Coral Beach, Saltline Docks) generated at boot from `CityLayout`; Blender facade kits merged per building
  with LOD; 120+ Blender prop types plus MultiMesh scatter for vegetation; procedural stand-in buildings only for
  landmarks whose Blender model is missing (logged as `[City] stand-in`).
- **Day / night and weather**: 30-minute day; clear, cloudy, rain, fog, storm (lightning + thunder); wet roads, rain
  particles, reduced tyre grip and AI visibility; lit windows, street lamps and vehicle lamps at night.
- **Player**: locomotion with stamina, swimming / diving with breath (scuba gear), cover, stealth, vault / mantle,
  ladders, combat roll, melee combos + blocking + takedowns, free fall + parachute, physics ragdolls on death and hard hits.
- **Weapons**: 17 weapons in 8 classes with hitscan ballistics (thin props and glass are penetrated, surface impacts),
  projectiles (rocket, 40 mm grenade, hand grenade), attachments (suppressor, extended mag, reflex, 4× scope, grip,
  flashlight) and finishes; weapon wheel; drive-by.
- **Vehicles**: 13 cars / service vehicles, motorbike, BMX, speedboat, 2 helicopters and a prop plane (all Blender);
  ray-cast suspension cars, balanced two-wheelers, buoyant boats, helicopter attitude control, lift / stall plane;
  damage (smoke → fire → explosion, glass, tyre punctures, crash damage), doors, sirens, carjacking, Torque House mods.
- **Pedestrians**: sidewalk-graph walkers and free-roam areas, district looks, idle / phone / talk, perception (vision
  cone + noise), panic / cower / fight back, witnesses phone the police, simulation tiers, async nav-mesh paths.
- **Traffic**: lane graph with junction reservations and signals, kinematic speed planning, passing blocked vehicles,
  horns, panic, pulling over for sirens, parked-car streaming, hailable taxis.
- **Wanted / police**: 0–5 stars from witnessed crimes only; pursuit while seen, search area when hidden, cool-down;
  arrest attempts at low levels (BUSTED), lethal force when justified; patrols, response cars, SWAT trucks,
  roadblocks with spike strips, police helicopter with searchlight; a respray at Torque House breaks the description.
- **Emergency services**: ambulances go to casualties (paramedics take bodies away / heal you when called), fire
  engines go to fires and explosions (hoses extinguish burning vehicles).
- **Economy and services**: cash, NPC drops, robbable clerks (silent alarm), weapon shop + gunsmith workbench, clothing,
  barber, market, Torque House (repair / performance / body / wheels / paint / lights), safehouse (sleep, save,
  wardrobe, 4-car garage), phone (taxi, vehicle delivery, emergency line, camera, map), ZipCab taxis (ride or skip).
- **Activities** (no missions): 4 unique stunt jumps with slow motion, Ironworks shooting range (4 timed challenges with
  medals), hidden pickups, underwater treasure.
- **Wildlife**: gulls, dogs, cats, deer, rabbits, coyotes at night, fish schools and one shark (Blender animals).
- **Audio**: everything is synthesised (`tools/audio/gen_audio.py`): engine loops pitched by RPM, sirens, ambience beds
  crossfaded by place / time, five original generative radio stations.
- **UI**: HUD (rotating minimap with GPS route, police blips and search area, vitals, cash, stars, weapon / ammo,
  speedometer, altimeter, prompts, toasts, banners), full map, pause / settings / stats / controls / save / load,
  phone, shops, admin / benchmark menu, photo mode.
- **Save / load**: 3 slots + quick save; player, inventory, appearance, cash, stats, skills, time, weather, garage,
  personal vehicles, activity records, settings.
- **Admin / benchmark menu (F1)**: every function of spec §38 plus a 60-second benchmark camera tour that writes
  frame-time statistics to `user://benchmark.txt`.

## 8. Blender asset workflow (details)

- Modules in `tools/blender/` run inside the live Blender through the MCP (`execute_blender_code`); each family has a
  spec (`SPEC_*.md`) that fixes sizes, part / marker names and budgets.
- Kit (`gta_kit.py`): bmesh builder `MB`, palette-UV colouring, `add_text` for 3D signage, `begin_asset`, markers,
  `export_asset` (one GLB per asset, `col_*` collision parts, `lod1`), `save_master()`.
- Families and drivers: buildings (`bld_*.py`, `bld_all.build_all()`), props / nature (`props_*.py`), vehicles
  (`veh_cars.py`, `veh_cars_qa.py`, `veh_bikes.py`, `veh_boats.py`, `veh_air.py`, `veh_air2.py`, `veh_parts.py`),
  characters (`chr_*.py`, `chr_pipeline.rebuild_all()`), weapons (`wpn_*.py`), landmarks (`lm_*.py`), animals and
  pickups. The agent reports with their rebuild snippets are summarised in `.fable-5.2-gta-runs/.../delegation.md`.
- Every asset was checked with the MCP `look` tool (viewport / Workbench / EEVEE only) before export; manifests in
  `gta/resources/data/manifests/*.json` describe parts, markers, sizes and triangle counts and are read by the Godot
  factories.

## 9. GPU safety (spec §3A)

- One shared RTX 5070: every Godot run goes through `tools/run_godot.ps1` (single-instance guard, OS timeout, frame
  limit, `nvidia-smi` back-off above 85 % utilisation / VRAM, 1280×720 for windowed tests, `--headless` when no
  rendering is needed). The shipped game uses V-Sync + a 60 FPS cap and render scale ≤ 1.0.
- Blender QA used viewport / Workbench / EEVEE previews only (no Cycles), images ≤ 512 px.
- No GPU incident (device lost / TDR) occurred during development.

## 10. Testing

`tools/run_godot.ps1 -Mode window -Frames 9000 -TimeoutSec 240 -UserArgs "--gta-test=<scenarios>"` with scenarios
`smoke, world, walk, drive, look, peds, traffic, traffic_soak, police, ui, shops, services, roster, air, ragdoll,
chaos, night`. Each prints PASS / FAIL lines and a summary; screenshots go to `_test_output/` and
`tools/contact_sheet.py` combines them for review.

## 11. Known limitations (honest)

- No train / monorail: the Blender rail kit pieces exist but no train model or track is placed in the game.
- No jet, dinghy or police boat models (their data entries are greyed out in the admin spawn menu).
- NPC combat uses positioning, crouching, strafing and bursts but no full cover-graph search.
- Ragdolls use cone joints without per-axis hinge limits; bodies can occasionally fold unnaturally.
- Interiors exist only in the four shops, the safehouse, Torque House and the hangar; other buildings are solid.
- Audio is synthesised: voices are non-verbal and the radio stations are ~40-second generative loops.
- If a landmark's Blender model were missing, `CityBuilder` would place a procedural stand-in (logged as
  `[City] stand-in`); with the current assets no stand-in is used.
