class_name VehicleAI
extends Node
## AI driver for wheeled vehicles. Modes: "traffic" (lane graph, signals, following), "route" (taxi/emergency
## to a destination), "pursuit" (police chase with ramming / PIT / boxing-in), "flee", "park", "leave".

var veh: Car
var mode := "traffic"
var a := Vector2i.ZERO
var b := Vector2i.ZERO
var lane := 0
var path := PackedVector3Array()
var pi := 0
var seg_kind := "lane"
var cruise := 11.0
var target: Node3D = null
var dest := Vector3.ZERO
var route: Array = []
var stuck_t := 0.0
var reverse_t := 0.0
var wait_t := 0.0
var think := 0.0
var ignore_signals := false
var arrived := false
var honk_cd := 0.0
var obstacle_d := 99.0
var obstacle_speed := 0.0
var want_speed := 0.0
var exit_cd := 0.0
var manager: Node = null
var park_xf = null
var officers_out := false
var search_point := Vector3.ZERO
var yielding := 0.0
var on_arrive: Callable
var pit_cd := 0.0
var final_stop := Vector3.INF


func attach(v: Car) -> void:
	veh = v
	v.ai = self
	v.add_child(self)
	v.engine_on = true
	v.handbrake = false
	v.brake = 0.0
	cruise = WorldLayout.seg_speed(a, b) * randf_range(0.85, 1.05) if a != b else 11.0


func place_on_lane(from: Vector2i, to: Vector2i, ln: int, t: float) -> Transform3D:
	a = from
	b = to
	lane = ln
	var ends := WorldLayout.lane_ends(a, b, lane)
	var p: Vector3 = (ends[0] as Vector3).lerp(ends[1], t)
	var d: Vector3 = ((ends[1] as Vector3) - (ends[0] as Vector3)).normalized()
	path = PackedVector3Array([ends[0], ends[1]])
	pi = 1
	seg_kind = "lane"
	return Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), p + Vector3(0, 0.25, 0))


func _next_segment() -> void:
	## We reached the stop line before intersection b: pick where to go and build the turn + next lane.
	var nb := WorldLayout.neighbors(b)
	var options: Array = []
	for n in nb:
		if n != a:
			options.append(n)
	if options.is_empty():
		options = [a]
	var nxt: Vector2i = options[randi() % options.size()]
	if not route.is_empty():
		nxt = route.pop_front()
		if not (nxt in nb):
			nxt = options[0]
	else:
		var straight := b + (b - a)
		if straight in options and randf() < 0.55:
			nxt = straight
	var ln2 := mini(lane, WorldLayout.seg_lanes(b, nxt) - 1)
	if WorldLayout.seg_lanes(b, nxt) > 1 and randf() < 0.3:
		ln2 = randi() % 2
	var cur_end := path[path.size() - 1]
	var ends := WorldLayout.lane_ends(b, nxt, ln2)
	var d0 := (WorldLayout.inter_pos(b) - WorldLayout.inter_pos(a)).normalized()
	var d1 := (WorldLayout.inter_pos(nxt) - WorldLayout.inter_pos(b)).normalized()
	var p0 := cur_end
	var p3: Vector3 = ends[0]
	var np := PackedVector3Array()
	if d0.dot(d1) > 0.9:
		np.append(p0)
		np.append(p3)
	else:
		# quadratic bezier through the corner
		var c := Vector3(p0.x if absf(d0.x) < 0.5 else p3.x, 0, p0.z if absf(d0.z) < 0.5 else p3.z)
		for k in 7:
			var t := k / 6.0
			np.append(p0.lerp(c, t).lerp(c.lerp(p3, t), t))
	np.append(ends[1])
	path = np
	pi = 1
	a = b
	b = nxt
	lane = ln2
	cruise = WorldLayout.seg_speed(a, b) * randf_range(0.85, 1.05)


