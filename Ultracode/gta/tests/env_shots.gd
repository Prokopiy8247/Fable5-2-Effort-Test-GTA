extends Node
## ENVIRONMENT screenshot test (windowed, short). Takes the look-dev shots listed in SHOTS with
## its own Camera3D near the shore and saves them to qa/screenshots/env_*.png.
## Run (isolated, ~17 s at the 30 fps cap):
##   tools\godot.ps1 -Mode window -Frames 520 -UserArgs '--test=env_shots','--no_player','--disable=world,city,interactions,vehicles,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## With the world system loaded (drop "world,city" from --disable) the camera goes to the
## "beach" / "shipwreck" / "downtown_plaza" / "marina_dock" locations and no stage is built.
## Optional: --env-only=<text> keeps only shots whose name contains <text>.
##
## The stage (only when there is no world) is a look-dev set: a code-built beach sloping into the
## sea, a road + pavement strip on the wet-surface hook shader and a pier (scaffolding standing
## in for the WORLD module's terrain), dressed with the REAL Blender assets of the project where
## they exist: buildings (M_Window UV cells, P_Neon* signs), street lamps (M_LampGlow lens +
## "Light" marker, group "street_light"), palms, beach props, a moored boat and a buoy riding
## get_wave_height(), sea-bed dressing. Nothing here calls apply_night_materials() or
## register_light_points(): the shots also prove the automatic integration path.
## Missing GLBs fall back to plain boxes and are listed in the log. Never game content.

const SHOTS: Array[Dictionary] = [
	{"name": "env_01_noon_clear", "hour": 12.0, "weather": "clear"},
	{"name": "env_02_sunset_clear", "hour": 19.5, "weather": "clear"},
	{"name": "env_03_night_clear", "hour": 23.0, "weather": "clear"},
	{"name": "env_04_rain_1400", "hour": 14.0, "weather": "rain"},
	{"name": "env_05_fog_0900", "hour": 9.0, "weather": "fog"},
	{"name": "env_06_storm_2100", "hour": 21.0, "weather": "storm"},
	{"name": "env_07_storm_flash", "hour": 21.0, "weather": "storm", "flash": true},
	{"name": "env_08_underwater", "hour": 12.0, "weather": "clear", "underwater": true},
	{"name": "env_09_cloudy_1630", "hour": 16.5, "weather": "cloudy"},
	{"name": "env_10_dawn_0610", "hour": 6.15, "weather": "clear", "east": true},
	{"name": "env_11_water_noon", "hour": 12.5, "weather": "clear", "cam": "water"},
	{"name": "env_12_street_night", "hour": 22.0, "weather": "clear", "cam": "street"},
	{"name": "env_13_street_rain_dusk", "hour": 19.9, "weather": "rain", "cam": "street"},
	{"name": "env_14_roof_storm", "hour": 15.0, "weather": "storm", "cam": "roof"},
	{"name": "env_15_moon_east", "hour": 22.5, "weather": "clear", "cam": "moon"},
	{"name": "env_16_wet_road_night", "hour": 22.5, "weather": "rain", "cam": "road"},
	{"name": "env_17_wet_road_day", "hour": 16.0, "weather": "cloudy", "cam": "road", "wetness": 0.85},
	{"name": "env_18_windows_close", "hour": 21.5, "weather": "clear", "cam": "windows"},
	{"name": "env_19_harbour_dusk", "hour": 19.0, "weather": "cloudy", "cam": "harbour"},
]
const SETTLE_FRAMES := 22
const MODELS := "res://gta/generated/models/"
const PLATEAU := 2.5

