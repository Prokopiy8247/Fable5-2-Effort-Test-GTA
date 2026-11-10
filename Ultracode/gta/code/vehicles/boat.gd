class_name Boat
extends VehicleBase
## Powered boat (speedboat, jetski, dinghy) on the shared VehicleBase.
##
## Physics (all in `_integrate_vehicle`, 60 Hz, forces only):
##   * buoyancy: a grid of hull sample points (from the `Col_Body` bounds) at the design draft; each
##     is a spring-damper against the sea surface of the environment system
##     (`get_wave_height(x, z)`, fallback Game.WATER_LEVEL). Spring rates carry the weight with the
##     hull level at the authored waterline (model origin), capped at the freeboard (reserve buoyancy)
##   * planing: speed-dependent virtual lift offsets per sample point raise the hull, lift the bow
##     (hump around 55 % of the planing speed, settling at full plane) and bank the boat into turns
##   * anisotropic water drag: light along the keel (linear + quadratic, less once planing), strong
##     sideways (applied behind the centre of mass, so the hull tracks like a keel), yaw / roll /
##     pitch damping - all scaled by how much of the hull is in the water
##   * thrust at the `Prop` marker, only while the propeller is under the surface, vectored by the
##     steerable `Motor` (outboard / jet nozzle); a rudder force from the flow over the leg keeps
##     it steerable when coasting; reverse thrust brakes. Aground with the prop out of the water,
##     reverse throttle still pushes the boat off slowly (`beach_push`)
##   * moored boats (BoatSpawner) hang on a soft, damped line until somebody boards them
##
## Per-spec tuning lives in the spec meta "boat" (keys = DEFAULTS), set by
## res://gta/resources/registries/vehicles_bikeboat_registry.gd. Docs: docs/BIKES_BOATS.md.

const GRAV := 9.81
const MAX_POINTS := 12
const DEFAULTS := {
	"draft": 0.3,             ## depth of the sample points below the waterline at rest (m)
	"freeboard": 0.6,         ## buoyancy cap above the waterline (reserve buoyancy)
	"thrust_accel": 3.4,      ## full thrust = mass * this (N)
	"reverse_thrust": 0.45,   ## share of the thrust available astern
	"plane_speed": 12.0,      ## m/s at which the hull is fully on the plane
	"bow_rise_deg": 6.5,      ## peak bow-up trim (at ~55 % of the planing speed)
	"plane_rise": 0.12,       ## m the hull rises out of the water on the plane
	"bank_deg": 9.0,          ## max bank into a turn
	"righting_gm": 0.9,       ## m: extra righting lever of the hull (W * gm * sin(roll error))
	"ground_drag": 1.2,       ## x mass per m/s while the hull drags over the seabed / a beach
	"rudder": 1.0,            ## side force of the flow over the leg / nozzle
	"yaw_damping": 1.6,       ## x inertia
	"lateral_drag": 1.6,      ## x mass per m/s of side slip
	"coast_drag": 0.16,       ## x mass per m/s along the keel (displacement speeds)
	"heave_damping": 0.35,    ## damping ratio of the buoyancy springs
	"roll_damping": 1.2,      ## x inertia
	"samples_x": 2,
	"samples_z": 4,
	"beach_push": 0.6,        ## share of the reverse thrust that works with the prop out of the water
	"rider_pose": "",         ## "bike" = the rider straddles (jetski) - see get_rider_pose()
}

var afloat: bool = false                 ## at least one hull sample is in the water
var submerged: float = 0.0               ## share of the hull samples in the water (0..1)
var prop_in_water: bool = false
var aground: bool = false                ## hull touching the ground while (partly) out of the water
var steer_angle: float = 0.0             ## leg / nozzle angle, + = turning right
var steer_norm: float = 0.0
var rpm: float = 0.0                     ## 0..1
var moored: bool = false                 ## hanging on a mooring line (BoatSpawner)
var trim_deg: float = 0.0                ## measured bow-up pitch (debug / tests)
var bank_deg: float = 0.0                ## measured roll, + = right side down

