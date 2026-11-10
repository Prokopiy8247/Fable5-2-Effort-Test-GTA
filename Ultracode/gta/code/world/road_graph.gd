class_name RoadGraph
extends RefCounted
## HALCYON BAY road network: segments, intersections, directed lanes (right-hand traffic), signal
## phases, nearest-lane queries and A* routing. Built from WorldLayout.ROADS by build().
##
## Contract members (docs/ARCHITECTURE.md 6.1): segments, lanes, intersections, get_nearest_lane,
## sample_lane, get_next_lanes, get_signal_state, find_route, find_lane_route, random_lane_point.
## Extra keys / helpers are documented in docs/WORLD.md.

const Geom := preload("res://gta/code/world/gen/world_geom.gd")
const EdgeGrid := preload("res://gta/code/world/gen/world_edgegrid.gd")

const GREEN_TIME := 9.0
const YELLOW_TIME := 2.5
const ALL_RED_TIME := 1.5
const PHASE_TIME := GREEN_TIME + YELLOW_TIME + ALL_RED_TIME
const CYCLE_TIME := PHASE_TIME * 2.0
const DEAD_END_CUT := 2.5
const MAX_SPEED := 22.0

## {id, points: PackedVector3Array, width, lanes_per_dir, speed_limit, kind, name} + extras:
## pts2, length, hw, node_a, node_b, parking, sw_l, sw_r, trim_a, trim_b, lanes_fwd, lanes_back,
## sw_l_span / sw_r_span ([s0, s1, cap0, cap1] or [] = no sidewalk on that side).
var segments: Array[Dictionary] = []
## {id, points, length, speed_limit, next: PackedInt32Array, segment_id, end_intersection} + extras:
## start_intersection, direction (+1 along the segment, -1 against), index (0 = next to the centre
## line), cum (PackedFloat32Array), pts2, kind, signal_group (-1 = no signal), yield (bool).
var lanes: Array[Dictionary] = []
## {id, position, radius, has_signal} + extras: legs (clockwise), box (half extents x / z),
## corners (sidewalk corner patches), phase_offset, lanes_in, lanes_out.
var intersections: Array[Dictionary] = []
## Rounded road bends: {v, centre, r, d0, d1, side, ang, steps, hw, sw_l, sw_r}.
var bends: Array[Dictionary] = []

var signal_time := 0.0
var total_lane_length := 0.0
var build_ms := 0
var seg_grid: EdgeGrid               ## segment centre lines, registered with their corridor margin

var _terrain: Terrain
var _lane_grid: EdgeGrid
var _lane_start := PackedFloat32Array()
var _sig_group := PackedInt32Array()
var _sig_offset := PackedFloat32Array()
var _node_pos: Array[Vector2] = []


# ---------------------------------------------------------------------------------------------
# build
# ---------------------------------------------------------------------------------------------

func build(terrain: Terrain) -> void:
	var t0 := Time.get_ticks_msec()
	_terrain = terrain
	var roads := _prepare_roads()
	_split(roads)
	_add_airfield()
	_build_intersections()
	_build_sidewalk_spans()
	_build_lanes()
	_connect_lanes()
	_build_grids()
	build_ms = Time.get_ticks_msec() - t0


func _y(x: float, z: float) -> float:
	var h: float = _terrain.get_mesh_height(x, z) if _terrain != null else Terrain.height(x, z)
	return h + WorldLayout.ROAD_LIFT


