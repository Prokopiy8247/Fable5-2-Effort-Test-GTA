# SAVE / PERSISTENCE + WORLD INTERACTIONS (Wave 3)

Owner: persistence and interaction programmer. Spec sections 37 (save / load), 23 (doors, use points,
elevators), 23A (safehouse). Skills: see `docs/SKILLS.md`.

| file | what |
|---|---|
| `gta/code/save/save_system.gd` | autoload `SaveSystem`: versioned JSON, atomic write + backup, providers, autosave, boot "continue" |
| `gta/code/world/interaction_system.gd` | system `interactions` (BootManifest): seats, binoculars, vending, ATM + bank, lifts |
| `gta/code/world/interactions/int_state_sit.gd` | player state `int_sit` (sitting) |
| `gta/code/world/interactions/int_state_view.gd` | player state `int_view` (viewpoint binoculars) |
| `gta/code/world/interactions/int_atm_panel.gd` | keyboard ATM panel ("Bay Savings") |
| `gta/code/world/interactions/int_view_overlay.gd` | binocular mask (canvas shader) + zoom / key hints |
| `gta/tests/sav_roundtrip.gd` | full-game round trip of every provider, file safety, vehicle session, autosave, continue, sleep |
| `gta/tests/int3_api.gd` | every use point through the real player path (Interactable -> scanner -> E) |

---------------------------------------------------------------------------------------------------

## 1. Save files

`user://saves/<slot>.json` (Windows: `%APPDATA%\Godot\app_userdata\Halcyon Bay - Free Roam (Fable 5.2 GTA Ultracode)\saves`).

```json
{ "format": "halcyon_bay_save", "version": 2,
  "meta": {"slot", "reason", "saved_unix", "datetime", "playtime", "day", "time", "district", "money", "test", "engine"},
  "money": 12345,
  "providers": {"player": {...}, "weapons": {...}, "clock": {...}, ...} }
```

- **Slots** in use: `quick` (F5 / F9, UI), `manual` (pause menu Save, safehouse save point and bed),
  `autosave` (this module). Any other name works (`save_game("my_slot")`); names with `/ \ ..` are refused.
- **Atomic write**: the JSON is written to `<slot>.json.tmp`, read back and compared byte for byte,
  then the previous main file is rotated to `<slot>.json.bak` and the temp file renamed into place.
  A main file that does not parse is deleted instead of rotated, so it can never overwrite a good backup.
  If the final rename fails the backup is copied back. ~5 KB, ~10 ms per save (measured).
- **Loading** tries `main -> tmp -> bak`; the first file that parses, has the right `format`, a
  `providers` dictionary and `1 <= version <= VERSION` wins. `last_load_info.source` says which one;
  a backup / temp load shows "Save file was damaged - restored the backup".
- **Versioning**: `VERSION = 2`. v1 = the lead's stub format (`version, timestamp, money, providers`) is
  migrated on load (meta synthesised). Files from a newer build are refused (backup tried instead).
- **JSON safety**: every provider blob is sanitised before writing: `Vector2/3/4`, `Color`,
  `Quaternion` -> arrays, packed arrays -> arrays, `StringName` -> String, NaN / INF -> 0 (warning with
  the key path), objects -> null (warning). `JSON.stringify` sorts keys, so the load order is explicit.
- **Missing / extra providers**: a blob whose provider is not registered is kept pending and applied
  the moment the provider registers; it is also *carried* into the next save of this session, so a
  system disabled with `--disable=` does not lose its data. A provider without a blob in the file keeps
  its current state (`last_load_info.missing`).
- **Dynamic world objects are not persisted** (traffic, peds, police, props, pickups, fires): before the
  blobs are applied every system's `reset_for_respawn()` runs (like the respawn flow) and an active
  wanted level is cleared (`Wanted.clear("load")`).

## 2. Providers (load order) and what the round-trip test verified

Load order (`LOAD_ORDER`): settings, clock, weather, skills, wanted, player, weapons, wardrobe, shops,
vehicles, garage, session, interactions, activities, radio, ui_stats, then any other key alphabetically.
World systems that implement `get_save_data` / `load_save_data` but never registered are registered
under their system name at `EventBus.game_ready` (`register_system_providers()`).

`sav_roundtrip` changes everything, saves, changes everything again, loads and compares
(run `150418_603`, PASS 74 checks):

