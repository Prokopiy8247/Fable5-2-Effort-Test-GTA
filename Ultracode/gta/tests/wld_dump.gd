extends Node
## WORLD data dump (headless): writes qa/world_dump.json (locations, roads, intersections, lots, spawn
## counts, statistics). The tables in docs/WORLD.md were produced from this file.
##   tools\godot.ps1 -Mode headless -Frames 300 -UserArgs '--test=wld_dump','--disable=traffic,peds,police','--no_player'


func _ready() -> void:
	var w: Variant = Game.world
	if w == null or w.get("roads") == null:
		TestHarness.finish(false, "no world")
		return
	var roads: Variant = w.get("roads")
	var out := {}
	var locs := {}
	var all: Dictionary = w.get_locations()
	for k: String in all:
		var xf: Transform3D = all[k]
		locs[k] = [snappedf(xf.origin.x, 0.01), snappedf(xf.origin.y, 0.01), snappedf(xf.origin.z, 0.01),
				snappedf(rad_to_deg(xf.basis.get_euler().y), 0.1), String(w.get_district(xf.origin))]
	out["locations"] = locs
	var segs: Array = []
	for s: Dictionary in roads.segments:
		var p: PackedVector2Array = s["pts2"]
		segs.append({"id": s["id"], "name": s["name"], "kind": s["kind"], "width": s["width"], "lanes_per_dir": s["lanes_per_dir"],
				"speed": s["speed_limit"], "length": snappedf(float(s["length"]), 0.1), "parking": s["parking"],
				"from": [snappedf(p[0].x, 0.1), snappedf(p[0].y, 0.1)], "to": [snappedf(p[p.size() - 1].x, 0.1), snappedf(p[p.size() - 1].y, 0.1)],
				"node_a": s["node_a"], "node_b": s["node_b"]})
	out["segments"] = segs
	var nodes: Array = []
	for n: Dictionary in roads.intersections:
		var pos: Vector3 = n["position"]
		var legs: Array = []
		for l: Dictionary in n["legs"]:
			legs.append(String(roads.segments[int(l["seg"])]["name"]))
		nodes.append({"id": n["id"], "x": snappedf(pos.x, 0.1), "z": snappedf(pos.z, 0.1), "signal": n["has_signal"],
				"radius": snappedf(float(n["radius"]), 0.1), "legs": legs})
	out["intersections"] = nodes
	var lots: Array = []
	for lot: Dictionary in w.get_lots():
		var c: Vector3 = lot["center"]
		var size: Vector2 = lot["size"]
		lots.append({"id": lot["id"], "district": lot["district"], "zone": lot["zone"], "x": snappedf(c.x, 0.1), "y": snappedf(c.y, 0.01),
				"z": snappedf(c.z, 0.1), "w": snappedf(size.x, 0.1), "d": snappedf(size.y, 0.1),
				"yaw": snappedf(rad_to_deg(float(lot["yaw"])), 0.1), "landmark": lot["landmark"], "block": lot["block"]})
	out["lots"] = lots
	var spawns := {}
	for k: String in w.get_spawn_kinds():
		spawns[k] = (w.get_spawn_points(k) as Array).size()
	out["spawn_counts"] = spawns
	var stops: Array = []
	for s: Dictionary in w.get_transit_stops():
		var sp: Vector3 = s["position"]
		stops.append({"name": s["name"], "x": snappedf(sp.x, 0.1), "z": snappedf(sp.z, 0.1), "offset": snappedf(float(s["offset"]), 0.1)})
	out["transit_stops"] = stops
	var tp: PackedVector3Array = w.get_transit_path()
	var tl := 0.0
	for i in range(1, tp.size()):
		tl += tp[i].distance_to(tp[i - 1])
	out["transit_length"] = snappedf(tl, 0.1)
	out["lanes"] = (roads.lanes as Array).size()
	out["lane_km"] = snappedf(float(roads.total_lane_length) / 1000.0, 0.01)
	out["walk_nodes"] = int(w.get("walk").node_count())
	out["stats"] = w.get("stats")
	var path := ProjectSettings.globalize_path("res://qa/world_dump.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		TestHarness.finish(false, "cannot write " + path)
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("WORLD_DUMP: ", path)
	TestHarness.check(true, "world dump written")
	TestHarness.finish()
