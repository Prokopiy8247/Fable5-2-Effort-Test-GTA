class_name Player
extends Humanoid
# Player controller: on-foot movement, cover, stealth, vault, ladders, swimming/diving,
# parachute, vehicles (enter / carjack / drive-by), shooting, melee, interaction.

var stamina := 100.0
var breath := 20.0
var has_parachute := false
var has_scuba := false
var chute: Node3D
var air_t := 0.0
var fall_v := 0.0
var face_cam_t := 0.0
var zoomed := false
var combo := 0
var combo_t := 0.0
var cover_n := Vector3.ZERO
var cover_low := false
var cover_edge := 0.0
var cover_out := 0.0
var ladder: Dictionary = {}
var death_t := 0.0
var busted := false
var last_shot_t := -100.0
var disguise_t := -100.0
var noise := 0.0
var prompt := ""
var prompt_action: Callable
var tween_lock := false
var passenger_of = null
var jump_buf := 0.0
var wheel_open := false
var test_input = null
var test_lift := 0.0


func _ready() -> void:
	is_player = true
	setup({"female": false, "skin": Color(0.85, 0.64, 0.48), "shirt": Color(0.75, 0.12, 0.12), "pants": Color(0.22, 0.3, 0.45), "shoes": Color(0.9, 0.9, 0.9),
		"hair": "acc_hair_short", "hair_color": Color(0.2, 0.13, 0.08), "hat": "", "glasses": "", "beard": ""})
	collision_mask = G.L_WORLD | G.L_VEH | G.L_PROP | G.L_CHAR
	give_weapon("pistol", 60)
	equip("fists")
	breath = max_breath()


func max_breath() -> float:
	return 300.0 if has_scuba else 15.0 + 45.0 * G.skill("lung")


func key(k: int) -> bool:
	return Input.is_physical_key_pressed(k)


func locked() -> bool:
	return G.menus.blocking() or dead or busted or tween_lock


