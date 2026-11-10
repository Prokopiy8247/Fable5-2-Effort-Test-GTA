extends CanvasLayer
## All menus (Control/Container + Theme): pause, map, status, phone, shops, customisation garage, vehicle terminals, benchmark/debug.

const Defs := preload("res://gta/code/core/defs.gd")
const Minimap := preload("res://gta/code/ui/minimap.gd")

var stack: Array = []
var root: Control
var panel: PanelContainer
var title_lbl: Label
var list: VBoxContainer
var desc_lbl: Label
var money_lbl: Label
var scroll: ScrollContainer
var map_open := false
var map_ctl: Control
var map_bg: ColorRect
var map_help: Label
var theme_res: Theme
var unlock_all := false
var spawn_at := Vector3.ZERO
var garage_at := Vector3.ZERO
var last_stipend_day := -1
var _day := 0
var _last_hour := 0.0
var _sleeping := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in [["ui_up", KEY_W], ["ui_down", KEY_S], ["ui_accept", KEY_E], ["ui_cancel", KEY_BACKSPACE]]:
		var ev = InputEventKey.new()
		ev.physical_keycode = a[1]
		InputMap.action_add_event(a[0], ev)
	_make_theme()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme_res
	add_child(root)
	panel = PanelContainer.new()
	panel.anchor_left = 0.04
	panel.anchor_top = 0.08
	panel.anchor_right = 0.04
	panel.anchor_bottom = 0.92
	panel.custom_minimum_size = Vector2(520, 0)
	root.add_child(panel)
	var mg = MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		mg.add_theme_constant_override("margin_" + s, 18)
	panel.add_child(mg)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	mg.add_child(vb)
	var hb = HBoxContainer.new()
	vb.add_child(hb)
	title_lbl = Label.new()
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(title_lbl)
	money_lbl = Label.new()
	money_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.5))
	hb.add_child(money_lbl)
	vb.add_child(HSeparator.new())
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	vb.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	vb.add_child(HSeparator.new())
	desc_lbl = Label.new()
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(0, 64)
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vb.add_child(desc_lbl)
	panel.visible = false
	# full map
	map_bg = ColorRect.new()
	map_bg.color = Color(0.02, 0.04, 0.07, 0.86)
	map_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_bg.visible = false
	root.add_child(map_bg)
	map_ctl = Control.new()
	map_ctl.set_script(Minimap)
	map_ctl.full = true
	map_ctl.anchor_left = 0.2
	map_ctl.anchor_right = 0.8
	map_ctl.anchor_top = 0.06
	map_ctl.anchor_bottom = 0.94
	map_bg.add_child(map_ctl)
	map_help = Label.new()
	map_help.text = "MAP — mouse: move cursor · LMB / ENTER: set waypoint · RMB: clear · M / ESC: close"
	map_help.position = Vector2(30, 14)
	map_bg.add_child(map_help)


func _make_theme() -> void:
	theme_res = Theme.new()
	var pb = StyleBoxFlat.new()
	pb.bg_color = Color(0.06, 0.08, 0.12, 0.93)
	pb.border_color = Color(1.0, 0.75, 0.25, 0.9)
	pb.set_border_width_all(0)
	pb.border_width_left = 4
	pb.set_corner_radius_all(6)
	theme_res.set_stylebox("panel", "PanelContainer", pb)
	for st in [["normal", Color(0.12, 0.15, 0.2, 0.9)], ["hover", Color(0.2, 0.26, 0.34, 0.95)], ["focus", Color(0.95, 0.72, 0.22, 1.0)], ["pressed", Color(1.0, 0.85, 0.4, 1.0)], ["disabled", Color(0.1, 0.1, 0.12, 0.6)]]:
		var sb = StyleBoxFlat.new()
		sb.bg_color = st[1]
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		theme_res.set_stylebox(st[0], "Button", sb)
	theme_res.set_color("font_color", "Button", Color(0.92, 0.94, 0.97))
	theme_res.set_color("font_focus_color", "Button", Color(0.05, 0.05, 0.06))
	theme_res.set_color("font_hover_color", "Button", Color(1, 1, 1))
	theme_res.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.55))
	theme_res.set_font_size("font_size", "Button", 17)
	theme_res.set_font_size("font_size", "Label", 17)


# ------------------------------------------------------------------ page stack
func is_open() -> bool:
	return stack.size() > 0 or map_open or _sleeping > 0.0


## builder: Callable returning Array of {t, r, fn, d, off}
func page(title: String, builder: Callable, pause := false) -> void:
	stack.append({"title": title, "builder": builder, "sel": 0, "pause": pause})
	_render()
	G.audio.play("ui_ok", -10.0)


func refresh() -> void:
	if stack.size() > 0:
		_render()


func back() -> void:
	if stack.size() == 0:
		return
	var p: Dictionary = stack.pop_back()
	if p.has("on_close"):
		p.on_close.call()
	G.audio.play("ui_move", -8.0)
	_render()


func close_all() -> void:
	while stack.size() > 0:
		var p: Dictionary = stack.pop_back()
		if p.has("on_close"):
			p.on_close.call()
	_render()


