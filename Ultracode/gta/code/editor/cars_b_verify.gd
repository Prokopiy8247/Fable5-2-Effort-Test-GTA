extends SceneTree
## Headless verification of the cars_b vehicle GLBs (suv, pickup, van, police_cruiser, taxi)
## against the vehicle node contract of docs/ARCHITECTURE.md 8.2 (VEHICLE ARTIST cars_b tool).
##
## For every vehicle: import structure FileRoot -> <id> -> parts, clean node names, required
## nodes, wheel pivots (origin at the wheel centre, axle along X, resting on the ground), door /
## tailgate hinge origins, marker positions, contract material names, livery paint colour,
## collision helper vertex counts and the visible triangle count.
##
## Run:  tools\godot.ps1 -Mode script -Script res://gta/code/editor/cars_b_verify.gd
## Optional user args: --only=suv,taxi   --tree (also print the node tree of every checked GLB:
## class, local position, surface materials, triangles - the print_scene_tree view, batched)

const DIR := "res://gta/generated/models/vehicles/"

const BASE: Array[String] = ["Body", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR", "SteeringWheel", "Hood",
	"Door_FL", "Door_FR", "Glass_Windshield", "Glass_Rear", "Glass_L", "Glass_R", "Seat_Driver",
	"Seat_Passenger_1", "Exit_Driver", "Exit_Passenger_1", "Light_Head_L", "Light_Head_R", "Light_Tail_L",
	"Light_Tail_R", "Exhaust", "Engine", "Col_Body", "Col_Cabin", "Body_LOD1"]
const REAR: Array[String] = ["Door_RL", "Door_RR", "Seat_Passenger_2", "Seat_Passenger_3", "Exit_Passenger_2",
	"Exit_Passenger_3"]
const MODS: Array[String] = ["Mod_Spoiler_A", "Mod_Spoiler_B", "Mod_BumperF_A", "Mod_BumperR_A", "Mod_Hood_A",
	"Mod_Skirts_A", "Mod_Roof_A", "Mod_Exhaust_A", "Mod_Grille_A"]

## id -> {extra nodes, length range (m), roof height range (m), wheel radius, body materials}
const SPECS := {
	"suv": {"rear": true, "mods": true, "extra": [], "len": [4.6, 5.0], "h": [1.75, 1.95], "r": 0.38,
		"mats": ["M_Paint_Primary", "M_Trim", "M_Chrome"]},
	"pickup": {"rear": true, "mods": true, "extra": ["Tailgate"], "len": [5.1, 5.5], "h": [1.78, 1.95], "r": 0.40,
		"mats": ["M_Paint_Primary", "M_Trim", "M_Chrome"]},
	"van": {"rear": false, "mods": false, "extra": ["Door_RearL", "Door_RearR", "Glass_Rear_R"], "len": [4.8, 5.2],
		"h": [1.95, 2.1], "r": 0.36, "mats": ["M_Paint_Primary", "M_Trim"],
		"nested": {"Glass_Rear": "Door_RearL", "Glass_Rear_R": "Door_RearR"}},
	"police_cruiser": {"rear": true, "mods": false, "extra": ["Trunk", "Siren"], "len": [4.75, 5.1], "h": [1.4, 1.65],
		"r": 0.35, "mats": ["M_Paint_Primary", "M_Siren_Red", "M_Siren_Blue", "P_PoliceWhite", "M_Trim"],
		"paint": Color("#1E3A6E")},
	"taxi": {"rear": true, "mods": false, "extra": ["Trunk", "TaxiSign"], "len": [4.55, 4.9], "h": [1.68, 1.8],
		"r": 0.34, "mats": ["M_Paint_Primary", "P_Black", "P_White", "M_Chrome"], "paint": Color("#F5C518")},
}


func _initialize() -> void:
	var only: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a == "--tree":
			_tree = true
	var bad := 0
	var ok := 0
	for id: String in SPECS:
		if not only.is_empty() and not only.has(id):
			continue
		var problems := _check(id, SPECS[id])
		if problems.is_empty():
			ok += 1
		else:
			bad += 1
			for p: String in problems:
				print("CHECK_FAIL cars_b ", id, ": ", p)
	print("CHECK_SUMMARY cars_b: ok=", ok, " failed=", bad)
	quit(0 if bad == 0 else 1)


var _tree := false


