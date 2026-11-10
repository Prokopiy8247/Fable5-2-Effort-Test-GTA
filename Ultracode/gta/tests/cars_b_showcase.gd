extends Node3D
## QA showcase for the road vehicles of art set cars_b (author: art critic cars_b): suv, pickup, van,
## police_cruiser and taxi in one row on a small look-dev stage. Isolated scene, no world boot.
## suv / pickup / van are repainted the way the game repaints them (M_Paint_Primary / _Secondary
## overrides); the cruiser and the taxi keep their authored livery. Screenshots go to
## qa/screenshots/cars_b_*.png:
##   cars_b_group_front / _rear      all five, relative scale
##   cars_b_<id>_a / _b              front and rear three-quarter of every vehicle
##   cars_b_police_cruiser_side / cars_b_taxi_side     door livery close-up (geometry decals)
##   cars_b_far                      cruiser + taxi from 70 m through a long lens (decal z-fight check)
##   cars_b_van_open                 Door_RearL / Door_RearR swung open (the panes must travel along)
##   cars_b_pickup_open              Tailgate folded flat
##   cars_b_mods                     suv + pickup with every Mod_* part on
##   cars_b_lod                      Body_LOD1 + wheels only
## Helper meshes (Col_*, Body_LOD1, Mod_*) are hidden the way the game hides them.
##
## Run (windowed, about 10 s):
##   tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/cars_b_showcase.tscn -Frames 420
## The stage is test scaffolding built from primitives, never game content.

const MODEL_DIR := "res://gta/generated/models/vehicles/"
const IDS: Array[String] = ["suv", "pickup", "van", "police_cruiser", "taxi"]
## primary / secondary paint (sRGB hex from the art-direction palette); "" = keep the authored livery
const PAINT := {
	"suv": ["#2F9E5C", "#F1F1EE"],
	"pickup": ["#2C6FD9", "#F1F1EE"],
	"van": ["#F1F1EE", "#1B1D22"],
	"police_cruiser": ["", ""],
	"taxi": ["", ""],
}
const SPACING := 3.4

var _cam: Camera3D
var _fails: int = 0


func _ready() -> void:
	await _run()


func _run() -> void:
	_build_stage()
	var headless := DisplayServer.get_name() == "headless"
	var insts := {}
	var x := -SPACING * 2.0
	for id: String in IDS:
		var inst := _spawn(MODEL_DIR + id + ".glb", "show_" + id, Vector3(x, 0.0, 0.0))
		x += SPACING
		if inst == null:
			continue
		_set_mode(inst, "stock")
		if PAINT[id][0] != "":
			_paint(inst, PAINT[id][0], PAINT[id][1])
		insts[id] = inst
		print("CARS_B_SHOWCASE: %s meshes=%d" % [id, inst.find_children("*", "MeshInstance3D", true, false).size()])
	if insts.size() != IDS.size():
		_fail("only %d of %d vehicles loaded" % [insts.size(), IDS.size()])
	if not headless and not insts.is_empty():
		var c := Vector3(0.0, 0.8, 0.0)
		_cam.fov = 34.0
		await _shot("group_front", c + Vector3(9.5, 5.0, -17.0), c)
		await _shot("group_rear", c + Vector3(-10.0, 5.2, 17.0), c)
		for id: String in insts:
			_set_mode(insts[id], "mods")
		await _shot("mods", Vector3(-5.1, 0.8, 0.0) + Vector3(5.5, 3.2, -9.5), Vector3(-5.1, 0.8, 0.0))
		for id: String in insts:
			_set_mode(insts[id], "lod")
		await _shot("lod", c + Vector3(9.5, 5.0, -17.0), c)
		for id: String in insts:
			_set_mode(insts[id], "stock")
		# long lens from far away: geometry decals (letters, shield, checker band) must not flicker
		_cam.fov = 5.0
		var mid := Vector3(SPACING * 1.5, 0.75, 0.0)
		await _shot("far", mid + Vector3(52.0, 9.0, -46.0), mid)
		for id: String in insts:
			var inst := insts[id] as Node3D
			for other_id: String in insts:
				(insts[other_id] as Node3D).visible = other_id == id
			var p := inst.position + Vector3(0.0, 0.75, 0.0)
			_cam.fov = 34.0
			await _shot(id + "_a", p + Vector3(4.6, 2.1, -7.0), p)
			await _shot(id + "_b", p + Vector3(-4.9, 2.3, 7.0), p)
			if id == "police_cruiser" or id == "taxi":
				_cam.fov = 30.0
				await _shot(id + "_side", p + Vector3(5.2, 0.35, 0.3), p + Vector3(0.0, -0.05, 0.3))
			if id == "van":
				var dl := inst.find_child("Door_RearL", true, false) as Node3D
				var dr := inst.find_child("Door_RearR", true, false) as Node3D
				if dl == null or dr == null:
					_fail("van has no Door_RearL / Door_RearR")
				else:
					var rl := dl.transform
					var rr := dr.transform
					dl.transform = rl * Transform3D(Basis(Vector3.UP, -1.75), Vector3.ZERO)
					dr.transform = rr * Transform3D(Basis(Vector3.UP, 1.75), Vector3.ZERO)
					await _shot("van_open", p + Vector3(-3.6, 1.6, 7.4), p + Vector3(0.0, 0.2, 1.6))
					dl.transform = rl
					dr.transform = rr
			if id == "pickup":
				var tg := inst.find_child("Tailgate", true, false) as Node3D
				if tg == null:
					_fail("pickup has no Tailgate")
				else:
					var rest := tg.transform
					tg.transform = rest * Transform3D(Basis(Vector3.RIGHT, 1.5), Vector3.ZERO)
					await _shot("pickup_open", p + Vector3(-3.4, 2.6, 6.6), p + Vector3(0.0, 0.1, 1.6))
					tg.transform = rest
	print("TEST_RESULT: %s cars_b_showcase failures=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
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


## "stock": the vehicle as it spawns; "mods": every Mod_* part on; "lod": Body_LOD1 + wheels only.
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
	print("CHECK_FAIL: cars_b_showcase ", msg)


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
	var path := dir.path_join("cars_b_" + shot_name + ".png")
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
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(240.0, 240.0)
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
