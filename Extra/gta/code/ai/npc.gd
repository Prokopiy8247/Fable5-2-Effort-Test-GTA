class_name NPC
extends CharacterBody3D
## All non-player humans: pedestrians, shop staff, drivers, gang members, police officers and tactical units.
## One state machine with behaviour driven by `kind`, personality and what the character perceives.

enum S { WANDER, IDLE, FLEE, COWER, FIGHT, INVESTIGATE, DRIVER, CLERK, DEAD, RAGDOLL, CALL, GOTO }

var kind := "civ"
var st: int = S.WANDER
var vis: CharVisual
var look := {}
var health := 100.0
var max_health := 100.0
var dead := false
var weapon := ""
var weapon_model: Node3D
var clip := 0
var target: Node3D = null
var brave := 0.3
var aggro := false
var vehicle: Vehicle = null
var seat := -1
var node_cur := -1
var node_prev := -1
var goal := Vector3.ZERO
var side_off := 0.0
var walk_speed := 1.5
var state_t := 0.0
var think_t := 0.0
var fire_cd := 0.0
var burst := 0
var reload_t := 0.0
var last_seen := Vector3.ZERO
var lost_t := 0.0
var ragdoll: Ragdoll = null
var ragdoll_min := 2.0
var face_yaw := 0.0
var danger := Vector3.ZERO
var stuck_t := 0.0
var cover_pos = null
var in_cover := false
var strafe_dir := 1.0
var tier := 0
var wait_cross := 0.0
var is_police := false
var shop_kind := ""
var robbed := 0.0
var aware := 0.0
var knocked_out := false
var call_t := 0.0
var crime_seen := {}
var spawn_time := 0.0
var home := Vector3.ZERO
var manager: Node = null
var gravity_v := 0.0
var accuracy := 0.55
var arrest_t := 0.0
var hands_up := false
var speak_cd := 0.0


func setup(k: String, lk: Dictionary = {}) -> void:
	kind = k
	add_to_group("chars")
	add_to_group("npcs")
	collision_layer = G.L_CHAR
	collision_mask = G.L_WORLD | G.L_VEHICLE
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0, 0.88, 0)
	cs.name = "Col"
	add_child(cs)
	floor_snap_length = 0.3
	look = lk if not lk.is_empty() else CharVisual.random_look(G.rng, k if k in ["cop", "swat", "medic", "fire", "gang", "clerk"] else "civ")
	vis = CharVisual.new()
	add_child(vis)
	vis.setup(look)
	vis.blend_rate = 10.0
	brave = G.rng.randf()
	walk_speed = G.rng.randf_range(1.25, 1.75)
	side_off = G.rng.randf_range(-1.2, 1.2)
	spawn_time = Time.get_ticks_msec() / 1000.0
	match kind:
		"cop":
			is_police = true
			_arm("pistol")
			health = 120.0
			brave = 1.0
			accuracy = 0.5
		"swat":
			is_police = true
			_arm("carbine" if G.rng.randf() < 0.7 else "smg")
			health = 220.0
			brave = 1.0
			accuracy = 0.62
		"gang":
			_arm(["pistol", "pistol", "smg", "bat", "knife"][G.rng.randi() % 5])
			brave = 0.9
			health = 110.0
			accuracy = 0.4
		"clerk":
			st = S.CLERK
	max_health = health
	set_process(true)


func _arm(wid: String) -> void:
	weapon = wid
	clip = int(Defs.WEAPONS[wid].get("mag", 0))
	_show_weapon(false)


func _show_weapon(drawn: bool) -> void:
	if weapon == "" or (weapon_model != null and drawn):
		return
	if not drawn:
		vis.set_weapon(null, "none", false)
		weapon_model = null
		return
	var d: Dictionary = Defs.WEAPONS[weapon]
	weapon_model = Weapons.make_model(weapon)
	var two: bool = d.type in ["smg", "rifle", "rpg"]
	vis.set_weapon(weapon_model, "pistol" if d.type == "pistol" else ("melee" if d.type == "melee" else "rifle"), two)


func global_position_now() -> Vector3:
	return ragdoll.global_position if ragdoll != null else global_position


func is_head_hit(pos: Vector3) -> bool:
	return pos.y > global_position.y + 1.5 - vis.hips_drop


