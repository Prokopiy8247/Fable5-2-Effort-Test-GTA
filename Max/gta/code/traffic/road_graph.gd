class_name RoadGraph
extends RefCounted
## Lane-level road graph derived from CityLayout: driving lanes (right-hand traffic),
## junction connectors with conflict sets, signal phases, nearest-lane queries and
## routing (used by civilian traffic, police pursuit, taxis and the GPS).

class Lane:
	extends RefCounted
	var id := 0
	var pts := PackedVector3Array()
	var cum := PackedFloat32Array()
	var length := 0.0
	var next: Array[int] = []
	var prev: Array[int] = []
	var road := -1
	var node_start := ""
	var node_end := ""
	var node := ""               # connectors: owning junction
	var is_connector := false
	var speed := 11.0
	var axis := 0                # 0 = travelling north-south at its end, 1 = east-west
	var turn := 0                # connectors: -1 left, 0 straight, 1 right
	var conflicts: Array[int] = []
	var lane_index := 0
	var lane_count := 1
	var sibling := -1            # neighbouring lane in the same direction (lane changes)
	var kind := "street"

const GREEN := 9.0
const YELLOW := 2.0
const ALL_RED := 1.5
const CYCLE := (GREEN + YELLOW + ALL_RED) * 2.0
const STOP_SETBACK := 5.6      # stop line distance before the junction box

var lanes: Array[Lane] = []
var node_in: Dictionary = {}     # node id -> Array[int] incoming lanes
var node_out: Dictionary = {}    # node id -> Array[int] outgoing lanes
var node_conn: Dictionary = {}   # node id -> Array[int] connectors
var node_signal: Dictionary = {} # node id -> bool
var node_offset: Dictionary = {} # node id -> phase offset seconds
var node_pos: Dictionary = {}
var _hash: Dictionary = {}       # Vector2i cell -> PackedInt32Array [lane, point, lane, point...]
var _layout: CityLayout

func build(layout: CityLayout) -> void:
	_layout = layout
	for id in layout.nodes.keys():
		node_in[id] = []
		node_out[id] = []
		node_conn[id] = []
		var nd: Dictionary = layout.nodes[id]
		node_signal[id] = nd["signal"]
		node_pos[id] = nd["pos"]
		var p: Vector3 = nd["pos"]
		node_offset[id] = fposmod(absf(p.x) * 0.05 + absf(p.z) * 0.07, CYCLE)
	for road in layout.roads:
		if not road["traffic"]:
			continue
		_build_road_lanes(road)
	for id in layout.nodes.keys():
		_build_connectors(id)
	_build_hash()

static func lane_offsets(kind: String) -> Array:
	match kind:
		"arterial": return [2.6, 6.3]
		"hill": return [1.85]
	return [1.85]

func _new_lane() -> Lane:
	var l := Lane.new()
	l.id = lanes.size()
	lanes.append(l)
	return l

static func _finish(l: Lane) -> void:
	l.cum.resize(l.pts.size())
	var total := 0.0
	l.cum[0] = 0.0
	for i in range(1, l.pts.size()):
		total += l.pts[i - 1].distance_to(l.pts[i])
		l.cum[i] = total
	l.length = total

func _build_road_lanes(road: Dictionary) -> void:
	var offs := lane_offsets(road["kind"])
	var src: PackedVector3Array = road["pts"]
	for dir in 2:
		var base := src.duplicate()
		if dir == 1:
			base.reverse()
		var made: Array[Lane] = []
		for k in offs.size():
			var l := _new_lane()
			l.road = road["id"]
			l.kind = road["kind"]
			l.speed = road["speed"]
			l.lane_index = k
			l.lane_count = offs.size()
			l.node_start = road["a"] if dir == 0 else road["b"]
			l.node_end = road["b"] if dir == 0 else road["a"]
			var n := base.size()
			for i in n:
				var t: Vector3
				if i == 0:
					t = base[1] - base[0]
				elif i == n - 1:
					t = base[n - 1] - base[n - 2]
				else:
					t = base[i + 1] - base[i - 1]
				t.y = 0.0
				t = t.normalized()
				var r := Vector3(-t.z, 0.0, t.x)
				l.pts.append(base[i] + r * float(offs[k]) + Vector3(0, 0.02, 0))
			_finish(l)
			var d_end := (l.pts[l.pts.size() - 1] - l.pts[l.pts.size() - 2]).normalized()
			l.axis = 0 if absf(d_end.z) >= absf(d_end.x) else 1
			(node_in[l.node_end] as Array).append(l.id)
			(node_out[l.node_start] as Array).append(l.id)
			made.append(l)
		if made.size() == 2:
			made[0].sibling = made[1].id
			made[1].sibling = made[0].id

func _lane_start_dir(l: Lane) -> Vector3:
	return (l.pts[1] - l.pts[0]).normalized()

func _lane_end_dir(l: Lane) -> Vector3:
	var n := l.pts.size()
	return (l.pts[n - 1] - l.pts[n - 2]).normalized()

