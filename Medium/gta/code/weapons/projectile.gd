extends RigidBody3D
## Rocket / thrown grenade / launcher grenade.

var kind := "grenade"
var dmg := 200.0
var source: Node3D
var life := 0.0
var fuse := 2.6
var dead := false
var trail: CPUParticles3D


func launch(origin: Vector3, dir: Vector3, ex: Array) -> void:
	collision_layer = 0
	collision_mask = G.L_WORLD | G.L_VEH | G.L_CHAR | G.L_PROP
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = true
	mass = 0.6
	var cs = CollisionShape3D.new()
	var s = SphereShape3D.new()
	s.radius = 0.09
	cs.shape = s
	add_child(cs)
	for r in ex:
		PhysicsServer3D.body_add_collision_exception(get_rid(), r)
	var vis = G.model("weapons/" + ("rocket" if kind == "rocket" else "grenade"))
	add_child(vis)
	global_position = origin
	match kind:
		"rocket":
			gravity_scale = 0.0
			look_at(origin + dir, Vector3.UP if abs(dir.y) < 0.98 else Vector3.RIGHT)
			linear_velocity = dir * 60.0
			fuse = 6.0
			trail = G.fx.make_smoke(self, Color(0.85, 0.85, 0.85), 0.25)
		"gl":
			linear_velocity = dir * 38.0 + Vector3.UP * 3.0
			fuse = 5.0
		_:
			var pm = PhysicsMaterial.new()
			pm.bounce = 0.35
			pm.friction = 0.8
			physics_material_override = pm
			linear_velocity = dir * 17.0
			angular_velocity = Vector3(6, 2, 4)
			if source and source.get("velocity") != null:
				linear_velocity += source.velocity * 0.6
	body_entered.connect(_hit)


func _hit(_b: Node) -> void:
	if kind == "grenade":
		if life > 0.1:
			G.audio.play3d("metal", global_position, -14.0, 1.6)
	else:
		_boom()


func _physics_process(dt: float) -> void:
	life += dt
	if kind == "rocket":
		linear_velocity = linear_velocity.normalized() * min(95.0, linear_velocity.length() + 70.0 * dt)
	if life >= fuse or (global_position.y < G.WATER_Y - 2.0):
		_boom()


func _boom() -> void:
	if dead:
		return
	dead = true
	G.fx.explode(global_position, 8.5 if kind == "rocket" else 7.0, dmg, source)
	queue_free()
