extends Node
## WORLD contract test (headless):
##   tools\godot.ps1 -Mode headless -Frames 1500 -UserArgs '--test=wld_api','--disable=traffic,peds,police','--no_player'
## Checks every method of ARCHITECTURE 6.1, all named locations and spawn kinds, lane connectivity,
## routing, the walk graph, signal phases, colliders, the navmesh, and prints statistics.

const LOCATIONS: Array[String] = ["spawn_start", "safehouse", "safehouse_garage", "hospital", "police_station", "gun_shop",
		"mod_garage", "clothing_store", "barber", "general_store", "gas_station", "parking_garage", "downtown_plaza",
		"industrial_yard", "residential_park", "hill_viewpoint", "hill_top", "beach", "marina_dock", "boat_spawn",
		"lighthouse", "airport_runway_start", "airport_runway_end", "airport_helipad", "airport_hangar",
		"rooftop_helipad", "shooting_range", "shipwreck", "tram_stop_1", "tram_stop_2", "tram_stop_3",
		"stunt_ramp_1", "stunt_ramp_2", "stunt_ramp_3", "race_start", "taxi_stand"]
const SPAWN_KINDS: Array[String] = ["parking", "boat", "heli", "plane", "police_car", "taxi", "ped", "wildlife_land",
		"wildlife_water", "pickup_weapon", "pickup_health", "pickup_armor", "pickup_cash", "parachute", "roadblock",
		"gang", "ladder", "bench", "street_light", "traffic_light", "tree_street", "bin", "hydrant", "bus_stop",
		"tree_hill", "tree_wild", "tree_palm", "tree_park", "bush", "rock", "ground_cover", "reef"]
const NATURE_LAND: Array[String] = ["tree_hill", "tree_wild", "tree_palm", "tree_park", "bush", "rock", "ground_cover"]
const METHODS: Array[String] = ["get_height", "get_water_depth", "is_water_at", "get_surface_at", "get_district",
		"get_location", "get_locations", "get_lots", "get_spawn_points", "get_minimap_data", "get_transit_path",
		"get_transit_stops", "get_signal_heads"]
const ZONES: Array[String] = ["office", "apartment", "house", "storefront", "warehouse", "hangar", "parking", "park",
		"landmark", "plaza"]
const DISTRICTS: Array[String] = ["downtown", "midtown", "residential", "industrial", "waterfront", "beach", "hill",
		"airport", "ocean"]
const MIN_LOT := {"police_station": [30, 26], "hospital": [34, 30], "gun_shop": [18, 16], "shooting_range": [32, 14],
		"mod_garage": [24, 20], "clothing_store": [18, 16], "barber": [14, 14], "general_store": [18, 16],
		"gas_station": [30, 24], "safehouse": [20, 18], "parking_garage": [34, 30], "airport_hangar": [32, 32],
		"airport_tower": [14, 14], "lighthouse": [10, 10], "tram_stop_1": [14, 6], "tram_stop_2": [14, 6],
		"tram_stop_3": [14, 6], "radio_mast": [8, 8]}

var T: Node


func _ready() -> void:
	T = TestHarness
	var w: Variant = Game.world
	if not T.check(w != null, "Game.world exists"):
		T.finish(false, "no world")
		return
	for m in METHODS:
		T.check(w.has_method(m), "World has method " + m)
	var roads: Variant = w.get("roads")
	var walk: Variant = w.get("walk")
	if not T.check(roads != null and walk != null and w.get("nav_region") != null, "roads / walk / nav_region are set"):
		T.finish(false, "world not built")
		return
	var stats: Dictionary = w.get("stats")
	T.log_line("stats: " + str(stats))
	T.check(int(stats.get("setup_ms", 99999)) < 4000, "world.setup() under 4 s (%d ms)" % int(stats.get("setup_ms", -1)))

	_test_heights(w)
	_test_locations(w)
	_test_spawns(w, roads)
	_test_lots(w)
	_test_roads(w, roads)
	_test_walk(w, walk)
	_test_transit_minimap(w)
	await _test_colliders(w)
	await _test_signal_clock(roads)
	await _test_nav(w)
	T.finish()


