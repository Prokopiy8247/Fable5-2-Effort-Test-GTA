extends Node
## Weapon inventory + firing logic shared by the player and armed NPCs.

const Defs := preload("res://gta/code/core/defs.gd")
const Projectile := preload("res://gta/code/weapons/projectile.gd")

var body: Node3D
var model: Node3D            # humanoid
var is_player := false
var inv := {"fists": {"clip": 0, "res": 0, "mods": [], "tint": "Factory"}}
var cur := "fists"
var cd := 0.0
var reload_t := 0.0
var bloom := 0.0
var inaccuracy := 0.0        # extra spread in degrees (NPCs)
var dmg_mult := 1.0
var infinite := false


func d() -> Dictionary:
	return Defs.WEAPONS[cur]


func has(id: String) -> bool:
	return inv.has(id)


func is_gun(id: String = "") -> bool:
	var w: Dictionary = Defs.WEAPONS[id if id != "" else cur]
	return w.has("clip") and w.cls != "thrown"


func clip_size(id: String) -> int:
	var w: Dictionary = Defs.WEAPONS[id]
	var c: int = w.get("clip", 0)
	if inv.has(id) and inv[id].mods.has("ExtMag"):
		c = int(ceil(c * 1.5))
	return c


func give(id: String, ammo := -1) -> void:
	var w: Dictionary = Defs.WEAPONS[id]
	if not inv.has(id):
		inv[id] = {"clip": 0, "res": 0, "mods": [], "tint": "Factory"}
		inv[id].clip = clip_size(id)
		if ammo < 0:
			ammo = w.get("clip", 0) * 3
	if ammo > 0:
		inv[id].res = min(w.get("max", 0), inv[id].res + ammo)


func add_mod(id: String, mod: String) -> void:
	if inv.has(id) and not inv[id].mods.has(mod):
		inv[id].mods.append(mod)
		if id == cur:
			select(id)


func select(id: String) -> void:
	if not inv.has(id):
		return
	cur = id
	reload_t = 0.0
	cd = max(cd, 0.25)
	if model:
		model.set_weapon(id, inv[id].mods, Defs.TINTS.get(inv[id].get("tint", "Factory")))
	if is_player and G.audio:
		G.audio.play("equip", -8.0)


func owned() -> Array:
	var out = []
	for id in Defs.WEAPON_ORDER:
		if inv.has(id):
			out.append(id)
	return out


func cycle(dir: int) -> void:
	var o = owned()
	var i = o.find(cur)
	select(o[posmod(i + dir, o.size())])


func update(dt: float) -> void:
	cd -= dt
	bloom = max(0.0, bloom - dt * 2.2)
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			var e: Dictionary = inv[cur]
			var need: int = clip_size(cur) - e.clip
			var take: int = need if infinite else min(need, e.res)
			e.clip += take
			if not infinite:
				e.res -= take


func reload() -> void:
	if not is_gun() or reload_t > 0.0:
		return
	var e: Dictionary = inv[cur]
	if e.clip >= clip_size(cur) or (e.res <= 0 and not infinite):
		return
	var t = 1.7
	if d().cls in ["shotgun", "heavy", "sniper"]:
		t = 2.3
	if is_player and G.skills:
		t *= lerpf(1.0, 0.65, G.skills.level("shooting"))
	reload_t = t
	if model:
		model.play("reload", t)
	if G.audio:
		G.audio.play3d("reload", body.global_position, -6.0)


func ammo_text() -> String:
	if not is_gun() and d().cls != "thrown":
		return ""
	var e: Dictionary = inv[cur]
	if d().cls == "thrown":
		return str(e.res + e.clip)
	return "%d / %d" % [e.clip, e.res]


