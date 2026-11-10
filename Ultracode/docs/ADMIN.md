# HALCYON BAY - Admin / benchmark menu and debug system

Owner: TOOLS programmer. Spec sections 38 (admin / benchmark menu), 26 (vehicle access), 54 (QA).
A testing tool for video demos and QA bots - **not** a mission system.

| file | what |
|---|---|
| `gta/code/debug/debug_system.gd` | world system `debug` (BootManifest): the cheat API, the performance overlay, text commands |
| `gta/code/ui/screens/admin_menu.gd` | `UI.SCREENS["admin"]` (F1): the menu, a thin UI over the debug system |
| `gta/tests/adm_api.gd` | headless test of every cheat function against the full game |
| `gta/tests/adm_shots.gd` | windowed screenshots of every tab and of the overlay (`qa/screenshots/adm_*.png`) |

Everything reaches other modules through their public APIs, softly (`Game.get_system`, `has_method`,
`"prop" in obj`, `ResourceLoader.exists`). A missing neighbour makes the call return `false` / `null`
and the menu greys the control out with a "Not available yet - ..." hint; nothing errors.

---------------------------------------------------------------------------------------------------

## 1. The admin menu (F1)

`UI.open_screen("admin", {"tab": "vehicles"})` - or F1 (`admin_menu` action, handled by the UI
autoload: opens only when no other screen is open, F1 again / Esc closes).

* Does **not** pause (`PAUSES_GAME false`): time, weather, traffic and spawns change live behind it.
* Locks gameplay input, shows the mouse. HUD stays visible on the right (money, wanted strip,
  toasts, weapon / vehicle card); the opaque panel docks left (1120 logical px of 1920).
* Q / E (LB / RB) or a click switch tabs; W / S navigate; A / D change option rows and sliders;
  Enter activates. The last tab is remembered for the session.
* Header strip: weather icon, clock, wanted stars, money, a shield while invulnerable and the time
  scale when it is not x1.
* While the menu is open the performance overlay moves to the bottom-right (above the HUD weapon
  card), clear of the toasts that confirm every admin action.

| tab | controls (debug system call) |
|---|---|
| Teleport | 8 districts (`teleport_player("district:<id>")`), every named location of the world with icon, district and distance (`teleport_player(name)`), "Go to map waypoint" (`"waypoint"`), "Bring vehicle" yes / no |
| Vehicles | class filter All / Cars / Service / Bikes / Boats / Helicopters / Planes, "Spawn + drive" or "Spawn only" (`spawn_vehicle_for_player(id, enter)`; "Spawn + drive" closes the menu), every registered spec (greyed with the reason when its GLB or class script is missing), Repair / Flip upright / Customise / Despawn (`repair_current_vehicle`, `flip_current_vehicle`, `open_customisation`, `clear_admin_vehicles`), "Unlock all mods (free)" (`set_mods_unlocked`) |
| Weapons | Give all weapons, Refill ammo, All attachments, Infinite ammunition, list of all 17 weapons (select = give with full ammo and draw) |
| Player | health / armour / breath bars, Health + Armour sliders, Heal + armour, Refill lungs, Kill player (confirm dialog), Invulnerable, money (type an amount + Set, + $10K / $100K / $1M), Give parachute, Random appearance, Scuba gear on / off, parachute state, 7 skill bars, Max all skills, Reset skills |
| Wanted | star picker 0-5 (click, or A / D), pursuit / search state + escape bar, Clear wanted level, Arrest me (`Wanted.bust`), Never wanted, police units Officer / Cruiser / SWAT / Helicopter / Roadblock / Clear units (police dispatcher) |
| World | clock + Hour slider, presets Dawn 06:00 / Morning 09:00 / Noon 12:00 / Sunset 19:30 / Dusk 20:45 / Midnight 00:00, Clock running / paused, weather buttons Clear / Cloudy / Rain / Fog / Storm (3 s blend, stops automatic changes), Automatic weather changes, toggles Traffic / Pedestrians / Wildlife / Police / Emergency services / Trams (`Game.set_system_enabled`), Traffic / Pedestrian density sliders |
| Services | Call a taxi, Deliver personal vehicle, Store vehicle in garage, Customise vehicle here, Phone / Garage / Wardrobe screens, Quick save / Quick load |
| Debug | Performance overlay (F3), HUD visible / hidden (clean video shots), Time scale slider 0.25-2 + presets, live FPS / frame time / draw calls / position / district / sector / entity counts / nodes, Clear spawned vehicles, Repair all vehicles, Respawn pickups |

