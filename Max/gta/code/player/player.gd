class_name Player
extends Character
## The player: third-person locomotion, stealth crouch, combat, vehicles (enter / carjack /
## drive / drive-by / bail out), swimming and diving, death, arrest and respawn.
## Cover, climbing, ladders and the parachute live in PlayerMoves (child node "Moves").

enum St { FOOT, SWIM, VEHICLE, MOVE, DEAD, BUSTED, ANIM }

const JOG := 4.3
const SPRINT := 7.0
const CROUCH_SPEED := 1.9
const AIM_SPEED := 2.3
const JUMP_V := 5.7

var state: int = St.FOOT
var moves: PlayerMoves
var stamina := 100.0
var breath := 1.0                # 0..1 of lung capacity
var diving := false
var aiming := false
var stealth := false
var combat_timer := 0.0          # keeps the weapon levelled shortly after a shot
var noise_radius := 0.0
var money_lost := 0
var passenger := false           # riding in a vehicle without controlling it
var last_vehicle: Vehicle = null
var scuba := false
## Backed by the inventory so shops, pickups, the admin menu and saves all agree.
var parachute: bool:
	get:
		return inventory != null and inventory.has_parachute
	set(value):
		if inventory != null:
			inventory.has_parachute = value
var _stamina_wait := 0.0
var _air_time := 0.0
var _fall_from := 0.0
var _step_acc := 0.0
var _prompt_cd := 0.0
var _interact: Interactable = null
var _near_vehicle: Vehicle = null
var _respawn_timer := 0.0
var _fire_was := false
var _busy := false
var _last_pos := Vector3.ZERO
var _horn_held := false
var _exit_hold := 0.0

func _ready() -> void:
	is_player = true
	team = &"player"
	name = "Player"
	setup_body(Appearance.default_player())
	moves = PlayerMoves.new()
	moves.name = "Moves"
	add_child(moves)
	moves.setup(self)
	inventory.give(&"pistol", 60, true)
	gunner.equip(&"unarmed", true)
	_last_pos = global_position
	add_to_group(&"player")

func max_stamina() -> float:
	return 100.0 * (1.0 + (Game.skills.level(&"stamina") if Game.skills else 0.0) * 0.8)

func lung_seconds() -> float:
	var base := 20.0 * (1.0 + (Game.skills.level(&"lung") if Game.skills else 0.0) * 1.5)
	return base * (7.0 if scuba else 1.0)

func camera_yaw() -> float:
	return Game.cam.yaw if Game.cam else face_yaw

func input_dir() -> Vector3:
	if Game.ui_blocked():
		return Vector3.ZERO
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if iv.length() < 0.05:
		return Vector3.ZERO
	return (Basis(Vector3.UP, camera_yaw()) * Vector3(iv.x, 0, iv.y)).normalized() * minf(iv.length(), 1.0)

# ---------------------------------------------------------------- main loop
func _physics_process(delta: float) -> void:
	combat_timer = maxf(0.0, combat_timer - delta)
	match state:
		St.FOOT:
			_foot(delta)
		St.SWIM:
			_swim(delta)
		St.VEHICLE:
			_in_vehicle(delta)
		St.MOVE:
			moves.tick(delta)
		St.DEAD, St.BUSTED:
			_tick_down(delta)
			_respawn_timer -= delta
			if _respawn_timer <= 0.0:
				_respawn()
		St.ANIM:
			pass
	_track_stats(delta)
	_update_prompt(delta)

func _track_stats(delta: float) -> void:
	var d := global_position.distance_to(_last_pos)
	_last_pos = global_position
	if d > 30.0:
		return
	match state:
		St.FOOT:
			Game.stats["distance_foot"] += d
		St.SWIM:
			Game.stats["distance_swim"] += d
			if Game.skills and d > 0.001:
				Game.skills.add(&"stamina", d * 0.00012)
				if diving:
					Game.skills.add(&"lung", delta * 0.0015)
		St.VEHICLE:
			if vehicle is Car or vehicle is Boat:
				Game.stats["distance_drive"] += d

