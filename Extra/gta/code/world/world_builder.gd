class_name WorldBuilder
extends Node3D
## Builds the Cinder Bay world at startup from WorldLayout data and the Blender-authored kits:
## terrain, roads, block slabs, modular buildings (MultiMesh), props, colliders, water.

const GH := 4.2
const FH := 3.4
const K_FACADE := "world/kit_facade"
const K_LAND := "world/kit_landmarks"
const KITS := ["world/kit_facade", "world/kit_landmarks", "props/kit_props", "props/kit_interiors", "world/kit_nature"]

const STYLES := {
	"office": {"ground": "bm_office_ground", "door": "bm_office_door", "upper": ["bm_office_upper"], "parapet": "bm_parapet_modern"},
	"grid": {"ground": "bm_office_ground", "door": "bm_office_door", "upper": ["bm_grid_upper"], "parapet": "bm_parapet_modern"},
	"apt": {"ground": "bm_apt_ground_window", "door": "bm_apt_ground_door", "upper": ["bm_apt_window", "bm_apt_balcony"], "parapet": "bm_parapet_classic", "blank": "bm_blank_upper"},
	"aptshop": {"ground": "bm_apt_ground_window", "front": "bm_shop_window", "door": "bm_shop_door", "upper": ["bm_apt_balcony", "bm_apt_window"], "parapet": "bm_parapet_classic"},
	"brick": {"ground": "bm_brick_ground", "door": "bm_brick_door", "upper": ["bm_brick_upper"], "parapet": "bm_parapet_brick", "blank": "bm_brick_blank"},
	"brickshop": {"ground": "bm_brick_ground", "front": "bm_shop_window", "door": "bm_shop_door", "upper": ["bm_brick_upper"], "parapet": "bm_parapet_brick"},
	"ind": {"ground": "bm_ind_ground", "door": "bm_ind_door", "upper": ["bm_ind_upper", "bm_ind_window", "bm_ind_upper"], "parapet": "bm_parapet_ind"},
}
const PAL := {
	"office": ["dfe6ea", "8fb0cf", "6fb2ad", "c9b28a", "9aa0a6", "3d4652", "e8d9c0"],
	"grid": ["e7e2d6", "cfd4d8", "d9c7a8", "b8c4b0", "c9b9b0"],
	"apt": ["e7d9bd", "e3a58c", "6fb2ad", "8fb0cf", "ecc874", "f0ece2", "d99a7a", "b5c99a"],
	"brick": ["ffffff", "d9c8c0", "ffe9d6", "b89a90", "e8d0b0"],
	"ind": ["9fb6bf", "c98a68", "dfe6ea", "8fae93", "d9b67a", "8a94a0"],
	"awning": ["d2553f", "2f9c95", "f2b705", "2a67c9", "3d8f4f", "e9792a", "7d2a8c", "f4f1ea"],
	"sign": ["ff6b4a", "3fe0ff", "ffd23e", "ff4fa3", "7dff8a", "ffffff", "ff9a3c"],
	"house": ["f0ece2", "e7d9bd", "e3a58c", "9fc4c0", "a9c0d9", "ecd38a", "c9d6b0", "d9b0a0"],
	"container": ["c9302a", "2f62b3", "3d8f4f", "e9792a", "f0c21c", "8a94a0", "7d2a8c"],
}
const POLE_PROPS := ["prop_street_lamp", "prop_traffic_light_A", "prop_traffic_light_B", "prop_park_lamp", "prop_power_pole", "prop_flagpole",
	"prop_antenna", "prop_umbrella", "prop_sign_stop", "prop_sign_speed", "prop_sign_oneway", "prop_sign_yield", "prop_sign_street",
	"prop_sign_parking", "prop_parking_meter", "prop_target_stand", "prop_dish", "tree_round", "tree_tall", "tree_pine", "tree_palm"]
