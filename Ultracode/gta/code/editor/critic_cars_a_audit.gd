extends SceneTree
## Contract audit for the road vehicles of art set cars_a + the kit reference (critic tool).
## Checks every GLB against docs/ARCHITECTURE.md 8.2 and docs/VEHICLE_KIT.md 4:
## node names, marker empties, pivots (wheel centres, door / hood / trunk hinge lines), facing,
## material names, collision helper size, tri counts.
## Run:  tools\godot.ps1 -Mode script -Script res://gta/code/editor/critic_cars_a_audit.gd
## Optional: -UserArgs '--only=sports,muscle'  '--verbose'

const DIR := "res://gta/generated/models/vehicles/"
const CARS: Dictionary = {
	"sedan": {"doors": 4, "rear_seats": true, "trunk": true, "roof": false},
	"compact": {"doors": 2, "rear_seats": true, "trunk": false, "roof": false},
	"sports": {"doors": 2, "rear_seats": false, "trunk": true, "roof": true},
	"muscle": {"doors": 2, "rear_seats": true, "trunk": true, "roof": false},
}
const WHEELS: Array[String] = ["wheel_sport", "wheel_classic", "wheel_offroad", "wheel_deep"]
const MODS: Array[String] = ["Mod_Spoiler_A", "Mod_Spoiler_B", "Mod_BumperF_A", "Mod_BumperR_A", "Mod_Hood_A",
		"Mod_Skirts_A", "Mod_Roof_A", "Mod_Exhaust_A", "Mod_Grille_A"]
const OK_MATS: Array[String] = ["M_Paint_Primary", "M_Paint_Secondary", "M_Glass", "M_Trim", "M_Chrome", "M_Interior",
		"M_Underbody", "M_Plate", "M_Headlight", "M_Taillight", "M_Indicator", "M_ReverseLight", "M_Tire", "M_Rim",
		"P_Collision"]

var _fails := 0
var _verbose := false


func _initialize() -> void:
	var only: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a == "--verbose":
			_verbose = true
	for id: String in CARS:
		if only.is_empty() or only.has(id):
			_audit_car(id, CARS[id])
	for id: String in WHEELS:
		if only.is_empty() or only.has(id):
			_audit_wheel(id)
	print("CRITIC_AUDIT_DONE fails=", _fails)
	quit(0)


func _fail(id: String, msg: String) -> void:
	_fails += 1
	print("CHECK_FAIL ", id, ": ", msg)


