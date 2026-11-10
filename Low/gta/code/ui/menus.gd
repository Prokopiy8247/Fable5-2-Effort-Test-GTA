class_name Menus
extends CanvasLayer
# Container/Theme based menus: shops, mod garage, wardrobe, safehouse, phone, pause,
# and the admin / benchmark menu.

var panel: PanelContainer
var title_lbl: Label
var info_lbl: Label
var list: VBoxContainer
var scroll: ScrollContainer
var current := ""
var free_mods := false
var paused_by_menu := false
var garage: Array = []


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var th := Theme.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.92)
	sb.border_color = Color(0.15, 0.65, 0.75)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	th.set_stylebox("panel", "PanelContainer", sb)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var b := StyleBoxFlat.new()
		b.bg_color = {"normal": Color(0.1, 0.13, 0.18), "hover": Color(0.15, 0.5, 0.6), "pressed": Color(0.1, 0.7, 0.8), "focus": Color(0.12, 0.3, 0.38), "disabled": Color(0.08, 0.09, 0.11)}[st]
		b.set_corner_radius_all(5)
		b.set_content_margin_all(7)
		th.set_stylebox(st, "Button", b)
	th.set_font_size("font_size", "Button", 17)
	th.set_font_size("font_size", "Label", 17)
	th.set_color("font_disabled_color", "Button", Color(0.75, 0.8, 0.85))
	panel = PanelContainer.new()
	panel.theme = th
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(40, 36)
	panel.custom_minimum_size = Vector2(470, 0)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	title_lbl = Label.new()
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	vb.add_child(title_lbl)
	info_lbl = Label.new()
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_lbl.custom_minimum_size = Vector2(440, 0)
	vb.add_child(info_lbl)
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(450, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	panel.visible = false


func blocking() -> bool:
	return panel.visible


func show_menu(title: String, items: Array, info := "") -> void:
	title_lbl.text = title
	info_lbl.text = info
	info_lbl.visible = info != ""
	for c in list.get_children():
		c.queue_free()
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		if it.size() < 2 or it[1] == null:
			b.disabled = true
		else:
			var cb: Callable = it[1]
			b.pressed.connect(func():
				G.audio.ui("click")
				cb.call())
		list.add_child(b)
	panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	panel.visible = false
	current = ""
	if paused_by_menu:
		paused_by_menu = false
		get_tree().paused = false
	if not G.hud.map_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if G.player.passenger_of != null and G.traffic.taxi_state == "waiting":
		G.player.exit_vehicle()


func _input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	match e.physical_keycode:
		KEY_ESCAPE:
			if panel.visible:
				close()
			elif not G.hud.map_open:
				open("pause")
			get_viewport().set_input_as_handled()
		KEY_F1, KEY_QUOTELEFT:
			if current == "admin":
				close()
			else:
				open("admin")
			get_viewport().set_input_as_handled()
		KEY_P, KEY_UP:
			if not panel.visible and not G.player.dead:
				open("phone")
		KEY_F5:
			G.save.save_game()
		KEY_F12:
			G.hud.hidden = not G.hud.hidden
		KEY_F11:
			var fs: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()


func open(mname: String) -> void:
	current = mname
	var p = G.player
	match mname:
		"gunshop": _gunshop()
		"clothes": _clothes()
		"barber": _barber()
		"safehouse": _safehouse()
		"garage": _garage()
		"modshop": _modshop()
		"aircraft": _aircraft()
		"taxi_dest": _taxi_dest()
		"phone": _phone()
		"pause":
			paused_by_menu = true
			get_tree().paused = true
			_pause()
		"admin": _admin()


func back(to: String) -> Array:
	return ["<  Back", func(): open(to)]


# ---------------------------------------------------------------- shops
func buy_snack(price := 15, heal := 30.0) -> void:
	var p = G.player
	if p.health >= p.max_health:
		G.notify("You are not hungry")
		return
	if G.spend(price):
		p.health = min(p.max_health, p.health + heal)
		G.notify("Health restored")


func _gunshop() -> void:
	var p = G.player
	var items: Array = []
	for w in Defs.WEAPON_ORDER:
		var d: Dictionary = Defs.WEAPONS[w]
		if d.price <= 0:
			continue
		if w in p.owned:
			if d.has("mag"):
				items.append(["%s  -  ammo x%d  $%d" % [d.name, d.mag * 2, d.ammo], func():
					if G.spend(d.ammo):
						p.give_weapon(w, d.mag * 2)
					_gunshop()])
			else:
				items.append([d.name + "  (owned)", null])
		else:
			items.append(["Buy %s  $%d" % [d.name, d.price], func():
				if G.spend(d.price):
					p.give_weapon(w)
					p.equip(w)
				_gunshop()])
	items.append(["Body armor  $500", func():
		if p.armor >= 100.0:
			G.notify("Armor already full")
		elif G.spend(500):
			p.armor = 100.0])
	items.append(["Refill all ammo  $600", func():
		if G.spend(600):
			p.collect("ammo", 1)])
	items.append(["Parachute  $250", func():
		if not p.has_parachute and G.spend(250):
			p.set_parachute(true)])
	items.append(["Scuba gear  $900", func():
		if not p.has_scuba and G.spend(900):
			p.collect("scuba", 1)])
	items.append(["Workbench: modify equipped weapon  >", func(): _workbench()])
	items.append(["Close", close])
	show_menu("IRONSIDE ARMS", items, "Cash: $%d" % G.money)


func _workbench() -> void:
	var p = G.player
	var d: Dictionary = p.wdef()
	var items: Array = []
	var allowed: Array = d.get("atts", [])
	for a in allowed:
		var ad: Dictionary = Defs.ATTACHMENTS[a]
		var has: bool = a in p.atts.get(p.weapon, [])
		items.append(["%s %s  -  %s%s" % ["[x]" if has else "[ ]", ad.name, ad.desc, "" if has else "  $%d" % ad.price], func():
			if not p.atts.has(p.weapon):
				p.atts[p.weapon] = []
			if has:
				p.atts[p.weapon].erase(a)
			elif G.spend(ad.price):
				p.atts[p.weapon].append(a)
			p.refresh_weapon_parts()
			_workbench()])
	if d.model != "" and not d.get("melee", false):
		for fn in Defs.FINISHES:
			items.append(["Finish: %s  $150" % fn[0], func():
				if G.spend(150):
					p.finish[p.weapon] = G.col(fn[1])
					p.refresh_weapon_parts()])
	if items.is_empty():
		items.append(["No modifications available for this weapon", null])
	items.append(back("gunshop"))
	show_menu("WORKBENCH", items, "Equipped: %s. Select a firearm with the weapon wheel first." % d.name)


func _color_items(items: Array, label: String, key: String, price: int, after: Callable) -> void:
	var p = G.player
	for c in Defs.CLOTH_COLORS:
		items.append(["%s: %s  $%d" % [label, c[0], price], func():
			if price == 0 or G.spend(price):
				p.look[key] = G.col(c[1])
				p.apply_look()
				if G.wanted:
					G.wanted.changed_clothes()
			after.call()])


func _clothes(free := false) -> void:
	var items: Array = [
		["Shirts / jackets  >", func(): _cloth_sub("Shirt", "shirt", 0 if free else 60, free)],
		["Pants  >", func(): _cloth_sub("Pants", "pants", 0 if free else 50, free)],
		["Shoes  >", func(): _cloth_sub("Shoes", "shoes", 0 if free else 40, free)],
		["Hats  >", func(): _hats(free)],
		["Glasses: toggle  $%d" % (0 if free else 35), func():
			if free or G.spend(35):
				G.player.look["glasses"] = "" if G.player.look.get("glasses", "") != "" else "acc_glasses"
				G.player.apply_look()
				if G.wanted:
					G.wanted.changed_clothes()],
	]
	if free:
		for i in Defs.SKINS.size():
			items.append(["Skin tone %d" % (i + 1), func():
				G.player.look["skin"] = G.col(Defs.SKINS[i])
				G.player.apply_look()])
		items.append(back("safehouse"))
	else:
		items.append(["Close", close])
	show_menu("WARDROBE" if free else "THREADLINE", items, "Cash: $%d" % G.money)


func _cloth_sub(label: String, key: String, price: int, free: bool) -> void:
	var items: Array = []
	_color_items(items, label, key, price, func(): pass)
	items.append(["<  Back", func(): _clothes(free)])
	show_menu(label.to_upper(), items)


func _hats(free: bool) -> void:
	var p = G.player
	var items: Array = [["No hat", func():
		p.look["hat"] = ""
		p.apply_look()]]
	for c in Defs.CLOTH_COLORS:
		items.append(["Cap: %s  $%d" % [c[0], 0 if free else 45], func():
			if free or G.spend(45):
				p.look["hat"] = "acc_cap"
				p.look["hat_color"] = G.col(c[1])
				p.apply_look()
				if G.wanted:
					G.wanted.changed_clothes()])
	items.append(["<  Back", func(): _clothes(free)])
	show_menu("HATS", items)


func _barber() -> void:
	var p = G.player
	var items: Array = []
	for i in Defs.HAIRS.size():
		items.append(["Style: %s  $30" % Defs.HAIR_NAMES[i], func():
			if G.spend(30):
				p.look["hair"] = Defs.HAIRS[i]
				p.apply_look()])
	for c in Defs.HAIR_COLORS:
		items.append(["Color: %s  $25" % c[0], func():
			if G.spend(25):
				p.look["hair_color"] = G.col(c[1])
				p.apply_look()])
	items.append(["Beard: toggle  $20", func():
		if G.spend(20):
			p.look["beard"] = "" if p.look.get("beard", "") != "" else "acc_beard"
			p.apply_look()])
	items.append(["Close", close])
	show_menu("CLIP JOINT", items, "Cash: $%d" % G.money)


func _safehouse() -> void:
	show_menu("SAFEHOUSE", [
		["Save game", func(): G.save.save_game()],
		["Sleep 8 hours (heal + save)", func():
			G.hud.fade()
			G.sky.time = fmod(G.sky.time + 8.0, 24.0)
			G.player.health = G.player.max_health
			G.save.save_game()
			close()],
		["Wardrobe  >", func(): _clothes(true)],
		["Close", close],
	], "Home sweet home. Your respawn and save point.")


func _garage() -> void:
	var p = G.player
	var spot: Vector3 = G.locations["Garage Spot"]
	var items: Array = []
	var near = null
	for v in G.vehicles:
		if not v.wrecked and v.kind in ["car", "bike"] and v.driver == null and v.global_position.distance_to(spot) < 16.0:
			near = v
			break
	if near != null and garage.size() < 4:
		items.append(["Store nearby %s" % near.def.name, func():
			garage.append(near.serialize())
			near.queue_free()
			G.notify("Vehicle stored")
			G.save.save_game()
			close()])
	elif near == null:
		items.append(["Park a car or bike next to the garage to store it", null])
	for i in garage.size():
		var d: Dictionary = garage[i]
		items.append(["Retrieve %s" % Defs.VEHICLES[d.id].name, func():
			var v := Vehicle.deserialize(d)
			G.main.add_child(v)
			v.global_transform = Transform3D(Basis(Vector3.UP, -PI / 2), spot + Vector3.UP * 0.3)
			garage.remove_at(i)
			close()])
	items.append(["Close", close])
	show_menu("GARAGE (%d/4 stored)" % garage.size(), items)


func _aircraft() -> void:
	show_menu("AIRFIELD DESK", [
		["Skylark helicopter (helipad)", func(): spawn_vehicle_at("heli", "Helipad", PI / 2)],
		["Finch 170 propeller plane (runway)", func(): spawn_vehicle_at("plane", "Runway", 0.0)],
		["Arrow jet (runway)", func(): spawn_vehicle_at("jet", "Runway", 0.0)],
		["Close", close],
	], "Free airfield rentals. Aircraft: W/S pitch, A/D roll, Q/E yaw, Shift/Ctrl throttle or lift.")


func spawn_vehicle_at(id: String, loc: String, yaw: float) -> void:
	var pos: Vector3 = G.locations[loc]
	for v in G.vehicles:
		if v.global_position.distance_to(pos) < 7.0 and v.driver == null:
			v.queue_free()
	G.traffic.spawn_vehicle(id, pos, yaw)
	G.notify(Defs.VEHICLES[id].name + " delivered: " + loc)
	close()


func _taxi_dest() -> void:
	var items: Array = []
	if G.waypoint != null:
		items.append(["Map waypoint", func():
			G.traffic.taxi_go(G.waypoint)
			panel.visible = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED])
	for ic in G.map_icons:
		if abs(ic.pos.x + 40.0) < 200.0 and abs(ic.pos.z + 40.0) < 200.0 or ic.label in ["Airport", "Docks", "Beach"]:
			items.append([ic.label, func():
				G.traffic.taxi_go(ic.pos)
				panel.visible = false
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED])
	items.append(["Get out", close])
	show_menu("TAXI: WHERE TO?", items, "Pick a destination. Press ENTER during the ride to skip.")


# ---------------------------------------------------------------- mod garage
func _mod_price(n: int) -> int:
	return 0 if free_mods else n


func _modshop() -> void:
	var p = G.player
	var v = p.vehicle
	if v == null or not v.kind in ["car", "bike"]:
		show_menu("TORQUE WORKS", [["Drive a car or motorcycle into the bay", null], ["Close", close]])
		return
	var cost := _mod_price(int((1.0 - v.health / v.max_health) * 1200.0) + 50)
	var items: Array = [
		["Repair vehicle  $%d" % cost, func():
			if G.spend(cost):
				v.repair()
			_modshop()],
		["Paint: primary  >", func(): _paint(v, true)],
		["Paint: secondary  >", func(): _paint(v, false)],
		["Paint finish  >", func(): _opt(v, "finish", Defs.FINISH_TYPES, 400, "PAINT FINISH")],
		["Wheel color  >", func(): _opt(v, "wheel", Defs.WHEEL_COLORS, 250, "WHEELS")],
		["Window tint  >", func(): _opt(v, "tint", Defs.TINTS, 200, "WINDOW TINT")],
		["Headlight color  >", func(): _opt(v, "lights", Defs.LIGHT_COLORS, 180, "LIGHTS")],
		["Horn  >", func(): _opt(v, "horn", Defs.HORNS, 120, "HORN")],
		["License plate  >", func(): _opt(v, "plate", Defs.PLATES, 80, "PLATE")],
		["Body parts  >", func(): _parts(v)],
		["Performance  >", func(): _perf(v)],
		["Close", close],
	]
	show_menu("TORQUE WORKS", items, "%s   Cash: $%d%s" % [v.def.name, G.money, "   (all mods unlocked)" if free_mods else ""])


func _paint(v, primary: bool) -> void:
	var items: Array = []
	for i in Defs.CAR_COLORS.size():
		items.append(["%s  $%d" % [Defs.PAINT_NAMES[i], _mod_price(300)], func():
			if G.spend(_mod_price(300)):
				if primary:
					v.paint = G.col(Defs.CAR_COLORS[i])
				else:
					v.paint2 = G.col(Defs.CAR_COLORS[i])
				v.apply_mods()])
	items.append(back("modshop"))
	show_menu("PRIMARY PAINT" if primary else "SECONDARY PAINT", items)


func _opt(v, key: String, table: Array, price: int, title: String) -> void:
	var items: Array = []
	for i in table.size():
		items.append(["%s %s  $%d" % ["[x]" if v.mods[key] == i else "[ ]", table[i][0], _mod_price(price)], func():
			if v.mods[key] != i and G.spend(_mod_price(price)):
				v.mods[key] = i
				v.apply_mods()
				if key == "horn":
					v.horn_t = 0.0
					v.horn()
			_opt(v, key, table, price, title)])
	items.append(back("modshop"))
	show_menu(title, items)


func _parts(v) -> void:
	var items: Array = []
	for k in Defs.MOD_PARTS:
		var d: Array = Defs.MOD_PARTS[k]
		var has: bool = k in v.mods.parts
		if G.part(v.model, "mod_" + k) == null:
			continue
		items.append(["%s %s  %s" % ["[x]" if has else "[ ]", d[0], "(remove)" if has else "$%d" % _mod_price(d[1])], func():
			if has:
				v.mods.parts.erase(k)
			elif G.spend(_mod_price(d[1])):
				v.mods.parts.append(k)
			v.apply_mods()
			_parts(v)])
	if items.is_empty():
		items.append(["No body parts available for this vehicle", null])
	items.append(back("modshop"))
	show_menu("BODY PARTS", items)


func _perf(v) -> void:
	var items: Array = []
	for k in Defs.UPGRADES:
		var d: Dictionary = Defs.UPGRADES[k]
		var lvl: int = v.mods[k]
		if lvl >= d.levels:
			items.append(["%s  MAX (%d/%d)  -  %s" % [d.name, lvl, d.levels, d.desc], null])
		else:
			var price := _mod_price(d.price * (lvl + 1))
			items.append(["%s  %d/%d  -  %s  $%d" % [d.name, lvl, d.levels, d.desc, price], func():
				if G.spend(price):
					v.mods[k] = lvl + 1
					v.apply_mods()
				_perf(v)])
	items.append(back("modshop"))
	show_menu("PERFORMANCE", items)


# ---------------------------------------------------------------- phone / pause
func _phone() -> void:
	show_menu("PHONE", [
		["Call a taxi", func():
			G.traffic.call_taxi()
			close()],
		["Quick save", func():
			G.save.save_game()
			close()],
		["Deliver stored vehicle  $100  >", func(): _deliver()],
		["Set GPS waypoint  >", func(): _waypoints()],
		["Radio station  >", func(): _radio()],
		["Photo mode (F12 hides HUD)", func():
			G.cam.photo = not G.cam.photo
			G.hud.hidden = G.cam.photo
			close()],
		["Open map (M)", func():
			close()
			G.hud.map_open = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE],
		["Close", close],
	], "%s   %s" % [G.sky.time_text(), G.district_at(G.player.global_position)])


func _deliver() -> void:
	var items: Array = []
	for i in garage.size():
		var d: Dictionary = garage[i]
		items.append([Defs.VEHICLES[d.id].name, func():
			if G.spend(100):
				var e: Array = G.roads.nearest_edge(G.player.global_position)
				var pos: Vector3 = G.roads.lane_point(e[0], e[1], e[2])
				var v := Vehicle.deserialize(d)
				G.main.add_child(v)
				var dir: Vector3 = G.roads.edge_dir(e[0], e[1])
				v.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), pos + Vector3.UP * 0.4)
				garage.remove_at(i)
				G.notify("Your vehicle was delivered to the nearest road")
			close()])
	if items.is_empty():
		items.append(["No vehicles stored in the safehouse garage", null])
	items.append(back("phone"))
	show_menu("VEHICLE DELIVERY", items)


