extends RigidBody3D
## Unified vehicle: raycast-suspension cars/trucks/bikes, buoyant boats, arcade helicopters and airplanes.

const Defs := preload("res://gta/code/core/defs.gd")

var id := "sedan"
var def: Dictionary
var inf: Dictionary
var kind := "car"            # car, bike, boat, heli, plane
var model: Node3D
var wheels: Array = []
var driver = null            # player node, NPC node, or the string "ai"
var ai: Dictionary = {}      # controller data owned by traffic/police
var owner_tag := ""          # traffic, police, parked, player, service
var npc_look: Dictionary = {}

# control inputs
var in_throttle := 0.0
var in_steer := 0.0
var in_brake := 0.0
var in_hand := false
var in_pitch := 0.0
var in_roll := 0.0
var in_yaw := 0.0
var in_lift := 0.0

var engine_on := false
var health := 1000.0
var max_health := 1000.0
var dead := false
var upgrades := {}
var st := {}                 # effective stats
var paint := Color(0.7, 0.1, 0.1)
var paint2 := Color(0.1, 0.1, 0.12)
var finish := "Gloss"
var rim_col := Color(0.72, 0.74, 0.78)
var mats := {}
var lights_on := false
var siren_on := false
var speed := 0.0
var steer_angle := 0.0
var grounded := 0
var in_sea := false
var throttle_state := 0.0    # airplanes
var rotor := 0.0
var last_vel := Vector3.ZERO
var last_attacker = null
var burn_t := -1.0
var flip_t := 0.0
var air_t := 0.0
var skid := 0.0
var stolen := false
var cop_seen_id := false
var wreck_t := 0.0
var _smoke: CPUParticles3D
var _fire: CPUParticles3D
var _eng: AudioStreamPlayer3D
var _siren: AudioStreamPlayer3D
var _horn: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _head: SpotLight3D
var _beacon: OmniLight3D
var _rot_main: Node3D
var _rot_tail: Node3D
var _prop: Node3D
var _spin := 0.0
var _half := Vector3.ONE
var _center := Vector3.ZERO
var _k := 0.0
var _c := 0.0
var _hit_cd := 0.0
var _tick := 0
var horn_on := false


func setup(vid: String, col = null) -> void:
	id = vid
	def = Defs.VEHICLES[vid]
	inf = G.info(vid)
	var mk: String = inf.get("kind", "car")
	kind = "car"
	if def.get("bike", false):
		kind = "bike"
	elif def.cat == "water":
		kind = "boat"
	elif def.cat == "air":
		kind = "heli" if vid.contains("heli") else "plane"
	model = G.model("vehicles/" + vid)
	add_child(model)
	for p in G.parts(model, "_Mod_"):
		p.visible = false
	collision_layer = G.L_VEH
	collision_mask = G.L_WORLD | G.L_VEH | G.L_PROP
	contact_monitor = true
	max_contacts_reported = 4
	mass = def.mass
	can_sleep = false
	var pm = PhysicsMaterial.new()
	pm.friction = 0.25 if kind in ["car", "bike"] else 0.6
	pm.bounce = 0.05
	physics_material_override = pm
	var mn = G.v3(inf.min)
	var mx = G.v3(inf.max)
	var boxes = []
	match kind:
		"heli":
			boxes = [[Vector3(0, 1.35, -0.3), Vector3(2.0, 2.7, 4.6)], [Vector3(0, 1.9, 3.4), Vector3(0.5, 0.6, 4.0)]]
			center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			center_of_mass = Vector3(0, 1.2, 0.0)
		"plane":
			if vid == "jet":
				boxes = [[Vector3(0, 1.5, -0.3), Vector3(1.5, 1.1, 10.4)], [Vector3(0, 1.4, 1.2), Vector3(9.0, 0.2, 3.6)]]
			else:
				boxes = [[Vector3(0, 1.5, 0.6), Vector3(1.3, 1.4, 6.6)], [Vector3(0, 2.3, -0.45), Vector3(10.0, 0.2, 1.5)]]
			center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			center_of_mass = Vector3(0, 0.9, -0.2 if vid != "jet" else 0.6)
		"boat":
			boxes = [[Vector3(0, (mn.y + 0.9) * 0.5, (mn.z + mx.z) * 0.5), Vector3(mx.x - mn.x, 0.9 - mn.y, mx.z - mn.z)]]
			center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			center_of_mass = Vector3(0, -0.1, 0)
		_:
			var wr: float = inf.get("wr", 0.33)
			var bot: float = wr * 0.85
			boxes = [[Vector3(0, (bot + mx.y) * 0.5, (mn.z + mx.z) * 0.5), Vector3(mx.x - mn.x - 0.1, mx.y - bot, mx.z - mn.z)]]
			center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			center_of_mass = Vector3(0, wr + 0.08, (mn.z + mx.z) * 0.5)
	for b in boxes:
		var cs = CollisionShape3D.new()
		var bs = BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.position = b[0]
		add_child(cs)
	_half = (mx - mn) * 0.5
	_center = (mx + mn) * 0.5
	# wheels
	if inf.has("wheels"):
		var wr: float = inf.get("wr", 0.33)
		var wl: Array = inf.wheels
		var names = ["_Wheel_FL", "_Wheel_FR", "_Wheel_RL", "_Wheel_RR"]
		for i in wl.size():
			var p = G.v3(wl[i])
			if kind == "bike":
				p.x = sign(p.x) * 0.3
			var front: bool = p.z < _center.z if kind != "plane" else (i == 2)
			var node: Node3D = null
			if kind == "car":
				node = G.part(model, names[i])
			elif kind == "bike":
				node = G.part(model, "_Wheel_F" if i < 2 else "_Wheel_R")
			var r: float = wr if not (kind == "plane" and i == 2 and vid == "plane") else 0.15
			if kind == "plane" and i == 2 and vid == "jet":
				r = 0.22
			wheels.append({"pos": p, "r": r, "front": front, "node": node, "comp": 0.0, "flat": false, "grounded": false, "spin": 0.0,
				"scale": node.scale if node else Vector3.ONE, "y": p.y})
		var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
		_k = mass * g / wheels.size() / 0.22
		_c = 2.0 * sqrt(_k * mass / wheels.size()) * 0.42
	_rot_main = G.part(model, "_Rotor_Main")
	_rot_tail = G.part(model, "_Rotor_Tail")
	_prop = G.part(model, "_Prop")
	max_health = def.hp
	health = max_health
	paint = col if col != null else def.get("color", Defs.TRAFFIC_COLORS[G.rng.randi() % Defs.TRAFFIC_COLORS.size()])
	if vid == "muscle":
		paint2 = Color(0.95, 0.95, 0.92) if G.rng.randf() < 0.5 else Color(0.05, 0.05, 0.06)
	_make_mats()
	apply_upgrades()
	angular_damp = 0.5 if kind in ["car", "bike"] else 1.2
	linear_damp = 0.02
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body_entered.connect(_on_body)
	add_to_group("vehicles")


