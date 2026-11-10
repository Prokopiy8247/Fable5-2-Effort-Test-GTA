class_name VehiclePlane
extends VehicleBase
## Fixed-wing aircraft (spec ids plane_prop, plane_jet).
## NOTE: the contract name `Plane` is impossible (Godot built-in math type `Plane`), so the class is
## registered as `VehiclePlane` (VEHICLE module prefix `Vehicle*`). VehicleManager loads it by path.
##
## Arcade-friendly but physically driven:
##   throttle  persistent lever (player: W / S move it, AI: in_power = wanted throttle 0..1),
##             thrust along the nose (propeller thrust fades with airspeed, jet thrust barely does)
##   pitch     arrows / numpad (in_pitch, + = nose up) -> pitch-rate command; on the ground it
##             rotates around the main gear up to a tail-safe attitude
##   roll      (in_roll, + = right) -> roll-rate command; a gentle wings-level tendency without input
##   yaw       A / D (in_yaw, + = right) -> rudder in the air, nose-wheel steering on the ground
##   brakes    handbrake action, or S with the throttle closed on the ground (AI: set_brakes())
##
## Aerodynamics: lift = k * CL(alpha) * V^2 perpendicular to the airflow (k from the stall speed),
## CL linear up to the stall angle, then it collapses (stall: nose drops, controls go mushy, a wing
## may drop); parasite + induced drag; control authority grows with airspeed; the nose weathervanes
## into the airflow (pitch / yaw stability); flaps come out automatically at low speed; a little
## ground effect helps the flare. Wheels: one suspension ray per gear leg (Wheel_Nose, Wheel_L,
## Wheel_R) with the spring built around the modelled pose, rolling resistance, brakes, side grip.
## Damage: touchdown above `touchdown_sink`, hull collisions (wing / tail strikes), ditching in the
## sea, explosion above `crash_explode_dv`. Tuning: spec metadata "air" (vehicles_air_registry.gd).

const GRAV := 9.81
const AUDIO_RANGE := 340.0
const AGL_MASK := Layers.WORLD | Layers.VEHICLE | Layers.PROP
const AGL_MAX := 800.0
const GEAR_EXTRA := 0.25             ## suspension rays start this far above full bump
const GROUND_MAX_PITCH := deg_to_rad(11.0)
const MAX_G := 5.5
const PROP_REV_PER_S := 32.0
const SOFT_LIMIT_NOTIFY_SEC := 8.0
const WHEEL_NAMES: Array[String] = ["Wheel_Nose", "Wheel_L", "Wheel_R"]

# --- public state (HUD / AI / tests) -----------------------------------------------------------
var throttle: float = 0.0            ## 0..1 lever position
var engine_power: float = 0.0        ## 0..1 spooled engine output (follows the lever)
var prop_rpm: float = 0.0            ## 0..1 propeller / fan speed (visuals + audio)
var airspeed: float = 0.0            ## m/s through the air
var vertical_speed: float = 0.0
var altitude_agl: float = 0.0
var angle_of_attack: float = 0.0     ## degrees
var sideslip: float = 0.0            ## degrees
var stall_amount: float = 0.0        ## 0 flying .. 1 fully stalled
var is_stalled: bool = false
var on_ground: bool = true
var gear_contacts: int = 0
var flaps: float = 0.0               ## 0..1 (automatic below ~1.6 x stall speed)
var brake: float = 0.0               ## 0..1 applied wheel brakes
var gear_down: bool = true           ## both models have fixed gear (see docs/AIRCRAFT.md)
var lift_force: float = 0.0
var thrust_force: float = 0.0
var last_touchdown_sink: float = 0.0
var air_audio_active: bool = false
var stall_speed: float = 24.0

# --- tuning ------------------------------------------------------------------------------------
var _cl_max: float = 1.45
var _cl0: float = 0.32
var _cl_alpha: float = 5.0
var _flap_cl: float = 0.25
var _thrust: float = 3700.0
var _thrust_fade: float = 0.55
var _drag: float = 0.33
var _induced: float = 0.045
var _pitch_rate: float = deg_to_rad(50.0)
var _roll_rate: float = deg_to_rad(105.0)
var _yaw_rate: float = deg_to_rad(18.0)
var _auth_speed: float = 34.0
var _throttle_rate: float = 0.55
var _brake_decel: float = 4.0
var _steer: float = deg_to_rad(32.0)
var _gear_hz: float = 2.3
var _gear_bump: float = 0.07
var _gear_droop: float = 0.07
var _explode_dv: float = 18.0
var _touchdown_sink: float = 3.2
var _is_prop: bool = true
var _spoilers: bool = false
var spoilers: float = 0.0             ## 0..1 ground lift dumpers (jet)
var _k_lift: float = 10.0
var _top_speed: float = 67.0
var _span: float = 10.0
var _grav: float = GRAV

# --- gear ----------------------------------------------------------------------------------------
var _gear: Array[GearLeg] = []

class GearLeg extends RefCounted:
	var node: Node3D = null
	var rest: Transform3D
	var pos: Vector3                 ## body space wheel centre (modelled pose)
	var radius: float = 0.2
	var steers: bool = false
	var braked: bool = false
	var static_load: float = 1000.0
	var k: float = 10000.0
	var c_bump: float = 1000.0
	var c_rebound: float = 1400.0
	var compression: float = 0.0
	var grounded: bool = false
	var normal_force: float = 0.0
	var spin: float = 0.0
	var ang_vel: float = 0.0

