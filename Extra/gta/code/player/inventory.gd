class_name Inventory
extends RefCounted
## Weapons, ammunition, attachments and finishes owned by a character.

var owned := {"fists": true}
var ammo := {}
var clip := {}
var wmods := {}
var tints := {}
var current := "fists"
var slot_last := {}


func give(wid: String, with_ammo: bool = true) -> bool:
	var d: Dictionary = Defs.WEAPONS[wid]
	var is_new := not owned.has(wid)
	owned[wid] = true
	if d.has("ammo"):
		var at: String = d.ammo
		if is_new and d.type != "throw":
			clip[wid] = mag_size(wid)
		if with_ammo:
			add_ammo(at, int(Defs.AMMO[at].box) * (2 if d.type != "throw" else 3))
	return is_new


func add_ammo(at: String, n: int) -> void:
	ammo[at] = mini(int(ammo.get(at, 0)) + n, int(Defs.AMMO[at].max))


func mag_size(wid: String) -> int:
	var d: Dictionary = Defs.WEAPONS[wid]
	var m := int(d.get("mag", 0))
	if has_mod(wid, "extmag"):
		m = int(ceil(m * 1.6))
	return m


func has_mod(wid: String, mod: String) -> bool:
	return wmods.has(wid) and wmods[wid].has(mod)


func mods_of(wid: String) -> Dictionary:
	return wmods.get(wid, {})


func add_mod(wid: String, mod: String) -> void:
	if not wmods.has(wid):
		wmods[wid] = {}
	wmods[wid][mod] = true


func reserve(wid: String) -> int:
	var d: Dictionary = Defs.WEAPONS[wid]
	if not d.has("ammo"):
		return -1
	return int(ammo.get(d.ammo, 0))


func in_clip(wid: String) -> int:
	var d: Dictionary = Defs.WEAPONS[wid]
	if not d.has("ammo"):
		return -1
	if d.type == "throw":
		return int(ammo.get(d.ammo, 0))
	return int(clip.get(wid, 0))


func use_round(wid: String) -> bool:
	var d: Dictionary = Defs.WEAPONS[wid]
	if not d.has("ammo"):
		return true
	if d.type == "throw":
		if int(ammo.get(d.ammo, 0)) <= 0:
			return false
		ammo[d.ammo] = int(ammo[d.ammo]) - 1
		return true
	if int(clip.get(wid, 0)) <= 0:
		return false
	clip[wid] = int(clip[wid]) - 1
	return true


func reload(wid: String) -> bool:
	var d: Dictionary = Defs.WEAPONS[wid]
	if not d.has("ammo") or d.type == "throw":
		return false
	var need := mag_size(wid) - int(clip.get(wid, 0))
	var have := int(ammo.get(d.ammo, 0))
	var n := mini(need, have)
	if n <= 0:
		return false
	clip[wid] = int(clip.get(wid, 0)) + n
	ammo[d.ammo] = have - n
	return true


func slot_weapons(slot: String) -> Array:
	var out: Array = []
	for wid in Defs.WEAPON_ORDER:
		if owned.has(wid) and Defs.WEAPONS[wid].slot == slot:
			out.append(wid)
	return out


func cycle(dir: int) -> String:
	var all: Array = []
	for wid in Defs.WEAPON_ORDER:
		if owned.has(wid):
			all.append(wid)
	var i := all.find(current)
	return all[posmod(i + dir, all.size())]


func refill_all() -> void:
	for at in Defs.AMMO.keys():
		ammo[at] = int(Defs.AMMO[at].max)
	for wid in owned.keys():
		if Defs.WEAPONS[wid].has("mag") and Defs.WEAPONS[wid].type != "throw":
			clip[wid] = mag_size(wid)


func to_dict() -> Dictionary:
	return {"owned": owned.keys(), "ammo": ammo, "clip": clip, "mods": wmods, "tints": tints, "current": current}


func from_dict(d: Dictionary) -> void:
	owned = {"fists": true}
	for w in d.get("owned", []):
		if Defs.WEAPONS.has(w):
			owned[w] = true
	ammo = {}
	for k in d.get("ammo", {}).keys():
		ammo[k] = int(d.ammo[k])
	clip = {}
	for k in d.get("clip", {}).keys():
		clip[k] = int(d.clip[k])
	wmods = d.get("mods", {})
	tints = d.get("tints", {})
	current = d.get("current", "fists")
	if not owned.has(current):
		current = "fists"
