extends RefCounted
## PropSystem placer: set pieces and themed areas (WORLD DRESSING) - docks and Foundry Yard,
## marina promenade, beach, residential park, downtown plaza, Signal Hill viewpoint, airport, stunt
## ramps, the shipwreck, buoys, moored boats and ladders (quay walls, building walls, lifeguard
## tower, radio mast). Positions come from the world API (locations, lots, spawn points) plus the
## fixed layout numbers documented in docs/WORLD.md.

const QUAY_X := -279.0
const QUAY_Z := 252.0
const QUAY_NORTH := -96.0
const PIER_X := [-210.0, -150.0, -90.0]
const RUNWAY_Z := -264.0
const RUNWAY_X0 := -170.0
const RUNWAY_X1 := 210.0
const RUNWAY_HW := 12.0
const AIRPORT_HELIPAD := Vector2(95.0, -217.0)
const CatalogScript := preload("res://gta/code/world/dressing/prop_catalog.gd")

var sys: Node
var world: Node
var cat: RefCounted
var walk: Object
var rng := RandomNumberGenerator.new()
var _lots: Array = []
var _back_tris: Dictionary = {}       ## building id -> PackedFloat32Array (see _back_triangles)


func run(s: Node) -> void:
	sys = s
	world = s.get("world")
	cat = s.get("catalog")
	walk = world.get("walk")
	rng.seed = 520217
	_lots = world.call("get_lots") if world.has_method("get_lots") else []
	_ramps()
	sys.call("mark_phase", "sets.ramps")
	_docks()
	sys.call("mark_phase", "sets.docks")
	_yard()
	sys.call("mark_phase", "sets.yard")
	_marina()
	sys.call("mark_phase", "sets.marina")
	_beach()
	sys.call("mark_phase", "sets.beach")
	_park()
	sys.call("mark_phase", "sets.park")
	_plaza()
	sys.call("mark_phase", "sets.plaza")
	_hill()
	sys.call("mark_phase", "sets.hill")
	_airport()
	sys.call("mark_phase", "sets.airport")
	_wreck()
	sys.call("mark_phase", "sets.wreck")
	_water()
	sys.call("mark_phase", "sets.water")
	_ladders()
	sys.call("mark_phase", "sets.ladders")
	_loose_extras()
	sys.call("mark_phase", "sets.loose_extras")


# ---------------------------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------------------------

func place(id: String, xf: Transform3D, opts: Dictionary = {}) -> int:
	return int(sys.call("place", id, xf, opts))


func g(x: float, z: float) -> float:
	return float(sys.call("ground", x, z))


func at(x: float, z: float, yaw: float, lift: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(x, g(x, z) + lift, z))


func loc(name: String) -> Transform3D:
	if world.has_method("has_location") and not bool(world.call("has_location", name)):
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	return world.call("get_location", name)


func is_clear(p: Vector3, r: float) -> bool:
	return bool(sys.call("is_free", p, r))


func path_dist(p: Vector3) -> float:
	if walk == null:
		return INF
	var q: Vector3 = walk.call("get_nearest_point", p)
	if q == Vector3.INF:
		return INF
	return Vector2(q.x - p.x, q.z - p.z).length()


func find_lot(zone: String, district: String) -> Dictionary:
	for lot: Dictionary in _lots:
		if String(lot.get("zone", "")) == zone and String(lot.get("district", "")) == district:
			return lot
	return {}


static func in_lot_rect(lot: Dictionary, p: Vector3, margin: float) -> bool:
	var c: Vector3 = lot["center"]
	var s: Vector2 = lot["size"]
	var yaw := float(lot["yaw"])
	var dx := p.x - c.x
	var dz := p.z - c.z
	var lx := dx * cos(yaw) - dz * sin(yaw)
	var lz := dx * sin(yaw) + dz * cos(yaw)
	return absf(lx) <= s.x * 0.5 + margin and absf(lz) <= s.y * 0.5 + margin


static func lot_point(lot: Dictionary, lx: float, lz: float) -> Vector3:
	var c: Vector3 = lot["center"]
	return c + Basis(Vector3.UP, float(lot["yaw"])) * Vector3(lx, 0.0, lz)


func water_y() -> float:
	return Game.WATER_LEVEL


# ---------------------------------------------------------------------------------------------
# stunt ramps (trimesh, drivable)
# ---------------------------------------------------------------------------------------------

func _ramps() -> void:
	var ids := {"stunt_ramp_1": "stunt_ramp_big", "stunt_ramp_2": "stunt_ramp_small", "stunt_ramp_3": "stunt_ramp_big"}
	for n: String in ids:
		var xf := loc(n)
		if xf.origin == Vector3.INF:
			continue
		var p := xf.origin
		var x2 := Transform3D(xf.basis.orthonormalized(), Vector3(p.x, g(p.x, p.z), p.z))
		place(ids[n], x2, {"no_occ": true, "road_ok": true, "tag": "set_piece"})
		# keep the approach and the landing clear of other dressing
		var fwd := -x2.basis.z
		for k in range(-3, 6):
			sys.call("reserve", p + fwd * (k * 6.0), 4.0)


# ---------------------------------------------------------------------------------------------
# docks quay (west): gantry cranes, container rows, mooring bollards
# ---------------------------------------------------------------------------------------------

