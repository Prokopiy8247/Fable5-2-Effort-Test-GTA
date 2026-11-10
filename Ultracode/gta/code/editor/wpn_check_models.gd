extends SceneTree
## Headless contract check for the weapon / projectile / pickup GLBs (docs/ARCHITECTURE.md 8.3).
## Compares every imported GLB with the manifests written by tools/blender/assets/weapons.py:
## node names (no Blender ".001" suffixes), mesh nodes, marker positions, material names,
## triangle count and bounds.
## Run:  tools\godot.ps1 -Mode script -Script res://gta/code/editor/wpn_check_models.gd
## Prints one "WPN_MODEL ..." line per asset, "CHECK_FAIL ..." per problem and a final
## "CHECK_RESULT wpn_check_models ok=N failed=M".

const WEAPON_DIR := "res://gta/generated/models/weapons/"
const PICKUP_DIR := "res://gta/generated/models/props/pickups/"

var _oks := 0
var _fails := 0


func _initialize() -> void:
	var wm := _read_json(WEAPON_DIR + "manifest.json")
	var pm := _read_json(PICKUP_DIR + "manifest_pickups.json")
	var weapons: Array = wm.get("weapons", [])
	var props: Array = pm.get("props", [])
	if weapons.is_empty():
		print("CHECK_FAIL wpn_check_models: weapon manifest missing or empty")
		_fails += 1
	if props.is_empty():
		print("CHECK_FAIL wpn_check_models: pickup manifest missing or empty")
		_fails += 1
	for w: Variant in weapons:
		_check(WEAPON_DIR, w as Dictionary)
	for p: Variant in props:
		_check(PICKUP_DIR, p as Dictionary)
	print("CHECK_RESULT wpn_check_models ok=%d failed=%d" % [_oks, _fails])
	quit(0 if _fails == 0 else 1)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(txt)
	if data is Dictionary:
		return data
	return {}


func _check(dir: String, d: Dictionary) -> void:
	var id := String(d.get("id", "?"))
	var path := dir + String(d.get("file", id + ".glb"))
	var errs: PackedStringArray = []
	if not ResourceLoader.exists(path):
		_report(id, ["file not found / not imported: " + path], "")
		return
	var ps := load(path) as PackedScene
	if ps == null:
		_report(id, ["not a PackedScene: " + path], "")
		return
	var inst := ps.instantiate()
	var root := inst.find_child(id, true, false) as Node3D
	if root == null:
		errs.append("asset root node '%s' missing" % id)
		root = inst as Node3D

	# every node: clean names, material names, triangles
	var tris := 0
	var mats := {}
	var stack: Array[Node] = [inst]
	var suffix := RegEx.create_from_string("(_|\\.)\\d{3}$")
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if suffix.search(String(n.name)) != null:
			errs.append("node name has a numeric suffix: " + String(n.name))
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				var mname := mat.resource_name if mat != null else "<none>"
				mats[mname] = true
				if not (mname.begins_with("P_") or mname.begins_with("M_")):
					errs.append("non-contract material '%s' on %s" % [mname, n.name])
				var am := mi.mesh as ArrayMesh
				if am != null:
					var il := am.surface_get_array_index_len(s)
					tris += (il if il > 0 else am.surface_get_array_len(s)) / 3

	# mesh nodes + bounds of the default (non-attachment) meshes in asset space
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for mname: Variant in d.get("meshes", ["Body"]):
		var mn := root.find_child(String(mname), true, false) as MeshInstance3D
		if mn == null or mn.mesh == null:
			errs.append("mesh node '%s' missing" % String(mname))
			continue
		if mn.get_parent() != root:
			errs.append("mesh node '%s' is not a direct child of the asset root" % String(mname))
		if String(mname).begins_with("Att_"):
			continue
		var bb := mn.transform * mn.mesh.get_aabb()
		lo = lo.min(bb.position)
		hi = hi.max(bb.end)
	var want_lo := _v3(d.get("aabb_min", []))
	var want_hi := _v3(d.get("aabb_max", []))
	if want_lo != Vector3.INF and (lo.distance_to(want_lo) > 0.004 or hi.distance_to(want_hi) > 0.004):
		errs.append("bounds differ: got %s..%s want %s..%s" % [lo, hi, want_lo, want_hi])

	# markers (Node3D empties, direct children, positions in Godot space)
	var markers: Dictionary = d.get("markers", {})
	for k: Variant in markers:
		var node := root.find_child(String(k), true, false) as Node3D
		if node == null:
			errs.append("marker '%s' missing" % String(k))
			continue
		if node is MeshInstance3D:
			errs.append("marker '%s' is a mesh" % String(k))
		var want := _v3(markers[k])
		if node.position.distance_to(want) > 0.002:
			errs.append("marker '%s' at %s, expected %s" % [String(k), node.position, want])

	# materials
	for m: Variant in d.get("materials", []):
		if not mats.has(String(m)):
			errs.append("material '%s' missing" % String(m))
	if bool(d.get("tintable", false)) and not mats.has("M_Weapon_Finish"):
		errs.append("M_Weapon_Finish missing")

	var want_tris := int(d.get("tris", 0))
	if want_tris > 0 and absi(tris - want_tris) > maxi(4, want_tris / 50):
		errs.append("triangle count %d differs from manifest %d" % [tris, want_tris])

	var size := hi - lo
	var info := "tris=%d size=(%.3f, %.3f, %.3f) meshes=%s markers=%s mats=%d" % [
		tris, size.x, size.y, size.z, str(d.get("meshes", [])), str(markers.keys()), mats.size()]
	inst.free()
	_report(id, errs, info)


func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.INF


func _report(id: String, errs: PackedStringArray, info: String) -> void:
	if errs.is_empty():
		_oks += 1
		print("WPN_MODEL ", id, " OK ", info)
	else:
		_fails += 1
		for e in errs:
			print("CHECK_FAIL wpn_check_models ", id, ": ", e)
		print("WPN_MODEL ", id, " FAILED ", info)
