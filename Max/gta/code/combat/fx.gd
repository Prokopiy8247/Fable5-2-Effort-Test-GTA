class_name FX
extends Node3D
## Pooled visual effects + explosions (Game.fx). Everything is bounded: fixed pool sizes,
## small particle counts, no shadows, short lifetimes - safe for the shared GPU.

const BURSTS := {
	&"dust": {"n": 10, "life": 0.7, "size": 0.16, "vel": [1.0, 3.0], "grav": -1.5, "spread": 55.0, "col": [Color(0.72, 0.7, 0.66, 0.85), Color(0.6, 0.58, 0.55, 0.0)], "grow": 2.6},
	&"sparks": {"n": 12, "life": 0.35, "size": 0.035, "vel": [4.0, 11.0], "grav": -12.0, "spread": 50.0, "col": [Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.35, 0.05, 0.0)], "grow": 0.4, "glow": true},
	&"dirt": {"n": 10, "life": 0.6, "size": 0.12, "vel": [1.5, 4.5], "grav": -8.0, "spread": 45.0, "col": [Color(0.45, 0.34, 0.22, 0.95), Color(0.4, 0.3, 0.2, 0.0)], "grow": 1.6},
	&"flesh": {"n": 8, "life": 0.4, "size": 0.07, "vel": [1.0, 3.5], "grav": -7.0, "spread": 50.0, "col": [Color(0.75, 0.08, 0.08, 0.95), Color(0.5, 0.05, 0.05, 0.0)], "grow": 1.4},
	&"water": {"n": 14, "life": 0.6, "size": 0.09, "vel": [2.0, 5.5], "grav": -11.0, "spread": 28.0, "col": [Color(0.85, 0.95, 1.0, 0.9), Color(0.8, 0.92, 1.0, 0.0)], "grow": 1.2},
	&"glass": {"n": 12, "life": 0.6, "size": 0.05, "vel": [1.5, 5.0], "grav": -11.0, "spread": 60.0, "col": [Color(0.75, 0.9, 0.95, 0.9), Color(0.7, 0.85, 0.9, 0.0)], "grow": 0.8},
	&"wood": {"n": 8, "life": 0.5, "size": 0.07, "vel": [1.5, 4.0], "grav": -9.0, "spread": 50.0, "col": [Color(0.62, 0.45, 0.27, 1.0), Color(0.5, 0.36, 0.2, 0.0)], "grow": 1.0},
	&"fireball": {"n": 26, "life": 0.75, "size": 1.3, "vel": [1.0, 7.0], "grav": 3.0, "spread": 180.0, "col": [Color(1.0, 0.85, 0.4, 1.0), Color(0.9, 0.25, 0.03, 0.0)], "grow": 2.2, "glow": true},
	&"blast_smoke": {"n": 18, "life": 2.6, "size": 1.5, "vel": [0.8, 4.0], "grav": 1.6, "spread": 180.0, "col": [Color(0.12, 0.12, 0.12, 0.85), Color(0.3, 0.3, 0.3, 0.0)], "grow": 3.0},
	&"debris": {"n": 22, "life": 1.3, "size": 0.14, "vel": [6.0, 17.0], "grav": -14.0, "spread": 75.0, "col": [Color(0.25, 0.24, 0.22, 1.0), Color(0.2, 0.2, 0.2, 0.0)], "grow": 0.9},
	&"splash": {"n": 26, "life": 0.9, "size": 0.22, "vel": [3.0, 8.5], "grav": -11.0, "spread": 35.0, "col": [Color(0.9, 0.97, 1.0, 0.95), Color(0.8, 0.92, 1.0, 0.0)], "grow": 1.8},
	&"puff": {"n": 6, "life": 0.9, "size": 0.45, "vel": [0.3, 1.2], "grav": 0.8, "spread": 180.0, "col": [Color(0.85, 0.85, 0.85, 0.5), Color(0.8, 0.8, 0.8, 0.0)], "grow": 2.4},
}
const POOL_PER_BURST := 5
const MAX_HOLES := 56

var _bursts: Dictionary = {}       # name -> [Array[GPUParticles3D], next index]
var _flashes: Array[MeshInstance3D] = []
var _flash_i := 0
var _flash_light: OmniLight3D
var _flash_t := 0.0
var _tracers: Array[MeshInstance3D] = []
var _tracer_i := 0
var _tracer_t: Array[float] = []
var _holes: MultiMeshInstance3D
var _hole_i := 0
var _blast_lights: Array[OmniLight3D] = []
var _blast_i := 0
var _shell: GPUParticles3D
var _mat_cache: Dictionary = {}

