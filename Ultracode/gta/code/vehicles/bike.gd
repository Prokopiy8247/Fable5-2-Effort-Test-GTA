class_name Bike
extends VehicleBase
## Two-wheeler: motorcycle ("bike") and bicycle ("bicycle") on the shared VehicleBase.
##
## Physics (all in `_integrate_vehicle`, 60 Hz, forces only):
##   * two in-line raycast wheels (three rays each so kerbs are climbed smoothly), spring + damper
##     around the modelled pose, slip-angle tyres with a friction ellipse (same model as Car)
##   * the rigid body is held upright by a roll PD controller; tyre side forces act at the height of
##     the centre of mass, so cornering never tips the hull. The VISUAL model (wheels, rider and
##     all) leans about the tyre contact line by atan(v * yaw_rate / g) - the lean the turn needs.
##   * engine: power-limited drive force with a governed top speed (motorcycle) or pedal power with
##     a sprint boost that drains the rider's stamina (bicycle); front + rear brakes, rear lock on
##     the handbrake, slow reverse (paddling / walking the bike back)
##   * crashes: a hard hull impact, a slide far past the tyre limit at speed ("lowside") or being
##     knocked past 35 degrees throws the rider (player.ragdoll through on_vehicle_ejected, NPCs
##     through knock_down) and the bike falls over. It stays down until somebody mounts it again,
##     then a short scripted roll stands it back up.
##
## Per-spec tuning that VehicleSpec has no fields for lives in the spec meta "bike" (Dictionary,
## keys = DEFAULTS below), set by res://gta/resources/registries/vehicles_bikeboat_registry.gd.
## Docs: docs/BIKES_BOATS.md.

const GRAV := 9.81
const RAY_EXTRA := 0.2           ## rays start this far above full bump
const HOLD_SPEED := 0.6          ## below this, with a closed throttle, the tyres hold position
const FLAT_GRIP := 0.55
const FLAT_DRAG := 0.3
const FALL_TILT_COS := 0.82      ## cos(35 deg): tipped further than this -> falls
const NO_TYRE_TILT_COS := 0.6    ## tyres stop working beyond ~53 deg of roll
const LONG_LEVER := 0.5          ## share of the COM height that brake / drive forces act at (load transfer, no wheelies)
const HIST := 8                  ## physics frames of velocity history (pre-impact velocity of a crash)

const DEFAULTS := {
	"pedal": false,              ## bicycle: pedal power instead of an engine
	"power_kw": 70.0,            ## motorcycle engine power
	"pedal_watts": 420.0,        ## bicycle: sustained pedal power
	"sprint_watts": 950.0,       ## bicycle: pedal power while sprinting (drains stamina)
	"max_drive_accel": 8.0,      ## drive force cap at low speed = mass * this (m/s^2)
	"max_lean_deg": 50.0,        ## visual lean limit
	"lean_rate": 6.0,            ## 1/s smoothing of the visual lean
	"crash_dv": 8.5,             ## velocity change (m/s) of a hull impact that throws the rider
	"crash_dv_ground": 14.0,     ## same for impacts from below (hard landings)
	"lowside_slip_deg": 30.0,    ## tyre slip angle beyond which a fast slide ends in a crash
	"lowside_speed": 10.0,       ## m/s
	"rider_mass": 80.0,          ## kg used for the throw impulse
	"crank_ratio": 2.7,          ## rear wheel turns per crank turn (bicycle)
	"rider_lean_fwd": 0.38,      ## torso pitch of the rider (rad)
	"gears": 6,                  ## virtual gears of the engine sound
	"upright_hz": 2.4,           ## roll controller natural frequency
	"upright_damping": 0.95,
	"stand_bias": 0.0,           ## unused (bikes stand straight when parked)
}

var wheels: Array[VehicleWheel] = []     ## [front, rear]
var is_bicycle: bool = false
var fallen: bool = false                 ## lying on its side after a crash (until mounted again)
var lean: float = 0.0                    ## visual lean in radians, + = right side down
var steer_angle: float = 0.0             ## road angle, + = right
var steer_norm: float = 0.0
var grounded_wheels: int = 0
var airborne_time: float = 0.0
var rpm: float = 0.0
var gear: int = 1
var wheelbase: float = 1.4
var pedal_effort: float = 0.0            ## bicycle 0..1 (audio, crank, stamina)
var sprinting: bool = false
var crash_count: int = 0                 ## crashes since spawn (tests / debug)
var last_crash_reason: String = ""

var _p: Dictionary = {}
var _power_w: float = 70000.0
var _max_drive: float = 2000.0
var _top_speed: float = 50.0
var _drag: float = 0.3
var _brake_force: float = 3000.0
var _drive_force: float = 0.0
var _brake_req: float = 0.0
var _engine_brake: float = 0.0
var _throttle_eff: float = 0.0
var _brake_lamp: bool = false
var _grip_env: float = 1.0
var _grip_env_t: float = 0.0
var _skid: float = 0.0
var _rest_t: float = 0.0
var _sleep_request: bool = false
var _lowside_t: float = 0.0
var _max_slip: float = 0.0
var _visual_settled: bool = false
var _model_rest: Transform3D = Transform3D.IDENTITY
var _handlebar: Node3D = null
var _handlebar_rest: Transform3D = Transform3D.IDENTITY     ## body space
var _handlebar_parent_inv: Transform3D = Transform3D.IDENTITY
var _steer_axis: Vector3 = Vector3.UP                       ## body space
var _steer_pivot: Vector3 = Vector3.ZERO                    ## body space
var _crank: Node3D = null
var _crank_rest: Transform3D = Transform3D.IDENTITY
var _crank_angle: float = 0.0
var _crank_speed: float = 0.0
var _self_exclude: Array[RID] = []
var _hist: PackedVector3Array = PackedVector3Array()
var _hist_i: int = 0
var _fallen_t: float = 0.0
var _spark_req: Vector3 = Vector3.INF
var _spark_t: float = 0.0
var _fx_t: float = 0.0
var _stamina_xp_t: float = 0.0
var _hull_material: PhysicsMaterial = null
var _audio_was: bool = true
var _pending_fall: String = ""          ## fall requested inside the physics callback (handled in _physics_process)
var _pending_carry: Vector3 = Vector3.ZERO
var _prev_ang: Vector3 = Vector3.ZERO