func eye() -> Vector3:
	return global_position + Vector3(0, 1.6 - vis.hips_drop, 0)


func can_see(pos: Vector3, max_d: float = 70.0, fov_dot: float = -0.2) -> bool:
	var to := pos - eye()
	if to.length() > max_d:
		return false
	var fwd := Basis(Vector3.UP, face_yaw) * Vector3(0, 0, -1)
	if to.length() > 4.0 and G.flat(to).normalized().dot(fwd) < fov_dot:
		return false
	var excl: Array = [get_rid()]
	if vehicle != null:
		excl.append(vehicle.get_rid())
	var pv = G.player.vehicle if G.player else null
	if pv != null:
		excl.append(pv.get_rid())
	return G.ray(eye(), pos, G.L_WORLD | G.L_VEHICLE, excl).is_empty()


# ------------------------------------------------------------------ reactions
func take_damage(amount: float, instigator: Node = null, pos: Vector3 = Vector3.ZERO, dkind: String = "") -> void:
	if dead:
		return
	var a := amount
	if kind == "swat" and dkind == "bullet" and not is_head_hit(pos):
		a *= 0.55
	health -= a
	aware = 1.0
	if vis.action == "":
		vis.play("hit", 0.3)
	if speak_cd <= 0.0:
		speak_cd = 1.5
		Sfx.play("grunt", global_position, -6.0, randf_range(0.85, 1.2) * (1.15 if look.get("sex", "m") == "f" else 0.95))
	if health <= 0.0:
		die(instigator, dkind)
		return
	if vehicle != null:
		if vehicle.ai != null and vehicle.ai.has_method("on_driver_attacked"):
			vehicle.ai.on_driver_attacked(instigator)
		return
	if instigator != null and instigator is Node3D and instigator != self:
		_provoked(instigator as Node3D, a)


func _provoked(by: Node3D, dmg: float) -> void:
	if is_police or kind == "gang":
		if is_police and G.is_player(by) and G.wanted:
			G.wanted.report("assault_police", global_position, 2.2, true)
		engage(by)
	elif brave > 0.72 and dmg < 30.0 and not (by.get("inv") != null and not by.melee_equipped()):
		engage(by)
	else:
		flee_from(by.global_position)


func engage(t: Node3D) -> void:
	if dead or st == S.DRIVER:
		return
	target = t
	st = S.FIGHT
	state_t = 0.0
	hands_up = false
	last_seen = t.global_position
	lost_t = 0.0
	_show_weapon(true)


func flee_from(p: Vector3) -> void:
	if dead or st in [S.DRIVER, S.FIGHT] or is_police:
		return
	danger = p
	if st != S.FLEE:
		st = S.FLEE if G.rng.randf() < 0.82 or kind == "clerk" else S.COWER
		state_t = 0.0
		if kind == "clerk":
			st = S.COWER
		if speak_cd <= 0.0:
			speak_cd = 3.0
			Sfx.play("scream", global_position, -3.0, randf_range(0.9, 1.25) * (1.2 if look.get("sex", "m") == "f" else 0.9))


func hear(pos: Vector3, nkind: String, source: Node) -> void:
	if dead or st == S.DRIVER or ragdoll != null:
		return
	match nkind:
		"gunshot", "explosion":
			aware = 1.0
			if is_police:
				if st != S.FIGHT:
					st = S.INVESTIGATE
					goal = pos
					state_t = 0.0
					_show_weapon(true)
			elif kind == "gang":
				if source != null and G.is_player(source) and pos.distance_to(global_position) < 30.0:
					engage(source as Node3D)
			else:
				flee_from(pos)
		"step", "fight":
			if st in [S.WANDER, S.IDLE]:
				aware = minf(aware + 0.5, 1.0)
				if is_police and nkind == "fight":
					st = S.INVESTIGATE
					goal = pos
					state_t = 0.0
		"horn":
			if st == S.WANDER and pos.distance_to(global_position) < 8.0:
				_sidestep(pos)


func _sidestep(from: Vector3) -> void:
	var away := G.flat(global_position - from).normalized()
	velocity = away * 4.0
	vis.play("hit", 0.3)


func knockdown(impulse: Vector3) -> void:
	if dead or ragdoll != null or st == S.DRIVER:
		return
	_start_ragdoll(impulse, false)


