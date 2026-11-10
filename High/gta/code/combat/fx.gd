extends Node
## Pooled low-poly VFX: muzzle flashes, tracers, impacts, decals, smoke/fire emitters, explosions (autoload "Fx").

const POOL := 10
var _pools: Dictionary = {}
var _idx: Dictionary = {}
var _tracers: Array[MeshInstance3D] = []
var _tracer_i := 0
var _flashes: Array = []
var _flash_i := 0
var _decals: Array[Decal] = []
var _decal_i := 0
var _decal_tex: Texture2D
var _puff_mesh: Mesh
var _box_mesh: Mesh
var _fires: Array = []
var _lights: Array[OmniLight3D] = []
var _light_i := 0
var _shrink: Curve
var _grow: Curve
var _fade: Gradient
var root: Node3D


func _ready() -> void:
	_shrink = Curve.new()
	_shrink.add_point(Vector2(0, 1))
	_shrink.add_point(Vector2(1, 0))
	_grow = Curve.new()
	_grow.add_point(Vector2(0, 0.35))
	_grow.add_point(Vector2(0.4, 1.0))
	_grow.add_point(Vector2(1, 1.3))
	_fade = Gradient.new()
	_fade.set_color(0, Color(1, 1, 1, 1))
	_fade.set_color(1, Color(1, 1, 1, 0))
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.roughness = 1.0
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	sm.material = pm
	_puff_mesh = sm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.06, 0.16)
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = bmat
	_box_mesh = bm
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.02, 0.02, 0.95))
	g.set_color(1, Color(0.02, 0.02, 0.02, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.9, 0.5)
	gt.width = 32
	gt.height = 32
	_decal_tex = gt


func attach(world: Node3D) -> void:
	## Called by the world once it exists; all pooled nodes live under it.
	root = Node3D.new()
	root.name = "FxRoot"
	world.add_child(root)
	_pools.clear()
	_tracers.clear()
	_flashes.clear()
	_decals.clear()
	_lights.clear()
	_fires.clear()
	_pool("spark", POOL, func(): return _cpu(10, 0.45, _box_mesh, 5.0, 11.0, 40.0, Vector3(0, -14, 0), 0.6, 1.2, true))
	_pool("dust", POOL, func(): return _cpu(7, 0.9, _puff_mesh, 0.6, 2.2, 60.0, Vector3(0, 0.6, 0), 0.25, 0.6, true, true))
	_pool("blood", 6, func(): return _cpu(8, 0.5, _puff_mesh, 1.0, 3.5, 50.0, Vector3(0, -9, 0), 0.06, 0.16, true))
	_pool("splash", 6, func(): return _cpu(16, 0.8, _puff_mesh, 3.0, 7.0, 35.0, Vector3(0, -12, 0), 0.15, 0.4, true))
	_pool("boom", 5, func(): return _cpu(26, 0.9, _puff_mesh, 3.0, 12.0, 180.0, Vector3(0, 2.0, 0), 0.9, 2.4, true, true))
	_pool("boomsmoke", 5, func(): return _cpu(18, 3.2, _puff_mesh, 1.0, 4.5, 180.0, Vector3(0, 1.6, 0), 1.2, 3.0, true, true))
	_pool("debris", 5, func(): return _cpu(22, 1.6, _box_mesh, 6.0, 18.0, 180.0, Vector3(0, -16, 0), 1.5, 4.0, true))
	for i in range(18):
		var mi := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.025, 0.025, 1.0)
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.albedo_color = Color(1.0, 0.9, 0.55, 0.9)
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tb.material = tm
		mi.mesh = tb
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		_tracers.append(mi)
	for i in range(6):
		var f := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.11
		fm.height = 0.34
		fm.radial_segments = 5
		fm.rings = 2
		var fmat := StandardMaterial3D.new()
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fmat.albedo_color = Color(1.0, 0.85, 0.4)
		fm.material = fmat
		f.mesh = fm
		f.visible = false
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(f)
		_flashes.append([f, 0.0])
	for i in range(36):
		var d := Decal.new()
		d.texture_albedo = _decal_tex
		d.size = Vector3(0.16, 0.3, 0.16)
		d.visible = false
		d.cull_mask = 1
		d.distance_fade_enabled = true
		d.distance_fade_begin = 35.0
		d.distance_fade_length = 10.0
		root.add_child(d)
		_decals.append(d)
	for i in range(5):
		var l := OmniLight3D.new()
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.omni_range = 9.0
		root.add_child(l)
		_lights.append(l)


