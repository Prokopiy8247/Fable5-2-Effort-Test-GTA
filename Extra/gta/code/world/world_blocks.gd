extends RefCounted
## District content for Cinder Bay: fills every city block, the coast, airport, hill, outskirts and the elevated rail loop.

const CH := 0.16
const GRASS := Color(0, 0, 0, 1)

var b: WorldBuilder
var L := WorldLayout
var rng: RandomNumberGenerator


func _init(builder: WorldBuilder) -> void:
	b = builder
	rng = b.rng


func build_all() -> void:
	b.spawns["clerks"] = []
	b.spawns["boats"] = []
	b.spawns["air"] = []
	b.spawns["special"] = []
	for bj in 4:
		for bi in 6:
			_block(bi, bj)
	_coast()
	_airport()
	_hill()
	_outskirts()
	_rail()


func v3(x: float, z: float, y: float = CH) -> Vector3:
	return Vector3(x, y, z)


func asphalt(x0: float, z0: float, x1: float, z1: float, type: int = 1, y: float = CH + 0.006) -> void:
	b.road_quad(Vector3(x0, 0, (z0 + z1) * 0.5), Vector3(x1, 0, (z0 + z1) * 0.5), absf(z1 - z0) * 0.5, 1, type, y)


func _curb(pos: Vector3, yaw: float, sx: float) -> void:
	var bas := Basis(Vector3.UP, yaw)
	bas.x *= sx
	if not b.cur.props.has("curb_straight"):
		b.cur.props["curb_straight"] = []
	b.cur.props["curb_straight"].append({"xf": Transform3D(bas, pos), "tint": Color.WHITE, "shape": null})


func _curbs(x0: float, z0: float, x1: float, z1: float) -> void:
	for side in 4:
		var horiz := side % 2 == 0
		var length := (x1 - x0) if horiz else (z1 - z0)
		var n := maxi(1, roundi(length / 4.0))
		var seg := length / n
		for k in n:
			var t := (k + 0.5) * seg
			match side:
				0: _curb(Vector3(x0 + t, 0, z1), 0.0, seg / 4.0)
				1: _curb(Vector3(x1, 0, z0 + t), PI * 0.5, seg / 4.0)
				2: _curb(Vector3(x0 + t, 0, z0), PI, seg / 4.0)
				3: _curb(Vector3(x0, 0, z0 + t), -PI * 0.5, seg / 4.0)


func _edge_point(x0: float, z0: float, x1: float, z1: float, side: int, t: float, inset: float) -> Vector3:
	match side:
		0: return Vector3(x0 + t, CH, z1 - inset)
		1: return Vector3(x1 - inset, CH, z0 + t)
		2: return Vector3(x1 - t, CH, z0 + inset)
	return Vector3(x0 + inset, CH, z1 - t)


func _furniture(x0: float, z0: float, x1: float, z1: float, type: String) -> void:
	var commercial := type in ["towers", "shops", "civic", "hospital", "hotel"]
	var industrial := type in ["ind", "yard", "docks", "gas"]
	var tree := "tree_round"
	if type in ["hotel", "beachres"]:
		tree = "tree_palm"
	for side in 4:
		var yaw: float = [0.0, PI * 0.5, PI, -PI * 0.5][side]
		var length := (x1 - x0) if side % 2 == 0 else (z1 - z0)
		var t := 9.0
		var k := 0
		while t < length - 8.0:
			b.prop("prop_street_lamp" if not industrial or k % 2 == 0 else "prop_power_pole", _edge_point(x0, z0, x1, z1, side, t, 0.8), yaw)
			if not industrial and t + 13.0 < length - 6.0:
				b.prop(tree, _edge_point(x0, z0, x1, z1, side, t + 13.0, 1.5), rng.randf() * TAU, rng.randf_range(0.7, 0.9) if tree != "tree_palm" else rng.randf_range(0.8, 1.0))
			t += 26.0
			k += 1
		b.prop("prop_hydrant", _edge_point(x0, z0, x1, z1, side, 6.0 + rng.randf() * 3.0, 0.7), yaw)
		if commercial:
			var m := length * 0.5 + rng.randf_range(-6, 6)
			b.prop("prop_bench", _edge_point(x0, z0, x1, z1, side, m, 3.2), yaw)
			b.prop("prop_bin", _edge_point(x0, z0, x1, z1, side, m + 1.8, 3.2), yaw)
			for q in 3:
				b.prop("prop_parking_meter", _edge_point(x0, z0, x1, z1, side, 20.0 + q * 6.5, 0.6), yaw)
			if side == 0:
				b.prop("prop_newsbox", _edge_point(x0, z0, x1, z1, side, length - 12.0, 3.3), yaw)
				b.prop("prop_bus_stop", _edge_point(x0, z0, x1, z1, side, length * 0.72, 2.2), yaw)
			if side == 1:
				b.prop("prop_vending", _edge_point(x0, z0, x1, z1, side, length - 15.0, 3.4), yaw)
				b.prop("prop_utility_box", _edge_point(x0, z0, x1, z1, side, 14.0, 3.3), yaw)
		elif industrial:
			b.prop("prop_utility_box", _edge_point(x0, z0, x1, z1, side, length * 0.4, 3.3), yaw)
		else:
			b.prop("prop_mailbox", _edge_point(x0, z0, x1, z1, side, length * 0.5, 0.9), yaw)
			b.prop("prop_bin", _edge_point(x0, z0, x1, z1, side, length * 0.25, 3.3), yaw)
		# street parking bays along the kerb
		if _road_hw(side, x0, z0, x1, z1) < 7.0:
			var along := Basis(Vector3.UP, yaw) * Vector3(1, 0, 0)
			var out := Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)
			var pt := 30.0
			while pt < length - 24.0:
				var pp := _edge_point(x0, z0, x1, z1, side, pt, 0.0) + out * 1.3
				b.park(Vector3(pp.x, 0.05, pp.z), atan2(along.x, along.z), "street")
				pt += 13.0 + rng.randf() * 9.0


func _road_hw(side: int, x0: float, z0: float, x1: float, z1: float) -> float:
	var best := 99.0
	if side % 2 == 0:
		var edge := z1 if side == 0 else z0
		for j in L.NZ:
			var g: float = (L.HZ[j] - edge) if side == 0 else (edge - L.HZ[j])
			if g > 0.0 and g < best:
				best = g
	else:
		var edge2 := x1 if side == 1 else x0
		for i in L.NX:
			var g2: float = (L.VX[i] - edge2) if side == 1 else (edge2 - L.VX[i])
			if g2 > 0.0 and g2 < best:
				best = g2
	return best


func _block(bi: int, bj: int) -> void:
	var r := L.block_rect(bi, bj)
	var type: String = L.BLOCKS[bj][bi]
	b.chunk("block_%d_%d_%s" % [bi, bj, type])
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	var inner: String = {"res": "grass", "apt": "grass", "safe": "grass", "beachres": "grass", "park": "grass", "towers": "plaza",
		"hotel": "plaza", "civic": "concrete", "hospital": "concrete", "shops": "plaza", "gas": "asphalt", "ind": "concrete",
		"yard": "concrete", "docks": "concrete"}[type]
	b.rect("pave", x0, z0, x1, z0 + 4, CH)
	b.rect("pave", x0, z1 - 4, x1, z1, CH)
	b.rect("pave", x0, z0 + 4, x0 + 4, z1 - 4, CH)
	b.rect("pave", x1 - 4, z0 + 4, x1, z1 - 4, CH)
	if inner == "asphalt":
		asphalt(x0 + 4, z0 + 4, x1 - 4, z1 - 4, 1, CH)
	else:
		b.rect(inner, x0 + 4, z0 + 4, x1 - 4, z1 - 4, CH, GRASS if inner == "grass" else Color.WHITE)
	b.add_box_collider(Vector3((x0 + x1) * 0.5, CH - 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0, 1.0, z1 - z0))
	_curbs(x0, z0, x1, z1)
	_furniture(x0, z0, x1, z1, type)
	match type:
		"towers": _towers(x0, z0, x1, z1, bi, bj)
		"res", "beachres": _res(x0, z0, x1, z1, type == "beachres", 4, 4)
		"apt": _apt(x0, z0, x1, z1)
		"safe": _safe(x0, z0, x1, z1)
		"park": _park(x0, z0, x1, z1)
		"hospital": _hospital(x0, z0, x1, z1)
		"civic": _civic(x0, z0, x1, z1)
		"gas": _gas(x0, z0, x1, z1)
		"shops": _shops(x0, z0, x1, z1)
		"hotel": _hotel(x0, z0, x1, z1)
		"ind": _ind(x0, z0, x1, z1, bi, bj)
		"yard": _yard(x0, z0, x1, z1)
		"docks": _docks(x0, z0, x1, z1, bi)


