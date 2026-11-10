class_name Projectile
extends Node3D
## Rockets, launched/thrown grenades and firebottles (manual ballistic stepping with raycasts).

var kind := "rocket"
var shooter: Node = null
var vel := Vector3.ZERO
var wdef := {}
var life := 0.0
var fuse := 2.6
var gravity := 0.0
var bounces := 0
var spin := Vector3.ZERO
var done := false
var mesh: MeshInstance3D


func setup(k: String, who: Node, _from: Vector3, dir: Vector3, d: Dictionary) -> void:
	kind = k
	shooter = who
	wdef = d
	mesh = MeshInstance3D.new()
	add_child(mesh)
	match kind:
		"rocket":
			vel = dir * 48.0
			mesh.mesh = Assets.mesh("props/vfx_kit", "proj_rocket")
			fuse = 6.0
		"grenade40":
			vel = dir * 36.0 + Vector3(0, 2.0, 0)
			gravity = 9.8
			mesh.mesh = Assets.mesh("props/vfx_kit", "proj_grenade40")
			fuse = 5.0
		"grenade":
			vel = dir * 15.0 + Vector3(0, 4.5, 0)
			gravity = 12.0
			mesh.mesh = Assets.mesh("weapons/weapons", "w_grenade_Body")
			fuse = 2.7
			spin = Vector3(6, 2, 4)
		"molotov":
			vel = dir * 14.0 + Vector3(0, 4.5, 0)
			gravity = 12.0
			mesh.mesh = Assets.mesh("weapons/weapons", "w_molotov_Body")
			fuse = 6.0
			spin = Vector3(8, 0, 3)
	if shooter is Node3D and shooter.get("velocity") != null and kind in ["grenade", "molotov"]:
		vel += (shooter.get("velocity") as Vector3) * 0.6


func _ready() -> void:
	if kind == "rocket" and G.fx:
		G.fx.attach_trail(self)


func _physics_process(delta: float) -> void:
	if done:
		return
	life += delta
	fuse -= delta
	if kind == "rocket":
		vel = vel.normalized() * minf(vel.length() + 55.0 * delta, 85.0)
	vel.y -= gravity * delta
	var from := global_position
	var to := from + vel * delta
	var excl: Array = []
	if shooter is CollisionObject3D and life < 0.25:
		excl.append((shooter as CollisionObject3D).get_rid())
		var sv = shooter.get("vehicle")
		if sv != null and sv is CollisionObject3D:
			excl.append((sv as CollisionObject3D).get_rid())
	var hit := G.ray(from, to, 1 | 2 | 4 | 8, excl)
	if not hit.is_empty():
		if kind == "grenade":
			global_position = hit.position + hit.normal * 0.06
			vel = vel.bounce(hit.normal) * 0.38
			bounces += 1
			Sfx.play("hit_metal", global_position, -12.0, 1.6)
			if vel.length() < 1.2:
				vel = Vector3.ZERO
				gravity = 0.0 if hit.normal.y > 0.5 else gravity
		else:
			global_position = hit.position
			_detonate(hit.normal)
			return
	else:
		global_position = to
	if global_position.y < G.WATER_LEVEL and kind != "grenade":
		if G.fx:
			G.fx.splash(Vector3(global_position.x, G.WATER_LEVEL, global_position.z), 1.5)
		if kind == "molotov":
			done = true
			queue_free()
			return
		_detonate(Vector3.UP)
		return
	if vel.length() > 0.5:
		if spin != Vector3.ZERO:
			rotation += spin * delta
		else:
			look_at(global_position + vel.normalized(), Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.RIGHT)
	if fuse <= 0.0:
		_detonate(Vector3.UP)


func _detonate(normal: Vector3) -> void:
	if done:
		return
	done = true
	var pos := global_position + normal * 0.3
	if kind == "molotov":
		Sfx.play("glass", pos, 0.0, 0.8)
		Sfx.play("fire_whoosh", pos)
		var zone := FireZone.new()
		zone.shooter = shooter
		G.main.add_child(zone)
		zone.global_position = pos
		G.report_crime("explosion", pos, 1.5, shooter)
	else:
		if G.fx:
			G.fx.explosion(pos, 1.25 if kind == "rocket" else 1.0)
		G.damage_radius(pos, float(wdef.get("radius", 6.0)), float(wdef.get("dmg", 250.0)), shooter)
	queue_free()


class FireZone:
	extends Node3D
	var shooter: Node = null
	var life := 7.5
	var tick := 0.0

	func _ready() -> void:
		for i in 6:
			var off := Vector3(randf_range(-2.4, 2.4), 0.0, randf_range(-2.4, 2.4)) if i > 0 else Vector3.ZERO
			var p := global_position + off
			var h := G.ray(p + Vector3(0, 1.5, 0), p - Vector3(0, 3, 0), 1)
			if not h.is_empty() and G.fx:
				var e: Node3D = G.fx.fire_at(h.position, randf_range(0.7, 1.1), life + randf())
				e.name = "f%d" % i

	func _process(delta: float) -> void:
		life -= delta
		tick -= delta
		if tick <= 0.0:
			tick = 0.4
			for ch in get_tree().get_nodes_in_group("chars"):
				var n := ch as Node3D
				if n and n.global_position.distance_to(global_position) < 3.4 and ch.has_method("take_damage"):
					ch.take_damage(11.0, shooter, n.global_position, "fire")
			for v in get_tree().get_nodes_in_group("vehicles"):
				var vn := v as Node3D
				if vn and vn.global_position.distance_to(global_position) < 4.5 and v.has_method("take_damage"):
					v.take_damage(26.0, shooter, vn.global_position, "fire")
		if life <= 0.0:
			queue_free()
