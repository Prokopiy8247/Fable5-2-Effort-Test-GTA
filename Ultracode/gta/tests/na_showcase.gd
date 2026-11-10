extends Node3D
## QA contract test + look-dev showcase for the nature and wildlife GLBs
## (author: nature and wildlife artist; assets built by tools/blender/assets/nature_animals.py).
##
## Always (also in --headless): reads manifest_nature.json / manifest_animals.json and checks that
##   * every listed GLB (incl. the tree LOD1 files) instantiates,
##   * nature assets have one MeshInstance3D child called "Mesh" whose AABB matches the manifest,
##   * animals have every part node from the manifest ("Body", "Head", "Leg_FL" ...) with its
##     origin at the manifest pivot, stand on y = 0 (fish: centred) and face -Z.
## Windowed: additionally saves qa/screenshots/na_<group>.png for every asset group, plus one shot
## of the animals in procedurally posed states (walk cycle frame, grazing, folded / flapping wings,
## tail swish) to prove that the rigid-part joints work in the engine.
##
## Run:
##   tools\godot.ps1 -Mode headless -Scene res://gta/tests/scenes/na_showcase.tscn -Frames 300
##   tools\godot.ps1 -Mode window   -Scene res://gta/tests/scenes/na_showcase.tscn -Frames 400
## The stage (floor, light, sky) is test scaffolding built from primitives, never game content.

const NAT_DIR := "res://gta/generated/models/nature/"
const ANI_DIR := "res://gta/generated/models/animals/"

var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _floor_mat: StandardMaterial3D
var _items: Array[Node3D] = []
var _bounds: AABB = AABB()
var _has_bounds: bool = false
var _fails: int = 0
var _checks: int = 0
var _shots: int = 0


func _ready() -> void:
	await _run()


