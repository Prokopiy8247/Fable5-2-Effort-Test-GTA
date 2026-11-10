extends Node3D
## QA showcase for the service-vehicle GLBs (author: vehicle artist cars_service).
## Isolated scene, no world boot: puts ambulance, firetruck, swat_van and box_truck in one row on a
## small look-dev stage and saves screenshots to qa/screenshots/svc_*.png:
##   svc_group_front / svc_group_rear   all four, relative scale
##   svc_<id>_a / svc_<id>_b            front and rear three-quarter of every vehicle
##   svc_<id>_lod1                      Body_LOD1 + wheels only
## Helper meshes (Col_*, Body_LOD1) are hidden the way the game hides them.
##
## Run (windowed, ~6 s):
##   tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/svc_showcase.tscn -Frames 400
## The stage is test scaffolding built from primitives, never game content.

const MODEL_DIR := "res://gta/generated/models/vehicles/"
const IDS: Array[String] = ["ambulance", "firetruck", "swat_van", "box_truck"]
const SPACING := 4.6

var _cam: Camera3D
var _fails: int = 0


func _ready() -> void:
	await _run()


func _run() -> void:
	_build_stage()
	var headless := DisplayServer.get_name() == "headless"
	var insts: Array[Node3D] = []
	var x := -SPACING * 1.5
	for id: String in IDS:
		var path := MODEL_DIR + id + ".glb"
		if not ResourceLoader.exists(path):
			_fail("no file " + path)
			x += SPACING
			continue
		var ps := load(path) as PackedScene
		if ps == null:
			_fail("%s: not a PackedScene" % id)
			x += SPACING
			continue
		var inst := ps.instantiate() as Node3D
		inst.name = "show_" + id
		add_child(inst)
		inst.position = Vector3(x, 0.0, 0.0)
		x += SPACING
		_set_helpers(inst, false)
		insts.append(inst)
		print("SVC_SHOWCASE: %s meshes=%d" % [id, inst.find_children("*", "MeshInstance3D", true, false).size()])
	if not headless and not insts.is_empty():
		var c := Vector3(0.0, 1.4, 0.0)
		await _shot("group_front", c + Vector3(9.5, 5.0, -17.0), c)
		await _shot("group_rear", c + Vector3(-10.5, 5.5, 17.0), c)
		for inst: Node3D in insts:
			var id := String(inst.name).substr(5)
			for other: Node3D in insts:
				other.visible = other == inst
			var p := inst.position + Vector3(0.0, 1.35, 0.0)
			await _shot(id + "_a", p + Vector3(5.6, 3.0, -9.2), p)
			await _shot(id + "_b", p + Vector3(-6.0, 3.3, 9.0), p)
			_set_helpers(inst, true)
			await _shot(id + "_lod1", p + Vector3(5.6, 3.0, -9.2), p)
			_set_helpers(inst, false)
	print("TEST_RESULT: %s svc_showcase failures=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## lod=false: full model (helpers hidden); lod=true: only Body_LOD1 + wheels.
func _set_helpers(inst: Node3D, lod: bool) -> void:
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var nm := String(n.name)
		var mi := n as MeshInstance3D
		if nm.begins_with("Col_"):
			mi.visible = false
		elif nm == "Body_LOD1":
			mi.visible = lod
		elif nm.begins_with("Wheel"):
			mi.visible = true
		else:
			mi.visible = not lod


func _fail(msg: String) -> void:
	_fails += 1
	print("CHECK_FAIL: svc_showcase ", msg)


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
	var path := dir.path_join("svc_" + shot_name + ".png")
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
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120.0, 120.0)
	ground.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.38, 0.42)
	m.roughness = 0.92
	ground.material_override = m
	add_child(ground)
	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.near = 0.05
	add_child(_cam)
	_cam.make_current()
