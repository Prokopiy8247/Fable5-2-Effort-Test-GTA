class_name GeoBuf
extends RefCounted
## Tiny triangle accumulator for generated world geometry (ground, roads, lots, walls).
## Handles Godot's clockwise front-face winding: callers only say which way a face looks.

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()
var use_uv2 := false

func size() -> int:
	return v.size()

func tri(a: Vector3, b: Vector3, cc: Vector3, nrm: Vector3, col: Color, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2,
		uv2v := Vector2.ZERO) -> void:
	if (b - a).cross(cc - a).dot(nrm) > 0.0:
		var tmp := b
		b = cc
		cc = tmp
		var tu := uv_b
		uv_b = uv_c
		uv_c = tu
	v.append(a); v.append(b); v.append(cc)
	n.append(nrm); n.append(nrm); n.append(nrm)
	c.append(col); c.append(col); c.append(col)
	uv.append(uv_a); uv.append(uv_b); uv.append(uv_c)
	if use_uv2:
		uv2.append(uv2v); uv2.append(uv2v); uv2.append(uv2v)

## Flat-coloured triangle with constant (pattern, wet) uv.
func tri_c(a: Vector3, b: Vector3, cc: Vector3, nrm: Vector3, col: Color, pat := 0.0, wet := 1.0) -> void:
	var u := Vector2(pat, wet)
	tri(a, b, cc, nrm, col, u, u, u)

func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, nrm: Vector3, col: Color, pat := 0.0, wet := 1.0) -> void:
	tri_c(a, b, cc, nrm, col, pat, wet)
	tri_c(a, cc, d, nrm, col, pat, wet)

## Horizontal rectangle facing up.
func rect_up(x0: float, z0: float, x1: float, z1: float, y: float, col: Color, pat := 0.0, wet := 1.0) -> void:
	if x1 - x0 < 0.001 or z1 - z0 < 0.001:
		return
	quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP, col, pat, wet)

## Convex polygon (XZ points) facing up, fanned from the first point.
func poly_up(pts: PackedVector2Array, y: float, col: Color, pat := 0.0, wet := 1.0) -> void:
	for i in range(1, pts.size() - 1):
		tri_c(Vector3(pts[0].x, y, pts[0].y), Vector3(pts[i].x, y, pts[i].y), Vector3(pts[i + 1].x, y, pts[i + 1].y),
			Vector3.UP, col, pat, wet)

## Vertical wall between two XZ points from y0 to y1, facing `out` (XZ direction).
func wall(p0: Vector2, p1: Vector2, y0: float, y1: float, out: Vector2, col: Color, pat := 0.0, wet := 1.0) -> void:
	var nrm := Vector3(out.x, 0.0, out.y).normalized()
	quad(Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y), nrm, col, pat, wet)

## Axis-aligned box (all six faces).
func box(lo: Vector3, hi: Vector3, col: Color, pat := 0.0, wet := 1.0, top_col: Variant = null) -> void:
	var tc: Color = col if top_col == null else top_col
	rect_up(lo.x, lo.z, hi.x, hi.z, hi.y, tc, pat, wet)
	quad(Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3.DOWN, col, pat, wet)
	wall(Vector2(lo.x, lo.z), Vector2(hi.x, lo.z), lo.y, hi.y, Vector2(0, -1), col, pat, wet)
	wall(Vector2(lo.x, hi.z), Vector2(hi.x, hi.z), lo.y, hi.y, Vector2(0, 1), col, pat, wet)
	wall(Vector2(lo.x, lo.z), Vector2(lo.x, hi.z), lo.y, hi.y, Vector2(-1, 0), col, pat, wet)
	wall(Vector2(hi.x, lo.z), Vector2(hi.x, hi.z), lo.y, hi.y, Vector2(1, 0), col, pat, wet)

func commit(material: Material) -> ArrayMesh:
	if v.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = uv
	if use_uv2:
		arr[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, material)
	return mesh

func instance(parent: Node3D, node_name: String, material: Material, shadows := false) -> MeshInstance3D:
	var mesh := commit(material)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## Linear colour of a palette entry (generated meshes store linear vertex colours).
static func pal(color_name: String) -> Color:
	return Assets.color(color_name).srgb_to_linear()