func _run() -> void:
	_build_stage()
	var headless := DisplayServer.get_name() == "headless"
	var nature := _load_manifest(NAT_DIR + "manifest_nature.json", "nature")
	var animals := _load_manifest(ANI_DIR + "manifest_animals.json", "animals")
	_check_nature(nature)
	_check_animals(animals)
	if not headless:
		var by_cat := {}
		for e_v: Variant in nature:
			var e: Dictionary = e_v
			var cat := String(e.get("category", "misc"))
			if not by_cat.has(cat):
				by_cat[cat] = []
			(by_cat[cat] as Array).append(e)
		# trees, then their LOD1 twins
		_layout(by_cat.get("tree", []) as Array, NAT_DIR, "file", 1.5, 60.0)
		await _shot("trees", Vector3(-0.45, 0.22, -1.0), 0.62)
		_clear()
		_layout(by_cat.get("tree", []) as Array, NAT_DIR, "lod1", 1.5, 60.0)
		await _shot("trees_lod1", Vector3(-0.45, 0.22, -1.0), 0.62)
		_clear()
		var small: Array = []
		small.append_array(by_cat.get("shrub", []) as Array)
		small.append_array(by_cat.get("groundcover", []) as Array)
		_layout(small, NAT_DIR, "file", 0.5, 9.0)
		await _shot("shrubs_groundcover", Vector3(-0.5, 0.45, -1.0), 0.70)
		_clear()
		var rocks: Array = []
		rocks.append_array(by_cat.get("cliff", []) as Array)
		rocks.append_array(by_cat.get("rock", []) as Array)
		rocks.append_array(by_cat.get("log", []) as Array)
		_layout(rocks, NAT_DIR, "file", 1.0, 22.0)
		await _shot("rocks_cliffs", Vector3(-0.5, 0.40, -1.0), 0.70)
		_clear()
		_floor_mat.albedo_color = Color(0.80, 0.74, 0.56)
		_layout(by_cat.get("underwater", []) as Array, NAT_DIR, "file", 0.5, 7.0)
		await _shot("underwater", Vector3(-0.5, 0.45, -1.0), 0.72)
		_clear()
		_floor_mat.albedo_color = Color(0.55, 0.66, 0.42)
		_layout(animals, ANI_DIR, "file", 0.7, 9.0)
		await _shot("animals", Vector3(-0.62, 0.36, -1.0), 0.66)
		_pose_animals()
		await _shot("animals_posed", Vector3(-0.62, 0.36, -1.0), 0.66)
		_clear()
	print("TEST_RESULT: %s na_showcase checks=%d shots=%d failures=%d" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _shots, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


# ---------------------------------------------------------------------------------------------
# contract checks
# ---------------------------------------------------------------------------------------------
func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if not ok:
		_fails += 1
		print("CHECK_FAIL: na_showcase ", what)
	return ok


func _load_manifest(path: String, key: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if not _check(f != null, "open " + path):
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not _check(typeof(data) == TYPE_DICTIONARY, "manifest is a dictionary: " + path):
		return []
	return (data as Dictionary).get(key, []) as Array


func _vec(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _instance(path: String) -> Node3D:
	if not _check(ResourceLoader.exists(path), "exists " + path):
		return null
	var ps := load(path) as PackedScene
	var inst: Node3D = null
	if ps != null:
		inst = ps.instantiate() as Node3D
	_check(inst != null, "instantiates " + path)
	return inst


func _merged_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != root:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var box := xf * mi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _check_nature(list: Array) -> void:
	_check(list.size() >= 36, "nature manifest lists >= 36 assets (has %d)" % list.size())
	for e_v: Variant in list:
		var e: Dictionary = e_v
		var id := String(e["id"])
		for key: String in ["file", "lod1"]:
			if not e.has(key):
				continue
			var inst := _instance(NAT_DIR + String(e[key]))
			if inst == null:
				continue
			var mesh := inst.find_child("Mesh", true, false) as MeshInstance3D
			if _check(mesh != null and mesh.mesh != null, "%s: MeshInstance3D 'Mesh'" % String(e[key])):
				_check(inst.find_children("*", "MeshInstance3D", true, false).size() == 1, "%s: exactly one mesh" % String(e[key]))
				_check(mesh.position.length() < 0.001, "%s: mesh at the asset origin" % String(e[key]))
				if key == "file":
					var box := mesh.get_aabb()
					_check((box.size - _vec(e["size"])).length() < 0.03, "%s: AABB size matches manifest" % id)
					_check(absf(-box.position.y - float(e["sink"])) < 0.02, "%s: sink matches manifest" % id)
					_check(absf(box.end.y - float(e["height"])) < 0.02, "%s: height matches manifest" % id)
					for i in mesh.mesh.get_surface_count():
						var m := mesh.mesh.surface_get_material(i)
						_check(m != null and m.resource_name.begins_with("P_"), "%s: surface %d uses a palette material" % [id, i])
			inst.free()


func _check_animals(list: Array) -> void:
	_check(list.size() >= 11, "animal manifest lists >= 11 animals (has %d)" % list.size())
	for e_v: Variant in list:
		var e: Dictionary = e_v
		var id := String(e["id"])
		var inst := _instance(ANI_DIR + String(e["file"]))
		if inst == null:
			continue
		var pivots: Dictionary = e["pivots"]
		for part_v: Variant in e["parts"] as Array:
			var part := String(part_v)
			var n := inst.find_child(part, true, false) as MeshInstance3D
			if _check(n != null and n.mesh != null, "%s: part node '%s'" % [id, part]):
				_check(n.position.distance_to(_vec(pivots[part])) < 0.002, "%s: %s origin at the manifest pivot" % [id, part])
		var box := _merged_aabb(inst)
		_check((box.size - _vec(e["size"])).length() < 0.03, "%s: AABB size matches manifest" % id)
		var kind := String(e["kind"])
		if kind == "fish":
			_check(box.get_center().length() < 0.03, "%s: centred on the origin" % id)
		else:
			_check(absf(box.position.y) < 0.03, "%s: feet on y = 0 (min y %.3f)" % [id, box.position.y])
		var head := inst.find_child("Head", true, false) as Node3D
		var tail := inst.find_child("Tail", true, false) as Node3D
		if head != null and tail != null:
			_check(head.position.z < tail.position.z, "%s: faces -Z (head in front of tail)" % id)
		elif tail != null:
			_check(tail.position.z > 0.0, "%s: faces -Z (tail behind the origin)" % id)
		for side: String in ["Leg_F", "Leg_R", "Wing_", "Fin_"]:
			var l := inst.find_child(side + "L", true, false) as Node3D
			var r := inst.find_child(side + "R", true, false) as Node3D
			if l != null and r != null:
				_check(l.position.x < 0.0 and r.position.x > 0.0, "%s: %sL on -X, %sR on +X" % [id, side, side])
		inst.free()


# ---------------------------------------------------------------------------------------------
# showcase
# ---------------------------------------------------------------------------------------------
func _layout(entries: Array, dir: String, file_key: String, gap: float, row_w: float) -> void:
	var list := entries.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float((a["size"] as Array)[1]) > float((b["size"] as Array)[1]))
	var x := 0.0
	var z := 0.0
	var row_depth := 0.0
	_has_bounds = false
	for e_v: Variant in list:
		var e: Dictionary = e_v
		if not e.has(file_key):
			continue
		var sz := _vec(e["size"])
		if x > 0.0 and x + sz.x > row_w:
			x = 0.0
			z += row_depth + gap      # camera stands on the -Z side: later rows go behind
			row_depth = 0.0
		var inst := _instance(dir + String(e[file_key]))
		if inst == null:
			continue
		add_child(inst)
		_items.append(inst)
		inst.set_meta("entry", e)
		var lift := 0.0
		if String(e.get("kind", "")) == "fish":
			lift = sz.y * 0.5 + 0.35
		inst.position = Vector3(x + sz.x * 0.5, lift, z + sz.z * 0.5)
		var box := AABB(Vector3(x, 0.0, z), Vector3(sz.x, sz.y + lift, sz.z))
		_bounds = box if not _has_bounds else _bounds.merge(box)
		_has_bounds = true
		x += sz.x + gap
		row_depth = maxf(row_depth, sz.z)


func _clear() -> void:
	for it in _items:
		it.queue_free()
	_items.clear()


func _part(inst: Node3D, part: String) -> Node3D:
	return inst.find_child(part, true, false) as Node3D


func _rot(inst: Node3D, part: String, deg: Vector3) -> void:
	var n := _part(inst, part)
	if n != null:
		n.rotation_degrees = deg


## Applies the same kind of transforms the in-game procedural animator uses, so the screenshot
## shows that the joints (part origins) are in the right places.
func _pose_animals() -> void:
	for inst in _items:
		var e: Dictionary = inst.get_meta("entry")
		var id := String(e["id"])
		var kind := String(e["kind"])
		if kind == "land":
			# one frame of a walk cycle: diagonal pairs swing together (+X rotation = forward)
			var swing := 26.0
			_rot(inst, "Leg_FL", Vector3(swing, 0, 0))
			_rot(inst, "Leg_RR", Vector3(swing * 0.9, 0, 0))
			_rot(inst, "Leg_FR", Vector3(-swing, 0, 0))
			_rot(inst, "Leg_RL", Vector3(-swing * 0.9, 0, 0))
			if id == "deer" or id == "cow" or id == "rabbit":
				_rot(inst, "Head", Vector3(float(e.get("graze_head_pitch_deg", -65.0)), 0, 0))
			else:
				_rot(inst, "Head", Vector3(-8.0, 28.0, 0))
			_rot(inst, "Tail", Vector3(35.0, 18.0, 0))
		elif kind == "bird":
			var poses: Dictionary = e.get("poses", {})
			if id == "seagull":
				var folded: Dictionary = poses.get("folded", {})
				for part: String in folded.keys():
					var n := _part(inst, part)
					var p: Dictionary = folded[part]
					if n != null:
						n.rotation_degrees = _vec(p["rotation_degrees"])
						n.scale = _vec(p["scale"])
				_rot(inst, "Head", Vector3(0, 35.0, 0))
			else:
				# flight: up-stroke, legs tucked, lifted off the ground
				inst.position.y += 0.55
				_rot(inst, "Wing_R", Vector3(0, 0, 32.0))
				_rot(inst, "Wing_L", Vector3(0, 0, -32.0))
				var flight: Dictionary = poses.get("flight", {})
				if flight.has("Legs"):
					_rot(inst, "Legs", _vec((flight["Legs"] as Dictionary)["rotation_degrees"]))
				_rot(inst, "Tail", Vector3(-12.0, 0, 0))
		else:
			_rot(inst, "Tail", Vector3(0, 24.0, 0))
			_rot(inst, "Fin_L", Vector3(0, 0, 22.0))
			_rot(inst, "Fin_R", Vector3(0, 0, -22.0))


func _shot(shot_name: String, view_dir: Vector3, tighten: float) -> void:
	if not _has_bounds:
		return
	var c := _bounds.get_center()
	var r := _bounds.size.length() * 0.5
	_cam.fov = 30.0
	var dist := r / sin(deg_to_rad(15.0)) * tighten
	_cam.look_at_from_position(c + view_dir.normalized() * dist, c, Vector3.UP)
	_sun.directional_shadow_max_distance = maxf(40.0, dist * 1.6)
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var dir := ProjectSettings.globalize_path("res://qa/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("na_" + shot_name + ".png")
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
	_sun.directional_shadow_max_distance = 80.0
	add_child(_sun)
	_sun.look_at_from_position(Vector3(-6.0, 9.0, -7.0), Vector3.ZERO, Vector3.UP)
	var floor_mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(400.0, 0.05, 400.0)
	floor_mi.mesh = bm
	_floor_mat = StandardMaterial3D.new()
	_floor_mat.albedo_color = Color(0.55, 0.66, 0.42)
	_floor_mat.roughness = 0.95
	floor_mi.material_override = _floor_mat
	floor_mi.position = Vector3(0.0, -0.025, 0.0)
	add_child(floor_mi)
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 600.0
	add_child(_cam)
	_cam.make_current()