# ---------------------------------------------------------------- input events
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and not locked() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle_weapon(-1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle_weapon(1)
		elif e.button_index == MOUSE_BUTTON_MIDDLE:
			if state in ["normal", "cover"]:
				melee_attack(true)
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: int = e.physical_keycode
	if locked():
		return
	match k:
		KEY_F:
			if state == "vehicle":
				exit_vehicle()
			elif state in ["normal", "swim", "cover"]:
				try_enter_vehicle()
			elif state == "chute":
				_end_chute()
		KEY_E:
			if prompt_action.is_valid() and prompt != "":
				prompt_action.call()
		KEY_SPACE:
			jump_buf = 0.15
		KEY_C:
			if state == "normal":
				crouching = not crouching
				capsule.height = 1.25 if crouching else 1.8
				cshape.position.y = capsule.height / 2
		KEY_Q:
			if state == "normal":
				try_cover()
			elif state == "cover":
				state = "normal"
				crouching = false
		KEY_R:
			if state == "vehicle":
				pass
			reload()
		KEY_V:
			G.cam.first_person = not G.cam.first_person
		KEY_H:
			if vehicle != null:
				vehicle.horn()
		KEY_L:
			if vehicle != null:
				vehicle.lights_on = not vehicle.lights_on
		KEY_G:
			if vehicle != null and vehicle.def.get("siren", false):
				vehicle.siren_on = not vehicle.siren_on
		KEY_Z:
			if vehicle != null:
				G.audio.set_station(G.audio.station + 1)
				G.notify("Radio: " + G.audio.stations[G.audio.station], 2.0)
		KEY_X:
			if state == "normal" and aiming and is_on_floor():
				_roll()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
			select_slot(k - KEY_1)


func cycle_weapon(dir: int) -> void:
	var list: Array = []
	for w in Defs.WEAPON_ORDER:
		if w in owned and _allowed(w):
			list.append(w)
	if list.is_empty():
		return
	var i := list.find(weapon)
	equip(list[wrapi(i + dir, 0, list.size())])


func select_slot(slot: int) -> void:
	var list: Array = []
	for w in Defs.WEAPON_ORDER:
		if w in owned and Defs.WEAPONS[w].slot == slot and _allowed(w):
			list.append(w)
	if list.is_empty():
		return
	var i := list.find(weapon)
	equip(list[(i + 1) % list.size()])


func _allowed(w: String) -> bool:
	if state != "vehicle":
		return true
	var d: Dictionary = Defs.WEAPONS[w]
	return d.get("onehand", false) or w == "fists"


# ---------------------------------------------------------------- main loop
func _physics_process(dt: float) -> void:
	tick(dt)
	jump_buf = max(0.0, jump_buf - dt)
	face_cam_t = max(0.0, face_cam_t - dt)
	combo_t = max(0.0, combo_t - dt)
	roll_t = max(0.0, roll_t - dt)
	prompt = ""
	if dead:
		_dead(dt)
	elif busted:
		pass
	else:
		match state:
			"vehicle": _vehicle(dt)
			"ragdoll": _ragdoll_physics(dt)
			"swim": _swim(dt)
			"climb": _climb(dt)
			"chute": _chute(dt)
			"cover": _cover(dt)
			"enter": pass
			_: _normal(dt)
		_scan_prompts()
	_animate(dt)
	if chute:
		chute.visible = state == "chute"
	# regen
	if not dead and health < max_health * 0.5 and G.time_now - last_hit_t > 8.0:
		health = min(max_health * 0.5, health + dt * 2.0)
	if global_position.y < -40.0:
		global_position = G.locations.get("Safehouse", Vector3(0, 2, 0))
		velocity = Vector3.ZERO


var last_hit_t := -100.0


func _damaged(amount: float, attacker, kind: String) -> void:
	last_hit_t = G.time_now
	if amount > 1.0:
		G.hud.flash_damage(clamp(amount / 40.0, 0.2, 1.0))
		G.cam.shake(clamp(amount / 80.0, 0.05, 0.5))


func _died(_attacker, _kind: String) -> void:
	death_t = 0.0
	if vehicle != null:
		force_exit()
	G.hud.big_text("WASTED", Color(0.8, 0.1, 0.1))


func _dead(dt: float) -> void:
	_ragdoll_physics(dt)
	death_t += dt
	if death_t > 4.0:
		respawn(G.locations.get("Hospital", Vector3(80, 0.4, -36)))
		G.add_money(-min(500, int(G.money * 0.05)))


func respawn(pos: Vector3) -> void:
	G.hud.fade()
	dead = false
	busted = false
	health = max_health
	state = "normal"
	collision_layer = G.L_CHAR
	global_position = pos + Vector3.UP * 0.3
	velocity = Vector3.ZERO
	crouching = false
	breath = max_breath()
	rag_t = 0.0
	if G.wanted:
		G.wanted.clear()


func warp(pos: Vector3) -> void:
	G.hud.fade()
	if vehicle != null:
		vehicle.global_position = pos + Vector3.UP * 0.6
		vehicle.linear_velocity = Vector3.ZERO
		vehicle.angular_velocity = Vector3.ZERO
		vehicle.rotation = Vector3(0, vehicle.rotation.y, 0)
	else:
		global_position = pos + Vector3.UP * 0.2
		velocity = Vector3.ZERO
		state = "normal"


func get_busted() -> void:
	if busted or dead:
		return
	busted = true
	if vehicle != null:
		exit_vehicle()
	state = "surrender"
	velocity = Vector3.ZERO
	G.hud.big_text("BUSTED", Color(0.2, 0.4, 1.0))
	await get_tree().create_timer(3.0).timeout
	G.add_money(-min(800, int(G.money * 0.1)))
	for w in reserve:
		reserve[w] = int(reserve[w] * 0.5)
	respawn(G.locations.get("Police Station", Vector3(84, 0.4, -116)))


func collect(type: String, amount: int) -> bool:
	if type == "cash":
		G.add_money(amount)
		G.notify("+$%d" % amount, 2.0)
	elif type == "health":
		if health >= max_health:
			return false
		health = min(max_health, health + amount)
	elif type == "armor":
		if armor >= 100.0:
			return false
		armor = min(100.0, armor + amount)
	elif type == "ammo":
		for w in owned:
			if Defs.WEAPONS[w].has("mag"):
				give_weapon(w)
		G.notify("Ammo refilled", 2.0)
	elif type == "parachute":
		if has_parachute:
			return false
		set_parachute(true)
		G.notify("Parachute equipped: press SPACE while falling", 4.0)
	elif type == "scuba":
		has_scuba = true
		attach("pack", "acc_scuba", "chest")
		breath = max_breath()
		G.notify("Scuba gear equipped: extended dive time", 4.0)
	elif type.begins_with("weapon:"):
		var w2 := type.substr(7)
		give_weapon(w2)
		G.notify("Picked up " + Defs.WEAPONS[w2].name, 2.5)
	G.audio.ui("pickup")
	return true


func set_parachute(on: bool) -> void:
	has_parachute = on
	if not has_scuba:
		attach("pack", "acc_parachute_pack" if on else "", "chest")


# ---------------------------------------------------------------- on foot
func _move_input() -> Vector3:
	if locked():
		return Vector3.ZERO
	var iv := Vector2((1.0 if key(KEY_D) else 0.0) - (1.0 if key(KEY_A) else 0.0), (1.0 if key(KEY_S) else 0.0) - (1.0 if key(KEY_W) else 0.0))
	if iv.length() < 0.1:
		return Vector3.ZERO
	return (Basis(Vector3.UP, G.cam.yaw) * Vector3(iv.x, 0, iv.y)).normalized()


func _face(dir: Vector3, dt: float, rate := 12.0) -> void:
	if dir.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), min(1.0, dt * rate))