const NOCOL_PROPS := ["grass_clump", "flower_clump", "reed", "seaweed", "coral", "bush_a", "bush_b", "prop_spike_strip", "prop_helipad",
	"curb_straight", "curb_corner", "prop_target", "rock_c", "prop_ladder"]
const FIXED_PROPS := ["prop_container", "prop_billboard", "prop_bus_stop", "prop_fountain", "prop_statue", "prop_lifeguard_tower",
	"prop_barrier_jersey", "prop_wall_low", "prop_roof_tank", "prop_roof_stair", "prop_ac_unit", "prop_roof_vent", "rock_a", "rock_b", "log",
	"prop_atm", "tree_round", "tree_tall", "tree_pine", "tree_palm", "prop_power_pole", "prop_antenna", "prop_dish", "prop_flagpole",
	"prop_stump", "prop_sandbags", "prop_planter", "prop_dumpster", "prop_fence_iron", "prop_tire_stack"]
const TRIMESH_PROPS := ["prop_stunt_ramp", "prop_wreck"]


class Chunk:
	var node: Node3D
	var body: StaticBody3D
	var mods := {}
	var props := {}
	var st := {}


var rng := RandomNumberGenerator.new()
var noise_tex: NoiseTexture2D
var gmats := {}
var kit_of := {}
var chunks: Array = []
var cur: Chunk
var pois := {}
var parking: Array = []
var interacts: Array = []
var lamps := PackedVector3Array()
var ladders: Array = []
var stunts: Array = []
var pickups: Array = []
var spawns := {}
var building_boxes: Array = []
var tower_roof := Vector3.ZERO
var water_mesh: MeshInstance3D
var water_mat: ShaderMaterial
var blocks: RefCounted


func build() -> void:
	rng.seed = 7731
	_make_noise()
	_make_materials()
	for k in KITS:
		for nm in Assets.kit(k).keys():
			kit_of[nm] = k
	_build_terrain()
	_build_water()
	_build_roads()
	blocks = load("res://gta/code/world/world_blocks.gd").new(self)
	blocks.build_all()
	for c in chunks:
		_finish_chunk(c)
	_boundaries()


# ------------------------------------------------------------------ materials
func _make_noise() -> void:
	noise_tex = NoiseTexture2D.new()
	noise_tex.width = 512
	noise_tex.height = 512
	noise_tex.seamless = true
	noise_tex.generate_mipmaps = true
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.012
	fn.fractal_octaves = 4
	noise_tex.noise = fn


func _sm(shader_name: String, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Assets.shader(shader_name)
	m.set_shader_parameter("noise_tex", noise_tex)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


func _make_materials() -> void:
	gmats["road"] = _sm("road", {})
	gmats["terrain"] = _sm("terrain", {})
	gmats["pave"] = _sm("pave", {"color": Color("b9b4a8"), "tile": 2.0, "line_strength": 0.2})
	gmats["plaza"] = _sm("pave", {"color": Color("d6cdb8"), "tile": 4.0, "line_strength": 0.14})
	gmats["concrete"] = _sm("pave", {"color": Color("9d9a92"), "tile": 6.0, "line_strength": 0.12})
	gmats["roof"] = _sm("pave", {"color": Color("8f8a80"), "tile": 1.0, "line_strength": 0.0})
	gmats["roofdark"] = _sm("pave", {"color": Color("55524f"), "tile": 1.0, "line_strength": 0.0})
	gmats["wood"] = _sm("pave", {"color": Color("a8783f"), "tile": 0.9, "line_strength": 0.22})
	gmats["metal"] = _sm("pave", {"color": Color("4a4d52"), "tile": 50.0, "line_strength": 0.0, "rough": 0.45})
	gmats["grass"] = _sm("terrain", {})
	gmats["curbwhite"] = _sm("pave", {"color": Color("d8d4c8"), "tile": 50.0, "line_strength": 0.0})
	gmats["floor"] = _sm("pave", {"color": Color("cfc8b8"), "tile": 1.2, "line_strength": 0.12, "rough": 0.5})
	water_mat = _sm("water", {})
	gmats["water"] = water_mat


# ------------------------------------------------------------------ chunk helpers
func chunk(nm: String) -> Chunk:
	var c := Chunk.new()
	c.node = Node3D.new()
	c.node.name = nm
	add_child(c.node)
	c.body = StaticBody3D.new()
	c.body.name = "Static"
	c.body.collision_layer = G.L_WORLD
	c.body.collision_mask = 0
	c.body.set_meta("props", true)
	c.node.add_child(c.body)
	chunks.append(c)
	cur = c
	return c


func st_for(key: String) -> SurfaceTool:
	if not cur.st.has(key):
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		cur.st[key] = s
	return cur.st[key]


func quad(key: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3 = Vector3.UP, uvs: Array = [], col: Color = Color.WHITE) -> void:
	var s := st_for(key)
	var pts := [p0, p1, p2, p3]
	var uv := uvs if uvs.size() == 4 else [Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), Vector2(p2.x, p2.z), Vector2(p3.x, p3.z)]
	var order := [0, 1, 2, 0, 2, 3]
	if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i in order:
		s.set_normal(n)
		s.set_uv(uv[i])
		s.set_color(col)
		s.add_vertex(pts[i])


