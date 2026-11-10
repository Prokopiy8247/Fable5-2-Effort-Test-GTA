class_name TrafficLanes
extends RefCounted
## Typed, cached copy of the WORLD RoadGraph lane data for the traffic module, plus the junction
## connection paths (lane end -> next lane start), turn directions and movement conflict tests.
##
## Built once from `Game.world.roads` (soft dependency: the RoadGraph is accessed untyped, never by
## its class_name). Everything here is read-only after build(); connection / conflict records are
## computed lazily and cached (a few hundred entries at most).

const KIND_ARTERIAL := 0
const KIND_STREET := 1
const KIND_ALLEY := 2
const KIND_DIRT := 3
const KIND_OTHER := 4
const CONN_STEPS := 8
const SIDESWIPE_DIST := 2.1      ## two junction paths closer than this conflict even if they do not cross

var roads: Variant = null        ## the RoadGraph (WORLD module) - untyped on purpose
var count: int = 0
var pts: Array[PackedVector3Array] = []
var cum: Array[PackedFloat32Array] = []
var length := PackedFloat32Array()
var limit := PackedFloat32Array()
var next: Array[PackedInt32Array] = []
var end_node := PackedInt32Array()
var start_node := PackedInt32Array()
var sig := PackedInt32Array()            ## signal group of the lane end (-1 = unsignalised)
var yields := PackedByteArray()          ## 1 = minor approach of a priority junction
var kind := PackedInt32Array()
var seg := PackedInt32Array()
var index := PackedInt32Array()          ## 0 = next to the centre line
var dirn := PackedInt32Array()           ## +1 along the segment, -1 against
var lanes_per_dir := PackedInt32Array()
var adjacent := PackedInt32Array()       ## same segment + direction, neighbouring index (-1 = none)
var opposite: Array[PackedInt32Array] = []   ## lanes of the same segment in the other direction
var parking := PackedByteArray()         ## the segment has a kerb parking lane
var dead_end := PackedByteArray()        ## the lane ends at a one-leg node (U-turn)
var spawnable := PackedByteArray()       ## ambient traffic may be spawned on this lane

var node_count: int = 0
var node_pos := PackedVector3Array()
var node_signal := PackedByteArray()
var node_radius := PackedFloat32Array()
var node_legs := PackedInt32Array()

var _conn: Dictionary = {}               ## from * 4096 + to -> [pts3, cum, length, turn, pts2]
var _conflict: Dictionary = {}           ## pair key -> bool


func build(p_roads: Variant) -> bool:
	roads = p_roads
	if roads == null:
		return false
	var lanes: Array = roads.get("lanes")
	var segs: Array = roads.get("segments")
	var nodes: Array = roads.get("intersections")
	if lanes == null or lanes.is_empty():
		return false
	count = lanes.size()
	pts.resize(count)
	cum.resize(count)
	next.resize(count)
	opposite.resize(count)
	length.resize(count)
	limit.resize(count)
	end_node.resize(count)
	start_node.resize(count)
	sig.resize(count)
	yields.resize(count)
	kind.resize(count)
	seg.resize(count)
	index.resize(count)
	dirn.resize(count)
	lanes_per_dir.resize(count)
	adjacent.resize(count)
	parking.resize(count)
	dead_end.resize(count)
	spawnable.resize(count)

	node_count = nodes.size()
	node_pos.resize(node_count)
	node_signal.resize(node_count)
	node_radius.resize(node_count)
	node_legs.resize(node_count)
	for n: Dictionary in nodes:
		var k := int(n["id"])
		node_pos[k] = n["position"]
		node_signal[k] = 1 if bool(n["has_signal"]) else 0
		node_radius[k] = float(n["radius"])
		node_legs[k] = (n["legs"] as Array).size()

	for l: Dictionary in lanes:
		var i := int(l["id"])
		pts[i] = l["points"]
		cum[i] = l["cum"]
		length[i] = float(l["length"])
		limit[i] = maxf(float(l["speed_limit"]), 4.0)
		next[i] = l["next"]
		end_node[i] = int(l["end_intersection"])
		start_node[i] = int(l.get("start_intersection", -1))
		sig[i] = int(l.get("signal_group", -1))
		yields[i] = 1 if bool(l.get("yield", false)) else 0
		index[i] = int(l.get("index", 0))
		dirn[i] = int(l.get("direction", 1))
		seg[i] = int(l["segment_id"])
		match str(l.get("kind", "street")):
			"arterial":
				kind[i] = KIND_ARTERIAL
			"street":
				kind[i] = KIND_STREET
			"alley":
				kind[i] = KIND_ALLEY
			"dirt":
				kind[i] = KIND_DIRT
			_:
				kind[i] = KIND_OTHER
		adjacent[i] = -1
		dead_end[i] = 1 if (end_node[i] >= 0 and end_node[i] < node_count and node_legs[end_node[i]] <= 1) else 0

	for s: Dictionary in segs:
		var fwd: PackedInt32Array = s.get("lanes_fwd", PackedInt32Array())
		var back: PackedInt32Array = s.get("lanes_back", PackedInt32Array())
		var park := bool(s.get("parking", false))
		var lpd := int(s.get("lanes_per_dir", 1))
		for grp: PackedInt32Array in [fwd, back]:
			var other: PackedInt32Array = back if grp == fwd else fwd
			for a in grp:
				lanes_per_dir[a] = lpd
				parking[a] = 1 if park else 0
				opposite[a] = other
				for b in grp:
					if a != b and absi(index[a] - index[b]) == 1:
						adjacent[a] = b

	for i in count:
		# dead-end feeders, dirt tracks and very short pieces are not used to spawn ambient traffic
		var ok := kind[i] <= KIND_ALLEY and length[i] > 18.0 and dead_end[i] == 0
		if ok and start_node[i] >= 0 and start_node[i] < node_count and node_legs[start_node[i]] <= 1:
			ok = false
		spawnable[i] = 1 if ok else 0
	return true


