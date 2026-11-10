class_name Services
extends Node
## Ambient city services: taxi rides for the player, ambulance and fire-engine responses, mechanic delivery.

var taxi: Vehicle = null
var taxi_state := ""         # "" | coming | waiting | riding
var taxi_dest := Vector3.ZERO
var _taxi_t := 0.0
var _incidents: Array = []   # {pos, kind, t}
var _responders: Array = []  # {veh, kind, pos, state, t, medic}
var _cool := 0.0


func _ready() -> void:
	if Game.world:
		Game.world.emergency = self


# ------------------------------------------------------------------ taxi
func call_taxi() -> void:
	var p = Game.player
	if taxi != null and is_instance_valid(taxi) and taxi_state != "":
		Game.say("Your cab is already on its way")
		return
	if Game.traffic == null or p.in_vehicle():
		Game.say("Taxi service unavailable right now")
		return
	var sp: Dictionary = Wanted._spawn_lane_point(p, 55.0, 120.0)
	if sp.is_empty():
		Game.say("No cab available, try again")
		return
	if Wanted.level > 0:
		Game.say("Dispatcher: we don't pick up fugitives!", Color(1, 0.6, 0.5))
		return
	var fwd: Vector3 = sp.dir
	taxi = Game.traffic.spawn_vehicle("taxi", sp.pos + Vector3.UP * 0.4, atan2(-fwd.x, -fwd.z))
	taxi.set_ai_driver(Data.random_civilian(Game.rng))
	var ai := DriverAI.new()
	ai.mode = "goto"
	ai.cruise = 13.0
	ai.arrive_dist = 11.0
	ai.target_pos = City.nearest_lane(p.global_position).pos
	ai.on_arrive = _taxi_arrived
	taxi.ai = ai
	taxi.set_meta("service", true)
	taxi_state = "coming"
	_taxi_t = 0.0
	Sfx.play("phone_beep", -4.0)
	Game.say("Cabbie dispatched - wait near the road", Color(1.0, 0.85, 0.4))


func _taxi_arrived() -> void:
	if taxi_state == "coming":
		taxi_state = "waiting"
		_taxi_t = 0.0
		if is_instance_valid(taxi):
			taxi.horn()
			Game.world.add_interact(taxi, Vector3(0, 0.5, 0), 4.5, "E  Ride the taxi (pick a destination)", _board, func(): return taxi_state == "waiting")
	elif taxi_state == "riding":
		_finish_ride()


func _board() -> void:
	if taxi_state != "waiting" or not is_instance_valid(taxi):
		return
	Game.hud.open_big_map(true, _set_destination)
	Game.say("Click the map to choose a destination", Color(1.0, 0.85, 0.4))


func _set_destination(pos: Vector3) -> void:
	if not is_instance_valid(taxi):
		return
	var p = Game.player
	taxi_dest = City.nearest_lane(pos).pos
	var fare := int(20 + p.global_position.distance_to(taxi_dest) * 0.25)
	if not Game.spend(fare):
		return
	var seat_i := mini(3, taxi.seats.size() - 1)
	taxi.seat_users[seat_i] = p
	p.rig.sit = 1.0
	p.start_ride(taxi, taxi.seats[seat_i] - Vector3(0, 0.95, 0), _leave_taxi)
	var ai: DriverAI = taxi.ai
	ai.mode = "goto"
	ai.target_pos = taxi_dest
	ai.pts = PackedVector3Array()
	ai.on_arrive = _taxi_arrived
	taxi_state = "riding"
	Game.say("Fare $%d  -  ENTER to skip the trip, F to get out" % fare, Color(1.0, 0.85, 0.4))


func _leave_taxi() -> void:
	_finish_ride()


func _finish_ride() -> void:
	var p = Game.player
	if is_instance_valid(taxi):
		for i in range(taxi.seat_users.size()):
			if taxi.seat_users[i] == p:
				taxi.seat_users[i] = null
		p.end_ride(taxi.door_pos(mini(3, taxi.seats.size() - 1)))
		var l := City.nearest_lane(taxi.global_position, -taxi.global_basis.z)
		var ai: DriverAI = taxi.ai
		if ai and not l.is_empty():
			ai.mode = "traffic"
			ai.start_lane(l.seg, l.dir, l.lane, taxi.global_position)
			Game.traffic.ambient.append(taxi)
	taxi_state = ""
	taxi = null


