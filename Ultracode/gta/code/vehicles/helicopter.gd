class_name Helicopter
extends VehicleBase
## Arcade-realistic helicopter (spec ids heli_civil, heli_police). Easy to fly on a keyboard:
##
##   power (W / S, AI in_power 0..1) = collective STICK: 0.5 holds the vertical speed at zero,
##       1 = full climb, 0 = full descent. On the ground a neutral stick keeps the rotor at flat pitch.
##   cyclic (arrows / numpad, in_pitch / in_roll -1..1) = attitude command: the stick sets the target
##       pitch / bank angle, releasing it levels the aircraft (weaker + turbulent at low "flying"
##       skill and in bad weather). Near the hover a stability assist leans against the drift.
##   pedals (A / D, in_yaw -1..1) = yaw-rate command; at speed the tail weathervanes into the wind.
##
## Physics: rotor thrust along the body up axis = collective x available thrust (rotor rpm^2, damage
## power factor, density / service ceiling ~350 m) x (1 + ground effect + translational lift).
## The two bonuses are outside the vertical-speed loop, so they are felt (cushion near the ground,
## a little "balloon" when accelerating through ~10 m/s). Attitude torques are computed as
## inertia x angular acceleration, so tuning does not depend on the model's box inertia.
## Contacts: the Col_* hulls (skids reach y = 0). Damage: hard landings and crashes through the
## shared collision path, rotor strikes (rays around the disc), explosion above `crash_explode_dv`.
##
## AI: set_flight_inputs(pitch, roll, yaw, power) or the autopilot: fly_to(), hover_at(), orbit(),
## stop_autopilot(). Police: set_searchlight(on, target). Tuning: spec metadata "air" (see
## vehicles_air_registry.gd) and docs/AIRCRAFT.md.

const GRAV := 9.81
const MAIN_REV_PER_S := 6.2          ## visual main rotor speed at 100 % rpm (rev/s)
const TAIL_REV_PER_S := 28.0
const AUDIO_RANGE := 320.0
const WASH_HEIGHT := 22.0
const GROUND_IDLE := 0.22            ## collective with a neutral stick on the ground (flat pitch)
const STRIKE_MASK := Layers.WORLD | Layers.VEHICLE | Layers.PROP | Layers.NPC | Layers.PLAYER
const AGL_MASK := Layers.WORLD | Layers.VEHICLE | Layers.PROP
const AGL_MAX := 800.0
const SOFT_LIMIT_NOTIFY_SEC := 8.0
const BEAM_SHADER := "shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
global uniform float gta_night;
uniform vec4 beam_color : source_color = vec4(1.0, 0.96, 0.82, 1.0);
uniform float strength = 0.22;
varying float v_along;
void vertex() { v_along = clamp(0.5 - VERTEX.y, 0.0, 1.0); }
void fragment() {
	float edge = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.6);
	float fade = (1.0 - v_along) * (1.0 - v_along);
	ALBEDO = beam_color.rgb;
	ALPHA = clamp(strength * edge * fade * mix(0.15, 1.0, gta_night), 0.0, 1.0);
}"

# --- public state (HUD / AI / debug) ---------------------------------------------------------
var rotor_rpm: float = 0.0           ## 0..1 main rotor speed
var collective: float = 0.0          ## 0..1 applied blade pitch (share of the available thrust)
var lift_force: float = 0.0          ## N, current rotor thrust
var altitude_agl: float = 0.0        ## metres above ground / water under the skids
var vertical_speed: float = 0.0      ## m/s, + = climbing
var airspeed: float = 0.0            ## m/s through the air (wind removed)
var on_ground: bool = true
var rotor_diameter: float = 9.5
var ground_effect: float = 0.0       ## current lift bonus 0..
var translational_lift: float = 0.0  ## current lift bonus 0..
var turbulence: float = 0.0          ## current turbulence amplitude (rad/s^2)
var searchlight_on: bool = false
var searchlight_target: Vector3 = Vector3.INF
var autopilot_mode: String = ""      ## "", "fly_to", "hover", "orbit"
var air_audio_active: bool = false   ## AirAudio: inside hearing range of the camera
var last_touchdown_sink: float = 0.0 ## m/s sink rate of the last touchdown
var rotor_strikes: int = 0

# --- tuning (spec metadata "air") ---------------------------------------------------------------
var _lift_ratio: float = 1.55
var _climb: float = 8.0
var _descent: float = 6.5
var _max_pitch: float = deg_to_rad(26.0)
var _max_roll: float = deg_to_rad(30.0)
var _yaw_rate: float = deg_to_rad(75.0)
var _kp: float = 9.0
var _kd: float = 5.2
var _ky: float = 5.0
var _top_speed: float = 46.0
var _spool_up: float = 4.0
var _spool_down: float = 9.0
var _ceiling: float = 350.0
var _weathervane: float = 0.55
var _explode_dv: float = 17.0
var _hard_sink: float = 4.5
var _has_searchlight: bool = false
var _drag_h: float = 0.002

# --- parts ---------------------------------------------------------------------------------------
var _rotor: Node3D = null
var _rotor_rest: Transform3D
var _rotor_blur: GeometryInstance3D = null
var _rotor_geo: Array[GeometryInstance3D] = []
var _tail: Node3D = null
var _tail_rest: Transform3D
var _tail_geo: Array[GeometryInstance3D] = []
var _hub_local: Vector3 = Vector3(0.0, 3.0, 0.0)
var _rotor_angle: float = 0.0
var _tail_angle: float = 0.0
var _blur_shown: float = -1.0
var _search_node: Node3D = null
var _search_rest: Transform3D
var _search_light: SpotLight3D = null
var _search_beam: MeshInstance3D = null
var _search_q: Quaternion = Quaternion.IDENTITY

