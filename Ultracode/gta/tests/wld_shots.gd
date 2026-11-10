extends Node
## WORLD screenshot test (windowed, short):
##   tools\godot.ps1 -Mode window -Frames 420 -UserArgs '--test=wld_shots','--disable=environment,city,...','--no_player'
## Own Camera3D; when the environment system is disabled it adds a temporary sun, sky colour and a flat
## water plane (test only). Writes qa/screenshots/wld_*.png. Optional user args: --wld_only=name1,name2
## (take only these shots), --wld_suffix=_env (appended to the file names).

const ZONE_COLOURS := {"office": Color(0.35, 0.55, 0.95), "apartment": Color(0.95, 0.6, 0.3), "house": Color(0.95, 0.85, 0.35),
		"storefront": Color(0.9, 0.35, 0.6), "warehouse": Color(0.6, 0.6, 0.65), "hangar": Color(0.45, 0.75, 0.8),
		"parking": Color(0.3, 0.3, 0.35), "park": Color(0.3, 0.8, 0.35), "landmark": Color(1.0, 0.2, 0.2), "plaza": Color(0.85, 0.8, 0.7)}

var _cam: Camera3D
var _overlay: Node3D
var _only: PackedStringArray = []
var _suffix := ""


func _ready() -> void:
	var w: Variant = Game.world
	if w == null:
		TestHarness.finish(false, "no world")
		return
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--wld_only="):
			_only = a.substr(11).split(",", false)
		elif a.begins_with("--wld_suffix="):
			_suffix = a.substr(13)
	_cam = Camera3D.new()
	_cam.far = 4000.0
	_cam.near = 0.2
	_cam.fov = 60.0
	add_child(_cam)
	_cam.make_current()
	if Game.get_system("environment") == null:
		_temp_environment()
	var ui := get_node_or_null("/root/UI")
	if ui != null and ui.has_method("set_hud_visible"):
		ui.call("set_hud_visible", false)
	await TestHarness.wait_frames(6)
	await TestHarness.wait_frames(75)          # let the boot banner of the UI fade out

	# straight-down overview (north up)
	await _shot_down("wld_overview_top", Vector3(0.0, 0.0, 5.0), 760.0)
	await _shot("wld_overview_sw", Vector3(-430.0, 260.0, 470.0), Vector3(0.0, 0.0, 20.0), 50.0)
	await _shot("wld_overview_ne", Vector3(440.0, 230.0, -430.0), Vector3(40.0, 0.0, -40.0), 50.0)
	# street level
	await _shot("wld_downtown_intersection", Vector3(14.0, 7.5, -86.0), Vector3(-2.0, 2.5, -107.0), 65.0)
	await _shot("wld_corner_closeup", Vector3(11.5, 4.3, -93.5), Vector3(5.5, 2.5, -100.5), 60.0)
	await _shot("wld_avenue_parking", Vector3(-3.5, 4.2, 40.0), Vector3(1.0, 2.5, -10.0), 65.0)
	await _shot("wld_ring_arterial", Vector3(-150.0, 9.0, -182.0), Vector3(-60.0, 2.5, -190.0), 60.0)
	await _shot("wld_ring_bend", Vector3(96.0, 22.0, -150.0), Vector3(122.0, 2.5, -192.0), 60.0)
	await _shot("wld_hill_road", Vector3(140.0, 16.0, -50.0), Vector3(205.0, 16.0, -130.0), 60.0)
	await _shot("wld_hill_top", Vector3(262.0, 52.0, -96.0), Vector3(222.0, 34.0, -130.0), 60.0)
	await _shot("wld_beach", Vector3(96.0, 9.0, 236.0), Vector3(175.0, 0.0, 268.0), 65.0)
	await _shot("wld_docks_edge", Vector3(-262.0, 11.0, 196.0), Vector3(-272.0, 0.0, 262.0), 68.0)
	await _shot("wld_marina_piers", Vector3(-176.0, 9.0, 244.0), Vector3(-140.0, 0.0, 276.0), 65.0)
	await _shot("wld_runway", Vector3(-196.0, 9.0, -258.0), Vector3(40.0, 2.5, -264.0), 55.0)
	await _shot("wld_airfield", Vector3(40.0, 60.0, -150.0), Vector3(30.0, 2.5, -245.0), 60.0)
	await _shot("wld_residential", Vector3(150.0, 30.0, 110.0), Vector3(190.0, 2.5, 40.0), 60.0)
	await _shot("wld_park_paths", Vector3(166.0, 14.0, 70.0), Vector3(190.0, 2.5, 30.0), 62.0)
	await _shot("wld_dune_trail", Vector3(283.0, 7.0, 64.0), Vector3(266.0, 2.0, 130.0), 60.0)
	await _shot("wld_lighthouse_lane", Vector3(-22.0, 9.0, 226.0), Vector3(6.0, 3.0, 262.0), 60.0)
	await _shot("wld_beach_parking", Vector3(160.0, 16.0, 150.0), Vector3(158.0, 2.5, 184.0), 62.0)
	await _shot("wld_marina_east_end", Vector3(-6.0, 16.0, 218.0), Vector3(-30.0, 1.0, 250.0), 60.0)
	await _shot("wld_airport_parking", Vector3(-168.0, 20.0, -176.0), Vector3(-168.0, 2.5, -212.0), 62.0)
	# nature placement data as markers (the real vegetation is placed by the city dressing module)
	if _wanted("wld_data_nature") or _wanted("wld_data_nature_hill") or _wanted("wld_data_nature_beach") or _wanted("wld_data_nature_park"):
		var nat := _build_nature_overlay(w)
		add_child(nat)
		await _shot_down("wld_data_nature", Vector3(0.0, 0.0, 5.0), 760.0)
		await _shot("wld_data_nature_hill", Vector3(130.0, 70.0, -10.0), Vector3(215.0, 15.0, -125.0), 60.0)
		await _shot("wld_data_nature_beach", Vector3(60.0, 40.0, 170.0), Vector3(150.0, 0.0, 270.0), 60.0)
		await _shot("wld_data_nature_park", Vector3(150.0, 45.0, 95.0), Vector3(191.0, 2.5, 22.0), 60.0)
		nat.queue_free()
		await TestHarness.wait_frames(2)
	# data overlay: lots by zone, lanes, walk links
	_overlay = _build_overlay(w)
	add_child(_overlay)
	await _shot_down("wld_overview_data", Vector3(0.0, 0.0, 5.0), 760.0)
	await _shot_down("wld_data_downtown", Vector3(0.0, 0.0, -60.0), 230.0)
	await _shot_down("wld_data_waterfront", Vector3(-80.0, 0.0, 200.0), 260.0)
	TestHarness.finish()


