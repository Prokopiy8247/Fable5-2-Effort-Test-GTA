# HALCYON BAY - Garages, Torque Garage, safehouse, gas station, vehicle access

Owner: Economy programmer B (Wave 2). Contract: `docs/ARCHITECTURE_WAVE2.md` W2.4 / W2.6 / W2.7,
spec sections 14A, 23A, 26, 37. Neighbours: VEHICLES.md (mods, paint, repair, save data), UI.md
(screens, widget kit), LANDMARKS.md (markers), WORLD.md (locations, spawn points).

## 1. Files

| file | what |
|---|---|
| `gta/code/vehicles/garage_system.gd` | world system `garage` (BootManifest). Storage, personal vehicle, sites, rentals, SaveSystem provider `garage`; creates the helpers below in `setup()` |
| `gta/code/world/shops/garage_sites.gd` | static marker resolver: city builder -> lot + manifest markers -> named location; spawn-point and free-spot helpers |
| `gta/code/world/shops/garage_stats.gd` | static numbers: stat bars from `VehicleSpec` + mods, vehicle condition, repair / service / rental prices, paint palette, money formatter |
| `gta/code/world/shops/garage_mod_shop.gd` | Torque Garage bay session (`mod_garage` landmark, `Use_Bay` / `Exit_Bay`) |
| `gta/code/world/shops/garage_safehouse.gd` | safehouse bed / save point / wardrobe / garage spot (`safehouse` landmark) |
| `gta/code/world/shops/garage_gas_station.gd` | Halcyon Fuel quick service + explosive `Pump_1..4` |
| `gta/code/world/shops/garage_vehicle_access.gd` | rental terminals (airport, marina, parking garage) + parking garage store point |
| `gta/code/ui/screens/mod_garage_screen.gd` | UI `mod_garage`: tabs, live preview, purchase, stat bars, orbit camera |
| `gta/code/ui/screens/garage_screen.gd` | UI `garage`: stored vehicles / rental catalogue |
| `gta/code/ui/screens/safehouse_screen.gd` | UI `safehouse`: sleep, save, wardrobe, garage |
| `gta/tests/gar_api.gd`, `gta/tests/gar_shots.gd` | tests (section 8) |

No `class_name`s: helpers are loaded by path; vehicles, the city, the player and Wanted are reached
by duck typing (`has_method`, `get`), so a missing or broken neighbour never breaks this module.

## 2. Garage system API (`Game.get_system("garage")`)

Contract (W2.7):

```gdscript
func store_vehicle(vehicle: Node3D) -> bool          # removes it, keeps spec / colours / mods / health; a player inside is put on foot first
func get_stored() -> Array[Dictionary]               # deep copies of VehicleBase.get_save_data() + "name", "class", ["personal"]
func retrieve_vehicle(index: int, xform: Transform3D) -> Node3D   # spawns it (owner "player", asleep), makes it personal, removes it from storage
func get_capacity() -> int                           # 4 bays, shared by the safehouse and the parking garage
func set_personal_vehicle(v: Node3D) -> void;  func get_personal_vehicle() -> Node3D
func deliver_personal_vehicle(near: Vector3) -> Node3D   # personal vehicle (or the personal / first stored one) to the nearest free kerb spot
```

Additions:

| member | use |
|---|---|
| `can_store(v) -> String` | "" or the reason (wreck, police / emergency, not a car / bike, too big, full) |
| `last_error: String` | reason of the last failed store / retrieve / rent (admin and phone can show it) |
| `remove_stored(i)`, `garage_vehicle_name(i)`, `capture(v)`, `spawn_from_data(d, xform)` | storage helpers |
| `retrieve_at_site(i, site)`, `rent_and_board(spec_id, site)`, `board(v)` | coroutines: fade, spawn at the site's first clear spot, seat the player, toast |
| `rent_vehicle(spec_id, site) -> Node3D` | rental without seating (fee unless `free_shopping`; refunded if the spawn fails) |
| `get_catalogue(kinds: Array) -> Array[Dictionary]` | `{id, name, class, fee, available, top_kmh, seats, flags, description}` of every registered spec of those classes |
| `find_spawn(site, vehicle_class) -> {"ok", "xform"}` | first clear spawn transform of a site; site `"player"` = in front of the player (admin) |
| `register_site(id, helper)`, `get_site_ids()`, `has_site(id)` | sites: `safehouse`, `airport`, `marina`, `parking_garage` |
| `get_helper(name)` | `mod_shop`, `safehouse`, `gas_station`, `access` |
| `is_police_or_emergency(v)`, `is_storable_class(cls)` | rules |
| `refresh_sites()` | re-resolves every marker (called on `game_ready`) |
| `set_enabled(on)`, `reset_for_respawn()` | system hooks |

