class_name CityLayout
extends RefCounted
## Deterministic description of Vesper Bay (≈ 600 × 600 m): road network, junctions,
## city blocks, special zones. Pure data — meshes, colliders, traffic lanes, the minimap
## and the GPS are all derived from this one source of truth.
##
## Axes: +X east, +Z south. Column lines A..F run north-south, row lines 1..6 east-west.

const COL := {"A": -230.0, "B": -140.0, "C": -50.0, "D": 40.0, "E": 130.0, "F": 205.0}
const ROW := {"1": -230.0, "2": -140.0, "3": -50.0, "4": 40.0, "5": 130.0, "6": 195.0}
const STREET_HW := 5.5        # carriageway half width of a normal street
const ARTERIAL_HW := 9.0      # Bayline Avenue (row 6)
const HILL_HW := 4.0
const SIDEWALK := 3.5
const CURB_H := 0.15
const CORNER_R := 3.0

const COL_NAMES := {"A": "Palm Row", "B": "Orchid St", "C": "Meridian St", "D": "Vesper Blvd", "E": "Foundry Ave", "F": "Airfield Rd"}
const ROW_NAMES := {"1": "Summit Ave", "2": "Lookout Ave", "3": "Mercer St", "4": "Coral Way", "5": "Dune St", "6": "Bayline Avenue"}

# which rows each column passes through (north -> south) and columns per row (west -> east)
const COL_NODES := {"A": ["3", "4", "5", "6"], "B": ["3", "4", "5"], "C": ["1", "2", "3", "4", "5"],
	"D": ["1", "2", "3", "4", "5", "6"], "E": ["1", "2", "3", "4", "5"], "F": ["1", "2", "3", "4", "5", "6"]}
const ROW_NODES := {"1": ["C", "D", "E", "F"], "2": ["C", "D", "E", "F"], "3": ["A", "B", "C", "D", "E", "F"],
	"4": ["A", "B", "C", "D", "E", "F"], "5": ["A", "B", "C", "D", "E", "F"], "6": ["A", "D", "F"]}

var nodes: Dictionary = {}      # id -> {id,pos,hx,hz,arms:{N,S,E,W -> road index or -1},signal}
var roads: Array = []           # {id,a,b,pts,hw,lanes,kind,speed,name,sidewalk,traffic,length}
var blocks: Array = []          # {id,rect,district,sides:{N,S,E,W -> bool}}
var hill_road_index := -1
var spur_pts: PackedVector3Array = PackedVector3Array()    # summit spur (drivable, no AI traffic)
var zones: Array = []           # {name, rect: Rect2}

# airfield geometry (east edge)
const AIR_X0 := 214.0
const AIR_X1 := 296.0
const AIR_Z0 := -292.0
const AIR_Z1 := 118.0
const RUNWAY_X := 262.0
const RUNWAY_HW := 11.0
const RUNWAY_Z0 := -282.0
const RUNWAY_Z1 := 104.0
const TAXI_X := 233.0
const TAXI_HW := 6.0

func _init() -> void:
	_build_nodes()
	_build_grid_roads()
	_build_hill_road()
	_build_blocks()
	_build_zones()

static func row_hw(row: String) -> float:
	return ARTERIAL_HW if row == "6" else STREET_HW

# ---------------------------------------------------------------- nodes
func _build_nodes() -> void:
	for c in COL_NODES.keys():
		for r in COL_NODES[c]:
			var id: String = c + r
			nodes[id] = {
				"id": id, "pos": Vector3(COL[c], 0.0, ROW[r]),
				"hx": STREET_HW, "hz": row_hw(r),
				"arms": {"N": -1, "S": -1, "E": -1, "W": -1},
				"signal": false, "col": c, "row": r,
			}

func _add_road(a: String, b: String, pts: PackedVector3Array, hw: float, lanes: int, kind: String,
		speed: float, road_name: String, sidewalk: bool, traffic := true) -> int:
	var length := 0.0
	for i in range(1, pts.size()):
		length += pts[i - 1].distance_to(pts[i])
	var idx := roads.size()
	roads.append({"id": idx, "a": a, "b": b, "pts": pts, "hw": hw, "lanes": lanes, "kind": kind,
		"speed": speed, "name": road_name, "sidewalk": sidewalk, "traffic": traffic, "length": length})
	return idx

