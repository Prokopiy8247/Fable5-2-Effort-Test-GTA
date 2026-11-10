# FABLE 5.2 FINAL REPORT — Port Fable (Godot GTA sandbox, Low)

## What was built
An original, missionless GTA-style free-roam sandbox in the existing Godot 4.7.2 project (Forward+, GDScript). The game launches directly into free roam on a compact island city. Every 3D model was authored in Blender through the verified MCP connection on localhost:9877 and exported as GLB; the world, gameplay, UI and audio are built in code. There is no mission, quest or objective system.

Art direction: flat-shaded low-poly "toy city" with one shared colour palette across characters, vehicles, weapons, buildings, props and UI.

## Validation performed
All checks were scripted (`tools/run_test.sh`, 15 test plans) plus screenshots I inspected. Nobody played the game by hand, and audio was never listened to. `FEATURE_MATRIX.md` marks which features a test exercised and which were only checked by reading the code.

Final results:
- Project parses and boots with no script errors; world builds in about 1.2 s; navmesh bakes (6061 polygons).
- Simulated keyboard/mouse input: walking, sprint, jump, crouch, weapon slot keys, aiming and firing, reload, F enter/exit, driving, drive-by, weapon wheel, phone, pause all responded.
- Driving: sedan 20.9 m/s, sports 33.3 m/s, motorcycle 30.8 m/s and truck 12.8 m/s after 8 s; all stayed upright.
- Flight: helicopter climbed 40 m in 6 s; prop plane and jet both took off; parachute deployed and landed.
- Boat floated and reached 14.4 m/s; swimming and diving states worked.
- Combat: seven weapons damaged or killed targets; an unwitnessed killing gave no stars.
- Police: 3 stars brought 3 units, 3 officers on foot and a helicopter within 24 s; an officer killed the unprotected player in 7.5 s; death and busted respawns worked; a roadblock stopped the car.
- Traffic: 13 AI cars, 10–13 moving, at most 1 stuck; 24 pedestrians walking; 7–14 of 22 fled a gunshot.
- Carjack, mod garage, garage storage round trip, cover attach, ladder, taxi ride with skip, shooting range and stunt jump detection all passed.
- Save/load round trip passed.

## What is partial or missing
- A full escape from a wanted level down to 0 stars was never achieved in a test (officers found the player both times), so the escape timer is verified only up to 12 s of "unseen".
- Not tested at all: vault, roll, cover movement/peek/blind fire, stealth takedown, melee block, store robbery, shop purchases, clothing/barber menus, weapon attachments via the menu, skills, time trial, first person, scoped view, tire puncture, tactical units at 4–5 stars, helicopter gunner, ambulance/fire engine arrival, wildlife behaviour, aircraft landing.
- Ragdoll is a scripted knockdown, not a physical bone ragdoll. Animations are procedural bone rotations, no authored clips.
- NPC cover use is limited to officers crouching behind their own car.
- Not implemented: trains, spike strips, officers commandeering cars, doors/trunk/hood/convertible roof, reverse lights, glass breaking, bullet penetration, vehicle deformation or detachable parts, liveries, shop interiors (only the safehouse is enterable), tattoo shop, tennis/golf/darts, controller support, mesh LODs.
- Bicycle reuses motorcycle physics with no pedalling animation.

## Known bugs / rough edges
- The prop plane keeps climbing on thrust below stall speed when the stick is held back.
- Menus were laid out for 1600×900; at 1280×720 the panel was cut off before a fix that was not re-screenshotted.
- The search-radius ring on the full-screen map is drawn at the wrong scale.
- Particle sprites are plain squares (intended for the style, but explosions look blocky up close).
- On exit Godot reports about 15 leaked ObjectDB instances.
- The Blender add-on is two protocol versions behind the server; everything used here worked.

## Controls
See `DEVELOPMENT.md` (also in-game: Esc → Controls). F1 opens the admin/benchmark menu.

## Build result
No export build was made. The project runs from the editor or with `Godot_v4.7.2-stable_win64.exe --path .`. V-Sync is on and `max_fps` is 60.

## Major assets created in Blender (140 root assets, 485 objects)
- Vehicles (20): compact, sedan, sports, muscle, SUV, pickup, van, police cruiser, taxi, ambulance, tactical van, box truck, fire engine, motorcycle, bicycle, speedboat, civil helicopter, police helicopter, prop plane, jet. Cars have separate wheels and six mod parts.
- Characters (2 rigged bodies, 12 accessories) and 6 animals.
- Weapons (12 + rocket projectile) with attachment parts.
- Buildings (30): 4 offices, 3 apartments, 4 houses, 4 shops, weapon shop, clothing store, barber, police station, hospital, 2 warehouses, factory, range, mod garage, gas station, hangar, control tower, parking deck, safehouse.
- Street/world props (43), interior props (4), nature (8), VFX helper meshes (2).

## Vehicle roster (all spawnable from the admin menu)
Pip Compact, Meridian Sedan, Vanta GT, Brawler 440, Ridgeback SUV, Hauler Pickup, Cargo Van, Police Cruiser, City Taxi, Ambulance, Tactical Van, Box Truck, Fire Engine, Wraith 600 motorcycle, Street Bicycle, Marlin Speedboat, Skylark Helicopter, Police Helicopter, Finch 170 Prop, Arrow Jet.