func _build_connectors(node_id: String) -> void:
	var ins: Array = node_in[node_id]
	var outs: Array = node_out[node_id]
	var arms := 0
	var nd: Dictionary = _layout.nodes[node_id]
	for k in nd["arms"].keys():
		if nd["arms"][k] >= 0 and _layout.roads[nd["arms"][k]]["traffic"]:
			arms += 1
	var made: Array[Lane] = []
	for li in ins:
		var lin: Lane = lanes[li]
		var d_in := _lane_end_dir(lin)
		for lo in outs:
			var lout: Lane = lanes[lo]
			if lout.road == lin.road:
				continue
			var d_out := _lane_start_dir(lout)
			var cross := d_in.x * d_out.z - d_in.z * d_out.x
			var dot := d_in.dot(d_out)
			var turn := 0
			if dot < 0.6:
				turn = 1 if cross > 0.0 else -1
			if arms > 2:
				# lane discipline on multi-lane approaches / exits
				if turn == 1:
					if lin.lane_index != lin.lane_count - 1 or lout.lane_index != lout.lane_count - 1:
						continue
				elif turn == -1:
					if lin.lane_index != 0 or lout.lane_index != 0:
						continue
				else:
					if mini(lin.lane_index, lout.lane_count - 1) != lout.lane_index:
						continue
			var c := _new_lane()
			c.is_connector = true
			c.node = node_id
			c.turn = turn
			c.kind = "connector"
			c.axis = lin.axis
			c.road = -1
			c.speed = minf(lin.speed, lout.speed) if turn == 0 else 6.2
			var p0 := lin.pts[lin.pts.size() - 1]
			var p3 := lout.pts[0]
			if turn == 0:
				c.pts = PackedVector3Array([p0, p0.lerp(p3, 0.5), p3])
			else:
				var h := p0.distance_to(p3) * 0.42
				var p1 := p0 + d_in * h
				var p2 := p3 - d_out * h
				for s in 9:
					var t := float(s) / 8.0
					var mt := 1.0 - t
					c.pts.append(p0 * mt * mt * mt + p1 * 3.0 * mt * mt * t + p2 * 3.0 * mt * t * t + p3 * t * t * t)
			_finish(c)
			c.prev = [lin.id]
			c.next = [lout.id]
			lin.next.append(c.id)
			lout.prev.append(c.id)
			(node_conn[node_id] as Array).append(c.id)
			made.append(c)
	# conflict sets
	for i in made.size():
		for j in range(i + 1, made.size()):
			var a := made[i]
			var b := made[j]
			if a.prev[0] == b.prev[0]:
				continue
			var hit := a.next[0] == b.next[0]
			if not hit:
				for pa in a.pts:
					for pb in b.pts:
						if pa.distance_squared_to(pb) < 6.2:
							hit = true
							break
					if hit:
						break
			if hit:
				a.conflicts.append(b.id)
				b.conflicts.append(a.id)

func _build_hash() -> void:
	_hash.clear()
	for l in lanes:
		for i in l.pts.size():
			var p := l.pts[i]
			var key := Vector2i(int(floor(p.x / 20.0)), int(floor(p.z / 20.0)))
			if not _hash.has(key):
				_hash[key] = PackedInt32Array()
			var arr: PackedInt32Array = _hash[key]
			arr.append(l.id)
			arr.append(i)
			_hash[key] = arr
		# long straight lanes: add intermediate hash samples
		if l.pts.size() == 2 and l.length > 20.0:
			var steps := int(l.length / 15.0)
			for s in range(1, steps):
				var p2 := l.pts[0].lerp(l.pts[1], float(s) / float(steps))
				var key2 := Vector2i(int(floor(p2.x / 20.0)), int(floor(p2.z / 20.0)))
				if not _hash.has(key2):
					_hash[key2] = PackedInt32Array()
				var arr2: PackedInt32Array = _hash[key2]
				arr2.append(l.id)
				arr2.append(0)
				_hash[key2] = arr2

# ---------------------------------------------------------------- sampling
func sample(lane_id: int, s: float) -> Vector3:
	var l := lanes[lane_id]
	if s <= 0.0:
		return l.pts[0]
	if s >= l.length:
		return l.pts[l.pts.size() - 1]
	var n := l.pts.size()
	if n == 2:
		return l.pts[0].lerp(l.pts[1], s / l.length)
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if l.cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := l.cum[hi] - l.cum[lo]
	return l.pts[lo].lerp(l.pts[hi], (s - l.cum[lo]) / maxf(seg, 0.0001))

func direction(lane_id: int, s: float) -> Vector3:
	var a := sample(lane_id, maxf(s - 0.5, 0.0))
	var b := sample(lane_id, minf(s + 0.5, lanes[lane_id].length))
	var d := b - a
	if d.length_squared() < 0.0001:
		var l := lanes[lane_id]
		return (l.pts[l.pts.size() - 1] - l.pts[0]).normalized()
	return d.normalized()

