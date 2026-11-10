class_name Interactable
extends Area3D
## Shared use-point component (written by the lead; frozen contract).
## Put one wherever the player can press a key to do something: shop counters, doors, garage
## pads, wardrobe, bed, ladders, activity starts, pickups that need a key press ...
##
## The PLAYER module scans group "interactable" each few frames, picks the best candidate in
## range (can_interact), shows the prompt through UI.show_prompt(prompt, action) and calls
## interact(player) when the action key is pressed. World code just creates these:
##
##     var it := Interactable.create("Browse weapons", 2.2)
##     it.position = Vector3(0, 1, 0)
##     counter.add_child(it)
##     it.interacted.connect(func(player): UI.open_screen("shop_weapons", {"shop_id": "ammo_depot"}))

signal interacted(player: Node3D)

@export var prompt: String = "Interact"
@export var action: String = "interact"      ## input action shown/used ("interact" = E, "enter_vehicle" = F)
@export var radius: float = 2.0
@export var enabled: bool = true
@export var on_foot_only: bool = true        ## ignore while the player sits in a vehicle
@export var in_vehicle_only: bool = false    ## e.g. mod-garage pad, drive-through
@export var use_priority: int = 0            ## higher wins when several are in range
@export var cooldown: float = 0.4

var condition: Callable = Callable()         ## optional extra predicate: func(player) -> bool
var _last_use_msec: int = -100000


static func create(prompt_text: String, use_radius: float = 2.0, use_action: String = "interact") -> Interactable:
	var it := Interactable.new()
	it.prompt = prompt_text
	it.radius = use_radius
	it.action = use_action
	return it


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = Layers.TRIGGER
	collision_mask = 0
	monitoring = false
	monitorable = true
	if get_child_count() == 0:
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		shape.shape = sphere
		add_child(shape)


func can_interact(player: Node3D) -> bool:
	if not enabled or not is_inside_tree() or player == null:
		return false
	if Time.get_ticks_msec() - _last_use_msec < int(cooldown * 1000.0):
		return false
	var in_vehicle: bool = player.get("current_vehicle") != null
	if on_foot_only and not in_vehicle_only and in_vehicle:
		return false
	if in_vehicle_only and not in_vehicle:
		return false
	var p: Vector3 = Game.get_player_position()
	if p.distance_to(global_position) > radius + (2.5 if in_vehicle else 0.0):
		return false
	if condition.is_valid() and not bool(condition.call(player)):
		return false
	return true


func interact(player: Node3D) -> void:
	if not can_interact(player):
		return
	_last_use_msec = Time.get_ticks_msec()
	interacted.emit(player)
