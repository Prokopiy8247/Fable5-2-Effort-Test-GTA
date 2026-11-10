extends Node3D
## 0-5 star wanted system: witnessed crimes, pursuit vs search with line of sight, dispatch, roadblocks, air support, busting.

const NEED := [0.0, 16.0, 26.0, 38.0, 52.0, 70.0]
const WANT_CARS := [0, 1, 2, 3, 3, 4]
const WANT_SWAT := [0, 0, 0, 0, 1, 2]
const Heli := preload("res://gta/code/police/police_heli.gd")

var stars := 0
var heat := 0.0
var state := "clean"          # clean, pursuit, search
var last_known := Vector3.ZERO
var search_radius := 40.0
var escape_t := 0.0
var seen := false
var lethal := false
var units: Array = []
var heli = null
var roadblock: Dictionary = {}
var bonus_vehicle := false
var bonus_look := false
var seen_vehicle = null
var patrol_car = null
var bust_t := 0.0
var last_shot_t := -99.0
var _cd := {}
var _dispatch_t := 0.0
var _see_t := 0.0
var _rb_cd := 20.0
var _resist_flag := false
var _now := 0.0
var _foot_cops_t := 5.0
var calls_pending := 0
var crime_log: Array = []


func start() -> void:
	pass


func _throttle(key: String, secs: float) -> bool:
	if _cd.get(key, -99.0) + secs > _now:
		return false
	_cd[key] = _now
	return true


# ------------------------------------------------------------------ crime intake
func cop_sees(pos: Vector3) -> bool:
	for n in get_tree().get_nodes_in_group("cops"):
		if not n.dead and n.state != "down" and n.can_see(pos + Vector3(0, 1.2, 0), 60.0, -0.2):
			return true
	for v in units:
		if is_instance_valid(v) and not v.dead and v.ai.get("cops", 0) > 0 and v.global_position.distance_to(pos) < 50.0 and G.los(v.global_position + Vector3(0, 1.5, 0), pos + Vector3(0, 1.2, 0)):
			return true
	if patrol_car and is_instance_valid(patrol_car) and not patrol_car.dead and patrol_car.has_ai_driver():
		if patrol_car.global_position.distance_to(pos) < 45.0 and G.los(patrol_car.global_position + Vector3(0, 1.5, 0), pos + Vector3(0, 1.2, 0)):
			return true
	if heli and is_instance_valid(heli) and heli.global_position.distance_to(pos) < 150.0 and G.los(heli.global_position, pos + Vector3(0, 1.5, 0)):
		return true
	return false


func crime(type: String, pos: Vector3, sev: float, direct := false) -> void:
	if G.player == null or G.player.state in ["dead", "busted"]:
		return
	var long_cd: float = 2.0 if type in ["shooting", "collision"] else 0.6
	if type not in ["murder", "kill_cop", "destroy_police", "robbery"] and not _throttle(type, long_cd):
		return
	if direct or cop_sees(pos) or (stars > 0 and state == "pursuit"):
		_add_heat(sev, pos, type)
		return
	var c = {"type": type, "sev": sev, "pos": pos}
	if G.pop and G.pop.find_witness(pos, c, 38.0 if type != "shooting" else 30.0):
		calls_pending += 1
		if _throttle("witness_note", 4.0):
			G.notify("A witness is calling the police…", 2.5)


func witness_report(c: Dictionary) -> void:
	calls_pending = max(0, calls_pending - 1)
	if G.player == null or G.player.state in ["dead", "busted"]:
		return
	_add_heat(c.sev, c.pos, c.type, true)


func _add_heat(sev: float, pos: Vector3, type: String, from_witness := false) -> void:
	var old = stars
	crime_log.append("%s +%.2f%s" % [type, sev, " (witness)" if from_witness else ""])
	if crime_log.size() > 8:
		crime_log.pop_front()
	heat = min(5.99, heat + sev)
	if type == "kill_cop":
		heat = max(heat, 3.0)
	elif type in ["assault_cop", "steal_police", "destroy_police"]:
		heat = max(heat, 2.0)
	stars = int(heat)
	if stars > old:
		G.audio.play("wanted", -4.0)
		escape_t = 0.0
		if old == 0:
			bonus_look = false
			bonus_vehicle = false
			seen_vehicle = null
			_dispatch_t = 0.0
			last_known = pos
			state = "search"
			search_radius = 45.0
	if stars > 0 and (from_witness or state != "pursuit"):
		if G.dist2d(pos, last_known) > 5.0 and not seen:
			last_known = pos
			escape_t = min(escape_t, NEED[stars] * 0.4)


