extends RefCounted
## PropSystem placer: street furniture along the road graph (WORLD DRESSING).
##
## Sidewalk cross-section used everywhere here (WORLD.md): carriageway half width hw, kerb at hw,
## 3 m sidewalk hw .. hw + 3. Furniture lives in the KERB STRIP hw + 0.25 .. hw + 1.0 (lamps,
## signs, meters, hydrants, boxes); the WALKING STRIP hw + 1.0 .. hw + 3.0 stays free (>= 1.5 m
## everywhere except at the four world bus-stop shelters, see docs/DRESSING.md). Nothing is placed
## within 6 m of a junction box (crosswalk landings) or along the frontage of landmark, parking and
## plaza lots (entrances, kerb ramps, driveways).

const SIDEWALK_W := 3.0
const STOP_SETBACK := 4.2
const C_RED := Color(1.0, 0.13, 0.08)
const C_YELLOW := Color(1.0, 0.68, 0.08)
const C_GREEN := Color(0.15, 1.0, 0.45)
const C_WALK := Color(0.85, 0.95, 1.0)
const C_STOP := Color(1.0, 0.35, 0.1)

var sys: Node
var roads: Object
var world: Node
var rng := RandomNumberGenerator.new()
var _no_kerb: Array[Dictionary] = []     ## lots whose frontage stays clear
var _lots: Array = []
var _buildings: Array = []


func run(s: Node) -> void:
	sys = s
	roads = s.get("roads")
	world = s.get("world")
	rng.seed = 520117
	if roads == null:
		return
	_lots = world.call("get_lots") if world.has_method("get_lots") else []
	for lot: Dictionary in _lots:
		var z := String(lot.get("zone", ""))
		if String(lot.get("landmark", "")) != "" or z == "parking" or z == "plaza" or z == "park":
			_no_kerb.append(lot)
	var city := Game.get_system("city")
	if city != null and city.has_method("get_buildings"):
		_buildings = city.call("get_buildings")
	_reserve_points()
	sys.call("mark_phase", "street.reserve_points")
	_traffic_lights()
	sys.call("mark_phase", "street.traffic_lights")
	_ped_signals()
	sys.call("mark_phase", "street.ped_signals")
	_street_lamps()
	sys.call("mark_phase", "street.street_lamps")
	_world_furniture()
	sys.call("mark_phase", "street.world_furniture")
	_street_trees()
	sys.call("mark_phase", "street.street_trees")
	_junction_furniture()
	sys.call("mark_phase", "street.junction_furniture")
	_kerb_furniture()
	sys.call("mark_phase", "street.kerb_furniture")
	_drains_manholes()
	sys.call("mark_phase", "street.drains_manholes")
	_guardrails()
	sys.call("mark_phase", "street.guardrails")
	_lot_edges()
	sys.call("mark_phase", "street.lot_edges")
	_alleys()
	sys.call("mark_phase", "street.alleys")
	_billboards()
	sys.call("mark_phase", "street.billboards")
	_power_line()
	sys.call("mark_phase", "street.power_line")


# ---------------------------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------------------------

static func pt(p: PackedVector2Array, dist: float) -> Vector2:
	var acc := 0.0
	for i in range(1, p.size()):
		var l := p[i].distance_to(p[i - 1])
		if acc + l >= dist and l > 0.0001:
			return p[i - 1].lerp(p[i], clampf((dist - acc) / l, 0.0, 1.0))
		acc += l
	return p[p.size() - 1]


static func dir_at(p: PackedVector2Array, dist: float) -> Vector2:
	var acc := 0.0
	for i in range(1, p.size()):
		var l := p[i].distance_to(p[i - 1])
		if acc + l >= dist and l > 0.0001:
			return (p[i] - p[i - 1]) / l
		acc += l
	var n := p.size()
	return (p[n - 1] - p[n - 2]).normalized()


