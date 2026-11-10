extends Node3D
## Water jets of the firefighters (owned by the emergency system, child "EmergencyFx").
##
## The Fx autoload has no water-jet effect, so the emergency module ships its own, built the way
## Fx builds its effects: a small POOL of GPUParticles3D (created once, recycled), opaque faceted
## droplet meshes (a procedural flat-shaded icosahedron, ~20 tris), world-space particles with
## gravity so the stream arcs onto the fire, no transparency / no per-frame allocations.
## At the impact point it asks Fx for steam puffs (Fx.smoke_puff "steam") and an occasional splash.
##
##   var jet := fx.start_jet(owner_key)        # -> index or -1 (pool exhausted)
##   fx.aim_jet(index, from, to)               # every frame / tick while spraying
##   fx.stop_jet(index)
## The hiss reuses the synthesized "rain_loop" (no dedicated hose sound exists).

const POOL := 3
const AMOUNT := 56
const LIFETIME := 1.05
const SPEED := 13.5
const GRAVITY := 9.8
const STEAM_INTERVAL := 0.32
const SPLASH_INTERVAL := 1.6

var _jets: Array[GPUParticles3D] = []
var _owner: Array = []                     ## owner key per jet (null = free)
var _target: PackedVector3Array = PackedVector3Array()
var _steam_t: PackedFloat32Array = PackedFloat32Array()
var _splash_t: PackedFloat32Array = PackedFloat32Array()
var _hiss: Array = []                      ## AudioStreamPlayer3D per jet (may be null)
var _built: bool = false
var active_count: int = 0


func _build() -> void:
	if _built:
		return
	_built = true
	var mesh := _droplet_mesh(0.07)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.9, 1.0)
	mat.roughness = 0.15
	mat.metallic_specular = 0.8
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.5, 0.65)
	mat.emission_energy_multiplier = 0.35          # still readable at night
	mat.vertex_color_use_as_albedo = false
	mesh.surface_set_material(0, mat)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.0, -1.0)
	pm.spread = 2.6
	pm.initial_velocity_min = SPEED * 0.93
	pm.initial_velocity_max = SPEED * 1.04
	pm.gravity = Vector3(0.0, -GRAVITY, 0.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.04
	pm.scale_min = 0.55
	pm.scale_max = 1.25
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.55))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(0.85, 1.25))
	curve.add_point(Vector2(1.0, 0.2))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -180.0
	pm.angular_velocity_max = 180.0
	for i in POOL:
		var p := GPUParticles3D.new()
		p.name = "WaterJet%d" % i
		p.amount = AMOUNT
		p.lifetime = LIFETIME
		p.explosiveness = 0.0
		p.randomness = 0.2
		p.local_coords = false
		p.emitting = false
		p.process_material = pm
		p.draw_pass_1 = mesh
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-12.0, -12.0, -16.0), Vector3(24.0, 24.0, 24.0))
		p.visible = false
		add_child(p)
		_jets.append(p)
		_owner.append(null)
		_target.append(Vector3.ZERO)
		_steam_t.append(0.0)
		_splash_t.append(0.0)
		var hiss: Variant = null
		if Audio.has_method("make_loop_player") and Audio.call("get_stream", "rain_loop") != null:
			hiss = Audio.call("make_loop_player", "rain_loop", p, 28.0, "SFX")
			if hiss is AudioStreamPlayer3D:
				(hiss as AudioStreamPlayer3D).volume_db = -9.0
				(hiss as AudioStreamPlayer3D).pitch_scale = 1.6
				(hiss as AudioStreamPlayer3D).stop()
		_hiss.append(hiss)


## Flat-shaded icosahedron (20 facets) - the project's chunky low-poly particle look.
static func _droplet_mesh(r: float) -> ArrayMesh:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in f:
		var a := v[tri.x].normalized() * r
		var b := v[tri.y].normalized() * r
		var c := v[tri.z].normalized() * r
		# stretch along -Z a little: droplets streak in the direction of flight
		a.z *= 1.6
		b.z *= 1.6
		c.z *= 1.6
		var n := (b - a).cross(c - a).normalized()
		st.set_normal(n)
		st.add_vertex(a)
		st.set_normal(n)
		st.add_vertex(c)
		st.set_normal(n)
		st.add_vertex(b)
	return st.commit()


func start_jet(owner_key: Object) -> int:
	_build()
	for i in _jets.size():
		if _owner[i] == owner_key and owner_key != null:
			return i
	for i in _jets.size():
		if _owner[i] == null or not is_instance_valid(_owner[i]):
			_owner[i] = owner_key
			_jets[i].visible = true
			_jets[i].emitting = true
			_steam_t[i] = 0.0
			_splash_t[i] = 0.4
			if _hiss[i] != null and is_instance_valid(_hiss[i]):
				(_hiss[i] as AudioStreamPlayer3D).play()
			_recount()
			return i
	return -1


func stop_jet(index: int) -> void:
	if index < 0 or index >= _jets.size():
		return
	_owner[index] = null
	_jets[index].emitting = false
	if _hiss[index] != null and is_instance_valid(_hiss[index]):
		(_hiss[index] as AudioStreamPlayer3D).stop()
	_recount()


func stop_all() -> void:
	for i in _jets.size():
		stop_jet(i)


## Stops jets whose owner is gone (a firefighter freed while spraying).
func reap() -> void:
	for i in _jets.size():
		var o: Variant = _owner[i]
		if o != null and not is_instance_valid(o):
			stop_jet(i)


func is_jet_active(index: int) -> bool:
	return index >= 0 and index < _jets.size() and _owner[index] != null and _jets[index].emitting


func _recount() -> void:
	var n := 0
	for o: Variant in _owner:
		if o != null:
			n += 1
	active_count = n


## Point jet `index` from `from` (the nozzle / hand) so the arc lands on `to` (the base of the fire).
func aim_jet(index: int, from: Vector3, to: Vector3, dt: float) -> void:
	if index < 0 or index >= _jets.size() or _owner[index] == null:
		return
	var p := _jets[index]
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var d := maxf(flat.length(), 0.5)
	var h := to.y - from.y
	# launch angle of the low ballistic arc at SPEED (fallback 35 deg when out of reach)
	var v2 := SPEED * SPEED
	var disc := v2 * v2 - GRAVITY * (GRAVITY * d * d + 2.0 * h * v2)
	var ang := deg_to_rad(35.0)
	if disc >= 0.0:
		ang = atan((v2 - sqrt(disc)) / (GRAVITY * d))
	var dir2 := flat / d
	var dir := Vector3(dir2.x * cos(ang), sin(ang), dir2.y * cos(ang)).normalized()
	p.global_position = from
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	p.global_basis = Basis.looking_at(dir, up)
	_target[index] = to
	# steam where the water hits the flames, an occasional splash on the ground
	_steam_t[index] -= dt
	if _steam_t[index] <= 0.0:
		_steam_t[index] = STEAM_INTERVAL
		if Fx.has_method("smoke_puff"):
			Fx.smoke_puff(to + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5)), "steam", 0.9)
	_splash_t[index] -= dt
	if _splash_t[index] <= 0.0:
		_splash_t[index] = SPLASH_INTERVAL
		if Fx.has_method("splash"):
			Fx.splash(to + Vector3(0.0, 0.05, 0.0), 0.45)


func get_stats() -> Dictionary:
	return {"jets": _jets.size(), "active": active_count, "particles_each": AMOUNT}
