class_name Player
extends CharacterBody3D
## Third-person player: locomotion, cover, stealth, traversal, swimming/diving, parachute, melee, firearms,
## vehicle entry/carjacking/drive-by, damage, death and arrest.

enum St {FOOT, VEHICLE, SWIM, RAGDOLL, DEAD, CHUTE, LADDER, COVER, VAULT, ROLL, ENTERING, BUSTED, RIDE}

const GRAVITY := 22.0
const WALK := 2.3
const JOG := 4.6
const SPRINT := 7.4

var state: int = St.FOOT
var rig: CharRig
var col: CollisionShape3D
var inv := Inventory.new()
var look: Dictionary = {}
var health := 100.0
var max_health := 100.0
var armor := 0.0
var stamina := 1.0
var breath := 1.0
var has_parachute := true
var scuba := false
var vehicle: Vehicle = null
var seat := 0
var facing := 0.0
var crouching := false
var aiming := false
var sprinting := false
var move_speed := 0.0
var cover_normal := Vector3.ZERO
var cover_low := false
var cover_side := 1.0
var _cover_edge_t := 0.0
var _cover_away_t := 0.0
var underwater := false
var last_shot_time := -100.0
var last_violence_time := -100.0
var last_damage_time := -100.0
var _fire_cd := 0.0
var _reload_t := 0.0
var _bloom := 0.0
var _attack_t := -1.0
var _attack_heavy := false
var _attack_hit_done := false
var _combo := 0
var _fire_hold := 0.0
var _melee_charge := 0.0
var _step_acc := 0.0
var _air_time := 0.0
var _peak_y := 0.0
var _state_t := 0.0
var _rag_vel := Vector3.ZERO
var _tween_from := Vector3.ZERO
var _tween_to := Vector3.ZERO
var _tween_dur := 0.4
var _enter_vehicle: Vehicle = null
var _enter_stage := 0
var _roll_dir := Vector3.ZERO
var ladder: Dictionary = {}
var ride_node: Node3D = null
var ride_offset := Vector3.ZERO
var ride_exit: Callable
var canopy: Node3D
var interact_target: Dictionary = {}
var _regen_t := 0.0
var _throw_pending := false
var known_look_hash := 0
var _chute_prompt := false
var _wheel_was_open := false
var _radio: AudioStreamPlayer
var _flip_hold := 0.0


func _ready() -> void:
	Game.player = self
	collision_layer = Game.L_CHAR
	collision_mask = Game.L_WORLD | Game.L_VEHICLE | Game.L_PROP | Game.L_CHAR | Game.L_SOFT
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	if look.is_empty():
		look = Data.default_player_look()
	rig = CharRig.new()
	add_child(rig)
	rig.setup(look, false)
	canopy = Assets.inst("canopy")
	canopy.visible = false
	add_child(canopy)
	inv.give("pistol", 48)
	inv.give("bat", 0)
	equip(inv.current)
	_radio = AudioStreamPlayer.new()
	_radio.bus = "Music"
	add_child(_radio)
	add_to_group("player")


# ------------------------------------------------------------------ queries
func in_vehicle() -> bool:
	return state == St.VEHICLE and vehicle != null and is_instance_valid(vehicle)


func is_swimming() -> bool:
	return state == St.SWIM


func alive() -> bool:
	return state != St.DEAD and state != St.BUSTED


func center() -> Vector3:
	if in_vehicle():
		return vehicle.global_position + Vector3.UP * 0.9
	return global_position + Vector3.UP * (0.7 if crouching else 1.2)


func velocity_now() -> Vector3:
	return vehicle.linear_velocity if in_vehicle() else velocity


func is_armed() -> bool:
	return inv.def().kind != "melee" or inv.current != "fists"


func noise_radius() -> float:
	if in_vehicle():
		return 18.0 + absf(vehicle.speed) * 0.5
	if move_speed < 0.3:
		return 0.0
	var r := 5.0 + move_speed * 1.6
	if crouching:
		r *= 0.3 * (1.0 - 0.5 * Game.skill("stealth"))
	return r


func visibility() -> float:
	## Multiplier applied to NPC sight range.
	var v := 1.0
	if crouching:
		v *= 0.6 - 0.15 * Game.skill("stealth")
	if state == St.COVER:
		v *= 0.5
	if Game.daynight and Game.daynight.night > 0.5:
		v *= 0.75
	if in_vehicle():
		v *= 1.15
	return v


func apply_look() -> void:
	rig.look = look
	rig.apply_look(false)


func equip(id: String) -> void:
	if not inv.has(id):
		return
	inv.current = id
	_reload_t = 0.0
	rig.set_weapon(inv.def(), inv.entry().mods, inv.tint_color())
	Sfx.play("equip", -10.0)
	if Game.hud:
		Game.hud.refresh_weapon()


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	_state_t += delta
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_bloom = maxf(0.0, _bloom - delta * 3.5)
	var blocked := Game.ui_blocked()
	match state:
		St.FOOT:
			_foot(delta, blocked)
		St.COVER:
			_cover(delta, blocked)
		St.SWIM:
			_swim(delta, blocked)
		St.VEHICLE:
			_in_vehicle(delta, blocked)
		St.RAGDOLL, St.DEAD, St.BUSTED:
			_ragdoll(delta)
		St.CHUTE:
			_chute(delta, blocked)
		St.LADDER:
			_ladder(delta, blocked)
		St.VAULT:
			_vault(delta)
		St.ROLL:
			_roll(delta)
		St.ENTERING:
			_entering(delta)
		St.RIDE:
			_ride(delta, blocked)
	if state != St.DEAD and state != St.BUSTED:
		_common(delta, blocked)
	# never fall out of the world
	if state != St.VEHICLE and state != St.RIDE and global_position.y < minf(City.terrain_height(global_position.x, global_position.z), 0.0) - 6.0:
		global_position.y = maxf(City.terrain_height(global_position.x, global_position.z), Game.WATER_Y) + 1.0
		velocity = Vector3.ZERO
	_animate(delta)


func _common(delta: float, blocked: bool) -> void:
	# reload timer
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			var e := inv.entry()
			var need: int = inv.mag_size() - e.mag
			var take: int = mini(need, e.reserve)
			e.mag += take
			e.reserve -= take
			if Game.hud:
				Game.hud.refresh_weapon()
	# regen to 50%
	_regen_t += delta
	if health < max_health * 0.5 and _regen_t > 8.0 and state != St.RAGDOLL:
		health = minf(max_health * 0.5, health + delta * 2.5)
	# breath
	var cap := 18.0 + 30.0 * Game.skill("lung")
	if scuba or Game.flags.scuba:
		cap = 600.0
	if underwater:
		breath = maxf(0.0, breath - delta / cap)
		Game.skill_up("lung", delta * 0.12)
		if breath <= 0.0:
			damage(delta * 9.0, global_position, null, "drown")
	else:
		breath = minf(1.0, breath + delta * 0.5)
	if blocked:
		return
	if Input.is_action_just_pressed("enter_vehicle"):
		_toggle_vehicle()
	if Input.is_action_just_pressed("interact") and not interact_target.is_empty():
		if state != St.VEHICLE or interact_target.get("vehicle_ok", false):
			var cb: Callable = interact_target.cb
			if cb.is_valid():
				cb.call()
	if Input.is_action_just_pressed("camera_toggle") and Game.cam:
		Game.cam.first_person = not Game.cam.first_person
	for i in range(8):
		if Input.is_action_just_pressed("slot_%d" % (i + 1)):
			_select_slot(i)
	if Input.is_action_just_pressed("weapon_next"):
		equip(inv.cycle(1))
	elif Input.is_action_just_pressed("weapon_prev"):
		equip(inv.cycle(-1))
	if Input.is_action_just_pressed("reload"):
		start_reload()