func set_route_to(p: Vector3) -> void:
	## Breadth-first route over the road grid that ends on the road segment passing closest to p;
	## the vehicle stops at the point of that segment nearest to p (final_stop).
	dest = p
	route = []
	arrived = false
	var best_d := 1e9
	var su := a
	var sv := b
	var cp := p
	for i in WorldLayout.NX:
		for j in WorldLayout.NZ:
			var u := Vector2i(i, j)
			var upos := WorldLayout.inter_pos(u)
			for v in WorldLayout.neighbors(u):
				var vpos := WorldLayout.inter_pos(v)
				var t := clampf((p - upos).dot(vpos - upos) / maxf((vpos - upos).length_squared(), 0.01), 0.15, 0.85)
				var q := upos.lerp(vpos, t)
				var d := G.dist2(q, p)
				if d < best_d:
					best_d = d
					su = u
					sv = v
					cp = q
	final_stop = cp
	# already driving along that segment and the stop point is still ahead
	if (su == a and sv == b) or (su == b and sv == a):
		var dir := (WorldLayout.inter_pos(b) - WorldLayout.inter_pos(a)).normalized()
		if (cp - veh.global_position).dot(dir) > 4.0:
			return
	var start := b
	var prev := {start: start}
	var q2: Array = [start]
	while not q2.is_empty():
		var cur: Vector2i = q2.pop_front()
		for n in WorldLayout.neighbors(cur):
			if not prev.has(n) and not (cur == start and n == a and WorldLayout.neighbors(start).size() > 1):
				prev[n] = cur
				q2.append(n)
	var entry := su
	var exit := sv
	if _hops(prev, sv, start) < _hops(prev, su, start):
		entry = sv
		exit = su
	if not prev.has(entry):
		final_stop = Vector3.INF
		return
	var c2: Vector2i = entry
	while c2 != start:
		route.push_front(c2)
		c2 = prev[c2]
	route.append(exit)


func _hops(prev: Dictionary, n: Vector2i, start: Vector2i) -> int:
	if not prev.has(n):
		return 999
	var k := 0
	var c: Vector2i = n
	while c != start and k < 99:
		c = prev[c]
		k += 1
	return k


func snap_to_road() -> void:
	## Re-acquire the lane graph from the current position (after pursuit / being moved).
	var p := veh.global_position
	var best_a := Vector2i.ZERO
	var best_b := Vector2i.ZERO
	var bd := 1e9
	var fwd := -veh.global_transform.basis.z
	for i in WorldLayout.NX:
		for j in WorldLayout.NZ:
			var ia := Vector2i(i, j)
			for ib in WorldLayout.neighbors(ia):
				var ends := WorldLayout.lane_ends(ia, ib, 0)
				var s: Vector3 = ends[0]
				var e: Vector3 = ends[1]
				var se := e - s
				var t := clampf((p - s).dot(se) / se.length_squared(), 0.0, 1.0)
				var d := p.distance_to(s + se * t) + (0.0 if se.normalized().dot(fwd) > 0.0 else 9.0)
				if d < bd:
					bd = d
					best_a = ia
					best_b = ib
	a = best_a
	b = best_b
	lane = 0
	var ends2 := WorldLayout.lane_ends(a, b, 0)
	path = PackedVector3Array([veh.global_position, ends2[1]])
	pi = 1


func on_rammed(by: Vehicle, dv: float) -> void:
	if mode in ["pursuit", "park"] or veh.is_emergency:
		return
	if dv > 5.0 and mode == "traffic":
		if randf() < 0.55:
			mode = "flee"
			ignore_signals = true
			cruise = 21.0
		elif randf() < 0.5 and veh.driver != null and veh.driver.has_method("flee_vehicle") and veh.speed < 6.0:
			veh.brake = 1.0
			veh.throttle = 0.0
			var drv := veh.driver
			drv.flee_vehicle(veh)
			if drv.brave > 0.6 and by.driver != null:
				drv.engage(by.driver)
			mode = "park"
	elif honk_cd <= 0.0:
		honk_cd = 3.0
		veh.honk()


func on_driver_attacked(_who: Node) -> void:
	if mode == "traffic" or mode == "route":
		mode = "flee"
		ignore_signals = true
		cruise = 22.0


func is_taxi_for_hire() -> bool:
	return veh.vid == "taxi" and mode in ["traffic", "park", "route"] and veh.driver != null and veh.seats.size() > 2 and veh.seats[2].occ == null


