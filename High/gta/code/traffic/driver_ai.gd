class_name DriverAI
extends RefCounted
## AI driver for road vehicles: lane-graph traffic, emergency/police pursuit, go-to (taxi, responders) and panic.

var mode := "traffic"       # traffic | pursue | goto | hold | flee
var seg := -1
var dir := 0
var lane := 0
var pts: PackedVector3Array = PackedVector3Array()
var pi := 0
var stop_idx := -1
var end_node := -1
var axis := "x"
var nxt: Dictionary = {}
var in_turn := false
var cruise := 10.5
var obey_signals := true
var target_pos := Vector3.ZERO
var target = null            # Player for pursuit
var on_arrive: Callable
var arrive_dist := 9.0
var stuck_t := 0.0
var stuck_total := 0.0
var reverse_t := 0.0
var want_despawn := false
var block_speed := 99.0
var _scan_t := 0.0
var _route_t := 0.0
var _honk_cd := 0.0
var yield_t := 0.0
var dismount_ready := false
var has_los := false
var _los_t := 0.0
var siren := false
var blocked_by_player_t := 0.0


func start_lane(p_seg: int, p_dir: int, p_lane: int, from_pos: Vector3) -> void:
	seg = p_seg
	dir = p_dir
	lane = p_lane
	var lp := City.lane_points(seg, dir, lane)
	var a: Vector3 = lp[0]
	var b: Vector3 = lp[1]
	var ab := b - a
	var t := clampf((from_pos - a).dot(ab) / ab.length_squared(), 0.0, 0.98)
	pts = PackedVector3Array([a + ab * t, b])
	pi = 1
	stop_idx = 1
	end_node = City.seg_end_node(seg, dir)
	axis = City.segs[seg].axis
	cruise = 15.0 if City.segs[seg].lanes == 2 else 10.5
	in_turn = false
	var opts := City.next_options(seg, dir, lane)
	nxt = opts[Game.rng.randi() % opts.size()] if not opts.is_empty() else {}
	if not opts.is_empty() and Game.rng.randf() < 0.45:
		for o in opts:
			if o.turn == 0:
				nxt = o


func _advance_lane() -> void:
	## Reached the stop line: add the connector curve then the next lane.
	if nxt.is_empty():
		want_despawn = true
		return
	var a: Vector3 = pts[pts.size() - 1]
	var lp := City.lane_points(nxt.seg, nxt.dir, nxt.lane)
	var b: Vector3 = lp[0]
	var d0 := City.seg_dir(seg, dir)
	var d1 := City.seg_dir(nxt.seg, nxt.dir)
	var np := PackedVector3Array()
	var c := a + d0 * (b - a).dot(d0)
	if absf(d0.dot(d1)) > 0.9:
		c = (a + b) * 0.5
	for i in range(1, 7):
		var t := float(i) / 6.0
		np.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	in_turn = nxt.turn != 0
	seg = nxt.seg
	dir = nxt.dir
	lane = nxt.lane
	np.append(lp[1])
	pts = np
	pi = 0
	stop_idx = np.size() - 1
	end_node = City.seg_end_node(seg, dir)
	axis = City.segs[seg].axis
	cruise = 15.0 if City.segs[seg].lanes == 2 else 10.5
	var opts := City.next_options(seg, dir, lane)
	nxt = opts[Game.rng.randi() % opts.size()] if not opts.is_empty() else {}


func update(v: Vehicle, delta: float) -> void:
	_honk_cd -= delta
	yield_t -= delta
	if reverse_t > 0.0:
		reverse_t -= delta
		v.throttle_in = -0.8
		v.steer_in = -v.steer_in if absf(v.steer_in) > 0.2 else 0.6
		v.handbrake_in = false
		return
	match mode:
		"traffic", "flee":
			_traffic(v, delta)
		"pursue":
			_pursue(v, delta)
		"goto":
			_goto(v, delta)
		_:
			v.throttle_in = 0.0
			v.steer_in = 0.0
			v.handbrake_in = true


# ------------------------------------------------------------------ shared control
func _drive(v: Vehicle, look_pt: Vector3, target_speed: float, delta: float) -> void:
	var local := v.to_local(look_pt)
	var ang := atan2(local.x, -local.z)
	v.steer_in = clampf(ang * 2.0, -1.0, 1.0)
	var sp := v.speed
	target_speed = minf(target_speed, block_speed)
	if absf(ang) > 0.5:
		target_speed = minf(target_speed, 6.5)
	var err := target_speed - sp
	if target_speed < 0.4 and sp < 1.6:
		v.throttle_in = 0.0
		v.handbrake_in = true
	else:
		v.handbrake_in = false
		v.throttle_in = clampf(err * 0.45, -1.0, 1.0)
		if v.throttle_in < 0.0 and sp < 1.6:
			v.throttle_in = 0.0
	# stuck handling
	if target_speed > 2.0 and absf(sp) < 0.5:
		stuck_t += delta
		stuck_total += delta
		if stuck_t > (2.5 if mode == "pursue" else 5.0):
			stuck_t = 0.0
			reverse_t = 1.4
	else:
		stuck_t = 0.0
		if absf(sp) > 3.0:
			stuck_total = 0.0
	if stuck_total > 14.0:
		want_despawn = true