# ---------------------------------------------------------------------------------------------
# polyline sampling
# ---------------------------------------------------------------------------------------------

static func poly_index(c: PackedFloat32Array, s: float) -> int:
	var n := c.size()
	if n <= 2:
		return 0
	var lo := 0
	var hi := n - 2
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi + 1) / 2
		if c[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return lo


## Point at distance s along a polyline (extrapolated past both ends along the end directions).
static func poly_point(p: PackedVector3Array, c: PackedFloat32Array, s: float) -> Vector3:
	var n := p.size()
	if n == 0:
		return Vector3.ZERO
	if n == 1:
		return p[0]
	if s <= 0.0:
		var d0 := p[1] - p[0]
		var l0 := d0.length()
		return p[0] + (d0 / l0 * s if l0 > 0.0001 else Vector3.ZERO)
	var total := c[n - 1]
	if s >= total:
		var d1 := p[n - 1] - p[n - 2]
		var l1 := d1.length()
		return p[n - 1] + (d1 / l1 * (s - total) if l1 > 0.0001 else Vector3.ZERO)
	var i := poly_index(c, s)
	var seg_len := c[i + 1] - c[i]
	var t := 0.0 if seg_len < 0.0001 else (s - c[i]) / seg_len
	return p[i].lerp(p[i + 1], t)


static func poly_dir(p: PackedVector3Array, c: PackedFloat32Array, s: float) -> Vector3:
	var n := p.size()
	if n < 2:
		return Vector3.FORWARD
	var i := clampi(poly_index(c, s), 0, n - 2)
	var d := p[i + 1] - p[i]
	d.y = 0.0
	if d.length_squared() < 0.000001:
		return Vector3.FORWARD
	return d.normalized()


func lane_point(lane: int, s: float) -> Vector3:
	return poly_point(pts[lane], cum[lane], s)


func lane_dir(lane: int, s: float) -> Vector3:
	return poly_dir(pts[lane], cum[lane], s)


func lane_end_dir(lane: int) -> Vector3:
	var p := pts[lane]
	var d := p[p.size() - 1] - p[p.size() - 2]
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD


func lane_start_dir(lane: int) -> Vector3:
	var p := pts[lane]
	var d := p[1] - p[0]
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD


## Signal state of the lane end: 0 green, 1 yellow, 2 red (0 for unsignalised lanes).
func signal_state(lane: int) -> int:
	if lane < 0 or lane >= count or sig[lane] < 0 or roads == null:
		return 0
	return int(roads.get_signal_state(lane))


func signal_time_left(lane: int) -> float:
	if lane < 0 or lane >= count or sig[lane] < 0 or roads == null or not roads.has_method("get_signal_time_left"):
		return 0.0
	return float(roads.get_signal_time_left(lane))


## Junction that needs right-of-way control (3+ legs).
func is_junction(node: int) -> bool:
	return node >= 0 and node < node_count and node_legs[node] >= 3


# ---------------------------------------------------------------------------------------------
# junction connections
# ---------------------------------------------------------------------------------------------

## [pts3: PackedVector3Array, cum: PackedFloat32Array, length: float, turn: int (-1 left, 0 straight,
## 1 right, 2 U-turn), pts2: PackedVector2Array]. Length 0 when the lanes join directly.
func get_conn(from_lane: int, to_lane: int) -> Array:
	var key := from_lane * 4096 + to_lane
	var rec: Variant = _conn.get(key, null)
	if rec != null:
		return rec
	var p3 := PackedVector3Array()
	var c := PackedFloat32Array()
	var p2 := PackedVector2Array()
	var total := 0.0
	var turn := 0
	if from_lane >= 0 and to_lane >= 0 and from_lane < count and to_lane < count:
		var a := pts[from_lane][pts[from_lane].size() - 1]
		var b := pts[to_lane][0]
		var da := lane_end_dir(from_lane)
		var db := lane_start_dir(to_lane)
		var dot := da.dot(db)
		var cross := da.x * db.z - da.z * db.x
		if dot < -0.7:
			turn = 2
		elif dot > 0.7:
			turn = 0
		else:
			turn = 1 if cross > 0.0 else -1
		if a.distance_to(b) >= 0.5:
			p3.append(a)
			var mid: Variant = roads.get_connection(from_lane, to_lane, CONN_STEPS) if roads != null and roads.has_method("get_connection") else PackedVector3Array()
			if mid is PackedVector3Array:
				p3.append_array(mid)
			p3.append(b)
			c.resize(p3.size())
			for i in range(1, p3.size()):
				total += p3[i].distance_to(p3[i - 1])
				c[i] = total
			for q in p3:
				p2.append(Vector2(q.x, q.z))
	var out: Array = [p3, c, total, turn, p2]
	_conn[key] = out
	return out


func conn_turn(from_lane: int, to_lane: int) -> int:
	return int(get_conn(from_lane, to_lane)[3])


func conn_length(from_lane: int, to_lane: int) -> float:
	return float(get_conn(from_lane, to_lane)[2])


## True when the two junction movements (a_from -> a_to) and (b_from -> b_to) can collide.
func movements_conflict(a_from: int, a_to: int, b_from: int, b_to: int) -> bool:
	if a_from == b_from:
		return false          # same approach lane: handled by car following
	if a_to == b_to:
		return true           # merge into the same lane
	var ka := a_from * 4096 + a_to
	var kb := b_from * 4096 + b_to
	var key := Vector2i(mini(ka, kb), maxi(ka, kb))
	var cached: Variant = _conflict.get(key, null)
	if cached != null:
		return bool(cached)
	var pa: PackedVector2Array = get_conn(a_from, a_to)[4]
	var pb: PackedVector2Array = get_conn(b_from, b_to)[4]
	var res := false
	if pa.size() >= 2 and pb.size() >= 2:
		res = _polylines_close(pa, pb, SIDESWIPE_DIST)
	_conflict[key] = res
	return res


## Smallest horizontal distance from a point to the junction path of a movement (INF if none).
func distance_to_movement(from_lane: int, to_lane: int, p: Vector3) -> float:
	var pa: PackedVector2Array = get_conn(from_lane, to_lane)[4]
	if pa.size() < 2:
		return INF
	var q := Vector2(p.x, p.z)
	var best := INF
	for i in range(1, pa.size()):
		best = minf(best, _pt_seg(q, pa[i - 1], pa[i]))
	return best


static func _pt_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _seg_cross(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> bool:
	var r := a1 - a0
	var s := b1 - b0
	var den := r.cross(s)
	if absf(den) < 0.000001:
		return false
	var t := (b0 - a0).cross(s) / den
	var u := (b0 - a0).cross(r) / den
	return t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0


static func _polylines_close(pa: PackedVector2Array, pb: PackedVector2Array, dist: float) -> bool:
	for i in range(1, pa.size()):
		for j in range(1, pb.size()):
			if _seg_cross(pa[i - 1], pa[i], pb[j - 1], pb[j]):
				return true
	# side-swipe: vertices of one path closer than `dist` to the other path (end points excluded,
	# they lie on lanes that are already separated by the road layout)
	for i in range(1, pa.size() - 1):
		for j in range(1, pb.size()):
			if _pt_seg(pa[i], pb[j - 1], pb[j]) < dist:
				return true
	for j in range(1, pb.size() - 1):
		for i in range(1, pa.size()):
			if _pt_seg(pb[j], pa[i - 1], pa[i]) < dist:
				return true
	return false
