extends RefCounted
## Registrar for Registry kind "vehicles": two-wheelers (class Bike) and boats (class Boat).
##
## VehicleSpec fields keep their usual meaning (mass, top_speed, brakes, tyres, suspension,
## camera, audio ...). Tuning that VehicleSpec has no field for lives in the spec meta:
##   "bike" -> Bike.DEFAULTS keys (pedal power, lean, crash thresholds ...)
##   "boat" -> Boat.DEFAULTS keys (draft, thrust, drag, planing, banking ...)
## Masses include a typical rider / crew. Speeds are scaled for the ~600 m island.
##
## Also hooks the marina moorings: at EventBus.game_ready a BoatSpawner
## (res://gta/code/vehicles/boat_spawner.gd) moors a few boats at the world's "boat" spawn
## points - unless a "boats" world system already does it. Docs: docs/BIKES_BOATS.md.

const SPAWNER_PATH := "res://gta/code/vehicles/boat_spawner.gd"

const BIKE_COLORS := [
	Color("#D8342C"), Color("#F2C331"), Color("#1B1D22"), Color("#F1F1EE"), Color("#2C6FD9"),
	Color("#F0802F"), Color("#1FA7A0"), Color("#7A50D0"),
]
const BICYCLE_COLORS := [
	Color("#2F9E5C"), Color("#D8342C"), Color("#2C6FD9"), Color("#F2C331"), Color("#1FA7A0"),
	Color("#F1F1EE"), Color("#1B1D22"), Color("#F0802F"),
]
const BOAT_COLORS := [
	Color("#F1F1EE"), Color("#D8342C"), Color("#2C6FD9"), Color("#1B1D22"), Color("#1FA7A0"),
	Color("#F2C331"),
]


## Fires once on game_ready and creates the mooring spawner (no shared boot file is touched).
class MooringHook:
	extends RefCounted

	const PATH := "res://gta/code/vehicles/boat_spawner.gd"

	func fire() -> void:
		if Game.is_disabled("vehicles") or Game.get_system("vehicles") == null:
			return
		if Game.get_system("boats") != null or Game.flags.has("no_moorings"):
			return
		if not ResourceLoader.exists(PATH):
			return
		var script := load(PATH) as Script
		if script == null or not script.can_instantiate():
			return
		var node := script.new() as Node
		if node == null:
			return
		node.name = "BoatMoorings"
		var root: Node = Game.get_entities_root()
		if root == null:
			node.free()
			return
		root.add_child(node)


static var _hook: MooringHook = null


static func register_all(registry: Node) -> void:
	for spec: VehicleSpec in _build():
		registry.register("vehicles", spec)
	if _hook == null:
		_hook = MooringHook.new()
		EventBus.game_ready.connect(_hook.fire, CONNECT_ONE_SHOT)


static func _colors(list: Array) -> Array[Color]:
	var out: Array[Color] = []
	out.assign(list)
	return out


static func _with(spec: VehicleSpec, key: String, data: Dictionary) -> VehicleSpec:
	spec.set_meta(key, data)
	return spec