func rect(key: String, x0: float, z0: float, x1: float, z1: float, y: float, col: Color = Color.WHITE) -> void:
	quad(key, Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP, [], col)


func box_mesh(key: String, c: Vector3, size: Vector3, col: Color = Color.WHITE) -> void:
	var h := size * 0.5
	var x0 := c.x - h.x
	var x1 := c.x + h.x
	var y0 := c.y - h.y
	var y1 := c.y + h.y
	var z0 := c.z - h.z
	var z1 := c.z + h.z
	quad(key, Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.UP, [], col)
	quad(key, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(0, 0, 1), [], col)
	quad(key, Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(0, 0, -1), [], col)
	quad(key, Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(1, 0, 0), [], col)
	quad(key, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(-1, 0, 0), [], col)


func road_quad(a: Vector3, b: Vector3, hw: float, lanes: int, type: int, y: float = 0.0, key: String = "road") -> void:
	var d := (b - a).normalized()
	var r := Vector3(-d.z, 0.0, d.x)
	var L := a.distance_to(b)
	var up := Vector3(0, y, 0)
	var col := Color(lanes / 4.0, type / 8.0, hw / 16.0, 1.0)
	quad(key, a + r * hw + up, a - r * hw + up, b - r * hw + up, b + r * hw + up, Vector3.UP,
		[Vector2(hw, 0), Vector2(-hw, 0), Vector2(-hw, L), Vector2(hw, L)], col)


func add_box_collider(c: Vector3, size: Vector3, yaw: float = 0.0) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), c)
	cur.body.add_child(cs)
	return cs


func xf(pos: Vector3, yaw: float = 0.0, s: float = 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), pos)


func col_of(key: String, idx: int = -1) -> Color:
	var arr: Array = PAL[key]
	return Color(arr[(rng.randi() if idx < 0 else idx) % arr.size()])


# ------------------------------------------------------------------ modular buildings
func module(nm: String, t: Transform3D, tint: Color, custom: Color) -> void:
	if not cur.mods.has(nm):
		cur.mods[nm] = []
	cur.mods[nm].append([t, tint, custom])