func _test_heights(w: Variant) -> void:
	T.check(absf(float(w.get_height(0.0, -60.0)) - 2.53) < 0.011, "road surface on Meridian Avenue = 2.53 (%.3f)" % float(w.get_height(0.0, -60.0)))
	T.check(absf(float(w.get_height(-113.0, -150.0)) - 2.65) < 0.011, "sidewalk = 2.65 (%.3f)" % float(w.get_height(-113.0, -150.0)))
	T.check(absf(float(w.get_height(-90.0, -150.0)) - 2.65) < 0.03, "block slab about 2.65 (%.3f)" % float(w.get_height(-90.0, -150.0)))
	var top := float(w.get_height(225.0, -128.0))
	T.check(top > 36.0 and top < 40.0, "Signal Hill top about 38 m (%.2f)" % top)
	T.check(float(w.get_height(0.0, 420.0)) < -10.0, "open sea bed is deep (%.2f)" % float(w.get_height(0.0, 420.0)))
	T.check(float(w.get_water_depth(148.0, 298.0)) > 8.0, "deep basin at the shipwreck (%.2f m)" % float(w.get_water_depth(148.0, 298.0)))
	T.check(float(w.get_water_depth(0.0, 0.0)) <= 0.0, "no water depth on land")
	T.check(absf(float(w.get_height(-150.0, 270.0)) - 1.15) < 0.02, "marina pier deck = 1.15 (%.2f)" % float(w.get_height(-150.0, 270.0)))
	T.check(absf(float(w.get_height(-278.0, 100.0)) - 2.52) < 0.02, "docks quay deck edge = 2.52 (%.2f)" % float(w.get_height(-278.0, 100.0)))
	T.check(bool(w.is_water_at(Vector3(-300.0, -1.0, 100.0))), "harbour basin is water")
	T.check(not bool(w.is_water_at(Vector3(-300.0, 2.0, 100.0))), "above the surface is not water")
	T.check(not bool(w.is_water_at(Vector3(0.0, -1.0, 0.0))), "under the city is not water")
	T.check(bool(w.is_water_at(Vector3(-150.0, -1.0, 270.0))), "water under the pier")
	var surf := {"asphalt": Vector3(0.0, 2.6, -60.0), "concrete": Vector3(-113.0, 2.7, -150.0), "grass": Vector3(205.0, 20.0, -100.0),
			"sand": Vector3(150.0, 1.0, 262.0), "wood": Vector3(-150.0, 1.2, 270.0), "water": Vector3(0.0, 0.0, 400.0)}
	for s: String in surf:
		var got := String(w.get_surface_at(surf[s]))
		T.check(got == s, "surface %s at %s (got %s)" % [s, str(surf[s]), got])
	var dist := {"downtown": Vector3(-30.0, 3.0, -150.0), "midtown": Vector3(-30.0, 3.0, 30.0), "residential": Vector3(190.0, 3.0, 40.0),
			"industrial": Vector3(-190.0, 3.0, -60.0), "waterfront": Vector3(-100.0, 3.0, 240.0), "beach": Vector3(160.0, 2.0, 246.0), "beach ": Vector3(180.0, 3.0, 200.0), "waterfront ": Vector3(60.0, 3.0, 200.0),
			"hill": Vector3(225.0, 38.0, -128.0), "airport": Vector3(0.0, 3.0, -250.0), "ocean": Vector3(0.0, 0.0, 420.0)}
	for d: String in dist:
		var got := String(w.get_district(dist[d]))
		T.check(got == d.strip_edges(), "district %s at %s (got %s)" % [d.strip_edges(), str(dist[d]), got])
	# every paved slab must sit on the flat plateau (no floating / buried city ground)
	var bad := 0
	for lot: Dictionary in w.get_lots():
		if String(lot["block"]) == "":
			continue
		var c: Vector3 = lot["center"]
		var size: Vector2 = lot["size"]
		for off: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2.ZERO]:
			var sideways := absf(sin(float(lot["yaw"]))) > 0.5
			var hx := (size.y if sideways else size.x) * 0.5
			var hz := (size.x if sideways else size.y) * 0.5
			if absf(Terrain.height(c.x + off.x * hx, c.z + off.y * hz) - 2.5) > 0.02:
				bad += 1
				T.log_line("off-plateau lot corner (%.1f, %.1f) h=%.2f: %s" % [c.x + off.x * hx, c.z + off.y * hz, Terrain.height(c.x + off.x * hx, c.z + off.y * hz), str(lot)])
	T.check(bad == 0, "all block lots lie on the flat plateau (%d corner violations)" % bad)


