extends SceneTree
## Headless verification of the set-piece GLBs in res://gta/generated/models/misc/ against
## manifest_misc.json (SET-PIECE ARTIST tool).
##
## For every manifest entry it loads the GLB, checks the import structure
## FileRoot -> <id> (Node3D) -> parts, every listed mesh node, every marker (name + position),
## the bounding box against the manifest size, missing materials and the triangle count.
##
## Run:  tools\godot.ps1 -Mode script -Script res://gta/code/editor/misc_check_glbs.gd
## Optional user args: --verbose (dump each node tree)  --only=tram,shipwreck

const DIR := "res://gta/generated/models/misc/"


func _initialize() -> void:
	var verbose := false
	var only: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a == "--verbose":
			verbose = true
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
	var f := FileAccess.open(DIR + "manifest_misc.json", FileAccess.READ)
	if f == null:
		print("CHECK_FAIL misc: manifest_misc.json missing")
		quit(1)
		return
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if typeof(doc) != TYPE_DICTIONARY or not (doc as Dictionary).has("misc"):
		print("CHECK_FAIL misc: manifest_misc.json is not valid")
		quit(1)
		return
	var ok := 0
	var bad := 0
	var total_tris := 0
	for e: Dictionary in (doc as Dictionary)["misc"]:
		var id := String(e["id"])
		if not only.is_empty() and not only.has(id):
			continue
		var problems := _check(e, verbose)
		total_tris += int(problems.pop_back())
		if problems.is_empty():
			ok += 1
		else:
			bad += 1
			for p: String in problems:
				print("CHECK_FAIL misc ", id, ": ", p)
	print("MISC_CHECK_SUMMARY ok=", ok, " bad=", bad, " total_tris=", total_tris)
	quit(0 if bad == 0 else 1)


## Returns the list of problems; the LAST element is the triangle count (as String).
func _check(e: Dictionary, verbose: bool) -> Array:
	var problems: Array = []
	var id := String(e["id"])
	var path := DIR + String(e["file"])
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
	# mesh nodes
	for n: String in e.get("nodes", []):
		var mn := inst.find_child(n, true, false)
		if mn == null:
			problems.append("mesh node missing: " + n)
		elif not (mn is MeshInstance3D):
			problems.append("node is not a MeshInstance3D: " + n)
	# markers
	var markers: Dictionary = e.get("markers", {})
	for m: String in markers.keys():
		var node := inst.find_child(m, true, false) as Node3D
		if node == null:
			problems.append("marker missing: " + m)
			continue
		var want: Array = markers[m]
		var got := _xf_to(node, asset_root).origin
		if got.distance_to(Vector3(want[0], want[1], want[2])) > 0.02:
			problems.append("marker %s at %s, manifest says %s" % [m, str(got), str(want)])
	# geometry: bounds, tris, materials
	var tris := 0
	var mn_v := Vector3(INF, INF, INF)
	var mx_v := Vector3(-INF, -INF, -INF)
	var mats := {}
	var has_alpha_glass := false
	for mi: MeshInstance3D in _meshes(inst):
		var mesh := mi.mesh
		if mesh == null:
			problems.append("MeshInstance3D without mesh: " + mi.name)
			continue
		var xf := _xf_to(mi, asset_root)
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n_idx: int = (idx as PackedInt32Array).size() if idx != null else verts.size()
			@warning_ignore("integer_division")
			tris += n_idx / 3
			for v in verts:
				var w := xf * v
				mn_v = mn_v.min(w)
				mx_v = mx_v.max(w)
			var mat := mesh.surface_get_material(s)
			if mat == null:
				problems.append("surface without material on " + mi.name)
			else:
				mats[mat.resource_name] = true
				if mat.resource_name == "M_Glass" and mat is BaseMaterial3D:
					has_alpha_glass = (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	if mats.has("M_Glass") and not has_alpha_glass:
		problems.append("M_Glass imported without transparency")
	var size := mx_v - mn_v
	var want_size: Array = e.get("size", [])
	if want_size.size() == 3:
		var ws := Vector3(want_size[0], want_size[1], want_size[2])
		var dv := (size - ws).abs()
		if dv.x > 0.03 or dv.y > 0.03 or dv.z > 0.03:
			problems.append("size %s differs from manifest %s" % [str(size), str(ws)])
	if e.has("tris") and absi(int(e["tris"]) - tris) > 0:
		problems.append("tri count %d differs from manifest %d" % [tris, int(e["tris"])])
	print("MISC_ASSET ", id, " tris=", tris, " size=(%.2f, %.2f, %.2f)" % [size.x, size.y, size.z],
			" min_y=%.2f" % mn_v.y, " meshes=", _meshes(inst).size(), " markers=", markers.size(),
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