static func _build() -> Array[VehicleSpec]:
	var out: Array[VehicleSpec] = []

	# --- two-wheelers ----------------------------------------------------------------------------
	out.append(_with(VehicleSpec.make("motorcycle", "Kestrel 690", {
		"vehicle_class": "bike",
		"description": "Naked street bike. Quick, light, leans hard - and unforgiving when it meets a wall.",
		"price": 11000, "seats": 2, "max_health": 450.0, "traffic_weight": 0.5,
		"mass": 260.0, "com_height": 0.66, "com_offset": Vector3(0.0, 0.0, 0.0), "inertia_scale": Vector3(1.0, 1.0, 1.0),
		"hull_clearance": 0.22, "hull_friction": 0.3, "collision_damage_scale": 0.7,
		"top_speed": 52.0, "reverse_speed": 1.6, "idle_rpm": 1400.0, "redline_rpm": 11000.0, "engine_braking": 1.3,
		"brake_force": 3400.0, "brake_bias_front": 0.68,
		"max_steer_angle": 32.0, "high_speed_steer_slip": 4.0, "steer_rate": 3.2, "steer_return_rate": 5.0,
		"grip_front": 1.15, "grip_rear": 1.15, "peak_slip_angle": 6.5, "slide_grip": 0.8, "handbrake_grip": 0.55,
		"power_slide": 0.6, "traction": 1.25, "rolling_resistance": 0.015,
		"suspension_rest_length": 0.08, "suspension_travel": 0.18, "suspension_stiffness": 2.0,
		"suspension_damping": 0.55, "suspension_rebound": 1.3, "body_lean": 1.0,
		"cam_distance": 4.2, "cam_height": 1.55, "cam_fov": 74.0, "cam_look_height": 0.95,
		"sound_engine": "engine_bike_loop", "sound_horn": "horn_bike", "engine_pitch_min": 0.6, "engine_pitch_max": 2.1,
		"default_colors": _colors(BIKE_COLORS),
		"allowed_mods": PackedStringArray(["engine", "turbo", "brakes", "tires", "armor", "paint_finish", "wheel_color", "lights", "horn"]),
	}), "bike", {
		"power_kw": 75.0, "max_drive_accel": 7.0, "max_lean_deg": 52.0, "crash_dv": 8.5, "crash_dv_ground": 14.0,
		"lowside_slip_deg": 30.0, "lowside_speed": 10.0, "rider_lean_fwd": 0.36, "gears": 6,
	}))
	out.append(_with(VehicleSpec.make("bicycle", "Spoke Urban", {
		"vehicle_class": "bicycle",
		"description": "City hardtail. Quiet, cheap, slow - sprint to pedal harder (costs stamina).",
		"price": 600, "seats": 1, "max_health": 300.0, "traffic_weight": 0.0,
		"mass": 95.0, "com_height": 0.95, "com_offset": Vector3(0.0, 0.0, 0.08), "inertia_scale": Vector3(1.0, 1.0, 1.0),
		"hull_clearance": 0.24, "hull_friction": 0.3, "collision_damage_scale": 0.25,
		"top_speed": 8.6, "reverse_speed": 1.3, "idle_rpm": 0.0, "redline_rpm": 1.0, "engine_braking": 0.0,
		"brake_force": 900.0, "brake_bias_front": 0.6,
		"max_steer_angle": 35.0, "high_speed_steer_slip": 4.5, "steer_rate": 2.8, "steer_return_rate": 4.5,
		"grip_front": 1.0, "grip_rear": 1.0, "peak_slip_angle": 7.0, "slide_grip": 0.78, "handbrake_grip": 0.5,
		"power_slide": 0.5, "traction": 1.0, "rolling_resistance": 0.008,
		"suspension_rest_length": 0.05, "suspension_travel": 0.1, "suspension_stiffness": 2.4,
		"suspension_damping": 0.6, "suspension_rebound": 1.3, "body_lean": 1.0,
		"cam_distance": 3.6, "cam_height": 1.65, "cam_fov": 72.0, "cam_look_height": 1.05,
		"sound_engine": "bicycle_loop", "sound_horn": "", "engine_pitch_min": 0.8, "engine_pitch_max": 1.35,
		"default_colors": _colors(BICYCLE_COLORS),
		"allowed_mods": PackedStringArray(["paint_finish", "wheel_color"]),
	}), "bike", {
		"pedal": true, "pedal_watts": 420.0, "sprint_watts": 820.0, "max_drive_accel": 2.6, "max_lean_deg": 40.0,
		"crash_dv": 6.0, "crash_dv_ground": 10.0, "lowside_slip_deg": 30.0, "lowside_speed": 7.0,
		"rider_lean_fwd": 0.26, "crank_ratio": 2.7,
	}))

	# --- boats -----------------------------------------------------------------------------------
	out.append(_with(VehicleSpec.make("speedboat", "Tidecutter 23", {
		"vehicle_class": "boat",
		"description": "Open sport boat with a big outboard. Climbs onto the plane fast and turns flat.",
		"price": 42000, "seats": 4, "max_health": 1100.0, "traffic_weight": 0.0,
		"mass": 1400.0, "com_height": 0.12, "com_offset": Vector3(0.0, 0.0, 0.35), "inertia_scale": Vector3(1.0, 1.0, 1.0),
		"hull_clearance": -5.0, "hull_friction": 0.45, "collision_damage_scale": 0.45,
		"top_speed": 19.5, "reverse_speed": 4.0, "idle_rpm": 800.0, "redline_rpm": 6000.0,
		"max_steer_angle": 30.0, "steer_rate": 2.2, "steer_return_rate": 3.0,
		"cam_distance": 9.0, "cam_height": 3.0, "cam_fov": 72.0, "cam_look_height": 1.3,
		"sound_engine": "engine_boat_loop", "sound_horn": "horn_truck", "engine_pitch_min": 0.55, "engine_pitch_max": 1.65,
		"default_colors": _colors(BOAT_COLORS),
		"allowed_mods": PackedStringArray(["paint_finish", "horn"]),
	}), "boat", {
		"draft": 0.3, "freeboard": 0.6, "thrust_accel": 3.4, "reverse_thrust": 0.45,
		"plane_speed": 12.0, "bow_rise_deg": 6.5, "plane_rise": 0.12, "bank_deg": 9.0,
		"rudder": 1.0, "yaw_damping": 1.6, "lateral_drag": 1.6, "samples_x": 2, "samples_z": 4,
	}))
	out.append(_with(VehicleSpec.make("jetski", "Wavehopper", {
		"vehicle_class": "boat",
		"description": "Stand-on-the-pegs personal watercraft. Twitchy, wet and very quick to turn.",
		"price": 14000, "seats": 2, "max_health": 500.0, "traffic_weight": 0.0,
		"mass": 420.0, "com_height": 0.22, "com_offset": Vector3(0.0, 0.0, 0.15), "inertia_scale": Vector3(1.0, 1.0, 1.0),
		"hull_clearance": -5.0, "hull_friction": 0.4, "collision_damage_scale": 0.5,
		"top_speed": 21.0, "reverse_speed": 2.5, "idle_rpm": 1200.0, "redline_rpm": 7500.0,
		"max_steer_angle": 32.0, "steer_rate": 3.2, "steer_return_rate": 4.0,
		"cam_distance": 5.5, "cam_height": 2.0, "cam_fov": 74.0, "cam_look_height": 1.0,
		"sound_engine": "engine_boat_loop", "sound_horn": "horn_bike", "engine_pitch_min": 0.75, "engine_pitch_max": 2.0,
		"default_colors": _colors(BOAT_COLORS),
		"allowed_mods": PackedStringArray(["paint_finish", "horn"]),
	}), "boat", {
		"draft": 0.2, "freeboard": 0.45, "thrust_accel": 4.2, "reverse_thrust": 0.4,
		"plane_speed": 9.0, "bow_rise_deg": 5.0, "plane_rise": 0.08, "bank_deg": 18.0,
		"rudder": 1.25, "yaw_damping": 1.4, "lateral_drag": 1.5, "samples_x": 2, "samples_z": 3,
		"rider_pose": "bike",
	}))
	out.append(_with(VehicleSpec.make("dinghy", "Bay Tender", {
		"vehicle_class": "boat",
		"description": "Inflatable tender with a small tiller outboard. Slow, stable, hard to sink.",
		"price": 5000, "seats": 2, "max_health": 600.0, "traffic_weight": 0.0,
		"mass": 330.0, "com_height": 0.12, "com_offset": Vector3(0.0, 0.0, 0.25), "inertia_scale": Vector3(1.0, 1.0, 1.0),
		"hull_clearance": -5.0, "hull_friction": 0.5, "collision_damage_scale": 0.35,
		"top_speed": 9.0, "reverse_speed": 2.5, "idle_rpm": 1000.0, "redline_rpm": 6000.0,
		"max_steer_angle": 35.0, "steer_rate": 2.0, "steer_return_rate": 3.0,
		"cam_distance": 5.5, "cam_height": 2.2, "cam_fov": 72.0, "cam_look_height": 0.9,
		"sound_engine": "engine_boat_loop", "sound_horn": "", "engine_pitch_min": 0.85, "engine_pitch_max": 1.9,
		"default_colors": _colors([Color("#3A3F47"), Color("#D85A2C"), Color("#5B6B3A"), Color("#B8BEC6")]),
		"allowed_mods": PackedStringArray(["paint_finish"]),
	}), "boat", {
		"draft": 0.14, "freeboard": 0.4, "thrust_accel": 2.6, "reverse_thrust": 0.5,
		"plane_speed": 7.0, "bow_rise_deg": 4.0, "plane_rise": 0.04, "bank_deg": 5.0,
		"rudder": 0.9, "yaw_damping": 1.8, "lateral_drag": 1.3, "samples_x": 2, "samples_z": 3,
	}))
	return out