func _normal(dt: float) -> void:
	var dir := _move_input()
	var can_act := not locked()
	var rmb := can_act and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var lmb := can_act and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not wheel_open
	var melee: bool = wdef().get("melee", false)
	blocking = rmb and melee
	aiming = (rmb and not melee) or (face_cam_t > 0.0 and not melee)
	zoomed = rmb
	aim_pitch = G.cam.pitch
	var sprint := can_act and key(KEY_SHIFT) and stamina > 1.0 and not crouching and not aiming and dir != Vector3.ZERO
	var speed := 4.4
	if crouching: speed = 2.0
	elif aiming or blocking: speed = 2.4
	elif key(KEY_ALT): speed = 1.9
	elif sprint: speed = 7.0 + 1.2 * G.skill("stamina")
	if sprint:
		stamina = max(0.0, stamina - dt * (14.0 - 8.0 * G.skill("stamina")))
		G.skill_gain("stamina", dt * 0.12)
	else:
		stamina = min(100.0, stamina + dt * 12.0)
	noise = 0.0
	if dir != Vector3.ZERO:
		noise = 2.5 if crouching else (12.0 if sprint else 6.0)
		noise *= 1.0 - 0.5 * G.skill("stealth")
		if crouching:
			G.skill_gain("stealth", dt * 0.08)
	var on_floor := is_on_floor()
	var acc := 34.0 if on_floor else 7.0
	if roll_t > 0.0:
		speed = 7.5
		dir = -global_basis.z if dir == Vector3.ZERO else dir
		acc = 80.0
	velocity.x = move_toward(velocity.x, dir.x * speed, acc * dt)
	velocity.z = move_toward(velocity.z, dir.z * speed, acc * dt)
	velocity.y -= GRAV * dt
	if aiming and roll_t <= 0.0:
		rotation.y = lerp_angle(rotation.y, G.cam.yaw, min(1.0, dt * 18.0))
	else:
		_face(dir, dt)
	# jump / vault / parachute
	if jump_buf > 0.0 and can_act:
		if on_floor:
			jump_buf = 0.0
			if not _try_vault():
				velocity.y = 7.2
				crouching = false
				capsule.height = 1.8
				cshape.position.y = 0.9
		elif has_parachute and air_t > 0.7 and global_position.y - max(G.height(global_position.x, global_position.z), G.WATER_Y) > 10.0:
			jump_buf = 0.0
			_start_chute()
			return
	if not on_floor:
		air_t += dt
		fall_v = min(fall_v, velocity.y)
	move_and_slide()
	if is_on_floor() and not on_floor:
		_landed()
	if is_on_floor():
		air_t = 0.0
		fall_v = 0.0
	# water
	if global_position.y < G.WATER_Y - 1.15:
		if fall_v < -6.0 or velocity.y < -6.0:
			G.fx.splash(global_position)
		state = "swim"
		crouching = false
		fall_v = 0.0
		air_t = 0.0
		return
	# combat
	if lmb and roll_t <= 0.0:
		_attack(melee)


