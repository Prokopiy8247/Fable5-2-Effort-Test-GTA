class_name Humanoid
extends CharacterBody3D
# Shared base for the player and all NPCs: Blender-rigged model, procedural animation,
# health/armor, weapons (hitscan + projectiles), melee, knockdown "ragdoll".

const GRAV := 22.0

var body: Node3D
var model: Node3D
var skel: Skeleton3D
var bones: Dictionary = {}
var tp: Dictionary = {}
var cp: Dictionary = {}
var hips_cur := 0.0
var look: Dictionary = {}
var mats: Dictionary = {}
var acc_nodes: Dictionary = {}
var health := 100.0
var max_health := 100.0
var armor := 0.0
var dead := false
var state := "normal"
var walk_phase := 0.0
var aiming := false
var aim_pitch := 0.0
var crouching := false
var blocking := false
var attack_t := 0.0
var flinch := 0.0
var weapon := "fists"
var weapon_node: Node3D
var holder: Node3D
var muzzle: Node3D
var flashlight: SpotLight3D
var clip: Dictionary = {}
var reserve: Dictionary = {}
var owned: Array = ["fists"]
var atts: Dictionary = {}
var finish: Dictionary = {}
var fire_cd := 0.0
var reload_t := 0.0
var rag_t := 0.0
var rag_dir := 1.0
var cshape: CollisionShape3D
var capsule: CapsuleShape3D
var is_player := false
var vehicle = null
var last_attacker = null
var accuracy := 1.0
var alerted := false
var roll_t := 0.0


func setup(l: Dictionary) -> void:
	look = l
	collision_layer = G.L_CHAR
	collision_mask = G.L_WORLD | G.L_VEH | G.L_PROP
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	cshape = CollisionShape3D.new()
	cshape.shape = capsule
	cshape.position.y = 0.9
	add_child(cshape)
	body = Node3D.new()
	add_child(body)
	model = G.model("characters/char_female" if l.get("female", false) else "characters/char_male")
	body.add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i)
		var gr := skel.get_bone_global_rest(i).basis.get_rotation_quaternion()
		bones[bn] = {"i": i, "rest": skel.get_bone_rest(i).basis.get_rotation_quaternion(), "gr": gr, "gri": gr.inverse(), "pos": skel.get_bone_rest(i).origin}
		cp[bn] = Vector3.ZERO
		tp[bn] = Vector3.ZERO
	var ba := BoneAttachment3D.new()
	skel.add_child(ba)
	ba.bone_name = "hand_r"
	holder = Node3D.new()
	ba.add_child(holder)
	holder.transform = Transform3D(skel.get_bone_global_rest(bones["hand_r"].i).basis.inverse() * Basis(Vector3.RIGHT, -PI / 2), Vector3.ZERO)
	apply_look()
	G.humanoids.append(self)
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.3


func _exit_tree() -> void:
	G.humanoids.erase(self)


func apply_look() -> void:
	for mn in ["Skin", "Shirt", "Pants", "Shoes"]:
		var key: String = mn.to_lower()
		var c: Color = look.get(key, Color(0.8, 0.8, 0.8))
		if not mats.has(mn):
			mats[mn] = G.flat_mat(c, 0.85)
			G.tint(model, mn, mats[mn])
		mats[mn].albedo_color = c
	for slot in acc_nodes.keys():
		acc_nodes[slot].queue_free()
	acc_nodes.clear()
	for slot in ["hair", "beard", "hat", "glasses"]:
		var mn2: String = look.get(slot, "")
		if mn2 != "" and mn2 != "none":
			if slot == "hair" and look.get("hat", "") in ["acc_helmet"]:
				continue
			attach(slot, mn2, "head")
	for slot in ["vest", "pack"]:
		var mn3: String = look.get(slot, "")
		if mn3 != "":
			attach(slot, mn3, "chest")


