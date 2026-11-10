class_name Gunner
extends Node
## Weapon handling for one Character (player or NPC): in-hand model with attachments,
## fire timing, spread / recoil, reloads, hitscan + projectiles, melee and throwables.

signal fired(weapon_id: StringName)
signal reloaded(weapon_id: StringName)
signal weapon_equipped(weapon_id: StringName)

var who: Character
var inv: Inventory
var weapon_id: StringName = &"unarmed"
var data: Dictionary = WeaponDB.W[&"unarmed"]
var model: Node3D = null
var cooldown := 0.0
var reload_left := 0.0
var bloom := 0.0
var aiming := false
var blocking := false
var driveby := false
var aim_dir := Vector3.FORWARD      # world direction the weapon is levelled at while aiming
var flashlight: SpotLight3D = null
var _muzzle: Node3D = null
var _hand_l: Node3D = null
var _melee_pending := 0.0
var _melee_heavy := false
var _combo := 0
var _wants_reload_sound := false
var _slide: Node3D = null
var _slide_rest := Vector3.ZERO
var _slide_kick := 0.0
var _trigger_was := false
const HOLD_BASIS := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))   # barrel (-Z) -> down the arm (-Y)

func setup(c: Character) -> void:
	who = c
	inv = c.inventory
	inv.changed.connect(_on_inventory_changed)
	equip(inv.current, true)

func _on_inventory_changed() -> void:
	if not inv.has(weapon_id):
		equip(&"unarmed")
	else:
		refresh_model()

# ---------------------------------------------------------------- equip / model
func equip(id: StringName, silent := false) -> void:
	if not inv.has(id):
		return
	weapon_id = id
	inv.current = id
	data = WeaponDB.get_w(id)
	reload_left = 0.0
	cooldown = maxf(cooldown, 0.25)
	bloom = 0.0
	refresh_model()
	if not silent:
		Audio.play(&"weapon_switch", who.global_position, -10.0)
	weapon_equipped.emit(id)
	if who.is_player:
		Events.weapon_changed.emit(id)

func refresh_model() -> void:
	if model != null and is_instance_valid(model):
		model.queue_free()
	model = null
	_muzzle = null
	_hand_l = null
	_slide = null
	flashlight = null
	var rel := String(data.get("model", ""))
	if rel == "" or who.visual == null or not Assets.has_model(rel):
		return
	model = Assets.instance(rel)
	who.visual.hand_r.add_child(model)
	model.transform = Transform3D(HOLD_BASIS, Vector3.ZERO)
	_muzzle = PropFactory.part(model, "muzzle")
	_hand_l = PropFactory.part(model, "hand_l")
	_slide = PropFactory.part(model, "slide")
	if _slide == null:
		_slide = PropFactory.part(model, "pump")
	if _slide:
		_slide_rest = _slide.position
	var atts := inv.atts(weapon_id)
	var mag := PropFactory.part(model, "mag")
	var mag_ext := PropFactory.part(model, "mag_ext")
	if mag_ext != null:
		mag_ext.visible = atts.has("extmag")
		if mag != null:
			mag.visible = not atts.has("extmag")
	var mounts: Array = atts.duplicate()
	if data.has("builtin_scope"):
		mounts.append("builtin")
	for a in mounts:
		var path := String(data["builtin_scope"]) if a == "builtin" else WeaponDB.att_for(weapon_id, a)
		if a == "builtin":
			path = "weapons/att/" + path
		var marker_name := "scope" if a == "builtin" else String(WeaponDB.ATT.get(a, {}).get("marker", ""))
		if path == "" or marker_name == "" or not Assets.has_model(path):
			continue
		var marker := PropFactory.part(model, marker_name)
		if marker == null and marker_name == "suppressor":
			marker = _muzzle
		if marker == null:
			continue
		var am := Assets.instance(path)
		marker.add_child(am)
		if a == "suppressor":
			var tip := Node3D.new()
			tip.position = Vector3(0, 0, -0.17 if data["hold"] == &"pistol" else -0.23)
			am.add_child(tip)
			_muzzle = tip
		elif a == "flashlight":
			flashlight = SpotLight3D.new()
			flashlight.light_energy = 6.0
			flashlight.spot_range = 38.0
			flashlight.spot_angle = 24.0
			flashlight.light_color = Color(0.95, 0.97, 1.0)
			flashlight.shadow_enabled = false
			flashlight.visible = false
			var lm := PropFactory.part(am, "light")
			(lm if lm != null else am).add_child(flashlight)
	var tint: Dictionary = WeaponDB.TINTS[clampi(int(inv.items[weapon_id]["tint"]), 0, WeaponDB.TINTS.size() - 1)]
	for mi in Assets.find_meshes(model):
		mi.set_instance_shader_parameter(&"tint_a", Color.html(tint["metal"]).srgb_to_linear())
		mi.set_instance_shader_parameter(&"tint_b", Color.html(tint["furn"]).srgb_to_linear())
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func drop_weapon_model() -> void:
	if model != null and is_instance_valid(model):
		model.queue_free()
	model = null
	if Game.pickups and weapon_id != &"unarmed" and not who.is_player:
		Game.pickups.drop_weapon(weapon_id, maxi(inv.mag(weapon_id), 6), who.global_position + Vector3(0, 0.3, 0))

