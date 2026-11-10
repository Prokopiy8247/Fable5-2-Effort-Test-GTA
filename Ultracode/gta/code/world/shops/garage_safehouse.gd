extends Node3D
## The player's safehouse (landmark `safehouse`, spec 23A) - created by the garage system.
## Interactables at the landmark markers:
##   Use_Bed       sleep: 8 in-game hours pass, full health, autosave        -> UI "safehouse" (sleep)
##   Use_Save      save point                                                -> UI "safehouse" (save)
##   Use_Wardrobe  change clothes                                            -> UI "wardrobe"
##   Garage_Spot   on foot: stored vehicles (UI "garage"); in a vehicle: store it
## A game saved here (bed or save point) loads with the player standing at `Spawn_Inside`
## (garage provider flag `spawn_inside`). Saves go to slot "manual" (the pause menu's Load reads
## the newer of "manual" / "quick").

const Sites := preload("res://gta/code/world/shops/garage_sites.gd")
const Stats := preload("res://gta/code/world/shops/garage_stats.gd")

const LANDMARK := "safehouse"
const SITE := "safehouse"
const SLEEP_HOURS := 8.0
const MARKERS := ["Use_Bed", "Use_Save", "Use_Wardrobe", "Garage_Spot", "Spawn_Inside", "Door_Front"]

var system: Node = null
var save_slot: String = "manual"
var markers: Dictionary = {}           ## marker -> world Transform3D
var source: String = ""
var enabled: bool = true
var bed: Interactable = null
var save_point: Interactable = null
var wardrobe: Interactable = null
var garage_foot: Interactable = null
var garage_store: Interactable = null
var _busy: bool = false


func setup_site(sys: Node) -> void:
	system = sys
	bed = _make("Bed", "Sleep (%d hours)" % int(SLEEP_HOURS), 1.6, false, _on_bed)
	save_point = _make("SavePoint", "Save game", 1.5, false, _on_save)
	wardrobe = _make("Wardrobe", "Wardrobe - change clothes", 1.5, false, _on_wardrobe)
	garage_foot = _make("GarageList", "Garage - stored vehicles", 2.6, false, _on_garage_list)
	garage_store = _make("GarageStore", "Store vehicle in the garage", 3.0, true, _on_store)
	garage_store.condition = _can_store_here
	if sys != null and sys.has_method("register_site"):
		sys.call("register_site", SITE, self)
	relocate()


func _make(node_name: String, text: String, radius: float, in_vehicle: bool, cb: Callable) -> Interactable:
	var it := Interactable.create(text, radius, "interact")
	it.name = node_name
	if in_vehicle:
		it.in_vehicle_only = true
		it.on_foot_only = false
	it.use_priority = 4
	add_child(it)
	it.interacted.connect(cb)
	return it


func relocate() -> void:
	var srcs := {}
	for m: String in MARKERS:
		var fb := "safehouse_garage" if m == "Garage_Spot" else ("safehouse" if m != "Spawn_Inside" else "spawn_start")
		var r := Sites.marker(LANDMARK, m, fb)
		markers[m] = r["xform"]
		srcs[str(r["source"])] = true
	source = ",".join(PackedStringArray(srcs.keys()))
	_place(bed, "Use_Bed", 0.9)
	_place(save_point, "Use_Save", 0.9)
	_place(wardrobe, "Use_Wardrobe", 0.9)
	_place(garage_foot, "Garage_Spot", 0.9)
	_place(garage_store, "Garage_Spot", 0.8)


func _place(it: Interactable, marker_name: String, lift: float) -> void:
	if it == null or not markers.has(marker_name):
		return
	it.global_position = (markers[marker_name] as Transform3D).origin + Vector3(0.0, lift, 0.0)


func get_marker(marker_name: String) -> Transform3D:
	return markers.get(marker_name, Transform3D.IDENTITY)


func set_enabled(on: bool) -> void:
	enabled = on
	for it: Interactable in [bed, save_point, wardrobe, garage_foot, garage_store]:
		if it != null:
			it.enabled = on


## Spawn candidates for retrieving a stored vehicle here: the garage bay, then the kerb outside.
func get_spawn_candidates(_site_id: String, vehicle_class: String) -> Array:
	var out: Array = []
	if not (system != null and system.has_method("is_storable_class") and bool(system.call("is_storable_class", vehicle_class))):
		return out
	if markers.has("Garage_Spot"):
		out.append(markers["Garage_Spot"])
	if Sites.has_location("safehouse_garage"):
		out.append(Game.get_location("safehouse_garage"))
	var near: Vector3 = (markers.get("Garage_Spot", Game.get_location("safehouse")) as Transform3D).origin
	out.append_array(Sites.spawn_points_near("parking", near, 70.0))
	return out