func _row(xa: float, xb: float, zc: float, n: int, nz: int, facing: int, styles: Array, fmin: int, fmax: int, opts: Dictionary = {}) -> void:
	var lw := (xb - xa) / n
	for k in n:
		var nx := int((lw - 2.0) / 4.0)
		var fr: Array = [facing]
		if k == 0:
			fr.append(3)
		if k == n - 1:
			fr.append(1)
		var o := opts.duplicate()
		o["fronts"] = fr
		b.building(xa + lw * (k + 0.5), zc, nx, nz, rng.randi_range(fmin, fmax), styles[rng.randi() % styles.size()], o)


func _alley_junk(xa: float, za: float, xb: float, zb: float, n: int) -> void:
	for i in n:
		var nm: String = ["prop_dumpster", "prop_trash_bags", "prop_boxes", "prop_pallet", "prop_crate", "prop_barrel", "prop_bin"][rng.randi() % 7]
		b.prop(nm, v3(rng.randf_range(xa, xb), rng.randf_range(za, zb)), rng.randf() * TAU)


func _towers(x0: float, z0: float, x1: float, z1: float, bi: int, bj: int) -> void:
	var ix0 := x0 + 5.0
	var ix1 := x1 - 5.0
	var iz0 := z0 + 5.0
	var iz1 := z1 - 5.0
	var lw := (ix1 - ix0 - 7.0) * 0.5
	var ld := (iz1 - iz0 - 7.0) * 0.5
	var nx := int(lw / 4.0)
	var nz := int(ld / 4.0)
	for a in 2:
		for c in 2:
			var cx := (ix0 + nx * 2.0) if a == 0 else (ix1 - nx * 2.0)
			var cz := (iz0 + nz * 2.0) if c == 0 else (iz1 - nz * 2.0)
			var fr := [3 if a == 0 else 1, 2 if c == 0 else 0]
			var floors := rng.randi_range(8, 17)
			var style := "office" if (a + c + bi) % 2 == 0 else "grid"
			var landmark := bi == 3 and bj == 0 and a == 0 and c == 1
			if landmark:
				floors = 26
				style = "office"
			var top := b.building(cx, cz, nx, nz, floors, style, {"fronts": fr, "roof_props": not landmark,
				"tint": Color("6fb2ad") if landmark else b.col_of(style)})
			if landmark:
				b.tower_roof = Vector3(cx, top + 0.1, cz)
				b.prop("prop_helipad", Vector3(cx + 2.0, top + 0.06, cz + 2.0))
				b.prop("prop_roof_stair", Vector3(cx - nx * 2.0 + 3.0, top + 0.05, cz - nz * 2.0 + 2.5), PI * 0.5)
				b.prop("prop_antenna", Vector3(cx - nx * 2.0 + 2.0, top + 0.05, cz + nz * 2.0 - 2.0), 0.0, 2.0)
				var door := Vector3(cx - nx * 2.0 - 1.4, CH, cz)
				b.poi("tower", "Cinder Tower", door, "tower", {"roof": Vector3(cx - nx * 2.0 + 6.0, top + 0.2, cz - nz * 2.0 + 2.5)})
				b.interact("elevator_up", door, 2.6, "Take the elevator to the roof", {})
				b.interact("elevator_down", Vector3(cx - nx * 2.0 + 5.2, top + 0.2, cz - nz * 2.0 + 2.5), 2.4, "Take the elevator down", {})
				b.pickups.append({"kind": "parachute", "pos": Vector3(cx + 9.0, top + 0.6, cz - 6.0)})
				b.spawns["special"].append({"veh": "helicopter", "pos": Vector3(cx + 2.0, top + 0.3, cz + 2.0), "yaw": 0.6})
	var mx := (x0 + x1) * 0.5
	var mz := (z0 + z1) * 0.5
	_alley_junk(mx - 2.5, iz0 + 2, mx + 2.5, iz1 - 2, 7)
	_alley_junk(ix0 + 2, mz - 2.5, ix1 - 2, mz + 2.5, 6)
	for s in [-1, 1]:
		b.prop("prop_planter", v3(mx + s * 3.0, z1 - 4.6), 0.0)
		b.prop("prop_planter", v3(mx + s * 3.0, z0 + 4.6), 0.0)
	b.park(Vector3(mx, CH + 0.05, mz - 12), 0.0, "lot")
	b.park(Vector3(mx, CH + 0.05, mz + 12), PI, "lot")


func _house(nm: String, pos: Vector3, yaw: float, palm: bool) -> void:
	var wall := b.col_of("house")
	b.model(nm, pos, yaw, {"WallTint": wall})
	var bas := Basis(Vector3.UP, yaw)
	var has_garage := nm in ["bld_house_a", "bld_house_c"]
	var ab := Assets.mesh(b.K_LAND, nm).get_aabb()
	var front := ab.size.z * 0.5
	if has_garage:
		var gx := ab.size.x * 0.5 - 1.9
		var p0 := pos + bas * Vector3(gx, 0.0, front - 0.6)
		var p1 := pos + bas * Vector3(gx, 0.0, front + 5.4)
		p0.y = 0.0
		p1.y = 0.0
		b.road_quad(p0, p1, 1.7, 1, 1, CH + 0.012)
		if rng.randf() < 0.7:
			var pk := pos + bas * Vector3(gx, 0.0, front + 2.9)
			b.park(Vector3(pk.x, CH + 0.05, pk.z), yaw + (PI if rng.randf() < 0.5 else 0.0), "res")
	for s in [-1.0, 1.0]:
		b.prop("bush_a" if rng.randf() < 0.6 else "bush_b", pos + bas * Vector3(s * (ab.size.x * 0.5 - 1.0), 0, front + 0.9), rng.randf() * TAU, rng.randf_range(0.6, 0.9), false)
	b.prop("tree_palm" if palm else ("tree_round" if rng.randf() < 0.6 else "tree_tall"), pos + bas * Vector3(rng.randf_range(-4, 4), 0, -front - 4.0 - rng.randf() * 3.0), rng.randf() * TAU, rng.randf_range(0.8, 1.15))
	if rng.randf() < 0.5:
		b.prop("flower_clump", pos + bas * Vector3(rng.randf_range(-3, 3), 0, front + 1.6), 0.0, 1.2, false)