Personal vehicle: `VehicleManager.set_personal_vehicle()` is the source of truth (the manager saves
it under provider `vehicles` and respawns it on load). The garage system mirrors it once a second
and tags it with the groups **`personal_vehicle`** and **`minimap_blip`** (metas `blip_icon = &"car"`,
`blip_color` teal, `blip_clamp = true`) so the minimap shows it. Wrecks lose the tag. A vehicle
becomes personal when it is taken out of the garage or customised at Torque Garage.

Save provider `garage`: `{"version": 1, "capacity": 4, "stored": [...], "spawn_inside": bool}`.

## 3. Torque Garage (spec 14A)

- In-vehicle `Interactable` on `Use_Bay` (radius 3.2 m + 2.5 m in vehicles, priority 5, only below
  4 m/s). Refused: wrecks, police vehicles, and anybody with a wanted level.
- Session: fade, the car is teleported to the centre of the bay and held (input locked by the
  screen), two shadowless work lights switch on (SpotLight + OmniLight, only during the session),
  UI `mod_garage` opens with `{"vehicle", "shop"}`. On close: fade, car on `Exit_Bay` facing out,
  player still at the wheel, toast with the number of jobs and the total.
- Screen tabs (only those the vehicle supports, from `vehicle.get_mod_options()`):
  **Repair** (cost = missing hp x 0.8 + $90 per broken pane + $140 per flat tyre, min $60; restores
  health, glass, lamps, tyres, handling via `vehicle.repair()`; condition bars Body / Glass /
  Tyres / Engine), **Paint** (16-colour palette, primary $450, secondary $300 where the model has
  `M_Paint_Secondary`, finish gloss / matte / metallic = mod slot `paint_finish`), **Wheels** (stock
  + the four shared styles, rim colour), **Body** (spoiler, bumpers, hood, skirts, roof, exhaust,
  grille: the Blender `Mod_*` parts), **Lights** (headlamp tint; headlights are switched on while
  this tab is open), **Windows** (tint), **Plate**, **Horn** (the horn sounds on hover),
  **Performance** (engine, turbo, transmission, brakes, suspension, tyres incl. bullet-resistant,
  armour). Classes other than `car` and police / emergency vehicles get **Repair only**; fixed
  liveries (taxi) get no Paint tab.
- Hover / focus = live preview (`apply_mods()` / `set_paint()` on the real car, camera frames the
  part: wheel close-up, rear for spoilers / exhaust / plate, front for lights / grille, side for
  skirts / tint, top for the roof). Enter = buy (`Game.spend`, `EventBus.item_purchased(kind, id,
  price)` with kinds `vehicle_mod`, `vehicle_paint`, `vehicle_repair`; `vehicle_modified` from
  `apply_mods()` or emitted for paint), sounds `wrench` / `spray_paint` + `ui_buy`. Leaving a
  section, tab or the screen reverts every un-bought preview.
- Stat bars recomputed from the spec + mods (`garage_stats.gd`, same accumulation rule as
  `VehicleMods`): top speed (governed top speed x turbo x power^0.33), acceleration (kW per tonne incl.
  armour mass, quicker shifts), braking (g, capped by tyre grip), handling (lateral g from grip,
  downforce at 30 m/s, anti-roll), durability (hp / damage factor). Solid = installed, ghost = preview
  (green better, coral worse). The physics effects are real: measured in `gar_api` (section 8).
- Orbit camera: own `Camera3D` (FOV 52) under the entities root, made current while open and the
  previous camera restored on close; mouse drag rotates, wheel zooms, slow auto-orbit on the
  overview, a WORLD ray keeps it inside the workshop walls.
- Remote (admin, anywhere): `UI.open_screen("mod_garage", {"vehicle": v, "remote": true})` (also
  accepts `"anywhere": true`; `"free": true` makes that session free). The car stays where it is and
  is slowed to a stop.
