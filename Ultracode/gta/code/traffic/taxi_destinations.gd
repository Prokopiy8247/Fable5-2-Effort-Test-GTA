class_name TaxiDestinations
extends RefCounted
## Taxi destinations and drop-off points (pure data helper of TaxiSystem; no nodes).
##
## Destinations = the named places the world publishes as map labels (World.get_minimap_data()
## "labels" of kind "location": "Bay Arms", "Founders Plaza", "Halcyon Light" ...), grouped by
## district (World.get_district), plus the player's map waypoint. Every destination gets a
## drop-off point on the kerb lane whose right-hand side faces the place (right-hand traffic: the
## passenger steps out on the sidewalk side), away from the junction ends of the lane.

const DISTRICT_ORDER: Array[String] = ["downtown", "midtown", "residential", "industrial", "waterfront", "beach",
		"hill", "airport"]
const DISTRICT_NAMES := {"downtown": "Downtown", "midtown": "Midtown", "residential": "Residential",
		"industrial": "Industrial", "waterfront": "Waterfront", "beach": "Beach", "hill": "Signal Hill",
		"airport": "Airport", "ocean": "Offshore"}
const SKIP_IDS: Array[String] = ["airport_runway_start", "spawn_start", "boat_spawn", "shipwreck"]
const ICONS := {"police_station": &"police", "hospital": &"hospital", "gun_shop": &"gun_shop", "mod_garage": &"wrench",
		"clothing_store": &"shirt", "barber": &"scissors", "general_store": &"bag", "gas_station": &"drop",
		"parking_garage": &"parking", "safehouse": &"house", "shooting_range": &"target", "airport_hangar": &"plane",
		"airport_helipad": &"helipad", "lighthouse": &"lighthouse", "hill_viewpoint": &"mountain", "hill_top": &"mountain",
		"beach": &"umbrella", "marina_dock": &"anchor", "taxi_stand": &"taxi", "downtown_plaza": &"flag",
		"industrial_yard": &"flag", "residential_park": &"flag"}
const MAX_KERB_DIST := 70.0

var roads: Variant = null     ## RoadGraph (WORLD) - untyped
var lanes: Variant = null     ## TrafficLanes (traffic system's lane cache) - untyped
var _places: Array[Dictionary] = []


func setup(p_roads: Variant, p_lanes: Variant) -> void:
	roads = p_roads
	lanes = p_lanes
	_places.clear()


## Every named place once: {id, label, district, district_label, icon, pos, drop: {lane, s, pos}}.
func places() -> Array[Dictionary]:
	if not _places.is_empty() or Game.world == null:
		return _places
	var w: Node = Game.world
	var labels: Array = []
	if w.has_method("get_minimap_data"):
		var md: Variant = w.call("get_minimap_data")
		if md is Dictionary:
			labels = (md as Dictionary).get("labels", [])
	var seen := {}
	for l: Variant in labels:
		if not (l is Dictionary):
			continue
		var d := l as Dictionary
		if str(d.get("kind", "")) != "location":
			continue
		var id := str(d.get("id", ""))
		if id == "" or seen.has(id) or SKIP_IDS.has(id):
			continue
		var pos := Vector3.INF
		if w.has_method("has_location") and bool(w.call("has_location", id)):
			pos = (w.call("get_location", id) as Transform3D).origin
		else:
			var p2: Variant = d.get("position", null)
			if p2 is Vector2:
				pos = Vector3((p2 as Vector2).x, Game.ground_height((p2 as Vector2).x, (p2 as Vector2).y), (p2 as Vector2).y)
		if not pos.is_finite():
			continue
		var drop := drop_point(pos)
		if drop.is_empty():
			continue
		seen[id] = true
		var district := str(w.call("get_district", pos)) if w.has_method("get_district") else "midtown"
		_places.append({"id": id, "label": str(d.get("text", id.capitalize())), "district": district,
				"district_label": str(DISTRICT_NAMES.get(district, district.capitalize())),
				"icon": ICONS.get(id, &"pin"), "pos": pos, "drop": drop})
	_places.sort_custom(_by_district)
	return _places