func _res(x0: float, z0: float, x1: float, z1: float, beach: bool, n_north: int, n_south: int, skip_south_from: float = 1e9) -> void:
	var models := ["bld_house_a", "bld_house_b", "bld_house_c", "bld_house_d"]
	var lw := (x1 - x0 - 8.0) / 4.0
	for k in n_north:
		var nm: String = models[(k + int(x0) + rng.randi() % 2) % 4]
		var d := Assets.mesh(b.K_LAND, nm).get_aabb().size.z
		_house(nm, v3(x0 + 4.0 + lw * (k + 0.5), z0 + 4.0 + 5.5 + d * 0.5), PI, beach)
	for k in n_south:
		var cx := x0 + 4.0 + lw * (k + 0.5)
		if cx > skip_south_from:
			continue
		var nm2: String = models[(k + 2 + int(z0) + rng.randi() % 2) % 4]
		var d2 := Assets.mesh(b.K_LAND, nm2).get_aabb().size.z
		_house(nm2, v3(cx, z1 - 4.0 - 5.5 - d2 * 0.5), 0.0, beach)
	var mz := (z0 + z1) * 0.5
	for k in 18:
		b.prop("prop_fence_picket", v3(x0 + 6.0 + k * 4.0, mz), 0.0)
		if x0 + 6.0 + k * 4.0 > x1 - 10.0:
			break
	for k in 3:
		b.prop("prop_fence_picket", v3(x0 + 4.0 + lw * (k + 1), mz - 8.0), PI * 0.5)
		b.prop("prop_fence_picket", v3(x0 + 4.0 + lw * (k + 1), mz + 8.0), PI * 0.5)
	b.scatter("grass_clump", x0 + 5, z0 + 5, x1 - 5, z1 - 5, 40, 0.8, 1.4, false)
	b.scatter("flower_clump", x0 + 5, mz - 12, x1 - 5, mz + 12, 10, 0.9, 1.3, false)


func _apt(x0: float, z0: float, x1: float, z1: float) -> void:
	_row(x0 + 5, x1 - 5, z0 + 5 + 8, 3, 4, 2, ["apt", "apt", "brick"], 4, 7)
	_row(x0 + 5, x1 - 5, z1 - 5 - 8, 3, 4, 0, ["apt", "aptshop", "brick"], 4, 7)
	var mz := (z0 + z1) * 0.5
	asphalt(x0 + 8, mz - 5.5, x1 - 8, mz + 5.5, 7)
	for k in 7:
		b.park(Vector3(x0 + 13 + k * 8.2, CH + 0.05, mz - 2.9), PI * 0.5 if k % 2 == 0 else -PI * 0.5, "lot")
	for k in 6:
		b.prop("tree_round", v3(x0 + 10 + k * 12.0, mz + 9.0 if k % 2 == 0 else mz - 9.0), rng.randf() * TAU, 0.9)
	b.prop("prop_picnic_table", v3(x0 + 20, mz + 9.5), 0.3)
	b.prop("prop_bench", v3(x1 - 22, mz + 9.5), PI)
	_alley_junk(x0 + 8, mz + 7, x1 - 8, mz + 10, 4)


func _safe(x0: float, z0: float, x1: float, z1: float) -> void:
	_res(x0, z0, x1, z1, false, 4, 4, x1 - 34.0)
	var hp := v3(x1 - 4.0 - 7.5, z1 - 4.0 - 6.5)
	var m := b.model("bld_safehouse", hp, 0.0, {"WallTint": Color("3d7ea6"), "AwningTint": Color("f2b705"), "SignTint": Color("ffd23e")})
	var t := m.transform
	for it in [["int_bed", Vector3(3.3, 0.1, -2.9), 0.0], ["int_wardrobe", Vector3(-3.4, 0.1, -3.9), 0.0], ["int_sofa", Vector3(-3.9, 0.1, 0.6), -PI * 0.5],
			["int_tv", Vector3(0.4, 0.1, 0.4), PI * 0.5], ["int_table", Vector3(-1.6, 0.1, -1.6), 0.0], ["int_chair", Vector3(-1.6, 0.1, -0.8), PI]]:
		b.prop(it[0], t * (it[1] as Vector3), it[2])
	b.poi("safehouse", "Safehouse", hp + Vector3(-0.4, 0, 6.8), "home", {"spawn": hp + Vector3(-0.4, 0.2, 6.5), "inside": t * Vector3(-0.4, 0.3, 2.0)})
	b.interact("bed", t * Vector3(2.2, 0.2, -2.9), 1.7, "Sleep and save the game", {})
	b.interact("wardrobe", t * Vector3(-3.4, 0.2, -3.0), 1.6, "Open wardrobe", {})
	# garage pad west of the house
	var gx := hp.x - 12.5
	asphalt(gx - 4.5, hp.z - 4.0, gx + 4.5, hp.z + 8.5, 7)
	b.interact("garage", Vector3(gx, CH, hp.z + 7.6), 2.2, "Personal garage: store / retrieve vehicles", {})
	b.poi("garage", "Personal Garage", Vector3(gx, CH, hp.z + 2.0), "garage", {"slots": [Vector3(gx - 2.3, CH + 0.05, hp.z + 1.5), Vector3(gx + 2.3, CH + 0.05, hp.z + 1.5)], "yaw": 0.0})
	b.prop("prop_planter", hp + Vector3(3.5, 0, 5.3), 0.0)
	b.prop("prop_mailbox", hp + Vector3(-3.4, 0, 9.8), 0.0)


func _park(x0: float, z0: float, x1: float, z1: float) -> void:
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	b.rect("plaza", cx - 9, cz - 9, cx + 9, cz + 9, CH + 0.012)
	b.rect("plaza", cx - 1.8, z0 + 4, cx + 1.8, cz - 9, CH + 0.012)
	b.rect("plaza", cx - 1.8, cz + 9, cx + 1.8, z1 - 4, CH + 0.012)
	b.rect("plaza", x0 + 4, cz - 1.8, cx - 9, cz + 1.8, CH + 0.012)
	b.rect("plaza", cx + 9, cz - 1.8, x1 - 4, cz + 1.8, CH + 0.012)
	b.prop("prop_fountain", v3(cx, cz))
	b.prop("prop_statue", v3(cx, z0 + 12.0))
	for a in 4:
		var ang := a * PI * 0.5 + PI * 0.25
		b.prop("prop_bench", v3(cx + cos(ang) * 7.0, cz + sin(ang) * 7.0), -ang + PI * 0.5 + PI)
		b.prop("prop_park_lamp", v3(cx + cos(ang) * 9.5, cz + sin(ang) * 9.5))
		b.prop("prop_bin", v3(cx + cos(ang + 0.3) * 7.5, cz + sin(ang + 0.3) * 7.5))
	for s in [-1.0, 1.0]:
		for k in 3:
			b.prop("prop_park_lamp", v3(cx + s * 2.6, cz + (14.0 + k * 9.0) * s))
			b.prop("prop_park_lamp", v3(cx + (14.0 + k * 9.0) * s, cz - s * 2.6))
			b.prop("prop_bench", v3(cx + s * 3.0, cz + (18.0 + k * 9.0) * s), s * PI * 0.5)
	var placed := 0
	var tries := 0
	while placed < 34 and tries < 400:
		tries += 1
		var px := rng.randf_range(x0 + 7, x1 - 7)
		var pz := rng.randf_range(z0 + 7, z1 - 7)
		if absf(px - cx) < 4.0 or absf(pz - cz) < 4.0 or (absf(px - cx) < 12.0 and absf(pz - cz) < 12.0):
			continue
		b.prop(["tree_round", "tree_round", "tree_tall", "tree_pine"][rng.randi() % 4], v3(px, pz), rng.randf() * TAU, rng.randf_range(0.9, 1.4))
		placed += 1
	for q in [[x0 + 6, z0 + 6, cx - 5, cz - 5], [cx + 5, z0 + 6, x1 - 6, cz - 5], [x0 + 6, cz + 5, cx - 5, z1 - 6], [cx + 5, cz + 5, x1 - 6, z1 - 6]]:
		b.scatter("bush_a", q[0], q[1], q[2], q[3], 4, 0.7, 1.2, false)
		b.scatter("bush_b", q[0], q[1], q[2], q[3], 3, 0.7, 1.2, false)
		b.scatter("grass_clump", q[0], q[1], q[2], q[3], 45, 0.8, 1.5, false)
		b.scatter("flower_clump", q[0], q[1], q[2], q[3], 12, 0.9, 1.4, false)
		b.scatter("rock_c", q[0], q[1], q[2], q[3], 2, 0.8, 1.6, false)
	b.prop("prop_picnic_table", v3(x0 + 16, z1 - 16), 0.4)
	b.prop("prop_picnic_table", v3(x0 + 22, z1 - 22), 1.2)
	b.prop("prop_picnic_table", v3(x1 - 18, z0 + 18), 0.9)
	b.poi("park", "Lantern Park", v3(cx, cz + 12), "park")
	b.spawns["park"] = Rect2(x0 + 6, z0 + 6, x1 - x0 - 12, z1 - z0 - 12)


