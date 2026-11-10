class_name CitySpecial
extends RefCounted
## One-off areas: Palm Park, the promenade + beach + pier, marina and docks, the port,
## Vesper Airfield, Lookout Hill, the sea floor and the map-edge walls.

const H := CityLayout.CURB_H

static func generate(cb: CityBuilder) -> void:
	_park(cb)
	_promenade(cb)
	_marina(cb)
	_port(cb)
	_airfield(cb)
	_hill(cb)
	_seabed(cb)
	_edges(cb)

## Sloped slab between two points (top edge centre -> bottom edge centre) with collision.
static func ramp(cb: CityBuilder, top: Vector3, bottom: Vector3, width: float, color_name := "concrete") -> void:
	var d := bottom - top
	var flat := Vector3(d.x, 0.0, d.z).normalized()
	var side := Vector3(-flat.z, 0.0, flat.x) * (width * 0.5)
	var a := top - side
	var b := top + side
	var c := bottom + side
	var e := bottom - side
	var nrm := (b - a).cross(e - a).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	var col := GeoBuf.pal(color_name)
	cb.lot_buf.quad(a, b, c, e, nrm, col, 0.0)
	var low := minf(top.y, bottom.y) - 1.2
	cb.lot_buf.quad(Vector3(a.x, low, a.z), a, e, Vector3(e.x, low, e.z), -side.normalized(), col, 0.0)
	cb.lot_buf.quad(Vector3(b.x, low, b.z), b, c, Vector3(c.x, low, c.z), side.normalized(), col, 0.0)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([a, b, c, e, Vector3(a.x, low, a.z), Vector3(b.x, low, b.z), Vector3(c.x, low, c.z), Vector3(e.x, low, e.z)])
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cb.world.ground_body.add_child(cs)

static func solid_box(cb: CityBuilder, lo: Vector3, hi: Vector3, color_name: String, pattern := 0.0, top_color := "") -> void:
	cb.lot_buf.box(lo, hi, GeoBuf.pal(color_name), pattern, 1.0, GeoBuf.pal(top_color) if top_color != "" else null)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = hi - lo
	cs.shape = bs
	cs.position = (lo + hi) * 0.5
	cb.world.ground_body.add_child(cs)

