class_name Vehicle
extends RigidBody3D
## Project-owned vehicle framework: raycast-suspension cars/bikes, buoyant boats, arcade helicopters and airplanes.
## Visuals come from Blender GLBs; handling comes from VehicleDef + upgrade state.

signal destroyed(v)

var def: VehicleDef
var model: Node3D
var wheels: Array = []
var seats: Array[Vector3] = []
var seat_users: Array = []
var driver = null                 # Player or null
var ai = null                     # DriverAI or null
var driver_rig: CharRig = null    # visual AI driver
var crew_looks: Array = []        # looks of AI passengers (police crews)
var health := 1000.0
var max_health := 1000.0
var dead := false
var drowned := false
var burning := 0.0
var owner_is_player := false
var stored_slot := -1
var parked := false

# inputs
var throttle_in := 0.0
var steer_in := 0.0
var handbrake_in := false
var pitch_in := 0.0
var roll_in := 0.0
var yaw_in := 0.0
var lift_in := 0.0
var plane_throttle := 0.0

# state
var speed := 0.0
var steer_angle := 0.0
var grounded_wheels := 0
var airborne_time := 0.0
var rotor_speed := 0.0
var lights_on := false
var siren_on := false
var glass_broken := false
var engine_rpm := 0.0
var skid := 0.0
var _prev_vel := Vector3.ZERO
var _prev_dv := 0.0
var _half := Vector3(1, 0.7, 2.2)
var _aabb := AABB()
var _com_h := 0.4
var in_water := false
var last_hit_by = null
var _despawn_t := 0.0

# upgrades / look
var mods: Dictionary = {}
var paint := Color("d8402f")
var paint2 := Color("f1eee6")
var engine_mult := 1.0
var brake_mult := 1.0
var speed_mult := 1.0
var armor_mult := 1.0
var susp_stiff := 1.0
var susp_drop := 0.0
var grip_bonus := 0.0
var bulletproof_tires := false
var turbo := 0

# nodes
var _mats: Dictionary = {}
var _parts: Dictionary = {}
var _doors: Array = []
var _door_open := 0.0
var _rotor_main: Node3D
var _rotor_tail: Node3D
var _prop: Node3D
var _head_lights: Array[SpotLight3D] = []
var _head_pos: Array[Vector3] = []
var _siren_light: OmniLight3D
var _neon_light: OmniLight3D
var _engine_audio: AudioStreamPlayer3D
var _siren_audio: AudioStreamPlayer3D
var _skid_audio: AudioStreamPlayer3D
var _smoke: GPUParticles3D
var _fire: GPUParticles3D
var _audio_t := 0.0
var _exhaust_pos := Vector3.ZERO
var _lean := 0.0
var _float_pts: Array[Vector3] = []
static var _wheel_meshes: Dictionary = {}


static func create(id: String) -> Vehicle:
	var v := Vehicle.new()
	v.setup(Data.vehicles[id])
	return v


func is_air() -> bool:
	return def.kind == "heli" or def.kind == "plane"


func is_two_wheel() -> bool:
	return def.kind == "bike" or def.kind == "bicycle"


func setup(d: VehicleDef) -> void:
	def = d
	name = "Veh_" + d.id
	mass = d.mass
	max_health = d.health
	health = max_health
	collision_layer = Game.L_VEHICLE
	collision_mask = Game.L_WORLD | Game.L_VEHICLE | Game.L_PROP
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35 if d.kind != "heli" else 0.9
	pm.bounce = 0.05
	physics_material_override = pm
	angular_damp = 0.6
	linear_damp = 0.02
	can_sleep = true
	continuous_cd = d.max_speed > 50.0
	model = Assets.inst(d.id)
	add_child(model)
	_aabb = Assets.size_of(d.id)
	_half = _aabb.size * 0.5
	_build_collision()
	_collect_nodes()
	_setup_materials()
	if d.fixed_color.a > 0.0:
		paint = d.fixed_color
	else:
		paint = Data.PAINTS[Game.rng.randi() % Data.PAINTS.size()][1]
	if d.fixed_color2.a > 0.0:
		paint2 = d.fixed_color2
	apply_mods()
	add_to_group("vehicles")
	Game.vehicles.append(self)
	tree_exiting.connect(func(): Game.vehicles.erase(self))


