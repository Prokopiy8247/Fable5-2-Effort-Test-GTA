class_name City
extends RefCounted
## Static description of Marlow Bay: terrain function, road network, lane graph, sidewalk graph,
## block/lot building placements and points of interest. Pure data + math (no nodes).

const XS: Array[float] = [-200.0, -100.0, 0.0, 100.0, 200.0, 280.0]
const ZS: Array[float] = [-190.0, -90.0, 10.0, 110.0, 180.0]
const SIDEWALK := 3.0
const CURB := 0.15
const MAP_HALF := 300.0

static var nodes: Array = []      # {id, pos:Vector3, segs:[seg ids], hx, hz, signal:bool}
static var segs: Array = []       # {id, a, b, axis, half, lanes, traffic, p0, p1, len}
static var walk_nodes: Array = [] # Vector3
static var walk_edges: Array = [] # per node: Array of {to, cross:bool}
static var _built := false

const POI := [
	{"id": "safehouse", "name": "Safehouse", "pos": Vector3(-123, 0.3, 83), "icon": "home"},
	{"id": "police", "name": "Police Station", "pos": Vector3(27, 0.3, -12), "icon": "police"},
	{"id": "hospital", "name": "Bayside Medical", "pos": Vector3(-70, 0.3, -128), "icon": "hospital"},
	{"id": "gunshop", "name": "Brass & Bolt Arms", "pos": Vector3(-34, 0.3, 26), "icon": "gun"},
	{"id": "modshop", "name": "Torque House", "pos": Vector3(118, 0.3, -52), "icon": "wrench"},
	{"id": "gas", "name": "Fuelio Gas", "pos": Vector3(122, 0.3, -110), "icon": "gas"},
	{"id": "clothes", "name": "Threadline", "pos": Vector3(-14, 0.3, 26), "icon": "shirt"},
	{"id": "barber", "name": "Fade Room", "pos": Vector3(-34, 0.3, 97), "icon": "scissors"},
	{"id": "food", "name": "Bite Box", "pos": Vector3(-14, 0.3, 97), "icon": "food"},
	{"id": "airport", "name": "Marlow Airfield", "pos": Vector3(60, 0.3, -232), "icon": "plane"},
	{"id": "helipad", "name": "Helipads", "pos": Vector3(232, 0.3, -224), "icon": "heli"},
	{"id": "marina", "name": "Marina Pier", "pos": Vector3(60, 0.3, 188), "icon": "boat"},
	{"id": "docks", "name": "Port Marlow", "pos": Vector3(190, 0.3, 192), "icon": "boat"},
	{"id": "beach", "name": "Coral Beach", "pos": Vector3(-120, 0.3, 190), "icon": "beach"},
	{"id": "hill", "name": "Signal Hill Viewpoint", "pos": Vector3(-254, 24.5, -92), "icon": "view"},
	{"id": "park", "name": "Founders Park", "pos": Vector3(-150, 0.3, -40), "icon": "tree"},
	{"id": "range", "name": "Shooting Range", "pos": Vector3(232, 0.3, 60), "icon": "target"},
	{"id": "parking", "name": "Central Parking", "pos": Vector3(70, 0.3, 84), "icon": "parking"},
	{"id": "lighthouse", "name": "Lighthouse Rock", "pos": Vector3(-40, 2.2, 262), "icon": "view"},
]


static func hwx(x: float) -> float:
	return 8.0 if is_equal_approx(x, 0.0) else 5.0


static func hwz(z: float) -> float:
	return 8.0 if is_equal_approx(z, -190.0) else 5.0


