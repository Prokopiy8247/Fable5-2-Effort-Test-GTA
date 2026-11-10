class_name Shops
extends RefCounted
## Menu builders for every shop and service screen. Pure data -> GameMenu items.


static func _item(text: String, right: String = "", cb: Callable = Callable(), disabled: bool = false) -> Dictionary:
	var d := {"text": text, "right": right, "disabled": disabled}
	if cb.is_valid():
		d["cb"] = cb
	return d


static func _info(text: String, color: Color = Color(0.78, 0.82, 0.88)) -> Dictionary:
	return {"text": text, "info": true, "color": color}


static func _price(n: int) -> String:
	if Game.flags.unlock_all or n <= 0:
		return "FREE"
	return "$%d" % n


# ------------------------------------------------------------------ gun shop
static func gun(menu: GameMenu) -> Array:
	var p = Game.player
	return [
		_info("Cash: $%d" % Game.money, Color(0.6, 1.0, 0.6)),
		_item("Weapons", ">", func(): menu.push("Weapons", func(): return gun_weapons(menu))),
		_item("Ammunition", ">", func(): menu.push("Ammunition", func(): return gun_ammo(menu))),
		_item("Attachments", ">", func(): menu.push("Attachments", func(): return gun_mods(menu), "Modifies the weapon currently in your hands: " + p.inv.def().name)),
		_item("Finishes", ">", func(): menu.push("Finishes", func(): return gun_tints(menu))),
		_item("Body Armour", _price(400), func():
			if p.armor >= 100.0:
				Game.say("Armour already full")
			elif Game.spend(400):
				p.armor = 100.0),
		_item("Parachute", _price(250), func():
			if p.has_parachute:
				Game.say("You already carry a parachute")
			elif Game.spend(250):
				p.give_parachute()),
	]


static func gun_weapons(_menu: GameMenu) -> Array:
	var p = Game.player
	var out := [_info("Cash: $%d" % Game.money, Color(0.6, 1.0, 0.6))]
	for id in Data.weapon_order:
		var d: WeaponDef = Data.weapons[id]
		if id == "fists":
			continue
		var owned: bool = p.inv.has(id)
		var wid: String = id
		out.append(_item("%s  [%s]" % [d.name, Data.SLOT_NAMES[d.slot]], "OWNED" if owned else _price(d.price), func():
			if p.inv.has(wid):
				p.equip(wid)
			elif Game.spend(Data.weapons[wid].price):
				p.inv.give(wid)
				p.equip(wid)))
	return out


static func gun_ammo(_menu: GameMenu) -> Array:
	var p = Game.player
	var out := [_info("Cash: $%d" % Game.money, Color(0.6, 1.0, 0.6))]
	for id in Data.weapon_order:
		var d: WeaponDef = Data.weapons[id]
		if not p.inv.has(id) or d.kind == "melee":
			continue
		var wid: String = id
		out.append(_item("%s  (%d / %d)" % [d.name, p.inv.total_ammo(id), d.max_ammo + p.inv.mag_size(id)], "+%d  %s" % [d.ammo_per_buy(), _price(d.ammo_price)], func():
			var dd: WeaponDef = Data.weapons[wid]
			if p.inv.owned[wid].reserve >= dd.max_ammo:
				Game.say("Ammo full")
			elif Game.spend(dd.ammo_price):
				p.inv.add_ammo(wid, dd.ammo_per_buy())
				if Game.hud:
					Game.hud.refresh_weapon()))
	if out.size() == 1:
		out.append(_info("Buy a firearm first."))
	return out


static func gun_mods(_menu: GameMenu) -> Array:
	var p = Game.player
	var d: WeaponDef = p.inv.def()
	var out := [_info("%s   -   Cash: $%d" % [d.name, Game.money], Color(0.6, 1.0, 0.6))]
	if d.mods.is_empty():
		out.append(_info("This weapon accepts no attachments. Equip another weapon (mouse wheel) and come back."))
		return out
	for m in d.mods:
		var md: Dictionary = Data.WEAPON_MODS[m]
		var has: bool = p.inv.has_mod(m)
		var mid: String = m
		out.append(_item(md.name + "  -  " + md.desc, "FITTED" if has else _price(md.price), func():
			if not p.inv.has_mod(mid) and Game.spend(Data.WEAPON_MODS[mid].price):
				p.inv.add_mod(p.inv.current, mid)
				if mid == "extmag":
					p.inv.entry().mag = p.inv.mag_size()
				p.equip(p.inv.current), has))
	return out


