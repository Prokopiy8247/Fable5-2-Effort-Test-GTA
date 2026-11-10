extends RefCounted
## WORLD module helper: triangle soup builder (render mesh + collision faces + navmesh source).
## Godot front faces are clockwise; every helper takes the wanted normal and fixes the winding.

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()


func tri(a: Vector3, b: Vector3, cc: Vector3, col: Color, nrm: Vector3 = Vector3.UP) -> void:
	var g := (b - a).cross(cc - a)
	if g.length_squared() < 0.0000001:
		return
	if g.dot(nrm) > 0.0:
		v.append(a); v.append(cc); v.append(b)
	else:
		v.append(a); v.append(b); v.append(cc)
	var fn := -g.normalized()
	if fn.dot(nrm) < 0.0:
		fn = -fn
	n.append(fn); n.append(fn); n.append(fn)
	c.append(col); c.append(col); c.append(col)


## a,b,c,d go around the perimeter.
func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color, nrm: Vector3 = Vector3.UP) -> void:
	tri(a, b, cc, col, nrm)
	tri(a, cc, d, col, nrm)


## Axis-aligned horizontal rectangle.
func rect(x0: float, z0: float, x1: float, z1: float, y: float, col: Color) -> void:
	quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), col)


## Ribbon between two polylines with the same point count (flat or sloped).
func strip(l: PackedVector2Array, r: PackedVector2Array, yl: float, yr: float, col: Color, nrm: Vector3 = Vector3.UP) -> void:
	for i in range(1, l.size()):
		var a := Vector3(l[i - 1].x, yl, l[i - 1].y)
		var b := Vector3(l[i].x, yl, l[i].y)
		var cc := Vector3(r[i].x, yr, r[i].y)
		var d := Vector3(r[i - 1].x, yr, r[i - 1].y)
		if nrm == Vector3.ZERO:
			var h := Vector3(a.x - d.x, 0.0, a.z - d.z)
			if yl < yr:
				h = -h
			quad(a, b, cc, d, col, h.normalized() + Vector3(0, 0.01, 0))
		else:
			quad(a, b, cc, d, col, nrm)


## Convex polygon (outline in order) at height y.
func poly(outline: PackedVector2Array, y: float, col: Color) -> void:
	var cnt := outline.size()
	if cnt < 3:
		return
	var centre := Vector2.ZERO
	for p in outline:
		centre += p
	centre /= float(cnt)
	var c3 := Vector3(centre.x, y, centre.y)
	for i in cnt:
		var a := outline[i]
		var b := outline[(i + 1) % cnt]
		tri(c3, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), col)


## Skirt around a closed outline: top ring at y_top, bottom ring pushed outward by `run` at y_bot.
func skirt(outline: PackedVector2Array, y_top: float, y_bot: float, run: float, col: Color) -> void:
	var cnt := outline.size()
	var centre := Vector2.ZERO
	for p in outline:
		centre += p
	centre /= float(cnt)
	for i in cnt:
		var a := outline[i]
		var b := outline[(i + 1) % cnt]
		var e := b - a
		if e.length() < 0.001:
			continue
		var o := Vector2(-e.y, e.x).normalized()
		if o.dot((a + b) * 0.5 - centre) < 0.0:
			o = -o
		var a2 := a + o * run
		var b2 := b + o * run
		quad(Vector3(a.x, y_top, a.y), Vector3(b.x, y_top, b.y), Vector3(b2.x, y_bot, b2.y), Vector3(a2.x, y_bot, a2.y),
				col, Vector3(o.x, 0.35, o.y))


func disc(centre: Vector2, radius: float, y: float, col: Color, sides: int = 20) -> void:
	var ring := PackedVector2Array()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		ring.append(centre + Vector2(cos(a), sin(a)) * radius)
	poly(ring, y, col)


