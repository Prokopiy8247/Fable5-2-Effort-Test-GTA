extends Node3D
## FX - pooled visual effects: bullet impacts, sparks, dust, muzzle flashes, tracers, explosions, fire, smoke,
## splashes, tyre smoke, water jets, decals. One-shot GPUParticles3D bursts are recycled from small pools.

var pools := {}
var soft_tex: GradientTexture2D
var decals: Array = []
var decal_i := 0
var tracers: Array = []
var tracer_i := 0
var flashes: Array = []
var flash_i := 0
var lights: Array = []
var light_i := 0
var hole_tex: GradientTexture2D
var scorch_tex: GradientTexture2D
var skid: Array = []
var skid_i := 0
var puff_mat: StandardMaterial3D
var bright_mat: StandardMaterial3D


func _ready() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	soft_tex = GradientTexture2D.new()
	soft_tex.gradient = g
	soft_tex.fill = GradientTexture2D.FILL_RADIAL
	soft_tex.fill_from = Vector2(0.5, 0.5)
	soft_tex.fill_to = Vector2(1.0, 0.5)
	soft_tex.width = 64
	soft_tex.height = 64
	puff_mat = _billboard_mat(soft_tex, false)
	bright_mat = _billboard_mat(null, true)
	_make_pool("puff", 22, 8, 1.3, null, puff_mat, Vector3(0, 0.6, 0), 1.6, 0.4, 2.3, true)
	_make_pool("spark", 9, 16, 0.5, null, bright_mat, Vector3(0, -12, 0), 0.5, 1.0, 0.2, false)
	_make_pool("drop", 10, 12, 0.8, null, puff_mat, Vector3(0, -11, 0), 0.3, 0.7, 0.4, false)
	_make_pool("chunk", 6, 8, 2.0, Assets.mesh("props/vfx_kit", "vfx_debris_0"), null, Vector3(0, -12, 0), 0.2, 1.0, 0.5, false)
	_make_pool("shell", 6, 1, 1.0, Assets.mesh("props/vfx_kit", "vfx_shell"), null, Vector3(0, -11, 0), 0.2, 1.0, 1.0, false)
	for i in 4:
		var s := _continuous(Color(0.92, 0.92, 0.92, 0.4), 0.7, 14, 1.1, Vector3(0, 0.8, 0), 0.6)
		s.emitting = false
		add_child(s)
		skid.append({"n": s, "t": 0.0})
	hole_tex = _radial(Color(0.03, 0.03, 0.03, 0.95), Color(0.05, 0.05, 0.05, 0.0))
	scorch_tex = _radial(Color(0.02, 0.02, 0.02, 0.9), Color(0.03, 0.03, 0.03, 0.0))
	for i in 40:
		var d := Decal.new()
		d.texture_albedo = hole_tex
		d.size = Vector3(0.14, 0.3, 0.14)
		d.visible = false
		d.distance_fade_enabled = true
		d.distance_fade_begin = 40.0
		d.distance_fade_length = 15.0
		add_child(d)
		decals.append(d)
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.9, 0.55, 0.85)
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 24:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, 0.025, 1.0)
		bm.material = tm
		mi.mesh = bm
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		tracers.append(mi)
	var fm := Assets.mesh("props/vfx_kit", "vfx_muzzle")
	for i in 10:
		var f := MeshInstance3D.new()
		f.mesh = fm
		f.visible = false
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(f)
		flashes.append(f)
	for i in 8:
		var l := OmniLight3D.new()
		l.shadow_enabled = false
		l.visible = false
		l.omni_range = 9.0
		add_child(l)
		lights.append(l)


