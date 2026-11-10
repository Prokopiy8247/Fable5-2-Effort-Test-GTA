class_name Vehicle
extends RigidBody3D
# Project-owned vehicle framework: raycast-suspension cars/bikes, buoyant boats,
# arcade helicopters and airplanes, damage/fire/explosion, mods, lights, sirens, audio.

const SEATS := {"motorcycle": Vector3(0, 0.36, 0.35), "bicycle": Vector3(0, 0.44, 0.28), "speedboat": Vector3(-0.5, 0.02, 0.75)}
const TRAVEL := 0.22

var id := ""
var def: Dictionary
var kind := "car"
var model: Node3D
var driver = null
var passenger = null
var ai = null
var owner_tag := "civ"
var throttle := 0.0
var steer_in := 0.0
var brake := 0.0
var handbrake := false
var pitch_in := 0.0
var roll_in := 0.0
var yaw_in := 0.0
var lift_in := 0.0
var steer := 0.0
var health := 800.0
var max_health := 800.0
var wrecked := false
var burning := false
var wheels: Array = []
var mods: Dictionary = {}
var paint := Color.WHITE
var paint2 := Color(0.1, 0.1, 0.1)
var mats: Dictionary = {}
var engine_on := false
var rotor := 0.0
var plane_throttle := 0.0
var lights_on := false
var siren_on := false
var prev_v := Vector3.ZERO
var dormant := false
var spawn_time := 0.0
var grounded := 0
var in_water := false
var air_t := 0.0
var air_from := Vector3.ZERO
var flip_t := 0.0
var fspeed := 0.0
var accel_mult := 1.0
var top_mult := 1.0
var brake_mult := 1.0
var grip_mult := 1.0
var armor_mult := 1.0
var stiff_mult := 1.0
var skill_grip := 1.0
var smoke: CPUParticles3D
var fire: CPUParticles3D
var snd: AudioStreamPlayer3D
var siren_snd: AudioStreamPlayer3D
var siren_light: OmniLight3D
var head_light: SpotLight3D
var rotor_main: Node3D
var rotor_tail: Node3D
var prop_node: Node3D
var body_mesh: Node3D
var last_hit_body = null
var horn_t := 0.0
var stolen := false
var identified := false


static func make(vid: String, color = null) -> Vehicle:
	var v := Vehicle.new()
	v.setup(vid, color)
	return v