func _test_locations(w: Variant) -> void:
	var locs: Dictionary = w.get_locations()
	var missing: PackedStringArray = []
	for n in LOCATIONS:
		if not locs.has(n):
			missing.append(n)
			continue
		var xf: Transform3D = w.get_location(n)
		var p := xf.origin
		T.check(absf(p.x) <= 300.0 and absf(p.z) <= 300.0, "location %s inside the map %s" % [n, str(p.snapped(Vector3(0.1, 0.1, 0.1)))])
		var depth := float(w.get_water_depth(p.x, p.z))
		if n == "shipwreck" or n == "boat_spawn":
			T.check(depth > 1.5, "location %s is in water (depth %.1f)" % [n, depth])
		elif n == "marina_dock":
			T.check(absf(p.y - 1.15) < 0.05, "marina_dock stands on the pier deck")
		else:
			T.check(depth <= 0.0, "location %s is on land" % n)
			if n != "rooftop_helipad":
				T.check(absf(p.y - float(w.get_height(p.x, p.z))) < 0.05, "location %s sits on the ground" % n)
		T.check(xf.basis.is_finite() and absf(xf.basis.determinant() - 1.0) < 0.01, "location %s has a clean basis" % n)
	T.check(missing.is_empty(), "all 36 named locations exist (missing: %s)" % ", ".join(missing))
	# use points face their building
	for n: String in ["police_station", "hospital", "gun_shop", "safehouse", "gas_station"]:
		var lot: Dictionary = w.get_landmark_lot(n)
		var xf: Transform3D = w.get_location(n)
		var to_lot: Vector3 = (lot["center"] as Vector3) - xf.origin
		to_lot.y = 0.0
		T.check((-xf.basis.z).dot(to_lot.normalized()) > 0.9, "use point %s faces its lot" % n)
		T.check(String(w.get_surface_at(xf.origin)) == "concrete", "use point %s is on the sidewalk" % n)
	T.check(w.get_location("no_such_place") is Transform3D, "unknown location returns a Transform3D")


func _test_spawns(w: Variant, roads: Variant) -> void:
	var counts := {}
	for k in SPAWN_KINDS:
		var pts: Array[Transform3D] = w.get_spawn_points(k)
		counts[k] = pts.size()
		T.check(not pts.is_empty(), "spawn kind '%s' has points (%d)" % [k, pts.size()])
	T.log_line("spawn points: " + str(counts))
	T.check((w.get_spawn_points("nonsense") as Array).is_empty(), "unknown spawn kind returns an empty array")
	var near_lane := 0
	var off_road := 0
	for xf: Transform3D in w.get_spawn_points("parking"):
		var hit: Dictionary = roads.get_nearest_lane(xf.origin, 2.3)
		if not hit.is_empty():
			near_lane += 1
		var s := String(w.get_surface_at(xf.origin))
		if s != "asphalt":
			off_road += 1
	T.check(near_lane == 0, "no parking spawn point overlaps a traffic lane (%d too close)" % near_lane)
	T.check(off_road == 0, "all parking spawn points are on asphalt (%d are not)" % off_road)
	for k: String in ["boat", "wildlife_water"]:
		var dry := 0
		for xf: Transform3D in w.get_spawn_points(k):
			if float(w.get_water_depth(xf.origin.x, xf.origin.z)) < 1.0:
				dry += 1
		T.check(dry == 0, "all '%s' points are over water" % k)
	for k: String in ["ped", "street_light", "tree_street", "bench", "bin", "hydrant", "bus_stop", "wildlife_land", "gang", "parachute",
			"pickup_health", "pickup_armor", "pickup_cash", "heli", "plane", "taxi", "police_car"]:
		var wet := 0
		var floating := 0
		for xf: Transform3D in w.get_spawn_points(k):
			if float(w.get_water_depth(xf.origin.x, xf.origin.z)) > 0.0 and float(w.get_height(xf.origin.x, xf.origin.z)) < 0.5:
				wet += 1
			if absf(xf.origin.y - float(w.get_height(xf.origin.x, xf.origin.z))) > 0.06:
				floating += 1
		T.check(wet == 0 and floating == 0, "'%s' points are on dry ground (%d wet, %d off the surface)" % [k, wet, floating])
	var lights_on_road := 0
	for k: String in ["street_light", "tree_street", "hydrant", "traffic_light", "bin", "bus_stop", "bench"]:
		for xf: Transform3D in w.get_spawn_points(k):
			if String(w.get_surface_at(xf.origin)) == "asphalt":
				lights_on_road += 1
	T.check(lights_on_road == 0, "no street furniture point stands on the carriageway (%d do)" % lights_on_road)
	# nature placement data: natural ground only, on the surface, away from lanes / runway / each other
	var t_n := Time.get_ticks_usec()
	var bad_surface := 0
	var off_surface := 0
	var near_lane2 := 0
	var in_clear_zone := 0
	var crowded := 0
	var trees: Array[Vector3] = []
	for k: String in NATURE_LAND:
		for xf: Transform3D in w.get_spawn_points(k):
			var o := xf.origin
			if not (String(w.get_surface_at(o)) in ["grass", "sand"]):
				bad_surface += 1
				if bad_surface <= 6:
					T.log_line("nature point off natural ground: %s at %s on %s" % [k, str(o), String(w.get_surface_at(o))])
			if absf(o.y - float(w.get_height(o.x, o.z))) > 0.06 or float(w.get_water_depth(o.x, o.z)) > 0.0:
				off_surface += 1
			if k != "ground_cover" and not (roads.get_nearest_lane(o, 4.0) as Dictionary).is_empty():
				near_lane2 += 1
			if k.begins_with("tree") and o.z < -212.0:
				in_clear_zone += 1
			if k.begins_with("tree"):
				for q: Vector3 in trees:
					if Vector2(q.x - o.x, q.z - o.z).length_squared() < 4.0 * 4.0:
						crowded += 1
						break
				if trees.size() < 900:
					trees.append(o)
	T.check(bad_surface == 0, "nature points stand on grass / sand only (%d do not)" % bad_surface)
	T.check(off_surface == 0, "nature points sit on dry ground (%d off the surface or wet)" % off_surface)
	T.check(near_lane2 == 0, "no tree / bush / rock within 4 m of a traffic lane (%d are)" % near_lane2)
	T.check(in_clear_zone == 0, "no trees in the runway clear zone (%d are)" % in_clear_zone)
	T.check(crowded == 0, "trees are at least 4 m apart (%d too close)" % crowded)
	var reef_bad := 0
	for xf: Transform3D in w.get_spawn_points("reef"):
		if float(w.get_water_depth(xf.origin.x, xf.origin.z)) < 2.4 or absf(xf.origin.y - float(w.get_height(xf.origin.x, xf.origin.z))) > 0.1:
			reef_bad += 1
	T.check(reef_bad == 0, "reef points lie on the seabed at least 2.4 m deep (%d do not)" % reef_bad)
	T.log_line("nature checks took %d us" % (Time.get_ticks_usec() - t_n))
	var heads: Array = w.get_signal_heads()
	T.check(heads.size() == (w.get_spawn_points("traffic_light") as Array).size() and heads.size() > 20,
			"signal heads match the traffic_light points (%d)" % heads.size())
	var heads_ok := true
	for h: Dictionary in heads:
		if (h["lane_ids"] as PackedInt32Array).is_empty() or not (h["transform"] is Transform3D):
			heads_ok = false
	T.check(heads_ok, "every signal head lists its lanes")


