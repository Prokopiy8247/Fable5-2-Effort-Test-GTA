extends Node3D
## World system "garage" (BootManifest; contract ARCHITECTURE_WAVE2 W2.7). Docs: docs/GARAGE.md.
##
## Owns the player's stored vehicles (persisted through SaveSystem provider "garage"), the personal
## vehicle tag (group `personal_vehicle` + a `minimap_blip`), and creates the site helpers in
## setup() (all in res://gta/code/world/shops/):
##   garage_mod_shop.gd        Torque Garage: in-vehicle Use_Bay -> UI "mod_garage" (spec 14A)
##   garage_safehouse.gd       safehouse bed / save point / wardrobe / Garage_Spot (spec 23A)
##   garage_gas_station.gd     Halcyon Fuel in-vehicle quick service + explosive Pump_* objects
##   garage_vehicle_access.gd  rental terminals: airport (aircraft), marina (boats), parking
##                             garage (cars, bikes) + the parking garage store / retrieve point (spec 26)
##
## Contract API (W2.7):
##   store_vehicle(vehicle) -> bool, get_stored() -> Array[Dictionary], retrieve_vehicle(index, xform)
##   -> Node3D, get_capacity() -> int, set_personal_vehicle(v), get_personal_vehicle() -> Node3D,
##   deliver_personal_vehicle(near) -> Node3D
## Additions: can_store(v) -> String (reason, "" = ok), last_error, remove_stored(i),
##   retrieve_at_site(i, site) / rent_vehicle(spec_id, site) / board(v) (fade + seat the player),
##   get_catalogue(kinds), find_spawn(site, vehicle_class), get_site_ids(), get_helper(name),
##   is_storable_class(cls), garage_vehicle_name(i).
## Vehicles are reached by duck typing only (no class types of the vehicle module).

const Sites := preload("res://gta/code/world/shops/garage_sites.gd")
const Stats := preload("res://gta/code/world/shops/garage_stats.gd")

const HELPERS := {
	"mod_shop": "res://gta/code/world/shops/garage_mod_shop.gd",
	"safehouse": "res://gta/code/world/shops/garage_safehouse.gd",
	"gas_station": "res://gta/code/world/shops/garage_gas_station.gd",
	"access": "res://gta/code/world/shops/garage_vehicle_access.gd",
}
const CAPACITY := 4
const SAVE_KEY := "garage"
const SAVE_VERSION := 1
const STORABLE_CLASSES: Array[String] = ["car", "bike", "bicycle"]
const MAX_STORE_LENGTH := 7.6       ## the safehouse bay is 7.4 m deep; a little overhang is fine
const MAX_STORE_HEIGHT := 3.1
const PERSONAL_GROUP := "personal_vehicle"
const BLIP_GROUP := "minimap_blip"
const PERSONAL_BLIP_COLOR := Color(0.373, 0.839, 0.8)
const SYNC_SECONDS := 1.0
const FADE := 0.35

var stored: Array[Dictionary] = []      ## VehicleBase.get_save_data() + "name"
var capacity: int = CAPACITY
var enabled: bool = true
var last_error: String = ""
var helpers: Dictionary = {}            ## name -> helper node
var spawn_inside_on_load: bool = false  ## the safehouse sets this while it saves
var busy: bool = false                  ## a fade / spawn sequence is running

var _personal: Node3D = null
var _sync_t: float = 0.0
var _sites: Dictionary = {}             ## site id -> helper that resolves its spawn points
var _rentals: Dictionary = {}           ## site id -> last rented vehicle


func setup() -> void:
	SaveSystem.register_provider(SAVE_KEY, self)
	EventBus.vehicle_spawned.connect(_on_vehicle_spawned)
	EventBus.vehicle_destroyed.connect(_on_vehicle_destroyed)
	EventBus.game_ready.connect(_on_game_ready)
	var times := PackedStringArray()
	for key: String in HELPERS:
		var t0 := Time.get_ticks_usec()
		var path: String = HELPERS[key]
		if not ResourceLoader.exists(path):
			continue
		var scr := load(path) as Script
		if scr == null or not scr.can_instantiate():
			push_warning("garage: helper %s failed to load" % path)
			continue
		var node := scr.new() as Node
		if node == null:
			continue
		node.name = key.to_pascal_case()
		add_child(node)
		helpers[key] = node
		if node.has_method("setup_site"):
			node.call("setup_site", self)
		times.append("%s %d ms" % [key, (Time.get_ticks_usec() - t0) / 1000])
	print("[garage] helpers: %s | sites: %s" % [", ".join(times), str(_sites.keys())])