# ==============================================================================================
# build
# ==============================================================================================

func _build_drive(_opts: Dictionary) -> void:
	_p = DEFAULTS.duplicate()
	var meta: Variant = spec.get_meta("bike", {}) if spec.has_meta("bike") else {}
	if meta is Dictionary:
		for k: Variant in meta:
			_p[k] = meta[k]
	is_bicycle = bool(_p["pedal"]) or vehicle_class == "bicycle"
	self_righting = false            # a fallen bike stays down until somebody mounts it
	_self_exclude = [get_rid()]
	_hist.resize(HIST)
	_hull_material = physics_material_override
	for nm: String in ["Wheel_F", "Wheel_R"]:
		var n := get_part(nm)
		var w := VehicleWheel.new()
		w.wheel_name = nm
		w.is_front = nm == "Wheel_F"
		w.node = n
		if n != null:
			var xf := xform_in_body(n)
			w.rest_pos = xf.origin
			w.rest_basis = xf.basis
			var par := n.get_parent() as Node3D
			if par != null and par != self:
				w.parent_inv = xform_in_body(par).affine_inverse()
			var a := aabb_in_body(n)
			var measured := maxf(a.size.y, a.size.z) * 0.5
			w.radius = spec.wheel_radius if spec.wheel_radius > 0.0 else (measured if measured > 0.1 else 0.32)
			w.width = maxf(a.size.x, 0.05)
			body_aabb = body_aabb.merge(a)
		else:
			push_warning("Bike %s: model has no %s - using an invisible wheel" % [spec_id, nm])
			w.radius = spec.wheel_radius if spec.wheel_radius > 0.0 else 0.32
			var c := body_aabb.get_center()
			w.rest_pos = Vector3(0.0, w.radius, c.z + (-0.45 if w.is_front else 0.45) * body_aabb.size.z)
		w.steers = w.is_front
		w.steer_ratio = 1.0 if w.is_front else 0.0
		w.driven = not w.is_front
		w.handbraked = not w.is_front
		wheels.append(w)
	wheelbase = maxf(absf(wheels[1].rest_pos.z - wheels[0].rest_pos.z), 0.6)
	_model_rest = model.transform
	# handlebar: steers about the raked Steer_Axis (its local +Y), the front wheel turns with it
	_handlebar = get_part("Handlebar")
	if _handlebar != null:
		_handlebar_rest = xform_in_body(_handlebar)
		var par := _handlebar.get_parent() as Node3D
		if par != null and par != self:
			_handlebar_parent_inv = xform_in_body(par).affine_inverse()
		body_aabb = body_aabb.merge(aabb_in_body(_handlebar))
		_steer_pivot = _handlebar_rest.origin
	var axis_node := get_part("Steer_Axis")
	if axis_node != null:
		var ax := xform_in_body(axis_node)
		_steer_axis = ax.basis.y.normalized()
		_steer_pivot = ax.origin
	elif _handlebar != null:
		_steer_axis = _handlebar_rest.basis.y.normalized()
	_crank = get_part("Crank")
	if _crank != null:
		_crank_rest = _crank.transform
	_add_wheel_hulls()


## Thin boxes over the upper half of each wheel so head-on hits stop at the tyre, not at the
## frame behind it (the hull helper only covers the frame). Above the hull clearance: kerbs and
## ramps are still handled by the suspension rays.
func _add_wheel_hulls() -> void:
	var floor_y := maxf(spec.hull_clearance, 0.12)
	var i := 0
	for w: VehicleWheel in wheels:
		var top := w.rest_pos.y + w.radius
		if top - floor_y < 0.1:
			continue
		var box := BoxShape3D.new()
		box.size = Vector3(maxf(w.width, 0.08), top - floor_y, w.radius * 1.8)
		var cs := CollisionShape3D.new()
		cs.name = "WheelHull%d" % i
		cs.shape = box
		cs.position = Vector3(w.rest_pos.x, (top + floor_y) * 0.5, w.rest_pos.z)
		add_child(cs)
		i += 1


func _get_reference_z() -> float:
	if wheels.size() == 2:
		return (wheels[0].rest_pos.z + wheels[1].rest_pos.z) * 0.5
	return super._get_reference_z()


func _apply_mass_properties() -> void:
	super._apply_mass_properties()
	_refresh_tuning()


func _on_mods_changed() -> void:
	_refresh_tuning()


