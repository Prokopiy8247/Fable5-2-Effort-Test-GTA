extends Node3D
## Free-roam extras: pickups & loot, emergency services, monorail, taxi rides, optional activities (no missions).

const Defs := preload("res://gta/code/core/defs.gd")
const Target := preload("res://gta/code/world/range_target.gd")

var pickups: Array = []
var service_vehicles: Array = []
var _amb = null
var _fire = null
var _svc_cd := 0.0
# monorail
var train: AnimatableBody3D
var train_x := -180.0
var train_dir := 1.0
var train_speed := 0.0
var train_wait := 5.0
var train_stop := -180.0
var riding_train := false
var _train_snd: AudioStreamPlayer3D
var _train_it := {}
const STOPS := [-180.0, 60.0, 180.0]
# taxi
var taxi = null
var taxi_state := ""
var taxi_dest := Vector3.ZERO
var taxi_from := Vector3.ZERO
var _taxi_t := 0.0
# activities
var activity := ""
var act := {}
var best := {}
var _air_start := Vector3.ZERO
var _air_time := 0.0
var _was_air := false
var _blips: Array = []
var chute_target := Vector3(-170, 0.2, 228)


func start() -> void:
	_place_pickups()
	_make_train()
	var W = G.world
	W.add_interact(W.locations["Shooting Range"] + Vector3(0, 0, 6), "Shooting range challenge ($20 entry)", func(): start_range(), 2.6, false, "activity")
	W._marker(W.locations["Shooting Range"] + Vector3(0, 0, 6), Color(1.0, 0.4, 0.7))
	var tt = Vector3(-6, 0.05, 30)
	W.add_interact(tt, "Ring-road time trial (bring a vehicle)", func(): start_trial(), 5.0, true, "activity")
	W._marker(tt, Color(1.0, 0.4, 0.7))
	var sr = Vector3(60, G.WATER_Y + 0.4, 268)
	W.add_interact(sr, "Bay sprint boat race", func(): start_searace(), 9.0, true, "activity")
	# parachute landing target on the beach
	var ring = MeshInstance3D.new()
	var tm = TorusMesh.new()
	tm.inner_radius = 9.0
	tm.outer_radius = 10.0
	ring.mesh = tm
	ring.material_override = G.flat_mat(Color(1.0, 0.4, 0.7), 0.5, 0.0, 1.0)
	ring.position = chute_target + Vector3(0, -1.6, 0)
	ring.scale.y = 0.15
	add_child(ring)
	W.map_icons.append({"pos": chute_target, "kind": "activity", "name": "Parachute target"})


# ------------------------------------------------------------------ pickups
func spawn_pickup(kind: String, pos: Vector3, amount = 0, life := -1.0, respawn := 0.0) -> void:
	var mdl = "pickup_" + kind
	var n: Node3D
	if kind.begins_with("w_"):
		n = G.model("weapons/" + Defs.WEAPONS[kind.substr(2)].model)
		n.scale = Vector3.ONE * 1.4
	else:
		if not G.man.has(mdl):
			mdl = "pickup_ammo"
		n = G.model("props/" + mdl)
	add_child(n)
	n.global_position = pos
	pickups.append({"kind": kind, "node": n, "amount": amount, "life": life, "respawn": respawn, "pos": pos, "cool": 0.0})


