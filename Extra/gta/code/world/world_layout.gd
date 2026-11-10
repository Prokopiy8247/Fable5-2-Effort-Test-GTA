class_name WorldLayout
## Static description of Cinder Bay: road grid, blocks, terrain height, signals and helper queries.
## Godot axes: +X east, +Z south, +Y up. Playable footprint: x,z in [-300, 300].

const VX: Array[float] = [-264.0, -176.0, -88.0, 0.0, 88.0, 176.0, 264.0]
const HZ: Array[float] = [-170.0, -85.0, 0.0, 85.0, 170.0]
const NX := 7
const NZ := 5
const SIDEWALK := 4.0
const CURB_H := 0.16
const LANE_W := 3.5
const WATER := -1.2
const COAST_Z := 184.0
const HILL_TOP := Vector3(-208.0, 24.6, -243.0)

# block district types: rows = j (north -> south), cols = i (west -> east)
const BLOCKS := [
	["res", "apt", "hospital", "towers", "gas", "ind"],
	["res", "res", "towers", "civic", "ind", "ind"],
	["res", "safe", "park", "shops", "yard", "ind"],
	["res", "beachres", "hotel", "hotel", "docks", "docks"],
]

const HILL_PATH: Array[Vector2] = [Vector2(-176, -180), Vector2(-150, -200), Vector2(-135, -235), Vector2(-160, -275),
	Vector2(-215, -285), Vector2(-250, -262), Vector2(-240, -232), Vector2(-222, -225), Vector2(-208, -243)]

const RUNWAY := {"x0": -70.0, "x1": 290.0, "z": -252.0, "hw": 15.0}
const DISTRICT_NAMES := {"res": "Maple Flats", "apt": "Maple Flats", "safe": "Maple Flats", "beachres": "Sandy Row", "hospital": "Midtown",
	"towers": "Financial Core", "civic": "Civic Square", "park": "Lantern Park", "shops": "Market Street", "hotel": "Bayfront",
	"gas": "Ironworks", "ind": "Ironworks", "yard": "Ironworks", "docks": "Harbor Docks"}

static var _path_len: Array[float] = []
static var _path_total := 0.0


static func v_hw(i: int) -> float:
	return 8.0 if i == 3 else 5.5


static func h_hw(j: int) -> float:
	if j == 0:
		return 8.0
	return 6.5 if j == 4 else 5.5


static func v_lanes(i: int) -> int:
	return 2 if i == 3 else 1


static func h_lanes(j: int) -> int:
	return 2 if j == 0 else 1


static func inter_pos(ix: Vector2i) -> Vector3:
	return Vector3(VX[ix.x], 0.0, HZ[ix.y])


static func valid(ix: Vector2i) -> bool:
	return ix.x >= 0 and ix.x < NX and ix.y >= 0 and ix.y < NZ


