extends RefCounted
## WORLD module helper: generates every paved surface of the island as a handful of mesh surfaces and
## trimesh colliders: asphalt, painted markings, sidewalks + kerbs, block slabs, lot grounds, airfield,
## quays, piers, tram rails. Module-private (no class_name).

const Geom := preload("res://gta/code/world/gen/world_geom.gd")
const MeshBuf := preload("res://gta/code/world/gen/world_meshbuf.gd")
const ROAD_SHADER := "res://gta/code/world/shaders/world_road.gdshader"
const GROUND_SHADER := "res://gta/code/world/shaders/world_ground.gdshader"

# colours are authored in sRGB; the shaders convert. Ground alpha = pattern id (see world_ground.gdshader).
const C_ART := Color(0.215, 0.215, 0.235)
const C_STREET := Color(0.245, 0.245, 0.26)
const C_ALLEY := Color(0.30, 0.295, 0.29)
const C_RUNWAY := Color(0.19, 0.19, 0.205)
const C_TAXI := Color(0.27, 0.27, 0.28)
const C_TARMAC := Color(0.28, 0.28, 0.295)
const C_WHITE := Color(0.93, 0.93, 0.90)
const C_YELLOW := Color(0.96, 0.76, 0.16)
const C_STEEL := Color(0.50, 0.51, 0.54)
const C_KERB := Color(0.70, 0.69, 0.66, 0.0)
const C_SIDEWALK := Color(0.69, 0.67, 0.63, 0.2)
const C_PAVERS := Color(0.70, 0.57, 0.48, 0.4)
const C_TILES := Color(0.77, 0.72, 0.62, 0.6)
const C_CONCRETE := Color(0.63, 0.63, 0.61, 0.2)
const C_DECK := Color(0.64, 0.63, 0.60, 0.2)
const C_WALL := Color(0.52, 0.51, 0.49, 0.0)
const C_PLANKS_X := Color(0.66, 0.50, 0.34, 0.9)      ## boards running north-south (joints at constant x)
const C_PLANKS_Z := Color(0.66, 0.50, 0.34, 0.8)      ## boards running east-west (joints at constant z)
const C_PILE := Color(0.36, 0.27, 0.20, 0.0)
const C_LAWN := Color(0.40, 0.60, 0.27, 1.0)
const C_GRAVEL := Color(0.76, 0.69, 0.55, 0.0)      ## park footpaths
const C_TRAIL := Color(0.72, 0.62, 0.46, 0.0)       ## trodden dune trail

const BAY_W := 2.8
const BAY_D := 5.2

var asphalt := MeshBuf.new()
var paint := MeshBuf.new()
var g_concrete := MeshBuf.new()
var g_grass := MeshBuf.new()
var g_wood := MeshBuf.new()
var g_path := MeshBuf.new()                    ## visual-only footpaths (no collision; the ground below collides)
var parking_bays: Array[Transform3D] = []      ## bays painted inside parking lots
var driveways: Array[Transform3D] = []         ## kerb ramps (centre of the ramp, -Z into the lot)
var tri_total := 0

var _y0: float = WorldLayout.PLATEAU_Y
var _yr: float = WorldLayout.PLATEAU_Y + WorldLayout.ROAD_LIFT
var _ym: float = WorldLayout.PLATEAU_Y + WorldLayout.MARK_LIFT
var _ys: float = WorldLayout.PLATEAU_Y + WorldLayout.CURB_H
var _yd: float = WorldLayout.PLATEAU_Y + WorldLayout.DECK_LIFT
var _run: float = WorldLayout.CURB_RUN
var _sw: float = WorldLayout.SIDEWALK_W


func build(parent: Node3D, roads: RoadGraph, lotgen: RefCounted, tram: PackedVector2Array) -> void:
	_road_strips(roads)
	_intersections(roads)
	_sidewalks(roads)
	_bends(roads)
	_slabs(lotgen.get("slabs"), lotgen.get("lots"))
	_markings(roads)
	_airfield(roads)
	_quay()
	_piers()
	_rails(tram)
	_footpaths(parent)
	_commit(parent)