# ---------------------------------------------------------------- Palm Park
static func _park(cb: CityBuilder) -> void:
	var b := cb.layout.block_by_id("B34_BC")
	if b.is_empty():
		return
	var r: Rect2 = b["rect"]
	var c := r.get_center()
	# paths: a cross and a ring
	cb.lot(r.position.x, c.y - 1.6, r.end.x, c.y + 1.6, "sand", 0.0)
	cb.lot(c.x - 1.6, r.position.y, c.x + 1.6, r.end.y, "sand", 0.0)
	for i in 24:
		var a0 := TAU * float(i) / 24.0
		var a1 := TAU * float(i + 1) / 24.0
		var p0 := c + Vector2(cos(a0), sin(a0)) * 22.0
		var p1 := c + Vector2(cos(a1), sin(a1)) * 22.0
		var q0 := c + Vector2(cos(a0), sin(a0)) * 24.6
		var q1 := c + Vector2(cos(a1), sin(a1)) * 24.6
		cb.lot_buf.quad(Vector3(p0.x, H + 0.014, p0.y), Vector3(p1.x, H + 0.014, p1.y), Vector3(q1.x, H + 0.014, q1.y),
			Vector3(q0.x, H + 0.014, q0.y), Vector3.UP, GeoBuf.pal("sand"), 0.0)
	cb.landmark("lm_gazebo", Vector3(c.x, H, c.y), "S", {"label": "Palm Park"})
	# pond in the north-west quadrant
	var pc := c + Vector2(-19.0, -19.0)
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * float(i) / 14.0
		pts.append(pc + Vector2(cos(a) * (7.5 + sin(a * 3.0) * 1.2), sin(a) * (5.5 + cos(a * 2.0) * 1.0)))
	cb.lot_buf.poly_up(pts, H + 0.02, GeoBuf.pal("ice_blue"), 0.0)
	for i in 7:
		var a2 := TAU * float(i) / 7.0 + 0.4
		cb.deco("reeds" if i % 2 == 0 else "rock_a", Vector3(pc.x + cos(a2) * 8.2, H, pc.y + sin(a2) * 6.3), cb.rng.randf() * TAU, cb.rng.randf_range(0.6, 0.9), false, 120.0)
	# trees, benches, lamps, picnic tables
	var kinds := ["tree_oak_a", "tree_oak_b", "tree_round", "tree_palm_a", "tree_oak_a"]
	var placed := 0
	var guard := 0
	while placed < 30 and guard < 400:
		guard += 1
		var p := Vector2(cb.rng.randf_range(r.position.x + 3.0, r.end.x - 3.0), cb.rng.randf_range(r.position.y + 3.0, r.end.y - 3.0))
		var dc := p.distance_to(c)
		if absf(p.x - c.x) < 3.5 or absf(p.y - c.y) < 3.5 or absf(dc - 23.3) < 3.0 or dc < 7.0 or p.distance_to(pc) < 10.0:
			continue
		cb.deco(kinds[cb.rng.randi() % kinds.size()], Vector3(p.x, H, p.y), cb.rng.randf() * TAU, cb.rng.randf_range(0.8, 1.2))
		placed += 1
	for i in 8:
		var a3 := TAU * (float(i) + 0.5) / 8.0
		var bp := c + Vector2(cos(a3), sin(a3)) * 26.2
		cb.prop("prop_bench", Vector3(bp.x, H, bp.y), CityBuilder.yaw_to(Vector3(c.x - bp.x, 0, c.y - bp.y)))
		if i % 2 == 0:
			var lp := c + Vector2(cos(a3 + 0.2), sin(a3 + 0.2)) * 20.6
			cb.prop("lamp_park", Vector3(lp.x, H, lp.y), 0.0)
	cb.prop("prop_picnic_table", Vector3(c.x + 14.0, H, c.y + 12.0), 0.5)
	cb.prop("prop_picnic_table", Vector3(c.x + 9.0, H, c.y + 16.0), 1.2)
	for i in 10:
		cb.deco("flower_patch", Vector3(c.x + cb.rng.randf_range(-6.0, 6.0) + (13.0 if i % 2 == 0 else -13.0), H, c.y + cb.rng.randf_range(8.0, 16.0)),
			cb.rng.randf() * TAU, 1.0, false, 70.0)
	# clipped hedges around the edge, open at the path ends and corners
	for side in 4:
		var n := int(r.size.x / 2.0)
		for i in n:
			var t := (float(i) + 0.5) * 2.0
			if absf(t - r.size.x * 0.5) < 3.0 or t < 5.0 or t > r.size.x - 5.0:
				continue
			var p2: Vector3
			match side:
				0: p2 = Vector3(r.position.x + t, H, r.position.y + 0.6)
				1: p2 = Vector3(r.position.x + t, H, r.end.y - 0.6)
				2: p2 = Vector3(r.position.x + 0.6, H, r.position.y + t)
				_: p2 = Vector3(r.end.x - 0.6, H, r.position.y + t)
			cb.deco("hedge", p2, 0.0 if side < 2 else PI * 0.5, 1.0, true, 140.0)
	cb.ped_areas.append({"rect": r.grow(-3.0), "y": H, "name": "Palm Park"})
	cb.locations["park"] = {"id": "park", "root": null, "markers": {}, "pos": Vector3(c.x, H, c.y)}

