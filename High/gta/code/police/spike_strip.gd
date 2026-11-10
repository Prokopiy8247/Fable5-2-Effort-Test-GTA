class_name SpikeStrip
extends Node3D
## Police spike strip: punctures the tyres of any vehicle that drives over it (unless bullet-resistant).

var width := 8.0
var _done: Dictionary = {}


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 0.05, 0.45)
	mi.mesh = bm
	mi.material_override = CharRig.color_mat(Color(0.12, 0.12, 0.13), 0.6)
	add_child(mi)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var pm := PrismMesh.new()
	pm.size = Vector3(0.08, 0.14, 0.08)
	pm.material = CharRig.color_mat(Color(0.8, 0.82, 0.85), 0.3)
	mm.mesh = pm
	var n := int(width / 0.22)
	mm.instance_count = n
	for i in range(n):
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(-width * 0.5 + (i + 0.5) * width / n, 0.09, (i % 2) * 0.16 - 0.08)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _physics_process(_delta: float) -> void:
	var inv := global_transform.affine_inverse()
	for v in Game.vehicles:
		if not is_instance_valid(v) or _done.has(v.get_instance_id()) or v.wheels.is_empty():
			continue
		var lp: Vector3 = inv * v.global_position
		if absf(lp.x) < width * 0.5 + 0.5 and absf(lp.z) < v._half.z and absf(lp.y) < 1.5 and v.linear_velocity.length() > 2.0:
			_done[v.get_instance_id()] = true
			if v.bulletproof_tires:
				continue
			for w in v.wheels:
				w.flat = true
			Sfx.play3d("shot_suppressed", v.global_position, 0.0, 0.5)
			if v.driver == Game.player and v.driver != null:
				Game.say("Tyres shredded by a spike strip!", Color(1.0, 0.5, 0.4))
