extends Node3D
## System "interactions" (BootManifest): generic world use points that no shop / garage owns
## (docs/SAVE.md section "Interactions"). One manager, no script per object:
##
##   seat        street / park benches, bus-shelter benches, tram-stop benches, picnic-table seats
##               (props instances + tram-stop `Use_Bench` markers) -> player state "int_sit"
##   binoculars  coin-op viewpoint binoculars (props `viewpoint_binoculars`, marker `Use`) ->
##               player state "int_view" (zoom camera, binocular mask)
##   vending     drinks machines (props `vending_machine`): $4 "Bay Fizz" = +12 health, full stamina
##   atm         cash machines (props `atm` + a few placed through props.spawn_prop() beside landmark
##               entrances): keyboard panel with a bank account (deposit / withdraw, daily limit,
##               transaction cooldown - an ATM never creates money); with a crowbar or bat in hand
##               it can be broken open (cash pickup + Wanted "robbery"; out of service for a day)
##   lift        hospital lobby lift <-> roof (helipad) and the lighthouse stair <-> gallery
##
## Landmark doors are NOT handled here: the city builder already animates every `Door_*`.
## The parking structure has no lift markers, so it has no lift.
##
## Points are collected once at EventBus.game_ready (props / city exist then). A pool of
## POOL_SIZE Interactables is moved onto the nearest points around the player a few times per second,
## so the player's interaction scanner only ever sees a handful of nodes.
## Persistence: SaveSystem provider "interactions" (bank balance, daily withdrawals, robbed ATMs).

signal point_used(index: int, kind: String)

const POOL_SIZE := 8
const ACTIVE_RADIUS := 22.0
const REFRESH_INTERVAL := 0.25
const SIT_STATE_PATH := "res://gta/code/world/interactions/int_state_sit.gd"
const VIEW_STATE_PATH := "res://gta/code/world/interactions/int_state_view.gd"
const ATM_PANEL_PATH := "res://gta/code/world/interactions/int_atm_panel.gd"
const VIEW_OVERLAY_PATH := "res://gta/code/world/interactions/int_view_overlay.gd"
const SIT_STATE := "int_sit"
const VIEW_STATE := "int_view"

const VENDING_PRICE := 4
const VENDING_HEAL := 12.0
const ATM_DAILY_LIMIT := 2000
const ATM_TX_COOLDOWN := 1.0                 ## s between two transactions
const ATM_ROB_TIME := 2.4                    ## s of prying
const ATM_ROB_MIN := 160
const ATM_ROB_MAX := 420
const ATM_OUT_OF_SERVICE_HOURS := 24.0
const ROB_WEAPONS: Array[String] = ["crowbar", "bat"]
## Extra cash machines beside these landmark entrances (only where the spot is free).
const EXTRA_ATM_LANDMARKS: Array[String] = ["general_store", "hospital", "clothing_store", "police_station"]
const LIFT_RIDE_SECONDS := 1.6

## Hospital lift (building-local Godot coordinates, from the hospital asset: lift doors on the lobby
## back wall at Blender (-0.9 / 0.7, 2.3) -> stand point between them; roof bulkhead door on its -X
## face at Blender x 8.5, y -9.5 -> stand point 0.9 m outside it on the roof).
const HOSPITAL_LOBBY_LIFT := Vector3(-0.1, 0.06, -3.15)
const HOSPITAL_LOBBY_YAW_IN := PI           ## facing the lift doors (+Z)
const HOSPITAL_ROOF_DEFAULT_Y := 18.2
const HOSPITAL_ROOF_LIFT := Vector3(7.55, 0.0, 9.5)   ## y = roof height (manifest roof_height)
const HOSPITAL_ROOF_YAW_OUT := PI * 0.5      ## stepping out of the bulkhead faces -X

var enabled: bool = true
var points: Array[Dictionary] = []
var bank_balance: int = 0
var stats: Dictionary = {"vending": 0, "deposits": 0, "withdrawals": 0, "robberies": 0, "lift_rides": 0,
		"sits": 0, "views": 0, "extra_atms": 0}
var busy: bool = false                       ## a lift ride / robbery / ATM session is running
var atm_open_point: int = -1

var _pool: Array[Interactable] = []
var _assign: PackedInt32Array = PackedInt32Array()
var _refresh_t: float = 0.0
var _collected: bool = false
var _sit_script: Script = null
var _view_script: Script = null
var _layer: CanvasLayer = null
var _atm_panel: Control = null
var _overlay: Control = null
var _withdrawn_today: int = 0
var _withdraw_day: int = -1
var _robbed: Dictionary = {}                 ## point key -> WorldClock.total_hours when it works again
var _tx_cd: float = 0.0                     ## game seconds until the ATM accepts the next transaction
var _hud_hidden_by_us: bool = false
var _last_state: String = ""


func setup() -> void:
	SaveSystem.register_provider("interactions", self)
	if not EventBus.game_ready.is_connected(_on_game_ready):
		EventBus.game_ready.connect(_on_game_ready, CONNECT_ONE_SHOT)
	_build_pool()
	_layer = CanvasLayer.new()
	_layer.name = "InteractionsUI"
	_layer.layer = 9
	add_child(_layer)


