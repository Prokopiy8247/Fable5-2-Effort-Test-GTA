class_name GroundBuilder
extends RefCounted
## Raised city blocks: lot base surface, sidewalks with rounded kerb corners, kerb faces,
## retaining/sea walls on non-street sides and the matching collision shapes.

# district -> [palette colour, ground pattern]
const LOT_GROUND := {
	"downtown": ["concrete", 5.0], "midtown": ["concrete_light", 5.0], "industrial": ["asphalt_light", 6.0],
	"residential": ["grass", 3.0], "park": ["grass", 3.0], "beachfront": ["concrete_light", 5.0],
	"marina": ["concrete", 5.0], "beach": ["wood_light", 2.0], "port": ["asphalt_light", 6.0],
	"airfield": ["grass_dry", 3.0], "verge": ["sidewalk", 1.0],
}
const WALL_DEPTH := {"P_w:S": -1.3, "P_e:S": -7.6, "PORT:S": -7.6, "PORT:E": -5.0, "AIR:E": -5.0}

static func build(layout: CityLayout, parent: Node3D, material: Material) -> StaticBody3D:
	var corners := {}
	for id in layout.nodes.keys():
		var r := layout.node_rect(layout.nodes[id])
		for p: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			corners[_key(p)] = true
	var body := StaticBody3D.new()
	body.name = "CityGround"
	body.collision_layer = Phys.WORLD
	body.collision_mask = 0
	body.set_meta("surface", &"concrete")
	parent.add_child(body)
	# plateau under all streets (top at y = 0), thick enough to be the quay wall too
	_add_box(body, Vector3(Terrain.HILL_EDGE, -12.0, -300.0), Vector3(Terrain.EAST_X, 0.0, Terrain.COAST_Z))
	_add_box(body, Vector3(-300.0, -12.0, Terrain.HILL_EDGE), Vector3(Terrain.HILL_EDGE, 0.0, Terrain.COAST_Z))
	var h := CityLayout.CURB_H
	var side_col := GeoBuf.pal("sidewalk")
	var kerb_col := GeoBuf.pal("curb")
	var wall_col := GeoBuf.pal("concrete_dark")
	for b in layout.blocks:
		var buf := GeoBuf.new()
		var r: Rect2 = b["rect"]
		var k := layout.kerb_rect(b)
		var s: Dictionary = b["sides"]
		var ground: Array = LOT_GROUND.get(b["district"], ["concrete", 0.0])
		buf.rect_up(r.position.x, r.position.y, r.end.x, r.end.y, h, GeoBuf.pal(ground[0]), ground[1])
		if r.size.x > 0.01 and r.size.y > 0.01:
			_add_box(body, Vector3(r.position.x, -0.6, r.position.y), Vector3(r.end.x, h, r.end.y))
		# which kerb corners are rounded (they coincide with a junction corner)
		var rounded := {}
		for cx: int in [-1, 1]:
			for cz: int in [-1, 1]:
				var p := Vector2(k.position.x if cx < 0 else k.end.x, k.position.y if cz < 0 else k.end.y)
				var both: bool = s["W" if cx < 0 else "E"] and s["N" if cz < 0 else "S"]
				rounded[Vector2i(cx, cz)] = both and corners.has(_key(p))
		var rr := CityLayout.CORNER_R
		# --- sidewalk strips + kerb faces on street sides
		if s["N"]:
			buf.rect_up(r.position.x, k.position.y, r.end.x, r.position.y, h, side_col, 1.0)
			_add_box(body, Vector3(r.position.x, -0.6, k.position.y), Vector3(r.end.x, h, r.position.y))
			var xa := k.position.x + (rr if rounded[Vector2i(-1, -1)] else 0.0)
			var xb := k.end.x - (rr if rounded[Vector2i(1, -1)] else 0.0)
			buf.wall(Vector2(xa, k.position.y), Vector2(xb, k.position.y), 0.0, h, Vector2(0, -1), kerb_col)
		if s["S"]:
			buf.rect_up(r.position.x, r.end.y, r.end.x, k.end.y, h, side_col, 1.0)
			_add_box(body, Vector3(r.position.x, -0.6, r.end.y), Vector3(r.end.x, h, k.end.y))
			var xa2 := k.position.x + (rr if rounded[Vector2i(-1, 1)] else 0.0)
			var xb2 := k.end.x - (rr if rounded[Vector2i(1, 1)] else 0.0)
			buf.wall(Vector2(xa2, k.end.y), Vector2(xb2, k.end.y), 0.0, h, Vector2(0, 1), kerb_col)
		if s["W"]:
			buf.rect_up(k.position.x, r.position.y, r.position.x, r.end.y, h, side_col, 1.0)
			_add_box(body, Vector3(k.position.x, -0.6, r.position.y), Vector3(r.position.x, h, r.end.y))
			var za := k.position.y + (rr if rounded[Vector2i(-1, -1)] else 0.0)
			var zb := k.end.y - (rr if rounded[Vector2i(-1, 1)] else 0.0)
			buf.wall(Vector2(k.position.x, za), Vector2(k.position.x, zb), 0.0, h, Vector2(-1, 0), kerb_col)
		if s["E"]:
			buf.rect_up(r.end.x, r.position.y, k.end.x, r.end.y, h, side_col, 1.0)
			_add_box(body, Vector3(r.end.x, -0.6, r.position.y), Vector3(k.end.x, h, r.end.y))
			var za2 := k.position.y + (rr if rounded[Vector2i(1, -1)] else 0.0)
			var zb2 := k.end.y - (rr if rounded[Vector2i(1, 1)] else 0.0)
			buf.wall(Vector2(k.end.x, za2), Vector2(k.end.x, zb2), 0.0, h, Vector2(1, 0), kerb_col)
		# --- corner pieces
		for cx: int in [-1, 1]:
			for cz: int in [-1, 1]:
				var sx_side: bool = s["W" if cx < 0 else "E"]
				var sz_side: bool = s["N" if cz < 0 else "S"]
				if not (sx_side and sz_side):
					continue
				var inner := Vector2(r.position.x if cx < 0 else r.end.x, r.position.y if cz < 0 else r.end.y)
				var outer := Vector2(k.position.x if cx < 0 else k.end.x, k.position.y if cz < 0 else k.end.y)
				var poly := PackedVector2Array()
				poly.append(inner)
				poly.append(Vector2(inner.x, outer.y))
				if rounded[Vector2i(cx, cz)]:
					var cen := outer + Vector2(-cx, -cz) * rr
					var prev := Vector2.ZERO
					for i in 7:
						var a := deg_to_rad(90.0 * float(i) / 6.0)
						var pt := cen + Vector2(float(cx) * rr * sin(a), float(cz) * rr * cos(a))
						poly.append(pt)
						if i > 0:
							buf.wall(prev, pt, 0.0, h, ((prev + pt) * 0.5 - cen), kerb_col)
						prev = pt
				else:
					poly.append(outer)
				poly.append(Vector2(outer.x, inner.y))
				buf.poly_up(poly, h, side_col, 1.0)
				_add_prism(body, poly, -0.6, h)
		# --- walls on sides that do not face a street
		for side: String in ["N", "S", "E", "W"]:
			if s[side]:
				continue
			var depth: float = WALL_DEPTH.get(b["id"] + ":" + side, -0.5)
			match side:
				"N": buf.wall(Vector2(k.position.x, k.position.y), Vector2(k.end.x, k.position.y), depth, h, Vector2(0, -1), wall_col)
				"S": buf.wall(Vector2(k.position.x, k.end.y), Vector2(k.end.x, k.end.y), depth, h, Vector2(0, 1), wall_col)
				"W": buf.wall(Vector2(k.position.x, k.position.y), Vector2(k.position.x, k.end.y), depth, h, Vector2(-1, 0), wall_col)
				"E": buf.wall(Vector2(k.end.x, k.position.y), Vector2(k.end.x, k.end.y), depth, h, Vector2(1, 0), wall_col)
		var mi := buf.instance(parent, "Block_" + String(b["id"]), material)
		if mi:
			mi.set_meta("block", b["id"])
	return body

