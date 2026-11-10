class_name AiEmergencyDriver
extends RefCounted
## Driving brain of ONE emergency vehicle (ambulance / fire truck). A plain state object: the
## emergency system's single loop calls tick() (15 Hz near the player, 5 Hz far); nothing here has
## its own _process. Implements the W2.1 `ai_controller` contract: the vehicle carries
## set_meta("ai_controller", <this object>) and release_vehicle(vehicle, reason).
##
## Modes:
##   route    lane route (A* on the RoadGraph) to a destination; `urgent` = siren run (faster,
##            crosses red lights at a careful speed, passes cars that pull over), calm = obeys
##            signals at the lane limit (driving away after a job)
##   parked   arrived: hand brake, the crew works on foot
##   hold     brakes (no driver, waiting for the crew to board)
## Shared: obstacle ray + swept "person box" (never runs anybody over on purpose), swerving round
## stopped cars, three-point turns, stuck recovery (reverse with opposite lock), flip detection.

enum Mode { ROUTE, PARKED, HOLD }
const MODE_NAMES: Array[String] = ["route", "parked", "hold"]

const A_LAT_FAST := 5.2             ## lateral acceleration used for corners on a siren run (m/s^2)
const A_LAT_CALM := 3.2
const B_FAST := 5.0                 ## braking assumed by the speed planning
const B_CALM := 2.6
const URGENT_SPEED_MULT := 1.35     ## x lane speed limit on a siren run
const CALM_SPEED_MULT := 0.85
const MAX_URGENT_SPEED := 22.0      ## m/s
const STUCK_TIME := 1.8
const REVERSE_TIME := 1.5
const KTURN_ANGLE := 2.0
const CUT_TOLERANCE := 1.3
const PERSON_BOX_WIDTH := 3.2
const SWERVE := 2.4
const LANE_CHANGE_COST := 12.0
const UTURN_COST := 45.0
const KERB_SHIFT := 1.1              ## pull this far to the right over the last KERB_BLEND metres of a job route
const KERB_BLEND := 22.0

var system: Node = null
var vehicle: RigidBody3D = null
var crew: Array[Node3D] = []        ## responders of this vehicle (seated or on foot)
var mode: int = Mode.HOLD
var mode_t: float = 0.0
var urgent: bool = true
var released: bool = false
var dest: Vector3 = Vector3.INF
var arrived: bool = false           ## the last route ended and the car stands
var failed_plans: int = 0
var drive_time: float = 0.0         ## seconds spent in ROUTE since the last drive_to()
var think_acc: float = 0.0
var stats := {"plans": 0, "recoveries": 0, "kturns": 0, "swerves": 0, "person_stops": 0}
var last_block: String = ""

# route ------------------------------------------------------------------------------------------
var route := PackedVector3Array()
var route_cum := PackedFloat32Array()
var route_vmax := PackedFloat32Array()
var route_stop_s := PackedFloat32Array()   ## arc length of the stop lines along the route
var route_stop_lane := PackedInt32Array()  ## lane whose signal governs that stop
var route_i: int = 0
var route_s: float = 0.0
var stop_short: float = 0.0                ## stop this far before the end of the route

# driving state ----------------------------------------------------------------------------------
var throttle: float = 0.0
var steer: float = 0.0
var brake: float = 0.0
var wheelbase: float = 3.4
var max_steer: float = deg_to_rad(34.0)
var grip: float = 1.0
var half_len: float = 3.0
var _stuck_t: float = 0.0
var _reverse_t: float = 0.0
var _reverse_steer: float = 0.0
var _recoveries: Array[float] = []
var _flip_t: float = 0.0
var _avoid: float = 0.0
var _avoid_t: float = 0.0
var _kturn_t: float = 0.0
var _kturn_dir: float = 1.0
var _clock: float = 0.0
var _hopeless: bool = false
var _emergency_stop: bool = false
var _person_wait_since: float = -1.0
var _rng := RandomNumberGenerator.new()
var _ray: PhysicsRayQueryParameters3D = null
var _person_q: PhysicsShapeQueryParameters3D = null
var _person_box := BoxShape3D.new()
var _left: float = INF                     ## metres to the stopping point of the current route


func setup(p_system: Node, v: RigidBody3D, p_crew: Array) -> void:
	system = p_system
	vehicle = v
	crew.clear()
	for c: Variant in p_crew:
		if c is Node3D and is_instance_valid(c):
			crew.append(c as Node3D)
	_rng.seed = v.get_instance_id() ^ 0x2c1b3c6d
	think_acc = _rng.randf() * 0.06
	var wb: Variant = v.get("wheelbase")
	if (wb is float or wb is int) and float(wb) > 0.8:
		wheelbase = float(wb)
	var spec: Variant = v.get("spec")
	if spec is Object and spec != null:
		var ms: Variant = (spec as Object).get("max_steer_angle")
		if ms is float or ms is int:
			max_steer = deg_to_rad(clampf(float(ms), 15.0, 50.0))
		var gf: Variant = (spec as Object).get("grip_front")
		if gf is float or gf is int:
			grip = clampf(float(gf), 0.6, 1.8)
	var aabb: Variant = v.get("body_aabb")
	if aabb is AABB:
		half_len = maxf((aabb as AABB).size.z * 0.5, 1.8)
		if not ((wb is float or wb is int) and float(wb) > 0.8):
			wheelbase = clampf((aabb as AABB).size.z * 0.58, 2.4, 5.0)
	var ex: Array[RID] = [v.get_rid()]
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = Layers.VEHICLE | Layers.NPC | Layers.PLAYER | Layers.PROP | Layers.WORLD
	_ray.hit_back_faces = false
	_ray.exclude = ex
	mode = Mode.HOLD