# --- parts ---------------------------------------------------------------------------------------
var _prop: Node3D = null
var _prop_rest: Transform3D
var _prop_geo: Array[GeometryInstance3D] = []
var _prop_blur: GeometryInstance3D = null
var _prop_angle: float = 0.0
var _blur_shown: float = -1.0
var _surf: Dictionary = {}           ## part name -> rest Transform3D
var _canopy: Node3D = null
var _canopy_rest: Transform3D
var _canopy_open: float = 0.0
var _canopy_timer: float = 0.0

# --- simulation ------------------------------------------------------------------------------
var _ctl: Vector3 = Vector3.ZERO     ## smoothed control-surface deflection (pitch, yaw, roll)
var _ai_brake: float = 0.0
var _agl_q: PhysicsRayQueryParameters3D = null
var _gear_q: PhysicsRayQueryParameters3D = null
var _air_t: float = 0.0
var _rest_t: float = 0.0
var _sleep_request: bool = false
var _env_t: float = 0.0
var _skill: float = 0.0
var _weather_turb: float = 0.0
var _wind: Vector3 = Vector3.ZERO
var _grip_env: float = 1.0
var _turb_t: float = 0.0
var _fly_xp_t: float = 0.0
var _audio_t: float = 0.0
var _limit_notify_t: float = 0.0
var _stall_notify_t: float = 0.0
var _beacon_t: float = 0.0
var _beacon_mat: BaseMaterial3D = null
var _pending_touchdown: float = -1.0
var _pending_limit_notify: bool = false
var _pending_stall_notify: bool = false
var _was_in_water: bool = false


# ==============================================================================================
# construction
# ==============================================================================================

func _build_drive(_opts: Dictionary) -> void:
	self_righting = false
	_grav = float(ProjectSettings.get_setting("physics/3d/default_gravity", GRAV))
	var air: Dictionary = spec.get_meta("air", {}) if spec.has_meta("air") else {}
	stall_speed = maxf(float(air.get("stall_speed", 24.0)), 5.0)
	_cl_max = float(air.get("cl_max", 1.45))
	_cl0 = float(air.get("cl0", 0.32))
	_cl_alpha = float(air.get("cl_alpha", 5.0))
	_flap_cl = float(air.get("flap_cl", 0.25))
	_thrust = float(air.get("thrust", 3700.0))
	_thrust_fade = float(air.get("thrust_fade", 0.55))
	_drag = float(air.get("drag", 0.33))
	_induced = float(air.get("induced", 0.045))
	_pitch_rate = deg_to_rad(float(air.get("pitch_rate_deg", 50.0)))
	_roll_rate = deg_to_rad(float(air.get("roll_rate_deg", 105.0)))
	_yaw_rate = deg_to_rad(float(air.get("yaw_rate_deg", 18.0)))
	_auth_speed = maxf(float(air.get("authority_speed", 34.0)), 5.0)
	_throttle_rate = float(air.get("throttle_rate", 0.55))
	_brake_decel = float(air.get("brake_decel", 4.0))
	_steer = deg_to_rad(float(air.get("steer_deg", 32.0)))
	_gear_hz = float(air.get("gear_hz", 2.3))
	_gear_bump = float(air.get("gear_bump", 0.07))
	_gear_droop = float(air.get("gear_droop", 0.07))
	_explode_dv = float(air.get("crash_explode_dv", 18.0))
	_touchdown_sink = float(air.get("touchdown_sink", 3.2))
	_is_prop = bool(air.get("prop", true))
	_spoilers = bool(air.get("ground_spoilers", false))
	_top_speed = maxf(spec.top_speed, stall_speed * 1.5)

	# gear legs (wheel centre + radius from the mesh)
	for wn: String in WHEEL_NAMES:
		var n := get_part(wn)
		var leg := GearLeg.new()
		if n != null:
			leg.node = n
			leg.rest = n.transform
			leg.pos = xform_in_body(n).origin
			var a := aabb_in_body(n)
			leg.radius = clampf(a.size.y * 0.5, 0.08, 0.6) if a.size.y > 0.05 else 0.2
		else:
			# fallback tricycle layout from the body bounds (logged once: the model lacks the part)
			push_warning("Plane %s: model has no %s - using a fallback gear point" % [spec_id, wn])
			var c := body_aabb.get_center()
			match wn:
				"Wheel_Nose": leg.pos = Vector3(c.x, 0.2, body_aabb.position.z + body_aabb.size.z * 0.18)
				"Wheel_L": leg.pos = Vector3(c.x - body_aabb.size.x * 0.12, 0.2, 0.45)
				_: leg.pos = Vector3(c.x + body_aabb.size.x * 0.12, 0.2, 0.45)
			leg.radius = 0.2
		leg.steers = wn == "Wheel_Nose"
		leg.braked = not leg.steers
		_gear.append(leg)

	# span from the wing collision helper (ground effect height)
	var wing := get_part("Col_Wing")
	_span = aabb_in_body(wing).size.x if wing != null else body_aabb.size.x * 2.0

	_prop = get_part("Propeller")
	if _prop != null:
		_prop_rest = _prop.transform
		_prop_geo = _geometry_of(_prop)
	var pb := get_part("PropBlur")
	if pb != null:
		_prop_blur = pb as GeometryInstance3D
		for g: GeometryInstance3D in _geometry_of(pb):
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pb.visible = false
	for sn: String in ["Aileron_L", "Aileron_R", "Flap_L", "Flap_R", "Elevator", "Rudder"]:
		var s := get_part(sn)
		if s != null:
			_surf[sn] = s.transform
	_canopy = get_part("Canopy")
	if _canopy != null:
		_canopy_rest = _canopy.transform

	_agl_q = PhysicsRayQueryParameters3D.new()
	_agl_q.collision_mask = AGL_MASK
	_gear_q = PhysicsRayQueryParameters3D.new()
	_gear_q.collision_mask = Layers.GROUND_MASK


