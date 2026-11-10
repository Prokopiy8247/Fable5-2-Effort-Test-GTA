class_name TransitSystem
extends Node3D
## World system "transit" (spec 29A "Trains / transit"): the Bay Tram loop.
##
## Two trams (misc/tram.glb) run clockwise on the closed loop World.get_transit_path() (791 m, the
## rails are already painted on the inner traffic lane by the world's city mesh) and serve the
## three stops of World.get_transit_stops(): they stop ~12 s with the right-hand doors sliding
## open, ring the bell on arrival / departure and play `tram_loop` while moving.
##
## ONE manager loop (_physics_process) drives every tram: target speed = min(cruise 11 m/s, curve
## profile (sqrt(a_lat R), held over the whole car), braking into the next stop, junction stop
## lines (RoadGraph signals: red / yellow decision, "do not block the box", minor approaches yield),
## obstacle boxes along the rails ahead of the nose (vehicles, people, props, the other tram)).
## A tram is a kinematic body that brakes (up to 3.6 m/s^2) instead of pushing things through; it
## cannot be derailed or stolen. A driverless car / far frozen traffic car that blocks the rails
## for 40 s while nobody looks is towed (despawned through the vehicle / traffic APIs).
##
## Riding: "Board the tram" at an open door puts the player on the floor of the car (standing
## riders walk around inside; the kinematic floor carries them), "Sit down" at a seat uses the
## player's vehicle-seat contract (TransitTram), "Stand up" (enter-vehicle key) / "Get off" at an
## open door. Not persisted (SaveSystem-safe): trams restart at their stops after a load.

const TRAM_COUNT := 2
const V_MAX := 11.0                 ## cruise speed (m/s, ~40 km/h)
const A_ACC := 0.85                 ## m/s^2
const B_COMF := 1.25                ## service braking (stops, signals, curves)
const B_FOLLOW := 2.0               ## planning deceleration behind obstacles
const B_MAX := 3.6                  ## emergency braking
const A_LAT := 1.3                  ## comfortable lateral acceleration -> ~4.3 m/s in the 14 m corners
const BOGIE := 5.9                  ## outer bogie centres (manifest bogie_centres_z)
const HALF_LEN := 9.19
const DWELL := 12.0
const DWELL_EXTRA_MAX := 10.0       ## doors held while the player stands in / right at a doorway
const DOOR_TIME := 1.8
const STOP_MARGIN := 1.2            ## nose this far behind a junction stop line
const GAP_STOP := 3.0               ## standstill gap to whatever stands ahead
const HEADWAY := 1.6                ## s, following a moving vehicle
const SIGNAL_LOOK := 70.0
const GREEN_MIN_LEFT := 2.5         ## s of green needed to start across a signalised junction
const OBS_MASK := Layers.VEHICLE | Layers.PLAYER | Layers.NPC | Layers.PROP
const TOW_TIME := 40.0
const NEAR_AUDIO := 75.0
const STOP_LABELS := {"tram_stop_1": "Plaza", "tram_stop_2": "Sandpiper", "tram_stop_3": "Tideline"}

var enabled: bool = true
var path: TransitPath = null
var stops: Array[Dictionary] = []    ## {name, label, s, position, platform}
var lines: Array[Dictionary] = []    ## junction stop lines along the loop {s, lane, signal, yield, node, pos, radius, cross}
var trams: Array[TransitTram] = []
var stats := {"static_in_corridor": 0, "top_speed": 0.0, "arrivals": 0, "departures": 0, "loops": 0, "boardings": 0, "alightings": 0, "seated": 0,
		"signal_holds": 0, "obstacle_holds": 0, "emergency_brakes": 0, "tows": 0, "bells": 0}

var _ready_world: bool = false
var _q: PhysicsShapeQueryParameters3D = null
var _box: BoxShape3D = null
var _sphere_q: PhysicsShapeQueryParameters3D = null
var _excl: Array[RID] = []
var _env_t: float = 0.0
var _night: bool = false
var _rider: TransitTram = null       ## tram the player is aboard (standing or seated), or null
var _rider_seated: bool = false
var _hinted: bool = false
var _cost_avg: float = 0.0
var _static_seen: Dictionary = {}     ## static colliders found inside the rail corridor (diagnostics)


# =================================================================================================
# lifecycle
# =================================================================================================

func setup() -> void:
	_try_init()
	if enabled and _ready_world and trams.is_empty():
		_spawn_trams()