func attach(slot: String, mname: String, bone: String) -> void:
	if acc_nodes.has(slot):
		acc_nodes[slot].queue_free()
		acc_nodes.erase(slot)
	if mname == "":
		return
	var ba := BoneAttachment3D.new()
	skel.add_child(ba)
	ba.bone_name = bone
	var n := G.model("characters/" + mname)
	ba.add_child(n)
	n.transform = Transform3D(skel.get_bone_global_rest(bones[bone].i).basis.inverse(), Vector3.ZERO)
	mats["Hair"] = G.flat_mat(look.get("hair_color", Color(0.2, 0.13, 0.08)), 0.9)
	mats["Hat"] = G.flat_mat(look.get("hat_color", Color(0.15, 0.2, 0.4)), 0.85)
	G.tint(n, "Hair", mats["Hair"])
	G.tint(n, "Hat", mats["Hat"])
	acc_nodes[slot] = ba


# ---------------------------------------------------------------- weapons
func wdef() -> Dictionary:
	return Defs.WEAPONS[weapon]


func mag_size(id: String) -> int:
	var d: Dictionary = Defs.WEAPONS[id]
	var m: int = d.get("mag", 0)
	if "extmag" in atts.get(id, []):
		m = int(m * 1.5)
	return m


func give_weapon(id: String, ammo := -1) -> void:
	var d: Dictionary = Defs.WEAPONS[id]
	if not id in owned:
		owned.append(id)
		clip[id] = mag_size(id)
		reserve[id] = 0
	if d.has("mag"):
		var add: int = d.mag * 3 if ammo < 0 else ammo
		reserve[id] = min(d.max, reserve.get(id, 0) + add)


func equip(id: String) -> void:
	if not id in owned:
		return
	weapon = id
	reload_t = 0.0
	if weapon_node:
		weapon_node.queue_free()
		weapon_node = null
	muzzle = null
	flashlight = null
	var d := wdef()
	if d.model != "":
		weapon_node = G.model("weapons/" + d.model)
		holder.add_child(weapon_node)
		refresh_weapon_parts()


func refresh_weapon_parts() -> void:
	if weapon_node == null:
		return
	var has: Array = atts.get(weapon, [])
	for a in weapon_node.find_children("*__att_*", "Node3D", true, false):
		var an := String(a.name)
		a.visible = an.substr(an.find("__att_") + 6) in has
	muzzle = G.part(weapon_node, "muzzle")
	if finish.has(weapon):
		G.tint(weapon_node, "WeaponFinish", G.flat_mat(finish[weapon], 0.4, 0.6))
	if flashlight:
		flashlight.queue_free()
		flashlight = null
	if "flashlight" in has and muzzle:
		flashlight = SpotLight3D.new()
		flashlight.spot_range = 28.0
		flashlight.spot_angle = 22.0
		flashlight.light_energy = 3.0
		flashlight.shadow_enabled = false
		flashlight.visible = false
		muzzle.add_child(flashlight)


func reload() -> void:
	var d := wdef()
	if d.get("melee", false) or reload_t > 0.0:
		return
	if clip.get(weapon, 0) >= mag_size(weapon) or reserve.get(weapon, 0) <= 0:
		return
	reload_t = d.reload * (1.0 - 0.25 * G.skill("shooting") if is_player else 1.0)
	G.audio.play3d("reload", global_position)


func _finish_reload() -> void:
	var need: int = mag_size(weapon) - clip.get(weapon, 0)
	var take: int = min(need, reserve.get(weapon, 0))
	clip[weapon] = clip.get(weapon, 0) + take
	reserve[weapon] -= take


func spread_dir(dir: Vector3, deg: float) -> Vector3:
	if deg <= 0.0:
		return dir
	var r := deg_to_rad(deg) * sqrt(randf())
	var a := randf() * TAU
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(dir).normalized()
	return (dir + (side * cos(a) + up * sin(a)) * tan(r)).normalized()


