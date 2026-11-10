extends CharacterBody3D
## Player controller: on-foot locomotion, cover, stealth, traversal, swimming/diving, parachute, vehicles, combat.

const Humanoid := preload("res://gta/code/player/humanoid.gd")
const Weapons := preload("res://gta/code/weapons/weapons.gd")
const Defs := preload("res://gta/code/core/defs.gd")

var model
var weapons
var shape: CapsuleShape3D
var col: CollisionShape3D

var health := 100.0
var max_health := 100.0
var armor := 0.0
var stamina := 1.0
var breath := 1.0
var state := "ground"     # ground, mantle, swim, ladder, cover, vehicle, enter, chute, ragdoll, dead, busted, passenger
var vehicle = null
var crouching := false
var stealth := false
var aiming := false
var sprinting := false
var blocking := false
var facing := 0.0
var look := {"female": false, "skin": 1, "hair_col": 1, "hair": "Hair_Short", "beard": false, "hat": "None", "hat_col": Color(0.7, 0.15, 0.12), "glasses": false,
	"shirt": Color(0.12, 0.17, 0.33), "long_sleeve": true, "jacket": true, "pants": Color(0.2, 0.3, 0.5), "shorts": false, "shoes": Color(0.92, 0.92, 0.9),
	"vest": false, "pack": false, "scuba": false}
var has_chute := false
var scuba := false
var noise := 0.0
var detect_mult := 1.0
var cover := {}
var ladder := {}
var model_visible := true
var interact_cur = null
var near_vehicle = null
var _state_t := 0.0
var _air_t := 0.0
var _fall_v := 0.0
var _rag_t := 0.0
var _step_ph := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _enter_from := Vector3.ZERO
var _enter_jack := false
var _roll_t := 0.0
var _roll_dir := Vector3.ZERO
var _invuln := 0.0
var _regen_t := 0.0
var _canopy: Node3D
var _peek := 0.0
var _cover_side := 1.0
var passenger_of = null
var passenger_off := Vector3.ZERO
var last_hurt_by = null
var _drown_t := 0.0
var _last_vehicle = null
var wheel_open := false
var input_locked := false
var cash_on_death := 0


func _ready() -> void:
	collision_layer = G.L_CHAR
	collision_mask = G.L_WORLD | G.L_VEH | G.L_PROP | G.L_CHAR
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.35
	col = CollisionShape3D.new()
	shape = CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.8
	col.shape = shape
	col.position.y = 0.9
	add_child(col)
	model = Node3D.new()
	model.set_script(Humanoid)
	model.look = look
	add_child(model)
	weapons = Node.new()
	weapons.set_script(Weapons)
	weapons.body = self
	weapons.model = model
	weapons.is_player = true
	add_child(weapons)
	add_to_group("player")


func spawn_initial() -> void:
	var p: Vector3 = G.world.locations.get("SafehouseInside", Vector3(0, 1, 0))
	global_position = p + Vector3(0, 0.3, 0.0)
	facing = PI
	weapons.give("pistol", 60)
	weapons.select("fists")
	if G.cam:
		G.cam.yaw = PI


func teleport(p: Vector3, yaw = null) -> void:
	if vehicle and state == "vehicle":
		vehicle.global_position = p + Vector3(0, 0.8, 0)
		vehicle.linear_velocity = Vector3.ZERO
		vehicle.angular_velocity = Vector3.ZERO
		if yaw != null:
			vehicle.global_rotation = Vector3(0, yaw, 0)
		return
	if state in ["passenger", "ladder", "cover", "chute", "swim", "mantle"]:
		_leave_special()
	global_position = p + Vector3(0, 0.1, 0)
	velocity = Vector3.ZERO
	if yaw != null:
		facing = yaw
	if G.cam:
		G.cam.global_position = p


func _leave_special() -> void:
	passenger_of = null
	_remove_canopy()
	col.disabled = false
	model_visible = true
	state = "ground"


func set_look(l: Dictionary) -> void:
	look = l
	look["pack"] = has_chute
	look["scuba"] = scuba
	model.apply_look(look)
	if G.wanted:
		G.wanted.appearance_changed()


func move_input() -> Vector3:
	if input_locked or G.menus and G.menus.is_open():
		return Vector3.ZERO
	var v = Input.get_vector("left", "right", "fwd", "back")
	var b = Basis(Vector3.UP, G.cam.yaw)
	return (b * Vector3(v.x, 0, v.y)).limit_length(1.0)


func busy() -> bool:
	return input_locked or (G.menus != null and G.menus.is_open()) or wheel_open


# ------------------------------------------------------------------ main loop
func _physics_process(dt: float) -> void:
	_state_t += dt
	_invuln = max(0.0, _invuln - dt)
	weapons.update(dt)
	match state:
		"ground":
			_ground(dt)
		"mantle":
			var k: float = clamp(_state_t / 0.42, 0.0, 1.0)
			global_position = _mantle_from.lerp(_mantle_to, k) + Vector3(0, sin(k * PI) * 0.25, 0)
			if k >= 1.0:
				state = "ground"
				velocity = Vector3.ZERO
		"swim":
			_swim(dt)
		"ladder":
			_ladder(dt)
		"cover":
			_cover(dt)
		"vehicle":
			_in_vehicle(dt)
		"enter":
			_entering(dt)
		"chute":
			_chute(dt)
		"ragdoll":
			_ragdoll(dt)
		"passenger":
			if passenger_of and is_instance_valid(passenger_of):
				global_position = passenger_of.to_global(passenger_off)
			else:
				_leave_special()
		"dead", "busted":
			velocity.x = move_toward(velocity.x, 0, dt * 8)
			velocity.z = move_toward(velocity.z, 0, dt * 8)
			velocity.y -= 14.0 * dt
			move_and_slide()
			if _state_t > 4.5:
				_respawn()
	_post(dt)