static func _asphalt_colour(kind: String) -> Color:
	match kind:
		"arterial":
			return C_ART
		"alley":
			return C_ALLEY
		"runway":
			return C_RUNWAY
		"taxiway":
			return C_TAXI
	return C_STREET


# ---------------------------------------------------------------------------------------------
# asphalt
# ---------------------------------------------------------------------------------------------

func _road_strips(roads: RoadGraph) -> void:
	for s: Dictionary in roads.segments:
		var kind: String = s["kind"]
		if kind == "dirt":
			continue
		var hw: float = s["hw"]
		var a0: float = s["trim_a"]
		var a1: float = float(s["length"]) - float(s["trim_b"])
		if a1 - a0 < 0.2:
			continue
		var sub := Geom.sub(s["pts2"], a0, a1)
		asphalt.strip(Geom.offset(sub, -hw), Geom.offset(sub, hw), _yr, _yr, _asphalt_colour(kind))


func _corner_path(cn: Dictionary) -> PackedVector2Array:
	var c: Vector2 = cn["c"]
	var da: Vector2 = cn["da"]
	var db: Vector2 = cn["db"]
	var r: float = WorldLayout.CORNER_R
	var q := c + (da + db) * r
	var path := PackedVector2Array()
	path.append(c + da * _sw)
	for i in 6:
		var th := PI * 0.5 * float(i) / 5.0
		path.append(q - db * (r * cos(th)) - da * (r * sin(th)))
	path.append(c + db * _sw)
	return path


func _intersections(roads: RoadGraph) -> void:
	for node: Dictionary in roads.intersections:
		var legs: Array = node["legs"]
		if legs.size() < 2:
			continue
		var c: Vector3 = node["position"]
		var box: Vector2 = node["box"]
		asphalt.rect(c.x - box.x, c.z - box.y, c.x + box.x, c.z + box.y, _yr, C_STREET)
		for cn: Dictionary in node["corners"]:
			var path := _corner_path(cn)
			# road surface between the kerb arc and the sharp corner
			asphalt.fan(cn["c"], path.slice(1, path.size() - 1), _yr, C_STREET)
			# raised sidewalk corner
			g_concrete.fan(cn["o"], path, _ys, C_SIDEWALK)
			g_concrete.path_skirt(path, cn["o"], _ys, _y0, _run, C_KERB)


# ---------------------------------------------------------------------------------------------
# sidewalks
# ---------------------------------------------------------------------------------------------

func _sidewalks(roads: RoadGraph) -> void:
	for s: Dictionary in roads.segments:
		var hw: float = s["hw"]
		for side: int in [-1, 1]:
			var span: Array = s["sw_l_span"] if side == -1 else s["sw_r_span"]
			if span.is_empty():
				continue
			var sub := Geom.sub(s["pts2"], float(span[0]), float(span[1]))
			var f := float(side)
			var k0 := Geom.offset(sub, f * (hw - _run))
			var k1 := Geom.offset(sub, f * hw)
			var k2 := Geom.offset(sub, f * (hw + _sw))
			var k3 := Geom.offset(sub, f * (hw + _sw + _run))
			g_concrete.strip(k0, k1, _y0, _ys, C_KERB)
			g_concrete.strip(k1, k2, _ys, _ys, C_SIDEWALK)
			g_concrete.strip(k2, k3, _ys, _y0, C_KERB)
			var n := sub.size()
			if span[2]:
				var back := (sub[0] - sub[1]).normalized() * _run
				_cap(k1[0], k2[0], back)
			if span[3]:
				var fwd := (sub[n - 1] - sub[n - 2]).normalized() * _run
				_cap(k1[n - 1], k2[n - 1], fwd)


func _cap(a: Vector2, b: Vector2, push: Vector2) -> void:
	g_concrete.quad(Vector3(a.x, _ys, a.y), Vector3(b.x, _ys, b.y), Vector3(b.x + push.x, _y0, b.y + push.y),
			Vector3(a.x + push.x, _y0, a.y + push.y), C_KERB)


