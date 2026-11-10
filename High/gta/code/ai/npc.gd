class_name Npc
extends CharacterBody3D
## Pedestrians, police, tactical units, gang members, shop staff and medics.
## One class, data-driven by `kind`; perception + small FSM; simulation tier set by PedManager.

enum S {WANDER, IDLE, FLEE, COWER, CALL, COMBAT, INVESTIGATE, STAND, GOTO, DOWN, DEAD, SURRENDER}

static var nav_map: RID
static var nav_ready := false

var kind := "civ"
var state: int = S.WANDER
var rig: CharRig
var look: Dictionary = {}
var health := 100.0
var dead := false
var down_time := 0.0
var in_vehicle := false
var tier := 0
var weapon: WeaponDef = null
var mag := 0
var accuracy := 0.35
var courage := 0.0
var target = null
var last_seen := Vector3.ZERO
var has_los := false
var alerted := false
var home := Vector3.ZERO
var home_yaw := 0.0
var persistent := false
var squad_vehicle = null
var witness_crime := ""
var cash := 0

var _think := 0.0
var _state_t := 0.0
var _fire_cd := 0.0
var _burst := 0
var _reload := 0.0
var _path: PackedVector3Array = PackedVector3Array()
var _path_i := 0
var _repath := 0.0
var _goal := Vector3.ZERO
var _walk_from := -1
var _walk_to := -1
var _walk_off := Vector3.ZERO
var _wait := 0.0
var _speed := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _cover_t := 0.0
var _in_cover := false
var _strafe := 1.0
var _frame := 0
var _body_t := 0.0
var _threat := Vector3.ZERO
var _melee_cd := 0.0
var _voice_cd := 0.0
var _aim_at_me_t := 0.0
var _robbed := false
var _seen_player_t := 0.0
var _get_up_state := S.FLEE


static func spawn(p_kind: String, pos: Vector3, p_look: Dictionary = {}) -> Npc:
	var n := Npc.new()
	n.kind = p_kind
	n.look = p_look
	Game.world.npc_root.add_child(n)
	n.global_position = pos
	n.home = pos
	return n


func _ready() -> void:
	collision_layer = Game.L_CHAR
	collision_mask = Game.L_WORLD | Game.L_VEHICLE | Game.L_PROP | Game.L_SOFT
	floor_snap_length = 0.35
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	col.shape = cap
	col.position.y = 0.88
	add_child(col)
	var r := Game.rng
	if look.is_empty():
		match kind:
			"cop":
				look = Data.look_cop(r)
			"swat":
				look = Data.look_cop(r, true)
			"gang":
				look = Data.look_gang(r)
			"clerk":
				look = Data.look_clerk(r)
			"medic":
				look = Data.look_medic(r)
			_:
				look = Data.random_civilian(r)
	rig = CharRig.new()
	add_child(rig)
	rig.setup(look, true)
	rig.phase = r.randf() * TAU
	cash = r.randi_range(4, 60)
	match kind:
		"cop":
			health = 130.0
			set_weapon("pistol")
			accuracy = 0.32
			courage = 1.0
			state = S.IDLE
		"swat":
			health = 220.0
			set_weapon("carbine")
			accuracy = 0.42
			courage = 1.0
			state = S.IDLE
		"gang":
			health = 110.0
			set_weapon(["pistol", "smg", "bat", "pistol"][r.randi() % 4])
			accuracy = 0.28
			courage = 1.0
			state = S.IDLE
			cash = r.randi_range(40, 220)
		"clerk":
			state = S.STAND
			persistent = true
			cash = r.randi_range(150, 420)
		"medic":
			state = S.GOTO
			courage = 0.0
		_:
			courage = r.randf()
			if courage > 0.93:
				set_weapon("pistol")
				accuracy = 0.2
			if r.randf() < 0.12:
				rig.phone = 1.0
	Game.npcs.append(self)
	Game.noise_event.connect(_on_noise)
	tree_exiting.connect(_on_exit)
	_think = r.randf() * 0.3
	_strafe = 1.0 if r.randf() < 0.5 else -1.0
	_last_pos = global_position


