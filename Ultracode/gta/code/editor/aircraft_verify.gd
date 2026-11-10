extends SceneTree
## Headless verification of the four aircraft GLBs (asset contract: node names, materials,
## origins, axes, ground contact). Author: aircraft artist.
## Run:  tools\godot.ps1 -Mode script -Script res://gta/code/editor/aircraft_verify.gd -Tail 300
## Optional user args: --tree (dump the full node tree of every aircraft), --only=<id>

const DIR := "res://gta/generated/models/vehicles/"

const HELI_NODES := ["Body", "Rotor_Main", "Rotor_Tail", "RotorBlur_Main", "Glass_Windshield",
	"Glass_L", "Glass_R", "Door_FL", "Door_FR", "Seat_Driver", "Seat_Passenger_1", "Seat_Passenger_2",
	"Seat_Passenger_3", "Exit_Driver", "Exit_Passenger_1", "Engine", "Light_Head", "Light_Tail",
	"Light_Head_L", "Light_Head_R", "Light_Tail_L", "Light_Tail_R", "Col_Body", "Col_Tail"]
const PLANE_NODES := ["Body", "Wheel_Nose", "Wheel_L", "Wheel_R", "Aileron_L", "Aileron_R",
	"Elevator", "Rudder", "Flap_L", "Flap_R", "Glass_Windshield", "Seat_Driver", "Seat_Passenger_1",
	"Exit_Driver", "Engine", "Light_Head", "Light_Tail", "Light_Head_L", "Light_Head_R", "Light_Tail_L",
	"Light_Tail_R", "Col_Body", "Col_Wing", "Col_Tail"]

var SPEC := {
	"heli_civil": {
		"nodes": HELI_NODES + (["Door_RL", "Door_RR", "Glass_RL", "Glass_RR"]),
		"mats": ["M_Paint_Primary", "M_Paint_Secondary", "M_Glass", "M_RotorBlur", "M_Trim", "M_Interior", "P_Collision"],
		"body_len": 9.3, "rotor_d": 9.5,  # fuselage incl. tail fin / main rotor diameter
	},
	"heli_police": {
		"nodes": HELI_NODES + (["Searchlight", "SensorBall", "Seat_Gunner_L", "Seat_Gunner_R", "Siren"]),
		"mats": ["P_PoliceBlue", "P_PoliceWhite", "P_BadgeGold", "M_Glass", "M_RotorBlur", "M_Siren_Red", "M_Siren_Blue", "P_Collision"],
		"body_len": 10.7, "rotor_d": 10.4,
	},
	"plane_prop": {
		"nodes": PLANE_NODES + (["Propeller", "PropBlur", "Door_FL", "Door_FR", "Glass_L", "Glass_R", "Glass_Rear",
			"Seat_Passenger_2", "Seat_Passenger_3"]),
		"mats": ["M_Paint_Primary", "M_Paint_Secondary", "M_Glass", "M_RotorBlur", "M_Tire", "M_Rim", "P_Collision"],
		"length": 7.8, "span": 10.5,
	},
	"plane_jet": {
		"nodes": PLANE_NODES + (["Canopy", "Glass_Canopy", "Exhaust_L", "Exhaust_R"]),
		"mats": ["M_Paint_Primary", "M_Paint_Secondary", "M_Glass", "M_Tire", "M_Rim", "M_Chrome", "P_Collision"],
		"length": 11.0, "span": 8.8,
	},
}

var _dump_tree := false
var _root: Node3D = null
var _only := ""


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a == "--tree":
			_dump_tree = true
		elif a.begins_with("--only="):
			_only = a.substr(7)
	var total_fail := 0
	for id: String in SPEC.keys():
		if _only != "" and _only != id:
			continue
		total_fail += _verify(id)
	print("CHECK_SUMMARY aircraft_verify fails=%d" % total_fail)
	quit(0 if total_fail == 0 else 1)


