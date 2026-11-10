class_name FX
extends Node3D
# Pooled visual effects (particles, tracers, muzzle flashes, decals, lights) and projectiles.

var pools: Dictionary = {}
var idx: Dictionary = {}
var tracers: Array = []
var tracer_i := 0
var flashes: Array = []
var flash_i := 0
var lights: Array = []
var light_i := 0
var decals: Array = []
var decal_i := 0
var rockets: Array = []
var pmat: StandardMaterial3D
var pmat_glow: StandardMaterial3D
var quad: QuadMesh
var hole_tex: ImageTexture
var scorch_tex: ImageTexture
var _impact_snd_t := 0.0
var _dust_t := 0.0


func _ready() -> void:
	quad = QuadMesh.new()
	quad.size = Vector2(1, 1)
	pmat = StandardMaterial3D.new()
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pmat.vertex_color_use_as_albedo = true
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	pmat_glow = pmat.duplicate()
	pmat_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hole_tex = _radial_tex(Color(0.03, 0.03, 0.03, 1.0), 0.5)
	scorch_tex = _radial_tex(Color(0.02, 0.02, 0.02, 0.9), 1.0)
	_pool("spark", 8, _mk(14, 0.35, Color(1, 0.85, 0.4), Color(1, 0.4, 0.1, 0), 7.0, 50.0, -14.0, 0.07, true, true))
	_pool("dust", 8, _mk(10, 0.6, Color(0.7, 0.68, 0.62, 0.8), Color(0.7, 0.68, 0.62, 0), 2.2, 40.0, -2.0, 0.28, true, false))
	_pool("blood", 6, _mk(8, 0.4, Color(0.6, 0.02, 0.02), Color(0.5, 0.02, 0.02, 0), 2.5, 60.0, -9.0, 0.11, true, false))
	_pool("debris", 5, _mk(18, 0.9, Color(0.5, 0.4, 0.3), Color(0.4, 0.3, 0.2, 0), 6.0, 80.0, -16.0, 0.16, true, false))
	_pool("splash", 6, _mk(20, 0.7, Color(0.85, 0.93, 1.0, 0.9), Color(0.8, 0.9, 1.0, 0), 5.0, 35.0, -12.0, 0.22, true, false))
	_pool("boom_fire", 4, _mk(36, 0.7, Color(1, 0.8, 0.3), Color(0.9, 0.2, 0.05, 0), 9.0, 180.0, 2.0, 1.7, true, true))
	_pool("boom_smoke", 4, _mk(26, 2.6, Color(0.14, 0.13, 0.12, 0.9), Color(0.25, 0.25, 0.25, 0), 4.5, 180.0, 1.5, 2.6, true, false))
	_pool("tire", 6, _mk(6, 0.8, Color(0.85, 0.85, 0.85, 0.5), Color(0.9, 0.9, 0.9, 0), 0.8, 60.0, 0.6, 0.6, true, false))
	var tm := BoxMesh.new()
	tm.size = Vector3(0.025, 0.025, 1.0)
	var tmat := G.flat_mat(Color(1, 0.9, 0.5), 0.5, 0.0, 3.0)
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 14:
		var mi := MeshInstance3D.new()
		mi.mesh = tm
		mi.material_override = tmat
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		tracers.append([mi, 0.0])
	for i in 6:
		var f := G.model("vfx/vfx_muzzle")
		f.visible = false
		add_child(f)
		flashes.append([f, 0.0])
	for i in 5:
		var l := OmniLight3D.new()
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		lights.append([l, 0.0, 1.0])
	for i in 36:
		var d := Decal.new()
		d.visible = false
		d.texture_albedo = hole_tex
		d.size = Vector3(0.22, 0.3, 0.22)
		d.cull_mask = 1
		add_child(d)
		decals.append(d)


func _radial_tex(c: Color, soft: float) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
			var a: float = clamp((1.0 - d) / max(soft, 0.05), 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * a))
	return ImageTexture.create_from_image(img)


