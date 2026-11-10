class_name Car
extends VehicleBase
## Four (or six) wheeled road vehicle: project-owned raycast suspension + tyre model on a
## RigidBody3D, tuned for an arcade-realistic feel (grippy but slidable, handbrake turns, slight
## body roll, forgiving). All forces are computed in `_integrate_vehicle` at 60 Hz:
##
##   1. drivetrain   torque curve -> automatic gearbox -> total drive force, brakes, engine braking
##   2. steering     rate-limited, speed-sensitive lock, counter-steer assist
##   3. wheels       one ray per wheel (three for the player's car so kerbs are climbed smoothly),
##                   spring + damper + bump stop + anti-roll bar around the MODELLED ride height,
##                   slip-angle lateral force, friction-ellipse coupling, kinetic friction for
##                   handbrake-locked wheels, static-friction anchors when parked
##   4. aero         drag (derived from the spec's top speed), downforce, in-air levelling
##   5. rest         puts the body to sleep when parked so it costs nothing and never jitters
##
## Tuning guide: docs/VEHICLES.md.

const RAY_EXTRA := 0.24        ## ray starts this far above full bump (detects bump-stop travel)
const FLAT_DROP := 0.035       ## a flat tyre loses this much radius
const FLAT_GRIP := 0.55        ## grip multiplier of a flat tyre
const FLAT_DRAG := 0.24        ## extra rolling drag of a flat tyre (x normal force): pulls to that side
const LSD_BIAS := 1.15         ## max drive force ratio between the two wheels of an axle
const HOLD_SPEED := 0.7        ## below this, with a closed throttle, the wheels hold position
const GRAV := 9.81
const GOVERNOR_FRAC := 0.985   ## rpm / redline at which the top gear holds the governed top speed
const TOP_SPEED_RESIST := 0.6  ## share of the drive force eaten by drag + rolling at top speed
const LEAN_ROLL_MAX := 0.04    ## rad of extra visual body roll (keeps the tyres clear of the arches)
const LEAN_PITCH_MAX := 0.02   ## rad of extra visual squat / dive
const WHEEL_ORDER: Array[String] = ["Wheel_FL", "Wheel_FR", "Wheel_ML", "Wheel_MR", "Wheel_RL", "Wheel_RR"]

var wheels: Array[VehicleWheel] = []
var gear: int = 1                  ## -1 reverse, 1..n forward
var rpm: float = 850.0
var steer_angle: float = 0.0       ## road-wheel angle in radians, + = right
var steer_norm: float = 0.0        ## steer_angle / max angle
var grounded_wheels: int = 0
var airborne_time: float = 0.0
var wheel_rays: int = 0            ## 0 = auto (3 for the player's car, 1 otherwise); 1 or 3 forces it
var wheelbase: float = 2.6
var track_width: float = 1.5

var _gear_ratio: PackedFloat32Array = PackedFloat32Array()   ## overall ratios, index 0 = first gear
var _peak_torque: float = 250.0
var _top_speed: float = 45.0
var _drag: float = 1.0
var _redline_omega: float = 680.0
var _wheel_r: float = 0.33
var _brake_force: float = 10000.0
var _ride_drop: float = 0.0
var _downforce: float = 0.0
var _wheel_ref_z: float = 0.0
var _has_wheel_ref: bool = false
var _shift_t: float = 0.0
var _shift_cd: float = 0.0
var _drive_force: float = 0.0
var _brake_req: float = 0.0
var _engine_brake: float = 0.0
var _throttle_eff: float = 0.0
var _brake_eff: float = 0.0
var _brake_lamp: bool = false
var _spin_extra: float = 0.0
var _skid: float = 0.0
var _rest_t: float = 0.0
var _sleep_request: bool = false
var _grip_env: float = 1.0
var _grip_env_t: float = 0.0
var _fx_t: float = 0.0
var _exhaust_t: float = 0.0          ## cool-down of the cosmetic exhaust puffs
var _exhaust_req: int = 0             ## 1 = upshift under load, 2 = hard launch (consumed by _update_visuals)
var _self_exclude: Array[RID] = []
var _visual_settled: bool = false
var _lean_roll: float = 0.0        ## extra visual roll of the shell (rad, + = leaning left)
var _lean_pitch: float = 0.0       ## extra visual pitch (rad, + = nose down)
var _lean_active: bool = false
var _lean_pivot: Vector3 = Vector3.ZERO
var _model_rest: Transform3D = Transform3D.IDENTITY


# ==============================================================================================
# build
# ==============================================================================================

