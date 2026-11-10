class_name Boat
extends Vehicle
## Boats: four-point buoyancy against the sea level, hull drag, stern thrust and rudder steering.

var in_water := 0
var wake_t := 0.0


func setup(id: String) -> void:
	super.setup(id)
	angular_damp = 1.4
	linear_damp = 0.08
	center_of_mass = Vector3(0, -0.15, 0.3)
	crash_scale = 0.7


func _physics_process(delta: float) -> void:
	var t := global_transform
	var fwd := -t.basis.z
	var right := t.basis.x
	speed = linear_velocity.length()
	fwd_speed = linear_velocity.dot(fwd)
	in_water = 0
	var wt: float = G.timew.wind_time if G.timew else 0.0
	var storm: float = G.timew.cur.storm if G.timew else 0.0
	for p in [Vector3(-half.x * 0.8, 0, -half.z * 0.72), Vector3(half.x * 0.8, 0, -half.z * 0.72), Vector3(-half.x * 0.8, 0, half.z * 0.8), Vector3(half.x * 0.8, 0, half.z * 0.8)]:
		var wp: Vector3 = t * p
		var wl := G.WATER_LEVEL + (sin(wp.x * 0.21 + wt * 1.3) + cos(wp.z * 0.17 + wt * 1.1)) * (0.05 + storm * 0.22)
		var depth := wl - wp.y
		if depth > -0.45:
			var sub := clampf(depth + 0.45, 0.0, 1.3)
			apply_force(Vector3.UP * (mass * 9.8 * 0.25 * sub / 0.45), wp - t.origin)
			var pv := linear_velocity + angular_velocity.cross(wp - t.origin)
			apply_force(Vector3.UP * (-pv.y * mass * 0.8), wp - t.origin)
			in_water += 1
	if in_water > 0:
		var vr := linear_velocity.dot(right)
		var top: float = float(def.top)
		apply_central_force(-right * vr * mass * 2.4 - fwd * fwd_speed * absf(fwd_speed) * mass * 0.006 - fwd * fwd_speed * mass * 0.22)
		if engine_on and not dead and absf(throttle) > 0.02:
			var fall := 1.0 - pow(clampf(absf(fwd_speed) / (top if throttle > 0.0 else top * 0.3), 0.0, 1.0), 2.0)
			apply_force(fwd * throttle * mass * float(def.accel) * fall, t.basis * Vector3(0, -0.1, half.z * 0.6))
		var steer_power := clampf(absf(fwd_speed) * 0.22 + absf(throttle) * 1.4, 0.0, 4.5) * (signf(fwd_speed) if absf(fwd_speed) > 1.0 else 1.0)
		apply_torque(Vector3.UP * (-steer * mass * steer_power * 1.6) - Vector3.UP * angular_velocity.y * mass * 1.6)
		apply_torque(fwd * (steer * mass * clampf(absf(fwd_speed) * 0.05, 0.0, 1.0) * 1.2))
		wake_t -= delta
		if absf(fwd_speed) > 3.0 and wake_t <= 0.0 and G.fx:
			wake_t = 0.07
			G.fx.splash(t * Vector3(0, 0.0, half.z * 0.95), clampf(absf(fwd_speed) / 22.0, 0.3, 1.0))
	else:
		apply_central_force(-linear_velocity * mass * 1.2)
	if parts.has("Motor"):
		(parts["Motor"] as Node3D).rotation.y = steer * 0.5
	if parts.has("SteeringWheel"):
		(parts["SteeringWheel"] as Node3D).rotation.z = -steer * 1.6
	if Sfx.has_method("engine_update"):
		Sfx.engine_update(self, clampf(absf(fwd_speed) / float(def.top) * 0.7 + absf(throttle) * 0.3, 0.0, 1.0), absf(throttle))