func _docks() -> void:
	var ladder_z: Array[float] = []
	for x: Transform3D in sys.call("spawn_points", "ladder"):
		if absf(x.origin.x - QUAY_X) < 2.0:
			ladder_z.append(x.origin.z)
	var crane_z := [-40.0, 95.0]
	for cz: float in crane_z:
		# legs straddle the 9.5 m deck (gantry clear span 6.4 m); boom and cab hang over the water / road
		var p := Vector3(QUAY_X + 4.3, 0.0, cz)
		if place("dock_crane", at(p.x, p.z, PI * 0.5), {"no_occ": true, "tag": "set_piece"}) >= 0:
			for dz: float in [-6.0, -3.0, 0.0, 3.0, 6.0]:
				sys.call("reserve", Vector3(QUAY_X + 1.0, 0, cz + dz), 1.2)
				sys.call("reserve", Vector3(QUAY_X + 8.5, 0, cz + dz), 1.2)
	# container groups along the quay, leaving the crane lanes, ladders and the ramp zone free
	var z := QUAY_NORTH + 8.0
	var group := 0
	var kinds := ["container_a", "container_b", "container_c"]
	while z < 180.0:
		var near_crane := false
		for cz: float in crane_z:
			if absf(z - cz) < 13.0:
				near_crane = true
		var near_ladder := false
		for lz: float in ladder_z:
			if absf(z - lz) < 8.0:
				near_ladder = true
		if near_crane or near_ladder:
			z += 4.0
			continue
		var n := 2 + (group % 2)
		var x := QUAY_X + 2.9
		for k in n:
			var zz := z + 3.1 + k * 6.4
			var p := Vector3(x, 0.0, zz)
			if not is_clear(p, 3.4):
				continue
			var id: String = kinds[(group + k) % 3]
			var xf := at(x, zz, 0.0 if rng.randf() < 0.5 else PI)
			if place(id, xf, {"r": 2.6, "tag": "set_piece"}) >= 0 and (k + group) % 3 == 0:
				var top := Transform3D(Basis(Vector3.UP, xf.basis.get_euler().y + rng.randf_range(-0.04, 0.04)),
						xf.origin + Vector3(0.0, 2.6, 0.0))
				place(kinds[(group + k + 1) % 3], top, {"no_occ": true, "tag": "set_piece"})
		z += n * 6.4 + 10.0
		group += 1
	# mooring bollards along the quay edge
	var zb := QUAY_NORTH + 4.0
	while zb < 248.0:
		var p := Vector3(QUAY_X + 0.9, 0.0, zb)
		if is_clear(p, 0.6):
			place("mooring_bollard", at(p.x, p.z, PI * 0.5), {"r": 0.5, "tag": "set_piece"})
		zb += 14.0
	# loose cargo around the containers (crates, pallets, drums)
	for k in 10:
		var zz := rng.randf_range(QUAY_NORTH + 10.0, 170.0)
		var p := Vector3(QUAY_X + rng.randf_range(6.0, 8.0), 0.0, zz)
		var ids := ["crate_wood", "crate_stack", "pallet", "barrel", "barrel_explosive", "tire_stack"]
		var id: String = ids[k % ids.size()]
		place(id, at(p.x, p.z, rng.randf() * TAU), {"r": 1.0, "tag": "loose"})


# ---------------------------------------------------------------------------------------------
# Foundry Yard (industrial plaza lot): containers, cargo stack, loose cargo, explosive drums
# ---------------------------------------------------------------------------------------------

func _yard() -> void:
	var lot := find_lot("plaza", "industrial")
	if lot.is_empty():
		return
	var size: Vector2 = lot["size"]
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var yaw := float(lot["yaw"])
	# the stunt ramp runs along the south edge: containers line the north edge, cargo stack in the NE corner
	var stack_p := lot_point(lot, hx - 6.0, -hz + 4.5)
	place("cargo_stack", Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(stack_p.x, g(stack_p.x, stack_p.z), stack_p.z)),
			{"r": 4.5, "tag": "set_piece"})
	var x := -hx + 4.0
	var k := 0
	while x < hx - 13.0:
		var p := lot_point(lot, x, -hz + 2.0)
		var id: String = ["container_c", "container_a", "container_open", "container_b"][k % 4]
		var ci := place(id, Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(p.x, g(p.x, p.z), p.z)), {"r": 2.4, "tag": "set_piece"})
		if ci >= 0 and k % 3 == 1 and id != "container_open":
			place(["container_b", "container_c", "container_a"][k % 3], Transform3D(Basis(Vector3.UP, yaw + PI * 0.5 + 0.03),
					Vector3(p.x, g(p.x, p.z) + 2.6, p.z)), {"no_occ": true, "tag": "set_piece"})
		x += 7.2
		k += 1
	# loose cargo clusters along the sides (the middle is the stunt ramp run)
	var clusters := [Vector2(-hx + 3.5, -hz + 6.0), Vector2(hx - 3.5, -hz + 7.0), Vector2(-hx + 3.0, 2.0), Vector2(hx - 3.0, 0.0),
			Vector2(hx - 9.0, hz - 4.0)]
	var ids := ["pallet", "crate_wood", "crate_stack", "barrel", "barrel_explosive", "gas_canister", "tire_stack",
			"cardboard_boxes", "barrel_explosive", "trash_bags"]
	var n := 0
	for c: Vector2 in clusters:
		for j in 5:
			var o := Vector2(rng.randf_range(-2.4, 2.4), rng.randf_range(-2.4, 2.4))
			var p := lot_point(lot, c.x + o.x, c.y + o.y)
			place(ids[n % ids.size()], at(p.x, p.z, rng.randf() * TAU), {"r": 0.75, "tag": "loose"})
			n += 1
	# a skip and a work light
	var dp := lot_point(lot, -hx + 9.0, -hz + 1.6)
	place("dumpster", Transform3D(Basis(Vector3.UP, yaw + PI), Vector3(dp.x, g(dp.x, dp.z), dp.z)), {"r": 1.3, "tag": "furniture"})