func setup(vid: String, color) -> void:
	id = vid
	def = Defs.VEHICLES[vid]
	kind = def.kind
	mass = def.mass
	max_health = def.health
	health = max_health
	collision_layer = G.L_VEH
	collision_mask = G.L_WORLD | G.L_VEH | G.L_PROP
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = false
	body_entered.connect(_on_body)
	model = G.model("vehicles/" + def.model)
	add_child(model)
	body_mesh = G.part(model, "body")
	var L: float = def.L
	var W: float = def.W
	var H: float = def.H
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	match kind:
		"car":
			_box(Vector3(W, H - 0.4, L - 0.1), Vector3(0, 0.4 + (H - 0.4) / 2, 0))
			center_of_mass = Vector3(0, 0.32, 0)
			var wx: float = W / 2 - def.ww / 2 + 0.04
			for wd in [["wheel_fl", -wx, -def.axf, true], ["wheel_fr", wx, -def.axf, true], ["wheel_rl", -wx, -def.axr, false], ["wheel_rr", wx, -def.axr, false]]:
				wheels.append({"mount": Vector3(wd[1], def.wr, wd[2]), "r": def.wr, "node": G.part(model, wd[0]), "steer": wd[3], "len": TRAVEL, "spin": 0.0, "popped": false, "g": false})
			angular_damp = 0.8
		"bike":
			_box(Vector3(0.5, 0.75, L - 0.3), Vector3(0, 0.8, 0))
			center_of_mass = Vector3(0, 0.3, 0)
			for wd in [[-0.2, -def.axf, true], [0.2, -def.axf, true], [-0.2, -def.axr, false], [0.2, -def.axr, false]]:
				wheels.append({"mount": Vector3(wd[0], def.wr, wd[1]), "r": def.wr, "node": null, "steer": wd[2], "len": TRAVEL, "spin": 0.0, "popped": false, "g": false})
			wheels[0]["node"] = G.part(model, "wheel_f")
			wheels[2]["node"] = G.part(model, "wheel_r")
			angular_damp = 1.5
		"boat":
			_box(Vector3(W * 0.9, 0.9, L * 0.92), Vector3(0, 0.15, 0))
			center_of_mass = Vector3(0, -0.2, 0.3)
			angular_damp = 1.6
			linear_damp = 0.15
		"heli":
			_box(Vector3(1.7, 1.9, 4.0), Vector3(0, 1.25, -0.2))
			_box(Vector3(0.4, 0.5, 3.8), Vector3(0, 1.85, 3.6))
			_box(Vector3(2.0, 0.3, 3.4), Vector3(0, 0.15, -0.2))
			center_of_mass = Vector3(0, 0.9, 0)
			angular_damp = 1.2
			linear_damp = 0.3
			rotor_main = G.part(model, "rotor_main")
			rotor_tail = G.part(model, "rotor_tail")
		"plane":
			_box(Vector3(1.2, 1.2, L), Vector3(0, 1.4, 0.4))
			if id == "plane":
				_box(Vector3(10.6, 0.2, 1.5), Vector3(0, 2.15, -0.5))
			else:
				_box(Vector3(8.4, 0.2, 3.0), Vector3(0, 1.36, 1.2))
			center_of_mass = Vector3(0, 0.7, 0)
			for g in def.gear:
				wheels.append({"mount": Vector3(g[0], def.wr, -g[1]), "r": def.wr, "node": null, "steer": abs(g[0]) < 0.1, "len": TRAVEL, "spin": 0.0, "popped": false, "g": false})
			angular_damp = 1.4
			prop_node = G.part(model, "prop")
	# per-instance materials
	if color != null:
		paint = color
	elif def.has("paint"):
		paint = G.col(def.paint)
	else:
		paint = G.col(Defs.CAR_COLORS[randi() % Defs.CAR_COLORS.size()])
	paint2 = G.col(def.paint2) if def.has("paint2") else Color(0.1, 0.1, 0.11)
	mats["Paint"] = G.flat_mat(paint, 0.3, 0.3)
	mats["Paint2"] = G.flat_mat(paint2, 0.4, 0.3)
	mats["Glass"] = G.flat_mat(Color(0.09, 0.14, 0.18), 0.08, 0.4)
	mats["Rim"] = G.flat_mat(Color(0.72, 0.74, 0.77), 0.3, 0.85)
	mats["HeadLight"] = G.flat_mat(Color(1.0, 0.95, 0.8), 0.3, 0.0, 0.3)
	mats["TailLight"] = G.flat_mat(Color(0.75, 0.08, 0.08), 0.4, 0.0, 0.3)
	mats["Plate"] = G.flat_mat(Color(0.9, 0.9, 0.85), 0.6)
	if def.get("siren", false):
		mats["SirenRed"] = G.flat_mat(Color(0.85, 0.1, 0.1), 0.3, 0.0, 0.2)
		mats["SirenBlue"] = G.flat_mat(Color(0.1, 0.25, 0.9), 0.3, 0.0, 0.2)
	for mn in mats:
		G.tint(model, mn, mats[mn])
	mods = {"engine": 0, "turbo": 0, "transmission": 0, "brakes": 0, "suspension": 0, "armor": 0, "tires": 0, "downforce": 0,
		"parts": [], "finish": 0, "tint": 0, "wheel": 0, "horn": 0, "lights": 0, "plate": 0}
	apply_mods()
	# fx + audio
	smoke = G.fx.make_smoke()
	smoke.position = Vector3(0, def.H * 0.55, -L * 0.36) if kind != "heli" else Vector3(0, 2.2, 0)
	add_child(smoke)
	fire = G.fx.make_fire()
	fire.position = smoke.position
	add_child(fire)
	snd = AudioStreamPlayer3D.new()
	snd.stream = G.audio.streams[{"heli": "heli", "plane": "prop", "boat": "boat"}.get(kind, "engine")]
	snd.max_distance = 90.0 if kind in ["heli", "plane"] else 55.0
	snd.unit_size = 14.0 if kind in ["heli", "plane"] else 7.0
	snd.bus = "SFX"
	add_child(snd)
	spawn_time = G.time_now
	G.vehicles.append(self)


