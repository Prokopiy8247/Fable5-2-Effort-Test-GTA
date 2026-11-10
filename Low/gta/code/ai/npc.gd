class_name NPC
extends Humanoid
# Pedestrians, drivers, police / tactical officers, gang members, shop staff, medics.
# Updated by Population with distance-based simulation tiers.

var role := "civ"
var ai := "wander"
var target = null
var path: PackedVector3Array = PackedVector3Array()
var path_i := 0
var repath_t := 0.0
var think_t := 0.0
var calm_t := 0.0
var brave := false
var route: Dictionary = {}
var dest := Vector3.ZERO
var has_dest := false
var wait_t := 0.0
var cash := 50
var car = null
var cover_car := false
var pop_t := 0.0
var corpse_t := 0.0
var home := Vector3.ZERO
var danger_pos := Vector3.ZERO
var robbed_t := -1000.0
var surrender_t := 0.0
var talk_label := ""
var move_speed := 1.4
var on_reach: Callable
var hurt_t := -100.0
var arrest_mode := false
var tier := 0


static func random_look(r: String) -> Dictionary:
	var female := randf() < 0.5
	var l := {"female": female, "skin": G.col(Defs.SKINS[randi() % Defs.SKINS.size()])}
	l["hair_color"] = G.col(Defs.HAIR_COLORS[randi() % 5][1])
	l["hair"] = Defs.HAIRS[(randi() % 3 + 1) if not female else [2, 4, 1][randi() % 3]]
	match r:
		"cop":
			l["shirt"] = Color(0.12, 0.17, 0.32)
			l["pants"] = Color(0.08, 0.1, 0.18)
			l["shoes"] = Color(0.05, 0.05, 0.05)
			l["hat"] = "acc_police_cap"
		"swat":
			l["shirt"] = Color(0.07, 0.08, 0.1)
			l["pants"] = Color(0.07, 0.08, 0.1)
			l["shoes"] = Color(0.04, 0.04, 0.04)
			l["hat"] = "acc_helmet"
			l["vest"] = "acc_vest"
		"gang":
			l["shirt"] = Color(0.45, 0.1, 0.55) if randf() < 0.6 else Color(0.08, 0.08, 0.08)
			l["pants"] = Color(0.1, 0.1, 0.12)
			l["shoes"] = Color(0.9, 0.9, 0.9)
			l["hat"] = "acc_cap" if randf() < 0.6 else ""
			l["hat_color"] = Color(0.45, 0.1, 0.55)
		"staff":
			l["shirt"] = Color(0.92, 0.92, 0.9)
			l["pants"] = Color(0.15, 0.15, 0.18)
			l["shoes"] = Color(0.1, 0.1, 0.1)
		"medic":
			l["shirt"] = Color(0.95, 0.95, 0.95)
			l["pants"] = Color(0.7, 0.1, 0.1)
			l["shoes"] = Color(0.1, 0.1, 0.1)
		_:
			l["shirt"] = G.col(Defs.CLOTH_COLORS[randi() % Defs.CLOTH_COLORS.size()][1])
			l["pants"] = G.col(Defs.CLOTH_COLORS[[1, 3, 8, 9, 10, 11][randi() % 6]][1])
			l["shoes"] = G.col(Defs.CLOTH_COLORS[[0, 1, 11, 8][randi() % 4]][1])
			if randf() < 0.18:
				l["hat"] = "acc_cap"
				l["hat_color"] = G.col(Defs.CLOTH_COLORS[randi() % Defs.CLOTH_COLORS.size()][1])
			if randf() < 0.15:
				l["glasses"] = "acc_glasses"
			if not female and randf() < 0.2:
				l["beard"] = "acc_beard"
	return l