func set_enabled(on: bool) -> void:
	enabled = on
	for it: Interactable in _pool:
		it.enabled = false
	if not on:
		close_atm()
		if _player_state() == SIT_STATE or _player_state() == VIEW_STATE:
			Game.player.call("change_state", "on_foot", {})


func _on_game_ready() -> void:
	if not _collected:
		collect_points()


# =================================================================================================
# points
# =================================================================================================

## (Re)builds the point list from the props system and the city. Called once at game_ready.
func collect_points() -> void:
	points.clear()
	_collected = true
	var props := Game.get_system("props")
	if props != null and props.has_method("find_instances"):
		_collect_props(props)
		_place_extra_atms(props)
	_collect_tram_benches()
	_collect_lifts()
	for it: Interactable in _pool:
		it.enabled = false
	_assign.fill(-1)
	print("[Interactions] %d use points: %s" % [points.size(), str(get_counts())])


func get_counts() -> Dictionary:
	var out := {}
	for p: Dictionary in points:
		out[p["kind"]] = int(out.get(p["kind"], 0)) + 1
	return out


## Points of one kind ("" = all). Each: {kind, key, pos, stand: Transform3D, radius, src, inst, ...}.
func get_points(kind: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in points:
		if kind == "" or p["kind"] == kind:
			out.append(p)
	return out


## Index of the nearest point of `kind` within `radius` of `near` (-1 = none).
func find_point(kind: String, near: Vector3, radius: float = INF) -> int:
	var best := -1
	var best_d := radius * radius if radius < INF else INF
	for i in points.size():
		var p: Dictionary = points[i]
		if kind != "" and p["kind"] != kind:
			continue
		var d := (p["pos"] as Vector3).distance_squared_to(near)
		if d < best_d:
			best_d = d
			best = i
	return best


func _add_point(kind: String, pos: Vector3, stand: Transform3D, extra: Dictionary = {}) -> int:
	var p := {"kind": kind, "pos": pos, "stand": stand, "radius": 1.5, "src": "", "inst": -1,
			"key": "%s@%d,%d,%d" % [kind, roundi(pos.x * 2.0), roundi(pos.y * 2.0), roundi(pos.z * 2.0)]}
	p.merge(extra, true)
	points.append(p)
	return points.size() - 1


func _collect_props(props: Node) -> void:
	# benches: seat 0.12 m in front of the origin, facing the prop's -Z (manifest "sitter faces +Y")
	for id: String in ["bench", "bench_park"]:
		for i: int in props.call("find_instances", id):
			var xf := _flat(props.call("get_instance_transform", i) as Transform3D)
			_add_seat(xf, Vector3(0.0, 0.0, -0.12), 0.41, 0.62, {"src": id, "inst": i})
	# bus shelters: bench inside, two seats
	for i: int in props.call("find_instances", "bus_stop"):
		var xf := _flat(props.call("get_instance_transform", i) as Transform3D)
		for x: float in [-0.2, 0.9]:
			_add_seat(xf, Vector3(x, 0.0, 0.22), 0.46, 0.62, {"src": "bus_stop", "inst": i})
	# picnic tables: Seat_1..4 markers (seat height 0.48, stand up backwards over the bench)
	var pt_def: Dictionary = props.call("get_prop_def", "picnic_table") if props.has_method("get_prop_def") else {}
	var marks: Variant = pt_def.get("markers", {})
	var seats: Array = []
	if marks is Dictionary and not (marks as Dictionary).is_empty():
		var yaws: Variant = pt_def.get("marker_yaw_deg", {})
		for k: String in ["Seat_1", "Seat_2", "Seat_3", "Seat_4"]:
			var m: Variant = (marks as Dictionary).get(k, null)
			if m is Array and (m as Array).size() >= 3:
				var yaw := deg_to_rad(float((yaws as Dictionary).get(k, 0.0))) if yaws is Dictionary else 0.0
				seats.append([Vector3(float(m[0]), 0.0, float(m[2])), yaw])
	else:
		seats = [[Vector3(-0.45, 0.0, -0.78), PI], [Vector3(0.45, 0.0, -0.78), PI],
				[Vector3(-0.45, 0.0, 0.78), 0.0], [Vector3(0.45, 0.0, 0.78), 0.0]]
	for i: int in props.call("find_instances", "picnic_table"):
		var xf := _flat(props.call("get_instance_transform", i) as Transform3D)
		for s: Array in seats:
			var local_xf := Transform3D(Basis(Vector3.UP, float(s[1])), s[0])
			var sx := xf * local_xf
			var back := sx.basis.z.normalized()
			_add_point("seat", sx.origin + Vector3.UP * 0.9, sx, {"height": 0.45, "stand_up": sx.origin + back * 0.6,
					"src": "picnic_table", "inst": i, "radius": 1.2})
	# vending machines / ATMs: the customer stands 0.95 m in front (their fronts face -Z)
	for i: int in props.call("find_instances", "vending_machine"):
		var xf := _flat(props.call("get_instance_transform", i) as Transform3D)
		_add_front_point("vending", xf, {"src": "vending_machine", "inst": i})
	for i: int in props.call("find_instances", "atm"):
		var xf := _flat(props.call("get_instance_transform", i) as Transform3D)
		_add_front_point("atm", xf, {"src": "atm", "inst": i})
	# viewpoint binoculars: the viewer stands at marker Use (local z +0.75) looking along -Z
	for i: int in props.call("find_instances", "viewpoint_binoculars"):
		var xf := _flat(props.call("get_instance_transform", i) as Transform3D)
		var use := Transform3D(xf.basis, xf * Vector3(0.0, 0.0, 0.75))
		_add_point("binoculars", use.origin + Vector3.UP * 1.0, use, {"src": "viewpoint_binoculars", "inst": i, "radius": 1.3})


func _add_seat(xf: Transform3D, local: Vector3, height: float, stand_dist: float, extra: Dictionary) -> void:
	var seat := Transform3D(xf.basis, xf * local)
	var fwd := -xf.basis.z.normalized()
	var e := {"height": height, "stand_up": seat.origin + fwd * stand_dist, "radius": 1.35}
	e.merge(extra, true)
	_add_point("seat", seat.origin + Vector3.UP * 0.8, seat, e)


func _add_front_point(kind: String, xf: Transform3D, extra: Dictionary) -> int:
	var fwd := -xf.basis.z.normalized()
	var stand_pos := xf.origin + fwd * 0.95
	# the customer faces the machine (+Z of the machine = towards it)
	var stand := Transform3D(Basis.looking_at(-fwd, Vector3.UP), stand_pos)
	var e := {"radius": 1.45}
	e.merge(extra, true)
	return _add_point(kind, xf.origin + fwd * 0.75 + Vector3.UP * 1.0, stand, e)


func _collect_tram_benches() -> void:
	var city := Game.get_system("city")
	if city == null or not city.has_method("has_landmark_marker"):
		return
	for lm: String in ["tram_stop_1", "tram_stop_2", "tram_stop_3"]:
		if not bool(city.call("has_landmark_marker", lm, "Use_Bench")):
			continue
		var m := _flat(city.call("get_landmark_marker", lm, "Use_Bench") as Transform3D)
		# the marker stands 0.18 m in front of the seat line; two seats along the 2.6 m bench
		for x: float in [-0.55, 0.55]:
			var seat := Transform3D(m.basis, m * Vector3(x, 0.0, 0.18))
			_add_point("seat", seat.origin + Vector3.UP * 0.8, seat, {"height": 0.44, "stand_up": m * Vector3(x, 0.0, -0.25),
					"src": "tram_stop", "landmark": lm, "radius": 1.35})


func _collect_lifts() -> void:
	var city := Game.get_system("city")
	if city == null or not city.has_method("has_landmark"):
		return
	if bool(city.call("has_landmark", "hospital")):
		var bx := _flat(city.call("get_landmark_transform", "hospital") as Transform3D)
		var lobby_local := Transform3D(Basis(Vector3.UP, HOSPITAL_LOBBY_YAW_IN), HOSPITAL_LOBBY_LIFT)
		var roof_local := Transform3D(Basis(Vector3.UP, HOSPITAL_ROOF_YAW_OUT),
				Vector3(HOSPITAL_ROOF_LIFT.x, HOSPITAL_ROOF_DEFAULT_Y, HOSPITAL_ROOF_LIFT.z))
		var lobby := _flat(bx * lobby_local)
		var roof := _flat(bx * roof_local)
		# the real roof surface under the stand point (collider), else the manifest roof height
		var space := get_world_3d().direct_space_state if is_inside_tree() else null
		if space != null:
			var rq := PhysicsRayQueryParameters3D.create(roof.origin + Vector3.UP * 4.0, roof.origin - Vector3.UP * 4.0, Layers.WORLD)
			var hit := space.intersect_ray(rq)
			if not hit.is_empty():
				roof.origin.y = float((hit["position"] as Vector3).y)
			var lq := PhysicsRayQueryParameters3D.create(lobby.origin + Vector3.UP * 1.5, lobby.origin - Vector3.UP * 1.5, Layers.WORLD)
			var lhit := space.intersect_ray(lq)
			if not lhit.is_empty():
				lobby.origin.y = float((lhit["position"] as Vector3).y)
		# arrivals: out of the lift into the lobby (facing away from the doors) / onto the roof
		var lobby_arrive := Transform3D(Basis(Vector3.UP, PI) * lobby.basis, lobby.origin)
		var a := _add_point("lift", lobby.origin + Vector3.UP * 1.1, lobby, {"label": "Take the lift to the roof",
				"arrive": lobby_arrive, "src": "hospital", "radius": 1.6})
		var b2 := _add_point("lift", roof.origin + Vector3.UP * 1.1, roof, {"label": "Take the lift down to the lobby",
				"arrive": roof, "src": "hospital", "radius": 1.6})
		points[a]["dest"] = b2
		points[b2]["dest"] = a
	if bool(city.call("has_landmark", "lighthouse")) and bool(city.call("has_landmark_marker", "lighthouse", "Door")) \
			and bool(city.call("has_landmark_marker", "lighthouse", "Gallery")):
		var door := _flat(city.call("get_landmark_marker", "lighthouse", "Door") as Transform3D)
		var gal := _flat(city.call("get_landmark_marker", "lighthouse", "Gallery") as Transform3D)
		var door_out := Transform3D(Basis(Vector3.UP, PI) * door.basis, door.origin)
		var a := _add_point("lift", door.origin + Vector3.UP * 1.1, door, {"label": "Climb the stairs to the gallery",
				"arrive": door_out, "src": "lighthouse", "radius": 1.8, "ride": 2.4})
		var b2 := _add_point("lift", gal.origin + Vector3.UP * 1.1, gal, {"label": "Take the stairs down",
				"arrive": gal, "src": "lighthouse", "radius": 1.5, "ride": 2.0})
		points[a]["dest"] = b2
		points[b2]["dest"] = a


## Up to a few extra ATMs beside landmark entrances, through props.spawn_prop() (static prop with
## its own collider); a spot is used only if a box test finds it free.
func _place_extra_atms(props: Node) -> void:
	var city := Game.get_system("city")
	if city == null or not props.has_method("spawn_prop") or not city.has_method("has_landmark_marker"):
		return
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.7, 1.1)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = Layers.WORLD | Layers.PROP | Layers.VEHICLE
	for lm: String in EXTRA_ATM_LANDMARKS:
		if not bool(city.call("has_landmark_marker", lm, "Entrance")):
			continue
		var ent := _flat(city.call("get_landmark_marker", lm, "Entrance") as Transform3D)
		var out := ent.basis.z.normalized()      # Entrance -Z points INTO the building
		var right := ent.basis.x.normalized()
		for side: float in [1.0, -1.0]:
			var cand := ent.origin + out * 0.75 + right * side * 2.5
			var floor_y := _floor_at(space, cand)
			if is_inf(floor_y):
				continue
			cand.y = floor_y
			var xf := Transform3D(Basis.looking_at(out, Vector3.UP), cand)    # ATM front (-Z) faces out
			q.transform = Transform3D(xf.basis, cand + Vector3.UP * 1.0)
			if not space.intersect_shape(q, 1).is_empty():
				continue
			# the customer spot in front must be free too
			q.transform = Transform3D(xf.basis, cand + out * 1.0 + Vector3.UP * 1.0)
			if not space.intersect_shape(q, 1).is_empty():
				continue
			var node: Variant = props.call("spawn_prop", "atm", xf)
			if node is Node3D:
				_add_front_point("atm", xf, {"src": "spawned", "landmark": lm, "node": node})
				stats["extra_atms"] = int(stats["extra_atms"]) + 1
				break


