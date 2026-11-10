extends RefCounted
## WORLD module helper: named locations, spawn points and transit stops. Everything is derived from
## the layout (lots, roads, walk graph) with a fixed seed. Module-private (no class_name).

const Geom := preload("res://gta/code/world/gen/world_geom.gd")

var locations := {}                 ## name -> Transform3D
var spawns := {}                    ## kind -> Array of Transform3D
var transit_path := PackedVector3Array()
var transit_stops: Array[Dictionary] = []

var _w: Node3D                      ## the World node (get_height, roads, walk, terrain)
var _lots: Array = []
var _by_landmark := {}
var _reserved: Array[Vector2] = []  ## kerb spots that generic parking must leave free
var _rng := RandomNumberGenerator.new()

const KINDS: Array[String] = ["parking", "boat", "heli", "plane", "police_car", "taxi", "ped", "wildlife_land",
		"wildlife_water", "pickup_weapon", "pickup_health", "pickup_armor", "pickup_cash", "parachute", "roadblock",
		"gang", "ladder", "bench", "street_light", "traffic_light", "tree_street", "bin", "hydrant", "bus_stop"]


func build(world: Node3D, lots: Array, tram2d: PackedVector2Array, lot_bays: Array, driveways: Array) -> void:
	_w = world
	_lots = lots
	_rng.seed = WorldLayout.SEED
	for k in KINDS:
		spawns[k] = []
	for k in NATURE_KINDS:
		spawns[k] = []
	for lot: Dictionary in lots:
		if String(lot["landmark"]) != "":
			_by_landmark[String(lot["landmark"])] = lot
	_transit(tram2d)
	_locations()
	_special_vehicles(driveways)
	_parking(lot_bays)
	_street_furniture()
	_peds_and_wildlife()
	_pickups_and_misc()
	_nature()


# ---------------------------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------------------------

func _h(x: float, z: float) -> float:
	return float(_w.call("get_height", x, z))


func _xf(x: float, z: float, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(x, _h(x, z), z))


func _add(kind: String, xf: Transform3D) -> void:
	(spawns[kind] as Array).append(xf)


func _lot_axes(lot: Dictionary) -> Array:
	var yaw: float = lot["yaw"]
	return [Vector2(cos(yaw), -sin(yaw)), Vector2(-sin(yaw), -cos(yaw))]      # along (local +X), front (local -Z)


## Point in front of a lot: `out` metres beyond its front edge, `along` metres along local +X.
func _lot_front(lot: Dictionary, out: float, along: float = 0.0) -> Vector2:
	var ax: Array = _lot_axes(lot)
	var c: Vector3 = lot["center"]
	var size: Vector2 = lot["size"]
	return Vector2(c.x, c.z) + (ax[1] as Vector2) * (size.y * 0.5 + out) + (ax[0] as Vector2) * along


## Use point on the sidewalk in front of a landmark lot, facing the building.
func _use_point(lot: Dictionary, along: float = 0.0) -> Transform3D:
	var p := _lot_front(lot, WorldLayout.SIDEWALK_W * 0.5, along)
	return _xf(p.x, p.y, float(lot["yaw"]) + PI)


## Kerb-side spot on the street in front of a lot (parking lane), facing the travel direction.
func _kerb_spot(lot: Dictionary, along: float) -> Transform3D:
	var p := _lot_front(lot, WorldLayout.SIDEWALK_W + 1.0, along)
	var f: Vector2 = _lot_axes(lot)[1]
	_reserved.append(p)
	return _xf(p.x, p.y, Geom.yaw_of(Vector2(-f.y, f.x)))


func _yaw_to(from: Vector2, to: Vector2) -> float:
	return Geom.yaw_of((to - from).normalized())


func _lot_of(landmark: String) -> Dictionary:
	return _by_landmark.get(landmark, {})


# ---------------------------------------------------------------------------------------------
# transit
# ---------------------------------------------------------------------------------------------

func _transit(tram2d: PackedVector2Array) -> void:
	var y: float = WorldLayout.PLATEAU_Y + WorldLayout.ROAD_LIFT
	for q in tram2d:
		transit_path.append(Vector3(q.x, y, q.y))
	for i in range(1, 4):
		var lname := "tram_stop_%d" % i
		var lot := _lot_of(lname)
		if lot.is_empty() or tram2d.size() < 2:
			continue
		var p := _lot_front(lot, WorldLayout.SIDEWALK_W * 0.5)
		var hit := Geom.closest(tram2d, p)
		var on: Vector2 = hit[2]
		transit_stops.append({"name": lname, "position": Vector3(on.x, y, on.y), "offset": float(hit[1]),
				"platform": _use_point(lot)})
	transit_stops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["offset"]) < float(b["offset"]))


# ---------------------------------------------------------------------------------------------
# named locations
# ---------------------------------------------------------------------------------------------