# ---------------------------------------------------------------- promenade, beach, pier
static func _promenade(cb: CityBuilder) -> void:
	var z_edge := Terrain.COAST_Z
	var x := -292.0
	var k := 0
	while x < 30.0:
		cb.deco("tree_palm_a" if k % 2 == 0 else "tree_palm_b", Vector3(x, H, 210.2), cb.rng.randf() * TAU, cb.rng.randf_range(0.9, 1.15))
		if k % 2 == 0:
			cb.prop("prop_bench", Vector3(x + 6.0, H, 217.6), 0.0)
		else:
			cb.prop("lamp_park", Vector3(x + 6.0, H, 219.8), 0.0)
		if k % 5 == 2:
			cb.prop("prop_bin", Vector3(x + 9.0, H, 219.6), 0.0)
		if k % 9 == 4:
			cb.prop("prop_vending", Vector3(x + 3.0, H, 209.0), PI)
		x += 13.0
		k += 1
	# sea-side railing with openings where ramps lead down to the sand
	var ramps := [-262.0, -214.0, -166.0, -118.0, -24.0, 12.0]
	var rx := -298.0
	while rx < 28.0:
		var mid := rx + 2.0
		var open := false
		for rp in ramps:
			if absf(mid - float(rp)) < 3.2:
				open = true
		if absf(mid + 60.0) < 5.0:
			open = true     # pier entrance
		if not open:
			cb.deco("prop_pier_rail", Vector3(mid, H, z_edge - 0.25), 0.0, 1.0, true, 160.0)
		rx += 4.0
	for rp in ramps:
		var bx := float(rp)
		var by := Terrain.sample(bx, z_edge + 6.5)
		ramp(cb, Vector3(bx, H, z_edge - 0.05), Vector3(bx, by - 0.05, z_edge + 6.5), 4.0, "concrete_light")
	# beach life
	for tx: float in [-232.0, -128.0, -8.0]:
		cb.prop("prop_lifeguard_tower", Vector3(tx, Terrain.sample(tx, 229.0), 229.0), 0.0, {"static": true, "tint_b": Color.html("d43d33")})
	var guard := 0
	var placed := 0
	while placed < 46 and guard < 400:
		guard += 1
		var px := cb.rng.randf_range(-292.0, 22.0)
		var pz := cb.rng.randf_range(224.5, 233.5)
		if absf(px + 60.0) < 7.0:
			continue
		var py := Terrain.sample(px, pz)
		if py < -0.85:
			continue
		var tint := cb.pick(CityBuilder.C_MID_B)
		match placed % 4:
			0:
				cb.prop("prop_umbrella", Vector3(px, py, pz), cb.rng.randf() * TAU, {"tint_a": tint, "static": true})
				cb.prop("prop_beach_chair", Vector3(px + 1.2, py, pz + 0.4), cb.rng.randf_range(2.6, 3.6))
			1: cb.prop("prop_towel", Vector3(px, py + 0.02, pz), cb.rng.randf() * TAU, {"tint_a": tint})
			2: cb.prop("prop_beach_chair", Vector3(px, py, pz), cb.rng.randf_range(2.6, 3.6))
			_: cb.prop("prop_surfboard", Vector3(px, py, pz), cb.rng.randf() * TAU, {"tint_a": tint})
		placed += 1
	cb.prop("prop_volleyball_net", Vector3(-180.0, Terrain.sample(-180.0, 229.0), 229.0), 0.0, {"static": true})
	cb.ped_areas.append({"rect": Rect2(-296.0, 209.0, 322.0, 11.0), "y": H, "name": "Promenade"})
	cb.ped_areas.append({"rect": Rect2(-290.0, 224.0, 310.0, 9.0), "y": -0.4, "name": "Coral Beach"})
	# --- the pier
	var pier_x := -60.0
	var zc := z_edge + 2.0
	var count := 0
	while zc < 296.0:
		for ox: float in [-2.0, 2.0]:
			cb.deco("prop_pier_deck", Vector3(pier_x + ox, H, zc), 0.0, 1.0, false, 0.0)
		if count % 1 == 0:
			cb.deco("prop_pier_rail", Vector3(pier_x - 3.85, H, zc), PI * 0.5, 1.0, false, 160.0)
			cb.deco("prop_pier_rail", Vector3(pier_x + 3.85, H, zc), PI * 0.5, 1.0, false, 160.0)
		if count % 4 == 1:
			cb.prop("lamp_park", Vector3(pier_x - 3.3, H, zc), 0.0)
		zc += 4.0
		count += 1
	# pier collision as two long solids (deck + invisible side rails) and a wider head platform
	var deck := BoxShape3D.new()
	deck.size = Vector3(8.0, 0.6, 296.0 - z_edge)
	var dcs := CollisionShape3D.new()
	dcs.shape = deck
	dcs.position = Vector3(pier_x, H - 0.3, (z_edge + 296.0) * 0.5)
	cb.world.ground_body.add_child(dcs)
	for sx: float in [-3.95, 3.95]:
		var rail := BoxShape3D.new()
		rail.size = Vector3(0.15, 1.1, 292.0 - z_edge)
		var rcs := CollisionShape3D.new()
		rcs.shape = rail
		rcs.position = Vector3(pier_x + sx, H + 0.55, (z_edge + 4.0 + 296.0) * 0.5)
		cb.world.ground_body.add_child(rcs)
	solid_box(cb, Vector3(pier_x - 14.0, H - 0.5, 270.0), Vector3(pier_x - 4.0, H, 296.0), "plank_gray", 2.0)
	solid_box(cb, Vector3(pier_x + 4.0, H - 0.5, 270.0), Vector3(pier_x + 14.0, H, 296.0), "plank_gray", 2.0)
	cb.landmark("lm_ferris_wheel", Vector3(pier_x + 9.0, H, 283.0), "W", {"label": "Pier"})
	cb.prop("prop_vending", Vector3(pier_x - 12.0, H, 273.0), PI * 0.5)
	cb.prop("prop_bench", Vector3(pier_x - 9.0, H, 292.0), PI)
	cb.prop("prop_bench", Vector3(pier_x - 6.0, H, 292.0), PI)
	cb.ped_areas.append({"rect": Rect2(pier_x - 3.4, z_edge + 2.0, 6.8, 70.0), "y": H, "name": "Pier"})
	cb.locations["pier"] = {"id": "pier", "root": null, "markers": {}, "pos": Vector3(pier_x, H, 290.0)}
	# lighthouse on the breakwater
	var ly := Terrain.sample(37.0, 284.0)
	cb.landmark("lm_lighthouse", Vector3(37.0, ly - 0.2, 284.0), "S", {"label": "Lighthouse"})
	for i in 14:
		var rz := 226.0 + float(i) * 4.6
		cb.deco("rock_b" if i % 3 == 0 else "rock_a", Vector3(37.0 + cb.rng.randf_range(-4.5, 4.5), Terrain.sample(37.0, rz) - 0.3, rz),
			cb.rng.randf() * TAU, cb.rng.randf_range(0.8, 1.6), true, 260.0)

