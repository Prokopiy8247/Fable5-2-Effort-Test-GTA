class_name TaxiSystem
extends Node
## World system "taxi" (spec 29A "Taxi passenger service"): call / hail a cab, ride as a passenger,
## pick a destination, ride there through traffic or skip the trip, pay the fare.
##
## The cab is a REAL traffic car: a "taxi" of the traffic system with its seated `taxi_driver`
## (TrafficDummy). The traffic manager keeps driving it with all of its rules (signals, right of
## way, following, obstacle boxes, reactions); this system only steers the job, once per physics
## frame right after the traffic manager (process_physics_priority 1):
##   * route: at every lane the TrafficDriver enters, its `next_lane` / `conn` are replaced by the
##     next lane of RoadGraph.find_lane_route(lane, target lane) (re-routed after lane changes);
##   * stopping: `speed_factor` scales the free speed down onto a braking curve to the kerb point,
##     `lateral_target` pulls over, `brake_t` holds the car while it waits;
##   * no voluntary lane changes (`lc_cd`), no hopeless-despawn while hired (`prog_t`).
## TrafficDriver / TrafficLanes are accessed untyped (soft dependency on the traffic module).
##
## Getting a cab: call_taxi(near) (phone, admin menu, the "Call a cab" point at the taxi stand),
## or hail a passing free cab (interact near the kerb when "Hail the cab" shows). The cab pulls
## over at the kerb, honks; "Get in the cab" (interact) seats the player in a rear seat (holding
## the enter-vehicle key to ride along works too). Tapping the enter-vehicle key steals it -
## that is a normal carjack of the traffic module (the job ends).
## Riding: the taxi screen lists the named places by district + the map waypoint with fares;
## choosing one starts the ride (the driver refuses when the player cannot pay the quote).
## Enter (`skip`) skips the ride (fade, the cab is moved to the drop-off, the clock advances by the
## trip time); the enter-vehicle key asks the driver to stop here (pays the distance so far).
## The fare is charged on arrival (Game.spend), the passenger gets out at the kerb.

enum State { IDLE, DISPATCH, WAITING, CHOOSING, RIDE, STOPPING, ARRIVED }

const STATE_NAMES: Array[String] = ["idle", "dispatch", "waiting", "choosing", "ride", "stopping", "arrived"]
const FARE_BASE := 8
const FARE_PER_KM := 34.0
const DISPATCH_TIMEOUT := 150.0       ## the cab gives up when it cannot reach the kerb point
const WAIT_TIMEOUT := 75.0            ## a cab waits this long at the kerb for its passenger
const WALK_AWAY := 120.0              ## passenger this far from the waiting cab: it leaves
const STOP_DECEL := 1.7               ## m/s^2 braking curve onto the kerb point
const SPAWN_MIN := 65.0
const SPAWN_MAX := 150.0
const CLAIM_MAX := 160.0              ## free cabs of the traffic up to this far away answer a call (traffic freezes beyond 170 m)
const HAIL_RANGE := 45.0
const MAX_ROUTE_M := 200.0            ## a free cab answers a call only if it can drive there within this
const AVG_SPEED := 8.0                ## m/s for trip-time estimates
const BLIP_COLOR := Color(1.0, 0.82, 0.22)

var enabled: bool = true
var state: int = State.IDLE
var taxi: Node3D = null               ## the cab (VehicleBase of the traffic system)
var drv: Object = null                ## its TrafficDriver (untyped)
var dest: Dictionary = {}             ## {id, label, district, pos, drop: {lane, s, pos}}
var fare_quote: int = 0
var ride_m: float = 0.0               ## metres driven with the passenger aboard
var stats := {"calls": 0, "hails": 0, "pickups": 0, "rides": 0, "arrivals": 0, "skips": 0, "early_stops": 0,
		"fares": 0, "refused": 0, "lost": 0, "timeouts": 0, "reroutes": 0, "spawned": 0, "claimed": 0}

var _traffic: Node = null
var _lanes: Variant = null
var _roads: Variant = null
var _dest_helper: TaxiDestinations = null
var _target_lane: int = -1
var _target_s: float = 0.0
var _route := PackedInt32Array()
var _route_i: int = 0
var _route_from: int = -1
var _job_t: float = 0.0
var _hold_t: float = 0.0
var _saved_sf: float = 1.0
var _last_pos: Vector3 = Vector3.INF
var _pickup: Dictionary = {}
var _set_waypoint: bool = false
var _skip_busy: bool = false
var _redispatch: int = 0
var _pred: Array = []                 ## predecessor lanes (inverted TrafficLanes.next), for upstream spawns
var _exit_t: float = -1.0
var _charged: bool = false
var _hail_t: float = 0.0
var _hail_target: Node3D = null
var _blip: Node3D = null
var _it_board: Interactable = null
var _it_ride: Interactable = null
var _it_hail: Interactable = null
var _it_stand: Interactable = null


# =================================================================================================
# lifecycle
# =================================================================================================

func setup() -> void:
	process_physics_priority = 1              # after the traffic manager in the same physics frame
	_build_interactables()
	if not EventBus.player_entered_vehicle.is_connected(_on_player_entered):
		EventBus.player_entered_vehicle.connect(_on_player_entered)
		EventBus.player_exited_vehicle.connect(_on_player_exited)
		EventBus.game_ready.connect(_on_game_ready)


func _on_game_ready() -> void:
	_place_stand_point()


