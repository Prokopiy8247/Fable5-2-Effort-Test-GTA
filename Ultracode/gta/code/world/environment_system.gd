class_name EnvironmentSystem
extends Node3D
## World system "environment" (BootManifest) - owner of everything atmospheric in Halcyon Bay:
## sun / moon light, sky, fog, tonemap, glow, SSAO, rain, lightning + thunder, the ocean surface,
## the underwater treatment, the pooled night street lights, the night-light shader hooks and
## the global shader uniforms (gta_daylight, gta_night, gta_wetness, gta_rain, gta_time,
## gta_wind, gta_underwater, gta_player_pos - nobody else writes them).
##
## It is a pure VIEW of the WorldClock and Weather autoloads: the look is recomputed from them
## every frame, so WorldClock.set_hour() / Weather.set_weather() are visible immediately.
## Works without the world system (tests) and in --headless. Full docs: docs/ENVIRONMENT.md.
##
## Public API for other modules (always through Game.get_system("environment") + has_method):
##   get_wave_height(x, z) -> float                 water surface Y incl. waves (boats, swimming)
##   get_water_normal(x, z) -> Vector3
##   register_light_points(points, color, light_range, energy)    pooled night street lights
##   clear_light_points()
##   get_window_material() / get_lamp_material(color) / get_neon_material(color)
##   get_night_material_for(material_name, source) / apply_night_materials(root) -> int
##   make_wet_surface_material(color, puddles, roughness, use_vertex_color)   wet-look ground
##   is_camera_underwater() -> bool, signal underwater_changed(on)
##   get_sun_direction() / get_light_direction() / get_sun_light() / get_environment()
##   refresh()                                      re-apply the look right now
##
## Automatic integration (no call needed, both can be switched off):
##   auto_night_materials   every MeshInstance3D / MultiMeshInstance3D that enters the tree gets
##                          the hook materials for its M_Window / M_LampGlow / P_LampWarm /
##                          P_Neon* surfaces (ARCHITECTURE 8.4: "the game swaps in a lit-window
##                          shader"). Opt out per node with the group "env_no_night_hook".
##   auto_street_lights     every Node3D in the group "street_light" gets a pooled night light
##                          at its "Light" marker (lamp props have one).

signal underwater_changed(underwater: bool)

const SkyControllerScript := preload("res://gta/code/world/env/sky_controller.gd")
const OceanSurfaceScript := preload("res://gta/code/world/env/ocean_surface.gd")
const RainScript := preload("res://gta/code/world/env/env_rain.gd")
const LightPoolScript := preload("res://gta/code/world/env/env_light_pool.gd")
const UnderwaterScript := preload("res://gta/code/world/env/env_underwater.gd")
const NightMaterialsScript := preload("res://gta/code/world/env/env_night_materials.gd")
const WET_GROUND_SHADER: Shader = preload("res://gta/code/world/shaders/env_wet_ground.gdshader")

const THUNDER_IDS: Array[String] = ["thunder_1", "thunder_2"]
const UNDERWATER_MARGIN := 0.03       ## the camera must be this far below the surface to enter
const UNDERWATER_EXIT_MARGIN := 0.02  ## ... and this far above it to leave (no flicker in the swell)
const STREET_LIGHT_GROUP := &"street_light"
const NO_HOOK_GROUP := &"env_no_night_hook"
const AUTO_HOOKS_PER_FRAME := 400     ## queued mesh instances checked per frame (cheap: cached per mesh)
const GROUP_SCAN_INTERVAL := 1.0      ## seconds between looks at the "street_light" group
const DEFAULT_LAMP_LIGHT := Color(1.0, 0.82, 0.56)