func _box(size: Vector3, center: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	add_child(cs)


func _exit_tree() -> void:
	G.vehicles.erase(self)


func apply_mods() -> void:
	accel_mult = 1.0 + 0.1 * mods.engine + 0.2 * mods.turbo + 0.08 * mods.transmission
	top_mult = 1.0 + 0.1 * mods.engine
	brake_mult = 1.0 + 0.25 * mods.brakes
	grip_mult = 1.0 + 0.06 * mods.suspension + (0.08 if mods.downforce > 0 else 0.0) + (0.05 if (mods.downforce > 0 and "spoiler" in mods.parts) else 0.0)
	stiff_mult = 1.0 + 0.3 * mods.suspension
	armor_mult = 1.0 - 0.18 * mods.armor
	for p in Defs.MOD_PARTS:
		var n := G.part(model, "mod_" + p)
		if n:
			n.visible = p in mods.parts
	var ft: Array = Defs.FINISH_TYPES[mods.finish]
	mats["Paint"].albedo_color = paint
	mats["Paint"].roughness = ft[1]
	mats["Paint"].metallic = ft[2]
	mats["Paint2"].albedo_color = paint2
	mats["Glass"].albedo_color = G.col(Defs.TINTS[mods.tint][1])
	mats["Rim"].albedo_color = G.col(Defs.WHEEL_COLORS[mods.wheel][1])
	mats["HeadLight"].albedo_color = G.col(Defs.LIGHT_COLORS[mods.lights][1])
	mats["HeadLight"].emission = mats["HeadLight"].albedo_color
	mats["Plate"].albedo_color = G.col(Defs.PLATES[mods.plate][1])
	if body_mesh and kind == "car":
		body_mesh.position.y = -0.04 * mods.suspension
	if head_light:
		head_light.light_color = mats["HeadLight"].albedo_color


func serialize() -> Dictionary:
	return {"id": id, "paint": [paint.r, paint.g, paint.b], "paint2": [paint2.r, paint2.g, paint2.b], "mods": mods.duplicate(true)}


static func deserialize(d: Dictionary) -> Vehicle:
	var v := Vehicle.make(d.id, Color(d.paint[0], d.paint[1], d.paint[2]))
	v.paint2 = Color(d.paint2[0], d.paint2[1], d.paint2[2])
	for k in d.mods:
		v.mods[k] = d.mods[k]
		if typeof(v.mods[k]) == TYPE_FLOAT:
			v.mods[k] = int(v.mods[k])
	v.apply_mods()
	return v


# ---------------------------------------------------------------- occupants
func set_driver(h) -> void:
	driver = h
	engine_on = h != null and not wrecked
	if h != null:
		wake()
	if h != null and h.is_player:
		if head_light == null and kind != "boat":
			head_light = SpotLight3D.new()
			head_light.spot_range = 45.0
			head_light.spot_angle = 38.0
			head_light.light_energy = 5.0
			head_light.shadow_enabled = false
			head_light.position = Vector3(0, 0.8, -def.L / 2 - 0.2)
			head_light.light_color = mats["HeadLight"].albedo_color
			add_child(head_light)
	if h == null:
		throttle = 0.0
		steer_in = 0.0
		brake = 0.0
		handbrake = kind != "heli"
		pitch_in = 0.0
		roll_in = 0.0
		yaw_in = 0.0
		lift_in = -0.4
		siren_on = false


func door_pos() -> Vector3:
	return global_transform * Vector3(-(def.W / 2 + 0.75), 0.3, 0.0)


func seat_transform() -> Transform3D:
	return global_transform * Transform3D(Basis(), SEATS.get(id, Vector3(-def.W * 0.22, 0.3, 0.0)))


func wake() -> void:
	if dormant:
		dormant = false
		freeze = false


func sleep_now() -> void:
	if driver == null and ai == null and not burning:
		dormant = true
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		freeze = true


func _on_body(b: Node) -> void:
	last_hit_body = b
	if b is Vehicle:
		b.wake()


# ---------------------------------------------------------------- physics
func _physics_process(dt: float) -> void:
	if dormant:
		return
	if ai != null:
		ai.update(self, dt)
	var fwd := -global_basis.z
	fspeed = linear_velocity.dot(fwd)
	var dvv := linear_velocity - prev_v
	dvv.y *= 0.45
	var dv := dvv.length()
	if dv > 5.0 and G.time_now - spawn_time > 1.5:
		_collision(dv)
	prev_v = linear_velocity
	match kind:
		"car", "bike":
			_car(dt)
		"boat":
			_boat(dt)
		"heli":
			_heli(dt)
		"plane":
			_plane(dt)
	_common(dt)


func _suspension(dt: float, drive_total: float, brake_total: float, coast := 0.35) -> void:
	var up := global_basis.y
	var fwd := -global_basis.z
	var ds := get_world_3d().direct_space_state
	var nw := wheels.size()
	var k: float = mass * 9.8 / (nw * TRAVEL) * stiff_mult
	var c: float = 2.0 * 0.5 * sqrt(k * mass / nw)
	var wet: float = G.sky.grip() if G.sky else 1.0
	grounded = 0
	var ray_len: float = 2.0 * TRAVEL
	for w in wheels:
		var o: Vector3 = global_transform * (w.mount + Vector3(0, TRAVEL, 0))
		var q := PhysicsRayQueryParameters3D.create(o, o - up * (ray_len + w.r), G.L_WORLD | G.L_PROP | G.L_VEH)
		q.exclude = [get_rid()]
		var hit := ds.intersect_ray(q)
		w.g = not hit.is_empty()
		if hit.is_empty():
			w.len = move_toward(w.len, ray_len, dt * 3.0)
			continue
		grounded += 1
		var dist: float = o.distance_to(hit.position)
		w.len = dist - w.r
		var comp: float = (ray_len + w.r) - dist
		var rel: Vector3 = hit.position - global_position
		var pv := linear_velocity + angular_velocity.cross(rel)
		var f: float = max(0.0, k * comp - c * pv.dot(up))
		f = min(f, mass * 9.8 * 2.5)
		apply_force(up * f, rel)
		var n: Vector3 = hit.normal
		var wf := fwd.rotated(up, -steer) if w.steer else fwd
		wf = (wf - n * wf.dot(n)).normalized()
		var wr := wf.cross(n)
		var vlat := pv.dot(wr)
		var vlong := pv.dot(wf)
		var mu: float = def.get("grip", 1.0) * grip_mult * skill_grip * wet * (0.5 if w.popped else 1.0)
		if handbrake and not w.steer:
			mu *= 0.4
		var maxf: float = mu * mass * 9.8 / nw * 1.5
		var flat: float = clamp(-vlat * mass / nw / dt * 0.5, -maxf, maxf)
		var flong: float = drive_total / nw
		if brake_total > 0.0:
			flong -= sign(vlong) * min(brake_total / nw, abs(vlong) * mass / nw / dt)
		elif abs(drive_total) < 1.0:
			flong -= vlong * mass / nw * coast
		if handbrake and not w.steer:
			flong = clamp(-vlong * mass / nw / dt, -maxf, maxf)
		if w.popped:
			flong -= vlong * mass / nw * 0.6
		flong = clamp(flong, -maxf * 1.4, maxf * 1.4)
		apply_force(wr * flat + wf * flong, rel + up * 0.22)
		w.spin -= vlong / w.r * dt
	for w in wheels:
		if w.node:
			w.node.position = Vector3(w.node.position.x, w.mount.y + TRAVEL - w.len, w.node.position.z)
			w.node.rotation = Vector3(w.spin, -steer if w.steer else 0.0, 0)


func _car(dt: float) -> void:
	var top: float = def.top * top_mult
	var max_steer: float = lerp(0.6, 0.13, clamp(abs(fspeed) / (top * 0.75), 0.0, 1.0))
	steer = move_toward(steer, steer_in * max_steer, dt * 2.8)
	var drive := 0.0
	var brk: float = brake * 14.0 * mass * brake_mult
	var acc: float = def.accel * accel_mult * mass
	if engine_on and not wrecked:
		if throttle > 0.0:
			if fspeed < -1.5:
				brk = max(brk, throttle * 14.0 * mass * brake_mult)
			else:
				drive = throttle * acc * clamp(1.0 - pow(max(fspeed, 0.0) / top, 2.0), 0.0, 1.0)
				if def.get("pedal", false) and driver != null and driver.is_player:
					G.skill_gain("stamina", dt * 0.15)
		elif throttle < 0.0:
			if fspeed > 1.5:
				brk = max(brk, -throttle * 14.0 * mass * brake_mult)
			else:
				drive = throttle * acc * 0.6 * clamp(1.0 + fspeed / (top * 0.3), 0.0, 1.0)
	var pops := 0
	for w in wheels:
		if w.popped:
			pops += 1
	drive *= 1.0 - 0.15 * pops
	if health < max_health * 0.3:
		drive *= 0.6
	_suspension(dt, drive, brk)
	var up := global_basis.y
	if grounded > 0:
		apply_central_force(-up * fspeed * fspeed * mass * 0.0025 * (1.6 if mods.downforce > 0 else 1.0))
	if kind == "bike":
		var fwd := -global_basis.z
		var roll: float = global_basis.x.y
		apply_torque(fwd * (roll * 60.0 - angular_velocity.dot(fwd) * 8.0) * mass * 0.5)
		model.rotation.z = lerp(model.rotation.z, -steer * clamp(fspeed / 12.0, 0.0, 1.0) * 1.1, dt * 6.0)
	elif grounded == 0:
		var fwd2 := -global_basis.z
		apply_torque(fwd2 * (global_basis.x.y * 4.0) * mass)
	# airtime / stunt tracking
	if grounded == 0:
		if air_t == 0.0:
			air_from = global_position
		air_t += dt
	else:
		if air_t > 1.1 and driver != null and driver.is_player and G.activities:
			G.activities.stunt_landed(self, air_t, air_from.distance_to(global_position))
		air_t = 0.0
	# flip recovery
	if up.y < 0.25 and linear_velocity.length() < 2.0 and driver != null:
		flip_t += dt
		if flip_t > 2.0:
			flip_t = 0.0
			var yaw := global_rotation.y
			global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * 1.0)
			angular_velocity = Vector3.ZERO
	else:
		flip_t = 0.0
	if global_position.y < G.WATER_Y - 0.6:
		# sinking in water: kill engine, drag
		in_water = true
		linear_velocity *= 1.0 - min(1.0, dt * 1.5)
		apply_central_force(Vector3.UP * mass * 6.0)
		if engine_on:
			engine_on = false
			if driver != null and driver.is_player:
				G.notify("Engine flooded")
	else:
		in_water = false