# --- simulation ------------------------------------------------------------------------------
var _air_t: float = 0.0              ## seconds airborne
var _rest_t: float = 0.0
var _sleep_request: bool = false
var _strike_phase: float = 0.0
var _strike_cd: float = 0.0
var _strike_q: PhysicsRayQueryParameters3D = null
var _agl_q: PhysicsRayQueryParameters3D = null
var _ground_point: Vector3 = Vector3.ZERO
var _ground_valid: bool = false
var _wash_t: float = 0.0
var _turb_t: float = 0.0
var _env_t: float = 0.0
var _skill: float = 0.0
var _weather_turb: float = 0.0
var _wind: Vector3 = Vector3.ZERO
var _fly_xp_t: float = 0.0
var _audio_t: float = 0.0
var _limit_notify_t: float = 0.0
var _beacon_t: float = 0.0
var _strobe_t: float = 0.0
var _beacon_mat: BaseMaterial3D = null
var _grav: float = GRAV
var _pending_touchdown: float = -1.0 ## sink rate recorded in _integrate_forces, handled in _physics_process
var _pending_strike: Array = []      ## [position, normal, collider, direction]
var _pending_limit_notify: bool = false

# --- autopilot -------------------------------------------------------------------------------
var _ap_target: Vector3 = Vector3.ZERO
var _ap_alt: float = 30.0
var _ap_radius: float = 40.0
var _ap_speed: float = 22.0
var _ap_dir: float = 1.0
var _ap_heading: float = INF
var _ap_alt_i: float = 0.0

static var _beam_mat: ShaderMaterial = null


# ==============================================================================================
# construction
# ==============================================================================================

func _build_drive(_opts: Dictionary) -> void:
	self_righting = false
	var air: Dictionary = spec.get_meta("air", {}) if spec.has_meta("air") else {}
	_lift_ratio = float(air.get("lift_ratio", 1.55))
	_climb = float(air.get("climb_rate", 8.0))
	_descent = float(air.get("descent_rate", 6.5))
	_max_pitch = deg_to_rad(float(air.get("max_pitch_deg", 26.0)))
	_max_roll = deg_to_rad(float(air.get("max_roll_deg", 30.0)))
	_yaw_rate = deg_to_rad(float(air.get("yaw_rate_deg", 75.0)))
	_kp = float(air.get("attitude_gain", 9.0))
	_kd = float(air.get("attitude_damp", 5.2))
	_ky = float(air.get("yaw_gain", 5.0))
	_top_speed = float(air.get("top_speed", 46.0))
	_spool_up = maxf(float(air.get("spool_up", 4.0)), 0.5)
	_spool_down = maxf(float(air.get("spool_down", 9.0)), 0.5)
	_ceiling = float(air.get("ceiling", 350.0))
	_weathervane = float(air.get("weathervane", 0.55))
	_explode_dv = float(air.get("crash_explode_dv", 17.0))
	_hard_sink = float(air.get("hard_landing_sink", 4.5))
	_has_searchlight = bool(air.get("searchlight", false))
	# level flight at full forward cyclic reaches top_speed: drag(top) = g tan(max pitch)
	_drag_h = GRAV * tan(_max_pitch) / maxf(_top_speed * _top_speed, 1.0)

	_rotor = get_part("Rotor_Main")
	if _rotor != null:
		_rotor_rest = _rotor.transform
		_hub_local = xform_in_body(_rotor).origin
		_rotor_geo = _geometry_of(_rotor)
	var blur := get_part("RotorBlur_Main")
	if blur != null:
		var ba := aabb_in_body(blur)
		rotor_diameter = maxf(maxf(ba.size.x, ba.size.z), 2.0)
		_rotor_blur = blur as GeometryInstance3D
		for g: GeometryInstance3D in _geometry_of(blur):
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blur.visible = false
	elif _rotor != null:
		var ra := aabb_in_body(_rotor)
		rotor_diameter = maxf(maxf(ra.size.x, ra.size.z), 2.0)
	_tail = get_part("Rotor_Tail")
	if _tail != null:
		_tail_rest = _tail.transform
		_tail_geo = _geometry_of(_tail)
	_search_node = get_part("Searchlight")
	if _search_node != null:
		_search_rest = _search_node.transform
		_search_q = _search_rest.basis.get_rotation_quaternion()

	_grav = float(ProjectSettings.get_setting("physics/3d/default_gravity", GRAV))
	_agl_q = PhysicsRayQueryParameters3D.new()
	_agl_q.collision_mask = AGL_MASK
	_strike_q = PhysicsRayQueryParameters3D.new()
	_strike_q.collision_mask = STRIKE_MASK


func _geometry_of(n: Node3D) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	var list: Array[Node] = [n]
	list.append_array(n.find_children("*", "GeometryInstance3D", true, false))
	for c: Node in list:
		var g := c as GeometryInstance3D
		if g != null:
			out.append(g)
	return out


## The centre of mass is measured from the rotor mast (model origin), not from the body centre.
func _get_reference_z() -> float:
	return 0.0