func _select_slot(slot: int) -> void:
	var ws := inv.slot_weapons(slot)
	if ws.is_empty():
		return
	var i := ws.find(inv.current)
	equip(ws[(i + 1) % ws.size()])


func start_reload() -> void:
	var d := inv.def()
	if d.kind == "melee" or d.kind == "thrown" or _reload_t > 0.0:
		return
	var e := inv.entry()
	if e.mag >= inv.mag_size() or e.reserve <= 0:
		return
	_reload_t = d.reload * (1.0 - 0.25 * Game.skill("shooting"))
	Sfx.play3d("reload", global_position, -4.0)


func _input_vec() -> Vector2:
	return Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_fwd", "move_back"))


func _wish_dir(iv: Vector2) -> Vector3:
	var yaw: float = Game.cam.yaw if Game.cam else facing
	var b := Basis(Vector3.UP, yaw)
	var d := b * Vector3(iv.x, 0, iv.y)
	return d.normalized() if d.length() > 0.01 else Vector3.ZERO


# ------------------------------------------------------------------ on foot
func _foot(delta: float, blocked: bool) -> void:
	var iv := Vector2.ZERO if blocked else _input_vec()
	var wish := _wish_dir(iv)
	var d := inv.def()
	aiming = not blocked and Input.is_action_pressed("aim") and d.kind != "melee"
	var blocking := not blocked and Input.is_action_pressed("aim") and d.kind == "melee"
	rig.block = 1.0 if blocking else 0.0
	if not blocked and Input.is_action_just_pressed("crouch"):
		crouching = not crouching
		if crouching:
			Game.say("Stealth mode", Color(0.6, 0.8, 1.0))
	sprinting = not blocked and Input.is_action_pressed("sprint") and iv.y < 0.3 and wish != Vector3.ZERO and not aiming and stamina > 0.05
	if sprinting:
		crouching = false
		stamina = maxf(0.0, stamina - delta / (9.0 + 16.0 * Game.skill("stamina")))
		Game.skill_up("stamina", delta * 0.1)
	else:
		stamina = minf(1.0, stamina + delta * 0.22)
	var target_speed := JOG
	if sprinting:
		target_speed = SPRINT
	elif crouching:
		target_speed = 2.0
	elif aiming or blocking:
		target_speed = WALK
	var on_floor := is_on_floor()
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.move_toward(wish * target_speed, (34.0 if on_floor else 7.0) * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if on_floor:
		if _air_time > 0.25:
			_land()
		_air_time = 0.0
		_peak_y = global_position.y
		if velocity.y < 0.0:
			velocity.y = -1.0
		if not blocked and Input.is_action_just_pressed("jump"):
			if aiming and wish != Vector3.ZERO:
				_start_roll(wish)
			elif not _try_vault(wish):
				velocity.y = 6.6
				crouching = false
	else:
		_air_time += delta
		_peak_y = maxf(_peak_y, global_position.y)
		velocity.y -= GRAVITY * delta
		_chute_prompt = has_parachute and _air_time > 0.5 and velocity.y < -6.0 and _height_above_ground() > 10.0
		if _chute_prompt and not blocked and Input.is_action_just_pressed("jump"):
			_open_chute()
			return
	move_and_slide()
	move_speed = Vector3(velocity.x, 0, velocity.z).length()
	# facing
	var cam_yaw: float = Game.cam.yaw if Game.cam else facing
	var recent_fire := Time.get_ticks_msec() * 0.001 - last_shot_time < 0.8
	if aiming or (recent_fire and d.kind != "melee"):
		facing = lerp_angle(facing, cam_yaw, clampf(delta * 18.0, 0.0, 1.0))
	elif wish != Vector3.ZERO:
		facing = lerp_angle(facing, atan2(-wish.x, -wish.z), clampf(delta * 11.0, 0.0, 1.0))
	rotation.y = facing
	# footsteps + noise
	if on_floor and move_speed > 0.8:
		_step_acc += move_speed * delta
		if _step_acc > (1.5 if sprinting else 1.25):
			_step_acc = 0.0
			var grass := City.district_name(global_position) in ["Signal Hill", "Founders Park"]
			Sfx.play3d("step_grass" if grass else "step_%d" % (randi() % 2), global_position, -16.0 if crouching else -9.0, randf_range(0.9, 1.1), 25.0)
			var nr := noise_radius()
			if nr > 3.0:
				Game.noise(global_position, nr, "steps")
			if crouching:
				Game.skill_up("stealth", 0.02)
	# water?
	if global_position.y < Game.WATER_Y - 1.0 and City.terrain_height(global_position.x, global_position.z) < Game.WATER_Y - 1.2:
		_enter_swim()
		return
	if not blocked:
		if Input.is_action_just_pressed("cover"):
			_try_cover()
		_weapon_input(delta)


func _height_above_ground() -> float:
	var hit := Game.ray(global_position + Vector3.UP * 0.5, global_position + Vector3.DOWN * 400.0, Game.L_WORLD)
	var gy := maxf(City.terrain_height(global_position.x, global_position.z), Game.WATER_Y)
	if not hit.is_empty():
		gy = maxf(gy, hit.position.y)
	return global_position.y - gy


func _land() -> void:
	var vy := -velocity.y
	var fell := _peak_y - global_position.y
	if vy > 13.0 and fell > 4.0:
		var dmg := (vy - 13.0) * 7.0
		damage(dmg, global_position, null, "fall")
		if vy > 19.0 and alive():
			knockdown(Vector3(velocity.x, 0, velocity.z) * 0.3)
	elif vy > 6.0:
		Sfx.play3d("step_0", global_position, -4.0, 0.7)
		rig.hit_t = 0.4
	Game.noise(global_position, 6.0 + vy, "steps")


# ------------------------------------------------------------------ traversal
func _try_vault(wish: Vector3) -> bool:
	var fwd := wish if wish != Vector3.ZERO else -global_basis.z
	var o := global_position
	var wall := Game.ray(o + Vector3.UP * 0.45, o + Vector3.UP * 0.45 + fwd * 0.9, Game.MASK_SOLID, [self])
	if wall.is_empty() or absf(wall.normal.y) > 0.4:
		return false
	var top_from: Vector3 = wall.position + fwd * 0.35 + Vector3.UP * 2.6
	top_from.y = o.y + 2.6
	var top := Game.ray(top_from, top_from + Vector3.DOWN * 2.3, Game.MASK_SOLID, [self])
	if top.is_empty():
		return false
	var h: float = top.position.y - o.y
	if h < 0.45 or h > 2.35 or top.normal.y < 0.7:
		return false
	var head := Game.ray(top.position + Vector3.UP * 0.1, top.position + Vector3.UP * 1.7, Game.MASK_SOLID, [self])
	if not head.is_empty():
		return false
	_tween_from = o
	_tween_to = top.position + Vector3.UP * 0.05
	_tween_dur = 0.3 + h * 0.22
	state = St.VAULT
	_state_t = 0.0
	crouching = false
	velocity = Vector3.ZERO
	Game.skill_up("stamina", 0.15)
	return true


func _vault(delta: float) -> void:
	var t := clampf(_state_t / _tween_dur, 0.0, 1.0)
	var p := _tween_from.lerp(_tween_to, smoothstep(0.3, 1.0, t))
	p.y = lerpf(_tween_from.y, _tween_to.y, smoothstep(0.0, 0.7, t))
	global_position = p
	if t >= 1.0:
		state = St.FOOT
		velocity = -global_basis.z * 2.0
		_air_time = 0.0
		_peak_y = global_position.y


func _start_roll(dir: Vector3) -> void:
	state = St.ROLL
	_state_t = 0.0
	_roll_dir = dir
	stamina = maxf(0.0, stamina - 0.12)


func _roll(delta: float) -> void:
	velocity = _roll_dir * 7.0 + Vector3(0, velocity.y - GRAVITY * delta, 0)
	move_and_slide()
	facing = atan2(-_roll_dir.x, -_roll_dir.z)
	rotation.y = facing
	if _state_t > 0.55:
		state = St.FOOT
		rig.rotation.x = 0.0


func _ladder(delta: float, blocked: bool) -> void:
	var iv := Vector2.ZERO if blocked else _input_vec()
	var top_y: float = ladder.top
	var base: Vector3 = ladder.pos
	var out: Vector3 = ladder.out
	global_position.x = base.x + out.x * 0.42
	global_position.z = base.z + out.z * 0.42
	global_position.y += -iv.y * 2.4 * delta
	rig.phase += -iv.y * delta * 7.0
	facing = atan2(out.x, out.z)
	rotation.y = facing
	velocity = Vector3.ZERO
	if global_position.y >= top_y - 0.1:
		global_position = Vector3(base.x - out.x * 0.9, top_y + 0.1, base.z - out.z * 0.9)
		state = St.FOOT
		_peak_y = global_position.y
	elif global_position.y <= base.y + 0.02 and iv.y > 0.0:
		global_position.y = base.y + 0.05
		state = St.FOOT
	elif not blocked and Input.is_action_just_pressed("jump"):
		state = St.FOOT
		velocity = out * 3.0 + Vector3.UP * 2.0
		_peak_y = global_position.y


func grab_ladder(l: Dictionary) -> void:
	ladder = l
	state = St.LADDER
	crouching = false
	aiming = false
	if global_position.y > l.top - 1.5:
		global_position.y = l.top - 1.3
	else:
		global_position.y = maxf(global_position.y, l.pos.y + 0.1)


# ------------------------------------------------------------------ cover
func _try_cover() -> void:
	var best := {}
	var bd := 1e9
	var o := global_position + Vector3.UP * 0.7
	for i in range(8):
		var a := facing + i * TAU / 8.0
		var dir := Vector3(-sin(a), 0, -cos(a))
		var hit := Game.ray(o, o + dir * 1.6, Game.MASK_SOLID, [self])
		if not hit.is_empty() and absf(hit.normal.y) < 0.35:
			var dd: float = o.distance_to(hit.position)
			if dd < bd:
				bd = dd
				best = hit
	if best.is_empty():
		Game.say("No cover nearby")
		return
	_attach_cover(best.position, best.normal)


func _attach_cover(pos: Vector3, n: Vector3) -> void:
	cover_normal = Vector3(n.x, 0, n.z).normalized()
	var p := pos + cover_normal * 0.42
	p.y = global_position.y
	global_position = p
	var head := Game.ray(global_position + Vector3.UP * 1.45, global_position + Vector3.UP * 1.45 - cover_normal * 1.0, Game.MASK_SOLID, [self])
	cover_low = head.is_empty()
	state = St.COVER
	_state_t = 0.0
	velocity = Vector3.ZERO
	_cover_edge_t = 0.0
	_cover_away_t = 0.0
	crouching = cover_low


func _cover(delta: float, blocked: bool) -> void:
	var iv := Vector2.ZERO if blocked else _input_vec()
	var wish := _wish_dir(iv)
	var tangent := cover_normal.cross(Vector3.UP).normalized()
	var along := wish.dot(tangent)
	var away := wish.dot(cover_normal)
	var d := inv.def()
	aiming = not blocked and Input.is_action_pressed("aim") and d.kind != "melee"
	var at_edge := 0.0
	velocity = Vector3.ZERO
	if absf(along) > 0.3 and not aiming:
		var dirv := tangent * signf(along)
		cover_side = signf(along) * (1.0 if tangent.dot(Basis(Vector3.UP, Game.cam.yaw).x) > 0.0 else -1.0)
		var probe := global_position + dirv * 0.5 + Vector3.UP * 0.6
		var wall := Game.ray(probe, probe - cover_normal * 1.0, Game.MASK_SOLID, [self])
		if not wall.is_empty():
			velocity = dirv * 1.9
			_cover_edge_t = 0.0
		else:
			at_edge = signf(along)
			_cover_edge_t += delta
			if _cover_edge_t > 0.4:
				var from := global_position + dirv * 0.95 - cover_normal * 0.7 + Vector3.UP * 0.6
				var side := Game.ray(from, from - dirv * 1.3, Game.MASK_SOLID, [self])
				if not side.is_empty() and absf(side.normal.y) < 0.35:
					_attach_cover(side.position, side.normal)
					return
	else:
		_cover_edge_t = 0.0
	if away > 0.6:
		_cover_away_t += delta
	else:
		_cover_away_t = 0.0
	velocity.y = -2.0
	move_and_slide()
	move_speed = Vector3(velocity.x, 0, velocity.z).length()
	# pose: back to wall, pop up / lean out to aim
	crouching = cover_low and not aiming
	if aiming:
		facing = lerp_angle(facing, Game.cam.yaw, clampf(delta * 16.0, 0.0, 1.0))
	else:
		facing = lerp_angle(facing, atan2(-cover_normal.x, -cover_normal.z), clampf(delta * 12.0, 0.0, 1.0))
	rotation.y = facing
	rig.lean = lerpf(rig.lean, at_edge * 0.5 if not aiming else 0.0, clampf(delta * 8.0, 0.0, 1.0))
	if blocked:
		return
	# blind fire (no aim) or aimed fire
	rig.blind_fire = 0.0
	if d.kind == "hitscan":
		if Input.is_action_pressed("fire") and not aiming:
			rig.blind_fire = 1.0
			_fire(delta, 4.0)
		elif aiming:
			_weapon_input(delta)
	elif aiming:
		_weapon_input(delta)
	if Input.is_action_just_pressed("cover") or Input.is_action_just_pressed("jump") or _cover_away_t > 0.25 or Input.is_action_pressed("sprint"):
		state = St.FOOT
		rig.lean = 0.0
		rig.blind_fire = 0.0
		crouching = false


# ------------------------------------------------------------------ weapons
func _weapon_input(delta: float) -> void:
	var d := inv.def()
	if d.kind == "melee":
		_melee_input(delta)
		return
	var pressed := Input.is_action_pressed("fire")
	var just := Input.is_action_just_pressed("fire")
	if d.kind == "thrown":
		if just and _attack_t < 0.0 and inv.total_ammo(inv.current) > 0:
			_attack_t = 0.0
			rig.attack_kind = 4
			_throw_pending = true
		return
	if (d.auto and pressed) or just:
		_fire(delta, 1.0)


func _fire(_delta: float, spread_mult: float) -> void:
	if _fire_cd > 0.0 or _reload_t > 0.0:
		return
	var d := inv.def()
	var e := inv.entry()
	if e.mag <= 0:
		if e.reserve > 0:
			start_reload()
		else:
			Sfx.play3d("dry_fire", global_position, -6.0)
			_fire_cd = 0.3
		return
	e.mag -= 1
	_fire_cd = 1.0 / d.rate
	var now := Time.get_ticks_msec() * 0.001
	last_shot_time = now
	last_violence_time = now
	var skill := Game.skill("shooting")
	var grip := 0.7 if inv.has_mod("grip") else 1.0
	var suppressed := inv.has_mod("suppressor")
	var spread := d.spread * spread_mult * grip * (1.0 - 0.3 * skill)
	spread += _bloom * 1.2
	if not aiming:
		spread *= 1.9
	if move_speed > 1.0:
		spread *= 1.3
	if crouching:
		spread *= 0.75
	if in_vehicle():
		spread *= 1.9
	var exclude: Array = [self]
	if in_vehicle():
		exclude.append(vehicle)
	var cam: CameraRig = Game.cam
	var origin := cam.aim_origin()
	var dirc := cam.aim_dir()
	var target := cam.aim_point(d.reach, exclude)
	var muzzle := rig.muzzle_pos()
	if in_vehicle():
		muzzle = vehicle.seat_global(seat).origin + Vector3.UP * 0.5 + dirc * 0.9
	if d.kind == "projectile":
		var dir := (target - muzzle).normalized()
		Projectile.launch(d.proj, muzzle + dir * 0.4, dir * (60.0 if d.proj == "rocket" else 30.0) + (Vector3.UP * 3.0 if d.proj == "grenade" else Vector3.ZERO), self, d.damage)
		Fx.muzzle(muzzle, dir, true)
		Sfx.play3d(d.sound, muzzle, 0.0, randf_range(0.95, 1.05), 160.0)
	else:
		for i in range(d.pellets):
			var dir2 := (target - muzzle).normalized()
			dir2 = _spread_dir(dir2, spread)
			var dmg := d.damage * (0.92 if suppressed else 1.0)
			_hitscan(muzzle, dir2, d.reach, dmg, exclude, i == 0)
		Fx.muzzle(muzzle, (target - muzzle).normalized(), d.pellets > 1)
		Sfx.play3d("shot_suppressed" if suppressed else d.sound, muzzle, -3.0 if suppressed else 0.0, randf_range(0.94, 1.06), 60.0 if suppressed else 220.0)
	Game.noise(global_position, d.noise * (0.12 if suppressed else 1.0), "gunshot")
	Wanted.crime("gunfire_suppressed" if suppressed else "gunfire", global_position)
	_bloom = minf(_bloom + 0.35, 2.5)
	var rec := d.recoil * 0.55 * grip * (1.0 - 0.35 * skill) * (0.6 if crouching else 1.0)
	cam.recoil(rec)
	cam.shake(0.05 + d.recoil * 0.02)
	cam.yaw += deg_to_rad(randf_range(-0.3, 0.3) * rec)
	rig.recoil_kick = 1.0
	Game.skill_up("shooting", 0.03)
	if Game.hud:
		Game.hud.refresh_weapon()
	if e.mag <= 0 and e.reserve > 0:
		start_reload()


func _spread_dir(dir: Vector3, deg: float) -> Vector3:
	var a := deg_to_rad(deg) * sqrt(randf())
	var ang := randf() * TAU
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var x := dir.cross(up).normalized()
	var y := x.cross(dir).normalized()
	return (dir + (x * cos(ang) + y * sin(ang)) * tan(a)).normalized()


func _hitscan(from: Vector3, dir: Vector3, reach: float, dmg: float, exclude: Array, draw: bool) -> void:
	var hit := Game.ray(from, from + dir * reach, Game.MASK_SHOT, exclude)
	var end := from + dir * reach
	if not hit.is_empty():
		end = hit.position
		Combat.apply_bullet(hit, dir, dmg, self)
	elif end.y < Game.WATER_Y:
		pass
	# water surface splash
	if from.y > Game.WATER_Y and end.y < Game.WATER_Y:
		var t := (from.y - Game.WATER_Y) / maxf(from.y - end.y, 0.001)
		var wp := from.lerp(end, t)
		if City.terrain_height(wp.x, wp.z) < Game.WATER_Y:
			Fx.splash(wp, 0.35)
	if draw or randf() < 0.4:
		Fx.tracer(from, end)


func _melee_input(delta: float) -> void:
	if _attack_t >= 0.0:
		return
	if Input.is_action_pressed("fire"):
		_melee_charge += delta
	if Input.is_action_just_released("fire") or _melee_charge > 0.7 or Input.is_action_just_pressed("melee_alt"):
		var heavy := _melee_charge > 0.32 or Input.is_action_just_pressed("melee_alt")
		_melee_charge = 0.0
		_start_melee(heavy)


func _start_melee(heavy: bool) -> void:
	_attack_t = 0.0
	_attack_heavy = heavy
	_attack_hit_done = false
	var d := inv.def()
	if d.hold == "melee":
		rig.attack_kind = 3
	elif heavy:
		rig.attack_kind = 2
	else:
		rig.attack_kind = _combo % 2
		_combo += 1
	Sfx.play3d("swing", global_position, -8.0, randf_range(0.9, 1.2), 20.0)
	if Game.cam:
		facing = Game.cam.yaw
	stamina = maxf(0.0, stamina - (0.1 if heavy else 0.04))


func _melee_hit() -> void:
	var d := inv.def()
	var fwd := -global_basis.z
	var best = null
	var bd := d.reach + 0.4
	for n in Game.npcs:
		if not is_instance_valid(n) or n.dead:
			continue
		var to: Vector3 = n.global_position - global_position
		var dist := to.length()
		if dist < bd and absf(to.y) < 1.6 and fwd.dot(Vector3(to.x, 0, to.z).normalized()) > 0.35:
			bd = dist
			best = n
	var now := Time.get_ticks_msec() * 0.001
	if best != null:
		last_violence_time = now
		var strength := Game.skill("strength")
		var dmg := d.damage * (1.0 + 0.6 * strength) * (2.2 if _attack_heavy else 1.0)
		var behind: bool = (-best.global_basis.z).dot(fwd) > 0.4
		var takedown: bool = crouching and behind and not best.is_alerted()
		if takedown:
			dmg = 999.0
			Game.say("Stealth takedown", Color(0.6, 0.8, 1.0))
			Game.skill_up("stealth", 2.0)
		var hp: Vector3 = best.global_position + Vector3.UP * 1.3
		best.damage(dmg, global_position, self, "melee_silent" if takedown else "melee")
		if is_instance_valid(best) and (_attack_heavy or d.knock > 1.2 or takedown):
			best.knockdown(fwd * 4.5 * d.knock + Vector3.UP * 2.0, self)
		Fx.impact(hp, -fwd, "flesh")
		Sfx.play3d("punch", hp, 0.0, randf_range(0.9, 1.1), 30.0)
		if Game.cam:
			Game.cam.shake(0.25 if _attack_heavy else 0.12)
		Game.skill_up("strength", 0.25)
		if not takedown:
			Game.noise(global_position, 10.0, "fight")
		return
	# vehicles / props
	var hit := Game.ray(global_position + Vector3.UP * 1.1, global_position + Vector3.UP * 1.1 + fwd * (d.reach + 0.3), Game.MASK_SOLID, [self])
	if not hit.is_empty():
		Combat.apply_melee(hit, fwd, d.damage, self)


func _do_throw() -> void:
	var d := inv.def()
	var e := inv.entry()
	if e.mag <= 0 and e.reserve > 0:
		e.mag = 1
		e.reserve -= 1
	if e.mag <= 0:
		return
	e.mag = 0
	if e.reserve > 0:
		e.mag = 1
		e.reserve -= 1
	var cam: CameraRig = Game.cam
	var dir := (cam.aim_dir() + Vector3.UP * 0.22).normalized()
	var from := rig.hand_pos(true) + dir * 0.3
	if in_vehicle():
		from = vehicle.seat_global(seat).origin + Vector3.UP * 0.9 + cam.aim_dir() * 1.2
	Projectile.launch(d.proj, from, dir * 17.0 + velocity_now() * 0.6, self, d.damage)
	last_violence_time = Time.get_ticks_msec() * 0.001
	if Game.hud:
		Game.hud.refresh_weapon()


# ------------------------------------------------------------------ swimming
func _enter_swim() -> void:
	state = St.SWIM
	crouching = false
	aiming = false
	Sfx.play3d("splash", global_position, -2.0)
	Fx.splash(Vector3(global_position.x, Game.WATER_Y, global_position.z), 1.2)
	velocity.y *= 0.3


func _swim(delta: float, blocked: bool) -> void:
	var iv := Vector2.ZERO if blocked else _input_vec()
	var wish := _wish_dir(iv)
	var surface_y := Game.WATER_Y - 1.42
	var up_in := 0.0
	if not blocked:
		up_in = Input.get_axis("crouch", "jump")
	underwater = global_position.y < surface_y - 0.35
	var sp := 2.7
	sprinting = not blocked and Input.is_action_pressed("sprint") and stamina > 0.05 and wish != Vector3.ZERO
	if sprinting:
		sp = 4.4
		stamina = maxf(0.0, stamina - delta / (10.0 + 14.0 * Game.skill("stamina")))
		Game.skill_up("stamina", delta * 0.08)
	else:
		stamina = minf(1.0, stamina + delta * 0.15)
	var target := wish * sp
	if underwater and Game.cam and iv.y < -0.1:
		target = Game.cam.aim_dir() * sp
	target.y += up_in * 2.4
	if not underwater and up_in >= 0.0:
		target.y = (surface_y - global_position.y) * 3.0
	velocity = velocity.move_toward(target, 9.0 * delta)
	if global_position.y > surface_y + 0.05 and velocity.y > 0.0:
		velocity.y = 0.0
	move_and_slide()
	move_speed = velocity.length()
	if wish != Vector3.ZERO:
		facing = lerp_angle(facing, atan2(-wish.x, -wish.z), clampf(delta * 6.0, 0.0, 1.0))
	rotation.y = facing
	if move_speed > 1.0:
		_step_acc += delta
		if _step_acc > 0.8:
			_step_acc = 0.0
			if not underwater:
				Sfx.play3d("swim", global_position, -8.0, randf_range(0.9, 1.1), 25.0)
				Fx.splash(Vector3(global_position.x, Game.WATER_Y, global_position.z) - global_basis.z * 0.5, 0.4)
	var th := City.terrain_height(global_position.x, global_position.z)
	if th > Game.WATER_Y - 1.15 or (is_on_floor() and global_position.y > Game.WATER_Y - 1.2):
		state = St.FOOT
		underwater = false
		rig.rotation.x = 0.0
		velocity.y = 0.0
		_peak_y = global_position.y
		_air_time = 0.0


# ------------------------------------------------------------------ parachute
func _open_chute() -> void:
	state = St.CHUTE
	_state_t = 0.0
	canopy.visible = true
	has_parachute = false
	rig.set_extra("pack", false)
	Sfx.play3d("chute_open", global_position, 0.0)
	velocity.y = maxf(velocity.y, -12.0)
	_chute_prompt = false
	Game.say("Parachute deployed  -  A/D steer, W dive, S flare")


func _chute(delta: float, blocked: bool) -> void:
	var iv := Vector2.ZERO if blocked else _input_vec()
	facing -= iv.x * delta * 1.3
	rotation.y = facing
	rig.steer = iv.x
	var fwd_speed := 9.0
	var sink := 5.0
	if iv.y < -0.2:
		fwd_speed = 14.0
		sink = 9.5
	elif iv.y > 0.2:
		fwd_speed = 5.0
		sink = 2.4
	var fwd := -global_basis.z
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(fwd * fwd_speed, 8.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = move_toward(velocity.y, -sink, 14.0 * delta)
	var sink_now := -velocity.y
	move_and_slide()
	move_speed = hv.length()
	canopy.rotation.z = lerpf(canopy.rotation.z, -iv.x * 0.3, delta * 4.0)
	if is_on_floor():
		canopy.visible = false
		state = St.FOOT
		if sink_now > 7.0:
			damage((sink_now - 7.0) * 9.0, global_position, null, "fall")
			if alive():
				knockdown(hv * 0.5)
		else:
			Game.say("Clean landing", Color(0.6, 1.0, 0.6))
		_peak_y = global_position.y
		_air_time = 0.0
		if Game.world and Game.world.activities:
			Game.world.activities.on_chute_landed(global_position)
	elif global_position.y < Game.WATER_Y - 0.9 and City.terrain_height(global_position.x, global_position.z) < Game.WATER_Y - 1.2:
		canopy.visible = false
		_enter_swim()


func give_parachute() -> void:
	has_parachute = true
	rig.set_extra("pack", true)


# ------------------------------------------------------------------ ragdoll / damage
func knockdown(impulse: Vector3) -> void:
	if state == St.DEAD or state == St.BUSTED or state == St.VEHICLE or state == St.RIDE:
		return
	if state == St.CHUTE:
		canopy.visible = false
	state = St.RAGDOLL
	_state_t = 0.0
	_rag_vel = impulse
	velocity = impulse
	aiming = false
	crouching = false
	rig.blind_fire = 0.0
	rig.lean = 0.0


func _ragdoll(delta: float) -> void:
	velocity.y -= GRAVITY * delta
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
	if global_position.y < Game.WATER_Y - 1.2 and City.terrain_height(global_position.x, global_position.z) < Game.WATER_Y - 1.2:
		velocity.y = move_toward(velocity.y, 0.8, 30.0 * delta)
	move_and_slide()
	move_speed = 0.0
	if state == St.RAGDOLL and _state_t > 1.5 and is_on_floor() and velocity.length() < 1.0:
		if health > 0.0:
			state = St.FOOT
			rig.rotation = Vector3.ZERO
			_peak_y = global_position.y
			_air_time = 0.0
			# cornered next to an officer while down => arrest check handled by Wanted
	elif state == St.RAGDOLL and _state_t > 5.0 and health > 0.0:
		state = St.FOOT
		rig.rotation = Vector3.ZERO


func damage(amount: float, from_pos: Vector3 = Vector3.ZERO, attacker = null, kind: String = "bullet") -> void:
	if not alive() or Game.flags.invuln or amount <= 0.0:
		return
	if state == St.ROLL and kind == "bullet":
		amount *= 0.4
	if rig.block > 0.5 and kind == "melee":
		amount *= 0.3
	if in_vehicle() and kind == "bullet":
		amount *= 0.55
	amount *= 1.0 - 0.25 * Game.skill("strength") if kind in ["melee", "fall"] else 1.0
	if armor > 0.0 and kind in ["bullet", "explosion", "melee"]:
		var absorbed := minf(armor, amount * 0.75)
		armor -= absorbed
		amount -= absorbed
	health -= amount
	_regen_t = 0.0
	last_damage_time = Time.get_ticks_msec() * 0.001
	rig.hit_t = 1.0
	if kind != "drown" and kind != "fire" or randf() < 0.2:
		Sfx.play3d("pain_f" if look.get("gender", "male") == "female" else "pain_m", global_position, -6.0, randf_range(0.9, 1.1), 30.0)
	if Game.hud:
		Game.hud.damage_flash(from_pos)
	if Game.cam and kind != "drown":
		Game.cam.shake(clampf(amount * 0.012, 0.05, 0.5))
	if health <= 0.0:
		die(kind)


func die(_kind: String = "") -> void:
	if state == St.DEAD:
		return
	if in_vehicle():
		_leave_vehicle(true)
	health = 0.0
	state = St.DEAD
	_state_t = 0.0
	aiming = false
	canopy.visible = false
	velocity = Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1))
	Game.stats.deaths += 1
	Sfx.play("sting_fail", -4.0)
	Game.banner("FLATLINED", "The paramedics scrape you off the street...", Color(0.9, 0.25, 0.2))
	if Game.hud:
		Game.hud.fade_out_in(3.2, Callable(self, "_respawn_hospital"))