# ---------------------------------------------------------------- marina
static func _marina(cb: CityBuilder) -> void:
	var z_edge := Terrain.COAST_Z
	cb.landmark("lm_boathouse", Vector3(134.0, H, 213.5), "S", {"label": "Marina"})
	var x := 46.0
	var k := 0
	while x < 208.0:
		cb.prop("prop_bollard", Vector3(x, H, z_edge - 0.7), 0.0)
		if k % 4 == 1:
			cb.prop("lamp_park", Vector3(x + 2.0, H, 209.2), 0.0)
		if k % 6 == 3:
			cb.prop("prop_bench", Vector3(x + 2.0, H, 210.0), PI)
		if k % 5 == 0:
			cb.prop("prop_lifebuoy_stand", Vector3(x + 3.0, H, z_edge - 1.2), 0.0)
		x += 7.0
		k += 1
	# floating finger docks with gangways
	var fingers := [58.0, 86.0, 114.0]
	var fi := 0
	for fx in fingers:
		var top_y := Terrain.SEA + 0.35
		ramp(cb, Vector3(fx, H, z_edge - 0.05), Vector3(fx, top_y, z_edge + 5.0), 1.8, "plank_gray")
		for i in 4:
			var fz := z_edge + 8.0 + float(i) * 6.0
			cb.prop("prop_dock_float", Vector3(fx, Terrain.SEA, fz), PI * 0.5, {"static": true})
			if i % 2 == 1:
				cb.prop("prop_dock_cleat", Vector3(fx + 0.8, top_y, fz), 0.0)
		# moored boats on both sides
		var boat := "boat_speed" if fi != 1 else "boat_dinghy"
		cb.spawn_vehicle(boat, Vector3(fx + 3.4, Terrain.SEA, z_edge + 14.0), PI, "marina")
		if fi == 0:
			cb.spawn_vehicle("boat_speed", Vector3(fx - 3.4, Terrain.SEA, z_edge + 22.0), PI, "marina")
		if fi == 2:
			cb.spawn_vehicle("boat_police", Vector3(fx - 3.6, Terrain.SEA, z_edge + 20.0), PI, "marina_police")
		fi += 1
	cb.locations["marina"] = {"id": "marina", "root": null, "markers": {}, "pos": Vector3(86.0, H, 216.0)}
	cb.ped_areas.append({"rect": Rect2(44.0, 208.5, 160.0, 11.5), "y": H, "name": "Marina"})
	for bx: float in [70.0, 100.0, 160.0, 190.0]:
		cb.prop("prop_buoy", Vector3(bx, Terrain.SEA, 268.0 + sin(bx) * 8.0), 0.0, {"static": true, "tint_a": Color.html("d43d33") if int(bx) % 20 == 10 else Color.html("3fa55a")})