func _ensure_links() -> bool:
	var tr := Game.get_system("traffic")
	if tr == null or not is_instance_valid(tr) or not tr.has_method("get_driver") or not tr.has_method("spawn_traffic_vehicle"):
		_traffic = null
		return false
	if tr.get("enabled") == false:
		return false
	_traffic = tr
	var l: Variant = tr.get("lanes")
	if l == null:
		return false
	_lanes = l
	_roads = l.get("roads")
	if _roads == null:
		return false
	if _dest_helper == null or _dest_helper.lanes != _lanes:
		_dest_helper = TaxiDestinations.new()
		_dest_helper.setup(_roads, _lanes)
	return true


func _build_interactables() -> void:
	_it_board = Interactable.create("Get in the cab", 4.2, "interact")
	_it_board.name = "TaxiBoard"
	_it_board.use_priority = 6
	_it_board.enabled = false
	_it_board.condition = _can_board
	_it_board.interacted.connect(func(_p: Node3D) -> void: board())
	add_child(_it_board)
	_it_ride = Interactable.create("Choose a destination", 3.0, "interact")
	_it_ride.name = "TaxiRide"
	_it_ride.on_foot_only = false
	_it_ride.in_vehicle_only = true
	_it_ride.use_priority = 30
	_it_ride.enabled = false
	_it_ride.condition = _can_ride_action
	_it_ride.interacted.connect(_on_ride_action)
	add_child(_it_ride)
	_it_hail = Interactable.create("Hail the cab", 3.0, "interact")
	_it_hail.name = "TaxiHail"
	_it_hail.use_priority = -2
	_it_hail.enabled = false
	_it_hail.condition = func(_p: Node3D) -> bool: return _hail_target != null and is_instance_valid(_hail_target)
	_it_hail.interacted.connect(func(_p: Node3D) -> void: _hail())
	add_child(_it_hail)
	_it_stand = Interactable.create("Call a cab", 3.0, "interact")
	_it_stand.name = "TaxiStand"
	_it_stand.enabled = false
	_it_stand.condition = func(_p: Node3D) -> bool: return enabled and state == State.IDLE
	_it_stand.interacted.connect(_on_stand)
	add_child(_it_stand)
	_blip = Node3D.new()
	_blip.name = "TaxiBlip"
	_blip.set_meta("blip_icon", &"taxi")
	_blip.set_meta("blip_color", BLIP_COLOR)
	_blip.set_meta("blip_clamp", true)
	add_child(_blip)


func _place_stand_point() -> void:
	if Game.world == null or not Game.world.has_method("get_location"):
		return
	if Game.world.has_method("has_location") and not bool(Game.world.call("has_location", "taxi_stand")):
		return
	var xf: Transform3D = Game.world.call("get_location", "taxi_stand")
	_it_stand.position = xf.origin + Vector3.UP
	_it_stand.enabled = true


# =================================================================================================
# public API
# =================================================================================================

## Sends a cab to the kerb nearest to `near` (default: the player). Returns false when no cab can
## come (service off, no traffic, no road near). Silent on success - the caller announces it
## (debug_system / phone already notify).
func call_taxi(near: Vector3 = Vector3.INF) -> bool:
	if not enabled or not _ensure_links():
		return false
	if near == Vector3.INF or not near.is_finite():
		near = Game.get_player_position()
	if state != State.IDLE:
		if state == State.DISPATCH or state == State.WAITING:
			return true                       # already on its way / waiting
		return false
	var pk := _dest_helper.drop_point(near, 60.0)
	if pk.is_empty():
		return false
	var v := _find_free_cab(pk)
	if v == null:
		v = _spawn_cab(pk)
	if v == null:
		return false
	if not _claim(v):
		return false
	stats["calls"] = int(stats["calls"]) + 1
	_pickup = pk
	_start_dispatch()
	_redispatch = 1
	return true


## Hail / call alias (debug_system looks for call_taxi, request_taxi, summon_taxi).
func request_taxi(near: Vector3 = Vector3.INF) -> bool:
	return call_taxi(near)


func cancel_taxi(reason: String = "") -> void:
	if state == State.IDLE:
		return
	if reason != "":
		UI.notify(reason, "warn")
	_finish()


## Interactable "Get in the cab": the player walks to a rear door and sits down as a passenger.
func board() -> bool:
	var p := Game.player
	if p == null or not _cab_ok() or p.get("current_vehicle") != null or not p.has_method("enter_vehicle"):
		return false
	var seat := _passenger_seat(p.global_position)
	if seat < 1:
		UI.notify("The cab is full", "warn")
		return false
	p.call("enter_vehicle", taxi, seat)
	return true


## Destinations for the taxi screen: [{id, label, district, district_label, icon, pos, distance,
## fare, minutes, disabled}] - the waypoint first (if set), then the places by district.
func get_destinations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _ensure_links():
		return out
	var from := taxi.global_position if _cab_ok() else Game.get_player_position()
	if UI.has_method("has_waypoint") and bool(UI.call("has_waypoint")):
		var wp: Variant = UI.get("nav").get("waypoint") if UI.get("nav") != null else null
		if wp is Vector3 and (wp as Vector3).is_finite():
			var drop := _dest_helper.drop_point(wp as Vector3, 90.0)
			if not drop.is_empty():
				var district := str(Game.world.call("get_district", wp)) if Game.world != null else ""
				out.append(_dest_entry({"id": "waypoint", "label": "Map waypoint", "district": district,
						"district_label": "Your waypoint", "icon": &"pin", "pos": wp, "drop": drop}, from))
	for pl: Dictionary in _dest_helper.places():
		out.append(_dest_entry(pl, from))
	return out