func _make_mats() -> void:
	var f: Array = Defs.FINISHES[finish]
	mats["Paint"] = G.flat_mat(paint, f[0], f[1])
	mats["Paint2"] = G.flat_mat(paint2, 0.4, 0.3)
	mats["LightTail"] = G.flat_mat(Color(0.75, 0.08, 0.08), 0.3, 0.0, 0.4)
	mats["LightHead"] = G.flat_mat(Color(1.0, 0.95, 0.8), 0.3, 0.0, 0.2)
	mats["LightRev"] = G.flat_mat(Color(0.9, 0.9, 0.9), 0.3, 0.0, 0.01)
	mats["Glass"] = G.flat_mat(Color(0.1, 0.16, 0.22), 0.08, 0.6)
	mats["Plate"] = G.flat_mat(Color(0.92, 0.9, 0.8), 0.6)
	mats["Rim"] = G.flat_mat(rim_col, 0.3, 0.8)
	if def.get("siren", false) or id == "police_heli":
		mats["LightRed"] = G.flat_mat(Color(1.0, 0.1, 0.1), 0.3, 0.0, 0.3)
		mats["LightBlue"] = G.flat_mat(Color(0.15, 0.3, 1.0), 0.3, 0.0, 0.3)
	G.remat(model, mats)


func set_paint(c: Color, c2 = null, fin := "") -> void:
	paint = c
	if c2 != null:
		paint2 = c2
	if fin != "":
		finish = fin
	var f: Array = Defs.FINISHES[finish]
	mats["Paint"].albedo_color = paint
	mats["Paint"].roughness = f[0]
	mats["Paint"].metallic = f[1]
	mats["Paint2"].albedo_color = paint2


func apply_upgrades() -> void:
	st = {"engine": float(def.get("engine", 0)), "top": float(def.top), "brake": float(def.get("brake", 10000)), "grip": float(def.get("grip", 1.8)),
		"armor": float(def.get("armor", 1.0)), "sus": float(def.get("sus", 1.0)), "down": 0.0, "ride": 0.0, "bp_tires": false, "ram": 1.0, "pitch": 1.0, "horn": 1.0}
	for p in G.parts(model, "_Mod_"):
		p.visible = false
	var base_mass: float = def.mass
	for cat in upgrades:
		var opt: Array = _opt(cat, upgrades[cat])
		if opt.is_empty():
			continue
		var e: Dictionary = opt[3]
		for k in ["engine", "top", "brake", "grip", "sus"]:
			if e.has(k):
				st[k] *= e[k]
		if e.has("armor"):
			st.armor = min(st.armor, e.armor)
		if e.has("mass"):
			base_mass *= e.mass
		for k in ["down", "ride", "bp_tires", "ram", "pitch", "horn"]:
			if e.has(k):
				st[k] = e[k]
		if e.has("part"):
			var pn = G.part(model, "_" + e.part)
			if pn:
				pn.visible = true
		if e.has("wheel") and kind == "car":
			var src = G.model("vehicles/wheels")
			var wm: MeshInstance3D = G.part(src, "Wheel_" + e.wheel)
			if wm:
				for w in wheels:
					if w.node is MeshInstance3D:
						w.node.mesh = wm.mesh
			src.queue_free()
			G.remat(model, mats)
		if e.has("light"):
			mats["LightHead"].albedo_color = e.light
			mats["LightHead"].emission = e.light
			if _head:
				_head.light_color = e.light
		if e.has("tint"):
			mats["Glass"].albedo_color = Color(0.1, 0.16, 0.22).lerp(Color(0.01, 0.01, 0.012), e.tint)
		if e.has("plate"):
			mats["Plate"].albedo_color = e.plate
	mass = base_mass
	for w in wheels:
		w.y = w.pos.y - st.ride


