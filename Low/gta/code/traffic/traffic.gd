class_name Traffic
extends Node
# Civilian traffic spawn/despawn around the player, parked vehicles, taxi service,
# ambulance / fire engine responders.

var enabled := true
var density := 13
var cars: Array = []          # civilian AI traffic
var spawn_t := 0.0
var taxi = null
var taxi_state := ""
var taxi_dest := Vector3.ZERO
var responders: Array = []    # {v, kind, pos, t, state}
var incident_cd := 0.0
var best_time := 0.0


func spawn_vehicle(id: String, pos: Vector3, yaw := 0.0, color = null) -> Vehicle:
	var v := Vehicle.make(id, color)
	G.main.add_child(v)
	var y := pos.y
	if v.kind == "boat":
		y = G.WATER_Y + 0.1
	v.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, y + 0.3, pos.z))
	return v


func add_driver(v: Vehicle, role := "civ") -> NPC:
	var n := NPC.make(role)
	G.main.add_child(n)
	G.pop.register(n, true)
	n.state = "vehicle"
	n.vehicle = v
	n.visible = v.def.get("open", false)
	n.collision_layer = 0
	n.cshape.disabled = true
	v.set_driver(n)
	v.handbrake = false
	return n


func setup_parked() -> void:
	var ids := ["compact", "sedan", "suv", "pickup", "van", "muscle", "sports", "compact", "sedan", "motorcycle"]
	var k := 0
	for s in G.world.parking_spots:
		spawn_vehicle(ids[k % ids.size()], s[0], s[1])
		k += 1
	spawn_vehicle("sedan", Vector3(-124, 0.2, -8), PI, Color(0.15, 0.3, 0.6))
	spawn_vehicle("motorcycle", Vector3(-124, 0.2, -13), PI)
	spawn_vehicle("bicycle", Vector3(-84, 0.3, 30), 0.0)
	spawn_vehicle("bicycle", Vector3(-110, 0.2, 164), 1.2)
	spawn_vehicle("heli", G.locations["Helipad"], PI / 2)
	spawn_vehicle("plane", G.locations["Runway"], 0.0, Color(0.9, 0.9, 0.95))
	spawn_vehicle("plane", Vector3(196, 0.2, -165), -PI / 2, Color(0.95, 0.8, 0.2))
	spawn_vehicle("jet", Vector3(200, 0.2, -120), -PI / 2, Color(0.6, 0.63, 0.68))
	spawn_vehicle("speedboat", G.locations["Boat Dock"], PI, Color(0.9, 0.2, 0.15))
	spawn_vehicle("speedboat", G.locations["Dock Boat 2"], PI, Color(0.15, 0.4, 0.8))
	spawn_vehicle("police", Vector3(100, 0.25, -110), PI / 2)
	spawn_vehicle("police", Vector3(100, 0.25, -105), PI / 2)
	spawn_vehicle("ambulance", Vector3(100, 0.25, -30), PI / 2)
	spawn_vehicle("sports", Vector3(-6, 0.25, -127), PI / 2, Color(0.9, 0.5, 0.05))
	spawn_vehicle("truck", Vector3(-110, 0.25, -180), 0.0)
	spawn_vehicle("firetruck", Vector3(100, 0.25, -22), PI / 2)
	spawn_vehicle("heli_police", G.locations["Helipad 2"], PI / 2)


func _physics_process(dt: float) -> void:
	var p = G.player
	if p == null:
		return
	var pp: Vector3 = p.global_position
	# despawn
	for i in range(cars.size() - 1, -1, -1):
		var v = cars[i]
		if not is_instance_valid(v):
			cars.remove_at(i)
			continue
		var d: float = v.global_position.distance_to(pp)
		var gone: bool = v.ai == null or v.wrecked
		if gone:
			cars.remove_at(i)
			continue
		if d > 230.0 or not enabled or (d > 90.0 and v.ai.want_despawn and not _in_view(v.global_position)) or v.global_position.y < G.WATER_Y - 1.0:
			_remove(v)
			cars.remove_at(i)
	# spawn
	spawn_t -= dt
	var want: int = density
	if G.sky and G.sky.is_night():
		want = int(density * 0.6)
	if enabled and spawn_t <= 0.0 and cars.size() < want:
		spawn_t = 0.35
		_spawn_traffic(pp)
	_taxi(dt)
	_responders(dt)
	incident_cd = max(0.0, incident_cd - dt)


