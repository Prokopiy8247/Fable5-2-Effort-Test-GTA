extends RefCounted
## PropSystem helper (WORLD DRESSING): merged catalogue of every manifest*.json under
## models/props, models/nature and models/misc, plus lazily extracted render meshes, part meshes,
## markers and collision shapes per asset id.
##
## Nothing here touches the scene tree. A GLB is loaded and instantiated once (off-tree) the first
## time an id is used, its MeshInstance3D / marker transforms are read relative to the file root and
## the instance is freed again. Multi-part assets are merged into one ArrayMesh (one surface per
## material) so they can feed a MultiMesh.

const DIRS := {
	"props": "res://gta/generated/models/props/",
	"nature": "res://gta/generated/models/nature/",
	"misc": "res://gta/generated/models/misc/",
}

## Thin vertical things: idle collider = a cylinder around the pole only (arms / plates are free).
const POLES := {
	"street_lamp_a": 0.15, "street_lamp_b": 0.14, "traffic_light": 0.18, "traffic_light_ped": 0.09,
	"sign_stop": 0.06, "sign_yield": 0.06, "sign_speed": 0.06, "sign_oneway": 0.06, "sign_parking": 0.06,
	"sign_street": 0.07, "sign_noentry": 0.06, "power_pole": 0.16, "windsock": 0.12, "rail_post": 0.14,
	"parking_meter": 0.07, "delineator": 0.12, "lifebuoy_stand": 0.08,
}

## Convex hulls with more points than this are simplified (slow V-HACD path, rare for props).
const MAX_HULL_POINTS := 160

const SURFACE_BY_CATEGORY := {
	"tree": "wood", "log": "wood", "rock": "concrete", "cliff": "concrete", "shrub": "foliage",
	"groundcover": "foliage", "underwater": "concrete", "harbour": "metal", "transit": "metal",
	"set_piece": "wood", "beach": "wood", "park": "concrete", "airport": "metal", "activities": "wood",
	"police": "metal", "service": "metal",
}

var defs: Dictionary = {}           ## id -> normalised manifest entry (see _normalise)
var errors: PackedStringArray = []
var load_ms: int = 0                ## time spent loading / extracting GLBs (boot profile)
var _load_us: int = 0

var _cache: Dictionary = {}         ## id -> extracted data (see _extract)
var _shape_cache: Dictionary = {}   ## "kind|id" -> Array of [Shape3D, Transform3D]
var _merge_cache: Dictionary = {}   ## "id|excluded names" -> {mesh, xf}


func load_manifests() -> void:
	for source: String in DIRS:
		var dir: String = DIRS[source]
		var files := DirAccess.get_files_at(dir)
		for f in files:
			if not (f.begins_with("manifest") and f.ends_with(".json")):
				continue
			var fa := FileAccess.open(dir + f, FileAccess.READ)
			if fa == null:
				errors.append("cannot open " + dir + f)
				continue
			var data: Variant = JSON.parse_string(fa.get_as_text())
			if typeof(data) != TYPE_DICTIONARY:
				errors.append("not a JSON object: " + dir + f)
				continue
			for key: String in (data as Dictionary):
				var arr: Variant = (data as Dictionary)[key]
				if typeof(arr) != TYPE_ARRAY:
					continue
				for e: Variant in (arr as Array):
					if typeof(e) != TYPE_DICTIONARY or not (e as Dictionary).has("id") or not (e as Dictionary).has("file"):
						continue
					var d := _normalise(e as Dictionary, source, dir)
					if not defs.has(d["id"]):
						defs[d["id"]] = d


func has(id: String) -> bool:
	return defs.has(id)


func get_def(id: String) -> Dictionary:
	return defs.get(id, {})


func _v3(a: Variant, fallback: Vector3) -> Vector3:
	if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