func hit_by_vehicle(veh: Vehicle, vel: Vector3) -> void:
	if ragdoll != null or dead or vehicle != null:
		return
	var sp := vel.length()
	var drv: Node = veh.driver
	health -= maxf(sp - 3.0, 0.0) * 7.0
	Sfx.play("thud", global_position, 0.0, randf_range(0.9, 1.1))
	if G.is_player(drv):
		G.report_crime("run_over" if not is_police else "assault_police", global_position, 1.0 if not is_police else 2.2, drv)
	if health <= 0.0:
		die(drv, "vehicle")
		if ragdoll:
			ragdoll.apply_central_impulse(vel * 0.6 * ragdoll.mass + Vector3(0, 3, 0) * ragdoll.mass)
	else:
		_start_ragdoll(vel * 0.6 + Vector3(0, 2.5, 0), false)
		if is_police or kind == "gang":
			if G.is_player(drv):
				target = drv as Node3D
		else:
			danger = veh.global_position


func can_takedown(by: Node3D) -> bool:
	if dead or ragdoll != null or st in [S.DRIVER, S.FIGHT]:
		return false
	var fwd := Basis(Vector3.UP, face_yaw) * Vector3(0, 0, -1)
	return G.flat(by.global_position - global_position).normalized().dot(fwd) < 0.2 and aware < 0.8


func takedown(by: Node3D) -> void:
	knocked_out = true
	health = 0.0
	die(by, "takedown")


func pulled_from_vehicle(veh: Vehicle, by: Node3D) -> void:
	var s := seat
	leave_vehicle()
	global_position = veh.door_point(maxi(s, 0)) + Vector3(0, 0.1, 0)
	aware = 1.0
	if is_police or kind == "gang" or brave > 0.86:
		_start_ragdoll(veh.global_transform.basis.x * (-2.0 if s % 2 == 0 else 2.0) + Vector3(0, 1.5, 0), false)
		target = by
		aggro = true
	else:
		_start_ragdoll(veh.global_transform.basis.x * (-2.5 if s % 2 == 0 else 2.5) + Vector3(0, 1.2, 0), false)
		danger = veh.global_position
	Sfx.play("scream", global_position, -4.0, randf_range(0.9, 1.2))


func flee_vehicle(veh: Vehicle) -> void:
	var s := seat
	leave_vehicle()
	global_position = veh.door_point(maxi(s, 0)) + Vector3(0, 0.1, 0)
	if is_police or kind == "gang":
		engage(G.player)
	else:
		flee_from(veh.global_position)


func on_vehicle_destroyed(_veh: Vehicle) -> void:
	leave_vehicle()
	health = 0.0
	die(null, "explosion")


func fall_off_vehicle(veh: Vehicle, vel: Vector3) -> void:
	leave_vehicle()
	_start_ragdoll(vel * 0.7 + Vector3(0, 2, 0), false)
	danger = veh.global_position


func enter_vehicle(veh: Vehicle, s: int) -> void:
	vehicle = veh
	seat = s
	veh.occupy(s, self)
	st = S.DRIVER
	if get_parent():
		get_parent().remove_child(self)
	(veh.seats[s].node as Node3D).add_child(self)
	transform = Transform3D(Basis(), Vector3(0, -(0.94 * vis.S - 0.04), 0))
	$Col.disabled = true
	collision_layer = 0
	velocity = Vector3.ZERO
	vis.mode = "bike" if veh.kind == "bike" else "sit"
	vis.speed = 0.0
	vis.aim = 0.0
	_show_weapon(false)
	set_physics_process(false)


func leave_vehicle() -> void:
	if vehicle == null:
		return
	var veh := vehicle
	var gt := global_transform
	veh.vacate(self)
	vehicle = null
	seat = -1
	if get_parent():
		get_parent().remove_child(self)
	G.main.add_child(self)
	global_transform = Transform3D(Basis(Vector3.UP, veh.rotation.y), gt.origin)
	face_yaw = veh.rotation.y
	$Col.disabled = false
	collision_layer = G.L_CHAR
	vis.mode = "foot"
	st = S.WANDER
	node_cur = -1
	set_physics_process(true)
	if manager and manager.has_method("adopt"):
		manager.adopt(self)