func building(cx: float, cz: float, nx: int, nz: int, floors: int, style: String, opts: Dictionary = {}) -> float:
	## Axis aligned modular building. fronts: sides with doors/shop fronts (0=S,1=E,2=N,3=W). Returns roof height.
	var S: Dictionary = STYLES[style]
	var base: float = opts.get("base", WorldLayout.CURB_H)
	var tint: Color = opts.get("tint", col_of(style.replace("shop", "") if PAL.has(style.replace("shop", "")) else "apt"))
	var awn: Color = opts.get("awning", col_of("awning"))
	var custom := Color(awn.r, awn.g, awn.b, 1.0)
	var fronts: Array = opts.get("fronts", [0])
	var H := GH + (floors - 1) * FH
	for side in 4:
		var n := nx if side % 2 == 0 else nz
		var half := (nz if side % 2 == 0 else nx) * 2.0
		var rot: float = [0.0, PI * 0.5, PI, -PI * 0.5][side]
		var bas := Basis(Vector3.UP, rot)
		var normal := bas * Vector3(0, 0, 1)
		var tan := bas * Vector3(1, 0, 0)
		var is_front := side in fronts
		for k in n:
			var p := Vector3(cx, base, cz) + normal * half + tan * ((k - (n - 1) * 0.5) * 4.0)
			var gm: String = S.ground
			if is_front:
				gm = S.door if k == n / 2 else S.get("front", S.ground)
			module(gm, Transform3D(bas, p), tint, custom)
			for f in range(1, floors):
				var ups: Array = S.upper
				var um: String = ups[(k + f) % ups.size()] if ups.size() > 1 else ups[0]
				if not is_front and S.has("blank") and opts.get("blank_rear", false) and side == (fronts[0] + 2) % 4:
					um = S.blank
				module(um, Transform3D(bas, p + Vector3(0, GH + (f - 1) * FH, 0)), tint, custom)
			module(S.parapet, Transform3D(bas, p + Vector3(0, H, 0)), tint, custom)
	var w := nx * 4.0
	var d := nz * 4.0
	rect("roofdark" if style in ["office", "grid"] else "roof", cx - w * 0.5 + 0.2, cz - d * 0.5 + 0.2, cx + w * 0.5 - 0.2, cz + d * 0.5 - 0.2, base + H + 0.05)
	add_box_collider(Vector3(cx, base + H * 0.5, cz), Vector3(w, H, d))
	for sgn in [-1.0, 1.0]:
		add_box_collider(Vector3(cx, base + H + 0.4, cz + sgn * (d * 0.5 - 0.15)), Vector3(w, 0.8, 0.3))
		add_box_collider(Vector3(cx + sgn * (w * 0.5 - 0.15), base + H + 0.4, cz), Vector3(0.3, 0.8, d))
	building_boxes.append({"c": Vector3(cx, base, cz), "w": w, "d": d, "h": H})
	if opts.get("roof_props", true):
		var cnt := 1 + rng.randi() % 3
		for i in cnt:
			var px := cx + rng.randf_range(-w * 0.3, w * 0.3)
			var pz := cz + rng.randf_range(-d * 0.3, d * 0.3)
			var pn: String = ["prop_ac_unit", "prop_roof_vent", "prop_roof_tank", "prop_antenna", "prop_dish", "prop_roof_stair", "prop_ac_unit"][rng.randi() % 7]
			if pn == "prop_roof_tank" and floors > 9:
				pn = "prop_antenna"
			prop(pn, Vector3(px, base + H + 0.05, pz), rng.randf() * TAU, 1.0, false)
	return base + H


func model(nm: String, pos: Vector3, yaw: float = 0.0, tints: Dictionary = {}, collide: bool = true) -> MeshInstance3D:
	## Places a landmark / whole-model building as its own MeshInstance3D with an exact trimesh collider.
	var k: String = kit_of.get(nm, K_LAND)
	var m := MeshInstance3D.new()
	m.mesh = Assets.mesh(k, nm)
	m.name = nm
	m.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	cur.node.add_child(m)
	if not tints.is_empty():
		Assets.tint_node(m, tints)
	if collide:
		var sb := Assets.trimesh_body(m, G.L_WORLD)
		m.add_child(sb)
	return m


func anim_scene(rel: String, prefix: String, pos: Vector3, yaw: float = 0.0) -> Node3D:
	## Places an imported GLB that carries a Blender-authored animation and loops it.
	var n := Assets.inst(rel, prefix)
	cur.node.add_child(n)
	n.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	var ap := n.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null:
		for an in ap.get_animation_list():
			if an != "RESET":
				ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
				ap.play(an)
				break
	return n