static func neighbors(ix: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if valid(ix + d):
			out.append(ix + d)
	return out


static func seg_lanes(a: Vector2i, b: Vector2i) -> int:
	return v_lanes(a.x) if a.x == b.x else h_lanes(a.y)


static func seg_hw(a: Vector2i, b: Vector2i) -> float:
	return v_hw(a.x) if a.x == b.x else h_hw(a.y)


static func seg_speed(a: Vector2i, b: Vector2i) -> float:
	return 17.0 if seg_lanes(a, b) > 1 else 11.5


static func inter_half(ix: Vector2i, along_x: bool) -> float:
	## Half extent of the intersection box measured along the travel axis.
	return v_hw(ix.x) if along_x else h_hw(ix.y)


static func signalized(ix: Vector2i) -> bool:
	return (ix.x == 3 or ix.y == 0) and neighbors(ix).size() >= 3


static func signal_state(ix: Vector2i, along_x: bool, t: float) -> int:
	## 0 = green, 1 = yellow, 2 = red for traffic travelling along X (east/west) or Z.
	if not signalized(ix):
		return 0
	var p := fmod(t, 26.0)
	if along_x:
		return 0 if p < 10.0 else (1 if p < 12.5 else 2)
	if p < 13.0:
		return 2
	return 0 if p < 23.0 else (1 if p < 25.5 else 2)


static func lane_ends(a: Vector2i, b: Vector2i, lane: int) -> Array:
	## Start (leaving a) and end (stop line before b) of a lane, right-hand traffic.
	var pa := inter_pos(a)
	var pb := inter_pos(b)
	var d := (pb - pa).normalized()
	var right := Vector3(-d.z, 0.0, d.x)
	var along_x := a.y == b.y
	var off := right * (LANE_W * (0.5 + lane))
	var s := pa + d * (inter_half(a, along_x) + 1.0) + off
	var e := pb - d * (inter_half(b, along_x) + 4.5) + off
	return [s, e]


static func block_rect(bi: int, bj: int) -> Rect2:
	var x0 := VX[bi] + v_hw(bi)
	var x1 := VX[bi + 1] - v_hw(bi + 1)
	var z0 := HZ[bj] + h_hw(bj)
	var z1 := HZ[bj + 1] - h_hw(bj + 1)
	return Rect2(x0, z0, x1 - x0, z1 - z0)


static func block_of(pos: Vector3) -> Vector2i:
	for bi in NX - 1:
		for bj in NZ - 1:
			if block_rect(bi, bj).has_point(Vector2(pos.x, pos.z)):
				return Vector2i(bi, bj)
	return Vector2i(-1, -1)


static func district_at(pos: Vector3) -> String:
	var b := block_of(pos)
	if b.x >= 0:
		return DISTRICT_NAMES[BLOCKS[b.y][b.x]]
	if pos.z > 176.0:
		return "Harbor Docks" if pos.x > 60.0 else "Coral Beach"
	if pos.z < -178.0:
		return "Cinder Field Airport" if pos.x > -90.0 else "Ember Hill"
	if absf(pos.x) > 270.0:
		return "City Limits"
	return "Cinder Bay"


static func nearest_inter(pos: Vector3) -> Vector2i:
	var best := Vector2i.ZERO
	var bd := 1e9
	for i in NX:
		for j in NZ:
			var d := Vector2(pos.x - VX[i], pos.z - HZ[j]).length_squared()
			if d < bd:
				bd = d
				best = Vector2i(i, j)
	return best


static func on_road(pos: Vector3) -> bool:
	if pos.z < HZ[0] - 9.0 or pos.z > HZ[NZ - 1] + 8.0 or absf(pos.x) > 271.0:
		return false
	for i in NX:
		if absf(pos.x - VX[i]) <= v_hw(i):
			return true
	for j in NZ:
		if absf(pos.z - HZ[j]) <= h_hw(j):
			return true
	return false


static func _ensure_path() -> void:
	if not _path_len.is_empty():
		return
	_path_len.append(0.0)
	for k in range(1, HILL_PATH.size()):
		_path_total += HILL_PATH[k].distance_to(HILL_PATH[k - 1])
		_path_len.append(_path_total)


static func path_info(x: float, z: float) -> Vector2:
	## Returns (distance to the hill track, target height of the track at the closest point).
	_ensure_path()
	var p := Vector2(x, z)
	var bd := 1e9
	var bh := 0.0
	for k in HILL_PATH.size() - 1:
		var a := HILL_PATH[k]
		var b := HILL_PATH[k + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < bd:
			bd = d
			bh = (_path_len[k] + ab.length() * t) / _path_total * HILL_TOP.y
	return Vector2(bd, bh)


static func raw_hill(x: float, z: float) -> float:
	var hx := x + 205.0
	var hz := z + 250.0
	var hd := sqrt(hx * hx * 0.8 + hz * hz * 1.5)
	if hd >= 95.0:
		return 0.0
	var t := 1.0 - hd / 95.0
	var hill := 27.0 * t * t * (3.0 - 2.0 * t)
	hill = minf(hill, 24.6 + (hill - 24.6) * 0.1)
	hill += sin(x * 0.13) * cos(z * 0.11) * 1.3 * t
	var fade := clampf((-183.0 - z) / 16.0, 0.0, 1.0) * clampf((-97.0 - x) / 16.0, 0.0, 1.0)
	return hill * fade


static func height(x: float, z: float) -> float:
	var h := 0.0
	if x < -90.0 and z < -175.0:
		h = raw_hill(x, z)
		var pi := path_info(x, z)
		if pi.x < 10.0:
			var k := smoothstep(4.0, 10.0, pi.x)
			h = lerpf(pi.y, h, k)
	var cz := coast_z(x)
	if z > cz:
		var dz := z - cz
		var beach := -dz * 0.062 - maxf(dz - 28.0, 0.0) * 0.09
		var quay := (-6.0 - dz * 0.07) if dz > 2.5 else (-dz * 2.4)
		var k2 := clampf((x - 40.0) / 20.0, 0.0, 1.0)
		h += lerpf(beach, quay, k2)
		h = maxf(h, -15.0)
		var di := Vector2(x + 40.0, z - 274.0).length()
		if di < 22.0:
			h = maxf(h, -6.0 + 7.8 * smoothstep(22.0, 9.0, di))
	var o := maxf(maxf(absf(x) - 318.0, 0.0), maxf(-z - 318.0, 0.0))
	if o > 0.0 and z < 150.0:
		h += minf(o * o * 0.0005, 45.0) * (1.0 + 0.35 * sin(x * 0.021) * cos(z * 0.017))
	return h


static func coast_z(x: float) -> float:
	return COAST_Z + 10.0 * clampf((x - 40.0) / 20.0, 0.0, 1.0)


static func sand_mask(x: float, z: float) -> float:
	var cz := coast_z(x)
	if z < cz - 6.0:
		return 0.0
	return clampf((z - (cz - 6.0)) / 5.0, 0.0, 1.0) * (1.0 - clampf((x - 44.0) / 14.0, 0.0, 1.0) * 0.85)