var _p: Dictionary = {}
var _pts: PackedVector3Array = PackedVector3Array()      ## body space, at the waterline (y = 0)
var _pk: PackedFloat32Array = PackedFloat32Array()        ## spring rate per sample (N/m)
var _pc: PackedFloat32Array = PackedFloat32Array()        ## damper per sample (N s/m)
var _pdepth: PackedFloat32Array = PackedFloat32Array()    ## last real depth per sample
var _zc: float = 0.0
var _hull_len: float = 6.0
var _hull_beam: float = 2.0
var _prop_local: Vector3 = Vector3(0.0, -0.4, 3.0)
var _bow_local: Vector3 = Vector3(0.0, 0.0, -3.0)
var _thrust: float = 4000.0
var _drag_q: float = 8.0
var _throttle_eff: float = 0.0
var _env: Node = null
var _env_t: float = 0.0
var _motor: Node3D = null
var _motor_rest: Transform3D = Transform3D.IDENTITY
var _handlebar: Node3D = null
var _handlebar_rest: Transform3D = Transform3D.IDENTITY
var _handlebar_parent_inv: Transform3D = Transform3D.IDENTITY
var _steer_axis: Vector3 = Vector3.UP
var _steer_pivot: Vector3 = Vector3.ZERO
var _wake_markers: Array[Node3D] = []
var _wake_handles: Array[Node3D] = []
var _moor_xf: Transform3D = Transform3D.IDENTITY
var _spray_t: float = 0.0
var _spray_side: float = 1.0
var _slam_req: float = 0.0               ## > 0: a bow slam splash of this scale is pending
var _slam_pos: Vector3 = Vector3.ZERO
var _was_afloat: bool = false
var _entry_splash: float = 0.0
var _air_t: float = 0.0
var _audio_was: bool = true
var _sleep_ok: bool = true
var _buoy_f: Vector3 = Vector3.ZERO      ## result of _buoyancy(): force
var _buoy_t: Vector3 = Vector3.ZERO      ## result of _buoyancy(): torque about the centre of mass
var _hull_material: PhysicsMaterial = null
var _want_friction: float = -1.0
var _prev_ang: Vector3 = Vector3.ZERO
var _ring_t: float = 0.0


# ==============================================================================================
# build
# ==============================================================================================

func _build_drive(_opts: Dictionary) -> void:
	_p = DEFAULTS.duplicate()
	var meta: Variant = spec.get_meta("boat", {}) if spec.has_meta("boat") else {}
	if meta is Dictionary:
		for k: Variant in meta:
			_p[k] = meta[k]
	self_righting = true
	_hull_material = physics_material_override
	var hull := body_aabb
	var col := get_part("Col_Body")
	if col != null:
		var a := aabb_in_body(col)
		if a.size.length() > 0.5:
			hull = a
	_hull_len = maxf(hull.size.z, 1.0)
	_hull_beam = maxf(hull.size.x, 0.5)
	var nx := clampi(int(_p["samples_x"]), 1, 3)
	var nz := clampi(int(_p["samples_z"]), 2, 6)
	_pts = PackedVector3Array()
	for iz in nz:
		var f := lerpf(0.12, 0.9, float(iz) / float(nz - 1))
		var z := hull.position.z + _hull_len * f
		# the bow is narrower: pull the forward samples in
		var taper := lerpf(0.55, 1.0, clampf(f / 0.45, 0.0, 1.0))
		for ix in nx:
			var x := 0.0
			if nx > 1:
				x = lerpf(-1.0, 1.0, float(ix) / float(nx - 1)) * _hull_beam * 0.4 * taper
			# forces act at the waterline; the depth is measured from the bottom (draft below)
			_pts.append(Vector3(hull.get_center().x + x, 0.0, z))
	_pk.resize(_pts.size())
	_pc.resize(_pts.size())
	_pdepth.resize(_pts.size())
	_prop_local = marker_local("Prop", Vector3(0.0, -float(_p["draft"]) - 0.2, hull.end.z))
	_bow_local = Vector3(hull.get_center().x, 0.0, hull.position.z + _hull_len * 0.08)
	_motor = get_part("Motor")
	if _motor != null:
		_motor_rest = _motor.transform
	_handlebar = get_part("Handlebar")
	if _handlebar != null:
		_handlebar_rest = xform_in_body(_handlebar)
		var par := _handlebar.get_parent() as Node3D
		if par != null and par != self:
			_handlebar_parent_inv = xform_in_body(par).affine_inverse()
		_steer_pivot = _handlebar_rest.origin
		_steer_axis = _handlebar_rest.basis.y.normalized()
		var axis_node := get_part("Steer_Axis")
		if axis_node != null:
			var ax := xform_in_body(axis_node)
			_steer_axis = ax.basis.y.normalized()
			_steer_pivot = ax.origin
	for nm: String in ["Wake_L", "Wake_R"]:
		var w := get_part(nm)
		if w != null:
			_wake_markers.append(w)