func _physics_process(delta: float) -> void:
	if veh == null or veh.dead or (veh.driver == null and not officers_out):
		if veh != null:
			veh.throttle = 0.0
			veh.brake = 1.0
		return
	honk_cd -= delta
	exit_cd -= delta
	pit_cd -= delta
	match mode:
		"traffic", "route", "flee", "leave":
			_drive_path(delta)
		"pursuit":
			_pursuit(delta)
		"park":
			veh.throttle = 0.0
			veh.steer = 0.0
			veh.brake = 1.0
			veh.handbrake = true


func _sense_ahead(dist: float) -> void:
	obstacle_d = 99.0
	obstacle_speed = 0.0
	var t := veh.global_transform
	var fwd := -t.basis.z
	var steer_dir := fwd.rotated(Vector3.UP, veh.steer_angle * 0.8)
	for off in [-0.55, 0.55]:
		var from: Vector3 = t * Vector3(off * veh.half.x, 0.55, -veh.half.z - 0.1)
		var h := G.ray(from, from + steer_dir * dist, G.L_VEHICLE | G.L_CHAR | G.L_WORLD, [veh.get_rid()])
		if not h.is_empty():
			if h.collider is StaticBody3D and h.normal.y > 0.5:
				continue
			var d := from.distance_to(h.position)
			if d < obstacle_d:
				obstacle_d = d
				obstacle_speed = 0.0
				if h.collider is Vehicle:
					obstacle_speed = maxf((h.collider as Vehicle).linear_velocity.dot(fwd), 0.0)


func _apply_speed(target_speed: float, delta: float) -> void:
	want_speed = target_speed
	var v := veh.fwd_speed
	veh.handbrake = false
	if target_speed <= 0.05:
		veh.throttle = 0.0
		veh.brake = 1.0 if absf(v) > 0.3 else 0.6
		return
	var err := target_speed - v
	if err > 0.4:
		veh.throttle = clampf(err * 0.5, 0.25, 1.0)
		veh.brake = 0.0
	elif err < -1.2:
		veh.throttle = 0.0
		veh.brake = clampf(-err * 0.25, 0.1, 1.0)
	else:
		veh.throttle = 0.12
		veh.brake = 0.0
	if delta < 0.0:
		pass


func _steer_to(p: Vector3, gain: float = 1.6) -> float:
	var lp := veh.to_local(p)
	var ang := atan2(lp.x, -lp.z)
	veh.steer = clampf(ang * gain, -1.0, 1.0)
	return ang