func _boat(dt: float) -> void:
	var L: float = def.L
	var W: float = def.W
	var sub := 0
	var b: float = mass * 9.8 / (4.0 * 0.35)
	for p in [Vector3(-W * 0.4, -0.35, -L * 0.4), Vector3(W * 0.4, -0.35, -L * 0.4), Vector3(-W * 0.4, -0.35, L * 0.4), Vector3(W * 0.4, -0.35, L * 0.4)]:
		var wp: Vector3 = global_transform * p
		var wave := sin(wp.x * 0.35 + G.time_now * 1.1) * 0.06
		var depth: float = G.WATER_Y + wave - wp.y
		if depth > 0.0:
			sub += 1
			var rel := wp - global_position
			var pv := linear_velocity + angular_velocity.cross(rel)
			apply_force(Vector3.UP * (b * min(depth, 1.2) - pv.y * mass * 0.9), rel)
	in_water = sub >= 2
	var fwd := -global_basis.z
	var right := global_basis.x
	if in_water:
		var top: float = def.top
		if engine_on and not wrecked:
			var ff := Vector3(fwd.x, 0, fwd.z).normalized()
			if throttle > 0.0:
				apply_central_force(ff * throttle * def.accel * mass * clamp(1.0 - pow(max(fspeed, 0.0) / top, 2.0), 0.0, 1.0))
			elif throttle < 0.0:
				apply_central_force(ff * throttle * def.accel * mass * 0.4)
			var auth: float = clamp(abs(fspeed) / 6.0, 0.25 if abs(throttle) > 0.1 else 0.0, 1.0) * (1.0 if fspeed >= -0.5 else -1.0)
			apply_torque(Vector3.UP * -steer_in * mass * L * 1.3 * auth)
			apply_torque(fwd * -steer_in * mass * 1.2 * clamp(fspeed / 12.0, 0.0, 1.0))
		apply_central_force(-right * linear_velocity.dot(right) * mass * 1.8)
		apply_central_force(-fwd * fspeed * mass * 0.22)
		linear_damp = 0.15
	else:
		linear_damp = 1.2 if global_position.y < 1.5 else 0.05