# ---------------------------------------------------------------- port
static func _port(cb: CityBuilder) -> void:
	var b := cb.layout.block_by_id("PORT")
	if b.is_empty():
		return
	var r: Rect2 = b["rect"]
	for row in 3:
		var z := 132.0 + float(row) * 13.0
		for i in 5:
			var x := 226.0 + float(i) * 13.5
			var levels := 1 + cb.rng.randi() % 3
			for lv in levels:
				cb.prop("prop_container", Vector3(x, H + float(lv) * 2.6, z + cb.rng.randf_range(-0.15, 0.15)), PI * 0.5,
					{"tint_a": cb.pick(CityBuilder.C_MID_B), "static": true})
	cb.modular("ind", 220.0, 176.0, 6, 5, 2, "S", "W", {"label": "Port Shed"})
	cb.landmark("lm_crane", Vector3(262.0, H, 208.0), "N", {"label": "Docks", "tint_a": Color.html("ef7f2d")})
	cb.driveway(Vector3(CityLayout.AIR_X0 - CityLayout.SIDEWALK, 0.0, 195.0), Vector3(1, 0, 0), 9.0)
	cb.prop("prop_boom_gate", Vector3(216.0, H, 189.5), PI * 0.5, {"static": true})
	CityBlocks._yard_clutter(cb, 250.0, 176.0, 290.0, 200.0, 12)
	cb.spawn_vehicle("car_truck", Vector3(244.0, H, 196.0), PI * 0.5, "port")
	cb.prop("prop_floodlight", Vector3(288.0, H, 170.0), -PI * 0.5)
	cb.prop("prop_floodlight", Vector3(220.0, H, 168.0), PI * 0.5)
	cb.fence_run("fence_chain", Vector2(214.6, 122.0), Vector2(214.6, 188.0), H, 3.0)
	cb.fence_run("fence_chain", Vector2(214.6, 202.0), Vector2(214.6, 220.0), H, 3.0)
	cb.locations["port"] = {"id": "port", "root": null, "markers": {}, "pos": Vector3(240.0, H, 195.0)}

# ---------------------------------------------------------------- Vesper Airfield
const RW_X := 279.0
const RW_HW := 11.0
const RW_Z0 := -286.0
const RW_Z1 := 106.0
const TW_X := 252.0
const TW_HW := 6.0