func _post(dt: float) -> void:
	# passive regen to 50% and stamina
	_regen_t += dt
	if state not in ["dead", "busted"] and health < max_health * 0.5 and _regen_t > 6.0:
		health = min(max_health * 0.5, health + dt * 2.0)
	var smax = 1.0
	if sprinting and velocity.length() > 5.0:
		var drain = lerpf(0.11, 0.05, G.skills.level("stamina") if G.skills else 0.0)
		stamina = max(0.0, stamina - dt * drain)
		if G.skills:
			G.skills.gain("stamina", dt * 0.0025)
	else:
		stamina = min(smax, stamina + dt * 0.14)
	detect_mult = 1.0
	if stealth:
		detect_mult = lerpf(0.55, 0.35, G.skills.level("stealth") if G.skills else 0.0)
	elif crouching or state == "cover":
		detect_mult = 0.7
	if G.is_night():
		detect_mult *= 0.75
	if state == "vehicle":
		detect_mult = 1.0
	# interaction scan
	_scan_interact()
	if not busy() and state not in ["dead", "busted", "ragdoll", "enter"]:
		if Input.is_action_just_pressed("interact") and interact_cur != null:
			interact_cur.fn.call()
		_weapon_keys()
	# animation feed
	_animate(dt)


func _scan_interact() -> void:
	interact_cur = null
	near_vehicle = null
	if state in ["dead", "busted", "ragdoll", "enter", "passenger"]:
		return
	var p = global_position if state != "vehicle" else vehicle.global_position
	var best = 99.0
	for it in G.world.interacts:
		var d: float = it.pos.distance_to(p)
		if d < it.r and d < best and (state != "vehicle" or it.veh) and abs(it.pos.y - p.y) < 3.0:
			best = d
			interact_cur = it
	if state in ["ground", "cover"]:
		var bd = 4.2
		for v in get_tree().get_nodes_in_group("vehicles"):
			if v.dead:
				continue
			var d2: float = v.global_position.distance_to(global_position) - v._half.x
			if d2 < bd:
				bd = d2
				near_vehicle = v


func _weapon_keys() -> void:
	if state in ["swim", "ladder", "mantle"]:
		return
	if Input.is_action_just_pressed("reload"):
		weapons.reload()


func _unhandled_input(ev: InputEvent) -> void:
	if busy() or state in ["dead", "busted"]:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k: int = ev.physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			var cls: String = Defs.WHEEL_CLASSES[min(k - KEY_1, Defs.WHEEL_CLASSES.size() - 1)]
			var opts = []
			for id in weapons.owned():
				if Defs.WEAPONS[id].cls == cls:
					opts.append(id)
			if opts.size() > 0:
				var i = opts.find(weapons.cur)
				select_weapon(opts[(i + 1) % opts.size()])
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			weapons.cycle(-1)
			_check_vehicle_weapon()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			weapons.cycle(1)
			_check_vehicle_weapon()


func select_weapon(id: String) -> void:
	weapons.select(id)
	_check_vehicle_weapon()


func _check_vehicle_weapon() -> void:
	if state == "vehicle" and not Defs.WEAPONS[weapons.cur].get("driveby", false) and weapons.cur != "fists":
		G.notify("%s can't be used while driving" % Defs.WEAPONS[weapons.cur].name, 2.0)


# ------------------------------------------------------------------ on foot
func _ground(dt: float) -> void:
	var mv = move_input()
	var on_floor = is_on_floor()
	var locked = busy()
	aiming = Input.is_action_pressed("aim") and not locked and weapons.d().cls != "melee" or (Input.is_action_pressed("aim") and not locked and weapons.d().cls == "melee" and false)
	blocking = Input.is_action_pressed("block") and weapons.d().cls == "melee" and not locked
	if not locked:
		if Input.is_action_just_pressed("crouch"):
			crouching = not crouching
			stealth = false
		if Input.is_action_just_pressed("stealth"):
			stealth = not stealth
			crouching = false
			G.notify("Stealth mode" if stealth else "Stealth off", 1.2)
	sprinting = Input.is_action_pressed("sprint") and not aiming and stamina > 0.02 and mv.length() > 0.3 and not locked and not crouching and not stealth
	var sp = 4.2
	if sprinting:
		sp = lerpf(6.8, 7.8, G.skills.level("stamina") if G.skills else 0.0)
	elif stealth:
		sp = 2.0
	elif crouching:
		sp = 1.8
	elif aiming:
		sp = 2.2
	if blocking:
		sp = 1.2
	_set_crouch(crouching or stealth)
	var target = mv * sp
	# dodge roll
	if _roll_t > 0.0:
		_roll_t -= dt
		target = _roll_dir * 7.5
	var acc = 14.0 if on_floor else 2.5
	velocity.x = move_toward(velocity.x, target.x, acc * dt * max(1.0, abs(target.x - velocity.x) * 0.4))
	velocity.z = move_toward(velocity.z, target.z, acc * dt * max(1.0, abs(target.z - velocity.z) * 0.4))
	if on_floor:
		if _air_t > 0.25:
			_land()
		_air_t = 0.0
		_fall_v = 0.0
		if Input.is_action_just_pressed("jump") and not locked:
			if aiming and mv.length() > 0.2 and _roll_t <= 0.0:
				_roll_t = 0.45
				_roll_dir = mv.normalized()
				_invuln = 0.35
				model.play("grab", 0.45)
			elif not _try_mantle(2.3):
				velocity.y = 6.4
				crouching = false
				stealth = false
	else:
		_air_t += dt
		velocity.y -= 14.0 * dt
		_fall_v = min(_fall_v, velocity.y)
		if _air_t > 0.2 and Input.is_action_just_pressed("jump") and not locked:
			if has_chute and _air_t > 0.7 and global_position.y - G.ground_y(global_position.x, global_position.z, global_position.y) > 12.0:
				_open_chute()
				return
			_try_mantle(2.3)
		if _air_t > 1.1 and has_chute and G.hud:
			G.hud.hint("SPACE — open parachute")
	move_and_slide()
	# push light props
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		var o = c.get_collider()
		if o is RigidBody3D and o.mass < 200.0:
			o.apply_central_impulse(-c.get_normal() * 3.0)
	# facing
	if aiming or (weapons.cd > 0.0 and weapons.is_gun()):
		facing = lerp_angle(facing, G.cam.yaw, clamp(dt * 18.0, 0.0, 1.0))
	elif mv.length() > 0.1:
		facing = lerp_angle(facing, atan2(-mv.x, -mv.z), clamp(dt * 11.0, 0.0, 1.0))
	rotation.y = facing
	noise = 0.0
	var hs = Vector2(velocity.x, velocity.z).length()
	if hs > 0.5 and on_floor:
		noise = 16.0 if sprinting else (2.5 if stealth else (4.0 if crouching else 9.0))
		if stealth and G.skills:
			noise *= lerpf(1.0, 0.5, G.skills.level("stealth"))
			G.skills.gain("stealth", dt * 0.002)
		_step_ph += hs * dt
		if _step_ph > 1.5:
			_step_ph = 0.0
			G.audio.play3d("step", global_position, -16.0 if stealth else -9.0, G.rng.randf_range(0.85, 1.15))
	# water entry
	if G.in_water(global_position + Vector3(0, 1.15, 0)):
		_enter_water()
		return
	if not locked:
		_combat_input()
		if Input.is_action_just_pressed("enter"):
			_try_enter_vehicle()
		if Input.is_action_just_pressed("cover"):
			_try_cover()
		_check_ladder(mv)