func _by_district(a: Dictionary, b: Dictionary) -> bool:
	var ia := DISTRICT_ORDER.find(str(a["district"]))
	var ib := DISTRICT_ORDER.find(str(b["district"]))
	if ia != ib:
		return (ia if ia >= 0 else 99) < (ib if ib >= 0 else 99)
	return str(a["label"]) < str(b["label"])


## Kerb drop-off / pick-up point for a place: {lane, s, pos} or {} when no road is near.
## The lane whose right side faces `pos`, `s` kept off the junction ends of the lane.
func drop_point(pos: Vector3, max_dist: float = MAX_KERB_DIST) -> Dictionary:
	if roads == null or lanes == null:
		return {}
	var nl: Dictionary = roads.get_nearest_lane(pos, max_dist)
	if nl.is_empty():
		nl = roads.get_nearest_lane(pos, max_dist * 2.0)
	if nl.is_empty():
		return {}
	var lane := int(nl["lane_id"])
	var best_lane := -1
	var best_s := 0.0
	var best_d := INF
	var cands := PackedInt32Array([lane])
	var opp: Variant = (lanes.opposite as Array)[lane] if lane < (lanes.opposite as Array).size() else PackedInt32Array()
	if opp is PackedInt32Array:
		cands.append_array(opp as PackedInt32Array)
	var adj := int(lanes.adjacent[lane]) if lane < (lanes.adjacent as PackedInt32Array).size() else -1
	if adj >= 0:
		cands.append(adj)
	for c in cands:
		if c < 0 or c >= int(lanes.count):
			continue
		var s := project_on_lane(c, pos)
		var p: Vector3 = lanes.lane_point(c, s)
		var dir: Vector3 = lanes.lane_dir(c, s)
		var right := Vector3(-dir.z, 0.0, dir.x)
		var side := (pos - p).dot(right)
		var dd := Vector2(pos.x - p.x, pos.z - p.z).length()
		# the place should be on the right; among those the outer (kerb) lane, the nearest
		var score := dd + (0.0 if side > 0.0 else 40.0) - float(lanes.index[c]) * 1.5
		if score < best_d:
			best_d = score
			best_lane = c
			best_s = s
	if best_lane < 0:
		return {}
	var length := float(lanes.length[best_lane])
	# far enough into the lane that a cab coming round the corner can stop there smoothly
	var s2 := clampf(best_s, 18.0, length - 13.0) if length > 36.0 else length * 0.5
	return {"lane": best_lane, "s": s2, "pos": lanes.lane_point(best_lane, s2)}


## Offset of the point of `lane` nearest to `pos`.
func project_on_lane(lane: int, pos: Vector3) -> float:
	var pts: PackedVector3Array = (lanes.pts as Array)[lane]
	var cum: PackedFloat32Array = (lanes.cum as Array)[lane]
	var best := INF
	var best_s := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var abx := b.x - a.x
		var abz := b.z - a.z
		var l2 := abx * abx + abz * abz
		var t := 0.0 if l2 < 0.000001 else clampf(((pos.x - a.x) * abx + (pos.z - a.z) * abz) / l2, 0.0, 1.0)
		var qx := a.x + abx * t - pos.x
		var qz := a.z + abz * t - pos.z
		var d2 := qx * qx + qz * qz
		if d2 < best:
			best = d2
			best_s = cum[i] + t * (cum[i + 1] - cum[i])
	return best_s


## Driving distance along a lane route from (first lane, s0) to (last lane, s1) incl. junction curves.
func route_length(route: PackedInt32Array, s0: float, s1: float) -> float:
	if route.is_empty() or lanes == null:
		return 0.0
	if route.size() == 1:
		return absf(s1 - s0)
	var total := maxf(float(lanes.length[route[0]]) - s0, 0.0)
	for i in range(1, route.size()):
		total += float(lanes.conn_length(route[i - 1], route[i]))
		if i < route.size() - 1:
			total += float(lanes.length[route[i]])
	return total + s1
