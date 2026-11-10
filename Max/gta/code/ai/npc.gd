class_name NPC
extends Character
## Every non-player human: pedestrians, drivers, shop staff, gang members, police and
## tactical officers. One compact state machine with shared perception (sight, hearing),
## navigation (sidewalk graph / nav-mesh paths / direct steering) and combat behaviour.

enum S { IDLE, WALK, AREA, GOTO, FLEE, COWER, FIGHT, CALL, SEATED, STAFF, DOWN, DEAD, POSE }

var role: StringName = &"civil"      # civil | driver | staff | gang | police | swat
var state: int = S.IDLE
var tier := 0                        # 0 near (full sim), 1 mid (cheap), 2 far (frozen)
var rng := RandomNumberGenerator.new()
var target: Character = null
var threat_pos := Vector3.ZERO
var alert := 0.0
var brave := false                   # fights back instead of fleeing
var armed: StringName = &""          # weapon id carried (drawn when fighting)
var accuracy_spread := 4.5
var sight := 34.0
var home_area: Dictionary = {}       # {rect, y} for AREA wanderers
var graph_at := -1
var graph_from := -1
var graph_edge := 0
var goal := Vector3.ZERO
var has_goal := false
var move_speed := 1.5
var path: PackedVector3Array = PackedVector3Array()
var path_i := 0
var cash := 0
var dispatch_vehicle: Vehicle = null # police: the unit's own car
var last_seen_target := -100.0
var last_known := Vector3.ZERO
var witnessed: Dictionary = {}       # crime being phoned in
var is_witness_calling := false
var _timer := 0.0
var _repath := 0.0
var _burst := 0
var _burst_cd := 0.0
var _react := 0.0
var _think := 0.0
var _stuck := 0.0
var _last_pos := Vector3.ZERO
var _wait := 0.0
var _crouch_t := 0.0
var _dead_t := 0.0
var _scream_cd := 0.0
var _lane_offset := 0.0
var _strafe := 0.0
var staff_yaw := 0.0
var cover_pos: Variant = null        # Vector3 assigned by the police dispatcher
var ambient := false                 # owned by the ambient population (may be despawned)
var enter_vehicle: Vehicle = null    # order_enter target
var post := Vector3.ZERO             # staff: where they stand behind the counter
var pose_name: StringName = &"idle"
var pose_upper: StringName = &""
var enter_seat := 0
var _dodge_dir := Vector3.ZERO
var _dodge_t := 0.0
var _veh_check := 0.0

static var scream_gate := 0.0

func init_npc(npc_role: StringName, ap: Dictionary, seed_v: int) -> void:
	role = npc_role
	rng.seed = seed_v
	team = &"police" if (role == &"police" or role == &"swat") else (&"gang" if role == &"gang" else &"civil")
	setup_body(ap)
	add_to_group(&"npcs")
	cash = rng.randi_range(6, 70)
	match role:
		&"police":
			max_health = 110.0
			armed = &"pistol"
			brave = true
			accuracy_spread = 3.4
			sight = 46.0
			add_to_group(&"police_units")
		&"swat":
			max_health = 140.0
			armor = 80.0
			armed = &"rifle_carbine" if rng.randf() < 0.6 else &"smg"
			brave = true
			accuracy_spread = 2.5
			sight = 55.0
			add_to_group(&"police_units")
		&"gang":
			armed = [&"pistol", &"smg", &"bat", &"knife"][rng.randi() % 4]
			brave = true
			accuracy_spread = 4.2
			cash = rng.randi_range(40, 220)
		&"staff":
			brave = rng.randf() < 0.25
			armed = &"shotgun_pump" if brave else &""
		&"medic", &"firefighter":
			brave = false
			armed = &""
		_:
			brave = rng.randf() < 0.12
			if brave and rng.randf() < 0.35:
				armed = &"pistol"
	health = max_health
	_lane_offset = rng.randf_range(-0.9, 0.9)
	if armed != &"":
		inventory.give(armed, 120, true)
	gunner.equip(&"unarmed", true)

func is_alerted() -> bool:
	return alert > 0.5 or state == S.FLEE or state == S.FIGHT or state == S.COWER or state == S.CALL

func is_cop() -> bool:
	return role == &"police" or role == &"swat"

