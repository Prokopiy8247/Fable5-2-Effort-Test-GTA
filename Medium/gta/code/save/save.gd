extends Node3D
## JSON persistence: player state, inventory, look, skills, clock, garage, settings, records.

const PATH := "user://port_cinder_save.json"
var garage: Array = []


func start() -> void:
	if FileAccess.file_exists(PATH) and not G.autotest:
		load_game.call_deferred()


func _look_out(l: Dictionary) -> Dictionary:
	var o = {}
	for k in l:
		o[k] = ("#" + l[k].to_html()) if l[k] is Color else l[k]
	return o


func _look_in(l: Dictionary) -> Dictionary:
	var o = {}
	for k in l:
		var v = l[k]
		if v is String and v.begins_with("#"):
			o[k] = Color(v.substr(1))
		elif v is float and k in ["skin", "hair_col"]:
			o[k] = int(v)
		else:
			o[k] = v
	return o


func save_game() -> bool:
	var p = G.player
	if p == null or p.state in ["dead", "busted"]:
		return false
	var pos: Vector3 = G.player_pos()
	var d = {
		"version": 1,
		"pos": [pos.x, pos.y, pos.z], "facing": p.facing,
		"health": p.health, "armor": p.armor, "money": G.money,
		"weapons": p.weapons.inv, "current": p.weapons.cur,
		"hour": G.env.hour, "weather": G.env.weather,
		"skills": G.skills.v, "look": _look_out(p.look), "chute": p.has_chute, "scuba": p.scuba,
		"garage": garage, "stats": G.stats, "best": G.extras.best,
		"settings": {"volume": G.audio.volume_master, "sens": G.cam.sens, "traffic": G.traffic.density, "peds": G.pop.max_peds, "day": G.env.day_minutes, "station": G.audio.station},
		"stipend_day": G.menus.last_stipend_day, "day": G.menus._day,
	}
	if p.vehicle and is_instance_valid(p.vehicle):
		d["vehicle"] = p.vehicle.to_dict()
		d["vehicle_yaw"] = p.vehicle.global_rotation.y
	var f = FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		G.notify("Save failed", 3.0)
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	G.notify("Game saved", 2.0)
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(PATH):
		G.notify("No save file found", 2.0)
		return false
	var f = FileAccess.open(PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		G.notify("Save file is corrupt — starting fresh", 3.0)
		return false
	var p = G.player
	if p.state == "vehicle":
		p._exit_vehicle(true)
	if G.wanted:
		G.wanted.clear(false)
	G.money = int(d.get("money", 2500))
	p.health = clamp(float(d.get("health", 100.0)), 10.0, p.max_health)
	p.armor = float(d.get("armor", 0.0))
	p.state = "ground"
	var inv: Dictionary = d.get("weapons", {})
	var clean = {}
	for id in inv:
		if G.player.weapons.Defs.WEAPONS.has(id):
			var e: Dictionary = inv[id]
			clean[id] = {"clip": int(e.get("clip", 0)), "res": int(e.get("res", 0)), "mods": e.get("mods", []), "tint": e.get("tint", "Factory")}
	if not clean.has("fists"):
		clean["fists"] = {"clip": 0, "res": 0, "mods": [], "tint": "Factory"}
	p.weapons.inv = clean
	p.weapons.select(d.get("current", "fists") if clean.has(d.get("current", "fists")) else "fists")
	var sk: Dictionary = d.get("skills", {})
	for k in sk:
		if G.skills.v.has(k):
			G.skills.v[k] = float(sk[k])
	p.has_chute = d.get("chute", false)
	p.scuba = d.get("scuba", false)
	var l: Dictionary = _look_in(d.get("look", {}))
	for k in p.look:
		if not l.has(k):
			l[k] = p.look[k]
	p.look = l
	p.look["pack"] = p.has_chute
	p.look["scuba"] = p.scuba
	p.model.apply_look(p.look)
	garage = d.get("garage", [])
	var stt: Dictionary = d.get("stats", {})
	for k in stt:
		G.stats[k] = int(stt[k])
	G.extras.best = d.get("best", {})
	G.env.set_hour(float(d.get("hour", 9.0)))
	G.env.set_weather(d.get("weather", "clear"), true)
	var s: Dictionary = d.get("settings", {})
	G.audio.volume_master = float(s.get("volume", 0.8))
	AudioServer.set_bus_volume_db(0, linear_to_db(max(0.001, G.audio.volume_master)))
	G.cam.sens = float(s.get("sens", 0.0026))
	G.traffic.density = int(s.get("traffic", 14))
	G.pop.max_peds = int(s.get("peds", 16))
	G.env.day_minutes = float(s.get("day", 24.0))
	G.audio.station = int(s.get("station", 1))
	G.menus.last_stipend_day = int(d.get("stipend_day", -1))
	G.menus._day = int(d.get("day", 0))
	var a: Array = d.get("pos", [0, 1, 0])
	var pos = Vector3(a[0], a[1], a[2])
	if d.has("vehicle") and G.traffic:
		var vd: Dictionary = d.vehicle
		if G.traffic.Defs.VEHICLES.has(vd.get("id", "")):
			var v = G.traffic.create(vd.id, pos + Vector3(3.0, 0.8, 0), float(d.get("vehicle_yaw", 0.0)))
			v.from_dict(vd)
			v.owner_tag = "player"
	p.teleport(pos + Vector3(0, 0.3, 0), float(d.get("facing", 0.0)))
	G.notify("Game loaded", 2.0)
	return true
