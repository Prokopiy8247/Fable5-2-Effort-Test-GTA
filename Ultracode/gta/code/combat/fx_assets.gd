extends RefCounted
## Procedural VFX resources for the Fx autoload ("Sunlit Low-Poly" style).
## Everything is authored in code - faceted meshes, soft gradient sprites, decal images, curves,
## colour ramps and particle process materials. No external files, nothing downloaded.
## Built once by Fx; decal textures are built lazily (first use / Fx prewarm at game_ready).

const SHADER_DIR := "res://gta/code/combat/shaders/"
const DECAL_KINDS: Array[String] = ["bullet", "scorch", "blood", "skid", "oil"]
const MAX_CACHED_MATERIALS := 96

# --- meshes (all flat shaded; unit sized so the particle scale is the size in metres) -----------
var blob: ArrayMesh        ## lumpy 80-facet icosphere, diameter 1 (smoke, dust, fireball, foam)
var pebble: ArrayMesh      ## irregular icosahedron, diameter 1 (droplets, small bits)
var chunk: ArrayMesh       ## squashed irregular octahedron (concrete chips, debris, clods)
var shard: ArrayMesh       ## thin triangular prism (glass, leaves, grass blades)
var splinter: ArrayMesh    ## tapered sliver along Y (wood)
var spark: ArrayMesh       ## thin bipyramid along Y, length 1 (sparks, embers)
var streak: ArrayMesh      ## bipyramid along Y, length 1 / width 1 (tracer; scaled per axis)
var flame: ArrayMesh       ## teardrop bipyramid, height 1 (fire)
var star: ArrayMesh        ## muzzle flash: forward spike (-Z) + radial spikes, vertex-colour gradient
var bill: ArrayMesh        ## bank note
var shell: ArrayMesh       ## spent casing
var quad: QuadMesh         ## 1 x 1 billboard quad
var plane: PlaneMesh       ## 2 x 2 ground quad (ring radius = node scale)

# --- textures / curves / ramps -------------------------------------------------------------------
var glow_tex: GradientTexture2D
var curve_pop: CurveTexture        ## 0 -> 1 fast, ease out to 0
var curve_hold: CurveTexture       ## full size, shrink at the end
var curve_shrink: CurveTexture     ## 1 -> 0
var curve_smoke: CurveTexture      ## grow slowly, shrink at the end
var curve_fire: CurveTexture       ## small -> full fast -> shrink
var ramp_fire: GradientTexture1D
var ramp_flame: GradientTexture1D
var ramp_blast_smoke: GradientTexture1D
var ramp_fire_smoke: GradientTexture1D
var ramp_smoke_age: GradientTexture1D   ## plain smoke: a little darker when young
var ramp_vary: GradientTexture1D   ## initial-colour variation (per particle brightness)

# --- shared materials ----------------------------------------------------------------------------
var sprite_add: ShaderMaterial     ## additive billboard (instance uniforms: glow_color, fade)
var ring_mat: ShaderMaterial       ## ring quad (instance uniforms: ring_color, progress, width, fade)

var _sh_lit: Shader
var _sh_glow: Shader
var _sh_add: Shader
var _mats: Dictionary = {}
var _decal_tex: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 20261109
	_sh_lit = load(SHADER_DIR + "fx_mesh_lit.gdshader") as Shader
	_sh_glow = load(SHADER_DIR + "fx_mesh_glow.gdshader") as Shader
	_sh_add = load(SHADER_DIR + "fx_glow_add.gdshader") as Shader
	_build_meshes()
	_build_textures()
	sprite_add = ShaderMaterial.new()
	sprite_add.shader = load(SHADER_DIR + "fx_sprite_add.gdshader") as Shader
	sprite_add.set_shader_parameter("tex", glow_tex)
	ring_mat = ShaderMaterial.new()
	ring_mat.shader = load(SHADER_DIR + "fx_ring.gdshader") as Shader
	ring_mat.render_priority = 1      # after the (transparent) ocean surface


# =================================================================================================
# materials (cached - a small discrete set of tints, so no per-shot allocation)
# =================================================================================================