func _wanted(shot_name: String) -> bool:
	return _only.is_empty() or _only.has(shot_name)


func _shot(shot_name: String, from: Vector3, to: Vector3, fov: float) -> void:
	if not _wanted(shot_name):
		return
	_cam.fov = fov
	_cam.global_position = from
	_cam.look_at(to, Vector3.UP)
	await TestHarness.wait_frames(4)
	await TestHarness.shot(shot_name + _suffix)


func _shot_down(shot_name: String, target: Vector3, height: float) -> void:
	if not _wanted(shot_name):
		return
	_cam.fov = 50.0
	_cam.global_position = target + Vector3(0.0, height, 0.0)
	_cam.look_at(target, Vector3(0, 0, -1))
	await TestHarness.wait_frames(4)
	await TestHarness.shot(shot_name + _suffix)


func _temp_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 38.0, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.56, 0.74, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.72, 0.86)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4200.0, 4200.0)
	water.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.44, 0.60, 0.72)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.12
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


const NATURE_MARKERS := {"tree_hill": [Color(0.08, 0.42, 0.14), 2.2, 7.0], "tree_wild": [Color(0.4, 0.62, 0.12), 2.2, 6.0],
		"tree_palm": [Color(0.98, 0.72, 0.15), 1.8, 8.0], "tree_park": [Color(0.1, 0.85, 0.45), 2.2, 6.0],
		"bush": [Color(0.55, 0.85, 0.3), 1.0, 1.4], "rock": [Color(0.45, 0.45, 0.5), 1.1, 1.0],
		"ground_cover": [Color(0.85, 1.0, 0.55), 0.5, 0.4], "reef": [Color(1.0, 0.3, 0.75), 1.4, 2.0]}


## Crossed vertical triangles plus a flat diamond per nature point (visible from the side and from above).
func _build_nature_overlay(w: Variant) -> Node3D:
	var root := Node3D.new()
	for pass_i in 2:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = pass_i == 1          # reef markers show through the water
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
		for kind: String in NATURE_MARKERS:
			if (kind == "reef") != (pass_i == 1):
				continue
			var spec: Array = NATURE_MARKERS[kind]
			var col: Color = spec[0]
			var r: float = spec[1]
			var hgt: float = spec[2]
			for xf: Transform3D in w.get_spawn_points(kind):
				var o := xf.origin
				var top := o + Vector3(0.0, hgt, 0.0)
				var flat := o + Vector3(0.0, 0.35, 0.0)
				var tris: Array[Vector3] = [o + Vector3(-r, 0, 0), o + Vector3(r, 0, 0), top, o + Vector3(0, 0, -r), o + Vector3(0, 0, r), top,
						flat + Vector3(-r, 0, 0), flat + Vector3(0, 0, -r), flat + Vector3(r, 0, 0),
						flat + Vector3(-r, 0, 0), flat + Vector3(r, 0, 0), flat + Vector3(0, 0, r)]
				for i in tris.size():
					im.surface_set_color(col.darkened(0.25) if i < 6 and (i % 3) != 2 else col)
					im.surface_add_vertex(tris[i])
		im.surface_end()
		var mi := MeshInstance3D.new()
		mi.mesh = im
		root.add_child(mi)
	return root