# ------------------------------------------------------------------ props
func prop(nm: String, pos: Vector3, yaw: float = 0.0, s: float = 1.0, collide: bool = true, tint: Color = Color.WHITE) -> void:
	if not kit_of.has(nm):
		push_warning("Unknown prop " + nm)
		return
	if nm in TRIMESH_PROPS:
		model(nm, pos, yaw)
		return
	if not cur.props.has(nm):
		cur.props[nm] = []
	var t := xf(pos, yaw, s)
	var entry := {"xf": t, "tint": tint, "shape": null}
	cur.props[nm].append(entry)
	if nm == "prop_street_lamp" or nm == "prop_park_lamp":
		var lp := t * (Vector3(0, 7.6, 2.3) if nm == "prop_street_lamp" else Vector3(0, 3.7, 0))
		lamps.append(lp)
	if not collide or nm in NOCOL_PROPS:
		return
	var ab := Assets.mesh(kit_of[nm], nm).get_aabb()
	var size := ab.size * s
	var center := ab.get_center() * s
	if nm in POLE_PROPS:
		var hgt := minf(size.y, 3.2) if nm.begins_with("tree_") else size.y
		size = Vector3(0.36, hgt, 0.36) if not nm.begins_with("tree_") else Vector3(0.5 * s, hgt, 0.5 * s)
		center = Vector3(0, hgt * 0.5, 0)
		if nm == "tree_palm":
			center = Vector3(0, hgt * 0.5, -0.15)
	size = size.max(Vector3(0.12, 0.12, 0.12))
	var cs := add_box_collider(t.origin + Basis(Vector3.UP, yaw) * center, size, yaw)
	entry.shape = cs
	if not (nm in FIXED_PROPS):
		cs.set_meta("prop", {"name": nm, "chunk": cur, "list": cur.props[nm], "idx": cur.props[nm].size() - 1})


func scatter(nm: String, x0: float, z0: float, x1: float, z1: float, count: int, smin: float = 0.85, smax: float = 1.2, collide: bool = true, y: float = WorldLayout.CURB_H) -> void:
	for i in count:
		prop(nm, Vector3(rng.randf_range(x0, x1), y, rng.randf_range(z0, z1)), rng.randf() * TAU, rng.randf_range(smin, smax), collide)


func poi(id: String, label: String, pos: Vector3, icon: String, extra: Dictionary = {}) -> void:
	var d := {"id": id, "label": label, "pos": pos, "icon": icon}
	d.merge(extra)
	pois[id] = d


func interact(kind: String, pos: Vector3, radius: float, prompt: String, data: Dictionary = {}) -> void:
	interacts.append({"kind": kind, "pos": pos, "radius": radius, "prompt": prompt, "data": data})


func park(pos: Vector3, yaw: float, tag: String = "lot") -> void:
	parking.append({"pos": pos, "yaw": yaw, "tag": tag, "veh": null})