func _waypoints() -> void:
	var items: Array = [["Clear waypoint", func():
		G.waypoint = null
		close()]]
	for ic in G.map_icons:
		items.append([ic.label, func():
			G.waypoint = ic.pos
			close()])
	items.append(back("phone"))
	show_menu("GPS", items)


func _radio() -> void:
	var items: Array = []
	for i in G.audio.stations.size():
		items.append([G.audio.stations[i], func():
			G.audio.set_station(i)
			close()])
	items.append(back("phone"))
	show_menu("RADIO (plays in vehicles)", items)


func _pause() -> void:
	show_menu("PAUSED", [
		["Resume", close],
		["Status and skills  >", func(): _status()],
		["Controls  >", func(): _controls()],
		["Settings  >", func(): _settings()],
		["Save game", func(): G.save.save_game()],
		["Admin / benchmark menu (F1)  >", func(): _admin()],
		["Quit to desktop", func(): get_tree().quit()],
	], "Free roam. No missions.")


func _settings() -> void:
	var fs: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	show_menu("SETTINGS", [
		["Fullscreen (F11): %s" % ("ON" if fs else "off"), func():
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
			_settings()],
		["<  Back", func(): _pause()],
	], "Display options.")


func _status() -> void:
	var items: Array = []
	for s in Defs.SKILLS:
		var v: float = G.skills[s]
		items.append(["%s   %s  %d%%" % [s.capitalize().rpad(10), "#".repeat(int(v / 5.0)).rpad(20, "."), int(v)], null])
	items.append(["Cash $%d   Best time trial %s   Best stunt %d m" % [G.money, ("%.1fs" % G.activities.best_trial) if G.activities.best_trial > 0.0 else "-", int(G.activities.best_stunt)], null])
	items.append(["<  Back", func(): _pause()])
	show_menu("STATUS", items, "Skills improve by doing the activity: sprinting, shooting, melee, sneaking, driving, flying, diving.")


