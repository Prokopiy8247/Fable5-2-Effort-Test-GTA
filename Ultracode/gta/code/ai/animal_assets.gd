class_name AnimalAssets
extends RefCounted
## Shared, cached access to the wildlife art: the animal manifest (parts, pivots, sizes, bird poses),
## the GLB scenes and the merged single-surface fish mesh used by the fish-school MultiMesh.
## Gameplay tuning lives in the Registry kind "animals" (resources/registries/animals_registry.gd);
## species_def() merges both into one Dictionary.

const DIR := "res://gta/generated/models/animals/"
const MANIFEST := DIR + "manifest_animals.json"

static var _manifest: Dictionary = {}       ## id -> manifest entry
static var _defs: Dictionary = {}           ## id -> merged def
static var _scenes: Dictionary = {}         ## id -> PackedScene
static var _merged: Dictionary = {}         ## id -> ArrayMesh (vertex colours from the materials)
static var _loaded := false


static func _load_manifest() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(MANIFEST):
		push_warning("[Wildlife] animal manifest missing: " + MANIFEST)
		return
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_warning("[Wildlife] animal manifest unreadable")
		return
	for e: Variant in (parsed as Dictionary).get("animals", []):
		if e is Dictionary:
			_manifest[String((e as Dictionary).get("id", ""))] = e


static func manifest(id: String) -> Dictionary:
	_load_manifest()
	return _manifest.get(id, {})


## Registry tuning + manifest facts in one Dictionary ({} if the species is unknown or has no art).
static func species_def(id: String) -> Dictionary:
	if _defs.has(id):
		return _defs[id]
	_load_manifest()
	var reg: Variant = null
	if Registry.has_def("animals", id):
		reg = Registry.get_def("animals", id)
	var m: Dictionary = _manifest.get(id, {})
	if not (reg is Dictionary) or m.is_empty():
		return {}
	var d: Dictionary = (reg as Dictionary).duplicate(true)
	for k: String in ["size", "parts", "shoulder_height", "length", "pivots", "leg_length",
			"graze_head_pitch_deg", "body_radius", "wing_span", "poses", "tags"]:
		if m.has(k) and not d.has(k):
			d[k] = m[k]
	if not d.has("walk_speed"):
		d["walk_speed"] = float(m.get("walk_speed", 1.0))
	if not d.has("run_speed"):
		d["run_speed"] = float(m.get("run_speed", 4.0))
	var sz: Array = d.get("size", [0.5, 0.5, 0.5])
	d["size_v"] = Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
	if not d.has("leg_length"):
		d["leg_length"] = float(d.get("shoulder_height", 0.3)) * 0.8
	d["model"] = DIR + String(m.get("file", id + ".glb"))
	_defs[id] = d
	return d


static func scene(id: String) -> PackedScene:
	if _scenes.has(id):
		return _scenes[id]
	var d := species_def(id)
	var path := String(d.get("model", DIR + id + ".glb"))
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	if ps == null:
		push_warning("[Wildlife] missing animal model: " + path)
	_scenes[id] = ps
	return ps


## All part meshes of the GLB merged into ONE surface (vertex colour = the part material's albedo,
## flat normals preserved), in asset-root space. Used by the fish-school MultiMesh.
static func merged_mesh(id: String) -> ArrayMesh:
	if _merged.has(id):
		return _merged[id]
	var ps := scene(id)
	if ps == null:
		_merged[id] = null
		return null
	var inst := ps.instantiate() as Node3D
	var root := inst.find_child(id, true, false) as Node3D
	if root == null:
		root = inst
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := _relative_xform(mi, root)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nr: Variant = arr[Mesh.ARRAY_NORMAL]
			var ix: Variant = arr[Mesh.ARRAY_INDEX]
			var mat := mi.get_active_material(s)
			var c := Color(0.7, 0.7, 0.7)
			if mat is BaseMaterial3D:
				c = (mat as BaseMaterial3D).albedo_color
			var base := verts.size()
			for i in v.size():
				verts.append(xf * v[i])
				cols.append(c)
				if nr is PackedVector3Array and i < (nr as PackedVector3Array).size():
					norms.append((xf.basis * (nr as PackedVector3Array)[i]).normalized())
				else:
					norms.append(Vector3.UP)
			if ix is PackedInt32Array and not (ix as PackedInt32Array).is_empty():
				for k in (ix as PackedInt32Array):
					idx.append(base + k)
			else:
				for k in v.size():
					idx.append(base + k)
	inst.free()
	if verts.is_empty():
		_merged[id] = null
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_merged[id] = am
	return am


static func _relative_xform(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	var guard := 0
	while cur != null and cur != root and guard < 16:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
		guard += 1
	return xf


static func clear_cache() -> void:
	_scenes.clear()
	_merged.clear()
	_defs.clear()
