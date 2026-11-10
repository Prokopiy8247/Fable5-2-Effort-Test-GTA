class_name SaveSystem
extends Node
# JSON persistence in user://: player state, inventory, appearance, skills, time, garage, settings.

const PATH := "user://fable52_gta_low_save.json"


func _c(c: Color) -> Array:
	return [c.r, c.g, c.b]


func save_game() -> void:
	var p = G.player
	var look := {}
	for k in p.look:
		look[k] = _c(p.look[k]) if p.look[k] is Color else p.look[k]
	var fin := {}
	for k in p.finish:
		fin[k] = _c(p.finish[k])
	var pos: Vector3 = p.global_position
	var d := {
		"version": 1,
		"pos": [pos.x, pos.y, pos.z], "yaw": p.rotation.y,
		"health": p.health, "armor": p.armor, "money": G.money,
		"owned": p.owned, "clip": p.clip, "reserve": p.reserve, "atts": p.atts, "finish": fin, "weapon": p.weapon,
		"parachute": p.has_parachute, "scuba": p.has_scuba,
		"look": look, "skills": G.skills,
		"time": G.sky.time, "weather": G.sky.weather,
		"garage": G.menus.garage,
		"settings": {"station": G.audio.station, "first_person": G.cam.first_person, "show_fps": G.show_fps},
		"best_trial": G.activities.best_trial, "best_stunt": G.activities.best_stunt, "best_range": G.activities.best_range,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		G.notify("Save failed")
		return
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	G.notify("Game saved")


func delete_save() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	G.notify("Save file deleted")


func load_game() -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return false
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return false
	var p = G.player
	var pos: Array = d.get("pos", [])
	if pos.size() == 3:
		var v := Vector3(pos[0], pos[1], pos[2])
		if v.y < G.WATER_Y - 0.5 or abs(v.x) > 320.0 or abs(v.z) > 340.0:
			v = G.locations["Safehouse"]
		p.global_position = v + Vector3.UP * 0.3
	p.rotation.y = d.get("yaw", 0.0)
	p.health = clamp(d.get("health", 100.0), 20.0, 100.0)
	p.armor = d.get("armor", 0.0)
	G.money = int(d.get("money", 2500))
	for w in d.get("owned", []):
		if Defs.WEAPONS.has(w) and not w in p.owned:
			p.owned.append(w)
	for k in d.get("clip", {}):
		p.clip[k] = int(d.clip[k])
	for k in d.get("reserve", {}):
		p.reserve[k] = int(d.reserve[k])
	for k in d.get("atts", {}):
		p.atts[k] = d.atts[k]
	for k in d.get("finish", {}):
		p.finish[k] = G.col(d.finish[k])
	var lk: Dictionary = d.get("look", {})
	for k in lk:
		p.look[k] = G.col(lk[k]) if lk[k] is Array else lk[k]
	p.apply_look()
	if d.get("parachute", false):
		p.set_parachute(true)
	if d.get("scuba", false):
		p.collect("scuba", 1)
	var w2: String = d.get("weapon", "fists")
	if w2 in p.owned:
		p.equip(w2)
	for s in d.get("skills", {}):
		if G.skills.has(s):
			G.skills[s] = float(d.skills[s])
	G.sky.time = d.get("time", 9.5)
	G.sky.weather = d.get("weather", "clear")
	G.menus.garage = d.get("garage", [])
	var st: Dictionary = d.get("settings", {})
	G.audio.set_station(int(st.get("station", 0)))
	G.cam.first_person = st.get("first_person", false)
	G.show_fps = st.get("show_fps", false)
	G.activities.best_trial = d.get("best_trial", 0.0)
	G.activities.best_stunt = d.get("best_stunt", 0.0)
	G.activities.best_range = d.get("best_range", 0)
	return true
