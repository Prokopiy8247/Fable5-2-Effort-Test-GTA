class_name AIDriver
extends RefCounted
# Lane-graph traffic driver + goto / pursuit / helicopter controllers.

var mode := "traffic"       # traffic, goto, direct, pursuit, wait, heli
var a := 0
var b := 1
var nxt := -1
var lane := 0
var route: Array = []
var target_pos := Vector3.ZERO
var stuck_t := 0.0
var reverse_t := 0.0
var panic := 0.0
var emergency := false
var on_arrive: Callable
var arrived := false
var want_despawn := false
var repath_t := 0.0
var wait_t := 0.0
var honk_t := 0.0
var frame := 0
var heli_alt := 38.0
var heli_fire_t := 0.0


func place_on(v, na: int, nb: int, t: float) -> void:
	a = na
	b = nb
	nxt = -1
	var g = G.roads
	lane = (randi() % 2) if g.is_arterial(a, b) else 0
	var p: Vector3 = g.lane_point(a, b, t, lane)
	var d: Vector3 = g.edge_dir(a, b)
	v.global_transform = Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), p + Vector3.UP * 0.25)


func set_route_to(v, pos: Vector3) -> void:
	var g = G.roads
	var e: Array = g.nearest_edge(v.global_position)
	a = e[0]
	b = e[1]
	var goal: int = g.nearest(pos)
	route = g.path(b, goal)
	if route.size() > 0:
		route.pop_front()
	nxt = route[0] if route.size() > 0 else -1
	target_pos = pos
	arrived = false


func update(v, dt: float) -> void:
	frame += 1
	panic = max(0.0, panic - dt)
	honk_t = max(0.0, honk_t - dt)
	if reverse_t > 0.0:
		reverse_t -= dt
		v.throttle = -0.7
		v.brake = 0.0
		v.steer_in = -v.steer_in if frame % 30 == 0 else v.steer_in
		return
	match mode:
		"traffic", "goto":
			_lane_follow(v, dt)
		"direct":
			_direct(v, dt, target_pos, 9.0, 5.0)
		"pursuit":
			_pursuit(v, dt)
		"wait":
			v.throttle = 0.0
			v.brake = 1.0
			v.steer_in = 0.0
		"heli":
			_heli(v, dt)


func _choose_next(g) -> void:
	if mode == "goto":
		nxt = route[0] if route.size() > 0 else -1
		return
	var opts: Array = []
	for n in g.links[b]:
		if n != a:
			opts.append(n)
	if opts.is_empty():
		nxt = a
		return
	var d: Vector3 = g.edge_dir(a, b)
	for n in opts:
		if g.edge_dir(b, n).dot(d) > 0.9 and randf() < 0.55:
			nxt = n
			return
	nxt = opts[randi() % opts.size()]


func _lane_follow(v, dt: float) -> void:
	var g = G.roads
	if nxt < 0 and not (mode == "goto" and route.is_empty()):
		_choose_next(g)
	var d: Vector3 = g.edge_dir(a, b)
	var na: Vector3 = g.nodes[a]
	var len: float = na.distance_to(g.nodes[b])
	var t: float = (v.global_position - na).dot(d)
	var ch: float = g.cross_half(b, a)
	var stop_t: float = len - ch - 4.0
	var arterial: bool = g.is_arterial(a, b)
	if mode == "goto" and nxt < 0:
		# last edge: head straight for the goal once close
		if v.global_position.distance_to(target_pos) < 45.0 or t > stop_t:
			mode = "direct"
			return
	elif t > len - ch + 1.5:
		var turning: bool = nxt >= 0 and g.edge_dir(b, nxt).dot(d) < 0.5
		a = b
		b = nxt
		if mode == "goto" and route.size() > 0:
			route.pop_front()
		nxt = -1
		if not g.is_arterial(a, b):
			lane = 0
		elif turning:
			lane = randi() % 2
		return
	var look: float = clamp(4.0 + abs(v.fspeed) * 0.6, 5.0, 13.0)
	var target: Vector3
	var turn_ahead := false
	if t + look < len - ch or nxt < 0:
		target = g.lane_point(a, b, min(t + look, len), lane)
	else:
		var nl: int = lane if g.is_arterial(b, nxt) else 0
		target = g.lane_point(b, nxt, g.half_width(a, b) + 1.0 + max(0.0, t + look - (len - ch)) * 0.6, nl)
	if nxt >= 0 and g.edge_dir(b, nxt).dot(d) < 0.5:
		turn_ahead = true
	var vmax: float = 15.0 if arterial else 10.5
	if emergency:
		vmax *= 1.5
	if panic > 0.0:
		vmax *= 1.7
	if turn_ahead and t > stop_t - 10.0:
		vmax = min(vmax, 6.0)
	if G.sky and G.sky.rain_amount > 0.3:
		vmax *= 0.85
	# traffic signals
	if g.links[b].size() >= 3 and not emergency and panic <= 0.0 and t < stop_t + 1.5 and t > stop_t - 32.0:
		var st: int = g.light_state(b, abs(d.x) > 0.5)
		if st == 2 or (st == 1 and t < stop_t - 7.0):
			vmax = min(vmax, max(0.0, stop_t - t - 0.5) * 0.9)
	vmax = _obstacles(v, vmax)
	_drive_to(v, dt, target, vmax)


