class_name Airplane
extends Car
## Fixed-wing aircraft on top of the wheel physics (landing gear): thrust, lift from speed
## and angle of attack, stall, weathervane stability and speed-dependent control authority.
## Controls: Shift/Ctrl throttle, W/S pitch (W = nose down), A/D roll, Q/E rudder, Space brakes.

var throttle := 0.0
var airspeed := 0.0
var stalled := false
var _prop_node: Node3D
var _surfaces: Dictionary = {}

func wheel_names() -> Array:
	return ["wheel_n", "wheel_l", "wheel_r"]

func _setup_kind() -> void:
	def = def.duplicate()
	def["drive"] = "none"
	def["grip"] = 1.6
	def["steer"] = 28.0
	def["brake"] = float(def.get("mass", 1100.0)) * 9.0
	def["susp"] = 0.22
	super._setup_kind()
	center_of_mass = Vector3(0, body_height * 0.4, -0.1)
	angular_damp = 1.6
	linear_damp = 0.0
	_prop_node = part("prop")
	for nm: String in ["aileron_l", "aileron_r", "elevator", "rudder"]:
		var n := part(nm)
		if n:
			_surfaces[nm] = [n, n.transform.basis]
	in_handbrake = true

func sit_pose() -> StringName:
	return &"sit_car"

func is_flying() -> bool:
	return grounded_wheels == 0 and airspeed > 8.0

func _drive(delta: float) -> void:
	var has_pilot := driver() != null and driver().alive
	# throttle lever: Shift up, Ctrl down (kept when released)
	if has_pilot and engine_on:
		throttle = clampf(throttle + in_lift * delta * 0.7, 0.0, 1.0)
	else:
		throttle = move_toward(throttle, 0.0, delta * 0.5)
	# ground steering through the nose wheel uses rudder + roll input
	in_steer = clampf(in_yaw + in_roll * 0.6, -1.0, 1.0)
	in_throttle = 0.0
	in_brake = 1.0 if in_handbrake else 0.0
	var hb := in_handbrake
	in_handbrake = false
	super._drive(delta)
	in_handbrake = hb
	var xf := global_transform
	var fwd := -xf.basis.z
	var up := xf.basis.y
	var right := xf.basis.x
	var v := linear_velocity
	var v_f := v.dot(fwd)
	var v_u := v.dot(up)
	var v_s := v.dot(right)
	airspeed = v.length()
	var top := float(def.get("top", 60.0))
	var v_stall := float(def.get("stall", 21.0))
	var power := float(def.get("power", 9000.0)) * lerpf(0.5, 1.0, clampf(health / max_health, 0.0, 1.0))
	var skill := Game.skills.level(&"flying") if (Game.skills and has_player()) else 0.5
	# --- thrust and drag
	apply_central_force(fwd * power * throttle * clampf(1.15 - v_f / (top * 1.25), 0.1, 1.0))
	var kd := power / (top * top)
	if airspeed > 0.5:
		apply_central_force(-v.normalized() * kd * airspeed * airspeed * (0.85 + (0.6 if grounded_wheels > 0 else 0.0)))
	# --- lift
	var alpha := atan2(-v_u, maxf(v_f, 0.1))
	var q := clampf((v_f / (v_stall * 1.12)) * (v_f / (v_stall * 1.12)), 0.0, 2.6) if v_f > 0.0 else 0.0
	stalled = alpha > 0.3 and grounded_wheels == 0
	var cl := clampf(0.55 + 3.1 * sin(alpha), -0.6, 1.75)
	if stalled:
		cl *= 0.45
	apply_central_force(up * mass * 9.8 * q * cl)
	# sideslip resistance (fin) and weathervane stability
	apply_central_force(-right * v_s * mass * 1.6 * clampf(airspeed / v_stall, 0.0, 1.5))
	if airspeed > 4.0:
		var vdir := v.normalized()
		apply_torque(fwd.cross(vdir) * mass * 2.6 * clampf(airspeed / v_stall, 0.0, 2.0))
	# --- control surfaces: authority follows airspeed
	var auth := clampf(v_f / (v_stall * 1.1), 0.0, 1.5)
	var turb := (1.0 - skill) * 0.2
	var pitch_cmd := in_pitch + (0.35 if stalled else 0.0)          # stall drops the nose
	apply_torque(right * (-pitch_cmd) * mass * 5.2 * auth)
	apply_torque(fwd * (-in_roll) * mass * 6.4 * auth)
	apply_torque(up * (-in_yaw) * mass * 2.4 * auth)
	if turb > 0.01 and grounded_wheels == 0:
		apply_torque(Vector3(sin(Time.get_ticks_msec() * 0.003), 0, cos(Time.get_ticks_msec() * 0.0021)) * mass * turb * 1.5)
	# banked turns pull the nose around (arcade coordination)
	if grounded_wheels == 0:
		apply_torque(Vector3.UP * (-right.y) * mass * 2.2 * auth * -1.0)
		# wings-level tendency when the stick is centred
		if absf(in_roll) < 0.05:
			apply_torque(fwd * (right.y) * mass * 1.6 * auth * -1.0)
	apply_torque(-angular_velocity * mass * (0.8 + 1.6 * auth))
	rpm = lerpf(rpm, 0.2 + throttle * 0.75 if engine_on else 0.0, clampf(delta * 3.0, 0.0, 1.0))
	if _prop_node and (engine_on or throttle > 0.01):
		_prop_node.rotate_object_local(Vector3.FORWARD, (12.0 + throttle * 55.0) * delta)
	for nm in _surfaces.keys():
		var e: Array = _surfaces[nm]
		var ang := 0.0
		match nm:
			"aileron_l": ang = -in_roll * 0.4
			"aileron_r": ang = in_roll * 0.4
			"elevator": ang = in_pitch * 0.4
			"rudder": ang = 0.0
		var axis := Vector3.RIGHT if nm != "rudder" else Vector3.UP
		(e[0] as Node3D).transform.basis = (e[1] as Basis) * Basis(axis, ang if nm != "rudder" else in_yaw * 0.45)
	if has_player() and grounded_wheels == 0:
		if Game.skills:
			Game.skills.add(&"flying", delta * 0.003)
		Game.stats["distance_fly"] += airspeed * delta