func _locations() -> void:
	for lname: String in ["police_station", "hospital", "gun_shop", "mod_garage", "clothing_store", "barber",
			"general_store", "gas_station", "parking_garage", "safehouse", "shooting_range", "airport_hangar",
			"airport_tower", "lighthouse", "tram_stop_1", "tram_stop_2", "tram_stop_3", "radio_mast"]:
		var lot := _lot_of(lname)
		if lot.is_empty():
			push_error("[World] landmark lot missing: " + lname)
			continue
		locations[lname] = _use_point(lot)
	var safe := _lot_of("safehouse")
	if not safe.is_empty():
		var sp := _lot_front(safe, WorldLayout.SIDEWALK_W * 0.5, -4.0)
		locations["spawn_start"] = _xf(sp.x, sp.y, float(safe["yaw"]))
		var ax: Array = _lot_axes(safe)
		var sc: Vector3 = safe["center"]
		var size: Vector2 = safe["size"]
		var gp: Vector2 = Vector2(sc.x, sc.z) + (ax[0] as Vector2) * (size.x * 0.5 + 4.0) + (ax[1] as Vector2) * 3.0
		locations["safehouse_garage"] = _xf(gp.x, gp.y, float(safe["yaw"]))
	for lot: Dictionary in _lots:
		if String(lot["row"]) != "R":
			continue
		var c: Vector3 = lot["center"]
		match String(lot["block"]):
			"D7":
				locations["downtown_plaza"] = _xf(c.x, c.z, 0.0)
			"I6":
				locations["industrial_yard"] = _xf(c.x, c.z, 0.0)
			"R2":
				locations["residential_park"] = _xf(c.x, c.z, 0.0)
	var vp: Vector2 = WorldLayout.VIEWPOINT
	locations["hill_viewpoint"] = _xf(vp.x, vp.y, _yaw_to(vp, Vector2(0.0, -40.0)))
	var top: Vector2 = WorldLayout.HILL_CENTRE + Vector2(-2.5, 3.5)
	locations["hill_top"] = _xf(top.x, top.y, _yaw_to(top, Vector2(0.0, 0.0)))
	locations["beach"] = _xf(150.0, 252.0, PI)
	locations["marina_dock"] = _xf(float(WorldLayout.PIER_X[1]), 272.0, PI)
	locations["boat_spawn"] = Transform3D(Basis(Vector3.UP, PI), Vector3(float(WorldLayout.PIER_X[1]) + 6.5, 0.0, 274.0))
	locations["airport_runway_start"] = _xf(-150.0, -264.0, -PI * 0.5)
	locations["airport_runway_end"] = _xf(190.0, -264.0, PI * 0.5)
	var hp: Vector2 = WorldLayout.AIRPORT_HELIPAD
	locations["airport_helipad"] = _xf(hp.x, hp.y, 0.0)
	var hh: Vector2 = WorldLayout.HARBOR_HELIPAD
	locations["harbor_helipad"] = _xf(hh.x, hh.y, 0.0)
	var pg := _lot_of("parking_garage")
	if not pg.is_empty():
		var pc: Vector3 = pg["center"]
		# provisional: the city builder knows the real roof height and overrides it with World.set_location()
		locations["rooftop_helipad"] = Transform3D(Basis(Vector3.UP, float(pg["yaw"])), pc + Vector3(0.0, 10.6, 0.0))
	var sw: Vector2 = WorldLayout.SHIPWRECK
	locations["shipwreck"] = Transform3D(Basis(Vector3.UP, 0.6), Vector3(sw.x, _h(sw.x, sw.y), sw.y))
	locations["stunt_ramp_1"] = _xf(-180.0, 138.0, -PI * 0.5)
	locations["stunt_ramp_2"] = _xf(-274.25, 205.0, PI)
	locations["stunt_ramp_3"] = _xf(-200.0, -256.0, -PI * 0.5)
	locations["race_start"] = _xf(60.0, 156.25, PI * 0.5)
	locations["taxi_stand"] = _xf(30.0, -15.5, -PI * 0.5)


# ---------------------------------------------------------------------------------------------
# vehicles
# ---------------------------------------------------------------------------------------------

