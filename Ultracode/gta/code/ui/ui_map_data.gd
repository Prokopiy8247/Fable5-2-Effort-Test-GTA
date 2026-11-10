class_name UiMapData
extends RefCounted
## Normalised 2D map data for the minimap and the full map (map space: x = world X (east),
## y = world Z (south), metres - so north is up without any flip).
##
## Sources, in order: Game.world.get_minimap_data() (contract: roads, coast, lots, labels,
## water_rects - parsed defensively because the format details are owned by the WORLD module),
## Game.world.roads.segments, then a soft read of the WorldLayout script constants (only so the
## UI can be tested before / without the world system), else nothing ("plain radar").

const LAYOUT_PATH := "res://gta/code/world/world_layout.gd"
const DEFAULT_WIDTH := {"arterial": 16.0, "street": 11.0, "alley": 6.0, "dirt": 6.0, "runway": 24.0, "taxiway": 10.0}
const RANK := {"runway": 0, "taxiway": 1, "dirt": 2, "alley": 3, "street": 4, "arterial": 5}
const DISTRICT_NAMES := {
	"downtown": "Downtown", "midtown": "Midtown", "residential": "Sandpiper Heights",
	"industrial": "Foundry Row", "waterfront": "Marina", "beach": "Halcyon Beach",
	"hill": "Signal Hill", "airport": "Halcyon Airfield", "ocean": "Open Water",
}

var roads: Array[Dictionary] = []            ## {pts: PackedVector2Array, width, kind, name, rank}
var coast: Array[PackedVector2Array] = []    ## land polygons
var lots: Array[Dictionary] = []             ## {poly: PackedVector2Array, zone, landmark}
var labels: Array[Dictionary] = []           ## {text, pos: Vector2, kind}
var water: Array[Rect2] = []
var piers: Array[Rect2] = []                 ## wooden piers (optional extra of the world data)
var decks: Array[Rect2] = []                 ## concrete / plank decks (optional extra)
var transit: PackedVector2Array = PackedVector2Array()   ## tram loop centre line (optional extra)
var helipads: Array[Vector3] = []            ## x, z, radius (optional extra)
var places: Array[Dictionary] = []           ## {id, name, icon, color, pos: Vector2, minor: bool}
var bounds: Rect2 = Rect2(-300.0, -300.0, 600.0, 600.0)
var source: String = "none"                  ## "world", "layout", "none"
var version: int = 0                         ## bumped on every refresh (layers redraw)

var _data_bounds: Rect2 = Rect2()

static var _place_defs: Dictionary = {}
static var _district_names: Dictionary = {}


## id -> [display name, icon, colour, minor (full map only)]
static func place_defs() -> Dictionary:
	if _place_defs.is_empty():
		_place_defs = {
			"safehouse": ["Safehouse", &"house", UiStyle.TEAL_LIGHT, false],
			"hospital": ["Bayview Medical", &"hospital", Color(1.0, 0.45, 0.45), false],
			"police_station": ["HBPD Station", &"police", UiStyle.POLICE_BLUE, false],
			"gun_shop": ["Bay Arms", &"gun_shop", UiStyle.CORAL, false],
			"mod_garage": ["Torque Garage", &"wrench", UiStyle.SUN, false],
			"clothing_store": ["Tide Threads", &"shirt", Color(0.72, 0.65, 0.88), false],
			"barber": ["Barber", &"scissors", Color(0.91, 0.6, 0.68), false],
			"general_store": ["General Store", &"bag", Color(0.64, 0.85, 0.76), false],
			"gas_station": ["Gas Station", &"drop", UiStyle.SUN, false],
			"parking_garage": ["Parking Garage", &"parking", Color(0.56, 0.79, 0.91), false],
			"airport_hangar": ["Halcyon Airfield", &"plane", UiStyle.CREAM, false],
			"airport_helipad": ["Airfield Helipad", &"helipad", UiStyle.CREAM, true],
			"rooftop_helipad": ["Rooftop Helipad", &"helipad", UiStyle.CREAM, true],
			"marina_dock": ["Marina", &"anchor", Color(0.56, 0.79, 0.91), false],
			"lighthouse": ["Lighthouse", &"lighthouse", UiStyle.CREAM, false],
			"hill_viewpoint": ["Signal Hill Viewpoint", &"mountain", UiStyle.GOOD, false],
			"shooting_range": ["Shooting Range", &"target", UiStyle.CORAL, false],
			"taxi_stand": ["Taxi Stand", &"taxi", UiStyle.SUN, false],
			"race_start": ["Street Race", &"flag", UiStyle.CREAM, false],
			"beach": ["Halcyon Beach", &"umbrella", UiStyle.SUN, true],
			"tram_stop_1": ["Tram Stop", &"tram", UiStyle.MUTED, true],
			"tram_stop_2": ["Tram Stop", &"tram", UiStyle.MUTED, true],
			"tram_stop_3": ["Tram Stop", &"tram", UiStyle.MUTED, true],
			"stunt_ramp_1": ["Stunt Ramp", &"ramp", UiStyle.MUTED, true],
			"stunt_ramp_2": ["Stunt Ramp", &"ramp", UiStyle.MUTED, true],
			"stunt_ramp_3": ["Stunt Ramp", &"ramp", UiStyle.MUTED, true],
		}
	return _place_defs