## Everything derived from spec + mod_stats (called on build and after apply_mods).
func _refresh_tuning() -> void:
	if wheels.size() != 2:
		return
	var weight := mass * GRAV
	var zf := wheels[0].rest_pos.z
	var zr := wheels[1].rest_pos.z
	var com_z := center_of_mass.z
	var front_share := clampf((zr - com_z) / (zr - zf), 0.2, 0.8)
	wheels[0].static_load = weight * front_share
	wheels[1].static_load = weight * (1.0 - front_share)
	var omega := TAU * spec.suspension_stiffness * float(mod_stats.get("stiffness", 1.0))
	var zeta := spec.suspension_damping
	var bump := maxf(spec.suspension_travel - spec.suspension_rest_length, 0.04)
	var grip_mult := float(mod_stats.get("grip", 1.0))
	for w: VehicleWheel in wheels:
		var mw := w.static_load / GRAV
		w.stiffness = mw * omega * omega
		w.damping_bump = 2.0 * zeta * mw * omega
		w.damping_rebound = w.damping_bump * spec.suspension_rebound
		w.anti_roll = 0.0
		w.bump = bump
		w.droop = spec.suspension_rest_length
		w.grip = (spec.grip_front if w.is_front else spec.grip_rear) * grip_mult
		w.brake_share = spec.brake_bias_front if w.is_front else 1.0 - spec.brake_bias_front
		w.drive_share = 0.0 if w.is_front else 1.0
	var power_mult := float(mod_stats.get("power", 1.0))
	if is_bicycle:
		_power_w = float(_p["pedal_watts"])
		var vt := maxf(spec.top_speed, 3.0)
		var roll := spec.rolling_resistance * spec.mass * GRAV
		_drag = maxf((_power_w / vt - roll) / (vt * vt), 0.05)
		_top_speed = vt
	else:
		_power_w = float(_p["power_kw"]) * 1000.0 * power_mult
		_top_speed = spec.top_speed * float(mod_stats.get("top_speed", 1.0)) * pow(power_mult, 0.33)
		if spec.drag_coefficient > 0.0:
			_drag = spec.drag_coefficient
		else:
			var f_top := float(_p["power_kw"]) * 1000.0 / spec.top_speed
			var roll2 := spec.rolling_resistance * spec.mass * GRAV
			_drag = maxf((f_top * 0.6 - roll2) / (spec.top_speed * spec.top_speed), 0.05)
	_max_drive = mass * float(_p["max_drive_accel"]) * float(mod_stats.get("drive", 1.0))
	_brake_force = spec.brake_force * float(mod_stats.get("brake", 1.0))
	_visual_settled = false


# ==============================================================================================
# input / occupants
# ==============================================================================================

func _read_player_input(_delta: float) -> void:
	var fwd := Input.get_action_strength("move_forward")
	var back := Input.get_action_strength("move_back")
	in_steer = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	in_handbrake = Input.is_action_pressed("handbrake")
	sprinting = is_bicycle and Input.is_action_pressed("sprint")
	if _fwd_speed > 1.0:
		in_throttle = fwd
		in_brake = back
	elif _fwd_speed < -0.8:
		in_throttle = -back
		in_brake = fwd
	else:
		in_throttle = fwd - back
		in_brake = 0.0


func set_inputs(throttle: float, steer: float, brake: float, handbrake: bool = false) -> void:
	super.set_inputs(throttle, steer, brake, handbrake)
	if not is_player_driven:
		sprinting = false


func _wants_wake() -> bool:
	return absf(in_throttle) > 0.01


func can_enter(who: Node) -> bool:
	if fallen:
		if destroyed or locked or not _built:
			return false
		if is_inside_tree() and linear_velocity.length() > 2.0:
			return false
		return get_free_seat() >= 0
	return super.can_enter(who)


func occupant_enter(who: Node, seat: int = 0) -> void:
	var was_fallen := fallen
	_mute_doors(true)
	super.occupant_enter(who, seat)
	_mute_doors(false)
	if seat == 0 and engine_on and not is_bicycle and audio != null:
		audio.play_start()
	if was_fallen and seat == 0 and is_inside_tree():
		_stand_up()
	if who != null and is_instance_valid(who):
		_tune_rider.call_deferred(who, seat)


func occupant_exit(seat: int = 0) -> Transform3D:
	var moving := is_inside_tree() and linear_velocity.length() > 4.0
	_mute_doors(true)
	var xf := super.occupant_exit(seat)
	_mute_doors(false)
	if seat == 0 and moving and not fallen and driver == null:
		_fall_over("bailed", Vector3.ZERO)
	return xf


## The base plays door sounds on enter / exit; two-wheelers have no doors.
func _mute_doors(on: bool) -> void:
	if on:
		_audio_was = audio_active
		audio_active = false
	else:
		audio_active = _audio_was


func start_engine() -> bool:
	if is_bicycle:
		if destroyed:
			return false
		engine_on = true
		return true
	return super.start_engine()


func exhaust_puff(kind: String = "light", scale: float = 0.35) -> void:
	if is_bicycle:
		return
	super.exhaust_puff(kind, scale)


## Hand / foot / torso tuning of the rider's procedural seated pose from the model's markers
## (Grip_L/R, Footrest_R or the Crank). Soft: only touches an `animator` that has these fields.
func _tune_rider(who: Node, seat: int) -> void:
	if who == null or not is_instance_valid(who) or get_occupant(seat) != who:
		return
	var a: Variant = who.get("animator")
	if a == null or not is_instance_valid(a) or not ("bar_pos" in a):
		return
	var seat_node := get_seat_node(seat)
	if seat_node == null:
		return
	var inv := xform_in_body(seat_node).affine_inverse()
	if seat == 0:
		var gl := get_part("Grip_L")
		var gr := get_part("Grip_R")
		if gl != null and gr != null:
			var pl := inv * _rest_point(gl)
			var pr := inv * _rest_point(gr)
			a.set("bar_pos", (pl + pr) * 0.5)
			a.set("bar_half_width", clampf(absf(pr.x - pl.x) * 0.5, 0.15, 0.4))
	var peg := Vector3.INF
	var fr := get_part("Footrest_R")
	if fr != null and seat == 0:
		peg = inv * _rest_point(fr) + Vector3(0.0, 0.07, 0.0)
	elif _crank != null and seat == 0:
		peg = inv * xform_in_body(_crank).origin + Vector3(0.13, 0.08, 0.0)
	if peg != Vector3.INF and "peg_pos" in a:
		a.set("peg_pos", Vector3(absf(peg.x), peg.y, peg.z))
	if "bike_lean_fwd" in a:
		a.set("bike_lean_fwd", float(_p["rider_lean_fwd"]))


