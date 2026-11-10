class_name Player
extends CharacterBody3D
## The player: third-person on-foot controller (run/sprint/jump/crouch-stealth/cover/vault/ladders/roll),
## swimming & diving, parachute, combat (guns, melee, throwables, drive-by), vehicle use, health/armor,
## death & arrest, skills. No missions - pure free roam.

enum St { FOOT, VEHICLE, SWIM, LADDER, CHUTE, RAGDOLL, DEAD, BUSTED, RIDE }

const SKILLS := ["stamina", "shooting", "strength", "stealth", "driving", "flying", "lung"]
const SKILL_NAMES := {"stamina": "Stamina", "shooting": "Shooting", "strength": "Strength", "stealth": "Stealth", "driving": "Driving", "flying": "Flying", "lung": "Lung Capacity"}

var st: int = St.FOOT
var vis: CharVisual
var cam: PlayerCamera
var inv := Inventory.new()
var look := {}
var health := 100.0
var max_health := 100.0
var armor := 0.0
var money := 3000
var stamina := 1.0
var breath := 1.0
var skills := {"stamina": 0.15, "shooting": 0.15, "strength": 0.15, "stealth": 0.1, "driving": 0.15, "flying": 0.05, "lung": 0.1}
var vehicle: Vehicle = null
var seat := -1
var dead := false
var has_parachute := false
var has_scuba := false
var crouching := false
var aiming := false
var in_cover := false
var cover_normal := Vector3.ZERO
var cover_low := false
var cover_edge := 0
var cover_pop := Vector3.ZERO
var fire_cd := 0.0
var reloading := 0.0
var reload_len := 1.0
var melee_cd := 0.0
var combo := 0
var air_t := 0.0
var peak_fall := 0.0
var ladder := {}
var chute: Node3D = null
var ragdoll: Ragdoll = null
var ragdoll_min := 0.0
var busy := false
var roll_t := 0.0
var roll_dir := Vector3.ZERO
var invuln := 0.0
var face_yaw := 0.0
var step_acc := 0.0
var last_shot := 99.0
var weapon_model: Node3D = null
var flashlight: SpotLight3D = null
var ride_node: Node3D = null
var underwater := false
var last_vehicle: Vehicle = null
var regen_t := 0.0
var stats := {"kills": 0, "shots": 0, "distance": 0.0, "stunts": 0, "deaths": 0, "busts": 0, "cars_stolen": 0}
var hidden_look_change := 0.0
var water_enter_t := 0.0
var exit_cd := 0.0


func _ready() -> void:
	add_to_group("chars")
	collision_layer = G.L_CHAR
	collision_mask = G.L_WORLD | G.L_VEHICLE
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.78
	cs.shape = cap
	cs.position = Vector3(0, 0.89, 0)
	cs.name = "Col"
	add_child(cs)
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.35
	max_slides = 5
	look = {"sex": "m", "skin": Color("d9a27a"), "hair": "Hair_Quiff", "hair_color": Color("2b1d14"), "beard": "", "shirt": Color("2f9c95"),
		"pants": Color("2d3142"), "shoes": Color("e8e4da"), "long_sleeve": true, "shorts": false, "hat": "", "glasses": "", "hat_color": Color("c9302a"), "pack": ""}
	vis = CharVisual.new()
	vis.name = "Visual"
	add_child(vis)
	vis.setup(look)
	cam = PlayerCamera.new()
	cam.name = "Camera"
	add_child(cam)
	inv.give("pistol")
	inv.give("bat", false)
	var sp := Vector3(-124.0, 0.4, 62.0)
	if G.world and G.world.pois.has("safehouse"):
		sp = G.world.pois["safehouse"].spawn
	global_position = sp
	face_yaw = PI
	cam.yaw = PI
	equip(inv.current)


func global_position_now() -> Vector3:
	if ragdoll != null:
		return ragdoll.global_position
	return global_position


func skill(n: String) -> float:
	return float(skills.get(n, 0.0))


func skill_gain(n: String, amt: float) -> void:
	var before := int(skill(n) * 10.0)
	skills[n] = clampf(skill(n) + amt, 0.0, 1.0)
	if int(skill(n) * 10.0) > before:
		G.say("%s skill increased (%d%%)" % [SKILL_NAMES[n], int(skill(n) * 100.0)], Color(0.5, 0.9, 1.0))


func add_money(n: int) -> void:
	money = maxi(money + n, 0)
	G.money_changed.emit(money)


func spend(n: int) -> bool:
	if money < n:
		G.say("Not enough cash", Color(1, 0.4, 0.3))
		Sfx.ui("deny")
		return false
	add_money(-n)
	Sfx.ui("buy")
	return true


# ------------------------------------------------------------------ weapons
func wdef() -> Dictionary:
	return Defs.WEAPONS[inv.current]


func melee_equipped() -> bool:
	return wdef().type in ["melee", "throw"]


func weapon_scoped() -> bool:
	return wdef().get("scoped", false)


func aim_fov() -> float:
	var d := wdef()
	if d.has("zoom"):
		return float(d.zoom)
	return 34.0 if inv.has_mod(inv.current, "scope") else 50.0


func equip(wid: String) -> void:
	if not inv.owned.has(wid):
		return
	inv.current = wid
	reloading = 0.0
	var d: Dictionary = Defs.WEAPONS[wid]
	var tint: Color = Defs.WEAPON_TINTS.get(inv.tints.get(wid, "Factory"), Color(0, 0, 0, 0))
	weapon_model = Weapons.make_model(wid, inv.mods_of(wid), tint)
	var wt := "none"
	var two := false
	match d.type:
		"pistol": wt = "pistol"
		"smg", "rifle":
			wt = "rifle"
			two = true
		"rpg":
			wt = "rpg"
			two = true
		"melee": wt = "melee" if weapon_model != null else "none"
		"throw": wt = "throw"
	vis.set_weapon(weapon_model, wt, two)
	flashlight = null
	if weapon_model != null and inv.has_mod(wid, "flashlight") and weapon_model.has_node("Light"):
		flashlight = SpotLight3D.new()
		flashlight.spot_range = 38.0
		flashlight.spot_angle = 24.0
		flashlight.light_energy = 6.0
		flashlight.shadow_enabled = false
		flashlight.visible = false
		weapon_model.get_node("Light").add_child(flashlight)
	Sfx.play("equip", global_position, -8.0)
	if G.hud and G.hud.has_method("weapon_changed"):
		G.hud.weapon_changed()


func can_use_weapon_in_vehicle() -> bool:
	return vehicle != null and wdef().get("driveby", false) and seat >= 0 and vehicle.kind != "plane"


func _best_driveby() -> String:
	for wid in ["smg", "pistol", "revolver"]:
		if inv.owned.has(wid) and inv.in_clip(wid) + inv.reserve(wid) > 0:
			return wid
	return ""