static func make(r: String) -> NPC:
	var n := NPC.new()
	n.role = r
	n.setup(random_look(r))
	n.cash = randi_range(20, 140)
	n.model.scale = Vector3.ONE * randf_range(0.94, 1.05)
	match r:
		"cop":
			n.accuracy = 0.5
			n.give_weapon("pistol", 999)
			n.equip("pistol")
			n.armor = 30.0
		"swat":
			n.accuracy = 0.65
			n.max_health = 150.0
			n.health = 150.0
			n.armor = 100.0
			var w: String = ["carbine", "shotgun", "smg"][randi() % 3]
			n.give_weapon(w, 999)
			n.equip(w)
		"gang":
			n.accuracy = 0.38
			var w2: String = ["pistol", "pistol", "smg", "bat"][randi() % 4]
			n.give_weapon(w2, 999)
			n.equip(w2)
			n.brave = true
			n.cash = randi_range(100, 400)
		_:
			n.accuracy = 0.25
			n.brave = randf() < 0.08
			if n.brave:
				n.give_weapon("pistol", 60)
	for k in n.reserve:
		n.reserve[k] = 9999
	return n


func eye() -> Vector3:
	return global_position + Vector3.UP * (1.1 if crouching else 1.65)


# ---------------------------------------------------------------- update (called by Population)
func update(dt: float, t: int) -> void:
	tier = t
	tick(dt)
	if dead:
		if state == "ragdoll" and corpse_t < 3.0:
			_ragdoll_physics(dt)
		corpse_t += dt
		if tier == 0:
			_animate(dt)
		return
	if state == "vehicle":
		if vehicle == null or not is_instance_valid(vehicle) or vehicle.wrecked:
			force_exit()
		elif visible:
			global_transform = vehicle.seat_transform()
			_animate(dt)
		else:
			global_position = vehicle.global_position
		return
	if state == "ragdoll":
		_ragdoll_physics(dt)
		_animate(dt)
		return
	calm_t = max(0.0, calm_t - dt)
	var want := Vector3.ZERO
	var speed := move_speed
	aiming = false
	match ai:
		"wander":
			want = _wander(dt)
		"idle":
			if home != Vector3.ZERO and global_position.distance_to(home) > 1.5:
				want = _dir_to(home)
			_staff_check(dt)
		"flee":
			speed = 5.6
			want = _follow_path(dt, danger_pos, true)
			if calm_t <= 0.0:
				ai = "wander"
				alerted = false
		"cower":
			state = "cower"
			if calm_t <= 0.0:
				state = "normal"
				ai = "wander"
				alerted = false
		"surrender":
			state = "surrender"
			surrender_t -= dt
			if surrender_t <= 0.0:
				state = "normal"
				if role == "staff":
					G.world.drop_cash(global_position + (-global_basis.z) * 1.0, randi_range(250, 600))
					G.notify("The clerk hands over the register cash")
					if G.wanted:
						G.wanted.crime("robbery", global_position)
				ai = "cower"
				calm_t = 12.0
		"goto":
			speed = 4.5
			want = _follow_path(dt, dest, false)
			if global_position.distance_to(dest) < 1.6:
				ai = "idle"
				home = Vector3.ZERO
				if on_reach.is_valid():
					on_reach.call()
		"combat":
			var r := _combat(dt)
			want = r[0]
			speed = r[1]
		"return_car":
			speed = 5.6
			if car == null or not is_instance_valid(car) or car.wrecked or (car.driver != null and car.driver != self):
				ai = "combat"
			else:
				var dp: Vector3 = car.door_pos()
				want = _follow_path(dt, dp, false)
				if global_position.distance_to(dp) < 2.2:
					_board_car()
	if state == "cower" or state == "surrender":
		want = Vector3.ZERO
	# movement
	if tier <= 1:
		velocity.x = move_toward(velocity.x, want.x * speed, 20.0 * dt)
		velocity.z = move_toward(velocity.z, want.z * speed, 20.0 * dt)
		velocity.y -= GRAV * dt
		if global_position.y < G.WATER_Y - 1.3:
			velocity.y = 1.0
		move_and_slide()
	else:
		global_position += want * speed * dt
		velocity = want * speed
	if want.length() > 0.1 and not aiming:
		rotation.y = lerp_angle(rotation.y, atan2(-want.x, -want.z), min(1.0, dt * 8.0))
	if tier == 0:
		_animate(dt)


func _dir_to(p: Vector3) -> Vector3:
	var d := p - global_position
	d.y = 0
	if d.length() < 0.2:
		return Vector3.ZERO
	return d.normalized()


