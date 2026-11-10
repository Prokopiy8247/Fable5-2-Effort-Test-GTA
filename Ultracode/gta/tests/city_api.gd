extends Node
## City builder API / placement test (headless):
##   tools\godot.ps1 -Mode headless -Frames 1500 -UserArgs '--test=city_api','--disable=traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## Checks: W2.4 API, every landmark lot has its landmark, every landmark of docs/LANDMARKS.md (+ the
## infrastructure ones) has a transform and all manifest markers, no footprint overlaps a road or
## another building, a ray from above hits every building, a character-sized capsule gets from the
## street through the doorway to every ground-floor Use_* marker of the walk-in landmarks, ladders,
## the automatic safehouse door, the GLB visitor pier, night-material hooks, catalogue variety and
## the boot time.

## docs/LANDMARKS.md section 2 + docs/LANDMARKS_INFRA.md (lot names)
const LANDMARKS: Array[String] = ["police_station", "hospital", "gun_shop", "shooting_range", "mod_garage",
		"clothing_store", "barber", "general_store", "gas_station", "safehouse", "airport_hangar", "airport_tower",
		"lighthouse", "tram_stop_1", "tram_stop_2", "tram_stop_3", "radio_mast", "parking_garage"]
const CAPSULE_R := 0.3
const STEP := 0.35
const CHAR_H := 1.8
const CELL := 0.3

var _city: Node
var _space: PhysicsDirectSpaceState3D
var _capsule: CapsuleShape3D
var _q: PhysicsShapeQueryParameters3D


func _ready() -> void:
	_city = Game.get_system("city")
	if not TestHarness.check(_city != null, "city system exists"):
		TestHarness.finish(false, "no city system")
		return
	TestHarness.check(bool(_city.call("is_built")), "city is built")
	var st: Dictionary = _city.call("get_debug_info")
	TestHarness.log_line("city setup %.0f ms (plan %.0f, load %.0f, place %.0f, post %.0f), %d buildings, %d nodes, roles %s" % [
			float(st.get("setup_ms", -1)), float(st.get("plan_ms", -1)), float(st.get("load_ms", -1)),
			float(st.get("place_ms", -1)), float(st.get("post_ms", -1)), int(st.get("buildings", 0)),
			int(st.get("nodes", 0)), str(st.get("roles", {}))])
	TestHarness.check(float(st.get("setup_ms", 99999.0)) < 2500.0, "city setup under 2.5 s (%.0f ms)" % float(st.get("setup_ms", -1)))
	for m: String in ["has_landmark", "get_landmark_node", "get_landmark_transform", "has_landmark_marker",
			"get_landmark_marker", "get_landmark_markers", "get_buildings"]:
		TestHarness.check(_city.has_method(m), "API method " + m)
	await TestHarness.wait_physics_frames(3)
	_space = (_city as Node3D).get_world_3d().direct_space_state
	_capsule = CapsuleShape3D.new()
	_capsule.radius = CAPSULE_R
	_capsule.height = CHAR_H - STEP
	_q = PhysicsShapeQueryParameters3D.new()
	_q.shape = _capsule
	_q.collision_mask = Layers.WORLD

	_check_landmark_lots()
	_check_landmark_markers()
	_check_overlaps()
	_check_raycasts()
	_check_ground_fit()
	_check_variety(st)
	_check_misc()
	_check_ladder_fit()
	_check_entrances()
	_check_spawn_points()
	_check_doorways()
	await _check_door()
	_check_enable_toggle()
	TestHarness.finish()


func _buildings() -> Array[Dictionary]:
	return _city.call("get_buildings")