## Paved wedges on the outside of rounded road bends (between the curved sidewalk and the square corner).
func _bends(roads: RoadGraph) -> void:
	for b: Dictionary in roads.bends:
		var s: float = b["side"]
		var outer_sw: bool = b["sw_l"] if s > 0.0 else b["sw_r"]
		if not outer_sw:
			continue
		var off: float = float(b["hw"]) + _sw
		var v: Vector2 = b["v"]
		var centre: Vector2 = b["centre"]
		var d0: Vector2 = b["d0"]
		var d1: Vector2 = b["d1"]
		var m: Vector2 = v - Geom.right_of(d0) * (s * off) - Geom.right_of(d1) * (s * off)
		var u0: Vector2 = -Geom.right_of(d0) * s
		var steps: int = b["steps"]
		var arc := PackedVector2Array()
		for k in steps + 1:
			arc.append(centre + u0.rotated(float(b["ang"]) * float(k) / float(steps)) * (float(b["r"]) + off))
		g_concrete.fan(m, arc, _ys, C_SIDEWALK)
		var inside := (m + arc[steps >> 1]) * 0.5
		g_concrete.path_skirt(PackedVector2Array([arc[steps], m, arc[0]]), inside, _ys, _y0, _run, C_KERB)


# ---------------------------------------------------------------------------------------------
# block slabs and lot grounds
# ---------------------------------------------------------------------------------------------

func _ground_buf(ground: String) -> MeshBuf:
	match ground:
		"grass":
			return g_grass
		"planks":
			return g_wood
		"tarmac":
			return asphalt
	return g_concrete


static func _ground_colour(ground: String, wide: bool) -> Color:
	match ground:
		"grass":
			return C_LAWN
		"planks":
			return C_PLANKS_X if wide else C_PLANKS_Z
		"tarmac":
			return C_TARMAC
		"tiles":
			return C_TILES
		"pavers":
			return C_PAVERS
	return C_CONCRETE


func _slabs(slabs: Array, lots: Array) -> void:
	var slab_ground := {}
	var slab_by_id := {}
	for sl: Dictionary in slabs:
		slab_by_id[String(sl["id"])] = sl
		var x0: float = sl["x0"]
		var z0: float = sl["z0"]
		var x1: float = sl["x1"]
		var z1: float = sl["z1"]
		var y: float = sl["y"]
		var ground: String = sl["ground"]
		slab_ground[String(sl["id"])] = ground
		var outline := Geom.rounded_rect(x0, z0, x1, z1, sl["radii"])
		_ground_buf(ground).poly(outline, y, _ground_colour(ground, (x1 - x0) > (z1 - z0)))
		if not sl["flat"]:
			g_concrete.skirt(outline, y, _y0, _run, C_KERB)
			if z1 > 231.0 and (z1 - z0) < 6.0:
				# beach boardwalk: its seaward edge sits on the plateau rim, close the gap to the sand
				g_concrete.wall(PackedVector2Array([Vector2(x0, z1 + _run), Vector2(x1, z1 + _run)]), _y0 + 0.02, _y0 - 0.9, C_WALL, 1.0)
	for lot: Dictionary in lots:
		var zone: String = lot["zone"]
		var ground: String = lot["ground"]
		var block: String = lot["block"]
		var c3: Vector3 = lot["center"]
		var size: Vector2 = lot["size"]
		var yaw: float = lot["yaw"]
		var ax := Vector2(cos(yaw), -sin(yaw))
		var c := Vector2(c3.x, c3.z)
		if block != "" and String(lot["row"]) != "R" and ground != String(slab_ground.get(block, "")):
			_ground_buf(ground).orect(c, ax, size.x * 0.5, size.y * 0.5, c3.y + 0.012, _ground_colour(ground, absf(ax.x) > 0.5))
		if zone == "parking":
			_parking_lot(lot)
			if String(lot["row"]) == "R" and slab_by_id.has(block) and absf(yaw) < 0.01:
				# whole-block car park (airport): ramp over the kerb of its north side
				_driveway_at(Vector2(c.x, float(slab_by_id[block]["z0"]) - _sw), yaw)
		if block != "" and (zone == "parking" or String(lot["landmark"]) in ["gas_station", "mod_garage", "parking_garage",
				"hospital", "police_station", "airport_hangar"]):
			_driveway(lot, 0.0)
			if String(lot["landmark"]) == "gas_station":
				_driveway(lot, -10.0)
				_driveway(lot, 10.0)
		if String(lot["landmark"]) == "safehouse":
			_driveway(lot, size.x * 0.5 + 4.0)       # the 8 m gap beside the safehouse (row start side)