## Lit faceted material. `emission` adds glow, `tumble` 0 keeps the particle basis (aligned meshes).
func lit(tint: Color, emission: float = 0.0, tumble: float = 1.0) -> ShaderMaterial:
	var key := "L%d_%d_%d" % [tint.to_rgba32(), int(emission * 100.0), int(tumble * 10.0)]
	var m: ShaderMaterial = _mats.get(key, null)
	if m == null:
		if _mats.size() >= MAX_CACHED_MATERIALS:
			return _first_of("L")
		m = ShaderMaterial.new()
		m.shader = _sh_lit
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("glow", emission)
		m.set_shader_parameter("tumble", tumble)
		_mats[key] = m
	return m


## Unshaded emissive faceted material (fire, sparks, sparkles).
func glow(tint: Color, strength: float = 1.4, tumble: float = 1.0, facet: float = 0.4) -> ShaderMaterial:
	var key := "G%d_%d_%d_%d" % [tint.to_rgba32(), int(strength * 100.0), int(tumble * 10.0), int(facet * 100.0)]
	var m: ShaderMaterial = _mats.get(key, null)
	if m == null:
		if _mats.size() >= MAX_CACHED_MATERIALS:
			return _first_of("G")
		m = ShaderMaterial.new()
		m.shader = _sh_glow
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("strength", strength)
		m.set_shader_parameter("tumble", tumble)
		m.set_shader_parameter("facet", facet)
		_mats[key] = m
	return m


## Additive mesh glow (tracers, muzzle star); `fade` is an instance uniform on the mesh instance.
func add(color: Color) -> ShaderMaterial:
	var key := "A%d" % color.to_rgba32()
	var m: ShaderMaterial = _mats.get(key, null)
	if m == null:
		if _mats.size() >= MAX_CACHED_MATERIALS:
			return _first_of("A")
		m = ShaderMaterial.new()
		m.shader = _sh_add
		m.set_shader_parameter("color", color)
		_mats[key] = m
	return m


func material_count() -> int:
	return _mats.size()


func _first_of(prefix: String) -> ShaderMaterial:
	for k: String in _mats:
		if k.begins_with(prefix):
			return _mats[k]
	return null


# =================================================================================================
# particle process materials
# =================================================================================================

## Builds a ParticleProcessMaterial from a compact description. Keys (all optional):
##   dir: Vector3, spread: deg, flat: 0..1, vel: Vector2(min, max), radial: Vector2(min, max),
##   gravity: Vector3, damping: Vector2, scale: Vector2, curve: CurveTexture, ramp, vary: bool,
##   shape: "point" | "sphere" | "box" | "ring", r: float, box: Vector3, ring_h: float,
##   angle: bool (random start angle), spin: deg/s (+/-), align_y: bool, rotate_y: bool,
##   life_rand: 0..1, accel: Vector2 (linear accel), hue: +/- hue variation (0..1 = 0..180 deg)
func proc(d: Dictionary) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = d.get("dir", Vector3.UP)
	m.spread = float(d.get("spread", 45.0))
	m.flatness = float(d.get("flat", 0.0))
	var vel: Vector2 = d.get("vel", Vector2.ZERO)
	m.initial_velocity_min = vel.x
	m.initial_velocity_max = vel.y
	var radial: Vector2 = d.get("radial", Vector2.ZERO)
	m.radial_velocity_min = radial.x
	m.radial_velocity_max = radial.y
	m.gravity = d.get("gravity", Vector3.ZERO)
	var damping: Vector2 = d.get("damping", Vector2.ZERO)
	m.damping_min = damping.x
	m.damping_max = damping.y
	var accel: Vector2 = d.get("accel", Vector2.ZERO)
	m.linear_accel_min = accel.x
	m.linear_accel_max = accel.y
	var sc: Vector2 = d.get("scale", Vector2.ONE)
	m.scale_min = sc.x
	m.scale_max = sc.y
	if d.has("curve"):
		m.scale_curve = d["curve"]
	if d.has("ramp"):
		m.color_ramp = d["ramp"]
	if bool(d.get("vary", false)):
		m.color_initial_ramp = ramp_vary
	match str(d.get("shape", "point")):
		"sphere":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = float(d.get("r", 0.1))
		"box":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			m.emission_box_extents = d.get("box", Vector3(0.1, 0.1, 0.1))
		"ring":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			m.emission_ring_axis = Vector3.UP
			m.emission_ring_radius = float(d.get("r", 0.5))
			m.emission_ring_inner_radius = float(d.get("r", 0.5)) * 0.7
			m.emission_ring_height = float(d.get("ring_h", 0.1))
		_:
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	if bool(d.get("angle", false)):
		m.angle_min = -180.0
		m.angle_max = 180.0
	var spin := float(d.get("spin", 0.0))
	m.angular_velocity_min = -spin
	m.angular_velocity_max = spin
	m.particle_flag_align_y = bool(d.get("align_y", false))
	m.particle_flag_rotate_y = bool(d.get("rotate_y", false))
	m.lifetime_randomness = float(d.get("life_rand", 0.0))
	var hue := float(d.get("hue", 0.0))
	m.hue_variation_min = -hue
	m.hue_variation_max = hue
	return m


