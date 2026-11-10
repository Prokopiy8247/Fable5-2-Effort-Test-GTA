extends Node
## Benchmark / admin menu (F1): instant access to every implemented system for testing and recording.
## A testing tool only - it adds no missions or objectives.

var menu: MenuPanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu = MenuPanel.new()
	add_child(menu)


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("admin") and G.player != null:
		if menu.is_open:
			menu.close()
		elif G.ui_blocking == 0:
			open()


func _toggle(flag: String, label: String) -> Dictionary:
	return {"text": label, "right": "ON" if G.flags[flag] else "OFF", "right_color": UIKit.TEAL if G.flags[flag] else UIKit.DIM, "fn": func(): G.flags[flag] = not G.flags[flag]}


func open() -> void:
	var p: Player = G.player
	menu.open("Benchmark Menu", func(m: MenuPanel):
		m.set_items([
			{"text": "Teleport", "right": ">", "fn": _teleport, "no_refresh": true},
			{"text": "Spawn vehicle", "right": ">", "fn": _vehicles, "no_refresh": true},
			{"text": "Weapons", "right": ">", "fn": _weapons, "no_refresh": true},
			{"text": "Player", "right": ">", "fn": _player, "no_refresh": true},
			{"text": "Wanted level / police", "right": ">", "fn": _wanted, "no_refresh": true},
			{"text": "Time & weather", "right": ">", "fn": _world, "no_refresh": true},
			{"text": "Current vehicle", "right": ">", "fn": _vehicle, "no_refresh": true},
			{"text": "Call taxi", "fn": _taxi, "no_refresh": true},
			{"text": "Start shooting range", "fn": _range, "no_refresh": true},
			{"header": "Toggles"},
			_toggle("god", "Invulnerability"),
			_toggle("traffic", "Traffic"),
			_toggle("peds", "Pedestrians"),
			_toggle("wildlife", "Wildlife"),
			_toggle("show_fps", "Show FPS"),
			_toggle("show_coords", "Show coordinates / sector"),
			_toggle("all_mods", "Unlock all vehicle mods"),
		]), {"side": "left", "sub": "%s   -   %s" % [WorldLayout.district_at(p.global_position_now()), G.fmt_money(p.money)]})


func _taxi() -> void:
	menu.close()
	if G.services:
		G.services.call_taxi()


func _range() -> void:
	menu.close()
	var poi: Dictionary = G.world.pois["range"]
	G.player.teleport(poi.pos + Vector3(-1.0, 0.3, 0), -PI * 0.5)
	if not G.player.inv.owned.has("pistol"):
		G.player.inv.give("pistol")
	G.player.equip("pistol")
	if G.main.has_node("Activities"):
		G.main.get_node("Activities").start_range()


func _teleport() -> void:
	menu.open("Teleport", func(m: MenuPanel):
		var items: Array = [{"header": "Districts"}]
		var spots := {"Financial Core": Vector3(44, 0.4, -100), "Civic Square": Vector3(12, 0.4, -42), "Market Street": Vector3(44, 0.4, 70),
			"Lantern Park": Vector3(-44, 0.4, 50), "Maple Flats (residential)": Vector3(-220, 0.4, -40), "Ironworks (industrial)": Vector3(176, 0.3, -40),
			"Harbor Docks": Vector3(170, 0.4, 188), "Coral Beach": Vector3(-120, 0.6, 190), "Bayfront": Vector3(-44, 0.4, 126),
			"Airport runway": Vector3(-40, 0.3, -252), "Airport apron": Vector3(170, 0.3, -192), "Ember Hill summit": WorldLayout.HILL_TOP + Vector3(0, 1.0, 3),
			"Cinder Tower roof": G.world.tower_roof + Vector3(-6, 0.5, -6), "Pier end": Vector3(-40, 0.5, 256), "Hill track start": Vector3(-176, 0.5, -182)}
		for k in spots.keys():
			items.append({"text": k, "fn": _tp.bind(spots[k]), "no_refresh": true})
		items.append({"header": "Locations"})
		for id in G.world.pois.keys():
			var poi: Dictionary = G.world.pois[id]
			items.append({"text": poi.label, "fn": _tp.bind(poi.get("spawn", poi.pos + Vector3(0, 0.4, 1.5))), "no_refresh": true})
		m.set_items(items), {})