func _on_exit() -> void:
	Game.npcs.erase(self)
	if Game.noise_event.is_connected(_on_noise):
		Game.noise_event.disconnect(_on_noise)


func set_weapon(id: String) -> void:
	weapon = Data.weapons[id]
	mag = maxi(weapon.mag, 1)
	if state == S.COMBAT:
		rig.set_weapon(weapon)


func is_law() -> bool:
	return kind == "cop" or kind == "swat"


func is_alerted() -> bool:
	return alerted or state in [S.COMBAT, S.FLEE, S.INVESTIGATE, S.CALL, S.COWER]


func eye() -> Vector3:
	return global_position + Vector3.UP * (1.0 if rig.crouch > 0.5 else 1.6)


# ------------------------------------------------------------------ perception
func can_see_player(max_dist: float = 45.0) -> bool:
	var p = Game.player
	if p == null or not p.alive():
		return false
	var c: Vector3 = p.center()
	var d := eye().distance_to(c)
	var rng: float = max_dist * p.visibility()
	if d > rng:
		return false
	if not alerted and d > 5.0:
		var to := (c - global_position)
		to.y = 0.0
		if (-global_basis.z).dot(to.normalized()) < 0.2:
			return false
	var ex: Array = [self, p]
	if p.in_vehicle():
		ex.append(p.vehicle)
	return Game.ray(eye(), c, Game.L_WORLD | Game.L_VEHICLE, ex).is_empty()


func _on_noise(pos: Vector3, radius: float, nk: String) -> void:
	if dead or down_time > 0.0:
		return
	var d := global_position.distance_to(pos)
	if d > radius:
		return
	match nk:
		"gunshot", "explosion":
			if is_law():
				if state != S.COMBAT:
					investigate(pos)
			elif kind == "gang":
				alerted = true
				if Game.player and state != S.COMBAT and d < 40.0:
					engage(Game.player)
			elif kind == "clerk":
				if d < 14.0:
					state = S.SURRENDER
					_state_t = 0.0
			elif kind == "medic":
				pass
			else:
				if state in [S.WANDER, S.IDLE]:
					_threat = pos
					if d < 9.0 and Game.rng.randf() < 0.3:
						_set_state(S.COWER)
					else:
						_set_state(S.FLEE)
					_scream()
		"steps":
			if (is_law() or kind == "gang") and state in [S.IDLE, S.INVESTIGATE] and Game.player:
				alerted = true
				_face(pos, 1.0)
		"horn":
			if state == S.WANDER and d < 9.0:
				_wait = 0.0
				velocity += (global_position - pos).normalized() * 2.0
		"fight":
			if kind == "civ" and state == S.WANDER and Game.rng.randf() < 0.5:
				_threat = pos
				_set_state(S.FLEE)


func _scream() -> void:
	if _voice_cd > 0.0:
		return
	_voice_cd = 4.0
	Sfx.play3d("scream_f" if look.get("gender", "male") == "female" else "scream_m", global_position, -7.0, Game.rng.randf_range(0.9, 1.15), 45.0)


func _set_state(s: int) -> void:
	state = s
	_state_t = 0.0
	_path = PackedVector3Array()
	rig.cower = 0.0
	rig.hands_up = 0.0
	rig.crouch = 0.0
	if s != S.CALL:
		rig.phone = 0.0
	if s == S.COMBAT and weapon:
		rig.set_weapon(weapon)


func engage(t) -> void:
	if dead:
		return
	target = t
	alerted = true
	if state != S.COMBAT:
		_set_state(S.COMBAT)
	if t != null and is_instance_valid(t):
		last_seen = t.global_position