func _verify(id: String) -> int:
	var path := DIR + id + ".glb"
	if not ResourceLoader.exists(path):
		print("CHECK_FAIL ", id, ": file missing ", path)
		return 1
	var ps := load(path) as PackedScene
	if ps == null:
		print("CHECK_FAIL ", id, ": not a PackedScene")
		return 1
	var file_root := ps.instantiate() as Node3D
	_root = file_root
	var issues: PackedStringArray = []
	var spec: Dictionary = SPEC[id]

	# structure: FileRoot -> <id> -> parts
	var asset := file_root.find_child(id, true, false) as Node3D
	if asset == null:
		issues.append("asset root node '%s' missing (file root children: %s)" % [id, str(file_root.get_children().map(func(c: Node) -> String: return String(c.name)))])
		asset = file_root

	# required nodes
	for n: String in spec["nodes"]:
		var node := file_root.find_child(n, true, false)
		if node == null:
			issues.append("missing node " + n)
	# stray Blender suffixes / duplicates
	var seen := {}
	for n: Node in _all(file_root):
		var nm := String(n.name)
		var re := RegEx.create_from_string("_\\d{3}$")
		if re.search(nm) != null:
			issues.append("suffixed node name " + nm)
		if seen.has(nm):
			issues.append("duplicate node name " + nm)
		seen[nm] = true

	# materials, triangles, bounds
	var mats := {}
	var tris := 0
	var aabb := AABB()
	var first := true
	for n: Node in _all(file_root):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var helper := String(mi.name).begins_with("Col_") or String(mi.name).contains("Blur")
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			var mname := mat.resource_name if mat != null else "<none>"
			mats[mname] = mat
			if mat == null:
				issues.append("surface without material on " + String(mi.name))
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var vtx: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			tris += (idx.size() if idx.size() > 0 else vtx.size()) / 3
		if helper:
			if String(mi.name).begins_with("Col_"):
				var cv := _unique_verts(mi.mesh)
				if cv > 32:
					issues.append("%s has %d unique verts (> 32)" % [mi.name, cv])
			continue
		var g := _xf(mi) * mi.mesh.get_aabb()
		aabb = g if first else aabb.merge(g)
		first = false
	for m: String in spec["mats"]:
		if not mats.has(m):
			issues.append("missing material " + m)
	for m: String in ["M_Glass", "M_RotorBlur"]:
		if mats.has(m):
			var sm := mats[m] as BaseMaterial3D
			if sm != null and sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				issues.append(m + " is not transparent after import")
	if absf(aabb.position.y) > 0.02:
		issues.append("lowest point is at y=%.3f (expected 0)" % aabb.position.y)
	if spec.has("length") and absf(aabb.size.z - float(spec["length"])) > 1.2:
		issues.append("length %.2f differs from target %.2f" % [aabb.size.z, spec["length"]])
	if spec.has("span") and absf(aabb.size.x - float(spec["span"])) > 0.8:
		issues.append("width %.2f differs from target %.2f" % [aabb.size.x, spec["span"]])
	# helicopters: the rotor may be parked fore-aft, so measure the rotor and the fuselage separately
	if spec.has("rotor_d"):
		var rm := file_root.find_child("Rotor_Main", true, false) as MeshInstance3D
		var rd := 0.0
		if rm != null and rm.mesh != null:
			# radial extent about the mast (the AABB is useless: blades may be parked diagonally)
			rd = _radial_extent(rm.mesh) * 2.0
			var blur := file_root.find_child("RotorBlur_Main", true, false) as MeshInstance3D
			if blur != null and blur.mesh != null and absf(_radial_extent(blur.mesh) * 2.0 - rd) > 0.05:
				issues.append("RotorBlur_Main diameter %.2f does not match the blades %.2f" % [_radial_extent(blur.mesh) * 2.0, rd])
		if absf(rd - float(spec["rotor_d"])) > 0.3:
			issues.append("main rotor diameter %.2f differs from target %.2f" % [rd, spec["rotor_d"]])
		var bd := file_root.find_child("Body", true, false) as MeshInstance3D
		var bl := 0.0
		var bw := 0.0
		if bd != null and bd.mesh != null:
			var ba := _xf(bd) * bd.mesh.get_aabb()
			bl = ba.size.z
			bw = ba.size.x
		if absf(bl - float(spec["body_len"])) > 0.6:
			issues.append("fuselage length %.2f differs from target %.2f" % [bl, spec["body_len"]])
		if rd <= bw * 2.0:
			issues.append("main rotor (%.2f m) is not clearly larger than the cabin / skid width (%.2f m)" % [rd, bw])
		print("AIRCRAFT ", id, ": rotor diameter=%.2f fuselage length=%.2f width=%.2f" % [rd, bl, bw])
	# nose toward -Z: the front extent must be on the -Z side of the tail for planes / helis
	var lh := file_root.find_child("Light_Head", true, false) as Node3D
	var lt := file_root.find_child("Light_Tail", true, false) as Node3D
	if lh != null and lt != null and not (_xf(lh).origin.z < -1.0 and _xf(lt).origin.z > 1.0):
		issues.append("nose does not point to -Z (Light_Head z=%.2f, Light_Tail z=%.2f)" % [_xf(lh).origin.z, _xf(lt).origin.z])

	# rotating parts: origin on the spin axis
	_axis_check(file_root, "Rotor_Main", Vector3(1, 0, 1), issues)
	_axis_check(file_root, "RotorBlur_Main", Vector3(1, 0, 1), issues)
	_axis_check(file_root, "Rotor_Tail", Vector3(0, 1, 1), issues)
	_axis_check(file_root, "Propeller", Vector3(1, 1, 0), issues)
	_axis_check(file_root, "PropBlur", Vector3(1, 1, 0), issues)
	for w: String in ["Wheel_Nose", "Wheel_L", "Wheel_R"]:
		var wn := file_root.find_child(w, true, false) as MeshInstance3D
		if wn != null:
			var a := wn.mesh.get_aabb()
			if a.get_center().length() > 0.01:
				issues.append("%s origin is not at the wheel centre (%s)" % [w, str(a.get_center())])
			if not (a.size.x < a.size.y * 0.9 and absf(a.size.y - a.size.z) < 0.02):
				issues.append("%s axle is not along X (aabb %s)" % [w, str(a.size)])
			if absf(_xf(wn).origin.y - a.size.y * 0.5) > 0.02:
				issues.append("%s does not touch the ground (centre y %.3f, radius %.3f)" % [w, _xf(wn).origin.y, a.size.y * 0.5])
	# seats inside the bounds, exits on the ground
	for n: Node in _all(file_root):
		var nm := String(n.name)
		var n3 := n as Node3D
		if n3 == null:
			continue
		if nm.begins_with("Seat_") and not aabb.has_point(_xf(n3).origin):
			issues.append(nm + " lies outside the model bounds")
		if nm.begins_with("Exit_") and absf(_xf(n3).origin.y) > 0.01:
			issues.append(nm + " is not on the ground")
	# left / right naming (_L = -X)
	for pair: Array in [["Aileron_L", "Aileron_R"], ["Flap_L", "Flap_R"], ["Wheel_L", "Wheel_R"], ["Door_FL", "Door_FR"],
			["Seat_Gunner_L", "Seat_Gunner_R"], ["Exhaust_L", "Exhaust_R"], ["Light_Head_L", "Light_Head_R"],
			["Light_Tail_L", "Light_Tail_R"], ["Glass_L", "Glass_R"]]:
		var l := file_root.find_child(pair[0], true, false) as Node3D
		var r := file_root.find_child(pair[1], true, false) as Node3D
		if l != null and r != null and not (_xf(l).origin.x < 0.0 and _xf(r).origin.x > 0.0):
			issues.append("%s / %s are on the wrong sides" % pair)

	# ---- critic pass: budgets, hinge lines, hierarchy, marker types, placeholder names ----------
	if tris < 2000 or tris > 7000:
		issues.append("triangle count %d outside the 2-7 k aircraft budget" % tris)
	# control surfaces / doors hang BEHIND their hinge: local AABB starts at z = 0 (Godot +Z = aft)
	for hn: String in ["Aileron_L", "Aileron_R", "Flap_L", "Flap_R", "Elevator", "Rudder", "Door_FL", "Door_FR", "Door_RL", "Door_RR"]:
		var hm := file_root.find_child(hn, true, false) as MeshInstance3D
		if hm == null or hm.mesh == null:
			continue
		var ha := hm.mesh.get_aabb()
		if absf(ha.position.z) > 0.02 or ha.size.z < 0.2:
			issues.append("%s hinge line is not at its origin (local z %.3f .. %.3f)" % [hn, ha.position.z, ha.end.z])
		if hn == "Rudder" and absf(ha.position.y) > 0.02:
			issues.append("Rudder origin is not at the bottom of its hinge (local y starts at %.3f)" % ha.position.y)
		if hn.begins_with("Aileron") or hn.begins_with("Flap") or hn == "Elevator":
			if ha.size.x < ha.size.z * 2.0:
				issues.append("%s hinge is not along local X (aabb %s)" % [hn, str(ha.size)])
	var can := file_root.find_child("Canopy", true, false) as MeshInstance3D
	if can != null and can.mesh != null:
		var ca := can.mesh.get_aabb()
		if absf(ca.end.z) > 0.08 or ca.size.z < 1.0:
			issues.append("Canopy hinge is not at its rear edge (local z %.3f .. %.3f)" % [ca.position.z, ca.end.z])
	for gp: Array in [["Glass_L", "Door_FL"], ["Glass_R", "Door_FR"], ["Glass_RL", "Door_RL"], ["Glass_RR", "Door_RR"], ["Glass_Canopy", "Canopy"]]:
		var gn := file_root.find_child(gp[0], true, false)
		var dn := file_root.find_child(gp[1], true, false)
		if gn != null and dn != null and gn.get_parent() != dn:
			issues.append("%s is not a child of %s" % gp)
	var bad := RegEx.create_from_string("^(Cube|Sphere|Cylinder|Plane|Cone|Torus|Empty|Icosphere|Mesh|Object)(_?\\d+)?$")
	for n: Node in _all(file_root):
		var nm := String(n.name)
		if n != file_root and bad.search(nm) != null:
			issues.append("placeholder node name " + nm)
		if (nm.begins_with("Seat_") or nm.begins_with("Exit_") or nm.begins_with("Light_") or nm.begins_with("Exhaust")
				or nm == "Engine" or nm == "Siren") and n is MeshInstance3D:
			issues.append("marker %s is a mesh, expected a plain Node3D" % nm)
	# every seat has its exit, on the same side and outside the fuselage
	for n: Node in _all(file_root):
		var nm := String(n.name)
		if not nm.begins_with("Seat_"):
			continue
		var ex := file_root.find_child("Exit_" + nm.substr(5), true, false) as Node3D
		if ex == null:
			issues.append("no Exit_ marker for " + nm)
			continue
		var sp := _xf(n as Node3D).origin
		var ep := _xf(ex).origin
		if absf(ep.x) < 1.2 or (absf(sp.x) > 0.05 and signf(sp.x) != signf(ep.x)) or absf(ep.z - sp.z) > 1.5:
			issues.append("%s is badly placed for %s (seat %s, exit %s)" % [ex.name, nm, str(sp), str(ep)])
	# landing gear: tricycle that carries the origin (CG) between nose and main wheels, mains level
	var wn0 := file_root.find_child("Wheel_Nose", true, false) as Node3D
	var wl0 := file_root.find_child("Wheel_L", true, false) as Node3D
	var wr0 := file_root.find_child("Wheel_R", true, false) as Node3D
	if wn0 != null and wl0 != null and wr0 != null:
		var pn := _xf(wn0).origin
		var pl := _xf(wl0).origin
		var pr := _xf(wr0).origin
		if not (pn.z < -1.0 and pl.z > 0.1 and absf(pl.z - pr.z) < 0.01 and absf(pl.x + pr.x) < 0.01 and absf(pn.x) < 0.01):
			issues.append("gear layout is not a symmetric tricycle around the origin (nose %s, L %s, R %s)" % [str(pn), str(pl), str(pr)])
		var main_share := -pn.z / (pl.z - pn.z)      # share of the weight on the mains for a CG at the origin
		print("AIRCRAFT ", id, ": gear wheelbase=%.2f track=%.2f main-gear load share=%.0f %%" % [pl.z - pn.z, pr.x - pl.x, main_share * 100.0])
		if main_share < 0.7 or main_share > 0.95:
			issues.append("origin is not sensibly placed over the gear (main share %.2f)" % main_share)

	var mat_names := mats.keys()
	mat_names.sort()
	print("AIRCRAFT ", id, ": tris=", tris, " size(x,y,z)=(%.2f, %.2f, %.2f)" % [aabb.size.x, aabb.size.y, aabb.size.z],
			" min=(%.2f, %.2f, %.2f)" % [aabb.position.x, aabb.position.y, aabb.position.z], " nodes=", _all(file_root).size())
	print("AIRCRAFT ", id, ": materials=", mat_names)
	for m: String in ["M_Paint_Primary", "M_Paint_Secondary", "M_Glass", "M_RotorBlur"]:
		if mats.has(m):
			var bm := mats[m] as BaseMaterial3D
			if bm != null:
				print("AIRCRAFT ", id, ": ", m, " albedo=", bm.albedo_color, " transparency=", bm.transparency, " cull=", bm.cull_mode)
	for n: String in ["Rotor_Main", "Rotor_Tail", "Propeller", "Wheel_Nose", "Wheel_L", "Aileron_L", "Flap_R", "Elevator", "Rudder",
			"Seat_Driver", "Seat_Gunner_L", "Exit_Driver", "Searchlight", "Canopy", "Door_FL", "Glass_L", "Light_Head",
			"Light_Head_L", "Light_Head_R", "Light_Tail_L", "Engine"]:
		var node := file_root.find_child(n, true, false) as Node3D
		if node != null:
			var gp := _xf(node).origin
			var rd := node.rotation_degrees
			print("AIRCRAFT ", id, ":   ", n, " [", node.get_class(), "] parent=", node.get_parent().name,
					" global=(%.3f, %.3f, %.3f) rot=(%.1f, %.1f, %.1f)" % [gp.x, gp.y, gp.z, rd.x, rd.y, rd.z])
	if _dump_tree:
		_dump(file_root, 0)
	if issues.is_empty():
		print("CHECK_OK ", id, " (", spec["nodes"].size(), " contract nodes, ", spec["mats"].size(), " contract materials)")
	else:
		for i: String in issues:
			print("CHECK_FAIL ", id, ": ", i)
	_root = null
	file_root.free()
	return issues.size()


