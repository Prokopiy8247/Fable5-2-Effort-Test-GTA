class_name MinimapWorldLayer
extends Node2D
## Static map geometry (coast, lots, decks, roads, runway, tram line, helipads) in map space
## (x = world X, y = world Z, metres), baked ONCE into a single vertex-coloured ArrayMesh and
## drawn with one draw call. The owner only changes this node's position / rotation / scale, so
## nothing is rebuilt while the map pans, zooms or rotates. Edges carry a thin alpha feather so
## the map stays smooth without MSAA. Used by the HUD minimap and by the full map screen.
## It is a Node2D on purpose: a Control is culled by its own rect, so a zero-size Control layer
## disappears as soon as its origin (the map origin) is off screen.

const SEA := Color(0.047, 0.118, 0.2)
const LAND := Color(0.13, 0.235, 0.31)
const SAND := Color(0.72, 0.66, 0.5)
const CASING := Color(0.03, 0.07, 0.12, 0.95)
const DECK := Color(0.3, 0.37, 0.44)
const PIER := Color(0.55, 0.45, 0.33)
const TRAM := Color(0.37, 0.84, 0.8, 0.85)
const ROAD_COLORS := {
	"arterial": Color(0.93, 0.95, 0.97), "street": Color(0.76, 0.81, 0.87), "alley": Color(0.55, 0.62, 0.7),
	"dirt": Color(0.7, 0.6, 0.45), "runway": Color(0.36, 0.42, 0.5), "taxiway": Color(0.3, 0.36, 0.44),
}
const ZONE_COLORS := {
	"office": Color(0.22, 0.34, 0.45), "apartment": Color(0.24, 0.35, 0.44), "house": Color(0.25, 0.38, 0.4),
	"storefront": Color(0.27, 0.37, 0.48), "warehouse": Color(0.23, 0.3, 0.38), "hangar": Color(0.22, 0.29, 0.37),
	"parking": Color(0.17, 0.26, 0.34), "park": Color(0.16, 0.4, 0.33), "plaza": Color(0.3, 0.38, 0.45),
	"landmark": Color(0.12, 0.47, 0.47),
}
const DISC_SEGMENTS := 10

var data: UiMapData = null
var detail: bool = false          ## full map: thicker casings, finer feather
var _version: int = -1
var _mesh: ArrayMesh = null
var _verts: PackedVector2Array = PackedVector2Array()
var _cols: PackedColorArray = PackedColorArray()
var _feather: float = 0.7
var _unit: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	for i in DISC_SEGMENTS + 1:
		var a := TAU * float(i) / float(DISC_SEGMENTS)
		_unit.append(Vector2(cos(a), sin(a)))


func set_data(d: UiMapData) -> void:
	data = d
	_version = -1
	queue_redraw()


## Call now and then: rebuilds only when the map data was refreshed.
func check_version() -> void:
	if data != null and data.version != _version:
		queue_redraw()


## Number of triangles in the baked mesh (0 = nothing to draw).
func get_triangle_count() -> int:
	if _mesh == null or _mesh.get_surface_count() == 0:
		return 0
	@warning_ignore("integer_division")
	return _mesh.surface_get_array_len(0) / 3


func _draw() -> void:
	if data == null:
		return
	if _version != data.version:
		_rebuild()
	if _mesh != null:
		draw_mesh(_mesh, null)


# --- baking ----------------------------------------------------------------------------------------

func _rebuild() -> void:
	_version = data.version
	_mesh = null
	_verts = PackedVector2Array()
	_cols = PackedColorArray()
	_feather = 0.45 if detail else 0.7
	for poly in data.coast:
		var ring := poly.duplicate()
		ring.append(poly[0])
		_polyline(ring, SAND, 10.0, true)
		if not _polygon(poly, LAND):
			_polyline(ring, LAND.lightened(0.2), 4.0, true)
	for r in data.water:
		_polygon(UiMapData.rect_poly(r), SEA)
	for lot in data.lots:
		var zc: Color = ZONE_COLORS.get(str(lot["zone"]), ZONE_COLORS["storefront"])
		if str(lot["landmark"]) != "":
			zc = ZONE_COLORS["landmark"]
		_polygon(lot["poly"], zc)
	for dk in data.decks:
		_polygon(UiMapData.rect_poly(dk), DECK)
	for pr in data.piers:
		_polygon(UiMapData.rect_poly(pr), PIER)
	var casing := 3.5 if detail else 2.5
	for road in data.roads:
		_polyline(road["pts"], CASING, float(road["width"]) + casing, false)
	for road in data.roads:
		var kind := str(road["kind"])
		var col: Color = ROAD_COLORS.get(kind, ROAD_COLORS["street"])
		_polyline(road["pts"], col, float(road["width"]), true)
		if kind == "runway":
			_dashes(road["pts"], Color(1, 1, 1, 0.8), 2.0, 14.0, 12.0)
	if data.transit.size() >= 2:
		_dashes(data.transit, TRAM, 1.6, 7.0, 5.0)
	for h in data.helipads:
		var hc := Vector2(h.x, h.y)
		var mark := Color(1, 1, 1, 0.78)
		_disc(hc, h.z, Color(0.2, 0.27, 0.34), true)
		_ring(hc, h.z * 0.8, 1.3, mark)
		_segment(hc + Vector2(-0.35, -0.45) * h.z, hc + Vector2(-0.35, 0.45) * h.z, 1.3, mark, false)
		_segment(hc + Vector2(0.35, -0.45) * h.z, hc + Vector2(0.35, 0.45) * h.z, 1.3, mark, false)
		_segment(hc + Vector2(-0.35, 0.0) * h.z, hc + Vector2(0.35, 0.0) * h.z, 1.3, mark, false)
	if _verts.size() >= 3:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _verts
		arrays[Mesh.ARRAY_COLOR] = _cols
		_mesh = ArrayMesh.new()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_verts = PackedVector2Array()
	_cols = PackedColorArray()
	# explicit culling rect = the whole map (cheap, and independent of how the mesh AABB is derived)
	RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, data.bounds.grow(80.0))