func _respawn_hospital() -> void:
	var fee := mini(int(Game.money * 0.05), 500)
	Game.add_money(-fee)
	Wanted.clear(true)
	health = max_health
	armor = 0.0
	state = St.FOOT
	rig.rotation = Vector3.ZERO
	rig.dead = 0.0
	rig.limp = 0.0
	teleport(Game.world.hospital_spawn if Game.world else Vector3.ZERO)
	if fee > 0:
		Game.say("Medical bill: $%d" % fee, Color(1, 0.6, 0.5))


func busted() -> void:
	if not alive():
		return
	if in_vehicle():
		_leave_vehicle(true)
	state = St.BUSTED
	_state_t = 0.0
	velocity = Vector3.ZERO
	aiming = false
	Game.stats.busted += 1
	Sfx.play("sting_fail", -4.0)
	Game.banner("BUSTED", "Booked at Marlow Bay PD", Color(0.35, 0.6, 1.0))
	if Game.hud:
		Game.hud.fade_out_in(3.0, Callable(self, "_respawn_police"))


func _respawn_police() -> void:
	var fine := mini(int(Game.money * 0.1), 1000)
	Game.add_money(-fine)
	for id in inv.owned:
		inv.owned[id].reserve = int(inv.owned[id].reserve * 0.5)
	Wanted.clear(true)
	health = maxf(health, max_health * 0.6)
	state = St.FOOT
	rig.rotation = Vector3.ZERO
	rig.hands_up = 0.0
	teleport(Game.world.police_spawn if Game.world else Vector3.ZERO)
	Game.say("Fine paid: $%d, half your spare ammo confiscated" % fine, Color(1, 0.6, 0.5))
	if Game.hud:
		Game.hud.refresh_weapon()


