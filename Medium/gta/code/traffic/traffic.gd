extends Node3D
## Lane-graph civilian traffic: spawning/despawning around the player, signal-aware AI drivers, parked cars, carjacking.

const Vehicle := preload("res://gta/code/vehicles/vehicle.gd")
const Defs := preload("res://gta/code/core/defs.gd")
const LANE_OFF := 2.5

var lanes: Array = []            # {a: Vector2i, b: Vector2i, p0, p1, dir, ns, speed, len}
var out_lanes: Dictionary = {}   # Vector2i -> [lane idx]
var ai_list: Array = []
var enabled := true
var density := 14
var _spawn_t := 0.0
var _tick := 0


func start() -> void:
	_build_graph()
	_spawn_parked()


func node_pos(n: Vector2i) -> Vector3:
	return Vector3(G.world.XR[n.x], 0, G.world.ZR[n.y])


func _build_graph() -> void:
	var W = G.world
	for i in 5:
		for j in 5:
			out_lanes[Vector2i(i, j)] = []
	for i in 5:
		for j in 5:
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a = Vector2i(i, j)
				var b: Vector2i = a + d
				if b.x > 4 or b.y > 4:
					continue
				_add_lane(a, b)
				_add_lane(b, a)


func _add_lane(a: Vector2i, b: Vector2i) -> void:
	var W = G.world
	var pa = node_pos(a)
	var pb = node_pos(b)
	var dir = (pb - pa).normalized()
	var ns: bool = abs(dir.z) > 0.5
	var right = dir.cross(Vector3.UP)
	var trim_a: float = (W.hw(W.ZR[a.y]) if ns else W.hw(W.XR[a.x])) + 3.0
	var trim_b: float = (W.hw(W.ZR[b.y]) if ns else W.hw(W.XR[b.x])) + 3.0
	var p0 = pa + dir * trim_a + right * LANE_OFF
	var p1 = pb - dir * trim_b + right * LANE_OFF
	var sp = 11.0
	var ring: bool = (ns and abs(pa.x) == 240.0) or (not ns and abs(pa.z) == 200.0)
	if ring:
		sp = 16.0
	elif (ns and pa.x == 0.0) or (not ns and pa.z == 0.0):
		sp = 13.0
	lanes.append({"a": a, "b": b, "p0": p0, "p1": p1, "dir": dir, "ns": ns, "speed": sp, "len": p0.distance_to(p1)})
	out_lanes[a].append(lanes.size() - 1)


## Breadth-first route over intersections (used by taxi rides and the GPS line).
func route(from: Vector3, to: Vector3) -> Array:
	var s = nearest_node(from)
	var e = nearest_node(to)
	var prev = {s: s}
	var queue = [s]
	while queue.size() > 0:
		var c: Vector2i = queue.pop_front()
		if c == e:
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x > 4 or n.y > 4 or prev.has(n):
				continue
			prev[n] = c
			queue.append(n)
	var out = [e]
	var c2: Vector2i = e
	while c2 != s:
		c2 = prev[c2]
		out.push_front(c2)
	return out


func nearest_node(p: Vector3) -> Vector2i:
	var best = Vector2i.ZERO
	var bd = 1e9
	for i in 5:
		for j in 5:
			var d = G.dist2d(node_pos(Vector2i(i, j)), p)
			if d < bd:
				bd = d
				best = Vector2i(i, j)
	return best


func nearest_lane(p: Vector3, heading = null) -> Dictionary:
	var best = {}
	var bd = 1e9
	for li in lanes.size():
		var l: Dictionary = lanes[li]
		var t: float = clamp((p - l.p0).dot(l.dir), 0.0, l.len)
		var q: Vector3 = l.p0 + l.dir * t
		var d = G.dist2d(q, p)
		if heading != null and l.dir.dot(heading) < 0.0:
			d += 6.0
		if d < bd:
			bd = d
			best = {"lane": li, "t": t, "pos": q, "dist": d}
	return best


# ------------------------------------------------------------------ creation
func create(id: String, pos: Vector3, yaw := 0.0, col = null):
	var v = RigidBody3D.new()
	v.set_script(Vehicle)
	G.main.add_child(v)
	v.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	v.setup(id, col)
	return v