# ------------------------------------------------------------------ finishing
func _finish_chunk(c: Chunk) -> void:
	for key in c.st.keys():
		var s: SurfaceTool = c.st[key]
		var mi := MeshInstance3D.new()
		var mat_key: String = key.split("#")[0]
		s.set_material(gmats.get(mat_key, gmats["concrete"]))
		mi.mesh = s.commit()
		mi.name = "Geo_" + key
		if mat_key == "road":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.node.add_child(mi)
	for nm in c.mods.keys():
		var arr: Array = c.mods[nm]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = Assets.mesh(K_FACADE, nm)
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i][0])
			mm.set_instance_color(i, arr[i][1])
			mm.set_instance_custom_data(i, arr[i][2])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "MM_" + nm
		c.node.add_child(mmi)
	for nm in c.props.keys():
		var arr2: Array = c.props[nm]
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.use_colors = true
		mm2.use_custom_data = true
		mm2.mesh = Assets.mesh(kit_of[nm], nm)
		mm2.instance_count = arr2.size()
		for i in arr2.size():
			mm2.set_instance_transform(i, arr2[i].xf)
			mm2.set_instance_color(i, arr2[i].tint)
			mm2.set_instance_custom_data(i, arr2[i].tint)
			arr2[i]["mm"] = mm2
		var mmi2 := MultiMeshInstance3D.new()
		mmi2.multimesh = mm2
		mmi2.name = "P_" + nm
		if nm.begins_with("grass") or nm.begins_with("flower"):
			mmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi2.visibility_range_end = 90.0
		elif nm.begins_with("prop_") and not (nm in FIXED_PROPS):
			mmi2.visibility_range_end = 260.0
		c.node.add_child(mmi2)
		if nm.begins_with("tree_") and kit_of.has(nm + "_lod1"):
			mmi2.visibility_range_end = 110.0
			mmi2.visibility_range_end_margin = 10.0
			mmi2.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			var mm3 := MultiMesh.new()
			mm3.transform_format = MultiMesh.TRANSFORM_3D
			mm3.mesh = Assets.mesh(kit_of[nm], nm + "_lod1")
			mm3.instance_count = arr2.size()
			for i in arr2.size():
				mm3.set_instance_transform(i, arr2[i].xf)
			var mmi3 := MultiMeshInstance3D.new()
			mmi3.multimesh = mm3
			mmi3.visibility_range_begin = 110.0
			mmi3.visibility_range_begin_margin = 10.0
			mmi3.name = "PL_" + nm
			c.node.add_child(mmi3)


# ------------------------------------------------------------------ terrain / water / roads
func _build_terrain() -> void:
	chunk("terrain")
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 4.0
	var x0 := -344.0
	var z0 := -344.0
	var nx := 172
	var nz := 190
	var hs: Array = []
	for j in nz + 1:
		var row := PackedFloat32Array()
		row.resize(nx + 1)
		for i in nx + 1:
			var x := x0 + i * step
			var z := z0 + j * step
			var h := WorldLayout.height(x, z)
			if absf(x) < 272.0 and z > -179.0 and z < 177.0:
				h -= 0.12
			row[i] = h
		hs.append(row)
	for j in nz:
		for i in nx:
			var xa := x0 + i * step
			var za := z0 + j * step
			var p00 := Vector3(xa, hs[j][i], za)
			var p10 := Vector3(xa + step, hs[j][i + 1], za)
			var p11 := Vector3(xa + step, hs[j + 1][i + 1], za + step)
			var p01 := Vector3(xa, hs[j + 1][i], za + step)
			for tri in [[p00, p10, p11], [p00, p11, p01]]:
				for p in tri:
					var pd := WorldLayout.path_info(p.x, p.z).x if (p.x < -90.0 and p.z < -175.0) else 99.0
					s.set_color(Color(WorldLayout.sand_mask(p.x, p.z), 1.0 - smoothstep(2.5, 4.5, pd), 0, 1))
					s.set_normal(Vector3.UP)
					s.add_vertex(p)
	# coarse outer ring
	var cs := 32.0
	var R := 1280.0
	var n := int(R * 2.0 / cs)
	for j in n:
		for i in n:
			var xa := -R + i * cs
			var za := -R + j * cs
			if xa >= x0 and xa + cs <= x0 + nx * step and za >= z0 and za + cs <= z0 + nz * step:
				continue
			var pts: Array = []
			for o in [Vector2(0, 0), Vector2(cs, 0), Vector2(cs, cs), Vector2(0, cs)]:
				var px: float = xa + o.x
				var pz: float = za + o.y
				pts.append(Vector3(px, WorldLayout.height(px, pz) - 0.3, pz))
			for tri in [[pts[0], pts[1], pts[2]], [pts[0], pts[2], pts[3]]]:
				for p in tri:
					s.set_color(Color(WorldLayout.sand_mask(p.x, p.z), 0, 0, 1))
					s.set_normal(Vector3.UP)
					s.add_vertex(p)
	s.set_material(gmats["terrain"])
	var mi := MeshInstance3D.new()
	mi.mesh = s.commit()
	mi.name = "Terrain"
	cur.node.add_child(mi)
	# collision: fine square heightmap + coarse outer one
	var N := 361
	var data := PackedFloat32Array()
	data.resize(N * N)
	for j in N:
		for i in N:
			data[j * N + i] = WorldLayout.height(-360.0 + i * 2.0, -360.0 + j * 2.0)
	var hshape := HeightMapShape3D.new()
	hshape.map_width = N
	hshape.map_depth = N
	hshape.map_data = data
	var cshape := CollisionShape3D.new()
	cshape.shape = hshape
	cshape.scale = Vector3(2.0, 1.0, 2.0)
	cur.body.add_child(cshape)
	var M := 81
	var data2 := PackedFloat32Array()
	data2.resize(M * M)
	for j in M:
		for i in M:
			var x := -1280.0 + i * 32.0
			var z := -1280.0 + j * 32.0
			data2[j * M + i] = -40.0 if (absf(x) < 352.0 and absf(z) < 352.0) else WorldLayout.height(x, z) - 0.3
	var hshape2 := HeightMapShape3D.new()
	hshape2.map_width = M
	hshape2.map_depth = M
	hshape2.map_data = data2
	var cshape2 := CollisionShape3D.new()
	cshape2.shape = hshape2
	cshape2.scale = Vector3(32.0, 1.0, 32.0)
	cur.body.add_child(cshape2)