func _controls() -> void:
	var rows := ["WASD move / drive    Mouse camera    Shift sprint    Alt walk", "Space jump, vault, handbrake, parachute    C crouch / stealth",
		"LMB fire / punch    RMB aim / block    MMB heavy melee    R reload", "Q cover (A/D slide, RMB peek, Shift+A/D round corner)    X dodge roll while aiming",
		"F enter / exit / carjack    E interact    Tab weapon wheel    1-8 slots", "V first person    H horn    L lights    G siren    Z radio",
		"Aircraft: W/S pitch  A/D roll  Q/E yaw  Shift/Ctrl throttle or lift", "Swim: Space up, Ctrl/C dive    P / Up phone    M map    F1 admin    F5 quick save    F11 fullscreen"]
	var items: Array = []
	for r in rows:
		items.append([r, null])
	items.append(["<  Back", func(): _pause()])
	show_menu("CONTROLS", items)


# ---------------------------------------------------------------- admin / benchmark
func _admin() -> void:
	current = "admin"
	show_menu("ADMIN / BENCHMARK", [
		["Teleport  >", func(): _adm_teleport()],
		["Spawn vehicle  >", func(): _adm_vehicles()],
		["Weapons  >", func(): _adm_weapons()],
		["Player  >", func(): _adm_player()],
		["Wanted / police  >", func(): _adm_wanted()],
		["Time of day  >", func(): _adm_time()],
		["Weather  >", func(): _adm_weather()],
		["World toggles  >", func(): _adm_world()],
		["Current vehicle  >", func(): _adm_vehicle()],
		["Activities and services  >", func(): _adm_misc()],
		["Close", close],
	], "Testing tools for rapid demonstration of every system.")


