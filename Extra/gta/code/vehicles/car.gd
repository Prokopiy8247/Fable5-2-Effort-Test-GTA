class_name Car
extends Vehicle
## Wheeled vehicles (cars, trucks, motorcycles, bicycles): project-owned raycast suspension + tyre model
## on a RigidBody3D. Bikes use two wheels and an upright/lean stabiliser.

var wheels: Array = []
var travel := 0.15
var steer_angle := 0.0
var bike := false
var grounded_count := 0
var airtime := 0.0
var skid := 0.0
var rpm := 0.0
var flip_t := 0.0
var sw_base: Basis
var steer_node: Node3D
var steer_base: Transform3D
var crank: Node3D
var stab_off := 0.0
var body_lean := 0.0
var max_air_h := 0.0
var _air_start := Vector3.ZERO
var rest_t := 0.0
var resting := false
var water_t := 0.0


func setup(id: String) -> void:
	super.setup(id)
	bike = kind == "bike"
	angular_damp = 0.5 if not bike else 1.2
	linear_damp = 0.02
	var names := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"] if not bike else ["Wheel_F", "Wheel_R"]
	steer_node = parts.get("Steer")
	if steer_node:
		steer_base = steer_node.transform
	crank = parts.get("Crank")
	var idx := 0
	for nm in names:
		if not parts.has(nm):
			continue
		var wn: MeshInstance3D = parts[nm]
		var rest := wn.position
		if wn.get_parent() == steer_node and steer_node != null:
			rest = steer_node.transform * wn.position
		var radius := wn.mesh.get_aabb().size.y * 0.5
		var is_front: bool = String(nm).contains("_F")
		var drive: bool = (not is_front) if (def.get("rwd", false) or bike) else is_front
		if mass > 2500.0:
			drive = true
		wheels.append({"node": wn, "rest": rest, "local": wn.position, "radius": radius, "steer": is_front, "drive": drive, "comp": travel, "spin": 0.0,
			"idx": idx, "grounded": false, "skid": 0.0, "contact": Vector3.ZERO})
		idx += 1
	travel = 0.13 if not bike else 0.10
	if mass > 3000.0:
		travel = 0.17
	if parts.has("SteeringWheel"):
		sw_base = (parts["SteeringWheel"] as Node3D).transform.basis
	center_of_mass = Vector3(0, (wheels[0].radius if wheels.size() > 0 else 0.3) + 0.12, 0.05 if not bike else 0.0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.05
	physics_material_override = pm


func _maybe_pop_tire(pos: Vector3) -> void:
	var lp := to_local(pos)
	for w in wheels:
		var r: Vector3 = w.rest
		if lp.distance_to(r) < w.radius + 0.22 and G.rng.randf() < 0.6:
			if not tires_popped[w.idx]:
				tires_popped[w.idx] = true
				Sfx.play("tire_pop", pos)


func _apply_rims(opt: Dictionary) -> void:
	if bike or not opt.has("rim") or not Assets.packed("vehicles/wheels"):
		return
	var mesh := Assets.mesh("vehicles/wheels", "wheel_%d" % int(opt.rim))
	var base := mesh.get_aabb().size
	for w in wheels:
		var wn: MeshInstance3D = w.node
		var cur := wn.mesh.get_aabb().size
		if not wn.has_meta("stock"):
			wn.set_meta("stock", wn.mesh)
			wn.set_meta("stock_size", cur)
		var ss: Vector3 = wn.get_meta("stock_size")
		wn.mesh = mesh
		wn.scale = Vector3(ss.x / base.x, ss.y / base.y, ss.z / base.z)


func rest_sleep() -> void:
	## Parked / abandoned cars stop simulating (no suspension rays, static body) until something disturbs them.
	resting = true
	rest_t = 0.0
	speed = 0.0
	fwd_speed = 0.0
	throttle = 0.0
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	if not siren:
		Sfx.stop_engine(self)


func rest_wake() -> void:
	if not resting:
		return
	resting = false
	rest_t = 0.0
	freeze = false
	sleeping = false


func _physics_process(delta: float) -> void:
	if resting:
		if driver != null or has_player():
			rest_wake()
		else:
			return
	if freeze:
		return
	if global_position.y < G.WATER_LEVEL - 0.45:
		_in_water(delta)
	var t := global_transform
	var up := t.basis.y
	var fwd := -t.basis.z
	var right := t.basis.x
	var com_w := t * center_of_mass
	var v := linear_velocity.dot(fwd)
	fwd_speed = v
	speed = linear_velocity.length()
	if sleeping and driver == null:
		return
	var space := get_world_3d().direct_space_state
	var wet: float = G.timew.grip_factor() if G.timew else 1.0
	var max_st: float = float(def.steer) / (1.0 + absf(v) * (0.05 if not bike else 0.07))
	steer_angle = move_toward(steer_angle, -steer * max_st, delta * (2.8 if absf(steer) > 0.05 else 4.5))
	var n_w := wheels.size()
	var m_w := mass / n_w
	var k := mass * 9.8 / (n_w * travel) * 1.05
	var c := 2.0 * 0.62 * sqrt(k * m_w)
	var n_drive := 0
	for w in wheels:
		if w.drive:
			n_drive += 1
	var hp := clampf(health / max_health, 0.0, 1.0)
	var top: float = float(def.top) * float(perf.top) * (0.55 + 0.45 * hp)
	var thr := throttle if engine_on and not dead else 0.0
	var fall := 1.0 - pow(clampf(absf(v) / (top if thr * v >= 0.0 and thr > 0.0 else top * 0.35), 0.0, 1.0), 2.2)
	if thr < 0.0 and v > 0.5:
		fall = 1.0
	var drive_force: float = mass * float(def.accel) * float(perf.accel) * thr * fall * (0.6 + 0.4 * hp)
	var brake_force: float = mass * float(def.brake) * float(perf.brake)
	grounded_count = 0
	skid = 0.0
	var excl := [get_rid()]
	for w in wheels:
		var rest_w: Vector3 = t * ((w.rest as Vector3) - Vector3(0, float(perf.drop), 0))
		var from := rest_w + up * travel
		var ray_len: float = travel * 2.0 + float(w.radius)
		var q := PhysicsRayQueryParameters3D.create(from, from - up * ray_len, G.L_WORLD)
		q.exclude = excl
		var hit := space.intersect_ray(q)
		w.grounded = not hit.is_empty()
		if hit.is_empty():
			w.comp = move_toward(w.comp, 0.0, delta * 2.0)
			w.spin += v / float(w.radius) * delta
			w.skid = 0.0
			continue
		grounded_count += 1
		var dist: float = from.distance_to(hit.position)
		var comp := clampf(ray_len - dist, 0.0, travel * 2.0)
		var vel_c: float = (comp - float(w.comp)) / delta
		w.comp = comp
		var nrm: Vector3 = hit.normal
		var N := clampf(k * comp + c * vel_c, 0.0, mass * 9.8 * 3.0)
		var cp: Vector3 = hit.position
		w.contact = cp
		apply_force(nrm * N, cp - t.origin)
		var pv := linear_velocity + angular_velocity.cross(cp - com_w)
		var wf := fwd
		if w.steer:
			wf = fwd.rotated(up, steer_angle)
		wf = (wf - nrm * wf.dot(nrm)).normalized()
		var ws := wf.cross(nrm).normalized()
		var v_long := pv.dot(wf)
		var v_lat := pv.dot(ws)
		var popped: bool = tires_popped[w.idx]
		var mu: float = float(def.grip) * float(perf.grip) * wet * (0.6 if popped else 1.0) * 1.35
		var hb: bool = handbrake and not w.steer
		if hb:
			mu *= 0.6
		var f_lat := -v_lat * m_w * (10.0 if not hb else 4.0)
		var f_long := 0.0
		if w.drive and not hb:
			f_long += drive_force / maxi(n_drive, 1)
		var brk := 1.0 if hb else brake
		if brk > 0.01:
			f_long -= signf(v_long) * minf(brake_force * brk / n_w, absf(v_long) * m_w / delta)
		f_long -= v_long * (14.0 + (120.0 if popped else 0.0)) * (mass / 1400.0)
		if absf(thr) < 0.05 and brk < 0.01:
			f_long -= v_long * m_w * 0.35
		var f := Vector2(f_long, f_lat)
		var fmax := mu * N
		var over := f.length() / maxf(fmax, 1.0)
		if over > 1.0:
			f = f / over
		w.skid = clampf((over - 0.95) * 1.2, 0.0, 1.0) if (absf(v_lat) > 2.5 or (hb and absf(v_long) > 4.0) or absf(f_long) > fmax * 0.98) else 0.0
		skid = maxf(skid, w.skid)
		var lift := clampf((com_w - cp).dot(up), 0.0, 1.2) * (0.62 / float(def.get("roll", 1.0))) * (1.0 + (1.0 - float(perf.rollk)) * 0.5)
		apply_force(wf * f.x + ws * f.y, cp + up * lift - t.origin)
		w.spin += (v_long if not hb else 0.0) / float(w.radius) * delta
	# aero + assists
	apply_central_force(-linear_velocity * speed * (0.42 + mass * 0.00006))
	if grounded_count > 0:
		apply_central_force(-up * v * v * (0.35 + float(perf.downforce) * 1.4) * (mass / 1400.0))
		if airtime > 0.45:
			_landed(airtime)
		airtime = 0.0
	else:
		if airtime == 0.0:
			_air_start = global_position
			max_air_h = global_position.y
		airtime += delta
		max_air_h = maxf(max_air_h, global_position.y)
		if driver != null:
			apply_torque(right * -in_pitch * mass * 1.6 + fwd * -steer * mass * 1.0)
	if bike:
		_bike_balance(delta, up, fwd, right)
	# self righting for stuck/flipped cars with a driver
	if up.y < 0.35 and speed < 2.5 and driver != null and not bike:
		flip_t += delta
		if flip_t > 1.2:
			var ax := fwd * signf(right.y if absf(right.y) > 0.05 else 1.0)
			apply_torque(ax * mass * 9.0)
			apply_central_force(Vector3.UP * mass * 4.0)
	else:
		flip_t = 0.0
	_hit_characters()
	_visuals(delta, v)
	rpm = clampf(fmod(absf(v), top / 4.2) / (top / 4.2) * 0.6 + absf(thr) * 0.3 + 0.1, 0.0, 1.0)
	if Sfx.has_method("engine_update"):
		Sfx.engine_update(self, rpm, absf(thr))
	if driver == null and speed < 0.12 and angular_velocity.length_squared() < 0.02 and burning < 0.0 and not has_player() and (grounded_count >= wheels.size() - 1 or dead):
		rest_t += delta
		if rest_t > 1.5:
			rest_sleep()
	else:
		rest_t = 0.0


func _in_water(delta: float) -> void:
	## Road vehicles flood: the engine dies, the hull sinks slowly and everybody bails out.
	if not flooded:
		flooded = true
		engine_on = false
		set_siren(false)
		Sfx.stop_engine(self)
		Sfx.play("splash", global_position, 2.0, 0.7)
		if G.fx:
			G.fx.splash(Vector3(global_position.x, G.WATER_LEVEL, global_position.z), 2.8)
		if has_player():
			if airtime > 1.1:
				_landed(airtime)
			G.say("Engine flooded  -  bail out!", Color(1.0, 0.6, 0.4))
		airtime = 0.0
	water_t += delta
	throttle = 0.0
	apply_central_force(Vector3.UP * mass * 9.8 * clampf(0.86 - water_t * 0.06, 0.35, 0.86))
	apply_central_force(-linear_velocity * mass * 1.8)
	apply_torque(-angular_velocity * mass * 1.2)
	if water_t > 2.0:
		for o in occupants():
			if G.is_player(o):
				G.player._leave_vehicle_now(false)
				G.player.global_position = global_position + Vector3(0, 0.4, 0)
				G.player.velocity = Vector3.ZERO
			elif o.has_method("leave_vehicle"):
				o.leave_vehicle()
				(o as Node3D).global_position = global_position + Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1))


