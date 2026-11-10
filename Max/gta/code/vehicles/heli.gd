class_name Heli
extends Vehicle
## Arcade-realistic helicopter: rotor spool-up, collective lift along the rotor axis,
## attitude control toward commanded pitch/roll with self-levelling, pedal yaw, hover
## assistance and crash damage.  Controls: W/S pitch, A/D roll, Q/E yaw, Shift/Ctrl collective.

var rotor_speed := 0.0
var _rotor: Node3D
var _tail: Node3D
var _dust_cd := 0.0
var searchlight: SpotLight3D
var out_of_control := false

func _setup_kind() -> void:
	_rotor = part("rotor_main")
	_tail = part("rotor_tail")
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, body_height * 0.42, 0)
	angular_damp = 2.2
	linear_damp = 0.12
	var sl := part("searchlight")
	if sl == null and vid == "heli_police":
		sl = Node3D.new()
		add_child(sl)
		sl.position = Vector3(0, 0.3, -half_length * 0.5)
	if sl != null:
		searchlight = SpotLight3D.new()
		searchlight.light_energy = 14.0
		searchlight.spot_range = 90.0
		searchlight.spot_angle = 11.0
		searchlight.light_color = Color(0.92, 0.96, 1.0)
		searchlight.shadow_enabled = false
		searchlight.visible = false
		sl.add_child(searchlight)

func sit_pose() -> StringName:
	return &"sit_car"

func is_flying() -> bool:
	return rotor_speed > 0.6 and not _on_ground()

func _on_ground() -> bool:
	var hit := Game.ray(global_position + Vector3(0, 0.5, 0), global_position - Vector3(0, 0.6, 0), Phys.WORLD | Phys.VEHICLE, [get_rid()])
	return not hit.is_empty()

func _drive(delta: float) -> void:
	var has_pilot := driver() != null and driver().alive
	var want := 1.0 if (engine_on and has_pilot and health > 0.0) else 0.0
	rotor_speed = move_toward(rotor_speed, want, delta * (0.35 if want > rotor_speed else 0.22))
	rpm = rotor_speed * 0.55 + absf(in_lift) * 0.1
	if _rotor:
		_rotor.rotate_object_local(Vector3.UP, rotor_speed * 26.0 * delta)
	if _tail:
		_tail.rotate_object_local(Vector3.RIGHT, rotor_speed * 40.0 * delta)
	if rotor_speed < 0.05:
		return
	var xf := global_transform
	var up := xf.basis.y
	var flying_skill := Game.skills.level(&"flying") if (Game.skills and has_player()) else 0.5
	out_of_control = health < max_health * 0.25
	# --- collective: lift along the rotor axis, with hover assistance on the vertical speed
	var lift_cmd := in_lift
	var hover := mass * 9.8 / maxf(up.y, 0.55)
	var vy := linear_velocity.y
	var target_vy := lift_cmd * 9.0
	var f_lift := hover + (target_vy - vy) * mass * 1.6
	f_lift = clampf(f_lift, 0.0, mass * 9.8 * 2.1) * smoothstep(0.55, 1.0, rotor_speed)
	if not has_pilot:
		f_lift *= 0.6
	apply_central_force(up * f_lift)
	# --- attitude: commanded pitch / roll, self-levelling when the stick is released
	var max_tilt := deg_to_rad(31.0)
	var target_pitch := in_pitch * max_tilt        # + = nose down (W)
	var target_roll := in_roll * max_tilt * 0.9      # + = roll right (D)
	if out_of_control:
		target_roll += sin(Time.get_ticks_msec() * 0.004) * 0.5
	var fwd_flat := Vector3(-xf.basis.z.x, 0, -xf.basis.z.z).normalized()
	var right_flat := Vector3(-fwd_flat.z, 0, fwd_flat.x)
	# desired up vector tilted by the commands in the yaw-aligned frame
	var desired_up := (Vector3.UP + fwd_flat * tan(target_pitch) + right_flat * tan(target_roll)).normalized()
	var err := up.cross(desired_up)
	var turb := (1.0 - flying_skill) * 0.25
	apply_torque(err * mass * (16.0 - turb * 8.0) - angular_velocity * mass * 3.4 * Vector3(1, 0, 1).length() * 0.6)
	# --- pedals
	var yaw_rate := angular_velocity.dot(Vector3.UP)
	var want_yaw := -in_yaw * 1.5 + (2.4 if out_of_control else 0.0)
	apply_torque(Vector3.UP * (want_yaw - yaw_rate) * mass * 3.0)
	# gentle turn coordination: banking yaws the nose at speed
	var sp := linear_velocity.length()
	if sp > 6.0:
		apply_torque(Vector3.UP * (-xf.basis.x.y) * mass * -1.6 * clampf(sp / 30.0, 0.0, 1.0))
	# --- drag and top-speed limit
	var top := float(def.get("top", 50.0))
	apply_central_force(-linear_velocity * mass * (0.22 + 0.5 * clampf(sp / top, 0.0, 1.5) * clampf(sp / top, 0.0, 1.5)))
	# --- rotor wash dust near the ground / spray over water
	_dust_cd -= delta
	if _dust_cd <= 0.0 and rotor_speed > 0.7 and Game.fx:
		_dust_cd = 0.25
		var ground := Game.ray(global_position, global_position - Vector3(0, 9.0, 0), Phys.WORLD, [get_rid()])
		if not ground.is_empty():
			var gp: Vector3 = ground["position"]
			Game.fx.puff(gp + Vector3(randf_range(-3, 3), 0.2, randf_range(-3, 3)), 1.6)
		elif Game.water_depth(global_position - Vector3(0, 8.0, 0)) > 0.0:
			Game.fx.burst(&"water", Vector3(global_position.x, Terrain.SEA, global_position.z) + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), Vector3.UP, 1.5)
	if has_player() and Game.skills and not _on_ground():
		Game.skills.add(&"flying", delta * 0.0025)
		Game.stats["distance_fly"] += sp * delta
	# ditching
	if Game.water_depth(global_position + Vector3(0, 0.8, 0)) > 0.4:
		engine_on = false
		water_level = 1.0
		linear_velocity *= 0.92
