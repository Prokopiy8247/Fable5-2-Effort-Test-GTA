extends Node
## World system "debug" (BootManifest): the admin / cheat API behind the F1 admin menu
## (`gta/code/ui/screens/admin_menu.gd`), the performance overlay (F3) and a small text command
## interface for QA bots (`run_command`). Owner: TOOLS. Documentation: docs/ADMIN.md.
##
## Every call reaches other modules only through their public APIs and softly (Game.get_system,
## has_method, "prop" in obj, ResourceLoader.exists). A missing neighbour makes the matching call
## return false / null and `is_available(feature)` false - never an error.
##
## Command line (after `--`, applied once after EventBus.game_ready):
##   --adm_overlay                       show the performance overlay
##   --adm_cmd=tp hospital;wanted 2      run commands (see run_command) separated by ';'

const UI_STYLE_PATH := "res://gta/code/ui/ui_style.gd"
const SECTOR_SIZE := 100.0
const SECTOR_COLUMNS := "ABCDEF"
const GRID_MIN := -300.0
const GRID_CELLS := 6
const DISTRICTS: Array[String] = ["downtown", "midtown", "residential", "industrial", "waterfront", "beach", "hill", "airport"]
## Vehicle groups for the admin menu filter. "service" = police / emergency / taxi cars.
const VEHICLE_GROUPS: Array[String] = ["car", "service", "bike", "boat", "heli", "plane"]
const POLICE_UNITS: Array[String] = ["officer", "cruiser", "swat", "heli", "roadblock"]
const TOGGLE_SYSTEMS: Array[String] = ["traffic", "peds", "wildlife", "police", "emergency", "transit"]
const TIME_SCALE_MIN := 0.25
const TIME_SCALE_MAX := 2.0
const MAX_ADMIN_VEHICLES := 10       ## oldest admin-spawned vehicle is removed beyond this
const WEATHER_BLEND_SEC := 3.0
const FRAME_RING := 1024             ## frame-time samples kept (5 s at up to 200 fps)
const FRAME_WINDOW_USEC := 5000000   ## window for average FPS and 1 % low
const OVERLAY_LAYER := 11            ## above the UI autoload (layer 10)
const OVERLAY_REFRESH := 0.25        ## seconds between overlay text refreshes
const OVERLAY_WIDTH := 560.0
const FLOAT_DEPTH_FALLBACK := 1.42   ## player origin below the water surface while floating
const PERSON_MASK := Layers.WORLD | Layers.VEHICLE | Layers.PROP | Layers.GLASS | Layers.NPC
const SPAWN_MASK := Layers.WORLD | Layers.VEHICLE | Layers.PROP | Layers.GLASS | Layers.NPC | Layers.PLAYER
## Clearance boxes (half extents, metres) used to find room for a vehicle of each class.
const HALF_EXTENTS := {
	"car": Vector3(1.15, 0.8, 2.6),
	"car_large": Vector3(1.45, 1.3, 4.4),
	"bike": Vector3(0.5, 0.7, 1.2),
	"bicycle": Vector3(0.45, 0.6, 1.0),
	"boat": Vector3(1.5, 0.8, 4.0),
	"heli": Vector3(5.4, 1.6, 6.2),
	"plane": Vector3(6.5, 1.6, 6.0),
}
const CLASS_LABELS := {"car": "Car", "service": "Service", "bike": "Bike", "bicycle": "Bicycle", "boat": "Boat",
		"heli": "Helicopter", "plane": "Plane"}

var enabled: bool = true
var time_scale: float = 1.0              ## admin time scale (0.25 .. 2)
var mods_unlocked: bool = false          ## Game.flags free_shopping + unlock_all_mods
var overlay_origin := Vector2(40.0, 40.0)   ## top-left of the overlay panel (logical pixels)
var last_teleport: Dictionary = {}       ## {target, position, water, in_vehicle} of the last teleport
var last_spawn: Dictionary = {}          ## {spec_id, where, position} of the last vehicle spawn

var _admin_vehicles: Array = []
var _system_state: Dictionary = {}       ## system name -> bool as last toggled
var _district_cache: Dictionary = {}
var _frame_us := PackedInt32Array()
var _scratch := PackedInt32Array()
var _frame_head: int = 0
var _frame_count: int = 0
var _last_tick_us: int = 0
var _stats: Dictionary = {}
var _overlay_layer: CanvasLayer = null
var _overlay_view: Control = null
var _overlay_shown: bool = false
var _overlay_own: bool = false           ## overlay flag when the UI autoload has none
var _overlay_t: float = 0.0
var _style: Script = null
var _box := BoxShape3D.new()
var _capsule := CapsuleShape3D.new()
var _shape_query := PhysicsShapeQueryParameters3D.new()
var _graph_pts := PackedVector2Array()
var _ui_has_flag: bool = false           ## UI autoload exposes debug_overlay_visible (checked once)
var _basic_overlay: CanvasItem = null    ## the UI's own text overlay, hidden while ours shows
var _no_rids: Array[RID] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_frame_us.resize(FRAME_RING)
	_scratch.resize(FRAME_RING)
	_last_tick_us = Time.get_ticks_usec()
	_capsule.radius = 0.33
	_capsule.height = 1.7
	if ResourceLoader.exists(UI_STYLE_PATH):
		_style = load(UI_STYLE_PATH) as Script
	_ui_has_flag = "debug_overlay_visible" in UI
	EventBus.system_toggled.connect(_on_system_toggled)
	EventBus.game_ready.connect(_on_game_ready)
	if Game.is_ready:
		_on_game_ready.call_deferred()


func _exit_tree() -> void:
	if _overlay_shown:
		_set_gpu_measure(false)
	if time_scale > 1.001 and Engine.time_scale > 1.001:
		Engine.time_scale = 1.0
	Game.release_time_scale("debug")


## World-system hook (admin toggles). The debug system itself always stays on.
func set_enabled(on: bool) -> void:
	enabled = on


func reset_for_respawn() -> void:
	pass


func _on_game_ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a == "--adm_overlay":
			set_overlay_visible(true)
		elif a.begins_with("--adm_cmd="):
			for c in a.substr(10).split(";", false):
				print("[Debug] ", c.strip_edges(), " -> ", run_command(c))


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := now - _last_tick_us
	_last_tick_us = now
	_frame_us[_frame_head] = mini(dt, 2000000)
	_frame_head = (_frame_head + 1) % FRAME_RING
	_frame_count = mini(_frame_count + 1, FRAME_RING)
	# fast forward: Game.request_time_scale() clamps to 1.0, so a scale above 1 is applied here while
	# nobody else asks for slow motion (Game resets Engine.time_scale to 1.0 when the last request goes)
	if time_scale > 1.001 and Engine.time_scale == 1.0:
		Engine.time_scale = time_scale
	var want := is_overlay_visible()
	if want != _overlay_shown:
		_show_overlay(want)
	if _overlay_shown:
		_hide_basic_overlay()
		_overlay_t += float(dt) / 1000000.0
		if _overlay_t >= OVERLAY_REFRESH:
			_overlay_t = 0.0
			refresh_stats()
			_place_overlay()
			_overlay_view.queue_redraw()


# =================================================================================================
# availability (the admin menu greys out what is missing)
# =================================================================================================

## True when the feature behind an admin control can work right now. Features: player, teleport,
## vehicles, customise, weapons, parachute, scuba, appearance, wanted, never_wanted, bust,
## police_units, taxi, garage_delivery, garage_store, the TOGGLE_SYSTEMS names, traffic_density,
## ped_density, overlay.
func is_available(feature: String) -> bool:
	return unavailable_reason(feature) == ""


## "" when available, else a short reason for the menu hint.
func unavailable_reason(feature: String) -> String:
	var p := _player()
	match feature:
		"player":
			return "" if p != null else "no player"
		"teleport":
			if p == null:
				return "no player"
			return "" if Game.world != null else "world system not loaded"
		"vehicles":
			return "" if _vm() != null else "vehicles system not loaded"
		"customise":
			if not _screen_exists("mod_garage"):
				return "mod garage screen not built yet"
			return ""
		"weapons":
			return "" if _inventory() != null else "player has no weapon inventory"
		"parachute":
			return "" if p != null and p.has_method("give_parachute") else "player has no parachute hook"
		"scuba":
			return "" if p != null and "has_scuba" in p else "player has no scuba hook"
		"breath":
			return "" if p != null and "breath" in p else "no player"
		"appearance":
			var vis := _visual()
			return "" if vis != null and vis.has_method("randomize_appearance") else "character visual missing"
		"wanted":
			return ""
		"never_wanted":
			return "" if "enabled" in Wanted or Wanted.has_method("set_enabled") else "wanted system has no switch"
		"bust":
			return "" if Wanted.has_method("bust") else "arrest flow not built yet"
		"police_units":
			var pol := Game.get_system("police")
			return "" if pol != null and pol.has_method("spawn_unit") else "police system not built yet"
		"clear_police":
			var pol2 := Game.get_system("police")
			return "" if pol2 != null and pol2.has_method("clear_units") else "police system not built yet"
		"taxi":
			return "" if _taxi_call_method() != "" else "taxi service not built yet"
		"garage_delivery":
			var g := Game.get_system("garage")
			return "" if g != null and g.has_method("deliver_personal_vehicle") else "garage system not built yet"
		"garage_store":
			var g2 := Game.get_system("garage")
			return "" if g2 != null and g2.has_method("store_vehicle") else "garage system not built yet"
		"traffic_density", "ped_density", "overlay", "time", "weather", "skills", "money", "health":
			return ""
		_:
			if feature in TOGGLE_SYSTEMS:
				return "" if Game.has_system(feature) else "%s system not built yet" % feature
			if feature.begins_with("screen:"):
				return "" if _screen_exists(feature.substr(7)) else "screen not built yet"
	return ""