func _heli(dt: float) -> void:
	rotor = move_toward(rotor, 1.0 if (engine_on and not wrecked) else 0.0, dt * 0.45)
	if rotor_main:
		rotor_main.rotation.y += rotor * 28.0 * dt
	if rotor_tail:
		rotor_tail.rotation.x += rotor * 40.0 * dt
	if rotor < 0.5:
		return
	var up := global_basis.y
	var fwd := -global_basis.z
	var g: float = mass * 9.8
	var fly: float = G.skill("flying") if (driver != null and driver.is_player) else 1.0
	var lift: float = g * (1.0 + lift_in * 0.8) * clamp((rotor - 0.5) * 2.0, 0.0, 1.0)
	apply_central_force(up * lift)
	var tilt := 0.5
	var tx: float = -pitch_in * tilt
	var tz: float = -roll_in * tilt
	var cur_x := asin(clamp(fwd.y, -1.0, 1.0))
	var cur_z := asin(clamp(global_basis.x.y, -1.0, 1.0))
	var wl: Vector3 = global_basis.inverse() * angular_velocity
	var inertia: float = mass * 2.5
	var turb := Vector3.ZERO
	if driver != null and driver.is_player:
		turb = Vector3(sin(G.time_now * 1.7), 0, cos(G.time_now * 2.3)) * 0.12 * (1.0 - fly)
	var tq := Vector3((tx - cur_x) * 9.0 - wl.x * 4.5 + turb.x, (-yaw_in * 1.5 - wl.y) * 4.0, (tz - cur_z) * 9.0 - wl.z * 4.5 + turb.z) * inertia
	apply_torque(global_basis * tq)
	# forward assist so tilting translates into speed
	var hf := Vector3(up.x, 0, up.z)
	apply_central_force(hf * g * 1.6)
	var top: float = def.top
	var hv := Vector3(linear_velocity.x, 0, linear_velocity.z)
	if hv.length() > top:
		apply_central_force(-hv.normalized() * (hv.length() - top) * mass * 2.0)
	if driver != null and driver.is_player and global_position.y > G.height(global_position.x, global_position.z) + 3.0:
		G.skill_gain("flying", dt * 0.12)