# ---------------------------------------------------------------- on foot
func _foot(delta: float) -> void:
	if down:
		_tick_down(delta)
		return
	update_water()
	if water_depth > SWIM_DEPTH:
		_enter_swim()
		return
	var blocked := Game.ui_blocked()
	var dir := input_dir()
	var on_floor := is_on_floor()
	# --- stance
	if not blocked and Input.is_action_just_pressed("crouch") and on_floor:
		set_crouched(not crouched)
	stealth = crouched
	var gun := gunner.is_gun()
	aiming = not blocked and Input.is_action_pressed("aim") and (gun or gunner.data["cls"] == &"thrown")
	gunner.blocking = not blocked and Input.is_action_pressed("aim") and gunner.data["cls"] == &"melee"
	gunner.aiming = aiming
	gunner.driveby = false
	# --- speed selection
	var wish := JOG
	var sprinting := false
	if crouched:
		wish = CROUCH_SPEED
	elif aiming or gunner.blocking:
		wish = AIM_SPEED
	elif not blocked and Input.is_action_pressed("sprint") and dir.length() > 0.1 and stamina > 1.0 and on_floor:
		wish = SPRINT * (1.0 + 0.08 * (Game.skills.level(&"stamina") if Game.skills else 0.0))
		sprinting = true
	if sprinting:
		stamina = maxf(0.0, stamina - 11.0 * delta)
		_stamina_wait = 0.9
		if Game.skills:
			Game.skills.add(&"stamina", delta * 0.0022)
	else:
		_stamina_wait -= delta
		if _stamina_wait <= 0.0:
			stamina = minf(max_stamina(), stamina + 17.0 * delta)
	var target := dir * wish
	var accel := 20.0 if on_floor else 4.5
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	# --- jump / vault
	if not blocked and Input.is_action_just_pressed("jump") and on_floor:
		if crouched:
			set_crouched(false)
		if aiming and dir.length() > 0.2 and moves.try_roll(dir):
			return
		if moves.try_vault(dir):
			return
		velocity.y = JUMP_V
		Audio.play(&"jump", global_position, -10.0)
	if not on_floor:
		velocity.y -= GRAVITY * delta
		if _air_time == 0.0:
			_fall_from = global_position.y
		_fall_from = maxf(_fall_from, global_position.y)
		_air_time += delta
		# open sky + big drop + parachute: skydiving
		if _air_time > 0.9 and velocity.y < -11.0 and moves.can_freefall():
			moves.start_freefall()
			return
	else:
		if _air_time > 0.25:
			_landed(_fall_from - global_position.y)
		_air_time = 0.0
	move_and_slide()
	# --- facing
	var levelled := aiming or combat_timer > 0.0
	if levelled:
		set_face_yaw(lerp_angle(face_yaw, camera_yaw(), clampf(delta * 16.0, 0.0, 1.0)))
	elif dir.length() > 0.1:
		turn_toward(dir, delta, 11.0)
	# --- weapons
	_combat_input(delta, blocked)
	# --- other actions
	if not blocked:
		if Input.is_action_just_pressed("enter_vehicle"):
			_try_enter_vehicle()
		if Input.is_action_just_pressed("cover"):
			moves.try_cover()
		if Input.is_action_just_pressed("interact") and _interact != null:
			_interact.use(self)
	# --- animation
	var hs := Vector2(velocity.x, velocity.z).length()
	var vs: StringName = &"idle"
	if not on_floor and _air_time > 0.18:
		vs = &"jump" if velocity.y > 0.5 else &"fall"
	elif crouched:
		vs = &"crouch_walk" if hs > 0.3 else &"crouch_idle"
	elif hs > 5.6:
		vs = &"sprint"
	elif hs > 2.7:
		vs = &"run"
	elif hs > 0.3:
		vs = &"walk"
	visual.set_state(vs, hs)
	_update_upper(levelled)
	visual.aim_pitch = Game.cam.pitch if (Game.cam and levelled) else 0.0
	_footsteps(delta, hs, on_floor)
	moves.foot_checks(delta, dir)

func _update_upper(levelled: bool) -> void:
	var h := gunner.hold()
	if h == &"pistol":
		visual.upper = &"aim_pistol" if levelled else &""
	elif h == &"rifle" or h == &"launcher":
		visual.upper = &"aim_rifle" if levelled else &"hold_rifle"
	elif gunner.blocking:
		visual.upper = &""
		if visual.state == &"idle" or visual.state == &"walk":
			visual.state = &"block"
	else:
		visual.upper = &""