static func _airfield(cb: CityBuilder) -> void:
	var y := H + 0.02
	RoadBuilder.strip(cb.road_buf, PackedVector3Array([Vector3(RW_X, 0, RW_Z0), Vector3(RW_X, 0, RW_Z1)]), RW_HW, RoadBuilder.T_RUNWAY, false, false, y)
	RoadBuilder.strip(cb.road_buf, PackedVector3Array([Vector3(TW_X, 0, -274.0), Vector3(TW_X, 0, 96.0)]), TW_HW, RoadBuilder.T_TAXI, false, false, y)
	for cz: float in [-268.0, -90.0, 90.0]:
		RoadBuilder.strip(cb.road_buf, PackedVector3Array([Vector3(TW_X + TW_HW, 0, cz), Vector3(RW_X - RW_HW, 0, cz)]), TW_HW, RoadBuilder.T_TAXI, false, false, y)
	# apron
	RoadBuilder.rect(cb.road_buf, 216.0, -246.0, TW_X - TW_HW, -96.0, y, RoadBuilder.T_APRON)
	RoadBuilder.rect(cb.road_buf, 214.0, -146.0, 216.0, -134.0, y, RoadBuilder.T_APRON)
	cb.driveway(Vector3(CityLayout.AIR_X0 - CityLayout.SIDEWALK, 0.0, -140.0), Vector3(1, 0, 0), 10.0)
	var hangar := cb.landmark("lm_hangar", Vector3(231.0, H, -264.0), "S", {"label": "Hangar", "tint_a": Color.html("8f989c"), "light_range": 16.0, "light_energy": 2.4})
	var spot := Vector3(231.0, H + 0.05, -262.0)
	if hangar != null:
		var m: Variant = cb.marker("lm_hangar", "spot")
		if m != null:
			spot = (m as Transform3D).origin + Vector3(0, 0.05, 0)
	cb.spawn_vehicle("plane_jet", spot, PI, "hangar")
	cb.spawn_vehicle("plane_prop", Vector3(236.0, H + 0.05, -222.0), -PI * 0.5, "apron")
	cb.spawn_vehicle("plane_prop", Vector3(236.0, H + 0.05, -200.0), -PI * 0.5, "apron")
	cb.landmark("lm_control_tower", Vector3(222.0, H, -104.0), "E", {"label": "Tower"})
	cb.landmark("lm_terminal", Vector3(228.0, H, -84.0), "N", {"label": "Airfield"})
	# two helipads on the apron
	var pads := [Vector3(236.0, H + 0.03, -122.0), Vector3(236.0, H + 0.03, -166.0)]
	for i in pads.size():
		var p: Vector3 = pads[i]
		var pad := BuildingFactory._module("buildings/roof/roof_helipad", "mesh")
		if pad.is_empty():
			cb.lot_buf.rect_up(p.x - 6.0, p.z - 6.0, p.x + 6.0, p.z + 6.0, p.y + 0.02, GeoBuf.pal("asphalt_dark"), 0.0)
		else:
			cb.prop("roof_helipad", p, 0.0, {"static": true})
		cb.spawn_vehicle("heli_civil", p + Vector3(0, 0.15, 0), 0.0, "helipad")
	cb.locations["airfield"] = {"id": "airfield", "root": null, "markers": {}, "pos": Vector3(224.0, H, -140.0),
		"runway_start": Vector3(RW_X, H, RW_Z1 - 14.0), "runway_dir": Vector3(0, 0, -1), "helipad": pads[0], "plane": Vector3(236.0, H, -222.0)}
	# perimeter fence with the gate gap, windsock, edge lights
	cb.fence_run("fence_chain", Vector2(214.6, -298.0), Vector2(214.6, -148.0), H, 3.0)
	cb.fence_run("fence_chain", Vector2(214.6, -132.0), Vector2(214.6, 118.0), H, 3.0)
	cb.fence_run("fence_chain", Vector2(216.0, 119.4), Vector2(295.0, 119.4), H, 3.0)
	cb.prop("prop_boom_gate", Vector3(215.2, H, -146.5), -PI * 0.5, {"static": true})
	cb.prop("prop_windsock", Vector3(264.5, H, -40.0), 0.0, {"static": true})
	var z := RW_Z0 + 6.0
	while z < RW_Z1:
		for sx: float in [-1.0, 1.0]:
			cb.deco("prop_runway_light", Vector3(RW_X + sx * (RW_HW + 0.8), H, z), 0.0, 1.0, false, 420.0)
		z += 28.0
	cb.prop("prop_generator", Vector3(244.0, H, -250.0), 0.0)
	cb.prop("prop_barrel_explosive", Vector3(219.0, H, -232.0), 0.0)
	cb.prop("prop_barrel_explosive", Vector3(220.2, H, -232.6), 0.0)

