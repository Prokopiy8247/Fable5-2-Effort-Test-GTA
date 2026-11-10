extends SceneTree
## Headless verification of the service-vehicle GLBs (ambulance, firetruck, swat_van, box_truck)
## against the vehicle node contract of docs/ARCHITECTURE.md 8.2 (VEHICLE ARTIST cars_service tool).
##
## For every vehicle: import structure FileRoot -> <id> -> parts, clean node names, required nodes,
## wheel pivots (origin at the wheel centre, axle along X, resting on the ground), door hinge
## origins, nested door panes, marker positions, material names, collision helper vertex counts,
## LOD and visible triangle counts.
##
## Run:  tools\godot.ps1 -Mode script -Script res://gta/code/editor/cars_service_verify.gd
## Optional user args: --only=ambulance,firetruck   --tree (also dump the node trees)

const DIR := "res://gta/generated/models/vehicles/"

const BASE: Array[String] = ["Body", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR", "SteeringWheel",
	"Door_FL", "Door_FR", "Glass_Windshield", "Glass_L", "Glass_R", "Seat_Driver", "Seat_Passenger_1",
	"Exit_Driver", "Exit_Passenger_1", "Light_Head_L", "Light_Head_R", "Light_Tail_L", "Light_Tail_R",
	"Exhaust", "Engine", "Col_Body", "Col_Cabin", "Body_LOD1"]

## id -> extra nodes, length range, height range, wheel radius, required Body materials,
## rear doors at the tail (barn doors), nested panes {pane: parent}
const SPECS := {
	"ambulance": {"extra": ["Siren", "Door_RL", "Door_RR", "Hood", "Col_Box", "Glass_Box_L", "Glass_Box_R"],
		"len": [5.9, 6.3], "h": [2.6, 3.0], "r": 0.42, "barn": true,
		"mats": ["P_AmbulanceWhite", "P_Teal", "M_Siren_Red", "M_Siren_Blue", "M_Trim", "M_Chrome", "M_Headlight", "M_Taillight"],
		"nested": {"Glass_Rear_L": "Door_RL", "Glass_Rear_R": "Door_RR"}},
	"firetruck": {"extra": ["Siren", "Door_RL", "Door_RR", "Wheel_ML", "Wheel_MR", "Glass_Rear", "Col_Box",
			"Seat_Passenger_2", "Seat_Passenger_3", "Exit_Passenger_2", "Exit_Passenger_3"],
		"len": [7.8, 8.4], "h": [2.8, 3.3], "r": 0.50, "barn": false,
		"mats": ["P_FireRed", "P_White", "M_Siren_Red", "M_Siren_Blue", "M_Chrome", "P_Steel", "M_Headlight", "M_Taillight"],
		"nested": {}},
	"swat_van": {"extra": ["Siren", "Door_RL", "Door_RR", "Hood", "Seat_Passenger_2", "Seat_Passenger_3",
			"Exit_Passenger_2", "Exit_Passenger_3"],
		"len": [6.0, 6.5], "h": [2.5, 2.9], "r": 0.48, "barn": true,
		"mats": ["P_UniformNavy", "M_Siren_Red", "M_Siren_Blue", "M_Trim", "P_Steel", "M_Headlight", "M_Taillight"],
		"nested": {"Glass_Rear_L": "Door_RL", "Glass_Rear_R": "Door_RR"}},
	"box_truck": {"extra": ["Glass_Rear", "Trunk", "Col_Box"],
		"len": [6.8, 7.3], "h": [3.0, 3.4], "r": 0.44, "barn": false,
		"mats": ["M_Paint_Primary", "M_Paint_Secondary", "M_Trim", "P_Steel", "M_Headlight", "M_Taillight"],
		"nested": {}},
}

var _dump_tree := false


func _initialize() -> void:
	var only: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a == "--tree":
			_dump_tree = true
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
				print("CHECK_FAIL cars_service ", id, ": ", p)
	print("CHECK_SUMMARY cars_service: ok=", ok, " failed=", bad)
	quit(0 if bad == 0 else 1)