func _check_landmark_lots() -> void:
	var n := 0
	for lot: Dictionary in Game.world.get_lots():
		var lm := String(lot["landmark"])
		if lm == "":
			continue
		n += 1
		var ok: bool = _city.call("has_landmark", lm)
		TestHarness.check(ok, "landmark lot '%s' has its building" % lm)
		if not ok:
			continue
		var node: Node3D = _city.call("get_landmark_node", lm)
		TestHarness.check(node != null and node.is_inside_tree(), "%s node in the tree" % lm)
		var xf: Transform3D = _city.call("get_landmark_transform", lm)
		var c: Vector3 = lot["center"]
		TestHarness.check(Vector2(xf.origin.x - c.x, xf.origin.z - c.z).length() < 0.05 and absf(xf.origin.y - c.y) < 0.3,
				"%s origin at the lot centre (%.2f, %.2f, %.2f)" % [lm, xf.origin.x, xf.origin.y, xf.origin.z])
		var fwd := -xf.basis.z
		var want := Basis(Vector3.UP, float(lot["yaw"])) * Vector3.FORWARD
		TestHarness.check(fwd.dot(want) > 0.999, "%s front faces the street (lot yaw)" % lm)
	TestHarness.check(n == 18, "18 landmark lots (%d)" % n)


func _check_landmark_markers() -> void:
	var cat := BuildingCatalog.new()
	cat.load_all()
	for lm in LANDMARKS:
		TestHarness.check(_city.call("has_landmark", lm), "landmark %s exists" % lm)
		var xf: Transform3D = _city.call("get_landmark_transform", lm)
		TestHarness.check(xf.origin.length() > 1.0, "landmark %s has a transform" % lm)
		var d: Dictionary = cat.find_landmark(lm)
		if d.is_empty():
			continue
		var mk: Variant = d.get("markers", {})
		if not (mk is Dictionary):
			continue
		var world_mk: Dictionary = _city.call("get_landmark_markers", lm)
		var bad := PackedStringArray()
		for k: String in (mk as Dictionary):
			var v: Array = (mk as Dictionary)[k]
			if not bool(_city.call("has_landmark_marker", lm, k)) or not world_mk.has(k):
				bad.append(k + " missing")
				continue
			var got: Transform3D = _city.call("get_landmark_marker", lm, k)
			var exp := xf * Vector3(float(v[0]), float(v[1]), float(v[2]))
			if got.origin.distance_to(exp) > 0.01:
				bad.append("%s at %s, expected %s" % [k, got.origin, exp])
		TestHarness.check(bad.is_empty(), "%s: %d manifest markers in world space %s" % [lm, (mk as Dictionary).size(), ", ".join(bad)])


## Footprints vs road surfaces and vs each other.
func _check_overlaps() -> void:
	var bs := _buildings()
	var segs: Array = Game.world.roads.segments
	var road_hits := PackedStringArray()
	for b in bs:
		var r: Rect2 = b["rect"]
		r = r.grow(-0.05)
		for seg: Dictionary in segs:
			var pts: PackedVector2Array = seg["pts2"]
			var hw := float(seg["hw"])
			for i in range(1, pts.size()):
				if _seg_rect_dist(pts[i - 1], pts[i], r) < hw:
					road_hits.append("%s_%d (%s) / %s" % [b["id"], b["lot_id"], b["role"], seg.get("name", "")])
					break
	TestHarness.check(road_hits.is_empty(), "no building footprint on a road (%d): %s" % [road_hits.size(), ", ".join(road_hits)])
	var pairs := PackedStringArray()
	for i in bs.size():
		var a: Rect2 = (bs[i]["rect"] as Rect2).grow(-0.05)
		for j in range(i + 1, bs.size()):
			var b: Rect2 = (bs[j]["rect"] as Rect2).grow(-0.05)
			if a.intersects(b):
				pairs.append("%s@%d x %s@%d" % [bs[i]["id"], bs[i]["lot_id"], bs[j]["id"], bs[j]["lot_id"]])
	TestHarness.check(pairs.is_empty(), "no two building footprints overlap (%d): %s" % [pairs.size(), ", ".join(pairs)])
	# every building stands on its lot(s) (piers excepted)
	var lots: Array = Game.world.get_lots()
	var outside := PackedStringArray()
	for b in bs:
		if String(b["role"]) == "pier":
			continue
		var ids: Array = b["lot_ids"]
		var union := Rect2()
		var first := true
		for id: Variant in ids:
			var lot: Dictionary = lots[int(id)]
			var lr := _lot_rect(lot)
			union = lr if first else union.merge(lr)
			first = false
		if not union.grow(0.35).encloses(b["rect"]):
			outside.append("%s@%d" % [b["id"], b["lot_id"]])
	TestHarness.check(outside.is_empty(), "every footprint lies on its lot(s): %s" % ", ".join(outside))