func _start_ragdoll(impulse: Vector3, is_dead: bool) -> void:
	if ragdoll != null:
		return
	if vehicle != null:
		leave_vehicle()
	$Col.disabled = true
	remove_from_group("chars")
	ragdoll = Ragdoll.start(self, vis, impulse, is_dead)
	ragdoll_min = 1.6 + G.rng.randf() * 1.5
	if not is_dead:
		st = S.RAGDOLL


func die(instigator: Node = null, dkind: String = "") -> void:
	if dead:
		return
	dead = true
	st = S.DEAD
	var was_in_vehicle := vehicle != null
	var v := velocity
	if was_in_vehicle:
		v = vehicle.linear_velocity
		var veh := vehicle
		var s := seat
		leave_vehicle()
		global_position = veh.door_point(maxi(s, 0))
	remove_from_group("chars")
	remove_from_group("npcs")
	if ragdoll == null:
		_start_ragdoll(v * 0.4 + Vector3(randf() - 0.5, 1.2, randf() - 0.5), true)
	else:
		ragdoll.vis.mode = "dead"
	state_t = 0.0
	if G.is_player(instigator):
		if not knocked_out:
			G.report_crime("murder_police" if is_police else "murder", global_position_now(), 3.0 if is_police else 1.6, instigator)
		if G.player:
			G.player.stats.kills += 0
	# loot
	if G.main.has_node("Interactions"):
		var it := G.main.get_node("Interactions")
		var p := global_position_now() + Vector3(randf_range(-0.5, 0.5), 0.3, randf_range(-0.5, 0.5))
		if kind != "clerk" or true:
			it.drop("cash", p, {"amount": G.rng.randi_range(15, 130) * (3 if kind in ["gang", "swat"] else 1)})
		if weapon != "" and G.rng.randf() < 0.75:
			it.drop("weapon", p + Vector3(0.4, 0, 0.3), {"weapon": weapon})
	if G.services and G.services.has_method("on_casualty") and dkind != "takedown":
		G.services.on_casualty(global_position_now())


# ------------------------------------------------------------------ main update
func _process(delta: float) -> void:
	if vis == null or ragdoll != null:
		return
	if tier <= 1 or st == S.FIGHT:
		if st != S.DRIVER:
			rotation.y = lerp_angle(rotation.y, face_yaw, clampf(delta * 9.0, 0.0, 1.0))
		vis.lod_skip = 0 if tier == 0 else 2
		vis.tick(delta)


func _physics_process(delta: float) -> void:
	state_t += delta
	speak_cd -= delta
	if ragdoll != null:
		if dead:
			if state_t > 28.0 or (state_t > 8.0 and G.player and ragdoll.global_position.distance_to(G.player.global_position_now()) > 90.0):
				ragdoll.queue_free()
				queue_free()
			return
		global_position = ragdoll.global_position
		if ragdoll.age > ragdoll_min and ragdoll.settled():
			_get_up()
		return
	if dead:
		return
	if tier >= 2 and st in [S.WANDER, S.IDLE]:
		_far_move(delta)
		return
	think_t -= delta
	match st:
		S.WANDER: _wander(delta)
		S.IDLE:
			_move(Vector3.ZERO, 0.0, delta)
			if state_t > 3.0:
				st = S.WANDER
				vis.phone = 0.0
		S.FLEE: _flee(delta)
		S.COWER: _cower(delta)
		S.FIGHT: _fight(delta)
		S.INVESTIGATE: _investigate(delta)
		S.CLERK: _clerk(delta)
		S.CALL: _call(delta)
		S.GOTO:
			_move(goal, 3.4, delta)
			if G.dist2(global_position, goal) < 1.5 or state_t > 25.0:
				st = S.WANDER
	if think_t <= 0.0:
		think_t = 0.35 + randf() * 0.2
		_think()
	vis.hands_up = move_toward(vis.hands_up, 1.0 if hands_up else 0.0, delta * 5.0)


func _get_up() -> void:
	var p := ragdoll.global_position
	var h := G.ray(p + Vector3(0, 0.6, 0), p - Vector3(0, 3.0, 0), G.L_WORLD)
	global_position = h.position + Vector3(0, 0.05, 0) if not h.is_empty() else p
	ragdoll.release_visual(self)
	ragdoll.queue_free()
	ragdoll = null
	$Col.disabled = false
	add_to_group("chars")
	vis.mode = "foot"
	node_cur = -1
	if target != null and is_instance_valid(target) and (is_police or kind == "gang" or aggro):
		engage(target)
	elif danger != Vector3.ZERO:
		st = S.FLEE
		state_t = 0.0
	else:
		st = S.WANDER