func _hospital(x0: float, z0: float, x1: float, z1: float) -> void:
	var cx := (x0 + x1) * 0.5
	var hz := z1 - 4.0 - 16.5
	b.model("bld_hospital", v3(cx, hz), 0.0)
	asphalt(x0 + 7, z0 + 7, x1 - 7, z0 + 30, 7)
	for k in 9:
		b.park(Vector3(x0 + 12 + k * 6.6, CH + 0.05, z0 + 12.5), 0.0 if k % 2 == 0 else PI, "lot")
	for k in 2:
		b.park(Vector3(cx + 20 + k * 5.0, CH + 0.05, hz + 15.0), 0.0, "ambulance")
	asphalt(cx + 16, hz + 9.5, cx + 29, hz + 20.5, 7)
	for s in [-1.0, 1.0]:
		b.prop("tree_round", v3(cx + s * 22, hz + 13), 0.0, 1.0)
		b.prop("prop_planter", v3(cx + s * 6.5, hz + 15.5), 0.0)
		b.prop("prop_bench", v3(cx + s * 11, hz + 10.5), 0.0)
	b.poi("hospital", "Mercy General Hospital", v3(cx, hz + 17.5), "hospital", {"spawn": Vector3(cx - 4.0, CH + 0.2, hz + 18.0)})
	b.interact("hospital", v3(cx, hz + 11.0), 2.4, "Get patched up ($150)", {})
	_alley_junk(x0 + 8, z0 + 32, x1 - 8, z0 + 34, 3)


func _civic(x0: float, z0: float, x1: float, z1: float) -> void:
	var cx := (x0 + x1) * 0.5
	var pz := z1 - 4.0 - 13.0
	b.model("bld_police", v3(cx, pz), 0.0)
	var dz := z0 + 4.0 + 15.0
	b.model("bld_parking", v3(cx, dz), 0.0)
	asphalt(x0 + 4, dz + 8, cx - 18, dz + 14, 1)
	asphalt(x0 + 6, dz + 15, x1 - 6, pz - 9, 7)
	for k in 5:
		b.park(Vector3(cx - 16 + k * 8.0, CH + 0.05, pz - 12.5), PI * 0.5, "police")
	for k in 6:
		b.park(Vector3(cx - 15 + k * 5.6, CH + 0.05, dz - 1.0), 0.0 if k % 2 == 0 else PI, "lot")
		b.park(Vector3(cx - 16 + k * 3.6 * 1.6, CH + 3.66, dz + 0.5), 0.0, "lot")
	b.poi("police", "CBPD Headquarters", v3(cx, pz + 13.0), "police", {"spawn": Vector3(cx + 5.0, CH + 0.2, pz + 14.0)})
	b.poi("parking", "Civic Parking Deck", v3(cx - 22, dz + 11), "parking")
	b.stunts.append({"pos": Vector3(cx + 12.0, CH + 3.6, dz - 11.0), "name": "Deck Dive"})
	for s in [-1.0, 1.0]:
		b.prop("tree_round", v3(cx + s * 19, pz + 9), 0.0, 0.9)
		b.prop("prop_barrier_police", v3(cx + s * 9, pz + 12.8), 0.0)


func _shop_shell(pos: Vector3, yaw: float, kind: String, label: String, wall: Color, awn: Color, sign_c: Color, icon: String) -> Transform3D:
	var m := b.model("bld_shop", pos, yaw, {"WallTint": wall, "AwningTint": awn, "SignTint": sign_c})
	var t := m.transform
	b.prop("int_counter", t * Vector3(0, 0.1, -2.2), yaw)
	b.spawns["clerks"].append({"pos": t * Vector3(0, 0.2, -3.0), "yaw": yaw, "kind": kind})
	b.interact(kind, t * Vector3(0, 0.2, -1.2), 1.8, "Browse " + label, {})
	b.poi(kind, label, t * Vector3(0, 0, 5.4), icon)
	return t


func _shops(x0: float, z0: float, x1: float, z1: float) -> void:
	var zs := z1 - 4.0 - 5.0
	var t := _shop_shell(v3(x0 + 15, zs), 0.0, "gunshop", "Brass Lantern Arms", Color("5d5a52"), Color("b3472e"), Color("ff9a3c"), "gun")
	for s in [-1.0, 1.0]:
		b.prop("int_gun_rack", t * Vector3(s * 4.55, 0.1, -0.5), -s * PI * 0.5)
	b.prop("int_gunsmith_bench", t * Vector3(-3.4, 0.1, -3.2), 0.0)
	b.interact("gunbench", t * Vector3(-3.4, 0.2, -2.3), 1.5, "Use weapon workbench", {})
	b.prop("int_shelf", t * Vector3(3.3, 0.1, -3.4), 0.0)
	t = _shop_shell(v3(x0 + 35, zs), 0.0, "clothes", "Thread & Tide Clothing", Color("f0ece2"), Color("2f9c95"), Color("3fe0ff"), "shirt")
	for s in [-1.0, 1.0]:
		b.prop("int_clothes_rack", t * Vector3(s * 3.2, 0.1, 0.8), PI * 0.5)
		b.prop("int_clothes_rack", t * Vector3(s * 3.2, 0.1, -1.6), PI * 0.5)
	b.prop("int_mirror", t * Vector3(4.6, 0.1, -3.0), -PI * 0.5)
	t = _shop_shell(v3(x0 + 55, zs), 0.0, "barber", "Fade Factory Barbers", Color("e3a58c"), Color("7d2a8c"), Color("ff4fa3"), "scissors")
	for k in 2:
		b.prop("int_barber_chair", t * Vector3(-2.6 + k * 2.6, 0.1, 0.6), PI)
		b.prop("int_mirror", t * Vector3(-2.6 + k * 2.6, 0.1, 3.5), PI)
	_row(x0 + 5, x1 - 5, z0 + 5 + 10, 3, 5, 2, ["brickshop", "aptshop", "brickshop"], 3, 6)
	var mz := (z0 + z1) * 0.5 + 6.0
	for k in 4:
		b.prop("prop_planter", v3(x0 + 14 + k * 14.0, mz), 0.0)
		b.prop("prop_picnic_table", v3(x0 + 20 + k * 14.0, mz + 3.0), rng.randf())
	b.prop("prop_atm", v3(x0 + 25, zs + 4.6), 0.0)
	b.interact("atm", v3(x0 + 25, zs + 5.6), 1.5, "Use ATM", {})
	b.prop("prop_vending", v3(x0 + 45, zs + 4.6), 0.0)
	_alley_junk(x0 + 8, mz - 9, x1 - 8, mz - 6, 5)


func _hotel(x0: float, z0: float, x1: float, z1: float) -> void:
	_row(x0 + 5, x1 - 5, z0 + 5 + 10, 3, 5, 2, ["aptshop", "aptshop", "apt"], 5, 9)
	_row(x0 + 5, x1 - 5, z1 - 5 - 10, 2, 5, 0, ["aptshop", "aptshop"], 7, 12)
	var mz := (z0 + z1) * 0.5
	for k in 6:
		b.prop("tree_palm", v3(x0 + 10 + k * 11.0, mz + (2.0 if k % 2 == 0 else -2.0)), rng.randf() * TAU, rng.randf_range(0.85, 1.1))
		b.prop("prop_planter", v3(x0 + 15 + k * 11.0, mz), 0.0)
	b.prop("prop_bench", v3(x0 + 20, mz - 3.5), 0.0)
	b.prop("prop_bench", v3(x1 - 20, mz + 3.5), PI)
	b.park(Vector3(x0 + 9, CH + 0.05, mz), 0.0, "lot")
	b.park(Vector3(x1 - 9, CH + 0.05, mz), PI, "lot")


