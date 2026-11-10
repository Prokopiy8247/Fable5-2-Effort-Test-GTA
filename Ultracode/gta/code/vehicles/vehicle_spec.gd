class_name VehicleSpec
extends Resource
## Data definition of one drivable vehicle (Registry kind "vehicles").
## Specs are created in code by res://gta/resources/registries/vehicles_registry.gd (or as .tres
## files under res://gta/resources/data/vehicles/). VehicleManager.spawn_vehicle() combines a spec
## with the Blender-authored GLB at `model_path` to build the actual RigidBody3D.
##
## Tuning guide: docs/VEHICLES.md. All lengths in metres, forces in newtons, speeds in m/s.

@export_group("Identity")
@export var id: String = ""
@export var display_name: String = ""
## "car", "bike", "bicycle", "boat", "heli", "plane" - selects the VehicleBase subclass.
@export var vehicle_class: String = "car"
## Empty = res://gta/generated/models/vehicles/<id>.glb
@export var model_path: String = ""
@export var description: String = ""
@export var price: int = 15000
@export var seats: int = 4
@export var max_health: float = 1000.0
@export var is_police: bool = false
@export var is_emergency: bool = false
@export var is_taxi: bool = false
## Relative chance to be picked as ambient civilian traffic (0 = never).
@export var traffic_weight: float = 1.0

@export_group("Body")
@export var mass: float = 1400.0
## Height of the centre of mass above the ground (rest pose).
@export var com_height: float = 0.5
## Extra centre-of-mass offset in body space (x right, y up, z back). -z moves weight to the nose.
@export var com_offset: Vector3 = Vector3.ZERO
## Multiplies the box-approximated inertia (x pitch, y yaw, z roll).
@export var inertia_scale: Vector3 = Vector3(1.0, 1.0, 1.25)
## Collision hull points below this height are lifted to it (kerb clearance).
@export var hull_clearance: float = 0.27
@export var hull_friction: float = 0.25
## Multiplier on collision damage taken (trucks are tougher per impact).
@export var collision_damage_scale: float = 1.0

@export_group("Engine")
## Peak engine power in kW.
@export var engine_power: float = 130.0
## Optional torque curve: x = rpm / redline (0..1), y = torque factor (0..1). Null = built-in.
@export var torque_curve: Curve = null
@export var idle_rpm: float = 850.0
@export var redline_rpm: float = 6500.0
## Top speed on a flat dry road (m/s). Aerodynamic drag is derived from it unless drag_coefficient > 0.
@export var top_speed: float = 45.0
@export var reverse_speed: float = 11.0
## Gear ratios (first .. top). Empty = geometric set generated from gear_count and gear_spread.
@export var gear_ratios: PackedFloat32Array = PackedFloat32Array()
@export var gear_count: int = 5
## first gear ratio / top gear ratio when the set is generated.
@export var gear_spread: float = 3.3
## 0 = automatic: chosen so that the top gear reaches top_speed just below the redline.
@export var final_drive: float = 0.0
@export var shift_time: float = 0.22
@export var drivetrain_efficiency: float = 0.9
## "fwd", "rwd", "awd"
@export var drivetrain: String = "rwd"
## Share of the drive force sent to the front axle for "awd".
@export var awd_front_bias: float = 0.4
## Deceleration (m/s^2) from engine braking with a closed throttle.
@export var engine_braking: float = 0.9

@export_group("Brakes")
## Total brake force at full pedal (N). Stock values sit below the tyre limit so brake mods matter.
@export var brake_force: float = 11000.0
@export var brake_bias_front: float = 0.62

@export_group("Steering")
## Maximum road-wheel angle at low speed (degrees).
@export var max_steer_angle: float = 35.0
## Speed-sensitive reduction: above ~15 km/h the lock is limited to the angle that uses the
## available grip plus this many degrees of extra slip (higher = more darty at speed).
@export var high_speed_steer_slip: float = 5.5
## Full lock is reached in 1 / steer_rate seconds.
@export var steer_rate: float = 3.2
@export var steer_return_rate: float = 5.0
## Automatic counter-steer toward the direction of travel while sliding (0 = off).
@export var drift_assist: float = 0.35

@export_group("Tyres")
## Peak friction coefficient per axle.
@export var grip_front: float = 1.08
@export var grip_rear: float = 1.08
## Slip angle (degrees) at which lateral grip peaks.
@export var peak_slip_angle: float = 7.5
## Fraction of peak grip that remains when the tyre slides far beyond the peak.
@export var slide_grip: float = 0.82
## Grip fraction of a wheel locked by the handbrake.
@export var handbrake_grip: float = 0.62
## Arcade assist: share of the full brake force put on the FRONT wheels while the handbrake is
## held with a closed throttle, so a held handbrake brings the car to a stop briskly (GTA style)
## while still sliding the tail. 0 = rear lock only (realistic). Throttle + handbrake = no assist.
@export var handbrake_brake_assist: float = 0.5
## How strongly drive / brake force eats lateral grip (0 = never, 1 = full friction circle).
@export var power_slide: float = 0.7
## Launch traction: multiplier on the grip a driven wheel has for putting drive force down
## (1 = same as its cornering grip; 1.2-1.3 = sticky drag-strip launches without more cornering grip).
@export var traction: float = 1.0
@export var rolling_resistance: float = 0.014