func _pool(kind: String, count: int, maker: Callable) -> void:
	var arr := []
	for i in range(count):
		var p: CPUParticles3D = maker.call()
		root.add_child(p)
		arr.append(p)
	_pools[kind] = arr
	_idx[kind] = 0


func _cpu(amount: int, life: float, mesh: Mesh, v0: float, v1: float, spread: float, grav: Vector3, s0: float, s1: float, one_shot: bool, grow: bool = false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.92 if one_shot else 0.0
	p.mesh = mesh
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.gravity = grav
	p.scale_amount_min = s0
	p.scale_amount_max = s1
	p.scale_amount_curve = _grow if grow else _shrink
	p.color_ramp = _fade
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.damping_min = 1.0
	p.damping_max = 2.0
	return p


func _emit(kind: String, pos: Vector3, dir: Vector3 = Vector3.UP, color: Color = Color.WHITE, scale: float = 1.0) -> void:
	if root == null or not _pools.has(kind):
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(pos) > 140.0:
		return
	var arr: Array = _pools[kind]
	var p: CPUParticles3D = arr[_idx[kind]]
	_idx[kind] = (_idx[kind] + 1) % arr.size()
	p.global_position = pos
	p.direction = dir
	p.color = color
	p.scale = Vector3.ONE * scale
	p.restart()
	p.emitting = true


func _process(delta: float) -> void:
	for f in _flashes:
		if f[1] > 0.0:
			f[1] -= delta
			if f[1] <= 0.0:
				f[0].visible = false
	for l in _lights:
		if l.light_energy > 0.0:
			l.light_energy = maxf(0.0, l.light_energy - delta * 40.0)
	for t in _tracers:
		if t.visible:
			var m: StandardMaterial3D = t.mesh.material
			m.albedo_color.a -= delta * 9.0
			if m.albedo_color.a <= 0.0:
				t.visible = false


func light_flash(pos: Vector3, color: Color, energy: float, rng_: float = 9.0) -> void:
	if root == null:
		return
	var l := _lights[_light_i]
	_light_i = (_light_i + 1) % _lights.size()
	l.global_position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_


func muzzle(pos: Vector3, dir: Vector3, big: bool = false) -> void:
	if root == null:
		return
	var f = _flashes[_flash_i]
	_flash_i = (_flash_i + 1) % _flashes.size()
	var mi: MeshInstance3D = f[0]
	mi.global_position = pos + dir * 0.14
	if absf(dir.dot(Vector3.UP)) < 0.98:
		mi.look_at(pos + dir, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	mi.scale = Vector3.ONE * (1.8 if big else 1.0) * randf_range(0.8, 1.2)
	mi.visible = true
	f[1] = 0.045
	light_flash(pos + dir * 0.3, Color(1.0, 0.8, 0.45), 2.5, 7.0)


func tracer(from: Vector3, to: Vector3) -> void:
	if root == null or from.distance_to(to) < 2.0:
		return
	var t := _tracers[_tracer_i]
	_tracer_i = (_tracer_i + 1) % _tracers.size()
	var mid := (from + to) * 0.5
	var d := to - from
	t.global_position = mid
	if absf(d.normalized().dot(Vector3.UP)) < 0.99:
		t.look_at(to, Vector3.UP)
	t.scale = Vector3(1, 1, d.length())
	(t.mesh.material as StandardMaterial3D).albedo_color.a = 0.85
	t.visible = true


func impact(pos: Vector3, normal: Vector3, surface: String = "concrete") -> void:
	match surface:
		"metal":
			_emit("spark", pos, normal, Color(1.0, 0.8, 0.4))
			Sfx.play3d("impact_metal", pos, -4.0, randf_range(0.85, 1.2), 45.0)
		"flesh":
			_emit("blood", pos, normal, Color(0.6, 0.08, 0.08))
			Sfx.play3d("impact_flesh", pos, -3.0, randf_range(0.9, 1.1), 40.0)
		"glass":
			_emit("spark", pos, normal, Color(0.8, 0.95, 1.0))
			Sfx.play3d("glass_break", pos, -6.0, randf_range(0.9, 1.2), 50.0)
		"water":
			splash(pos, 0.4)
		"dirt":
			_emit("dust", pos, normal, Color(0.55, 0.45, 0.3, 0.8), 0.7)
			Sfx.play3d("impact_concrete", pos, -8.0, 0.8, 40.0)
		_:
			_emit("dust", pos, normal, Color(0.75, 0.73, 0.7, 0.8), 0.6)
			_emit("spark", pos, normal, Color(0.7, 0.68, 0.62), 0.6)
			Sfx.play3d("impact_concrete", pos, -5.0, randf_range(0.9, 1.15), 45.0)
	if surface == "concrete" or surface == "metal" or surface == "dirt":
		decal(pos, normal)


func decal(pos: Vector3, normal: Vector3) -> void:
	if root == null:
		return
	var d := _decals[_decal_i]
	_decal_i = (_decal_i + 1) % _decals.size()
	d.global_position = pos
	var up := normal.normalized()
	var x := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(up).normalized()
	d.global_transform = Transform3D(Basis(x, up, z), pos)
	d.visible = true


func sparks(pos: Vector3, _n: int = 8, color: Color = Color(1.0, 0.8, 0.4)) -> void:
	_emit("spark", pos, Vector3.UP, color)


func dust(pos: Vector3, size: float = 1.0, color: Color = Color(0.7, 0.66, 0.58, 0.6)) -> void:
	_emit("dust", pos, Vector3.UP, color, size)


func blood(pos: Vector3, dir: Vector3 = Vector3.UP) -> void:
	_emit("blood", pos, dir, Color(0.6, 0.08, 0.08))


func splash(pos: Vector3, size: float = 1.0) -> void:
	_emit("splash", pos, Vector3.UP, Color(0.85, 0.95, 1.0, 0.8), size)


func make_smoke_emitter(color: Color, scale: float = 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 2.2
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 14.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0, 1.2, 0)
	pm.scale_min = 0.35 * scale
	pm.scale_max = 0.9 * scale
	var ct := CurveTexture.new()
	ct.curve = _grow
	pm.scale_curve = ct
	var grt := GradientTexture1D.new()
	grt.gradient = _fade
	pm.color_ramp = grt
	pm.color = color
	p.process_material = pm
	p.draw_pass_1 = _puff_mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 12, 8))
	return p


