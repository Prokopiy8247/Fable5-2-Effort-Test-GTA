extends RefCounted
## ENVIRONMENT module helper: factory + cache for the night-light hook materials.
## Reach it through the environment system (see docs/ENVIRONMENT.md):
##     var env := Game.get_system("environment")
##     env.apply_night_materials(building_root)      # swaps by Blender material name
##     env.get_window_material() / env.get_lamp_material() / env.get_neon_material(color)
## All materials are shared instances driven by the global uniforms gta_night / gta_time, so
## thousands of windows and lamps cost no script time at all.
##
## Three ways in:
##   apply_to(root)            explicit, per-instance surface overrides for a whole subtree
##   apply_to_instance(mi)     the automatic path (EnvironmentSystem.auto_night_materials): one
##                             cached lookup per Mesh resource, never touches a surface whose
##                             owner already set an override
##   apply_to_mesh(mesh)       swaps on the Mesh resource itself (MultiMesh geometry)
## The hook materials keep the Blender name as a prefix (M_Window_Env1, M_LampGlow_Env,
## P_Neon_Env), so code that recognises surfaces by name prefix still finds them.

const WINDOW_SHADER: Shader = preload("res://gta/code/world/shaders/env_lit_window.gdshader")
const GLOW_SHADER: Shader = preload("res://gta/code/world/shaders/env_lamp_glow.gdshader")

## Blender material names that are hooks (prefix match, so "M_Window.001" works too).
const WINDOW_NAMES: Array[String] = ["M_Window"]
const LAMP_NAMES: Array[String] = ["M_LampGlow", "P_LampWarm"]
const NEON_PREFIXES: Array[String] = ["P_Neon"]
const DEFAULT_LAMP_COLOR := Color(1.0, 0.80, 0.50)
const MESH_CACHE_LIMIT := 4096

## Window pane modes (uniform cell_mode of env_lit_window.gdshader).
const CELL_AUTO := 0          ## UV cells when the mesh has UVs, otherwise the object grid
const CELL_UV := 1            ## building-kit UV cells: floor(UV) = pane id
const CELL_OBJECT_GRID := 2   ## 4 m module grid in object space (meshes without UVs)
const CELL_WORLD_GRID := 3    ## 4 m grid in world space (geometry merged in world space)

var _windows: Dictionary = {}     ## cell mode -> ShaderMaterial
var _lamps: Dictionary = {}       ## colour key -> ShaderMaterial
var _neons: Dictionary = {}       ## colour key -> ShaderMaterial
var _mesh_hooks: Dictionary = {}  ## Mesh instance id -> Array (one ShaderMaterial or null per surface; [] = no hooks)


## Shared window glass: mirrors the sky by day, a pseudo-random subset of panes glows at night.
func get_window_material(cell_mode: int = CELL_AUTO) -> ShaderMaterial:
	var mode := clampi(cell_mode, CELL_AUTO, CELL_WORLD_GRID)
	if _windows.has(mode):
		return _windows[mode]
	var m := ShaderMaterial.new()
	m.shader = WINDOW_SHADER
	m.resource_name = "M_Window_Env%d" % mode
	m.set_shader_parameter(&"cell_mode", mode)
	_windows[mode] = m
	return m


## Lamp lens: pale plastic by day, emissive `color` at night (one cached material per colour).
func get_lamp_material(color: Color = DEFAULT_LAMP_COLOR) -> ShaderMaterial:
	var key := _color_key(color)
	if _lamps.has(key):
		return _lamps[key]
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.resource_name = "M_LampGlow_Env"
	m.set_shader_parameter(&"glow_color", color)
	m.set_shader_parameter(&"off_color", Color(0.86, 0.85, 0.80).lerp(color, 0.12))
	m.set_shader_parameter(&"day_energy", 0.0)
	m.set_shader_parameter(&"night_energy", 4.5)
	_lamps[key] = m
	return m


## Neon / illuminated signage: always emissive, clearly stronger at night (cached per colour).
func get_neon_material(color: Color) -> ShaderMaterial:
	var key := _color_key(color)
	if _neons.has(key):
		return _neons[key]
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.resource_name = "P_Neon_Env"
	m.set_shader_parameter(&"glow_color", color)
	m.set_shader_parameter(&"off_color", color.lerp(Color(1, 1, 1), 0.15))
	m.set_shader_parameter(&"day_energy", 1.15)
	m.set_shader_parameter(&"night_energy", 3.8)
	m.set_shader_parameter(&"switch_start", 0.15)
	m.set_shader_parameter(&"switch_end", 0.50)
	m.set_shader_parameter(&"shimmer", 0.35)
	_neons[key] = m
	return m


