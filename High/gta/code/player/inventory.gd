class_name Inventory
extends RefCounted
## Player weapon ownership, ammo, attachments and finishes.

var owned: Dictionary = {}   # id -> {"mag": int, "reserve": int, "mods": Array, "tint": int}
var current := "fists"


func _init() -> void:
	give("fists", 0)


func give(id: String, ammo: int = -1) -> void:
	var d: WeaponDef = Data.weapons[id]
	if not owned.has(id):
		owned[id] = {"mag": d.mag, "reserve": 0, "mods": [], "tint": 0}
		if ammo < 0:
			ammo = d.mag * 3
	if ammo > 0:
		add_ammo(id, ammo)


func has(id: String) -> bool:
	return owned.has(id)


func def() -> WeaponDef:
	return Data.weapons[current]


func entry() -> Dictionary:
	return owned[current]


func mag_size(id: String = "") -> int:
	if id == "":
		id = current
	var d: WeaponDef = Data.weapons[id]
	var m := d.mag
	if owned.has(id) and owned[id].mods.has("extmag"):
		m = int(ceil(m * 1.5))
	return m


func add_ammo(id: String, n: int) -> void:
	if not owned.has(id):
		return
	var d: WeaponDef = Data.weapons[id]
	owned[id].reserve = mini(owned[id].reserve + n, d.max_ammo)


func refill_all() -> void:
	for id in owned:
		var d: WeaponDef = Data.weapons[id]
		owned[id].reserve = d.max_ammo
		owned[id].mag = mag_size(id)


func total_ammo(id: String) -> int:
	if not owned.has(id):
		return 0
	return owned[id].mag + owned[id].reserve


func has_mod(m: String) -> bool:
	return owned[current].mods.has(m)


func add_mod(id: String, m: String) -> void:
	if owned.has(id) and not owned[id].mods.has(m):
		owned[id].mods.append(m)


func slot_weapons(slot: int) -> Array:
	var out := []
	for id in Data.weapon_order:
		if owned.has(id) and Data.weapons[id].slot == slot:
			out.append(id)
	return out


func cycle(dir: int) -> String:
	var ids := []
	for id in Data.weapon_order:
		if owned.has(id):
			ids.append(id)
	var i := ids.find(current)
	return ids[posmod(i + dir, ids.size())]


func tint_color(id: String = "") -> Color:
	if id == "":
		id = current
	return Data.WEAPON_TINTS[clampi(int(owned[id].tint), 0, Data.WEAPON_TINTS.size() - 1)][1]


func save_state() -> Dictionary:
	return {"owned": owned.duplicate(true), "current": current}


func load_state(s: Dictionary) -> void:
	owned.clear()
	var o: Dictionary = s.get("owned", {})
	for id in o:
		if Data.weapons.has(id):
			var e: Dictionary = o[id]
			owned[id] = {"mag": int(e.get("mag", 0)), "reserve": int(e.get("reserve", 0)), "mods": Array(e.get("mods", [])), "tint": int(e.get("tint", 0))}
	if not owned.has("fists"):
		give("fists", 0)
	current = s.get("current", "fists")
	if not owned.has(current):
		current = "fists"