## Body-space position of a marker in the rest pose (undoing the current visual lean / steer).
func _rest_point(n: Node3D) -> Vector3:
	var p := xform_in_body(n).origin
	var lean_xf := model.transform * _model_rest.affine_inverse()
	return lean_xf.affine_inverse() * p


# ==============================================================================================
# physics
# ==============================================================================================

func _physics_process(delta: float) -> void:
	if _sleep_request:
		_sleep_request = false
		if absf(in_throttle) < 0.01 and not destroyed:
			sleeping = true
			_on_sleep()
	if _pending_fall != "":
		var why := _pending_fall
		_pending_fall = ""
		_fall_over(why, _pending_carry)
	super._physics_process(delta)
	if is_bicycle and is_player_driven and driver != null and is_instance_valid(driver):
		_update_stamina(delta)


func _update_stamina(delta: float) -> void:
	var d := driver
	var draining := sprinting and _throttle_eff > 0.1 and absf(_fwd_speed) > 1.0
	if d.has_method("update_stamina"):
		d.call("update_stamina", delta, draining)
	if draining:
		var st: Variant = d.get("stamina")
		if st != null and float(st) <= 0.0:
			sprinting = false
	# pedalling trains stamina a little even without sprinting
	if _throttle_eff > 0.2 and absf(_fwd_speed) > 3.0:
		_stamina_xp_t += delta
		if _stamina_xp_t >= 1.0:
			_stamina_xp_t = 0.0
			Skills.add_xp("stamina", 0.01)


func _on_sleep() -> void:
	_brake_lamp = false
	_skid = 0.0
	speed_kmh = 0.0
	_fwd_speed = 0.0
	pedal_effort = 0.0
	for w: VehicleWheel in wheels:
		w.skid = 0.0
		w.ang_vel = 0.0


func _on_teleported() -> void:
	_rest_t = 0.0
	_sleep_request = false
	_visual_settled = false
	_lowside_t = 0.0
	lean = 0.0
	for i in HIST:
		_hist[i] = Vector3.ZERO
	for w: VehicleWheel in wheels:
		w.anchor_valid = false
		w.ang_vel = 0.0
		w.skid = 0.0


