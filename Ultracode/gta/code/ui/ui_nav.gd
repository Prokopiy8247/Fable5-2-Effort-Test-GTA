class_name UiNav
extends Node
## Waypoint + GPS route shared by the minimap and the full map (child of the UI autoload:
## UI.nav). Setting / clearing goes through EventBus.waypoint_changed, and waypoints emitted by
## other modules on that signal are picked up too. No mission markers: the only marker is the
## player's own waypoint.

const ARRIVE_DISTANCE := 14.0
const REROUTE_DISTANCE := 12.0

var has_waypoint: bool = false
var waypoint: Vector3 = Vector3.ZERO
var route: PackedVector2Array = PackedVector2Array()   ## map space (x, z), player -> waypoint
var route_version: int = 0
var route_length: float = 0.0

var _last_from: Vector3 = Vector3.INF
var _timer: float = 0.0
var _emitting: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	EventBus.waypoint_changed.connect(_on_waypoint_changed)


func set_waypoint(pos: Vector3) -> void:
	has_waypoint = true
	waypoint = pos
	recompute()
	_emit()


func clear_waypoint() -> void:
	if not has_waypoint:
		return
	has_waypoint = false
	route = PackedVector2Array()
	route_length = 0.0
	route_version += 1
	_emit()


func _emit() -> void:
	_emitting = true
	EventBus.waypoint_changed.emit(has_waypoint, waypoint)
	_emitting = false


func _on_waypoint_changed(has: bool, pos: Vector3) -> void:
	if _emitting:
		return
	has_waypoint = has
	waypoint = pos
	if has:
		recompute()
	else:
		route = PackedVector2Array()
		route_length = 0.0
		route_version += 1


func _process(delta: float) -> void:
	if not has_waypoint:
		return
	_timer += delta
	if _timer < 0.5:
		return
	_timer = 0.0
	if not Game.has_player():
		return
	var p := Game.get_player_position()
	if Vector2(p.x - waypoint.x, p.z - waypoint.z).length() < ARRIVE_DISTANCE:
		clear_waypoint()
		UI.notify("Destination reached", "good")
		return
	if _last_from.distance_to(p) > REROUTE_DISTANCE:
		recompute()


## Rebuild the route from the player's position (RoadGraph.find_route when the world has it,
## else a straight line).
func recompute() -> void:
	var from := Game.get_player_position()
	_last_from = from
	var a := Vector2(from.x, from.z)
	var b := Vector2(waypoint.x, waypoint.z)
	var pts := PackedVector2Array()
	var w: Node = Game.world
	if w != null and is_instance_valid(w):
		var graph: Variant = w.get("roads")
		if graph is Object and is_instance_valid(graph) and (graph as Object).has_method("find_route"):
			var r: Variant = (graph as Object).call("find_route", from, waypoint)
			pts = UiMapData.to_points(r)
	if pts.size() < 2:
		pts = PackedVector2Array([a, b])
	else:
		if pts[0].distance_to(a) > 1.5:
			pts.insert(0, a)
		if pts[pts.size() - 1].distance_to(b) > 1.5:
			pts.append(b)
	route = pts
	route_length = 0.0
	for i in pts.size() - 1:
		route_length += pts[i].distance_to(pts[i + 1])
	route_version += 1