## Display name of a district id ("residential" -> "Sandpiper Heights").
static func district_name(id: String) -> String:
	if _district_names.is_empty():
		_district_names = DISTRICT_NAMES.duplicate()
		if ResourceLoader.exists(LAYOUT_PATH):
			var scr := load(LAYOUT_PATH) as Script
			if scr != null:
				var lab: Variant = scr.get_script_constant_map().get("DISTRICT_LABELS", null)
				if lab is Dictionary:
					for k in lab:
						var e: Variant = lab[k]
						if e is Array and (e as Array).size() >= 3:
							_district_names[str(k)] = str(e[2])
	if _district_names.has(id):
		return str(_district_names[id])
	return id.capitalize()


func has_map() -> bool:
	return not roads.is_empty() or not coast.is_empty()


## Re-read everything from the world (cheap; called on game_ready and when the world appears).
func refresh() -> void:
	roads.clear()
	coast.clear()
	lots.clear()
	labels.clear()
	water.clear()
	piers.clear()
	decks.clear()
	helipads.clear()
	transit = PackedVector2Array()
	places.clear()
	_data_bounds = Rect2()
	source = "none"
	var w: Node = Game.world
	if w != null and not is_instance_valid(w):
		w = null
	var data: Dictionary = {}
	if w != null and w.has_method("get_minimap_data"):
		var d: Variant = w.call("get_minimap_data")
		if d is Dictionary and not (d as Dictionary).is_empty():
			data = d
			source = "world"
	if data.is_empty():
		data = _layout_fallback()
		if not data.is_empty():
			source = "layout"
	_parse(data)
	if roads.is_empty() and w != null:
		_roads_from_graph(w)
		if not roads.is_empty() and source == "none":
			source = "world"
	roads.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["rank"]) < int(b["rank"]))
	_collect_places(w)
	_compute_bounds()
	version += 1


## Nearest named place within max_dist metres of a map position ({} if none).
func place_at(p: Vector2, max_dist: float, include_minor: bool = true) -> Dictionary:
	var best: Dictionary = {}
	var best_d := max_dist
	for pl in places:
		if not include_minor and bool(pl["minor"]):
			continue
		var d := (pl["pos"] as Vector2).distance_to(p)
		if d <= best_d:
			best_d = d
			best = pl
	return best


# --- conversion helpers ----------------------------------------------------------------------------

static func to_v2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Vector3:
		return Vector2((v as Vector3).x, (v as Vector3).z)
	if v is Transform3D:
		return Vector2((v as Transform3D).origin.x, (v as Transform3D).origin.z)
	if v is Vector2i:
		return Vector2(v)
	if v is Array:
		var a: Array = v
		if a.size() >= 3:
			return Vector2(float(a[0]), float(a[2]))
		if a.size() == 2:
			return Vector2(float(a[0]), float(a[1]))
	if v is Dictionary:
		var d: Dictionary = v
		return Vector2(float(d.get("x", 0.0)), float(d.get("z", d.get("y", 0.0))))
	return Vector2.ZERO