## Kind of hook a Blender material name stands for: "window", "lamp", "neon" or "".
func hook_kind(material_name: String) -> String:
	for n in WINDOW_NAMES:
		if material_name.begins_with(n):
			return "window"
	for n in LAMP_NAMES:
		if material_name.begins_with(n):
			return "lamp"
	for n in NEON_PREFIXES:
		if material_name.begins_with(n):
			return "neon"
	return ""


## True for a material that already is one of the hook materials.
func is_hook_material(mat: Material) -> bool:
	var sm := mat as ShaderMaterial
	return sm != null and (sm.shader == WINDOW_SHADER or sm.shader == GLOW_SHADER)


## Maps a Blender material name to its hook material, or null when the name is not a hook.
## `source` (the imported material) supplies the colour for neon variants.
## `window_cell_mode` picks the pane mode for windows (CELL_AUTO by default).
func get_material_for(material_name: String, source: Material = null,
		window_cell_mode: int = CELL_AUTO) -> ShaderMaterial:
	match hook_kind(material_name):
		"window":
			return get_window_material(window_cell_mode)
		"lamp":
			return get_lamp_material()
		"neon":
			return get_neon_material(_source_color(source, Color(1.0, 0.25, 0.55)))
	return null


## Walks `root` and replaces every surface whose material is named M_Window / M_LampGlow /
## P_LampWarm / P_Neon* with the matching hook material (surface override; the mesh resource is
## untouched). Windows use UV cells when the mesh has UVs, the object grid otherwise.
## Returns the number of surfaces that were replaced.
func apply_to(root: Node) -> int:
	if root == null:
		return 0
	var count := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src: Material = mi.get_surface_override_material(s)
			if src == null:
				src = mi.mesh.surface_get_material(s)
			if src == null or is_hook_material(src):
				continue
			var hook := get_material_for(src.resource_name, src, _cell_mode_for(mi.mesh, s))
			if hook != null and hook != src:
				mi.set_surface_override_material(s, hook)
				count += 1
	return count


## The automatic path: gives one MeshInstance3D the hook materials of its mesh (surface
## overrides). Surfaces that already have an override are left alone - their owner decided.
## Returns the number of surfaces that were replaced.
func apply_to_instance(mi: MeshInstance3D) -> int:
	if mi == null or mi.mesh == null:
		return 0
	var hooks := _hooks_for_mesh(mi.mesh)
	var count := 0
	for s in hooks.size():
		var hook: ShaderMaterial = hooks[s]
		if hook == null or mi.get_surface_override_material(s) != null:
			continue
		mi.set_surface_override_material(s, hook)
		count += 1
	return count


## Swaps the hook materials into the Mesh resource itself, for geometry without per-surface
## overrides (MultiMesh). Every user of the mesh is affected. Returns the replaced count.
func apply_to_mesh(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var hooks := _hooks_for_mesh(mesh)
	var count := 0
	for s in hooks.size():
		var hook: ShaderMaterial = hooks[s]
		if hook == null or mesh.surface_get_material(s) == hook:
			continue
		mesh.surface_set_material(s, hook)
		count += 1
	return count


## Hook material per surface of `mesh` (null = not a hook); an empty array when there is none.
## Looked up once per Mesh resource.
func _hooks_for_mesh(mesh: Mesh) -> Array:
	var key := mesh.get_instance_id()
	var cached: Variant = _mesh_hooks.get(key)
	if cached != null:
		return cached
	var hooks: Array = []
	var any := false
	var n := mesh.get_surface_count()
	hooks.resize(n)
	for s in n:
		var src := mesh.surface_get_material(s)
		var hook: ShaderMaterial = null
		if src != null:
			if is_hook_material(src):
				hook = src as ShaderMaterial
			else:
				hook = get_material_for(src.resource_name, src, _cell_mode_for(mesh, s))
		hooks[s] = hook
		if hook != null:
			any = true
	if not any:
		hooks = []
	if _mesh_hooks.size() >= MESH_CACHE_LIMIT:
		_mesh_hooks.clear()
	_mesh_hooks[key] = hooks
	return hooks


func _cell_mode_for(mesh: Mesh, surface: int) -> int:
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null:
		return CELL_AUTO
	var has_uv := (array_mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_TEX_UV) != 0
	return CELL_UV if has_uv else CELL_OBJECT_GRID


func _source_color(source: Material, fallback: Color) -> Color:
	var bm := source as BaseMaterial3D
	if bm == null:
		return fallback
	if bm.emission_enabled and bm.emission.get_luminance() > 0.02:
		return bm.emission
	return bm.albedo_color


func _color_key(c: Color) -> int:
	return (int(clampf(c.r, 0.0, 1.0) * 63.0) << 12) | (int(clampf(c.g, 0.0, 1.0) * 63.0) << 6) \
			| int(clampf(c.b, 0.0, 1.0) * 63.0)