func _floor_at(space: PhysicsDirectSpaceState3D, p: Vector3) -> float:
	var rq := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.5, p - Vector3.UP * 3.0, Layers.WORLD)
	var hit := space.intersect_ray(rq)
	if hit.is_empty():
		return INF
	var y := float((hit["position"] as Vector3).y)
	return y if absf(y - p.y) < 2.0 else INF


static func _flat(xf: Transform3D) -> Transform3D:
	var f := -xf.basis.z
	f.y = 0.0
	if f.length_squared() < 0.0001:
		f = Vector3.FORWARD
	return Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), xf.origin)


# =================================================================================================
# pool
# =================================================================================================

func _build_pool() -> void:
	_assign.resize(POOL_SIZE)
	_assign.fill(-1)
	for k in POOL_SIZE:
		var it := Interactable.create("Interact", 1.5)
		it.name = "Use_%d" % k
		it.enabled = false
		it.cooldown = 0.35
		it.set_meta(&"pool_index", k)
		it.condition = _can_use_slot.bind(k)
		it.interacted.connect(_on_pool_interacted.bind(k))
		add_child(it)
		_pool.append(it)


func _process(delta: float) -> void:
	if _tx_cd > 0.0:
		_tx_cd -= delta
	var st := _player_state()
	if st != _last_state:
		_on_player_state_changed(_last_state, st)
		_last_state = st
	if st == VIEW_STATE and _overlay != null and _overlay.visible:
		var s: Variant = Game.player.get("state")
		if s is Object and (s as Object).has_method("get_fov"):
			_overlay.call("set_zoom_text", "x%.1f" % (70.0 / maxf(float((s as Object).call("get_fov")), 1.0)))
	_refresh_t -= delta
	if _refresh_t > 0.0:
		return
	_refresh_t = REFRESH_INTERVAL
	_refresh_pool()