func investigate(pos: Vector3) -> void:
	if dead or state == S.COMBAT:
		return
	alerted = true
	last_seen = pos
	if state != S.INVESTIGATE:
		_set_state(S.INVESTIGATE)
	if weapon:
		rig.set_weapon(weapon)


func start_witness(crime: String) -> void:
	if dead or kind != "civ" or state == S.CALL:
		return
	witness_crime = crime
	_set_state(S.CALL)
	rig.phone = 1.0


# ------------------------------------------------------------------ damage
func damage(amount: float, from_pos: Vector3 = Vector3.ZERO, attacker = null, dk: String = "bullet", _headshot: bool = false) -> void:
	if dead:
		return
	health -= amount
	rig.hit_t = 1.0
	alerted = true
	var by_player: bool = attacker != null and attacker == Game.player
	if by_player and Game.hud:
		Game.hud.hit_marker(health <= 0.0)
	if health <= 0.0:
		_die(attacker, dk)
		return
	if _voice_cd <= 0.0 and dk != "melee_silent":
		_voice_cd = 1.5
		Sfx.play3d("pain_f" if look.get("gender", "male") == "female" else "pain_m", global_position, -6.0, Game.rng.randf_range(0.9, 1.15), 35.0)
	if by_player:
		if is_law():
			Wanted.crime("attack_cop", global_position)
			engage(attacker)
		elif kind == "gang":
			engage(attacker)
			for n in Game.npcs:
				if n != self and is_instance_valid(n) and n.kind == "gang" and n.global_position.distance_to(global_position) < 40.0:
					n.engage(attacker)
		elif kind == "civ":
			Wanted.crime("assault" if dk == "melee" else "shoot_ped", global_position)
			_threat = from_pos
			if (courage > 0.72 or weapon != null) and dk != "explosion":
				engage(attacker)
			else:
				_set_state(S.FLEE)
				_scream()
		else:
			Wanted.crime("assault", global_position)
			_threat = from_pos
			_set_state(S.FLEE)
	elif attacker != null and attacker is Npc and state != S.COMBAT and courage > 0.5:
		engage(attacker)


func knockdown(impulse: Vector3, attacker = null) -> void:
	if dead:
		velocity = impulse
		return
	down_time = Game.rng.randf_range(2.2, 3.8)
	velocity = impulse
	collision_layer = 0
	rig.set_weapon(null)
	if state != S.DOWN:
		_get_up_state = S.COMBAT if (is_law() or kind == "gang" or (courage > 0.8 and attacker == Game.player)) else S.FLEE
		if attacker != null and is_instance_valid(attacker):
			target = attacker
			_threat = attacker.global_position
	state = S.DOWN


func _die(attacker, dk: String) -> void:
	dead = true
	state = S.DEAD
	collision_layer = 0
	rig.set_weapon(null)
	if velocity.length() < 1.0:
		velocity = Vector3(Game.rng.randf_range(-1, 1), 1.5, Game.rng.randf_range(-1, 1))
	_body_t = 0.0
	var by_player: bool = attacker != null and attacker == Game.player
	if by_player:
		Game.stats.kills += 1
		if is_law():
			Wanted.crime("kill_cop", global_position)
		elif dk == "melee_silent":
			Wanted.crime("kill_silent", global_position)
		elif kind == "gang":
			Wanted.crime("kill_gang", global_position)
		else:
			Wanted.crime("kill_ped", global_position)
	if Game.world:
		if kind != "medic" and Game.world.pickups:
			if cash > 0:
				Game.world.pickups.drop("cash", global_position + Vector3(Game.rng.randf_range(-0.6, 0.6), 0.2, Game.rng.randf_range(-0.6, 0.6)), cash)
			if weapon != null and weapon.kind != "melee" and Game.rng.randf() < 0.6:
				Game.world.pickups.drop("ammo", global_position + Vector3(0.5, 0.2, 0.3), 0, weapon.id)
		if Game.world.emergency and not is_law():
			Game.world.emergency.report_body(global_position)
	if Game.peds:
		Game.peds.on_npc_died(self)