func _opt(cat: String, oid: String) -> Array:
	for o in Defs.UPGRADES.get(cat, []):
		if o[0] == oid:
			return o
	return []


func to_dict() -> Dictionary:
	return {"id": id, "paint": paint.to_html(), "paint2": paint2.to_html(), "finish": finish, "rim": rim_col.to_html(), "upgrades": upgrades.duplicate(), "health": health}


func from_dict(d: Dictionary) -> void:
	upgrades = d.get("upgrades", {})
	rim_col = Color(d.get("rim", rim_col.to_html()))
	mats["Rim"].albedo_color = rim_col
	set_paint(Color(d.get("paint", paint.to_html())), Color(d.get("paint2", paint2.to_html())), d.get("finish", "Gloss"))
	apply_upgrades()
	health = clamp(float(d.get("health", max_health)), 100.0, max_health)


# ------------------------------------------------------------------ occupancy
func wake() -> void:
	freeze = false
	sleeping = false


func park() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	owner_tag = "parked"


func set_driver(d) -> void:
	driver = d
	wake()
	if not dead:
		engine_on = true
	if d != null and typeof(d) != TYPE_STRING and d == G.player:
		lights_on = G.is_night()
		if _head == null and kind in ["car", "bike", "heli", "plane", "boat"]:
			_head = SpotLight3D.new()
			_head.spot_range = 55.0
			_head.spot_angle = 34.0
			_head.light_energy = 0.0
			_head.light_color = mats["LightHead"].albedo_color
			_head.position = Vector3(0, max(0.7, _center.y * 0.9), -_half.z + _center.z - 0.2)
			_head.rotation.x = -0.06
			add_child(_head)


func clear_driver() -> void:
	driver = null
	in_throttle = 0.0
	in_steer = 0.0
	in_brake = 1.0 if kind in ["car", "bike"] else 0.0
	in_hand = false
	in_pitch = 0.0
	in_roll = 0.0
	in_yaw = 0.0
	in_lift = 0.0
	horn(false)
	if kind in ["car", "bike", "boat"]:
		engine_on = false


func has_ai_driver() -> bool:
	return driver != null and (typeof(driver) == TYPE_STRING or driver != G.player)


func door_pos(side := -1.0) -> Vector3:
	var z: float = inf.seat[2] if inf.has("seat") else 0.0
	if kind in ["bike"]:
		return to_global(Vector3(side * 0.9, 0.1, 0.0))
	return to_global(Vector3(side * (_half.x + 0.75), 0.1, z))


func seat_pos() -> Vector3:
	return to_global(G.v3(inf.seat)) if inf.has("seat") else global_position + Vector3(0, 1, 0)


func is_open() -> bool:
	return inf.get("open", false)


func surface(p: Vector3) -> String:
	var lp = to_local(p)
	if kind == "car" and lp.y > _center.y + 0.15:
		return "glass"
	return "metal"


func horn(on: bool) -> void:
	if on == horn_on:
		return
	horn_on = on
	if on:
		if _horn == null:
			_horn = G.audio.loop3d("horn", self, -2.0, 10.0)
		if _horn:
			_horn.pitch_scale = st.horn * (0.8 if kind == "car" and mass > 3000 else 1.0)
			_horn.play()
		if G.pop and driver == G.player:
			G.pop.honk(global_position, -global_basis.z)
	elif _horn:
		_horn.stop()


func set_siren(on: bool) -> void:
	if not (def.get("siren", false) or id == "police_heli"):
		return
	siren_on = on
	if on:
		if _siren == null and id != "police_heli":
			_siren = G.audio.loop3d("siren", self, -3.0, 14.0)
		if _beacon == null:
			_beacon = OmniLight3D.new()
			_beacon.omni_range = 13.0
			_beacon.position = Vector3(0, _half.y * 2.0 + 0.6, 0)
			add_child(_beacon)
	else:
		if _siren:
			_siren.queue_free()
			_siren = null
		if _beacon:
			_beacon.queue_free()
			_beacon = null
		if mats.has("LightRed"):
			mats["LightRed"].emission_energy_multiplier = 0.3
			mats["LightBlue"].emission_energy_multiplier = 0.3


# ------------------------------------------------------------------ damage
func damage(amount: float, from = null, pos := Vector3.ZERO, dkind := "bullet") -> void:
	if dead:
		return
	wake()
	if from != null:
		last_attacker = from
	var a = amount
	if dkind == "bullet":
		a *= 0.45
		var lp = to_local(pos)
		for w in wheels:
			if not w.flat and not st.bp_tires and kind in ["car", "bike"] and lp.distance_to(w.pos) < w.r + 0.18:
				w.flat = true
				G.audio.play3d("whoosh", pos, 0.0, 0.6)
				if driver == G.player:
					G.notify("Tyre punctured!", 2.0)
		# chance to hit an AI driver through the glass
		if has_ai_driver() and lp.y > _center.y + 0.1 and G.rng.randf() < 0.22 and kind == "car":
			_driver_killed(from)
	elif dkind.begins_with("melee"):
		a *= 0.25
	elif dkind == "explosion":
		a *= 3.5
	a *= st.get("armor", 1.0)
	if G.cheats.god and driver == G.player:
		a = 0.0
	health -= a
	if from == G.player and G.wanted:
		G.wanted.vehicle_attacked(self, a)
	if health <= 0.0:
		explode()