# ---------------------------------------------------------------- perception
func can_see(c: Character) -> bool:
	if c == null or not is_instance_valid(c) or not c.alive:
		return false
	var to := c.chest_position() - eye_position()
	var d := to.length()
	var range_m := sight * (Game.weather.visibility_range() if Game.weather else 1.0)
	if c.is_player:
		var pl := c as Player
		if pl.crouched and pl.vehicle == null:
			range_m *= 0.55 - 0.15 * (Game.skills.level(&"stealth") if Game.skills else 0.0)
		if pl.vehicle != null:
			range_m *= 1.25
	if d > range_m:
		return false
	if vehicle != null and is_instance_valid(vehicle):
		# seated: mirrors and windows give a wide view, helicopter crews look all around
		var vb := (vehicle as Node3D).global_transform.basis
		if (vehicle as Vehicle).kind != &"heli" and d > 6.0 and to.normalized().dot(-vb.z) < -0.35:
			return false
	elif d > 3.0 and to.normalized().dot(forward()) < (0.15 if is_alerted() else 0.42):
		return false
	var ex: Array[RID] = [get_rid()]
	if vehicle != null and is_instance_valid(vehicle):
		ex.append((vehicle as CollisionObject3D).get_rid())
	if c.vehicle != null and is_instance_valid(c.vehicle):
		ex.append((c.vehicle as CollisionObject3D).get_rid())
	return Game.ray(eye_position(), c.chest_position(), Phys.SIGHT_BLOCK, ex).is_empty()

## Routed by PedManager for every audible event in range.
func hear(pos: Vector3, kind: StringName, source: Node) -> void:
	if not alive or state == S.DEAD or state == S.SEATED and vehicle != null and role != &"driver":
		return
	if kind == &"gunshot" or kind == &"explosion":
		alert = 1.0
		threat_pos = pos
		if is_cop():
			if source is Character and (source as Character).is_player:
				last_known = pos
			return
		if state == S.SEATED:
			if vehicle != null and (vehicle as Vehicle).ai != null and (vehicle as Vehicle).ai.has_method("panic"):
				(vehicle as Vehicle).ai.panic(pos)
			return
		if brave and source is Character and armed != &"" and global_position.distance_to(pos) < 25.0:
			fight(source)
		elif state != S.FLEE and state != S.FIGHT and state != S.CALL:
			if rng.randf() < 0.18 and global_position.distance_to(pos) < 14.0 and state != S.STAFF:
				cower(rng.randf_range(4.0, 8.0))
			else:
				flee(pos)
	elif kind == &"impact" or kind == &"scream" or kind == &"horn":
		alert = maxf(alert, 0.4)

## The player (or anyone) is pointing a gun at this NPC.
func threatened(by: Character) -> void:
	if not alive or state == S.DEAD or state == S.FIGHT or is_cop() or state == S.SEATED:
		return
	if role == &"staff" and has_meta("shop") and by.is_player:
		_robbed(by)
		return
	alert = 1.0
	threat_pos = by.global_position
	if brave and (armed != &"" or global_position.distance_to(by.global_position) < 4.0):
		fight(by)
	elif state != S.COWER and state != S.FLEE:
		if rng.randf() < 0.45:
			cower(rng.randf_range(5.0, 9.0))
		else:
			flee(by.global_position)

## A shop clerk held up at gunpoint: hands up, the till is emptied onto the counter and a
## silent alarm goes off a few seconds later (unless the clerk is silenced first).
func _robbed(by: Character) -> void:
	alert = 1.0
	threat_pos = by.global_position
	if Game.clock < float(get_meta("robbed_at", -1000.0)) + 240.0:
		if state != S.COWER:
			cower(5.0)
		return
	set_meta("robbed_at", Game.clock)
	cower(7.0)
	visual.set_state(&"hands_up")
	if scream_gate <= 0.0:
		scream_gate = 0.5
		Audio.play(StringName("scream_%d" % (1 + rng.randi() % 3)), global_position, -6.0)
	Game.notify("The clerk empties the till", "money")
	get_tree().create_timer(2.2, false).timeout.connect(func() -> void:
		if is_instance_valid(self) and alive and Game.pickups != null:
			Game.pickups.drop_cash(rng.randi_range(220, 680), global_position + forward() * 0.9 + Vector3(0, 1.1, 0)))
	get_tree().create_timer(6.0, false).timeout.connect(func() -> void:
		if is_instance_valid(self) and alive and Game.wanted != null:
			Game.wanted.report(&"shoplift", global_position, 20.0, false))

