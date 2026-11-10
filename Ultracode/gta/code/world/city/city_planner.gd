extends RefCounted
## City builder helper (module-private, no class_name): decides which building stands on which lot.
## Pure data in, pure data out - deterministic (own seeded RNG, never Game.rng), no nodes.
##
## Rules (docs/CITY.md section 2):
## - Landmark lots get their landmark building (manifest "landmark" / "serves"), origin at the lot
##   centre, yaw = lot yaw.
## - Generic lots of one block row form a "run" along the street. The run is cut into units of one lot
##   or two neighbouring lots (merged when a wide building - office_c, warehouse_b, storefront_c ... -
##   or a pair of buildings fills them better). A unit holds one or two main buildings plus an
##   optional small filler (kiosk / shed / garage row). Every building lies inside its unit, fronts the
##   street (yaw = lot yaw) and is set back from the lot front by a zone dependent distance.
## - Scoring: street-frontage fill, catalogue novelty (unused buildings first), district tags, never
##   the same building twice in a row, a little seeded jitter.

const SEED := 520017 + 9173
const EDGE := 0.1             ## min distance between a building and the side edge of its unit
const GAP := 0.25             ## min gap between two buildings of one unit
const DEPTH_TOL := 0.3        ## a building may reach this far past the back edge of its lot
const CONTIGUOUS := 1.2       ## max gap between two lots of one run
const MERGE_ZONES: Array[String] = ["office", "apartment", "storefront", "warehouse", "hangar"]
const ZONE_CANDIDATES := {
	"office": ["cat:office"], "apartment": ["cat:apartment"], "house": ["cat:house"],
	"storefront": ["cat:storefront"], "warehouse": ["cat:warehouse"],
	"hangar": ["cat:hangar", "tag:hangar", "cat:warehouse"],
}
const ZONE_FILLERS := {
	"office": ["kiosk_a"], "storefront": ["kiosk_a"], "apartment": ["kiosk_a", "garage_row"],
	"house": ["shed_a"], "warehouse": ["garage_row", "shed_a"], "hangar": ["garage_row", "shed_a"],
}
const FILLER_IDS: Array[String] = ["kiosk_a", "shed_a", "garage_row"]
## Landmark lots whose building has no manifest "landmark" field.
const LANDMARK_FALLBACK := {"parking_garage": "parking_a"}

## {def_id, role ("landmark" | "building" | "filler"), lot_id, lot_ids: Array[int], landmark,
##  xform: Transform3D (origin on the ground, front = -Z), zone, district}
var placements: Array[Dictionary] = []
var usage: Dictionary = {}                 ## def id -> times placed
var empty_lots: Array[Dictionary] = []     ## {lot_id, reason}
var merged_units := 0
var notes: PackedStringArray = []

var _cat: RefCounted                       ## BuildingCatalog
var _cands: Dictionary = {}                ## zone -> Array[Dictionary]
var _rng := RandomNumberGenerator.new()


func plan(lots: Array, catalog: RefCounted) -> void:
	_cat = catalog
	placements.clear()
	usage.clear()
	empty_lots.clear()
	merged_units = 0
	for zone: String in ZONE_CANDIDATES:
		_cands[zone] = _candidates(zone)
	# 1) landmarks first (their usage counts against generic copies, e.g. the airport hangar)
	var runs: Dictionary = {}
	var run_order: Array[String] = []
	for lot: Dictionary in lots:
		var lm := String(lot.get("landmark", ""))
		if lm != "":
			_place_landmark(lot, lm)
			continue
		var zone := String(lot.get("zone", ""))
		if not _cands.has(zone):
			continue                                    # park / plaza / parking: drawn by WORLD
		var key := "%s|%s|%s" % [lot.get("block", ""), lot.get("row", ""), zone]
		if not runs.has(key):
			runs[key] = []
			run_order.append(key)
		(runs[key] as Array).append(lot)
	# 2) generic rows
	for key in run_order:
		for run: Array in _split_runs(runs[key]):
			_fill_run(run, key)


# ---------------------------------------------------------------------------------------------
# landmarks
# ---------------------------------------------------------------------------------------------