func _obstacles(v, vmax: float) -> float:
	var vf: Vector3 = -v.global_basis.z
	var vr: Vector3 = v.global_basis.x
	var pos: Vector3 = v.global_position
	var gap: float = 7.0 + abs(v.fspeed) * 1.3
	for o in G.vehicles:
		if o == v:
			continue
		var rel: Vector3 = o.global_position - pos
		var f: float = rel.dot(vf)
		if f > 0.5 and f < gap + o.def.L and abs(rel.dot(vr)) < 2.1 and abs(rel.y) < 3.0:
			var free: float = f - (v.def.L + o.def.L) * 0.5 - 2.2
			vmax = min(vmax, max(0.0, free) * 0.9 + max(0.0, o.linear_velocity.dot(vf)) * 0.8)
			if emergency and o.ai != null:
				o.ai.panic = max(o.ai.panic, 0.0)
	if frame % 3 == 0 or vmax < 3.0:
		for h in G.humanoids:
			if h.vehicle != null or h.dead:
				continue
			var rel2: Vector3 = h.global_position - pos
			var f2: float = rel2.dot(vf)
			if f2 > 1.0 and f2 < 6.0 + abs(v.fspeed) * 0.9 and abs(rel2.dot(vr)) < 1.7 and abs(rel2.y) < 2.5:
				if panic <= 0.0:
					vmax = min(vmax, max(0.0, f2 - v.def.L * 0.5 - 2.0))
					if honk_t <= 0.0 and v.fspeed < 1.0 and randf() < 0.02:
						honk_t = 4.0
						v.horn()
	return vmax


func _drive_to(v, dt: float, target: Vector3, vmax: float) -> void:
	var lt: Vector3 = v.global_transform.affine_inverse() * target
	var ang := atan2(lt.x, -lt.z)
	v.steer_in = clamp(ang * 2.2, -1.0, 1.0)
	var sp: float = v.fspeed
	if vmax < 0.4:
		v.throttle = 0.0
		v.brake = 1.0
	elif sp < vmax - 0.6:
		v.throttle = 1.0 if (panic > 0.0 or emergency) else 0.65
		v.brake = 0.0
	elif sp > vmax + 1.2:
		v.throttle = 0.0
		v.brake = clamp((sp - vmax) / 4.0, 0.25, 1.0)
	else:
		v.throttle = 0.15
		v.brake = 0.0
	v.handbrake = false
	if vmax > 2.5 and abs(sp) < 0.5:
		stuck_t += dt
		if stuck_t > 3.5:
			reverse_t = 1.6
			v.steer_in = -sign(ang) if abs(ang) > 0.1 else (1.0 if randf() < 0.5 else -1.0)
			stuck_t = 1.5
			want_despawn = true
	else:
		stuck_t = max(0.0, stuck_t - dt * 2.0)
		if abs(sp) > 3.0:
			want_despawn = false


func _direct(v, dt: float, tpos: Vector3, vmax: float, stop_dist: float) -> void:
	var dist: float = Vector2(tpos.x - v.global_position.x, tpos.z - v.global_position.z).length()
	if dist < stop_dist:
		v.throttle = 0.0
		v.brake = 1.0
		v.steer_in = 0.0
		if not arrived and abs(v.fspeed) < 1.0:
			arrived = true
			mode = "wait"
			if on_arrive.is_valid():
				on_arrive.call()
		return
	vmax = min(vmax, 3.0 + dist * 0.5)
	vmax = _avoid_walls(v, vmax)
	_drive_to(v, dt, tpos, vmax)


func _avoid_walls(v, vmax: float) -> float:
	if frame % 4 != 0:
		return vmax
	var o: Vector3 = v.global_position + Vector3.UP * 0.9
	var f: Vector3 = -v.global_basis.z
	var hit: Dictionary = G.ray(o, o + f * (6.0 + abs(v.fspeed) * 0.5), G.L_WORLD, [v])
	if not hit.is_empty() and abs(hit.normal.y) < 0.5:
		var dd: float = o.distance_to(hit.position)
		vmax = min(vmax, max(1.5, dd - v.def.L * 0.5 - 1.0))
		if dd < v.def.L * 0.5 + 1.6 and abs(v.fspeed) < 1.5:
			reverse_t = 1.4
			v.steer_in = 1.0 if hit.normal.dot(v.global_basis.x) < 0.0 else -1.0
	return vmax