func _special_vehicles(driveways: Array) -> void:
	for dx: float in [-6.5, 0.0, 6.5]:
		var p := Vector2(30.0 + dx, -15.5)
		_reserved.append(p)
		_add("taxi", _xf(p.x, p.y, -PI * 0.5))
	var ps := _lot_of("police_station")
	if not ps.is_empty():
		for a: float in [-9.0, -2.5, 4.0, 10.5]:
			_add("police_car", _kerb_spot(ps, a))
	var hs := _lot_of("hospital")
	if not hs.is_empty():
		_reserved.append(_lot_front(hs, WorldLayout.SIDEWALK_W + 1.0, 8.0))
	for i in range(1, 4):
		var ts := _lot_of("tram_stop_%d" % i)
		if not ts.is_empty():
			_reserved.append(_lot_front(ts, WorldLayout.SIDEWALK_W + 1.0, 0.0))
	for d: Transform3D in driveways:
		var o := d.origin + d.basis.z * 1.0
		_reserved.append(Vector2(o.x, o.z))
	# boats: slips on both sides of every marina pier
	for px: float in WorldLayout.PIER_X:
		for sx: float in [-5.0, 5.0]:
			for z: float in [267.0, 278.0]:
				_add("boat", Transform3D(Basis(Vector3.UP, PI), Vector3(px + sx, 0.0, z)))
	_add("heli", locations["airport_helipad"])
	_add("heli", locations["harbor_helipad"])
	_add("plane", _xf(-215.0, -247.0, -PI * 0.5))
	_add("plane", _xf(-185.0, -247.0, -PI * 0.5))
	_add("plane", locations["airport_runway_start"])
	# bus stops on the ring (sidewalk, facing the road)
	_add("bus_stop", _xf(-30.0, -180.4, 0.0))
	_add("bus_stop", _xf(60.0, 150.4, PI))
	_add("bus_stop", _xf(-205.4, 25.0, PI * 0.5))
	_add("bus_stop", _xf(205.4, 40.0, -PI * 0.5))
	# roadblock sites: middle of long arterial / avenue stretches
	var roads: RoadGraph = _w.get("roads")
	for s: Dictionary in roads.segments:
		var kind: String = s["kind"]
		var length: float = s["length"]
		if (kind == "arterial" and length > 55.0) or (kind == "street" and length > 100.0):
			var p2: PackedVector2Array = s["pts2"]
			var m := Geom.point_at(p2, length * 0.5)
			_add("roadblock", _xf(m.x, m.y, Geom.yaw_of(Geom.dir_at(p2, length * 0.5))))


func _free_kerb(p: Vector2) -> bool:
	for r in _reserved:
		if r.distance_squared_to(p) < 64.0:
			return false
	return true


func _parking(lot_bays: Array) -> void:
	var roads: RoadGraph = _w.get("roads")
	var setback: float = WorldLayout.STOP_SETBACK
	for s: Dictionary in roads.segments:
		if not s["parking"]:
			continue
		var a0: float = float(s["trim_a"]) + setback
		var a1: float = float(s["length"]) - float(s["trim_b"]) - setback
		if a1 - a0 < 20.0:
			continue
		var sub := Geom.sub(s["pts2"], a0, a1)
		var total := Geom.length_of(sub)
		var t := 3.0 + 6.5            # first bay is kept free (sight line at the junction)
		while t + 6.5 <= total - 8.0:
			var p := Geom.point_at(sub, t + 3.25)
			var d := Geom.dir_at(sub, t + 3.25)
			var r := Geom.right_of(d)
			for side: float in [1.0, -1.0]:
				var q := p + r * (4.5 * side)
				if _free_kerb(q):
					_add("parking", _xf(q.x, q.y, Geom.yaw_of(d * side)))
			t += 6.5
	for b: Transform3D in lot_bays:
		_add("parking", b)


# ---------------------------------------------------------------------------------------------
# street furniture
# ---------------------------------------------------------------------------------------------