# ---------------------------------------------------------------- Lookout Hill
static func _hill(cb: CityBuilder) -> void:
	var peak := Terrain.PEAK
	var top := Terrain.sample(peak.x, peak.y)
	cb.landmark("lm_radio_tower", Vector3(peak.x - 7.0, top - 0.1, peak.y - 7.0), "S", {"label": "Radio Tower"})
	cb.landmark("lm_viewpoint", Vector3(peak.x + 9.5, top - 0.05, peak.y + 9.5), "S", {"yaw": -PI * 0.75, "label": "Lookout"})
	cb.prop("prop_picnic_table", Vector3(peak.x + 2.0, top, peak.y - 9.0), 0.4)
	cb.prop("lamp_park", Vector3(peak.x + 4.5, top, peak.y + 4.5), 0.0)
	cb.locations["lookout"] = {"id": "lookout", "root": null, "markers": {}, "pos": Vector3(peak.x, top, peak.y)}
	# woods: density from noise, kept clear of the road, the summit and steep slopes
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.018
	var guard := 0
	var trees := 0
	while trees < 420 and guard < 9000:
		guard += 1
		var x := cb.rng.randf_range(-372.0, -63.0)
		var z := cb.rng.randf_range(-372.0, -63.0)
		if x > -300.0 and z > -300.0:
			if noise.get_noise_2d(x, z) < -0.12:
				continue
		var hgt := Terrain.sample(x, z)
		if hgt < 0.6 or Terrain.road_distance(x, z) < 8.5:
			continue
		if Vector2(x, z).distance_to(peak) < 17.0:
			continue
		var nrm := Terrain.normal(x, z)
		if nrm.y < 0.86:
			continue
		var inside := x > -300.0 and z > -300.0
		var kind := "tree_pine_a"
		var roll := cb.rng.randf()
		if roll < 0.3: kind = "tree_pine_b"
		elif roll < 0.55: kind = "tree_oak_a"
		elif roll < 0.72: kind = "tree_oak_b"
		elif roll < 0.76: kind = "tree_dead"
		cb.deco(kind, Vector3(x, hgt - 0.15, z), cb.rng.randf() * TAU, cb.rng.randf_range(0.85, 1.35) * (1.0 if inside else 1.5), inside)
		trees += 1
	# backdrop tree line along the ridges north and west of the city
	var back := 0
	guard = 0
	while back < 260 and guard < 4000:
		guard += 1
		var x2: float
		var z2: float
		if cb.rng.randf() < 0.5:
			x2 = cb.rng.randf_range(-60.0, 300.0)
			z2 = cb.rng.randf_range(-390.0, -304.0)
		else:
			x2 = cb.rng.randf_range(-390.0, -304.0)
			z2 = cb.rng.randf_range(-60.0, 250.0)
		var h2 := Terrain.sample(x2, z2)
		if h2 < 0.3:
			continue
		cb.deco("tree_pine_a" if back % 3 != 0 else "tree_oak_b", Vector3(x2, h2 - 0.2, z2), cb.rng.randf() * TAU, cb.rng.randf_range(1.2, 1.9), false)
		back += 1
	# rocks, bushes, ferns and grass tufts
	guard = 0
	var small := 0
	while small < 900 and guard < 9000:
		guard += 1
		var x3 := cb.rng.randf_range(-298.0, -62.0)
		var z3 := cb.rng.randf_range(-298.0, -62.0)
		var h3 := Terrain.sample(x3, z3)
		if h3 < 0.4 or Terrain.road_distance(x3, z3) < 5.5:
			continue
		var p := Vector3(x3, h3 - 0.05, z3)
		var roll2 := small % 20
		if roll2 < 13:
			cb.deco("grass_tuft" if roll2 % 3 != 0 else "grass_tall", p, cb.rng.randf() * TAU, cb.rng.randf_range(0.9, 1.6), false, 75.0)
		elif roll2 < 16:
			cb.deco("bush_a" if roll2 % 2 == 0 else "fern", p, cb.rng.randf() * TAU, cb.rng.randf_range(0.7, 1.3), false, 120.0)
		elif roll2 < 18:
			cb.deco("rock_a", p - Vector3(0, 0.15, 0), cb.rng.randf() * TAU, cb.rng.randf_range(0.6, 1.5), true, 220.0)
		elif roll2 == 18:
			cb.deco("rock_b", p - Vector3(0, 0.3, 0), cb.rng.randf() * TAU, cb.rng.randf_range(0.7, 1.3), true, 300.0)
		else:
			cb.deco("log" if small % 40 == 19 else "stump", p, cb.rng.randf() * TAU, 1.0, true, 150.0)
		small += 1
	# a dirt kicker at the summit edge pointing toward downtown
	var jp := Vector3(peak.x + 13.0, 0.0, peak.y - 4.0)
	jp.y = Terrain.sample(jp.x, jp.z)
	cb.prop("prop_ramp_dirt", jp, -PI * 0.5, {"static": true})
	cb.ped_areas.append({"rect": Rect2(peak.x - 14.0, peak.y - 14.0, 28.0, 28.0), "y": top, "name": "Lookout"})