func _plane(dt: float) -> void:
	var up := global_basis.y
	var fwd := -global_basis.z
	var right := global_basis.x
	var top: float = def.top
	var stall: float = def.stall
	if engine_on and not wrecked:
		plane_throttle = clamp(plane_throttle + lift_in * dt * 0.6, 0.0, 1.0)
	else:
		plane_throttle = move_toward(plane_throttle, 0.0, dt * 0.5)
	if prop_node:
		prop_node.rotation.z += (plane_throttle * 40.0 + (4.0 if engine_on else 0.0)) * dt
	apply_central_force(fwd * plane_throttle * def.accel * mass * clamp(1.0 - fspeed / top, 0.0, 1.0))
	steer = move_toward(steer, clamp(roll_in + yaw_in, -1.0, 1.0) * 0.45, dt * 2.0)
	var brk: float = (9.0 * mass) if plane_throttle < 0.05 else 0.0
	_suspension(dt, 0.0, brk, 0.02)
	var auth: float = clamp(fspeed / stall, 0.0, 1.3)
	var lift: float = mass * 9.8 * clamp(auth * auth, 0.0, 1.2)
	apply_central_force(up * lift)
	var vl: Vector3 = global_basis.inverse() * linear_velocity
	apply_central_force(-right * vl.x * mass * 2.2)
	apply_central_force(-up * vl.y * mass * 1.6 * clamp(auth, 0.0, 1.0))
	apply_central_force(-linear_velocity * mass * 0.04)
	var wl: Vector3 = global_basis.inverse() * angular_velocity
	var fly: float = G.skill("flying") if (driver != null and driver.is_player) else 1.0
	var turb := sin(G.time_now * 2.1) * 0.1 * (1.0 - fly) * auth
	var airborne := grounded == 0
	var rate := Vector3(-pitch_in * 1.3 * auth, (-yaw_in * 0.7 + right.y * 0.9) * auth, -roll_in * 2.4 * auth + turb)
	if not airborne:
		rate.z = 0.0
		rate.y = -clamp(roll_in + yaw_in, -1.0, 1.0) * 0.6 * clamp(abs(fspeed) / 6.0, 0.0, 1.0)
		rate.x = -pitch_in * 1.0 * clamp(auth - 0.75, 0.0, 1.0) * 2.0
	if airborne and abs(roll_in) < 0.1 and abs(pitch_in) < 0.1:
		rate.z += -asin(clamp(right.y, -1.0, 1.0)) * 1.2 * auth
	if airborne and fspeed < stall * 0.9:
		rate.x += -0.5 * (1.0 - auth)
	apply_torque(global_basis * ((rate - wl) * mass * 3.5 * (1.0 if airborne else 0.6)))
	if airborne and driver != null and driver.is_player:
		G.skill_gain("flying", dt * 0.15)