func _think() -> void:
	## Periodic perception: threats, player aiming, witnessed crimes.
	var p: Node3D = G.player
	if p == null or p.dead:
		if st == S.FIGHT and target == p:
			st = S.WANDER
			_show_weapon(false)
		return
	var pp: Vector3 = p.global_position_now()
	var d := pp.distance_to(global_position)
	aware = maxf(aware - 0.05, 0.0)
	if is_police:
		if G.wanted and G.wanted.level > 0 and st != S.FIGHT and d < 80.0 and can_see(pp + Vector3(0, 1.0, 0), 80.0, -0.5):
			engage(p)
		return
	if d > 28.0:
		return
	var armed_aim: bool = p.aiming and not p.melee_equipped() and p.vehicle == null
	if armed_aim and d < 14.0 and st in [S.WANDER, S.IDLE, S.CLERK] and can_see(pp + Vector3(0, 1.2, 0), 16.0, 0.0):
		var to_me: Vector3 = (global_position - pp).normalized()
		if G.cam and G.cam.forward().dot(to_me) > 0.93:
			aware = 1.0
			if kind == "clerk":
				st = S.COWER
				state_t = 0.0
				hands_up = true
			elif kind == "gang":
				engage(p)
			elif brave < 0.75:
				hands_up = G.rng.randf() < 0.4
				flee_from(pp)
			G.report_crime("threaten", global_position, 0.4, p)


func _move(to: Vector3, sp: float, delta: float) -> void:
	var dir := G.flat(to - global_position)
	var dist := dir.length()
	var tv := Vector3.ZERO
	if sp > 0.0 and dist > 0.25:
		dir = dir / dist
		tv = dir * sp
		face_yaw = atan2(-dir.x, -dir.z)
	velocity.x = move_toward(velocity.x, tv.x, 18.0 * delta)
	velocity.z = move_toward(velocity.z, tv.z, 18.0 * delta)
	if not is_on_floor():
		velocity.y -= 16.0 * delta
	else:
		velocity.y = -0.5
	var before := global_position
	move_and_slide()
	var moved := G.flat(global_position - before).length()
	if sp > 0.5 and moved < sp * delta * 0.25:
		stuck_t += delta
		if stuck_t > 0.6:
			# hop over low obstacles / slide around corners
			var side := Vector3(-dir.z, 0, dir.x) * (1.0 if int(state_t * 2.0) % 2 == 0 else -1.0)
			velocity = side * sp + Vector3(0, 3.0 if stuck_t > 1.2 else 0.0, 0)
			if stuck_t > 2.2:
				stuck_t = 0.0
				node_cur = -1
	else:
		stuck_t = 0.0
	vis.speed = Vector3(velocity.x, 0, velocity.z).length()
	vis.grounded = true
	vis.mode = "foot"
	if global_position.y < G.WATER_LEVEL - 1.0:
		vis.mode = "swim"
		velocity.y = 1.5
	if global_position.y < -20.0:
		queue_free()


func _far_move(delta: float) -> void:
	if manager == null or node_cur < 0:
		return
	var to: Vector3 = goal
	var d := G.flat(to - global_position)
	if d.length() < 1.2:
		_next_node()
		return
	global_position += d.normalized() * walk_speed * delta
	global_position.y = move_toward(global_position.y, to.y, delta)
	face_yaw = atan2(-d.x, -d.z)
	rotation.y = face_yaw


func _next_node() -> void:
	if manager == null:
		return
	var nb: Array = manager.neighbors(node_cur) if node_cur >= 0 else []
	if node_cur < 0 or nb.is_empty():
		node_cur = manager.nearest_node(global_position)
		node_prev = -1
	else:
		var choices: Array = []
		for n in nb:
			if n != node_prev:
				choices.append(n)
		if choices.is_empty():
			choices = nb
		node_prev = node_cur
		node_cur = choices[G.rng.randi() % choices.size()]
	var p: Vector3 = manager.node_pos(node_cur)
	goal = p + Vector3(G.rng.randf_range(-1.1, 1.1), 0, G.rng.randf_range(-1.1, 1.1))
	wait_cross = 0.0


