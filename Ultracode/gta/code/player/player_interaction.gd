class_name PlayerInteraction
extends Node
## Interaction scanner of the player (docs/ARCHITECTURE.md "Interactable" mini-contract).
##
## A few times per second it looks at every node in group "interactable", keeps the best one the
## player may use (can_interact -> use_priority -> distance), shows its prompt through
## UI.show_prompt() and calls interact(player) when the matching action key is pressed.
## When no interactable is in reach it offers a ladder in reach ("Climb ladder" / "Climb down",
## interact key -> player.start_ladder) and otherwise the enter-vehicle prompt of the nearest usable
## vehicle ("Steal ..." when somebody else drives it, "(hold: ride along)" when a passenger seat is
## free). Nothing is offered while the player is busy (ladder, vault, roll, busted, ragdoll, dead,
## takedown). A stealth takedown in reach (Player.takedown_target) is offered before everything else
## ("Takedown" on melee_heavy).
## Emits EventBus.interactable_focus_changed.

const SCAN_INTERVAL := 0.15

var player: Node3D = null
var focus: Node = null                 ## current Interactable (or null)
var focus_vehicle: Node3D = null       ## vehicle the enter prompt refers to (or null)
var focus_ladder: Dictionary = {}      ## {"ladder", "from_top", "distance"} of the ladder prompt, or {}
var enabled: bool = true

var _scan_t: float = 0.0
var _prompt_shown: bool = false
var _prompt_text: String = ""
var _prompt_action: String = ""


func setup(p: Node3D) -> void:
	player = p


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_INTERVAL
		_scan()
	if focus != null and not is_instance_valid(focus):
		_set_focus(null)
	if focus == null and not focus_ladder.is_empty() and _may_act() and Input.is_action_just_pressed(&"interact"):
		var l: Variant = focus_ladder.get("ladder", null)
		if l is Node3D and is_instance_valid(l) and player.has_method("start_ladder"):
			player.call("start_ladder", l, 1 if bool(focus_ladder.get("from_top", false)) else 0)
			focus_ladder = {}
			_scan_t = 0.2
			_hide_prompt()
		return
	if focus == null or not _may_act():
		return
	var action := _action_of(focus)
	if InputMap.has_action(action) and Input.is_action_just_pressed(action):
		if focus.has_method("can_interact") and not bool(focus.call("can_interact", player)):
			return
		if focus.has_method("interact"):
			focus.call("interact", player)
		_scan_t = 0.0


## True if the focused interactable is bound to `action`; the player's own handling of that key
## (for example F = enter vehicle) must then stand back for this press.
func handles_action(action: String) -> bool:
	return enabled and focus != null and is_instance_valid(focus) and _action_of(focus) == action


## Text of the prompt that is on screen right now ("" = none).
func get_prompt_text() -> String:
	return _prompt_text if _prompt_shown else ""


func get_prompt_action() -> String:
	return _prompt_action if _prompt_shown else ""


func clear() -> void:
	_set_focus(null)
	focus_vehicle = null
	focus_ladder = {}
	_hide_prompt()


func _may_act() -> bool:
	if not enabled or Game.is_input_locked():
		return false
	if bool(player.get("is_dead")):
		return false
	if player.has_method("has_control") and not bool(player.call("has_control")):
		return false
	return true


## States in which nothing is offered (a committed motion, arrested, knocked down).
func _player_busy() -> bool:
	var sid: Variant = player.get("state_id")
	return sid is String and (sid == "ladder" or sid == "vault" or sid == "roll" or sid == "busted" \
			or sid == "ragdoll" or sid == "takedown" or sid == "freefall" or sid == "parachute")


func _action_of(it: Node) -> String:
	var a: Variant = it.get("action")
	if a is String and a != "":
		return a
	return "interact"