func _to3(p: PackedVector2Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(p.size())
	for i in p.size():
		out[i] = Vector3(p[i].x, _y(p[i].x, p[i].y), p[i].y)
	return out


func _prepare_roads() -> Array:
	var defs: Array = WorldLayout.ROADS
	var raws: Array = []
	for d: Dictionary in defs:
		var raw := WorldLayout.pts2(d["pts"])
		if d.get("closed", false):
			raw.append(raw[0])
		raws.append(raw)
	var out: Array = []
	for i in defs.size():
		var d: Dictionary = defs[i]
		var raw: PackedVector2Array = raws[i]
		var pts := raw
		var kind: String = d["kind"]
		var kd: Dictionary = WorldLayout.KINDS[kind]
		var hw: float = float(d.get("hw", kd["hw"]))
		var sw: bool = kd["sw"]
		var sw_l: bool = d.get("sw_l", sw)
		var sw_r: bool = d.get("sw_r", sw)
		if d.get("smooth", false):
			pts = Geom.catmull(raw, 3.0)
		elif float(d.get("round", 0.0)) > 0.0:
			var radii := PackedFloat32Array()
			radii.resize(raw.size())
			for v in range(1, raw.size() - 1):
				var junction := false
				for j in defs.size():
					if j != i and float(Geom.closest(raws[j], raw[v])[0]) < 0.6:
						junction = true
						break
				radii[v] = 0.0 if junction else float(d["round"])
			var my_bends: Array = []
			pts = Geom.round_some(raw, radii, my_bends)
			for b: Dictionary in my_bends:
				b["hw"] = hw
				b["sw_l"] = sw_l
				b["sw_r"] = sw_r
				bends.append(b)
		out.append({"def": d, "pts": pts, "kind": kind, "hw": hw, "sw_l": sw_l, "sw_r": sw_r,
				"cuts": PackedFloat32Array(), "cum": Geom.cumulative(pts)})
	return out


func _bbox(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r.grow(1.0)


func _node_at(p: Vector2) -> int:
	for k in _node_pos.size():
		if _node_pos[k].distance_squared_to(p) < 0.64:
			return k
	_node_pos.append(p)
	return _node_pos.size() - 1


func _split(roads: Array) -> void:
	var boxes: Array[Rect2] = []
	for r: Dictionary in roads:
		boxes.append(_bbox(r["pts"]))
	for i in roads.size():
		var pi: PackedVector2Array = roads[i]["pts"]
		var ci: PackedFloat32Array = roads[i]["cum"]
		for j in range(i + 1, roads.size()):
			if not boxes[i].intersects(boxes[j]):
				continue
			var bj := boxes[j]
			var pj: PackedVector2Array = roads[j]["pts"]
			var cj: PackedFloat32Array = roads[j]["cum"]
			for a in range(1, pi.size()):
				var a0 := pi[a - 1]
				var a1 := pi[a]
				if maxf(a0.x, a1.x) < bj.position.x or minf(a0.x, a1.x) > bj.end.x \
						or maxf(a0.y, a1.y) < bj.position.y or minf(a0.y, a1.y) > bj.end.y:
					continue
				for b in range(1, pj.size()):
					var b0 := pj[b - 1]
					var b1 := pj[b]
					if maxf(b0.x, b1.x) < minf(a0.x, a1.x) - 0.2 or minf(b0.x, b1.x) > maxf(a0.x, a1.x) + 0.2 \
							or maxf(b0.y, b1.y) < minf(a0.y, a1.y) - 0.2 or minf(b0.y, b1.y) > maxf(a0.y, a1.y) + 0.2:
						continue
					var hit := Geom.seg_hit(a0, a1, b0, b1, 0.05)
					if is_inf(hit.x):
						continue
					_pushf(roads[i], "cuts", ci[a - 1] + a0.distance_to(hit))
					_pushf(roads[j], "cuts", cj[b - 1] + b0.distance_to(hit))
	for r: Dictionary in roads:
		var pts: PackedVector2Array = r["pts"]
		var d: Dictionary = r["def"]
		var kind: String = r["kind"]
		var kd: Dictionary = WorldLayout.KINDS[kind]
		var total := Geom.length_of(pts)
		var cuts: PackedFloat32Array = r["cuts"]
		cuts.append(0.0)
		cuts.append(total)
		cuts.sort()
		var clean := PackedFloat32Array()
		for c in cuts:
			if clean.is_empty() or c - clean[clean.size() - 1] > 0.8:
				clean.append(c)
		clean[clean.size() - 1] = total
		for c in range(1, clean.size()):
			var sub := Geom.sub(pts, clean[c - 1], clean[c])
			var na := _node_at(sub[0])
			var nb := _node_at(sub[sub.size() - 1])
			sub[0] = _node_pos[na]
			sub[sub.size() - 1] = _node_pos[nb]
			var hw: float = r["hw"]
			segments.append({
				"id": segments.size(), "points": _to3(sub), "width": hw * 2.0, "lanes_per_dir": int(kd["lanes"]),
				"speed_limit": float(d.get("speed", kd["speed"])), "kind": kind, "name": String(d["name"]),
				"pts2": sub, "length": Geom.length_of(sub), "hw": hw, "node_a": na, "node_b": nb,
				"parking": bool(d.get("parking", false)), "sw_l": bool(r["sw_l"]), "sw_r": bool(r["sw_r"]),
				"trim_a": 0.0, "trim_b": 0.0, "lanes_fwd": PackedInt32Array(), "lanes_back": PackedInt32Array(),
				"sw_l_span": [], "sw_r_span": [], "offs": kd["offs"],
			})


func _add_airfield() -> void:
	for d: Dictionary in WorldLayout.AIRFIELD:
		var kind: String = d["kind"]
		var kd: Dictionary = WorldLayout.KINDS[kind]
		var p := WorldLayout.pts2(d["pts"])
		var hw: float = float(d.get("hw", kd["hw"]))
		segments.append({
			"id": segments.size(), "points": _to3(p), "width": hw * 2.0, "lanes_per_dir": 0, "speed_limit": 0.0,
			"kind": kind, "name": String(d["name"]), "pts2": p, "length": Geom.length_of(p), "hw": hw,
			"node_a": -1, "node_b": -1, "parking": false, "sw_l": false, "sw_r": false, "trim_a": 0.0, "trim_b": 0.0,
			"lanes_fwd": PackedInt32Array(), "lanes_back": PackedInt32Array(), "sw_l_span": [], "sw_r_span": [], "offs": [],
		})


static func _push(d: Dictionary, key: String, v: int) -> void:
	var a: PackedInt32Array = d[key]
	a.append(v)
	d[key] = a


static func _pushf(d: Dictionary, key: String, v: float) -> void:
	var a: PackedFloat32Array = d[key]
	a.append(v)
	d[key] = a


func _build_intersections() -> void:
	for k in _node_pos.size():
		var legs: Array[Dictionary] = []
		var arterial := false
		var majors := 0
		for s: Dictionary in segments:
			for at_start: bool in [true, false]:
				if int(s["node_a"] if at_start else s["node_b"]) != k:
					continue
				var p: PackedVector2Array = s["pts2"]
				var n := p.size()
				var dir: Vector2 = (p[1] - p[0]).normalized() if at_start else (p[n - 2] - p[n - 1]).normalized()
				var kind: String = s["kind"]
				var major := kind == "arterial" or kind == "street"
				if kind == "arterial":
					arterial = true
				if major:
					majors += 1
				legs.append({"seg": int(s["id"]), "start": at_start, "dir": dir, "angle": atan2(dir.y, dir.x),
						"hw": float(s["hw"]), "kind": kind, "major": major, "rank": int(WorldLayout.KINDS[kind]["rank"]),
						"sw_cw": bool(s["sw_r"] if at_start else s["sw_l"]), "sw_ccw": bool(s["sw_l"] if at_start else s["sw_r"]),
						"trim": 0.0, "crosswalk": false, "lanes_in": PackedInt32Array(), "lanes_out": PackedInt32Array()})
		legs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["angle"]) < float(b["angle"]))
		var bx := 0.0
		var bz := 0.0
		var walk_legs := 0
		for l: Dictionary in legs:
			var dir: Vector2 = l["dir"]
			if absf(dir.y) > 0.7:
				bx = maxf(bx, float(l["hw"]))
			else:
				bz = maxf(bz, float(l["hw"]))
			if l["sw_cw"] and l["sw_ccw"]:
				walk_legs += 1
		if legs.size() < 2:
			bx = 0.0
			bz = 0.0
		var has_signal := legs.size() >= 3 and ((arterial and majors >= 3) or majors >= 4)
		for l: Dictionary in legs:
			var dir: Vector2 = l["dir"]
			var trim := bz if absf(dir.y) > 0.7 else bx
			l["trim"] = trim
			l["crosswalk"] = legs.size() >= 3 and bool(l["sw_cw"]) and bool(l["sw_ccw"]) and (has_signal or walk_legs >= 3)
			var s: Dictionary = segments[int(l["seg"])]
			if l["start"]:
				s["trim_a"] = trim
			else:
				s["trim_b"] = trim
		var pos2 := _node_pos[k]
		intersections.append({"id": k, "position": Vector3(pos2.x, _y(pos2.x, pos2.y), pos2.y),
				"radius": (maxf(bx, bz) + WorldLayout.STOP_SETBACK) if legs.size() > 1 else 4.0,
				"has_signal": has_signal, "legs": legs, "box": Vector2(bx, bz), "corners": [],
				"phase_offset": fposmod(float(k) * 7.37, CYCLE_TIME),
				"lanes_in": PackedInt32Array(), "lanes_out": PackedInt32Array()})


