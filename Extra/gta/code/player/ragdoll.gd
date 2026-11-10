class_name Ragdoll
extends RigidBody3D
## Lightweight physical knock-down body: a tumbling capsule that carries the character visual in a limp pose.
## Used for deaths, vehicle impacts, explosions and hard falls (player and NPCs).

var vis: CharVisual
var settle_t := 0.0
var age := 0.0
var owner_char: Node = null


static func start(who: Node3D, visual: CharVisual, impulse: Vector3, dead: bool) -> Ragdoll:
	var r := Ragdoll.new()
	r.owner_char = who
	r.vis = visual
	r.collision_layer = G.L_DEBRIS
	r.collision_mask = G.L_WORLD | G.L_VEHICLE
	r.mass = 75.0
	r.angular_damp = 1.6
	r.linear_damp = 0.15
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	r.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.27
	cap.height = 1.5
	cs.shape = cap
	r.add_child(cs)
	G.main.add_child(r)
	r.global_transform = Transform3D(who.global_transform.basis.orthonormalized(), who.global_position + Vector3(0, 0.85, 0))
	if visual.get_parent():
		visual.get_parent().remove_child(visual)
	r.add_child(visual)
	visual.transform = Transform3D(Basis(), Vector3(0, -0.85, 0))
	visual.mode = "dead" if dead else "fall"
	visual.aim = 0.0
	visual.crouch = 0.0
	visual.speed = 0.0
	var imp := impulse * r.mass
	r.apply_central_impulse(imp)
	var flat := Vector3(impulse.x, 0, impulse.z)
	var axis := Vector3.UP.cross(flat.normalized()) if flat.length() > 0.2 else Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()
	r.apply_torque_impulse(axis * 55.0)
	return r


func _physics_process(delta: float) -> void:
	age += delta
	var sp := linear_velocity.length()
	if vis:
		vis.mode = "dead" if sp < 2.5 else "fall"
		vis.tick(delta)
	if global_position.y < G.WATER_LEVEL - 0.3:
		apply_central_force(Vector3.UP * mass * 13.0)
		linear_damp = 2.0
	if sp < 0.4 and angular_velocity.length() < 0.8:
		settle_t += delta
	else:
		settle_t = 0.0


func settled() -> bool:
	return settle_t > 0.5 or age > 4.0


func release_visual(new_parent: Node3D) -> void:
	if vis and vis.get_parent() == self:
		remove_child(vis)
		new_parent.add_child(vis)
		vis.transform = Transform3D.IDENTITY
