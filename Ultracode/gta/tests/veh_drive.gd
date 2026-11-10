extends Node
## Headless driving test for every car spec whose GLB exists (all specs run side by side in
## 16 m lanes on a code-built proving ground):
##   rest 3 s (drift < 5 cm, upright) -> full throttle 20 s (0-100 km/h, speed at 6 s, top speed)
##   -> full brake (distance) -> reverse -> steering direction (+1 turns right) -> handbrake
##   slide -> 0.15 m kerb straight (1 ray) and diagonal (3 rays) -> ramp jump -> all upright.
## Prints a table (0-100 km/h, speed @6 s, top speed, 100-0 braking distance, ...).
##
## Run: tools\godot.ps1 -Mode headless -Frames 7000 -UserArgs '--test=veh_drive','--no_player',
##      '--disable=world,environment,city,interactions,pickups,props,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## Optional: --veh=sedan,sports   (limit the specs)
##           --rig                 TEST ONLY: car specs whose GLB is not exported yet run on a
##                                 programmatic box-and-cylinder stand-in of similar size, so
##                                 their tuning can be checked early (marked "rig" in the table).

const Bed := preload("res://gta/tests/veh_testbed.gd")
const LANE := 24.0
const KMH100 := 27.778

var cars: Array = []
var ids: Array[String] = []
var stats: Dictionary = {}       ## id -> Dictionary of measurements
var rigged: Dictionary = {}      ## id -> true when a stand-in rig replaces a missing GLB (--rig)


func _ready() -> void:
	await _run()


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _lane_x(i: int) -> float:
	return (float(i) - float(ids.size() - 1) * 0.5) * LANE


func _all_inputs(throttle: float, steer: float, brake: float, handbrake: bool = false) -> void:
	for c: Variant in cars:
		c.set_inputs(throttle, steer, brake, handbrake)


func _teleport_all(z: float, yaw: float) -> void:
	for i in cars.size():
		cars[i].release_inputs()
		cars[i].teleport(Transform3D(Basis(Vector3.UP, yaw), Vector3(_lane_x(i), 0.03, z)))


func _stop_all(seconds: float = 3.0) -> void:
	_all_inputs(0.0, 0.0, 1.0)
	await _physics_frames(int(seconds * 60.0))
	_all_inputs(0.0, 0.0, 0.0)