## Fire toward a world-space target point. origin_override is used for drive-by / vehicle fire.
func try_fire(target: Vector3, exclude: Array = [], from_vehicle := false, heavy_melee := false) -> bool:
	if cd > 0.0 or reload_t > 0.0:
		return false
	var w = d()
	if w.cls == "melee":
		return _melee(w, heavy_melee)
	var e: Dictionary = inv[cur]
	if w.cls == "thrown":
		if e.clip + e.res <= 0 and not infinite:
			return false
		if e.clip > 0:
			e.clip -= 1
		elif not infinite:
			e.res -= 1
		cd = 1.0 / w.rate
		_throw(target, exclude)
		return true
	if e.clip <= 0:
		cd = 0.3
		if e.res > 0 or infinite:
			reload()
		elif is_player:
			G.audio.play("empty", -6.0)
		return false
	e.clip -= 1
	cd = 1.0 / w.rate
	var mods: Array = e.mods
	var origin: Vector3 = model.muzzle() if model and model.weapon_node and not from_vehicle else body.global_position + Vector3(0, 1.3, 0)
	if from_vehicle:
		origin = body.global_position + Vector3(0, 1.1, 0)
	var dir = (target - origin).normalized()
	var spread: float = w.get("spread", 1.0) * (1.0 + bloom) + inaccuracy
	if mods.has("Grip"):
		spread *= 0.7
	if from_vehicle:
		spread = spread * 1.8 + 1.0
	if is_player and G.skills:
		spread *= lerpf(1.15, 0.75, G.skills.level("shooting"))
		G.skills.gain("shooting", 0.0012)
	var supp = mods.has("Suppressor")
	var dmg: float = w.dmg * dmg_mult * (0.92 if supp else 1.0)
	var ex = exclude.duplicate()
	ex.append(body.get_rid())
	for p in w.get("pellets", 1):
		var sd = _spread(dir, spread)
		if w.has("proj"):
			_spawn_projectile(w.proj, origin + sd * 0.6, sd, dmg, ex)
		else:
			_hitscan(origin, sd, w.range, dmg, ex, 0)
	bloom = min(2.0, bloom + 0.22)
	if G.fx:
		G.fx.muzzle(origin + dir * 0.1, dir, supp)
	if G.audio:
		var snd = "shot_" + String(w.cls)
		if supp:
			snd = "shot_silenced"
		G.audio.play3d(snd, origin, 0.0 if is_player else -3.0, G.rng.randf_range(0.94, 1.06))
	if is_player:
		var rec: float = w.get("recoil", 1.0) * (0.7 if mods.has("Grip") else 1.0)
		if G.skills:
			rec *= lerpf(1.1, 0.7, G.skills.level("shooting"))
		G.cam.kick(rec)
	if G.wanted:
		G.wanted.gunshot(origin, w.get("noise", 80.0) * (0.25 if supp else 1.0), body)
	return true


func _spread(dir: Vector3, deg: float) -> Vector3:
	if deg <= 0.001:
		return dir
	var a = deg_to_rad(deg) * sqrt(G.rng.randf())
	var b = G.rng.randf() * TAU
	var side = dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up = side.cross(dir).normalized()
	return (dir + (side * cos(b) + up * sin(b)) * tan(a)).normalized()


func _hitscan(origin: Vector3, dir: Vector3, rng_m: float, dmg: float, ex: Array, depth: int) -> void:
	var to = origin + dir * rng_m
	var hit = G.ray(origin, to, G.L_SHOT, ex)
	var end: Vector3 = hit.position if hit else to
	# water surface
	if origin.y > G.WATER_Y and end.y < G.WATER_Y:
		var t = (origin.y - G.WATER_Y) / (origin.y - end.y)
		var wp = origin.lerp(end, t)
		if G.world.is_sea(wp.x, wp.z):
			G.fx.impact(wp, Vector3.UP, "water")
			if G.fx:
				G.fx.tracer(origin, wp)
			return
	if G.fx and depth == 0:
		G.fx.tracer(origin, end)
	if hit.is_empty():
		return
	var col: Object = hit.collider
	var tgt = find_target(col)
	var dist = origin.distance_to(end)
	var fall: float = clamp(1.0 - (dist / rng_m - 0.6) / 0.8, 0.5, 1.0)
	var surf = "concrete"
	if tgt:
		if tgt.has_method("surface"):
			surf = tgt.surface(hit.position)
		elif tgt is CharacterBody3D:
			surf = "flesh"
		elif tgt is RigidBody3D:
			surf = "metal"
		tgt.damage(dmg * fall, body, hit.position, "bullet")
	elif col is RigidBody3D:
		surf = "wood"
		col.apply_impulse(dir * 6.0, hit.position - col.global_position)
	G.fx.impact(hit.position, hit.normal, surf)
	# limited penetration through light dynamic props
	if depth == 0 and col is RigidBody3D and col.collision_layer & G.L_PROP:
		var ex2 = ex.duplicate()
		ex2.append(col.get_rid())
		_hitscan(hit.position + dir * 0.2, dir, rng_m - dist, dmg * 0.5, ex2, 1)


