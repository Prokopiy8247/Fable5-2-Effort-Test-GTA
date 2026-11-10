class_name BuildingFactory
extends RefCounted
## Assembles ordinary buildings from the Blender facade kits (res://gta/generated/models/buildings).
## Modules are tiled along the four facades of a box footprint and merged into ONE mesh per
## building (plus a far LOD mesh made of the modules' flat `lod1` parts). Per-building colour
## comes from the tint_a / tint_b instance uniforms of the shared palette material.

const KITS := {
	"office": {"mw": 4.0, "gh": 4.5, "fh": 3.5, "ph": 1.0, "win": Vector3(4.0, 3.5, 1.15)},
	"apt": {"mw": 4.0, "gh": 4.0, "fh": 3.2, "ph": 0.8, "win": Vector3(4.0, 3.2, 0.95)},
	"mixed": {"mw": 4.0, "gh": 4.5, "fh": 3.2, "ph": 0.8, "win": Vector3(4.0, 3.2, 1.45)},
	"ind": {"mw": 4.0, "gh": 4.0, "fh": 4.0, "ph": 0.6, "win": Vector3(4.0, 4.0, 0.15)},
	"house": {"mw": 3.0, "gh": 3.0, "fh": 3.0, "ph": 0.0, "win": Vector3(3.0, 3.0, 0.15)},
}
const DETAIL_FLOORS := 5          # storeys above this use the flat lod1 modules even up close
const LOD_DISTANCE := 120.0
const SIGNS := ["sign_cafe", "sign_bar", "sign_pizza", "sign_pawn", "sign_24h", "sign_market", "sign_tattoo",
	"sign_arcade", "sign_diner", "sign_gym", "sign_books", "sign_noodles", "sign_club", "sign_laundry", "sign_bank"]

static var _mod_cache: Dictionary = {}
static var stats := {"buildings": 0, "tris": 0, "lod_tris": 0, "missing": {}}

## De-indexed, part-local triangle soup of one GLB part, grouped by material.
static func _module(rel: String, part: String) -> Array:
	var key := rel + "#" + part
	if _mod_cache.has(key):
		return _mod_cache[key]
	var out: Array = []
	if Assets.has_model(rel):
		for p in Assets.mesh_parts(rel):
			var pname: String = p[2]
			if not pname.ends_with("__" + part):
				continue
			var mesh: Mesh = p[0]
			var xf: Transform3D = p[1]
			var rot := Transform3D(xf.basis.orthonormalized(), Vector3.ZERO)
			for s in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(s)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				var uv: Variant = arr[Mesh.ARRAY_TEX_UV]
				var idx: Variant = arr[Mesh.ARRAY_INDEX]
				var dv := PackedVector3Array()
				var dn := PackedVector3Array()
				var du := PackedVector2Array()
				var has_uv: bool = uv != null and (uv as PackedVector2Array).size() == v.size()
				if idx != null and (idx as PackedInt32Array).size() > 0:
					for i in (idx as PackedInt32Array):
						dv.append(v[i])
						dn.append(nrm[i])
						du.append(uv[i] if has_uv else Vector2.ZERO)
				else:
					dv = v
					dn = nrm
					if has_uv:
						du = uv
					else:
						du.resize(v.size())
				out.append({"mat": mesh.surface_get_material(s), "v": xf * dv, "n": rot * dn, "uv": du})
	_mod_cache[key] = out
	return out

class Acc:
	extends RefCounted
	var parts := {}    # Material -> [verts, normals, uvs]
	var tris := 0

	func add(mat: Material, v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array) -> void:
		if not parts.has(mat):
			parts[mat] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array()]
		# NOTE: `x as PackedVector3Array` yields a COPY in GDScript, so fetch, append and store back.
		var a: Array = parts[mat]
		var av: PackedVector3Array = a[0]
		var an: PackedVector3Array = a[1]
		var au: PackedVector2Array = a[2]
		av.append_array(v)
		an.append_array(n)
		au.append_array(uv)
		a[0] = av
		a[1] = an
		a[2] = au
		tris += v.size() / 3

	func add_module(module: Array, xf: Transform3D) -> void:
		var rot := Transform3D(xf.basis, Vector3.ZERO)
		for surf in module:
			add(surf["mat"], xf * (surf["v"] as PackedVector3Array), rot * (surf["n"] as PackedVector3Array), surf["uv"])

	## Quad a,b,c,d (any winding) facing `nrm`, flat palette colour.
	func quad(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, uv: Vector2, unit_uv := false) -> void:
		if (b - a).cross(c - a).dot(nrm) > 0.0:
			var t := b
			b = d
			d = t
		var uvs := PackedVector2Array([uv, uv, uv, uv, uv, uv])
		if unit_uv:
			uvs = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(0, 0)])
		add(mat, PackedVector3Array([a, b, c, a, c, d]), PackedVector3Array([nrm, nrm, nrm, nrm, nrm, nrm]), uvs)

	func box(mat: Material, lo: Vector3, hi: Vector3, uv: Vector2) -> void:
		quad(mat, Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.UP, uv)
		quad(mat, Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(0, 0, -1), uv)
		quad(mat, Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(0, 0, 1), uv)
		quad(mat, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z), Vector3(-1, 0, 0), uv)
		quad(mat, Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(1, 0, 0), uv)

	func mesh() -> ArrayMesh:
		if parts.is_empty():
			return null
		var m := ArrayMesh.new()
		for mat in parts.keys():
			var a: Array = parts[mat]
			if (a[0] as PackedVector3Array).is_empty():
				continue
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = a[0]
			arr[Mesh.ARRAY_NORMAL] = a[1]
			arr[Mesh.ARRAY_TEX_UV] = a[2]
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			m.surface_set_material(m.get_surface_count() - 1, mat)
		return m

