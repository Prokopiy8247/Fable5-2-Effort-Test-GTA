# POLICE — dispatcher, officers, SWAT, pursuit driving, roadblocks, search, arrests

Owner: police programmer (Wave 2). Contracts: `docs/ARCHITECTURE.md` 6.9 + section 10 (caps),
`docs/ARCHITECTURE_WAVE2.md` W2.1 (ai_controller), W2.2 (brains), W2.3 (Wanted), spec 18 / 18A / 19 / 13A /
49 / 50. Builds on the Wanted autoload (`docs/WANTED.md`), the NPC body + `AiBrainCombat` (`docs/AI.md`),
vehicles (`docs/VEHICLES.md`) and the RoadGraph / WalkGraph (`docs/WORLD.md`). Soft dependencies only:
neighbours are reached through `Game.get_system`, `Game.spawn_npc` / `spawn_vehicle`, groups, `has_method`,
`ResourceLoader.exists`; `AiBrainCombat` is loaded by path at runtime.

| file | class | what it is |
|---|---|---|
| `gta/code/police/police_system.gd` | `PoliceSystem` (Node3D) | world system `police`: dispatcher + the ONE manager loop (vehicle AI ticks, roadblocks, spikes, ambient presence, clean-up), services for brains |
| `gta/code/police/police_vehicle_ai.gd` | `PoliceVehicleAi` (RefCounted) | driving brain of one cruiser / SWAT van = the W2.1 `ai_controller` object |
| `gta/code/police/police_officer_brain.gd` | `PoliceOfficerBrain` (Node) | W2.2 brain of `police_officer` NPCs |
| `gta/code/police/police_swat_brain.gd` | `PoliceSwatBrain` (extends the officer brain) | `police_swat`: armour, carbine / SMG, pairs, aggressive flanking, no arrests |
| `gta/code/police/police_roadblock.gd` | `PoliceRoadblock` (RefCounted) | one roadblock: 2 cruisers, barricades, spike strips, officers |
| `gta/tests/pol_response.gd`, `pol_escape.gd`, `pol_ambient.gd`, `pol_tactics.gd`, `pol_shots.gd`, `pol_bust_flow.gd` | tests | section 9 |
| `gta/tests/pol_route_debug.gd` | debug helper | approach logger: every police car 4x / s (position, pedals, mode, obstacle, contacts, route dump); `--pol_dump` lists the gang hangouts against the named locations (no real checks) |

`wanted_system.gd` / `wanted_config.gd` belong to the Wanted programmer; the police review added one small,
compatible guard to `wanted_system.gd` (late witness calls after an arrest / death, section 6).

---------------------------------------------------------------------------------------------------

## 1. Public API (`Game.get_system("police")`)

```gdscript
func spawn_unit(kind: String, near: Vector3) -> Node3D   # "officer" (NPC), "cruiser" / "swat" (vehicle),
                                                         # "roadblock" (one of its cruisers), "heli" -> null (Wave 3)
func spawn_unit_at(kind: String, xf: Transform3D) -> Node3D   # admin / tests: exactly there, no view rules
func get_units() -> Array          # driven police vehicles + officers not sitting in a vehicle
func clear_units() -> void         # every unit, roadblock, parked police car and officer of this system
func set_enabled(on: bool) -> void # off = clear_units + no spawning
func adopt_patrol(vehicle: Node3D) -> bool   # a driverless police vehicle becomes a patrol unit (crew of 2)
func reset_for_respawn() -> void   # W2.5: clear_units + timers
func get_debug_info() -> Dictionary  # level, units, unit_modes, officers_alive, officer_modes, roadblocks,
                                     # spike_strips, abandoned, station_cars, episode_t, stats{...}
```
Services used by the brains / vehicle AI (stable, may be used by admin tools): `report_sighting(observer, pos,
force := false)` (throttled `Wanted.police_sighting`), `claim_arrest(npc)`, `arrest_in_progress(npc)`,
`complete_arrest(npc)`, `report_resisting(npc)`, `report_brandishing(npc)`, `get_search_point(npc)`,
`get_search_lane_point(unit)`, `random_walk_point(center, dmin, dmax)`, `los(from, to, exclude)`,
`los_static(from, to)`, `spawn_officer(arch, pos, role, vehicle, seat)`, `take_plan_token()`,
`alert_npc_threat(attacker, pos, radius)` (an NPC shot at an officer: officers on foot within `radius` fight back).
Officer brains additionally expose `set_npc_threat(attacker)` / `npc_threat`.
Readable state: `units: Array[PoliceVehicleAi]`, `officers`, `roadblocks`, `trail` (the driving player's
breadcrumbs), `sight_factor`, `stats`.

