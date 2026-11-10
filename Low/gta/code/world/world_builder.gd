class_name WorldBuilder
extends Node3D
# Builds the compact ~600x600 m island: terrain, road plate, blocks, Blender buildings/props, water, nav.

const SLAB_Y := 0.18
const PLATE_Y := 0.04

var rects: Array = []          # occupied building footprints (Rect2 in XZ)
var rnd := RandomNumberGenerator.new()
var interacts: Array = []      # {pos, radius, label, action, veh, node}
var pickups: Array = []        # {node, pos, type, amount, t}
var prop_grid: Dictionary = {}
var awake_props: Array = []
var lamp_points: Array = []
var parking_spots: Array = []  # [Vector3, yaw]
var ladders: Array = []        # {pos, top, dir}
var cover_points: Array = []
var stunt_zones: Array = []
var mat_road: StandardMaterial3D
var mat_slab: StandardMaterial3D
var nav_region: NavigationRegion3D
var nav_ready := false
var _shape_cache: Dictionary = {}
var _static: StaticBody3D
var _mm: Dictionary = {}
var _tl_t := 0.0
var _marker_mesh: Mesh


static func smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static func height(x: float, z: float) -> float:
	var h := 0.0
	var hz: float = clamp(1.0 - abs(z + 256.0) / 36.0, 0.0, 1.0)
	var hx: float = clamp(min(x + 285.0, 128.0 - x) / 50.0, 0.0, 1.0)
	h += 24.0 * smooth(hz) * smooth(hx) * (0.8 + 0.2 * sin(x * 0.045))
	var e: float = max(max(abs(x) - 288.0, -292.0 - z), 0.0)
	h -= e * 0.5
	var s: float = max(z - 204.0, 0.0)
	h -= s * 0.1 + max(z - 236.0, 0.0) * 0.45
	return max(h, -14.0)


func build() -> void:
	rnd.seed = 5207
	_static = StaticBody3D.new()
	add_child(_static)
	mat_road = G.flat_mat(Color(0.17, 0.18, 0.2), 0.85)
	mat_slab = G.flat_mat(Color(0.52, 0.51, 0.49), 0.9)
	var mm := CylinderMesh.new()
	mm.top_radius = 0.75
	mm.bottom_radius = 0.75
	mm.height = 0.06
	mm.radial_segments = 20
	_marker_mesh = mm
	_terrain()
	_plates()
	_markings()
	_water()
	_landmarks()
	_fill_blocks()
	_street_furniture()
	_airport()
	_waterfront()
	_nature()
	_extras()
	_flush_multimeshes()
	_nav()


# ---------------------------------------------------------------- geometry helpers
func box_static(center: Vector3, size: Vector3, mat: Material = null, collide := true) -> void:
	if mat:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		mi.position = center
		add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = center
		_static.add_child(cs)


func quad(st: SurfaceTool, cx: float, cz: float, sx: float, sz: float, y: float) -> void:
	var x0 := cx - sx / 2
	var x1 := cx + sx / 2
	var z0 := cz - sz / 2
	var z1 := cz + sz / 2
	st.set_normal(Vector3.UP)
	for v in [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]:
		st.add_vertex(v)


