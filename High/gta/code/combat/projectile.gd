class_name Projectile
extends Node3D
## Rockets, launched/thrown grenades and fire bottles. Simple swept-ray ballistic integration (no rigid bodies).

var kind := "rocket"
var vel := Vector3.ZERO
var attacker = null
var dmg := 200.0
var life := 0.0
var fuse := 2.6
var bounces := 0
var _mesh: Node3D
var _trail_t := 0.0


static func launch(p_kind: String, pos: Vector3, velocity: Vector3, p_attacker, p_dmg: float) -> Projectile:
	var p := Projectile.new()
	p.kind = p_kind
	p.vel = velocity
	p.attacker = p_attacker
	p.dmg = p_dmg
	Game.world.add_child(p)
	p.global_position = pos
	p._mesh = Assets.inst({"rocket": "w_rocket", "grenade": "w_grenade", "molotov": "w_molotov"}[p_kind])
	p.add_child(p._mesh)
	if p_kind == "rocket":
		p.look_at(pos + velocity, Vector3.UP)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.2)
		l.light_energy = 2.0
		l.omni_range = 6.0
		l.shadow_enabled = false
		p.add_child(l)
	return p


func _physics_process(delta: float) -> void:
	life += delta
	if kind != "rocket":
		vel.y -= 14.0 * delta
		_mesh.rotate_x(delta * 9.0)
	else:
		vel += vel.normalized() * 30.0 * delta
		_trail_t -= delta
		if _trail_t <= 0.0:
			_trail_t = 0.03
			Fx.dust(global_position, 0.45, Color(0.85, 0.85, 0.85, 0.6))
	var from := global_position
	var to := from + vel * delta
	var ex: Array = []
	if life < 0.25 and attacker != null and is_instance_valid(attacker):
		ex.append(attacker)
		if attacker is Player and attacker.in_vehicle():
			ex.append(attacker.vehicle)
	var hit := Game.ray(from, to, Game.MASK_SHOT, ex)
	if not hit.is_empty():
		if kind == "rocket" or kind == "molotov" or hit.collider is CharacterBody3D or hit.collider is Vehicle:
			global_position = hit.position
			_detonate()
			return
		# grenade bounce
		bounces += 1
		vel = vel.bounce(hit.normal) * 0.38
		global_position = hit.position + hit.normal * 0.06
		Sfx.play3d("impact_concrete", global_position, -8.0, 1.4, 30.0)
		if vel.length() < 1.0:
			vel = Vector3.ZERO
	else:
		global_position = to
	if global_position.y < Game.WATER_Y and City.terrain_height(global_position.x, global_position.z) < Game.WATER_Y:
		Fx.splash(Vector3(global_position.x, Game.WATER_Y, global_position.z), 1.0)
		if kind == "molotov":
			queue_free()
			return
		vel *= 0.9
	if (kind == "grenade" and life > fuse) or life > 8.0:
		_detonate()


func _detonate() -> void:
	var p := global_position
	match kind:
		"molotov":
			Sfx.play3d("glass_break", p, 0.0)
			Fx.fire_patch(p, 10.0, 3.0, attacker)
			Fx.explosion(p, 2.5, 25.0, attacker)
		"rocket":
			Fx.explosion(p, 9.0, dmg, attacker)
		_:
			Fx.explosion(p, 7.5, dmg, attacker)
	queue_free()
