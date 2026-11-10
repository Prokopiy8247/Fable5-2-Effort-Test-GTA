class_name Transit
extends Node
## ZipCab taxi service. Call a cab with the phone (it drives to you and waits) or hail one in
## traffic with F. Inside, the destination is the GPS waypoint or a pick from the list; ride
## along (fare by distance) or press Space to skip the trip for a surcharge.

enum T { NONE, COMING, WAITING, RIDING }

const BASE_FARE := 6
const PER_100M := 9
const SKIP_FEE := 20

var state: int = T.NONE
var cab: Car = null
var dest := Vector3.ZERO
var dest_name := ""
var travelled := 0.0
var _last := Vector3.ZERO
var _timer := 0.0
var _tick := 0.0

func _ready() -> void:
	Events.player_exited_vehicle.connect(_on_exit)
	Events.player_died.connect(func(_c: String) -> void: _reset())
	Events.player_busted.connect(func() -> void: _reset())

func fare() -> int:
	return BASE_FARE + int(travelled / 100.0 * float(PER_100M))

func _cab_ok() -> bool:
	return cab != null and is_instance_valid(cab) and not cab.destroyed and cab.driver() != null and cab.driver().alive

# ---------------------------------------------------------------- calling a cab
func call_taxi() -> void:
	var p: Player = Game.player
	if p.vehicle != null:
		Game.notify("Get out of the vehicle first", "info")
		return
	if state != T.NONE and _cab_ok():
		Game.notify("Your cab is already on its way", "info")
		return
	if not VehicleDB.has_model("car_taxi"):
		Game.notify("ZipCab has no cars on the road", "bad")
		return
	var pd: PoliceDispatch = Game.police
	var spot: Array = pd._find_spawn(p.global_position, 55.0, 140.0) if pd != null else []
	if spot.is_empty():
		Game.notify("ZipCab cannot find you here - walk to a street", "bad")
		return
	var graph: RoadGraph = Game.world.graph
	var lane := int(spot[0])
	var s0 := float(spot[1])
	var pos := graph.sample(lane, s0)
	var dirv := graph.direction(lane, s0)
	var v := VehicleFactory.spawn("car_taxi", pos, atan2(-dirv.x, -dirv.z), {"tag": "taxi"}) as Car
	if v == null:
		return
	v.set_meta("taxi", true)
	if Game.peds.seat_in(v, 0, &"driver") == null:
		v.queue_free()
		return
	var ai := AIDriver.attach(v, Game.traffic, lane, s0)
	if not ai.drive_to(p.global_position, false):
		ai.cruise()
	cab = v
	state = T.COMING
	_timer = 0.0
	Game.notify("ZipCab is on the way", "info")
	Audio.play_ui(&"phone_beep", -6.0)

func _reset() -> void:
	if _cab_ok() and cab.ai is AIDriver:
		(cab.ai as AIDriver).cruise()
	if cab != null and is_instance_valid(cab):
		cab.owner_tag = "traffic"
	cab = null
	state = T.NONE
	if Game.hud != null:
		Game.hud.info_text = ""

# ---------------------------------------------------------------- riding
## Called by the player when boarding a taxi as a passenger.
func on_board(v: Vehicle) -> void:
	if Game.wanted != null and Game.wanted.level >= 2:
		Game.notify("\"Not with the cops after you, pal.\"", "bad")
		Game.player.force_exit_vehicle.call_deferred()
		return
	cab = v as Car
	state = T.RIDING
	travelled = 0.0
	_last = cab.global_position
	if cab.ai is AIDriver:
		(cab.ai as AIDriver).hold()
	var hud: HUD = Game.hud
	if hud != null and hud.waypoint != null:
		_go(hud.waypoint, "your waypoint")
	else:
		_ask_destination.call_deferred()

func _ask_destination() -> void:
	if Game.menus == null or not _cab_ok():
		return
	Game.menus.open_menu("taxi", "ZipCab", "Where to?", _dest_rows, false, false, Color(1.0, 0.8, 0.1))

func _dest_rows() -> Array:
	var rows: Array = [{"text": "Places", "header": true}]
	var city: CityBuilder = Game.world.city
	var seen := {}
	for key in city.locations.keys():
		var loc: Dictionary = city.locations[key]
		var lid := String(loc.get("id", key))
		if not MapDraw.ICON_NAMES.has(lid) or seen.has(lid):
			continue
		seen[lid] = true
		var pos: Vector3 = loc["pos"]
		var m: Variant = city.marker(key, "entrance")
		if m != null:
			pos = (m as Transform3D).origin
		var nm := String(MapDraw.ICON_NAMES[lid])
		var est := BASE_FARE + int(pos.distance_to(Game.player_pos()) * 1.25 / 100.0 * float(PER_100M))
		rows.append({"text": nm, "right": "~$%d" % est, "fn": func() -> void:
			Game.menus.menu.close()
			_go(pos, nm)})
	rows.append({"text": "Districts", "header": true})
	for zn in Game.world.layout.zones:
		var dn := String(zn["name"])
		var pt: Variant = AdminMenu.district_point(dn)
		if pt == null:
			continue
		var at: Vector3 = pt
		rows.append({"text": dn, "fn": func() -> void:
			Game.menus.menu.close()
			_go(at, dn)})
	rows.append({"text": "Get out", "fn": func() -> void:
		Game.menus.menu.close()
		Game.player.force_exit_vehicle()})
	return rows