func _box(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	add_child(cs)


func _build_collision() -> void:
	var a := _aabb
	var c := a.position + a.size * 0.5
	match def.kind:
		"car":
			var clear := 0.3 + (def.susp_rest - 0.3) * 0.6
			var belt := a.position.y + a.size.y * 0.58
			_box(Vector3(c.x, (clear + belt) * 0.5, c.z), Vector3(a.size.x * 0.94, belt - clear, a.size.z * 0.96))
			_box(Vector3(c.x, (belt + a.end.y) * 0.5, c.z + a.size.z * 0.05), Vector3(a.size.x * 0.8, a.end.y - belt, a.size.z * 0.55))
			_com_h = clear + 0.12
			center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			center_of_mass = Vector3(0, _com_h, c.z - a.size.z * 0.03)
		"bike", "bicycle":
			_box(Vector3(0, 0.75, c.z), Vector3(0.5, 0.7, a.size.z * 0.8))
			_com_h = 0.45
			center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			center_of_mass = Vector3(0, _com_h, c.z)
		"boat":
			_box(Vector3(0, 0.25, c.z), Vector3(a.size.x * 0.9, 1.0, a.size.z * 0.92))
			center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			center_of_mass = Vector3(0, 0.0, c.z - 0.3)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_float_pts.append(Vector3(sx * a.size.x * 0.38, -0.5, c.z + sz * a.size.z * 0.36))
			angular_damp = 1.5
		"heli":
			_box(Vector3(0, 1.1, -0.4), Vector3(2.0, 2.1, 4.2))
			_box(Vector3(0, 1.8, 3.4), Vector3(0.5, 0.6, 3.6))
			center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			center_of_mass = Vector3(0, 1.0, -0.2)
			angular_damp = 1.2
		"plane":
			_box(Vector3(0, c.y, c.z), Vector3(1.4, a.size.y * 0.45, a.size.z * 0.9))
			_box(Vector3(0, c.y + 0.4 if not def.jet else c.y - 0.3, c.z - a.size.z * 0.1), Vector3(a.size.x * 0.92, 0.3, 1.8))
			center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			center_of_mass = Vector3(0, 0.9, c.z - a.size.z * 0.08)
			angular_damp = 1.0


func _collect_nodes() -> void:
	var id := def.id
	var i := 0
	while true:
		var s := Assets.find(model, "%s_seat_%d" % [id, i])
		if s == null:
			break
		seats.append(to_local_pos(s))
		i += 1
	if seats.is_empty():
		seats.append(Vector3(0, 0.6, 0))
	seat_users.resize(seats.size())
	for part in ["door_fl", "door_fr"]:
		var dn := Assets.find(model, "%s_%s" % [id, part])
		if dn:
			_doors.append(dn)
	for n in Assets.find_all(model, "_mod_"):
		n.visible = false
		var nm := String(n.name)
		var key := nm.substr(nm.find("_mod_") + 5)
		_parts[key] = n
	_rotor_main = Assets.find(model, "_rotor_main")
	_rotor_tail = Assets.find(model, "_rotor_tail")
	_prop = Assets.find(model, "_prop")
	for side in ["l", "r"]:
		var h := Assets.find(model, "%s_headlight_%s" % [id, side])
		if h:
			_head_pos.append(to_local_pos(h))
	var ex := Assets.find(model, id + "_exhaust")
	if ex:
		_exhaust_pos = to_local_pos(ex)
	# wheels
	var rest := def.susp_rest
	var wnodes := Assets.find_all(model, id + "_wheel_")
	for wn in wnodes:
		if not (wn is MeshInstance3D):
			continue
		var nm2 := String(wn.name)
		var tag := nm2.substr(nm2.find("_wheel_") + 7)
		var pos := to_local_pos(wn)
		var radius: float = absf(wn.scale.y)
		var pivot := Node3D.new()
		pivot.position = pos
		add_child(pivot)
		var spinner := Node3D.new()
		pivot.add_child(spinner)
		var keep_basis: Basis = wn.transform.basis
		wn.owner = null
		wn.get_parent().remove_child(wn)
		spinner.add_child(wn)
		wn.transform = Transform3D(keep_basis, Vector3.ZERO)
		var front := tag.begins_with("f")
		var drive := true
		if def.drive == "fwd":
			drive = front
		elif def.drive == "rwd":
			drive = not front
		if def.kind == "plane":
			drive = false
		var base := {"pos": pos, "radius": radius, "rest": rest, "steer": front, "drive": drive, "pivot": pivot, "spinner": spinner, "mesh": wn,
			"d": rest, "prev_d": rest, "ground": false, "spin": 0.0, "flat": false, "visual": true}
		if is_two_wheel():
			for sx in [-0.2, 0.2]:
				var w2 := base.duplicate()
				w2.pos = pos + Vector3(sx, 0, 0)
				w2.visual = sx < 0.0
				wheels.append(w2)
		else:
			wheels.append(base)


func to_local_pos(n: Node3D) -> Vector3:
	## Position of a model sub-node in vehicle space (model is an untransformed child).
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != self:
		if cur is Node3D:
			t = cur.transform * t
		cur = cur.get_parent()
	return t.origin


func _setup_materials() -> void:
	var names := ["M_Paint", "M_Paint2", "M_Glass", "M_Headlight", "M_Taillight", "M_Siren_R", "M_Siren_B", "M_Rim", "M_Plate", "M_TaxiSign"]
	for n in names:
		var src: Material = Assets.mat(n)
		_mats[n] = src.duplicate()
	_apply_overrides(self)
	_mats["M_Headlight"].emission_enabled = true
	_mats["M_Taillight"].emission_enabled = true
	_mats["M_Siren_R"].emission_enabled = true
	_mats["M_Siren_B"].emission_enabled = true
	_mats["M_Siren_R"].emission = Color(1, 0.1, 0.1)
	_mats["M_Siren_B"].emission = Color(0.1, 0.3, 1)
	_mats["M_Headlight"].emission_energy_multiplier = 0.15
	_mats["M_Taillight"].emission_energy_multiplier = 0.2
	_mats["M_Siren_R"].emission_energy_multiplier = 0.1
	_mats["M_Siren_B"].emission_energy_multiplier = 0.1


func _apply_overrides(n: Node) -> void:
	if n is MeshInstance3D and n.mesh:
		for si in range(n.mesh.get_surface_count()):
			var m: Material = n.mesh.surface_get_material(si)
			if m and _mats.has(m.resource_name):
				n.set_surface_override_material(si, _mats[m.resource_name])
	for c in n.get_children():
		_apply_overrides(c)


static func wheel_mesh(wname: String) -> Mesh:
	if _wheel_meshes.is_empty():
		var lib := Assets.inst("wheels_lib")
		for n in Assets.find_all(lib, "wheel_"):
			if n is MeshInstance3D:
				_wheel_meshes[String(n.name)] = n.mesh
		lib.free()
	return _wheel_meshes.get(wname, null)


# ------------------------------------------------------------------ upgrades
func mod(id: String) -> int:
	return int(mods.get(id, 0))


func apply_mods() -> void:
	engine_mult = 1.0 + 0.09 * mod("engine") + 0.18 * mod("turbo")
	turbo = mod("turbo")
	brake_mult = 1.0 + 0.15 * mod("brakes")
	speed_mult = 1.0 + 0.05 * mod("transmission") + 0.03 * mod("engine")
	armor_mult = maxf(0.3, 1.0 - 0.15 * mod("armor"))
	max_health = def.health * (1.0 + 0.2 * mod("armor"))
	bulletproof_tires = mod("tires") == 1
	susp_stiff = [1.0, 1.35, 1.6][clampi(mod("suspension"), 0, 2)]
	susp_drop = [0.0, 0.03, 0.08][clampi(mod("suspension"), 0, 2)]
	grip_bonus = [0.0, 0.05, 0.12][clampi(mod("spoiler"), 0, 2)] + 0.04 * mod("suspension")
	if mods.has("paint_color"):
		paint = mods.paint_color
	if mods.has("paint2_color"):
		paint2 = mods.paint2_color
	var fin: Array = Data.FINISHES[mods.get("finish", "gloss")]
	var mp: StandardMaterial3D = _mats["M_Paint"]
	mp.albedo_color = paint
	mp.roughness = fin[0]
	mp.metallic = fin[1]
	var mp2: StandardMaterial3D = _mats["M_Paint2"]
	mp2.albedo_color = paint2
	mp2.roughness = fin[0]
	mp2.metallic = fin[1]
	var mg: StandardMaterial3D = _mats["M_Glass"]
	mg.albedo_color.a = 0.06 if glass_broken else Data.TINTS[clampi(mod("tint"), 0, 3)][1]
	_mats["M_Rim"].albedo_color = Data.RIM_COLORS[clampi(mod("rim_color"), 0, 4)][1]
	_mats["M_Plate"].albedo_color = Data.PLATES[clampi(mod("plate"), 0, 3)][1]
	var lc: Color = Data.LIGHT_COLORS[clampi(mod("lights"), 0, 3)][0 + 1]
	_mats["M_Headlight"].emission = lc
	_mats["M_Headlight"].albedo_color = lc
	for l in _head_lights:
		l.light_color = lc
	for key in _parts:
		var base: String = key.substr(0, key.rfind("_"))
		var idx := int(key.substr(key.rfind("_") + 1))
		_parts[key].visible = mod(base) == idx or (base == "spoiler" and mod("spoiler") == idx)
	if def.kind == "car" and mods.has("rims"):
		var wm := wheel_mesh(Data.RIMS[clampi(mod("rims"), 0, 3)][1])
		if wm:
			for w in wheels:
				w.mesh.mesh = wm
		_apply_overrides(self)
	var neon := mod("neon")
	if neon > 0:
		if _neon_light == null:
			_neon_light = OmniLight3D.new()
			_neon_light.omni_range = 4.5
			_neon_light.position = Vector3(0, 0.15, 0)
			_neon_light.shadow_enabled = false
			add_child(_neon_light)
		_neon_light.light_color = [Color.WHITE, Color(0.2, 1.0, 0.9), Color(1.0, 0.3, 0.6), Color(1.0, 0.8, 0.25)][neon]
		_neon_light.light_energy = 3.0
		_neon_light.visible = true
	elif _neon_light:
		_neon_light.visible = false


func repair() -> void:
	health = max_health
	burning = 0.0
	glass_broken = false
	drowned = false
	for w in wheels:
		w.flat = false
	if _smoke:
		_smoke.emitting = false
	if _fire:
		_fire.emitting = false
	apply_mods()


# ------------------------------------------------------------------ seats
func free_seat(prefer_driver: bool = true) -> int:
	if prefer_driver and seat_users[0] == null and driver_rig == null:
		return 0
	for i in range(1, seats.size()):
		if seat_users[i] == null:
			return i
	return -1


func seat_global(i: int) -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, seats[clampi(i, 0, seats.size() - 1)])