## Asphalt ramp over the kerb in front of a lot (only where the lot fronts a raised sidewalk).
func _driveway(lot: Dictionary, along: float) -> void:
	var c3: Vector3 = lot["center"]
	if absf(c3.y - _ys) > 0.02 or String(lot["row"]) == "X":
		return
	var size: Vector2 = lot["size"]
	var yaw: float = lot["yaw"]
	var ax := Vector2(cos(yaw), -sin(yaw))
	var front := Vector2(-sin(yaw), -cos(yaw))
	var depth := size.y * 0.5
	if String(lot["row"]) == "R":
		return
	_driveway_at(Vector2(c3.x, c3.z) + front * (depth + _sw) + ax * along, yaw)


## kerb = point on the kerb line (top edge of the kerb), yaw = lot yaw (front faces the road).
func _driveway_at(kerb: Vector2, yaw: float) -> void:
	var ax := Vector2(cos(yaw), -sin(yaw))
	var front := Vector2(-sin(yaw), -cos(yaw))
	var hw := 3.2
	var reach := 1.1
	var a := kerb - ax * hw
	var b := kerb + ax * hw
	var a2 := a + front * reach
	var b2 := b + front * reach
	asphalt.quad(Vector3(a.x, _ys, a.y), Vector3(b.x, _ys, b.y), Vector3(b2.x, _yr - 0.01, b2.y), Vector3(a2.x, _yr - 0.01, a2.y), C_STREET)
	asphalt.tri(Vector3(a.x, _ys, a.y), Vector3(a2.x, _yr - 0.01, a2.y), Vector3(a.x - ax.x * 0.5, _yr - 0.01, a.y - ax.y * 0.5), C_STREET)
	asphalt.tri(Vector3(b.x, _ys, b.y), Vector3(b2.x, _yr - 0.01, b2.y), Vector3(b.x + ax.x * 0.5, _yr - 0.01, b.y + ax.y * 0.5), C_STREET)
	driveways.append(Transform3D(Basis(Vector3.UP, yaw + PI), Vector3(kerb.x, _ys, kerb.y)))


func _parking_lot(lot: Dictionary) -> void:
	var c3: Vector3 = lot["center"]
	var size: Vector2 = lot["size"]
	var yaw: float = lot["yaw"]
	var ax := Vector2(cos(yaw), -sin(yaw))
	var back := Vector2(sin(yaw), cos(yaw))
	var c := Vector2(c3.x, c3.z)
	var y := c3.y + 0.035
	var rows: Array = [size.y * 0.5 - 1.0 - BAY_D * 0.5]
	if size.y >= 2.0 * BAY_D + 8.5:
		rows.append(-(size.y * 0.5 - 1.0 - BAY_D * 0.5))
	var cnt := int(floor((size.x - 3.0) / BAY_W))
	if cnt < 1:
		return
	var x_start := -float(cnt) * BAY_W * 0.5
	for r: float in rows:
		var row_c := c + back * r
		for i in cnt + 1:
			paint.orect(row_c + ax * (x_start + float(i) * BAY_W), back, BAY_D * 0.5, 0.06, y, C_WHITE)
		for i in cnt:
			var p := row_c + ax * (x_start + (float(i) + 0.5) * BAY_W)
			var face := yaw + PI if r > 0.0 else yaw
			parking_bays.append(Transform3D(Basis(Vector3.UP, face), Vector3(p.x, c3.y + (0.012 if lot["row"] != "R" else 0.0), p.y)))


# ---------------------------------------------------------------------------------------------
# markings
# ---------------------------------------------------------------------------------------------

