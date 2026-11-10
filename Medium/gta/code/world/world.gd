extends Node3D
## Builds the compact ~600x600 m island city "Port Cinder" procedurally from Blender-authored kit pieces.

const XR := [-240.0, -120.0, 0.0, 120.0, 240.0]
const ZR := [-200.0, -100.0, 0.0, 100.0, 200.0]
const LAND := Rect2(-300, -300, 600, 514)   # x,z ; south edge z=214
const CURB := 0.15
const RUNWAY_Z := -274.0

var occupied: Array = []        # Rect2 footprints of buildings
var interacts: Array = []       # {pos, r, text, fn, veh}
var lamps: Array = []           # Vector3 light positions
var locations: Dictionary = {}  # name -> Vector3
var map_icons: Array = []       # {pos, kind, name}
var blocks: Array = []          # {rect: Rect2, i, j, district}
var ped_nodes: Array = []       # Vector3
var ped_links: Array = []       # Array[Array[int]]
var parking: Array = []         # {pos, yaw}
var signals: Array = []         # {pos, ns:[nodes], ew:[nodes], x, z}
var ladders: Array = []         # {pos, top, dir}
var cover_boxes: Array = []
var building_nodes: Dictionary = {}
var window_mat: ShaderMaterial
var tower_mat: ShaderMaterial
var water_mat: ShaderMaterial
var rng := RandomNumberGenerator.new()
var _static: StaticBody3D
var _mark: SurfaceTool
var knock_scene_cache := {}


func hw(v: float) -> float:
	return 10.0 if v == 0.0 else 7.0


func is_sea(x: float, z: float) -> bool:
	return not LAND.has_point(Vector2(x, z))


func hill_h(x: float, z: float) -> float:
	var u: float = 1.0 - clamp(abs(x + 180.0) / 46.0, 0.0, 1.0)
	var v: float = 1.0 - clamp(abs(z + 150.0) / 36.0, 0.0, 1.0)
	var f: float = smoothstep(0.0, 1.0, u) * smoothstep(0.0, 1.0, v)
	return 15.0 * smoothstep(0.0, 0.8, f)


func on_road(x: float, z: float, margin := 0.0) -> bool:
	if abs(x) > 247 + margin or abs(z) > 207 + margin:
		return false
	for xr in XR:
		if abs(x - xr) < hw(xr) + margin and abs(z) <= 207:
			return true
	for zr in ZR:
		if abs(z - zr) < hw(zr) + margin and abs(x) <= 247:
			return true
	return false


func district(p: Vector3) -> String:
	if is_sea(p.x, p.z):
		return "Cinder Bay"
	if p.z < -207:
		return "Cinder Airfield"
	if p.z > 207:
		return "Saltline Beach" if p.x < 0 else "Anchor Docks"
	if p.x < -247:
		return "Westwood"
	if p.x > 247:
		return "Rustyard"
	if p.x < -120:
		return "Signal Hill" if p.z < -100 else "Larkspur"
	if p.x > 120:
		return "Ironside"
	if p.z < -100:
		return "Civic North"
	if p.z > 100:
		return "Southshore"
	return "Downtown"


func build() -> void:
	rng.seed = 4242
	_static = StaticBody3D.new()
	_static.collision_layer = G.L_WORLD
	_static.collision_mask = 0
	add_child(_static)
	_make_materials()
	_ground()
	_slabs()
	_markings()
	_water()
	_layout_buildings()
	_props()
	_ped_graph()
	_nav()


# ---------------------------------------------------------------- helpers
func _box_col(center: Vector3, size: Vector3, body: Node = null, basis := Basis.IDENTITY) -> void:
	var cs = CollisionShape3D.new()
	var b = BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.transform = Transform3D(basis, center)
	(body if body else _static).add_child(cs)


func _box_mesh(center: Vector3, size: Vector3, mat: Material, parent: Node = null) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	(parent if parent else self).add_child(mi)
	return mi


func _make_materials() -> void:
	var sh = Shader.new()
	sh.code = """
shader_type spatial;
uniform vec3 base : source_color = vec3(0.12,0.2,0.28);
uniform vec3 lit : source_color = vec3(1.0,0.82,0.5);
uniform float cell = 2.6;
uniform float floor_h = 3.3;
global uniform float night_amount;
varying vec3 wp;
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
float hash(vec3 p){ return fract(sin(dot(p, vec3(12.9898,78.233,37.719))) * 43758.5453); }
void fragment(){
	vec3 c = floor(vec3((wp.x + wp.z) / cell, wp.y / floor_h, (wp.x - wp.z) / cell * 0.37));
	float h = hash(c);
	float on = step(0.55, h) * night_amount;
	ALBEDO = mix(base, base * 0.5, night_amount * 0.5);
	METALLIC = 0.5; ROUGHNESS = 0.15;
	EMISSION = lit * on * (0.6 + 0.8 * fract(h * 7.0));
}"""
	window_mat = ShaderMaterial.new()
	window_mat.shader = sh
	tower_mat = ShaderMaterial.new()
	tower_mat.shader = sh
	tower_mat.set_shader_parameter("base", Color(0.2, 0.42, 0.6))
	tower_mat.set_shader_parameter("lit", Color(0.75, 0.9, 1.0))
	tower_mat.set_shader_parameter("cell", 3.5)
	tower_mat.set_shader_parameter("floor_h", 4.0)
	var ws = Shader.new()
	ws.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_always;
