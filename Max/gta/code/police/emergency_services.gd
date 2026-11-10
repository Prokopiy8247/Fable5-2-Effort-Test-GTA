class_name EmergencyServices
extends Node
## Ambulances respond to deaths and injuries near the player, fire trucks to vehicle fires
## and explosions. Units drive on the road network with sirens (traffic pulls over), the crew
## gets out and works the scene (paramedics kneel at the casualties and take the bodies away,
## firefighters hose the fire down), then they drive off and despawn out of sight.
## The phone / admin menu can call either service to the player.

enum U { DRIVE, WORK, RETURN, LEAVE }

const MAX_UNITS := 2
const RANGE := 150.0

class Unit:
	extends RefCounted
	var kind := ""                     # ambulance | fire
	var veh: Vehicle = null
	var ai: AIDriver = null
	var crew: Array[NPC] = []
	var state := 0
	var target := Vector3.ZERO
	var timer := 0.0
	var age := 0.0
	var for_player := false

var calls: Array = []                  # {kind, pos, at, for_player}
var units: Array[Unit] = []
var rng := RandomNumberGenerator.new()
var _tick := 0.0

func _ready() -> void:
	rng.seed = 911
	Events.npc_died.connect(_on_death)
	Events.fire_started.connect(_on_fire)
	Events.explosion.connect(_on_explosion)

func _model_for(kind: String) -> String:
	return "car_ambulance" if kind == "ambulance" else "car_firetruck"

func available(kind: String) -> bool:
	return VehicleDB.has_model(_model_for(kind))

# ---------------------------------------------------------------- incidents
func _on_death(npc: Node3D, _killer: Node) -> void:
	if npc is NPC and (npc as NPC).vehicle != null:
		return
	_queue("ambulance", npc.global_position, rng.randf_range(14.0, 26.0), false)

func _on_fire(pos: Vector3, _source: Node) -> void:
	_queue("fire", pos, rng.randf_range(10.0, 18.0), false)

func _on_explosion(pos: Vector3, _radius: float, _damage: float, _source: Node) -> void:
	_queue("fire", pos, rng.randf_range(10.0, 18.0), false)

func _queue(kind: String, pos: Vector3, delay: float, for_player: bool) -> void:
	if not available(kind) or pos.distance_to(Game.player_pos()) > RANGE:
		return
	for c in calls:
		if String(c["kind"]) == kind and (c["pos"] as Vector3).distance_to(pos) < 45.0:
			return
	for u in units:
		if u.kind == kind and u.target.distance_to(pos) < 45.0 and u.state <= U.WORK:
			return
	calls.append({"kind": kind, "pos": pos, "at": Game.clock + delay, "for_player": for_player})

## Phone / admin call: kind = ambulance | fire | police.
func request(kind: String, pos: Vector3, _hurry := true) -> void:
	if kind == "police":
		var pd: PoliceDispatch = Game.police
		if pd != null:
			var spot := pd._find_spawn(pos, 50.0, 120.0)
			if not spot.is_empty():
				var u := pd.spawn_unit(&"patrol", int(spot[0]), float(spot[1]), 1)
				if u != null:
					u.ai.drive_to(pos, true)
					(u.veh as Vehicle).set_siren(true)
					Game.notify("A patrol car is on its way", "info")
					return
		Game.notify("No patrol available", "bad")
		return
	if not available(kind):
		Game.notify("No %s available right now" % ("ambulance" if kind == "ambulance" else "fire engine"), "bad")
		return
	calls.append({"kind": kind, "pos": pos, "at": Game.clock, "for_player": true})
	Game.notify("%s dispatched to your location" % ("Ambulance" if kind == "ambulance" else "Fire engine"), "info")