func _radial(c0: Color, c1: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	g.set_offset(0, 0.25)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _billboard_mat(tex: Texture2D, bright: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	if tex:
		m.albedo_texture = tex
	if bright:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.75, 0.35)
		m.emission_energy_multiplier = 4.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _process_mat(grav: Vector3, damp: float, s0: float, s1: float, fade: bool, spin: bool) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.gravity = grav
	pm.damping_min = damp
	pm.damping_max = damp
	pm.spread = 180.0
	var cv := Curve.new()
	cv.add_point(Vector2(0, s0))
	cv.add_point(Vector2(1, s1))
	var ct := CurveTexture.new()
	ct.curve = cv
	pm.scale_curve = ct
	if fade:
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture1D.new()
		gt.gradient = gr
		pm.color_ramp = gt
	if spin:
		pm.angular_velocity_min = -400.0
		pm.angular_velocity_max = 400.0
	return pm


func _make_pool(kind: String, count: int, amount: int, life: float, mesh: Mesh, mat: Material, grav: Vector3, damp: float, s0: float, s1: float, fade: bool) -> void:
	var nodes: Array = []
	for i in count:
		var p := GPUParticles3D.new()
		p.amount = amount
		p.lifetime = life
		p.one_shot = true
		p.explosiveness = 0.95
		p.emitting = false
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.process_material = _process_mat(grav, damp, s0, s1, fade, mesh != null)
		if mesh == null:
			var q := QuadMesh.new()
			q.size = Vector2(1, 1)
			q.material = mat
			p.draw_pass_1 = q
		else:
			p.draw_pass_1 = mesh
		add_child(p)
		nodes.append(p)
	pools[kind] = {"nodes": nodes, "i": 0}


func _burst(kind: String, pos: Vector3, ratio: float, col: Color, size: float, dir: Vector3, spread: float, v0: float, v1: float, radius: float = 0.15) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_squared_to(pos) > 190.0 * 190.0:
		return
	var pool: Dictionary = pools[kind]
	var nodes: Array = pool.nodes
	var p: GPUParticles3D = nodes[int(pool.i)]
	pool.i = (int(pool.i) + 1) % nodes.size()
	var pm: ParticleProcessMaterial = p.process_material
	pm.color = col
	pm.scale_min = size * 0.7
	pm.scale_max = size * 1.3
	pm.direction = dir if dir.length() > 0.01 else Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = v0
	pm.initial_velocity_max = v1
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	p.global_position = pos
	p.amount_ratio = clampf(ratio, 0.07, 1.0)
	p.restart()
	p.emitting = true


func _continuous(col: Color, size: float, amount: int, life: float, grav: Vector3, radius: float, s1: float = 2.4) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := _process_mat(grav, 1.0, 0.5, s1, true, false)
	pm.color = col
	pm.scale_min = size * 0.7
	pm.scale_max = size * 1.3
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = puff_mat
	p.draw_pass_1 = q
	return p


func _physics_process(delta: float) -> void:
	for s in skid:
		s.t = float(s.t) - delta
		if float(s.t) <= 0.0:
			(s.n as GPUParticles3D).emitting = false


# ------------------------------------------------------------------ public one-shots
func dust(pos: Vector3, n: int = 4, col: Color = Color(0.72, 0.68, 0.6, 0.7), size: float = 0.5, up: float = 1.0) -> void:
	_burst("puff", pos, n / 8.0, col, size, Vector3.UP, 70.0, 0.3, 0.8 + up, 0.2)


func sparks(pos: Vector3, n: int = 6) -> void:
	_burst("spark", pos, n / 16.0, Color(1.0, 0.8, 0.4), 0.07, Vector3.UP, 80.0, 2.0, 6.0, 0.05)


func splash(pos: Vector3, s: float = 1.0) -> void:
	_burst("drop", pos, clampf(s, 0.3, 1.0), Color(0.85, 0.95, 1.0, 0.85), 0.14 * s, Vector3.UP, 35.0, 2.5 * s, 5.5 * s, 0.3 * s)
	_burst("puff", pos, 0.3, Color(0.9, 0.97, 1.0, 0.55), 0.8 * s, Vector3.UP, 40.0, 0.5, 1.6, 0.3 * s)


func debris(pos: Vector3, n: int = 6, power: float = 6.0) -> void:
	_burst("chunk", pos, n / 8.0, Color(1, 1, 1), 1.0, Vector3.UP, 60.0, power * 0.5, power * 1.3, 0.2)


func shell_eject(pos: Vector3, dir: Vector3) -> void:
	_burst("shell", pos, 1.0, Color(1, 1, 1), 1.0, (dir + Vector3(0, 0.8, 0)).normalized(), 12.0, 2.0, 3.0, 0.0)


func jet(from: Vector3, dir: Vector3, power: float = 12.0) -> void:
	_burst("drop", from, 0.6, Color(0.8, 0.92, 1.0, 0.85), 0.16, (dir + Vector3(0, 0.25, 0)).normalized(), 6.0, power * 0.8, power, 0.05)


func tire_smoke(pos: Vector3, _amount: float = 1.0) -> void:
	var s: Dictionary = skid[skid_i]
	skid_i = (skid_i + 1) % skid.size()
	(s.n as GPUParticles3D).global_position = pos + Vector3(0, 0.1, 0)
	(s.n as GPUParticles3D).emitting = true
	s.t = 0.12


func impact(pos: Vector3, normal: Vector3, surface: String = "concrete", decal: bool = true) -> void:
	match surface:
		"metal":
			sparks(pos, 5)
			Sfx.play("hit_metal", pos, -6.0, randf_range(0.9, 1.2))
		"flesh":
			_burst("puff", pos, 0.3, Color(0.7, 0.05, 0.05, 0.8), 0.22, normal, 60.0, 0.3, 1.0, 0.05)
			Sfx.play("hit_flesh", pos, -4.0, randf_range(0.9, 1.1))
			decal = false
		"water":
			splash(Vector3(pos.x, G.WATER_LEVEL, pos.z), 0.5)
			decal = false
		"glass":
			_burst("drop", pos, 0.4, Color(0.8, 0.95, 1.0, 0.9), 0.07, normal, 50.0, 1.0, 3.0, 0.05)
			Sfx.play("glass", pos, -4.0, randf_range(0.9, 1.2))
			decal = false
		"dirt":
			_burst("puff", pos, 0.4, Color(0.5, 0.4, 0.28, 0.75), 0.4, normal, 45.0, 0.5, 1.6, 0.08)
		_:
			_burst("puff", pos + normal * 0.05, 0.3, Color(0.75, 0.72, 0.66, 0.7), 0.3, normal, 45.0, 0.4, 1.3, 0.05)
			Sfx.play("hit_concrete", pos, -8.0, randf_range(0.9, 1.3))
	if decal:
		var d: Decal = decals[decal_i]
		decal_i = (decal_i + 1) % decals.size()
		d.texture_albedo = hole_tex
		d.size = Vector3(0.13, 0.3, 0.13)
		d.global_position = pos
		_orient(d, normal)
		d.visible = true


func _orient(n: Node3D, normal: Vector3) -> void:
	var up := normal.normalized()
	var x := up.cross(Vector3(0.31, 0.77, 0.55)).normalized()
	n.global_transform.basis = Basis(x, up, x.cross(up))


func tracer(from: Vector3, to: Vector3) -> void:
	var m: MeshInstance3D = tracers[tracer_i]
	tracer_i = (tracer_i + 1) % tracers.size()
	var L := from.distance_to(to)
	if L < 0.5:
		return
	m.global_position = (from + to) * 0.5
	m.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.98 else Vector3.RIGHT)
	m.scale = Vector3(1, 1, L)
	m.visible = true
	get_tree().create_timer(0.055).timeout.connect(func(): m.visible = false)


