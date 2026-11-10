extends RefCounted
## The player's owned clothing set (SaveSystem provider "wardrobe", registered by the shops system).
## Owned = clothing definition ids of Registry kind "clothing" (appearance_registry.gd). Owning an item
## means it can be worn in any of its colours in the wardrobe, for free. Zero-price items ("No Hat",
## "No Glasses") are always owned. The first time the set is used it is seeded with what the player
## is wearing, so the wardrobe is never empty.

var owned: Dictionary = {}        ## def id -> true
var seeded: bool = false


func owns(def_id: String) -> bool:
	if owned.has(def_id):
		return true
	var d: Variant = Registry.get_def("clothing", def_id)
	return d is Dictionary and int((d as Dictionary).get("price", 0)) <= 0


func add(def_id: String) -> void:
	if def_id != "":
		owned[def_id] = true


func remove(def_id: String) -> void:
	owned.erase(def_id)


func get_owned() -> Array:
	var out: Array = []
	for d: Variant in Registry.all("clothing"):
		if d is Dictionary and owns(str((d as Dictionary).get("id", ""))):
			out.append(str((d as Dictionary)["id"]))
	return out


func clear() -> void:
	owned.clear()
	seeded = false


## Own every clothing def the appearance currently wears (called once, lazily).
func seed_from_appearance(a: Dictionary) -> void:
	seeded = true
	if a.is_empty():
		return
	var outfit := str(a.get("outfit", ""))
	for d: Variant in Registry.all("clothing"):
		if not (d is Dictionary):
			continue
		var def := d as Dictionary
		var slot := str(def.get("slot", ""))
		if outfit != "" and (slot == "top" or slot == "bottom"):
			continue
		if str(a.get(slot, "")) == str(def.get("part", "")):
			add(str(def.get("id", "")))


func ensure_seeded(a: Dictionary) -> void:
	if not seeded:
		seed_from_appearance(a)


func get_save_data() -> Dictionary:
	var appearance: Dictionary = {}
	if Game.has_player() and Game.player.has_method("get_appearance"):
		var a: Variant = Game.player.call("get_appearance")
		if a is Dictionary:
			appearance = (a as Dictionary).duplicate()
	return {"owned": owned.keys(), "seeded": seeded, "appearance": appearance}


func load_save_data(d: Dictionary) -> void:
	owned.clear()
	var list: Variant = d.get("owned", [])
	if list is Array:
		for id: Variant in list:
			if Registry.has_def("clothing", str(id)):
				owned[str(id)] = true
	seeded = bool(d.get("seeded", not owned.is_empty()))
	# The player provider restores the appearance itself; this is a safety net for saves where it
	# did not (applied only when the look differs, without notifying Wanted).
	var a: Variant = d.get("appearance", {})
	if a is Dictionary and not (a as Dictionary).is_empty() and Game.has_player():
		var cur: Variant = Game.player.call("get_appearance") if Game.player.has_method("get_appearance") else {}
		if cur is Dictionary and not _same_look(cur as Dictionary, a as Dictionary):
			if Game.player.has_method("set_appearance"):
				Game.player.call("set_appearance", (a as Dictionary).duplicate())


static func _same_look(a: Dictionary, b: Dictionary) -> bool:
	for k: Variant in b.keys():
		if str(a.get(k, "")) != str(b[k]):
			return false
	return true