# ------------------------------------------------------------------ terrain
static func terrain_height(x: float, z: float) -> float:
	var h := 0.0
	var rx := (x + 256.0) / 46.0
	var rz := (z + 95.0) / 92.0
	var r := sqrt(rx * rx + rz * rz)
	if r < 1.0:
		var t := clampf((1.0 - r) / 0.8, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		h += 24.0 * t + sin(x * 0.21) * cos(z * 0.17) * 0.6 * t
	var shore := 208.0
	if x < 106.0:
		var beach := 200.0 + 3.0 * sin(x * 0.035)
		shore = lerpf(beach, 208.0, clampf((x - 100.0) / 6.0, 0.0, 1.0))
	if z > shore:
		var d := z - shore
		if x < 103.0:
			h = -d * 0.12 if d < 12.0 else -1.44 - (d - 12.0) * 0.3
		else:
			h = maxf(-9.0, -d * 5.0)
	var e: float = maxf(maxf(-MAP_HALF - x, x - MAP_HALF), -MAP_HALF - z)
	if e > 0.0:
		h = minf(h, -e * 0.7)
	# lighthouse islet
	var di := Vector2(x + 40.0, z - 262.0).length()
	if di < 24.0:
		var ti := clampf((24.0 - di) / 14.0, 0.0, 1.0)
		ti = ti * ti * (3.0 - 2.0 * ti)
		h = maxf(h, lerpf(h, 2.0, ti))
	return maxf(h, -14.0)


static func district_name(p: Vector3) -> String:
	if terrain_height(p.x, p.z) < Game.WATER_Y - 0.3:
		return "Marlow Bay"
	if p.z < -198.0:
		return "Marlow Airfield"
	if p.x < -206.0 and p.z < 8.0:
		return "Signal Hill"
	if p.z >= 114.0:
		return "Port Marlow" if p.x >= 100.0 else "Bayfront"
	if p.x < -100.0:
		return "Founders Park" if (p.z > -85.0 and p.z < 5.0 and p.x > -195.0) else "Palm Court"
	if p.x >= 100.0:
		return "Ironworks"
	return "Downtown" if p.z < 10.0 else "Midtown Market"


# ------------------------------------------------------------------ road network
static func build() -> void:
	if _built:
		return
	_built = true
	nodes.clear()
	segs.clear()
	var grid := {}
	for xi in range(XS.size()):
		for zi in range(ZS.size()):
			if xi == 5 and zi == 4:
				continue
			var n := {"id": nodes.size(), "pos": Vector3(XS[xi], 0, ZS[zi]), "segs": [], "hx": hwx(XS[xi]), "hz": hwz(ZS[zi]), "xi": xi, "zi": zi, "signal": false}
			grid[Vector2i(xi, zi)] = n.id
			nodes.append(n)
	# segments along z (vertical roads)
	for xi in range(XS.size()):
		for zi in range(ZS.size() - 1):
			if grid.has(Vector2i(xi, zi)) and grid.has(Vector2i(xi, zi + 1)):
				_add_seg(grid[Vector2i(xi, zi)], grid[Vector2i(xi, zi + 1)], "z", hwx(XS[xi]))
	for zi in range(ZS.size()):
		for xi in range(XS.size() - 1):
			if grid.has(Vector2i(xi, zi)) and grid.has(Vector2i(xi + 1, zi)):
				_add_seg(grid[Vector2i(xi, zi)], grid[Vector2i(xi + 1, zi)], "x", hwz(ZS[zi]))
	for n in nodes:
		n.signal = n.segs.size() >= 3
	_build_walk()


static func _add_seg(a: int, b: int, axis: String, half: float) -> void:
	var s := {"id": segs.size(), "a": a, "b": b, "axis": axis, "half": half, "lanes": 2 if half > 6.0 else 1, "traffic": true}
	var pa: Vector3 = nodes[a].pos
	var pb: Vector3 = nodes[b].pos
	var d := (pb - pa).normalized()
	var ra: float = (nodes[a].hz if axis == "z" else nodes[a].hx) + SIDEWALK + 1.0
	var rb: float = (nodes[b].hz if axis == "z" else nodes[b].hx) + SIDEWALK + 1.0
	s["p0"] = pa + d * ra
	s["p1"] = pb - d * rb
	s["len"] = (s.p1 - s.p0).length()
	s["dir"] = d
	segs.append(s)
	nodes[a].segs.append(s.id)
	nodes[b].segs.append(s.id)


## Extra non-traffic stubs (drawn as roads but not driven by AI).
static func stubs() -> Array:
	return [
		{"p0": Vector3(-205, 0, 110), "p1": Vector3(-288, 0, 110), "half": 4.0},
		{"p0": Vector3(100, 0, -198), "p1": Vector3(100, 0, -207), "half": 5.0},
	]


static func lane_points(seg_id: int, dir: int, lane: int) -> Array:
	## Returns [start, end] of the lane centre line. dir 0: a->b, 1: b->a.
	var s: Dictionary = segs[seg_id]
	var d: Vector3 = s.dir if dir == 0 else -s.dir
	var right := Vector3(-d.z, 0, d.x)
	var lw: float = s.half / float(s.lanes)
	var off := right * (lw * (float(lane) + 0.5))
	if dir == 0:
		return [s.p0 + off, s.p1 + off]
	return [s.p1 + off, s.p0 + off]


static func seg_end_node(seg_id: int, dir: int) -> int:
	return segs[seg_id].b if dir == 0 else segs[seg_id].a


static func seg_dir(seg_id: int, dir: int) -> Vector3:
	return segs[seg_id].dir if dir == 0 else -segs[seg_id].dir


static func next_options(seg_id: int, dir: int, lane: int) -> Array:
	## Possible continuations at the end node: [{seg, dir, lane, turn}] turn: 0 straight, -1 left, 1 right, 2 u-turn
	var node_id := seg_end_node(seg_id, dir)
	var d := seg_dir(seg_id, dir)
	var out := []
	var lanes_in: int = segs[seg_id].lanes
	for s2 in nodes[node_id].segs:
		if s2 == seg_id:
			continue
		var sd: Dictionary = segs[s2]
		var dir2 := 0 if sd.a == node_id else 1
		var d2 := seg_dir(s2, dir2)
		var cross := d.x * d2.z - d.z * d2.x  # >0 => right turn (x east, z south)
		var dot := d.dot(d2)
		var turn := 0
		if dot < 0.5:
			turn = 1 if cross > 0.0 else -1
		if lanes_in == 2:
			if turn == -1 and lane == 1:
				continue
			if turn == 1 and lane == 0:
				continue
		var lane2 := 0
		if sd.lanes == 2:
			lane2 = lane if turn == 0 and lanes_in == 2 else (1 if turn == 1 else 0)
			if turn == 0 and lanes_in == 1:
				lane2 = Game.rng.randi() % 2
		out.append({"seg": s2, "dir": dir2, "lane": lane2, "turn": turn})
	if out.is_empty():
		for s2 in nodes[node_id].segs:
			if s2 != seg_id:
				var dir3 := 0 if segs[s2].a == node_id else 1
				out.append({"seg": s2, "dir": dir3, "lane": 0, "turn": 0})
	return out


static func signal_state(node_id: int, axis: String, t: float) -> int:
	## 0 green, 1 yellow, 2 red for traffic travelling along 'axis' into the node.
	var n: Dictionary = nodes[node_id]
	if not n.signal:
		return 0
	var ph := fmod(t + float(node_id) * 7.0, 26.0)
	if axis == "z":
		if ph < 10.0:
			return 0
		if ph < 12.5:
			return 1
		return 2
	if ph < 13.0:
		return 2
	if ph < 23.0:
		return 0
	if ph < 25.5:
		return 1
	return 2


static func nearest_node(p: Vector3) -> int:
	var best := 0
	var bd := 1e9
	for n in nodes:
		var d: float = (n.pos - p).length_squared()
		if d < bd:
			bd = d
			best = n.id
	return best


static func nearest_lane(p: Vector3, heading: Vector3 = Vector3.ZERO) -> Dictionary:
	## Closest lane point: {seg, dir, lane, pos, t}
	var best := {}
	var bd := 1e9
	for s in segs:
		for dir in range(2):
			if heading != Vector3.ZERO and seg_dir(s.id, dir).dot(heading) < -0.2:
				continue
			for lane in range(s.lanes):
				var lp := lane_points(s.id, dir, lane)
				var a: Vector3 = lp[0]
				var b: Vector3 = lp[1]
				var ab := b - a
				var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
				var q := a + ab * t
				var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
				if d < bd:
					bd = d
					best = {"seg": s.id, "dir": dir, "lane": lane, "pos": q, "t": t, "dist": sqrt(d)}
	return best


static func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	## A* over road nodes; returns node positions between the two points (GPS / police routing).
	var a := nearest_node(from)
	var b := nearest_node(to)
	var open := [a]
	var came := {}
	var g := {a: 0.0}
	var f := {a: (nodes[a].pos - nodes[b].pos).length()}
	while not open.is_empty():
		var cur: int = open[0]
		for o in open:
			if f.get(o, 1e9) < f.get(cur, 1e9):
				cur = o
		if cur == b:
			break
		open.erase(cur)
		for sid in nodes[cur].segs:
			var s: Dictionary = segs[sid]
			var nb: int = s.b if s.a == cur else s.a
			var ng: float = g[cur] + (nodes[nb].pos - nodes[cur].pos).length()
			if ng < g.get(nb, 1e9):
				came[nb] = cur
				g[nb] = ng
				f[nb] = ng + (nodes[nb].pos - nodes[b].pos).length()
				if not open.has(nb):
					open.append(nb)
	var path := PackedVector3Array()
	var c := b
	var guard := 0
	while guard < 64:
		path.insert(0, nodes[c].pos)
		if c == a or not came.has(c):
			break
		c = came[c]
		guard += 1
	return path


# ------------------------------------------------------------------ sidewalks
static func _build_walk() -> void:
	walk_nodes.clear()
	walk_edges.clear()
	# 4 corners per road node: 0 NW, 1 NE, 2 SE, 3 SW
	for n in nodes:
		var ox: float = n.hx + 1.6
		var oz: float = n.hz + 1.6
		for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			walk_nodes.append(n.pos + Vector3(q.x * ox, CURB, q.y * oz))
			walk_edges.append([])
	for n in nodes:
		var b: int = n.id * 4
		for i in range(4):
			_walk_link(b + i, b + (i + 1) % 4, true)
	for s in segs:
		var a: int = s.a * 4
		var b2: int = s.b * 4
		if s.axis == "x":   # a is west, b is east
			_walk_link(a + 1, b2 + 0, false)
			_walk_link(a + 2, b2 + 3, false)
		else:               # a is north, b is south
			_walk_link(a + 3, b2 + 0, false)
			_walk_link(a + 2, b2 + 1, false)


static func _walk_link(a: int, b: int, cross: bool) -> void:
	walk_edges[a].append({"to": b, "cross": cross})
	walk_edges[b].append({"to": a, "cross": cross})


static func nearest_walk_node(p: Vector3) -> int:
	var best := 0
	var bd := 1e9
	for i in range(walk_nodes.size()):
		var d: float = (walk_nodes[i] - p).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


# ------------------------------------------------------------------ blocks and lots
static func block_rect(ci: int, ri: int) -> Rect2:
	var x0: float = XS[ci] + hwx(XS[ci])
	var x1: float = XS[ci + 1] - hwx(XS[ci + 1])
	var z0: float = ZS[ri] + hwz(ZS[ri])
	var z1: float = ZS[ri + 1] - hwz(ZS[ri + 1])
	return Rect2(x0, z0, x1 - x0, z1 - z0)


const BLOCKS := {
	# [NW, NE, SW, SE] lot specs
	"0,0": ["bar:apt_a", "bar:apt_d", "two:apt_c,off_g", "bar:apt_b"],
	"1,0": ["one:hospital", "one:parking", "big:off_b", "bar:off_c"],
	"2,0": ["big:off_a", "big:off_e", "bar:off_f", "two:off_d,off_g"],
	"3,0": ["big:wh_c", "bar:wh_a", "one:gas_station", "bar:wh_b"],
	"0,1": ["park", "", "", ""],
	"1,1": ["bar:hotel", "big:off_a", "bar:shop_d", "two:off_d,apt_c"],
	"2,1": ["big:off_b", "bar:off_c", "one:police_station", "bar:shop_b"],
	"3,1": ["one:garage_mod", "bar:wh_a", "yard", "two:wh_d,wh_d"],
	"0,2": ["houses", "houses", "houses", "safe"],
	"1,2": ["bar:shop_a", "two:shop_gun,shop_clothing", "bar:apt_e", "two:shop_barber,shop_food"],
	"2,2": ["bar:shop_b", "bar:off_f", "bar:apt_a", "lot:shop_c"],
	"3,2": ["bar:wh_b", "big:wh_c", "yard", "two:wh_d,off_g"],
	"0,3": ["houses_s", "houses_s"],
	"1,3": ["bar:hotel", "bar:shop_a"],
	"2,3": ["bar:shop_d", "lot:shop_c"],
	"3,3": ["bar:wh_a", "yard"],
}


static func placements() -> Array:
	## Returns [{asset, pos, rot, tag}] for buildings plus [{tag:'park'|'yard'|'lot', rect}] areas via second array.
	var out := []
	for key in BLOCKS:
		var ci := int(key.split(",")[0])
		var ri := int(key.split(",")[1])
		var r := block_rect(ci, ri)
		var inner := r.grow(-(SIDEWALK + 2.0))
		var lots: Array = BLOCKS[key]
		for li in range(lots.size()):
			var spec: String = lots[li]
			if spec == "":
				continue
			var west := li % 2 == 0
			var north := li < 2
			if lots.size() == 2:
				north = false
			var lot := Rect2(inner.position.x if west else inner.position.x + inner.size.x * 0.5 + 2.0,
				inner.position.y if (north or lots.size() == 2) else inner.position.y + inner.size.y * 0.5 + 2.0,
				inner.size.x * 0.5 - 2.0, inner.size.y if lots.size() == 2 else inner.size.y * 0.5 - 2.0)
			var kind := spec.split(":")[0]
			var args: PackedStringArray = spec.split(":")[1].split(",") if spec.contains(":") else PackedStringArray()
			match kind:
				"park":
					out.append({"tag": "park", "rect": inner})
				"yard":
					out.append({"tag": "yard", "rect": lot})
				"houses", "houses_s", "safe":
					var names := ["house_a", "house_b", "house_c", "house_d", "house_e", "house_f"]
					var cnt := 2
					for i in range(cnt):
						var nm: String = names[(li * 2 + i + ci + ri) % names.size()]
						if kind == "safe" and i == 1:
							nm = "safehouse"
						var sz := Assets.size_of(nm)
						var x := lot.position.x + 10.0 + i * 19.0 if west else lot.end.x - 10.0 - (cnt - 1 - i) * 19.0
						x -= (sz.position.x + sz.size.x * 0.5) * (-1.0 if north else 1.0)
						var z := lot.position.y + 7.0 if north else lot.end.y - 7.0
						out.append({"asset": nm, "pos": Vector3(x, CURB, z), "rot": 180.0 if north else 0.0, "tag": "house"})
					out.append({"tag": "garden", "rect": lot, "north": north})
				_:
					var x_cursor := lot.position.x if west else lot.end.x
					for ai in range(args.size()):
						var nm2: String = args[ai]
						var sz2 := Assets.size_of(nm2)
						var w: float = sz2.size.x
						var d: float = sz2.size.z
						var cx := x_cursor + w * 0.5 if west else x_cursor - w * 0.5
						# asset local centre offset
						var off_x: float = sz2.position.x + w * 0.5
						var off_z: float = sz2.position.z + d * 0.5
						var z2: float
						var rot := 0.0
						if north:
							rot = 180.0
							z2 = lot.position.y + d * 0.5 + off_z
							cx += off_x
						else:
							z2 = lot.end.y - d * 0.5 - off_z
							cx -= off_x
						out.append({"asset": nm2, "pos": Vector3(cx, CURB, z2), "rot": rot, "tag": kind})
						x_cursor += (w + 3.0) if west else -(w + 3.0)
					if kind == "lot":
						out.append({"tag": "lot", "rect": lot, "north": north})
	# --- hand placed: west residential strip, airport, industrial east strip, coast
	for i in range(3):
		out.append({"asset": ["house_b", "house_d", "house_f"][i], "pos": Vector3(-226.0 - i * 21.0, 0.0, 95.0), "rot": 0.0, "tag": "house"})
		out.append({"asset": ["house_a", "house_e", "house_c"][i], "pos": Vector3(-222.0 - i * 21.0, 0.0, 125.0), "rot": 180.0, "tag": "house"})
	out.append({"asset": "house_e", "pos": Vector3(-222, 0, 40), "rot": 90.0, "tag": "house"})
	out.append({"asset": "house_a", "pos": Vector3(-222, 0, 62), "rot": 90.0, "tag": "house"})
	out.append({"asset": "house_d", "pos": Vector3(-222, 0, 152), "rot": 90.0, "tag": "house"})
	out.append({"asset": "terminal", "pos": Vector3(40, 0, -212), "rot": 0.0, "tag": "airport"})
	out.append({"asset": "control_tower", "pos": Vector3(-10, 0, -214), "rot": 180.0, "tag": "airport"})
	out.append({"asset": "hangar", "pos": Vector3(150, 0, -222), "rot": 180.0, "tag": "airport"})
	out.append({"asset": "hangar", "pos": Vector3(186, 0, -222), "rot": 180.0, "tag": "airport"})
	out.append({"asset": "wh_b", "pos": Vector3(240, 0, -140), "rot": 270.0, "tag": "ind"})
	out.append({"asset": "wh_d", "pos": Vector3(238, 0, -60), "rot": 270.0, "tag": "ind"})
	out.append({"asset": "wh_d", "pos": Vector3(238, 0, -24), "rot": 270.0, "tag": "ind"})
	out.append({"asset": "lighthouse", "pos": Vector3(-40, 1.6, 264), "rot": 180.0, "tag": "coast"})
	out.append({"asset": "wh_b", "pos": Vector3(250, 0, 150), "rot": 270.0, "tag": "ind"})
	return out


static func teleports() -> Dictionary:
	return {
		"Downtown": Vector3(8, 0.5, -90), "Midtown Market": Vector3(-50, 0.5, 14), "Palm Court (residential)": Vector3(-150, 0.5, 106),
		"Safehouse": Vector3(-123, 0.5, 96), "Founders Park": Vector3(-136, 0.5, -30), "Ironworks (industrial)": Vector3(150, 0.5, 6),
		"Torque House garage": Vector3(118, 0.5, -84), "Gun shop": Vector3(-34, 0.5, 13), "Police station": Vector3(27, 0.5, 14),
		"Hospital": Vector3(-70, 0.5, -96), "Airfield apron": Vector3(40, 0.5, -236), "Helipads": Vector3(222, 0.5, -232),
		"Marina pier": Vector3(60, 0.5, 190), "Port Marlow docks": Vector3(180, 0.5, 196), "Coral Beach": Vector3(-120, 0.5, 192),
		"Signal Hill viewpoint": Vector3(-250, 25.0, -90), "Shooting range": Vector3(226, 0.5, 60), "Expressway": Vector3(-150, 0.5, -186),
		"Lighthouse Rock": Vector3(-40, 2.6, 256), "Shipwreck (dive)": Vector3(-170, -0.5, 258), "Skyline station": Vector3(-60, 0.5, 187),
		"Tower rooftop (base jump)": Vector3(77, 80.5, -150),
	}
