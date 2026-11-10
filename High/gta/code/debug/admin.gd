class_name Admin
extends RefCounted
## Benchmark / debug menu (F1): rapid access to every implemented system for testing and video capture.


static func _i(text: String, right: String = "", cb: Callable = Callable()) -> Dictionary:
	var d := {"text": text, "right": right}
	if cb.is_valid():
		d["cb"] = cb
	return d


static func _toggle(label: String, flag: String) -> Dictionary:
	return _i(label, "ON" if Game.flags[flag] else "OFF", func(): Game.flags[flag] = not Game.flags[flag])


static func root(menu: GameMenu) -> Array:
	return [
		_i("Teleport", ">", func(): menu.push("Teleport", func(): return teleport(menu))),
		_i("Spawn vehicle", ">", func(): menu.push("Spawn vehicle", func(): return vehicles(menu))),
		_i("Weapons", ">", func(): menu.push("Weapons", func(): return weapons(menu))),
		_i("Player", ">", func(): menu.push("Player", func(): return player(menu))),
		_i("Wanted / police", ">", func(): menu.push("Wanted / police", func(): return wanted(menu))),
		_i("World: time and weather", ">", func(): menu.push("Time and weather", func(): return world(menu))),
		_i("Current vehicle", ">", func(): menu.push("Current vehicle", func(): return vehicle(menu))),
		_i("Toggles and debug", ">", func(): menu.push("Toggles", func(): return toggles(menu))),
	]


static func teleport(menu: GameMenu) -> Array:
	var out := []
	var keys: Array = Game.world.teleports.keys()
	keys.sort()
	for k in keys:
		var name: String = k
		out.append(_i(name, "", func():
			var pos: Vector3 = Game.world.teleports[name]
			Game.player.teleport(pos, float(Game.world.teleport_yaw.get(name, 0.0)))
			menu.close()))
	return out


static func spawn_point() -> Transform3D:
	var p = Game.player
	var yaw: float = Game.cam.yaw if Game.cam else p.facing
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var pos: Vector3 = p.global_position + fwd * 7.0
	var gy := Game.ground_y(pos.x, pos.z)
	pos.y = maxf(gy, Game.WATER_Y) + 0.8
	return Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), pos)


static func spawn(id: String) -> Vehicle:
	var p = Game.player
	if p.in_vehicle():
		p._leave_vehicle(true)
	var t := spawn_point()
	var d: VehicleDef = Data.vehicles[id]
	if d.kind == "boat" and City.terrain_height(t.origin.x, t.origin.z) > Game.WATER_Y - 0.5:
		Game.say("Boats need water - teleporting you to the marina", Color(1, 0.8, 0.5))
		p.teleport(Vector3(60, 0.5, 236))
		t = Transform3D(Basis(Vector3.UP, PI), Vector3(67, Game.WATER_Y + 0.5, 240))
	var v: Vehicle = Game.traffic.spawn_vehicle(id, t.origin, t.basis.get_euler().y)
	v.owner_is_player = true
	return v


static func vehicles(menu: GameMenu) -> Array:
	var out := []
	for id in Data.vehicle_order:
		var d: VehicleDef = Data.vehicles[id]
		var vid: String = id
		out.append(_i("%s  (%s)" % [d.name, id], d.kind, func():
			spawn(vid)
			menu.close()))
	return out


static func weapons(_menu: GameMenu) -> Array:
	var p = Game.player
	var out := [
		_i("Give ALL weapons + full ammo", "", func():
			for id in Data.weapon_order:
				p.inv.give(id)
			p.inv.refill_all()
			Game.say("All weapons given", Color(0.6, 1.0, 0.6))),
		_i("Refill ammo", "", func(): p.inv.refill_all()),
		_i("Fit all attachments to owned weapons", "", func():
			for id in p.inv.owned:
				for m in Data.weapons[id].mods:
					p.inv.add_mod(id, m)
			p.equip(p.inv.current)),
	]
	for id in Data.weapon_order:
		var wid: String = id
		out.append(_i(Data.weapons[id].name, "OWNED" if p.inv.has(id) else "give", func():
			p.inv.give(wid)
			p.inv.add_ammo(wid, 9999)
			p.equip(wid)))
	return out


static func player(_menu: GameMenu) -> Array:
	var p = Game.player
	return [
		_i("Money +$10,000", "$%d" % Game.money, func(): Game.add_money(10000)),
		_i("Money = $1,000,000", "", func(): Game.add_money(1000000 - Game.money)),
		_i("Money = $0", "", func(): Game.add_money(-Game.money)),
		_i("Full health", "%d" % int(p.health), func(): p.health = p.max_health),
		_i("Full armour", "%d" % int(p.armor), func(): p.armor = 100.0),
		_i("Health = 20", "", func(): p.health = 20.0),
		_toggle("Invulnerability", "invuln"),
		_i("Give parachute", "HAVE" if p.has_parachute else "", func(): p.give_parachute()),
		_toggle("Scuba (unlimited-ish air)", "scuba"),
		_i("Refill lungs", "%d%%" % int(p.breath * 100.0), func(): p.breath = 1.0),
		_i("Max all skills", "", func():
			for k in Game.skills:
				Game.skills[k] = 100.0),
		_i("Reset all skills", "", func():
			for k in Game.skills:
				Game.skills[k] = 20.0),
		_i("Call taxi", "", func(): Game.world.emergency.call_taxi()),
		_toggle("Free purchases / unlock all mods", "unlock_all"),
	]