## The city builder may finish placing buildings after our setup: re-resolve every marker once
## the whole session is up (cheap: moves a few Area3Ds).
func _on_game_ready() -> void:
	refresh_sites()


func refresh_sites() -> void:
	for h: Node in helpers.values():
		if is_instance_valid(h) and h.has_method("relocate"):
			h.call("relocate")


func get_helper(helper_name: String) -> Node:
	var h: Variant = helpers.get(helper_name, null)
	if h != null and is_instance_valid(h):
		return h
	return null


func set_enabled(on: bool) -> void:
	enabled = on
	for h: Node in helpers.values():
		if is_instance_valid(h) and h.has_method("set_enabled"):
			h.call("set_enabled", on)


func reset_for_respawn() -> void:
	for h: Node in helpers.values():
		if is_instance_valid(h) and h.has_method("reset_for_respawn"):
			h.call("reset_for_respawn")


func _process(delta: float) -> void:
	_sync_t -= delta
	if _sync_t > 0.0:
		return
	_sync_t = SYNC_SECONDS
	_sync_personal()


# =================================================================================================
# storage (contract)
# =================================================================================================

func get_capacity() -> int:
	return capacity


func get_stored() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in stored:
		out.append(d.duplicate(true))
	return out


func is_storable_class(vehicle_class: String) -> bool:
	return STORABLE_CLASSES.has(vehicle_class)


## "" when `vehicle` may be stored, otherwise the reason shown to the player.
func can_store(vehicle: Node3D) -> String:
	if vehicle == null or not is_instance_valid(vehicle):
		return "No vehicle"
	if _bool(vehicle, "destroyed"):
		return "This vehicle is a wreck"
	if is_police_or_emergency(vehicle):
		return "Police and emergency vehicles cannot be stored"
	var cls := str(vehicle.get("vehicle_class")) if vehicle.get("vehicle_class") != null else "car"
	if not is_storable_class(cls):
		return "This garage only takes cars and bikes"
	var box: Variant = vehicle.get("body_aabb")
	if box is AABB and ((box as AABB).size.z > MAX_STORE_LENGTH or (box as AABB).size.y > MAX_STORE_HEIGHT):
		return "Too big for this garage"
	if stored.size() >= capacity:
		return "Garage full (%d / %d)" % [stored.size(), capacity]
	return ""


func is_police_or_emergency(vehicle: Node3D) -> bool:
	if vehicle == null or not is_instance_valid(vehicle):
		return false
	if _bool(vehicle, "is_police") or _bool(vehicle, "is_emergency"):
		return true
	var tag := str(vehicle.get("owner_tag")) if vehicle.get("owner_tag") != null else ""
	if tag == "police" or tag == "emergency":
		return true
	var spec := Stats.spec_of(vehicle)
	return spec != null and (_bool(spec, "is_police") or _bool(spec, "is_emergency"))


## Removes the vehicle from the world and keeps spec / colours / mods / health. A player sitting
## in it is put on foot beside it first. False (and `last_error`) when it may not be stored.
func store_vehicle(vehicle: Node3D) -> bool:
	last_error = can_store(vehicle)
	if last_error != "":
		return false
	var data := capture(vehicle)
	if vehicle == get_personal_vehicle():
		data["personal"] = true
		_untag(vehicle)
		_personal = null
	_evict_player(vehicle)
	stored.append(data)
	_despawn(vehicle)
	return true


## Plain JSON-safe description of a vehicle (VehicleBase.get_save_data() + display name).
func capture(vehicle: Node3D) -> Dictionary:
	var d := {}
	if vehicle.has_method("get_save_data"):
		var v: Variant = vehicle.call("get_save_data")
		if v is Dictionary:
			d = (v as Dictionary).duplicate(true)
	if not d.has("spec_id"):
		d["spec_id"] = str(vehicle.get("spec_id"))
	d["name"] = Stats.vehicle_name(vehicle)
	d["class"] = str(vehicle.get("vehicle_class")) if vehicle.get("vehicle_class") != null else "car"
	return d