func _build_overlay(w: Variant) -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	var tris := ImmediateMesh.new()
	tris.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for lot: Dictionary in w.get_lots():
		var c: Vector3 = lot["center"]
		var size: Vector2 = lot["size"]
		var yaw: float = lot["yaw"]
		var col: Color = ZONE_COLOURS.get(String(lot["zone"]), Color.WHITE)
		col.a = 0.6
		var b := Basis(Vector3.UP, yaw)
		var hx := b.x * (size.x * 0.5 - 0.4)
		var hz := b.z * (size.y * 0.5 - 0.4)
		var o := c + Vector3(0.0, 0.5, 0.0)
		var p: Array[Vector3] = [o - hx - hz, o + hx - hz, o + hx + hz, o - hx + hz]
		for i: int in [0, 1, 2, 0, 2, 3]:
			tris.surface_set_color(col)
			tris.surface_add_vertex(p[i])
		# front marker (dark stripe at the street side)
		var f0 := o - hz * 0.92
		var fp: Array[Vector3] = [f0 - hx - hz * 0.08, f0 + hx - hz * 0.08, f0 + hx + hz * 0.08, f0 - hx + hz * 0.08]
		for i: int in [0, 1, 2, 0, 2, 3]:
			tris.surface_set_color(Color(0.05, 0.05, 0.05, 0.9))
			tris.surface_add_vertex(fp[i] + Vector3(0.0, 0.1, 0.0))
	tris.surface_end()
	var mi_t := MeshInstance3D.new()
	mi_t.mesh = tris
	root.add_child(mi_t)
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var roads: Variant = w.get("roads")
	for l: Dictionary in roads.lanes:
		var pts: PackedVector3Array = l["points"]
		var col := Color(0.2, 1.0, 1.0) if int(l["direction"]) == 1 else Color(1.0, 0.9, 0.2)
		for i in range(1, pts.size()):
			lines.surface_set_color(col)
			lines.surface_add_vertex(pts[i - 1] + Vector3(0.0, 0.8, 0.0))
			lines.surface_set_color(col)
			lines.surface_add_vertex(pts[i] + Vector3(0.0, 0.8, 0.0))
		for nx: int in (l["next"] as PackedInt32Array):
			var a: Vector3 = pts[pts.size() - 1]
			var b2: Vector3 = (roads.lanes[nx]["points"] as PackedVector3Array)[0]
			lines.surface_set_color(Color(1.0, 0.3, 1.0, 0.8))
			lines.surface_add_vertex(a + Vector3(0.0, 0.8, 0.0))
			lines.surface_set_color(Color(1.0, 0.3, 1.0, 0.8))
			lines.surface_add_vertex(b2 + Vector3(0.0, 0.8, 0.0))
	var walk: Variant = w.get("walk")
	var wp: PackedVector3Array = walk.points
	for i in wp.size():
		for j: int in (walk.links[i] as PackedInt32Array):
			if j > i:
				var col := Color(1.0, 1.0, 1.0) if int((walk.kinds as PackedByteArray)[i]) != 1 and int((walk.kinds as PackedByteArray)[j]) != 1 else Color(1.0, 0.4, 0.1)
				lines.surface_set_color(col)
				lines.surface_add_vertex(wp[i] + Vector3(0.0, 0.9, 0.0))
				lines.surface_set_color(col)
				lines.surface_add_vertex(wp[j] + Vector3(0.0, 0.9, 0.0))
	var tram: PackedVector3Array = w.get_transit_path()
	for i in range(1, tram.size()):
		lines.surface_set_color(Color(1.0, 0.1, 0.1))
		lines.surface_add_vertex(tram[i - 1] + Vector3(0.0, 1.2, 0.0))
		lines.surface_set_color(Color(1.0, 0.1, 0.1))
		lines.surface_add_vertex(tram[i] + Vector3(0.0, 1.2, 0.0))
	lines.surface_end()
	var mi_l := MeshInstance3D.new()
	mi_l.mesh = lines
	root.add_child(mi_l)
	return root