func _build_drive(_opts: Dictionary) -> void:
	_self_exclude = [get_rid()]
	for nm: String in WHEEL_ORDER:
		var n := get_part(nm)
		if n == null:
			continue
		var w := VehicleWheel.new()
		w.wheel_name = nm
		w.node = n
		var xf := xform_in_body(n)
		w.rest_pos = xf.origin
		w.rest_basis = xf.basis
		var par := n.get_parent() as Node3D
		if par != null and par != self:
			w.parent_inv = xform_in_body(par).affine_inverse()
		var a := aabb_in_body(n)
		var measured := maxf(a.size.y, a.size.z) * 0.5
		if spec.wheel_radius > 0.0:
			w.radius = spec.wheel_radius
		elif measured > 0.1:
			w.radius = measured
		if a.size.x > 0.05:
			w.width = a.size.x
		w.is_front = nm.begins_with("Wheel_F")
		w.is_left = nm.ends_with("L")
		wheels.append(w)
	if wheels.size() < 3:
		push_warning("Car %s: model has %d Wheel_* nodes - using invisible wheels from the body bounds" % [spec_id, wheels.size()])
		wheels.clear()
		var c := body_aabb.get_center()
		var hx := body_aabb.size.x * 0.5 - 0.14
		var hz := body_aabb.size.z * 0.31
		for i in 4:
			var w := VehicleWheel.new()
			w.is_front = i < 2
			w.is_left = (i % 2) == 0
			w.wheel_name = WHEEL_ORDER[i if i < 2 else i + 2]
			w.radius = spec.wheel_radius if spec.wheel_radius > 0.0 else 0.33
			w.rest_pos = Vector3(c.x + (-hx if w.is_left else hx), w.radius, c.z + (-hz if w.is_front else hz))
			wheels.append(w)
	# axles
	var front_z := 0.0
	var rear_z := 0.0
	var n_rear := 0
	var nf := 0
	var left_x := 0.0
	var right_x := 0.0
	for w: VehicleWheel in wheels:
		if w.is_front:
			front_z += w.rest_pos.z
			nf += 1
			if w.is_left:
				left_x = w.rest_pos.x
			else:
				right_x = w.rest_pos.x
		else:
			rear_z += w.rest_pos.z
			n_rear += 1
		for oi in wheels.size():
			var o := wheels[oi]
			if o != w and o.wheel_name.substr(0, 7) == w.wheel_name.substr(0, 7):
				w.partner_index = oi
	if nf > 0:
		front_z /= float(nf)
	# the effective rear axle is the centre of all non-steered wheels (tandem trucks)
	if n_rear > 0:
		rear_z /= float(n_rear)
	else:
		rear_z = front_z + 2.6
	wheelbase = maxf(absf(rear_z - front_z), 1.0)
	# Tandem rear axles: each axle follows its own arc around the turn centre, so a six-wheeler
	# turns like a two-axle truck instead of scrubbing (a tiny passive steer, not shown visually).
	for w: VehicleWheel in wheels:
		if w.is_front:
			w.steer_ratio = 1.0
		elif absf(w.rest_pos.z - rear_z) > 0.05:
			w.steer_ratio = -(w.rest_pos.z - rear_z) / wheelbase
	track_width = maxf(absf(right_x - left_x), 0.8)
	_wheel_ref_z = (front_z + rear_z) * 0.5
	_has_wheel_ref = true
	_model_rest = model.transform
	_lean_pivot = Vector3((left_x + right_x) * 0.5, wheels[0].radius, _wheel_ref_z)


func _get_reference_z() -> float:
	return _wheel_ref_z if _has_wheel_ref else super._get_reference_z()


func _apply_mass_properties() -> void:
	super._apply_mass_properties()
	_refresh_tuning()