func _run() -> void:
	var mgr := Game.get_system("vehicles")
	if not TestHarness.check(mgr != null, "vehicles system is registered"):
		TestHarness.finish(false, "no vehicles system")
		return
	# the cars spread over hundreds of metres: pin full detail so wheel visuals are simulated
	mgr.detail_override = 0
	ids = Bed.ids_with_models()
	var args := OS.get_cmdline_user_args()
	if args.has("--rig"):
		for id: Variant in Registry.ids("vehicles"):
			var rs := Registry.get_def("vehicles", str(id)) as VehicleSpec
			if rs != null and rs.vehicle_class == "car" and not ids.has(str(id)):
				ids.append(str(id))
				rigged[str(id)] = true
	for i in range(ids.size() - 1, -1, -1):
		var cs := Registry.get_def("vehicles", ids[i]) as VehicleSpec
		if cs == null or cs.vehicle_class != "car":
			ids.remove_at(i)        # this test drives cars; other classes have their own tests
	for a: String in args:
		if a.begins_with("--veh="):
			var want := a.substr(6).split(",", false)
			var filtered: Array[String] = []
			for id: String in ids:
				if want.has(id):
					filtered.append(id)
			ids = filtered
	var all_ids := Registry.ids("vehicles")
	print("VEH_DRIVE: registered specs = ", all_ids)
	print("VEH_DRIVE: car specs under test = ", ids)
	print("VEH_DRIVE: on a stand-in rig (no GLB yet) = ", rigged.keys())
	Bed.build_proving_ground(self, maxf(140.0, float(ids.size()) * LANE * 0.5 + 60.0))
	if not TestHarness.check(not ids.is_empty(), "at least one vehicle GLB is available"):
		TestHarness.finish(false, "no models")
		return
	await _physics_frames(2)

	# ---------------------------------------------------------------- spawn + rest
	var start: Array[Vector3] = []
	for i in ids.size():
		var opts := {"color": Color(0.8, 0.2, 0.15)}
		if rigged.has(ids[i]):
			opts["model_instance"] = Bed.make_rig_model(ids[i])
		var v: Node3D = Game.spawn_vehicle(ids[i], Transform3D(Basis.IDENTITY, Vector3(_lane_x(i), 0.0, 0.0)), opts)
		if not TestHarness.check(v != null, "%s spawns" % ids[i]):
			continue
		cars.append(v)
		stats[ids[i]] = {}
	if cars.size() != ids.size():
		TestHarness.finish(false, "spawn failed")
		return
	# the lanes are independent experiments: test cars never collide with each other
	for a: Variant in cars:
		for b: Variant in cars:
			if a != b:
				a.add_collision_exception_with(b)
	await _physics_frames(1)
	for c: Variant in cars:
		start.append(c.global_position)
	var max_tilt_rest := 0.0
	for f in 180:
		await get_tree().physics_frame
	for i in cars.size():
		var c: Variant = cars[i]
		var drift: float = (c.global_position - start[i]).length()
		var upy: float = c.global_transform.basis.y.y
		max_tilt_rest = maxf(max_tilt_rest, 1.0 - upy)
		stats[ids[i]]["rest_drift_cm"] = drift * 100.0
		stats[ids[i]]["rest_y_cm"] = c.global_position.y * 100.0
		stats[ids[i]]["asleep"] = c.sleeping
		TestHarness.check(drift < 0.05, "%s rests within 5 cm (drift %.1f cm, y %.1f cm, asleep=%s)" % [ids[i], drift * 100.0, c.global_position.y * 100.0, str(c.sleeping)])
		TestHarness.check(upy > 0.9995, "%s rests upright (up.y %.5f)" % [ids[i], upy])
		TestHarness.check(c.get_wheel_count() >= 4, "%s has %d wheels" % [ids[i], c.get_wheel_count()])
		TestHarness.check(absf(c.global_position.y) < 0.02, "%s sits at its modelled ride height: neither floating nor sunk (origin y %.3f m)" % [ids[i], c.global_position.y])
		var worst := 0.0
		var lowest := INF
		for wi in c.get_wheel_count():
			var wn: Node3D = c.get_wheel_node(wi)
			if wn == null:
				continue
			var wo: Vector3 = c.xform_in_body(wn).origin
			var wr: Vector3 = c.wheels[wi].rest_pos
			worst = maxf(worst, (wo - wr).length())
			lowest = minf(lowest, wn.global_position.y - c.get_wheel_radius(wi))
		TestHarness.check(worst < 0.02 and absf(lowest) < 0.03,
				"%s wheels rest at their authored positions in the arches (max offset %.3f m, tyre bottom at y %.3f m)" % [ids[i], worst, lowest])

	# ---------------------------------------------------------------- acceleration / top speed
	_all_inputs(1.0, 0.0, 0.0)
	for i in cars.size():
		stats[ids[i]]["t100"] = -1.0
		stats[ids[i]]["v6"] = 0.0
		stats[ids[i]]["vmax"] = 0.0
		stats[ids[i]]["x_dev"] = 0.0
	var spin_b0: Array = []
	for c: Variant in cars:
		spin_b0.append(Basis.IDENTITY)
	for f in 20 * 60:
		await get_tree().physics_frame
		var t := float(f + 1) / 60.0
		for i in cars.size():
			var c: Variant = cars[i]
			var sp: float = c.get_forward_speed()
			var s: Dictionary = stats[ids[i]]
			# visual wheel spin: one frame of rotation of the last (rear) wheel, in body space
			var rear: Node3D = c.get_wheel_node(c.get_wheel_count() - 1)
			if rear != null and f == 60:
				spin_b0[i] = c.xform_in_body(rear).basis.orthonormalized()
			elif rear != null and f == 61:
				var b1: Basis = c.xform_in_body(rear).basis.orthonormalized()
				var b0: Basis = spin_b0[i]
				var dq: Quaternion = (b1 * b0.inverse()).get_rotation_quaternion()
				var ang: float = dq.get_angle()
				var axis: Vector3 = dq.get_axis() if ang > 0.0001 else Vector3.ZERO
				s["spin_axis"] = axis
				s["spin_angle"] = ang
				TestHarness.check(ang > 0.02 and ang < PI and axis.x < -0.995,
						"%s wheels spin about the axle (body X) and roll forward (axis %s, %.2f rad / frame at %.1f m/s)" % [ids[i], str(axis.snapped(Vector3(0.01, 0.01, 0.01))), ang, sp])
			if float(s["t100"]) < 0.0 and sp >= KMH100:
				s["t100"] = t
			if f == 6 * 60 - 1:
				s["v6"] = sp
				s["x_dev"] = absf(c.global_position.x - start[i].x)
			s["vmax"] = maxf(float(s["vmax"]), sp)
	for i in cars.size():
		var c: Variant = cars[i]
		var s: Dictionary = stats[ids[i]]
		var top: float = c.spec.top_speed
		s["v_end"] = c.get_forward_speed()
		TestHarness.check(float(s["v6"]) > top * 0.45 and float(s["v6"]) < top * 1.1,
				"%s speed after 6 s is plausible (%.1f m/s, top %.1f)" % [ids[i], float(s["v6"]), top])
		TestHarness.check(float(s["vmax"]) > top * 0.93 and float(s["vmax"]) < top * 1.08,
				"%s reaches its top speed (%.1f of %.1f m/s)" % [ids[i], float(s["vmax"]), top])
		TestHarness.check(float(s["x_dev"]) < 1.5, "%s tracks straight under power (%.2f m off line after 6 s)" % [ids[i], float(s["x_dev"])])
		TestHarness.check(c.global_transform.basis.y.y > 0.97, "%s upright at speed" % ids[i])

	# ---------------------------------------------------------------- braking
	var brake_from: Array[Vector3] = []
	var brake_v0: Array[float] = []
	var p100: Array = []
	var stop_pos: Array = []
	var stop_t: Array[float] = []
	for c: Variant in cars:
		brake_from.append(c.global_position)
		brake_v0.append(c.get_forward_speed())
		p100.append(null)
		stop_pos.append(null)
		stop_t.append(-1.0)
	_all_inputs(0.0, 0.0, 1.0)
	for f in 10 * 60:
		await get_tree().physics_frame
		for i in cars.size():
			var c: Variant = cars[i]
			var sp: float = c.get_forward_speed()
			if p100[i] == null and sp <= KMH100:
				p100[i] = c.global_position
			if stop_pos[i] == null and sp < 0.25:
				stop_pos[i] = c.global_position
				stop_t[i] = float(f + 1) / 60.0
	for i in cars.size():
		var s: Dictionary = stats[ids[i]]
		var ok := stop_pos[i] != null
		TestHarness.check(ok, "%s brakes to a stop from %.1f m/s" % [ids[i], brake_v0[i]])
		if not ok:
			s["brake100"] = -1.0
			continue
		var d_total: float = (stop_pos[i] as Vector3).distance_to(brake_from[i])
		var d100 := d_total * pow(KMH100 / maxf(brake_v0[i], 1.0), 2.0)
		if brake_v0[i] > KMH100 and p100[i] != null:
			d100 = (stop_pos[i] as Vector3).distance_to(p100[i] as Vector3)
		s["brake100"] = d100
		s["brake_total"] = d_total
		TestHarness.check(d100 > 20.0 and d100 < 95.0, "%s 100-0 km/h braking distance is plausible (%.1f m)" % [ids[i], d100])
		TestHarness.check(absf((stop_pos[i] as Vector3).x - start[i].x) < 3.0, "%s brakes in a straight line" % ids[i])

	# ---------------------------------------------------------------- reverse
	_all_inputs(-1.0, 0.0, 0.0)
	await _physics_frames(3 * 60)
	for i in cars.size():
		var c: Variant = cars[i]
		var sp: float = c.get_forward_speed()
		stats[ids[i]]["v_rev"] = sp
		TestHarness.check(sp < -2.5, "%s reverses (%.1f m/s after 3 s)" % [ids[i], sp])
		TestHarness.check(c.is_reversing(), "%s reports is_reversing()" % ids[i])
	await _stop_all(3.0)

	# ---------------------------------------------------------------- steering direction
	_teleport_all(0.0, 0.0)
	await _physics_frames(20)
	_all_inputs(1.0, 0.0, 0.0)
	await _physics_frames(int(2.6 * 60.0))
	var h0: Array[float] = []
	for c: Variant in cars:
		h0.append(Bed.heading(c))
	_all_inputs(0.35, 1.0, 0.0)
	var beta_steer: Array[float] = []
	for c: Variant in cars:
		beta_steer.append(0.0)
	for f in 75:
		await get_tree().physics_frame
		for i in cars.size():
			beta_steer[i] = maxf(beta_steer[i], _slip_deg(cars[i]))
	for i in cars.size():
		var c: Variant = cars[i]
		var dh := wrapf(Bed.heading(c) - h0[i], -PI, PI)
		var front: Node3D = c.get_wheel_node(0)
		if front != null:
			var fb: Basis = c.xform_in_body(front).basis.orthonormalized()
			var fr: Basis = c.get_wheel_rest_basis(0).orthonormalized()
			var axle: Vector3 = (fb * fr.inverse()) * Vector3.RIGHT
			TestHarness.check(absf(axle.y) < 0.02 and axle.z > 0.03 and axle.x > 0.8,
					"%s front wheels steer about the vertical axis, to the right (axle %s, steer %.2f)" % [ids[i], str(axle.snapped(Vector3(0.01, 0.01, 0.01))), float(c.steer_norm)])
		stats[ids[i]]["yaw_deg"] = rad_to_deg(dh)
		stats[ids[i]]["beta_steer"] = beta_steer[i]
		TestHarness.check(dh > 0.12, "%s steer +1 turns right (heading change %.1f deg)" % [ids[i], rad_to_deg(dh)])
		TestHarness.check(c.global_transform.basis.y.y > 0.9, "%s stays upright while cornering (up.y %.3f)" % [ids[i], c.global_transform.basis.y.y])
	_all_inputs(0.35, -1.0, 0.0)
	var h1: Array[float] = []
	for c: Variant in cars:
		h1.append(Bed.heading(c))
	await _physics_frames(90)
	for i in cars.size():
		var dh := wrapf(Bed.heading(cars[i]) - h1[i], -PI, PI)
		TestHarness.check(dh < -0.08, "%s steer -1 turns left (heading change %.1f deg in 1.5 s, including the steering reversal)" % [ids[i], rad_to_deg(dh)])
	await _stop_all(4.0)

	# ---------------------------------------------------------------- handbrake slide
	_teleport_all(0.0, 0.0)
	await _physics_frames(20)
	_all_inputs(1.0, 0.0, 0.0)
	await _physics_frames(int(4.0 * 60.0))
	var beta_hb: Array[float] = []
	for c: Variant in cars:
		beta_hb.append(0.0)
	_all_inputs(0.0, 1.0, 0.0, true)
	for f in 110:
		await get_tree().physics_frame
		for i in cars.size():
			beta_hb[i] = maxf(beta_hb[i], _slip_deg(cars[i]))
	for i in cars.size():
		var c: Variant = cars[i]
		stats[ids[i]]["beta_hb"] = beta_hb[i]
		TestHarness.check(beta_hb[i] > 14.0, "%s handbrake turn slides (max slip angle %.1f deg, %.1f without handbrake)" % [ids[i], beta_hb[i], beta_steer[i]])
		TestHarness.check(c.global_transform.basis.y.y > 0.85, "%s upright after the handbrake turn (up.y %.3f)" % [ids[i], c.global_transform.basis.y.y])
	await _stop_all(4.0)

	# ---------------------------------------------------------------- kerb, straight (1 ray per wheel)
	await _kerb_pass(PI, 1, "straight")
	# ---------------------------------------------------------------- kerb, diagonal (3 rays per wheel)
	await _kerb_pass(PI + 0.45, 3, "diagonal")

	# ---------------------------------------------------------------- ramp jump
	_teleport_all(100.0, PI)
	for c: Variant in cars:
		c.wheel_rays = 0
	await _physics_frames(20)
	_all_inputs(1.0, 0.0, 0.0)
	var air: Array[float] = []
	var min_up: Array[float] = []
	var max_y: Array[float] = []
	for c: Variant in cars:
		air.append(0.0)
		min_up.append(1.0)
		max_y.append(0.0)
	for f in int(12.0 * 60.0):
		await get_tree().physics_frame
		for i in cars.size():
			var c: Variant = cars[i]
			# full throttle up the ramp, brake once well past the landing zone
			if c.global_position.z > Bed.RAMP_Z1 + 30.0:
				c.set_inputs(0.0, 0.0, 1.0)
			else:
				c.set_inputs(1.0, 0.0, 0.0)
			air[i] = maxf(air[i], float(c.airborne_time))
			min_up[i] = minf(min_up[i], c.global_transform.basis.y.y)
			max_y[i] = maxf(max_y[i], c.global_position.y)
	await _physics_frames(90)
	for i in cars.size():
		var c: Variant = cars[i]
		stats[ids[i]]["air"] = air[i]
		stats[ids[i]]["jump_y"] = max_y[i]
		TestHarness.check(c.global_position.z > Bed.RAMP_Z1, "%s cleared the ramp (z %.1f)" % [ids[i], c.global_position.z])
		TestHarness.check(air[i] > 0.15, "%s was airborne (%.2f s, peak y %.2f m)" % [ids[i], air[i], max_y[i]])
		TestHarness.check(c.global_transform.basis.y.y > 0.9 and min_up[i] > 0.5,
				"%s lands on its wheels (up.y now %.3f, min %.3f)" % [ids[i], c.global_transform.basis.y.y, min_up[i]])
		TestHarness.check(c.global_position.y < 0.3 and not c.destroyed, "%s back on the ground, health %.0f" % [ids[i], c.health])

	_print_table()
	TestHarness.finish()