func _combat_input(_delta: float, blocked: bool) -> void:
	if blocked or Game.cam == null:
		_fire_was = false
		return
	var fire := Input.is_action_pressed("fire")
	var just := fire and not _fire_was
	_fire_was = fire
	var target: Vector3 = Game.cam.aim_point()
	if aiming or fire or combat_timer > 0.0:
		gunner.aim_dir = (target - eye_position()).normalized()
	if fire:
		# stealth takedown has priority over a normal attack
		if just and stealth and gunner.data["cls"] == &"melee" and moves.try_takedown():
			return
		if gunner.data["cls"] != &"melee":
			combat_timer = 0.7
			gunner.aiming = true
		if gunner.trigger(target, just):
			if gunner.is_gun():
				Game.cam.kick(gunner.recoil_kick())
				Game.cam.shake(0.05 + gunner.recoil_kick() * 1.2)
	if Input.is_action_just_pressed("melee_heavy") and gunner.data["cls"] == &"melee":
		gunner.melee(true)
	if Input.is_action_just_pressed("reload"):
		gunner.reload()
	if Input.is_action_just_pressed("grenade"):
		gunner.throw_grenade(Game.cam.forward())
	if Input.is_action_just_pressed("weapon_next"):
		gunner.equip(inventory.cycle(1))
	elif Input.is_action_just_pressed("weapon_prev"):
		gunner.equip(inventory.cycle(-1))
	if Input.is_action_just_pressed("holster"):
		gunner.equip(&"unarmed")
	for i in range(1, 9):
		if Input.is_action_just_pressed("weapon_%d" % i):
			select_slot(i - 1)

func select_slot(slot: int) -> void:
	var list := inventory.owned_in_slot(slot)
	if list.is_empty():
		return
	var i := list.find(gunner.weapon_id)
	gunner.equip(list[(i + 1) % list.size()] if i >= 0 else list[0])

func _landed(height: float) -> void:
	if height > 1.2:
		Audio.play(&"land_hard" if height > 4.0 else &"land", global_position, -6.0)
		Events.noise.emit(global_position, 6.0 + height, &"footstep", self)
	if height > 4.2:
		var resist := 1.0 - 0.3 * (Game.skills.level(&"strength") if Game.skills else 0.0)
		apply_damage((height - 4.2) * 11.0 * resist, null, global_position, Vector3.ZERO, {"type": "fall"})
		if height > 7.5 and alive:
			knockdown(velocity * 0.3, 1.8)
		if Game.cam:
			Game.cam.shake(clampf(height / 14.0, 0.2, 0.9))

func _footsteps(delta: float, hs: float, on_floor: bool) -> void:
	noise_radius = 0.0
	if not on_floor or hs < 0.4:
		return
	_step_acc += hs * delta
	var stride := 1.9 if hs > 5.6 else (1.5 if hs > 2.7 else 1.1)
	var r := 3.5
	if crouched:
		r = 1.2
	elif hs > 5.6:
		r = 11.0
	elif hs > 2.7:
		r = 7.0
	if Game.skills:
		r *= 1.0 - 0.4 * Game.skills.level(&"stealth")
	noise_radius = r
	if _step_acc >= stride:
		_step_acc = 0.0
		var surf := &"concrete"
		var c := get_last_slide_collision()
		if is_on_floor():
			var hit := Game.ray(global_position + Vector3(0, 0.3, 0), global_position - Vector3(0, 0.5, 0), Phys.WORLD | Phys.VEHICLE | Phys.PROP, [get_rid()])
			if not hit.is_empty():
				surf = Ballistics.surface_of(hit["collider"], hit["position"])
		var snd := "footstep_concrete_%d" % (1 + randi() % 4)
		match surf:
			&"dirt", &"ground":
				if global_position.z > Terrain.COAST_Z:
					snd = "footstep_sand_%d" % (1 + randi() % 2)
				else:
					snd = "footstep_grass_%d" % (1 + randi() % 3)
			&"metal": snd = "footstep_metal_%d" % (1 + randi() % 2)
			&"wood": snd = "footstep_wood_%d" % (1 + randi() % 2)
		Audio.play(StringName(snd), global_position, -14.0 if crouched else -9.0, 1.0, 0.08, 30.0)
		Events.noise.emit(global_position, r, &"footstep", self)
		if crouched and Game.skills and hs > 0.5:
			Game.skills.add(&"stealth", 0.0009)

# ---------------------------------------------------------------- swimming
func _enter_swim() -> void:
	state = St.SWIM
	diving = false
	set_crouched(false)
	gunner.equip(&"unarmed", true)
	visual.upper = &""
	if velocity.y < -4.0 and Game.fx:
		Game.fx.splash(Vector3(global_position.x, Game.water_surface(global_position), global_position.z), clampf(-velocity.y / 8.0, 0.6, 2.0))
	velocity.y *= 0.3