func _driver_killed(from) -> void:
	var d = driver
	driver = null
	ai = {}
	in_throttle = 0.0
	in_brake = 0.3
	if typeof(d) != TYPE_STRING and is_instance_valid(d) and d.has_method("damage"):
		d.damage(999.0, from, global_position, "bullet")
	if from == G.player and G.wanted:
		G.wanted.crime("murder", global_position, 2.2)
		G.stats.kills += 1
	if G.traffic:
		G.traffic.release(self)


func repair(full := true, frac := 1.0) -> void:
	health = max_health if full else min(max_health, health + max_health * frac)
	if full:
		for w in wheels:
			w.flat = false
	burn_t = -1.0
	_update_smoke()


func explode() -> void:
	if dead:
		return
	dead = true
	engine_on = false
	health = 0.0
	var p = global_position + Vector3(0, 0.8, 0)
	var att = last_attacker
	G.fx.explode(p, 9.0, 260.0, att)
	apply_central_impulse(Vector3.UP * mass * 5.0)
	apply_torque_impulse(Vector3(G.rng.randf_range(-1, 1), 0, G.rng.randf_range(-1, 1)) * mass * 2.0)
	var burnt = G.cmat("burnt", Color(0.06, 0.055, 0.05), 0.95)
	for k in mats:
		mats[k] = burnt
	G.remat(model, {"Paint": burnt, "Paint2": burnt, "Glass": burnt, "LightHead": burnt, "LightTail": burnt, "Rim": burnt, "White": burnt, "Red": burnt,
		"LightRed": burnt, "LightBlue": burnt, "Plate": burnt, "LightRev": burnt, "Yellow": burnt, "Chrome": burnt, "Steel": burnt, "Seat": burnt})
	set_siren(false)
	horn(false)
	if _eng:
		_eng.queue_free()
		_eng = null
	if driver != null:
		var d = driver
		driver = null
		if typeof(d) != TYPE_STRING and is_instance_valid(d):
			if d == G.player:
				G.player.eject_from_wreck(self)
			elif d.has_method("damage"):
				d.damage(999.0, att, p, "explosion")
	if owner_tag == "police" and att == G.player and G.wanted:
		G.wanted.crime("destroy_police", global_position, 3.0)
	if _fire == null:
		_fire = G.fx.make_smoke(self, Color(1.0, 0.5, 0.1), 0.7, true)
		_fire.position = Vector3(0, 0.9, 0)
	if _smoke == null:
		_smoke = G.fx.make_smoke(self, Color(0.1, 0.1, 0.1, 0.8), 1.0)
		_smoke.position = Vector3(0, 1.2, 0)
	wreck_t = 45.0
	if G.traffic:
		G.traffic.release(self)
	if G.extras:
		G.extras.on_explosion(p)


func _update_smoke() -> void:
	var hp = health / max_health
	if hp < 0.45 and _smoke == null and not dead:
		_smoke = G.fx.make_smoke(self, Color(0.75, 0.75, 0.75, 0.6), 0.5)
		_smoke.position = Vector3(0, _center.y + 0.2, -_half.z * 0.75 + _center.z) if kind in ["car"] else Vector3(0, 1.6, 0)
	elif hp >= 0.45 and _smoke and not dead:
		_smoke.queue_free()
		_smoke = null
	if _smoke and not dead:
		(_smoke.material_override as StandardMaterial3D).albedo_color = Color(0.75, 0.75, 0.75, 0.6).lerp(Color(0.08, 0.08, 0.08, 0.85), clamp(1.0 - hp / 0.45, 0.0, 1.0))
	if hp < 0.18 and _fire == null and not dead:
		_fire = G.fx.make_smoke(self, Color(1.0, 0.5, 0.1), 0.45, true)
		_fire.position = Vector3(0, _center.y + 0.15, -_half.z * 0.75 + _center.z) if kind in ["car"] else Vector3(0, 1.5, 0)
		burn_t = 7.0
		if driver == G.player:
			G.notify("Engine on fire — get out!", 3.0)
	elif hp >= 0.18 and _fire and not dead:
		_fire.queue_free()
		_fire = null


func _on_body(b: Node) -> void:
	if b.has_meta("knock") and last_vel.length() > 5.0:
		G.world.knock(b, last_vel * min(mass, 2000.0) * 0.12)
		linear_velocity = last_vel * 0.93
	elif b is RigidBody3D and b.is_in_group("vehicles") and b.freeze:
		b.wake()