func make_fire_emitter(scale: float = 1.0) -> GPUParticles3D:
	var p := make_smoke_emitter(Color(1.0, 0.55, 0.12, 0.95), scale * 0.8)
	p.amount = 12
	p.lifetime = 0.7
	var pm: ParticleProcessMaterial = p.process_material
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0, 3.0, 0)
	var fm := SphereMesh.new()
	fm.radius = 0.5
	fm.height = 1.0
	fm.radial_segments = 5
	fm.rings = 2
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.material = m
	p.draw_pass_1 = fm
	return p


func fire_patch(pos: Vector3, duration: float = 9.0, radius: float = 2.6, attacker = null) -> void:
	## Burning ground area (fire bottles, wrecks). Bounded to 6 simultaneous patches.
	if root == null:
		return
	if _fires.size() >= 6:
		var old = _fires.pop_front()
		if is_instance_valid(old[0]):
			old[0].queue_free()
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = pos
	for i in range(3):
		var f := make_fire_emitter(1.4)
		f.position = Vector3(randf_range(-1, 1), 0.1, randf_range(-1, 1)) * radius * 0.5
		n.add_child(f)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 3.0
	l.omni_range = 9.0
	l.position.y = 1.0
	l.shadow_enabled = false
	n.add_child(l)
	var au := Sfx.loop3d(n, "fire_loop", 40.0, -4.0)
	au.play()
	_fires.append([n, duration, radius, attacker, 0.0])


