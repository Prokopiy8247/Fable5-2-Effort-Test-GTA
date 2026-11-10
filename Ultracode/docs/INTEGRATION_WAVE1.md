# Integration notes after Wave 1

Written by the lead on 2026-11-10 after the first playable vertical slice was verified.

## What runs now

`res://gta/scenes/bootstrap/main.tscn` boots straight into free roam (~2.4 s headless) with these
world systems from `BootManifest`: `world`, `environment`, `vehicles`, `pickups`, `radio`,
`ambience`, plus the player (`scenes/characters/player.tscn`). All 211 scripts parse.

Lead integration test (real systems, gameplay camera screenshots):

```powershell
tools\godot.ps1 -Mode headless -Frames 3000 -TimeoutSec 240 -UserArgs '--test=int_slice','--test-timeout=200'
tools\godot.ps1 -Mode window   -Frames 2400 -TimeoutSec 300 -UserArgs '--test=int_slice','--test-timeout=220'
```

It walks downtown, equips and fires the assault rifle, spawns the sports car, enters it, drives,
switches to night, exits, tours hill / beach / marina / industrial / airport / residential, sets
3 wanted stars and opens the map. Screenshots: `qa/screenshots/int_*.png`. PASS (9 checks).

Verified look: HUD (money, health, clock, district, minimap, weapon/ammo, speedometer), sky,
clouds, sun, night sky with stars, roads / markings / sidewalks / plazas, terrain, ocean, player
model + procedural animation + aim pose, sports car with lights and exhaust puffs.

## What the city still lacks (Wave 2 must fix — this is the most visible gap on video)

- **No buildings yet**: the 182 lots are empty paved slabs. `city_builder.gd` does not exist.
  Manifests ready: `models/buildings/manifest_generic.json` (30 buildings) and
  `manifest_landmarks.json` (18 landmarks incl. airport_hangar, airport_tower, lighthouse,
  tram_stop, radio_mast, pier_straight / pier_end / pier_ramp).
- **No street furniture, signals, lamps or vegetation**: `prop_system.gd` does not exist. Signal Hill
  is a bare green dome. WORLD now provides nature placement kinds (below).
- No traffic, pedestrians, police units, shops, garages, respawn flow or admin menu yet.

## Module docs (read the ones you touch)

`WORLD.md, ENVIRONMENT.md, PLAYER.md, CHARACTERS.md, VEHICLES.md, VEHICLE_KIT.md,
VEHICLES_CARS_B.md, VEHICLES_SERVICE.md, BIKES_BOATS.md, AIRCRAFT_ASSETS.md, WEAPONS.md,
WEAPON_ASSETS.md, FX.md, UI.md, AUDIO.md, BUILDING_KIT.md, LANDMARKS.md, LANDMARKS_INFRA.md,
PROPS_STREET.md, NATURE_ANIMALS.md, MISC_PROPS.md` — plus `ARCHITECTURE.md` and
`ARCHITECTURE_WAVE2.md`.

## Facts worth knowing (collected from the Wave 1 reports)

- **WORLD**: `get_spawn_kinds()` returns 32 kinds. New nature kinds (origin on the ground, random
  yaw): `tree_hill` 127, `tree_wild` 41, `tree_palm` 30, `tree_park` 21, `bush` 95, `rock` 47,
  `ground_cover` 708, `reef` 163 (on the seabed). Suggested assets: tree_hill → tree_pine_a/b,
  tree_broadleaf_a/b; tree_wild → tree_broadleaf_*, tree_dead; tree_palm → palm_a/b;
  tree_park → tree_broadleaf_c, tree_small_a; bush → bush_a/b/c; rock → rock_a..e (cliff_chunk on
  the shore band); ground_cover → grass_tuft_a/b, fern, flower_patch_a/b (MultiMesh,
  visibility_range_end ≈ 60 m); reef → coral_a/b/c, kelp_a, seashell, starfish.
  `WorldLayout.FOOTPATHS` are drawn as ribbons. The navmesh is a cached Recast bake; pedestrians
  should use `WalkGraph`. `rooftop_helipad` is provisional until the city builder calls
  `set_location`.
- **WORLD already builds procedural marina piers** (`world_citymesh._piers()`). The landmark pier
  GLBs cover the same place: the city builder must not place them on top (lead decision: keep the
  procedural piers; use the GLB pieces only where no procedural pier exists).
- **Infra landmark positions** (from the landmark artist): lighthouse at (8, 274), radio mast at
  (229, −131.5) on `hill_top`, tram stops at `tram_stop_1..3`, hangar / tower on their airport
  lots. The radio mast and the pier-end swim ladder carry `Ladder_Bottom` / `Ladder_Top` markers:
  turn them into `ladder` group nodes (ARCHITECTURE_WAVE2 W2.4).
- Landmark GLBs contain extra nodes on purpose (`Building_Interior`, `separate_objects` such as
  `Pump_1..4`, `Door_*`); `bld_check_generic.gd` flags them — ignore those warnings.
- **VEHICLES**: all 13 car GLBs pass `veh_drive` / `veh_systems` / `veh_shots`. Optional nodes the
  code handles: `Tailgate` (pickup), `Door_RearL/R` (van), `TaxiSign`, any `Col_*` hull, glass
  nested under doors, `Roof_Convertible` (sports). Tyres pop from body hits within ~0.37 m of a
  wheel centre (no wheel colliders). No skid decals.
- **PLAYER**: on foot / air / swim / vehicle / ragdoll / dead states; scuba (`give_scuba()`,
  breath × 12); walking = hold Left Alt. Cover, ladders, vault, roll, parachute, takedowns and
  melee combos are NOT player states yet (Wave 2 / 3). Known bugs to fix: an error
  `_rehome: Cannot convert argument 1 from Object to Object` when the game quits while seated in a
  vehicle; `enter_vehicle` aborts silently when the car centre is < 8 m but its door > 9 m away.
- **UI**: `UI.SCREENS` paths fixed; widget kit in `code/ui/widgets/` (see UI.md). Weapon-wheel
  glyphs are per class. Inventory API is `get_current_spread()`.
- **AUDIO**: 130 synthesized WAVs (all ids of ARCHITECTURE 6.11 + 5 radio stations ×2 loops).
  Audio is mono; nobody has listened to it (headless only).
- **Settings**: a `--max-fps` on the command line now always caps `Engine.max_fps` (GPU safety).
- Every headless run ends with the engine notice "N ObjectDB instances leaked / resources still in
  use at exit" (static caches); it is harmless and not an error of your module.