func _ready() -> void:
	name = "FX"
	for key in BURSTS.keys():
		var list: Array[GPUParticles3D] = []
		for i in POOL_PER_BURST:
			var p := _make_burst(BURSTS[key])
			add_child(p)
			list.append(p)
		_bursts[key] = [list, 0]
	_build_flashes()
	_build_tracers()
	_build_holes()
	for i in 3:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.35)
		l.omni_range = 26.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_blast_lights.append(l)
	_shell = _make_burst({"n": 1, "life": 0.7, "size": 0.03, "vel": [2.0, 3.0], "grav": -12.0, "spread": 20.0,
		"col": [Color(0.85, 0.65, 0.25, 1.0), Color(0.85, 0.65, 0.25, 0.0)], "grow": 1.0})
	_shell.amount = 12
	_shell.one_shot = false
	_shell.emitting = false
	add_child(_shell)

func _particle_material(glow: bool) -> StandardMaterial3D:
	var key := "glow" if glow else "plain"
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(2.2, 2.2, 2.2, 1.0)
	m.albedo_texture = _soft_dot()
	_mat_cache[key] = m
	return m

func _soft_dot() -> Texture2D:
	if _mat_cache.has("dot"):
		return _mat_cache["dot"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.55, Color(1, 1, 1, 0.85))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 32
	t.height = 32
	_mat_cache["dot"] = t
	return t

func _make_burst(cfg: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = int(cfg["n"])
	p.lifetime = float(cfg["life"])
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = float(cfg["spread"])
	pm.initial_velocity_min = float(cfg["vel"][0])
	pm.initial_velocity_max = float(cfg["vel"][1])
	pm.gravity = Vector3(0, float(cfg["grav"]), 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, cfg["col"][0])
	ramp.set_color(1, cfg["col"][1])
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, float(cfg["grow"])))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * float(cfg["size"])
	q.material = _particle_material(bool(cfg.get("glow", false)))
	p.draw_pass_1 = q
	var reach := float(cfg["vel"][1]) * float(cfg["life"]) + 2.0
	p.visibility_aabb = AABB(Vector3(-reach, -reach, -reach), Vector3(reach, reach, reach) * 2.0)
	return p

func burst(kind: StringName, pos: Vector3, dir := Vector3.UP, scale := 1.0) -> void:
	if not _bursts.has(kind) or Game.is_headless:
		return
	var entry: Array = _bursts[kind]
	var list: Array[GPUParticles3D] = entry[0]
	var p := list[int(entry[1])]
	entry[1] = (int(entry[1]) + 1) % list.size()
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	# particles are emitted along local +Y, so point +Y along the requested direction
	p.global_transform = Transform3D(_basis_y(d).scaled(Vector3.ONE * scale), pos)
	p.restart()
	p.emitting = true

static func _basis_y(y_axis: Vector3) -> Basis:
	var y := y_axis.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

# ---------------------------------------------------------------- weapons
func _build_flashes() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(2.6, 1.9, 0.9, 1.0)
	mat.albedo_texture = _soft_dot()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 6:
		var mi := MeshInstance3D.new()
		var holder := ArrayMesh.new()
		for k in 3:
			var q := QuadMesh.new()
			q.size = Vector2(0.34, 0.34)
			var arr := q.get_mesh_arrays()
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var rot := Basis(Vector3.FORWARD, PI * float(k) / 3.0) * Basis(Vector3.UP, PI * 0.5 if k < 2 else 0.0)
			for v in verts.size():
				verts[v] = rot * verts[v] + Vector3(0, 0, -0.12)
			arr[Mesh.ARRAY_VERTEX] = verts
			holder.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			holder.surface_set_material(k, mat)
		mi.mesh = holder
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_flashes.append(mi)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.8, 0.45)
	_flash_light.omni_range = 9.0
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	add_child(_flash_light)

func muzzle_flash(pos: Vector3, dir: Vector3, strength := 1.0) -> void:
	if Game.is_headless:
		return
	var mi := _flashes[_flash_i]
	_flash_i = (_flash_i + 1) % _flashes.size()
	var d := dir.normalized()
	mi.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT), pos)
	mi.scale = Vector3.ONE * randf_range(0.8, 1.25) * strength
	mi.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	mi.visible = true
	mi.set_meta("t", 0.05)
	_flash_light.global_position = pos + d * 0.3
	_flash_light.light_energy = 2.6 * strength
	_flash_t = 0.06

func _build_tracers() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.6, 1.3, 0.7, 0.55)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 14:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.018, 0.018, 1.0)
		bm.material = mat
		mi.mesh = bm
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_tracers.append(mi)
		_tracer_t.append(0.0)