func _physics_process(delta: float) -> void:
	var i := 0
	while i < _fires.size():
		var f = _fires[i]
		if not is_instance_valid(f[0]):
			_fires.remove_at(i)
			continue
		f[1] -= delta
		f[4] -= delta
		if f[4] <= 0.0:
			f[4] = 0.4
			var p: Vector3 = f[0].global_position
			for npc in Game.npcs:
				if is_instance_valid(npc) and npc.global_position.distance_to(p) < f[2]:
					npc.damage(9.0, p, f[3], "fire")
			if Game.player and Game.player.global_position.distance_to(p) < f[2] and not Game.player.in_vehicle():
				Game.player.damage(6.0, p, null, "fire")
			for v in Game.vehicles:
				if is_instance_valid(v) and v.global_position.distance_to(p) < f[2] + 1.5:
					v.damage(22.0, Vector3.ZERO, f[3])
		if f[1] <= 0.0:
			f[0].queue_free()
			_fires.remove_at(i)
			continue
		i += 1


func explosion(pos: Vector3, radius: float = 8.0, dmg: float = 200.0, attacker = null, source = null) -> void:
	_emit("boom", pos, Vector3.UP, Color(1.0, 0.62, 0.15), radius / 8.0)
	_emit("boomsmoke", pos + Vector3.UP * 0.5, Vector3.UP, Color(0.1, 0.1, 0.1, 0.85), radius / 8.0)
	_emit("debris", pos, Vector3.UP, Color(0.2, 0.2, 0.2))
	light_flash(pos + Vector3.UP, Color(1.0, 0.7, 0.3), 30.0, radius * 3.0)
	Sfx.play3d("explosion", pos, 4.0, randf_range(0.85, 1.05), 320.0)
	if Game.cam:
		var d: float = Game.cam.global_position.distance_to(pos)
		Game.cam.shake(clampf(1.4 - d / 45.0, 0.0, 1.2))
	Game.noise(pos, 140.0, "explosion")
	if attacker != null and attacker == Game.player:
		Wanted.crime("explosion", pos)
	if City.terrain_height(pos.x, pos.z) < Game.WATER_Y and pos.y < Game.WATER_Y + 1.5:
		splash(Vector3(pos.x, Game.WATER_Y, pos.z), 3.0)
	for v in Game.vehicles.duplicate():
		if not is_instance_valid(v) or v == source:
			continue
		var dd: float = v.global_position.distance_to(pos)
		if dd < radius + 2.0:
			var k := clampf(1.0 - dd / (radius + 2.0), 0.0, 1.0)
			var dir: Vector3 = (v.global_position - pos + Vector3.UP * 1.5).normalized()
			v.apply_impulse(dir * v.mass * 9.0 * k, Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5)))
			v.sleeping = false
			v.parked = false
			v.freeze = false
			v.damage(dmg * 3.2 * k, Vector3.ZERO, attacker)
	for n in Game.npcs.duplicate():
		if not is_instance_valid(n):
			continue
		var dn: float = n.global_position.distance_to(pos)
		if dn < radius:
			var kn := clampf(1.0 - dn / radius, 0.1, 1.0)
			n.damage(dmg * kn, pos, attacker, "explosion")
			if is_instance_valid(n):
				n.knockdown((n.global_position - pos + Vector3.UP * 2.0).normalized() * 9.0 * kn, attacker)
	var pl = Game.player
	if pl and is_instance_valid(pl):
		var dp: float = pl.global_position.distance_to(pos)
		if dp < radius:
			var kp := clampf(1.0 - dp / radius, 0.1, 1.0)
			if pl.in_vehicle():
				pass
			else:
				pl.damage(dmg * 0.6 * kp, pos, attacker, "explosion")
				pl.knockdown((pl.global_position - pos + Vector3.UP * 2.0).normalized() * 8.0 * kp)
	if Game.world and Game.world.props:
		Game.world.props.blast(pos, radius, attacker)