@export_group("Suspension")
## Distance the wheel can drop below the modelled (loaded) pose.
@export var suspension_rest_length: float = 0.13
## Total wheel travel (droop + bump). Bump = travel - rest length.
@export var suspension_travel: float = 0.28
## Natural frequency of the sprung mass in Hz (1.3 soft truck .. 2.6 stiff sports car).
@export var suspension_stiffness: float = 1.8
## Damping ratio for compression (0.3 floaty .. 0.9 dead).
@export var suspension_damping: float = 0.5
## Rebound damping = damping * this.
@export var suspension_rebound: float = 1.35
## Anti-roll bar stiffness as a fraction of the spring stiffness.
@export var anti_roll: float = 0.5
## 1 = tyre forces act at the road (full body roll), 0 = at centre-of-mass height (no roll).
@export var roll_influence: float = 0.45
## Visual exaggeration of body roll / squat / dive: the shell leans this many times the physical
## angle (1 = physical only). Extra lean is capped (Car.LEAN_ROLL_MAX / LEAN_PITCH_MAX).
@export var body_lean: float = 3.5

@export_group("Aero")
## N per (m/s)^2. 0 = derived from top_speed.
@export var drag_coefficient: float = 0.0
## Downforce in N per (m/s)^2.
@export var downforce: float = 0.25

@export_group("Wheels")
## 0 = measured from the wheel mesh.
@export var wheel_radius: float = 0.0

@export_group("Camera")
@export var cam_distance: float = 5.6
@export var cam_height: float = 1.9
@export var cam_fov: float = 72.0
@export var cam_look_height: float = 1.0

@export_group("Audio")
@export var sound_engine: String = "engine_car_loop"
@export var sound_horn: String = "horn_car"
@export var sound_siren: String = ""
## Engine loop pitch at idle and at the redline.
@export var engine_pitch_min: float = 0.6
@export var engine_pitch_max: float = 1.9

@export_group("Appearance")
## Random primary paint choices for civilian spawns.
@export var default_colors: Array[Color] = []
## Optional secondary paint choices (empty = keep the authored secondary colour).
@export var secondary_colors: Array[Color] = []
## Keep the colours authored in Blender (police / taxi / ambulance liveries).
@export var fixed_livery: bool = false
## Fold angle (rad about its local X) of a `Roof_Convertible` part, if the model has one.
@export var roof_fold_angle: float = 3.35
## Mod slots this vehicle accepts ("*" = every slot the model supports, empty = none).
@export var allowed_mods: PackedStringArray = PackedStringArray(["*"])

const MODEL_DIR := "res://gta/generated/models/vehicles/"


## Convenience constructor used by the registrar: VehicleSpec.make("sedan", "Meridian", {...}).
static func make(spec_id: String, spec_name: String, props: Dictionary = {}) -> VehicleSpec:
	var s := VehicleSpec.new()
	s.id = spec_id
	s.display_name = spec_name
	s.resource_name = spec_id
	for k: String in props:
		if k in s:
			s.set(k, props[k])
		else:
			push_warning("VehicleSpec.make(%s): unknown property '%s'" % [spec_id, k])
	return s


func get_model_path() -> String:
	if model_path != "":
		return model_path
	return MODEL_DIR + id + ".glb"


func has_model() -> bool:
	return ResourceLoader.exists(get_model_path())


## Torque factor 0..1 at rpm_fraction = rpm / redline.
func get_torque_factor(rpm_fraction: float) -> float:
	var x := clampf(rpm_fraction, 0.0, 1.0)
	if torque_curve != null:
		return clampf(torque_curve.sample_baked(x), 0.0, 1.0)
	var d := x - 0.55
	return clampf(1.0 - 1.1 * d * d, 0.0, 1.0)


## Peak torque in N*m derived from engine_power and the torque curve.
func get_peak_torque() -> float:
	var redline_omega := redline_rpm * TAU / 60.0
	var best := 0.0001
	for i in 41:
		var x := 0.2 + 0.02 * float(i)
		best = maxf(best, get_torque_factor(x) * x)
	return engine_power * 1000.0 / (best * redline_omega)


func get_flags() -> PackedStringArray:
	var out := PackedStringArray()
	if is_police:
		out.append("police")
	if is_emergency:
		out.append("emergency")
	if is_taxi:
		out.append("taxi")
	return out


func allows_mod_slot(slot: String) -> bool:
	return allowed_mods.has("*") or allowed_mods.has(slot)


func get_camera_params() -> Dictionary:
	return {"distance": cam_distance, "height": cam_height, "fov": cam_fov, "look_height": cam_look_height}


## Plain-data summary for UIs (garage, admin menu).
func to_summary() -> Dictionary:
	return {
		"id": id, "name": display_name, "class": vehicle_class, "price": price, "seats": seats,
		"mass": mass, "power_kw": engine_power, "top_speed_kmh": top_speed * 3.6,
		"drivetrain": drivetrain, "flags": get_flags(), "has_model": has_model(),
	}