func is_gun() -> bool:
	return WeaponDB.is_gun(weapon_id)

func hold() -> StringName:
	return data.get("hold", &"fist")

func suppressed() -> bool:
	return inv.has_att("suppressor", weapon_id)

func att_mul(key: String) -> float:
	var m := 1.0
	for a in inv.atts(weapon_id):
		m *= float(WeaponDB.ATT.get(a, {}).get(key, 1.0))
	return m

func zoom_fov() -> float:
	var z := float(data.get("zoom", 52.0))
	for a in inv.atts(weapon_id):
		var ad: Dictionary = WeaponDB.ATT.get(a, {})
		if ad.has("zoom_to"):
			z = float(ad["zoom_to"])
		z += float(ad.get("zoom", 0.0))
	return z

func noise_radius() -> float:
	return float(data.get("noise", 60.0)) * att_mul("noise")

func muzzle_position() -> Vector3:
	if _muzzle != null and is_instance_valid(_muzzle):
		return _muzzle.global_position
	return who.chest_position() + who.forward() * 0.5

func current_spread() -> float:
	var s := float(data.get("spread_aim" if aiming else "spread_hip", 3.0))
	s *= att_mul("spread")
	if aiming:
		s *= att_mul("spread_aim")
	if who.crouched:
		s *= 0.8
	if Vector2(who.velocity.x, who.velocity.z).length() > 2.5:
		s *= 1.35
	if driveby:
		s *= 1.9
	if who.is_player and Game.skills:
		s *= lerpf(1.0, 0.72, Game.skills.level(&"shooting"))
	elif not who.is_player:
		s *= float(who.get("accuracy_spread") if who.get("accuracy_spread") != null else 2.2)
	return s + bloom

# ---------------------------------------------------------------- update
func _process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	bloom = maxf(0.0, bloom - delta * (5.0 if aiming else 3.5))
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			_finish_reload()
	if _melee_pending > 0.0:
		_melee_pending -= delta
		if _melee_pending <= 0.0:
			_melee_hit()
	if _slide != null and is_instance_valid(_slide):
		_slide_kick = move_toward(_slide_kick, 0.0, delta * 0.5)
		_slide.position = _slide_rest + Vector3(0, 0, _slide_kick)
	if model != null and is_instance_valid(model):
		var levelled := aiming or cooldown > 0.0 and is_gun() and bloom > 0.0
		if is_gun() and levelled and who.alive:
			# keep the barrel on the aim line whatever the arm pose is doing
			var d := aim_dir.normalized()
			var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.FORWARD
			var b := Basis.looking_at(d, up)
			model.global_transform = Transform3D(b, model.global_position)
		else:
			model.transform = Transform3D(HOLD_BASIS, Vector3.ZERO)
		if flashlight != null:
			flashlight.visible = aiming and who.alive
	if who.visual != null:
		if aiming and is_gun() and _hand_l != null and is_instance_valid(_hand_l) and reload_left <= 0.0 and who.vehicle == null:
			who.visual.set_ik_hands(_hand_l.global_position, null)
		elif who.vehicle == null:
			who.visual.set_ik_hands(null, null)

# ---------------------------------------------------------------- firing
func can_fire() -> bool:
	return who.alive and cooldown <= 0.0 and reload_left <= 0.0 and not who.down

## Call every frame while the trigger is held. `target` = world point under the crosshair.
## Returns true when a shot / attack was started this frame.
func trigger(target: Vector3, pressed_now: bool) -> bool:
	if not can_fire():
		return false
	var cls: StringName = data["cls"]
	if cls == &"melee":
		if pressed_now:
			return melee(false)
		return false
	if cls == &"thrown":
		if pressed_now:
			return throw_grenade((target - who.eye_position()).normalized())
		return false
	if not bool(data.get("auto", false)) and not pressed_now:
		return false
	return fire_at(target)