# Ocean palette (sRGB). The water is lit by the engine, so these are albedo colours.
const WATER_SHALLOW := Color(0.24, 0.82, 0.76)
const WATER_MID := Color(0.05, 0.50, 0.67)
const WATER_DEEP := Color(0.02, 0.19, 0.43)
const WATER_SHALLOW_STORM := Color(0.26, 0.52, 0.50)
const WATER_MID_STORM := Color(0.10, 0.30, 0.36)
const WATER_DEEP_STORM := Color(0.035, 0.12, 0.20)
const WATER_SHALLOW_NIGHT := Color(0.20, 0.44, 0.52)
const WATER_MID_NIGHT := Color(0.07, 0.24, 0.38)
const WATER_DEEP_NIGHT := Color(0.03, 0.09, 0.21)
const FOAM_COLOR := Color(0.96, 0.98, 1.0)

var sky: SkyControllerScript
var ocean: OceanSurfaceScript
var rain: RainScript
var light_pool: LightPoolScript
var underwater_overlay: UnderwaterScript
var night_materials: NightMaterialsScript = NightMaterialsScript.new()

var enabled: bool = true
var is_underwater: bool = false
var underwater_depth: float = 0.0
## Effective night value written to gta_night: the clock's night factor, lifted a little in
## gloomy weather so lamps and windows come on during a storm or dense fog.
var night_factor: float = 0.0
var time_seconds: float = 0.0         ## the value of the global uniform gta_time
## Swap the night-light hook materials into every mesh that enters the tree (see header).
var auto_night_materials: bool = true
## Give every Node3D in the group "street_light" a pooled night light (see header).
var auto_street_lights: bool = true

var _built: bool = false
var _pending_points: Array = []       ## registrations that arrived before the pool existed
var _last_cam_pos := Vector3.ZERO
var _hook_queue := PackedInt64Array() ## instance ids of mesh nodes waiting for the hook check
var _hook_head: int = 0
var _group_seen: Dictionary = {}      ## instance id -> true, "street_light" nodes already handled
var _group_scan_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


## Called by Main after add_child (BootManifest contract).
func setup() -> void:
	_build()
	refresh()


func _build() -> void:
	if _built:
		return
	_built = true
	sky = SkyControllerScript.new()
	sky.name = "Sky"
	add_child(sky)
	ocean = OceanSurfaceScript.new()
	ocean.name = "Ocean"
	add_child(ocean)
	rain = RainScript.new()
	rain.name = "Rain"
	add_child(rain)
	light_pool = LightPoolScript.new()
	light_pool.name = "StreetLightPool"
	add_child(light_pool)
	underwater_overlay = UnderwaterScript.new()
	underwater_overlay.name = "UnderwaterLayer"
	add_child(underwater_overlay)
	for reg: Dictionary in _pending_points:
		light_pool.register_points(reg["points"], reg["color"], reg["range"], reg["energy"])
	_pending_points.clear()
	_apply_settings()
	if not EventBus.settings_changed.is_connected(_apply_settings):
		EventBus.settings_changed.connect(_apply_settings)
	if not Weather.lightning_strike.is_connected(_on_lightning_strike):
		Weather.lightning_strike.connect(_on_lightning_strike)
	if is_inside_tree():
		var tree := get_tree()
		if not tree.node_added.is_connected(_on_node_added):
			tree.node_added.connect(_on_node_added)
		# Meshes that were in the tree before this system existed (the world is built first).
		_queue_existing(tree.root)


func _exit_tree() -> void:
	if is_underwater:
		_set_underwater(false)
	RenderingServer.global_shader_parameter_set(&"gta_underwater", 0.0)


func _process(delta: float) -> void:
	# Integration chores run even while the look is frozen (set_enabled(false)) or paused.
	if _hook_head < _hook_queue.size():
		_drain_hook_queue()
	if auto_street_lights:
		_group_scan_timer -= delta
		if _group_scan_timer <= 0.0:
			_group_scan_timer = GROUP_SCAN_INTERVAL
			_scan_street_light_group()
	if not enabled:
		return
	var dt := 0.0 if get_tree().paused else delta
	time_seconds += dt
	_update(dt)


## Re-applies the whole look immediately (after set_hour / snap_weather in the same frame).
func refresh() -> void:
	if _built:
		_update(0.0)