func _street_furniture() -> void:
	var roads: RoadGraph = _w.get("roads")
	var ys: float = WorldLayout.PLATEAU_Y + WorldLayout.CURB_H
	for s: Dictionary in roads.segments:
		var hw: float = s["hw"]
		var p2: PackedVector2Array = s["pts2"]
		var spans: Array = [s["sw_l_span"], s["sw_r_span"]]
		var have_l := not (spans[0] as Array).is_empty()
		var have_r := not (spans[1] as Array).is_empty()
		if not have_l and not have_r:
			continue
		var lo := 0.0
		var hi: float = s["length"]
		for sp: Array in spans:
			if not sp.is_empty():
				lo = maxf(lo, float(sp[0]))
				hi = minf(hi, float(sp[1]))
		var k := 0
		var t := lo + 6.0
		var green := String(s["kind"]) != "alley"
		while t <= hi - 4.0:
			var use_right := (k % 2 == 0)
			if use_right and not have_r:
				use_right = false
			elif not use_right and not have_l:
				use_right = true
			var p := Geom.point_at(p2, t)
			var d := Geom.dir_at(p2, t)
			var r := Geom.right_of(d) * (1.0 if use_right else -1.0)
			var q := p + r * (hw + 0.6)
			_add("street_light", Transform3D(Basis(Vector3.UP, Geom.yaw_of(-r)), Vector3(q.x, ys, q.y)))
			# a street tree half way to the next lamp, on the other side when it exists
			var t2 := t + 14.0
			if green and t2 <= hi - 4.0:
				var other := -r if (have_l and have_r) else r
				var p_t := Geom.point_at(p2, t2)
				var d_t := Geom.dir_at(p2, t2)
				var r_t := Geom.right_of(d_t) * (1.0 if other.dot(Geom.right_of(d)) > 0.0 else -1.0)
				var qt := p_t + r_t * (hw + 0.95)
				var dist: String = WorldLayout.district_at(qt.x, qt.y)
				if dist != "industrial" and dist != "airport":
					_add("tree_street", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(qt.x, ys, qt.y)))
			t += 28.0
			k += 1
		# one hydrant per longer street segment
		if float(s["length"]) > 50.0 and have_r and String(s["kind"]) == "street":
			var th := (lo + hi) * 0.5 + 9.0
			var ph := Geom.point_at(p2, th)
			var rh := Geom.right_of(Geom.dir_at(p2, th))
			var qh := ph + rh * (hw + 0.5)
			_add("hydrant", Transform3D(Basis(Vector3.UP, Geom.yaw_of(-rh)), Vector3(qh.x, ys, qh.y)))
	for head: Dictionary in roads.get_signal_heads():
		_add("traffic_light", head["transform"])
	for node: Dictionary in roads.intersections:
		if not node["has_signal"]:
			continue
		var c3: Vector3 = node["position"]
		var corners: Array = node["corners"]
		for i in corners.size():
			if i % 2 != 0:
				continue
			var cn: Dictionary = corners[i]
			var da: Vector2 = cn["da"]
			var db: Vector2 = cn["db"]
			var q := Vector2(c3.x, c3.z) + da * (float(cn["hwb"]) + 2.3) + db * (float(cn["hwa"]) + 2.3)
			_add("bin", Transform3D(Basis(Vector3.UP, Geom.yaw_of(-(da + db).normalized())), Vector3(q.x, ys, q.y)))
	# benches: plaza, park, promenade, boardwalk, viewpoint, tram stops
	var benches: Array = [
		[18.0, -70.0, -PI * 0.5], [42.0, -70.0, PI * 0.5], [18.0, -45.0, -PI * 0.5], [42.0, -45.0, PI * 0.5],
		[181.0, 10.0, -PI * 0.5], [198.0, 10.0, PI * 0.5], [181.0, 42.0, -PI * 0.5], [198.0, 42.0, PI * 0.5],
		[163.5, -150.5, PI * 0.5], [162.6, -144.5, PI * 0.5],
	]
	for x: float in [-240.0, -196.0, -164.0, -134.0, -104.0, -72.0, -44.0]:
		benches.append([x, 246.4, PI])
	for x: float in [60.0, 96.0, 132.0, 168.0, 204.0, 236.0]:
		benches.append([x, 233.4, PI])
	for b: Array in benches:
		_add("bench", _xf(float(b[0]), float(b[1]), float(b[2])))
	for i in range(1, 4):
		var ts := _lot_of("tram_stop_%d" % i)
		if not ts.is_empty():
			var c: Vector3 = ts["center"]
			_add("bench", Transform3D(Basis(Vector3.UP, float(ts["yaw"])), c))


# ---------------------------------------------------------------------------------------------
# pedestrians, wildlife
# ---------------------------------------------------------------------------------------------

func _peds_and_wildlife() -> void:
	var walk: WalkGraph = _w.get("walk")
	if walk != null:
		for i in walk.points.size():
			if i % 2 != 0 or walk.main[i] == 0 or walk.kinds[i] == WalkGraph.K_CROSSWALK:
				continue
			var p := walk.points[i]
			var yaw := 0.0
			if not walk.links[i].is_empty():
				var o := walk.points[walk.links[i][0]]
				yaw = Geom.yaw_of(Vector2(o.x - p.x, o.z - p.z).normalized())
			_add("ped", Transform3D(Basis(Vector3.UP, yaw), p))
	var terrain: Terrain = _w.get("terrain")
	# land wildlife: Signal Hill, lighthouse headland, east dunes, park
	var areas: Array = [
		[WorldLayout.HILL_CENTRE.x, WorldLayout.HILL_CENTRE.y, 84.0, 24, 4.0],
		[10.0, 258.0, 16.0, 3, 2.0], [268.0, 150.0, 30.0, 4, 1.0], [191.0, 26.0, 20.0, 4, 2.0],
		[190.0, 252.0, 40.0, 4, 0.6],
	]
	for a: Array in areas:
		var want: int = a[3]
		var got := 0
		var tries := 0
		while got < want and tries < 400:
			tries += 1
			var ang := _rng.randf() * TAU
			var rad := sqrt(_rng.randf()) * float(a[2])
			var x := float(a[0]) + cos(ang) * rad
			var z := float(a[1]) + sin(ang) * rad
			var h := terrain.get_mesh_height(x, z)
			if h < float(a[4]):
				continue
			var kd := terrain.get_kind(x, z)
			if (kd & 3) == 2:
				continue
			if absf(terrain.get_mesh_height(x + 2.0, z) - h) > 1.3 or absf(terrain.get_mesh_height(x, z + 2.0) - h) > 1.3:
				continue
			if String(_w.call("get_surface_at", Vector3(x, h, z))) in ["asphalt", "concrete", "wood"]:
				continue
			_add("wildlife_land", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(x, _h(x, z), z)))
			got += 1
	# water wildlife: around the wreck, the bays and the open sea
	var seas: Array = [[WorldLayout.SHIPWRECK.x, WorldLayout.SHIPWRECK.y, 34.0, 5], [0.0, 0.0, 430.0, 12]]
	for a: Array in seas:
		var want: int = a[3]
		var got := 0
		var tries := 0
		while got < want and tries < 600:
			tries += 1
			var ang := _rng.randf() * TAU
			var rad := sqrt(_rng.randf()) * float(a[2])
			var x := float(a[0]) + cos(ang) * rad
			var z := float(a[1]) + sin(ang) * rad
			var h := terrain.get_mesh_height(x, z)
			if h > -3.5 or absf(x) > 370.0 or absf(z) > 370.0:
				continue
			_add("wildlife_water", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(x, h * 0.5, z)))
			got += 1