func _dest_entry(pl: Dictionary, from: Vector3) -> Dictionary:
	var e := pl.duplicate()
	var drop: Dictionary = pl["drop"]
	var dist := Vector2(from.x - (drop["pos"] as Vector3).x, from.z - (drop["pos"] as Vector3).z).length() * 1.3
	e["distance"] = dist
	e["fare"] = estimate_fare(dist)
	e["minutes"] = maxi(1, roundi(dist / AVG_SPEED * WorldClock.rate / 60.0))
	e["disabled"] = dist < 70.0
	return e


func estimate_fare(metres: float) -> int:
	if Game.flags.get("free_shopping", false):
		return 0
	return FARE_BASE + roundi(FARE_PER_KM * metres / 1000.0)


## Starts the ride to a destination id from get_destinations() (or a dictionary of it).
## False when there is no cab / no passenger / no route, or the passenger cannot pay the quote.
func choose_destination(which: Variant) -> bool:
	if not (state == State.CHOOSING or state == State.RIDE) or not _cab_ok() or not _passenger_aboard():
		return false
	var d: Dictionary = {}
	if which is Dictionary:
		d = which as Dictionary
	else:
		for e: Dictionary in get_destinations():
			if str(e["id"]) == str(which):
				d = e
				break
	if d.is_empty() or not d.has("drop"):
		return false
	var drop: Dictionary = d["drop"]
	var lane := int(drop["lane"])
	var start := _cursor_lane()
	var route: PackedInt32Array = _roads.find_lane_route(start, lane) if start >= 0 else PackedInt32Array()
	if route.is_empty():
		UI.notify("The driver does not know the way there", "warn")
		return false
	var s_now := float(drv.get("s")) if not bool(drv.get("in_conn")) else 0.0
	var metres := _dest_helper.route_length(route, s_now, float(drop["s"]))
	if route.size() == 1 and float(drop["s"]) < s_now:
		metres = float(_lanes.length[lane]) * 2.0      # behind us on this lane: round the block
	var fare := estimate_fare(metres)
	if fare > Game.money:
		stats["refused"] = int(stats["refused"]) + 1
		UI.notify("The driver wants to see %s first" % _money(fare), "bad")
		if UI.has_method("sfx"):
			UI.call("sfx", "ui_error")
		return false
	dest = d
	fare_quote = fare
	_target_lane = lane
	_target_s = float(drop["s"])
	_route = route
	_route_i = 0
	_route_from = start
	if state == State.CHOOSING:
		ride_m = 0.0
		_last_pos = taxi.global_position
		stats["rides"] = int(stats["rides"]) + 1
	state = State.RIDE
	_job_t = 0.0
	_release_hold()
	_route_waypoint(drop["pos"] as Vector3)
	UI.close_screen("taxi")
	UI.notify("Taxi to %s - fare %s. %s: skip the ride" % [str(d["label"]), _money(fare), InputSetup.label("skip")], "info", 5.0)
	return true


## Skip the ride (the "skip" action, Enter): fade out, the cab is at the drop-off, the clock moved on
## by the trip time, fade in, pay and get out.
func skip_ride() -> bool:
	if state != State.RIDE or _skip_busy or not _cab_ok() or not _passenger_aboard():
		return false
	_skip_busy = true
	_do_skip.call_deferred()
	return true


## Ask the driver to stop at the next safe kerb spot (the enter-vehicle key while riding).
func stop_here() -> bool:
	if state != State.RIDE or not _cab_ok():
		return false
	var lane := int(drv.get("next_lane")) if bool(drv.get("in_conn")) else int(drv.get("lane"))
	if lane < 0:
		return false
	var v := absf(float(taxi.call("get_forward_speed")))
	var s0 := 0.0 if bool(drv.get("in_conn")) else float(drv.get("s"))
	var s_stop := s0 + v * v / (2.0 * STOP_DECEL) + 4.0
	var length := float(_lanes.length[lane])
	if s_stop > length - 8.0:
		# not enough lane left before the junction: stop just after it
		var nx := int(drv.get("next_lane"))
		if nx >= 0 and not bool(drv.get("in_conn")):
			lane = nx
			s_stop = 10.0
		else:
			s_stop = length - 8.0
	_target_lane = lane
	_target_s = clampf(s_stop, 2.0, maxf(float(_lanes.length[lane]) - 6.0, 2.0))
	_route = _roads.find_lane_route(_cursor_lane(), lane)
	_route_i = 0
	state = State.STOPPING
	stats["early_stops"] = int(stats["early_stops"]) + 1
	UI.notify("Pulling over", "info", 2.0)
	return true


func is_player_in_taxi() -> bool:
	return _cab_ok() and _passenger_aboard()


func get_taxi() -> Node3D:
	return taxi if _cab_ok() else null


func get_state_name() -> String:
	return STATE_NAMES[state]


## Job overview (phone / tests / debug).
func get_job_info() -> Dictionary:
	var info := {"state": STATE_NAMES[state], "taxi": taxi if _cab_ok() else null, "fare": fare_quote,
			"ride_m": ride_m, "destination": str(dest.get("label", "")), "destination_id": str(dest.get("id", "")),
			"target_lane": _target_lane, "target_s": _target_s, "time": _job_t}
	if _cab_ok():
		info["taxi_pos"] = taxi.global_position
		var tp := _target_point()
		info["distance_to_target"] = taxi.global_position.distance_to(tp) if tp.is_finite() else -1.0
		info["eta"] = info["distance_to_target"] / AVG_SPEED if tp.is_finite() else -1.0
	return info