func _dashes(pl: PackedVector2Array, off: float, w: float, dash: float, gap: float, col: Color) -> void:
	var total := Geom.length_of(pl)
	var s := gap * 0.5
	while s + dash <= total:
		var a := Geom.point_at(pl, s)
		var b := Geom.point_at(pl, s + dash)
		var d := b - a
		var l := d.length()
		if l > 0.01:
			d /= l
			paint.orect((a + b) * 0.5 + Geom.right_of(d) * off, d, l * 0.5, w * 0.5, _ym, col)
		s += dash + gap


func _solid(pl: PackedVector2Array, off: float, w: float, col: Color, y_add: float = 0.0) -> void:
	paint.strip(Geom.offset(pl, off - w * 0.5), Geom.offset(pl, off + w * 0.5), _ym + y_add, _ym + y_add, col)


func _markings(roads: RoadGraph) -> void:
	var setback: float = WorldLayout.STOP_SETBACK
	for s: Dictionary in roads.segments:
		var kind: String = s["kind"]
		if int(s["lanes_per_dir"]) == 0 or kind == "dirt" or kind == "alley":
			continue
		var n_a: Dictionary = roads.intersections[int(s["node_a"])]
		var n_b: Dictionary = roads.intersections[int(s["node_b"])]
		var a0: float = (float(s["trim_a"]) + setback) if (n_a["legs"] as Array).size() > 1 else 0.0
		var a1: float = float(s["length"]) - ((float(s["trim_b"]) + setback) if (n_b["legs"] as Array).size() > 1 else 0.0)
		if a1 - a0 < 3.0:
			continue
		var sub := Geom.sub(s["pts2"], a0, a1)
		if kind == "arterial":
			_solid(sub, -0.16, 0.12, C_YELLOW)
			_solid(sub, 0.16, 0.12, C_YELLOW)
			_dashes(sub, -3.75, 0.13, 3.0, 6.0, C_WHITE)
			_dashes(sub, 3.75, 0.13, 3.0, 6.0, C_WHITE)
		else:
			_dashes(sub, 0.0, 0.14, 3.0, 4.5, C_YELLOW)
			if s["parking"]:
				_solid(sub, -3.5, 0.10, C_WHITE)
				_solid(sub, 3.5, 0.10, C_WHITE)
				var total := Geom.length_of(sub)
				var t := 3.0
				while t <= total - 2.0:
					var p := Geom.point_at(sub, t)
					var d := Geom.dir_at(sub, t)
					var r := Geom.right_of(d)
					paint.orect(p + r * 4.45, r, 0.95, 0.05, _ym, C_WHITE)
					paint.orect(p - r * 4.45, r, 0.95, 0.05, _ym, C_WHITE)
					t += 6.5
	for node: Dictionary in roads.intersections:
		var legs: Array = node["legs"]
		if legs.size() < 3:
			continue
		var c3: Vector3 = node["position"]
		var c := Vector2(c3.x, c3.z)
		for l: Dictionary in legs:
			var d: Vector2 = l["dir"]
			var hw: float = l["hw"]
			var kind: String = l["kind"]
			var trim: float = l["trim"]
			if not (l["lanes_in"] as PackedInt32Array).is_empty() and kind != "dirt":
				var lat := hw - 0.5
				if kind == "street" and bool(roads.segments[int(l["seg"])]["parking"]):
					lat = 3.5
				var rin := Geom.right_of(-d)
				paint.orect(c + d * (trim + setback - 0.2) + rin * ((0.3 + lat) * 0.5), d, 0.2, (lat - 0.3) * 0.5, _ym, C_WHITE)
			if l["crosswalk"]:
				var r := Geom.right_of(d)
				var mid: float = trim + (WorldLayout.CROSSWALK_NEAR + WorldLayout.CROSSWALK_FAR) * 0.5
				var half: float = (WorldLayout.CROSSWALK_FAR - WorldLayout.CROSSWALK_NEAR) * 0.5
				var u := -(hw - 0.55)
				while u + 0.55 <= hw - 0.5:
					paint.orect(c + d * mid + r * (u + 0.275), d, half, 0.275, _ym, C_WHITE)
					u += 1.1


# ---------------------------------------------------------------------------------------------
# airfield
# ---------------------------------------------------------------------------------------------