func gunshot(pos: Vector3, radius: float, shooter) -> void:
	if G.pop and _throttle("panic_shot", 0.5):
		G.pop.panic(pos, min(radius * 0.6, 45.0), shooter)
	if shooter != G.player:
		return
	last_shot_t = _now
	if radius < 5.0:
		return
	if radius > 40.0 and stars == 0 and not cop_sees(pos) and _throttle("heard", 8.0):
		# indirect report: somebody nearby heard gunfire
		var heard = false
		for n in get_tree().get_nodes_in_group("npcs"):
			if not n.dead and n.role in ["ped", "clerk"] and n.global_position.distance_to(pos) < radius * 0.7:
				heard = true
				break
		if heard:
			var c = {"type": "shooting", "sev": 1.0, "pos": pos}
			get_tree().create_timer(6.0).timeout.connect(func(): if stars == 0 and G.player.state not in ["dead", "busted"]: witness_report(c))
	crime("shooting", pos, 0.5)


func explosion(pos: Vector3, source) -> void:
	if G.pop:
		G.pop.panic(pos, 60.0, source)
	if source != null and source == G.player:
		if cop_sees(pos) or stars > 0:
			crime("explosion", pos, 1.5, true)
		elif _throttle("boom_report", 2.0):
			var c = {"type": "explosion", "sev": 1.5, "pos": pos}
			get_tree().create_timer(3.5).timeout.connect(func(): witness_report(c))


func vehicle_attacked(v, _amount: float) -> void:
	if v.owner_tag == "police":
		crime("assault_cop", v.global_position, 0.8, v.has_ai_driver() or v.ai.get("cops", 0) > 0)
	elif v.has_ai_driver():
		crime("assault", v.global_position, 0.5)


func appearance_changed() -> void:
	if state == "search" and stars > 0 and not bonus_look and not seen:
		bonus_look = true
		G.notify("New look — police descriptions no longer match", 3.0)


func vehicle_changed(v) -> void:
	if state == "search" and stars > 0 and not bonus_vehicle and not seen and seen_vehicle != null and v != seen_vehicle:
		bonus_vehicle = true
		G.notify("Switched vehicles unseen — harder to identify", 3.0)


func clear(escaped := false) -> void:
	var had = stars > 0
	stars = 0
	heat = 0.0
	state = "clean"
	lethal = false
	seen = false
	escape_t = 0.0
	bust_t = 0.0
	if had and escaped:
		G.notify("You lost the police", 3.0)
		G.audio.play("ui_ok", -4.0)
	for v in units.duplicate():
		if is_instance_valid(v) and not v.dead:
			v.set_siren(false)
			if v.ai.get("cops", 0) > 0 and G.traffic:
				var nl: Dictionary = G.traffic.nearest_lane(v.global_position, -v.global_basis.z)
				G.traffic.adopt(v, nl.lane)
				v.owner_tag = "traffic"
			else:
				v.clear_driver()
				v.owner_tag = "abandoned"
	units.clear()
	for n in get_tree().get_nodes_in_group("cops"):
		if n.has_meta("dispatched"):
			n.leaving = true
			n.lethal = false
			var away: Vector3 = n.global_position + G.flat(n.global_position - G.player_pos()).normalized() * 60.0
			n.goto(away, func(): n.queue_free())
			get_tree().create_timer(25.0).timeout.connect(func(): if is_instance_valid(n) and not n.dead: n.queue_free())
		else:
			n.lethal = false
			if n.state in ["combat", "arrest", "search"]:
				n.set_state("wander")
	if heli and is_instance_valid(heli):
		heli.leave()
		heli = null
	_free_roadblock()