func get_mode_name() -> String:
	return MODE_NAMES[mode]


func is_valid() -> bool:
	return not released and vehicle != null and is_instance_valid(vehicle) and vehicle.is_inside_tree() \
			and not vehicle.is_queued_for_deletion()


func is_hopeless() -> bool:
	return _hopeless


func get_position() -> Vector3:
	return vehicle.global_position if vehicle != null and is_instance_valid(vehicle) else Vector3.INF


## The responder in the driver seat (null when nobody of ours sits there).
func seated_driver() -> Node3D:
	if vehicle == null or not is_instance_valid(vehicle):
		return null
	var d: Variant = vehicle.get("driver")
	if d is Node3D and is_instance_valid(d) and crew.has(d) and (d as Node3D).get("is_dead") != true:
		return d as Node3D
	return null


func seated_crew() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in crew:
		if is_instance_valid(c) and c.get("is_dead") != true and c.get("current_vehicle") == vehicle:
			out.append(c)
	return out


# =================================================================================================
# W2.1 ai_controller contract
# =================================================================================================

## Stop controlling `v`. "carjacked" / "abandon" / "crash": the driver leaves beside the door as a
## real NPC (returned) and the other seated responders get out too; "despawn" / "destroyed":
## clean-up only. Afterwards the vehicle has no ai_controller meta and driver == null.
func release_vehicle(v: Node3D, reason: String) -> Node3D:
	if v == null or not is_instance_valid(v) or v != vehicle:
		return null
	if released:
		return null
	released = true
	var drv := seated_driver()
	var out: Node3D = null
	if reason in ["carjacked", "abandon", "crash"]:
		# everybody of ours gets out; the driver is handed back to the caller (the player module
		# throws it to the ground for a carjacking)
		for c in seated_crew():
			if c == drv and reason == "carjacked":
				continue
			if c.has_method("exit_vehicle"):
				c.call("exit_vehicle")
		if drv != null and reason == "carjacked" and drv.get("current_vehicle") == v and drv.has_method("exit_vehicle"):
			drv.call("exit_vehicle")
		out = drv
	else:
		for c in seated_crew():
			if c.has_method("exit_vehicle"):
				c.call("exit_vehicle")
	if v.has_method("release_inputs"):
		v.call("release_inputs")
	if v.has_meta("ai_controller") and v.get_meta("ai_controller") == self:
		v.remove_meta("ai_controller")
	if v.get("driver") != null and crew.has(v.get("driver")) and v.has_method("occupant_exit"):
		v.call("occupant_exit", 0)
	if v.has_method("set_siren") and v.get("is_player_driven") != true:
		v.call("set_siren", false)
	if system != null and is_instance_valid(system) and system.has_method("_on_driver_released"):
		system.call("_on_driver_released", self, reason)
	return out


# =================================================================================================
# orders (from the emergency system)
# =================================================================================================

## Plan a lane route to `target`. `stop_before` = metres before the route end to stop (keep clear
## of the bodies / the fire). False when no route exists.
func drive_to(target: Vector3, p_urgent: bool, stop_before: float = 0.0) -> bool:
	urgent = p_urgent
	stop_short = maxf(stop_before, 0.0)
	arrived = false
	drive_time = 0.0
	_set_siren(urgent)
	if _plan_to(target):
		mode = Mode.ROUTE
		mode_t = 0.0
		failed_plans = 0
		return true
	failed_plans += 1
	return false


## Random calm route of about 400 m (driving away after the job).
func drive_away() -> bool:
	urgent = false
	stop_short = 0.0
	arrived = false
	drive_time = 0.0
	_set_siren(false)
	if _plan_wander():
		mode = Mode.ROUTE
		mode_t = 0.0
		return true
	return false


func park() -> void:
	mode = Mode.PARKED
	mode_t = 0.0
	route.clear()


func hold() -> void:
	mode = Mode.HOLD
	mode_t = 0.0


func remaining() -> float:
	if route.size() < 2:
		return 0.0
	return maxf(_route_len() - stop_short - route_s, 0.0)


# =================================================================================================
# tick
# =================================================================================================