Groups: every police NPC is in `police` (archetype groups; the minimap draws them, Wanted counts them);
police vehicles of this system are in `police_vehicle` (not in `police`, so the minimap does not draw a car and
its crew twice). `EventBus.police_unit_spawned(unit, kind)` fires for "cruiser", "swat", "officer" (on foot)
and "roadblock".

---------------------------------------------------------------------------------------------------

## 2. Dispatcher

Every 0.5 s (`_dispatch`), driven by `Wanted.get_level_config(level)`:

| ★ | officers | cruisers | SWAT vans | roadblocks | spikes | lethal | arrest |
|---|---|---|---|---|---|---|---|
| 0 | ambient | 2 patrols | – | – | – | – | – |
| 1 | 2 | 1 | 0 | 0 | – | only if armed + aiming / attacked | yes |
| 2 | 4 | 2 | 0 | 0 | – | yes | yes |
| 3 | 8 | 4 | 0 | 1 | – | yes | yes (arrest_first) |
| 4 | 12 | 5 | 1 | 2 | yes | yes | no |
| 5 | 16 | 6 | 2 | 2 (cap) | yes | yes | no |

- **Caps** (ARCHITECTURE 10): at most **16 police NPCs** and **8 driven police vehicles**. A cruiser carries 2
  officers (1 when the level's officer budget is short), a SWAT van up to 4 `police_swat`; vans are dispatched
  first, then cruisers, then foot officers. While a roadblock is due, 2 NPC slots are kept free for it. The
  roadblock cruisers and the parked station cruisers are sleeping set pieces and are counted apart (≤ 2
  roadblocks = 4 parked cruisers).
- **Counting**: only units within 230 m of the reference point count for the targets; a unit flagged hopeless
  (wedged) does not count, so its replacement is dispatched at once. The reference point is
  the player while the police track him and `Wanted.search_center` during SEARCH (new units must not "know"
  where an unseen player went).
- **Pace**: first wave one unit per second for the first 25 s of an episode, afterwards one per
  `respawn_interval` of the level (replacements for losses).
- **Spawning out of view**: `RoadGraph.random_lane_point(ref, 80, 160)` (10 tries, no dirt / runway lanes, not
  in water), rejected when the camera could see it (frustum + < 260 m + no WORLD hit on the line from the camera)
  or a vehicle stands within 7.5 m; scored to prefer spots ahead of a moving player and lanes heading towards
  him. Foot officers: `WalkGraph.random_point(ref, 45, 90)`, also out of view. Units then arrive by road with
  sirens.
- **Ambient presence (0 ★)**: 2 patrol cruisers around the player (random lane walks, obey signals, no siren;
  despawned beyond 215 m unseen / 320 m and replaced), 2 beat officers each at the `police_station` and
  `downtown_plaza` locations while the player is within 190 m (walk-graph strolls around the post, look at the
  player when he comes close), and 2 parked cruisers at the world's `police_car` points in front of the station
  (within 170 m; they can be stolen -> `police_vehicle_theft`, reported by the player module, auto-known).
  Ambient units witness crimes themselves (section 4) and become responders when stars appear.
- **Stand down** (`wanted_cleared` / level 0): ambient patrols return to patrol (up to 2), every other car drives
  off (`leave`) and is despawned out of view (> 90 m unseen or > 240 m); deployed crews are recalled first; foot
  officers walk away and are freed out of view (> 55 m unseen or > 200 m); beat officers go back to their post.
- **Clean-up** (1 Hz): dead officers are freed after 25 s or when unseen > 60 m away (the ragdoll lives on in the
  AI module); responders > 330 m from both the player and the search area are recycled when unseen; a unit that
  is hopelessly stuck / on its roof (4 recoveries in 30 s or 7 s upside down) is despawned when unseen and the
  dispatcher sends a fresh one; a car whose whole crew died becomes an `abandoned` police car (stealable,
  despawned unseen > 140 m away).
- `reset_for_respawn()` (respawn system after death / arrest) clears everything; the ambient presence rebuilds
  around the new position.

---------------------------------------------------------------------------------------------------

## 3. Vehicle AI (`PoliceVehicleAi`, one per car, ticked by the system at 15 Hz < 90 m, 6 Hz beyond)

W2.1: `vehicle.set_meta("ai_controller", ai)`, `vehicle.driver` = the seated officer (a real NPC);
`release_vehicle(vehicle, reason)`: "carjacked" / "abandon" / "crash" -> every seated officer gets out beside his
door (the driver is returned), inputs released, meta removed; "despawn" / "destroyed" -> clean-up only. The
system also releases a car the player takes (`vehicle_stolen`, `player_entered_vehicle` seat 0).

Modes (`get_mode_name()`):

| mode | when | driving |
|---|---|---|
| `patrol` | 0 ★, ambient | random lane walk (~450 m, straight preferred, avoids dirt / alleys / dead ends), 0.82 × limit, stops for red and yellow lights, no siren |
| `pursuit` | wanted and (PURSUIT or seen < 3 s ago) | see below, siren on |
| `search` | wanted, SEARCH | first 12 s ("hot"): straight to `Wanted.search_center` at up to 24 m/s; then cruises to random lane points inside 0.85 × `search_radius` at 10 m/s, replans on arrival / every 22 s |
| `deploy` | target on foot within 34 m (seen), held up by people within 70 m of him, stopped within 60 m (end of the road route, blocked), or his vehicle stopped < 1.5 m/s within 22 m for 1.2 s, or wedged next to him | brakes, then every seated officer gets out (`exit_vehicle`) |
| `deployed` | crew on foot | parked with the light bar on; recalls the crew when the player drives away (> 5 m/s, > 18 m), runs off on foot beyond 80 m during PURSUIT, after 30 s of SEARCH, or when the level clears |
| `board` | recall | officers within 45 m run back (`enter_vehicle`, seat by seat), the driver seat first; stragglers are left as foot officers after 6 s (driver aboard) / 14 s |
| `leave` | stand down | drives away on a lane walk; despawned out of view |
| `hold` | nobody of the crew can drive | brakes; a passenger slides over to the wheel; crew on foot -> `deployed` |

**Pursuit driving**:
1. **Direct predictive pursuit** within 30 m of a driving target (20 m of one on foot) when the straight line is
   clear of static geometry (ray at 0.5 m, so kerb posts / bollards count). Lead point = target + velocity ×
   (distance / speed, ≤ 1.4 s). Tactics (`tactic`, with 1.2 s hysteresis):
   - `chase`: follow close behind, speed = target speed + (distance − 8) × 0.9;
   - `pit` (2 ★+, target 7–24 m/s, we are behind / beside within 15 m): line up beside the rear wheel on our
     side, then steer into the rear quarter panel;
   - `ram` (3 ★+, target < 16 m/s, we come in at right angles to its side): full throttle at the lead point;
   - `box` (target < 6 m/s within 24 m): the pursuing units take front / left / right / rear slots around the
     target (slots assigned by distance every 0.5 s by the system);
   - `approach` (target on foot): drive up and stop about 9 m short.
2. **Trail following** within 140 m of a driving target that the police can see: the system records the
   player's path while he drives (one breadcrumb per 2.5 m, 90 kept = 225 m); the car joins the trail (on it, or
   heading the same way with a clear line) and pure-pursues along it, so it takes the corners the player took;
   speed = target speed + gap × 0.75 (−6..+18 m/s), limited by the trail curvature.