func set_stars(n: int) -> void:
	if n <= 0:
		clear(false)
		return
	heat = float(n) + 0.05
	var old = stars
	stars = n
	last_known = G.player_pos()
	if old == 0:
		state = "search"
		_dispatch_t = 0.0
		bonus_look = false
		bonus_vehicle = false
	escape_t = 0.0
	G.audio.play("wanted", -4.0)


# ------------------------------------------------------------------ update
func _physics_process(dt: float) -> void:
	_now += dt
	var p = G.player
	if p == null:
		return
	if stars == 0:
		heat = max(0.0, heat - dt * 0.02)
		_ambient(dt)
		_cleanup_abandoned()
		return
	if p.state in ["dead", "busted"]:
		return
	var pp = G.player_pos()
	_see_t -= dt
	if _see_t <= 0.0:
		_see_t = 0.2
		seen = _unit_sees_player()
	if seen:
		if state != "pursuit" and _resist_flag:
			_resist_flag = false
		state = "pursuit"
		last_known = pp
		escape_t = 0.0
		search_radius = 45.0
		bonus_look = false
		bonus_vehicle = false
		seen_vehicle = p.vehicle
		heat = min(5.99, heat + dt * (0.012 if stars >= 2 else 0.004))
		if int(heat) > stars:
			stars = int(heat)
			G.audio.play("wanted", -4.0)
			G.notify("Resisting arrest — wanted level raised", 3.0)
	else:
		state = "search"
		escape_t += dt
		search_radius = 45.0 + escape_t * 1.6
		var need: float = NEED[stars]
		if bonus_vehicle:
			need *= 0.75
		if bonus_look:
			need *= 0.75
		if escape_t >= need:
			clear(true)
			return
	lethal = stars >= 2 or (p.weapons.is_gun() and (_now - last_shot_t) < 4.0)
	_engage_cops(p)
	_dispatch_t -= dt
	if _dispatch_t <= 0.0:
		_dispatch_t = 1.5
		_dispatch(pp)
	for v in units.duplicate():
		if not is_instance_valid(v) or v.dead:
			units.erase(v)
			continue
		_drive(v, dt, pp)
	_roadblock_update(dt, pp)
	bust_t = max(0.0, bust_t - dt * 0.5)


func escape_progress() -> float:
	if stars <= 0 or state != "search":
		return 0.0
	return clamp(escape_t / NEED[stars], 0.0, 1.0)


func _unit_sees_player() -> bool:
	var p = G.player
	var body = G.player_body()
	var tp: Vector3 = body.global_position + Vector3(0, 1.3, 0)
	var rng_m: float = (62.0 if G.is_night() else 80.0) * p.detect_mult
	if p.vehicle:
		rng_m = 85.0
	var any = false
	for n in get_tree().get_nodes_in_group("cops"):
		if n.dead or n.state == "down":
			continue
		n.sees_player = n.can_see(tp, rng_m, -0.1 if n.state in ["combat", "arrest"] else 0.15)
		any = any or n.sees_player
	for v in units:
		if is_instance_valid(v) and not v.dead and v.ai.get("cops", 0) > 0:
			if v.global_position.distance_to(tp) < rng_m and G.los(v.global_position + Vector3(0, 1.6, 0), tp, [body.get_rid()] if body is RigidBody3D else []):
				any = true
	if heli and is_instance_valid(heli) and not heli.leaving:
		if heli.global_position.distance_to(tp) < 170.0 and G.los(heli.global_position - Vector3(0, 2, 0), tp):
			any = true
	return any


func _engage_cops(p) -> void:
	for n in get_tree().get_nodes_in_group("cops"):
		if n.dead or n.leaving:
			continue
		if n.state in ["wander", "idle", "search", "goto"] and (n.sees_player or (state == "pursuit" and n.global_position.distance_to(p.global_position) < 35.0)):
			n.target = p
			n.alerted = true
			n.set_state("combat" if (lethal or n.lethal) else "arrest")
		elif n.state == "wander" and state == "search" and n.global_position.distance_to(last_known) < 120.0:
			n.set_state("search")
			n.has_goal = false