func _update(delta: float) -> void:
	var cam: Camera3D = null
	if is_inside_tree():
		cam = get_viewport().get_camera_3d()
	if cam != null:
		_last_cam_pos = cam.global_position
	elif Game.has_player():
		_last_cam_pos = Game.get_player_position()

	# --- ocean geometry first: the underwater test needs the current surface -------------
	var wind := Weather.wind_strength
	var amp := lerpf(ocean.CALM_WAVE_AMP, ocean.MAX_WAVE_AMP, smoothstep(0.2, 1.0, wind))
	ocean.update_surface(_last_cam_pos, time_seconds, amp)

	var under := false
	var depth := 0.0
	if cam != null:
		var surface_y := ocean.get_height(_last_cam_pos.x, _last_cam_pos.z)
		depth = surface_y - _last_cam_pos.y
		# Hysteresis: a camera bobbing at the waterline must not flip the whole look every wave.
		under = depth > (-UNDERWATER_EXIT_MARGIN if is_underwater else UNDERWATER_MARGIN)
		if under and Game.world != null and is_instance_valid(Game.world) and Game.world.has_method("is_water_at"):
			# Do not treat a camera clipped below the terrain as "in the sea".
			var probe := Vector3(_last_cam_pos.x, minf(_last_cam_pos.y, Game.WATER_LEVEL - 0.05), _last_cam_pos.z)
			under = bool(Game.world.is_water_at(probe))
	underwater_depth = maxf(depth, 0.0) if under else 0.0
	if under != is_underwater:
		_set_underwater(under)

	# --- sky, light, fog -------------------------------------------------------------------
	sky.update_look(delta, time_seconds, 1.0 if is_underwater else 0.0, underwater_depth)
	var gloom_lights := clampf(Weather.storminess * 0.5 + Weather.rain_intensity * 0.12
			+ Weather.fog_amount * 0.3, 0.0, 0.55)
	night_factor = maxf(sky.night, gloom_lights)

	# --- ocean colours ---------------------------------------------------------------------
	var storm := clampf(Weather.storminess * 0.8 + sky.overcast * 0.35, 0.0, 1.0)
	# Moonlight is blue already: pull the albedo towards a calmer navy at night so the sea
	# does not turn electric blue.
	var dusk := (1.0 - sky.day_factor) * 0.55
	ocean.set_colors(
			WATER_SHALLOW.lerp(WATER_SHALLOW_STORM, storm).lerp(WATER_SHALLOW_NIGHT, dusk),
			WATER_MID.lerp(WATER_MID_STORM, storm).lerp(WATER_MID_NIGHT, dusk),
			WATER_DEEP.lerp(WATER_DEEP_STORM, storm).lerp(WATER_DEEP_NIGHT, dusk),
			FOAM_COLOR,
			sky.sky_horizon,
			lerpf(0.16, 0.10, storm),
			smoothstep(0.45, 1.0, wind),
			lerpf(1.0, 0.6, storm))

	# --- rain --------------------------------------------------------------------------------
	var rain_lum := 0.30 + 0.70 * sky.day_factor
	var rain_color := Color(0.74, 0.80, 0.88) * rain_lum
	rain_color.a = 1.0
	rain.update_rain(cam, time_seconds, Weather.rain_intensity, Weather.get_wind_vector(),
			rain_color, Weather.lightning_flash, is_underwater)

	# --- pooled street lights + overlay ----------------------------------------------------
	light_pool.update_pool(cam, delta, night_factor)
	underwater_overlay.update_overlay(is_underwater, underwater_depth, sky.day_factor, time_seconds)

	_push_globals()


func _push_globals() -> void:
	var player_pos := Game.get_player_position() if Game.has_player() else _last_cam_pos
	RenderingServer.global_shader_parameter_set(&"gta_daylight", 1.0 - night_factor)
	RenderingServer.global_shader_parameter_set(&"gta_night", night_factor)
	RenderingServer.global_shader_parameter_set(&"gta_wetness", Weather.wetness)
	RenderingServer.global_shader_parameter_set(&"gta_rain", Weather.rain_intensity)
	RenderingServer.global_shader_parameter_set(&"gta_time", time_seconds)
	RenderingServer.global_shader_parameter_set(&"gta_wind", Weather.get_wind_vector())
	RenderingServer.global_shader_parameter_set(&"gta_underwater", 1.0 if is_underwater else 0.0)
	RenderingServer.global_shader_parameter_set(&"gta_player_pos", player_pos)