func _geometry_of(n: Node3D) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	var list: Array[Node] = [n]
	list.append_array(n.find_children("*", "GeometryInstance3D", true, false))
	for c: Node in list:
		var g := c as GeometryInstance3D
		if g != null:
			out.append(g)
	return out


## The model origin sits on the ground under the centre of gravity.
func _get_reference_z() -> float:
	return 0.0


func _apply_mass_properties() -> void:
	super._apply_mass_properties()
	_k_lift = mass * _grav / maxf(_cl_max * stall_speed * stall_speed, 1.0)
	_solve_gear_loads()


func _solve_gear_loads() -> void:
	if _gear.size() < 3:
		return
	var nose := _gear[0]
	var zl := (_gear[1].pos.z + _gear[2].pos.z) * 0.5
	var com_z := center_of_mass.z
	var span_z := zl - nose.pos.z
	var nose_share := clampf((zl - com_z) / maxf(span_z, 0.3), 0.05, 0.6)
	var weight := mass * _grav
	nose.static_load = weight * nose_share
	_gear[1].static_load = weight * (1.0 - nose_share) * 0.5
	_gear[2].static_load = weight * (1.0 - nose_share) * 0.5
	var w0 := TAU * _gear_hz
	for leg: GearLeg in _gear:
		var m_w := leg.static_load / _grav
		leg.k = m_w * w0 * w0
		leg.c_bump = 2.0 * 0.55 * sqrt(leg.k * m_w)
		leg.c_rebound = leg.c_bump * 1.4


func _ready() -> void:
	super._ready()
	_agl_q.exclude = [get_rid()]
	_gear_q.exclude = [get_rid()]
	var aa := AirAudio.new()
	aa.setup(self)
	aa.audio_range = AUDIO_RANGE
	aa.local_pos = marker_local("Engine", body_aabb.get_center())
	audio = aa
	_beacon_mat = lights.tail_mat if lights != null else null


# ==============================================================================================
# public API
# ==============================================================================================

func get_rpm_factor() -> float:
	return prop_rpm


func get_engine_load() -> float:
	return engine_power


func get_camera_params() -> Dictionary:
	var p := super.get_camera_params()
	var d: float = float(p.get("distance", 10.0))
	p["distance"] = d + clampf(airspeed * 0.03, 0.0, 3.0)
	return p


## AI / scripted ground handling: wheel brakes 0..1 (released with 0).
func set_brakes(amount: float) -> void:
	if is_player_driven:
		return
	_ai_brake = clampf(amount, 0.0, 1.0)
	_scripted = true


## Throttle lever position for AI / tests (the player moves it with W / S).
func set_throttle(value: float) -> void:
	if is_player_driven or destroyed:
		return
	throttle = clampf(value, 0.0, 1.0)
	in_power = throttle
	_scripted = true
	if throttle > 0.01:
		if not engine_on:
			start_engine()
		sleeping = false


func get_telemetry() -> Dictionary:
	return {
		"throttle": throttle, "engine": engine_power, "airspeed": airspeed, "vs": vertical_speed,
		"agl": altitude_agl, "aoa": angle_of_attack, "sideslip": sideslip, "stall": stall_amount,
		"on_ground": on_ground, "gear_contacts": gear_contacts, "flaps": flaps, "brake": brake,
		"lift": lift_force, "thrust": thrust_force, "health": health, "spoilers": spoilers,
	}


## Body pitch angle in degrees (+ nose up) and bank angle in degrees (+ right wing down).
func get_attitude_degrees() -> Vector2:
	var b := global_transform.basis.orthonormalized()
	return Vector2(rad_to_deg(asin(clampf(-b.z.y, -1.0, 1.0))), rad_to_deg(asin(clampf(-b.x.y, -1.0, 1.0))))


## Heading in radians (0 = north / -Z, + = counter-clockwise seen from above).
func get_heading() -> float:
	var f := -global_transform.basis.z
	return atan2(-f.x, -f.z)


# ==============================================================================================
# input
# ==============================================================================================