func _test_lots(w: Variant) -> void:
	var lots: Array[Dictionary] = w.get_lots()
	var by_zone := {}
	var by_district := {}
	var keys_ok := true
	var on_land := true
	for lot in lots:
		for k: String in ["id", "district", "zone", "center", "size", "yaw", "landmark"]:
			if not lot.has(k):
				keys_ok = false
		by_zone[lot["zone"]] = int(by_zone.get(lot["zone"], 0)) + 1
		by_district[lot["district"]] = int(by_district.get(lot["district"], 0)) + 1
		if not (String(lot["zone"]) in ZONES) or not (String(lot["district"]) in DISTRICTS):
			keys_ok = false
		var c: Vector3 = lot["center"]
		if float(w.get_water_depth(c.x, c.z)) > 0.0:
			on_land = false
	T.log_line("lots per zone: " + str(by_zone))
	T.log_line("lots per district: " + str(by_district))
	T.check(lots.size() > 100, "more than 100 lots (%d)" % lots.size())
	T.check(keys_ok, "every lot has the contract keys and valid zone / district ids")
	T.check(on_land, "every lot centre is on land")
	for z in ZONES:
		T.check(by_zone.has(z), "zone '%s' is used" % z)
	for n: String in MIN_LOT:
		var lot: Dictionary = w.get_landmark_lot(n)
		if not T.check(not lot.is_empty(), "landmark lot '%s' exists" % n):
			continue
		var size: Vector2 = lot["size"]
		var need: Array = MIN_LOT[n]
		T.check(size.x >= float(need[0]) - 0.01 and size.y >= float(need[1]) - 0.01, "lot %s is at least %dx%d (%.0fx%.0f)" % [n, need[0], need[1], size.x, size.y])
	# lots must not overlap each other
	var rects: Array[Rect2] = []
	for lot in lots:
		var c: Vector3 = lot["center"]
		var size: Vector2 = lot["size"]
		var sideways := absf(sin(float(lot["yaw"]))) > 0.5
		var ext := Vector2(size.y, size.x) if sideways else size
		rects.append(Rect2(Vector2(c.x, c.z) - ext * 0.5, ext).grow(-0.05))
	var overlaps := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				overlaps += 1
				if overlaps <= 4:
					T.log_line("lot overlap: %s / %s" % [str(lots[i]), str(lots[j])])
	T.check(overlaps == 0, "lots do not overlap (%d overlapping pairs)" % overlaps)
	# no lot may reach into a carriageway
	var on_road := 0
	for i in rects.size():
		var r := rects[i]
		for p: Vector2 in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), r.get_center()]:
			if String(lots[i]["block"]) != "" and String(lots[i]["zone"]) != "parking" and String(w.get_surface_at(Vector3(p.x, 3.0, p.y))) == "asphalt":
				on_road += 1
				T.log_line("lot corner on a road at %s: %s" % [str(p), str(lots[i])])
	T.check(on_road == 0, "no lot corner lies on a road (%d do)" % on_road)