func _place_pickups() -> void:
	var W = G.world
	var L: Dictionary = W.locations
	var fixed = [
		["health", L["Hospital"] + Vector3(4, 0.4, 0)], ["health", Vector3(-180, 0.5, 150)], ["health", Vector3(170, 0.5, 205)], ["health", Vector3(-262, 0.5, 0)],
		["health", L["SafehouseInside"] + Vector3(-3.5, 0.4, -2.0)],
		["armor", L["Police Station"] + Vector3(6, 0.4, 1)], ["armor", Vector3(272, 0.5, -120)], ["armor", L["Spire Roof"] + Vector3(8, 0.3, -8)],
		["parachute", L["Spire Roof"] + Vector3(-8, 0.3, 8)], ["parachute", L["Signal Hill"] + Vector3(3, 0.4, 0)], ["parachute", Vector3(190, 19.6, 190)],
		["parachute", L["Hangar"] + Vector3(10, 0.4, 14)], ["parachute", L["Helipad"] + Vector3(9, 0.4, 0)],
		["scuba", Vector3(-80, 0.6, 290)], ["scuba", Vector3(-186, 0.6, 216)], ["scuba", Vector3(46, 0.6, 258)],
		["ammo", L["Shooting Range"] + Vector3(-9, 0.4, 5)], ["ammo", Vector3(200, 0.5, 60)], ["ammo", Vector3(-272, 0.5, -150)],
		["cash", Vector3(-200, -8.2, 332)], ["cash", Vector3(362, -8.0, 60)], ["cash", Vector3(255, 5.6, 137)], ["cash", L["Spire Roof"] + Vector3(0, 0.3, -10)],
		["w_bat", Vector3(-150, 0.5, 170)], ["w_knife", Vector3(60, 0.5, -60)], ["w_crowbar", Vector3(150, 0.5, -20)], ["w_shotgun", Vector3(285, 0.5, 170)],
		["w_smg", Vector3(-286, 0.5, 180)], ["w_sniper", Vector3(232, 20.6, -222)], ["w_grenade", Vector3(140, 0.5, 205)], ["w_revolver", Vector3(-200, -8.4, 326)],
	]
	for f in fixed:
		var amt = 0
		match f[0]:
			"cash": amt = 500
			"ammo": amt = 1
		spawn_pickup(f[0], f[1], amt, -1.0, 150.0)


func drop_loot(npc) -> void:
	var p: Vector3 = npc.global_position + Vector3(G.rng.randf_range(-0.6, 0.6), 0.35, G.rng.randf_range(-0.6, 0.6))
	if npc.cash > 0 and npc.role in ["ped", "gang", "clerk"]:
		spawn_pickup("cash", p, npc.cash, 70.0)
	if npc.weapons and npc.weapons.cur != "fists":
		spawn_pickup("w_" + npc.weapons.cur, p + Vector3(0.5, 0, 0.3), 0, 70.0)
	elif npc.role in ["cop", "swat"]:
		spawn_pickup("ammo", p, 1, 70.0)


func _update_pickups(dt: float) -> void:
	var p = G.player
	var pp: Vector3 = p.global_position + Vector3(0, 0.8, 0)
	var t = Time.get_ticks_msec() * 0.002
	for pk in pickups.duplicate():
		var n: Node3D = pk.node
		if pk.cool > 0.0:
			pk.cool -= dt
			if pk.cool <= 0.0:
				n.visible = true
			continue
		if pk.life > 0.0:
			pk.life -= dt
			if pk.life <= 0.0:
				n.queue_free()
				pickups.erase(pk)
				continue
		if n.global_position.distance_squared_to(pp) > 70.0 * 70.0:
			continue
		n.rotation.y = t
		n.position.y = pk.pos.y + sin(t * 1.5) * 0.08
		if p.state in ["ground", "swim", "cover"] and n.global_position.distance_to(pp) < 1.5:
			if _collect(pk, p):
				if pk.respawn > 0.0:
					pk.cool = pk.respawn
					n.visible = false
				else:
					n.queue_free()
					pickups.erase(pk)


func _collect(pk: Dictionary, p) -> bool:
	var k: String = pk.kind
	match k:
		"cash":
			G.add_money(pk.amount)
			G.notify("Picked up $%d" % pk.amount, 2.0)
		"health":
			if p.health >= p.max_health:
				return false
			p.health = p.max_health
			G.audio.play("heal", -6.0)
			G.notify("Health restored", 2.0)
		"armor":
			if p.armor >= 100.0:
				return false
			p.armor = 100.0
			G.audio.play("pickup", -6.0)
			G.notify("Body armour equipped", 2.0)
		"ammo":
			for id in p.weapons.owned():
				if Defs.WEAPONS[id].has("clip"):
					p.weapons.give(id, Defs.WEAPONS[id].clip * 2)
			G.audio.play("pickup", -6.0)
			G.notify("Ammo collected", 2.0)
		"parachute":
			if p.has_chute:
				return false
			p.give_chute()
			G.audio.play("pickup", -6.0)
			G.notify("Parachute equipped — jump from height and press SPACE", 4.0)
		"scuba":
			if p.scuba:
				return false
			p.set_scuba(true)
			G.audio.play("pickup", -6.0)
			G.notify("Scuba gear equipped — long dives enabled", 4.0)
		_:
			if k.begins_with("w_"):
				var id: String = k.substr(2)
				var had: bool = p.weapons.has(id)
				p.weapons.give(id, Defs.WEAPONS[id].get("clip", 0) * 2 if had else -1)
				if id == "grenade":
					p.weapons.give(id, 3)
				G.audio.play("pickup", -6.0)
				G.notify(("Ammo for %s" if had else "Picked up %s") % Defs.WEAPONS[id].name, 2.0)
	return true