# ------------------------------------------------------------------ update
func _physics_process(delta: float) -> void:
	_frame += 1
	_voice_cd = maxf(0.0, _voice_cd - delta)
	if dead or state == S.DOWN:
		_down(delta)
		return
	if tier >= 2:
		if _frame % 4 != 0:
			return
		delta *= 4.0
	_state_t += delta
	_fire_cd -= delta
	_melee_cd -= delta
	_think -= delta
	if _think <= 0.0:
		_think = 0.2 if tier == 0 else 0.5
		_do_think()
	var want_vel := Vector3.ZERO
	match state:
		S.WANDER:
			want_vel = _wander(delta)
		S.FLEE:
			want_vel = _follow_path(5.6)
		S.COMBAT:
			want_vel = _combat_move(delta)
		S.INVESTIGATE:
			want_vel = _follow_path(4.6 if global_position.distance_to(last_seen) > 12.0 else 2.0)
		S.GOTO:
			want_vel = _follow_path(4.8)
		S.CALL, S.COWER, S.STAND, S.IDLE, S.SURRENDER:
			want_vel = Vector3.ZERO
	if tier >= 2:
		global_position += want_vel * delta
		_speed = want_vel.length()
	else:
		var hv := Vector3(velocity.x, 0, velocity.z).move_toward(want_vel, 24.0 * delta)
		velocity.x = hv.x
		velocity.z = hv.z
		if is_on_floor():
			velocity.y = -1.0
		else:
			velocity.y -= 22.0 * delta
		move_and_slide()
		_speed = hv.length()
		if global_position.y < Game.WATER_Y - 1.0:
			velocity.y = 2.0
	if _speed > 0.3 and state != S.COMBAT:
		_face(global_position + want_vel, delta * 8.0)
	# animation
	rig.speed = _speed
	rig.phase += _speed * delta * (2.6 if _speed < 5.0 else 2.1)
	rig.hit_t = maxf(0.0, rig.hit_t - delta * 3.0)
	rig.lod_skip = [0, 2, 6][tier]
	if tier < 2:
		rig.tick(delta)


func _face(pos: Vector3, k: float) -> void:
	var to := pos - global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), clampf(k, 0.0, 1.0))


func _down(delta: float) -> void:
	velocity.y -= 22.0 * delta
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
	if global_position.y < Game.WATER_Y - 1.2 and City.terrain_height(global_position.x, global_position.z) < Game.WATER_Y - 1.0:
		velocity.y = move_toward(velocity.y, 0.6, 40.0 * delta)
	if tier < 2:
		move_and_slide()
	rig.limp = 0.0 if dead else 1.0
	rig.dead = 1.0 if dead else 0.0
	rig.rotation.x = lerpf(rig.rotation.x, -1.45, clampf(delta * 8.0, 0.0, 1.0))
	rig.position.y = lerpf(rig.position.y, 0.25, clampf(delta * 8.0, 0.0, 1.0))
	rig.speed = 0.0
	rig.lod_skip = [0, 2, 8][tier]
	if not dead or _body_t < 1.5:
		rig.tick(delta)
	if dead:
		_body_t += delta
		if _body_t > 40.0 or (_body_t > 12.0 and Game.player and global_position.distance_to(Game.player.global_position) > 70.0):
			queue_free()
		return
	down_time -= delta
	if down_time <= 0.0 and is_on_floor():
		collision_layer = Game.L_CHAR
		rig.rotation.x = 0.0
		rig.position.y = 0.0
		rig.limp = 0.0
		_set_state(_get_up_state)
		if state == S.COMBAT and (target == null or not is_instance_valid(target)):
			_set_state(S.FLEE)