## Same guard as Boat: a teleported character body must not kick the bike across the map.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _built and (state.linear_velocity - _prev_lin).length() > 4.0:
		for i in state.get_contact_count():
			if state.get_contact_collider_object(i) is CharacterBody3D:
				state.linear_velocity = _prev_lin
				state.angular_velocity = _prev_ang
				break
	_prev_ang = state.angular_velocity
	super._integrate_forces(state)


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
	_hist[_hist_i] = lin
	_hist_i = (_hist_i + 1) % HIST

	_grip_env_t -= dt
	if _grip_env_t <= 0.0:
		_grip_env_t = 0.25
		_grip_env = Weather.get_grip_multiplier()
		if is_player_driven:
			_grip_env *= Skills.get_multiplier("driving", 0.97, 1.05)

	var tilt := up.dot(Vector3.UP)
	if fallen:
		_integrate_fallen(state, speed, tilt)
		return
	if tilt < FALL_TILT_COS:
		_request_fall("knocked", lin)
		return

	_update_drive(dt, v_fwd)
	_update_steering(dt, v_fwd)

	var total_f := Vector3.ZERO
	var total_t := Vector3.ZERO

	# ---------------------------------------------------------------- upright controller (roll)
	var roll_err := fwd.dot(up.cross(Vector3.UP))
	var roll_rate := ang.dot(fwd)
	var wn := TAU * float(_p["upright_hz"])
	var zeta := float(_p["upright_damping"])
	var h := maxf(center_of_mass.y, 0.2)
	var t_roll := inertia.z * (wn * wn * roll_err - 2.0 * zeta * wn * roll_rate) + mass * GRAV * h * roll_err
	total_t += fwd * t_roll

	# ---------------------------------------------------------------- pass 1: ground contact
	var space := state.get_space_state()
	grounded_wheels = 0
	for w: VehicleWheel in wheels:
		if w.detached or tilt < NO_TYRE_TILT_COS:
			w.grounded = false
			continue
		var r := w.radius - (0.03 if w.flat else 0.0)
		var top := w.bump + RAY_EXTRA
		var mount := xf * (w.rest_pos + Vector3(0.0, top, 0.0))
		var ray_len := top + w.droop + r
		var best_x := -INF
		var best_hit := _wheel_cast(space, mount, mount - up * ray_len)
		if not best_hit.is_empty():
			best_x = top - ((mount - (best_hit["position"] as Vector3)).dot(up) - r)
		var off := r * 0.7
		var hh := r * 0.7141
		for k in 2:
			var o := mount + fwd * (off if k == 0 else -off)
			var hit2 := _wheel_cast(space, o, o - up * (ray_len - (r - hh)))
			if not hit2.is_empty():
				var x2 := top - ((o - (hit2["position"] as Vector3)).dot(up) - hh)
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

	# ---------------------------------------------------------------- pass 2: tyre forces
	var hold := _throttle_eff < 0.02 and speed < HOLD_SPEED and grounded_wheels > 0
	var peak := deg_to_rad(spec.peak_slip_angle)
	var slide := spec.slide_grip
	var skid_max := 0.0
	_max_slip = 0.0
	for w: VehicleWheel in wheels:
		if not w.grounded:
			w.skid = 0.0
			if w.driven and absf(_drive_force) > 1.0:
				w.ang_vel = lerpf(w.ang_vel, signf(_drive_force) * (absf(v_fwd) + 4.0) / w.radius, clampf(dt * 4.0, 0.0, 1.0))
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

		# suspension around the modelled pose
		var x := w.compression
		var f_s := w.static_load + w.stiffness * x
		if x > w.bump:
			f_s += w.stiffness * 3.0 * (x - w.bump)
		var rate := -vp.dot(n)
		f_s += rate * (w.damping_bump if rate > 0.0 else w.damping_rebound)
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
		var mu := w.grip * w.surface_grip * _grip_env * (FLAT_GRIP if w.flat else 1.0)
		mu *= clampf(1.08 - 0.08 * nf / w.static_load, 0.8, 1.06)
		var cap := mu * nf
		var m_w := nf / GRAV
		var stop := m_w / dt
		var f_long := 0.0
		var f_lat := 0.0
		var tyre_planar := Vector3.ZERO
		w.locked = in_handbrake and w.handbraked
		if hold:
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
			tyre_planar = f
			w.skid = 0.0
			w.ang_vel = v_long / w.radius
			w.slip_angle = 0.0
		elif w.locked:
			w.anchor_valid = false
			var vpl2 := vp - n * vp.dot(n)
			var sp := vpl2.length()
			if sp > 0.02:
				tyre_planar = -vpl2 / sp * minf(cap * spec.handbrake_grip, sp * stop * 0.85)
			w.skid = clampf(sp / 5.0, 0.0, 1.0)
			w.ang_vel = 0.0
			w.slip_angle = atan2(v_lat, absf(v_long) + 0.8)
		else:
			w.anchor_valid = false
			var drive := 0.0
			var cap_l := cap
			var opp := _brake_req * w.brake_share + spec.rolling_resistance * nf
			if w.driven:
				drive = _drive_force
				opp += _engine_brake
				var dcap := cap * spec.traction
				if absf(drive) > dcap * 0.95:
					drive = signf(drive) * dcap * 0.95
					w.spinning = true
				else:
					w.spinning = false
				if absf(drive) > 1.0:
					cap_l = maxf(cap, dcap)
			if w.flat:
				opp += FLAT_DRAG * nf
			opp = minf(opp, cap * 0.96)
			opp = minf(opp, absf(v_long) * stop * 0.9)
			f_long = drive - signf(v_long) * opp
			var over := absf(f_long) / maxf(cap_l, 1.0)
			if over > 1.0:
				f_long = signf(f_long) * cap_l * 0.95
				over = 1.0
			var alpha := atan2(v_lat, absf(v_long) + 0.8)
			w.slip_angle = alpha
			var sn := absf(alpha) / peak
			f_lat = -signf(alpha) * cap * VehicleWheel.slip_curve(sn, slide)
			var lat_cap := absf(v_lat) * stop * 0.85
			f_lat = clampf(f_lat, -lat_cap, lat_cap)
			f_lat *= sqrt(maxf(1.0 - over * over * spec.power_slide, 0.06))
			w.long_force = f_long
			w.lat_force = f_lat
			var sk := 0.0
			if sn > 1.3:
				sk = clampf((sn - 1.3) * 0.7, 0.0, 1.0) * clampf(absf(v_lat) / 3.0, 0.0, 1.0)
			if w.spinning:
				sk = maxf(sk, 0.6)
			w.skid = sk
			w.ang_vel = v_long / w.radius
		skid_max = maxf(skid_max, w.skid)
		_max_slip = maxf(_max_slip, absf(w.slip_angle))
		# lateral forces act at the COM height (no roll from cornering); longitudinal ones lower
		# down, so braking dives the fork and accelerating squats the rear without wheelies
		var lift := maxf((com - p).dot(up), 0.0)
		var lat_vec := sdir * f_lat
		var long_vec := fdir * f_long
		if hold or w.locked:
			var lat_part := sdir * tyre_planar.dot(sdir)
			lat_vec = lat_part
			long_vec = tyre_planar - lat_part
		total_f += lat_vec + long_vec
		total_t += (rel + up * lift).cross(lat_vec) + (rel + up * lift * LONG_LEVER).cross(long_vec)

	_skid = lerpf(_skid, skid_max, clampf(dt * 10.0, 0.0, 1.0))

	# ---------------------------------------------------------------- aero + air control
	total_f += -lin * speed * _drag
	if grounded_wheels == 0:
		airborne_time += dt
		if airborne_time > 0.1 and state.get_contact_count() == 0:
			# gentle pitch levelling so jumps land on both wheels
			var pitch_err := right.dot(up.cross(Vector3.UP))
			total_t += right * (inertia.x * (16.0 * pitch_err - 4.0 * ang.dot(right)))
	else:
		airborne_time = 0.0

	state.apply_central_force(total_f)
	state.apply_torque(total_t)

	# ---------------------------------------------------------------- lowside: sliding far past the tyre limit at speed
	if _max_slip > deg_to_rad(float(_p["lowside_slip_deg"])) and speed > float(_p["lowside_speed"]) and grounded_wheels > 0:
		_lowside_t += dt
		if _lowside_t > 0.3:
			_lowside_t = 0.0
			_request_fall("lowside", lin)
			return
	else:
		_lowside_t = maxf(_lowside_t - dt * 2.0, 0.0)

	# ---------------------------------------------------------------- rest detection
	if hold and grounded_wheels == 2 and speed < 0.06 and ang.length_squared() < 0.004 and not horn_on:
		_rest_t += dt
		if _rest_t > 0.9:
			_rest_t = 0.0
			_sleep_request = true
	else:
		_rest_t = 0.0


## Lying on the side (or tipping over): no tyres, no controller; the hull slides to a stop on a
## grippy material, throwing sparks on hard ground, then sleeps.
func _integrate_fallen(state: PhysicsDirectBodyState3D, speed: float, _tilt: float) -> void:
	var dt := state.step
	grounded_wheels = 0
	_drive_force = 0.0
	_fallen_t += dt
	_skid = 0.0
	for w: VehicleWheel in wheels:
		w.grounded = false
		w.ang_vel = lerpf(w.ang_vel, 0.0, clampf(dt * 0.8, 0.0, 1.0))
	var lin := state.linear_velocity
	state.apply_central_force(-lin * speed * _drag)
	if speed > 2.5 and state.get_contact_count() > 0:
		_spark_req = state.get_contact_local_position(0)
	if speed < 0.08 and state.angular_velocity.length_squared() < 0.01 and _fallen_t > 1.0:
		_rest_t += dt
		if _rest_t > 1.0:
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