func _adm_teleport() -> void:
	var items: Array = []
	var names: Array = G.locations.keys()
	names.sort()
	for n in names:
		items.append([n, func():
			G.player.warp(G.locations[n])
			close()])
	items.append(back("admin"))
	show_menu("TELEPORT", items)


func admin_spawn(id: String) -> void:
	var p = G.player
	var d: Dictionary = Defs.VEHICLES[id]
	var base: Vector3 = p.global_position if p.vehicle == null else p.vehicle.global_position
	var fwd: Vector3 = Basis(Vector3.UP, G.cam.yaw) * Vector3(0, 0, -1)
	var pos: Vector3 = base + fwd * (6.0 + d.L)
	if d.kind == "boat":
		if G.height(pos.x, pos.z) > G.WATER_Y - 0.6:
			pos = G.locations["Boat Dock"]
			G.notify("Boat spawned at the pier (needs water)")
	else:
		pos.y = max(G.height(pos.x, pos.z), base.y - 0.5) + 0.5
	G.traffic.spawn_vehicle(id, pos, G.cam.yaw)


func _adm_vehicles() -> void:
	var items: Array = []
	for id in Defs.VEHICLES:
		items.append(["%s  (%s)" % [Defs.VEHICLES[id].name, Defs.VEHICLES[id].kind], func():
			admin_spawn(id)
			close()])
	items.append(back("admin"))
	show_menu("SPAWN VEHICLE", items, "Spawns in front of the camera.")