func _physics_process(delta: float) -> void:
	if taxi_state != "" and (taxi == null or not is_instance_valid(taxi) or taxi.dead or taxi.ai == null):
		if Game.player and Game.player.state == Player.St.RIDE:
			Game.player.end_ride(Game.player.global_position + Vector3.UP)
		taxi_state = ""
		taxi = null
	if taxi_state == "waiting":
		_taxi_t += delta
		if _taxi_t > 45.0:
			Game.say("The cab got tired of waiting")
			var l := City.nearest_lane(taxi.global_position, -taxi.global_basis.z)
			taxi.ai.mode = "traffic"
			taxi.ai.start_lane(l.seg, l.dir, l.lane, taxi.global_position)
			Game.traffic.ambient.append(taxi)
			taxi_state = ""
			taxi = null
	elif taxi_state == "riding" and Input.is_action_just_pressed("skip") and not Game.ui_blocked():
		Game.hud.fade_out_in(1.2, _skip_ride)
	elif taxi_state == "coming":
		_taxi_t += delta
		if _taxi_t > 24.0 and is_instance_valid(taxi) and taxi.global_position.distance_to(Game.player.global_position) > 30.0:
			_taxi_t = 0.0
			var l2 := City.nearest_lane(Game.player.global_position)
			taxi.place(l2.pos + Vector3.UP * 0.5, taxi.global_rotation.y)
	_emergency(delta)


func _skip_ride() -> void:
	if taxi_state != "riding" or not is_instance_valid(taxi):
		return
	var l := City.nearest_lane(taxi_dest)
	var fwd := City.seg_dir(l.seg, l.dir)
	taxi.place(l.pos + Vector3.UP * 0.5, atan2(-fwd.x, -fwd.z))
	if Game.daynight:
		Game.daynight.hour = fposmod(Game.daynight.hour + 0.25, 24.0)
	_finish_ride()


# ------------------------------------------------------------------ ambulance / fire
func report_body(pos: Vector3) -> void:
	_incidents.append({"pos": pos, "kind": "ems", "t": 0.0})


func report_fire(pos: Vector3) -> void:
	_incidents.append({"pos": pos, "kind": "fire", "t": 0.0})


func _emergency(delta: float) -> void:
	_cool -= delta
	var p = Game.player
	if p == null or Game.traffic == null:
		return
	if not _incidents.is_empty() and _cool <= 0.0 and _responders.size() < 2 and Wanted.level < 3:
		var inc: Dictionary = _incidents.pop_front()
		_incidents = _incidents.filter(func(o): return (o.pos as Vector3).distance_to(inc.pos) > 25.0)
		if (inc.pos as Vector3).distance_to(p.global_position) < 160.0:
			_cool = 14.0
			var sp: Dictionary = Wanted._spawn_lane_point(p, 80.0, 150.0)
			if not sp.is_empty():
				var fwd: Vector3 = sp.dir
				var id := "ambulance" if inc.kind == "ems" else "firetruck"
				var v: Vehicle = Game.traffic.spawn_vehicle(id, sp.pos + Vector3.UP * 0.5, atan2(-fwd.x, -fwd.z))
				v.set_ai_driver(Data.look_medic(Game.rng))
				var ai := DriverAI.new()
				ai.mode = "goto"
				ai.cruise = 16.0
				ai.obey_signals = false
				ai.arrive_dist = 14.0
				ai.target_pos = City.nearest_lane(inc.pos).pos
				v.ai = ai
				v.set_siren(true)
				v.set_lights(true)
				var rec := {"veh": v, "kind": inc.kind, "pos": inc.pos, "state": "driving", "t": 0.0, "medic": null}
				ai.on_arrive = func(): rec.state = "arrived"
				_responders.append(rec)
	var i := 0
	while i < _responders.size():
		var r: Dictionary = _responders[i]
		var v2 = r.veh
		if not is_instance_valid(v2) or v2.dead or v2.driver != null:
			if r.medic != null and is_instance_valid(r.medic):
				r.medic.queue_free()
			_responders.remove_at(i)
			continue
		r.t += delta
		# traffic yields to the siren
		if r.state == "driving" and int(r.t * 4.0) % 2 == 0:
			for o in Game.traffic.ambient:
				if is_instance_valid(o) and o.ai != null and o.ai is DriverAI and o.global_position.distance_to(v2.global_position) < 28.0:
					o.ai.yield_t = 2.5
		match r.state:
			"driving":
				if r.t > 70.0:
					r.state = "leave"
			"arrived":
				r.state = "working"
				r.t = 0.0
				if r.kind == "ems":
					var m := Npc.spawn("medic", v2.door_pos(0))
					m.persistent = true
					m.goto(r.pos)
					r.medic = m
			"working":
				if r.kind == "fire" and int(r.t * 3.0) % 2 == 0:
					Fx.splash(r.pos + Vector3(randf_range(-2, 2), 0.5, randf_range(-2, 2)), 1.5)
				if r.medic != null and is_instance_valid(r.medic) and r.medic.arrived():
					r.medic.rig.crouch = 1.0
				if r.t > 16.0:
					r.state = "leave"
					if r.medic != null and is_instance_valid(r.medic):
						r.medic.queue_free()
						r.medic = null
			"leave":
				v2.set_siren(false)
				var l := City.nearest_lane(v2.global_position, -v2.global_basis.z)
				if not l.is_empty() and v2.ai is DriverAI:
					v2.ai.mode = "traffic"
					v2.ai.obey_signals = true
					v2.ai.start_lane(l.seg, l.dir, l.lane, v2.global_position)
					Game.traffic.ambient.append(v2)
				_responders.remove_at(i)
				continue
		i += 1
