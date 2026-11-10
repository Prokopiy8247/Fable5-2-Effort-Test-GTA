# NEON TIDE: Vesper Bay — Feature Matrix

Status values: `WORKING` (implemented and verified by an automated scenario and/or screenshots), `PARTIAL`
(implemented with a stated gap), `NOT IMPLEMENTED`. Verification scenarios are the `--gta-test=` names in
`gta/code/debug/test_scenarios.gd` (see DEVELOPMENT.md §10).

| Feature | Status | Notes |
|---|---|---|
| **Project / pipeline** | | |
| Starts directly in free roam, no missions / quests / markers | WORKING | main scene boots the world and puts the player at the safehouse |
| Blender MCP as the asset pipeline (localhost:9881, master .blend) | WORKING | 311 GLB assets authored in Python through the MCP, QA'd with `look`; see report |
| No external / downloaded / AI-generated assets | WORKING | meshes from Blender code, audio synthesised in Python, textures procedural |
| GPU safety rules (time limits, single instance, caps) | WORKING | `tools/run_godot.ps1`; V-Sync + 60 FPS cap in the game |
| Save / load (3 slots + quick save) | WORKING | `services` (save, change, load, verify) |
| Admin / benchmark menu (all §38 functions) | WORKING | `ui`, `air`, `misc`; benchmark tour `bench` |
| **World** | | |
| Compact ≈600×600 m map, 8 districts | WORKING | `world` overview shots |
| Road network, arterial, signals, sidewalks, crossings | WORKING | `traffic` |
| Landmarks and useful locations (25 Blender landmarks) | WORKING | `landmarks` |
| Building interiors | PARTIAL | the 4 shops, safehouse, Torque House and hangar have interiors; other buildings are solid |
| Vegetation, street furniture, yard / beach / pier props (126 types) | WORKING | `world`, foliage wind shader |
| Day / night cycle, street lights, lit windows, headlights | WORKING | `night` |
| Weather: clear, cloudy, rain, fog, storm (lightning) | WORKING | `ui` (admin weather), `chaos` (storm) |
| Wet roads and reduced grip in rain | WORKING | grip factor used by car physics |
| Monorail / train | NOT IMPLEMENTED | rail kit pieces exist in Blender but no train or track was built into the game |
| **Player** | | |
| Walk, jog, sprint, jump, crouch, stamina | WORKING | `walk` |
| Third-person camera, aim, vehicle chase, first-person toggle | WORKING | used in every scenario |
| Swimming, diving, breath, scuba gear | WORKING | `misc` |
| Cover system | WORKING | `moves` |
| Stealth (crouch detection, silent takedowns) | WORKING | `moves` |
| Traversal: vault, mantle, ladders, combat roll | WORKING | `moves`, `extras` (radio-tower ladder) |
| Melee: combos, heavy attacks, blocking | WORKING | `moves` |
| Physics ragdolls (death, hard hits) | WORKING | `ragdoll`; cone joints only (occasional unnatural folds) |
| Skydiving and parachute | WORKING | `moves` |
| Skills (stamina, shooting, strength, stealth, driving, flying, lung) | WORKING | grow with use, admin max / reset |
| Clothing / appearance / barber | WORKING | `shops` (preview, pay, revert) |
| **Weapons** | | |
| 17 weapons in 8 classes | WORKING | `chaos`, `shops` |
| Weapon wheel with slow motion | WORKING | `ui` |
| Attachments and finishes (gunsmith workbench) | WORKING | `shops` |
| Ballistics: penetration of thin props / glass, surface impacts | WORKING | |
| Explosives: grenades, rocket launcher, grenade launcher | WORKING | `chaos` |
| Drive-by shooting | WORKING | `extras` |
| **Vehicles** | | |
| 13 cars and service vehicles | WORKING | `roster` (all accelerate, steer, brake, stay upright) |
| Motorbike and BMX | WORKING | `roster` |
| Speedboat | WORKING | `misc` |
| Helicopters (civil, police with searchlight) | WORKING | `air`, `police` |
| Prop airplane | WORKING | `air` (takes off, climbs) |
| Jet, dinghy, police boat | NOT IMPLEMENTED | defined in the data but no Blender model was built; shown greyed out in the admin spawn menu, never spawned |
| Carjacking | WORKING | `moves` |
| Doors, lights, horn, siren, indicators | WORKING | |
| Vehicle damage: smoke, fire, explosion, glass, tyre punctures | WORKING | `chaos`, spike strips in `misc` |
| Torque House: repair, performance, body kits, wheels, paint, lights | WORKING | `shops`, `air` (mounted parts) |
| Personal vehicles, safehouse garage (4), phone delivery | WORKING | `services` |
| **Population / AI** | | |
| Pedestrians: sidewalk walkers, free-roam areas, district looks | WORKING | `peds` |
| Pedestrian reactions: panic, cower, fight back, witnesses call police | WORKING | `peds`, `police` |
| Traffic AI: lanes, signals, junction reservations, overtaking | WORKING | `traffic`, `traffic_soak` (2 min, no gridlock) |
| Traffic yields to sirens | WORKING | |
| Combat AI | PARTIAL | positioning, crouching, bursts, flanking strafes; no cover-graph search |
| Emergency services: ambulance and fire engine | WORKING | `services`, `misc` |
| Wildlife: gulls, dogs, cats, deer, rabbits, coyotes, fish, shark | WORKING | `extras` |
| Simulation tiers / streaming | WORKING | NPC tiers, parked-car streaming, despawn out of sight |
| **Police / wanted** | | |
| Wanted level 0–5 from witnessed crimes only | WORKING | `police` |
| Pursuit vs search, search area, cool-down | WORKING | `police` |
| Busted / arrest | WORKING | `police` |
| Patrols, response units, dismount, fight, search on foot | WORKING | `police`, `chaos` |
| SWAT trucks, roadblocks, spike strips | WORKING | `misc` |
| Police helicopter | WORKING | `police` |
| Disguise: respray breaks the description | WORKING | Torque House paint while unseen |
| **Economy / services / activities** | | |
| Cash, NPC drops, pickups, hidden stashes, underwater treasure | WORKING | `shops` |
| Weapon shop, clothing, barber, market | WORKING | `shops`, `landmarks` |
| Store robbery | WORKING | clerks empty the till, silent alarm |
| Safehouse: sleep, save, wardrobe, garage | WORKING | |
| Phone: taxi, vehicle delivery, emergency line, camera, map | WORKING | `ui` |
| ZipCab taxi (call, hail, ride, skip) | WORKING | `services` |
| Stunt jumps (4, slow motion) | WORKING | `services`, `roster` |
| Shooting range (4 timed challenges, medals) | WORKING | `services` |
| Races / other hobbies | NOT IMPLEMENTED | not required by the spec |
| **UI** | | |
| HUD: health, armour, cash, stars, weapon, ammo, speed, altimeter | WORKING | |
| Minimap, full map, waypoint, GPS route | WORKING | `ui` |
| Pause, settings, stats, controls, save / load menus | WORKING | `ui` |
| Photo mode | WORKING | `moves` |
| Controller support | PARTIAL | gamepad bindings exist for most actions; not tested with a pad |
| **Audio** | | |
| 174 synthesised sounds (weapons, characters, vehicles, UI, world) | WORKING | `audio` |
| Engine pitch by RPM, sirens, rotors, skids | WORKING | |
| Ambience beds by place / time | WORKING | `audio` |
| Radio: 5 original stations | WORKING | `audio` |
| **Performance** | | |
| 60 FPS target (V-Sync cap) | WORKING | `bench`: 59.9 avg, 1% low 60 at 1600×900, `chaos`: 59.5 avg / 47 min under a 5-star firefight |