var _cam: Camera3D
var _stage: Node3D
var _env: Node
var _floaters: Array[Node3D] = []       ## boat / buoy: ride the waves through get_wave_height()
var _missing: PackedStringArray = []
var _real_buildings: Array[Node3D] = []
var _real_lamps: int = 0
var _shore_pos := Vector3(70.0, 4.0, -8.0)
var _shore_target := Vector3(-30.0, 3.0, -16.0)
var _east_target := Vector3(170.0, 5.0, 6.0)
var _water_pos := Vector3(26.0, 2.6, 30.0)
var _water_target := Vector3(-40.0, 0.0, 8.0)
var _street_pos := Vector3(34.0, 4.3, -30.0)
var _street_target := Vector3(-20.0, 4.0, -50.0)
var _roof_pos := Vector3(60.3, 4.4, -69.4)
var _roof_target := Vector3(30.0, 3.6, -50.0)
var _road_pos := Vector3(62.0, 4.1, -39.2)
var _road_target := Vector3(-10.0, 2.9, -41.5)
var _dive_pos := Vector3(14.0, -2.0, 46.0)
var _dive_target := Vector3(-4.0, -1.6, 14.0)
var _windows_pos := Vector3(-11.0, 5.2, -39.0)
var _windows_target := Vector3(-17.0, 11.5, -50.5)
var _harbour_pos := Vector3(17.0, 1.5, 34.0)
var _harbour_target := Vector3(3.0, 0.7, 25.5)


func _ready() -> void:
	await _run()


func _process(_delta: float) -> void:
	# Floating props follow the same wave function the game's boats and swimmers use.
	if _env == null or _floaters.is_empty():
		return
	for f in _floaters:
		if not is_instance_valid(f):
			continue
		var p := f.global_position
		var n: Vector3 = _env.call("get_water_normal", p.x, p.z)
		var yaw: float = f.get_meta("yaw", 0.0)
		var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
		var right := fwd.cross(n).normalized()
		f.global_transform = Transform3D(Basis(right, n, right.cross(n)).orthonormalized(),
				Vector3(p.x, float(_env.call("get_wave_height", p.x, p.z)), p.z))


