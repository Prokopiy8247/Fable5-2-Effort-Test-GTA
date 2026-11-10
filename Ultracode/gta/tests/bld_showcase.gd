extends Node3D
## QA showcase for the generic building GLBs (author: building-kit artist, docs/BUILDING_KIT.md).
## Isolated look-dev scene, no world boot: reads manifest_generic.json, lines the buildings up like
## street fronts (front facades toward the camera) and saves screenshots to qa/screenshots/:
##   bld_downtown.png  bld_residential.png  bld_industrial.png   three-quarter ensemble shots
##   bld_street.png    eye-level view along a row of shop fronts
##   bld_dusk.png      the same street at dusk with glow on (neon signage, emissive check)
##   bld_rear.png      service sides (rear + side walls) of five buildings, sun moved behind them
##   bld_crown.png     office_d roof crown from above      bld_terrace.png  house_d roof terrace
##   bld_parking.png   parking_a close three-quarter view
## Purpose: judge the in-engine look (flat shading, back-face culling, palette materials, neon).
## In --headless it only checks that every GLB of the manifest instantiates.
##
## Run (windowed, a few seconds):
##   tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/bld_showcase.tscn -Frames 300
## The stage (floor, light, sky) is test scaffolding built from primitives, never game content.

const DIR := "res://gta/generated/models/buildings/"
const SETS := {
	"downtown": [["office_f", "office_e", "office_d", "office_c", "office_b", "office_a"],
		["parking_a", "storefront_c", "storefront_d", "storefront_a", "kiosk_a"]],
	"residential": [["apartment_d", "apartment_c", "apartment_b", "apartment_a", "storefront_f"],
		["house_a", "house_b", "house_c", "house_d", "house_e", "house_f", "storefront_b", "storefront_e", "shed_a"]],
	"industrial": [["warehouse_d", "warehouse_b"], ["warehouse_a", "warehouse_c", "garage_row", "shed_a"]],
}
const STREET: Array[String] = ["storefront_e", "storefront_b", "storefront_a", "storefront_f", "storefront_d", "office_e"]
const GAP := 6.0

var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _items: Array[Node3D] = []
var _bounds: AABB = AABB()
var _has_bounds: bool = false
var _by_id: Dictionary = {}
var _fails: int = 0
var _shots: int = 0
var _spawned: int = 0


func _ready() -> void:
	await _run()