func tick(dt: float) -> void:
	if not is_valid():
		return
	_clock += dt
	mode_t += dt
	if _avoid_t > 0.0:
		_avoid_t -= dt
		if _avoid_t <= 0.0:
			_avoid = 0.0
	if vehicle.get("destroyed") == true:
		return
	match mode:
		Mode.PARKED, Mode.HOLD:
			_hold_brake()
			return
	var drv := seated_driver()
	if drv == null:
		_hold_brake()
		return
	drive_time += dt
	if _flip_check(dt):
		return
	if _reverse_t > 0.0:
		_reverse_t -= dt
		if _rear_blocked(vehicle.global_transform):
			_reverse_t = 0.0
			_hold_brake()
			return
		_apply(-0.75, _reverse_steer, 0.0, false)
		return
	if route.size() < 2:
		_hold_brake()
		return
	_follow_route(dt)
	_stuck_check(dt)


func _follow_route(dt: float) -> void:
	var xf := vehicle.global_transform
	var pos := xf.origin
	var spd := _fwd_speed()
	if not _advance_cursor(pos):
		# far off the route (pushed, recovered): plan again towards the same destination
		if dest != Vector3.INF and urgent:
			_plan_to(dest)
		else:
			_plan_wander()
		_hold_brake()
		return
	var end_s := _route_len() - stop_short
	var left := end_s - route_s
	_left = left
	if left <= 0.8:
		if absf(spd) < 0.8:
			arrived = true
			park()
			return
		_hold_brake()
		return
	var look := clampf(absf(spd) * 0.7 + 5.5, 6.5, 22.0)
	var aim := _route_point_at(route_s + look)
	for _k in 3:
		if look <= 6.5 or _seg_dev(pos, aim, _route_point_at(route_s + look * 0.5)) <= CUT_TOLERANCE:
			break
		look *= 0.65
		aim = _route_point_at(route_s + look)
	var vt := _route_vmax_ahead()
	vt = minf(vt, _curve_speed(spd))
	vt = minf(vt, _signal_speed())
	vt = minf(vt, sqrt(2.0 * (B_FAST if urgent else B_CALM) * maxf(left - 1.0, 0.0)) + 0.6)
	if _kturn(xf, aim, spd, dt):
		return
	vt = minf(vt, _turn_speed(xf, aim))
	vt = _obstacles(xf, spd, vt, aim)
	if _avoid != 0.0:
		var side := xf.basis.x
		side.y = 0.0
		aim += side.normalized() * _avoid
	if stop_short > 0.0 and left < KERB_BLEND:
		# arriving at a scene: ease over towards the kerb so traffic can pass on the left
		var side2 := xf.basis.x
		side2.y = 0.0
		aim += side2.normalized() * KERB_SHIFT * clampf(1.0 - left / KERB_BLEND, 0.0, 1.0)
	var st := _pursuit_steer(xf, aim, spd)
	_pedals(vt, spd)
	_apply(throttle, st, brake, false)


# =================================================================================================
# route following helpers
# =================================================================================================

func _route_len() -> float:
	return route_cum[route_cum.size() - 1] if route_cum.size() > 0 else 0.0


func _advance_cursor(pos: Vector3) -> bool:
	var n := route.size()
	if n < 2:
		return false
	var best_d := INF
	var best_i := route_i
	var best_s := route_s
	var last := mini(route_i + 14, n - 2)
	for i in range(route_i, last + 1):
		var a := route[i]
		var b := route[i + 1]
		var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var l2 := ab.length_squared()
		var t := 0.0
		if l2 > 0.0001:
			t = clampf(Vector3(pos.x - a.x, 0.0, pos.z - a.z).dot(ab) / l2, 0.0, 1.0)
		var q := a + (b - a) * t
		var dd := Vector2(pos.x - q.x, pos.z - q.z).length_squared()
		if dd < best_d:
			best_d = dd
			best_i = i
			best_s = route_cum[i] + (route_cum[i + 1] - route_cum[i]) * t
	route_i = best_i
	route_s = maxf(best_s, route_s - 2.0)
	return best_d < 16.0 * 16.0


func _route_point_at(s: float) -> Vector3:
	var n := route.size()
	if s >= route_cum[n - 1]:
		return route[n - 1]
	var i := route_i
	while i < n - 2 and route_cum[i + 1] < s:
		i += 1
	var seg := route_cum[i + 1] - route_cum[i]
	var t := 0.0 if seg < 0.0001 else clampf((s - route_cum[i]) / seg, 0.0, 1.0)
	return route[i].lerp(route[i + 1], t)