func _bike_balance(delta: float, up: Vector3, fwd: Vector3, right: Vector3) -> void:
	stab_off -= delta
	if stab_off > 0.0:
		return
	var roll := atan2(right.y, up.y)
	var target := clampf(steer_angle * clampf(speed / 14.0, 0.0, 1.0) * 1.6, -0.6, 0.6)
	if driver == null and speed < 1.0:
		target = 0.0
	var err := target - roll
	apply_torque(-fwd * (err * mass * 55.0) - fwd * (angular_velocity.dot(fwd) * mass * 9.0))
	# keep pitch reasonable in the air
	if grounded_count == 0:
		apply_torque(right * (-fwd.y) * mass * 14.0 - right * angular_velocity.dot(right) * mass * 3.0)


func _landed(t: float) -> void:
	if has_player() and G.main and G.main.has_node("Activities"):
		G.main.get_node("Activities").on_jump_landed(self, t, _air_start, max_air_h)


func _visuals(delta: float, v: float) -> void:
	for w in wheels:
		var wn: Node3D = w.node
		var y_off: float = float(w.comp) - travel - float(perf.drop)
		if steer_node != null and wn.get_parent() == steer_node:
			wn.rotation = Vector3(-float(w.spin), 0, 0)
		else:
			wn.position = (w.local as Vector3) + Vector3(0, y_off, 0)
			wn.rotation = Vector3(-float(w.spin), steer_angle if w.steer else 0.0, 0)
	if parts.has("SteeringWheel"):
		(parts["SteeringWheel"] as Node3D).transform.basis = sw_base * Basis(Vector3(0, 0, 1), steer_angle * 3.5)
	if steer_node:
		steer_node.transform = steer_base * Transform3D(Basis(Vector3(0, 0.94, 0.34).normalized(), steer_angle * 1.4), Vector3.ZERO)
	if crank and driver != null:
		crank.rotation.x -= v * delta * 2.2