func _try_init() -> bool:
	if _ready_world:
		return true
	var w: Node = Game.world
	if w == null or not is_instance_valid(w) or not w.has_method("get_transit_path"):
		return false
	var raw: Variant = w.call("get_transit_path")
	if not (raw is PackedVector3Array) or (raw as PackedVector3Array).size() < 3:
		push_warning("TransitSystem: the world has no transit path - no trams")
		return false
	path = TransitPath.new()
	if not path.build(raw as PackedVector3Array):
		push_warning("TransitSystem: transit path too short")
		path = null
		return false
	path.build_profile(V_MAX, A_LAT, HALF_LEN, B_COMF)
	_build_stops(w)
	if stops.is_empty():
		push_warning("TransitSystem: no tram stops")
		return false
	_build_lines(w)
	_box = BoxShape3D.new()
	_q = PhysicsShapeQueryParameters3D.new()
	_q.shape = _box
	_q.collision_mask = OBS_MASK
	var sph := SphereShape3D.new()
	sph.radius = 8.0
	_sphere_q = PhysicsShapeQueryParameters3D.new()
	_sphere_q.shape = sph
	_sphere_q.collision_mask = Layers.VEHICLE
	_excl.resize(1)
	_ready_world = true
	return true


func _build_stops(w: Node) -> void:
	stops.clear()
	var list: Variant = w.call("get_transit_stops") if w.has_method("get_transit_stops") else []
	if not (list is Array):
		return
	for e: Variant in (list as Array):
		if not (e is Dictionary):
			continue
		var d := e as Dictionary
		var pos: Vector3 = d.get("position", Vector3.INF)
		if not pos.is_finite():
			continue
		var nm := str(d.get("name", "tram_stop"))
		stops.append({"name": nm, "label": str(STOP_LABELS.get(nm, nm.capitalize())), "s": path.project(pos),
				"position": pos, "platform": d.get("platform", Transform3D(Basis.IDENTITY, pos))})
	stops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) < float(b["s"]))


## Junction stop lines on the loop: the end of every RoadGraph lane the rails follow into a junction
## of 3+ legs (signal group / yield flag of that lane), measured as path offsets.
func _build_lines(w: Node) -> void:
	lines.clear()
	var roads: Variant = w.get("roads")
	if roads == null or not roads.has_method("get_nearest_lane"):
		return
	var lane_list: Variant = roads.get("lanes")
	var inters: Variant = roads.get("intersections")
	if not (lane_list is Array) or not (inters is Array):
		return
	var seen := {}
	var s := 0.0
	while s < path.length:
		var p := path.sample(s)
		var nl: Dictionary = roads.get_nearest_lane(p, 1.8)
		s += 2.0
		if nl.is_empty():
			continue
		var lid := int(nl["lane_id"])
		if seen.has(lid) or lid < 0 or lid >= (lane_list as Array).size():
			continue
		var lane: Dictionary = (lane_list as Array)[lid]
		var lp: PackedVector3Array = lane.get("points", PackedVector3Array())
		if lp.size() < 2:
			continue
		# same direction as the rails
		var ld := lp[lp.size() - 1] - lp[0]
		ld.y = 0.0
		if ld.length_squared() < 0.01 or ld.normalized().dot(path.tangent(s - 2.0)) < 0.5:
			continue
		seen[lid] = true
		var node := int(lane.get("end_intersection", -1))
		if node < 0 or node >= (inters as Array).size():
			continue
		var it: Dictionary = (inters as Array)[node]
		var legs: Variant = it.get("legs", [])
		if legs is Array and (legs as Array).size() < 3:
			continue
		var end := lp[lp.size() - 1]
		if path.distance_to(end) > 2.5:
			continue
		var ls := path.project(end)
		var npos: Vector3 = it.get("position", end)
		var rad := float(it.get("radius", 8.0))
		# path distance from the stop line to where the rails leave the junction circle
		var cross := 0.0
		while cross < 60.0:
			cross += 1.0
			var q := path.sample(ls + cross)
			if Vector2(q.x - npos.x, q.z - npos.z).length() > rad + 0.5:
				break
		lines.append({"s": ls, "lane": lid, "signal": int(lane.get("signal_group", -1)) >= 0,
				"yield": bool(lane.get("yield", false)), "node": node, "pos": npos, "radius": rad, "cross": cross})
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) < float(b["s"]))


