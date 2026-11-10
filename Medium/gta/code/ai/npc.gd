extends CharacterBody3D
## Pedestrians, police, tactical officers, gang members, shop staff and service crews.

const Humanoid := preload("res://gta/code/player/humanoid.gd")
const Weapons := preload("res://gta/code/weapons/weapons.gd")

var role := "ped"          # ped, cop, swat, gang, clerk, medic, fire
var model
var weapons
var health := 100.0
var state := "wander"
var state_t := 0.0
var brave := 0.3
var node_i := -1
var prev_i := -1
var goal := Vector3.ZERO
var has_goal := false
var goal_cb = null
var threat := Vector3.ZERO
var target = null
var alerted := false
var walk_speed := 1.5
var dead := false
var cash := 0
var home := Vector3.ZERO
var vehicle_home = null
var report_crime := {}
var lethal := false
var _path: PackedVector3Array = PackedVector3Array()
var _path_t := 0.0
var _think := 0.0
var _burst := 0
var _strafe := 0.0
var _stuck := 0.0
var _down_v := Vector3.ZERO
var _tick := 0
var _see_t := 0.0
var sees_player := false
var _arrest_t := 0.0
var _crouch := false
var robbed := false
var leaving := false


func setup(r: String, look: Dictionary = {}) -> void:
	role = r
	collision_layer = G.L_CHAR
	collision_mask = G.L_WORLD | G.L_VEH | G.L_PROP
	floor_snap_length = 0.3
	var cs = CollisionShape3D.new()
	var sh = CapsuleShape3D.new()
	sh.radius = 0.32
	sh.height = 1.8
	cs.shape = sh
	cs.position.y = 0.9
	add_child(cs)
	model = Node3D.new()
	model.set_script(Humanoid)
	model.look = look if not look.is_empty() else Humanoid.random_look(r)
	add_child(model)
	brave = G.rng.randf()
	walk_speed = G.rng.randf_range(1.3, 1.9)
	cash = G.rng.randi_range(8, 90)
	add_to_group("npcs")
	if role in ["cop", "swat", "gang"]:
		weapons = Node.new()
		weapons.set_script(Weapons)
		weapons.body = self
		weapons.model = model
		weapons.infinite = true
		add_child(weapons)
		match role:
			"cop":
				health = 120.0
				weapons.inaccuracy = 5.5
				weapons.dmg_mult = 0.45
				weapons.give("pistol")
				weapons.select("pistol")
				add_to_group("cops")
			"swat":
				health = 220.0
				weapons.inaccuracy = 4.0
				weapons.dmg_mult = 0.5
				var w: String = ["carbine", "smg", "shotgun"][G.rng.randi() % 3]
				weapons.give(w)
				weapons.select(w)
				add_to_group("cops")
			"gang":
				health = 110.0
				weapons.inaccuracy = 7.0
				weapons.dmg_mult = 0.45
				var w2: String = ["pistol", "pistol", "smg", "bat"][G.rng.randi() % 4]
				weapons.give(w2)
				weapons.select("fists")
				set_meta("gun", w2)
				brave = 1.0
	if role == "clerk":
		state = "idle"


func set_state(s: String) -> void:
	state = s
	state_t = 0.0
	_crouch = false


func is_unaware() -> bool:
	return not alerted and state in ["wander", "idle", "goto", "phone"]


func is_head(p: Vector3) -> bool:
	return p.y - global_position.y > 1.5


func goto(p: Vector3, cb = null, run := false) -> void:
	goal = p
	has_goal = true
	goal_cb = cb
	set_state("goto")
	set_meta("run", run)


# ------------------------------------------------------------------ perception
func can_see(pos: Vector3, rng_m: float, fov_dot := 0.1) -> bool:
	var eye = global_position + Vector3(0, 1.6, 0)
	var to = pos - eye
	var d = to.length()
	if d > rng_m:
		return false
	var fwd = -global_basis.z
	if d > 5.0 and fwd.dot(to.normalized()) < fov_dot:
		return false
	return G.los(eye, pos)


func sees(body, rng_m: float) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var p: Vector3 = body.global_position + Vector3(0, 1.3, 0)
	return can_see(p, rng_m)