func _render() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	if stack.is_empty():
		panel.visible = false
		get_tree().paused = false
		if not map_open:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	var p: Dictionary = stack[-1]
	panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = p.pause
	title_lbl.text = p.title
	money_lbl.text = "$%d" % G.money
	desc_lbl.text = ""
	var items: Array = p.builder.call()
	var idx = 0
	var focus_btn: Button = null
	for it in items:
		var b = Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var r: String = it.get("r", "")
		b.text = it.t
		if r != "":
			var rl = Label.new()
			rl.text = r
			rl.set_anchors_preset(Control.PRESET_FULL_RECT)
			rl.offset_right = -12
			rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rl.add_theme_font_size_override("font_size", 15)
			rl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
			b.add_child(rl)
		b.disabled = it.get("off", false)
		b.focus_mode = Control.FOCUS_ALL
		var d: String = it.get("d", "")
		var my = idx
		b.focus_entered.connect(func():
			desc_lbl.text = d
			if stack.size() > 0:
				stack[-1].sel = my)
		b.mouse_entered.connect(func(): if not b.disabled: b.grab_focus())
		if it.has("fn"):
			var fn: Callable = it.fn
			b.pressed.connect(func():
				G.audio.play("ui_move", -8.0)
				fn.call())
		list.add_child(b)
		if idx == p.sel and not b.disabled:
			focus_btn = b
		elif focus_btn == null and not b.disabled and idx >= p.sel:
			focus_btn = b
		idx += 1
	if focus_btn == null and list.get_child_count() > 0:
		focus_btn = list.get_child(0)
	if focus_btn:
		focus_btn.grab_focus.call_deferred()


func _input(ev: InputEvent) -> void:
	if G.player == null:
		return
	if map_open:
		_map_input(ev)
		return
	if stack.size() > 0:
		if ev.is_action_pressed("ui_cancel") or ev.is_action_pressed("pause"):
			back()
			get_viewport().set_input_as_handled()
		elif ev.is_action_pressed("debug") or ev.is_action_pressed("phone") and ev is InputEventKey and ev.physical_keycode == KEY_P:
			close_all()
			get_viewport().set_input_as_handled()
		return
	if G.player.wheel_open:
		return
	if ev.is_action_pressed("pause"):
		open_pause()
	elif ev.is_action_pressed("debug"):
		open_debug()
	elif ev.is_action_pressed("phone"):
		open_phone()
	elif ev.is_action_pressed("map"):
		open_map()
	elif ev.is_action_pressed("status"):
		open_status()
	elif ev.is_action_pressed("quicksave"):
		G.save.save_game()
	elif ev.is_action_pressed("quickload"):
		G.save.load_game()
	elif ev.is_action_pressed("camera"):
		G.cam.first_person = not G.cam.first_person
	if G.cam.photo and (ev.is_action_pressed("interact") or ev.is_action_pressed("enter")):
		G.cam.set_photo(false)
		Engine.time_scale = G.time_scale
	elif G.cam.photo and ev.is_action_pressed("fire"):
		_snap()


func _process(dt: float) -> void:
	if G.env:
		if G.env.hour < _last_hour:
			_day += 1
		_last_hour = G.env.hour
	if stack.size() > 0:
		money_lbl.text = "$%d" % G.money
	if _sleeping > 0.0:
		_sleeping -= dt
		if G.hud:
			G.hud._fade = 1.0
		if _sleeping <= 0.0:
			G.env.set_hour(G.env.hour + 8.0)
			G.player.health = G.player.max_health
			G.save.save_game()
			G.hud.fade_in()
			G.notify("You slept 8 hours. Game saved.", 4.0)


func pay(cost: int) -> bool:
	if unlock_all or cost <= 0:
		G.audio.play("ui_ok", -6.0)
		return true
	if G.money < cost:
		G.audio.play("ui_bad", -4.0)
		G.notify("Not enough cash ($%d needed)" % cost, 2.0)
		return false
	G.add_money(-cost)
	G.audio.play("cash", -8.0)
	return true


func price(c: int) -> String:
	return "FREE" if (unlock_all or c <= 0) else "$%d" % c


# ------------------------------------------------------------------ map
func open_map() -> void:
	map_open = true
	map_bg.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var pp = G.player_pos()
	map_ctl.cursor = Vector2(pp.x, pp.z)
	map_ctl.waypoint = G.hud.minimap.waypoint
	map_ctl.route_pts = G.hud.minimap.route_pts


