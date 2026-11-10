extends Node
## Automated, time-limited validation scenarios:  godot --path . -- --test=<name>
## Every scenario ends with get_tree().quit(); a watchdog force-quits after 100 s.

var scenario := "world"
var fails := 0
var cam: Camera3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(100.0, true, false, true).timeout.connect(func():
		print("[TEST] WATCHDOG quit")
		get_tree().quit(2))
	await get_tree().create_timer(1.0).timeout
	if has_method("t_" + scenario):
		await call("t_" + scenario)
	else:
		print("[TEST] unknown scenario ", scenario)
	print("[TEST] DONE scenario=%s fails=%d" % [scenario, fails])
	get_tree().quit(1 if fails > 0 else 0)


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func check(name: String, ok: bool, extra := "") -> void:
	print("[TEST] %s %s %s" % ["PASS" if ok else "FAIL", name, extra])
	if not ok:
		fails += 1


func hold(action: String, secs: float) -> void:
	Input.action_press(action)
	await wait(secs)
	Input.action_release(action)


func tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func t_parse() -> void:
	var bad = 0
	var stack = ["res://gta/code"]
	var n = 0
	while stack.size() > 0:
		var d: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(d):
			stack.append(d + "/" + sub)
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				n += 1
				var s = load(d + "/" + f)
				if s == null or not (s as GDScript).can_instantiate():
					bad += 1
					print("[TEST] FAIL parse ", d + "/" + f)
	check("all scripts parse (%d)" % n, bad == 0)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	img.save_png("res://screenshots/%s.png" % name)
	print("[TEST] shot ", name)


func free_cam(pos: Vector3, look: Vector3) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.far = 1500.0
		G.main.add_child(cam)
	cam.global_position = pos
	cam.look_at(look)
	cam.make_current()


func release_cam() -> void:
	if cam:
		cam.queue_free()
		cam = null
	if G.cam:
		G.cam.camera.make_current()


func t_world() -> void:
	free_cam(Vector3(-260, 190, 330), Vector3(0, 0, -20))
	await wait(1.0)
	await shot("world_overview")
	free_cam(Vector3(-40, 9, 34), Vector3(40, 14, -30))
	await wait(0.5)
	await shot("world_downtown")
	free_cam(Vector3(-200, 7, 60), Vector3(-170, 2, 0))
	await wait(0.5)
	await shot("world_residential")
	free_cam(Vector3(110, 14, 260), Vector3(60, 0, 200))
	await wait(0.5)
	await shot("world_waterfront")
	free_cam(Vector3(120, 20, -190), Vector3(160, 2, -250))
	await wait(0.5)
	await shot("world_airport")
	free_cam(Vector3(-120, 30, -90), Vector3(-180, 12, -150))
	await wait(0.5)
	await shot("world_hill")
	free_cam(Vector3(230, 18, 100), Vector3(170, 2, 30))
	await wait(0.5)
	await shot("world_industrial")
	check("world built", G.world.blocks.size() == 16)
