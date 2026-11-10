class_name Combat
extends RefCounted
## Shared damage routing: bullets, melee hits and vehicle-versus-character impacts.


static func surface_of(collider) -> String:
	if collider is Vehicle:
		return "metal"
	if collider is CharacterBody3D:
		return "flesh"
	if collider is RigidBody3D:
		return "metal"
	return "concrete"


static func apply_bullet(hit: Dictionary, dir: Vector3, dmg: float, attacker) -> void:
	var c = hit.collider
	var pos: Vector3 = hit.position
	var nrm: Vector3 = hit.normal
	if c is Npc:
		var rel: float = pos.y - c.global_position.y
		var mult := 1.0
		if rel > 1.5 * c.rig.height_scale:
			mult = 3.0
		elif rel < 0.8:
			mult = 0.7
		c.damage(dmg * mult, pos - dir, attacker, "bullet", mult > 2.0)
		Fx.impact(pos, -dir, "flesh")
	elif c is Player:
		c.damage(dmg, pos - dir * 3.0, attacker, "bullet")
		Fx.impact(pos, -dir, "flesh")
	elif c is Vehicle:
		c.damage(dmg * 0.55, pos, attacker)
		Fx.impact(pos, nrm, "metal")
		if c.driver_rig != null and attacker == Game.player and randf() < 0.22 and Game.traffic:
			Game.traffic.on_vehicle_shot(c, attacker)
		elif c.driver == Game.player and Game.player != null and randf() < 0.18:
			Game.player.damage(dmg * 0.5, pos - dir * 3.0, attacker, "bullet")
	elif c is Animal:
		c.hit(dmg, attacker)
		Fx.impact(pos, -dir, "flesh")
	else:
		var handled := false
		if Game.world and Game.world.props:
			handled = Game.world.props.bullet_hit(c, pos, dir, attacker)
		if c is RigidBody3D:
			c.apply_impulse(dir * dmg * 0.4, pos - c.global_position)
			handled = true
			Fx.impact(pos, nrm, "metal")
		if not handled:
			var surf := "concrete"
			if pos.y < 0.3 and City.district_name(pos) in ["Signal Hill", "Founders Park", "Marlow Airfield"]:
				surf = "dirt"
			Fx.impact(pos, nrm, surf)
		if Game.world and Game.world.activities:
			Game.world.activities.on_bullet(c, pos, attacker)


static func apply_melee(hit: Dictionary, dir: Vector3, dmg: float, attacker) -> void:
	var c = hit.collider
	var pos: Vector3 = hit.position
	if c is Vehicle:
		c.damage(dmg * 0.4, pos, attacker)
		c.apply_impulse(dir * 150.0, pos - c.global_position)
		Fx.impact(pos, hit.normal, "metal")
		if c.driver_rig != null and Game.traffic:
			Game.traffic.on_vehicle_shot(c, attacker)
	elif c is Animal:
		c.hit(dmg, attacker)
	elif c is RigidBody3D:
		c.apply_impulse(dir * 60.0, pos - c.global_position)
		Fx.impact(pos, hit.normal, "metal")
	else:
		if Game.world and Game.world.props:
			Game.world.props.bullet_hit(c, pos, dir, attacker)
		Fx.impact(pos, hit.normal, "concrete")


static func vehicle_hits() -> void:
	## Vehicles do not physically collide with characters; fast ones knock them down here.
	var pl = Game.player
	for v in Game.vehicles:
		if not is_instance_valid(v) or v.parked:
			continue
		var vel: Vector3 = v.linear_velocity
		var sp := vel.length()
		if sp < 2.5:
			continue
		var inv: Transform3D = v.global_transform.affine_inverse()
		var hx: float = v._half.x + 0.35
		var hz: float = v._half.z + 0.35
		var zc: float = v._aabb.position.z + v._aabb.size.z * 0.5
		for n in Game.npcs:
			if not is_instance_valid(n) or n.down_time > 0.0 or n.in_vehicle:
				continue
			var d: Vector3 = n.global_position - v.global_position
			if absf(d.x) > 8.0 or absf(d.z) > 8.0:
				continue
			var lp: Vector3 = inv * (n.global_position + Vector3.UP * 0.6)
			if absf(lp.x) < hx and absf(lp.z - zc) < hz and lp.y > -0.6 and lp.y < 2.6:
				var rel: Vector3 = vel - n.velocity
				if rel.length() > 3.0 and rel.dot(n.global_position - v.global_position) > 0.0:
					var attacker = v.driver
					n.damage(clampf((rel.length() - 2.0) * 7.0, 4.0, 400.0), v.global_position, attacker, "vehicle")
					if is_instance_valid(n):
						n.knockdown(vel * 0.75 + Vector3.UP * (2.5 + sp * 0.12), attacker)
					Sfx.play3d("punch", n.global_position, 2.0, 0.7, 40.0)
					if attacker == pl and pl != null:
						Wanted.crime("hit_ped", n.global_position)
						if Game.cam:
							Game.cam.shake(0.25)
		if pl != null and is_instance_valid(pl) and not pl.in_vehicle() and pl.state in [Player.St.FOOT, Player.St.COVER] and v.driver != pl:
			var lp2: Vector3 = inv * (pl.global_position + Vector3.UP * 0.6)
			if absf(lp2.x) < hx and absf(lp2.z - zc) < hz and lp2.y > -0.6 and lp2.y < 2.6 and sp > 4.0:
				if vel.dot(pl.global_position - v.global_position) > 0.0:
					pl.damage(clampf((sp - 3.0) * 5.0, 3.0, 120.0), v.global_position, null, "vehicle")
					if pl.alive():
						pl.knockdown(vel * 0.7 + Vector3.UP * 3.0)