func _test_roads(w: Variant, roads: Variant) -> void:
	var segs: Array = roads.segments
	var lanes: Array = roads.lanes
	var inters: Array = roads.intersections
	var kinds := {}
	var seg_ok := true
	for s: Dictionary in segs:
		kinds[s["kind"]] = int(kinds.get(s["kind"], 0)) + 1
		for k: String in ["id", "points", "width", "lanes_per_dir", "speed_limit", "kind", "name"]:
			if not s.has(k):
				seg_ok = false
		if String(s["kind"]) in ["runway", "taxiway"] and int(s["lanes_per_dir"]) != 0:
			seg_ok = false
	T.log_line("segments per kind: " + str(kinds))
	T.check(seg_ok, "segments have the contract keys; runway / taxiway carry no lanes")
	for k: String in ["arterial", "street", "alley", "dirt", "runway", "taxiway"]:
		T.check(kinds.has(k), "segment kind '%s' exists" % k)
	var signals := 0
	var inter_ok := true
	for n: Dictionary in inters:
		for k: String in ["id", "position", "radius", "has_signal"]:
			if not n.has(k):
				inter_ok = false
		if n["has_signal"]:
			signals += 1
	T.check(inter_ok, "intersections have the contract keys")
	T.check(signals >= 12 and signals < inters.size(), "signalised (%d) and unsignalised (%d) intersections" % [signals, inters.size() - signals])
	T.log_line("lanes: %d, lane km: %.2f, intersections: %d" % [lanes.size(), float(roads.total_lane_length) / 1000.0, inters.size()])
	var lane_ok := true
	var dead := 0
	var short := 0
	for l: Dictionary in lanes:
		for k: String in ["id", "points", "length", "speed_limit", "next", "segment_id", "end_intersection"]:
			if not l.has(k):
				lane_ok = false
		if (l["next"] as PackedInt32Array).is_empty():
			dead += 1
		if float(l["length"]) < 8.0:
			short += 1
	T.check(lane_ok, "lanes have the contract keys")
	T.check(dead == 0, "no lane is a dead end (%d without next)" % dead)
	T.check(short == 0, "no degenerate lanes (%d shorter than 8 m)" % short)
	# strong connectivity: forward and backward BFS from lane 0
	var n_l := lanes.size()
	var rev: Array = []
	for i in n_l:
		rev.append(PackedInt32Array())
	for l: Dictionary in lanes:
		for nx: int in (l["next"] as PackedInt32Array):
			var r: PackedInt32Array = rev[nx]
			r.append(int(l["id"]))
			rev[nx] = r
	var fwd := _bfs(n_l, func(i: int) -> PackedInt32Array: return lanes[i]["next"])
	var bwd := _bfs(n_l, func(i: int) -> PackedInt32Array: return rev[i])
	T.check(fwd == n_l and bwd == n_l, "lane graph is strongly connected (forward %d, backward %d of %d)" % [fwd, bwd, n_l])
	# right-hand traffic
	var near: Dictionary = roads.get_nearest_lane(Vector3(1.75, 2.5, -60.0), 3.0)
	if T.check(not near.is_empty(), "get_nearest_lane finds the northbound lane of Meridian Avenue"):
		var xf: Transform3D = roads.sample_lane(int(near["lane_id"]), float(near["offset"]))
		T.check((-xf.basis.z).dot(Vector3(0, 0, -1)) > 0.95, "east-side lane of a N-S avenue runs north (right-hand traffic)")
		T.check(xf.origin.distance_to(near["point"]) < 0.05, "sample_lane(offset) returns the nearest point")
		T.check(not (roads.get_next_lanes(int(near["lane_id"])) as PackedInt32Array).is_empty(), "get_next_lanes works")
	T.check((roads.get_nearest_lane(Vector3(0.0, 0.0, 600.0), 30.0) as Dictionary).is_empty(), "get_nearest_lane returns {} far from roads")
	T.check(float(lanes[int(near["lane_id"])]["speed_limit"]) == 14.0, "avenue speed limit 14 m/s")
	var ring: Dictionary = roads.get_nearest_lane(Vector3(-40.0, 2.5, -190.0), 10.0)
	T.check(not ring.is_empty() and float(lanes[int(ring["lane_id"])]["speed_limit"]) == 22.0, "ring arterial speed limit 22 m/s")
	# routing between far apart places
	var pairs: Array = [["safehouse", "airport_hangar"], ["police_station", "hill_top"], ["lighthouse", "industrial_yard"],
			["gas_station", "parking_garage"], ["hospital", "beach"]]
	for pr: Array in pairs:
		var a: Vector3 = (w.get_location(pr[0]) as Transform3D).origin
		var b: Vector3 = (w.get_location(pr[1]) as Transform3D).origin
		var t0 := Time.get_ticks_usec()
		var route: PackedVector3Array = roads.find_route(a, b)
		var us := Time.get_ticks_usec() - t0
		if not T.check(route.size() >= 2, "find_route %s -> %s returns a polyline" % [pr[0], pr[1]]):
			continue
		var length := 0.0
		var max_gap := 0.0
		var off_lane := 0.0
		for i in range(1, route.size()):
			var d := route[i].distance_to(route[i - 1])
			length += d
			var mid := (route[i] + route[i - 1]) * 0.5
			var hit: Dictionary = roads.get_nearest_lane(mid, 40.0)
			off_lane = maxf(off_lane, float(hit.get("distance", 99.0)))
			if d > max_gap:
				max_gap = d
		var direct := Vector2(a.x - b.x, a.z - b.z).length()
		var ends_ok: bool = float((roads.get_nearest_lane(a, 700.0) as Dictionary)["distance"]) + 12.0 > Vector2(route[0].x - a.x, route[0].z - a.z).length() \
				and Vector2(route[route.size() - 1].x - b.x, route[route.size() - 1].z - b.z).length() < 60.0
		T.check(off_lane < 14.0 and ends_ok and length >= direct * 0.8 and length < direct * 4.0 + 200.0,
				"route %s -> %s is continuous on roads: %.0f m (direct %.0f m), %d points, max off-lane %.1f m, %d us" % [pr[0], pr[1], length, direct, route.size(), off_lane, us])
	var lr: PackedInt32Array = roads.find_lane_route(0, n_l - 1)
	var lr_ok := lr.size() >= 2 and lr[0] == 0 and lr[lr.size() - 1] == n_l - 1
	if lr_ok:
		for i in range(1, lr.size()):
			if not (lanes[lr[i - 1]]["next"] as PackedInt32Array).has(lr[i]):
				lr_ok = false
	T.check(lr_ok, "find_lane_route returns a chain of connected lanes (%d lanes)" % lr.size())
	var got := 0
	for i in 20:
		var rp: Dictionary = roads.random_lane_point(Vector3(0.0, 2.5, 0.0), 60.0, 160.0)
		if rp.is_empty():
			continue
		var o: Vector3 = (rp["transform"] as Transform3D).origin
		var d := Vector2(o.x, o.z).length()
		if d >= 59.9 and d <= 160.1 and rp.has("lane_id") and rp.has("offset"):
			got += 1
	T.check(got == 20, "random_lane_point respects the distance band (%d / 20)" % got)
	# signal logic: all three states appear and crossing directions are never green together
	var seen := {}
	var conflict := 0
	var steps := int(ceil(float(roads.CYCLE_TIME) / 0.25)) + 4
	for s in steps:
		roads.advance(0.25)
		for n: Dictionary in inters:
			if not n["has_signal"]:
				continue
			var open_groups := {}
			for li: int in (n["lanes_in"] as PackedInt32Array):
				var st: int = roads.get_signal_state(li)
				seen[st] = true
				if st != 2:
					open_groups[int(lanes[li]["signal_group"])] = true
			if open_groups.size() > 1:
				conflict += 1
	T.check(seen.has(0) and seen.has(1) and seen.has(2), "signals cycle through green / yellow / red")
	T.check(conflict == 0, "crossing approaches are never open at the same time (%d conflicts)" % conflict)
	var unsig := -1
	for l: Dictionary in lanes:
		if int(l["signal_group"]) < 0:
			unsig = int(l["id"])
			break
	T.check(unsig >= 0 and int(roads.get_signal_state(unsig)) == 0, "unsignalised lanes report green")


