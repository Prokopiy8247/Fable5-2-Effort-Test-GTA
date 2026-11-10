class_name WalkGraph
extends RefCounted
## HALCYON BAY pedestrian graph: sidewalks on both sides of the streets, crosswalks at intersections,
## alley / track mouth crossings, plaza / park / promenade / pier / beach / hill paths.
## Contract: random_point(), get_nearest_point(), find_path(). Nodes are about 9 m apart.

const Geom := preload("res://gta/code/world/gen/world_geom.gd")

const MERGE_DIST := 1.0
const SPACING := 9.0
const CELL := 12.0
const K_SIDEWALK := 0
const K_CROSSWALK := 1
const K_PATH := 2

var points := PackedVector3Array()          ## node positions (on the walkable surface)
var links: Array[PackedInt32Array] = []     ## adjacency
var kinds := PackedByteArray()              ## K_* per node
var main := PackedByteArray()               ## 1 = node belongs to the main connected component
var build_ms := 0

var _cells := {}
var _height: Callable
var _empty := PackedInt32Array()


# ---------------------------------------------------------------------------------------------
# construction
# ---------------------------------------------------------------------------------------------

func _key(x: float, z: float) -> int:
	return (int(floor(x / CELL)) + 4096) * 8192 + (int(floor(z / CELL)) + 4096)


func _find_node(p: Vector2, max_d: float, skip: Dictionary = {}) -> int:
	var best := -1
	var best_d := max_d * max_d
	var r := int(ceil(max_d / CELL))
	var cx := int(floor(p.x / CELL))
	var cz := int(floor(p.y / CELL))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var lst: PackedInt32Array = _cells.get((cx + dx + 4096) * 8192 + (cz + dz + 4096), _empty)
			for id in lst:
				if skip.has(id):
					continue
				var q := points[id]
				var d := (q.x - p.x) * (q.x - p.x) + (q.z - p.y) * (q.z - p.y)
				if d <= best_d:
					best_d = d
					best = id
	return best


func add_node(p: Vector2, kind: int) -> int:
	var hit := _find_node(p, MERGE_DIST)
	if hit >= 0:
		return hit
	var id := points.size()
	points.append(Vector3(p.x, float(_height.call(p.x, p.y)), p.y))
	links.append(PackedInt32Array())
	kinds.append(kind)
	var k := _key(p.x, p.y)
	var lst: PackedInt32Array = _cells.get(k, _empty)
	if lst.is_empty():
		lst = PackedInt32Array()
	lst.append(id)
	_cells[k] = lst
	return id