# ---------------------------------------------------------------------------------------------
# marina promenade (planks): lamps, palms in grates, lifebuoys, bollards, kiosks
# ---------------------------------------------------------------------------------------------

func _marina() -> void:
	var x := -246.0
	var mk: Variant = cat.call("marker", "street_lamp_b", "Light")
	var local: Transform3D = mk if mk != null else Transform3D(Basis.IDENTITY, Vector3(0, 4.2, 0))
	while x <= -40.0:
		var near_pier := false
		for px: float in PIER_X:
			if absf(x - px) < 5.0:
				near_pier = true
		if not near_pier:
			var i := place("street_lamp_b", at(x, 245.6, PI), {"r": 0.5, "tag": "lamp"})
			if i >= 0:
				sys.call("add_lamp_light", i, local, Color(1.0, 0.84, 0.6), 12.0, 2.4)
		var xp := x + 12.0
		if xp < -38.0:
			var p := Vector3(xp, 0, 234.6)
			if is_clear(p, 1.5):
				if place("palm_b" if int(xp) % 3 != 0 else "palm_a", at(xp, 234.6, rng.randf() * TAU), {"r": 1.0, "tag": "tree_street", "lod": false}) >= 0:
					place("tree_grate", at(xp, 234.6, 0.0, 0.002), {"no_occ": true, "tag": "furniture"})
		x += 24.0
	for px: float in PIER_X:
		place("lifebuoy_stand", at(px - 4.0, 247.0, PI), {"r": 0.5, "tag": "set_piece"})
		place("bin", at(px + 4.2, 246.6, PI), {"r": 0.4, "tag": "furniture"})
	place("vending_machine", at(-118.0, 233.4, 0.0), {"r": 0.7, "tag": "furniture"})
	place("phone_kiosk", at(-182.0, 233.4, 0.0), {"r": 0.6, "tag": "furniture"})
	place("bike_rack", at(-60.0, 233.6, 0.0), {"r": 1.2, "tag": "furniture"})
	var xb := -250.0
	while xb < -36.0:
		var skip := false
		for px: float in PIER_X:
			if absf(xb - px) < 4.0:
				skip = true
		if not skip:
			place("mooring_bollard", at(xb, QUAY_Z - 1.2, PI), {"r": 0.5, "tag": "set_piece"})
		xb += 15.0


# ---------------------------------------------------------------------------------------------
# beach: umbrellas + loungers, lifeguard towers, volleyball, kiosk
# ---------------------------------------------------------------------------------------------

func _beach() -> void:
	# volleyball court between the towers: net across X (posts at +-5 m), courts 4.5 m either side
	for xv: float in [150.0, 140.0, 160.0, 130.0, 170.0, 122.0, 178.0]:
		var zv := 236.0
		while zv < 300.0 and g(xv, zv) > 0.25:
			zv += 1.0
		if zv - 245.0 <= 12.0:
			continue
		var zc := lerpf(242.0, zv - 4.0, 0.5)
		var spots := [Vector3(xv, 0, zc), Vector3(xv - 5.0, 0, zc), Vector3(xv + 5.0, 0, zc),
				Vector3(xv, 0, zc - 4.5), Vector3(xv, 0, zc + 4.5)]
		var free := true
		for s: Vector3 in spots:
			if not is_clear(s, 1.4) or g(s.x, s.z) < 0.45:
				free = false
				break
		if not free:
			continue
		if place("volleyball_net", at(xv, zc, 0.0), {"no_occ": true, "tag": "set_piece"}) >= 0:
			for s: Vector3 in spots:
				sys.call("reserve", s, 2.2)
			break
	var towers := [100.0, 196.0]
	var x := 62.0
	var k := 0
	while x < 236.0:
		# waterline at this x: first point south of the boardwalk below 0.25 m
		var zw := 236.0
		while zw < 300.0 and g(x, zw) > 0.25:
			zw += 1.0
		var z0 := 240.0
		var z1 := zw - 5.0
		var tower := false
		for tx: float in towers:
			if absf(x - tx) < 4.0:
				tower = true
		if tower and z1 - z0 > 8.0:
			# the ramp is the way up: a side ladder would end at the platform railing (no top-out)
			var zt := lerpf(z0, z1, 0.55)
			place("lifeguard_tower", at(x, zt, 0.0), {"r": 4.0, "tag": "set_piece"})
		elif z1 - z0 > 4.0 and rng.randf() < 0.8:
			var zu := rng.randf_range(z0 + 1.0, z1)
			if g(x, zu) > 0.45 and is_clear(Vector3(x, 0, zu), 2.0):
				place("beach_umbrella", at(x, zu, rng.randf() * TAU), {"r": 1.6, "tag": "set_piece"})
				for j in (1 + int(rng.randf() < 0.6)):
					var lx := x - 1.0 + j * 1.1
					place("lounger", at(lx, zu + 1.5, PI + rng.randf_range(-0.12, 0.12)), {"no_occ": true, "tag": "set_piece"})
		x += 8.0
		k += 1
	place("vending_machine", at(48.5, 239.0, PI * 0.5), {"r": 0.7, "tag": "furniture"})
	place("bin", at(120.0, 237.4, PI), {"r": 0.4, "tag": "furniture"})
	place("bin", at(210.0, 237.4, PI), {"r": 0.4, "tag": "furniture"})


# ---------------------------------------------------------------------------------------------
# residential park: gazebo, playground, picnic tables, park lamps, bins
# ---------------------------------------------------------------------------------------------

