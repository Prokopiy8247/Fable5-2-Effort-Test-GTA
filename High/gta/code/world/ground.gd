class_name Ground
extends Node3D
## Terrain mesh + collision, road surfaces with shader-drawn markings, sidewalk slabs and the ocean.

const CELL := 4.0
const EXTENT := 384.0

const ROAD_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec3 asphalt : source_color = vec3(0.21, 0.22, 0.24);
uniform vec3 line_white : source_color = vec3(0.86, 0.86, 0.8);
uniform vec3 line_yellow : source_color = vec3(0.92, 0.72, 0.18);
global uniform float wetness;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float u = UV.x;
	float v = UV.y;
	float len = UV2.x;
	float hw = UV2.y;
	float major = step(6.0, hw);
	vec3 col = asphalt * (0.94 + 0.12 * hash(floor(wpos.xz * 1.5)));
	col *= 1.0 - 0.1 * step(0.94, hash(floor(wpos.xz * 0.22)));
	col *= 1.0 - 0.1 * step(0.9, hash(floor(vec2(wpos.x * 0.6, wpos.z * 6.0))));
	float m = 0.0;
	float y = 0.0;
	if (len > 0.5) {
		float au = abs(u);
		m = max(m, step(hw - 0.5, au) * step(au, hw - 0.34));
		if (major > 0.5) {
			y = step(0.1, au) * step(au, 0.24);
			m = max(m, step(abs(au - hw * 0.5), 0.07) * step(fract(v / 8.0), 0.4));
		} else {
			y = step(au, 0.08) * step(fract(v / 7.0), 0.55);
		}
		float de = min(v, len - v);
		float zebra = step(0.4, de) * step(de, 3.0) * step(fract((u + hw) / 1.1), 0.5);
		float inside = step(3.0, de);
		m *= inside; y *= inside;
		m = max(m, zebra);
		float stopl = step(3.5, de) * step(de, 3.9);
		float side = (v > len * 0.5) ? step(0.0, u) : step(u, 0.0);
		m = max(m, stopl * side);
	}
	float wear = 0.75 + 0.25 * hash(floor(wpos.xz * 3.0));
	col = mix(col, line_yellow * wear, y);
	col = mix(col, line_white * wear, m);
	ALBEDO = col * mix(1.0, 0.6, wetness);
	ROUGHNESS = mix(0.93, 0.18, wetness);
	SPECULAR = mix(0.3, 0.7, wetness);
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;
uniform vec3 shallow : source_color = vec3(0.16, 0.62, 0.66);
uniform vec3 deep : source_color = vec3(0.03, 0.2, 0.34);
uniform vec3 foam : source_color = vec3(0.92, 0.97, 0.98);
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform float storm = 0.0;
varying vec3 wpos;
float wave(vec2 p, float t) {
	return sin(p.x * 0.09 + t * 0.9) * 0.5 + sin(p.y * 0.13 + t * 1.1) * 0.35 + sin((p.x + p.y) * 0.31 + t * 1.9) * 0.15;
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float amp = 0.12 + storm * 0.3;
	VERTEX.y += wave(wpos.xz, TIME) * amp;
	float e = 1.0;
	float hx = wave(wpos.xz + vec2(e, 0.0), TIME) - wave(wpos.xz - vec2(e, 0.0), TIME);
	float hz = wave(wpos.xz + vec2(0.0, e), TIME) - wave(wpos.xz - vec2(0.0, e), TIME);
	NORMAL = normalize(vec3(-hx * amp, 2.0, -hz * amp));
}
void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -up.z / up.w;
	float water_z = -VERTEX.z;
	float depth = max(scene_z - water_z, 0.0);
	float t = clamp(depth / 9.0, 0.0, 1.0);
	vec3 col = mix(shallow, deep, t);
	float ripple = sin(wpos.x * 0.8 + TIME * 1.4) * sin(wpos.z * 0.7 - TIME * 1.1);
	float f = smoothstep(0.9, 0.0, depth + ripple * 0.25) ;
	col = mix(col, foam, f * 0.85);
	float sparkle = step(0.985, sin(wpos.x * 1.7 + TIME * 0.7) * sin(wpos.z * 1.9 - TIME * 0.5));
	col += foam * sparkle * 0.12;
	ALBEDO = col;
	ALPHA = clamp(0.55 + t * 0.4 + f * 0.4, 0.0, 0.97);
	ROUGHNESS = 0.08;
	METALLIC = 0.1;
	SPECULAR = 0.6;
}
"""

var water: MeshInstance3D
var water_mat: ShaderMaterial
var road_mat: ShaderMaterial
var body: StaticBody3D


func build() -> void:
	body = StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	add_child(body)
	_terrain()
	_roads()
	_slabs()
	_water()


func _zone_color(x: float, z: float, h: float, ny: float) -> Color:
	var sand := Color(0.80, 0.69, 0.46)
	var grass := Color(0.36, 0.6, 0.28)
	var grass2 := Color(0.44, 0.66, 0.3)
	var rock := Color(0.52, 0.5, 0.47)
	var tar := Color(0.23, 0.24, 0.26)
	var n := sin(x * 0.37) * cos(z * 0.29) * 0.5 + 0.5
	if h < -0.25:
		return sand.lerp(Color(0.5, 0.56, 0.5), clampf(-h / 9.0, 0.0, 1.0))
	if ny < 0.8:
		return rock
	if z > 187.5 and x < 104.0:
		return sand
	if Vector2(x + 40.0, z - 262.0).length() < 26.0:
		return rock.lerp(grass, 0.3)
	if x < -206.0 or z < -199.0 or x > 284.0:
		return grass.lerp(grass2, n)
	if z > 184.0 and x >= 104.0:
		return Color(0.55, 0.54, 0.51)
	return tar


func _terrain() -> void:
	var n := int(EXTENT * 2.0 / CELL)
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	for iz in range(n + 1):
		for ix in range(n + 1):
			heights[iz * (n + 1) + ix] = City.terrain_height(-EXTENT + ix * CELL, -EXTENT + iz * CELL)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var faces := PackedVector3Array()
	for iz in range(n):
		for ix in range(n):
			var x0 := -EXTENT + ix * CELL
			var z0 := -EXTENT + iz * CELL
			var h00 := heights[iz * (n + 1) + ix]
			var h10 := heights[iz * (n + 1) + ix + 1]
			var h01 := heights[(iz + 1) * (n + 1) + ix]
			var h11 := heights[(iz + 1) * (n + 1) + ix + 1]
			if h00 <= -13.9 and h10 <= -13.9 and h01 <= -13.9 and h11 <= -13.9:
				continue
			var a := Vector3(x0, h00, z0)
			var b := Vector3(x0 + CELL, h10, z0)
			var c := Vector3(x0, h01, z0 + CELL)
			var d := Vector3(x0 + CELL, h11, z0 + CELL)
			for tri in [[a, b, c], [b, d, c]]:
				var nrm: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				var cen: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				var col := _zone_color(cen.x, cen.z, cen.y, nrm.y)
				for p in tri:
					verts.append(p)
					norms.append(nrm)
					cols.append(col)
					faces.append(p)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	m.metallic_specular = 0.2
	mesh.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	# far seabed so the horizon never shows the clear colour through the water
	var sb := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	sb.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.1, 0.22, 0.3)
	sm.roughness = 1.0
	sb.material_override = sm
	sb.position.y = -14.2
	add_child(sb)


func _quad(st: SurfaceTool, c: Vector3, along: Vector3, half_len: float, half_w: float, length_uv: float, y: float) -> void:
	## Road quad: u = lateral metres (+ = right of 'along'), v = metres along.
	var right := Vector3(-along.z, 0, along.x)
	var p := [c - along * half_len - right * half_w, c - along * half_len + right * half_w,
		c + along * half_len + right * half_w, c + along * half_len - right * half_w]
	var uv := [Vector2(-half_w, 0), Vector2(half_w, 0), Vector2(half_w, half_len * 2.0), Vector2(-half_w, half_len * 2.0)]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_normal(Vector3.UP)
		st.set_uv(uv[i])
		st.set_uv2(Vector2(length_uv, half_w))
		st.add_vertex(Vector3(p[i].x, y, p[i].z))


func _roads() -> void:
	City.build()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.03
	for s in City.segs:
		var na: Dictionary = City.nodes[s.a]
		var nb: Dictionary = City.nodes[s.b]
		var ha: float = na.hz if s.axis == "z" else na.hx
		var hb: float = nb.hz if s.axis == "z" else nb.hx
		var a: Vector3 = na.pos + s.dir * ha
		var b: Vector3 = nb.pos - s.dir * hb
		var length := (b - a).length()
		_quad(st, (a + b) * 0.5, s.dir, length * 0.5, s.half, length, y)
	for n in City.nodes:
		# plain asphalt intersection box (len 0 disables markings)
		var p: Vector3 = n.pos
		var hx: float = n.hx
		var hz: float = n.hz
		var along := Vector3(0, 0, 1)
		_quad(st, p, along, hz, hx, 0.0, y)
	for sb in City.stubs():
		var d: Vector3 = (sb.p1 - sb.p0).normalized()
		var length2: float = (sb.p1 - sb.p0).length()
		_quad(st, (sb.p0 + sb.p1) * 0.5, d, length2 * 0.5, sb.half, length2, y)
	# airport: runway, taxiway and apron
	_quad(st, Vector3(0, 0, -272), Vector3(1, 0, 0), 282.0, 11.0, 0.0, y)
	_quad(st, Vector3(60, 0, -240), Vector3(1, 0, 0), 215.0, 21.0, 0.0, y - 0.005)
	_quad(st, Vector3(-150, 0, -250), Vector3(1, 0, 0), 12.0, 11.0, 0.0, y - 0.01)
	# port apron
	_quad(st, Vector3(203, 0, 194), Vector3(1, 0, 0), 97.0, 12.0, 0.0, y)
	var mesh := st.commit()
	road_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = ROAD_SHADER
	road_mat.shader = sh
	mesh.surface_set_material(0, road_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Roads"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_runway_marks()


func _runway_marks() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 0.02, 1)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.9, 0.85)
	m.roughness = 0.9
	bm.material = m
	mm.mesh = bm
	var xf: Array[Transform3D] = []
	for i in range(27):
		xf.append(Transform3D(Basis().scaled(Vector3(9.0, 1, 0.7)), Vector3(-260 + i * 20.0, 0.05, -272)))
	for sx in [-1, 1]:
		for k in range(6):
			xf.append(Transform3D(Basis().scaled(Vector3(14.0, 1, 0.9)), Vector3(sx * 268.0, 0.05, -279.5 + k * 3.0)))
	xf.append(Transform3D(Basis().scaled(Vector3(560.0, 1, 0.35)), Vector3(0, 0.05, -261.6)))
	xf.append(Transform3D(Basis().scaled(Vector3(560.0, 1, 0.35)), Vector3(0, 0.05, -282.4)))
	mm.instance_count = xf.size()
	for i in range(xf.size()):
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _slab(rect: Rect2, top: Color, inner = null, h: float = City.CURB) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(rect.size.x, h + 0.5, rect.size.y)
	mi.mesh = bm
	mi.material_override = CharRig.color_mat(top, 0.92)
	mi.position = Vector3(rect.position.x + rect.size.x * 0.5, h - (h + 0.5) * 0.5, rect.position.y + rect.size.y * 0.5)
	add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	cs.position = mi.position
	body.add_child(cs)
	if inner != null:
		var r2 := rect.grow(-City.SIDEWALK)
		var mi2 := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = r2.size
		mi2.mesh = pm
		mi2.material_override = CharRig.color_mat(inner, 0.95)
		mi2.position = Vector3(r2.position.x + r2.size.x * 0.5, h + 0.012, r2.position.y + r2.size.y * 0.5)
		mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi2)


func _slabs() -> void:
	var walk := Color(0.64, 0.62, 0.58)
	var pave := Color(0.55, 0.54, 0.52)
	var grass := Color(0.4, 0.63, 0.3)
	var yard := Color(0.42, 0.42, 0.42)
	for ci in range(5):
		for ri in range(4):
			if ci == 4 and ri == 3:
				continue
			var r := City.block_rect(ci, ri)
			var key := "%d,%d" % [ci, ri]
			var inner: Color = pave
			if key == "0,1":
				inner = grass
			elif key == "0,2" or key == "0,3":
				inner = Color(0.45, 0.64, 0.33)
			elif ci >= 3:
				inner = yard
			_slab(r, walk, inner)
	# outer sidewalk strips
	_slab(Rect2(-208, -198, 3, 386), walk)                 # west of x=-200
	_slab(Rect2(-205, -201, 493, 3), walk)                 # north of expressway
	_slab(Rect2(285, -198, 3, 316), walk)                  # east of x=280
	_slab(Rect2(-205, 185, 410, 3.5), walk)                # promenade south of Ocean Drive
	_slab(Rect2(205, 115, 83, 70), walk, yard)             # port block
	_slab(Rect2(100, 206, 200, 2), Color(0.5, 0.5, 0.48), null, 0.5)  # quay edge


func _water() -> void:
	water = MeshInstance3D.new()
	water.name = "Ocean"
	var pm := PlaneMesh.new()
	pm.size = Vector2(3200, 3200)
	pm.subdivide_width = 160
	pm.subdivide_depth = 160
	water.mesh = pm
	water_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = WATER_SHADER
	water_mat.shader = sh
	water.material_override = water_mat
	water.position.y = Game.WATER_Y
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