# ------------------------------------------------------------------ thinking
func _do_think() -> void:
	var p = Game.player
	match state:
		S.WANDER, S.IDLE:
			if kind == "gang" and p and p.alive():
				var d: float = global_position.distance_to(p.global_position)
				if d < 14.0 and can_see_player(14.0) and (p.is_armed() and p.aiming or d < 3.0 and p.is_armed()):
					engage(p)
			elif kind == "civ" and p and p.alive() and p.aiming and tier == 0:
				var d2: float = global_position.distance_to(p.global_position)
				if d2 < 12.0 and Game.cam and Game.cam.aim_dir().dot((global_position - p.global_position).normalized()) > 0.96 and can_see_player(14.0):
					_threat = p.global_position
					if courage > 0.5:
						_set_state(S.FLEE)
					else:
						_set_state(S.COWER)
					Wanted.crime("brandish", global_position)
			if state == S.IDLE and kind == "civ" and _state_t > _wait:
				_set_state(S.WANDER)
		S.STAND:
			_face(home + Vector3(-sin(home_yaw), 0, -cos(home_yaw)), 0.5)
			if p and p.alive() and p.aiming and global_position.distance_to(p.global_position) < 9.0 and can_see_player(10.0):
				if Game.cam.aim_dir().dot((eye() - Game.cam.aim_origin()).normalized()) > 0.97:
					_set_state(S.SURRENDER)
		S.SURRENDER:
			rig.hands_up = 1.0
			if p and p.aiming and global_position.distance_to(p.global_position) < 10.0:
				_aim_at_me_t += 0.3
				if _aim_at_me_t > 3.0 and not _robbed and kind == "clerk":
					_robbed = true
					Game.world.pickups.drop("cash", global_position + Vector3(-sin(home_yaw), 0.9, -cos(home_yaw)) * 1.4, cash)
					Game.say("The clerk hands over the register cash!", Color(0.6, 1.0, 0.6))
					Wanted.crime("robbery", global_position)
			elif _state_t > 8.0:
				_aim_at_me_t = 0.0
				_set_state(S.STAND if kind == "clerk" else S.FLEE)
		S.COWER:
			rig.cower = 1.0
			if _state_t > 6.0 + courage * 4.0:
				_set_state(S.FLEE)
		S.CALL:
			rig.phone = 1.0
			if _state_t > 4.5:
				Wanted.witness_report(witness_crime, global_position)
				witness_crime = ""
				_set_state(S.FLEE)
		S.FLEE:
			if _path.is_empty() or _path_i >= _path.size():
				var away := (global_position - _threat)
				away.y = 0.0
				if away.length() < 0.1:
					away = Vector3(Game.rng.randf_range(-1, 1), 0, Game.rng.randf_range(-1, 1))
				var goal := global_position + away.normalized().rotated(Vector3.UP, Game.rng.randf_range(-0.7, 0.7)) * 35.0
				_path_to(goal)
			if _state_t > 14.0 + courage * 6.0:
				alerted = false
				_set_state(S.WANDER)
				_walk_to = -1
		S.INVESTIGATE:
			if p and can_see_player(50.0) and Wanted.level > 0:
				engage(p)
			elif global_position.distance_to(last_seen) < 3.0 or _state_t > 25.0:
				if _state_t > 6.0:
					var np := last_seen + Vector3(Game.rng.randf_range(-18, 18), 0, Game.rng.randf_range(-18, 18))
					if Wanted.level > 0:
						np = Wanted.search_point()
					last_seen = np
					_state_t = 0.0
					_path_to(np)
			elif _path.is_empty():
				_path_to(last_seen)
			if Wanted.level == 0 and is_law() and _state_t > 12.0 and not persistent:
				_set_state(S.WANDER)
				rig.set_weapon(null)
		S.COMBAT:
			_combat_think()
		S.GOTO:
			if _path.is_empty() and global_position.distance_to(_goal) > 2.0:
				_path_to(_goal)