static func right_of(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


static func yaw_of(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


func xf_at(q: Vector2, facing: Vector2, y: float = INF) -> Transform3D:
	var h := y if y != INF else float(sys.call("ground", q.x, q.y))
	return Transform3D(Basis(Vector3.UP, yaw_of(facing)), Vector3(q.x, h, q.y))


static func in_lot(lot: Dictionary, p: Vector3, margin: float) -> bool:
	var c: Vector3 = lot["center"]
	var s: Vector2 = lot["size"]
	var yaw := float(lot["yaw"])
	var dx := p.x - c.x
	var dz := p.z - c.z
	var lx := dx * cos(yaw) - dz * sin(yaw)
	var lz := dx * sin(yaw) + dz * cos(yaw)
	return absf(lx) <= s.x * 0.5 + margin and absf(lz) <= s.y * 0.5 + margin


func kerb_ok(p: Vector3) -> bool:
	for lot: Dictionary in _no_kerb:
		if in_lot(lot, p, 6.5):
			return false
	return true


## Distance from p to the nearest building box (2D), INF without building data.
func building_clearance(p: Vector3) -> float:
	var best := INF
	for b: Dictionary in _buildings:
		var xf: Transform3D = b.get("transform", Transform3D.IDENTITY)
		var fp: Vector2 = b.get("footprint", Vector2.ZERO)
		var lp := xf.affine_inverse() * p
		var dx := maxf(absf(lp.x) - fp.x * 0.5, 0.0)
		var dz := maxf(absf(lp.z) - fp.y * 0.5, 0.0)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best


func place(id: String, xf: Transform3D, opts: Dictionary = {}) -> int:
	return int(sys.call("place", id, xf, opts))


## Sidewalk spans of a segment side: [s0, s1] or [] (side = +1 right, -1 left of pts2 order).
static func span_of(seg: Dictionary, side: float) -> Array:
	var sp: Array = seg["sw_r_span"] if side > 0.0 else seg["sw_l_span"]
	if sp.is_empty():
		return []
	return [float(sp[0]), float(sp[1])]


func _reserve_points() -> void:
	# named locations and gameplay points stay clear of dressing
	if world.has_method("get_locations"):
		var locs: Dictionary = world.call("get_locations")
		for k: String in locs:
			sys.call("reserve", (locs[k] as Transform3D).origin, 1.6)
	for kind: String in ["pickup_weapon", "pickup_health", "pickup_armor", "pickup_cash", "parachute", "ladder",
			"gang", "police_car", "taxi", "heli", "plane"]:
		for x: Transform3D in sys.call("spawn_points", kind):
			sys.call("reserve", x.origin, 1.4 if kind != "plane" and kind != "heli" else 8.0)
	for x: Transform3D in sys.call("spawn_points", "parking"):
		sys.call("reserve", x.origin, 1.2)


# ---------------------------------------------------------------------------------------------
# signals
# ---------------------------------------------------------------------------------------------

func _traffic_lights() -> void:
	if not world.has_method("get_signal_heads"):
		return
	var parts := {}
	for pn: String in ["Lamp_Red", "Lamp_Yellow", "Lamp_Green"]:
		parts[pn] = sys.get("catalog").call("part", "traffic_light", pn)
	var mats := [sys.call("lens_material", C_RED), sys.call("lens_material", C_YELLOW), sys.call("lens_material", C_GREEN)]
	for head: Dictionary in world.call("get_signal_heads"):
		var xf: Transform3D = head["transform"]
		var lanes: PackedInt32Array = head["lane_ids"]
		if lanes.is_empty():
			continue
		var i := place("traffic_light", xf, {"r": 0.4, "tag": "signal"})
		if i < 0:
			continue
		var lens: Array = []
		var k := 0
		for pn: String in ["Lamp_Red", "Lamp_Yellow", "Lamp_Green"]:
			var pv: Dictionary = parts[pn]
			if pv.is_empty():
				lens.append(PackedInt32Array())
			else:
				lens.append(sys.call("add_extra_slot", i, "traffic_light|" + pn, pv, xf,
						{"custom": true, "material": mats[k], "shadow": false, "cell": 300.0}))
			k += 1
		sys.call("add_signal_head", i, lanes[0], int(head["intersection_id"]), lens)


func _ped_signals() -> void:
	var cat: RefCounted = sys.get("catalog")
	var p_stop: Dictionary = cat.call("part", "traffic_light_ped", "Lamp_Stop")
	var p_walk: Dictionary = cat.call("part", "traffic_light_ped", "Lamp_Walk")
	if p_stop.is_empty() or p_walk.is_empty():
		return
	var m_stop: Material = sys.call("lens_material", C_STOP)
	var m_walk: Material = sys.call("lens_material", C_WALK)
	for node: Dictionary in roads.get("intersections"):
		if not node["has_signal"]:
			continue
		var c3: Vector3 = node["position"]
		var c := Vector2(c3.x, c3.z)
		for l: Dictionary in node["legs"]:
			if not bool(l["crosswalk"]):
				continue
			var lanes: PackedInt32Array = l["lanes_in"]
			if lanes.is_empty():
				continue
			var d: Vector2 = l["dir"]
			var r := right_of(d)
			var hw := float(l["hw"])
			var along := float(l["trim"]) + 0.45
			for side: float in [1.0, -1.0]:
				# 1.3 m behind the kerb: the pole of the neighbouring crosswalk at the same corner
				# stands 1.2 m away instead of on the same spot
				var q := c + d * along + r * side * (hw + 1.3)
				var xf := xf_at(q, -r * side)
				var i := place("traffic_light_ped", xf, {"r": 0.3, "tag": "signal"})
				if i < 0:
					continue
				var ls: PackedInt32Array = sys.call("add_extra_slot", i, "traffic_light_ped|stop", p_stop, xf,
						{"custom": true, "material": m_stop, "shadow": false, "cell": 300.0})
				var lw: PackedInt32Array = sys.call("add_extra_slot", i, "traffic_light_ped|walk", p_walk, xf,
						{"custom": true, "material": m_walk, "shadow": false, "cell": 300.0})
				sys.call("add_ped_signal", i, lanes[0], [ls, lw])


# ---------------------------------------------------------------------------------------------
# lamps, world furniture points
# ---------------------------------------------------------------------------------------------

func _street_lamps() -> void:
	var mk: Variant = sys.get("catalog").call("marker", "street_lamp_a", "Light")
	var local: Transform3D = mk if mk != null else Transform3D(Basis.IDENTITY, Vector3(0, 8.4, -3.2))
	for xf: Transform3D in sys.call("spawn_points", "street_light"):
		var i := place("street_lamp_a", xf, {"r": 0.4, "tag": "lamp"})
		if i >= 0:
			sys.call("add_lamp_light", i, local, Color(1.0, 0.8, 0.52), 21.0, 6.0)


func _world_furniture() -> void:
	for xf: Transform3D in sys.call("spawn_points", "hydrant"):
		place("hydrant", xf, {"r": 0.35, "tag": "furniture"})
	for xf: Transform3D in sys.call("spawn_points", "bin"):
		place("bin", xf, {"r": 0.4, "tag": "furniture"})
	for xf: Transform3D in sys.call("spawn_points", "bus_stop"):
		# shelter pulled to the kerb (front edge ~0.15 m behind it) to leave the most room behind it
		var fwd := -xf.basis.z.normalized()
		var x2 := Transform3D(xf.basis, xf.origin + fwd * 0.45)
		place("bus_stop", x2, {"r": 1.6, "tag": "furniture"})
	for xf: Transform3D in sys.call("spawn_points", "bench"):
		var p := xf.origin
		var skip := false
		for lot: Dictionary in _lots:
			if String(lot.get("landmark", "")).begins_with("tram_stop") and in_lot(lot, p, 0.5):
				skip = true      # the tram stop landmark brings its own seating
				break
		if skip:
			continue
		var dist := String(world.call("get_district", p))
		var id := "bench_park" if dist in ["hill", "beach", "residential", "waterfront"] else "bench"
		place(id, xf, {"r": 0.9, "tag": "furniture"})


func _street_trees() -> void:
	for xf: Transform3D in sys.call("spawn_points", "tree_street"):
		var p := xf.origin
		var dist := String(world.call("get_district", p))
		var id := "tree_small_a"
		if dist == "waterfront" or dist == "beach":
			id = "palm_b"
		elif dist == "residential":
			id = "tree_broadleaf_c" if rng.randf() < 0.6 else "tree_small_a"
		var x2 := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		if place(id, x2, {"r": 0.7, "tag": "tree_street", "lod": false}) >= 0:
			place("tree_grate", Transform3D(xf.basis.orthonormalized(), p + Vector3(0, 0.002, 0)), {"no_occ": true, "tag": "furniture"})


# ---------------------------------------------------------------------------------------------
# junctions: stop / yield signs, controller boxes, street-name signs
# ---------------------------------------------------------------------------------------------

func _junction_furniture() -> void:
	for node: Dictionary in roads.get("intersections"):
		var c3: Vector3 = node["position"]
		var c := Vector2(c3.x, c3.z)
		var legs: Array = node["legs"]
		if legs.size() < 3:
			continue
		if node["has_signal"]:
			var corners: Array = node["corners"]
			for k in corners.size():
				var cn: Dictionary = corners[k]
				var da: Vector2 = cn["da"]
				var db: Vector2 = cn["db"]
				var diag := (da + db).normalized()
				var q: Vector2 = cn["c"]
				if k % 4 == 1:
					# signal controller cabinet in the kerb strip beyond the crosswalk and the signal pole
					var qq := q + da * 5.6 + db * 0.6
					place("utility_box", xf_at(qq, -db), {"r": 0.7, "tag": "furniture"})
				elif k % 4 == 3:
					place("sign_street", xf_at(q + diag * 1.6, -diag), {"r": 0.45, "tag": "sign"})
			continue
		# priority junction: stop / yield signs on the minor approaches that have a kerb
		for l: Dictionary in legs:
			var lanes: PackedInt32Array = l["lanes_in"]
			if lanes.is_empty():
				continue
			var lane: Dictionary = roads.get("lanes")[lanes[0]]
			if not bool(lane.get("yield", false)):
				continue
			if not bool(l["sw_ccw"]):
				continue
			var d: Vector2 = l["dir"]
			var r_app := right_of(-d)
			var q := c + d * (float(l["trim"]) + STOP_SETBACK + 0.4) + r_app * (float(l["hw"]) + 0.45)
			var id := "sign_stop" if String(l["kind"]) == "street" else "sign_yield"
			place(id, xf_at(q, d), {"r": 0.35, "tag": "sign"})


# ---------------------------------------------------------------------------------------------
# kerb strip: meters, speed / parking signs, news boxes, mailboxes, planters, bike racks
# ---------------------------------------------------------------------------------------------

func _kerb_furniture() -> void:
	for seg: Dictionary in roads.get("segments"):
		var kind := String(seg["kind"])
		if kind != "street" and kind != "arterial":
			continue
		var p2: PackedVector2Array = seg["pts2"]
		var hw := float(seg["hw"])
		var length := float(seg["length"])
		var parking := bool(seg.get("parking", false))
		for side: float in [1.0, -1.0]:
			var sp := span_of(seg, side)
			if sp.is_empty():
				continue
			var s0: float = sp[0] + 7.0
			var s1: float = sp[1] - 7.0
			if s1 - s0 < 8.0:
				continue
			var mid := pt(p2, (s0 + s1) * 0.5)
			var dist := String(world.call("get_district", Vector3(mid.x, 2.6, mid.y)))
			# speed limit sign for the traffic on this side (right-hand traffic: right side = forward)
			var s_sign := s0 + 2.0 if side > 0.0 else s1 - 2.0
			_kerb_item("sign_speed", p2, s_sign, side, hw + 0.45, "traffic", "sign")
			if parking:
				var first := true
				var s := s0 + 3.0
				while s < s1 - 2.0:
					if first:
						_kerb_item("sign_parking", p2, s, side, hw + 0.45, "traffic", "sign")
						first = false
					else:
						_kerb_item("parking_meter", p2, s, side, hw + 0.42, "walk", "furniture")
					s += 13.0
			if dist == "downtown" or dist == "midtown":
				var n_items := ["newspaper_box", "mailbox", "planter", "bike_rack", "newspaper_box", "planter"]
				var s2 := s0 + 9.5
				var k := int(rng.randi() % n_items.size())
				while s2 < s1 - 3.0:
					var id: String = n_items[k % n_items.size()]
					if id == "planter" and dist != "downtown":
						id = "mailbox"
					var lat := hw + (0.62 if id == "planter" else (0.5 if id == "bike_rack" else 0.45))
					_kerb_item(id, p2, s2, side, lat, "road" if id == "bike_rack" else "walk", "furniture")
					k += 1
					s2 += 19.0 + rng.randf() * 8.0
			elif dist == "residential" or dist == "industrial":
				if rng.randf() < 0.55:
					_kerb_item("utility_box", p2, lerpf(s0, s1, rng.randf_range(0.3, 0.7)), side, hw + 0.6, "road", "furniture")
			elif dist == "waterfront" or dist == "beach":
				if rng.randf() < 0.5:
					_kerb_item("newspaper_box", p2, lerpf(s0, s1, rng.randf_range(0.25, 0.75)), side, hw + 0.45, "walk", "furniture")


## One kerb-strip item at arc length s, lateral offset `lat` on `side`. mode: "road" faces the
## carriageway (long axis along the kerb), "walk" faces the sidewalk, "traffic" faces the drivers
## approaching on that side (signs), slightly turned toward the road.
func _kerb_item(id: String, p2: PackedVector2Array, s: float, side: float, lat: float, mode: String,
		tag: String) -> int:
	var d := dir_at(p2, s)
	var r := right_of(d) * side
	var q := pt(p2, s) + r * lat
	var p := Vector3(q.x, 0.0, q.y)
	if not kerb_ok(p):
		return -1
	var facing := -r
	if mode == "walk":
		facing = r
	elif mode == "traffic":
		facing = (-d * side - r * 0.18).normalized()
	return place(id, xf_at(q, facing), {"tag": tag})


# ---------------------------------------------------------------------------------------------
# drains (gutter) and manholes (lanes): flush plates, no collision
# ---------------------------------------------------------------------------------------------

func _drains_manholes() -> void:
	for seg: Dictionary in roads.get("segments"):
		var kind := String(seg["kind"])
		if kind != "street" and kind != "arterial":
			continue
		var p2: PackedVector2Array = seg["pts2"]
		var hw := float(seg["hw"])
		var length := float(seg["length"])
		var a0 := float(seg["trim_a"]) + 7.0
		var a1 := length - float(seg["trim_b"]) - 7.0
		if a1 - a0 < 10.0:
			continue
		for side: float in [1.0, -1.0]:
			if span_of(seg, side).is_empty():
				continue
			var s := a0 + 4.0 + rng.randf() * 6.0
			while s < a1:
				var d := dir_at(p2, s)
				var r := right_of(d) * side
				var q := pt(p2, s) + r * (hw - 0.32)
				var y := float(sys.call("ground", q.x, q.y))
				place("drain", Transform3D(Basis(Vector3.UP, yaw_of(-r)), Vector3(q.x, y + 0.004, q.y)),
						{"no_occ": true, "road_ok": true, "tag": "road"})
				s += 34.0
		# manholes in the lanes
		var lane_off := 1.75 if kind == "street" else 3.75
		var sm := a0 + rng.randf() * 20.0
		var flip := 1.0
		while sm < a1:
			var d2 := dir_at(p2, sm)
			var q2 := pt(p2, sm) + right_of(d2) * (lane_off * flip)
			var y2 := float(sys.call("ground", q2.x, q2.y))
			place("manhole", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q2.x, y2 + 0.003, q2.y)),
					{"no_occ": true, "road_ok": true, "tag": "road"})
			sm += 45.0 + rng.randf() * 25.0
			flip = -flip