func _adm_weapons() -> void:
	var p = G.player
	var items: Array = [["Give ALL weapons + ammo", func():
		for w in Defs.WEAPON_ORDER:
			p.give_weapon(w, 9999)
		G.notify("All weapons given")],
		["Refill ammo", func(): p.collect("ammo", 1)],
		["All attachments on owned weapons", func():
			for w in p.owned:
				p.atts[w] = Defs.WEAPONS[w].get("atts", []).duplicate()
			p.refresh_weapon_parts()
			G.notify("Attachments unlocked")]]
	for w in Defs.WEAPON_ORDER:
		if w != "fists":
			items.append(["Give " + Defs.WEAPONS[w].name, func():
				p.give_weapon(w, 9999)
				p.equip(w)])
	items.append(back("admin"))
	show_menu("WEAPONS", items)


func _adm_player() -> void:
	var p = G.player
	show_menu("PLAYER", [
		["Money +$10,000", func(): G.add_money(10000)],
		["Money +$100,000", func(): G.add_money(100000)],
		["Set money to $0", func(): G.money = 0],
		["Full health + armor", func():
			p.health = p.max_health
			p.armor = 100.0],
		["Toggle invulnerability (%s)" % ("ON" if G.invulnerable else "off"), func():
			G.invulnerable = not G.invulnerable
			_adm_player()],
		["Give parachute", func(): p.set_parachute(true)],
		["Toggle scuba gear (%s)" % ("ON" if p.has_scuba else "off"), func():
			if p.has_scuba:
				p.has_scuba = false
				p.attach("pack", "", "chest")
			else:
				p.collect("scuba", 1)
			_adm_player()],
		["Refill lung capacity", func(): p.breath = p.max_breath()],
		["Max all skills", func():
			for s in Defs.SKILLS:
				G.skills[s] = 100.0],
		["Reset all skills", func():
			for s in Defs.SKILLS:
				G.skills[s] = 20.0],
		["Wardrobe (free)", func(): _clothes(true)],
		back("admin"),
	])