func _run() -> void:
	var t := TestHarness
	var env := Game.get_system("environment")
	if not t.check(env != null, "environment system is loaded"):
		t.finish(false, "no environment system")
		return
	_env = env
	if UI.has_method("set_hud_visible"):
		UI.set_hud_visible(false)
	Weather.auto_cycle = false
	WorldClock.paused = true

	if Game.world == null:
		_build_stage(env)
	else:
		_use_world_locations()

	_cam = Camera3D.new()
	_cam.name = "EnvShotCamera"
	_cam.fov = 62.0
	_cam.near = 0.1
	_cam.far = 4000.0
	add_child(_cam)
	_cam.global_position = _shore_pos
	_cam.look_at(_shore_target)
	_cam.current = true

	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--env-only="):
			only = a.substr(11)

	# Render cost of the frame that is captured (the run stays capped at 30 fps).
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)

	if _stage != null:
		await t.wait_frames(4)
		_check_auto_integration(env)

	var taken := 0
	for shot: Dictionary in SHOTS:
		var shot_name: String = shot["name"]
		if only != "" and not shot_name.contains(only):
			continue
		WorldClock.set_hour(float(shot["hour"]))
		Weather.snap_weather(str(shot["weather"]), float(shot.get("wetness", -1.0)))
		var cam_id := str(shot.get("cam", ""))
		if shot.get("underwater", false):
			_cam.global_position = _dive_pos
			_cam.look_at(_dive_target)
		elif shot.get("east", false):
			_cam.global_position = _shore_pos
			_cam.look_at(_east_target)
		elif cam_id == "water":
			_cam.global_position = _water_pos
			_cam.look_at(_water_target)
		elif cam_id == "street":
			_cam.global_position = _street_pos
			_cam.look_at(_street_target)
		elif cam_id == "roof":
			_cam.global_position = _roof_pos
			_cam.look_at(_roof_target)
		elif cam_id == "road":
			_cam.global_position = _road_pos
			_cam.look_at(_road_target)
		elif cam_id == "windows":
			_cam.global_position = _windows_pos
			_cam.look_at(_windows_target)
		elif cam_id == "harbour":
			_cam.global_position = _harbour_pos
			_cam.look_at(_harbour_target)
		elif cam_id == "moon":
			_cam.global_position = _shore_pos
			var md := WorldClock.get_moon_direction()
			_cam.look_at(_shore_pos + Vector3(md.x, md.y * 0.55, md.z) * 100.0)
		else:
			_cam.global_position = _shore_pos
			_cam.look_at(_shore_target)
		await t.wait_frames(SETTLE_FRAMES)
		if shot.get("flash", false):
			Weather.lightning_flash = 1.0
		var path: String = await t.shot(shot_name)
		if not t.is_headless():
			t.check(path != "", "saved " + shot_name)
		if shot.get("underwater", false):
			t.check(env.is_camera_underwater(), "underwater state is active for the dive shot")
		if _stage != null and cam_id == "street" and float(shot["hour"]) > 21.0 and _real_lamps > 0:
			t.check(int(env.get_light_point_count()) >= _real_lamps and int(env.get_active_light_count()) > 0,
					"street lamps in group street_light got pooled lights by themselves (%d points, %d lit)" % [
					env.get_light_point_count(), env.get_active_light_count()])
		taken += 1
		t.log_line("%s  hour=%.2f weather=%s info=%s" % [shot_name, WorldClock.hour, Weather.current, str(env.get_debug_info())])
		t.log_line("%s  gpu_ms=%.2f cpu_ms=%.2f draw_calls=%d primitives=%d" % [shot_name,
				RenderingServer.viewport_get_measured_render_time_gpu(vp_rid),
				RenderingServer.viewport_get_measured_render_time_cpu(vp_rid),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	t.check(taken > 0, "at least one shot taken")
	if not _missing.is_empty():
		t.log_line("stage assets missing (plain boxes used instead): " + ", ".join(_missing))
	WorldClock.paused = false
	Weather.auto_cycle = true
	t.finish()


func _use_world_locations() -> void:
	var beach := Game.get_location("beach").origin
	var gy := maxf(Game.ground_height(beach.x, beach.z), Game.WATER_LEVEL)
	_shore_pos = Vector3(beach.x + 30.0, gy + 3.2, beach.z + 6.0)
	_shore_target = Vector3(beach.x - 70.0, gy + 2.0, beach.z - 4.0)
	_east_target = Vector3(beach.x + 130.0, gy + 4.0, beach.z + 20.0)
	var wreck := Game.get_location("shipwreck").origin
	var floor_y := Game.ground_height(wreck.x, wreck.z)
	_dive_target = Vector3(wreck.x, minf(floor_y + 2.0, -2.0), wreck.z)
	_dive_pos = _dive_target + Vector3(12.0, 0.0, 10.0)
	_dive_pos.y = clampf(floor_y + 4.0, -9.0, -1.6)
	_water_pos = Vector3(beach.x + 10.0, Game.WATER_LEVEL + 2.6, beach.z + 40.0)
	_water_target = Vector3(beach.x - 50.0, Game.WATER_LEVEL, beach.z + 10.0)
	var plaza := Game.get_location("downtown_plaza").origin
	_street_pos = plaza + Vector3(18.0, 2.2, 14.0)
	_street_target = plaza + Vector3(-20.0, 3.0, -20.0)
	_roof_pos = _street_pos
	_roof_target = _street_target
	_road_pos = _street_pos
	_road_target = _street_target
	_windows_pos = plaza + Vector3(6.0, 3.0, 6.0)
	_windows_target = plaza + Vector3(-14.0, 14.0, -18.0)
	var dock := Game.get_location("marina_dock").origin
	_harbour_pos = Vector3(dock.x, maxf(dock.y, Game.WATER_LEVEL) + 1.8, dock.z)
	_harbour_target = _harbour_pos + Vector3(-20.0, -1.4, 14.0)


## The automatic integration path on the real assets of the stage (no explicit API call was made).
func _check_auto_integration(env: Node) -> void:
	var t := TestHarness
	if _real_buildings.is_empty():
		t.log_line("no real building GLB on the stage - automatic hook check skipped")
		return
	var nm: Variant = env.get("night_materials")
	var hooked := 0
	var uv_mode := 0
	var neon := 0
	for b in _real_buildings:
		for c: Node in b.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			for s in mi.get_surface_override_material_count():
				var m := mi.get_surface_override_material(s) as ShaderMaterial
				if m == null or not nm.is_hook_material(m):
					continue
				if String(m.resource_name).begins_with("M_Window"):
					hooked += 1
					if int(m.get_shader_parameter("cell_mode")) == 1:
						uv_mode += 1
				elif String(m.resource_name).begins_with("P_Neon"):
					neon += 1
	t.check(hooked >= _real_buildings.size() and uv_mode == hooked,
			"real building GLBs got the lit-window material in UV-cell mode by themselves (%d glass surfaces on %d buildings, %d neon)" % [
			hooked, _real_buildings.size(), neon])


# --- look-dev stage ---------------------------------------------------------------------------

func _stage_height(x: float, z: float) -> float:
	var shore := 8.0 * sin(x * 0.035)
	var h := (shore - z) * 0.1
	if h < 0.0:
		h *= 1.15
	return clampf(h, -13.0, PLATEAU)


func _on_ground(x: float, z: float) -> Vector3:
	return Vector3(x, _stage_height(x, z), z)


## Instances a project GLB on the stage; null (and a log entry) when the file does not exist.
func _asset(rel: String, pos: Vector3, yaw_deg: float = 0.0, scale: float = 1.0) -> Node3D:
	var path := MODELS + rel
	if not ResourceLoader.exists(path):
		if not _missing.has(rel):
			_missing.append(rel)
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	if n == null:
		return null
	_stage.add_child(n)
	n.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3.ONE * scale), pos)
	return n