func _wander(delta: float) -> void:
	if manager == null:
		_move(Vector3.ZERO, 0.0, delta)
		return
	if node_cur < 0:
		_next_node()
	if G.dist2(global_position, goal) < 1.3:
		if G.rng.randf() < 0.08:
			st = S.IDLE
			state_t = 0.0
			vis.phone = 1.0 if G.rng.randf() < 0.5 else 0.0
			return
		_next_node()
	# crossing roads: wait for a gap / the pedestrian phase
	var sp := walk_speed
	if node_prev >= 0 and manager.is_crossing(node_prev, node_cur):
		var onr := WorldLayout.on_road(global_position)
		if not onr and G.dist2(global_position, manager.node_pos(node_prev)) < 3.0:
			if not manager.can_cross(node_prev, node_cur):
				wait_cross += delta
				if wait_cross < 14.0:
					sp = 0.0
		elif onr:
			sp = walk_speed * 1.35
	_move(goal, sp, delta)
	# avoid oncoming cars
	if tier == 0 and int(state_t * 5.0) != int((state_t - delta) * 5.0):
		for v in get_tree().get_nodes_in_group("vehicles"):
			var veh := v as Vehicle
			if veh.speed > 4.0:
				var rel := global_position - veh.global_position
				if rel.length() < 7.0 and rel.normalized().dot(veh.linear_velocity.normalized()) > 0.92:
					_sidestep(veh.global_position - veh.global_transform.basis.x * signf(rel.dot(veh.global_transform.basis.x)) * 3.0)
					break


func _flee(delta: float) -> void:
	var away := G.flat(global_position - danger)
	if away.length() < 0.1:
		away = Vector3(randf() - 0.5, 0, randf() - 0.5)
	var dir := away.normalized()
	if stuck_t > 0.3:
		dir = dir.rotated(Vector3.UP, 1.2 * strafe_dir)
	_move(global_position + dir * 6.0, 5.2 + brave, delta)
	vis.sprinting = true
	hands_up = false
	if state_t > 9.0 and away.length() > 38.0:
		st = S.WANDER
		node_cur = -1
		danger = Vector3.ZERO
		vis.sprinting = false
	if state_t > 2.0 and int(state_t) % 3 == 0 and stuck_t > 0.25:
		strafe_dir = -strafe_dir


func _cower(delta: float) -> void:
	_move(Vector3.ZERO, 0.0, delta)
	vis.crouch = move_toward(vis.crouch, 1.0, delta * 5.0)
	hands_up = true
	if kind == "clerk" and G.player and G.player.aiming and state_t > 2.5 and robbed <= 0.0 and G.player.global_position.distance_to(global_position) < 9.0:
		robbed = 150.0
		if G.main.has_node("Interactions"):
			G.main.get_node("Interactions").drop("cash", global_position + Basis(Vector3.UP, face_yaw) * Vector3(0, 1.1, -1.3), {"amount": G.rng.randi_range(250, 900)})
		G.report_crime("robbery", global_position, 2.2, G.player)
		G.say("The clerk hands over the register", Color(1, 0.85, 0.4))
	if state_t > 7.0 and (G.player == null or not G.player.aiming or G.player.global_position.distance_to(global_position) > 14.0):
		vis.crouch = 0.0
		hands_up = false
		st = S.CLERK if kind == "clerk" else S.FLEE
		state_t = 0.0


func _clerk(delta: float) -> void:
	_move(Vector3.ZERO, 0.0, delta)
	robbed = maxf(robbed - delta, 0.0)
	vis.crouch = move_toward(vis.crouch, 0.0, delta * 4.0)
	if G.player and G.player.global_position.distance_to(global_position) < 7.0:
		var to: Vector3 = G.player.global_position - global_position
		face_yaw = atan2(-to.x, -to.z)
		if state_t > 6.0 and vis.action == "":
			state_t = 0.0
			vis.play("wave", 1.2)


func _investigate(delta: float) -> void:
	_move(goal, 3.8, delta)
	vis.aim = move_toward(vis.aim, 0.3, delta * 3.0)
	if G.dist2(global_position, goal) < 3.0 or state_t > 16.0:
		if state_t > 20.0 or G.dist2(global_position, goal) < 3.0 and state_t > 6.0:
			st = S.WANDER
			node_cur = -1
			vis.aim = 0.0
			_show_weapon(false)