## Closest point on one lane: returns [s, distance].
func project(lane_id: int, pos: Vector3) -> Array:
	var l := lanes[lane_id]
	var best_d := 1.0e18
	var best_s := 0.0
	for i in range(l.pts.size() - 1):
		var a := l.pts[i]
		var b := l.pts[i + 1]
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := a + ab * t
		var d := q.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best_s = l.cum[i] + ab.length() * t
	return [best_s, sqrt(best_d)]

## Nearest lane to a world position. heading (optional) prefers lanes going that way.
## Returns {} or {"lane": id, "s": float, "dist": float}.
func nearest(pos: Vector3, max_dist := 40.0, heading := Vector3.ZERO, allow_connectors := false) -> Dictionary:
	var cx := int(floor(pos.x / 20.0))
	var cz := int(floor(pos.z / 20.0))
	var reach := int(ceil(max_dist / 20.0))
	var tested := {}
	var best := {}
	var best_score := 1.0e18
	for ox in range(-reach, reach + 1):
		for oz in range(-reach, reach + 1):
			var key := Vector2i(cx + ox, cz + oz)
			if not _hash.has(key):
				continue
			var arr: PackedInt32Array = _hash[key]
			var i := 0
			while i < arr.size():
				var lid := arr[i]
				i += 2
				if tested.has(lid):
					continue
				tested[lid] = true
				var l := lanes[lid]
				if l.is_connector and not allow_connectors:
					continue
				var pr := project(lid, pos)
				var d: float = pr[1]
				if d > max_dist:
					continue
				var score := d
				if heading != Vector3.ZERO:
					var dirv := direction(lid, pr[0])
					score += (1.0 - dirv.dot(heading)) * 6.0
				if score < best_score:
					best_score = score
					best = {"lane": lid, "s": pr[0], "dist": d}
	return best

# ---------------------------------------------------------------- signals
## 0 = green, 1 = yellow, 2 = red for traffic arriving on `axis` at `node_id`.
func signal_state(node_id: String, axis: int, time_s: float) -> int:
	if not node_signal.get(node_id, false):
		return 0
	var t := fposmod(time_s + float(node_offset[node_id]), CYCLE)
	var half := CYCLE * 0.5
	if axis == 1:
		t = fposmod(t - half, CYCLE)
	if t < GREEN:
		return 0
	if t < GREEN + YELLOW:
		return 1
	return 2

# ---------------------------------------------------------------- routing
## Dijkstra over lanes. Returns lane ids from `from_lane` to `to_lane` (inclusive) or [].
func route(from_lane: int, to_lane: int) -> PackedInt32Array:
	if from_lane == to_lane:
		return PackedInt32Array([from_lane])
	var dist := {from_lane: 0.0}
	var came := {}
	var open: Array = [[0.0, from_lane]]
	var target_pos := lanes[to_lane].pts[0]
	while not open.is_empty():
		# small graphs: linear pop of the best entry is fine
		var bi := 0
		for i in range(1, open.size()):
			if open[i][0] < open[bi][0]:
				bi = i
		var cur: Array = open[bi]
		open.remove_at(bi)
		var cid: int = cur[1]
		if cid == to_lane:
			break
		var cl := lanes[cid]
		var base: float = dist[cid]
		for nx in cl.next:
			var nl := lanes[nx]
			var nd := base + cl.length / maxf(cl.speed, 1.0)
			if not dist.has(nx) or nd < float(dist[nx]):
				dist[nx] = nd
				came[nx] = cid
				var hcost := nl.pts[nl.pts.size() - 1].distance_to(target_pos) / 20.0
				open.append([nd + hcost, nx])
	if not came.has(to_lane):
		return PackedInt32Array()
	var out := PackedInt32Array()
	var c := to_lane
	while true:
		out.append(c)
		if c == from_lane:
			break
		c = came[c]
	out.reverse()
	return out

## Route between two world positions as a polyline (GPS line, taxi, police dispatch).
func route_points(from: Vector3, to: Vector3, heading := Vector3.ZERO) -> PackedVector3Array:
	var a := nearest(from, 80.0, heading)
	var b := nearest(to, 80.0)
	var out := PackedVector3Array()
	if a.is_empty() or b.is_empty():
		return out
	var ids := route(a["lane"], b["lane"])
	if ids.is_empty():
		return out
	for k in ids.size():
		var l := lanes[ids[k]]
		var s0 := float(a["s"]) if k == 0 else 0.0
		var s1 := float(b["s"]) if k == ids.size() - 1 else l.length
		if ids.size() == 1 and s1 < s0:
			s1 = l.length
		out.append(sample(l.id, s0))
		for i in l.pts.size():
			if l.cum[i] > s0 + 0.5 and l.cum[i] < s1 - 0.5:
				out.append(l.pts[i])
		out.append(sample(l.id, s1))
	return out

func random_lane(rng: RandomNumberGenerator, include_hill := true) -> int:
	for attempt in 30:
		var l := lanes[rng.randi() % lanes.size()]
		if l.is_connector:
			continue
		if not include_hill and l.kind == "hill":
			continue
		return l.id
	return 0
