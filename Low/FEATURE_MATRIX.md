# FEATURE MATRIX — Port Fable (Fable 5.2 GTA, Low)

Status values: WORKING, PARTIAL, NOT IMPLEMENTED. "Tested" means a scripted autotest (`gta/code/debug/autotest.gd`) exercised it; anything else was checked by reading the code path only and has not been played by hand.

| Feature | Status | Notes |
|---|---|---|
| Launch straight into free roam, no missions | WORKING | Tested (`boot`). No mission, quest or objective code exists. |
| Compact ~600×600 m map with 7 district types | WORKING | Tested (`tour` screenshots of 12 locations). |
| Blender MCP asset pipeline (GLB) | WORKING | 140 GLBs built and exported through MCP; all import without errors. |
| Third-person player: walk, run, sprint, jump, crouch | WORKING | Tested with simulated key input (`input`). |
| Camera orbit, collision, shoulder aim, vehicle chase, shake | WORKING | Orbit by mouse was not simulated; code path only. |
| First-person toggle (V) | PARTIAL | Implemented for foot and vehicles; not tested. |
| Vault / mantle | PARTIAL | Implemented with ray probes; not tested. |
| Ladder climbing | WORKING | Tested (prompt and climb state); two ladders in the world. |
| Dodge roll while aiming (X) | PARTIAL | Implemented; not tested. |
| Cover system | PARTIAL | Tested: attach and low/high detection. Sliding, peeking, corner rounding and blind fire are implemented but untested. NPC cover is limited to cops crouching behind their own car. |
| Stealth mode and stealth takedown | PARTIAL | Crouch lowers noise and police detection range; takedown from behind is implemented but untested. No suspicion meter. |
| Melee: light, heavy, block, knockdown, melee weapons | PARTIAL | Heavy bat strike with knockdown tested. Block and combo untested. |
| Procedural character animation | WORKING | Skeleton3D bones driven in code (walk, run, crouch, aim, swim, climb, sit, parachute, cower, surrender). No authored clips. |
| Ragdoll | PARTIAL | Scripted knockdown and tumble of the capsule, not physical bone ragdoll. |
| NPC pedestrians on sidewalks, crossing at signals | WORKING | Tested (`traffic`: 24 wandering). |
| NPC variants (male/female, clothing, hair, police, tactical) | WORKING | Colours and accessories randomised per NPC. |
| NPC panic, flee, cower, armed civilians | WORKING | Tested: 11–14 of 22 fled after a gunshot. Cower and armed response untested. |
| Shop staff and store robbery | PARTIAL | Implemented (hold clerk at gunpoint); not tested. |
| Gang NPCs | PARTIAL | Five hostile-on-provocation members at the gang yard; one spawned and hit in `combat`. |
| Traffic: lane graph, signals, following, spawn/despawn | WORKING | Tested: 13 cars, 10–13 moving, 0–1 stuck. |
| Lane changes, accident handling | PARTIAL | Lane is picked per road segment; stuck cars reverse or despawn. No overtaking. |
| Parked vehicles | WORKING | About 40 placed at start, frozen until used or hit. |
| Vehicle framework (suspension, grip, brakes, handbrake, reverse) | WORKING | Tested (`drive`): sedan 20.9 m/s, sports 33.3 m/s, motorcycle 30.8 m/s, truck 12.8 m/s in 8 s; all stayed upright. |
| Car roster: compact, sedan, sports, muscle, SUV, pickup, van, police, taxi, ambulance, tactical van, box truck, fire engine | WORKING | Distinct Blender bodies; four were driven in tests, the rest share the same code. |
| Motorcycle | WORKING | Tested. Uses four hidden wheel rays and a visual lean. |
| Bicycle | PARTIAL | Uses the motorcycle model with low power; no pedalling animation; untested. |
| Speedboat with buoyancy | WORKING | Tested: floats at rest, 14.4 m/s after 6 s. |
| Helicopter (civil and police) | WORKING | Tested: 40 m climb in 6 s, 25 m/s forward. |
| Propeller plane | WORKING | Tested after retune: 21.7 m/s ground roll in 5 s, climbed to 59 m. Holding full back-stick bleeds speed to 13.6 m/s, below the 22 m/s stall speed, while still climbing on thrust, so stall behaviour is weak. |
| Jet | WORKING | Tested after the rolling-drag fix: 50.9 m/s on the runway, 109 m altitude. |
| Aircraft landing | NOT IMPLEMENTED as a tested feature | Wheels and brakes exist; landing was never attempted. |
| Enter / exit vehicles | WORKING | Tested with the F key. |
| Carjacking occupied vehicles | WORKING | Tested: driver ejected, witness report gave 1 star after the delay. |
| Drive-by shooting | WORKING | Tested: SMG fired from a moving sedan with LMB. One-handed weapons only. |
| Headlights, brake lights, horn, siren | WORKING | Horn key tested; lights are automatic at night. |
| Reverse lights, doors, trunk/hood, convertible roof | NOT IMPLEMENTED | |
| Vehicle damage, smoke, fire, explosion | WORKING | Collision damage tested; rocket kill of a car was not confirmed (the test rocket missed before the spawn fix). |
| Tire puncture, bullet-resistant tires | PARTIAL | Implemented; untested. |
| Detachable parts, deformation, broken glass | NOT IMPLEMENTED | |
| Mod garage: repair, paint, finish, wheels, tint, lights, horn, plate, 6 body parts, 8 performance upgrades | WORKING | Tested: prompt in the bay, parts visible, multipliers applied, repair. |
| Liveries, bumpers/grille variants beyond the 6 parts | NOT IMPLEMENTED | |
| Weapons: fists, knife, bat, pistol, revolver, SMG, pump shotgun, assault rifle, carbine, marksman rifle, sniper, grenade, rocket launcher | WORKING | Pistol, SMG, shotgun, rifle, sniper, grenade, rocket and bat were fired in tests. |
| Ammo, magazines, reload, recoil, spread, fire rate | WORKING | Tested with simulated mouse input. |
| Weapon wheel (Tab, slow motion) | WORKING | Tested open/close; mouse selection untested. |
| Scoped sniper view | PARTIAL | Overlay and zoom implemented; untested. |
| Weapon attachments and finishes | PARTIAL | Suppressor, flashlight, extended magazine, optic and grip change stats and show on the model; menu path untested. |
| Bullet impacts: sparks, dust, decals, impact audio | WORKING | |
| Glass breaking, bullet penetration | NOT IMPLEMENTED | |
| Wanted system 0–5 stars | WORKING | Tested (`police`). |
| Witnesses and delayed reports | WORKING | Tested: no stars with nobody around, 1 star 3.5 s after a witnessed carjack. |
| Pursuit vs search, last known position, LOS escape | PARTIAL | State switching tested. A full escape to 0 stars was not achieved in tests: officers found the player in the safehouse both times. |
| Police dispatch, officers leaving cars, shooting | WORKING | Tested: 3 units and 3 officers at 3 stars; an officer killed the player in 7.5 s. |
| Tactical vans and units (4–5 stars) | PARTIAL | Implemented; 4 stars only ran in the performance sample. |
| Police helicopter with spotlight and gunner | PARTIAL | Spawns at 3 stars and tracks the player; gunner at 4+ untested. |
| Roadblocks | WORKING | Tested: block placed 97 m ahead and it stopped the car. |
| PIT / ramming / boxing in | PARTIAL | Pursuit driver aims at the rear quarter; not observed. |
| Spike strips, officers commandeering cars | NOT IMPLEMENTED | Spike strip model exists but is unused. |
| Vehicle/appearance change helps evasion | PARTIAL | Reduces detection range; untested. |
| Busted / arrest | PARTIAL | Busted outcome and respawn tested by direct call; the arrest trigger by an officer was not observed. |
| Death and hospital respawn | WORKING | Tested. |
| Economy, cash pickups, NPC cash drops | WORKING | |
| Weapon shop | WORKING | Menu opened in test; purchases untested. |
| Clothing store, barber, wardrobe | PARTIAL | Colours, cap, glasses, hair and beard; menus untested. |
| Safehouse: save, sleep, wardrobe, interior | PARTIAL | Enterable room with bed and wardrobe; menu untested. |
| Garage vehicle storage | WORKING | Serialise/restore round trip tested, including mods and paint. |
| Phone: taxi, save, delivery, GPS, radio, photo mode | PARTIAL | Menu opened in test; items untested except taxi call. |
| Taxi passenger service with skip | WORKING | Tested in the final run: taxi arrived (7 m away), ride started, skip delivered the player 5 m from the hospital. The taxi obeys red lights, so arrival can take close to a minute. |
| Trains / transit | NOT IMPLEMENTED | |
| Parachute | WORKING | Tested from a helicopter: deploy, descent at 4.5 m/s, landing. |
| Swimming, diving, breath, scuba | WORKING | Tested swim state and breath; scuba untested. |
| Underwater wreck with loot | WORKING | Placed; screenshot taken nearby. |
| Wildlife (deer, boar, dogs, gulls, fish, sharks) | PARTIAL | 33 animals spawn; behaviour untested; rigid models without leg animation. |
| Day/night cycle, lit windows, street lamps | WORKING | Tested (`night`). |
| Weather: clear, cloudy, rain, fog, storm | WORKING | Rain and storm tested; wet roads and reduced grip. |
| Minimap, full map, waypoint, GPS line | WORKING | Map screenshot tested; route follows road nodes only. |
| HUD | WORKING | |
| Audio (synthesized) | PARTIAL | All categories exist; none could be listened to in this run. |
| Radio (3 stations) | PARTIAL | Procedural loops; untested by ear. |
| Ambulance / fire engine response | PARTIAL | Dispatch tested; arrival and medic behaviour untested. |
| Save / load | WORKING | Tested round trip. |
| Admin / benchmark menu | PARTIAL | All listed functions are present; only the top level was opened in test. |
| Character skills (7) | PARTIAL | Gains and effects implemented; untested. |
| Shooting range | WORKING | Tested: 6 hits, score 133. |
| Stunt jumps | WORKING | Tested: 42.8 m jump detected. |
| Street time trial | PARTIAL | Implemented; untested. |
| Interiors beyond the safehouse | NOT IMPLEMENTED | Shops are used from the door. |
| Controller support | NOT IMPLEMENTED | |
| LOD meshes | NOT IMPLEMENTED | Assets are low-poly; only grass uses a visibility range. |
| Navigation mesh | WORKING | Baked at startup (6061 polygons) and used for NPC chase and flee paths. |