func _swim(delta: float) -> void:
	update_water()
	var surface := Game.water_surface(global_position)
	var blocked := Game.ui_blocked()
	var dir := input_dir()
	var head_depth := surface - (global_position.y + 1.55)
	# leave the water when standing in the shallows
	var ground := Game.ground_y(global_position.x, global_position.z)
	if water_depth < 1.05 or (not diving and surface - ground < 1.25):
		if is_on_floor() or surface - ground < 1.25:
			state = St.FOOT
			diving = false
			Audio.set_underwater(false)
			return
	var fast := not blocked and Input.is_action_pressed("sprint") and stamina > 1.0
	var sp := 3.3 if fast else 2.2
	if fast:
		stamina = maxf(0.0, stamina - 7.0 * delta)
		_stamina_wait = 0.9
	else:
		_stamina_wait -= delta
		if _stamina_wait <= 0.0:
			stamina = minf(max_stamina(), stamina + 12.0 * delta)
	if not blocked and Input.is_action_just_pressed("crouch"):
		diving = true
	var target := dir * sp
	if diving:
		# free 3D swimming along the camera direction
		var cam_fwd: Vector3 = Game.cam.forward() if Game.cam else forward()
		var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if not blocked else Vector2.ZERO
		target = cam_fwd * (-iv.y) * sp + Basis(Vector3.UP, camera_yaw()) * Vector3(iv.x, 0, 0) * sp * 0.7
		if not blocked and Input.is_action_pressed("jump"):
			target.y += sp
		if not blocked and Input.is_action_pressed("crouch"):
			target.y -= sp * 0.6
		velocity = velocity.move_toward(target, delta * 6.0)
		if head_depth < 0.1 and target.y >= 0.0:
			diving = false
	else:
		velocity.x = move_toward(velocity.x, target.x, delta * 6.0)
		velocity.z = move_toward(velocity.z, target.z, delta * 6.0)
		var want_y := surface - 1.42
		velocity.y = clampf((want_y - global_position.y) * 4.0, -3.0, 3.0)
	move_and_slide()
	if dir.length() > 0.1:
		turn_toward(dir, delta, 6.0)
	var hs := velocity.length()
	visual.set_state(&"dive" if diving else (&"swim" if hs > 0.5 else &"swim_idle"), hs)
	visual.upper = &""
	# --- breath
	var underwater := head_depth > 0.15
	if underwater:
		breath = maxf(0.0, breath - delta / lung_seconds())
		if breath <= 0.0:
			apply_damage(9.0 * delta, null, global_position, Vector3.ZERO, {"type": "drown"})
	else:
		if breath < 0.25:
			Audio.play_ui(&"breath_gasp", -6.0)
		breath = minf(1.0, breath + delta * 0.6)
	# swimming strokes
	_step_acc += hs * delta
	if _step_acc > 2.2 and not underwater:
		_step_acc = 0.0
		Audio.play(&"swim_stroke", global_position, -10.0)
	if not blocked and Input.is_action_just_pressed("enter_vehicle"):
		_try_enter_vehicle()

# ---------------------------------------------------------------- vehicles
func nearest_vehicle(max_dist := 4.2) -> Vehicle:
	var best: Vehicle = null
	var best_d := max_dist
	for n in get_tree().get_nodes_in_group(&"vehicles"):
		var v := n as Vehicle
		if v.destroyed or v.seats.is_empty():
			continue
		var local := v.to_local(global_position + Vector3(0, 0.8, 0))
		var dx := maxf(absf(local.x) - v.half_width, 0.0)
		var dz := maxf(absf(local.z) - v.half_length, 0.0)
		var dy := maxf(absf(local.y - v.body_height * 0.5) - v.body_height * 0.5 - 0.6, 0.0)
		var d := Vector3(dx, dy, dz).length()
		if d < best_d:
			best_d = d
			best = v
	return best

func _try_enter_vehicle() -> void:
	if _busy:
		return
	var v := nearest_vehicle()
	if v == null:
		return
	if v.locked:
		Game.notify("Locked", "bad")
		return
	var seat_i := 0
	# AI-driven taxi: ride as a passenger instead of stealing it
	if (v.owner_tag == "taxi" or v.has_meta("taxi")) and v.driver() != null and not v.driver().is_player:
		seat_i = v.free_seat(false)
		if seat_i < 0:
			return
	_enter_sequence(v, seat_i)