# ---------------------------------------------------------------------------------------------
# guard rails: arterial stretches with an embankment / natural ground behind the sidewalk
# ---------------------------------------------------------------------------------------------

func _guardrails() -> void:
	var walk: Object = world.get("walk")
	for seg: Dictionary in roads.get("segments"):
		var kind := String(seg["kind"])
		if kind != "arterial" and kind != "dirt":
			continue
		var p2: PackedVector2Array = seg["pts2"]
		var hw := float(seg["hw"])
		var length := float(seg["length"])
		for side: float in [1.0, -1.0]:
			var lat := hw + 0.7
			var s0 := 12.0
			var s1 := length - 12.0
			if kind == "arterial":
				var sp := span_of(seg, side)
				if sp.is_empty():
					continue
				lat = hw + SIDEWALK_W + 0.3
				s0 = float(sp[0]) + 14.0
				s1 = float(sp[1]) - 14.0
			var s := s0
			var run := 0
			while s + 2.0 < s1:
				var d := dir_at(p2, s)
				var r := right_of(d) * side
				var q := pt(p2, s) + r * lat
				var beyond := pt(p2, s) + r * (lat + 3.5)
				var surf := String(sys.call("surface_at", beyond.x, beyond.y))
				var y := float(sys.call("ground", q.x, q.y))
				var yb := float(sys.call("ground", beyond.x, beyond.y))
				if kind == "arterial":
					# the ring road: measure the fall over 9 m (the plateau edge falls gently to the coast)
					var far := pt(p2, s) + r * (lat + 9.0)
					yb = minf(yb, float(sys.call("ground", far.x, far.y)))
				# a rail where the ground falls away beside the road (embankment / hill side) or, on the ring
				# road, on the outside of its rounded bends next to open ground
				var natural := surf == "grass" or surf == "sand" or surf == "dirt" or surf == "water"
				if natural and kind == "arterial":
					var bp := Vector3(beyond.x, 0.0, beyond.y)
					for lot: Dictionary in _lots:
						if in_lot(lot, bp, 0.5):
							natural = false       # a lawn yard / park behind the sidewalk, not open ground
							break
				var ok := natural and y - yb > (0.6 if kind == "arterial" else 0.9)
				if not ok and natural and kind == "arterial":
					var d0 := dir_at(p2, maxf(s - 5.0, 0.0))
					var d1 := dir_at(p2, minf(s + 5.0, length))
					var turn := right_of(d0).dot(d1)          # > 0: the road bends toward its right side
					ok = absf(turn) > 0.06 and signf(turn) == -side
				if ok and walk != null:
					var np: Vector3 = walk.call("get_nearest_point", Vector3(q.x, y, q.y))
					if np != Vector3.INF and Vector2(np.x, np.z).distance_to(q) < 0.9:
						ok = false     # a path runs (or crosses) right here: keep the gap
				if ok and bool(sys.call("on_carriageway", Vector3(q.x, y, q.y), 0.0)):
					ok = false
				if ok:
					var gy := minf(y, float(sys.call("ground", q.x + r.x * 0.3, q.y + r.y * 0.3)))
					if place("guardrail", Transform3D(Basis(Vector3.UP, yaw_of(-r)), Vector3(q.x, gy, q.y)),
							{"no_occ": true, "tag": "road"}) >= 0:
						run += 1
				s += 4.0