func _bfs(n: int, next_of: Callable) -> int:
	var seen := PackedByteArray()
	seen.resize(n)
	var stack: Array[int] = [0]
	seen[0] = 1
	var cnt := 0
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		cnt += 1
		var nxt: PackedInt32Array = next_of.call(cur)
		for nx in nxt:
			if seen[nx] == 0:
				seen[nx] = 1
				stack.append(nx)
	return cnt


func _test_walk(w: Variant, walk: Variant) -> void:
	var n: int = walk.node_count()
	var in_main := 0
	for i in n:
		if (walk.main as PackedByteArray)[i] == 1:
			in_main += 1
	T.log_line("walk graph: %d nodes, %d in the main component" % [n, in_main])
	T.check(n > 600, "walk graph has more than 600 nodes (%d)" % n)
	T.check(in_main >= int(float(n) * 0.985), "walk graph is connected (%d of %d nodes in the main component)" % [in_main, n])
	var pairs: Array = [["safehouse", "police_station"], ["hospital", "hill_viewpoint"], ["marina_dock", "airport_hangar"], ["beach", "gun_shop"]]
	for pr: Array in pairs:
		var a: Vector3 = (w.get_location(pr[0]) as Transform3D).origin
		var b: Vector3 = (w.get_location(pr[1]) as Transform3D).origin
		var t0 := Time.get_ticks_usec()
		var path: PackedVector3Array = walk.find_path(a, b)
		var us := Time.get_ticks_usec() - t0
		var max_step := 0.0
		var length := 0.0
		for i in range(1, path.size()):
			max_step = maxf(max_step, path[i].distance_to(path[i - 1]))
			length += path[i].distance_to(path[i - 1])
		T.check(path.size() >= 2 and max_step < 31.0 and path[0].distance_to(a) < 40.0 and path[path.size() - 1].distance_to(b) < 40.0,
				"walk path %s -> %s: %d nodes, %.0f m, max step %.1f m, %d us" % [pr[0], pr[1], path.size(), length, max_step, us])
	var ok := 0
	for i in 30:
		var p: Vector3 = walk.random_point(Vector3(0.0, 2.5, 0.0), 20.0, 120.0)
		if p.is_finite():
			var d := Vector2(p.x, p.z).length()
			if d > 12.0 and d < 128.0 and float(w.get_water_depth(p.x, p.z)) <= 0.0:
				ok += 1
	T.check(ok == 30, "random_point returns dry points in the band (%d / 30)" % ok)
	T.check(not (walk.random_point(Vector3(0.0, 0.0, 900.0), 5.0, 30.0) as Vector3).is_finite(), "random_point returns Vector3.INF when nothing is in range")
	var np: Vector3 = walk.get_nearest_point(Vector3(-90.0, 2.5, -150.0))
	T.check(np.is_finite() and String(w.get_surface_at(np)) != "asphalt", "get_nearest_point from a block centre lands on a sidewalk / path (%s)" % str(np))
	# sidewalk nodes must be on the sidewalk, crosswalk interior nodes on the road
	var wrong := 0
	for i in n:
		if int((walk.kinds as PackedByteArray)[i]) == 0 and String(w.get_surface_at((walk.points as PackedVector3Array)[i])) == "asphalt":
			wrong += 1
			T.log_line("sidewalk node on asphalt: " + str((walk.points as PackedVector3Array)[i]))
	T.check(wrong == 0, "sidewalk nodes are not on the carriageway (%d are)" % wrong)