func _adm_wanted() -> void:
	var items: Array = []
	for n in 6:
		items.append(["Set wanted level: %d star%s" % [n, "" if n == 1 else "s"], func(): G.wanted.set_stars(n)])
	items.append(["Clear wanted level", func(): G.wanted.clear()])
	items.append(["Spawn police cruiser unit", func():
		if G.wanted.stars == 0:
			G.wanted.set_stars(1)
		G.wanted.spawn_unit("police")])
	items.append(["Spawn tactical van unit", func():
		if G.wanted.stars == 0:
			G.wanted.set_stars(1)
		G.wanted.spawn_unit("swat")])
	items.append(["Spawn police officer here", func():
		var n2: NPC = G.pop.spawn("cop", G.player.global_position + Basis(Vector3.UP, G.cam.yaw) * Vector3(0, 0.3, -8))
		n2.ai = "wander"
		n2.route = {"type": "area", "rect": Rect2(n2.global_position.x - 10, n2.global_position.z - 10, 20, 20)}])
	items.append(["Spawn hostile gang member here", func():
		var n3: NPC = G.pop.spawn("gang", G.player.global_position + Basis(Vector3.UP, G.cam.yaw) * Vector3(0, 0.3, -10))
		n3.engage(G.player)])
	items.append(back("admin"))
	show_menu("WANTED / POLICE", items)


