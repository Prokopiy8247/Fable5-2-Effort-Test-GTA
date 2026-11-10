extends Node3D
## Vehicle access for free-roam testing (spec 26) - created by the garage system.
## Rental terminals (the Blender-authored `atm` kiosk prop with a lit screen) at
##   airport          in front of Hangar One         -> every registered aircraft (heli, plane)
##   marina           on the quay at the middle pier -> every registered boat
##   parking_garage   on the downtown parking garage -> every car / bike / bicycle
## open UI "garage" in catalogue mode: rent for a fee (free with Game.flags.free_shopping), the
## vehicle is spawned at the site's spawn point and the player is seated in it.
## The parking garage is also a garage use point (W2.7): stored vehicles can be retrieved from the
## terminal and a vehicle is stored by stopping at the kerb in front of it.
## Each terminal is a `minimap_blip` (icon plane / boat / parking).

const Sites := preload("res://gta/code/world/shops/garage_sites.gd")
const Stats := preload("res://gta/code/world/shops/garage_stats.gd")

const TERMINAL_MODEL := "res://gta/generated/models/props/atm.glb"
const TERMINAL_SIZE := Vector3(0.9, 1.94, 0.97)
const TERMINAL_VIS_RANGE := 140.0
const BLIP_COLOR := Color(0.373, 0.839, 0.8)

## anchor: World location; side / back: metres along the anchor's +X / +Z (the location faces the
## building with -Z); face: "out" = screen toward anchor +Z, "center" = toward the anchor's line.
const SITES := {
	"airport": {"name": "Hangar One rentals", "anchor": "airport_hangar", "side": -6.5, "back": 1.0,
			"face": "out", "kinds": ["heli", "plane"], "icon": &"plane", "title": "Aircraft rentals",
			"subtitle": "Hangar One - helicopters and planes"},
	"marina": {"name": "Marina rentals", "anchor": "marina_dock", "side": 3.5, "back": 22.0,
			"face": "center", "kinds": ["boat"], "icon": &"boat", "title": "Boat rentals",
			"subtitle": "Halcyon Marina - boats"},
	"parking_garage": {"name": "Parking garage", "anchor": "parking_garage", "side": 3.6, "back": 0.2,
			"face": "out", "kinds": ["car", "bike", "bicycle"], "icon": &"parking", "title": "Parking garage",
			"subtitle": "Downtown parking - rentals and stored vehicles", "garage": true},
}

var system: Node = null
var enabled: bool = true
var terminals: Dictionary = {}         ## site -> {"node": Node3D, "interactable": Interactable, "xform": Transform3D, "anchor": Transform3D}
var store_point: Interactable = null
var _busy: bool = false
static var _terminal_scene: PackedScene = null


func setup_site(sys: Node) -> void:
	system = sys
	for site: String in SITES:
		var def: Dictionary = SITES[site]
		var root := Node3D.new()
		root.name = "Terminal_" + site.to_pascal_case()
		add_child(root)
		root.add_to_group("minimap_blip")
		root.set_meta("blip_icon", def["icon"])
		root.set_meta("blip_color", BLIP_COLOR)
		root.set_meta("blip_clamp", false)
		var model := _make_terminal_model()
		if model != null:
			root.add_child(model)
		var it := Interactable.create("%s - %s" % [str(def["name"]), "rent / garage" if bool(def.get("garage", false)) else "rent a vehicle"], 1.7, "interact")
		it.name = "Use"
		it.use_priority = 3
		add_child(it)
		it.interacted.connect(_on_terminal.bind(site))
		terminals[site] = {"node": root, "interactable": it, "xform": Transform3D.IDENTITY, "anchor": Transform3D.IDENTITY}
		if sys != null and sys.has_method("register_site"):
			sys.call("register_site", site, self)
	store_point = Interactable.create("Parking garage - store vehicle", 6.0, "interact")
	store_point.name = "ParkingStore"
	store_point.in_vehicle_only = true
	store_point.on_foot_only = false
	store_point.use_priority = 2
	store_point.condition = _can_store_here
	add_child(store_point)
	store_point.interacted.connect(_on_store)
	relocate()