static func to_points(v: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if v is PackedVector2Array:
		return v
	if v is PackedVector3Array:
		var p3: PackedVector3Array = v
		out.resize(p3.size())
		for i in p3.size():
			out[i] = Vector2(p3[i].x, p3[i].z)
		return out
	if v is PackedFloat32Array or v is PackedFloat64Array:
		var n: int = v.size()
		for i in range(0, n - 1, 2):
			out.append(Vector2(float(v[i]), float(v[i + 1])))
		return out
	if v is Array:
		var a: Array = v
		if a.is_empty():
			return out
		if a[0] is float or a[0] is int:
			for i in range(0, a.size() - 1, 2):
				out.append(Vector2(float(a[i]), float(a[i + 1])))
		else:
			for e in a:
				out.append(to_v2(e))
	return out


static func rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func to_rect(v: Variant) -> Rect2:
	if v is Rect2:
		return (v as Rect2).abs()
	if v is Rect2i:
		var ri: Rect2i = v
		return Rect2(ri).abs()
	if v is AABB:
		var bb: AABB = v
		return Rect2(bb.position.x, bb.position.z, bb.size.x, bb.size.z).abs()
	if v is Array and (v as Array).size() >= 4:
		return Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3])).abs()
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("rect"):
			return to_rect(d["rect"])
		if d.has("position") and d.has("size"):
			return Rect2(to_v2(d["position"]), to_v2(d["size"])).abs()
		if d.has("center") and d.has("size"):
			var s := to_v2(d["size"])
			return Rect2(to_v2(d["center"]) - s * 0.5, s).abs()
	return Rect2()


# --- parsing ---------------------------------------------------------------------------------------

func _parse(data: Dictionary) -> void:
	var rd: Variant = data.get("roads", [])
	if rd is Array:
		for r in rd:
			_add_road(r)
	var c: Variant = data.get("coast", null)
	if c is Array and not (c as Array).is_empty() and ((c as Array)[0] is Array or (c as Array)[0] is PackedVector2Array or (c as Array)[0] is PackedVector3Array):
		for poly in c:
			var pp := to_points(poly)
			if pp.size() >= 3:
				coast.append(pp)
	elif c != null:
		var pp2 := to_points(c)
		if pp2.size() >= 3:
			coast.append(pp2)
	var ld: Variant = data.get("lots", [])
	if ld is Array:
		for l in ld:
			_add_lot(l)
	var lb: Variant = data.get("labels", [])
	if lb is Array:
		for e in lb:
			if e is Dictionary:
				var d: Dictionary = e
				var txt := str(d.get("text", d.get("name", d.get("label", ""))))
				if txt == "":
					continue
				labels.append({"text": txt, "pos": to_v2(d.get("position", d.get("pos", d.get("center", Vector2.ZERO)))),
						"kind": str(d.get("kind", d.get("type", "district"))), "id": str(d.get("id", ""))})
	_rects(data.get("water_rects", data.get("water", [])), water)
	_rects(data.get("piers", []), piers)
	_rects(data.get("decks", []), decks)
	transit = to_points(data.get("transit", null))
	var hp: Variant = data.get("helipads", [])
	if hp is Array:
		for e in hp:
			if e is Vector3:
				helipads.append(e)
	if data.get("bounds", null) is Rect2:
		_data_bounds = (data["bounds"] as Rect2).abs()


func _rects(src: Variant, into: Array[Rect2]) -> void:
	if not (src is Array):
		return
	for e in src:
		var r := to_rect(e)
		if r.size.x > 0.0 and r.size.y > 0.0:
			into.append(r)


