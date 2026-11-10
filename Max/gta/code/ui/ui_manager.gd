class_name UIManager
extends Control
## Owns every interactive screen: pause menu, full-screen map, weapon wheel, phone, shops,
## the admin / benchmark menu and photo mode, and routes input to whichever one is open.

var menu: MenuList
var map: MapScreen
var wheel: WeaponWheel
var mode := ""                    # "" | pause | shop | admin | phone | map | wheel | photo
var shop_kind := ""
var font: Font
var _paused := false
var _map_from_pause := false
var _photo_yaw := 0.0
var _photo_pitch := 0.0
var _photo_fov := 70.0
var _photo_hud := true
var _photo_count := 0
var _photo_msg := 0.0
var _saved_cam := Transform3D.IDENTITY

func _ready() -> void:
	name = "UIManager"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	Game.menus = self
	menu = MenuList.new()
	add_child(menu)
	menu.closed.connect(_on_menu_closed)
	map = MapScreen.new()
	add_child(map)
	map.closed.connect(_on_map_closed)
	wheel = WeaponWheel.new()
	add_child(wheel)

func is_open() -> bool:
	return mode != ""

# ---------------------------------------------------------------- open / close
func open_menu(kind: String, title: String, subtitle: String, build: Callable, pause := false, right := false, accent := Color(0.18, 0.9, 1.0)) -> void:
	if mode != "":
		return
	mode = kind
	_paused = pause
	menu.align_right = right
	menu.panel_w = 420.0 if right else 560.0
	menu.accent = accent
	menu.footer = ""
	Game.ui_push()
	if pause:
		get_tree().paused = true
	menu.open(title, subtitle, build)

func close_all() -> void:
	if wheel.visible:
		_close_wheel(false)
	if map.visible:
		map.close()
	if menu.visible:
		menu.close()
	if mode == "photo":
		_exit_photo()

func _on_menu_closed() -> void:
	if mode == "map":
		return
	Game.ui_pop()
	if _paused:
		get_tree().paused = false
		_paused = false
	mode = ""
	Events.menu_closed.emit()

func _on_map_closed() -> void:
	if _map_from_pause:
		_map_from_pause = false
		mode = "pause"
		menu.visible = true
		return
	Game.ui_pop()
	if _paused:
		get_tree().paused = false
		_paused = false
	mode = ""

func open_map() -> void:
	if mode == "pause":
		_map_from_pause = true
		menu.visible = false
		mode = "map"
		map.open()
		return
	if mode != "":
		return
	mode = "map"
	_paused = true
	Game.ui_push()
	get_tree().paused = true
	map.open()

func _open_wheel() -> void:
	var p: Player = Game.player
	if p == null or not p.alive or p.state == Player.St.BUSTED:
		return
	mode = "wheel"
	Game.soft_block += 1
	wheel.open()

func _close_wheel(apply: bool) -> void:
	wheel.close(apply)
	Game.soft_block = maxi(0, Game.soft_block - 1)
	mode = ""

# ---------------------------------------------------------------- input routing
func _input(event: InputEvent) -> void:
	if mode == "photo":
		_photo_input(event)
		get_viewport().set_input_as_handled()
		return
	if mode == "wheel":
		if event.is_action_released("weapon_wheel"):
			_close_wheel(true)
		elif wheel.handle_input(event):
			get_viewport().set_input_as_handled()
		return
	if mode == "map":
		if map.handle_input(event):
			get_viewport().set_input_as_handled()
		return
	if menu.visible:
		if mode == "admin" and event.is_action_pressed("debug_menu"):
			menu.close()
			get_viewport().set_input_as_handled()
			return
		if mode == "phone" and event.is_action_pressed("phone"):
			menu.close()
			get_viewport().set_input_as_handled()
			return
		if menu.handle_input(event):
			get_viewport().set_input_as_handled()
		return
	if Game.automated and not (event is InputEventAction):
		pass
	if event.is_action_pressed("pause"):
		open_pause()
	elif event.is_action_pressed("map"):
		open_map()
	elif event.is_action_pressed("weapon_wheel"):
		_open_wheel()
	elif event.is_action_pressed("phone"):
		open_phone()
	elif event.is_action_pressed("debug_menu"):
		open_admin()
	elif event.is_action_pressed("photo_mode"):
		enter_photo()
	elif event.is_action_pressed("quick_save"):
		quick_save()
	elif event.is_action_pressed("quick_load"):
		quick_load()
	elif event.is_action_pressed("toggle_fps"):
		Game.flags["show_fps"] = not Game.flags["show_fps"]