# ---------------------------------------------------------------------------------------------
# lot edges: hedges / timber fences around house yards, chain-link around industrial yards
# ---------------------------------------------------------------------------------------------

func _lot_edges() -> void:
	var have_buildings := not _buildings.is_empty()
	var seen := {}
	for lot: Dictionary in _lots:
		var zone := String(lot.get("zone", ""))
		var district := String(lot.get("district", ""))
		if String(lot.get("landmark", "")) != "":
			continue
		var id := ""
		if zone == "house":
			id = "hedge" if int(lot["id"]) % 3 == 0 else ("fence_wood" if int(lot["id"]) % 3 == 1 else "wall_low")
		elif zone == "warehouse" and district == "industrial" and have_buildings:
			id = "fence_chainlink"
		else:
			continue
		var c: Vector3 = lot["center"]
		var size: Vector2 = lot["size"]
		var yaw := float(lot["yaw"])
		var basis := Basis(Vector3.UP, yaw)
		var hx := size.x * 0.5
		var hz := size.y * 0.5
		# back edge (local +z) and both sides (local +-x), front (local -z) stays open
		var edges: Array = [
			[Vector3(-hx, 0, hz), Vector3(hx, 0, hz)],
			[Vector3(hx, 0, hz), Vector3(hx, 0, -hz + 1.5)],
			[Vector3(-hx, 0, -hz + 1.5), Vector3(-hx, 0, hz)],
		]
		for e: Array in edges:
			var a: Vector3 = c + basis * (e[0] as Vector3)
			var b: Vector3 = c + basis * (e[1] as Vector3)
			_fence_run(id, a, b, seen)