# ---------------------------------------------------------------------------------------------
# pickups, ladders, gangs, parachutes
# ---------------------------------------------------------------------------------------------

func _pickups_and_misc() -> void:
	var weapon: Array = [[-165.6, 20.0], [57.6, -150.0], [-57.6, 30.0], [-275.0, 100.0], [-90.0, 282.0], [219.0, -131.0],
			[165.0, -149.5], [4.5, 268.0], [180.0, 234.2], [-236.0, -262.0], [-150.0, 130.0], [190.0, 26.0]]
	for p: Array in weapon:
		_add("pickup_weapon", _xf(float(p[0]), float(p[1]), 0.0))
	var sw: Vector2 = WorldLayout.SHIPWRECK
	_add("pickup_weapon", Transform3D(Basis.IDENTITY, Vector3(sw.x + 3.0, _h(sw.x + 3.0, sw.y - 2.0), sw.y - 2.0)))
	var health: Array = [[30.0, -60.0], [120.0, 246.0], [-120.0, 240.0], [168.0, -144.0], [104.5, -217.0], [182.0, 40.0], [-275.0, -40.0]]
	var armor: Array = [[-275.0, 200.0], [-165.6, -60.0], [62.4, 40.0], [228.0, -123.0], [-210.0, 282.0]]
	var cash: Array = [[20.0, -45.0], [45.0, -75.0], [-60.0, 240.0], [-180.0, 240.0], [100.0, 234.2], [220.0, 234.2],
			[-62.4, -150.0], [-180.0, 120.0]]
	for spec: Array in [["hospital", "pickup_health", 6.0], ["safehouse", "pickup_health", -6.0], ["police_station", "pickup_health", -10.0],
			["police_station", "pickup_armor", 12.0], ["airport_tower", "pickup_armor", 0.0], ["gun_shop", "pickup_cash", 6.0],
			["clothing_store", "pickup_cash", 5.0], ["general_store", "pickup_cash", -5.0], ["gas_station", "pickup_cash", 13.0],
			["airport_hangar", "pickup_armor", 10.0]]:
		var lot := _lot_of(String(spec[0]))
		if lot.is_empty():
			continue
		var q := _lot_front(lot, 1.0, float(spec[2]))
		_add(String(spec[1]), _xf(q.x, q.y, 0.0))
	for p: Array in health:
		_add("pickup_health", _xf(float(p[0]), float(p[1]), 0.0))
	for p: Array in armor:
		_add("pickup_armor", _xf(float(p[0]), float(p[1]), 0.0))
	for p: Array in cash:
		_add("pickup_cash", _xf(float(p[0]), float(p[1]), 0.0))
	# parachutes at the high / remote spots
	var top: Vector2 = WorldLayout.HILL_CENTRE
	_add("parachute", _xf(top.x - 1.0, top.y + 7.0, 0.0))
	_add("parachute", _xf(95.0, -206.5, 0.0))
	_add("parachute", _xf(11.5, 267.5, 0.0))
	# gang hangouts (transform faces the open side)
	var gang: Array = [[-165.8, 28.0, PI * 0.5], [-274.0, 150.0, -PI * 0.5], [62.2, -60.0, PI * 0.5], [-195.0, 115.0, -PI * 0.5]]
	for g: Array in gang:
		_add("gang", _xf(float(g[0]), float(g[1]), float(g[2])))
	for lot: Dictionary in _lots:
		if String(lot["zone"]) == "parking" and String(lot["district"]) == "beach":
			var c: Vector3 = lot["center"]
			_add("gang", _xf(c.x, c.z, float(lot["yaw"])))
	# ladders out of the harbour water: origin at sea level on the wall face, -Z points into the wall
	var qx: float = WorldLayout.QUAY_X
	var qz: float = WorldLayout.QUAY_Z
	for z: float in [-60.0, 20.0, 100.0, 180.0, 236.0]:
		_add("ladder", Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(qx - 0.05, 0.0, z)))
	for x: float in [-240.0, -180.0, -120.0, -60.0]:
		_add("ladder", Transform3D(Basis(Vector3.UP, 0.0), Vector3(x, 0.0, qz + 0.05)))
	for px: float in WorldLayout.PIER_X:
		_add("ladder", Transform3D(Basis(Vector3.UP, 0.0), Vector3(px, 0.0, float(WorldLayout.PIER_END_Z) + 0.05)))