3. **Road route** otherwise (and towards `last_known_position` when unseen): `RoadGraph.find_lane_route` (A* over
   lanes), tried from the lane we are on AND the other same-direction lane of our segment (two-lane approaches
   only turn right from the outer lane), to both lanes of the target's road (the nearest lane alone may force a
   loop round the block); replanned every 3.5–4.3 s or when the target moved > 25 m; at most one plan per physics
   frame for all units (`take_plan_token`). Route speed: lane limit × 1.9 (pursuit) / × 0.82 (calm), curvature
   speed over a braking horizon (6.8 / 3.4 m/s² lateral), red lights crossed at about 9 m/s with the siren.

Shared: pure-pursuit steering normalised by the speed-dependent steering limit (same formula as the traffic
module); the **look-ahead shrinks in bends** until the straight line to the aim point cuts the path by at most
1.4 m (trail and route following; cruisers used to clip kerb bollards / poles on the inside of junctions);
turn-speed limit towards the aim point; braking gain matched to the planned deceleration (the old gentle gain
made cruisers run wide in tight junctions); **K-turn** when the aim is > 115° behind (reverse with opposite lock,
stopped at once when something is right behind); route planning also offers **turning round** (three-point turn
onto the other direction, cost 45 m) instead of a loop round the block / half the island.
**People**: a swept box (car width + 1.1 m, stopping distance long; NPC + player layers) in front of the car ->
speed limit to stop 3.5 m short, full brakes when too fast for it; somebody standing at the bumper who does not
move -> wait 1.2 s (pursuit) / 2.5 s, back up 0.9 s (only if the rear is clear) and steer round him; a cruiser
held up by people within 70 m of a suspect on foot deploys its crew instead. **Obstacle ray** towards the
(swerved) aim point: slower cars -> follow, and swerve to pass when in a hurry; stopped cars -> swerve 2.2 m and
slow; static obstacles only when close. Swerves go to the **left** unless the left is clearly more blocked
(right-hand traffic: the right is the kerb with posts the side rays miss). **Stuck recovery** (wants to move but
< 0.8 m/s for 1.6 s -> reverse 1.4–1.9 s with the opposite lock; a reverse that does not move the car within
0.7 s counts double) -> 4 recoveries in 30 s = hopeless -> replaced out of view. Box slots behind a wall /
bollard line (no static line of sight from the target) are replaced by the rear slot. Self-righting is the
vehicle's own.
**Sight** for the seated crew: 360° through the windows, 72 m × `sight_factor` (weather visibility × daylight),
line of sight on `Layers.SIGHT_MASK` excluding both vehicles; after `Wanted.get_recognition_delay()` of
continuous sight -> `police_sighting` (throttled). Traffic yields to the siren (traffic module).