func teleport(pos: Vector3, yaw: float = 0.0) -> void:
	if in_vehicle():
		_leave_vehicle(true)
	if state in [St.CHUTE, St.LADDER, St.COVER, St.VAULT, St.SWIM, St.ROLL, St.ENTERING, St.RIDE, St.RAGDOLL]:
		state = St.FOOT
	canopy.visible = false
	global_position = pos
	velocity = Vector3.ZERO
	facing = yaw
	rotation.y = yaw
	_peak_y = pos.y
	_air_time = 0.0
	underwater = false
	rig.rotation = Vector3.ZERO
	if Game.cam:
		Game.cam.snap_behind(yaw)


# ------------------------------------------------------------------ vehicles
func nearest_vehicle(max_d: float = 4.6):
	var best = null
	var bd := max_d
	for v in Game.vehicles:
		if not is_instance_valid(v) or v.dead:
			continue
		var d: float = v.global_position.distance_to(global_position) - v._half.z * 0.6
		if d < bd:
			bd = d
			best = v
	return best


func _toggle_vehicle() -> void:
	if state == St.VEHICLE:
		_leave_vehicle(false)
		return
	if state == St.RIDE:
		if ride_exit.is_valid():
			ride_exit.call()
		return
	if state != St.FOOT and state != St.SWIM and state != St.COVER:
		return
	var v = nearest_vehicle()
	if v == null:
		return
	if v.seat_users[0] != null:
		return
	_enter_vehicle = v
	_enter_stage = 0
	_state_t = 0.0
	_tween_from = global_position
	state = St.ENTERING
	aiming = false
	crouching = false
	if v.driver_rig != null:
		# carjack: pull the driver out
		var police: bool = v.def.tag == "police"
		if Game.traffic:
			Game.traffic.eject_driver(v, true)
		Wanted.crime("carjack_police" if police else "carjack", global_position)
		Sfx.play3d("punch", v.global_position, -4.0)
		last_violence_time = Time.get_ticks_msec() * 0.001