## Planar distance of `m` from the segment a-b.
static func _seg_dev(a: Vector3, b: Vector3, m: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var am := Vector2(m.x - a.x, m.z - a.z)
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return am.length()
	var t := clampf(am.dot(ab) / l2, 0.0, 1.0)
	return (am - ab * t).length()


func _route_vmax_ahead() -> float:
	var v := INF
	var n := route.size()
	var i := route_i
	while i < n and route_cum[i] < route_s + 25.0:
		v = minf(v, route_vmax[i])
		i += 1
	if v == INF:
		v = 13.0
	if urgent:
		return minf(v * URGENT_SPEED_MULT, MAX_URGENT_SPEED)
	return v * CALM_SPEED_MULT


func _curve_speed(spd: float) -> float:
	var a_lat := (A_LAT_FAST if urgent else A_LAT_CALM) * _weather_grip()
	var b := B_FAST if urgent else B_CALM
	var step := 5.0
	var horizon := clampf(spd * spd / (2.0 * b) + 14.0, 20.0, 60.0)
	var n := int(horizon / step)
	var best := INF
	var prev := _route_point_at(route_s)
	var cur := _route_point_at(route_s + step)
	for k in range(1, n):
		var nxt := _route_point_at(route_s + step * float(k + 1))
		var a := Vector2(cur.x - prev.x, cur.z - prev.z)
		var c := Vector2(nxt.x - cur.x, nxt.z - cur.z)
		var la := a.length()
		var lc := c.length()
		if la > 0.05 and lc > 0.05:
			var ang := absf(a.angle_to(c))
			if ang > 0.03:
				var kappa := ang / (0.5 * (la + lc))
				var vc := sqrt(a_lat / kappa)
				var dd := maxf(step * float(k) - 3.0, 0.0)
				best = minf(best, sqrt(vc * vc + 2.0 * b * dd))
		prev = cur
		cur = nxt
	return maxf(best, 3.5)


## Calm: stop at red / yellow. Urgent: through red junctions at a careful speed (~8 m/s at the line).
func _signal_speed() -> float:
	var roads: Object = _roads()
	if roads == null:
		return INF
	for k in route_stop_s.size():
		var ds := route_stop_s[k] - route_s
		if ds < -1.0:
			continue
		if ds > 55.0:
			break
		var st := int(roads.call("get_signal_state", route_stop_lane[k]))
		if st == 0:
			return INF
		if not urgent:
			var spd := absf(_fwd_speed())
			if st == 1 and spd * spd / (2.0 * 4.5) > maxf(ds, 0.0) + 1.0:
				return INF        # too late to stop on yellow
			return sqrt(2.0 * B_CALM * maxf(ds - 1.2, 0.0))
		if st == 2:
			return sqrt(64.0 + 2.0 * B_FAST * maxf(ds, 0.0))
		return INF
	return INF


# =================================================================================================
# route planning (RoadGraph)
# =================================================================================================

func _roads() -> Object:
	var w := Game.world
	if w == null or not is_instance_valid(w):
		return null
	var r: Variant = w.get("roads")
	return r as Object if r is Object else null


## [lane_id, offset] of the lane under the car whose travel direction matches its heading.
func _start_lane() -> Array:
	var roads := _roads()
	if roads == null:
		return []
	var pos := vehicle.global_position
	var near: Dictionary = roads.call("get_nearest_lane", pos, 40.0)
	if near.is_empty():
		return []
	var id := int(near["lane_id"])
	var off := float(near["offset"])
	var fwd := -vehicle.global_basis.z
	fwd.y = 0.0
	var lxf: Transform3D = roads.call("sample_lane", id, off)
	if (-lxf.basis.z).dot(fwd) >= -0.2:
		return [id, off]
	var lanes: Array = roads.get("lanes")
	var segs: Array = roads.get("segments")
	var lane: Dictionary = lanes[id]
	var seg: Dictionary = segs[int(lane["segment_id"])]
	var others: PackedInt32Array = seg["lanes_back"] if int(lane["direction"]) == 1 else seg["lanes_fwd"]
	var best := -1
	var best_d := INF
	var best_off := 0.0
	for o in others:
		var r := _project_on_lane(lanes[o], pos)
		if r.y < best_d:
			best_d = r.y
			best = o
			best_off = r.x
	if best >= 0:
		return [best, best_off]
	return [id, off]


## Start options: the lane under the car + the other lanes of the same direction (lane change) +
## the nearest lane of the other direction (three-point turn), with their extra costs.
func _start_options() -> Array:
	var st := _start_lane()
	if st.is_empty():
		return []
	var out: Array = [[st[0], st[1], 0.0]]
	var roads := _roads()
	var lanes: Array = roads.get("lanes")
	var segs: Array = roads.get("segments")
	var lane: Dictionary = lanes[int(st[0])]
	var seg: Dictionary = segs[int(lane["segment_id"])]
	var same: PackedInt32Array = seg["lanes_fwd"] if int(lane["direction"]) == 1 else seg["lanes_back"]
	for o in same:
		if o == int(st[0]):
			continue
		var r := _project_on_lane(lanes[o], vehicle.global_position)
		if r.y < 8.0:
			out.append([o, r.x + 6.0, LANE_CHANGE_COST])
	var back: PackedInt32Array = seg["lanes_back"] if int(lane["direction"]) == 1 else seg["lanes_fwd"]
	var best_b := -1
	var best_bd := INF
	var best_bo := 0.0
	for o in back:
		var r2 := _project_on_lane(lanes[o], vehicle.global_position)
		if r2.y < best_bd:
			best_bd = r2.y
			best_b = o
			best_bo = r2.x
	if best_b >= 0 and best_bd < 12.0:
		out.append([best_b, best_bo + 4.0, UTURN_COST])
	return out


## Vector2(offset along the lane, horizontal distance) of `pos` projected on a lane polyline.
static func _project_on_lane(lane: Dictionary, pos: Vector3) -> Vector2:
	var pts: PackedVector3Array = lane["points"]
	var cum: PackedFloat32Array = lane["cum"]
	var best_d := INF
	var best_s := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var l2 := ab.length_squared()
		var t := 0.0
		if l2 > 0.0001:
			t = clampf(Vector2(pos.x - a.x, pos.z - a.z).dot(ab) / l2, 0.0, 1.0)
		var qx := a.x + (b.x - a.x) * t
		var qz := a.z + (b.z - a.z) * t
		var dd := Vector2(pos.x - qx, pos.z - qz).length()
		if dd < best_d:
			best_d = dd
			best_s = cum[i] + (cum[i + 1] - cum[i]) * t
	return Vector2(best_s, best_d)


## Lane route to `target` (A* over lanes). The route ends on the lane point nearest the target, on
## whichever side of that road gives the shorter route.
func _plan_to(target: Vector3) -> bool:
	var roads := _roads()
	if roads == null:
		return false
	var starts := _start_options()
	if starts.is_empty():
		return false
	var near: Dictionary = roads.call("get_nearest_lane", target, 70.0)
	if near.is_empty():
		return false
	var options: Array = [[int(near["lane_id"]), float(near["offset"])]]
	var lanes: Array = roads.get("lanes")
	var segs: Array = roads.get("segments")
	var nl: Dictionary = lanes[int(near["lane_id"])]
	var seg: Dictionary = segs[int(nl["segment_id"])]
	var others: PackedInt32Array = seg["lanes_back"] if int(nl["direction"]) == 1 else seg["lanes_fwd"]
	var best_od := INF
	var best_opt: Array = []
	for o in others:
		var pr := _project_on_lane(lanes[o], target)
		if pr.y < best_od:
			best_od = pr.y
			best_opt = [o, pr.x]
	if not best_opt.is_empty():
		options.append(best_opt)
	var best_ids := PackedInt32Array()
	var best_cost := INF
	var best_ob := 0.0
	var best_oa := 0.0
	var direct := Vector2(vehicle.global_position.x - target.x, vehicle.global_position.z - target.z).length()
	for k in starts.size():
		var a := int((starts[k] as Array)[0])
		var oa := float((starts[k] as Array)[1])
		for opt: Array in options:
			var b := int(opt[0])
			var ob := float(opt[1])
			var ids := PackedInt32Array()
			if a == b and ob >= oa + stop_short + 4.0:
				ids.append(a)
			else:
				ids = roads.call("find_lane_route", a, b)
			if ids.is_empty():
				continue
			var cost := 0.0
			for i in ids.size():
				var l: Dictionary = lanes[ids[i]]
				var s0 := oa if i == 0 else 0.0
				var s1 := ob if i == ids.size() - 1 else float(l["length"])
				cost += maxf(s1 - s0, 0.0) + 8.0
			cost += float((starts[k] as Array)[2])
			if cost < best_cost:
				best_cost = cost
				best_ids = ids
				best_ob = ob
				best_oa = oa
		if k == 0 and best_cost < direct * 1.5 + 60.0:
			break
	if best_ids.is_empty():
		return false
	stats["plans"] = int(stats["plans"]) + 1
	_build_route(best_ids, best_oa, best_ob)
	dest = target
	return route.size() >= 2


## Random lane walk of about 400 m: prefers going straight, avoids dirt and dead ends.
func _plan_wander() -> bool:
	var roads := _roads()
	if roads == null:
		return false
	var st := _start_lane()
	if st.is_empty():
		return false
	var lanes: Array = roads.get("lanes")
	var ids := PackedInt32Array([int(st[0])])
	var total := float((lanes[int(st[0])] as Dictionary)["length"]) - float(st[1])
	var cur := int(st[0])
	var guard := 0
	while total < 400.0 and guard < 24:
		guard += 1
		var nxt: PackedInt32Array = roads.call("get_next_lanes", cur)
		if nxt.is_empty():
			break
		var cur_dir := _lane_end_dir(lanes[cur])
		var best := -1
		var best_w := -1.0
		for id in nxt:
			var l: Dictionary = lanes[id]
			var turn := cur_dir.dot(_lane_start_dir(l))
			var w := 1.8 if turn > 0.85 else (0.8 if turn > -0.5 else 0.05)
			var kind := str(l.get("kind", ""))
			if kind == "dirt" or kind == "runway" or kind == "taxiway":
				w *= 0.03
			elif kind == "alley":
				w *= 0.3
			if (roads.call("get_next_lanes", id) as PackedInt32Array).size() <= 1 and float(l["length"]) < 60.0:
				w *= 0.2
			w *= _rng.randf_range(0.4, 1.0)
			if w > best_w:
				best_w = w
				best = id
		if best < 0:
			break
		ids.append(best)
		total += float((lanes[best] as Dictionary)["length"])
		cur = best
	var last_len := float((lanes[ids[ids.size() - 1]] as Dictionary)["length"])
	_build_route(ids, float(st[1]), last_len)
	dest = route[route.size() - 1] if route.size() > 0 else Vector3.INF
	return route.size() >= 2


static func _lane_end_dir(l: Dictionary) -> Vector2:
	var p: PackedVector3Array = l["points"]
	var n := p.size()
	var d := Vector2(p[n - 1].x - p[n - 2].x, p[n - 1].z - p[n - 2].z)
	return d.normalized() if d.length_squared() > 0.0001 else Vector2.UP


static func _lane_start_dir(l: Dictionary) -> Vector2:
	var p: PackedVector3Array = l["points"]
	var d := Vector2(p[1].x - p[0].x, p[1].z - p[0].z)
	return d.normalized() if d.length_squared() > 0.0001 else Vector2.UP


func _build_route(ids: PackedInt32Array, s_first: float, s_last: float) -> void:
	var roads := _roads()
	route.clear()
	route_vmax.clear()
	route_stop_s.clear()
	route_stop_lane.clear()
	route_cum.clear()
	route_i = 0
	route_s = 0.0
	var lanes: Array = roads.get("lanes")
	var acc := 0.0
	for i in ids.size():
		var id := ids[i]
		var lane: Dictionary = lanes[id]
		var vlim := float(lane.get("speed_limit", 14.0))
		if i > 0:
			var conn: PackedVector3Array = roads.call("get_connection", ids[i - 1], id)
			for p in conn:
				acc = _route_add(p, minf(vlim, 10.0), acc)
		var length := float(lane["length"])
		var s0 := clampf(s_first, 0.0, length) if i == 0 else 0.0
		var s1 := clampf(s_last, 0.0, length) if i == ids.size() - 1 else length
		if s1 < s0:
			s1 = s0
		var pts: PackedVector3Array = lane["points"]
		var cum: PackedFloat32Array = lane["cum"]
		acc = _route_add(_lane_point(pts, cum, s0), vlim, acc)
		for k in pts.size():
			if cum[k] > s0 + 0.2 and cum[k] < s1 - 0.2:
				acc = _route_add(pts[k], vlim, acc)
		acc = _route_add(_lane_point(pts, cum, s1), vlim, acc)
		if i < ids.size() - 1 and s1 >= length - 0.5:
			route_stop_s.append(acc)
			route_stop_lane.append(id)


func _route_add(p: Vector3, vmax: float, acc: float) -> float:
	var n := route.size()
	if n > 0:
		var d := route[n - 1].distance_to(p)
		if d < 0.3:
			route_vmax[n - 1] = minf(route_vmax[n - 1], vmax)
			return acc
		acc += d
	route.append(p)
	route_vmax.append(vmax)
	route_cum.append(acc)
	return acc


static func _lane_point(pts: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Vector3:
	var n := pts.size()
	if s <= 0.0:
		return pts[0]
	for i in n - 1:
		if cum[i + 1] >= s:
			var seg := cum[i + 1] - cum[i]
			var t := 0.0 if seg < 0.0001 else (s - cum[i]) / seg
			return pts[i].lerp(pts[i + 1], t)
	return pts[n - 1]


## Route length of a plan from the car to `target` without committing to it (spawn checks).
func route_length() -> float:
	return _route_len()


# =================================================================================================
# steering, pedals, obstacles, recovery
# =================================================================================================

func _pursuit_steer(xf: Transform3D, tgt: Vector3, spd: float) -> float:
	var lp := xf.affine_inverse() * tgt
	# reference point: rear axle for short vehicles; a quarter wheelbase ahead of the centre for long
	# ones (as the traffic module does), so the nose does not swing wide into the opposite lane
	var fwd := -lp.z + (wheelbase * 0.5 if half_len <= 2.9 else -wheelbase * 0.25)
	var side := lp.x
	var delta := 0.0
	if fwd < 0.5:
		delta = (1.0 if side >= 0.0 else -1.0) * max_steer
	else:
		delta = atan(2.0 * wheelbase * side / maxf(fwd * fwd + side * side, 0.01))
	var limit := max_steer
	var sp := absf(spd)
	if sp > 4.0:
		limit = minf(max_steer, atan(wheelbase * grip * _weather_grip() * 9.81 / (sp * sp)) + deg_to_rad(4.0))
	return clampf(delta / maxf(limit, 0.05), -1.0, 1.0)


func _pedals(vt: float, spd: float) -> void:
	var err := vt - spd
	if _emergency_stop:
		throttle = 0.0
		brake = 1.0
		return
	if vt < 0.3:
		throttle = 0.0
		brake = 1.0 if spd < 2.5 else clampf(0.35 + 0.1 * spd, 0.35, 1.0)
	elif err > 0.4:
		throttle = clampf(0.35 + 0.2 * err, 0.3, 1.0 if urgent else 0.7)
		brake = 0.0
	elif err < -1.0:
		throttle = 0.0
		brake = clampf((0.15 + 0.16 * (-err)) if urgent else (0.08 + 0.11 * (-err)), 0.0, 1.0)
	else:
		throttle = clampf(0.15 + 0.012 * vt + 0.15 * err, 0.0, 0.7)
		brake = 0.0


## One ray towards the aim point (+ side rays when blocked) and the swept person box. Returns the
## allowed speed and may set a swerve offset (_avoid).
func _obstacles(xf: Transform3D, spd: float, vt: float, aim: Vector3) -> float:
	last_block = ""
	_emergency_stop = false
	if not vehicle.is_inside_tree() or spd < -0.5:
		return vt
	var space := vehicle.get_world_3d().direct_space_state
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var from := xf.origin + fwd * (half_len - 0.2) + Vector3.UP * 0.8
	var dir := fwd
	var aim_s := aim + right * _avoid
	var to_aim := Vector3(aim_s.x - from.x, 0.0, aim_s.z - from.z)
	if to_aim.length() > 2.0 and to_aim.normalized().dot(fwd) > 0.2:
		dir = to_aim.normalized()
	var length := clampf(4.0 + absf(spd) * 1.25, 6.0, 34.0)
	var pl := _person_speed(space, xf, spd, dir)
	if pl < 0.5 and absf(spd) < 1.0:
		# somebody stands right in front of the bumper and does not move: wait, then back up a
		# little and steer round him (never push through)
		if _person_wait_since < 0.0:
			_person_wait_since = _clock
			stats["person_stops"] = int(stats["person_stops"]) + 1
		elif _clock - _person_wait_since > 2.5:
			_person_wait_since = -1.0
			_avoid_t = 0.0
			_pick_swerve(space, from, fwd, right, length)
			_avoid *= 1.3
			_avoid_t = 3.2
			if not _rear_blocked(xf):
				_reverse_t = 0.9
				_reverse_steer = 0.0
	else:
		_person_wait_since = -1.0
	vt = minf(vt, pl)
	_ray.from = from
	_ray.to = from + dir * length
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		return vt
	var col: Object = hit.get("collider")
	var hd := from.distance_to(hit["position"])
	var nrm: Vector3 = hit.get("normal", Vector3.UP)
	if absf(nrm.y) > 0.8:
		return vt                 # ground / ramp
	if col is Node and ((col as Node).is_in_group("npc") or (col as Node).is_in_group("player")):
		last_block = "person %.1f" % hd
		return minf(vt, sqrt(2.0 * 6.5 * maxf(hd - 3.5, 0.0)))
	if col is RigidBody3D and (col as Node).is_in_group("vehicle"):
		var ov := (col as RigidBody3D).linear_velocity
		var along := ov.dot(fwd)
		last_block = "vehicle %.1f v=%.1f" % [hd, along]
		if along > 2.5:
			var follow := along + maxf(hd - 7.0, 0.0) * 0.6
			if urgent and follow < vt - 3.0:
				_pick_swerve(space, from, fwd, right, length)
			return minf(vt, maxf(follow, vt * 0.7 if _avoid != 0.0 else follow))
		if hd > _left - 3.0:
			# the stopped vehicle stands at / beyond our stopping point (the wreck we came for, a car
			# at the scene): no swerve, just stop in time behind it
			return minf(vt, sqrt(2.0 * B_FAST * maxf(hd - 4.0, 0.0)))
		_pick_swerve(space, from, fwd, right, length)
		if hd < 7.0:
			return minf(vt, 2.5)
		return minf(vt, maxf(hd * 0.6, 5.0))
	if hd > clampf(absf(spd) * 0.9, 6.0, 15.0):
		return vt
	last_block = "static %.1f" % hd
	_pick_swerve(space, from, fwd, right, length)
	if hd < 5.0:
		return minf(vt, 2.5)
	return minf(vt, maxf(hd * 0.8, 5.0))


## Speed limit for the people (NPCs, the player on foot) in the box the vehicle sweeps over its
## stopping distance (vehicle width + margin). INF when clear. Dead bodies are ragdolls on their
## own layer: the route stops short of them instead.
func _person_speed(space: PhysicsDirectSpaceState3D, xf: Transform3D, spd: float, dir: Vector3) -> float:
	if spd < -0.5:
		return INF
	var length := clampf(3.0 + spd * spd / 10.0 + spd * 0.35, 4.0, 34.0)
	if _person_q == null:
		_person_q = PhysicsShapeQueryParameters3D.new()
		_person_q.collision_mask = Layers.NPC | Layers.PLAYER
		_person_q.collide_with_areas = false
		_person_q.shape = _person_box
	_person_box.size = Vector3(PERSON_BOX_WIDTH, 1.6, length)
	var front := xf.origin + dir * half_len
	_person_q.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), front + dir * (length * 0.5) + Vector3.UP * 1.0)
	var hits := space.intersect_shape(_person_q, 6)
	var best := INF
	for h: Dictionary in hits:
		var c: Variant = h.get("collider")
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		if crew.has(c):
			continue
		var along := ((c as Node3D).global_position - front).dot(dir)
		var lim := sqrt(2.0 * 6.0 * maxf(along - 3.5, 0.0))
		if lim < best:
			best = lim
			last_block = "person-box %.1f" % along
	if spd > best + 0.5:
		_emergency_stop = true
	return best