func _build_water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(3200, 3200)
	pm.subdivide_width = 80
	pm.subdivide_depth = 80
	water_mesh = MeshInstance3D.new()
	water_mesh.mesh = pm
	water_mesh.material_override = water_mat
	water_mesh.position = Vector3(0, WorldLayout.WATER, 300)
	water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_mesh.name = "Sea"
	add_child(water_mesh)


func _build_roads() -> void:
	chunk("roads")
	var L := WorldLayout
	for i in L.NX:
		for j in L.NZ:
			var c := L.inter_pos(Vector2i(i, j))
			road_quad(c - Vector3(0, 0, L.h_hw(j)), c + Vector3(0, 0, L.h_hw(j)), L.v_hw(i), 1, 1)
	for i in L.NX:
		for j in L.NZ - 1:
			var a := Vector3(L.VX[i], 0, L.HZ[j] + L.h_hw(j))
			var b := Vector3(L.VX[i], 0, L.HZ[j + 1] - L.h_hw(j + 1))
			road_quad(a, b, L.v_hw(i), L.v_lanes(i), 0)
			_crossing(a, Vector3(0, 0, 1), L.v_hw(i))
			_crossing(b, Vector3(0, 0, -1), L.v_hw(i))
	for j in L.NZ:
		for i in L.NX - 1:
			var a := Vector3(L.VX[i] + L.v_hw(i), 0, L.HZ[j])
			var b := Vector3(L.VX[i + 1] - L.v_hw(i + 1), 0, L.HZ[j])
			road_quad(a, b, L.h_hw(j), L.h_lanes(j), 0)
			_crossing(a, Vector3(1, 0, 0), L.h_hw(j))
			_crossing(b, Vector3(-1, 0, 0), L.h_hw(j))
	# signals / stop signs
	for i in L.NX:
		for j in L.NZ:
			var ix := Vector2i(i, j)
			var c := L.inter_pos(ix)
			for nb in L.neighbors(ix):
				var d := (c - L.inter_pos(nb)).normalized()
				var right := Vector3(-d.z, 0, d.x)
				var along_x := nb.y == j
				var hw := L.seg_hw(nb, ix)
				var pos := c - d * (L.inter_half(ix, along_x) + 2.4) + right * (hw + 1.0) + Vector3(0, L.CURB_H, 0)
				var bas := Basis(right, Vector3.UP, -d)
				var yaw := bas.get_euler().y
				if L.signalized(ix):
					prop("prop_traffic_light_A" if along_x else "prop_traffic_light_B", pos, yaw)
				elif L.neighbors(ix).size() >= 3:
					prop("prop_sign_stop", pos + right * 0.3, yaw)
				if nb.x > i or nb.y > j:
					prop("prop_sign_street", pos + right * 1.2 - d * 1.0, yaw)