func door_pos(i: int) -> Vector3:
	var s := seats[clampi(i, 0, seats.size() - 1)]
	var side := -1.0 if s.x <= 0.0 else 1.0
	if is_two_wheel():
		side = -1.0
	var local := Vector3(side * (_half.x + 0.75), 0.2, s.z)
	if def.kind == "boat":
		local = Vector3(side * (_half.x * 0.5), 0.9, s.z)
	return global_transform * local


func set_door(open: float) -> void:
	_door_open = open
	for i in range(_doors.size()):
		var sgn := 1.0 if i == 0 else -1.0
		_doors[i].rotation.y = -sgn * open * 1.1


func set_ai_driver(look: Dictionary) -> void:
	if driver_rig:
		driver_rig.queue_free()
	driver_rig = CharRig.new()
	add_child(driver_rig)
	driver_rig.setup(look, true)
	var s := seats[0]
	driver_rig.position = s - Vector3(0, 0.95 * driver_rig.height_scale, 0)
	if is_two_wheel():
		driver_rig.bike = 1.0
	else:
		driver_rig.sit = 1.0
	driver_rig.snap()
	driver_rig.tick(0.016)
	driver_rig.set_meta("look", look)


func remove_ai_driver() -> Dictionary:
	var look := {}
	if driver_rig:
		look = driver_rig.get_meta("look", {})
		driver_rig.queue_free()
		driver_rig = null
	ai = null
	return look


