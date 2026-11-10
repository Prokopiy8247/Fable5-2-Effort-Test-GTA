class_name Projectile
extends Node3D
## Rockets, launcher grenades and hand grenades. Rockets / 40 mm rounds fly kinematically and
## detonate on contact; hand grenades are small rigid bodies on a fuse.

var kind := "rocket"
var vel := Vector3.ZERO
var owner_char: Node = null
var life := 0.0
var _exclude: Array[RID] = []
var _loop: AudioStreamPlayer3D = null
var _body: RigidBody3D = null
var _done := false

const CFG := {
	"rocket": {"model": "weapons/rocket", "speed": 38.0, "accel": 60.0, "max": 85.0, "gravity": 0.0, "radius": 8.5, "damage": 230.0, "life": 6.0},
	"grenade40": {"model": "weapons/grenade_40mm", "speed": 42.0, "accel": 0.0, "max": 42.0, "gravity": 13.0, "radius": 6.5, "damage": 170.0, "life": 7.0},
	"grenade": {"model": "weapons/grenade", "speed": 16.0, "radius": 7.0, "damage": 190.0, "fuse": 2.6},
}

static func spawn(proj_kind: String, pos: Vector3, dir: Vector3, by: Node, speed := -1.0) -> Projectile:
	var p := Projectile.new()
	p.kind = proj_kind
	p.owner_char = by
	var cfg: Dictionary = CFG[proj_kind]
	p.vel = dir.normalized() * (speed if speed > 0.0 else float(cfg["speed"]))
	var parent: Node = Game.main.get_node_or_null("Entities") if Game.main else null
	if parent == null:
		parent = Game.main
	parent.add_child(p)
	p.global_position = pos
	p._start()
	return p

func _start() -> void:
	var cfg: Dictionary = CFG[kind]
	if owner_char is CollisionObject3D:
		_exclude.append((owner_char as CollisionObject3D).get_rid())
		var veh: Variant = owner_char.get("vehicle")
		if veh != null and is_instance_valid(veh) and veh is CollisionObject3D:
			_exclude.append((veh as CollisionObject3D).get_rid())
	var mesh_holder: Node3D = self
	if kind == "grenade":
		_body = RigidBody3D.new()
		_body.collision_layer = Phys.PROJECTILE
		_body.collision_mask = Phys.WORLD | Phys.VEHICLE | Phys.PROP
		_body.mass = 0.4
		_body.continuous_cd = true
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.35
		pm.friction = 0.8
		_body.physics_material_override = pm
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.06
		cs.shape = sh
		_body.add_child(cs)
		add_child(_body)
		_body.top_level = true
		_body.global_position = global_position
		_body.linear_velocity = vel
		_body.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		_body.contact_monitor = true
		_body.max_contacts_reported = 2
		_body.body_entered.connect(func(_b: Node) -> void: Audio.play(&"grenade_bounce", _body.global_position, -8.0))
		for r in _exclude:
			PhysicsServer3D.body_add_collision_exception(_body.get_rid(), r)
		mesh_holder = _body
	if Assets.has_model(String(cfg["model"])):
		var m := Assets.instance(String(cfg["model"]))
		mesh_holder.add_child(m)
	else:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		mi.mesh = sm
		mesh_holder.add_child(mi)
	if kind == "rocket":
		_loop = Audio.make_loop(&"rocket_fly", self, -4.0, 90.0)
		if Game.fx:
			Game.fx.attach_trail(self)
	if vel.length() > 0.1 and kind != "grenade":
		look_at(global_position + vel, Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.RIGHT)

func _physics_process(delta: float) -> void:
	if _done:
		return
	life += delta
	var cfg: Dictionary = CFG[kind]
	if kind == "grenade":
		if life >= float(cfg["fuse"]):
			_explode(_body.global_position)
		return
	var sp := vel.length()
	var dirv := vel / maxf(sp, 0.001)
	sp = minf(float(cfg["max"]), sp + float(cfg["accel"]) * delta)
	vel = dirv * sp
	vel.y -= float(cfg["gravity"]) * delta
	var from := global_position
	var to := from + vel * delta
	var hit := Game.ray(from, to, Phys.SHOOTABLE, _exclude)
	if not hit.is_empty():
		_explode(hit["position"] + (hit["normal"] as Vector3) * 0.15)
		return
	if to.y < Terrain.SEA and Terrain.is_water(to.x, to.z):
		_explode(Vector3(to.x, Terrain.SEA, to.z))
		return
	global_position = to
	if vel.length() > 0.1:
		look_at(to + vel, Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.RIGHT)
	if life > float(cfg["life"]):
		_explode(global_position)

func _explode(pos: Vector3) -> void:
	if _done:
		return
	_done = true
	var cfg: Dictionary = CFG[kind]
	if Game.fx:
		Game.fx.explosion(pos, float(cfg["radius"]), float(cfg["damage"]), owner_char)
	queue_free()