func _test_transit_minimap(w: Variant) -> void:
	var path: PackedVector3Array = w.get_transit_path()
	var length := 0.0
	var max_seg := 0.0
	for i in range(1, path.size()):
		length += path[i].distance_to(path[i - 1])
		max_seg = maxf(max_seg, path[i].distance_to(path[i - 1]))
	T.check(path.size() > 20 and path[0].distance_to(path[path.size() - 1]) < 0.5 and length > 600.0 and max_seg < 9.0,
			"tram loop is closed: %.0f m, %d points" % [length, path.size()])
	var stops: Array = w.get_transit_stops()
	var stops_ok := stops.size() == 3
	var last := -1.0
	for s: Dictionary in stops:
		if not (s.has("name") and s.has("position") and s.has("offset")) or float(s["offset"]) <= last:
			stops_ok = false
		last = float(s.get("offset", 0.0))
		var lot_pos: Vector3 = (w.get_location(String(s["name"])) as Transform3D).origin
		if lot_pos.distance_to(s["position"]) > 16.0:
			stops_ok = false
	T.check(stops_ok, "three tram stops with increasing offsets next to their platforms")
	var t0 := Time.get_ticks_msec()
	var mm: Dictionary = w.get_minimap_data()
	var ms := Time.get_ticks_msec() - t0
	var mm_ok := true
	for k: String in ["roads", "coast", "lots", "labels", "water_rects"]:
		if not mm.has(k):
			mm_ok = false
	T.check(mm_ok, "minimap data has the contract keys")
	if mm_ok:
		var coast: PackedVector2Array = mm["coast"]
		var area := 0.0
		for i in coast.size():
			var a := coast[i]
			var b := coast[(i + 1) % coast.size()]
			area += a.x * b.y - b.x * a.y
		area = absf(area) * 0.5
		T.check(coast.size() > 100 and area > 250000.0 and area < 360000.0, "coast polygon: %d points, %.1f ha, built in %d ms" % [coast.size(), area / 10000.0, ms])
		T.check((mm["roads"] as Array).size() == (w.get("roads").segments as Array).size() and (mm["lots"] as Array).size() == (w.get_lots() as Array).size(),
				"minimap roads / lots match the world data")
		T.check((mm["labels"] as Array).size() >= 20, "minimap labels for districts and locations (%d)" % (mm["labels"] as Array).size())
		var rd: Dictionary = (mm["roads"] as Array)[0]
		T.check(rd.has("points") and rd.has("width") and rd.has("kind"), "minimap road entries carry points / width / kind")