## Static trimesh colliders for every mesh of a stage asset (rain splash rays need colliders).
func _stage_mesh_colliders(root: Node3D, surface: String = "wood") -> void:
	for c: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or String(mi.name).begins_with("Col_"):
			continue
		var body := StaticBody3D.new()
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.set_meta("surface", surface)
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		body.add_child(cs)
		_stage.add_child(body)
		body.global_transform = mi.global_transform


func _build_stage(env: Node) -> void:
	_stage = Node3D.new()
	_stage.name = "EnvShotStage"
	add_child(_stage)

	# Ground: flat-shaded grid with vertex colours (sand / grass / wet sand).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell := 4.0
	var half := 60
	for j in range(-half, half):
		for i in range(-half, half):
			var x0 := float(i) * cell
			var z0 := float(j) * cell
			var x1 := x0 + cell
			var z1 := z0 + cell
			var a := Vector3(x0, _stage_height(x0, z0), z0)
			var b := Vector3(x1, _stage_height(x1, z0), z0)
			var c := Vector3(x0, _stage_height(x0, z1), z1)
			var d := Vector3(x1, _stage_height(x1, z1), z1)
			_stage_tri(st, a, b, c)
			_stage_tri(st, d, c, b)
	var ground_mesh := st.commit()
	# Wet-surface hook (reference shader): sand and grass darken in the rain, few puddles.
	var ground_mat: ShaderMaterial = env.call("make_wet_surface_material", Color(1, 1, 1), 0.16, 0.95, true)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = ground_mesh
	ground.material_override = ground_mat
	_stage.add_child(ground)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.set_meta("surface", "sand")
	var shape := CollisionShape3D.new()
	shape.shape = ground_mesh.create_trimesh_shape()
	body.add_child(shape)
	_stage.add_child(body)

	# Road + pavement strip in front of the buildings (wet-surface hook: puddles, reflections).
	var road_mat: ShaderMaterial = env.call("make_wet_surface_material", Color(0.30, 0.31, 0.335), 1.0, 0.88, false)
	var pave_mat: ShaderMaterial = env.call("make_wet_surface_material", Color(0.62, 0.61, 0.58), 0.55, 0.9, false)
	_stage_solid(Vector3(4.0, PLATEAU, -39.5), Vector3(140.0, 0.06, 8.0), road_mat, "asphalt")
	_stage_solid(Vector3(4.0, PLATEAU + 0.03, -46.75), Vector3(140.0, 0.12, 6.5), pave_mat, "concrete")
	_stage_solid(Vector3(-10.0, PLATEAU + 0.02, -62.0), Vector3(112.0, 0.10, 24.0), pave_mat, "concrete")
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.92, 0.90, 0.80)
	paint.roughness = 0.7
	for i in 17:
		_stage_box(Vector3(-60.0 + float(i) * 8.0, PLATEAU + 0.032, -39.5), Vector3(3.0, 0.01, 0.16), paint)

	# Buildings: real GLBs (front faces the road = +Z, so yaw 180), plain blocks when missing.
	env.call("clear_light_points")
	var front_z := -50.6
	var row: Array[Dictionary] = [
		{"id": "apartment_a", "x": -44.0, "size": Vector3(24.1, 24.7, 16.1), "wall": Color(0.86, 0.80, 0.70), "neon": Color(1.0, 0.25, 0.55)},
		{"id": "office_a", "x": -16.5, "size": Vector3(24.0, 46.4, 20.0), "wall": Color(0.70, 0.78, 0.82), "neon": Color(1.0, 0.85, 0.2)},
		{"id": "storefront_d", "x": 6.5, "size": Vector3(15.9, 12.8, 14.1), "wall": Color(0.93, 0.55, 0.45), "neon": Color(0.15, 0.9, 1.0)},
		{"id": "storefront_a", "x": 27.5, "size": Vector3(20.4, 9.8, 12.4), "wall": Color(0.55, 0.72, 0.70), "neon": Color(0.5, 1.0, 0.4)},
	]
	for e: Dictionary in row:
		var size: Vector3 = e["size"]
		var centre := Vector3(float(e["x"]), PLATEAU + 0.07, front_z - size.z * 0.5)
		var b := _asset("buildings/%s.glb" % str(e["id"]), centre, 180.0)
		if b != null:
			_real_buildings.append(b)
			_stage_collider(centre + Vector3(0.0, size.y * 0.5, 0.0), size)
		else:
			_stage_block(env, centre, Vector3(snappedf(size.x, 4.0), size.y, snappedf(size.z, 4.0)), e["wall"], e["neon"])

	# Street lamps: real prop, arm over the road, only tagged with the group "street_light".
	var fallback_points: Array = []
	for i in 7:
		var lamp_pos := Vector3(56.0 - float(i) * 16.0, PLATEAU + 0.09, -44.4)
		var lamp := _asset("props/street_lamp_a.glb", lamp_pos, 180.0)
		if lamp != null:
			lamp.add_to_group("street_light")
			_real_lamps += 1
		else:
			fallback_points.append(_stage_lamp(env, lamp_pos))
	if not fallback_points.is_empty():
		env.call("register_light_points", fallback_points, Color(1.0, 0.80, 0.52), 16.0, 3.0)
	_asset("props/neon_sign_b.glb", Vector3(-31.0, PLATEAU + 5.2, front_z + 0.12), 180.0)

	# Shelter (rain must not fall or splash under it): the park gazebo, or a plain canopy.
	var slab := StandardMaterial3D.new()
	slab.albedo_color = Color(0.80, 0.82, 0.84)
	slab.roughness = 0.8
	var gazebo := _asset("misc/gazebo.glb", Vector3(60.0, PLATEAU, -70.0), 150.0)
	if gazebo != null:
		_stage_mesh_colliders(gazebo)
	else:
		_stage_solid(Vector3(60.0, 8.0, -70.0), Vector3(16.0, 0.3, 16.0), slab)
		for cx: float in [-7.4, 7.4]:
			for cz: float in [-7.4, 7.4]:
				_stage_solid(Vector3(60.0 + cx, 5.2, -70.0 + cz), Vector3(0.4, 5.4, 0.4), slab)
		_roof_pos = Vector3(60.0, 4.3, -70.0)

	# Beach dressing.
	_asset("nature/palm_a.glb", _on_ground(52.0, -15.0), 40.0)
	_asset("nature/palm_b.glb", _on_ground(33.0, -21.0), 200.0)
	_asset("nature/palm_a.glb", _on_ground(15.0, -25.0), 120.0)
	_asset("nature/palm_b.glb", _on_ground(-9.0, -23.0), 300.0)
	_asset("nature/palm_a.glb", _on_ground(-33.0, -21.0), 250.0)
	_asset("nature/palm_b.glb", _on_ground(74.0, -24.0), 10.0)
	var tower := _asset("misc/lifeguard_tower.glb", Vector3(45.0, PLATEAU, -19.6), 0.0)
	if tower != null:
		_stage_mesh_colliders(tower)
	_asset("misc/beach_umbrella.glb", _on_ground(55.0, -1.5), 25.0)
	_asset("misc/lounger.glb", _on_ground(56.4, -0.6), 95.0)
	_asset("misc/lounger.glb", _on_ground(56.2, -2.6), 82.0)
	_asset("misc/beach_umbrella.glb", _on_ground(28.0, -5.0), 110.0)
	_asset("misc/lounger.glb", _on_ground(29.4, -4.2), 275.0)

	# Pier with pillars standing in the water (foam rings).
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.38, 0.24)
	wood.roughness = 0.9
	_stage_box(Vector3(20.0, 1.0, 22.0), Vector3(3.2, 0.25, 44.0), wood)
	for k in 6:
		var pz := 4.0 + float(k) * 7.6
		_stage_box(Vector3(18.7, -2.0, pz), Vector3(0.35, 6.2, 0.35), wood)
		_stage_box(Vector3(21.3, -2.0, pz), Vector3(0.35, 6.2, 0.35), wood)
	_stage_box(Vector3(34.0, 0.3, 3.0), Vector3(2.4, 2.2, 2.0), _stage_rock_material())

	# Floating props ride the waves (origin at the waterline by their manifest).
	var boat := _asset("misc/fishing_boat_static.glb", Vector3(9.5, 0.0, 24.0), 25.0)
	if boat != null:
		boat.set_meta("yaw", deg_to_rad(25.0))
		_floaters.append(boat)
	var buoy := _asset("misc/buoy.glb", Vector3(3.0, 0.0, 29.5), 0.0)
	if buoy != null:
		buoy.set_meta("yaw", 0.0)
		_floaters.append(buoy)

	# Sea bed in front of the dive camera.
	# (the stage sea is only 3-5 m deep here: the 5.3 m kelp is scaled to stay under water)
	var bed := [
		["nature/kelp_a.glb", 12.6, 37.2, 0.0, 0.62], ["nature/kelp_a.glb", 5.6, 38.6, 140.0, 0.55],
		["nature/kelp_a.glb", 15.4, 33.0, 60.0, 0.5], ["nature/coral_a.glb", 9.6, 40.6, 30.0, 1.0],
		["nature/coral_b.glb", 11.9, 41.8, 200.0, 1.0], ["nature/coral_c.glb", 7.0, 35.2, 90.0, 1.0],
		["nature/coral_a.glb", 3.0, 33.4, 250.0, 1.0], ["nature/sunken_crate.glb", 8.6, 33.6, 35.0, 1.0],
		["nature/anchor.glb", 4.6, 30.6, 70.0, 1.0], ["nature/rock_c.glb", 13.4, 39.6, 10.0, 1.0],
		["nature/rock_d.glb", 1.4, 28.4, 100.0, 1.0], ["nature/starfish.glb", 10.4, 42.6, 0.0, 1.0],
		["nature/starfish.glb", 8.2, 37.4, 130.0, 1.0],
	]
	var dressed := 0
	for e: Array in bed:
		if _asset(str(e[0]), _on_ground(float(e[1]), float(e[2])), float(e[3]), float(e[4])) != null:
			dressed += 1
	_asset("animals/shark.glb", Vector3(2.5, -1.9, 31.5), 115.0)
	for k in 7:
		_asset("animals/fish_small.glb", Vector3(9.0 + sin(float(k) * 2.4) * 1.6, -2.6 + cos(float(k) * 1.7) * 0.5,
				38.0 + cos(float(k) * 2.1) * 1.4), 100.0 + float(k) * 9.0)
	if dressed == 0:
		var crate := StandardMaterial3D.new()
		crate.albedo_color = Color(0.80, 0.62, 0.30)
		crate.roughness = 0.9
		_stage_box(Vector3(2.0, _stage_height(2.0, 26.0) + 0.6, 26.0), Vector3(1.2, 1.2, 1.2), crate)
		_stage_box(Vector3(8.0, _stage_height(8.0, 32.0) + 0.8, 32.0), Vector3(2.6, 1.6, 2.0), _stage_rock_material())