static func gun_tints(_menu: GameMenu) -> Array:
	var p = Game.player
	var out := [_info("Finish for: " + p.inv.def().name)]
	for i in range(Data.WEAPON_TINTS.size()):
		var idx := i
		out.append(_item(Data.WEAPON_TINTS[i][0], "CURRENT" if int(p.inv.entry().tint) == i else _price(100), func():
			if int(p.inv.entry().tint) != idx and Game.spend(100):
				p.inv.entry().tint = idx
				p.equip(p.inv.current)))
	return out


# ------------------------------------------------------------------ mod garage
static func mod(menu: GameMenu) -> Array:
	var v: Vehicle = Game.player.vehicle
	if v == null:
		return [_info("Drive a vehicle into the bay first.")]
	var dmg := v.max_health - v.health
	var flat := false
	for w in v.wheels:
		if w.flat:
			flat = true
	var cost := int(dmg * 0.5) + (150 if v.glass_broken else 0) + (100 if flat else 0)
	var out := [
		_info("%s   -   Cash: $%d" % [v.def.name, Game.money], Color(0.6, 1.0, 0.6)),
		_item("Repair vehicle", _price(cost) if cost > 0 else "PERFECT", func():
			if cost > 0 and Game.spend(cost):
				v.repair()),
	]
	for cat in ["Cosmetic", "Body", "Performance"]:
		var c: String = cat
		out.append(_item(cat, ">", func(): menu.push(c, func(): return mod_cat(menu, c))))
	return out


static func mod_cat(menu: GameMenu, cat: String) -> Array:
	var v: Vehicle = Game.player.vehicle
	if v == null:
		return [_info("No vehicle.")]
	var out := [_info("Cash: $%d" % Game.money, Color(0.6, 1.0, 0.6))]
	for up in Data.UPGRADES:
		if up.cat != cat:
			continue
		if up.has("part") and not v._parts.has(up.part + "_1"):
			continue
		if v.def.kind != "car" and up.id in ["rims", "tint", "roof", "hood", "skirts", "bumper_f", "bumper_r", "spoiler"]:
			continue
		var u: Dictionary = up
		var cur := ""
		match up.kind:
			"paint":
				cur = "colour"
			"choice":
				cur = str(v.mods.get(up.id, up.options[0]))
			"index":
				cur = up.labels[clampi(v.mod(up.id), 0, up.count - 1)]
			"level":
				cur = "Lv %d / %d" % [v.mod(up.id), up.count - 1]
		out.append(_item(up.name, cur + "  >", func(): menu.push(u.name, func(): return mod_options(menu, u), u.get("desc", ""))))
	return out


static func mod_options(_menu: GameMenu, up: Dictionary) -> Array:
	var v: Vehicle = Game.player.vehicle
	if v == null:
		return [_info("No vehicle.")]
	var out := [_info("Cash: $%d" % Game.money, Color(0.6, 1.0, 0.6))]
	match up.kind:
		"paint":
			for pc in Data.PAINTS:
				var col: Color = pc[1]
				var key: String = "paint_color" if up.id == "paint" else "paint2_color"
				var is_cur: bool = (v.paint if up.id == "paint" else v.paint2).is_equal_approx(col)
				var d := _item(pc[0], "CURRENT" if is_cur else _price(up.price), func():
					if Game.spend(up.price):
						v.mods[key] = col
						v.apply_mods())
				d["color"] = col.lightened(0.25)
				out.append(d)
		"choice":
			for o in up.options:
				var opt: String = o
				var is_cur2: bool = str(v.mods.get(up.id, up.options[0])) == o
				out.append(_item(o.capitalize(), "CURRENT" if is_cur2 else _price(up.price), func():
					if Game.spend(up.price):
						v.mods[up.id] = opt
						v.apply_mods()))
		"index", "level":
			for i in range(up.count):
				var idx := i
				var label: String = up.labels[i] if up.has("labels") else ("Stock" if i == 0 else "Level %d" % i)
				var price: int = 0 if i == 0 else up.price * (i if up.kind == "level" else 1)
				var is_cur3: bool = v.mod(up.id) == i
				out.append(_item(label, "FITTED" if is_cur3 else _price(price), func():
					if v.mod(up.id) != idx and Game.spend(price):
						v.mods[up.id] = idx
						v.apply_mods()
						if up.id == "horn":
							v.horn()))
	return out