| provider | owner / registered by | fields verified after save -> change -> load |
|---|---|---|
| (top level) money | SaveSystem | money |
| player | PLAYER `player.gd` | position, yaw, health, armor, parachute, scuba, appearance (hair, top colour, bottom, hat) |
| weapons | WEAPONS `weapon_inventory.gd` | owned weapons, ammo (in mag + reserve), attachments (suppressor), finish tint (`finish_sand`), current weapon |
| clock | `WorldClock` | hour, day |
| weather | `Weather` | current weather (+ wetness snapped) |
| skills | `Skills` | all 7 levels, strength max-health bonus re-applied |
| wardrobe | ECONOMY `shop_wardrobe.gd` | owned clothes |
| shops | ECONOMY `shop_system.gd` | unlocked weapon attachments (also closed shops / robbery count) |
| garage | VEHICLE `garage_system.gd` | stored vehicles (spec, colour, health) |
| vehicles | VEHICLE `vehicle_manager.gd` | personal vehicle (spec, position, paint) - no duplicate after load |
| activities | ACTIVITIES `activity_system.gd` | personal records (best score, plays) |
| interactions | this module | bank balance, robbed (out-of-service) ATMs |
| radio | AUDIO `radio_system.gd` (auto-registered by system name) | station |
| ui_stats | UI `ui_stats.gd` | statistics (vehicles stolen) |
| settings | SaveSystem (inner class) | all values written; world settings (`traffic_density`, `ped_density`) restored; controls / audio / display stay machine-local unless `restore_all_settings` (verified both ways) |
| session | SaveSystem (inner class) | play time; the vehicle the player sits in (see 3) |
| wanted | POLICE `Wanted` | nothing stored on purpose: a load clears the wanted level (verified) |

File-safety rows (same run): backup of the previous file, corrupt main -> backup loaded, corrupt main
never rotated over the backup, empty main -> complete temp file loaded, `delete_save` removes
main / bak / tmp, v1 migration, newer version refused, extra provider tolerated + carried into the next
save + delivered to a late provider, missing provider keeps its state, sanitising.

## 3. Session details

- **Vehicle at save time** (`session` provider): driver of the personal vehicle -> re-seated in it after
  the `vehicles` provider recreated it; driver of any other car / bike / boat / landed aircraft -> the
  vehicle is recreated from `VehicleBase.get_save_data()` through `vehicles.spawn_from_save(data, false)`
  and the player re-seated (`enter_vehicle(v, 0, true)`, same frame as the teleport, so nothing gets
  kicked); a passenger is put out at the seat's exit point; a flight (aircraft not on the ground,
  `altitude_agl > 2.5`) is not restored - the player is saved at `last_safe_position` instead.
  Verified: taxi (non-personal) and personal muscle car.
- **Autosave**: slot `autosave` every `autosave_interval` (300 s) of unpaused play. Deferred (retried every
  10 s) while wanted, dead, in a menu / input locked, the respawn flow is busy, in a non-calm player
  state or flying. Toast "Autosaved". Off in test runs unless a test switches it on. Verified: deferred
  while wanted, fires when calm (`meta.reason == "timer"`).
- **Sleep autosave**: the safehouse bed (`garage_safehouse.gd`, VEHICLE/garage owner) sleeps 8 h, heals and
  saves to slot `manual` with the "spawn inside" flag; verified by `sav_roundtrip` (`sleep()` -> save).
- **Continue at boot** (spec: launch directly into free roam): after `EventBus.game_ready` the newest
  valid save (`get_latest_slot()`, by `meta.saved_unix`) is loaded behind the UI loading veil and a toast
  says "Continued: day N, hh:mm". `--new-game` starts fresh. Test runs (`--test=`) never continue unless
  `--continue=<slot>` is passed, and saves written during tests carry `meta.test = true` and are never
  picked by a real session. Verified: `continue_latest()` restores the slot and the selection skips
  test saves. The automatic boot path itself (no `--test`) was run headless only as a boot check.

## 4. API (additions to the lead's stub; all stub names kept)

```gdscript
signal save_failed(slot, reason); signal load_failed(slot, reason); signal autosaved(slot); signal continued(slot)
const VERSION := 2; const FORMAT := "halcyon_bay_save"; const AUTOSAVE_SLOT := "autosave"; const LOAD_ORDER
var autosave_enabled; var autosave_interval; var restore_all_settings; var is_loading
var last_error; var last_load_info; var last_save_info; var continued_from; var save_count; var load_count
register_provider(key, obj) / unregister_provider(key) / has_provider(key) / get_provider_keys()
register_system_providers()
save_game(slot := "quick") -> bool; autosave(reason := "timer") -> bool; load_game(slot := "quick") -> bool
has_save(slot) (main or backup); delete_save(slot) (main + bak + tmp)
slot_path(slot) / backup_path(slot) / temp_path(slot)
list_slots() -> [{slot, meta, valid, source, modified}] newest first; get_slot_info(slot) -> {valid, source, version, meta, modified}
get_latest_slot(include_test := false) -> String; continue_latest(slot := "") -> bool (coroutine)
is_autosave_safe() -> bool
vec3_to_array / array_to_vec3 / color_to_array / array_to_color (now NaN-safe)
```

## 5. Interactions (system `interactions`)

Points are collected at `EventBus.game_ready` from the props system and the city (63 at the moment:
51 seats, 3 vending machines, 4 ATMs, 1 binoculars, 4 lift ends). A pool of **8** `Interactable`s is
moved onto the nearest points within 22 m four times a second, so the player's scanner sees 8 nodes,
not 63. Prompts are dynamic.