func _slip_deg(c: Variant) -> float:
	var vel: Vector3 = c.linear_velocity
	vel.y = 0.0
	if vel.length() < 3.0:
		return 0.0
	var f: Vector3 = -c.global_transform.basis.z
	f.y = 0.0
	return rad_to_deg(absf(f.normalized().signed_angle_to(vel.normalized(), Vector3.UP)))


func _kerb_pass(yaw: float, rays: int, label: String) -> void:
	_teleport_all(34.0, yaw)
	for c: Variant in cars:
		c.wheel_rays = rays
		c.repair()
	await _physics_frames(20)
	var min_up: Array[float] = []
	for c: Variant in cars:
		min_up.append(1.0)
	_all_inputs(1.0, 0.0, 0.0)
	for f in int(7.5 * 60.0):
		await get_tree().physics_frame
		for i in cars.size():
			var c: Variant = cars[i]
			# hold roughly 9 m/s
			c.set_inputs(1.0 if c.linear_velocity.length() < 9.0 else 0.15, 0.0, 0.0)
			min_up[i] = minf(min_up[i], c.global_transform.basis.y.y)
	for i in cars.size():
		var c: Variant = cars[i]
		stats[ids[i]]["kerb_" + label] = min_up[i]
		TestHarness.check(c.global_position.z > Bed.KERB_Z1 + 1.0, "%s crossed the 0.15 m kerb %s (z %.1f)" % [ids[i], label, c.global_position.z])
		TestHarness.check(min_up[i] > 0.9 and c.global_transform.basis.y.y > 0.97,
				"%s stays upright over the kerb, %s, %d ray(s) (min up.y %.3f)" % [ids[i], label, rays, min_up[i]])
		TestHarness.check(c.health > c.max_health * 0.95, "%s takes no real damage from the kerb (%s): health %.0f" % [ids[i], label, c.health])
	await _stop_all(3.0)