static func _lot_rect(lot: Dictionary) -> Rect2:
	var c: Vector3 = lot["center"]
	var s: Vector2 = lot["size"]
	var sideways := absf(sin(float(lot["yaw"]))) > 0.5
	var hx := (s.y if sideways else s.x) * 0.5
	var hz := (s.x if sideways else s.y) * 0.5
	return Rect2(c.x - hx, c.z - hz, hx * 2.0, hz * 2.0)


static func _seg_rect_dist(a: Vector2, b: Vector2, r: Rect2) -> float:
	# 0 if the segment touches the rectangle, else the smallest distance (sampled, fine for > 0.5 m)
	var n := maxi(2, int(a.distance_to(b) / 0.5))
	var best := INF
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
		var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best


func _check_raycasts() -> void:
	var miss := PackedStringArray()
	var wrong_layer := 0
	for b in _buildings():
		var node: Node3D = b["node"]
		var xf: Transform3D = b["transform"]
		var fp: Vector2 = b["footprint"]
		var top := xf.origin.y + float(b["height"]) + 5.0
		var hit_it := false
		for q: Vector2 in [Vector2(0, 0), Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.3)]:
			var p := xf * Vector3(q.x * fp.x, 0.0, q.y * fp.y)
			var rq := PhysicsRayQueryParameters3D.create(Vector3(p.x, top, p.z), Vector3(p.x, xf.origin.y - 1.0, p.z), Layers.WORLD)
			var h := _space.intersect_ray(rq)
			if h.is_empty():
				continue
			var col := h["collider"] as Node
			if col != null and node.is_ancestor_of(col):
				hit_it = true
				if (col as CollisionObject3D).collision_layer != Layers.WORLD:
					wrong_layer += 1
				break
		if not hit_it:
			miss.append("%s@%d" % [b["id"], b["lot_id"]])
	TestHarness.check(miss.is_empty(), "a ray from above hits every building (%d missed): %s" % [miss.size(), ", ".join(miss)])
	TestHarness.check(wrong_layer == 0, "building bodies are on Layers.WORLD only")


