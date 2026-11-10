extends Node
## Save - JSON persistence of the free-roam state (autoload). F5 quick save, F9 quick load,
## sleeping in the safehouse also saves. Dynamic world objects are simply regenerated.

const PATH := "user://cinderbay_save.json"
const SETTINGS_PATH := "user://cinderbay_settings.json"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()


func _unhandled_input(ev: InputEvent) -> void:
	if G.player == null or G.test_mode != "":
		return
	if ev.is_action_pressed("quicksave"):
		if save_game():
			G.say("Game saved", Color(0.6, 1.0, 0.6))
	elif ev.is_action_pressed("quickload"):
		if load_game():
			G.say("Game loaded", Color(0.6, 1.0, 0.6))


func _look_out(lk: Dictionary) -> Dictionary:
	var o := {}
	for k in lk.keys():
		o[k] = ("#" + (lk[k] as Color).to_html()) if lk[k] is Color else lk[k]
	return o


func _look_in(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d.keys():
		var v = d[k]
		o[k] = Color(v.substr(1)) if (v is String and v.begins_with("#") and v.length() >= 7) else v
	return o


func save_game() -> bool:
	var p: Player = G.player
	if p == null or p.dead:
		return false
	var pos := p.global_position_now()
	var data := {
		"version": 1,
		"pos": [pos.x, pos.y, pos.z], "yaw": p.face_yaw,
		"health": p.health, "armor": p.armor, "money": p.money,
		"look": _look_out(p.look), "inv": p.inv.to_dict(), "skills": p.skills, "stats": p.stats,
		"parachute": p.has_parachute, "scuba": p.has_scuba,
		"time": G.timew.time if G.timew else 9.0, "weather": G.timew.weather if G.timew else "clear",
		"garage": [], "last_vehicle": null, "radio": Sfx.get("station") if Sfx.get("station") != null else 0,
	}
	if G.main.has_node("Interactions"):
		data.garage = G.main.get_node("Interactions").garage
	var lv: Vehicle = p.vehicle if p.vehicle != null else p.last_vehicle
	if lv != null and is_instance_valid(lv) and not lv.dead:
		var st := lv.export_state()
		st["pos"] = [lv.global_position.x, lv.global_position.y, lv.global_position.z]
		st["yaw"] = lv.rotation.y
		st["inside"] = p.vehicle == lv
		data.last_vehicle = st
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	save_settings()
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var txt := FileAccess.get_file_as_string(PATH)
	var data = JSON.parse_string(txt)
	if not (data is Dictionary):
		push_warning("Save file is corrupt - starting fresh")
		return false
	var p: Player = G.player
	if p == null:
		return false
	var pos: Array = data.get("pos", [0, 1, 0])
	p.teleport(Vector3(float(pos[0]), float(pos[1]) + 0.3, float(pos[2])), float(data.get("yaw", 0.0)))
	p.health = clampf(float(data.get("health", 100.0)), 10.0, p.max_health)
	p.armor = float(data.get("armor", 0.0))
	p.money = int(data.get("money", 3000))
	var lk := _look_in(data.get("look", {}))
	if not lk.is_empty():
		var sex_changed: bool = lk.get("sex", "m") != p.look.get("sex", "m")
		p.look = lk
		if sex_changed and G.main.has_node("Interactions"):
			G.main.get_node("Interactions")._rebuild_player_visual()
	p.inv.from_dict(data.get("inv", {}))
	for k in data.get("skills", {}).keys():
		if p.skills.has(k):
			p.skills[k] = float(data.skills[k])
	for k in data.get("stats", {}).keys():
		p.stats[k] = data.stats[k]
	p.has_parachute = bool(data.get("parachute", false))
	p.has_scuba = bool(data.get("scuba", false))
	p.apply_look()
	p.hidden_look_change = 0.0
	if G.timew:
		G.timew.set_time(float(data.get("time", 9.0)))
		G.timew.set_weather(String(data.get("weather", "clear")), true)
	if G.main.has_node("Interactions"):
		var g: Array = []
		for st in data.get("garage", []):
			if st is Dictionary and Defs.VEHICLES.has(st.get("vid", "")):
				g.append(st)
		G.main.get_node("Interactions").garage = g
	if Sfx.get("station") != null:
		Sfx.set("station", int(data.get("radio", 0)))
	var lv = data.get("last_vehicle")
	if lv is Dictionary and Defs.VEHICLES.has(lv.get("vid", "")):
		var vp: Array = lv.get("pos", [0, 1, 0])
		var v := VehicleFactory.spawn(String(lv.vid), Vector3(float(vp[0]), float(vp[1]) + 0.4, float(vp[2])), float(lv.get("yaw", 0.0)))
		v.import_state(lv)
		v.owned = true
		p.last_vehicle = v
		if lv.get("inside", false):
			p.warp_into(v)
	if G.wanted:
		G.wanted.clear()
	return true


func autoload_game() -> void:
	if FileAccess.file_exists(PATH):
		await get_tree().process_frame
		if load_game():
			G.say("Welcome back to Cinder Bay  (save loaded)", Color(0.6, 1.0, 0.6))


func delete_save() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(G.settings))


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if d is Dictionary:
		for k in d.keys():
			if G.settings.has(k):
				G.settings[k] = d[k]
