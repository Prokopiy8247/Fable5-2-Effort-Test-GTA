extends RigidBody3D
## Red barrel: explodes when shot / burned / hit hard.

var hp := 40.0
var dead := false


func damage(amount: float, _from = null, _pos := Vector3.ZERO, _kind := "bullet") -> void:
	if dead:
		return
	hp -= amount
	if hp <= 0.0:
		dead = true
		var p = global_position + Vector3(0, 0.5, 0)
		get_tree().create_timer(0.08).timeout.connect(func():
			G.fx.explode(p, 7.0, 220.0, _from)
			queue_free())