func _read_player_input(delta: float) -> void:
	var up := Input.get_action_strength("air_throttle_up")
	var down := Input.get_action_strength("air_throttle_down")
	throttle = clampf(throttle + (up - down) * _throttle_rate * delta, 0.0, 1.0)
	in_power = throttle
	in_pitch = Input.get_action_strength("air_pitch_up") - Input.get_action_strength("air_pitch_down")
	in_roll = Input.get_action_strength("air_roll_right") - Input.get_action_strength("air_roll_left")
	in_yaw = Input.get_action_strength("air_yaw_right") - Input.get_action_strength("air_yaw_left")
	var b := 1.0 if Input.is_action_pressed("handbrake") else 0.0
	if on_ground and throttle <= 0.001 and down > 0.1:
		b = maxf(b, down)
	in_brake = b
	if up > 0.1 and not engine_on and not stalled:
		start_engine()


func _read_player_toggles() -> void:
	if Input.is_action_just_pressed("headlights"):
		set_headlights((headlight_mode + 1) % 3)
	if Input.is_action_just_pressed("air_gear"):
		UI.notify("Fixed landing gear", "info")


func _wants_wake() -> bool:
	return in_power > 0.01 or throttle > 0.01


# ==============================================================================================
# frame updates
# ==============================================================================================

func _physics_process(delta: float) -> void:
	if _sleep_request:
		_sleep_request = false
		if not destroyed and throttle < 0.02 and in_power < 0.02:
			sleeping = true
			_on_sleep()
	if not is_player_driven and not destroyed:
		if driver == null and not _scripted:
			in_power = 0.0
		throttle = move_toward(throttle, clampf(in_power, 0.0, 1.0), delta * 0.8)
	# engine spool (also while asleep)
	var lever := throttle if engine_on and not destroyed and not stalled else 0.0
	var spool := 2.2 if _is_prop else 0.75
	engine_power = move_toward(engine_power, lever, delta * spool)
	var rpm_target := (0.2 + 0.8 * engine_power) if (engine_on and not destroyed and not stalled) else 0.0
	prop_rpm = move_toward(prop_rpm, rpm_target, delta * (0.9 if rpm_target > prop_rpm else 0.35))
	_xp_t = 0.0                          # flying earns "flying", not "driving"
	super._physics_process(delta)
	if destroyed:
		return
	if _pending_touchdown >= 0.0:
		_touchdown(_pending_touchdown)
		_pending_touchdown = -1.0
	if _pending_limit_notify:
		_pending_limit_notify = false
		UI.notify("Airspace limit - turning back to Halcyon Bay", "warn")
	if _pending_stall_notify:
		_pending_stall_notify = false
		UI.notify("STALL - lower the nose", "warn")
	if is_player_driven:
		_fly_xp_t += delta
		if _fly_xp_t >= 1.0:
			_fly_xp_t = 0.0
			if not on_ground:
				Skills.add_xp("flying", 0.018 * clampf(airspeed / 40.0, 0.35, 1.0))
		_limit_notify_t = maxf(_limit_notify_t - delta, 0.0)
		_stall_notify_t = maxf(_stall_notify_t - delta, 0.0)


func _on_sleep() -> void:
	_rest_t = 0.0
	airspeed = 0.0
	vertical_speed = 0.0
	speed_kmh = 0.0
	for leg: GearLeg in _gear:
		leg.ang_vel = 0.0


func _process(delta: float) -> void:
	super._process(delta)
	if not _built:
		return
	_audio_t -= delta
	if _audio_t <= 0.0:
		_audio_t = 0.25
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		air_audio_active = is_player_driven or (cam != null and cam.global_position.distance_to(global_position) < AUDIO_RANGE)
	if detail_level >= 2 and not is_player_driven:
		_spin_prop(delta)


func _update_visuals(delta: float) -> void:
	_spin_prop(delta)
	# control surfaces follow the inputs (smoothed like hydraulics / cables)
	var k := clampf(delta * 6.0, 0.0, 1.0)
	_ctl = _ctl.lerp(Vector3(clampf(in_pitch, -1.0, 1.0), clampf(in_yaw, -1.0, 1.0), clampf(in_roll, -1.0, 1.0)), k)
	_pose_surface("Aileron_L", Vector3.RIGHT, deg_to_rad(18.0) * _ctl.z)
	_pose_surface("Aileron_R", Vector3.RIGHT, -deg_to_rad(18.0) * _ctl.z)
	_pose_surface("Elevator", Vector3.RIGHT, -deg_to_rad(20.0) * _ctl.x)
	_pose_surface("Rudder", Vector3.UP, deg_to_rad(22.0) * _ctl.y)
	_pose_surface("Flap_L", Vector3.RIGHT, deg_to_rad(26.0) * flaps)
	_pose_surface("Flap_R", Vector3.RIGHT, deg_to_rad(26.0) * flaps)
	# wheels: roll with the ground, small visible suspension travel
	for leg: GearLeg in _gear:
		if leg.node == null or not is_instance_valid(leg.node):
			continue
		leg.spin = wrapf(leg.spin - leg.ang_vel * delta, 0.0, TAU)
		var travel := clampf(leg.compression if leg.grounded else -_gear_droop, -0.05, 0.05)
		var t := leg.rest
		t.origin += Vector3(0.0, travel, 0.0)
		leg.node.transform = t * Transform3D(Basis(Vector3.RIGHT, leg.spin), Vector3.ZERO)
	# jet canopy: open while parked with the engine off, or briefly for boarding
	if _canopy != null:
		_canopy_timer = maxf(_canopy_timer - delta, 0.0)
		var want := 1.0 if (_canopy_timer > 0.0 or (not engine_on and driver == null and airspeed < 1.0 and on_ground)) else 0.0
		if not is_equal_approx(_canopy_open, want):
			_canopy_open = move_toward(_canopy_open, want, delta * 1.4)
			var e := _canopy_open * _canopy_open * (3.0 - 2.0 * _canopy_open)
			_canopy.transform = _canopy_rest * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(38.0) * e), Vector3.ZERO)
	# anti-collision beacon
	if _beacon_mat != null and (engine_on or prop_rpm > 0.15):
		_beacon_t = fmod(_beacon_t + delta, 1.2)
		var base := 1.1 if headlight_mode > 0 else 0.4
		_beacon_mat.emission_energy_multiplier = 6.5 if (_beacon_t < 0.1 or (_beacon_t > 0.25 and _beacon_t < 0.33)) else base