# ------------------------------------------------------------------ clothing / barber / wardrobe
static func clothes(menu: GameMenu, free: bool = false) -> Array:
	var out := [_info("Cash: $%d" % Game.money, Color(0.6, 1.0, 0.6))]
	for w in Data.WARDROBE:
		var item: Dictionary = w
		out.append(_item(w.name, ">", func(): menu.push(item.name, func(): return clothes_options(item, free))))
	out.append(_item("Switch body type", "male / female", func(): _set_look("gender", "female" if Game.player.look.get("gender", "male") == "male" else "male", 0)))
	return out


static func _set_look(key: String, value, price: int) -> void:
	var p = Game.player
	if price > 0 and not Game.spend(price):
		return
	if key == "gender":
		p.look[key] = value
		p.rig.queue_free()
		p.rig = CharRig.new()
		p.add_child(p.rig)
		p.rig.setup(p.look, false)
		p.equip(p.inv.current)
	else:
		if key == "jacket":
			var ex: Array = p.look.get("extras", [])
			ex.erase("jacket")
			if int(value) == 1:
				ex.append("jacket")
			p.look["extras"] = ex
		else:
			p.look[key] = value
		p.apply_look()
	if p.has_parachute:
		p.rig.set_extra("pack", true)
	Wanted.on_appearance_changed()


static func clothes_options(item: Dictionary, free: bool) -> Array:
	var out := []
	var price: int = 0 if free else item.price
	var p = Game.player
	if item.has("labels"):
		for i in range(item.labels.size()):
			var idx := i
			var key: String = item.id
			var value = idx
			if key == "hat":
				value = Data.HATS[idx]
			elif key == "glasses":
				value = Data.GLASSES[idx]
			var v2 = value
			out.append(_item(item.labels[i], _price(price), func(): _set_look(key, v2, price)))
	else:
		for cc in Data.CLOTH_COLORS:
			var col: Color = cc[1]
			var key2: String = item.id
			var d := _item(cc[0], _price(price), func(): _set_look(key2, col, price))
			d["color"] = col.lightened(0.3)
			out.append(d)
	if out.is_empty():
		out.append(_info("Nothing here."))
	if p == null:
		return out
	return out


static func barber(menu: GameMenu) -> Array:
	return [
		_info("Cash: $%d" % Game.money, Color(0.6, 1.0, 0.6)),
		_item("Hairstyle", ">", func(): menu.push("Hairstyle", func():
			var o := []
			for h in Data.HAIR_STYLES:
				var hs: String = h
				o.append(_item(h.replace("hair_", "").capitalize() if h != "none" else "Shaved", _price(60), func(): _set_look("hair", hs, 60)))
			return o)),
		_item("Hair colour", ">", func(): menu.push("Hair colour", func():
			var o := []
			for hc in Data.HAIR_COLORS:
				var col: Color = hc[1]
				o.append(_item(hc[0], _price(40), func(): _set_look("hair_color", col, 40)))
			return o)),
		_item("Facial hair", ">", func(): menu.push("Facial hair", func():
			var o := []
			for b in Data.BEARDS:
				var bs: String = b
				o.append(_item(b.capitalize() if b != "none" else "Clean shaven", _price(30), func(): _set_look("beard", bs, 30)))
			return o)),
		_item("Skin tone", ">", func(): menu.push("Skin tone", func():
			var o := []
			for i in range(Data.SKIN_TONES.size()):
				var col: Color = Data.SKIN_TONES[i]
				o.append(_item("Tone %d" % (i + 1), "FREE", func(): _set_look("skin", col, 0)))
			return o)),
	]


static func food(_menu: GameMenu) -> Array:
	var p = Game.player
	return [
		_info("Cash: $%d   Health: %d%%" % [Game.money, int(p.health)], Color(0.6, 1.0, 0.6)),
		_item("Snack bar  (+30 health)", _price(10), func():
			if p.health < p.max_health and Game.spend(10):
				p.health = minf(p.max_health, p.health + 30.0)),
		_item("Combo meal  (full health)", _price(30), func():
			if p.health < p.max_health and Game.spend(30):
				p.health = p.max_health),
		_item("Energy drink  (stamina boost)", _price(15), func():
			if Game.spend(15):
				p.stamina = 1.0
				Game.skill_up("stamina", 1.0)),
	]


