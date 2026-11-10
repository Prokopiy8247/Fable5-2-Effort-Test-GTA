extends SceneTree
## Headless verification of the street-furniture GLBs (STREET FURNITURE ARTIST) against
## res://gta/generated/models/props/manifest_street.json.
## Checks per prop: GLB loads, FileRoot -> <id> -> parts structure, every contract child mesh and
## marker named in the manifest exists, no surface without a material, emissive contract materials
## really are emissive, triangle count and bounding box match the manifest.
## Run:  tools\godot.ps1 -Mode script -Script res://gta/code/editor/props_street_verify.gd -Tail 100
## Optional user arg: --only=bench,cone

const DIR := "res://gta/generated/models/props/"
const EMISSIVE := ["M_LampGlow", "M_ScreenGlow"]


func _initialize() -> void:
	var only: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",", false)
	var path := DIR + "manifest_street.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("CHECK_FAIL props_street: cannot open ", path)
		quit(1)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("props"):
		print("CHECK_FAIL props_street: manifest is not {\"props\": [...]}")
		quit(1)
		return
	var props: Array = (data as Dictionary)["props"]
	var ok := 0
	var bad := 0
	var total_tris := 0
	var mats_seen := {}
	for e_v: Variant in props:
		var e: Dictionary = e_v
		var id := String(e.get("id", ""))
		if not only.is_empty() and not only.has(id):
			continue
		var problems: PackedStringArray = []
		var p := DIR + String(e.get("file", ""))
		var tris := 0
		var size := Vector3.ZERO
		var names: PackedStringArray = []
		if not ResourceLoader.exists(p):
			problems.append("glb not found by ResourceLoader")
		else:
			var ps := load(p) as PackedScene
			if ps == null:
				problems.append("glb is not a PackedScene")
			else:
				var root := ps.instantiate()
				var asset := root.get_node_or_null(NodePath(id))
				if asset == null:
					problems.append("asset root node '%s' missing under the file root" % id)
				for c_v: Variant in (e.get("children", []) as Array):
					var c := String(c_v)
					var n := root.find_child(c, true, false)
					if n == null:
						problems.append("child mesh '%s' missing" % c)
					elif not (n is MeshInstance3D):
						problems.append("child '%s' is %s, not MeshInstance3D" % [c, n.get_class()])
				for m_v: Variant in (e.get("markers", []) as Array):
					var m := String(m_v)
					if root.find_child(m, true, false) == null:
						problems.append("marker '%s' missing" % m)
				var box := AABB()
				var first := true
				var stack: Array = [[root, Transform3D.IDENTITY]]
				while not stack.is_empty():
					var item: Array = stack.pop_back()
					var node: Node = item[0]
					var xf: Transform3D = item[1]
					if node is Node3D and node != root:
						xf = xf * (node as Node3D).transform
					if node != root:
						names.append(String(node.name))
					if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
						var mesh := (node as MeshInstance3D).mesh
						var wb := xf * mesh.get_aabb()
						if first:
							box = wb
							first = false
						else:
							box = box.merge(wb)
						for s in mesh.get_surface_count():
							var mat := mesh.surface_get_material(s)
							if mat == null:
								problems.append("surface %d of '%s' has no material" % [s, node.name])
							else:
								mats_seen[mat.resource_name] = true
								var must_glow := EMISSIVE.has(mat.resource_name) or mat.resource_name.begins_with("P_Neon")
								if must_glow and not (mat is BaseMaterial3D and (mat as BaseMaterial3D).emission_enabled):
									problems.append("material %s is not emissive" % mat.resource_name)
							var arr := mesh.surface_get_arrays(s)
							var idx: Variant = arr[Mesh.ARRAY_INDEX]
							if idx != null and (idx as PackedInt32Array).size() > 0:
								tris += (idx as PackedInt32Array).size() / 3
							else:
								tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
					for ch in node.get_children():
						stack.append([ch, xf])
				size = box.size
				var want: Array = e.get("size", [0, 0, 0])
				var ws := Vector3(float(want[0]), float(want[1]), float(want[2]))
				var sdiff := (size - ws).abs()
				if sdiff.x > 0.03 or sdiff.y > 0.03 or sdiff.z > 0.03:
					problems.append("size %s differs from manifest %s" % [str(size), str(ws)])
				var wc: Array = e.get("center", [0, 0, 0])
				var cdiff := (box.get_center() - Vector3(float(wc[0]), float(wc[1]), float(wc[2]))).abs()
				if cdiff.x > 0.03 or cdiff.y > 0.03 or cdiff.z > 0.03:
					problems.append("centre %s differs from manifest %s" % [str(box.get_center()), str(wc)])
				if tris != int(e.get("tris", -1)):
					problems.append("tris %d differ from manifest %d" % [tris, int(e.get("tris", -1))])
				if tris < 30 or tris > 900:
					problems.append("tris %d outside the 30-900 budget" % tris)
				root.free()
		total_tris += tris
		if problems.is_empty():
			ok += 1
			print("PROP_OK %s tris=%d size=(%.2f, %.2f, %.2f) nodes=%s" % [id, tris, size.x, size.y, size.z, str(names)])
		else:
			bad += 1
			print("CHECK_FAIL props_street %s: %s" % [id, "; ".join(problems)])
	var mat_names: Array = mats_seen.keys()
	mat_names.sort()
	print("PROPS_MATERIALS ", mat_names.size(), " ", str(mat_names))
	print("CHECK_SUMMARY props_street ok=%d fail=%d total_tris=%d" % [ok, bad, total_tris])
	quit(0 if bad == 0 else 1)