# side: 0 = north (-Z), 1 = east (+X), 2 = south (+Z), 3 = west (-X)
static func side_xform(side: int, along: float, y: float, w: float, d: float) -> Transform3D:
	match side:
		0: return Transform3D(Basis.IDENTITY, Vector3(along, y, 0.0))
		1: return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(w, y, along))
		2: return Transform3D(Basis(Vector3.UP, PI), Vector3(along, y, d))
	return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, y, along))

static func side_index(letter: String) -> int:
	return "NESW".find(letter)

static func _fallback(acc: Acc, xf: Transform3D, mw: float, h: float, window: bool) -> void:
	# procedural flat module used when a kit GLB is missing (also a valid far LOD)
	var pal: Material = Assets.mat("Palette")
	var win: Material = Assets.mat("Window")
	var uvw := Assets.pal_uv("tint_a")
	var hw := mw * 0.5
	var n := xf.basis * Vector3(0, 0, -1)
	var p := func(x: float, y: float) -> Vector3: return xf * Vector3(x, y, 0.0)
	if not window:
		acc.quad(pal, p.call(-hw, 0), p.call(hw, 0), p.call(hw, h), p.call(-hw, h), n, uvw)
		return
	var x0 := -hw + 0.7
	var x1 := hw - 0.7
	var y0 := minf(1.0, h * 0.3)
	var y1 := h - 0.6
	acc.quad(pal, p.call(-hw, 0), p.call(hw, 0), p.call(hw, y0), p.call(-hw, y0), n, uvw)
	acc.quad(pal, p.call(-hw, y1), p.call(hw, y1), p.call(hw, h), p.call(-hw, h), n, uvw)
	acc.quad(pal, p.call(-hw, y0), p.call(x0, y0), p.call(x0, y1), p.call(-hw, y1), n, uvw)
	acc.quad(pal, p.call(x1, y0), p.call(hw, y0), p.call(hw, y1), p.call(x1, y1), n, uvw)
	acc.quad(win, p.call(x0, y0), p.call(x1, y0), p.call(x1, y1), p.call(x0, y1), n, Vector2.ZERO, true)

static func _put(detail: Acc, lod: Acc, id: String, xf: Transform3D, mw: float, h: float, flat_only: bool, folder := "buildings/") -> void:
	var rel := folder + id
	var md := _module(rel, "mesh")
	var ml := _module(rel, "lod1")
	if md.is_empty():
		stats["missing"][id] = true
		var win := not (id.ends_with("solid") or id.ends_with("parapet") or id == "ind_wall" or id == "house_wall")
		if not id.ends_with("parapet"):
			_fallback(detail, xf, mw, h, win)
			_fallback(lod, xf, mw, h, win)
		return
	if flat_only and not ml.is_empty():
		detail.add_module(ml, xf)
	else:
		detail.add_module(md, xf)
	if ml.is_empty():
		lod.add_module(md, xf)
	else:
		lod.add_module(ml, xf)

