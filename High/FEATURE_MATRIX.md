# Feature matrix — Marlow Bay (Godot 4.7.2)

Status rule: `WORKING` = has an in-game path **and** was exercised in a scripted run of the real game
(see `tools/run_godot.ps1`). `PARTIAL` = simplified, or implemented but not exercised/visually verified.
`NOT IMPLEMENTED` = absent.

| Feature | Status | Notes |
| --- | --- | --- |
| Launch straight into free roam, no missions | WORKING | Spawns in the safehouse with control; 0 mission/quest nodes |
| ~600×600 m map with 8 districts | WORKING | Downtown, Midtown, Palm Court, Ironworks, Bayfront, Port, Signal Hill, Airfield |
| Road network, arterial, intersections | WORKING | 29 nodes, 4-lane expressway + avenue, shader lane markings, crosswalks |
| Traffic signals | WORKING | Phased per intersection, AI obeys, lamp meshes switch |
| Civilian traffic (lane graph, following, stopping) | WORKING | Up to 14 ambient cars, spawn/despawn around player, night scaling |
| Lane changes | NOT IMPLEMENTED | Lane chosen only at intersections |
| Parked vehicles | WORKING | Kerb, lots, driveways; frozen until approached |
| Honking / yielding to sirens / stuck recovery | PARTIAL | Implemented; not individually verified |
| Pedestrians on sidewalks, crossings | WORKING | Sidewalk graph, wait for traffic, dodge cars |
| Pedestrian panic / cower / flee | WORKING | Reacts to aiming, gunfire, explosions (seen in combat run) |
| Witnesses calling police | PARTIAL | Phone-call state + delayed report implemented; not isolated in a test |
| Navigation mesh | WORKING | Baked NavigationMesh (5,573 polys), NavigationServer path queries for chase/flee |
| NPC variety (male/female, clothes, skin, hair, police, tactical, gang, staff) | WORKING | Verified in line-up screenshot |
| Player: walk/run/sprint/jump/crouch | WORKING | CharacterBody3D + stamina |
| Third-person camera, orbit, collision, shoulder aim | WORKING | SpringArm3D rig, FOV changes, shake, recoil recovery |
| First-person toggle (foot + vehicle) | PARTIAL | Implemented (V); not visually verified |
| Procedural character animation + weapon IK | WORKING | Locomotion, aim, sit, swim, climb, chute, melee poses |
| Ragdoll / knockdown | PARTIAL | Tumbling body with limp pose, not per-bone physics |
| Cover system | PARTIAL | Attach/slide/aim-out/blind-fire/corner wrap coded; only attach verified |
| Stealth mode + takedown | PARTIAL | Noise radius, sight modifiers, rear takedown coded; lightly tested |
| Vault / mantle | PARTIAL | Implemented; not covered by a run |
| Ladders | WORKING | 11 roof ladders; climb verified |
| Dodge roll while aiming | PARTIAL | Implemented; not covered by a run |
| Melee (light, heavy, block, weapons, knockdown) | PARTIAL | Light hit verified; heavy/block not verified |
| Firearms: pistol, heavy pistol, SMG, 2 shotguns, 2 rifles, marksman, sniper | WORKING | Hitscan, spread, bloom, recoil, reload, tracers, headshots |
| Rocket launcher, grenade launcher, grenades, fire bottles | WORKING | Projectiles + explosions + fire patches verified |
| Sniper scope overlay | PARTIAL | Implemented; not visually verified |
| Weapon wheel | WORKING | Hold Tab, slow motion, 8 classes |
| Weapon attachments + finishes | WORKING | Purchase path verified; visible parts; gameplay effects coded |
| Ballistic impacts (sparks, dust, decals, glass) | WORKING | Pooled particles + decals |
| Bullet penetration | NOT IMPLEMENTED | |
| Enter / exit vehicles | WORKING | Door transition, exit placement |
| Carjacking occupied vehicles | WORKING | Driver pulled out as NPC, flees or fights |
| Cars (8 civil + taxi) | WORKING | Raycast suspension, grip model, handbrake, damage |
| Police cruiser, tactical van, ambulance, fire engine, box truck | WORKING | Distinct Blender models and handling |
| Motorcycle | WORKING | AI-ridden in traffic; balance torque + lean |
| Bicycle | PARTIAL | Implemented; not ridden in a run |
| Speedboat / patrol boat | WORKING | Buoyancy points, 56 km/h verified |
| Helicopters (civil + police) | WORKING | Take-off, forward flight, altitude hold verified |
| Prop plane | WORKING | Take-off and climb verified; stall nose-drop coded |
| Jet | PARTIAL | Same flight model; not flown in a run |
| Vehicle lights, brake lights, horn, siren | PARTIAL | Implemented; auto headlights at night |
| Doors opening | PARTIAL | Hinged door skins during entry |
| Convertible roof, trunk/hood | NOT IMPLEMENTED | |
| Drive-by shooting | PARTIAL | Implemented for pistols/SMG/throwables; not covered by a run |
| Vehicle damage, smoke, fire, explosion, chain reactions | WORKING | Explosion + ejection verified |
| Tyre puncture, broken glass | PARTIAL | Implemented; not isolated in a test |
| Vehicle customisation + repair garage | WORKING | All 103 option paths exercised; parts/paint/rims visible; performance multipliers |
| Liveries | NOT IMPLEMENTED | |
| Wanted level 0–5 | WORKING | Heat thresholds, HUD stars |
| Pursuit vs. search, last-known position, escape | WORKING | Escape after 17 s unseen at 1 star verified |
| Police on foot + cruisers + crew dismount | WORKING | Seen at 2 and 4 stars |
| Arrest / BUSTED | WORKING | Verified with respawn at station |
| Tactical units, police helicopter | PARTIAL | Spawn verified; behaviour not visually verified |
| Roadblocks, spike strips, PIT / ramming | PARTIAL | Implemented; roadblock did not trigger in the test window |
| Vehicle / appearance change helps evasion | PARTIAL | Halves detection range while unseen; not isolated |
| Death, hospital respawn, bill | WORKING | Verified |
| Swimming, diving, breath, drowning | WORKING | Verified; underwater fog tuned afterwards |
| Scuba gear | PARTIAL | Pickup + long breath coded |
| Parachute | WORKING | Deploy, steer, glide verified |
| Taxi passenger service | PARTIAL | Call + arrival verified; full ride/skip not completed in a run |
| Monorail (Skyline) | WORKING | Board, ride, get off verified |
| Wildlife (deer, boar, cows, dogs, gulls, fish, sharks) | PARTIAL | Spawning verified (13 active); flee/attack not verified |
| Emergency services (ambulance, fire engine) | PARTIAL | Implemented; not observed in a run |
| Weapon shop (interior + clerk) | WORKING | Weapons, ammo, armour, parachute, attachments, finishes |
| Store robbery | PARTIAL | Aim at clerk for cash; not covered by a run |
| Clothing store / wardrobe | WORKING | Colours, sleeves, jacket, shorts, hat, eyewear, body type |
| Barber | WORKING | Hair, hair colour, facial hair, skin tone |
| Food / health purchases, hospital treatment | WORKING | |
| Safehouse (save, sleep, wardrobe, garage) | WORKING | Vehicle store/retrieve verified |
| Phone | PARTIAL | Menu and actions built; not exercised end to end |
| Economy (cash, drops, pickups, fines) | WORKING | |
| Day/night cycle, street lamps, lit windows | WORKING | |
| Weather: clear, cloudy, rain, fog, storm | WORKING | Wet roads, rain, lightning, reduced grip |
| HUD (health, armour, ammo, stars, money, speed, minimap) | WORKING | |
| Full map, waypoint, GPS route | PARTIAL | Map + waypoint verified; route line not checked |
| Audio (72 synthesised clips, ambience mixer) | PARTIAL | Playback wired; not auditioned |
| Radio (4 original stations) | PARTIAL | Station switching verified by HUD toast only |
| Save / load | WORKING | JSON, verified round trip |
| Benchmark / admin menu (F1) | WORKING | All required actions present |
| Character skills (7) | PARTIAL | Gain + effects coded, shown in pause menu |
| Shooting range | PARTIAL | Start verified; scoring not completed |
| Time trial, stunt jumps, precision landing | PARTIAL | Implemented; not completed in a run |
| LODs | PARTIAL | Importer auto-LOD, visibility ranges, AI tiers; no hand LODs |
| Interiors beyond three buildings, elevators, automatic doors | NOT IMPLEMENTED | |
| Tattoo shop | NOT IMPLEMENTED | |
| Controller support | PARTIAL | Basic bindings, untested |
| Reusable `.tscn` scenes per entity | NOT IMPLEMENTED | World and entities are assembled in code from GLBs |