func try_bust(cop, dt: float) -> bool:
	var p = G.player
	if p.state not in ["ground", "cover", "vehicle", "ragdoll"]:
		return false
	var sp: float = p.velocity.length() if p.state != "vehicle" else p.vehicle.linear_velocity.length()
	if sp > 1.6 or (_now - last_shot_t) < 2.0 or lethal and p.weapons.is_gun():
		if bust_t > 0.6 and not _resist_flag:
			_resist_flag = true
			heat = min(5.99, heat + 0.35)
			stars = int(heat)
		return false
	bust_t += dt * 1.5
	if G.hud:
		G.hud.hint("Stay still to surrender — move to resist arrest")
	if bust_t > 1.8:
		bust_t = 0.0
		p.bust()
		clear(false)
	return true


func siren_near(pos: Vector3) -> bool:
	for v in units:
		if is_instance_valid(v) and v.siren_on and v.global_position.distance_squared_to(pos) < 900.0 and abs(v.speed) > 4.0:
			return true
	if G.extras:
		for v in G.extras.service_vehicles:
			if is_instance_valid(v) and v.siren_on and v.global_position.distance_squared_to(pos) < 900.0:
				return true
	return false


func unit_blips() -> Array:
	var out = []
	if stars <= 0:
		return out
	for v in units:
		if is_instance_valid(v) and not v.dead:
			out.append({"pos": v.global_position, "dir": -v.global_basis.z})
	for n in get_tree().get_nodes_in_group("cops"):
		if not n.dead and n.state in ["combat", "arrest", "search"]:
			out.append({"pos": n.global_position, "dir": -n.global_basis.z})
	if heli and is_instance_valid(heli):
		out.append({"pos": heli.global_position})
	return out


# ------------------------------------------------------------------ dispatch
func _dispatch(pp: Vector3) -> void:
	var cars = 0
	var swat = 0
	for v in units.duplicate():
		if not is_instance_valid(v) or v.dead:
			units.erase(v)
			continue
		if G.dist2d(v.global_position, pp) > 320.0:
			units.erase(v)
			v.queue_free()
			continue
		if v.id == "swat":
			swat += 1
		else:
			cars += 1
	# nearby ambient patrol responds first
	if patrol_car and is_instance_valid(patrol_car) and not patrol_car.dead and patrol_car.has_ai_driver() and not units.has(patrol_car):
		if G.dist2d(patrol_car.global_position, last_known) < 190.0:
			G.traffic.release(patrol_car)
			_make_unit(patrol_car, 2)
			patrol_car = null
			cars += 1
	if cars < WANT_CARS[stars]:
		_spawn_unit("police", 2)
	elif swat < WANT_SWAT[stars]:
		_spawn_unit("swat", 4)
	if stars >= 3 and (heli == null or not is_instance_valid(heli)):
		heli = Node3D.new()
		heli.set_script(Heli)
		G.main.add_child(heli)
		var a = G.rng.randf() * TAU
		heli.global_position = pp + Vector3(cos(a) * 240.0, 110.0, sin(a) * 240.0)
	# stranded foot cops far from the action despawn; cops near their car re-mount when the suspect drives off
	for n in get_tree().get_nodes_in_group("cops"):
		if n.dead or not n.has_meta("dispatched"):
			continue
		var d = G.dist2d(n.global_position, pp)
		var cam = get_viewport().get_camera_3d()
		if d > 130.0 and (cam == null or (n.global_position - cam.global_position).dot(-cam.global_basis.z) < 0.0 or d > 200.0):
			n.queue_free()
		elif d > 55.0 and G.player.vehicle and n.vehicle_home and is_instance_valid(n.vehicle_home) and not n.vehicle_home.dead:
			var vh = n.vehicle_home
			if n.global_position.distance_to(vh.global_position) < 9.0 and vh.driver == null:
				for m in get_tree().get_nodes_in_group("cops"):
					if m.vehicle_home == vh and not m.dead and m.global_position.distance_to(vh.global_position) < 12.0:
						vh.ai["cops"] = vh.ai.get("cops", 0) + 1
						m.queue_free()
				if vh.ai.get("cops", 0) > 0:
					_make_unit(vh, vh.ai.cops)


