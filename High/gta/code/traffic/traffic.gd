class_name Traffic
extends Node
## Ambient civilian traffic (spawn/despawn around the player), parked cars, showcase vehicles, carjack reactions.

const MAX_AMBIENT := 14
var density := 1.0
var ambient: Array = []
var parked_spots: Array = []      # {pos, yaw, id, veh}
var showcase: Array = []          # {pos, yaw, id, veh, t}
var _t := 0.0
var _park_t := 0.0
var _weights: Array = []
var _wsum := 0.0
var root: Node3D


func _ready() -> void:
	Game.traffic = self
	root = Node3D.new()
	root.name = "Vehicles"
	add_child(root)
	for id in Data.vehicle_order:
		var d: VehicleDef = Data.vehicles[id]
		if d.traffic > 0.0:
			_weights.append([id, d.traffic])
			_wsum += d.traffic


func random_id() -> String:
	var r := Game.rng.randf() * _wsum
	for w in _weights:
		r -= w[1]
		if r <= 0.0:
			return w[0]
	return "sedan"


func spawn_vehicle(id: String, pos: Vector3, yaw: float = 0.0) -> Vehicle:
	var v := Vehicle.create(id)
	root.add_child(v)
	v.place(pos, yaw)
	return v


func add_parked(pos: Vector3, yaw: float, id: String = "") -> void:
	parked_spots.append({"pos": pos, "yaw": yaw, "id": id, "veh": null})


func add_showcase(id: String, pos: Vector3, yaw: float) -> void:
	showcase.append({"pos": pos, "yaw": yaw, "id": id, "veh": null, "t": 0.0})


func _physics_process(delta: float) -> void:
	var p = Game.player
	if p == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.35
		_ambient(p)
	_park_t -= delta
	if _park_t <= 0.0:
		_park_t = 0.5
		_parked(p)
		_showcase(p, 0.5)
	Combat.vehicle_hits()


func _ambient(p) -> void:
	var ppos: Vector3 = p.global_position
	var i := 0
	while i < ambient.size():
		var v = ambient[i]
		if not is_instance_valid(v):
			ambient.remove_at(i)
			continue
		var d: float = v.global_position.distance_to(ppos)
		var gone: bool = v.ai == null or v.dead
		if gone:
			ambient.remove_at(i)   # no longer ours (hijacked, abandoned or wrecked)
			continue
		if d > 175.0 or v.ai.want_despawn and d > 45.0 or not Game.flags.traffic or (v.drowned and d > 30.0):
			v.queue_free()
			ambient.remove_at(i)
			continue
		i += 1
	if not Game.flags.traffic:
		return
	var night: float = Game.daynight.night if Game.daynight else 0.0
	var want := int(MAX_AMBIENT * density * (1.0 - 0.45 * night))
	if ambient.size() >= want:
		return
	# pick a lane point 75..135 m away, out of view
	var cam := get_viewport().get_camera_3d()
	for attempt in range(4):
		var s: Dictionary = City.segs[Game.rng.randi() % City.segs.size()]
		var dir := Game.rng.randi() % 2
		var lane := Game.rng.randi() % int(s.lanes)
		var lp := City.lane_points(s.id, dir, lane)
		var pos: Vector3 = (lp[0] as Vector3).lerp(lp[1], Game.rng.randf_range(0.05, 0.8))
		var d2 := pos.distance_to(ppos)
		if d2 < 70.0 or d2 > 140.0:
			continue
		if cam and cam.is_position_in_frustum(pos + Vector3.UP) and d2 < 115.0:
			continue
		var clear := true
		for o in Game.vehicles:
			if is_instance_valid(o) and o.global_position.distance_to(pos) < 13.0:
				clear = false
				break
		if not clear:
			continue
		var fwd := City.seg_dir(s.id, dir)
		var v := spawn_vehicle(random_id(), pos + Vector3.UP * 0.4, atan2(-fwd.x, -fwd.z))
		v.set_ai_driver(Data.random_civilian(Game.rng))
		var ai := DriverAI.new()
		ai.start_lane(s.id, dir, lane, pos)
		v.ai = ai
		v.linear_velocity = fwd * 7.0
		if night > 0.5:
			v.set_lights(true)
		ambient.append(v)
		break


func _parked(p) -> void:
	var ppos: Vector3 = p.global_position
	for s in parked_spots:
		var d: float = (s.pos as Vector3).distance_to(ppos)
		var v = s.veh
		if v != null and not is_instance_valid(v):
			s.veh = null
			v = null
		if v == null:
			if d < 120.0 and d > 55.0 and Game.flags.traffic:
				var id: String = s.id if s.id != "" else random_id()
				var nv := spawn_vehicle(id, s.pos + Vector3.UP * 0.35, s.yaw)
				nv.parked = true
				nv.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
				nv.freeze = true
				nv.set_meta("spot", true)
				s.veh = nv
		else:
			if v.parked:
				if d > 170.0:
					v.queue_free()
					s.veh = null
				elif d < 16.0 or _vehicle_near(v, 9.0):
					v.parked = false
					v.freeze = false
			elif v.owner_is_player or v.global_position.distance_to(s.pos) > 6.0 or v.dead:
				s.veh = null     # taken or moved; the spot will refill once the player is away


func _vehicle_near(v, dist: float) -> bool:
	for o in Game.vehicles:
		if o != v and is_instance_valid(o) and not o.parked and o.global_position.distance_to(v.global_position) < dist and o.linear_velocity.length() > 2.0:
			return true
	return false


func _showcase(p, dt: float) -> void:
	var ppos: Vector3 = p.global_position
	for s in showcase:
		var v = s.veh
		var d: float = (s.pos as Vector3).distance_to(ppos)
		if v != null and not is_instance_valid(v):
			s.veh = null
			v = null
		if v == null:
			s.t -= dt
			if s.t <= 0.0 and (d > 45.0 or s.get("first", true)) and d < 260.0:
				var nv := spawn_vehicle(s.id, s.pos, s.yaw)
				s.veh = nv
				s["first"] = false
		elif v.dead or v.global_position.distance_to(s.pos) > 25.0:
			s.veh = null
			s.t = 25.0
		elif d > 320.0 and not v.owner_is_player:
			v.queue_free()
			s.veh = null
			s["first"] = true


func eject_driver(v: Vehicle, by_player: bool) -> Npc:
	var look := v.remove_ai_driver()
	ambient.erase(v)
	if look.is_empty():
		return null
	var pos := v.door_pos(0)
	pos.y = maxf(pos.y, v.global_position.y - 0.3)
	var kind := "cop" if v.def.tag == "police" else "civ"
	var n := Npc.spawn(kind, pos, look)
	n.knockdown((pos - v.global_position).normalized() * 3.0 + Vector3.UP * 1.5, Game.player if by_player else null)
	if kind == "civ":
		n.down_time = 1.2
		if n.courage > 0.8 or n.weapon != null:
			n._get_up_state = Npc.S.COMBAT
			n.target = Game.player
		else:
			n._get_up_state = Npc.S.FLEE
		n._scream()
	return n


func on_vehicle_shot(v: Vehicle, _attacker) -> void:
	if v.ai == null or v.driver_rig == null:
		return
	if Game.rng.randf() < 0.3 and absf(v.speed) < 6.0:
		eject_driver(v, false)
	else:
		v.ai.mode = "flee"


func clear_all() -> void:
	for v in ambient:
		if is_instance_valid(v):
			v.queue_free()
	ambient.clear()