func _containers(xa: float, za: float, xb: float, zb: float, rows: int, per_row: int, yaw: float = 0.0) -> void:
	for r in rows:
		for k in per_row:
			if rng.randf() < 0.18:
				continue
			var p := v3(xa + (xb - xa) * (k + 0.5) / per_row, za + (zb - za) * (r + 0.5) / rows)
			var stack := 1 + (rng.randi() % 3 if rng.randf() < 0.6 else 0)
			for s in stack:
				b.prop("prop_container", p + Vector3(0, s * 2.6, 0), yaw + (rng.randf_range(-0.03, 0.03)), 1.0, true, b.col_of("container"))


func _ind(x0: float, z0: float, x1: float, z1: float, bi: int, bj: int) -> void:
	var cx := (x0 + x1) * 0.5
	b.building(cx - 12, z1 - 5 - 12, 10, 6, 2, "ind", {"fronts": [0]})
	b.building(cx + 14, z0 + 5 + 12, 8, 6, 2 + (bi + bj) % 2, "ind", {"fronts": [2]})
	_containers(x0 + 7, z0 + 8, cx - 6, z0 + 26, 2, 3, PI * 0.5)
	_containers(cx + 12, z1 - 26, x1 - 8, z1 - 9, 2, 2, PI * 0.5)
	for k in 5:
		b.prop(["prop_pallet", "prop_crate", "prop_barrel", "prop_barrel_explosive", "prop_tire_stack"][k], v3(cx - 30 + k * 2.2, z1 - 31.5), rng.randf())
	_alley_junk(x0 + 8, (z0 + z1) * 0.5 - 3, x1 - 8, (z0 + z1) * 0.5 + 3, 8)
	for k in 14:
		b.prop("prop_fence_chain", v3(x0 + 6.0 + k * 4.0, z0 + 4.6), 0.0)
	b.park(Vector3(cx - 28, CH + 0.05, z1 - 34), PI * 0.5, "ind")
	b.park(Vector3(cx + 30, CH + 0.05, z0 + 32), -PI * 0.5, "ind")
	b.park(Vector3(cx, CH + 0.05, (z0 + z1) * 0.5), 0.0, "ind")
	if bi == 5 and bj == 0:
		b.model("bld_water_tower", v3(x1 - 14, z1 - 14), 0.0)
		b.ladders.append({"base": Vector3(cx + 14 + 16.4, CH, z0 + 5 + 12), "top": CH + 4.2 + 3.4 * 2 + 0.9, "normal": Vector3(1, 0, 0)})
		b.prop("prop_ladder", Vector3(cx + 14 + 16.25, CH, z0 + 5 + 12), PI * 0.5, 1.9, false)


func _gas(x0: float, z0: float, x1: float, z1: float) -> void:
	var gp := v3(x0 + 27, z1 - 21)
	b.model("bld_gas_canopy", gp, 0.0)
	var t := _shop_shell(v3(x0 + 27, z1 - 39), 0.0, "store", "Sunny Mart", Color("f2efe8"), Color("e9792a"), Color("ffd23e"), "store")
	b.prop("int_shelf", t * Vector3(-3.3, 0.1, 0.4), PI * 0.5)
	b.prop("int_shelf", t * Vector3(3.3, 0.1, 0.4), -PI * 0.5)
	b.prop("prop_vending", t * Vector3(-3.6, 0.0, 4.5), 0.0)
	var mp := v3(x1 - 4.0 - 10.0, z1 - 4.0 - 8.0)
	var m := b.model("bld_garage", mp, 0.0, {"WallTint": Color("2d3142"), "SignTint": Color("ff9a3c"), "AwningTint": Color("f2b705")})
	var mt := m.transform
	b.prop("int_tool_chest", mt * Vector3(-5.8, 0.1, -4.6), 0.0)
	b.prop("int_workbench", mt * Vector3(3.5, 0.1, -5.2), 0.0)
	b.prop("prop_tire_stack", mt * Vector3(5.8, 0.1, -2.0), 0.0)
	b.prop("prop_barrel", mt * Vector3(-5.9, 0.1, 1.0), 0.0)
	b.poi("modshop", "Torque Bay Customs", mt * Vector3(0, 0, 8.5), "wrench", {"bay": mt * Vector3(0, 0.15, 0.0), "yaw": 0.0, "exit": mt * Vector3(0, 0.2, 10.0)})
	b.interact("modshop", mt * Vector3(0, 0.15, 0.0), 3.6, "Enter Torque Bay Customs", {"vehicle": true})
	b.poi("gas", "Sunny Fuel", gp + Vector3(0, 0, 6), "fuel")
	b.building(x1 - 20, z0 + 5 + 10, 6, 4, 2, "ind", {"fronts": [0]})
	for k in 4:
		b.park(Vector3(x0 + 9 + k * 5.5, CH + 0.05, z0 + 10), 0.0, "lot")
	b.prop("prop_barrel_explosive", v3(x0 + 44, z1 - 34), 0.0)
	b.prop("prop_barrel_explosive", v3(x0 + 45, z1 - 35.2), 0.0)
	b.prop("prop_dumpster", v3(x0 + 40, z1 - 43), 0.0)
	_containers(x0 + 8, z0 + 20, x0 + 22, z0 + 30, 1, 2, 0.0)
	b.park(Vector3(mp.x - 13, CH + 0.05, mp.z + 2), 0.0, "lot")


func _yard(x0: float, z0: float, x1: float, z1: float) -> void:
	# shooting range along the north side
	var rz := z0 + 14.0
	var fx := x0 + 12.0
	b.rect("plaza", fx - 3, rz - 7, fx + 3, rz + 7, CH + 0.01)
	for k in 3:
		b.prop("prop_sandbags", v3(fx + 1.6, rz - 4.0 + k * 4.0), PI * 0.5)
	var targets: Array = []
	for d in [14.0, 24.0, 38.0]:
		for k in 3:
			var tp := v3(fx + d, rz - 4.0 + k * 4.0)
			b.prop("prop_target_stand", tp, 0.0)
			targets.append(tp + Vector3(0, 1.55, 0))
	for k in 5:
		b.prop("prop_barrier_jersey", v3(fx + 43.0, rz - 6.0 + k * 3.0), 0.0)
		b.prop("prop_sandbags", v3(fx + 41.8, rz - 6.0 + k * 3.0), PI * 0.5)
	for k in 12:
		b.prop("prop_fence_chain", v3(fx + k * 4.0, rz + 8.5), 0.0)
	b.poi("range", "Ironworks Shooting Range", v3(fx, rz), "target", {"targets": targets, "dir": Vector3(1, 0, 0)})
	b.interact("range", v3(fx - 0.5, rz), 2.2, "Start shooting range challenge", {})
	var cx := (x0 + x1) * 0.5
	b.building(cx + 14, z1 - 5 - 10, 8, 5, 2, "ind", {"fronts": [0]})
	_containers(x0 + 8, z1 - 36, cx - 6, z1 - 10, 3, 3, PI * 0.5)
	_alley_junk(x0 + 8, rz + 12, x1 - 8, rz + 18, 6)
	b.park(Vector3(cx + 8, CH + 0.05, rz + 16), PI * 0.5, "ind")