func _crossing(at: Vector3, d: Vector3, hw: float) -> void:
	## Crosswalk + stop line at the end of a road segment; d points away from the intersection.
	road_quad(at + d * 0.7, at + d * 3.5, hw - 0.2, 1, 2, 0.012)
	var r := Vector3(-d.z, 0, d.x)
	# stop line on the half carrying traffic towards the intersection (their right side)
	var mid := at + d * 4.3 - r * (hw * 0.5)
	quad("road", mid - r * (hw * 0.5 - 0.2) - d * 0.2 + Vector3(0, 0.012, 0), mid + r * (hw * 0.5 - 0.2) - d * 0.2 + Vector3(0, 0.012, 0),
		mid + r * (hw * 0.5 - 0.2) + d * 0.2 + Vector3(0, 0.012, 0), mid - r * (hw * 0.5 - 0.2) + d * 0.2 + Vector3(0, 0.012, 0),
		Vector3.UP, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Color(0.25, 3.0 / 8.0, hw / 16.0, 1))


func _boundaries() -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = G.L_WORLD
	sb.collision_mask = 0
	sb.name = "Bounds"
	add_child(sb)
	for b in [[Vector3(620, 100, 0), Vector3(4, 400, 1300)], [Vector3(-620, 100, 0), Vector3(4, 400, 1300)],
			[Vector3(0, 100, -620), Vector3(1300, 400, 4)], [Vector3(0, 100, 700), Vector3(1300, 400, 4)],
			[Vector3(0, -30, 0), Vector3(2600, 2, 2600)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.position = b[0]
		sb.add_child(cs)


# ------------------------------------------------------------------ runtime prop interaction
func knock_prop(shape_node: Node, impulse: Vector3, at: Vector3) -> RigidBody3D:
	## Converts a static street prop into a physical rigid body (called when rammed, shot or blasted).
	if shape_node == null or not shape_node.has_meta("prop"):
		return null
	var info: Dictionary = shape_node.get_meta("prop")
	var entry: Dictionary = info.list[info.idx]
	if entry.get("gone", false):
		return null
	entry["gone"] = true
	var mm: MultiMesh = entry.get("mm")
	var t: Transform3D = entry.xf
	if mm != null:
		mm.set_instance_transform(info.idx, Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), t.origin - Vector3(0, 50, 0)))
	var cs := shape_node as CollisionShape3D
	var shape := cs.shape
	var ct := cs.transform
	cs.queue_free()
	var nm: String = info.name
	var rb := RigidBody3D.new()
	rb.collision_layer = G.L_DEBRIS
	rb.collision_mask = G.L_WORLD | G.L_VEHICLE | G.L_DEBRIS
	var vol := (shape as BoxShape3D).size
	rb.mass = clampf(vol.x * vol.y * vol.z * 220.0, 6.0, 400.0)
	rb.transform = Transform3D(ct.basis, ct.origin)
	var cs2 := CollisionShape3D.new()
	cs2.shape = shape
	rb.add_child(cs2)
	var mi := MeshInstance3D.new()
	mi.mesh = Assets.mesh(kit_of[nm], nm)
	mi.transform = rb.transform.affine_inverse() * t
	rb.add_child(mi)
	rb.set_meta("prop_name", nm)
	add_child(rb)
	rb.apply_impulse(impulse.limit_length(rb.mass * 14.0), at - rb.global_position)
	if G.fx:
		G.fx.prop_broken(nm, t.origin)
	get_tree().create_timer(18.0).timeout.connect(func(): if is_instance_valid(rb): rb.queue_free())
	return rb
