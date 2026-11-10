class_name GarageSystem
extends Node
## Personal vehicles: the safehouse garage stores up to four of them (with paint and every
## Torque House modification), personal vehicles survive save / load, and the phone can have
## Torque House deliver your personal vehicle to the nearest road.

const CAPACITY := 4
const DELIVERY_FEE := 250

var stored: Array = []               # vehicle records (see record())
var _spot := Vector3.ZERO            # inside the garage
var _out := Vector3.ZERO             # driveway in front of the garage door
var _out_yaw := 0.0
var _near := false
var _tick := 0.0

func _ready() -> void:
	var city: CityBuilder = Game.world.city
	var g: Variant = city.marker("safehouse", "garage_spot")
	var o: Variant = city.marker("safehouse", "garage_out")
	var loc: Dictionary = city.locations.get("safehouse", {})
	var base: Vector3 = loc.get("pos", Vector3(-193.0, 0.15, 140.0))
	_spot = (g as Transform3D).origin if g != null else base + Vector3(-9.0, 0.0, -4.0)
	_out = (o as Transform3D).origin if o != null else _spot + Vector3(0, 0, -5.0)
	var dirv := _out - _spot
	dirv.y = 0.0
	_out_yaw = atan2(-dirv.x, -dirv.z) if dirv.length() > 0.5 else PI

## Everything needed to rebuild a vehicle exactly.
static func record(v: Vehicle) -> Dictionary:
	return {"vid": v.vid, "paint_a": v.paint_a.to_html(false), "paint_b": v.paint_b.to_html(false),
		"finish": [v.finish.x, v.finish.y, v.finish.z, v.finish.w], "mods": v.mods.duplicate(true),
		"health": v.health / maxf(v.max_health, 1.0)}

static func rebuild(rec: Dictionary, pos: Vector3, yaw: float) -> Vehicle:
	var id := String(rec.get("vid", "car_sedan"))
	if not VehicleDB.exists(id):
		return null
	var v := VehicleFactory.spawn(id, pos, yaw, {"tag": "player", "personal": true,
		"paint": Color.html(String(rec.get("paint_a", "2aa59a"))), "paint_b": Color.html(String(rec.get("paint_b", "17181b")))})
	if v == null:
		return null
	var f: Array = rec.get("finish", [])
	if f.size() == 4:
		v.set_paint(v.paint_a, v.paint_b, Vector4(f[0], f[1], f[2], f[3]))
	var mods: Dictionary = rec.get("mods", {})
	if not mods.is_empty():
		VehicleMods.apply_all(v, mods)
	v.health = v.max_health * clampf(float(rec.get("health", 1.0)), 0.3, 1.0)
	v.personal = true
	return v

func personal_vehicles() -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	for n in get_tree().get_nodes_in_group(&"vehicles"):
		var v := n as Vehicle
		if v.personal and not v.destroyed and not v.is_queued_for_deletion():
			out.append(v)
	return out

# ---------------------------------------------------------------- store / retrieve
func can_store(v: Vehicle) -> bool:
	return v != null and is_instance_valid(v) and not v.destroyed and v is Car and not (v is Airplane) and stored.size() < CAPACITY

func store(v: Vehicle) -> bool:
	if not can_store(v):
		return false
	var p: Player = Game.player
	if v.has_player():
		p.force_exit_vehicle()
		p.teleport(_out + Vector3(2.5, 0.2, 0.0), _out_yaw)
	for i in v.seat_count():
		if v.seats[i]["occupant"] != null:
			v.unseat(i)
	stored.append(record(v))
	v.queue_free()
	Audio.play_ui(&"garage_door", -6.0)
	Game.notify("%s stored in the garage (%d / %d)" % [String(v.def.get("name", v.vid)), stored.size(), CAPACITY], "good")
	return true

func take_out(i: int) -> Vehicle:
	if i < 0 or i >= stored.size():
		return null
	var at := _out
	var yaw := _out_yaw
	if not _free(at):
		# driveway taken: park it at the kerb of the nearest street instead
		var found := false
		for k in range(1, 6):
			var spot := _street_spot(k)
			if not spot.is_empty() and _free(spot[0]):
				at = spot[0]
				yaw = float(spot[1])
				found = true
				break
		if not found:
			Game.notify("Clear the driveway first", "bad")
			return null
	var rec: Dictionary = stored[i]
	var v := rebuild(rec, at, yaw)
	if v != null:
		stored.remove_at(i)
		Audio.play_ui(&"garage_door", -6.0)
		Game.notify("%s is waiting on the driveway" % String(v.def.get("name", v.vid)), "good")
	return v

func _free(p: Vector3) -> bool:
	for n in get_tree().get_nodes_in_group(&"vehicles"):
		if (n as Node3D).global_position.distance_to(p) < 4.0:
			return false
	return true

