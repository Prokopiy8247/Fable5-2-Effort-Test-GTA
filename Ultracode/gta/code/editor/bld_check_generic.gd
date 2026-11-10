extends SceneTree
## Headless verification of the generic building GLBs in res://gta/generated/models/buildings/
## against manifest_generic.json (BUILDING KIT ARTIST tool, see docs/BUILDING_KIT.md).
##
## For every manifest entry it loads the GLB and checks:
##   * import structure  FileRoot -> <id> (Node3D) -> Building [, Building_Glass, Building_Detail, Building_Neon]
##   * every node listed in the manifest exists and is a MeshInstance3D, no surface without material
##   * window glass: every surface of Building_Glass is M_Window, M_Window is used nowhere else, UVs present
##   * neon: every surface of Building_Neon is an emissive P_Neon* material
##   * footprint [x, z] == bounds of the `Building` node, height == top of everything, tri count
##   * origin: the `Building` shell is centred on the origin (manifest center_offset), foundation below y = 0
##   * overhang: Detail / Neon parts never leave the footprint box at the sides or the back, and the
##     manifest "overhang" numbers (front / back / left / right) match the GLB
##   * materials: only shared palette / contract materials (P_* / M_*), no placeholder node names
##   * parking category: ramp_slope <= 0.18, clear_height >= 2.6, lane_width_min >= 3.5, collision_nodes exist,
##     route_up present; triangle guide (0.4 k .. 5 k, reported as a NOTE, not a failure)
##
## Run:  tools\godot.ps1 -Mode script -Script res://gta/code/editor/bld_check_generic.gd
## Optional user args:  --verbose (dump node trees)   --only=office_a,parking_a   --manifest=manifest_generic.json

const DIR := "res://gta/generated/models/buildings/"
const PART_NAMES := ["Building", "Building_Glass", "Building_Detail", "Building_Neon"]


func _initialize() -> void:
	var verbose := false
	var only: PackedStringArray = []
	var manifest := "manifest_generic.json"
	for a: String in OS.get_cmdline_user_args():
		if a == "--verbose":
			verbose = true
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a.begins_with("--manifest="):
			manifest = a.substr(11)
	var f := FileAccess.open(DIR + manifest, FileAccess.READ)
	if f == null:
		print("CHECK_FAIL bld: ", manifest, " missing")
		quit(1)
		return
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if typeof(doc) != TYPE_DICTIONARY or not (doc as Dictionary).has("buildings"):
		print("CHECK_FAIL bld: ", manifest, " is not {\"buildings\": [...]}")
		quit(1)
		return
	var ok := 0
	var bad := 0
	var total_tris := 0
	var cats := {}
	for e: Dictionary in (doc as Dictionary)["buildings"]:
		var id := String(e.get("id", "?"))
		if not only.is_empty() and not only.has(id):
			continue
		var problems := _check(e, verbose)
		total_tris += int(problems.pop_back())
		cats[String(e.get("category", "?"))] = int(cats.get(String(e.get("category", "?")), 0)) + 1
		if problems.is_empty():
			ok += 1
		else:
			bad += 1
			for p: String in problems:
				print("CHECK_FAIL bld ", id, ": ", p)
	print("BLD_CHECK_SUMMARY ok=", ok, " bad=", bad, " total_tris=", total_tris, " categories=", cats)
	quit(0 if bad == 0 else 1)