func _fence_run(id: String, a: Vector3, b: Vector3, seen: Dictionary) -> void:
	var len := Vector2(b.x - a.x, b.z - a.z).length()
	var n := floori(len / 4.0)
	if n < 1:
		return
	var dir := Vector2(b.x - a.x, b.z - a.z) / len
	var start := (len - n * 4.0) * 0.5
	for k in n:
		var t := start + 2.0 + k * 4.0
		var q := Vector2(a.x, a.z) + dir * t
		var key := Vector2i(roundi(q.x), roundi(q.y))
		if seen.has(key):
			continue
		seen[key] = true
		var p := Vector3(q.x, 0.0, q.y)
		if bool(sys.call("on_carriageway", p, 1.0)):
			continue
		if not _buildings.is_empty() and building_clearance(p) < 0.6:
			continue
		var surf := String(sys.call("surface_at", q.x, q.y))
		if surf == "water":
			continue
		# local X along the run, the "front" (-Z) faces out of the lot (direction does not matter much)
		var facing := right_of(dir)
		var y := float(sys.call("ground", q.x, q.y))
		place(id, Transform3D(Basis(Vector3.UP, yaw_of(facing)), Vector3(q.x, y, q.y)), {"no_occ": true, "tag": "fence"})


# ---------------------------------------------------------------------------------------------
# alleys: dumpsters, bins, bags and boxes against the back walls (needs building data)
# ---------------------------------------------------------------------------------------------