func _ready() -> void:
	super._ready()
	_agl_q.exclude = [get_rid()]
	_strike_q.exclude = [get_rid()]
	# replace the car audio helper with the aircraft one (long range, rotor rpm driven)
	var aa := AirAudio.new()
	aa.setup(self)
	aa.audio_range = AUDIO_RANGE
	aa.local_pos = _hub_local
	audio = aa
	_beacon_mat = lights.tail_mat if lights != null else null


# ==============================================================================================
# public API
# ==============================================================================================

## Rotor spin-up / the HUD use this as "engine speed".
func get_rpm_factor() -> float:
	return rotor_rpm


func get_engine_load() -> float:
	return clampf(collective, 0.0, 1.0)


func get_camera_params() -> Dictionary:
	var p := super.get_camera_params()
	var d: float = float(p.get("distance", 10.0))
	p["distance"] = d + clampf(airspeed * 0.04, 0.0, 2.2)
	return p


## Telemetry for debug overlays / tests.
func get_telemetry() -> Dictionary:
	return {
		"rotor_rpm": rotor_rpm, "collective": collective, "lift": lift_force, "agl": altitude_agl,
		"vs": vertical_speed, "airspeed": airspeed, "on_ground": on_ground, "ground_effect": ground_effect,
		"translational_lift": translational_lift, "turbulence": turbulence, "autopilot": autopilot_mode,
		"health": health, "rotor_strikes": rotor_strikes,
	}


## Police searchlight (heli_police has the Searchlight part). target = Vector3.INF points it
## forward-down in its rest pose; otherwise it tracks the world position (gimbal limited).
func set_searchlight(on: bool, target_position: Vector3 = Vector3.INF) -> void:
	searchlight_on = on and _search_node != null and not destroyed
	searchlight_target = target_position
	if searchlight_on:
		_ensure_searchlight()
	if _search_light != null:
		_search_light.visible = searchlight_on
	if _search_beam != null:
		_search_beam.visible = searchlight_on


func has_searchlight() -> bool:
	return _search_node != null


## Autopilot: fly to `position` (x / z) at `altitude` (world y; NaN/INF = keep the current one)
## and hover there on arrival. Takes over in_* until stop_autopilot() / release_inputs().
func fly_to(position: Vector3, altitude: float = INF, cruise_speed: float = 24.0) -> void:
	_begin_autopilot("fly_to", position, altitude)
	_ap_speed = maxf(cruise_speed, 2.0)


## Autopilot: hold `position` (x / z) at `altitude` (world y).
func hover_at(position: Vector3, altitude: float = INF) -> void:
	_begin_autopilot("hover", position, altitude)


## Autopilot: circle `target_position` at `radius` and `altitude` (world y), nose toward the target
## (searchlight / gunners). direction +1 counter-clockwise seen from above, -1 clockwise.
func orbit(target_position: Vector3, radius: float = 40.0, altitude: float = INF, speed: float = 14.0, direction: float = 1.0) -> void:
	_begin_autopilot("orbit", target_position, altitude)
	_ap_radius = maxf(radius, 8.0)
	# keep the circle flyable: centripetal acceleration within ~70 % of the bank limit
	var v_max := sqrt(_grav * tan(_max_roll) * 0.7 * _ap_radius)
	_ap_speed = clampf(minf(speed, v_max), 2.0, _top_speed * 0.8)
	_ap_dir = -1.0 if direction < 0.0 else 1.0


## Move the autopilot target without resetting its mode (chasing a moving target).
func set_autopilot_target(position: Vector3, altitude: float = INF) -> void:
	_ap_target = position
	if altitude != INF and not is_nan(altitude):
		_ap_alt = altitude


## Fix the heading the autopilot holds while hovering (radians, 0 = north). INF = automatic.
func set_autopilot_heading(heading: float) -> void:
	_ap_heading = heading


func stop_autopilot() -> void:
	autopilot_mode = ""
	_ap_alt_i = 0.0


func is_autopilot_active() -> bool:
	return autopilot_mode != ""


func release_inputs() -> void:
	stop_autopilot()
	super.release_inputs()


## Direct AI control (cancels the autopilot). power: 0.5 hold height, 1 climb, 0 descend.
func set_flight_inputs(pitch: float, roll: float, yaw: float, power: float) -> void:
	if autopilot_mode != "":
		stop_autopilot()
	super.set_flight_inputs(pitch, roll, yaw, power)


func _begin_autopilot(mode: String, position: Vector3, altitude: float) -> void:
	if destroyed:
		return
	autopilot_mode = mode
	_ap_target = position
	_ap_alt = global_position.y if (altitude == INF or is_nan(altitude)) else altitude
	_ap_heading = INF
	_ap_alt_i = 0.0
	_scripted = true
	if not engine_on:
		start_engine()
	sleeping = false


# ==============================================================================================
# input
# ==============================================================================================

func _read_player_input(_delta: float) -> void:
	var up := Input.get_action_strength("air_throttle_up")
	var down := Input.get_action_strength("air_throttle_down")
	in_power = clampf(0.5 + 0.5 * (up - down), 0.0, 1.0)
	in_pitch = Input.get_action_strength("air_pitch_up") - Input.get_action_strength("air_pitch_down")
	in_roll = Input.get_action_strength("air_roll_right") - Input.get_action_strength("air_roll_left")
	in_yaw = Input.get_action_strength("air_yaw_right") - Input.get_action_strength("air_yaw_left")
	if up > 0.1 and not engine_on and not stalled:
		start_engine()