## Hull samples are measured from the body centre: the centre of mass sits over the middle of the hull.
func _get_reference_z() -> float:
	var col := get_part("Col_Body")
	if col != null:
		var a := aabb_in_body(col)
		if a.size.length() > 0.5:
			return a.get_center().z
	return super._get_reference_z()


func _apply_mass_properties() -> void:
	super._apply_mass_properties()
	_refresh_tuning()


func _on_mods_changed() -> void:
	_refresh_tuning()


func _refresh_tuning() -> void:
	var n := _pts.size()
	if n == 0:
		return
	var weight := mass * GRAV
	var com := center_of_mass
	_zc = com.z
	# static share per sample: W_i = a + b z' + c x' with zero net moment about the centre of mass
	var sz := 0.0
	var sx := 0.0
	var szz := 0.0
	var sxx := 0.0
	var sxz := 0.0
	for p: Vector3 in _pts:
		var z := p.z - com.z
		var x := p.x - com.x
		sz += z
		sx += x
		szz += z * z
		sxx += x * x
		sxz += x * z
	var fn := float(n)
	var mtx := Basis(Vector3(fn, sz, sx), Vector3(sz, szz, sxz), Vector3(sx, sxz, sxx))
	var sol := Vector3(weight / fn, 0.0, 0.0)
	if absf(mtx.determinant()) > 1e-6:
		sol = mtx.inverse() * Vector3(weight, 0.0, 0.0)
	var draft := float(_p["draft"])
	var zeta := float(_p["heave_damping"])
	for i in n:
		var z := _pts[i].z - com.z
		var x := _pts[i].x - com.x
		var w := maxf(sol.x + sol.y * z + sol.z * x, weight / fn * 0.15)
		_pk[i] = w / draft
		_pc[i] = 2.0 * zeta * sqrt(_pk[i] * w / GRAV)
	var power := float(mod_stats.get("power", 1.0))
	_thrust = mass * float(_p["thrust_accel"]) * power
	# quadratic drag so the thrust left over at top speed (after the planing linear drag) holds it there
	var top := spec.top_speed * float(mod_stats.get("top_speed", 1.0)) * pow(power, 0.33)
	var lin_top := mass * float(_p["coast_drag"]) * 0.35 * top
	_drag_q = maxf((_thrust - lin_top) / (top * top), 0.5)


# ==============================================================================================
# inputs / occupants
# ==============================================================================================

func _read_player_input(_delta: float) -> void:
	in_throttle = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	in_steer = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	in_brake = 0.0
	in_handbrake = Input.is_action_pressed("handbrake")


func _wants_wake() -> bool:
	return absf(in_throttle) > 0.01 or not _sleep_ok


## AI / scripted driving casts off the mooring line as soon as it applies throttle.
func set_inputs(throttle: float, steer: float, brake: float, handbrake: bool = false) -> void:
	super.set_inputs(throttle, steer, brake, handbrake)
	if absf(throttle) > 0.01 and not is_player_driven:
		moored = false


func occupant_enter(who: Node, seat: int = 0) -> void:
	moored = false
	_audio_was = audio_active
	audio_active = false          # no door sounds on a boat
	super.occupant_enter(who, seat)
	audio_active = _audio_was
	if seat == 0 and engine_on and audio != null:
		audio.play_start()
	if who != null and is_instance_valid(who):
		_tune_rider.call_deferred(who, seat)


func occupant_exit(seat: int = 0) -> Transform3D:
	_audio_was = audio_active
	audio_active = false
	var xf := super.occupant_exit(seat)
	audio_active = _audio_was
	return xf


## Seated pose the rider should use: "seated_bike" when straddling (jetski), else "seated_car".
func get_rider_pose(_seat: int = 0) -> String:
	return "seated_bike" if str(_p.get("rider_pose", "")) == "bike" else "seated_car"