func tracer(from: Vector3, to: Vector3) -> void:
	if Game.is_headless:
		return
	var length := from.distance_to(to)
	if length < 3.0:
		return
	var mi := _tracers[_tracer_i]
	_tracer_t[_tracer_i] = 0.07
	_tracer_i = (_tracer_i + 1) % _tracers.size()
	var d := (to - from) / length
	var seg := minf(length * 0.6, 22.0)
	var mid := from + d * (length - seg * 0.5 - randf() * (length - seg) * 0.5)
	mi.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT), mid)
	mi.scale = Vector3(1.0, 1.0, seg)
	mi.visible = true

func _build_holes() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.11)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.03, 0.03, 0.03, 0.85)
	mat.albedo_texture = _soft_dot()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = mat
	mm.mesh = q
	mm.instance_count = MAX_HOLES
	for i in MAX_HOLES:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0, -1000, 0)))
	_holes = MultiMeshInstance3D.new()
	_holes.multimesh = mm
	_holes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holes.custom_aabb = AABB(Vector3(-2000, -200, -2000), Vector3(4000, 800, 4000))
	add_child(_holes)

func bullet_hole(pos: Vector3, normal: Vector3) -> void:
	var n := normal.normalized()
	var b := Basis.looking_at(-n, Vector3.UP if absf(n.y) < 0.98 else Vector3.RIGHT)
	_holes.multimesh.set_instance_transform(_hole_i, Transform3D(b, pos + n * 0.012))
	_hole_i = (_hole_i + 1) % MAX_HOLES

func impact(pos: Vector3, normal: Vector3, surface: StringName, with_sound := true) -> void:
	var kind := &"dust"
	var snd := &"bullet_impact_concrete"
	match surface:
		&"metal": kind = &"sparks"; snd = &"bullet_impact_metal"
		&"flesh": kind = &"flesh"; snd = &"bullet_impact_flesh"
		&"dirt", &"ground", &"sand", &"grass": kind = &"dirt"; snd = &"bullet_impact_dirt"
		&"water": kind = &"water"; snd = &"bullet_impact_water"
		&"glass": kind = &"glass"; snd = &"bullet_impact_glass"
		&"wood": kind = &"wood"; snd = &"bullet_impact_dirt"
	burst(kind, pos, normal)
	if surface == &"concrete" or surface == &"wood":
		bullet_hole(pos, normal)
	if with_sound:
		Audio.play(snd, pos, -7.0, 1.0, 0.15, 55.0)
	Events.bullet_impact.emit(pos, normal, surface)

func shell(pos: Vector3, side: Vector3) -> void:
	if Game.is_headless:
		return
	_shell.global_transform = Transform3D(_basis_y((side + Vector3.UP * 0.6).normalized()), pos)
	_shell.emit_particle(_shell.global_transform, side * 2.5 + Vector3.UP * 1.5, Color.WHITE, Color.WHITE,
		GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY)

func sparks(pos: Vector3, dir := Vector3.UP, _count := 12) -> void:
	burst(&"sparks", pos, dir)

func splash(pos: Vector3, scale := 1.0) -> void:
	burst(&"splash", pos, Vector3.UP, scale)
	Audio.play(&"splash_big" if scale > 0.8 else &"splash_small", pos, -4.0)

func puff(pos: Vector3, scale := 1.0) -> void:
	burst(&"puff", pos, Vector3.UP, scale)

# ---------------------------------------------------------------- persistent emitters
## Smoke / fire attached to a parent (burning vehicles, barrels). Caller frees the node.
func make_fire(parent: Node3D, local_pos: Vector3, scale := 1.0, with_flames := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Fire"
	parent.add_child(root)
	root.position = local_pos
	var smoke := _make_burst({"n": 14, "life": 2.4, "size": 0.9 * scale, "vel": [0.6, 1.6], "grav": 2.2, "spread": 18.0,
		"col": [Color(0.1, 0.1, 0.1, 0.75), Color(0.35, 0.35, 0.35, 0.0)], "grow": 3.2})
	smoke.one_shot = false
	smoke.explosiveness = 0.0
	smoke.emitting = true
	root.add_child(smoke)
	if with_flames:
		var flames := _make_burst({"n": 16, "life": 0.6, "size": 0.7 * scale, "vel": [1.0, 2.6], "grav": 3.0, "spread": 22.0,
			"col": [Color(1.0, 0.8, 0.3, 1.0), Color(0.9, 0.2, 0.02, 0.0)], "grow": 0.5, "glow": true})
		flames.one_shot = false
		flames.explosiveness = 0.0
		flames.emitting = true
		root.add_child(flames)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.2)
		l.light_energy = 2.2
		l.omni_range = 9.0 * scale
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 60.0
		root.add_child(l)
		var snd := Audio.make_loop(&"fire_loop", root, -6.0, 45.0)
		snd.name = "FireLoop"
	return root