func _spawn_trams() -> void:
	if not _ready_world or not is_inside_tree():
		return
	var starts: Array[int] = [0]
	if TRAM_COUNT > 1 and stops.size() > 1:
		# the stop nearest to half a loop from the first one
		var want := path.wrap_s(float(stops[0]["s"]) + path.length * 0.5)
		var best := 1
		var best_d := INF
		for i in range(1, stops.size()):
			var dd := absf(path.delta(float(stops[i]["s"]), want))
			if dd < best_d:
				best_d = dd
				best = i
		starts.append(best)
	for i in mini(TRAM_COUNT, starts.size()):
		var t := TransitTram.new()
		add_child(t)
		if not t.setup(self, i):
			t.queue_free()
			continue
		var si := starts[i]
		t.s = float(stops[si]["s"])
		t.v = 0.0
		t.visits.resize(stops.size())
		t.visits.fill(0)
		t.phase = TransitTram.Phase.DWELL
		t.dwell_t = 0.0 if i == 0 else 5.0
		t.dwell_len = DWELL
		t.last_stop = si
		t.next_stop = (si + 1) % stops.size()
		t.line_idx = _first_line_ahead(t.s + HALF_LEN)
		t.place(path, BOGIE)
		trams.append(t)


func _first_line_ahead(nose: float) -> int:
	if lines.is_empty():
		return 0
	var best := 0
	var best_d := INF
	for i in lines.size():
		var d := path.ahead(nose, float(lines[i]["s"]))
		if d < best_d:
			best_d = d
			best = i
	return best


func _exit_tree() -> void:
	trams.clear()


# =================================================================================================
# public API
# =================================================================================================

func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if not on:
		_put_player_off_all()
		for t: TransitTram in trams:
			if is_instance_valid(t):
				t.queue_free()
		trams.clear()
		_rider = null
	else:
		_try_init()
		_spawn_trams()


## Death / arrest: nothing transient to forget except the rider bookkeeping.
func reset_for_respawn() -> void:
	_rider = null
	_rider_seated = false


func get_trams() -> Array:
	return trams.duplicate()


func get_stops() -> Array[Dictionary]:
	return stops


func get_path_length() -> float:
	return path.length if path != null else 0.0


## The tram the player rides (standing inside or seated), or null.
func get_player_tram() -> Node3D:
	return _rider if _rider != null and is_instance_valid(_rider) else null


func is_player_aboard() -> bool:
	return get_player_tram() != null


func get_tram_info(i: int) -> Dictionary:
	if i < 0 or i >= trams.size() or not is_instance_valid(trams[i]):
		return {}
	var t := trams[i]
	return {"name": String(t.name), "s": t.s, "v": t.v, "phase": "dwell" if t.phase == TransitTram.Phase.DWELL else "run",
			"door": t.door, "next_stop": str(stops[t.next_stop]["name"]) if not stops.is_empty() else "",
			"last_stop": str(stops[t.last_stop]["name"]) if t.last_stop >= 0 and t.last_stop < stops.size() else "",
			"hold": t.hold, "obstacle_gap": t.obs_gap, "obstacle_kind": t.obs_kind,
			"obstacle": String(t.obs_node.name) if t.obs_node != null and is_instance_valid(t.obs_node) else "",
			"line": _line_info(t), "loops": t.loops,
			"visits": t.visits, "position": t.global_position, "odometer": t.odometer}


func _line_info(t: TransitTram) -> String:
	if lines.is_empty() or t.line_idx < 0 or t.line_idx >= lines.size():
		return ""
	var ln: Dictionary = lines[t.line_idx]
	var roads: Variant = Game.world.get("roads") if Game.world != null else null
	var sig := int(roads.get_signal_state(int(ln["lane"]))) if roads != null else -1
	return "#%d lane %d node %d d %.1f sig %s/%d yield %s committed %s" % [t.line_idx, int(ln["lane"]), int(ln["node"]),
			path.delta(t.s + HALF_LEN, float(ln["s"])), str(ln["signal"]), sig, str(ln["yield"]), str(t.committed_line == t.line_idx)]


func get_debug_info() -> Dictionary:
	var out := {"enabled": enabled, "trams": trams.size(), "stops": stops.size(), "lines": lines.size(),
			"loop_m": get_path_length(), "player_aboard": is_player_aboard(), "player_seated": _rider_seated,
			"cost_ms": snappedf(_cost_avg, 0.001)}
	for k: String in stats:
		out[k] = stats[k]
	var ts: Array = []
	for i in trams.size():
		ts.append(get_tram_info(i))
	out["tram_list"] = ts
	return out