func _spawn_parked() -> void:
	var ids = ["sedan", "compact", "suv", "pickup", "van", "muscle", "sports", "motorcycle", "sedan", "compact", "bicycle", "taxi"]
	for sp in G.world.parking:
		if G.rng.randf() < 0.3:
			continue
		var p: Vector3 = sp.pos
		# keep the car inside the parking strip
		var right = Basis(Vector3.UP, sp.yaw).x
		var id: String = ids[G.rng.randi() % ids.size()]
		var v = create(id, p, sp.yaw)
		v.park()
	# a few fixed showcase vehicles
	var fixed = [["helicopter", Vector3(95, 0.3, -232), 0.0], ["plane", Vector3(-250, 0.3, G.world.RUNWAY_Z), -PI / 2], ["jet", Vector3(170, 0.3, -230), 0.0],
		["speedboat", Vector3(47, G.WATER_Y + 0.3, 240), 0.0], ["dinghy", Vector3(93, G.WATER_Y + 0.3, 236), 0.0], ["speedboat", Vector3(-73, G.WATER_Y + 0.3, 262), PI],
		["bicycle", Vector3(-150, 0.4, 208.5), PI / 2], ["motorcycle", Vector3(-168, 0.4, -6.0), PI / 2]]
	for f in fixed:
		var v = create(f[0], f[1], f[2])
		v.owner_tag = "parked"
		if f[0] in ["bicycle", "motorcycle"]:
			v.park()
	var hn = G.world.building_nodes.get("hospital")
	if hn:
		var hv = create("helicopter", hn.global_position + Vector3(0, 17.4, 0), 0.0)
		hv.owner_tag = "parked"


func pick_traffic_id() -> String:
	var total = 0
	for id in Defs.VEHICLES:
		total += Defs.VEHICLES[id].get("traffic", 0)
	var r = G.rng.randi() % total
	for id in Defs.VEHICLES:
		r -= Defs.VEHICLES[id].get("traffic", 0)
		if r < 0:
			return id
	return "sedan"


func spawn_on_lane(id: String, li: int, t: float, tag := "traffic"):
	var l: Dictionary = lanes[li]
	var p: Vector3 = l.p0 + l.dir * t + Vector3(0, 0.45, 0)
	var v = create(id, p, atan2(-l.dir.x, -l.dir.z))
	v.owner_tag = tag
	v.set_driver(self)
	v.ai = {"lane": li, "mode": "lane", "personality": G.rng.randf_range(0.85, 1.15), "stuck": 0.0, "panic": 0.0, "wait": 0.0, "honk": 0.0, "route": []}
	v.npc_look = {}
	v.linear_velocity = l.dir * l.speed * 0.6
	ai_list.append(v)
	return v


func release(v) -> void:
	ai_list.erase(v)
	if is_instance_valid(v):
		v.ai = {}


func adopt(v, li: int, route_nodes: Array = []) -> void:
	v.set_driver(self)
	v.ai = {"lane": li, "mode": "lane", "personality": 1.0, "stuck": 0.0, "panic": 0.0, "wait": 0.0, "honk": 0.0, "route": route_nodes}
	if not ai_list.has(v):
		ai_list.append(v)


func carjack(v, by) -> void:
	if not v.has_ai_driver():
		return
	var d = v.driver
	release(v)
	v.driver = null
	v.in_throttle = 0.0
	v.in_brake = 1.0
	if G.pop:
		var p: Vector3 = v.door_pos(-1.0) + Vector3(0, 0.2, 0)
		var npc = G.pop.spawn_ped(p, v.npc_look if not v.npc_look.is_empty() else {}, "cop" if v.owner_tag == "police" else "ped")
		if npc:
			npc.thrown_from_vehicle(v, by)
	if G.wanted and by == G.player:
		G.wanted.crime("carjack", v.global_position, 1.0 if v.owner_tag != "police" else 2.5)


func on_crash(v, dv: float) -> void:
	if v.ai.is_empty():
		# player-driven vehicle hitting something
		if v.driver == G.player and dv > 9.0 and G.wanted:
			G.wanted.crime("collision", v.global_position, 0.35)
		return
	if not v.ai.has("wait"):
		return
	v.ai.wait = max(v.ai.wait, 1.5)
	if dv > 9.0 and G.player and G.player.vehicle and G.dist2d(v.global_position, G.player_pos()) < 12.0:
		v.ai.panic = 6.0 if G.rng.randf() < 0.5 else 0.0
		if v._horn == null:
			v.horn(true)
			get_tree().create_timer(1.2).timeout.connect(func(): if is_instance_valid(v): v.horn(false))