## Sidewalk ribbon spans per segment side and the corner patches between neighbouring legs.
func _build_sidewalk_spans() -> void:
	var sw_w: float = WorldLayout.SIDEWALK_W
	for node: Dictionary in intersections:
		var legs: Array = node["legs"]
		var n := legs.size()
		var c2 := Vector2((node["position"] as Vector3).x, (node["position"] as Vector3).z)
		for i in n:
			var a: Dictionary = legs[i]
			var seg: Dictionary = segments[int(a["seg"])]
			var da: Vector2 = a["dir"]
			for cw: bool in [true, false]:
				if not bool(a["sw_cw"] if cw else a["sw_ccw"]):
					continue
				var trim := 0.0
				var cap := true
				if n > 1:
					var b: Dictionary = legs[(i + 1) % n] if cw else legs[(i + n - 1) % n]
					var db: Vector2 = b["dir"]
					if da.dot(db) < -0.7:
						trim = 0.0
						cap = not bool(b["sw_ccw"] if cw else b["sw_cw"])
					elif bool(b["sw_ccw"] if cw else b["sw_cw"]):
						trim = float(b["hw"]) + sw_w
						cap = false
						if cw:
							var hwa: float = a["hw"]
							var hwb: float = b["hw"]
							(node["corners"] as Array).append({
								"c": c2 + da * hwb + db * hwa, "o": c2 + da * (hwb + sw_w) + db * (hwa + sw_w),
								"da": da, "db": db, "hwa": hwa, "hwb": hwb})
					else:
						trim = float(b["hw"])
						cap = true
				# looking outward from the node: clockwise side = right. Map to the segment's own sides.
				var seg_right := (cw == bool(a["start"]))
				var key := "sw_r_span" if seg_right else "sw_l_span"
				var span: Array = seg[key]
				if span.is_empty():
					span = [0.0, float(seg["length"]), true, true]
				if a["start"]:
					span[0] = trim
					span[2] = cap
				else:
					span[1] = float(seg["length"]) - trim
					span[3] = cap
				seg[key] = span
	for s: Dictionary in segments:
		for key: String in ["sw_l_span", "sw_r_span"]:
			var span: Array = s[key]
			if not span.is_empty() and float(span[1]) - float(span[0]) < 1.0:
				s[key] = []


