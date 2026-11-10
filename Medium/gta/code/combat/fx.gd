extends Node3D
## Pooled visual effects: tracers, muzzle flashes, impacts, decals, explosions, smoke/fire emitters.

var _pools := {}
var _pi := {}
var _tracers: Array = []
var _ti := 0
var _flashes: Array = []
var _fi := 0
var _decals: Array = []
var _di := 0
var _decal_tex: Texture2D
var _scorch_tex: Texture2D
var _sphere: SphereMesh
var active_emitters := 0


func _ready() -> void:
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 6
	_sphere.rings = 3
	_mkpool("spark", 10, 14, 0.35, Color(1.0, 0.8, 0.3), 7.0, 0.05, true, 12.0)
	_mkpool("dust", 10, 10, 0.7, Color(0.7, 0.68, 0.62, 0.8), 2.2, 0.16, false, 2.0)
	_mkpool("flesh", 8, 8, 0.45, Color(0.55, 0.05, 0.05), 2.6, 0.07, false, 9.0)
	_mkpool("wood", 6, 8, 0.6, Color(0.55, 0.4, 0.25), 3.5, 0.07, false, 9.0)
	_mkpool("glass", 6, 14, 0.6, Color(0.8, 0.92, 1.0, 0.8), 4.0, 0.05, false, 10.0)
	_mkpool("water", 8, 14, 0.7, Color(0.9, 0.95, 1.0, 0.8), 4.5, 0.12, false, 9.0)
	_mkpool("puff", 14, 5, 0.9, Color(0.85, 0.85, 0.85, 0.5), 0.9, 0.5, false, -0.6)
	_mkpool("fireball", 5, 26, 0.9, Color(1.0, 0.55, 0.12), 7.0, 1.1, true, -2.0)
	_mkpool("blast_smoke", 5, 20, 2.6, Color(0.14, 0.13, 0.12, 0.9), 3.5, 1.6, false, -1.2)
	_mkpool("debris", 5, 22, 1.6, Color(0.2, 0.2, 0.2), 13.0, 0.14, false, 14.0)
	_mkpool("geyser", 3, 60, 1.6, Color(0.85, 0.93, 1.0, 0.7), 11.0, 0.22, false, 12.0)
	var tm = StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.9, 0.6, 0.75)
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 24:
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = Vector3(0.025, 0.025, 1.0)
		mi.mesh = bm
		mi.material_override = tm
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_tracers.append({"n": mi, "t": 0.0})
	for i in 6:
		var l = OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.45)
		l.omni_range = 7.0
		l.light_energy = 0.0
		add_child(l)
		var q = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 0.11
		sm.height = 0.22
		sm.radial_segments = 6
		sm.rings = 3
		q.mesh = sm
		q.material_override = G.flat_mat(Color(1.0, 0.85, 0.4), 0.5, 0.0, 6.0)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.add_child(q)
		_flashes.append({"n": l, "t": 0.0, "q": q})
	_decal_tex = _radial(Color(0.05, 0.05, 0.05, 0.9), 32)
	_scorch_tex = _radial(Color(0.04, 0.035, 0.03, 0.85), 64)
	for i in 36:
		var dn = Decal.new()
		dn.texture_albedo = _decal_tex
		dn.size = Vector3(0.16, 0.3, 0.16)
		dn.visible = false
		dn.cull_mask = 1
		add_child(dn)
		_decals.append(dn)


func _radial(col: Color, sz: int) -> Texture2D:
	var g = Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.55, Color(col.r, col.g, col.b, col.a * 0.8))
	var t = GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = sz
	t.height = sz
	return t


