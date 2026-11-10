# Cinder Bay — Development Notes

Missionless GTA-style single-player free-roam sandbox on a compact ~600 × 600 m map, built in
**Godot 4.7.2 (stable, Forward+, Vulkan, Jolt Physics, GDScript)** with every important 3D asset authored
procedurally in **Blender 5.2.2 LTS** through the project-bound Blender MCP connection
(`blender-gta-extra`, `localhost:9880`, master file `GodotFable5.2GTAExtra.blend`).

There are **no missions, quests, objectives or story markers** anywhere in the game. Everything is free roam;
optional activities (shooting range, stunt jumps, ring-road time trial) are started by the player.

---

## 1. Build / run

| What | How |
|---|---|
| Play | Open the folder in Godot 4.7.x and press **F5**, or run `Godot_v4.7.2-stable_win64.exe --path "<this folder>"` |
| First import | Godot imports the GLBs in `gta/generated/models/` automatically (Blender import is disabled in project settings; only the exported GLBs are used) |
| Main scene | `res://gta/scenes/bootstrap/main.tscn` → `gta/code/core/main.gd` |
| Automated scenario | `powershell -File tools/run_test.ps1 -Test <name> -Frames N -TimeoutSec S` (screenshots + log in `_qa/`) |
| Script check | `powershell -File tools/check.ps1` (import scan + load every script; prints any parse errors) |
| Save file | `user://cinderbay_save.json` (F5 quick-save, F9 quick-load, bed in the safehouse also saves) |

GPU safety (spec §3A) is built into the tooling: `run_test.ps1` checks `nvidia-smi` before starting and waits if
the GPU is busy, refuses to start a second Cinder Bay instance, always passes `--quit-after` and kills the
process on an OS-level timeout, and runs at 1280×720. The shipped game uses V-Sync, `run/max_fps = 60` and a
render scale of 1.0.

Test scenarios in `gta/code/debug/test_harness.gd`: `world, night, play, sim, systems, police, misc, looks, fx,
verify, verify2, perf, rest, stunt, boat, final, orphans`.

---

## 2. Controls (keyboard + mouse; most actions also have gamepad bindings)

**On foot**
| Key | Action |
|---|---|
| W A S D | move · **Shift** sprint · **Space** jump / climb a ledge (0.45–2.35 m) · **C / Ctrl** crouch (stealth) |
| Mouse | look · **RMB** aim · **LMB** fire / melee · **R** reload · **X** quick melee · **G** throw grenade |
| Q | take / leave cover (A/D slide along cover, RMB peek, LMB blind fire) |
| Space while aiming + direction | combat roll / dodge |
| crouch (or knife) + melee from behind an unaware NPC | stealth takedown |
| E | interact (shops, ATM, bed, wardrobe, garage, elevator, ladders, train, range…) |
| F | enter / exit vehicle (taking an occupied car = carjack; hold Shift+F at a taxi to steal it) |
| Tab (hold) | weapon wheel · **mouse wheel / 1–8** cycle weapons / slots |
| M | full map (LMB set waypoint + GPS route, RMB clear) · **T / ↑** phone · **P** stats & skills |
| V | first / third person · **B** look back · **F12** photo mode · **Esc** pause |
| F1 | **admin / benchmark menu** · **F5 / F9** quick save / load |

**Vehicles** — W/S throttle & brake/reverse, A/D steer, Space handbrake, H horn, L headlights, N radio station,
K convertible roof, Q siren (emergency vehicles), RMB + LMB drive-by (SMG / pistol / revolver), F exit.
**Helicopter** — Space up, C down, W/S pitch, A/D roll, Q/E yaw. **Airplane** — Shift/C throttle up/down,
W/S pitch, A/D roll, Q/E rudder, Space wheel brakes. **Boat** — W/S throttle, A/D rudder.
**Swimming** — Space up, C dive, Shift fast. **Parachute** — Space to deploy in free-fall, A/D steer, W dive,
S flare, F cut away. **Train** — E to board at a platform, F to get off at the next station.

---

## 3. Architecture

Everything is assembled at runtime from data + Blender GLB kits; the main scene only holds the bootstrap node.