func _build_grid_roads() -> void:
	# north-south segments
	for c in COL_NODES.keys():
		var rows: Array = COL_NODES[c]
		for i in range(rows.size() - 1):
			var na: Dictionary = nodes[c + rows[i]]
			var nb: Dictionary = nodes[c + rows[i + 1]]
			var p0: Vector3 = na["pos"] + Vector3(0, 0, na["hz"])
			var p1: Vector3 = nb["pos"] - Vector3(0, 0, nb["hz"])
			var idx := _add_road(na["id"], nb["id"], PackedVector3Array([p0, p1]), STREET_HW, 1, "street", 11.5, COL_NAMES[c], true)
			na["arms"]["S"] = idx
			nb["arms"]["N"] = idx
	# east-west segments
	for r in ROW_NODES.keys():
		var cols: Array = ROW_NODES[r]
		var arterial: bool = r == "6"
		for i in range(cols.size() - 1):
			var na: Dictionary = nodes[cols[i] + r]
			var nb: Dictionary = nodes[cols[i + 1] + r]
			var p0: Vector3 = na["pos"] + Vector3(na["hx"], 0, 0)
			var p1: Vector3 = nb["pos"] - Vector3(nb["hx"], 0, 0)
			var idx := _add_road(na["id"], nb["id"], PackedVector3Array([p0, p1]),
				ARTERIAL_HW if arterial else STREET_HW, 2 if arterial else 1,
				"arterial" if arterial else "street", 19.0 if arterial else 11.5, ROW_NAMES[r], true)
			na["arms"]["E"] = idx
			nb["arms"]["W"] = idx
	# traffic signals at the busier junctions (all four-way grid crossings + the arterial T)
	for id in nodes.keys():
		var n: Dictionary = nodes[id]
		var count := 0
		for k in n["arms"].keys():
			if n["arms"][k] >= 0:
				count += 1
		n["signal"] = count == 4 or id == "D6"

# ---------------------------------------------------------------- Lookout Hill road
const HILL_CTRL := [
	Vector2(-55.5, -140.0), Vector2(-80.0, -140.0), Vector2(-105.0, -146.0), Vector2(-128.0, -160.0),
	Vector2(-140.0, -185.0), Vector2(-142.0, -212.0), Vector2(-160.0, -238.0), Vector2(-190.0, -250.0),
	Vector2(-222.0, -242.0), Vector2(-244.0, -218.0), Vector2(-250.0, -190.0), Vector2(-240.0, -160.0),
	Vector2(-218.0, -138.0), Vector2(-190.0, -122.0), Vector2(-165.0, -105.0), Vector2(-148.0, -85.0),
	Vector2(-140.0, -70.0), Vector2(-140.0, -55.5),
]
const SPUR_CTRL := [Vector2(-250.0, -190.0), Vector2(-236.0, -186.0), Vector2(-222.0, -189.0), Vector2(-209.0, -193.0), Vector2(-199.0, -195.0)]