func _park() -> void:
	var lot := find_lot("park", "residential")
	if lot.is_empty():
		return
	var c: Vector3 = lot["center"]
	var size: Vector2 = lot["size"]
	# the lot's long axis is z (66 m); the cross path splits it at the middle
	var north := Vector3(c.x, 0.0, c.z - size.y * 0.25)
	var south := Vector3(c.x, 0.0, c.z + size.y * 0.25)
	place("gazebo", at(north.x, north.z, 0.0), {"r": 3.6, "tag": "set_piece"})
	place("playground_slide", at(south.x - 4.0, south.z + 1.0, -PI * 0.5), {"r": 3.0, "tag": "set_piece"})
	for k in 3:
		var p := Vector3(south.x + 4.5, 0.0, south.z - 8.0 + k * 7.0)
		if path_dist(p) > 2.6:
			place("picnic_table", at(p.x, p.z, rng.randf_range(-0.2, 0.2)), {"r": 1.4, "tag": "set_piece"})
	var mk: Variant = cat.call("marker", "street_lamp_b", "Light")
	var local: Transform3D = mk if mk != null else Transform3D(Basis.IDENTITY, Vector3(0, 4.2, 0))
	for dz: float in [-27.0, -9.0, 9.0, 27.0]:
		for dx: float in [-8.6, 8.6]:
			var p := Vector3(c.x + dx, 0.0, c.z + dz)
			# slide inward until the lamp stands on the lawn just beside the path
			var tries := 0
			while path_dist(p) < 1.7 and tries < 6:
				p.x -= signf(dx) * 0.7
				tries += 1
			if path_dist(p) < 1.7:
				continue
			var i := place("street_lamp_b", at(p.x, p.z, 0.0), {"r": 0.5, "tag": "lamp"})
			if i >= 0:
				sys.call("add_lamp_light", i, local, Color(1.0, 0.86, 0.62), 11.0, 2.2)
	for dz: float in [-15.0, 15.0]:
		var p := Vector3(c.x + 9.2, 0.0, c.z + dz)
		place("bin", at(p.x, p.z, -PI * 0.5), {"r": 0.4, "tag": "furniture"})


# ---------------------------------------------------------------------------------------------
# downtown plaza: fountain, statue, planters, lamps, trees in grates, bollards, kiosks
# ---------------------------------------------------------------------------------------------

func _plaza() -> void:
	var lot := find_lot("plaza", "downtown")
	if lot.is_empty():
		return
	var c: Vector3 = lot["center"]
	var size: Vector2 = lot["size"]
	var yaw := float(lot["yaw"])
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	# the fountain takes the middle of the square unless the plaza's named location (a spawn / teleport
	# point) is there: then it moves along the long axis
	var fc := c
	var pl := loc("downtown_plaza")
	if pl.origin != Vector3.INF and Vector2(pl.origin.x - c.x, pl.origin.z - c.z).length() < 7.0:
		fc = lot_point(lot, 0.0, hz * 0.45)     # >= 12 m: a player teleported there can walk off freely
	place("fountain", at(fc.x, fc.z, 0.0), {"r": 3.6, "no_occ": true, "tag": "set_piece"})
	sys.call("reserve", fc, 3.6)
	# keep a clear 8 m lane ahead of the named location (players / vehicles teleported there head off along
	# its facing; the lead's int_slice drives a car out that way)
	if pl.origin != Vector3.INF:
		var ahead := -pl.basis.z
		ahead.y = 0.0
		ahead = ahead.normalized()
		var t := -3.0
		while t < 40.0:
			var q := pl.origin + ahead * t
			if in_lot_rect(lot, q, 1.0):
				sys.call("reserve", q, 4.0)
			t += 3.0
	# the sculpture: first free quarter of the square (off the walk paths and the clear lane)
	for q: Vector2 in [Vector2(-0.45, -0.5), Vector2(0.45, -0.5), Vector2(-0.45, 0.5), Vector2(0.45, 0.5),
			Vector2(-0.6, 0.0), Vector2(0.6, 0.0), Vector2(0.0, -0.6)]:
		var sp := lot_point(lot, hx * q.x, hz * q.y)
		if path_dist(sp) > 3.0 and is_clear(sp, 2.6) and fc.distance_to(Vector3(sp.x, fc.y, sp.z)) > 9.0:
			if place("park_statue", at(sp.x, sp.z, yaw + (PI if q.y > 0.0 else 0.0)), {"r": 2.6, "tag": "set_piece"}) >= 0:
				break
	var mk: Variant = cat.call("marker", "street_lamp_b", "Light")
	var local: Transform3D = mk if mk != null else Transform3D(Basis.IDENTITY, Vector3(0, 4.2, 0))
	# ring of lamps and planters around the fountain
	for k in 8:
		var a := k * TAU / 8.0 + PI / 8.0
		var p := fc + Vector3(cos(a), 0.0, sin(a)) * 9.0
		if path_dist(p) < 1.2 or (pl.origin != Vector3.INF and p.distance_to(Vector3(pl.origin.x, p.y, pl.origin.z)) < 2.0):
			continue
		if k % 2 == 0:
			var i := place("street_lamp_b", at(p.x, p.z, -a), {"r": 0.5, "tag": "lamp"})
			if i >= 0:
				sys.call("add_lamp_light", i, local, Color(1.0, 0.85, 0.6), 12.0, 2.4)
		else:
			place("planter", at(p.x, p.z, a), {"r": 0.75, "tag": "furniture"})
	# benches facing the fountain between the lamps and planters
	for k in 4:
		var a := k * TAU / 4.0
		var p := fc + Vector3(cos(a), 0.0, sin(a)) * 6.4
		if path_dist(p) > 1.0:
			place("bench", at(p.x, p.z, atan2(cos(a), sin(a))), {"r": 0.9, "tag": "furniture"})
	# a seating strip across the half opposite the fountain: planters with benches (facing the square)
	# between them, two lamps behind the benches
	for k in 5:
		var lx := lerpf(-hx * 0.55, hx * 0.55, k / 4.0)
		var p := lot_point(lot, lx, -hz * 0.62)
		if path_dist(p) < 1.6:
			continue
		if k % 2 == 0:
			place("planter", at(p.x, p.z, yaw), {"r": 0.75, "tag": "furniture"})
		else:
			place("bench", at(p.x, p.z, yaw + PI), {"r": 0.9, "tag": "furniture"})
			var bp := lot_point(lot, lx, -hz * 0.62 - 1.6)
			var li := place("street_lamp_b", at(bp.x, bp.z, yaw), {"r": 0.5, "tag": "lamp"})
			if li >= 0:
				sys.call("add_lamp_light", li, local, Color(1.0, 0.85, 0.6), 12.0, 2.4)
	# two rows of trees in grates along the long sides
	for side: float in [-1.0, 1.0]:
		var lz := -hz + 8.0
		while lz < hz - 6.0:
			var p := lot_point(lot, side * (hx - 5.0), lz)
			if path_dist(p) > 2.0 and is_clear(p, 1.5):
				if place("tree_small_a", at(p.x, p.z, rng.randf() * TAU), {"r": 1.2, "tag": "tree_street", "lod": false}) >= 0:
					place("tree_grate", at(p.x, p.z, 0.0, 0.002), {"no_occ": true, "tag": "furniture"})
			lz += 11.0
	# bollards along the edges, gaps where walk paths enter
	for e: Array in [[Vector2(-hx + 0.6, -hz + 0.6), Vector2(hx - 0.6, -hz + 0.6)], [Vector2(-hx + 0.6, hz - 0.6), Vector2(hx - 0.6, hz - 0.6)],
			[Vector2(-hx + 0.6, -hz + 0.6), Vector2(-hx + 0.6, hz - 0.6)], [Vector2(hx - 0.6, -hz + 0.6), Vector2(hx - 0.6, hz - 0.6)]]:
		var a2: Vector2 = e[0]
		var b2: Vector2 = e[1]
		var n := int(a2.distance_to(b2) / 3.0)
		for k in range(1, n):
			var q := a2.lerp(b2, float(k) / n)
			var p := lot_point(lot, q.x, q.y)
			if path_dist(p) < 2.6 or not is_clear(p, 0.4):
				continue
			place("bollard_light" if k % 4 == 0 else "bollard", at(p.x, p.z, yaw), {"r": 0.3, "tag": "furniture"})
	for it: Array in [["atm", -hx + 2.0, hz * 0.3, PI * 0.5], ["phone_kiosk", hx - 2.0, -hz * 0.3, -PI * 0.5],
			["vending_machine", hx - 2.0, hz * 0.35, -PI * 0.5], ["bike_rack", -hx + 2.5, -hz * 0.35, PI * 0.5],
			["bin", -hx + 3.0, 0.0, PI * 0.5], ["bin", hx - 3.0, 0.0, -PI * 0.5]]:
		var p := lot_point(lot, float(it[1]), float(it[2]))
		if path_dist(p) > 1.6:
			place(String(it[0]), at(p.x, p.z, yaw + float(it[3])), {"tag": "furniture"})


