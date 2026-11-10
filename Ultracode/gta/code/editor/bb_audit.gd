extends SceneTree
## Contract audit for the two-wheel + boat GLBs (art critic pass).  Headless, no autoloads:
##   tools\godot.ps1 -Mode script -Script res://gta/code/editor/bb_audit.gd
## For every model it prints the node tree (class, position, tris, materials) and checks the
## ARCHITECTURE 8.2 contract: structure FileRoot -> <id> -> parts, required nodes and their kind,
## facing (-Z forward), wheel pivots (origin at the centre, axle along X, tyre on the ground),
## steering / crank / motor pivots, waterline origin of the boats, collision hull size, tri budget,
## material names, no suffixed or placeholder names.  Ends with "BB_AUDIT: PASS|FAIL failures=N".

const DIR := "res://gta/generated/models/vehicles/"
const MESH := ["Body", "Body_LOD1", "Col_Body"]
const SPEC := {
	"motorcycle": {
		"mesh": ["Handlebar", "Wheel_F", "Wheel_R"],
		"marker": ["Seat_Driver", "Seat_Passenger_1", "Exit_Driver", "Exit_Passenger_1", "Light_Head", "Light_Head_L",
			"Light_Head_R", "Light_Tail", "Light_Tail_L", "Light_Tail_R", "Exhaust", "Engine", "Steer_Axis", "Grip_L",
			"Grip_R", "Footrest_L", "Footrest_R"],
		"wheels": {"Wheel_F": 0.31, "Wheel_R": 0.32}, "rake": 25.0, "ground": true, "tris": [2000, 7000],
		"mats": ["M_Paint_Primary", "M_Tire", "M_Rim", "M_Headlight", "M_Taillight"],
	},
	"bicycle": {
		"mesh": ["Handlebar", "Crank", "Wheel_F", "Wheel_R"],
		"marker": ["Seat_Driver", "Exit_Driver", "Light_Head", "Light_Head_L", "Light_Head_R", "Light_Tail",
			"Light_Tail_L", "Light_Tail_R", "Steer_Axis", "Grip_L", "Grip_R", "Pedal_L", "Pedal_R"],
		"wheels": {"Wheel_F": 0.34, "Wheel_R": 0.34}, "rake": 19.3, "ground": true, "tris": [2000, 7000],
		"mats": ["M_Paint_Primary", "M_Tire", "M_Rim", "M_Headlight", "M_Taillight"],
	},
	"speedboat": {
		"mesh": ["Glass_Windshield", "SteeringWheel", "Motor"],
		"marker": ["Seat_Driver", "Seat_Passenger_1", "Seat_Passenger_2", "Seat_Passenger_3", "Exit_Driver",
			"Exit_Passenger_1", "Exit_Passenger_2", "Exit_Passenger_3", "Prop", "Wake_L", "Wake_R", "Engine",
			"Light_Head", "Light_Head_L", "Light_Head_R", "Light_Tail", "Light_Tail_L", "Light_Tail_R"],
		"keel": -0.35, "tris": [2000, 7000], "mats": ["M_Paint_Primary", "M_Paint_Secondary", "M_Glass"],
	},
	"jetski": {
		"mesh": ["Handlebar", "Motor"],
		"marker": ["Seat_Driver", "Seat_Passenger_1", "Exit_Driver", "Exit_Passenger_1", "Prop", "Wake_L", "Wake_R",
			"Engine", "Light_Head", "Light_Head_L", "Light_Head_R", "Steer_Axis", "Grip_L", "Grip_R", "Footrest_L",
			"Footrest_R"],
		"keel": -0.22, "rake": 24.0, "tris": [2000, 7000], "mats": ["M_Paint_Primary", "M_Paint_Secondary"],
	},
	"dinghy": {
		"mesh": ["Motor"],
		"marker": ["Seat_Driver", "Seat_Passenger_1", "Exit_Driver", "Exit_Passenger_1", "Prop", "Wake_L", "Wake_R",
			"Engine", "Light_Head", "Light_Head_L", "Light_Head_R"],
		"keel": -0.14, "tris": [2000, 7000], "mats": ["M_Paint_Primary", "M_Paint_Secondary"],
	},
}

var _fails := 0
var _id := ""