func _on_damaged(amount: float, source: Node, _hit_pos: Vector3, _dir: Vector3, info: Dictionary) -> void:
	Events.npc_hurt.emit(self, source, amount)
	alert = 1.0
	is_witness_calling = false
	if not alive:
		return
	if source is Character and source != self:
		var s := source as Character
		threat_pos = s.global_position
		if state == S.SEATED:
			return
		if s.team == team and team != &"civil":
			return               # stray round from a colleague
		if is_cop() or brave:
			fight(s)
		elif String(info.get("type", "")) != "vehicle":
			flee(s.global_position)
	if _scream_cd <= 0.0 and scream_gate <= 0.0 and not is_cop():
		_scream_cd = 4.0
		scream_gate = 0.35
		Audio.play(StringName("hurt_%d" % (1 + rng.randi() % 3)), global_position, -4.0, 1.1 if visual.female else 0.9)

func _on_died(killer: Node) -> void:
	state = S.DEAD
	_dead_t = 0.0
	is_witness_calling = false
	remove_from_group(&"police_units")
	Events.npc_died.emit(self, killer)
	if Game.pickups:
		if cash > 0 and not is_cop():
			Game.pickups.drop_cash(cash, global_position + Vector3(0, 0.4, 0))
		if armed != &"" and WeaponDB.is_gun(armed) and vehicle == null:
			Game.pickups.drop_weapon(armed, int(WeaponDB.get_w(armed).get("mag", 10)) * 2, global_position + forward() * 0.6 + Vector3(0, 0.4, 0))
	if killer == Game.player:
		Game.stats["kills"] += 1
		if is_cop():
			Game.stats["police_kills"] += 1

func on_carjacked(by: Character, _veh: Vehicle) -> void:
	alert = 1.0
	threat_pos = by.global_position
	knockdown((global_position - by.global_position).normalized() * 2.0 + Vector3(0, 1.5, 0), 1.4)
	if brave:
		target = by
		_after_down = S.FIGHT
	else:
		_after_down = S.FLEE
	if scream_gate <= 0.0:
		scream_gate = 0.5
		Audio.play(StringName("scream_%d" % (1 + rng.randi() % 3)), global_position, -3.0)

var _after_down: int = S.FLEE

func on_takedown(by: Character, lethal: bool) -> void:
	if visual:
		visual.play_action("TakedownVictim", 1.2)
	apply_damage(9999.0 if lethal else maxf(health - 1.0, 1.0), by, global_position + Vector3(0, 1.4, 0), Vector3.ZERO, {"type": "melee", "silent": true})
	if alive:
		knockdown(Vector3.ZERO, 30.0)

# ---------------------------------------------------------------- state changes
func walk_graph(at: int) -> void:
	graph_at = at
	graph_from = -1
	state = S.WALK
	has_goal = false

## Start somewhere along the sidewalk edge `from` -> `to` (used by the spawner).
func walk_edge(from: int, to: int, edge_type: int, graph_pts: PackedVector3Array) -> void:
	graph_from = from
	graph_at = to
	graph_edge = edge_type
	var side := (graph_pts[to] - graph_pts[from]).cross(Vector3.UP).normalized()
	goal = graph_pts[to] + side * _lane_offset
	has_goal = true
	move_speed = rng.randf_range(1.25, 1.75)
	state = S.WALK
	_wait = 0.0

func set_tier(t: int) -> void:
	if t == tier:
		return
	if t == 0 and tier > 0 and vehicle == null:
		global_position.y += 0.25      # cheap movement ignores kerbs: drop back onto the surface
		velocity = Vector3.ZERO
	if (t >= 2) != (tier >= 2) and visual != null:
		visual.set_anim_active(t < 2)
	tier = t

## Jump out of the way of a vehicle bearing down on us.
func dodge(vel: Vector3, from: Vector3) -> void:
	if state == S.SEATED or state == S.DEAD or down or state == S.FIGHT:
		return
	var dirv := vel.normalized()
	var rel := global_position - from
	var side := rel - dirv * rel.dot(dirv)
	side.y = 0.0
	if side.length() < 0.1:
		side = Vector3(-dirv.z, 0.0, dirv.x)
	_dodge_dir = side.normalized()
	_dodge_t = 0.55
	alert = maxf(alert, 0.6)
	threat_pos = from

func wander_area(area: Dictionary) -> void:
	home_area = area
	state = S.AREA
	has_goal = false