func _xf(n: Node3D) -> Transform3D:
	## Transform relative to the instantiated file root (the scene is not inside the tree).
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != _root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _axis_check(root: Node, node_name: String, mask: Vector3, issues: PackedStringArray) -> void:
	var n := root.find_child(node_name, true, false) as MeshInstance3D
	if n == null or n.mesh == null:
		return
	var c := n.mesh.get_aabb().get_center() * mask
	if c.length() > 0.06:
		issues.append("%s origin is off its spin axis by %.3f m" % [node_name, c.length()])


func _radial_extent(mesh: Mesh) -> float:
	## Largest horizontal distance of any vertex from the mesh origin (= rotor radius).
	var r := 0.0
	for s in mesh.get_surface_count():
		var v: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for p in v:
			r = maxf(r, Vector2(p.x, p.z).length())
	return r


func _unique_verts(mesh: Mesh) -> int:
	var d := {}
	for s in mesh.get_surface_count():
		var v: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for p in v:
			d[p.snapped(Vector3(0.001, 0.001, 0.001))] = true
	return d.size()


func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _dump(n: Node, depth: int) -> void:
	var line := "TREE " + "  ".repeat(depth) + String(n.name) + " [" + n.get_class() + "]"
	if n is Node3D:
		var p := (n as Node3D).position
		line += " pos=(%.3f, %.3f, %.3f)" % [p.x, p.y, p.z]
		var r := (n as Node3D).rotation_degrees
		if r.length() > 0.01:
			line += " rot=(%.1f, %.1f, %.1f)" % [r.x, r.y, r.z]
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