func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			n += (idx as PackedInt32Array).size() / 3
		else:
			n += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _unique_verts(m: Mesh) -> int:
	var seen := {}
	for s in m.get_surface_count():
		for v: Vector3 in (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			seen[v.snappedf(0.0005)] = true
	return seen.size()


func _mats(id: String, mi: MeshInstance3D) -> PackedStringArray:
	var out: PackedStringArray = []
	for s in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(s)
		var nm := mat.resource_name if mat != null else "<none>"
		out.append(nm)
		if not (OK_MATS.has(nm) or nm.begins_with("P_") or nm.begins_with("M_Siren")):
			_fail(id, "%s has non-contract material '%s'" % [mi.name, nm])
	return out


func _load(id: String, path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		_fail(id, "missing file " + path)
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		_fail(id, "not a PackedScene")
		return null
	return ps.instantiate() as Node3D


func _audit_car(id: String, cfg: Dictionary) -> void:
	var root := _load(id, DIR + id + ".glb")
	if root == null:
		return
	var asset := root.get_child(0) as Node3D if root.get_child_count() == 1 else null
	if asset == null or asset.name != id:
		_fail(id, "expected FileRoot -> %s, got %s children" % [id, root.get_child_count()])
		root.free()
		return
	var parts := {}
	for c: Node in asset.get_children():
		parts[String(c.name)] = c
		if String(c.name).contains(":") or String(c.name).contains("."):
			_fail(id, "unclean node name " + c.name)
		if c.get_child_count() > 0:
			_fail(id, "%s has children (flat list expected)" % c.name)
	var need: Array[String] = ["Body", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR", "SteeringWheel", "Hood",
			"Door_FL", "Door_FR", "Glass_Windshield", "Glass_Rear", "Glass_L", "Glass_R", "Seat_Driver",
			"Seat_Passenger_1", "Exit_Driver", "Exit_Passenger_1", "Light_Head_L", "Light_Head_R", "Light_Tail_L",
			"Light_Tail_R", "Exhaust", "Engine", "Col_Body", "Col_Cabin", "Body_LOD1"]
	need.append_array(MODS)
	if cfg["doors"] == 4:
		need.append_array(["Door_RL", "Door_RR"])
	if cfg["rear_seats"]:
		need.append_array(["Seat_Passenger_2", "Seat_Passenger_3", "Exit_Passenger_2", "Exit_Passenger_3"])
	if cfg["trunk"]:
		need.append("Trunk")
	if cfg["roof"]:
		need.append("Roof_Convertible")
	for n: String in need:
		if not parts.has(n):
			_fail(id, "missing node " + n)
	var vis := 0
	var all := 0
	var lod := 0
	var mat_set := {}
	for nm: String in parts:
		var mi := parts[nm] as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var t := _tris(mi.mesh)
		all += t
		for m: String in _mats(id, mi):
			mat_set[m] = true
		if nm == "Body_LOD1":
			lod = t
		elif not (nm.begins_with("Mod_") or nm.begins_with("Col_")):
			vis += t
		if _verbose:
			var ab := mi.mesh.get_aabb()
			print("   %s pos=%s tris=%d aabb=%s..%s mats=%s" % [nm, mi.position.snappedf(0.001), t,
					ab.position.snappedf(0.001), ab.end.snappedf(0.001), _mats(id, mi)])
	# --- wheels
	var wtxt := ""
	for w: String in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var mi := parts.get(w) as MeshInstance3D
		if mi == null:
			continue
		var ab := mi.mesh.get_aabb()
		var c := ab.get_center()
		if c.length() > 0.004:
			_fail(id, "%s origin is not the wheel centre (aabb centre %s)" % [w, c])
		if not (ab.size.x < ab.size.y and absf(ab.size.y - ab.size.z) < 0.03):
			_fail(id, "%s axle is not local X (aabb %s)" % [w, ab.size])
		var r := maxf(ab.size.y, ab.size.z) * 0.5
		if absf(mi.position.y - r) > 0.012:
			_fail(id, "%s does not touch the ground: y=%.3f r=%.3f" % [w, mi.position.y, r])
		if r < 0.295 or r > 0.405:
			_fail(id, "%s radius %.3f outside 0.30-0.40" % [w, r])
		var left := w.ends_with("L")
		if (mi.position.x < 0.0) != left:
			_fail(id, "%s on the wrong side" % w)
		if (mi.position.z < 0.0) != w.begins_with("Wheel_F"):
			_fail(id, "%s on the wrong end (front must be -Z)" % w)
		if mi.rotation.length() > 0.001 or (mi.scale - Vector3.ONE).length() > 0.001:
			_fail(id, "%s has rotation / scale" % w)
		wtxt += " %s(%.3f,%.3f,%.3f r%.3f w%.2f)" % [w.substr(6), mi.position.x, mi.position.y, mi.position.z, r, ab.size.x]
	# --- body size, facing
	var body := parts.get("Body") as MeshInstance3D
	var bab := AABB()
	if body != null:
		bab = body.mesh.get_aabb()
		if body.position.length() > 0.001:
			_fail(id, "Body origin not at the car origin")
		if absf(bab.get_center().x) > 0.02:
			_fail(id, "Body not centred in X (%.3f)" % bab.get_center().x)
		if not _mats(id, body).has("M_Paint_Primary"):
			_fail(id, "Body lacks M_Paint_Primary")
	for l: String in ["Light_Head_L", "Light_Head_R"]:
		var n := parts.get(l) as Node3D
		if n != null and (n.position.z > -1.0 or (n.position.x < 0.0) != l.ends_with("L")):
			_fail(id, "%s misplaced %s (head lights must be at -Z)" % [l, n.position])
	for l: String in ["Light_Tail_L", "Light_Tail_R"]:
		var n := parts.get(l) as Node3D
		if n != null and (n.position.z < 1.0 or (n.position.x < 0.0) != l.ends_with("L")):
			_fail(id, "%s misplaced %s" % [l, n.position])
	for nm: String in parts:
		if nm.begins_with("Exhaust"):
			var n := parts[nm] as Node3D
			if n.position.z < 1.0 or n.position.y > 0.6:
				_fail(id, "%s misplaced %s" % [nm, n.position])
			# marker -Z must point backwards (+Z in car space)
			if (n.transform.basis * Vector3.FORWARD).z < 0.9:
				_fail(id, "%s does not point backwards" % nm)
	# --- seats / exits
	var stxt := ""
	for nm: String in parts:
		var n := parts[nm] as Node3D
		if nm.begins_with("Seat_"):
			if n.position.y < 0.2 or n.position.y > 0.75 or bab.size.x > 0.0 and absf(n.position.x) > bab.size.x * 0.5:
				_fail(id, "%s hip point odd %s" % [nm, n.position])
			stxt += " %s(%.2f,%.2f,%.2f)" % [nm.substr(5), n.position.x, n.position.y, n.position.z]
		elif nm.begins_with("Exit_"):
			if absf(n.position.y) > 0.001 or absf(n.position.x) < 1.2:
				_fail(id, "%s must be on the ground beside the car %s" % [nm, n.position])
	var sd := parts.get("Seat_Driver") as Node3D
	if sd != null and sd.position.x >= 0.0:
		_fail(id, "Seat_Driver must be on the left (-X)")
	# --- hinges
	for d: String in ["Door_FL", "Door_FR", "Door_RL", "Door_RR"]:
		var mi := parts.get(d) as MeshInstance3D
		if mi == null:
			continue
		var ab := mi.mesh.get_aabb()
		# front hinged: the door extends towards +Z (rear) from its origin; origin near the bottom
		if ab.position.z < -0.16 or ab.end.z < 0.6:
			_fail(id, "%s origin is not on its front edge (z %.2f..%.2f)" % [d, ab.position.z, ab.end.z])
		if ab.position.y < -0.06 or ab.position.y > 0.06:
			_fail(id, "%s origin is not at the door bottom (y min %.3f)" % [d, ab.position.y])
		if (mi.position.x < 0.0) != d.ends_with("L"):
			_fail(id, "%s on the wrong side" % d)
	var hood := parts.get("Hood") as MeshInstance3D
	if hood != null:
		var ab := hood.mesh.get_aabb()
		if ab.end.z > 0.03 or absf(hood.position.x) > 0.001:
			_fail(id, "Hood origin is not on its rear edge (z %.2f..%.2f)" % [ab.position.z, ab.end.z])
	var trunk := parts.get("Trunk") as MeshInstance3D
	if trunk != null:
		var ab := trunk.mesh.get_aabb()
		if ab.position.z < -0.03 or absf(trunk.position.x) > 0.001:
			_fail(id, "Trunk origin is not on its front edge (z %.2f..%.2f)" % [ab.position.z, ab.end.z])
	var roof := parts.get("Roof_Convertible") as MeshInstance3D
	if roof != null:
		var ab := roof.mesh.get_aabb()
		if ab.end.z > 0.03:
			_fail(id, "Roof_Convertible origin is not on its rear edge (z %.2f..%.2f)" % [ab.position.z, ab.end.z])
		print("   roof pos=%s aabb=%s..%s" % [roof.position.snappedf(0.001), ab.position.snappedf(0.001), ab.end.snappedf(0.001)])
	var sw := parts.get("SteeringWheel") as MeshInstance3D
	if sw != null and sd != null:
		if absf(sw.position.x - sd.position.x) > 0.02 or sw.position.z > sd.position.z:
			_fail(id, "SteeringWheel is not in front of the driver")
	# --- collision helpers
	for c: String in ["Col_Body", "Col_Cabin"]:
		var mi := parts.get(c) as MeshInstance3D
		if mi == null:
			continue
		var nv := _unique_verts(mi.mesh)
		if nv > 32:
			_fail(id, "%s has %d verts (> 32)" % [c, nv])
		if _mats(id, mi) != PackedStringArray(["P_Collision"]):
			_fail(id, "%s material is not P_Collision" % c)
	for g: String in ["Glass_Windshield", "Glass_Rear", "Glass_L", "Glass_R"]:
		var mi := parts.get(g) as MeshInstance3D
		if mi != null and _mats(id, mi) != PackedStringArray(["M_Glass"]):
			_fail(id, "%s material is not M_Glass only" % g)
	if vis > 7000:
		_fail(id, "visible tris %d > 7000 budget" % vis)
	if lod > vis / 4:
		_fail(id, "Body_LOD1 %d tris is more than 25%% of %d" % [lod, vis])
	var keys := mat_set.keys()
	keys.sort()
	print("AUDIT %s: nodes=%d vis_tris=%d all_tris=%d lod=%d body_aabb=(%.2f x %.2f x %.2f) y %.3f..%.3f z %.2f..%.2f"
			% [id, parts.size(), vis, all, lod, bab.size.x, bab.size.z, bab.size.y, bab.position.y, bab.end.y, bab.position.z, bab.end.z])
	print("   wheels:", wtxt)
	print("   seats:", stxt)
	print("   materials: ", keys)
	root.free()


func _audit_wheel(id: String) -> void:
	var root := _load(id, DIR + "parts/" + id + ".glb")
	if root == null:
		return
	var asset := root.get_child(0) as Node3D if root.get_child_count() == 1 else null
	if asset == null or asset.name != id or asset.get_child_count() != 1 or asset.get_child(0).name != "Wheel":
		_fail(id, "expected FileRoot -> %s -> Wheel" % id)
		root.free()
		return
	var mi := asset.get_child(0) as MeshInstance3D
	if mi == null or mi.mesh == null:
		_fail(id, "Wheel is not a mesh")
		root.free()
		return
	var ab := mi.mesh.get_aabb()
	var r := maxf(ab.size.y, ab.size.z) * 0.5
	if ab.get_center().length() > 0.004 or mi.position.length() > 0.001 or asset.position.length() > 0.001:
		_fail(id, "origin is not the wheel centre")
	if not (ab.size.x < ab.size.y and absf(ab.size.y - ab.size.z) < 0.03):
		_fail(id, "axle is not local X (aabb %s)" % ab.size)
	if absf(r - 0.34) > 0.006:
		_fail(id, "radius %.3f, contract 0.34" % r)
	var mats := _mats(id, mi)
	if not (mats.has("M_Tire") and mats.has("M_Rim")) or mats.size() != 2:
		_fail(id, "materials must be M_Tire + M_Rim, got %s" % mats)
	var t := _tris(mi.mesh)
	if t > 900:
		_fail(id, "%d tris > 900" % t)
	print("AUDIT %s: tris=%d r=%.3f w=%.3f mats=%s" % [id, t, r, ab.size.x, mats])
	root.free()