func _add_road(r: Variant) -> void:
	var pts: PackedVector2Array
	var kind := "street"
	var width := 0.0
	var road_name := ""
	if r is Dictionary:
		var d: Dictionary = r
		pts = to_points(d.get("points", d.get("pts", d.get("polyline", null))))
		kind = str(d.get("kind", "street"))
		width = float(d.get("width", 0.0))
		if width <= 0.0:
			width = float(d.get("hw", d.get("half_width", 0.0))) * 2.0
		road_name = str(d.get("name", ""))
		if bool(d.get("closed", false)) and pts.size() > 2 and pts[0] != pts[pts.size() - 1]:
			pts.append(pts[0])
	else:
		pts = to_points(r)
	if pts.size() < 2:
		return
	if width <= 0.0:
		width = float(DEFAULT_WIDTH.get(kind, 10.0))
	roads.append({"pts": pts, "width": width, "kind": kind, "name": road_name, "rank": int(RANK.get(kind, 4))})


func _add_lot(l: Variant) -> void:
	var poly := PackedVector2Array()
	var zone := ""
	var landmark := ""
	if l is Dictionary:
		var d: Dictionary = l
		zone = str(d.get("zone", ""))
		landmark = str(d.get("landmark", ""))
		if d.has("poly") or d.has("polygon") or d.has("points"):
			poly = to_points(d.get("poly", d.get("polygon", d.get("points", null))))
		elif d.has("rect"):
			poly = rect_poly(to_rect(d["rect"]))
		elif d.has("center") or d.has("position"):
			var c := to_v2(d.get("center", d.get("position", Vector2.ZERO)))
			var s := to_v2(d.get("size", Vector2(12.0, 12.0))) * 0.5
			var yaw := float(d.get("yaw", d.get("rotation", 0.0)))
			var cy := cos(yaw)
			var sy := sin(yaw)
			for corner: Vector2 in [Vector2(-s.x, -s.y), Vector2(s.x, -s.y), Vector2(s.x, s.y), Vector2(-s.x, s.y)]:
				# rotation about +Y: x' = x cos + z sin, z' = -x sin + z cos
				poly.append(c + Vector2(corner.x * cy + corner.y * sy, -corner.x * sy + corner.y * cy))
	elif l is Rect2:
		poly = rect_poly(l)
	if poly.size() >= 3:
		lots.append({"poly": poly, "zone": zone, "landmark": landmark})


func _roads_from_graph(w: Node) -> void:
	var graph: Variant = w.get("roads")
	if graph == null or not (graph is Object) or not is_instance_valid(graph):
		return
	var segs: Variant = (graph as Object).get("segments")
	if segs is Array:
		for s in segs:
			_add_road(s)


func _collect_places(w: Node) -> void:
	if w == null or not w.has_method("get_locations"):
		return
	var locs: Variant = w.call("get_locations")
	if not (locs is Dictionary):
		return
	# names published by the world ("location" labels) win over the built-in ones
	var names: Dictionary = {}
	for lab in labels:
		if str(lab["kind"]) == "location" and str(lab["id"]) != "":
			names[str(lab["id"])] = str(lab["text"])
	var defs := place_defs()
	for id: String in defs:
		if not (locs as Dictionary).has(id):
			continue
		var def: Array = defs[id]
		places.append({"id": id, "name": str(names.get(id, def[0])), "icon": def[1], "color": def[2], "minor": bool(def[3]),
				"pos": to_v2((locs as Dictionary)[id])})
	# location labels that became a place icon are not drawn as text again
	var keep: Array[Dictionary] = []
	for lab in labels:
		if str(lab["kind"]) == "location" and defs.has(str(lab["id"])):
			continue
		keep.append(lab)
	labels = keep


func _compute_bounds() -> void:
	var first := true
	var r := Rect2()
	for poly in coast:
		for p in poly:
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	for road in roads:
		for p: Vector2 in road["pts"]:
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	if _data_bounds.size.x > 50.0 and _data_bounds.size.y > 50.0:
		bounds = _data_bounds.grow(12.0)
	elif first or r.size.x < 50.0 or r.size.y < 50.0:
		bounds = Rect2(-300.0, -300.0, 600.0, 600.0)
	else:
		bounds = r.grow(20.0)


# --- WorldLayout constant fallback (soft: load by path, constants only) ----------------------------