# ------------------------------------------------------------------ safehouse garage
static func garage(_menu: GameMenu) -> Array:
	var w = Game.world
	var p = Game.player
	var out := [_info("Stored vehicles: %d / 4" % w.stored_vehicles.size())]
	if p.in_vehicle() and p.vehicle.def.price > 0 or (p.in_vehicle() and Game.flags.unlock_all):
		out.append(_item("Store this %s" % p.vehicle.def.name, "", func():
			if w.stored_vehicles.size() >= 4:
				Game.say("Garage full (4 vehicles)")
				return
			var v: Vehicle = p.vehicle
			w.stored_vehicles.append(v.save_state())
			p._leave_vehicle(true)
			v.queue_free()
			Game.say("Vehicle stored", Color(0.6, 1.0, 0.6))
			SaveGame.save_game(true)))
	elif p.in_vehicle():
		out.append(_info("Emergency / service vehicles cannot be stored."))
	for i in range(w.stored_vehicles.size()):
		var idx := i
		var st: Dictionary = w.stored_vehicles[i]
		out.append(_item("Take out %s" % Data.vehicles[st.id].name, "", func():
			if p.in_vehicle():
				Game.say("Leave your current vehicle first")
				return
			var s: Dictionary = w.stored_vehicles[idx]
			w.stored_vehicles.remove_at(idx)
			var v2: Vehicle = Game.traffic.spawn_vehicle(s.id, w.safehouse_garage + Vector3.UP * 0.6, w.garage_yaw)
			v2.load_state(s)
			v2.owner_is_player = true))
	return out


# ------------------------------------------------------------------ phone
static func phone(menu: GameMenu) -> Array:
	var p = Game.player
	return [
		_info("%s   %s   $%d" % [Game.daynight.clock_text(), Game.daynight.weather.capitalize(), Game.money], Color(0.5, 0.95, 0.9)),
		_item("Call a taxi", "", func():
			menu.close()
			Game.world.emergency.call_taxi()),
		_item("Mechanic: deliver a stored vehicle", _price(100), func():
			if Game.world.stored_vehicles.is_empty():
				Game.say("No vehicles in your garage")
			elif Game.spend(100):
				var s: Dictionary = Game.world.stored_vehicles.pop_front()
				var l := City.nearest_lane(p.global_position)
				var v: Vehicle = Game.traffic.spawn_vehicle(s.id, l.pos + Vector3.UP * 0.6, 0.0)
				v.load_state(s)
				v.owner_is_player = true
				Game.say("Your %s was dropped off nearby" % v.def.name, Color(0.6, 1.0, 0.6))
				menu.close()),
		_item("Map / set waypoint", "", func():
			menu.close()
			Game.hud.open_big_map()),
		_item("Camera (photo mode)", "", func():
			menu.close()
			Game.hud.toggle_photo()),
		_item("Quick save", "", func(): SaveGame.save_game()),
		_item("Clear waypoint", "", func(): Game.waypoint = null),
	]


# ------------------------------------------------------------------ pause
static func pause(menu: GameMenu) -> Array:
	return [
		_item("Resume", "", func(): menu.close()),
		_item("Map", "", func():
			menu.close()
			Game.hud.open_big_map()),
		_item("Stats & skills", ">", func(): menu.push("Stats & Skills", func(): return stats())),
		_item("Controls", ">", func(): menu.push("Controls", func(): return controls())),
		_item("Settings", ">", func(): menu.push("Settings", func(): return settings())),
		_item("Save game", "", func(): SaveGame.save_game()),
		_item("Load game", "", func():
			menu.close()
			SaveGame.load_game(), not SaveGame.exists()),
		_item("Benchmark / debug menu  (F1)", "", func():
			menu.close()
			Game.hud.open_admin()),
		_item("Quit to desktop", "", func(): Game.get_tree().quit()),
	]


