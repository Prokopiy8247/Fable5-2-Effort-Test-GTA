# Feature Matrix — Halcyon Bay

Statuses: `WORKING` = a functional in-game path was exercised by an automated test and/or an in-game
screenshot during development. `PARTIAL` = implemented, but only partly verified or with known gaps.
`NOT IMPLEMENTED` = absent. Evidence: `gta/tests/*.gd` (run through `tools/godot.ps1`), module docs in
`docs/`, screenshots in `qa/screenshots/`. The final QA wave (Wave 4) was **not run** because the user
asked to finish early; Wave 3 agents were stopped during their last verification pass, so several
Wave 3 rows are `PARTIAL` even where most of their tests passed.

| Feature | Status | Notes |
|---|---|---|
| Boots straight into free roam, no menu gate, no missions | WORKING | `int_slice` PASS (headless + window); no mission/quest code anywhere |
| Project health (parse, boot) | WORKING | 404 scripts parse (`-Mode check`, 0 fails); 60 s full headless boot: only dummy-renderer mesh RID errors from headless asset loading |
| Blender MCP pipeline (verified :9882 master file, builders, previews, GLB export, Godot import) | WORKING | ~275 asset roots in `GodotFable5.2GTAUltracode.blend`, builder code in `tools/blender/assets/` |
| 600×600 m island, 8 districts, road network, arterial ring | WORKING | `wld_api` 395 checks, `wld_ground`, district tour in `int_slice` |
| City buildings (30 generic + 18 landmarks), interiors, doors, ladders, lit windows | WORKING | `city_api` 177 checks, 23 city screenshots, night shots |
| Street furniture, traffic lights, street lamps, vegetation (wooded hill), breakables | WORKING | `prp_*` tests + review; explosive barrels, hydrants, toppling lamps |
| Day/night cycle, sun/moon, street & window lighting | WORKING | `env_cycle`, `env_shots`, `int_slice` night shot |
| Weather (clear, cloudy, rain, fog, storm, wetness, lightning) | WORKING | `env_cycle` + screenshots; reduced grip in rain via `Weather.get_grip_multiplier()` |
| Ocean, swimming, diving, breath, scuba | WORKING | `plr_move` (swim/dive/scuba), `env_waves` |
| Parachute (deploy, steer, flare, landing) | PARTIAL | Implemented in Wave 3 (`player_parachute.gd`); agent stopped before its final test pass |
| Shipwreck exploration / treasure | PARTIAL | Wreck + reef placed; treasure pickup coded in Wave 3, not finally verified |
| Third-person player, walk/run/sprint/jump/crouch, camera collision, aim | WORKING | `plr_move` 120 checks, `plr_camera` 70 |
| First-person camera toggle | WORKING | `plr_camera` |
| Procedural humanoid animation (shared by player + NPCs), ragdoll | WORKING | `plr_anim_shots`, `chr_lineup` 91 checks |
| Traversal: vault, mantle, ladders, roll | WORKING | `plr2_traversal`; leaning-ladder fix from Wave 3 not finally verified |
| Melee combos, heavy attack, block, knock-down | WORKING | `plr2_melee` |
| Cover system (low/high, move, peek, blind fire, corners) | WORKING | `plr3_cover` |
| Stealth mode and takedowns | WORKING | `plr3_stealth`; AI double-counts stealth in awareness (tuning issue) |
| Weapons: 17 types incl. melee, handguns, SMG, shotguns, rifles, sniper scope, grenade, RPG, grenade launcher, molotov | WORKING | `wpn_core` balance table; `int_slice` rifle fire |
| Weapon wheel, reload, recoil, spread, headshots, attachments | WORKING | `ui_api`, `wpn_core` |
| Weapon shop + workbench (attachments, tints), ammo, armour | WORKING | `shp_api` |
| Drive-by shooting | WORKING | `plr2_driveby`; in-cabin camera not tuned for van / box truck / sports car |
| Cars (13 Blender-authored classes incl. police, taxi, ambulance, fire truck, SWAT van) | WORKING | `veh_drive` 418 checks on real GLBs, `veh_systems` 129 |
| Vehicle damage, smoke, fire, explosion, glass, tyre pops | WORKING | `veh_systems` |
| Motorcycle, bicycle, speedboat, jetski, dinghy | WORKING | `bkb_bike`, `bkb_boat` |
| Helicopters (civil, police) and airplanes (prop, jet) | WORKING | `air_heli`, `air_plane` (take-off, climb, turn, stall, touchdown) |
| Carjacking (pull driver out, NPC reaction, crime report) | WORKING | `plr2_carjack` |
| Traffic (lanes, signals, following, lane changes, parked cars, density) | WORKING | `trf_flow` + review: no gridlock, 0 impacts in final runs |
| Pedestrians (wander, benches, flee, panic, witnesses, gangs) | WORKING | `ai_api`, `ai_population` |
| Wanted system 0–5 (heat, witnesses, pursuit / search / escape, busted) | WORKING | `wnt_core`, `pol_escape`; star HUD with search mode in `int_slice` screenshots |
| Police: patrols, cruisers, foot officers, SWAT, roadblocks, spike strips, PIT, arrests | WORKING | `pol_response` 6/6 runs after review; chases tested with traffic disabled |
| Police helicopter with searchlight | PARTIAL | `police_heli.gd` written and integrated in Wave 3; its test (`pol_heli`) was not finished |
| Emergency services (ambulance, fire truck) | WORKING | `emg_api` 46/46 |
| Wildlife (deer, boar, coyote, dogs, birds, fish, shark) | WORKING | `wld3_api` 70 checks, `wld3_shots` |
| Taxi service | PARTIAL | Implemented; a missing helper was fixed by the lead at the end; `trn_taxi` not run to completion |
| Tram (board, ride, stops) | PARTIAL | `trn_tram` ride path PASS; full loop re-run pending |
| Shops: clothing, wardrobe, barber, general store, robbery | WORKING | `shp_api` |
| Garages, personal vehicles, rental terminals (airport / marina / parking) | WORKING | `gar_api`; terminals print RID errors only in headless runs |
| Vehicle customisation & repair shop (paint, wheels, body parts, performance) | WORKING | `gar_api` measures performance change |
| Safehouse (sleep, save, wardrobe, garage) | WORKING | `gar_api` |
| Save / load (versioned JSON, backup, autosave, continue at boot) | WORKING | `sav_roundtrip` 74 checks |
| Character skills (7 stats, XP from activity, benefits) | PARTIAL | Wave 3 audit written; status screen shows them; not every benefit re-verified |
| Activities: shooting range, stunt jumps, street race | PARTIAL | `act_api` setup / stunt / race PASS; range course PASS in a subset run |
| HUD (health, armour, money, stars, ammo, minimap, speedo, clock, district) | WORKING | `ui_api`, `ui_shots`, `int_slice` |
| Full-screen map, waypoint, GPS route | WORKING | `ui_api`, `int_15_map.png` |
| Phone, photo mode, radio wheel | PARTIAL | Written in Wave 3; agent stopped before its screenshot pass |
| Radio stations (5 original procedural stations) | WORKING | `aud_api` |
| Audio (130 synthesized sounds: weapons, engines, sirens, ambience) | PARTIAL | All ids load (`aud_api` 97 checks); never listened to by a human |
| Admin / benchmark menu (F1) | WORKING | `adm_api`; helicopter-unit button depends on the police helicopter |
| Performance / LOD / pooling / AI tiers | PARTIAL | Per-module budgets measured; the planned whole-game perf tour (Wave 4) was not run |
| Controller support | PARTIAL | Bindings registered in `InputSetup`; not tested |