## Spawns stored vehicle `index` at `xform` (asleep, owner "player", personal) and removes it
## from storage. Null (and `last_error`) when it cannot be spawned; it then stays stored.
func retrieve_vehicle(index: int, xform: Transform3D) -> Node3D:
	last_error = ""
	if index < 0 or index >= stored.size():
		last_error = "No vehicle in that slot"
		return null
	var data: Dictionary = stored[index]
	var v := spawn_from_data(data, xform)
	if v == null:
		last_error = "%s could not be brought out" % str(data.get("name", "Vehicle"))
		return null
	stored.remove_at(index)
	set_personal_vehicle(v)
	return v


func spawn_from_data(data: Dictionary, xform: Transform3D) -> Node3D:
	var spec_id := str(data.get("spec_id", ""))
	if spec_id == "":
		return null
	var opts := {"owner_tag": "player", "asleep": true,
			"color": SaveSystem.array_to_color(data.get("primary", null), Color(0.8, 0.8, 0.8)),
			"color2": SaveSystem.array_to_color(data.get("secondary", null), Color(0, 0, 0, 0))}
	var m: Variant = data.get("mods", {})
	if m is Dictionary and not (m as Dictionary).is_empty():
		opts["mods"] = (m as Dictionary).duplicate()
	if data.has("health"):
		opts["health"] = float(data["health"])
	var v := Game.spawn_vehicle(spec_id, xform, opts)
	if v == null:
		return null
	if v.has_method("apply_save_data"):
		v.call("apply_save_data", data)
	return v


## Drops a stored vehicle for good (frees the slot).
func remove_stored(index: int) -> bool:
	if index < 0 or index >= stored.size():
		return false
	stored.remove_at(index)
	return true


func garage_vehicle_name(index: int) -> String:
	if index < 0 or index >= stored.size():
		return ""
	return str(stored[index].get("name", Stats.display_name(str(stored[index].get("spec_id", "")))))


# =================================================================================================
# personal vehicle (contract)
# =================================================================================================

func set_personal_vehicle(vehicle: Node3D) -> void:
	var vm := Game.get_system("vehicles")
	if vm != null and vm.has_method("set_personal_vehicle"):
		vm.call("set_personal_vehicle", vehicle)
	if _personal != null and is_instance_valid(_personal) and _personal != vehicle:
		_untag(_personal)
	_personal = vehicle if (vehicle != null and is_instance_valid(vehicle)) else null
	if _personal != null:
		_personal.set("personal", true)
		if str(_personal.get("owner_tag")) != "player":
			_personal.set("owner_tag", "player")
		_tag(_personal)


func get_personal_vehicle() -> Node3D:
	var vm := Game.get_system("vehicles")
	if vm != null and vm.has_method("get_personal_vehicle"):
		var pv: Variant = vm.call("get_personal_vehicle")
		if pv != null and is_instance_valid(pv):
			return pv as Node3D
		return null
	if _personal != null and is_instance_valid(_personal):
		return _personal
	return null


## Phone service (Wave 3): brings the personal vehicle (or the personal / first stored one) to the
## nearest free kerb spot near `near`. Returns the vehicle or null.
func deliver_personal_vehicle(near: Vector3) -> Node3D:
	last_error = ""
	var xf := _delivery_spot(near)
	if xf == Transform3D.IDENTITY:
		last_error = "No free spot nearby"
		return null
	var pv := get_personal_vehicle()
	if pv != null and not _bool(pv, "destroyed"):
		if _bool(pv, "is_player_driven"):
			last_error = "You are already in it"
			return pv
		if pv.has_method("teleport"):
			pv.call("teleport", xf)
		else:
			pv.global_transform = xf
		return pv
	if stored.is_empty():
		last_error = "No personal vehicle"
		return null
	var idx := 0
	for i in stored.size():
		if bool(stored[i].get("personal", false)):
			idx = i
			break
	return retrieve_vehicle(idx, xf)