---------------------------------------------------------------------------------------------------

## 2. Debug system API (`Game.get_system("debug")`)

```gdscript
# availability (the menu greys out what is missing)
is_available(feature) -> bool;  unavailable_reason(feature) -> String
#   features: player teleport vehicles customise weapons parachute scuba breath appearance wanted
#   never_wanted bust police_units clear_police taxi garage_delivery garage_store traffic peds
#   wildlife police emergency transit "screen:<id>"
# teleport
get_teleport_targets() -> Array[Dictionary]    # {id, name, kind "district"|"location", district, position, yaw, water}
resolve_target(target) -> Dictionary           # {ok, name, position, yaw, water}
teleport_player(target, keep_vehicle := true) -> bool   # location name | "district:<id>" | "waypoint" | Vector3 | Transform3D
find_safe_spot(pos) -> Vector3                 # free standing spot (capsule test) on solid ground near pos
# vehicles
get_vehicle_specs(group := "") -> Array[Dictionary]   # {id, name, vehicle_class, group, can_spawn, reason, seats, top_speed_kmh}
vehicle_group(spec_or_id) -> String            # car | service | bike | boat | heli | plane
find_vehicle_spawn(spec_id, enter := false) -> Dictionary   # {ok, transform, where}
spawn_vehicle_for_player(spec_id, enter := false) -> Node3D
get_target_vehicle() -> Node3D                 # the player's vehicle, else the nearest within 10 m
repair_current_vehicle() -> bool;  flip_current_vehicle() -> bool;  open_customisation() -> bool
set_mods_unlocked(on);  clear_admin_vehicles() -> int;  get_admin_vehicles() -> Array
repair_all_vehicles() -> bool;  respawn_pickups() -> bool
# weapons
get_weapon_list() -> Array[Dictionary];  give_weapon(id, equip := true) -> bool;  give_all_weapons() -> int
refill_ammo() -> bool;  give_all_attachments() -> int;  set_infinite_ammo(on) -> bool;  is_infinite_ammo() -> bool
# player
set_health(v) -> bool;  set_armor(v) -> bool;  heal_full() -> bool;  set_money(n);  add_money(n)
set_invulnerable(on);  max_skills();  reset_skills();  give_parachute() -> bool;  set_scuba(on) -> bool
has_scuba() -> bool;  refill_breath() -> bool;  randomize_appearance(seed := -1) -> bool;  kill_player() -> bool
# wanted / police
set_wanted(level);  clear_wanted();  set_never_wanted(on) -> bool;  is_never_wanted() -> bool
bust_player() -> bool;  spawn_police(kind := "cruiser") -> Node;  clear_police() -> bool
# world
set_time(hour);  set_clock_paused(on);  is_clock_paused() -> bool
set_weather(id, instant := false) -> bool;  set_auto_weather(on);  is_auto_weather() -> bool
toggle_system(name, on) -> bool;  is_system_enabled(name) -> bool;  set_density("traffic"|"peds", v);  get_density(kind)
# services
call_taxi() -> bool;  deliver_personal_vehicle() -> Node3D;  store_current_vehicle() -> bool
# debug
set_time_scale(s);  set_overlay_visible(on);  toggle_overlay();  is_overlay_visible() -> bool;  set_overlay_origin(p)
get_sector(pos) -> String;  district_at(pos) -> String
get_frame_stats() -> Dictionary;  refresh_stats() -> Dictionary;  get_stats() -> Dictionary
run_command(line) -> String
# members
time_scale, mods_unlocked, overlay_origin, last_teleport, last_spawn
```