func commit(st: SurfaceTool, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _terrain() -> void:
	var n := 144
	var size := 900.0
	var cell := size / n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var data := PackedFloat32Array()
	data.resize((n + 1) * (n + 1))
	for zi in n + 1:
		for xi in n + 1:
			var x := -size / 2 + xi * cell
			var z := -size / 2 + zi * cell
			var h := height(x, z)
			data[zi * (n + 1) + xi] = h
			var c := Color(0.29, 0.46, 0.24)
			if h < -0.2 or z > 172.0 or abs(x) > 284.0 or z < -289.0:
				c = Color(0.62, 0.55, 0.39)
			if h < -2.0:
				c = Color(0.55, 0.6, 0.5).lerp(Color(0.2, 0.3, 0.35), clamp(-h / 14.0, 0.0, 1.0))
			elif h > 6.0:
				c = Color(0.29, 0.46, 0.24).lerp(Color(0.24, 0.36, 0.22), clamp((h - 6.0) / 14.0, 0.0, 1.0))
			c = c.darkened(0.06 * sin(x * 0.7) * cos(z * 0.9) + 0.03)
			st.set_color(c)
			st.add_vertex(Vector3(x, h, z))
	for zi in n:
		for xi in n:
			var a := zi * (n + 1) + xi
			st.add_index(a); st.add_index(a + 1); st.add_index(a + n + 2)
			st.add_index(a); st.add_index(a + n + 2); st.add_index(a + n + 1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	mi.material_override = m
	add_child(mi)
	var hs := HeightMapShape3D.new()
	hs.map_width = n + 1
	hs.map_depth = n + 1
	hs.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = hs
	cs.scale = Vector3(cell, 1, cell)
	_static.add_child(cs)


func block_rect(i: int, j: int) -> Rect2:
	var x0: float = Defs.ROADS[i] + Defs.road_w(i) / 2
	var x1: float = Defs.ROADS[i + 1] - Defs.road_w(i + 1) / 2
	var z0: float = Defs.ROADS[j] + Defs.road_w(j) / 2
	var z1: float = Defs.ROADS[j + 1] - Defs.road_w(j + 1) / 2
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func _plates() -> void:
	# city asphalt plate (roads), airport apron, promenade, quay
	box_static(Vector3(-40, PLATE_Y - 0.5, -40), Vector3(338, 1.0, 338), mat_road)
	box_static(Vector3(209.5, PLATE_Y - 0.5, -7.5), Vector3(161, 1.0, 415), G.flat_mat(Color(0.36, 0.36, 0.37), 0.9))
	box_static(Vector3(-40, PLATE_Y - 0.5, 149.5), Vector3(338, 1.0, 41), G.flat_mat(Color(0.58, 0.53, 0.44), 0.9))
	box_static(Vector3(94, -2.85, 192), Vector3(70, 6.3, 44), G.flat_mat(Color(0.4, 0.4, 0.39), 0.9))
	var grass := G.flat_mat(Color(0.31, 0.5, 0.26), 0.95)
	var ind := G.flat_mat(Color(0.45, 0.45, 0.44), 0.9)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		for j in 4:
			var r := block_rect(i, j)
			var c := r.get_center()
			box_static(Vector3(c.x, SLAB_Y - 0.25, c.y), Vector3(r.size.x, 0.5, r.size.y), mat_slab)
			var d: String = Defs.DISTRICTS[i][j]
			if d == "residential" or d == "park":
				quad(st, c.x, c.y, r.size.x - 6, r.size.y - 6, SLAB_Y + 0.012)
			elif d == "industrial":
				quad(st2, c.x, c.y, r.size.x - 5, r.size.y - 5, SLAB_Y + 0.012)
	commit(st, grass)
	commit(st2, ind)


func _markings() -> void:
	var w := SurfaceTool.new()
	w.begin(Mesh.PRIMITIVE_TRIANGLES)
	var yl := SurfaceTool.new()
	yl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := PLATE_Y + 0.012
	for k in 5:
		var rw := Defs.road_w(k)
		for s in 4:
			var a: float = Defs.ROADS[s] + Defs.road_w(s) / 2 + 4.5
			var b: float = Defs.ROADS[s + 1] - Defs.road_w(s + 1) / 2 - 4.5
			var mid := (a + b) / 2
			var len := b - a
			var c: float = Defs.ROADS[k]
			# k as a north-south road (x = c) and as an east-west road (z = c)
			quad(yl, c - 0.2, mid, 0.14, len, y); quad(yl, c + 0.2, mid, 0.14, len, y)
			quad(yl, mid, c - 0.2, len, 0.14, y); quad(yl, mid, c + 0.2, len, 0.14, y)
			if rw > 14:
				var p := a
				while p < b - 3:
					for off in [-4.5, 4.5]:
						quad(w, c + off, p + 1.5, 0.14, 3.0, y)
						quad(w, p + 1.5, c + off, 3.0, 0.14, y)
					p += 8.0
			for e in [a - 1.2, b + 1.2]:
				var q := -rw / 2 + 0.7
				while q < rw / 2 - 0.3:
					quad(w, c + q, e - (2.0 if e < mid else -2.0) + (2.0 if e < mid else -2.0), 0.55, 2.4, y)
					quad(w, e, c + q, 2.4, 0.55, y)
					q += 1.15
	# runway markings
	var p2 := -196.0
	while p2 < 186:
		quad(w, 240, p2 + 6, 0.5, 12, y)
		p2 += 24
	for xx in [-9, -6, -3, 3, 6, 9]:
		quad(w, 240 + xx, -202, 1.4, 8, y)
		quad(w, 240 + xx, 188, 1.4, 8, y)
	commit(w, G.flat_mat(Color(0.9, 0.9, 0.88), 0.8))
	commit(yl, G.flat_mat(Color(0.92, 0.75, 0.15), 0.8))
	var rw_st := SurfaceTool.new()
	rw_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	quad(rw_st, 240, -7, 26, 406, y - 0.006)
	quad(rw_st, 180, 120, 100, 12, y - 0.006)
	quad(rw_st, 180, -40, 100, 12, y - 0.006)
	commit(rw_st, mat_road)


func _water() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	mi.mesh = pm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.04, 0.22, 0.38);
uniform vec3 shallow : source_color = vec3(0.12, 0.5, 0.6);
void fragment() {
	vec2 p = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	float w = sin(p.x * 0.35 + TIME * 1.1) * sin(p.y * 0.3 - TIME * 0.9) + 0.5 * sin(p.x * 1.3 - TIME * 1.7 + p.y * 0.9);
	float w2 = sin(p.x * 0.9 + TIME * 0.7) * cos(p.y * 1.1 + TIME * 0.8);
	ALBEDO = mix(deep, shallow, 0.5 + 0.22 * w);
	NORMAL = normalize(NORMAL + vec3(w * 0.035, 0.0, w2 * 0.035));
	ROUGHNESS = 0.08;
	METALLIC = 0.2;
	SPECULAR = 0.7;
	ALPHA = 0.86;
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	mi.material_override = sm
	mi.position.y = G.WATER_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------- buildings
func free_rect(r: Rect2, margin := 1.5) -> bool:
	var g := r.grow(margin)
	for o in rects:
		if g.intersects(o):
			return false
	return true


func add_collision(root: Node3D) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).contains("sign"):
			continue
		var mesh: Mesh = mi.mesh
		if not _shape_cache.has(mesh):
			_shape_cache[mesh] = mesh.create_trimesh_shape()
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = _shape_cache[mesh]
		sb.add_child(cs)
		mi.add_child(sb)


func place_building(bname: String, x: float, z: float, rot: float, y := SLAB_Y) -> Node3D:
	var fp: Array = Defs.BUILDINGS[bname]
	var w: float = fp[0]
	var d: float = fp[1]
	if abs(abs(rot) - PI / 2) < 0.1:
		var t := w
		w = d
		d = t
	rects.append(Rect2(x - w / 2, z - d / 2, w, d))
	var inst := G.model("buildings/" + bname)
	inst.position = Vector3(x, y, z)
	inst.rotation.y = rot
	add_child(inst)
	add_collision(inst)
	return inst


func add_interact(pos: Vector3, label: String, action: Callable, color := Color(0.2, 0.8, 1.0), veh := false, radius := 2.4) -> Dictionary:
	var mi := MeshInstance3D.new()
	mi.mesh = _marker_mesh
	var m := G.flat_mat(color, 0.4, 0.0, 1.6)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.55
	mi.material_override = m
	mi.position = pos + Vector3(0, 0.06, 0)
	if veh:
		mi.scale = Vector3(2.4, 1, 2.4)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var it := {"pos": pos, "radius": radius * (1.8 if veh else 1.0), "label": label, "action": action, "veh": veh, "node": mi}
	interacts.append(it)
	return it


func icon(pname: String, pos: Vector3, color: Color) -> void:
	G.locations[pname] = pos
	G.map_icons.append({"pos": pos, "label": pname, "color": color})


func _landmarks() -> void:
	# --- industrial row
	place_building("bld_factory", -158, -143, PI)
	place_building("bld_modshop", -14, -137, PI)
	add_interact(Vector3(-14, SLAB_Y + 0.1, -135), "Torque Works: customize / repair vehicle", func(): G.menus.open("modshop"), Color(1.0, 0.55, 0.1), true, 3.8)
	icon("Mod Garage", Vector3(-14, 0.3, -124), Color(1.0, 0.55, 0.1))
	place_building("bld_gas", 18, -139.5, PI)
	add_interact(Vector3(13.2, SLAB_Y, -134.5), "Petrola kiosk: buy snack ($15, +health)", func(): G.menus.buy_snack(), Color(1, 0.3, 0.3))
	icon("Gas Station", Vector3(18, 0.3, -124), Color(1, 0.3, 0.3))
	place_building("bld_range", 60, -134, PI)
	add_interact(Vector3(60, SLAB_Y, -143), "Bullseye Range: start shooting challenge", func(): G.activities.start_range(), Color(1.0, 0.6, 0.2))
	icon("Shooting Range", Vector3(60, 0.4, -144.5), Color(1.0, 0.6, 0.2))
	rects.append(Rect2(47, -189, 32, 48))
	var cm := G.flat_mat(Color(0.5, 0.5, 0.48), 0.9)
	box_static(Vector3(63, SLAB_Y + 2.2, -186.5), Vector3(32, 4.4, 0.8), cm)
	box_static(Vector3(47.4, SLAB_Y + 1.5, -166), Vector3(0.6, 3.0, 41), cm)
	box_static(Vector3(78.6, SLAB_Y + 1.5, -166), Vector3(0.6, 3.0, 41), cm)
	box_static(Vector3(63, SLAB_Y + 0.5, -146.5), Vector3(18, 1.0, 0.5), G.flat_mat(Color(0.45, 0.3, 0.18), 0.8))
	place_building("bld_parking", 92, -144, PI)
	var wh := place_building("bld_warehouse_b", -80, -139, PI)
	ladders.append({"pos": Vector3(-80 + 15.0, SLAB_Y, -139), "top": Vector3(-80 + 12.5, SLAB_Y + 8.7, -139), "dir": Vector3(-1, 0, 0), "h": 8.0})
	var lad := G.model("props/prop_ladder")
	lad.position = Vector3(-80 + 14.55, SLAB_Y, -139)
	lad.rotation.y = PI / 2
	add_child(lad)
	add_pickup(Vector3(-80, SLAB_Y + 10.3, -139), "weapon:sniper", 1)
	# --- downtown
	place_building("bld_office_a", -14, -98, 0)
	add_interact(Vector3(-14, SLAB_Y, -112.4), "Elevator: go to rooftop", func(): G.player.warp(Vector3(-14, SLAB_Y + 56.6, -100)), Color(0.8, 0.8, 1.0))
	add_interact(Vector3(-14, SLAB_Y + 56.2, -97), "Elevator: go to street", func(): G.player.warp(Vector3(-14, SLAB_Y + 0.2, -113.5)), Color(0.8, 0.8, 1.0))
	add_pickup(Vector3(-8, SLAB_Y + 56.6, -92), "parachute", 1)
	icon("Skyline Tower", Vector3(-14, 0.3, -116), Color(0.8, 0.8, 1.0))
	place_building("bld_police", 84, -98, 0)
	add_pickup(Vector3(66, SLAB_Y + 0.2, -86), "armor", 100)
	icon("Police Station", Vector3(84, 0.3, -116), Color(0.3, 0.5, 1.0))
	place_building("bld_hospital", 80, -14, 0)
	add_pickup(Vector3(70, SLAB_Y + 0.2, -32.5), "health", 100)
	icon("Hospital", Vector3(80, 0.3, -36), Color(1, 0.3, 0.3))
	var hp := G.model("props/prop_helipad")
	hp.position = Vector3(92, SLAB_Y, 22)
	add_child(hp)
	rects.append(Rect2(82, 12, 20, 20))
	place_building("bld_gunshop", -14, 25, PI)
	add_interact(Vector3(-14, SLAB_Y, 32.4), "Ironside Arms: weapons, ammo, armor, workbench", func(): G.menus.open("gunshop"), Color(1, 0.25, 0.2))
	icon("Weapon Shop", Vector3(-14, 0.3, 36), Color(1, 0.25, 0.2))
	place_building("bld_clothes", 12, 25, PI)
	add_interact(Vector3(12, SLAB_Y, 32.4), "Threadline: clothing store", func(): G.menus.open("clothes"), Color(0.7, 0.4, 1.0))
	icon("Clothing", Vector3(12, 0.3, 36), Color(0.7, 0.4, 1.0))
	place_building("bld_barber", -100, 54, 0)
	add_interact(Vector3(-100, SLAB_Y, 47.6), "Clip Joint: barber", func(): G.menus.open("barber"), Color(0.9, 0.9, 0.9))
	icon("Barber", Vector3(-100, 0.3, 44), Color(0.9, 0.9, 0.9))
	# --- safehouse (front faces +X)
	place_building("bld_safehouse", -135, 3, -PI / 2)
	for it in [["int_bed", Vector3(-138.3, SLAB_Y + 0.1, 7.0), PI / 2], ["int_wardrobe", Vector3(-139.3, SLAB_Y + 0.1, 0.6), -PI / 2], ["int_counter", Vector3(-136, SLAB_Y + 0.1, -1.9), 0.0]]:
		var n := G.model("props/" + it[0])
		n.position = it[1]
		n.rotation.y = it[2]
		add_child(n)
	add_interact(Vector3(-135.5, SLAB_Y + 0.1, 3), "Safehouse: save, sleep, wardrobe", func(): G.menus.open("safehouse"), Color(0.3, 1.0, 0.5))
	add_interact(Vector3(-126.8, SLAB_Y, 12), "Garage: store / retrieve vehicles", func(): G.menus.open("garage"), Color(0.3, 1.0, 0.5), false, 2.6)
	icon("Safehouse", Vector3(-127.5, 0.4, 3), Color(0.3, 1.0, 0.5))
	G.locations["Garage Spot"] = Vector3(-135, 0.35, 12)


func _fill_side(r: Rect2, side: int, pool: Array) -> void:
	var horizontal := side < 2
	var a0 := (r.position.x if horizontal else r.position.y) + 3.0
	var a1 := (r.end.x if horizontal else r.end.y) - 3.0
	var p := a0
	var tries := 0
	while p < a1 - 8 and tries < 30:
		tries += 1
		var bname: String = pool[rnd.randi() % pool.size()]
		var fp: Array = Defs.BUILDINGS[bname]
		var w: float = fp[0]
		var d: float = fp[1]
		if p + w > a1:
			continue
		var c := p + w / 2
		var pos := Vector2.ZERO
		var rot := 0.0
		var rr: Rect2
		match side:
			0:
				pos = Vector2(c, r.position.y + 3 + d / 2); rot = 0.0; rr = Rect2(pos.x - w / 2, pos.y - d / 2, w, d)
			1:
				pos = Vector2(c, r.end.y - 3 - d / 2); rot = PI; rr = Rect2(pos.x - w / 2, pos.y - d / 2, w, d)
			2:
				pos = Vector2(r.position.x + 3 + d / 2, c); rot = PI / 2; rr = Rect2(pos.x - d / 2, pos.y - w / 2, d, w)
			3:
				pos = Vector2(r.end.x - 3 - d / 2, c); rot = -PI / 2; rr = Rect2(pos.x - d / 2, pos.y - w / 2, d, w)
		if free_rect(rr):
			place_building(bname, pos.x, pos.y, rot)
			p += w + rnd.randf_range(2.5, 6.0)
		else:
			p += 4.0


func _fill_blocks() -> void:
	for i in 4:
		for j in 4:
			var d: String = Defs.DISTRICTS[i][j]
			var r := block_rect(i, j)
			if d == "park":
				continue
			for side in [0, 1, 2, 3]:
				_fill_side(r, side, Defs.POOLS[d])
			var c := r.get_center()
			var lot := Rect2(c.x - 9, c.y - 6, 18, 12)
			if d != "residential" and free_rect(lot, 0.5):
				for k in 4:
					if rnd.randf() < 0.75:
						parking_spots.append([Vector3(c.x - 6.3 + k * 4.2, SLAB_Y + 0.05, c.y), 0.0 if rnd.randf() < 0.5 else PI])
	# west strip houses facing the west arterial, waterfront row facing the boulevard
	_fill_side(Rect2(-272, -205, 63, 330), 3, Defs.POOLS["residential"])
	_fill_side(Rect2(-205, 129, 250, 40), 0, Defs.POOLS["commercial"])


# ---------------------------------------------------------------- props
func add_prop(kind: String, pos: Vector3, yaw := 0.0) -> Prop:
	var p := Prop.make(kind)
	p.position = pos
	p.rotation.y = yaw
	add_child(p)
	G.props.append(p)
	p.cell = Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
	if not prop_grid.has(p.cell):
		prop_grid[p.cell] = []
	prop_grid[p.cell].append(p)
	return p


func prop_woke(p: Prop) -> void:
	if prop_grid.has(p.cell):
		prop_grid[p.cell].erase(p)
	awake_props.append([p, G.time_now + 50.0])


func wake_props_near(pos: Vector3, radius: float, speed: float, vel: Vector3) -> void:
	var c := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var k := c + Vector2i(dx, dz)
			if not prop_grid.has(k):
				continue
			for p in prop_grid[k].duplicate():
				if not is_instance_valid(p):
					continue
				var d: Vector3 = p.global_position - pos
				d.y = 0
				if d.length() < radius and speed >= p.min_speed:
					p.wake(vel.normalized() * min(speed, 20.0) * p.mass * 0.5 + Vector3.UP * p.mass * 1.5)


func static_model(path: String, pos: Vector3, yaw := 0.0, collide := true) -> Node3D:
	var n := G.model(path)
	n.position = pos
	n.rotation.y = yaw
	add_child(n)
	if collide:
		add_collision(n)
	return n


func _street_furniture() -> void:
	var rots := [0.0, PI, PI / 2, -PI / 2]
	for i in 4:
		for j in 4:
			var r := block_rect(i, j)
			var d: String = Defs.DISTRICTS[i][j]
			for side in 4:
				var horizontal := side < 2
				var a0 := (r.position.x if horizontal else r.position.y)
				var a1 := (r.end.x if horizontal else r.end.y)
				var fixed := 0.0
				match side:
					0: fixed = r.position.y + 1.0
					1: fixed = r.end.y - 1.0
					2: fixed = r.position.x + 1.0
					3: fixed = r.end.x - 1.0
				var p := a0 + 7.0
				var k := 0
				while p < a1 - 5:
					var pos := Vector3(p, SLAB_Y, fixed) if horizontal else Vector3(fixed, SLAB_Y, p)
					if k % 3 == 0:
						add_prop("prop_street_lamp", pos, rots[side])
						var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, rots[side])
						lamp_points.append(pos + fwd * 2.0 + Vector3.UP * 7.0)
					else:
						var q := rnd.randf()
						var kind := ""
						if q < 0.2: kind = "prop_bin"
						elif q < 0.32: kind = "prop_bench"
						elif q < 0.4: kind = "prop_hydrant"
						elif q < 0.47: kind = "prop_mailbox"
						elif q < 0.53: kind = "prop_utility_box"
						elif q < 0.58 and d != "residential": kind = "prop_vending"
						elif q < 0.63: kind = "prop_sign_speed"
						elif q < 0.68 and d == "industrial": kind = "prop_barrel"
						elif q < 0.72 and d == "industrial": kind = "prop_pallet"
						if kind != "":
							var pr := add_prop(kind, pos, rots[side])
							if kind == "prop_vending":
								add_interact(pos + Vector3(0, 0, -1.0).rotated(Vector3.UP, rots[side]), "Vending machine: soda ($5, +health)", func(): G.menus.buy_snack(5, 12.0), Color(1, 0.4, 0.4), false, 1.6)
					p += 8.7
					k += 1
			if (i + j) % 2 == 0 and d != "park":
				static_model("props/prop_bus_stop", Vector3(r.get_center().x + 12, SLAB_Y, r.position.y + 2.2), PI)
	# traffic lights
	for n in 25:
		if G.roads.links[n].size() < 3:
			continue
		for a in G.roads.links[n]:
			var dir: Vector3 = G.roads.edge_dir(a, n)
			var right := dir.cross(Vector3.UP)
			var pos: Vector3 = G.roads.nodes[n] - dir * (G.roads.cross_half(n, a) + 1.2) + right * (G.roads.half_width(a, n) + 1.2)
			pos.y = SLAB_Y
			var left := -right
			var pr := add_prop("prop_traffic_light", pos, atan2(-left.x, -left.z))
			var moving_x: bool = abs(dir.x) > 0.5
			var parity := ((n / 5) + (n % 5)) % 2
			if (parity + (1 if moving_x else 0)) % 2 == 1:
				for mn in ["TLRed", "TLYellow", "TLGreen"]:
					G.tint(pr, mn, G.shared_mats[mn + "B"])