---------------------------------------------------------------------------------------------------

## 4. Officer brain (`PoliceOfficerBrain`)

Roles: `beat` (ambient post), `crew` (belongs to a car), `foot` (dispatched / left behind), `roadblock`.
Modes (`get_mode_name()`): `idle, patrol, investigate, respond, engage, arrest, search, board, seated, post,
leave`.

- **Sightings**: `npc.can_see(player)` (cone 160°, 55 m × weather / daylight, line of sight) continuously for
  `Wanted.get_recognition_delay()` -> `report_sighting` -> `Wanted.police_sighting(officer, pos)` — also at
  0 ★, which is how crimes in front of police become known: Wanted promotes the pending record (no duplicate
  report). The `saw_crime` event triggers an immediate (deferred, unthrottled) sighting when the officer sees the
  player.
- **0 ★**: beat patrol / post / idle; gunfire or an explosion heard within 75 m is investigated for 20 s (run
  there, weapon drawn, look around); a gun aimed at an officer for 1 s -> `Wanted.report_crime("disturbance",
  pos, {direct_police_witness: true, victim: officer})` + `note_player_attack()` (rate-limited 10 s); weapons
  holstered after 4 s of calm.
- **Wanted, sees the player (or PURSUIT and seen < 6 s / within 25 m)**: `AiBrainCombat.tick` with rules
  `lethal = Wanted.is_lethal_force_authorized()` (non-lethal at 1 ★ unless the player is armed + aiming or
  attacked; lethal from 2 ★), `aggression` 0.45–0.72, cover when lethal (`find_cover_from`, peek, bursts,
  reload, advance / flank, retreat), `hold_fire` while non-lethal, while a colleague is cuffing the suspect, or
  while **a colleague stands in the line of fire** (geometric check against the system's officer list, widened
  like the spread cone: 0.85 m + 8.5 % of the distance, 10 Hz; also for drive-by fire and NPC fights).
  Accuracy multiplier 1.15 at 2 ★, 1.25 from 3 ★ (archetype accuracy 0.58). Officers on foot do not run after a
  car driving away at non-lethal levels.