func _particles(amount: int, life: float, col: Color, vel: float, size: float, emissive: bool, grav: float) -> CPUParticles3D:
	var p = CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amount
	p.lifetime = life
	p.mesh = _sphere
	p.direction = Vector3.UP
	p.spread = 65.0
	p.initial_velocity_min = vel * 0.4
	p.initial_velocity_max = vel
	p.gravity = Vector3(0, -grav, 0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.3
	var cv = Curve.new()
	cv.add_point(Vector2(0, 0.6))
	cv.add_point(Vector2(0.3, 1.0))
	cv.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = cv
	var m = StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if emissive else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 3.0
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _mkpool(name: String, n: int, amount: int, life: float, col: Color, vel: float, size: float, emissive: bool, grav: float) -> void:
	var arr = []
	for i in n:
		var p = _particles(amount, life, col, vel, size, emissive, grav)
		add_child(p)
		arr.append(p)
	_pools[name] = arr
	_pi[name] = 0


func burst(name: String, pos: Vector3, normal := Vector3.UP) -> void:
	if not _pools.has(name):
		return
	var cam = get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_squared_to(pos) > 160.0 * 160.0:
		return
	var arr: Array = _pools[name]
	var p: CPUParticles3D = arr[_pi[name]]
	_pi[name] = (_pi[name] + 1) % arr.size()
	p.global_position = pos
	p.direction = normal if normal.length() > 0.5 else Vector3.UP
	p.restart()
	p.emitting = true


func tracer(a: Vector3, b: Vector3) -> void:
	var t: Dictionary = _tracers[_ti]
	_ti = (_ti + 1) % _tracers.size()
	var n: MeshInstance3D = t.n
	var d = b - a
	var len = d.length()
	if len < 1.0:
		return
	var seg: float = min(len, 28.0)
	var start = a + d.normalized() * min(len - seg, 2.0)
	n.global_position = start + d.normalized() * seg * 0.5
	n.look_at(b, Vector3.UP if abs(d.normalized().y) < 0.98 else Vector3.RIGHT)
	n.scale = Vector3(1, 1, seg)
	n.visible = true
	t.t = 0.06


func muzzle(pos: Vector3, _dir: Vector3, suppressed := false) -> void:
	if suppressed:
		return
	var f: Dictionary = _flashes[_fi]
	_fi = (_fi + 1) % _flashes.size()
	f.n.global_position = pos
	f.n.light_energy = 2.5
	f.q.visible = true
	f.t = 0.05


func impact(pos: Vector3, normal: Vector3, surf := "concrete") -> void:
	match surf:
		"metal":
			burst("spark", pos, normal)
			G.audio.play3d("metal", pos, -10.0, G.rng.randf_range(1.2, 1.8))
		"flesh":
			burst("flesh", pos, normal)
			G.audio.play3d("hit", pos, -6.0)
		"water":
			burst("water", pos, Vector3.UP)
			G.audio.play3d("splash", pos, -12.0, 1.5)
		"glass":
			burst("glass", pos, normal)
			G.audio.play3d("glass", pos, -6.0)
		"wood":
			burst("wood", pos, normal)
			G.audio.play3d("thud", pos, -10.0, 1.4)
		_:
			burst("dust", pos, normal)
			G.audio.play3d("ricochet", pos, -12.0, G.rng.randf_range(0.9, 1.4))
			decal(pos, normal, 0.16)


func decal(pos: Vector3, normal: Vector3, size := 0.16, scorch := false) -> void:
	var d: Decal = _decals[_di]
	_di = (_di + 1) % _decals.size()
	d.texture_albedo = _scorch_tex if scorch else _decal_tex
	d.size = Vector3(size, 0.5, size)
	d.global_position = pos
	if abs(normal.y) > 0.95 or normal.length() < 0.5:
		d.global_basis = Basis.IDENTITY
	else:
		d.global_basis = Basis.looking_at(normal, Vector3.UP).rotated(Basis.looking_at(normal, Vector3.UP).x, -PI / 2)
	d.visible = true


func splash(pos: Vector3, big := false) -> void:
	burst("water", Vector3(pos.x, G.WATER_Y, pos.z))
	if big:
		burst("geyser", Vector3(pos.x, G.WATER_Y, pos.z))
	G.audio.play3d("splash", pos, -3.0 if big else -9.0)


func geyser(pos: Vector3) -> void:
	for i in 10:
		get_tree().create_timer(i * 0.9).timeout.connect(func(): burst("geyser", pos))


func puff(pos: Vector3) -> void:
	burst("puff", pos)


## Persistent smoke/fire emitter parented to a node (vehicles, rockets). Caller frees it.
func make_smoke(parent: Node3D, col: Color, size: float, fire := false) -> CPUParticles3D:
	var p = _particles(14 if not fire else 18, 1.3 if not fire else 0.6, col, 2.4, size, fire, -2.2)
	p.one_shot = false
	p.explosiveness = 0.0
	p.spread = 20.0
	p.local_coords = false
	parent.add_child(p)
	p.emitting = true
	return p


func explode(pos: Vector3, radius: float, dmg: float, source = null) -> void:
	burst("fireball", pos)
	burst("blast_smoke", pos + Vector3(0, 0.6, 0))
	burst("debris", pos)
	var f: Dictionary = _flashes[_fi]
	_fi = (_fi + 1) % _flashes.size()
	f.n.global_position = pos + Vector3(0, 1, 0)
	f.n.light_energy = 14.0
	f.q.visible = false
	f.t = 0.22
	G.audio.play3d("explosion", pos, 6.0, G.rng.randf_range(0.85, 1.1))
	if pos.y < G.WATER_Y + 1.0 and G.world.is_sea(pos.x, pos.z):
		splash(pos, true)
	else:
		decal(pos + Vector3(0, 0.3, 0), Vector3.UP, radius * 0.9, true)
	if G.cam:
		var d: float = G.cam.camera.global_position.distance_to(pos)
		G.cam.shake(clamp(1.6 - d / 40.0, 0.0, 1.4))
	# damage + impulse
	var q = PhysicsShapeQueryParameters3D.new()
	var sp = SphereShape3D.new()
	sp.radius = radius
	q.shape = sp
	q.transform = Transform3D(Basis.IDENTITY, pos)
	q.collision_mask = G.L_VEH | G.L_CHAR | G.L_PROP | G.L_WORLD
	var seen = {}
	for r in get_world_3d().direct_space_state.intersect_shape(q, 40):
		var c: Object = r.collider
		if c == null or seen.has(c):
			continue
		seen[c] = true
		var cp: Vector3 = c.global_position
		var dist: float = max(0.5, cp.distance_to(pos))
		var k: float = clamp(1.0 - dist / radius, 0.05, 1.0)
		var away = (cp + Vector3(0, 0.6, 0) - pos).normalized()
		if c is RigidBody3D:
			c.sleeping = false
			if c.get("freeze"):
				if c.has_method("wake"):
					c.wake()
			c.apply_central_impulse(away * k * min(c.mass, 1500.0) * 9.0 + Vector3.UP * min(c.mass, 1500.0) * 2.5 * k)
		elif c.has_meta("knock"):
			G.world.knock(c, away * 300.0 * k)
			continue
		if c.has_method("damage"):
			c.damage(dmg * k, source, pos, "explosion")
	if G.wanted:
		G.wanted.explosion(pos, source)


func _process(dt: float) -> void:
	for t in _tracers:
		if t.t > 0.0:
			t.t -= dt
			if t.t <= 0.0:
				t.n.visible = false
	for f in _flashes:
		if f.t > 0.0:
			f.t -= dt
			if f.t <= 0.0:
				f.n.light_energy = 0.0
				f.q.visible = false
