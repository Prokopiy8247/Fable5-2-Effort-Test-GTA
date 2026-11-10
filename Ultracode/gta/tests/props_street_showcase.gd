extends Node3D
## QA showcase for the street-furniture GLBs (author: street-furniture artist).
## Isolated look-dev scene, no world boot: reads manifest_street.json, lays every prop of a
## category out on a neutral floor and saves one screenshot per category to
## qa/screenshots/props_street_<category>.png, plus one dusk shot of everything that glows.
## Purpose: judge the in-engine look (flat shading, back-face culling, palette materials, glass
## alpha, emissives, relative scale). In --headless it only checks that every GLB instantiates.
##
## Run (windowed, a few seconds):
##   tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/props_street_showcase.tscn -Frames 300
## The stage (floor, light, sky) is test scaffolding built from primitives, never game content.

const DIR := "res://gta/generated/models/props/"
const ORDER: Array[String] = ["signal", "lamp", "sign", "barrier", "road", "furniture", "utility", "fence",
	"container", "signage"]
const GLOWING: Array[String] = ["street_lamp_a", "street_lamp_b", "wall_lamp", "bollard_light", "neon_sign_a",
	"neon_sign_b", "neon_sign_c", "billboard_roof", "vending_machine", "atm", "bus_stop", "phone_kiosk",
	"roadblock_police"]
const GAP := 0.6

var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _items: Array[Node3D] = []
var _bounds: AABB = AABB()
var _has_bounds: bool = false
var _fails: int = 0
var _shots: int = 0
var _spawned: int = 0


func _ready() -> void:
	await _run()


func _run() -> void:
	_build_stage()
	var headless := DisplayServer.get_name() == "headless"
	var props := _load_manifest()
	var groups := {}
	var by_id := {}
	for e_v: Variant in props:
		var e: Dictionary = e_v
		var cat := String(e.get("category", "misc"))
		if not groups.has(cat):
			groups[cat] = []
		(groups[cat] as Array).append(e)
		by_id[String(e.get("id", ""))] = e
	for cat: String in ORDER:
		if not groups.has(cat):
			continue
		_layout(groups[cat] as Array)
		if not headless:
			await _shot(cat)
		_clear()
		await get_tree().process_frame
	# dusk: everything with an emissive material
	var glow: Array = []
	for id: String in GLOWING:
		if by_id.has(id):
			glow.append(by_id[id])
	_sun.light_energy = 0.06
	_env.ambient_light_energy = 0.22
	_env.glow_enabled = true
	_env.glow_intensity = 0.9
	_layout(glow)
	if not headless:
		await _shot("dusk_emissive")
	_clear()
	print("TEST_RESULT: %s props_street_showcase spawned=%d shots=%d failures=%d" % [
		"PASS" if _fails == 0 else "FAIL", _spawned, _shots, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _load_manifest() -> Array:
	var f := FileAccess.open(DIR + "manifest_street.json", FileAccess.READ)
	if f == null:
		_fails += 1
		print("CHECK_FAIL: props_street_showcase cannot open manifest_street.json")
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		_fails += 1
		print("CHECK_FAIL: props_street_showcase manifest is not a dictionary")
		return []
	return (data as Dictionary).get("props", []) as Array


func _vec(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _layout(entries: Array) -> void:
	var list := entries.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float((a["size"] as Array)[1]) > float((b["size"] as Array)[1]))
	var total_w := 0.0
	for e_v: Variant in list:
		total_w += float(((e_v as Dictionary)["size"] as Array)[0]) + GAP
	var row_w := maxf(sqrt(total_w) * 2.6, 6.0)
	var x := 0.0
	var z := 0.0
	var row_depth := 0.0
	_has_bounds = false
	for e_v: Variant in list:
		var e: Dictionary = e_v
		var sz := _vec(e["size"])
		var c := _vec(e["center"])
		if x > 0.0 and x + sz.x > row_w:
			x = 0.0
			z -= row_depth + GAP
			row_depth = 0.0
		var inst := _spawn(String(e["id"]))
		if inst == null:
			continue
		var lift := 0.0
		if String(e.get("anchor", "ground")) == "wall":
			lift = sz.y * 0.5 - c.y + 0.4
		inst.position = Vector3(x + sz.x * 0.5 - c.x, lift, z - sz.z * 0.5 - c.z)
		var box := AABB(inst.position + c - sz * 0.5, sz)
		_bounds = box if not _has_bounds else _bounds.merge(box)
		_has_bounds = true
		x += sz.x + GAP
		row_depth = maxf(row_depth, sz.z)


func _spawn(id: String) -> Node3D:
	var path := DIR + id + ".glb"
	if not ResourceLoader.exists(path):
		_fails += 1
		print("CHECK_FAIL: props_street_showcase missing ", path)
		return null
	var ps := load(path) as PackedScene
	var inst: Node3D = null
	if ps != null:
		inst = ps.instantiate() as Node3D
	if inst == null:
		_fails += 1
		print("CHECK_FAIL: props_street_showcase cannot instantiate ", path)
		return null
	add_child(inst)
	_items.append(inst)
	_spawned += 1
	return inst


func _clear() -> void:
	for it in _items:
		it.queue_free()
	_items.clear()


func _shot(shot_name: String) -> void:
	if not _has_bounds:
		return
	var c := _bounds.get_center()
	var r := _bounds.size.length() * 0.5
	_cam.fov = 30.0
	var dist := r / sin(deg_to_rad(15.0)) * 0.80
	# props face -Z, so the camera stands on the -Z side
	_cam.look_at_from_position(c + Vector3(-0.50, 0.42, -1.0).normalized() * dist, c, Vector3.UP)
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var dir := ProjectSettings.globalize_path("res://qa/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("props_street_" + shot_name + ".png")
	img.save_png(path)
	_shots += 1
	print("SHOT_SAVED: ", path)


func _build_stage() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.25, 0.48, 0.82)
	psm.sky_horizon_color = Color(0.78, 0.86, 0.93)
	psm.ground_bottom_color = Color(0.42, 0.40, 0.36)
	psm.ground_horizon_color = Color(0.78, 0.84, 0.88)
	sky.sky_material = psm
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.9
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.ssao_enabled = true
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.light_energy = 1.25
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 60.0
	add_child(_sun)
	_sun.look_at_from_position(Vector3(-6.0, 9.0, -7.0), Vector3.ZERO, Vector3.UP)
	var floor_mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(160.0, 0.05, 160.0)
	floor_mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.60, 0.55)
	m.roughness = 0.9
	floor_mi.material_override = m
	floor_mi.position = Vector3(0.0, -0.025, 0.0)
	add_child(floor_mi)
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 300.0
	add_child(_cam)
	_cam.make_current()