func _refresh_pool() -> void:
	if not enabled or points.is_empty() or not Game.has_player():
		for it: Interactable in _pool:
			it.enabled = false
		return
	var pp := Game.get_player_position()
	# nearest points inside ACTIVE_RADIUS (the list is small: a linear scan is cheaper than a grid)
	var near: Array = []
	var r2 := ACTIVE_RADIUS * ACTIVE_RADIUS
	for i in points.size():
		var d := (points[i]["pos"] as Vector3).distance_squared_to(pp)
		if d < r2:
			near.append([d, i])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var wanted := {}
	for k in mini(near.size(), POOL_SIZE):
		wanted[int(near[k][1])] = true
	# keep slots whose point is still wanted, refill the others
	var free_slots: Array[int] = []
	for k in POOL_SIZE:
		var pi := _assign[k]
		if pi >= 0 and wanted.has(pi):
			wanted.erase(pi)
		else:
			_assign[k] = -1
			free_slots.append(k)
	for pi: Variant in wanted.keys():
		if free_slots.is_empty():
			break
		var k: int = free_slots.pop_back()
		_assign[k] = int(pi)
		var it := _pool[k]
		var p: Dictionary = points[int(pi)]
		it.global_position = p["pos"]
		it.radius = float(p["radius"])
		var shape := it.get_child(0) as CollisionShape3D if it.get_child_count() > 0 else null
		if shape != null and shape.shape is SphereShape3D:
			(shape.shape as SphereShape3D).radius = it.radius
	for k in POOL_SIZE:
		var it := _pool[k]
		var pi := _assign[k]
		if pi < 0:
			it.enabled = false
			continue
		it.enabled = true
		it.prompt = _prompt_for(pi)
		it.use_priority = 10 if _is_active_point(pi) else 1