# ------------------------------------------------------------------ simulation
func _physics_process(dt: float) -> void:
	if freeze:
		return
	if not (global_transform.is_finite() and linear_velocity.is_finite()):
		if driver != null and driver == G.player:
			G.player._exit_vehicle(true)
		queue_free()
		return
	_tick += 1
	var fwd = -global_basis.z
	speed = linear_velocity.dot(fwd)
	# impact damage
	var dv = (linear_velocity - last_vel).length()
	_hit_cd -= dt
	if dv > 4.5 and _hit_cd <= 0.0:
		_hit_cd = 0.25
		var dmg: float = (dv - 4.5) * (22.0 if kind in ["car", "bike", "boat"] else 60.0) * st.get("armor", 1.0) * st.get("ram", 1.0)
		if not (G.cheats.god and driver == G.player):
			health -= dmg
		G.audio.play3d("crash", global_position, clamp(dv - 12.0, -12.0, 4.0), G.rng.randf_range(0.8, 1.1))
		if driver == G.player:
			G.cam.shake(clamp(dv / 25.0, 0.1, 0.9))
			G.player.vehicle_impact(dv)
		if G.traffic and dv > 7.0:
			G.traffic.on_crash(self, dv)
		if health <= 0.0 and not dead:
			if kind in ["heli", "plane"] or dv > 26.0:
				explode()
			else:
				health = 1.0
	last_vel = linear_velocity
	if not dead:
		_update_smoke()
		if burn_t > 0.0:
			burn_t -= dt
			if burn_t <= 0.0:
				explode()
	else:
		wreck_t -= dt
		if wreck_t < 30.0 and _fire:
			_fire.queue_free()
			_fire = null
		if wreck_t <= 0.0 and G.dist2d(global_position, G.player_pos()) > 70.0:
			queue_free()
			return
	in_sea = G.world.is_sea(global_position.x, global_position.z)
	match kind:
		"car", "bike":
			_phys_wheels(dt, true)
			if kind == "bike":
				_bike_balance(dt)
			_water_drag(dt)
		"boat":
			_phys_boat(dt)
		"heli":
			_phys_heli(dt)
		"plane":
			_phys_wheels(dt, false)
			_phys_plane(dt)
	if abs(speed) > 3.0 and (_tick % 2 == 0):
		_run_over()
	# self-righting for stuck land vehicles
	if kind in ["car", "bike"] and not dead:
		if global_basis.y.y < 0.25 and linear_velocity.length() < 2.0:
			flip_t += dt
			if flip_t > (1.2 if has_ai_driver() else 3.0):
				flip_upright()
		else:
			flip_t = 0.0
	if global_position.y < -30.0:
		queue_free()


func flip_upright() -> void:
	flip_t = 0.0
	var yaw = global_rotation.y
	global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3(0, 1.0, 0))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _phys_wheels(dt: float, powered: bool) -> void:
	var up = global_basis.y
	var gp = global_position
	var space = get_world_3d().direct_space_state
	var steer_max: float = lerpf(0.62, 0.11, clamp(abs(speed) / 42.0, 0.0, 1.0))
	if kind == "bike":
		steer_max *= 0.75
	var target_steer: float = in_steer * steer_max if kind != "plane" else in_yaw * 0.5
	steer_angle = move_toward(steer_angle, target_steer, dt * 2.6)
	grounded = 0
	var hp = health / max_health
	var grip: float = st.grip * (G.env.grip_factor() if G.env else 1.0)
	if hp < 0.3:
		grip *= 0.85
	if driver == G.player and G.skills:
		grip *= lerpf(0.94, 1.06, G.skills.level("driving"))
	var eng: float = st.engine * (0.6 + 0.4 * clamp(hp / 0.4, 0.0, 1.0))
	var nw = wheels.size()
	var driven = 0
	for w in wheels:
		if not w.front or not def.get("rwd", false):
			driven += 1
	if def.get("rwd", false):
		driven = 2
	else:
		driven = nw
	skid = 0.0
	for w in wheels:
		var travel: float = 0.24 * st.sus
		var top: Vector3 = to_global(Vector3(w.pos.x, w.y + travel, w.pos.z))
		var maxlen: float = travel + w.r + 0.22 * st.sus
		var q = PhysicsRayQueryParameters3D.create(top, top - up * maxlen, G.L_WORLD, [get_rid()])
		var hit = space.intersect_ray(q)
		var wr: float = w.r * (0.82 if w.flat else 1.0)
		if hit.is_empty():
			w.grounded = false
			w.comp = move_toward(w.comp, 0.0, dt * 2.0)
		else:
			w.grounded = true
			grounded += 1
			var dist: float = top.distance_to(hit.position)
			var comp: float = maxlen - dist
			var pt: Vector3 = hit.position
			var vel = linear_velocity + angular_velocity.cross(pt - gp)
			var fs: float = max(0.0, _k * comp - _c * vel.dot(up))
			fs = min(fs, mass * 40.0)
			apply_force(up * fs, pt - gp)
			w.comp = comp
			var n: Vector3 = hit.normal
			var wf = -global_basis.z
			if w.front:
				wf = wf.rotated(up, steer_angle)
			wf = (wf - n * wf.dot(n)).normalized()
			var wrt = wf.cross(n).normalized()
			var vl = vel.dot(wf)
			var vs = vel.dot(wrt)
			var mu: float = grip * (0.55 if w.flat else 1.0)
			var maxf: float = mu * fs
			var lat_mu = 1.0
			var flong = 0.0
			if powered:
				var is_driven: bool = (not w.front) or not def.get("rwd", false)
				if in_hand and not w.front:
					lat_mu = 0.42
					flong = -clamp(vl * mass * 3.0, -st.brake * 0.5, st.brake * 0.5)
				else:
					if is_driven and engine_on and abs(in_throttle) > 0.01:
						var topv: float = st.top if in_throttle > 0.0 else 13.0
						var k: float = clamp(1.0 - pow(abs(speed) / topv, 2.0), 0.0, 1.0)
						if sign(in_throttle) != sign(speed) and abs(speed) > 1.0:
							k = 1.0
						flong += in_throttle * eng * 1.15 * k / driven * (1.0 if in_throttle > 0.0 else 0.5)
					if in_brake > 0.01:
						flong -= clamp(vl * mass * 4.0, -1.0, 1.0) * st.brake * in_brake / nw
					flong -= vl * mass * 0.012
			else:
				if in_brake > 0.01:
					flong -= clamp(vl * mass * 2.0, -1.0, 1.0) * mass * 6.0 * in_brake / nw
				flong -= vl * mass * 0.01
			flong = clamp(flong, -maxf * 1.15, maxf * 1.15)
			var flat_f: float = clamp(-vs * (mass / nw) * 11.0, -maxf * lat_mu, maxf * lat_mu)
			if abs(vs) > 3.5 and abs(speed) > 4.0:
				skid = max(skid, abs(vs))
			apply_force(wrt * flat_f + wf * flong, pt + up * (0.28 if kind != "bike" else 0.0) - gp)
			w.spin += vl / max(0.1, wr) * dt
		if w.node:
			var drop: float = (w.pos.y - w.y) + (0.22 * st.sus - (w.comp - 0.0)) if w.grounded else (w.pos.y - w.y) + 0.22 * st.sus
			var ly: float = w.y + travel - (maxlen - w.comp) + wr if w.grounded else w.y - 0.2 * st.sus
			w.node.position.y = ly
			var b = Basis(Vector3.UP, steer_angle if w.front else 0.0) * Basis(Vector3.RIGHT, -w.spin)
			w.node.basis = b.scaled(w.scale)
	if grounded > 0:
		apply_central_force(-up * speed * speed * (0.35 + st.down * 0.9) * mass * 0.001 * 3.0)
		air_t = 0.0
	else:
		air_t += dt
		# mild air control
		apply_torque(global_basis * Vector3(in_throttle * 0.6, 0, -in_steer * 0.6) * mass * 0.5)
	# aerodynamic drag
	apply_central_force(-linear_velocity * linear_velocity.length() * 0.42)
	if not engine_on and abs(speed) < 0.6 and grounded >= 2 and kind != "plane":
		apply_central_force(-linear_velocity * mass * 2.0)
	if skid > 5.0 and grounded > 0 and (_tick % 6 == 0) and G.dist2d(gp, G.player_pos()) < 60.0:
		G.fx.puff(to_global(Vector3(0, 0.2, _half.z * 0.6 + _center.z)))