func has_occupant() -> bool:
	return driver != null or driver_rig != null


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	if parked:
		return
	if ai != null and not dead:
		ai.update(self, delta)
	if sleeping and (driver != null or ai != null):
		sleeping = false
	speed = linear_velocity.dot(-global_basis.z)
	in_water = global_position.y < Game.WATER_Y + 0.2 and City.terrain_height(global_position.x, global_position.z) < Game.WATER_Y - 0.3
	match def.kind:
		"car", "bike", "bicycle":
			_wheels_physics(delta)
			if is_two_wheel():
				_bike_balance(delta)
			if in_water and global_position.y < Game.WATER_Y - 0.5:
				if not drowned:
					drowned = true
					Sfx.play3d("splash", global_position, 0.0, 0.8)
					Fx.splash(Vector3(global_position.x, Game.WATER_Y, global_position.z), 2.0)
				apply_central_force(-linear_velocity * mass * 2.0 + Vector3.UP * mass * 6.0)
		"boat":
			_boat_physics(delta)
		"heli":
			_heli_physics(delta)
		"plane":
			_wheels_physics(delta)
			_plane_physics(delta)
	_damage_check(delta)
	if global_position.y < -40.0:
		place(Vector3(global_position.x, maxf(City.terrain_height(global_position.x, global_position.z), Game.WATER_Y) + 1.5, global_position.z), global_rotation.y)
	_prev_vel = linear_velocity
	if driver == Game.player and driver != null:
		Game.stats.distance_driven += absf(speed) * delta
		if absf(speed) > 12.0:
			Game.skill_up("flying" if is_air() else "driving", delta * 0.05)


func _process(delta: float) -> void:
	if parked:
		return
	_update_visuals(delta)
	_audio_t -= delta
	if _audio_t <= 0.0:
		_audio_t = 0.1
		_update_audio()
	if dead:
		_despawn_t += delta
		if _despawn_t > 75.0 and (Game.player == null or global_position.distance_to(Game.player.global_position) > 60.0):
			queue_free()


func engine_running() -> bool:
	return not dead and not drowned and has_occupant() and health > 0.0


func _wheels_physics(delta: float) -> void:
	var up := global_basis.y
	var fwd := -global_basis.z
	var space := get_world_3d().direct_space_state
	var n := float(wheels.size())
	var com_w := global_transform * center_of_mass
	var a_in := throttle_in
	var drive_dir := 0.0
	var brake := 0.0
	if a_in > 0.01:
		if speed < -1.5:
			brake = a_in
		else:
			drive_dir = a_in
	elif a_in < -0.01:
		if speed > 1.5:
			brake = -a_in
		else:
			drive_dir = a_in * 0.55
	if not engine_running():
		drive_dir = 0.0
		if not has_occupant() and absf(speed) < 6.0:
			brake = 0.6
	var top := def.max_speed * speed_mult * (0.75 if health < max_health * 0.25 else 1.0)
	var pw := clampf(1.0 - pow(absf(speed) / top, 2.0), 0.0, 1.0)
	if drive_dir < 0.0:
		pw = clampf(1.0 - absf(speed) / 13.0, 0.0, 1.0)
	var boost := 1.0 + (0.12 * turbo if absf(speed) > top * 0.3 else 0.0)
	var drive_wheels := 0.0
	for w in wheels:
		if w.drive:
			drive_wheels += 1.0
	var eng: float = def.engine * engine_mult * boost * drive_dir * pw / maxf(drive_wheels, 1.0)
	if def.kind == "plane":
		eng = 0.0
	var steer_max := deg_to_rad(def.steer) / (1.0 + absf(speed) * 0.05)
	var skill := Game.skill("driving") if driver == Game.player else 0.5
	steer_angle = move_toward(steer_angle, -steer_in * steer_max, delta * (2.6 + skill))
	var weather_grip: float = Game.daynight.grip_factor() if Game.daynight else 1.0
	var mu := 1.5 * def.grip * weather_grip * (1.0 + grip_bonus * clampf(absf(speed) / 30.0, 0.0, 1.0)) * (0.92 + 0.12 * skill)
	grounded_wheels = 0
	skid = 0.0
	var travel := def.susp_rest * 1.6
	var k := mass * 9.8 / (n * 0.6 * def.susp_rest) * susp_stiff
	var damp := 2.0 * 0.6 * sqrt(k * mass / n)
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = Game.L_WORLD | Game.L_PROP | Game.L_VEHICLE
	q.exclude = [get_rid()]
	for w in wheels:
		var top_l: Vector3 = w.pos + Vector3(0, def.susp_rest + susp_drop, 0)
		var o := global_transform * top_l
		var r: float = w.radius - (0.07 if w.flat else 0.0)
		q.from = o
		q.to = o - up * (travel + r)
		var hit := space.intersect_ray(q)
		w.prev_d = w.d
		if hit.is_empty():
			w.d = travel
			w.ground = false
			continue
		w.ground = true
		grounded_wheels += 1
		var d: float = clampf(o.distance_to(hit.position) - r, 0.0, travel)
		w.d = d
		var comp_vel: float = (w.prev_d - d) / delta
		var f: float = maxf(k * (travel - d) + damp * comp_vel, 0.0)
		f = minf(f, mass * 9.8 * 3.0)
		apply_force(up * f, o - global_position)
		# tyre forces
		var p: Vector3 = hit.position
		var wf := fwd
		if w.steer:
			wf = fwd.rotated(up, steer_angle)
		var nrm: Vector3 = hit.normal
		wf = (wf - nrm * wf.dot(nrm)).normalized()
		var wr := wf.cross(nrm).normalized()
		var vp := linear_velocity + angular_velocity.cross(p - com_w)
		var other = hit.collider
		if other is RigidBody3D:
			vp -= other.linear_velocity
		var v_long := vp.dot(wf)
		var v_lat := vp.dot(wr)
		var wmu := mu * (0.55 if w.flat else 1.0)
		if handbrake_in and not w.steer:
			wmu *= 0.45
		var f_lat := -v_lat * (mass / n) / delta * 0.45
		var f_long := 0.0
		if w.drive:
			f_long += eng
		var brk: float = brake * def.brake * brake_mult / n
		if handbrake_in and not w.steer:
			brk += def.brake * 0.9 / n
		if brk > 0.0:
			f_long -= signf(v_long) * minf(brk, absf(v_long) * (mass / n) / delta)
		f_long -= v_long * (mass / n) * (0.04 + (0.5 if w.flat else 0.0))
		if drive_dir == 0.0 and brake == 0.0 and def.kind != "plane":
			f_long -= v_long * (mass / n) * 0.25
		var lim := wmu * f
		var mag := sqrt(f_lat * f_lat + f_long * f_long)
		if mag > lim and mag > 0.001:
			skid = maxf(skid, clampf((mag - lim) / (lim + 1.0), 0.0, 1.0) * clampf(absf(v_lat) / 4.0 + (absf(v_long) / 8.0 if brk > 0.0 else 0.0), 0.0, 1.0))
			var s := lim / mag
			f_lat *= s
			f_long *= s
		var ap := p + up * ((com_w - p).dot(up) * 0.7)
		apply_force(wf * f_long + wr * f_lat, ap - global_position)
		w.spin += v_long / maxf(r, 0.1) * delta
	if grounded_wheels == 0:
		airborne_time += delta
	else:
		airborne_time = 0.0
	# aero
	var v := linear_velocity
	if def.kind != "plane":
		apply_central_force(-v * v.length() * 0.42 * (mass / 1400.0) * 1.2)
		if grounded_wheels > 0:
			apply_central_force(-up * speed * speed * 0.35 * (1.0 + grip_bonus * 4.0))
	engine_rpm = lerpf(engine_rpm, clampf(absf(speed) / top * 0.8 + absf(drive_dir) * 0.3, 0.0, 1.2), delta * 5.0)