func _pursuit(v, dt: float) -> void:
	var p = G.player
	if p == null or G.wanted == null or G.wanted.stars == 0:
		mode = "traffic"
		emergency = false
		v.siren_on = false
		var e: Array = G.roads.nearest_edge(v.global_position)
		a = e[0]
		b = e[1]
		nxt = -1
		return
	emergency = true
	var seen: bool = G.wanted.seen
	var tpos: Vector3 = p.global_position if seen else G.wanted.search_point(v)
	var dist: float = v.global_position.distance_to(tpos)
	var tv = p.vehicle
	repath_t -= dt
	# far away or out of sight: use the road graph
	if dist > 75.0 or (not seen and dist > 40.0):
		if repath_t <= 0.0:
			repath_t = 2.5
			set_route_to(v, tpos)
			if route.is_empty() and nxt < 0:
				nxt = -1
		var m := mode
		mode = "goto"
		_lane_follow(v, dt)
		if mode == "direct":
			repath_t = 0.0
		mode = m
		return
	if tv != null and seen:
		# intercept: aim slightly ahead; PIT toward the rear quarter when close
		var tvel: Vector3 = tv.linear_velocity
		var aim: Vector3 = tv.global_position + tvel * clamp(dist / 30.0, 0.0, 1.2)
		if dist < 14.0 and tvel.length() > 6.0:
			var side: float = 1.0 if (v.global_position - tv.global_position).dot(tv.global_basis.x) > 0.0 else -1.0
			aim = tv.global_position + tv.global_basis.z * 1.6 + tv.global_basis.x * side * 0.6
		var vmax: float = v.def.top
		if dist < 10.0 and tvel.length() < 3.0:
			vmax = 0.0  # box in / hold when the suspect has stopped
			if not arrived and abs(v.fspeed) < 1.5:
				arrived = true
				if on_arrive.is_valid():
					on_arrive.call()
		vmax = _avoid_walls(v, vmax)
		_drive_to(v, dt, aim, vmax)
		if abs(v.steer_in) > 0.8 and v.fspeed > 14.0:
			v.throttle = 0.2
	else:
		if dist < 16.0 and seen:
			v.throttle = 0.0
			v.brake = 1.0
			if not arrived and abs(v.fspeed) < 1.5:
				arrived = true
				if on_arrive.is_valid():
					on_arrive.call()
		elif dist < 9.0:
			v.throttle = 0.0
			v.brake = 1.0
			if not arrived and abs(v.fspeed) < 1.5:
				arrived = true
				if on_arrive.is_valid():
					on_arrive.call()
		else:
			var vm := _avoid_walls(v, min(v.def.top, 6.0 + dist * 0.5))
			_drive_to(v, dt, tpos, vm)


func _heli(v, dt: float) -> void:
	var p = G.player
	if p == null:
		return
	var leaving: bool = G.wanted == null or G.wanted.stars < 3
	var tpos: Vector3 = p.global_position if (G.wanted and G.wanted.seen) else (G.wanted.last_known if G.wanted else p.global_position)
	if leaving:
		tpos = Vector3(400, 0, -400)
	var gh: float = max(G.height(v.global_position.x, v.global_position.z), 0.0)
	var alt: float = max(gh, tpos.y) + heli_alt + (30.0 if leaving else 0.0)
	var to: Vector3 = tpos - v.global_position
	var hd: float = Vector2(to.x, to.z).length()
	var want_yaw := atan2(-to.x, -to.z)
	var yerr: float = wrapf(want_yaw - v.global_rotation.y, -PI, PI)
	v.yaw_in = clamp(-yerr * 1.5, -1.0, 1.0)
	var fwd_want: float = clamp((hd - 28.0) / 40.0, -0.35, 1.0)
	if abs(yerr) > 1.0:
		fwd_want *= 0.2
	v.pitch_in = clamp(fwd_want - v.fspeed / 45.0, -0.6, 1.0)
	v.roll_in = clamp(-v.linear_velocity.dot(v.global_basis.x) / 12.0, -0.5, 0.5)
	v.lift_in = clamp((alt - v.global_position.y) * 0.12 - v.linear_velocity.y * 0.3, -1.0, 1.0)
	v.engine_on = true
	if leaving:
		if v.global_position.distance_to(p.global_position) > 320.0:
			want_despawn = true
		return
	# spotlight + door gunner
	var sl = v.get_meta("spot", null)
	if sl != null:
		sl.look_at(p.global_position + Vector3.UP, Vector3.UP)
		sl.visible = G.sky.is_night() if G.sky else false
	if G.wanted.stars >= 4 and G.wanted.seen and hd < 90.0:
		heli_fire_t -= dt
		if heli_fire_t <= 0.0:
			heli_fire_t = 0.22 if fmod(G.time_now, 4.0) < 1.6 else 0.6
			if fmod(G.time_now, 4.0) < 1.6:
				var o: Vector3 = v.global_position + Vector3.DOWN * 0.3
				var tgt: Vector3 = p.global_position + Vector3.UP + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
				var dir := (tgt - o).normalized()
				var hit: Dictionary = G.ray(o, o + dir * 200.0, G.L_WORLD | G.L_VEH | G.L_CHAR | G.L_PROP, [v])
				var end: Vector3 = hit.position if not hit.is_empty() else o + dir * 200.0
				G.fx.tracer(o, end)
				G.fx.muzzle_flash(o + dir * 1.5, dir)
				G.audio.play3d("shot_rifle", o)
				if not hit.is_empty():
					var tn = G.damage_target(hit.collider, 14.0, null, hit.position, dir, "bullet")
					G.fx.impact(hit.position, hit.normal, tn)