## Jetski: hands on the Grip_L/R markers, feet in the footwells (soft: only an animator with
## these fields is touched).
func _tune_rider(who: Node, seat: int) -> void:
	if who == null or not is_instance_valid(who) or get_occupant(seat) != who or seat != 0:
		return
	var a: Variant = who.get("animator")
	if a == null or not is_instance_valid(a) or not ("bar_pos" in a):
		return
	var sn := get_seat_node(seat)
	var gl := get_part("Grip_L")
	var gr := get_part("Grip_R")
	if sn == null or gl == null or gr == null:
		return
	var inv := xform_in_body(sn).affine_inverse()
	var pl := inv * xform_in_body(gl).origin
	var pr := inv * xform_in_body(gr).origin
	a.set("bar_pos", (pl + pr) * 0.5)
	a.set("bar_half_width", clampf(absf(pr.x - pl.x) * 0.5, 0.15, 0.4))
	var fr := get_part("Footrest_R")
	if fr != null and "peg_pos" in a:
		var pp := inv * xform_in_body(fr).origin + Vector3(0.0, 0.08, 0.0)
		a.set("peg_pos", Vector3(absf(pp.x), pp.y, pp.z))


func exhaust_puff(_kind: String = "light", _scale: float = 0.35) -> void:
	pass                          # outboards / jets exhaust under water


## BoatSpawner: hang the boat on a soft mooring line at `xform` until somebody boards it.
func set_moored(xform: Transform3D) -> void:
	_moor_xf = xform
	moored = true


## Exits: a dry spot on a pier / the shore right beside the hull, else a standing spot on the deck
## (Exit_* markers above the waterline), else the water beside the boat. A swimmer next to the boat
## is offered the deck spot, so boarding from the water climbs over the side.
func get_exit_transform(seat: int = 0) -> Transform3D:
	if not is_inside_tree():
		return Transform3D.IDENTITY
	var gt := global_transform
	var f := -gt.basis.z
	f.y = 0.0
	if f.length_squared() < 0.0025:
		f = Vector3.FORWARD
	var facing := Basis(Vector3.UP, atan2(-f.x, -f.z))
	var s := clampi(seat, 0, maxi(_seat_nodes.size() - 1, 0))
	var seat_local := xform_in_body(_seat_nodes[s]).origin if s < _seat_nodes.size() else body_aabb.get_center()
	var exit_node: Node3D = _seat_exits[s] if s < _seat_exits.size() else null
	var exit_local := xform_in_body(exit_node).origin if exit_node != null and is_instance_valid(exit_node) else seat_local
	var side := signf(exit_local.x) if absf(exit_local.x) > 0.05 else (signf(seat_local.x) if absf(seat_local.x) > 0.05 else -1.0)
	var half_w := body_aabb.size.x * 0.5
	var upright := gt.basis.y.y > 0.6
	if not _swimmer_near():
		var space := get_world_3d().direct_space_state
		var zc := body_aabb.get_center().z
		for z: float in [seat_local.z, zc, zc - body_aabb.size.z * 0.3, zc + body_aabb.size.z * 0.3]:
			for sd: float in [side, -side]:
				for extra: float in [0.75, 1.35]:
					var w := gt * Vector3(sd * (half_w + extra), 0.0, z)
					var res := _probe_exit(space, w, gt.origin.y + 1.3)
					if res.x != INF:
						return Transform3D(facing, res)
	if upright and exit_local.y > 0.25:
		return Transform3D(facing, gt * exit_local + Vector3.UP * 0.03)
	var wp := gt * Vector3(side * (half_w + 0.8), 0.0, seat_local.z)
	wp.y = _wave_y(wp.x, wp.z)
	return Transform3D(facing, wp)


func _swimmer_near() -> bool:
	var pl := Game.player
	if pl == null or not is_instance_valid(pl) or not pl.is_inside_tree():
		return false
	if not bool(pl.get("is_swimming")):
		return false
	return pl.global_position.distance_to(get_center_position()) < body_aabb.size.length() * 0.5 + 4.0


# ==============================================================================================
# water
# ==============================================================================================