# ---------------------------------------------------------------- dispatch
func _dispatch(c: Dictionary) -> bool:
	var kind := String(c["kind"])
	var pos: Vector3 = c["pos"]
	var pd: PoliceDispatch = Game.police
	var spot: Array = pd._find_spawn(pos, 55.0, 110.0) if pd != null else []
	if spot.is_empty() and pd != null:
		spot = pd._find_spawn(pos, 55.0, 170.0)
	if spot.is_empty():
		return false
	var graph: RoadGraph = Game.world.graph
	var lane := int(spot[0])
	var s0 := float(spot[1])
	var p := graph.sample(lane, s0)
	var dirv := graph.direction(lane, s0)
	var v := VehicleFactory.spawn(_model_for(kind), p, atan2(-dirv.x, -dirv.z), {"tag": "service"}) as Car
	if v == null:
		return false
	var u := Unit.new()
	u.kind = kind
	u.veh = v
	u.target = pos
	u.for_player = bool(c["for_player"])
	var peds: PedManager = Game.peds
	for i in mini(2, v.seat_count()):
		var ap := _uniform(kind)
		var n := peds.seat_in(v, i, &"medic" if kind == "ambulance" else &"firefighter", ap)
		if n != null:
			u.crew.append(n)
	if u.crew.is_empty():
		v.queue_free()
		return false
	u.ai = AIDriver.attach(v, Game.traffic, lane, s0)
	if not u.ai.drive_to(pos, true):
		u.ai.cruise()
	v.set_siren(true)
	v.lights_on = true
	v.linear_velocity = dirv * 8.0
	units.append(u)
	return true

func _uniform(kind: String) -> Dictionary:
	var ap := Appearance.staff(rng, "f4f4f2" if kind == "ambulance" else "3a3328")
	ap["pants"] = "22407f" if kind == "ambulance" else "3a3328"
	ap["legs"] = "long"
	ap["sleeves"] = "short" if kind == "ambulance" else "long"
	ap["vest"] = "vest_safety"
	ap["vest_color"] = "ef7f2d" if kind == "ambulance" else "f2c230"
	if kind == "fire":
		ap["hat"] = "helmet_moto"
		ap["hat_color"] = "c81e1e"
	ap["glasses"] = ""
	return ap

# ---------------------------------------------------------------- per-frame
func _physics_process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	var dt := 0.25
	_tick = dt
	var pp := Game.player_pos()
	# due calls
	for i in range(calls.size() - 1, -1, -1):
		var c: Dictionary = calls[i]
		if Game.clock < float(c["at"]):
			continue
		var n_kind := 0
		for u in units:
			if u.kind == String(c["kind"]):
				n_kind += 1
		if (c["pos"] as Vector3).distance_to(pp) > RANGE + 40.0 and not bool(c["for_player"]):
			calls.remove_at(i)
		elif n_kind < MAX_UNITS and _dispatch(c):
			calls.remove_at(i)
		elif Game.clock > float(c["at"]) + 60.0:
			calls.remove_at(i)
	for i in range(units.size() - 1, -1, -1):
		var u := units[i]
		u.age += dt
		var alive_crew: Array[NPC] = []
		for n in u.crew:
			if is_instance_valid(n) and n.alive:
				alive_crew.append(n)
		u.crew = alive_crew
		var veh_ok := u.veh != null and is_instance_valid(u.veh) and not u.veh.destroyed
		if not veh_ok or u.crew.is_empty():
			if veh_ok and not u.veh.has_player():
				u.veh.set_siren(false)
				u.veh.owner_tag = ""
			units.remove_at(i)
			continue
		if u.for_player:
			u.target = pp if Game.player.vehicle == null else u.target
		match u.state:
			U.DRIVE: _drive(u, dt)
			U.WORK: _work(u, dt)
			U.RETURN: _return(u)
			U.LEAVE:
				var d := u.veh.global_position.distance_to(pp)
				var cam: Camera3D = Game.cam.cam if Game.cam != null else null
				var seen := cam != null and cam.is_position_in_frustum(u.veh.global_position)
				if d > RANGE or (d > 70.0 and not seen) or u.age > 240.0:
					_despawn(u)
					units.remove_at(i)

func _drive(u: Unit, dt: float) -> void:
	var v := u.veh
	var d := v.global_position.distance_to(u.target)
	var drv := v.driver()
	if drv == null or not u.crew.has(drv as NPC):
		_dismount(u)
		return
	if u.ai == null or not is_instance_valid(u.ai):
		u.ai = AIDriver.attach(v as Car, Game.traffic, -1, 0.0)
		if not u.ai.drive_to(u.target, true):
			u.ai.cruise()
	if d < 18.0 or u.ai.arrived or (u.ai.mode == AIDriver.Mode.HOLD and d < 45.0) or u.ai.dead_end:
		_dismount(u)
	elif u.age > 100.0:
		_dismount(u)        # stuck somewhere: walk the rest