func _set_crouch(c: bool) -> void:
	var h = 1.2 if c else 1.8
	if abs(shape.height - h) > 0.01:
		if not c and G.ray(global_position + Vector3(0, 1.0, 0), global_position + Vector3(0, 2.0, 0), G.L_WORLD):
			return
		shape.height = h
		col.position.y = h / 2.0


func _land() -> void:
	var v = -_fall_v
	if v > 13.0:
		var dmg = (v - 13.0) * 7.0
		if G.skills:
			dmg *= lerpf(1.0, 0.7, G.skills.level("strength"))
		damage(dmg, null, global_position, "fall")
		G.cam.shake(0.4)
		if v > 19.0 and health > 0.0:
			start_ragdoll(Vector3(velocity.x, 0, velocity.z) * 0.5)
	elif v > 5.0:
		G.audio.play3d("thud", global_position, -8.0)
		if G.extras:
			G.extras.on_player_land(v)


func _try_mantle(max_h: float) -> bool:
	var fwd = -Basis(Vector3.UP, facing).z
	var feet = global_position
	var wall = G.ray(feet + Vector3(0, 0.45, 0), feet + Vector3(0, 0.45, 0) + fwd * 0.95, G.L_WORLD | G.L_PROP | G.L_VEH, [get_rid()])
	if wall.is_empty():
		wall = G.ray(feet + Vector3(0, 1.3, 0), feet + Vector3(0, 1.3, 0) + fwd * 0.95, G.L_WORLD | G.L_PROP | G.L_VEH, [get_rid()])
	if wall.is_empty():
		return false
	var top_from: Vector3 = wall.position + fwd * 0.4 + Vector3(0, max_h + 0.6 - (wall.position.y - feet.y), 0)
	var top = G.ray(top_from, top_from - Vector3(0, max_h + 0.5, 0), G.L_WORLD | G.L_PROP | G.L_VEH, [get_rid()])
	if top.is_empty():
		return false
	var h: float = top.position.y - feet.y
	if h < 0.45 or h > max_h:
		return false
	if G.ray(top.position + Vector3(0, 0.3, 0), top.position + Vector3(0, 1.7, 0), G.L_WORLD, [get_rid()]):
		return false
	_mantle_from = global_position
	_mantle_to = top.position + Vector3(0, 0.05, 0)
	state = "mantle"
	_state_t = 0.0
	model.play("grab", 0.42)
	crouching = false
	return true


func _check_ladder(mv: Vector3) -> void:
	for l in G.world.ladders:
		var base: Vector3 = l.pos
		if G.dist2d(base, global_position) < 1.1 and abs(global_position.y - base.y) < 1.2 and mv.dot(l.dir) > 0.4:
			ladder = l
			ladder["up"] = true
			state = "ladder"
			_state_t = 0.0
			global_position = Vector3(base.x, global_position.y, base.z) + l.dir * 0.12
			facing = atan2(-l.dir.x, -l.dir.z)
			return
		var top: Vector3 = l.top
		if G.dist2d(top, global_position) < 1.3 and abs(global_position.y - top.y) < 1.0 and mv.dot(-l.dir) > 0.4:
			ladder = l
			state = "ladder"
			_state_t = 0.0
			global_position = Vector3(base.x, top.y - 0.6, base.z) + l.dir * 0.12
			facing = atan2(-l.dir.x, -l.dir.z)
			return


func _ladder(dt: float) -> void:
	var v = Input.get_axis("back", "fwd") if not busy() else 0.0
	velocity = Vector3(0, v * 2.6, 0)
	global_position.y += v * 2.6 * dt
	rotation.y = facing
	var base: Vector3 = ladder.pos
	var top: Vector3 = ladder.top
	if global_position.y >= top.y - 0.4:
		global_position = top
		state = "ground"
	elif global_position.y <= base.y - 0.05 and v < 0.0:
		state = "ground"
	elif Input.is_action_just_pressed("jump"):
		state = "ground"
		velocity = -ladder.dir * 3.0 + Vector3(0, 3, 0)