## No building sunken into or floating above the terrain (footprint corners + centre, plinths excepted).
func _check_ground_fit() -> void:
	var worst_sunk := 0.0
	var worst_float := 0.0
	var bad := PackedStringArray()
	for b in _buildings():
		if String(b["role"]) == "pier":
			continue
		var xf: Transform3D = b["transform"]
		var d := _def_of(String(b["id"]))
		var fp: Vector2 = d["fp"]
		var co: Vector2 = d["co"]
		var sunk := 0.0
		var flt := 0.0
		for q: Vector2 in [Vector2(0, 0), Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
			var p := xf * Vector3(co.x + q.x * (fp.x - 0.6), 0.0, co.y + q.y * (fp.y - 0.6))
			var g := float(Game.world.get_height(p.x, p.z))
			sunk = maxf(sunk, g - xf.origin.y)
			flt = maxf(flt, xf.origin.y - g)
		worst_sunk = maxf(worst_sunk, sunk)
		if not bool(b["plinth"]):
			worst_float = maxf(worst_float, flt)
		if sunk > 0.3 or (flt > 0.65 and not bool(b["plinth"])):
			bad.append("%s@%d (sunk %.2f, gap %.2f)" % [b["id"], b["lot_id"], sunk, flt])
	TestHarness.log_line("ground fit: worst sunk %.2f m, worst gap under a footprint corner %.2f m" % [worst_sunk, worst_float])
	TestHarness.check(bad.is_empty(), "no building sunken > 0.3 m or floating > 0.65 m without a plinth: %s" % ", ".join(bad))


## Ladder nodes sit on the measured rail line and their top exit (foot + height - back * 0.55, where
## PlayerStateLadder puts the climber) is solid ground at the right height.
func _check_ladder_fit() -> void:
	for lad: Node3D in _city.call("get_ladders"):
		var foot := lad.global_position
		var h := float(lad.get_meta("height", 0.0))
		var back := lad.global_transform.basis.z
		back.y = 0.0
		back = back.normalized()
		var exit := foot + Vector3(0, h, 0) - back * 0.55
		var hit := _space.intersect_ray(PhysicsRayQueryParameters3D.create(exit + Vector3(0, 1.5, 0), exit + Vector3(0, -1.0, 0), Layers.WORLD))
		var bid := String(lad.get_meta("building", ""))
		TestHarness.check(not hit.is_empty() and absf((hit["position"] as Vector3).y - exit.y) < 0.2,
				"%s ladder: top exit %s is solid ground at the top height (hit %s)" % [bid, str(exit), str(hit.get("position", "none"))])
		var lb: Vector3 = lad.get_meta("line_bottom", foot)
		var lt: Vector3 = lad.get_meta("line_top", foot)
		var off_b := Vector2(lb.x - foot.x, lb.z - foot.z).length()
		var off_t := Vector2(lt.x - foot.x, lt.z - foot.z).length()
		TestHarness.log_line("%s ladder: foot %s height %.2f, rail line %.2f m off at the foot, %.2f m at the top" % [bid, str(foot), h, off_b, off_t])
		TestHarness.check(off_b < 0.3 and off_t < 0.6, "%s ladder node on the rail line (%.2f / %.2f m)" % [bid, off_b, off_t])


## The synthesized Entrance marker's -Z points into the building.
func _check_entrances() -> void:
	for b in _buildings():
		if String(b["role"]) != "landmark" or not bool(b["walk_in"]):
			continue
		var lm := String(b["landmark"])
		if not bool(_city.call("has_landmark_marker", lm, "Entrance")):
			continue
		var e: Transform3D = _city.call("get_landmark_marker", lm, "Entrance")
		var p_in := e.origin - e.basis.z * 1.5
		TestHarness.check((b["rect"] as Rect2).has_point(Vector2(p_in.x, p_in.z)), "%s Entrance marker faces into the building" % lm)


## World spawn points (peds, pickups, gangs, parked cars, ...) must not end up inside solid buildings.
func _check_spawn_points() -> void:
	if not Game.world.has_method("get_spawn_kinds"):
		return
	var strict: Array[String] = ["ped", "pickup_weapon", "pickup_health", "pickup_armor", "pickup_cash", "gang", "bench",
			"parking", "police_car", "taxi", "roadblock", "wildlife_land", "parachute", "boat", "plane", "heli"]
	var bad := PackedStringArray()
	var soft := PackedStringArray()
	var bs := _buildings()
	for kind: String in Game.world.call("get_spawn_kinds"):
		for x: Transform3D in Game.world.get_spawn_points(kind):
			var p := x.origin
			for b in bs:
				var xf: Transform3D = b["transform"]
				if p.y > xf.origin.y + 2.5 or p.y < xf.origin.y - 1.0:
					continue
				if not (b["rect"] as Rect2).grow(-0.3).has_point(Vector2(p.x, p.z)):
					continue
				var s := "%s (%.1f, %.1f) in %s@%d" % [kind, p.x, p.z, b["id"], b["lot_id"]]
				if strict.has(kind) and String(b["collision"]) == "box":
					bad.append(s)
				else:
					soft.append(s)
				break
	if not soft.is_empty():
		TestHarness.log_line("spawn points inside open / walk-in buildings or of dressing kinds (%d): %s" % [soft.size(), ", ".join(soft)])
	TestHarness.check(bad.is_empty(), "no gameplay spawn point inside a solid building (%d): %s" % [bad.size(), ", ".join(bad)])


func _check_enable_toggle() -> void:
	_city.call("set_enabled", false)
	TestHarness.check(not (_city as Node3D).visible and not _city.is_processing(), "set_enabled(false) hides the city and stops its loop")
	_city.call("set_enabled", true)
	TestHarness.check((_city as Node3D).visible and _city.is_processing(), "set_enabled(true) shows the city and restarts the door / room-light loop")


func _check_variety(st: Dictionary) -> void:
	var cat := BuildingCatalog.new()
	cat.load_all()
	var used := {}
	for b in _buildings():
		used[String(b["id"])] = true
	var unused := PackedStringArray()
	for d in cat.all():
		if not used.has(String(d["id"])):
			unused.append(String(d["id"]))
	TestHarness.log_line("catalogue %d types, used %d, unused: %s" % [cat.defs.size(), used.size(), ", ".join(unused)])
	TestHarness.log_line("usage: " + str(st.get("usage", {})))
	TestHarness.log_line("empty lots: " + str(st.get("empty_lots", [])))
	TestHarness.check(unused.is_empty(), "every catalogue building appears in the city (unused: %s)" % ", ".join(unused))
	# no identical neighbours along one block row (main buildings sorted along the street)
	var lots: Array = Game.world.get_lots()
	var rows := {}
	for b in _buildings():
		if String(b["role"]) != "building":
			continue
		var lot: Dictionary = lots[int(b["lot_id"])]
		var key := "%s|%s" % [lot.get("block", ""), lot.get("row", "")]
		var yaw := float(lot["yaw"])
		var ax := Vector3(cos(yaw), 0.0, -sin(yaw))
		if not rows.has(key):
			rows[key] = []
		(rows[key] as Array).append([(b["transform"] as Transform3D).origin.dot(ax), String(b["id"]), int(b["lot_id"])])
	var same := PackedStringArray()
	for key: String in rows:
		var arr: Array = rows[key]
		arr.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
		for i in range(1, arr.size()):
			if arr[i][1] == arr[i - 1][1]:
				same.append("%s lots %d/%d (%s)" % [arr[i][1], arr[i - 1][2], arr[i][2], key])
	TestHarness.check(same.is_empty(), "no identical buildings side by side in a row (%d): %s" % [same.size(), ", ".join(same)])


func _check_misc() -> void:
	# ladders
	var lads := get_tree().get_nodes_in_group("ladder")
	var ours := 0
	for n in lads:
		if (_city as Node).is_ancestor_of(n):
			ours += 1
			TestHarness.check(n.has_meta("height") and float(n.get_meta("height")) > 0.5, "ladder %s has a height (%.2f)" % [n.get_path(), float(n.get_meta("height", 0.0))])
	TestHarness.check(ours >= 2, "radio mast + pier end ladders in group 'ladder' (%d)" % ours)
	var mast := _city.call("get_landmark_node", "radio_mast") as Node3D
	TestHarness.check(mast != null and mast.get_node_or_null("Ladder") != null, "radio mast ladder node")
	# visitor pier walkable deck
	TestHarness.check(_city.call("has_landmark", "marina_pier"), "GLB visitor pier placed")
	if _city.call("has_landmark", "marina_pier"):
		var xf: Transform3D = _city.call("get_landmark_transform", "marina_pier")
		var p := xf.origin
		var h := _space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 5, -2.0), p + Vector3(0, -3, -2.0), Layers.WORLD))
		TestHarness.check(not h.is_empty() and absf((h["position"] as Vector3).y - p.y) < 0.25,
				"pier end deck is walkable at y %.2f (hit %s)" % [p.y, str(h.get("position", "none"))])
		for z: float in [-8.0, -20.0, -30.0]:
			var h2 := _space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 5, z), p + Vector3(0, -3, z), Layers.WORLD))
			TestHarness.check(not h2.is_empty(), "pier deck continuous at dz %.0f (y %s)" % [z, str((h2.get("position", Vector3.ZERO) as Vector3).y)])
	# roof helipad location
	var hp: Transform3D = Game.world.get_location("rooftop_helipad")
	var hospital: Transform3D = _city.call("get_landmark_transform", "hospital")
	TestHarness.check(hp.origin.y > hospital.origin.y + 15.0 and Vector2(hp.origin.x - hospital.origin.x, hp.origin.z - hospital.origin.z).length() < 20.0,
			"rooftop_helipad on the hospital roof (%s)" % str(hp.origin))
	var hh := _space.intersect_ray(PhysicsRayQueryParameters3D.create(hp.origin + Vector3(0, 4, 0), hp.origin + Vector3(0, -1, 0), Layers.WORLD))
	TestHarness.check(not hh.is_empty() and absf((hh["position"] as Vector3).y - hp.origin.y) < 0.3, "helipad surface is solid")
	# night material hooks on the shared meshes
	var hooked := 0
	var office := _first_building("office_a")
	if office != null:
		var glass := office.get_node_or_null("Building_Glass") as MeshInstance3D
		if glass != null:
			for s in glass.mesh.get_surface_count():
				var m := glass.mesh.surface_get_material(s)
				if m != null and String(m.resource_name).begins_with("M_Window_Env"):
					hooked += 1
	TestHarness.check(hooked > 0 or Game.get_system("environment") == null, "office_a windows use the lit-window hook material")
	# walk-in shops: inward window panes are transparent glass, outward ones keep the lit-window hook
	var gshop := _city.call("get_landmark_node", "gun_shop") as Node3D
	var gglass := gshop.get_node_or_null("Building_Glass") as MeshInstance3D if gshop != null else null
	var inner_glass := 0
	var outer_lit := 0
	if gglass != null:
		for s in gglass.mesh.get_surface_count():
			var m := gglass.mesh.surface_get_material(s)
			if m == null:
				continue
			if String(m.resource_name) == "City_InteriorGlass":
				inner_glass += 1
			elif m is ShaderMaterial:
				outer_lit += 1
	TestHarness.check(inner_glass == 1 and (outer_lit >= 1 or Game.get_system("environment") == null),
			"gun shop windows: transparent inner panes + lit-window outer panes (%d / %d surfaces, %d tris split city-wide)" % [
			inner_glass, outer_lit, int((_city.call("get_debug_info") as Dictionary).get("interior_glass_tris", 0))])
	# interiors are culled by distance, big towers always visible
	var gun := _city.call("get_landmark_node", "gun_shop") as Node3D
	var inter := gun.get_node_or_null("Building_Interior") as GeometryInstance3D if gun != null else null
	TestHarness.check(inter != null and inter.visibility_range_end > 0.0 and inter.visibility_range_end < 80.0, "gun shop interior has a short visibility range")
	var tall := _first_building("office_c")
	var shell := tall.get_node_or_null("Building") as GeometryInstance3D if tall != null else null
	TestHarness.check(shell != null and shell.visibility_range_end == 0.0, "office_c tower always visible")
	# plinths (hill side)
	var plinths := 0
	for b in _buildings():
		if bool(b["plinth"]):
			plinths += 1
	TestHarness.log_line("plinths: %d" % plinths)
	# occluders
	var occ := get_tree().get_nodes_in_group("city_building").size()
	TestHarness.log_line("building roots in group city_building: %d" % occ)