func _bike_balance(_dt: float) -> void:
	var up = global_basis.y
	var lean: float = clamp(-steer_angle * speed * 0.06, -0.55, 0.55)
	var target = Vector3.UP.rotated(-global_basis.z.normalized(), -lean) if grounded > 0 else Vector3.UP
	var axis = up.cross(target)
	var fwd_axis = -global_basis.z
	var roll_rate = angular_velocity.dot(fwd_axis)
	apply_torque(axis * mass * 9.0 - fwd_axis * roll_rate * mass * 1.8)


func _water_drag(_dt: float) -> void:
	if in_sea and global_position.y < G.WATER_Y + 0.3:
		var sub: float = clamp((G.WATER_Y + 0.3 - global_position.y) / 1.2, 0.0, 1.0)
		apply_central_force(-linear_velocity * mass * 1.8 * sub + Vector3.UP * mass * 6.0 * sub)
		if sub > 0.7 and not dead:
			engine_on = false
			if driver == G.player and _tick % 60 == 0:
				G.notify("Vehicle is sinking!", 2.0)
			health -= 2.0


func _phys_boat(dt: float) -> void:
	var gp = global_position
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var sub_n = 0
	if in_sea:
		for sx in [-0.8, 0.8]:
			for sz in [-0.75, 0.75]:
				var lp = Vector3(sx * _half.x, -0.05, _center.z + sz * _half.z)
				var p = to_global(lp)
				var wy: float = G.WATER_Y + sin(p.x * 0.35 + Time.get_ticks_msec() * 0.0011) * 0.1
				var depth: float = wy - p.y
				if depth > 0.0:
					sub_n += 1
					var vel = linear_velocity + angular_velocity.cross(p - gp)
					var f: float = mass * g * 0.25 * clamp(depth / 0.3, 0.0, 2.6) - vel.y * mass * 0.9
					apply_force(Vector3.UP * f, p - gp)
	if sub_n > 0:
		var fwd = -global_basis.z
		var right = global_basis.x
		var lv = linear_velocity
		if engine_on:
			var k: float = clamp(1.0 - pow(abs(speed) / st.top, 2.0), 0.0, 1.0)
			apply_force(fwd * in_throttle * st.engine * k * (1.0 if in_throttle > 0 else 0.4), to_global(Vector3(0, -0.2, _center.z + _half.z * 0.8)) - gp)
			apply_torque(Vector3.UP * -in_steer * mass * (1.6 + clamp(abs(speed), 0.0, 14.0) * 0.5) * sign(speed + 0.5 * in_throttle + 0.01))
		apply_central_force(-right * lv.dot(right) * mass * 2.2 - fwd * lv.dot(fwd) * mass * 0.22)
		apply_torque(-angular_velocity * mass * 2.4)
		if abs(speed) > 6.0 and _tick % 8 == 0 and G.dist2d(gp, G.player_pos()) < 70.0:
			G.fx.burst("water", to_global(Vector3(0, 0, _center.z + _half.z)))
		if _prop:
			_spin += dt * (4.0 + abs(in_throttle) * 40.0)
			_prop.rotation.z = _spin
	else:
		apply_central_force(-linear_velocity * mass * 0.8)


