class_name Inventory
extends RefCounted
## Weapons owned by one character: ammo in magazine / reserve, attachments, finish.

signal changed()

var owner_is_player := false
var items: Dictionary = {&"unarmed": {"mag": 0, "reserve": 0, "atts": [], "tint": 0}}
var current: StringName = &"unarmed"
var has_parachute := false
var has_scuba := false

func has(id: StringName) -> bool:
	return items.has(id)

func give(id: StringName, ammo := -1, quiet := false) -> void:
	var w := WeaponDB.get_w(id)
	if not items.has(id):
		items[id] = {"mag": mag_size(id) if WeaponDB.is_gun(id) else 0, "reserve": 0, "atts": [], "tint": 0}
		if w["cls"] == &"thrown":
			items[id]["reserve"] = 0
	if ammo < 0:
		ammo = int(w.get("mag", 0)) * 3 if WeaponDB.is_gun(id) else (3 if w["cls"] == &"thrown" else 0)
	add_ammo(id, ammo)
	if not quiet:
		changed.emit()

func remove(id: StringName) -> void:
	if id == &"unarmed":
		return
	items.erase(id)
	if current == id:
		current = &"unarmed"
	changed.emit()

func add_ammo(id: StringName, amount: int) -> void:
	if not items.has(id):
		return
	var w := WeaponDB.get_w(id)
	var cap := int(w.get("reserve", 0))
	items[id]["reserve"] = mini(cap, int(items[id]["reserve"]) + amount)

func refill_all() -> void:
	for id in items.keys():
		var w := WeaponDB.get_w(id)
		items[id]["reserve"] = int(w.get("reserve", 0))
		if WeaponDB.is_gun(id):
			items[id]["mag"] = mag_size(id)
	changed.emit()

func mag_size(id: StringName) -> int:
	var w := WeaponDB.get_w(id)
	var m := int(w.get("mag", 0))
	if items.has(id) and (items[id]["atts"] as Array).has("extmag"):
		m = int(round(float(m) * 1.5))
	return m

func mag(id: StringName = &"") -> int:
	if id == &"":
		id = current
	return int(items[id]["mag"]) if items.has(id) else 0

func reserve(id: StringName = &"") -> int:
	if id == &"":
		id = current
	return int(items[id]["reserve"]) if items.has(id) else 0

func atts(id: StringName = &"") -> Array:
	if id == &"":
		id = current
	return items[id]["atts"] if items.has(id) else []

func has_att(att: String, id: StringName = &"") -> bool:
	return atts(id).has(att)

func add_att(id: StringName, att: String) -> bool:
	if not items.has(id):
		return false
	var allowed: Array = WeaponDB.get_w(id).get("atts", [])
	if not allowed.has(att) or (items[id]["atts"] as Array).has(att):
		return false
	# only one optic at a time
	if att == "reddot":
		(items[id]["atts"] as Array).erase("scope")
	elif att == "scope":
		(items[id]["atts"] as Array).erase("reddot")
	(items[id]["atts"] as Array).append(att)
	changed.emit()
	return true

func remove_att(id: StringName, att: String) -> void:
	if items.has(id):
		(items[id]["atts"] as Array).erase(att)
		items[id]["mag"] = mini(int(items[id]["mag"]), mag_size(id))
		changed.emit()

func set_tint(id: StringName, tint: int) -> void:
	if items.has(id):
		items[id]["tint"] = tint
		changed.emit()

## Owned weapons in wheel order.
func owned() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in WeaponDB.ORDER:
		if items.has(id):
			out.append(id)
	return out

func owned_in_slot(slot: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in owned():
		if int(WeaponDB.get_w(id)["slot"]) == slot:
			out.append(id)
	return out

func cycle(dir: int) -> StringName:
	var list := owned()
	var i := list.find(current)
	return list[posmod(i + dir, list.size())]

func save_state() -> Dictionary:
	var out := {}
	for id in items.keys():
		out[String(id)] = {"mag": items[id]["mag"], "reserve": items[id]["reserve"], "atts": (items[id]["atts"] as Array).duplicate(), "tint": items[id]["tint"]}
	return {"items": out, "current": String(current), "parachute": has_parachute, "scuba": has_scuba}

func load_state(d: Dictionary) -> void:
	items = {&"unarmed": {"mag": 0, "reserve": 0, "atts": [], "tint": 0}}
	var src: Dictionary = d.get("items", {})
	for k in src.keys():
		var id := StringName(String(k))
		if not WeaponDB.W.has(id):
			continue
		var e: Dictionary = src[k]
		var a: Array = []
		for x in e.get("atts", []):
			a.append(String(x))
		items[id] = {"mag": int(e.get("mag", 0)), "reserve": int(e.get("reserve", 0)), "atts": a, "tint": int(e.get("tint", 0))}
	current = StringName(String(d.get("current", "unarmed")))
	if not items.has(current):
		current = &"unarmed"
	has_parachute = bool(d.get("parachute", false))
	has_scuba = bool(d.get("scuba", false))
	changed.emit()