## Weapon roster
Fists, Combat Knife, Ash Bat, P9 Pistol, Ridge .44 Revolver, Hornet SMG, Pump Shotgun, AR-7 Assault Rifle, Kestrel Carbine, Longfield Marksman, Hawkeye Sniper, Frag Grenade, Ramrod Launcher.

## Map regions
Downtown, Midtown, Harbor Row, Maple Heights (residential, safehouse), Central Park, Ironworks (industrial), Waterfront (promenade, beach, piers, docks), Airport, Northridge Hills, West Side, open sea with a dive wreck.

## Wanted / police implementation
Crimes add heat with per-crime minimum stars. A crime counts at once if police see it; otherwise a civilian witness reports it after 3.5 s unless silenced first, and unheard, unseen crimes give nothing. While any officer, police car or the helicopter has line of sight the state is Pursuit; otherwise Search around the last known position, stars flash, and the wanted level clears after 14–58 s unseen depending on stars. Dispatch scales cruisers by stars, adds tactical vans at 4+, a helicopter and roadblocks at 3+. Officers leave their cars, shoot at 2+ stars, try to arrest at 1 star, and return to their car if the player drives off. Death and arrest both clear the level.

## Performance notes
Measured only with the 30 fps test cap, 1280×720, RTX 5070: a 20 s downtown sample at 4 stars with 50 NPCs and 65 vehicles held 30.0 fps average and minimum, 4.3 ms process time, 6.1 ms physics time, 1753 draw calls. No uncapped measurement was taken, to keep GPU load low for the other agents.

## Claude Fable 5.2 GTA Session Metrics

Project: Godot GTA sandbox
Run/session identifier: run-20261109-214834 / Claude Code session 6cbcf8f5-a6fa-4ea5-9dff-2b4d154ce3a3
Working-directory full path: G:\YouTube\Fable 5.2 Effort Test GTA\Low
Start timestamp and timezone: 2026-11-09T21:48:34+01:00 (Central European Standard Time)
End timestamp and timezone: 2026-11-09T23:52:27+01:00 (Central European Standard Time)
Elapsed wall-clock time (HH:MM:SS): 02:03:53 (measured, includes the pauses below)
Elapsed minutes: 123.9
Elapsed hours: 2.06
Known pauses / resumed segments: segment 1 ran 21:48:34-21:50:06 and stopped on the missing Blender MCP; segment 2 started 2026-11-09T22:01:47+01:00. Sum of the two segments: 01:52:11 (112.2 min). Segment 2 also contains one interruption of unknown length before the user's "Try again" message.

Requested model: Claude Fable 5.2
Actual model identifier(s): claude-fable-5-2 (80 responses)
Thinking/effort setting (if exposed): not exposed in the log (this benchmark folder is the "Low" effort variant)
Input tokens (state whether uncached or inclusive): 164 (uncached only)
Cache-read tokens: 29,564,109
Cache-write tokens: 520,356
Cache-write duration breakdown (if exposed): 5-minute 0; 1-hour 520,356
Output tokens: 406,930
Thinking/reasoning tokens (included / separate / unavailable): included in output tokens; not reported separately
Deduplicated total tokens: 30,491,559
Usage source and observation cutoff: local Claude Code session log (~/.claude/projects/G--YouTube-Fable-5-2-Effort-Test-GTA-Low/6cbcf8f5-a6fa-4ea5-9dff-2b4d154ce3a3.jsonl), per-response usage deduplicated by message id, read at 2026-11-09T23:52:27+01:00
Unmeasured work / limitations: (1) the response that wrote this section and the final chat message are not in the count; (2) segment 1 ran in an earlier session whose log was not found, so its tokens are not counted; (3) this session's log also contains one short turn before the task prompt (a Blender connection check), which is counted; (4) one delegated web-fetch subagent (about 19k tokens, model not recorded) is not counted.

Token-only API-equivalent cost (USD): $30.52 (measured tokens x list rates; a lower bound given the limitations above)
Per-model subtotals (if applicable): single model
Official pricing source, verification date and comparison tier: https://platform.claude.com/docs/en/about-claude/pricing, read on 2026-11-09 through a web-fetch subagent (I did not read the page myself), Standard API tier
Rates and formula used: input $8, 5-minute cache write $10, 1-hour cache write $16, cache read $0.20, output $40 per million tokens; cost = sum(category tokens x rate) / 1,000,000
Cache/context/tier adjustments or explicit assumptions: no long-context, batch or fast-mode adjustment applied
External tool/API fees (known / excluded / unknown): none known; local Blender and Godot carry no fee; no asset libraries or 3D generators were used
Measured / estimated / unavailable, with reasons: time measured from OS timestamps; tokens measured from the session log with the listed gaps; cost computed from those tokens, so it is a measured lower bound, not a bill

Blender MCP server/tool namespace actually used: blender-gta-low (mcp__blender-gta-low__*)
Blender host: localhost
Blender port: 9877
Blender master file: GodotFable5.2GTALow.blend
Verified full path of master file: G:\YouTube\Fable 5.2 Effort Test GTA\Low\GodotFable5.2GTALow.blend
Approximate number of major Blender assets created: 140