func _make_unit(v, cops: int) -> void:
	v.owner_tag = "police"
	v.set_driver(G.traffic)
	v.ai = {"mode": "pursuit", "cops": cops, "state": "drive", "stuck": 0.0, "rev": 0.0, "route": [], "route_t": 0.0, "fire_t": 2.0, "hold": 0.0}
	v.set_siren(true)
	if not units.has(v):
		units.append(v)


func _spawn_unit(id: String, cops: int) -> void:
	var T = G.traffic
	var cam = get_viewport().get_camera_3d()
	for attempt in 12:
		var li = G.rng.randi() % T.lanes.size()
		var l: Dictionary = T.lanes[li]
		var t = G.rng.randf_range(4.0, l.len - 6.0)
		var p: Vector3 = l.p0 + l.dir * t
		var d = G.dist2d(p, last_known)
		if d < 85.0 or d > 190.0:
			continue
		if cam and (p - cam.global_position).normalized().dot(-cam.global_basis.z) > 0.6 and G.los(cam.global_position, p + Vector3(0, 1.2, 0)):
			continue
		var ok = true
		for o in get_tree().get_nodes_in_group("vehicles"):
			if o.global_position.distance_squared_to(p) < 100.0:
				ok = false
				break
		if not ok:
			continue
		# face toward the suspect
		var dir: Vector3 = l.dir
		var v = T.create(id, p + Vector3(0, 0.5, 0), atan2(-dir.x, -dir.z))
		_make_unit(v, cops)
		v.linear_velocity = dir * 8.0
		return


func _deploy(v) -> void:
	var n: int = v.ai.get("cops", 0)
	if n <= 0:
		return
	v.ai.cops = 0
	v.ai.state = "parked"
	v.clear_driver()
	v.engine_on = true
	var role = "swat" if v.id == "swat" else "cop"
	for i in n:
		var side = -1.0 if i % 2 == 0 else 1.0
		var pos: Vector3 = v.to_global(Vector3(side * (v._half.x + 0.8), 0.2, -0.6 + (i / 2) * 1.6))
		var c = G.pop.spawn_ped(pos, {}, role)
		c.set_meta("dispatched", true)
		c.vehicle_home = v
		c.target = G.player
		c.alerted = true
		c.rotation.y = v.global_rotation.y
		if stars >= 3 and role == "cop" and i % 2 == 1:
			var w: String = ["smg", "shotgun"][G.rng.randi() % 2]
			c.weapons.give(w)
			c.weapons.select(w)
		c.set_state("combat" if lethal else "arrest")
	G.audio.play3d("door", v.global_position, 0.0)