func _kturn(xf: Transform3D, aim: Vector3, spd: float, dt: float) -> bool:
	var lp := xf.affine_inverse() * aim
	var ang := atan2(lp.x, -lp.z)
	if _kturn_t > 0.0:
		_kturn_t -= dt
		if absf(ang) < 1.25 or spd < -7.0 or _rear_blocked(xf):
			_kturn_t = 0.0
			return false
		_apply(-0.8, -_kturn_dir, 0.0, false)
		return true
	if absf(ang) < KTURN_ANGLE or absf(spd) > 4.5 or Vector2(lp.x, lp.z).length() > 70.0:
		return false
	if _rear_blocked(xf):
		return false
	_kturn_dir = 1.0 if lp.x >= 0.0 else -1.0
	_kturn_t = 2.2
	stats["kturns"] = int(stats["kturns"]) + 1
	_apply(-0.8, -_kturn_dir, 0.0, false)
	return true


func _rear_blocked(xf: Transform3D) -> bool:
	if not vehicle.is_inside_tree():
		return false
	var back := xf.basis.z
	back.y = 0.0
	back = back.normalized()
	var from := xf.origin + back * (half_len - 0.3) + Vector3.UP * 0.8
	_ray.from = from
	_ray.to = from + back * 3.5
	return not vehicle.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


