extends Node
## Pedestrian population: sidewalk graph, spawn/despawn around the player, simulation tiers,
## noise distribution and witness queries for the wanted system.

const CH := 0.16

var nodes := PackedVector3Array()
var adj: Array = []
var crossings := {}
var npcs: Array = []
var cap := 26
var spawn_t := 0.0
var tier_t := 0.0
var clerks: Array = []
var enabled := true


func _ready() -> void:
	_build_graph()
	G.noise.connect(_on_noise)
	call_deferred("_spawn_clerks")


func _add_node(p: Vector3) -> int:
	nodes.append(p)
	adj.append([])
	return nodes.size() - 1


func _link(a: int, b: int, cross = null) -> void:
	adj[a].append(b)
	adj[b].append(a)
	if cross != null:
		crossings["%d_%d" % [a, b]] = cross
		crossings["%d_%d" % [b, a]] = cross


func _build_graph() -> void:
	var L := WorldLayout
	var base := {}
	for bj in 4:
		for bi in 6:
			var r := L.block_rect(bi, bj)
			var x0 := r.position.x + 2.0
			var z0 := r.position.y + 2.0
			var x1 := r.end.x - 2.0
			var z1 := r.end.y - 2.0
			var b := _add_node(Vector3(x0, CH, z0))
			_add_node(Vector3(x1, CH, z0))
			_add_node(Vector3(x1, CH, z1))
			_add_node(Vector3(x0, CH, z1))
			base[Vector2i(bi, bj)] = b
			for k in 4:
				_link(b + k, b + (k + 1) % 4)
			if L.BLOCKS[bj][bi] == "park":
				var c := _add_node(Vector3((x0 + x1) * 0.5 + 4.0, CH, (z0 + z1) * 0.5 + 11.0))
				for k in 4:
					_link(c, b + k)
	for bj in 4:
		for bi in 6:
			var b: int = base[Vector2i(bi, bj)]
			if bi < 5:
				var e: int = base[Vector2i(bi + 1, bj)]
				_link(b + 1, e + 0, {"along_x": false, "ix": Vector2i(bi + 1, bj)})
				_link(b + 2, e + 3, {"along_x": false, "ix": Vector2i(bi + 1, bj + 1)})
			if bj < 3:
				var s: int = base[Vector2i(bi, bj + 1)]
				_link(b + 3, s + 0, {"along_x": true, "ix": Vector2i(bi, bj + 1)})
				_link(b + 2, s + 1, {"along_x": true, "ix": Vector2i(bi + 1, bj + 1)})
	# promenade along the coast
	var prev := -1
	for bi in 6:
		var b2: int = base[Vector2i(bi, 3)]
		var pw := _add_node(Vector3(nodes[b2 + 3].x, CH, 180.3))
		var pe := _add_node(Vector3(nodes[b2 + 2].x, CH, 180.3))
		_link(pw, pe)
		_link(b2 + 3, pw, {"along_x": true, "ix": Vector2i(bi, 4)})
		_link(b2 + 2, pe, {"along_x": true, "ix": Vector2i(bi + 1, 4)})
		if prev >= 0:
			_link(prev, pw)
		prev = pe
		if bi == 2:
			var p0 := _add_node(Vector3(-40.0, CH, 181.0))
			var p1 := _add_node(Vector3(-40.0, CH, 222.0))
			var p2 := _add_node(Vector3(-40.0, CH, 258.0))
			_link(pw, p0)
			_link(pe, p0)
			_link(p0, p1)
			_link(p1, p2)


func neighbors(i: int) -> Array:
	return adj[i] if i >= 0 and i < adj.size() else []


func node_pos(i: int) -> Vector3:
	return nodes[i]