# ------------------------------------------------------------------ emergency services
func on_casualty(pos: Vector3, _by_player: bool) -> void:
	if _amb != null or _svc_cd > 0.0 or G.traffic == null or not G.traffic.enabled:
		return
	if G.dist2d(pos, G.player_pos()) > 120.0 or G.world.is_sea(pos.x, pos.z):
		return
	_amb = _dispatch_service("ambulance", pos)


func on_explosion(pos: Vector3) -> void:
	if _fire != null or G.traffic == null or not G.traffic.enabled or G.world.is_sea(pos.x, pos.z):
		return
	if G.dist2d(pos, G.player_pos()) > 140.0:
		return
	_fire = _dispatch_service("firetruck", pos)


func _dispatch_service(id: String, pos: Vector3):
	var T = G.traffic
	for attempt in 14:
		var li = G.rng.randi() % T.lanes.size()
		var l: Dictionary = T.lanes[li]
		var t = l.len * 0.5
		var p: Vector3 = l.p0 + l.dir * t
		var d = G.dist2d(p, pos)
		if d < 100.0 or d > 230.0:
			continue
		var v = T.spawn_on_lane(id, li, t, "service")
		v.set_siren(true)
		v.ai.route = T.route(p, pos)
		var s = {"v": v, "pos": pos, "state": "drive", "t": 0.0, "crew": [], "id": id}
		service_vehicles.append(v)
		return s
	return null


func _update_service(s, dt: float):
	if s == null:
		return null
	var v = s.v
	if not is_instance_valid(v) or v.dead:
		for c in s.crew:
			if is_instance_valid(c) and not c.dead:
				c.set_state("wander")
		_svc_cd = 20.0
		return null
	s.t += dt
	match s.state:
		"drive":
			var d = G.dist2d(v.global_position, s.pos)
			if d < 26.0 or s.t > 70.0 or (v.ai.get("route", []).is_empty() and d < 60.0 and s.t > 6.0):
				v.ai.wait = 999.0
				s.state = "stop"
				s.t = 0.0
		"stop":
			if abs(v.speed) < 0.8 or s.t > 4.0:
				var n = 1 if s.id == "ambulance" else 2
				for i in n:
					var c = G.pop.spawn_ped(v.door_pos(-1.0 if i == 0 else 1.0) + Vector3(0, 0.2, 0), {}, "medic" if s.id == "ambulance" else "fire")
					c.brave = 0.0
					var goal: Vector3 = s.pos + Vector3(1.5 * (i * 2 - 1), 0, 1.0)
					if s.id == "firetruck":
						goal = s.pos + G.flat(v.global_position - s.pos).normalized() * 7.0 + Vector3(i * 2.0, 0, 0)
					c.goto(goal, null, true)
					s.crew.append(c)
				s.state = "work"
				s.t = 0.0
		"work":
			var arrived = s.t > 22.0
			for c in s.crew:
				if is_instance_valid(c) and c.state == "idle":
					arrived = true
			if arrived and not s.has("work_t"):
				s["work_t"] = 0.0
			if s.has("work_t"):
				s.work_t += dt
				for c in s.crew:
					if is_instance_valid(c) and not c.dead and c.state == "idle":
						c._crouch = s.id == "ambulance"
						var look: Vector3 = G.flat(s.pos - c.global_position)
						if look.length() > 0.3:
							c.rotation.y = atan2(-look.x, -look.z)
						if s.id == "firetruck" and int(s.work_t * 6.0) % 2 == 0:
							G.fx.burst("water", c.global_position + Vector3(0, 1.2, 0) + look.normalized() * 1.2, (look.normalized() + Vector3(0, 0.5, 0)).normalized())
				if s.work_t > 6.0:
					if s.id == "ambulance":
						for n2 in get_tree().get_nodes_in_group("npcs"):
							if n2.dead and n2.global_position.distance_to(s.pos) < 9.0:
								n2.queue_free()
					else:
						for w in get_tree().get_nodes_in_group("vehicles"):
							if w.dead and w.global_position.distance_to(s.pos) < 16.0:
								if w._fire:
									w._fire.queue_free()
									w._fire = null
								w.wreck_t = min(w.wreck_t, 20.0)
					for c in s.crew:
						if is_instance_valid(c) and not c.dead:
							c._crouch = false
							c.goto(v.door_pos(-1.0), func(): c.queue_free(), false)
					s.state = "return"
					s.t = 0.0
		"return":
			var gone = true
			for c in s.crew:
				if is_instance_valid(c) and not c.dead and c.state == "goto":
					gone = false
			if gone or s.t > 20.0:
				for c in s.crew:
					if is_instance_valid(c) and not c.dead:
						c.queue_free()
				v.set_siren(false)
				v.ai.wait = 0.0
				v.ai.route = []
				v.owner_tag = "traffic"
				service_vehicles.erase(v)
				_svc_cd = 25.0
				return null
	return s