# ---------------------------------------------------------------- pause menu
func open_pause() -> void:
	open_menu("pause", Game.GAME_TITLE, "Paused", _pause_rows, true)

func _pause_rows() -> Array:
	return [
		{"text": "Resume", "fn": func() -> void: menu.close()},
		{"text": "Map", "desc": "City map, locations and GPS waypoint.", "fn": open_map},
		{"text": "Stats & Skills", "page": _stats_rows},
		{"text": "Settings", "page": _settings_rows},
		{"text": "Controls", "page": _controls_rows},
		{"text": "Save Game", "page": func() -> Array: return _slot_rows(true)},
		{"text": "Load Game", "page": func() -> Array: return _slot_rows(false)},
		{"text": "Admin / Benchmark Menu", "desc": "Teleports, spawns, wanted level, time, weather and test toggles (F1 in game).",
			"fn": func() -> void:
				menu.close()
				open_admin()},
		{"text": "Quit to Desktop", "page": func() -> Array: return [
			{"text": "No, keep playing", "fn": func() -> void: menu.back()},
			{"text": "Yes, quit", "desc": "Unsaved progress is lost.", "fn": func() -> void: get_tree().quit()},
		]},
	]

func _slot_rows(saving: bool) -> Array:
	var rows: Array = []
	for slot: String in ["slot1", "slot2", "slot3", "quick"]:
		var label := "Quick slot" if slot == "quick" else "Slot %s" % slot.substr(4)
		var has := SaveSystem.has_save(slot)
		var info := "empty"
		if has:
			info = Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(SaveSystem.slot_path(slot))).replace("T", " ")
		if saving:
			rows.append({"text": label, "right": info, "desc": "Saves position, health, cash, weapons, clothing, skills, time, weather and stored vehicles.",
				"fn": func() -> void: _save_to(slot)})
		else:
			rows.append({"text": label, "right": info, "off": not has, "fn": func() -> void: _load_from(slot)})
	return rows

func _save_to(slot: String) -> void:
	if Game.wanted != null and Game.wanted.level > 0:
		Game.notify("Cannot save while wanted", "bad")
		return
	if SaveSystem.save_game(slot):
		Game.notify("Game saved", "good")
	else:
		Game.notify("Save failed: " + SaveSystem.last_error, "bad")

func _load_from(slot: String) -> void:
	menu.close()
	if SaveSystem.load_game(slot):
		Game.notify("Game loaded", "good")
	else:
		Game.notify("Load failed: " + SaveSystem.last_error, "bad")

func quick_save() -> void:
	_save_to("quick")

func quick_load() -> void:
	if not SaveSystem.has_save("quick"):
		Game.notify("No quick save yet (F5 saves)", "info")
		return
	if SaveSystem.load_game("quick"):
		Game.notify("Quick save loaded", "good")