## Recompute everything derived from spec + mods (called on build and after apply_mods).
func _refresh_tuning() -> void:
	if wheels.is_empty():
		return
	_solve_static_loads(mass * GRAV, center_of_mass)
	var omega := TAU * spec.suspension_stiffness * float(mod_stats.get("stiffness", 1.0))
	var zeta := spec.suspension_damping
	var bump := maxf(spec.suspension_travel - spec.suspension_rest_length, 0.05)
	var grip_mult := float(mod_stats.get("grip", 1.0))
	var nf := 0
	var nr := 0
	for w: VehicleWheel in wheels:
		if w.is_front:
			nf += 1
		else:
			nr += 1
	nf = maxi(nf, 1)
	nr = maxi(nr, 1)
	var r_sum := 0.0
	var r_n := 0
	for w: VehicleWheel in wheels:
		var mw := w.static_load / GRAV
		w.stiffness = mw * omega * omega
		w.damping_bump = 2.0 * zeta * mw * omega
		w.damping_rebound = w.damping_bump * spec.suspension_rebound
		w.anti_roll = w.stiffness * spec.anti_roll * float(mod_stats.get("anti_roll", 1.0))
		w.bump = bump
		w.droop = spec.suspension_rest_length
		w.grip = (spec.grip_front if w.is_front else spec.grip_rear) * grip_mult
		w.steers = w.is_front
		w.handbraked = not w.is_front
		w.brake_share = (spec.brake_bias_front / float(nf)) if w.is_front else ((1.0 - spec.brake_bias_front) / float(nr))
		match spec.drivetrain:
			"fwd":
				w.driven = w.is_front
				w.drive_share = (1.0 / float(nf)) if w.is_front else 0.0
			"awd":
				w.driven = true
				w.drive_share = (spec.awd_front_bias / float(nf)) if w.is_front else ((1.0 - spec.awd_front_bias) / float(nr))
			_:
				w.driven = not w.is_front
				w.drive_share = 0.0 if w.is_front else (1.0 / float(nr))
		if w.driven:
			r_sum += w.radius
			r_n += 1
	_wheel_r = (r_sum / float(r_n)) if r_n > 0 else 0.33

	_redline_omega = spec.redline_rpm * TAU / 60.0
	var stock_torque := spec.get_peak_torque()
	var power_mult := float(mod_stats.get("power", 1.0))
	_peak_torque = stock_torque * power_mult
	# Governed top speed: the top gear runs into the rev limiter at this speed. More power raises
	# it with the cube root (as drag-limited top speed would), turbo mods raise it directly.
	_top_speed = spec.top_speed * float(mod_stats.get("top_speed", 1.0)) * pow(power_mult, 0.33)
	var ratios := spec.gear_ratios.duplicate()
	if ratios.is_empty():
		var n := maxi(spec.gear_count, 2)
		for i in n:
			ratios.append(pow(spec.gear_spread, float(n - 1 - i) / float(n - 1)))
	var top_ratio := ratios[ratios.size() - 1]
	var fd := spec.final_drive
	if fd <= 0.0:
		fd = (_redline_omega * _wheel_r * GOVERNOR_FRAC / _top_speed) / top_ratio
	_gear_ratio = PackedFloat32Array()
	for r: float in ratios:
		_gear_ratio.append(r * fd)
	# Drag comes from the STOCK car: at spec.top_speed air + rolling resistance use only
	# TOP_SPEED_RESIST of the available drive force, so the top speed is reached briskly
	# (scaled speeds on a 600 m island) instead of asymptotically.
	if spec.drag_coefficient > 0.0:
		_drag = spec.drag_coefficient
	else:
		var stock_fd := spec.final_drive if spec.final_drive > 0.0 else (_redline_omega * _wheel_r * GOVERNOR_FRAC / spec.top_speed) / top_ratio
		var frac := clampf(spec.top_speed * top_ratio * stock_fd / (_wheel_r * _redline_omega), 0.1, 1.0)
		var f_top := stock_torque * spec.get_torque_factor(frac) * top_ratio * stock_fd * spec.drivetrain_efficiency / _wheel_r
		var roll := spec.rolling_resistance * spec.mass * GRAV
		_drag = maxf((f_top * TOP_SPEED_RESIST - roll) / (spec.top_speed * spec.top_speed), 0.05)
	_brake_force = spec.brake_force * float(mod_stats.get("brake", 1.0))
	_ride_drop = float(mod_stats.get("ride_drop", 0.0))
	_downforce = spec.downforce + float(mod_stats.get("downforce_add", 0.0))
	gear = clampi(gear, -1, _gear_ratio.size())
	if gear == 0:
		gear = 1
	_visual_settled = false


## Static wheel loads W_i = a + b*z_i + c*x_i that carry the weight with zero net moment about
## the centre of mass (works for 4 and 6 wheels).
func _solve_static_loads(weight: float, com: Vector3) -> void:
	var n := float(wheels.size())
	var sz := 0.0
	var sx := 0.0
	var szz := 0.0
	var sxx := 0.0
	var sxz := 0.0
	for w: VehicleWheel in wheels:
		var z := w.rest_pos.z
		var x := w.rest_pos.x
		sz += z
		sx += x
		szz += z * z
		sxx += x * x
		sxz += x * z
	var r0 := Vector3(n, sz, sx)
	var r1 := Vector3(sz - n * com.z, szz - com.z * sz, sxz - com.z * sx)
	var r2 := Vector3(sx - n * com.x, sxz - com.x * sz, sxx - com.x * sx)
	var mtx := Basis(Vector3(r0.x, r1.x, r2.x), Vector3(r0.y, r1.y, r2.y), Vector3(r0.z, r1.z, r2.z))
	var even := weight / n
	if absf(mtx.determinant()) < 1e-6:
		for w: VehicleWheel in wheels:
			w.static_load = even
		return
	var sol := mtx.inverse() * Vector3(weight, 0.0, 0.0)
	for w: VehicleWheel in wheels:
		w.static_load = maxf(sol.x + sol.y * w.rest_pos.z + sol.z * w.rest_pos.x, even * 0.15)


# ==============================================================================================
# input
# ==============================================================================================

func _read_player_input(_delta: float) -> void:
	var fwd := Input.get_action_strength("move_forward")
	var back := Input.get_action_strength("move_back")
	in_steer = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	in_handbrake = Input.is_action_pressed("handbrake")
	# brake first, then reverse (and the other way round when rolling backwards)
	if _fwd_speed > 1.2:
		in_throttle = fwd
		in_brake = back
	elif _fwd_speed < -1.2:
		in_throttle = -back
		in_brake = fwd
	else:
		in_throttle = fwd - back
		in_brake = 0.0


func _wants_wake() -> bool:
	return absf(in_throttle) > 0.01


func _physics_process(delta: float) -> void:
	if _sleep_request:
		_sleep_request = false
		if absf(in_throttle) < 0.01 and not destroyed:
			sleeping = true
			_on_sleep()
	super._physics_process(delta)


func _on_sleep() -> void:
	_brake_lamp = false
	_brake_eff = 0.0
	_skid = 0.0
	_spin_extra = 0.0
	speed_kmh = 0.0
	_fwd_speed = 0.0
	for w: VehicleWheel in wheels:
		w.skid = 0.0
		w.ang_vel = 0.0


