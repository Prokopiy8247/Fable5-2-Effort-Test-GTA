extends Node3D
## QA showcase for the four aircraft GLBs in res://gta/generated/models/vehicles/ (author: aircraft
## artist). Isolated look-dev scene, no world boot. For every aircraft it saves
##   qa/screenshots/air_<id>_front.png   whole aircraft, front three-quarter
##   qa/screenshots/air_<id>_rear.png    fuselage close-up, rear three-quarter
##   qa/screenshots/air_<id>_pose.png    moving parts driven about their authored pivots (rotor /
##                                       propeller turned, doors and canopy open, control surfaces
##                                       deflected, searchlight aimed, blur discs shown)
## plus qa/screenshots/air_lineup.png (all four, relative scale). The coral / white post is a 1.8 m
## scale stick (player height).
##
## Run (windowed, a few seconds):
##   tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/air_showcase.tscn -Frames 400
## Headless runs only do the load / instantiate / pose checks (no pixels).
## The stage (floor, light, scale stick) is test scaffolding built from primitives, never game content.

const DIR := "res://gta/generated/models/vehicles/"
const IDS: Array[String] = ["heli_civil", "heli_police", "plane_prop", "plane_jet"]

## node -> [local axis, degrees] applied in the pose shot (Godot local axes of the imported nodes)
const POSE := {
	"Rotor_Main": [Vector3.UP, 35.0],
	"RotorBlur_Main": [Vector3.UP, 35.0],
	"Rotor_Tail": [Vector3.RIGHT, 50.0],
	"Propeller": [Vector3.BACK, 60.0],
	"Aileron_L": [Vector3.RIGHT, 22.0],       # + = trailing edge down
	"Aileron_R": [Vector3.RIGHT, -22.0],
	"Flap_L": [Vector3.RIGHT, 30.0],
	"Flap_R": [Vector3.RIGHT, 30.0],
	"Elevator": [Vector3.RIGHT, -20.0],
	"Rudder": [Vector3.UP, 25.0],             # + = trailing edge to the right (+X)
	"Canopy": [Vector3.RIGHT, 38.0],          # + = open
}

var _cam: Camera3D
var _stick: Node3D
var _fails: int = 0
var _shots: int = 0


func _ready() -> void:
	await _run()