func go_to(pos: Vector3, speed := 4.2) -> void:
	goal = pos
	has_goal = true
	move_speed = speed
	state = S.GOTO
	path = PackedVector3Array()

## Police order: move to a search point with the weapon ready.
func order_search(pos: Vector3) -> void:
	if state == S.DEAD or state == S.SEATED or down:
		return
	target = null
	enter_vehicle = null
	go_to(pos, 3.6)
	if armed != &"" and gunner.weapon_id != armed:
		gunner.equip(armed, true)

## Order: run to a vehicle and get into the given seat.
func order_enter(veh: Vehicle, seat_index: int) -> void:
	if state == S.DEAD or state == S.SEATED or down or veh == null:
		return
	target = null
	enter_vehicle = veh
	enter_seat = seat_index
	gunner.aiming = false
	visual.upper = &""
	go_to(veh.door_position(seat_index), 5.6)

## Scripted pose for a while (paramedic kneeling, firefighter spraying), facing `look_at_pos`.
func hold_pose(pose: StringName, seconds: float, look_at_pos: Vector3, upper_pose: StringName = &"") -> void:
	if state == S.DEAD or state == S.SEATED or down:
		return
	state = S.POSE
	_timer = seconds
	pose_name = pose
	pose_upper = upper_pose
	goal = look_at_pos
	has_goal = false

func _pose(delta: float) -> void:
	_timer -= delta
	_stand(delta, pose_name)
	set_crouched(pose_name == &"crouch_idle")
	visual.upper = pose_upper
	turn_toward(goal - global_position, delta, 6.0)
	if _timer <= 0.0:
		set_crouched(false)
		visual.upper = &""
		calm()

func make_staff(yaw: float) -> void:
	state = S.STAFF
	staff_yaw = yaw
	post = global_position
	set_face_yaw(yaw)

func flee(from: Vector3) -> void:
	if state == S.SEATED or state == S.DEAD:
		return
	threat_pos = from
	state = S.FLEE
	_timer = rng.randf_range(11.0, 19.0)
	_repath = 0.0
	set_crouched(false)
	gunner.aiming = false
	visual.upper = &""
	if scream_gate <= 0.0 and rng.randf() < 0.5:
		scream_gate = 0.6
		Audio.play(StringName("scream_%d" % (1 + rng.randi() % 3)), global_position, -4.0, 1.15 if visual.female else 0.9)
		Events.noise.emit(global_position, 18.0, &"scream", self)

func cower(seconds: float) -> void:
	state = S.COWER
	_timer = seconds
	velocity = Vector3.ZERO

func fight(who: Character) -> void:
	if who == null or who == self or state == S.DEAD or state == S.SEATED:
		return
	target = who
	if state != S.FIGHT:
		_react = rng.randf_range(0.35, 0.9)
		_burst = 0
		_burst_cd = 0.0
	state = S.FIGHT
	last_known = who.global_position
	last_seen_target = Game.clock
	if armed != &"" and gunner.weapon_id != armed:
		gunner.equip(armed, true)

## Witness: phone the police about a crime. WantedSystem is told only if the call completes.
func call_police(crime: Dictionary) -> void:
	if is_cop() or state == S.DEAD or state == S.SEATED or state == S.FIGHT:
		return
	witnessed = crime
	is_witness_calling = true
	state = S.CALL
	_timer = rng.randf_range(3.2, 5.0)

func calm() -> void:
	alert = 0.0
	target = null
	gunner.aiming = false
	visual.upper = &""
	if gunner.weapon_id != &"unarmed" and not is_cop():
		gunner.equip(&"unarmed", true)
	if role == &"staff":
		state = S.STAFF
	elif not home_area.is_empty():
		state = S.AREA
	elif graph_at >= 0:
		state = S.WALK
	else:
		state = S.IDLE
	has_goal = false