func _bike_balance(delta: float) -> void:
	var up := global_basis.y
	var tgt := Vector3.UP
	var err := up.cross(tgt)
	var fwd := -global_basis.z
	var roll_err := err.dot(fwd)
	var roll_vel := angular_velocity.dot(fwd)
	apply_torque(fwd * (roll_err * 60.0 - roll_vel * 9.0) * mass * 0.3)
	_lean = lerpf(_lean, clampf(steer_angle * speed * 0.09, -0.6, 0.6), delta * 6.0)
	model.rotation.z = _lean
	if driver_rig:
		driver_rig.rotation.z = _lean


func _boat_physics(delta: float) -> void:
	var up := global_basis.y
	var fwd := -global_basis.z
	var right := global_basis.x
	var com_w := global_transform * center_of_mass
	var sub := 0
	var t := Time.get_ticks_msec() * 0.001
	for lp in _float_pts:
		var p := global_transform * lp
		var wave := sin(p.x * 0.09 + t * 0.9) * 0.06 + sin(p.z * 0.13 + t * 1.1) * 0.04
		var depth := Game.WATER_Y + wave - p.y
		if depth > 0.0 and City.terrain_height(p.x, p.z) < Game.WATER_Y:
			sub += 1
			var vp := linear_velocity + angular_velocity.cross(p - com_w)
			var f := minf(depth, 1.4) * mass * 9.8 / 4.0 * 2.2 - vp.y * mass * 0.9
			apply_force(Vector3.UP * f, p - global_position)
	in_water = sub > 0
	if sub == 0:
		return
	var wet := float(sub) / 4.0
	var thr := throttle_in if engine_running() else 0.0
	var top := def.max_speed
	var pw := clampf(1.0 - pow(absf(speed) / top, 2.0), 0.0, 1.0)
	var stern := global_transform * Vector3(0, -0.3, _half.z * 0.8)
	apply_force(fwd * def.engine * (thr if thr > 0.0 else thr * 0.4) * pw * wet, stern - global_position)
	apply_torque(up * (-steer_in) * mass * clampf(speed * 0.5, -6.0, 9.0) * wet * 0.9)
	var lat := linear_velocity.dot(right)
	apply_central_force(-right * lat * mass * 2.4 * wet)
	apply_central_force(-fwd * speed * absf(speed) * mass * 0.012 * wet - fwd * speed * mass * 0.25 * wet)
	apply_torque(-angular_velocity * mass * 1.2 * wet)
	engine_rpm = lerpf(engine_rpm, clampf(absf(speed) / top + absf(thr) * 0.4, 0.0, 1.2), delta * 4.0)
	if absf(speed) > 6.0 and Game.rng.randf() < delta * 10.0:
		Fx.splash(stern, 0.6)