# ------------------------------------------------------------------ monorail
func _make_train() -> void:
	train = AnimatableBody3D.new()
	train.collision_layer = G.L_VEH
	train.collision_mask = 0
	train.sync_to_physics = false
	var cs = CollisionShape3D.new()
	var bs = BoxShape3D.new()
	bs.size = Vector3(2.6, 2.9, 12.4)
	cs.shape = bs
	cs.position = Vector3(0, 1.6, 0)
	train.add_child(cs)
	var m = G.model("vehicles/monorail")
	train.add_child(m)
	G.remat(m, {"Paint": G.cmat("train_p", Color(0.1, 0.55, 0.6), 0.4, 0.3), "Paint2": G.cmat("train_p2", Color(0.9, 0.9, 0.9), 0.5)})
	add_child(train)
	train.rotation.y = PI / 2
	train.global_position = Vector3(train_x, 6.05, 0)
	_train_it = {"pos": Vector3(0, -100, 0), "r": 0.0, "text": "Board the Skyline Metro ($5)", "fn": func(): _board_train(), "veh": false}
	G.world.interacts.append(_train_it)


func _update_train(dt: float) -> void:
	var p = G.player
	if train_wait > 0.0:
		train_wait -= dt
		train_speed = 0.0
		var door = Vector3(train_x, 6.75, 2.6)
		if not riding_train:
			_train_it.pos = door
			_train_it.r = 5.0
		if riding_train and G.hud:
			G.hud.hint("[F] Get off at %s station" % _station_name(train_stop))
			if Input.is_action_just_pressed("enter") or Input.is_action_just_pressed("interact"):
				riding_train = false
				p.leave_passenger(Vector3(train_x, 6.75, 3.4))
		if train_wait <= 0.0:
			_train_it.r = 0.0
			# choose the next stop
			var i = STOPS.find(train_stop)
			if i + int(train_dir) < 0 or i + int(train_dir) >= STOPS.size():
				train_dir = -train_dir
			train_stop = STOPS[i + int(train_dir)]
	else:
		var remain: float = abs(train_stop - train_x)
		var want: float = min(15.0, sqrt(2.0 * 2.2 * max(remain, 0.0)) + 0.4)
		train_speed = move_toward(train_speed, want, dt * 3.0)
		train_x += train_dir * train_speed * dt
		if remain < 0.3:
			train_x = train_stop
			train_wait = 8.0
			if G.dist2d(train.global_position, G.player_pos()) < 60.0:
				G.audio.play3d("door", train.global_position, 2.0, 0.7)
	train.global_position = Vector3(train_x, 6.05, 0)
	if _train_snd == null and G.audio:
		_train_snd = G.audio.loop3d("train", train, -2.0, 12.0)
	if _train_snd:
		_train_snd.pitch_scale = 0.6 + train_speed / 15.0 * 0.7
		_train_snd.volume_db = -30.0 if train_speed < 0.5 else -2.0


func _station_name(x: float) -> String:
	return "Metro West" if x < -100 else ("Metro Central" if x < 100 else "Metro East")