# ---------------------------------------------------------------- movement
func _steer(to: Vector3, speed: float, delta: float, run_anim := true) -> float:
	var flat := Vector3(to.x - global_position.x, 0.0, to.z - global_position.z)
	var dist := flat.length()
	var dirv := flat / maxf(dist, 0.001)
	if tier >= 1:
		# cheap far-away movement: no collision, stay on the known ground height
		global_position += dirv * minf(speed * delta, dist)
		turn_toward(dirv, delta, 8.0)
		visual.set_state(&"walk" if speed < 2.6 else &"run", speed)
		return dist
	# whisker avoidance: slide around walls / props / vehicles
	if dist > 1.0:
		var o := global_position + Vector3(0, 0.6, 0)
		var ahead := Game.ray(o, o + dirv * 1.3, Phys.WORLD | Phys.VEHICLE | Phys.PROP, [get_rid()])
		if not ahead.is_empty():
			var n: Vector3 = ahead["normal"]
			var slide := (dirv - n * dirv.dot(n))
			slide.y = 0.0
			if slide.length() < 0.2:
				slide = Vector3(-dirv.z, 0, dirv.x) * (1.0 if _lane_offset > 0.0 else -1.0)
			dirv = slide.normalized()
	velocity.x = move_toward(velocity.x, dirv.x * speed, delta * 14.0)
	velocity.z = move_toward(velocity.z, dirv.z * speed, delta * 14.0)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	turn_toward(dirv, delta, 9.0)
	var hs := Vector2(velocity.x, velocity.z).length()
	if run_anim:
		visual.set_state(&"idle" if hs < 0.25 else (&"walk" if hs < 2.6 else (&"run" if hs < 5.6 else &"sprint")), hs)
	# stuck detection
	if global_position.distance_to(_last_pos) < speed * delta * 0.25:
		_stuck += delta
	else:
		_stuck = 0.0
	_last_pos = global_position
	return dist

func _stand(delta: float, anim: StringName = &"idle") -> void:
	velocity.x = move_toward(velocity.x, 0.0, delta * 12.0)
	velocity.z = move_toward(velocity.z, 0.0, delta * 12.0)
	if tier == 0:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
	visual.set_state(anim, 0.0)

func _path_to(dest: Vector3, speed: float, delta: float) -> float:
	_repath -= delta
	var world: World = Game.world
	if _repath <= 0.0 or path.is_empty():
		_repath = rng.randf_range(0.6, 1.1)
		path = PackedVector3Array()
		if world != null and world.nav_ready and tier == 0:
			path = NavigationServer3D.map_get_path(world.nav_map, global_position, dest, true)
		path_i = 1 if path.size() > 1 else 0
	var aim := dest
	if path.size() > 1:
		while path_i < path.size() - 1 and Vector2(path[path_i].x - global_position.x, path[path_i].z - global_position.z).length() < 0.9:
			path_i += 1
		aim = path[path_i]
	_steer(aim, speed, delta)
	return Vector2(dest.x - global_position.x, dest.z - global_position.z).length()

# ---------------------------------------------------------------- brain
func _physics_process(delta: float) -> void:
	if tier >= 2 and state != S.FIGHT:
		return
	_scream_cd = maxf(0.0, _scream_cd - delta)
	alert = maxf(0.0, alert - delta * 0.04)
	if state == S.DEAD:
		_dead_t += delta
		if tier == 0:
			_tick_down(delta)
		return
	if vehicle != null:
		_seat_align()
		if not alive:
			return
		state = S.SEATED
		_seated(delta)
		return
	if down:
		_tick_down(delta)
		if not down:
			_resume_after_down()
		return
	if state == S.SEATED:
		state = S.IDLE
	if _dodge_t > 0.0:
		_dodge_t -= delta
		_steer(global_position + _dodge_dir * 3.0, 6.2, delta)
		if _dodge_t <= 0.0 and not is_cop() and not brave and state != S.FLEE:
			flee(threat_pos)
			_timer = rng.randf_range(4.0, 7.0)
		return
	match state:
		S.IDLE: _idle(delta)
		S.WALK: _walk(delta)
		S.AREA: _area(delta)
		S.GOTO: _goto(delta)
		S.FLEE: _flee(delta)
		S.COWER: _cower(delta)
		S.FIGHT: _fight(delta)
		S.CALL: _call(delta)
		S.STAFF: _staff(delta)
		S.POSE: _pose(delta)
	# notice a gun pointed at us
	_think -= delta
	if _think <= 0.0 and tier == 0:
		_think = 0.35
		var pl: Player = Game.player
		if pl != null and pl.alive and pl.aiming and pl.gunner.is_gun() and state != S.FIGHT:
			var d := pl.global_position.distance_to(global_position)
			if d < 16.0 and Game.cam != null:
				var to_me := (chest_position() - Game.cam.cam.global_position).normalized()
				if to_me.dot(Game.cam.forward()) > 0.985 and can_see(pl):
					if is_cop():
						Events.crime.emit(&"threaten_cop", global_position, {"victim": self})
						fight(pl)
					else:
						threatened(pl)
		# a vehicle bearing down on us: get out of the way
		for n in get_tree().get_nodes_in_group(&"vehicles"):
			var v := n as Vehicle
			var sp := v.linear_velocity.length()
			if sp < 5.0:
				continue
			var rel := global_position - v.global_position
			var ahead := rel.dot(v.linear_velocity / sp)
			if ahead < 0.0 or ahead > sp * 1.1 + 3.0:
				continue
			var lateral := (rel - (v.linear_velocity / sp) * ahead).length()
			if lateral < v.half_width + 0.9 and absf(rel.y) < 2.5:
				dodge(v.linear_velocity, v.global_position)
				break