# =================================================================================================
# teleport
# =================================================================================================

## Every teleport destination: 8 districts (id "district:<name>") + every named location of the
## world. Entry: {id, name, kind ("district" | "location"), district, position: Vector3, yaw, water}.
func get_teleport_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var w := Game.world
	if w == null:
		return out
	for d: String in DISTRICTS:
		var t := _district_target(d)
		if bool(t.get("ok", false)):
			out.append({"id": "district:" + d, "name": d.capitalize(), "kind": "district", "district": d,
					"position": t["position"], "yaw": float(t["yaw"]), "water": false})
	var locs := _locations()
	var names: Array = locs.keys()
	names.sort()
	for n: Variant in names:
		var xf: Transform3D = locs[n]
		out.append({"id": str(n), "name": str(n).capitalize(), "kind": "location", "district": district_at(xf.origin),
				"position": xf.origin, "yaw": _yaw_of(xf.basis), "water": _is_water_location(xf.origin)})
	return out


## Resolves a target into {ok, name, position, yaw, water}. Accepts a location name, a district
## id (prefix "district:" or a bare district id that is not also a location), "waypoint", a
## Vector3 or a Transform3D.
func resolve_target(target: Variant) -> Dictionary:
	if target is Vector3:
		var v: Vector3 = target
		return {"ok": true, "name": "%.0f, %.0f, %.0f" % [v.x, v.y, v.z], "position": v, "yaw": _view_yaw(),
				"water": _is_water_location(v)}
	if target is Transform3D:
		var xf: Transform3D = target
		return {"ok": true, "name": "point", "position": xf.origin, "yaw": _yaw_of(xf.basis), "water": _is_water_location(xf.origin)}
	var s := str(target).strip_edges()
	if s == "":
		return {"ok": false}
	if s == "waypoint":
		if "nav" in UI and UI.has_waypoint():
			var wp: Vector3 = UI.nav.waypoint
			var h := Game.ground_height(wp.x, wp.z)
			var wpos := Vector3(wp.x, h, wp.z)
			return {"ok": true, "name": "Waypoint", "position": wpos, "yaw": _view_yaw(), "water": _is_water_location(wpos)}
		return {"ok": false}
	var district := ""
	if s.begins_with("district:"):
		district = s.substr(9)
	elif s in DISTRICTS and not _locations().has(s):
		district = s
	if district != "":
		var t := _district_target(district)
		if not bool(t.get("ok", false)):
			return {"ok": false}
		return {"ok": true, "name": district.capitalize(), "position": t["position"], "yaw": float(t["yaw"]), "water": false}
	var locs := _locations()
	if locs.has(s):
		var lx: Transform3D = locs[s]
		return {"ok": true, "name": s.capitalize(), "position": lx.origin, "yaw": _yaw_of(lx.basis),
				"water": _is_water_location(lx.origin)}
	return {"ok": false}


## Teleports the player (and the vehicle they drive when it suits the destination: cars / bikes /
## aircraft to land, boats to water; otherwise the player leaves it). Land destinations end on a
## free spot of solid ground (capsule-tested); water destinations float the player at the surface.
func teleport_player(target: Variant, keep_vehicle: bool = true) -> bool:
	var p := _player()
	if p == null or bool(p.get("is_dead")):
		_notify("Teleport: no living player", "bad")
		return false
	var dest := resolve_target(target)
	if not bool(dest.get("ok", false)):
		_notify("Teleport: unknown destination '%s'" % str(target), "bad")
		return false
	var pos: Vector3 = dest["position"]
	var yaw: float = dest["yaw"]
	var water: bool = dest["water"]
	var veh := Game.get_player_vehicle()
	if veh != null and keep_vehicle and _teleport_vehicle(veh, pos, yaw, water):
		last_teleport = {"target": str(target), "position": veh.global_position, "water": water, "in_vehicle": true}
		_notify("Teleported to %s" % str(dest["name"]))
		return true
	var final := pos
	if water:
		final = Vector3(pos.x, _water_surface(pos.x, pos.z) - _float_depth(p), pos.z)
	else:
		final = find_safe_spot(pos)
	if p.has_method("teleport"):
		p.call("teleport", final, yaw)
	else:
		p.global_position = final
	last_teleport = {"target": str(target), "position": final, "water": water, "in_vehicle": false}
	_notify("Teleported to %s" % str(dest["name"]))
	return true


## Nearest free standing spot (capsule test against world, vehicles, props, NPCs) on solid ground
## around `pos`, preferring the same height level. Returns `pos` if nothing better was found.
func find_safe_spot(pos: Vector3) -> Vector3:
	var r := _find_clear_spot(pos, 0.0, _capsule, 0.05 + _capsule.height * 0.5, 20.0, 0.0, PERSON_MASK, _no_rids, false)
	if bool(r.get("ok", false)):
		return r["position"]
	var w := Game.world
	if w != null and "walk" in w and w.walk != null and w.walk.has_method("get_nearest_point"):
		var q: Vector3 = w.walk.get_nearest_point(pos)
		if q != Vector3.INF:
			var r2 := _find_clear_spot(q, 0.0, _capsule, 0.05 + _capsule.height * 0.5, 12.0, 0.0, PERSON_MASK, _no_rids, false)
			if bool(r2.get("ok", false)):
				return r2["position"]
	return pos


# =================================================================================================
# vehicles
# =================================================================================================