func _alleys() -> void:
	if _buildings.is_empty():
		return
	var sets := [["dumpster", "trash_bags"], ["recycling_bins", "cardboard_boxes"], ["dumpster", "cardboard_boxes"],
			["pallet", "crate_wood"], ["trash_bags", "barrel"], ["dumpster", "trash_bags"]]
	var k := 0
	for seg: Dictionary in roads.get("segments"):
		if String(seg["kind"]) != "alley":
			continue
		var p2: PackedVector2Array = seg["pts2"]
		var hw := float(seg["hw"])
		var length := float(seg["length"])
		var s := float(seg["trim_a"]) + 12.0 + rng.randf() * 8.0
		var side := 1.0
		while s < length - float(seg["trim_b"]) - 12.0:
			var d := dir_at(p2, s)
			var r := right_of(d) * side
			var grp: Array = sets[k % sets.size()]
			var lat := hw + 1.05
			var q := pt(p2, s) + r * lat
			var p := Vector3(q.x, 0.0, q.y)
			var size: Vector3 = (sys.call("get_prop_def", grp[0]) as Dictionary).get("size_v", Vector3.ONE)
			if building_clearance(p) >= size.z * 0.5 + 0.25 and not bool(sys.call("on_carriageway", p, 0.3)):
				if place(grp[0], xf_at(q, -r), {"tag": "furniture" if grp[0] == "dumpster" else "loose"}) >= 0:
					var q2 := q + d * (size.x * 0.5 + 0.9)
					var p2b := Vector3(q2.x, 0.0, q2.y)
					if building_clearance(p2b) >= 0.6:
						place(grp[1], Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q2.x, float(sys.call("ground", q2.x, q2.y)), q2.y)),
								{"tag": "loose"})
			k += 1
			side = -side
			s += 17.0 + rng.randf() * 12.0