func _tri(a: Vector2, b: Vector2, c: Vector2, ca: Color, cb: Color, cc: Color) -> void:
	_verts.append(a)
	_verts.append(b)
	_verts.append(c)
	_cols.append(ca)
	_cols.append(cb)
	_cols.append(cc)


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_tri(a, b, c, ca, cb, cc)
	_tri(a, c, d, ca, cc, cd)


## Filled polygon (any simple polygon). Returns false if it could not be triangulated.
func _polygon(poly: PackedVector2Array, col: Color) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	if n == 3:
		_tri(poly[0], poly[1], poly[2], col, col, col)
		return true
	if n == 4:
		_quad(poly[0], poly[1], poly[2], poly[3], col, col, col, col)
		return true
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return false
	for i in range(0, idx.size() - 2, 3):
		_tri(poly[idx[i]], poly[idx[i + 1]], poly[idx[i + 2]], col, col, col)
	return true


## Thick segment with an optional alpha feather on both long edges.
func _segment(a: Vector2, b: Vector2, width: float, col: Color, feather: bool) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var n := Vector2(-d.y, d.x) / length * (width * 0.5)
	_quad(a + n, b + n, b - n, a - n, col, col, col, col)
	if feather:
		var f := n.normalized() * _feather
		var clear := Color(col.r, col.g, col.b, 0.0)
		_quad(a + n + f, b + n + f, b + n, a + n, clear, clear, col, col)
		_quad(a - n, b - n, b - n - f, a - n - f, col, col, clear, clear)


func _disc(c: Vector2, radius: float, col: Color, feather: bool) -> void:
	var clear := Color(col.r, col.g, col.b, 0.0)
	var outer := radius + _feather
	for i in DISC_SEGMENTS:
		var u0 := _unit[i]
		var u1 := _unit[i + 1]
		_tri(c, c + u0 * radius, c + u1 * radius, col, col, col)
		if feather:
			_quad(c + u0 * radius, c + u0 * outer, c + u1 * outer, c + u1 * radius, col, clear, clear, col)


func _ring(c: Vector2, radius: float, width: float, col: Color) -> void:
	var r0 := radius - width * 0.5
	var r1 := radius + width * 0.5
	for i in DISC_SEGMENTS:
		var u0 := _unit[i]
		var u1 := _unit[i + 1]
		_quad(c + u0 * r0, c + u0 * r1, c + u1 * r1, c + u1 * r0, col, col, col, col)


## Thick polyline: one quad per segment, discs at the ends (round caps) and at real corners.
func _polyline(pts: PackedVector2Array, col: Color, width: float, feather: bool) -> void:
	var n := pts.size()
	if n < 2:
		return
	var closed := pts[0].distance_squared_to(pts[n - 1]) < 0.0001
	var half := width * 0.5
	for i in n - 1:
		_segment(pts[i], pts[i + 1], width, col, feather)
	for i in n:
		var is_end := i == 0 or i == n - 1
		if is_end and not closed:
			_disc(pts[i], half, col, feather)
			continue
		if is_end and i == n - 1:
			continue            # closed: the joint is handled at index 0
		var prev := pts[n - 2] if i == 0 else pts[i - 1]
		var next := pts[i + 1]
		var d0 := (pts[i] - prev).normalized()
		var d1 := (next - pts[i]).normalized()
		if d0.dot(d1) < 0.9995:
			_disc(pts[i], half, col, feather)


func _dashes(pts: PackedVector2Array, col: Color, width: float, dash: float, gap: float) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var length := a.distance_to(b)
		if length < 1.0:
			continue
		var dir := (b - a) / length
		var t := gap * 0.5
		while t + dash <= length:
			_segment(a + dir * t, a + dir * (t + dash), width, col, false)
			t += dash + gap