# ------------------------------------------------------------------ cover
func _try_cover() -> void:
	var fwd = -Basis(Vector3.UP, facing).z
	var feet = global_position
	var best = {}
	for a in [0.0, 0.6, -0.6, 1.2, -1.2, 2.2, -2.2, PI]:
		var d = fwd.rotated(Vector3.UP, a)
		var h = G.ray(feet + Vector3(0, 0.6, 0), feet + Vector3(0, 0.6, 0) + d * 1.9, G.L_WORLD | G.L_VEH | G.L_PROP, [get_rid()])
		if h and abs(h.normal.y) < 0.4:
			if best.is_empty() or feet.distance_to(h.position) < feet.distance_to(best.position):
				best = h
	if best.is_empty():
		G.notify("No cover nearby", 1.0)
		return
	var n: Vector3 = Vector3(best.normal.x, 0, best.normal.z).normalized()
	var high = not G.ray(feet + Vector3(0, 1.45, 0) + n * 0.5, feet + Vector3(0, 1.45, 0) - n * 1.6 + (best.position - feet) * Vector3(1, 0, 1), G.L_WORLD | G.L_VEH | G.L_PROP, [get_rid()]).is_empty()
	cover = {"n": n, "low": not high, "obj": best.collider}
	global_position = Vector3(best.position.x, feet.y, best.position.z) + n * 0.48
	state = "cover"
	_state_t = 0.0
	_peek = 0.0
	crouching = false
	stealth = false
	velocity = Vector3.ZERO


func _cover(dt: float) -> void:
	var n: Vector3 = cover.n
	var tang = n.cross(Vector3.UP)
	var mv = move_input()
	var locked = busy()
	aiming = Input.is_action_pressed("aim") and not locked and weapons.d().cls != "melee"
	var along = mv.dot(tang)
	if abs(along) > 0.2:
		_cover_side = sign(along)
	var feet = global_position
	# check the wall continues where we are heading
	var can_move = true
	var probe = feet + tang * _cover_side * 0.55 + Vector3(0, 0.6, 0)
	var edge = G.ray(probe + n * 0.2, probe - n * 1.0, G.L_WORLD | G.L_VEH | G.L_PROP, [get_rid()]).is_empty()
	if edge:
		can_move = false
	var pk = 0.0
	if aiming:
		pk = 1.0
	_peek = move_toward(_peek, pk, dt * 6.0)
	velocity = Vector3.ZERO
	if not aiming and abs(along) > 0.2 and can_move:
		velocity = tang * along * 2.2
	elif not aiming and abs(along) > 0.2 and edge and Input.is_action_pressed("sprint"):
		# round the corner: hop to the adjacent face
		var corner = feet + tang * _cover_side * 1.0 - n * 0.9
		var h = G.ray(corner + tang * _cover_side * 0.8 + Vector3(0, 0.6, 0), corner - tang * _cover_side * 0.6 + Vector3(0, 0.6, 0), G.L_WORLD | G.L_VEH | G.L_PROP, [get_rid()])
		if h and abs(h.normal.y) < 0.4:
			cover.n = Vector3(h.normal.x, 0, h.normal.z).normalized()
			global_position = Vector3(h.position.x, feet.y, h.position.z) + cover.n * 0.48
	velocity.y = -2.0
	move_and_slide()
	# keep attached
	var back = G.ray(global_position + Vector3(0, 0.6, 0), global_position + Vector3(0, 0.6, 0) - n * 1.2, G.L_WORLD | G.L_VEH | G.L_PROP, [get_rid()])
	if back.is_empty():
		state = "ground"
		return
	facing = lerp_angle(facing, G.cam.yaw if aiming else atan2(-n.x, -n.z), clamp(dt * 14.0, 0.0, 1.0))
	rotation.y = facing
	# pop-out offset for high cover
	if not cover.low and edge:
		var off = tang * _cover_side * 0.75 * _peek
		model.position = model.position.lerp(global_basis.inverse() * off, clamp(dt * 12.0, 0.0, 1.0))
	else:
		model.position = model.position.lerp(Vector3.ZERO, clamp(dt * 12.0, 0.0, 1.0))
	if not locked:
		if weapons.is_gun() or weapons.d().cls == "thrown":
			var auto: bool = weapons.d().get("auto", false)
			var want: bool = Input.is_action_pressed("fire") if auto else Input.is_action_just_pressed("fire")
			if want:
				if aiming:
					weapons.try_fire(G.cam.aim_point())
				else:
					# blind fire: reduced accuracy over / around cover
					weapons.inaccuracy = 7.0
					var tp = global_position + Vector3(0, 1.3, 0) - n * 30.0 + Vector3(G.rng.randf_range(-3, 3), G.rng.randf_range(-1, 2), G.rng.randf_range(-3, 3))
					weapons.try_fire(tp)
					weapons.inaccuracy = 0.0
		if Input.is_action_just_pressed("cover") or Input.is_action_just_pressed("jump") or mv.dot(n) > 0.6:
			state = "ground"
			model.position = Vector3.ZERO
			if Input.is_action_just_pressed("jump"):
				_try_mantle(1.6)
		if Input.is_action_just_pressed("enter"):
			state = "ground"
			model.position = Vector3.ZERO
			_try_enter_vehicle()
	if G.in_water(global_position + Vector3(0, 1.15, 0)):
		_enter_water()