func _dump(n: Node, depth: int) -> void:
	var line := "TREE " + "  ".repeat(depth) + n.name + " [" + n.get_class() + "]"
	if n is Node3D:
		var p := (n as Node3D).position
		line += " pos=(%.3f, %.3f, %.3f)" % [p.x, p.y, p.z]
		var r := (n as Node3D).rotation_degrees
		if r.length() > 0.01:
			line += " rot=(%.1f, %.1f, %.1f)" % [r.x, r.y, r.z]
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		var sz := mi.mesh.get_aabb().size
		line += " tris=%d mats=%s aabb=(%.2f, %.2f, %.2f)" % [_tris(mi), str(_surface_names(mi)), sz.x, sz.y, sz.z]
	print(line)
	for c in n.get_children():
		_dump(c, depth + 1)


func _all_nodes(n: Node, out: Array[Node]) -> void:
	out.append(n)
	for c in n.get_children():
		_all_nodes(c, out)


func _surface_names(mi: MeshInstance3D) -> PackedStringArray:
	var out: PackedStringArray = []
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		out.append(m.resource_name if m != null else "<none>")
	return out


func _tris(mi: MeshInstance3D) -> int:
	return mi.mesh.get_faces().size() / 3


func _unique_points(mi: MeshInstance3D) -> int:
	var seen := {}
	for v: Vector3 in mi.mesh.get_faces():
		seen[Vector3i(roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0))] = true
	return seen.size()