func _print_table() -> void:
	print("VEH_TABLE: %-15s %-4s %6s %7s %8s %8s %9s %7s %8s %8s %6s %7s" % ["spec", "mdl", "mass", "0-100", "v@6s", "top", "brake100", "rev", "yaw1.25", "hb_slip", "air", "rest_cm"])
	for id: String in ids:
		var s: Dictionary = stats[id]
		var spec: VehicleSpec = Registry.get_def("vehicles", id)
		var t100 := float(s.get("t100", -1.0))
		print("VEH_TABLE: %-15s %-4s %6.0f %7s %8.1f %8.1f %9.1f %7.1f %8.1f %8.1f %6.2f %7.2f" % [
			id, "rig" if rigged.has(id) else "glb", spec.mass, ("%.2f" % t100) if t100 > 0.0 else "n/a",
			float(s.get("v6", 0.0)) * 3.6, float(s.get("vmax", 0.0)) * 3.6, float(s.get("brake100", -1.0)),
			float(s.get("v_rev", 0.0)) * 3.6, float(s.get("yaw_deg", 0.0)), float(s.get("beta_hb", 0.0)),
			float(s.get("air", 0.0)), float(s.get("rest_drift_cm", 0.0))])
	print("VEH_TABLE: units: mass kg | 0-100 s | v@6s, top, rev km/h | brake100 m | yaw deg in 1.25 s | hb_slip deg | air s")