# ------------------------------------------------------------------ combat
func _combat_input() -> void:
	var w: Dictionary = weapons.d()
	if w.cls == "melee":
		if Input.is_action_just_pressed("fire"):
			weapons.try_fire(Vector3.ZERO, [], false, Input.is_action_pressed("aim"))
			noise = max(noise, 6.0)
		elif Input.is_action_just_pressed("heavy"):
			weapons.try_fire(Vector3.ZERO, [], false, true)
		if blocking:
			model.play("block", 0.2)
	else:
		var auto: bool = w.get("auto", false)
		var want: bool = Input.is_action_pressed("fire") if auto else Input.is_action_just_pressed("fire")
		if want:
			weapons.try_fire(G.cam.aim_point())
		elif Input.is_action_just_pressed("heavy"):
			# melee shove with the weapon
			var cur: String = weapons.cur
			weapons.cur = "fists"
			weapons.try_fire(Vector3.ZERO, [], false, true)
			weapons.cur = cur
	if Input.is_action_just_pressed("grenade") and weapons.has("grenade") and weapons.cd <= 0.0:
		var cur2: String = weapons.cur
		weapons.cur = "grenade"
		weapons.try_fire(G.cam.aim_point())
		weapons.cur = cur2
		weapons.cd = 0.8


func damage(amount: float, from = null, pos := Vector3.ZERO, kind := "bullet") -> void:
	if state in ["dead", "busted"] or _invuln > 0.0:
		return
	if G.cheats.god:
		return
	var a = amount
	if state == "vehicle" and kind == "bullet":
		a *= 0.35
	if blocking and kind.begins_with("melee"):
		a *= 0.3
		G.audio.play3d("thud", global_position, -6.0)
	if kind in ["bullet", "explosion"] and armor > 0.0:
		var ab: float = min(armor, a * 0.75)
		armor -= ab
		a -= ab
	if G.skills and kind.begins_with("melee"):
		a *= lerpf(1.0, 0.75, G.skills.level("strength"))
	health -= a
	_regen_t = 0.0
	last_hurt_by = from
	if G.hud:
		G.hud.hurt(a, pos)
	G.cam.shake(clamp(a / 60.0, 0.05, 0.6))
	if kind != "fall" and kind != "drown":
		model.play("hit", 0.25)
	if health <= 0.0:
		die()
	elif kind in ["explosion", "melee_heavy"] and a > 18.0 and state in ["ground", "cover"]:
		start_ragdoll(((global_position - pos) * Vector3(1, 0, 1)).normalized() * 6.0 + Vector3(0, 4, 0))


func is_head(p: Vector3) -> bool:
	return p.y - global_position.y > 1.5


func hit_by_vehicle(veh, vel: Vector3) -> void:
	if state in ["vehicle", "enter", "dead", "busted", "passenger", "ragdoll"] or _invuln > 0.0 or veh == vehicle:
		return
	var s = vel.length()
	if s < 3.5:
		return
	_invuln = 0.6
	damage((s - 3.0) * 4.5, veh.driver if typeof(veh.driver) != TYPE_STRING else null, veh.global_position, "vehicle")
	if health > 0.0:
		start_ragdoll(vel * 0.7 + Vector3(0, 3.5, 0))


func vehicle_impact(dv: float) -> void:
	if dv > 13.0:
		damage((dv - 13.0) * 2.2, null, global_position, "crash")
	if vehicle and vehicle.kind == "bike" and dv > 9.0 and state == "vehicle":
		var v: Vector3 = vehicle.last_vel
		_exit_vehicle(true)
		start_ragdoll(v * 0.8 + Vector3(0, 4, 0))


func start_ragdoll(v: Vector3) -> void:
	if state in ["dead", "busted"]:
		return
	if state == "cover":
		model.position = Vector3.ZERO
	_remove_canopy()
	state = "ragdoll"
	_state_t = 0.0
	_rag_t = 0.0
	velocity = v
	aiming = false


func _ragdoll(dt: float) -> void:
	velocity.y -= 14.0 * dt
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0, dt * 9.0)
		velocity.z = move_toward(velocity.z, 0, dt * 9.0)
		_rag_t += dt
	move_and_slide()
	if G.in_water(global_position + Vector3(0, 1.0, 0)):
		_enter_water()
		return
	if _rag_t > 1.3 and health > 0.0:
		state = "ground"
		model.rotation = Vector3.ZERO


func die() -> void:
	if state == "dead":
		return
	health = 0.0
	if state == "vehicle":
		_exit_vehicle(true)
	_remove_canopy()
	state = "dead"
	_state_t = 0.0
	aiming = false
	G.stats.wasted += 1
	G.audio.play("wasted", -2.0)
	if G.hud:
		G.hud.big_message("WASTED", Color(0.8, 0.1, 0.1))
	if G.wanted:
		G.wanted.clear()


func bust() -> void:
	if state in ["dead", "busted"]:
		return
	if state == "vehicle":
		_exit_vehicle(true)
	state = "busted"
	_state_t = 0.0
	aiming = false
	G.stats.busted += 1
	G.audio.play("busted", -2.0)
	if G.hud:
		G.hud.big_message("BUSTED", Color(0.2, 0.4, 1.0))


func _respawn() -> void:
	var was_busted = state == "busted"
	var fee: int = min(500, int(G.money * 0.1))
	G.add_money(-fee)
	if was_busted:
		for id in weapons.inv:
			weapons.inv[id].res = int(weapons.inv[id].res * 0.75)
	if G.wanted:
		G.wanted.clear()
	health = max_health
	breath = 1.0
	state = "ground"
	model.rotation = Vector3.ZERO
	col.disabled = false
	model_visible = true
	var key = "Police Station" if was_busted else "Hospital"
	var p: Vector3 = G.world.locations.get(key, Vector3(0, 1, 0))
	global_position = p + Vector3(0, 0.3, 2.5)
	velocity = Vector3.ZERO
	if G.hud:
		G.hud.fade_in()
		G.notify(("Released from custody. Fine: $%d, some ammo confiscated." if was_busted else "Discharged from St. Ember Medical. Bill: $%d.") % fee, 4.0)
	if G.env and not was_busted:
		G.env.set_hour(G.env.hour + 3.0)