func start_reload() -> void:
	var d := wdef()
	if reloading > 0.0 or not d.has("ammo") or d.type == "throw":
		return
	if inv.in_clip(inv.current) >= inv.mag_size(inv.current) or inv.reserve(inv.current) <= 0:
		return
	reload_len = float(d.get("reload", 1.5)) * (1.0 - 0.25 * skill("shooting"))
	reloading = reload_len
	Sfx.play("reload", global_position, -4.0)


func _try_fire(delta: float) -> void:
	var d := wdef()
	fire_cd -= delta
	melee_cd -= delta
	last_shot += delta
	if reloading > 0.0:
		reloading -= delta
		vis.reload_t = 1.0 - reloading / reload_len
		if reloading <= 0.0:
			inv.reload(inv.current)
			vis.reload_t = 0.0
		return
	vis.reload_t = 0.0
	if G.ui_blocking > 0 or busy:
		return
	var in_veh := vehicle != null
	if in_veh and not can_use_weapon_in_vehicle():
		return
	var pressed := Input.is_action_just_pressed("fire")
	var held := Input.is_action_pressed("fire")
	if Input.is_action_just_pressed("reload"):
		start_reload()
		return
	if d.type == "melee":
		if in_veh:
			return
		if (pressed or Input.is_action_just_pressed("melee")) and melee_cd <= 0.0:
			_melee_attack(aiming and Input.is_action_pressed("sprint"))
		return
	if Input.is_action_just_pressed("melee") and not in_veh and melee_cd <= 0.0:
		_melee_attack(false, true)
		return
	if d.type == "throw":
		if pressed and fire_cd <= 0.0 and inv.use_round(inv.current):
			_throw(inv.current)
		return
	if not (pressed or (held and d.get("auto", false))):
		return
	if fire_cd > 0.0:
		return
	if inv.in_clip(inv.current) <= 0:
		if pressed:
			Sfx.play("dry", global_position, -6.0)
		start_reload()
		return
	inv.use_round(inv.current)
	fire_cd = float(d.rate)
	last_shot = 0.0
	stats.shots += 1
	var excl: Array = [get_rid()]
	if in_veh:
		excl.append(vehicle.get_rid())
	var target := cam.aim_point(float(d.range), excl)
	var origin := vis.head_pos() + Vector3(0, -0.08, 0)
	var blind := in_cover and not aiming
	if blind:
		origin = global_position + Vector3(0, 1.35 if cover_low else 1.5, 0) + cover_normal * -0.1
		var cf := G.flat(cam.forward()).normalized()
		target = origin + (cf + Vector3(0, 0.03, 0)) * 60.0
	if in_veh:
		var side := cam.forward().dot(vehicle.global_transform.basis.x)
		origin = vehicle.seat_global(seat).origin + Vector3(0, 0.55, 0) + vehicle.global_transform.basis.x * (0.55 if side > 0 else -0.55)
	var dir := (target - origin).normalized()
	var sm := 1.0
	if not aiming:
		sm *= 2.1
	if velocity.length() > 1.5:
		sm *= 1.35
	if crouching:
		sm *= 0.8
	if in_veh:
		sm *= 1.7
	if blind:
		sm *= 3.2
	if inv.has_mod(inv.current, "scope") and aiming:
		sm *= 0.8
	sm *= 1.0 - 0.3 * skill("shooting")
	var muzzle := Weapons.muzzle_of(weapon_model, inv.has_mod(inv.current, "suppressor")) if vis.visible and weapon_model != null else origin + dir * 0.6
	var res := Weapons.fire(self, inv.current, origin, dir, {"mods": inv.mods_of(inv.current), "spread_mul": sm, "muzzle": muzzle, "exclude": excl})
	var rec: float = float(d.recoil) * (0.65 if inv.has_mod(inv.current, "grip") else 1.0) * (1.0 - 0.3 * skill("shooting")) * (0.8 if crouching else 1.0)
	cam.kick(rec * randf_range(0.7, 1.0), rec * randf_range(-0.35, 0.35))
	cam.shake(0.05 + rec * 0.012)
	vis.recoil = 1.0
	if G.fx and weapon_model and d.type != "rpg":
		G.fx.shell_eject(muzzle - dir * 0.3, global_transform.basis.x)
	if res.hit and res.collider is CharacterBody3D:
		skill_gain("shooting", 0.004)
		if G.hud and G.hud.has_method("hit_marker"):
			G.hud.hit_marker(res.kills > 0)
	if res.kills > 0:
		stats.kills += res.kills


func _melee_attack(heavy: bool, quick: bool = false) -> void:
	var wid := inv.current if not quick else "fists"
	var d: Dictionary = Defs.WEAPONS[wid]
	melee_cd = float(d.rate) * (1.5 if heavy else 1.0)
	combo = (combo + 1) % 3
	var act: String = "heavy" if heavy else ("swing" if wid != "fists" else (["punch_r", "punch_l", "kick"][combo]))
	vis.play(act, melee_cd * 0.95)
	face_yaw = cam.yaw
	var dir := Basis(Vector3.UP, face_yaw) * Vector3(0, 0, -1)
	var origin := global_position + Vector3(0, 1.0, 0)
	# stealth takedown from behind
	if crouching or wid == "knife":
		for ch in get_tree().get_nodes_in_group("chars"):
			if ch == self or not ch.has_method("takedown"):
				continue
			var n := ch as Node3D
			var to := n.global_position - global_position
			if to.length() < 1.9 and to.normalized().dot(dir) > 0.4 and ch.can_takedown(self):
				ch.takedown(self)
				vis.play("heavy", 0.5)
				skill_gain("stealth", 0.02)
				stats.kills += 1
				return
	var dly := melee_cd * (0.5 if heavy else 0.35)
	await get_tree().create_timer(dly).timeout
	if dead or st != St.FOOT:
		return
	var hit := Weapons.melee(self, wid, origin, dir, heavy, 1.0 + 0.6 * skill("strength"))
	if hit != null:
		skill_gain("strength", 0.004)
		cam.shake(0.12 if not heavy else 0.25)
		if hit is CharacterBody3D:
			G.report_crime("assault", global_position, 0.7, self)


func _throw(wid: String) -> void:
	fire_cd = 0.9
	vis.play("throw", 0.5)
	face_yaw = cam.yaw
	await get_tree().create_timer(0.22).timeout
	if dead:
		return
	var d: Dictionary = Defs.WEAPONS[wid]
	var dir := (cam.forward() + Vector3(0, 0.18, 0)).normalized()
	var p := Projectile.new()
	p.setup(String(d.projectile), self, global_position, dir, d)
	G.main.add_child(p)
	var from := global_position + Vector3(0, 1.5, 0) + dir * 0.5
	if vehicle != null:
		from = vehicle.seat_global(seat).origin + Vector3(0, 0.9, 0) + vehicle.global_transform.basis.x * (0.8 if cam.forward().dot(vehicle.global_transform.basis.x) > 0 else -0.8)
		p.vel += vehicle.linear_velocity
	p.global_position = from
	Sfx.play("throw", global_position)
	if inv.in_clip(wid) <= 0:
		equip("fists")