func _landed() -> void:
	if fall_v < -15.0:
		var dmg := (-fall_v - 15.0) * 7.0
		take_damage(dmg, null, global_position, Vector3.UP, "fall")
		if fall_v < -19.0 and not dead:
			knockdown(Vector3(velocity.x, 2.0, velocity.z))


func _attack(melee: bool) -> void:
	if melee:
		if fire_cd <= 0.0:
			combo = combo + 1 if combo_t > 0.0 else 1
			var heavy := combo >= 3 or key(KEY_SHIFT)
			if heavy:
				combo = 0
			combo_t = 1.0
			melee_attack(heavy)
			_melee_crime()
		return
	var d := wdef()
	if not d.get("auto", false) and not _just_lmb:
		return
	face_cam_t = 0.9
	var sm := 1.0
	if not zoomed: sm *= 1.7
	if crouching: sm *= 0.75
	if Vector2(velocity.x, velocity.z).length() > 3.0: sm *= 1.4
	if state == "cover" and not zoomed: sm *= 2.2
	sm *= 1.0 - 0.35 * G.skill("shooting")
	if fire(G.cam.aim_origin(), G.cam.aim_dir(), sm):
		_after_shot(d)


var _just_lmb := false
var _lmb_prev := false


func _process(_dt: float) -> void:
	var l := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if l and not _lmb_prev:
		_just_lmb = true
	_lmb_prev = l


func _after_shot(d: Dictionary) -> void:
	_just_lmb = false
	last_shot_t = G.time_now
	var has: Array = atts.get(weapon, [])
	var rc: float = d.recoil * (0.7 if "grip" in has else 1.0) * (1.0 - 0.4 * G.skill("shooting")) * (1.1 if "suppressor" in has else 1.0)
	G.cam.kick(rc * 0.6)
	G.cam.shake(0.05 + d.recoil * 0.02)
	G.skill_gain("shooting", 0.05)
	if G.wanted:
		G.wanted.crime("gunfire_quiet" if "suppressor" in has else "gunfire", global_position)


func _melee_crime() -> void:
	pass


func _roll() -> void:
	roll_t = 0.55
	fire_cd = 0.6


func _try_vault() -> bool:
	var fwd := -global_basis.z
	var base := global_position
	var mask := G.L_WORLD | G.L_PROP | G.L_VEH
	var low := G.ray(base + Vector3.UP * 0.45, base + Vector3.UP * 0.45 + fwd * 0.9, mask, [self])
	if low.is_empty():
		return false
	for top_h in [1.3, 2.4]:
		var clear := G.ray(base + Vector3.UP * (top_h + 0.25), base + Vector3.UP * (top_h + 0.25) + fwd * 1.1, mask, [self])
		if not clear.is_empty():
			continue
		var down := G.ray(base + Vector3.UP * (top_h + 0.25) + fwd * 0.95, base + fwd * 0.95 + Vector3.UP * 0.2, mask, [self])
		if down.is_empty():
			continue
		var top: Vector3 = down.position
		if top.y - base.y < 0.35:
			return false
		tween_lock = true
		state = "enter"
		velocity = Vector3.ZERO
		var tw := create_tween()
		var dur: float = 0.3 + (top.y - base.y) * 0.22
		tw.tween_property(self, "global_position", Vector3(base.x, top.y + 0.05, base.z), dur * 0.6)
		tw.tween_property(self, "global_position", top + Vector3.UP * 0.05 + fwd * 0.2, dur * 0.4)
		tw.tween_callback(func():
			tween_lock = false
			state = "normal")
		return true
	return false