func _delivery_spot(near: Vector3) -> Transform3D:
	for xf: Transform3D in Sites.spawn_points_near("parking", near, 90.0):
		if Sites.is_spot_clear(xf.origin, 3.2):
			return xf
	var w := Game.world
	if w != null:
		var roads: Variant = w.get("roads")
		if roads is Object and (roads as Object).has_method("get_nearest_lane"):
			var hit: Variant = (roads as Object).call("get_nearest_lane", near, 90.0)
			if hit is Dictionary and not (hit as Dictionary).is_empty():
				var xf2: Variant = (roads as Object).call("sample_lane", int(hit["lane_id"]), float(hit["offset"]))
				if xf2 is Transform3D:
					return xf2
	return Transform3D.IDENTITY


func _tag(v: Node3D) -> void:
	if v == null or not is_instance_valid(v):
		return
	if not v.is_in_group(PERSONAL_GROUP):
		v.add_to_group(PERSONAL_GROUP)
	if not v.is_in_group(BLIP_GROUP):
		v.add_to_group(BLIP_GROUP)
	v.set_meta("blip_icon", &"car")
	v.set_meta("blip_color", PERSONAL_BLIP_COLOR)
	v.set_meta("blip_clamp", true)


func _untag(v: Node3D) -> void:
	if v == null or not is_instance_valid(v):
		return
	if v.is_in_group(PERSONAL_GROUP):
		v.remove_from_group(PERSONAL_GROUP)
	if v.is_in_group(BLIP_GROUP):
		v.remove_from_group(BLIP_GROUP)


func _sync_personal() -> void:
	var pv := get_personal_vehicle()
	if pv != null and _bool(pv, "destroyed"):
		_untag(pv)
		if pv == _personal:
			_personal = null
		return
	if pv == _personal:
		if pv != null and not pv.is_in_group(PERSONAL_GROUP):
			_tag(pv)
		return
	if _personal != null and is_instance_valid(_personal):
		_untag(_personal)
	_personal = pv
	if pv != null:
		_tag(pv)


func _on_vehicle_spawned(v: Node3D) -> void:
	if v != null and is_instance_valid(v) and _bool(v, "personal"):
		_sync_t = 0.0


func _on_vehicle_destroyed(v: Node3D, _instigator: Node) -> void:
	if v != null and v == _personal:
		_untag(v)
		_personal = null


# =================================================================================================
# sites: spawn points, rentals, retrieving with the player seated
# =================================================================================================

## Helpers call this from setup_site(): `helper.get_spawn_candidates(site_id, vehicle_class)` must
## return an Array[Transform3D] in order of preference.
func register_site(site_id: String, helper: Node) -> void:
	_sites[site_id] = helper


func get_site_ids() -> Array:
	return _sites.keys()


func has_site(site_id: String) -> bool:
	return _sites.has(site_id) or site_id == "player"


## First clear spawn transform of a site for that vehicle class: {"ok", "xform"}.
## Site "player" = in front of the player (admin / testing).
func find_spawn(site_id: String, vehicle_class: String, ignore: Node = null) -> Dictionary:
	var cands: Array = []
	if site_id == "player":
		cands = _player_spots(vehicle_class)
	else:
		var h: Variant = _sites.get(site_id, null)
		if h != null and is_instance_valid(h) and (h as Node).has_method("get_spawn_candidates"):
			cands = (h as Node).call("get_spawn_candidates", site_id, vehicle_class)
	var radius := clear_radius(vehicle_class)
	for xf: Variant in cands:
		if xf is Transform3D and Sites.is_spot_clear((xf as Transform3D).origin, radius, ignore):
			return {"ok": true, "xform": xf}
	return {"ok": false, "xform": Transform3D.IDENTITY}


static func clear_radius(vehicle_class: String) -> float:
	match vehicle_class:
		"plane":
			return 9.0
		"heli":
			return 7.5
		"boat":
			return 5.0
		"bike", "bicycle":
			return 2.0
	return 3.2


