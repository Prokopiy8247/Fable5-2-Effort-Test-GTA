extends Node
## Asset + shared-material library (autoload "Assets").
##
## Pipeline: Blender (GodotFable5.2GTAMax.blend) -> GLB in res://gta/generated/models -> here.
## Blender materials are matched BY NAME to shared project materials, so every authored
## asset renders with the same handful of shaders:
##   Palette      palette-atlas surface (flat colours, roughness/metal/emission per cell)
##   Window       building windows (lit at night by hash)
##   Glass        transparent glass (vehicle/shop), per-instance tint
##   Paint1/2     vehicle paint channels (per-instance colour/finish/damage)
##   Light*       vehicle lamp lenses driven by per-instance channel intensities
##   Character    region-coloured skinned characters (duplicated per character)
##   Foliage      palette colours + wind sway

const PALETTE_PATH := "res://gta/resources/data/palette.json"
const MODELS := "res://gta/generated/models/"
const PAL_SIZE := 16

var palette_index: Dictionary = {}    # name -> int
var palette_colors: Dictionary = {}   # name -> Color (sRGB)
var palette_props: Dictionary = {}    # name -> [rough, metal, emission, flag]

var pal_albedo: ImageTexture
var pal_orm: ImageTexture
var pal_flags: ImageTexture

var _materials: Dictionary = {}
var _scene_cache: Dictionary = {}
var _prepared: Dictionary = {}
var _mesh_cache: Dictionary = {}
var noise_tex: NoiseTexture2D
var detail_noise: NoiseTexture2D

func _enter_tree() -> void:
	_load_palette()
	_build_noise()
	_build_materials()

# ---------------------------------------------------------------- palette
func _load_palette() -> void:
	var f := FileAccess.open(PALETTE_PATH, FileAccess.READ)
	if f == null:
		push_error("Assets: palette.json missing")
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	var colors: Array = data["colors"]
	var img_a := Image.create(PAL_SIZE, PAL_SIZE, false, Image.FORMAT_RGBA8)
	var img_o := Image.create(PAL_SIZE, PAL_SIZE, false, Image.FORMAT_RGBA8)
	var img_f := Image.create(PAL_SIZE, PAL_SIZE, false, Image.FORMAT_RGBA8)
	img_a.fill(Color(1, 0, 1))
	img_o.fill(Color(0.8, 0, 0, 1))
	img_f.fill(Color(0, 0, 0, 0))
	for i in colors.size():
		var e: Array = colors[i]
		var c := Color.html(e[1])
		var col := i % PAL_SIZE
		var row := i / PAL_SIZE
		palette_index[e[0]] = i
		palette_colors[e[0]] = c
		palette_props[e[0]] = [float(e[2]), float(e[3]), float(e[4]), String(e[5])]
		img_a.set_pixel(col, row, c)
		img_o.set_pixel(col, row, Color(float(e[2]), float(e[3]), clampf(float(e[4]) / 4.0, 0.0, 1.0), 1.0))
		var flag := String(e[5])
		img_f.set_pixel(col, row, Color(
			1.0 if flag == "tA" else 0.0,
			1.0 if flag == "tB" else 0.0,
			1.0 if flag == "night" else 0.0,
			1.0 if flag == "neon" else 0.0))
	pal_albedo = ImageTexture.create_from_image(img_a)
	pal_orm = ImageTexture.create_from_image(img_o)
	pal_flags = ImageTexture.create_from_image(img_f)

## UV of a palette cell centre (use for code-generated meshes that share the Palette material).
func pal_uv(color_name: String) -> Vector2:
	var i: int = palette_index.get(color_name, 0)
	return Vector2((float(i % PAL_SIZE) + 0.5) / PAL_SIZE, (float(i / PAL_SIZE) + 0.5) / PAL_SIZE)

func color(color_name: String) -> Color:
	return palette_colors.get(color_name, Color.MAGENTA)

func _build_noise() -> void:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.012
	n.fractal_octaves = 4
	noise_tex = NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.noise = n
	var n2 := FastNoiseLite.new()
	n2.noise_type = FastNoiseLite.TYPE_CELLULAR
	n2.frequency = 0.045
	n2.seed = 7
	detail_noise = NoiseTexture2D.new()
	detail_noise.width = 256
	detail_noise.height = 256
	detail_noise.seamless = true
	detail_noise.noise = n2

