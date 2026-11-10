class_name Heli
extends Vehicle
## Helicopters: arcade-realistic rotor lift along the body axis with attitude PD control,
## hover assist, coordinated banking turns and rotor spool-up.

var rotor := 0.0
var rotor_main: Node3D
var rotor_tail: Node3D
var dust_t := 0.0
var ai_target_vel = null


func setup(id: String) -> void:
	super.setup(id)
	rotor_main = parts.get("Rotor_Main")
	rotor_tail = parts.get("Rotor_Tail")
	angular_damp = 2.2
	linear_damp = 0.05
	center_of_mass = Vector3(0, 1.2, 0)
	crash_scale = 2.2
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	physics_material_override = pm


func _physics_process(delta: float) -> void:
	var active := engine_on and not dead and (driver != null or ai != null)
	rotor = move_toward(rotor, 1.0 if active else 0.0, delta * (0.42 if active else 0.25))
	if rotor_main:
		rotor_main.rotate_y(rotor * 34.0 * delta)
	if rotor_tail:
		rotor_tail.rotate_x(rotor * 48.0 * delta)
	speed = linear_velocity.length()
	var t := global_transform
	var up := t.basis.y
	var fwd := -t.basis.z
	var right := t.basis.x
	fwd_speed = linear_velocity.dot(fwd)
	if Sfx.has_method("engine_update"):
		Sfx.engine_update(self, rotor, absf(in_up))
	if rotor < 0.08 or dead:
		return
	var hp := clampf(health / max_health, 0.3, 1.0)
	if ai_target_vel != null:
		# simple velocity-following flight for AI pilots
		var tv: Vector3 = ai_target_vel
		var dvv := tv - linear_velocity
		apply_central_force((dvv * 1.6 + Vector3(0, 9.8, 0)) * mass)
		var want_yaw := atan2(-tv.x, -tv.z) if G.flat(tv).length() > 2.0 else rotation.y
		var flat_acc := G.flat(dvv).limit_length(6.0)
		var tb := Basis(Vector3.UP, want_yaw) * Basis.from_euler(Vector3(-clampf(G.flat(linear_velocity).length() * 0.012, 0.0, 0.3), 0, 0))
		var q := Quaternion(t.basis.orthonormalized()).slerp(Quaternion(tb), clampf(delta * 2.0, 0.0, 1.0))
		angular_velocity = Vector3.ZERO
		global_transform.basis = Basis(q)
		if flat_acc.length() > 0.0:
			pass
		return
	var lift := mass * 9.8 / maxf(up.y, 0.55) * (1.0 + in_up * 0.8) * rotor * rotor
	if absf(in_up) < 0.05:
		lift -= linear_velocity.y * mass * 1.4
	lift = clampf(lift, 0.0, mass * 9.8 * 2.2) * (0.75 + 0.25 * hp)
	apply_central_force(up * lift)
	var max_tilt := 0.48
	var pitch := asin(clampf(fwd.y, -1.0, 1.0))
	var roll_r := asin(clampf(right.y, -1.0, 1.0))
	var tp := -in_pitch * max_tilt
	var tr := -in_roll * max_tilt
	var kp := mass * 11.0
	var kd := mass * 4.0
	apply_torque(right * ((tp - pitch) * kp) - right * (angular_velocity.dot(right) * kd))
	apply_torque(-fwd * ((tr - roll_r) * kp) - fwd * (angular_velocity.dot(fwd) * kd))
	var yaw_cmd := -in_yaw * 1.5 + roll_r * clampf(speed / 14.0, 0.0, 1.0) * 1.1
	apply_torque(up * ((yaw_cmd - angular_velocity.dot(up)) * mass * 3.5))
	apply_central_force(-linear_velocity * mass * (float(def.accel) / float(def.top)) * 0.55)
	# rotor wash dust near the ground
	dust_t -= delta
	if dust_t <= 0.0 and G.fx:
		dust_t = 0.12
		var h := G.ray(t.origin, t.origin - Vector3(0, 9.0, 0), G.L_WORLD, [get_rid()])
		if not h.is_empty():
			var a := randf() * TAU
			var hp2: Vector3 = h.position
			if hp2.y < G.WATER_LEVEL:
				G.fx.splash(Vector3(hp2.x + cos(a) * 3.5, G.WATER_LEVEL, hp2.z + sin(a) * 3.5), 0.5)
			else:
				G.fx.dust(hp2 + Vector3(cos(a) * 3.5, 0.2, sin(a) * 3.5), 1, Color(0.8, 0.76, 0.66, 0.4), 1.4, 0.4)
		elif t.origin.y - G.WATER_LEVEL < 9.0:
			var a2 := randf() * TAU
			G.fx.splash(Vector3(t.origin.x + cos(a2) * 3.5, G.WATER_LEVEL, t.origin.z + sin(a2) * 3.5), 0.5)
	_soft_bounds()


func _soft_bounds() -> void:
	var p := global_position
	if absf(p.x) > 560.0 or absf(p.z) > 580.0:
		apply_central_force(Vector3(-signf(p.x) * maxf(absf(p.x) - 560.0, 0.0), 0, -signf(p.z) * maxf(absf(p.z) - 580.0, 0.0)) * mass * 0.6)