func _entering(delta: float) -> void:
	var v := _enter_vehicle
	if v == null or not is_instance_valid(v) or v.dead:
		state = St.FOOT
		return
	var door := v.door_pos(0)
	door.y = maxf(door.y - 0.2, v.global_position.y - 0.4)
	if _enter_stage == 0:
		var t := clampf(_state_t / 0.28, 0.0, 1.0)
		global_position = _tween_from.lerp(door, t)
		var to := v.global_position - global_position
		facing = lerp_angle(facing, atan2(-to.x, -to.z), 0.3)
		rotation.y = facing
		v.set_door(t)
		if t >= 1.0:
			_enter_stage = 1
			_state_t = 0.0
	else:
		var t2 := clampf(_state_t / 0.32, 0.0, 1.0)
		var seat_t := v.seat_global(0)
		var target := seat_t.origin - v.global_basis.y * 0.95
		global_position = door.lerp(target, t2)
		rig.sit = t2
		if t2 >= 1.0:
			_mount(v, 0)


func _mount(v: Vehicle, s: int) -> void:
	vehicle = v
	seat = s
	state = St.VEHICLE
	col.disabled = true
	v.seat_users[s] = self
	if s == 0:
		v.driver = self
		v.ai = null
		v.parked = false
		v.freeze = false
		v.sleeping = false
		v.owner_is_player = true
	v.set_door(0.0)
	velocity = Vector3.ZERO
	var d := inv.def()
	if not d.driveby:
		for cand in ["smg", "pistol", "heavy_pistol"]:
			if inv.has(cand):
				equip(cand)
				break
		if not inv.def().driveby:
			equip("fists")
	if v.def.tag == "police":
		pass
	Wanted.on_player_vehicle_changed(v)
	_update_radio()
	if Game.hud:
		Game.hud.show_vehicle_hint(v)