## Returns the list of problems; the LAST element is the triangle count (as String).
func _check(e: Dictionary, verbose: bool) -> Array:
	var problems: Array = []
	var id := String(e.get("id", "?"))
	for key: String in ["id", "file", "category", "footprint", "height", "landmark", "collision", "entrance", "tags"]:
		if not e.has(key):
			problems.append("manifest key missing: " + key)
	var path := DIR + String(e.get("file", id + ".glb"))
	if not ResourceLoader.exists(path):
		problems.append("file not imported: " + path)
		problems.append("0")
		return problems
	var ps := load(path) as PackedScene
	if ps == null:
		problems.append("not a PackedScene")
		problems.append("0")
		return problems
	var inst := ps.instantiate() as Node3D
	var asset_root := inst.get_node_or_null(NodePath(id)) as Node3D
	if asset_root == null:
		problems.append("asset root node '%s' missing under the file root (children: %s)" % [id, str(_child_names(inst))])
		asset_root = inst
	for n: String in e.get("nodes", ["Building"]):
		var mn := asset_root.get_node_or_null(NodePath(n))
		if mn == null:
			problems.append("mesh node missing: " + n)
		elif not (mn is MeshInstance3D):
			problems.append("node is not a MeshInstance3D: " + n)
	if asset_root.get_node_or_null(^"Building") == null:
		problems.append("required node 'Building' missing")
	var tris := 0
	var mn_all := Vector3(INF, INF, INF)
	var mx_all := Vector3(-INF, -INF, -INF)
	var mn_body := Vector3(INF, INF, INF)
	var mx_body := Vector3(-INF, -INF, -INF)
	var mats := {}
	var window_tris := 0
	for mi: MeshInstance3D in _meshes(inst):
		var mesh := mi.mesh
		if mesh == null:
			problems.append("MeshInstance3D without mesh: " + mi.name)
			continue
		if not PART_NAMES.has(String(mi.name)):
			problems.append("unexpected mesh node name: " + mi.name)
		var xf := _xf_to(mi, asset_root)
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n_idx: int = (idx as PackedInt32Array).size() if idx != null else verts.size()
			@warning_ignore("integer_division")
			var st := n_idx / 3
			tris += st
			for v in verts:
				var w := xf * v
				mn_all = mn_all.min(w)
				mx_all = mx_all.max(w)
				if mi.name == &"Building":
					mn_body = mn_body.min(w)
					mx_body = mx_body.max(w)
			var mat := mesh.surface_get_material(s)
			if mat == null:
				problems.append("surface without material on " + mi.name)
				continue
			var mname := mat.resource_name
			mats[mname] = true
			if mi.name == &"Building_Glass":
				window_tris += st
				if mname != "M_Window":
					problems.append("Building_Glass uses %s (must be M_Window only)" % mname)
				if arrays[Mesh.ARRAY_TEX_UV] == null:
					problems.append("Building_Glass has no UVs (lit-window cells)")
			elif mname == "M_Window":
				problems.append("M_Window used outside Building_Glass (on %s)" % mi.name)
			if mi.name == &"Building_Neon":
				if not mname.begins_with("P_Neon"):
					problems.append("Building_Neon uses %s (must be P_Neon*)" % mname)
				elif mat is BaseMaterial3D and not (mat as BaseMaterial3D).emission_enabled:
					problems.append("%s imported without emission" % mname)
	var size_body := mx_body - mn_body
	var fp: Array = e.get("footprint", [0.0, 0.0])
	if absf(size_body.x - float(fp[0])) > 0.05 or absf(size_body.z - float(fp[1])) > 0.05:
		problems.append("Building footprint (%.2f, %.2f) differs from manifest %s" % [size_body.x, size_body.z, str(fp)])
	if absf(mx_all.y - float(e.get("height", 0.0))) > 0.05:
		problems.append("height %.2f differs from manifest %s" % [mx_all.y, str(e.get("height"))])
	var co: Array = e.get("center_offset", [0.0, 0.0])
	var cx := (mn_body.x + mx_body.x) * 0.5
	var cz := (mn_body.z + mx_body.z) * 0.5
	if absf(cx - float(co[0])) > 0.05 or absf(cz - float(co[1])) > 0.05:
		problems.append("Building centre (%.2f, %.2f) differs from manifest center_offset %s" % [cx, cz, str(co)])
	if absf(cx) > 0.5 or absf(cz) > 0.5:
		problems.append("Building shell is not centred on the origin: (%.2f, %.2f)" % [cx, cz])
	if mn_body.y > -0.5:
		problems.append("no foundation skirt below ground (min y %.2f)" % mn_body.y)
	if e.has("tris") and int(e["tris"]) != tris:
		problems.append("tri count %d differs from manifest %d" % [tris, int(e["tris"])])
	var ent: Array = e.get("entrance", [0.0, 0.0])
	if absf(float(ent[0])) > float(fp[0]) * 0.5 + 0.1 or absf(float(ent[1])) > float(fp[1]) * 0.5 + 0.1:
		problems.append("entrance %s lies outside the footprint" % str(ent))
	# how far Detail / Neon parts (awnings, signs) stick out of the box collider footprint
	var over := maxf(maxf(mx_all.x - mx_body.x, mn_body.x - mn_all.x), maxf(mx_all.z - mx_body.z, mn_body.z - mn_all.z))
	# front = -Z, back = +Z, left = -X, right = +X
	var oh := {"front": maxf(0.0, mn_body.z - mn_all.z), "back": maxf(0.0, mx_all.z - mx_body.z),
			"left": maxf(0.0, mn_body.x - mn_all.x), "right": maxf(0.0, mx_all.x - mx_body.x)}
	for side: String in ["back", "left", "right"]:
		if float(oh[side]) > 0.05:
			problems.append("non-solid parts stick %.2f m out of the footprint on the %s side" % [float(oh[side]), side])
	if float(oh["front"]) > 1.6:
		problems.append("front overhang %.2f m is more than the 1.6 m street-side allowance" % float(oh["front"]))
	if e.has("overhang"):
		var mo: Dictionary = e["overhang"]
		for side: String in oh.keys():
			if absf(float(mo.get(side, 0.0)) - float(oh[side])) > 0.03:
				problems.append("overhang %s %.2f differs from manifest %s" % [side, float(oh[side]), str(mo.get(side))])
	else:
		problems.append("manifest key missing: overhang")
	for mname: String in mats.keys():
		if not (mname.begins_with("P_") or mname.begins_with("M_")):
			problems.append("non-palette material: " + mname)
	if String(e.get("category", "")) == "parking":
		if float(e.get("ramp_slope", 1.0)) > 0.18 + 1e-4:
			problems.append("ramp_slope %s above 0.18" % str(e.get("ramp_slope")))
		if float(e.get("clear_height", 0.0)) < 2.6:
			problems.append("clear_height %s below 2.6 m" % str(e.get("clear_height")))
		if float(e.get("lane_width_min", 0.0)) < 3.5:
			problems.append("lane_width_min %s below 3.5 m" % str(e.get("lane_width_min")))
		if (e.get("route_up", []) as Array).size() < 4:
			problems.append("route_up missing")
		for cn: Variant in e.get("collision_nodes", []):
			if asset_root.get_node_or_null(NodePath(String(cn))) == null:
				problems.append("collision node missing: " + String(cn))
	if tris > 5000 or tris < 400:
		print("BLD_NOTE ", id, ": ", tris, " tris is outside the 0.4 k .. 5 k guide for generic buildings")
	print("BLD_ASSET ", id, " [", e.get("category", "?"), "] tris=", tris, " footprint=(%.2f, %.2f)" % [size_body.x, size_body.z],
			" height=%.2f" % mx_all.y, " overhang=%.2f" % over, " window_tris=", window_tris, " meshes=", _meshes(inst).size(),
			" mats=", mats.keys().size(), " ", "OK" if problems.is_empty() else "PROBLEMS")
	if verbose:
		_dump(inst, 1)
	inst.free()
	problems.append(str(tris))
	return problems


func _child_names(n: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for c in n.get_children():
		out.append(c.name)
	return out


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


## Transform of `node` expressed in the space of `ancestor` (works outside the scene tree).
func _xf_to(node: Node3D, ancestor: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _dump(n: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + n.name + " [" + n.get_class() + "]"
	if n is Node3D:
		var p := (n as Node3D).position
		line += " pos=(%.3f, %.3f, %.3f)" % [p.x, p.y, p.z]
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m := (n as MeshInstance3D).mesh
		var names: PackedStringArray = []
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			names.append(mat.resource_name if mat != null else "<none>")
		line += " mats=" + str(names)
	print(line)
	for c in n.get_children():
		_dump(c, depth + 1)