func add_link(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0:
		return
	var la := links[a]
	if la.has(b):
		return
	la.append(b)
	links[a] = la
	var lb := links[b]
	lb.append(a)
	links[b] = lb


## Adds a chain of nodes along the polyline. With snap > 0 loose ends are linked to the nearest
## existing node within that distance.
func add_path(pts: PackedVector2Array, kind: int, snap: float = 0.0) -> void:
	if pts.size() < 2:
		return
	var dense := Geom.resample(pts, SPACING)
	var own := {}
	var prev := -1
	var first := -1
	for q in dense:
		var id := add_node(q, kind)
		if first < 0:
			first = id
		if prev >= 0:
			add_link(prev, id)
		own[id] = true
		prev = id
	if snap > 0.0:
		for end_id: int in [first, prev]:
			if links[end_id].size() <= 1:
				var e := points[end_id]
				var other := _find_node(Vector2(e.x, e.z), snap, own)
				if other >= 0:
					add_link(end_id, other)


func build(roads: RoadGraph, height_fn: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	_height = height_fn
	var sw_w: float = WorldLayout.SIDEWALK_W
	var half := sw_w * 0.5
	# 1. sidewalk centre lines
	for s: Dictionary in roads.segments:
		var hw: float = s["hw"]
		for side: int in [-1, 1]:
			var span: Array = s["sw_l_span"] if side == -1 else s["sw_r_span"]
			if span.is_empty():
				continue
			var s0: float = float(span[0]) + (0.5 if span[2] else 0.0)
			var s1: float = float(span[1]) - (0.5 if span[3] else 0.0)
			var sub := Geom.sub(s["pts2"], s0, s1)
			add_path(Geom.offset(sub, float(side) * (hw + half)), K_SIDEWALK)
	for node: Dictionary in roads.intersections:
		var c3: Vector3 = node["position"]
		var c := Vector2(c3.x, c3.z)
		var legs: Array = node["legs"]
		var n := legs.size()
		# 2. corner connectors
		for cn: Dictionary in node["corners"]:
			var da: Vector2 = cn["da"]
			var db: Vector2 = cn["db"]
			var hwa: float = cn["hwa"]
			var hwb: float = cn["hwb"]
			add_path(PackedVector2Array([c + da * (hwb + sw_w) + db * (hwa + half), c + da * (hwb + half) + db * (hwa + half),
					c + da * (hwb + half) + db * (hwa + sw_w)]), K_SIDEWALK)
		if n < 3:
			continue
		for i in n:
			var b: Dictionary = legs[i]
			var d: Vector2 = b["dir"]
			var hwb: float = b["hw"]
			# 3. unmarked crossing of a sidewalk-less mouth (alley, dirt track)
			var prev: Dictionary = legs[(i + n - 1) % n]
			var next: Dictionary = legs[(i + 1) % n]
			if not bool(b["sw_ccw"]) and not bool(b["sw_cw"]) and bool(prev["sw_cw"]) and bool(next["sw_ccw"]) \
					and (prev["dir"] as Vector2).dot(next["dir"]) < -0.7:
				var e0: Vector2 = c + (prev["dir"] as Vector2) * (hwb + 0.5) + d * (float(prev["hw"]) + half)
				var e1: Vector2 = c + (next["dir"] as Vector2) * (hwb + 0.5) + d * (float(next["hw"]) + half)
				add_path(PackedVector2Array([e0, e1]), K_CROSSWALK, 4.0)
			# 4. marked crosswalk across this leg
			if b["crosswalk"]:
				var t := float(b["trim"]) + (WorldLayout.CROSSWALK_NEAR + WorldLayout.CROSSWALK_FAR) * 0.5
				var r := Geom.right_of(d)
				add_path(PackedVector2Array([c + d * t + r * (hwb + half), c + d * t - r * (hwb + half)]), K_CROSSWALK, 7.0)
	# 5. foot paths along the dirt tracks (right-hand edge going out of town)
	for s: Dictionary in roads.segments:
		if String(s["kind"]) != "dirt":
			continue
		var a0: float = float(s["trim_a"]) + half
		var a1: float = float(s["length"]) - 1.0
		if a1 - a0 < 4.0:
			continue
		add_path(Geom.offset(Geom.sub(s["pts2"], a0, a1), float(s["hw"]) - 0.8), K_PATH, 14.0)
	# 6. authored paths
	for flat: Array in WorldLayout.WALK_PATHS:
		add_path(WorldLayout.pts2(flat), K_PATH, 30.0)
	_connect_components()
	build_ms = Time.get_ticks_msec() - t0


func _components() -> Array:
	var comp := PackedInt32Array()
	comp.resize(points.size())
	comp.fill(-1)
	var sizes: Array[int] = []
	for start in points.size():
		if comp[start] >= 0:
			continue
		var cid := sizes.size()
		var stack: Array[int] = [start]
		comp[start] = cid
		var cnt := 0
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			cnt += 1
			for nb in links[cur]:
				if comp[nb] < 0:
					comp[nb] = cid
					stack.append(nb)
		sizes.append(cnt)
	return [comp, sizes]


func _connect_components() -> void:
	for pass_i in 12:
		var res := _components()
		var comp: PackedInt32Array = res[0]
		var sizes: Array[int] = res[1]
		if sizes.size() <= 1:
			break
		var big := 0
		for i in sizes.size():
			if sizes[i] > sizes[big]:
				big = i
		var linked := false
		for cid in sizes.size():
			if cid == big:
				continue
			var best_a := -1
			var best_b := -1
			var best_d := 60.0 * 60.0
			for a in points.size():
				if comp[a] != cid:
					continue
				for b in points.size():
					if comp[b] != big:
						continue
					var d := points[a].distance_squared_to(points[b])
					if d < best_d:
						best_d = d
						best_a = a
						best_b = b
			if best_a >= 0:
				add_link(best_a, best_b)
				linked = true
		if not linked:
			break
	var res2 := _components()
	var comp2: PackedInt32Array = res2[0]
	var sizes2: Array[int] = res2[1]
	var big2 := 0
	for i in sizes2.size():
		if sizes2[i] > sizes2[big2]:
			big2 = i
	main.resize(points.size())
	for i in points.size():
		main[i] = 1 if comp2[i] == big2 else 0


# ---------------------------------------------------------------------------------------------
# queries
# ---------------------------------------------------------------------------------------------

func node_count() -> int:
	return points.size()


## Nearest node of the main component (-1 if the graph is empty).
func get_nearest_node(pos: Vector3) -> int:
	var p := Vector2(pos.x, pos.z)
	var radius := CELL
	while radius < 1600.0:
		var best := -1
		var best_d := radius * radius
		var r := int(ceil(radius / CELL))
		var cx := int(floor(p.x / CELL))
		var cz := int(floor(p.y / CELL))
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var lst: PackedInt32Array = _cells.get((cx + dx + 4096) * 8192 + (cz + dz + 4096), _empty)
				for id in lst:
					if main[id] == 0:
						continue
					var q := points[id]
					var d := (q.x - p.x) * (q.x - p.x) + (q.z - p.y) * (q.z - p.y)
					if d <= best_d:
						best_d = d
						best = id
		if best >= 0:
			return best
		radius *= 2.5
	return -1


## Closest point on the walk network (Vector3.INF if the graph is empty).
func get_nearest_point(pos: Vector3) -> Vector3:
	var n := get_nearest_node(pos)
	if n < 0:
		return Vector3.INF
	var best := points[n]
	var best_d := best.distance_squared_to(pos)
	for m in links[n]:
		var a := points[n]
		var ab := points[m] - a
		var l2 := ab.length_squared()
		if l2 < 0.0001:
			continue
		var c := a + ab * clampf((pos - a).dot(ab) / l2, 0.0, 1.0)
		var d := c.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = c
	return best


## Random walkable point whose horizontal distance to `near` is inside [min_d, max_d].
func random_point(near: Vector3, min_d: float, max_d: float) -> Vector3:
	if points.is_empty():
		return Vector3.INF
	var rng: RandomNumberGenerator = Game.rng
	var r := int(ceil(max_d / CELL))
	var cx := int(floor(near.x / CELL))
	var cz := int(floor(near.z / CELL))
	var min2 := min_d * min_d
	var max2 := max_d * max_d
	var pick := -1
	var seen := 0
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var lst: PackedInt32Array = _cells.get((cx + dx + 4096) * 8192 + (cz + dz + 4096), _empty)
			for id in lst:
				if main[id] == 0:
					continue
				var q := points[id]
				var d := (q.x - near.x) * (q.x - near.x) + (q.z - near.z) * (q.z - near.z)
				if d < min2 or d > max2:
					continue
				seen += 1
				if rng.randi() % seen == 0:
					pick = id
	if pick < 0:
		return Vector3.INF
	var ls := links[pick]
	if ls.is_empty():
		return points[pick]
	var other := ls[rng.randi() % ls.size()]
	return points[pick].lerp(points[other], rng.randf() * 0.5)


func _heap_push(ids: PackedInt32Array, fs: PackedFloat32Array, id: int, f: float) -> void:
	ids.append(id)
	fs.append(f)
	var i := ids.size() - 1
	while i > 0:
		@warning_ignore("integer_division")
		var p := (i - 1) / 2
		if fs[p] <= fs[i]:
			break
		var ti := ids[p]
		ids[p] = ids[i]
		ids[i] = ti
		var tf := fs[p]
		fs[p] = fs[i]
		fs[i] = tf
		i = p


func _heap_pop(ids: PackedInt32Array, fs: PackedFloat32Array) -> int:
	var top := ids[0]
	var last := ids.size() - 1
	ids[0] = ids[last]
	fs[0] = fs[last]
	ids.resize(last)
	fs.resize(last)
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var s := i
		if l < last and fs[l] < fs[s]:
			s = l
		if r < last and fs[r] < fs[s]:
			s = r
		if s == i:
			break
		var ti := ids[s]
		ids[s] = ids[i]
		ids[i] = ti
		var tf := fs[s]
		fs[s] = fs[i]
		fs[i] = tf
		i = s
	return top


## Node ids of the shortest path between two nodes (empty if unreachable).
func find_node_path(from_node: int, to_node: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := points.size()
	if from_node < 0 or to_node < 0 or from_node >= n or to_node >= n:
		return out
	if from_node == to_node:
		out.append(from_node)
		return out
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(1.0e12)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var hid := PackedInt32Array()
	var hf := PackedFloat32Array()
	var goal := points[to_node]
	g[from_node] = 0.0
	_heap_push(hid, hf, from_node, points[from_node].distance_to(goal))
	while not hid.is_empty():
		var cur := _heap_pop(hid, hf)
		if cur == to_node:
			var c := cur
			while c >= 0:
				out.append(c)
				c = came[c]
			out.reverse()
			return out
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		var pc := points[cur]
		for nb in links[cur]:
			if closed[nb] == 1:
				continue
			var cost := g[cur] + pc.distance_to(points[nb])
			if kinds[nb] == K_CROSSWALK:
				cost += 4.0
			if cost < g[nb]:
				g[nb] = cost
				came[nb] = cur
				_heap_push(hid, hf, nb, cost + points[nb].distance_to(goal))
	return out


## Walkable polyline from the network point nearest `from` to the one nearest `to` (empty if none).
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var ids := find_node_path(get_nearest_node(from), get_nearest_node(to))
	for id in ids:
		out.append(points[id])
	return out