func _get_env() -> Node:
	if _env != null and is_instance_valid(_env):
		return _env
	_env = null
	if _env_t > 0.0:
		return null
	_env_t = 2.0
	var e := Game.get_system("environment")
	if e != null and e.has_method("get_wave_height"):
		_env = e
	return _env


## Sea surface height at x, z (environment waves, else the flat sea level).
func _wave_y(x: float, z: float) -> float:
	var e := _get_env()
	if e != null:
		return float(e.call("get_wave_height", x, z))
	return Game.WATER_LEVEL


## Boats never flood: the base water stall is replaced by the buoyancy model.
func _check_water() -> void:
	in_water = false


func _integrate_water(_state: PhysicsDirectBodyState3D) -> void:
	pass


# ==============================================================================================
# physics
# ==============================================================================================

func _physics_process(delta: float) -> void:
	_env_t = maxf(_env_t - delta, 0.0)
	if _hull_material != null and _want_friction >= 0.0 and not is_equal_approx(_hull_material.friction, _want_friction):
		_hull_material.friction = _want_friction
	super._physics_process(delta)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _built:
		_guard_kinematic_kick(state)
	if _built and destroyed and _recover_t < 0.0:
		# a wreck loses most of its buoyancy and settles low / sinks slowly
		_prev_lin = state.linear_velocity
		_buoyancy(state, 0.7, false)
		state.apply_central_force(_buoy_f - state.linear_velocity * mass * 0.6 * submerged)
		state.apply_torque(_buoy_t - state.angular_velocity * (inertia.x + inertia.z) * 0.5 * submerged)
		return
	super._integrate_forces(state)


## A character body that is teleported (respawn, scripted moves) while standing on / next to the
## hull is swept by Jolt as a kinematic body and can kick the boat at absurd speeds. Characters
## never legitimately change a boat's velocity by more than a few m/s in one step: undo such kicks.
func _guard_kinematic_kick(state: PhysicsDirectBodyState3D) -> void:
	var dv := (state.linear_velocity - _prev_lin).length()
	if dv < 4.0:
		return
	for i in state.get_contact_count():
		if state.get_contact_collider_object(i) is CharacterBody3D:
			state.linear_velocity = _prev_lin
			state.angular_velocity = _prev_ang
			return