func _stage_rock_material() -> StandardMaterial3D:
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.45, 0.47, 0.50)
	rock.roughness = 1.0
	return rock


func _stage_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (c - a).cross(b - a).normalized()
	var y := (a.y + b.y + c.y) / 3.0
	var col: Color
	if y < -0.3:
		col = Color(0.78, 0.72, 0.52).lerp(Color(0.52, 0.50, 0.40), clampf(-y / 8.0, 0.0, 1.0))
	elif y < 1.9:
		col = Color(0.93, 0.86, 0.64)
	elif y < 2.45:
		col = Color(0.80, 0.80, 0.56)
	else:
		col = Color(0.45, 0.68, 0.36)
	# Small per-facet tone step so the low-poly facets read.
	var tone := 0.94 + 0.12 * fposmod(sin(a.x * 12.9898 + a.z * 78.233) * 43758.5453, 1.0)
	col = Color(col.r * tone, col.g * tone, col.b * tone)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(c)


func _stage_box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	_stage.add_child(mi)
	mi.global_position = pos
	return mi


## Invisible static box on the world layer (rain splash rays need colliders).
func _stage_collider(pos: Vector3, size: Vector3, surface: String = "concrete") -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	_stage.add_child(body)
	body.global_position = pos


## Box with a static collider on the world layer.
func _stage_solid(pos: Vector3, size: Vector3, mat: Material, surface: String = "concrete") -> void:
	_stage_box(pos, size, mat)
	_stage_collider(pos, size, surface)