func goto(pos: Vector3) -> void:
	_goal = pos
	_set_state(S.GOTO)
	_path_to(pos)


func arrived() -> bool:
	return global_position.distance_to(_goal) < 2.2


# ------------------------------------------------------------------ movement helpers
func _path_to(goal: Vector3) -> void:
	_goal = goal
	_path_i = 0
	if nav_ready and tier < 2:
		_path = NavigationServer3D.map_get_path(nav_map, global_position, goal, true)
		if _path.size() < 2:
			_path = PackedVector3Array([global_position, goal])
	else:
		_path = PackedVector3Array([global_position, goal])


func _follow_path(speed: float) -> Vector3:
	if _path.is_empty() or _path_i >= _path.size():
		return Vector3.ZERO
	var tp := _path[_path_i]
	var to := tp - global_position
	to.y = 0.0
	if to.length() < 0.9:
		_path_i += 1
		if _path_i >= _path.size():
			return Vector3.ZERO
		tp = _path[_path_i]
		to = tp - global_position
		to.y = 0.0
	# stuck detection -> sidestep
	if _frame % 30 == 0:
		if global_position.distance_to(_last_pos) < 0.3:
			_stuck_t += 0.5
		else:
			_stuck_t = 0.0
		_last_pos = global_position
	var dir := to.normalized()
	if _stuck_t > 1.0:
		dir = dir.rotated(Vector3.UP, 1.3 * _strafe)
		if _stuck_t > 2.5:
			_strafe = -_strafe
			_stuck_t = 0.0
			_path = PackedVector3Array()
	return dir * speed


func _wander(delta: float) -> Vector3:
	if _wait > 0.0:
		_wait -= delta
		return Vector3.ZERO
	if _walk_to < 0:
		_walk_from = City.nearest_walk_node(global_position)
		_walk_to = _walk_from
		_walk_off = Vector3(Game.rng.randf_range(-0.9, 0.9), 0, Game.rng.randf_range(-0.9, 0.9))
	var tp: Vector3 = City.walk_nodes[_walk_to] + _walk_off
	var to := tp - global_position
	to.y = 0.0
	if to.length() < 1.0:
		var edges: Array = City.walk_edges[_walk_to]
		var opts := []
		for e in edges:
			if e.to != _walk_from or edges.size() == 1:
				opts.append(e)
		if opts.is_empty():
			opts = edges
		var pick: Dictionary = opts[Game.rng.randi() % opts.size()]
		if pick.cross:
			# wait for the road to clear before crossing
			var mid: Vector3 = (City.walk_nodes[_walk_to] + City.walk_nodes[pick.to]) * 0.5
			for v in Game.vehicles:
				if is_instance_valid(v) and v.global_position.distance_to(mid) < 11.0 and v.linear_velocity.length() > 3.0:
					_wait = 0.8
					return Vector3.ZERO
		_walk_from = _walk_to
		_walk_to = pick.to
		if Game.rng.randf() < 0.06:
			_wait = Game.rng.randf_range(2.0, 6.0)
		return Vector3.ZERO
	# dodge vehicles bearing down on us
	if tier == 0 and _frame % 6 == 0:
		for v in Game.vehicles:
			if not is_instance_valid(v):
				continue
			var rel: Vector3 = global_position - v.global_position
			var sp: float = v.linear_velocity.length()
			if sp > 4.0 and rel.length() < 5.0 + sp * 0.5 and v.linear_velocity.normalized().dot(rel.normalized()) > 0.85:
				var side: Vector3 = v.linear_velocity.normalized().cross(Vector3.UP)
				if side.dot(rel) < 0.0:
					side = -side
				velocity = side * 6.0 + Vector3.UP * 2.0
				_scream()
				break
	return to.normalized() * (1.5 + courage * 0.5)


