extends StaticBody3D
## Hit volume carried by the shark so it can be shot.

var mgr: Node = null
var dead := false


func take_damage(a: float, _instigator: Node = null, _pos: Vector3 = Vector3.ZERO, _k: String = "") -> void:
	if mgr != null:
		mgr.shark_hit(a)