func _build_lanes() -> void:
	for s: Dictionary in segments:
		var lpd: int = s["lanes_per_dir"]
		if lpd == 0:
			continue
		var offs: Array = s["offs"]
		for dirn: int in [1, -1]:
			var base: PackedVector2Array = s["pts2"] if dirn == 1 else Geom.reversed(s["pts2"])
			var n_start: int = s["node_a"] if dirn == 1 else s["node_b"]
			var n_end: int = s["node_b"] if dirn == 1 else s["node_a"]
			var t_start: float = s["trim_a"] if dirn == 1 else s["trim_b"]
			var t_end: float = s["trim_b"] if dirn == 1 else s["trim_a"]
			var cut0: float = DEAD_END_CUT if (intersections[n_start]["legs"] as Array).size() == 1 else t_start + WorldLayout.STOP_SETBACK
			var cut1: float = DEAD_END_CUT if (intersections[n_end]["legs"] as Array).size() == 1 else t_end + WorldLayout.STOP_SETBACK
			for k in lpd:
				var poly := Geom.trim(Geom.offset(base, float(offs[k])), cut0, cut1)
				var p3 := _to3(poly)
				var cum := PackedFloat32Array()
				cum.resize(p3.size())
				var acc := 0.0
				for i in range(1, p3.size()):
					acc += p3[i].distance_to(p3[i - 1])
					cum[i] = acc
				var id := lanes.size()
				lanes.append({"id": id, "points": p3, "length": acc, "speed_limit": float(s["speed_limit"]),
						"next": PackedInt32Array(), "segment_id": int(s["id"]), "end_intersection": n_end,
						"start_intersection": n_start, "direction": dirn, "index": k, "cum": cum, "pts2": poly,
						"kind": String(s["kind"]), "signal_group": -1, "yield": false})
				_push(s, "lanes_fwd" if dirn == 1 else "lanes_back", id)
				_push(intersections[n_end], "lanes_in", id)
				_push(intersections[n_start], "lanes_out", id)
				for l: Dictionary in intersections[n_end]["legs"]:
					if int(l["seg"]) == int(s["id"]) and bool(l["start"]) == (dirn == -1):
						_push(l, "lanes_in", id)
				for l: Dictionary in intersections[n_start]["legs"]:
					if int(l["seg"]) == int(s["id"]) and bool(l["start"]) == (dirn == 1):
						_push(l, "lanes_out", id)


