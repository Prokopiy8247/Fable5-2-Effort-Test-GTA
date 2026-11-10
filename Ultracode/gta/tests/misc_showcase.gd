extends Node3D
## QA showcase for the set-piece GLBs in res://gta/generated/models/misc/ (author: set-piece artist).
## Isolated look-dev scene, no world boot: lines the assets up family by family on a neutral
## floor and saves screenshots to qa/screenshots/misc_<name>.png, so the in-engine look (flat
## shading, back-face culling, palette materials, glass alpha, emissives, relative scale) can be
## judged. The coral / white post in every shot is a 1.8 m scale stick (player height).
##
## Run (windowed, a few seconds):
##   tools\godot.ps1 -Mode window -Scene res://gta/tests/scenes/misc_showcase.tscn -Frames 300
## Headless runs only do the load / instantiate checks (no pixels).
## The stage (floor, light, scale stick) is test scaffolding built from primitives, never game content.

const DIR := "res://gta/generated/models/misc/"

## shot name -> rows of asset ids (row 0 is nearest to the camera)
const PLANS: Array = [
	["transit", [["rail_post", "tram", "rail_straight", "rail_post"]], Vector3(-1.0, 0.36, -0.6)],
	["wreck", [["shipwreck"]], Vector3(-1.0, 0.55, -0.35)],
	["harbour_a", [["mooring_bollard", "lifebuoy_stand", "buoy", "container_a", "container_b", "container_c", "container_open"],
			["fishing_boat_static", "cargo_stack", "dock_crane"]], Vector3(-0.55, 0.50, -1.0)],
	["harbour_b", [["boat_ramp"]], Vector3(-1.0, 0.45, -0.7)],
	["park", [["viewpoint_binoculars", "lounger", "beach_umbrella", "picnic_table", "playground_slide", "park_statue", "volleyball_net"],
			["lifeguard_tower", "fountain", "gazebo"]], Vector3(-0.50, 0.55, -1.0)],
	["airport", [["runway_light", "runway_sign", "helipad_beacon", "windsock", "aircraft_stairs"],
			["fuel_truck_static", "radar_dish"]], Vector3(-0.60, 0.45, -1.0)],
	["activities", [["target_round", "target_silhouette", "race_flag", "stunt_ramp_small", "stunt_ramp_big"],
			["checkpoint_arch"]], Vector3(-0.55, 0.50, -1.0)],
	["service", [["parachute_pack", "spike_strip", "traffic_barrier_arm", "police_light_stand", "parachute_canopy"]],
			Vector3(-0.55, 0.40, -1.0)],
]

var _cam: Camera3D
var _floor: MeshInstance3D
var _stick: Node3D
var _items: Array[Node3D] = []
var _fails: int = 0
var _shots: int = 0


func _ready() -> void:
	await _run()