func _make_terminal_model() -> Node3D:
	if _terminal_scene == null and ResourceLoader.exists(TERMINAL_MODEL):
		_terminal_scene = load(TERMINAL_MODEL) as PackedScene
	if _terminal_scene == null:
		push_warning("garage: terminal model missing (%s) - terminals have no visible kiosk" % TERMINAL_MODEL)
		return null
	var holder := Node3D.new()
	holder.name = "Kiosk"
	var inst := _terminal_scene.instantiate() as Node3D
	if inst != null:
		holder.add_child(inst)
		for c: Node in inst.find_children("*", "GeometryInstance3D", true, false):
			var gi := c as GeometryInstance3D
			gi.visibility_range_end = TERMINAL_VIS_RANGE
	var body := StaticBody3D.new()
	body.name = "Collider"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.set_meta("surface", "metal")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = TERMINAL_SIZE
	shape.shape = box
	shape.position = Vector3(0.0, TERMINAL_SIZE.y * 0.5, 0.0)
	body.add_child(shape)
	holder.add_child(body)
	return holder


func relocate() -> void:
	for site: String in SITES:
		var def: Dictionary = SITES[site]
		var t: Dictionary = terminals[site]
		var anchor_name := str(def["anchor"])
		var anchor := Game.get_location(anchor_name) if Sites.has_location(anchor_name) else Transform3D.IDENTITY
		anchor = Sites._level(anchor)
		t["anchor"] = anchor
		var pos := anchor.origin + anchor.basis.x * float(def["side"]) + anchor.basis.z * float(def["back"])
		pos.y = Game.ground_height(pos.x, pos.z)
		var screen_dir := anchor.basis.z
		if str(def["face"]) == "center":
			screen_dir = -anchor.basis.x * signf(float(def["side"]))
		screen_dir.y = 0.0
		screen_dir = screen_dir.normalized()
		var yaw := atan2(-screen_dir.x, -screen_dir.z)        # node -Z (the lit screen) along screen_dir
		var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
		t["xform"] = xf
		(t["node"] as Node3D).global_transform = xf
		(t["interactable"] as Interactable).global_position = pos + screen_dir * 0.9 + Vector3(0.0, 0.9, 0.0)
	# store point: the kerb lane in front of the parking garage terminal
	var pg: Dictionary = terminals.get("parking_garage", {})
	if not pg.is_empty() and store_point != null:
		var a: Transform3D = pg["anchor"]
		var sp := a.origin + a.basis.z * 5.0
		sp.y = Game.ground_height(sp.x, sp.z) + 0.6
		store_point.global_position = sp


func set_enabled(on: bool) -> void:
	enabled = on
	for t: Dictionary in terminals.values():
		(t["interactable"] as Interactable).enabled = on
		(t["node"] as Node3D).visible = on
	if store_point != null:
		store_point.enabled = on


func get_terminal_transform(site: String) -> Transform3D:
	return (terminals[site]["xform"] as Transform3D) if terminals.has(site) else Transform3D.IDENTITY


func get_interactable(site: String) -> Interactable:
	return (terminals[site]["interactable"] as Interactable) if terminals.has(site) else null


func get_site_kinds(site: String) -> Array:
	return (SITES[site]["kinds"] as Array).duplicate() if SITES.has(site) else []


## Spawn candidates in order of preference (the garage system picks the first clear one).
func get_spawn_candidates(site_id: String, vehicle_class: String) -> Array:
	var out: Array = []
	if not terminals.has(site_id) or not (SITES[site_id]["kinds"] as Array).has(vehicle_class):
		return out
	var anchor: Transform3D = terminals[site_id]["anchor"]
	match site_id:
		"airport":
			if vehicle_class == "heli":
				if Sites.has_location("airport_helipad"):
					out.append(Game.get_location("airport_helipad"))
				out.append_array(Sites.spawn_points_near("heli", anchor.origin))
			else:
				out.append_array(Sites.spawn_points_near("plane", anchor.origin))
				# further down the runway, lined up for take-off
				if Sites.has_location("airport_runway_start"):
					var rs := Sites._level(Game.get_location("airport_runway_start"))
					for k in 6:
						var p := rs.origin - rs.basis.z * (35.0 + 28.0 * float(k))
						p.y = Game.ground_height(p.x, p.z)
						out.append(Transform3D(rs.basis, p))
				var hm := Sites.marker("airport_hangar", "Spawn_Plane")
				if bool(hm["ok"]):
					out.append(hm["xform"])
		"marina":
			if Sites.has_location("boat_spawn"):
				var b := Game.get_location("boat_spawn")
				b.origin.y = Game.WATER_LEVEL
				out.append(b)
			for xf: Transform3D in Sites.spawn_points_near("boat", anchor.origin, 260.0):
				out.append(xf)
		"parking_garage":
			out.append_array(Sites.spawn_points_near("parking", anchor.origin, 85.0))
	# every authored point may be taken (parked aircraft / moored boats / parked cars): search the
	# open apron / water / street around the site for a clear spot as well
	out.append_array(_fallback_spots(site_id, vehicle_class, anchor))
	return out