func _player_spots(vehicle_class: String) -> Array:
	var out: Array = []
	if not Game.has_player():
		return out
	var p := Game.get_player_position()
	var yaw := float(Game.player.global_rotation.y)
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var dist := 6.0
	if vehicle_class == "plane":
		dist = 16.0
	elif vehicle_class == "heli":
		dist = 11.0
	elif vehicle_class == "boat":
		dist = 9.0
	for k in 4:
		var d := dist + float(k) * 4.0
		var pos := p + fwd * d
		if vehicle_class == "boat":
			if not Game.is_in_water(Vector3(pos.x, -0.5, pos.z)):
				continue
			pos.y = Game.WATER_LEVEL
		else:
			pos.y = Game.ground_height(pos.x, pos.z)
		out.append(Transform3D(Basis(Vector3.UP, yaw), pos))
	return out


## Catalogue for the access terminals: every registered spec whose class is in `kinds`.
## Entries: {id, name, class, fee, available, top_kmh, seats, flags, description}.
func get_catalogue(kinds: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var vm := Game.get_system("vehicles")
	for id: Variant in Registry.ids("vehicles"):
		var spec: Variant = Registry.get_def("vehicles", str(id))
		if not (spec is Object):
			continue
		var cls := str((spec as Object).get("vehicle_class"))
		if not kinds.has(cls):
			continue
		var avail := vm != null and vm.has_method("can_spawn") and bool(vm.call("can_spawn", str(id)))
		var flags := []
		if bool((spec as Object).get("is_police")):
			flags.append("police")
		if bool((spec as Object).get("is_emergency")):
			flags.append("emergency")
		out.append({"id": str(id), "name": Stats.display_name(str(id)), "class": cls,
				"fee": Stats.rental_fee(str(id)), "available": avail,
				"top_kmh": float((spec as Object).get("top_speed")) * 3.6,
				"seats": int((spec as Object).get("seats")), "flags": flags,
				"description": str((spec as Object).get("description"))})
	# civilian first, then service vehicles; by class, then by fee
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := (a["flags"] as Array).size() > 0
		var sb := (b["flags"] as Array).size() > 0
		if sa != sb:
			return sb
		if str(a["class"]) != str(b["class"]):
			return str(a["class"]) < str(b["class"])
		if bool(a["available"]) != bool(b["available"]):
			return bool(a["available"])
		return int(a["fee"]) < int(b["fee"]))
	return out


## Rents `spec_id` at `site_id` (fee unless free_shopping) and spawns it at the site. Does not
## seat the player (see board()). Null + `last_error` on failure (no money is taken then).
func rent_vehicle(spec_id: String, site_id: String) -> Node3D:
	last_error = ""
	var vm := Game.get_system("vehicles")
	if vm == null or not vm.has_method("can_spawn") or not bool(vm.call("can_spawn", spec_id)):
		last_error = "%s is not available" % Stats.display_name(spec_id)
		return null
	var spec: Variant = Registry.get_def("vehicles", spec_id)
	var cls := str((spec as Object).get("vehicle_class")) if spec is Object else "car"
	_clear_old_rental(site_id)
	var spot := find_spawn(site_id, cls)
	if not bool(spot["ok"]):
		last_error = "The pick-up spot is blocked"
		return null
	var fee := Stats.rental_fee(spec_id)
	if not Game.spend(fee):
		last_error = "Not enough money (%s)" % Stats.money(fee)
		return null
	var v := Game.spawn_vehicle(spec_id, spot["xform"], {"owner_tag": "player"})
	if v == null:
		Game.add_money(fee)
		last_error = "%s could not be spawned" % Stats.display_name(spec_id)
		return null
	v.set_meta("garage_rental", site_id)
	_rentals[site_id] = v
	EventBus.item_purchased.emit("vehicle_rental", spec_id, fee)
	return v


func _clear_old_rental(site_id: String) -> void:
	var old: Variant = _rentals.get(site_id, null)
	_rentals.erase(site_id)
	if old == null or not is_instance_valid(old):
		return
	var v := old as Node3D
	if _bool(v, "is_player_driven") or v == get_personal_vehicle() or v == Game.get_player_vehicle():
		return
	if Game.has_player() and v.global_position.distance_to(Game.get_player_position()) < 4.0:
		return
	_despawn(v)