func _drive_path(delta: float) -> void:
	if reverse_t > 0.0:
		reverse_t -= delta
		veh.throttle = -0.7
		veh.brake = 0.0
		veh.steer = 0.4
		return
	var pos := veh.global_position
	var v := maxf(veh.fwd_speed, 0.0)
	if path.size() < 2:
		snap_to_road()
	# advance along the path
	while pi < path.size() - 1 and G.dist2(pos, path[pi]) < 3.0 + v * 0.35:
		pi += 1
	var tgt := path[pi]
	var last := pi >= path.size() - 1
	var dist_end := G.dist2(pos, path[path.size() - 1])
	var limit := cruise
	var turning := path.size() > 3 and pi < path.size() - 1
	if turning:
		limit = minf(limit, 6.5 if mode != "flee" else 10.0)
	# stop line logic
	var stop := false
	if last and not ignore_signals and mode != "leave":
		var along_x := a.y == b.y
		if WorldLayout.signalized(b):
			var t: float = manager.sig_time if manager else 0.0
			var sg := WorldLayout.signal_state(b, along_x, t)
			if sg == 2 or (sg == 1 and dist_end > 9.0):
				stop = true
		elif WorldLayout.neighbors(b).size() >= 3:
			if dist_end < 14.0:
				limit = minf(limit, 4.5)
			if dist_end < 5.0 and wait_t < 4.0 and manager != null and manager.intersection_busy(b, veh):
				stop = true
	if last and dist_end < 2.8 + v * 0.3:
		if stop:
			_apply_speed(0.0, delta)
			wait_t += delta
			veh.steer = move_toward(veh.steer, 0.0, delta * 2.0)
			return
		if mode == "route" and route.is_empty():
			_arrive()
			return
		wait_t = 0.0
		_next_segment()
		tgt = path[pi]
	if stop:
		limit = minf(limit, maxf((dist_end - 2.5) * 0.9, 0.0))
	if mode == "route" and route.is_empty():
		var near_stop := final_stop.x < 1e8 and G.dist2(pos, final_stop) < 9.0
		var near_dest := G.dist2(pos, dest) < (14.0 if final_stop.x < 1e8 else 22.0)
		# something (e.g. the burning wreck we were sent to) blocks the lane right at the scene
		var blocked := G.dist2(pos, dest) < 30.0 and veh.speed < 1.0 and obstacle_d < 7.0
		if near_stop or near_dest or blocked:
			_arrive()
			return
	# yield to sirens
	if yielding > 0.0:
		yielding -= delta
		limit = minf(limit, 2.5)
		tgt += veh.global_transform.basis.x * 2.0
	_steer_to(tgt, 1.7)
	_sense_ahead(5.0 + v * 1.1)
	if obstacle_d < 99.0:
		var gap := obstacle_d - 2.2
		if gap < 0.6:
			limit = 0.0
		else:
			limit = minf(limit, obstacle_speed + gap * 0.9)
	_apply_speed(limit, delta)
	# stuck handling
	if veh.speed < 0.4 and limit > 1.0:
		stuck_t += delta
		if stuck_t > 4.0 and honk_cd <= 0.0 and obstacle_d < 8.0:
			honk_cd = 5.0
			veh.honk()
		if stuck_t > 7.0:
			stuck_t = 0.0
			reverse_t = 1.3
	elif veh.speed < 0.4 and limit <= 0.05 and obstacle_d < 4.0:
		stuck_t += delta * 0.4
		if stuck_t > 9.0:
			stuck_t = 0.0
			reverse_t = 1.0
	else:
		stuck_t = maxf(stuck_t - delta, 0.0)


func _arrive() -> void:
	arrived = true
	mode = "park"
	if on_arrive.is_valid():
		on_arrive.call(self)


