class_name Weapons
## Shared weapon logic for the player and every armed NPC: hitscan, pellets, projectiles, melee, impacts.

const MASK := 1 | 2 | 4 | 8 | 32


static func make_model(wid: String, mods: Dictionary = {}, tint: Color = Color(0, 0, 0, 0)) -> Node3D:
	## Instantiates the Blender-authored weapon and toggles attachment meshes.
	var d: Dictionary = Defs.WEAPONS[wid]
	var mn: String = d.get("model", "")
	if mn == "":
		return null
	var n := Assets.sub("weapons/weapons", mn, mn + "_")
	for c in n.get_children():
		var cn := String(c.name)
		if cn.begins_with("Att_"):
			var on := false
			for m in mods.keys():
				if Defs.WEAPON_MODS.has(m) and Defs.WEAPON_MODS[m].node == cn:
					on = true
			(c as Node3D).visible = on
			if cn == "Att_ExtMag" and on and n.has_node("Mag") and wid in ["autoshotgun"]:
				(n.get_node("Mag") as Node3D).visible = false
		if tint.a > 0.01 and c is MeshInstance3D:
			var mi := c as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(i)
				if sm and sm.resource_name in ["GunMetal", "GunPolymer", "Olive", "Steel"]:
					mi.set_surface_override_material(i, Assets.color_mat(tint, 0.45, 0.6))
	return n


static func muzzle_of(model: Node3D, suppressed: bool = false) -> Vector3:
	if model == null:
		return Vector3.ZERO
	var nm := "Muzzle_S" if suppressed and model.has_node("Muzzle_S") else "Muzzle"
	if model.has_node(nm):
		return (model.get_node(nm) as Node3D).global_position
	return model.global_position


static func surface_of(col: Object, pos: Vector3) -> String:
	if col is Vehicle:
		return "metal"
	if col is CharacterBody3D:
		return "flesh"
	if col is RigidBody3D:
		return "metal"
	if col is Node and (col as Node).get_parent() != null and String((col as Node).get_parent().name) in ["terrain", "hill", "outskirts"]:
		return "dirt" if pos.y > G.WATER_LEVEL else "water"
	return "concrete"


static func fire(shooter: Node, wid: String, origin: Vector3, dir: Vector3, opts: Dictionary = {}) -> Dictionary:
	## One trigger pull. opts: mods, spread_mul, dmg_mul, muzzle (Vector3), exclude (Array[RID]).
	var d: Dictionary = Defs.WEAPONS[wid]
	var mods: Dictionary = opts.get("mods", {})
	var suppressed: bool = mods.has("suppressor")
	var muzzle: Vector3 = opts.get("muzzle", origin)
	var is_player := G.is_player(shooter)
	var result := {"hit": false, "pos": origin + dir * 50.0, "collider": null, "kills": 0}
	var loud: float = float(d.get("noise", 80.0)) * (0.14 if suppressed else 1.0)
	G.make_noise(origin, loud, "gunshot", shooter)
	if is_player:
		G.report_crime("gunfire", origin, 1.1 if not suppressed else 0.25, shooter)
	if G.fx and not suppressed:
		G.fx.muzzle(muzzle, dir, 1.0 if d.type != "pistol" else 0.7)
	Sfx.play(d.get("snd", "shot_pistol") if not suppressed else "shot_silenced", origin, 0.0, randf_range(0.96, 1.05))
	if d.has("projectile"):
		var p := Projectile.new()
		p.setup(String(d.projectile), shooter, muzzle if muzzle != origin else origin, dir, d)
		G.main.add_child(p)
		p.global_position = muzzle if muzzle != origin else origin + dir * 0.8
		return result
	var pellets: int = int(d.get("pellets", 1))
	var spread := deg_to_rad(float(d.spread)) * float(opts.get("spread_mul", 1.0))
	if mods.has("grip"):
		spread *= 0.85
	var dmg: float = float(d.dmg) * float(opts.get("dmg_mul", 1.0)) * (0.95 if suppressed else 1.0)
	var excl: Array = opts.get("exclude", [])
	for i in pellets:
		var dd := dir
		if spread > 0.0001:
			var ax := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
			dd = dir.rotated(ax, randf() * spread).rotated(dir, randf() * TAU).normalized()
		var to := origin + dd * float(d.range)
		var hit := G.ray(origin, to, MASK, excl)
		var end := to
		if not hit.is_empty():
			end = hit.position
			var col: Object = hit.collider
			result.hit = true
			result.pos = end
			result.collider = col
			var surf := surface_of(col, end)
			var falloff := clampf(1.3 - origin.distance_to(end) / float(d.range), 0.35, 1.0)
			if col.has_method("take_damage"):
				var mult := 1.0
				if col.has_method("is_head_hit") and col.is_head_hit(end):
					mult = 2.6
				var was_alive: bool = (not col.get("dead")) if col.get("dead") != null else true
				col.take_damage(dmg * mult * falloff, shooter, end, "bullet")
				if was_alive and col.get("dead") == true:
					result.kills += 1
			elif col is RigidBody3D:
				(col as RigidBody3D).apply_impulse(dd * dmg * 0.6, end - (col as RigidBody3D).global_position)
			elif col is StaticBody3D and (col as Node).has_meta("props"):
				_hit_prop(col as StaticBody3D, int(hit.shape), dd, end, shooter)
			if G.fx:
				G.fx.impact(end, hit.normal, surf, i < 3)
		if origin.y > G.WATER_LEVEL and end.y < G.WATER_LEVEL and G.fx:
			var tt := (origin.y - G.WATER_LEVEL) / maxf(origin.y - end.y, 0.001)
			G.fx.splash(origin.lerp(end, tt), 0.5)
		if G.fx and (i == 0 or pellets <= 3):
			G.fx.tracer(muzzle, end)
	return result