func _xf(n: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _tris(mi: MeshInstance3D) -> int:
	if mi.mesh == null:
		return 0
	return int(mi.mesh.get_faces().size() / 3.0)


func _mats(mi: MeshInstance3D) -> PackedStringArray:
	var out: PackedStringArray = []
	if mi.mesh == null:
		return out
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		out.append(m.resource_name if m != null else "<none>")
	return out


func _print_tree(n: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + String(n.name) + " [" + n.get_class() + "]"
	if n is Node3D:
		var p := (n as Node3D).position
		line += " pos=(%.3f, %.3f, %.3f)" % [p.x, p.y, p.z]
	if n is MeshInstance3D:
		line += " mats=" + str(_mats(n as MeshInstance3D))
	print(line)
	for c in n.get_children():
		_print_tree(c, depth + 1)


func _check(id: String, spec: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var path := DIR + id + ".glb"
	if not ResourceLoader.exists(path):
		out.append("file missing: " + path)
		return out
	var ps := load(path) as PackedScene
	if ps == null:
		out.append("not a PackedScene")
		return out
	var file_root := ps.instantiate() as Node3D
	if _dump_tree:
		print("TREE_OF ", path)
		_print_tree(file_root, 0)
	var root := file_root.get_node_or_null(id) as Node3D
	if root == null:
		out.append("asset root '%s' missing under the file root" % id)
		file_root.free()
		return out
	# ---- names
	var names := {}
	for n: Node in root.find_children("*", "", true, false):
		var nm := String(n.name)
		if nm.contains(":") or nm.contains(".") or nm.contains("@"):
			out.append("unclean node name: " + nm)
		if names.has(nm):
			out.append("duplicate node name: " + nm)
		names[nm] = n
	var need: Array[String] = []
	need.append_array(BASE)
	for e: String in spec["extra"]:
		need.append(e)
	for k: String in spec["nested"]:
		need.append(k)
	for nm: String in need:
		if not names.has(nm):
			out.append("missing node: " + nm)
	# ---- body bounds + materials
	var body := names.get("Body") as MeshInstance3D
	var visible_tris := 0
	if body != null:
		var a := _xf(body, file_root) * body.get_aabb()
		var ln: float = a.size.z
		var top: float = a.position.y + a.size.y
		if ln < float(spec["len"][0]) or ln > float(spec["len"][1]):
			out.append("Body length %.2f outside %s" % [ln, str(spec["len"])])
		if top < float(spec["h"][0]) or top > float(spec["h"][1]):
			out.append("Body top %.2f outside %s" % [top, str(spec["h"])])
		if absf(a.get_center().x) > 0.15:
			out.append("Body not centred in x: %.2f" % a.get_center().x)
		var bm := _mats(body)
		for m: String in spec["mats"]:
			if not bm.has(m):
				out.append("Body lacks material " + m)
		print("INFO ", id, ": Body aabb pos=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f) surfaces=%d" % [a.position.x, a.position.y,
				a.position.z, a.size.x, a.size.y, a.size.z, bm.size()])
		print("INFO ", id, ": Body materials ", bm)
	# ---- wheels
	var r_exp: float = spec["r"]
	for nm: String in ["Wheel_FL", "Wheel_FR", "Wheel_ML", "Wheel_MR", "Wheel_RL", "Wheel_RR"]:
		var w := names.get(nm) as MeshInstance3D
		if w == null:
			continue
		var wa := w.get_aabb()
		var wp := _xf(w, file_root).origin
		if wa.get_center().length() > 0.012:
			out.append("%s origin not at the wheel centre (aabb centre %s)" % [nm, str(wa.get_center())])
		if wa.size.x > wa.size.y * 0.75 or absf(wa.size.y - wa.size.z) > 0.03:
			out.append("%s axle is not local X (aabb %s)" % [nm, str(wa.size)])
		var rad := maxf(wa.size.y, wa.size.z) * 0.5
		if absf(rad - r_exp) > 0.02:
			out.append("%s radius %.3f != %.2f" % [nm, rad, r_exp])
		if absf(wp.y - rad) > 0.02:
			out.append("%s does not rest on the ground: y=%.3f r=%.3f" % [nm, wp.y, rad])
		if (nm.ends_with("L") and wp.x > -0.5) or (nm.ends_with("R") and wp.x < 0.5):
			out.append("%s on the wrong side: x=%.2f" % [nm, wp.x])
		for m: String in _mats(w):
			if m != "M_Tire" and m != "M_Rim":
				out.append("%s has foreign material %s" % [nm, m])
		print("INFO ", id, ": ", nm, " pos=(%.3f, %.3f, %.3f) radius=%.3f width=%.3f tris=%d" % [wp.x, wp.y, wp.z, rad, wa.size.x, _tris(w)])
	# ---- doors
	for nm: String in ["Door_FL", "Door_FR", "Door_RL", "Door_RR"]:
		var d := names.get(nm) as MeshInstance3D
		if d == null:
			continue
		var dp := _xf(d, file_root).origin
		var da := d.get_aabb()
		if (nm.ends_with("L") and dp.x > -0.3) or (nm.ends_with("R") and dp.x < 0.3):
			out.append("%s hinge on the wrong side: x=%.2f" % [nm, dp.x])
		# the hinge origin must sit on an edge of the door mesh (not in its middle)
		var barn: bool = bool(spec["barn"]) and nm.begins_with("Door_R")
		if barn:
			var edge := minf(absf(da.position.x), absf(da.position.x + da.size.x))
			if edge > 0.08:
				out.append("%s (barn door) origin is %.2f m off its side edge" % [nm, edge])
		else:
			if absf(da.position.z) > 0.2 and absf(da.position.z + da.size.z) > 0.2:
				out.append("%s origin is not on its front / rear edge (aabb z %.2f..%.2f)" % [nm, da.position.z, da.position.z + da.size.z])
		print("INFO ", id, ": ", nm, " hinge=(%.3f, %.3f, %.3f) aabb_size=(%.2f, %.2f, %.2f)" % [dp.x, dp.y, dp.z, da.size.x, da.size.y, da.size.z])
	for pane: String in spec["nested"]:
		var g := names.get(pane) as Node
		if g != null and String(g.get_parent().name) != String(spec["nested"][pane]):
			out.append("%s should be a child of %s, parent is %s" % [pane, spec["nested"][pane], g.get_parent().name])
	# ---- glass, collision, LOD, tri counts
	var lod_tris := 0
	for nm: String in names:
		var mi := names[nm] as MeshInstance3D
		if mi == null:
			continue
		var t := _tris(mi)
		if nm.begins_with("Glass_"):
			var gm := _mats(mi)
			if gm.size() != 1 or gm[0] != "M_Glass":
				out.append("%s materials %s (want M_Glass only)" % [nm, str(gm)])
		if nm.begins_with("Col_"):
			var pts := {}
			for p: Vector3 in mi.mesh.get_faces():
				pts[Vector3i(roundi(p.x * 500.0), roundi(p.y * 500.0), roundi(p.z * 500.0))] = true
			if pts.size() > 32:
				out.append("%s has %d verts (> 32)" % [nm, pts.size()])
			var cm := _mats(mi)
			if cm.size() != 1 or cm[0] != "P_Collision":
				out.append("%s materials %s (want P_Collision)" % [nm, str(cm)])
			print("INFO ", id, ": ", nm, " verts=", pts.size())
		elif nm == "Body_LOD1":
			lod_tris = t
		else:
			visible_tris += t
	if lod_tris <= 0 or lod_tris * 4 > visible_tris:
		out.append("Body_LOD1 tris %d is not <= 25%% of the visible %d" % [lod_tris, visible_tris])
	# ---- markers
	for pair: Array in [["Seat_Driver", -1.0], ["Seat_Passenger_1", 1.0], ["Exit_Driver", -1.0], ["Exit_Passenger_1", 1.0],
			["Light_Head_L", -1.0], ["Light_Head_R", 1.0], ["Light_Tail_L", -1.0], ["Light_Tail_R", 1.0]]:
		var mk := names.get(pair[0]) as Node3D
		if mk == null:
			continue
		var mp := _xf(mk, file_root).origin
		if mp.x * float(pair[1]) <= 0.05:
			out.append("%s on the wrong side: x=%.2f" % [pair[0], mp.x])
		if String(pair[0]).begins_with("Exit_") and absf(mp.y) > 0.02:
			out.append("%s is not on the ground: y=%.2f" % [pair[0], mp.y])
		if String(pair[0]).begins_with("Light_Head") and mp.z > -1.0:
			out.append("%s is not at the nose: z=%.2f" % [pair[0], mp.z])
		if String(pair[0]).begins_with("Light_Tail") and mp.z < 1.0:
			out.append("%s is not at the tail: z=%.2f" % [pair[0], mp.z])
	for nm: String in ["Seat_Driver", "Exit_Driver", "Exit_Passenger_2", "Light_Head_L", "Light_Tail_L", "Exhaust", "Engine", "Siren"]:
		var mk2 := names.get(nm) as Node3D
		if mk2 != null:
			var q := _xf(mk2, file_root).origin
			print("INFO ", id, ": ", nm, " at (%.3f, %.3f, %.3f)" % [q.x, q.y, q.z])
	print("INFO ", id, ": nodes=", names.size(), " visible_tris=", visible_tris, " lod_tris=", lod_tris, " problems=", out.size())
	file_root.free()
	return out