# ------------------------------------------------------------------ damage
func damage(amount: float, from = null, pos := Vector3.ZERO, kind := "bullet") -> void:
	if dead:
		return
	var a = amount
	if kind == "bullet" and is_head(pos):
		a *= 3.0
	if role == "swat" and kind in ["bullet", "explosion"]:
		a *= 0.55
	health -= a
	alerted = true
	var by_player: bool = from != null and from == G.player
	if by_player and G.wanted:
		if role in ["cop", "swat"]:
			G.wanted.crime("assault_cop", global_position, 2.0, true)
		else:
			G.wanted.crime("assault", global_position, 0.6)
	if health <= 0.0:
		die(from, kind, pos)
		return
	model.play("hit", 0.25)
	if kind in ["melee_heavy", "explosion", "vehicle"] or (kind == "melee" and G.rng.randf() < 0.25):
		knockdown(((global_position - pos) * Vector3(1, 0, 1)).normalized() * (4.0 if kind != "explosion" else 8.0) + Vector3(0, 3.5, 0))
		return
	if from != null and is_instance_valid(from) and from is Node3D:
		_react_attack(from)


func _react_attack(from) -> void:
	threat = from.global_position
	match role:
		"ped", "clerk", "medic", "fire":
			if brave > 0.75 and from is CharacterBody3D and state != "flee":
				target = from
				set_state("fight")
			else:
				flee(threat)
		"gang":
			target = from
			_arm()
			set_state("combat")
			if G.pop:
				G.pop.rally_gang(self, from)
		"cop", "swat":
			target = from
			lethal = true
			set_state("combat")
	if G.pop:
		G.pop.panic(global_position, 22.0, from, self)


func _arm() -> void:
	if has_meta("gun") and weapons.cur == "fists":
		weapons.select(get_meta("gun"))


func hit_by_vehicle(veh, vel: Vector3) -> void:
	if dead or state == "down" and state_t < 0.5:
		return
	var s = vel.length()
	if s < 3.5:
		return
	var by_player: bool = veh.driver != null and veh.driver == G.player
	health -= (s - 3.0) * 7.0
	alerted = true
	if by_player and G.wanted:
		G.wanted.crime("hit_and_run", global_position, 1.0 if role not in ["cop", "swat"] else 2.0, role in ["cop", "swat"])
	G.audio.play3d("thud", global_position, -2.0)
	if health <= 0.0:
		die(G.player if by_player else null, "vehicle", veh.global_position)
		_down_v = vel * 0.8 + Vector3(0, 4.0, 0)
		velocity = _down_v
	else:
		knockdown(vel * 0.8 + Vector3(0, 4.0, 0))
		if G.pop:
			G.pop.panic(global_position, 16.0, veh, self)


func knockdown(v: Vector3) -> void:
	if dead:
		return
	set_state("down")
	velocity = v
	model.state = "limp"


func thrown_from_vehicle(veh, by) -> void:
	alerted = true
	var side: Vector3 = (global_position - veh.global_position).normalized()
	knockdown(side * 3.0 + Vector3(0, 2.5, 0))
	threat = veh.global_position
	if role in ["cop", "swat"]:
		target = by
		lethal = true
	elif brave > 0.7:
		target = by
		set_meta("after_down", "fight")
	G.audio.play3d("scream", global_position, -8.0, G.rng.randf_range(0.8, 1.2))


func die(from = null, kind := "bullet", pos := Vector3.ZERO) -> void:
	if dead:
		return
	dead = true
	health = 0.0
	set_state("dead")
	collision_layer = 0
	collision_mask = G.L_WORLD
	model.state = "dead"
	model.aiming = false
	var away = ((global_position - pos) * Vector3(1, 0, 1)).normalized()
	velocity = away * (2.0 if kind == "bullet" else 5.0) + Vector3(0, 2.0 if kind == "bullet" else 4.0, 0)
	var by_player: bool = from != null and from == G.player
	if by_player:
		G.stats.kills += 1
		if G.wanted:
			if role in ["cop", "swat"]:
				G.wanted.crime("kill_cop", global_position, 3.0, true)
			else:
				G.wanted.crime("murder", global_position, 1.2)
	if G.pop:
		G.pop.panic(global_position, 28.0, from, self)
		G.pop.on_death(self, by_player)
	if G.extras:
		G.extras.drop_loot(self)
	remove_from_group("cops")


func flee(from: Vector3, t := 12.0) -> void:
	threat = from
	if state != "flee":
		if G.rng.randf() < 0.4:
			G.audio.play3d("scream", global_position, -10.0, G.rng.randf_range(0.85, 1.3))
	set_state("flee")
	set_meta("flee_t", t)