func _adm_time() -> void:
	var items: Array = []
	for t in [[6.0, "Sunrise 06:00"], [9.0, "Morning 09:00"], [13.0, "Noon 13:00"], [18.7, "Sunset 18:40"], [22.0, "Night 22:00"], [2.0, "Late night 02:00"]]:
		items.append([t[1], func(): G.sky.time = t[0]])
	items.append(["Time speed: normal (24 min day)", func(): G.sky.time_scale = 1.0 / 60.0])
	items.append(["Time speed: fast (2 min day)", func(): G.sky.time_scale = 0.2])
	items.append(["Freeze time", func(): G.sky.time_scale = 0.0])
	items.append(back("admin"))
	show_menu("TIME OF DAY", items)


func _adm_weather() -> void:
	var items: Array = []
	for w in SkySystem.WEATHERS:
		items.append([w.capitalize(), func():
			G.sky.set_weather(w)
			G.sky.auto_weather = false])
	items.append(["Automatic weather changes", func(): G.sky.auto_weather = true])
	items.append(back("admin"))
	show_menu("WEATHER", items)


func _adm_world() -> void:
	show_menu("WORLD", [
		["Traffic: %s" % ("ON" if G.traffic.enabled else "off"), func():
			G.traffic.enabled = not G.traffic.enabled
			_adm_world()],
		["Pedestrians: %s" % ("ON" if G.pop.enabled else "off"), func():
			G.pop.enabled = not G.pop.enabled
			_adm_world()],
		["Wildlife: %s" % ("ON" if G.pop.wildlife_on else "off"), func():
			G.pop.wildlife_on = not G.pop.wildlife_on
			_adm_world()],
		["Show FPS: %s" % ("ON" if G.show_fps else "off"), func():
			G.show_fps = not G.show_fps
			_adm_world()],
		["Show coordinates / district: %s" % ("ON" if G.show_coords else "off"), func():
			G.show_coords = not G.show_coords
			_adm_world()],
		["Traffic density: low", func(): G.traffic.density = 7],
		["Traffic density: normal", func(): G.traffic.density = 13],
		["Traffic density: high", func(): G.traffic.density = 20],
		["Delete save file", func(): G.save.delete_save()],
		back("admin"),
	])


