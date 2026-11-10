extends Node
## Save / load (autoload "SaveSystem"). JSON files in user://saves/. Each gameplay system
## contributes a dictionary through `save_state()` / `load_state(d)`; missing keys are
## tolerated so old saves keep loading as systems evolve.

const DIR := "user://saves/"
const VERSION := 1

var last_error := ""

func slot_path(slot: String) -> String:
	return DIR + slot + ".json"

func has_save(slot := "quick") -> bool:
	return FileAccess.file_exists(slot_path(slot))

func _providers() -> Dictionary:
	# name -> node implementing save_state()/load_state()
	var p := {}
	for key: String in ["player", "time", "weather", "skills", "garage", "wanted", "activities"]:
		var n: Variant = Game.get(key)
		if n != null and is_instance_valid(n) and n.has_method("save_state"):
			p[key] = n
	return p

func save_game(slot := "quick") -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var data := {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"cash": Game.cash,
		"stats": Game.stats,
		"settings": Settings.data,
	}
	var prov := _providers()
	for key in prov.keys():
		data[key] = prov[key].save_state()
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		last_error = "cannot open save file"
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

func load_game(slot := "quick") -> bool:
	if not has_save(slot):
		last_error = "no save in slot " + slot
		return false
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		last_error = "cannot read save file"
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		last_error = "corrupt save file"
		return false
	var data: Dictionary = parsed
	Game.cash = int(data.get("cash", Game.cash))
	var st: Dictionary = data.get("stats", {})
	for k in st.keys():
		if Game.stats.has(k):
			Game.stats[k] = st[k]
	var prov := _providers()
	for key in prov.keys():
		if data.has(key) and typeof(data[key]) == TYPE_DICTIONARY:
			prov[key].load_state(data[key])
	Events.cash_changed.emit(Game.cash, 0)
	Events.game_loaded.emit()
	return true

func delete_save(slot := "quick") -> void:
	if has_save(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))

# --- helpers shared by providers -------------------------------------------
static func v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

static func to_v3(a: Variant, default := Vector3.ZERO) -> Vector3:
	if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return default

static func col(c: Color) -> String:
	return c.to_html(false)