```
gta/
  code/
    core/      game.gd (autoload G: layers, signals, InputMap, helpers, crime/noise bus)
               assets.gd (autoload Assets: GLB loading, material unification, shader swaps, tinting)
               main.gd (bootstraps the world and all systems)
    world/     world_layout.gd (static map description: road grid, districts, terrain height)
               world_builder.gd (chunks, MultiMesh buildings/props, roads, terrain, sea, colliders)
               world_blocks.gd (per-district content), time_weather.gd, fx.gd, interactions.gd,
               services.gd (taxi + ambulance / fire engine), train.gd, activities.gd
    player/    player.gd, player_camera.gd, character_visual.gd (procedural skeletal animation + IK),
               inventory.gd, ragdoll.gd
    vehicles/  vehicle.gd (base), car.gd (raycast suspension/tyres, bikes), boat.gd, heli.gd,
               airplane.gd, vehicle_factory.gd
    ai/        npc.gd, ped_manager.gd (sidewalk graph, population, witnesses), wildlife.gd, shark_body.gd
    traffic/   traffic_manager.gd (spawn/despawn, signals, parking), vehicle_ai.gd (lane graph driver,
               routing, pursuit, PIT/box-in, dismount)
    police/    wanted.gd (0–5 stars, witnesses, LOS, search/escape, dispatch, roadblocks, spikes, heli)
    weapons/   weapons.gd (hitscan, melee, ballistics), projectile.gd (rockets, grenades, molotovs)
    ui/        hud.gd (minimap, full map, GPS, stars, prompts), weapon_wheel.gd, menu_panel.gd,
               menus.gd (pause, stats, settings, phone, photo mode), ui_kit.gd
    audio/     sfx.gd (procedural synthesis of all sounds, engines, sirens, ambience, 5 radio stations)
    save/      save.gd
    debug/     admin_menu.gd (F1), test_harness.gd
  resources/
    data/defs.gd      vehicles, weapons, ammo, weapon mods/tints, car mods, paints, finishes, clothes, hair, store
    shaders/          window (night-lit windows), foliage (wind), tint_custom, road, terrain, water, sky, pave
  generated/models/   Blender exports: vehicles/, characters/, weapons/, props/, world/
  scenes/bootstrap/main.tscn
tools/
  blender/            Python modules executed in Blender through MCP (asset authoring + export)
  run_test.ps1, check.ps1, check_all.gd, dump.gd
```

Key runtime ideas

* **World chunks** (`WorldBuilder.chunk`) per district: road/sidewalk geometry is baked with `SurfaceTool`, modular
  facades and repeated props are `MultiMeshInstance3D` (per-instance colour + custom data drive the tint shader),
  colliders are boxes / trimesh / a `HeightMapShape3D` terrain. World build takes ~1.1 s.
* **LOD / culling**: props, foliage and distant tree belts use `visibility_range`; vehicles and characters have
  Blender-authored LOD1 meshes; NPCs and traffic have distance-based simulation tiers and despawn rules.
  Parked / abandoned cars freeze (static) after settling and wake on contact, damage or entry.
* **Materials** are unified by name on load (`Assets.shared`) so the whole city uses ~200 shared materials;
  `*Tint` materials become vertex/instance-colour driven; window glass gets the night-lit window shader.
* **Global shader uniforms** `night_factor`, `wetness`, `wind_time` animate windows, wet roads and foliage.
* **Vehicles** are `RigidBody3D`s with project-owned physics: raycast suspension + friction-circle tyres (cars),
  upright PD controller (bikes), four-point buoyancy (boats), PD attitude/altitude control (helicopters),
  thrust/lift/stall model with tricycle gear (planes). Road vehicles flood and sink in deep water.
* **Characters** use one rigged Blender human (male + female body) with procedural pose blending in
  `character_visual.gd` (locomotion, crouch, cover, sit, bike, swim, ladder, fall, parachute, actions) and analytic
  two-bone IK for the off-hand on weapons. Ragdoll is a "ragdoll-lite": a tumbling capsule rigid body carrying the
  visual in a limp pose (no per-bone physics).
* **Crime bus**: `G.report_crime()` → `Wanted._on_crime()` decides whether police saw it, civilians witnessed it
  (they run, then phone it in and can be stopped) or people only heard it. Police LOS calls `Wanted.spotted()`;
  the escape timer only runs while the player is unseen.
* **No navmesh**: pedestrians walk a generated sidewalk/crosswalk graph with direct steering and simple
  obstacle side-stepping; vehicles drive a lane graph. `NavigationRegion3D` was not used (see limitations).

---

## 4. Map

Cinder Bay — playable footprint x, z ∈ [-300, 300] (+X east, +Z south), sea to the south, hills around.

