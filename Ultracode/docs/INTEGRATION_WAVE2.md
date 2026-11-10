# Integration notes after Wave 2

Written by the lead on 2026-11-10 after integrating Wave 2 (police and player reviews were still
finishing when this was written; their files may still change slightly).

## What runs now

Boot (headless ~4–5 s, windowed ~8.5 s) instantiates: `world, environment, city, vehicles,
pickups, props, traffic, peds, police, shops, garage, radio, ambience, respawn, debug` + player.
Main now **skips a system whose script has parse errors** (push_error) instead of aborting the boot.

- City: 175 buildings (18 landmarks, 123 generic, 30 fillers, 4 pier pieces) from 48 catalogue
  types, 0 empty lots, landmark markers in world space (`Game.get_system("city")` W2.4 API),
  automatic doors, 2 ladders (radio mast, pier), lit windows / neon at night.
- Dressing: street furniture, traffic lights driven by the road graph, street lamps registered
  with the environment lights, vegetation from the WORLD nature kinds (Signal Hill is a wood),
  breakables / dynamic props with rigid-body activation, set pieces (wreck, docks, park, airport,
  stunt ramps), fire-escape ladders.
- Traffic (≤ 22 moving + parked), pedestrians (≤ 40) with witnesses / panic / gangs, wanted
  0–5 with witness reports and pursuit / search / escape, police dispatcher with cruisers, foot
  officers, SWAT, roadblocks, arrests (helicopter: NOT yet — Wave 3).
- Aircraft (`Helicopter`, `VehiclePlane` — **not** `Plane`, which is a Godot built-in type),
  bikes (`Bike`), boats (`Boat`), plus `jetski` and `dinghy` (confirmed as roster additions).
- Player: traversal (vault / mantle / ladders / roll), melee combos / block / heavy, carjacking,
  drive-by, death → hospital and arrest → police station (respawn system), cover, stealth,
  takedowns.
- Shops (weapons + workbench, clothing, wardrobe, barber, general store, robbery), garage
  (store / retrieve, personal vehicle), mod garage (repair, paint, wheels, body, performance),
  safehouse (sleep / save / wardrobe), gas station, rental terminals (airport / marina / parking).
- Admin menu (F1) and debug overlay.

Lead integration test `int_slice` passes headless and windowed (`qa/screenshots/int_*.png`).

## Lead changes in this integration

- `project.godot`: occlusion culling enabled (the city's occluder boxes now work).
- `InputSetup`: new actions `walk` (Left Alt) and `radio_wheel` (Y).
- `Game.request_time_scale` accepts 0.05–2.0; slow-motion requests (< 1) win over fast-forward.
- `Dmg.caused_by_player` no longer errors on vehicle-group nodes without `is_player_driven`.
- AI fixes: `ai_brain_civilian.gd` TALK no longer reads a partner that left the tree;
  `ai_brain_gang.gd` no longer calls `bool(null)` on `is_dead`. ~40 other places still use
  `bool(x.get("is_dead"))` — fine for NPCs / player, but use `x.get("is_dead") == true` for any
  node that might not have the property.
- `tools/godot.ps1`: windowed runs wait until the shared GPU is ≤ 65 % (peak of 3 samples) —
  other benchmark sessions use the same GPU. Expect windowed runs to queue for a while.

## Open items assigned to Wave 3 owners

| Owner | Item |
|---|---|
| UI | Minimap / map search circle should use `Wanted.search_center`; aircraft altimeter should read `altitude_agl`; stealth indicator (+ optional noise ring) on `player_state_changed('stealth')`; drive-by "out of arc" reticle; parachute and hat glyphs in `UiIcons`; debug overlay coupling (`UI/Root/Debug`) |
| AI / wildlife / emergency | `ped_system.count_near(pos, radius)` for Wanted indirect reports; brain event `carjacked`; takedown `info.knockout` handling (stay down ~30 s, dazed on waking); silent harm witnessed by sight only; awareness double-counts stealth (ai_senses multiplies visibility_factor again by in_stealth / crouch / daylight); exit-time leak notice when props + peds run together (bench sitting) |
| Police (wave 3) | helicopter unit (`spawn_unit('heli')`); decide whether silent takedowns of officers nobody saw stay pending |
| Player (wave 3) | step-up gap for edges 0.107–0.157 m (`move_body` / `_try_step_up`); leaning ladders (`line_bottom` → `line_top` metas, radio mast leans 0.7 m); props ladder `Ladder_0` at (104.6, 1.4, 253.7) cannot be topped out; `Player.teleport()` while touching a vehicle kicks it (bikes / boats guard against it now, fix at the source); rider pose for jetski via `vehicle.get_rider_pose(seat)`; no door sounds for bike / bicycle / boat |
| Weapons (owned by the player wave-3 programmer for this item) | holder hook `get_shoot_origin()` and a public "drop held throwable" API (blind fire, drive-by drops) |
| Save / skills | vehicle XP hook (base class gives driving XP to every class; aircraft suppress it via a private field) |
| Activities | spawn `checkpoint_arch` with `props.spawn_prop()` only for the duration of a race (cannot stand permanently at race_start) |
| Transit | `call_taxi(pos)` is already called by the admin menu — keep that signature |
| Debug (lead) | `set_density` double-applies density; "repair street furniture" → `props.respawn_all()` |

## Facts worth knowing

- Generic buildings sit on the street edge of their lots (docs/CITY.md); back halves of deep
  downtown lots are empty paving.
- Doors have no collision. Shop windows are opaque from outside.
- Garage mods / paint only for class `car`; bikes, boats, aircraft get repair only.
- Aircraft have no autorotation and no water collision (they sink). Helicopter autopilot helpers:
  `fly_to`, `hover_at`, `orbit` (docs/AIRCRAFT.md). `heli_police` has `Seat_Gunner_L/R` markers
  that `_build_seats` currently ignores.
- Bikes lean visually only; the bicycle cannot be destroyed (≤ 50 % damage, by design).
- Every headless run ends with the harmless engine notice about leaked ObjectDB instances.
