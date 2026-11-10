# Halcyon Bay — Development Notes

Original missionless GTA-style free-roam sandbox built for the *Claude Fable 5.2 — Godot + Blender MCP*
benchmark. The binding technical contract for contributors is [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Session bookkeeping

| Item | Value |
|---|---|
| Run id | `run-20261109-215759` (`.fable-5.2-gta-runs/run-20261109-215759/`) |
| Start timestamp | 2026-11-09T21:57:59.952+01:00 (Central European Standard Time) |
| Working directory | `G:\YouTube\Fable 5.2 Effort Test GTA\Ultracode` |
| Godot | 4.7.2.stable.official.ed1daf0bf (`W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`) |
| Renderer / pipeline | Forward+ (`rendering_method="forward_plus"`), Vulkan, Jolt Physics, 60 Hz physics |
| Installed packages / addons | none (no `addons/`, no Asset Library content, no C#) |
| Blender | 5.2.2 LTS (`W:\Blender\blender.exe`) |
| Blender MCP server / tool namespace | `blender-gta-ultracode` (`mcp__blender-gta-ultracode__*`), add-on "MCP for Blender" 1.8 |
| Blender endpoint | localhost:9882 (verified: `scene.blendermcp_port == 9882`, `blendermcp_server_running == True`) |
| Verified master file | `G:\YouTube\Fable 5.2 Effort Test GTA\Ultracode\GodotFable5.2GTAUltracode.blend` (read from `bpy.data.filepath` through the MCP connection before any change) |
| Pre-modification backup | `backups/blender/GodotFable5.2GTAUltracode.ORIGINAL_20261109-215759.blend` (SHA-256 `B409428272C9CA3CD69EAAB5E46671531B96D268115D277D9145CE4B95F5D1C1`) |
| Hardware | Ryzen 7 5700X3D, 64 GB RAM, single shared RTX 5070 12 GB |

The original file contained only Blender's default `Collection` (Camera, Cube, Light, `Material`); it is left untouched.
All project assets live under the `GTA_GODOT` collection tree.

## Technical plan (concise)

1. **Foundation (lead):** project settings, autoload contracts, boot manifest, test harness, Godot run
   wrapper with single-instance lock + GPU gate, shared Blender helper library, architecture contract.
2. **Wave 1 — vertical slice in parallel:** Blender asset authors (characters, cars, other vehicles, weapons,
   building kits, landmarks, props/nature) + code modules (world generation, environment, character
   animation + player + camera, vehicle physics, weapons/combat/VFX, UI/HUD, audio synthesis).
3. **Wave 2 — sandbox systems:** city dressing, traffic, pedestrians/AI, police + wanted, aircraft/boats/bikes,
   shops/economy/garage/customisation, cover/stealth/traversal/melee, admin menu.
4. **Wave 3 — breadth:** parachute/diving/wildlife/taxi/transit, emergency services, skills, activities,
   phone/radio, save/load, drive-by, damage polish.
5. **Wave 4 — QA:** automated play tests, visual review, performance pass, honest feature matrix, final report.

Each wave is followed by an integration pass (boot, parse check, scripted tests, screenshots) and a Git commit.

## How to run

Open the folder in Godot 4.7.2 and press **F5**, or:

```powershell
& 'W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe' --path 'G:\YouTube\Fable 5.2 Effort Test GTA\Ultracode'
```

Automation (agents/QA) must use `tools\godot.ps1` (single instance, hard time limits, FPS cap, GPU gate).

## GPU / stability log

- 2026-11-09 22:13 — first headless + windowed smoke runs through the wrapper; GPU 1 % / 30 % VRAM before launch. No incidents.

## Architecture (summary)

- Contract: `docs/ARCHITECTURE.md` (+ `ARCHITECTURE_WAVE2.md`); per-module docs in `docs/*.md`
  (WORLD, CITY, DRESSING, ENVIRONMENT, PLAYER, CHARACTERS, VEHICLES, AIRCRAFT, BIKES_BOATS, WEAPONS,
  FX, UI, AUDIO, TRAFFIC, AI, WANTED, POLICE, SHOPS, GARAGE, ADMIN, WILDLIFE, EMERGENCY, TRANSIT,
  ACTIVITIES, SAVE, SKILLS ...). Integration notes: `docs/INTEGRATION_WAVE1.md`, `INTEGRATION_WAVE2.md`.
  Open defects: `docs/QA_BACKLOG.md`.
- Boot: `gta/scenes/bootstrap/main.tscn` → autoloads (InputSetup, EventBus, Settings, Registry, Game,
  WorldClock, Weather, Audio, Fx, Wanted, Skills, SaveSystem, UI, TestHarness) → world systems from
  `gta/code/core/boot_manifest.gd` (world, environment, city, interactions, vehicles, pickups, props,
  traffic, peds, police, emergency, wildlife, shops, garage, transit, taxi, activities, radio,
  ambience, respawn, debug) → player → free roam. Systems with script errors are skipped.
- Everything world-related is generated in code from data (no hand-made level scene): terrain, roads,
  lanes, lots, city placement from Blender building manifests, MultiMesh dressing, navigation.
- Layout: `gta/code/<module>/`, `gta/generated/models|audio|vfx/`, `gta/scenes/`, `gta/resources/`,
  `gta/tests/` (TestHarness tests, `--test=<name>`).

## Blender asset workflow

`tools/blender/gta_bl.py` (shared helper: collections, palette materials, bmesh builders, previews,
validation, GLB export, save) + one builder module per asset family in `tools/blender/assets/`, all
executed through the verified MCP connection (`blender-gta-ultracode`, localhost:9882) against the
master file. Visual QA = Workbench contact sheets in `qa/blender_previews/` that agents opened and
inspected; exports go to `gta/generated/models/<category>/`; Godot import checked with
`gta/code/editor/print_scene_tree.gd`. No external or AI-generated assets were used.

## Controls / systems / known limitations

See `FABLE_5.2_FINAL_REPORT.md` (controls, systems, regions, rosters) and `FEATURE_MATRIX.md`
(per-feature status). Session interruptions: two Fable usage-limit stops and one user pause (logged in
`.fable-5.2-gta-runs/run-20261109-215759/segments.txt`); from 05:49 on 2026-11-10 the session model was
claude-opus-5-5. The final QA wave was skipped at the user's request.

- 2026-11-10 12:20 — another benchmark session's uncapped windowed Godot overlapped with one of our
  capped screenshot runs (GPU 96–99 % for ~1 min, VRAM 8.1/12 GB, no device loss). The wrapper's gate
  was tightened to start windowed runs only at ≤ 65 % GPU (peak of 3 samples).