## Interactable "Board the tram" (open right door d): the player steps in onto the floor.
func board(t: TransitTram, d: int) -> bool:
	var p := Game.player
	if p == null or not is_instance_valid(p) or t == null or not is_instance_valid(t) or not t.is_door_open():
		return false
	if p.get("current_vehicle") != null:
		return false
	# the standing spot of that vestibule that is nearer to the door centre
	var pos := t.stand_point(0 if d == 0 else 2)
	var f := -t.global_basis.z
	var yaw := atan2(-f.x, -f.z)
	if p.has_method("teleport"):
		p.call("teleport", pos + Vector3.UP * 0.04, yaw)
	else:
		p.global_position = pos + Vector3.UP * 0.04
	Audio.play_at("footstep_metal", pos, -6.0, 1.0, 20.0)
	stats["boardings"] = int(stats["boardings"]) + 1
	_rider = t
	_rider_seated = false
	if not _hinted:
		_hinted = true
		UI.notify("Bay Tram: sit down at a seat, get off at any stop", "info", 4.5)
	return true


## Interactable "Get off" (open door d, from inside): the player steps out beside the door.
func alight(t: TransitTram, d: int) -> bool:
	var p := Game.player
	if p == null or not is_instance_valid(p) or t == null or not is_instance_valid(t) or not t.is_door_open():
		return false
	var out := t.door_point(d, 0.95)
	var gy := Game.ground_height(out.x, out.z)
	var r := t.global_basis.x
	var yaw := atan2(-r.x, -r.z)
	if p.has_method("teleport"):
		p.call("teleport", Vector3(out.x, gy + 0.03, out.z), yaw)
	stats["alightings"] = int(stats["alightings"]) + 1
	_rider = null
	_rider_seated = false
	return true


## Interactable "Sit down": the player's vehicle-seat contract (TransitTram seats 1..4).
func sit(t: TransitTram, seat: int) -> bool:
	var p := Game.player
	if p == null or not is_instance_valid(p) or t == null or not is_instance_valid(t) or not p.has_method("enter_vehicle"):
		return false
	if t.get_occupant(seat) != null:
		return false
	# while the car moves the seat is taken at once (the vehicle state's slide is in world space)
	p.call("enter_vehicle", t, seat, absf(t.v) > 0.2)
	return true


## Interactable "Stand up" (enter-vehicle key while seated): back on the floor in the aisle.
func stand_up(t: TransitTram) -> bool:
	var p := Game.player
	if p == null or not is_instance_valid(p) or t == null or not is_instance_valid(t):
		return false
	var seat := t.get_seat_of(p)
	if seat < 1:
		return false
	var xf := t.get_exit_transform(seat)
	var f := -t.global_basis.z
	if p.has_method("teleport"):
		p.call("teleport", xf.origin + Vector3.UP * 0.03, atan2(-f.x, -f.z))   # leaves the seat (occupant_exit) first
	_rider = t
	_rider_seated = false
	return true


func _on_rider_seated(t: TransitTram, who: Node, _seat: int) -> void:
	if who != null and who == Game.player:
		_rider = t
		_rider_seated = true
		stats["seated"] = int(stats["seated"]) + 1


# =================================================================================================
# manager loop
# =================================================================================================

func _physics_process(delta: float) -> void:
	if not enabled or trams.is_empty() or path == null:
		return
	var t0 := Time.get_ticks_usec()
	var focus := Game.get_player_position() if Game.has_player() else Vector3.ZERO
	_env_t -= delta
	if _env_t <= 0.0:
		_env_t = 1.0
		_night = WorldClock.get_daylight() < 0.35
		for t: TransitTram in trams:
			if is_instance_valid(t):
				var dd := t.global_position.distance_to(focus)
				t.set_lamps(_night, _night and dd < 150.0)
				t.set_detail(dd < 95.0)
	for t: TransitTram in trams:
		if is_instance_valid(t):
			_drive(t, delta, focus)
	_update_rider()
	_cost_avg = lerpf(_cost_avg, float(Time.get_ticks_usec() - t0) / 1000.0, 0.02)