func _tp(pos: Vector3) -> void:
	var p: Player = G.player
	var veh := p.vehicle
	if veh != null and veh.kind in ["car", "bike"]:
		veh.linear_velocity = Vector3.ZERO
		veh.angular_velocity = Vector3.ZERO
		veh.global_transform = Transform3D(Basis(Vector3.UP, veh.rotation.y), pos + Vector3(0, 0.6, 0))
	else:
		p.teleport(pos + Vector3(0, 0.2, 0), p.cam.yaw)
	menu.close()


func _vehicles() -> void:
	menu.open("Spawn vehicle", func(m: MenuPanel):
		var items: Array = []
		var heads := {"compact": "Cars", "motorcycle": "Two wheels", "speedboat": "Boats", "helicopter": "Aircraft", "police": "Emergency"}
		for vid in Defs.VEHICLE_ORDER:
			if heads.has(vid):
				items.append({"header": heads[vid]})
			var d: Dictionary = Defs.VEHICLES[vid]
			items.append({"text": d.name, "right": String(d.kind), "right_color": UIKit.DIM, "fn": _spawn.bind(vid, false), "no_refresh": true})
		items.append({"header": "Shortcuts"})
		items.append({"text": "Spawn + sit in: sports car", "fn": _spawn.bind("sports", true), "no_refresh": true})
		items.append({"text": "Spawn + sit in: helicopter", "fn": _spawn.bind("helicopter", true), "no_refresh": true})
		items.append({"text": "Spawn + sit in: airplane (on runway)", "fn": _spawn_runway.bind("plane"), "no_refresh": true})
		items.append({"text": "Spawn + sit in: jet (on runway)", "fn": _spawn_runway.bind("jet"), "no_refresh": true})
		items.append({"text": "Spawn + sit in: speedboat (marina)", "fn": _spawn_boat, "no_refresh": true})
		m.set_items(items), {})


func _spawn(vid: String, sit: bool) -> void:
	var v := VehicleFactory.spawn_near_player(vid)
	menu.close()
	if v == null:
		return
	v.owned = true
	G.say("Spawned %s" % v.def.name, UIKit.GOLD)
	if sit:
		await get_tree().create_timer(0.4).timeout
		G.player.warp_into(v)


func _spawn_runway(vid: String) -> void:
	menu.close()
	var rw: Dictionary = WorldLayout.RUNWAY
	var v := VehicleFactory.spawn(vid, Vector3(float(rw.x0) + 18.0, 0.5, float(rw.z)), -PI * 0.5)
	v.owned = true
	await get_tree().create_timer(0.3).timeout
	G.player.warp_into(v)
	G.player.cam.yaw = -PI * 0.5
	G.say("Shift = throttle, pull up with S around %d km/h" % int(float(v.def.takeoff) * 3.6 * 1.1), UIKit.TEAL)


func _spawn_boat() -> void:
	menu.close()
	var v := VehicleFactory.spawn("speedboat", Vector3(140.0, G.WATER_LEVEL + 0.3, 232.0), PI)
	v.owned = true
	await get_tree().create_timer(0.3).timeout
	G.player.warp_into(v)
	G.player.cam.yaw = PI


func _weapons() -> void:
	var p: Player = G.player
	menu.open("Weapons", func(m: MenuPanel):
		var items: Array = [
			{"text": "Give ALL weapons + full ammo", "fn": func():
				for wid in Defs.WEAPON_ORDER:
					p.inv.give(wid, false)
				p.inv.refill_all()
				G.say("All weapons unlocked", UIKit.GOLD)},
			{"text": "Refill ammo", "fn": func():
				p.inv.refill_all()
				G.say("Ammo refilled", UIKit.GOLD)},
			{"text": "Fit every attachment", "fn": func():
				for wid in p.inv.owned.keys():
					for md in Defs.WEAPONS[wid].get("mods", []):
						p.inv.add_mod(wid, md)
				p.equip(p.inv.current)},
			{"header": "Give"}]
		for wid in Defs.WEAPON_ORDER:
			if wid == "fists":
				continue
			items.append({"text": Defs.WEAPONS[wid].name, "right": "owned" if p.inv.owned.has(wid) else "", "fn": func():
				p.inv.give(wid, true)
				p.equip(wid)})
		m.set_items(items), {})