static func _pick(kit: String, spec: Dictionary, side: int, i: int, n: int, f: int, rng: RandomNumberGenerator) -> String:
	var style: int = spec.get("style", 0)
	var door_side: int = side_index(spec.get("door_side", "S"))
	var streets: String = spec.get("street_sides", "NESW")
	var on_street := streets.contains("NESW"[side])
	var mid := n / 2
	match kit:
		"office":
			if f == 0:
				if side == door_side and i == mid:
					return "off_ground_door"
				return "off_ground_glass" if on_street else "off_ground_solid"
			match style % 4:
				0: return "off_win_a"
				1: return "off_solid" if (i == 0 or i == n - 1) else "off_win_b"
				2: return "off_win_c"
			return "off_win_a" if i % 2 == 0 else "off_win_b"
		"apt":
			if f == 0:
				if side == door_side and i == mid:
					return "apt_ground_door"
				return "apt_ground_win"
			if (side == door_side or side == (door_side + 2) % 4) and (i + style) % 2 == 0 and n > 2:
				return "apt_balcony"
			if not on_street and (i == 0 or i == n - 1):
				return "apt_solid"
			return "apt_win_a" if (i + f + style) % 3 != 0 else "apt_win_b"
		"mixed":
			if f == 0:
				if not on_street:
					return "shop_solid"
				return "shop_door" if i % 3 == 1 else "shop_glass"
			if (i + style) % 2 == 0 and n > 2 and side == door_side:
				return "apt_balcony"
			return "apt_win_a" if (i + f) % 3 != 0 else "apt_win_b"
		"ind":
			if f == 0:
				if side == door_side:
					if i == mid or (n > 5 and i == mid - 2):
						return "ind_door_roll"
					if i == 0:
						return "ind_door_man"
				return "ind_wall"
			return "ind_wall_win" if (i + style) % 2 == 0 else "ind_wall"
	return "off_solid"

static func parapet_id(kit: String) -> String:
	match kit:
		"office": return "off_parapet"
		"apt", "mixed": return "apt_parapet"
		"ind": return "ind_parapet"
	return ""

## spec: {kit, x, z, nx, nz, floors, tint_a, tint_b, style, door_side, street_sides, front, seed, helipad, name}
## Returns the StaticBody3D of the building (placed at its min corner on top of the kerb).
static func build(parent: Node3D, spec: Dictionary) -> StaticBody3D:
	var kit_name: String = spec["kit"]
	var kit: Dictionary = KITS[kit_name]
	var mw: float = kit["mw"]
	var gh: float = kit["gh"]
	var fh: float = kit["fh"]
	var ph: float = kit["ph"]
	var nx: int = spec["nx"]
	var nz: int = spec["nz"]
	var floors: int = spec["floors"]
	var w := nx * mw
	var d := nz * mw
	var height := gh + float(floors - 1) * fh
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	var detail := Acc.new()
	var lod := Acc.new()
	var front: String = spec.get("front", "")
	var door_side: int = side_index(spec.get("door_side", "S"))
	var signs_placed := 0
	for side in 4:
		var n := nx if (side == 0 or side == 2) else nz
		var front_start := -1
		if front != "" and side == door_side and n >= 3:
			front_start = (n - 3) / 2
			var fx := side_xform(side, (float(front_start) + 1.5) * mw, 0.0, w, d)
			_put(detail, lod, front, fx, mw * 3.0, gh, false)
		for i in n:
			var along := (float(i) + 0.5) * mw
			for f in floors:
				if f == 0 and front_start >= 0 and i >= front_start and i < front_start + 3:
					continue
				var y := 0.0 if f == 0 else gh + float(f - 1) * fh
				var id := _pick(kit_name, spec, side, i, n, f, rng)
				_put(detail, lod, id, side_xform(side, along, y, w, d), mw, gh if f == 0 else fh, f >= DETAIL_FLOORS)
				# shop dressing: awnings over glass bays, a neon sign over doors
				if kit_name == "mixed" and f == 0:
					if id == "shop_glass" and rng.randf() < 0.55:
						var am := _module("buildings/shop_awning", "mesh")
						if not am.is_empty():
							detail.add_module(am, side_xform(side, along, 3.12, w, d))
					elif id == "shop_door" and rng.randf() < 0.9:
						var sid: String = SIGNS[(int(spec.get("seed", 0)) + signs_placed * 7 + side * 3) % SIGNS.size()]
						signs_placed += 1
						var sm := _module("buildings/signs/" + sid, "mesh")
						if not sm.is_empty():
							var sx := side_xform(side, along, 3.28, w, d)
							sx.origin += sx.basis * Vector3(0, 0, -0.06)
							detail.add_module(sm, sx)
			var pid := parapet_id(kit_name)
			if pid != "":
				_put(detail, lod, pid, side_xform(side, along, height, w, d), mw, ph, false)
	# roof slab
	var pal: Material = Assets.mat("Palette")
	var roof_uv := Assets.pal_uv("roof_gravel" if kit_name != "ind" else "roof_dark")
	for acc: Acc in [detail, lod]:
		acc.quad(pal, Vector3(0, height, 0), Vector3(w, height, 0), Vector3(w, height, d), Vector3(0, height, d), Vector3.UP, roof_uv)
	# roof clutter (merged into the detail mesh; tall silhouette pieces also in the LOD)
	_roof_props(detail, lod, spec, rng, w, d, height)
	stats["buildings"] += 1
	stats["tris"] += detail.tris
	stats["lod_tris"] += lod.tris
	return _finish(parent, spec, detail, lod, Vector3(w, height, d), kit["win"])