func _scan(v: Vehicle, ignore_peds: bool = false) -> void:
	## Finds the closest blocker in the lane ahead and derives a safe speed.
	block_speed = 99.0
	var fwd := -v.global_basis.z
	var look := 7.0 + absf(v.speed) * 1.3
	var inv := v.global_transform.affine_inverse()
	var hz: float = v._half.z
	var hx: float = v._half.x
	for o in Game.vehicles:
		if o == v or not is_instance_valid(o):
			continue
		var rel: Vector3 = o.global_position - v.global_position
		if absf(rel.x) > look + 8.0 or absf(rel.z) > look + 8.0:
			continue
		var lp: Vector3 = inv * o.global_position
		var ahead := -lp.z
		if ahead > 0.0 and ahead < look + o._half.z and absf(lp.x) < hx + o._half.x * 0.8 + 0.3 and absf(lp.y) < 3.0:
			var gap: float = ahead - hz - o._half.z
			var os: float = o.linear_velocity.dot(fwd)
			block_speed = minf(block_speed, maxf(0.0, os + (gap - 2.2) * 0.9))
			if o.driver == Game.player and o.driver != null and gap < 4.0 and absf(o.speed) < 1.0:
				blocked_by_player_t += 0.15
				if blocked_by_player_t > 2.5 and _honk_cd <= 0.0:
					_honk_cd = Game.rng.randf_range(3.0, 6.0)
					v.horn()
	if ignore_peds:
		return
	var p = Game.player
	if p != null and is_instance_valid(p) and not p.in_vehicle():
		_ped_block(v, inv, p.global_position, look, hx, hz)
	for n in Game.npcs:
		if not is_instance_valid(n) or n.dead:
			continue
		var rel2: Vector3 = n.global_position - v.global_position
		if absf(rel2.x) > look + 4.0 or absf(rel2.z) > look + 4.0:
			continue
		_ped_block(v, inv, n.global_position, look, hx, hz)


func _ped_block(v: Vehicle, inv: Transform3D, pos: Vector3, look: float, hx: float, hz: float) -> void:
	var lp: Vector3 = inv * pos
	var ahead := -lp.z
	if ahead > 0.0 and ahead < look and absf(lp.x) < hx + 0.9 and absf(lp.y) < 2.5:
		var gap := ahead - hz
		block_speed = minf(block_speed, maxf(0.0, (gap - 2.0) * 1.2))
		if gap < 5.0 and _honk_cd <= 0.0 and absf(v.speed) < 2.0:
			_honk_cd = Game.rng.randf_range(4.0, 8.0)
			v.horn()


func _look_point(v: Vehicle, dist: float) -> Vector3:
	## Point 'dist' metres ahead along pts starting from pi.
	var pos := v.global_position
	var remaining := dist
	var prev := pos
	for i in range(pi, pts.size()):
		var p := pts[i]
		var d := Vector2(p.x - prev.x, p.z - prev.z).length()
		if d >= remaining:
			return prev.lerp(p, remaining / maxf(d, 0.001))
		remaining -= d
		prev = p
	return pts[pts.size() - 1]


# ------------------------------------------------------------------ traffic
func _traffic(v: Vehicle, delta: float) -> void:
	if pts.is_empty():
		v.throttle_in = 0.0
		v.handbrake_in = true
		return
	var pos := v.global_position
	while pi < pts.size() and Vector2(pts[pi].x - pos.x, pts[pi].z - pos.z).length() < (3.2 if pi < stop_idx else 2.6):
		pi += 1
	if pi >= pts.size():
		_advance_lane()
		if want_despawn:
			return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.15
		_scan(v, mode == "flee")
	var target := cruise
	if mode == "flee":
		target = 21.0
	var endp := pts[stop_idx]
	var d_stop := Vector2(endp.x - pos.x, endp.z - pos.z).length()
	if in_turn and pi < stop_idx - 0:
		# still inside the connector part (first 6 points)
		if pi < 6:
			target = minf(target, 5.5)
	if pi >= stop_idx - 0 or not in_turn or pi >= 6:
		if not nxt.is_empty() and nxt.turn != 0 and d_stop < 16.0:
			target = minf(target, 5.0 + d_stop * 0.35)
		if obey_signals and mode != "flee" and City.nodes[end_node].signal:
			var st := City.signal_state(end_node, axis, Game.world.sim_time)
			if st != 0 and d_stop < maxf(8.0, v.speed * v.speed / 7.0 + 6.0) and d_stop > 0.5:
				target = minf(target, sqrt(maxf(0.0, 2.0 * 3.5 * (d_stop - 1.2))))
				if d_stop < 2.0:
					target = 0.0
	if yield_t > 0.0:
		target = minf(target, 2.5)
	var lp := _look_point(v, 3.8 + absf(v.speed) * 0.45)
	if yield_t > 0.0:
		var fwd := -v.global_basis.z
		lp += Vector3(-fwd.z, 0, fwd.x) * 2.2
	_drive(v, lp, target, delta)