func _board_train() -> void:
	if train_wait <= 0.0:
		return
	if G.money < 5:
		G.notify("Not enough cash for a ticket", 2.0)
		return
	G.add_money(-5)
	riding_train = true
	_train_it.r = 0.0
	G.player.set_passenger(train, Vector3(0, 0.9, 0))
	G.notify("Riding the Skyline Metro — press F at a station to get off", 4.0)


# ------------------------------------------------------------------ taxi
func call_taxi() -> void:
	if taxi != null and is_instance_valid(taxi):
		G.notify("A cab is already on its way", 2.0)
		return
	var T = G.traffic
	var pp = G.player_pos()
	for attempt in 20:
		var li = G.rng.randi() % T.lanes.size()
		var l: Dictionary = T.lanes[li]
		var t = l.len * 0.5
		var p: Vector3 = l.p0 + l.dir * t
		var d = G.dist2d(p, pp)
		if d < 60.0 or d > 150.0:
			continue
		taxi = T.spawn_on_lane("taxi", li, t, "taxi")
		taxi.ai.route = T.route(p, pp)
		taxi.ai.personality = 1.2
		taxi_state = "coming"
		_taxi_t = 0.0
		G.notify("Cinder Cab dispatched — it will pull up nearby", 3.0)
		G.audio.play("whistle", -6.0)
		return
	G.notify("No cabs available right now", 2.0)


## Called when the player presses F next to a vehicle. Returns true if handled as a passenger ride.
func try_board(v) -> bool:
	if v.id != "taxi" or not v.has_ai_driver() or G.player.weapons.is_gun() and G.player.aiming:
		return false
	if taxi != null and is_instance_valid(taxi) and taxi != v and taxi_state in ["riding"]:
		return false
	if taxi != v:
		if taxi != null and is_instance_valid(taxi) and taxi_state == "coming":
			taxi.owner_tag = "traffic"
		taxi = v
		v.owner_tag = "taxi"
	taxi.ai.wait = 999.0
	taxi_state = "choose"
	G.menus.open_taxi()
	return true


func taxi_go(dest: Vector3) -> void:
	if taxi == null or not is_instance_valid(taxi):
		return
	taxi_dest = dest
	taxi_from = taxi.global_position
	taxi_state = "riding"
	_taxi_t = 0.0
	taxi.ai.wait = 0.0
	taxi.ai.route = G.traffic.route(taxi.global_position, dest)
	taxi.ai.personality = 1.25
	G.player.set_passenger(taxi, Vector3(0.4, 0.6, 0.6))
	G.notify("Taxi ride started — ENTER to skip the trip, F to get out", 4.0)


func taxi_cancel() -> void:
	if taxi and is_instance_valid(taxi):
		taxi.ai.wait = 0.0
		taxi.owner_tag = "traffic"
	taxi = null
	taxi_state = ""


func _update_taxi(dt: float) -> void:
	if taxi == null:
		return
	if not is_instance_valid(taxi) or taxi.dead or not taxi.has_ai_driver():
		if taxi_state == "riding" and G.player.state == "passenger":
			G.player.leave_passenger(G.player.global_position + Vector3(1.5, 0.5, 0))
		taxi = null
		taxi_state = ""
		return
	_taxi_t += dt
	var p = G.player
	match taxi_state:
		"coming":
			var d = G.dist2d(taxi.global_position, p.global_position)
			if d < 13.0:
				taxi.ai.wait = 999.0
				if G.hud and d < 6.0:
					G.hud.hint("[F] Get in the taxi")
			if _taxi_t > 90.0:
				taxi_cancel()
		"riding":
			var d2 = G.dist2d(taxi.global_position, taxi_dest)
			var done = d2 < 26.0 or (taxi.ai.route.is_empty() and d2 < 70.0 and _taxi_t > 4.0)
			if Input.is_action_just_pressed("skip") and _taxi_t > 1.0 and not done:
				var nl: Dictionary = G.traffic.nearest_lane(taxi_dest)
				var l: Dictionary = G.traffic.lanes[nl.lane]
				taxi.global_transform = Transform3D(Basis(Vector3.UP, atan2(-l.dir.x, -l.dir.z)), nl.pos + Vector3(0, 0.6, 0))
				taxi.linear_velocity = Vector3.ZERO
				taxi.ai.lane = nl.lane
				taxi.ai.mode = "lane"
				taxi.ai.erase("next")
				taxi.ai.route = []
				if G.hud:
					G.hud.fade_in()
				done = true
			if done or Input.is_action_just_pressed("enter") and _taxi_t > 1.0:
				var fare: int = clamp(int(taxi_from.distance_to(taxi.global_position) * 0.12) + 5, 5, 120)
				G.add_money(-min(fare, G.money))
				taxi.ai.wait = 3.0
				taxi.ai.route = []
				var out: Vector3 = taxi.door_pos(1.0) + Vector3(0, 0.3, 0)
				p.leave_passenger(out)
				G.notify("Taxi fare: $%d" % fare, 3.0)
				taxi.owner_tag = "traffic"
				taxi = null
				taxi_state = ""