func _stats_rows() -> Array:
	var rows: Array = [{"text": "Skills", "header": true}]
	var sk: Skills = Game.skills
	for s in Skills.LIST:
		rows.append({"text": String(Skills.NAMES[s]), "right": "%d%%" % int(round(sk.level(s) * 100.0)), "info": true, "desc": String(Skills.DESC[s])})
	rows.append({"text": "Statistics", "header": true})
	var st := Game.stats
	var t := int(st["play_time"])
	var list := [
		["Play time", "%d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]],
		["Distance on foot", "%.2f km" % (float(st["distance_foot"]) / 1000.0)],
		["Distance driven", "%.2f km" % (float(st["distance_drive"]) / 1000.0)],
		["Distance flown", "%.2f km" % (float(st["distance_fly"]) / 1000.0)],
		["Distance swum", "%.2f km" % (float(st["distance_swim"]) / 1000.0)],
		["Shots fired", str(st["shots_fired"])],
		["Kills", str(st["kills"])],
		["Vehicles stolen", str(st["vehicles_stolen"])],
		["Vehicles destroyed", str(st["vehicles_destroyed"])],
		["Highest wanted level", str(st["max_wanted"])],
		["Times busted", str(st["busted"])],
		["Times wasted", str(st["deaths"])],
		["Stunt jumps completed", str(st["stunt_jumps"])],
		["Longest jump", "%.1f m" % float(st["best_jump"])],
		["Cash spent", "$" + HUD._commas(int(st["cash_spent"]))],
	]
	for e in list:
		rows.append({"text": e[0], "right": e[1], "info": true})
	rows.append({"text": "Back", "fn": func() -> void: menu.back()})
	return rows

func _slider(label: String, key: String, lo: float, hi: float, step: float, fmt := "%.2f", desc := "") -> Dictionary:
	return {"text": label, "desc": desc, "slider": {"min": lo, "max": hi, "step": step, "value": float(Settings.get_v(key, lo)), "fmt": fmt,
		"on_change": func(v: float) -> void: Settings.set_v(key, v)}}

func _toggle(label: String, key: String, desc := "") -> Dictionary:
	return {"text": label, "desc": desc, "opts": ["Off", "On"], "idx": 1 if bool(Settings.get_v(key, false)) else 0,
		"on_opt": func(i: int) -> void: Settings.set_v(key, i == 1)}

func _settings_rows() -> Array:
	var fps_opts := [30, 60, 90, 120]
	return [
		{"text": "Audio", "header": true},
		_slider("Master volume", "master_volume", 0.0, 1.0, 0.05),
		_slider("Effects volume", "sfx_volume", 0.0, 1.0, 0.05),
		_slider("Music / radio volume", "music_volume", 0.0, 1.0, 0.05),
		_slider("Ambience volume", "ambient_volume", 0.0, 1.0, 0.05),
		{"text": "Controls", "header": true},
		_slider("Mouse sensitivity", "mouse_sensitivity", 0.2, 3.0, 0.1),
		_toggle("Invert Y axis", "invert_y"),
		_slider("Field of view", "fov", 55.0, 95.0, 1.0, "%.0f"),
		_slider("Camera shake", "camera_shake", 0.0, 1.0, 0.1),
		{"text": "Display", "header": true},
		{"text": "Quality preset", "opts": ["Low", "Medium", "High"], "idx": int(Settings.get_v("quality", 1)),
			"desc": "Shadows, anti-aliasing and effect density. Medium is the tested default.",
			"on_opt": func(i: int) -> void: Settings.set_v("quality", i)},
		_slider("3D render scale", "render_scale", 0.5, 1.0, 0.05, "%.2f", "Never above 1.0 (GPU safety)."),
		{"text": "Frame-rate cap", "opts": ["30", "60", "90", "120"], "idx": maxi(fps_opts.find(int(Settings.get_v("max_fps", 60))), 0),
			"desc": "The game always runs with a frame-rate cap.",
			"on_opt": func(i: int) -> void: Settings.set_v("max_fps", int(fps_opts[i]))},
		_toggle("V-Sync", "vsync"),
		_toggle("Fullscreen", "fullscreen"),
		_toggle("Show FPS", "show_fps"),
		{"text": "World", "header": true},
		_slider("Traffic density", "traffic_density", 0.0, 1.5, 0.1, "%.1f"),
		_slider("Pedestrian density", "ped_density", 0.0, 1.5, 0.1, "%.1f"),
	]

func _controls_rows() -> Array:
	var keys := [
		["On foot", ""],
		["Move / look", "WASD / Mouse"], ["Sprint", "Left Shift"], ["Jump / vault / climb", "Space"], ["Crouch / stealth", "C or Left Ctrl"],
		["Take cover", "Q"], ["Combat roll (while aiming)", "Space"], ["Interact / shop", "E"], ["Enter / exit vehicle", "F"],
		["Fire / punch", "Left Mouse"], ["Aim / block", "Right Mouse"], ["Heavy melee / takedown", "Middle Mouse or X"],
		["Reload", "R"], ["Throw grenade", "G"], ["Weapon wheel", "Tab (hold)"], ["Weapon slots", "1-8, mouse wheel, 0 = holster"],
		["Camera: third / first person", "V"],
		["Vehicles", ""],
		["Accelerate / brake / steer", "W / S / A D"], ["Handbrake", "Space"], ["Horn", "H"], ["Headlights", "L"], ["Siren", "J"],
		["Drive-by aim / fire", "Right / Left Mouse"], ["Look behind", "B"], ["Radio next / previous", ". / ,"],
		["Bail out (moving)", "Hold F"],
		["Aircraft", ""],
		["Helicopter", "W S pitch, A D roll, Q E yaw, Shift / Ctrl lift"], ["Airplane", "W S pitch, A D roll, Q E rudder, Shift / Ctrl throttle"],
		["Parachute", "Space in free fall, WASD steer"],
		["Menus", ""],
		["Map", "M"], ["Phone", "P or Up"], ["Pause", "Esc"], ["Quick save / load", "F5 / F9"], ["Photo mode", "F8"],
		["Admin / benchmark menu", "F1"], ["Show FPS", "F3"],
	]
	var rows: Array = []
	for k in keys:
		if k[1] == "":
			rows.append({"text": k[0], "header": true})
		else:
			rows.append({"text": k[0], "right": k[1], "info": true})
	rows.append({"text": "Back", "fn": func() -> void: menu.back()})
	return rows

# ---------------------------------------------------------------- phone
func open_phone() -> void:
	var p: Player = Game.player
	if p == null or not p.alive:
		return
	open_menu("phone", "Tide Phone", (Game.time.clock_text() if Game.time else "") + "   " + Game.district_at(p.global_position), _phone_rows, false, true, Color(1.0, 0.25, 0.63))
	Audio.play_ui(&"ui_phone", -8.0)

func _phone_rows() -> Array:
	var rows: Array = [
		{"text": "Contacts", "header": true},
		{"text": "ZipCab", "right": "taxi", "desc": "A cab picks you up. Set a waypoint on the map first, or choose a destination inside the cab.",
			"fn": func() -> void:
				menu.close()
				if Game.transit != null and Game.transit.has_method("call_taxi"):
					Game.transit.call_taxi()
				else:
					Game.notify("ZipCab is not answering", "info")},
		{"text": "Torque House", "right": "$250", "desc": "The garage delivers your personal vehicle to the nearest road.",
			"fn": func() -> void:
				menu.close()
				if Game.garage != null and Game.garage.has_method("deliver_personal"):
					Game.garage.deliver_personal()
				else:
					Game.notify("Torque House is closed", "info")},
		{"text": "Emergency line", "page": func() -> Array: return [
			{"text": "Ambulance", "desc": "Paramedics drive to your position.", "fn": func() -> void: _call_service("ambulance")},
			{"text": "Fire department", "fn": func() -> void: _call_service("fire")},
			{"text": "Police", "desc": "A patrol comes by. They will not be amused if you are the problem.", "fn": func() -> void: _call_service("police")},
		]},
		{"text": "Apps", "header": true},
		{"text": "Map & GPS", "fn": func() -> void:
			menu.close()
			open_map()},
		{"text": "Camera", "desc": "Free camera photo mode. Photos are stored in the user folder.", "fn": func() -> void:
			menu.close()
			enter_photo()},
		{"text": "Quick save", "fn": func() -> void:
			quick_save()
			menu.close()},
		{"text": "Clear GPS waypoint", "off": Game.hud == null or Game.hud.waypoint == null, "fn": func() -> void: Game.hud.set_waypoint(null)},
	]
	return rows

func _call_service(kind: String) -> void:
	menu.close()
	if Game.services != null and Game.services.has_method("request"):
		Game.services.request(kind, Game.player_pos(), true)
	else:
		Game.notify("No answer", "info")

# ---------------------------------------------------------------- shops / admin (row builders live in their own files)
func open_shop(kind: String, context: Dictionary = {}) -> void:
	var def: Dictionary = ShopMenus.describe(kind)
	if def.is_empty() or mode != "":
		return
	shop_kind = kind
	open_menu("shop", String(def["title"]), String(def["subtitle"]), func() -> Array: return ShopMenus.rows(kind, self, context), false, false, def.get("accent", Color(0.18, 0.9, 1.0)))
	menu.closed.connect(func() -> void:
		ShopMenus.on_close(kind, context)
		shop_kind = "", CONNECT_ONE_SHOT)

func open_admin() -> void:
	open_menu("admin", "Admin / Benchmark", "Testing tools", func() -> Array: return AdminMenu.rows(self), false, false, Color(1.0, 0.8, 0.2))

# ---------------------------------------------------------------- photo mode
func enter_photo() -> void:
	if mode != "" or Game.cam == null:
		return
	mode = "photo"
	Game.ui_push()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = true
	var cam := Game.cam.cam
	_saved_cam = cam.global_transform
	_photo_fov = cam.fov
	var e := cam.global_transform.basis.get_euler()
	_photo_pitch = e.x
	_photo_yaw = e.y
	Game.cam.photo_mode = true
	_photo_hud = Game.hud.show_hud if Game.hud != null else true
	if Game.hud != null:
		Game.hud.show_hud = false
		Game.hud.visible = false
	queue_redraw()

func _exit_photo() -> void:
	Game.cam.photo_mode = false
	Game.cam.cam.global_transform = _saved_cam
	if Game.hud != null:
		Game.hud.show_hud = _photo_hud
		Game.hud.visible = true
	get_tree().paused = false
	mode = ""
	Game.ui_pop()
	queue_redraw()

func _photo_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var rel := (event as InputEventMouseMotion).relative
		_photo_yaw -= rel.x * 0.0026
		_photo_pitch = clampf(_photo_pitch - rel.y * 0.0026, -1.5, 1.5)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_photo_fov = maxf(_photo_fov - 3.0, 12.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_photo_fov = minf(_photo_fov + 3.0, 100.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_take_photo()
	elif event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE or k == KEY_F8 or k == KEY_BACKSPACE:
			_exit_photo()
		elif k == KEY_ENTER or k == KEY_SPACE:
			_take_photo()

func _take_photo() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://photos"))
	_photo_msg = -1.0                  # hide the overlay for the capture frame
	queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_photo_count += 1
	var path := "user://photos/photo_%s_%02d.png" % [Time.get_datetime_string_from_system().replace(":", "-"), _photo_count]
	if img != null and img.save_png(path) == OK:
		_photo_msg = 2.5
		Audio.play_ui(&"ui_camera", -4.0)
	else:
		_photo_msg = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if mode != "photo":
		return
	var cam := Game.cam.cam
	var real := delta / maxf(Engine.time_scale, 0.05)
	var b := Basis.from_euler(Vector3(_photo_pitch, _photo_yaw, 0.0))
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move -= b.z
	if Input.is_key_pressed(KEY_S):
		move += b.z
	if Input.is_key_pressed(KEY_A):
		move -= b.x
	if Input.is_key_pressed(KEY_D):
		move += b.x
	if Input.is_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move -= Vector3.UP
	var speed := 30.0 if Input.is_key_pressed(KEY_SHIFT) else 8.0
	var pos := cam.global_position + move * speed * real
	# stay within reach of the player and above the ground
	var anchor := Game.player_pos()
	if pos.distance_to(anchor) > 90.0:
		pos = anchor + (pos - anchor).normalized() * 90.0
	pos.y = maxf(pos.y, Game.ground_y(pos.x, pos.z) + 0.3)
	cam.global_transform = Transform3D(b, pos)
	cam.fov = _photo_fov
	if _photo_msg > 0.0:
		_photo_msg = maxf(0.0, _photo_msg - real)
	queue_redraw()

func _draw() -> void:
	if mode != "photo" or _photo_msg < 0.0:
		return
	var s := size
	draw_rect(Rect2(0, s.y - 46.0, s.x, 46.0), Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(24, s.y - 17.0), "PHOTO MODE     WASD move   Q/E down/up   Shift fast   Wheel zoom   Click / Enter take photo   Esc exit",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.93, 0.96))
	if _photo_msg > 0.0:
		draw_string(font, Vector2(0, 60), "Photo saved to user://photos", HORIZONTAL_ALIGNMENT_CENTER, s.x, 20, Color(0.6, 1.0, 0.7))