func _resume_after_down() -> void:
	if not alive:
		return
	if _after_down == S.FIGHT and target != null:
		fight(target)
	elif alert > 0.5:
		flee(threat_pos)
	else:
		calm()
	_after_down = S.FLEE

func _seated(_delta: float) -> void:
	visual.upper = &""
	# police passengers / drivers shoot from their vehicle at a wanted player (drive-by)
	if is_cop() and Game.wanted != null and Game.wanted.level >= 2 and Game.player != null:
		var pl: Player = Game.player
		if pl.alive and can_see(pl) and global_position.distance_to(pl.global_position) < 38.0 and seat != 0:
			if gunner.weapon_id == &"unarmed" and armed != &"":
				gunner.equip(armed, true)
			gunner.aiming = true
			gunner.driveby = true
			visual.upper = &"aim_one"
			gunner.aim_dir = (pl.chest_position() - eye_position()).normalized()
			_burst_cd -= _delta
			if _burst_cd <= 0.0:
				gunner.fire_at(pl.chest_position() + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.6), rng.randf_range(-1, 1)) * 0.6)
				_burst += 1
				_burst_cd = 0.14 if _burst % 4 != 0 else rng.randf_range(0.8, 1.6)
		else:
			gunner.aiming = false

func _idle(delta: float) -> void:
	_stand(delta)
	_wait -= delta
	if _wait <= 0.0:
		_wait = rng.randf_range(2.0, 6.0)
		if graph_at >= 0:
			state = S.WALK
		elif not home_area.is_empty():
			state = S.AREA

func _walk(delta: float) -> void:
	var peds: PedManager = Game.peds
	if peds == null or peds.graph == null or graph_at < 0:
		_stand(delta)
		return
	var g: PedGraph = peds.graph
	if not has_goal:
		var nx: Array = g.next(graph_at, graph_from, rng)
		graph_from = graph_at
		graph_at = int(nx[0])
		graph_edge = int(nx[1])
		var a := g.pts[graph_from]
		var b := g.pts[graph_at]
		var side := (b - a).cross(Vector3.UP).normalized()
		goal = b + side * _lane_offset * (0.4 if graph_edge == PedGraph.T_CROSS else 1.0)
		has_goal = true
		move_speed = rng.randf_range(1.25, 1.75)
		_wait = 0.0
		if graph_edge == PedGraph.T_CROSS:
			_wait = 0.01     # check traffic before stepping out
	if _wait > 0.0:
		# wait at the kerb while cars are passing
		if _road_busy(g.pts[graph_from], g.pts[graph_at]) and _wait < 7.0:
			_wait += delta
			_stand(delta)
			return
		_wait = 0.0
	var d := _steer(goal, move_speed * (1.35 if graph_edge == PedGraph.T_CROSS else 1.0), delta)
	if d < 0.8 or _stuck > 2.5:
		has_goal = false
		_stuck = 0.0
		if rng.randf() < 0.06:
			state = S.IDLE
			_wait = rng.randf_range(2.0, 7.0)
			visual.set_state([&"idle", &"phone", &"talk"][rng.randi() % 3])

func _road_busy(a: Vector3, b: Vector3) -> bool:
	var mid := (a + b) * 0.5
	for n in get_tree().get_nodes_in_group(&"vehicles"):
		var v := n as Vehicle
		if v.linear_velocity.length() < 2.5:
			continue
		var to := mid - v.global_position
		var dist := to.length()
		if dist < 16.0 and to.normalized().dot(v.linear_velocity.normalized()) > 0.6:
			return true
	return false