## Every registered vehicle spec with its state for the menu: {id, name, vehicle_class, group,
## can_spawn, reason, seats, top_speed_kmh}. group_filter: "" or one of VEHICLE_GROUPS.
func get_vehicle_specs(group_filter: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var vm := _vm()
	for id: Variant in Registry.ids("vehicles"):
		var spec: Variant = Registry.get_def("vehicles", str(id))
		if not (spec is Object):
			continue
		var so := spec as Object
		var cls := str(so.get("vehicle_class"))
		var group := vehicle_group(so)
		if group_filter != "" and group != group_filter:
			continue
		var reason := ""
		var ok := false
		if vm == null:
			reason = "vehicles system not loaded"
		elif vm.has_method("can_spawn") and bool(vm.call("can_spawn", str(id))):
			ok = true
		elif so.has_method("has_model") and not bool(so.call("has_model")):
			reason = "model missing"
		else:
			reason = "%s physics not built yet" % str(CLASS_LABELS.get(cls, cls)).to_lower()
		var dn := str(so.get("display_name"))
		out.append({"id": str(id), "name": dn if dn != "" else str(id).capitalize(), "vehicle_class": cls, "group": group,
				"can_spawn": ok, "reason": reason, "seats": int(so.get("seats")),
				"top_speed_kmh": float(so.get("top_speed")) * 3.6})
	return out


## Menu group of a VehicleSpec (or spec id): car, service, bike, boat, heli, plane.
func vehicle_group(spec_or_id: Variant) -> String:
	var so: Object = null
	if spec_or_id is Object:
		so = spec_or_id
	else:
		var d: Variant = Registry.get_def("vehicles", str(spec_or_id))
		so = d as Object if d is Object else null
	if so == null:
		return "car"
	var cls := str(so.get("vehicle_class"))
	match cls:
		"bike", "bicycle":
			return "bike"
		"boat", "heli", "plane":
			return cls
	if bool(so.get("is_police")) or bool(so.get("is_emergency")) or bool(so.get("is_taxi")):
		return "service"
	return "car"


## Where spec_id would spawn for the player right now: {ok, transform, where, reason}.
## Cars / bikes: free ground in front of the camera (road fallback); boats: nearest deep water;
## helicopters: free ground nearby with open sky; planes: the runway start.
func find_vehicle_spawn(spec_id: String, enter: bool = false) -> Dictionary:
	var spec: Variant = Registry.get_def("vehicles", spec_id)
	var cls := str((spec as Object).get("vehicle_class")) if spec is Object else "car"
	var half := _class_half_extents(cls, spec)
	var origin := Game.get_player_position()
	var vyaw := _view_yaw()
	var fwd := Vector3(-sin(vyaw), 0.0, -cos(vyaw))
	var veh := Game.get_player_vehicle()
	var exclude: Array[RID] = []
	if veh is CollisionObject3D:
		exclude.append((veh as CollisionObject3D).get_rid())
	match cls:
		"plane":
			return _plane_spot(half)
		"boat":
			return _water_spot(origin, vyaw, half, exclude)
		"heli":
			var hc := origin + fwd * (half.z + 5.0)
			var hs := _find_clear_spot(hc, vyaw, _box_of(half), half.y + 0.35, 45.0, 10.0, SPAWN_MASK, exclude, true)
			if bool(hs.get("ok", false)):
				return {"ok": true, "transform": Transform3D(Basis(Vector3.UP, vyaw), hs["position"]), "where": "nearby"}
			return _nearest_spawn_point(["heli"], ["airport_helipad", "rooftop_helipad", "harbor_helipad"], origin, "helipad")
	# land vehicles
	var yaw := vyaw if enter else vyaw + PI * 0.5
	var dist := (half.z + 2.0) if enter else (half.x + 3.0)
	var center := origin + fwd * dist
	var on_land := _ground_hit(origin.x, origin.z, origin.y + 1.0, 4.0)
	if not on_land.is_empty() and _water_depth(origin.x, origin.z) < 0.3:
		var s := _find_clear_spot(center, yaw, _box_of(half), half.y + 0.35, 25.0, 0.0, SPAWN_MASK, exclude, true)
		if bool(s.get("ok", false)):
			return {"ok": true, "transform": Transform3D(Basis(Vector3.UP, yaw), s["position"]), "where": "in front"}
	# in the water, in the air or boxed in: the nearest road
	var road := _nearest_road(origin)
	if bool(road.get("ok", false)):
		var rpos: Vector3 = road["position"]
		var ryaw: float = road["yaw"]
		var s2 := _find_clear_spot(rpos, ryaw, _box_of(half), half.y + 0.35, 30.0, 0.0, SPAWN_MASK, exclude, true)
		if bool(s2.get("ok", false)):
			return {"ok": true, "transform": Transform3D(Basis(Vector3.UP, ryaw), s2["position"]), "where": "nearest road"}
	return _nearest_spawn_point(["parking"], ["parking_garage"], origin, "parking")


## Spawns spec_id for the player on a suitable surface (see find_vehicle_spawn). enter = put the
## player in the driver seat at once. Admin vehicles beyond MAX_ADMIN_VEHICLES are recycled.
func spawn_vehicle_for_player(spec_id: String, enter: bool = false) -> Node3D:
	var vm := _vm()
	if vm == null or not vm.has_method("spawn_vehicle"):
		_notify("Vehicles system not available", "bad")
		return null
	if vm.has_method("can_spawn") and not bool(vm.call("can_spawn", spec_id)):
		_notify("%s cannot spawn yet (model or physics missing)" % spec_id, "bad")
		return null
	var place := find_vehicle_spawn(spec_id, enter)
	if not bool(place.get("ok", false)):
		_notify("No free space found for %s" % spec_id, "bad")
		return null
	var xf: Transform3D = place["transform"]
	var v: Variant = vm.call("spawn_vehicle", spec_id, xf, {"owner_tag": "player", "engine_on": enter})
	if not (v is Node3D) or not is_instance_valid(v):
		_notify("Spawning %s failed" % spec_id, "bad")
		return null
	var vn := v as Node3D
	_track_admin_vehicle(vn)
	last_spawn = {"spec_id": spec_id, "where": str(place.get("where", "")), "position": xf.origin}
	var p := _player()
	var name_txt := _vehicle_name(vn)
	if enter and p != null and p.has_method("enter_vehicle") and not bool(p.get("is_dead")):
		p.call("enter_vehicle", vn, 0, true)
		_notify("%s ready (%s)" % [name_txt, str(place.get("where", ""))], "good")
	else:
		var far := xf.origin.distance_to(Game.get_player_position()) > 60.0
		if far and UI.has_method("set_waypoint"):
			UI.set_waypoint(xf.origin)
		_notify("%s spawned %s%s" % [name_txt, str(place.get("where", "")), " - waypoint set" if far else ""], "good")
	return vn


## The vehicle admin actions work on: the one the player sits in, else the nearest within 10 m.
func get_target_vehicle() -> Node3D:
	var v := Game.get_player_vehicle()
	if v != null:
		return v
	var vm := _vm()
	if vm != null and vm.has_method("get_nearest_vehicle"):
		var n: Variant = vm.call("get_nearest_vehicle", Game.get_player_position(), 10.0, null)
		if is_instance_valid(n) and n is Node3D:
			return n
	return null


func repair_current_vehicle() -> bool:
	var v := get_target_vehicle()
	if v == null or not v.has_method("repair"):
		_notify("No vehicle to repair", "warn")
		return false
	v.call("repair")
	_notify("%s repaired" % _vehicle_name(v), "good")
	return true


## Puts the target vehicle back on its wheels (same heading, lifted 1 m).
func flip_current_vehicle() -> bool:
	var v := get_target_vehicle()
	if v == null:
		_notify("No vehicle to flip", "warn")
		return false
	var fwd := -v.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		fwd = v.global_basis.y
		fwd.y = 0.0
	var yaw := atan2(-fwd.x, -fwd.z) if fwd.length_squared() > 0.0001 else 0.0
	var pos := v.global_position
	var g := _ground_hit(pos.x, pos.z, pos.y + 2.0, 8.0)
	var y := (Vector3(g["position"]).y if not g.is_empty() else pos.y) + 0.6
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, maxf(y, pos.y), pos.z))
	if v.has_method("teleport"):
		v.call("teleport", xf)
	else:
		v.global_transform = xf
	_notify("%s flipped upright" % _vehicle_name(v), "good")
	return true


## Opens the vehicle customisation screen anywhere (mod garage screen, `UI.SCREENS["mod_garage"]`).
func open_customisation() -> bool:
	if not _screen_exists("mod_garage"):
		_notify("Customisation screen not available yet", "warn")
		return false
	var v := get_target_vehicle()
	if v == null:
		_notify("Get in (or next to) a vehicle first", "warn")
		return false
	if UI.is_screen_open("admin"):
		UI.close_screen("admin")
	var s: Control = UI.open_screen("mod_garage", {"vehicle": v, "anywhere": true, "source": "admin", "free": mods_unlocked})
	return s != null


## Unlock every modification option: Game.flags["unlock_all_mods"] and ["free_shopping"]
## (ARCHITECTURE_WAVE2 W2.6: shops make every price 0 while free_shopping is set).
func set_mods_unlocked(on: bool) -> void:
	mods_unlocked = on
	if on:
		Game.flags["unlock_all_mods"] = true
		Game.flags["free_shopping"] = true
	else:
		Game.flags.erase("unlock_all_mods")
		Game.flags.erase("free_shopping")
	_notify("All modifications %s" % ("unlocked, shopping is free" if on else "back to normal prices"), "info")


## Removes every vehicle this system spawned (except the one the player sits in).
func clear_admin_vehicles() -> int:
	var vm := _vm()
	var pv := Game.get_player_vehicle()
	var n := 0
	for v: Variant in _admin_vehicles.duplicate():
		if is_instance_valid(v) and v is Node3D and v != pv:
			if vm != null and vm.has_method("despawn_vehicle"):
				vm.call("despawn_vehicle", v)
			else:
				(v as Node3D).queue_free()
			n += 1
	_admin_vehicles = _admin_vehicles.filter(func(x: Variant) -> bool: return is_instance_valid(x) and x is Node3D and x == pv)
	return n


func get_admin_vehicles() -> Array:
	_prune_admin_vehicles()
	return _admin_vehicles.duplicate()


## VehicleManager.repair_all(): every vehicle in the world, wrecks included.
func repair_all_vehicles() -> bool:
	var vm := _vm()
	if vm == null or not vm.has_method("repair_all"):
		return false
	vm.call("repair_all")
	_notify("All vehicles repaired", "good")
	return true


## Pickup system: put every world pickup back and clear dropped ones.
func respawn_pickups() -> bool:
	var ps := Game.get_system("pickups")
	if ps == null or not ps.has_method("respawn_all"):
		return false
	ps.call("respawn_all")
	if ps.has_method("clear_dropped"):
		ps.call("clear_dropped")
	_notify("Pickups respawned", "good")
	return true


# =================================================================================================
# weapons
# =================================================================================================

## Registered weapons for the menu: {id, name, slot, owned, in_mag, reserve, uses_ammo}.
func get_weapon_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inv := _inventory()
	for id: Variant in Registry.ids("weapons"):
		var spec: Variant = Registry.get_def("weapons", str(id))
		if not (spec is Object):
			continue
		var so := spec as Object
		var owned: bool = inv != null and bool(inv.call("has_weapon", str(id)))
		var ammo: Dictionary = {}
		if owned and inv.has_method("get_ammo"):
			var a: Variant = inv.call("get_ammo", str(id))
			if a is Dictionary:
				ammo = a
		var dn := str(so.get("display_name"))
		out.append({"id": str(id), "name": dn if dn != "" else str(id).capitalize(), "slot": str(so.get("slot")),
				"owned": owned, "in_mag": int(ammo.get("in_mag", -1)), "reserve": int(ammo.get("reserve", -1)),
				"uses_ammo": str(so.get("ammo_type")) != ""})
	out.sort_custom(_weapon_less)
	return out