func _follow_path(dt: float, goal: Vector3, away: bool) -> Vector3:
	repath_t -= dt
	if repath_t <= 0.0 or path.size() < 2:
		repath_t = 1.2 + randf() * 0.6
		var g := goal
		if away:
			var d := global_position - goal
			d.y = 0
			if d.length() < 0.1:
				d = Vector3(1, 0, 0)
			g = global_position + d.normalized() * 30.0
			g.x = clamp(g.x, -280.0, 280.0)
			g.z = clamp(g.z, -285.0, 200.0)
		path = G.world.nav_path(global_position, g)
		path_i = 1
	while path_i < path.size() - 1 and Vector2(path[path_i].x - global_position.x, path[path_i].z - global_position.z).length() < 0.8:
		path_i += 1
	if path_i >= path.size():
		return Vector3.ZERO
	return _dir_to(path[path_i])


func _wander(dt: float) -> Vector3:
	if wait_t > 0.0:
		wait_t -= dt
		return Vector3.ZERO
	if not has_dest:
		_next_waypoint()
	var d := dest - global_position
	d.y = 0
	if d.length() < 1.0:
		has_dest = false
		if randf() < 0.12:
			wait_t = randf_range(1.5, 5.0)
		return Vector3.ZERO
	# wait at the curb for cross traffic to get a red light
	if route.get("crossing", false) and route.get("wait_node", -1) >= 0:
		if G.roads.light_state(route.wait_node, route.wait_x) != 2 and route.get("waited", 0.0) < 14.0:
			route["waited"] = route.get("waited", 0.0) + dt
			return Vector3.ZERO
		route["wait_node"] = -1
	return d.normalized()


func _next_waypoint() -> void:
	has_dest = true
	if route.get("type", "block") == "area":
		var r: Rect2 = route.rect
		dest = Vector3(randf_range(r.position.x, r.end.x), global_position.y, randf_range(r.position.y, r.end.y))
		return
	var i: int = route.get("i", 1)
	var j: int = route.get("j", 1)
	var c: int = route.get("c", 0)
	var dirn: int = route.get("dir", 1)
	route["crossing"] = false
	var roll := randf()
	if roll < 0.3:
		# cross to a neighbouring block at this corner
		var opts := []
		if c in [1, 2] and i < 3: opts.append([i + 1, j, 0 if c == 1 else 3, true])
		if c in [0, 3] and i > 0: opts.append([i - 1, j, 1 if c == 0 else 2, true])
		if c in [2, 3] and j < 3: opts.append([i, j + 1, 1 if c == 2 else 0, false])
		if c in [0, 1] and j > 0: opts.append([i, j - 1, 2 if c == 1 else 3, false])
		if not opts.is_empty():
			var o: Array = opts[randi() % opts.size()]
			route["i"] = o[0]
			route["j"] = o[1]
			route["c"] = o[2]
			route["crossing"] = true
			dest = corner_pos(o[0], o[1], o[2])
			var mid := (global_position + dest) / 2
			route["wait_node"] = G.roads.nearest(mid)
			route["wait_x"] = not o[3]
			route["waited"] = 0.0
			return
	c = wrapi(c + dirn, 0, 4)
	route["c"] = c
	dest = corner_pos(i, j, c)


static func corner_pos(i: int, j: int, c: int) -> Vector3:
	var r: Rect2 = G.world.block_rect(i, j)
	var m := 2.0
	match c:
		0: return Vector3(r.position.x + m, WorldBuilder.SLAB_Y, r.position.y + m)
		1: return Vector3(r.end.x - m, WorldBuilder.SLAB_Y, r.position.y + m)
		2: return Vector3(r.end.x - m, WorldBuilder.SLAB_Y, r.end.y - m)
	return Vector3(r.position.x + m, WorldBuilder.SLAB_Y, r.end.y - m)


func _staff_check(dt: float) -> void:
	if role != "staff":
		return
	var p = G.player
	if p == null or p.dead or G.time_now - robbed_t < 240.0:
		return
	var d: float = p.global_position.distance_to(global_position)
	if d < 9.0 and p.aiming and not p.wdef().get("melee", false) and (-p.global_basis.z).dot((global_position - p.global_position).normalized()) > 0.85:
		ai = "surrender"
		surrender_t = 3.5
		robbed_t = G.time_now
		rotation.y = atan2(-(p.global_position.x - global_position.x), -(p.global_position.z - global_position.z))
		G.notify("Robbery: keep the clerk at gunpoint...")