static func _spline(ctrl: Array, step: float) -> PackedVector2Array:
	# centripetal-ish Catmull-Rom through the control points, resampled every `step` metres
	var dense := PackedVector2Array()
	var n := ctrl.size()
	for i in range(n - 1):
		var p0: Vector2 = ctrl[maxi(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(i + 2, n - 1)]
		if i == 0:
			p0 = p1 + (p1 - p2)
		if i == n - 2:
			p3 = p2 + (p2 - p1)
		for k in 16:
			var t := float(k) / 16.0
			var t2 := t * t
			var t3 := t2 * t
			dense.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	dense.append(ctrl[n - 1])
	# resample at constant arc length
	var out := PackedVector2Array([dense[0]])
	var acc := 0.0
	for i in range(1, dense.size()):
		var a := dense[i - 1]
		var b := dense[i]
		var seg := a.distance_to(b)
		while acc + seg >= step:
			var t := (step - acc) / seg
			a = a.lerp(b, t)
			out.append(a)
			seg = a.distance_to(b)
			acc = 0.0
		acc += seg
	if out[out.size() - 1].distance_to(dense[dense.size() - 1]) > 0.3:
		out.append(dense[dense.size() - 1])
	return out

static func _profile(path: PackedVector2Array, pin_start: bool, pin_end: bool, end_h := 0.0) -> PackedVector3Array:
	# road elevation = smoothed hill dome along the path
	var n := path.size()
	var hs := PackedFloat32Array()
	hs.resize(n)
	for i in n:
		hs[i] = Terrain.dome(path[i].x, path[i].y)
	if pin_end and end_h > 0.0:
		hs[n - 1] = end_h
	for pass_i in 10:
		var tmp := hs.duplicate()
		for i in range(1, n - 1):
			tmp[i] = (hs[i - 1] + hs[i] * 2.0 + hs[i + 1]) * 0.25
		if pin_start:
			tmp[0] = hs[0]
		if pin_end:
			tmp[n - 1] = hs[n - 1]
		hs = tmp
	var out := PackedVector3Array()
	for i in n:
		out.append(Vector3(path[i].x, hs[i], path[i].y))
	return out

func _build_hill_road() -> void:
	var path := _spline(HILL_CTRL, 2.0)
	var pts := _profile(path, true, true)
	# keep the first/last metres perfectly level with the junctions
	for i in pts.size():
		var dist_start := float(i) * 2.0
		var dist_end := float(pts.size() - 1 - i) * 2.0
		var k := minf(smoothstep(4.0, 22.0, dist_start), smoothstep(4.0, 22.0, dist_end))
		pts[i].y *= k
	hill_road_index = _add_road("C2", "B3", pts, HILL_HW, 1, "hill", 10.0, "Lookout Hill Rd", false)
	nodes["C2"]["arms"]["W"] = hill_road_index
	nodes["B3"]["arms"]["N"] = hill_road_index
	nodes["C2"]["signal"] = true
	nodes["B3"]["signal"] = true
	Terrain.clear_roads()
	Terrain.add_road(pts, HILL_HW + 1.0)
	# summit spur: starts at the hill road's height near the west side and climbs to the top plateau
	var spath := _spline(SPUR_CTRL, 2.0)
	var start_h := 0.0
	var best := 1.0e9
	for p in pts:
		var d := Vector2(p.x, p.z).distance_to(spath[0])
		if d < best:
			best = d
			start_h = p.y
	spur_pts = PackedVector3Array()
	var top_h := Terrain.PEAK_H - 0.4
	for i in spath.size():
		var t := float(i) / float(spath.size() - 1)
		spur_pts.append(Vector3(spath[i].x, lerpf(start_h, top_h, smoothstep(0.0, 1.0, t)), spath[i].y))
	Terrain.add_road(spur_pts, 3.6)
	# flat summit plateau for the viewpoint / radio tower / parking
	var plateau := PackedVector3Array()
	for a in 16:
		var ang := TAU * float(a) / 16.0
		for r: float in [0.0, 6.0, 12.0]:
			plateau.append(Vector3(Terrain.PEAK.x + cos(ang) * r, top_h, Terrain.PEAK.y + sin(ang) * r))
	Terrain.add_road(plateau, 5.0)

# ---------------------------------------------------------------- blocks
func _add_block(id: String, x0: float, x1: float, z0: float, z1: float, district: String, sides: String) -> void:
	blocks.append({"id": id, "rect": Rect2(x0, z0, x1 - x0, z1 - z0), "district": district,
		"sides": {"N": sides.contains("N"), "S": sides.contains("S"), "E": sides.contains("E"), "W": sides.contains("W")}})

func _build_blocks() -> void:
	var g := STREET_HW + SIDEWALK   # 9.0 : centre line to lot line
	var ga := ARTERIAL_HW + SIDEWALK
	var xa: float = COL["A"]; var xb: float = COL["B"]; var xc: float = COL["C"]
	var xd: float = COL["D"]; var xe: float = COL["E"]; var xf: float = COL["F"]
	var z1: float = ROW["1"]; var z2: float = ROW["2"]; var z3: float = ROW["3"]
	var z4: float = ROW["4"]; var z5: float = ROW["5"]; var z6: float = ROW["6"]
	var kx := AIR_X0 - SIDEWALK   # 210.5 : east kerb line of Airfield Rd
	# north strip (backs onto the map edge)
	_add_block("N_a", xc - g, xd, -300.0, z1 - g, "downtown", "S")
	_add_block("N_b", xd, xe, -300.0, z1 - g, "downtown", "S")
	_add_block("N_c", xe, kx, -300.0, z1 - g, "industrial", "S")
	# sidewalk-only strips where a street borders the hill (zero lot area)
	_add_block("H_c1", xc - g, xc - g, z1 - STREET_HW, z2 - g, "verge", "ES")
	_add_block("H_c2", xc - g, xc - g, z2 + g, z3 - g, "verge", "EN")
	_add_block("H_r3a", xa - g, xb - g, z3 - g, z3 - g, "verge", "SE")
	_add_block("H_r3b", xb + g, xc - g, z3 - g, z3 - g, "verge", "SEW")
	# rows 1-2 and 2-3: downtown + industrial
	_add_block("B12_CD", xc + g, xd - g, z1 + g, z2 - g, "downtown", "NSEW")
	_add_block("B12_DE", xd + g, xe - g, z1 + g, z2 - g, "downtown", "NSEW")
	_add_block("B12_EF", xe + g, xf - g, z1 + g, z2 - g, "industrial", "NSEW")
	_add_block("B23_CD", xc + g, xd - g, z2 + g, z3 - g, "downtown", "NSEW")
	_add_block("B23_DE", xd + g, xe - g, z2 + g, z3 - g, "downtown", "NSEW")
	_add_block("B23_EF", xe + g, xf - g, z2 + g, z3 - g, "industrial", "NSEW")
	# rows 3-4 and 4-5
	_add_block("B34_AB", xa + g, xb - g, z3 + g, z4 - g, "residential", "NSEW")
	_add_block("B34_BC", xb + g, xc - g, z3 + g, z4 - g, "park", "NSEW")
	_add_block("B34_CD", xc + g, xd - g, z3 + g, z4 - g, "midtown", "NSEW")
	_add_block("B34_DE", xd + g, xe - g, z3 + g, z4 - g, "midtown", "NSEW")
	_add_block("B34_EF", xe + g, xf - g, z3 + g, z4 - g, "industrial", "NSEW")
	_add_block("B45_AB", xa + g, xb - g, z4 + g, z5 - g, "residential", "NSEW")
	_add_block("B45_BC", xb + g, xc - g, z4 + g, z5 - g, "residential", "NSEW")
	_add_block("B45_CD", xc + g, xd - g, z4 + g, z5 - g, "midtown", "NSEW")
	_add_block("B45_DE", xd + g, xe - g, z4 + g, z5 - g, "midtown", "NSEW")
	_add_block("B45_EF", xe + g, xf - g, z4 + g, z5 - g, "industrial", "NSEW")
	# beachfront strip between Dune St (row 5) and Bayline Avenue (row 6)
	_add_block("S_AD", xa + g, xd - g, z5 + g, z6 - ga, "beachfront", "NSEW")
	_add_block("S_DF", xd + g, xf - g, z5 + g, z6 - ga, "marina", "NSEW")
	# west strip (houses backing onto the western tree line)
	_add_block("W_a", -300.0, xa - g, z3 - g, z6 + ARTERIAL_HW, "residential", "E")
	# promenade / quay south of Bayline Avenue
	_add_block("P_w", -300.0, xd, z6 + ga, Terrain.COAST_Z, "beach", "N")
	_add_block("P_e", xd, kx, z6 + ga, Terrain.COAST_Z, "marina", "N")
	# airfield platform and the port yard south of it (east of Airfield Rd)
	_add_block("AIR", AIR_X0, AIR_X1, -300.0, AIR_Z1 + 2.0, "airfield", "W")
	_add_block("PORT", AIR_X0, AIR_X1, AIR_Z1 + 2.0, Terrain.COAST_Z, "port", "W")

func _build_zones() -> void:
	zones = [
		{"name": "Lookout Hill", "rect": Rect2(-300, -300, 241, 241)},
		{"name": "Downtown", "rect": Rect2(-59, -300, 189, 250)},
		{"name": "Ironworks", "rect": Rect2(130, -300, 84, 430)},
		{"name": "Vesper Airfield", "rect": Rect2(214, -300, 86, 420)},
		{"name": "Palm Row", "rect": Rect2(-300, -59, 250, 190)},
		{"name": "Midtown", "rect": Rect2(-50, -50, 180, 180)},
		{"name": "Coral Beach", "rect": Rect2(-300, 131, 340, 400)},
		{"name": "Saltline Docks", "rect": Rect2(40, 131, 400, 400)},
	]

func district_at(x: float, z: float) -> String:
	for zn in zones:
		if (zn["rect"] as Rect2).has_point(Vector2(x, z)):
			return zn["name"]
	if z > 131.0:
		return "Vesper Bay"
	return "Outskirts"

func block_by_id(id: String) -> Dictionary:
	for b in blocks:
		if b["id"] == id:
			return b
	return {}

## Rectangle of a block including its sidewalks (the raised kerb slab).
func kerb_rect(b: Dictionary) -> Rect2:
	var r: Rect2 = b["rect"]
	var s: Dictionary = b["sides"]
	var x0 := r.position.x - (SIDEWALK if s["W"] else 0.0)
	var z0 := r.position.y - (SIDEWALK if s["N"] else 0.0)
	var x1 := r.end.x + (SIDEWALK if s["E"] else 0.0)
	var z1 := r.end.y + (SIDEWALK if s["S"] else 0.0)
	return Rect2(x0, z0, x1 - x0, z1 - z0)

## Junction box (asphalt square) of a node as Rect2 in XZ.
func node_rect(n: Dictionary) -> Rect2:
	var p: Vector3 = n["pos"]
	return Rect2(p.x - n["hx"], p.z - n["hz"], n["hx"] * 2.0, n["hz"] * 2.0)