# ---------------------------------------------------------------- cover
func try_cover() -> void:
	var mask := G.L_WORLD | G.L_PROP | G.L_VEH
	var best := {}
	var bd := 1.6
	for i in 8:
		var d := Vector3(sin(i * TAU / 8), 0, cos(i * TAU / 8))
		var hit := G.ray(global_position + Vector3.UP * 0.6, global_position + Vector3.UP * 0.6 + d * 1.6, mask, [self])
		if not hit.is_empty() and abs(hit.normal.y) < 0.4:
			var dist: float = hit.position.distance_to(global_position)
			if dist < bd:
				bd = dist
				best = hit
	if best.is_empty():
		G.notify("No cover nearby", 1.5)
		return
	cover_n = Vector3(best.normal.x, 0, best.normal.z).normalized()
	var hi := G.ray(global_position + Vector3.UP * 1.5, global_position + Vector3.UP * 1.5 - cover_n * 2.0, mask, [self])
	cover_low = hi.is_empty()
	global_position = Vector3(best.position.x, global_position.y, best.position.z) + cover_n * 0.45
	state = "cover"
	velocity = Vector3.ZERO
	cover_out = 0.0


func _cover(dt: float) -> void:
	var mask := G.L_WORLD | G.L_PROP | G.L_VEH
	var tangent := cover_n.cross(Vector3.UP)
	var cam_right: Vector3 = G.cam.global_basis.x
	var sgn: float = 1.0 if tangent.dot(cam_right) > 0.0 else -1.0
	var ix := (1.0 if key(KEY_D) else 0.0) - (1.0 if key(KEY_A) else 0.0)
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not locked()
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not locked() and not wheel_open
	var melee: bool = wdef().get("melee", false)
	aiming = (rmb or face_cam_t > 0.0) and not melee
	zoomed = rmb
	aim_pitch = G.cam.pitch
	crouching = cover_low and not rmb
	velocity = Vector3.ZERO
	if ix != 0.0 and not rmb:
		var mv := tangent * sgn * ix
		var np := global_position + mv * 0.45
		var chk := G.ray(np + Vector3.UP * 0.6, np + Vector3.UP * 0.6 - cover_n * 1.1, mask, [self])
		if not chk.is_empty():
			velocity = mv * 2.2
			cover_edge = 0.0
			cover_n = Vector3(chk.normal.x, 0, chk.normal.z).normalized()
		else:
			cover_edge = sgn * ix
			# round a convex corner onto the adjacent face
			var around := G.ray(np + Vector3.UP * 0.6 - cover_n * 0.9, np + Vector3.UP * 0.6 - cover_n * 0.9 - mv * 1.2, mask, [self])
			if not around.is_empty() and key(KEY_SHIFT):
				cover_n = Vector3(around.normal.x, 0, around.normal.z).normalized()
				global_position = Vector3(around.position.x, global_position.y, around.position.z) + cover_n * 0.45
	# peek out sideways at an edge of tall cover while aiming
	var want_out := 0.0
	if rmb and not cover_low and cover_edge != 0.0:
		want_out = 0.7
	var delta_out: float = move_toward(cover_out, want_out, dt * 4.0) - cover_out
	cover_out += delta_out
	velocity += tangent * cover_edge * delta_out / max(dt, 0.001)
	velocity.y = -2.0
	move_and_slide()
	if aiming:
		rotation.y = lerp_angle(rotation.y, G.cam.yaw, min(1.0, dt * 18.0))
	else:
		_face(cover_n, dt)
	noise = 0.0
	if lmb and not melee:
		_attack(false)
	if key(KEY_S) and not rmb or jump_buf > 0.0:
		state = "normal"
		crouching = false
	var still := G.ray(global_position + Vector3.UP * 0.6, global_position + Vector3.UP * 0.6 - cover_n * 1.4, mask, [self])
	if still.is_empty() and cover_out < 0.1:
		state = "normal"
		crouching = false
	capsule.height = 1.25 if crouching else 1.8
	cshape.position.y = capsule.height / 2