# ------------------------------------------------------------------ damage / death
func is_head_hit(pos: Vector3) -> bool:
	return pos.y > global_position.y + 1.5 - vis.hips_drop


func take_damage(amount: float, instigator: Node = null, pos: Vector3 = Vector3.ZERO, kind: String = "") -> void:
	if dead or G.flags.god or invuln > 0.0 or st == St.BUSTED:
		return
	var a := amount
	if kind == "melee":
		a *= 1.0 - 0.25 * skill("strength")
	if vis.action == "block" and kind == "melee":
		a *= 0.25
	if armor > 0.0 and kind in ["bullet", "explosion", "melee"]:
		var ab := minf(armor, a * 0.8)
		armor -= ab
		a -= ab
	health -= a
	regen_t = 6.0
	if G.hud and G.hud.has_method("damage_flash"):
		G.hud.damage_flash(pos if pos != Vector3.ZERO else global_position, a)
	if kind != "drown" and kind != "fall":
		vis.play("hit", 0.3) if vis.action == "" else null
	Sfx.play("hurt", global_position, -6.0, randf_range(0.9, 1.1))
	cam.shake(clampf(a * 0.015, 0.05, 0.5))
	if health <= 0.0:
		die(instigator)


func heal(n: float) -> void:
	health = minf(health + n, max_health)


func knockdown(impulse: Vector3) -> void:
	if dead or vehicle != null or ragdoll != null or G.flags.god or st in [St.BUSTED, St.RIDE]:
		return
	_start_ragdoll(impulse, 1.6)


func hit_by_vehicle(veh: Vehicle, vel: Vector3) -> void:
	if vehicle != null or ragdoll != null or invuln > 0.0 or dead:
		return
	var sp := vel.length()
	take_damage(maxf(sp - 3.0, 0.0) * 5.5, veh.driver, global_position, "vehicle")
	if not dead and sp > 4.0:
		_start_ragdoll(vel * 0.55 + Vector3(0, 2.5, 0), 1.8)


func on_vehicle_destroyed(veh: Vehicle) -> void:
	if vehicle == veh:
		var v := veh.linear_velocity
		_leave_vehicle_now()
		if not G.flags.god:
			health = 0.0
			die(veh.last_attacker)
		_start_ragdoll(v + Vector3(0, 5, 0), 3.0) if not dead and ragdoll == null else null


func fall_off_vehicle(veh: Vehicle, vel: Vector3) -> void:
	if vehicle == veh:
		_leave_vehicle_now()
		take_damage(clampf(vel.length() * 1.2, 4.0, 45.0), null, global_position, "crash")
		if not dead:
			_start_ragdoll(vel * 0.7 + Vector3(0, 2.5, 0), 2.0)


func _start_ragdoll(impulse: Vector3, min_t: float) -> void:
	if ragdoll != null:
		return
	if chute:
		chute.queue_free()
		chute = null
	in_cover = false
	aiming = false
	ragdoll = Ragdoll.start(self, vis, impulse, dead)
	ragdoll_min = min_t
	if not dead:
		st = St.RAGDOLL
	$Col.disabled = true
	velocity = Vector3.ZERO


func _end_ragdoll() -> void:
	if ragdoll == null:
		return
	var p := ragdoll.global_position
	var h := G.ray(p + Vector3(0, 0.6, 0), p - Vector3(0, 3.0, 0), G.L_WORLD)
	global_position = h.position + Vector3(0, 0.05, 0) if not h.is_empty() else p
	face_yaw = ragdoll.rotation.y
	ragdoll.release_visual(self)
	ragdoll.queue_free()
	ragdoll = null
	$Col.disabled = false
	vis.mode = "foot"
	st = St.SWIM if global_position.y < G.WATER_LEVEL - 1.1 else St.FOOT
	invuln = 0.6


func die(instigator: Node = null) -> void:
	if dead:
		return
	dead = true
	stats.deaths += 1
	var v := velocity
	if vehicle != null:
		v = vehicle.linear_velocity
		_leave_vehicle_now()
	st = St.DEAD
	if ragdoll == null:
		_start_ragdoll(v * 0.5 + Vector3(randf() - 0.5, 1.5, randf() - 0.5), 9.0)
	else:
		ragdoll.vis.mode = "dead"
	G.time_scale_target = 0.35
	Sfx.play("death", global_position)
	if G.hud and G.hud.has_method("big_message"):
		G.hud.big_message("FLATLINED", Color(0.9, 0.15, 0.1))
	await get_tree().create_timer(1.6, true, false, true).timeout
	G.time_scale_target = 1.0
	if G.hud and G.hud.has_method("fade"):
		await G.hud.fade(true, 0.8)
	_respawn("hospital", mini(500, int(money * 0.08)))
	if G.hud and G.hud.has_method("fade"):
		G.hud.fade(false, 0.8)


func get_busted() -> void:
	if dead or st == St.BUSTED:
		return
	stats.busts += 1
	if vehicle != null:
		_leave_vehicle_now()
	st = St.BUSTED
	velocity = Vector3.ZERO
	vis.hands_up = 1.0
	aiming = false
	if G.hud and G.hud.has_method("big_message"):
		G.hud.big_message("APPREHENDED", Color(0.25, 0.5, 1.0))
	Sfx.play("busted", global_position)
	await get_tree().create_timer(2.4).timeout
	if G.hud and G.hud.has_method("fade"):
		await G.hud.fade(true, 0.7)
	var stars: int = G.wanted.level if G.wanted else 1
	for at in inv.ammo.keys():
		inv.ammo[at] = int(int(inv.ammo[at]) * 0.6)
	_respawn("police", mini(money, 150 * maxi(stars, 1)))
	if G.hud and G.hud.has_method("fade"):
		G.hud.fade(false, 0.8)


func _respawn(poi: String, fee: int) -> void:
	if ragdoll != null:
		ragdoll.release_visual(self)
		ragdoll.queue_free()
		ragdoll = null
	$Col.disabled = false
	dead = false
	st = St.FOOT
	vis.mode = "foot"
	vis.hands_up = 0.0
	health = max_health
	armor = 0.0
	breath = 1.0
	stamina = 1.0
	velocity = Vector3.ZERO
	add_money(-fee)
	var p := Vector3(0, 0.5, 0)
	if G.world and G.world.pois.has(poi):
		p = G.world.pois[poi].get("spawn", G.world.pois[poi].pos)
	global_position = p
	if G.wanted:
		G.wanted.clear()
	if G.timew:
		G.timew.set_time(G.timew.time + 3.0)
	if fee > 0:
		G.say("%s charged %s" % ["Hospital" if poi == "hospital" else "Bail", G.fmt_money(fee)], Color(1, 0.8, 0.4))
	invuln = 2.0