# ------------------------------------------------------------------ update
func _physics_process(dt: float) -> void:
	_tick += 1
	var pp = G.player_pos()
	var pd = global_position.distance_to(pp)
	model.lod = pd > 75.0
	var step = dt
	if pd > 45.0 and state not in ["down", "dead"]:
		if (_tick + get_instance_id()) % 4 != 0:
			return
		step = dt * 4.0
	state_t += step
	if weapons:
		weapons.update(step)
	var want = Vector3.ZERO
	var face = null
	model.aiming = false
	match state:
		"wander":
			want = _wander(step)
		"idle":
			if role == "clerk":
				_clerk(step)
		"goto":
			var d = G.flat(goal - global_position)
			if d.length() < 1.0:
				has_goal = false
				set_state("idle")
				if goal_cb != null:
					var cb = goal_cb
					goal_cb = null
					cb.call()
			else:
				want = _steer_to(goal, 4.6 if get_meta("run", false) else walk_speed, step)
		"flee":
			var away = G.flat(global_position - threat)
			if away.length() < 0.1:
				away = Vector3(1, 0, 0)
			want = away.normalized() * 5.2
			if is_on_wall():
				want = want.rotated(Vector3.UP, 1.2 if (_tick / 40) % 2 == 0 else -1.2)
			if state_t > get_meta("flee_t", 12.0) and global_position.distance_to(threat) > 30.0:
				alerted = false
				_resume()
		"cower":
			if state_t > 8.0:
				_resume()
		"phone":
			face = threat
			if state_t > 4.5:
				if G.wanted and not report_crime.is_empty():
					G.wanted.witness_report(report_crime)
				report_crime = {}
				flee(threat, 8.0)
		"fight":
			want = _fight(step)
			if target and is_instance_valid(target):
				face = target.global_position
		"combat":
			want = _combat(step)
			if target and is_instance_valid(target):
				face = target.global_position
		"arrest":
			want = _arrest(step)
			if target and is_instance_valid(target):
				face = target.global_position
		"search":
			if not has_goal or G.flat(goal - global_position).length() < 1.5 or state_t > 6.0:
				state_t = 0.0
				var c: Vector3 = G.wanted.last_known if G.wanted else global_position
				goal = c + Vector3(G.rng.randf_range(-18, 18), 0, G.rng.randf_range(-18, 18))
				has_goal = true
			want = _steer_to(goal, 2.6, step)
		"down":
			velocity.y -= 14.0 * step
			if is_on_floor():
				velocity.x = move_toward(velocity.x, 0, step * 9.0)
				velocity.z = move_toward(velocity.z, 0, step * 9.0)
			move_and_slide()
			if state_t > 3.0 and is_on_floor():
				var nxt: String = get_meta("after_down", "")
				if has_meta("after_down"):
					remove_meta("after_down")
				if role in ["cop", "swat"] or (role == "gang" and target):
					set_state("combat")
				elif nxt == "fight" and target:
					set_state("fight")
				else:
					flee(threat)
			_anim(step)
			return
		"dead":
			velocity.y -= 14.0 * step
			if is_on_floor():
				velocity.x = move_toward(velocity.x, 0, step * 8.0)
				velocity.z = move_toward(velocity.z, 0, step * 8.0)
			if state_t < 2.5:
				move_and_slide()
			if state_t > 45.0 and pd > 25.0 or state_t > 90.0:
				queue_free()
			_anim(step)
			return
	# locomotion
	velocity.x = move_toward(velocity.x, want.x, step * 14.0)
	velocity.z = move_toward(velocity.z, want.z, step * 14.0)
	if not is_on_floor():
		velocity.y -= 14.0 * step
	else:
		velocity.y = -0.5
	if step > dt:
		global_position += Vector3(velocity.x, 0, velocity.z) * (step - dt)
	move_and_slide()
	if global_position.y < G.WATER_Y - 1.0 and G.world.is_sea(global_position.x, global_position.z):
		die(null, "drown", global_position)
	var fdir = want
	if face != null:
		fdir = G.flat(face - global_position)
	if fdir.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(-fdir.x, -fdir.z), clamp(step * 9.0, 0.0, 1.0))
	if want.length() > 0.5 and G.flat(velocity).length() < 0.2:
		_stuck += step
		if _stuck > 1.0 and is_on_floor():
			velocity.y = 5.0
			_stuck = 0.0
	else:
		_stuck = 0.0
	_anim(step)


func _resume() -> void:
	target = null
	if role == "clerk":
		goto(home)
	elif role in ["cop", "swat"]:
		set_state("search" if G.wanted and G.wanted.stars > 0 else "wander")
	else:
		set_state("wander")


