# Feature Matrix — Cinder Bay (Godot 4.7.2 + Blender MCP)

Statuses: **WORKING** = implemented and behaves correctly in play / automated scenarios ·
**PARTIAL** = implemented with clear gaps or simplifications · **NOT IMPLEMENTED** = absent.
"Verified" in the notes means it was exercised by a scenario in `gta/code/debug/test_harness.gd` during this
session (log + screenshots in `_qa/`, not committed). Items without that note were checked by playing through code
paths / screenshots only.

| Feature | Status | Notes |
|---|---|---|
| **Core** | | |
| Godot 4 project, Forward+ renderer, launches straight into free roam | WORKING | Verified: normal launch, world built in ~1.0–1.4 s, ready in ~3.5–4.3 s |
| Missionless sandbox (no missions / quests / objective markers) | WORKING | Only player-started optional activities exist |
| Blender MCP asset pipeline (project-bound `blender-gta-extra`, port 9880) | WORKING | 35 GLBs exported from `GodotFable5.2GTAExtra.blend`, all import cleanly |
| Compact ~600×600 m map with 10+ distinct regions | WORKING | City grid, docks, beach + lighthouse island, airport, hill, sea floor |
| LOD / visibility ranges / simulation tiers | WORKING | LOD1 meshes for vehicles + characters, MultiMesh props with visibility ranges, NPC/traffic tiers + despawn, parked cars freeze when settled |
| World-sector streaming | PARTIAL | District chunks are built once at start and culled by distance; no runtime load/unload |
| NavigationRegion3D / navmesh for pedestrians | NOT IMPLEMENTED | Pedestrians use a generated sidewalk/crosswalk graph + steering instead |
| Reusable `.tscn` prefab scenes | NOT IMPLEMENTED | Scenes are assembled at runtime from GLB PackedScenes + data tables |
| Save / load (money, inventory, mods, skills, looks, garage, position, time) | WORKING | Verified round-trip (F5/F9, safehouse bed) |
| Admin / benchmark menu (F1) | WORKING | Teleports, every vehicle, weapons/ammo/attachments, money, health/armor, 0–5 stars, spawn police/gang, time & weather, repair/customise/flip vehicle, parachute, scuba, lung refill, skills max/reset, taxi, toggles (god, traffic, peds, wildlife, FPS, coords, all mods) |
| **Player** | | |
| Walk / run / sprint / jump / crouch | WORKING | Verified |
| Third-person aiming & shooting with recoil, spread, reload | WORKING | Verified |
| First-person camera toggle (V) | PARTIAL | Works as a camera mode; no dedicated first-person arms/animations |
| Cover system (enter, low/high, slide, peek-aim, blind fire) | WORKING | Verified entering low cover + peek-aim; sliding/blind fire not auto-tested |
| Stealth (crouch noise reduction, awareness, takedowns) | WORKING | Verified stealth takedown; detection model is a simple awareness value |
| Climb onto ledges / low walls | WORKING | Verified (0.77 m sandbag wall); no separate vault-over animation |
| Ladders | WORKING | Verified quay ladder |
| Combat roll | WORKING | Space while aiming + direction; not auto-tested |
| Melee (fist combos, knife, bat, crowbar, nightstick, heavy attack) | WORKING | Verified bat hit (100 → 61 hp) |
| Swimming, diving, breath meter, scuba gear | WORKING | Verified |
| Parachute (deploy, steer, flare, cut away) | WORKING | Verified 120 m drop, clean landing in 14.8 s |
| Ragdoll | PARTIAL | "Ragdoll-lite": tumbling single rigid body carrying a limp pose, no per-bone physics |
| Health, armor, death → hospital, fees | WORKING | Verified |
| Skill progression (stamina, shooting, strength, stealth, driving, flying, lung) | WORKING | Gains from use, affect handling/melee/breath/aim; stats screen (P) |
| Clothing, hair/beard, barber, wardrobe | WORKING | Shop menus with live preview |
| **NPCs** | | |
| Pedestrian population with varied looks | WORKING | ~26 walking peds near the player, density scales with time/weather |
| Reactions: flee, cower, investigate, phone police, fight back | WORKING | Witness calls verified |
| Shop clerks | WORKING | React to robbery/gunfire |
| Gang members (Ironworks / Docks) | WORKING | Hostile when provoked |
| Police / SWAT on foot, combat AI with cover-seeking | WORKING | Verified arrests, gunfights |
| AI simulation tiers | WORKING | Near / medium / far tiers, despawn outside view |
| **Traffic** | | |
| Lane-graph traffic with turns & intersections | WORKING | Verified: 7–13 moving cars, none off-road or flipped |
| Traffic signals obeyed by AI | WORKING | Verified stops at red |
| Parked cars at kerbs / lots / police & hospital bays | WORKING | |
| Yield to sirens | WORKING | Not auto-tested |
| **Vehicles** | | |
| Cars: compact, sedan, sports (convertible), muscle, SUV, pickup, van, taxi, box truck | WORKING | Verified driving |
| Emergency: police cruiser, ambulance, fire engine, SWAT van | WORKING | Sirens + lights |
| Motorcycle, bicycle | WORKING | Verified; riders fall off in hard crashes |
| Boats: speedboat, police boat | WORKING | Verified buoyancy and 12.8 m/s |
| Helicopters: utility, police | WORKING | Verified take-off / 23 m/s cruise |
| Airplanes: Skylark (prop), Stiletto (jet) | WORKING | Verified Skylark take-off and climb to 54 m; jet not auto-tested |
| Enter / exit, seats, passengers, doors | WORKING | |
| Carjacking | WORKING | Verified |
| Drive-by shooting | WORKING | Verified 12–13 SMG shots while driving |
| Headlights, horn, siren, convertible roof, radio | WORKING | |
| Vehicle damage: smoke, fire, explosion, burnt wreck, tyre popping | PARTIAL | No body deformation or detachable panels |
| Road vehicles flood in deep water | WORKING | Verified (engine dies, occupants bail out) |
| Cosmetic customisation (21 slots: spoiler, bumpers, hood, roof, grille, skirts, exhaust, livery, wheels, tint, lights, horn, plate… + paint & finishes) | WORKING | Verified visual parts |
| Performance customisation (engine, turbo, transmission, brakes, suspension, armor, tyres) | WORKING | Verified effect (+5 % speed after 5 s with engine 3 / turbo / transmission 2) — modest |
| Repair (mod shop, admin) | WORKING | |
| Personal garage (store / retrieve with mods) + mechanic delivery (phone) | WORKING | Verified store → retrieve keeps mods |
| **Weapons** | | |
| 17 weapons + fists across 8 slots (melee, handguns, SMG, shotguns, rifles, sniper, heavy, thrown) | WORKING | |
| Bullet impacts, surface FX, vehicle/tyre hits, headshots | WORKING | |
| Explosives: RPG, grenade launcher, frag grenades, molotov fire zones | WORKING | Verified explosion / fire VFX |
| Weapon attachments (suppressor, flashlight, optic, grip, extended mag) + tints | WORKING | Verified suppressor + ext. mag (mag 20) |
| Weapon wheel | WORKING | Verified |
| Gun shop, ammo, workbench | WORKING | |
| **Wanted / police** | | |
| 0–5 star wanted levels with escalating response | WORKING | Verified 1 → 5 stars |
| Witnesses phone it in (can be interrupted) | WORKING | Verified |
| Line of sight, pursuit vs search state, escape timer only while unseen | WORKING | Verified escape after ~24 s hidden |
| Police car pursuit + officers dismounting | WORKING | |
| PIT / box-in tactics | PARTIAL | Implemented, not verified in tests |
| Roadblocks + spike strips (3+ / 4+ stars) | WORKING | Verified roadblock and blown tyres |
| Police helicopter with searchlight (3+ stars) | WORKING | Verified at 4 stars |
| SWAT vans / tactical units (4–5 stars) | WORKING | Verified 2 vans at 5 stars |
| Changing vehicle / outfit helps escape | WORKING | Escape timer multipliers; not separately tested |
| Busted → police station, bail fee | WORKING | Verified |
| Police boats dispatched on water | NOT IMPLEMENTED | Police boat is drivable only |
| **World & services** | | |
| Day / night cycle with lit windows, street lamps, headlights | WORKING | |
| Weather: clear, cloudy, rain, fog, storm (wet roads, lightning, grip) | WORKING | |
| Physics props (lamps, hydrants, bins, signs…) knocked over by vehicles | WORKING | Verified street lamp |
| Shops: store, clothes, barber, gun shop, mod shop, ATM | WORKING | |
| Safehouse (bed = save + skip time, wardrobe, garage) | WORKING | |
| Smartphone (taxi, mechanic, paramedics, waypoint, photo mode, save, radio) | WORKING | |
| Minimap, full map, waypoint + GPS route | WORKING | Verified |
| Taxi service (call, ride, skip trip, fare) | WORKING | Verified |
| Elevated train (board / ride / leave at stations) | WORKING | Verified 48 s ride |
| Wildlife (deer, boar, cow, coyote, rabbit, dogs, cats, birds, fish, sharks) | WORKING | Verified populations |
| Emergency services (ambulance to casualties, fire engine to explosions) | WORKING | Verified both arrive and crews deploy |
| Interiors | PARTIAL | Shop counters + safehouse room; most buildings closed |
| Underwater exploration (wreck, chests, kelp, fish) | WORKING | |
| **Presentation** | | |
| HUD (health, armor, breath, money, ammo, stars, speed, prompts, notifications) | WORKING | |
| Camera (orbit, aim zoom, vehicle chase, look back, shake) | WORKING | |
| VFX (muzzle flash, tracers, impacts, sparks, dust, splashes, explosions, fire, smoke, tyre smoke) | WORKING | Verified after the pooled-emitter rewrite |
| Procedural audio (weapons, engines, sirens, impacts, ambience) | WORKING | All sounds synthesised in code |
| Radio (5 procedural stations) | WORKING | |
| Pause, settings, controls, stats screens | WORKING | |
| Gamepad support | PARTIAL | Core actions bound; not tested on hardware |
| **Optional activities** | | |
| Shooting range challenge | WORKING | Verified start |
| Stunt jumps (5 named) | WORKING | Verified "Eastside Air" and "Runway Rocket" rewards |
| Ring-road time trial | WORKING | Start verified; full lap not auto-tested |
| **Performance** | | |
| Frame rate at 1280×720 (RTX 5070, 60 fps cap) | PARTIAL | 45–60 fps in town, ~43–58 fps in a 4-star chase with ~75 vehicles; short frame-time spikes when many NPCs / vehicles spawn |