func _read_player_toggles() -> void:
	if Input.is_action_just_pressed("headlights"):
		set_headlights((headlight_mode + 1) % 3)
	if _search_node != null and Input.is_action_just_pressed("siren"):
		set_searchlight(not searchlight_on)


func _wants_wake() -> bool:
	return (in_power > 0.56 and not stalled) or autopilot_mode != ""


# ==============================================================================================
# frame updates
# ==============================================================================================

func _physics_process(delta: float) -> void:
	if _sleep_request:
		_sleep_request = false
		if not destroyed and in_power <= 0.56 and autopilot_mode == "":
			sleeping = true
			_on_sleep()
	# rotor spool (also while asleep: a parked helicopter still spins down)
	var want := 1.0 if (engine_on and not destroyed and not stalled) else 0.0
	var rate := (1.0 / _spool_up) if want > rotor_rpm else (1.0 / _spool_down)
	if destroyed:
		rate = 1.2
	rotor_rpm = move_toward(rotor_rpm, want, rate * delta)
	if autopilot_mode != "" and not is_player_driven and not destroyed:
		_run_autopilot(delta)
	_xp_t = 0.0                          # flying earns "flying", not "driving" (see VehicleBase)
	super._physics_process(delta)
	if destroyed:
		return
	_strike_cd = maxf(_strike_cd - delta, 0.0)
	if _pending_touchdown >= 0.0:
		_touchdown(_pending_touchdown)
		_pending_touchdown = -1.0
	if not _pending_strike.is_empty():
		var ps := _pending_strike
		_pending_strike = []
		_rotor_strike(ps[0], ps[1], ps[2], ps[3])
	if _pending_limit_notify:
		_pending_limit_notify = false
		UI.notify("Airspace limit - turning back to Halcyon Bay", "warn")
	if is_player_driven:
		_fly_xp_t += delta
		if _fly_xp_t >= 1.0:
			_fly_xp_t = 0.0
			if not on_ground:
				Skills.add_xp("flying", 0.016 * clampf(airspeed / 25.0, 0.35, 1.0))
		_limit_notify_t = maxf(_limit_notify_t - delta, 0.0)
	# rotor wash on the ground / water under the disc
	_wash_t -= delta
	if _wash_t <= 0.0:
		_wash_t = 0.12
		if rotor_rpm > 0.4 and _ground_valid and altitude_agl < WASH_HEIGHT and detail_level <= 1:
			var st := rotor_rpm * clampf(collective * 1.6, 0.3, 1.2) * (1.0 - altitude_agl / WASH_HEIGHT)
			Fx.rotor_wash(_ground_point, st)


func _on_sleep() -> void:
	_rest_t = 0.0
	vertical_speed = 0.0
	airspeed = 0.0
	speed_kmh = 0.0


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
		_spin_rotors(delta)              # far away: no other visuals, but the rotors keep turning
		if searchlight_on:
			_update_searchlight(delta)


func _update_visuals(delta: float) -> void:
	_spin_rotors(delta)
	if searchlight_on:
		_update_searchlight(delta)
	_update_beacons(delta)


func _spin_rotors(delta: float) -> void:
	if _rotor != null:
		_rotor_angle = wrapf(_rotor_angle + rotor_rpm * MAIN_REV_PER_S * TAU * delta, 0.0, TAU)
		_rotor.transform = _rotor_rest * Transform3D(Basis(Vector3.UP, _rotor_angle), Vector3.ZERO)
	if _tail != null:
		_tail_angle = wrapf(_tail_angle + rotor_rpm * TAIL_REV_PER_S * TAU * delta, 0.0, TAU)
		_tail.transform = _tail_rest * Transform3D(Basis(Vector3.RIGHT, _tail_angle), Vector3.ZERO)
	# blades fade into the blur disc as the rotor comes up to speed
	var blur := smoothstep(0.32, 0.8, rotor_rpm)
	if absf(blur - _blur_shown) < 0.01:
		return
	_blur_shown = blur
	if _rotor_blur != null:
		_rotor_blur.visible = blur > 0.01
		_rotor_blur.transparency = 1.0 - blur
	for g: GeometryInstance3D in _rotor_geo:
		g.transparency = blur * 0.6
	for g: GeometryInstance3D in _tail_geo:
		g.transparency = blur * 0.55


func _update_beacons(delta: float) -> void:
	# red anti-collision beacon (M_Taillight) flashes while the engine runs; police belly strobes
	if _beacon_mat != null and (engine_on or rotor_rpm > 0.2):
		_beacon_t = fmod(_beacon_t + delta, 1.1)
		var base := 1.1 if headlight_mode > 0 else 0.35
		_beacon_mat.emission_energy_multiplier = 6.5 if _beacon_t < 0.12 else base
	if is_police and lights != null and engine_on:
		_strobe_t = fmod(_strobe_t + delta, 0.9)
		if lights.siren_red_mat != null:
			lights.siren_red_mat.emission_energy_multiplier = 7.0 if _strobe_t < 0.08 else 0.0
		if lights.siren_blue_mat != null:
			lights.siren_blue_mat.emission_energy_multiplier = 7.0 if (_strobe_t > 0.45 and _strobe_t < 0.53) else 0.0


# ==============================================================================================
# physics
# ==============================================================================================

