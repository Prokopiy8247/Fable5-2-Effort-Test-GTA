extends RefCounted
## WORLD module helper: block interiors (raised slabs) and building lots from WorldLayout.BLOCKS.
## Module-private (no class_name).

const Geom := preload("res://gta/code/world/gen/world_geom.gd")

## Contract lots: {id, district, zone, center, size, yaw, landmark} + extras {block, ground, row}.
var lots: Array[Dictionary] = []
## Block interiors: {id, x0, z0, x1, z1, radii [nw, ne, se, sw], ground, flat, district, zone, y}.
var slabs: Array[Dictionary] = []
var errors: PackedStringArray = []

var _roads: RoadGraph


func build(roads: RoadGraph, terrain: Terrain) -> void:
	_roads = roads
	for b: Array in WorldLayout.BLOCKS:
		_block(b)
	for e: Array in WorldLayout.EXTRA_LOTS:
		var x := float(e[3])
		var z := float(e[4])
		var y: float = terrain.get_mesh_height(x, z) if terrain != null else Terrain.height(x, z)
		lots.append({"id": lots.size(), "district": String(e[2]), "zone": String(e[1]), "center": Vector3(x, y, z),
				"size": Vector2(float(e[5]), float(e[6])), "yaw": float(e[7]), "landmark": String(e[0]),
				"block": "", "ground": "", "row": "X"})


## Distance from a block edge (road centre line) to the lot area: half road width + sidewalk.
func _side_inset(p0: Vector2, p1: Vector2, inward: Vector2) -> float:
	var grid := _roads.seg_grid
	for f: float in [0.5, 0.3, 0.7]:
		var p := p0.lerp(p1, f)
		var best := -1
		var best_d := 0.7
		for e in grid.candidates(p):
			var a := grid.ea[e]
			var ab := grid.eb[e] - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var d := (a + ab * t).distance_to(p)
			if d < best_d:
				best_d = d
				best = e
		if best < 0:
			continue
		var seg: Dictionary = _roads.segments[grid.eid[best]]
		if int(seg["node_a"]) < 0:
			continue
		var dir := (grid.eb[best] - grid.ea[best]).normalized()
		var on_right := Geom.right_of(dir).dot(inward) > 0.0
		var sw: bool = seg["sw_r"] if on_right else seg["sw_l"]
		return float(seg["hw"]) + (WorldLayout.SIDEWALK_W if sw else 0.0)
	return 0.0


## Radius needed at an interior corner that sits inside a rounded road bend.
func _corner_radius(corner: Vector2) -> float:
	for b: Dictionary in _roads.bends:
		var s: float = b["side"]
		var inner_sw: bool = b["sw_r"] if s > 0.0 else b["sw_l"]
		var off: float = float(b["hw"]) + (WorldLayout.SIDEWALK_W if inner_sw else 0.0)
		var v: Vector2 = b["v"]
		var pi: Vector2 = v + Geom.right_of(b["d0"]) * (s * off) + Geom.right_of(b["d1"]) * (s * off)
		if pi.distance_to(corner) < 0.9:
			return maxf(float(b["r"]) - off, 0.0)
	return 0.0