# ---------------------------------------------------------------------------------------------
# Signal Hill viewpoint
# ---------------------------------------------------------------------------------------------

func _hill() -> void:
	var v := loc("hill_viewpoint")
	if v.origin == Vector3.INF:
		return
	var fwd := -v.basis.z.normalized()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var yaw := atan2(-fwd.x, -fwd.z)
	var bp := v.origin + fwd * 1.4
	place("viewpoint_binoculars", at(bp.x, bp.z, yaw), {"no_occ": true, "tag": "set_piece"})
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	for k: int in [-1, 0, 1]:
		var p := v.origin + fwd * 3.6 + right * (k * 4.0)
		var y0 := g(p.x, p.z)
		var y1 := g(p.x + fwd.x * 3.0, p.z + fwd.z * 3.0)
		if y0 - y1 > 0.4:
			place("fence_metal", Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y0, p.z)), {"no_occ": true, "tag": "fence"})
	sys.call("reserve", v.origin, 6.0)
	var top := loc("hill_top")
	if top.origin != Vector3.INF:
		sys.call("reserve", top.origin, 8.0)


# ---------------------------------------------------------------------------------------------
# airport: runway edge / threshold lights, windsock, signs, stairs, fuel truck, radar, beacons
# ---------------------------------------------------------------------------------------------