func _weapon_less(a: Dictionary, b: Dictionary) -> bool:
	var ka := _slot_order(a["slot"]) * 2 + (0 if str(a["id"]) == "fists" else 1)
	var kb := _slot_order(b["slot"]) * 2 + (0 if str(b["id"]) == "fists" else 1)
	if ka != kb:
		return ka < kb
	return str(a["name"]) < str(b["name"])


## Gives one weapon with full ammunition (and draws it when `equip`).
func give_weapon(id: String, equip: bool = true) -> bool:
	var inv := _inventory()
	if inv == null or not Registry.has_def("weapons", id):
		return false
	inv.call("give_weapon", id)
	var spec: Variant = Registry.get_def("weapons", id)
	if spec is Object and str((spec as Object).get("ammo_type")) != "" and inv.has_method("add_ammo"):
		inv.call("add_ammo", str((spec as Object).get("ammo_type")), 100000)
	if equip and inv.has_method("equip") and Game.get_player_vehicle() == null:
		inv.call("equip", id)
	return bool(inv.call("has_weapon", id))


## Every registered weapon with full ammunition. Returns the number of weapons owned afterwards.
func give_all_weapons() -> int:
	var inv := _inventory()
	if inv == null:
		return 0
	if inv.has_method("give_all_weapons"):
		inv.call("give_all_weapons")
	else:
		for id: Variant in Registry.ids("weapons"):
			inv.call("give_weapon", str(id))
	refill_ammo()
	var n := (inv.call("get_weapons") as Array).size() if inv.has_method("get_weapons") else 0
	_notify("All weapons (%d) with full ammunition" % n, "good")
	return n


func refill_ammo() -> bool:
	var inv := _inventory()
	if inv == null or not inv.has_method("refill_all"):
		return false
	inv.call("refill_all")
	return true


## Installs every functional attachment (suppressor, scope, flashlight, grip, extended magazine)
## each owned weapon accepts. Finishes are cosmetic and left alone. Returns attachments installed.
func give_all_attachments() -> int:
	var inv := _inventory()
	if inv == null or not inv.has_method("add_attachment"):
		return 0
	var n := 0
	for w: Variant in (inv.call("get_weapons") as Array):
		var wid := str(w)
		for att: Variant in (inv.call("get_compatible_attachments", wid) as Array):
			var def: Variant = Registry.get_def("attachments", str(att))
			if def is Object and str((def as Object).get("kind")) == "finish":
				continue
			if bool(inv.call("add_attachment", wid, str(att))):
				n += 1
	_notify("%d attachments installed" % n, "good")
	return n


func set_infinite_ammo(on: bool) -> bool:
	var inv := _inventory()
	if inv == null or not "infinite_ammo" in inv:
		return false
	inv.set("infinite_ammo", on)
	return true


func is_infinite_ammo() -> bool:
	var inv := _inventory()
	return inv != null and bool(inv.get("infinite_ammo"))


# =================================================================================================
# player
# =================================================================================================

func set_health(value: float) -> bool:
	var p := _player()
	if p == null or bool(p.get("is_dead")):
		return false
	var mh := float(p.get("max_health")) if "max_health" in p else 100.0
	p.set("health", clampf(value, 1.0, mh))
	_emit_health(p)
	return true


func set_armor(value: float) -> bool:
	var p := _player()
	if p == null or bool(p.get("is_dead")):
		return false
	var ma := float(p.get("max_armor")) if "max_armor" in p else 100.0
	p.set("armor", clampf(value, 0.0, ma))
	_emit_health(p)
	return true


## Full health and armour.
func heal_full() -> bool:
	var p := _player()
	if p == null:
		return false
	return set_health(float(p.get("max_health"))) and set_armor(float(p.get("max_armor")))


func set_money(amount: int) -> void:
	Game.set_money(maxi(amount, 0))


func add_money(amount: int) -> void:
	Game.add_money(amount)


func set_invulnerable(on: bool) -> void:
	Game.invulnerable = on
	_notify("Invulnerability %s" % ("ON" if on else "off"), "info")


func max_skills() -> void:
	Skills.set_all(100.0)
	_notify("All skills maxed", "skill")


func reset_skills() -> void:
	Skills.reset()
	_notify("Skills reset", "skill")


func give_parachute() -> bool:
	var p := _player()
	if p == null or not p.has_method("give_parachute"):
		return false
	p.call("give_parachute")
	_notify("Parachute equipped", "good")
	return true


func set_scuba(on: bool) -> bool:
	var p := _player()
	if p == null or not "has_scuba" in p:
		return false
	if on and p.has_method("give_scuba"):
		p.call("give_scuba")
	else:
		p.set("has_scuba", on)
	_notify("Scuba gear %s" % ("on" if on else "off"), "info")
	return true


func has_scuba() -> bool:
	var p := _player()
	return p != null and bool(p.get("has_scuba"))


## Lung capacity back to full (breath = 1).
func refill_breath() -> bool:
	var p := _player()
	if p == null or not "breath" in p:
		return false
	p.set("breath", 1.0)
	return true


## A random everyday look (body, hair, clothes, colours) through CharacterVisual.
func randomize_appearance(seed_value: int = -1) -> bool:
	var p := _player()
	var vis := _visual()
	if p == null or vis == null or not vis.has_method("randomize_appearance"):
		return false
	var s := seed_value if seed_value >= 0 else randi()
	vis.call("randomize_appearance", "civilian_f" if s % 2 == 1 else "civilian_m", s)
	if p.has_method("set_appearance") and vis.has_method("get_appearance"):
		p.call("set_appearance", vis.call("get_appearance"))
	return true


## Kills the player (tests the death -> respawn flow).
func kill_player() -> bool:
	var p := _player()
	if p == null or not p.has_method("kill") or bool(p.get("is_dead")):
		return false
	var was := Game.invulnerable
	Game.invulnerable = false
	p.call("kill", "admin")
	Game.invulnerable = was
	return true


# =================================================================================================
# wanted / police
# =================================================================================================

func set_wanted(level: int) -> void:
	level = clampi(level, 0, 5)
	if level == 0:
		Wanted.clear("cheat")
	else:
		Wanted.set_level(level, "cheat")


func clear_wanted() -> void:
	Wanted.clear("cheat")


## Never wanted: the wanted system ignores every crime report while on.
func set_never_wanted(on: bool) -> bool:
	if Wanted.has_method("set_enabled"):
		Wanted.call("set_enabled", not on)
	elif "enabled" in Wanted:
		Wanted.set("enabled", not on)
	else:
		return false
	if on:
		Wanted.clear("cheat")
	_notify("Never wanted %s" % ("ON" if on else "off"), "info")
	return true


func is_never_wanted() -> bool:
	return "enabled" in Wanted and not bool(Wanted.get("enabled"))


## Completes an arrest (tests the busted flow; needs Wanted.bust from the police module).
func bust_player() -> bool:
	if not Wanted.has_method("bust"):
		return false
	Wanted.call("bust")
	return true


## Asks the police dispatcher for one unit near the player. kind: officer, cruiser, swat, heli,
## roadblock. Returns the unit (or null).
func spawn_police(kind: String = "cruiser") -> Node:
	var pol := Game.get_system("police")
	if pol == null or not pol.has_method("spawn_unit"):
		_notify("Police dispatch not available yet", "warn")
		return null
	var u: Variant = pol.call("spawn_unit", kind, Game.get_player_position())
	if is_instance_valid(u) and u is Node:
		_notify("Police %s dispatched" % kind, "info")
		return u
	_notify("Police %s could not be placed" % kind, "warn")
	return null


func clear_police() -> bool:
	var pol := Game.get_system("police")
	if pol == null or not pol.has_method("clear_units"):
		return false
	pol.call("clear_units")
	return true


# =================================================================================================
# world
# =================================================================================================

func set_time(hour: float) -> void:
	WorldClock.set_hour(fposmod(hour, 24.0))


func set_clock_paused(on: bool) -> void:
	if WorldClock.has_method("set_paused"):
		WorldClock.set_paused(on)
	else:
		WorldClock.paused = on


func is_clock_paused() -> bool:
	return bool(WorldClock.paused)


## Weather by id (Weather.TYPES). instant = no blend. Automatic weather changes are switched off
## so the chosen weather stays (set_auto_weather(true) to resume them).
func set_weather(id: String, instant: bool = false) -> bool:
	if not (id in Weather.TYPES):
		return false
	if Weather.has_method("set_auto_cycle"):
		Weather.set_auto_cycle(false)
	if instant and Weather.has_method("snap_weather"):
		Weather.snap_weather(id)
	else:
		Weather.set_weather(id, WEATHER_BLEND_SEC)
	return true


func set_auto_weather(on: bool) -> void:
	if Weather.has_method("set_auto_cycle"):
		Weather.set_auto_cycle(on)
	else:
		Weather.auto_cycle = on


func is_auto_weather() -> bool:
	return bool(Weather.auto_cycle)