### Teleport rules

* Land destinations: a ring search (0 to 20 m, same height level first) for a spot whose ground is
  static world geometry, level (normal.y > 0.86), dry, and where a player capsule touches no
  building, vehicle, prop or NPC. Fallback: the nearest WalkGraph point. Then `player.teleport()`
  (which also snaps the camera).
* Water destinations (a point at / below sea level over water: `boat_spawn`, `shipwreck`): the
  player floats at the wave surface (`environment.get_wave_height`) minus the player's
  `FLOAT_DEPTH`, i.e. swimming.
* Districts: the WalkGraph point nearest the centroid of the district's lots (sidewalk at the heart
  of the district), facing that centroid.
* In a vehicle with "Bring vehicle": cars / bikes / aircraft move with the player to a free spot that
  fits their body (helicopters also need open sky), boats to water destinations; any other combination
  leaves the vehicle behind and teleports the player on foot.

### Vehicle spawn rules (spec 26: no searching the map for a helicopter or an aircraft)

| class | where |
|---|---|
| car, bike, bicycle | free, level, dry ground in front of the camera (broadside for "Spawn only", facing away for "Spawn + drive"); in the water / in the air / boxed in: the nearest road lane; last resort the nearest `parking` spawn point |
| boat | nearest deep (1.6 m+), open water within 230 m, bow toward deeper water, clear of piers, quays and other boats; further inland: free water next to the nearest `boat` spawn point (the marina) |
| heli | free ground with 10 m of open sky within 45 m; else the nearest `heli` spawn point / helipad |
| plane | the runway start (`airport_runway_start`), stepping 26 m down the runway while occupied |

Spawned vehicles get `owner_tag "player"`. At most 10 admin vehicles live at once (the oldest one the
player is not sitting in is despawned). A far spawn (plane at the runway) sets the map waypoint.

### Text commands (`run_command`, `--adm_cmd=`)

`tp <target|x y z>`, `veh <spec> [enter]`, `weapon <id>`, `weapons`, `ammo`, `attachments`,
`god [on|off]`, `money <n>`, `health <n>`, `armor <n>`, `heal`, `wanted <0-5>`, `neverwanted [on|off]`,
`police <kind>`, `time <hour>`, `weather <id>`, `sys <name> <on|off>`, `density <traffic|peds> <v>`,
`repair`, `flip`, `skills <max|reset>`, `parachute`, `scuba [on|off]`, `breath`, `appearance`, `taxi`,
`scale <0.25..2>`, `overlay [on|off]`, `stats`. Returns `"ok"` / `"error ..."`.

Command line (after `--`): `--adm_overlay` shows the overlay; `--adm_cmd=tp airport_helipad;veh heli_civil enter;time 19.5`
runs commands right after `game_ready` (handy for screenshot runs of other modules).

---------------------------------------------------------------------------------------------------

## 3. Performance overlay (F3)

The UI autoload owns the flag (`UI.debug_overlay_visible`; F3, the pause-menu setting
"Performance overlay" and `set_overlay_visible()` all toggle it). While the flag is on, the debug
system draws its overlay on CanvasLayer 11 and hides the UI's basic text box (`UI/Root/Debug`).
One custom-drawn Control, refreshed 4 times a second (no per-frame allocation; the frame-time ring
buffer is a preallocated `PackedInt32Array`):

* current FPS (green >= 55, yellow >= 30, red), **average FPS and 1 % low over the last 5 s of real
  frame times** (1 % low = 1 / mean of the slowest 1 % of frames), frame-time graph of the last 5 s
  with 60 / 30 fps guides;
* frame ms (average / worst), GPU ms (`viewport_get_measured_render_time_gpu`, measured only while
  shown), CPU process / physics ms, VRAM;
* draw calls, primitives and objects (`RenderingServer.get_rendering_info`), node count, vehicles,
  pedestrians, NPCs, police, animals (group counts);