| kind | source | use |
|---|---|---|
| seat | props `bench`, `bench_park` (1 seat, 0.12 m in front of the origin), `bus_stop` (2 seats on the shelter bench), `picnic_table` (`Seat_1..4`), tram stops `Use_Bench` (2 seats) | "Sit down" -> player state `int_sit` (body at hip height, collision off, seated pose with the NPC bench tuning); "Stand up" (E), moving or jumping for 0.22 s, any damage or a vehicle heading at the seat stands up in front of the seat. Seats an NPC occupies or a broken bench are not offered |
| binoculars | props `viewpoint_binoculars` (Signal Hill), marker `Use` | "Use binoculars" -> state `int_view`: camera mode `scope` with a FOV override (34 / 20 / 11 / 6.5 deg, wheel or RMB), look clamped to +-72 deg, binocular mask overlay, HUD hidden; E or moving steps away |
| vending | props `vending_machine` | "Buy a Bay Fizz ($4)": `Game.spend`, +12 health (never above max), full stamina, `EventBus.item_purchased("vending", "bay_fizz", 4)`; "not enough cash" otherwise; free with `Game.flags.free_shopping` |
| atm | props `atm` + up to 4 placed with `props.spawn_prop("atm")` 2.5 m beside the `Entrance` of general_store / hospital / clothing_store / police_station when a box test finds the spot and the customer spot free (3 placed now) | "Use ATM (account $N)" -> keyboard panel: 1 withdraw $100, 2 withdraw $500, 3 deposit $100, 4 deposit all, E / Esc leave. Bank account persisted; daily withdrawal limit $2000 (game day); 1 s between transactions. Cash + account is conserved - an ATM never creates money. Banked money is safe from the hospital / arrest fees (they take cash). With a **crowbar or bat** in hand: "Break open the ATM" -> 2.4 s of blows (sparks, metal hits, noise), a $160-420 cash pickup, `Wanted.report_crime("robbery")`, machine out of service for 24 game hours (persisted) |
| lift | hospital: lobby lift doors (asset, Blender local (-0.9 / 0.7, 2.3)) <-> roof bulkhead door (roof surface found by a ray); lighthouse: `Door` <-> `Gallery` markers | "Take the lift to the roof" / "...down to the lobby", "Climb the stairs to the gallery" / "Take the stairs down": input locked, fade, teleport, chime + door sounds, fade in. The hospital roof has the helipad + a parachute pickup (`rooftop_helipad`), the lighthouse gallery a parachute pickup |

Not done here on purpose: **landmark doors** (the city builder animates every `Door_*`), the
**parking structure** (no lift markers -> skipped, as briefed), shop / garage / safehouse use points
(their owners).

Interactions API: `get_points(kind)`, `get_counts()`, `find_point(kind, near, radius)`,
`can_use_point(i)`, `use_point(i, player)`, `sit_at(i)`, `stand_up()`, `start_view(i)`,
`buy_drink(i)`, `open_atm(i)` / `close_atm()`, `deposit(n)` / `withdraw(n)` / `get_bank_balance()` /
`get_withdraw_remaining()`, `rob_atm(i)`, `is_atm_out_of_service(i)`, `ride_lift(i)` (coroutine),
`get_debug_info()`, `set_enabled(on)`, `reset_for_respawn()`, signal `point_used(index, kind)`.

## 6. Integration notes

- Providers: return plain JSON data from `get_save_data()` (the save system sanitises, but strings for
  colours are nicer), tolerate missing keys in `load_save_data()`. A system that only implements the two
  methods is picked up automatically under its system name.
- Pause menu / phone: `SaveSystem.get_latest_slot()` gives the newest real slot (autosave included);
  `get_slot_info(slot).meta` has day / time / district / money for a slot list.
- Player states `int_sit` / `int_view` are registered lazily through `Player.register_state()` (the
  documented extension point) the first time they are needed; public names `sitting` / `binoculars`
  in `EventBus.player_state_changed`.
- The ATM panel locks gameplay input (`Game.lock_input`) and reads `weapon_slot_1..4`, `interact`,
  `pause`, `ui_cancel` in `_input` (consumed), so Esc closes the ATM instead of opening the pause menu.

## 7. Tests

```powershell
tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 420 -UserArgs '--test=sav_roundtrip','--test-timeout=380'
tools\godot.ps1 -Mode headless -Frames 7200 -TimeoutSec 400 -UserArgs '--test=int3_api','--disable=traffic,police','--test-timeout=360'
tools\godot.ps1 -Mode window   -Frames 1200 -TimeoutSec 300 -UserArgs '--test=int3_api','--disable=traffic,police','--shots-only','--test-timeout=280'
```
`sav_roundtrip` backs up every file in `user://saves` and the touched settings first and restores them at
the end, so it never destroys the player's own saves.

## 8. Known limits

- Money moved through the ATM goes through `Game.add_money` / `Game.spend`, so the UI statistics count a
  withdrawal as "money earned" and a deposit as "money spent".
- Lifts are fade-and-teleport rides (no cabin geometry exists in the assets).
- A save taken while flying restores the player on foot at the last safe ground position.