## Fallback for a missing building GLB: a plain block (origin at the footprint centre on the
## ground) with window quads on the +Z and +X faces (object-grid pane mode) and a neon strip.
func _stage_block(env: Node, ground_pos: Vector3, size: Vector3, wall: Color, neon: Color) -> void:
	var root := Node3D.new()
	_stage.add_child(root)
	root.global_position = ground_pos
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = wall
	wall_mat.roughness = 0.85
	var shell := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	shell.mesh = bm
	shell.material_override = wall_mat
	shell.position = Vector3(0.0, size.y * 0.5, 0.0)
	root.add_child(shell)
	_stage_collider(ground_pos + Vector3(0.0, size.y * 0.5, 0.0), size)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var floors := int(round((size.y - 4.0) / 3.2)) + 1
	for f in floors:
		var y0 := 0.5 if f == 0 else 4.0 + float(f - 1) * 3.2 + 0.9
		var y1 := 3.1 if f == 0 else 4.0 + float(f - 1) * 3.2 + 2.6
		var w := 1.8
		var nx := int(round(size.x / 4.0))
		for m in nx:
			var cx := -hx + 2.0 + float(m) * 4.0
			var z := hz + 0.04
			_stage_quad(st, Vector3(cx - w * 0.5, y1, z), Vector3(cx + w * 0.5, y1, z),
					Vector3(cx + w * 0.5, y0, z), Vector3(cx - w * 0.5, y0, z), Vector3(0, 0, 1))
		var nz := int(round(size.z / 4.0))
		for m in nz:
			var cz := -hz + 2.0 + float(m) * 4.0
			var x := hx + 0.04
			_stage_quad(st, Vector3(x, y1, cz + w * 0.5), Vector3(x, y1, cz - w * 0.5),
					Vector3(x, y0, cz - w * 0.5), Vector3(x, y0, cz + w * 0.5), Vector3(1, 0, 0))
	var windows := MeshInstance3D.new()
	windows.name = "Windows"
	windows.mesh = st.commit()
	windows.material_override = env.call("get_window_material")
	windows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(windows)

	var sign_front := MeshInstance3D.new()
	var sf := BoxMesh.new()
	sf.size = Vector3(minf(size.x - 2.0, 8.0), 0.9, 0.18)
	sign_front.mesh = sf
	sign_front.material_override = env.call("get_neon_material", neon)
	sign_front.position = Vector3(0.0, 3.75, hz + 0.12)
	sign_front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sign_front)


## Quad a (top-left), b (top-right), c (bottom-right), d (bottom-left) as seen from outside.
func _stage_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var verts: Array[Vector3] = [a, b, c, a, c, d]
	for i in 6:
		st.set_normal(n)
		st.add_vertex(verts[i])


## Fallback for a missing lamp GLB: a plain post with a lens that uses the lamp hook material.
## Returns the lens position.
func _stage_lamp(env: Node, ground_pos: Vector3) -> Vector3:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.20, 0.23, 0.27)
	metal.roughness = 0.6
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.10
	cyl.height = 6.0
	cyl.radial_segments = 8
	pole.mesh = cyl
	pole.material_override = metal
	_stage.add_child(pole)
	pole.global_position = ground_pos + Vector3(0.0, 3.0, 0.0)
	_stage_box(ground_pos + Vector3(0.0, 6.0, 0.7), Vector3(0.12, 0.12, 1.6), metal)
	var lens_pos := ground_pos + Vector3(0.0, 5.88, 1.3)
	var lens := _stage_box(lens_pos, Vector3(0.42, 0.14, 0.7), env.call("get_lamp_material"))
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return lens_pos