func _drive(v, dt: float, pp: Vector3) -> void:
	var ai: Dictionary = v.ai
	if ai.get("state", "") != "drive" or not ai.has("route_t"):
		return
	var pos: Vector3 = v.global_position
	var fwd: Vector3 = -v.global_basis.z
	var p = G.player
	var pveh = p.vehicle
	var target: Vector3 = pp
	var pursuing = state == "pursuit"
	if not pursuing:
		if not ai.has("goal") or G.dist2d(ai.goal, pos) < 10.0 or ai.hold > 14.0:
			ai["hold"] = 0.0
			var rp = last_known + Vector3(G.rng.randf_range(-1, 1), 0, G.rng.randf_range(-1, 1)) * search_radius
			var nl: Dictionary = G.traffic.nearest_lane(rp)
			ai["goal"] = nl.pos
		ai.hold += dt
		target = ai.goal
	elif pveh:
		target = pp + pveh.linear_velocity * 0.5
	var dist = G.dist2d(pos, target)
	var direct: bool = dist < 55.0 and G.los(pos + Vector3(0, 1.2, 0), target + Vector3(0, 1.2, 0), [v.get_rid()])
	var aim: Vector3 = target
	if not direct:
		ai.route_t -= dt
		if ai.route_t <= 0.0 or ai.route.is_empty():
			ai.route_t = 2.5
			ai.route = G.traffic.route(pos, target)
			# skip the first node if we are already past it
			if ai.route.size() > 1 and G.dist2d(G.traffic.node_pos(ai.route[0]), pos) < 16.0:
				ai.route.pop_front()
		if ai.route.size() > 0:
			var np: Vector3 = G.traffic.node_pos(ai.route[0])
			if G.dist2d(np, pos) < 13.0 and ai.route.size() > 1:
				ai.route.pop_front()
				np = G.traffic.node_pos(ai.route[0])
			aim = np if ai.route.size() > 1 or dist > 30.0 else target
	var want_speed = 26.0 if stars < 3 else 32.0
	if not pursuing:
		want_speed = 12.0
	# tactics versus a vehicle
	if pursuing and pveh and direct and dist < 16.0:
		var pf: Vector3 = -pveh.global_basis.z
		var rel: Vector3 = pos - pveh.global_position
		var ps: float = pveh.linear_velocity.length()
		if ps > 9.0:
			# PIT: aim for the rear quarter and steer into it
			var side: float = sign(rel.dot(pveh.global_basis.x) + 0.01)
			aim = pveh.global_position - pf * 1.6 + pveh.global_basis.x * side * 1.1
			want_speed = ps + 7.0
		elif ps < 4.0:
			# box in: stop tight against the suspect
			want_speed = 3.0 if dist > 5.5 else 0.0
		else:
			want_speed = ps + 5.0
	# on-foot suspect: pull up and deploy
	var deploy_now = false
	if pursuing and pveh == null and dist < 20.0:
		want_speed = 0.0
		deploy_now = true
	if pursuing and pveh and pveh.linear_velocity.length() < 2.0 and dist < 10.0:
		ai.hold += dt
		if ai.hold > 2.5:
			deploy_now = true
			want_speed = 0.0
	elif pursuing:
		ai.hold = 0.0
	if pveh and pveh.kind in ["heli", "plane", "boat"] and dist < 45.0 and pursuing:
		want_speed = 0.0
		if pveh.linear_velocity.length() < 3.0:
			deploy_now = true
	if deploy_now and abs(v.speed) < 2.0:
		_deploy(v)
		return
	# obstacle avoidance + steering
	var to = G.flat(aim - pos)
	var ang = fwd.signed_angle_to(to.normalized(), Vector3.UP) if to.length() > 0.5 else 0.0
	var steer: float = clamp(ang * 2.0, -1.0, 1.0)
	var o = pos + Vector3(0, 0.8, 0) + fwd * (v._half.z + 0.2)
	var reach: float = 5.0 + abs(v.speed) * 0.45
	var ex = [v.get_rid()]
	if pveh and pursuing:
		ex.append(pveh.get_rid())
	var c = G.ray(o, o + fwd * reach, G.L_WORLD | G.L_VEH, ex)
	if c:
		var l = G.ray(o, o + fwd.rotated(Vector3.UP, 0.55) * reach, G.L_WORLD | G.L_VEH, ex)
		var r = G.ray(o, o + fwd.rotated(Vector3.UP, -0.55) * reach, G.L_WORLD | G.L_VEH, ex)
		if l.is_empty() and not r.is_empty():
			steer = 1.0
		elif r.is_empty() and not l.is_empty():
			steer = -1.0
		elif l.is_empty() and r.is_empty():
			steer = 1.0 if ang >= 0.0 else -1.0
		else:
			steer = 1.0 if o.distance_to(l.position) > o.distance_to(r.position) else -1.0
		want_speed = min(want_speed, 9.0)
		if o.distance_to(c.position) < 2.2:
			ai.stuck += dt
	if abs(v.speed) < 1.0 and want_speed > 1.0:
		ai.stuck += dt
	else:
		ai.stuck = max(0.0, ai.stuck - dt * 0.5)
	if ai.rev > 0.0:
		ai.rev -= dt
		v.in_throttle = -1.0
		v.in_brake = 0.0
		v.in_steer = -steer
		return
	if ai.stuck > 1.6:
		ai.stuck = 0.0
		ai.rev = 1.4
		ai["revs"] = ai.get("revs", 0) + 1
		if ai.revs > 4 and pveh == null and dist < 60.0:
			_deploy(v)
			return
	v.in_steer = steer
	var err: float = want_speed - v.speed
	if want_speed <= 0.1:
		v.in_throttle = 0.0
		v.in_brake = 1.0
	elif abs(ang) > 1.2 and v.speed > 10.0:
		v.in_throttle = 0.0
		v.in_brake = 0.7
	elif err > 0.0:
		v.in_throttle = clamp(err * 0.4, 0.2, 1.0)
		v.in_brake = 0.0
	else:
		v.in_throttle = 0.0
		v.in_brake = clamp(-err * 0.2, 0.0, 1.0)
	# officers shooting from the vehicle
	if lethal and stars >= 3 and pursuing and dist < 35.0 and direct:
		ai.fire_t -= dt
		if ai.fire_t <= 0.0:
			ai.fire_t = G.rng.randf_range(0.5, 1.4)
			_car_fire(v, pp)