func _integrate_vehicle(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	var xf := state.transform
	var b := xf.basis.orthonormalized()
	var up := b.y
	var lin := state.linear_velocity
	var ang := state.angular_velocity
	var weight := mass * _grav

	_env_t -= dt
	if _env_t <= 0.0:
		_env_t = 0.5
		_refresh_environment()

	# --- probes: height above ground / water
	_probe_ground(state.get_space_state(), xf.origin)
	var touching := state.get_contact_count() > 0
	var was_ground := on_ground
	on_ground = touching and altitude_agl < 0.6
	vertical_speed = lin.y
	var air_v := lin - _wind
	airspeed = air_v.length()
	var h_air := Vector2(air_v.x, air_v.z).length()
	if on_ground:
		if not was_ground and _air_t > 0.6:
			_pending_touchdown = maxf(-_prev_lin.y, 0.0)
		_air_t = 0.0
	else:
		_air_t += dt

	# --- collective: vertical-speed command -> blade pitch
	var pwr := clampf(in_power, 0.0, 1.0)
	var stick := (pwr - 0.5) * 2.0
	var vs_cmd := stick * (_climb if stick > 0.0 else _descent)
	if _ground_valid and altitude_agl < 8.0:
		vs_cmd = maxf(vs_cmd, -(1.1 + altitude_agl * 0.7))   # landing assist: the last metres are gentle
	var pf := get_power_factor()
	if get_health_ratio() < 0.25:
		pf *= 0.82 + 0.18 * sin(_turb_t * 6.3)          # failing engine: surging power
	var alt_frac := clampf((xf.origin.y - (_ceiling - 200.0)) / 200.0, 0.0, 1.6)
	var alt_f := lerpf(1.0, 0.985 / _lift_ratio, alt_frac)
	var avail := weight * _lift_ratio * rotor_rpm * rotor_rpm * pf * alt_f
	var col_target := 0.0
	if on_ground and pwr <= 0.56 and autopilot_mode == "":
		col_target = GROUND_IDLE
	elif on_ground and pwr <= 0.52:
		col_target = GROUND_IDLE
	else:
		var a_cmd := clampf((vs_cmd - lin.y) * 1.7, -7.0, 7.0)
		var vy_air := lin.y - _wind.y
		var drag_ff := (vy_air * absf(vy_air) * 0.035 + vy_air * 0.12) * mass
		var need := (mass * (_grav + a_cmd) + drag_ff) / maxf(up.y, 0.4)
		col_target = clampf(need / maxf(avail, 1.0), 0.0, 1.0)
	collective = move_toward(collective, col_target, dt * 2.6)

	# --- thrust: + ground effect + translational lift (felt, not cancelled by the loop)
	ground_effect = 0.0
	if _ground_valid:
		var ge := clampf(1.0 - altitude_agl / (rotor_diameter * 0.9), 0.0, 1.0)
		ground_effect = 0.16 * ge * ge
	translational_lift = 0.11 * smoothstep(4.0, 13.0, h_air) - 0.04 * smoothstep(30.0, 60.0, h_air)
	lift_force = collective * avail * (1.0 + ground_effect + translational_lift)
	var force := up * lift_force

	# --- aerodynamic drag: rotor disc / fuselage
	var hv := Vector3(air_v.x, 0.0, air_v.z)
	force += -hv * (h_air * _drag_h * mass + 0.06 * mass)
	force.y += -air_v.y * absf(air_v.y) * 0.035 * mass - air_v.y * 0.12 * mass
	if not on_ground:
		force += Vector3(_wind.x, 0.0, _wind.z) * mass * 0.05      # light drift in the wind

	# --- attitude: cyclic sets target pitch / bank, self-levelling without input
	var fwd := -b.z
	var heading := atan2(-fwd.x, -fwd.z) if Vector2(fwd.x, fwd.z).length() > 0.2 else atan2(up.x, up.z)
	var hb := Basis(Vector3.UP, heading)
	var lift_share := lift_force / maxf(weight, 1.0)
	var ap := autopilot_mode != ""
	var tp := clampf(in_pitch, -1.0, 1.0) * _max_pitch
	var tr := clampf(in_roll, -1.0, 1.0) * _max_roll
	var no_p := absf(in_pitch) < 0.05 and not ap
	var no_r := absf(in_roll) < 0.05 and not ap
	if not on_ground:
		# stability assist (the "pilot" holding the hover): lean against the GROUND speed while the
		# stick is centred, which also flares a released helicopter to a stop
		var hl := hb.inverse() * Vector3(lin.x, 0.0, lin.z)     # x = right, z = back
		var h_ground := Vector2(lin.x, lin.z).length()
		var assist := 1.0 - smoothstep(18.0, 40.0, h_ground)
		var k_assist := lerpf(0.024, 0.036, _skill)
		if no_p:
			tp += clampf(-hl.z * k_assist, -0.19, 0.19) * assist
		if no_r:
			tr += clampf(-hl.x * k_assist, -0.17, 0.17) * assist
	if on_ground and lift_share < 0.9:
		tp = 0.0
		tr = 0.0
	var tb := hb * Basis(Vector3.RIGHT, tp) * Basis(Vector3.BACK, -tr)
	var err := b.inverse() * up.cross(tb.y)    # body axes: x pitch, z roll (sin of the error)
	var wl := b.inverse() * ang
	var level_k := lerpf(0.5, 1.0, _skill) * (1.0 - 0.25 * clampf(_weather_turb, 0.0, 1.0))
	var kp_p := _kp * (level_k if no_p else 1.0)
	var kp_r := _kp * (level_k if no_r else 1.0)
	var authority := clampf(rotor_rpm * rotor_rpm * 1.25, 0.0, 1.0)
	if on_ground:
		authority *= clampf((lift_share - 0.45) * 2.0, 0.0, 1.0)
	var alpha := Vector3(
		err.x * kp_p - wl.x * _kd,
		0.0,
		err.z * kp_r - wl.z * _kd)
	# pedals: yaw-rate command, weathervane into the relative wind at speed
	var yaw_target := -clampf(in_yaw, -1.0, 1.0) * _yaw_rate
	var al := b.inverse() * air_v
	if h_air > 6.0 and not on_ground:
		var beta := atan2(al.x, maxf(-al.z, 0.5))
		yaw_target += -beta * _weathervane * smoothstep(6.0, 20.0, h_air)
	alpha.y = (yaw_target - wl.y) * _ky
	alpha *= authority
	if on_ground and authority < 0.05:
		alpha = Vector3.ZERO
	# turbulence (low skill, wind, storms): smooth pseudo-random angular accelerations
	_turb_t += dt
	turbulence = 0.0
	if not on_ground and rotor_rpm > 0.5:
		turbulence = (0.22 * (1.0 - _skill) + _weather_turb) * clampf(_air_t / 2.0, 0.0, 1.0)
		if turbulence > 0.005:
			var t := _turb_t
			alpha += Vector3(
				sin(t * 1.71 + 0.4) * 0.6 + sin(t * 4.37 + 2.1) * 0.4,
				sin(t * 1.13 + 1.7) * 0.5 + sin(t * 3.21 + 0.2) * 0.3,
				sin(t * 2.03 + 3.3) * 0.6 + sin(t * 5.11 + 1.3) * 0.4) * turbulence
			force.y += sin(t * 0.93 + 0.8) * sin(t * 2.71) * turbulence * mass * 1.6

	# --- player beyond the soft world limit: gently turned back toward the island
	if is_player_driven:
		var hp := Vector2(xf.origin.x, xf.origin.z)
		var d := hp.length()
		if d > Game.WORLD_SOFT_LIMIT:
			var out_dir := Vector3(hp.x / d, 0.0, hp.y / d)
			var over := clampf((d - Game.WORLD_SOFT_LIMIT) / 150.0, 0.15, 1.0)
			force -= out_dir * mass * 3.0 * over
			force -= out_dir * maxf(lin.dot(out_dir), 0.0) * mass * 0.5
			var home := atan2(out_dir.x, out_dir.z)          # heading that faces the origin
			alpha.y += wrapf(home - heading, -PI, PI) * 1.2 * over
			if _limit_notify_t <= 0.0:
				_limit_notify_t = SOFT_LIMIT_NOTIFY_SEC
				_pending_limit_notify = true

	state.apply_central_force(force)
	state.apply_torque(b * (alpha * inertia))

	# --- rotor strikes: two rays sweep the disc each step
	if rotor_rpm > 0.35 and _strike_cd <= 0.0:
		_check_rotor_strike(state, xf, b)

	# --- rest detection (sleep on the pad)
	if on_ground and in_power <= 0.56 and autopilot_mode == "" and lin.length_squared() < 0.01 and ang.length_squared() < 0.004:
		_rest_t += dt
		if _rest_t > 1.2:
			_rest_t = 0.0
			_sleep_request = true
	else:
		_rest_t = 0.0


func _integrate_common(state: PhysicsDirectBodyState3D) -> void:
	super._integrate_common(state)
	speed_kmh = state.linear_velocity.length() * 3.6


func _refresh_environment() -> void:
	_skill = Skills.get_factor("flying") if is_player_driven else 0.75
	var storm := 0.0
	if Weather.has_method("get_storminess"):
		storm = float(Weather.get_storminess())
	_weather_turb = clampf(Weather.wind_strength * 0.35 + storm * 0.55 + Weather.rain_intensity * 0.15, 0.0, 1.2)
	_wind = Weather.get_wind_vector() * 4.0 if Weather.has_method("get_wind_vector") else Vector3.ZERO
	_wind.y = 0.0


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
		_ground_point = Vector3(origin.x, water_y, origin.z)
		_ground_valid = true
	elif ground_y > -INF:
		altitude_agl = maxf(origin.y - ground_y, 0.0)
		_ground_point = hit["position"]
		_ground_valid = true
	else:
		altitude_agl = AGL_MAX
		_ground_valid = false


func _touchdown(sink: float) -> void:
	last_touchdown_sink = sink
	if sink > _hard_sink and damage != null:
		# the skids take the hit on top of the hull impact (VehicleDamage.on_collision)
		var extra := (sink - _hard_sink) * 45.0
		damage.apply(Dmg.make(extra, "collision", driver if driver != null else self, global_position, Vector3.DOWN, {"hard_landing": true}))
		if is_player_driven:
			Fx.shake_camera(clampf(sink / 12.0, 0.2, 0.8))
	if sink > 1.5 and _ground_valid and detail_level <= 1:
		Fx.dust(_ground_point, clampf(sink / 4.0, 0.5, 1.5))


func _check_rotor_strike(state: PhysicsDirectBodyState3D, xf: Transform3D, b: Basis) -> void:
	var hub := xf * _hub_local
	var r := rotor_diameter * 0.5 * 0.97
	var space := state.get_space_state()
	for k in 2:
		var th := _strike_phase + float(k) * PI
		var dir := b * Vector3(cos(th), 0.0, sin(th))
		_strike_q.from = hub + dir * 0.6
		_strike_q.to = hub + dir * r
		var hit := space.intersect_ray(_strike_q)
		if hit.is_empty():
			continue
		var other: Variant = hit.get("collider", null)
		if other is Node and get_seat_of(other as Node) >= 0:
			continue
		_strike_cd = 0.3
		_pending_strike = [hit["position"], hit["normal"], other, dir]
		break
	_strike_phase = wrapf(_strike_phase + 0.83, 0.0, TAU)


func _rotor_strike(pos: Vector3, normal: Vector3, other: Variant, dir: Vector3) -> void:
	_strike_cd = 0.3
	rotor_strikes += 1
	var inst: Node = driver if driver != null else self
	var amount := 70.0 * rotor_rpm
	if damage != null:
		damage.apply(Dmg.make(amount, "collision", inst, pos, -dir, {"rotor_strike": true}))
	rotor_rpm *= 0.78
	Fx.sparks(pos, normal, 1.6)
	Audio.play_at("impact_metal", pos, 2.0, randf_range(0.7, 0.9), 90.0)
	EventBus.noise_emitted.emit(pos, 40.0, "crash", inst)
	# the blades kick the airframe: yaw + roll jolt
	apply_torque_impulse(global_transform.basis.y * mass * 1.6 + dir.cross(Vector3.UP) * mass * 0.9)
	if is_player_driven:
		Fx.shake_camera(0.55)
	if other != null and is_instance_valid(other) and other is Node:
		var on := other as Node
		var d := Dmg.find_damageable(on)
		if d != null and d != self:
			d.apply_damage(Dmg.make(120.0 * rotor_rpm + 30.0, "melee", inst, pos, dir, {"impulse": 400.0, "rotor": true}))


func _on_collision(other: Node, dv: float, pos: Vector3, normal: Vector3, pre_speed: float) -> void:
	super._on_collision(other, dv, pos, normal, pre_speed)
	if not destroyed and dv > _explode_dv and is_inside_tree():
		explode(get_last_instigator())


func _check_water() -> void:
	var was := in_water
	var speed := linear_velocity.length()
	super._check_water()
	if in_water and not was and not destroyed and speed > 14.0 and damage != null:
		damage.apply(Dmg.make((speed - 14.0) * 30.0, "collision", driver if driver != null else self, global_position, Vector3.DOWN, {"ditch": true}))


## In flight the occupant steps out beside the door (the player then falls / opens a parachute).
func get_exit_transform(seat: int = 0) -> Transform3D:
	if is_inside_tree() and altitude_agl > 2.5:
		var gt := global_transform
		var p := _exit_local(seat)
		var sn := get_seat_node(seat)
		p.y = xform_in_body(sn).origin.y if sn != null else 1.0
		p.x = signf(p.x if absf(p.x) > 0.05 else -1.0) * (body_aabb.size.x * 0.5 + 1.1)
		var f := -gt.basis.z
		f.y = 0.0
		var facing := Basis(Vector3.UP, atan2(-f.x, -f.z)) if f.length() > 0.05 else Basis.IDENTITY
		return Transform3D(facing, gt * p)
	return super.get_exit_transform(seat)


func _on_teleported() -> void:
	_rest_t = 0.0
	_sleep_request = false
	_air_t = 0.0
	collective = 0.0


func _on_destroyed() -> void:
	stop_autopilot()
	set_searchlight(false)
	engine_on = false
	rotor_rpm *= 0.35


func _on_repaired() -> void:
	_blur_shown = -1.0
	rotor_strikes = 0


# ==============================================================================================
# autopilot
# ==============================================================================================

func _run_autopilot(_delta: float) -> void:
	var p := global_position
	var v := linear_velocity
	var vh := Vector3(v.x, 0.0, v.z)
	var b := global_transform.basis.orthonormalized()
	var fwd := -b.z
	var heading := atan2(-fwd.x, -fwd.z)
	var to := _ap_target - p
	to.y = 0.0
	var d := to.length()
	var v_des := Vector3.ZERO
	var heading_des := heading if _ap_heading == INF else _ap_heading
	match autopilot_mode:
		"fly_to":
			if d > 1.0:
				var sp := minf(_ap_speed, sqrt(2.0 * 2.2 * maxf(d - 2.0, 0.0)) + 0.5)
				v_des = to / d * sp
			if d > 14.0 and _ap_heading == INF:
				heading_des = atan2(-to.x, -to.z)
		"hover":
			v_des = to * 0.45
			if v_des.length() > 7.0:
				v_des = v_des.normalized() * 7.0
		"orbit":
			var rel := p - _ap_target
			rel.y = 0.0
			var r := maxf(rel.length(), 0.1)
			var radial := rel / r
			var tangent := Vector3.UP.cross(radial) * _ap_dir
			v_des = tangent * _ap_speed + radial * clampf((_ap_radius - r) * 0.45, -8.0, 8.0)
			if _ap_heading == INF:
				heading_des = atan2(radial.x, radial.z)      # nose toward the target
	# vertical: altitude error -> climb / descent stick, small integral against steady errors
	var alt_err := _ap_alt - p.y
	_ap_alt_i = clampf(_ap_alt_i + alt_err * _delta * 0.04, -0.6, 0.6)
	var vs_des := clampf(alt_err * 0.55 + _ap_alt_i, -_descent * 0.9, _climb * 0.9)
	if altitude_agl < 6.0 and vs_des < -1.5 and alt_err > -altitude_agl + 0.5:
		vs_des = -1.5                                        # never slam into the ground on the way down
	var pwr := 0.5 + (vs_des / (2.0 * _climb) if vs_des > 0.0 else vs_des / (2.0 * _descent))
	# horizontal: velocity error -> acceleration -> attitude stick
	var a_des := (v_des - vh) * 0.85
	if autopilot_mode == "orbit":
		var rel2 := p - _ap_target
		rel2.y = 0.0
		var r2 := maxf(rel2.length(), 4.0)
		a_des += -rel2 / r2 * (_ap_speed * _ap_speed / r2)      # centripetal feed-forward
	var a_max := _grav * tan(maxf(_max_pitch, _max_roll)) * 0.95
	if a_des.length() > a_max:
		a_des = a_des.normalized() * a_max
	var hf := Vector3(fwd.x, 0.0, fwd.z).normalized() if Vector2(fwd.x, fwd.z).length() > 0.05 else Vector3.FORWARD
	var hr := Vector3(-hf.z, 0.0, hf.x)                     # right of the heading
	var a_f := a_des.dot(hf)
	var a_r := a_des.dot(hr)
	var tp := -atan(a_f / _grav)
	var tr := atan(a_r / _grav)
	var herr := wrapf(heading_des - heading, -PI, PI)
	in_pitch = clampf(tp / _max_pitch, -1.0, 1.0)
	in_roll = clampf(tr / _max_roll, -1.0, 1.0)
	in_yaw = -clampf(herr * 1.6, -1.0, 1.0)
	in_power = clampf(pwr, 0.0, 1.0)
	_scripted = true
	if not engine_on and not stalled:
		start_engine()


# ==============================================================================================
# searchlight
# ==============================================================================================

func _ensure_searchlight() -> void:
	if _search_node == null or _search_light != null:
		return
	var beam_marker := _search_node.find_child("Searchlight_Beam", true, false) as Node3D
	var holder: Node3D = beam_marker if beam_marker != null else _search_node
	_search_light = SpotLight3D.new()
	_search_light.name = "SearchSpot"
	_search_light.light_color = Color(1.0, 0.96, 0.85)
	_search_light.spot_range = 140.0
	_search_light.spot_angle = 8.5
	_search_light.spot_attenuation = 0.6
	_search_light.spot_angle_attenuation = 2.0
	_search_light.shadow_enabled = false
	_search_light.light_energy = 16.0
	holder.add_child(_search_light)
	if _beam_mat == null:
		var sh := Shader.new()
		sh.code = BEAM_SHADER
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = sh
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.004                     # per metre of beam length (the node is scaled by the length)
	cyl.bottom_radius = tan(deg_to_rad(8.5))
	cyl.height = 1.0
	cyl.radial_segments = 14
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_search_beam = MeshInstance3D.new()
	_search_beam.name = "SearchBeam"
	_search_beam.mesh = cyl
	_search_beam.material_override = _beam_mat
	_search_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(_search_beam)


func _update_searchlight(delta: float) -> void:
	if _search_node == null or not is_inside_tree():
		return
	var parent := _search_node.get_parent() as Node3D
	var pgt := parent.global_transform if parent != null else global_transform
	var want := _search_rest.basis.get_rotation_quaternion()
	if searchlight_target != Vector3.INF:
		var origin := (pgt * _search_rest).origin
		var dir := searchlight_target - origin
		if dir.length() > 0.5:
			var local_dir := (pgt.basis.inverse() * dir).normalized()
			local_dir.y = minf(local_dir.y, -0.08)        # the gimbal cannot look up into the fuselage
			local_dir = local_dir.normalized()
			var up_ref := Vector3.UP if absf(local_dir.y) < 0.95 else Vector3.BACK   # straight down: no parallel up vector
			want = Basis.looking_at(local_dir, up_ref).get_rotation_quaternion()
	_search_q = _search_q.slerp(want, clampf(delta * 3.0, 0.0, 1.0))
	_search_node.transform = Transform3D(Basis(_search_q), _search_rest.origin)
	if _search_light != null:
		_search_light.light_energy = lerpf(22.0, 5.0, WorldClock.get_daylight())
	if _search_beam != null:
		var length := 60.0
		if searchlight_target != Vector3.INF:
			length = clampf(_search_node.global_position.distance_to(searchlight_target), 4.0, 140.0)
		elif _ground_valid:
			length = clampf(altitude_agl * 1.7 + 2.0, 4.0, 140.0)
		# cylinder axis (+Y, narrow end on top) -> -Z from the lens, scaled to the beam length
		_search_beam.transform = Transform3D(
			Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(length, length, length)),
			Vector3(0.0, 0.0, -length * 0.5))


# ==============================================================================================
# audio helper: long-range rotor loop driven by rotor rpm (replaces the car audio)
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
				engine.pitch_scale = lerpf(v.spec.engine_pitch_min, v.spec.engine_pitch_max, rf) + v.get_engine_load() * 0.06
				var target := lerpf(-26.0, 0.0, clampf(rf, 0.0, 1.0)) + v.get_engine_load() * 2.5
				engine.volume_db = lerpf(engine.volume_db, target, clampf(delta * 5.0, 0.0, 1.0))
				if not engine.playing:
					engine.play()
		elif _usable(engine) and engine.playing:
			engine.stop()
