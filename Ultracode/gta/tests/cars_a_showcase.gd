extends Node3D
## QA showcase for the road cars of art set cars_a + the kit reference sedan (author: art critic
## cars_a). Isolated scene, no world boot: sedan, compact, sports and muscle in one row on a small
## look-dev stage, each in another paint so the M_Paint_Primary / M_Paint_Secondary surfaces are
## exercised the way the game repaints them. Screenshots go to qa/screenshots/cars_a_*.png:
##   cars_a_group_front / _rear      all four, relative scale
##   cars_a_<id>_a / _b              front and rear three-quarter of every car
##   cars_a_<id>_eye                 driver-eye view (first-person camera check: headliner, dash)
##   cars_a_sports_roof              Roof_Convertible folded the way the vehicle code folds it
##   cars_a_mods                     every Mod_* part switched on (do they sit on the bodies?)
##   cars_a_lod                      Body_LOD1 + wheels only
##   cars_a_wheels                   the four shared wheel parts
## Helper meshes (Col_*, Body_LOD1, Mod_*) are hidden the way the game hides them.
##
## Run (windowed, about 10 s):
##   tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/cars_a_showcase.tscn -Frames 420
## The stage is test scaffolding built from primitives, never game content.

const MODEL_DIR := "res://gta/generated/models/vehicles/"
const IDS: Array[String] = ["sedan", "compact", "sports", "muscle"]
const WHEELS: Array[String] = ["wheel_sport", "wheel_classic", "wheel_offroad", "wheel_deep"]
## primary / secondary paint per car (sRGB hex from the art-direction palette)
const PAINT := {
	"sedan": ["#BFC5CC", "#1B1D22"],
	"compact": ["#F2C331", "#1B1D22"],
	"sports": ["#D8342C", "#F1F1EE"],
	"muscle": ["#2C6FD9", "#F1F1EE"],
}
const SPACING := 3.4
const ROOF_FOLD := 3.35

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
		var inst := _spawn(MODEL_DIR + id + ".glb", "show_" + id, Vector3(x, 0.0, 0.0))
		x += SPACING
		if inst == null:
			continue
		_set_mode(inst, "stock")
		_paint(inst, PAINT[id][0], PAINT[id][1])
		insts.append(inst)
		print("CARS_A_SHOWCASE: %s meshes=%d" % [id, inst.find_children("*", "MeshInstance3D", true, false).size()])
	if not headless and not insts.is_empty():
		var c := Vector3(0.0, 0.7, 0.0)
		_cam.fov = 34.0
		await _shot("group_front", c + Vector3(7.5, 4.2, -13.5), c)
		await _shot("group_rear", c + Vector3(-8.0, 4.4, 13.5), c)
		for inst: Node3D in insts:
			_set_mode(inst, "mods")
		await _shot("mods", c + Vector3(7.5, 4.2, -13.5), c)
		await _shot("mods_rear", c + Vector3(-8.0, 4.4, 13.5), c)
		for inst: Node3D in insts:
			_set_mode(inst, "lod")
		await _shot("lod", c + Vector3(7.5, 4.2, -13.5), c)
		for inst: Node3D in insts:
			_set_mode(inst, "stock")
		for inst: Node3D in insts:
			var id := String(inst.name).substr(5)
			for other: Node3D in insts:
				other.visible = other == inst
			var p := inst.position + Vector3(0.0, 0.65, 0.0)
			_cam.fov = 34.0
			await _shot(id + "_a", p + Vector3(4.3, 2.0, -6.6), p)
			await _shot(id + "_b", p + Vector3(-4.6, 2.2, 6.6), p)
			var seat := inst.find_child("Seat_Driver", true, false) as Node3D
			if seat != null:
				_cam.fov = 78.0
				var eye := seat.global_position + Vector3(0.0, 0.70, 0.06)
				await _shot(id + "_eye", eye, eye + Vector3(0.12, -0.16, -1.0))
			var roof := inst.find_child("Roof_Convertible", true, false) as Node3D
			if roof != null:
				var rest := roof.transform
				roof.transform = rest * Transform3D(Basis(Vector3.RIGHT, ROOF_FOLD), Vector3.ZERO)
				_cam.fov = 34.0
				await _shot(id + "_roof", p + Vector3(-4.6, 2.6, 6.2), p)
				await _shot(id + "_roof_front", p + Vector3(4.3, 2.4, -6.6), p)
				roof.transform = rest
		for inst: Node3D in insts:
			inst.visible = false
		var wx := -0.75
		for id: String in WHEELS:
			var w := _spawn(MODEL_DIR + "parts/" + id + ".glb", "show_" + id, Vector3(wx, 0.34, 0.0))
			wx += 0.5
			if w != null:
				w.rotation.y = deg_to_rad(-60.0)
		_cam.fov = 30.0
		await _shot("wheels", Vector3(0.0, 0.75, -2.9), Vector3(0.0, 0.34, 0.0))
	print("TEST_RESULT: %s cars_a_showcase failures=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _spawn(path: String, node_name: String, pos: Vector3) -> Node3D:
	if not ResourceLoader.exists(path):
		_fail("no file " + path)
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		_fail("not a PackedScene: " + path)
		return null
	var inst := ps.instantiate() as Node3D
	inst.name = node_name
	add_child(inst)
	inst.position = pos
	return inst


## "stock": the car as it spawns; "mods": every Mod_* part on; "lod": Body_LOD1 + wheels only.
func _set_mode(inst: Node3D, mode: String) -> void:
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var nm := String(n.name)
		var mi := n as MeshInstance3D
		if nm.begins_with("Col_"):
			mi.visible = false
		elif nm == "Body_LOD1":
			mi.visible = mode == "lod"
		elif nm.begins_with("Wheel"):
			mi.visible = true
		elif nm.begins_with("Mod_"):
			mi.visible = mode == "mods"
		else:
			mi.visible = mode != "lod"


## Repaint the way the game does: override every M_Paint_Primary / M_Paint_Secondary surface.
func _paint(inst: Node3D, primary_hex: String, secondary_hex: String) -> void:
	var cache := {}
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			var hex := ""
			if mat.resource_name == "M_Paint_Primary":
				hex = primary_hex
			elif mat.resource_name == "M_Paint_Secondary":
				hex = secondary_hex
			if hex == "":
				continue
			if not cache.has(hex):
				var dup := mat.duplicate() as BaseMaterial3D
				dup.albedo_color = Color(hex)
				cache[hex] = dup
			mi.set_surface_override_material(s, cache[hex])


func _fail(msg: String) -> void:
	_fails += 1
	print("CHECK_FAIL: cars_a_showcase ", msg)


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
	var path := dir.path_join("cars_a_" + shot_name + ".png")
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
	_cam.near = 0.03
	add_child(_cam)
	_cam.make_current()