- **Attacked by an NPC** (gang member ...; the `damaged` event with an NPC attacker that is not police): the
  officer fights that NPC first (own `AiBrainCombat` instance, lethal, 14 s after the last attack, up to 70 m) and
  the system alerts every officer on foot within 35 m (`alert_npc_threat`). Nothing of it is charged to the
  player.
- **Arrest** (levels with `arrest_first`: 1–3 ★, never SWAT): when `Wanted.is_player_arrestable()` and the
  suspect is within 10 m (24 m when he is in sight and standing still, on foot or in a stopped car), ONE officer (system claim; a clearly closer one may take over) walks up with the
  pistol raised (notification "HBPD: Stay where you are - hands up!"), and after **1.8 s within 2.2 m** (3.6 m
  from a suspect seated in a stopped car, standing at the nearer front door; "close enough" when no progress is
  made for 1.5 s within 1.8 m of that range: blocked door, cornered) calls `complete_arrest` -> `Wanted.bust()`. Running away from an officer in contact reports
  `Wanted.report_crime("resisting", pos, {direct_police_witness: true})`, at most every 12 s.
- **PURSUIT, not seen**: runs to `Wanted.last_known_position`, then searches there.
- **SEARCH**: walks / runs between search points the system spreads over the search circle (golden-angle sectors,
  radius 0.12–0.75 × `search_radius`, snapped to the walk network), looks around 1.8–3.6 s at each.
- **Seated passenger** at 3 ★+ with lethal force and the car seeing the player (> 0.8 s) within 38 m: drive-by fire
  (`aim_at` + `fire_at`, pistol, accuracy × 0.55), never straight through the rear window.
- **Board**: runs to its car door when recalled (`board(vehicle, seat)`), re-tries another free seat.

**SWAT** (`PoliceSwatBrain`): 150 hp + the archetype's 100 armour, carbine (55 %) or SMG, aggression 0.78–0.95,
accuracy × 1.1, cover radius 16 m, retreats only below 20 % health, never arrests. Fire teams: the four officers
of a van are paired (`buddy`, opposite `flank_side`); a member that is more than 13 m from its buddy while not in
cover regroups first.

---------------------------------------------------------------------------------------------------

## 5. Roadblocks and spike strips

From 3 ★ while the player drives (> 6 m/s), at most `min(level roadblocks, 2)` at a time, one every 12 s:
the player's likely route is predicted along the lanes (his lane, straight-most continuation, 260 m); the world's
`roadblock` spawn point (21, middle of long arterial / street stretches) that lies on that route 70–245 m ahead
(closest to 125 m) and not in view when nearer than 150 m is used. Build (`PoliceRoadblock.build`):
- two `police_cruiser`s across the road in a V (noses towards the centre line, turned 25° towards the incoming
  player), spawned asleep with the light bar on (they are pushed aside physically when rammed);
- three `roadblock_police` barricades (props system `spawn_prop`: dynamic, they fly when hit) in the middle gap
  and at both road edges;
- 4 ★+: 2–4 `spike_strip`s across the carriageway 17 m in front (props catalogue, or the GLB directly); the system
  checks every 0.1 s each non-police vehicle within reach: a wheel that is over a strip or crossed its line since
  the last check (swept test from the wheel velocity; the strip is only 0.8 m deep) -> `vehicle.pop_tire(i)`;
- 2 (3 at 5 ★) officers crouched behind the cars (`roadblock` role: hold the post, engage from cover when the
  player is within 45 m or seen).
Cleaned up (cars despawned, props / strips freed, officers sent home) when the level drops below 3, after 100 s,
or when the player is > 230 m away — only while nobody sees any part of it (or beyond 280 m).

---------------------------------------------------------------------------------------------------

## 6. Crimes the police module reports

| situation | report |
|---|---|
| officer sees the player commit a crime | `Wanted.police_sighting` (promotes the pending record) |
| running from an arrest | `report_crime("resisting", ..., {direct_police_witness: true})`, ≤ 1 per 12 s |
| gun aimed at an officer at 0 ★ for 1 s | `report_crime("disturbance", ..., {direct_police_witness: true, victim})` + `note_player_attack()` |
| gun aimed at an officer while wanted | `Wanted.note_player_attack()` (lethal force, no arrest) |
| police vehicle destroyed by the player | `report_crime("police_vehicle_destroyed", ..., {direct_police_witness: police within 90 m})` |
| police vehicle stolen | NOT re-reported: the player module reports `police_vehicle_theft` (auto-known in Wanted); the police system only releases the car |

