extends RefCounted
## Registrar for Registry kind "vehicles" (VehicleSpec resources) - the ground cars.
## Speeds are scaled for the ~600 m island: 30 m/s (trucks) .. 58 m/s (sports) top speed.
## Handling is deliberately distinct per class: weight, power, drivetrain, grip, body roll.
## Two-wheelers, boats and aircraft register their specs in their own registrar files.
## Tuning guide and field reference: docs/VEHICLES.md.

const CIVIL_COLORS := [
	Color("#D8342C"), Color("#2C6FD9"), Color("#F2C331"), Color("#F1F1EE"), Color("#1B1D22"),
	Color("#BFC5CC"), Color("#2F9E5C"), Color("#F0802F"), Color("#1FA7A0"), Color("#7A50D0"),
]
const SOBER_COLORS := [
	Color("#F1F1EE"), Color("#1B1D22"), Color("#BFC5CC"), Color("#2C6FD9"), Color("#8E99A6"), Color("#27405F"),
]
const WORK_COLORS := [
	Color("#F1F1EE"), Color("#BFC5CC"), Color("#2C6FD9"), Color("#F0802F"), Color("#2F9E5C"), Color("#E2B13C"),
]
const SPORT_COLORS := [
	Color("#D8342C"), Color("#F2C331"), Color("#F0802F"), Color("#1FA7A0"), Color("#7A50D0"), Color("#F1F1EE"),
	Color("#1B1D22"), Color("#2C6FD9"),
]
const PERF_MODS := ["engine", "brakes", "suspension", "transmission", "turbo", "armor", "tires", "tint", "lights", "horn"]


static func register_all(registry: Node) -> void:
	for spec: VehicleSpec in _build():
		registry.register("vehicles", spec)


static func _colors(list: Array) -> Array[Color]:
	var out: Array[Color] = []
	out.assign(list)
	return out