func _leave_vehicle(force: bool) -> void:
	var v := vehicle
	if v == null or not is_instance_valid(v):
		state = St.FOOT
		col.disabled = false
		vehicle = null
		return
	var fast := v.linear_velocity.length() > 11.0
	var out := v.door_pos(seat)
	var hit := Game.ray(v.global_position + Vector3.UP, out + Vector3.UP * 0.6, Game.L_WORLD)
	if not hit.is_empty():
		out = v.global_transform * Vector3(-(v._half.x + 0.75) * (-1.0 if v.seats[seat].x <= 0.0 else 1.0), 0.2, v.seats[seat].z)
		var hit2 := Game.ray(v.global_position + Vector3.UP, out + Vector3.UP * 0.6, Game.L_WORLD)
		if not hit2.is_empty():
			out = v.global_position + Vector3.UP * (v._half.y * 2.0 + 0.3)
	v.seat_users[seat] = null
	if v.driver == self:
		v.driver = null
		v.throttle_in = 0.0
		v.steer_in = 0.0
		v.handbrake_in = true
		v.lift_in = 0.0
		v.pitch_in = 0.0
		v.roll_in = 0.0
		v.yaw_in = 0.0
	var vel := v.linear_velocity
	vehicle = null
	col.disabled = false
	state = St.FOOT
	rig.sit = 0.0
	rig.bike = 0.0
	rig.rotation = Vector3.ZERO
	global_position = out
	rotation = Vector3(0, v.global_rotation.y, 0)
	facing = rotation.y
	velocity = Vector3.ZERO
	_peak_y = global_position.y
	_air_time = 0.0
	_radio.stop()
	if Game.hud:
		Game.hud.show_vehicle_hint(null)
	if v.is_air() and _height_above_ground() > 8.0:
		velocity = vel
	elif fast and not force:
		health -= 0.0
		damage(clampf((vel.length() - 11.0) * 2.0, 2.0, 40.0), global_position, null, "fall")
		if alive():
			knockdown(vel * 0.7 + Vector3.UP * 2.0)
	Wanted.on_player_vehicle_changed(null)