func close_map() -> void:
	map_open = false
	map_bg.visible = false
	if stack.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var w: Vector3 = map_ctl.map_to_world(ev.position - map_ctl.global_position)
		map_ctl.cursor = Vector2(clamp(w.x, -380.0, 380.0), clamp(w.z, -380.0, 380.0))
	elif (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or ev.is_action_pressed("skip"):
		var wp = Vector3(map_ctl.cursor.x, 0, map_ctl.cursor.y)
		G.hud.minimap.set_waypoint(wp)
		map_ctl.waypoint = wp
		G.audio.play("ui_ok", -6.0)
		G.notify("Waypoint set", 1.5)
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		G.hud.minimap.set_waypoint(null)
		map_ctl.waypoint = null
		map_ctl.route_pts = PackedVector3Array()
	elif ev.is_action_pressed("map") or ev.is_action_pressed("pause") or ev.is_action_pressed("ui_cancel"):
		close_map()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ pause / status / phone
func open_pause() -> void:
	page("PORT CINDER — PAUSED", func():
		return [
			{"t": "Resume", "fn": func(): close_all()},
			{"t": "Map", "fn": func(): close_all(); open_map()},
			{"t": "Status & skills", "fn": func(): open_status()},
			{"t": "Controls", "fn": func(): open_controls()},
			{"t": "Settings", "fn": func(): open_settings()},
			{"t": "Save game", "fn": func(): G.save.save_game(); close_all()},
			{"t": "Load game", "fn": func(): close_all(); G.save.load_game()},
			{"t": "Benchmark / debug menu (F1)", "fn": func(): close_all(); open_debug()},
			{"t": "Quit to desktop", "fn": func(): get_tree().quit()},
		], true)


func open_status() -> void:
	page("STATUS", func():
		var out = []
		for k in G.skills.NAMES:
			var v: float = G.skills.level(k)
			out.append({"t": "%-14s %s" % [G.skills.NAMES[k], "█".repeat(int(v * 20.0)) + "░".repeat(20 - int(v * 20.0))], "r": "%d%%" % int(v * 100.0), "d": "Improves by use."})
		out.append({"t": "Cash", "r": "$%d" % G.money})
		out.append({"t": "Kills", "r": str(G.stats.kills)})
		out.append({"t": "Vehicles stolen", "r": str(G.stats.cars_stolen)})
		out.append({"t": "Times busted / wasted", "r": "%d / %d" % [G.stats.busted, G.stats.wasted]})
		out.append({"t": "Stunt jumps", "r": str(G.stats.stunts)})
		for k in G.extras.best:
			out.append({"t": "Best — " + k, "r": "%.1f" % float(G.extras.best[k])})
		return out, true)


func open_controls() -> void:
	var rows = [["Move / drive", "W A S D"], ["Camera / aim", "Mouse, RMB aim"], ["Sprint", "Shift"], ["Jump / climb / handbrake", "Space"], ["Crouch", "C"], ["Stealth mode", "Ctrl"],
		["Cover (attach / leave)", "Q  (Shift+A/D rounds a corner)"], ["Enter / exit vehicle, hijack", "F"], ["Interact", "E"], ["Fire / melee", "LMB"], ["Heavy melee / kick", "X or RMB+LMB"],
		["Block (melee)", "Alt"], ["Reload", "R"], ["Weapon wheel", "Tab (hold)"], ["Weapon class", "1-8, mouse wheel"], ["Quick grenade", "G"], ["Dodge roll", "Space while aiming + moving"],
		["Phone", "P / Up"], ["Map", "M"], ["Status", "I"], ["Camera 1st/3rd person", "V"], ["Horn", "H"], ["Siren", "J"], ["Headlights", "L"], ["Radio station", "N"],
		["Flip vehicle", "B"], ["Look back", "Z"], ["Helicopter", "Space up, Ctrl down, W/S pitch, A/D yaw, Q/E roll"],
		["Airplane", "Shift/Ctrl throttle, S pull up, W nose down, A/D roll, Q/E rudder, Space brake"], ["Parachute", "Space in free fall; A/D steer, S flare"],
		["Dive / surface", "Ctrl / Space"], ["Quick save / load", "F5 / F9"], ["Debug menu", "F1"], ["Pause", "Esc"]]
	page("CONTROLS", func():
		var out = []
		for r in rows:
			out.append({"t": r[0], "r": r[1]})
		return out, true)


func open_settings() -> void:
	page("SETTINGS", func():
		return [
			{"t": "Master volume", "r": "%d%%" % int(G.audio.volume_master * 100.0), "fn": func(): G.audio.volume_master = fposmod(G.audio.volume_master + 0.1, 1.05); AudioServer.set_bus_volume_db(0, linear_to_db(max(0.001, G.audio.volume_master))); refresh()},
			{"t": "Mouse sensitivity", "r": "%.1f" % (G.cam.sens * 1000.0), "fn": func(): G.cam.sens = 0.001 + fposmod(G.cam.sens - 0.001 + 0.0004, 0.004); refresh()},
			{"t": "Traffic density", "r": str(G.traffic.density), "fn": func(): G.traffic.density = 6 + (G.traffic.density - 6 + 4) % 20; refresh()},
			{"t": "Pedestrian density", "r": str(G.pop.max_peds), "fn": func(): G.pop.max_peds = 6 + (G.pop.max_peds - 6 + 4) % 24; refresh()},
			{"t": "Day length (real minutes)", "r": str(int(G.env.day_minutes)), "fn": func(): G.env.day_minutes = 12.0 if G.env.day_minutes >= 48.0 else G.env.day_minutes * 2.0; refresh()},
			{"t": "Dynamic weather", "r": "On" if G.env.auto_weather else "Off", "fn": func(): G.env.auto_weather = not G.env.auto_weather; refresh()},
			{"t": "Fullscreen", "r": "On" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else "Off", "fn": func():
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
				refresh()},
		], true)


func open_phone() -> void:
	page("PHONE — CinderOS", func():
		var out = [
			{"t": "Call Cinder Cab", "d": "A taxi drives to you. Get in with F and pick a destination.", "fn": func(): close_all(); G.extras.call_taxi()},
			{"t": "Map / set waypoint", "fn": func(): close_all(); open_map()},
			{"t": "Camera (photo mode)", "d": "Free camera: WASD + mouse, Space/Ctrl up/down, LMB saves a photo, E exits.", "fn": func(): close_all(); G.cam.set_photo(true); Engine.time_scale = 0.05},
			{"t": "Quick save", "fn": func(): G.save.save_game(); close_all()},
			{"t": "Mechanic: deliver a stored vehicle", "r": "$150", "d": "Brings one of your garage vehicles to the nearest road.", "fn": func(): _deliver_menu()},
			{"t": "Radio: next station", "r": G.audio.STATIONS[G.audio.station], "fn": func(): G.audio.next_station(); refresh()},
			{"t": "Status & skills", "fn": func(): open_status()},
		]
		if G.hud.minimap.waypoint != null:
			out.append({"t": "Clear waypoint", "fn": func(): G.hud.minimap.set_waypoint(null); refresh()})
		return out)


func _snap() -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/photos")
	var path = "user://photos/photo_%d.png" % int(Time.get_unix_time_from_system())
	img.save_png(path)
	G.audio.play("ui_ok")
	print("[photo] saved ", ProjectSettings.globalize_path(path))


func _deliver_menu() -> void:
	page("DELIVER VEHICLE", func():
		var out = []
		for i in G.save.garage.size():
			var d: Dictionary = G.save.garage[i]
			out.append({"t": Defs.VEHICLES[d.id].name, "r": price(150), "fn": func():
				if pay(150):
					var nl: Dictionary = G.traffic.nearest_lane(G.player_pos())
					var l: Dictionary = G.traffic.lanes[nl.lane]
					var v = G.traffic.create(d.id, nl.pos + l.dir.cross(Vector3.UP) * 2.6 + Vector3(0, 0.6, 0), atan2(-l.dir.x, -l.dir.z))
					v.from_dict(d)
					v.owner_tag = "player"
					G.save.garage.remove_at(i)
					close_all()
					G.notify("Your %s was delivered to the kerb" % v.def.name, 3.0)})
		if out.is_empty():
			out.append({"t": "No stored vehicles — use the home garage first", "off": true})
		return out)


func sleep() -> void:
	if G.wanted.stars > 0:
		G.notify("You can't sleep while wanted", 2.0)
		return
	_sleeping = 1.6


func quick_buy(what: String) -> void:
	if what == "soda" and pay(5):
		G.player.health = min(G.player.max_health, G.player.health + 15.0)
		G.audio.play("heal", -8.0)


# ------------------------------------------------------------------ shops
func open_shop(kind: String) -> void:
	match kind:
		"guns": _shop_guns()
		"clothes": _shop_clothes(false)
		"wardrobe": _shop_clothes(true)
		"barber": _shop_barber()
		"accessories": _shop_accessories()
		"police": _shop_police()
		"atm": _shop_atm()
		_: _shop_items(kind)


func _shop_items(kind: String) -> void:
	var titles = {"food": "PITA STOP", "market": "24/7 MARKET", "hospital": "ST. EMBER MEDICAL", "gas": "SUNBELT FUEL"}
	page(titles.get(kind, kind.to_upper()), func():
		var out = []
		for it in Defs.SHOP_ITEMS.get(kind, []):
			out.append({"t": it[0], "r": price(it[1]), "fn": func(): _buy_item(it)})
		return out)


func _buy_item(it: Array) -> void:
	var p = G.player
	match it[2]:
		"heal":
			if p.health >= p.max_health:
				G.notify("Already at full health", 1.5)
				return
			if pay(it[1]):
				p.health = min(p.max_health, p.health + it[3])
				G.audio.play("heal", -6.0)
		"chute":
			if p.has_chute:
				G.notify("You already carry a parachute", 1.5)
			elif pay(it[1]):
				p.give_chute()
		"scuba":
			if p.scuba:
				G.notify("You already own scuba gear", 1.5)
			elif pay(it[1]):
				p.set_scuba(true)
		"tires":
			if p.vehicle and pay(it[1]):
				for w in p.vehicle.wheels:
					w.flat = false
				G.audio.play("repair")
		"repair":
			if p.vehicle and pay(it[1]):
				p.vehicle.repair(false, it[3])
				G.audio.play("repair")
	refresh()


func _shop_guns() -> void:
	page("BRASS TACK ARMS", func():
		var w = G.player.weapons
		var out = [{"t": "Body armour", "r": price(300), "d": "Absorbs most bullet and blast damage until depleted.", "fn": func():
			if G.player.armor >= 100.0:
				G.notify("Armour already full", 1.5)
			elif pay(300):
				G.player.armor = 100.0
			refresh()}]
		for id in Defs.WEAPON_ORDER:
			var d: Dictionary = Defs.WEAPONS[id]
			if id == "fists":
				continue
			if not w.has(id):
				out.append({"t": "Buy " + d.name, "r": price(d.price), "d": "%s · damage %d · %s" % [d.cls.capitalize(), d.dmg, ("mag %d" % d.clip) if d.has("clip") else "melee"], "fn": func():
					if pay(d.price):
						w.give(id)
						G.player.select_weapon(id)
					refresh()})
			else:
				if d.has("clip"):
					out.append({"t": "%s — ammo x%d" % [d.name, d.clip * 2 if d.cls != "thrown" else 3], "r": price(d.ammo), "d": "Owned. Reserve %d / %d" % [w.inv[id].res, d.max], "fn": func():
						if w.inv[id].res >= d.max:
							G.notify("Ammo full", 1.5)
						elif pay(d.ammo):
							w.give(id, d.clip * 2 if d.cls != "thrown" else 3)
						refresh()})
				if d.get("mods", []).size() > 0 or d.has("clip") and d.cls != "thrown":
					out.append({"t": "   Workbench: customise " + d.name, "r": ">", "fn": func(): _weapon_bench(id)})
		return out)


func _weapon_bench(id: String) -> void:
	page("WORKBENCH — " + Defs.WEAPONS[id].name, func():
		var w = G.player.weapons
		var d: Dictionary = Defs.WEAPONS[id]
		var out = []
		for m in d.get("mods", []):
			var mi: Dictionary = Defs.MOD_INFO[m]
			var has: bool = w.inv[id].mods.has(m)
			out.append({"t": mi.name, "r": "INSTALLED" if has else price(mi.price), "d": mi.desc, "off": has, "fn": func():
				if pay(mi.price):
					w.add_mod(id, m)
					if m == "ExtMag":
						w.inv[id].clip = w.clip_size(id)
					G.player.select_weapon(id)
				refresh()})
		for t in Defs.TINTS:
			var cur: bool = w.inv[id].get("tint", "Factory") == t
			out.append({"t": "Finish: " + t, "r": "APPLIED" if cur else price(150), "off": cur, "fn": func():
				if pay(150):
					w.inv[id].tint = t
					G.player.select_weapon(id)
				refresh()})
		return out)


func _cycle_color(key: String, cost: int) -> void:
	if not pay(cost):
		return
	var cols: Array = Defs.CLOTH_COLORS.values()
	var l: Dictionary = G.player.look
	var cur: Color = l.get(key, cols[0])
	var i = 0
	for k in cols.size():
		if cols[k].is_equal_approx(cur):
			i = k
	l[key] = cols[(i + 1) % cols.size()]
	G.player.set_look(l)
	refresh()


func _color_name(c: Color) -> String:
	for k in Defs.CLOTH_COLORS:
		if Defs.CLOTH_COLORS[k].is_equal_approx(c):
			return k
	return "Custom"


func _toggle(key: String, cost: int) -> void:
	if not pay(cost):
		return
	var l: Dictionary = G.player.look
	l[key] = not l.get(key, false)
	G.player.set_look(l)
	refresh()


func _shop_clothes(free: bool) -> void:
	var c = 0 if free else 40
	page("WARDROBE" if free else "THREAD COUNT", func():
		var l: Dictionary = G.player.look
		return [
			{"t": "Shirt / jacket colour", "r": "%s  (%s)" % [_color_name(l.shirt), price(c)], "fn": func(): _cycle_color("shirt", c)},
			{"t": "Jacket", "r": ("On" if l.jacket else "Off") + "  (%s)" % price(c * 2), "fn": func(): _toggle("jacket", c * 2)},
			{"t": "Long sleeves", "r": "On" if l.long_sleeve else "Off", "fn": func(): _toggle("long_sleeve", c / 2)},
			{"t": "Trousers colour", "r": "%s  (%s)" % [_color_name(l.pants), price(c)], "fn": func(): _cycle_color("pants", c)},
			{"t": "Shorts", "r": "On" if l.shorts else "Off", "fn": func(): _toggle("shorts", c / 2)},
			{"t": "Shoes", "r": price(c), "fn": func():
				if pay(c):
					var opts = [Color(0.92, 0.92, 0.9), Color(0.08, 0.08, 0.08), Color(0.4, 0.25, 0.15), Color(0.7, 0.14, 0.12), Color(0.12, 0.17, 0.33)]
					var i = 0
					for k in opts.size():
						if opts[k].is_equal_approx(l.shoes):
							i = k
					l.shoes = opts[(i + 1) % opts.size()]
					G.player.set_look(l)
					refresh()},
			{"t": "Hat", "r": "%s  (%s)" % [l.hat, price(c)], "fn": func():
				if pay(c):
					l.hat = Defs.HATS[(Defs.HATS.find(l.hat) + 1) % Defs.HATS.size()]
					G.player.set_look(l)
					refresh()},
			{"t": "Hat colour", "r": _color_name(l.hat_col), "fn": func(): _cycle_color("hat_col", c / 2)},
			{"t": "Glasses", "r": "On" if l.glasses else "Off", "fn": func(): _toggle("glasses", c)},
			{"t": "Body type", "r": "Feminine" if l.female else "Masculine", "fn": func(): _toggle("female", 0)},
			{"t": "Skin tone", "r": str(int(l.skin) + 1), "fn": func(): l.skin = (int(l.skin) + 1) % 5; G.player.set_look(l); refresh()},
		])


func _shop_barber() -> void:
	page("CLIP JOINT", func():
		var l: Dictionary = G.player.look
		return [
			{"t": "Hair style", "r": "%s  (%s)" % [String(l.hair).replace("Hair_", ""), price(30)], "fn": func():
				if pay(30):
					l.hair = Defs.HAIR_STYLES[(Defs.HAIR_STYLES.find(l.hair) + 1) % Defs.HAIR_STYLES.size()]
					G.player.set_look(l)
					refresh()},
			{"t": "Hair colour", "r": price(25), "fn": func():
				if pay(25):
					l.hair_col = (int(l.hair_col) + 1) % 6
					G.player.set_look(l)
					refresh()},
			{"t": "Beard", "r": ("On" if l.beard else "Off") + "  (%s)" % price(20), "fn": func(): _toggle("beard", 20)},
		])


func _shop_accessories() -> void:
	page("INK HARBOR — ACCESSORIES", func():
		var l: Dictionary = G.player.look
		return [
			{"t": "Glasses", "r": ("On" if l.glasses else "Off") + "  (%s)" % price(60), "fn": func(): _toggle("glasses", 60)},
			{"t": "Hat", "r": "%s  (%s)" % [l.hat, price(50)], "fn": func():
				if pay(50):
					l.hat = Defs.HATS[(Defs.HATS.find(l.hat) + 1) % Defs.HATS.size()]
					G.player.set_look(l)
					refresh()},
			{"t": "Hat colour", "r": _color_name(l.hat_col), "fn": func(): _cycle_color("hat_col", 20)},
		])


func _shop_police() -> void:
	page("POLICE FRONT DESK", func():
		var s: int = G.wanted.stars
		var out = []
		if s == 0:
			out.append({"t": "Your record is clean", "off": true})
		elif s <= 2 and G.wanted.state == "search":
			var fine = 400 * s
			out.append({"t": "Pay fine and clear wanted level", "r": price(fine), "fn": func():
				if pay(fine):
					G.wanted.clear(false)
					G.notify("Fine paid — record cleared", 3.0)
				refresh()})
		else:
			out.append({"t": "Officers will not negotiate right now", "off": true})
		return out)


func _shop_atm() -> void:
	page("CINDER TRUST ATM", func():
		var got = last_stipend_day == _day
		return [
			{"t": "Balance", "r": "$%d" % G.money, "off": true},
			{"t": "Collect daily investment dividend", "r": "CLAIMED" if got else "+$750", "off": got, "d": "A free-roam income source: once per in-game day.", "fn": func():
				last_stipend_day = _day
				G.add_money(750)
				refresh()},
		])


# ------------------------------------------------------------------ vehicle customisation
func open_mods() -> void:
	var v = G.player.vehicle
	if v == null or v.kind not in ["car", "bike"]:
		G.notify("Drive a car or motorcycle into the bay", 2.5)
		return
	v.linear_velocity = Vector3.ZERO
	page("TORQUE BAY", func():
		var dmg: float = 1.0 - v.health / v.max_health
		var flat = false
		for w in v.wheels:
			flat = flat or w.flat
		var rc = int(dmg * 900.0) + (120 if flat else 0)
		var out = [
			{"t": "Repair vehicle", "r": price(rc) if rc > 0 else "No damage", "off": rc <= 0, "d": "Restores body health, tyres, glass and handling.", "fn": func():
				if pay(rc):
					v.repair(true)
					G.audio.play("repair")
				refresh()},
			{"t": "Primary paint", "r": ">", "fn": func(): _paint_menu(v, false)},
			{"t": "Secondary paint / trim", "r": ">", "fn": func(): _paint_menu(v, true)},
			{"t": "Paint finish", "r": v.finish, "d": "Gloss, matte, metallic or chrome ($400).", "fn": func():
				if pay(400):
					var ks: Array = Defs.FINISHES.keys()
					v.set_paint(v.paint, null, ks[(ks.find(v.finish) + 1) % ks.size()])
					G.audio.play("spray")
				refresh()},
			{"t": "Wheel colour", "r": ">", "fn": func(): _rim_menu(v)},
		]
		for cat in Defs.UPGRADES:
			if v.kind == "bike" and cat in ["spoiler", "skirts", "hood", "bumper", "wheels", "tint", "stripe", "armor"]:
				continue
			if cat == "stripe":
				continue
			var cur: String = v.upgrades.get(cat, Defs.UPGRADES[cat][0][0])
			var label = ""
			for o in Defs.UPGRADES[cat]:
				if o[0] == cur:
					label = o[1]
			out.append({"t": cat.capitalize(), "r": label, "fn": func(): _upgrade_menu(v, cat)})
		return out)


func _paint_menu(v, secondary: bool) -> void:
	page("PAINT — " + ("SECONDARY" if secondary else "PRIMARY"), func():
		var out = []
		for n in Defs.PAINTS:
			var c: Color = Defs.PAINTS[n]
			out.append({"t": n, "r": price(350), "fn": func():
				if pay(350):
					if secondary:
						v.set_paint(v.paint, c)
					else:
						v.set_paint(c)
					G.audio.play("spray")})
		return out)


func _rim_menu(v) -> void:
	page("WHEEL COLOUR", func():
		var out = []
		for n in ["Pearl White", "Jet Black", "Gunmetal", "Signal Red", "Sunburst", "Bronze", "Teal"]:
			var c: Color = Defs.PAINTS[n]
			out.append({"t": n, "r": price(200), "fn": func():
				if pay(200):
					v.rim_col = c
					v.mats["Rim"].albedo_color = c
					G.audio.play("spray")})
		return out)


func _upgrade_menu(v, cat: String) -> void:
	page(cat.to_upper(), func():
		var out = []
		var cur: String = v.upgrades.get(cat, Defs.UPGRADES[cat][0][0])
		for o in Defs.UPGRADES[cat]:
			var is_cur: bool = o[0] == cur
			var desc = ""
			for k in o[3]:
				if k in ["engine", "top", "brake", "grip", "sus"]:
					desc += "%s x%.2f  " % [k, o[3][k]]
				elif k == "armor":
					desc += "damage taken x%.2f  " % o[3][k]
				elif k == "bp_tires":
					desc += "bullet-resistant tyres  "
				elif k == "down":
					desc += "downforce +%.1f  " % o[3][k]
			out.append({"t": o[1], "r": "INSTALLED" if is_cur else price(o[2]), "off": is_cur, "d": desc, "fn": func():
				if pay(o[2]):
					v.upgrades[cat] = o[0]
					v.apply_upgrades()
					G.audio.play("repair")
				refresh()})
		return out)


# ------------------------------------------------------------------ garage / terminals / taxi
func open_garage(at: Vector3) -> void:
	garage_at = at
	page("HOME GARAGE", func():
		var out = []
		var v = G.player.vehicle
		if v and v.def.cat == "land" and v.def.get("price", 0) >= 0:
			out.append({"t": "Store this %s" % v.def.name, "off": G.save.garage.size() >= 6, "d": "Stored vehicles persist in your save (max 6).", "fn": func():
				G.save.garage.append(v.to_dict())
				G.player._exit_vehicle(true)
				v.queue_free()
				G.notify("Vehicle stored", 2.0)
				G.save.save_game()
				refresh()})
		for i in G.save.garage.size():
			var d: Dictionary = G.save.garage[i]
			out.append({"t": "Retrieve " + Defs.VEHICLES[d.id].name, "fn": func():
				var nv = G.traffic.create(d.id, garage_at + Vector3(0, 0.6, 0), PI)
				nv.from_dict(d)
				nv.owner_tag = "player"
				G.save.garage.remove_at(i)
				close_all()})
		if out.is_empty():
			out.append({"t": "Drive a land vehicle here to store it", "off": true})
		return out)


func open_spawner(cat: String, at: Vector3) -> void:
	spawn_at = at
	page("VEHICLE TERMINAL", func():
		var out = []
		for id in Defs.VEHICLES:
			var d: Dictionary = Defs.VEHICLES[id]
			if cat != "all" and d.cat != cat:
				continue
			out.append({"t": d.name, "r": d.cat, "fn": func(): _spawn_vehicle(id, spawn_at)})
		return out)


func _spawn_vehicle(id: String, at: Vector3):
	for o in get_tree().get_nodes_in_group("vehicles"):
		if o.global_position.distance_to(at) < 5.0 and o.driver == null:
			o.queue_free()
	var yaw: float = G.player.facing
	var v = G.traffic.create(id, at + Vector3(0, 0.7, 0), yaw)
	v.owner_tag = "player"
	G.notify("%s ready" % v.def.name, 2.0)
	close_all()
	return v


func open_taxi() -> void:
	page("CINDER CAB — WHERE TO?", func():
		var out = []
		if G.hud.minimap.waypoint != null:
			out.append({"t": "My map waypoint", "fn": func(): var wp: Vector3 = G.hud.minimap.waypoint; close_all(); G.extras.taxi_go(wp)})
		for n in ["Safehouse", "Downtown", "Gun Shop", "Clothing Store", "Hospital", "Police Station", "Torque Bay", "Airfield", "Marina", "Beach", "Docks", "Gas Station", "Shooting Range", "Larkspur", "Ironside"]:
			if G.world.locations.has(n):
				var p: Vector3 = G.world.locations[n]
				out.append({"t": n, "r": "~$%d" % int(clamp(G.player_pos().distance_to(p) * 0.12 + 5, 5, 120)), "fn": func(): close_all(); G.extras.taxi_go(p)})
		return out)
	stack[-1]["on_close"] = func():
		if G.extras.taxi_state == "choose":
			G.extras.taxi_cancel()


# ------------------------------------------------------------------ benchmark / debug menu
func open_debug() -> void:
	page("BENCHMARK MENU", func():
		var p = G.player
		return [
			{"t": "Teleport…", "r": ">", "fn": func(): _dbg_teleport()},
			{"t": "Spawn vehicle…", "r": ">", "d": "Any land, water or air vehicle appears in front of you.", "fn": func(): _dbg_spawn()},
			{"t": "Weapons…", "r": ">", "fn": func(): _dbg_weapons()},
			{"t": "Wanted level…", "r": "%d★" % G.wanted.stars, "fn": func(): _dbg_wanted()},
			{"t": "Time of day…", "r": G.env.time_string(), "fn": func(): _dbg_time()},
			{"t": "Weather…", "r": G.env.weather, "fn": func(): _dbg_weather()},
			{"t": "Money +$10,000", "fn": func(): G.add_money(10000); refresh()},
			{"t": "Set money to $1,000,000", "fn": func(): G.money = 1000000; refresh()},
			{"t": "Full health + armour", "fn": func(): p.health = p.max_health; p.armor = 100.0; G.audio.play("heal")},
			{"t": "Invulnerability", "r": _on(G.cheats.god), "fn": func(): G.cheats.god = not G.cheats.god; refresh()},
			{"t": "Repair current vehicle", "off": p.vehicle == null, "fn": func(): p.vehicle.repair(true); G.audio.play("repair")},
			{"t": "Open vehicle customisation here", "off": p.vehicle == null, "fn": func(): close_all(); open_mods()},
			{"t": "Unlock all shop / mod options (free)", "r": _on(unlock_all), "fn": func(): unlock_all = not unlock_all; refresh()},
			{"t": "Give parachute", "r": _on(p.has_chute), "fn": func(): p.give_chute(); refresh()},
			{"t": "Scuba gear", "r": _on(p.scuba), "fn": func(): p.set_scuba(not p.scuba); refresh()},
			{"t": "Refill lung capacity", "fn": func(): p.breath = 1.0},
			{"t": "Max all character skills", "fn": func(): G.skills.set_all(1.0)},
			{"t": "Reset character skills", "fn": func(): G.skills.set_all(0.2)},
			{"t": "Call taxi", "fn": func(): close_all(); G.extras.call_taxi()},
			{"t": "Traffic", "r": _on(G.traffic.enabled), "fn": func():
				G.traffic.enabled = not G.traffic.enabled
				if not G.traffic.enabled:
					for v in G.traffic.ai_list.duplicate():
						if is_instance_valid(v) and v.owner_tag == "traffic":
							v.queue_free()
				refresh()},
			{"t": "Pedestrians", "r": _on(G.pop.enabled), "fn": func(): G.pop.set_enabled(not G.pop.enabled); refresh()},
			{"t": "Wildlife", "r": _on(G.pop.wildlife_enabled), "fn": func(): G.pop.wildlife_enabled = not G.pop.wildlife_enabled; refresh()},
			{"t": "Show FPS", "r": _on(G.cheats.fps), "fn": func(): G.cheats.fps = not G.cheats.fps; refresh()},
			{"t": "Show coordinates / district", "r": _on(G.cheats.coords), "fn": func(): G.cheats.coords = not G.cheats.coords; refresh()},
			{"t": "Start activity…", "r": ">", "fn": func(): _dbg_activity()},
			{"t": "Explosion at crosshair", "fn": func(): G.fx.explode(G.cam.aim_point(120.0), 8.0, 250.0, p)},
		])


func _on(b: bool) -> String:
	return "ON" if b else "off"


func _dbg_teleport() -> void:
	page("TELEPORT", func():
		var out = []
		var names: Array = G.world.locations.keys()
		names.sort()
		for n in names:
			var pos: Vector3 = G.world.locations[n]
			out.append({"t": n, "r": G.world.district(pos), "fn": func(): G.player.teleport(pos + Vector3(0, 0.4, 0)); close_all()})
		if G.hud.minimap.waypoint != null:
			out.push_front({"t": "Map waypoint", "fn": func():
				var wp: Vector3 = G.hud.minimap.waypoint
				G.player.teleport(Vector3(wp.x, G.ground_y(wp.x, wp.z) + 0.5, wp.z))
				close_all()})
		return out)


func _dbg_spawn() -> void:
	page("SPAWN VEHICLE", func():
		var out = []
		for id in Defs.VEHICLES:
			var d: Dictionary = Defs.VEHICLES[id]
			out.append({"t": d.name, "r": d.cat, "fn": func():
				var p = G.player
				var fwd: Vector3 = -Basis(Vector3.UP, G.cam.yaw).z
				var at: Vector3 = G.player_pos() + fwd * (9.0 if d.cat != "air" else 14.0)
				if d.cat == "water":
					at.y = G.WATER_Y + 0.3
				else:
					at.y = G.ground_y(at.x, at.z, G.player_pos().y + 6.0)
				_spawn_vehicle(id, at)})
		return out)


func _dbg_weapons() -> void:
	page("WEAPONS", func():
		var w = G.player.weapons
		var out = [
			{"t": "Give ALL weapons + full ammo", "fn": func():
				for id in Defs.WEAPON_ORDER:
					w.give(id, 9999)
				G.audio.play("pickup")
				refresh()},
			{"t": "Refill all ammo", "fn": func():
				for id in w.inv:
					if Defs.WEAPONS[id].has("clip"):
						w.give(id, 9999)
				G.audio.play("pickup")},
			{"t": "Install every attachment on owned weapons", "fn": func():
				for id in w.inv:
					for m in Defs.WEAPONS[id].get("mods", []):
						w.add_mod(id, m)
				G.audio.play("pickup")},
		]
		for id in Defs.WEAPON_ORDER:
			if id == "fists":
				continue
			out.append({"t": Defs.WEAPONS[id].name, "r": "owned" if w.has(id) else "give", "fn": func(): w.give(id, 9999); G.player.select_weapon(id); refresh()})
		return out)


func _dbg_wanted() -> void:
	page("WANTED LEVEL", func():
		var out = []
		for i in 6:
			out.append({"t": "Set %d star%s" % [i, "" if i == 1 else "s"], "fn": func(): G.wanted.set_stars(i); refresh()})
		out.append({"t": "Clear wanted level", "fn": func(): G.wanted.clear(false); refresh()})
		out.append({"t": "Spawn police cruiser unit", "fn": func(): G.wanted.last_known = G.player_pos(); G.wanted._spawn_unit("police", 2)})
		out.append({"t": "Spawn tactical unit", "fn": func(): G.wanted.last_known = G.player_pos(); G.wanted._spawn_unit("swat", 4)})
		out.append({"t": "Spawn foot officer nearby", "fn": func():
			var c = G.pop.spawn_ped(G.player.global_position + Vector3(6, 0.3, 6), {}, "cop")
			c.set_meta("dispatched", true)})
		out.append({"t": "State", "r": "%s  seen=%s  escape %d%%" % [G.wanted.state, str(G.wanted.seen), int(G.wanted.escape_progress() * 100.0)], "off": true})
		return out)


func _dbg_time() -> void:
	page("TIME OF DAY", func():
		var out = []
		for h in [0, 3, 6, 8, 10, 12, 15, 18, 19.5, 21, 23]:
			out.append({"t": "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60)], "fn": func(): G.env.set_hour(h); refresh()})
		out.append({"t": "Freeze clock", "r": _on(G.env.paused_clock), "fn": func(): G.env.paused_clock = not G.env.paused_clock; refresh()})
		return out)


func _dbg_weather() -> void:
	page("WEATHER", func():
		var out = []
		for w in G.env.WEATHERS:
			out.append({"t": w.capitalize(), "fn": func(): G.env.auto_weather = false; G.env.set_weather(w, true); refresh()})
		out.append({"t": "Dynamic weather", "r": _on(G.env.auto_weather), "fn": func(): G.env.auto_weather = not G.env.auto_weather; refresh()})
		return out)


func _dbg_activity() -> void:
	page("ACTIVITIES", func():
		return [
			{"t": "Go to shooting range", "fn": func(): G.player.teleport(G.world.locations["Shooting Range"] + Vector3(0, 0.4, 6)); close_all()},
			{"t": "Go to time trial start", "fn": func(): G.player.teleport(Vector3(-6, 0.5, 30)); close_all()},
			{"t": "Go to boat race start", "fn": func(): G.player.teleport(Vector3(60, G.WATER_Y + 1.0, 268)); close_all()},
			{"t": "Go to Spire roof (parachute jump)", "fn": func(): G.player.give_chute(); G.player.teleport(G.world.locations["Spire Roof"] + Vector3(0, 0.4, 0)); close_all()},
			{"t": "Go to wreck dive site", "fn": func(): G.player.set_scuba(true); G.player.teleport(G.world.locations["Wreck Dive"]); close_all()},
			{"t": "Abort current activity", "fn": func(): G.extras.end_activity("Activity aborted")},
		])