static func _roof_props(detail: Acc, lod: Acc, spec: Dictionary, rng: RandomNumberGenerator, w: float, d: float, h: float) -> void:
	var items: Array = []
	if spec.get("helipad", false) and w >= 14.0 and d >= 14.0:
		items.append(["roof_helipad", Vector3(w * 0.5, h + 0.02, d * 0.5), 0.0, false])
	else:
		var count := clampi(int(w * d / 160.0), 1, 6)
		for i in count:
			var id: String = ["roof_ac", "roof_ac", "roof_vent", "roof_duct", "roof_skylight"][rng.randi() % 5]
			items.append([id, Vector3(rng.randf_range(2.5, w - 2.5), h, rng.randf_range(2.5, d - 2.5)), float(rng.randi() % 4) * PI * 0.5, false])
		if w >= 12.0 and d >= 12.0:
			items.append(["roof_stairhut", Vector3(w - 3.0, h, 3.0), 0.0, true])
		if int(spec["floors"]) >= 9 and rng.randf() < 0.7:
			items.append(["roof_antenna", Vector3(w * 0.5, h, d * 0.5), 0.0, true])
		elif spec["kit"] != "office" and rng.randf() < 0.45:
			items.append(["roof_tank", Vector3(3.0, h, d - 3.0), 0.0, true])
	if spec.has("billboard"):
		items.append([String(spec["billboard"]), Vector3(w * 0.5, h, d * 0.5), float(spec.get("billboard_rot", 0.0)), true])
	for it in items:
		var m := _module("buildings/roof/" + String(it[0]), "mesh")
		if m.is_empty():
			m = _module("buildings/" + String(it[0]), "mesh")
		if m.is_empty():
			continue
		var xf := Transform3D(Basis(Vector3.UP, it[2]), it[1])
		detail.add_module(m, xf)
		if it[3]:
			lod.add_module(m, xf)

static func _finish(parent: Node3D, spec: Dictionary, detail: Acc, lod: Acc, size: Vector3, win_cell: Vector3,
		extra_shapes: Array = []) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = String(spec.get("name", "Building"))
	body.collision_layer = Phys.WORLD
	body.collision_mask = 0
	body.position = Vector3(float(spec["x"]), CityLayout.CURB_H, float(spec["z"]))
	body.set_meta("surface", &"concrete")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = size * 0.5
	body.add_child(cs)
	for sh in extra_shapes:
		body.add_child(sh)
	var tint_a: Color = spec.get("tint_a", Color.WHITE)
	var tint_b: Color = spec.get("tint_b", Color.WHITE)
	var dm := detail.mesh()
	var lm := lod.mesh()
	var use_lod := lm != null and lod.tris < detail.tris * 0.7
	if dm != null:
		var mi := MeshInstance3D.new()
		mi.name = "Detail"
		mi.mesh = dm
		if use_lod:
			mi.visibility_range_end = LOD_DISTANCE
			mi.visibility_range_end_margin = 6.0
		_tint(mi, tint_a, tint_b, win_cell)
		body.add_child(mi)
	if use_lod:
		var li := MeshInstance3D.new()
		li.name = "Lod"
		li.mesh = lm
		li.visibility_range_begin = LOD_DISTANCE
		li.visibility_range_begin_margin = 6.0
		_tint(li, tint_a, tint_b, win_cell)
		body.add_child(li)
	parent.add_child(body)
	return body

static func _tint(mi: MeshInstance3D, a: Color, b: Color, win_cell: Vector3) -> void:
	mi.set_instance_shader_parameter(&"tint_a", a.srgb_to_linear())
	mi.set_instance_shader_parameter(&"tint_b", b.srgb_to_linear())
	mi.set_instance_shader_parameter(&"win_cell", win_cell)