# ---------------------------------------------------------------- combat
func engage(t) -> void:
	if dead or t == null or t == self:
		return
	target = t
	alerted = true
	if state in ["cower", "surrender"]:
		state = "normal"
	if state != "vehicle":
		ai = "combat"


func _combat(dt: float) -> Array:
	var want := Vector3.ZERO
	var speed := 5.2
	if target == null or not is_instance_valid(target) or target.dead:
		target = null
		ai = "wander" if role != "gang" else "idle"
		crouching = false
		alerted = false
		return [want, speed]
	var police := role in ["cop", "swat"]
	var tp: Vector3 = target.global_position
	if police and target.is_player and G.wanted:
		if G.wanted.stars == 0:
			target = null
			ai = "wander"
			route = {"type": "area", "rect": Rect2(global_position.x - 20, global_position.z - 20, 40, 40)}
			crouching = false
			return [want, speed]
		if not G.wanted.seen:
			tp = G.wanted.search_point(self)
	var dist := global_position.distance_to(tp)
	var tchest: Vector3 = target.global_position + Vector3.UP * (0.7 if target.crouching else 1.2)
	var can_see: bool = dist < 90.0 and G.los(eye(), tchest, [self, target])
	if police and target.is_player and not G.wanted.seen:
		can_see = false
	var melee: bool = wdef().get("melee", false)
	arrest_mode = police and target.is_player and G.wanted != null and not G.wanted.lethal
	# chase a fleeing vehicle on wheels
	if police and target.vehicle != null and dist > 30.0 and car != null and is_instance_valid(car) and not car.wrecked and car.driver == null and target.vehicle.linear_velocity.length() > 5.0:
		ai = "return_car"
		repath_t = 0.0
		return [want, speed]
	var rmin := 1.2 if (melee or arrest_mode) else 7.0
	var rmax := 1.8 if (melee or arrest_mode) else 26.0
	think_t -= dt
	if not can_see or dist > rmax:
		want = _follow_path(dt, tp, false)
		crouching = false
	elif dist < rmin and not melee and not arrest_mode:
		want = -_dir_to(tp) * 0.6
	else:
		# hold position; sometimes take a knee / use own car as cover
		if think_t <= 0.0:
			think_t = randf_range(1.5, 3.5)
			crouching = not melee and not arrest_mode and (randf() < 0.45 or G.time_now - hurt_t < 4.0)
			if police and car != null and is_instance_valid(car) and not arrest_mode and dist > 10.0 and car.global_position.distance_to(global_position) < 14.0:
				cover_car = true
		if cover_car and car != null and is_instance_valid(car):
			var away: Vector3 = car.global_position - tp
			away.y = 0
			var cp2: Vector3 = car.global_position + away.normalized() * (car.def.W * 0.5 + 0.9)
			if global_position.distance_to(cp2) > 1.0:
				want = _dir_to(cp2)
				speed = 4.0
			else:
				pop_t -= dt
				if pop_t <= 0.0:
					pop_t = randf_range(1.0, 2.2)
					crouching = not crouching
	if can_see:
		var fd := _dir_to(tp)
		if fd != Vector3.ZERO:
			rotation.y = lerp_angle(rotation.y, atan2(-fd.x, -fd.z), min(1.0, dt * 10.0))
		aiming = not melee and not arrest_mode
		var o := eye()
		var to := tchest - o
		aim_pitch = atan2(to.y, Vector2(to.x, to.z).length())
		if arrest_mode:
			if dist < 2.6 and G.wanted:
				G.wanted.arrest_tick(dt)
		elif melee:
			if dist < 2.0:
				melee_attack(false)
		elif dist < 70.0 and not (cover_car and crouching):
			if fire(o, to.normalized(), 3.0):
				if target.vehicle != null and randf() < 0.2:
					target.take_damage(wdef().dmg * 0.5, self, tchest, to.normalized(), "bullet")
	return [want, speed]