# ------------------------------------------------------------------ vehicles
func nearest_vehicle(max_d: float = 4.2) -> Vehicle:
	var best: Vehicle = null
	var bd := max_d
	for v in get_tree().get_nodes_in_group("vehicles"):
		var veh := v as Vehicle
		if veh == null or veh.dead or veh.seats.is_empty():
			continue
		var lp := veh.to_local(global_position)
		var d := Vector3(maxf(absf(lp.x) - veh.half.x, 0.0), 0.0, maxf(absf(lp.z) - veh.half.z, 0.0)).length() + absf(lp.y) * 0.3
		if d < bd:
			bd = d
			best = veh
	return best


func try_enter_vehicle() -> void:
	if busy or st not in [St.FOOT, St.SWIM] or exit_cd > 0.0:
		return
	var veh := nearest_vehicle()
	if veh == null:
		return
	if veh.ai != null and veh.ai.has_method("is_taxi_for_hire") and veh.ai.is_taxi_for_hire() and veh.seats.size() > 2 and not Input.is_action_pressed("sprint"):
		if G.services and G.services.has_method("board_taxi"):
			G.services.board_taxi(veh)
			return
	_enter(veh, 0)


func _enter(veh: Vehicle, s: int, instant: bool = false) -> void:
	busy = true
	in_cover = false
	aiming = false
	crouching = false
	$Col.disabled = true
	var door := veh.door_point(s)
	var occupant: Node = veh.seats[s].occ
	if not instant:
		var tw := create_tween()
		door.y = global_position.y
		tw.tween_property(self, "global_position", door, clampf(global_position.distance_to(door) / 6.0, 0.12, 0.45))
		await tw.finished
		if not is_instance_valid(veh) or veh.dead:
			busy = false
			$Col.disabled = false
			return
		face_yaw = atan2(-(veh.global_position.x - global_position.x), -(veh.global_position.z - global_position.z))
		veh.set_door(s, true)
		if occupant != null and is_instance_valid(occupant) and occupant != self:
			# carjacking
			vis.play("use", 0.45)
			await get_tree().create_timer(0.28).timeout
			if is_instance_valid(occupant) and occupant.has_method("pulled_from_vehicle"):
				occupant.pulled_from_vehicle(veh, self)
			stats.cars_stolen += 1
			G.report_crime("carjack" if not veh.is_emergency else "steal_police", global_position, 1.2 if not veh.is_emergency else 2.6, self)
			await get_tree().create_timer(0.3).timeout
		else:
			await get_tree().create_timer(0.22 if veh.kind == "car" else 0.1).timeout
			if veh.is_emergency and not veh.owned and veh.ai == null and veh.last_driver_was_player == false:
				G.report_crime("steal_police", global_position, 2.0, self)
	if not is_instance_valid(veh):
		busy = false
		$Col.disabled = false
		return
	if s == 0:
		for i in veh.seats.size():
			if veh.seats[i].occ != null and veh.seats[i].occ != self and i != s and is_instance_valid(veh.seats[i].occ) and veh.seats[i].occ.has_method("flee_vehicle"):
				veh.seats[i].occ.flee_vehicle(veh)
		if veh.ai != null:
			veh.ai.queue_free()
			veh.ai = null
	vehicle = veh
	seat = s
	veh.occupy(s, self)
	st = St.VEHICLE
	vis.mode = "bike" if veh.kind == "bike" else "sit"
	vis.recline = 0.25 if veh.vid != "sports" else 0.45
	vis.crouch = 0.0
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_sync_to_seat()
	busy = false
	last_vehicle = veh
	veh.set_door(s, false)
	if veh.kind in ["heli", "plane"]:
		veh.engine_on = not veh.flooded
	G.player_vehicle_changed.emit(veh)
	if G.hud and G.hud.has_method("vehicle_entered"):
		G.hud.vehicle_entered(veh)
	if not can_use_weapon_in_vehicle() and _best_driveby() != "":
		equip(_best_driveby())


func _sync_to_seat() -> void:
	if vehicle == null or seat < 0:
		return
	var sx := vehicle.seat_global(seat)
	var b := sx.basis.orthonormalized()
	global_transform = Transform3D(b, sx.origin - b.y * (0.94 * vis.S - 0.04) + b.z * (0.0 if vehicle.kind != "bike" else 0.05))


func try_exit_vehicle() -> void:
	if vehicle == null or busy:
		return
	var veh := vehicle
	if veh.speed > 8.0 and veh.kind in ["car", "bike"]:
		var v := veh.linear_velocity
		_leave_vehicle_now()
		take_damage(clampf((v.length() - 8.0) * 1.6, 2.0, 60.0), null, global_position, "fall")
		if not dead:
			_start_ragdoll(v * 0.85 + veh.global_transform.basis.x * -2.5 + Vector3(0, 1.5, 0), 1.6)
		return
	if veh.kind in ["heli", "plane"] and veh.global_position.y - G.ground_y(veh.global_position.x, veh.global_position.z, veh.global_position.y) > 6.0:
		var v2 := veh.linear_velocity
		_leave_vehicle_now()
		velocity = v2
		air_t = 0.5
		return
	busy = true
	veh.set_door(seat, true)
	await get_tree().create_timer(0.2 if veh.kind == "car" else 0.05).timeout
	if not is_instance_valid(veh):
		busy = false
		return
	var s := seat
	var out := veh.door_point(s)
	_leave_vehicle_now(false)
	var gy := G.ray(out + Vector3(0, 1.6, 0), out - Vector3(0, 3.0, 0), G.L_WORLD)
	if not gy.is_empty():
		out.y = gy.position.y + 0.05
	if veh.kind == "boat":
		out.y = maxf(out.y, G.WATER_LEVEL - 1.3)
	global_position = out
	rotation = Vector3(0, veh.rotation.y, 0)
	face_yaw = veh.rotation.y
	veh.set_door(s, false)
	busy = false


func _leave_vehicle_now(place: bool = true) -> void:
	if vehicle == null:
		return
	var veh := vehicle
	var s := seat
	veh.vacate(self)
	vehicle = null
	seat = -1
	st = St.FOOT
	vis.mode = "foot"
	collision_layer = G.L_CHAR
	collision_mask = G.L_WORLD | G.L_VEHICLE
	$Col.disabled = false
	exit_cd = 0.5
	if place and is_instance_valid(veh):
		global_position = veh.door_point(maxi(s, 0)) + Vector3(0, 0.2, 0)
		velocity = veh.linear_velocity
	rotation = Vector3(0, rotation.y, 0)
	G.player_vehicle_changed.emit(null)
	if G.hud and G.hud.has_method("vehicle_entered"):
		G.hud.vehicle_entered(null)
	equip(inv.current)