func _update_drive(dt: float, v_fwd: float) -> void:
	var thr := in_throttle
	var brk := in_brake
	var can_drive := (engine_on and not stalled) if not is_bicycle else (driver != null or _scripted)
	if not can_drive:
		thr = 0.0
	if thr < -0.02 and v_fwd > 1.5:
		brk = maxf(brk, -thr)
		thr = 0.0
	elif thr > 0.02 and v_fwd < -1.0:
		brk = maxf(brk, thr)
		thr = 0.0
	if driver == null and not _scripted:
		brk = maxf(brk, 0.3)
	_brake_lamp = brk > 0.1 or in_handbrake
	_throttle_eff = absf(thr)
	var force := 0.0
	var sp := absf(v_fwd)
	if thr > 0.02:
		var pw := _power_w
		if is_bicycle:
			pw = float(_p["sprint_watts"]) if sprinting else float(_p["pedal_watts"])
			if is_player_driven:
				pw *= Skills.get_multiplier("stamina", 1.0, 1.15)
		else:
			pw *= get_power_factor()
		force = minf(pw * thr / maxf(sp, 0.5), _max_drive * thr)
		if not is_bicycle:
			force *= clampf((_top_speed - v_fwd) / (0.03 * _top_speed), 0.0, 1.0)
	elif thr < -0.02:
		# reverse: paddling / walking the bike back, slowly
		force = -mass * 1.4 * (-thr) * clampf((spec.reverse_speed - sp) / 0.8, 0.0, 1.0)
	_drive_force = force
	_brake_req = brk * _brake_force
	_engine_brake = spec.engine_braking * mass if (not is_bicycle and _throttle_eff < 0.05 and engine_on and sp > 1.0) else 0.0
	pedal_effort = lerpf(pedal_effort, _throttle_eff * (1.0 if not sprinting else 1.6) if is_bicycle else 0.0, clampf(dt * 5.0, 0.0, 1.0))
	if is_bicycle:
		engine_on = (driver != null or _scripted) and not destroyed and sp > 0.4
		rpm = sp / maxf(_top_speed * 1.3, 1.0)
		return
	# engine sound: virtual sequential gearbox over the speed range
	var n_gears := maxi(int(_p["gears"]), 1)
	var frac := clampf(sp / maxf(_top_speed, 1.0), 0.0, 1.0)
	var gpos := pow(frac, 0.8) * float(n_gears)
	gear = clampi(int(gpos) + 1, 1, n_gears)
	var in_gear := gpos - float(gear - 1)
	var idle_frac := spec.idle_rpm / spec.redline_rpm
	var target := lerpf(0.42, 0.97, clampf(in_gear, 0.0, 1.0)) if sp > 1.0 else lerpf(idle_frac, 0.5, _throttle_eff)
	if grounded_wheels == 0 and _throttle_eff > 0.3:
		target = 1.0
	if not engine_on:
		target = 0.0
	rpm = lerpf(rpm, target * spec.redline_rpm, clampf(dt * 9.0, 0.0, 1.0))


func _update_steering(dt: float, v_fwd: float) -> void:
	var max_a := deg_to_rad(spec.max_steer_angle)
	var sp := absf(v_fwd)
	var limit := max_a
	if sp > 3.0:
		var mu := (spec.grip_front + spec.grip_rear) * 0.5 * _grip_env
		limit = minf(max_a, atan(wheelbase * mu * GRAV / (sp * sp)) + deg_to_rad(spec.high_speed_steer_slip))
	var target := in_steer * limit
	if damage != null:
		target += damage.steer_pull * limit * 0.5
	target = clampf(target, -max_a, max_a)
	var returning := absf(target) < absf(steer_angle) or signf(target) != signf(steer_angle)
	var rate := (spec.steer_return_rate if returning else spec.steer_rate) * max_a * lerpf(1.0, 0.45, clampf(sp / 30.0, 0.0, 1.0))
	steer_angle = move_toward(steer_angle, target, rate * dt)
	steer_norm = steer_angle / max_a
	wheels[0].steer = steer_angle


# ==============================================================================================
# crashes
# ==============================================================================================

func _on_collision(other: Node, dv: float, pos: Vector3, normal: Vector3, pre_speed: float) -> void:
	super._on_collision(other, dv, pos, normal, pre_speed)
	if fallen or destroyed or not is_inside_tree() or _recover_t >= 0.0:
		return
	if other != null and is_instance_valid(other) and VehicleBase._is_character(other):
		return
	var limit := float(_p["crash_dv"])
	if absf(normal.y) > 0.7:
		limit = float(_p["crash_dv_ground"])      # landing / bottoming out
	var rb := other as RigidBody3D
	if rb != null and rb.mass < mass * 0.3 and not rb.is_in_group("vehicle"):
		limit *= 2.0                              # light clutter (bins, cones)
	if dv < limit:
		return
	var pre := _pre_impact_velocity()
	_fall_over("crash", pre)


## Physics-callback safe: the fall (and the rider's ejection) happens in the next _physics_process.
func _request_fall(reason: String, carry: Vector3) -> void:
	if _pending_fall == "" and not fallen:
		_pending_fall = reason
		_pending_carry = carry


## Fastest velocity of the last HIST physics frames (the speed the rider had before the hit).
func _pre_impact_velocity() -> Vector3:
	var best := Vector3.ZERO
	for v: Vector3 in _hist:
		if v.length_squared() > best.length_squared():
			best = v
	return best