uniform vec3 deep : source_color = vec3(0.02,0.22,0.36);
uniform vec3 shallow : source_color = vec3(0.1,0.55,0.62);
global uniform float night_amount;
varying vec3 wp;
float wave(vec2 p, float t){ return sin(p.x*0.35 + t*1.1)*0.5 + sin(p.y*0.27 - t*0.9)*0.5 + sin((p.x+p.y)*0.6 + t*1.7)*0.25; }
void vertex(){
	wp = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	VERTEX.y += wave(wp.xz, TIME) * 0.12;
}
void fragment(){
	float dist = length(wp - CAMERA_POSITION_WORLD);
	float lodk = clamp(1.0 - dist / 260.0, 0.0, 1.0);
	float w = wave(wp.xz * 2.0, TIME * 1.3) * lodk;
	float w2 = wave(wp.zx * 5.0 + 3.0, TIME * 2.0) * lodk;
	vec3 n = normalize(vec3(w * 0.12 + w2 * 0.05, 1.0, w2 * 0.1 - w * 0.06));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(deep, shallow, clamp(0.5 + w * 0.3, 0.0, 1.0));
	float foam = smoothstep(0.93, 1.0, sin(wp.x * 0.9 + w * 2.0 + TIME) * sin(wp.z * 1.1 - TIME * 0.7 + w2)) * lodk;
	ALBEDO = mix(col, vec3(0.9), foam * 0.6) * (1.0 - night_amount * 0.75);
	ROUGHNESS = 0.08; METALLIC = 0.2; SPECULAR = 0.7;
	ALPHA = mix(0.78, 0.96, fres);
}"""
	water_mat = ShaderMaterial.new()
	water_mat.shader = ws


func _ground() -> void:
	# land base (road level y=0)
	_box_col(Vector3(0, -10, -43), Vector3(600, 20, 514))
	_box_mesh(Vector3(0, -10, -43), Vector3(600, 20, 514), G.cmat("asphalt", Color(0.2, 0.21, 0.23), 0.95))
	# sea bed
	_box_col(Vector3(0, -19, 0), Vector3(3000, 20, 3000))
	_box_mesh(Vector3(0, -9.5, 0), Vector3(3000, 1, 3000), G.cmat("seabed", Color(0.55, 0.5, 0.36), 1.0))
	# beach ramp (west half of the south shore)
	var p0 = Vector3(-150, CURB, 214)
	var p1 = Vector3(-150, -9.0, 284)
	var d = p1 - p0
	var basis = Basis.looking_at(d.normalized(), Vector3.UP)
	var mid = (p0 + p1) * 0.5 - basis.y * 1.0
	_box_col(mid, Vector3(300, 2.0, d.length()), null, basis)
	var m = _box_mesh(mid, Vector3(300, 2.0, d.length()), G.cmat("sand", Color(0.89, 0.8, 0.58), 1.0))
	m.basis = basis
	# seawall trim
	var wall = G.cmat("seawall", Color(0.5, 0.5, 0.48), 0.95)
	_box_mesh(Vector3(150, -4.5, 214.2), Vector3(300, 9.4, 0.6), wall)
	_box_mesh(Vector3(0, -4.5, -300.2), Vector3(600.8, 9.4, 0.6), wall)
	_box_mesh(Vector3(-300.2, -4.5, -43), Vector3(0.6, 9.4, 514), wall)
	_box_mesh(Vector3(300.2, -4.5, -43), Vector3(0.6, 9.4, 514), wall)


func _slab(r: Rect2, top_mat: Material, ring := 3.0, ring_mat: Material = null) -> void:
	var c = Vector3(r.position.x + r.size.x / 2, CURB / 2 - 0.5, r.position.y + r.size.y / 2)
	_box_col(c, Vector3(r.size.x, CURB + 1.0, r.size.y))
	var side = ring_mat if ring_mat else G.cmat("sidewalk", Color(0.66, 0.65, 0.62), 0.95)
	_box_mesh(Vector3(c.x, CURB / 2, c.z), Vector3(r.size.x, CURB, r.size.y), side)
	if ring > 0.0 and top_mat:
		_box_mesh(Vector3(c.x, CURB + 0.005, c.z), Vector3(r.size.x - ring * 2, 0.01, r.size.y - ring * 2), top_mat)


func _slabs() -> void:
	var grass = G.cmat("grass", Color(0.36, 0.6, 0.3), 1.0)
	var conc = G.cmat("concrete", Color(0.58, 0.58, 0.56), 0.95)
	var lot = G.cmat("lot", Color(0.3, 0.31, 0.33), 0.95)
	var dirt = G.cmat("dirt", Color(0.55, 0.47, 0.36), 1.0)
	var apron = G.cmat("apron", Color(0.42, 0.43, 0.45), 0.95)
	for i in 4:
		for j in 4:
			var x0: float = XR[i] + hw(XR[i])
			var x1: float = XR[i + 1] - hw(XR[i + 1])
			var z0: float = ZR[j] + hw(ZR[j])
			var z1: float = ZR[j + 1] - hw(ZR[j + 1])
			var r = Rect2(x0, z0, x1 - x0, z1 - z0)
			var dname = "downtown"
			var top: Material = conc
			if i == 0:
				dname = "hill" if j == 0 else ("park" if j == 3 else "residential")
				top = grass
			elif i == 3:
				dname = "industrial"
				top = lot if j != 3 else conc
			elif j == 0:
				dname = "civic"
				top = conc
			elif j == 3:
				dname = "southshore"
				top = grass if i == 1 else conc
			blocks.append({"rect": r, "i": i, "j": j, "district": dname})
			_slab(r, top)
	# outer strips
	_slab(Rect2(-300, -300, 600, 93), null, 0.0, apron)                 # airport (north)
	_slab(Rect2(-300, 207, 600, 7), null, 0.0, G.cmat("promenade", Color(0.76, 0.7, 0.6), 0.95))
	_slab(Rect2(-300, -207, 53, 414), null, 0.0, grass)                 # westwood
	_slab(Rect2(247, -207, 53, 414), null, 0.0, dirt)                   # rustyard
	# runway + apron paint
	var rw = G.cmat("runway", Color(0.16, 0.16, 0.18), 0.95)
	_box_mesh(Vector3(0, CURB + 0.006, RUNWAY_Z), Vector3(580, 0.012, 30), rw)
	_box_mesh(Vector3(150, CURB + 0.006, -232), Vector3(200, 0.012, 46), rw)
	# hill terrain
	_hill(grass)


func _hill(grass: Material) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 = -228.0
	var z0 = -188.0
	var nx = 48
	var nz = 38
	var step = 2.0
	var faces = PackedVector3Array()
	for ix in nx:
		for iz in nz:
			var a = Vector3(x0 + ix * step, 0, z0 + iz * step)
			var pts = [a, a + Vector3(step, 0, 0), a + Vector3(step, 0, step), a + Vector3(0, 0, step)]
			for k in 4:
				pts[k].y = CURB + 0.01 + hill_h(pts[k].x, pts[k].z)
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var n: Vector3 = (pts[tri[2]] - pts[tri[0]]).cross(pts[tri[1]] - pts[tri[0]]).normalized()
				var shade: float = clamp(n.y, 0.0, 1.0)
				var col = Color(0.3, 0.52, 0.26).lerp(Color(0.42, 0.66, 0.32), shade * shade)
				if pts[tri[0]].y > 12.0:
					col = col.lerp(Color(0.5, 0.62, 0.34), 0.5)
				for k in tri:
					st.set_normal(n)
					st.set_color(col)
					st.add_vertex(pts[k])
					faces.append(pts[k])
	var mi = MeshInstance3D.new()
	mi.mesh = st.commit()
	var m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	mi.material_override = m
	add_child(mi)
	var cs = CollisionShape3D.new()
	var shp = ConcavePolygonShape3D.new()
	shp.set_faces(faces)
	cs.shape = shp
	_static.add_child(cs)


func _q(c: Vector3, sx: float, sz: float, col: Color, yaw := 0.0) -> void:
	var b = Basis(Vector3.UP, yaw)
	var hx = b * Vector3(sx / 2, 0, 0)
	var hz = b * Vector3(0, 0, sz / 2)
	var p = [c - hx - hz, c + hx - hz, c + hx + hz, c - hx + hz]
	for k in [0, 1, 2, 0, 2, 3]:
		_mark.set_normal(Vector3.UP)
		_mark.set_color(col)
		_mark.add_vertex(p[k])


func _markings() -> void:
	_mark = SurfaceTool.new()
	_mark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white = Color(0.92, 0.92, 0.9)
	var yellow = Color(0.95, 0.78, 0.2)
	var y = 0.02
	for xr in XR:
		var h = hw(xr)
		var z = -200.0
		while z < 200.0:
			var near = false
			for zr in ZR:
				if abs(z + 1.5 - zr) < hw(zr) + 6.0:
					near = true
			if not near:
				if h > 8:
					_q(Vector3(xr - 0.2, y, z + 3), 0.14, 6, yellow)
					_q(Vector3(xr + 0.2, y, z + 3), 0.14, 6, yellow)
					_q(Vector3(xr - 5, y, z + 1.5), 0.14, 3, white)
					_q(Vector3(xr + 5, y, z + 1.5), 0.14, 3, white)
				else:
					_q(Vector3(xr, y, z + 1.5), 0.14, 3, yellow)
			z += 6.0
	for zr in ZR:
		var h = hw(zr)
		var x = -240.0
		while x < 240.0:
			var near = false
			for xr in XR:
				if abs(x + 1.5 - xr) < hw(xr) + 6.0:
					near = true
			if not near:
				if h > 8:
					_q(Vector3(x + 3, y, zr - 0.2), 6, 0.14, yellow)
					_q(Vector3(x + 3, y, zr + 0.2), 6, 0.14, yellow)
					_q(Vector3(x + 1.5, y, zr - 5), 3, 0.14, white)
					_q(Vector3(x + 1.5, y, zr + 5), 3, 0.14, white)
				else:
					_q(Vector3(x + 1.5, y, zr), 3, 0.14, yellow)
			x += 6.0
	# crosswalks + stop lines
	for xr in XR:
		for zr in ZR:
			var hx = hw(xr)
			var hz = hw(zr)
			for s in [-1.0, 1.0]:
				if abs(zr + s * 50) < 205:
					var n = int(hx * 2 / 1.2)
					for k in n:
						_q(Vector3(xr - hx + 0.6 + k * 1.2, y, zr + s * (hz + 2.2)), 0.6, 3.0, white)
					_q(Vector3(xr - s * hx / 2, y, zr + s * (hz + 4.6)), hx, 0.4, white)
				if abs(xr + s * 50) < 245:
					var n2 = int(hz * 2 / 1.2)
					for k in n2:
						_q(Vector3(xr + s * (hx + 2.2), y, zr - hz + 0.6 + k * 1.2), 3.0, 0.6, white)
					_q(Vector3(xr + s * (hx + 4.6), y, zr + s * hz / 2), 0.4, hz, white)
	# runway
	var ry = CURB + 0.02
	var x2 = -270.0
	while x2 < 270.0:
		_q(Vector3(x2, ry, RUNWAY_Z), 12, 0.5, white)
		x2 += 24.0
	for s in [-1.0, 1.0]:
		for k in 6:
			_q(Vector3(s * 280, ry, RUNWAY_Z - 10 + k * 4), 14, 1.6, white)
		_q(Vector3(0, ry, RUNWAY_Z + s * 14), 570, 0.3, white)
	# helipads
	for hp in [Vector3(95, ry, -232), Vector3(70, ry, -244)]:
		for k in 24:
			var a = k * TAU / 24
			_q(hp + Vector3(cos(a), 0, sin(a)) * 7.0, 1.9, 0.4, yellow, -a + PI / 2)
		_q(hp + Vector3(-1.4, 0, 0), 0.6, 4.4, white)
		_q(hp + Vector3(1.4, 0, 0), 0.6, 4.4, white)
		_q(hp, 2.8, 0.6, white)
	var mi = MeshInstance3D.new()
	mi.mesh = _mark.commit()
	var m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _water() -> void:
	var mi = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	pm.subdivide_width = 90
	pm.subdivide_depth = 90
	mi.mesh = pm
	mi.material_override = water_mat
	mi.position = Vector3(0, G.WATER_Y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------- buildings
func place(model: String, pos: Vector3, yaw := 0.0, folder := "buildings") -> Node3D:
	var n = G.model(folder + "/" + model)
	n.name = model + "_" + str(get_child_count())
	add_child(n)
	n.position = pos
	n.rotation.y = yaw
	G.remat(n, {"Window": window_mat, "GlassTower": tower_mat})
	var inf = G.info(model)
	if inf.has("col") or inf.has("ramps"):
		var sb = StaticBody3D.new()
		sb.collision_layer = G.L_WORLD
		sb.collision_mask = 0
		n.add_child(sb)
		for c in inf.get("col", []):
			_box_col(G.v3(c), G.v3(c, 3), sb)
		for r in inf.get("ramps", []):
			var a = G.v3(r)
			var b = G.v3(r, 3)
			var d = b - a
			var bs = Basis.looking_at(d.normalized(), Vector3.UP)
			_box_col((a + b) * 0.5 - bs.y * 0.15, Vector3(r[6], 0.3, d.length()), sb, bs)
	if folder == "buildings" and inf.has("min"):
		var mn = G.v3(inf.min)
		var mx = G.v3(inf.max)
		var rect = Rect2()
		var first = true
		for cx in [mn.x, mx.x]:
			for cz in [mn.z, mx.z]:
				var w: Vector3 = n.transform * Vector3(cx, 0, cz)
				if first:
					rect = Rect2(w.x, w.z, 0, 0)
					first = false
				else:
					rect = rect.expand(Vector2(w.x, w.z))
		occupied.append(rect)
		if mx.y > 1.0 and mx.y < 2.2:
			cover_boxes.append(rect)
	if not building_nodes.has(model):
		building_nodes[model] = n
	return n


func wpos(n: Node3D, key: String, model: String) -> Vector3:
	return n.transform * G.v3(G.info(model)[key])


func _row(i: int, j: int, side: String, models: Array, gap := 4.0, inset := 3.6, shift := 0.0) -> Array:
	var r: Rect2 = blocks[i * 4 + j].rect
	var total = 0.0
	for m in models:
		var inf = G.info(m)
		total += inf.max[0] - inf.min[0]
	total += gap * (models.size() - 1)
	var horizontal = side == "N" or side == "S"
	var mid: float = (r.position.x + r.size.x / 2) if horizontal else (r.position.y + r.size.y / 2)
	var cur = mid - total / 2 + shift
	var out = []
	for m in models:
		var inf = G.info(m)
		var w: float = inf.max[0] - inf.min[0]
		var cxl: float = (inf.max[0] + inf.min[0]) / 2
		var front: float = inf.max[2]
		var pos = Vector3.ZERO
		var yaw = 0.0
		match side:
			"S":
				pos = Vector3(cur + w / 2 - cxl, CURB, r.end.y - inset - front)
			"N":
				yaw = PI
				pos = Vector3(cur + w / 2 + cxl, CURB, r.position.y + inset + front)
			"E":
				yaw = PI / 2
				pos = Vector3(r.end.x - inset - front, CURB, cur + w / 2 + cxl)
			"W":
				yaw = -PI / 2
				pos = Vector3(r.position.x + inset + front, CURB, cur + w / 2 - cxl)
		out.append(place(m, pos, yaw))
		cur += w + gap
	return out


func add_interact(pos: Vector3, text: String, fn: Callable, r := 2.4, veh := false, icon := "") -> void:
	interacts.append({"pos": pos, "r": r, "text": text, "fn": fn, "veh": veh})
	if icon != "":
		map_icons.append({"pos": pos, "kind": icon, "name": text})


func _door(n: Node3D, model: String, text: String, fn: Callable, icon := "", loc := "") -> Vector3:
	var p = wpos(n, "door", model)
	add_interact(p, text, fn, 2.6, false, icon)
	if loc != "":
		locations[loc] = p
	_marker(p, Color(1.0, 0.8, 0.2))
	return p


func _marker(p: Vector3, col: Color) -> void:
	var mi = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 0.9
	cm.height = 0.04
	cm.radial_segments = 16
	mi.mesh = cm
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.2
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = p + Vector3(0, 0.05, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _layout_buildings() -> void:
	var b: Array
	# ---- Downtown NW (1,1)
	b = _row(1, 1, "S", ["tower_a", "hotel", "shop_food"])
	_door(b[0], "tower_a", "Take the elevator to the Cinder Spire roof", func(): G.player.teleport(b[0].position + Vector3(0, 72.3, 0)), "elevator", "Cinder Spire")
	add_interact(b[0].position + Vector3(0, 72.2, 9), "Take the elevator down", func(): G.player.teleport(wpos(b[0], "door", "tower_a")), 2.5)
	_marker(b[0].position + Vector3(0, 72.1, 9), Color(1, 0.8, 0.2))
	locations["Spire Roof"] = b[0].position + Vector3(0, 72.3, 0)
	_door(b[2], "shop_food", "Pita Stop — buy food", func(): G.menus.open_shop("food"), "food")
	b = _row(1, 1, "N", ["office_d", "bank", "shop_market", "shop_tattoo"])
	_door(b[1], "bank", "Cinder Trust ATM lobby", func(): G.menus.open_shop("atm"), "atm")
	_door(b[2], "shop_market", "24/7 Market — snacks & supplies", func(): G.menus.open_shop("market"), "food")
	_door(b[3], "shop_tattoo", "Ink Harbor — accessories", func(): G.menus.open_shop("accessories"), "clothes")
	_row(1, 1, "W", ["apartment_c"], 4.0, 3.6, -6.0)
	b = _row(1, 1, "E", ["shop_barber"], 4.0, 3.6, -8.0)
	_door(b[0], "shop_barber", "Clip Joint — hair & beard", func(): G.menus.open_shop("barber"), "barber", "Barber")
	# ---- Downtown NE (2,1)
	b = _row(2, 1, "S", ["shop_guns", "tower_b", "shop_clothes", "office_d"])
	_door(b[0], "shop_guns", "Brass Tack Arms — weapons, ammo, mods", func(): G.menus.open_shop("guns"), "gun", "Gun Shop")
	_door(b[2], "shop_clothes", "Thread Count — clothing", func(): G.menus.open_shop("clothes"), "clothes", "Clothing Store")
	b = _row(2, 1, "N", ["police_station", "parking_garage", "fire_station"])
	locations["Police Station"] = wpos(b[0], "door", "police_station")
	map_icons.append({"pos": locations["Police Station"], "kind": "police", "name": "Police Station"})
	add_interact(locations["Police Station"], "Front desk — pay fines / clear record", func(): G.menus.open_shop("police"), 2.6)
	_marker(locations["Police Station"], Color(0.3, 0.5, 1.0))
	locations["Parking Garage"] = wpos(b[1], "door", "parking_garage")
	add_interact(locations["Parking Garage"], "Vehicle terminal — request a land vehicle", func(): G.menus.open_spawner("land", locations["Parking Garage"] + Vector3(0, 0.5, 9)), 3.0, false, "garage")
	_marker(locations["Parking Garage"], Color(0.3, 1.0, 0.5))
	locations["Fire Station"] = wpos(b[2], "door", "fire_station")
	# ---- Downtown SW (1,2)
	_row(1, 2, "N", ["tower_c", "apartment_b", "office_d"], 8.0)
	_row(1, 2, "S", ["apartment_a", "apartment_c", "house_d"], 8.0)
	# ---- Downtown SE (2,2)
	_row(2, 2, "N", ["office_d", "tower_c", "apartment_b"], 8.0, 3.6, 14.0)
	b = _row(2, 2, "S", ["apartment_a", "shop_market", "apartment_c"], 8.0)
	_door(b[1], "shop_market", "24/7 Market — snacks & supplies", func(): G.menus.open_shop("market"), "food")
	# ---- Civic north (1,0) (2,0)
	_row(1, 0, "S", ["apartment_a", "tower_b", "apartment_c"], 8.0)
	_row(1, 0, "N", ["apartment_b", "office_d"], 20.0)
	b = _row(2, 0, "S", ["hospital", "apartment_b"], 14.0)
	var hp = _door(b[0], "hospital", "St. Ember Medical — treatment", func(): G.menus.open_shop("hospital"), "hospital", "Hospital")
	locations["Hospital"] = hp + Vector3(0, 0, 3)
	_row(2, 0, "N", ["apartment_c", "apartment_a"], 20.0)
	place("water_tower", Vector3(60, CURB, -150), 0.0)
	place("billboard", Vector3(20, CURB, -150), PI / 2)
	# ---- Residential (0,1) (0,2) (0,3)
	_row(0, 1, "N", ["house_a", "house_b", "house_c", "house_d", "house_a", "house_b"], 6.0)
	_row(0, 1, "S", ["house_c", "house_d", "house_a", "house_b", "house_c", "house_d"], 6.0)
	b = _row(0, 2, "N", ["house_b", "house_d", "safehouse", "house_c", "apartment_c"], 6.0)
	var sh: Node3D = b[2]
	locations["Safehouse"] = wpos(sh, "door", "safehouse")
	locations["SafehouseInside"] = wpos(sh, "inside", "safehouse") + Vector3(0, 0.1, 0)
	map_icons.append({"pos": locations["Safehouse"], "kind": "home", "name": "Safehouse"})
	add_interact(wpos(sh, "wardrobe", "safehouse"), "Wardrobe — change outfit", func(): G.menus.open_shop("wardrobe"), 2.0)
	add_interact(wpos(sh, "bed", "safehouse"), "Bed — sleep (save & advance 8h)", func(): G.menus.sleep(), 2.0)
	var gpos: Vector3 = locations["Safehouse"] + Vector3(9, 0, -1)
	add_interact(gpos, "Home garage — store / retrieve vehicles", func(): G.menus.open_garage(gpos + Vector3(0, 0.3, -6)), 3.0, true, "garage")
	_marker(gpos, Color(0.3, 1.0, 0.5))
	var sl = OmniLight3D.new()
	sl.position = wpos(sh, "inside", "safehouse") + Vector3(0, 2.6, 0)
	sl.light_color = Color(1, 0.9, 0.75)
	sl.omni_range = 9.0
	sl.light_energy = 1.2
	add_child(sl)
	_row(0, 2, "S", ["house_a", "house_c", "house_b", "house_d", "house_a"], 8.0)
	_row(0, 3, "N", ["house_d", "house_a", "house_b", "house_c"], 12.0)
	place("gazebo", Vector3(-180, CURB, 160), 0.0)
	# ---- Southshore (1,3) (2,3)
	b = _row(1, 3, "S", ["apartment_b", "shop_food", "apartment_c", "house_c"], 8.0)
	_door(b[1], "shop_food", "Pita Stop — buy food", func(): G.menus.open_shop("food"), "food")
	_row(1, 3, "N", ["apartment_a", "house_a", "house_d", "house_b"], 8.0)
	b = _row(2, 3, "S", ["gas_station", "apartment_a", "house_b"], 14.0)
	var pumps = wpos(b[0], "pumps", "gas_station")
	locations["Gas Station"] = pumps
	add_interact(pumps, "Sunbelt Fuel — quick service (repair tyres, top up)", func(): G.menus.open_shop("gas"), 4.5, true, "gas")
	_row(2, 3, "N", ["apartment_c", "office_d", "house_c"], 10.0)
	# ---- Ironside industrial (3,1) (3,2) (3,3) (3,0)
	b = _row(3, 1, "W", ["shop_mods"], 4.0, 6.0, 4.0)
	var bay = wpos(b[0], "bay", "shop_mods")
	locations["Torque Bay"] = wpos(b[0], "door", "shop_mods")
	add_interact(bay, "Torque Bay — repair & customise vehicle", func(): G.menus.open_mods(), 4.0, true, "mods")
	var gl = OmniLight3D.new()
	gl.position = bay + Vector3(0, 4.6, 0)
	gl.omni_range = 14.0
	gl.light_energy = 1.5
	add_child(gl)
	_row(3, 1, "N", ["warehouse_a"], 4.0, 3.6, 20.0)
	_row(3, 1, "S", ["factory"], 4.0, 3.6, 16.0)
	_row(3, 1, "E", ["warehouse_b"], 4.0, 3.6, -6.0)
	_row(3, 2, "N", ["warehouse_b", "warehouse_a"], 14.0)
	place("silo", Vector3(150, CURB, 70), 0.0)
	place("silo", Vector3(162, CURB, 70), 0.0)
	place("silo", Vector3(156, CURB, 82), 0.0)
	_row(3, 2, "E", ["warehouse_b"], 4.0, 3.6, 22.0)
	_row(3, 3, "N", ["warehouse_a", "warehouse_b"], 14.0)
	place("crane", Vector3(190, CURB, 196), 0.0)
	place("crane", Vector3(150, CURB, 196), 0.0)
	_row(3, 0, "S", ["warehouse_a"], 4.0, 3.6, -30.0)
	# ---- Airport
	b = [place("terminal", Vector3(10, CURB, -222), 0.0), place("hangar", Vector3(170, CURB, -228), PI), place("control_tower", Vector3(232, CURB, -222), 0.0)]
	locations["Airfield"] = Vector3(120, CURB, -238)
	locations["Runway West"] = Vector3(-262, CURB, RUNWAY_Z)
	locations["Hangar"] = Vector3(170, CURB, -248)
	locations["Helipad"] = Vector3(95, CURB, -232)
	var term = Vector3(128, CURB, -214)
	add_interact(term, "Airfield terminal — request an aircraft", func(): G.menus.open_spawner("air", Vector3(95, CURB + 0.5, -232)), 3.0, false, "air")
	_marker(term, Color(0.3, 1.0, 0.5))
	# ---- Waterfront
	for k in 4:
		place("pier", Vector3(40, CURB, 220 + k * 12), 0.0)
		place("pier", Vector3(100, CURB, 220 + k * 12), 0.0)
	for k in 6:
		place("pier", Vector3(-80, CURB, 226 + k * 12), 0.0)
	place("lighthouse", Vector3(-80, CURB, 300), 0.0)
	_box_col(Vector3(-80, -4.5, 300), Vector3(8, 9.4, 8))
	_box_mesh(Vector3(-80, -4.5, 300), Vector3(8, 9.4, 8), G.cmat("seawall", Color(0.5, 0.5, 0.48)))
	place("lifeguard_tower", Vector3(-190, CURB - 0.5, 222), PI)
	locations["Marina"] = Vector3(40, CURB, 250)
	locations["Beach"] = Vector3(-170, CURB, 211)
	locations["Docks"] = Vector3(170, CURB, 205)
	var mar = Vector3(40, CURB, 216)
	add_interact(mar, "Marina terminal — request a boat", func(): G.menus.open_spawner("water", Vector3(52, G.WATER_Y + 0.6, 244)), 3.0, false, "boat")
	_marker(mar, Color(0.3, 1.0, 0.5))
	# ---- Metro track + stations along the z=0 avenue
	for sx in [-180.0, 60.0, 180.0]:
		var st = place("metro_station", Vector3(sx, 0, 0), PI)
		occupied.pop_back()
		locations["Metro " + ("West" if sx < -100 else ("Central" if sx < 100 else "East"))] = st.transform * G.v3(G.info("metro_station").platform)
		map_icons.append({"pos": Vector3(sx, 0, 0), "kind": "metro", "name": "Metro"})
	var x = -220.0
	while x <= 221.0:
		var tb = place("track_beam", Vector3(x, 0, 0), 0.0)
		occupied.pop_back()
		var px = x
		for xr in XR:
			if abs(px - xr) < hw(xr) + 1.5:
				px = xr + hw(xr) + 2.0
		var tp = place("track_pillar", Vector3(px, 0, 0), 0.0)
		occupied.pop_back()
		x += 20.0
	locations["Signal Hill"] = Vector3(-180, CURB + 15.2, -150)
	place("gazebo", Vector3(-180, CURB + 15.0, -150), 0.0)
	locations["Downtown"] = Vector3(-6, 0.1, -6)
	locations["Ironside"] = Vector3(124, 0.1, -50)
	locations["Larkspur"] = Vector3(-124, 0.1, 50)
	locations["Rustyard"] = Vector3(272, CURB, 0)
	locations["Westwood"] = Vector3(-272, CURB, 40)
	locations["Shooting Range"] = Vector3(200, CURB, -140)
	locations["Wreck Dive"] = Vector3(-200, G.WATER_Y, 330)


# ---------------------------------------------------------------- props
func free_at(x: float, z: float, r := 1.0) -> bool:
	if not LAND.has_point(Vector2(x, z)):
		return false
	for o in occupied:
		if o.grow(r).has_point(Vector2(x, z)):
			return false
	return not on_road(x, z, r * 0.5)


func prop(model: String, pos: Vector3, yaw := 0.0, force_static := false) -> Node3D:
	var inf = G.info(model)
	var vis = G.model("props/" + model)
	vis.rotation.y = 0
	var body: Node3D
	if inf.has("dynamic") and not force_static:
		var rb = RigidBody3D.new()
		rb.mass = inf.dynamic
		rb.collision_layer = G.L_PROP
		rb.collision_mask = G.L_WORLD | G.L_VEH | G.L_PROP | G.L_CHAR
		rb.sleeping = true
		rb.set_meta("prop", model)
		if inf.has("explosive"):
			rb.set_script(preload("res://gta/code/world/explosive_prop.gd"))
		body = rb
	elif inf.get("col", []).size() > 0:
		var sb = StaticBody3D.new()
		sb.collision_layer = G.L_WORLD
		sb.collision_mask = 0
		if inf.has("knock"):
			sb.set_meta("knock", model)
		body = sb
	else:
		body = Node3D.new()
	add_child(body)
	body.position = pos
	body.rotation.y = yaw
	body.add_child(vis)
	if not inf.has("light") and not model in ["tree_a", "tree_b", "pine", "palm", "wreck", "rock_b", "traffic_light", "bus_stop", "stunt_ramp", "ladder"]:
		for mi in G.meshes(vis):
			mi.visibility_range_end = 190.0
			mi.visibility_range_end_margin = 15.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for c in inf.get("col", []):
		_box_col(G.v3(c), G.v3(c, 3), body)
	for r in inf.get("ramps", []):
		var sb2 = StaticBody3D.new()
		sb2.collision_layer = G.L_WORLD
		body.add_child(sb2)
		var a = G.v3(r)
		var b = G.v3(r, 3)
		var d = b - a
		var bs = Basis.looking_at(d.normalized(), Vector3.UP)
		_box_col((a + b) * 0.5 - bs.y * 0.15, Vector3(r[6], 0.3, d.length()), sb2, bs)
	if inf.has("light"):
		lamps.append(body.transform * G.v3(inf.light))
	return body


## Convert a knockable static prop into a tumbling rigid body (called by vehicles on impact).
func knock(sb: Node3D, impulse: Vector3) -> void:
	if not is_instance_valid(sb) or not sb.has_meta("knock"):
		return
	var model: String = sb.get_meta("knock")
	var t = sb.global_transform
	var rb = RigidBody3D.new()
	rb.mass = 60.0
	rb.collision_layer = G.L_PROP
	rb.collision_mask = G.L_WORLD | G.L_VEH | G.L_PROP
	add_child(rb)
	rb.global_transform = t
	for c in sb.get_children():
		sb.remove_child(c)
		rb.add_child(c)
	sb.queue_free()
	rb.apply_central_impulse(impulse * 0.5 + Vector3.UP * 60.0)
	rb.apply_torque_impulse(Vector3(G.rng.randf_range(-40, 40), 0, G.rng.randf_range(-40, 40)))
	if G.info(model).has("hydrant") and G.fx:
		G.fx.geyser(t.origin)
	if G.audio:
		G.audio.play3d("metal", t.origin, -4.0)
	get_tree().create_timer(30.0).timeout.connect(func(): if is_instance_valid(rb): rb.queue_free())


func _multimesh(model: String, xforms: Array) -> void:
	if xforms.is_empty():
		return
	var src = G.model("props/" + model)
	var mis = G.meshes(src)
	for mi in mis:
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mi.mesh
		mm.instance_count = xforms.size()
		for k in xforms.size():
			mm.set_instance_transform(k, xforms[k] * mi.transform)
		var mmi = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 260.0
		add_child(mmi)
	src.queue_free()


func _props() -> void:
	# street lamps + roadside furniture
	var furniture = ["bin", "bench", "hydrant", "newsbox", "mailbox", "parking_meter", "planter", "utility_box"]
	for xr in XR:
		var z = -185.0
		var k = 0
		while z < 190.0:
			var skip = false
			for zr in ZR:
				if abs(z - zr) < hw(zr) + 8:
					skip = true
			if not skip:
				var s = -1.0 if k % 2 == 0 else 1.0
				prop("street_lamp", Vector3(xr + s * (hw(xr) + 0.9), CURB, z), -s * PI / 2)
				var fz = z + 9.0
				if abs(xr) < 200 and rng.randf() < 0.7:
					var f: String = furniture[rng.randi() % furniture.size()]
					prop(f, Vector3(xr - s * (hw(xr) + 1.1), CURB, fz), -s * PI / 2 + PI)
			z += 28.0
			k += 1
	for zr in ZR:
		var x = -225.0
		var k = 0
		while x < 230.0:
			var skip = false
			for xr in XR:
				if abs(x - xr) < hw(xr) + 8:
					skip = true
			for sx in [-180.0, 60.0, 180.0]:
				if zr == 0.0 and abs(x - sx) < 14:
					skip = true
			if not skip:
				var s = -1.0 if k % 2 == 0 else 1.0
				prop("street_lamp", Vector3(x, CURB, zr + s * (hw(zr) + 0.9)), PI if s > 0 else 0.0)
				if rng.randf() < 0.7:
					var f: String = furniture[rng.randi() % furniture.size()]
					prop(f, Vector3(x + 9.0, CURB, zr - s * (hw(zr) + 1.1)), 0.0 if s > 0 else PI)
			x += 28.0
			k += 1
	# traffic signals at the nine inner intersections
	for xr in [-120.0, 0.0, 120.0]:
		for zr in [-100.0, 0.0, 100.0]:
			var sig = {"x": xr, "z": zr, "pos": Vector3(xr, 0, zr), "ns": [], "ew": [], "phase": rng.randf() * 30.0, "state": 0}
			for q in 4:
				var yaw = q * PI / 2
				var lat: float = hw(xr) if q % 2 == 0 else hw(zr)
				var lon: float = hw(zr) if q % 2 == 0 else hw(xr)
				var off = Basis(Vector3.UP, yaw) * Vector3(lat + 0.8, 0, lon + 0.8)
				var tl = prop("traffic_light", Vector3(xr, CURB, zr) + off, yaw)
				(sig.ns if q % 2 == 0 else sig.ew).append(tl)
			signals.append(sig)
	# stop signs on ring intersections, speed signs
	for xr in XR:
		for zr in ZR:
			if abs(xr) == 240.0 or abs(zr) == 200.0:
				prop("sign_stop", Vector3(xr + hw(xr) + 0.7, CURB, zr + hw(zr) + 0.7), 0.0)
	for z in [-150.0, 50.0]:
		prop("sign_speed", Vector3(247.8, CURB, z), 0.0)
		prop("sign_speed", Vector3(-247.8, CURB, z + 20), PI)
	# bus stops
	for p in [[-60, 11.6, 0.0], [70, -11.6, PI], [-131, 50, PI / 2], [131, -40, -PI / 2], [-60, 208.6, 0.0], [60, -108.6, PI]]:
		prop("bus_stop", Vector3(p[0], CURB, p[1]), p[2] + PI)
	# trees / vegetation
	var grass_x = []
	var bush_x = []
	var flower_x = []
	for blk in blocks:
		var r: Rect2 = blk.rect
		var dn: String = blk.district
		var count = 0
		match dn:
			"residential": count = 34
			"park": count = 60
			"hill": count = 55
			"southshore": count = 20
			"downtown", "civic": count = 10
			_: count = 3
		for n in count:
			var x = rng.randf_range(r.position.x + 5, r.end.x - 5)
			var z = rng.randf_range(r.position.y + 5, r.end.y - 5)
			if dn == "downtown" or dn == "civic":
				# street trees on the sidewalk ring
				if rng.randf() < 0.5:
					x = r.position.x + 1.6 if rng.randf() < 0.5 else r.end.x - 1.6
				else:
					z = r.position.y + 1.6 if rng.randf() < 0.5 else r.end.y - 1.6
			if not free_at(x, z, 2.0):
				continue
			var y = CURB + (hill_h(x, z) if dn == "hill" else 0.0)
			if dn == "hill" and Vector2(x + 180, z + 150).length() < 9:
				continue
			var t = "tree_a"
			var rr = rng.randf()
			if dn == "hill":
				t = "pine" if rr < 0.6 else "tree_b"
			elif dn == "southshore":
				t = "palm"
			elif rr < 0.3:
				t = "tree_b"
			var tn = prop(t, Vector3(x, y, z), rng.randf() * TAU)
			tn.scale = Vector3.ONE * rng.randf_range(0.85, 1.25)
			if dn in ["residential", "park", "hill"]:
				for g in 5:
					var gx = x + rng.randf_range(-6, 6)
					var gz = z + rng.randf_range(-6, 6)
					if free_at(gx, gz, 1.0) and r.grow(-3.5).has_point(Vector2(gx, gz)):
						var gy = CURB + (hill_h(gx, gz) if dn == "hill" else 0.0)
						var tx = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.6)), Vector3(gx, gy, gz))
						if g == 0:
							bush_x.append(tx)
						elif g == 1 and dn != "hill":
							flower_x.append(tx)
						else:
							grass_x.append(tx)
	# Westwood woodland
	for n in 150:
		var x = rng.randf_range(-298, -250)
		var z = rng.randf_range(-204, 204)
		var rr = rng.randf()
		if rr < 0.55:
			var tn = prop("pine" if rng.randf() < 0.6 else "tree_b", Vector3(x, CURB, z), rng.randf() * TAU)
			tn.scale = Vector3.ONE * rng.randf_range(0.9, 1.5)
		elif rr < 0.63:
			prop("rock_a" if rng.randf() < 0.7 else "rock_b", Vector3(x, CURB, z), rng.randf() * TAU)
		elif rr < 0.67:
			prop("log", Vector3(x, CURB, z), rng.randf() * TAU)
		elif rr < 0.8:
			bush_x.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, CURB, z)))
		else:
			grass_x.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 1.5), Vector3(x, CURB, z)))
	# promenade palms, beach furniture
	var px = -290.0
	while px < 295.0:
		if abs(px - 40) > 6 and abs(px - 100) > 6 and abs(px + 80) > 6:
			prop("palm", Vector3(px, CURB, 211.5), rng.randf() * TAU)
		px += 22.0
	for n in 16:
		var x = rng.randf_range(-290, -10)
		if abs(x + 80) < 8 or abs(x + 190) < 8:
			continue
		var z = rng.randf_range(219, 232)
		var y = lerpf(CURB, -9.0, (z - 214.0) / 70.0)
		prop("umbrella", Vector3(x, y, z), 0.0)
		prop("sunbed", Vector3(x + 1.2, y - 0.1, z + 0.5), rng.randf_range(2.6, 3.6)).rotation.x = 0.13
	for p in [[-150, 300], [-20, 320], [140, 290], [-260, 290], [70, 300], [320, 100], [-330, -50], [0, -330]]:
		var bn = prop("buoy", Vector3(p[0], G.WATER_Y, p[1]), 0.0)
	# underwater exploration
	prop("wreck", Vector3(-200, -9.2, 330), 0.5).rotation.z = 0.25
	prop("wreck", Vector3(360, -9.0, 60), 2.0).rotation.z = -0.2
	for n in 60:
		var a = rng.randf() * TAU
		var d = rng.randf_range(330, 430)
		var x = cos(a) * d
		var z = sin(a) * d * 0.8 + 20
		if z < 290 and abs(x) < 310:
			continue
		prop("coral" if n % 2 == 0 else "seaweed", Vector3(x, -9.0, z), rng.randf() * TAU).scale = Vector3.ONE * rng.randf_range(1.0, 2.2)
	for n in 14:
		prop("rock_b", Vector3(rng.randf_range(-280, 280), -9.2, rng.randf_range(292, 380)), rng.randf() * TAU)
		prop("coral", Vector3(-200 + rng.randf_range(-18, 18), -9.0, 330 + rng.randf_range(-18, 18)), rng.randf() * TAU)
	# industrial yard dressing
	var cont_cols = [Color(0.75, 0.25, 0.2), Color(0.2, 0.4, 0.7), Color(0.85, 0.65, 0.15), Color(0.25, 0.55, 0.4), Color(0.6, 0.6, 0.62)]
	var cpos = []
	for n in 9:
		cpos.append(Vector3(255 + (n % 3) * 3.2, CURB, 120 + int(n / 3) * 7.5))
		cpos.append(Vector3(275 + (n % 3) * 3.2, CURB, -80 + int(n / 3) * 7.5))
	for n in 8:
		cpos.append(Vector3(135 + n * 3.4, CURB, 150))
		cpos.append(Vector3(205 + (n % 4) * 3.4, CURB, 176 - int(n / 4) * 7))
	for cp in cpos:
		for lv in (2 if rng.randf() < 0.45 else 1):
			var c = place("container", cp + Vector3(0, lv * 2.6, 0), 0.0)
			G.remat(c, {"Paint": G.cmat("cont%d" % (rng.randi() % 5), cont_cols[rng.randi() % 5], 0.7, 0.2)})
	for n in 46:
		var x = rng.randf_range(124, 296)
		var z = rng.randf_range(-190, 205)
		if not free_at(x, z, 2.5):
			continue
		var kind: String = ["crate", "barrel", "tire_stack", "dumpster", "crate", "cone", "barrel"][rng.randi() % 7]
		prop(kind, Vector3(x, CURB + 0.02, z), rng.randf() * TAU)
		if kind == "crate" and rng.randf() < 0.5:
			prop("crate", Vector3(x + 1.0, CURB + 0.02, z + 0.3), rng.randf() * TAU)
	for n in 18:
		var blk: Dictionary = blocks[[5, 6, 9, 10][n % 4]]
		var r: Rect2 = blk.rect
		var x = rng.randf_range(r.position.x + 20, r.end.x - 20)
		var z = rng.randf_range(r.position.y + 30, r.end.y - 30)
		if free_at(x, z, 2.5):
			prop(["dumpster", "crate", "vending", "barrel"][n % 4], Vector3(x, CURB + 0.02, z), rng.randf() * TAU)
	# vending machines / ATMs (interactive)
	for p in [[-14, -30, PI / 2], [14, 40, -PI / 2], [-60, 14.5, 0.0], [116, -60, PI / 2], [-126.5, 20, -PI / 2]]:
		var pos = Vector3(p[0], CURB, p[1])
		prop("vending", pos, p[2])
		add_interact(pos + Basis(Vector3.UP, p[2]) * Vector3(0, 0, 1.0), "Vending machine — soda ($5, +15 health)", func(): G.menus.quick_buy("soda"), 1.8)
	for p in [[30, -14.4, 0.0], [-100, 14.4, PI], [126.4, 60, -PI / 2]]:
		var pos = Vector3(p[0], CURB, p[1])
		prop("atm", pos, p[2] + PI)
		add_interact(pos + Basis(Vector3.UP, p[2]) * Vector3(0, 0, -1.0), "ATM — account & stats", func(): G.menus.open_shop("atm"), 1.8, false, "atm")
	# airport fence with gaps, barriers
	var fx = -296.0
	while fx < 296.0:
		if abs(fx - 10) > 22 and abs(fx - 125) > 10 and abs(fx + 180) > 8:
			prop("fence_chain", Vector3(fx + 1.5, CURB, -207.6), 0.0)
		fx += 3.0
	for k in 10:
		prop("barrier", Vector3(-250 + k * 3.1, CURB, -256.5), 0.0)
	# shooting range (Ironside north block)
	var sr: Vector3 = locations["Shooting Range"]
	for k in 5:
		prop("barrier", Vector3(sr.x - 8 + k * 4, CURB, sr.z + 3), 0.0)
	prop("gun_rack", sr + Vector3(-11, 0, 5), PI / 2)
	# stunt ramps
	for p in [[272, -150, 0.0], [272, 60, PI], [-272, -120, PI], [150, 222, PI], [0, 204, PI / 2], [-262, -274, PI / 2], [200, -100, -PI / 2]]:
		var sp = prop("stunt_ramp", Vector3(p[0], CURB if abs(p[1]) > 207 or abs(p[0]) > 247 else 0.0, p[1]), p[2])
		map_icons.append({"pos": sp.position, "kind": "stunt", "name": "Stunt ramp"})
	# ladders (warehouse roofs + lighthouse pier)

	for bn in get_children():
		if String(bn.name).begins_with("warehouse_a"):
			var inf = G.info("warehouse_a")
			var lp: Vector3 = bn.transform * Vector3(inf.max[0] + 0.25, 0, 0)
			_ladder(Vector3(lp.x, CURB, lp.z), bn.rotation.y - PI / 2, 9.6)
	# picnic + park dressing
	for n in 10:
		var x = rng.randf_range(-228, -132)
		var z = rng.randf_range(135, 190)
		if free_at(x, z, 2.5):
			prop("picnic_table" if n % 2 == 0 else "bench", Vector3(x, CURB, z), rng.randf() * TAU)
	# residential fences
	for blk in blocks:
		if blk.district != "residential":
			continue
		var r: Rect2 = blk.rect
		var zc = r.position.y + r.size.y / 2
		var x = r.position.x + 8
		while x < r.end.x - 8:
			prop("fence_wood", Vector3(x + 1.5, CURB, zc), 0.0)
			x += 3.0
	_multimesh("grass", grass_x)
	_multimesh("bush", bush_x)
	_multimesh("flowers", flower_x)
	# parking spots (kerbside + lots)
	for zr in [-100.0, 100.0]:
		for x in [-200.0, -170.0, -80.0, -50.0, 40.0, 75.0, 160.0, 195.0]:
			parking.append({"pos": Vector3(x, 0.4, zr + 5.6), "yaw": -PI / 2})
			parking.append({"pos": Vector3(x + 12, 0.4, zr - 5.6), "yaw": PI / 2})
	for xr in [-120.0, 120.0]:
		for z in [-160.0, -60.0, 40.0, 150.0]:
			parking.append({"pos": Vector3(xr + 5.6, 0.4, z), "yaw": 0.0})
			parking.append({"pos": Vector3(xr - 5.6, 0.4, z + 14), "yaw": PI})
	for k in 5:
		parking.append({"pos": Vector3(150 + k * 4, 0.6, -150), "yaw": 0.0})
		parking.append({"pos": Vector3(262, 0.6, -20 + k * 5), "yaw": PI / 2})


func _ladder(base: Vector3, yaw: float, height: float) -> void:
	var l = prop("ladder", base, yaw)
	l.scale.y = height / 6.4
	var dir = Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)
	ladders.append({"pos": base - dir * 0.5, "top": base + Vector3(0, height + 0.2, 0) + dir * 0.8, "dir": dir, "h": height})


# ---------------------------------------------------------------- pedestrians / navigation
func _ped_graph() -> void:
	var owner_block = []
	for bi in blocks.size():
		var r: Rect2 = blocks[bi].rect
		var base = ped_nodes.size()
		var c = [Vector3(r.position.x + 1.5, CURB, r.position.y + 1.5), Vector3(r.end.x - 1.5, CURB, r.position.y + 1.5),
			Vector3(r.end.x - 1.5, CURB, r.end.y - 1.5), Vector3(r.position.x + 1.5, CURB, r.end.y - 1.5)]
		# add mid-edge nodes for more variety
		var pts = []
		for k in 4:
			pts.append(c[k])
			pts.append((c[k] + c[(k + 1) % 4]) * 0.5)
		for k in pts.size():
			ped_nodes.append(pts[k])
			owner_block.append(bi)
			ped_links.append([base + (k + 1) % pts.size(), base + (k + pts.size() - 1) % pts.size()])
	for a in ped_nodes.size():
		for b in range(a + 1, ped_nodes.size()):
			if owner_block[a] == owner_block[b]:
				continue
			var d: Vector3 = ped_nodes[a] - ped_nodes[b]
			if d.length() < 26.0 and (abs(d.x) < 1.0 or abs(d.z) < 1.0):
				ped_links[a].append(b)
				ped_links[b].append(a)
	# promenade walk
	var prev = -1
	var x = -280.0
	while x <= 280.0:
		ped_nodes.append(Vector3(x, CURB, 210.5))
		ped_links.append([])
		var id = ped_nodes.size() - 1
		if prev >= 0:
			ped_links[id].append(prev)
			ped_links[prev].append(id)
		prev = id
		x += 80.0


var nav_region: NavigationRegion3D
var nav_ready := false


func _nav() -> void:
	nav_region = NavigationRegion3D.new()
	var nm = NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = G.L_WORLD
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = "navsrc"
	add_to_group("navsrc")
	nm.cell_size = 0.5
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 40.0
	nm.filter_baking_aabb = AABB(Vector3(-302, -1, -302), Vector3(604, 24, 520))
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	nav_region.bake_finished.connect(func(): nav_ready = true; print("[world] navmesh baked, polys=", nm.get_polygon_count()))
	nav_region.bake_navigation_mesh.call_deferred(true)


func nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not nav_ready:
		return PackedVector3Array([from, to])
	return NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, to, true)


func update_signals(dt: float) -> void:
	for s in signals:
		s.phase = fmod(s.phase + dt, 30.0)
		var st = 0   # 0 NS green, 1 NS yellow, 2 EW green, 3 EW yellow
		if s.phase < 12.0:
			st = 0
		elif s.phase < 15.0:
			st = 1
		elif s.phase < 27.0:
			st = 2
		else:
			st = 3
		if st != s.state or not s.has("init"):
			s.state = st
			s["init"] = true
			for tl in s.ns:
				_set_light(tl, "G" if st == 0 else ("Y" if st == 1 else "R"))
			for tl in s.ew:
				_set_light(tl, "G" if st == 2 else ("Y" if st == 3 else "R"))


func _set_light(tl, which: String) -> void:
	if not is_instance_valid(tl):
		return
	for k in ["R", "Y", "G"]:
		var n = G.part(tl, "_Lit" + k)
		if n:
			n.visible = k == which


## 0 = go, 1 = stop for a vehicle travelling along axis ("ns"/"ew") near intersection (x,z)
func signal_stop(x: float, z: float, ns: bool) -> bool:
	for s in signals:
		if s.x == x and s.z == z:
			return (s.state != 0) if ns else (s.state != 2)
	return false