* player position, heading, district, **sector** (100 m grid over the island: columns A-F west to
  east, rows 1-6 north to south, `OFF` outside), time, day phase, weather, time scale, wanted level.

### Time scale

0.25-1 goes through `Game.request_time_scale("debug", s)` (lowest request wins, as for the weapon
wheel). Above 1 `Game` clamps requests, so the debug system sets `Engine.time_scale` itself while no
other system asks for slow motion and re-applies it when the last request ends.

---------------------------------------------------------------------------------------------------

## 4. Integration notes for neighbours

* **Shops / mod garage**: "Unlock all mods" sets `Game.flags["free_shopping"] = true` (W2.6: prices
  become 0) and `Game.flags["unlock_all_mods"] = true` (show every option the vehicle supports, no
  progression gates). Clearing it erases both flags.
* **Mod garage screen**: "Customise" closes the admin menu and calls
  `UI.open_screen("mod_garage", {"vehicle": v, "anywhere": true, "source": "admin", "free": mods_unlocked})`
  for the player's (or the nearest) vehicle. Please accept a vehicle passed in `args.vehicle` anywhere.
* **Taxi**: "Call a taxi" calls the first of `call_taxi(pos)`, `request_taxi(pos)`, `summon_taxi(pos)`
  found on `Game.get_system("taxi")`; anything non-null / non-false counts as accepted.
* **Police**: `spawn_unit(kind, near)` with kinds `officer, cruiser, swat, heli, roadblock` and
  `clear_units()`; "Arrest me" calls `Wanted.bust()`; "Never wanted" sets `Wanted.enabled = false`
  (or calls `Wanted.set_enabled(false)` when that exists).
* **Toggles** go through `Game.set_system_enabled(name, on)` -> your `set_enabled(on)`. The menu reads
  the state back from your `enabled` member when you have one.
* **Densities**: `Settings.set_value("traffic_density" | "ped_density", v, false)` plus your
  `set_density(v)` when present.
* **Garage**: `deliver_personal_vehicle(near)`, `store_vehicle(vehicle)` (W2.7).
* **Respawn**: "Kill player" calls `player.kill("admin")` (invulnerability is lifted for the call).

---------------------------------------------------------------------------------------------------

## 5. Tests

```powershell
tools\godot.ps1 -Mode check -Dirs 'gta/code/debug,gta/code/ui/screens,gta/tests'
tools\godot.ps1 -Mode headless -Frames 6000 -TimeoutSec 400 -UserArgs '--test=adm_api','--test-timeout=380'
tools\godot.ps1 -Mode window   -Frames 600  -TimeoutSec 120 -UserArgs '--test=adm_shots'          # '--adm_only=world,overlay'
```

`adm_api` (107 checks in the last run): sector grid; teleport to all 8 districts + every named location (39)
ends grounded on solid ground with a ray hit under the feet, or swimming for water locations; raw
positions; every spawnable vehicle spec spawns on a suitable surface (cars on dry ground, boats on
water, planes at the runway); two boats get separate spots; spawn + drive, repair, flip upright,
teleport while driving, water teleport leaves a car behind; unlock-mods flags; all weapons, full ammo,
attachments, infinite ammo; health / armour / heal / money / invulnerability / skills / parachute /
scuba / breath / appearance; wanted 3 / 5 / clear / never wanted / text command; time / clock pause /
weather instant + blended / auto weather; system toggles (every system that exists, plus `pickups`);
densities; time scale 0.5 / 2 / interplay with another slow-motion request; overlay on / off with
stats; text commands; F1 opens the menu without pausing, locks input, every tab builds, F1 closes.
Features whose module does not exist yet are logged as `SKIP`.

`adm_shots`: `qa/screenshots/adm_teleport, adm_vehicles, adm_weapons, adm_player, adm_wanted,
adm_world, adm_world_sim, adm_services, adm_debug, adm_overlay, adm_menu_overlay`.