func _dismount(u: Unit) -> void:
	var v := u.veh
	if u.ai != null and is_instance_valid(u.ai):
		u.ai.release()
	u.ai = null
	v.in_handbrake = true
	for i in v.seat_count():
		var c: Character = v.seats[i]["occupant"]
		if c is NPC and u.crew.has(c as NPC):
			v.open_door(i, true)
			v.unseat(i)
	for k in u.crew.size():
		var n := u.crew[k]
		var off := Vector3(cos(float(k) * 2.4), 0.0, sin(float(k) * 2.4)) * (1.6 if u.kind == "ambulance" else 6.0)
		n.go_to(u.target + off, 4.4)
	u.state = U.WORK
	u.timer = 0.0

func _work(u: Unit, dt: float) -> void:
	u.timer += dt
	var all_done := true
	for n in u.crew:
		if n.state == NPC.S.GOTO:
			all_done = false
			if u.timer > 25.0:
				n.calm()
			continue
		if n.state == NPC.S.POSE:
			all_done = false
			continue
		if not n.has_meta("worked"):
			n.set_meta("worked", true)
			all_done = false
			if u.kind == "ambulance":
				n.hold_pose(&"crouch_idle", 6.0, u.target)
			else:
				n.hold_pose(&"idle", 6.0, u.target, &"aim_rifle")
				_spray(n, u.target)
	if u.kind == "fire" and u.timer > 3.0:
		for veh in get_tree().get_nodes_in_group(&"vehicles"):
			if (veh as Vehicle).global_position.distance_to(u.target) < 12.0:
				(veh as Vehicle).extinguish()
	if all_done and u.timer > 2.0:
		if u.kind == "ambulance":
			_clear_casualties(u)
		for n in u.crew:
			n.remove_meta("worked")
		u.state = U.RETURN

func _spray(n: NPC, at: Vector3) -> void:
	if Game.fx == null:
		return
	var from := n.global_position + Vector3(0, 1.2, 0)
	var jet := Game.fx.water_jet(from, 5.5)
	var dirv := (at + Vector3(0, 0.6, 0) - from).normalized()
	jet.global_transform.basis = Basis(Quaternion(Vector3.UP, dirv))

func _clear_casualties(u: Unit) -> void:
	var taken := 0
	for n in get_tree().get_nodes_in_group(&"npcs"):
		var npc := n as NPC
		if not npc.alive and npc.global_position.distance_to(u.target) < 12.0:
			npc.queue_free()
			taken += 1
	var p: Player = Game.player
	if u.for_player and p.alive and p.global_position.distance_to(u.target) < 12.0 and p.health < p.max_health:
		p.heal(p.max_health)
		Audio.play_ui(&"ui_heal", -4.0)
		Game.notify("The paramedics patched you up", "good")

func _return(u: Unit) -> void:
	var v := u.veh
	var seated := 0
	for k in u.crew.size():
		var n := u.crew[k]
		if n.vehicle == v:
			seated += 1
		elif n.enter_vehicle != v and k < v.seat_count() and v.seats[k]["occupant"] == null:
			n.order_enter(v, k)
	if seated >= u.crew.size():
		v.set_siren(false)
		u.ai = AIDriver.attach(v as Car, Game.traffic, -1, 0.0)
		u.ai.cruise()
		u.state = U.LEAVE

func _despawn(u: Unit) -> void:
	for n in u.crew:
		if is_instance_valid(n):
			if n.vehicle != null and is_instance_valid(n.vehicle):
				(n.vehicle as Vehicle).eject(n)
			n.queue_free()
	if u.veh != null and is_instance_valid(u.veh) and not u.veh.has_player():
		if u.veh.ai != null and is_instance_valid(u.veh.ai):
			u.veh.ai.release()
		u.veh.queue_free()

func active() -> int:
	return units.size()