func get_debug_info() -> Dictionary:
	var d := get_job_info()
	d.erase("taxi")
	d["enabled"] = enabled
	for k: String in stats:
		d[k] = stats[k]
	return d


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if not on:
		_finish()
		UI.close_screen("taxi")
	_it_stand.enabled = on and _it_stand.position != Vector3.ZERO


## Death / arrest: the job ends (the cab drives on as ordinary traffic).
func reset_for_respawn() -> void:
	if state != State.IDLE:
		_finish()
	UI.close_screen("taxi")
	_skip_busy = false


# =================================================================================================
# manager loop
# =================================================================================================

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_hail_t -= delta
	if _hail_t <= 0.0:
		_hail_t = 0.25
		_hail_tick()
	if state == State.IDLE:
		_sync_interactables()
		return
	if not _cab_ok():
		if taxi != null and is_instance_valid(taxi) and Game.get_player_vehicle() == taxi and taxi.get("driver") == Game.player:
			_finish()                                    # the player took the wheel (carjack): no fare
		elif state == State.DISPATCH and _redispatch > 0 and _pickup.has("pos"):
			# the cab was taken off the road (despawned, crashed, frozen far away): send another
			var left := _redispatch - 1
			var pk := _pickup
			_finish()
			if call_taxi(pk["pos"] as Vector3):
				_redispatch = left
			else:
				UI.notify("No cab available right now", "warn")
		else:
			_lost("Your cab is gone")
		return
	_job_t += delta
	_keep_alive()
	var aboard := _passenger_aboard()
	if aboard and _last_pos.is_finite() and (state == State.RIDE or state == State.STOPPING):
		ride_m += Vector2(taxi.global_position.x - _last_pos.x, taxi.global_position.z - _last_pos.z).length()
	_last_pos = taxi.global_position
	match state:
		State.DISPATCH:
			_steer()
			if _approach():
				_arrived_pickup()
			elif _job_t > DISPATCH_TIMEOUT:
				stats["timeouts"] = int(stats["timeouts"]) + 1
				_lost("Your cab is stuck in traffic - try again")
		State.WAITING:
			_hold()
			_hold_t += delta
			var pd := Game.get_player_position().distance_to(taxi.global_position)
			if not _player_getting_in() and (_hold_t > WAIT_TIMEOUT or pd > WALK_AWAY):
				stats["timeouts"] = int(stats["timeouts"]) + 1
				UI.notify("Your cab left", "warn")
				_finish()
		State.CHOOSING:
			_hold()
			if not aboard:
				_finish()
		State.RIDE:
			_steer()
			if _approach():
				_arrive()
			elif aboard and Input.is_action_just_pressed(&"skip") and _input_ok():
				skip_ride()
		State.STOPPING:
			_steer()
			if _approach():
				_arrive()
		State.ARRIVED:
			_hold()
			if _exit_t >= 0.0:
				_exit_t -= delta
				if _exit_t < 0.0 and aboard and Game.player.has_method("exit_vehicle"):
					Game.player.call("exit_vehicle")
			if not aboard and _exit_t < 0.0 and not _skip_busy:
				_finish()
	_sync_interactables()


# --- the cab -------------------------------------------------------------------------------------

func _cab_ok() -> bool:
	if taxi == null or not is_instance_valid(taxi) or taxi.is_queued_for_deletion() or not taxi.is_inside_tree():
		return false
	if taxi.get("destroyed") == true:
		return false
	if _traffic == null or not is_instance_valid(_traffic) or drv == null:
		return false
	return _traffic.call("get_driver", taxi) == drv


func _passenger_aboard() -> bool:
	if not Game.has_player() or taxi == null or not is_instance_valid(taxi):
		return false
	return Game.player.get("current_vehicle") == taxi and taxi.has_method("get_seat_of") and int(taxi.call("get_seat_of", Game.player)) >= 1


## The player walks to a door / slides into a seat (PLAYER vehicle state, not seated yet).
func _player_getting_in() -> bool:
	if not Game.has_player() or not Game.player.has_method("get_state_name"):
		return false
	return str(Game.player.call("get_state_name")) == "vehicle" and Game.player.get("current_vehicle") == null


func _input_ok() -> bool:
	if Game.is_input_locked() or UI.is_screen_open():
		return false
	return Game.has_player() and (not Game.player.has_method("has_control") or bool(Game.player.call("has_control")))


## A traffic cab that can take a fare: a live vehicle with its driver, not wrecked, not driven by the
## player and with nobody else riding in a passenger seat.
func _is_free_cab(v: Node3D) -> bool:
	if v == null or not is_instance_valid(v) or not v.is_inside_tree():
		return false
	if v.get("destroyed") == true or v.get("is_player_driven") == true:
		return false
	if v.get("driver") == null:
		return false
	if v.has_method("get_occupants"):
		for o: Variant in (v.call("get_occupants") as Array):
			if o != null and o != v.get("driver"):
				return false
	return true