func _adm_vehicle() -> void:
	var v = G.player.vehicle
	if v == null:
		show_menu("CURRENT VEHICLE", [["Enter a vehicle first", null], back("admin")])
		return
	show_menu("CURRENT VEHICLE", [
		["Repair", func(): v.repair()],
		["Open customization menu here", func(): _modshop()],
		["Unlock all modifications (free): %s" % ("ON" if free_mods else "off"), func():
			free_mods = not free_mods
			_adm_vehicle()],
		["Max performance now", func():
			for k in Defs.UPGRADES:
				v.mods[k] = Defs.UPGRADES[k].levels
			v.apply_mods()
			G.notify("All performance upgrades fitted")],
		["Flip upright", func():
			v.global_transform = Transform3D(Basis(Vector3.UP, v.global_rotation.y), v.global_position + Vector3.UP)
			v.angular_velocity = Vector3.ZERO],
		back("admin"),
	])


func _adm_misc() -> void:
	show_menu("ACTIVITIES / SERVICES", [
		["Call taxi", func():
			G.traffic.call_taxi()
			close()],
		["Start shooting range challenge", func():
			G.player.warp(G.locations["Shooting Range"])
			G.activities.start_range()
			close()],
		["Start street time trial (need a vehicle)", func():
			G.activities.start_trial()
			close()],
		["Dispatch ambulance to me", func(): G.traffic._dispatch("ambulance", G.player.global_position)],
		["Dispatch fire engine to me", func(): G.traffic._dispatch("firetruck", G.player.global_position)],
		back("admin"),
	])