## Enables / disables a running world system through Game.set_system_enabled. false if the
## system does not exist.
func toggle_system(system_name: String, on: bool) -> bool:
	if not Game.has_system(system_name):
		return false
	Game.set_system_enabled(system_name, on)
	_system_state[system_name] = on
	return true


func is_system_enabled(system_name: String) -> bool:
	var s := Game.get_system(system_name)
	if s == null:
		return false
	if _system_state.has(system_name):
		return bool(_system_state[system_name])
	if "enabled" in s:
		return bool(s.get("enabled"))
	return s.process_mode != Node.PROCESS_MODE_DISABLED


## Traffic / pedestrian density multiplier (0 .. 1.5): Settings + the system's set_density().
## kind: "traffic" or "peds".
func set_density(kind: String, value: float) -> void:
	value = clampf(value, 0.0, 1.5)
	var key := "traffic_density" if kind == "traffic" else "ped_density"
	Settings.set_value(key, value, false)
	var s := Game.get_system(kind)
	if s != null and s.has_method("set_density"):
		s.call("set_density", value)


func get_density(kind: String) -> float:
	return float(Settings.get_value("traffic_density" if kind == "traffic" else "ped_density"))


# =================================================================================================
# services (next-wave systems; each one is optional)
# =================================================================================================

## Calls a taxi to the player through the taxi system. Returns true if it accepted.
func call_taxi() -> bool:
	var m := _taxi_call_method()
	if m == "":
		_notify("Taxi service not available yet", "warn")
		return false
	var t := Game.get_system("taxi")
	var r: Variant = t.call(m) if t.get_method_argument_count(m) == 0 else t.call(m, Game.get_player_position())
	var ok: bool = r != null and not (r is bool and not bool(r))
	_notify("Taxi on its way" if ok else "No taxi available", "info" if ok else "warn")
	return ok


## Brings the personal vehicle from the garage to the player (W2.7 contract).
func deliver_personal_vehicle() -> Node3D:
	var g := Game.get_system("garage")
	if g == null or not g.has_method("deliver_personal_vehicle"):
		_notify("Garage service not available yet", "warn")
		return null
	var v: Variant = g.call("deliver_personal_vehicle", Game.get_player_position())
	if is_instance_valid(v) and v is Node3D:
		_notify("Personal vehicle delivered", "good")
		return v
	_notify("No personal vehicle to deliver", "warn")
	return null


## Stores the player's (or the nearest) vehicle in the garage (W2.7 contract).
func store_current_vehicle() -> bool:
	var g := Game.get_system("garage")
	var v := get_target_vehicle()
	if g == null or not g.has_method("store_vehicle") or v == null:
		return false
	var ok := bool(g.call("store_vehicle", v))
	_notify("Vehicle stored in the garage" if ok else "Garage is full", "good" if ok else "warn")
	return ok


func _taxi_call_method() -> String:
	var t := Game.get_system("taxi")
	if t == null:
		return ""
	for m: String in ["call_taxi", "request_taxi", "summon_taxi"]:
		if t.has_method(m):
			return m
	return ""


# =================================================================================================
# debug: time scale, overlay, stats
# =================================================================================================

## Simulation speed 0.25 .. 2. Slow motion goes through Game.request_time_scale("debug");
## fast forward is applied here while no other system asks for slow motion.
func set_time_scale(s: float) -> void:
	time_scale = clampf(s, TIME_SCALE_MIN, TIME_SCALE_MAX)
	if time_scale < 0.999:
		Game.request_time_scale("debug", time_scale)
	else:
		Game.release_time_scale("debug")
		if time_scale > 1.001 and Engine.time_scale == 1.0:
			Engine.time_scale = time_scale


## The overlay follows UI.debug_overlay_visible (F3 and the pause-menu setting toggle it).
func set_overlay_visible(on: bool) -> void:
	if UI.has_method("set_debug_overlay"):
		UI.set_debug_overlay(on)
	else:
		_overlay_own = on


func toggle_overlay() -> void:
	set_overlay_visible(not is_overlay_visible())


func is_overlay_visible() -> bool:
	if _ui_has_flag:
		return bool(UI.debug_overlay_visible)
	return _overlay_own


## The admin menu moves the overlay next to its panel while it is open.
func set_overlay_origin(p: Vector2) -> void:
	overlay_origin = p
	_place_overlay()


## 100 m grid cell over the island (A..F west to east, 1..6 north to south), "OFF" outside.
func get_sector(pos: Vector3) -> String:
	var cx := int(floor((pos.x - GRID_MIN) / SECTOR_SIZE))
	var cz := int(floor((pos.z - GRID_MIN) / SECTOR_SIZE))
	if cx < 0 or cx >= GRID_CELLS or cz < 0 or cz >= GRID_CELLS:
		return "OFF"
	return "%s%d" % [SECTOR_COLUMNS[cx], cz + 1]


func district_at(pos: Vector3) -> String:
	var w := Game.world
	if w != null and w.has_method("get_district"):
		return str(w.call("get_district", pos))
	return ""


## Average FPS and 1 % low over the last 5 s of real frame times.
## {frames, avg_fps, low_1_fps, avg_ms, worst_ms, last_ms}
func get_frame_stats() -> Dictionary:
	var n := 0
	var total := 0
	var idx := _frame_head
	while n < _frame_count:
		idx = (idx - 1 + FRAME_RING) % FRAME_RING
		var d := _frame_us[idx]
		if n > 0 and total + d > FRAME_WINDOW_USEC:
			break
		_scratch[n] = d
		total += d
		n += 1
	if n == 0 or total <= 0:
		return {"frames": 0, "avg_fps": 0.0, "low_1_fps": 0.0, "avg_ms": 0.0, "worst_ms": 0.0, "last_ms": 0.0}
	# worst 1 % (at least one frame): partial selection into the front of _scratch, no allocation
	var k := maxi(1, int(float(n) / 100.0))
	for i in k:
		var best := i
		for j in range(i + 1, n):
			if _scratch[j] > _scratch[best]:
				best = j
		var tmp := _scratch[i]
		_scratch[i] = _scratch[best]
		_scratch[best] = tmp
	var worst_sum := 0
	for i in k:
		worst_sum += _scratch[i]
	var last := _frame_us[(_frame_head - 1 + FRAME_RING) % FRAME_RING]
	return {"frames": n, "avg_fps": float(n) * 1000000.0 / float(total),
			"low_1_fps": 1000000.0 * float(k) / float(maxi(worst_sum, 1)),
			"avg_ms": float(total) / float(n) / 1000.0, "worst_ms": float(_scratch[0]) / 1000.0, "last_ms": float(last) / 1000.0}