func fire(origin: Vector3, dir: Vector3, spread_mult := 1.0) -> bool:
	var d := wdef()
	if dead or fire_cd > 0.0 or reload_t > 0.0:
		return false
	if d.get("melee", false):
		return melee_attack(false)
	if clip.get(weapon, 0) <= 0:
		if reserve.get(weapon, 0) > 0:
			reload()
		else:
			fire_cd = 0.4
			G.audio.play3d("click", global_position)
		return false
	clip[weapon] -= 1
	fire_cd = 1.0 / d.rate
	var has: Array = atts.get(weapon, [])
	var silenced := "suppressor" in has
	var spread: float = d.spread * spread_mult * (0.7 if "grip" in has else 1.0) / max(accuracy, 0.2)
	var mpos: Vector3 = muzzle.global_position if muzzle else origin
	if state != "vehicle" and mpos.y - global_position.y < (0.7 if crouching else 1.05):
		# arm not raised yet (hip / first shot): fire from the shoulder line instead of the floor
		mpos = global_position + Vector3.UP * (0.95 if crouching else 1.4) + dir * 0.7 + global_basis.x * 0.22
	var proj: String = d.get("proj", "")
	if proj == "grenade":
		G.fx.throw_grenade(self, mpos, dir, d.dmg)
	elif proj == "rocket":
		G.fx.launch_rocket(self, mpos, origin, dir, d.dmg)
	else:
		for p in d.get("pellets", 1):
			var dd := spread_dir(dir, spread)
			var hit := G.ray(origin, origin + dd * d.range, G.L_WORLD | G.L_VEH | G.L_CHAR | G.L_PROP, [self, vehicle])
			var end: Vector3 = hit.position if not hit.is_empty() else origin + dd * d.range
			G.fx.tracer(mpos, end)
			if not hit.is_empty():
				var dmg: float = d.dmg * (0.92 if silenced else 1.0)
				var target = G.damage_target(hit.collider, dmg, self, hit.position, dd, "bullet")
				G.fx.impact(hit.position, hit.normal, target)
	if proj != "grenade":
		G.fx.muzzle_flash(mpos, dir)
	G.audio.play3d("shot_silenced" if silenced else d.snd, mpos)
	if proj != "grenade":
		G.emit_danger(global_position, 14.0 if silenced else 75.0, self, "gunshot")
	if clip[weapon] <= 0 and reserve.get(weapon, 0) > 0:
		reload()
	return true


func melee_attack(heavy: bool) -> bool:
	if dead or fire_cd > 0.0:
		return false
	var d := wdef()
	if not d.get("melee", false):
		d = Defs.WEAPONS["fists"]
	fire_cd = (1.0 / d.rate) * (1.5 if heavy else 1.0)
	attack_t = 0.35
	var fwd := -global_basis.z
	var hit_any := false
	var mult := (1.9 if heavy else 1.0) * ((1.0 + 0.6 * G.skill("strength")) if is_player else 1.0)
	for h in G.humanoids.duplicate():
		if h == self or h.dead or h.vehicle != null:
			continue
		var v: Vector3 = h.global_position - global_position
		if v.length() < d.range and abs(v.y) < 1.6 and fwd.dot(v.normalized()) > 0.35:
			hit_any = true
			var behind: bool = (-h.global_basis.z).dot(v.normalized()) > 0.4
			if is_player and crouching and behind and not h.alerted:
				h.take_damage(9999.0, self, h.global_position + Vector3.UP, v.normalized(), "stealth")
				G.skill_gain("stealth", 3.0)
				G.notify("Stealth takedown")
			else:
				h.take_damage(d.dmg * mult, self, h.global_position + Vector3.UP * 1.2, v.normalized(), "melee")
				if (heavy or d.get("knock", false)) and not h.dead:
					h.knockdown(v.normalized() * 4.5 + Vector3.UP * 2.5)
	if not hit_any:
		var c := global_position + Vector3.UP * 1.1
		var hit := G.ray(c, c + fwd * d.range, G.L_VEH | G.L_PROP, [self])
		if not hit.is_empty():
			hit_any = true
			G.damage_target(hit.collider, d.dmg * mult, self, hit.position, fwd, "melee")
			G.fx.impact(hit.position, hit.normal, null)
	G.audio.play3d("punch" if hit_any else "swing", global_position)
	if is_player and hit_any:
		G.skill_gain("strength", 0.4)
	return true