func _enter_sequence(v: Vehicle, seat_i: int) -> void:
	_busy = true
	state = St.ANIM
	set_crouched(false)
	visual.upper = &""
	gunner.aiming = false
	velocity = Vector3.ZERO
	var door := v.door_position(seat_i)
	var start := global_position
	var dist := start.distance_to(door)
	var walk_t := clampf(dist / 4.5, 0.12, 0.7)
	visual.set_state(&"run" if dist > 1.0 else &"walk", 3.5)
	var t := 0.0
	while t < walk_t:
		if not is_instance_valid(v) or v.destroyed:
			_abort_anim()
			return
		t += get_physics_process_delta_time()
		door = v.door_position(seat_i)
		var k := clampf(t / walk_t, 0.0, 1.0)
		var p := start.lerp(door, k)
		p.y = lerpf(start.y, maxf(door.y, start.y - 0.6), k)
		global_position = p
		turn_toward(v.global_position - global_position, 0.016, 14.0)
		await get_tree().physics_frame
	v.open_door(seat_i, true)
	visual.set_state(&"idle")
	await get_tree().create_timer(0.22).timeout
	if not is_instance_valid(v) or v.destroyed or not alive:
		_abort_anim()
		return
	var occ: Character = v.seats[seat_i]["occupant"]
	if occ != null:
		# carjacking: yank the driver out
		visual.play_upper("Carjack", 1.3)
		Audio.play(&"melee_swing", global_position, -8.0)
		await get_tree().create_timer(0.35).timeout
		if not is_instance_valid(v) or v.destroyed or not alive:
			_abort_anim()
			return
		if v.seats[seat_i]["occupant"] == occ and is_instance_valid(occ):
			var out_pos := v.door_position(seat_i) + (v.door_position(seat_i) - v.global_position).normalized() * 1.1
			v.unseat(seat_i, out_pos)
			if occ.has_method("on_carjacked"):
				occ.on_carjacked(self, v)
			Events.crime.emit(&"carjack", global_position, {"victim": occ, "vehicle": v})
			Game.stats["vehicles_stolen"] += 1
		await get_tree().create_timer(0.2).timeout
	elif v.owner_tag != "player" and not v.personal and v.last_driver != self and v.owner_tag != "":
		# taking a parked / abandoned vehicle that is not yours
		if v.owner_tag == "police" or v.def.get("emergency", false):
			Events.crime.emit(&"steal_police", global_position, {"vehicle": v})
		else:
			Events.crime.emit(&"steal_parked", global_position, {"vehicle": v})
	if not is_instance_valid(v) or v.destroyed or v.seats[seat_i]["occupant"] != null:
		_abort_anim()
		return
	v.seat_character(seat_i, self)
	passenger = seat_i != 0 or (v.ai != null and (v.owner_tag == "taxi" or v.has_meta("taxi")))
	if passenger and (v.owner_tag == "taxi" or v.has_meta("taxi")) and Game.transit != null and Game.transit.has_method("on_board"):
		Game.transit.on_board(v)
	if seat_i == 0 and v.ai != null and v.owner_tag != "taxi" and not v.has_meta("taxi"):
		if v.ai.has_method("release"):
			v.ai.release()
	last_vehicle = v
	state = St.VEHICLE
	_busy = false
	_exit_hold = 0.0
	Events.player_entered_vehicle.emit(v, seat_i)
	await get_tree().create_timer(0.35).timeout
	if is_instance_valid(v):
		v.open_door(seat_i, false)

func _abort_anim() -> void:
	_busy = false
	if alive and state == St.ANIM:
		state = St.FOOT

func _in_vehicle(delta: float) -> void:
	var v := vehicle as Vehicle
	if v == null or not is_instance_valid(v):
		state = St.FOOT
		return
	_seat_align()
	var blocked := Game.ui_blocked()
	if not passenger:
		if blocked:
			v.in_throttle = 0.0
			v.in_steer = 0.0
			v.in_brake = 0.0
			v.in_pitch = 0.0
			v.in_roll = 0.0
			v.in_yaw = 0.0
			v.in_lift = 0.0
		else:
			var fb := Input.get_axis("move_back", "move_forward")
			var lr := Input.get_axis("move_left", "move_right")
			var skill := Game.skills.level(&"driving") if Game.skills else 0.0
			if v is Heli or v is Airplane:
				v.in_pitch = fb
				v.in_roll = lr
				v.in_yaw = Input.get_axis("yaw_left", "yaw_right")
				v.in_lift = Input.get_axis("air_down", "air_up")
				v.in_handbrake = Input.is_action_pressed("handbrake")
			else:
				v.in_throttle = fb
				v.in_steer = lr
				v.in_handbrake = Input.is_action_pressed("handbrake")
				v.in_brake = 0.0
				if v is Car:
					(v as Car).grip_scale_mod = maxf((v as Car).grip_scale_mod, 1.0 + 0.06 * skill)
					if Game.skills and absf(v.speed) > 12.0:
						Game.skills.add(&"driving", delta * 0.0012)
			var horn_now := Input.is_action_pressed("horn")
			if horn_now != _horn_held:
				_horn_held = horn_now
				v.horn(horn_now)
			if Input.is_action_just_pressed("headlights"):
				v.toggle_lights()
			if Input.is_action_just_pressed("siren"):
				v.set_siren(not v.siren_on)
		_drive_by(delta, blocked)
	# steering-wheel hands
	if v is Car and not (v as Car).two_wheel and not passenger and gunner.cooldown <= 0.0 and not aiming:
		var sw := v.part("steering")
		if sw != null:
			var b := sw.global_transform.basis
			visual.set_ik_hands(sw.global_position - b.x * 0.17 + b.y * 0.03, sw.global_position + b.x * 0.17 + b.y * 0.03)
	elif v is Car and (v as Car).two_wheel:
		var hl := v.part("hand_l")
		var hr := v.part("hand_r")
		if hl != null and hr != null:
			visual.set_ik_hands(hl.global_position, hr.global_position)
	# exit: tap = get out, in fast / flying vehicles you bail
	if not blocked and Input.is_action_just_pressed("enter_vehicle") and not _busy:
		_exit_vehicle()