# ------------------------------------------------------------------ activities
func map_blips() -> Array:
	return _blips


func end_activity(msg := "") -> void:
	activity = ""
	for n in act.get("nodes", []):
		if is_instance_valid(n):
			n.queue_free()
	act = {}
	_blips = []
	if G.hud:
		G.hud.activity_text = ""
	if msg != "":
		G.notify(msg, 5.0)


func start_range() -> void:
	if activity != "":
		return
	if not G.player.weapons.is_gun():
		G.notify("Equip a firearm first", 2.0)
		return
	if G.money < 20:
		G.notify("Entry costs $20", 2.0)
		return
	G.add_money(-20)
	activity = "range"
	act = {"t": 0.0, "n": 0, "hits": 0, "shots0": _ammo_total(), "nodes": [], "next": 1.0, "cur": null, "total": 12}
	G.notify("Shooting range: 12 pop-up targets. Stay behind the barriers.", 4.0)


func _ammo_total() -> int:
	var w = G.player.weapons
	var s = 0
	for id in w.inv:
		s += w.inv[id].clip + w.inv[id].res
	return s


func range_hit(t) -> void:
	if activity != "range":
		return
	act.hits += 1
	G.audio.play("ui_ok", -4.0)
	if G.skills:
		G.skills.gain("shooting", 0.01)
	if is_instance_valid(t):
		t.queue_free()
	act.cur = null
	act.next = 0.5


func _update_range(dt: float) -> void:
	var base: Vector3 = G.world.locations["Shooting Range"]
	act.t += dt
	act.next -= dt
	if G.hud:
		G.hud.activity_text = "RANGE  target %d/%d   hits %d" % [min(act.n, act.total), act.total, act.hits]
	if act.cur != null and act.next <= 0.0:
		if is_instance_valid(act.cur):
			act.cur.queue_free()
		act.cur = null
		act.next = 0.4
	if act.cur == null and act.next <= 0.0:
		if act.n >= act.total:
			var used: int = max(1, act.shots0 - _ammo_total())
			var acc: float = clamp(float(act.hits) / used, 0.0, 1.0)
			var reward: int = act.hits * 15 + int(acc * 100.0)
			G.add_money(reward)
			best["range"] = max(best.get("range", 0), act.hits)
			end_activity("Range complete: %d/%d hits, %d%% accuracy, +$%d" % [act.hits, act.total, int(acc * 100.0), reward])
			return
		act.n += 1
		var tn = StaticBody3D.new()
		tn.set_script(Target)
		add_child(tn)
		tn.global_position = base + Vector3(G.rng.randf_range(-9, 9), 0.15, -G.rng.randf_range(12, 34))
		act.cur = tn
		act.nodes.append(tn)
		act.next = 2.6
	if G.dist2d(G.player.global_position, base) > 30.0:
		end_activity("Left the shooting range")


func _checkpoint(pos: Vector3, col := Color(1.0, 0.4, 0.7, 0.35)) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = 6.0
	cm.bottom_radius = 6.0
	cm.height = 9.0
	cm.radial_segments = 16
	mi.mesh = cm
	var m = StandardMaterial3D.new()
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + Vector3(0, 4.0, 0)
	return mi