func _first_building(id: String) -> Node3D:
	for b in _buildings():
		if String(b["id"]) == id:
			return b["node"]
	return null


# ---------------------------------------------------------------------------------------------
# doorway walk test: grid search with a character capsule (r 0.3, from 0.35 m above the floor up to
# 1.8 m) from 1.8 m in front of the street facade to each ground-floor Use_* marker.
# ---------------------------------------------------------------------------------------------

func _check_doorways() -> void:
	for b in _buildings():
		if String(b["role"]) != "landmark" or not bool(b["walk_in"]):
			continue
		var lm := String(b["landmark"])
		var cat_def: Dictionary = _def_of(String(b["id"]))
		var xf: Transform3D = b["transform"]
		var mk: Dictionary = b["markers"]
		var ent: Transform3D = mk.get("Entrance", Transform3D.IDENTITY)
		var fp: Vector2 = cat_def["fp"]
		var co: Vector2 = cat_def["co"]
		var ov: Dictionary = cat_def["ov"]
		var front := co.y - fp.y * 0.5 - float(ov["front"])
		var start := Vector2(ent.origin.x, front - 1.8)
		for k: String in mk:
			if not k.begins_with("Use_"):
				continue
			var m: Transform3D = mk[k]
			if m.origin.y > 1.0:
				TestHarness.log_line("%s %s is on an upper floor (y %.1f): not walked" % [lm, k, m.origin.y])
				continue
			var res := _walk(xf, start, Vector2(m.origin.x, m.origin.z), fp, co)
			TestHarness.check(res == "", "%s: a character gets from the street to %s %s" % [lm, k, res])


