class_name Boat
extends Vehicle
## Buoyant hull: float points against the animated sea surface, stern thrust with
## vectoring, keel-like lateral resistance. Origin of boat models is at the waterline.

var _floats: Array[Vector3] = []
var _motor: Node3D
var _motor_rest := Basis.IDENTITY
var _prop: Node3D
var _steering: Node3D
var _steering_rest := Basis.IDENTITY
var _wake_cd := 0.0
var in_water_points := 0

func _setup_kind() -> void:
	var hl := half_length * 0.82
	var hw := half_width * 0.75
	var keel := -0.32
	_floats = [Vector3(-hw, keel, -hl), Vector3(hw, keel, -hl), Vector3(-hw, keel, hl), Vector3(hw, keel, hl),
		Vector3(0, keel, 0), Vector3(0, keel, -hl * 0.5), Vector3(0, keel, hl * 0.5)]
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.05, 0.15)
	angular_damp = 1.2
	linear_damp = 0.05
	_motor = part("motor")
	if _motor:
		_motor_rest = _motor.transform.basis
	_prop = part("prop")
	_steering = part("steering")
	if _steering:
		_steering_rest = _steering.transform.basis

func sit_pose() -> StringName:
	return &"sit_car"

func _drive(delta: float) -> void:
	var xf := global_transform
	var fwd := -xf.basis.z
	var right := xf.basis.x
	var world: World = Game.world
	in_water_points = 0
	var per := mass * 9.8 * 2.3 / float(_floats.size())
	for fp in _floats:
		var wp: Vector3 = xf * fp
		if world == null or not world.is_water_at(wp.x, wp.z):
			continue
		var surf := world.wave_height(wp.x, wp.z)
		var depth := surf - wp.y
		if depth <= 0.0:
			continue
		in_water_points += 1
		var sub := clampf(depth / 0.75, 0.0, 1.5)
		var v := linear_velocity + angular_velocity.cross(wp - global_position)
		var f := Vector3.UP * (per * sub - v.y * mass * 0.9 / float(_floats.size()))
		apply_force(f, wp - global_position)
	water_level = float(in_water_points) / float(_floats.size())
	var has_driver := driver() != null and driver().alive
	if in_water_points > 0:
		var v_f := linear_velocity.dot(fwd)
		var v_s := linear_velocity.dot(right)
		# hull resistance: low forward, high sideways
		apply_central_force(-fwd * v_f * absf(v_f) * mass * 0.012 - fwd * v_f * mass * 0.12)
		apply_central_force(-right * v_s * mass * 2.2)
		apply_torque(-angular_velocity * mass * 1.4)
		if has_driver and engine_on and in_water_points >= 3:
			var top := float(def.get("top", 28.0))
			var thr := in_throttle
			var curve := clampf(1.0 - absf(v_f) / top, 0.0, 1.0)
			var steer_a := -in_steer * 0.5
			var thrust_dir := fwd.rotated(xf.basis.y, -steer_a * 0.0)
			var force := float(def.get("power", 20000.0)) * thr * (0.35 + 0.65 * curve) * (1.0 if thr > 0.0 else 0.45)
			apply_force(thrust_dir * force, xf.basis * Vector3(0, -0.25, half_length * 0.55))
			# rudder / thrust vectoring: yaw torque grows with speed, still works at low speed under power
			var authority := clampf(absf(v_f) / 6.0, 0.0, 1.0) * signf(v_f) + thr * 0.5
			apply_torque(xf.basis.y * (-in_steer) * authority * mass * 5.2)
			# bank into the turn a little
			apply_torque(fwd * in_steer * clampf(absf(v_f) / top, 0.0, 1.0) * mass * 2.0)
		rpm = lerpf(rpm, clampf(0.15 + absf(in_throttle) * 0.5 + absf(v_f) / float(def.get("top", 28.0)) * 0.4, 0.0, 1.0) if engine_on and has_driver else 0.0, clampf(delta * 4.0, 0.0, 1.0))
		_wake_cd -= delta
		if absf(v_f) > 5.0 and _wake_cd <= 0.0 and Game.fx:
			_wake_cd = 0.12
			var stern := xf * marker_pos("wake", Vector3(0, 0, half_length))
			Game.fx.burst(&"water", Vector3(stern.x, world.wave_height(stern.x, stern.z), stern.z), Vector3.UP, clampf(absf(v_f) / 12.0, 0.6, 2.2))
		if has_player() and Game.skills and absf(v_f) > 8.0:
			Game.skills.add(&"driving", delta * 0.001)
	else:
		# beached: heavy friction so boats do not sledge across the city
		linear_velocity.x *= 1.0 - minf(delta * 1.5, 0.9)
		linear_velocity.z *= 1.0 - minf(delta * 1.5, 0.9)
		rpm = lerpf(rpm, 0.1 if engine_on and has_driver else 0.0, clampf(delta * 4.0, 0.0, 1.0))
	if _motor:
		_motor.transform.basis = _motor_rest * Basis(Vector3.UP, in_steer * 0.45)
	if _prop and engine_on:
		_prop.rotate_object_local(Vector3.FORWARD, (8.0 + absf(in_throttle) * 40.0) * delta)
	if _steering:
		_steering.transform.basis = _steering_rest * Basis(Vector3.FORWARD, in_steer * 1.6)