func _docks(x0: float, z0: float, x1: float, z1: float, bi: int) -> void:
	var cx := (x0 + x1) * 0.5
	b.building(cx, z0 + 5 + 10, 10, 5, 2, "ind", {"fronts": [2]})
	_containers(x0 + 8, z0 + 30, x1 - 8, z1 - 10, 4, 4, PI * 0.5)
	for k in 14:
		b.prop("prop_fence_chain", v3(x0 + 6.0 + k * 4.0, z1 - 4.6), 0.0)
		if x0 + 6.0 + k * 4.0 > cx - 8 and x0 + 6.0 + k * 4.0 < cx + 6:
			continue
	b.park(Vector3(x0 + 9, CH + 0.05, z0 + 24), 0.0, "ind")
	b.park(Vector3(x1 - 9, CH + 0.05, z0 + 24), PI, "ind")
	if bi == 5:
		b.building(x1 - 12, z0 + 5 + 26, 4, 3, 2, "brick", {"fronts": [3]})


func _pier(x: float, za: float, n: int) -> void:
	for k in n:
		var pz := za + 4.0 + k * 8.0
		b.prop("bld_pier", Vector3(x, CH, pz), 0.0, 1.0, false)
		b.add_box_collider(Vector3(x, CH - 0.15, pz), Vector3(5.0, 0.3, 8.0))
		for s in [-1.0, 1.0]:
			b.add_box_collider(Vector3(x + s * 2.4, CH + 0.07, pz), Vector3(0.14, 0.2, 8.0))


func _coast() -> void:
	b.chunk("coast")
	b.rect("pave", -271, 176.5, 52, 184, CH)
	b.rect("concrete", 52, 176.5, 271, 194, CH)
	b.add_box_collider(Vector3(-109.5, CH - 0.5, 180.25), Vector3(323, 1.0, 7.5))
	b.add_box_collider(Vector3(161.5, CH - 0.5, 185.25), Vector3(219, 1.0, 17.5))
	var n := 135
	for k in n:
		_curb(Vector3(-270.0 + (k + 0.5) * 4.0, 0, 176.5), PI, 1.0)
	var x := -262.0
	var k2 := 0
	while x < 268.0:
		b.prop("prop_street_lamp", Vector3(x, CH, 177.4), PI)
		if x < 44.0:
			b.prop("tree_palm", Vector3(x + 9.0, CH, 182.6), rng.randf() * TAU, rng.randf_range(0.9, 1.15))
			if k2 % 2 == 0:
				b.prop("prop_bench", Vector3(x + 15.0, CH, 181.5), PI)
			if k2 % 3 == 0:
				b.prop("prop_bin", Vector3(x + 17.0, CH, 181.5), 0.0)
		x += 27.0
		k2 += 1
	# beach furniture
	for i in 26:
		var bx := rng.randf_range(-255.0, 28.0)
		var bz := rng.randf_range(188.0, 199.0)
		if absf(bx + 40.0) < 6.0:
			continue
		var by := L.height(bx, bz)
		b.prop("prop_umbrella", Vector3(bx, by, bz), rng.randf() * TAU, 1.0, true, b.col_of("awning"))
		b.prop("prop_lounger", Vector3(bx + 1.2, by, bz + 0.4), rng.randf_range(-0.4, 0.4))
	b.prop("prop_lifeguard_tower", Vector3(-120.0, L.height(-120.0, 192.0), 192.0), PI)
	b.prop("prop_lifeguard_tower", Vector3(-210.0, L.height(-210.0, 192.0), 192.0), PI)
	b.poi("beach", "Coral Beach", Vector3(-120, 0.2, 188), "beach")
	for i in 7:
		b.prop("prop_buoy", Vector3(-250.0 + i * 45.0, L.WATER, 246.0 + sin(i * 2.1) * 3.0), 0.0, 1.0, false)
	# long pier + lighthouse island
	_pier(-40.0, 184.0, 10)
	b.prop("prop_park_lamp", Vector3(-42.2, CH, 200), 0.0)
	b.prop("prop_park_lamp", Vector3(-37.8, CH, 230), 0.0)
	b.prop("prop_bench", Vector3(-38.2, CH, 215), -PI * 0.5)
	var ly := L.height(-40.0, 276.0)
	b.model("bld_lighthouse", Vector3(-40.0, ly - 0.3, 277.0), PI)
	for i in 9:
		var a := i * 0.7
		b.prop("rock_a" if i % 2 == 0 else "rock_b", Vector3(-40.0 + cos(a) * 11.0, L.height(-40.0 + cos(a) * 11.0, 274.0 + sin(a) * 11.0) - 0.2, 274.0 + sin(a) * 11.0), a, rng.randf_range(0.7, 1.2))
	b.poi("lighthouse", "Ember Point Lighthouse", Vector3(-40, 1.6, 268), "lighthouse")
	b.pickups.append({"kind": "scuba", "pos": Vector3(-40.0, CH + 0.6, 259.0)})
	b.pickups.append({"kind": "cash", "pos": Vector3(-33.0, ly + 0.5, 281.0), "amount": 1500})
	# docks: quay fence, crane, piers, boats, ladders
	for k in 54:
		var fxp := 56.0 + k * 4.0
		if absf(fxp - 110.0) < 5.0 or absf(fxp - 170.0) < 5.0 or absf(fxp - 230.0) < 5.0 or absf(fxp - 140.0) < 2.5 or absf(fxp - 200.0) < 2.5:
			continue
		b.prop("prop_fence_iron", Vector3(fxp, CH, 193.6), 0.0)
	b.model("bld_crane", Vector3(200.0, CH, 185.0), -PI * 0.5)
	b.model("bld_crane", Vector3(254.0, CH, 185.0), -PI * 0.5)
	_containers(60, 178.5, 96, 191, 2, 3, 0.0)
	for px in [110.0, 170.0, 230.0]:
		_pier(px, 194.0, 6)
		b.prop("prop_park_lamp", Vector3(px + 2.0, CH, 240.0 if px < 220.0 else 216.0), 0.0)
		for k in 2:
			b.spawns["boats"].append({"pos": Vector3(px - 4.4, L.WATER + 0.25, 208.0 + k * 20.0), "yaw": PI, "veh": "speedboat" if (k + int(px)) % 3 != 0 else "policeboat"})
			b.spawns["boats"].append({"pos": Vector3(px + 4.4, L.WATER + 0.25, 214.0 + k * 20.0), "yaw": 0.0, "veh": "speedboat"})
	for lx in [140.0, 200.0, 86.0]:
		b.prop("prop_ladder", Vector3(lx, -5.6, 194.25), 0.0, 1.0, false)
		b.ladders.append({"base": Vector3(lx, -5.4, 194.75), "top": CH + 0.1, "normal": Vector3(0, 0, 1)})
	for lx2 in [-42.9, -37.1]:
		b.prop("prop_ladder", Vector3(lx2, -5.2, 252.0), PI * 0.5 if lx2 < -40 else -PI * 0.5, 1.0, false)
		b.ladders.append({"base": Vector3(lx2 + (-0.5 if lx2 < -40 else 0.5), -5.0, 252.0), "top": CH + 0.1, "normal": Vector3(-1 if lx2 < -40 else 1, 0, 0)})
	b.poi("marina", "Harbor Marina", Vector3(170, CH, 190), "anchor")
	# underwater scenery and wreck
	var wy := L.height(165.0, 268.0)
	b.model("prop_wreck", Vector3(165.0, wy - 0.8, 268.0), 0.6)
	b.poi("wreck", "Sunken Trawler", Vector3(165, L.WATER, 268), "wreck")
	b.pickups.append({"kind": "cash", "pos": Vector3(163.0, wy + 2.4, 264.0), "amount": 5000})
	b.pickups.append({"kind": "cash", "pos": Vector3(-150.0, L.height(-150.0, 262.0) + 0.5, 262.0), "amount": 2500})
	b.prop("prop_chest", Vector3(163.0, wy + 1.6, 264.0), 0.4, 1.0, false)
	b.prop("prop_chest", Vector3(-150.0, L.height(-150.0, 262.0), 262.0), 1.4, 1.0, false)
	for i in 150:
		var sx := rng.randf_range(-290.0, 300.0)
		var sz := rng.randf_range(214.0, 330.0)
		var sy := L.height(sx, sz)
		if sy > -2.6:
			continue
		var nm: String = ["seaweed", "seaweed", "coral", "rock_a", "rock_c", "seaweed"][rng.randi() % 6]
		b.prop(nm, Vector3(sx, sy - 0.05, sz), rng.randf() * TAU, rng.randf_range(0.8, 1.8), nm == "rock_a")