# ---------------------------------------------------------------- damage
func take_damage(amount: float, attacker, pos: Vector3, dir: Vector3, kind: String) -> void:
	if dead:
		return
	if is_player and G.invulnerable:
		return
	if kind == "bullet" and pos.y - global_position.y > (1.05 if crouching else 1.5):
		amount *= 2.5
	if kind == "melee" and blocking and dir.dot(-global_basis.z) < -0.2:
		amount *= 0.25
	if is_player and kind == "melee":
		amount *= 1.0 - 0.3 * G.skill("strength")
	if armor > 0.0 and kind in ["bullet", "melee", "explosion"]:
		var ab: float = min(armor, amount * 0.75)
		armor -= ab
		amount -= ab
	health -= amount
	flinch = 0.3
	if attacker != null:
		last_attacker = attacker
	_damaged(amount, attacker, kind)
	if kind == "bullet" or kind == "melee":
		G.fx.blood(pos)
	if health <= 0.0:
		die(attacker, dir, kind)
	elif (kind == "explosion" and amount > 20.0) or (kind == "vehicle" and amount > 10.0):
		knockdown(dir * 6.0 + Vector3.UP * 4.0)


func _damaged(_amount: float, _attacker, _kind: String) -> void:
	pass


func _died(_attacker, _kind: String) -> void:
	pass


func die(attacker, dir: Vector3, kind: String) -> void:
	if dead:
		return
	dead = true
	health = 0.0
	if state != "vehicle":
		knockdown(dir * (7.0 if kind in ["explosion", "vehicle"] else 2.5) + Vector3.UP * (4.0 if kind in ["explosion", "vehicle"] else 1.5))
	collision_layer = 0
	_died(attacker, kind)


func knockdown(impulse: Vector3) -> void:
	if state == "vehicle":
		return
	state = "ragdoll"
	velocity = impulse
	rag_t = 0.0
	rag_dir = 1.0 if (-global_basis.z).dot(impulse) < 0.0 else -1.0
	aiming = false


func _ragdoll_physics(dt: float) -> void:
	if global_position.y < G.WATER_Y - 1.2:
		velocity.y = lerp(velocity.y, 1.2 if not dead else 0.3, min(1.0, dt * 4.0))
		velocity.x *= 1.0 - dt * 2.0
		velocity.z *= 1.0 - dt * 2.0
	else:
		velocity.y -= GRAV * dt
	move_and_slide()
	if is_on_floor() or global_position.y < G.WATER_Y - 1.2:
		velocity.x *= 1.0 - min(1.0, dt * 6.0)
		velocity.z *= 1.0 - min(1.0, dt * 6.0)
		if Vector2(velocity.x, velocity.z).length() < 1.0:
			rag_t += dt
	if not dead and rag_t > 1.4:
		state = "normal"


func tick(dt: float) -> void:
	fire_cd = max(0.0, fire_cd - dt)
	attack_t = max(0.0, attack_t - dt)
	flinch = max(0.0, flinch - dt)
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			_finish_reload()


