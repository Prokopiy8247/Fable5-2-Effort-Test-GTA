extends Node
## Ambient city services: taxi passenger rides (hail / phone, choose destination, ride or skip) and
## emergency response (ambulances for casualties, fire engines for explosions and fires).

var menu: MenuPanel
var taxi: Vehicle = null
var taxi_state := ""
var taxi_dest := Vector3.ZERO
var taxi_from := Vector3.ZERO
var taxi_fare := 0
var responders: Array = []
var cool := {"ambulance": 0.0, "firetruck": 0.0}


func _ready() -> void:
	menu = MenuPanel.new()
	add_child(menu)
	G.explosion.connect(func(pos: Vector3, _r: float): _on_explosion(pos))


func _road_spot(near: Vector3, dmin: float, dmax: float) -> Array:
	if G.wanted:
		return G.wanted._hidden_road_point(near, dmin, dmax)
	return []


# ------------------------------------------------------------------ taxi
func call_taxi() -> void:
	if taxi != null and is_instance_valid(taxi) and taxi_state != "":
		G.say("A taxi is already on its way", UIKit.DIM)
		return
	var pp: Vector3 = G.player.global_position_now()
	var spot := _road_spot(pp, 55.0, 130.0)
	if spot.is_empty() or G.traffic == null:
		G.say("No taxis available right now", UIKit.DIM)
		return
	taxi = G.traffic.spawn_traffic_vehicle("taxi", spot[0], spot[1], 0, spot[2])
	if taxi == null:
		return
	G.traffic.moving.erase(taxi)
	taxi.no_despawn = true
	taxi.ai.mode = "route"
	taxi.ai.cruise = 14.0
	taxi.ai.set_route_to(pp)
	taxi.ai.on_arrive = func(_ai): _taxi_waiting()
	taxi_state = "coming"
	G.say("Taxi dispatched  -  it will stop on the nearest road", UIKit.GOLD)


func _taxi_waiting() -> void:
	if taxi_state == "coming":
		taxi_state = "waiting"
		taxi.honk()
		G.say("Your taxi has arrived  -  press F next to it (hold Shift + F to steal it instead)", UIKit.GOLD)


func board_taxi(veh: Vehicle) -> void:
	## Called by the player when pressing F next to a taxi that is for hire.
	var p: Player = G.player
	if G.wanted and G.wanted.level > 0:
		G.say("The driver refuses to take a wanted passenger", Color(1, 0.6, 0.4))
		return
	taxi = veh
	taxi.no_despawn = true
	if G.traffic:
		G.traffic.moving.erase(taxi)
	veh.ai.mode = "park"
	taxi_state = "boarding"
	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(veh) or veh.dead or veh.driver == null:
		taxi_state = ""
		return
	var s := 2 if veh.seats.size() > 2 and veh.seats[2].occ == null else 3
	p.warp_into(veh, s)
	_destinations()


func _destinations() -> void:
	var p: Player = G.player
	menu.open("Where to?", func(m: MenuPanel):
		var items: Array = []
		var from := p.global_position_now()
		if G.hud and G.hud.waypoint != null:
			var wp: Vector3 = G.hud.waypoint
			items.append({"text": "Map waypoint", "right": "$%d" % _fare(from, wp), "fn": _go.bind(wp), "no_refresh": true})
		for id in G.world.pois.keys():
			var poi: Dictionary = G.world.pois[id]
			var pos: Vector3 = poi.pos
			if pos.y > 5.0 or id in ["lighthouse", "wreck", "viewpoint", "tower"] and false:
				continue
			items.append({"text": poi.label, "right": "$%d" % _fare(from, pos), "fn": _go.bind(pos), "no_refresh": true})
		items.append({"text": "Never mind (get out)", "fn": func():
			m.close()
			taxi_state = "waiting"
			p.try_exit_vehicle(), "no_refresh": true})
		m.set_items(items), {"sub": "Pick a destination. During the ride press ENTER to skip the trip."})


func _fare(a: Vector3, b: Vector3) -> int:
	return 5 + int(G.dist2(a, b) * 0.35)


func _go(dest: Vector3) -> void:
	menu.close()
	if taxi == null or not is_instance_valid(taxi) or taxi.ai == null:
		return
	taxi_dest = dest
	taxi_from = taxi.global_position
	taxi_fare = _fare(taxi_from, dest)
	taxi.ai.mode = "route"
	taxi.ai.cruise = 15.5
	taxi.ai.arrived = false
	taxi.ai.snap_to_road()
	taxi.ai.set_route_to(dest)
	taxi.ai.on_arrive = func(_ai): _taxi_arrived()
	taxi_state = "riding"
	taxi.brake = 0.0
	taxi.handbrake = false