func _airport() -> void:
	b.chunk("airport")
	var rw: Dictionary = L.RUNWAY
	b.road_quad(Vector3(rw.x0, 0, rw.z), Vector3(rw.x1, 0, rw.z), rw.hw, 1, 4, 0.03)
	asphalt(14, -237, 287, -186, 1, 0.02)
	b.road_quad(Vector3(88, 0, -178), Vector3(88, 0, -186), 5.5, 1, 1, 0.012)
	for hx in [62.0, 104.0]:
		b.model("bld_hangar", Vector3(hx, 0.02, -205.5), PI, {"CorrTint": Color("9fb6bf") if hx < 80 else Color("d9b67a"), "SignTint": Color("3fe0ff")})
	b.model("bld_control_tower", Vector3(148.0, 0.02, -196.0), 0.0)
	b.prop("prop_helipad", Vector3(190.0, 0.03, -208.0))
	b.anim_scene("props/radar", "", Vector3(168.0, 0.02, -193.0))
	b.add_box_collider(Vector3(168.0, 4.0, -193.0), Vector3(2.6, 8.0, 2.6))
	b.prop("prop_helipad", Vector3(226.0, 0.03, -208.0))
	b.prop("prop_flagpole", Vector3(132.0, 0.0, -188.0), 0.0, 1.0, true, Color("e9792a"))
	for k in 92:
		var fx := -78.0 + k * 4.0
		if fx > 80.0 and fx < 96.0:
			continue
		b.prop("prop_fence_chain", Vector3(fx, 0, -181.0), 0.0)
	for k in 26:
		b.prop("prop_fence_chain", Vector3(-80.0, 0, -183.0 - k * 4.0), PI * 0.5)
	for k in 10:
		b.prop("prop_bollard", Vector3(rw.x0 + 4.0 + k * 38.0, 0, rw.z - rw.hw - 1.0), 0.0, 0.5)
		b.prop("prop_bollard", Vector3(rw.x0 + 4.0 + k * 38.0, 0, rw.z + rw.hw + 1.0), 0.0, 0.5)
	b.prop("prop_barrier_plastic", Vector3(84.0, 0, -184.0), PI * 0.5)
	_containers(250, -200, 280, -190, 1, 2, 0.0)
	b.spawns["air"] = [
		{"veh": "plane", "pos": Vector3(250.0, 0.3, -222.0), "yaw": PI * 0.5},
		{"veh": "jet", "pos": Vector3(104.0, 0.3, -206.0), "yaw": 0.0},
		{"veh": "plane", "pos": Vector3(62.0, 0.3, -206.0), "yaw": 0.0},
		{"veh": "helicopter", "pos": Vector3(190.0, 0.3, -208.0), "yaw": 0.0},
		{"veh": "policeheli", "pos": Vector3(226.0, 0.3, -208.0), "yaw": 0.0}]
	b.poi("airport", "Cinder Field Airport", Vector3(120, 0, -190), "plane", {"spawn": Vector3(170.0, 0.3, -192.0)})
	b.pickups.append({"kind": "parachute", "pos": Vector3(152.0, 0.7, -190.5)})
	b.stunts.append({"pos": Vector3(-60.0, 0.0, rw.z), "name": "Runway Rocket"})
	b.prop("prop_stunt_ramp", Vector3(-58.0, 0.02, rw.z + 22.0), PI * 0.5)


func _hill() -> void:
	b.chunk("hill")
	var placed := 0
	var tries := 0
	while placed < 150 and tries < 900:
		tries += 1
		var x := rng.randf_range(-338.0, -96.0)
		var z := rng.randf_range(-338.0, -183.0)
		var h := L.height(x, z)
		if x > -100.0 or (x > -300.0 and z > -300.0 and L.path_info(x, z).x < 7.0):
			continue
		if Vector2(x - L.HILL_TOP.x, z - L.HILL_TOP.z).length() < 13.0:
			continue
		b.prop(["tree_pine", "tree_pine", "tree_round", "tree_tall", "tree_pine"][rng.randi() % 5], Vector3(x, h - 0.15, z), rng.randf() * TAU, rng.randf_range(0.9, 1.6))
		placed += 1
	for i in 260:
		var x2 := rng.randf_range(-300.0, -98.0)
		var z2 := rng.randf_range(-300.0, -184.0)
		if L.path_info(x2, z2).x < 5.0:
			continue
		var nm: String = ["grass_clump", "grass_clump", "grass_clump", "flower_clump", "bush_a", "bush_b", "rock_c", "rock_a", "grass_clump"][rng.randi() % 9]
		b.prop(nm, Vector3(x2, L.height(x2, z2) - 0.05, z2), rng.randf() * TAU, rng.randf_range(0.8, 1.6), nm == "rock_a")
	for i in 5:
		var x3 := rng.randf_range(-280.0, -120.0)
		var z3 := rng.randf_range(-290.0, -200.0)
		if L.path_info(x3, z3).x > 8.0:
			b.prop("log" if i % 2 == 0 else "prop_stump", Vector3(x3, L.height(x3, z3), z3), rng.randf() * TAU)
	var top := L.HILL_TOP
	var ty := L.height(top.x, top.z)
	b.prop("prop_antenna", Vector3(top.x + 7.0, L.height(top.x + 7.0, top.z - 5.0), top.z - 5.0), 0.0, 2.6)
	b.prop("prop_bench", Vector3(top.x - 3.0, L.height(top.x - 3.0, top.z + 7.0), top.z + 7.0), 0.0)
	b.prop("prop_bench", Vector3(top.x + 2.0, L.height(top.x + 2.0, top.z + 7.5), top.z + 7.5), 0.0)
	b.prop("prop_flagpole", Vector3(top.x - 7.0, L.height(top.x - 7.0, top.z - 3.0), top.z - 3.0), 0.0, 1.0, true, Color("2f9c95"))
	b.prop("prop_picnic_table", Vector3(top.x - 2.0, ty, top.z - 6.0), 0.5)
	b.prop("prop_stunt_ramp", Vector3(top.x + 9.0, L.height(top.x + 9.0, top.z + 9.0) - 0.1, top.z + 9.0), PI * 0.75 + PI)
	b.stunts.append({"pos": Vector3(top.x + 9.0, ty, top.z + 9.0), "name": "Ember Hill Leap"})
	b.poi("viewpoint", "Ember Hill Viewpoint", Vector3(top.x, ty, top.z), "view")
	b.pickups.append({"kind": "parachute", "pos": Vector3(top.x - 5.0, ty + 0.6, top.z + 3.0)})
	b.spawns["wild"] = Rect2(-296, -296, 190, 108)
	# dirt track surface marker posts
	for k in L.HILL_PATH.size():
		var hp: Vector2 = L.HILL_PATH[k]
		if k % 2 == 1:
			b.prop("prop_bollard", Vector3(hp.x + 4.2, L.height(hp.x + 4.2, hp.y), hp.y), 0.0)