## The nearest free cab of the traffic whose DRIVING distance to the pick-up is short (a cab sent
## round a long detour would leave the traffic's 190 m despawn ring).
func _find_free_cab(pk: Dictionary) -> Node3D:
	var near: Vector3 = pk["pos"]
	var cands: Array = []
	for d: Variant in (_traffic.call("get_drivers") as Array):
		if d == null or not bool(d.call("is_valid")):
			continue
		if str(d.get("spec_id")) != "taxi" or bool(d.get("frozen")) or str(d.get("release_reason")) != "" or float(d.get("panic_t")) > 0.0:
			continue
		var v := d.get("body") as Node3D
		if not _is_free_cab(v):
			continue
		var dd := v.global_position.distance_to(near)
		if dd > 22.0 and dd < CLAIM_MAX:
			cands.append([dd, d, v])
	cands.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var best: Node3D = null
	var best_m := MAX_ROUTE_M
	for i in mini(cands.size(), 4):
		var d: Variant = cands[i][1]
		var in_conn := bool(d.get("in_conn"))
		var from := int(d.get("next_lane")) if in_conn else int(d.get("lane"))
		if from < 0:
			continue
		var r: PackedInt32Array = _roads.find_lane_route(from, int(pk["lane"]))
		if r.is_empty():
			continue
		var s0 := 0.0 if in_conn else float(d.get("s"))
		var m := _dest_helper.route_length(r, s0, float(pk["s"]))
		if r.size() == 1 and float(pk["s"]) < s0:
			continue                                     # just passed the spot on the same lane
		if m < best_m:
			best_m = m
			best = cands[i][2]
	return best


## Spawns a cab "upstream" of the pick-up: on a lane that leads to the pick-up lane, SPAWN_MIN..
## SPAWN_MAX metres of driving away, out of the camera view when possible.
func _spawn_cab(pk: Dictionary) -> Node3D:
	var cap := 22
	var sc := _traffic.get_script() as Script
	if sc != null and sc.get_script_constant_map().has("CAP"):
		cap = int(sc.get_script_constant_map()["CAP"])
	if int(_traffic.call("get_vehicle_count")) >= cap:
		_make_room()
	var spots := _upstream(int(pk["lane"]), float(pk["s"]), SPAWN_MIN, SPAWN_MAX)
	# shuffle (Game.rng), unseen spots first
	for i in range(spots.size() - 1, 0, -1):
		var j := Game.rng.randi_range(0, i)
		var tmp: Variant = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	var seen_spots: Array = []
	for sp: Array in spots:
		var p: Vector3 = _lanes.lane_point(int(sp[0]), float(sp[1]))
		if bool(_traffic.call("is_seen", p)):
			seen_spots.append(sp)
			continue
		var v: Variant = _traffic.call("spawn_traffic_vehicle", int(sp[0]), float(sp[1]), "taxi")
		if v != null and is_instance_valid(v):
			stats["spawned"] = int(stats["spawned"]) + 1
			return v as Node3D
	for sp: Array in seen_spots:
		var v2: Variant = _traffic.call("spawn_traffic_vehicle", int(sp[0]), float(sp[1]), "taxi")
		if v2 != null and is_instance_valid(v2):
			stats["spawned"] = int(stats["spawned"]) + 1
			return v2 as Node3D
	return null


## Lane points [lane, offset] from which the driving distance to (lane, s) is min_d..max_d
## (backwards over the lane graph; offsets kept away from lane ends, spawnable lanes only).
func _upstream(lane: int, s: float, min_d: float, max_d: float) -> Array:
	_ensure_pred()
	var out: Array = []
	var spawnable: Variant = _lanes.get("spawnable")
	# d_start[L] = driving distance from the START of lane L to the pick-up
	var d_start := {lane: s}
	var queue: Array[int] = [lane]
	var guard := 0
	while not queue.is_empty() and guard < 400:
		guard += 1
		var q: int = queue.pop_front()
		var dq := float(d_start[q])
		for pl: int in (_pred[q] as PackedInt32Array):
			var d_end := float(_lanes.conn_length(pl, q)) + dq
			var ln := float(_lanes.length[pl])
			if d_end > max_d or (d_start.has(pl) and float(d_start[pl]) <= d_end + ln):
				continue
			d_start[pl] = d_end + ln
			queue.append(pl)
	for l: int in d_start:
		if spawnable is PackedByteArray and int((spawnable as PackedByteArray)[l]) == 0:
			continue
		var ln := float(_lanes.length[l])
		var ds := float(d_start[l])
		# offset o on lane l: distance to the pick-up = ds - o
		var o := 8.0
		while o < ln - 14.0:
			var dist := ds - o
			if l == lane and o >= s - 6.0:
				break
			if dist >= min_d and dist <= max_d:
				out.append([l, o])
			o += 12.0
	return out


func _ensure_pred() -> void:
	if not _pred.is_empty() and _pred.size() == int(_lanes.count):
		return
	_pred.clear()
	var n := int(_lanes.count)
	for i in n:
		_pred.append(PackedInt32Array())
	var nexts: Array = _lanes.get("next")
	for i in n:
		for nx: int in (nexts[i] as PackedInt32Array):
			var arr: PackedInt32Array = _pred[nx]
			arr.append(i)
			_pred[nx] = arr


## At the traffic cap: the farthest unseen ordinary traffic car makes room for the cab.
func _make_room() -> void:
	var far: Node3D = null
	var far_d := 90.0
	var focus := Game.get_player_position()
	for d: Variant in (_traffic.call("get_drivers") as Array):
		if d == null or not bool(d.call("is_valid")) or str(d.get("spec_id")) == "taxi":
			continue
		var v := d.get("body") as Node3D
		if v == Game.get_player_vehicle():
			continue
		var dd := v.global_position.distance_to(focus)
		if dd > far_d and not bool(_traffic.call("is_seen", v.global_position)):
			far_d = dd
			far = v
	if far != null:
		_traffic.call("release_vehicle", far, "despawn")
		_traffic.call("despawn_vehicle_node", far)