func _on_teleported() -> void:
	_rest_t = 0.0
	_sleep_request = false
	_visual_settled = false
	for w: VehicleWheel in wheels:
		w.anchor_valid = false
		w.ang_vel = 0.0
		w.skid = 0.0


# ==============================================================================================
# physics
# ==============================================================================================

func _integrate_vehicle(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	var xf := state.transform
	var b := xf.basis
	var up := b.y
	var fwd := -b.z
	var right := b.x
	var lin := state.linear_velocity
	var ang := state.angular_velocity
	var com := xf.origin + b * center_of_mass
	var v_fwd := lin.dot(fwd)
	var speed := lin.length()

	_grip_env_t -= dt
	if _grip_env_t <= 0.0:
		_grip_env_t = 0.25
		_grip_env = Weather.get_grip_multiplier()
		if is_player_driven:
			_grip_env *= Skills.get_multiplier("driving", 0.97, 1.05)

	_update_drivetrain(dt, v_fwd)
	_update_steering(dt, v_fwd, lin.dot(right))

	# ---------------------------------------------------------------- pass 1: ground contact
	var space := state.get_space_state()
	var n_rays := wheel_rays if wheel_rays > 0 else (3 if is_player_driven else 1)
	grounded_wheels = 0
	var drive_sum := 0.0
	for w: VehicleWheel in wheels:
		if w.detached:
			w.grounded = false
			continue
		var r := w.radius - (FLAT_DROP if w.flat else 0.0)
		var top := w.bump + RAY_EXTRA
		var mount := xf * (w.rest_pos + Vector3(0.0, top, 0.0))
		var ray_len := top + w.droop + r
		var best_x := -INF
		var best_hit := _wheel_cast(space, mount, mount - up * ray_len)
		if not best_hit.is_empty():
			best_x = top - ((mount - (best_hit["position"] as Vector3)).dot(up) - r)
		if n_rays >= 3:
			var off := r * 0.7
			var h := r * 0.7141
			for k in 2:
				var o := mount + fwd * (off if k == 0 else -off)
				var hit2 := _wheel_cast(space, o, o - up * (ray_len - (r - h)))
				if not hit2.is_empty():
					var x2 := top - ((o - (hit2["position"] as Vector3)).dot(up) - h)
					if x2 > best_x + 0.004:
						best_x = x2
						best_hit = hit2
		if best_hit.is_empty():
			w.grounded = false
			w.compression = -w.droop
			w.normal_force = 0.0
			w.anchor_valid = false
			w.collider = null
			w.collider_id = 0
			continue
		w.grounded = true
		grounded_wheels += 1
		w.compression = best_x
		var nrm: Vector3 = best_hit["normal"]
		if nrm.dot(up) < 0.35:
			nrm = up
		w.contact_normal = nrm
		w.contact_point = mount - up * (top - best_x + r)
		var cid: int = best_hit["collider_id"]
		w.surface_timer -= dt
		if cid != w.collider_id or w.surface_timer <= 0.0:
			w.collider_id = cid
			w.collider = best_hit["collider"]
			w.surface_timer = 0.35
			w.set_surface(_surface_for(w.collider, w.contact_point))
		if w.driven:
			drive_sum += w.drive_share

	# ---------------------------------------------------------------- pass 2: forces
	var hold := _throttle_eff < 0.02 and speed < HOLD_SPEED and grounded_wheels > 0
	var total_f := Vector3.ZERO
	var total_t := Vector3.ZERO
	var peak := deg_to_rad(spec.peak_slip_angle)
	var slide := spec.slide_grip
	var roll_lift := 1.0 - spec.roll_influence
	var skid_max := 0.0
	var spin_target := 0.0
	for w: VehicleWheel in wheels:
		if not w.grounded:
			w.skid = 0.0
			w.spinning = false
			if w.driven and absf(_drive_force) > 1.0:
				w.ang_vel = lerpf(w.ang_vel, signf(_drive_force) * (absf(v_fwd) + 6.0) / w.radius, clampf(dt * 4.0, 0.0, 1.0))
			else:
				w.ang_vel = lerpf(w.ang_vel, 0.0 if (in_handbrake and w.handbraked) else v_fwd / w.radius, clampf(dt * 2.0, 0.0, 1.0))
			continue
		var n := w.contact_normal
		var p := w.contact_point
		var rel := p - com
		var vp := lin + ang.cross(rel)
		var other := w.collider as RigidBody3D
		if other != null and not other.freeze and not other.sleeping:
			vp -= other.linear_velocity + other.angular_velocity.cross(p - other.global_position)

		# --- suspension: spring around the modelled pose + damper + bump stop + anti-roll bar
		var x := w.compression
		var f_s := w.static_load + w.stiffness * (x - _ride_drop)
		if x > w.bump:
			f_s += w.stiffness * 3.0 * (x - w.bump)
		var rate := -vp.dot(n)
		f_s += rate * (w.damping_bump if rate > 0.0 else w.damping_rebound)
		if w.partner_index >= 0:
			var ap := wheels[w.partner_index]
			var px := ap.compression if ap.grounded else -ap.droop
			f_s += w.anti_roll * (x - px)
		var nf := clampf(f_s, 0.0, w.static_load * 6.0)
		w.normal_force = nf
		var fn := n * nf
		total_f += fn
		total_t += rel.cross(fn)
		if other != null and nf > 1.0 and not other.freeze and other.mass > 150.0:
			other.apply_force(-fn, p - other.global_position)
		if nf < 1.0:
			w.skid = 0.0
			w.anchor_valid = false
			continue

		# --- tyre frame on the contact plane
		var wf := fwd
		if absf(w.steer) > 0.0001:
			wf = fwd.rotated(up, -w.steer)
		var fdir := wf - n * wf.dot(n)
		var fl := fdir.length()
		if fl < 0.01:
			continue
		fdir /= fl
		var sdir := fdir.cross(n)
		var v_long := vp.dot(fdir)
		var v_lat := vp.dot(sdir)
		var mu := w.grip * w.surface_grip * _grip_env
		if w.flat:
			mu *= FLAT_GRIP
		mu *= clampf(1.08 - 0.08 * nf / w.static_load, 0.8, 1.06)
		var cap := mu * nf
		var m_w := nf / GRAV
		var stop := m_w / dt
		var tyre := Vector3.ZERO
		var r_eff := w.radius
		w.locked = in_handbrake and w.handbraked
		w.spinning = false

		if hold:
			# parked: static friction as a damped spring to an anchor point (no creep on slopes)
			if not w.anchor_valid:
				w.anchor = p
				w.anchor_valid = true
			var d := w.anchor - p
			d -= n * d.dot(n)
			var vpl := vp - n * vp.dot(n)
			var ka := m_w * 900.0
			var f := d * ka - vpl * (m_w * 50.0)
			var fmag := f.length()
			if fmag > cap:
				f *= cap / fmag
				var dl := d.length()
				if dl > 0.0001:
					w.anchor = p + d * minf(1.0, (cap / ka) / dl)
			tyre = f
			w.skid = 0.0
			w.ang_vel = v_long / r_eff
			w.slip_angle = 0.0
		elif w.locked:
			# handbrake: a locked tyre only has kinetic friction, opposing the sliding direction
			w.anchor_valid = false
			var vpl := vp - n * vp.dot(n)
			var sp := vpl.length()
			if sp > 0.02:
				tyre = -vpl / sp * minf(cap * spec.handbrake_grip, sp * stop * 0.85)
			w.skid = clampf(sp / 5.0, 0.0, 1.0)
			w.ang_vel = 0.0
			w.slip_angle = atan2(v_lat, absf(v_long) + 0.8)
		else:
			w.anchor_valid = false
			var drive := 0.0
			var cap_l := cap              # longitudinal limit (launch traction raises it under power)
			var opp := _brake_req * w.brake_share + spec.rolling_resistance * nf
			if w.driven and drive_sum > 0.0:
				var share := w.drive_share / drive_sum
				drive = _drive_force * share
				opp += _engine_brake * share
				# limited-slip differential: a wheel can only put down LSD_BIAS times what its
				# partner on the same axle can (partner load from the previous step)
				var dcap := cap * spec.traction
				var pw: VehicleWheel = wheels[w.partner_index] if w.partner_index >= 0 else null
				if pw != null and pw.grounded:
					var pmu := pw.grip * pw.surface_grip * _grip_env * (FLAT_GRIP if pw.flat else 1.0)
					dcap = minf(dcap, pw.normal_force * pmu * spec.traction * LSD_BIAS)
				if absf(drive) > dcap * 0.95:
					w.spinning = true
					spin_target = maxf(spin_target, minf(9.0, (absf(drive) / maxf(dcap, 1.0) - 1.0) * 10.0 + 1.5))
					drive = signf(drive) * dcap * 0.95
				if absf(drive) > 1.0:
					cap_l = maxf(cap, dcap)
			if w.flat:
				opp += FLAT_DRAG * nf
			opp = minf(opp, cap * 0.96)                       # ABS: braking never locks the wheel
			opp = minf(opp, absf(v_long) * stop * 0.9)        # never reverse the motion in one step
			var f_long := drive - signf(v_long) * opp
			var over := absf(f_long) / maxf(cap_l, 1.0)
			if over > 1.0:
				f_long = signf(f_long) * cap_l * 0.95
				over = 1.0
			var alpha := atan2(v_lat, absf(v_long) + 0.8)
			w.slip_angle = alpha
			var sn := absf(alpha) / peak
			var f_lat := -signf(alpha) * cap * VehicleWheel.slip_curve(sn, slide)
			var lat_cap := absf(v_lat) * stop * 0.85
			f_lat = clampf(f_lat, -lat_cap, lat_cap)
			f_lat *= sqrt(maxf(1.0 - over * over * spec.power_slide, 0.06))
			tyre = fdir * f_long + sdir * f_lat
			w.long_force = f_long
			w.lat_force = f_lat
			var sk := 0.0
			if sn > 1.2:
				sk = clampf((sn - 1.2) * 0.7, 0.0, 1.0) * clampf(absf(v_lat) / 3.0, 0.0, 1.0)
			if w.spinning:
				sk = maxf(sk, 0.75)
			w.skid = sk
			var spin_add := 0.0
			if w.spinning:
				spin_add = signf(drive) * _spin_extra
			w.ang_vel = (v_long + spin_add) / r_eff
		skid_max = maxf(skid_max, w.skid)
		# tyre forces act between the road and the centre of mass height (controls body roll)
		var lift := maxf((com - p).dot(up), 0.0) * roll_lift
		total_f += tyre
		total_t += (rel + up * lift).cross(tyre)

	_skid = lerpf(_skid, skid_max, clampf(dt * 10.0, 0.0, 1.0))
	_spin_extra = lerpf(_spin_extra, spin_target, clampf(dt * 6.0, 0.0, 1.0))

	# ---------------------------------------------------------------- aero + air control
	total_f += -lin * speed * _drag
	if grounded_wheels >= 2 and _downforce > 0.0:
		total_f += -up * _downforce * v_fwd * v_fwd
	if grounded_wheels == 0:
		airborne_time += dt
		if airborne_time > 0.1 and state.get_contact_count() == 0:
			# gentle levelling so jumps land on the wheels
			var i_avg := (inertia.x + inertia.z) * 0.5
			total_t += up.cross(Vector3.UP) * i_avg * 5.5
			total_t += -ang * i_avg * 1.4
	else:
		airborne_time = 0.0

	state.apply_central_force(total_f)
	state.apply_torque(total_t)

	# ---------------------------------------------------------------- rest detection
	if hold and grounded_wheels == wheels.size() and speed < 0.06 and ang.length_squared() < 0.004 and not horn_on:
		_rest_t += dt
		if _rest_t > 0.9:
			_rest_t = 0.0
			_sleep_request = true
	else:
		_rest_t = 0.0


func _wheel_cast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	_ray_q.from = from
	_ray_q.to = to
	var hit := space.intersect_ray(_ray_q)
	if hit.is_empty():
		return hit
	var rb := hit["collider"] as RigidBody3D
	if rb != null and not rb.freeze and rb.mass < mass * 0.25:
		# light dynamic clutter (cones, bins) is not ground: look through it once
		_ray_q.exclude = [get_rid(), rb.get_rid()]
		hit = space.intersect_ray(_ray_q)
		_ray_q.exclude = _self_exclude
	return hit


func _surface_for(collider: Object, pos: Vector3) -> String:
	var node := collider as Node
	var guard := 0
	while node != null and guard < 4:
		if node.has_meta("surface"):
			return str(node.get_meta("surface"))
		if node.is_in_group("vehicle"):
			return "metal"
		node = node.get_parent()
		guard += 1
	if Game.world != null and Game.world.has_method("get_surface_at"):
		return str(Game.world.get_surface_at(pos))
	return "asphalt"


func _update_drivetrain(dt: float, v_fwd: float) -> void:
	var thr := in_throttle
	var brk := in_brake
	if not engine_on or stalled:
		thr = 0.0
	if thr < -0.02:
		if v_fwd > 2.0:
			brk = maxf(brk, -thr)       # reverse requested while rolling forward: brake first
			thr = 0.0
		else:
			gear = -1
	elif thr > 0.02 and gear == -1:
		if v_fwd < -2.0:
			brk = maxf(brk, thr)
			thr = 0.0
		else:
			gear = 1
	_brake_lamp = brk > 0.1
	if driver == null and not _scripted:
		brk = maxf(brk, 0.3)            # abandoned cars roll to a stop
	var t_abs := absf(thr)
	if in_handbrake and t_abs < 0.05 and spec.handbrake_brake_assist > 0.0:
		# the locked rear wheels ignore the service brake, so this only drags the fronts
		brk = maxf(brk, spec.handbrake_brake_assist)
	_throttle_eff = t_abs
	_brake_eff = brk

	var n_gears := _gear_ratio.size()
	var ratio := _gear_ratio[0] if gear == -1 else _gear_ratio[clampi(gear - 1, 0, n_gears - 1)]
	var wheel_omega := absf(v_fwd) / _wheel_r
	var frac_wheel := wheel_omega * ratio / _redline_omega
	var idle_frac := spec.idle_rpm / spec.redline_rpm
	var frac := maxf(frac_wheel, lerpf(idle_frac, 0.42, t_abs))     # clutch slip when pulling away

	_shift_t = maxf(_shift_t - dt, 0.0)
	_shift_cd = maxf(_shift_cd - dt, 0.0)
	if gear >= 1 and _shift_cd <= 0.0 and grounded_wheels > 0:
		if frac_wheel > 0.93 and gear < n_gears and t_abs > 0.05:
			gear += 1
			_begin_shift()
		elif gear > 1:
			var lower := wheel_omega * _gear_ratio[gear - 2] / _redline_omega
			if lower < (0.86 if t_abs > 0.85 else 0.6):
				gear -= 1
				_begin_shift()

	var force := 0.0
	if engine_on and t_abs > 0.0 and _shift_t <= 0.0:
		var tf := spec.get_torque_factor(frac)
		if frac_wheel >= 1.0:
			tf = 0.0
		elif frac_wheel > 0.97:
			tf *= (1.0 - frac_wheel) / 0.03
		force = _peak_torque * tf * t_abs * get_power_factor() * ratio * spec.drivetrain_efficiency * float(mod_stats.get("drive", 1.0)) / _wheel_r
		if gear == -1:
			force *= -clampf((spec.reverse_speed - absf(v_fwd)) / 2.0, 0.0, 1.0)
	_drive_force = force
	_brake_req = brk * _brake_force
	_engine_brake = spec.engine_braking * mass if (t_abs < 0.05 and engine_on and absf(v_fwd) > 1.0) else 0.0

	# engine speed for audio (includes wheelspin flare)
	var audio_frac := maxf(frac, (absf(v_fwd) + _spin_extra) / _wheel_r * ratio / _redline_omega)
	var target_rpm := clampf(audio_frac, idle_frac, 1.0) * spec.redline_rpm if engine_on else 0.0
	rpm = lerpf(rpm, target_rpm, clampf(dt * 10.0, 0.0, 1.0))


func _begin_shift() -> void:
	_shift_t = spec.shift_time * float(mod_stats.get("shift_time", 1.0))
	_shift_cd = _shift_t + 0.3
	if _throttle_eff > 0.7:
		_exhaust_req = 1


func _update_steering(dt: float, v_fwd: float, v_right: float) -> void:
	var max_a := deg_to_rad(spec.max_steer_angle)
	var sp := absf(v_fwd)
	var limit := max_a
	if sp > 4.0:
		var mu := (spec.grip_front + spec.grip_rear) * 0.5 * _grip_env
		limit = minf(max_a, atan(wheelbase * mu * GRAV / (sp * sp)) + deg_to_rad(spec.high_speed_steer_slip))
	var target := in_steer * limit
	if damage != null:
		target += damage.steer_pull * limit
	if spec.drift_assist > 0.0 and v_fwd > 6.0:
		var beta := atan2(v_right, v_fwd)
		if absf(beta) > 0.035:
			target += (beta - signf(beta) * 0.035) * spec.drift_assist
	target = clampf(target, -max_a, max_a)
	var returning := absf(target) < absf(steer_angle) or signf(target) != signf(steer_angle)
	var rate := (spec.steer_return_rate if returning else spec.steer_rate) * max_a * lerpf(1.0, 0.5, clampf(sp / 40.0, 0.0, 1.0))
	steer_angle = move_toward(steer_angle, target, rate * dt)
	steer_norm = steer_angle / max_a
	for w: VehicleWheel in wheels:
		if w.steer_ratio != 0.0:
			w.steer = steer_angle * w.steer_ratio


# ==============================================================================================
# visuals
# ==============================================================================================

func _update_visuals(delta: float) -> void:
	if sleeping and _visual_settled:
		return
	var moving := not sleeping
	var k := clampf(delta * 22.0, 0.0, 1.0)
	var lean_inv := _update_lean(delta)
	for w: VehicleWheel in wheels:
		if w.node == null or w.detached or not is_instance_valid(w.node):
			continue
		if moving:
			w.spin_angle = fposmod(w.spin_angle + w.ang_vel * delta, TAU)
		var target := clampf(w.compression, -w.droop, w.bump + 0.03)
		w.visual_offset = lerpf(w.visual_offset, target, k)
		var wb := Basis(Vector3.UP, -w.steer if w.steers else 0.0) * Basis(Vector3.RIGHT, -w.spin_angle) * w.rest_basis
		w.node.transform = w.parent_inv * lean_inv * Transform3D(wb, w.rest_pos + Vector3(0.0, w.visual_offset, 0.0))
	_update_steering_wheel(steer_norm)
	_visual_settled = sleeping
	_update_exhaust(delta)
	if moving and detail_level == 0 and _skid > 0.4:
		_fx_t -= delta
		if _fx_t <= 0.0:
			_fx_t = 0.08
			for w: VehicleWheel in wheels:
				if w.grounded and w.skid > 0.4 and not w.is_front:
					if w.surface == "asphalt" or w.surface == "concrete":
						Fx.tire_smoke(w.contact_point, w.skid)
					else:
						Fx.dust(w.contact_point, w.skid)


## Cosmetic tail-pipe puffs: a hard upshift under load or a full-throttle launch from low speed.
func _update_exhaust(delta: float) -> void:
	_exhaust_t = maxf(_exhaust_t - delta, 0.0)
	if detail_level != 0 or not engine_on or destroyed:
		_exhaust_req = 0
		return
	if _exhaust_req == 0 and _throttle_eff > 0.85 and absf(get_forward_speed()) < 6.0 and grounded_wheels > 0:
		_exhaust_req = 2
	if _exhaust_req != 0 and _exhaust_t <= 0.0:
		exhaust_puff("light", 0.3 if _exhaust_req == 1 else 0.4)
		_exhaust_t = 0.35 if _exhaust_req == 1 else 0.5
	_exhaust_req = 0


## Visual body lean: the shell (the whole model except the wheels) exaggerates the small physical
## roll / pitch measured from the suspension, so cornering, braking and launches read clearly
## without making the physics tippy. Returns the inverse lean transform (body space) that keeps
## the wheels exactly where the simulation has them.
func _update_lean(delta: float) -> Transform3D:
	var gain := spec.body_lean - 1.0
	if model == null or (gain <= 0.001 and not _lean_active):
		return Transform3D.IDENTITY
	var roll_t := 0.0
	var pitch_t := 0.0
	if not destroyed and grounded_wheels >= 3 and gain > 0.001:
		var cl := 0.0
		var cr := 0.0
		var cf := 0.0
		var cb := 0.0
		var nl := 0
		var nr := 0
		var nf := 0
		var nb := 0
		for w: VehicleWheel in wheels:
			if w.detached:
				continue
			var c := clampf(w.compression, -w.droop, w.bump)
			if w.is_left:
				cl += c
				nl += 1
			else:
				cr += c
				nr += 1
			if w.is_front:
				cf += c
				nf += 1
			else:
				cb += c
				nb += 1
		if nl > 0 and nr > 0 and nf > 0 and nb > 0:
			roll_t = clampf((cl / float(nl) - cr / float(nr)) / track_width * gain, -LEAN_ROLL_MAX, LEAN_ROLL_MAX)
			pitch_t = clampf((cf / float(nf) - cb / float(nb)) / wheelbase * gain, -LEAN_PITCH_MAX, LEAN_PITCH_MAX)
	var kl := clampf(delta * 9.0, 0.0, 1.0)
	_lean_roll = lerpf(_lean_roll, roll_t, kl)
	_lean_pitch = lerpf(_lean_pitch, pitch_t, kl)
	var on := absf(_lean_roll) > 0.0003 or absf(_lean_pitch) > 0.0003
	if not on:
		if _lean_active:
			_lean_active = false
			_lean_roll = 0.0
			_lean_pitch = 0.0
			model.transform = _model_rest
		return Transform3D.IDENTITY
	_lean_active = true
	# +Z is the tail: a positive turn about it drops the left side; a negative turn about +X drops the nose
	var lb := Basis(Vector3.BACK, _lean_roll) * Basis(Vector3.RIGHT, -_lean_pitch)
	var lean := Transform3D(lb, _lean_pivot - lb * _lean_pivot)
	model.transform = lean * _model_rest
	return lean.affine_inverse()


## Extra visual lean of the shell in degrees: x = roll (+ left side down), y = pitch (+ nose down).
func get_body_lean_degrees() -> Vector2:
	return Vector2(rad_to_deg(_lean_roll), rad_to_deg(_lean_pitch))


# ==============================================================================================
# queries / damage hooks
# ==============================================================================================

func is_braking() -> bool:
	return in_brake > 0.1 or in_handbrake or (_brake_lamp and not sleeping)


func is_reversing() -> bool:
	return gear == -1 and engine_on and (in_throttle < -0.02 or _fwd_speed < -0.3)


func get_rpm_factor() -> float:
	return clampf(rpm / maxf(spec.redline_rpm, 1.0), 0.0, 1.0)


func get_engine_load() -> float:
	return _throttle_eff


func get_skid_amount() -> float:
	return _skid


func get_wheel_count() -> int:
	return wheels.size()


func get_wheel_position(index: int) -> Vector3:
	if index < 0 or index >= wheels.size():
		return global_position
	return global_transform * wheels[index].rest_pos


func get_wheel_radius(index: int) -> float:
	if index < 0 or index >= wheels.size():
		return 0.33
	return wheels[index].radius


func get_wheel_node(index: int) -> Node3D:
	if index < 0 or index >= wheels.size():
		return null
	return wheels[index].node


func is_tire_flat(index: int) -> bool:
	return index >= 0 and index < wheels.size() and wheels[index].flat


func get_wheel_rest_basis(index: int) -> Basis:
	if index < 0 or index >= wheels.size():
		return Basis.IDENTITY
	return wheels[index].rest_basis


func pop_tire(index: int) -> void:
	if index < 0 or index >= wheels.size():
		return
	var w := wheels[index]
	if w.flat or w.detached:
		return
	w.flat = true
	_visual_settled = false
	if is_inside_tree():
		sleeping = false
		Audio.play_at("tire_pop", get_wheel_position(index), 0.0, randf_range(0.9, 1.1), 50.0)


## Removes a wheel from the simulation and returns its visual node (for wreck debris).
func detach_wheel(index: int) -> Node3D:
	if index < 0 or index >= wheels.size():
		return null
	var w := wheels[index]
	if w.detached:
		return null
	w.detached = true
	w.grounded = false
	return w.node


func _on_destroyed() -> void:
	_drive_force = 0.0
	_skid = 0.0
	for w: VehicleWheel in wheels:
		w.skid = 0.0
		w.ang_vel = 0.0
		w.anchor_valid = false


func _on_repaired() -> void:
	for w: VehicleWheel in wheels:
		w.flat = false
		w.detached = false
		w.reset_state()
		if w.node != null and is_instance_valid(w.node):
			w.node.visible = true
	_visual_settled = false
	_rest_t = 0.0


## Numbers for HUD / debug overlays.
func get_telemetry() -> Dictionary:
	return {"gear": gear, "rpm": rpm, "speed_kmh": speed_kmh, "steer": steer_norm, "grounded": grounded_wheels,
			"skid": _skid, "throttle": _throttle_eff, "brake": _brake_eff}