var _cat_cache: BuildingCatalog


func _def_of(id: String) -> Dictionary:
	if _cat_cache == null:
		_cat_cache = BuildingCatalog.new()
		_cat_cache.load_all()
	return _cat_cache.get_def(id)


func _free(xf: Transform3D, p: Vector2) -> bool:
	var w := xf * Vector3(p.x, STEP + _capsule.height * 0.5, p.y)
	_q.transform = Transform3D(Basis.IDENTITY, w)
	return _space.intersect_shape(_q, 1).is_empty()


func _walk(xf: Transform3D, start: Vector2, goal: Vector2, fp: Vector2, co: Vector2) -> String:
	var x0 := co.x - fp.x * 0.5 - 3.0
	var z0 := co.y - fp.y * 0.5 - 3.0
	var nx := int((fp.x + 6.0) / CELL) + 1
	var nz := int((fp.y + 6.0) / CELL) + 1
	var to_cell := func(p: Vector2) -> Vector2i: return Vector2i(clampi(int(round((p.x - x0) / CELL)), 0, nx - 1), clampi(int(round((p.y - z0) / CELL)), 0, nz - 1))
	var s: Vector2i = to_cell.call(start)
	var g: Vector2i = to_cell.call(goal)
	if not _free(xf, Vector2(x0 + s.x * CELL, z0 + s.y * CELL)):
		return "(start blocked)"
	var seen := {s: true}
	var open: Array[Vector2i] = [s]
	var head := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var reach := 1.2 / CELL          # Interactables use a 2 m radius; 1.2 m is stricter
	while head < open.size():
		var c: Vector2i = open[head]
		head += 1
		if Vector2(c - g).length() <= reach:
			return ""
		for dv: Vector2i in dirs:
			var n: Vector2i = c + dv
			if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz or seen.has(n):
				continue
			seen[n] = true
			if _free(xf, Vector2(x0 + n.x * CELL, z0 + n.y * CELL)):
				open.append(n)
	return "(no path, %d cells searched)" % seen.size()


