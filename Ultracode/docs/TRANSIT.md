# HALCYON BAY - TRANSIT (taxi service + Bay Tram)

Owner: transit programmer (Wave 3, TRAFFIC module). Spec 29A ("Taxi passenger service", "Trains / transit"),
spec 12. Contracts: `docs/ARCHITECTURE.md` (4, 6.8), `docs/ARCHITECTURE_WAVE2.md` (W2.1), `docs/TRAFFIC.md`
(driver + `ai_controller`), `docs/WORLD.md` (transit path / stops, RoadGraph), `docs/MISC_PROPS.md` (tram GLB),
`docs/PLAYER.md` section 4 (vehicle-seat contract). Soft dependencies only (`Game.get_system`, `has_method`,
untyped access to the traffic module's `TrafficDriver` / `TrafficLanes`).

---------------------------------------------------------------------------------------------------

## 1. Files

| file | class | what it is |
|---|---|---|
| `gta/code/traffic/transit_system.gd` | `TransitSystem` (Node3D) | world system `transit`: ONE manager loop for both trams (motion, stops, doors, junction stop lines, obstacles, towing, riders) |
| `gta/code/traffic/transit_tram.gd` | `TransitTram` (AnimatableBody3D) | one passive tram: model, collision boxes, door leaves, seats (vehicle-seat contract), interactables, audio, lamps |
| `gta/code/traffic/transit_path.gd` | `TransitPath` (RefCounted) | the closed loop as an arc-length polyline: sample / tangent / project / lateral, curve speed profile |
| `gta/code/traffic/taxi_system.gd` | `TaxiSystem` (Node) | world system `taxi`: call / hail / stand, steering a traffic cab, fares, skip, interactables, blip |
| `gta/code/traffic/taxi_destinations.gd` | `TaxiDestinations` (RefCounted) | named places by district, kerb drop-off points, route length |
| `gta/code/ui/screens/taxi_screen.gd` | - (extends `UiScreen`) | `UI.SCREENS["taxi"]`: destination picker with fares |
| `gta/tests/trn_tram.gd`, `trn_taxi.gd`, `trn_shots.gd` | - | tests (section 6) |

---------------------------------------------------------------------------------------------------

## 2. Bay Tram (`Game.get_system("transit")`)

**Line**: `World.get_transit_path()` - 791 m clockwise loop on the inner traffic lane of Foundry Street ->
Coral Ring / Sandpiper Avenue -> Tideline Street -> Marlin Avenue, 14 m corners. The rails are already part of
the world city mesh (`world_citymesh._rails()`, steel strips at +-0.72 m); no `rail_straight` tiles were added
(they would double the rails). No overhead wire: `rail_post` stands 2.4 m left of the track, i.e. in the
opposite traffic lane of these 11 m streets.

**Stops**: `World.get_transit_stops()` - `tram_stop_1` "Plaza" (32.5, -103.2), `tram_stop_2` "Sandpiper"
(118, 23.5), `tram_stop_3` "Tideline" (-70, 68.3); the doors (right side) face the platforms.

**Trams**: 2 (`TRAM_COUNT`), started at stop 1 and at the stop nearest half a loop away (stop 3). Each one:
- `AnimatableBody3D` (sync_to_physics) on `Layers.VEHICLE`, mask 0: kinematic, never pushed, cannot be derailed;
  NOT in group `vehicle` (the player's enter-vehicle key and carjacking ignore it: not stealable). In groups
  `tram` and `minimap_blip` (`blip_icon` `tram`).
- Collision: the manifest's 12 `collision_boxes` (floor, roof, walls, cab ends) + 4 door-opening boxes; the two
  right-hand door boxes switch off while the doors are open (`door < 0.3`).
- Placement: the bogie points `s +- 5.9 m` lie on the loop polyline, the body sits on their chord (origin at
  rail level, path y 2.53). On the 14 m corners the rigid 18.4 m car sweeps ~1.3 m inside / ~1.7 m outside the
  rails (inherent to a rigid car on that radius).
- Doors: `Door_R1_A/B`, `Door_R2_A/B` slide 0.7 m apart along the body (smoothstep, 1.8 s).
- Audio: `tram_loop` (3D loop, pitch / volume by speed, only within 75 m), `tram_bell` on arrival, departure and
  as a warning when people / vehicles block the rails (every 4.5 s), `door_open` / `door_close` at stops.
- Lamps: at night (`WorldClock.get_daylight() < 0.35`) the `M_Headlight` / `M_Taillight` surfaces get emissive
  overrides and an interior OmniLight (no shadows) switches on within 150 m of the player.

**Driving** (`TransitSystem._drive`, per physics frame, both trams in one loop): target speed = min of
- cruise `V_MAX` 11 m/s;
- the curve profile `TransitPath.build_profile`: `sqrt(A_LAT 1.3 * R)` (~4.3 m/s in the 14 m corners), held over
  the whole car length, reachable with 1.25 m/s^2 of braking;
- braking into the next stop (`sqrt(2 * 1.25 * d)`), arrival when within 0.4 m and < 0.5 m/s;
- junction stop lines: the end of every RoadGraph lane the rails follow into a 3+ leg junction (12 found),
  nose 1.2 m behind the line. Red = stop; yellow = stop if <= 2.0 m/s^2 suffices; green with < 2.5 s left and
  standing / slow = wait for the next green; minor approaches (`lane.yield`) creep at <= 4 m/s and wait while
  a vehicle moves in the junction circle; "do not block the box": a standing obstacle just past the junction
  (closer than the junction + one car length) keeps the tram at the line. A late stop uses the deceleration it
  needs (no emergency spike); a line it can no longer stop for is committed to;
- obstacles: box queries (2.9 x 1.7 m, 7.5 m pieces following the rails) from the nose, 16..64 m ahead (longer
  at speed and before junctions), 20 Hz within 160 m, 5 Hz beyond; mask VEHICLE | PLAYER | NPC | PROP. Vehicles
  use their oriented `body_aabb`, the other tram its half length, people 0.4 m. Following: `min(sqrt(v_l^2 +
  2*2.0*gap'), gap'/1.6 s + 0.4 v_l)` with a 3 m standstill gap; the integrator brakes up to 3.6 m/s^2.
  Ignored: static bodies (the world, compound street-furniture bodies), people / asleep props standing on a
  sidewalk inside a corner (`ground_height > road + 0.07`), the player riding the other tram.
- Blocked by a vehicle for 40 s (`TOW_TIME`): a driverless car or a traffic car that nobody looks at (not in the
  camera frustum within 200 m, > 30 m from the player, never the player's / personal vehicle, never police /
  emergency crews) is towed: `traffic.release_vehicle(v, "despawn")` + `vehicles.despawn_vehicle(v)`.

**Stops**: 12 s dwell (`DWELL`), doors open after 0.5 s, close 1.8 s before departure; the doors stay open up to
10 s longer while the player stands in / right at a doorway.

**Riding** (free):
- *Board the tram* (interact, outside an open right door, the player on the road beside the car - the platform
  edge is ~5 m away behind the parking lane and the sidewalk): the player is put on the floor at the vestibule
  `Stand_1` / `Stand_3`. The player's step-up (0.32 m) is lower than the 0.35 m floor, so walking in from the
  road needs the prompt (jumping in works too).
- *Standing* riders are ordinary on-foot players on the moving kinematic floor (`Player.platform_floor_layers`
  includes VEHICLE): they walk around inside; the closed door boxes keep them in between stops.
- *Sit down* (interact at a seat, `Seat_1..4`): `player.enter_vehicle(tram, seat, instant_if_moving)` - the
  PLAYER vehicle state seats them on the marker (seated pose, vehicle chase camera, HUD card "Tram").
  *Stand up* = the enter-vehicle key (an in-vehicle Interactable on that action, so the player's own exit
  handling stands back) -> `player.teleport(aisle point)` (instant: the vehicle state's EXIT slide is in world
  space and would leave the player behind in a moving car).
- *Get off* (interact inside an open door) puts the player on the road beside the door; walking out of the open
  door works as well.
- Toasts for a rider: "Next stop: Sandpiper" on departure, "Sandpiper - doors open" on arrival.

**API** (`Game.get_system("transit")`): `set_enabled(on)` (off: the player is put beside the car, trams freed;
on: respawned at their stops), `reset_for_respawn()`, `get_trams() -> Array`, `get_stops() -> Array[Dictionary]`
`{name, label, s, position, platform}`, `get_path_length()`, `get_player_tram() -> Node3D`, `is_player_aboard()`,
`get_tram_info(i) -> Dictionary`, `get_debug_info() -> Dictionary` (+ `stats`: arrivals, departures, loops,
boardings, alightings, seated, signal_holds, obstacle_holds, emergency_brakes, tows, bells, top_speed,
static_in_corridor), `board(tram, door)`, `alight(tram, door)`, `sit(tram, seat)`, `stand_up(tram)`.
`--trn_log` prints hard brakes and static colliders found inside the rail corridor as `TRANSIT:` lines.

Not persisted (SaveSystem-safe): after a load the trams continue from wherever they are.

---------------------------------------------------------------------------------------------------

## 3. Taxi service (`Game.get_system("taxi")`)

**The cab is a real traffic car.** A `taxi` of the traffic system with its seated `taxi_driver` (TrafficDummy +
pooled humanoid visual) keeps being driven by the traffic manager with all of its rules: signals, right of way
(permits), following, obstacle boxes, turn speeds, siren yielding, reactions (a driver may still flee gunfire -
the job then ends). The taxi system runs right after it each physics frame (`process_physics_priority = 1`) and
only steers the job through public fields of its `TrafficDriver`:
- route: whenever the driver is on a lane that is not the target lane, `next_lane` / `conn` are set to the next
  lane of `RoadGraph.find_lane_route(lane, target_lane)` (re-planned after forced lane changes / reroutes);
- stopping: `speed_factor` scales the free speed onto a 1.7 m/s^2 braking curve to the kerb point, starting on
  the lane before the target lane; within the stopping distance `brake_t` forces the hard stop; `lateral_target`
  pulls over to the kerb (0.55 m beside a parking lane, 1.1 m on the outer arterial lane, 0.9 m otherwise);
  waiting = `brake_t` + `speed_factor 0`;
- no voluntary lane changes while hired (`lc_cd`), no hopeless-despawn (`prog_t` reset);
- a small overshoot is stopped a little further along the same kerb instead of driving round the block.
The cab's roof sign is switched off while hired (`set_taxi_sign(false)`), back on afterwards.

**Getting a cab**
- `call_taxi(near := player)` (phone, admin "Call a taxi", the *Call a cab* point at `taxi_stand`): a free cab of
  the traffic within 22..160 m answers, else one is spawned 65..150 m away out of view
  (`traffic.spawn_traffic_vehicle(lane, off, "taxi")`; at the traffic cap the farthest unseen ordinary car makes
  room). Pick-up point = the kerb lane whose right side faces the caller (`TaxiDestinations.drop_point`). The cab
  honks on arrival ("Your cab is here"), waits 75 s (or until the player is 120 m away), then leaves. A minimap
  blip (`minimap_blip`, icon `taxi`, clamped to the rim) marks it until the player is aboard. If the cab is
  taken off the road on its way (despawn / crash) one replacement is sent.
- Hailing: on foot within 9 m of a lane, a free cab within 45 m that is coming (or within 16 m) shows *Hail the
  cab* (interact) -> it pulls over at the kerb beside the player.
- Riding along in any free traffic cab (hold the enter-vehicle key at its rear door) hires it too.
- *Get in the cab* (interact, near the waiting cab): `player.enter_vehicle(cab, seat)` - a rear seat with the
  nearest door. Tapping the enter-vehicle key instead is a normal carjack (traffic module) and ends the job.

**Riding**
- The taxi screen (`UI.open_screen("taxi")`) lists the map waypoint (if set) and every named place the world
  publishes as a map label (25: shops, services, plaza, park, beach, marina, lighthouse, hill, airport ...)
  with district tabs (Q / E), distance, trip time and fare. Esc keeps the player in the waiting cab (*Choose a
  destination* reopens it, the enter-vehicle key gets out for free).
- Fare = $8 + $34 per km of the lane route (quote fixed when the destination is chosen; free with the admin
  `free_shopping` flag). The driver refuses a destination the player cannot pay ("The driver wants to see $N
  first").
- While riding: *Stop here* on the enter-vehicle key (prompt shows the skip key and the fare) pulls over at the
  next safe kerb spot and charges the distance so far (never more than the quote); getting out any other way
  (bailing) charges the distance too. Skip = the `skip` action (Enter): fade out, the cab is teleported to the
  drop-off (`VehicleBase.teleport`, `TrafficDriver.place`), the clock advances by the trip time
  (`WorldClock.advance_hours`), fade in.
- On arrival the fare is charged (`Game.spend`, `EventBus.item_purchased("service", "taxi_fare", price)`, toast)
  and the passenger gets out at the kerb; the cab is released to ordinary traffic.
- If the player had no waypoint, the destination becomes the waypoint for the ride (GPS route on the minimap)
  and is cleared afterwards.

**API**: `call_taxi(near := Vector3.INF) -> bool` (frozen signature, silent on success), `request_taxi(near)`,
`cancel_taxi(reason := "")`, `board()`, `get_destinations() -> Array[Dictionary]`, `estimate_fare(metres) -> int`,
`choose_destination(id_or_entry) -> bool`, `skip_ride() -> bool`, `stop_here() -> bool`, `is_player_in_taxi()`,
`get_taxi()`, `get_state_name()` (`idle dispatch waiting choosing ride stopping arrived`), `get_job_info()`,
`get_debug_info()`, `set_enabled(on)`, `reset_for_respawn()`. Not persisted.

Taxi driving as a paid side activity: not built (optional in the spec).

---------------------------------------------------------------------------------------------------

## 4. Integration notes

- **Phone (Wave 3)**: `Game.get_system("taxi").call_taxi(Game.get_player_position())` returns true when a cab
  is on its way (announce it yourself, the system is silent); `get_job_info()["eta"]` (s) for a status line.
- **Admin**: `debug_system.call_taxi()` already works; the Trams toggle uses `set_enabled`.
- **Minimap**: trams and the called cab are `minimap_blip` nodes (UI already draws that group).
- **Radio**: a seated tram rider counts as "in a vehicle" (`vehicle_class` "tram"), so the radio plays; the
  audio owner may add "tram" to `NO_RADIO_CLASSES`.

---------------------------------------------------------------------------------------------------

## 5. Known limits

- The tram's rigid body sweeps over the inside corner of the sidewalk in the four 14 m corners; at two corners
  street-furniture poles of the props system stand inside that sweep (0.5-0.7 m inside the rail arc, near
  (-114, -98.6) and (114, 63.6)) and the car passes through them visually (they are static, the tram ignores
  them). Fix belongs to the dressing (keep the inside of the tram corners clear) or a larger `TRAM_RADIUS`.
- Traffic cars do not see the tram in their lane-occupancy table (it lists the VehicleManager's RigidBody3D
  vehicles); they react to it through their obstacle boxes only (as a stationary obstacle, so they keep a larger
  gap behind a moving tram and go around a tram that waits at a stop).
- Taxi service needs the traffic system enabled (the cab is a traffic car): with traffic off `call_taxi` returns
  false.
- The trams do not bend at the articulation, the pantograph has no wire.
