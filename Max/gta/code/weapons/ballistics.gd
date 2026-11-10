class_name Ballistics
extends RefCounted
## Hitscan bullets: damage zones, range fall-off, thin-material penetration, surface FX.

static func surface_of(collider: Object, pos: Vector3) -> StringName:
	if collider is Character:
		return &"flesh"
	if collider is Vehicle:
		return &"metal"
	if collider is Node and (collider as Node).has_meta("surface"):
		var s: StringName = (collider as Node).get_meta("surface")
		if s == &"ground":
			if pos.z > Terrain.COAST_Z or pos.x > Terrain.EAST_X:
				return &"dirt"
			return &"dirt"
		return s
	if collider is Prop:
		return &"metal" if (collider as Prop).mass > 14.0 else &"wood"
	return &"concrete"

## Fires one bullet. Returns {} or the final hit dictionary (position, normal, collider).
static func hitscan(shooter: Character, from: Vector3, dir: Vector3, max_range: float, dmg: float, pellet := false) -> Dictionary:
	var exclude: Array[RID] = []
	if shooter != null:
		exclude.append(shooter.get_rid())
		if shooter.vehicle != null and is_instance_valid(shooter.vehicle) and shooter.vehicle is CollisionObject3D:
			exclude.append((shooter.vehicle as CollisionObject3D).get_rid())
	var start := from
	var remaining := max_range
	var last := {}
	var end_point := from + dir * max_range
	for pass_i in 3:
		var to := start + dir * remaining
		var hit := Game.ray(start, to, Phys.SHOOTABLE, exclude)
		if hit.is_empty():
			break
		last = hit
		var pos: Vector3 = hit["position"]
		var nrm: Vector3 = hit["normal"]
		var c: Object = hit["collider"]
		end_point = pos
		var travelled := from.distance_to(pos)
		var fall := 1.0 - 0.5 * smoothstep(max_range * 0.55, max_range, travelled)
		var d := dmg * fall * (0.6 if pass_i > 0 else 1.0)
		var surf := surface_of(c, pos)
		var go_through := false
		if c is Character:
			var ch := c as Character
			ch.apply_damage(d, shooter, pos, dir, {"type": "bullet", "zone": ch.hit_zone(pos), "force": 1.5})
			if shooter != null and shooter.is_player and Game.skills:
				Game.skills.add(&"shooting", 0.004)
		elif c is PhysicalBone3D:
			(c as PhysicalBone3D).apply_impulse(dir * 18.0, pos - (c as PhysicalBone3D).global_position)
		elif c != null and c.has_method("apply_damage"):
			c.apply_damage(d, shooter, pos, dir, {"type": "bullet"})
			# thin / light things do not stop a bullet
			if c is Prop and (c as Prop).mass < 30.0:
				go_through = true
			if c is Node and (c as Node).is_in_group(&"glass"):
				go_through = true
				surf = &"glass"
		if Game.fx:
			Game.fx.impact(pos, nrm, surf, not pellet or randf() < 0.4)
		if not go_through:
			break
		if c is CollisionObject3D:
			exclude.append((c as CollisionObject3D).get_rid())
		remaining -= start.distance_to(pos)
		start = pos + dir * 0.05
		if remaining < 1.0:
			break
	# water surface splash
	if from.y > Terrain.SEA and end_point.y < Terrain.SEA and absf(dir.y) > 0.0001:
		var t := (Terrain.SEA - from.y) / dir.y
		var wp := from + dir * t
		if t > 0.0 and Terrain.is_water(wp.x, wp.z) and Game.fx:
			Game.fx.impact(wp, Vector3.UP, &"water")
	if Game.fx and (not pellet or randf() < 0.35):
		Game.fx.tracer(from, end_point)
	return last