func _player() -> void:
	var p: Player = G.player
	menu.open("Player", func(m: MenuPanel):
		m.set_items([
			{"text": "Full health + armor", "fn": func():
				p.health = p.max_health
				p.armor = 100.0},
			{"text": "Money +$10,000", "fn": func(): p.add_money(10000)},
			{"text": "Money +$250,000", "fn": func(): p.add_money(250000)},
			{"text": "Money = $0", "fn": func(): p.add_money(-p.money)},
			{"text": "Give parachute", "right": "have" if p.has_parachute else "", "fn": p.give_parachute},
			{"text": "Scuba gear", "right": "ON" if p.has_scuba else "OFF", "fn": func(): p.give_scuba(not p.has_scuba)},
			{"text": "Refill lung capacity", "fn": func(): p.breath = 1.0},
			{"text": "Max all skills", "fn": func():
				for s in Player.SKILLS:
					p.skills[s] = 1.0},
			{"text": "Reset skills", "fn": func():
				for s in Player.SKILLS:
					p.skills[s] = 0.1},
			_toggle("god", "Invulnerability"),
			{"text": "Wardrobe", "right": ">", "fn": func():
				m.close()
				G.main.get_node("Interactions").open_clothes(true), "no_refresh": true},
			{"text": "Respawn at hospital", "fn": func():
				m.close()
				p._respawn("hospital", 0), "no_refresh": true},
		]), {})


func _wanted() -> void:
	menu.open("Wanted level", func(m: MenuPanel):
		var items: Array = []
		for i in 6:
			items.append({"text": ("Clear wanted level" if i == 0 else "Set %d star%s" % [i, "" if i == 1 else "s"]), "right": "current" if G.wanted.level == i else "", "fn": func():
				G.wanted.set_level(i)})
		items.append({"text": "Spawn police cruiser nearby", "fn": func(): G.wanted.spawn_unit_near(40.0)})
		items.append({"text": "Spawn police officer on foot", "fn": func():
			var pos: Vector3 = G.player.global_position_now() + Basis(Vector3.UP, G.cam.yaw) * Vector3(2, 0.3, -9)
			G.peds.spawn("cop", pos)})
		items.append({"text": "Spawn hostile gang member", "fn": func():
			var pos2: Vector3 = G.player.global_position_now() + Basis(Vector3.UP, G.cam.yaw) * Vector3(-2, 0.3, -12)
			G.peds.spawn("gang", pos2).engage(G.player)})
		m.set_items(items), {"sub": "State: %s" % G.wanted.state})


func _world() -> void:
	menu.open("Time & weather", func(m: MenuPanel):
		var items: Array = [{"header": "Time of day  (now %s)" % G.timew.time_string()}]
		for h in [6.0, 9.0, 12.0, 15.0, 17.6, 19.0, 21.0, 0.0, 3.0]:
			items.append({"text": "%02d:%02d" % [int(h), int((h - int(h)) * 60.0)], "fn": func(): G.timew.set_time(h)})
		items.append({"text": "Clock speed", "right": "< %.0fx >" % G.timew.minutes_per_second, "adjust": func(d: int):
			G.timew.minutes_per_second = clampf(G.timew.minutes_per_second + d * (1.0 if G.timew.minutes_per_second < 5.0 else 5.0), 0.0, 60.0)})
		items.append({"header": "Weather"})
		for w in TimeWeather.WEATHER_ORDER:
			items.append({"text": String(w).capitalize(), "right": "current" if G.timew.weather == w else "", "fn": func(): G.timew.set_weather(w, true)})
		items.append({"text": "Automatic weather changes", "right": "ON" if G.timew.auto_weather else "OFF", "fn": func(): G.timew.auto_weather = not G.timew.auto_weather})
		m.set_items(items), {})


func _vehicle() -> void:
	var p: Player = G.player
	menu.open("Current vehicle", func(m: MenuPanel):
		var v := p.vehicle
		if v == null:
			m.set_items([{"text": "Get into a vehicle first", "disabled": true}])
			return
		m.set_items([
			{"text": "Repair", "fn": v.repair},
			{"text": "Open customisation here", "fn": func():
				m.close()
				G.main.get_node("Interactions").open_modshop(true), "no_refresh": true},
			_toggle("all_mods", "Unlock all vehicle mods"),
			{"text": "Flip upright", "fn": func():
				v.global_transform = Transform3D(Basis(Vector3.UP, v.rotation.y), v.global_position + Vector3(0, 1.0, 0))
				v.angular_velocity = Vector3.ZERO},
			{"text": "Random paint", "fn": func(): v.set_paint(Color(Defs.PAINTS[randi() % Defs.PAINTS.size()]))},
			{"text": "Pop all tires", "fn": func(): v.tires_popped = [true, true, true, true]},
			{"text": "Set on fire", "fn": func(): v.take_damage(v.health - v.max_health * 0.08, null, v.global_position, "debug")},
		]), {"sub": ""})
