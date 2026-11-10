class_name Interactable
extends Node3D
## A world use-point (shop counter, door, wardrobe, activity start...). The player shows
## the prompt of the nearest enabled one in range and triggers it with [E].

static var all: Array[Interactable] = []

var prompt := "Use"
var radius := 2.2
var action: Callable
var condition: Callable        # optional: () -> bool
var enabled := true
var on_foot_only := true
var tag := ""

func _enter_tree() -> void:
	all.append(self)

func _exit_tree() -> void:
	all.erase(self)

func usable() -> bool:
	if not enabled or not is_inside_tree():
		return false
	if condition.is_valid() and not condition.call():
		return false
	return true

func use(by: Node) -> void:
	if action.is_valid():
		action.call(by)

static func create(parent: Node, pos: Vector3, prompt_text: String, r: float, act: Callable, tag_name := "") -> Interactable:
	var it := Interactable.new()
	it.prompt = prompt_text
	it.radius = r
	it.action = act
	it.tag = tag_name
	parent.add_child(it)
	it.global_position = pos
	return it

static func nearest(pos: Vector3, in_vehicle := false) -> Interactable:
	var best: Interactable = null
	var best_d := 1.0e9
	for it in all:
		if not is_instance_valid(it) or not it.usable():
			continue
		if in_vehicle and it.on_foot_only:
			continue
		var d := it.global_position.distance_to(pos)
		if d <= it.radius and d < best_d:
			best_d = d
			best = it
	return best
