class_name SignalController
extends Node
## Drives the lamp state of every traffic-light prop from the RoadGraph signal phases.
## (AI drivers query RoadGraph.signal_state directly with the same clock.)

var graph: RoadGraph
var lights: Array = []     # [Array[MeshInstance3D], node id, axis]
var clock := 0.0
var _tick := 0.0
var _last: Dictionary = {}

func setup(g: RoadGraph, light_list: Array) -> void:
	graph = g
	lights = light_list
	_apply()

func _process(delta: float) -> void:
	clock += delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.2
		_apply()

func _apply() -> void:
	if graph == null:
		return
	for i in lights.size():
		var entry: Array = lights[i]
		var st := graph.signal_state(entry[1], entry[2], clock)
		if _last.get(i, -1) == st:
			continue
		_last[i] = st
		var v := Vector3(1, 0, 0)
		if st == 0:
			v = Vector3(0, 0, 1)
		elif st == 1:
			v = Vector3(0, 1, 0)
		for mi in entry[0]:
			if is_instance_valid(mi):
				(mi as MeshInstance3D).set_instance_shader_parameter(&"signal_state", v)

## Time in seconds on the shared signal clock.
func now() -> float:
	return clock