func _mk(amount: int, life: float, c0: Color, c1: Color, vel: float, spread: float, grav: float, size: float, oneshot: bool, glow: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = oneshot
	p.explosiveness = 0.95 if oneshot else 0.0
	p.emitting = false
	p.mesh = quad
	p.material_override = pmat_glow if glow else pmat
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = vel * 0.5
	p.initial_velocity_max = vel
	p.gravity = Vector3(0, grav, 0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _pool(pname: String, n: int, template: CPUParticles3D) -> void:
	pools[pname] = []
	idx[pname] = 0
	for i in n:
		var e: CPUParticles3D = template if i == 0 else template.duplicate()
		add_child(e)
		pools[pname].append(e)


func burst(pname: String, pos: Vector3, dir := Vector3.UP) -> void:
	if G.cam and G.cam.global_position.distance_squared_to(pos) > 200.0 * 200.0:
		return
	var e: CPUParticles3D = pools[pname][idx[pname]]
	idx[pname] = (idx[pname] + 1) % pools[pname].size()
	e.global_position = pos
	e.direction = dir
	e.restart()
	e.emitting = true


func make_smoke() -> CPUParticles3D:
	var p := _mk(14, 1.8, Color(0.2, 0.2, 0.2, 0.7), Color(0.4, 0.4, 0.4, 0), 2.0, 20.0, 1.5, 1.1, false, false)
	return p


func make_fire() -> CPUParticles3D:
	var p := _mk(16, 0.7, Color(1, 0.75, 0.2, 0.9), Color(0.9, 0.2, 0.05, 0), 2.6, 25.0, 3.0, 1.0, false, true)
	return p


func light(pos: Vector3, color: Color, energy: float, rng: float, dur: float) -> void:
	var e: Array = lights[light_i]
	light_i = (light_i + 1) % lights.size()
	var l: OmniLight3D = e[0]
	l.global_position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.visible = true
	e[1] = dur
	e[2] = dur


func muzzle_flash(pos: Vector3, dir: Vector3) -> void:
	var e: Array = flashes[flash_i]
	flash_i = (flash_i + 1) % flashes.size()
	var f: Node3D = e[0]
	f.global_position = pos
	if abs(dir.y) < 0.99:
		f.look_at(pos + dir, Vector3.UP)
	f.rotate_object_local(Vector3(0, 0, 1), randf() * TAU)
	f.visible = true
	e[1] = 0.05
	light(pos + dir * 0.3, Color(1, 0.8, 0.4), 2.5, 7.0, 0.06)


func tracer(a: Vector3, b: Vector3) -> void:
	var e: Array = tracers[tracer_i]
	tracer_i = (tracer_i + 1) % tracers.size()
	var mi: MeshInstance3D = e[0]
	var d := a.distance_to(b)
	if d < 0.5:
		return
	mi.global_position = (a + b) / 2
	var dir := (b - a) / d
	mi.look_at(b, Vector3.UP if abs(dir.y) < 0.99 else Vector3.RIGHT)
	mi.scale = Vector3(1, 1, d)
	mi.visible = true
	e[1] = 0.045


func impact(pos: Vector3, normal: Vector3, target) -> void:
	if target is Humanoid:
		return
	var metal: bool = target is Vehicle or (target is Prop and target.mass > 25.0)
	burst("spark" if metal else "dust", pos + normal * 0.05, normal)
	if _impact_snd_t <= 0.0:
		_impact_snd_t = 0.06
		G.audio.play3d("impact_metal" if metal else "impact", pos, 0.6)
	if target == null:
		var d: Decal = decals[decal_i]
		decal_i = (decal_i + 1) % decals.size()
		d.texture_albedo = hole_tex
		d.size = Vector3(0.22, 0.3, 0.22)
		_orient_decal(d, pos, normal)


func _orient_decal(d: Decal, pos: Vector3, normal: Vector3) -> void:
	var y := normal.normalized()
	var x := y.cross(Vector3.FORWARD if abs(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	d.global_transform = Transform3D(Basis(x, y, z), pos)
	d.visible = true


func blood(pos: Vector3) -> void:
	burst("blood", pos)


func debris(pos: Vector3, _c: Color) -> void:
	burst("debris", pos)
	G.audio.play3d("crash", pos, 0.5, 1.4)


func splash(pos: Vector3) -> void:
	burst("splash", Vector3(pos.x, G.WATER_Y + 0.05, pos.z))
	G.audio.play3d("splash", pos, 0.7)


func explosion(pos: Vector3, radius: float) -> void:
	burst("boom_fire", pos)
	burst("boom_smoke", pos + Vector3.UP * 0.5)
	burst("debris", pos)
	light(pos + Vector3.UP, Color(1, 0.6, 0.2), 14.0, radius * 3.0, 0.5)
	G.audio.play3d("explosion", pos, 1.0, randf_range(0.9, 1.1))
	if pos.y - G.height(pos.x, pos.z) < 2.5 and pos.y > G.WATER_Y:
		var d: Decal = decals[decal_i]
		decal_i = (decal_i + 1) % decals.size()
		d.texture_albedo = scorch_tex
		d.size = Vector3(radius * 0.7, 3.0, radius * 0.7)
		_orient_decal(d, Vector3(pos.x, pos.y - 0.5, pos.z), Vector3.UP)
	if pos.y < G.WATER_Y + 1.0:
		splash(pos)


func throw_grenade(shooter, pos: Vector3, dir: Vector3, dmg: float) -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = G.L_WORLD | G.L_VEH | G.L_PROP
	rb.mass = 0.5
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.07
	cs.shape = s
	rb.add_child(cs)
	rb.add_child(G.model("weapons/wpn_grenade"))
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.9
	rb.physics_material_override = pm
	add_child(rb)
	rb.global_position = pos + dir * 0.4
	var base := Vector3.ZERO
	if shooter and shooter.vehicle != null:
		base = shooter.vehicle.linear_velocity
	rb.linear_velocity = base + dir * 17.0 + Vector3.UP * 4.5
	rb.angular_velocity = Vector3(8, 3, 5)
	G.audio.play3d("swing", pos)
	get_tree().create_timer(2.4).timeout.connect(func():
		if is_instance_valid(rb):
			var p := rb.global_position + Vector3.UP * 0.2
			rb.queue_free()
			G.explode(p, 10.0, dmg, shooter))


func launch_rocket(shooter, mpos: Vector3, origin: Vector3, dir: Vector3, dmg: float) -> void:
	var n := G.model("weapons/wpn_proj_rocket")
	add_child(n)
	var start := mpos + dir * 0.5
	# converge on the crosshair target
	var hit := G.ray(origin, origin + dir * 400.0, G.L_WORLD | G.L_VEH | G.L_CHAR | G.L_PROP, [shooter, shooter.vehicle])
	var target: Vector3 = hit.position if not hit.is_empty() else origin + dir * 400.0
	var d := (target - start).normalized()
	n.global_position = start
	n.look_at(start + d, Vector3.UP if abs(d.y) < 0.99 else Vector3.RIGHT)
	var trail := _mk(24, 0.9, Color(0.9, 0.9, 0.9, 0.7), Color(0.6, 0.6, 0.6, 0), 0.5, 30.0, 0.5, 0.6, false, false)
	n.add_child(trail)
	trail.emitting = true
	rockets.append({"n": n, "d": d, "t": 0.0, "dmg": dmg, "by": shooter})


func _physics_process(dt: float) -> void:
	for i in range(rockets.size() - 1, -1, -1):
		var r: Dictionary = rockets[i]
		var n: Node3D = r.n
		var step: Vector3 = r.d * 75.0 * dt
		var ex: Array = []
		if is_instance_valid(r.by):
			ex = [r.by, r.by.vehicle]
		var hit := G.ray(n.global_position, n.global_position + step, G.L_WORLD | G.L_VEH | G.L_CHAR | G.L_PROP, ex)
		r.t += dt
		if not hit.is_empty() or r.t > 5.0 or n.global_position.y < G.WATER_Y:
			var p: Vector3 = hit.position if not hit.is_empty() else n.global_position
			n.queue_free()
			rockets.remove_at(i)
			G.explode(p, 11.0, r.dmg, r.by if is_instance_valid(r.by) else null)
		else:
			n.global_position += step


func _process(dt: float) -> void:
	_impact_snd_t -= dt
	for e in tracers:
		if e[1] > 0.0:
			e[1] -= dt
			if e[1] <= 0.0:
				e[0].visible = false
	for e in flashes:
		if e[1] > 0.0:
			e[1] -= dt
			if e[1] <= 0.0:
				e[0].visible = false
	for e in lights:
		if e[1] > 0.0:
			e[1] -= dt
			e[0].light_energy *= 0.86
			if e[1] <= 0.0:
				e[0].visible = false
	# rotor wash dust / wake splash for the player's vehicle
	_dust_t -= dt
	if _dust_t <= 0.0 and G.player and G.player.vehicle != null:
		_dust_t = 0.18
		var v = G.player.vehicle
		if v.kind == "heli" and v.rotor > 0.7:
			var gh: float = max(G.height(v.global_position.x, v.global_position.z), G.WATER_Y)
			if v.global_position.y - gh < 9.0:
				var a := randf() * TAU
				var p := Vector3(v.global_position.x + cos(a) * 4.0, gh + 0.2, v.global_position.z + sin(a) * 4.0)
				burst("splash" if gh <= G.WATER_Y + 0.01 else "dust", p, Vector3(cos(a), 0.4, sin(a)))
		elif v.kind == "boat" and v.in_water and abs(v.fspeed) > 5.0:
			burst("splash", v.global_position + v.global_basis.z * 3.0)
		elif v.kind in ["car", "bike"] and v.grounded > 0 and (v.handbrake and abs(v.fspeed) > 6.0 or abs(v.linear_velocity.dot(v.global_basis.x)) > 5.0):
			burst("tire", v.global_position + v.global_basis.z * 1.5 + Vector3.UP * 0.2)
			G.audio.skid(0.25)