# ---------------------------------------------------------------------------------------------
# billboards on open ground beside the ring road
# ---------------------------------------------------------------------------------------------

func _billboards() -> void:
	var placed := 0
	for seg: Dictionary in roads.get("segments"):
		if placed >= 7:
			break
		if String(seg["kind"]) != "arterial":
			continue
		var p2: PackedVector2Array = seg["pts2"]
		var hw := float(seg["hw"])
		var length := float(seg["length"])
		if length < 60.0:
			continue
		for side: float in [1.0, -1.0]:
			var s := length * 0.5
			var d := dir_at(p2, s)
			var r := right_of(d) * side
			var q := pt(p2, s) + r * (hw + SIDEWALK_W + 6.0)
			var p := Vector3(q.x, 0.0, q.y)
			var surf := String(sys.call("surface_at", q.x, q.y))
			if surf != "grass" and surf != "dirt" and surf != "sand":
				continue
			var y0 := float(sys.call("ground", q.x - d.x * 3.0, q.y - d.y * 3.0))
			var y1 := float(sys.call("ground", q.x + d.x * 3.0, q.y + d.y * 3.0))
			var y := float(sys.call("ground", q.x, q.y))
			if absf(y0 - y1) > 0.8 or y < 0.8:
				continue
			if bool(sys.call("on_carriageway", p, 4.0)):
				continue
			if place("billboard", Transform3D(Basis(Vector3.UP, yaw_of(-r)), Vector3(q.x, minf(minf(y0, y1), y), q.y)),
					{"r": 4.2, "tag": "signage"}) >= 0:
				placed += 1
				break