func _heli_physics(delta: float) -> void:
	var want := 1.0 if engine_running() and health > max_health * 0.08 else 0.0
	rotor_speed = move_toward(rotor_speed, want, delta * (0.35 if want > 0.5 else 0.2))
	engine_rpm = rotor_speed
	if rotor_speed < 0.2:
		return
	var up := global_basis.y
	var fwd := -global_basis.z
	var right := global_basis.x
	var g := mass * 9.8
	var skill := Game.skill("flying") if driver == Game.player else 0.6
	var tilt := maxf(up.dot(Vector3.UP), 0.35)
	var lift := g / tilt * (1.0 + lift_in * 0.6)
	if absf(lift_in) < 0.05:
		lift += -linear_velocity.y * mass * 1.6
	else:
		lift += -linear_velocity.y * mass * 0.55      # caps climb / sink rate around 10 m/s
	lift = clampf(lift, 0.0, g * 2.3) * clampf((rotor_speed - 0.2) / 0.7, 0.0, 1.0)
	if rotor_speed < 0.95 and lift_in <= 0.0:
		lift = minf(lift, g * rotor_speed * 0.9)
	apply_central_force(up * lift)
	var ff := Vector3(fwd.x, 0, fwd.z).normalized()
	var rf := Vector3(right.x, 0, right.z).normalized()
	var des_up := (Vector3.UP + ff * 0.62 * pitch_in + rf * 0.62 * roll_in).normalized()
	var err := up.cross(des_up)
	var w := angular_velocity
	var w_tilt := w - up * w.dot(up)
	apply_torque((err * 16.0 - w_tilt * 5.5) * mass * (0.9 + 0.3 * skill))
	var yaw_rate := -yaw_in * 1.5
	apply_torque(up * (yaw_rate - w.dot(up)) * mass * 5.0)
	var vh := Vector3(linear_velocity.x, 0, linear_velocity.z)
	apply_central_force(-vh * vh.length() * mass * (5.9 / (def.max_speed * def.max_speed)) - vh * mass * 0.15)
	if driver == Game.player and Game.rng.randf() < delta * 2.0 * (1.0 - skill):
		apply_torque(Vector3(Game.rng.randf_range(-1, 1), 0, Game.rng.randf_range(-1, 1)) * mass * 3.0)
	# rotor wash dust
	if global_position.y - City.terrain_height(global_position.x, global_position.z) < 7.0 and Game.rng.randf() < delta * 12.0:
		var a := Game.rng.randf() * TAU
		var gp := global_position + Vector3(cos(a), 0, sin(a)) * Game.rng.randf_range(2.0, 5.0)
		gp.y = maxf(City.terrain_height(gp.x, gp.z), Game.WATER_Y) + 0.2
		Fx.dust(gp, 1.2)


func _plane_physics(delta: float) -> void:
	var up := global_basis.y
	var fwd := -global_basis.z
	var right := global_basis.x
	var run := engine_running()
	if run:
		plane_throttle = clampf(plane_throttle + throttle_in * delta * 0.55, 0.0, 1.0)
	else:
		plane_throttle = move_toward(plane_throttle, 0.0, delta * 0.3)
	engine_rpm = plane_throttle
	var fs := linear_velocity.dot(fwd)
	var to := def.takeoff_speed
	var top := def.max_speed
	var skill := Game.skill("flying") if driver == Game.player else 0.6
	apply_central_force(fwd * def.engine * plane_throttle * clampf(1.15 - fs / top, 0.0, 1.0))
	var q := clampf(fs / to, 0.0, 1.4)
	var lift_k := clampf(q * q, 0.0, 1.0)
	apply_central_force(up * mass * 9.8 * lift_k * clampf(up.dot(Vector3.UP) + 0.35, 0.0, 1.0))
	# velocity follows the nose once there is airflow
	var v := linear_velocity
	var align := 2.6 * clampf(q, 0.0, 1.0) * (1.0 if grounded_wheels == 0 else 0.3)
	apply_central_force((fwd * v.length() - v) * mass * align)
	apply_central_force(-v * v.length() * mass * (def.engine / mass) / (top * top))
	# control surfaces
	var auth := clampf(q, 0.12, 1.25) * (0.85 + 0.3 * skill)
	var lw := global_basis.inverse() * angular_velocity
	var bank := right.y
	var want := Vector3(pitch_in * 1.15 * auth, -yaw_in * 0.6 * auth + bank * 0.9 * clampf(q, 0.0, 1.0), -roll_in * 2.0 * auth)
	if absf(roll_in) < 0.05 and grounded_wheels == 0:
		want.z += -bank * 1.2
	if grounded_wheels > 0:
		want.z = 0.0
		want.y = -yaw_in * 0.9 * clampf(absf(fs) / 6.0, 0.0, 1.0)
		if q < 0.9:
			want.x = minf(want.x, 0.15)
	if q < 0.7 and grounded_wheels == 0:
		want.x -= (0.7 - q) * 1.6   # stall: nose drops
	var tq := (want - lw) * mass * 2.2
	apply_torque(global_basis * tq)
	if grounded_wheels > 0 and throttle_in < -0.1:
		apply_central_force(-fwd * signf(fs) * minf(def.brake, absf(fs) * mass * 2.0))


# ------------------------------------------------------------------ damage
func _damage_check(delta: float) -> void:
	var dv := (linear_velocity - _prev_vel).length()
	if dv > 3.2 and _prev_dv <= 3.2:
		var dmg := (dv - 2.8) * 16.0 * armor_mult * (2.2 if is_air() else 1.0)
		damage(dmg, global_position, null, true)
		Sfx.play3d("crash_big" if dv > 7.0 else "crash_small", global_position, 0.0, Game.rng.randf_range(0.85, 1.1))
		Fx.sparks(global_position + linear_velocity.normalized() * _half.z * 0.5 + Vector3.UP * 0.5, 8)
		if driver == Game.player and driver != null:
			if Game.cam:
				Game.cam.shake(clampf(dv * 0.05, 0.1, 0.7))
			Game.player.on_vehicle_crash(dv, self)
	_prev_dv = dv
	if burning > 0.0 and not dead:
		burning -= delta
		health -= delta * max_health * 0.02
		if burning <= 0.0:
			explode()
	if health <= max_health * 0.1 and burning <= 0.0 and not dead:
		burning = Game.rng.randf_range(5.0, 8.0)
		_ensure_fx()
		_fire.emitting = true
	if drowned and has_occupant() and driver_rig != null:
		remove_ai_driver()