## Phone service: bring your personal vehicle (or the most recently stored one) to a road near you.
func deliver_personal() -> void:
	var p: Player = Game.player
	if p.vehicle != null:
		Game.notify("You are already in a vehicle", "info")
		return
	var graph: RoadGraph = Game.world.graph
	var near := graph.nearest(p.global_position, 80.0)
	if near.is_empty():
		Game.notify("Torque House cannot reach you here", "bad")
		return
	var lane := int(near["lane"])
	var s := clampf(float(near["s"]) + 6.0, 2.0, graph.lanes[lane].length - 2.0)
	var pos := graph.sample(lane, s)
	var dirv := graph.direction(lane, s)
	var yaw := atan2(-dirv.x, -dirv.z)
	var right := Vector3(-dirv.z, 0.0, dirv.x)
	pos += right * 1.0              # tuck it toward the kerb
	if not _free(pos):
		pos += dirv * 9.0
	if not Game.spend(DELIVERY_FEE):
		return
	var mine := personal_vehicles()
	var v: Vehicle = null
	if not mine.is_empty():
		# move the existing car (nobody is watching a flatbed in this town)
		v = mine[mine.size() - 1]
		for i in v.seat_count():
			if v.seats[i]["occupant"] != null:
				v.unseat(i)
		v.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.4, 0))
		v.linear_velocity = Vector3.ZERO
		v.angular_velocity = Vector3.ZERO
		v.sleeping = false
	elif not stored.is_empty():
		var rec: Dictionary = stored.pop_back()
		v = rebuild(rec, pos, yaw)
	else:
		v = rebuild({"vid": "car_sedan", "paint_a": "2aa59a"}, pos, yaw)
	if v != null:
		Game.notify("Torque House delivered your %s ($%d)" % [String(v.def.get("name", v.vid)), DELIVERY_FEE], "money")
		if Game.hud != null:
			Game.hud.set_waypoint(pos)

# ---------------------------------------------------------------- safehouse menu page
func menu_rows(ui: UIManager) -> Array:
	var rows: Array = [{"text": "Stored (%d / %d)" % [stored.size(), CAPACITY], "header": true}]
	for i in stored.size():
		var rec: Dictionary = stored[i]
		var d := VehicleDB.get_v(String(rec["vid"]))
		var mods: Dictionary = rec.get("mods", {})
		var idx := i
		rows.append({"text": String(d.get("name", rec["vid"])), "right": "Take out", "swatch": Color.html(String(rec.get("paint_a", "ffffff"))),
			"desc": VehicleMods.describe(mods) if not mods.is_empty() else "Stock.",
			"fn": func() -> void:
				if take_out(idx) != null:
					ui.menu.close()})
	if stored.is_empty():
		rows.append({"text": "The garage is empty", "info": true})
	rows.append({"text": "Your vehicles outside", "header": true})
	var any := false
	for v in personal_vehicles():
		any = true
		var dist := v.global_position.distance_to(_spot)
		var near := dist < 30.0
		rows.append({"text": String(v.def.get("name", v.vid)), "right": "Store" if near else "%d m away" % int(dist), "off": not near or not can_store(v),
			"swatch": v.paint_a, "desc": "Park it in front of the garage to store it." if not near else "",
			"fn": func() -> void:
				if store(v):
					ui.menu.refresh()})
	if not any:
		rows.append({"text": "No personal vehicles outside", "info": true})
	rows.append({"text": "Back", "fn": func() -> void: ui.menu.back()})
	return rows

# ---------------------------------------------------------------- drive-in
func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	var p: Player = Game.player
	if p == null or Game.menus == null:
		return
	var v: Vehicle = p.vehicle as Vehicle if (p.vehicle != null and is_instance_valid(p.vehicle) and p.seat == 0) else null
	var inside := v != null and v.global_position.distance_to(_spot) < 3.6 and absf(v.speed) < 1.5
	if inside and not _near and not Game.menus.is_open():
		_near = true
		if not v.personal:
			Game.notify("Only your own vehicles fit in the garage (modify one at Torque House to make it yours)", "info")
		elif Game.wanted != null and Game.wanted.level > 0:
			Game.notify("Lose the police before using the garage", "bad")
		else:
			store(v)
	elif not inside:
		_near = false

# ---------------------------------------------------------------- persistence
func save_state() -> Dictionary:
	var outside: Array = []
	for v in personal_vehicles():
		outside.append(record(v))
	return {"stored": stored.duplicate(true), "outside": outside}

func load_state(d: Dictionary) -> void:
	stored = (d.get("stored", []) as Array).duplicate(true)
	var p: Player = Game.player
	for v in personal_vehicles():
		if v.has_player():
			p.force_exit_vehicle()
		v.queue_free()
	# personal vehicles that were outside come back on the safehouse driveway / street
	var outside: Array = d.get("outside", [])
	for i in outside.size():
		var at := _out
		var yaw := _out_yaw
		if i > 0:
			# the rest line up along the kerb of the nearest street
			var spot := _street_spot(i)
			if not spot.is_empty():
				at = spot[0]
				yaw = float(spot[1])
		var v := rebuild(outside[i], at + Vector3(0, 0.2, 0), yaw)
		if v != null and i == 0:
			v.set_meta("home", true)

## k-th kerbside parking spot along the street nearest to the garage: [position, yaw] or [].
func _street_spot(k: int) -> Array:
	var graph: RoadGraph = Game.world.graph
	var near := graph.nearest(_out, 60.0)
	if near.is_empty():
		return []
	var lane := int(near["lane"])
	var s := clampf(float(near["s"]) + 8.0 * float(k), 2.0, graph.lanes[lane].length - 2.0)
	var dirv := graph.direction(lane, s)
	return [graph.sample(lane, s) + Vector3(-dirv.z, 0.0, dirv.x) * 1.0, atan2(-dirv.x, -dirv.z)]