static func stats() -> Array:
	var out := []
	for k in ["stamina", "shooting", "strength", "stealth", "driving", "flying", "lung"]:
		var v := int(Game.skills[k])
		var bar := ""
		for i in range(20):
			bar += "#" if i < v / 5 else "-"
		out.append(_info("%-10s  [%s]  %d%%" % ["Lung cap." if k == "lung" else k.capitalize(), bar, v]))
	out.append(_info(""))
	out.append(_info("Cash: $%d" % Game.money, Color(0.6, 1.0, 0.6)))
	out.append(_info("NPCs taken down: %d      Vehicles destroyed: %d" % [Game.stats.kills, Game.stats.vehicles_destroyed]))
	out.append(_info("Distance driven: %.1f km" % (float(Game.stats.distance_driven) / 1000.0)))
	out.append(_info("Stunt jumps found: %d / %d" % [Game.stats.stunts_found.size(), Game.world.activities.ramps.size()]))
	out.append(_info("Best range score: %d      Best City Loop: %s" % [Game.stats.best_range_score, Game.world.activities._fmt(float(Game.stats.best_trial))]))
	out.append(_info("Times busted: %d      Times flatlined: %d" % [Game.stats.busted, Game.stats.deaths]))
	return out


static func controls() -> Array:
	var lines := [
		"ON FOOT   WASD move - Shift sprint - Space jump / vault / parachute - C crouch + stealth",
		"          RMB aim (melee: block) - LMB fire / punch (hold = heavy) - R reload - Q take cover",
		"          Aim + Space dodge roll - Tab weapon wheel - 1-8 / wheel switch weapon",
		"          F enter / hijack / exit vehicle - E interact - V first person",
		"COVER     A/D slide along cover - RMB pop out and aim - LMB without aim: blind fire",
		"VEHICLES  WASD drive - Space handbrake - H horn - L lights - G siren - , . radio - B look back - T flip",
		"          RMB + LMB drive-by with pistols / SMG / throwables",
		"HELI      W/S pitch - A/D yaw - Q/E roll - Space up - C down",
		"PLANE     W/S throttle - A/D roll - Q/E rudder - Space / Down pull up - C / Up push down",
		"BOAT      WASD",
		"SWIM      WASD - Space surface - C dive - Shift fast",
		"PARACHUTE Space (while falling) - A/D steer - W dive - S flare",
		"MENUS     M map (click = waypoint) - P / Up phone - Esc pause - F1 benchmark menu",
		"          F5 quick save - F9 quick load - F12 photo mode",
	]
	var out := []
	for l in lines:
		out.append(_info(l))
	return out


static func settings() -> Array:
	var s: Dictionary = Game.settings
	return [
		_item("V-Sync", "ON" if s.vsync else "OFF", func():
			s.vsync = not s.vsync
			Game.apply_settings()),
		_item("FPS cap", str(int(s.max_fps)), func():
			var opts := [30, 60, 90, 120]
			s.max_fps = opts[(opts.find(int(s.max_fps)) + 1) % opts.size()]
			Game.apply_settings()),
		_item("3D render scale", "%d%%" % int(s.render_scale * 100.0), func():
			var opts := [0.6, 0.75, 0.9, 1.0]
			var i := 0
			for k in range(opts.size()):
				if absf(opts[k] - float(s.render_scale)) < 0.01:
					i = k
			s.render_scale = opts[(i + 1) % opts.size()]
			Game.apply_settings()),
		_item("Shadows", "ON" if s.shadows else "OFF", func(): s.shadows = not s.shadows),
		_item("Master volume", "%d%%" % int(s.master_volume * 100.0), func():
			s.master_volume = fmod(float(s.master_volume) + 0.2, 1.2)
			if s.master_volume > 1.01:
				s.master_volume = 0.0
			Game.apply_settings()),
		_item("Mouse sensitivity", "%.1f" % (float(s.mouse_sens) * 1000.0), func():
			s.mouse_sens = float(s.mouse_sens) + 0.0005
			if s.mouse_sens > 0.0051:
				s.mouse_sens = 0.001),
		_item("Invert look Y", "ON" if s.invert_y else "OFF", func(): s.invert_y = not s.invert_y),
		_item("Field of view", str(int(s.fov)), func():
			s.fov = float(s.fov) + 5.0
			if s.fov > 90.0:
				s.fov = 60.0),
	]