func _run() -> void:
	_build_stage()
	var headless := DisplayServer.get_name() == "headless"
	for e_v: Variant in _load_manifest():
		var e: Dictionary = e_v
		_by_id[String(e.get("id", ""))] = e
	if headless:
		for id: String in _by_id.keys():
			_spawn(id)
		_clear()
	else:
		for set_name: String in SETS.keys():
			_layout_rows(SETS[set_name] as Array)
			await _shot_ensemble(set_name)
			_clear()
			await get_tree().process_frame
		await _critic_shots()
		var x_end := _layout_row(STREET, 0.0, 0.0, 0.4)
		_cam.fov = 62.0
		_cam.look_at_from_position(Vector3(-7.0, 1.7, -15.0), Vector3(x_end * 0.42, 5.5, 0.0), Vector3.UP)
		await _save("street")
		_sun.light_energy = 0.05
		_sun.light_color = Color(0.55, 0.62, 0.9)
		_env.ambient_light_energy = 0.28
		_env.glow_enabled = true
		_env.glow_intensity = 0.9
		_env.glow_bloom = 0.1
		await _save("dusk")
		_clear()
	print("TEST_RESULT: %s bld_showcase manifest=%d spawned=%d shots=%d failures=%d" % [
		"PASS" if _fails == 0 else "FAIL", _by_id.size(), _spawned, _shots, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _load_manifest() -> Array:
	var f := FileAccess.open(DIR + "manifest_generic.json", FileAccess.READ)
	if f == null:
		_fails += 1
		print("CHECK_FAIL: bld_showcase cannot open manifest_generic.json")
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		_fails += 1
		print("CHECK_FAIL: bld_showcase manifest is not a dictionary")
		return []
	return (data as Dictionary).get("buildings", []) as Array


## Rows from back (index 0) to front; every row is centred on x = 0, fronts face -Z.
func _layout_rows(rows: Array) -> void:
	_has_bounds = false
	var z := 0.0
	for r in range(rows.size() - 1, -1, -1):
		var ids: Array = rows[r]
		var width := 0.0
		var depth := 0.0
		for id: String in ids:
			if _by_id.has(id):
				var fp: Array = (_by_id[id] as Dictionary)["footprint"]
				width += float(fp[0]) + GAP
				depth = maxf(depth, float(fp[1]))
		var typed: Array[String] = []
		typed.assign(ids)
		_layout_row(typed, -width * 0.5, z, GAP)
		z += depth + 14.0


## Places the buildings side by side from x0, with their front edge on the line z = z_front.
func _layout_row(ids: Array[String], x0: float, z_front: float, gap: float) -> float:
	var x := x0
	for id: String in ids:
		if not _by_id.has(id):
			continue
		var e: Dictionary = _by_id[id]
		var fp: Array = e["footprint"]
		var w := float(fp[0])
		var d := float(fp[1])
		var inst := _spawn(id)
		if inst == null:
			continue
		inst.position = Vector3(x + w * 0.5, 0.0, z_front + d * 0.5)
		var box := AABB(Vector3(x, 0.0, z_front), Vector3(w, float(e["height"]), d))
		_bounds = box if not _has_bounds else _bounds.merge(box)
		_has_bounds = true
		x += w + gap
	return x


func _spawn(id: String) -> Node3D:
	var path := DIR + id + ".glb"
	if not ResourceLoader.exists(path):
		_fails += 1
		print("CHECK_FAIL: bld_showcase missing ", path)
		return null
	var ps := load(path) as PackedScene
	var inst: Node3D = null
	if ps != null:
		inst = ps.instantiate() as Node3D
	if inst == null:
		_fails += 1
		print("CHECK_FAIL: bld_showcase cannot instantiate ", path)
		return null
	add_child(inst)
	_items.append(inst)
	_spawned += 1
	return inst


func _clear() -> void:
	for it in _items:
		it.queue_free()
	_items.clear()
	_has_bounds = false


## Close views added by the art critic: service sides, roofs and the car park.
func _critic_shots() -> void:
	var rear: Array[String] = ["warehouse_d", "storefront_d", "storefront_f", "storefront_a", "garage_row"]
	_has_bounds = false
	_layout_row(rear, 0.0, 0.0, GAP)
	if _has_bounds:
		var c := _bounds.get_center()
		var r := _bounds.size.length() * 0.5
		_cam.fov = 32.0
		_sun.look_at_from_position(Vector3(8.0, 9.0, 7.0), Vector3.ZERO, Vector3.UP)
		_cam.look_at_from_position(c + Vector3(0.5, 0.4, 1.0).normalized() * (r / sin(deg_to_rad(16.0)) * 0.7), c, Vector3.UP)
		await _save("rear")
		_sun.look_at_from_position(Vector3(-7.0, 9.0, -8.0), Vector3.ZERO, Vector3.UP)
	_clear()
	await get_tree().process_frame
	# [id, shot name, camera position, look-at target] - the building's footprint starts at the origin
	var singles := [
		["office_d", "crown", Vector3(-16.0, 80.0, -24.0), Vector3(10.0, 53.0, 10.0)],
		["house_d", "terrace", Vector3(19.0, 11.5, -9.0), Vector3(6.5, 3.2, 5.0)],
		["parking_a", "parking", Vector3(-16.0, 21.0, -24.0), Vector3(16.0, 2.5, 14.0)],
	]
	for sv: Variant in singles:
		var one: Array[String] = [String(sv[0])]
		_layout_row(one, 0.0, 0.0, 0.0)
		_cam.fov = 42.0
		_cam.look_at_from_position(sv[2], sv[3], Vector3.UP)
		await _save(String(sv[1]))
		_clear()
		await get_tree().process_frame


func _shot_ensemble(shot_name: String) -> void:
	if not _has_bounds:
		return
	var c := _bounds.get_center()
	var r := _bounds.size.length() * 0.5
	_cam.fov = 32.0
	var dist := r / sin(deg_to_rad(16.0)) * 0.78
	# buildings face -Z, so the camera stands on the -Z side
	_cam.look_at_from_position(c + Vector3(-0.55, 0.38, -1.0).normalized() * dist, c, Vector3.UP)
	await _save(shot_name)


func _save(shot_name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var dir := ProjectSettings.globalize_path("res://qa/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("bld_" + shot_name + ".png")
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
	_sun.directional_shadow_max_distance = 400.0
	add_child(_sun)
	_sun.look_at_from_position(Vector3(-7.0, 9.0, -8.0), Vector3.ZERO, Vector3.UP)
	var floor_mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(900.0, 0.05, 900.0)
	floor_mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.56, 0.55, 0.52)
	m.roughness = 0.9
	floor_mi.material_override = m
	floor_mi.position = Vector3(0.0, -0.025, 0.0)
	add_child(floor_mi)
	_cam = Camera3D.new()
	_cam.near = 0.1
	_cam.far = 1500.0
	add_child(_cam)
	_cam.make_current()