func _lane_end_dir(l: Dictionary) -> Vector2:
	var p: PackedVector2Array = l["pts2"]
	return (p[p.size() - 1] - p[p.size() - 2]).normalized()


func _lane_start_dir(l: Dictionary) -> Vector2:
	var p: PackedVector2Array = l["pts2"]
	return (p[1] - p[0]).normalized()


func _connect_lanes() -> void:
	_sig_group.resize(lanes.size())
	_sig_group.fill(-1)
	_sig_offset.resize(lanes.size())
	_sig_offset.fill(0.0)
	for node: Dictionary in intersections:
		var ins: PackedInt32Array = node["lanes_in"]
		var outs: PackedInt32Array = node["lanes_out"]
		var legs: Array = node["legs"]
		for li in ins:
			var lane: Dictionary = lanes[li]
			var nxt := PackedInt32Array()
			var d_in := _lane_end_dir(lane)
			var n_in: int = segments[int(lane["segment_id"])]["lanes_per_dir"]
			for lo in outs:
				var o: Dictionary = lanes[lo]
				if int(o["segment_id"]) == int(lane["segment_id"]):
					continue
				var d_out := _lane_start_dir(o)
				var dot := d_in.dot(d_out)
				if dot < -0.7:
					continue
				var cross := d_in.x * d_out.y - d_in.y * d_out.x
				var turn := 0 if dot > 0.7 else (1 if cross > 0.0 else -1)   # 1 right, -1 left
				var n_out: int = segments[int(o["segment_id"])]["lanes_per_dir"]
				var ok := false
				if n_in == 1 and n_out == 1:
					ok = true
				elif n_in >= 2 and n_out >= 2:
					ok = int(lane["index"]) == int(o["index"])
				elif n_in >= 2:
					ok = (int(lane["index"]) == 0) if turn == -1 else (int(lane["index"]) == n_in - 1)
				else:
					ok = (int(o["index"]) == 0) if turn == -1 else (int(o["index"]) == n_out - 1)
				if ok:
					nxt.append(lo)
			if nxt.is_empty():
				for lo in outs:
					if int(lanes[lo]["segment_id"]) != int(lane["segment_id"]):
						nxt.append(lo)
			if nxt.is_empty():
				for lo in outs:       # dead end: U-turn onto the opposite direction
					nxt.append(lo)
			lane["next"] = nxt
		# signals / priorities
		if node["has_signal"]:
			var axis: Vector2 = legs[0]["dir"]
			for li in ins:
				var g := 0 if absf(_lane_end_dir(lanes[li]).dot(axis)) > 0.7 else 1
				lanes[li]["signal_group"] = g
				_sig_group[li] = g
				_sig_offset[li] = float(node["phase_offset"])
		elif legs.size() >= 3:
			var max_rank := 0
			var any_through := false
			for l: Dictionary in legs:
				max_rank = maxi(max_rank, int(l["rank"]))
			for l: Dictionary in legs:
				var through := false
				for m: Dictionary in legs:
					if (l["dir"] as Vector2).dot(m["dir"]) < -0.9:
						through = true
				l["through"] = through
				any_through = any_through or through
			for l: Dictionary in legs:
				var must_yield := int(l["rank"]) < max_rank or (any_through and not bool(l["through"]))
				for li: int in (l["lanes_in"] as PackedInt32Array):
					lanes[li]["yield"] = must_yield


func _build_grids() -> void:
	_lane_grid = EdgeGrid.new(16.0)
	_lane_start.resize(lanes.size())
	total_lane_length = 0.0
	for l: Dictionary in lanes:
		_lane_grid.add_polyline(int(l["id"]), l["pts2"], 0.0)
		_lane_start[int(l["id"])] = total_lane_length
		total_lane_length += float(l["length"])
	seg_grid = EdgeGrid.new(16.0)
	for s: Dictionary in segments:
		seg_grid.add_polyline(int(s["id"]), s["pts2"], float(s["hw"]) + WorldLayout.SIDEWALK_W + 0.6)


# ---------------------------------------------------------------------------------------------
# queries
# ---------------------------------------------------------------------------------------------

## Advances the signal clock (called by World every physics frame with game-time delta).
func advance(delta: float) -> void:
	signal_time += delta