| Region | Content |
|---|---|
| Financial Core | glass towers, Cinder Tower (rooftop helipad, elevator), parking |
| Midtown | Mercy General Hospital (respawn point, helipad, ambulances) |
| Civic Square | CBPD Headquarters (busted respawn, police lot), Civic Parking Deck (stunt "Deck Dive"), train station |
| Market Street | Sunny Mart store, clothes shop, barber, gun shop + workbench, ATM |
| Lantern Park | park, fountain, train station, time-trial start |
| Maple Flats / Sandy Row | houses, apartments, the player **safehouse** (bed = save, wardrobe, personal garage) |
| Bayfront | hotels and promenade |
| Ironworks | warehouses, Sunny Fuel gas station, **Torque Bay Customs** (mod shop), shooting range, stunt "Eastside Air" |
| Harbor Docks / Marina | cranes, containers, three piers with boats and ladders, stunt "Pier Pressure" |
| Coral Beach | sand, umbrellas, lifeguard towers, long pier to **Ember Point Lighthouse** island |
| Cinder Field Airport | runway, hangar, control tower with **animated radar**, planes/helicopters, stunt "Runway Rocket" |
| Ember Hill | dirt track up to a viewpoint, wildlife, stunt "Ember Hill Leap" |
| Sea floor | kelp, rocks, fish schools, sharks, **Sunken Trawler** wreck with a treasure chest |
| Loop Line | elevated two-car train circling the city (two stations) |

---

## 5. Blender asset workflow

1. Verified the MCP connection (namespace `blender-gta-extra`, PID listening on 127.0.0.1:9880, open file =
   `G:\YouTube\Fable 5.2 Effort Test GTA\Extra\GodotFable5.2GTAExtra.blend`) and backed the master file up to
   `_blender_backups/` before the first change. Pre-existing collections were left untouched.
2. Assets are authored by Python modules in `tools/blender/` that are executed inside Blender through
   `execute_blender_code` (`fable_lib.py` = bmesh modelling helpers `MB`, materials, export; `palette.py`,
   `vehicles.py`, `cars_defs.py`, `vehicles2.py`, `characters.py`, `weapons.py`, `kit_buildings.py`,
   `kit_props.py`, `extras.py`).
3. Everything lives under the `GTA_GODOT` collection tree (Characters, NPCs, Vehicles/{Cars, Motorcycles, Boats,
   Helicopters, Airplanes}, Weapons, Buildings, StreetProps, Interiors, Nature, VFX_HelperMeshes, CollisionHelpers).
4. Visual QA in Blender with the MCP `look` tool (Workbench/EEVEE material view only, no Cycles, no renders larger
   than 1920×1080).
5. Export: one GLB per vehicle, kits (facades, landmarks, props, interiors, nature, animals, weapons, character
   parts, VFX helpers) with prefix-named objects (`<asset>_<Part>`), `Mod_*` customisation parts, `P_*` marker
   empties (seats, doors, exhaust, lights, muzzles), `*_COL_*` collision helpers and LOD1 meshes. The radar is the
   only asset exported with an animation (`RadarSpin`).
6. Godot imports the GLBs; `Assets` strips prefixes, unifies materials and swaps in project shaders;
   `Vehicle.setup()` turns COL helpers into convex shapes and markers into seats/doors/lights.
7. After every export the master `.blend` is saved through MCP.

Scale of the Blender work: 21 vehicles (+ wheel-rim kit), 2 rigged humans with clothing/hair/accessory parts and a
parachute canopy, 17 weapons with attachments, 24 facade modules, 26 landmarks/buildings, ~64 street props,
16 interior props, 19 nature assets, animals (deer, boar, cow, coyote, rabbit, dog, cat, seagull, pigeon, two fish, shark), VFX/pickup
helpers — ~670 meshes in the `.blend`, 35 GLB files.

---

## 6. Known limitations

* No `NavigationRegion3D`/navmesh — pedestrians use a hand-built sidewalk graph; they do not path around
  arbitrary dynamic obstacles or enter buildings.
* World "streaming" is static: all district chunks are built at start (≈1.1 s) and culled by distance/visibility
  ranges; nothing is loaded/unloaded from disk at runtime.
* No reusable `.tscn` prefabs were generated; scenes are assembled in code from GLB kits and data tables.
* Ragdolls are single-body "ragdoll-lite", not per-bone physical ragdolls.
* Vehicle damage has no mesh deformation or detachable panels (health → smoke → fire → explosion → burnt wreck,
  tyre popping, glass/lights unaffected).
* Interiors are limited to shop counters/props and the safehouse room; most buildings are not enterable.
* Audio is fully procedural (synthesised); there is no recorded music or voice acting.
* Police use cars, SWAT vans and a helicopter; the police boat exists as a drivable vehicle but is not dispatched.
* A Godot-internal warning (`2 ObjectDB instances were leaked at exit`, an AudioStreamWAV playback) is printed on
  quit; it has no gameplay effect.