## Snapshot of everything the overlay shows (also handy for QA bots). Refreshed in place.
func refresh_stats() -> Dictionary:
	var fs := get_frame_stats()
	for k: Variant in fs:
		_stats[k] = fs[k]
	_stats["fps"] = Engine.get_frames_per_second()
	_stats["cpu_ms"] = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_stats["physics_ms"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var vp_rid := get_viewport().get_viewport_rid()
	_stats["gpu_ms"] = RenderingServer.viewport_get_measured_render_time_gpu(vp_rid) if _overlay_shown else 0.0
	_stats["draw_calls"] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_stats["primitives"] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_stats["objects"] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	_stats["vram_mb"] = float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0
	_stats["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var tree := get_tree()
	_stats["vehicles"] = tree.get_node_count_in_group(&"vehicle")
	_stats["peds"] = tree.get_node_count_in_group(&"ped")
	_stats["npcs"] = tree.get_node_count_in_group(&"npc")
	_stats["police"] = tree.get_node_count_in_group(&"police")
	_stats["animals"] = tree.get_node_count_in_group(&"animal")
	var pos := Game.get_player_position()
	_stats["position"] = pos
	_stats["heading_deg"] = fposmod(-rad_to_deg(_view_yaw()), 360.0)
	_stats["district"] = district_at(pos)
	_stats["sector"] = get_sector(pos)
	_stats["time"] = WorldClock.get_time_string()
	_stats["phase"] = WorldClock.get_phase()
	_stats["weather"] = str(Weather.current)
	_stats["time_scale"] = Engine.time_scale
	_stats["wanted"] = int(Wanted.level)
	return _stats


func get_stats() -> Dictionary:
	return refresh_stats().duplicate()


# =================================================================================================
# text commands (QA bots, --adm_cmd)
# =================================================================================================

## Runs one command, returns "ok ..." or "error ...". Commands:
## tp <target|x y z>, veh <spec> [enter], weapon <id>, weapons, ammo, attachments, god [on|off],
## money <n>, health <n>, armor <n>, heal, wanted <0-5>, neverwanted [on|off], police <kind>,
## time <hour>, weather <id>, sys <name> <on|off>, density <traffic|peds> <0..1.5>, repair, flip,
## skills <max|reset>, parachute, scuba [on|off], breath, appearance, taxi, scale <0.25..2>,
## overlay [on|off], stats
func run_command(line: String) -> String:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return "error empty"
	var cmd := parts[0].to_lower()
	var a1 := parts[1] if parts.size() > 1 else ""
	var a2 := parts[2] if parts.size() > 2 else ""
	var on := a1.to_lower() != "off" and a1 != "0"
	match cmd:
		"tp", "teleport":
			if parts.size() >= 4 and a1.is_valid_float():
				return _res(teleport_player(Vector3(float(a1), float(a2), float(parts[3]))))
			return _res(teleport_player(a1))
		"veh", "vehicle":
			return _res(spawn_vehicle_for_player(a1, a2 == "enter") != null)
		"weapon":
			return _res(give_weapon(a1))
		"weapons":
			return _res(give_all_weapons() > 0)
		"ammo":
			return _res(refill_ammo())
		"attachments":
			return _res(give_all_attachments() >= 0)
		"god":
			set_invulnerable(on)
		"money":
			set_money(int(a1))
		"health":
			return _res(set_health(float(a1)))
		"armor", "armour":
			return _res(set_armor(float(a1)))
		"heal":
			return _res(heal_full())
		"wanted":
			set_wanted(int(a1))
		"neverwanted":
			return _res(set_never_wanted(on))
		"police":
			return _res(spawn_police(a1 if a1 != "" else "cruiser") != null)
		"time":
			set_time(float(a1))
		"weather":
			return _res(set_weather(a1, true))
		"sys":
			return _res(toggle_system(a1, a2.to_lower() != "off"))
		"density":
			set_density(a1, float(a2))
		"repair":
			return _res(repair_current_vehicle())
		"flip":
			return _res(flip_current_vehicle())
		"skills":
			if a1 == "reset":
				reset_skills()
			else:
				max_skills()
		"parachute":
			return _res(give_parachute())
		"scuba":
			return _res(set_scuba(on))
		"breath":
			return _res(refill_breath())
		"appearance":
			return _res(randomize_appearance())
		"taxi":
			return _res(call_taxi())
		"scale":
			set_time_scale(float(a1))
		"overlay":
			set_overlay_visible(on)
		"stats":
			return "ok " + str(get_stats())
		_:
			return "error unknown command '%s'" % cmd
	return "ok"


func _res(ok: bool) -> String:
	return "ok" if ok else "error"


# =================================================================================================
# internals: lookups
# =================================================================================================

func _player() -> Node3D:
	if Game.has_player():
		return Game.player
	return null


func _vm() -> Node:
	return Game.get_system("vehicles")


func _inventory() -> Object:
	var p := _player()
	if p == null:
		return null
	var inv: Variant = p.get("inventory")
	if is_instance_valid(inv) and inv is Object and (inv as Object).has_method("give_weapon"):
		return inv
	return null


func _visual() -> Node:
	var p := _player()
	if p == null:
		return null
	var v: Variant = p.get("visual")
	if is_instance_valid(v) and v is Node:
		return v
	return null


func _screen_exists(id: String) -> bool:
	var path := str(UI.SCREENS.get(id, ""))
	return path != "" and ResourceLoader.exists(path)


func _locations() -> Dictionary:
	var w := Game.world
	if w != null and w.has_method("get_locations"):
		var d: Variant = w.call("get_locations")
		if d is Dictionary:
			return d
	return {}


func _notify(text: String, kind: String = "info") -> void:
	if UI.has_method("notify"):
		UI.notify(text, kind)


func _emit_health(p: Node) -> void:
	EventBus.player_health_changed.emit(float(p.get("health")), float(p.get("armor")))


func _vehicle_name(v: Node) -> String:
	var spec: Variant = v.get("spec")
	if spec is Object and str((spec as Object).get("display_name")) != "":
		return str((spec as Object).get("display_name"))
	return str(v.get("spec_id")).capitalize()


func _slot_order(slot: Variant) -> int:
	var order := ["melee", "handgun", "smg", "shotgun", "rifle", "sniper", "heavy", "thrown"]
	var i := order.find(str(slot))
	return i if i >= 0 else 99


func _float_depth(p: Node) -> float:
	var scr := p.get_script() as Script
	if scr != null:
		var c: Variant = scr.get_script_constant_map().get("FLOAT_DEPTH", null)
		if c is float:
			return c
	return FLOAT_DEPTH_FALLBACK


## Yaw (radians about +Y, 0 = facing -Z) the player looks along: camera first, else the body.
func _view_yaw() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.is_inside_tree():
		var f := -cam.global_basis.z
		f.y = 0.0
		if f.length_squared() > 0.0001:
			return atan2(-f.x, -f.z)
	var p := _player()
	if p != null:
		return p.global_rotation.y
	return 0.0


func _yaw_of(b: Basis) -> float:
	var f := -b.z
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return 0.0
	return atan2(-f.x, -f.z)


func _water_surface(x: float, z: float) -> float:
	var env := Game.get_system("environment")
	if env != null and env.has_method("get_wave_height"):
		return float(env.call("get_wave_height", x, z))
	return Game.WATER_LEVEL


func _water_depth(x: float, z: float) -> float:
	var w := Game.world
	if w != null and w.has_method("get_water_depth"):
		return float(w.call("get_water_depth", x, z))
	return -1.0


## A water location: a point at / below sea level over real water (boat_spawn, shipwreck).
func _is_water_location(pos: Vector3) -> bool:
	return pos.y < 0.5 and _water_depth(pos.x, pos.z) > 0.6


func _district_target(d: String) -> Dictionary:
	if _district_cache.has(d):
		return _district_cache[d]
	var w := Game.world
	var res := {"ok": false}
	if w == null:
		return res
	var sum := Vector3.ZERO
	var n := 0
	if w.has_method("get_lots"):
		for lot: Variant in w.call("get_lots"):
			if lot is Dictionary and str((lot as Dictionary).get("district", "")) == d:
				sum += Vector3((lot as Dictionary).get("center", Vector3.ZERO))
				n += 1
	if n == 0:
		var locs := _locations()
		for k: Variant in locs:
			var o: Vector3 = (locs[k] as Transform3D).origin
			if district_at(o) == d:
				sum += o
				n += 1
	if n == 0:
		return res
	var c := sum / float(n)
	var target := c
	if "walk" in w and w.walk != null and w.walk.has_method("get_nearest_point"):
		var q: Vector3 = w.walk.get_nearest_point(c)
		if q != Vector3.INF and Vector2(q.x - c.x, q.z - c.z).length() < 90.0 and district_at(q) == d:
			target = q
	target.y = Game.ground_height(target.x, target.z)
	var to_c := Vector3(c.x - target.x, 0.0, c.z - target.z)
	var yaw := atan2(-to_c.x, -to_c.z) if to_c.length() > 2.0 else 0.0
	res = {"ok": true, "position": target, "yaw": yaw}
	_district_cache[d] = res
	return res


func _nearest_road(origin: Vector3) -> Dictionary:
	var w := Game.world
	if w == null or not ("roads" in w) or w.roads == null:
		return {"ok": false}
	var roads: Object = w.roads
	if not roads.has_method("get_nearest_lane") or not roads.has_method("sample_lane"):
		return {"ok": false}
	var l: Variant = roads.call("get_nearest_lane", origin, 900.0)
	if not (l is Dictionary) or (l as Dictionary).is_empty():
		return {"ok": false}
	var xf: Transform3D = roads.call("sample_lane", int(l["lane_id"]), float(l["offset"]))
	return {"ok": true, "position": xf.origin, "yaw": _yaw_of(xf.basis)}


func _nearest_spawn_point(kinds: Array, location_names: Array, origin: Vector3, label: String) -> Dictionary:
	var best := Transform3D()
	var best_d := INF
	var w := Game.world
	if w != null and w.has_method("get_spawn_points"):
		for k: Variant in kinds:
			for xf: Variant in w.call("get_spawn_points", str(k)):
				if xf is Transform3D:
					var d := origin.distance_squared_to((xf as Transform3D).origin)
					if d < best_d:
						best_d = d
						best = xf
	var locs := _locations()
	for n: Variant in location_names:
		if locs.has(n):
			var lx: Transform3D = locs[n]
			var d2 := origin.distance_squared_to(lx.origin)
			if d2 < best_d:
				best_d = d2
				best = lx
	if best_d == INF:
		return {"ok": false, "reason": "no %s spot" % label}
	return {"ok": true, "transform": Transform3D(Basis(Vector3.UP, _yaw_of(best.basis)), best.origin), "where": "at the nearest " + label}


func _class_half_extents(cls: String, spec: Variant) -> Vector3:
	if cls == "car" and spec is Object and float((spec as Object).get("mass")) >= 2800.0:
		return HALF_EXTENTS["car_large"]
	return HALF_EXTENTS.get(cls, HALF_EXTENTS["car"])


func _half_extents_of(v: Node3D) -> Vector3:
	var cls := str(v.get("vehicle_class"))
	var half: Vector3 = _class_half_extents(cls, v.get("spec"))
	var aabb: Variant = v.get("body_aabb")
	if aabb is AABB:
		var h: Vector3 = (aabb as AABB).size * 0.5 + Vector3(0.2, 0.0, 0.3)
		half = Vector3(maxf(half.x, h.x), maxf(minf(half.y, h.y), 0.5), maxf(half.z, h.z))
	return half


func _box_of(half: Vector3) -> BoxShape3D:
	_box.size = half * 2.0
	return _box


func _track_admin_vehicle(v: Node3D) -> void:
	_prune_admin_vehicles()
	_admin_vehicles.append(v)
	var pv := Game.get_player_vehicle()
	var vm := _vm()
	var i := 0
	while _admin_vehicles.size() > MAX_ADMIN_VEHICLES and i < _admin_vehicles.size():
		var old: Variant = _admin_vehicles[i]
		if old == pv or old == v:
			i += 1
			continue
		_admin_vehicles.remove_at(i)
		if vm != null and vm.has_method("despawn_vehicle"):
			vm.call("despawn_vehicle", old)


func _prune_admin_vehicles() -> void:
	_admin_vehicles = _admin_vehicles.filter(_is_live_vehicle)


func _is_live_vehicle(x: Variant) -> bool:
	return is_instance_valid(x) and x is Node3D and not bool((x as Node3D).get("destroyed"))


func _on_system_toggled(system_name: String, on: bool) -> void:
	_system_state[system_name] = on


# =================================================================================================
# internals: physics probes and spot search
# =================================================================================================

func _space() -> PhysicsDirectSpaceState3D:
	var w3d := get_viewport().find_world_3d()
	return w3d.direct_space_state if w3d != null else null


## Downward ray on static world geometry. {} if nothing, else {position, normal}.
func _ground_hit(x: float, z: float, top: float, depth: float = 60.0) -> Dictionary:
	var space := _space()
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, top - depth, z), Layers.WORLD)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	return {"position": hit["position"], "normal": hit["normal"]}