func _scan() -> void:
	if not enabled or bool(player.get("is_dead")) or not player.is_inside_tree() or _player_busy():
		if focus != null:
			_set_focus(null)
		focus_vehicle = null
		focus_ladder = {}
		_hide_prompt()
		return
	var origin: Vector3 = Game.get_player_position()
	var best: Node = null
	var best_prio := -1000000
	var best_dist := INF
	for n: Node in get_tree().get_nodes_in_group("interactable"):
		if not n.has_method("can_interact") or not (n is Node3D):
			continue
		if not bool(n.call("can_interact", player)):
			continue
		var prio := 0
		var pv: Variant = n.get("use_priority")
		if pv != null:
			prio = int(pv)
		var d := (n as Node3D).global_position.distance_squared_to(origin)
		if prio > best_prio or (prio == best_prio and d < best_dist):
			best = n
			best_prio = prio
			best_dist = d
	_set_focus(best)

	focus_vehicle = null
	focus_ladder = {}
	var on_foot: bool = player.get("current_vehicle") == null
	if best == null and on_foot and player.has_method("find_ladder"):
		var li: Variant = player.call("find_ladder")
		if li is Dictionary:
			focus_ladder = li
	if best == null and focus_ladder.is_empty() and on_foot and player.has_method("find_enterable_vehicle") \
			and player.has_method("can_enter_vehicles") and bool(player.call("can_enter_vehicles")):
		focus_vehicle = player.call("find_enterable_vehicle") as Node3D

	var td: Variant = player.get("takedown_target")
	if td is Node3D and is_instance_valid(td) and on_foot:
		_show_prompt("Takedown", "melee_heavy")
	elif best != null:
		var text := "Interact"
		var tv: Variant = best.get("prompt")
		if tv is String and tv != "":
			text = tv
		_show_prompt(text, _action_of(best))
	elif not focus_ladder.is_empty():
		_show_prompt("Climb down" if bool(focus_ladder.get("from_top", false)) else "Climb ladder", "interact")
	elif focus_vehicle != null:
		_show_prompt(_vehicle_prompt(focus_vehicle), "enter_vehicle")
	else:
		_hide_prompt()


func _vehicle_prompt(v: Node3D) -> String:
	var label := ""
	var dn: Variant = v.get("display_name")
	if not (dn is String and dn != ""):
		var spec: Variant = v.get("spec")
		if spec is Object and is_instance_valid(spec):
			dn = (spec as Object).get("display_name")
	if dn is String and dn != "":
		label = dn
	var cls: Variant = v.get("vehicle_class")
	var bike: bool = cls is String and (cls == "bike" or cls == "bicycle")
	var ix: Variant = player.get("vehicle_ix")
	if ix is Object and is_instance_valid(ix) and (ix as Object).has_method("has_other_driver") \
			and bool((ix as Object).call("has_other_driver", v)):
		var text := ("Shove off the rider of " if bike else "Steal ") + (label if label != "" else ("bike" if bike else "vehicle"))
		if int((ix as Object).call("passenger_seat", v)) > 0:
			text += "  (hold: ride along)"
		return text
	if cls is String:
		match cls:
			"bike", "bicycle":
				return "Ride " + (label if label != "" else "bike")
			"boat":
				return "Board " + (label if label != "" else "boat")
			"heli", "plane":
				return "Fly " + (label if label != "" else "aircraft")
	return "Enter " + (label if label != "" else "vehicle")


func _set_focus(n: Node) -> void:
	if n == focus:
		return
	focus = n
	EventBus.interactable_focus_changed.emit(n)


func _show_prompt(text: String, action: String) -> void:
	if _prompt_shown and text == _prompt_text and action == _prompt_action:
		return
	_prompt_shown = true
	_prompt_text = text
	_prompt_action = action
	UI.show_prompt(text, action)


func _hide_prompt() -> void:
	if not _prompt_shown:
		return
	_prompt_shown = false
	_prompt_text = ""
	_prompt_action = ""
	UI.hide_prompt()