func _taxi_arrived() -> void:
	if taxi_state != "riding":
		return
	taxi_state = "done"
	var p: Player = G.player
	p.add_money(-mini(taxi_fare, p.money))
	G.say("Arrived  -  fare %s" % G.fmt_money(taxi_fare), UIKit.GOLD)
	await get_tree().create_timer(0.8).timeout
	if p.vehicle == taxi:
		p.try_exit_vehicle()
	await get_tree().create_timer(2.5).timeout
	_release_taxi()


func _release_taxi() -> void:
	if taxi != null and is_instance_valid(taxi) and taxi.ai != null:
		taxi.no_despawn = false
		taxi.ai.mode = "traffic"
		taxi.ai.route.clear()
		taxi.ai.on_arrive = Callable()
		taxi.ai.snap_to_road()
		if G.traffic and not G.traffic.moving.has(taxi):
			G.traffic.moving.append(taxi)
	taxi = null
	taxi_state = ""


func _skip_trip() -> void:
	if taxi_state != "riding" or taxi == null:
		return
	taxi_state = "skipping"
	await G.hud.fade(true, 0.5)
	if is_instance_valid(taxi) and taxi.ai != null:
		var ix := WorldLayout.nearest_inter(taxi_dest)
		var nb := WorldLayout.neighbors(ix)
		var best: Vector2i = nb[0]
		for n in nb:
			if WorldLayout.inter_pos(n).distance_to(taxi_dest) < WorldLayout.inter_pos(best).distance_to(taxi_dest):
				best = n
		var xf: Transform3D = taxi.ai.place_on_lane(ix, best, 0, clampf(G.dist2(WorldLayout.inter_pos(ix), taxi_dest) / maxf(WorldLayout.inter_pos(ix).distance_to(WorldLayout.inter_pos(best)), 1.0), 0.1, 0.8))
		taxi.linear_velocity = Vector3.ZERO
		taxi.angular_velocity = Vector3.ZERO
		taxi.global_transform = xf
		taxi.ai.mode = "park"
		if G.timew:
			G.timew.set_time(G.timew.time + 0.25)
	G.hud.fade(false, 0.5)
	taxi_state = "riding"
	_taxi_arrived()


func _process(delta: float) -> void:
	for k in cool.keys():
		cool[k] = maxf(float(cool[k]) - delta, 0.0)
	var p: Player = G.player
	if p == null:
		return
	if taxi_state != "" and (taxi == null or not is_instance_valid(taxi) or taxi.dead or taxi.driver == null or (taxi.ai == null)):
		taxi = null
		taxi_state = ""
	if taxi_state == "riding":
		if p.vehicle != taxi:
			var part := mini(_fare(taxi_from, taxi.global_position), p.money)
			p.add_money(-part)
			G.say("You left the taxi early  -  paid %s" % G.fmt_money(part), UIKit.DIM)
			_release_taxi()
		else:
			if G.hud:
				G.hud.alt_text = "TAXI  %d m to go   -   ENTER: skip trip    F: get out" % int(G.dist2(taxi.global_position, taxi_dest))
			if Input.is_action_just_pressed("skip") and G.ui_blocking == 0:
				_skip_trip()
	elif G.hud and G.hud.alt_text.begins_with("TAXI"):
		G.hud.alt_text = ""
	if taxi_state == "waiting" and taxi != null and taxi.global_position.distance_to(p.global_position_now()) > 140.0:
		_release_taxi()
	_update_responders(delta)


# ------------------------------------------------------------------ emergency response
func on_casualty(pos: Vector3) -> void:
	if float(cool.ambulance) <= 0.0 and randf() < 0.65 and (G.wanted == null or G.wanted.level < 3):
		dispatch("ambulance", pos)


func _on_explosion(pos: Vector3) -> void:
	if float(cool.firetruck) <= 0.0 and (G.wanted == null or G.wanted.level < 4) and pos.y < 12.0 and absf(pos.x) < 280.0 and pos.z > -180.0 and pos.z < 180.0:
		dispatch("firetruck", pos)