# ---------------------------------------------------------------------------------------------
# nature placement data for the city dressing (trees, bushes, rocks, ground cover, reef decor)
# ---------------------------------------------------------------------------------------------
## Kinds (all Transform3D: origin on the ground / seabed, random yaw):
##   tree_hill    wooded Signal Hill (pines / broadleaf)      tree_wild   sparse trees on the grass margins
##   tree_palm    palms behind the beach / on the south shore  tree_park   inside "park" lots
##   bush, rock, ground_cover (grass tufts / ferns / flowers)  reef        seabed decor (coral / kelp), dense at the wreck
## Everything keeps clear of roads, dirt tracks, pads, walk paths, lots, named locations and pickups,
## of the runway clear zone (z < AIRPORT_CLEAR_Z) and of each other.

const NATURE_KINDS: Array[String] = ["tree_hill", "tree_wild", "tree_palm", "tree_park", "bush", "rock", "ground_cover", "reef"]
const AIRPORT_CLEAR_Z := -212.0
const EDGE_CLEAR := 4.5                 ## nature keeps this far from non-wild (city / airport / quay) ground
const LANE_CLEAR := 4.6                 ## trees / bushes / rocks keep this far from any lane centre line
const _OCC := 8.0

var _occ := {}                       ## 8 m cell -> PackedVector3Array (x, z, radius) of placed items
var _clear_pts := PackedVector2Array()
var _wild_lots: Array = []
var _nrng := RandomNumberGenerator.new()
var _nat := PackedByteArray()        ## lazy natural-ground flags per terrain lattice vertex (0 unknown, 1 yes, 2 no)


func _nature() -> void:
	var terrain: Terrain = _w.get("terrain")
	if terrain == null:
		return
	var walk: WalkGraph = _w.get("walk")
	_nrng.seed = WorldLayout.SEED + 4111
	for n: String in locations:
		var o: Vector3 = (locations[n] as Transform3D).origin
		_clear_pts.append(Vector2(o.x, o.z))
	for k: String in ["pickup_weapon", "pickup_health", "pickup_armor", "pickup_cash", "parachute", "gang", "bench", "wildlife_land"]:
		for xf: Transform3D in spawns[k]:
			_clear_pts.append(Vector2(xf.origin.x, xf.origin.z))
	# lots that touch wild land (lighthouse, radio mast, edge lots): vegetation keeps out of them
	for lot: Dictionary in _lots:
		var c: Vector3 = lot["center"]
		var size: Vector2 = lot["size"]
		var reach := size.length() * 0.5 + 6.0
		for q: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
				Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7)]:
			if (terrain.get_kind(c.x + q.x * reach, c.z + q.y * reach) & 4) != 0:
				_wild_lots.append(lot)
				break

	# park lots first (they own their interior)
	for lot: Dictionary in _lots:
		if String(lot["zone"]) == "park":
			_park(lot, walk)

	# trees: wooded hill, sparse elsewhere
	for p: Vector2 in _grid(-300.0, -300.0, 300.0, 300.0, 7.5):
		if _in_city_box(p.x, p.y) or p.y < AIRPORT_CLEAR_Z:
			continue
		var on_hill := Terrain.hill(p.x, p.y) > 1.0
		if _nrng.randf() > (0.8 if on_hill else 0.16):
			continue
		var h := _site(terrain, p.x, p.y, false, 6.0, EDGE_CLEAR, 7.0, 0.85)
		if h != -INF and _nature_free(walk, p, h, 2.6, 5.0, 3.0):
			_put("tree_hill" if on_hill else "tree_wild", p, h, 2.6)

	# palms near the sea on the southern half (beach, lighthouse knoll, east dunes)
	for p: Vector2 in _grid(-60.0, -40.0, 300.0, 300.0, 8.0):
		if _in_city_box(p.x, p.y) or Terrain.hill(p.x, p.y) > 0.5:
			continue
		var sand := (terrain.get_kind(p.x, p.y) & 3) == 1
		if _nrng.randf() > (0.42 if sand else 0.14):
			continue
		if Terrain.coast_sd(p.x, p.y) > 40.0:
			continue
		var h := _site(terrain, p.x, p.y, true, 4.5, 4.0, 8.0, 0.6)
		if h != -INF and h > 0.9 and _nature_free(walk, p, h, 2.2, 4.0, 2.6):
			_put("tree_palm", p, h, 2.2)

	# rocks: hill slopes and the rocky (non-beach) shore line
	for p: Vector2 in _grid(-300.0, -300.0, 300.0, 300.0, 8.0):
		if _in_city_box(p.x, p.y):
			continue
		var hl := Terrain.hill(p.x, p.y)
		var cd := Terrain.coast_sd(p.x, p.y)
		var chance := 0.03
		if cd < 7.0 and Terrain.beach_mask(p.x, p.y) < 0.3:
			chance = 0.4
		elif hl > 2.0:
			chance = 0.16
		if p.y < AIRPORT_CLEAR_Z and cd > 7.0:
			continue
		if _nrng.randf() > chance:
			continue
		var h := _site(terrain, p.x, p.y, true, 3.5, 3.0, 1.2, 1.3)
		if h != -INF and _nature_free(walk, p, h, 1.6, 3.0, 2.0):
			_put("rock", p, h, 1.6)

	# bushes
	for p: Vector2 in _grid(-300.0, -300.0, 300.0, 300.0, 6.0):
		if _in_city_box(p.x, p.y) or p.y < AIRPORT_CLEAR_Z:
			continue
		if _nrng.randf() > (0.22 if Terrain.hill(p.x, p.y) > 1.0 else 0.09):
			continue
		var h := _site(terrain, p.x, p.y, false, 3.5, 3.5, 4.0, 1.0)
		if h != -INF and _nature_free(walk, p, h, 1.2, 3.0, 2.0):
			_put("bush", p, h, 1.2)

	# ground cover (grass tufts, ferns, flowers): meant for MultiMesh with a short visibility range
	for p: Vector2 in _grid(-300.0, -300.0, 300.0, 300.0, 4.5):
		if _in_city_box(p.x, p.y):
			continue
		if _nrng.randf() > (0.4 if Terrain.hill(p.x, p.y) > 1.0 else 0.3):
			continue
		var h := _site(terrain, p.x, p.y, false, 2.5, 2.0, 3.0, 1.2)
		if h != -INF and _nature_free(walk, p, h, 0.5, 1.5, 1.3):
			_put("ground_cover", p, h, 0.5)

	# reef decor on the seabed: dense around the wreck, sparse along the shelf (never in the harbour basin)
	var wreck: Vector2 = WorldLayout.SHIPWRECK
	for p: Vector2 in _grid(-370.0, -370.0, 370.0, 370.0, 11.0):
		var dw := p.distance_to(wreck)
		if _nrng.randf() > (0.6 if dw < 48.0 else 0.11):
			continue
		if dw < 11.0:
			continue
		var h := terrain.get_mesh_height(p.x, p.y)
		if h > -2.5 or h < Terrain.SEA_FLOOR - 0.2:
			continue
		var cd := Terrain.coast_sd(p.x, p.y)
		if cd > -5.0 or cd < -110.0 or Terrain.port_sd(p.x, p.y) < 6.0:
			continue
		_add("reef", Transform3D(Basis(Vector3.UP, _nrng.randf() * TAU), Vector3(p.x, h, p.y)))