func _hit_characters() -> void:
	if speed < 2.6:
		return
	for ch in get_tree().get_nodes_in_group("chars"):
		var n3 := ch as Node3D
		if n3 == null or not ch.has_method("hit_by_vehicle"):
			continue
		var d := n3.global_position - global_position
		if d.length_squared() > 49.0:
			continue
		if ch.get("vehicle") != null:
			continue
		var lp := to_local(n3.global_position + Vector3(0, 0.6, 0))
		if absf(lp.x) < half.x + 0.3 and absf(lp.z) < half.z + 0.35 and lp.y > -0.3 and lp.y < half.y * 2.0 + 0.6:
			var rel := linear_velocity
			if rel.dot(d.normalized()) > 1.5 or speed > 6.0:
				ch.hit_by_vehicle(self, rel)
				apply_central_impulse(-linear_velocity.normalized() * minf(speed, 3.0) * 60.0)


func _on_crash(dv: float, other: Object, pos: Vector3, shape_idx: int) -> void:
	super._on_crash(dv, other, pos, shape_idx)
	if bike and dv > 7.5:
		stab_off = 2.5
		for o in occupants():
			if o.has_method("fall_off_vehicle"):
				o.fall_off_vehicle(self, linear_velocity)
	if other is StaticBody3D and (other as Node).has_meta("props") and speed > 3.5:
		var sb := other as StaticBody3D
		if shape_idx >= 0 and shape_idx < sb.get_shape_owners().size() + 4096:
			var owner_id := sb.shape_find_owner(shape_idx)
			var sn := sb.shape_owner_get_owner(owner_id) as Node
			if sn and sn.has_meta("prop") and G.world:
				G.world.knock_prop(sn, linear_velocity * mass * 0.05, pos)
	elif other is Vehicle:
		var ov := other as Vehicle
		if has_player() and driver != null and G.is_player(driver):
			if ov.is_emergency or ov.driver != null:
				G.report_crime("collision", pos, 0.5 if not ov.is_emergency else 1.5, G.player)
			if ov.ai != null and ov.ai.has_method("on_rammed"):
				ov.ai.on_rammed(self, dv)