# ---------------------------------------------------------------------------------------------
# power line along the Signal Hill road up to the radio mast (poles + procedural sagging wires)
# ---------------------------------------------------------------------------------------------

func _power_line() -> void:
	var hill_seg: Dictionary = {}
	for seg: Dictionary in roads.get("segments"):
		if String(seg.get("name", "")) == "Signal Hill Road":
			hill_seg = seg
			break
	if hill_seg.is_empty():
		return
	var p2: PackedVector2Array = hill_seg["pts2"]
	var hw := float(hill_seg["hw"])
	var length := float(hill_seg["length"])
	var poles: Array[Transform3D] = []
	var s := 22.0
	while s < length - 8.0:
		var d := dir_at(p2, s)
		var r := right_of(d)
		var q := pt(p2, s) + r * (hw + 2.6)
		var p := Vector3(q.x, 0.0, q.y)
		if not bool(sys.call("on_carriageway", p, 2.4)):
			var y := float(sys.call("ground", q.x, q.y))
			var xf := Transform3D(Basis(Vector3.UP, yaw_of(d)), Vector3(q.x, y, q.y))
			if place("power_pole", xf, {"r": 0.6, "tag": "utility"}) >= 0:
				poles.append(xf)
		s += 34.0
	if poles.size() < 2:
		return
	var cat: RefCounted = sys.get("catalog")
	var wires: Array[Transform3D] = []
	for wn: String in ["Wire_1", "Wire_2", "Wire_3", "Wire_4"]:
		var m: Variant = cat.call("marker", "power_pole", wn)
		if m != null:
			wires.append(m)
	if wires.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(poles.size() - 1):
		for w: Transform3D in wires:
			var a := (poles[k] * w).origin
			var b := (poles[k + 1] * w).origin
			_wire(st, a, b, 0.025)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.09, 0.1)
	mat.roughness = 0.6
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "PowerWires"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 320.0
	(sys.get("_scene_root") as Node).add_child(mi)


## Sagging wire as a thin triangular tube (12 segments).
static func _wire(st: SurfaceTool, a: Vector3, b: Vector3, r: float) -> void:
	var n := 12
	var sag := a.distance_to(b) * 0.035
	var prev: Array = []
	for k in n + 1:
		var t := float(k) / n
		var c := a.lerp(b, t) + Vector3.DOWN * (sag * 4.0 * t * (1.0 - t))
		var fwd := (b - a).normalized()
		var side := fwd.cross(Vector3.UP).normalized()
		var up := side.cross(fwd).normalized()
		var ring := [c + up * r, c - up * r * 0.5 + side * r * 0.87, c - up * r * 0.5 - side * r * 0.87]
		if not prev.is_empty():
			for j in 3:
				var j2 := (j + 1) % 3
				st.add_vertex(prev[j])
				st.add_vertex(ring[j])
				st.add_vertex(ring[j2])
				st.add_vertex(prev[j])
				st.add_vertex(ring[j2])
				st.add_vertex(prev[j2])
		prev = ring
