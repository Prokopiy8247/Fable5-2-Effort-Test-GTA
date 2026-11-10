extends Node
## JSON persistence in user://marlow_bay_save.json (autoload "SaveGame").

const PATH := "user://marlow_bay_save.json"


func exists() -> bool:
	return FileAccess.file_exists(PATH)


func _look_out(look: Dictionary) -> Dictionary:
	var o := {}
	for k in look:
		o[k] = (look[k] as Color).to_html(false) if look[k] is Color else look[k]
	return o


func _look_in(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		var v = d[k]
		if k in ["skin", "shirt", "pants", "shoes", "hair_color", "hat_color", "jacket_color"] and v is String:
			o[k] = Color(v)
		elif v is float and k in ["sleeves", "shorts"]:
			o[k] = int(v)
		else:
			o[k] = v
	return o


func save_game(silent: bool = false) -> bool:
	var p = Game.player
	if p == null or Game.world == null:
		return false
	var pos: Vector3 = p.global_position
	var last_vehicle := {}
	if p.in_vehicle():
		last_vehicle = p.vehicle.save_state()
		last_vehicle["pos"] = [p.vehicle.global_position.x, p.vehicle.global_position.y, p.vehicle.global_position.z]
		last_vehicle["yaw"] = p.vehicle.global_rotation.y
	var data := {
		"version": 1,
		"pos": [pos.x, pos.y, pos.z], "yaw": p.facing,
		"health": p.health, "armor": p.armor, "money": Game.money,
		"parachute": p.has_parachute, "scuba": p.scuba,
		"inventory": p.inv.save_state(),
		"look": _look_out(p.look),
		"hour": Game.daynight.hour, "weather": Game.daynight.weather,
		"settings": Game.settings, "skills": Game.skills, "stats": Game.stats,
		"garage": Game.world.stored_vehicles,
		"last_vehicle": last_vehicle,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		Game.say("Save failed", Color(1, 0.4, 0.4))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if not silent:
		Game.say("Game saved", Color(0.6, 1.0, 0.6))
		Sfx.ui("buy")
	return true


func load_game() -> bool:
	if not exists() or Game.player == null:
		Game.say("No save file found", Color(1, 0.6, 0.5))
		return false
	var f := FileAccess.open(PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		Game.say("Save file is corrupt", Color(1, 0.4, 0.4))
		return false
	var p = Game.player
	Wanted.clear(true)
	var pos: Array = data.get("pos", [0, 1, 0])
	p.teleport(Vector3(pos[0], pos[1] + 0.3, pos[2]), float(data.get("yaw", 0.0)))
	p.health = clampf(float(data.get("health", 100.0)), 1.0, p.max_health)
	p.armor = float(data.get("armor", 0.0))
	Game.money = int(data.get("money", 0))
	Game.money_changed.emit(Game.money)
	p.inv.load_state(data.get("inventory", {}))
	p.look = _look_in(data.get("look", {}))
	if p.look.is_empty():
		p.look = Data.default_player_look()
	p.rig.queue_free()
	p.rig = CharRig.new()
	p.add_child(p.rig)
	p.rig.setup(p.look, false)
	p.equip(p.inv.current)
	p.has_parachute = bool(data.get("parachute", false))
	p.rig.set_extra("pack", p.has_parachute)
	p.scuba = bool(data.get("scuba", false))
	if p.scuba:
		p.rig.set_extra("tank", true)
		p.rig.set_extra("scuba_mask", true)
	Game.daynight.set_hour(float(data.get("hour", 9.0)))
	Game.daynight.set_weather(String(data.get("weather", "clear")), true)
	var st: Dictionary = data.get("settings", {})
	for k in st:
		if Game.settings.has(k):
			Game.settings[k] = st[k]
	Game.apply_settings()
	var sk: Dictionary = data.get("skills", {})
	for k in sk:
		if Game.skills.has(k):
			Game.skills[k] = float(sk[k])
	var stt: Dictionary = data.get("stats", {})
	for k in stt:
		if Game.stats.has(k):
			Game.stats[k] = stt[k]
	var found := []
	for s in Game.stats.stunts_found:
		found.append(int(s))
	Game.stats.stunts_found = found
	Game.world.stored_vehicles = Array(data.get("garage", []))
	var lv: Dictionary = data.get("last_vehicle", {})
	if not lv.is_empty() and Data.vehicles.has(lv.get("id", "")) and Game.traffic:
		var vp: Array = lv.get("pos", pos)
		var v: Vehicle = Game.traffic.spawn_vehicle(lv.id, Vector3(vp[0], vp[1] + 0.5, vp[2]), float(lv.get("yaw", 0.0)))
		v.load_state(lv)
		v.owner_is_player = true
		p.global_position = v.door_pos(0)
	Game.say("Game loaded", Color(0.6, 1.0, 0.6))
	return true