# ---------------------------------------------------------------- procedural animation
func _animate(dt: float) -> void:
	for k in tp:
		tp[k] = Vector3.ZERO
	var hs := Vector2(velocity.x, velocity.z).length()
	var p := walk_phase
	var ho := 0.0
	var bp := 0.0
	var t := G.time_now
	var two_handed: bool = weapon_node != null and not wdef().get("onehand", false) and not wdef().get("melee", false)
	match state:
		"ragdoll":
			bp = rag_dir * PI / 2 * clamp(rag_t * 3.0 + 0.6, 0.0, 1.0)
			tp["arm_l"] = Vector3(0.3, 0, -1.3)
			tp["arm_r"] = Vector3(-0.4, 0, 1.0)
			tp["thigh_l"] = Vector3(0.35, 0, -0.15)
			tp["shin_r"] = Vector3(-0.7, 0, 0)
			tp["head"] = Vector3(0, 0.5, 0)
		"swim":
			walk_phase += (1.5 + hs) * dt * 2.0
			var moving: bool = hs > 0.4 or abs(velocity.y) > 0.4
			bp = -1.3 if moving else -0.25
			if moving:
				tp["arm_l"] = Vector3(PI * 0.9 + sin(p) * 0.9, 0, 0)
				tp["arm_r"] = Vector3(PI * 0.9 - sin(p) * 0.9, 0, 0)
				tp["thigh_l"] = Vector3(sin(p * 2.0) * 0.35, 0, 0)
				tp["thigh_r"] = Vector3(-sin(p * 2.0) * 0.35, 0, 0)
			else:
				tp["arm_l"] = Vector3(0.4, 0, -1.0 + sin(t * 2.5) * 0.3)
				tp["arm_r"] = Vector3(0.4, 0, 1.0 - sin(t * 2.5) * 0.3)
				tp["thigh_l"] = Vector3(sin(t * 3.0) * 0.4, 0, 0)
				tp["thigh_r"] = Vector3(-sin(t * 3.0) * 0.4, 0, 0)
		"climb":
			tp["arm_l"] = Vector3(2.5 + sin(p) * 0.45, 0, 0)
			tp["arm_r"] = Vector3(2.5 - sin(p) * 0.45, 0, 0)
			tp["forearm_l"] = Vector3(0.5, 0, 0)
			tp["forearm_r"] = Vector3(0.5, 0, 0)
			tp["thigh_l"] = Vector3(0.7 + sin(p) * 0.5, 0, 0)
			tp["thigh_r"] = Vector3(0.7 - sin(p) * 0.5, 0, 0)
			tp["shin_l"] = Vector3(-1.0, 0, 0)
			tp["shin_r"] = Vector3(-1.0, 0, 0)
		"chute":
			tp["arm_l"] = Vector3(2.9, 0, -0.35)
			tp["arm_r"] = Vector3(2.9, 0, 0.35)
			tp["thigh_l"] = Vector3(0.3 + sin(t * 2.0) * 0.08, 0, 0)
			tp["thigh_r"] = Vector3(0.2, 0, 0)
			tp["shin_l"] = Vector3(-0.4, 0, 0)
			tp["shin_r"] = Vector3(-0.3, 0, 0)
		"vehicle":
			ho = -0.42
			for s in ["l", "r"]:
				tp["thigh_" + s] = Vector3(1.45, 0, 0)
				tp["shin_" + s] = Vector3(-1.3, 0, 0)
				tp["arm_" + s] = Vector3(1.0, 0, 0)
				tp["forearm_" + s] = Vector3(0.35, 0, 0)
			tp["chest"] = Vector3(-0.18, 0, 0)
			if aiming:
				tp["arm_r"] = Vector3(PI / 2 + aim_pitch, 0.0, 0)
		"cower":
			ho = -0.4
			for s in ["l", "r"]:
				tp["thigh_" + s] = Vector3(1.3, 0, 0)
				tp["shin_" + s] = Vector3(-2.0, 0, 0)
				tp["arm_" + s] = Vector3(2.7, 0, 0)
				tp["forearm_" + s] = Vector3(1.7, 0, 0)
			tp["chest"] = Vector3(-0.6, 0, 0)
		"surrender":
			tp["arm_l"] = Vector3(0, 0, -2.7)
			tp["arm_r"] = Vector3(0, 0, 2.7)
		_:
			var a: float = clamp(hs / 4.5, 0.0, 1.2)
			walk_phase += hs * dt * (2.9 if crouching else 2.3)
			var s := sin(p)
			var on_floor := is_on_floor() or state == "cover" or state == "enter"
			if on_floor:
				tp["thigh_l"] = Vector3(s * 0.75 * a, 0, 0)
				tp["thigh_r"] = Vector3(-s * 0.75 * a, 0, 0)
				tp["shin_l"] = Vector3(-clamp(-cos(p) + 0.2, 0.0, 1.0) * 1.1 * a, 0, 0)
				tp["shin_r"] = Vector3(-clamp(cos(p) + 0.2, 0.0, 1.0) * 1.1 * a, 0, 0)
				ho = -abs(cos(p)) * 0.035 * a
			else:
				tp["thigh_l"] = Vector3(0.5, 0, 0)
				tp["thigh_r"] = Vector3(-0.2, 0, 0)
				tp["shin_l"] = Vector3(-0.7, 0, 0)
			tp["arm_l"] = Vector3(-s * 0.6 * a, 0, -0.07)
			tp["arm_r"] = Vector3(s * 0.6 * a, 0, 0.07)
			tp["forearm_l"] = Vector3(0.15 + 0.6 * a, 0, 0)
			tp["forearm_r"] = Vector3(0.15 + 0.6 * a, 0, 0)
			tp["chest"] = Vector3(-0.12 * a + sin(t * 1.6) * 0.015, 0, 0)
			if not on_floor:
				tp["arm_l"] = Vector3(2.3 + sin(t * 9.0) * 0.3, 0, -0.5)
				tp["arm_r"] = Vector3(2.3 - sin(t * 9.0) * 0.3, 0, 0.5)
			if crouching:
				ho -= 0.38
				tp["thigh_l"] += Vector3(1.1, 0, 0)
				tp["thigh_r"] += Vector3(1.1, 0, 0)
				tp["shin_l"] += Vector3(-1.9, 0, 0)
				tp["shin_r"] += Vector3(-1.9, 0, 0)
				tp["chest"] += Vector3(-0.35, 0, 0)
			if two_handed and not aiming:
				tp["arm_r"] = Vector3(0.45, 0, 0.1)
				tp["forearm_r"] = Vector3(1.0, 0, 0)
				tp["arm_l"] = Vector3(0.75, -0.6, 0)
				tp["forearm_l"] = Vector3(0.9, 0, 0)
			if aiming:
				var cx := 0.35 if crouching else 0.0
				tp["arm_r"] = Vector3(PI / 2 + aim_pitch + cx, 0.12, 0)
				tp["forearm_r"] = Vector3.ZERO
				tp["arm_l"] = Vector3(PI / 2 + aim_pitch - 0.08 + cx, -0.55, 0)
				tp["forearm_l"] = Vector3.ZERO
				tp["head"] = Vector3(aim_pitch * 0.5, 0, 0)
			if blocking:
				tp["arm_l"] = Vector3(1.9, -0.4, 0)
				tp["arm_r"] = Vector3(1.9, 0.4, 0)
				tp["forearm_l"] = Vector3(1.5, 0, 0)
				tp["forearm_r"] = Vector3(1.5, 0, 0)
			if attack_t > 0.0:
				var k: float = attack_t / 0.35
				tp["arm_r"] = Vector3(lerp(0.9, 2.7, k), 0.2, 0)
				tp["forearm_r"] = Vector3(0.5 * k, 0, 0)
				tp["chest"] += Vector3(0, (0.5 - k) * 0.9, 0)
				cp["arm_r"] = tp["arm_r"]
			if roll_t > 0.0:
				bp = -(1.0 - roll_t / 0.55) * TAU
				ho = -0.4
				for sd in ["l", "r"]:
					tp["thigh_" + sd] = Vector3(1.6, 0, 0)
					tp["shin_" + sd] = Vector3(-2.0, 0, 0)
	if flinch > 0.0:
		tp["chest"] += Vector3(flinch * 1.2, 0, 0)
	var kk: float = min(1.0, dt * 14.0)
	for b in cp:
		cp[b] = cp[b].lerp(tp[b], kk)
		var d: Dictionary = bones[b]
		skel.set_bone_pose_rotation(d.i, d.rest * (d.gri * Quaternion.from_euler(cp[b]) * d.gr))
	hips_cur = lerp(hips_cur, ho, kk)
	var hb: Dictionary = bones["hips"]
	skel.set_bone_pose_position(hb.i, hb.pos + Vector3(0, hips_cur, 0))
	if roll_t > 0.0:
		body.rotation.x = bp
		body.position.y = 0.5
	else:
		body.rotation.x = lerp_angle(body.rotation.x, bp, kk)
		body.position.y = lerp(body.position.y, 0.12 if state == "ragdoll" else 0.0, kk)
	if flashlight:
		flashlight.visible = aiming and state != "ragdoll"