func scare(pos: Vector3, radius: float) -> void:
	for v in ai_list:
		if is_instance_valid(v) and v.owner_tag == "traffic" and v.global_position.distance_to(pos) < radius:
			v.ai.panic = G.rng.randf_range(5.0, 10.0)


# ------------------------------------------------------------------ simulation
func _physics_process(dt: float) -> void:
	_tick += 1
	if G.world:
		G.world.update_signals(dt)
	var pp = G.player_pos()
	for v in ai_list.duplicate():
		if not is_instance_valid(v) or v.dead or v.ai.is_empty():
			ai_list.erase(v)
			continue
		var d = G.dist2d(v.global_position, pp)
		if d > 80.0 and (_tick + v.get_instance_id()) % 3 != 0:
			continue
		_drive(v, dt, d)
	_spawn_t -= dt
	if _spawn_t <= 0.0:
		_spawn_t = 0.5
		_manage(pp)


func _manage(pp: Vector3) -> void:
	var cam = get_viewport().get_camera_3d()
	var count = 0
	for v in ai_list.duplicate():
		if not is_instance_valid(v):
			continue
		if v.owner_tag != "traffic":
			continue
		var d = G.dist2d(v.global_position, pp)
		var behind: bool = cam != null and (v.global_position - cam.global_position).dot(-cam.global_basis.z) < 0.0
		if d > 210.0 or (d > 120.0 and behind) or v.ai.stuck > 25.0 and d > 45.0:
			ai_list.erase(v)
			v.queue_free()
		else:
			count += 1
	# cleanup abandoned traffic vehicles far away
	if _tick % 120 < 30:
		for v in get_tree().get_nodes_in_group("vehicles"):
			if v.owner_tag in ["traffic", "abandoned"] and v.driver == null and v.ai.is_empty() and G.dist2d(v.global_position, pp) > 170.0:
				v.queue_free()
	if not enabled:
		return
	var want: int = int(density * (0.55 if G.is_night() else 1.0))
	var tries = 0
	while count < want and tries < 6:
		tries += 1
		var li = G.rng.randi() % lanes.size()
		var l: Dictionary = lanes[li]
		var t = G.rng.randf_range(4.0, l.len - 8.0)
		var p: Vector3 = l.p0 + l.dir * t
		var d = G.dist2d(p, pp)
		if d < 70.0 or d > 170.0:
			continue
		if cam and d < 130.0:
			var to = (p - cam.global_position).normalized()
			if to.dot(-cam.global_basis.z) > 0.55 and G.los(cam.global_position, p + Vector3(0, 1, 0)):
				continue
		var blocked = false
		for o in get_tree().get_nodes_in_group("vehicles"):
			if o.global_position.distance_squared_to(p) < 14.0 * 14.0:
				blocked = true
				break
		if blocked:
			continue
		spawn_on_lane(pick_traffic_id(), li, t)
		count += 1


func _next_lane(v, l: Dictionary) -> int:
	var opts: Array = out_lanes[l.b]
	var rt: Array = v.ai.route
	if rt.size() > 0:
		# follow the planned route
		while rt.size() > 0 and rt[0] == l.b:
			rt.pop_front()
		if rt.size() > 0:
			for o in opts:
				if lanes[o].b == rt[0]:
					return o
	var cands = []
	for o in opts:
		if lanes[o].b != l.a:
			cands.append(o)
			if lanes[o].dir.dot(l.dir) > 0.9:
				cands.append(o)
				cands.append(o)
	if cands.is_empty():
		return opts[0]
	return cands[G.rng.randi() % cands.size()]