func _is_active_point(pi: int) -> bool:
	var st := _player_state()
	if st != SIT_STATE and st != VIEW_STATE:
		return false
	var s: Variant = Game.player.get("state")
	return s is Object and int((s as Object).get("point_index")) == pi


func _prompt_for(pi: int) -> String:
	var p: Dictionary = points[pi]
	match str(p["kind"]):
		"seat":
			return "Stand up" if _is_active_point(pi) else "Sit down"
		"binoculars":
			return "Step away" if _is_active_point(pi) else "Use binoculars"
		"vending":
			var price := _price(VENDING_PRICE)
			return "Buy a Bay Fizz ($%d)" % price if price > 0 else "Take a Bay Fizz"
		"atm":
			if is_atm_out_of_service(pi):
				return "ATM out of service"
			if _holding_rob_weapon():
				return "Break open the ATM"
			return "Use ATM (account $%d)" % bank_balance
		"lift":
			return str(p.get("label", "Use the lift"))
	return "Interact"


func _can_use_slot(_player: Node3D, k: int) -> bool:
	if not enabled or busy or k < 0 or k >= POOL_SIZE:
		return false
	var pi := _assign[k]
	if pi < 0 or pi >= points.size():
		return false
	return can_use_point(pi)


## Whether the point is usable right now (prop intact, seat free, no other activity running).
func can_use_point(pi: int) -> bool:
	if pi < 0 or pi >= points.size() or not Game.has_player() or busy:
		return false
	var p: Dictionary = points[pi]
	var st := _player_state()
	if st == SIT_STATE or st == VIEW_STATE:
		return _is_active_point(pi)
	if st != "on_foot":
		return false
	if not _prop_intact(p):
		return false
	if str(p["kind"]) == "seat":
		return not _seat_occupied(p)
	return true


func _prop_intact(p: Dictionary) -> bool:
	var inst := int(p.get("inst", -1))
	if inst >= 0:
		var props := Game.get_system("props")
		if props != null and props.has_method("get_instance_state"):
			return str(props.call("get_instance_state", inst)) == "idle"
	var node: Variant = p.get("node", null)
	if node != null:
		return is_instance_valid(node)
	return true


func _seat_occupied(p: Dictionary) -> bool:
	var sp := (p["stand"] as Transform3D).origin
	for n: Node in get_tree().get_nodes_in_group("npc"):
		var c := n as Node3D
		if c != null and c.is_inside_tree() and c.global_position.distance_squared_to(sp) < 0.36:
			return true
	return false


func _on_pool_interacted(player: Node3D, k: int) -> void:
	if k < 0 or k >= POOL_SIZE:
		return
	var pi := _assign[k]
	if pi >= 0:
		use_point(pi, player)


# =================================================================================================
# using points
# =================================================================================================

## Same as pressing the use key at point `pi` (the player must be in reach for the pooled prompt;
## this entry point is also used by tests). Returns true if something happened.
func use_point(pi: int, player: Node3D = null) -> bool:
	if pi < 0 or pi >= points.size():
		return false
	if player == null:
		player = Game.player
	if player == null or not is_instance_valid(player):
		return false
	var p: Dictionary = points[pi]
	var kind := str(p["kind"])
	if _is_active_point(pi):
		player.call("change_state", "on_foot", {})
		return true
	if not can_use_point(pi):
		return false
	var ok := false
	match kind:
		"seat":
			ok = sit_at(pi)
		"binoculars":
			ok = start_view(pi)
		"vending":
			ok = buy_drink(pi)
		"atm":
			if is_atm_out_of_service(pi):
				UI.notify("This cash machine is out of service", "warn")
				Audio.play("ui_error", -8.0)
			elif _holding_rob_weapon():
				rob_atm(pi)
				ok = true
			else:
				ok = open_atm(pi)
		"lift":
			ride_lift(pi)
			ok = true
	if ok:
		point_used.emit(pi, kind)
	return ok