func _anim(_dt: float) -> void:
	if model.lod:
		return
	var m = model
	m.speed = G.flat(velocity).length()
	match state:
		"down":
			m.state = "limp"
			m.rotation.x = lerp_angle(m.rotation.x, -PI / 2, 0.2)
			m.position.y = 0.25
		"dead":
			m.state = "dead"
			m.rotation.x = lerp_angle(m.rotation.x, -PI / 2, 0.15)
			m.position.y = 0.22
		"cower":
			m.state = "cower"
		"phone":
			m.state = "phone"
		_:
			m.rotation.x = lerp_angle(m.rotation.x, 0.0, 0.2)
			m.position.y = 0.0
			if role == "clerk" and robbed and state == "idle":
				m.state = "handsup"
			elif _crouch:
				m.state = "crouch"
			else:
				m.state = "move" if m.speed > 0.3 else "idle"


# ------------------------------------------------------------------ behaviours
func _steer_to(p: Vector3, sp: float, step: float) -> Vector3:
	var tgt = p
	_path_t -= step
	if G.world.nav_ready and role != "ped":
		if _path_t <= 0.0:
			_path_t = 0.8
			_path = G.world.nav_path(global_position, p)
		if _path.size() > 1:
			var k = 1
			while k < _path.size() - 1 and G.flat(_path[k] - global_position).length() < 1.0:
				k += 1
			tgt = _path[k]
	var d = G.flat(tgt - global_position)
	if d.length() < 0.05:
		return Vector3.ZERO
	return d.normalized() * sp


func _wander(step: float) -> Vector3:
	var W = G.world
	if node_i < 0:
		var bd = 1e9
		for i in W.ped_nodes.size():
			var d: float = W.ped_nodes[i].distance_squared_to(global_position)
			if d < bd:
				bd = d
				node_i = i
		prev_i = node_i
	var tp: Vector3 = W.ped_nodes[node_i] + Vector3(sin(get_instance_id() * 0.37) * 0.9, 0, cos(get_instance_id() * 0.73) * 0.9)
	var d2 = G.flat(tp - global_position)
	if d2.length() < 1.3:
		var opts: Array = W.ped_links[node_i]
		var cands = []
		for o in opts:
			if o != prev_i:
				cands.append(o)
		if cands.is_empty():
			cands = opts.duplicate()
		prev_i = node_i
		node_i = cands[G.rng.randi() % cands.size()]
		return Vector3.ZERO
	# wait for traffic before stepping onto the road
	if W.on_road(global_position.x + d2.normalized().x * 2.0, global_position.z + d2.normalized().z * 2.0) and not W.on_road(global_position.x, global_position.z):
		_think -= step
		if _think <= 0.0:
			_think = 0.4
			var wait = false
			for v in get_tree().get_nodes_in_group("vehicles"):
				if abs(v.speed) > 3.0 and v.global_position.distance_to(global_position) < 16.0:
					var tov: Vector3 = global_position - v.global_position
					if tov.normalized().dot(v.linear_velocity.normalized()) > 0.5:
						wait = true
						break
			set_meta("wait", wait)
		if get_meta("wait", false):
			return Vector3.ZERO
	return d2.normalized() * walk_speed


func _fight(_step: float) -> Vector3:
	if target == null or not is_instance_valid(target) or target.get("health") == null or target.health <= 0.0 or state_t > 25.0:
		_resume()
		return Vector3.ZERO
	var d = G.flat(target.global_position - global_position)
	if d.length() > 30.0:
		_resume()
		return Vector3.ZERO
	if d.length() > 1.5:
		return d.normalized() * 4.4
	if weapons == null:
		_think -= _step
		if _think <= 0.0:
			_think = 0.9
			model.play("punch", 0.32)
			if target.has_method("damage"):
				target.damage(8.0, self, global_position + Vector3(0, 1.2, 0), "melee")
			G.audio.play3d("punch", global_position, -6.0)
	else:
		weapons.try_fire(Vector3.ZERO)
	return Vector3.ZERO