# --- interactions -------------------------------------------------------------------------------

func _on_bed(_player: Node3D) -> void:
	UI.open_screen("safehouse", {"site": SITE, "focus": "sleep", "safehouse": self})


func _on_save(_player: Node3D) -> void:
	UI.open_screen("safehouse", {"site": SITE, "focus": "save", "safehouse": self})


func _on_wardrobe(_player: Node3D) -> void:
	open_wardrobe()


func open_wardrobe() -> bool:
	var scr := UI.open_screen("wardrobe", {"shop_id": "safehouse_wardrobe", "source": "safehouse", "free": true})
	if scr == null:
		UI.notify("The wardrobe is not available yet", "warn")
		return false
	return true


func _on_garage_list(_player: Node3D) -> void:
	open_garage_list()


func open_garage_list() -> void:
	UI.open_screen("garage", {"mode": "stored", "site": SITE, "title": "Safehouse garage"})


func _can_store_here(player: Node3D) -> bool:
	if not enabled or _busy:
		return false
	var v: Variant = player.get("current_vehicle")
	if v == null or not is_instance_valid(v):
		return false
	var rb := v as RigidBody3D
	return rb == null or rb.linear_velocity.length() < 3.0


func _on_store(player: Node3D) -> void:
	var v: Variant = player.get("current_vehicle")
	if v == null or not is_instance_valid(v):
		return
	await store_here(v as Node3D)


## Drive-in store: fade, vehicle into storage, player standing in the bay facing out.
func store_here(v: Node3D) -> bool:
	if system == null or _busy:
		return false
	var reason := str(system.call("can_store", v))
	if reason != "":
		UI.notify(reason, "warn")
		Audio.play("ui_error", -6.0, 1.0, "UI")
		return false
	_busy = true
	var vname := Stats.vehicle_name(v)
	await UI.fade_out(0.35)
	var ok := bool(system.call("store_vehicle", v))
	if ok and Game.has_player():
		var spot: Transform3D = markers.get("Garage_Spot", Game.get_location("safehouse"))
		Game.player.call("teleport", spot.origin + Vector3(0.0, 0.05, 0.0), Sites.yaw_of(spot))
		Audio.play_at("door_close", spot.origin, -2.0, 0.8, 30.0)
	await UI.fade_in(0.35)
	_busy = false
	if ok:
		var n: int = (system.call("get_stored") as Array).size()
		UI.notify("%s stored in the garage (%d / %d)" % [vname, n, int(system.call("get_capacity"))], "good")
	else:
		UI.notify(str(system.get("last_error")), "warn")
	return ok


## Sleep: refuses while wanted. 8 hours pass, full health, autosave. Returns true if slept.
func sleep() -> bool:
	if _busy:
		return false
	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null and wanted.get("level") is int and int(wanted.get("level")) > 0:
		UI.notify("You can't rest with the police after you", "warn")
		return false
	_busy = true
	await UI.fade_out(0.8)
	WorldClock.advance_hours(SLEEP_HOURS)
	if Game.has_player():
		var p := Game.player
		var mh: Variant = p.get("max_health")
		if p.has_method("heal"):
			p.call("heal", float(mh) if (mh is float or mh is int) else 100.0)
	var saved := save_here(false)
	await UI.fade_in(0.8)
	_busy = false
	UI.notify("Slept %d hours - it is %s%s" % [int(SLEEP_HOURS), WorldClock.get_time_string(),
			" (game saved)" if saved else ""], "good")
	return true


## Saves to `save_slot`; a game loaded from it starts at Spawn_Inside.
func save_here(with_toast: bool = true) -> bool:
	if system != null:
		system.set("spawn_inside_on_load", true)
	var ok := SaveSystem.save_game(save_slot)
	if system != null:
		system.set("spawn_inside_on_load", false)
	if with_toast:
		UI.notify("Game saved" if ok else "Saving failed", "good" if ok else "bad")
	return ok


## Called (deferred) by the garage system when a save made here is loaded.
func spawn_player_inside() -> void:
	if not Game.has_player():
		return
	var xf: Transform3D = markers.get("Spawn_Inside", Game.get_location("safehouse"))
	Game.player.call("teleport", xf.origin + Vector3(0.0, 0.05, 0.0), Sites.yaw_of(xf))
