# Feature matrix — Port Cinder (Fable 5.2 Godot GTA benchmark, Medium)

Status values: `WORKING` (functional in-game path, exercised by an automated scenario or screenshot check unless noted),
`PARTIAL`, `NOT IMPLEMENTED`. "auto" = covered by `tools/run_test.ps1 <scenario>`.

| Feature | Status | Notes |
|---|---|---|
| Launch straight into free roam, no missions | WORKING | Spawns inside the safehouse; no quests, markers or story |
| Compact ~600×600 m map with 7+ districts | WORKING | Downtown, Civic North, Larkspur, Signal Hill, Ironside, Southshore/beach/docks, Westwood, Rustyard, airfield |
| Road network, arterial avenues, fast ring, intersections | WORKING | 5×5 grid, generated markings and crosswalks |
| Traffic signals | WORKING | 9 signalled intersections; AI obeys them |
| Third-person player (walk/run/sprint/jump/crouch) | WORKING | auto: basic |
| First-person toggle (V) | WORKING | On foot and in vehicles; not screenshot-verified |
| Camera orbit, collision, shoulder aim, FOV, shake, recoil | WORKING | SpringArm3D rig |
| Blender-authored rigged player model | WORKING | 13-bone armature, rigid skinning, procedural animation |
| Procedural animation set | WORKING | walk/run/crouch/aim/melee/reload/swim/climb/sit/parachute/cower etc. |
| Ragdoll / death | PARTIAL | Procedural tumble + limp pose, not physical bones |
| Cover system (attach, slide, low/high, aim out, blind fire) | WORKING | auto: misc. Corner rounding (Shift+A/D at an edge) is implemented but untested |
| AI use of cover | PARTIAL | Officers crouch and tuck behind their own vehicle while reloading |
| Stealth mode, noise, detection modifiers | WORKING | auto: misc |
| Stealth takedown | WORKING | auto: misc |
| Suppressor affects detection | WORKING | Noise radius ×0.25 feeds witness/police logic |
| Vault / mantle | WORKING | auto: misc; also used to climb out of water |
| Ladders | WORKING | auto: misc (warehouse roofs) |
| Dodge roll (Space while aiming) | PARTIAL | Implemented, not auto-tested |
| Fall damage / landing | WORKING | Hard falls ragdoll |
| Melee: light, heavy/kick, block, melee weapons, knockdown | WORKING | auto: combat (light hit); heavy/block untested |
| Pedestrians (variants, sidewalk graph, crossing, panic, flee) | WORKING | auto: city, combat |
| NPC visual variety | WORKING | M/F bodies, 5 skin tones, hair/hat/glasses/jacket/colour variants |
| Witnesses phone the police | WORKING | auto: wanted (delayed report, can be interrupted) |
| Gang-like hostile NPCs | WORKING | Rust Hounds turf in the Rustyard; spawn auto-checked, combat not |
| Shop staff | PARTIAL | Clerks stand at storefronts; can be robbed (auto: misc) |
| Civilian traffic (lane graph, following, stopping, spawn/despawn) | WORKING | auto: city |
| Traffic lane changes | NOT IMPLEMENTED | One AI lane per direction |
| Parked vehicles | WORKING | Frozen until touched/entered |
| Honking, yielding to sirens, crash reactions | PARTIAL | Implemented; not auto-tested |
| Vehicle framework (suspension, grip, brakes, handbrake, reverse) | WORKING | auto: basic, vehicles (15 land vehicles) |
| Cars: compact, sedan, sports, muscle, SUV, pickup, van, police | WORKING | Distinct Blender silhouettes and handling data |
| Taxi, ambulance, fire engine, box truck, tactical carrier | WORKING | |
| Motorcycle, bicycle | WORKING | Stabilised 4-contact model with visual wheels |
| Speedboat, dinghy (buoyancy) | WORKING | auto: vehicles |
| Civilian helicopter | WORKING | auto: vehicles (take-off, forward flight) |
| Police helicopter | WORKING | AI air unit (auto: wanted/misc); also player-spawnable |
| Propeller airplane, jet | WORKING | auto: vehicles/plane (take-off, climb, stall behaviour) |
| Aircraft landing | PARTIAL | Physically possible; not auto-tested |
| Enter/exit, hijack occupied vehicle | WORKING | auto: misc; driver is pulled out and reacts |
| Seat-specific entry, door/trunk/hood animation | NOT IMPLEMENTED | Procedural slide-in transition only |
| Convertible roof | NOT IMPLEMENTED | |
| Drive-by shooting (pistols, SMG, grenades) | WORKING | auto: misc |
| AI shooting from vehicles | PARTIAL | Pursuit cars fire at 3★+ |
| Headlights, brake/reverse lights, horn, siren | WORKING | L / H / J |
| Vehicle damage: health, smoke, fire, explosion, wreck | WORKING | auto: combat |
| Handling damage, tyre punctures | WORKING | auto: misc (spike strip) |
| Deformation, detachable panels, broken glass | NOT IMPLEMENTED | Glass only produces impact FX |
| Vehicle repair + customisation garage (Torque Bay) | WORKING | auto: menus |
| Paint primary/secondary, finish, wheel colour | WORKING | |
| Body parts: spoilers, skirts, hood scoop, bull bar, exhaust, rims | WORKING | Blender-authored modular parts |
| Tint, lights colour, horn, plate | WORKING | |
| Liveries | NOT IMPLEMENTED | Muscle car has baked stripes only |
| Performance upgrades (engine, turbo, gearbox, brakes, suspension, armour, tyres, downforce) | WORKING | Change physics stats (auto: menus) |
| Weapons: fists, knife, bat, crowbar | WORKING | |
| Pistol, revolver, SMG, pump + auto shotgun | WORKING | |
| Assault rifle, carbine, marksman rifle, sniper (scope) | WORKING | Scope overlay not screenshot-verified |
| Grenade, rocket launcher, grenade launcher | WORKING | auto: combat (rocket) |
| Ammo, magazines, reload, recoil, spread, fire rates | WORKING | |
| Weapon wheel (Tab, slow-mo) + 1–8 / mouse wheel | WORKING | auto: combat |
| Weapon attachments & tints (suppressor, ext. mag, flashlight, optic, grip) | WORKING | auto: menus (purchase + effect data) |
| Headshots / damage zones | PARTIAL | Height-based head multiplier |
| Impact FX per surface, decals, tracers, muzzle flash | WORKING | |
| Penetration | PARTIAL | Through light dynamic props only |
| Wanted system 0–5 stars | WORKING | auto: wanted |
| Witness / visibility based crime detection | WORKING | Unwitnessed crimes are ignored |
| Pursuit vs search, last known position, search radius, LOS | WORKING | Stars blink and radar shows cones/radius in search |
| Losing wanted level by breaking line of sight | WORKING | auto: wanted |
| Vehicle / appearance change bonus while unseen | PARTIAL | Implemented, not auto-tested |
| Police dispatch by level, patrol response | WORKING | Cars 1–5★, tactical 4–5★ |
| Police on foot: arrest at 1★, lethal 2★+ | WORKING | |
| Roadblocks (3★+) and spike strips (4★+) | WORKING | auto: misc |
| Police helicopter support (3★+), gunfire (4★+) | WORKING | Presence auto-tested; gunfire not |
| PIT / ramming / boxing-in | PARTIAL | Steering heuristics; not verified in play |
| Officers commandeering civilian cars | NOT IMPLEMENTED | |
| BUSTED outcome | WORKING | auto: wanted |
| Death / hospital respawn | WORKING | Not auto-tested end to end |
| Physics props, knock-over street furniture, explosive barrels | WORKING | |
| Hydrant geysers, chain explosions | PARTIAL | Implemented, unverified |
| Weapon shop + workbench | WORKING | auto: menus |
| Clothing store, wardrobe, barber, accessories | WORKING | auto: menus (clothes) |
| Tattoo shop | NOT IMPLEMENTED | Building sells accessories instead |
| Food, market, hospital, gas station, vending, ATM | WORKING | |
| Economy (cash, purchases, loot, pickups, daily dividend, robbery) | WORKING | |
| Safehouse (interior, wardrobe, bed/sleep, save) | WORKING | auto: misc (sleep) |
| Home garage vehicle storage (persistent) | WORKING | auto: menus |
| Phone (taxi, map, photo mode, save, vehicle delivery, radio) | WORKING | Photo mode not auto-tested |
| Vehicle access terminals (land / air / water) | WORKING | Parking garage, airfield, marina |
| Day/night cycle, street lights, lit windows, headlights | WORKING | screenshots: look |
| Weather: clear, cloudy, rain, fog, storm | WORKING | Rain lowers tyre grip |
| Wet-looking surfaces / reflections | NOT IMPLEMENTED | |
| Minimap, full map, waypoint, GPS route | WORKING | |
| Taxi passenger rides with skip | WORKING | auto: extras |
| Monorail you can board and ride | WORKING | auto: extras |
| Parachute | WORKING | auto: extras |
| Diving, breath, scuba, underwater props/wrecks | WORKING | auto: extras |
| Wildlife (deer, rabbits, cows, dogs, gulls, fish, sharks) | WORKING | Spawn auto-checked; shark attack untested |
| HUD (health, armour, ammo, weapon, stars, money, radar, speed) | WORKING | |
| Audio (all synthesised) | WORKING | Not audible in automated runs; simple timbres |
| Radio stations (4) | WORKING | Procedural loops |
| Emergency services (ambulance, fire engine) | PARTIAL | Dispatch auto-tested; full arrive/work/leave cycle not verified |
| Save / load | WORKING | auto: menus |
| Benchmark / debug menu (F1) | WORKING | Every item required by the spec is present |
| Character skills (7 stats) | WORKING | Effects wired into stamina, recoil, melee, stealth, grip, flight, breath |
| Shooting range activity | WORKING | auto: extras |
| Stunt jumps, time trial, boat race, parachute target | PARTIAL | Implemented, not auto-tested |
| Runtime navigation mesh | WORKING | Baked on a thread at startup; used by police/crews |
| LOD strategy | PARTIAL | Importer mesh LODs, visibility ranges, MultiMesh vegetation; no hand-made LOD meshes |
| Interiors | PARTIAL | Safehouse, garage bay, hangar only |
| Elevators / automatic doors | PARTIAL | Roof elevator is a teleport; no animated doors |
| Controller support | PARTIAL | Bound but untested |
