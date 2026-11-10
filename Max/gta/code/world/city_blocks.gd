class_name CityBlocks
extends RefCounted
## Lot-level content of the regular city blocks, one generator per district.
## Everything is deterministic (seeded through CityBuilder.rng) so the map is identical
## on every launch and the minimap / saves stay valid.

const H := CityLayout.CURB_H

static func generate(cb: CityBuilder, b: Dictionary) -> void:
	var id: String = b["id"]
	match String(b["district"]):
		"downtown":
			if id == "N_a":
				_police_block(cb, b)
			elif id == "N_b":
				_hospital_block(cb, b)
			else:
				_downtown(cb, b)
		"midtown":
			_midtown(cb, b)
		"residential":
			if id == "W_a":
				_west_strip(cb, b)
			else:
				_residential(cb, b)
		"industrial":
			_industrial(cb, b)
		"beachfront":
			_beachfront(cb, b)
		"marina":
			if id == "S_DF":
				_marina_strip(cb, b)

# ---------------------------------------------------------------- downtown
static func _downtown(cb: CityBuilder, b: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var id: String = b["id"]
	var tall := id.begins_with("B12")
	var half := r.size.x * 0.5
	var cx := r.position.x + half
	var cz := r.position.y + r.size.y * 0.5
	# service alleys forming a cross
	cb.lot(cx - 3.0, r.position.y, cx + 3.0, r.end.y, "asphalt_dark", 6.0)
	cb.lot(r.position.x, cz - 3.0, r.end.x, cz + 3.0, "asphalt_dark", 6.0)
	for qx in 2:
		for qz in 2:
			var x0 := r.position.x if qx == 0 else cx + 3.0
			var x1 := cx - 3.0 if qx == 0 else r.end.x
			var z0 := r.position.y if qz == 0 else cz + 3.0
			var z1 := cz - 3.0 if qz == 0 else r.end.y
			var ew := "W" if qx == 0 else "E"
			var ns := "N" if qz == 0 else "S"
			var key := "%s:%d%d" % [id, qx, qz]
			if key == "B23_CD:11":
				_plaza(cb, x0, z0, x1, z1)
				continue
			if key == "B12_DE:10" and Assets.has_model("landmarks/lm_parking_garage"):
				cb.landmark("lm_parking_garage", Vector3((x0 + x1) * 0.5, H, (z0 + z1) * 0.5 + 2.0), "N", {"label": "Parking"})
				cb.driveway(Vector3((x0 + x1) * 0.5, 0.0, r.position.y - CityLayout.SIDEWALK), Vector3(0, 0, 1), 8.0)
				continue
			var nx := 6 + cb.rng.randi() % 3
			var nz := 6 + cb.rng.randi() % 3
			var floors := cb.rng.randi_range(13, 22) if tall else cb.rng.randi_range(7, 14)
			var x := CityBuilder.snap_up(x0 + 0.6, 4.0) if qx == 0 else CityBuilder.snap_down(x1 - 0.6, 4.0) - nx * 4.0
			var z := CityBuilder.snap_up(z0 + 0.6, 4.0) if qz == 0 else CityBuilder.snap_down(z1 - 0.6, 4.0) - nz * 4.0
			var opts := {}
			if key == "B12_CD:11":
				opts["helipad"] = true
				opts["label"] = "Helipad Tower"
				floors = 16
				nx = 7
				nz = 7
				x = CityBuilder.snap_down(x1 - 0.6, 4.0) - nx * 4.0
				z = CityBuilder.snap_down(z1 - 0.6, 4.0) - nz * 4.0
			elif key == "B23_DE:01":
				opts["front"] = "front_cinema"
				floors = 5
				nx = 7
			elif cb.rng.randf() < 0.3:
				opts["billboard"] = "roof_billboard_a" if cb.rng.randf() < 0.5 else "roof_billboard_b"
				opts["billboard_rot"] = float(cb.rng.randi() % 4) * PI * 0.5
			var body := cb.modular("office", x, z, nx, nz, floors, ns, ns + ew, opts)
			if key == "B12_CD:11":
				var top := body.position + Vector3(nx * 2.0, 4.5 + float(floors - 1) * 3.5 + 0.2, nz * 2.0)
				cb.locations["helipad_tower"] = {"id": "helipad_tower", "root": body, "markers": {}, "pos": top,
					"door": body.position + Vector3(nx * 2.0, 0.0, nz * 4.0 + 1.5)}
				cb.spawn_vehicle("heli_civil", top, 0.0, "roof")
			# street trees / benches in the leftover forecourt on the inner side
			var ix := x1 - 2.0 if qx == 0 else x0 + 2.0
			var iz := z1 - 2.0 if qz == 0 else z0 + 2.0
			cb.prop("prop_dumpster", Vector3(ix, H, iz), float(cb.rng.randi() % 4) * PI * 0.5, {"tint_a": cb.pick(CityBuilder.C_IND)})
			if cb.rng.randf() < 0.6:
				cb.prop("prop_pallet", Vector3(ix + (3.0 if qx == 1 else -3.0), H, iz), cb.rng.randf() * TAU)

static func _plaza(cb: CityBuilder, x0: float, z0: float, x1: float, z1: float) -> void:
	cb.lot(x0, z0, x1, z1, "stucco_cream", 5.0)
	var c := Vector3((x0 + x1) * 0.5, H, (z0 + z1) * 0.5)
	cb.landmark("lm_fountain", c, "S", {"label": "Meridian Square"})
	cb.landmark("lm_statue", Vector3(x0 + 6.0, H, z0 + 6.0), "S")
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		var p := c + Vector3(cos(a), 0, sin(a)) * 9.5
		cb.prop("prop_bench", p, CityBuilder.yaw_to(c - p))
		var q := c + Vector3(cos(a + 0.6), 0, sin(a + 0.6)) * 13.0
		cb.prop("lamp_park", q, 0.0)
	for i in 6:
		var a2 := TAU * float(i) / 6.0 + 0.3
		var t := c + Vector3(cos(a2) * 14.0, 0, sin(a2) * 14.0)
		if t.x > x0 + 1.5 and t.x < x1 - 1.5 and t.z > z0 + 1.5 and t.z < z1 - 1.5:
			cb.deco("tree_round", t, cb.rng.randf() * TAU, cb.rng.randf_range(0.9, 1.15))
	cb.ped_areas.append({"rect": Rect2(x0 + 2.0, z0 + 2.0, x1 - x0 - 4.0, z1 - z0 - 4.0), "y": H, "name": "Meridian Square"})
	cb.locations["plaza"] = {"id": "plaza", "root": null, "markers": {}, "pos": c}

static func _police_block(cb: CityBuilder, b: Dictionary) -> void:
	# Vesper Bay Police HQ + secure car park + an office tower
	var hq := cb.modular("office", -24.0, -272.0, 9, 6, 5, "S", "S", {
		"front": "front_police", "helipad": true, "tint_a": Color.html("d9d2c2"), "tint_b": Color.html("1f3f8f"), "style": 1, "label": "VBPD"})
	var roof_y := H + 4.5 + 4.0 * 3.5 + 0.2
	cb.locations["police_hq"] = {"id": "police_hq", "root": hq, "markers": {}, "pos": Vector3(-6.0, H, -243.5),
		"release": Vector3(-6.0, H, -241.0), "roof": Vector3(-6.0, roof_y, -260.0)}
	cb.spawn_vehicle("heli_police", Vector3(-6.0, roof_y, -260.0), 0.0, "police_roof")
	cb.parking_lot(-56.0, -292.0, -30.0, -246.0, "police", 0.0)
	for i in 4:
		cb.spawn_vehicle("car_police", Vector3(-53.0 + float(i) * 5.8, H, -288.5), PI, "police_lot")
	cb.spawn_vehicle("car_swat", Vector3(-36.0, H, -252.0), -PI * 0.5, "police_lot")
	cb.driveway(Vector3(-43.0, 0.0, -235.5), Vector3(0, 0, -1), 7.0)
	cb.fence_run("fence_chain", Vector2(-57.5, -297.0), Vector2(-57.5, -241.0), H, 3.0)
	cb.fence_run("fence_chain", Vector2(-28.0, -297.0), Vector2(-28.0, -247.0), H, 3.0)
	cb.modular("office", 16.0, -268.0, 5, 6, 12, "S", "S")
	for i in 3:
		cb.deco("tree_round", Vector3(-22.0 + float(i) * 16.0, H, -242.0), 0.0, 1.0)

static func _hospital_block(cb: CityBuilder, b: Dictionary) -> void:
	var hosp := cb.modular("office", 60.0, -272.0, 10, 6, 7, "S", "S", {
		"front": "front_hospital", "helipad": true, "tint_a": Color.html("f2f0ea"), "tint_b": Color.html("2aa59a"), "style": 2, "label": "Hospital"})
	var roof_y := H + 4.5 + 6.0 * 3.5 + 0.2
	cb.locations["hospital"] = {"id": "hospital", "root": hosp, "markers": {}, "pos": Vector3(80.0, H, -243.5),
		"respawn": Vector3(80.0, H, -241.5), "roof": Vector3(80.0, roof_y, -260.0)}
	cb.parking_lot(104.0, -292.0, 128.0, -246.0, "ambulance", 0.25)
	cb.spawn_vehicle("car_ambulance", Vector3(108.0, H, -288.0), PI, "hospital")
	cb.spawn_vehicle("car_ambulance", Vector3(114.0, H, -288.0), PI, "hospital")
	cb.driveway(Vector3(116.0, 0.0, -235.5), Vector3(0, 0, -1), 7.0)
	# small garden west of the hospital
	cb.lot(42.0, -296.0, 57.0, -241.0, "grass", 3.0)
	for i in 5:
		cb.deco("tree_oak_a" if i % 2 == 0 else "tree_round", Vector3(49.5 + sin(float(i) * 2.1) * 4.0, H, -290.0 + float(i) * 11.0), cb.rng.randf() * TAU, cb.rng.randf_range(0.8, 1.05))
	cb.prop("prop_bench", Vector3(55.0, H, -262.0), -PI * 0.5)
	cb.prop("prop_bench", Vector3(55.0, H, -252.0), -PI * 0.5)
	cb.ped_areas.append({"rect": Rect2(43.0, -295.0, 13.0, 52.0), "y": H, "name": "Hospital Garden"})

# ---------------------------------------------------------------- midtown
const MID_LANDMARKS := {
	"B34_DE:S:0": "shop_guns", "B34_CD:S:2": "shop_clothes", "B45_CD:N:2": "shop_barber", "B45_DE:N:0": "shop_market",
}

static func _midtown(cb: CityBuilder, b: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var id: String = b["id"]
	var depth := 20.0
	for row: String in ["N", "S"]:
		var z := CityBuilder.snap_up(r.position.y + 0.6, 4.0) if row == "N" else CityBuilder.snap_down(r.end.y - 0.6, 4.0) - depth
		for slot in 3:
			var sx0 := r.position.x + 1.0 + float(slot) * 24.5
			var key := "%s:%s:%d" % [id, row, slot]
			var sides: String = row + ("W" if slot == 0 else "") + ("E" if slot == 2 else "")
			if MID_LANDMARKS.has(key):
				var lid: String = MID_LANDMARKS[key]
				var deep := 4.0 if lid == "shop_barber" else 5.0
				var cz := (r.position.y + 3.5 + deep) if row == "N" else (r.end.y - 3.5 - deep)
				var cxm := sx0 + 11.0
				cb.lot(sx0, r.position.y if row == "N" else r.end.y - depth - 2.0, sx0 + 22.0,
					r.position.y + depth + 2.0 if row == "N" else r.end.y, "stucco_sand", 5.0)
				cb.landmark(lid, Vector3(cxm, H, cz), row, {"label": lid})
				continue
			var roll := cb.rng.randf()
			var kit := "mixed"
			if roll > 0.85:
				kit = "office"
			elif roll > 0.72:
				kit = "apt"
			cb.modular(kit, sx0 + 0.5, z, 5, 5, cb.rng.randi_range(3, 6), row, sides)
	# courtyard car park in the middle band
	var cz0 := r.position.y + 23.0
	var cz1 := r.end.y - 23.0
	cb.parking_lot(r.position.x + 3.0, cz0, r.end.x - 3.0, cz1, "civil", 0.55)
	var mid := (cz0 + cz1) * 0.5
	cb.driveway(Vector3(r.position.x - CityLayout.SIDEWALK, 0.0, mid), Vector3(1, 0, 0), 6.5)
	cb.driveway(Vector3(r.end.x + CityLayout.SIDEWALK, 0.0, mid), Vector3(-1, 0, 0), 6.5)
	cb.prop("lamp_park", Vector3(r.position.x + 20.0, H, mid), 0.0)
	cb.prop("lamp_park", Vector3(r.end.x - 20.0, H, mid), 0.0)
	cb.prop("prop_dumpster", Vector3(r.position.x + 5.0, H, cz0 + 1.2), 0.0, {"tint_a": cb.pick(CityBuilder.C_IND)})
	cb.prop("prop_dumpster", Vector3(r.end.x - 5.0, H, cz1 - 1.2), PI, {"tint_a": cb.pick(CityBuilder.C_IND)})

# ---------------------------------------------------------------- residential
static func _house_lot(cb: CityBuilder, cx: float, front_z: float, facing: String, lot_w: float) -> void:
	# a house facing N or S: front wall `set_back` metres behind the lot line at front_z
	var nx := 3 + cb.rng.randi() % 2
	var nz := 2 + cb.rng.randi() % 2
	var floors := 1 + cb.rng.randi() % 2
	var garage := nx >= 4 and cb.rng.randf() < 0.75
	var d := nz * 3.0
	var w := nx * 3.0
	var sgn := 1.0 if facing == "N" else -1.0        # +1: lot extends toward +Z from the street
	var set_back := 7.0
	var cz := front_z + sgn * (set_back + d * 0.5)
	var body := cb.house(cx, cz, nx, nz, floors, facing, garage)
	var hx: float = body.position.x
	var front_wall := cz - sgn * d * 0.5
	var kerb_z := front_z - sgn * CityLayout.SIDEWALK
	# front path + optional driveway with a parked car
	var door_x := hx + (1.5 * 3.0 if garage else float(nx / 2) * 3.0 + 1.5)
	cb.lot(door_x - 0.6, front_z, door_x + 0.6, front_wall, "concrete_light", 0.0)
	if garage:
		var gx := hx + float(nx - 1) * 3.0
		cb.lot(gx - 2.6, front_z, gx + 2.6, front_wall, "concrete", 0.0)
		cb.driveway(Vector3(gx, 0.0, kerb_z), Vector3(0, 0, sgn), 5.2)
		if cb.rng.randf() < 0.6:
			cb.parking_spots.append({"pos": Vector3(gx, H, front_z + sgn * 3.6), "yaw": 0.0 if sgn > 0.0 else PI, "kind": "driveway"})
	cb.prop("prop_mailbox", Vector3(door_x + 1.4, H, front_z - sgn * 0.6), 0.0 if sgn > 0.0 else PI)
	if cb.rng.randf() < 0.5:
		cb.prop("prop_bin", Vector3(hx - 1.2, H, front_wall + sgn * 1.0), 0.0)
	# garden
	var back_z := cz + sgn * (d * 0.5 + 6.0)
	var trees := ["tree_oak_a", "tree_round", "tree_palm_b", "tree_oak_b", "tree_palm_a"]
	cb.deco(trees[cb.rng.randi() % trees.size()], Vector3(cx + cb.rng.randf_range(-7.0, 7.0), H, back_z + sgn * cb.rng.randf_range(0.0, 6.0)),
		cb.rng.randf() * TAU, cb.rng.randf_range(0.75, 1.05))
	for i in 3:
		cb.deco("bush_a" if i % 2 == 0 else "bush_b", Vector3(hx + float(i) * 2.6 + 0.5, H, front_wall - sgn * 1.0), cb.rng.randf() * TAU,
			cb.rng.randf_range(0.6, 0.9), false, 110.0)
	if cb.rng.randf() < 0.3:
		var px := cx - 5.0
		cb.lot(px, back_z + sgn * 2.0, px + 7.0, back_z + sgn * 6.5, "white", 0.0, 0.014)
		cb.lot(px + 0.4, back_z + sgn * 2.4, px + 6.6, back_z + sgn * 6.1, "ice_blue", 0.0, 0.02)
	# picket fence along the front, with a gap at the path and the driveway
	var fx0 := cx - lot_w * 0.5 + 1.0
	var fx1 := cx + lot_w * 0.5 - 1.0
	var fz := front_z + sgn * 0.5
	var t := fx0
	while t < fx1 - 1.9:
		var mid := t + 1.0
		var blocked := absf(mid - door_x) < 1.6 or (garage and absf(mid - (hx + float(nx - 1) * 3.0)) < 3.6)
		if not blocked and cb.rng.randf() < 0.9:
			cb.prop("fence_picket", Vector3(mid, H, fz), 0.0)
		t += 2.0

static func _residential(cb: CityBuilder, b: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var id: String = b["id"]
	var lot_w := r.size.x / 3.0
	var mid_z := r.position.y + r.size.y * 0.5
	for k in 3:
		var cx := r.position.x + lot_w * (float(k) + 0.5)
		if id == "B45_BC":
			# two apartment buildings on the north half instead of houses
			if k < 2:
				var ax := r.position.x + 2.0 + float(k) * 36.0
				cb.modular("apt", ax, r.position.y + 2.0, 7 if k == 0 else 6, 4, cb.rng.randi_range(4, 5), "N", "N" + ("W" if k == 0 else "E"))
		else:
			_house_lot(cb, cx, r.position.y, "N", lot_w)
		_house_lot(cb, cx, r.end.y, "S", lot_w)
	if id == "B45_BC":
		cb.parking_lot(r.position.x + 4.0, r.position.y + 21.0, r.end.x - 4.0, mid_z - 1.0, "civil", 0.6)
		cb.driveway(Vector3(r.position.x - CityLayout.SIDEWALK, 0.0, r.position.y + 28.0), Vector3(1, 0, 0), 6.0)
	# back-garden fences (static): property lines and the mid line
	for k in range(1, 3):
		var fx := r.position.x + lot_w * float(k)
		_static_fence(cb, Vector2(fx, r.end.y - 30.0), Vector2(fx, r.end.y - 8.0))
		if id != "B45_BC":
			_static_fence(cb, Vector2(fx, r.position.y + 8.0), Vector2(fx, r.position.y + 30.0))
	_static_fence(cb, Vector2(r.position.x + 1.0, mid_z), Vector2(r.end.x - 1.0, mid_z))

static func _static_fence(cb: CityBuilder, a: Vector2, b: Vector2) -> void:
	var total := a.distance_to(b)
	var n := int(round(total / 2.0))
	if n < 1:
		return
	var dirv := (b - a) / total
	var yaw := atan2(-dirv.y, dirv.x)
	for i in n:
		var p := a + dirv * ((float(i) + 0.5) * 2.0)
		cb.deco("fence_wood", Vector3(p.x, H, p.y), yaw, 1.0, true, 150.0)

static func _west_strip(cb: CityBuilder, b: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var front_x := r.end.x
	var n := int(r.size.y / 26.0)
	var lot := r.size.y / float(n)
	for k in n:
		var cz := r.position.y + lot * (float(k) + 0.5)
		var nx := 3 + cb.rng.randi() % 2
		var nz := 2 + cb.rng.randi() % 2
		var d := nz * 3.0
		var garage := nx >= 4 and cb.rng.randf() < 0.7
		var cx := front_x - 7.0 - d * 0.5
		var body := cb.house(cx, cz, nx, nz, 1 + cb.rng.randi() % 2, "E", garage)
		var front_wall := cx + d * 0.5
		# local +X of the rotated house points north, so the garage is at the north end
		var w := nx * 3.0
		var south_z: float = body.position.z            # local x = 0
		var door_z := south_z - (4.5 if garage else float(nx / 2) * 3.0 + 1.5)
		cb.lot(front_wall, door_z - 0.6, front_x, door_z + 0.6, "concrete_light", 0.0)
		if garage:
			var gz := south_z - float(nx - 1) * 3.0
			cb.lot(front_wall, gz - 2.6, front_x, gz + 2.6, "concrete", 0.0)
			cb.driveway(Vector3(front_x + CityLayout.SIDEWALK, 0.0, gz), Vector3(-1, 0, 0), 5.2)
			if cb.rng.randf() < 0.6:
				cb.parking_spots.append({"pos": Vector3(front_x - 3.6, H, gz), "yaw": PI * 0.5, "kind": "driveway"})
		cb.prop("prop_mailbox", Vector3(front_x + 0.6, H, door_z + 1.4), -PI * 0.5)
		for i in 2:
			cb.deco("bush_a", Vector3(front_wall + 1.0, H, south_z - w * 0.5 + float(i) * 3.0 - 1.5), cb.rng.randf() * TAU, 0.75, false, 110.0)
		# back yards run into the western tree line
		for i in 3:
			var tx := cb.rng.randf_range(r.position.x + 3.0, cx - d * 0.5 - 3.0)
			var tz := cz + cb.rng.randf_range(-lot * 0.45, lot * 0.45)
			var trees := ["tree_oak_a", "tree_oak_b", "tree_pine_a", "tree_pine_b", "tree_round"]
			cb.deco(trees[cb.rng.randi() % trees.size()], Vector3(tx, H, tz), cb.rng.randf() * TAU, cb.rng.randf_range(0.8, 1.2))
		if k > 0:
			_static_fence(cb, Vector2(front_x - 8.0, r.position.y + lot * float(k)), Vector2(r.position.x + 14.0, r.position.y + lot * float(k)))

# ---------------------------------------------------------------- industrial
static func _yard_clutter(cb: CityBuilder, x0: float, z0: float, x1: float, z1: float, amount: int) -> void:
	for i in amount:
		var p := Vector3(cb.rng.randf_range(x0, x1), H, cb.rng.randf_range(z0, z1))
		match cb.rng.randi() % 7:
			0: cb.prop("prop_pallet", p, cb.rng.randf() * TAU)
			1: cb.prop("prop_crate", p, cb.rng.randf() * TAU)
			2: cb.prop("prop_barrel", p, 0.0, {"tint_a": cb.pick(CityBuilder.C_IND_B)})
			3: cb.prop("prop_crate_small", p, cb.rng.randf() * TAU)
			4: cb.prop("prop_tire_stack", p, 0.0)
			5: cb.prop("prop_barrel_explosive", p, 0.0)
			_: cb.prop("prop_cable_spool", p, cb.rng.randf() * TAU)

static func _containers(cb: CityBuilder, x: float, z: float, count: int, along_x: bool, stack := true) -> void:
	for i in count:
		var p := Vector3(x + (float(i) * 2.7 if not along_x else 0.0), H, z + (float(i) * 2.7 if along_x else 0.0))
		var yaw := PI * 0.5 if along_x else 0.0
		var tint := cb.pick(CityBuilder.C_MID_B)
		cb.prop("prop_container", p, yaw, {"tint_a": tint, "static": true})
		if stack and cb.rng.randf() < 0.45:
			cb.prop("prop_container", p + Vector3(0, 2.6, 0), yaw, {"tint_a": cb.pick(CityBuilder.C_MID_B), "static": true})

static func _industrial(cb: CityBuilder, b: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var x0 := r.position.x
	var z0 := r.position.y
	match String(b["id"]):
		"N_c":
			cb.modular("ind", 136.0, -276.0, 8, 6, 2, "S", "S")
			cb.landmark("lm_water_tower", Vector3(188.0, H, -262.0), "S", {"label": "Water Tower"})
			for i in 3:
				cb.prop("prop_transformer", Vector3(184.0 + float(i) * 6.0, H, -288.0), 0.0)
			cb.fence_run("fence_chain", Vector2(178.0, -281.0), Vector2(205.0, -281.0), H, 3.0)
			_containers(cb, 172.0, -250.0, 3, false)
			_yard_clutter(cb, 132.0, -250.0, 168.0, -242.0, 6)
		"B12_EF":
			cb.modular("ind", 144.0, -216.0, 11, 7, 2, "S", "NSEW")
			_containers(cb, 146.0, -178.0, 4, false)
			_containers(cb, 176.0, -182.0, 3, true, false)
			_yard_clutter(cb, 142.0, -170.0, 192.0, -152.0, 10)
			cb.spawn_vehicle("car_truck", Vector3(166.0, H, -160.0), PI * 0.5, "yard")
			cb.driveway(Vector3(166.0, 0.0, -145.5), Vector3(0, 0, -1), 8.0)
			cb.parking_spots.append({"pos": Vector3(186.0, H, -160.0), "yaw": 0.0, "kind": "civil"})
		"B23_EF":
			cb.modular("ind", 144.0, -128.0, 6, 6, 2, "W", "NW")
			cb.modular("ind", 172.0, -92.0, 5, 7, 2, "S", "SE")
			# open-air shooting range in the north-east corner of the block
			cb.lot(172.0, -129.0, 195.0, -96.0, "dirt", 0.0)
			cb.locations["range"] = {"id": "range", "root": null, "markers": {}, "pos": Vector3(183.5, H, -100.0),
				"lane_from": Vector3(183.5, H, -100.0), "lane_dir": Vector3(0, 0, -1), "rect": Rect2(173.0, -128.0, 21.0, 26.0)}
			cb.fence_run("wall_concrete", Vector2(172.0, -129.5), Vector2(196.0, -129.5), H, 2.0)
			cb.fence_run("wall_concrete", Vector2(195.5, -129.0), Vector2(195.5, -97.0), H, 2.0)
			cb.fence_run("wall_concrete", Vector2(171.5, -129.0), Vector2(171.5, -104.0), H, 2.0)
			_yard_clutter(cb, 142.0, -98.0, 168.0, -62.0, 8)
			cb.driveway(Vector3(135.5, 0.0, -110.0), Vector3(1, 0, 0), 7.0)
		"B34_EF":
			cb.modular("office", 144.0, -28.0, 9, 5, 3, "W", "WN", {"front": "front_firestation", "tint_a": Color.html("a2523f"),
				"tint_b": Color.html("e3dfd4"), "style": 1, "label": "Fire Station"})
			cb.locations["fire_station"] = {"id": "fire_station", "root": null, "markers": {}, "pos": Vector3(141.0, H, -18.0)}
			cb.lot(139.0, -30.0, 144.0, -6.0, "concrete", 0.0)
			cb.driveway(Vector3(135.5, 0.0, -22.5), Vector3(1, 0, 0), 5.0)
			cb.driveway(Vector3(135.5, 0.0, -13.5), Vector3(1, 0, 0), 5.0)
			cb.spawn_vehicle("car_firetruck", Vector3(162.0, H, 10.0), PI * 0.5, "fire")
			cb.modular("ind", 148.0, 2.0, 8, 4, 2, "N", "ES")
			cb.driveway(Vector3(196.0 + CityLayout.SIDEWALK, 0.0, -2.0), Vector3(-1, 0, 0), 7.0)
			_yard_clutter(cb, 184.0, -28.0, 194.0, 26.0, 6)
		"B45_EF":
			# Torque House Customs: mod / repair garage, bay facing Foundry Ave
			cb.lot(139.0, 73.0, 152.0, 97.0, "asphalt", 6.0)
			var g := cb.landmark("shop_garage", Vector3(157.0, H, 85.0), "W", {"label": "Torque House"})
			cb.driveway(Vector3(135.5, 0.0, 85.0), Vector3(1, 0, 0), 9.0)
			if g == null:
				cb.locations["shop_garage"] = {"id": "shop_garage", "root": null, "markers": {}, "pos": Vector3(146.0, H, 85.0)}
			cb.modular("ind", 144.0, 52.0, 10, 4, 2, "S", "NWE")
			cb.prop("prop_tire_stack", Vector3(150.0, H, 100.0), 0.0)
			cb.prop("prop_tire_stack", Vector3(152.0, H, 101.0), 0.4)
			cb.prop("prop_barrel", Vector3(149.0, H, 71.0), 0.0, {"tint_a": Color.html("2f6fd0")})
			# scrapyard with a stunt ramp behind the garage
			cb.lot(168.0, 72.0, 195.0, 120.0, "dirt", 0.0)
			# (the stunt ramp itself is placed by activities.gd together with its landing zone)
			cb.prop("wreck_car", Vector3(172.0, H, 80.0), 0.6, {"static": true})
			cb.prop("wreck_car", Vector3(176.5, H, 79.0), 2.0, {"static": true})
			_containers(cb, 190.0, 76.0, 3, true)
			_yard_clutter(cb, 170.0, 86.0, 192.0, 118.0, 9)
			cb.driveway(Vector3(182.0, 0.0, 121.0 + CityLayout.SIDEWALK), Vector3(0, 0, -1), 8.0)

# ---------------------------------------------------------------- beachfront strip
static func _beachfront(cb: CityBuilder, b: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var zn := r.position.y            # Dune St lot line (north)
	var zs := r.end.y                 # Bayline Avenue lot line (south)
	# 1. the safehouse bungalow with garage, facing Dune St
	cb.lot(-221.0, zn, -172.0, zs, "grass", 3.0)
	var sh := cb.landmark("safehouse", Vector3(-193.0, H, zn + 12.5), "N", {"label": "Safehouse", "tint_a": Color.html("58b5a8"), "tint_b": Color.html("e3dfd4")})
	var gout: Variant = cb.marker("safehouse", "garage_out")
	var gx := -202.0 if gout == null else (gout as Transform3D).origin.x
	cb.lot(gx - 2.8, zn, gx + 2.8, zn + 8.5, "concrete", 0.0)
	cb.driveway(Vector3(gx, 0.0, zn - CityLayout.SIDEWALK), Vector3(0, 0, 1), 5.6)
	if sh == null and not cb.locations.has("safehouse"):
		cb.locations["safehouse"] = {"id": "safehouse", "root": null, "markers": {}, "pos": Vector3(-193.0, H, zn + 4.0)}
	for i in 4:
		cb.deco("tree_palm_a" if i % 2 == 0 else "tree_palm_b", Vector3(-216.0 + float(i) * 13.0, H, zs - 5.0 - float(i % 2) * 4.0), cb.rng.randf() * TAU, cb.rng.randf_range(0.85, 1.1))
	cb.fence_run("fence_picket", Vector2(-220.0, zn + 0.6), Vector2(-206.0, zn + 0.6), H)
	cb.fence_run("fence_picket", Vector2(-197.0, zn + 0.6), Vector2(-173.0, zn + 0.6), H, 2.0, 5.0, 8.0)
	# 2. motel
	cb.modular("apt", -168.0, zn + 2.0, 8, 3, 2, "S", "N", {"tint_a": Color.html("f0b592"), "tint_b": Color.html("2aa59a"), "label": "Motel"})
	cb.parking_lot(-168.0, zn + 17.0, -136.0, zs - 2.0, "civil", 0.5)
	cb.driveway(Vector3(-152.0, 0.0, zs + CityLayout.SIDEWALK), Vector3(0, 0, -1), 6.5)
	# 3. Tideline Hotel facing the bay
	var hotel := cb.modular("apt", -124.0, zs - 22.5, 10, 5, 10, "S", "S", {"front": "front_hotel", "tint_a": cb.pick(CityBuilder.C_HOTEL),
		"tint_b": Color.html("f2f0ea"), "helipad": false, "label": "Tideline Hotel"})
	cb.locations["hotel"] = {"id": "hotel", "root": hotel, "markers": {}, "pos": Vector3(-104.0, H, zs - 1.0)}
	cb.parking_lot(-126.0, zn + 2.0, -84.0, zn + 19.0, "civil", 0.6)
	cb.driveway(Vector3(-105.0, 0.0, zn - CityLayout.SIDEWALK), Vector3(0, 0, 1), 6.5)
	# 4. bars, diner and surf shops
	cb.modular("mixed", -76.0, zs - 18.5, 8, 4, 2, "S", "S")
	cb.modular("mixed", -76.0, zn + 2.0, 6, 4, 3, "N", "N")
	cb.modular("mixed", -48.0, zn + 2.0, 3, 4, 2, "N", "N")
	# 5. public car park
	cb.parking_lot(-38.0, zn + 3.0, -10.0, zs - 3.0, "civil", 0.5)
	cb.driveway(Vector3(-24.0, 0.0, zn - CityLayout.SIDEWALK), Vector3(0, 0, 1), 6.5)
	cb.driveway(Vector3(-24.0, 0.0, zs + CityLayout.SIDEWALK), Vector3(0, 0, -1), 6.5)
	# 6. Gull Gas + QuikNook market at the corner of Vesper Blvd
	cb.lot(-6.0, zn, 31.0, zs, "asphalt", 6.0)
	cb.landmark("lm_gas_station", Vector3(13.0, H, zs - 15.0), "S", {"label": "Gull Gas", "light_energy": 2.2, "light_range": 9.0})
	cb.landmark("shop_market", Vector3(11.0, H, zn + 8.0), "S", {"label": "QuikNook"})
	cb.driveway(Vector3(4.0, 0.0, zs + CityLayout.SIDEWALK), Vector3(0, 0, -1), 7.0)
	cb.driveway(Vector3(22.0, 0.0, zs + CityLayout.SIDEWALK), Vector3(0, 0, -1), 7.0)
	cb.driveway(Vector3(31.0 + CityLayout.SIDEWALK, 0.0, zs - 15.0), Vector3(-1, 0, 0), 7.0)

static func _marina_strip(cb: CityBuilder, b: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var zn := r.position.y
	var zs := r.end.y
	cb.modular("mixed", 52.0, zn + 2.0, 7, 4, 3, "N", "NW")
	cb.parking_lot(52.0, zn + 21.0, 100.0, zs - 2.0, "civil", 0.55)
	cb.driveway(Vector3(76.0, 0.0, zs + CityLayout.SIDEWALK), Vector3(0, 0, -1), 6.5)
	cb.modular("ind", 108.0, zn + 5.0, 8, 6, 2, "S", "N", {"label": "Boat Storage"})
	cb.driveway(Vector3(124.0, 0.0, zs + CityLayout.SIDEWALK), Vector3(0, 0, -1), 8.0)
	# ZipCab depot
	cb.modular("ind", 148.0, zn + 5.0, 6, 5, 1, "S", "N", {"tint_a": Color.html("f5c518"), "tint_b": Color.html("17181b"), "label": "ZipCab"})
	cb.lot(146.0, zn + 26.0, 174.0, zs, "asphalt", 6.0)
	for i in 3:
		cb.spawn_vehicle("car_taxi", Vector3(151.0 + float(i) * 7.0, H, zs - 6.0), PI, "taxi_depot")
	cb.driveway(Vector3(160.0, 0.0, zs + CityLayout.SIDEWALK), Vector3(0, 0, -1), 8.0)
	cb.locations["taxi_depot"] = {"id": "taxi_depot", "root": null, "markers": {}, "pos": Vector3(160.0, H, zs - 4.0)}
	cb.modular("office", 180.0, zn + 2.0, 4, 5, 4, "S", "NE")