func _drive(t: TransitTram, dt: float, focus: Vector3) -> void:
	var dist := t.global_position.distance_to(focus)
	var near := dist < NEAR_AUDIO
	t.bell_cd = maxf(t.bell_cd - dt, 0.0)
	if t.phase == TransitTram.Phase.DWELL:
		_dwell(t, dt, near)
		return
	var vt := V_MAX
	t.hold = ""
	var nose := t.s + HALF_LEN
	# curves (profile already includes braking into them)
	var vc := path.speed_limit(t.s)
	if vc < vt:
		vt = vc
		t.hold = "curve"
	# next stop
	var st: Dictionary = stops[t.next_stop]
	var d_stop := path.ahead(t.s, float(st["s"]))
	if d_stop > path.length - 3.0:
		d_stop = 0.0                                   # a hair past the mark: we are there
	var v_st := sqrt(2.0 * B_COMF * maxf(d_stop - 0.05, 0.0))
	if v_st < vt:
		vt = v_st
		t.hold = "stop"
	if d_stop < 0.4 and t.v < 0.5:
		_arrive(t, near)
		return
	# obstacles (box queries ahead of the nose, 20 Hz near / 5 Hz far)
	t.obs_t -= dt
	if t.obs_t <= 0.0:
		t.obs_t = 0.05 if dist < 160.0 else 0.2
		_scan_obstacles(t, nose)
	# junction stop lines
	var vj := _line_control(t, nose)
	if vj < vt:
		vt = vj
	if t.obs_gap < INF:
		var gap := maxf(t.obs_gap - GAP_STOP, 0.0)
		var vl := maxf(t.obs_v, 0.0)
		var vo := minf(sqrt(vl * vl + 2.0 * B_FOLLOW * gap), gap / HEADWAY + 0.4 * vl)
		if vo < vt:
			vt = vo
			t.hold = "obstacle"
	# speed: accelerate gently, brake as hard as needed (the targets follow braking curves)
	var prev_v := t.v
	if vt > t.v:
		t.v = minf(t.v + A_ACC * dt, vt)
	else:
		t.v = maxf(t.v - B_MAX * dt, vt)
	t.v = maxf(t.v, 0.0)
	var hard := (prev_v - t.v) / maxf(dt, 0.0001) > B_COMF * 2.2 and prev_v > 2.0
	if hard and not t.braking_hard:
		stats["emergency_brakes"] = int(stats["emergency_brakes"]) + 1
		if Game.flags.has("trn_log"):
			print("TRANSIT: hard brake %s v %.1f -> %.1f hold %s obs %s gap %.1f kind %d line %s" % [t.name, prev_v, t.v, t.hold,
					String(t.obs_node.name) if t.obs_node != null and is_instance_valid(t.obs_node) else "-", t.obs_gap, t.obs_kind, _line_info(t)])
	t.braking_hard = hard
	if t.v > float(stats["top_speed"]):
		stats["top_speed"] = snappedf(t.v, 0.01)
	var ds := t.v * dt
	t.s = path.wrap_s(t.s + ds)
	t.odometer += ds
	t.place(path, BOGIE)
	t.door_target = 0.0
	t.update_doors(dt, DOOR_TIME)
	t.update_audio(dt, near)
	_blocked(t, dt, dist)
	t.last_hold = t.hold


func _dwell(t: TransitTram, dt: float, near: bool) -> void:
	t.v = 0.0
	t.hold = "stop"
	t.dwell_t += dt
	var close_at := t.dwell_len - DOOR_TIME
	if t.dwell_t < close_at:
		t.door_target = 1.0 if t.dwell_t > 0.5 else 0.0
	elif _doorway_busy(t) and t.dwell_len < DWELL + DWELL_EXTRA_MAX:
		t.dwell_len = minf(t.dwell_len + dt, DWELL + DWELL_EXTRA_MAX)
		t.door_target = 1.0
	else:
		t.door_target = 0.0
	if t.door_target > 0.5 and t.door < 0.02 and near:
		Audio.play_at("door_open", t.global_position, -4.0, 0.8, 30.0)
	elif t.door_target < 0.5 and t.door > 0.98 and near:
		Audio.play_at("door_close", t.global_position, -4.0, 0.8, 30.0)
	t.update_doors(dt, DOOR_TIME)
	t.update_audio(dt, near)
	if t.dwell_t >= t.dwell_len and t.door <= 0.0:
		t.phase = TransitTram.Phase.RUN
		t.committed_line = -1
		t.obs_t = 0.0
		stats["departures"] = int(stats["departures"]) + 1
		if near:
			t.ring_bell()
		if _rider == t and is_player_aboard():
			UI.notify("Next stop: %s" % str(stops[t.next_stop]["label"]), "info", 3.0)


