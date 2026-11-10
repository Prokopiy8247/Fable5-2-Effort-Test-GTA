class_name Car
extends Vehicle
## Ray-cast wheel vehicle (cars, vans, trucks and - with balance assistance - two-wheelers).
## Project-owned physics: spring/damper suspension per wheel, impulse-limited lateral grip
## inside a friction circle, engine/brake forces, hand-brake drifts, downforce, tyre
## punctures and damage-dependent handling.

var wheels: Array = []           # per wheel dictionary, see _add_wheel
var two_wheel := false
var steer_angle := 0.0
var grounded_wheels := 0
var skid := 0.0
var airborne_time := 0.0
var air_start := Vector3.ZERO
var upside_time := 0.0
var _k := 30000.0
var _c := 3000.0
var _rest := 0.26
var _fork: Node3D
var _fork_rest := Basis.IDENTITY
var _steering: Node3D
var _steering_rest := Basis.IDENTITY
var _crank: Node3D
var _gear := 0
var _skid_fx_cd := 0.0
var grip_scale := 1.0            # set by weather
var grip_scale_mod := 1.0        # set by suspension upgrades
var power_scale := 1.0
var brake_scale := 1.0
var downforce := 0.0

func _setup_kind() -> void:
	two_wheel = kind == &"bike"
	_rest = float(def.get("susp", 0.26))
	downforce = float(def.get("downforce", 0.6))
	var names := wheel_names()
	var dims: Vector3 = def.get("dims", Vector3(4.6, 1.9, 1.5))
	var r_default := 0.34 if not two_wheel else 0.31
	for i in names.size():
		var n := part(names[i])
		var pos: Vector3
		var radius := r_default
		if n != null:
			pos = _rel_xform(n).origin
			if n is MeshInstance3D:
				var bb := (n as MeshInstance3D).get_aabb()
				radius = maxf(bb.size.y, bb.size.z) * 0.5
		else:
			if two_wheel:
				pos = Vector3(0, r_default, -dims.x * 0.33 if i == 0 else dims.x * 0.33)
			else:
				pos = Vector3((-1.0 if i % 2 == 0 else 1.0) * (dims.y * 0.5 - 0.15), r_default, -dims.x * 0.3 if i < 2 else dims.x * 0.3)
		var front := (i == 0) if (two_wheel or names.size() == 3) else (i < 2)
		if names.size() == 3 and n == null:
			pos = [Vector3(0, r_default, -dims.x * 0.3), Vector3(-1.3, r_default, 0.3), Vector3(1.3, r_default, 0.3)][i]
		_add_wheel(n, pos, radius, front)
	var per := mass * 9.8 / float(wheels.size())
	_k = per / (_rest * 0.42) * float(def.get("stiff", 1.0))
	_c = 2.0 * 0.42 * sqrt(_k * mass / float(wheels.size()))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	var com_y := 0.32 if not two_wheel else 0.4
	if body_height > 2.0:
		com_y = 0.55
	center_of_mass = Vector3(0, com_y, 0.0)
	angular_damp = 0.6 if not two_wheel else 1.4
	_fork = part("fork")
	if _fork:
		_fork_rest = _fork.transform.basis
	_steering = part("steering")
	if _steering:
		_steering_rest = _steering.transform.basis
	_crank = part("crank")
	in_handbrake = true

func wheel_names() -> Array:
	return ["wheel_f", "wheel_r"] if two_wheel else ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]

func _add_wheel(node: Node3D, pos: Vector3, radius: float, front: bool) -> void:
	var drive_type := String(def.get("drive", "fwd"))
	var driven := drive_type == "awd" or (drive_type == "fwd" and front) or (drive_type == "rwd" and not front)
	var sag := _rest * 0.42
	wheels.append({
		"node": node, "rest": node.transform if node != null else Transform3D.IDENTITY,
		"attach": pos + Vector3(0, _rest - sag, 0), "radius": radius, "front": front, "drive": driven,
		"comp": sag, "grounded": false, "spin": 0.0, "punctured": false, "slip": 0.0, "pos": pos,
		"sign": 1.0 if (node == null or node.transform.basis.x.x >= 0.0) else -1.0,
		"contact": Vector3.ZERO, "normal": Vector3.UP, "len": _rest - sag,
	})

func _on_repair() -> void:
	for w in wheels:
		w["punctured"] = false