## Nearest lane (horizontal distance). {} if none within max_dist.
func get_nearest_lane(pos: Vector3, max_dist: float = 30.0) -> Dictionary:
	if _lane_grid == null:
		return {}
	var e := _lane_grid.nearest(Vector2(pos.x, pos.z), max_dist)
	if e < 0:
		return {}
	var id := _lane_grid.eid[e]
	var lane: Dictionary = lanes[id]
	var cum: PackedFloat32Array = lane["cum"]
	var pts: PackedVector3Array = lane["points"]
	var i := _lane_grid.eidx[e]
	var t := _lane_grid.r_t
	return {"lane_id": id, "offset": lerpf(cum[i], cum[i + 1], t), "point": pts[i].lerp(pts[i + 1], t),
			"distance": _lane_grid.r_dist}


## Transform on a lane at a distance from its start; -Z = travel direction.
func sample_lane(lane_id: int, offset: float) -> Transform3D:
	if lane_id < 0 or lane_id >= lanes.size():
		return Transform3D.IDENTITY
	var lane: Dictionary = lanes[lane_id]
	var cum: PackedFloat32Array = lane["cum"]
	var pts: PackedVector3Array = lane["points"]
	var n := pts.size()
	var o := clampf(offset, 0.0, cum[n - 1])
	var i := 0
	if n > 2:
		var lo := 0
		var hi := n - 2
		while lo < hi:
			@warning_ignore("integer_division")
			var mid := (lo + hi + 1) / 2
			if cum[mid] <= o:
				lo = mid
			else:
				hi = mid - 1
		i = lo
	var seg_len := cum[i + 1] - cum[i]
	var t := 0.0 if seg_len < 0.0001 else (o - cum[i]) / seg_len
	var dir := pts[i + 1] - pts[i]
	if dir.length_squared() < 0.000001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	return Transform3D(Basis.looking_at(dir, Vector3.UP), pts[i].lerp(pts[i + 1], t))


func get_next_lanes(lane_id: int) -> PackedInt32Array:
	if lane_id < 0 or lane_id >= lanes.size():
		return PackedInt32Array()
	return lanes[lane_id]["next"]


## 0 green, 1 yellow, 2 red for traffic leaving that lane (always 0 at unsignalised ends).
func get_signal_state(lane_id: int) -> int:
	if lane_id < 0 or lane_id >= _sig_group.size():
		return 0
	var g := _sig_group[lane_id]
	if g < 0:
		return 0
	var t := fposmod(signal_time + _sig_offset[lane_id] - float(g) * PHASE_TIME, CYCLE_TIME)
	if t < GREEN_TIME:
		return 0
	if t < GREEN_TIME + YELLOW_TIME:
		return 1
	return 2


## Seconds until the signal of that lane changes state (0 for unsignalised lanes).
func get_signal_time_left(lane_id: int) -> float:
	if lane_id < 0 or lane_id >= _sig_group.size() or _sig_group[lane_id] < 0:
		return 0.0
	var t := fposmod(signal_time + _sig_offset[lane_id] - float(_sig_group[lane_id]) * PHASE_TIME, CYCLE_TIME)
	if t < GREEN_TIME:
		return GREEN_TIME - t
	if t < GREEN_TIME + YELLOW_TIME:
		return GREEN_TIME + YELLOW_TIME - t
	return CYCLE_TIME - t


## One entry per signalised approach: {transform, lane_ids, intersection_id}. The transform stands on
## the right-hand kerb at the stop line; -Z points towards the approaching drivers.
func get_signal_heads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node: Dictionary in intersections:
		if not node["has_signal"]:
			continue
		var c: Vector3 = node["position"]
		for l: Dictionary in node["legs"]:
			var ids: PackedInt32Array = l["lanes_in"]
			if ids.is_empty():
				continue
			var d: Vector2 = l["dir"]
			var right := Geom.right_of(-d)
			var p := Vector2(c.x, c.z) + d * (float(l["trim"]) + WorldLayout.STOP_SETBACK - 0.6) + right * (float(l["hw"]) + 0.7)
			var y := c.y - WorldLayout.ROAD_LIFT + (WorldLayout.CURB_H if bool(l["sw_ccw"]) else 0.0)
			var xf := Transform3D(Basis(Vector3.UP, Geom.yaw_of(d)), Vector3(p.x, y, p.y))
			out.append({"transform": xf, "lane_ids": ids, "intersection_id": int(node["id"])})
	return out