Wanted guard added by the review (`wanted_system.gd`, `report_witnessed`): a civilian who finishes a call about a
crime **without a record** within `PENDING_TTL + WITNESS_CALL_GRACE` (27 s) after an episode ended by an arrest or
the player's death is ignored. The clear drops the records, so such a late call used to start a brand-new episode
right after the arrest (seen as a second bust in `pol_response` part 4). Escapes keep their records and are not
affected; `wnt_core` (99 checks) and `wnt_ingame` still pass.

---------------------------------------------------------------------------------------------------

## 7. Performance

One manager loop; no `_process` per unit; officers are ticked by the PedSystem (10 / 3.3 / 1 Hz by tier); vehicle
AIs at 15 / 6 Hz; one obstacle ray + one people box query per car tick (+2 side rays only when blocked; ray queries
are built once per exclusion set, no per-tick arrays); friendly-fire check = plain geometry over <= 16 officers,
10 Hz per shooting officer; sight rays 5 Hz per car;
A* plans rate-limited to one per physics frame; trail = 90 points. GLBs of the cruiser / van / spike strip /
barricade are requested on a loader thread at setup (the first dispatch would otherwise hitch 20–80 ms).
Measured (headless, `pol_response`, up to 14 officers + 5 vehicles): manager loop ≈ 0.05–0.13 ms per physics
frame on average (`stats.tick_us`, after the review: 46–125 µs over four runs), decayed peaks 0.9–2.3 ms on frames
that spawn a unit (vehicle build + NPC spawn in the neighbour modules).

---------------------------------------------------------------------------------------------------

## 8. Integration notes

- **Admin / debug**: `spawn_unit(kind, Game.get_player_position())` for "officer" / "cruiser" / "swat" /
  "roadblock" ("heli" returns null until the Wave 3 helicopter); `clear_units()`, `set_enabled()`,
  `get_debug_info()`.
- **Respawn**: `reset_for_respawn()` is called through the systems list.
- **Traffic**: police cars are foreign vehicles for traffic (projected onto lanes, yielded to with sirens). A
  police car traffic spawned could be handed over with `adopt_patrol(vehicle)` (releases a foreign controller with
  "despawn" first).
- **Minimap**: draws group `police` (NPCs, seated crews included) and `Wanted.search_radius`.
- **AI module**: officer brains use `AiBrainCombat` (loaded by path); police NPCs are `persistent` (the police
  system frees them). Without the peds system no officer can be spawned (one warning) and the police stay away.
- **Wanted**: all W2.3 members exist; one small guard was added (section 6).
- **Gangs** (AI module): gang members are provoked by any gunshot within 28 m and by any damage, so a police
  gunfight next to a hangout (one sits on the street beside the downtown plaza) turns into a police - gang
  shoot-out; officers now fight back (section 4). See the requests to the lead in the review notes.

---------------------------------------------------------------------------------------------------

## 9. Tests