func _run() -> void:
	_build_stage()
	var headless := DisplayServer.get_name() == "headless"
	for p: Array in PLANS:
		_layout(p[1])
		if not headless:
			await _shot_fit(String(p[0]), p[2])
		_clear()
		await get_tree().process_frame
	# inside the tram: standing in the rear car, looking forward through the gangway
	var tram := _spawn("tram")
	if tram != null:
		_stick.visible = false
		if not headless:
			_cam.fov = 72.0
			_cam.look_at_from_position(Vector3(0.0, 0.35 + 1.62, 4.6), Vector3(0.0, 1.55, -7.0), Vector3.UP)
			await _save("tram_inside")
			_cam.look_at_from_position(Vector3(4.6, 1.7, 1.6), Vector3(1.0, 1.2, 3.9), Vector3.UP)
			await _save("tram_door")
	_clear()
	print("TEST_RESULT: %s misc_showcase shots=%d failures=%d" % ["PASS" if _fails == 0 else "FAIL", _shots, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _spawn(id: String) -> Node3D:
	var path := DIR + id + ".glb"
	if not ResourceLoader.exists(path):
		_fails += 1
		print("CHECK_FAIL: misc_showcase missing ", path)
		return null
	var ps := load(path) as PackedScene
	var inst: Node3D = null
	if ps != null:
		inst = ps.instantiate() as Node3D
	if inst == null:
		_fails += 1
		print("CHECK_FAIL: misc_showcase cannot instantiate ", path)
		return null
	add_child(inst)
	_items.append(inst)
	return inst


## Places the rows along +X (left to right as seen by the camera), every asset resting on the floor.
func _layout(rows: Array) -> void:
	var z := 0.0
	for row: Array in rows:
		var x := 0.0
		var depth := 0.0
		var placed: Array = []
		for id: String in row:
			var inst := _spawn(id)
			if inst == null:
				continue
			var b := _bounds_of(inst)
			var gap := clampf(b.size.x * 0.35, 0.6, 3.0)
			# camera looks toward +Z from the -X side: X grows to the camera's left, so mirror the row
			inst.position = Vector3(-x - b.size.x - b.position.x, -b.position.y, 0.0)
			placed.append([inst, b])
			x += b.size.x + gap
			depth = maxf(depth, b.size.z)
		for it: Array in placed:
			var inst := it[0] as Node3D
			var b: AABB = it[1]
			inst.position.x += x * 0.5
			inst.position.z = z - b.position.z
		z += depth + 2.5
	_stick.visible = true
	_stick.position = Vector3(_bounds().end.x + 1.0, 0.0, 0.0)


func _clear() -> void:
	for it in _items:
		it.queue_free()
	_items.clear()


func _bounds_of(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var a := mi.global_transform * mi.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


func _bounds() -> AABB:
	var out := AABB()
	var first := true
	for it in _items:
		var a := _bounds_of(it)
		out = a if first else out.merge(a)
		first = false
	return out


## Corner points of every visible mesh AABB (+ the scale stick), in world space.
func _points() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for it in _items:
		for n: Node in it.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if not mi.visible or mi.mesh == null:
				continue
			var a := mi.get_aabb()
			for i in 8:
				pts.append(mi.global_transform * a.get_endpoint(i))
	if _stick.visible:
		pts.append(_stick.position)
		pts.append(_stick.position + Vector3(0.0, 1.8, 0.0))
	return pts


## Perspective shot from direction `dir` (target -> eye), framed so the whole line-up fits.
func _shot_fit(shot_name: String, dir: Vector3) -> void:
	var pts := _points()
	if pts.is_empty():
		return
	var d := dir.normalized()
	var right := Vector3.UP.cross(d).normalized()
	var up := d.cross(right).normalized()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in pts:
		var q := Vector3(p.dot(right), p.dot(up), p.dot(d))
		lo = lo.min(q)
		hi = hi.max(q)
	var mid := (lo + hi) * 0.5
	var c := right * mid.x + up * mid.y + d * mid.z
	var vfov := deg_to_rad(32.0)
	var size := get_viewport().get_visible_rect().size
	var th := tan(vfov * 0.5)
	var tw := th * size.x / maxf(size.y, 1.0)
	var dist := 1.0
	for p in pts:
		var o := p - c
		var along := o.dot(d)
		dist = maxf(dist, absf(o.dot(right)) / tw + along)
		dist = maxf(dist, absf(o.dot(up)) / th + along)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = rad_to_deg(vfov)
	_cam.far = dist * 3.0 + 200.0
	_cam.look_at_from_position(c + d * dist * 1.06, c, Vector3.UP)
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
	var path := dir.path_join("misc_" + shot_name + ".png")
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
	sun.look_at_from_position(Vector3(-6.0, 9.0, -5.0), Vector3.ZERO, Vector3.UP)
	_floor = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(400.0, 0.05, 400.0)
	_floor.mesh = bm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.66, 0.63, 0.57)
	fm.roughness = 0.95
	_floor.material_override = fm
	_floor.position = Vector3(0.0, -0.03, 0.0)
	add_child(_floor)
	# 1.8 m scale stick (player height)
	_stick = Node3D.new()
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