func _car_fire(v, pp: Vector3) -> void:
	var from: Vector3 = v.global_position + Vector3(0, 1.3, 0) + v.global_basis.x * 0.9
	var to = pp + Vector3(G.rng.randf_range(-2.2, 2.2), 1.0 + G.rng.randf_range(-0.8, 1.2), G.rng.randf_range(-2.2, 2.2))
	var dir = (to - from).normalized()
	var h = G.ray(from, from + dir * 60.0, G.L_SHOT, [v.get_rid()])
	G.fx.tracer(from, h.position if h else from + dir * 60.0)
	G.fx.muzzle(from, dir)
	G.audio.play3d("shot_handgun", from, -2.0)
	if h:
		var n: Node = h.collider
		for i in 3:
			if n == null:
				break
			if n.has_method("damage"):
				n.damage(7.0, v, h.position, "bullet")
				break
			n = n.get_parent()
		G.fx.impact(h.position, h.normal, "metal" if h.collider is RigidBody3D else "concrete")


# ------------------------------------------------------------------ roadblocks
func _roadblock_update(dt: float, pp: Vector3) -> void:
	_rb_cd -= dt
	var p = G.player
	if not roadblock.is_empty():
		var c: Vector3 = roadblock.pos
		if G.dist2d(c, pp) > 190.0 or roadblock.t > 80.0:
			_free_roadblock()
			return
		roadblock.t += dt
		if roadblock.has("spike") and p.vehicle and p.vehicle.kind in ["car", "bike"]:
			var sp: Vector3 = roadblock.spike
			var rel: Vector3 = p.vehicle.global_position - sp
			var along: float = abs(rel.dot(roadblock.dir))
			var across: float = abs(rel.dot(roadblock.dir.cross(Vector3.UP)))
			if along < 2.4 and across < 5.5 and not roadblock.get("popped", false):
				roadblock["popped"] = true
				if not p.vehicle.st.bp_tires:
					for w in p.vehicle.wheels:
						w.flat = true
					G.notify("Spike strip! Tyres shredded", 3.0)
					G.audio.play3d("whoosh", sp, 2.0, 0.5)
		return
	if stars < 3 or _rb_cd > 0.0 or p.vehicle == null or p.vehicle.kind not in ["car", "bike"] or p.vehicle.linear_velocity.length() < 8.0:
		return
	var T = G.traffic
	var heading: Vector3 = p.vehicle.linear_velocity.normalized()
	var nl: Dictionary = T.nearest_lane(pp, heading)
	if nl.is_empty() or nl.dist > 12.0:
		return
	var lane: Dictionary = T.lanes[nl.lane]
	var pos = Vector3.ZERO
	var dir: Vector3 = lane.dir
	var found = false
	if lane.len - nl.t > 85.0:
		pos = lane.p0 + lane.dir * (nl.t + 80.0)
		found = true
	else:
		for o in T.out_lanes[lane.b]:
			var l2: Dictionary = T.lanes[o]
			if l2.dir.dot(lane.dir) > 0.9 and l2.len > 60.0:
				pos = l2.p0 + l2.dir * 35.0
				dir = l2.dir
				found = true
	if not found:
		return
	_rb_cd = 30.0
	var right = dir.cross(Vector3.UP)
	var center = pos - right * T.LANE_OFF
	roadblock = {"pos": center, "dir": dir, "t": 0.0, "nodes": []}
	var yaw = atan2(-dir.x, -dir.z) + PI / 2
	var hw: float = 10.0 if (abs(center.x) < 1.0 or abs(center.z) < 1.0) else 7.0
	for s in [-1.0, 1.0]:
		var v = T.create("police" if stars < 5 or s < 0 else "swat", center + right * s * (hw * 0.42) + Vector3(0, 0.5, 0), yaw + (0.25 * s))
		v.owner_tag = "police"
		v.set_siren(true)
		v.in_hand = true
		v.in_brake = 1.0
		roadblock.nodes.append(v)
		var bp = G.world.prop("barrier_police", center + right * s * (hw - 1.4) + Vector3(0, 0.2, 0) - dir * 0.5, yaw - PI / 2)
		roadblock.nodes.append(bp)
	for i in (2 if stars < 4 else 4):
		var cp: Vector3 = center + dir * 3.5 + right * (i - 1.0) * 2.4
		var c = G.pop.spawn_ped(cp + Vector3(0, 0.2, 0), {}, "swat" if stars >= 4 and i % 2 == 0 else "cop")
		c.set_meta("dispatched", true)
		c.vehicle_home = roadblock.nodes[0]
		c.target = p
		c.lethal = true
		c.set_state("combat")
		c.rotation.y = atan2(dir.x, dir.z)
	if stars >= 4:
		var sp = center - dir * 14.0
		var sn = G.world.prop("spike_strip", sp + Vector3(0, 0.02, 0), yaw - PI / 2)
		sn.scale.x = hw / 2.4
		roadblock["spike"] = sp
		roadblock.nodes.append(sn)
	if _throttle("rb_note", 20.0):
		G.notify("Police roadblock ahead", 2.5)