## Throw the riders off and let the bike fall over. `carry` = velocity the riders keep.
func _fall_over(reason: String, carry: Vector3) -> void:
	if fallen:
		return
	fallen = true
	_fallen_t = 0.0
	_rest_t = 0.0
	_lowside_t = 0.0
	crash_count += 1
	last_crash_reason = reason
	can_sleep = true
	if _hull_material != null:
		_hull_material.friction = 0.75
	var rm := float(_p["rider_mass"])
	var impulse := carry * rm * 0.8 + Vector3.UP * rm * (2.2 + carry.length() * 0.08)
	for i in _seat_occupants.size():
		_throw_seat(i, impulse)
	# tip over towards the lean (or a random side)
	if is_inside_tree():
		var gt := global_transform
		# + about the forward axis drops the right side; fall the way the bike was leaning
		var side := signf(lean) if absf(lean) > 0.03 else (1.0 if Game.rng.randf() < 0.5 else -1.0)
		var fwd := -gt.basis.z
		sleeping = false
		apply_torque_impulse(fwd * side * inertia.z * 2.6)
		if (reason == "lowside" or reason == "knocked") and audio != null:
			audio.play_crash(maxf(carry.length() * 0.5, 4.0), global_position)
	lean = 0.0
	_drive_force = 0.0
	_clear_inputs()


## Like VehicleBase._evict(), but the rider leaves from the seat itself (thrown over the bars).
func _throw_seat(seat: int, impulse: Vector3) -> void:
	var who := get_occupant(seat)
	if who == null:
		return
	var xf := get_exit_transform(seat)
	var sn := get_seat_node(seat)
	if sn != null and is_instance_valid(sn) and sn.is_inside_tree():
		var sp := sn.global_position
		var f := -global_transform.basis.z
		f.y = 0.0
		var yaw := atan2(-f.x, -f.z) if f.length_squared() > 0.001 else 0.0
		xf = Transform3D(Basis(Vector3.UP, yaw), sp + Vector3.UP * 0.1)
	_seat_occupants[seat] = null
	if who == driver:
		_driver_left()
	if who.has_method("on_vehicle_ejected"):
		who.call("on_vehicle_ejected", self, xf, impulse)
	elif who.has_method("exit_vehicle") and who.get("current_vehicle") == self:
		who.call("exit_vehicle")
		if who.has_method("ragdoll"):
			who.call("ragdoll", impulse, 2.0)
	elif who is Node3D and is_ancestor_of(who):
		var n3 := who as Node3D
		n3.reparent(Game.get_entities_root(), false)
		n3.global_transform = xf
		if n3.has_method("knock_down"):
			n3.call("knock_down", impulse)
	elif who.has_method("knock_down"):
		who.call("knock_down", impulse)


## Mounting a fallen bike: a short scripted roll puts it back on its wheels.
func _stand_up() -> void:
	fallen = false
	_fallen_t = 0.0
	if _hull_material != null:
		_hull_material.friction = spec.hull_friction
	_begin_self_right()


func _begin_self_right() -> void:
	super._begin_self_right()
	fallen = false


## Where to stand to pick a fallen bike up: beside it in its heading frame.
func get_exit_transform(seat: int = 0) -> Transform3D:
	if not fallen or not is_inside_tree():
		return super.get_exit_transform(seat)
	var gt := global_transform
	var f := -gt.basis.z
	f.y = 0.0
	if f.length_squared() < 0.01:
		f = gt.basis.y
		f.y = 0.0
	var yaw := atan2(-f.x, -f.z) if f.length_squared() > 0.0001 else 0.0
	var upright := Transform3D(Basis(Vector3.UP, yaw), get_center_position())
	var space := get_world_3d().direct_space_state
	for dist: float in [0.9, 1.5]:
		for side: float in [-1.0, 1.0]:
			var res := _probe_exit(space, upright * Vector3(side * dist, 0.0, 0.0), gt.origin.y)
			if res.x != INF:
				return Transform3D(upright.basis, res)
	return Transform3D(upright.basis, gt.origin + Vector3.UP * 0.3)


# ==============================================================================================
# damage hooks
# ==============================================================================================

## Bicycles are not destroyed: hits wear them down to half health at most (no smoke, no fire)
## and a blast or a big hit knocks them over.
func apply_damage(info: Dictionary) -> void:
	if not is_bicycle:
		super.apply_damage(info)
		_knock_check(info)
		return
	if destroyed:
		return
	var amount := float(info.get("amount", 0.0))
	if amount <= 0.0:
		return
	var floor_h := max_health * 0.5
	var capped := info.duplicate()
	capped["amount"] = minf(amount, maxf(health - floor_h, 0.0) / 3.3 + 0.01)
	super.apply_damage(capped)
	health = maxf(health, floor_h)
	_knock_check(info)


func _knock_check(info: Dictionary) -> void:
	if fallen or destroyed or not is_inside_tree():
		return
	var type := str(info.get("type", ""))
	var amount := float(info.get("amount", 0.0))
	if type == "explosion" and amount > 30.0:
		var dir: Vector3 = info.get("direction", Vector3.UP)
		_fall_over("blast", dir * 6.0)


func explode(instigator: Node = null) -> void:
	if is_bicycle:
		if not fallen:
			_fall_over("blast", Vector3.UP * 4.0)
		return
	super.explode(instigator)


func _on_destroyed() -> void:
	_drive_force = 0.0
	_skid = 0.0
	if not fallen:
		fallen = true
	for w: VehicleWheel in wheels:
		w.skid = 0.0
		w.ang_vel = 0.0


func _on_repaired() -> void:
	for w: VehicleWheel in wheels:
		w.flat = false
		w.detached = false
		w.reset_state()
		if w.node != null and is_instance_valid(w.node):
			w.node.visible = true
	_visual_settled = false
	_rest_t = 0.0
	if fallen and is_inside_tree():
		_stand_up()


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


