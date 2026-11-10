extends Node3D
## QA showcase for the two-wheel + boat GLBs (author: two-wheel & boat artist).
## Isolated scene, no world boot: instantiates every model of IDS that exists, puts it on a small
## look-dev stage (ground for bikes, a flat "water" sheet at y = 0 for boats) and saves two
## screenshots per model (plus one of Body_LOD1 where present) to qa/screenshots/bb_<id>_*.png.
## It also prints the contract nodes it found, so it doubles as a headless structure check.
##
## Run (windowed, ~8 s):
##   tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/bb_showcase.tscn -Frames 400
## Headless (structure check only, no pictures):
##   tools\godot.ps1 -Mode headless -Scene res://gta/tests/scenes/bb_showcase.tscn -Frames 400
## The stage is test scaffolding built from primitives, never game content.

const MODEL_DIR := "res://gta/generated/models/vehicles/"
const IDS: Array[String] = ["motorcycle", "bicycle", "speedboat", "jetski", "dinghy"]
const BOATS: Array[String] = ["speedboat", "jetski", "dinghy"]
const REQUIRED := {
	"motorcycle": ["Body", "Handlebar", "Wheel_F", "Wheel_R", "Col_Body", "Seat_Driver", "Seat_Passenger_1",
		"Exit_Driver", "Light_Head", "Light_Tail", "Exhaust", "Engine", "Steer_Axis", "Grip_L", "Grip_R",
		"Footrest_L", "Footrest_R"],
	"bicycle": ["Body", "Handlebar", "Crank", "Wheel_F", "Wheel_R", "Col_Body", "Seat_Driver", "Exit_Driver",
		"Steer_Axis", "Grip_L", "Grip_R", "Pedal_L", "Pedal_R"],
	"speedboat": ["Body", "Glass_Windshield", "SteeringWheel", "Motor", "Col_Body", "Seat_Driver",
		"Seat_Passenger_1", "Seat_Passenger_2", "Seat_Passenger_3", "Exit_Driver", "Prop", "Wake_L", "Wake_R",
		"Engine", "Light_Head"],
	"jetski": ["Body", "Handlebar", "Motor", "Col_Body", "Seat_Driver", "Seat_Passenger_1", "Exit_Driver", "Prop",
		"Wake_L", "Wake_R", "Engine", "Light_Head", "Steer_Axis", "Grip_L", "Grip_R", "Footrest_L", "Footrest_R"],
	"dinghy": ["Body", "Motor", "Col_Body", "Seat_Driver", "Seat_Passenger_1", "Exit_Driver", "Prop",
		"Wake_L", "Wake_R", "Engine"],
}

var _cam: Camera3D
var _ground: MeshInstance3D
var _water: MeshInstance3D
var _fails: int = 0


func _ready() -> void:
	await _run()


func _run() -> void:
	_build_stage()
	var headless := DisplayServer.get_name() == "headless"
	for id: String in IDS:
		var path := MODEL_DIR + id + ".glb"
		if not ResourceLoader.exists(path):
			print("BB_SHOWCASE: skip (no file) ", path)
			continue
		var ps := load(path) as PackedScene
		if ps == null:
			_fail("%s: not a PackedScene" % id)
			continue
		var inst := ps.instantiate() as Node3D
		add_child(inst)
		_check_nodes(id, inst)
		var lod := inst.find_child("Body_LOD1", true, false) as Node3D
		for n: Node in inst.find_children("Col_*", "MeshInstance3D", true, false):
			(n as Node3D).visible = false
		if lod != null:
			lod.visible = false
		var boat := BOATS.has(id)
		_ground.visible = not boat
		_water.visible = boat
		var box := _aabb_of(inst)
		print("BB_SHOWCASE: %s aabb pos=%s size=%s lod=%s" % [id, box.position, box.size, lod != null])
		if not headless:
			var c := box.get_center()
			var r := box.size.length() * 0.5
			await _shot(id + "_a", c + Vector3(r * 1.3, r * 0.75, -r * 1.85), c)
			await _shot(id + "_b", c + Vector3(-r * 1.4, r * 0.85, r * 1.75), c)
			await _shot(id + "_c", c + Vector3(r * 2.5, r * 0.2, 0.0), c)
			if lod != null:
				for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
					var nm := String(n.name)
					(n as Node3D).visible = nm == "Body_LOD1" or nm.begins_with("Wheel")
				await _shot(id + "_lod1", c + Vector3(r * 1.3, r * 0.75, -r * 1.85), c)
		inst.queue_free()
		await get_tree().process_frame
	print("TEST_RESULT: %s bb_showcase failures=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _fail(msg: String) -> void:
	_fails += 1
	print("CHECK_FAIL: bb_showcase ", msg)


func _check_nodes(id: String, inst: Node3D) -> void:
	var missing: PackedStringArray = []
	for nm: String in REQUIRED.get(id, []):
		if inst.find_child(nm, true, false) == null:
			missing.append(nm)
	if not missing.is_empty():
		_fail("%s: missing nodes %s" % [id, ", ".join(missing)])
	var bad: PackedStringArray = []
	for n: Node in inst.find_children("*", "", true, false):
		var s := String(n.name)
		if s.length() > 4 and s.substr(s.length() - 4).is_valid_int() and s[s.length() - 4] == "_":
			bad.append(s)
	if not bad.is_empty():
		_fail("%s: suffixed node names %s" % [id, ", ".join(bad)])
	var mats := {}
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			mats[m.resource_name if m != null else "<none>"] = true
	var keys := mats.keys()
	keys.sort()
	print("BB_SHOWCASE: %s nodes ok=%s materials=%s" % [id, missing.is_empty() and bad.is_empty(), keys])


func _aabb_of(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var a := (root.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


func _shot(shot_name: String, from: Vector3, target: Vector3) -> void:
	_cam.look_at_from_position(from, target, Vector3.UP)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var dir := ProjectSettings.globalize_path("res://qa/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("bb_" + shot_name + ".png")
	img.save_png(path)
	print("SHOT_SAVED: ", path)


func _build_stage() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.25, 0.48, 0.82)
	psm.sky_horizon_color = Color(0.78, 0.86, 0.93)
	psm.ground_bottom_color = Color(0.42, 0.40, 0.36)
	psm.ground_horizon_color = Color(0.78, 0.84, 0.88)
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46.0, -140.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	_ground = _plane(Color(0.62, 0.60, 0.55), 0.0, 1.0)
	_water = _plane(Color(0.10, 0.42, 0.55), 0.0, 0.72)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.near = 0.05
	add_child(_cam)
	_cam.make_current()


func _plane(col: Color, y: float, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80.0, 80.0)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.roughness = 0.35 if alpha < 1.0 else 0.9
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.position.y = y
	add_child(mi)
	return mi