func _claim(v: Node3D) -> bool:
	var d: Variant = _traffic.call("get_driver", v)
	if d == null:
		return false
	taxi = v
	drv = d
	_saved_sf = float(drv.get("speed_factor"))
	dest = {}
	fare_quote = 0
	ride_m = 0.0
	_charged = false
	_exit_t = -1.0
	_job_t = 0.0
	_hold_t = 0.0
	_last_pos = Vector3.INF
	if taxi.has_method("set_taxi_sign"):
		taxi.call("set_taxi_sign", false)          # hired: roof sign off
	stats["claimed"] = int(stats["claimed"]) + 1
	return true


func _start_dispatch() -> void:
	state = State.DISPATCH
	_target_lane = int(_pickup["lane"])
	_target_s = float(_pickup["s"])
	_route = PackedInt32Array()
	_route_i = 0
	_release_hold()
	_blip.add_to_group("minimap_blip")


func _arrived_pickup() -> void:
	state = State.WAITING
	_hold_t = 0.0
	stats["pickups"] = int(stats["pickups"]) + 1
	_hold()
	if taxi.has_method("honk"):
		taxi.call("honk", true)
		drv.set("honk_t", 0.45)
	UI.notify("Your cab is here", "info", 3.0)


## Passenger arrived (destination reached or stopped early): pay, then get out at the kerb.
func _arrive() -> void:
	if state == State.ARRIVED:
		return
	var full := state == State.RIDE
	state = State.ARRIVED
	_hold()
	_charge(fare_quote if full else mini(fare_quote, estimate_fare(ride_m)))
	if full:
		stats["arrivals"] = int(stats["arrivals"]) + 1
	_exit_t = 0.8
	_clear_route_waypoint()


func _charge(amount: int) -> void:
	if _charged:
		return
	_charged = true
	if Game.flags.get("free_shopping", false):
		amount = 0
	amount = maxi(amount, 0)
	var paid := mini(amount, Game.money)
	if paid > 0:
		Game.spend(paid)
		EventBus.item_purchased.emit("service", "taxi_fare", paid)
	stats["fares"] = int(stats["fares"]) + paid
	var where := str(dest.get("label", ""))
	UI.notify(("Fare paid: %s" % _money(paid)) + ((" - " + where) if where != "" and state == State.ARRIVED else ""), "money", 3.5)


func _do_skip() -> void:
	var d := dest
	var drop: Dictionary = d.get("drop", {})
	if drop.is_empty() or not _cab_ok():
		_skip_busy = false
		return
	stats["skips"] = int(stats["skips"]) + 1
	var remaining := taxi.global_position.distance_to(drop["pos"] as Vector3) * 1.3
	await UI.fade_out(0.5)
	if not _cab_ok() or state != State.RIDE:
		await UI.fade_in(0.4)
		_skip_busy = false
		return
	var lane := int(drop["lane"])
	var s := float(drop["s"])
	var p: Vector3 = _lanes.lane_point(lane, s)
	var dir: Vector3 = _lanes.lane_dir(lane, s)
	var right := Vector3(-dir.z, 0.0, dir.x)
	p += right * _pull_over(lane)
	var gy := Game.ground_height(p.x, p.z)
	var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(p.x, gy + 0.05, p.z))
	if taxi.has_method("teleport"):
		taxi.call("teleport", xf)
	else:
		taxi.global_transform = xf
	drv.call("place", _lanes, lane, s, Game.rng)
	ride_m += remaining
	_last_pos = taxi.global_position
	var secs := remaining / AVG_SPEED + 5.0
	if WorldClock.has_method("advance_hours"):
		WorldClock.advance_hours(secs * WorldClock.rate / 3600.0)
	_target_lane = lane
	_target_s = s
	_arrive()
	if Game.camera_rig != null and Game.camera_rig.has_method("snap_to"):
		Game.camera_rig.call("snap_to", atan2(-dir.x, -dir.z))
	await get_tree().create_timer(0.35, true, false, true).timeout
	await UI.fade_in(0.5)
	_skip_busy = false


## Job over: the cab goes back to ordinary traffic.
func _finish() -> void:
	if drv != null and taxi != null and is_instance_valid(taxi) and _traffic != null and is_instance_valid(_traffic) \
			and _traffic.call("get_driver", taxi) == drv:
		drv.set("speed_factor", _saved_sf)
		drv.set("lc_cd", Game.rng.randf_range(4.0, 10.0))
		drv.set("lateral_target", 0.0)
		drv.set("brake_t", 0.0)
		drv.set("prog_t", 0.0)
	if taxi != null and is_instance_valid(taxi) and taxi.has_method("set_taxi_sign"):
		taxi.call("set_taxi_sign", true)
	_clear_route_waypoint()
	taxi = null
	drv = null
	state = State.IDLE
	dest = {}
	_route = PackedInt32Array()
	_target_lane = -1
	_exit_t = -1.0
	if _blip.is_in_group("minimap_blip"):
		_blip.remove_from_group("minimap_blip")
	UI.close_screen("taxi")


func _lost(msg: String) -> void:
	stats["lost"] = int(stats["lost"]) + 1
	if state == State.DISPATCH or state == State.WAITING:
		UI.notify(msg, "warn")
	_finish()


# --- steering the traffic driver --------------------------------------------------------------------

func _cursor_lane() -> int:
	if drv == null:
		return -1
	if bool(drv.get("in_conn")):
		return int(drv.get("next_lane"))
	return int(drv.get("lane"))