func _test_colliders(w: Variant) -> void:
	await T.wait_physics_frames(3)
	var space := (w as Node3D).get_world_3d().direct_space_state
	var probes: Array = [[0.0, -60.0, "asphalt"], [-113.0, -150.0, "concrete"], [205.0, -100.0, "grass"], [150.0, 262.0, "sand"],
			[-150.0, 270.0, "wood"], [-274.0, 100.0, "concrete"], [30.0, -60.0, "concrete"], [191.0, 26.0, "grass"],
			[0.0, -264.0, "asphalt"], [-200.0, -250.0, "concrete"], [225.0, -128.0, "dirt"], [0.0, 350.0, "sand"]]
	for p: Array in probes:
		var x := float(p[0])
		var z := float(p[1])
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -30.0, z), Layers.WORLD)
		var hit := space.intersect_ray(q)
		if not T.check(not hit.is_empty(), "ground collider under (%.0f, %.0f)" % [x, z]):
			continue
		var y: float = (hit["position"] as Vector3).y
		var expect := float(w.get_height(x, z))
		var surf := String((hit["collider"] as Object).get_meta("surface", "?"))
		T.check(absf(y - expect) < 0.06 and surf == String(p[2]),
				"collider at (%.0f, %.0f): y %.2f (get_height %.2f), surface %s (expected %s)" % [x, z, y, expect, surf, p[2]])


func _test_signal_clock(roads: Variant) -> void:
	var before: float = roads.signal_time
	await T.wait_physics_frames(30)
	T.check(float(roads.signal_time) > before + 0.3, "the signal clock advances with game time")


func _test_nav(w: Variant) -> void:
	var waited := 0
	var t_nav := Time.get_ticks_msec()
	while not bool(w.is_nav_ready()) and Time.get_ticks_msec() - t_nav < 70000:
		OS.delay_msec(8)
		await get_tree().process_frame
		waited += 1
	if not T.check(bool(w.is_nav_ready()), "navmesh is ready after %d frames / %d ms" % [waited, Time.get_ticks_msec() - t_nav]):
		return
	var region: NavigationRegion3D = w.get("nav_region")
	var nm := region.navigation_mesh
	T.check(nm != null and nm.get_polygon_count() > 300, "navigation mesh has polygons (%d, source %s)" % [
			nm.get_polygon_count() if nm != null else 0, str((w.get("stats") as Dictionary).get("nav_source", "?"))])
	T.log_line("stats after nav: " + str(w.get("stats")))
	var map := (w as Node3D).get_world_3d().navigation_map
	var probe_a: Vector3 = (w.get_location("spawn_start") as Transform3D).origin
	var probe_b: Vector3 = (w.get_location("police_station") as Transform3D).origin
	var synced := 0
	var t_wait := Time.get_ticks_msec()
	# the navigation server builds region / map iterations on worker threads: wait in real time
	while synced < 1500 and Time.get_ticks_msec() - t_wait < 20000 and NavigationServer3D.map_get_path(map, probe_a, probe_b, true).size() < 2:
		OS.delay_msec(8)
		await get_tree().physics_frame
		synced += 1
	T.log_line("navigation map answered after %d physics frames / %d ms (iteration id %d, server polygons %d, edges %d, regions %d, navmesh vertices %d)" % [
			synced, Time.get_ticks_msec() - t_wait, NavigationServer3D.map_get_iteration_id(map),
			int(NavigationServer3D.get_process_info(NavigationServer3D.INFO_POLYGON_COUNT)),
			int(NavigationServer3D.get_process_info(NavigationServer3D.INFO_EDGE_COUNT)),
			NavigationServer3D.map_get_regions(map).size(), nm.get_vertices().size()])
	T.log_line("closest navmesh point to spawn_start: %s (spawn %s)" % [str(NavigationServer3D.map_get_closest_point(map, probe_a)), str(probe_a)])
	var pairs: Array = [["spawn_start", "police_station"], ["hospital", "hill_top"], ["marina_dock", "beach"]]
	for pr: Array in pairs:
		var a: Vector3 = (w.get_location(pr[0]) as Transform3D).origin
		var b: Vector3 = (w.get_location(pr[1]) as Transform3D).origin
		var t0 := Time.get_ticks_usec()
		var path := NavigationServer3D.map_get_path(map, a, b, true)
		var us := Time.get_ticks_usec() - t0
		var ok := path.size() >= 2 and path[0].distance_to(a) < 6.0 and path[path.size() - 1].distance_to(b) < 6.0
		T.check(ok, "NavigationServer path %s -> %s: %d points, %d us" % [pr[0], pr[1], path.size(), us])