func _free_roadblock() -> void:
	if roadblock.is_empty():
		return
	for n in roadblock.nodes:
		if is_instance_valid(n):
			if n is RigidBody3D and n.is_in_group("vehicles") and not n.dead:
				n.owner_tag = "abandoned"
				n.set_siren(false)
			else:
				n.queue_free()
	roadblock = {}


# ------------------------------------------------------------------ ambient police presence
func _ambient(dt: float) -> void:
	_foot_cops_t -= dt
	if _foot_cops_t > 0.0 or G.traffic == null or not G.traffic.enabled:
		return
	_foot_cops_t = 4.0
	var pp = G.player_pos()
	if patrol_car == null or not is_instance_valid(patrol_car) or patrol_car.dead or G.dist2d(patrol_car.global_position, pp) > 260.0 or not patrol_car.has_ai_driver():
		if patrol_car != null and is_instance_valid(patrol_car) and patrol_car.has_ai_driver() and G.dist2d(patrol_car.global_position, pp) > 260.0:
			G.traffic.release(patrol_car)
			patrol_car.queue_free()
		patrol_car = null
		for attempt in 6:
			var li = G.rng.randi() % G.traffic.lanes.size()
			var l: Dictionary = G.traffic.lanes[li]
			var p: Vector3 = l.p0 + l.dir * (l.len * 0.5)
			var d = G.dist2d(p, pp)
			if d > 110.0 and d < 220.0:
				patrol_car = G.traffic.spawn_on_lane("police", li, l.len * 0.5, "police")
				break
	var beat = 0
	for n in get_tree().get_nodes_in_group("cops"):
		if not n.dead and not n.has_meta("dispatched"):
			beat += 1
			if G.dist2d(n.global_position, pp) > 190.0:
				n.queue_free()
	if beat < 2 and G.pop and G.pop.enabled:
		for attempt in 5:
			var i = G.rng.randi() % G.world.ped_nodes.size()
			var np: Vector3 = G.world.ped_nodes[i]
			var d2 = G.dist2d(np, pp)
			if d2 > 60.0 and d2 < 140.0 and abs(np.x) < 130.0 and abs(np.z) < 110.0:
				var c = G.pop.spawn_ped(np + Vector3(0, 0.1, 0), {}, "cop")
				c.node_i = i
				c.prev_i = i
				break


func _cleanup_abandoned() -> void:
	if int(_now * 2.0) % 10 != 0:
		return
	var pp = G.player_pos()
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v.owner_tag == "abandoned" and v.driver == null and G.dist2d(v.global_position, pp) > 90.0:
			v.queue_free()