func _park(lot: Dictionary, walk: WalkGraph) -> void:
	var c: Vector3 = lot["center"]
	var size: Vector2 = lot["size"]
	var ax: Array = _lot_axes(lot)
	var along: Vector2 = ax[0]
	var front: Vector2 = ax[1]
	var specs: Array = [["tree_park", 5.5, 0.9, 2.2, 2.6], ["bush", 5.0, 0.35, 1.2, 2.0], ["ground_cover", 4.0, 0.4, 0.5, 1.3]]
	for spec: Array in specs:
		var step: float = spec[1]
		var u := -size.x * 0.5 + 2.5
		while u <= size.x * 0.5 - 2.5:
			var v := -size.y * 0.5 + 2.5
			while v <= size.y * 0.5 - 2.5:
				var ju := clampf(u + _nrng.randf_range(-0.3, 0.3) * step, -size.x * 0.5 + 2.0, size.x * 0.5 - 2.0)
				var jv := clampf(v + _nrng.randf_range(-0.3, 0.3) * step, -size.y * 0.5 + 2.0, size.y * 0.5 - 2.0)
				v += step
				if _nrng.randf() > float(spec[2]):
					continue
				var p := Vector2(c.x, c.z) + along * ju + front * jv
				var h := _h(p.x, p.y)
				if _nature_free(walk, p, h, float(spec[3]), 3.0, float(spec[4]), false):
					_put(String(spec[0]), p, h, float(spec[3]))
			u += step