# ------------------------------------------------------------------ swimming / diving
func _enter_water() -> void:
	if state == "swim":
		return
	if abs(velocity.y) > 6.0:
		G.fx.splash(global_position, true)
	else:
		G.fx.splash(global_position)
	_remove_canopy()
	state = "swim"
	_state_t = 0.0
	crouching = false
	stealth = false
	aiming = false
	velocity *= 0.4
	_set_crouch(false)
	model.position = Vector3.ZERO


func head_underwater() -> bool:
	return global_position.y + 1.55 < G.WATER_Y


func _swim(dt: float) -> void:
	var mv = move_input()
	var locked = busy()
	var surf_y = G.WATER_Y - 1.42
	var under = global_position.y < surf_y - 0.25
	var sp = 2.7
	sprinting = Input.is_action_pressed("sprint") and stamina > 0.02 and not locked
	if sprinting:
		sp = lerpf(3.6, 4.6, G.skills.level("stamina") if G.skills else 0.0)
	var target = mv * sp
	var vy = 0.0
	if not locked:
		if Input.is_action_pressed("stealth") or Input.is_action_pressed("crouch"):
			vy = -2.4
		elif Input.is_action_pressed("jump"):
			vy = 2.6
		elif under and mv.length() > 0.2:
			# swim along the camera pitch when submerged
			vy = clamp(G.cam.forward().y, -1.0, 1.0) * sp * (1.0 if Input.is_action_pressed("fwd") else 0.0)
	if vy == 0.0 and not under:
		vy = (surf_y - global_position.y) * 3.0
	elif vy == 0.0:
		vy = 0.25
	if global_position.y >= surf_y and vy > 0.0:
		vy = (surf_y - global_position.y) * 3.0
	velocity = velocity.lerp(Vector3(target.x, vy, target.z), clamp(dt * 4.0, 0.0, 1.0))
	move_and_slide()
	if mv.length() > 0.1:
		facing = lerp_angle(facing, atan2(-mv.x, -mv.z), clamp(dt * 6.0, 0.0, 1.0))
	rotation.y = facing
	# breath
	var cap = lerpf(22.0, 55.0, G.skills.level("lung") if G.skills else 0.0)
	if scuba:
		cap *= 12.0
	if head_underwater():
		breath = max(0.0, breath - dt / cap)
		if G.skills:
			G.skills.gain("lung", dt * 0.004)
		if breath <= 0.0:
			_drown_t += dt
			if _drown_t > 1.0:
				_drown_t = 0.0
				damage(12.0, null, global_position, "drown")
	else:
		breath = min(1.0, breath + dt * 0.5)
	if G.skills and velocity.length() > 1.0:
		G.skills.gain("stamina", dt * 0.002)
	# leave water: standing depth or mantle onto a ledge / pier
	if not G.in_water(global_position + Vector3(0, 1.3, 0)) and is_on_floor():
		state = "ground"
		return
	if not locked and Input.is_action_just_pressed("jump") and not under:
		if _try_mantle(3.1):
			return
	if not locked and Input.is_action_just_pressed("enter"):
		_try_enter_vehicle()


# ------------------------------------------------------------------ parachute
func _open_chute() -> void:
	state = "chute"
	_state_t = 0.0
	G.audio.play3d("chute", global_position, 0.0)
	_canopy = G.model("props/parachute")
	add_child(_canopy)
	_canopy.position = Vector3(0, 1.0, 0)
	velocity.y = max(velocity.y, -9.0)
	G.notify("W/S — glide / flare, A/D — steer", 4.0)


func _remove_canopy() -> void:
	if _canopy:
		_canopy.queue_free()
		_canopy = null


func _chute(dt: float) -> void:
	var turn = Input.get_axis("right", "left") if not busy() else 0.0
	facing += turn * dt * 1.4
	rotation.y = facing
	var flare = Input.is_action_pressed("back") and not busy()
	var fast = Input.is_action_pressed("fwd") and not busy()
	var fwd = -Basis(Vector3.UP, facing).z
	var hs = 6.0 if flare else (12.0 if fast else 9.0)
	var vs = -2.6 if flare else (-7.5 if fast else -5.0)
	velocity = velocity.lerp(fwd * hs + Vector3(0, vs, 0), clamp(dt * 2.0, 0.0, 1.0))
	if _canopy:
		_canopy.rotation.z = lerpf(_canopy.rotation.z, turn * 0.35, clamp(dt * 4.0, 0.0, 1.0))
		_canopy.rotation.x = lerpf(_canopy.rotation.x, 0.25 if flare else 0.0, clamp(dt * 4.0, 0.0, 1.0))
	var pre_v = velocity.y
	move_and_slide()
	if G.in_water(global_position + Vector3(0, 1.15, 0)):
		_enter_water()
		return
	if is_on_floor() or is_on_wall():
		_remove_canopy()
		state = "ground"
		has_chute = false
		look["pack"] = false
		model.apply_look(look)
		if -pre_v > 6.0:
			damage((-pre_v - 6.0) * 9.0, null, global_position, "fall")
			G.notify("Hard landing!", 2.0)
		else:
			G.notify("Clean landing", 2.0)
			if G.extras:
				G.extras.on_chute_land(global_position)
	if Input.is_action_just_pressed("enter") and not busy():
		_remove_canopy()
		state = "ground"


func give_chute() -> void:
	has_chute = true
	look["pack"] = true
	model.apply_look(look)


func set_scuba(on: bool) -> void:
	scuba = on
	look["scuba"] = on
	model.apply_look(look)


# ------------------------------------------------------------------ vehicles
func _try_enter_vehicle() -> void:
	var v = near_vehicle
	if v == null or not is_instance_valid(v) or v.dead:
		return
	if G.extras and G.extras.try_board(v):
		return
	vehicle = v
	state = "enter"
	_state_t = 0.0
	_enter_from = global_position
	_enter_jack = v.has_ai_driver()
	aiming = false
	crouching = false
	stealth = false
	_set_crouch(false)
	col.disabled = true
	if _enter_jack:
		model.play("grab", 0.8)
		if G.traffic:
			G.traffic.carjack(v, self)
	G.audio.play3d("door", v.global_position, -4.0)