func _airport() -> void:
	static_model("buildings/bld_hangar", Vector3(160, PLATE_Y, -165), -PI / 2)
	static_model("buildings/bld_hangar", Vector3(160, PLATE_Y, -120), -PI / 2)
	static_model("buildings/bld_tower", Vector3(148, PLATE_Y, -78), -PI / 2)
	add_pickup(Vector3(152, PLATE_Y + 0.2, -72), "parachute", 1)
	for z in [-10.0, 30.0]:
		var h := G.model("props/prop_helipad")
		h.position = Vector3(170, PLATE_Y, z)
		add_child(h)
	icon("Airport", Vector3(176, 0.3, -78), Color(0.6, 0.9, 1.0))
	G.locations["Helipad"] = Vector3(170, 0.4, -10)
	G.locations["Helipad 2"] = Vector3(170, 0.4, 30)
	G.locations["Runway"] = Vector3(240, 0.4, 176)
	G.locations["Hangar Apron"] = Vector3(196, 0.4, -120)
	add_interact(Vector3(182, PLATE_Y, -142), "Airfield desk: spawn aircraft", func(): G.menus.open("aircraft"), Color(0.6, 0.9, 1.0))
	# perimeter fence with gates
	var z := -206.0
	while z < 196:
		if abs(z - 120) > 10 and abs(z + 40) > 10:
			add_prop("prop_fence", Vector3(131, PLATE_Y, z + 1.5), PI / 2)
		z += 3.0
	for p in [Vector3(200, PLATE_Y, 60), Vector3(215, PLATE_Y, 60)]:
		add_prop("prop_barrel", p)
	for k in 6:
		add_prop("prop_cone", Vector3(222, PLATE_Y, -190 + k * 6.0))
	parking_spots.append([Vector3(150, PLATE_Y + 0.1, 100), 0.0])
	parking_spots.append([Vector3(155, PLATE_Y + 0.1, 100), 0.0])
	var ramp := static_model("props/prop_ramp", Vector3(205, PLATE_Y, 80), 0.0)
	stunt_zones.append(Vector3(205, 0, 76))