func _area(delta: float) -> void:
	if not has_goal:
		var r: Rect2 = home_area["rect"]
		goal = Vector3(rng.randf_range(r.position.x, r.end.x), float(home_area.get("y", 0.15)), rng.randf_range(r.position.y, r.end.y))
		has_goal = true
		move_speed = rng.randf_range(1.1, 1.6)
	var d := _steer(goal, move_speed, delta)
	if d < 1.0 or _stuck > 2.0:
		has_goal = false
		_stuck = 0.0
		if rng.randf() < 0.5:
			state = S.IDLE
			_wait = rng.randf_range(3.0, 10.0)
			visual.set_state([&"idle", &"phone", &"talk", &"idle"][rng.randi() % 4])

func _goto(delta: float) -> void:
	if not has_goal:
		calm()
		return
	if enter_vehicle != null:
		if not is_instance_valid(enter_vehicle) or enter_vehicle.destroyed or enter_vehicle.seats[enter_seat]["occupant"] != null:
			enter_vehicle = null
			has_goal = false
			calm()
			return
		goal = enter_vehicle.door_position(enter_seat)
	var d := _path_to(goal, move_speed, delta)
	if enter_vehicle != null:
		if d < 1.7 or (_stuck > 1.5 and d < 4.0):
			var v := enter_vehicle
			enter_vehicle = null
			has_goal = false
			gunner.aiming = false
			v.seat_character(enter_seat, self)
			state = S.SEATED
		return
	if d < 1.2:
		has_goal = false
		_stand(delta)
		if is_cop():
			state = S.IDLE
			_wait = 3.0
		else:
			calm()

func _flee(delta: float) -> void:
	_timer -= delta
	var away := global_position - threat_pos
	away.y = 0.0
	var far := away.length() > 70.0
	if _timer <= 0.0 or far:
		calm()
		return
	_repath -= delta
	if _repath <= 0.0 or not has_goal:
		_repath = 1.6
		var dirv := away.normalized() if away.length() > 0.5 else Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		dirv = dirv.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6))
		goal = global_position + dirv * 22.0
		has_goal = true
		path = PackedVector3Array()
	var sp := 5.6 if tier == 0 else 5.0
	_path_to(goal, sp, delta)
	if _stuck > 0.8:
		has_goal = false
		_stuck = 0.0
		threat_pos = global_position + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 3.0

func _cower(delta: float) -> void:
	_timer -= delta
	_stand(delta, &"hands_up" if (role == &"staff" or rng.seed % 2 != 0) else &"cower")
	var pl: Player = Game.player
	if pl != null:
		turn_toward(pl.global_position - global_position, delta, 4.0)
	if _timer <= 0.0:
		if role == &"staff":
			calm()
		else:
			flee(threat_pos)

func _call(delta: float) -> void:
	_timer -= delta
	var away := global_position - threat_pos
	away.y = 0.0
	if away.length() < 18.0:
		_steer(global_position + away.normalized() * 6.0, 2.4, delta, false)
	else:
		_stand(delta, &"phone_call")
	visual.state = &"phone_call"
	visual.upper = &""
	if _timer <= 0.0:
		if is_witness_calling and Game.wanted != null:
			Game.wanted.witness_report(witnessed, self)
		is_witness_calling = false
		flee(threat_pos)

func _staff(delta: float) -> void:
	if post != Vector3.ZERO and Vector2(global_position.x - post.x, global_position.z - post.z).length() > 0.8:
		_path_to(post, 1.7, delta)
		return
	_stand(delta)
	set_face_yaw(lerp_angle(face_yaw, staff_yaw, clampf(delta * 3.0, 0.0, 1.0)))