func _run() -> void:
	_build_stage()
	var headless := DisplayServer.get_name() == "headless"
	for id: String in IDS:
		var inst := _spawn(id)
		if inst == null:
			continue
		_set_helpers(inst, false)
		await get_tree().process_frame
		if not headless:
			_stick.visible = true
			_stick.position = Vector3(_bounds_of(inst, false).end.x + 0.9, 0.0, -1.0)
			await _shot_fit("%s_front" % id, _with_stick(_bounds_of(inst, true)), Vector3(0.80, 0.42, -1.0))
			await _shot_fit("%s_rear" % id, _with_stick(_bounds_of(inst, false)), Vector3(-0.85, 0.50, 1.0))
		var posed := _pose(inst)
		print("AIR_POSE %s parts=%d" % [id, posed])
		_set_helpers(inst, true)
		await get_tree().process_frame
		if not headless:
			var dir := Vector3(1.0, 0.45, -0.55) if id.begins_with("heli") else Vector3(-0.7, 0.75, 1.0)
			await _shot_fit("%s_pose" % id, _with_stick(_bounds_of(inst, false)), dir)
		inst.queue_free()
		await get_tree().process_frame
	# relative scale: all four side by side
	var x := -19.0
	var all := AABB()
	var first := true
	for id: String in IDS:
		var inst := _spawn(id)
		if inst == null:
			continue
		_set_helpers(inst, false)
		inst.position = Vector3(x, 0.0, 0.0)
		x += 12.5
		await get_tree().process_frame
		var b := _bounds_of(inst, true)
		all = b if first else all.merge(b)
		first = false
	if not headless and not first:
		_stick.visible = true
		_stick.position = Vector3(all.end.x + 1.0, 0.0, -1.0)
		await _shot_fit("lineup", _with_stick(all), Vector3(0.30, 0.55, -1.0))
	print("TEST_RESULT: %s air_showcase shots=%d failures=%d" % ["PASS" if _fails == 0 else "FAIL", _shots, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _spawn(id: String) -> Node3D:
	var path := DIR + id + ".glb"
	if not ResourceLoader.exists(path):
		_fails += 1
		print("CHECK_FAIL: air_showcase missing ", path)
		return null
	var ps := load(path) as PackedScene
	var inst: Node3D = null
	if ps != null:
		inst = ps.instantiate() as Node3D
	if inst == null:
		_fails += 1
		print("CHECK_FAIL: air_showcase cannot instantiate ", path)
		return null
	add_child(inst)
	return inst


## Collision hulls are always hidden (as in game); blur discs only when `blur` is set.
func _set_helpers(root: Node3D, blur: bool) -> void:
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var nm := String(n.name)
		if nm.begins_with("Col_"):
			(n as MeshInstance3D).visible = false
		elif nm.contains("Blur"):
			(n as MeshInstance3D).visible = blur


## Drives every moving part about its authored pivot, the way the vehicle code is expected to.
func _pose(root: Node3D) -> int:
	var count := 0
	for part: String in POSE:
		var n := root.find_child(part, true, false) as Node3D
		if n == null:
			continue
		n.rotate_object_local(POSE[part][0], deg_to_rad(float(POSE[part][1])))
		count += 1
	for dn: String in ["Door_FL", "Door_FR", "Door_RL", "Door_RR"]:
		var d := root.find_child(dn, true, false) as Node3D
		if d == null:
			continue
		var side := -1.0 if d.position.x < 0.0 else 1.0
		d.transform = d.transform * Transform3D(Basis(Vector3.UP, side * 0.95), Vector3.ZERO)   # same as VehicleBase
		count += 1
	var sl := root.find_child("Searchlight", true, false) as Node3D
	if sl != null:
		sl.look_at(root.global_transform * Vector3(-5.0, 0.0, -7.0), Vector3.UP)
		count += 1
	return count


func _bounds_of(root: Node3D, with_rotor: bool) -> AABB:
	var out := AABB()
	var first := true
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var nm := String(mi.name)
		if not with_rotor and (nm == "Rotor_Main" or nm.contains("Blur")):
			continue
		var a := mi.global_transform * mi.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


func _with_stick(b: AABB) -> AABB:
	if not _stick.visible:
		return b
	return b.expand(_stick.position + Vector3(0.2, 1.8, 0.2)).expand(_stick.position - Vector3(0.2, 0.0, 0.2))


## Perspective shot from direction `dir` (target -> eye), framed so the whole box fits.
func _shot_fit(shot_name: String, b: AABB, dir: Vector3) -> void:
	var c := b.get_center()
	var d := dir.normalized()
	var vfov := deg_to_rad(32.0)
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var th := tan(vfov * 0.5)
	var tw := th * aspect
	var right := Vector3.UP.cross(d).normalized()
	var up := d.cross(right).normalized()
	var dist := 1.0
	for i in 8:
		var corner := b.get_endpoint(i) - c
		var along := corner.dot(d)
		dist = maxf(dist, absf(corner.dot(right)) / tw + along)
		dist = maxf(dist, absf(corner.dot(up)) / th + along)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = rad_to_deg(vfov)
	_cam.far = dist * 3.0 + 200.0
	_cam.look_at_from_position(c + d * dist * 1.04, c, Vector3.UP)
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
	var path := dir.path_join("air_" + shot_name + ".png")
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
	env.glow_enabled = true
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	sun.look_at_from_position(Vector3(5.0, 9.0, -7.0), Vector3.ZERO, Vector3.UP)
	var floor_mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(400.0, 0.05, 400.0)
	floor_mi.mesh = bm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.56, 0.55, 0.53)
	fm.roughness = 0.95
	floor_mi.material_override = fm
	floor_mi.position = Vector3(0.0, -0.03, 0.0)
	add_child(floor_mi)
	# 1.8 m scale stick (player height)
	_stick = Node3D.new()
	_stick.visible = false
	add_child(_stick)
	var parts := [[Vector3(0.12, 1.5, 0.12), 0.75, Color(0.95, 0.94, 0.90)], [Vector3(0.3, 0.3, 0.3), 1.65, Color(0.93, 0.49, 0.39)]]
	for part: Array in parts:
		var mi := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = part[0]
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = part[2]
		mi.material_override = m
		mi.position = Vector3(0.0, part[1], 0.0)
		_stick.add_child(mi)
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 400.0
	add_child(_cam)
	_cam.make_current()