```powershell
$dis = '--disable=traffic,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
tools\godot.ps1 -Mode check -Dirs 'gta/code/police,gta/tests'
tools\godot.ps1 -Mode headless -Frames 26000 -TimeoutSec 420 -UserArgs '--test=pol_response','--test-timeout=410','--seed=21',$dis
tools\godot.ps1 -Mode headless -Frames 9000  -TimeoutSec 400 -UserArgs '--test=pol_escape','--test-timeout=380','--seed=5',$dis
tools\godot.ps1 -Mode headless -Frames 22000 -TimeoutSec 420 -UserArgs '--test=pol_tactics','--test-timeout=410','--seed=12',$dis
tools\godot.ps1 -Mode headless -Frames 9000  -TimeoutSec 360 -UserArgs '--test=pol_bust_flow','--test-timeout=340','--seed=21','--disable=traffic,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,debug'
tools\godot.ps1 -Mode headless -Frames 9000  -TimeoutSec 400 -UserArgs '--test=pol_ambient','--test-timeout=380','--seed=8','--disable=emergency,wildlife,transit,taxi,activities,radio,ambience,respawn,debug'
tools\godot.ps1 -Mode window   -Frames 600   -TimeoutSec 150 -UserArgs '--test=pol_shots','--pol_shot=A','--test-timeout=120','--seed=4',$dis
tools\godot.ps1 -Mode window   -Frames 600   -TimeoutSec 150 -UserArgs '--test=pol_shots','--pol_shot=B','--test-timeout=120','--seed=4',$dis
tools\godot.ps1 -Mode window   -Frames 600   -TimeoutSec 150 -UserArgs '--test=pol_shots','--pol_shot=C','--test-timeout=120','--seed=4',$dis
tools\godot.ps1 -Mode window   -Frames 600   -TimeoutSec 150 -UserArgs '--test=pol_shots','--pol_shot=D','--test-timeout=120','--seed=4',$dis
```
(`--pol_part=1,2,...` runs single parts of `pol_response`. `respawn` is disabled so an arrest does not move the
player to the station between parts; the test calls `reset_for_respawn()` itself. Traffic is off to keep the
scenarios repeatable.)

| test | covers |
|---|---|
| `pol_response` part 1 | 1 ★, idle unarmed player downtown: a cruiser arrives by road, a crew deploys, an officer reaches him (< 30 s) and the arrest completes (`Wanted.bust`, level cleared "busted") |
| part 2 | 2 ★, armed + aiming player in front of the hospital (no gang hangout in earshot): officers open fire, the player takes damage |
| part 3 | 3 ★, the player drives a sedan east on the Coral Ring (test autopilot through Input actions): a roadblock appears on his route ahead (2 cruisers, barricades, officers), ≥ 2 cruisers reach him |
| part 4 | 2 ★ chase on the ring: pursuit tactics are used (PIT / box), cruisers stay within 30 m for most of it; the player stops (or is boxed in) -> crews deploy -> arrest at the car door |
| part 5 | 5 ★: SWAT vans with `police_swat` arrive; caps (≤ 16 officers, ≤ 8 vehicles) hold |
| part 6 | crews deployed near the player on foot run back to their cruiser when he drives off and the cruiser resumes |
| all parts | no officer is ever hurt by police fire (friendly fire); every crime that becomes known and every hit on police / gang NPCs is logged (`CRIME known`, `POLICE hurt`, `GANG hurt`) |
| `pol_escape` | 2 ★ found downtown -> teleported out of sight -> SEARCH centred on the last known position, units search there, escape progress grows; with `debug_time_scale` the level clears ("escaped") and units stand down; lost again -> an officer in front of the player -> PURSUIT resumes, progress reset |
| `pol_tactics` S | 4 ★ roadblock with spike strips on the ring; the player's sedan drives over them -> tyres pop |
| `pol_tactics` D | 3 ★ chase: passenger officers fire from the moving cruiser |
| `pol_tactics` W | 4 ★ on foot: the SWAT van arrives, tactical officers are paired (buddy), armoured (150 hp + armour) and open fire |
| `pol_tactics` R | 1 ★: an officer starts cuffing the idle player, who sprints away -> `resisting` is reported (source "police") and he gets away |
| `pol_tactics` G | a gang member shoots an officer: that officer and a colleague nearby both take him on and fire back; nothing is charged to the player; the system counted the threat |
| `pol_tactics` P | a frozen (brainless, cowering) pedestrian stands in the lane 32 m ahead of a responding cruiser: it stops short, gets round him without any vehicle damage to him |
| `pol_tactics` X | W2.1 `release_vehicle`: "carjacked" returns the driver and puts the whole crew out (driver null, no meta); "despawn" frees the seated crew (empty seats); both units leave the dispatcher |
| `pol_tactics` L | a late witness call after `Wanted.bust()` starts no new episode; after the 27 s window an independent observation counts again |
| `pol_ambient` | every system incl. traffic: 2 patrol cruisers drive around at 0 ★, 4 beat officers near the station / plaza, 2 parked station cruisers; pistol shots in front of a beat officer are known at once (source "police"), ambient officers respond and calm down after the clear; taking a parked cruiser = `police_vehicle_theft` (2 ★) and the police system lets go of the car |
| `pol_bust_flow` | the REAL respawn system enabled: 1 ★ arrest at the plaza -> released at the police station (fine charged, level 0), the episode's units dropped by `reset_for_respawn`, the ambient presence rebuilt around the station; then 2 ★ and killed -> hospital, level 0, no pursuing unit left |
| `pol_shots` | `qa/screenshots/pol_chase.png`, `pol_chase_b.png` (3 ★ chase, the driver looks back at the cruisers: right behind / alongside for a PIT, drive-by casings), `pol_roadblock.png` (4 ★ roadblock: two cruisers, barricades, spike strips across the road), `pol_cover_fire.png` (roadblock officers firing from behind the cars: muzzle flash + tracer), `pol_arrest.png` (C: 1 ★, officer with the pistol raised cuffing the player, "HBPD" warning), `pol_swat.png` (D: 4 ★, SWAT van pulled up, the team firing from beside it) |