func _board_car() -> void:
	if car.driver == null:
		state = "vehicle"
		vehicle = car
		visible = false
		collision_layer = 0
		cshape.disabled = true
		car.set_driver(self)
		car.handbrake = false
		car.siren_on = true
		car.ai = AIDriver.new()
		car.ai.mode = "pursuit"
		ai = "combat"
	else:
		car.set_meta("cops", car.get_meta("cops", 0) + 1)
		G.pop.remove(self)


func leave_vehicle(side := -1.0) -> void:
	var v = vehicle
	if v == null:
		return
	if v.driver == self:
		v.set_driver(null)
	vehicle = null
	state = "normal"
	visible = true
	collision_layer = G.L_CHAR
	cshape.disabled = false
	global_position = v.global_transform * Vector3(side * (v.def.W / 2 + 0.9), 0.3, 0.0)
	rotation = Vector3(0, v.global_rotation.y, 0)
	velocity = Vector3.ZERO


func force_exit() -> void:
	leave_vehicle()


func pulled_out(by, v) -> void:
	v.ai = null
	leave_vehicle(-1.6)
	alerted = true
	knockdown((global_position - v.global_position).normalized() * 3.0 + Vector3.UP * 2.0)
	if role in ["cop", "swat"] or brave:
		engage(by)
	else:
		start_flee(by.global_position, 20.0)


func vehicle_attacked(attacker) -> void:
	if vehicle != null and vehicle.ai != null and role == "civ":
		vehicle.ai.panic = 12.0


func start_flee(from: Vector3, dur: float) -> void:
	if dead or role in ["cop", "swat"]:
		return
	alerted = true
	danger_pos = from
	calm_t = dur
	repath_t = 0.0
	if state in ["cower", "surrender"]:
		state = "normal"
	ai = "flee"
	crouching = false


func on_danger(pos: Vector3, source, kind: String) -> void:
	if dead or state == "vehicle" or kind == "horn":
		return
	var d := pos.distance_to(global_position)
	match role:
		"civ", "staff", "medic":
			if brave and source != null and is_instance_valid(source) and source is Humanoid and d < 25.0 and role == "civ" and "pistol" in owned:
				equip("pistol")
				engage(source)
			elif d < 10.0 and randf() < 0.35 and ai != "flee":
				ai = "cower"
				calm_t = randf_range(8.0, 16.0)
				alerted = true
			else:
				start_flee(pos, randf_range(12.0, 22.0))
		"gang":
			if source != null and is_instance_valid(source) and source is Humanoid and source != self and d < 45.0:
				if not (source is NPC and source.role == "gang"):
					engage(source)
		"cop", "swat":
			if source != null and is_instance_valid(source) and source is NPC and source.role == "gang" and target == null:
				engage(source)


func _damaged(amount: float, attacker, kind: String) -> void:
	hurt_t = G.time_now
	alerted = true
	if attacker == null or not is_instance_valid(attacker) or attacker == self:
		return
	if attacker.is_player and G.wanted and kind != "explosion":
		if role in ["cop", "swat"]:
			G.wanted.crime("attack_police", global_position, self)
		elif kind != "vehicle":
			G.wanted.crime("assault", global_position, self)
	if attacker is Humanoid:
		if role in ["cop", "swat", "gang"] or brave:
			if not (role in ["cop", "swat"] and attacker is NPC and attacker.role in ["cop", "swat"]):
				engage(attacker)
		else:
			start_flee(attacker.global_position, 20.0)


func _died(attacker, kind: String) -> void:
	if weapon_node:
		weapon_node.visible = false
	if attacker != null and is_instance_valid(attacker) and attacker.is_player and G.wanted:
		G.wanted.crime("kill_cop" if role in ["cop", "swat"] else "kill", global_position, self)
	if cash > 0 and role != "medic":
		G.world.drop_cash(global_position, cash)
	if role in ["cop", "swat"] and randf() < 0.5:
		G.world.add_pickup(global_position + Vector3(0.6, 0.2, 0), "ammo", 1)
		G.world.pickups[-1]["temp"] = G.time_now + 60.0
	if G.traffic and role != "medic":
		G.traffic.report_death(global_position)
	if vehicle != null:
		var v = vehicle
		if v.driver == self:
			v.set_driver(null)
			v.ai = null
		vehicle = null


func talk(_by) -> void:
	pass