func _arrive(t: TransitTram, near: bool) -> void:
	var st: Dictionary = stops[t.next_stop]
	t.s = float(st["s"])
	t.v = 0.0
	t.place(path, BOGIE)
	t.phase = TransitTram.Phase.DWELL
	t.dwell_t = 0.0
	t.dwell_len = DWELL
	t.hold = "stop"
	t.blocked_t = 0.0
	var vis := t.visits
	if vis.size() != stops.size():
		vis.resize(stops.size())
	vis[t.next_stop] += 1
	t.visits = vis
	# a full loop = every stop served since the last time this stop was served
	if t.last_stop >= 0 and t.next_stop == 0 and t.odometer > path.length * 0.9 * float(t.loops + 1):
		t.loops += 1
		stats["loops"] = int(stats["loops"]) + 1
	t.last_stop = t.next_stop
	t.next_stop = (t.next_stop + 1) % stops.size()
	stats["arrivals"] = int(stats["arrivals"]) + 1
	if near:
		t.ring_bell()
	if _rider == t and is_player_aboard():
		UI.notify("%s - doors open" % str(st["label"]), "info", 3.0)


## Someone stands in an open doorway (or right outside it, about to step in): keep the doors open.
func _doorway_busy(t: TransitTram) -> bool:
	if not Game.has_player():
		return false
	var p := Game.player
	if p.get("current_vehicle") != null:
		return false
	var l := t.to_local_point(p.global_position)
	for z: float in TransitTram.DOOR_Z:
		if absf(l.z - z) < 1.0 and l.x > 0.5 and l.x < 2.4 and l.y > -0.6 and l.y < 1.2:
			return true
	return false


# =================================================================================================
# junctions
# =================================================================================================

func _line_control(t: TransitTram, nose: float) -> float:
	if lines.is_empty():
		return INF
	var n := lines.size()
	for _guard in n:
		var ln0: Dictionary = lines[t.line_idx]
		if path.delta(nose, float(ln0["s"])) < -STOP_MARGIN - 1.5:
			if t.committed_line == t.line_idx:
				t.committed_line = -1
			t.line_idx = (t.line_idx + 1) % n
			continue
		break
	var ln: Dictionary = lines[t.line_idx]
	var d_line := path.delta(nose, float(ln["s"])) - STOP_MARGIN
	if d_line > SIGNAL_LOOK or d_line < -1.0 or t.committed_line == t.line_idx:
		return INF
	var roads: Variant = Game.world.get("roads") if Game.world != null else null
	var need_dec := t.v * t.v / (2.0 * maxf(d_line, 0.05))
	var why := ""
	var cap := INF
	if bool(ln["signal"]) and roads != null:
		var lane := int(ln["lane"])
		var sig := int(roads.get_signal_state(lane))
		if sig == 2:
			why = "signal"
		elif sig == 1:
			if need_dec <= B_COMF * 1.6:
				why = "signal"
		else:
			# green about to end (yellow + all-red follow): a standing / slow tram waits for the next
			# green instead of starting an 18 m crossing in the last seconds
			var left := float(roads.get_signal_time_left(lane)) if roads.has_method("get_signal_time_left") else 99.0
			if left < GREEN_MIN_LEFT and need_dec <= B_COMF:
				why = "signal"
	if why == "" and bool(ln["yield"]):
		cap = sqrt(16.0 + 2.0 * B_COMF * maxf(d_line, 0.0))     # approach the line at <= 4 m/s
		if d_line < 8.0 and not _junction_clear(ln):
			why = "yield"
	# do not block the box: something stands right behind the junction
	if why == "" and t.obs_gap < INF and t.obs_v < 1.5:
		var room := t.obs_gap - GAP_STOP
		if room > d_line and room < d_line + STOP_MARGIN + float(ln["cross"]) + 2.0 * HALF_LEN:
			why = "box"
	if why == "":
		if d_line < 2.5:
			t.committed_line = t.line_idx
		return cap
	if need_dec > B_MAX:
		# too late to stop before the line: go through
		t.committed_line = t.line_idx
		return cap
	if t.last_hold != why and why == "signal":
		stats["signal_holds"] = int(stats["signal_holds"]) + 1
	t.hold = why
	# a stop decided late (light turned yellow) uses the deceleration it needs from here on, not a
	# jump onto the comfortable curve (which would mean a short emergency brake)
	return sqrt(2.0 * clampf(need_dec, B_COMF, B_MAX) * maxf(d_line, 0.0))