func _place_landmark(lot: Dictionary, lm: String) -> void:
	var d: Dictionary = _cat.call("find_landmark", lm)
	if d.is_empty() and LANDMARK_FALLBACK.has(lm):
		d = _cat.call("get_def", LANDMARK_FALLBACK[lm])
	if d.is_empty():
		empty_lots.append({"lot_id": int(lot["id"]), "reason": "no building for landmark '%s'" % lm})
		return
	var size: Vector2 = lot["size"]
	var fp: Vector2 = d["fp"]
	if fp.x > size.x + 0.05 or fp.y > size.y + 0.05:
		notes.append("landmark %s: footprint %.1f x %.1f exceeds its lot %.1f x %.1f" % [lm, fp.x, fp.y, size.x, size.y])
	var c: Vector3 = lot["center"]
	var yaw := float(lot["yaw"])
	placements.append({"def_id": String(d["id"]), "role": "landmark", "lot_id": int(lot["id"]), "lot_ids": [int(lot["id"])],
			"landmark": lm, "xform": Transform3D(Basis(Vector3.UP, yaw), c), "zone": String(lot["zone"]),
			"district": String(lot.get("district", ""))})
	usage[String(d["id"])] = int(usage.get(String(d["id"]), 0)) + 1


# ---------------------------------------------------------------------------------------------
# generic rows
# ---------------------------------------------------------------------------------------------