func _shape_blocked(shape: Shape3D, xf: Transform3D, mask: int, exclude: Array[RID]) -> bool:
	var space := _space()
	if space == null:
		return false
	_shape_query.shape = shape
	_shape_query.transform = xf
	_shape_query.collision_mask = mask
	_shape_query.exclude = exclude
	_shape_query.collide_with_areas = false
	_shape_query.margin = 0.02
	return not space.intersect_shape(_shape_query, 1).is_empty()


func _ray_blocked(a: Vector3, b: Vector3, mask: int) -> bool:
	var space := _space()
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(a, b, mask)
	return not space.intersect_ray(q).is_empty()


## Searches rings around `center` for a spot on solid, level, dry ground where `shape` (placed
## `lift` metres above the ground, rotated by `yaw`) touches nothing in `mask`. up_clear > 0 also
## needs that much open sky (helicopters). First pass keeps the height level of `center`.
func _find_clear_spot(center: Vector3, yaw: float, shape: Shape3D, lift: float, max_r: float, up_clear: float,
		mask: int, exclude: Array[RID], land_only: bool) -> Dictionary:
	var basis := Basis(Vector3.UP, yaw)
	for same_level in [true, false]:
		var r := 0.0
		while r <= max_r:
			var n := 1 if r == 0.0 else clampi(int(TAU * r / 3.0), 8, 40)
			for k in n:
				var a := TAU * float(k) / float(n)
				var q := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
				var surface_y := Game.ground_height(q.x, q.z)
				var top := maxf(center.y, surface_y) + 2.5
				var g := _ground_hit(q.x, q.z, top)
				if g.is_empty():
					continue
				var gp: Vector3 = g["position"]
				var gn: Vector3 = g["normal"]
				if gn.y < 0.86:
					continue
				if same_level and absf(gp.y - center.y) > 3.0:
					continue
				if land_only and _water_depth(gp.x, gp.z) > 0.25 and gp.y < 0.6:
					continue
				if gp.y < Game.WATER_LEVEL - 0.2:
					continue
				if _shape_blocked(shape, Transform3D(basis, gp + Vector3.UP * lift), mask, exclude):
					continue
				if up_clear > 0.0 and _ray_blocked(gp + Vector3.UP * (lift * 2.0 + 0.3), gp + Vector3.UP * up_clear, Layers.WORLD | Layers.VEHICLE):
					continue
				return {"ok": true, "position": gp, "normal": gn}
			r += 1.5 if r < 6.0 else 3.0
	return {"ok": false}


func _plane_spot(half: Vector3) -> Dictionary:
	var locs := _locations()
	if not locs.has("airport_runway_start"):
		return _nearest_spawn_point(["plane"], [], Game.get_player_position(), "plane stand")
	var base: Transform3D = locs["airport_runway_start"]
	var yaw := _yaw_of(base.basis)
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	for i in 8:
		var c := base.origin + fwd * (float(i) * 26.0)
		var g := _ground_hit(c.x, c.z, c.y + 3.0, 10.0)
		if g.is_empty():
			continue
		var gp: Vector3 = g["position"]
		if _shape_blocked(_box_of(half), Transform3D(Basis(Vector3.UP, yaw), gp + Vector3.UP * (half.y + 0.35)), SPAWN_MASK, _no_rids):
			continue
		return {"ok": true, "transform": Transform3D(Basis(Vector3.UP, yaw), gp), "where": "at the runway start"}
	return _nearest_spawn_point(["plane"], [], Game.get_player_position(), "plane stand")


## Nearest deep, open water (search rings out to ~230 m, forward first), boat facing deeper water.
## Too far from the sea: free water next to the nearest boat spawn point (marina).
func _water_spot(origin: Vector3, vyaw: float, half: Vector3, exclude: Array[RID]) -> Dictionary:
	var near := _search_water(origin, vyaw, half, exclude, 8.0, 230.0)
	if bool(near.get("ok", false)):
		near["where"] = "on the nearest water"
		return near
	var sp := _nearest_spawn_point(["boat"], ["boat_spawn"], origin, "boat dock")
	if not bool(sp.get("ok", false)):
		return sp
	var t: Transform3D = sp["transform"]
	var dock := _search_water(t.origin, _yaw_of(t.basis), half, exclude, 0.0, 90.0)
	if bool(dock.get("ok", false)):
		dock["where"] = "at the nearest boat dock"
		return dock
	return {"ok": false, "reason": "no free water near the boat docks"}


func _search_water(origin: Vector3, vyaw: float, half: Vector3, exclude: Array[RID], r0: float, r1: float) -> Dictionary:
	if Game.world == null or not Game.world.has_method("get_water_depth"):
		return {"ok": false}
	var min_depth := 1.6
	var r := r0
	while r <= r1:
		var n := 1 if r < 0.5 else clampi(int(TAU * r / 7.0), 8, 200)
		for k in n:
			var step := ((k + 1) >> 1) * (1 if k % 2 == 1 else -1)
			var a := vyaw + TAU * float(step) / float(n)
			var q := origin + Vector3(-sin(a), 0.0, -cos(a)) * r
			if _water_depth(q.x, q.z) < min_depth:
				continue
			var yaw := _deep_water_yaw(q, a if r > 0.5 else vyaw)
			var bf := Vector3(-sin(yaw), 0.0, -cos(yaw)) * half.z
			if _water_depth(q.x + bf.x, q.z + bf.z) < 1.2 or _water_depth(q.x - bf.x, q.z - bf.z) < 1.2:
				continue
			var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, _water_surface(q.x, q.z), q.z))
			if _shape_blocked(_box_of(half), Transform3D(xf.basis, xf.origin + Vector3.UP * (half.y * 0.5 + 0.4)), SPAWN_MASK, exclude):
				continue
			if _ray_blocked(xf.origin + Vector3.UP * 0.5, xf.origin + Vector3.UP * 12.0, Layers.WORLD):
				continue
			return {"ok": true, "transform": xf}
		r += 6.0
	return {"ok": false}


## Heading toward deeper water at q (falls back to `fallback` yaw on flat seabed).
func _deep_water_yaw(q: Vector3, fallback: float) -> float:
	var gx := _water_depth(q.x + 5.0, q.z) - _water_depth(q.x - 5.0, q.z)
	var gz := _water_depth(q.x, q.z + 5.0) - _water_depth(q.x, q.z - 5.0)
	var g := Vector2(gx, gz)
	if g.length() < 0.2:
		return fallback
	return atan2(-g.x, -g.y)


func _teleport_vehicle(v: Node3D, pos: Vector3, yaw: float, water: bool) -> bool:
	if not v.has_method("teleport"):
		return false
	var cls := str(v.get("vehicle_class"))
	var exclude: Array[RID] = []
	if v is CollisionObject3D:
		exclude.append((v as CollisionObject3D).get_rid())
	var xf: Transform3D
	if water:
		if cls != "boat":
			return false
		xf = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, _water_surface(pos.x, pos.z), pos.z))
	else:
		if cls == "boat":
			return false
		var half := _half_extents_of(v)
		var s := _find_clear_spot(pos, yaw, _box_of(half), half.y + 0.35, 35.0, 10.0 if cls == "heli" else 0.0,
				SPAWN_MASK & ~Layers.PLAYER, exclude, true)
		if not bool(s.get("ok", false)):
			return false
		xf = Transform3D(Basis(Vector3.UP, yaw), s["position"])
	v.call("teleport", xf)
	return true


# =================================================================================================
# overlay
# =================================================================================================