func _fight(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		calm()
		return
	var now := Game.clock
	var sees := can_see(target)
	var tpos := target.global_position
	if sees:
		last_seen_target = now
		last_known = tpos
	var dist := global_position.distance_to(tpos)
	var has_gun := gunner.is_gun()
	# civilians give up quickly, everyone gives up on a target that is gone
	if not is_cop() and (now - last_seen_target > 9.0 or dist > 70.0):
		calm()
		return
	_react -= delta
	# police arrest a suspect who is not a lethal threat instead of opening fire
	if is_cop() and target.is_player and Game.wanted != null and not Game.wanted.police_may_shoot(self):
		_arrest(delta, sees, dist, tpos)
		return
	if not has_gun:
		# melee: close in and swing
		gunner.aiming = false
		visual.upper = &""
		if dist > 1.5:
			_path_to(tpos, 4.6, delta)
		else:
			_stand(delta)
			turn_toward(tpos - global_position, delta, 12.0)
			if _react <= 0.0 and gunner.can_fire():
				gunner.melee(rng.randf() < 0.2)
				_react = rng.randf_range(0.5, 1.1)
		return
	var want: float = minf(float(gunner.data.get("range", 40.0)) * 0.5, 24.0 if not is_cop() else 20.0)
	_crouch_t -= delta
	if sees and dist < want + 12.0:
		# hold position (or the assigned cover spot), aim and fire in bursts
		var spot: Vector3 = cover_pos if cover_pos != null else global_position
		if cover_pos != null and global_position.distance_to(spot) > 1.5:
			_path_to(spot, 4.8, delta)
		elif dist < 6.0 and not is_cop():
			_steer(global_position + (global_position - tpos).normalized() * 4.0, 3.0, delta)
		else:
			_strafe -= delta
			if _strafe < -2.0:
				_strafe = rng.randf_range(0.5, 1.2)
			if _strafe > 0.0 and cover_pos == null:
				var side := (tpos - global_position).cross(Vector3.UP).normalized() * (1.0 if rng.seed % 2 == 0 else -1.0)
				_steer(global_position + side * 3.0, 2.0, delta, false)
			else:
				_stand(delta, &"crouch_idle" if crouched else &"idle")
		var aim_at := target.chest_position()
		if target.vehicle != null:
			aim_at = target.global_position + Vector3(0, 0.3, 0)
		set_face_yaw(lerp_angle(face_yaw, atan2(-(aim_at.x - global_position.x), -(aim_at.z - global_position.z)), clampf(delta * 10.0, 0.0, 1.0)))
		gunner.aiming = true
		gunner.aim_dir = (aim_at - eye_position()).normalized()
		visual.upper = &"aim_pistol" if gunner.hold() == &"pistol" else &"aim_rifle"
		visual.aim_pitch = asin(clampf(gunner.aim_dir.y, -0.9, 0.9))
		var allowed := true
		if is_cop() and Game.wanted != null:
			allowed = Game.wanted.police_may_shoot(self)
		_burst_cd -= delta
		if allowed and _react <= 0.0 and _burst_cd <= 0.0 and gunner.can_fire():
			var miss := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.7), rng.randf_range(-1, 1)) * (0.25 + dist * 0.012)
			if gunner.fire_at(aim_at + miss):
				_burst += 1
				var auto := bool(gunner.data.get("auto", false))
				var per := 3 + rng.randi() % 4 if auto else 1 + rng.randi() % 2
				if _burst >= per:
					_burst = 0
					_burst_cd = rng.randf_range(0.7, 1.6)
				else:
					_burst_cd = 0.0 if auto else rng.randf_range(0.28, 0.5)
		# duck while reloading or right after being hit
		var hurt_recent := now - last_damage_time < 1.2
		if (gunner.reload_left > 0.0 or hurt_recent) and _crouch_t <= 0.0 and rng.randf() < 0.6:
			_crouch_t = rng.randf_range(1.4, 2.8)
		set_crouched(_crouch_t > 0.0)
	else:
		# lost sight: push toward the last known position
		gunner.aiming = false
		visual.upper = &"hold_rifle" if gunner.hold() == &"rifle" else &""
		set_crouched(false)
		var dd := _path_to(last_known, 5.2 if is_cop() else 4.4, delta)
		if dd < 2.0 and not sees:
			_stand(delta)
			if is_cop():
				# look around
				set_face_yaw(face_yaw + delta * 1.8)

func _arrest(delta: float, sees: bool, dist: float, tpos: Vector3) -> void:
	set_crouched(false)
	var levelled := sees and dist < 16.0 and gunner.is_gun()
	gunner.aiming = levelled
	if levelled:
		var aim_at := target.chest_position()
		gunner.aim_dir = (aim_at - eye_position()).normalized()
		visual.upper = &"aim_pistol" if gunner.hold() == &"pistol" else &"aim_rifle"
		visual.aim_pitch = asin(clampf(gunner.aim_dir.y, -0.9, 0.9))
	else:
		visual.upper = &""
	if dist > 1.9 or not sees:
		_path_to(tpos if sees else last_known, 5.6, delta)
	else:
		_stand(delta)
	if sees and dist < 9.0:
		set_face_yaw(lerp_angle(face_yaw, atan2(-(tpos.x - global_position.x), -(tpos.z - global_position.z)), clampf(delta * 10.0, 0.0, 1.0)))
	if sees and dist < 2.6:
		Game.wanted.arrest_tick(self, delta)