static func _key(p: Vector2) -> Vector2i:
	return Vector2i(int(round(p.x * 10.0)), int(round(p.y * 10.0)))

static func _add_box(body: StaticBody3D, lo: Vector3, hi: Vector3) -> void:
	var size := hi - lo
	if size.x < 0.01 or size.z < 0.01:
		return
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = (lo + hi) * 0.5
	body.add_child(cs)

static func _add_prism(body: StaticBody3D, poly: PackedVector2Array, y0: float, y1: float) -> void:
	var pts := PackedVector3Array()
	for p in poly:
		pts.append(Vector3(p.x, y0, p.y))
		pts.append(Vector3(p.x, y1, p.y))
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	cs.shape = shape
	body.add_child(cs)

## Small ramp over the kerb so vehicles can enter lots / driveways smoothly.
## `pos` = point on the kerb line at road level, `dir` = unit vector pointing into the lot.
static func add_driveway(parent: Node3D, body: StaticBody3D, buf: GeoBuf, pos: Vector3, dir: Vector3, width: float, length := 1.6) -> void:
	var h := CityLayout.CURB_H
	var side := Vector3(-dir.z, 0.0, dir.x) * (width * 0.5)
	var a := pos - side
	var b := pos + side
	var c := pos + side + dir * length + Vector3(0, h + 0.012, 0)
	var d := pos - side + dir * length + Vector3(0, h + 0.012, 0)
	var nrm := (b - a).cross(d - a).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	buf.quad(a + Vector3(0, 0.012, 0), b + Vector3(0, 0.012, 0), c, d, nrm, GeoBuf.pal("concrete_light"), 0.0)
	# collision wedge
	var pts := PackedVector3Array([a + Vector3(0, -0.3, 0), b + Vector3(0, -0.3, 0), a, b, c, d,
		c + Vector3(0, -0.6, 0), d + Vector3(0, -0.6, 0)])
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	cs.shape = shape
	body.add_child(cs)