func nearest_node(p: Vector3) -> int:
	var best := 0
	var bd := 1e12
	for i in nodes.size():
		var d := nodes[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func is_crossing(a: int, b: int) -> bool:
	return crossings.has("%d_%d" % [a, b])


func can_cross(a: int, b: int) -> bool:
	var c: Dictionary = crossings.get("%d_%d" % [a, b], {})
	if c.is_empty():
		return true
	var t: float = G.traffic.sig_time if G.traffic else 0.0
	if WorldLayout.signalized(c.ix):
		return WorldLayout.signal_state(c.ix, c.along_x, t) == 2
	var mid := (nodes[a] + nodes[b]) * 0.5
	for v in get_tree().get_nodes_in_group("vehicles"):
		var veh := v as Vehicle
		if veh.speed > 3.0 and veh.global_position.distance_to(mid) < 12.0:
			return false
	return true


func adopt(n: NPC) -> void:
	n.manager = self
	if not npcs.has(n):
		npcs.append(n)


func spawn(kind: String, pos: Vector3, lk: Dictionary = {}) -> NPC:
	var n := NPC.new()
	n.setup(kind, lk)
	n.manager = self
	G.main.add_child(n)
	n.global_position = pos
	npcs.append(n)
	return n


func make_driver(kind: String = "civ") -> NPC:
	## An NPC that is not walking the streets (will be seated in a vehicle by the caller).
	var n := NPC.new()
	n.setup(kind)
	n.manager = self
	G.main.add_child(n)
	return n


func _spawn_clerks() -> void:
	if G.world == null:
		return
	for c in G.world.spawns.get("clerks", []):
		var n := spawn("clerk", c.pos)
		n.face_yaw = float(c.yaw) + PI
		n.rotation.y = n.face_yaw
		n.shop_kind = c.kind
		n.home = c.pos
		clerks.append(n)
		npcs.erase(n)


func _on_noise(pos: Vector3, radius: float, nkind: String, source: Node) -> void:
	var r2 := radius * radius
	for n in npcs:
		if is_instance_valid(n) and n != source and n.global_position.distance_squared_to(pos) < r2:
			n.hear(pos, nkind, source)
	for c in clerks:
		if is_instance_valid(c) and nkind in ["gunshot", "explosion"] and c.global_position.distance_squared_to(pos) < minf(r2, 900.0):
			c.hear(pos, nkind, source)


func witnesses(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	for n in npcs:
		if not is_instance_valid(n) or n.dead or n.ragdoll != null:
			continue
		if n.global_position.distance_to(pos) < radius and n.can_see(pos + Vector3(0, 1.0, 0), radius, -0.6):
			out.append(n)
	return out


func police_near(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	for n in npcs:
		if is_instance_valid(n) and n.is_police and not n.dead and n.global_position_now().distance_to(pos) < radius:
			out.append(n)
	return out


func _process(delta: float) -> void:
	if G.player == null:
		return
	var pp: Vector3 = G.player.global_position_now()
	var cam := get_viewport().get_camera_3d()
	tier_t -= delta
	if tier_t <= 0.0:
		tier_t = 0.5
		var i := npcs.size() - 1
		while i >= 0:
			var raw = npcs[i]
			if not is_instance_valid(raw):
				npcs.remove_at(i)
				i -= 1
				continue
			var n: NPC = raw
			if n.vehicle == null and not n.dead:
				var d := n.global_position_now().distance_to(pp)
				n.tier = 0 if d < 45.0 else (1 if d < 85.0 else 2)
				var vis := cam != null and cam.is_position_in_frustum(n.global_position + Vector3(0, 1, 0))
				var is_wanted_cop: bool = n.is_police and G.wanted != null and G.wanted.level > 0
				if (d > 150.0 or (d > 100.0 and not vis)) and not is_wanted_cop:
					n.queue_free()
					npcs.remove_at(i)
				elif is_wanted_cop and d > 230.0:
					n.queue_free()
					npcs.remove_at(i)
			i -= 1
	if not enabled or not G.flags.peds:
		return
	spawn_t -= delta
	if spawn_t > 0.0:
		return
	spawn_t = 0.35
	var walking := 0
	for n in npcs:
		if is_instance_valid(n) and n.vehicle == null and not n.dead:
			walking += 1
	var density: float = float(G.settings.density)
	if G.timew:
		density *= lerpf(1.0, 0.45, G.timew.night) * lerpf(1.0, 0.6, clampf(G.timew.cur.rain, 0.0, 1.0))
	if walking >= int(cap * density):
		return
	for attempt in 6:
		var idx := G.rng.randi() % nodes.size()
		var p := nodes[idx]
		var d2 := p.distance_to(pp)
		if d2 < 34.0 or d2 > 105.0:
			continue
		if cam != null and cam.is_position_in_frustum(p + Vector3(0, 1, 0)) and d2 < 70.0:
			continue
		var kind := "civ"
		var dist_name := WorldLayout.district_at(p)
		var r := G.rng.randf()
		if r < 0.07:
			kind = "cop"
		elif r < 0.2 and dist_name in ["Ironworks", "Harbor Docks"]:
			kind = "gang"
		var n2 := spawn(kind, p + Vector3(G.rng.randf_range(-1, 1), 0.05, G.rng.randf_range(-1, 1)))
		n2.node_cur = idx
		n2.goal = p
		n2.tier = 1
		break


func clear_all() -> void:
	for n in npcs:
		if is_instance_valid(n) and n.vehicle == null:
			n.queue_free()
	npcs = npcs.filter(func(n): return is_instance_valid(n) and n.vehicle != null)