func _drive(v, dt: float, pdist: float) -> void:
	var ai: Dictionary = v.ai
	var l: Dictionary = lanes[ai.lane]
	var pos: Vector3 = v.global_position
	var fwd: Vector3 = -v.global_basis.z
	var target: Vector3
	var want_speed: float = l.speed * ai.personality
	var emergency: bool = v.siren_on or ai.panic > 0.0
	if ai.panic > 0.0:
		ai.panic -= dt
		want_speed *= 1.7
	if ai.mode == "lane":
		var t: float = (pos - l.p0).dot(l.dir)
		var remain: float = l.len - t
		target = l.p0 + l.dir * min(l.len, t + 6.0 + abs(v.speed) * 0.5)
		if not ai.has("next"):
			ai["next"] = _next_lane(v, l)
		var nl: Dictionary = lanes[ai.next]
		var turning: bool = nl.dir.dot(l.dir) < 0.9
		if remain < 22.0:
			if turning:
				want_speed = min(want_speed, 5.5)
			# traffic signal
			if not emergency and remain < 18.0 and remain > 1.0 and G.world.signal_stop(G.world.XR[l.b.x], G.world.ZR[l.b.y], l.ns):
				want_speed = 0.0 if remain < 9.0 else min(want_speed, 4.0)
		if remain <= 0.5:
			ai.mode = "turn"
			ai["c0"] = l.p1
			ai["c2"] = nl.p0
			# control point: intersection of the two lane lines
			var cp: Vector3 = l.p1 + l.dir * (nl.p0 - l.p1).dot(l.dir)
			ai["c1"] = cp
			ai["ct"] = 0.0
			ai["clen"] = max(4.0, l.p1.distance_to(cp) + cp.distance_to(nl.p0))
	else:
		ai.ct += max(1.5, abs(v.speed)) * dt / ai.clen
		var ct: float = min(1.0, ai.ct + 4.5 / ai.clen)
		var a: Vector3 = ai.c0.lerp(ai.c1, ct)
		var b: Vector3 = ai.c1.lerp(ai.c2, ct)
		target = a.lerp(b, ct)
		var nl2: Dictionary = lanes[ai.next]
		if nl2.dir.dot(l.dir) < 0.9:
			want_speed = min(want_speed, 6.0)
		if ai.ct >= 1.0 or (pos - nl2.p0).dot(nl2.dir) > 0.0 and G.dist2d(pos, nl2.p0) < 6.0:
			ai.lane = ai.next
			ai.erase("next")
			ai.mode = "lane"
			if ai.has("on_node"):
				ai.on_node.call(lanes[ai.lane].a)
	# yield to sirens
	if not emergency and G.wanted and G.wanted.siren_near(pos):
		target += fwd.cross(Vector3.UP) * 2.4
		want_speed = min(want_speed, 3.0)
	# obstacle sensing
	var sense: float = 5.0 + max(0.0, v.speed) * 0.9
	var from: Vector3 = pos + Vector3(0, 0.7, 0) + fwd * (v._half.z + 0.3)
	var hit = G.ray(from, from + fwd * sense, G.L_VEH | G.L_CHAR | (G.L_WORLD if ai.mode == "lane" else 0), [v.get_rid()])
	var blocked = false
	if hit:
		var hd: float = from.distance_to(hit.position)
		if hit.collider is CharacterBody3D or hit.collider is RigidBody3D:
			blocked = true
			if ai.panic > 0.0 and hit.collider is CharacterBody3D:
				blocked = false
			else:
				want_speed = 0.0 if hd < 4.0 else min(want_speed, hd * 0.9)
		elif hd < 3.5:
			blocked = true
			want_speed = 0.0
	if ai.wait > 0.0:
		ai.wait -= dt
		want_speed = 0.0
	# stuck handling
	if abs(v.speed) < 0.6 and want_speed <= 0.1 and blocked:
		ai.stuck += dt
		ai.honk += dt
		if ai.honk > 3.5 and pdist < 40.0:
			ai.honk = -G.rng.randf_range(2.0, 6.0)
			v.horn(true)
			get_tree().create_timer(0.7).timeout.connect(func(): if is_instance_valid(v): v.horn(false))
		if ai.stuck > 9.0:
			# creep around the obstacle
			target += fwd.cross(Vector3.UP) * -3.0
			want_speed = 3.0
			if ai.stuck > 13.0:
				ai.stuck = 4.0
	elif abs(v.speed) > 2.0:
		ai.stuck = max(0.0, ai.stuck - dt * 2.0)
	# steering
	var to = target - pos
	to.y = 0.0
	var ang = fwd.signed_angle_to(to.normalized(), Vector3.UP)
	v.in_steer = clamp(ang * 2.2, -1.0, 1.0)
	var err: float = want_speed - v.speed
	if want_speed <= 0.1:
		v.in_throttle = 0.0
		v.in_brake = 1.0 if abs(v.speed) > 0.3 else 0.6
	elif err > 0.0:
		v.in_throttle = clamp(err * 0.45, 0.15, 1.0)
		v.in_brake = 0.0
	else:
		v.in_throttle = 0.0
		v.in_brake = clamp(-err * 0.25, 0.0, 1.0)
	v.in_hand = false