func _phys_heli(dt: float) -> void:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	rotor = move_toward(rotor, 1.0 if engine_on and not dead else 0.0, dt * 0.45)
	_spin += dt * rotor * 30.0
	if _rot_main:
		_rot_main.rotation.y = _spin
	if _rot_tail:
		_rot_tail.rotation.x = _spin * 1.7
	if rotor < 0.05:
		return
	var up = global_basis.y
	var skill: float = G.skills.level("flying") if (driver == G.player and G.skills) else 0.6
	var lift_in = in_lift
	var hp = health / max_health
	var lift: float = mass * g * rotor * (1.0 + lift_in * 0.5) / max(0.62, up.y)
	if rotor < 0.9:
		lift *= rotor * 0.9
	if hp < 0.25:
		lift *= 0.9
	if global_position.y > 420.0:
		lift *= 0.6
	apply_central_force(up * lift)
	# attitude control (rate command + auto-level)
	var lw = global_basis.inverse() * angular_velocity
	var e = global_basis.get_euler()
	var want = Vector3(-in_pitch * 1.3, in_yaw * 1.5, -in_roll * 1.5)
	if abs(in_pitch) < 0.05:
		want.x += -e.x * 2.2
	if abs(in_roll) < 0.05:
		want.z += -e.z * 2.2
	# limit tilt
	if e.x < -0.75 and want.x < 0.0:
		want.x = 0.3
	if e.x > 0.6 and want.x > 0.0:
		want.x = -0.3
	if abs(e.z) > 0.75 and sign(want.z) == sign(e.z):
		want.z = -sign(e.z) * 0.3
	var wob: float = (1.0 - skill) * 0.12
	want += Vector3(sin(_spin * 0.11), 0, cos(_spin * 0.13)) * wob
	apply_torque(global_basis * _rate_torque(want - lw, 5.0) * rotor)
	var lv = linear_velocity
	apply_central_force(-Vector3(lv.x * 0.42, lv.y * 0.7, lv.z * 0.42) * mass)
	# rotor wash
	if _tick % 10 == 0 and G.dist2d(global_position, G.player_pos()) < 80.0:
		var h = G.ray(global_position, global_position - Vector3(0, 9, 0), G.L_WORLD)
		if h:
			G.fx.puff(h.position + Vector3(G.rng.randf_range(-3, 3), 0.3, G.rng.randf_range(-3, 3)))
		elif in_sea and global_position.y < G.WATER_Y + 9.0:
			G.fx.burst("water", Vector3(global_position.x + G.rng.randf_range(-3, 3), G.WATER_Y, global_position.z + G.rng.randf_range(-3, 3)))


func _phys_plane(dt: float) -> void:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var fwd = -global_basis.z
	var up = global_basis.y
	var stall: float = def.get("stall", 24.0)
	if engine_on and not dead:
		throttle_state = clamp(throttle_state + in_lift * dt * 0.7, 0.0, 1.0)
	else:
		throttle_state = move_toward(throttle_state, 0.0, dt)
	_spin += dt * (4.0 + throttle_state * 60.0) * (1.0 if engine_on else 0.0)
	if _prop:
		_prop.rotation.z = _spin
	var v = linear_velocity
	var vf = v.dot(fwd)
	var k: float = clamp(1.0 - pow(max(vf, 0.0) / st.top, 2.0), 0.0, 1.0)
	apply_central_force(fwd * st.engine * throttle_state * k)
	var q: float = clamp(vf / stall, 0.0, 1.6)
	var lift_k: float = clamp(q * q, 0.0, 1.0)
	var skill: float = G.skills.level("flying") if (driver == G.player and G.skills) else 0.6
	# base lift balances gravity at/above stall speed; angle of attack converts pitch into flight path
	apply_central_force(up * mass * g * lift_k * clamp(up.y + 0.25, 0.0, 1.0))
	var lv = global_basis.inverse() * v
	var aoa_f: float = clamp(q, 0.0, 1.0) * (0.15 if grounded >= 2 else 1.0)
	apply_central_force(global_basis * Vector3(-lv.x * 2.6, -lv.y * 3.2, 0.0) * mass * aoa_f)
	apply_central_force(-v * v.length() * (0.012 * mass / 100.0 + (0.4 if grounded > 0 and in_brake > 0.0 else 0.0)))
	var lw = global_basis.inverse() * angular_velocity
	var auth: float = clamp(q, 0.0, 1.2)
	var e = global_basis.get_euler()
	var want = Vector3(in_pitch * 0.8 * auth, in_yaw * 0.6 * auth, -in_roll * 2.0 * auth)
	if abs(e.x) > 1.0 and sign(want.x) == sign(e.x):
		want.x = 0.0
	# coordinated turn: bank yaws the nose
	want.y += e.z * 0.75 * auth
	if q < 0.85 and grounded == 0 and air_t > 0.7:
		want.x -= (0.85 - q) * 1.4          # stall: nose drops
		want.z += sin(_spin * 0.05) * (1.0 - skill) * 0.4
	if abs(in_roll) < 0.05 and grounded == 0:
		want.z += -e.z * 0.9
	if abs(in_pitch) < 0.05 and grounded == 0:
		want.x += -e.x * 0.5
	if grounded > 0:
		want.z = -e.z * 2.0
		if vf < stall * 0.9:
			want.x = min(want.x, 0.0) if e.x > 0.12 else want.x
	apply_torque(global_basis * _rate_torque(want - lw, 3.5) * clamp(q, 0.25, 1.0))