static func _hit_prop(sb: StaticBody3D, shape_idx: int, dir: Vector3, pos: Vector3, shooter: Node) -> void:
	var sn := sb.shape_owner_get_owner(sb.shape_find_owner(shape_idx)) as Node
	if sn == null or not sn.has_meta("prop"):
		return
	var info: Dictionary = sn.get_meta("prop")
	var nm: String = info.name
	if nm == "prop_barrel_explosive":
		G.world.knock_prop(sn, dir * 30.0 + Vector3(0, 60, 0), pos)
		if G.fx:
			G.fx.explosion(pos, 1.0)
		G.damage_radius(pos, 6.5, 240.0, shooter)
	elif nm in ["prop_cone", "prop_bin", "prop_barrel", "prop_crate", "prop_boxes", "prop_trash_bags", "prop_newsbox", "prop_pallet", "prop_barrier_plastic", "prop_hydrant"]:
		G.world.knock_prop(sn, dir * 60.0 + Vector3(0, 20, 0), pos)


static func melee(shooter: Node3D, wid: String, origin: Vector3, dir: Vector3, heavy: bool = false, dmg_mul: float = 1.0) -> Object:
	var d: Dictionary = Defs.WEAPONS[wid]
	var reach: float = float(d.range)
	var shape := SphereShape3D.new()
	shape.radius = 0.75
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), origin + dir * (reach * 0.55))
	q.collision_mask = 2 | 4 | 8 | 32
	q.exclude = [shooter.get_rid()] if shooter is CollisionObject3D else []
	var best: Object = null
	var bd := 99.0
	for r in G.main.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var c: Object = r.collider
		if c == shooter or c == null:
			continue
		var cd: float = (c as Node3D).global_position.distance_to(origin)
		if cd < bd:
			bd = cd
			best = c
	if best == null:
		Sfx.play("swing", origin, -6.0, randf_range(0.9, 1.2))
		return null
	var dmg: float = float(d.dmg) * dmg_mul * (1.7 if heavy else 1.0)
	var hp := (best as Node3D).global_position + Vector3(0, 1.0, 0)
	if best.has_method("take_damage"):
		best.take_damage(dmg, shooter, hp, "melee")
	if best.has_method("knockdown") and (heavy or (best.get("health") != null and float(best.get("health")) < 22.0)):
		best.knockdown(dir * 3.2 + Vector3(0, 1.6, 0))
	if best is RigidBody3D:
		(best as RigidBody3D).apply_central_impulse(dir * dmg * 2.0)
	Sfx.play("punch" if wid == "fists" else "whack", origin, 0.0, randf_range(0.9, 1.15))
	if G.fx:
		G.fx.dust(hp, 2, Color(0.9, 0.9, 0.9, 0.5), 0.25, 0.4)
	G.make_noise(origin, 9.0, "fight", shooter)
	return best