## Retrieve stored vehicle `index` at a site's spawn spot and seat the player (with a fade).
func retrieve_at_site(index: int, site_id: String) -> Node3D:
	last_error = ""
	if busy:
		last_error = "Busy"
		return null
	if index < 0 or index >= stored.size():
		last_error = "No vehicle in that slot"
		return null
	var cls := str(stored[index].get("class", "car"))
	var spot := find_spawn(site_id, cls)
	if not bool(spot["ok"]):
		last_error = "The garage spot is blocked"
		return null
	busy = true
	var vname := garage_vehicle_name(index)
	await _fade_out()
	var v := retrieve_vehicle(index, spot["xform"])
	if v != null:
		_seat_player(v)
	await _fade_in()
	busy = false
	if v != null:
		notify("%s is ready" % vname, "good")
	else:
		notify(last_error, "warn")
	return v


## Rent + seat the player (fade). Used by the catalogue screen.
func rent_and_board(spec_id: String, site_id: String) -> Node3D:
	if busy:
		last_error = "Busy"
		return null
	busy = true
	var fee := Stats.rental_fee(spec_id)
	await _fade_out()
	var v := rent_vehicle(spec_id, site_id)
	if v != null:
		_seat_player(v)
	await _fade_in()
	busy = false
	if v != null:
		notify("%s rented%s" % [Stats.display_name(spec_id), "" if fee <= 0 else " for " + Stats.money(fee)], "money")
	else:
		notify(last_error, "warn")
	return v


## Seat the player in `v` at once (no walk-up), with a fade.
func board(v: Node3D) -> void:
	if v == null or not is_instance_valid(v):
		return
	await _fade_out()
	_seat_player(v)
	await _fade_in()


func _seat_player(v: Node3D) -> void:
	if not Game.has_player() or v == null or not is_instance_valid(v):
		return
	var p := Game.player
	if bool(p.get("is_dead")):
		return
	if p.has_method("enter_vehicle"):
		p.call("enter_vehicle", v, 0, true)


func _evict_player(vehicle: Node3D) -> void:
	if not Game.has_player():
		return
	var p := Game.player
	if p.get("current_vehicle") != vehicle:
		return
	var xf: Transform3D = vehicle.global_transform
	if vehicle.has_method("get_exit_transform"):
		var e: Variant = vehicle.call("get_exit_transform", 0)
		if e is Transform3D:
			xf = e
	if p.has_method("teleport"):
		p.call("teleport", xf.origin, Sites.yaw_of(xf))


func _despawn(v: Node3D) -> void:
	if v == null or not is_instance_valid(v):
		return
	var vm := Game.get_system("vehicles")
	if vm != null and vm.has_method("despawn_vehicle"):
		vm.call("despawn_vehicle", v)
	else:
		v.queue_free()


func _fade_out() -> void:
	if UI != null and UI.has_method("fade_out"):
		await UI.fade_out(FADE)


func _fade_in() -> void:
	if UI != null and UI.has_method("fade_in"):
		await UI.fade_in(FADE)


func notify(text: String, kind: String = "info") -> void:
	if UI != null and UI.has_method("notify"):
		UI.notify(text, kind)


static func _bool(obj: Object, prop: String) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	var v: Variant = obj.get(prop)
	return v is bool and v


# =================================================================================================
# save provider "garage"
# =================================================================================================

func get_save_data() -> Dictionary:
	var list: Array = []
	for d: Dictionary in stored:
		list.append(d.duplicate(true))
	return {"version": SAVE_VERSION, "capacity": capacity, "stored": list, "spawn_inside": spawn_inside_on_load}


func load_save_data(d: Dictionary) -> void:
	stored.clear()
	var list: Variant = d.get("stored", [])
	if list is Array:
		for e: Variant in list:
			if e is Dictionary and str((e as Dictionary).get("spec_id", "")) != "":
				stored.append((e as Dictionary).duplicate(true))
	capacity = maxi(int(d.get("capacity", CAPACITY)), CAPACITY)
	_sync_t = 0.0
	if bool(d.get("spawn_inside", false)):
		var sh := get_helper("safehouse")
		if sh != null and sh.has_method("spawn_player_inside"):
			sh.call_deferred("spawn_player_inside")
