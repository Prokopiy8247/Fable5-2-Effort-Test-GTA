extends Node3D
## QA showcase for the weapon / projectile / pickup GLBs (author: weapon artist).
## Isolated look-dev scene, no world boot: racks the models in front of a neutral wall (or puts
## the pickups on a floor) and saves screenshots to qa/screenshots/wpnart_<name>.png, so the
## in-engine look (flat shading, back-face culling, palette materials, relative scale) can be
## judged. Attachments are hidden like in the game, except in the *_att shots.
##
## Run (windowed, a few seconds):
##   tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/wpnart_showcase.tscn -Frames 300
## The stage (wall, floor, light) is test scaffolding built from primitives, never game content.

const WDIR := "res://gta/generated/models/weapons/"
const PDIR := "res://gta/generated/models/props/pickups/"
const LONG_A: Array[String] = ["smg", "carbine", "assault_rifle", "pump_shotgun", "auto_shotgun", "marksman_rifle"]
const LONG_B: Array[String] = ["sniper_rifle", "grenade_launcher", "rocket_launcher", "bat", "crowbar", "rocket"]
const SMALL: Array[String] = ["pistol", "heavy_pistol", "knife", "grenade", "molotov", "grenade_round"]
const ATT: Array[String] = ["pistol", "smg", "carbine", "assault_rifle", "auto_shotgun", "sniper_rifle"]
const PICKUPS: Array[String] = ["ammo_box", "medkit", "armor_vest", "cash_stack", "cash_bag", "parachute_pack",
	"scuba_tank", "weapon_crate"]

var _cam: Camera3D
var _wall: MeshInstance3D
var _floor: MeshInstance3D
var _items: Array[Node3D] = []
var _fails: int = 0
var _shots: int = 0


func _ready() -> void:
	await _run()


func _run() -> void:
	_build_stage()
	var headless := DisplayServer.get_name() == "headless"
	var plans := [
		["long_a", LONG_A, WDIR, 3, 0.36, 1.50, false],
		["long_b", LONG_B, WDIR, 3, 0.36, 1.50, false],
		["small", SMALL, WDIR, 3, 0.34, 0.50, false],
		["att_a", ATT.slice(0, 3), WDIR, 3, 0.42, 1.5, true],
		["att_b", ATT.slice(3, 6), WDIR, 3, 0.46, 1.5, true],
	]
	for p: Array in plans:
		_wall.visible = true
		_floor.visible = false
		_rack(p[1], p[2], p[3], p[4], p[5], p[6])
		if not headless:
			await _shot_rack(p[0])
		_clear()
		await get_tree().process_frame
	# pickups on the floor, seen from the front-right
	_wall.visible = false
	_floor.visible = true
	for i in PICKUPS.size():
		var inst := _spawn(PDIR, PICKUPS[i])
		if inst == null:
			continue
		inst.position = Vector3((float(i % 4) - 1.5) * 0.72, 0.0, float(i / 4) * 0.85)
	if not headless:
		await _shot_persp("pickups", Vector3(1.9, 1.35, -2.9), Vector3(0.05, 0.16, 0.45), 30.0)
		await _shot_persp("pickups_back", Vector3(-1.7, 1.2, 3.6), Vector3(0.0, 0.16, 0.35), 30.0)
	_clear()
	print("TEST_RESULT: %s wpnart_showcase shots=%d failures=%d" % ["PASS" if _fails == 0 else "FAIL", _shots, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _spawn(dir: String, id: String) -> Node3D:
	var path := dir + id + ".glb"
	if not ResourceLoader.exists(path):
		_fails += 1
		print("CHECK_FAIL: wpnart_showcase missing ", path)
		return null
	var ps := load(path) as PackedScene
	var inst: Node3D = null
	if ps != null:
		inst = ps.instantiate() as Node3D
	if inst == null:
		_fails += 1
		print("CHECK_FAIL: wpnart_showcase cannot instantiate ", path)
		return null
	add_child(inst)
	_items.append(inst)
	return inst


func _rack(ids: Array, dir: String, rows: int, row_gap: float, col_gap: float, with_atts: bool) -> void:
	for i in ids.size():
		var inst := _spawn(dir, String(ids[i]))
		if inst == null:
			continue
		var col := i / rows
		var row := i % rows
		inst.position = Vector3(0.0, 2.0 - float(row) * row_gap, 0.2 - float(col) * col_gap)
		var has_ext := inst.find_child("Att_ExtMag", true, false) != null
		for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
			var nm := String(n.name)
			if nm.begins_with("Att_"):
				(n as Node3D).visible = with_atts
			elif nm == "Mag" and with_atts and has_ext:
				(n as Node3D).visible = false


func _clear() -> void:
	for it in _items:
		it.queue_free()
	_items.clear()


func _bounds() -> AABB:
	var out := AABB()
	var first := true
	for it in _items:
		for n: Node in it.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if not mi.visible or mi.mesh == null:
				continue
			var a := mi.global_transform * mi.get_aabb()
			out = a if first else out.merge(a)
			first = false
	return out


func _shot_rack(shot_name: String) -> void:
	var b := _bounds()
	var c := b.get_center()
	_wall.position = Vector3(b.position.x - 0.06, c.y, c.z)
	var aspect := 16.0 / 9.0
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = maxf(b.size.y * 1.14, b.size.z * 1.10 / aspect)
	_cam.look_at_from_position(c + Vector3(6.0, 0.9, 1.3), c, Vector3.UP)
	await _save(shot_name)


func _shot_persp(shot_name: String, from: Vector3, target: Vector3, fov: float) -> void:
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = fov
	_cam.look_at_from_position(from, target, Vector3.UP)
	await _save(shot_name)


func _save(shot_name: String) -> void:
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var dir := ProjectSettings.globalize_path("res://qa/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("wpnart_" + shot_name + ".png")
	img.save_png(path)
	_shots += 1
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
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	sun.look_at_from_position(Vector3(6.0, 7.0, 3.0), Vector3.ZERO, Vector3.UP)
	_wall = _slab(Vector3(0.05, 12.0, 12.0), Color(0.80, 0.77, 0.70))
	_floor = _slab(Vector3(30.0, 0.05, 30.0), Color(0.62, 0.60, 0.55))
	_floor.position = Vector3(0.0, -0.025, 0.0)
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 100.0
	add_child(_cam)
	_cam.make_current()


func _slab(size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	mi.material_override = m
	add_child(mi)
	return mi