func _drive_by(_delta: float, blocked: bool) -> void:
	var v := vehicle as Vehicle
	aiming = false
	if blocked or Game.cam == null:
		return
	var w := gunner.data
	var allowed := bool(w.get("driveby", false)) and not (v is Heli and not passenger) and not (v is Airplane)
	if not allowed:
		if Input.is_action_just_pressed("fire") and gunner.weapon_id != &"unarmed":
			# swap to a usable sidearm automatically
			for id in [&"smg", &"pistol", &"revolver"]:
				if inventory.has(id):
					gunner.equip(id)
					break
		visual.upper = &""
		gunner.aiming = false
		return
	var fire := Input.is_action_pressed("fire")
	var aim := Input.is_action_pressed("aim")
	gunner.driveby = true
	gunner.aiming = aim or fire
	aiming = gunner.aiming
	if gunner.aiming:
		var target: Vector3 = Game.cam.aim_point()
		# cannot shoot through your own car: only out of the side you look at
		gunner.aim_dir = (target - eye_position()).normalized()
		visual.upper = &"aim_one"
		visual.aim_pitch = 0.0
		visual.look_yaw = clampf(angle_difference(v.global_rotation.y, Game.cam.yaw), -1.2, 1.2)
		var just := Input.is_action_just_pressed("fire")
		if fire and gunner.trigger(target, just):
			Game.cam.kick(gunner.recoil_kick() * 0.7)
	else:
		visual.upper = &""
		visual.look_yaw = 0.0
	if Input.is_action_just_pressed("grenade"):
		gunner.throw_grenade(Game.cam.forward())
	if Input.is_action_just_pressed("weapon_next") or Input.is_action_just_pressed("weapon_prev"):
		var order: Array[StringName] = [&"pistol", &"smg", &"revolver"]
		var have: Array[StringName] = []
		for id in order:
			if inventory.has(id):
				have.append(id)
		if not have.is_empty():
			var i := have.find(gunner.weapon_id)
			gunner.equip(have[(i + 1) % have.size()])
	if Input.is_action_just_pressed("reload"):
		gunner.reload()

func _exit_vehicle() -> void:
	var v := vehicle as Vehicle
	if v == null:
		return
	var seat_i := seat
	var fast := v.linear_velocity.length() > 9.0
	var airborne := (v is Heli and (v as Heli).is_flying()) or (v is Airplane and (v as Airplane).is_flying())
	_horn_held = false
	v.horn(false)
	visual.look_yaw = 0.0
	if airborne:
		var pos := v.global_position + v.global_transform.basis.x * (v.half_width + 1.2) * float(v.seats[seat_i]["side"]) - Vector3(0, 0.5, 0)
		var vel := v.linear_velocity
		v.unseat(seat_i, pos)
		velocity = vel
		state = St.FOOT
		passenger = false
		Events.player_exited_vehicle.emit(v)
		moves.start_freefall()
		return
	if fast:
		# bail out of a moving vehicle
		var vel2 := v.linear_velocity
		v.unseat(seat_i)
		velocity = vel2 * 0.8
		state = St.FOOT
		passenger = false
		Events.player_exited_vehicle.emit(v)
		apply_damage(clampf((vel2.length() - 9.0) * 1.6, 2.0, 35.0), null, global_position, Vector3.ZERO, {"type": "fall"})
		if alive:
			knockdown(vel2 * 0.7, 1.6)
		return
	_busy = true
	state = St.ANIM
	v.in_throttle = 0.0
	v.in_handbrake = true
	v.open_door(seat_i, true)
	await get_tree().create_timer(0.22).timeout
	if is_instance_valid(v) and vehicle == v:
		v.unseat(seat_i)
		Events.player_exited_vehicle.emit(v)
		var vv := v
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if is_instance_valid(vv):
				vv.open_door(seat_i, false))
	passenger = false
	_busy = false
	if alive:
		state = St.FOOT