# ---------------------------------------------------------------- swimming / diving
func _swim(dt: float) -> void:
	var surf := G.WATER_Y - 1.42
	var dir := _move_input()
	var speed := 2.7 + (1.2 if key(KEY_SHIFT) else 0.0) + G.skill("stamina") * 0.6
	velocity.x = move_toward(velocity.x, dir.x * speed, 8.0 * dt)
	velocity.z = move_toward(velocity.z, dir.z * speed, 8.0 * dt)
	var vy := 0.0
	var down := (key(KEY_CTRL) or key(KEY_C)) and not locked()
	var upk := key(KEY_SPACE) and not locked()
	if down: vy = -2.4
	elif upk: vy = 2.6
	elif global_position.y < surf - 0.4 and dir == Vector3.ZERO: vy = 0.35
	if global_position.y >= surf and vy > 0.0:
		vy = 0.0
	if global_position.y > surf + 0.05:
		vy = -1.5
	velocity.y = move_toward(velocity.y, vy, 9.0 * dt)
	_face(dir, dt, 6.0)
	move_and_slide()
	aiming = false
	var under := global_position.y < surf - 0.45
	if under:
		breath -= dt
		G.skill_gain("lung", dt * 0.25)
		if breath <= 0.0:
			breath = 0.0
			take_damage(9.0 * dt, null, global_position, Vector3.UP, "drown")
	else:
		breath = min(max_breath(), breath + dt * 12.0)
	if dir != Vector3.ZERO:
		G.skill_gain("stamina", dt * 0.06)
	var gh := G.height(global_position.x, global_position.z)
	if gh > G.WATER_Y - 1.1 and global_position.y > G.WATER_Y - 1.2 and is_on_floor():
		state = "normal"
	if global_position.y > G.WATER_Y - 0.6:
		state = "normal"


# ---------------------------------------------------------------- ladders
func _climb(dt: float) -> void:
	var up := (1.0 if key(KEY_W) else 0.0) - (1.0 if key(KEY_S) else 0.0)
	if locked():
		up = 0.0
	global_position.y += up * 2.3 * dt
	walk_phase += abs(up) * dt * 7.0
	velocity = Vector3.ZERO
	_face(ladder.dir, dt)
	if global_position.y >= ladder.pos.y + ladder.h - 0.3:
		global_position = ladder.top
		state = "normal"
	elif global_position.y < ladder.pos.y - 0.05 or jump_buf > 0.0:
		state = "normal"


# ---------------------------------------------------------------- parachute
func _start_chute() -> void:
	state = "chute"
	if chute == null:
		chute = G.model("props/prop_parachute")
		chute.scale = Vector3.ONE * 0.8
		chute.position = Vector3(0, 1.1, 0)
		add_child(chute)
	G.audio.play3d("chute", global_position)
	velocity.y = max(velocity.y, -6.0)


func _end_chute() -> void:
	state = "normal"
	set_parachute(false)
	air_t = 0.0
	fall_v = velocity.y


func _chute(dt: float) -> void:
	var turn := (1.0 if key(KEY_A) else 0.0) - (1.0 if key(KEY_D) else 0.0)
	rotation.y += turn * 1.3 * dt
	var fwd := -global_basis.z
	var fs := 8.0
	var sink := -4.5
	if key(KEY_S):
		fs = 4.0
		sink = -2.3
	elif key(KEY_W):
		fs = 13.0
		sink = -8.5
	velocity.x = lerp(velocity.x, fwd.x * fs, dt * 2.0)
	velocity.z = lerp(velocity.z, fwd.z * fs, dt * 2.0)
	velocity.y = lerp(velocity.y, sink, dt * 2.5)
	var vy := velocity.y
	move_and_slide()
	if is_on_floor() or global_position.y < G.WATER_Y - 1.0:
		if vy < -7.0:
			take_damage((-vy - 7.0) * 9.0, null, global_position, Vector3.UP, "fall")
		_end_chute()
		fall_v = 0.0
		G.notify("Landed", 1.5)