# seven-segment digits for the runway numbers: segments a b c d e f g
const DIGITS := {"0": "abcdef", "9": "abcdfg", "2": "abdeg", "7": "abc"}


func _digit(ch: String, origin: Vector2, right: Vector2, up: Vector2, w: float, h: float, st: float) -> void:
	var segs: String = DIGITS.get(ch, "")
	var hs := st * 0.5
	for sgm in segs:
		var cu := 0.0
		var cv := 0.0
		var hu := 0.0
		var hv := 0.0
		match sgm:
			"a":
				cu = w * 0.5; cv = h - hs; hu = w * 0.5; hv = hs
			"d":
				cu = w * 0.5; cv = hs; hu = w * 0.5; hv = hs
			"g":
				cu = w * 0.5; cv = h * 0.5; hu = w * 0.5; hv = hs
			"b":
				cu = w - hs; cv = h * 0.75; hu = hs; hv = h * 0.25
			"c":
				cu = w - hs; cv = h * 0.25; hu = hs; hv = h * 0.25
			"e":
				cu = hs; cv = h * 0.25; hu = hs; hv = h * 0.25
			"f":
				cu = hs; cv = h * 0.75; hu = hs; hv = h * 0.25
		paint.orect(origin + right * cu + up * cv, up, hv, hu, _ym, C_WHITE)


func _helipad_marks(centre: Vector2, radius: float, y: float) -> void:
	paint.ring(centre, radius * 0.80, radius * 0.86, y, C_WHITE, 32)
	paint.ring(centre, radius * 0.95, radius * 0.99, y, C_YELLOW, 32)
	var s := radius * 0.2
	paint.rect(centre.x - s * 1.25, centre.y - s * 1.7, centre.x - s * 0.75, centre.y + s * 1.7, y, C_WHITE)
	paint.rect(centre.x + s * 0.75, centre.y - s * 1.7, centre.x + s * 1.25, centre.y + s * 1.7, y, C_WHITE)
	paint.rect(centre.x - s * 0.75, centre.y - s * 0.25, centre.x + s * 0.75, centre.y + s * 0.25, y, C_WHITE)


func _airfield(roads: RoadGraph) -> void:
	var ap: Rect2 = WorldLayout.APRON
	g_concrete.rect(ap.position.x, ap.position.y, ap.end.x, ap.end.y, _yd, C_DECK)
	var dw: Rect2 = WorldLayout.APRON_DRIVEWAY
	asphalt.rect(dw.position.x, dw.position.y, dw.end.x, dw.end.y, _yd + 0.004, C_TAXI)
	for s: Dictionary in roads.segments:
		var kind: String = s["kind"]
		var p: PackedVector2Array = s["pts2"]
		if kind == "taxiway":
			_solid(p, 0.0, 0.22, C_YELLOW)
		elif kind == "runway":
			var a := p[0]
			var b := p[p.size() - 1]
			var d := (b - a).normalized()
			var hw: float = s["hw"]
			var length := a.distance_to(b)
			_solid(p, -(hw - 1.0), 0.6, C_WHITE)
			_solid(p, hw - 1.0, 0.6, C_WHITE)
			# centre line dashes between the numbers
			var t := 62.0
			while t + 24.0 <= length - 62.0:
				paint.orect(a + d * (t + 12.0), d, 12.0, 0.45, _ym, C_WHITE)
				t += 40.0
			for end_i in 2:
				var o: Vector2 = a if end_i == 0 else b
				var dd: Vector2 = d if end_i == 0 else -d
				var rr: Vector2 = Geom.right_of(dd)
				# threshold "piano keys"
				for k in 8:
					var lat := (float(k) - 3.5) * 2.5
					paint.orect(o + dd * 17.0 + rr * lat, dd, 11.0, 0.8, _ym, C_WHITE)
				# designator: 09 at the west end (heading east), 27 at the east end
				var txt := "09" if (dd.x > 0.0) else "27"
				_digit(txt[0], o + dd * 33.0 - rr * 5.2, rr, dd, 4.4, 10.0, 1.1)
				_digit(txt[1], o + dd * 33.0 + rr * 0.8, rr, dd, 4.4, 10.0, 1.1)
				# aiming point blocks
				paint.orect(o + dd * 95.0 - rr * 5.0, dd, 11.0, 1.6, _ym, C_WHITE)
				paint.orect(o + dd * 95.0 + rr * 5.0, dd, 11.0, 1.6, _ym, C_WHITE)
	var hp: Vector2 = WorldLayout.AIRPORT_HELIPAD
	g_concrete.disc(hp, WorldLayout.HELIPAD_RADIUS, _yd, C_DECK, 28)
	_helipad_marks(hp, WorldLayout.HELIPAD_RADIUS, _ym)
	_helipad_marks(WorldLayout.HARBOR_HELIPAD, WorldLayout.HARBOR_HELIPAD_RADIUS, _ym)