func on_vehicle_destroyed(_v) -> void:
	if state != St.VEHICLE:
		return
	_leave_vehicle(true)
	if not Game.flags.invuln:
		damage(140.0, global_position, null, "explosion")
	if alive():
		knockdown(Vector3(randf_range(-3, 3), 6.0, randf_range(-3, 3)))


func on_vehicle_crash(dv: float, v) -> void:
	if state != St.VEHICLE:
		return
	if v.is_two_wheel() and dv > 6.5:
		var vel: Vector3 = v._prev_vel
		_leave_vehicle(true)
		damage((dv - 5.0) * 4.0, global_position, null, "fall")
		if alive():
			knockdown(vel * 0.6 + Vector3.UP * 3.0)
	elif dv > 9.0:
		damage((dv - 9.0) * 3.5, global_position, null, "fall")


func _in_vehicle(delta: float, blocked: bool) -> void:
	var v := vehicle
	if v == null or not is_instance_valid(v):
		_leave_vehicle(true)
		return
	var st := v.seat_global(seat)
	global_transform = Transform3D(v.global_basis.orthonormalized(), st.origin - v.global_basis.y * 0.95 * rig.height_scale)
	facing = v.global_rotation.y
	move_speed = 0.0
	underwater = v.drowned and global_position.y < Game.WATER_Y - 1.4
	if v.driver != self:
		return
	if blocked:
		v.throttle_in = 0.0
		v.steer_in = 0.0
		v.lift_in = 0.0
		v.pitch_in = 0.0
		v.roll_in = 0.0
		v.yaw_in = 0.0
		return
	var iv := _input_vec()
	match v.def.kind:
		"heli":
			v.pitch_in = -iv.y
			v.yaw_in = iv.x
			v.roll_in = Input.get_axis("roll_left", "roll_right")
			v.lift_in = Input.get_axis("crouch", "jump")
		"plane":
			v.throttle_in = -iv.y
			v.roll_in = iv.x
			v.yaw_in = Input.get_axis("roll_left", "roll_right")
			v.pitch_in = Input.get_axis("crouch", "jump") + Input.get_axis("pitch_down", "pitch_up")
			v.steer_in = iv.x
		_:
			v.throttle_in = -iv.y
			v.steer_in = iv.x
			v.handbrake_in = Input.is_action_pressed("handbrake")
	rig.steer = iv.x
	if Input.is_action_just_pressed("horn"):
		v.horn()
	if Input.is_action_just_pressed("headlights"):
		v.set_lights(not v.lights_on)
	if Input.is_action_just_pressed("siren"):
		v.set_siren(not v.siren_on)
	if Input.is_action_just_pressed("radio_next"):
		Game.settings.radio_station = (int(Game.settings.radio_station) + 1) % 5
		_update_radio()
	elif Input.is_action_just_pressed("radio_prev"):
		Game.settings.radio_station = posmod(int(Game.settings.radio_station) - 1, 5)
		_update_radio()
	if Input.is_action_pressed("flip"):
		_flip_hold += delta
		if _flip_hold > 0.6 and v.global_basis.y.dot(Vector3.UP) < 0.4 and v.linear_velocity.length() < 3.0:
			v.flip_upright()
			_flip_hold = 0.0
	else:
		_flip_hold = 0.0
	if Game.daynight and Game.daynight.night > 0.6 and not v.lights_on and v.def.kind != "bicycle":
		v.set_lights(true)
	# drive-by
	var d := inv.def()
	aiming = Input.is_action_pressed("aim") and d.driveby
	if d.driveby and not v.is_air():
		if d.kind == "thrown":
			if Input.is_action_just_pressed("fire") and inv.total_ammo(inv.current) > 0:
				_do_throw()
		elif (d.auto and Input.is_action_pressed("fire")) or Input.is_action_just_pressed("fire"):
			_fire(delta, 1.0)
	if v.drowned and Game.cam:
		pass