func _candidates(zone: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for rule: String in ZONE_CANDIDATES[zone]:
		var list: Array[Dictionary] = []
		if rule.begins_with("cat:"):
			list = _cat.call("by_category", rule.substr(4))
		elif rule.begins_with("tag:"):
			list = _cat.call("by_tag", rule.substr(4))
		for d in list:
			var id := String(d["id"])
			if seen.has(id) or FILLER_IDS.has(id):
				continue
			seen[id] = true
			out.append(d)
	return out


## Lots of one block row sorted along the street and cut where they are not contiguous.
func _split_runs(lots: Array) -> Array:
	if lots.is_empty():
		return []
	var l0: Dictionary = lots[0]
	var ax := _axis(float(l0["yaw"]))
	var c0: Vector3 = l0["center"]
	var keyed: Array = []
	for lot: Dictionary in lots:
		var c: Vector3 = lot["center"]
		keyed.append([(c - c0).dot(ax), lot])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array = []
	var cur: Array = []
	var last_end := -INF
	for k: Array in keyed:
		var lot: Dictionary = k[1]
		var w: float = (lot["size"] as Vector2).x
		var s0 := float(k[0]) - w * 0.5
		if not cur.is_empty() and s0 - last_end > CONTIGUOUS:
			out.append(cur)
			cur = []
		cur.append(lot)
		last_end = float(k[0]) + w * 0.5
	if not cur.is_empty():
		out.append(cur)
	return out


func _fill_run(run: Array, key: String) -> void:
	_rng.seed = hash([SEED, key, int((run[0] as Dictionary)["id"])])
	var zone := String((run[0] as Dictionary)["zone"])
	var prev := ""
	var i := 0
	while i < run.size():
		var lot: Dictionary = run[i]
		var a := _best_unit([lot], zone, prev)
		var take_pair := false
		var b := {}
		if i + 1 < run.size() and MERGE_ZONES.has(zone):
			b = _best_unit([lot, run[i + 1]], zone, prev)
			if not b.is_empty():
				var a_val := float(a.get("score", -100.0))
				# the next lot's neighbour is the LAST main building of option a (items may be reversed)
				var a_last := _last_main(a, prev) if not a.is_empty() else prev
				var nxt := _best_unit([run[i + 1]], zone, a_last)
				a_val += float(nxt.get("score", -100.0))
				take_pair = float(b["score"]) > a_val
		if take_pair:
			_commit([lot, run[i + 1]], b, zone)
			merged_units += 1
			prev = _last_main(b, prev)
			i += 2
		else:
			if a.is_empty():
				var f := _filler_only([lot], zone)
				if f.is_empty():
					empty_lots.append({"lot_id": int(lot["id"]), "reason": "nothing fits %.1f x %.1f" % [(lot["size"] as Vector2).x, (lot["size"] as Vector2).y]})
				else:
					_commit([lot], f, zone)
			else:
				_commit([lot], a, zone)
				prev = _last_main(a, prev)
			i += 1


func _last_main(opt: Dictionary, prev: String) -> String:
	var out := prev
	for it: Array in opt["items"]:
		if not bool(it[2]):
			out = String((it[0] as Dictionary)["id"])
	return out


## Full width of a building along the street (footprint + side overhangs).
static func _width(d: Dictionary) -> float:
	var ov: Dictionary = d["ov"]
	return (d["fp"] as Vector2).x + float(ov["left"]) + float(ov["right"])


## Full depth (footprint + front / back overhang).
static func _depth(d: Dictionary) -> float:
	var ov: Dictionary = d["ov"]
	return (d["fp"] as Vector2).y + float(ov["front"]) + float(ov["back"])


func _fits_depth(d: Dictionary, depth: float) -> bool:
	return _depth(d) <= depth + DEPTH_TOL


## Best option for a unit made of `unit` lots: {score, items: [[def, along_centre, is_filler]], width}
## or {} if no main building fits. along_centre = centre of the building's full width, measured from
## the unit's start edge.
func _best_unit(unit: Array, zone: String, prev: String) -> Dictionary:
	var W := 0.0
	var D := INF
	for lot: Dictionary in unit:
		W += (lot["size"] as Vector2).x
		D = minf(D, (lot["size"] as Vector2).y)
	var district := String((unit[0] as Dictionary).get("district", ""))
	var cands: Array[Dictionary] = _cands[zone]
	var avail := W - 2.0 * EDGE
	var best := {}
	var best_score := -INF
	var fits: Array[Dictionary] = []
	for d in cands:
		if _width(d) <= avail and _fits_depth(d, D):
			fits.append(d)
	for d in fits:
		var items: Array = [[d, 0.0, false]]
		var s := _score(items, W, zone, district, prev)
		if s > best_score:
			best_score = s
			best = {"score": s, "items": items}
	if unit.size() > 1 or W >= 26.0:
		for i in fits.size():
			for j in fits.size():
				var d1: Dictionary = fits[i]
				var d2: Dictionary = fits[j]
				if d1["id"] == d2["id"] or _width(d1) + _width(d2) + GAP > avail:
					continue
				var items: Array = [[d1, 0.0, false], [d2, 0.0, false]]
				var s := _score(items, W, zone, district, prev)
				if s > best_score:
					best_score = s
					best = {"score": s, "items": items}
	if best.is_empty():
		return {}
	_layout(best, W, D, zone, prev)
	best["W"] = W
	best["D"] = D
	return best


func _score(items: Array, W: float, zone: String, district: String, prev: String) -> float:
	var used := 0.0
	var s := 0.0
	var prev_id := prev
	for it: Array in items:
		var d: Dictionary = it[0]
		var id := String(d["id"])
		used += _width(d)
		var n := int(usage.get(id, 0))
		s += 1.6 if n == 0 else -0.5 * float(n)
		var tags: Array = d["tags"]
		if tags.has(district):
			s += 0.45
		if zone == "hangar" and tags.has("hangar"):
			s += 2.5
		if district == "downtown" and tags.has("tall"):
			s += 0.35
		if id == prev_id:
			s -= 6.0
		prev_id = id
	s += 4.0 * used / W
	if zone == "house":
		s -= 2.0 * maxf(used / W - 0.9, 0.0)           # houses keep a little side yard
	return s + _rng.randf() * 0.6


## Positions the items of an option along the unit and adds a filler where one fits.
func _layout(opt: Dictionary, W: float, D: float, zone: String, prev: String) -> void:
	var items: Array = opt["items"]
	# random order for variety, but never the previous neighbour's building first
	if items.size() == 2 and _rng.randf() < 0.5 and String((items[1][0] as Dictionary)["id"]) != prev:
		items.reverse()
	var total := 0.0
	for it: Array in items:
		total += _width(it[0])
	total += GAP * float(items.size() - 1)
	var left := W - 2.0 * EDGE - total
	var filler: Dictionary = {}
	if zone != "house" and left > 0.0:
		for fid: String in ZONE_FILLERS.get(zone, []):
			var f: Dictionary = _cat.call("get_def", fid)
			if f.is_empty() or not _fits_depth(f, D):
				continue
			if _width(f) + GAP + 0.6 <= left and _rng.randf() < 0.6:
				filler = f
				break
	var start := EDGE + left * 0.5
	var filler_first := false
	if not filler.is_empty():
		filler_first = _rng.randf() < 0.5
		start = EDGE if not filler_first else W - EDGE - total
	var cur := start
	for it: Array in items:
		var w := _width(it[0])
		it[1] = cur + w * 0.5
		cur += w + GAP
	if not filler.is_empty():
		var fw := _width(filler)
		var free0 := start + total if not filler_first else EDGE
		var free1 := W - EDGE if not filler_first else start
		items.append([filler, (free0 + free1) * 0.5, true])
	elif zone == "house":
		# back-yard shed when the lot is deep enough behind the house
		var shed: Dictionary = _cat.call("get_def", "shed_a")
		if not shed.is_empty() and _rng.randf() < 0.6:
			var house: Dictionary = items[0][0]
			var back_room := D - _setback(zone, D, _depth(house)) - _depth(house)
			if back_room >= _depth(shed) + 1.6:
				var sw := _width(shed)
				var along: float = EDGE + sw * 0.5 + 0.6 if _rng.randf() < 0.5 else W - EDGE - sw * 0.5 - 0.6
				items.append([shed, along, true, "back"])


## Distance from the lot front edge to the front of the building (incl. its front overhang).
static func _setback(zone: String, D: float, depth: float) -> float:
	var room := D - depth
	var s := 0.25
	match zone:
		"apartment":
			s = clampf(room * 0.25, 0.5, 2.5)
		"house":
			s = clampf(room * 0.55, 2.0, 6.0)
		"warehouse", "hangar":
			s = clampf(room * 0.5, 0.5, 7.0)
	return maxf(minf(s, room + DEPTH_TOL), 0.0)


## Option with just a small filler (lots too small for any main building): a paved yard with a kiosk,
## shed or garage row.
func _filler_only(unit: Array, zone: String) -> Dictionary:
	var lot: Dictionary = unit[0]
	var size: Vector2 = lot["size"]
	for fid: String in ZONE_FILLERS.get(zone, FILLER_IDS):
		var f: Dictionary = _cat.call("get_def", fid)
		if f.is_empty():
			continue
		if _width(f) <= size.x - 2.0 * EDGE and _fits_depth(f, size.y):
			return {"score": 0.0, "items": [[f, size.x * 0.5, true]], "W": size.x, "D": size.y}
	return {}


## Turns an option into placements (world transforms) on the lots of the unit.
func _commit(unit: Array, opt: Dictionary, zone: String) -> void:
	var l0: Dictionary = unit[0]
	var yaw := float(l0["yaw"])
	var ax := _axis(yaw)
	var back := Vector3(sin(yaw), 0.0, cos(yaw))               # lot local +Z (away from the street)
	var c0: Vector3 = l0["center"]
	var size0: Vector2 = l0["size"]
	var start := c0 - ax * (size0.x * 0.5)                     # unit start edge, on the lot centre line
	var D := float(opt.get("D", size0.y))
	var lot_ids: Array[int] = []
	for lot: Dictionary in unit:
		lot_ids.append(int(lot["id"]))
	for it: Array in opt["items"]:
		var d: Dictionary = it[0]
		var along := float(it[1])
		var is_filler := bool(it[2])
		var at_back := it.size() > 3 and String(it[3]) == "back"
		var ov: Dictionary = d["ov"]
		var fp: Vector2 = d["fp"]
		var co: Vector2 = d["co"]
		var depth := _depth(d)
		# building-local footprint centre along X: co.x, the full width is offset by (right - left) / 2
		var origin_along := along - (float(ov["right"]) - float(ov["left"])) * 0.5 - co.x
		var front_z: float                                     # lot-local z of the building's front-most point
		if at_back:
			front_z = D * 0.5 - 0.6 - depth
		else:
			front_z = -D * 0.5 + _setback(zone, D, depth)
		# front-most point = origin_z + co.y - fp.y / 2 - ov.front
		var origin_z := front_z - co.y + fp.y * 0.5 + float(ov["front"])
		var p := start + ax * origin_along + back * origin_z
		p.y = c0.y
		# the lot whose span contains the building centre
		var lot_id := lot_ids[0]
		var acc := 0.0
		for lot: Dictionary in unit:
			var w: float = (lot["size"] as Vector2).x
			if along >= acc and along <= acc + w:
				lot_id = int(lot["id"])
			acc += w
		var role := "filler" if is_filler else "building"
		placements.append({"def_id": String(d["id"]), "role": role, "lot_id": lot_id, "lot_ids": lot_ids.duplicate(),
				"landmark": "", "xform": Transform3D(Basis(Vector3.UP, yaw), p), "zone": zone,
				"district": String(l0.get("district", ""))})
		usage[String(d["id"])] = int(usage.get(String(d["id"]), 0)) + 1


static func _axis(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))