## Instantly seat the player (admin spawns, taxi skips, garage deliveries). No animation.
func warp_into(v: Vehicle, seat_i := 0) -> bool:
	if v == null or v.destroyed or not alive or _busy:
		return false
	if state == St.VEHICLE:
		force_exit_vehicle()
	elif state == St.SWIM or state == St.MOVE:
		moves.cancel()
	if seat_i < 0 or seat_i >= v.seat_count():
		return false
	var occ: Character = v.seats[seat_i]["occupant"]
	if occ != null:
		v.unseat(seat_i)
		if occ is NPC:
			(occ as NPC).flee(global_position)
	set_crouched(false)
	visual.upper = &""
	gunner.aiming = false
	v.seat_character(seat_i, self)
	passenger = seat_i != 0
	if seat_i == 0 and v.ai != null and v.ai.has_method("release"):
		v.ai.release()
	last_vehicle = v
	state = St.VEHICLE
	Events.player_entered_vehicle.emit(v, seat_i)
	if Game.cam:
		Game.cam.snap()
	return true

func force_exit_vehicle() -> void:
	if state == St.VEHICLE and vehicle != null and not _busy:
		var v := vehicle as Vehicle
		v.unseat(seat)
		passenger = false
		state = St.FOOT
		Events.player_exited_vehicle.emit(v)

# ---------------------------------------------------------------- prompts
func _update_prompt(delta: float) -> void:
	_prompt_cd -= delta
	if _prompt_cd > 0.0:
		return
	_prompt_cd = 0.12
	_interact = null
	_near_vehicle = null
	var text := ""
	if state == St.FOOT and not down:
		_interact = Interactable.nearest(global_position)
		if _interact != null:
			text = "[E] " + _interact.prompt
		else:
			_near_vehicle = nearest_vehicle()
			if _near_vehicle != null:
				var d := _near_vehicle.driver()
				var verb := "Enter"
				if d != null and not d.is_player:
					verb = "Ride in" if (_near_vehicle.owner_tag == "taxi" or _near_vehicle.has_meta("taxi")) else "Hijack"
				text = "[F] %s %s" % [verb, String(_near_vehicle.def.get("name", "vehicle"))]
		var extra := moves.prompt()
		if extra != "":
			text = extra if text == "" else text + "   " + extra
	elif state == St.SWIM:
		_near_vehicle = nearest_vehicle(5.0)
		if _near_vehicle != null:
			text = "[F] Board " + String(_near_vehicle.def.get("name", "vehicle"))
	if Game.hud and Game.hud.has_method("set_prompt"):
		Game.hud.set_prompt(text)

# ---------------------------------------------------------------- damage / death / arrest
func _on_damaged(amount: float, _source: Node, _hit_pos: Vector3, _dir: Vector3, info: Dictionary) -> void:
	if amount > 1.0 and String(info.get("type", "")) != "drown":
		Audio.play_ui(StringName("hurt_%d" % (1 + randi() % 3)), -8.0)
	if Game.cam:
		Game.cam.shake(clampf(amount / 60.0, 0.05, 0.5))
	if Game.hud and Game.hud.has_method("damage_flash"):
		Game.hud.damage_flash(clampf(amount / 40.0, 0.15, 1.0))

func apply_damage(amount: float, source: Node = null, hit_pos := Vector3.ZERO, dir := Vector3.ZERO, info: Dictionary = {}) -> void:
	if state == St.DEAD or state == St.BUSTED:
		return
	if gunner and gunner.blocking and String(info.get("type", "")) == "melee":
		amount *= 0.25
	super.apply_damage(amount, source, hit_pos, dir, info)

func _on_died(killer: Node) -> void:
	state = St.DEAD
	_respawn_timer = 5.0
	_busy = false
	passenger = false
	diving = false
	Audio.set_underwater(false)
	Game.stats["deaths"] += 1
	Game.set_slowmo("death", 0.45)
	Audio.play_ui(&"ui_wasted", -2.0)
	Events.player_died.emit("killed" if killer != null else "accident")
	Game.banner("WASTED", "", Color(0.85, 0.15, 0.12), 4.0)