func _waterfront() -> void:
	# main pier into the sea
	for k in 6:
		var pz := 204.0 + k * 8.0
		var n := G.model("props/prop_pier")
		n.position = Vector3(-80, 0.35, pz)
		add_child(n)
		box_static(Vector3(-80, 0.25, pz), Vector3(4, 0.4, 8))
	for k in 4:
		var n2 := G.model("props/prop_pier")
		n2.position = Vector3(96, 0.35, 218.0 + k * 8.0)
		add_child(n2)
		box_static(Vector3(96, 0.25, 218.0 + k * 8.0), Vector3(4, 0.4, 8))
	G.locations["Pier"] = Vector3(-80, 0.7, 240)
	G.locations["Boat Dock"] = Vector3(-87, 0.0, 236)
	G.locations["Dock Boat 2"] = Vector3(103, 0.0, 240)
	icon("Docks", Vector3(96, 0.5, 190), Color(0.4, 0.8, 1.0))
	icon("Beach", Vector3(-60, 0.4, 190), Color(1.0, 0.9, 0.5))
	add_interact(Vector3(-80, 0.5, 246), "Pier: spawn speedboat", func(): G.menus.spawn_vehicle_at("speedboat", "Boat Dock", PI), Color(0.4, 0.8, 1.0))
	static_model("props/prop_crane", Vector3(110, 0.3, 198), PI)
	for c in [[70, 180, 0.0, 0, 0.0], [74, 180, 0.0, 1, 0.0], [78, 180, 0.0, 2, 0.0], [70, 180, 2.6, 5, 0.0], [106, 176, 0.0, 6, PI / 2], [116, 176, 0.0, 1, PI / 2], [116, 176, 2.6, 3, PI / 2], [64, 202, 0.0, 9, 0.0]]:
		var cn := static_model("props/prop_container", Vector3(c[0], 0.3 + c[2], c[1]), c[4])
		G.tint(cn, "Paint", G.flat_mat(G.col(Defs.CAR_COLORS[c[3]]), 0.6, 0.3))
	ladders.append({"pos": Vector3(70, 0.3, 176.4), "top": Vector3(70, 5.6, 178.2), "dir": Vector3(0, 0, 1), "h": 5.2})
	var lad := G.model("props/prop_ladder")
	lad.position = Vector3(70, 0.3 - 2.8, 176.85)
	add_child(lad)
	for k in 5:
		add_prop("prop_crate", Vector3(84 + k * 1.3, 0.3, 186 + (k % 2) * 1.2))
	add_prop("prop_barrel_explosive", Vector3(90, 0.3, 182))
	add_prop("prop_barrel_explosive", Vector3(91, 0.3, 183))
	static_model("props/prop_lifeguard", Vector3(-30, height(-30, 196), 196), 0.0)
	for k in 9:
		var x := -190.0 + k * 26.0 + rnd.randf_range(-4, 4)
		if abs(x + 80) < 8:
			continue
		add_prop("prop_umbrella", Vector3(x, height(x, 192), 192 + rnd.randf_range(-3, 4)), rnd.randf() * TAU)
	for k in 14:
		var x2 := -200.0 + k * 22.0
		add_prop("prop_bench", Vector3(x2, PLATE_Y, 167), PI)
		if k % 2 == 0:
			add_prop("prop_street_lamp", Vector3(x2 + 6, PLATE_Y, 168.5), 0.0)
			lamp_points.append(Vector3(x2 + 6, 7.0, 166.5))
	for b in [Vector3(-40, 0, 300), Vector3(40, 0, 330), Vector3(-160, 0, 310), Vector3(140, 0, 290)]:
		var bu := G.model("props/prop_buoy")
		bu.position = Vector3(b.x, G.WATER_Y, b.z)
		add_child(bu)
	# beach stunt ramp into the sea
	static_model("props/prop_ramp", Vector3(-190, PLATE_Y, 163), PI)
	stunt_zones.append(Vector3(-190, 0, 166))
	# sunken wreck + loot
	var wz := 266.0
	static_model("props/prop_wreck", Vector3(-150, height(-150, wz) - 0.4, wz), 0.7)
	add_pickup(Vector3(-146, height(-146, wz + 4) + 0.6, wz + 4), "cash", 2500)
	add_pickup(Vector3(-154, height(-154, wz - 5) + 0.6, wz - 5), "cash", 1500)
	add_pickup(Vector3(-80, 0.6, 250), "scuba", 1)
	G.locations["Dive Wreck"] = Vector3(-150, G.WATER_Y, wz)
	G.map_icons.append({"pos": Vector3(-150, 0, wz), "label": "Wreck", "color": Color(0.5, 0.7, 0.8)})


