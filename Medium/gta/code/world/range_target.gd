extends StaticBody3D
## Pop-up shooting range target.


func _ready() -> void:
	collision_layer = G.L_PROP
	collision_mask = 0
	var m = G.model("props/target")
	add_child(m)
	var cs = CollisionShape3D.new()
	var bs = BoxShape3D.new()
	bs.size = Vector3(0.85, 0.85, 0.14)
	cs.shape = bs
	cs.position = Vector3(0, 1.4, 0)
	add_child(cs)
	m.scale = Vector3(1, 0.05, 1)
	var tw = create_tween()
	tw.tween_property(m, "scale", Vector3.ONE, 0.18)


func damage(_amount: float, from = null, _pos := Vector3.ZERO, _kind := "bullet") -> void:
	if from == G.player and G.extras:
		G.extras.range_hit(self)