func _in_view(pos: Vector3) -> bool:
	var c = G.cam.cam
	var to: Vector3 = pos - c.global_position
	return to.normalized().dot(-c.global_basis.z) > 0.55 and to.length() < 160.0


func _remove(v) -> void:
	if v.driver != null and is_instance_valid(v.driver) and not v.driver.is_player:
		G.pop.remove(v.driver)
	if v.driver != null and is_instance_valid(v.driver) and v.driver.is_player:
		v.ai = null
		return
	v.queue_free()


func _spawn_point(pp: Vector3, dmin: float, dmax: float) -> Array:
	var g = G.roads
	for attempt in 30:
		var a: int = randi() % 25
		var links: Array = g.links[a]
		var b: int = links[randi() % links.size()]
		var len: float = g.nodes[a].distance_to(g.nodes[b])
		var t := randf_range(14.0, len - 16.0)
		var pos: Vector3 = g.lane_point(a, b, t)
		var d := pos.distance_to(pp)
		if d < dmin or d > dmax:
			continue
		if d < 130.0 and _in_view(pos):
			continue
		var ok := true
		for o in G.vehicles:
			if o.global_position.distance_to(pos) < 15.0:
				ok = false
				break
		if ok:
			return [a, b, t]
	return []


func _spawn_traffic(pp: Vector3) -> void:
	var s := _spawn_point(pp, 70.0, 190.0)
	if s.is_empty():
		return
	var id: String = Defs.TRAFFIC_POOL[randi() % Defs.TRAFFIC_POOL.size()]
	var role := "civ"
	if randf() < 0.07:
		id = "police"
		role = "cop"
	var v := Vehicle.make(id)
	G.main.add_child(v)
	v.ai = AIDriver.new()
	v.ai.place_on(v, s[0], s[1], s[2])
	if id == "police":
		v.owner_tag = "police"
	elif id == "taxi":
		v.owner_tag = "civ"
	v.linear_velocity = -v.global_basis.z * 6.0
	add_driver(v, role)
	cars.append(v)


# ---------------------------------------------------------------- taxi
func call_taxi() -> void:
	if taxi != null and is_instance_valid(taxi) and not taxi.wrecked:
		G.notify("Your taxi is already on its way")
		return
	var pp: Vector3 = G.player.global_position
	var s := _spawn_point(pp, 55.0, 120.0)
	if s.is_empty():
		G.notify("No taxi available right now, try again")
		return
	taxi = Vehicle.make("taxi")
	G.main.add_child(taxi)
	taxi.owner_tag = "taxi"
	taxi.ai = AIDriver.new()
	taxi.ai.place_on(taxi, s[0], s[1], s[2])
	add_driver(taxi)
	var e: Array = G.roads.nearest_edge(pp)
	var stop: Vector3 = G.roads.lane_point(e[0], e[1], e[2])
	taxi.ai.mode = "goto"
	taxi.ai.set_route_to(taxi, stop)
	taxi.ai.on_arrive = func():
		taxi_state = "waiting"
		G.notify("Your taxi has arrived: press F next to it to ride")
		taxi.horn()
	taxi_state = "coming"
	G.notify("Taxi dispatched")


func taxi_ready(v) -> bool:
	return v == taxi and taxi_state == "waiting"


func taxi_go(dest: Vector3) -> void:
	if taxi == null:
		return
	taxi_dest = dest
	var fare := int(taxi.global_position.distance_to(dest) * 0.6) + 20
	if not G.spend(fare):
		G.player.exit_vehicle()
		return
	G.notify("Fare $%d. Press ENTER to skip the trip" % fare, 5.0)
	var e: Array = G.roads.nearest_edge(dest)
	var stop: Vector3 = G.roads.lane_point(e[0], e[1], e[2])
	taxi.ai.mode = "goto"
	taxi.ai.set_route_to(taxi, stop)
	taxi.ai.on_arrive = func():
		taxi_state = "arrived"
		G.notify("Destination reached")
		if G.player.passenger_of == taxi:
			G.player.exit_vehicle()
	taxi_state = "riding"
	taxi_dest = stop


func taxi_skip() -> void:
	if taxi_state != "riding" or taxi == null:
		return
	G.hud.fade()
	var e: Array = G.roads.nearest_edge(taxi_dest)
	taxi.ai.place_on(taxi, e[0], e[1], max(e[2] - 8.0, 10.0))
	taxi.ai.lane = 0
	taxi.linear_velocity = Vector3.ZERO
	taxi.ai.mode = "direct"
	taxi.ai.target_pos = taxi_dest
	taxi.ai.arrived = false


