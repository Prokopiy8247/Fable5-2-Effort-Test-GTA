class_name TrafficDummy
extends Node3D
## The lightweight seated driver of an AI traffic vehicle (= `vehicle.driver`, ARCHITECTURE_WAVE2
## W2.1). It sits in the driver seat node with an identity transform. It has no _process: the
## TrafficSystem manager attaches a pooled humanoid visual (humanoid.tscn + HumanoidAnimator in
## the `seated_car` state at a low update rate) only while the vehicle is near the camera.
##
## When the vehicle throws its occupants out (explosion, a carjack that calls occupant_enter
## directly, admin eject) VehicleBase calls on_vehicle_ejected(): the dummy forwards it to the
## traffic system, which turns the driver into a real NPC (Game.spawn_npc) or just cleans up.

var system: Node = null                 ## TrafficSystem
var driver_uid: int = 0
var archetype: String = "civilian_m"    ## npc archetype (civilian_m / civilian_f / civilian_tough / taxi_driver)
var look_archetype: String = "civilian_m"   ## CharacterVisual archetype of the seated look
var look_seed: int = 0
var visual: Node3D = null               ## pooled CharacterVisual (humanoid.tscn) or null when far
var animator: Node = null               ## its HumanoidAnimator
var appearance: Dictionary = {}         ## remembered look (so the NPC that gets out matches)
var health: float = 100.0
var lethal_info: Dictionary = {}        ## damage that killed the driver inside the car (explosion)


func _init() -> void:
	name = "TrafficDriver"


## Occupant damage (VehicleDamage hits every occupant with a lethal blast before ejecting them).
func apply_damage(info: Dictionary) -> void:
	var amount := float(info.get("amount", 0.0))
	health -= amount
	if health <= 0.0 and lethal_info.is_empty():
		lethal_info = info.duplicate()


func is_dead() -> bool:
	return health <= 0.0


## VehicleBase._evict() hook: the seat is already free.
func on_vehicle_ejected(vehicle: Node, exit_xform: Transform3D, impulse: Vector3 = Vector3.ZERO) -> void:
	if system != null and is_instance_valid(system) and system.has_method("_on_dummy_ejected"):
		system.call("_on_dummy_ejected", self, vehicle, exit_xform, impulse)


func get_appearance() -> Dictionary:
	if visual != null and is_instance_valid(visual) and visual.has_method("get_appearance"):
		return visual.call("get_appearance")
	return appearance.duplicate()


func get_target_position() -> Vector3:
	return global_position + Vector3.UP * 0.45