func _block(b: Array) -> void:
	var id: String = b[0]
	var x0 := float(b[1])
	var z0 := float(b[2])
	var x1 := float(b[3])
	var z1 := float(b[4])
	var district: String = b[5]
	var zone: String = b[6]
	var rows: Array = b[7]
	var opts: Dictionary = b[8]
	var ix0 := x0
	var iz0 := z0
	var ix1 := x1
	var iz1 := z1
	if opts.has("inner"):
		var inn: Array = opts["inner"]
		ix0 = float(inn[0])
		iz0 = float(inn[1])
		ix1 = float(inn[2])
		iz1 = float(inn[3])
	else:
		iz0 = z0 + _side_inset(Vector2(x0, z0), Vector2(x1, z0), Vector2(0, 1))
		iz1 = z1 - _side_inset(Vector2(x0, z1), Vector2(x1, z1), Vector2(0, -1))
		ix0 = x0 + _side_inset(Vector2(x0, z0), Vector2(x0, z1), Vector2(1, 0))
		ix1 = x1 - _side_inset(Vector2(x1, z0), Vector2(x1, z1), Vector2(-1, 0))
	var flat: bool = opts.get("flat", false)
	var ground: String = opts.get("ground", WorldLayout.GROUND_OF_ZONE[zone])
	var radii: Array = [_corner_radius(Vector2(ix0, iz0)), _corner_radius(Vector2(ix1, iz0)),
			_corner_radius(Vector2(ix1, iz1)), _corner_radius(Vector2(ix0, iz1))]
	var y: float = WorldLayout.PLATEAU_Y + (WorldLayout.DECK_LIFT if flat else WorldLayout.CURB_H)
	slabs.append({"id": id, "x0": ix0, "z0": iz0, "x1": ix1, "z1": iz1, "radii": radii, "ground": ground,
			"flat": flat, "district": district, "zone": zone, "y": y})
	if ix1 - ix0 < 2.0 or iz1 - iz0 < 2.0:
		errors.append("block %s has a degenerate interior" % id)
		return

	var depth := {"N": 0.0, "S": 0.0, "E": 0.0, "W": 0.0}
	for row: Array in rows:
		if String(row[0]) != "R":
			depth[String(row[0])] = float(row[1])
	var r_nw: float = radii[0]
	var r_ne: float = radii[1]
	var r_se: float = radii[2]
	var r_sw: float = radii[3]
	for row: Array in rows:
		var side: String = row[0]
		var d: float = float(row[1])
		var items: Array = row[2]
		if side == "R":
			var k := 0.293
			var rx0: float = ix0 + float(depth["W"]) + k * maxf(r_nw, r_sw)
			var rx1: float = ix1 - float(depth["E"]) - k * maxf(r_ne, r_se)
			var rz0: float = iz0 + float(depth["N"]) + k * maxf(r_nw, r_ne)
			var rz1: float = iz1 - float(depth["S"]) - k * maxf(r_sw, r_se)
			var rzone := String(items[0])
			lots.append({"id": lots.size(), "district": district, "zone": rzone,
					"center": Vector3((rx0 + rx1) * 0.5, y, (rz0 + rz1) * 0.5), "size": Vector2(rx1 - rx0, rz1 - rz0),
					"yaw": 0.0, "landmark": "", "block": id, "ground": String(WorldLayout.GROUND_OF_ZONE[rzone]), "row": "R"})
			continue
		var a0: float
		var a1: float
		match side:
			"N":
				a0 = ix0 + r_nw
				a1 = ix1 - r_ne
			"S":
				a0 = ix0 + r_sw
				a1 = ix1 - r_se
			"W":
				a0 = iz0 + maxf(float(depth["N"]), r_nw)
				a1 = iz1 - maxf(float(depth["S"]), r_sw)
			_:
				a0 = iz0 + maxf(float(depth["N"]), r_ne)
				a1 = iz1 - maxf(float(depth["S"]), r_se)
		# the far edge of the row must stay inside the rounded corners of the opposite side as well
		match side:
			"N":
				a0 = maxf(a0, _fit(ix0, r_sw, iz0 + d - (iz1 - r_sw)))
				a1 = minf(a1, ix1 + ix0 - _fit(ix0, r_se, iz0 + d - (iz1 - r_se)))
			"S":
				a0 = maxf(a0, _fit(ix0, r_nw, (iz0 + r_nw) - (iz1 - d)))
				a1 = minf(a1, ix1 + ix0 - _fit(ix0, r_ne, (iz0 + r_ne) - (iz1 - d)))
			"W":
				a0 = maxf(a0, _fit(iz0, r_ne, ix0 + d - (ix1 - r_ne)))
				a1 = minf(a1, iz1 + iz0 - _fit(iz0, r_se, ix0 + d - (ix1 - r_se)))
			_:
				a0 = maxf(a0, _fit(iz0, r_nw, (ix0 + r_nw) - (ix1 - d)))
				a1 = minf(a1, iz1 + iz0 - _fit(iz0, r_sw, (ix0 + r_sw) - (ix1 - d)))
		var fixed := 0.0
		var stars := 0
		for it: String in items:
			if it.begins_with("*"):
				stars += 1
			elif it.begins_with("gap:"):
				fixed += float(it.substr(4))
			else:
				fixed += float(it.get_slice(":", 1).get_slice("x", 0))
		var free := a1 - a0 - fixed
		if free < -0.01:
			errors.append("block %s row %s: items need %.1f m, only %.1f m available" % [id, side, fixed, a1 - a0])
		var star_len := maxf(free, 0.0) / float(maxi(stars, 1))
		var cur := a0
		for it: String in items:
			if it.begins_with("*"):
				var z: String = it.substr(1) if it.length() > 1 else zone
				if star_len >= 7.0:
					var cnt := maxi(1, int(round(star_len / float(WorldLayout.LOT_WIDTH.get(z, 20.0)))))
					var w := star_len / float(cnt)
					for k in cnt:
						_row_lot(side, cur + w * float(k), w, d, z, "", district, id, y, ix0, iz0, ix1, iz1)
				cur += star_len
			elif it.begins_with("gap:"):
				cur += float(it.substr(4))
			else:
				var lname := it.get_slice(":", 0)
				var dims := it.get_slice(":", 1)
				var w := float(dims.get_slice("x", 0))
				var dd := float(dims.get_slice("x", 1))
				_row_lot(side, cur, w, dd, "landmark", lname, district, id, y, ix0, iz0, ix1, iz1)
				cur += w
	if flat:
		for lot in lots:
			if String(lot["block"]) == id:
				lot["ground"] = ground


## Smallest along-coordinate (measured from lo) at which a row edge that reaches "over" metres into
## the zone of a rounded corner (radius r) is still inside the rounded outline.
static func _fit(lo: float, r: float, over: float) -> float:
	if r <= 0.05 or over <= 0.0:
		return lo
	var o := minf(over, r)
	return lo + r - sqrt(maxf(r * r - o * o, 0.0))


func _row_lot(side: String, a: float, w: float, d: float, zone: String, landmark: String, district: String,
		block: String, y: float, ix0: float, iz0: float, ix1: float, iz1: float) -> void:
	var c := Vector3.ZERO
	var yaw := 0.0
	match side:
		"N":
			c = Vector3(a + w * 0.5, y, iz0 + d * 0.5)
			yaw = 0.0
		"S":
			c = Vector3(a + w * 0.5, y, iz1 - d * 0.5)
			yaw = PI
		"W":
			c = Vector3(ix0 + d * 0.5, y, a + w * 0.5)
			yaw = PI * 0.5
		_:
			c = Vector3(ix1 - d * 0.5, y, a + w * 0.5)
			yaw = -PI * 0.5
	lots.append({"id": lots.size(), "district": district, "zone": zone, "center": c, "size": Vector2(w, d), "yaw": yaw,
			"landmark": landmark, "block": block, "ground": String(WorldLayout.GROUND_OF_ZONE[zone]), "row": side})