func _common(dt: float) -> void:
	var cam_d: float = 9999.0
	if G.cam:
		cam_d = G.cam.global_position.distance_to(global_position)
	# audio
	var running: bool = (engine_on or rotor > 0.05) and not wrecked and cam_d < snd.max_distance and not def.get("pedal", false)
	if running and not snd.playing:
		snd.play()
	elif not running and snd.playing:
		snd.stop()
	if running:
		match kind:
			"heli":
				snd.pitch_scale = 0.4 + rotor * 0.7
			"plane":
				snd.pitch_scale = 0.6 + plane_throttle * 0.9
			_:
				snd.pitch_scale = clamp(0.55 + abs(fspeed) / (def.top * top_mult) * 1.5 + abs(throttle) * 0.15, 0.4, 2.4)
	# lights
	var night: bool = G.sky.is_night() if G.sky else false
	var lit: bool = (lights_on or (night and engine_on)) and not wrecked
	mats["HeadLight"].emission_energy_multiplier = 3.0 if lit else 0.2
	var braking: bool = brake > 0.1 or (throttle < -0.1 and fspeed > 1.0) or handbrake
	mats["TailLight"].emission_energy_multiplier = 3.5 if (braking and engine_on) else (1.0 if lit else 0.2)
	if head_light:
		head_light.visible = lit and driver != null and driver.is_player
	if def.get("siren", false):
		if siren_on and not wrecked:
			var ph: bool = fmod(G.time_now * 3.0, 1.0) < 0.5
			mats["SirenRed"].emission_energy_multiplier = 5.0 if ph else 0.1
			mats["SirenBlue"].emission_energy_multiplier = 0.1 if ph else 5.0
			if siren_light == null:
				siren_light = OmniLight3D.new()
				siren_light.omni_range = 16.0
				siren_light.light_energy = 2.5
				siren_light.shadow_enabled = false
				siren_light.position = Vector3(0, def.H + 0.6, 0)
				add_child(siren_light)
				siren_snd = AudioStreamPlayer3D.new()
				siren_snd.stream = G.audio.streams["siren"]
				siren_snd.max_distance = 120.0
				siren_snd.unit_size = 12.0
				siren_snd.bus = "SFX"
				add_child(siren_snd)
			siren_light.visible = cam_d < 120.0
			siren_light.light_color = Color(1, 0.1, 0.1) if ph else Color(0.1, 0.2, 1)
			if not siren_snd.playing and kind != "heli":
				siren_snd.play()
		elif siren_light:
			siren_light.visible = false
			mats["SirenRed"].emission_energy_multiplier = 0.2
			mats["SirenBlue"].emission_energy_multiplier = 0.2
			if siren_snd.playing:
				siren_snd.stop()
	# damage states
	var hp := health / max_health
	smoke.emitting = hp < 0.4 and not wrecked and cam_d < 150.0
	if hp < 0.15 and not wrecked:
		burning = true
	fire.emitting = burning and cam_d < 150.0
	if burning and not wrecked:
		health -= max_health * 0.035 * dt
		if health <= 0.0:
			explode(null)
	# knock props, run over people
	var sp := linear_velocity.length()
	if sp > 1.5 and G.world:
		G.world.wake_props_near(global_position + linear_velocity.normalized() * def.L * 0.3, def.L * 0.5 + 0.9, sp, linear_velocity)
	if sp > 3.5 and kind != "heli":
		_run_over(sp)
	horn_t = max(0.0, horn_t - dt)
	# settle to dormant when parked
	if driver == null and ai == null and not burning and sp < 0.15 and angular_velocity.length() < 0.1 and G.time_now - spawn_time > 3.0 and kind in ["car", "bike"] and grounded >= 3 and passenger == null:
		sleep_now()