func taxi_done(v) -> void:
	if v == taxi:
		taxi_state = "leaving"
		taxi.owner_tag = "civ"
		taxi.ai.mode = "traffic"
		taxi.ai.nxt = -1
		taxi.ai.route = []
		var e: Array = G.roads.nearest_edge(taxi.global_position)
		taxi.ai.a = e[0]
		taxi.ai.b = e[1]
		cars.append(taxi)
		taxi = null


func _taxi(_dt: float) -> void:
	if taxi == null:
		return
	if not is_instance_valid(taxi) or taxi.wrecked or taxi.ai == null:
		if G.player.passenger_of != null:
			G.player.force_exit()
		taxi = null
		taxi_state = ""
		return
	if taxi_state == "riding" and Input.is_physical_key_pressed(KEY_ENTER):
		taxi_skip()


# ---------------------------------------------------------------- emergency services
func report_death(pos: Vector3) -> void:
	_incident("ambulance", pos)


func report_fire(pos: Vector3) -> void:
	_incident("firetruck", pos)


func _incident(kind: String, pos: Vector3) -> void:
	if not enabled or incident_cd > 0.0 or responders.size() >= 2:
		return
	if G.wanted and G.wanted.stars >= 2:
		return
	for r in responders:
		if r.kind == kind:
			return
	if abs(pos.x + 40.0) > 175.0 or abs(pos.z + 40.0) > 175.0:
		return
	incident_cd = 20.0
	get_tree().create_timer(6.0).timeout.connect(func(): _dispatch(kind, pos))


func _dispatch(kind: String, pos: Vector3) -> void:
	var s := _spawn_point(G.player.global_position, 90.0, 220.0)
	if s.is_empty():
		return
	var v := Vehicle.make(kind)
	G.main.add_child(v)
	v.owner_tag = "ems"
	v.ai = AIDriver.new()
	v.ai.place_on(v, s[0], s[1], s[2])
	v.ai.emergency = true
	v.siren_on = true
	add_driver(v, "medic")
	var e: Array = G.roads.nearest_edge(pos)
	v.ai.mode = "goto"
	v.ai.set_route_to(v, G.roads.lane_point(e[0], e[1], e[2]))
	var r := {"v": v, "kind": kind, "pos": pos, "t": 0.0, "state": "driving"}
	v.ai.on_arrive = func(): r.state = "working"
	responders.append(r)


func _responders(dt: float) -> void:
	for i in range(responders.size() - 1, -1, -1):
		var r: Dictionary = responders[i]
		var v = r.v
		if not is_instance_valid(v) or v.wrecked or v.ai == null:
			responders.remove_at(i)
			continue
		r.t += dt
		if r.state == "driving" and r.t > 70.0:
			r.state = "leaving"
		if r.state == "working":
			r["w"] = r.get("w", 0.0) + dt
			if r.kind == "firetruck":
				if fmod(r.w, 0.3) < dt:
					G.fx.splash(r.pos + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
					G.fx.burst("splash", r.pos + Vector3(randf_range(-2, 2), 0.5, randf_range(-2, 2)))
				for o in G.vehicles:
					if o.global_position.distance_to(r.pos) < 25.0 and o.wrecked:
						o.burning = false
			elif r.w > 1.0 and not r.has("medic"):
				var m := NPC.make("medic")
				G.main.add_child(m)
				G.pop.register(m, false)
				m.global_position = v.global_transform * Vector3(v.def.W / 2 + 1.0, 0.3, 2.0)
				m.ai = "goto"
				m.dest = r.pos
				m.on_reach = func():
					for h in G.humanoids.duplicate():
						if h.dead and not h.is_player and h.global_position.distance_to(r.pos) < 8.0:
							G.pop.remove(h)
					r["cleared"] = true
				r["medic"] = m
			if r.w > (9.0 if r.kind == "firetruck" else 16.0) or r.get("cleared", false) and r.w > 6.0:
				r.state = "leaving"
		if r.state == "leaving":
			if r.has("medic") and is_instance_valid(r.medic):
				G.pop.remove(r.medic)
			v.siren_on = false
			v.ai.emergency = false
			v.ai.mode = "traffic"
			v.ai.nxt = -1
			var e: Array = G.roads.nearest_edge(v.global_position)
			v.ai.a = e[0]
			v.ai.b = e[1]
			v.owner_tag = "civ"
			cars.append(v)
			responders.remove_at(i)