## Arrest by the police (WantedSystem decides when).
func busted() -> void:
	if state == St.DEAD or state == St.BUSTED:
		return
	if state == St.VEHICLE:
		force_exit_vehicle()
	state = St.BUSTED
	_respawn_timer = 4.0
	velocity = Vector3.ZERO
	visual.upper = &""
	visual.set_state(&"surrender")
	gunner.aiming = false
	Game.stats["busted"] += 1
	Audio.play_ui(&"ui_busted", -2.0)
	Events.player_busted.emit()
	Game.banner("BUSTED", "", Color(0.25, 0.5, 1.0), 3.5)

func _respawn() -> void:
	Game.set_slowmo("death", 1.0)
	var was_busted := state == St.BUSTED
	var where := Vector3(80.0, 0.3, -241.5)
	var world: World = Game.world
	if world and world.city:
		var loc_id := "police_hq" if was_busted else "hospital"
		if world.city.locations.has(loc_id):
			var l: Dictionary = world.city.locations[loc_id]
			where = l.get("release" if was_busted else "respawn", l["pos"])
	if vehicle != null and is_instance_valid(vehicle):
		(vehicle as Vehicle).eject(self)
	alive = true
	down = false
	health = max_health
	breath = 1.0
	stamina = max_stamina()
	collision_layer = _body_layer
	collision_mask = _body_mask
	global_position = where + Vector3(0, 0.2, 0)
	velocity = Vector3.ZERO
	set_face_yaw(PI)
	visual.stop_ragdoll()
	visual.stop_action()
	visual.set_state(&"idle")
	gunner.refresh_model()
	# consequences: hospital bill or fine + confiscated ammo
	var fee := mini(int(Game.cash * 0.1), 800) if not was_busted else mini(int(Game.cash * 0.12), 1200)
	if fee > 0:
		Game.add_cash(-fee, false)
	money_lost = fee
	if was_busted:
		for id in inventory.items.keys():
			inventory.items[id]["reserve"] = int(int(inventory.items[id]["reserve"]) * 0.5)
		inventory.changed.emit()
		Game.notify("Released from VBPD custody. Fine: $%d, half your ammo confiscated." % fee, "bad")
	else:
		Game.notify("Vesper General patched you up. Bill: $%d" % fee, "info")
	state = St.FOOT
	if Game.cam:
		Game.cam.snap()
	if Game.time:
		Game.time.advance_hours(3.0)
	Events.player_respawned.emit()

func teleport(pos: Vector3, yaw := 0.0) -> void:
	if state == St.VEHICLE and vehicle != null:
		var v := vehicle as Vehicle
		v.global_position = pos + Vector3(0, 0.6, 0)
		v.global_rotation = Vector3(0, yaw, 0)
		v.linear_velocity = Vector3.ZERO
		v.angular_velocity = Vector3.ZERO
	else:
		if state == St.SWIM or state == St.MOVE:
			moves.cancel()
			state = St.FOOT
		global_position = pos + Vector3(0, 0.15, 0)
		velocity = Vector3.ZERO
		set_face_yaw(yaw)
	if Game.cam:
		Game.cam.snap()

# ---------------------------------------------------------------- persistence
func save_state() -> Dictionary:
	var pos := global_position
	return {
		"pos": SaveSystem.v3(pos), "yaw": face_yaw, "health": health, "armor": armor,
		"inventory": inventory.save_state(), "appearance": appearance, "stamina": stamina,
		"parachute": parachute, "scuba": scuba,
		"vehicle": (vehicle as Vehicle).vid if (vehicle != null and is_instance_valid(vehicle)) else "",
	}

func load_state(d: Dictionary) -> void:
	if state == St.VEHICLE:
		force_exit_vehicle()
	moves.cancel()
	state = St.FOOT
	alive = true
	down = false
	health = clampf(float(d.get("health", 100.0)), 1.0, max_health)
	armor = float(d.get("armor", 0.0))
	parachute = bool(d.get("parachute", false))
	scuba = bool(d.get("scuba", false))
	inventory.load_state(d.get("inventory", {}))
	if d.has("appearance") and typeof(d["appearance"]) == TYPE_DICTIONARY:
		set_appearance(d["appearance"])
	gunner.equip(inventory.current, true)
	teleport(SaveSystem.to_v3(d.get("pos", [0, 0, 0]), global_position), float(d.get("yaw", 0.0)))