static func _build() -> Array[VehicleSpec]:
	var out: Array[VehicleSpec] = []

	# --- civilian cars (customisable) ----------------------------------------------------------
	out.append(VehicleSpec.make("compact", "Pip", {
		"description": "Small front-wheel-drive city hatchback. Light, nimble, runs out of breath early.",
		"price": 9000, "seats": 4, "max_health": 850.0, "traffic_weight": 1.3,
		"mass": 1050.0, "com_height": 0.47, "com_offset": Vector3(0, 0, -0.12),
		"engine_power": 94.0, "top_speed": 40.0, "redline_rpm": 6400.0, "gear_count": 5, "gear_spread": 3.3,
		"drivetrain": "fwd", "brake_force": 8200.0, "brake_bias_front": 0.66,
		"max_steer_angle": 37.0, "high_speed_steer_slip": 6.0, "steer_rate": 3.6,
		"grip_front": 1.05, "grip_rear": 1.02, "slide_grip": 0.84, "power_slide": 0.55, "traction": 1.1,
		"suspension_stiffness": 1.9, "suspension_damping": 0.5, "anti_roll": 0.5, "roll_influence": 0.45,
		"suspension_rest_length": 0.12, "suspension_travel": 0.26,
		"cam_distance": 5.0, "cam_height": 1.8,
		"default_colors": _colors(CIVIL_COLORS),
	}))
	out.append(VehicleSpec.make("sedan", "Meridian", {
		"description": "Mid-size rear-wheel-drive saloon. The honest all-rounder of Halcyon Bay.",
		"price": 16000, "seats": 4, "max_health": 1000.0, "traffic_weight": 1.6,
		"mass": 1450.0, "com_height": 0.5, "com_offset": Vector3(0, 0, -0.06),
		"engine_power": 152.0, "top_speed": 45.0, "redline_rpm": 6300.0, "gear_count": 5, "gear_spread": 3.3,
		"drivetrain": "rwd", "brake_force": 11500.0,
		"max_steer_angle": 35.0, "steer_rate": 3.2,
		"grip_front": 1.08, "grip_rear": 1.08, "power_slide": 0.65, "traction": 1.2,
		"suspension_stiffness": 1.7, "suspension_damping": 0.5, "anti_roll": 0.5, "roll_influence": 0.45,
		"default_colors": _colors(SOBER_COLORS + CIVIL_COLORS),
	}))
	out.append(VehicleSpec.make("sports", "Vanta RS", {
		"description": "Low mid-engined coupe. Huge grip, huge power, flat through corners.",
		"price": 85000, "seats": 2, "max_health": 900.0, "traffic_weight": 0.3,
		"mass": 1300.0, "com_height": 0.38, "com_offset": Vector3(0, 0, 0.1), "inertia_scale": Vector3(1.0, 0.95, 1.2),
		"engine_power": 335.0, "top_speed": 58.0, "redline_rpm": 8000.0, "gear_count": 6, "gear_spread": 3.5,
		"shift_time": 0.12, "drivetrain": "rwd", "brake_force": 13000.0, "brake_bias_front": 0.6,
		"max_steer_angle": 33.0, "high_speed_steer_slip": 5.0, "steer_rate": 4.0, "drift_assist": 0.4,
		"grip_front": 1.32, "grip_rear": 1.36, "peak_slip_angle": 6.5, "slide_grip": 0.8, "power_slide": 0.75, "traction": 1.1,
		"suspension_stiffness": 2.4, "suspension_damping": 0.6, "anti_roll": 0.9, "roll_influence": 0.25,
		"suspension_rest_length": 0.09, "suspension_travel": 0.2, "hull_clearance": 0.22,
		"downforce": 1.1, "engine_braking": 1.1,
		"sound_engine": "engine_sport_loop", "engine_pitch_min": 0.65, "engine_pitch_max": 2.1,
		"cam_distance": 5.2, "cam_height": 1.55, "cam_fov": 75.0, "cam_look_height": 0.85,
		"default_colors": _colors(SPORT_COLORS),
	}))
	out.append(VehicleSpec.make("muscle", "Galeforce 426", {
		"description": "Big-block rear-drive coupe. Brutal straight-line shove, a tail that loves to step out.",
		"price": 48000, "seats": 4, "max_health": 1050.0, "traffic_weight": 0.5,
		"mass": 1650.0, "com_height": 0.47, "com_offset": Vector3(0, 0, -0.12),
		"engine_power": 290.0, "top_speed": 54.0, "redline_rpm": 6000.0, "gear_count": 4, "gear_spread": 2.6,
		"shift_time": 0.26, "drivetrain": "rwd", "brake_force": 11500.0, "brake_bias_front": 0.64,
		"max_steer_angle": 34.0, "high_speed_steer_slip": 6.5, "steer_rate": 3.0, "drift_assist": 0.45,
		"grip_front": 1.08, "grip_rear": 1.16, "peak_slip_angle": 8.5, "slide_grip": 0.86, "power_slide": 0.95, "traction": 1.3,
		"suspension_stiffness": 1.75, "suspension_damping": 0.45, "anti_roll": 0.45, "roll_influence": 0.42,
		"downforce": 0.3, "engine_braking": 1.2,
		"sound_engine": "engine_sport_loop", "engine_pitch_min": 0.5, "engine_pitch_max": 1.6,
		"default_colors": _colors(SPORT_COLORS),
	}))
	out.append(VehicleSpec.make("suv", "Summit", {
		"description": "Tall all-wheel-drive family hauler. Sure-footed off the tarmac, leans in corners.",
		"price": 34000, "seats": 4, "max_health": 1200.0, "traffic_weight": 1.0,
		"mass": 2100.0, "com_height": 0.64, "com_offset": Vector3(0, 0, -0.05),
		"engine_power": 205.0, "top_speed": 44.0, "redline_rpm": 5800.0, "gear_count": 5, "gear_spread": 3.6,
		"drivetrain": "awd", "awd_front_bias": 0.45, "brake_force": 15500.0,
		"max_steer_angle": 34.0, "steer_rate": 2.9,
		"grip_front": 1.04, "grip_rear": 1.04, "peak_slip_angle": 8.5, "power_slide": 0.5,
		"suspension_stiffness": 1.5, "suspension_damping": 0.45, "anti_roll": 0.4, "roll_influence": 0.58,
		"suspension_rest_length": 0.17, "suspension_travel": 0.36, "hull_clearance": 0.32,
		"collision_damage_scale": 0.85,
		"cam_distance": 6.2, "cam_height": 2.2, "cam_look_height": 1.2,
		"default_colors": _colors(SOBER_COLORS + [Color("#2F9E5C"), Color("#D8342C")]),
	}))
	out.append(VehicleSpec.make("pickup", "Dustrunner", {
		"description": "Body-on-frame work truck. Light rear end, long-travel springs, happy on dirt.",
		"price": 26000, "seats": 4, "max_health": 1250.0, "traffic_weight": 0.9,
		"mass": 1900.0, "com_height": 0.6, "com_offset": Vector3(0, 0, -0.3),
		"engine_power": 172.0, "top_speed": 42.0, "redline_rpm": 5400.0, "gear_count": 5, "gear_spread": 3.7,
		"shift_time": 0.28, "drivetrain": "rwd", "brake_force": 13500.0, "brake_bias_front": 0.68,
		"max_steer_angle": 34.0, "steer_rate": 2.8, "drift_assist": 0.4,
		"grip_front": 1.0, "grip_rear": 0.98, "peak_slip_angle": 9.0, "slide_grip": 0.86, "power_slide": 0.85, "traction": 1.15,
		"suspension_stiffness": 1.55, "suspension_damping": 0.42, "anti_roll": 0.35, "roll_influence": 0.55,
		"suspension_rest_length": 0.17, "suspension_travel": 0.36, "hull_clearance": 0.33,
		"collision_damage_scale": 0.85,
		"sound_engine": "engine_truck_loop", "engine_pitch_min": 0.7, "engine_pitch_max": 1.7,
		"cam_distance": 6.3, "cam_height": 2.2, "cam_look_height": 1.2,
		"default_colors": _colors(WORK_COLORS + [Color("#D8342C"), Color("#1B1D22")]),
	}))

	# --- utility -------------------------------------------------------------------------------
	out.append(VehicleSpec.make("van", "Cargomate", {
		"description": "Slab-sided delivery van. Slow, top-heavy, carries everything.",
		"price": 22000, "seats": 2, "max_health": 1300.0, "traffic_weight": 0.8,
		"mass": 2300.0, "com_height": 0.74, "com_offset": Vector3(0, 0, -0.1),
		"engine_power": 140.0, "top_speed": 34.0, "redline_rpm": 5000.0, "gear_count": 5, "gear_spread": 3.6,
		"shift_time": 0.3, "drivetrain": "rwd", "brake_force": 15500.0, "brake_bias_front": 0.64,
		"max_steer_angle": 34.0, "high_speed_steer_slip": 4.5, "steer_rate": 2.6, "drift_assist": 0.3,
		"grip_front": 0.96, "grip_rear": 0.96, "peak_slip_angle": 9.0, "power_slide": 0.5, "traction": 1.15,
		"suspension_stiffness": 1.5, "suspension_damping": 0.5, "anti_roll": 0.4, "roll_influence": 0.6,
		"suspension_rest_length": 0.14, "suspension_travel": 0.3, "hull_clearance": 0.3,
		"collision_damage_scale": 0.8,
		"sound_engine": "engine_truck_loop", "engine_pitch_min": 0.75, "engine_pitch_max": 1.8,
		"cam_distance": 7.0, "cam_height": 2.6, "cam_look_height": 1.4,
		"default_colors": _colors(WORK_COLORS), "allowed_mods": PackedStringArray(PERF_MODS),
	}))
	out.append(VehicleSpec.make("box_truck", "Tidewater 7.5t", {
		"description": "Medium box truck. Ponderous, needs room to stop, flattens small cars.",
		"price": 38000, "seats": 2, "max_health": 1700.0, "traffic_weight": 0.45,
		"mass": 4800.0, "com_height": 0.98, "com_offset": Vector3(0, 0, -0.2), "inertia_scale": Vector3(1.0, 1.0, 1.4),
		"engine_power": 240.0, "top_speed": 30.0, "redline_rpm": 3800.0, "idle_rpm": 650.0, "gear_count": 6, "gear_spread": 5.0,
		"shift_time": 0.38, "drivetrain": "rwd", "brake_force": 30000.0, "brake_bias_front": 0.58,
		"max_steer_angle": 33.0, "high_speed_steer_slip": 4.0, "steer_rate": 2.2, "steer_return_rate": 3.5, "drift_assist": 0.25,
		"grip_front": 0.93, "grip_rear": 0.96, "peak_slip_angle": 9.5, "power_slide": 0.4, "traction": 1.1,
		"suspension_stiffness": 1.45, "suspension_damping": 0.55, "anti_roll": 0.5, "roll_influence": 0.65,
		"suspension_rest_length": 0.14, "suspension_travel": 0.3, "hull_clearance": 0.38,
		"collision_damage_scale": 0.55, "engine_braking": 1.3,
		"sound_engine": "engine_truck_loop", "sound_horn": "horn_truck", "engine_pitch_min": 0.6, "engine_pitch_max": 1.5,
		"cam_distance": 9.0, "cam_height": 3.4, "cam_look_height": 1.8,
		"default_colors": _colors(WORK_COLORS), "allowed_mods": PackedStringArray(PERF_MODS),
	}))

	# --- services (fixed liveries) -------------------------------------------------------------
	out.append(VehicleSpec.make("taxi", "Meridian Cab", {
		"description": "Halcyon Cab Co. purpose-built cab: tall roof, sedan running gear, a tougher clutch and softer springs.",
		"price": 0, "seats": 4, "max_health": 1050.0, "traffic_weight": 0.0, "is_taxi": true, "fixed_livery": true,
		"mass": 1550.0, "com_height": 0.55, "com_offset": Vector3(0, 0, -0.06),
		"engine_power": 150.0, "top_speed": 45.0, "redline_rpm": 6200.0, "gear_count": 5, "gear_spread": 3.3,
		"drivetrain": "rwd", "brake_force": 12000.0,
		"max_steer_angle": 37.0, "steer_rate": 3.2,
		"grip_front": 1.08, "grip_rear": 1.08, "power_slide": 0.65, "traction": 1.2,
		"suspension_stiffness": 1.6, "suspension_damping": 0.48, "anti_roll": 0.45, "roll_influence": 0.47,
		"cam_distance": 5.9, "cam_height": 2.05, "cam_look_height": 1.1,
		"allowed_mods": PackedStringArray(PERF_MODS),
	}))
	out.append(VehicleSpec.make("police_cruiser", "HBPD Patrol", {
		"description": "Pursuit-tuned saloon of the Halcyon Bay Police Dept. Fast, planted, reinforced.",
		"price": 0, "seats": 4, "max_health": 1400.0, "traffic_weight": 0.0,
		"is_police": true, "is_emergency": true, "fixed_livery": true,
		"mass": 1750.0, "com_height": 0.46, "com_offset": Vector3(0, 0, -0.08),
		"engine_power": 285.0, "top_speed": 54.0, "redline_rpm": 6600.0, "gear_count": 5, "gear_spread": 3.2,
		"shift_time": 0.16, "drivetrain": "rwd", "brake_force": 16000.0, "brake_bias_front": 0.6,
		"max_steer_angle": 35.0, "steer_rate": 3.6, "drift_assist": 0.45,
		"grip_front": 1.22, "grip_rear": 1.24, "peak_slip_angle": 7.0, "power_slide": 0.55, "traction": 1.2,
		"suspension_stiffness": 2.0, "suspension_damping": 0.55, "anti_roll": 0.7, "roll_influence": 0.35,
		"collision_damage_scale": 0.75, "downforce": 0.5,
		"sound_engine": "engine_sport_loop", "sound_siren": "siren_police_loop", "engine_pitch_min": 0.55, "engine_pitch_max": 1.8,
		"allowed_mods": PackedStringArray(),
	}))
	out.append(VehicleSpec.make("swat_van", "HBPD Bulwark", {
		"description": "Armoured tactical truck. Shrugs off small arms and rams roadblocks aside.",
		"price": 0, "seats": 4, "max_health": 3200.0, "traffic_weight": 0.0,
		"is_police": true, "is_emergency": true, "fixed_livery": true,
		"mass": 5200.0, "com_height": 0.86, "com_offset": Vector3(0, 0, -0.1), "inertia_scale": Vector3(1.0, 1.0, 1.4),
		"engine_power": 350.0, "top_speed": 38.0, "redline_rpm": 4400.0, "idle_rpm": 700.0, "gear_count": 5, "gear_spread": 4.2,
		"shift_time": 0.3, "drivetrain": "awd", "awd_front_bias": 0.4, "brake_force": 36000.0,
		"max_steer_angle": 33.0, "high_speed_steer_slip": 4.5, "steer_rate": 2.5, "drift_assist": 0.3,
		"grip_front": 1.0, "grip_rear": 1.02, "peak_slip_angle": 9.0, "power_slide": 0.4,
		"suspension_stiffness": 1.5, "suspension_damping": 0.55, "anti_roll": 0.6, "roll_influence": 0.6,
		"suspension_rest_length": 0.15, "suspension_travel": 0.32, "hull_clearance": 0.38,
		"collision_damage_scale": 0.4, "engine_braking": 1.2,
		"sound_engine": "engine_truck_loop", "sound_horn": "horn_truck", "sound_siren": "siren_police_loop",
		"engine_pitch_min": 0.6, "engine_pitch_max": 1.5,
		"cam_distance": 8.2, "cam_height": 3.0, "cam_look_height": 1.6,
		"allowed_mods": PackedStringArray(),
	}))
	out.append(VehicleSpec.make("ambulance", "Bayside Medic", {
		"description": "Box-body ambulance of Halcyon General. Quick for its size, rolls like a ship.",
		"price": 0, "seats": 2, "max_health": 1600.0, "traffic_weight": 0.0, "is_emergency": true, "fixed_livery": true,
		"mass": 3200.0, "com_height": 0.82, "com_offset": Vector3(0, 0, -0.15), "inertia_scale": Vector3(1.0, 1.0, 1.35),
		"engine_power": 230.0, "top_speed": 40.0, "redline_rpm": 4800.0, "idle_rpm": 750.0, "gear_count": 5, "gear_spread": 3.9,
		"shift_time": 0.28, "drivetrain": "rwd", "brake_force": 22000.0, "brake_bias_front": 0.62,
		"max_steer_angle": 34.0, "high_speed_steer_slip": 4.5, "steer_rate": 2.7, "drift_assist": 0.3,
		"grip_front": 0.98, "grip_rear": 1.0, "peak_slip_angle": 8.5, "power_slide": 0.45, "traction": 1.15,
		"suspension_stiffness": 1.5, "suspension_damping": 0.5, "anti_roll": 0.5, "roll_influence": 0.6,
		"suspension_rest_length": 0.14, "suspension_travel": 0.3, "hull_clearance": 0.32,
		"collision_damage_scale": 0.7,
		"sound_engine": "engine_truck_loop", "sound_siren": "siren_ambulance_loop", "engine_pitch_min": 0.7, "engine_pitch_max": 1.7,
		"cam_distance": 8.0, "cam_height": 3.0, "cam_look_height": 1.6,
		"allowed_mods": PackedStringArray(),
	}))
	out.append(VehicleSpec.make("firetruck", "Engine 9", {
		"description": "Halcyon Bay Fire Dept. pumper. Nine tonnes of red: unstoppable once rolling.",
		"price": 0, "seats": 4, "max_health": 2600.0, "traffic_weight": 0.0, "is_emergency": true, "fixed_livery": true,
		"mass": 9000.0, "com_height": 1.02, "com_offset": Vector3(0, 0, -0.2), "inertia_scale": Vector3(1.0, 1.0, 1.45),
		"engine_power": 460.0, "top_speed": 32.0, "redline_rpm": 3400.0, "idle_rpm": 600.0, "gear_count": 6, "gear_spread": 5.5,
		"shift_time": 0.4, "drivetrain": "rwd", "brake_force": 58000.0, "brake_bias_front": 0.55,
		"max_steer_angle": 32.0, "high_speed_steer_slip": 4.0, "steer_rate": 2.4, "steer_return_rate": 4.2, "drift_assist": 0.2,
		"grip_front": 0.95, "grip_rear": 1.0, "peak_slip_angle": 9.5, "power_slide": 0.35, "traction": 1.1,
		"suspension_stiffness": 1.4, "suspension_damping": 0.6, "anti_roll": 0.6, "roll_influence": 0.62,
		"suspension_rest_length": 0.13, "suspension_travel": 0.28, "hull_clearance": 0.4,
		"collision_damage_scale": 0.35, "engine_braking": 1.4,
		"sound_engine": "engine_truck_loop", "sound_horn": "horn_truck", "sound_siren": "siren_fire_loop",
		"engine_pitch_min": 0.55, "engine_pitch_max": 1.4,
		"cam_distance": 10.5, "cam_height": 3.8, "cam_look_height": 2.0,
		"allowed_mods": PackedStringArray(),
	}))
	return out