func damage(amount: float, pos: Vector3 = Vector3.ZERO, attacker = null, collision: bool = false) -> void:
	if dead:
		return
	if driver == Game.player and driver != null and Game.flags.invuln:
		return
	if attacker != null:
		last_hit_by = attacker
	health -= amount * (1.0 if collision else armor_mult)
	if not collision and pos != Vector3.ZERO:
		var lp := to_local(pos)
		for w in wheels:
			if not bulletproof_tires and not w.flat and lp.distance_to(w.pos) < w.radius + 0.12:
				w.flat = true
				Sfx.play3d("shot_suppressed", pos, -2.0, 0.6)
		if not glass_broken and lp.y > _aabb.position.y + _aabb.size.y * 0.6 and def.kind == "car":
			glass_broken = true
			_mats["M_Glass"].albedo_color.a = 0.06
			Sfx.play3d("glass_break", pos, -2.0)
			Fx.sparks(pos, 6, Color(0.8, 0.95, 1.0))
	if health < max_health * 0.45:
		_ensure_fx()
		_smoke.emitting = true
		var pm: ParticleProcessMaterial = _smoke.process_material
		pm.color = Color(0.75, 0.75, 0.75, 0.5) if health > max_health * 0.25 else Color(0.12, 0.12, 0.12, 0.8)
	if health <= 0.0:
		health = 0.0
		if is_air() and global_position.y - City.terrain_height(global_position.x, global_position.z) > 4.0:
			burning = maxf(burning, 2.5) if burning > 0.0 else 2.5
			_ensure_fx()
			_fire.emitting = true
		else:
			explode()


func _ensure_fx() -> void:
	if _smoke != null:
		return
	var at := Vector3(0, _aabb.position.y + _aabb.size.y * 0.55, -_half.z * 0.7)
	if def.kind == "heli" or def.kind == "boat":
		at = Vector3(0, _aabb.size.y * 0.7, _half.z * 0.3)
	_smoke = Fx.make_smoke_emitter(Color(0.7, 0.7, 0.7, 0.5), 1.0)
	_smoke.position = at
	add_child(_smoke)
	_fire = Fx.make_fire_emitter(1.0)
	_fire.position = at
	add_child(_fire)
	_smoke.emitting = false
	_fire.emitting = false


func explode() -> void:
	if dead:
		return
	dead = true
	health = 0.0
	burning = 0.0
	siren_on = false
	_ensure_fx()
	_fire.emitting = true
	_smoke.emitting = true
	(_smoke.process_material as ParticleProcessMaterial).color = Color(0.08, 0.08, 0.08, 0.85)
	for k in ["M_Paint", "M_Paint2"]:
		_mats[k].albedo_color = Color(0.09, 0.08, 0.075)
		_mats[k].roughness = 0.95
		_mats[k].metallic = 0.0
	_mats["M_Glass"].albedo_color.a = 0.0
	for k in ["M_Headlight", "M_Taillight", "M_Siren_R", "M_Siren_B"]:
		_mats[k].emission_energy_multiplier = 0.0
	apply_central_impulse(Vector3.UP * mass * 5.0)
	apply_torque_impulse(Vector3(Game.rng.randf_range(-1, 1), Game.rng.randf_range(-1, 1), Game.rng.randf_range(-1, 1)) * mass * 2.0)
	var attacker = last_hit_by
	Fx.explosion(global_position + Vector3.UP * 0.6, 9.0, 240.0, attacker, self)
	if driver != null and is_instance_valid(driver):
		driver.on_vehicle_destroyed(self)
	for i in range(seat_users.size()):
		var u = seat_users[i]
		if u != null and is_instance_valid(u) and u != driver and u.has_method("on_vehicle_destroyed"):
			u.on_vehicle_destroyed(self)
	if driver_rig:
		remove_ai_driver()
	if attacker == Game.player and Game.player != null:
		Game.stats.vehicles_destroyed += 1
		Wanted.crime("destroy_police_vehicle" if def.tag == "police" else "destroy_vehicle", global_position)
	for l in _head_lights:
		l.visible = false
	if _siren_light:
		_siren_light.visible = false
	if _engine_audio:
		_engine_audio.stop()
	if _siren_audio:
		_siren_audio.stop()
	destroyed.emit(self)
	if Game.world and Game.world.emergency:
		Game.world.emergency.report_fire(global_position)
	get_tree().create_timer(14.0).timeout.connect(func():
		if is_instance_valid(self) and _fire:
			_fire.emitting = false)


# ------------------------------------------------------------------ visuals / audio
func _update_visuals(delta: float) -> void:
	for w in wheels:
		if not w.visual:
			continue
		var piv: Node3D = w.pivot
		var y: float = def.susp_rest + susp_drop - w.d - (0.06 if w.flat else 0.0)
		piv.position = Vector3(w.pos.x, w.pos.y + y, w.pos.z)
		if is_two_wheel():
			piv.position.x = 0.0
		piv.rotation.y = steer_angle if w.steer else 0.0
		w.spinner.rotation.x = -w.spin
	if _rotor_main:
		_rotor_main.rotate_y(rotor_speed * 26.0 * delta)
	if _rotor_tail:
		_rotor_tail.rotate_x(rotor_speed * 40.0 * delta)
	if _prop:
		_prop.rotate_z((plane_throttle * 40.0 + (4.0 if engine_running() else 0.0)) * delta)
	if driver_rig:
		driver_rig.steer = steer_in
		driver_rig.lod_skip = 3
		driver_rig.tick(delta)
	# lights
	var braking := throttle_in < -0.05 and speed > 1.0 or handbrake_in
	var tail := 0.2
	if lights_on:
		tail = 0.9
	if braking and not dead:
		tail = 3.0
	if dead:
		tail = 0.0
	_mats["M_Taillight"].emission_energy_multiplier = tail
	_mats["M_Headlight"].emission_energy_multiplier = (3.0 if lights_on else 0.15) if not dead else 0.0
	if siren_on and not dead:
		var ph := fmod(Time.get_ticks_msec() * 0.001 * 3.2, 1.0)
		_mats["M_Siren_R"].emission_energy_multiplier = 5.0 if ph < 0.5 else 0.1
		_mats["M_Siren_B"].emission_energy_multiplier = 5.0 if ph >= 0.5 else 0.1
		if _siren_light:
			_siren_light.light_color = Color(1, 0.15, 0.15) if ph < 0.5 else Color(0.2, 0.35, 1)
	if skid > 0.35 and grounded_wheels > 0 and absf(speed) > 4.0 and Game.rng.randf() < delta * 30.0:
		var rw := global_transform * Vector3(Game.rng.randf_range(-1, 1) * _half.x * 0.8, 0.1, _half.z * 0.6)
		Fx.dust(rw, 0.5, Color(0.85, 0.85, 0.85, 0.35))