func _check(id: String, spec: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var path := DIR + id + ".glb"
	if not ResourceLoader.exists(path):
		return ["file missing: " + path]
	var ps := load(path) as PackedScene
	if ps == null:
		return ["not a PackedScene"]
	var root := ps.instantiate()
	var asset := root.get_node_or_null(id) as Node3D
	if asset == null:
		root.free()
		return ["no asset root node '%s' under the file root" % id]
	var nodes: Array[Node] = []
	_all_nodes(asset, nodes)
	var by_name := {}
	for n in nodes:
		var nm := String(n.name)
		if nm.contains(":") or nm.contains(".") or nm.contains("@"):
			problems.append("unclean node name: " + nm)
		for ph: String in ["Cube", "Sphere", "Cylinder", "Plane", "Cone", "Empty", "Icosphere", "Mesh", "Object"]:
			if nm == ph or nm.begins_with(ph + "_0") or nm.begins_with(ph + "0"):
				problems.append("placeholder node name: " + nm)
		by_name[nm] = n
	if _tree:
		print("TREE_OF ", path)
		_dump(root, 0)
	var need: Array[String] = []
	need.append_array(BASE)
	if spec["rear"]:
		need.append_array(REAR)
	if spec["mods"]:
		need.append_array(MODS)
	for e: String in spec["extra"]:
		need.append(e)
	for nm in need:
		if not by_name.has(nm):
			problems.append("missing node " + nm)
	if not problems.is_empty():
		root.free()
		return problems

	# ---- meshes: materials, triangles
	var visible_tris := 0
	var all_mats := {}
	for n in nodes:
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var nm := String(mi.name)
		var names := _surface_names(mi)
		for s in names:
			all_mats[s] = true
			if s == "<none>" or s == "":
				problems.append("surface without material on " + nm)
		if nm.begins_with("Glass_") and (names.size() != 1 or names[0] != "M_Glass"):
			problems.append("%s must be a single M_Glass surface, has %s" % [nm, names])
		if nm.begins_with("Col_"):
			if names.size() != 1 or names[0] != "P_Collision":
				problems.append("%s must use P_Collision, has %s" % [nm, names])
			var pts := _unique_points(mi)
			if pts > 32:
				problems.append("%s has %d verts (> 32)" % [nm, pts])
		if nm.begins_with("Wheel_"):
			if not names.has("M_Tire") or not names.has("M_Rim"):
				problems.append("%s needs M_Tire + M_Rim, has %s" % [nm, names])
		if not (nm.begins_with("Mod_") or nm.begins_with("Col_") or nm == "Body_LOD1"):
			visible_tris += _tris(mi)
	var body := by_name["Body"] as MeshInstance3D
	var body_mats := _surface_names(body)
	for want: String in spec["mats"]:
		if not all_mats.has(want):
			problems.append("material %s not found in the file" % want)
	if not body_mats.has("M_Paint_Primary"):
		problems.append("Body has no M_Paint_Primary surface: %s" % [body_mats])
	if spec.has("paint"):
		for i in body.mesh.get_surface_count():
			var m := body.mesh.surface_get_material(i) as BaseMaterial3D
			if m != null and m.resource_name == "M_Paint_Primary":
				var c: Color = spec["paint"]
				var d := absf(m.albedo_color.r - c.r) + absf(m.albedo_color.g - c.g) + absf(m.albedo_color.b - c.b)
				if d > 0.06:
					problems.append("M_Paint_Primary authored colour %s differs from livery %s" % [m.albedo_color, c])
	if visible_tris > 7000:
		problems.append("visible triangles %d > 7000" % visible_tris)
	var lod := by_name["Body_LOD1"] as MeshInstance3D
	var lod_tris := _tris(lod)
	if lod_tris > _tris(body) / 4:
		problems.append("Body_LOD1 has %d tris (> 25%% of Body)" % lod_tris)

	# ---- size
	var a := body.get_aabb()
	var length := a.size.z
	var lr: Array = spec["len"]
	if length < lr[0] or length > lr[1]:
		problems.append("body length %.2f outside %s" % [length, lr])
	if absf(a.position.x + a.size.x * 0.5) > 0.03:
		problems.append("body not centred on X: %.3f" % (a.position.x + a.size.x * 0.5))
	# Body includes mud flaps / exhaust (they hang lower than the hull); the hull itself is Col_Body
	if a.position.y < 0.08 or a.position.y > 0.45:
		problems.append("lowest body part %.3f above the ground looks wrong" % a.position.y)
	var hull := (by_name["Col_Body"] as MeshInstance3D).get_aabb()
	if hull.position.y < 0.2 or hull.position.y > 0.5:
		problems.append("hull clearance (Col_Body bottom) %.3f looks wrong" % hull.position.y)

	# ---- wheels: origin at the centre, axle X, standing on the ground, front = -Z
	var r: float = spec["r"]
	for wn: String in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var w := by_name[wn] as MeshInstance3D
		if w == null:
			problems.append(wn + " is not a mesh")
			continue
		var wa := w.get_aabb()
		if (wa.position + wa.size * 0.5).length() > 0.012:
			problems.append("%s origin is not at the wheel centre (%s)" % [wn, wa.position + wa.size * 0.5])
		if wa.size.x > wa.size.y * 0.6 or absf(wa.size.y - wa.size.z) > 0.03:
			problems.append("%s axle is not along X (aabb %s)" % [wn, wa.size])
		if absf(wa.size.y * 0.5 - r) > 0.02:
			problems.append("%s radius %.3f, expected %.2f" % [wn, wa.size.y * 0.5, r])
		if absf(w.position.y - wa.size.y * 0.5) > 0.02:
			problems.append("%s does not stand on the ground (y=%.3f, r=%.3f)" % [wn, w.position.y, wa.size.y * 0.5])
		var left := wn.ends_with("L")
		var front := wn.begins_with("Wheel_F")
		if (w.position.x < 0.0) != left or (w.position.z < 0.0) != front:
			problems.append("%s is on the wrong corner: %s" % [wn, w.position])
		if w.rotation.length() > 0.001 or (w.scale - Vector3.ONE).length() > 0.001:
			problems.append("%s has a rotation / scale" % wn)

	# ---- hinges
	for dn: String in ["Door_FL", "Door_FR", "Door_RL", "Door_RR"]:
		if not by_name.has(dn):
			continue
		var d := by_name[dn] as MeshInstance3D
		var da := d.get_aabb()
		# origin on the front edge at the door bottom: the mesh extends towards +Z and up
		if da.position.z < -0.08 or da.position.z + da.size.z < 0.6:
			problems.append("%s hinge origin is not on its front edge (aabb z %.2f..%.2f)" % [dn, da.position.z, da.position.z + da.size.z])
		if da.position.y < -0.03 or da.position.y > 0.05:
			problems.append("%s origin is not at the door bottom (aabb y from %.3f)" % [dn, da.position.y])
		if (d.position.x < 0.0) != dn.ends_with("L"):
			problems.append("%s is on the wrong side" % dn)
	if by_name.has("Tailgate"):
		var t := by_name["Tailgate"] as MeshInstance3D
		var ta := t.get_aabb()
		if absf(ta.position.y) > 0.03 or ta.size.y < 0.35 or absf(ta.position.x + ta.size.x * 0.5) > 0.01:
			problems.append("Tailgate hinge origin is not on its bottom edge (aabb %s)" % ta)
		if t.position.z < 2.3:
			problems.append("Tailgate is not at the tail (z=%.2f)" % t.position.z)
	if by_name.has("Door_RearL"):
		var dl := by_name["Door_RearL"] as MeshInstance3D
		var dr := by_name["Door_RearR"] as MeshInstance3D
		var la := dl.get_aabb()
		var ra := dr.get_aabb()
		if la.position.x < -0.06 or la.position.x + la.size.x < 0.6 or dl.position.x > -0.6:
			problems.append("Door_RearL hinge origin is not on its outer edge (pos %s aabb x %.2f..%.2f)" % [dl.position, la.position.x, la.position.x + la.size.x])
		if ra.position.x + ra.size.x > 0.06 or ra.position.x > -0.6 or dr.position.x < 0.6:
			problems.append("Door_RearR hinge origin is not on its outer edge (pos %s aabb x %.2f..%.2f)" % [dr.position, ra.position.x, ra.position.x + ra.size.x])
	# ---- parts that must hang under another part (panes that swing with their door)
	if spec.has("nested"):
		var nested: Dictionary = spec["nested"]
		for child_name: String in nested:
			var c := by_name[child_name] as MeshInstance3D
			var want_parent := String(nested[child_name])
			var par := c.get_parent() as MeshInstance3D
			if par == null or String(par.name) != want_parent:
				problems.append("%s should be a child of %s (is under %s)" % [child_name, want_parent, c.get_parent().name])
				continue
			var pa := par.get_aabb().grow(0.02)
			var ca := c.transform * c.get_aabb()
			if not pa.encloses(ca):
				problems.append("%s does not sit inside %s (pane %s, door %s)" % [child_name, want_parent, ca, pa])
	var hood := by_name["Hood"] as MeshInstance3D
	var ha := hood.get_aabb()
	if ha.position.z + ha.size.z > 0.05:
		problems.append("Hood origin is not on its rear edge (aabb z %.2f..%.2f)" % [ha.position.z, ha.position.z + ha.size.z])

	# ---- markers
	var seat := by_name["Seat_Driver"] as Node3D
	if seat.position.x > -0.2 or seat.position.y < 0.3 or seat.position.y > 1.0:
		problems.append("Seat_Driver position looks wrong: %s" % seat.position)
	var exit := by_name["Exit_Driver"] as Node3D
	if absf(exit.position.y) > 0.01 or exit.position.x > -(a.size.x * 0.5 + 0.3):
		problems.append("Exit_Driver should be on the ground left of the body: %s" % exit.position)
	for ln: String in ["Light_Head_L", "Light_Head_R"]:
		var l := by_name[ln] as Node3D
		if l.position.z > -1.8:
			problems.append("%s is not at the nose: %s" % [ln, l.position])
	for ln: String in ["Light_Tail_L", "Light_Tail_R"]:
		var l := by_name[ln] as Node3D
		if l.position.z < 1.8:
			problems.append("%s is not at the tail: %s" % [ln, l.position])
	if by_name.has("Siren"):
		var s := by_name["Siren"] as Node3D
		if s.position.y < 1.4:
			problems.append("Siren marker is not on the roof: %s" % s.position)
	if by_name.has("TaxiSign"):
		var ts := by_name["TaxiSign"] as MeshInstance3D
		var names := _surface_names(ts)
		if not names.has("P_NeonYellow"):
			problems.append("TaxiSign has no P_NeonYellow surface: %s" % [names])
		else:
			var m := ts.mesh.surface_get_material(names.find("P_NeonYellow")) as BaseMaterial3D
			if m == null or not m.emission_enabled:
				problems.append("TaxiSign P_NeonYellow is not emissive")
		if ts.position.y < 1.6:
			problems.append("TaxiSign is not on the roof: %s" % ts.position)

	print("CHECK_INFO cars_b %s: nodes=%d visible_tris=%d lod_tris=%d body=%.2fx%.2fx%.2f (w,h,l) hull_clearance=%.2f wheel_r=%.2f body_mats=%s" % [
		id, nodes.size(), visible_tris, lod_tris, a.size.x, a.position.y + a.size.y, a.size.z, hull.position.y,
		(by_name["Wheel_FL"] as MeshInstance3D).get_aabb().size.y * 0.5, body_mats])
	if problems.is_empty():
		print("CHECK_OK cars_b ", id)
	root.free()
	return problems