func sit_at(pi: int) -> bool:
	if not _ensure_state(SIT_STATE):
		return false
	var p: Dictionary = points[pi]
	var seat: Transform3D = p["stand"]          # ground point under the hips, -Z = facing
	var up_pos: Vector3 = p.get("stand_up", seat.origin - seat.basis.z * 0.6)
	Game.player.call("change_state", SIT_STATE, {"seat": seat, "height": float(p.get("height", 0.41)),
			"stand": up_pos, "point": pi})
	if _player_state() != SIT_STATE:
		return false
	stats["sits"] = int(stats["sits"]) + 1
	_refresh_t = 0.0
	return true


func stand_up() -> void:
	if _player_state() == SIT_STATE or _player_state() == VIEW_STATE:
		Game.player.call("change_state", "on_foot", {})


func start_view(pi: int) -> bool:
	if not _ensure_state(VIEW_STATE):
		return false
	Game.player.call("change_state", VIEW_STATE, {"stand": points[pi]["stand"], "point": pi})
	if _player_state() != VIEW_STATE:
		return false
	stats["views"] = int(stats["views"]) + 1
	_refresh_t = 0.0
	return true


func buy_drink(pi: int) -> bool:
	var price := _price(VENDING_PRICE)
	var p := Game.player
	if not Game.spend(price):
		UI.notify("Not enough cash for a drink", "warn")
		Audio.play("ui_error", -6.0)
		return false
	EventBus.item_purchased.emit("vending", "bay_fizz", price)
	var mh := float(p.get("max_health")) if p.get("max_health") != null else 100.0
	if p.has_method("heal"):
		p.call("heal", minf(VENDING_HEAL, maxf(mh - float(p.get("health")), 0.0)))
	p.set("stamina", 1.0)
	if p.has_method("play_action"):
		p.call("play_action", "pickup", 0.6)
	Audio.play_at("cash_register", points[pi]["pos"], -8.0, 1.2, 20.0)
	Audio.play_at("pickup_health", points[pi]["pos"], -10.0, 1.0, 20.0)
	stats["vending"] = int(stats["vending"]) + 1
	return true


func ride_lift(pi: int) -> void:
	var p: Dictionary = points[pi]
	var di := int(p.get("dest", -1))
	if di < 0 or di >= points.size() or busy:
		return
	busy = true
	var dest: Dictionary = points[di]
	var arrive: Transform3D = dest.get("arrive", dest["stand"])
	var f := -arrive.basis.z
	var yaw := atan2(-f.x, -f.z)
	var is_stair := str(p.get("src", "")) == "lighthouse"
	Game.lock_input()
	Audio.play_at("footstep_concrete" if is_stair else "door_close", p["pos"], -6.0, 1.0, 20.0)
	await UI.fade_out(0.35)
	if Game.has_player():
		Game.player.call("teleport", arrive.origin + Vector3.UP * 0.05, yaw)
	await get_tree().create_timer(float(p.get("ride", LIFT_RIDE_SECONDS)) * 0.5).timeout
	if not is_stair:
		Audio.play("tram_bell", -16.0, 1.6, "SFX")
		Audio.play_at("door_open", arrive.origin + Vector3.UP, -6.0, 1.0, 20.0)
	await UI.fade_in(0.45)
	Game.unlock_input()
	busy = false
	stats["lift_rides"] = int(stats["lift_rides"]) + 1
	_refresh_t = 0.0


# --- ATM / bank ------------------------------------------------------------------------------------

func open_atm(pi: int) -> bool:
	if atm_open_point >= 0 or is_atm_out_of_service(pi):
		return false
	if _atm_panel == null:
		var scr: Script = load(ATM_PANEL_PATH) if ResourceLoader.exists(ATM_PANEL_PATH) else null
		if scr == null or not scr.can_instantiate():
			return false
		_atm_panel = scr.new() as Control
		_atm_panel.name = "AtmPanel"
		_layer.add_child(_atm_panel)
		_atm_panel.connect("option_chosen", _on_atm_option)
	atm_open_point = pi
	busy = true
	Game.lock_input()
	_atm_panel.visible = true
	_update_atm_panel("Insert card... welcome!")
	Audio.play_at("ui_open", points[pi]["pos"], -8.0, 1.1, 15.0)
	return true


func close_atm() -> void:
	if atm_open_point < 0:
		return
	atm_open_point = -1
	busy = false
	Game.unlock_input()
	if _atm_panel != null:
		_atm_panel.visible = false
	Audio.play("ui_close", -8.0)
	_refresh_t = 0.0