func detach_wheel(index: int) -> Node3D:
	if index < 0 or index >= wheels.size():
		return null
	var w := wheels[index]
	if w.detached:
		return null
	w.detached = true
	w.grounded = false
	return w.node


# ==============================================================================================
# visuals
# ==============================================================================================

func _process(delta: float) -> void:
	super._process(delta)
	if _spark_req != Vector3.INF:
		_spark_t -= delta
		if _spark_t <= 0.0 and detail_level == 0:
			_spark_t = 0.09
			Fx.sparks(_spark_req, Vector3.UP, 0.6)
		_spark_req = Vector3.INF


func _update_visuals(delta: float) -> void:
	if sleeping and _visual_settled:
		return
	var moving := not sleeping
	var k := clampf(delta * 20.0, 0.0, 1.0)
	# visual lean: the angle a real bike needs for this turn (v * yaw rate = lateral acceleration)
	var target_lean := 0.0
	if not fallen and not destroyed and moving and grounded_wheels > 0 and _recover_t < 0.0:
		var gt := global_transform
		var v_fwd := linear_velocity.dot(-gt.basis.z)
		var yaw_rate := angular_velocity.dot(gt.basis.y)
		var max_lean := deg_to_rad(float(_p["max_lean_deg"]))
		target_lean = clampf(atan(v_fwd * -yaw_rate / GRAV), -max_lean, max_lean) * clampf(absf(v_fwd) / 3.0, 0.0, 1.0)
	lean = lerpf(lean, target_lean, clampf(delta * float(_p["lean_rate"]), 0.0, 1.0))
	if absf(lean) > 0.0005:
		model.transform = Transform3D(Basis(Vector3.BACK, -lean), Vector3.ZERO) * _model_rest
	elif model.transform != _model_rest:
		model.transform = _model_rest
	# steering: handlebar (fork, lamp, bars) about the raked axis, the front wheel with it
	var vis_steer := steer_angle * 1.1
	var steer_xf := Transform3D.IDENTITY
	if absf(vis_steer) > 0.0001:
		var rb := Basis(_steer_axis, -vis_steer)
		steer_xf = Transform3D(rb, _steer_pivot - rb * _steer_pivot)
	if _handlebar != null and is_instance_valid(_handlebar):
		_handlebar.transform = _handlebar_parent_inv * steer_xf * _handlebar_rest
	for w: VehicleWheel in wheels:
		if w.node == null or w.detached or not is_instance_valid(w.node):
			continue
		if moving:
			w.spin_angle = fposmod(w.spin_angle + w.ang_vel * delta, TAU)
		var target := clampf(w.compression, -w.droop, w.bump + 0.03) if w.grounded else -w.droop
		w.visual_offset = lerpf(w.visual_offset, target, k)
		var travel_dir := _steer_axis if w.is_front else Vector3.UP
		var wb := Basis(Vector3.RIGHT, -w.spin_angle) * w.rest_basis
		var wx := Transform3D(wb, w.rest_pos + travel_dir * (w.visual_offset / maxf(travel_dir.y, 0.5)))
		if w.is_front:
			wx = steer_xf * wx
		w.node.transform = w.parent_inv * wx
	# crank: turns with the rear wheel while pedalling, freewheels (stops) when coasting
	if _crank != null and is_instance_valid(_crank):
		var want := 0.0
		if moving and _throttle_eff > 0.05 and wheels[1].grounded and not fallen:
			want = wheels[1].ang_vel / maxf(float(_p["crank_ratio"]), 0.5)
		_crank_speed = lerpf(_crank_speed, want, clampf(delta * 6.0, 0.0, 1.0))
		if absf(_crank_speed) > 0.01:
			_crank_angle = fposmod(_crank_angle + _crank_speed * delta, TAU)
			_crank.transform = _crank_rest * Transform3D(Basis(Vector3.RIGHT, -_crank_angle), Vector3.ZERO)
	_visual_settled = sleeping
	# tyre smoke / dust from a sliding rear tyre
	if moving and detail_level == 0 and _skid > 0.45:
		_fx_t -= delta
		if _fx_t <= 0.0:
			_fx_t = 0.09
			var w := wheels[1]
			if w.grounded and w.skid > 0.45:
				if w.surface == "asphalt" or w.surface == "concrete":
					Fx.tire_smoke(w.contact_point, w.skid * 0.7)
				else:
					Fx.dust(w.contact_point, w.skid)


# ==============================================================================================
# queries
# ==============================================================================================

func is_braking() -> bool:
	return in_brake > 0.1 or in_handbrake or (_brake_lamp and not sleeping)


func is_reversing() -> bool:
	return in_throttle < -0.02 and _fwd_speed < 0.3 and not fallen


func get_rpm_factor() -> float:
	if is_bicycle:
		return clampf(rpm, 0.0, 1.0)
	return clampf(rpm / maxf(spec.redline_rpm, 1.0), 0.0, 1.0)


func get_engine_load() -> float:
	if is_bicycle:
		return clampf(pedal_effort * 0.6 + absf(_fwd_speed) / maxf(_top_speed * 2.0, 1.0), 0.0, 1.0)
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
		return 0.32
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


## Visual lean of the bike in degrees (+ = right side down).
func get_lean_degrees() -> float:
	return rad_to_deg(lean)


## Same shape as Car.get_body_lean_degrees() (x = roll, + = left side down; y = pitch).
func get_body_lean_degrees() -> Vector2:
	return Vector2(-rad_to_deg(lean), 0.0)


func is_fallen() -> bool:
	return fallen


func get_telemetry() -> Dictionary:
	return {"gear": gear, "rpm": rpm, "speed_kmh": speed_kmh, "steer": steer_norm, "grounded": grounded_wheels,
			"lean_deg": rad_to_deg(lean), "skid": _skid, "throttle": _throttle_eff, "fallen": fallen,
			"pedal": pedal_effort, "sprint": sprinting}