func fire_at(target: Vector3) -> bool:
	if not can_fire() or not is_gun():
		return false
	if inv.mag(weapon_id) <= 0:
		if inv.reserve(weapon_id) > 0:
			reload()
		else:
			cooldown = 0.3
			Audio.play(&"dry_fire", who.global_position, -8.0)
		return false
	cooldown = 60.0 / float(data.get("rpm", 300.0))
	if not (who.is_player and Game.cheats["infinite_ammo"]):
		inv.items[weapon_id]["mag"] = inv.mag(weapon_id) - 1
	var from := muzzle_position()
	# never shoot through the wall the muzzle is poking into
	var chest := who.chest_position()
	var block := Game.ray(chest, from, Phys.WORLD, [who.get_rid()])
	if not block.is_empty():
		from = chest
	var base_dir := (target - from).normalized()
	aim_dir = base_dir
	var spread := deg_to_rad(current_spread())
	var pellets := int(data.get("pellets", 1))
	var dmg := float(data.get("dmg", 10.0)) * att_mul("dmg")
	var rng_m := float(data.get("range", 60.0)) * att_mul("range")
	var proj := String(data.get("projectile", ""))
	if proj != "":
		var dirp := _spread_dir(base_dir, spread)
		Projectile.spawn(proj, from + dirp * 0.4, dirp, who)
		var rl := PropFactory.part(model, "rocket_loaded") if model else null
		if rl:
			rl.visible = false
	else:
		for i in pellets:
			Ballistics.hitscan(who, from, _spread_dir(base_dir, spread), rng_m, dmg, pellets > 1)
	# feedback
	var supp := suppressed()
	Audio.play(&"shot_suppressed" if supp else StringName(data.get("sound", &"shot_pistol")), from, -2.0 if who.is_player else -5.0, 1.0, 0.05, 160.0 if not supp else 40.0)
	if Game.fx:
		Game.fx.muzzle_flash(from, base_dir, 0.5 if supp else 1.0)
		if proj == "":
			Game.fx.shell(from - base_dir * 0.25, who.global_transform.basis.x)
	bloom = minf(bloom + float(data.get("recoil", 1.0)) * 0.45 * att_mul("recoil"), 7.0)
	_slide_kick = 0.045
	if who.visual:
		who.visual.recoil = 1.0
	Events.noise.emit(from, noise_radius(), &"gunshot", who)
	if who.is_player:
		Game.stats["shots_fired"] += 1
		Events.crime.emit(&"gunfire", from, {"radius": noise_radius(), "suppressed": supp})
	fired.emit(weapon_id)
	if inv.mag(weapon_id) <= 0 and inv.reserve(weapon_id) > 0:
		reload()
	return true

func _spread_dir(dir: Vector3, spread: float) -> Vector3:
	if spread <= 0.0001:
		return dir
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	var up2 := right.cross(dir).normalized()
	var ang := randf() * TAU
	var r := spread * sqrt(randf())
	return (dir + right * cos(ang) * r + up2 * sin(ang) * r).normalized()

func recoil_kick() -> float:
	## camera pitch kick in radians for the player's last shot
	var k := deg_to_rad(float(data.get("recoil", 1.0))) * att_mul("recoil") * 0.55
	if Game.skills:
		k *= lerpf(1.0, 0.65, Game.skills.level(&"shooting"))
	return k

func reload() -> void:
	if not is_gun() or reload_left > 0.0:
		return
	if inv.mag(weapon_id) >= inv.mag_size(weapon_id) or inv.reserve(weapon_id) <= 0:
		return
	var t := float(data.get("reload", 1.5))
	if who.is_player and Game.skills:
		t *= lerpf(1.0, 0.72, Game.skills.level(&"shooting"))
	reload_left = t
	if who.visual:
		var clip_len := who.visual.play_upper("Reload", 1.0)
		if clip_len > 0.0:
			who.visual.set_meta("overlay_speed", clip_len / t)
	var snd := &"reload_pistol"
	if data["hold"] == &"rifle" or data["hold"] == &"launcher":
		snd = &"reload_shotgun" if data["cls"] == &"shotgun" else &"reload_rifle"
	Audio.play(snd, who.global_position, -6.0)

func _finish_reload() -> void:
	var need := inv.mag_size(weapon_id) - inv.mag(weapon_id)
	var take := mini(need, inv.reserve(weapon_id))
	if who.is_player and Game.cheats["infinite_ammo"]:
		take = need
	else:
		inv.items[weapon_id]["reserve"] = inv.reserve(weapon_id) - take
	inv.items[weapon_id]["mag"] = inv.mag(weapon_id) + take
	var rl := PropFactory.part(model, "rocket_loaded") if model else null
	if rl:
		rl.visible = true
	if data["cls"] == &"shotgun":
		Audio.play(&"pump_shotgun", who.global_position, -6.0)
	reloaded.emit(weapon_id)