## Flat ring (annulus) - helipad circles.
func ring(centre: Vector2, r0: float, r1: float, y: float, col: Color, sides: int = 28) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var p0 := centre + d0 * r0
		var p1 := centre + d1 * r0
		var p2 := centre + d1 * r1
		var p3 := centre + d0 * r1
		quad(Vector3(p0.x, y, p0.y), Vector3(p1.x, y, p1.y), Vector3(p2.x, y, p2.y), Vector3(p3.x, y, p3.y), col)


## Sloped skirt along an OPEN path: top edge on the path at y_top, bottom edge pushed away from
## `inside` by `run` at y_bot (kerbs of corner patches).
func path_skirt(path: PackedVector2Array, inside: Vector2, y_top: float, y_bot: float, run: float, col: Color) -> void:
	var cnt := path.size()
	if cnt < 2:
		return
	var low := PackedVector2Array()
	low.resize(cnt)
	for i in cnt:
		var o := path[i] - inside
		var e: Vector2 = path[mini(i + 1, cnt - 1)] - path[maxi(i - 1, 0)]
		var nrm := Vector2(-e.y, e.x).normalized()
		if nrm.dot(o) < 0.0:
			nrm = -nrm
		low[i] = path[i] + nrm * run
	for i in range(1, cnt):
		var a := path[i - 1]
		var b := path[i]
		var out_dir := (low[i - 1] + low[i]) * 0.5 - (a + b) * 0.5
		quad(Vector3(a.x, y_top, a.y), Vector3(b.x, y_top, b.y), Vector3(low[i].x, y_bot, low[i].y),
				Vector3(low[i - 1].x, y_bot, low[i - 1].y), col, Vector3(out_dir.x, 0.35, out_dir.y))


## Fan of triangles from `hub` over an open path (flat, at height y).
func fan(hub: Vector2, path: PackedVector2Array, y: float, col: Color) -> void:
	var h3 := Vector3(hub.x, y, hub.y)
	for i in range(1, path.size()):
		tri(h3, Vector3(path[i - 1].x, y, path[i - 1].y), Vector3(path[i].x, y, path[i].y), col)


## Oriented flat rectangle: centre, half extent along `ax` (unit XZ vector) and across it.
func orect(centre: Vector2, ax: Vector2, half_along: float, half_across: float, y: float, col: Color) -> void:
	var s := Vector2(-ax.y, ax.x)
	var a := centre - ax * half_along - s * half_across
	var b := centre + ax * half_along - s * half_across
	var cc := centre + ax * half_along + s * half_across
	var d := centre - ax * half_along + s * half_across
	quad(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(cc.x, y, cc.y), Vector3(d.x, y, d.y), col)


## Vertical wall along an XZ path, facing `side` (+1 = right of the path direction).
func wall(path: PackedVector2Array, y_top: float, y_bot: float, col: Color, side: float = 1.0) -> void:
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var e := b - a
		if e.length() < 0.001:
			continue
		var o := Vector2(-e.y, e.x).normalized() * side
		quad(Vector3(a.x, y_top, a.y), Vector3(b.x, y_top, b.y), Vector3(b.x, y_bot, b.y), Vector3(a.x, y_bot, a.y),
				col, Vector3(o.x, 0.0, o.y))


## Axis-aligned box (top and four sides; bottom optional).
func box(centre: Vector3, size: Vector3, col: Color, with_bottom: bool = false) -> void:
	var h := size * 0.5
	var x0 := centre.x - h.x
	var x1 := centre.x + h.x
	var y0 := centre.y - h.y
	var y1 := centre.y + h.y
	var z0 := centre.z - h.z
	var z1 := centre.z + h.z
	quad(Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), col, Vector3.UP)
	if with_bottom:
		quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), col, Vector3.DOWN)
	quad(Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3(x0, y0, z0), col, Vector3.FORWARD)
	quad(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3(x0, y0, z1), col, Vector3.BACK)
	quad(Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3(x0, y0, z0), col, Vector3.LEFT)
	quad(Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0), col, Vector3.RIGHT)


func tri_count() -> int:
	@warning_ignore("integer_division")
	return v.size() / 3


func is_empty() -> bool:
	return v.is_empty()


func add_surface(mesh: ArrayMesh, material: Material) -> void:
	if v.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
