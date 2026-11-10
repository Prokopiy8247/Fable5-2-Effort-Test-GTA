extends RefCounted
## Registrar for the aircraft of Registry kind "vehicles": heli_civil, heli_police, plane_prop, plane_jet.
##
## Generic VehicleSpec fields (mass, health, seats, camera, audio, colours) are set as usual. The
## flight-model tuning that VehicleSpec has no fields for lives in the spec's metadata "air"
## (a Dictionary read by helicopter.gd / plane.gd; every key has a default there, so a spec
## without metadata still flies). Field reference and tuning guide: docs/AIRCRAFT.md.
##
## Side job: at boot this registrar adds the AircraftSpawner helper node (aircraft_spawner.gd,
## same module) under the Registry autoload. It waits for EventBus.game_ready and parks the
## aircraft at the world's "heli" / "plane" spawn points (owner_tag "parked"). That keeps the
## free-roam aircraft independent of BootManifest edits.

const SPAWNER_PATH := "res://gta/code/vehicles/aircraft_spawner.gd"
const SPAWNER_NAME := "AircraftSpawner"

const HELI_COLORS := [
	Color("#F0802F"), Color("#F1F1EE"), Color("#D8342C"), Color("#2C6FD9"), Color("#1B1D22"),
	Color("#F2C331"), Color("#1FA7A0"),
]
const HELI_SECOND := [Color("#F1F1EE"), Color("#1B1D22"), Color("#BFC5CC")]
const PLANE_COLORS := [
	Color("#F1F1EE"), Color("#D8342C"), Color("#2C6FD9"), Color("#F2C331"), Color("#2F9E5C"), Color("#F0802F"),
]
const PLANE_SECOND := [Color("#27405F"), Color("#D8342C"), Color("#1B1D22"), Color("#F1F1EE")]
const JET_COLORS := [Color("#F1F1EE"), Color("#BFC5CC"), Color("#1B1D22"), Color("#27405F"), Color("#D8342C")]


static func register_all(registry: Node) -> void:
	for spec: VehicleSpec in _build():
		registry.register("vehicles", spec)
	_add_spawner(registry)


static func _add_spawner(registry: Node) -> void:
	if registry == null or not is_instance_valid(registry) or registry.has_node(SPAWNER_NAME):
		return
	if not ResourceLoader.exists(SPAWNER_PATH):
		return
	var script := load(SPAWNER_PATH) as Script
	if script == null or not script.can_instantiate():
		return
	var node := script.new() as Node
	if node == null:
		return
	node.name = SPAWNER_NAME
	registry.add_child.call_deferred(node)


static func _colors(list: Array) -> Array[Color]:
	var out: Array[Color] = []
	out.assign(list)
	return out


static func _spec(id: String, display_name: String, props: Dictionary, air: Dictionary) -> VehicleSpec:
	var s := VehicleSpec.make(id, display_name, props)
	s.set_meta("air", air)
	return s