const FALLBACK := {
	"airport": {"ahead": 30.0, "half_heli": Vector3(6.0, 2.4, 6.0), "half_plane": Vector3(7.5, 2.4, 7.5), "max_r": 70.0, "step": 14.0},
	"marina": {"ahead": -14.0, "half": Vector3(1.8, 0.8, 4.2), "max_r": 40.0, "step": 7.0},
	"parking_garage": {"ahead": 7.5, "half": Vector3(1.2, 0.9, 2.6), "max_r": 42.0, "step": 6.0},
}


func _fallback_spots(site_id: String, vehicle_class: String, anchor: Transform3D) -> Array:
	var f: Dictionary = FALLBACK.get(site_id, {})
	if f.is_empty() or not is_inside_tree():
		return []
	var half: Vector3 = f.get("half", Vector3(2, 1, 3))
	if site_id == "airport":
		half = f["half_heli"] if vehicle_class == "heli" else f["half_plane"]
	var center := anchor.origin + anchor.basis.z * float(f["ahead"])
	var yaw := Sites.yaw_of(anchor) + PI
	if site_id == "airport" and vehicle_class == "heli" and Sites.has_location("airport_helipad"):
		# around the helipad (the pad itself is usually taken by a parked helicopter)
		var hp := Sites._level(Game.get_location("airport_helipad"))
		center = hp.origin
		yaw = Sites.yaw_of(hp)
	if site_id == "marina":
		var bs := Game.get_location("boat_spawn") if Sites.has_location("boat_spawn") else anchor
		center = Vector3(bs.origin.x, Game.WATER_LEVEL, bs.origin.z)
		yaw = Sites.yaw_of(bs)
	elif site_id != "airport":
		center.y = Game.ground_height(center.x, center.z)
	return Sites.free_spots(get_world_3d().direct_space_state, center, yaw, half, float(f["max_r"]), float(f["step"]), site_id == "marina")


# --- interactions -------------------------------------------------------------------------------

func _on_terminal(_player: Node3D, site: String) -> void:
	open_terminal(site)


func open_terminal(site: String) -> Control:
	if not SITES.has(site):
		return null
	var def: Dictionary = SITES[site]
	var args := {"mode": "catalogue", "site": site, "kinds": def["kinds"], "title": def["title"],
			"subtitle": def["subtitle"]}
	if bool(def.get("garage", false)):
		args["allow_stored"] = true
	return UI.open_screen("garage", args)


func _can_store_here(player: Node3D) -> bool:
	if not enabled or _busy or system == null:
		return false
	var v: Variant = player.get("current_vehicle")
	if v == null or not is_instance_valid(v):
		return false
	var rb := v as RigidBody3D
	if rb != null and rb.linear_velocity.length() > 3.0:
		return false
	return bool(system.call("is_storable_class", Stats.text(v, "vehicle_class", "car")))


func _on_store(player: Node3D) -> void:
	var v: Variant = player.get("current_vehicle")
	if v == null or not is_instance_valid(v) or system == null:
		return
	var reason := str(system.call("can_store", v))
	if reason != "":
		UI.notify(reason, "warn")
		return
	_busy = true
	var vname := Stats.vehicle_name(v)
	await UI.fade_out(0.35)
	var ok := bool(system.call("store_vehicle", v))
	await UI.fade_in(0.35)
	_busy = false
	if ok:
		UI.notify("%s parked in the garage (%d / %d)" % [vname, (system.call("get_stored") as Array).size(), int(system.call("get_capacity"))], "good")