# ------------------------------------------------------------------ combat
func _combat_think() -> void:
	if target == null or not is_instance_valid(target) or (target is Npc and target.dead) or (target is Player and not target.alive()):
		target = null
		alerted = false
		_set_state(S.WANDER if kind == "civ" else S.IDLE)
		rig.set_weapon(null)
		rig.aim = 0.0
		return
	var tpos: Vector3 = target.center() if target is Player else target.global_position + Vector3.UP * 1.2
	var ex: Array = [self, target]
	if target is Player and target.in_vehicle():
		ex.append(target.vehicle)
	has_los = Game.ray(eye(), tpos, Game.L_WORLD, ex).is_empty()
	var dist := global_position.distance_to(target.global_position)
	if target is Player:
		var seen: bool = has_los and dist < 70.0 * target.visibility()
		if seen:
			last_seen = target.global_position
			_seen_player_t = 0.0
		else:
			_seen_player_t += _think
		if is_law():
			if Wanted.level == 0:
				target = null
				_set_state(S.IDLE)
				rig.set_weapon(null)
				rig.aim = 0.0
				return
			if _seen_player_t > 4.0:
				investigate(Wanted.last_known)
				return
		elif _seen_player_t > 12.0:
			target = null
			_set_state(S.FLEE if kind == "civ" else S.IDLE)
			return
	else:
		if has_los:
			last_seen = target.global_position
	if _repath <= 0.0:
		_repath = 0.8
		if not has_los or dist > 26.0 or weapon == null or weapon.kind == "melee":
			_path_to(last_seen)
		elif _cover_t <= 0.0:
			_pick_cover(tpos)
	_repath -= _think


func _pick_cover(tpos: Vector3) -> void:
	_cover_t = Game.rng.randf_range(4.0, 7.0)
	_in_cover = false
	var best := Vector3.ZERO
	var found := false
	for i in range(6):
		var a := Game.rng.randf() * TAU
		var p := global_position + Vector3(cos(a), 0, sin(a)) * Game.rng.randf_range(3.0, 8.0)
		var low := Game.ray(p + Vector3.UP * 0.8, tpos, Game.L_WORLD | Game.L_VEHICLE)
		if not low.is_empty() and p.distance_to(low.position) < 2.5:
			if Game.ray(global_position + Vector3.UP, p + Vector3.UP, Game.L_WORLD).is_empty():
				best = p
				found = true
				break
	if found:
		_path = PackedVector3Array([global_position, best])
		_path_i = 0
		_in_cover = true
	else:
		_strafe = -_strafe
		_path = PackedVector3Array()


func _combat_move(delta: float) -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	var tp: Vector3 = target.global_position
	var dist := global_position.distance_to(tp)
	_cover_t -= delta
	var mv := Vector3.ZERO
	var melee_only := weapon == null or weapon.kind == "melee"
	var arrest: bool = is_law() and target is Player and Wanted.arrest_mode()
	rig.crouch = 0.0
	if melee_only or arrest:
		if dist > (1.5 if not arrest else 2.0):
			if has_los and dist < 14.0:
				mv = (tp - global_position).normalized() * (5.6 if dist > 4.0 else 3.0)
			else:
				mv = _follow_path(5.6)
		_face(tp, delta * 10.0)
		rig.aim = 1.0 if (arrest and dist < 12.0) else 0.0
		rig.aim_pitch = 0.0
		if not arrest and dist < 1.9 and _melee_cd <= 0.0:
			_melee_cd = 1.1
			rig.attack_kind = 3 if (weapon != null) else (Game.rng.randi() % 2)
			rig.attack_t = 0.0
			var dmg := 9.0 if weapon == null else weapon.damage * 0.45
			target.damage(dmg, global_position, self, "melee")
			Sfx.play3d("punch", tp + Vector3.UP * 1.2, -2.0, Game.rng.randf_range(0.9, 1.1), 30.0)
		if rig.attack_t >= 0.0:
			rig.attack_t += delta * 3.0
			if rig.attack_t >= 1.0:
				rig.attack_t = -1.0
		return mv
	# ranged
	if not _path.is_empty() and _path_i < _path.size():
		mv = _follow_path(4.8)
	elif has_los:
		if dist > 24.0:
			mv = (tp - global_position).normalized() * 4.0
		elif dist < 6.0:
			mv = (global_position - tp).normalized() * 3.0
		elif _in_cover:
			var ph := fmod(_state_t, 5.0)
			rig.crouch = 1.0 if ph < 2.0 else 0.0
		else:
			var side := (tp - global_position).normalized().cross(Vector3.UP) * _strafe
			mv = side * 1.6 if fmod(_state_t, 4.0) < 1.6 else Vector3.ZERO
	_face(tp, delta * 10.0)
	rig.aim = 1.0
	var dy := (tp.y + 1.1) - (global_position.y + 1.4)
	rig.aim_pitch = clampf(atan2(dy, maxf(dist, 1.0)), -0.8, 0.8)
	# shooting
	if _reload > 0.0:
		_reload -= delta
		if _reload <= 0.0:
			mag = weapon.mag
	elif has_los and rig.crouch < 0.5 and dist < weapon.reach * 0.6 and _fire_cd <= 0.0 and tier < 2:
		if is_law() and target is Player and not Wanted.lethal():
			pass
		else:
			_shoot(dist)
	return mv