func _call(delta: float) -> void:
	_move(Vector3.ZERO, 0.0, delta)
	vis.phone = 1.0
	call_t -= delta
	if call_t <= 0.0:
		vis.phone = 0.0
		if G.wanted:
			G.wanted.witness_report(crime_seen)
		st = S.FLEE
		state_t = 0.0


func witness(info: Dictionary) -> void:
	## Called by the wanted system: this civilian saw a crime and will phone it in.
	if dead or st in [S.DRIVER, S.FIGHT, S.CALL] or ragdoll != null:
		return
	crime_seen = info
	danger = info.pos
	call_t = 3.2 + G.rng.randf() * 2.0
	st = S.CALL
	state_t = 0.0


# ------------------------------------------------------------------ combat
func _fight(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.get("dead") == true:
		target = null
		st = S.WANDER
		node_cur = -1
		vis.aim = 0.0
		_show_weapon(false)
		return
	if is_police and G.is_player(target) and G.wanted and G.wanted.level == 0 and not aggro:
		st = S.WANDER
		node_cur = -1
		vis.aim = 0.0
		_show_weapon(false)
		return
	var tp: Vector3 = target.global_position_now() if target.has_method("global_position_now") else target.global_position
	var aim_at := tp + Vector3(0, 1.15, 0)
	var d := tp.distance_to(global_position)
	var sees := can_see(aim_at, 90.0, -1.0)
	fire_cd -= delta
	if sees:
		last_seen = tp
		lost_t = 0.0
		if is_police and G.is_player(target) and G.wanted:
			G.wanted.spotted(self)
	else:
		lost_t += delta
	var wd: Dictionary = Defs.WEAPONS[weapon] if weapon != "" else Defs.WEAPONS["fists"]
	var melee: bool = wd.type == "melee"
	var to := G.flat(tp - global_position).normalized()
	# arrest attempt at low wanted levels
	if is_police and G.is_player(target) and G.wanted and G.wanted.level <= 2 and not G.wanted.lethal and target.get("vehicle") == null:
		if d < 2.6 and sees:
			arrest_t += delta
			_move(Vector3.ZERO, 0.0, delta)
			face_yaw = atan2(-to.x, -to.z)
			vis.aim = move_toward(vis.aim, 1.0, delta * 6.0)
			vis.aim_pitch = 0.0
			if arrest_t > 1.6 and (target.get("velocity") as Vector3).length() < 2.5:
				target.get_busted()
			return
		arrest_t = maxf(arrest_t - delta, 0.0)
		_move(last_seen, 5.6, delta)
		vis.aim = move_toward(vis.aim, 0.0, delta * 4.0)
		if lost_t > 12.0:
			st = S.INVESTIGATE
			goal = last_seen
			state_t = 0.0
		return
	if melee:
		if d > float(wd.range) * 0.8:
			_move(tp, 5.4, delta)
		else:
			_move(Vector3.ZERO, 0.0, delta)
			face_yaw = atan2(-to.x, -to.z)
			if fire_cd <= 0.0:
				fire_cd = float(wd.rate) * 1.6
				vis.play("swing" if weapon != "" else (["punch_r", "punch_l"][G.rng.randi() % 2]), 0.45)
				Weapons.melee(self, weapon if weapon != "" else "fists", global_position + Vector3(0, 1.0, 0), to, false, 0.7)
		return
	# gunfight
	var want := float(wd.range) * 0.28
	want = clampf(want, 9.0, 32.0)
	if reload_t > 0.0:
		reload_t -= delta
		vis.reload_t = 1.0 - reload_t / 2.0
		if reload_t <= 0.0:
			clip = int(wd.mag)
			vis.reload_t = 0.0
	if not sees:
		in_cover = false
		vis.crouch = move_toward(vis.crouch, 0.0, delta * 4.0)
		_move(last_seen, 5.2, delta)
		vis.aim = move_toward(vis.aim, 0.4, delta * 4.0)
		if lost_t > 14.0:
			st = S.INVESTIGATE
			goal = last_seen
			state_t = 0.0
		return
	# choose where to stand: cover if we have one, otherwise strafe at range
	if cover_pos == null and state_t > 1.0 and int(state_t) % 4 == 0 and think_t <= 0.0:
		cover_pos = _find_cover(tp)
	var move_sp := 0.0
	var move_to := global_position
	if cover_pos != null:
		if G.dist2(global_position, cover_pos) > 0.9:
			move_to = cover_pos
			move_sp = 5.0
			in_cover = false
		else:
			in_cover = true
			if state_t > 14.0 or not G.ray(cover_pos + Vector3(0, 0.6, 0), aim_at, G.L_WORLD | G.L_VEHICLE, [get_rid()]).is_empty() == false:
				pass
	elif d > want * 1.4:
		move_to = tp
		move_sp = 4.6
	elif d < want * 0.45:
		move_to = global_position - to * 4.0
		move_sp = 3.0
	else:
		if int(state_t * 0.5) % 2 == 0:
			var sd := Vector3(-to.z, 0, to.x) * strafe_dir
			move_to = global_position + sd * 3.0
			move_sp = 2.2
		if G.rng.randf() < delta * 0.3:
			strafe_dir = -strafe_dir
	_move(move_to, move_sp, delta)
	face_yaw = atan2(-to.x, -to.z)
	var popping := not in_cover or burst > 0 or fmod(state_t, 3.2) < 1.7
	vis.crouch = move_toward(vis.crouch, 1.0 if (in_cover and not popping) else 0.0, delta * 6.0)
	vis.aim = move_toward(vis.aim, 1.0 if popping else 0.2, delta * 7.0)
	var ev := aim_at - eye()
	vis.aim_pitch = atan2(ev.y, G.flat(ev).length())
	if popping and fire_cd <= 0.0 and reload_t <= 0.0 and vis.aim > 0.85 and move_sp < 4.0:
		if clip <= 0:
			reload_t = 2.0
			Sfx.play("reload", global_position, -8.0)
			return
		if burst <= 0:
			burst = 1 if not wd.get("auto", false) else G.rng.randi_range(3, 6)
		burst -= 1
		clip -= 1
		fire_cd = float(wd.rate) + (0.0 if burst > 0 else randf_range(0.5, 1.3))
		var tv: Vector3 = target.get("velocity") if target.get("velocity") != null else Vector3.ZERO
		if target.get("vehicle") != null and target.get("vehicle") is Vehicle:
			tv = (target.get("vehicle") as Vehicle).linear_velocity
		var acc := accuracy * clampf(1.25 - d / 60.0, 0.35, 1.0) * clampf(1.0 - tv.length() / 30.0, 0.4, 1.0)
		var miss := (1.0 - acc) * 0.11
		var dir := (aim_at + tv * 0.05 - eye()).normalized()
		dir = (dir + Vector3(randf_range(-miss, miss), randf_range(-miss, miss), randf_range(-miss, miss))).normalized()
		var excl: Array = [get_rid()]
		var muzzle := Weapons.muzzle_of(weapon_model) if weapon_model else eye() + dir * 0.5
		Weapons.fire(self, weapon, eye() + Vector3(0, -0.1, 0), dir, {"exclude": excl, "muzzle": muzzle, "dmg_mul": 0.55, "spread_mul": 0.6})
		vis.recoil = 1.0


func _find_cover(threat: Vector3):
	## Samples nearby spots and returns one that blocks the threat at crouch height.
	var best = null
	var bs := 1e9
	for i in 10:
		var a := i * TAU / 10.0
		for r in [4.0, 8.0]:
			var p := global_position + Vector3(cos(a) * r, 0, sin(a) * r)
			var h := G.ray(p + Vector3(0, 2.0, 0), p - Vector3(0, 2.0, 0), G.L_WORLD)
			if h.is_empty():
				continue
			p = h.position
			if absf(p.y - global_position.y) > 1.0:
				continue
			var low_blocked := not G.ray(p + Vector3(0, 0.6, 0), threat + Vector3(0, 1.0, 0), G.L_WORLD | G.L_VEHICLE, [get_rid()]).is_empty()
			var high_clear := G.ray(p + Vector3(0, 1.65, 0), threat + Vector3(0, 1.2, 0), G.L_WORLD | G.L_VEHICLE, [get_rid()]).is_empty()
			if low_blocked and high_clear:
				var sc := p.distance_to(global_position) + absf(p.distance_to(threat) - 16.0) * 0.4
				if sc < bs:
					bs = sc
					best = p
	return best