## Minor approach: nothing moving inside / about to enter the junction circle.
func _junction_clear(ln: Dictionary) -> bool:
	if not is_inside_tree():
		return true
	(_sphere_q.shape as SphereShape3D).radius = float(ln["radius"]) + 4.0
	_sphere_q.transform = Transform3D(Basis.IDENTITY, (ln["pos"] as Vector3) + Vector3.UP)
	_sphere_q.exclude = []
	var hits := get_world_3d().direct_space_state.intersect_shape(_sphere_q, 16)
	for h: Dictionary in hits:
		var c: Variant = h.get("collider")
		if c is RigidBody3D and (c as RigidBody3D).linear_velocity.length() > 1.0:
			return false
		if c is TransitTram and absf((c as TransitTram).v) > 0.5:
			return false
	return true


# =================================================================================================
# obstacles
# =================================================================================================

func _scan_obstacles(t: TransitTram, nose: float) -> void:
	t.obs_gap = INF
	t.obs_v = 0.0
	t.obs_kind = 0
	t.obs_node = null
	if not is_inside_tree():
		return
	var length := clampf(t.v * t.v / (2.0 * B_COMF) + 14.0, 16.0, 44.0)
	# approaching a junction: look past it for the whole car ("do not block the box")
	if not lines.is_empty():
		var ln: Dictionary = lines[t.line_idx]
		var d_line := path.delta(nose, float(ln["s"]))
		if d_line > -1.0 and d_line < 30.0:
			length = clampf(maxf(length, d_line + float(ln["cross"]) + 2.0 * HALF_LEN + GAP_STOP + 2.0), 16.0, 64.0)
	var pieces := int(ceil(length / 7.5))
	var piece := length / float(pieces)
	var space := get_world_3d().direct_space_state
	_excl[0] = t.get_rid()
	_q.exclude = _excl
	for b in pieces:
		var a0 := nose + piece * float(b) - 0.6
		var pa := path.sample(a0)
		var pc := path.sample(a0 + piece)
		var dir := pc - pa
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			continue
		dir = dir.normalized()
		_box.size = Vector3(2.9, 1.7, piece + 0.3)
		_q.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), (pa + pc) * 0.5 + Vector3.UP * 1.25)
		var hits := space.intersect_shape(_q, 10)
		var found := false
		for h: Dictionary in hits:
			var node := h.get("collider") as Node3D
			if node == null or not is_instance_valid(node) or node == t:
				continue
			if node is StaticBody3D and not (node is TransitTram):
				# static street furniture (compound PROP bodies of lamps / signals) is part of the world:
				# nothing the tram could wait for - noted once for the report
				_note_static(node, h)
				continue
			var kind := 4
			var extent := 0.5
			var ov := 0.0
			if node is TransitTram:
				kind = 3
				extent = HALF_LEN
				ov = (node as TransitTram).v
			elif node.is_in_group("vehicle"):
				kind = 2
				var rb := node as RigidBody3D
				if rb != null:
					ov = rb.linear_velocity.dot(dir)
				var aabb: Variant = node.get("body_aabb")
				if aabb is AABB:
					var nb := node.global_transform.basis
					extent = absf(nb.z.dot(dir)) * (aabb as AABB).size.z * 0.5 + absf(nb.x.dot(dir)) * (aabb as AABB).size.x * 0.5
				else:
					extent = 2.0
			elif node is CharacterBody3D or node.is_in_group("player") or node.is_in_group("npc") or node.is_in_group("animal"):
				kind = 1
				extent = 0.4
				var cb := node as CharacterBody3D
				if cb != null:
					ov = cb.velocity.dot(dir)
				# the player riding in / on the other tram is part of that tram's load
				if _rider != null and node == Game.player and _rider != t:
					continue
				# people waiting on the kerb inside a corner (the car's swept area reaches over the
				# corner of the sidewalk in the 14 m turns) are not on the rails
				if _on_sidewalk(node.global_position, pa.y):
					continue
			else:
				# street furniture standing on the sidewalk corner (asleep / static) is not on the rails
				var rbp := node as RigidBody3D
				if (rbp == null or rbp.sleeping or rbp.freeze) and _on_sidewalk(node.global_position, pa.y):
					continue
			var along := path.ahead(nose, path.project(node.global_position))
			if along > length + 12.0:
				along = piece * float(b)         # projection wrapped (behind the nose): treat as here
			var gap := maxf(along - extent, 0.0)
			found = true
			if gap < t.obs_gap:
				t.obs_gap = gap
				t.obs_v = ov
				t.obs_kind = kind
				t.obs_node = node
		if found:
			return