func set_lights(on: bool) -> void:
	lights_on = on
	if on and _head_lights.is_empty() and driver == Game.player and driver != null:
		for hp in _head_pos:
			var l := SpotLight3D.new()
			l.position = hp + Vector3(0, 0, -0.1)
			l.spot_range = 42.0
			l.spot_angle = 30.0
			l.light_energy = 7.0
			l.shadow_enabled = false
			l.light_color = _mats["M_Headlight"].emission
			l.rotation.x = -0.06
			add_child(l)
			_head_lights.append(l)
	for l in _head_lights:
		l.visible = on and not dead


func set_siren(on: bool) -> void:
	if not def.siren:
		return
	siren_on = on
	if on and _siren_light == null:
		_siren_light = OmniLight3D.new()
		_siren_light.position = Vector3(0, _aabb.end.y + 0.4, 0)
		_siren_light.omni_range = 16.0
		_siren_light.light_energy = 3.5
		_siren_light.shadow_enabled = false
		add_child(_siren_light)
	if _siren_light:
		_siren_light.visible = on
	if on and _siren_audio == null:
		_siren_audio = Sfx.loop3d(self, "siren_ems" if def.tag == "ems" else "siren_loop", 110.0, -4.0)
	if _siren_audio:
		if on and not _siren_audio.playing:
			_siren_audio.play()
		elif not on:
			_siren_audio.stop()
	if not on:
		_mats["M_Siren_R"].emission_energy_multiplier = 0.1
		_mats["M_Siren_B"].emission_energy_multiplier = 0.1


func horn() -> void:
	Sfx.play3d("horn_%d" % (1 if def.mass > 2500.0 and mod("horn") == 0 else mod("horn")), global_position, 0.0, 1.0, 80.0)
	Game.noise(global_position, 25.0, "horn")


func _update_audio() -> void:
	if def.silent:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var near := cam.global_position.distance_to(global_position) < (150.0 if is_air() else 55.0)
	var run := engine_running() or (def.kind == "heli" and rotor_speed > 0.05)
	if near and run:
		if _engine_audio == null:
			var sname := "engine_loop"
			match def.kind:
				"bike":
					sname = "engine_bike_loop"
				"boat":
					sname = "boat_loop"
				"heli":
					sname = "heli_loop"
				"plane":
					sname = "jet_loop" if def.jet else "plane_loop"
				_:
					if def.mass > 2600.0:
						sname = "engine_truck_loop"
			_engine_audio = Sfx.loop3d(self, sname, 160.0 if is_air() else 60.0, -6.0)
		if not _engine_audio.playing:
			_engine_audio.play()
		var pitch := (0.55 + engine_rpm * 1.1) * def.engine_pitch
		if def.kind == "heli":
			pitch = 0.5 + rotor_speed * 0.6
		elif def.kind == "plane":
			pitch = 0.6 + plane_throttle * 0.7
		_engine_audio.pitch_scale = clampf(pitch, 0.4, 2.6)
		_engine_audio.volume_db = -9.0 + engine_rpm * 6.0 + (4.0 if is_air() else 0.0)
	elif _engine_audio and _engine_audio.playing:
		_engine_audio.stop()
	if skid > 0.4 and absf(speed) > 5.0 and near and grounded_wheels > 0:
		if _skid_audio == null:
			_skid_audio = Sfx.loop3d(self, "skid_loop", 50.0, -8.0)
		if not _skid_audio.playing:
			_skid_audio.play()
	elif _skid_audio and _skid_audio.playing:
		_skid_audio.stop()


func flip_upright() -> void:
	var yaw := global_rotation.y
	global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * 1.2)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func place(pos: Vector3, yaw: float = 0.0) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_vel = Vector3.ZERO


func save_state() -> Dictionary:
	var m := mods.duplicate()
	for k in ["paint_color", "paint2_color"]:
		if m.has(k):
			m[k] = (m[k] as Color).to_html(false)
	return {"id": def.id, "paint": paint.to_html(false), "paint2": paint2.to_html(false), "mods": m, "health": health}


func load_state(s: Dictionary) -> void:
	paint = Color(s.get("paint", "d8402f"))
	paint2 = Color(s.get("paint2", "f1eee6"))
	mods = s.get("mods", {}).duplicate()
	for k in ["paint_color", "paint2_color"]:
		if mods.has(k):
			mods[k] = Color(mods[k])
	for k in mods.keys():
		if mods[k] is float:
			mods[k] = int(mods[k])
	apply_mods()
	health = minf(float(s.get("health", max_health)), max_health)