# ------------------------------------------------------------------ police pursuit
func _pursuit(delta: float) -> void:
	think -= delta
	var tpos := search_point
	var tvel := Vector3.ZERO
	var tveh: Vehicle = null
	var chasing := false
	if target != null and is_instance_valid(target) and G.wanted != null and G.wanted.level > 0:
		if G.wanted.state == "pursuit":
			tpos = target.global_position_now() if target.has_method("global_position_now") else target.global_position
			chasing = true
			if target.get("vehicle") != null:
				tveh = target.get("vehicle")
				tvel = tveh.linear_velocity
			elif target.get("velocity") != null:
				tvel = target.get("velocity")
		else:
			tpos = search_point if search_point != Vector3.ZERO else G.wanted.last_known
	elif G.wanted == null or G.wanted.level == 0:
		mode = "leave"
		veh.set_siren(false)
		snap_to_road()
		ignore_signals = false
		cruise = 12.0
		return
	var pos := veh.global_position
	var d := G.dist2(pos, tpos)
	# line of sight reports
	if think <= 0.0:
		think = 0.3
		if target != null and is_instance_valid(target) and d < 95.0:
			var tp2: Vector3 = (target.global_position_now() if target.has_method("global_position_now") else target.global_position) + Vector3(0, 1.0, 0)
			var excl: Array = [veh.get_rid()]
			if target.get("vehicle") != null:
				excl.append((target.get("vehicle") as Vehicle).get_rid())
			if G.ray(pos + Vector3(0, 1.3, 0), tp2, G.L_WORLD | G.L_VEHICLE, excl).is_empty():
				G.wanted.spotted(veh)
	if reverse_t > 0.0:
		reverse_t -= delta
		veh.throttle = -1.0
		veh.brake = 0.0
		veh.steer = 0.7 * (1.0 if int(reverse_t * 3.0) % 2 == 0 else 1.0)
		return
	# officers dismount when the suspect is slow / on foot and close
	var slow_target := tvel.length() < 3.5
	if chasing and d < (16.0 if tveh != null else 24.0) and slow_target and veh.speed < 4.0:
		_apply_speed(0.0, delta)
		veh.steer = 0.0
		if veh.speed < 1.0 and not officers_out and exit_cd <= 0.0:
			_dismount()
		return
	if not chasing and d < 14.0:
		_apply_speed(0.0, delta)
		if veh.speed < 1.0 and not officers_out and exit_cd <= 0.0 and G.wanted.state == "search":
			search_point = G.wanted.random_search_point()
			exit_cd = 6.0
		return
	if officers_out:
		_apply_speed(0.0, delta)
		# re-mount if the suspect drives away
		if chasing and (d > 45.0 or not slow_target) and exit_cd <= 0.0:
			_remount()
		return
	# far away: follow the road grid towards the target; close: drive straight at it
	var aim := tpos + tvel * clampf(d / 30.0, 0.0, 1.0)
	var direct := d < 55.0 or not WorldLayout.on_road(pos)
	if not direct:
		if route.is_empty() or think <= 0.0 and randi() % 6 == 0:
			if path.size() < 2 or not WorldLayout.on_road(pos):
				snap_to_road()
			set_route_to(tpos)
		var keep_mode := mode
		cruise = 26.0
		ignore_signals = true
		mode = "route"
		_drive_path(delta)
		if mode == "park":
			arrived = false
		mode = keep_mode
		return
	var ang := _steer_to(aim, 2.0)
	var sp := 30.0
	if absf(ang) > 0.6:
		sp = 10.0
	# tactics: PIT when alongside the rear quarter, box in at low speeds
	if tveh != null and chasing:
		var rel := veh.to_local(tveh.global_position)
		if absf(rel.x) < 3.6 and absf(rel.z) < 4.5 and veh.speed > 9.0 and pit_cd <= 0.0 and G.wanted.level >= 2:
			veh.steer = clampf(signf(rel.x) * 1.0, -1.0, 1.0)
			pit_cd = 2.5
		if tveh.speed < 6.0 and d < 12.0:
			sp = 5.0
	_sense_ahead(4.0 + veh.speed * 0.5)
	if obstacle_d < 4.5 and veh.speed < 1.5:
		stuck_t += delta
		if stuck_t > 0.8:
			stuck_t = 0.0
			reverse_t = 1.1
	elif obstacle_d < 12.0 and veh.speed > 12.0 and not (tveh != null and d < 14.0):
		sp = minf(sp, 9.0)
		veh.steer = clampf(veh.steer + 0.6 * (1.0 if int(Time.get_ticks_msec() / 800.0) % 2 == 0 else -1.0), -1.0, 1.0)
	else:
		stuck_t = maxf(stuck_t - delta, 0.0)
	if veh.speed < 0.5:
		stuck_t += delta
		if stuck_t > 2.0:
			stuck_t = 0.0
			reverse_t = 1.2
	_apply_speed(sp, delta)


func _dismount() -> void:
	officers_out = true
	exit_cd = 5.0
	veh.brake = 1.0
	for i in veh.seats.size():
		var o: Node = veh.seats[i].occ
		if o != null and is_instance_valid(o) and o is NPC:
			var n := o as NPC
			veh.set_door(i, true)
			var dp := veh.door_point(i)
			n.leave_vehicle()
			n.global_position = dp + Vector3(0, 0.1, 0)
			n.home = veh.global_position
			n.set_meta("car", veh)
			n.set_meta("seat", i)
			if target != null and is_instance_valid(target):
				n.engage(target)
	# keep a phantom driver flag so the car stays "manned" for remounting
	veh.set_meta("crew_out", true)


func _remount() -> void:
	var any := false
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as NPC
		if npc != null and npc.has_meta("car") and npc.get_meta("car") == veh and not npc.dead and npc.ragdoll == null:
			if npc.global_position.distance_to(veh.global_position) < 14.0:
				var s: int = npc.get_meta("seat")
				if veh.seats[s].occ == null:
					npc.enter_vehicle(veh, s)
					veh.set_door(s, false)
					any = any or s == 0
	if any:
		officers_out = false
		exit_cd = 4.0
	else:
		exit_cd = 3.0