- Prices are 0 with `Game.flags["free_shopping"]` (admin "unlock all").

## 4. Safehouse (spec 23A)

Interactables at the landmark markers (resolved through the city builder): `Use_Bed` (Sleep),
`Use_Save` (Save game), `Use_Wardrobe` (UI `wardrobe` with `{"shop_id": "safehouse_wardrobe",
"source": "safehouse"}`; the shop system drops its own duplicate point here), `Garage_Spot` on foot
(UI `garage`, stored vehicles) and in a vehicle (store it: fade, vehicle into storage, player
standing in the bay).
- Sleep (bed or the safehouse menu): refused while wanted; fade, `WorldClock.advance_hours(8)`,
  full health, autosave.
- Saves made here go to slot **`manual`** (the pause menu's Load picks the newer of `manual` /
  `quick`) with the garage flag `spawn_inside`: loading such a save teleports the player to
  `Spawn_Inside` (deferred, after every provider loaded). Quick saves elsewhere load where they were made.
- Retrieving a stored vehicle here spawns it on `Garage_Spot` (then the `safehouse_garage`
  driveway, then nearby kerb bays) with the player at the wheel.

## 5. Halcyon Fuel (gas station)

- In-vehicle quick service under the canopy (centre of the four pump markers, radius 6 m + 2.5 m),
  offered only when the vehicle has a flat tyre or less than 75 % health. Cost $35 + 0.35 per
  missing hp up to 75 % + $45 per flat tyre (a fraction of a full repair). Uses the vehicle's
  `fix_tires()` if it ever exists, otherwise `repair()` and then caps the health at 75 % again
  (so glass and lamps are replaced too). `EventBus.item_purchased("vehicle_service", ...)`.
- Pumps: when the city builder exposes the building node, `Pump_1..4` get a `StaticBody3D`
  (Layers.PROP, group `damageable`, box from the mesh bounds) whose `apply_damage` forwards to the
  station. 60 hp (bullets x1, explosions x1, fire x0.6, collisions x0.5, melee x0.25). At 0 the pump
  mesh hides and `Fx.explosion(7.5 m, 240)` + a 14 s `Fx.spawn_fire` go off (chain reactions through
  the neighbouring pumps). Restored after 150 s once the player is more than 90 m away.
- The kiosk counter (`Use_Kiosk`) and staff belong to the shop system (Economy A).

## 6. Vehicle access terminals (spec 26)

| site | where | lists | spawns at |
|---|---|---|---|
| `airport` | 6.5 m beside the `airport_hangar` use point, screen to the apron | every `heli` / `plane` spec | helis: `airport_helipad`, `heli` points, then a free 12 m box on the apron around the helipad; planes: `plane` points, six slots further down the runway (lined up for take-off), hangar `Spawn_Plane`, then a free 15 m box in front of the hangar |
| `marina` | quay at the root of the middle pier (`marina_dock` - 22 m) | every `boat` spec | `boat_spawn`, `boat` points; then free water >= 1.4 m deep |
| `parking_garage` | 3.6 m beside the `parking_garage` use point, screen to the street | every `car` / `bike` / `bicycle` spec + the stored vehicles | kerb `parking` points within 85 m; then a free street spot |

The terminal is the Blender `atm` kiosk (`models/props/atm.glb`, lit screen) with a box collider on
`Layers.WORLD`, `visibility_range_end` 140 m, and a `minimap_blip` (plane / boat / parking icon).
Every registered spec of the kinds is listed; those whose class script or GLB does not exist are
greyed out ("not in the game yet"). Fee: 1.5 % of `spec.price`, $150-$2,500 ($400 for price-0 service
vehicles), 0 with `free_shopping`. One rental per site: renting again despawns the previous one
when nobody uses it. Rented vehicles are `owner_tag "player"` (no theft report), not personal.
The free-spot search (`Sites.free_spots`) exists because the aircraft spawner parks aircraft on
every authored heli / plane point.

Parking garage store point: in-vehicle `Interactable` on the kerb lane in front of the terminal
(radius 6 m) -> same storage as the safehouse.

## 7. Integration notes for neighbours