func _run_over(sp: float) -> void:
	var hl: float = def.L / 2 + 0.3
	var hw: float = def.W / 2 + 0.25
	for h in G.humanoids:
		if h.dead or h.vehicle != null or h == driver or h.state == "ragdoll" or h.state == "enter":
			continue
		var lp: Vector3 = global_transform.affine_inverse() * (h.global_position + Vector3.UP * 0.5)
		if abs(lp.x) < hw and abs(lp.z) < hl and lp.y > -0.6 and lp.y < def.H + 0.5:
			var rel: Vector3 = linear_velocity - h.velocity
			var rs := rel.length()
			if rs < 3.5:
				continue
			var dir := rel.normalized()
			h.take_damage((rs - 3.0) * 7.0, driver, h.global_position + Vector3.UP, dir, "vehicle")
			if not h.dead and rs > 5.0:
				h.knockdown(dir * min(rs, 16.0) * 0.8 + Vector3.UP * 3.5)
			if driver != null and driver.is_player and not h.is_player and G.wanted:
				G.wanted.crime("hit_ped", h.global_position, h)
			G.audio.play3d("punch", h.global_position)


func _collision(dv: float) -> void:
	var dmg := (dv - 5.0) * 9.0 * armor_mult
	health -= dmg
	G.audio.play3d("crash", global_position, clamp(dv / 20.0, 0.3, 1.0))
	if driver != null:
		if driver.is_player:
			G.cam.shake(clamp(dv / 30.0, 0.1, 0.8))
			if last_hit_body is Vehicle and is_instance_valid(last_hit_body) and G.wanted:
				if last_hit_body.owner_tag == "police":
					G.wanted.crime("ram_police", global_position)
				elif dv > 9.0 and last_hit_body.driver != null:
					G.wanted.crime("collision", global_position)
		if dv > 15.0 and (kind in ["bike", "heli", "plane"] or dv > 22.0):
			driver.take_damage((dv - 12.0) * 2.5, null, global_position, Vector3.UP, "crash")
		if kind == "bike" and dv > 11.0 and driver != null and driver.has_method("bail"):
			driver.bail(prev_v)
	if kind in ["heli", "plane"] and dv > 12.0:
		health -= dmg * 2.0
	if health <= 0.0:
		explode(null)


func take_damage(amount: float, attacker, pos: Vector3, dir: Vector3, dkind: String) -> void:
	if wrecked:
		return
	wake()
	amount *= armor_mult
	if dkind == "bullet":
		amount *= 0.6
		if mods.tires == 0:
			var lp := to_local(pos)
			for w in wheels:
				if lp.distance_to(w.mount) < 0.5 and not w.popped:
					w.popped = true
					G.audio.play3d("pop", pos)
	elif dkind == "melee":
		amount *= 0.25
	health -= amount
	if attacker != null and attacker == G.player and G.wanted and owner_tag == "police":
		G.wanted.crime("attack_police", global_position)
	if driver != null and not driver.is_player and driver.has_method("vehicle_attacked"):
		driver.vehicle_attacked(attacker)
	if health <= 0.0:
		explode(attacker)


func repair() -> void:
	health = max_health
	burning = false
	for w in wheels:
		w.popped = false


func horn() -> void:
	if horn_t <= 0.0 and not def.get("pedal", false):
		horn_t = 0.5
		G.audio.play3d("horn", global_position, 1.0, Defs.HORNS[mods.horn][1])
		G.emit_danger(global_position, 14.0, driver, "horn")


func explode(attacker) -> void:
	if wrecked:
		return
	wrecked = true
	burning = true
	engine_on = false
	health = 0.0
	var pos := global_position + Vector3.UP * 0.8
	if attacker == null and driver != null:
		attacker = null
	for h in [driver, passenger]:
		if h != null and is_instance_valid(h):
			if h.has_method("force_exit"):
				h.force_exit()
			h.take_damage(500.0, attacker, pos, Vector3.UP, "explosion")
	driver = null
	passenger = null
	ai = null
	var char_mat := G.flat_mat(Color(0.05, 0.05, 0.05), 0.95)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = char_mat
	G.explode(pos, 9.0, 240.0, attacker)
	if attacker == G.player and owner_tag == "police" and G.wanted:
		G.wanted.crime("destroy_police", pos)
	apply_central_impulse(Vector3.UP * mass * 5.0)
	apply_torque_impulse(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * mass * 3.0)
	if G.traffic:
		G.traffic.report_fire(pos)
	get_tree().create_timer(14.0).timeout.connect(func():
		if is_instance_valid(self):
			burning = false)
	get_tree().create_timer(45.0).timeout.connect(func():
		if is_instance_valid(self) and driver == null:
			queue_free())