## Buoyancy of every hull sample into _buoy_f / _buoy_t (force, torque about the centre of mass).
## `scale` multiplies the spring rates (wrecks), `dynamic` enables planing / bow rise / banking.
func _buoyancy(state: PhysicsDirectBodyState3D, scale: float, dynamic: bool) -> void:
	var xf := state.transform
	var b := xf.basis
	var lin := state.linear_velocity
	var ang := state.angular_velocity
	var com := xf.origin + b * center_of_mass
	var v_fwd := lin.dot(-b.z)
	var rise := 0.0
	var pitch_t := 0.0
	if dynamic:
		var sp := maxf(v_fwd, 0.0) / maxf(float(_p["plane_speed"]), 1.0)
		var plane := smoothstep(0.45, 1.0, sp)
		rise = float(_p["plane_rise"]) * plane
		var peak := deg_to_rad(float(_p["bow_rise_deg"]))
		var hump := smoothstep(0.0, 0.55, sp) if sp < 0.55 else lerpf(1.0, 0.45, smoothstep(0.55, 1.0, sp))
		pitch_t = tan(peak * hump * clampf(_throttle_eff * 1.5 + 0.35, 0.0, 1.0))
	var draft := float(_p["draft"])
	var cap := draft + float(_p["freeboard"])
	var f := Vector3.ZERO
	var t := Vector3.ZERO
	var wet := 0
	for i in _pts.size():
		var lp := _pts[i]
		var wp := xf * lp
		var depth := _wave_y(wp.x, wp.z) - wp.y + draft
		_pdepth[i] = depth
		if depth <= 0.0:
			continue
		wet += 1
		var off := rise - pitch_t * (lp.z - _zc)
		var d := clampf(depth + off, 0.0, cap)
		var vp := lin + ang.cross(wp - com)
		var fy := _pk[i] * scale * d - _pc[i] * vp.y
		if fy <= 0.0:
			continue
		var fv := Vector3(0.0, fy, 0.0)
		f += fv
		t += (wp - com).cross(fv)
	submerged = float(wet) / float(maxi(_pts.size(), 1))
	afloat = wet > 0
	_buoy_f = f
	_buoy_t = t


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
	var v_lat := lin.dot(right)

	_update_steering(dt)
	var thr := in_throttle
	if not engine_on or stalled:
		thr = 0.0
	if driver == null and not _scripted:
		thr = 0.0
	_throttle_eff = absf(thr)

	_prev_ang = ang
	_buoyancy(state, 1.0, true)
	var total_f := _buoy_f
	var total_t := _buoy_t
	var wetf := submerged

	# --- water drag (body frame), scaled by how much hull is wet
	if wetf > 0.0:
		var sp := absf(v_fwd) / maxf(float(_p["plane_speed"]), 1.0)
		var plane := smoothstep(0.45, 1.0, sp)
		var c_lin := mass * float(_p["coast_drag"]) * (1.0 - 0.65 * plane)
		total_f += -fwd * (v_fwd * c_lin + v_fwd * absf(v_fwd) * _drag_q) * wetf
		var lat := -right * (v_lat * mass * float(_p["lateral_drag"]) + v_lat * absf(v_lat) * mass * 0.2) * wetf
		var lat_at := com + b.z * (_hull_len * 0.12)          # behind the centre of mass: tracks like a keel
		total_f += lat
		total_t += (lat_at - com).cross(lat)
		var yaw_rate := ang.dot(up)
		total_t += -up * yaw_rate * inertia.y * float(_p["yaw_damping"]) * wetf
		var rp := ang - up * yaw_rate
		total_t += -rp * (inertia.x + inertia.z) * 0.5 * float(_p["roll_damping"]) * wetf
		# righting moment of the hull towards a bank into the turn (+ about fwd drops the right side)
		var bank_max := deg_to_rad(float(_p["bank_deg"]))
		var bank_target := clampf(-yaw_rate * absf(v_fwd) * 0.06, -bank_max, bank_max)
		var roll := asin(clampf(-right.y, -1.0, 1.0))
		total_t += fwd * (-(mass * GRAV * float(_p["righting_gm"])) * sin(roll - bank_target) * wetf)

	# --- propulsion: thrust at the prop while it is under the surface, vectored by the leg
	var prop_w := xf * _prop_local
	prop_in_water = prop_w.y < _wave_y(prop_w.x, prop_w.z) - 0.02
	var thrust_dir := fwd.rotated(up, steer_angle)
	if absf(thr) > 0.01:
		var tmag := 0.0
		if thr > 0.0:
			tmag = thr * _thrust * get_power_factor()
		else:
			tmag = thr * _thrust * float(_p["reverse_thrust"]) * clampf((spec.reverse_speed + v_fwd) / 1.5, 0.0, 1.0)
		if prop_in_water:
			var tf := thrust_dir * tmag
			total_f += tf
			total_t += (prop_w - com).cross(tf)
		elif thr < 0.0 and aground:
			# beached with the prop in the air: reversing still works itself off, slowly
			total_f += fwd * tmag * float(_p["beach_push"])
	# rudder: flow along the leg turns the stern even without power
	if prop_in_water and absf(steer_angle) > 0.001:
		var rf := -right * float(_p["rudder"]) * mass * 0.012 * v_fwd * absf(v_fwd) * sin(steer_angle)
		total_f += rf
		total_t += (prop_w - com).cross(rf)

	# --- mooring line (until somebody boards)
	if moored:
		var d := _moor_xf.origin - xf.origin
		d.y = 0.0
		if d.length() > 8.0:
			moored = false             # the line parted (rammed / pushed away)
		else:
			var hv := Vector3(lin.x, 0.0, lin.z)
			total_f += d * mass * 0.35 - hv * mass * 0.9
			var mf := -_moor_xf.basis.z
			var cur := fwd
			var yaw_err := atan2(cur.cross(mf).dot(Vector3.UP), cur.dot(mf))
			total_t += Vector3.UP * (yaw_err * inertia.y * 0.4 - ang.y * inertia.y * 1.2)

	# --- in the air (wave jumps): gentle levelling
	if not afloat:
		_air_t += dt
		if _air_t > 0.25 and state.get_contact_count() == 0:
			var lev := up.cross(Vector3.UP)
			total_t += lev * (inertia.x + inertia.z) * 1.5 - ang * (inertia.x + inertia.z) * 0.3
	else:
		if _air_t > 0.35 and lin.y < -2.0:
			_slam_req = clampf(-lin.y / 4.0, 0.5, 2.0)
			_slam_pos = xf * _bow_local
		_air_t = 0.0

	# --- hull on the seabed / a beach: sand drag; reversing off gets a slippery hull
	var ground_contact := false
	for ci in state.get_contact_count():
		if state.get_contact_local_normal(ci).y > 0.45:
			var other := state.get_contact_collider_object(ci)
			if other == null or not (other is RigidBody3D):
				ground_contact = true
				break
	aground = ground_contact and wetf < 0.99
	if aground:
		var hv2 := Vector3(lin.x, 0.0, lin.z)
		total_f += -hv2 * mass * float(_p["ground_drag"]) * (1.0 - wetf * 0.5)
	_want_friction = 0.08 if (aground and thr < -0.01) else spec.hull_friction

	state.apply_central_force(total_f)
	state.apply_torque(total_t)

	# measured attitude for HUD / tests
	trim_deg = rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	bank_deg = rad_to_deg(asin(clampf(-right.y, -1.0, 1.0)))

	# engine note: revs with the throttle, races when the prop leaves the water
	var target := 0.18 + 0.82 * clampf(_throttle_eff * 0.7 + absf(v_fwd) / maxf(spec.top_speed, 1.0) * 0.45, 0.0, 1.0)
	if _throttle_eff > 0.2 and not prop_in_water:
		target = 1.0
	if not engine_on:
		target = 0.0
	rpm = lerpf(rpm, target, clampf(dt * 4.0, 0.0, 1.0))
	if afloat and not _was_afloat and lin.y < -3.0:
		_entry_splash = clampf(-lin.y / 5.0, 0.8, 2.5)
	_was_afloat = afloat