func _outskirts() -> void:
	b.chunk("outskirts")
	for i in 80:
		var z := rng.randf_range(-176.0, 174.0)
		b.prop(["tree_round", "tree_tall", "tree_pine"][rng.randi() % 3], Vector3(rng.randf_range(-298.0, -273.0), 0.0, z), rng.randf() * TAU, rng.randf_range(0.9, 1.5))
		var te := ["tree_round", "tree_tall", "tree_pine"][rng.randi() % 3] as String
		var tx := rng.randf_range(273.0, 298.0)
		var tyaw := rng.randf() * TAU
		var tsc := rng.randf_range(0.9, 1.5)
		# keep the run-up and landing zone of the "Eastside Air" stunt ramp clear
		if not (absf(tx - 284.0) < 8.0 and z > -75.0 and z < 150.0):
			b.prop(te, Vector3(tx, 0.0, z), tyaw, tsc)
	for i in 46:
		b.prop("bush_a" if i % 2 == 0 else "tree_round", Vector3(rng.randf_range(-268.0, -100.0), 0.0, rng.randf_range(-186.5, -180.0)), rng.randf() * TAU, rng.randf_range(0.8, 1.2), i % 2 == 1)
	b.scatter("grass_clump", -298, -176, -272, 174, 120, 0.8, 1.6, false, 0.0)
	b.scatter("grass_clump", 272, -176, 298, 174, 120, 0.8, 1.6, false, 0.0)
	# distant tree belt on the surrounding hills (LOD meshes only, no collision)
	for i in 420:
		var a := rng.randf() * TAU
		var d := rng.randf_range(335.0, 640.0)
		var x := cos(a) * d
		var z2 := sin(a) * d
		if z2 > 150.0:
			continue
		b.prop("tree_pine_lod1" if i % 3 != 0 else "tree_round_lod1", Vector3(x, L.height(x, z2) - 0.5, z2), rng.randf() * TAU, rng.randf_range(1.3, 2.4), false)
	# stunt ramps around town
	b.prop("prop_stunt_ramp", Vector3(230.0, CH + 0.02, 235.0), PI)
	b.stunts.append({"pos": Vector3(230.0, 0.0, 236.0), "name": "Pier Pressure"})
	b.prop("prop_stunt_ramp", Vector3(284.0, 0.02, 60.0), 0.0)
	b.stunts.append({"pos": Vector3(284.0, 0.0, 60.0), "name": "Eastside Air"})
	b.pickups.append({"kind": "armor", "pos": Vector3(284.0, 0.6, 30.0)})
	b.pickups.append({"kind": "health", "pos": Vector3(-284.0, 0.6, -40.0)})
	b.pickups.append({"kind": "weapon", "pos": Vector3(-284.0, 0.6, 100.0), "weapon": "bat"})
	b.pickups.append({"kind": "weapon", "pos": Vector3(120.0, 0.6, 189.0), "weapon": "crowbar"})


func _rail() -> void:
	b.chunk("rail")
	var H := 7.6
	var rad := 22.0
	var X0 := -88.0
	var X1 := 88.0
	var Z0 := -85.0
	var Z1 := 85.0
	var pts := PackedVector3Array()
	var corners := [[X1 - rad, Z1 - rad, 0.0], [X0 + rad, Z1 - rad, PI * 0.5], [X0 + rad, Z0 + rad, PI], [X1 - rad, Z0 + rad, PI * 1.5]]
	# clockwise seen from above: east side going south -> south side going west -> west side north -> north side east
	var step := 2.0
	var z := Z0 + rad
	while z < Z1 - rad:
		pts.append(Vector3(X1, H, z))
		z += step
	for ci in 4:
		var c: Array = corners[ci]
		for k in 11:
			var a: float = c[2] + (k / 11.0) * PI * 0.5
			pts.append(Vector3(c[0] + cos(a) * rad, H, c[1] + sin(a) * rad))
		match ci:
			0:
				var x := X1 - rad
				while x > X0 + rad:
					pts.append(Vector3(x, H, Z1))
					x -= step
			1:
				var z2 := Z1 - rad
				while z2 > Z0 + rad:
					pts.append(Vector3(X0, H, z2))
					z2 -= step
			2:
				var x2 := X0 + rad
				while x2 < X1 - rad:
					pts.append(Vector3(x2, H, Z0))
					x2 += step
	var n := pts.size()
	for i in n:
		var p0 := pts[i]
		var p1 := pts[(i + 1) % n]
		var d := (p1 - p0).normalized()
		var r := Vector3(-d.z, 0, d.x)
		var up := Vector3.UP
		b.quad("concrete", p0 - r * 1.7, p0 + r * 1.7, p1 + r * 1.7, p1 - r * 1.7, up)
		b.quad("concrete", p0 - r * 1.7 - up * 0.55, p0 + r * 1.7 - up * 0.55, p1 + r * 1.7 - up * 0.55, p1 - r * 1.7 - up * 0.55, -up)
		for s in [-1.0, 1.0]:
			b.quad("concrete", p0 + r * 1.7 * s - up * 0.55, p1 + r * 1.7 * s - up * 0.55, p1 + r * 1.7 * s + up * 0.25, p0 + r * 1.7 * s + up * 0.25, r * s)
			b.quad("concrete", p0 + r * 1.45 * s, p1 + r * 1.45 * s, p1 + r * 1.45 * s + up * 0.25, p0 + r * 1.45 * s + up * 0.25, -r * s)
			b.quad("concrete", p0 + r * 1.45 * s + up * 0.25, p1 + r * 1.45 * s + up * 0.25, p1 + r * 1.7 * s + up * 0.25, p0 + r * 1.7 * s + up * 0.25, up)
			b.quad("metal", p0 + r * (0.75 * s - 0.05) + up * 0.14, p0 + r * (0.75 * s + 0.05) + up * 0.14, p1 + r * (0.75 * s + 0.05) + up * 0.14, p1 + r * (0.75 * s - 0.05) + up * 0.14, up)
		if i % 11 == 0:
			var mid := p0
			var hwr := 7.4
			if L.on_road(Vector3(mid.x + d.x * 6.0, 0, mid.z + d.z * 6.0)) and not _in_intersection(mid):
				for s2 in [-1.0, 1.0]:
					var lp: Vector3 = mid + r * hwr * s2
					b.box_mesh("concrete", Vector3(lp.x, (H - 0.55) * 0.5, lp.z), Vector3(0.9, H - 0.55, 0.9))
					b.add_box_collider(Vector3(lp.x, (H - 0.55) * 0.5, lp.z), Vector3(0.9, H - 0.55, 0.9))
				var beam_size := Vector3(absf(r.x) * hwr * 2.0 + 0.9, 0.7, absf(r.z) * hwr * 2.0 + 0.9)
				b.box_mesh("concrete", Vector3(mid.x, H - 0.9, mid.z), beam_size)
	for seg in [[Vector3(X1, H - 0.3, 0), Vector3(3.4, 0.6, Z1 - Z0 - rad * 2)], [Vector3(X0, H - 0.3, 0), Vector3(3.4, 0.6, Z1 - Z0 - rad * 2)],
			[Vector3(0, H - 0.3, Z1), Vector3(X1 - X0 - rad * 2, 0.6, 3.4)], [Vector3(0, H - 0.3, Z0), Vector3(X1 - X0 - rad * 2, 0.6, 3.4)]]:
		b.add_box_collider(seg[0], seg[1])
	# stations
	var sa := Vector3(-40.0, H, Z1)
	b.model("rail_station", sa, PI * 0.5)
	var sb := Vector3(X1, H, -40.0)
	b.model("rail_station", sb, PI)
	b.poi("station_a", "Lantern Park Station", Vector3(-63.6, CH, Z1 - 5.4), "train", {"platform": sa + Vector3(0, 0.9, -4.3)})
	b.poi("station_b", "Civic Square Station", Vector3(X1 - 5.4, CH, -16.4), "train", {"platform": sb + Vector3(-4.3, 0.9, 0)})
	b.spawns["rail"] = {"points": pts, "stations": [sa, sb], "height": H}


func _in_intersection(p: Vector3) -> bool:
	for i in L.NX:
		for j in L.NZ:
			if absf(p.x - L.VX[i]) < L.v_hw(i) + 6.0 and absf(p.z - L.HZ[j]) < L.h_hw(j) + 6.0:
				return true
	return false