func _layout_fallback() -> Dictionary:
	if not ResourceLoader.exists(LAYOUT_PATH):
		return {}
	var scr := load(LAYOUT_PATH) as Script
	if scr == null:
		return {}
	var consts := scr.get_script_constant_map()
	var kinds: Dictionary = consts.get("KINDS", {}) if consts.get("KINDS", {}) is Dictionary else {}
	var out_roads: Array = []
	for key in ["AIRFIELD", "ROADS"]:
		var list: Variant = consts.get(key, [])
		if not (list is Array):
			continue
		for def in list:
			if not (def is Dictionary):
				continue
			var d: Dictionary = def
			var pts := to_points(d.get("pts", []))
			if pts.size() < 2:
				continue
			var kind := str(d.get("kind", "street"))
			var hw := float(d.get("hw", 0.0))
			if hw <= 0.0 and kinds.has(kind) and kinds[kind] is Dictionary:
				hw = float((kinds[kind] as Dictionary).get("hw", 5.0))
			var closed := bool(d.get("closed", false))
			if bool(d.get("smooth", false)):
				pts = _catmull(pts)
			elif float(d.get("round", 0.0)) > 0.0:
				pts = _round_corners(pts, float(d["round"]), closed)
			if closed and pts[0] != pts[pts.size() - 1]:
				pts.append(pts[0])
			out_roads.append({"points": pts, "width": hw * 2.0, "kind": kind, "name": str(d.get("name", ""))})
	if out_roads.is_empty():
		return {}
	var out_lots: Array = []
	var blocks: Variant = consts.get("BLOCKS", [])
	if blocks is Array:
		for b in blocks:
			if not (b is Array) or (b as Array).size() < 9:
				continue
			var r := Rect2(float(b[1]), float(b[2]), float(b[3]) - float(b[1]), float(b[4]) - float(b[2])).abs().grow(-9.0)
			var opts: Variant = b[8]
			if opts is Dictionary and (opts as Dictionary).has("inner"):
				var inner: Array = (opts as Dictionary)["inner"]
				if inner.size() >= 4:
					r = Rect2(float(inner[0]), float(inner[1]), float(inner[2]) - float(inner[0]), float(inner[3]) - float(inner[1])).abs()
			if r.size.x > 2.0 and r.size.y > 2.0:
				out_lots.append({"rect": r, "zone": str(b[6])})
	var apron: Variant = consts.get("APRON", null)
	if apron is Rect2:
		out_lots.append({"rect": apron, "zone": "hangar"})
	var out_labels: Array = []
	var dl: Variant = consts.get("DISTRICT_LABELS", {})
	if dl is Dictionary:
		for k in dl:
			var e: Variant = dl[k]
			if e is Array and (e as Array).size() >= 3:
				out_labels.append({"text": str(e[2]), "position": Vector2(float(e[0]), float(e[1])), "kind": "district"})
	return {"roads": out_roads, "lots": out_lots, "labels": out_labels}


static func _round_corners(pts: PackedVector2Array, radius: float, closed: bool) -> PackedVector2Array:
	var n := pts.size()
	if n < 3:
		return pts
	var out := PackedVector2Array()
	for i in n:
		if not closed and (i == 0 or i == n - 1):
			out.append(pts[i])
			continue
		var prev := pts[(i - 1 + n) % n]
		var cur := pts[i]
		var next := pts[(i + 1) % n]
		var d0 := minf(radius, cur.distance_to(prev) * 0.5)
		var d1 := minf(radius, cur.distance_to(next) * 0.5)
		var a := cur + (prev - cur).normalized() * d0
		var b := cur + (next - cur).normalized() * d1
		for k in 7:
			var t := float(k) / 6.0
			out.append(a.lerp(cur, t).lerp(cur.lerp(b, t), t))
	return out


static func _catmull(pts: PackedVector2Array) -> PackedVector2Array:
	var n := pts.size()
	if n < 3:
		return pts
	var out := PackedVector2Array()
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		for k in 5:
			var t := float(k) / 5.0
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(pts[n - 1])
	return out