func _normalise(e: Dictionary, source: String, dir: String) -> Dictionary:
	var d := e.duplicate(true)
	d["id"] = String(e["id"])
	d["source"] = source
	d["path"] = dir + String(e["file"])
	var size := _v3(e.get("size", null), Vector3.ONE)
	d["size_v"] = size
	var center := Vector3(0.0, size.y * 0.5, 0.0)
	if e.has("center"):
		center = _v3(e["center"], center)
	elif e.has("aabb_min") and e.has("aabb_max"):
		var mn := _v3(e["aabb_min"], Vector3.ZERO)
		var mx := _v3(e["aabb_max"], size)
		center = (mn + mx) * 0.5
		size = mx - mn
		d["size_v"] = size
	d["center_v"] = center
	var cat := String(e.get("category", ""))
	d["category"] = cat
	d["physics"] = String(e.get("physics", "static"))
	var mass := float(e.get("mass", 0.0))
	if mass <= 0.0:
		mass = clampf(size.x * size.y * size.z * 120.0, 5.0, 3000.0)
	d["mass"] = mass
	var surf := String(e.get("surface", ""))
	if surf == "":
		surf = String(SURFACE_BY_CATEGORY.get(cat, "concrete"))
		if cat == "tree" and String(e.get("id", "")).begins_with("palm"):
			surf = "wood"
	d["surface"] = surf
	var vis := float(e.get("vis_range", e.get("visibility_end", 0.0)))
	if vis <= 0.0:
		vis = 260.0 if size.y > 2.6 else (120.0 if size.y > 1.0 else 90.0)
		if source == "nature" and (cat == "tree" or cat == "rock" or cat == "cliff"):
			vis = 600.0
	d["vis"] = vis
	d["collision"] = String(e.get("collision", ""))
	return d


# ---------------------------------------------------------------------------------------------
# meshes, parts, markers
# ---------------------------------------------------------------------------------------------