func _set_underwater(on: bool) -> void:
	is_underwater = on
	var audio := _autoload(&"Audio")
	if audio != null and audio.has_method("set_underwater"):
		audio.call("set_underwater", on)
	underwater_changed.emit(on)


## Autoloads of other modules are reached by path, never by their global name: if a neighbour's
## autoload script is broken (mid-edit) the sky, the sun and the sea must still come up.
func _autoload(autoload_name: StringName) -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null(NodePath(String(autoload_name)))


func _apply_settings() -> void:
	if sky == null:
		return
	var level: Variant = Settings.get_value("shadows")
	sky.apply_shadow_quality(int(level) if level != null else 2)


func _on_lightning_strike(distance: float, delay: float) -> void:
	if not is_inside_tree():
		return
	# Thunder arrives late and gets quieter / duller with distance. The timer runs in game time
	# (it waits while the tree is paused and follows Engine.time_scale).
	var timer := get_tree().create_timer(clampf(delay, 0.15, 7.0), false)
	timer.timeout.connect(_play_thunder.bind(distance))
	if distance < 600.0:
		var fx := _autoload(&"Fx")
		if fx != null and fx.has_method("shake_camera"):
			fx.call("shake_camera", 0.12 * (1.0 - distance / 600.0))


func _play_thunder(distance: float) -> void:
	var audio := _autoload(&"Audio")
	if audio == null or not audio.has_method("play"):
		return
	var id: String = THUNDER_IDS[randi() % THUNDER_IDS.size()]
	var volume := lerpf(2.0, -14.0, clampf(distance / 2600.0, 0.0, 1.0))
	var pitch := lerpf(1.05, 0.82, clampf(distance / 2600.0, 0.0, 1.0)) * randf_range(0.94, 1.06)
	audio.call("play", id, volume, pitch, "Ambience")


# --- automatic integration ----------------------------------------------------------------------

func _on_node_added(n: Node) -> void:
	if auto_night_materials and (n is MeshInstance3D or n is MultiMeshInstance3D):
		# Checked a little later from _process: code-built nodes often get their mesh after
		# add_child(), and a whole city entering the tree must not stall one frame.
		_hook_queue.append(n.get_instance_id())


func _queue_existing(root: Node) -> void:
	if not auto_night_materials or root == null:
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == self:
			continue
		if n is MeshInstance3D or n is MultiMeshInstance3D:
			_hook_queue.append(n.get_instance_id())
		for c in n.get_children():
			stack.append(c)