# ---------------------------------------------------------------------------------------------
# quays, piers, tram rails
# ---------------------------------------------------------------------------------------------

func _quay() -> void:
	var qx: float = WorldLayout.QUAY_X
	var qz: float = WorldLayout.QUAY_Z
	var qn: float = WorldLayout.QUAY_NORTH
	var qe: float = WorldLayout.QUAY_EAST
	var dx: float = qx + WorldLayout.QUAY_DECK_W
	var dz: float = qz - WorldLayout.QUAY_DECK_S
	g_concrete.rect(qx, qn, dx, qz, _yd, C_DECK)                    # docks deck (west)
	g_concrete.rect(dx, dz, qe, qz, _yd, C_DECK)                    # marina quay strip (south)
	g_concrete.rect(dx, 232.5, -254.5, dz, _yd, C_DECK)             # corner pad (harbour helipad)
	g_concrete.rect(-34.5, 232.5, qe, dz, _yd, C_DECK)              # east end
	var bot := -6.3
	g_concrete.wall(PackedVector2Array([Vector2(qx, qz), Vector2(qx, qn)]), _yd, bot, C_WALL, -1.0)
	g_concrete.wall(PackedVector2Array([Vector2(qx, qz), Vector2(qe, qz)]), _yd, bot, C_WALL, 1.0)
	g_concrete.wall(PackedVector2Array([Vector2(qx, qn), Vector2(dx, qn)]), _yd, bot, C_WALL, -1.0)
	g_concrete.wall(PackedVector2Array([Vector2(qe, 232.5), Vector2(qe, qz)]), _yd, bot, C_WALL, -1.0)
	# yellow safety line along the water edge
	paint.rect(qx + 0.45, qn + 0.45, qx + 0.70, qz - 0.45, _ym, C_YELLOW)
	paint.rect(qx + 0.45, qz - 0.70, qe - 0.45, qz - 0.45, _ym, C_YELLOW)


func _piers() -> void:
	var qz: float = WorldLayout.QUAY_Z
	var rz: float = WorldLayout.PIER_RAMP_Z
	var ez: float = WorldLayout.PIER_END_Z
	var py: float = WorldLayout.PIER_DECK_Y
	var hw: float = WorldLayout.PIER_HALF_W
	for px: float in WorldLayout.PIER_X:
		var x0 := px - hw
		var x1 := px + hw
		g_wood.quad(Vector3(x0, _yd, qz), Vector3(x1, _yd, qz), Vector3(x1, py, rz), Vector3(x0, py, rz), C_PLANKS_Z)
		g_wood.rect(x0, rz, x1, ez, py, C_PLANKS_Z)
		for sx: float in [x0, x1]:
			var nrm := Vector3(-1, 0, 0) if sx == x0 else Vector3(1, 0, 0)
			g_wood.quad(Vector3(sx, _yd, qz), Vector3(sx, py, rz), Vector3(sx, py - 0.35, rz), Vector3(sx, _yd - 0.35, qz), C_PILE, nrm)
			g_wood.quad(Vector3(sx, py, rz), Vector3(sx, py, ez), Vector3(sx, py - 0.35, ez), Vector3(sx, py - 0.35, rz), C_PILE, nrm)
		g_wood.quad(Vector3(x0, py, ez), Vector3(x1, py, ez), Vector3(x1, py - 0.35, ez), Vector3(x0, py - 0.35, ez), C_PILE, Vector3(0, 0, 1))
		var z := rz + 2.0
		while z <= ez + 0.01:
			for sx: float in [x0 + 0.1, x1 - 0.1]:
				g_wood.box(Vector3(sx, (py + 0.45 - 6.0) * 0.5, z - 0.3), Vector3(0.42, py + 0.45 + 6.0, 0.42), C_PILE)
			z += 5.5