func _entering(dt: float) -> void:
	if not is_instance_valid(vehicle) or vehicle.dead:
		state = "ground"
		col.disabled = false
		vehicle = null
		return
	var dur = 0.9 if _enter_jack else 0.45
	var side = -1.0
	var door: Vector3 = vehicle.door_pos(side)
	var k: float = clamp(_state_t / dur, 0.0, 1.0)
	var a: float = clamp(k * 1.6, 0.0, 1.0)
	var b: float = clamp((k - 0.6) / 0.4, 0.0, 1.0)
	var p = _enter_from.lerp(door, a).lerp(vehicle.seat_pos() - Vector3(0, 0.4, 0), b)
	global_position = p
	var dirv: Vector3 = vehicle.global_position - global_position
	facing = lerp_angle(facing, atan2(-dirv.x, -dirv.z), clamp(dt * 10.0, 0.0, 1.0))
	rotation.y = facing
	if k >= 1.0:
		state = "vehicle"
		vehicle.set_driver(self)
		if vehicle.owner_tag != "player" and not vehicle.stolen:
			vehicle.stolen = true
			G.stats.cars_stolen += 1
		if vehicle.owner_tag == "police" and G.wanted:
			G.wanted.crime("steal_police", global_position, 2.0)
		_last_vehicle = vehicle
		model_visible = vehicle.is_open()
		G.audio.set_radio(vehicle.kind in ["car", "boat"] and not vehicle.def.get("siren", false))
		_vehicle_hint()
		if G.wanted:
			G.wanted.vehicle_changed(vehicle)


func _vehicle_hint() -> void:
	match vehicle.kind:
		"heli":
			G.notify("Helicopter: SPACE up, CTRL down, W/S pitch, A/D yaw, Q/E roll", 6.0)
		"plane":
			G.notify("Plane: SHIFT throttle up, CTRL down, S pull up / W nose down, A/D roll, Q/E rudder, SPACE brake", 7.0)
		"boat":
			G.notify("Boat: W/S throttle, A/D steer", 3.0)


func _in_vehicle(dt: float) -> void:
	var v = vehicle
	if v == null or not is_instance_valid(v):
		state = "ground"
		col.disabled = false
		model_visible = true
		vehicle = null
		return
	global_position = v.seat_pos() - Vector3(0, 0.55 if v.kind != "bike" else 0.85, 0)
	rotation.y = v.global_rotation.y
	facing = rotation.y
	velocity = v.linear_velocity
	if v.dead:
		return
	var locked = busy()
	var th = 0.0
	var steer = 0.0
	if not locked:
		th = Input.get_axis("back", "fwd")
		steer = Input.get_axis("right", "left")
	match v.kind:
		"car", "bike":
			v.in_steer = steer
			v.in_hand = Input.is_action_pressed("jump") and not locked
			if th > 0.0:
				if v.speed < -1.5:
					v.in_brake = 1.0
					v.in_throttle = 0.0
				else:
					v.in_throttle = th
					v.in_brake = 0.0
			elif th < 0.0:
				if v.speed > 1.5:
					v.in_brake = 1.0
					v.in_throttle = 0.0
				else:
					v.in_throttle = th
					v.in_brake = 0.0
			else:
				v.in_throttle = 0.0
				v.in_brake = 0.0
			if G.skills and abs(v.speed) > 12.0:
				G.skills.gain("driving", dt * 0.0012)
		"boat":
			v.in_throttle = th
			v.in_steer = steer
		"heli":
			v.in_pitch = th
			v.in_yaw = steer
			v.in_roll = (Input.get_axis("roll_l", "roll_r") if not locked else 0.0)
			v.in_lift = 0.0
			if not locked:
				if Input.is_action_pressed("jump") or Input.is_action_pressed("sprint"):
					v.in_lift = 1.0
				elif Input.is_action_pressed("descend"):
					v.in_lift = -1.0
			if G.skills and v.global_position.y > 8.0:
				G.skills.gain("flying", dt * 0.002)
		"plane":
			v.in_pitch = -th
			v.in_roll = -steer
			v.in_yaw = (Input.get_axis("roll_r", "roll_l") if not locked else 0.0)
			if v.grounded > 0:
				v.in_yaw += steer
			v.in_lift = 0.0
			v.in_brake = 1.0 if (Input.is_action_pressed("jump") and not locked) else 0.0
			if not locked:
				if Input.is_action_pressed("sprint"):
					v.in_lift = 1.0
				elif Input.is_action_pressed("descend"):
					v.in_lift = -1.0
			if G.skills and v.grounded == 0:
				G.skills.gain("flying", dt * 0.002)
	if locked:
		return
	v.horn(Input.is_action_pressed("horn"))
	if Input.is_action_just_pressed("lights"):
		v.lights_on = not v.lights_on
	if Input.is_action_just_pressed("siren"):
		v.set_siren(not v.siren_on)
	if Input.is_action_just_pressed("radio"):
		G.audio.next_station()
	if Input.is_action_just_pressed("flip") and v.kind in ["car", "bike"]:
		v.flip_upright()
	# drive-by
	aiming = Input.is_action_pressed("aim") and v.kind in ["car", "bike", "boat"]
	var w: Dictionary = weapons.d()
	if w.get("driveby", false) and v.kind in ["car", "bike", "boat"]:
		if w.cls == "thrown":
			if Input.is_action_just_pressed("fire"):
				weapons.try_fire(G.cam.aim_point(), [v.get_rid()], true)
		else:
			var auto: bool = w.get("auto", false)
			if (Input.is_action_pressed("fire") if auto else Input.is_action_just_pressed("fire")):
				weapons.try_fire(G.cam.aim_point(), [v.get_rid()], true)
	if Input.is_action_just_pressed("grenade") and weapons.has("grenade") and weapons.cd <= 0.0:
		var c2: String = weapons.cur
		weapons.cur = "grenade"
		weapons.try_fire(G.cam.aim_point(), [v.get_rid()], true)
		weapons.cur = c2
	if Input.is_action_just_pressed("enter"):
		_exit_vehicle(false)