func _initialize() -> void:
	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--id="):
			only = a.substr(5)
	for id: String in SPEC:
		if only != "" and only != id:
			continue
		_id = id
		_audit(id)
	print("BB_AUDIT: %s failures=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)


func _bad(msg: String) -> void:
	_fails += 1
	print("CHECK_FAIL: bb_audit %s: %s" % [_id, msg])


func _tris(mi: MeshInstance3D) -> int:
	return mi.mesh.get_faces().size() / 3


func _unique_verts(mi: MeshInstance3D) -> int:
	var seen := {}
	for v: Vector3 in mi.mesh.get_faces():
		seen[Vector3i(roundi(v.x * 2000.0), roundi(v.y * 2000.0), roundi(v.z * 2000.0))] = true
	return seen.size()


func _mats(mi: MeshInstance3D) -> PackedStringArray:
	var out: PackedStringArray = []
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		out.append(m.resource_name if m != null else "<none>")
	return out


## Transform of `n` relative to the asset root (parents are unrotated except the marker itself).
func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _audit(id: String) -> void:
	var path := DIR + id + ".glb"
	if not ResourceLoader.exists(path):
		_bad("file missing " + path)
		return
	var ps := load(path) as PackedScene
	if ps == null:
		_bad("not a PackedScene")
		return
	var file_root := ps.instantiate() as Node3D
	var spec: Dictionary = SPEC[id]
	print("---- ", id, "  file root '", file_root.name, "' children=", file_root.get_child_count())
	var root := file_root.get_node_or_null(id) as Node3D
	if root == null or file_root.get_child_count() != 1:
		_bad("expected FileRoot -> '%s' as the only child" % id)
		root = file_root
	if root.transform.origin.length() > 0.0005 or not root.transform.basis.is_equal_approx(Basis.IDENTITY):
		_bad("asset root is not at identity: %s" % root.transform)
	var total := 0
	var all_mats := {}
	var vis := AABB()
	var first := true
	for n: Node in root.find_children("*", "", true, false):
		var s := String(n.name)
		var line := "  %-18s %-15s" % [s, n.get_class()]
		var n3 := n as Node3D
		if n3 == null:
			_bad("unexpected non-3D node '%s' (%s)" % [s, n.get_class()])
			continue
		var t := _rel(n3, root)
		line += " pos=(%.3f, %.3f, %.3f)" % [t.origin.x, t.origin.y, t.origin.z]
		if n.get_parent() != root:
			line += " parent=" + String(n.get_parent().name)
		if s.contains(":") or s.contains(".") or (s.length() > 4 and s.substr(s.length() - 3).is_valid_int()):
			_bad("suspicious node name '%s'" % s)
		if s.begins_with("Cube") or s.begins_with("Cylinder") or s.begins_with("Sphere") or s.begins_with("Empty") or s.begins_with("Plane"):
			_bad("placeholder node name '%s'" % s)
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			var tr := _tris(mi)
			total += tr
			var mats := _mats(mi)
			for m: String in mats:
				all_mats[m] = true
				if m == "<none>" or m.contains("."):
					_bad("%s has material '%s'" % [s, m])
			var a := mi.mesh.get_aabb()
			line += " tris=%d aabb=(%.2f, %.2f, %.2f) mats=%s" % [tr, a.size.x, a.size.y, a.size.z, str(mats)]
			if not s.begins_with("Col_") and s != "Body_LOD1":
				var wa := t * a
				vis = wa if first else vis.merge(wa)
				first = false
			if not t.basis.get_scale().is_equal_approx(Vector3.ONE):
				_bad("%s has a non-unit scale %s" % [s, t.basis.get_scale()])
		print(line)

	# ---- required nodes
	for nm: String in MESH + spec["mesh"]:
		var n := root.find_child(nm, true, false)
		if n == null:
			_bad("missing mesh node " + nm)
		elif not (n is MeshInstance3D):
			_bad("%s is %s, expected MeshInstance3D" % [nm, n.get_class()])
	for nm: String in spec["marker"]:
		var n := root.find_child(nm, true, false)
		if n == null:
			_bad("missing marker " + nm)
		elif n is MeshInstance3D:
			_bad("marker %s is a mesh" % nm)
	for m: String in spec["mats"] + ["P_Collision"]:
		if not all_mats.has(m):
			_bad("material %s not found" % m)
	var lo: int = spec["tris"][0]
	var hi: int = spec["tris"][1]
	if total < lo or total > hi:
		_bad("tri count %d outside the %d..%d budget" % [total, lo, hi])

	# ---- collision hull, LOD
	var col := root.find_child("Col_Body", true, false) as MeshInstance3D
	var colv := _unique_verts(col) if col != null else -1
	if colv > 32:
		_bad("Col_Body has %d verts (> 32)" % colv)
	if col != null and _mats(col) != PackedStringArray(["P_Collision"]):
		_bad("Col_Body material is %s" % str(_mats(col)))
	var lod := root.find_child("Body_LOD1", true, false) as MeshInstance3D
	var lod_tris := _tris(lod) if lod != null else 0
	var full := total - lod_tris - (_tris(col) if col != null else 0)
	if lod != null and float(lod_tris) > 0.25 * float(full):
		_bad("Body_LOD1 has %d tris (> 25 %% of %d)" % [lod_tris, full])

	# ---- facing: head light / bow at -Z, seats behind it
	var head := root.find_child("Light_Head", true, false) as Node3D
	var seat := root.find_child("Seat_Driver", true, false) as Node3D
	if head != null and seat != null:
		if not (head.position.z < seat.position.z and head.position.z < -0.3):
			_bad("model does not face -Z (Light_Head z=%.2f, Seat_Driver z=%.2f)" % [head.position.z, seat.position.z])
		if not vis.grow(0.05).has_point(seat.position):
			_bad("Seat_Driver %s is outside the visible bounds" % seat.position)
	var tail := root.find_child("Light_Tail", true, false) as Node3D
	if tail != null and tail.position.z < 0.3:
		_bad("Light_Tail is not at the rear (z=%.2f)" % tail.position.z)
	for pair: Array in [["Light_Head_L", "Light_Head_R"], ["Light_Tail_L", "Light_Tail_R"], ["Wake_L", "Wake_R"],
			["Grip_L", "Grip_R"], ["Footrest_L", "Footrest_R"], ["Pedal_L", "Pedal_R"]]:
		var l := root.find_child(pair[0], true, false) as Node3D
		var r := root.find_child(pair[1], true, false) as Node3D
		if l != null and r != null and not (_rel(l, root).origin.x < 0.0 and _rel(r, root).origin.x > 0.0):
			_bad("%s / %s are not on the left (-X) / right (+X)" % pair)

	# ---- wheels
	var wheels: Dictionary = spec.get("wheels", {})
	for wn: String in wheels:
		var w := root.find_child(wn, true, false) as MeshInstance3D
		if w == null:
			continue
		var a := w.mesh.get_aabb()
		var c := a.get_center()
		var radius := a.size.y * 0.5
		print("  WHEEL %s centre_offset=(%.4f, %.4f, %.4f) radius=%.3f width=%.3f bottom_y=%.4f" % [
			wn, c.x, c.y, c.z, radius, a.size.x, w.position.y - radius])
		if c.length() > 0.004:
			_bad("%s origin is not at the wheel centre (offset %s)" % [wn, c])
		if absf(a.size.y - a.size.z) > 0.006 or a.size.x > a.size.y * 0.7:
			_bad("%s axle is not along X (aabb %s)" % [wn, a.size])
		if absf(radius - float(wheels[wn])) > 0.006:
			_bad("%s radius %.3f, documented %.3f" % [wn, radius, float(wheels[wn])])
		if absf(w.position.y - radius) > 0.004 or absf(w.position.x) > 0.001:
			_bad("%s does not stand on the ground / centre line (pos %s)" % [wn, w.position])
	if wheels.size() == 2:
		var wf := root.find_child("Wheel_F", true, false) as Node3D
		var wr := root.find_child("Wheel_R", true, false) as Node3D
		if wf != null and wr != null:
			print("  wheelbase=%.3f" % (wr.position.z - wf.position.z))
			if wf.position.z >= wr.position.z:
				_bad("Wheel_F is not in front of Wheel_R")
	if spec.get("ground", false):
		print("  lowest visible y=%.4f  size=(%.2f, %.2f, %.2f)" % [vis.position.y, vis.size.x, vis.size.y, vis.size.z])
		if absf(vis.position.y) > 0.004:
			_bad("lowest point is y=%.4f, expected 0 (stands on its wheels)" % vis.position.y)

	# ---- steering axis
	var bar := root.find_child("Handlebar", true, false) as Node3D
	var ax := root.find_child("Steer_Axis", true, false) as Node3D
	if spec.has("rake"):
		if bar == null or ax == null:
			_bad("Handlebar / Steer_Axis missing")
		else:
			var up := ax.transform.basis.y.normalized()
			var rake := rad_to_deg(acos(clampf(up.y, -1.0, 1.0)))
			print("  Handlebar origin=%s  Steer_Axis +Y=(%.3f, %.3f, %.3f) rake=%.1f deg" % [bar.position, up.x, up.y, up.z, rake])
			if bar.position.distance_to(ax.position) > 0.002:
				_bad("Handlebar origin is not on the Steer_Axis marker")
			if absf(rake - float(spec["rake"])) > 0.6 or up.z <= 0.0 or absf(up.x) > 0.001:
				_bad("steering axis rake is %.1f deg (documented %.1f), must lean back (+Z)" % [rake, float(spec["rake"])])
			if not bar.transform.basis.is_equal_approx(Basis.IDENTITY):
				_bad("Handlebar node is rotated")
			var wf2 := root.find_child("Wheel_F", true, false) as Node3D
			if wf2 != null:
				# the front axle should lie (almost) on the steering axis line when seen from the side, minus fork offset
				var d := wf2.position - ax.position
				var off := (d - up * d.dot(up)).length()
				print("  fork offset (axle to steering axis)=%.3f m" % off)
				if off > 0.09:
					_bad("front axle is %.3f m off the steering axis" % off)
	var crank := root.find_child("Crank", true, false) as MeshInstance3D
	if crank != null:
		var ca := crank.mesh.get_aabb()
		print("  Crank origin=%s aabb centre=(%.3f, %.3f, %.3f)" % [crank.position, ca.get_center().x, ca.get_center().y, ca.get_center().z])
		if absf(ca.get_center().y) > 0.01 or absf(ca.get_center().z) > 0.01:
			_bad("Crank origin is not on the bottom-bracket axle")
		if absf(crank.position.x) > 0.001:
			_bad("Crank is off the centre line")

	# ---- boats
	if spec.has("keel"):
		var body := root.find_child("Body", true, false) as MeshInstance3D
		var keel := body.mesh.get_aabb().position.y if body != null else 0.0
		var ba := body.mesh.get_aabb() if body != null else AABB()
		print("  hull keel y=%.3f (documented %.2f)  body size=(%.2f, %.2f, %.2f)  bow z=%.2f stern z=%.2f" % [
			keel, float(spec["keel"]), ba.size.x, ba.size.y, ba.size.z, ba.position.z, ba.end.z])
		if absf(keel - float(spec["keel"])) > 0.03:
			_bad("keel depth %.3f differs from the documented %.2f (waterline origin)" % [keel, float(spec["keel"])])
		var motor := root.find_child("Motor", true, false) as Node3D
		var prop := root.find_child("Prop", true, false) as Node3D
		if motor != null and prop != null:
			print("  Motor origin=%s  Prop=%s" % [motor.position, prop.position])
			if motor.position.z < 0.5 or absf(motor.position.x) > 0.001 or prop.position.y > 0.0 or prop.position.z < motor.position.z:
				_bad("Motor / Prop are not at the stern below the waterline")
		for wn: String in ["Wake_L", "Wake_R"]:
			var wk := root.find_child(wn, true, false) as Node3D
			if wk != null and (absf(wk.position.y) > 0.01 or wk.position.z < 0.5):
				_bad("%s is not at the waterline at the stern (%s)" % [wn, wk.position])
		var sw := root.find_child("SteeringWheel", true, false) as MeshInstance3D
		if sw != null:
			var sc := sw.mesh.get_aabb().get_center()
			print("  SteeringWheel pos=%s rot=%s hub offset=(%.3f, %.3f, %.3f)" % [sw.position, sw.rotation_degrees, sc.x, sc.y, sc.z])
			if Vector2(sc.x, sc.y).length() > 0.01:
				_bad("SteeringWheel origin is not at the hub")
	var names := {}
	for n: Node in root.find_children("*", "", true, false):
		if names.has(String(n.name)):
			_bad("duplicate node name " + String(n.name))
		names[String(n.name)] = true
	var keys := all_mats.keys()
	keys.sort()
	print("  TOTAL tris=%d (full detail %d, LOD1 %d, Col_Body %d verts)  materials=%s" % [total, full, lod_tris, colv, str(keys)])
	file_root.free()