func _rails(tram: PackedVector2Array) -> void:
	if tram.size() < 3:
		return
	for off: float in [-0.72, 0.72]:
		_solid(tram, off, 0.09, C_STEEL, 0.006)


# ---------------------------------------------------------------------------------------------
# output
# ---------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------
# footpaths (park gravel paths on the slab, dune trail following the terrain)
# ---------------------------------------------------------------------------------------------

func _footpaths(parent: Node3D) -> void:
	var terrain: Terrain = parent.get("terrain") as Terrain
	for fp: Array in WorldLayout.FOOTPATHS:
		var pts := WorldLayout.pts2(fp[0])
		var hw := float(fp[1]) * 0.5
		var on_ground := String(fp[2]) == "terrain"
		var col := C_TRAIL if on_ground else C_GRAVEL
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var r := Geom.right_of((b - a).normalized()) * hw
			var steps := maxi(1, int(ceil(a.distance_to(b) / 1.5)))
			for s in steps:
				var p0 := a.lerp(b, float(s) / float(steps))
				var p1 := a.lerp(b, float(s + 1) / float(steps))
				g_path.quad(_fp3(p0 - r, terrain, on_ground), _fp3(p1 - r, terrain, on_ground),
						_fp3(p1 + r, terrain, on_ground), _fp3(p0 + r, terrain, on_ground), col)
		# round joints / ends
		for p in pts:
			var hub := _fp3(p, terrain, on_ground)
			for k in 10:
				var t0 := TAU * float(k) / 10.0
				var t1 := TAU * float(k + 1) / 10.0
				g_path.tri(hub, _fp3(p + Vector2(cos(t0), sin(t0)) * hw, terrain, on_ground),
						_fp3(p + Vector2(cos(t1), sin(t1)) * hw, terrain, on_ground), col)


func _fp3(q: Vector2, terrain: Terrain, on_ground: bool) -> Vector3:
	if not on_ground:
		return Vector3(q.x, _ys + 0.02, q.y)
	var h := terrain.get_mesh_height(q.x, q.y) if terrain != null else Terrain.height(q.x, q.y)
	return Vector3(q.x, h + 0.06, q.y)


func _commit(parent: Node3D) -> void:
	var road_mat := ShaderMaterial.new()
	road_mat.shader = load(ROAD_SHADER) as Shader
	road_mat.set_shader_parameter("paint", 0.0)
	var paint_mat := ShaderMaterial.new()
	paint_mat.shader = load(ROAD_SHADER) as Shader
	paint_mat.set_shader_parameter("paint", 1.0)
	var ground_mat := ShaderMaterial.new()
	ground_mat.shader = load(GROUND_SHADER) as Shader
	var mesh := ArrayMesh.new()
	asphalt.add_surface(mesh, road_mat)
	paint.add_surface(mesh, paint_mat)
	g_concrete.add_surface(mesh, ground_mat)
	g_grass.add_surface(mesh, ground_mat)
	g_wood.add_surface(mesh, ground_mat)
	g_path.add_surface(mesh, ground_mat)
	var mi := MeshInstance3D.new()
	mi.name = "CityGround"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	tri_total = asphalt.tri_count() + paint.tri_count() + g_concrete.tri_count() + g_grass.tri_count() + g_wood.tri_count() + g_path.tri_count()
	var names := ["asphalt", "concrete", "grass", "wood"]
	var bufs: Array = [asphalt, g_concrete, g_grass, g_wood]
	for i in 4:
		var buf: MeshBuf = bufs[i]
		if buf.is_empty():
			continue
		var body := StaticBody3D.new()
		body.name = "CityBody_" + str(names[i])
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.set_meta("surface", names[i])
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(buf.v)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		parent.add_child(body)