func _show_overlay(on: bool) -> void:
	_overlay_shown = on
	if on and _overlay_layer == null:
		_overlay_layer = CanvasLayer.new()
		_overlay_layer.name = "DebugOverlay"
		_overlay_layer.layer = OVERLAY_LAYER
		add_child(_overlay_layer)
		_overlay_view = OverlayView.new()
		_overlay_view.set("sys", self)
		_overlay_view.name = "View"
		_overlay_layer.add_child(_overlay_view)
	if _overlay_layer != null:
		_overlay_layer.visible = on
	_set_gpu_measure(on)
	if on:
		refresh_stats()
		_place_overlay()
		_overlay_view.queue_redraw()


func _place_overlay() -> void:
	if _overlay_view != null:
		_overlay_view.position = overlay_origin


func _set_gpu_measure(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), on)


## The UI autoload draws a basic text overlay on the same flag; ours replaces it while shown.
func _hide_basic_overlay() -> void:
	if _basic_overlay == null or not is_instance_valid(_basic_overlay):
		_basic_overlay = UI.get_node_or_null("Root/Debug") as CanvasItem
	if _basic_overlay != null and _basic_overlay.visible:
		_basic_overlay.visible = false


func _font(kind: StringName) -> Font:
	if _style != null:
		var f: Variant = _style.call("font", kind)
		if f is Font:
			return f
	return ThemeDB.fallback_font


## Frame-time history of the last 5 s as polyline points inside `rect` (top = 50 ms).
func _graph_points(rect: Rect2) -> PackedVector2Array:
	var n := 0
	var total := 0
	var idx := _frame_head
	while n < _frame_count and n < 600:
		idx = (idx - 1 + FRAME_RING) % FRAME_RING
		var d := _frame_us[idx]
		if n > 0 and total + d > FRAME_WINDOW_USEC:
			break
		total += d
		n += 1
	_graph_pts.resize(n)
	var acc := 0
	idx = _frame_head
	for i in n:
		idx = (idx - 1 + FRAME_RING) % FRAME_RING
		var d2 := _frame_us[idx]
		acc += d2
		var x := rect.end.x - rect.size.x * float(acc) / float(FRAME_WINDOW_USEC)
		var y := rect.end.y - rect.size.y * clampf(float(d2) / 50000.0, 0.0, 1.0)
		_graph_pts[i] = Vector2(maxf(x, rect.position.x), y)
	return _graph_pts


## Custom-drawn overlay panel (one CanvasItem, redrawn 4 times a second).
class OverlayView extends Control:
	const NAVY := Color(0.02, 0.045, 0.085, 0.86)
	const LINE := Color(1, 1, 1, 0.12)
	const TEAL := Color(0.373, 0.839, 0.8)
	const SUN := Color(0.969, 0.788, 0.282)
	const CORAL := Color(0.933, 0.494, 0.392)
	const GOOD := Color(0.345, 0.839, 0.553)
	const BAD := Color(1.0, 0.353, 0.322)
	const TEXT := Color(0.961, 0.953, 0.933)
	const MUTED := Color(0.655, 0.722, 0.8)
	const DIM := Color(0.42, 0.49, 0.58)

	var sys: Node = null
	var _bg: StyleBoxFlat = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(560.0, 454.0)
		_bg = StyleBoxFlat.new()
		_bg.bg_color = NAVY
		_bg.set_corner_radius_all(14)
		_bg.border_color = LINE
		_bg.set_border_width_all(2)

	func _fps_color(fps: float) -> Color:
		if fps >= 55.0:
			return GOOD
		if fps >= 30.0:
			return SUN
		return BAD

	func _draw() -> void:
		if sys == null:
			return
		var s: Dictionary = sys.get("_stats")
		if s.is_empty():
			return
		var head: Font = sys.call("_font", &"head")
		var num: Font = sys.call("_font", &"num")
		var body: Font = sys.call("_font", &"body")
		var w := size.x
		draw_style_box(_bg, Rect2(Vector2.ZERO, size))
		var x := 22.0
		var y := 38.0
		draw_string(head, Vector2(x, y), "PERFORMANCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEAL)
		var tw := head.get_string_size("PERFORMANCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(body, Vector2(x + tw + 16.0, y), "frame times of the last 5 s", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DIM)
		draw_string(body, Vector2(0, y), "F3  ", HORIZONTAL_ALIGNMENT_RIGHT, w - 16.0, 17, DIM)
		# big fps + averages
		y += 62.0
		var fps := float(s.get("fps", 0.0))
		var fc := _fps_color(fps)
		draw_string(num, Vector2(x, y), "%d" % int(fps), HORIZONTAL_ALIGNMENT_LEFT, -1, 58, fc)
		var fw := num.get_string_size("%d" % int(fps), HORIZONTAL_ALIGNMENT_LEFT, -1, 58).x
		draw_string(head, Vector2(x + fw + 10.0, y - 4.0), "FPS", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, MUTED)
		var col2 := 250.0
		draw_string(body, Vector2(col2, y - 34.0), "avg 5 s", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, DIM)
		draw_string(num, Vector2(col2, y - 4.0), "%.1f" % float(s.get("avg_fps", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, TEXT)
		var low := float(s.get("low_1_fps", 0.0))
		draw_string(body, Vector2(col2 + 150.0, y - 34.0), "1 % low", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, DIM)
		draw_string(num, Vector2(col2 + 150.0, y - 4.0), "%.1f" % low, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, _fps_color(low))
		# frame-time graph (5 s, top = 50 ms; guides at 60 and 30 fps)
		y += 16.0
		var g := Rect2(x, y, w - 2.0 * x - 62.0, 70.0)
		draw_rect(g, Color(0, 0, 0, 0.28))
		for guide: float in [16.667, 33.333]:
			var gy := g.end.y - g.size.y * guide / 50.0
			draw_line(Vector2(g.position.x, gy), Vector2(g.end.x, gy), Color(1, 1, 1, 0.14), 1.0)
			draw_string(body, Vector2(g.end.x + 8.0, gy + 5.0), "%d fps" % int(round(1000.0 / guide)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DIM)
		var pts: PackedVector2Array = sys.call("_graph_points", g)
		if pts.size() >= 2:
			draw_polyline(pts, TEAL, 2.0, true)
		y += g.size.y + 30.0
		var lines: Array = [
			["frame", "%.1f ms" % float(s.get("avg_ms", 0.0)), "worst", "%.1f ms" % float(s.get("worst_ms", 0.0)),
					"gpu", "%.1f ms" % float(s.get("gpu_ms", 0.0))],
			["cpu", "%.1f ms" % float(s.get("cpu_ms", 0.0)), "physics", "%.1f ms" % float(s.get("physics_ms", 0.0)),
					"vram", "%d MB" % int(s.get("vram_mb", 0.0))],
			["draws", "%d" % int(s.get("draw_calls", 0)), "prims", "%.2f M" % (float(s.get("primitives", 0)) / 1000000.0),
					"objects", "%d" % int(s.get("objects", 0))],
			["nodes", "%d" % int(s.get("nodes", 0)), "vehicles", "%d" % int(s.get("vehicles", 0)),
					"peds", "%d" % int(s.get("peds", 0))],
			["npcs", "%d" % int(s.get("npcs", 0)), "police", "%d" % int(s.get("police", 0)),
					"animals", "%d" % int(s.get("animals", 0))],
		]
		var cw := (w - 2.0 * x) / 3.0
		for row: Array in lines:
			for c in 3:
				var cx := x + cw * float(c)
				draw_string(body, Vector2(cx, y), str(row[c * 2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, DIM)
				draw_string(num, Vector2(cx, y), str(row[c * 2 + 1]), HORIZONTAL_ALIGNMENT_RIGHT, cw - 14.0, 20, TEXT)
			y += 28.0
		y += 4.0
		draw_line(Vector2(x, y - 14.0), Vector2(w - x, y - 14.0), LINE, 2.0)
		var p: Vector3 = s.get("position", Vector3.ZERO)
		draw_string(num, Vector2(x, y + 8.0), "X %.1f   Y %.1f   Z %.1f" % [p.x, p.y, p.z], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, TEXT)
		draw_string(body, Vector2(0, y + 8.0), "heading %03d°" % int(s.get("heading_deg", 0.0)), HORIZONTAL_ALIGNMENT_RIGHT, w - x, 17, MUTED)
		y += 38.0
		var dist := str(s.get("district", "")).to_upper()
		draw_string(head, Vector2(x, y), dist if dist != "" else "-", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, SUN)
		var dw := head.get_string_size(dist if dist != "" else "-", HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(head, Vector2(x + dw + 18.0, y), "SECTOR %s" % str(s.get("sector", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, CORAL)
		y += 34.0
		var tail := "%s  %s   %s   x%.2f   wanted %d" % [str(s.get("time", "")), str(s.get("phase", "")),
				str(s.get("weather", "")).capitalize(), float(s.get("time_scale", 1.0)), int(s.get("wanted", 0))]
		draw_string(body, Vector2(x, y), tail, HORIZONTAL_ALIGNMENT_LEFT, w - 2.0 * x, 19, MUTED)