func _shoot(dist: float) -> void:
	mag -= 1
	_burst += 1
	var auto := weapon.auto
	_fire_cd = (1.0 / weapon.rate) * (1.0 if auto else Game.rng.randf_range(1.6, 3.0))
	if auto and _burst >= 5:
		_burst = 0
		_fire_cd = Game.rng.randf_range(0.7, 1.4)
	if mag <= 0:
		_reload = weapon.reload * 1.3
	var from := rig.muzzle_pos()
	var tpos: Vector3 = target.center() if target is Player else target.global_position + Vector3.UP * 1.2
	var chance := accuracy * clampf(1.25 - dist / 55.0, 0.15, 1.0)
	var tv: Vector3 = target.velocity_now() if target is Player else target.velocity
	if tv.length() > 5.0:
		chance *= 0.6
	if target is Player:
		if target.crouching or target.state == Player.St.COVER or target.state == Player.St.ROLL:
			chance *= 0.55
		chance *= 0.7 + 0.12 * Wanted.level
	var hit := Game.rng.randf() < chance
	var end := tpos
	if not hit:
		end = tpos + Vector3(Game.rng.randf_range(-1.2, 1.2), Game.rng.randf_range(-0.6, 1.0), Game.rng.randf_range(-1.2, 1.2))
		var miss := Game.ray(from, from + (end - from).normalized() * (dist + 30.0), Game.L_WORLD | Game.L_VEHICLE | Game.L_PROP, [self])
		if not miss.is_empty():
			end = miss.position
			Fx.impact(end, miss.normal, Combat.surface_of(miss.collider))
		else:
			end = from + (end - from).normalized() * (dist + 30.0)
	else:
		var dmg := weapon.damage * 0.42 * weapon.pellets * 0.5 if weapon.pellets > 1 else weapon.damage * 0.42
		if target is Player and target.in_vehicle():
			target.vehicle.damage(dmg * 2.2, tpos, self)
			Fx.impact(tpos, (from - tpos).normalized(), "metal")
			if Game.rng.randf() < 0.3:
				target.damage(dmg * 0.6, global_position, self, "bullet")
		else:
			target.damage(dmg, global_position, self, "bullet")
			Fx.blood(tpos, (from - tpos).normalized())
	Fx.tracer(from, end)
	Fx.muzzle(from, (end - from).normalized())
	Sfx.play3d(weapon.sound, from, -3.0, Game.rng.randf_range(0.92, 1.08), 160.0)
	rig.recoil_kick = 1.0