func _on_atm_option(option: String) -> void:
	if atm_open_point < 0:
		return
	if option == "close":
		close_atm()
		return
	var msg := ""
	if _tx_cd > 0.0:
		msg = "Processing - please wait"
	else:
		match option:
			"w100":
				msg = _tx_msg(withdraw(100), "Withdrew")
			"w500":
				msg = _tx_msg(withdraw(500), "Withdrew")
			"d100":
				msg = _tx_msg(deposit(100), "Deposited")
			"dall":
				msg = _tx_msg(deposit(Game.money), "Deposited")
	_update_atm_panel(msg)


func _tx_msg(amount: int, verb: String) -> String:
	if amount > 0:
		_tx_cd = ATM_TX_COOLDOWN
		Audio.play("cash_register", -8.0, 1.0, "UI")
		return "%s $%d" % [verb, amount]
	Audio.play("ui_error", -8.0)
	return str(get_meta(&"last_tx_error", "Transaction declined"))


func _update_atm_panel(status: String) -> void:
	if _atm_panel != null:
		_atm_panel.call("show_values", Game.money, bank_balance, get_withdraw_remaining(), status)


## Moves up to `amount` cash into the bank account. Returns the amount moved (0 = declined).
func deposit(amount: int) -> int:
	var a := mini(amount, Game.money)
	if a <= 0:
		set_meta(&"last_tx_error", "No cash to deposit")
		return 0
	if not Game.spend(a):
		set_meta(&"last_tx_error", "No cash to deposit")
		return 0
	bank_balance += a
	stats["deposits"] = int(stats["deposits"]) + 1
	return a


## Moves up to `amount` from the account into cash (daily limit). Returns the amount (0 = declined).
func withdraw(amount: int) -> int:
	var a := mini(mini(amount, bank_balance), get_withdraw_remaining())
	if a <= 0:
		set_meta(&"last_tx_error", "Insufficient funds" if bank_balance <= 0 else "Daily withdrawal limit reached")
		return 0
	_roll_day()
	bank_balance -= a
	_withdrawn_today += a
	Game.add_money(a)
	stats["withdrawals"] = int(stats["withdrawals"]) + 1
	return a


func get_bank_balance() -> int:
	return bank_balance


func get_withdraw_remaining() -> int:
	_roll_day()
	return maxi(ATM_DAILY_LIMIT - _withdrawn_today, 0)


func _roll_day() -> void:
	var day := int(WorldClock.get("day")) if WorldClock.get("day") != null else 1
	if day != _withdraw_day:
		_withdraw_day = day
		_withdrawn_today = 0


func is_atm_out_of_service(pi: int) -> bool:
	if pi < 0 or pi >= points.size():
		return true
	var until: Variant = _robbed.get(points[pi]["key"], null)
	if until == null:
		return false
	if _clock_hours() >= float(until):
		_robbed.erase(points[pi]["key"])
		return false
	return true


## Pry the machine open (crowbar / bat in hand): ~2.4 s of blows, sparks, then a cash pickup at the
## machine and a robbery report (witness logic is Wanted's). Out of service for a day afterwards.
func rob_atm(pi: int) -> void:
	if busy or is_atm_out_of_service(pi):
		return
	busy = true
	var p: Dictionary = points[pi]
	var pl := Game.player
	var stand: Transform3D = p["stand"]
	var f := -stand.basis.z
	pl.call("teleport", stand.origin + Vector3.UP * 0.03, atan2(-f.x, -f.z))
	pl.call("set_control_enabled", false)
	var hit_pos: Vector3 = (p["pos"] as Vector3) + f * 0.15
	var blows := 3
	for b in blows:
		if pl.has_method("play_action"):
			pl.call("play_action", "heavy", 0.6)
		await get_tree().create_timer(ATM_ROB_TIME / float(blows)).timeout
		if not is_instance_valid(pl) or pl.get("is_dead") == true:
			busy = false
			return
		Audio.play_at("impact_metal", hit_pos, -2.0, randf_range(0.9, 1.1), 40.0)
		Fx.sparks(hit_pos, -f, 0.8)
		EventBus.noise_emitted.emit(hit_pos, 30.0, "melee", pl)
	pl.call("set_control_enabled", true)
	var amount := Game.rng.randi_range(ATM_ROB_MIN, ATM_ROB_MAX)
	var drop := (p["pos"] as Vector3) + f * 0.6 - Vector3.UP * 0.9
	var pickups := Game.get_system("pickups")
	var dropped: Variant = null
	if pickups != null and pickups.has_method("spawn_pickup"):
		dropped = pickups.call("spawn_pickup", "cash", "", amount, drop)
	if dropped == null:
		Game.add_money(amount)
	Audio.play_at("glass_break", hit_pos, -6.0, 1.3, 40.0)
	Wanted.report_crime("robbery", hit_pos, {"instigator": pl})
	_robbed[p["key"]] = _clock_hours() + ATM_OUT_OF_SERVICE_HOURS
	stats["robberies"] = int(stats["robberies"]) + 1
	set_meta(&"last_robbery_amount", amount)
	busy = false
	_refresh_t = 0.0