## Torque (local space) that corrects an angular-rate error using the body's real inertia.
func _rate_torque(err: Vector3, gain: float) -> Vector3:
	var inv: Vector3 = PhysicsServer3D.body_get_direct_state(get_rid()).inverse_inertia
	return Vector3(err.x / max(inv.x, 1e-6), err.y / max(inv.y, 1e-6), err.z / max(inv.z, 1e-6)) * gain


func _run_over() -> void:
	if G.dist2d(global_position, G.player_pos()) > 90.0 and driver != G.player:
		return
	var q = PhysicsShapeQueryParameters3D.new()
	var bs = BoxShape3D.new()
	bs.size = Vector3(_half.x * 2.0 + 0.3, 1.6, _half.z * 2.0 + 0.6)
	q.shape = bs
	q.transform = Transform3D(global_basis, to_global(Vector3(0, 0.9, _center.z)) + linear_velocity * 0.05)
	q.collision_mask = G.L_CHAR
	for r in get_world_3d().direct_space_state.intersect_shape(q, 6):
		var c = r.collider
		if c and c.has_method("hit_by_vehicle") and c != driver:
			c.hit_by_vehicle(self, linear_velocity)


func _process(dt: float) -> void:
	if freeze:
		return
	var cam = get_viewport().get_camera_3d()
	var near: bool = cam != null and cam.global_position.distance_squared_to(global_position) < 75.0 * 75.0
	# lights
	var night: bool = G.is_night()
	var want_l: bool = (lights_on or (has_ai_driver() and night)) and not dead
	if not dead:
		mats["LightHead"].emission_energy_multiplier = 3.5 if want_l else 0.2
		var braking: bool = in_brake > 0.1 or (in_throttle < -0.1 and speed > 1.0) or in_hand
		mats["LightTail"].emission_energy_multiplier = 4.0 if braking and engine_on else (1.2 if want_l else 0.3)
		mats["LightRev"].emission_energy_multiplier = 2.5 if (in_throttle < -0.1 and speed < -0.5 and engine_on) else 0.01
	if _head:
		_head.light_energy = 5.0 if (lights_on and not dead) else 0.0
	if siren_on and not dead:
		var ph = fmod(Time.get_ticks_msec() * 0.004, 1.0)
		if mats.has("LightRed"):
			mats["LightRed"].emission_energy_multiplier = 6.0 if ph < 0.5 else 0.2
			mats["LightBlue"].emission_energy_multiplier = 6.0 if ph >= 0.5 else 0.2
		if _beacon:
			_beacon.light_color = Color(1, 0.1, 0.1) if ph < 0.5 else Color(0.1, 0.25, 1.0)
			_beacon.light_energy = 2.5 if near else 0.0
	# engine audio
	if engine_on and near and not dead and not def.get("silent", false):
		if _eng == null:
			var nm = "engine"
			match kind:
				"bike": nm = "engine_bike"
				"boat": nm = "boat"
				"heli": nm = "heli"
				"plane": nm = "jet" if id == "jet" else "prop"
				_: nm = "engine_big" if mass > 2500 else "engine"
			_eng = G.audio.loop3d(nm, self, -7.0 if driver != G.player else -4.0, 8.0 if kind in ["car", "bike", "boat"] else 16.0)
		if _eng:
			var rpm: float = clamp(abs(speed) / max(1.0, st.top), 0.0, 1.2)
			match kind:
				"heli": _eng.pitch_scale = 0.5 + rotor * 0.55
				"plane": _eng.pitch_scale = 0.6 + throttle_state * 0.7 + rpm * 0.2
				_:
					var gear = fmod(rpm * 4.0, 1.0)
					_eng.pitch_scale = (0.55 + gear * 0.5 + rpm * 0.55 + abs(in_throttle) * 0.12) * st.pitch
	elif _eng:
		_eng.queue_free()
		_eng = null
	if skid > 5.0 and near and grounded > 0:
		if _skid == null:
			_skid = G.audio.loop3d("skid", self, -8.0, 8.0)
	elif _skid:
		_skid.queue_free()
		_skid = null
	if kind == "bike" and model:
		model.rotation.z = lerpf(model.rotation.z, clamp(-steer_angle * speed * 0.05, -0.5, 0.5) * 0.0, clamp(dt * 6.0, 0.0, 1.0))