# ---------------------------------------------------------------- melee / thrown
func melee(heavy: bool) -> bool:
	if not can_fire() or _melee_pending > 0.0:
		return false
	var rate := float(data.get("rate", 2.0))
	cooldown = (1.0 / rate) * (1.55 if heavy else 1.0)
	_melee_heavy = heavy
	_melee_pending = 0.22 if heavy else 0.13
	var clip := "Punch_L"
	if weapon_id == &"unarmed":
		_combo = (_combo + 1) % 2
		clip = "Kick" if heavy else ("Punch_L" if _combo == 0 else "Punch_R")
	elif weapon_id == &"knife":
		clip = "Stab"
	else:
		clip = "SwingBat"
	if who.visual:
		var moving := Vector2(who.velocity.x, who.velocity.z).length() > 0.5
		if moving and clip != "Kick":
			who.visual.play_upper(clip, 1.4)
		elif who.visual.play_action(clip, 1.4) <= 0.0:
			who.visual.recoil = 2.0
	Audio.play(&"melee_swing", who.global_position, -8.0, 0.9 if heavy else 1.1, 0.1)
	return true

func _melee_hit() -> void:
	if not who.alive:
		return
	var reach := float(data.get("range", 1.5)) + (0.2 if _melee_heavy else 0.0)
	var dmg := float(data.get("heavy" if _melee_heavy else "dmg", 12.0))
	if who.is_player and Game.skills:
		dmg *= lerpf(1.0, 1.5, Game.skills.level(&"strength"))
	var origin := who.chest_position()
	var fwd := who.forward()
	var best: Node = null
	var best_d := 1.0e9
	var shape := SphereShape3D.new()
	shape.radius = reach
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, origin + fwd * (reach * 0.55))
	q.collision_mask = Phys.CHARACTER | Phys.VEHICLE | Phys.PROP | Phys.GLASS
	q.exclude = [who.get_rid()]
	for hit in Game.space().intersect_shape(q, 12):
		var c: Object = hit["collider"]
		if not (c is Node3D) or c == who or c == who.vehicle:
			continue
		var to := (c as Node3D).global_position + Vector3(0, 0.9, 0) - origin
		to.y = 0.0
		if to.length() > 0.3 and to.normalized().dot(fwd) < 0.25:
			continue
		var d := to.length()
		if c is Character:
			d -= 1.0      # prefer people over props
		if d < best_d:
			best_d = d
			best = c
	if best == null:
		return
	var pos: Vector3 = (best as Node3D).global_position + Vector3(0, 1.1, 0)
	var knock: bool = _melee_heavy or bool(data.get("knock", false)) and randf() < 0.45
	if best.has_method("apply_damage"):
		best.apply_damage(dmg, who, pos, fwd, {"type": "melee", "force": 5.0 if knock else 1.5, "knock": knock,
			"silent": bool(data.get("silent_kill", false))})
	if best is Character and knock and (best as Character).alive:
		(best as Character).knockdown(fwd * 4.0 + Vector3(0, 2.0, 0), 2.4)
	Audio.play(&"melee_hit" if best is Character else &"melee_hit_metal", pos, -4.0, 1.0, 0.12)
	if Game.fx:
		Game.fx.impact(pos, -fwd, &"flesh" if best is Character else &"metal")
	Events.noise.emit(pos, float(data.get("noise", 4.0)), &"impact", who)
	if who.is_player:
		if Game.skills:
			Game.skills.add(&"strength", 0.012)
		if best is Character:
			Events.crime.emit(&"assault", pos, {"victim": best})
		if Game.cam and Game.cam.has_method("shake"):
			Game.cam.shake(0.25 if _melee_heavy else 0.12)

func throw_grenade(dir: Vector3) -> bool:
	var gid: StringName = &"grenade"
	if not inv.has(gid) or inv.reserve(gid) <= 0 or cooldown > 0.0:
		return false
	cooldown = 1.1
	if not (who.is_player and Game.cheats["infinite_ammo"]):
		inv.items[gid]["reserve"] = inv.reserve(gid) - 1
	if who.visual:
		who.visual.play_upper("Throw", 1.3)
	Audio.play(&"grenade_pin", who.global_position, -6.0)
	var from := who.eye_position() + who.forward() * 0.5 + Vector3(0, 0.1, 0)
	var v := dir.normalized() * 15.0 + Vector3(0, 4.5, 0) + who.velocity * 0.6
	Projectile.spawn("grenade", from, v.normalized(), who, v.length())
	if inv.reserve(gid) <= 0 and weapon_id == gid:
		inv.remove(gid)
	inv.changed.emit()
	return true