# ---------------------------------------------------------------------------------------------
# automatic landmark door (safehouse Door_1)
# ---------------------------------------------------------------------------------------------

func _check_door() -> void:
	var doors: Array = _city.call("get_doors")
	TestHarness.check(not doors.is_empty(), "landmark doors registered (%d)" % doors.size())
	if doors.is_empty() or not Game.has_player():
		TestHarness.log_line("door motion not tested (no player)")
		return
	var d: Dictionary = doors[0]
	var c: Vector3 = d["centre"]
	await TestHarness.wait_physics_frames(10)
	TestHarness.check(float(d["open"]) < 0.05, "door starts closed (%.2f)" % float(d["open"]))
	var front: Transform3D = _city.call("get_landmark_marker", "safehouse", "Door_Front")
	Game.player.call("teleport", front.origin + Vector3(0, 0.1, 0), 0.0)
	await TestHarness.wait_seconds(1.0)
	var now: Dictionary = (_city.call("get_doors") as Array)[0]
	TestHarness.check(float(now["open"]) > 0.95, "door opens when the player is %.1f m away (%.2f)" % [
			Vector2(front.origin.x - c.x, front.origin.z - c.z).length(), float(now["open"])])
	Game.player.call("teleport", front.origin + front.basis * Vector3(0, 0.1, 8.0), 0.0)
	await TestHarness.wait_seconds(1.0)
	now = (_city.call("get_doors") as Array)[0]
	TestHarness.check(float(now["open"]) < 0.05, "door closes again when the player leaves (%.2f)" % float(now["open"]))