func _airport() -> void:
	var x := RUNWAY_X0 + 2.0
	while x <= RUNWAY_X1 - 2.0:
		for side: float in [-1.0, 1.0]:
			var z := RUNWAY_Z + side * (RUNWAY_HW + 0.8)
			place("runway_light", at(x, z, 0.0), {"no_occ": true, "tag": "airport"})
		x += 16.0
	for xe: float in [RUNWAY_X0 - 1.5, RUNWAY_X1 + 1.5]:
		var z2 := RUNWAY_Z - RUNWAY_HW + 1.0
		while z2 <= RUNWAY_Z + RUNWAY_HW - 1.0:
			place("runway_light", at(xe, z2, 0.0), {"no_occ": true, "tag": "airport"})
			z2 += 2.75
	var ws := Transform3D(Basis.IDENTITY, Vector3(40.0, g(40.0, -283.0), -283.0))
	if g(40.0, -283.0) > 1.0:
		sys.call("add_scene_piece", "windsock", ws, "Sock", "wind")
	for p: Vector2 in [Vector2(-139.0, -248.5), Vector2(119.0, -248.5), Vector2(-121.0, -248.5), Vector2(101.0, -248.5)]:
		place("runway_sign", at(p.x, p.y, PI * 0.5), {"r": 1.0, "tag": "airport"})
	place("aircraft_stairs", at(-232.0, -233.5, 0.0), {"r": 2.5, "tag": "airport"})
	place("fuel_truck_static", at(-160.0, -235.0, PI * 0.5), {"r": 3.5, "tag": "airport"})
	for rp: Vector2 in [Vector2(-60.0, -284.0), Vector2(-20.0, -284.0), Vector2(150.0, -284.0)]:
		if g(rp.x, rp.y) > 1.2 and is_clear(Vector3(rp.x, 0, rp.y), 3.0):
			sys.call("add_scene_piece", "radar_dish", Transform3D(Basis.IDENTITY, Vector3(rp.x, g(rp.x, rp.y), rp.y)), "Dish", "spin")
			break
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var p := Vector3(AIRPORT_HELIPAD.x + cos(a) * 10.3, 0.0, AIRPORT_HELIPAD.y + sin(a) * 10.3)
		if not bool(sys.call("on_carriageway", p)):
			sys.call("add_scene_piece", "helipad_beacon", at(p.x, p.z, -a), "Lamp", "beacon")


# ---------------------------------------------------------------------------------------------
# shipwreck + wreck dressing on the seabed
# ---------------------------------------------------------------------------------------------

func _wreck() -> void:
	var w := loc("shipwreck")
	if w.origin == Vector3.INF:
		return
	var p := w.origin
	var xf := Transform3D(w.basis.orthonormalized(), Vector3(p.x, g(p.x, p.z), p.z))
	place("shipwreck", xf, {"no_occ": true, "road_ok": true, "tag": "set_piece"})
	sys.call("reserve", p, 11.0)
	var fwd := -xf.basis.z
	var right := xf.basis.x
	var ap := p + fwd * 16.0 + right * 4.0
	place("anchor", at(ap.x, ap.z, rng.randf() * TAU), {"r": 1.2, "tag": "underwater"})
	for k in 4:
		var q := p + right * rng.randf_range(-11.0, 11.0) + fwd * rng.randf_range(-15.0, 15.0)
		if q.distance_to(p) < 9.0:
			q = p + (q - p).normalized() * 12.0
		place("sunken_crate", at(q.x, q.z, rng.randf() * TAU), {"r": 1.0, "tag": "underwater"})


# ---------------------------------------------------------------------------------------------
# buoys (swim zone, harbour mouth) and moored fishing boats at the docks
# ---------------------------------------------------------------------------------------------

func _water() -> void:
	var pts: Array[Vector2] = []
	var x := 70.0
	while x <= 232.0:
		pts.append(Vector2(x, 284.0))
		x += 27.0
	for xb: float in [-240.0, -180.0, -120.0, -60.0]:
		pts.append(Vector2(xb, 306.0))
	for q: Vector2 in pts:
		if float(world.call("get_water_depth", q.x, q.y)) < 2.5:
			continue
		place("buoy", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q.x, water_y(), q.y)),
				{"r": 1.0, "road_ok": true, "tag": "set_piece"})
	for z: float in [30.0, 140.0]:
		var bx := QUAY_X - 3.2
		if float(world.call("get_water_depth", bx, z)) > 1.6 and is_clear(Vector3(bx, 0, z), 3.0):
			place("fishing_boat_static", Transform3D(Basis(Vector3.UP, PI if z > 100.0 else 0.0), Vector3(bx, water_y(), z)),
					{"r": 3.0, "road_ok": true, "tag": "set_piece"})


# ---------------------------------------------------------------------------------------------
# ladders
# ---------------------------------------------------------------------------------------------

## fire_escape_ladder sections against a wall. `wall_xf`: origin at the FOOT of the ladder plane
## (0.2 m off the wall), -Z = climb side (away from the wall). `visual_h` = total ladder length,
## `climb_h` = height to the top exit, `top_y` = world y of the top exit.
func _mount_ladder(wall_xf: Transform3D, visual_h: float, climb_h: float, top_y: float) -> void:
	var n := maxi(1, roundi(visual_h / 4.0))
	var sy := visual_h / (n * 4.0)
	var basis := wall_xf.basis.orthonormalized()
	for k in n:
		var o := wall_xf.origin + Vector3(0.0, k * 4.0 * sy, 0.0)
		place("fire_escape_ladder", Transform3D(basis.scaled_local(Vector3(1.0, sy, 1.0)), o),
				{"no_occ": true, "road_ok": true, "tag": "ladder"})
	# group "ladder" node (W2.4): origin ON the rail line at the foot (PlayerStateLadder keeps the body
	# STAND_OFF = 0.36 m behind that line, like the city builder's ladders), +Z = climb side, the climber
	# faces local -Z = the wall
	var climb_dir := -basis.z
	var foot := Transform3D(Basis(Vector3.UP, atan2(climb_dir.x, climb_dir.z)), wall_xf.origin)
	var top := wall_xf.origin - climb_dir * 0.9
	top.y = top_y
	sys.call("add_ladder", foot, climb_h, top)


func _existing_ladder_near(p: Vector3, r: float) -> bool:
	for n: Node in (sys as Node).get_tree().get_nodes_in_group("ladder"):
		var n3 := n as Node3D
		if n3 != null and n3.global_position.distance_to(p) < r:
			return true
	return false