static func find_target(n: Object) -> Node:
	var x = n as Node
	for i in 4:
		if x == null:
			return null
		if x.has_method("damage"):
			return x
		x = x.get_parent()
	return null


func _spawn_projectile(kind: String, origin: Vector3, dir: Vector3, dmg: float, ex: Array) -> void:
	var p = RigidBody3D.new()
	p.set_script(Projectile)
	p.kind = kind
	p.dmg = dmg
	p.source = body
	G.main.add_child(p)
	p.launch(origin, dir, ex)


func _throw(target: Vector3, ex: Array) -> void:
	if model:
		model.play("throw", 0.45)
	var origin = body.global_position + Vector3(0, 1.6, 0)
	var dir = (target - origin).normalized()
	dir = (dir + Vector3.UP * 0.25).normalized()
	var e2 = ex.duplicate()
	e2.append(body.get_rid())
	_spawn_projectile("grenade", origin + dir * 0.7, dir, d().dmg, e2)


func _melee(w: Dictionary, heavy: bool) -> bool:
	cd = (1.0 / w.rate) * (1.6 if heavy else 1.0)
	if model:
		if heavy and cur == "fists":
			model.play("kick", 0.5)
		elif cur == "fists":
			model.play("punch", 0.32)
		else:
			model.play("swing", 0.45 if not heavy else 0.6)
	var fwd = -body.global_basis.z
	if model:
		fwd = -model.global_basis.z
	var center = body.global_position + Vector3(0, 1.1, 0) + fwd * (w.range * 0.55)
	var q = PhysicsShapeQueryParameters3D.new()
	var sp = SphereShape3D.new()
	sp.radius = 0.95
	q.shape = sp
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = G.L_CHAR | G.L_VEH | G.L_PROP
	q.exclude = [body.get_rid()]
	var res = body.get_world_3d().direct_space_state.intersect_shape(q, 6)
	var hit_any = false
	var dmg: float = w.dmg * dmg_mult * (1.8 if heavy else 1.0)
	if is_player and G.skills:
		dmg *= lerpf(1.0, 1.6, G.skills.level("strength"))
	for r in res:
		var tgt = find_target(r.collider)
		if tgt and tgt != body:
			var kind = "melee_heavy" if heavy or w.get("knock", false) else "melee"
			# stealth takedown from behind
			if is_player and body.get("stealth") and tgt is CharacterBody3D and tgt.has_method("is_unaware") and tgt.is_unaware():
				var tf: Vector3 = -tgt.global_basis.z
				if tf.dot(fwd) > 0.3:
					dmg = 9999.0
					kind = "takedown"
					G.notify("Stealth takedown", 1.5)
					if G.skills:
						G.skills.gain("stealth", 0.04)
			tgt.damage(dmg, body, r.collider.global_position + Vector3(0, 1.2, 0), kind)
			hit_any = true
			if is_player and G.skills:
				G.skills.gain("strength", 0.006)
		elif r.collider is RigidBody3D:
			r.collider.apply_central_impulse(fwd * 40.0 + Vector3.UP * 10.0)
			hit_any = true
	if G.audio:
		G.audio.play3d("punch" if hit_any else "whoosh", center, -4.0, G.rng.randf_range(0.9, 1.1))
	if hit_any and is_player:
		G.cam.shake(0.15)
	return true