# ---------------------------------------------------------------- vehicles
func try_enter_vehicle() -> void:
	var best = null
	var bd := 1e9
	for v in G.vehicles:
		if v.wrecked:
			continue
		var d: float = v.global_position.distance_to(global_position) - v.def.L * 0.4
		if d < 2.6 and d < bd:
			bd = d
			best = v
	if best == null:
		return
	var v2 = best
	if v2.owner_tag == "taxi" and v2.driver != null and not v2.driver.is_player and G.traffic.taxi_ready(v2):
		_ride_taxi(v2)
		return
	if v2.driver != null and v2.driver != self:
		var npc = v2.driver
		if npc.has_method("pulled_out"):
			npc.pulled_out(self, v2)
		if G.wanted:
			G.wanted.crime("carjack_police" if v2.owner_tag == "police" else "carjack", global_position)
		v2.stolen = true
	elif v2.owner_tag == "police" and G.wanted:
		G.wanted.crime("steal_police", global_position)
	state = "enter"
	tween_lock = true
	crouching = false
	velocity = Vector3.ZERO
	var tw := create_tween()
	var dp: Vector3 = v2.door_pos()
	dp.y = global_position.y
	tw.tween_property(self, "global_position", dp, clamp(global_position.distance_to(dp) / 6.0, 0.15, 0.5))
	tw.tween_callback(func():
		tween_lock = false
		if is_instance_valid(v2) and not v2.wrecked and (v2.driver == null or v2.driver == self):
			_seat(v2)
		else:
			state = "normal")


func _seat(v) -> void:
	state = "vehicle"
	vehicle = v
	v.ai = null
	v.set_driver(self)
	v.handbrake = false
	cshape.disabled = true
	visible = v.def.get("open", false)
	aiming = false
	if not _allowed(weapon):
		for w in ["smg", "pistol", "revolver", "fists"]:
			if w in owned:
				equip(w)
				break
	if G.wanted:
		G.wanted.vehicle_changed(v)
	G.cam.last_mouse = -10.0


func _ride_taxi(v) -> void:
	state = "vehicle"
	vehicle = v
	passenger_of = v
	v.passenger = self
	cshape.disabled = true
	visible = false
	G.menus.open("taxi_dest")


func force_exit() -> void:
	if vehicle == null:
		return
	var v = vehicle
	if v.driver == self:
		v.set_driver(null)
	if v.passenger == self:
		v.passenger = null
	passenger_of = null
	vehicle = null
	cshape.disabled = false
	visible = true
	state = "normal"
	global_position = v.global_position + Vector3.UP * 1.2


func exit_vehicle() -> void:
	var v = vehicle
	if v == null:
		return
	var vel: Vector3 = v.linear_velocity
	var W: float = v.def.W
	var spot: Vector3 = v.global_position + Vector3.UP * (v.def.H + 0.3)
	for off in [Vector3(-(W / 2 + 0.8), 0.5, 0), Vector3(W / 2 + 0.8, 0.5, 0), Vector3(0, 0.5, v.def.L / 2 + 0.9)]:
		var c: Vector3 = v.global_transform * off
		var from: Vector3 = v.global_position + Vector3.UP * 0.8
		if G.ray(from, c + Vector3.UP * 0.5, G.L_WORLD | G.L_PROP, [v]).is_empty():
			spot = c
			break
	var was_passenger: bool = passenger_of != null
	force_exit()
	global_position = spot
	rotation = Vector3(0, v.global_rotation.y, 0)
	velocity = vel
	if was_passenger:
		G.traffic.taxi_done(v)
	if vel.length() > 9.0:
		bail(vel)
	air_t = 0.0
	fall_v = 0.0


func bail(vel: Vector3) -> void:
	if vehicle != null:
		force_exit()
	take_damage(clamp((vel.length() - 8.0) * 2.0, 0.0, 60.0), null, global_position, Vector3.UP, "crash")
	if not dead:
		knockdown(vel * 0.8 + Vector3.UP * 3.0)