func warp_into(veh: Vehicle, s: int = 0) -> void:
	if dead or st == St.BUSTED or st == St.RIDE:
		return
	if ragdoll != null:
		_end_ragdoll()
	if chute:
		chute.queue_free()
		chute = null
	if vehicle != null:
		_leave_vehicle_now(false)
	_enter(veh, s, true)


func _drive(delta: float) -> void:
	var veh := vehicle
	if not is_instance_valid(veh):
		vehicle = null
		st = St.FOOT
		return
	_sync_to_seat()
	if seat != 0 or G.ui_blocking > 0:
		if seat == 0:
			veh.throttle = 0.0
			veh.steer = 0.0
		return
	var f := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var s := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	match veh.kind:
		"car", "bike":
			veh.brake = 0.0
			if f > 0.05:
				if veh.fwd_speed < -1.5:
					veh.brake = 1.0
					veh.throttle = 0.0
				else:
					veh.throttle = f
			elif f < -0.05:
				if veh.fwd_speed > 1.5:
					veh.brake = 1.0
					veh.throttle = 0.0
				else:
					veh.throttle = f
			else:
				veh.throttle = 0.0
			veh.steer = move_toward(veh.steer, s, delta * (4.0 + skill("driving") * 2.0))
			veh.handbrake = Input.is_action_pressed("jump")
			veh.in_pitch = f
			if veh.speed > 8.0:
				skill_gain("driving", delta * 0.0006)
				stats.distance += veh.speed * delta
		"boat":
			veh.throttle = f
			veh.steer = move_toward(veh.steer, s, delta * 3.0)
		"heli":
			veh.in_up = (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
			veh.in_pitch = f
			veh.in_roll = s
			veh.in_yaw = (1.0 if Input.is_action_pressed("yaw_right") else 0.0) - (1.0 if Input.is_action_pressed("yaw_left") else 0.0)
			skill_gain("flying", delta * 0.001)
		"plane":
			if Input.is_action_pressed("sprint"):
				veh.throttle = minf(veh.throttle + delta * 0.7, 1.0)
			if Input.is_action_pressed("crouch"):
				veh.throttle = maxf(veh.throttle - delta * 0.9, 0.0)
			veh.in_pitch = f
			veh.in_roll = s
			veh.in_yaw = (1.0 if Input.is_action_pressed("yaw_right") else 0.0) - (1.0 if Input.is_action_pressed("yaw_left") else 0.0)
			veh.brake = 1.0 if Input.is_action_pressed("jump") else 0.0
			skill_gain("flying", delta * 0.001)
	if Input.is_action_just_pressed("horn"):
		veh.honk()
	if Input.is_action_just_pressed("headlights"):
		veh.headlights = not veh.headlights
	if Input.is_action_just_pressed("siren") and veh.is_emergency:
		veh.set_siren(not veh.siren)
	if Input.is_action_just_pressed("roof"):
		veh.set_roof(not veh.roof_down)
	vis.lean = lerpf(vis.lean, -veh.steer * clampf(veh.speed / 15.0, 0.0, 1.0), delta * 5.0)


# ------------------------------------------------------------------ main loops
func _unhandled_input(ev: InputEvent) -> void:
	if G.ui_blocking > 0 or dead or st == St.BUSTED:
		return
	if ev.is_action_pressed("enter_vehicle"):
		if st == St.RIDE:
			if ride_node and ride_node.has_method("player_leave"):
				ride_node.player_leave()
		elif vehicle != null:
			try_exit_vehicle()
		else:
			try_enter_vehicle()
	elif ev.is_action_pressed("camera_toggle"):
		cam.first_person = not cam.first_person
	elif ev.is_action_pressed("next_weapon"):
		equip(inv.cycle(1))
	elif ev.is_action_pressed("prev_weapon"):
		equip(inv.cycle(-1))
	elif ev.is_action_pressed("crouch") and st == St.FOOT and vehicle == null:
		crouching = not crouching
		if in_cover:
			pass
	elif ev.is_action_pressed("cover") and st == St.FOOT:
		if in_cover:
			in_cover = false
		else:
			_try_cover()
	elif ev.is_action_pressed("grenade") and vehicle == null and st == St.FOOT:
		if inv.owned.has("grenade") and inv.in_clip("grenade") > 0 and fire_cd <= 0.0:
			inv.use_round("grenade")
			_throw("grenade")
	else:
		for i in range(1, 9):
			if ev.is_action_pressed("slot_%d" % i):
				var slot: String = Defs.SLOTS[i - 1]
				var ws := inv.slot_weapons(slot)
				if not ws.is_empty():
					var idx := ws.find(inv.current)
					equip(ws[(idx + 1) % ws.size()] if idx >= 0 else ws[0])


func _physics_process(delta: float) -> void:
	invuln = maxf(invuln - delta, 0.0)
	exit_cd = maxf(exit_cd - delta, 0.0)
	if ragdoll != null:
		global_position = ragdoll.global_position
		if not dead and ragdoll.age > ragdoll_min and ragdoll.settled():
			_end_ragdoll()
		return
	if dead or busy:
		return
	match st:
		St.VEHICLE:
			_drive(delta)
			aiming = Input.is_action_pressed("aim") and can_use_weapon_in_vehicle() and G.ui_blocking == 0
			vis.aim = move_toward(vis.aim, 1.0 if aiming else 0.0, delta * 8.0)
			vis.aim_pitch = cam.pitch
			_try_fire(delta)
		St.FOOT:
			_foot(delta)
		St.SWIM:
			_swim(delta)
		St.LADDER:
			_ladder(delta)
		St.CHUTE:
			_chute(delta)
		St.RIDE:
			if ride_node and is_instance_valid(ride_node):
				global_position = ride_node.global_position + Vector3(0, 1.2, 0)
		St.BUSTED:
			velocity = Vector3.ZERO
	# passive regen up to 50%
	regen_t -= delta
	if regen_t <= 0.0 and health < max_health * 0.5 and not dead:
		health = minf(health + delta * 2.0, max_health * 0.5)
	if flashlight:
		flashlight.visible = aiming and G.timew != null and G.timew.night > 0.3


func _process(delta: float) -> void:
	if vis == null or ragdoll != null:
		return
	if vehicle == null and st != St.RIDE:
		rotation.y = lerp_angle(rotation.y, face_yaw, clampf(delta * 14.0, 0.0, 1.0))
	vis.tick(delta)


func _wish_dir() -> Vector3:
	if G.ui_blocking > 0:
		return Vector3.ZERO
	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return Basis(Vector3.UP, cam.yaw) * Vector3(inp.x, 0, inp.y)


func in_cover_low() -> bool:
	return in_cover and cover_low and not aiming


func _foot(delta: float) -> void:
	var wish := _wish_dir()
	var on_floor := is_on_floor()
	aiming = Input.is_action_pressed("aim") and G.ui_blocking == 0 and roll_t <= 0.0
	if aiming and melee_equipped() and wdef().type == "melee":
		if vis.action == "":
			vis.play("block", 0.3)
	elif vis.action == "block":
		vis.action = ""
	var sprint := Input.is_action_pressed("sprint") and wish.length() > 0.1 and stamina > 0.02 and not aiming and not crouching and not in_cover
	var sp := 4.5
	if sprint:
		sp = 7.2 + skill("stamina") * 0.8
		stamina -= delta / (11.0 + 22.0 * skill("stamina"))
		skill_gain("stamina", delta * 0.0012)
	else:
		stamina = minf(stamina + delta * 0.16, 1.0)
	if crouching or in_cover_low():
		sp = 2.1
	if aiming:
		sp = 2.5
	if health < 25.0:
		sp *= 0.85
	# roll / dodge
	if roll_t > 0.0:
		roll_t -= delta
		velocity.x = roll_dir.x * 6.5
		velocity.z = roll_dir.z * 6.5
		vis.rotation.x = -(1.0 - roll_t / 0.6) * TAU
		if roll_t <= 0.0:
			vis.rotation.x = 0.0
	elif in_cover:
		_cover_move(delta, wish)
	else:
		var tv := wish * sp
		var acc := 30.0 if on_floor else 6.0
		velocity.x = move_toward(velocity.x, tv.x, acc * delta)
		velocity.z = move_toward(velocity.z, tv.z, acc * delta)
		if aiming or last_shot < 0.6:
			face_yaw = cam.yaw
		elif wish.length() > 0.1:
			face_yaw = atan2(-wish.x, -wish.z)
	# gravity / jump / fall
	if not on_floor:
		velocity.y -= 17.0 * delta
		air_t += delta
		peak_fall = minf(peak_fall, velocity.y)
		if velocity.y < -52.0:
			velocity.y = -52.0
	else:
		if air_t > 0.25:
			_land()
		air_t = 0.0
		peak_fall = 0.0
	if Input.is_action_just_pressed("jump") and G.ui_blocking == 0 and roll_t <= 0.0:
		if not on_floor and air_t > 0.6 and has_parachute and _height_above_ground() > 7.0:
			_deploy_chute()
			return
		elif on_floor:
			if aiming and wish.length() > 0.2:
				roll_t = 0.6
				roll_dir = wish.normalized()
				invuln = 0.4
				vis.play("roll", 0.6)
				in_cover = false
			elif in_cover:
				in_cover = false
			elif not _try_climb():
				velocity.y = 6.0
				crouching = false
				Sfx.play("jump", global_position, -10.0)
	if Input.is_action_just_pressed("interact") or (wish.length() > 0.3 and on_floor):
		_check_ladder(wish)
	move_and_slide()
	# water transition
	if global_position.y < G.WATER_LEVEL - 1.15:
		_enter_water()
		return
	# animation inputs
	var hv := Vector3(velocity.x, 0, velocity.z)
	vis.speed = hv.length()
	vis.sprinting = sprint
	vis.grounded = on_floor or air_t < 0.18
	vis.mode = "fall" if air_t > 0.9 else ("cover" if in_cover else "foot")
	vis.crouch = move_toward(vis.crouch, 1.0 if (crouching or in_cover_low()) else 0.0, delta * 7.0)
	var want_aim := aiming or last_shot < 0.5
	if melee_equipped():
		want_aim = false
	vis.aim = move_toward(vis.aim, 1.0 if want_aim else 0.0, delta * 9.0)
	vis.aim_pitch = cam.pitch
	var loc := global_transform.basis.inverse() * hv
	vis.strafe = Vector2(loc.x, loc.z).normalized() if hv.length() > 0.3 else Vector2.ZERO
	vis.injured = 1.0 if health < 25.0 else 0.0
	# footsteps / noise
	if on_floor and hv.length() > 0.8:
		step_acc += hv.length() * delta
		if step_acc > (1.9 if not sprint else 2.3):
			step_acc = 0.0
			var rad := (10.0 if sprint else 5.5) if not crouching else 1.6
			rad *= 1.0 - 0.5 * skill("stealth")
			G.make_noise(global_position, rad, "step", self)
			Sfx.play("step", global_position, -16.0 if crouching else -9.0, randf_range(0.85, 1.15))
			if crouching:
				skill_gain("stealth", 0.0006)
		stats.distance += hv.length() * delta
	_try_fire(delta)
	hidden_look_change = maxf(hidden_look_change - delta, 0.0)


func _height_above_ground() -> float:
	var h := G.ray(global_position + Vector3(0, 0.5, 0), global_position - Vector3(0, 400, 0), G.L_WORLD | G.L_VEHICLE, [get_rid()])
	var gy: float = h.position.y if not h.is_empty() else G.WATER_LEVEL
	return global_position.y - maxf(gy, G.WATER_LEVEL)


func _land() -> void:
	var v := -peak_fall
	if v > 12.5:
		var dmg := (v - 12.5) * 6.5
		take_damage(dmg, null, global_position, "fall")
		cam.shake(0.4)
		if v > 19.0 and not dead:
			_start_ragdoll(Vector3(velocity.x, 0.5, velocity.z) * 0.5, 1.5)
	elif v > 6.0:
		vis.play("hit", 0.25)
		Sfx.play("land", global_position, -8.0)


func _try_climb() -> bool:
	var fwd := Basis(Vector3.UP, face_yaw) * Vector3(0, 0, -1)
	var w := _wish_dir()
	if w.length() > 0.2:
		fwd = w.normalized()
	var base := global_position
	var low := G.ray(base + Vector3(0, 0.45, 0), base + Vector3(0, 0.45, 0) + fwd * 0.95, G.L_WORLD | G.L_VEHICLE, [get_rid()])
	var mid := G.ray(base + Vector3(0, 1.1, 0), base + Vector3(0, 1.1, 0) + fwd * 0.95, G.L_WORLD | G.L_VEHICLE, [get_rid()])
	var h := low if not low.is_empty() else mid
	if h.is_empty():
		return false
	var top_from: Vector3 = h.position + fwd * 0.32 + Vector3(0, 2.7 - (h.position.y - base.y), 0)
	var top := G.ray(top_from, top_from - Vector3(0, 2.6, 0), G.L_WORLD | G.L_VEHICLE, [get_rid()])
	if top.is_empty():
		return false
	var ledge: float = top.position.y - base.y
	if ledge < 0.45 or ledge > 2.35 or top.normal.y < 0.6:
		return false
	var head := G.ray(top.position + Vector3(0, 0.2, 0), top.position + Vector3(0, 1.75, 0), G.L_WORLD, [get_rid()])
	if not head.is_empty():
		return false
	busy = true
	velocity = Vector3.ZERO
	face_yaw = atan2(-fwd.x, -fwd.z)
	vis.play("climb", 0.3 + ledge * 0.28)
	var tw := create_tween()
	tw.tween_property(self, "global_position", Vector3(base.x, top.position.y + 0.05, base.z), 0.18 + ledge * 0.2)
	tw.tween_property(self, "global_position", top.position + Vector3(0, 0.05, 0), 0.16)
	tw.tween_callback(func(): busy = false)
	Sfx.play("jump", global_position, -8.0)
	return true


# ------------------------------------------------------------------ cover
func _try_cover() -> void:
	var dirs := [Basis(Vector3.UP, face_yaw) * Vector3(0, 0, -1), G.flat(cam.forward()).normalized()]
	for d in dirs:
		var from := global_position + Vector3(0, 0.75, 0)
		var h := G.ray(from, from + d * 1.7, G.L_WORLD | G.L_VEHICLE, [get_rid()])
		if h.is_empty() or absf(h.normal.y) > 0.35:
			continue
		cover_normal = G.flat(h.normal).normalized()
		var p: Vector3 = h.position + cover_normal * 0.42
		p.y = global_position.y
		var hi := G.ray(p + Vector3(0, 1.5, 0), p + Vector3(0, 1.5, 0) - cover_normal * 1.0, G.L_WORLD | G.L_VEHICLE, [get_rid()])
		cover_low = hi.is_empty()
		in_cover = true
		crouching = false
		cover_pop = Vector3.ZERO
		var tw := create_tween()
		tw.tween_property(self, "global_position", p, 0.14)
		face_yaw = atan2(-cover_normal.x, -cover_normal.z)
		Sfx.play("step", global_position, -6.0, 0.8)
		return


func _cover_move(delta: float, wish: Vector3) -> void:
	var tan := cover_normal.cross(Vector3.UP).normalized()
	var along := wish.dot(tan)
	var away := wish.dot(cover_normal)
	velocity.x = 0.0
	velocity.z = 0.0
	cover_edge = 0
	var chest := global_position + Vector3(0, 0.75, 0)
	for sgn in [-1.0, 1.0]:
		var probe: Vector3 = chest + tan * sgn * 0.55
		if G.ray(probe, probe - cover_normal * 1.0, G.L_WORLD | G.L_VEHICLE, [get_rid()]).is_empty():
			cover_edge = int(sgn)
	if aiming:
		# pop out: sideways at an edge, otherwise up over low cover
		var pop := Vector3.ZERO
		if cover_edge != 0:
			pop = tan * cover_edge * 0.62
		if pop != cover_pop:
			var tw := create_tween()
			tw.tween_property(self, "global_position", global_position - cover_pop + pop, 0.12)
			cover_pop = pop
		face_yaw = cam.yaw
		return
	if cover_pop != Vector3.ZERO:
		var tw2 := create_tween()
		tw2.tween_property(self, "global_position", global_position - cover_pop, 0.12)
		cover_pop = Vector3.ZERO
	face_yaw = atan2(-cover_normal.x, -cover_normal.z)
	if away > 0.75 or Input.is_action_pressed("sprint"):
		in_cover = false
		return
	if absf(along) > 0.2:
		var sgn2 := signf(along)
		var next: Vector3 = chest + tan * sgn2 * 0.5
		var wall := G.ray(next, next - cover_normal * 1.0, G.L_WORLD | G.L_VEHICLE, [get_rid()])
		if not wall.is_empty():
			velocity.x = tan.x * sgn2 * 2.0
			velocity.z = tan.z * sgn2 * 2.0
			var hi := G.ray(next + Vector3(0, 0.75, 0), next + Vector3(0, 0.75, 0) - cover_normal * 1.0, G.L_WORLD | G.L_VEHICLE, [get_rid()])
			cover_low = hi.is_empty()
		else:
			# try to wrap around an outside corner
			var around: Vector3 = chest + tan * sgn2 * 0.75 - cover_normal * 0.75
			var c2 := G.ray(around, around - tan * sgn2 * 1.2, G.L_WORLD | G.L_VEHICLE, [get_rid()])
			if not c2.is_empty() and absf(c2.normal.y) < 0.35 and Input.is_action_pressed("cover"):
				cover_normal = G.flat(c2.normal).normalized()
				var np: Vector3 = c2.position + cover_normal * 0.42
				np.y = global_position.y
				var tw3 := create_tween()
				tw3.tween_property(self, "global_position", np, 0.22)


# ------------------------------------------------------------------ ladders
func _check_ladder(wish: Vector3) -> void:
	if G.world == null:
		return
	for l in G.world.ladders:
		var b: Vector3 = l.base
		var d := Vector2(global_position.x - b.x, global_position.z - b.z).length()
		if d < 1.0 and global_position.y > b.y - 0.6 and global_position.y < float(l.top) - 0.4:
			var n: Vector3 = l.normal
			if wish.length() < 0.1 or wish.normalized().dot(-n) > 0.3 or st == St.SWIM:
				ladder = l
				st = St.LADDER
				velocity = Vector3.ZERO
				in_cover = false
				crouching = false
				global_position = Vector3(b.x, maxf(global_position.y, b.y), b.z) + n * 0.05
				face_yaw = atan2(n.x, n.z)
				vis.mode = "ladder"
				vis.aim = 0.0
				return


func _ladder(delta: float) -> void:
	var f := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var n: Vector3 = ladder.normal
	var b: Vector3 = ladder.base
	global_position.y += f * 2.3 * delta
	vis.speed = absf(f)
	vis.mode = "ladder"
	if global_position.y >= float(ladder.top):
		global_position = Vector3(b.x, float(ladder.top) + 0.1, b.z) - n * 0.9
		st = St.FOOT
		vis.mode = "foot"
	elif (global_position.y <= b.y + 0.05 and f < 0.0) or Input.is_action_just_pressed("jump"):
		global_position += n * 0.4
		st = St.SWIM if global_position.y < G.WATER_LEVEL - 1.1 else St.FOOT
		vis.mode = "foot"


# ------------------------------------------------------------------ swimming / diving
func _enter_water() -> void:
	st = St.SWIM
	in_cover = false
	crouching = false
	aiming = false
	vis.aim = 0.0
	if velocity.y < -4.0 and G.fx:
		G.fx.splash(Vector3(global_position.x, G.WATER_LEVEL, global_position.z), clampf(-velocity.y * 0.15, 0.8, 2.5))
		Sfx.play("splash", global_position)
	velocity.y *= 0.3
	air_t = 0.0
	peak_fall = 0.0
	if chute:
		chute.queue_free()
		chute = null


func _swim(delta: float) -> void:
	var wish := _wish_dir()
	var surface_y := G.WATER_LEVEL - 1.42
	var up := (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
	var head_under := global_position.y + 1.62 < G.WATER_LEVEL
	underwater = head_under
	var sp := 2.3 + (1.2 if Input.is_action_pressed("sprint") and stamina > 0.05 else 0.0) + skill("stamina") * 0.5
	if Input.is_action_pressed("sprint"):
		stamina = maxf(stamina - delta / 20.0, 0.0)
		skill_gain("stamina", delta * 0.001)
	else:
		stamina = minf(stamina + delta * 0.1, 1.0)
	var tv := wish * sp
	var deep := global_position.y < surface_y - 0.25
	if deep and wish.length() > 0.1:
		tv.y = cam.forward().y * sp * wish.dot(G.flat(cam.forward()).normalized())
	tv.y += up * 2.0
	if not deep and up >= 0.0 and tv.y >= 0.0:
		tv.y = (surface_y - global_position.y) * 3.0
	velocity = velocity.lerp(tv, clampf(delta * 3.5, 0.0, 1.0))
	if wish.length() > 0.1:
		face_yaw = atan2(-wish.x, -wish.z)
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	move_and_slide()
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	if global_position.y > surface_y:
		global_position.y = move_toward(global_position.y, surface_y, delta * 3.0)
	# leave the water on shallow ground
	var ground := G.ray(global_position + Vector3(0, 1.0, 0), global_position - Vector3(0, 0.25, 0), G.L_WORLD, [get_rid()])
	if not ground.is_empty() and ground.position.y > G.WATER_LEVEL - 1.1:
		global_position.y = ground.position.y + 0.02
		st = St.FOOT
		vis.mode = "foot"
		vis.rotation.x = 0.0
		underwater = false
		return
	if Input.is_action_just_pressed("interact") or wish.length() > 0.3:
		_check_ladder(wish)
		if st == St.LADDER:
			vis.rotation.x = 0.0
			return
	# breath
	var lung := 22.0 + 30.0 * skill("lung") + (260.0 if has_scuba else 0.0)
	if head_under:
		breath -= delta / lung
		skill_gain("lung", delta * 0.0015)
		if breath <= 0.0:
			breath = 0.0
			take_damage(delta * 14.0, null, global_position, "drown")
	else:
		breath = minf(breath + delta * 0.5, 1.0)
	var hs := Vector3(velocity.x, 0, velocity.z).length()
	vis.mode = "swim"
	vis.speed = hs + absf(velocity.y) * 0.5
	vis.rotation.x = lerp_angle(vis.rotation.x, -1.25 * clampf(hs / 1.2, 0.0, 1.0) + clampf(velocity.y * 0.25, -0.5, 0.5), delta * 4.0)
	vis.position.y = 0.0
	if hs > 0.5 and not head_under and G.fx and randf() < delta * 5.0:
		G.fx.splash(Vector3(global_position.x, G.WATER_LEVEL, global_position.z) + G.flat(velocity).normalized() * 0.6, 0.35)


# ------------------------------------------------------------------ parachute
func _deploy_chute() -> void:
	st = St.CHUTE
	chute = Assets.inst("characters/parachute_canopy", "parachute_canopy_")
	add_child(chute)
	chute.position = Vector3(0, 1.45, 0)
	chute.scale = Vector3(0.1, 0.1, 0.1)
	var tw := create_tween()
	tw.tween_property(chute, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	vis.mode = "chute"
	velocity.y = maxf(velocity.y, -14.0)
	Sfx.play("chute", global_position)
	G.say("Parachute deployed  -  A/D steer, W dive, S flare", Color(0.8, 0.95, 1.0))


func _chute(delta: float) -> void:
	var f := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var s := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	face_yaw -= s * delta * 1.25
	var sink := -5.2
	var fwd_sp := 9.5
	if f > 0.1:
		sink = -10.0
		fwd_sp = 15.0
	elif f < -0.1:
		sink = -2.4
		fwd_sp = 4.5
	var fw := Basis(Vector3.UP, face_yaw) * Vector3(0, 0, -1)
	velocity = velocity.lerp(fw * fwd_sp + Vector3(0, sink, 0), clampf(delta * 1.8, 0.0, 1.0))
	vis.lean = lerpf(vis.lean, s, delta * 4.0)
	vis.mode = "chute"
	if chute:
		chute.rotation.z = lerpf(chute.rotation.z, -s * 0.3, delta * 3.0)
		chute.rotation.x = lerpf(chute.rotation.x, f * 0.2, delta * 3.0)
	var vy := velocity.y
	move_and_slide()
	if is_on_floor() or global_position.y < G.WATER_LEVEL - 1.1:
		if chute:
			chute.queue_free()
			chute = null
		has_parachute = false
		vis.set_pack("")
		vis.lean = 0.0
		st = St.FOOT
		vis.mode = "foot"
		air_t = 0.0
		peak_fall = 0.0
		if global_position.y < G.WATER_LEVEL - 1.1:
			_enter_water()
		elif vy < -7.5:
			take_damage((-vy - 7.5) * 6.0, null, global_position, "fall")
			if not dead:
				_start_ragdoll(velocity * 0.5, 1.2)
		else:
			vis.play("hit", 0.3)
			G.say("Clean landing", Color(0.6, 1.0, 0.6))
	if Input.is_action_just_pressed("enter_vehicle"):
		chute.queue_free()
		chute = null
		st = St.FOOT
		has_parachute = false
		vis.set_pack("")


func give_parachute() -> void:
	has_parachute = true
	vis.set_pack("Parachute_Pack")


func give_scuba(on: bool = true) -> void:
	has_scuba = on
	vis.set_pack("Scuba_Tank" if on else ("Parachute_Pack" if has_parachute else ""))
	vis.set_part("mask", "Scuba_Mask" if on else "")


func apply_look() -> void:
	vis.apply_look(look)
	if has_scuba:
		give_scuba(true)
	elif has_parachute:
		vis.set_pack("Parachute_Pack")
	equip(inv.current)
	hidden_look_change = 20.0


func teleport(p: Vector3, yaw: float = 0.0) -> void:
	if vehicle != null:
		_leave_vehicle_now(false)
	if ragdoll != null:
		_end_ragdoll()
	global_position = p
	velocity = Vector3.ZERO
	face_yaw = yaw
	cam.yaw = yaw
	st = St.FOOT
	vis.mode = "foot"
	vis.rotation.x = 0.0
	in_cover = false
	air_t = 0.0
	peak_fall = 0.0