func _update_radio() -> void:
	var st := int(Game.settings.radio_station)
	if not in_vehicle() or vehicle.def.kind == "bicycle" or st >= 4:
		_radio.stop()
		if in_vehicle() and st >= 4:
			Game.say("Radio off")
		return
	_radio.stream = Sfx.stream("radio_%d" % st, true)
	_radio.play()
	Game.say("Radio: " + ["Coastline FM", "Lowtide Lounge", "Pulse 128", "Night Drift"][st], Color(1.0, 0.85, 0.5))


# ------------------------------------------------------------------ passenger rides (taxi / monorail)
func start_ride(node: Node3D, offset: Vector3, exit_cb: Callable) -> void:
	ride_node = node
	ride_offset = offset
	ride_exit = exit_cb
	state = St.RIDE
	col.disabled = true
	aiming = false
	crouching = false
	velocity = Vector3.ZERO


func end_ride(pos: Vector3) -> void:
	if state != St.RIDE:
		return
	state = St.FOOT
	col.disabled = false
	ride_node = null
	rig.sit = 0.0
	global_position = pos
	rotation = Vector3(0, facing, 0)
	_peak_y = pos.y
	_air_time = 0.0


func _ride(_delta: float, _blocked: bool) -> void:
	if ride_node == null or not is_instance_valid(ride_node):
		end_ride(global_position)
		return
	global_transform = Transform3D(ride_node.global_basis.orthonormalized(), ride_node.global_transform * ride_offset)
	facing = ride_node.global_rotation.y


# ------------------------------------------------------------------ animation
func _animate(delta: float) -> void:
	rig.speed = move_speed
	if state == St.FOOT or state == St.COVER:
		rig.phase += move_speed * delta * (2.6 if move_speed < 5.5 else 2.05)
	rig.crouch = 1.0 if (crouching and state in [St.FOOT, St.COVER]) else 0.0
	if state == St.ROLL:
		rig.crouch = 1.0
		rig.rotation.x = -_state_t / 0.55 * TAU
	rig.aim = 1.0 if aiming else 0.0
	var d := inv.def()
	var recent_fire := Time.get_ticks_msec() * 0.001 - last_shot_time < 0.7
	if recent_fire and d.kind != "melee" and state != St.COVER:
		rig.aim = 1.0
	if Game.cam:
		rig.aim_pitch = Game.cam.pitch
	if state == St.VEHICLE and vehicle != null:
		var two := vehicle.is_two_wheel()
		rig.sit = 0.0 if two else 1.0
		rig.bike = 1.0 if two else 0.0
		if two:
			rig.rotation.z = vehicle._lean
		if Game.cam:
			rig.look_yaw = clampf(angle_difference(vehicle.global_rotation.y, Game.cam.yaw), -1.6, 1.6)
	elif state == St.RIDE:
		rig.sit = 1.0
		rig.look_yaw = 0.0
	else:
		if state != St.ENTERING:
			rig.sit = 0.0
		rig.bike = 0.0
		rig.look_yaw = 0.0
	rig.swim = 1.0 if state == St.SWIM else 0.0
	if state == St.SWIM:
		rig.rotation.x = lerpf(rig.rotation.x, -1.25 if move_speed > 0.8 else -0.15, clampf(delta * 5.0, 0.0, 1.0))
	rig.fall = 1.0 if (state == St.FOOT and _air_time > 0.45) else 0.0
	rig.chute = 1.0 if state == St.CHUTE else 0.0
	rig.climb = 1.0 if (state == St.LADDER or state == St.VAULT) else 0.0
	if state == St.VAULT:
		rig.phase += delta * 9.0
	var down := state == St.RAGDOLL or state == St.DEAD
	rig.limp = 1.0 if state == St.RAGDOLL else 0.0
	rig.dead = 1.0 if state == St.DEAD else 0.0
	rig.hands_up = 1.0 if state == St.BUSTED else 0.0
	if down:
		rig.rotation.x = lerpf(rig.rotation.x, -1.45, clampf(delta * 7.0, 0.0, 1.0))
		rig.position.y = lerpf(rig.position.y, 0.25, clampf(delta * 7.0, 0.0, 1.0))
	elif state != St.SWIM and state != St.ROLL:
		rig.rotation.x = lerpf(rig.rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		rig.position.y = lerpf(rig.position.y, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		if state != St.VEHICLE:
			rig.rotation.z = 0.0
	rig.hit_t = maxf(0.0, rig.hit_t - delta * 3.5)
	if _attack_t >= 0.0:
		var dur := 0.34
		if d.kind == "thrown":
			dur = 0.42
		elif _attack_heavy:
			dur = 0.55
		_attack_t += delta / dur
		rig.attack_t = _attack_t
		if _attack_t >= 0.5 and not _attack_hit_done and d.kind == "melee":
			_attack_hit_done = true
			_melee_hit()
		if _attack_t >= 0.55 and _throw_pending:
			_throw_pending = false
			_do_throw()
		if _attack_t >= 1.0:
			_attack_t = -1.0
			rig.attack_t = -1.0
	else:
		rig.attack_t = -1.0
	rig.tick(delta)
	if canopy.visible:
		canopy.position = Vector3(0, 1.3, 0)