func _pose_surface(part_name: String, axis: Vector3, angle: float) -> void:
	if not _surf.has(part_name):
		return
	var n := get_part(part_name)
	if n != null:
		n.transform = (_surf[part_name] as Transform3D) * Transform3D(Basis(axis, angle), Vector3.ZERO)


func _spin_prop(delta: float) -> void:
	if _prop != null:
		_prop_angle = wrapf(_prop_angle + prop_rpm * PROP_REV_PER_S * TAU * delta, 0.0, TAU)
		_prop.transform = _prop_rest * Transform3D(Basis(Vector3.BACK, _prop_angle), Vector3.ZERO)
	var blur := smoothstep(0.15, 0.45, prop_rpm)
	if absf(blur - _blur_shown) < 0.01:
		return
	_blur_shown = blur
	if _prop_blur != null:
		_prop_blur.visible = blur > 0.01
		_prop_blur.transparency = 1.0 - blur
	for g: GeometryInstance3D in _prop_geo:
		g.transparency = blur * 0.75


# ==============================================================================================
# physics
# ==============================================================================================

func _integrate_vehicle(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	var xf := state.transform
	var b := xf.basis.orthonormalized()
	var up := b.y
	var fwd := -b.z
	var right := b.x
	var lin := state.linear_velocity
	var ang := state.angular_velocity
	var com := xf.origin + b * center_of_mass
	var weight := mass * _grav

	_env_t -= dt
	if _env_t <= 0.0:
		_env_t = 0.5
		_refresh_environment()
	_probe_ground(state.get_space_state(), xf.origin)
	vertical_speed = lin.y

	var force := Vector3.ZERO
	var torque := Vector3.ZERO

	# ---------------------------------------------------------------- thrust
	var v_fwd := lin.dot(fwd)
	var fade := 1.0 - _thrust_fade * clampf(v_fwd / _top_speed, 0.0, 1.2)
	thrust_force = _thrust * engine_power * get_power_factor() * fade
	force += fwd * thrust_force

	# ---------------------------------------------------------------- brakes
	brake = maxf(maxf(in_brake, _ai_brake), 0.0)
	if throttle < 0.03 and lin.length() < 0.6 and _ai_brake <= 0.0 and in_brake <= 0.0:
		brake = 1.0                     # parking brake while stopped with the throttle closed

	# ---------------------------------------------------------------- gear
	var space := state.get_space_state()
	var was_contacts := gear_contacts
	gear_contacts = 0
	var steer_max := lerpf(_steer, deg_to_rad(5.0), clampf(absf(v_fwd) / 30.0, 0.0, 1.0))
	var steer := clampf(in_yaw, -1.0, 1.0) * steer_max
	var max_sink := 0.0
	for leg: GearLeg in _gear:
		var top := _gear_bump + GEAR_EXTRA
		var mount := xf * (leg.pos + Vector3(0.0, top, 0.0))
		var ray_len := top + _gear_droop + leg.radius
		_gear_q.from = mount
		_gear_q.to = mount - up * ray_len
		var hit := space.intersect_ray(_gear_q)
		if hit.is_empty():
			leg.grounded = false
			leg.compression = -_gear_droop
			leg.normal_force = 0.0
			leg.ang_vel = lerpf(leg.ang_vel, 0.0, clampf(dt * 0.6, 0.0, 1.0))
			continue
		var hp: Vector3 = hit["position"]
		var dist := (mount - hp).dot(up)
		var x := (top + leg.radius) - dist
		if x < -_gear_droop:
			leg.grounded = false
			leg.compression = -_gear_droop
			leg.normal_force = 0.0
			continue
		leg.grounded = true
		leg.compression = x
		gear_contacts += 1
		var n: Vector3 = hit["normal"]
		if n.dot(up) < 0.4:
			n = up
		var rel := hp - com
		var vp := lin + ang.cross(rel)
		max_sink = maxf(max_sink, -vp.dot(n))
		var f_s := leg.static_load + leg.k * x
		if x > _gear_bump:
			f_s += leg.k * 4.0 * (x - _gear_bump)
		var rate := -vp.dot(n)
		f_s += rate * (leg.c_bump if rate > 0.0 else leg.c_rebound)
		var nf := clampf(f_s, 0.0, leg.static_load * 12.0)
		leg.normal_force = nf
		var fn := n * nf
		force += fn
		torque += rel.cross(fn)
		if nf < 1.0:
			continue
		var wf := fwd.rotated(up, -steer) if leg.steers else fwd
		var fdir := wf - n * wf.dot(n)
		if fdir.length() < 0.01:
			continue
		fdir = fdir.normalized()
		var sdir := fdir.cross(n)
		var v_long := vp.dot(fdir)
		var v_lat := vp.dot(sdir)
		var mu := 0.85 * _grip_env
		var cap := mu * nf
		var m_w := nf / _grav
		var stop := m_w / dt
		var opp := 0.016 * nf
		if leg.braked and brake > 0.0:
			opp += brake * _brake_decel * mass * 0.5
		opp = minf(opp, cap * 0.95)
		opp = minf(opp, absf(v_long) * stop * 0.9)
		var f_long := -signf(v_long) * opp
		var f_lat := clampf(-v_lat * m_w * 30.0, -cap, cap)
		f_lat = clampf(f_lat, -absf(v_lat) * stop * 0.85, absf(v_lat) * stop * 0.85)
		var ft := fdir * f_long + sdir * f_lat
		force += ft
		torque += rel.cross(ft)
		leg.ang_vel = v_long / maxf(leg.radius, 0.05)
	var was_ground := on_ground
	on_ground = gear_contacts > 0 or (state.get_contact_count() > 0 and altitude_agl < 1.5)
	if gear_contacts > 0:
		if was_contacts == 0 and _air_t > 0.6:
			_pending_touchdown = max_sink
		_air_t = 0.0
	elif not on_ground:
		_air_t += dt
	if was_ground and not on_ground:
		_air_t = 0.0

	# ---------------------------------------------------------------- aerodynamics
	var air_v := lin - _wind
	var v := air_v.length()
	airspeed = v
	# automatic flaps: full for the approach, a take-off setting (half) at high power
	var flap_set := 0.6 if throttle > 0.6 else 1.0
	flaps = move_toward(flaps, (1.0 - smoothstep(1.3 * stall_speed, 1.75 * stall_speed, v)) * flap_set, dt * 0.5)
	var dump := 1.0 if (_spoilers and gear_contacts >= 2 and throttle < 0.1 and _gear[0].grounded) else 0.0
	spoilers = move_toward(spoilers, dump, dt * 2.5)
	lift_force = 0.0
	var aoa := 0.0
	var beta := 0.0
	var q_norm := 0.0
	if v > 1.0:
		var vd := air_v / v
		var vl := b.inverse() * air_v
		aoa = atan2(-vl.y, maxf(-vl.z, 0.01))
		beta = atan2(vl.x, maxf(-vl.z, 0.01))
		if vl.z > 0.0:
			aoa = PI * 0.5 * signf(-vl.y) if absf(vl.y) > 0.01 else PI * 0.5    # flying backwards: fully stalled
		var cl_m := _cl_max + _flap_cl * flaps
		var a_st := (cl_m - (_cl0 + _flap_cl * flaps)) / _cl_alpha
		var cl_lin := clampf(_cl0 + _flap_cl * flaps + _cl_alpha * aoa, -cl_m * 0.8, cl_m)
		var neg_st := (-cl_m * 0.8 - (_cl0 + _flap_cl * flaps)) / _cl_alpha
		var st_pos := smoothstep(a_st - 0.015, a_st + 0.06, aoa)
		var st_neg := smoothstep(-neg_st - 0.015, -neg_st + 0.06, -aoa)
		stall_amount = clampf(maxf(st_pos, st_neg) * clampf(v / 6.0, 0.0, 1.0), 0.0, 1.0)
		var cl_post := signf(aoa) * cl_m * 0.5 * clampf(1.0 - (absf(aoa) - a_st) / 1.4, 0.15, 1.0)
		var cl := lerpf(cl_lin, cl_post, maxf(st_pos, st_neg)) - 0.45 * spoilers
		var ge := 0.0
		if altitude_agl < _span:
			ge = 0.1 * pow(1.0 - altitude_agl / _span, 2.0)
		var qv := v * v
		lift_force = clampf(_k_lift * cl * qv * (1.0 + ge), -weight * MAX_G, weight * MAX_G)
		var ldir := right.cross(vd)
		if ldir.length() > 0.01:
			force += ldir.normalized() * lift_force
		var cd := _drag * (1.0 + flaps * flaps * 0.8 + spoilers * 0.6) + _k_lift * (_induced * cl * cl + 0.35 * stall_amount)
		force += -vd * cd * qv
		force += -right * vl.x * v * _drag * 5.0        # fuselage / fin side force
		q_norm = clampf(v / _auth_speed, 0.0, 1.3)
	else:
		stall_amount = 0.0
	is_stalled = stall_amount > 0.5
	angle_of_attack = rad_to_deg(aoa)
	sideslip = rad_to_deg(beta)
	if is_player_driven and is_stalled and not on_ground and _stall_notify_t <= 0.0:
		_stall_notify_t = 6.0
		_pending_stall_notify = true

	# ---------------------------------------------------------------- control moments (body axes)
	var wl := b.inverse() * ang
	var authority := q_norm * (1.0 - 0.55 * stall_amount) * lerpf(0.94, 1.05, _skill)
	var pitch_ang := asin(clampf(fwd.y, -1.0, 1.0))
	var bank := asin(clampf(-right.y, -1.0, 1.0))           # + = right wing down
	var alpha := Vector3.ZERO
	# pitch: rate command + stability (nose follows the airflow) + stall nose drop
	var pr := clampf(in_pitch, -1.0, 1.0) * _pitch_rate
	if gear_contacts > 0:
		pr = minf(pr, (GROUND_MAX_PITCH - pitch_ang) * 3.0)
	alpha.x = (pr - wl.x) * 4.0 * authority
	# (weak while the wheels are down: the elevator rotates the aircraft about the main gear)
	alpha.x += -aoa * 6.0 * q_norm * q_norm * (1.0 - stall_amount * 0.6) * (0.25 if gear_contacts > 0 else 1.0)
	alpha.x += -stall_amount * 2.4 * clampf(v / 12.0, 0.3, 1.0)
	# roll: rate command, gentle wings-level without input, a wing drops in the stall
	var rr := -clampf(in_roll, -1.0, 1.0) * _roll_rate
	alpha.z = (rr - wl.z) * 5.0 * authority
	if absf(in_roll) < 0.05 and gear_contacts == 0:
		alpha.z += bank * 0.7 * q_norm * lerpf(0.6, 1.0, _skill)
	if stall_amount > 0.2 and gear_contacts == 0:
		alpha.z += sin(_turb_t * 1.3 + 0.7) * 1.4 * stall_amount
	# yaw: rudder rate command + coordinated turn + weathervane into the airflow
	var yr := -clampf(in_yaw, -1.0, 1.0) * _yaw_rate
	if gear_contacts == 0 and v > 8.0:
		yr += -_grav * sin(bank) / maxf(v, 15.0) * cos(pitch_ang)
	alpha.y = (yr - wl.y) * 3.0 * authority
	alpha.y += -beta * 4.0 * q_norm * q_norm
	# turbulence (weather, low skill)
	_turb_t += dt
	if gear_contacts == 0 and v > 5.0:
		var turb := (0.12 * (1.0 - _skill) + _weather_turb) * q_norm
		if turb > 0.005:
			var t := _turb_t
			alpha += Vector3(sin(t * 1.9 + 0.2) * 0.5 + sin(t * 4.7) * 0.3, sin(t * 1.3 + 1.1) * 0.3, sin(t * 2.3 + 2.0) * 0.6 + sin(t * 5.3) * 0.3) * turb
			force.y += sin(t * 1.1 + 0.5) * sin(t * 3.1) * turb * mass * 2.0

	# ---------------------------------------------------------------- soft world limit (player)
	if is_player_driven:
		var hp := Vector2(xf.origin.x, xf.origin.z)
		var d := hp.length()
		if d > Game.WORLD_SOFT_LIMIT:
			var out_dir := Vector3(hp.x / d, 0.0, hp.y / d)
			var over := clampf((d - Game.WORLD_SOFT_LIMIT) / 200.0, 0.15, 1.0)
			var heading := atan2(-fwd.x, -fwd.z)
			var home := atan2(out_dir.x, out_dir.z)
			var herr := wrapf(home - heading, -PI, PI)
			var want_bank := -clampf(herr * 1.2, -0.6, 0.6)
			alpha.z += (bank - want_bank) * 2.5 * over
			alpha.x += 0.4 * over * absf(sin(bank))
			force -= out_dir * maxf(lin.dot(out_dir), 0.0) * mass * 0.25 * over
			if _limit_notify_t <= 0.0:
				_limit_notify_t = SOFT_LIMIT_NOTIFY_SEC
				_pending_limit_notify = true

	torque += b * (alpha * inertia)
	state.apply_central_force(force)
	state.apply_torque(torque)

	# ---------------------------------------------------------------- rest detection
	if gear_contacts == _gear.size() and throttle < 0.02 and lin.length_squared() < 0.004 and ang.length_squared() < 0.003:
		_rest_t += dt
		if _rest_t > 1.0:
			_rest_t = 0.0
			_sleep_request = true
	else:
		_rest_t = 0.0


func _integrate_common(state: PhysicsDirectBodyState3D) -> void:
	super._integrate_common(state)
	speed_kmh = state.linear_velocity.length() * 3.6


func _refresh_environment() -> void:
	_skill = Skills.get_factor("flying") if is_player_driven else 0.75
	var storm := float(Weather.get_storminess()) if Weather.has_method("get_storminess") else 0.0
	_weather_turb = clampf(Weather.wind_strength * 0.25 + storm * 0.45 + Weather.rain_intensity * 0.1, 0.0, 1.0)
	_wind = Weather.get_wind_vector() * 4.0 if Weather.has_method("get_wind_vector") else Vector3.ZERO
	_wind.y = 0.0
	_grip_env = float(Weather.get_grip_multiplier()) if Weather.has_method("get_grip_multiplier") else 1.0


func _probe_ground(space: PhysicsDirectSpaceState3D, origin: Vector3) -> void:
	var from := origin + Vector3.UP * 0.5
	_agl_q.from = from
	_agl_q.to = from + Vector3.DOWN * AGL_MAX
	var hit := space.intersect_ray(_agl_q)
	var ground_y := -INF
	if not hit.is_empty():
		ground_y = (hit["position"] as Vector3).y
	var water_y := Game.WATER_LEVEL
	if water_y > ground_y and Game.is_in_water(Vector3(origin.x, water_y - 0.3, origin.z)):
		altitude_agl = maxf(origin.y - water_y, 0.0)
	elif ground_y > -INF:
		altitude_agl = maxf(origin.y - ground_y, 0.0)
	else:
		altitude_agl = AGL_MAX


func _touchdown(sink: float) -> void:
	last_touchdown_sink = sink
	if sink > _touchdown_sink and damage != null:
		var extra := (sink - _touchdown_sink) * 85.0
		damage.apply(Dmg.make(extra, "collision", driver if driver != null else self, global_position, Vector3.DOWN, {"hard_landing": true}))
		if is_player_driven:
			Fx.shake_camera(clampf(sink / 10.0, 0.2, 0.8))
		if audio != null:
			audio.play_crash(sink, global_position)
	if sink > 0.8 and detail_level <= 1:
		for leg: GearLeg in _gear:
			if leg.braked:
				Fx.tire_smoke(global_transform * (leg.pos - Vector3(0.0, leg.radius, 0.0)), clampf(airspeed / 40.0, 0.3, 1.0))


func _on_collision(other: Node, dv: float, pos: Vector3, normal: Vector3, pre_speed: float) -> void:
	super._on_collision(other, dv, pos, normal, pre_speed)
	if not destroyed and dv > _explode_dv and is_inside_tree():
		explode(get_last_instigator())


func _check_water() -> void:
	var was := in_water
	var speed := linear_velocity.length()
	super._check_water()
	if in_water and not was and not destroyed and damage != null:
		# ditching: a fast water impact tears the aircraft apart, a slow one just floods the engine
		if speed > 22.0:
			damage.apply(Dmg.make((speed - 22.0) * 35.0, "collision", driver if driver != null else self, global_position, Vector3.DOWN, {"ditch": true}))
		if is_player_driven:
			UI.notify("Ditched in the sea", "bad")


func _integrate_water(state: PhysicsDirectBodyState3D) -> void:
	super._integrate_water(state)
	# skimming the water: strong drag on the hull while any part is below the surface
	var low := state.transform.origin.y + 0.4
	if low < Game.WATER_LEVEL:
		var sub := clampf((Game.WATER_LEVEL - low) / 1.0, 0.0, 1.0)
		state.apply_central_force(-state.linear_velocity * mass * 0.9 * sub)


func get_exit_transform(seat: int = 0) -> Transform3D:
	if is_inside_tree() and altitude_agl > 2.5 and not on_ground:
		var gt := global_transform
		var p := _exit_local(seat)
		var sn := get_seat_node(seat)
		p.y = xform_in_body(sn).origin.y if sn != null else 1.2
		p.x = signf(p.x if absf(p.x) > 0.05 else -1.0) * (body_aabb.size.x * 0.25 + 1.2)
		var f := -gt.basis.z
		f.y = 0.0
		var facing := Basis(Vector3.UP, atan2(-f.x, -f.z)) if f.length() > 0.05 else Basis.IDENTITY
		return Transform3D(facing, gt * p)
	return super.get_exit_transform(seat)


func occupant_enter(who: Node, seat: int = 0) -> void:
	_canopy_timer = 1.4
	super.occupant_enter(who, seat)


func occupant_exit(seat: int = 0) -> Transform3D:
	_canopy_timer = 1.6
	return super.occupant_exit(seat)


func release_inputs() -> void:
	_ai_brake = 0.0
	super.release_inputs()


func _driver_left() -> void:
	super._driver_left()
	_ai_brake = 0.0
	in_power = 0.0


## Aircraft have no brake lamps (M_Taillight is the red beacon / nav light).
func is_braking() -> bool:
	return false


func _on_teleported() -> void:
	_rest_t = 0.0
	_sleep_request = false
	_air_t = 0.0
	for leg: GearLeg in _gear:
		leg.ang_vel = 0.0
		leg.compression = 0.0


func _on_destroyed() -> void:
	engine_on = false
	throttle = 0.0
	engine_power = 0.0


# ==============================================================================================
# audio helper: long-range engine loop driven by prop / fan speed (replaces the car audio)
# ==============================================================================================

class AirAudio extends VehicleAudio:
	var audio_range: float = 300.0
	var local_pos: Vector3 = Vector3.ZERO

	func update(delta: float) -> void:
		if v == null or not v.is_inside_tree():
			return
		var rf := v.get_rpm_factor()
		var active := not v.destroyed and bool(v.get("air_audio_active")) and rf > 0.03
		if active:
			if engine == null:
				engine = _make(v.spec.sound_engine, audio_range, "Engine", local_pos)
				if engine != null:
					engine.max_distance = audio_range
					engine.volume_db = -30.0
			if _usable(engine):
				var spd := clampf(float(v.get("airspeed")) / 80.0, 0.0, 1.0)
				engine.pitch_scale = lerpf(v.spec.engine_pitch_min, v.spec.engine_pitch_max, rf) + spd * 0.08
				var target := lerpf(-24.0, -1.0, clampf(rf, 0.0, 1.0)) + v.get_engine_load() * 2.0
				engine.volume_db = lerpf(engine.volume_db, target, clampf(delta * 5.0, 0.0, 1.0))
				if not engine.playing:
					engine.play()
		elif _usable(engine) and engine.playing:
			engine.stop()