func _vehicle(dt: float) -> void:
	var v = vehicle
	if v == null or not is_instance_valid(v):
		vehicle = null
		state = "normal"
		cshape.disabled = false
		visible = true
		return
	global_transform = v.seat_transform()
	velocity = Vector3.ZERO
	noise = 0.0
	if passenger_of != null:
		return
	var can := not locked()
	var fw := ((1.0 if key(KEY_W) else 0.0) - (1.0 if key(KEY_S) else 0.0)) if can else 0.0
	var lr := ((1.0 if key(KEY_D) else 0.0) - (1.0 if key(KEY_A) else 0.0)) if can else 0.0
	if test_input != null:
		fw = test_input.y
		lr = test_input.x
	match v.kind:
		"car", "bike", "boat":
			v.throttle = fw
			v.steer_in = lr
			v.handbrake = can and key(KEY_SPACE)
			if v.kind != "boat" and abs(v.fspeed) > 6.0:
				G.skill_gain("driving", dt * 0.05)
			v.skill_grip = 1.0 + 0.08 * G.skill("driving")
		"heli":
			v.pitch_in = fw
			v.roll_in = lr
			v.yaw_in = ((1.0 if key(KEY_E) else 0.0) - (1.0 if key(KEY_Q) else 0.0)) if can else 0.0
			v.lift_in = ((1.0 if key(KEY_SHIFT) else 0.0) - (1.0 if key(KEY_CTRL) else 0.0)) if can else 0.0
		"plane":
			v.pitch_in = fw
			v.roll_in = lr
			v.yaw_in = ((1.0 if key(KEY_E) else 0.0) - (1.0 if key(KEY_Q) else 0.0)) if can else 0.0
			v.lift_in = ((1.0 if key(KEY_SHIFT) else 0.0) - (1.0 if key(KEY_CTRL) else 0.0)) if can else 0.0
	if test_lift != 0.0:
		v.lift_in = test_lift
	# drive-by
	var d := wdef()
	var rmb := can and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var lmb := can and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not wheel_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	aiming = rmb and d.get("onehand", false)
	aim_pitch = G.cam.pitch
	if lmb and d.get("onehand", false) and v.kind in ["car", "bike", "boat"]:
		if d.get("auto", false) or _just_lmb:
			var o: Vector3 = G.cam.aim_origin()
			var from: Vector3 = v.global_position + Vector3.UP * (v.def.H + 0.25)
			var dirv: Vector3 = (o + G.cam.aim_dir() * 60.0 - from).normalized()
			if fire(from, dirv, 2.0 - 0.4 * G.skill("shooting")):
				_after_shot(d)
				last_mouse_hold()
	# ejected into water / wreck
	if v.wrecked:
		force_exit()
	if v.kind in ["car", "bike"] and v.global_position.y < G.WATER_Y - 1.6:
		exit_vehicle()


func last_mouse_hold() -> void:
	G.cam.last_mouse = G.time_now


# ---------------------------------------------------------------- interaction prompts
func _scan_prompts() -> void:
	prompt_action = Callable()
	if state == "vehicle":
		var v = vehicle
		for it in G.world.interacts:
			if it.veh and it.pos.distance_to(v.global_position) < it.radius and v.linear_velocity.length() < 3.0:
				prompt = "E  " + it.label
				prompt_action = it.action
				return
		return
	if state != "normal" and state != "swim":
		return
	var pp := global_position
	for it in G.world.interacts:
		if not it.veh and it.pos.distance_to(pp) < it.radius:
			prompt = "E  " + it.label
			prompt_action = it.action
			return
	for l in G.world.ladders:
		if l.pos.distance_to(pp) < 1.7:
			prompt = "E  Climb ladder"
			prompt_action = func():
				ladder = l
				state = "climb"
				global_position = l.pos + Vector3.UP * 0.1
			return
	if G.pop:
		var npc = G.pop.talk_target(self)
		if npc != null:
			prompt = "E  " + npc.talk_label
			prompt_action = func(): npc.talk(self)
			return
	for v2 in G.vehicles:
		if not v2.wrecked and v2.global_position.distance_to(pp) - v2.def.L * 0.4 < 2.6:
			var jack: bool = v2.driver != null
			prompt = "F  " + ("Ride taxi" if (v2.owner_tag == "taxi" and jack and G.traffic.taxi_ready(v2)) else ("Carjack " if jack else "Enter ") + v2.def.name)
			return