func _holding_rob_weapon() -> bool:
	if not Game.has_player():
		return false
	var inv: Variant = Game.player.get("inventory")
	if not (inv is Object) or not is_instance_valid(inv):
		return false
	return ROB_WEAPONS.has(str((inv as Object).get("current_id")))


static func _clock_hours() -> float:
	var th: Variant = WorldClock.get("total_hours")
	return float(th) if (th is float or th is int) else 0.0


static func _price(base: int) -> int:
	return 0 if Game.flags.get("free_shopping", false) == true else base


# =================================================================================================
# player states / overlays
# =================================================================================================

func _player_state() -> String:
	if not Game.has_player():
		return ""
	return str(Game.player.get("state_id"))


func _ensure_state(id: String) -> bool:
	if not Game.has_player() or not Game.player.has_method("register_state"):
		return false
	var states: Variant = Game.player.get("states")
	if states is Dictionary and (states as Dictionary).has(id):
		return true
	var path := SIT_STATE_PATH if id == SIT_STATE else VIEW_STATE_PATH
	var scr: Script = _sit_script if id == SIT_STATE else _view_script
	if scr == null:
		if not ResourceLoader.exists(path):
			return false
		scr = load(path) as Script
		if scr == null or not scr.can_instantiate():
			push_warning("[Interactions] player state script failed to load: " + path)
			return false
		if id == SIT_STATE:
			_sit_script = scr
		else:
			_view_script = scr
	var node: Variant = scr.new()
	if not (node is Node):
		return false
	Game.player.call("register_state", id, node)
	states = Game.player.get("states")
	return states is Dictionary and (states as Dictionary).has(id)


func _on_player_state_changed(from: String, to: String) -> void:
	if to == VIEW_STATE:
		_show_overlay(true)
	elif from == VIEW_STATE:
		_show_overlay(false)
	_refresh_t = 0.0


func _show_overlay(on: bool) -> void:
	if on and _overlay == null:
		var scr: Script = load(VIEW_OVERLAY_PATH) if ResourceLoader.exists(VIEW_OVERLAY_PATH) else null
		if scr != null and scr.can_instantiate():
			_overlay = scr.new() as Control
			_overlay.name = "BinocularOverlay"
			_layer.add_child(_overlay)
	if _overlay != null:
		_overlay.visible = on
	if on and UI.has_method("set_hud_visible"):
		UI.set_hud_visible(false)
		_hud_hidden_by_us = true
	elif not on and _hud_hidden_by_us:
		UI.set_hud_visible(true)
		_hud_hidden_by_us = false


func _unhandled_input(event: InputEvent) -> void:
	if _player_state() != VIEW_STATE or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	var s: Variant = Game.player.get("state")
	if not (s is Object) or not (s as Object).has_method("set_zoom"):
		return
	var z := int((s as Object).get("zoom_index"))
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		(s as Object).call("set_zoom", z + 1)
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		(s as Object).call("set_zoom", z - 1)
		get_viewport().set_input_as_handled()


func reset_for_respawn() -> void:
	close_atm()
	busy = false
	if Game.has_player():
		Game.player.call("set_control_enabled", true)


# =================================================================================================
# persistence (SaveSystem provider "interactions")
# =================================================================================================

func get_save_data() -> Dictionary:
	var robbed := {}
	var now := _clock_hours()
	for k: Variant in _robbed:
		var left := float(_robbed[k]) - now
		if left > 0.0:
			robbed[str(k)] = left
	return {"version": 1, "bank": bank_balance, "withdrawn": _withdrawn_today, "withdraw_day": _withdraw_day,
			"robbed_hours_left": robbed, "stats": stats.duplicate()}


func load_save_data(d: Dictionary) -> void:
	close_atm()
	bank_balance = maxi(int(SaveSystem._num(d.get("bank", 0), 0.0)), 0)
	_withdrawn_today = maxi(int(SaveSystem._num(d.get("withdrawn", 0), 0.0)), 0)
	_withdraw_day = int(SaveSystem._num(d.get("withdraw_day", -1), -1.0))
	_robbed.clear()
	var now := _clock_hours()
	var r: Variant = d.get("robbed_hours_left", {})
	if r is Dictionary:
		for k: Variant in r:
			var left := SaveSystem._num((r as Dictionary)[k], 0.0)
			if left > 0.0:
				_robbed[str(k)] = now + left
	var s: Variant = d.get("stats", {})
	if s is Dictionary:
		for k: Variant in s:
			if stats.has(k):
				stats[k] = int(SaveSystem._num((s as Dictionary)[k], 0.0))
	if _player_state() == SIT_STATE or _player_state() == VIEW_STATE:
		stand_up()


func get_debug_info() -> Dictionary:
	var assigned := 0
	for k in POOL_SIZE:
		if _assign[k] >= 0:
			assigned += 1
	return {"points": points.size(), "counts": get_counts(), "pool_assigned": assigned, "bank": bank_balance,
			"robbed": _robbed.size(), "stats": stats.duplicate(), "busy": busy}
