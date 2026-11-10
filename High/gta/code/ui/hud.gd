extends CanvasLayer
## UI hub: HUD canvas, minimap, full map, weapon wheel, list menus (shops / pause / phone / benchmark), fades.

var canvas: HudCanvas
var minimap: MiniMap
var bigmap: MiniMap
var bigmap_panel: Control
var menu: GameMenu
var wheel: WeaponWheel
var fade: ColorRect
var _fade_t := -1.0
var _fade_dur := 1.0
var _fade_cb: Callable
var _fade_fired := false
var _map_pick_cb: Callable
var _map_pick := false


func _ready() -> void:
	Game.hud = self
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	canvas = HudCanvas.new()
	add_child(canvas)
	minimap = MiniMap.new()
	minimap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	minimap.position = Vector2(28, -250)
	minimap.offset_left = 28
	minimap.offset_top = -250
	minimap.offset_right = 238
	minimap.offset_bottom = -40
	add_child(minimap)
	bigmap_panel = Control.new()
	bigmap_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bigmap_panel.visible = false
	add_child(bigmap_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bigmap_panel.add_child(dim)
	bigmap = MiniMap.new()
	bigmap.big = true
	bigmap.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bigmap.custom_minimum_size = Vector2(760, 760)
	bigmap.offset_left = -380
	bigmap.offset_right = 380
	bigmap.offset_top = -380
	bigmap.offset_bottom = 380
	bigmap_panel.add_child(bigmap)
	bigmap.map_clicked.connect(_on_map_click)
	var ml := Label.new()
	ml.text = "MARLOW BAY   -   left click: set waypoint / destination    right click: clear    M / Esc: close"
	ml.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	ml.offset_top = 14
	ml.offset_left = -420
	ml.offset_right = 420
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.add_theme_font_size_override("font_size", 17)
	bigmap_panel.add_child(ml)
	wheel = WeaponWheel.new()
	add_child(wheel)
	menu = GameMenu.new()
	add_child(menu)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	Game.toast.connect(func(text, color): canvas.toasts.append({"text": text, "color": color, "t": 4.5}))
	Game.big_text.connect(func(title, sub, color): canvas.banner = {"title": title, "sub": sub, "color": color, "t": 4.5})


# ------------------------------------------------------------------ API used by gameplay
func refresh_weapon() -> void:
	pass


func set_prompt(text: String) -> void:
	canvas.prompt = text


func damage_flash(from_pos: Vector3) -> void:
	canvas.dmg_flash = 1.0
	canvas.dmg_dir = from_pos


func hit_marker(kill: bool) -> void:
	canvas.hit_t = 1.0
	canvas.hit_kill = kill


func set_underwater(on: bool) -> void:
	canvas.underwater = on


func show_vehicle_hint(v) -> void:
	if v == null:
		canvas.hint_t = 0.0
		return
	var h := "WASD drive  -  Space handbrake  -  H horn  -  L lights  -  , . radio  -  RMB+LMB drive-by  -  F exit"
	match v.def.kind:
		"heli":
			h = "W/S pitch  -  A/D yaw  -  Q/E roll  -  Space climb  -  C descend  -  F exit"
		"plane":
			h = "W/S throttle  -  A/D roll  -  Q/E rudder  -  Space pull up  -  C push down  -  F exit"
		"boat":
			h = "W/S throttle  -  A/D steer  -  F exit"
		"bicycle":
			h = "W pedal  -  A/D steer  -  Space brake  -  F exit"
	if v.def.siren:
		h += "  -  G siren"
	canvas.hint = h
	canvas.hint_t = 7.0


func fade_out_in(dur: float, cb: Callable) -> void:
	_fade_t = 0.0
	_fade_dur = dur
	_fade_cb = cb
	_fade_fired = false


func sleep() -> void:
	fade_out_in(1.6, func():
		Game.daynight.hour = fposmod(Game.daynight.hour + 8.0, 24.0)
		Game.player.health = Game.player.max_health
		SaveGame.save_game(true)
		Game.say("You slept 8 hours. Game saved.", Color(0.6, 1.0, 0.6)))


func toggle_photo() -> void:
	if Game.cam == null:
		return
	var on: bool = not Game.cam.photo_mode
	Game.cam.set_photo(on)
	if on:
		Game.ui_stack.append("photo")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Game.ui_close("photo")


func open_big_map(pick: bool = false, cb: Callable = Callable()) -> void:
	_map_pick = pick
	_map_pick_cb = cb
	bigmap_panel.visible = true
	Game.ui_open("map")


func close_big_map() -> void:
	if bigmap_panel.visible:
		bigmap_panel.visible = false
		Game.ui_close("map")


func _on_map_click(pos: Vector3) -> void:
	if _map_pick:
		var cb := _map_pick_cb
		close_big_map()
		if cb.is_valid():
			cb.call(pos)
		return
	Game.waypoint = pos
	Sfx.ui("click")
	Game.say("Waypoint set", Color(0.75, 0.5, 1.0))


func open_shop(kind: String) -> void:
	var p = Game.player
	match kind:
		"gun":
			menu.open("gun", "BRASS & BOLT ARMS", func(): return Shops.gun(menu))
		"mod":
			var v: Vehicle = p.vehicle
			if v:
				v.linear_velocity = Vector3.ZERO
				v.throttle_in = 0.0
			menu.open("mod", "TORQUE HOUSE", func(): return Shops.mod(menu), false, "Custom + Repair")
		"clothes":
			menu.open("clothes", "THREADLINE", func(): return Shops.clothes(menu))
		"wardrobe":
			menu.open("wardrobe", "WARDROBE", func(): return Shops.clothes(menu, true))
		"barber":
			menu.open("barber", "FADE ROOM", func(): return Shops.barber(menu))
		"food":
			menu.open("food", "BITE BOX", func(): return Shops.food(menu))
		"garage":
			menu.open("garage", "GARAGE", func(): return Shops.garage(menu))


func open_admin() -> void:
	menu.open("admin", "BENCHMARK MENU", func(): return Admin.root(menu), false, "Testing tools - not part of normal free roam")


# ------------------------------------------------------------------ input
func _unhandled_input(ev: InputEvent) -> void:
	if Game.cam and Game.cam.photo_mode:
		if ev.is_action_pressed("pause") or ev.is_action_pressed("photo"):
			toggle_photo()
		elif ev.is_action_pressed("skip") or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
			var path := "user://photos/photo_%d.png" % Time.get_unix_time_from_system()
			Game.screenshot(ProjectSettings.globalize_path(path))
			Sfx.ui("click")
		return
	if ev.is_action_pressed("pause"):
		if bigmap_panel.visible:
			close_big_map()
		elif wheel.visible:
			wheel.close(false)
		elif not menu.is_open():
			menu.open("pause", "PAUSED", func(): return Shops.pause(menu), true, "Marlow Bay - free roam sandbox")
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("map"):
		if bigmap_panel.visible:
			close_big_map()
		elif not menu.is_open():
			open_big_map()
	elif ev.is_action_pressed("admin"):
		if menu.is_open() and menu.id == "admin":
			menu.close()
		elif not menu.is_open():
			open_admin()
	elif ev.is_action_pressed("photo") and not menu.is_open():
		toggle_photo()
	elif ev.is_action_pressed("phone") and not menu.is_open() and not bigmap_panel.visible:
		var p = Game.player
		var in_air: bool = p != null and p.in_vehicle() and p.vehicle.is_air()
		if p != null and p.alive() and not (in_air and ev is InputEventKey and ev.physical_keycode == KEY_UP):
			Sfx.play("phone_beep", -6.0)
			menu.open("phone", "PHONE", func(): return Shops.phone(menu), false, "Services - map - camera")


func _process(delta: float) -> void:
	# weapon wheel hold
	var p = Game.player
	if p != null and p.alive():
		var held := Input.is_action_pressed("weapon_wheel")
		if held and not wheel.visible and not menu.is_open() and not bigmap_panel.visible and Game.ui_stack.is_empty():
			wheel.open()
		elif not held and wheel.visible:
			wheel.close(true)
	elif wheel.visible:
		wheel.close(false)
	# fades
	if _fade_t >= 0.0:
		_fade_t += delta / maxf(Engine.time_scale, 0.05)
		var half := _fade_dur * 0.5
		if _fade_t < half:
			fade.color.a = clampf(_fade_t / (half * 0.8), 0.0, 1.0)
		else:
			if not _fade_fired:
				_fade_fired = true
				if _fade_cb.is_valid():
					_fade_cb.call()
			fade.color.a = clampf(1.0 - (_fade_t - half) / half, 0.0, 1.0)
		if _fade_t >= _fade_dur:
			_fade_t = -1.0
			fade.color.a = 0.0
	minimap.visible = canvas.visible