---------------------------------------------------------------------------------------------------

## 10. Known limits

- No police helicopter (Wave 3): `spawn_unit("heli")` returns null; the 3 ★+ "heli" entry of the level table is
  ignored.
- Officers do not commandeer civilian vehicles when their car is lost (spec stretch); they continue on foot.
- Drive-by fire from SWAT vans is not used (carbines are not drive-by weapons).
- Units spawned for a new episode need 5–15 s to arrive; Wanted's lost-contact grace (3–5 s) often turns a
  cheat-started episode into SEARCH before they get there — they then search the last known area (by design of
  the Wanted model: escape needs real loss of sight).
- Pursuit driving is physics-based and can still lose cars in tight corners / pile-ups; hopeless units are
  replaced out of view rather than teleported.
- Roadblocks only appear for a driving player and only at the 21 world roadblock points.
- Police vs gang: gang members join any gunfight near their hangout (AI module rule) and the officers fight back;
  around the downtown plaza this turns 2 ★+ scenes into three-way shoot-outs. Officers still run over nobody on
  purpose, but a gang member who runs into a moving cruiser in a fight can be hit.
- Police PIT / box contacts are charged to the player as `collision_major` by the vehicle module when he was the
  faster car (VehicleCrime); harmless at the non-violent 3-star cap, but not intended.
- A cruiser can still wedge itself on a kerb / building corner in a tight turn; it is replaced out of view
  (faster now) but stays visibly stuck while the player looks at it.
- Chase scenarios are physics-driven and not bit-for-bit repeatable (the same seed gives different runs).

---------------------------------------------------------------------------------------------------

## 11. Independent review (Wave 2) — what was changed and why

Found by running every test repeatedly (the suite failed a different part on most runs) and reading the logs:
1. **Friendly fire**: officers shot (and killed) colleagues standing in their line of fire -> line-of-fire hold.
2. **Gang shoot-outs**: a cruiser ran over a gang member standing on the street next to the downtown plaza, police
   gunfire provoked the gang; officers were shot and never fought back -> NPC-threat retaliation + people box.
3. **Pedestrians**: the single centre ray missed people beside the bumper line; gentle braking -> swept people box,
   full brakes, wait / back up / steer round, deploy instead of manoeuvring in crowds.
4. **Wedged cruisers**: corner cutting into kerb bollards (right-hand swerve, long look-ahead in bends, weak
   braking), reversing into things -> left swerve, bend-limited look-ahead, matched braking, rear checks, box slots
   must be reachable, failed reverses count double, hopeless units are replaced at once.
5. **Route loops**: a cruiser pointing the wrong way planned a loop round half the island -> U-turn start option.
6. **Second arrest**: late witness calls started a new episode right after a bust -> Wanted guard (section 6).
7. **release_vehicle("despawn")** left the seated crew behind in seats the vehicle had already forgotten -> the
   crew is freed; `adopt_patrol` could exceed the officer cap by one.
8. **Per-tick allocations**: obstacle / rear rays built a new exclude array every tick -> cached queries.
Tests added: `pol_tactics` G / P / X / L, `pol_shots` C / D, `pol_bust_flow` (real respawn system), friendly-fire
check over all of `pol_response`; `pol_response` part 2 moved to the hospital (no gang in earshot). After the fixes
`pol_response` passed 4 runs in a row (seeds 5 / 21 / 33 / 7), see `qa/progress/review_police.md` for the logs.