func _on_bullet(local: Vector3, _amount: float) -> void:
	if bool(def.get("bulletproof_tires", false)) or bool(mods.get("bp_tires", false)):
		return
	for w in wheels:
		var wp: Vector3 = w["pos"]
		if not w["punctured"] and local.distance_to(wp) < float(w["radius"]) * 1.25:
			w["punctured"] = true
			Audio.play(&"tire_pop", global_transform * wp, -3.0)
			if Game.fx:
				Game.fx.puff(global_transform * wp)
			break

func max_steer() -> float:
	var s := absf(speed)
	var base := deg_to_rad(float(def.get("steer", 34.0))) * lerpf(1.0, 0.24, clampf(s / 42.0, 0.0, 1.0))
	if two_wheel and s > 2.0 and wheels.size() >= 2:
		# two-wheelers: never ask for more cornering than the tyres can hold (they would spin out)
		var wb := absf((wheels[0]["pos"] as Vector3).z - (wheels[1]["pos"] as Vector3).z)
		var mu := float(def.get("grip", 2.0)) * grip_scale * 9.8 * 1.1
		base = minf(base, atan(wb * mu / (s * s)))
	return base

func _drive(delta: float) -> void:
	var xf := global_transform
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var right := xf.basis.x
	var space := get_world_3d().direct_space_state
	var has_driver := driver() != null and driver().alive
	var throttle := in_throttle if (engine_on and has_driver) else 0.0
	var brake := in_brake
	var handbrake := in_handbrake or not has_driver
	# W/S semantics: reverse input brakes first, then reverses
	var drive_cmd := 0.0
	if throttle > 0.02:
		if speed < -1.5:
			brake = maxf(brake, throttle)
		else:
			drive_cmd = throttle
	elif throttle < -0.02:
		if speed > 1.5:
			brake = maxf(brake, -throttle)
		else:
			drive_cmd = throttle * 0.55
	# steering with speed-sensitive lock and smoothing
	var target_steer := -in_steer * max_steer()
	var rate := lerpf(4.5, 2.4, clampf(absf(speed) / 30.0, 0.0, 1.0))
	steer_angle = move_toward(steer_angle, target_steer, rate * delta * maxf(0.35, absf(target_steer - steer_angle) * 2.5))
	var top := float(def.get("top", 45.0))
	var hp := clampf(health / max_health, 0.0, 1.0)
	var power := float(def.get("power", 9000.0)) * power_scale * lerpf(0.55, 1.0, hp)
	if Game.weather:
		grip_scale = Game.weather.grip_factor()
	var mu := float(def.get("grip", 1.9)) * grip_scale * grip_scale_mod
	var n_wheels := float(wheels.size())
	var n_drive := 0.0
	for w in wheels:
		if w["drive"]:
			n_drive += 1.0
	grounded_wheels = 0
	var slip_sum := 0.0
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = Phys.WORLD | Phys.PROP
	ray.exclude = [get_rid()]
	for w in wheels:
		var attach: Vector3 = xf * (w["attach"] as Vector3)
		var radius: float = float(w["radius"]) * (0.86 if w["punctured"] else 1.0)
		var reach := _rest + radius
		ray.from = attach
		ray.to = attach - up * reach
		var hit := space.intersect_ray(ray)
		var prev_comp: float = w["comp"]
		if hit.is_empty():
			w["grounded"] = false
			w["comp"] = move_toward(prev_comp, 0.0, delta * 2.0)
			w["len"] = _rest - float(w["comp"])
			w["spin"] = float(w["spin"]) + (speed / maxf(radius, 0.1)) * delta
			w["slip"] = 0.0
			continue
		grounded_wheels += 1
		var hit_pos: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		var dist := attach.distance_to(hit_pos)
		var comp := clampf(reach - dist, 0.0, _rest)
		var comp_rate := (comp - prev_comp) / delta
		w["comp"] = comp
		w["grounded"] = true
		w["contact"] = hit_pos
		w["normal"] = normal
		w["len"] = dist - radius
		var f_susp := maxf(0.0, _k * comp + _c * comp_rate)
		f_susp = minf(f_susp, mass * 9.8 * 3.2)
		var r_arm := hit_pos - global_position
		apply_force(normal * f_susp, r_arm)
		# --- tyre forces in the contact plane
		var steer_here := steer_angle if w["front"] else 0.0
		var wf := fwd.rotated(up, steer_here)
		wf = (wf - normal * wf.dot(normal)).normalized()
		var ws := wf.cross(normal).normalized()
		var v := linear_velocity + angular_velocity.cross(hit_pos - (global_position + xf.basis * center_of_mass))
		var v_f := v.dot(wf)
		var v_s := v.dot(ws)
		var m_w := mass / n_wheels
		var grip_here := mu * (0.55 if w["punctured"] else 1.0)
		var f_long := 0.0
		if w["drive"] and absf(drive_cmd) > 0.01:
			var curve := clampf(1.0 - pow(absf(speed) / top, 2.2), 0.0, 1.0) if drive_cmd * speed >= 0.0 else 1.0
			if drive_cmd < 0.0 and speed < -top * 0.28:
				curve = 0.0
			f_long += drive_cmd * power * (0.45 + 0.55 * curve) * curve / maxf(n_drive, 1.0)
		var locked = handbrake and not w["front"]
		if two_wheel and handbrake:
			locked = not w["front"]
		if brake > 0.01:
			var fb := float(def.get("brake", 16000.0)) * brake_scale * brake / n_wheels
			f_long -= signf(v_f) * minf(fb, absf(v_f) * m_w / delta)
		if locked:
			f_long = -signf(v_f) * minf(grip_here * f_susp * 0.85, absf(v_f) * m_w / delta)
			grip_here *= 0.42
		elif absf(drive_cmd) < 0.01 and brake < 0.01:
			f_long -= v_f * m_w * 0.12      # engine braking / rolling resistance
		if w["punctured"]:
			f_long -= v_f * m_w * 0.5
		var f_lat := -v_s * m_w / delta * 0.62
		var limit := grip_here * f_susp
		var mag := sqrt(f_long * f_long + f_lat * f_lat)
		var slip := 0.0
		if mag > limit and mag > 0.001:
			slip = clampf((mag - limit) / maxf(limit, 1.0), 0.0, 1.0)
			var s := limit / mag
			# keep a little more longitudinal force so cars still accelerate while sliding
			f_lat *= s
			f_long *= lerpf(s, 1.0, 0.25) if not locked else s
		w["slip"] = slip if absf(v_s) > 1.5 or locked else 0.0
		slip_sum += float(w["slip"])
		# apply above the contact patch to limit body roll (arcade stability)
		var apply_at := r_arm + up * (radius * 0.9 + (0.25 if not two_wheel else 0.1))
		apply_force(wf * f_long + ws * f_lat, apply_at)
		w["spin"] = float(w["spin"]) + ((0.0 if locked else v_f) / maxf(radius, 0.1)) * delta
	skid = slip_sum / n_wheels
	# --- aero
	var sp := linear_velocity.length()
	if sp > 0.5:
		var drag := power / (top * top) * 0.55
		apply_central_force(-linear_velocity.normalized() * drag * sp * sp * 0.35)
		if grounded_wheels > 0:
			apply_central_force(-up * downforce * sp * sp * (1.0 + 0.4 * float(mods.get("spoiler_level", 0))))
	# --- stability helpers
	if two_wheel:
		_balance(delta, up, fwd, right)
	if grounded_wheels == 0:
		if airborne_time == 0.0:
			air_start = global_position
		airborne_time += delta
		# mild air control
		apply_torque(right * in_throttle * mass * 1.2 + fwd * in_steer * mass * 0.9)
	else:
		if airborne_time > 0.6:
			_landed(airborne_time)
		airborne_time = 0.0
		# anti-roll: resist roll rate when cornering hard
		var roll_rate := angular_velocity.dot(fwd)
		apply_torque(-fwd * roll_rate * mass * (0.9 if not two_wheel else 0.0))
	if up.y < 0.25 and sp < 2.5:
		upside_time += delta
		if upside_time > 1.6 and has_driver:
			# self-righting so a flipped car is not the end of the fun
			var axis := up.cross(Vector3.UP)
			if axis.length() < 0.05:
				axis = fwd
			apply_torque(axis.normalized() * mass * 9.0)
			apply_central_force(Vector3.UP * mass * 3.5)
	else:
		upside_time = 0.0
	# --- water: cars sink slowly
	var depth := Game.water_depth(global_position + Vector3(0, 0.3, 0))
	water_level = clampf(depth / maxf(body_height, 0.5), 0.0, 2.0) if depth > 0.0 else 0.0
	if water_level > 0.0:
		apply_central_force(Vector3.UP * mass * 9.8 * minf(water_level, 1.0) * 0.82)
		linear_velocity *= 1.0 - minf(delta * 1.6 * minf(water_level, 1.0), 0.5)
		angular_velocity *= 1.0 - minf(delta * 2.0, 0.5)
	# --- engine "rpm" with fake gears for audio
	var gears := 5.0
	var norm := clampf(absf(speed) / top, 0.0, 1.0)
	var g := minf(floor(norm * gears), gears - 1.0)
	var in_gear := norm * gears - g
	rpm = lerpf(rpm, clampf(0.18 + in_gear * 0.72 + absf(in_throttle) * 0.1, 0.0, 1.0) if engine_on else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	if int(g) != _gear:
		_gear = int(g)
	_update_wheels(delta)
	_update_skid(delta)
	if def.get("pedal", false) and has_driver:
		rpm = 0.0

func _balance(delta: float, up: Vector3, fwd: Vector3, right: Vector3) -> void:
	# keep two-wheelers upright and lean them into turns
	var has_rider := driver() != null
	var lean_target := clampf(in_steer * absf(speed) * 0.035, -0.62, 0.62) if has_rider else 0.0
	if not has_rider and absf(speed) < 0.5:
		lean_target = 0.22        # resting on the side stand
	var world_right := fwd.cross(Vector3.UP).normalized()
	if world_right.length() < 0.5:
		return
	var roll := atan2(up.dot(world_right), up.dot(Vector3.UP))
	var roll_rate := angular_velocity.dot(fwd)
	# gains are per unit of roll inertia so light bicycles and heavy motorbikes behave alike
	var inv_i := PhysicsServer3D.body_get_direct_state(get_rid()).inverse_inertia_tensor
	var i_roll := 1.0 / maxf((inv_i * fwd).length(), 0.0001)
	var torque := (lean_target - roll) * 170.0 - roll_rate * 22.0
	apply_torque(fwd * torque * i_roll)
	# pitch stays controllable: damp wheelies a little
	apply_torque(-right * angular_velocity.dot(right) * mass * 0.4)

func _landed(air_time: float) -> void:
	var dist := Vector2(global_position.x - air_start.x, global_position.z - air_start.z).length()
	if has_player() and Game.activities and Game.activities.has_method("on_jump"):
		Game.activities.on_jump(self, air_time, dist, global_transform.basis.y.y > 0.5)
	if has_player() and Game.cam and Game.cam.has_method("shake"):
		Game.cam.shake(clampf(air_time * 0.25, 0.1, 0.6))

func _update_wheels(_delta: float) -> void:
	for w in wheels:
		var n: Node3D = w["node"]
		if n == null:
			continue
		var rest: Transform3D = w["rest"]
		var attach: Vector3 = w["attach"]
		var y := attach.y - float(w["len"])
		var steer_here := steer_angle if w["front"] and not two_wheel else 0.0
		var b := Basis(Vector3.UP, steer_here) * rest.basis * Basis(Vector3.RIGHT, -float(w["spin"]) * float(w["sign"]))
		n.transform = Transform3D(b, Vector3(rest.origin.x, y, rest.origin.z))
	if _fork:
		_fork.transform.basis = _fork_rest * Basis(Vector3.UP, steer_angle)
		# the front wheel follows the fork on bikes
		if two_wheel and wheels.size() > 0 and wheels[0]["node"] != null:
			var fw: Node3D = wheels[0]["node"]
			fw.transform.basis = Basis(Vector3.UP, steer_angle) * (wheels[0]["rest"] as Transform3D).basis * Basis(Vector3.RIGHT, -float(wheels[0]["spin"]) * float(wheels[0]["sign"]))
	if _steering:
		_steering.transform.basis = _steering_rest * Basis(Vector3.FORWARD, -steer_angle * 2.6)
	if _crank and absf(speed) > 0.2:
		_crank.rotate_object_local(Vector3.RIGHT, -speed * 0.02)

func _update_skid(delta: float) -> void:
	var skidding := skid > 0.22 and absf(speed) > 4.0 and grounded_wheels >= 2
	if skidding and _skid_snd == null:
		_skid_snd = Audio.make_loop(&"skid_loop", self, -10.0, 60.0, false)
	if _skid_snd:
		if skidding:
			if not _skid_snd.playing and _skid_snd.stream != null:
				_skid_snd.play()
			_skid_snd.volume_db = lerpf(-16.0, -3.0, clampf(skid * 1.6, 0.0, 1.0))
			_skid_snd.pitch_scale = lerpf(0.85, 1.15, clampf(absf(speed) / 30.0, 0.0, 1.0))
		elif _skid_snd.playing:
			_skid_snd.stop()
	_skid_fx_cd -= delta
	if skidding and _skid_fx_cd <= 0.0 and Game.fx:
		_skid_fx_cd = 0.07
		for w in wheels:
			if float(w["slip"]) > 0.25 and w["grounded"]:
				Game.fx.puff(w["contact"] as Vector3, 0.7)
				break
	if skidding and has_player() and Game.skills:
		Game.skills.add(&"driving", delta * 0.004)