func _turn_speed(xf: Transform3D, aim: Vector3) -> float:
	var lp := xf.affine_inverse() * aim
	var d := Vector2(lp.x, lp.z).length()
	if d < 0.5:
		return INF
	var ang := absf(atan2(lp.x, -lp.z))
	if ang < 0.25:
		return INF
	if ang > KTURN_ANGLE and d < 70.0:
		return 3.0
	var kappa := 2.0 * sin(minf(ang, PI * 0.5)) / d
	var a_lat := (A_LAT_FAST if urgent else A_LAT_CALM) * _weather_grip()
	return maxf(sqrt(a_lat / maxf(kappa, 0.001)), 3.5)


func _pick_swerve(space: PhysicsDirectSpaceState3D, from: Vector3, fwd: Vector3, right: Vector3, length: float) -> void:
	if _avoid_t > 0.0:
		return
	var free_l := _side_free(space, from, (fwd - right * 0.45).normalized(), length * 0.8)
	var free_r := _side_free(space, from, (fwd + right * 0.45).normalized(), length * 0.8)
	# pass on the left: traffic pulls over to the right for the siren
	_avoid = -SWERVE if free_l + 2.0 >= free_r else SWERVE
	_avoid_t = 1.4
	stats["swerves"] = int(stats["swerves"]) + 1