func _combat(step: float) -> Vector3:
	if target == null or not is_instance_valid(target) or target.get("health") == null or target.health <= 0.0:
		_resume()
		return Vector3.ZERO
	var tp: Vector3 = target.global_position
	var body = target
	if target == G.player and G.player.vehicle:
		tp = G.player.vehicle.global_position
		body = G.player.vehicle
	var d = G.flat(tp - global_position)
	var dist = d.length()
	var vis = can_see(tp + Vector3(0, 1.2, 0), 90.0, -1.0)
	if role in ["cop", "swat"] and G.wanted:
		if G.wanted.stars <= 0:
			set_state("wander" if not leaving else "goto")
			return Vector3.ZERO
		if not vis and dist > 12.0 and G.wanted.state == "search":
			set_state("search")
			has_goal = false
			return Vector3.ZERO
		if not lethal and not G.wanted.lethal:
			set_state("arrest")
			return Vector3.ZERO
	if weapons and weapons.d().cls == "melee":
		if dist > 1.6:
			return d.normalized() * 4.6
		weapons.try_fire(Vector3.ZERO)
		return Vector3.ZERO
	var want = Vector3.ZERO
	var ideal = 14.0 if role != "swat" else 18.0
	_strafe -= step
	if _strafe <= 0.0:
		_strafe = G.rng.randf_range(1.2, 3.0)
		set_meta("sdir", G.rng.randf_range(-1.0, 1.0))
		_crouch = G.rng.randf() < 0.3 and dist > 6.0
		# approximate cover: tuck behind our own vehicle when under fire
		if vehicle_home and is_instance_valid(vehicle_home) and vehicle_home.global_position.distance_to(global_position) < 14.0 and G.rng.randf() < 0.5:
			var behind: Vector3 = vehicle_home.global_position + G.flat(vehicle_home.global_position - tp).normalized() * 2.2
			set_meta("cover", behind)
		else:
			if has_meta("cover"):
				remove_meta("cover")
	if has_meta("cover") and weapons.reload_t > 0.0:
		var cp: Vector3 = get_meta("cover")
		if G.flat(cp - global_position).length() > 0.8:
			want = G.flat(cp - global_position).normalized() * 4.0
		_crouch = true
	elif not vis or dist > ideal + 12.0:
		want = _steer_to(tp, 4.6, step)
	elif dist < ideal - 6.0:
		want = -d.normalized() * 2.0
	else:
		want = d.normalized().cross(Vector3.UP) * float(get_meta("sdir", 0.0)) * 1.8
	if vis and dist < 70.0:
		model.aiming = true
		model.aim_pitch = clamp(atan2(tp.y + 1.1 - (global_position.y + 1.4), max(1.0, dist)), -0.9, 0.9)
		_think -= step
		if _think <= 0.0:
			var aim: Vector3 = tp + Vector3(0, 1.0, 0)
			if body is RigidBody3D:
				aim += body.linear_velocity * 0.08
			if weapons.try_fire(aim, [vehicle_home.get_rid()] if vehicle_home and is_instance_valid(vehicle_home) else []):
				_burst += 1
				if _burst >= (5 if weapons.d().get("auto", false) else 2):
					_burst = 0
					_think = G.rng.randf_range(0.7, 1.6)
	return want


func _arrest(step: float) -> Vector3:
	if target == null or not is_instance_valid(target) or G.wanted == null or G.wanted.stars <= 0:
		_resume()
		return Vector3.ZERO
	if lethal or G.wanted.lethal:
		set_state("combat")
		return Vector3.ZERO
	var tp: Vector3 = target.global_position
	var d = G.flat(tp - global_position)
	if not can_see(tp + Vector3(0, 1.2, 0), 80.0, -1.0) and d.length() > 10.0 and G.wanted.state == "search":
		set_state("search")
		has_goal = false
		return Vector3.ZERO
	model.aiming = d.length() < 12.0
	if d.length() > 2.0:
		_arrest_t = 0.0
		return _steer_to(tp, 5.4, step)
	if G.wanted.try_bust(self, step):
		_arrest_t += step
	return Vector3.ZERO


func _clerk(step: float) -> void:
	var p = G.player
	if p == null or robbed:
		if robbed and state_t > 40.0:
			robbed = false
		return
	var d = global_position.distance_to(p.global_position)
	if d < 9.0 and p.aiming and p.weapons.is_gun() and sees(p, 12.0):
		var to: Vector3 = (global_position - p.global_position).normalized()
		if (-p.global_basis.z).dot(to) > 0.8:
			_see_t += step
			model.state = "handsup"
			if G.hud:
				G.hud.hint("Keep aiming to rob the till…")
			if _see_t > 3.0:
				_see_t = 0.0
				robbed = true
				state_t = 0.0
				var amount = G.rng.randi_range(180, 520)
				if G.extras:
					G.extras.spawn_pickup("cash", global_position + (-global_basis.z) * 1.0 + Vector3(0, 0.3, 0), amount)
				if G.wanted:
					G.wanted.crime("robbery", global_position, 1.6, true)
				G.notify("Store robbed!", 2.5)
			return
	_see_t = 0.0