func muzzle(pos: Vector3, dir: Vector3, s: float = 1.0) -> void:
	var f: MeshInstance3D = flashes[flash_i]
	flash_i = (flash_i + 1) % flashes.size()
	f.global_position = pos
	var d := dir.normalized()
	var x := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	f.global_transform.basis = Basis(x, -d, x.cross(-d)).rotated(d, randf() * TAU).scaled(Vector3(s, s, s))
	f.visible = true
	flash_light(pos + d * 0.3, Color(1.0, 0.8, 0.45), 2.5 * s, 0.05, 7.0)
	get_tree().create_timer(0.045).timeout.connect(func(): f.visible = false)


func flash_light(pos: Vector3, col: Color, energy: float, dur: float, rng: float = 10.0) -> void:
	var l: OmniLight3D = lights[light_i]
	light_i = (light_i + 1) % lights.size()
	l.global_position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.visible = true
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	tw.tween_callback(func(): l.visible = false)


func explosion(pos: Vector3, s: float = 1.0) -> void:
	flash_light(pos + Vector3(0, 1, 0), Color(1.0, 0.65, 0.25), 14.0 * s, 0.45, 26.0 * s)
	_burst("puff", pos, 1.0, Color(1.0, 0.62, 0.15, 0.95), 2.6 * s, Vector3.UP, 180.0, 2.0 * s, 7.0 * s, 0.8 * s)
	_burst("puff", pos + Vector3(0, 0.6 * s, 0), 1.0, Color(1.0, 0.85, 0.3, 0.95), 1.6 * s, Vector3.UP, 60.0, 3.0 * s, 9.0 * s, 0.5 * s)
	_burst("puff", pos + Vector3(0, 1.2 * s, 0), 1.0, Color(0.11, 0.1, 0.1, 0.85), 3.4 * s, Vector3.UP, 70.0, 1.5, 4.5, 1.2 * s)
	_burst("spark", pos, 1.0, Color(1.0, 0.8, 0.4), 0.1, Vector3.UP, 120.0, 4.0, 12.0 * s, 0.3)
	debris(pos, 8, 9.0 * s)
	var d: Decal = decals[decal_i]
	decal_i = (decal_i + 1) % decals.size()
	d.texture_albedo = scorch_tex
	d.size = Vector3(5.5 * s, 1.5, 5.5 * s)
	d.global_position = pos - Vector3(0, 0.3, 0)
	d.global_transform.basis = Basis()
	d.visible = true
	Sfx.play("explosion", pos, 6.0, randf_range(0.85, 1.05))
	if G.cam:
		var dist := pos.distance_to(G.cam.global_position)
		G.cam.shake(clampf(1.2 - dist / 60.0, 0.0, 1.0))


