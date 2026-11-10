class_name PlayerState
extends Node
## Base class of the player state machine (see docs/PLAYER.md "Adding a state").
##
## A state is a Node under Player/States. Player.change_state(id, args) calls exit() on the old
## state and enter() on the new one; the active state gets physics_update() every physics tick
## and frame_update() every rendered frame. New states (cover, stealth takedown, parachute ...)
## only need a script like this plus one Player.register_state() call. Ground states that walk,
## aim and shoot should extend PlayerStateOnFoot and override its hooks instead (see that file).

## Shared read-only "no camera hint" (the camera asks every frame: no allocation per frame).
const NO_HINT: Dictionary = {}

var player: Player = null
var id: String = ""                      ## key in Player.states
var public_name: String = "on_foot"      ## reported through EventBus.player_state_changed


func setup(p: Player, state_id: String) -> void:
	player = p
	id = state_id


func enter(_previous: String, _args: Dictionary) -> void:
	pass


func exit(_next: String) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func frame_update(_delta: float) -> void:
	pass


## May the weapon inventory receive fire / reload / switch input in this state?
func allows_weapons() -> bool:
	return false


## May the player start entering a vehicle from this state?
func allows_vehicle_entry() -> bool:
	return false


## World position the camera and AI should treat as "where the player is" (feet level).
func get_focus_position() -> Vector3:
	return player.global_position


## Called by Player.apply_damage BEFORE armor / health are touched. Return the amount that really
## lands (0 = the hit is avoided completely). A state may also write flags into `info` (it is a
## private copy): "no_ragdoll", "knockdown" = false, "blocked" = true ... Used by the melee block,
## the dodge roll / step and (next wave) cover.
func modify_damage(_info: Dictionary, amount: float) -> float:
	return amount


## Called by Player.apply_damage after health was reduced (the player is still alive).
func on_damage(_info: Dictionary, _amount: float) -> void:
	pass


## Camera overrides of this state for the third-person / aim camera (PlayerCamera reads it every
## frame). {} = the defaults. Keys (all optional): "side", "height", "distance" (the shoulder
## offset / pivot height / arm length that replace the mode's values), "pivot_offset" (Vector3
## added to the pivot), "mask" (extra collision layers for the camera probe). Cover uses it.
func get_camera_hint() -> Dictionary:
	return NO_HINT


## Called at the end of Player._update_animator (render frame, on foot) after the shared animator
## parameters were set: a state may refine them (cover: cover_side / cover_peek / cover_blind).
func update_animator(_a: HumanoidAnimator) -> void:
	pass