func _drain_hook_queue() -> void:
	var end := mini(_hook_queue.size(), _hook_head + AUTO_HOOKS_PER_FRAME)
	for i in range(_hook_head, end):
		var obj := instance_from_id(_hook_queue[i])
		if obj == null or not is_instance_valid(obj):
			continue
		var node := obj as Node
		if node == null or not node.is_inside_tree() or node.is_in_group(NO_HOOK_GROUP):
			continue
		if node is MeshInstance3D:
			night_materials.apply_to_instance(node as MeshInstance3D)
		elif node is MultiMeshInstance3D:
			var mm := (node as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null:
				night_materials.apply_to_mesh(mm.mesh)
	_hook_head = end
	if _hook_head >= _hook_queue.size():
		_hook_queue.clear()
		_hook_head = 0


## Lamp props only need to be in the group "street_light": their "Light" marker (or, without
## one, the top of their mesh) becomes a pooled light point owned by the node, so the light dies
## with the lamp. Optional metadata on the node: light_color (Color), light_range, light_energy.
func _scan_street_light_group() -> void:
	if light_pool == null or not is_inside_tree():
		return
	var nodes := get_tree().get_nodes_in_group(STREET_LIGHT_GROUP)
	for n: Node in nodes:
		var id := n.get_instance_id()
		if _group_seen.has(id):
			continue
		_group_seen[id] = true
		var n3 := n as Node3D
		if n3 == null:
			continue
		var anchor := n3.find_child("Light", true, false) as Node3D
		if anchor == null:
			anchor = _lamp_top_anchor(n3)
		var height := maxf(anchor.global_position.y - n3.global_position.y, 0.0)
		var color := DEFAULT_LAMP_LIGHT
		if n.has_meta(&"light_color") and n.get_meta(&"light_color") is Color:
			color = n.get_meta(&"light_color")
		var reach := clampf(height * 2.2, 5.0, 22.0)
		if n.has_meta(&"light_range"):
			reach = maxf(float(n.get_meta(&"light_range")), 1.0)
		var energy := clampf(1.0 + height * 0.3, 1.2, 3.2)
		if n.has_meta(&"light_energy"):
			energy = maxf(float(n.get_meta(&"light_energy")), 0.0)
		light_pool.register_points([anchor], color, reach, energy)
	# Forget lamps that no longer exist (the dictionary must not grow for ever).
	if _group_seen.size() > nodes.size() * 2 + 64:
		_group_seen.clear()
		for n: Node in nodes:
			_group_seen[n.get_instance_id()] = true


## Lamp without a "Light" marker: a helper node at the top of its mesh stands in for the lens.
func _lamp_top_anchor(lamp: Node3D) -> Node3D:
	var top := 0.0
	for c: Node in lamp.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := mi.global_transform * mi.mesh.get_aabb()
		top = maxf(top, box.end.y - lamp.global_position.y)
	if top <= 0.05:
		return lamp
	var anchor := Node3D.new()
	anchor.name = "EnvLightAnchor"
	lamp.add_child(anchor)
	anchor.global_position = lamp.global_position + Vector3(0.0, maxf(top - 0.3, 0.0), 0.0)
	return anchor


# --- public API ---------------------------------------------------------------------------------

## BootManifest optional hook: freezing the system keeps the last look on screen.
func set_enabled(on: bool) -> void:
	enabled = on


## World Y of the sea surface at (x, z) including the waves that are rendered there.
func get_wave_height(x: float, z: float) -> float:
	if ocean == null:
		return Game.WATER_LEVEL
	return ocean.get_height(x, z)


## Approximate surface normal of the sea at (x, z).
func get_water_normal(x: float, z: float) -> Vector3:
	if ocean == null:
		return Vector3.UP
	return ocean.get_normal(x, z)


func get_water_level() -> float:
	return Game.WATER_LEVEL


## Registers lamp positions for the pooled night lights. `points`: Array of Vector3 (the lamp
## lens position in world space; Transform3D and Node3D entries are accepted too).
## At night up to 14 real lights (no shadows) follow the camera over these points.
func register_light_points(points: Array, color: Color = Color(1.0, 0.82, 0.56),
		light_range: float = 15.0, energy: float = 3.0) -> void:
	if light_pool == null:
		_pending_points.append({"points": points.duplicate(), "color": color, "range": light_range, "energy": energy})
		return
	light_pool.register_points(points, color, light_range, energy)


## Removes every registered light point. Lamps that are still in the group "street_light" are
## picked up again by the next group scan (within a second) - they still exist, after all.
func clear_light_points() -> void:
	_pending_points.clear()
	_group_seen.clear()
	if light_pool != null:
		light_pool.clear_points()


func get_light_point_count() -> int:
	return light_pool.get_point_count() if light_pool != null else 0


func get_active_light_count() -> int:
	return light_pool.get_active_count() if light_pool != null else 0


## How many pooled street lights may be lit at once (0..14, default 14). The whole game shares
## a budget of about 16 positional lights near the player: lower this when headlights, police
## light bars and muzzle flashes need a bigger share.
func set_street_light_budget(count: int) -> void:
	if light_pool != null:
		light_pool.set_max_lights(count)


## Shared window glass material (Blender material "M_Window"): mirrors the sky by day, a
## pseudo-random subset of panes glows warm at night. Auto pane mode: building-kit UV cells when
## the mesh has UVs, the 4 m object-space grid otherwise (see docs/ENVIRONMENT.md).
func get_window_material() -> ShaderMaterial:
	return night_materials.get_window_material(night_materials.CELL_AUTO)


## Window material with an explicit pane mode: 0 auto, 1 UV cells, 2 object grid, 3 world grid.
func get_window_material_mode(cell_mode: int) -> ShaderMaterial:
	return night_materials.get_window_material(cell_mode)


## Variant of the window material for meshes that were merged in world space.
func get_window_material_world() -> ShaderMaterial:
	return night_materials.get_window_material(night_materials.CELL_WORLD_GRID)


## Lamp lens material (Blender material "M_LampGlow"): off by day, emissive at night.
func get_lamp_material(color: Color = Color(1.0, 0.80, 0.50)) -> ShaderMaterial:
	return night_materials.get_lamp_material(color)


## Neon / sign material (Blender materials "P_Neon*"): always emissive, stronger at night.
func get_neon_material(color: Color) -> ShaderMaterial:
	return night_materials.get_neon_material(color)


## New material using the reference wet-ground shader (env_wet_ground.gdshader): a flat-colour
## surface that darkens, turns glossy and collects puddles with gta_wetness. `puddles` 0..1 is
## how much standing water it collects (asphalt 1, pavement 0.6, sand / grass 0.1-0.2).
## Custom ground shaders should include env_wet.gdshaderinc instead (docs/ENVIRONMENT.md).
func make_wet_surface_material(color: Color = Color(1, 1, 1), puddles: float = 1.0,
		roughness: float = 0.92, use_vertex_color: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WET_GROUND_SHADER
	m.set_shader_parameter(&"tint", color)
	m.set_shader_parameter(&"puddle_amount", clampf(puddles, 0.0, 1.0))
	# Hard surfaces that hold puddles are also the ones that turn shiny when damp.
	m.set_shader_parameter(&"wet_gloss", clampf(0.12 + puddles, 0.0, 1.0))
	m.set_shader_parameter(&"base_roughness", clampf(roughness, 0.0, 1.0))
	m.set_shader_parameter(&"use_vertex_color", use_vertex_color)
	return m


## Hook material for a Blender material name, or null if the name is not a hook.
func get_night_material_for(material_name: String, source: Material = null) -> ShaderMaterial:
	return night_materials.get_material_for(material_name, source)


## Swaps M_Window / M_LampGlow / P_Neon* surfaces under `root` for the hook materials
## (surface overrides). Returns the number of replaced surfaces. With auto_night_materials on
## (default) this happens by itself for every mesh that enters the tree; calling it as well is
## harmless (surfaces that already carry a hook material are skipped).
func apply_night_materials(root: Node) -> int:
	return night_materials.apply_to(root)


## Same swap on a Mesh RESOURCE (every user of that mesh gets the hook materials). This is the
## way for MultiMesh geometry, which has no per-surface overrides. Returns the replaced count.
func apply_night_materials_to_mesh(mesh: Mesh) -> int:
	return night_materials.apply_to_mesh(mesh)


func is_camera_underwater() -> bool:
	return is_underwater


## Unit vector pointing to the sun (below the horizon at night).
func get_sun_direction() -> Vector3:
	return WorldClock.get_sun_direction()


## Unit vector pointing to the light that currently casts the shadows (sun or moon).
func get_light_direction() -> Vector3:
	return sky.light_dir if sky != null else WorldClock.get_sun_direction()


func get_sun_light() -> DirectionalLight3D:
	return sky.sun_light if sky != null else null


func get_environment() -> Environment:
	return sky.env if sky != null else null


## Numbers for debug overlays / the admin menu.
func get_debug_info() -> Dictionary:
	return {
		"time": WorldClock.get_time_string(),
		"phase": WorldClock.get_phase(),
		"weather": Weather.current,
		"night": night_factor,
		"wetness": Weather.wetness,
		"underwater": is_underwater,
		"light_points": get_light_point_count(),
		"lights_active": get_active_light_count(),
		"wave_amp": ocean.wave_amp if ocean != null else 0.0,
	}
