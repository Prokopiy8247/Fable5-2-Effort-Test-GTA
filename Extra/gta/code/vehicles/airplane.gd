class_name Airplane
extends Vehicle
## Fixed-wing aircraft: thrust, speed dependent lift (velocity alignment), stall, control surfaces
## that scale with airspeed, tricycle landing gear with brakes and nose steering.

var gear: Array = []
var prop: Node3D
var grounded := 0
var stall := 0.0
var travel := 0.16


func setup(id: String) -> void:
	super.setup(id)
	prop = parts.get("Propeller")
	angular_damp = 2.4
	linear_damp = 0.0
	crash_scale = 1.8
	for nm in ["Wheel_N", "Wheel_L", "Wheel_R"]:
		if parts.has(nm):
			var wn: MeshInstance3D = parts[nm]
			gear.append({"node": wn, "rest": wn.position, "radius": wn.mesh.get_aabb().size.y * 0.5, "comp": travel, "spin": 0.0, "nose": nm == "Wheel_N"})
	center_of_mass = Vector3(0, half.y * 0.5, 0.25)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.4
	physics_material_override = pm


func _physics_process(delta: float) -> void:
	var t := global_transform
	var up := t.basis.y
	var fwd := -t.basis.z
	var right := t.basis.x
	var v := linear_velocity
	speed = v.length()
	var vf := v.dot(fwd)
	fwd_speed = vf
	var active := engine_on and not dead and (driver != null or ai != null)
	var thr := throttle if active else 0.0
	if prop:
		prop.rotate_object_local(Vector3(0, 0, 1), (4.0 + thr * 40.0 if active else 0.0) * delta)
	if Sfx.has_method("engine_update"):
		Sfx.engine_update(self, clampf(0.25 + thr * 0.75, 0.0, 1.0) if active else 0.0, thr)
	if sleeping and not active:
		return
	var top: float = float(def.top)
	var vto: float = float(def.takeoff)
	var hp := clampf(health / max_health, 0.3, 1.0)
	# thrust and drag
	apply_central_force(fwd * thr * mass * float(def.accel) * clampf(1.0 - vf / (top * 1.05), 0.0, 1.0) * hp)
	apply_central_force(-v * speed * mass * (float(def.accel) / (top * top)) * 0.9)
	# landing gear
	grounded = 0
	var com_w := t * center_of_mass
	var k := mass * 9.8 / (maxi(gear.size(), 1) * travel)
	var c := 2.0 * 0.6 * sqrt(k * mass / maxi(gear.size(), 1))
	for g in gear:
		var rest_w: Vector3 = t * (g.rest as Vector3)
		var from := rest_w + up * travel
		var ray_len: float = travel * 2.0 + float(g.radius)
		var q := PhysicsRayQueryParameters3D.create(from, from - up * ray_len, G.L_WORLD)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			g.comp = 0.0
			continue
		grounded += 1
		var comp := clampf(ray_len - from.distance_to(hit.position), 0.0, travel * 2.0)
		var N := clampf(k * comp + c * (comp - float(g.comp)) / delta, 0.0, mass * 9.8 * 3.0)
		g.comp = comp
		var cp: Vector3 = hit.position
		apply_force(hit.normal * N, cp - t.origin)
		var pv := v + angular_velocity.cross(cp - com_w)
		var wf := fwd
		if g.nose:
			wf = fwd.rotated(up, -in_yaw * 0.35 - in_roll * 0.2)
		var ws := wf.cross(up).normalized()
		var f_lat := clampf(-pv.dot(ws) * mass / gear.size() * 8.0, -N * 1.1, N * 1.1)
		var f_long := -pv.dot(wf) * mass / gear.size() * (0.06 + brake * 2.2 + (0.5 if not active else 0.0))
		apply_force(ws * f_lat + wf * clampf(f_long, -N, N), cp + up * 0.2 - t.origin)
		g.spin += pv.dot(wf) / float(g.radius) * delta
		(g.node as Node3D).rotation.x = -float(g.spin)
		(g.node as Node3D).position = (g.rest as Vector3) + Vector3(0, comp - travel, 0)
	# aerodynamics
	var sf := clampf(vf / vto, 0.0, 1.5)
	var lift_k := sf * sf
	stall = clampf(1.0 - sf * 1.15, 0.0, 1.0) if grounded == 0 else 0.0
	apply_central_force(-up * v.dot(up) * mass * 4.2 * lift_k - right * v.dot(right) * mass * 2.6 * minf(lift_k, 1.0))
	apply_central_force(up * mass * 9.8 * minf(lift_k, 1.0) * 0.55 * maxf(up.y, 0.0))
	var eff := clampf(sf, 0.0, 1.25)
	var flying: float = G.player.skill("flying") if G.player != null and has_player() else 0.5
	eff *= 0.85 + 0.3 * flying
	apply_torque(right * (-in_pitch) * mass * 5.2 * eff)
	apply_torque(fwd * in_roll * mass * 6.5 * eff)
	apply_torque(up * (-in_yaw) * mass * 2.2 * eff)
	if speed > 3.0:
		apply_torque(fwd.cross(v / speed) * mass * 3.0 * eff)
	if grounded == 0:
		apply_torque(right * (-stall) * mass * 4.0)
		# gentle self-levelling so the plane is easy to fly with keys
		if absf(in_roll) < 0.05:
			apply_torque(fwd * right.y * mass * 1.3 * eff)
		if has_player() and G.timew and G.timew.cur.storm > 0.3:
			apply_torque(Vector3(sin(t.origin.x * 0.05 + speed), 0, cos(t.origin.z * 0.04)) * mass * G.timew.cur.storm * (1.2 - flying))
	var p := global_position
	if absf(p.x) > 900.0 or absf(p.z) > 900.0:
		var to_c := (-G.flat(p)).normalized()
		apply_torque(up * fwd.cross(to_c).y * mass * 6.0)
		if has_player() and Engine.get_physics_frames() % 240 == 0:
			G.say("Leaving Cinder Bay airspace - turning back", Color(1, 0.8, 0.4))
	if p.y < G.WATER_LEVEL - 0.5 and not dead:
		take_damage(max_health, null, p, "crash")