func _update_steering(dt: float) -> void:
	var max_a := deg_to_rad(spec.max_steer_angle)
	var target := clampf(in_steer, -1.0, 1.0) * max_a
	var returning := absf(target) < absf(steer_angle) or signf(target) != signf(steer_angle)
	var rate := (spec.steer_return_rate if returning else spec.steer_rate) * max_a
	steer_angle = move_toward(steer_angle, target, rate * dt)
	steer_norm = steer_angle / max_a


## Capsized for a few seconds: roll back upright at the surface (never down to the seabed).
func _begin_self_right() -> void:
	if destroyed or not is_inside_tree():
		return
	_recover_from = global_transform
	var f := -_recover_from.basis.z
	f.y = 0.0
	if f.length() < 0.15:
		f = _recover_from.basis.y
		f.y = 0.0
	if f.length() < 0.01:
		f = Vector3.FORWARD
	var yaw := atan2(-f.x, -f.z)
	var c := get_center_position()
	var y := _wave_y(c.x, c.z)
	if Game.world != null and Game.world.has_method("get_height"):
		y = maxf(y, float(Game.world.call("get_height", c.x, c.z)) + float(_p["draft"]) + 0.1)
	_recover_to = Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, y, c.z))
	_recover_t = 0.0
	can_sleep = false
	sleeping = false


func _on_teleported() -> void:
	_air_t = 0.0
	_was_afloat = false


func _on_destroyed() -> void:
	_throttle_eff = 0.0
	_release_wakes()


func _on_repaired() -> void:
	pass


# ==============================================================================================
# visuals / fx
# ==============================================================================================

func _process(delta: float) -> void:
	super._process(delta)
	# boats only sleep when nobody can see the waves move them (far from the camera)
	var want_sleep_ok := detail_level >= 2 and driver == null
	if want_sleep_ok != _sleep_ok:
		_sleep_ok = want_sleep_ok
		can_sleep = want_sleep_ok
		if not want_sleep_ok and sleeping:
			sleeping = false
	if detail_level >= 2 and not is_player_driven:
		_release_wakes()