func _exit_vehicle(forced: bool) -> void:
	var v = vehicle
	if v == null or not is_instance_valid(v):
		vehicle = null
		state = "ground"
		col.disabled = false
		model_visible = true
		return
	var sp: float = v.linear_velocity.length()
	var out: Vector3 = v.door_pos(-1.0)
	for side in [-1.0, 1.0]:
		var dp: Vector3 = v.door_pos(side)
		if G.ray(v.global_position + Vector3(0, 0.8, 0), dp + Vector3(0, 0.8, 0), G.L_WORLD | G.L_VEH, [v.get_rid()]).is_empty():
			out = dp
			break
		out = v.global_position + Vector3(0, v._half.y * 2.0 + 0.4, 0)
	v.clear_driver()
	if v.kind in ["heli", "plane"]:
		v.engine_on = v.global_position.y - G.ground_y(v.global_position.x, v.global_position.z, v.global_position.y) > 6.0
	v.owner_tag = "player" if v.owner_tag in ["traffic", "parked", ""] else v.owner_tag
	G.audio.set_radio(false)
	vehicle = null
	col.disabled = false
	model_visible = true
	global_position = out + Vector3(0, 0.15, 0)
	state = "ground"
	_air_t = 0.0
	_fall_v = 0.0
	velocity = v.linear_velocity * 0.9
	aiming = false
	if not forced and sp > 9.0 and v.kind in ["car", "bike"]:
		damage((sp - 8.0) * 1.5, null, global_position, "fall")
		if health > 0.0:
			start_ragdoll(v.linear_velocity * 0.8 + Vector3(0, 2, 0))
	if G.in_water(global_position + Vector3(0, 1.15, 0)):
		_enter_water()


func eject_from_wreck(v) -> void:
	if vehicle != v:
		return
	_exit_vehicle(true)
	damage(85.0, null, v.global_position, "explosion")
	if health > 0.0:
		start_ragdoll(Vector3(G.rng.randf_range(-4, 4), 7, G.rng.randf_range(-4, 4)))


func set_passenger(v, off: Vector3) -> void:
	passenger_of = v
	passenger_off = off
	state = "passenger"
	col.disabled = true
	model_visible = false
	aiming = false


func leave_passenger(p: Vector3) -> void:
	passenger_of = null
	col.disabled = false
	model_visible = true
	state = "ground"
	global_position = p
	velocity = Vector3.ZERO


# ------------------------------------------------------------------ animation
func _animate(dt: float) -> void:
	var m = model
	m.aiming = aiming and state in ["ground", "cover", "vehicle"]
	m.aim_pitch = G.cam.pitch if G.cam else 0.0
	m.speed = Vector2(velocity.x, velocity.z).length()
	var tilt = 0.0
	var tgt_rot = Vector3.ZERO
	match state:
		"ground", "mantle", "enter":
			if not is_on_floor() and _air_t > 0.25 and state == "ground":
				m.state = "air"
			elif crouching or stealth:
				m.state = "crouch"
			else:
				m.state = "move" if m.speed > 0.3 else "idle"
			if _roll_t > 0.0:
				m.state = "crouch"
				tgt_rot.x = -(0.45 - _roll_t) / 0.45 * TAU
		"swim":
			var under = global_position.y < G.WATER_Y - 1.7
			if m.speed > 0.5 or under:
				m.state = "swim"
				tgt_rot.x = -1.25 + clamp(velocity.y * 0.2, -0.5, 0.5)
			else:
				m.state = "tread"
		"ladder":
			m.state = "climb"
			m.speed = abs(velocity.y)
		"cover":
			m.state = "cover_low" if cover.get("low", false) and not aiming else ("cover_high" if not aiming else "idle")
		"vehicle":
			m.state = "bike" if vehicle and is_instance_valid(vehicle) and vehicle.kind == "bike" else "sit"
			m.speed = 0.0
		"chute":
			m.state = "chute"
		"ragdoll":
			m.state = "limp"
			tgt_rot.x = -PI / 2 if _rag_t > 0.0 else fmod(_state_t * 9.0, TAU)
		"dead":
			m.state = "dead"
			tgt_rot.x = -PI / 2
		"busted":
			m.state = "handsup"
		"passenger":
			m.state = "sit"
	if state == "ragdoll" and _rag_t <= 0.0:
		m.rotation.x = tgt_rot.x
	elif _roll_t > 0.0:
		m.rotation.x = tgt_rot.x
	else:
		m.rotation.x = lerp_angle(m.rotation.x, tgt_rot.x, clamp(dt * 9.0, 0.0, 1.0))
	if state in ["ragdoll", "dead"]:
		m.position.y = lerpf(m.position.y, 0.25 if (_rag_t > 0.0 or state == "dead") else 0.9, clamp(dt * 8.0, 0.0, 1.0))
	elif state == "swim" and m.state == "swim":
		m.position.y = lerpf(m.position.y, 0.9, clamp(dt * 6.0, 0.0, 1.0))
	elif state != "cover":
		m.position.y = lerpf(m.position.y, 0.0, clamp(dt * 10.0, 0.0, 1.0))
		m.position.x = lerpf(m.position.x, 0.0, clamp(dt * 10.0, 0.0, 1.0))
		m.position.z = lerpf(m.position.z, 0.0, clamp(dt * 10.0, 0.0, 1.0))