func _note_static(node: Node3D, h: Dictionary) -> void:
	var key := "%d:%d" % [node.get_instance_id(), int(h.get("shape", 0))]
	if _static_seen.has(key) or _static_seen.size() > 64:
		return
	var p := node.global_position
	var rid: Variant = h.get("rid")
	if rid is RID:
		p = node.global_transform * PhysicsServer3D.body_get_shape_transform(rid, int(h.get("shape", 0))).origin
	_static_seen[key] = p
	stats["static_in_corridor"] = _static_seen.size()
	if Game.flags.has("trn_log"):
		print("TRANSIT: static %s shape %d at %s (path lateral %.2f m)" % [node.name, int(h.get("shape", 0)), str(p.snapped(Vector3.ONE * 0.01)),
				path.lateral(path.project(p), p)])


## Stands on a kerb / sidewalk / slab (not on the carriageway the rails lie in).
func _on_sidewalk(p: Vector3, road_y: float) -> bool:
	return Game.ground_height(p.x, p.z) > road_y + 0.07


func _blocked(t: TransitTram, dt: float, dist: float) -> void:
	if t.v > 0.3 or t.hold != "obstacle" or t.obs_node == null or not is_instance_valid(t.obs_node):
		if t.v > 0.3:
			t.blocked_t = 0.0
		return
	if t.blocked_t <= 0.0:
		stats["obstacle_holds"] = int(stats["obstacle_holds"]) + 1
	t.blocked_t += dt
	# warning bell for people / vehicles on the rails
	if t.blocked_t > 1.2 and t.bell_cd <= 0.0 and dist < 120.0 and t.obs_kind in [1, 2]:
		t.bell_cd = 4.5
		t.ring_bell()
		stats["bells"] = int(stats["bells"]) + 1
	if t.obs_kind == 2 and t.blocked_t > TOW_TIME:
		if _tow(t.obs_node):
			t.blocked_t = 0.0


## A vehicle has blocked the rails for TOW_TIME: remove it if it is nobody's (no player link, not
## driven by the player, not watched by the camera). Traffic cars go through the traffic API.
func _tow(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node == Game.get_player_vehicle() or node.get("is_player_driven") == true or str(node.get("owner_tag")) == "player" \
			or node.get("personal") == true:
		return false
	var n3 := node as Node3D
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if n3 != null and cam != null and cam.is_position_in_frustum(n3.global_position) and cam.global_position.distance_to(n3.global_position) < 200.0:
		return false
	if n3 != null and Game.has_player() and n3.global_position.distance_to(Game.player.global_position) < 30.0:
		return false
	var drv: Variant = node.get("driver")
	var ctrl: Variant = node.get_meta("ai_controller") if node.has_meta("ai_controller") else null
	var traffic := Game.get_system("traffic")
	if drv != null and is_instance_valid(drv):
		# only traffic cars (police / emergency crews move on their own)
		if ctrl == null or ctrl != traffic or not traffic.has_method("release_vehicle"):
			return false
		traffic.call("release_vehicle", node, "despawn")
	var vm := Game.get_system("vehicles")
	if vm != null and vm.has_method("despawn_vehicle"):
		vm.call("despawn_vehicle", node)
	elif traffic != null and traffic.has_method("despawn_vehicle_node"):
		traffic.call("despawn_vehicle_node", node)
	else:
		node.queue_free()
	stats["tows"] = int(stats["tows"]) + 1
	return true


# =================================================================================================
# rider bookkeeping
# =================================================================================================

func _update_rider() -> void:
	if not Game.has_player():
		_rider = null
		return
	var p := Game.player
	var cv: Variant = p.get("current_vehicle")
	if cv != null and is_instance_valid(cv) and cv is TransitTram:
		_rider = cv as TransitTram
		_rider_seated = true
		return
	_rider_seated = false
	if cv != null:
		_rider = null
		return
	var pos := p.global_position
	var found: TransitTram = null
	for t: TransitTram in trams:
		if is_instance_valid(t) and t.global_position.distance_squared_to(pos) < 144.0 and t.contains_point(pos, 0.2):
			found = t
			break
	_rider = found


## Disabling the trams with the player aboard: put the player beside the car first.
func _put_player_off_all() -> void:
	var t := get_player_tram() as TransitTram
	if t == null or not Game.has_player():
		return
	var p := Game.player
	var out := t.door_point(0, 0.95)
	var gy := Game.ground_height(out.x, out.z)
	if p.has_method("teleport"):
		p.call("teleport", Vector3(out.x, gy + 0.03, out.z), p.global_rotation.y)