## Raw extraction: {"parts": {name: [mesh, xf, overrides]}, "order": [names], "markers": {name: xf},
## "aabb": AABB of every mesh in file-root space}. Empty dictionary if the GLB does not load.
func _extract(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var out := {}
	var d: Dictionary = defs.get(id, {})
	if d.is_empty():
		_cache[id] = out
		return out
	var path: String = d["path"]
	var t0 := Time.get_ticks_usec()
	out = extract_scene(path)
	_load_us += Time.get_ticks_usec() - t0
	load_ms = _load_us / 1000
	if out.is_empty():
		errors.append("asset failed to load: " + path)
	_cache[id] = out
	return out


static func extract_scene(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var ps := load(path) as PackedScene
	if ps == null:
		return {}
	var root := ps.instantiate()
	if root == null:
		return {}
	var parts := {}
	var order: Array[String] = []
	var markers := {}
	var aabb := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var n: Node = it[0]
		var xf: Transform3D = it[1]
		for c: Node in n.get_children():
			var cxf := xf
			if c is Node3D:
				cxf = xf * (c as Node3D).transform
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				if mi.mesh != null:
					var overrides: Array = []
					var any := false
					for s in mi.mesh.get_surface_count():
						var o := mi.get_surface_override_material(s)
						overrides.append(o)
						any = any or o != null
					var pname := String(mi.name)
					if parts.has(pname):
						pname = pname + "_" + str(parts.size())
					parts[pname] = [mi.mesh, cxf, overrides if any else []]
					order.append(pname)
					var box := cxf * mi.mesh.get_aabb()
					if first:
						aabb = box
						first = false
					else:
						aabb = aabb.merge(box)
			elif c is Node3D and c.get_child_count() == 0:
				markers[String(c.name)] = cxf
			stack.append([c, cxf])
	root.free()
	return {"parts": parts, "order": order, "markers": markers, "aabb": aabb}


## Render mesh of the whole asset: {"mesh": Mesh, "xf": Transform3D (mesh space -> asset space)}.
## Single-part assets reuse the imported mesh (no copy); multi-part assets are merged.
func visual(id: String) -> Dictionary:
	return visual_except(id, [])


## Like visual() but without the named parts (traffic light lenses, door leaves ...).
func visual_except(id: String, excluded: Array) -> Dictionary:
	var key := id + "|" + ",".join(PackedStringArray(excluded))
	if _merge_cache.has(key):
		return _merge_cache[key]
	var ex := _extract(id)
	var res := {}
	if ex.is_empty():
		_merge_cache[key] = res
		return res
	var use: Array = []
	for pname: String in ex["order"]:
		if excluded.has(pname):
			continue
		use.append(ex["parts"][pname])
	if use.size() == 1 and (use[0][2] as Array).is_empty():
		res = {"mesh": use[0][0], "xf": use[0][1]}
	elif not use.is_empty():
		res = {"mesh": merge(use), "xf": Transform3D.IDENTITY}
	_merge_cache[key] = res
	return res


## One named part {"mesh", "xf"} or {} if the asset has no such part.
func part(id: String, part_name: String) -> Dictionary:
	var ex := _extract(id)
	if ex.is_empty() or not (ex["parts"] as Dictionary).has(part_name):
		return {}
	var p: Array = ex["parts"][part_name]
	return {"mesh": p[0], "xf": p[1]}


func has_part(id: String, part_name: String) -> bool:
	var ex := _extract(id)
	return not ex.is_empty() and (ex["parts"] as Dictionary).has(part_name)


## Marker transform in asset space, or null.
func marker(id: String, marker_name: String) -> Variant:
	var ex := _extract(id)
	if ex.is_empty():
		return null
	return (ex["markers"] as Dictionary).get(marker_name, null)


func aabb(id: String) -> AABB:
	var ex := _extract(id)
	if ex.is_empty():
		var d: Dictionary = defs.get(id, {})
		if d.is_empty():
			return AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
		var s: Vector3 = d["size_v"]
		return AABB(d["center_v"] - s * 0.5, s)
	return ex["aabb"]


## Lower detail render mesh (nature trees: manifest "lod1" GLB next to the asset), or {}.
func lod1(id: String) -> Dictionary:
	var d: Dictionary = defs.get(id, {})
	var f := String(d.get("lod1", ""))
	if f == "":
		return {}
	var key := "lod1|" + id
	if _merge_cache.has(key):
		return _merge_cache[key]
	var t0 := Time.get_ticks_usec()
	var ex := extract_scene(String(DIRS[d["source"]]) + f)
	_load_us += Time.get_ticks_usec() - t0
	load_ms = _load_us / 1000
	var res := {}
	if not ex.is_empty():
		var use: Array = []
		for pname: String in ex["order"]:
			use.append(ex["parts"][pname])
		if use.size() == 1 and (use[0][2] as Array).is_empty():
			res = {"mesh": use[0][0], "xf": use[0][1]}
		elif not use.is_empty():
			res = {"mesh": merge(use), "xf": Transform3D.IDENTITY}
	_merge_cache[key] = res
	return res


## Merges [mesh, xf, overrides] entries into one ArrayMesh, one surface per material.
static func merge(entries: Array) -> ArrayMesh:
	var by_mat: Dictionary = {}       # material (or null key) -> SurfaceTool
	var mats: Array = []
	for e: Array in entries:
		var mesh: Mesh = e[0]
		var xf: Transform3D = e[1]
		var ov: Array = e[2]
		for s in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat: Material = ov[s] if s < ov.size() and ov[s] != null else mesh.surface_get_material(s)
			var st: SurfaceTool = by_mat.get(mat)
			if st == null:
				st = SurfaceTool.new()
				by_mat[mat] = st
				mats.append(mat)
			st.append_from(mesh, s, xf)
	var out := ArrayMesh.new()
	for mat: Variant in mats:
		var st: SurfaceTool = by_mat[mat]
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mat as Material)
	return out


# ---------------------------------------------------------------------------------------------
# collision shapes (asset space)
# ---------------------------------------------------------------------------------------------

## Collider of an IDLE instance (batched into the chunk bodies): Array of [Shape3D, Transform3D].
## Empty for walk-through / flush assets.
func static_shapes(id: String) -> Array:
	var key := "s|" + id
	if _shape_cache.has(key):
		return _shape_cache[key]
	var out: Array = []
	var d: Dictionary = defs.get(id, {})
	if d.is_empty():
		return out
	var hint: String = d["collision"]
	var size: Vector3 = d["size_v"]
	var center: Vector3 = d["center_v"]
	var cat: String = d["category"]
	if hint == "none" or cat == "groundcover" or cat == "underwater" and hint != "box":
		pass
	elif POLES.has(id):
		var r: float = POLES[id]
		var h := size.y
		if id == "traffic_light":
			h = 6.9
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = h
		out.append([cyl, Transform3D(Basis.IDENTITY, Vector3(0.0, h * 0.5, 0.0))])
	elif hint == "trunk":
		var cyl2 := CylinderShape3D.new()
		cyl2.radius = maxf(float(d.get("collision_radius", 0.25)), 0.08)
		var th := clampf(float(d.get("height", size.y)) * 0.55, 1.5, 6.0)
		cyl2.height = th
		out.append([cyl2, Transform3D(Basis.IDENTITY, Vector3(0.0, th * 0.5 - 0.3, 0.0))])
	elif hint == "blob":
		var hull := _convex(id, 1.0)
		if hull != null:
			out.append([hull, _visual_xf(id)])
	elif hint == "trimesh":
		var v := visual(id)
		if not v.is_empty():
			var tri := (v["mesh"] as Mesh).create_trimesh_shape()
			if tri != null:
				out.append([tri, v["xf"]])
	elif d["source"] == "props" or hint == "box" or hint == "":
		var bx := BoxShape3D.new()
		bx.size = Vector3(maxf(size.x * 0.96, 0.08), maxf(size.y, 0.05), maxf(size.z * 0.96, 0.08))
		out.append([bx, Transform3D(Basis.IDENTITY, center)])
	_shape_cache[key] = out
	return out


## Shapes of the ACTIVE rigid body: a convex hull of the render mesh (shrunk a little so a panel
## that shares a post with its static neighbour does not start inside it).
func rigid_shapes(id: String) -> Array:
	var key := "r|" + id
	if _shape_cache.has(key):
		return _shape_cache[key]
	var out: Array = []
	var d: Dictionary = defs.get(id, {})
	var shrink := 0.94 if d.has("tile") else 0.985
	var hull := _convex(id, shrink)
	if hull != null:
		out.append([hull, _visual_xf(id)])
	else:
		var size: Vector3 = d.get("size_v", Vector3.ONE)
		var bx := BoxShape3D.new()
		bx.size = size * 0.95
		out.append([bx, Transform3D(Basis.IDENTITY, d.get("center_v", Vector3(0, size.y * 0.5, 0)))])
	_shape_cache[key] = out
	return out


func _visual_xf(id: String) -> Transform3D:
	var v := visual(id)
	return v.get("xf", Transform3D.IDENTITY)


func _convex(id: String, shrink: float) -> ConvexPolygonShape3D:
	var v := visual(id)
	if v.is_empty():
		return null
	# plain quickhull of the (low-poly) render mesh; the simplified variant runs a V-HACD convex
	# decomposition (tens of ms per asset) and is only used when the hull would be very large
	var mesh := v["mesh"] as Mesh
	var cs := mesh.create_convex_shape(true, false) as ConvexPolygonShape3D
	if cs != null and cs.points.size() > MAX_HULL_POINTS:
		var simple := mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
		if simple != null and simple.points.size() >= 4:
			cs = simple
	if cs == null:
		return null
	if shrink < 0.999:
		var pts := cs.points
		var c := Vector3.ZERO
		for p in pts:
			c += p
		c /= maxf(float(pts.size()), 1.0)
		for i in pts.size():
			var q := pts[i] - c
			pts[i] = c + Vector3(q.x * shrink, q.y, q.z * shrink)
		cs.points = pts
	return cs