## Smooth connection through an intersection (interior points only, without both end points).
func get_connection(from_lane: int, to_lane: int, steps: int = 6) -> PackedVector3Array:
	var out := PackedVector3Array()
	if from_lane < 0 or to_lane < 0 or from_lane >= lanes.size() or to_lane >= lanes.size():
		return out
	var pa: PackedVector3Array = lanes[from_lane]["points"]
	var pb: PackedVector3Array = lanes[to_lane]["points"]
	var a := pa[pa.size() - 1]
	var b := pb[0]
	var dist := a.distance_to(b)
	if dist < 0.5:
		return out
	var da := (a - pa[pa.size() - 2]).normalized()
	var db := (pb[1] - b).normalized()
	var c1 := a + da * dist * 0.4
	var c2 := b - db * dist * 0.4
	for s in range(1, steps):
		var t := float(s) / float(steps)
		out.append(a.bezier_interpolate(c1, c2, b, t))
	return out


func _lane_cost(id: int) -> float:
	var l: Dictionary = lanes[id]
	return float(l["length"]) / maxf(float(l["speed_limit"]), 1.0) + 1.5


## A* over lanes. Returns [src ... dst] (src == dst gives a full loop), empty if unreachable.
func _astar(src: int, dst: int) -> PackedInt32Array:
	var n := lanes.size()
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(1.0e12)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var open: Array[int] = []
	var fscore := PackedFloat32Array()
	fscore.resize(n)
	var goal: Vector3 = (lanes[dst]["points"] as PackedVector3Array)[0]
	for nx in (lanes[src]["next"] as PackedInt32Array):
		g[nx] = _lane_cost(nx)
		came[nx] = src
		var pe: PackedVector3Array = lanes[nx]["points"]
		fscore[nx] = g[nx] + pe[pe.size() - 1].distance_to(goal) / MAX_SPEED
		open.append(nx)
	while not open.is_empty():
		var bi := 0
		for i in range(1, open.size()):
			if fscore[open[i]] < fscore[open[bi]]:
				bi = i
		var cur := open[bi]
		open[bi] = open[open.size() - 1]
		open.pop_back()
		if cur == dst:
			var path := PackedInt32Array()
			path.append(dst)
			var c := came[dst]
			var guard := 0
			while c != src and c >= 0 and guard < n:
				path.append(c)
				c = came[c]
				guard += 1
			path.append(src)
			path.reverse()
			return path
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		for nx in (lanes[cur]["next"] as PackedInt32Array):
			if closed[nx] == 1:
				continue
			var cost := g[cur] + _lane_cost(nx)
			if cost < g[nx]:
				g[nx] = cost
				came[nx] = cur
				var pe: PackedVector3Array = lanes[nx]["points"]
				fscore[nx] = cost + pe[pe.size() - 1].distance_to(goal) / MAX_SPEED
				if not open.has(nx):
					open.append(nx)
	return PackedInt32Array()


## Lane ids from from_lane to to_lane (both included). Empty if there is no route.
func find_lane_route(from_lane: int, to_lane: int) -> PackedInt32Array:
	if from_lane < 0 or to_lane < 0 or from_lane >= lanes.size() or to_lane >= lanes.size():
		return PackedInt32Array()
	if from_lane == to_lane:
		return PackedInt32Array([from_lane])
	return _astar(from_lane, to_lane)


func _append_slice(out: PackedVector3Array, lane_id: int, s0: float, s1: float) -> void:
	var lane: Dictionary = lanes[lane_id]
	var cum: PackedFloat32Array = lane["cum"]
	var pts: PackedVector3Array = lane["points"]
	out.append(sample_lane(lane_id, s0).origin)
	for i in range(1, pts.size() - 1):
		if cum[i] > s0 + 0.05 and cum[i] < s1 - 0.05:
			out.append(pts[i])
	if s1 > s0 + 0.05:
		out.append(sample_lane(lane_id, s1).origin)