# =================================================================================================
# decal textures (RGBA images drawn in code; jagged polar outlines = chunky stylised marks)
# =================================================================================================

func decal_texture(kind: String) -> Texture2D:
	var t: Texture2D = _decal_tex.get(kind, null)
	if t != null:
		return t
	match kind:
		"scorch":
			t = _tex_scorch()
		"blood":
			t = _tex_blob(Color(0.3, 0.012, 0.02), Color(0.44, 0.03, 0.035), 0.98, 10, 0.42, 0.3, 7)
		"oil":
			t = _tex_blob(Color(0.03, 0.03, 0.045), Color(0.075, 0.07, 0.11), 0.98, 12, 0.72, 0.16, 2)
		"skid":
			t = _tex_skid()
		_:
			t = _tex_bullet()
			kind = "bullet"
	_decal_tex[kind] = t
	return t


func prewarm_decals() -> void:
	for k in DECAL_KINDS:
		decal_texture(k)


func _edge_table(n: int, base: float, jitter: float) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(n)
	for i in n:
		t[i] = base * (1.0 + _rng.randf_range(-jitter, jitter))
	return t


static func _edge_at(t: PackedFloat32Array, theta: float) -> float:
	var n := t.size()
	var f := fposmod(theta / TAU, 1.0) * float(n)
	var i := int(f) % n
	var j := (i + 1) % n
	return lerpf(t[i], t[j], f - floorf(f))


static func _finish(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _tex_bullet() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var hole := _edge_table(9, 0.25, 0.22)
	var chip := _edge_table(11, 0.6, 0.3)
	var crack_ang := PackedFloat32Array()
	var crack_len := PackedFloat32Array()
	for i in 4:
		crack_ang.append(_rng.randf_range(0.0, TAU))
		crack_len.append(_rng.randf_range(0.7, 0.96))
	for y in s:
		for x in s:
			var u := (float(x) + 0.5) / float(s) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(s) * 2.0 - 1.0
			var d := sqrt(u * u + v * v)
			var th := atan2(v, u)
			var rh := _edge_at(hole, th)
			var rc := _edge_at(chip, th)
			var col := Color(0.5, 0.48, 0.45, 0.0)
			if d < rc:
				# pale chipped ring with a hard, slightly anti-aliased outline
				col.a = 0.78 * (1.0 - smoothstep(rc - 0.06, rc, d))
			for i in 4:
				if d > rh and d < crack_len[i] and absf(angle_difference(th, crack_ang[i])) * d < 0.03:
					col = Color(0.07, 0.07, 0.075, 0.8 * (1.0 - smoothstep(crack_len[i] - 0.2, crack_len[i], d)))
			if d < rh:
				var k := smoothstep(rh - 0.06, rh, d)
				col = Color(0.025, 0.025, 0.03, 0.97).lerp(Color(0.18, 0.17, 0.16, 0.9), k)
			img.set_pixel(x, y, col)
	return _finish(img)


func _tex_scorch() -> ImageTexture:
	var s := 96
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var outer := _edge_table(19, 0.82, 0.2)
	var mid := _edge_table(13, 0.56, 0.2)
	var core := _edge_table(9, 0.3, 0.22)
	for y in s:
		for x in s:
			var u := (float(x) + 0.5) / float(s) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(s) * 2.0 - 1.0
			var d := sqrt(u * u + v * v)
			var th := atan2(v, u)
			var ro := _edge_at(outer, th)
			var rm := _edge_at(mid, th)
			var rc := _edge_at(core, th)
			var col := Color(0.15, 0.1, 0.07, 0.0)
			if d < ro:
				col.a = 0.55 * (1.0 - smoothstep(ro - 0.07, ro, d))
			if d < rm:
				var k := 1.0 - smoothstep(rm - 0.06, rm, d)
				col = col.lerp(Color(0.06, 0.045, 0.035, 0.88), k)
			if d < rc:
				var k2 := 1.0 - smoothstep(rc - 0.06, rc, d)
				col = col.lerp(Color(0.02, 0.018, 0.016, 0.985), k2)
			img.set_pixel(x, y, col)
	return _finish(img)


## Irregular puddle / splat with `drops` satellite droplets.
func _tex_blob(inner: Color, edge: Color, alpha: float, points: int, base: float, jitter: float, drops: int) -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var outline := _edge_table(points, base, jitter)
	var drop_pos := PackedVector2Array()
	var drop_r := PackedFloat32Array()
	for i in drops:
		var a := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(base + 0.14, 0.86)
		drop_pos.append(Vector2(cos(a), sin(a)) * r)
		drop_r.append(_rng.randf_range(0.035, 0.085))
	for y in s:
		for x in s:
			var u := (float(x) + 0.5) / float(s) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(s) * 2.0 - 1.0
			var d := sqrt(u * u + v * v)
			var re := _edge_at(outline, atan2(v, u))
			var a_out := 0.0
			var col := edge
			if d < re:
				a_out = alpha * (1.0 - smoothstep(re - 0.06, re, d))
				col = inner.lerp(edge, smoothstep(re * 0.45, re * 0.6, d))
			for i in drops:
				var dd := Vector2(u, v).distance_to(drop_pos[i])
				if dd < drop_r[i]:
					a_out = maxf(a_out, alpha * (1.0 - smoothstep(drop_r[i] - 0.03, drop_r[i], dd)))
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a_out))
	return _finish(img)