func _update_visuals(delta: float) -> void:
	if _motor != null and is_instance_valid(_motor):
		_motor.transform = _motor_rest * Transform3D(Basis(Vector3.UP, steer_angle), Vector3.ZERO)
	if _handlebar != null and is_instance_valid(_handlebar):
		var rb := Basis(_steer_axis, -steer_angle)
		var sx := Transform3D(rb, _steer_pivot - rb * _steer_pivot)
		_handlebar.transform = _handlebar_parent_inv * sx * _handlebar_rest
	_update_steering_wheel(steer_norm)
	if destroyed or not is_inside_tree():
		_release_wakes()
		return
	var v_fwd := get_forward_speed()
	var near := detail_level == 0
	# wake trails on the stern corners
	if near and afloat and v_fwd > 1.5:
		if _wake_handles.is_empty():
			_attach_wakes()
		var s := clampf(v_fwd / maxf(spec.top_speed, 1.0), 0.15, 1.0)
		for h: Node3D in _wake_handles:
			if is_instance_valid(h) and h.has_method("set_strength"):
				h.call("set_strength", s)
	elif not _wake_handles.is_empty():
		_release_wakes()
	if not near:
		return
	# bow spray while running fast, slams after wave jumps, a splash when dropped in the water
	if afloat and v_fwd > 6.0:
		_spray_t -= delta
		if _spray_t <= 0.0:
			_spray_t = randf_range(0.25, 0.55) * lerpf(1.4, 0.7, clampf(v_fwd / maxf(spec.top_speed, 1.0), 0.0, 1.0))
			_spray_side = -_spray_side
			var gt := global_transform
			var bp := gt * (_bow_local + Vector3(_spray_side * _hull_beam * 0.32, 0.0, _hull_len * 0.18))
			bp.y = _wave_y(bp.x, bp.z) + 0.05
			Fx.splash(bp, clampf(v_fwd / maxf(spec.top_speed, 1.0), 0.3, 1.0) * 0.8)
	# the player's boat also leaves expanding ripples behind the transom (shared ring pool: sparingly)
	if is_player_driven and afloat and v_fwd > 5.0 and Fx.has_method("water_ring"):
		_ring_t -= delta
		if _ring_t <= 0.0:
			_ring_t = 0.34
			var gt2 := global_transform
			var sp2 := gt2 * Vector3(_bow_local.x, 0.0, _prop_local.z + 1.2)
			sp2.y = _wave_y(sp2.x, sp2.z)
			Fx.call("water_ring", sp2, clampf(_hull_beam * 0.55 + v_fwd * 0.04, 0.8, 2.4))
	if _slam_req > 0.0:
		var p := _slam_pos
		p.y = _wave_y(p.x, p.z) + 0.05
		Fx.splash(p, _slam_req)
		_slam_req = 0.0
	if _entry_splash > 0.0:
		var c := get_center_position()
		Fx.splash(Vector3(c.x, _wave_y(c.x, c.z), c.z), _entry_splash)
		_entry_splash = 0.0


func _attach_wakes() -> void:
	if not Fx.has_method("attach_trail"):
		return
	var parents: Array[Node3D] = []
	parents.append_array(_wake_markers)
	if parents.is_empty():
		parents.append(self)
	for par: Node3D in parents:
		var h: Variant = Fx.call("attach_trail", par, "wake")
		if h != null and is_instance_valid(h) and h is Node3D:
			_wake_handles.append(h as Node3D)


func _release_wakes() -> void:
	for h: Node3D in _wake_handles:
		if is_instance_valid(h):
			h.queue_free()
	_wake_handles.clear()


# ==============================================================================================
# queries
# ==============================================================================================

func get_rpm_factor() -> float:
	return clampf(rpm, 0.0, 1.0)


func get_engine_load() -> float:
	return _throttle_eff


func is_braking() -> bool:
	return in_throttle < -0.05 and get_forward_speed() > 1.0


func is_reversing() -> bool:
	return in_throttle < -0.05 and get_forward_speed() < 0.5


## World Y of the sea surface under the hull centre.
func get_surface_height() -> float:
	var c := global_position
	return _wave_y(c.x, c.z)


func get_telemetry() -> Dictionary:
	return {"speed_kmh": speed_kmh, "steer": steer_norm, "afloat": afloat, "submerged": submerged,
			"prop_in_water": prop_in_water, "aground": aground, "trim_deg": trim_deg, "bank_deg": bank_deg,
			"rpm": rpm, "moored": moored}
