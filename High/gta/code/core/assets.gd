extends Node
## Loads Blender-exported GLB assets, unifies their materials into one shared library (autoload "Assets").

const MANIFEST := "res://gta/generated/models/manifest.json"

var manifest: Dictionary = {}
var _scenes: Dictionary = {}
var _mats: Dictionary = {}
var _done_meshes: Dictionary = {}
var _mesh_cache: Dictionary = {}
var night := 0.0


func _enter_tree() -> void:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			manifest = d
	else:
		push_error("Asset manifest missing: " + MANIFEST)


func has_asset(n: String) -> bool:
	return manifest.has(n)


func size_of(n: String) -> AABB:
	if not manifest.has(n):
		return AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
	var mn: Array = manifest[n]["min"]
	var mx: Array = manifest[n]["max"]
	return AABB(Vector3(mn[0], mn[1], mn[2]), Vector3(mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]))


func scene(n: String) -> PackedScene:
	if _scenes.has(n):
		return _scenes[n]
	if not manifest.has(n):
		push_error("Unknown asset: " + n)
		return null
	var ps = load(manifest[n]["path"])
	_scenes[n] = ps
	return ps


func inst(n: String) -> Node3D:
	var ps := scene(n)
	if ps == null:
		return Node3D.new()
	var node: Node3D = ps.instantiate()
	unify(node)
	return node


func unify(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var mesh: Mesh = node.mesh
		var id := mesh.get_instance_id()
		if not _done_meshes.has(id):
			_done_meshes[id] = true
			for i in range(mesh.get_surface_count()):
				var m := mesh.surface_get_material(i)
				if m != null:
					mesh.surface_set_material(i, mat(m.resource_name, m))
	for c in node.get_children():
		unify(c)


func find(node: Node, suffix: String) -> Node:
	## First descendant whose name ends with suffix.
	if String(node.name).ends_with(suffix):
		return node
	for c in node.get_children():
		var r := find(c, suffix)
		if r != null:
			return r
	return null


func find_all(node: Node, contains: String, out: Array = []) -> Array:
	if String(node.name).contains(contains):
		out.append(node)
	for c in node.get_children():
		find_all(c, contains, out)
	return out


func mesh_of(n: String) -> Mesh:
	## First mesh inside an asset (for MultiMesh use).
	if _mesh_cache.has(n):
		return _mesh_cache[n]
	var node := inst(n)
	var mi := _first_mesh(node)
	var mesh: Mesh = mi.mesh if mi else null
	_mesh_cache[n] = mesh
	node.free()
	return mesh


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var r := _first_mesh(c)
		if r:
			return r
	return null


func mat(mname: String, src: Material = null) -> Material:
	if _mats.has(mname):
		return _mats[mname]
	var m: StandardMaterial3D
	if src is StandardMaterial3D:
		m = src.duplicate()
	else:
		m = StandardMaterial3D.new()
		m.albedo_color = Color(0.6, 0.6, 0.6)
	m.resource_name = mname
	m.vertex_color_use_as_albedo = false
	m.metallic_specular = 0.4
	match mname:
		"M_Glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.10, 0.17, 0.2, 0.5)
			m.roughness = 0.05
			m.metallic = 0.3
			m.cull_mode = BaseMaterial3D.CULL_BACK
		"M_ChainLink":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = 0.35
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"M_Water":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = 0.75
			m.roughness = 0.05
		"M_WindowLit":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.82, 0.5)
			m.emission_energy_multiplier = 0.0
			m.roughness = 0.12
			m.metallic = 0.5
		"M_WindowDark", "M_ShopFront":
			m.roughness = 0.12
			m.metallic = 0.5
			if mname == "M_ShopFront":
				m.emission_enabled = true
				m.emission = Color(0.9, 0.85, 0.7)
				m.emission_energy_multiplier = 0.0
		"M_LampGlow":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.9, 0.65)
			m.emission_energy_multiplier = 0.0
		"M_Grass", "M_Flower", "M_Seaweed", "M_Canopy", "M_Canopy2", "M_Fabric":
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"M_Paint", "M_Paint2":
			m.roughness = 0.3
			m.metallic = 0.35
			m.metallic_specular = 0.6
	if mname.begins_with("M_Neon") or mname.begins_with("M_TLon") or mname == "M_Cross" or mname == "M_TaxiSign":
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 1.6 if mname.begins_with("M_Neon") else 2.5
	_mats[mname] = m
	return m


func set_night(n: float) -> void:
	## n: 0 day .. 1 night. Drives window, lamp and neon emission.
	night = n
	if _mats.has("M_WindowLit"):
		_mats["M_WindowLit"].emission_energy_multiplier = n * 1.6
	if _mats.has("M_ShopFront"):
		_mats["M_ShopFront"].emission_energy_multiplier = n * 0.5
	if _mats.has("M_LampGlow"):
		_mats["M_LampGlow"].emission_energy_multiplier = 0.2 + n * 3.0
	for k in _mats:
		if String(k).begins_with("M_Neon"):
			_mats[k].emission_energy_multiplier = 1.0 + n * 2.2