func _side_free(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, length: float) -> float:
	_ray.from = from
	_ray.to = from + dir * length
	var h := space.intersect_ray(_ray)
	if h.is_empty():
		return length
	return from.distance_to(h["position"])


func _stuck_check(dt: float) -> void:
	var spd := absf(_fwd_speed())
	if throttle > 0.25 and spd < 0.8 and brake < 0.1:
		_stuck_t += dt
	else:
		_stuck_t = maxf(_stuck_t - dt * 2.0, 0.0)
	if _stuck_t < STUCK_TIME:
		return
	_stuck_t = 0.0
	_reverse_t = REVERSE_TIME + _rng.randf() * 0.5
	_reverse_steer = -steer if absf(steer) > 0.2 else (1.0 if _rng.randf() < 0.5 else -1.0)
	stats["recoveries"] = int(stats["recoveries"]) + 1
	_recoveries.append(_clock)
	while not _recoveries.is_empty() and _clock - _recoveries[0] > 30.0:
		_recoveries.remove_at(0)
	if _recoveries.size() >= 4:
		_hopeless = true


func _flip_check(dt: float) -> bool:
	if vehicle.global_basis.y.y < 0.35:
		_flip_t += dt
		_hold_brake()
		if _flip_t > 6.0:
			_hopeless = true
		return true
	_flip_t = 0.0
	return false