func _tex_skid() -> ImageTexture:
	var w := 32
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rows := PackedFloat32Array()
	for y in h:
		rows.append(_rng.randf_range(0.75, 1.0))
	for y in h:
		for x in w:
			var u := absf((float(x) + 0.5) / float(w) * 2.0 - 1.0)
			var v := (float(y) + 0.5) / float(h)
			var across := 1.0 - smoothstep(0.72, 0.98, u)
			var tread := 1.0 if fposmod(u * 2.6 + 0.2, 1.0) >= 0.5 else 0.7
			var ends := smoothstep(0.0, 0.12, v) * (1.0 - smoothstep(0.88, 1.0, v))
			img.set_pixel(x, y, Color(0.03, 0.03, 0.032, 0.62 * across * tread * ends * rows[y]))
	return _finish(img)


# =================================================================================================
# textures, curves, ramps
# =================================================================================================

func _build_textures() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.22, 0.55, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1), Color(0.72, 0.72, 0.72), Color(0.2, 0.2, 0.2), Color(0, 0, 0)])
	glow_tex = GradientTexture2D.new()
	glow_tex.gradient = g
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(1.0, 0.5)
	glow_tex.width = 64
	glow_tex.height = 64

	curve_pop = _curve([Vector2(0.0, 0.0), Vector2(0.1, 1.0), Vector2(0.5, 0.86), Vector2(1.0, 0.0)])
	curve_hold = _curve([Vector2(0.0, 1.0), Vector2(0.65, 1.0), Vector2(1.0, 0.0)])
	curve_shrink = _curve([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
	curve_smoke = _curve([Vector2(0.0, 0.1), Vector2(0.2, 0.8), Vector2(0.6, 1.0), Vector2(1.0, 0.0)])
	curve_fire = _curve([Vector2(0.0, 0.3), Vector2(0.14, 1.0), Vector2(0.5, 0.8), Vector2(1.0, 0.0)])

	ramp_fire = _ramp([0.0, 0.18, 0.45, 0.78, 1.0], [Color(1.0, 0.9, 0.46), Color(1.0, 0.63, 0.14),
			Color(0.94, 0.3, 0.06), Color(0.36, 0.1, 0.05), Color(0.12, 0.1, 0.1)])
	ramp_flame = _ramp([0.0, 0.3, 0.7, 1.0], [Color(1.0, 0.9, 0.5), Color(1.0, 0.56, 0.1),
			Color(0.92, 0.24, 0.05), Color(0.5, 0.08, 0.03)])
	ramp_blast_smoke = _ramp([0.0, 0.12, 0.45, 1.0], [Color(0.8, 0.38, 0.1), Color(0.24, 0.2, 0.17),
			Color(0.3, 0.28, 0.27), Color(0.5, 0.49, 0.48)])
	ramp_fire_smoke = _ramp([0.0, 0.2, 1.0], [Color(0.42, 0.2, 0.08), Color(0.17, 0.16, 0.16),
			Color(0.36, 0.35, 0.35)])
	ramp_smoke_age = _ramp([0.0, 1.0], [Color(0.82, 0.82, 0.82), Color(1.0, 1.0, 1.0)])
	ramp_vary = _ramp([0.0, 1.0], [Color(0.86, 0.86, 0.86), Color(1.0, 1.0, 1.0)])


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p: Vector2 in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.width = 32
	t.curve = c
	return t


static func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.width = 32
	t.gradient = g
	return t


# =================================================================================================
# meshes
# =================================================================================================

func _build_meshes() -> void:
	blob = _tri_mesh(_lumpy(_subdivide(_icosa_tris(0.5, 0.0), 0.5), 0.16))
	pebble = _tri_mesh(_icosa_tris(0.5, 0.13))
	chunk = _tri_mesh(_octa_tris(Vector3(0.5, 0.36, 0.44), 0.25))
	# glass shard: thin triangular prism
	var a := Vector3(-0.5, -0.3, 0.0)
	var b := Vector3(0.5, -0.2, 0.0)
	var c := Vector3(0.05, 0.5, 0.0)
	var t := Vector3(0.0, 0.0, 0.035)
	var sh := PackedVector3Array([a - t, b - t, c - t, a + t, c + t, b + t])
	for e: Array in [[a, b], [b, c], [c, a]]:
		var p: Vector3 = e[0]
		var q: Vector3 = e[1]
		sh.append_array(PackedVector3Array([p - t, q - t, q + t, p - t, q + t, p + t]))
	shard = _tri_mesh(sh)
	splinter = _tri_mesh(_box_tris(Vector3(0.2, 1.0, 0.12), 0.2))
	spark = _tri_mesh(_bipyramid_tris(0.07, -0.5, -0.2, 0.5, 4))
	streak = _tri_mesh(_bipyramid_tris(0.5, -0.5, -0.25, 0.5, 4))
	flame = _tri_mesh(_bipyramid_tris(0.27, -0.28, 0.0, 0.72, 5), Vector3(0.0, 0.1, 0.0))
	bill = _tri_mesh(_box_tris(Vector3(0.17, 0.012, 0.08), 1.0))
	shell = _tri_mesh(_box_tris(Vector3(0.022, 0.055, 0.022), 0.8))
	star = _build_star()
	quad = QuadMesh.new()
	quad.size = Vector2.ONE
	plane = PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)


## Flat-shaded mesh from a triangle soup of a shape that is convex around `center`.
## Winding is fixed here (Godot front faces are clockwise), normals are per facet.
static func _tri_mesh(tris: PackedVector3Array, center: Vector3 = Vector3.ZERO) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		if n.dot((a + b + c) / 3.0 - center) < 0.0:
			var tmp := b
			b = c
			c = tmp
			n = -n
		# a, b, c is now counter-clockwise seen from outside -> emit clockwise
		verts.append(a)
		verts.append(c)
		verts.append(b)
		norms.append(n)
		norms.append(n)
		norms.append(n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _icosa_tris(radius: float, jitter: float) -> PackedVector3Array:
	var p := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = [Vector3(-1, p, 0), Vector3(1, p, 0), Vector3(-1, -p, 0), Vector3(1, -p, 0),
			Vector3(0, -1, p), Vector3(0, 1, p), Vector3(0, -1, -p), Vector3(0, 1, -p),
			Vector3(p, 0, -1), Vector3(p, 0, 1), Vector3(-p, 0, -1), Vector3(-p, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized() * radius * (1.0 + _rng.randf_range(-jitter, jitter))
	var f := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4,
			11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5,
			2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	var out := PackedVector3Array()
	for i in f:
		out.append(v[i])
	return out


## Splits every triangle in four and pushes the new vertices out to the sphere of `radius`.
static func _subdivide(tris: PackedVector3Array, radius: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var ab := ((a + b) * 0.5).normalized() * radius
		var bc := ((b + c) * 0.5).normalized() * radius
		var ca := ((c + a) * 0.5).normalized() * radius
		out.append_array(PackedVector3Array([a, ab, ca, ab, b, bc, ca, bc, c, ab, bc, ca]))
	return out


## Radial jitter that is identical for coincident vertices (keeps the mesh closed).
func _lumpy(tris: PackedVector3Array, jitter: float) -> PackedVector3Array:
	var seen: Dictionary = {}
	var out := PackedVector3Array()
	for v in tris:
		var key := Vector3i(roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0))
		if not seen.has(key):
			seen[key] = 1.0 + _rng.randf_range(-jitter, jitter)
		out.append(v * float(seen[key]))
	return out


func _octa_tris(half: Vector3, jitter: float) -> PackedVector3Array:
	var v: Array[Vector3] = [Vector3(half.x, 0, 0), Vector3(-half.x, 0, 0), Vector3(0, half.y, 0),
			Vector3(0, -half.y, 0), Vector3(0, 0, half.z), Vector3(0, 0, -half.z)]
	for i in v.size():
		v[i] = v[i] * (1.0 + _rng.randf_range(-jitter, jitter))
	var f := PackedInt32Array([0, 2, 4, 4, 2, 1, 1, 2, 5, 5, 2, 0, 0, 4, 3, 4, 1, 3, 1, 5, 3, 5, 0, 3])
	var out := PackedVector3Array()
	for i in f:
		out.append(v[i])
	return out


static func _box_tris(size: Vector3, top_taper: float) -> PackedVector3Array:
	var h := size * 0.5
	var t := top_taper
	var p: Array[Vector3] = [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z),
			Vector3(-h.x, -h.y, h.z), Vector3(-h.x * t, h.y, -h.z * t), Vector3(h.x * t, h.y, -h.z * t),
			Vector3(h.x * t, h.y, h.z * t), Vector3(-h.x * t, h.y, h.z * t)]
	var quads := PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 5, 4, 1, 2, 6, 5, 2, 3, 7, 6, 3, 0, 4, 7])
	var out := PackedVector3Array()
	for q in range(0, quads.size(), 4):
		var a := p[quads[q]]
		var b := p[quads[q + 1]]
		var c := p[quads[q + 2]]
		var d := p[quads[q + 3]]
		out.append_array(PackedVector3Array([a, b, c, a, c, d]))
	return out


## Two pyramids sharing a ring at `y_waist` (convex around the waist centre).
static func _bipyramid_tris(radius: float, y_bottom: float, y_waist: float, y_top: float, sides: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var top := Vector3(0.0, y_top, 0.0)
	var bottom := Vector3(0.0, y_bottom, 0.0)
	for k in sides:
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var p0 := Vector3(cos(a0) * radius, y_waist, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, y_waist, sin(a1) * radius)
		out.append_array(PackedVector3Array([p0, p1, top, p1, p0, bottom]))
	return out


## Muzzle flash: a forward spike along -Z plus five short radial spikes. Rendered additive and
## double sided; vertex colours fade from a hot core to transparent orange tips.
func _build_star() -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var core := Color(1.0, 0.96, 0.78, 1.0)
	var tip := Color(1.0, 0.5, 0.1, 0.0)
	_spike(verts, cols, Vector3(0.0, 0.0, 0.02), Vector3(0.0, 0.0, -0.62), 0.085, core, tip)
	_spike(verts, cols, Vector3.ZERO, Vector3(0.0, 0.0, 0.08), 0.085, core, tip)
	for k in 5:
		var a := TAU * float(k) / 5.0 + 0.3
		var l := 0.22 + 0.12 * _rng.randf()
		_spike(verts, cols, Vector3(0.0, 0.0, -0.03), Vector3(cos(a) * l, sin(a) * l, -0.1), 0.05, core, tip)
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.BACK)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _spike(verts: PackedVector3Array, cols: PackedColorArray, base: Vector3, tip_pos: Vector3,
		radius: float, base_col: Color, tip_col: Color) -> void:
	var axis := (tip_pos - base).normalized()
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := axis.cross(u)
	for k in 4:
		var a0 := TAU * float(k) / 4.0
		var a1 := TAU * float(k + 1) / 4.0
		verts.append(base + (u * cos(a0) + w * sin(a0)) * radius)
		verts.append(base + (u * cos(a1) + w * sin(a1)) * radius)
		verts.append(tip_pos)
		cols.append(base_col)
		cols.append(base_col)
		cols.append(tip_col)