# ---------------------------------------------------------------- sea floor
static func _seabed(cb: CityBuilder) -> void:
	var wx := -120.0
	var wz := 286.0
	cb.prop("wreck_boat", Vector3(wx, Terrain.sample(wx, wz) + 0.2, wz), 0.7, {"static": true})
	cb.locations["wreck"] = {"id": "wreck", "root": null, "markers": {}, "pos": Vector3(wx, Terrain.sample(wx, wz), wz)}
	cb.prop("prop_anchor", Vector3(wx + 9.0, Terrain.sample(wx + 9.0, wz + 4.0), wz + 4.0), 1.3, {"static": true})
	cb.prop("wreck_car", Vector3(96.0, Terrain.sample(96.0, 262.0), 262.0), 2.2, {"static": true})
	var chests := [Vector3(wx - 3.0, 0, wz + 2.0), Vector3(-236.0, 0, 292.0), Vector3(22.0, 0, 300.0), Vector3(150.0, 0, 286.0), Vector3(318.0, 0, 40.0)]
	for c in chests:
		var p := Vector3(c.x, Terrain.sample(c.x, c.z), c.z)
		cb.prop("prop_treasure_chest", p, cb.rng.randf() * TAU, {"static": true})
		cb.pickup_spots.append({"kind": "treasure", "pos": p + Vector3(0, 0.6, 0)})
	var guard := 0
	var placed := 0
	while placed < 170 and guard < 3000:
		guard += 1
		var x := cb.rng.randf_range(-320.0, 360.0)
		var z := cb.rng.randf_range(244.0, 360.0)
		var hgt := Terrain.sample(x, z)
		if hgt > -2.4 or hgt < -15.0:
			continue
		var p2 := Vector3(x, hgt - 0.05, z)
		match placed % 6:
			0, 1: cb.deco("seaweed_a", p2, cb.rng.randf() * TAU, cb.rng.randf_range(0.7, 1.4), false, 90.0)
			2: cb.deco("coral_a", p2, cb.rng.randf() * TAU, cb.rng.randf_range(0.8, 1.6), false, 110.0)
			3: cb.deco("coral_b", p2, cb.rng.randf() * TAU, cb.rng.randf_range(0.8, 1.6), false, 110.0)
			4: cb.deco("rock_b", p2 - Vector3(0, 0.3, 0), cb.rng.randf() * TAU, cb.rng.randf_range(0.8, 2.0), true, 140.0)
			_: cb.deco("rock_a", p2, cb.rng.randf() * TAU, cb.rng.randf_range(0.8, 1.6), false, 110.0)
		placed += 1

# ---------------------------------------------------------------- map edges
static func _edges(cb: CityBuilder) -> void:
	# a plain boundary wall where the city meets the northern / western hills
	solid_box(cb, Vector3(Terrain.HILL_EDGE, 0.0, -300.6), Vector3(CityLayout.AIR_X1, 3.0, -300.0), "concrete", 5.0, "concrete_dark")
	solid_box(cb, Vector3(-300.6, 0.0, Terrain.HILL_EDGE), Vector3(-300.0, 3.0, Terrain.COAST_Z + 6.0), "concrete", 5.0, "concrete_dark")