## Jittered grid of candidate positions (deterministic, uses the nature RNG).
func _grid(x0: float, z0: float, x1: float, z1: float, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var z := z0 + step * 0.5
	while z < z1:
		var x := x0 + step * 0.5
		while x < x1:
			out.append(Vector2(x + _nrng.randf_range(-0.42, 0.42) * step, z + _nrng.randf_range(-0.42, 0.42) * step))
			x += step
		z += step
	return out


## Height of a natural-ground site or -INF when it is unsuitable. Natural = wild land (hill, coast
## margins) or unpaved grass outside the city box; every lattice vertex within edge_r must be natural
## (keeps off kerbs, slabs, decks, runway, dirt), none within dirt_r may be a dirt track / pad.
func _site(terrain: Terrain, x: float, z: float, sand_ok: bool, dirt_r: float, edge_r: float, coast_min: float, slope_max: float) -> float:
	var surf := terrain.get_kind(x, z) & 3
	if surf == 2 or (surf == 1 and not sand_ok):
		return -INF
	var ci := int(round(x / Terrain.CELL)) + Terrain.HALF
	var cj := int(round(z / Terrain.CELL)) + Terrain.HALF
	if not _natural(terrain, ci, cj) or int(_w.call("_paved", x, z)) != 0:
		return -INF
	if Terrain.coast_sd(x, z) < coast_min:
		return -INF
	var h := terrain.get_mesh_height(x, z)
	if h < 0.6:
		return -INF
	var sx := terrain.get_mesh_height(x + 1.5, z) - terrain.get_mesh_height(x - 1.5, z)
	var sz := terrain.get_mesh_height(x, z + 1.5) - terrain.get_mesh_height(x, z - 1.5)
	if sqrt(sx * sx + sz * sz) / 3.0 > slope_max:
		return -INF
	var reach := maxf(dirt_r, edge_r)
	var n := int(ceil(reach / Terrain.CELL))
	var fx := x / Terrain.CELL + float(Terrain.HALF)
	var fz := z / Terrain.CELL + float(Terrain.HALF)
	var i0 := int(floor(fx))
	var j0 := int(floor(fz))
	for j in range(j0 - n, j0 + n + 2):
		for i in range(i0 - n, i0 + n + 2):
			var d2 := ((float(i) - fx) * (float(i) - fx) + (float(j) - fz) * (float(j) - fz)) * Terrain.CELL * Terrain.CELL
			if d2 <= edge_r * edge_r and not _natural(terrain, i, j):
				return -INF
			if d2 <= dirt_r * dirt_r and i >= 0 and j >= 0 and i < Terrain.N and j < Terrain.N 					and (terrain.kinds[j * Terrain.N + i] & 3) == 2:
				return -INF
	return h


## Lazy per lattice vertex test: natural (unpaved, not dirt, dry) ground.
func _natural(terrain: Terrain, i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= Terrain.N or j >= Terrain.N:
		return false
	if _nat.is_empty():
		_nat.resize(Terrain.N * Terrain.N)
	var g := j * Terrain.N + i
	var v := _nat[g]
	if v == 0:
		var x := float(i - Terrain.HALF) * Terrain.CELL
		var z := float(j - Terrain.HALF) * Terrain.CELL
		var kd := terrain.kinds[g]
		var ok := (kd & 3) != 2 and terrain.heights[g] >= 0.6 and absf(x) < 299.0 and absf(z) < 299.0
		if ok and (kd & 4) == 0:
			ok = not _in_city_box(x, z) and int(_w.call("_paved", x, z)) == 0
		v = 1 if ok else 2
		_nat[g] = v
	return v == 1


## The dense city footprint (same box as Terrain._land's fast path): never natural ground.
static func _in_city_box(x: float, z: float) -> bool:
	return x > -250.0 and z > -250.0 and z < 226.0 and (x < 128.0 or (x < 258.0 and z > -22.0))


## True when an item of radius r fits at p: away from other nature items, named locations / pickups,
## lots outside the plateau, walk paths and (for everything but ground cover) traffic lanes incl. dirt roads.
func _nature_free(walk: WalkGraph, p: Vector2, h: float, r: float, clear_r: float, path_r: float, check_lots: bool = true) -> bool:
	if not _occ_free(p.x, p.y, r):
		return false
	if r >= 1.0:
		var roads: RoadGraph = _w.get("roads")
		if roads != null and not roads.get_nearest_lane(Vector3(p.x, h, p.y), LANE_CLEAR).is_empty():
			return false
	for q: Vector2 in _clear_pts:
		if q.distance_squared_to(p) < clear_r * clear_r:
			return false
	if check_lots:
		for lot: Dictionary in _wild_lots:
			if _in_lot(lot, p, 2.5):
				return false
	if walk != null and path_r > 0.0:
		var q := walk.get_nearest_point(Vector3(p.x, h, p.y))
		if q != Vector3.INF and Vector2(q.x - p.x, q.z - p.y).length_squared() < path_r * path_r:
			return false
	return true


func _put(kind: String, p: Vector2, h: float, r: float) -> void:
	_add(kind, Transform3D(Basis(Vector3.UP, _nrng.randf() * TAU), Vector3(p.x, h, p.y)))
	var key := (int(floor(p.x / _OCC)) + 512) * 1024 + int(floor(p.y / _OCC)) + 512
	var lst: PackedVector3Array = _occ.get(key, PackedVector3Array())
	lst.append(Vector3(p.x, p.y, r))
	_occ[key] = lst


func _occ_free(x: float, z: float, r: float) -> bool:
	var cx := int(floor(x / _OCC)) + 512
	var cz := int(floor(z / _OCC)) + 512
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := (cx + dx) * 1024 + cz + dz
			if not _occ.has(key):
				continue
			var lst: PackedVector3Array = _occ[key]
			for q: Vector3 in lst:
				var rr := r + q.z
				if (q.x - x) * (q.x - x) + (q.y - z) * (q.y - z) < rr * rr:
					return false
	return true


func _in_lot(lot: Dictionary, p: Vector2, margin: float) -> bool:
	var c: Vector3 = lot["center"]
	var size: Vector2 = lot["size"]
	var ax: Array = _lot_axes(lot)
	var d := p - Vector2(c.x, c.z)
	return absf(d.dot(ax[0] as Vector2)) < size.x * 0.5 + margin and absf(d.dot(ax[1] as Vector2)) < size.y * 0.5 + margin