- **Shop system (A)**: do not create Interactables at `mod_garage/Use_Bay` or under the gas canopy;
  the kiosk, staff and the clothing-side wardrobe are yours. The safehouse wardrobe point of the
  shop system is deduplicated automatically (it prints `wardrobe point ... left to .../Garage/Safehouse/Wardrobe`).
- **Admin menu**: `open_customisation()` already opens `mod_garage` with `{"vehicle", "anywhere",
  "free"}` - supported. `store_current_vehicle()` can show `garage.last_error` instead of "Garage is full".
  Catalogue anywhere: `UI.open_screen("garage", {"mode": "catalogue", "site": "player", "kinds": [...]})`.
- **Phone (Wave 3)**: `deliver_personal_vehicle(Game.get_player_position())`.
- **City builder**: markers come from `get_landmark_marker()`; `get_landmark_node("gas_station")`
  must keep `Pump_1..4` as named descendants. Pumps must not get a second collider from the city.
- **Vehicles**: a `fix_tires()` method on vehicles would let the gas station leave broken glass
  alone (currently `repair()` + health cap).
- Interactables are placed again on `EventBus.game_ready` (`refresh_sites()`), so a city that
  finishes placing buildings late is still matched.

## 8. Tests

```powershell
tools\godot.ps1 -Mode check -Dirs 'gta/code/vehicles,gta/code/world/shops,gta/code/ui/screens,gta/tests'
tools\godot.ps1 -Mode headless -Frames 15000 -TimeoutSec 420 -UserArgs '--test=gar_api','--test-timeout=400','--disable=props,traffic,peds,police,emergency,wildlife,transit,taxi,activities,radio,ambience,respawn'
tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 90 -UserArgs '--test=gar_shots','--test-timeout=80','--gar_only=mod','--disable=props,traffic,peds,police,emergency,wildlife,transit,taxi,activities,radio,ambience,respawn'
tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 90 -UserArgs '--test=gar_shots','--test-timeout=80','--gar_only=list,home,terminal','--disable=props,traffic,peds,police,emergency,wildlife,transit,taxi,activities,radio,ambience,respawn'
```

(`props` / `respawn` were disabled only because those neighbours' scripts had parse errors while
this module was tested; the garage itself does not need them off.)

`gar_api` (headless, real world + city + player, own save slots `gar_test` / `gar_test_home`):
site resolution, drive-in store at the safehouse + retrieve keeps colours / mods / health, personal
vehicle tag, `retrieve_at_site` seats the player, police refused (garage and Torque Garage),
SaveSystem round trip of the storage, Torque Garage bay session (prompt, hold, 9 tabs, orbit camera,
Exit_Bay, camera restored), purchases charge money, stat bars move, body part visible, preview
reverts, paint, free_shopping, refusal without money, **measured** 0-79 km/h and 90-0 km/h on the
runway stock vs modded, repair by damage, gas quick service, catalogue rentals of a car (parking
garage), boat (marina; the boat gets Repair only), helicopter and plane (airport), safehouse sleep
(+8 h, healed, autosave), save point, load spawns inside, wardrobe screen, garage list, pump explosion.
Last run: PASS (109 checks); measured 0-79 km/h 4.50 s -> 3.55 s and 90-0 km/h 34.6 m -> 29.6 m
(sedan, engine_4 + turbo_3 + transmission_3 + brakes_3); helicopter delivered 14 m from the helipad,
jet on the runway start, dinghy at the marina, compact 12 m from the parking garage.

`gar_shots` -> `qa/screenshots/gar_mod_paint.png`, `gar_mod_wheels.png`, `gar_mod_body.png`,
`gar_mod_perf.png`, `gar_list.png`, `gar_catalogue.png`, `gar_safehouse.png`,
`gar_safehouse_menu.png`, `gar_terminal.png`.

## 9. Known limits

- Mods / paint only for `vehicle_class == "car"` (the shared mod registry targets cars).
- The quick service also replaces glass (see section 5).
- Rentals are not saved (dynamic world objects); stored vehicles and the personal vehicle are.
- The mod garage shows no staff animation; the shop system may place its staff NPC at `Staff`.
- Terminal kiosks are the street `atm` prop - no dedicated rental-kiosk asset exists.
- The four helper scripts cost about 290 ms of GDScript compile time at boot (measured: `load()`
  45-100 ms each, `setup_site()` < 3 ms); the boot log prints the split (`[garage] helpers: ...`).