func _keep_alive() -> void:
	drv.set("lc_cd", 999.0)                     # no lane changes for overtaking while hired
	drv.set("prog_t", 0.0)                      # never "hopeless" (we stop on purpose)
	drv.set("prog_pos", taxi.global_position)


## Replaces the random next lane with the next lane of the route to the target lane.
func _steer() -> void:
	if bool(drv.get("frozen")):
		return
	var cur := int(drv.get("lane"))
	if cur < 0 or bool(drv.get("in_conn")) or _target_lane < 0:
		return
	if cur == _target_lane:
		return
	var i := -1
	for k in range(_route_i, _route.size()):
		if _route[k] == cur:
			i = k
			break
	if i < 0 or i + 1 >= _route.size():
		_route = _roads.find_lane_route(cur, _target_lane)
		_route_i = 0
		if _route.size() < 2 or _route[0] != cur:
			return
		i = 0
		stats["reroutes"] = int(stats["reroutes"]) + 1
	_route_i = i
	var want := _route[i + 1]
	if int(drv.get("next_lane")) != want:
		drv.set("next_lane", want)
		drv.set("conn", _lanes.get_conn(cur, want))
		drv.set("permit", false)
		drv.set("path_clear_ok", false)
		drv.set("jn_foreign", false)


## Braking curve onto the target kerb point; true once the cab stands there. The curve starts on
## the lane before the target lane (through the junction) so the cab never arrives too fast.
func _approach() -> bool:
	var lane := int(drv.get("lane"))
	var in_conn := bool(drv.get("in_conn"))
	var nxt := int(drv.get("next_lane"))
	var spd := absf(float(taxi.call("get_forward_speed")))
	var on_target := lane == _target_lane and not in_conn
	var d := INF
	if on_target:
		d = _target_s - float(drv.get("s"))
	elif nxt == _target_lane and nxt >= 0:
		d = float(drv.call("dist_to_next_lane", _lanes)) + _target_s
	if d == INF:
		drv.set("speed_factor", _saved_sf)
		return false
	if on_target and d < -3.0:
		# could not stop in time (traffic, a late turn): stop a little further on this kerb instead of
		# going round the block
		var length := float(_lanes.length[lane])
		_target_s = clampf(float(drv.get("s")) + spd * spd / 5.0 + 1.5, 0.0, maxf(length - 6.0, 0.0))
		d = _target_s - float(drv.get("s"))
		if d < -3.0:
			_target_s = float(drv.get("s"))
			d = 0.0
	var lim := maxf(float(drv.call("current_limit", _lanes)), 1.0)
	var v_allow := sqrt(2.0 * STOP_DECEL * maxf(d - 0.6, 0.0))
	drv.set("speed_factor", clampf(v_allow / lim, 0.0, _saved_sf))
	if on_target and d < 40.0:
		drv.set("lateral_target", _pull_over(lane))
	if on_target and d < spd * spd / 4.4 + 0.6:
		drv.set("brake_t", 0.15)                    # firm final stop (the traffic pedals brake hard at vt 0)
	if on_target and spd < 0.8 and (d < 2.5 or (spd < 0.3 and d < 7.0)):
		_hold()
		return true
	return false


func _hold() -> void:
	drv.set("brake_t", 0.4)
	drv.set("speed_factor", 0.0)
	if _target_lane >= 0:
		drv.set("lateral_target", _pull_over(_target_lane))


func _release_hold() -> void:
	drv.set("brake_t", 0.0)
	drv.set("speed_factor", _saved_sf)
	drv.set("lateral_target", 0.0)


## Sideways offset towards the kerb for a stop on `lane` (clear of parked cars).
func _pull_over(lane: int) -> float:
	var lpd := int(_lanes.lanes_per_dir[lane])
	if lpd >= 2:
		return 1.1 if int(_lanes.index[lane]) == lpd - 1 else 0.0
	match int(_lanes.kind[lane]):
		2:
			return 0.35          # alley
		3:
			return 0.3           # dirt track
	return 0.55 if int(_lanes.parking[lane]) == 1 else 0.9


func _target_point() -> Vector3:
	if _target_lane < 0 or _lanes == null:
		return Vector3.INF
	return _lanes.lane_point(_target_lane, _target_s)


func _passenger_seat(from: Vector3) -> int:
	if taxi == null or not taxi.has_method("get_seat_count"):
		return -1
	var n := int(taxi.call("get_seat_count"))
	var best := -1
	var best_d := INF
	for i in range(1, n):
		if taxi.call("get_occupant", i) != null:
			continue
		var door: Vector3 = taxi.call("get_door_position", i) if taxi.has_method("get_door_position") else taxi.global_position
		# rear seats first (a cab passenger sits in the back)
		var dd := door.distance_to(from) - (3.0 if i >= 2 else 0.0)
		if dd < best_d:
			best_d = dd
			best = i
	return best


# --- waypoint / GPS -------------------------------------------------------------------------------

func _route_waypoint(p: Vector3) -> void:
	if not UI.has_method("set_waypoint"):
		return
	if UI.has_method("has_waypoint") and bool(UI.call("has_waypoint")) and str(dest.get("id", "")) != "waypoint":
		return                                          # keep the player's own waypoint
	if str(dest.get("id", "")) == "waypoint":
		return
	UI.call("set_waypoint", p)
	_set_waypoint = true


func _clear_route_waypoint() -> void:
	if _set_waypoint and UI.has_method("clear_waypoint"):
		UI.call("clear_waypoint")
	_set_waypoint = false