# ---------------------------------------------------------------- suburban houses
## spec: {x, z, nx (3..5), nz (2 or 3), floors (1..2), tint_a, tint_b, door_side ("N"|"S"), garage: bool, seed, name}
static func build_house(parent: Node3D, spec: Dictionary) -> StaticBody3D:
	var mw := 3.0
	var nx: int = spec["nx"]
	var nz: int = spec["nz"]
	var floors: int = spec["floors"]
	var w := nx * mw
	var d := nz * mw
	var height := 3.0 * floors
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	var detail := Acc.new()
	var lod := Acc.new()
	var door_side: int = side_index(spec.get("door_side", "S"))
	var garage: bool = spec.get("garage", false) and nx >= 4
	var door_i := 1 if garage else nx / 2
	for side in 4:
		var n := nx if (side == 0 or side == 2) else nz
		for f in floors:
			var skip_next := false
			for i in n:
				if skip_next:
					skip_next = false
					continue
				var along := (float(i) + 0.5) * mw
				var id := "house_wall_win" if (i + f + side) % 2 == 0 else "house_wall"
				if side == door_side and f == 0:
					# as seen from outside the module +X runs to the viewer's left; index along the wall is fine
					if garage and i == n - 2:
						_put(detail, lod, "house_wall_garage", side_xform(side, (float(i) + 1.0) * mw, 0.0, w, d), 6.0, 3.0, false)
						skip_next = true
						continue
					if i == door_i:
						id = "house_wall_door"
				elif f == 0 and side != door_side and i == 0 and n >= 3:
					id = "house_wall"
				_put(detail, lod, id, side_xform(side, along, float(f) * 3.0, w, d), mw, 3.0, false)
	# porch in front of the door
	var porch := _module("buildings/house_porch", "mesh")
	if not porch.is_empty():
		detail.add_module(porch, side_xform(door_side, (float(door_i) + 0.5) * mw, 0.0, w, d))
	# gable roof: ridge along X
	var roof_id := "house_roof_9" if nz >= 3 else "house_roof_6"
	var gable_id := "house_gable_9" if nz >= 3 else "house_gable_6"
	var ridge := 2.4 if nz >= 3 else 1.6
	var roof := _module("buildings/" + roof_id, "mesh")
	var roof_l := _module("buildings/" + roof_id, "lod1")
	for i in nx:
		var xf := Transform3D(Basis.IDENTITY, Vector3((float(i) + 0.5) * mw, height, d * 0.5))
		if roof.is_empty():
			_fallback_roof(detail, xf, mw, d, ridge)
			_fallback_roof(lod, xf, mw, d, ridge)
		else:
			detail.add_module(roof, xf)
			lod.add_module(roof if roof_l.is_empty() else roof_l, xf)
	var gable := _module("buildings/" + gable_id, "mesh")
	if not gable.is_empty():
		detail.add_module(gable, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, height, d * 0.5)))
		detail.add_module(gable, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(w, height, d * 0.5)))
		lod.add_module(gable, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, height, d * 0.5)))
		lod.add_module(gable, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(w, height, d * 0.5)))
	if rng.randf() < 0.6:
		var chim := _module("buildings/house_chimney", "mesh")
		if not chim.is_empty():
			detail.add_module(chim, Transform3D(Basis.IDENTITY, Vector3(w * 0.72, height + ridge * 0.35, d * 0.34)))
	# roof collision so the player can land / stand on it
	var prism := ConvexPolygonShape3D.new()
	prism.points = PackedVector3Array([
		Vector3(0, height, -0.4), Vector3(w, height, -0.4), Vector3(0, height, d + 0.4), Vector3(w, height, d + 0.4),
		Vector3(0, height + ridge, d * 0.5), Vector3(w, height + ridge, d * 0.5)])
	var rc := CollisionShape3D.new()
	rc.shape = prism
	stats["buildings"] += 1
	stats["tris"] += detail.tris
	stats["lod_tris"] += lod.tris
	spec["kit"] = "house"
	return _finish(parent, spec, detail, lod, Vector3(w, height, d), KITS["house"]["win"], [rc])

static func _fallback_roof(acc: Acc, xf: Transform3D, mw: float, d: float, ridge: float) -> void:
	var pal: Material = Assets.mat("Palette")
	var uv := Assets.pal_uv("tint_b")
	var hw := mw * 0.5
	var hd := d * 0.5 + 0.45
	var a := xf * Vector3(-hw, 0, -hd)
	var b := xf * Vector3(hw, 0, -hd)
	var c := xf * Vector3(hw, ridge, 0)
	var e := xf * Vector3(-hw, ridge, 0)
	var f := xf * Vector3(-hw, 0, hd)
	var g := xf * Vector3(hw, 0, hd)
	acc.quad(pal, a, b, c, e, Vector3(0, 0.6, -0.8).normalized(), uv)
	acc.quad(pal, f, g, c, e, Vector3(0, 0.6, 0.8).normalized(), uv)