func attach_trail(parent: Node3D) -> void:
	var t := _make_burst({"n": 26, "life": 0.9, "size": 0.45, "vel": [0.1, 0.6], "grav": 0.6, "spread": 180.0,
		"col": [Color(0.9, 0.9, 0.9, 0.7), Color(0.6, 0.6, 0.6, 0.0)], "grow": 2.6})
	t.one_shot = false
	t.explosiveness = 0.0
	t.emitting = true
	parent.add_child(t)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.3)
	l.light_energy = 2.0
	l.omni_range = 7.0
	l.shadow_enabled = false
	parent.add_child(l)

func water_jet(pos: Vector3, seconds: float) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var j := _make_burst({"n": 40, "life": 1.1, "size": 0.3, "vel": [9.0, 12.0], "grav": -12.0, "spread": 7.0,
		"col": [Color(0.85, 0.95, 1.0, 0.85), Color(0.8, 0.92, 1.0, 0.0)], "grow": 2.2})
	j.one_shot = false
	j.explosiveness = 0.0
	j.emitting = true
	root.add_child(j)
	var snd := Audio.make_loop(&"hydrant_spray_loop", root, -6.0, 40.0)
	snd.name = "Spray"
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(root):
			root.queue_free())
	return root

# ---------------------------------------------------------------- explosions
func explosion(pos: Vector3, radius: float, damage: float, source: Node = null) -> void:
	burst(&"fireball", pos, Vector3.UP, clampf(radius / 7.0, 0.5, 1.8))
	burst(&"blast_smoke", pos, Vector3.UP, clampf(radius / 7.0, 0.5, 1.8))
	burst(&"debris", pos + Vector3(0, 0.2, 0), Vector3.UP)
	burst(&"sparks", pos, Vector3.UP, 2.0)
	var l := _blast_lights[_blast_i]
	_blast_i = (_blast_i + 1) % _blast_lights.size()
	l.global_position = pos + Vector3(0, 1.0, 0)
	l.light_energy = 9.0
	l.visible = true
	var dist_cam := pos.distance_to(Game.player_pos())
	Audio.play(&"explosion_big" if radius > 5.0 else &"explosion_small", pos, 2.0, 1.0, 0.08, 420.0)
	if Game.cam and Game.cam.has_method("shake"):
		Game.cam.shake(clampf(1.3 - dist_cam / 60.0, 0.0, 1.0))
	if pos.y < Terrain.SEA + 1.0 and Terrain.is_water(pos.x, pos.z):
		splash(Vector3(pos.x, Terrain.SEA, pos.z), 2.0)
	# --- damage + impulses
	var shape := SphereShape3D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, pos)
	q.collision_mask = Phys.CHARACTER | Phys.VEHICLE | Phys.PROP | Phys.GLASS
	var seen := {}
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 48):
		var c: Object = hit["collider"]
		if c == null or seen.has(c) or not (c is Node3D):
			continue
		seen[c] = true
		var n3 := c as Node3D
		var centre := n3.global_position + Vector3(0, 0.8, 0)
		var to := centre - pos
		var d := maxf(to.length() - 0.6, 0.0)
		if d > radius:
			continue
		var fall := pow(clampf(1.0 - d / radius, 0.0, 1.0), 1.15)
		if not Game.ray(pos + Vector3(0, 0.35, 0), centre, Phys.WORLD).is_empty():
			fall *= 0.3
		var dir := to.normalized() if to.length() > 0.05 else Vector3.UP
		dir = (dir + Vector3(0, 0.35, 0)).normalized()
		if c.has_method("apply_damage"):
			c.apply_damage(damage * fall, source, pos, dir, {"type": "explosion", "force": 5.0 + 11.0 * fall})
		if c is RigidBody3D:
			var rb := c as RigidBody3D
			if rb is Prop:
				(rb as Prop).wake()
			rb.apply_central_impulse(dir * minf(rb.mass * 9.0, 14000.0) * fall)
	Events.explosion.emit(pos, radius, damage, source)
	Events.noise.emit(pos, 170.0, &"explosion", source)
	if source != null and is_instance_valid(source) and (source == Game.player or (source.get("is_player") == true)):
		Events.crime.emit(&"explosion", pos, {})

func _process(delta: float) -> void:
	for mi in _flashes:
		if mi.visible:
			var t := float(mi.get_meta("t", 0.0)) - delta
			mi.set_meta("t", t)
			if t <= 0.0:
				mi.visible = false
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash_light.light_energy = 0.0
	for i in _tracers.size():
		if _tracer_t[i] > 0.0:
			_tracer_t[i] -= delta
			if _tracer_t[i] <= 0.0:
				_tracers[i].visible = false
	for l in _blast_lights:
		if l.visible:
			l.light_energy = move_toward(l.light_energy, 0.0, delta * 22.0)
			if l.light_energy <= 0.01:
				l.visible = false
