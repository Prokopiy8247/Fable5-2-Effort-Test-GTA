extends Node
## Assets - loads Blender-exported GLB files, unifies materials by name and hands out meshes/sub-scenes (autoload).

const DIR := "res://gta/generated/models/"
const SH := "res://gta/resources/shaders/"

var _packed := {}
var _kits := {}
var _kit_roots: Array = []
var mats := {}
var _fixed := {}
var _color_mats := {}
var _shaders := {}

const FOLIAGE := ["Leaf", "LeafDark", "LeafLight", "LeafAutumn", "Pine", "Palm", "Grass", "Seaweed", "Flower", "FlowerYellow"]


func _exit_tree() -> void:
	for r in _kit_roots:
		if is_instance_valid(r):
			r.free()


func shader(n: String) -> Shader:
	if not _shaders.has(n):
		_shaders[n] = load(SH + n + ".gdshader")
	return _shaders[n]


func packed(rel: String) -> PackedScene:
	if not _packed.has(rel):
		var p := DIR + rel + ".glb"
		if not ResourceLoader.exists(p):
			push_error("Missing model: " + p)
			return null
		_packed[rel] = load(p)
	return _packed[rel]


func inst(rel: String, prefix: String = "") -> Node3D:
	var ps := packed(rel)
	if ps == null:
		return Node3D.new()
	var n: Node3D = ps.instantiate()
	prepare(n, prefix)
	return n


func prepare(n: Node, prefix: String) -> void:
	if prefix != "" and String(n.name).begins_with(prefix):
		n.name = String(n.name).substr(prefix.length())
	if n is MeshInstance3D and n.mesh != null:
		fix_mesh(n.mesh)
	for c in n.get_children():
		prepare(c, prefix)


func fix_mesh(mesh: Mesh) -> void:
	var id := mesh.get_instance_id()
	if _fixed.has(id):
		return
	_fixed[id] = true
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m == null:
			continue
		var nm := m.resource_name
		if nm == "":
			continue
		mesh.surface_set_material(i, shared(nm, m))


func shared(nm: String, original: Material) -> Material:
	if mats.has(nm):
		return mats[nm]
	var m: Material = original
	var sm := original as StandardMaterial3D
	if nm in FOLIAGE:
		var f := ShaderMaterial.new()
		f.shader = shader("foliage")
		f.set_shader_parameter("albedo", sm.albedo_color if sm else Color(0.3, 0.6, 0.3))
		f.set_shader_parameter("sway", 0.02 if nm in ["Grass", "Flower", "FlowerYellow"] else (0.12 if nm == "Seaweed" else 0.05))
		m = f
	elif nm == "WindowGlass" or nm == "ShopGlass":
		var w := ShaderMaterial.new()
		w.shader = shader("window")
		w.set_shader_parameter("glass_color", sm.albedo_color if sm else Color(0.2, 0.33, 0.42))
		w.set_shader_parameter("lit_ratio", 0.8 if nm == "ShopGlass" else 0.3)
		m = w
	elif nm == "AwningTint" or nm == "SignTint":
		var t := ShaderMaterial.new()
		t.shader = shader("tint_custom")
		t.set_shader_parameter("glow", 1.0 if nm == "SignTint" else 0.0)
		m = t
	elif sm != null:
		if nm.ends_with("Tint"):
			sm.vertex_color_use_as_albedo = true
			sm.albedo_color = Color.WHITE
		if nm in ["Glass", "GlassClear", "ChainLink", "PoolWater", "BottleGlass"]:
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			sm.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
			if nm == "Glass":
				sm.albedo_color.a = 0.55
		if nm == "FlashCore":
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		if nm in ["ChuteA", "ChuteB"]:
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.resource_name = nm
	mats[nm] = m
	return m


func kit(rel: String) -> Dictionary:
	if not _kits.has(rel):
		var d := {}
		var ps := packed(rel)
		if ps != null:
			var root: Node = ps.instantiate()
			prepare(root, "")
			_collect(root, d)
			_kit_roots.append(root)
		_kits[rel] = d
	return _kits[rel]


func _collect(n: Node, d: Dictionary) -> void:
	for c in n.get_children():
		d[String(c.name)] = c
		_collect(c, d)


func mesh(rel: String, nm: String) -> Mesh:
	var k := kit(rel)
	if not k.has(nm):
		push_error("Missing mesh %s in %s" % [nm, rel])
		return BoxMesh.new()
	return (k[nm] as MeshInstance3D).mesh


func has(rel: String, nm: String) -> bool:
	return kit(rel).has(nm)


func sub(rel: String, nm: String, prefix: String = "") -> Node3D:
	## Duplicate of a named subtree with its root transform reset.
	var k := kit(rel)
	if not k.has(nm):
		push_error("Missing node %s in %s" % [nm, rel])
		return Node3D.new()
	var n: Node3D = k[nm].duplicate()
	n.transform = Transform3D.IDENTITY
	if prefix != "":
		_strip(n, prefix)
	return n


func _strip(n: Node, prefix: String) -> void:
	if String(n.name).begins_with(prefix):
		n.name = String(n.name).substr(prefix.length())
	for c in n.get_children():
		_strip(c, prefix)


func mi(rel: String, nm: String) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh(rel, nm)
	m.name = nm
	return m


func color_mat(c: Color, rough: float = 0.8, metal: float = 0.0, emit: float = 0.0, unshaded := false) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f_%.2f_%s" % [c.to_html(), rough, metal, emit, unshaded]
	if _color_mats.has(key):
		return _color_mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if c.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = Color(c.r, c.g, c.b)
		m.emission_energy_multiplier = emit
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_color_mats[key] = m
	return m


func tinted(base_name: String, c: Color) -> Material:
	## Opaque copy of a *Tint material with a fixed colour (for single MeshInstance3D buildings).
	var key := base_name + c.to_html()
	if _color_mats.has(key):
		return _color_mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if base_name == "SignTint":
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.6
		m.roughness = 0.5
	_color_mats[key] = m
	return m


func tint_node(n: Node, colors: Dictionary) -> void:
	## colors: {"WallTint": Color, ...} applied as surface overrides on every MeshInstance3D below n.
	if n is MeshInstance3D and n.mesh != null:
		for i in n.mesh.get_surface_count():
			var m: Material = n.mesh.surface_get_material(i)
			if m != null and colors.has(m.resource_name):
				n.set_surface_override_material(i, tinted(m.resource_name, colors[m.resource_name]))
	for c in n.get_children():
		tint_node(c, colors)


func trimesh_body(mi_node: MeshInstance3D, layer: int = 1) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mi_node.mesh.create_trimesh_shape()
	sb.add_child(cs)
	return sb


func mesh_aabb(rel: String, nm: String) -> AABB:
	return mesh(rel, nm).get_aabb()