# ---------------------------------------------------------------- materials
func _shader_mat(shader_path: String, params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(shader_path)
	for k in params.keys():
		m.set_shader_parameter(k, params[k])
	return m

func _build_materials() -> void:
	var pal := {"pal_albedo": pal_albedo, "pal_orm": pal_orm, "pal_flags": pal_flags}
	_materials["Palette"] = _shader_mat("res://gta/shaders/palette.gdshader", pal)
	var pal_dry := pal.duplicate()
	pal_dry["wet_response"] = 0.0
	_materials["PaletteDry"] = _shader_mat("res://gta/shaders/palette.gdshader", pal_dry)  # interiors
	_materials["Window"] = _shader_mat("res://gta/shaders/window.gdshader")
	_materials["Glass"] = _shader_mat("res://gta/shaders/glass.gdshader")
	_materials["Paint1"] = _shader_mat("res://gta/shaders/paint.gdshader", {"slot": 0})
	_materials["Paint2"] = _shader_mat("res://gta/shaders/paint.gdshader", {"slot": 1})
	var lights := {
		"LightHead": [0, Color(1.0, 0.96, 0.86), 5.0],
		"LightTail": [1, Color(1.0, 0.08, 0.05), 3.5],
		"LightReverse": [2, Color(1.0, 1.0, 1.0), 3.0],
		"LightIndL": [3, Color(1.0, 0.6, 0.08), 4.0],
		"LightIndR": [4, Color(1.0, 0.6, 0.08), 4.0],
		"LightSirenA": [5, Color(1.0, 0.1, 0.08), 7.0],
		"LightSirenB": [6, Color(0.12, 0.3, 1.0), 7.0],
		"LightAux": [7, Color(1.0, 0.9, 0.5), 3.0],
	}
	for k in lights.keys():
		var d: Array = lights[k]
		_materials[k] = _shader_mat("res://gta/shaders/vehicle_light.gdshader",
			{"channel": d[0], "lens_color": d[1], "energy": d[2]})
	var sig := "res://gta/shaders/signal_light.gdshader"
	_materials["SignalR"] = _shader_mat(sig, {"which": 0, "lens_color": Color(1.0, 0.12, 0.08)})
	_materials["SignalA"] = _shader_mat(sig, {"which": 1, "lens_color": Color(1.0, 0.65, 0.08)})
	_materials["SignalG"] = _shader_mat(sig, {"which": 2, "lens_color": Color(0.1, 1.0, 0.45)})
	if ResourceLoader.exists("res://gta/shaders/character.gdshader"):
		_materials["Character"] = _shader_mat("res://gta/shaders/character.gdshader")
	if ResourceLoader.exists("res://gta/shaders/foliage.gdshader"):
		_materials["Foliage"] = _shader_mat("res://gta/shaders/foliage.gdshader", {"pal_albedo": pal_albedo})

func mat(mat_name: String) -> Material:
	return _materials.get(mat_name)

func register_material(mat_name: String, m: Material) -> void:
	_materials[mat_name] = m

## A fresh per-character copy of the Character material (regions are per-material uniforms).
func new_character_material() -> ShaderMaterial:
	return (_materials["Character"] as ShaderMaterial).duplicate() as ShaderMaterial

# ---------------------------------------------------------------- models
func has_model(rel: String) -> bool:
	return ResourceLoader.exists(MODELS + rel + ".glb")

func scene(rel: String) -> PackedScene:
	if _scene_cache.has(rel):
		return _scene_cache[rel]
	var path := MODELS + rel + ".glb"
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	else:
		push_warning("Assets: missing model " + path)
	_scene_cache[rel] = ps
	return ps

## Instantiate an imported GLB and swap its materials for the shared project materials.
func instance(rel: String) -> Node3D:
	var ps := scene(rel)
	if ps == null:
		return _missing_placeholder(rel)
	var n := ps.instantiate() as Node3D
	prepare(n)
	return n

func prepare(root: Node) -> void:
	for mi in find_meshes(root):
		prepare_mesh(mi.mesh)

func prepare_mesh(mesh: Mesh) -> void:
	if mesh == null:
		return
	var id := mesh.get_instance_id()
	if _prepared.has(id):
		return
	_prepared[id] = true
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m == null:
			continue
		var nm := String(m.resource_name)
		var dot := nm.find(".")
		if dot > 0:
			nm = nm.substr(0, dot)   # Blender duplicate suffix "Palette.001"
		if _materials.has(nm):
			mesh.surface_set_material(s, _materials[nm])

func find_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect_meshes(root, out)
	return out

func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)

## Fetch a prepared Mesh resource out of a GLB (for MultiMesh / merging). node_name "" = first mesh.
func mesh(rel: String, node_name: String = "") -> Mesh:
	var key := rel + "#" + node_name
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var ps := scene(rel)
	var result: Mesh = null
	if ps != null:
		var inst := ps.instantiate()
		for mi in find_meshes(inst):
			if node_name == "" or String(mi.name) == node_name:
				result = mi.mesh
				break
		inst.free()
	if result != null:
		prepare_mesh(result)
	else:
		push_warning("Assets: mesh not found " + key)
	_mesh_cache[key] = result
	return result

## All meshes of a GLB with their transforms relative to the scene root: Array of [Mesh, Transform3D, name].
func mesh_parts(rel: String) -> Array:
	var key := "parts:" + rel
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var out: Array = []
	var ps := scene(rel)
	if ps != null:
		var inst := ps.instantiate() as Node3D
		for mi in find_meshes(inst):
			prepare_mesh(mi.mesh)
			out.append([mi.mesh, _rel_transform(mi, inst), String(mi.name)])
		inst.free()
	_mesh_cache[key] = out
	return out

func _rel_transform(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

func _missing_placeholder(rel: String) -> Node3D:
	# Loud magenta marker so missing exports are obvious during QA (never shipped intentionally).
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.6, 0.6)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(1, 0, 1)
	bm.material = sm
	mi.mesh = bm
	mi.name = "MISSING_" + rel.replace("/", "_")
	return mi

## Set a per-instance shader parameter on every mesh below `root`.
func set_instance_param(root: Node, param: StringName, value: Variant) -> void:
	for mi in find_meshes(root):
		mi.set_instance_shader_parameter(param, value)