# ------------------------------------------------------------------ continuous emitters
func attach_smoke(parent: Node3D, local_pos: Vector3) -> Node3D:
	var e := Emitter.new()
	e.mode = "smoke"
	e.position = local_pos
	parent.add_child(e)
	e.part = _continuous(Color(0.6, 0.6, 0.6, 0.5), 0.8, 16, 1.6, Vector3(0, 1.2, 0), 0.2)
	e.add_child(e.part)
	return e


func attach_fire(parent: Node3D, local_pos: Vector3, s: float = 1.0, life: float = 10.0) -> Node3D:
	var e := Emitter.new()
	e.mode = "fire"
	e.size = s
	e.life = life
	e.position = local_pos
	parent.add_child(e)
	e.part = _continuous(Color(1.0, 0.55, 0.12, 0.9), 0.95 * s, 22, 0.8, Vector3(0, 3.2, 0), 0.4 * s, 0.4)
	e.add_child(e.part)
	var sm := _continuous(Color(0.1, 0.1, 0.1, 0.55), 1.4 * s, 10, 2.0, Vector3(0, 1.8, 0), 0.4 * s)
	sm.position = Vector3(0, 1.1 * s, 0)
	e.add_child(sm)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 3.0 * s
	l.omni_range = 9.0 * s
	l.shadow_enabled = false
	l.position = Vector3(0, 0.6, 0)
	e.add_child(l)
	e.light = l
	return e


func attach_trail(parent: Node3D) -> Node3D:
	var e := Emitter.new()
	e.mode = "trail"
	parent.add_child(e)
	e.part = _continuous(Color(0.9, 0.9, 0.9, 0.6), 0.5, 24, 0.9, Vector3(0, 0.3, 0), 0.05, 2.0)
	e.add_child(e.part)
	return e


func fire_at(pos: Vector3, s: float = 1.0, life: float = 8.0) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = pos
	var e: Emitter = attach_fire(holder, Vector3.ZERO, s, life)
	e.free_parent = true
	return e


func prop_broken(nm: String, pos: Vector3) -> void:
	if nm == "prop_hydrant":
		var holder := Node3D.new()
		add_child(holder)
		holder.global_position = pos + Vector3(0, 0.2, 0)
		var e := Emitter.new()
		e.mode = "water"
		e.life = 9.0
		e.free_parent = true
		holder.add_child(e)
		e.part = _continuous(Color(0.8, 0.92, 1.0, 0.8), 0.22, 40, 1.3, Vector3(0, -11.0, 0), 0.1, 1.2)
		var pm: ParticleProcessMaterial = e.part.process_material
		pm.spread = 7.0
		pm.initial_velocity_min = 8.0
		pm.initial_velocity_max = 11.0
		e.add_child(e.part)
		Sfx.play("splash", pos)
	elif nm in ["prop_street_lamp", "prop_traffic_light_A", "prop_traffic_light_B", "prop_utility_box", "prop_power_pole"]:
		sparks(pos + Vector3(0, 1.0, 0), 16)
		Sfx.play("hit_metal", pos, 0.0, 0.7)
	else:
		dust(pos + Vector3(0, 0.4, 0), 4)
		Sfx.play("crash", pos, -8.0, 1.4)


class Emitter:
	extends Node3D
	var mode := "smoke"
	var level := 0.5
	var size := 1.0
	var life := 9999.0
	var light: OmniLight3D
	var part: GPUParticles3D
	var free_parent := false

	func set_level(v: float) -> void:
		level = v
		if part:
			part.amount_ratio = clampf(0.25 + v * 0.75, 0.1, 1.0)
			var c := lerpf(0.75, 0.08, v)
			(part.process_material as ParticleProcessMaterial).color = Color(c, c, c, 0.55)

	func _process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			if free_parent:
				get_parent().queue_free()
			else:
				queue_free()
			return
		if light:
			light.light_energy = (2.4 + randf() * 1.6) * size