func _hold_brake() -> void:
	_apply(0.0, 0.0, 1.0, absf(_fwd_speed()) < 3.0)


func _apply(t: float, s: float, b: float, hb: bool) -> void:
	throttle = t
	steer = s
	brake = b
	if vehicle.has_method("set_inputs"):
		vehicle.call("set_inputs", t, s, b, hb)


func _set_siren(on: bool) -> void:
	if vehicle != null and is_instance_valid(vehicle) and vehicle.has_method("set_siren") and bool(vehicle.get("siren_on")) != on:
		vehicle.call("set_siren", on)


func set_siren(on: bool) -> void:
	_set_siren(on)


func _fwd_speed() -> float:
	if vehicle.has_method("get_forward_speed"):
		return float(vehicle.call("get_forward_speed"))
	return vehicle.linear_velocity.dot(-vehicle.global_basis.z)


func get_speed() -> float:
	return _fwd_speed() if is_valid() else 0.0


func _weather_grip() -> float:
	if Weather.has_method("get_grip_multiplier"):
		return clampf(float(Weather.get_grip_multiplier()), 0.5, 1.2)
	return 1.0


func get_debug_info() -> Dictionary:
	return {"mode": get_mode_name(), "urgent": urgent, "speed": get_speed(), "route_pts": route.size(),
			"route_s": route_s, "remaining": remaining(), "block": last_block, "thr": throttle, "brk": brake,
			"arrived": arrived, "drive_time": drive_time, "hopeless": _hopeless, "stats": stats}