## Options for starting / ending a route near a point: the nearest lane plus the nearest lane of the
## opposite direction on the same road segment.
func _lane_options(pos: Vector3) -> Array:
	var res: Array = []
	var near := get_nearest_lane(pos, 700.0)
	if near.is_empty():
		return res
	res.append([int(near["lane_id"]), float(near["offset"])])
	var lane: Dictionary = lanes[int(near["lane_id"])]
	var seg: Dictionary = segments[int(lane["segment_id"])]
	var others: PackedInt32Array = seg["lanes_back"] if int(lane["direction"]) == 1 else seg["lanes_fwd"]
	var best := -1
	var best_d := 1.0e12
	var best_off := 0.0
	for id in others:
		var hit := Geom.closest(lanes[id]["pts2"], Vector2(pos.x, pos.z))
		if float(hit[0]) < best_d:
			best_d = float(hit[0])
			best = id
			best_off = minf(float(hit[1]), float(lanes[id]["length"]))
	if best >= 0:
		res.append([best, best_off])
	return res


## Drivable polyline from `from` to `to` (GPS / taxi / police). Follows lanes and intersection
## connections; empty if the road graph is empty.
func find_route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var starts := _lane_options(from)
	var ends := _lane_options(to)
	if starts.is_empty() or ends.is_empty():
		return out
	var best_route := PackedInt32Array()
	var best_cost := 1.0e12
	var best_oa := 0.0
	var best_ob := 0.0
	for s: Array in starts:
		for e: Array in ends:
			var la: int = s[0]
			var lb: int = e[0]
			var oa: float = s[1]
			var ob: float = e[1]
			var route: PackedInt32Array
			if la == lb and ob >= oa:
				route = PackedInt32Array([la])
			else:
				route = _astar(la, lb)
			if route.is_empty():
				continue
			var cost := 0.0
			for i in route.size():
				var l: Dictionary = lanes[route[i]]
				var s0 := oa if i == 0 else 0.0
				var s1 := ob if i == route.size() - 1 else float(l["length"])
				cost += maxf(s1 - s0, 0.0) / maxf(float(l["speed_limit"]), 1.0) + 1.5
			if cost < best_cost:
				best_cost = cost
				best_route = route
				best_oa = oa
				best_ob = ob
	if best_route.is_empty():
		return out
	for i in best_route.size():
		var id := best_route[i]
		var s0 := best_oa if i == 0 else 0.0
		var s1 := best_ob if i == best_route.size() - 1 else float(lanes[id]["length"])
		if i > 0:
			out.append_array(get_connection(best_route[i - 1], id))
		_append_slice(out, id, s0, s1)
	return out


## Random point on a lane whose horizontal distance to `near` is inside [min_d, max_d]. {} if none.
func random_lane_point(near: Vector3, min_d: float, max_d: float) -> Dictionary:
	if lanes.is_empty() or total_lane_length <= 0.0:
		return {}
	var rng: RandomNumberGenerator = Game.rng
	var n2 := Vector2(near.x, near.z)
	for attempt in 28:
		var r := rng.randf() * total_lane_length
		var lo := 0
		var hi := lanes.size() - 1
		while lo < hi:
			@warning_ignore("integer_division")
			var mid := (lo + hi + 1) / 2
			if _lane_start[mid] <= r:
				lo = mid
			else:
				hi = mid - 1
		var off := r - _lane_start[lo]
		var xf := sample_lane(lo, off)
		var d := Vector2(xf.origin.x, xf.origin.z).distance_to(n2)
		if d >= min_d and d <= max_d:
			return {"lane_id": lo, "offset": off, "transform": xf}
	# deterministic fallback: scan a few offsets on every lane
	var cands: Array = []
	for l: Dictionary in lanes:
		for f: float in [0.2, 0.5, 0.8]:
			var off := float(l["length"]) * f
			var xf := sample_lane(int(l["id"]), off)
			var d := Vector2(xf.origin.x, xf.origin.z).distance_to(n2)
			if d >= min_d and d <= max_d:
				cands.append([int(l["id"]), off, xf])
	if cands.is_empty():
		return {}
	var pick: Array = cands[rng.randi() % cands.size()]
	return {"lane_id": pick[0], "offset": pick[1], "transform": pick[2]}


func get_lane_length(lane_id: int) -> float:
	if lane_id < 0 or lane_id >= lanes.size():
		return 0.0
	return lanes[lane_id]["length"]


## Segment id whose corridor (carriageway) contains the point, or -1.
func get_segment_at(pos: Vector3) -> int:
	if seg_grid == null:
		return -1
	var q := Vector2(pos.x, pos.z)
	for e in seg_grid.candidates(q):
		var a := seg_grid.ea[e]
		var ab := seg_grid.eb[e] - a
		var t := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var id := seg_grid.eid[e]
		if (a + ab * t).distance_to(q) <= float(segments[id]["hw"]):
			return id
	return -1