static func _build() -> Array[VehicleSpec]:
	var out: Array[VehicleSpec] = []
	var no_mods := PackedStringArray()

	# --- helicopters --------------------------------------------------------------------------
	out.append(_spec("heli_civil", "Bayflyer 204", {
		"description": "Light four-seat utility helicopter. Forgiving, smooth, a little underpowered when full.",
		"vehicle_class": "heli", "price": 260000, "seats": 4, "max_health": 900.0, "traffic_weight": 0.0,
		"mass": 1500.0, "com_height": 1.25, "com_offset": Vector3(0.0, 0.0, 0.15),
		"inertia_scale": Vector3(0.75, 0.8, 1.4), "hull_clearance": 0.0, "hull_friction": 0.85,
		"collision_damage_scale": 1.35, "top_speed": 46.0,
		"cam_distance": 10.0, "cam_height": 3.3, "cam_fov": 70.0, "cam_look_height": 2.0,
		"sound_engine": "heli_rotor_loop", "sound_horn": "", "engine_pitch_min": 0.45, "engine_pitch_max": 1.0,
		"default_colors": _colors(HELI_COLORS), "secondary_colors": _colors(HELI_SECOND),
		"allowed_mods": no_mods,
	}, {
		"lift_ratio": 1.55,          # max rotor thrust / weight (sea level, full rpm, healthy)
		"climb_rate": 8.0,           # m/s at full collective
		"descent_rate": 6.5,         # m/s at zero collective
		"max_pitch_deg": 26.0, "max_roll_deg": 30.0, "yaw_rate_deg": 75.0,
		"attitude_gain": 9.0, "attitude_damp": 5.2, "yaw_gain": 5.0,
		"top_speed": 46.0,           # level-flight speed at full forward cyclic (m/s)
		"spool_up": 4.0, "spool_down": 9.0,
		"ceiling": 350.0,
		"weathervane": 0.55,
		"crash_explode_dv": 17.0, "hard_landing_sink": 4.5,
	}))
	out.append(_spec("heli_police", "HBPD Air One", {
		"description": "Halcyon Bay Police patrol helicopter: twin turbines, searchlight, quick and stable.",
		"vehicle_class": "heli", "price": 0, "seats": 4, "max_health": 1400.0, "traffic_weight": 0.0,
		"is_police": true, "fixed_livery": true,
		"mass": 2300.0, "com_height": 1.4, "com_offset": Vector3(0.0, 0.0, 0.2),
		"inertia_scale": Vector3(0.75, 0.8, 1.4), "hull_clearance": 0.0, "hull_friction": 0.85,
		"collision_damage_scale": 1.2, "top_speed": 56.0,
		"cam_distance": 11.0, "cam_height": 3.6, "cam_fov": 70.0, "cam_look_height": 2.2,
		"sound_engine": "heli_rotor_loop", "sound_horn": "", "engine_pitch_min": 0.5, "engine_pitch_max": 1.08,
		"allowed_mods": no_mods,
	}, {
		"lift_ratio": 1.75, "climb_rate": 10.0, "descent_rate": 7.5,
		"max_pitch_deg": 28.0, "max_roll_deg": 34.0, "yaw_rate_deg": 85.0,
		"attitude_gain": 10.0, "attitude_damp": 5.6, "yaw_gain": 5.5,
		"top_speed": 56.0, "spool_up": 3.5, "spool_down": 9.0, "ceiling": 380.0,
		"weathervane": 0.6, "crash_explode_dv": 18.0, "hard_landing_sink": 5.0,
		"searchlight": true,
	}))

	# --- airplanes ----------------------------------------------------------------------------
	out.append(_spec("plane_prop", "Bayhopper 318", {
		"description": "High-wing four-seat touring plane. Slow, docile stall, short take-off roll.",
		"vehicle_class": "plane", "price": 180000, "seats": 4, "max_health": 850.0, "traffic_weight": 0.0,
		"mass": 1100.0, "com_height": 1.25, "com_offset": Vector3.ZERO,
		"inertia_scale": Vector3(1.0, 1.0, 1.0), "hull_clearance": 0.0, "hull_friction": 0.5,
		"collision_damage_scale": 1.6, "top_speed": 60.0,
		"cam_distance": 10.5, "cam_height": 3.0, "cam_fov": 70.0, "cam_look_height": 1.8,
		"sound_engine": "plane_prop_loop", "sound_horn": "", "engine_pitch_min": 0.55, "engine_pitch_max": 1.25,
		"default_colors": _colors(PLANE_COLORS), "secondary_colors": _colors(PLANE_SECOND),
		"allowed_mods": no_mods,
	}, {
		"stall_speed": 24.0,         # 1 g stall speed, flaps up (m/s)
		"cl_max": 1.45, "cl0": 0.22, "cl_alpha": 5.0,
		"flap_cl": 0.25,             # extra lift coefficient with the (automatic) flaps out
		"thrust": 4200.0,            # static thrust (N)
		"thrust_fade": 0.6,          # share of the thrust lost at top speed (propeller)
		"drag": 0.55,                # parasite drag N / (m/s)^2 (flaps add up to 80 %)
		"induced": 0.045,
		"pitch_rate_deg": 50.0, "roll_rate_deg": 105.0, "yaw_rate_deg": 18.0,
		"authority_speed": 34.0,     # airspeed with full control authority
		"throttle_rate": 0.55,       # player throttle change per second
		"brake_decel": 5.0,          # wheel brakes, m/s^2 at full pedal (tyre grip permitting)
		"steer_deg": 32.0, "gear_hz": 2.3, "gear_bump": 0.07, "gear_droop": 0.07,
		"crash_explode_dv": 18.0, "touchdown_sink": 3.2,
		"prop": true,
	}))
	out.append(_spec("plane_jet", "Swiftline 900", {
		"description": "Tandem two-seat light jet. Fast, crisp roll, needs the whole runway and a careful landing.",
		"vehicle_class": "plane", "price": 950000, "seats": 2, "max_health": 1000.0, "traffic_weight": 0.0,
		"mass": 4500.0, "com_height": 1.35, "com_offset": Vector3.ZERO,
		"inertia_scale": Vector3(1.0, 1.0, 1.0), "hull_clearance": 0.0, "hull_friction": 0.5,
		"collision_damage_scale": 1.5, "top_speed": 112.0,
		"cam_distance": 12.0, "cam_height": 3.2, "cam_fov": 72.0, "cam_look_height": 1.9,
		"sound_engine": "jet_loop", "sound_horn": "", "engine_pitch_min": 0.6, "engine_pitch_max": 1.35,
		"default_colors": _colors(JET_COLORS), "secondary_colors": _colors(PLANE_SECOND),
		"allowed_mods": no_mods,
	}, {
		"stall_speed": 38.0, "cl_max": 1.4, "cl0": 0.2, "cl_alpha": 4.6, "flap_cl": 0.2,
		"thrust": 24000.0, "thrust_fade": 0.15,
		"drag": 1.6, "induced": 0.05,
		"ground_spoilers": true,     # lift dumpers on the ground with the throttle closed
		"pitch_rate_deg": 65.0, "roll_rate_deg": 170.0, "yaw_rate_deg": 20.0,
		"authority_speed": 55.0, "throttle_rate": 0.5, "brake_decel": 5.5,
		"steer_deg": 28.0, "gear_hz": 2.2, "gear_bump": 0.07, "gear_droop": 0.07,
		"crash_explode_dv": 20.0, "touchdown_sink": 3.6,
		"prop": false,
	}))
	return out