func _go(pos: Vector3, label: String) -> void:
	if not _cab_ok():
		_reset()
		return
	dest = pos
	dest_name = label
	var ai: AIDriver = cab.ai as AIDriver
	if ai == null:
		ai = AIDriver.attach(cab, Game.traffic, -1, 0.0)
	if not ai.drive_to(pos, false):
		Game.notify("The driver does not know the way there", "bad")
		return
	ai.cruise_mul = 1.15
	Game.notify("Heading to %s" % label, "info")

func skip_trip() -> void:
	if state != T.RIDING or not _cab_ok() or dest == Vector3.ZERO:
		return
	var graph: RoadGraph = Game.world.graph
	var near := graph.nearest(dest, 80.0)
	if near.is_empty():
		return
	var lane := int(near["lane"])
	var s := float(near["s"])
	var pos := graph.sample(lane, s)
	var dirv := graph.direction(lane, s)
	travelled += cab.global_position.distance_to(pos) * 1.2
	if Game.hud != null:
		Game.hud.fade_to(1.0, 0.4)
	await get_tree().create_timer(0.45).timeout
	if not _cab_ok():
		return
	cab.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dirv.x, -dirv.z)), pos + Vector3(0, 0.4, 0))
	cab.linear_velocity = Vector3.ZERO
	cab.angular_velocity = Vector3.ZERO
	_last = cab.global_position
	if cab.ai is AIDriver:
		(cab.ai as AIDriver).cruise()
	Game.add_cash(-mini(SKIP_FEE, Game.cash), false)
	if Game.cam != null:
		Game.cam.snap()
	if Game.hud != null:
		Game.hud.fade_to(0.0, 0.6)
	_arrive()

func _arrive() -> void:
	var p: Player = Game.player
	var f := fare()
	var paid := mini(f, Game.cash)
	Game.add_cash(-paid, false)
	Game.notify("ZipCab fare: $%d%s" % [paid, "" if paid == f else " (all you had)"], "money")
	if cab != null and is_instance_valid(cab) and p.vehicle == cab:
		cab.in_handbrake = true
		p.force_exit_vehicle()
	state = T.NONE
	if Game.hud != null:
		Game.hud.info_text = ""
		if Game.hud.waypoint != null and (Game.hud.waypoint as Vector3).distance_to(p.global_position) < 40.0:
			Game.hud.set_waypoint(null)
	var c := cab
	cab = null
	if c != null and is_instance_valid(c):
		c.owner_tag = "traffic"
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			if is_instance_valid(c) and c.ai is AIDriver:
				(c.ai as AIDriver).cruise())

func _on_exit(v: Node3D) -> void:
	if state == T.RIDING and v == cab:
		# got out early: pay what the meter shows
		var f := fare()
		var paid := mini(f, Game.cash)
		if paid > 0:
			Game.add_cash(-paid, false)
			Game.notify("ZipCab fare: $%d" % paid, "money")
		_reset()

func _process(delta: float) -> void:
	_tick -= delta
	if state == T.RIDING and Input.is_action_just_pressed("jump") and not Game.ui_blocked():
		skip_trip()
	if _tick > 0.0:
		return
	_tick = 0.25
	var p: Player = Game.player
	if p == null:
		return
	match state:
		T.COMING:
			_timer += 0.25
			if not _cab_ok():
				Game.notify("Your cab did not make it", "bad")
				_reset()
				return
			var d := cab.global_position.distance_to(p.global_position)
			var ai: AIDriver = cab.ai as AIDriver
			if d < 16.0 or (ai != null and ai.arrived and d < 40.0):
				state = T.WAITING
				_timer = 0.0
				if ai != null:
					ai.hold()
				cab.horn(true)
				get_tree().create_timer(0.5).timeout.connect(func() -> void:
					if is_instance_valid(cab):
						cab.horn(false))
				Game.notify("Your ZipCab is here - press F to get in", "good")
			elif ai != null and (ai.arrived or ai.dead_end or _timer > 8.0 and int(_timer) % 8 == 0):
				ai.drive_to(p.global_position, false)
			if _timer > 120.0:
				Game.notify("The cab gave up looking for you", "bad")
				_reset()
		T.WAITING:
			_timer += 0.25
			if not _cab_ok() or _timer > 90.0:
				_reset()
		T.RIDING:
			if not _cab_ok() or p.vehicle != cab:
				if state == T.RIDING and not _cab_ok():
					_reset()
				return
			travelled += cab.global_position.distance_to(_last)
			_last = cab.global_position
			if Game.hud != null:
				Game.hud.info_text = "ZipCab to %s    fare $%d    [Space] skip trip (+$%d)" % [dest_name if dest_name != "" else "...", fare(), SKIP_FEE] if dest != Vector3.ZERO else "ZipCab    fare $%d" % fare()
			var ai2: AIDriver = cab.ai as AIDriver
			if dest != Vector3.ZERO and (cab.global_position.distance_to(dest) < 18.0 or (ai2 != null and ai2.arrived)) and absf(cab.speed) < 2.0:
				_arrive()

func save_state() -> Dictionary:
	return {}

func load_state(_d: Dictionary) -> void:
	_reset()