static func wanted(_menu: GameMenu) -> Array:
	var out := [_i("Clear wanted level", "now %d" % Wanted.level, func(): Wanted.clear())]
	for n in range(1, 6):
		var lvl := n
		out.append(_i("Set wanted level %d" % n, "", func(): Wanted.set_level(lvl)))
	out.append(_i("Lock wanted level", "ON" if Wanted.locked else "OFF", func(): Wanted.locked = not Wanted.locked))
	out.append(_i("Wanted system enabled", "ON" if Wanted.enabled else "OFF", func():
		Wanted.enabled = not Wanted.enabled
		if not Wanted.enabled:
			Wanted.clear()))
	out.append(_i("Spawn police cruiser nearby", "", func():
		var v := spawn("police")
		v.set_ai_driver(Data.look_cop(Game.rng))
		v.crew_looks = [Data.look_cop(Game.rng)]
		var ai := DriverAI.new()
		ai.mode = "pursue"
		ai.target = Game.player
		v.ai = ai
		v.owner_is_player = false
		v.set_siren(true)
		Wanted.cars.append(v)))
	out.append(_i("Spawn 2 officers on foot", "", func():
		for k in range(2):
			var t := spawn_point()
			var c := Npc.spawn("cop", t.origin + Vector3(k * 1.5, 0, 0))
			Wanted.cops.append(c)))
	out.append(_i("Spawn tactical team (4)", "", func():
		for k in range(4):
			var t := spawn_point()
			var c := Npc.spawn("swat", t.origin + Vector3(k * 1.2, 0, 0))
			Wanted.cops.append(c)))
	out.append(_i("Spawn police helicopter", "", func(): Wanted.spawn_heli(Game.player)))
	out.append(_i("Spawn hostile gang members (3)", "", func():
		for k in range(3):
			var t := spawn_point()
			var g := Npc.spawn("gang", t.origin + Vector3(k * 1.4, 0, 0))
			g.engage(Game.player)))
	return out


static func world(_menu: GameMenu) -> Array:
	var dn: DayNight = Game.daynight
	var out := [_i("Time now", dn.clock_text())]
	for h in [6.0, 9.0, 12.0, 17.5, 19.5, 22.0, 2.0]:
		var hh: float = h
		out.append(_i("Set time %02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)], "", func(): dn.set_hour(hh)))
	out.append(_i("Advance 1 hour", "", func(): dn.set_hour(dn.hour + 1.0)))
	out.append(_i("Freeze time", "ON" if dn.paused_time else "OFF", func(): dn.paused_time = not dn.paused_time))
	out.append(_i("Fast day cycle (x20)", "ON" if dn.minutes_per_second > 5.0 else "OFF", func(): dn.minutes_per_second = 20.0 if dn.minutes_per_second < 5.0 else 1.0))
	for w in ["clear", "cloudy", "rain", "fog", "storm"]:
		var ww: String = w
		out.append(_i("Weather: " + w.capitalize(), "CURRENT" if dn.weather == w else "", func():
			dn.set_weather(ww, true)
			dn.auto_weather = false))
	out.append(_i("Automatic weather changes", "ON" if dn.auto_weather else "OFF", func(): dn.auto_weather = not dn.auto_weather))
	return out


static func vehicle(menu: GameMenu) -> Array:
	var p = Game.player
	if not p.in_vehicle():
		return [{"text": "Get into a vehicle first.", "info": true}]
	var v: Vehicle = p.vehicle
	return [
		_i("Repair", "%d%%" % int(v.health / v.max_health * 100.0), func(): v.repair()),
		_i("Flip upright", "", func(): v.flip_upright()),
		_i("Open customisation here", ">", func():
			if v.def.kind in ["car", "bike"]:
				menu.push("Torque House (remote)", func(): return Shops.mod(menu))
			else:
				Game.say("Only cars and motorcycles can be customised")),
		_i("Max performance upgrades", "", func():
			for up in Data.UPGRADES:
				if up.cat == "Performance":
					v.mods[up.id] = up.count - 1
			v.apply_mods()
			Game.say("Performance maxed", Color(0.6, 1.0, 0.6))),
		_i("Destroy (explode)", "", func():
			p._leave_vehicle(true)
			v.explode()),
		_i("Set on fire", "", func(): v.health = v.max_health * 0.08),
	]


static func toggles(_menu: GameMenu) -> Array:
	return [
		_toggle("Traffic", "traffic"),
		_toggle("Pedestrians", "peds"),
		_toggle("Wildlife", "wildlife"),
		_toggle("Show FPS", "show_fps"),
		_toggle("Show coordinates / district / counts", "show_coords"),
		_i("Traffic density", "%d%%" % int(Game.traffic.density * 100.0), func(): Game.traffic.density = 0.5 if Game.traffic.density > 1.2 else Game.traffic.density + 0.25),
		_i("Pedestrian density", "%d%%" % int(Game.peds.density * 100.0), func(): Game.peds.density = 0.5 if Game.peds.density > 1.2 else Game.peds.density + 0.25),
		_i("Explosion at crosshair", "", func():
			var pos: Vector3 = Game.cam.aim_point(200.0, [Game.player])
			Fx.explosion(pos, 8.0, 200.0, Game.player)),
		_i("Save game", "", func(): SaveGame.save_game()),
		_i("Load game", "", func(): SaveGame.load_game()),
	]