# --- events ---------------------------------------------------------------------------------------

func _on_player_entered(vehicle: Node3D, seat: int) -> void:
	if not enabled or vehicle == null:
		return
	if vehicle == taxi and _cab_ok():
		if seat == 0:
			_finish()                                    # stolen: a carjack, not a fare
			return
		if state == State.DISPATCH or state == State.WAITING:
			state = State.CHOOSING
			_hold()
			_open_screen.call_deferred()
		return
	# riding along in a passing free cab (hold the enter key at its rear door) = hiring it
	if state == State.IDLE and seat >= 1 and _ensure_links() and str(vehicle.get("spec_id")) == "taxi":
		var d: Variant = _traffic.call("get_driver", vehicle)
		if d != null and vehicle.get("taxi_for_hire") != false and _claim(vehicle):
			stats["hails"] = int(stats["hails"]) + 1
			state = State.CHOOSING
			_hold()
			_open_screen.call_deferred()


func _on_player_exited(vehicle: Node3D) -> void:
	if vehicle == null or vehicle != taxi or state == State.IDLE:
		return
	match state:
		State.RIDE, State.STOPPING:
			# got out early: pay for the distance
			_charge(mini(fare_quote, estimate_fare(ride_m)))
			_finish()
		State.CHOOSING:
			_finish()
		State.ARRIVED:
			_exit_t = -1.0


func _open_screen() -> void:
	if state == State.CHOOSING and _passenger_aboard():
		UI.open_screen("taxi", {})


func _on_stand(_p: Node3D) -> void:
	var at := _it_stand.global_position
	if call_taxi(at):
		UI.notify("A cab is on its way to the stand", "info")
	else:
		UI.notify("No cabs running right now", "warn")


# --- interactables / hailing ----------------------------------------------------------------------

func _can_board(p: Node3D) -> bool:
	return state == State.WAITING and _cab_ok() and p.get("current_vehicle") == null


func _can_ride_action(p: Node3D) -> bool:
	if not _cab_ok() or p.get("current_vehicle") != taxi or not _passenger_aboard():
		return false
	if state == State.CHOOSING:
		return not UI.is_screen_open("taxi")
	return state == State.RIDE and not _skip_busy


func _on_ride_action(_p: Node3D) -> void:
	if state == State.CHOOSING:
		_open_screen()
	elif state == State.RIDE:
		stop_here()


func _sync_interactables() -> void:
	var ok := _cab_ok()
	_it_board.enabled = ok and state == State.WAITING
	if ok:
		_it_board.global_position = taxi.global_position + Vector3.UP
		_it_ride.global_position = taxi.global_position + Vector3.UP
		_blip.global_position = taxi.global_position
	_it_ride.enabled = ok and (state == State.CHOOSING or state == State.RIDE)
	if state == State.CHOOSING:
		_it_ride.action = "interact"
		_it_ride.prompt = "Choose a destination"
	elif state == State.RIDE:
		_it_ride.action = "enter_vehicle"
		_it_ride.prompt = "Stop here   (%s: skip the ride - %s)" % [InputSetup.label("skip"), _money(fare_quote)]
	var show_blip := ok and (state == State.DISPATCH or state == State.WAITING)
	if show_blip and not _blip.is_in_group("minimap_blip"):
		_blip.add_to_group("minimap_blip")
	elif not show_blip and _blip.is_in_group("minimap_blip"):
		_blip.remove_from_group("minimap_blip")


## 4 Hz: a free cab of the traffic coming along while the player stands near the kerb -> "Hail the cab".
func _hail_tick() -> void:
	_hail_target = null
	if state != State.IDLE or not Game.has_player() or Game.player.get("current_vehicle") != null:
		_it_hail.enabled = false
		return
	if Game.player.get("is_swimming") == true or Game.player.get("is_dead") == true or not _ensure_links():
		_it_hail.enabled = false
		return
	var pp := Game.player.global_position
	var nl: Dictionary = _roads.get_nearest_lane(pp, 9.0)
	if nl.is_empty():
		_it_hail.enabled = false
		return
	var best: Node3D = null
	var best_d := HAIL_RANGE
	for d: Variant in (_traffic.call("get_drivers") as Array):
		if d == null or not bool(d.call("is_valid")) or str(d.get("spec_id")) != "taxi":
			continue
		if bool(d.get("frozen")) or str(d.get("release_reason")) != "" or float(d.get("panic_t")) > 0.0:
			continue
		var v := d.get("body") as Node3D
		if not _is_free_cab(v):
			continue
		var to_p := pp - v.global_position
		to_p.y = 0.0
		var dd := to_p.length()
		if dd >= best_d:
			continue
		var vel := (v as RigidBody3D).linear_velocity if v is RigidBody3D else Vector3.ZERO
		if dd > 16.0 and vel.dot(to_p) <= 0.0:
			continue                                    # driving away
		best_d = dd
		best = v
	_hail_target = best
	_it_hail.enabled = best != null
	_it_hail.global_position = pp + Vector3.UP


func _hail() -> void:
	var v := _hail_target
	if v == null or not is_instance_valid(v) or state != State.IDLE or not _ensure_links():
		return
	var pk := _dest_helper.drop_point(Game.player.global_position, 30.0)
	if pk.is_empty() or not _claim(v):
		return
	stats["hails"] = int(stats["hails"]) + 1
	_pickup = pk
	_start_dispatch()
	UI.notify("The cab is pulling over", "info", 2.5)


static func _money(n: int) -> String:
	return "$%d" % n