func _start_course(kind: String, pts: Array, needs: Array, label: String) -> void:
	if activity != "":
		return
	var v = G.player.vehicle
	if v == null or not (v.kind in needs):
		G.notify("Bring a suitable vehicle to start", 2.5)
		return
	activity = kind
	act = {"t": 0.0, "i": 0, "pts": pts, "nodes": [], "label": label, "go": 3.0}
	act.nodes.append(_checkpoint(pts[0]))
	_blips = [{"pos": pts[0], "col": Color(1.0, 0.4, 0.7)}]
	G.audio.play("ui_ok")


func start_trial() -> void:
	var y = 0.0
	_start_course("trial", [Vector3(0, y, 100), Vector3(0, y, 200), Vector3(240, y, 200), Vector3(240, y, 0), Vector3(240, y, -200), Vector3(0, y, -200),
		Vector3(-240, y, -200), Vector3(-240, y, 0), Vector3(-240, y, 200), Vector3(0, y, 200), Vector3(0, y, 30)], ["car", "bike"], "TIME TRIAL")


func start_searace() -> void:
	var y = G.WATER_Y
	_start_course("searace", [Vector3(200, y, 290), Vector3(340, y, 120), Vector3(340, y, -200), Vector3(0, y, -340), Vector3(-340, y, -100), Vector3(-340, y, 200),
		Vector3(-150, y, 310), Vector3(60, y, 270)], ["boat"], "BAY SPRINT")


func _update_course(dt: float) -> void:
	act.t += dt
	var pts: Array = act.pts
	var pp = G.player_pos()
	if G.hud:
		G.hud.activity_text = "%s  %d/%d   %.1f s" % [act.label, act.i, pts.size(), act.t]
	if G.player.vehicle == null:
		end_activity("%s abandoned" % act.label.capitalize())
		return
	if G.dist2d(pp, pts[act.i]) < 9.0:
		act.i += 1
		G.audio.play("pickup", -4.0)
		for n in act.nodes:
			n.queue_free()
		act.nodes = []
		if act.i >= pts.size():
			var prev: float = best.get(activity, 9999.0)
			var t: float = act.t
			var reward = 150 + int(max(0.0, 140.0 - t) * 4.0)
			G.add_money(reward)
			var nb = t < prev
			best[activity] = min(prev, t)
			if G.skills:
				G.skills.gain("driving", 0.03)
			end_activity("%s finished in %.1f s%s  +$%d" % [act.label.capitalize(), t, "  — new best!" if nb else "", reward])
			return
		act.nodes.append(_checkpoint(pts[act.i]))
		_blips = [{"pos": pts[act.i], "col": Color(1.0, 0.4, 0.7)}]


func on_player_land(_v: float) -> void:
	pass


func on_chute_land(pos: Vector3) -> void:
	var d = G.dist2d(pos, chute_target)
	if d < 10.0:
		var reward = int(400 - d * 25.0)
		G.add_money(reward)
		G.notify("Precision landing! %.1f m from centre, +$%d" % [d, reward], 4.0)
		G.audio.play("cash")


func _update_stunts(dt: float) -> void:
	var v = G.player.vehicle
	if v == null or not is_instance_valid(v) or v.kind not in ["car", "bike"]:
		_was_air = false
		return
	var air: bool = v.grounded == 0
	if air and not _was_air:
		_air_start = v.global_position
		_air_time = 0.0
	if air:
		_air_time += dt
	elif _was_air:
		var dist = G.dist2d(_air_start, v.global_position)
		if _air_time > 1.1 and dist > 14.0 and v.global_basis.y.y > 0.6 and not v.dead:
			var reward = int(dist * 4.0)
			G.add_money(reward)
			G.stats.stunts += 1
			best["jump"] = max(best.get("jump", 0.0), dist)
			G.notify("Stunt jump! %.0f m, %.1f s airtime  +$%d" % [dist, _air_time, reward], 4.0)
			G.audio.play("ui_ok")
			if G.skills:
				G.skills.gain("driving", 0.02)
	_was_air = air


func _physics_process(dt: float) -> void:
	if G.player == null:
		return
	_svc_cd -= dt
	_update_pickups(dt)
	_update_train(dt)
	_update_taxi(dt)
	_amb = _update_service(_amb, dt)
	_fire = _update_service(_fire, dt)
	_update_stunts(dt)
	match activity:
		"range":
			_update_range(dt)
		"trial", "searace":
			_update_course(dt)