func _ladders() -> void:
	# quay walls and pier heads (world "ladder" points: origin on the wall face at sea level, -Z into the wall)
	for x: Transform3D in sys.call("spawn_points", "ladder"):
		var p := x.origin
		if _existing_ladder_near(p, 1.5):
			continue
		var into := -x.basis.z.normalized()
		var deck := g(p.x - into.x * 1.5, p.z - into.z * 1.5)
		if deck < 0.5:
			deck = 2.52
		var climb := -into
		var wall_basis := Basis(Vector3.UP, atan2(-climb.x, -climb.z))     # -Z = away from the wall
		var bottom := Vector3(p.x, deck - 4.0, p.z) + climb * 0.2
		_mount_ladder(Transform3D(wall_basis, bottom), 4.0, deck - water_y(), deck)
		# the climber starts in the water: move the group node to sea level
		var lad: Array = sys.call("get_ladders")
		if not lad.is_empty():
			var ln: Node3D = lad[lad.size() - 1]
			ln.global_position.y = water_y() - 0.2
			ln.set_meta(&"height", deck - water_y() + 0.2)
			ln.set_meta(&"water", true)
	# radio mast: its caged ladder is part of the landmark mesh; add only the climb node
	var city := Game.get_system("city")
	if city != null and city.has_method("has_landmark_marker") and bool(city.call("has_landmark_marker", "radio_mast", "Ladder_Bottom")):
		var lb: Transform3D = city.call("get_landmark_marker", "radio_mast", "Ladder_Bottom")
		if not _existing_ladder_near(lb.origin, 1.5):
			var lt: Transform3D = lb
			if bool(city.call("has_landmark_marker", "radio_mast", "Ladder_Top")):
				lt = city.call("get_landmark_marker", "radio_mast", "Ladder_Top")
			sys.call("add_ladder", lb, maxf(lt.origin.y - lb.origin.y, 2.0), lt.origin)
	# building walls (needs the city builder): a few low/mid buildings downtown and in the industrial district
	if city == null or not city.has_method("get_buildings"):
		return
	var mf := _building_manifest()
	var buildings: Array = city.call("get_buildings")
	var count := 0
	for b: Dictionary in buildings:
		if count >= 12:
			break
		var bcat := String(b.get("category", ""))
		if not (bcat in ["storefront", "warehouse", "apartment", "office"]):
			continue
		var xf: Transform3D = b.get("transform", Transform3D.IDENTITY)
		var dist := String(world.call("get_district", xf.origin))
		if not (dist in ["downtown", "industrial", "midtown"]):
			continue
		if bool(b.get("plinth", false)):
			continue        # a plinth on falling ground: the wall does not reach the ground at the back
		var bid := String(b.get("id", ""))
		var e: Dictionary = mf.get(bid, {})
		var roof := float(e.get("roof_height", b.get("height", 0.0)))
		if roof < 4.5 or roof > 21.0:
			continue
		var box := _main_box(e, b)
		if box.size == Vector3.ZERO:
			continue
		var tris := _back_triangles(bid, e, box.end.z)
		# back wall (local +Z face), near one corner (the other corner if the first one is not clean)
		var fracs := [0.25, 0.75] if count % 2 == 0 else [0.75, 0.25]
		for frac: float in fracs:
			var lx := box.position.x + box.size.x * frac
			var wall_z := box.end.z
			if not tris.is_empty():
				# the real wall face from the mesh; skip spots under a cornice / overhang / ground-floor
				# canopy (the ladder plane is only 0.2 m off the wall and would run through them)
				var wc := _wall_check(tris, lx, roof)
				if wc.is_empty() or not bool(wc["clean"]):
					continue
				wall_z = float(wc["wall"])
				if absf(wall_z - box.end.z) > 0.35:
					continue    # a balcony / recess at mid height, not the plain wall

			var foot_l := Vector3(lx, 0.0, wall_z + 0.2)
			var foot := xf * foot_l
			var clear := xf * (foot_l + Vector3(0.0, 0.0, 1.6))
			foot.y = g(foot.x, foot.z)
			if absf(foot.y - xf.origin.y) > 0.6:
				continue
			if bool(sys.call("on_carriageway", clear, 0.5)) or not is_clear(clear, 0.7):
				continue
			if _blocked_by_buildings(clear, buildings, b):
				continue
			var basis := xf.basis.orthonormalized() * Basis(Vector3.UP, PI)     # -Z away from the wall (+Z local)
			var top_y := xf.origin.y + roof
			_mount_ladder(Transform3D(basis, foot), top_y - foot.y + 1.0, top_y - foot.y, top_y)
			sys.call("reserve", clear, 0.8)
			count += 1
			break


func _building_manifest() -> Dictionary:
	var out := {}
	var dir := "res://gta/generated/models/buildings/"
	for f in DirAccess.get_files_at(dir):
		if not (f.begins_with("manifest") and f.ends_with(".json")):
			continue
		var fa := FileAccess.open(dir + f, FileAccess.READ)
		if fa == null:
			continue
		var data: Variant = JSON.parse_string(fa.get_as_text())
		if typeof(data) != TYPE_DICTIONARY:
			continue
		for e: Variant in (data as Dictionary).get("buildings", []):
			if typeof(e) == TYPE_DICTIONARY:
				out[String((e as Dictionary).get("id", ""))] = e
	return out


## Main collision box of a building in its local space (manifest collision_boxes[0]: cx, cy, cz, sx, sy, sz).
func _main_box(e: Dictionary, b: Dictionary) -> AABB:
	var boxes: Array = e.get("collision_boxes", [])
	if not boxes.is_empty() and (boxes[0] as Array).size() >= 6:
		var a: Array = boxes[0]
		var size := Vector3(float(a[3]), float(a[4]), float(a[5]))
		return AABB(Vector3(float(a[0]), float(a[1]), float(a[2])) - size * 0.5, size)
	var fp: Vector2 = b.get("footprint", Vector2.ZERO)
	if fp == Vector2.ZERO:
		return AABB()
	return AABB(Vector3(-fp.x * 0.5, 0.0, -fp.y * 0.5), Vector3(fp.x, float(b.get("height", 6.0)), fp.y))