# ------------------------------------------------------------------ pursuit
func _pursue(v: Vehicle, delta: float) -> void:
	var p = target
	if p == null or not is_instance_valid(p):
		mode = "hold"
		return
	_los_t -= delta
	var tpos: Vector3 = p.global_position
	var dist := v.global_position.distance_to(tpos)
	if _los_t <= 0.0:
		_los_t = 0.3
		var ex: Array = [v, p]
		if p.in_vehicle():
			ex.append(p.vehicle)
		has_los = dist < 75.0 and Game.ray(v.global_position + Vector3.UP * 1.4, p.center(), Game.L_WORLD, ex).is_empty()
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.2
		block_speed = 99.0
	var goal: Vector3 = Wanted.last_known
	dismount_ready = false
	if has_los and Wanted.seen:
		var tv: Vector3 = p.velocity_now()
		var lead := clampf(dist / maxf(absf(v.speed) + 8.0, 8.0), 0.0, 1.2)
		var aim := tpos + tv * lead
		var tsp := tv.length()
		var want := minf(v.def.max_speed, tsp + 9.0 + dist * 0.35)
		if not p.in_vehicle():
			if dist < 17.0:
				want = 0.0
				dismount_ready = absf(v.speed) < 2.0
			else:
				want = minf(want, 6.0 + dist * 0.4)
		else:
			var pv: Vehicle = p.vehicle
			var pf := -pv.global_basis.z
			var behind := (v.global_position - tpos).dot(pf) < 0.0
			if tsp < 4.0 and dist < 9.0:
				want = 0.0                                   # box in
				dismount_ready = absf(v.speed) < 1.5 and Wanted.level <= 3
			elif behind and dist < 12.0 and tsp > 8.0:
				var side := signf((v.global_position - tpos).dot(pv.global_basis.x))
				aim = tpos + pv.global_basis.x * side * 1.3 + pf * 1.2   # PIT: clip the rear quarter
				want = tsp + 7.0
			elif dist < 7.0:
				want = tsp + 5.0                             # ram
		_drive(v, aim, want, delta)
		return
	# no line of sight: follow the road network to the last known position
	_route_t -= delta
	if _route_t <= 0.0 or pts.is_empty():
		_route_t = 2.5
		_build_route(v, goal)
	if v.global_position.distance_to(goal) < 18.0:
		_drive(v, goal, 0.0, delta)
		dismount_ready = absf(v.speed) < 2.0
		return
	_follow_route(v, 17.0 + Wanted.level * 1.5, delta)


func _build_route(v: Vehicle, goal: Vector3) -> void:
	var r := City.route(v.global_position, goal)
	var out := PackedVector3Array()
	var prev := v.global_position
	for i in range(r.size()):
		var n := r[i]
		if i == 0 and r.size() > 1 and (n - prev).dot(r[1] - n) < 0.0:
			continue
		var d := (n - prev)
		d.y = 0.0
		if d.length() > 1.0:
			d = d.normalized()
			out.append(n + Vector3(-d.z, 0, d.x) * 2.3)
		prev = n
	out.append(goal)
	pts = out
	pi = 0


func _follow_route(v: Vehicle, speed: float, delta: float) -> void:
	var pos := v.global_position
	while pi < pts.size() - 1 and Vector2(pts[pi].x - pos.x, pts[pi].z - pos.z).length() < 9.0:
		pi += 1
	var tp := pts[mini(pi, pts.size() - 1)]
	var d := Vector2(tp.x - pos.x, tp.z - pos.z).length()
	var sp := speed
	if d < 22.0 and pi < pts.size() - 1:
		sp = minf(sp, 8.0 + d * 0.35)
	_drive(v, tp, sp, delta)


func _goto(v: Vehicle, delta: float) -> void:
	_route_t -= delta
	if _route_t <= 0.0 or pts.is_empty():
		_route_t = 4.0
		_build_route(v, target_pos)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.2
		_scan(v)
	var dist := v.global_position.distance_to(target_pos)
	if dist < arrive_dist:
		_drive(v, target_pos, 0.0, delta)
		if absf(v.speed) < 1.0:
			mode = "hold"
			if on_arrive.is_valid():
				on_arrive.call()
		return
	_follow_route(v, cruise, delta)