func dispatch(kind: String, pos: Vector3) -> void:
	if G.traffic == null:
		return
	for r in responders:
		if is_instance_valid(r.veh) and r.veh.vid == kind:
			return
	var spot := _road_spot(pos, 70.0, 170.0)
	if spot.is_empty():
		return
	var crew_kind := "medic" if kind == "ambulance" else "fire"
	var v: Vehicle = G.traffic.spawn_traffic_vehicle(kind, spot[0], spot[1], 0, spot[2], crew_kind)
	if v == null:
		return
	cool[kind] = 55.0
	G.traffic.moving.erase(v)
	v.no_despawn = true
	if G.peds:
		G.peds.make_driver(crew_kind).enter_vehicle(v, 1)
	v.set_siren(true)
	v.ai.mode = "route"
	v.ai.ignore_signals = true
	v.ai.cruise = 17.0
	v.ai.set_route_to(pos)
	var entry := {"veh": v, "pos": pos, "state": "enroute", "t": 0.0, "crew": []}
	v.ai.on_arrive = func(_ai): entry.state = "arrived"
	responders.append(entry)


func _update_responders(delta: float) -> void:
	var i := responders.size() - 1
	while i >= 0:
		var r: Dictionary = responders[i]
		var rv = r.veh
		if not is_instance_valid(rv) or rv.dead:
			responders.remove_at(i)
			i -= 1
			continue
		var v: Vehicle = rv
		r.t = float(r.t) + delta
		match String(r.state):
			"enroute":
				if float(r.t) > 70.0:
					r.state = "leave"
			"arrived":
				v.set_siren(false)
				v.siren = false
				r.state = "work"
				r.t = 0.0
				for s in v.seats.size():
					var o: Node = v.seats[s].occ
					if o != null and o is NPC:
						var n := o as NPC
						var dp := v.door_point(s)
						n.leave_vehicle()
						n.global_position = dp + Vector3(0, 0.1, 0)
						n.st = NPC.S.GOTO
						n.goal = (r.pos as Vector3) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
						n.state_t = 0.0
						n.set_meta("seat", s)
						(r.crew as Array).append(n)
			"work":
				if v.vid == "firetruck" and G.fx and int(float(r.t) * 6.0) != int((float(r.t) - delta) * 6.0):
					for c in r.crew:
						if is_instance_valid(c) and c.global_position.distance_to(r.pos) < 9.0:
							var from: Vector3 = c.global_position + Vector3(0, 1.3, 0)
							var d: Vector3 = ((r.pos as Vector3) + Vector3(0, 0.5, 0) - from).normalized()
							G.fx.jet(from + d * 0.6, d)
					for e in get_tree().get_nodes_in_group("vehicles"):
						var ev := e as Vehicle
						if ev.fire != null and ev.global_position.distance_to(r.pos) < 12.0 and float(r.t) > 6.0:
							ev.fire.queue_free()
							ev.fire = null
							ev.burning = -1.0
				for c2 in r.crew:
					if is_instance_valid(c2) and c2.st == NPC.S.WANDER:
						c2.st = NPC.S.IDLE
						c2.state_t = -8.0
						c2.vis.crouch = 1.0 if v.vid == "ambulance" else 0.0
				if float(r.t) > 16.0:
					r.state = "pack"
					r.t = 0.0
					for c3 in r.crew:
						if is_instance_valid(c3) and not c3.dead:
							c3.vis.crouch = 0.0
							c3.st = NPC.S.GOTO
							c3.goal = v.global_position
							c3.state_t = 0.0
			"pack":
				var all_in := true
				for c4 in r.crew:
					if is_instance_valid(c4) and not c4.dead and c4.vehicle == null:
						if c4.global_position.distance_to(v.global_position) < 4.5 or float(r.t) > 12.0:
							var s2: int = c4.get_meta("seat")
							if v.seats[s2].occ == null:
								c4.enter_vehicle(v, s2)
						else:
							all_in = false
				if all_in or float(r.t) > 14.0:
					r.state = "leave"
			"leave":
				v.no_despawn = false
				if v.ai != null and v.driver != null:
					v.ai.mode = "traffic"
					v.ai.ignore_signals = false
					v.ai.cruise = 11.0
					v.ai.on_arrive = Callable()
					v.ai.snap_to_road()
					if G.traffic and not G.traffic.moving.has(v):
						G.traffic.moving.append(v)
				else:
					v.add_to_group("loose")
				responders.remove_at(i)
		i -= 1