func mm_add(path: String, pos: Vector3, yaw: float, scale := 1.0) -> void:
	if not _mm.has(path):
		_mm[path] = []
	_mm[path].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos))


func _flush_multimeshes() -> void:
	for path in _mm:
		var n := G.model(path)
		var mi: MeshInstance3D = n.find_children("*", "MeshInstance3D", true, false)[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mi.mesh
		mm.instance_count = _mm[path].size()
		for k in _mm[path].size():
			mm.set_instance_transform(k, _mm[path][k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if path.contains("grass"):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 90.0
		add_child(mmi)
		n.free()


func tree(path: String, pos: Vector3, scale := 1.0) -> void:
	mm_add(path, pos, rnd.randf() * TAU, scale)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.3
	cy.height = 4.0
	cs.shape = cy
	cs.position = pos + Vector3(0, 2, 0)
	_static.add_child(cs)


func _nature() -> void:
	# hills: pines, rocks, grass
	for k in 110:
		var x := rnd.randf_range(-280, 125)
		var z := rnd.randf_range(-290, -216)
		if abs(x + 60) < 7 and abs(z + 256) < 8:
			continue
		var h := height(x, z)
		if k % 6 == 0:
			mm_add("nature/nat_rock_a" if k % 12 == 0 else "nature/nat_rock_b", Vector3(x, h - 0.3, z), rnd.randf() * TAU, rnd.randf_range(0.6, 1.2))
		else:
			tree("nature/nat_pine" if k % 3 != 0 else "nature/nat_tree_tall", Vector3(x, h - 0.1, z), rnd.randf_range(0.8, 1.3))
	for k in 500:
		var x := rnd.randf_range(-280, 125)
		var z := rnd.randf_range(-290, -214)
		mm_add("nature/nat_grass", Vector3(x, height(x, z), z), rnd.randf() * TAU, rnd.randf_range(0.8, 1.6))
	# park
	var pr := block_rect(1, 2)
	var c := pr.get_center()
	static_model("props/prop_fountain", Vector3(c.x, SLAB_Y, c.y))
	rects.append(Rect2(c.x - 5, c.y - 5, 10, 10))
	G.locations["Park"] = Vector3(c.x + 8, 0.4, c.y)
	icon("Central Park", Vector3(c.x + 8, 0.4, c.y), Color(0.4, 0.9, 0.4))
	for k in 46:
		var x := rnd.randf_range(pr.position.x + 5, pr.end.x - 5)
		var z := rnd.randf_range(pr.position.y + 5, pr.end.y - 5)
		if Vector2(x - c.x, z - c.y).length() < 8 or abs(x - c.x) < 2.5 or abs(z - c.y) < 2.5:
			continue
		if k % 4 == 0:
			mm_add("nature/nat_bush", Vector3(x, SLAB_Y, z), rnd.randf() * TAU, rnd.randf_range(0.8, 1.4))
		else:
			tree("nature/nat_tree_round" if k % 3 else "nature/nat_tree_tall", Vector3(x, SLAB_Y, z), rnd.randf_range(0.8, 1.2))
	for k in 300:
		var x := rnd.randf_range(pr.position.x + 4, pr.end.x - 4)
		var z := rnd.randf_range(pr.position.y + 4, pr.end.y - 4)
		mm_add("nature/nat_grass", Vector3(x, SLAB_Y, z), rnd.randf() * TAU, rnd.randf_range(0.7, 1.3))
	for a in 6:
		var ang := a * TAU / 6
		add_prop("prop_bench", Vector3(c.x + cos(ang) * 6.5, SLAB_Y, c.y + sin(ang) * 6.5), -ang - PI / 2)
	add_prop("prop_picnic_table", Vector3(c.x - 18, SLAB_Y, c.y + 16))
	add_prop("prop_picnic_table", Vector3(c.x + 18, SLAB_Y, c.y - 18))
	add_pickup(Vector3(c.x - 18, SLAB_Y + 0.3, c.y + 13), "weapon:bat", 1)
	# residential yards + west strip trees
	for k in 150:
		var x := rnd.randf_range(-284, -42)
		var z := rnd.randf_range(-205, 126)
		var d := "none"
		if x < -209:
			d = "west"
		elif x > -191 and z > -114:
			var ci := clampi(int((x + 200.0) / 80.0), 0, 3)
			var ri := clampi(int((z + 200.0) / 80.0), 0, 3)
			var br := block_rect(ci, ri)
			if Defs.DISTRICTS[ci][ri] == "residential" and br.grow(-5).has_point(Vector2(x, z)):
				d = "res"
		if d == "none" or not free_rect(Rect2(x - 1.5, z - 1.5, 3, 3), 1.0):
			continue
		var y := SLAB_Y if d == "res" else height(x, z)
		if k % 5 == 0:
			mm_add("nature/nat_bush", Vector3(x, y, z), rnd.randf() * TAU, rnd.randf_range(0.8, 1.3))
		else:
			tree("nature/nat_tree_round" if k % 2 else "nature/nat_tree_tall", Vector3(x, y, z), rnd.randf_range(0.8, 1.2))
	# palms along the promenade / beach, rocks on the beach and sea floor
	for k in 26:
		var x := -204.0 + k * 13.0 + rnd.randf_range(-2, 2)
		if abs(x + 80) < 5 or (x > 56 and x < 130):
			continue
		tree("nature/nat_palm", Vector3(x, height(x, 178), 178 + rnd.randf_range(-2, 3)), rnd.randf_range(0.9, 1.25))
	for k in 40:
		var x := rnd.randf_range(-290, 290)
		var z := rnd.randf_range(200, 320)
		mm_add("nature/nat_rock_a" if k % 2 else "nature/nat_rock_b", Vector3(x, height(x, z) - 0.2, z), rnd.randf() * TAU, rnd.randf_range(0.5, 1.6))


func _extras() -> void:
	# hill viewpoint
	var vp := Vector3(-60, height(-60, -256), -256)
	G.locations["Hill Viewpoint"] = vp + Vector3(0, 0.4, 0)
	icon("Viewpoint", vp, Color(0.6, 1.0, 0.6))
	add_prop("prop_bench", vp + Vector3(0, 0, 3), PI)
	add_prop("prop_picnic_table", vp + Vector3(4, 0, -1))
	add_pickup(vp + Vector3(-3, 0.3, 0), "cash", 400)
	# gang yard in the industrial district
	var gy := Vector3(-80, SLAB_Y, -172)
	G.locations["Gang Yard"] = gy
	for k in 4:
		add_prop("prop_barrel", gy + Vector3(-6 + k * 1.1, 0, 4))
	add_prop("prop_barrel_explosive", gy + Vector3(6, 0, 4))
	add_prop("prop_dumpster", gy + Vector3(8, 0, -3), 0.4)
	add_prop("prop_tire_stack", gy + Vector3(-8, 0, -3))
	add_prop("prop_crate", gy + Vector3(-3, 0, -5))
	add_prop("prop_crate", gy + Vector3(-1.8, 0, -5.2))
	add_pickup(gy + Vector3(0, 0.3, -6), "weapon:smg", 1)
	# construction zone with cones and roadblock barriers on the arterial shoulder
	for k in 6:
		add_prop("prop_cone", Vector3(-150 + k * 2.5, SLAB_Y, 109.6))
	static_model("props/prop_barrier", Vector3(-160, PLATE_Y, 131.5), PI / 2)
	static_model("props/prop_billboard", Vector3(-214, 0, -160), -PI / 2)
	static_model("props/prop_billboard", Vector3(137, PLATE_Y, 60), PI / 2, false)
	# stunt ramp on the verge of the north arterial
	static_model("props/prop_ramp", Vector3(-160, 0.0, -213.0), -PI / 2)
	stunt_zones.append(Vector3(-156, 0, -213))
	add_interact(Vector3(-120, PLATE_Y, 126), "Start street time trial (ring road lap)", func(): G.activities.start_trial(), Color(1.0, 0.85, 0.2), true)
	G.map_icons.append({"pos": Vector3(-120, 0, 126), "label": "Time Trial", "color": Color(1.0, 0.85, 0.2)})
	# scattered pickups
	for p in [[Vector3(-20, 0.4, 0), "cash", 250], [Vector3(60, 0.4, 60), "cash", 300], [Vector3(-100, 0.4, -80), "cash", 200],
			[Vector3(100, 0.4, 100), "health", 50], [Vector3(-170, 0.4, 100), "armor", 50], [Vector3(30, 0.4, -170), "ammo", 1],
			[Vector3(-60, 0.4, 150), "weapon:pistol", 1], [Vector3(96, 0.6, 244), "weapon:shotgun", 1], [Vector3(190, 0.3, -165), "weapon:rocket", 1],
			[Vector3(-250, 0.4, 0), "weapon:knife", 1], [Vector3(0, 0.4, 100), "ammo", 1]]:
		add_pickup(p[0], p[1], p[2])
	# cover points from parked spots / props are computed on the fly; keep a few fixed ones
	for it in interacts:
		cover_points.append(it.pos)


func add_pickup(pos: Vector3, type: String, amount: int) -> void:
	var path := "props/prop_pickup_cash"
	if type == "health": path = "props/prop_pickup_health"
	elif type == "armor": path = "props/prop_pickup_armor"
	elif type == "ammo": path = "props/prop_pickup_ammo"
	elif type == "parachute": path = "characters/acc_parachute_pack"
	elif type == "scuba": path = "characters/acc_scuba"
	elif type.begins_with("weapon:"): path = "weapons/" + Defs.WEAPONS[type.substr(7)].model
	var n := G.model(path)
	n.position = pos
	if type.begins_with("weapon:"):
		n.position.y += 0.5
		n.scale = Vector3.ONE * 1.6
		for a in n.find_children("*att_*", "Node3D", true, false):
			a.visible = false
	add_child(n)
	pickups.append({"node": n, "pos": pos, "type": type, "amount": amount, "t": 0.0})


func drop_cash(pos: Vector3, amount: int) -> void:
	add_pickup(Vector3(pos.x, max(pos.y, height(pos.x, pos.z)) + 0.1, pos.z), "cash", amount)
	pickups[-1]["temp"] = G.time_now + 90.0


func _nav() -> void:
	nav_region = NavigationRegion3D.new()
	add_child(nav_region)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = G.L_WORLD
	nm.cell_size = 0.5
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 42.0
	nm.filter_baking_aabb = AABB(Vector3(-292, -1.2, -296), Vector3(584, 12, 520))
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, 0.5)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, 0.25)
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, self)
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, func():
		nav_region.navigation_mesh = nm
		nav_ready = true
		print("[nav] baked polygons: ", nm.get_polygon_count()))


func nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not nav_ready:
		return PackedVector3Array([from, to])
	var p := NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, to, true)
	if p.size() < 2:
		return PackedVector3Array([from, to])
	return p


func _process(delta: float) -> void:
	# traffic light materials (two phase groups)
	_tl_t -= delta
	if _tl_t <= 0.0:
		_tl_t = 0.25
		for g in 2:
			var ph: float = fmod(G.time_now + g * RoadGraph.CYCLE * 0.5, RoadGraph.CYCLE)
			var st := 2
			if ph < RoadGraph.CYCLE * 0.5 - 3.0: st = 0
			elif ph < RoadGraph.CYCLE * 0.5 - 1.0: st = 1
			var sfx := "" if g == 0 else "B"
			G.shared_mats["TLGreen" + sfx].emission_energy_multiplier = 3.0 if st == 0 else 0.0
			G.shared_mats["TLYellow" + sfx].emission_energy_multiplier = 3.0 if st == 1 else 0.0
			G.shared_mats["TLRed" + sfx].emission_energy_multiplier = 3.0 if st == 2 else 0.0
		while not awake_props.is_empty() and awake_props[0][1] < G.time_now:
			var p = awake_props.pop_front()[0]
			if is_instance_valid(p):
				G.props.erase(p)
				p.queue_free()
	# pickups
	var pl = G.player
	if pl == null:
		return
	var pp: Vector3 = pl.global_position
	for i in range(pickups.size() - 1, -1, -1):
		var pk: Dictionary = pickups[i]
		var n: Node3D = pk.node
		if pk.has("temp") and pk.temp < G.time_now:
			n.queue_free()
			pickups.remove_at(i)
			continue
		if pk.t > 0.0:
			pk.t -= delta
			if pk.t <= 0.0:
				n.visible = true
			continue
		if pk.pos.distance_squared_to(pp) > 3600.0:
			continue
		n.rotation.y += delta * 2.0
		n.position.y = pk.pos.y + (0.5 if pk.type.begins_with("weapon:") else 0.0) + sin(G.time_now * 2.5 + i) * 0.08
		if pk.pos.distance_to(pp + Vector3.UP * 0.5) < 1.5 and not pl.dead:
			if pl.collect(pk.type, pk.amount):
				if pk.has("temp"):
					n.queue_free()
					pickups.remove_at(i)
				else:
					n.visible = false
					pk.t = 120.0
	for it in interacts:
		if it.pos.distance_squared_to(pp) < 2500.0:
			it.node.rotation.y += delta