## Triangles of a building's meshes near its back face (building space), cached per building id, as
## packed [xmin, xmax, ymin, ymax, zmax] rows. Empty when the GLB cannot be read (callers then trust
## the manifest collision box).
func _back_triangles(id: String, e: Dictionary, back_z: float) -> PackedFloat32Array:
	if _back_tris.has(id):
		return _back_tris[id]
	var out := PackedFloat32Array()
	var file := String(e.get("file", ""))
	if file != "":
		var ex: Dictionary = CatalogScript.extract_scene("res://gta/generated/models/buildings/" + file)
		if not ex.is_empty():
			for pname: String in ex["order"]:
				var part: Array = ex["parts"][pname]
				var mesh := part[0] as Mesh
				if mesh == null:
					continue
				var xf: Transform3D = part[1]
				var f := mesh.get_faces()
				var k := 0
				while k + 2 < f.size():
					var a := xf * f[k]
					var b := xf * f[k + 1]
					var c := xf * f[k + 2]
					k += 3
					var zmax := maxf(a.z, maxf(b.z, c.z))
					if zmax < back_z - 0.8:
						continue
					out.append(minf(a.x, minf(b.x, c.x)))
					out.append(maxf(a.x, maxf(b.x, c.x)))
					out.append(minf(a.y, minf(b.y, c.y)))
					out.append(maxf(a.y, maxf(b.y, c.y)))
					out.append(zmax)
	_back_tris[id] = out
	return out


## Back wall at local x = lx: {"wall": z of the wall face at mid height, "clean": nothing near the ladder
## line (cornice, roof overhang, canopy, plinth) stands out more than 0.14 m beyond it}; {} if the mesh
## has no wall there (a gap / recess).
func _wall_check(tris: PackedFloat32Array, lx: float, roof: float) -> Dictionary:
	var low := -INF
	var mid := -INF
	var top := -INF
	var y_mid0 := roof * 0.3
	var y_mid1 := roof * 0.7
	var k := 0
	while k + 4 < tris.size():
		var x0 := tris[k]
		var x1 := tris[k + 1]
		var y0 := tris[k + 2]
		var y1 := tris[k + 3]
		var z := tris[k + 4]
		k += 5
		if x1 < lx - 0.35 or x0 > lx + 0.35 or y1 < 0.35 or y0 > roof + 1.6:
			continue
		if y0 < y_mid0:
			low = maxf(low, z)
		if y1 > y_mid0 and y0 < y_mid1:
			mid = maxf(mid, z)
		if y1 > y_mid1:
			top = maxf(top, z)
	if mid == -INF:
		return {}
	return {"wall": mid, "clean": low <= mid + 0.14 and top <= mid + 0.14}


func _blocked_by_buildings(p: Vector3, buildings: Array, own: Dictionary) -> bool:
	for b: Dictionary in buildings:
		if b == own:
			continue
		var xf: Transform3D = b.get("transform", Transform3D.IDENTITY)
		if xf.origin.distance_to(p) > 40.0:
			continue
		var fp: Vector2 = b.get("footprint", Vector2.ZERO)
		var lp := xf.affine_inverse() * p
		if absf(lp.x) < fp.x * 0.5 + 1.0 and absf(lp.z) < fp.y * 0.5 + 1.0:
			return true
	return false


# ---------------------------------------------------------------------------------------------
# loose props: cones and delineators lining the stunt ramp run-ups, plastic / crowd barriers on the
# docks, shopping carts at the beach car park
# ---------------------------------------------------------------------------------------------

func _loose_extras() -> void:
	for n: String in ["stunt_ramp_1", "stunt_ramp_3"]:
		var xf := loc(n)
		if xf.origin == Vector3.INF:
			continue
		var fwd := -xf.basis.z.normalized()
		var right := xf.basis.x.normalized()
		for k in 4:
			for side: float in [-1.0, 1.0]:
				var p := xf.origin - fwd * (9.0 + k * 5.0) + right * side * 3.6
				var id := "cone" if k % 2 == 0 else "delineator"
				if not bool(sys.call("on_carriageway", p, 4.2)):     # 4.2 m: also keeps them off the sidewalks
					place(id, at(p.x, p.z, 0.0), {"no_occ": true, "tag": "loose"})
	var r2 := loc("stunt_ramp_2")
	if r2.origin != Vector3.INF:
		var fwd2 := -r2.basis.z.normalized()
		var right2 := r2.basis.x.normalized()
		for k in 3:
			var p := r2.origin + fwd2 * (14.0 + k * 3.0) + right2 * 3.4
			place("barrier_plastic" if k != 1 else "barrier_fence", Transform3D(r2.basis.orthonormalized(), Vector3(p.x, g(p.x, p.z), p.z)),
					{"no_occ": true, "tag": "loose"})
	var lot := find_lot("parking", "beach")
	if not lot.is_empty():
		var size: Vector2 = lot["size"]
		for k in 3:
			var p := lot_point(lot, -size.x * 0.5 + 1.2 + k * 0.8, size.y * 0.5 - 1.0)
			if is_clear(p, 0.5):
				place("shopping_cart", at(p.x, p.z, float(lot["yaw"]) + rng.randf_range(-0.4, 0.4)), {"r": 0.4, "tag": "loose"})
