class_name CityBuilder
extends Node3D
## Populates the CityLayout with buildings, landmarks, props, vegetation, street furniture
## and gameplay metadata (locations, parking spots, vehicle spawns, pedestrian zones).
## District content lives in city_blocks.gd / city_special.gd; this file is the toolbox.

const C_DOWNTOWN := ["aab4bf", "8f9aa6", "c9c4b8", "6f7a86", "d9d2c2", "7d8794", "b7a894", "5c6570", "9fb0bd", "e3dfd4", "879aa8", "bfb39c"]
const C_DOWNTOWN_B := ["2e3035", "55585e", "3a5fa8", "22407f", "c9a24a", "8f2a25", "2aa59a", "e3dfd4"]
const C_MID := ["efe2c2", "dcc391", "f0b592", "ea8271", "58b5a8", "7fb2d9", "f1d273", "a9dcc0", "b9a4d6", "a2523f", "c2a078", "e3dfd4", "d98f6a", "8fb7a8"]
const C_MID_B := ["d43d33", "2f6fd0", "3fa55a", "ef7f2d", "2aa59a", "7a48c2", "f2c230", "22407f", "8f2a25", "17181b", "f08ab8"]
const C_IND := ["8f989c", "5e7d93", "9a4b3f", "7c786f", "6b7a3a", "aaa598", "55585e", "a9834f"]
const C_IND_B := ["f2c21c", "d43d33", "2f6fd0", "55585e", "ef7f2d"]
const C_HOUSE := ["f2f0ea", "cfe0ea", "d8e6c8", "f1e2b0", "efd0c0", "c9d6e6", "e6d9c4", "b7cfc4", "f0c9a8", "dfe3e6", "e8b8a0", "9fc3c9"]
const C_ROOF := ["b3543c", "4d5560", "33363c", "2f7f7a", "6e3a30", "7a5236"]
const C_HOTEL := ["f0b592", "58b5a8", "f1d273", "7fb2d9", "ea8271", "efe2c2"]

var world: World
var layout: CityLayout
var rng := RandomNumberGenerator.new()
var buildings_root: Node3D
var landmarks_root: Node3D
var props_root: Node3D
var scatter := Scatter.new()
var lot_buf := GeoBuf.new()
var road_buf := GeoBuf.new()

# gameplay metadata consumed by other systems
var footprints: Array = []        # {rect: Rect2, color: Color, h: float, name: String}  (minimap)
var locations: Dictionary = {}    # id -> {root: Node3D, markers: {name: Node3D}, pos: Vector3}
var parking_spots: Array = []     # {pos: Vector3, yaw: float, kind: String}
var vehicle_spawns: Array = []    # {id: String, pos: Vector3, yaw: float, tag: String}
var ped_areas: Array = []         # {rect: Rect2, y: float, name: String} free-roam zones for pedestrians
var pickup_spots: Array = []      # {kind: String, pos: Vector3}
var signal_lights: Array = []     # [MeshInstance3D list, node id, axis]
var stats := {"props": 0, "landmarks": 0, "missing": {}}

func build(w: World) -> void:
	world = w
	layout = w.layout
	rng.seed = 90210
	PropFactory.load_manifests()
	buildings_root = _group("Buildings")
	landmarks_root = _group("Landmarks")
	props_root = _group("Props")
	lot_buf.use_uv2 = false
	for b in layout.blocks:
		CityBlocks.generate(self, b)
	CitySpecial.generate(self)
	_street_furniture()
	lot_buf.instance(self, "LotSurfaces", world.mat_ground)
	road_buf.instance(self, "ExtraPavement", world.mat_road)
	scatter.commit(self, "Scatter")
	var sc := SignalController.new()
	sc.name = "Signals"
	add_child(sc)
	sc.setup(world.graph, signal_lights)
	if world.env:
		world.env.night_changed.connect(PropFactory.set_lamps)
		PropFactory.set_lamps(world.env.is_night)
	print("[City] buildings=%d detail_tris=%d lod_tris=%d props=%d landmarks=%d scatter=%d" % [
		BuildingFactory.stats["buildings"], BuildingFactory.stats["tris"], BuildingFactory.stats["lod_tris"],
		stats["props"], stats["landmarks"], scatter.count])
	if not (BuildingFactory.stats["missing"] as Dictionary).is_empty():
		print("[City] missing kit modules (procedural fallback used): ", (BuildingFactory.stats["missing"] as Dictionary).keys())
	if not (stats["missing"] as Dictionary).is_empty():
		print("[City] missing assets: ", (stats["missing"] as Dictionary).keys())

func _group(group_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = group_name
	add_child(n)
	return n

# ---------------------------------------------------------------- helpers
static func hexc(h: String) -> Color:
	return Color.html(h)

func pick(list: Array) -> Color:
	return hexc(list[rng.randi() % list.size()])

static func snap_up(v: float, m: float) -> float:
	return ceil(v / m - 0.0001) * m

static func snap_down(v: float, m: float) -> float:
	return floor(v / m + 0.0001) * m

## yaw so that an asset's front (Blender +Y = Godot -Z) points toward compass side N/E/S/W.
static func facing_yaw(side: String) -> float:
	match side:
		"N": return 0.0
		"E": return -PI * 0.5
		"S": return PI
	return PI * 0.5

static func yaw_to(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)

func ground_y(x: float, z: float) -> float:
	## Top surface height at (x,z): kerb slab in the city, terrain elsewhere.
	if Terrain.in_city(x, z):
		return CityLayout.CURB_H
	return Terrain.sample(x, z)

## Modular building. x,z = desired min corner (snapped to the module grid here).
func modular(kit: String, x: float, z: float, nx: int, nz: int, floors: int, door_side: String, street_sides: String,
		opts: Dictionary = {}) -> StaticBody3D:
	var mw: float = BuildingFactory.KITS[kit]["mw"]
	var spec := {
		"kit": kit, "x": snap_up(x, mw), "z": snap_up(z, mw), "nx": nx, "nz": nz, "floors": floors,
		"door_side": door_side, "street_sides": street_sides, "style": rng.randi() % 4, "seed": rng.randi(),
		"tint_a": Color.WHITE, "tint_b": Color.WHITE, "name": "%s_%d" % [kit, footprints.size()],
	}
	match kit:
		"office":
			spec["tint_a"] = pick(C_DOWNTOWN)
			spec["tint_b"] = pick(C_DOWNTOWN_B)
		"apt":
			spec["tint_a"] = pick(C_MID)
			spec["tint_b"] = pick(C_MID_B)
		"mixed":
			spec["tint_a"] = pick(C_MID)
			spec["tint_b"] = pick(C_MID_B)
		"ind":
			spec["tint_a"] = pick(C_IND)
			spec["tint_b"] = pick(C_IND_B)
	for k in opts.keys():
		spec[k] = opts[k]
	var body := BuildingFactory.build(buildings_root, spec)
	var size := Vector2(nx * mw, nz * mw)
	var kd: Dictionary = BuildingFactory.KITS[kit]
	footprints.append({"rect": Rect2(Vector2(spec["x"], spec["z"]), size), "color": spec["tint_a"],
		"h": float(kd["gh"]) + float(floors - 1) * float(kd["fh"]), "name": String(opts.get("label", ""))})
	return body

## Suburban house facing N, S, E or W. (cx, cz) = centre of the footprint.
func house(cx: float, cz: float, nx: int, nz: int, floors: int, facing: String, garage: bool) -> StaticBody3D:
	var w := nx * 3.0
	var d := nz * 3.0
	var spec := {"nx": nx, "nz": nz, "floors": floors, "garage": garage, "seed": rng.randi(),
		"tint_a": pick(C_HOUSE), "tint_b": pick(C_ROOF), "name": "house_%d" % footprints.size()}
	var yaw := 0.0
	var rect: Rect2
	match facing:
		"N":
			spec["door_side"] = "N"
			spec["x"] = snap_up(cx - w * 0.5, 3.0)
			spec["z"] = snap_up(cz - d * 0.5, 3.0)
			rect = Rect2(spec["x"], spec["z"], w, d)
		"S":
			spec["door_side"] = "S"
			spec["x"] = snap_up(cx - w * 0.5, 3.0)
			spec["z"] = snap_up(cz - d * 0.5, 3.0)
			rect = Rect2(spec["x"], spec["z"], w, d)
		"E":
			# local +Z (door side S) rotated by +90 deg faces +X; footprint becomes X:[0,d] Z:[-w,0]
			spec["door_side"] = "S"
			yaw = PI * 0.5
			spec["x"] = snap_up(cx - d * 0.5, 3.0)
			spec["z"] = snap_up(cz + w * 0.5, 3.0)
			rect = Rect2(spec["x"], float(spec["z"]) - w, d, w)
		_:
			# facing west: rotate by -90 deg: local +Z -> -X; footprint X:[-d,0] Z:[0,w]
			spec["door_side"] = "S"
			yaw = -PI * 0.5
			spec["x"] = snap_up(cx + d * 0.5, 3.0)
			spec["z"] = snap_up(cz - w * 0.5, 3.0)
			rect = Rect2(float(spec["x"]) - d, spec["z"], d, w)
	var body := BuildingFactory.build_house(buildings_root, spec)
	body.rotation.y = yaw
	footprints.append({"rect": rect, "color": spec["tint_a"], "h": 3.0 * floors + 2.0, "name": ""})
	return body

## Place a one-off landmark asset. `facing` = compass side its front points to (or pass yaw in opts).
func landmark(id: String, pos: Vector3, facing := "S", opts: Dictionary = {}) -> Node3D:
	var rel := "landmarks/" + id
	if not Assets.has_model(rel):
		stats["missing"][id] = true
		_landmark_stand_in(id, pos, float(opts.get("yaw", facing_yaw(facing))), facing, opts)
		return null
	var inst := Assets.instance(rel)
	inst.name = id if not locations.has(id) else "%s_%d" % [id, locations.size()]
	inst.position = pos
	inst.rotation.y = float(opts.get("yaw", facing_yaw(facing)))
	landmarks_root.add_child(inst)
	var col_part := PropFactory.part(inst, "col")
	if col_part is MeshInstance3D:
		var cmi := col_part as MeshInstance3D
		cmi.visible = false
		var faces := cmi.mesh.get_faces()
		if not faces.is_empty():
			var body := StaticBody3D.new()
			body.name = "Collision"
			body.collision_layer = Phys.WORLD
			body.collision_mask = 0
			body.set_meta("surface", &"concrete")
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(faces)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			cmi.get_parent().add_child(body)
			body.transform = cmi.transform
	for mi in Assets.find_meshes(inst):
		if opts.has("tint_a"):
			mi.set_instance_shader_parameter(&"tint_a", (opts["tint_a"] as Color).srgb_to_linear())
		if opts.has("tint_b"):
			mi.set_instance_shader_parameter(&"tint_b", (opts["tint_b"] as Color).srgb_to_linear())
	# interior / canopy lights at light_* markers
	for m in PropFactory.parts_with_prefix(inst, "light"):
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.9, 0.74)
		ol.light_energy = float(opts.get("light_energy", 1.6))
		ol.omni_range = float(opts.get("light_range", 8.0))
		ol.shadow_enabled = false
		ol.distance_fade_enabled = true
		ol.distance_fade_begin = 45.0
		ol.distance_fade_length = 15.0
		m.add_child(ol)
	var markers := {}
	_collect_markers(inst, markers)
	var key := id
	var n := 2
	while locations.has(key):
		key = "%s_%d" % [id, n]
		n += 1
	locations[key] = {"id": id, "root": inst, "markers": markers, "pos": pos}
	stats["landmarks"] += 1
	var box := PropFactory.visual_aabb(inst)
	var gb := inst.transform * box
	footprints.append({"rect": Rect2(gb.position.x, gb.position.z, gb.size.x, gb.size.z), "color": Color(0.85, 0.8, 0.7),
		"h": box.size.y, "name": String(opts.get("label", ""))})
	return inst

## Footprints (width along the front, depth) of landmarks that gameplay depends on. While the
## Blender model is missing a procedural building stands in and the gameplay markers are
## synthesised at the front door, so shops / safehouse work with or without the asset.
const STAND_IN := {
	"shop_guns": Vector2(12, 10), "shop_clothes": Vector2(12, 10), "shop_barber": Vector2(8, 8),
	"shop_market": Vector2(12, 10), "safehouse": Vector2(12, 9),
}

func _landmark_stand_in(id: String, pos: Vector3, yaw: float, facing: String, opts: Dictionary) -> void:
	if not STAND_IN.has(id) or locations.has(id):
		return
	var sz: Vector2 = STAND_IN[id]
	var basis := Basis(Vector3.UP, yaw)
	var front := basis * Vector3(0, 0, -1)
	var half_d := sz.y * 0.5
	if id == "safehouse":
		house(pos.x, pos.z, 4, 3, 1, facing, true)
	else:
		# storefront building: one storey of the mixed kit with the door side toward the street
		var mw: float = BuildingFactory.KITS["mixed"]["mw"]
		var nx := int(ceil(sz.x / mw))
		var nz := int(ceil(sz.y / mw))
		var w := float(nx) * mw
		var d := float(nz) * mw
		if facing == "E" or facing == "W":
			var t := w
			w = d
			d = t
			var tn := nx
			nx = nz
			nz = tn
		modular("mixed", pos.x - w * 0.5, pos.z - d * 0.5, nx, nz, 2, facing, facing, {"label": String(opts.get("label", id))})
		half_d = (d if (facing == "N" or facing == "S") else w) * 0.5
	var holder := Node3D.new()
	holder.name = "StandIn_" + id
	landmarks_root.add_child(holder)
	holder.global_transform = Transform3D(basis, pos)
	var markers := {}
	var door := Vector3(0, 0, -(half_d + 1.6))
	var spots := {"entrance": door, "counter": door, "staff": door + Vector3(0, 0, 0.8), "spawn": door,
		"workbench": door, "wardrobe": door, "chair": door, "register": door, "save": door, "bed": door}
	if id == "safehouse":
		spots["garage_out"] = Vector3(-9.0, 0, -(half_d + 7.0))
		spots["garage_spot"] = Vector3(-9.0, 0, -(half_d + 2.5))
	for k in spots.keys():
		var m := Node3D.new()
		m.name = "%s__%s" % [id, k]
		holder.add_child(m)
		m.position = spots[k]
		if k == "staff":
			m.rotation.y = PI
	locations[id] = {"id": id, "root": null, "markers": markers, "pos": pos, "stand_in": true}
	for c in holder.get_children():
		markers[String(c.name).get_slice("__", 1)] = c
	print("[City] stand-in for missing landmark ", id)

func _collect_markers(n: Node, out: Dictionary) -> void:
	if n is Node3D and not (n is MeshInstance3D):
		var nm := String(n.name)
		var i := nm.rfind("__")
		if i >= 0:
			out[nm.substr(i + 2)] = n
	for c in n.get_children():
		_collect_markers(c, out)

## World transform of a landmark marker (or null).
func marker(location_id: String, marker_name: String) -> Variant:
	if not locations.has(location_id):
		return null
	var m: Dictionary = locations[location_id]["markers"]
	if not m.has(marker_name):
		return null
	return (m[marker_name] as Node3D).global_transform

func prop(id: String, pos: Vector3, yaw := 0.0, opts: Dictionary = {}) -> Node3D:
	var p := PropFactory.spawn(props_root, id, pos, yaw, opts)
	if p == null:
		stats["missing"][id] = true
	else:
		stats["props"] += 1
	return p

## Static decorative instance batched through MultiMesh (trees, rocks, bushes, clutter).
func deco(id: String, pos: Vector3, yaw := 0.0, scale := 1.0, collide := true, vis_range := 0.0) -> void:
	if not scatter.add_prop(id, pos, yaw, scale, collide, vis_range):
		stats["missing"][id] = true

## Coloured ground overlay just above the block slab (parking asphalt, paths, plazas...).
func lot(x0: float, z0: float, x1: float, z1: float, color_name: String, pattern := 0.0, lift := 0.012) -> void:
	lot_buf.rect_up(minf(x0, x1), minf(z0, z1), maxf(x0, x1), maxf(z0, z1), CityLayout.CURB_H + lift, GeoBuf.pal(color_name), pattern)

func line(x0: float, z0: float, x1: float, z1: float, width := 0.12, color_name := "line_white") -> void:
	## thin painted line on a lot (parking stalls, helipad markings)
	var a := Vector2(x0, z0)
	var b := Vector2(x1, z1)
	var dirv := (b - a).normalized()
	var n := Vector2(-dirv.y, dirv.x) * width * 0.5
	var y := CityLayout.CURB_H + 0.03
	lot_buf.quad(Vector3(a.x - n.x, y, a.y - n.y), Vector3(a.x + n.x, y, a.y + n.y), Vector3(b.x + n.x, y, b.y + n.y),
		Vector3(b.x - n.x, y, b.y - n.y), Vector3.UP, GeoBuf.pal(color_name), 0.0)

func driveway(pos: Vector3, into: Vector3, width := 6.0) -> void:
	GroundBuilder.add_driveway(self, world.ground_body, lot_buf, pos, into.normalized(), width)

## Asphalt parking lot with stalls along X (rows stacked on Z). Registers parking spots.
func parking_lot(x0: float, z0: float, x1: float, z1: float, kind := "civil", fill := 0.6) -> void:
	lot(x0, z0, x1, z1, "asphalt", 6.0)
	var stall_w := 2.9
	var stall_d := 5.4
	var depth := z1 - z0
	var rows: Array = []
	if depth >= stall_d * 2.0 + 6.5:
		rows = [[z0, 1.0], [z1, -1.0]]
	else:
		rows = [[z0, 1.0]]
	for row in rows:
		var zr: float = row[0]
		var sgn: float = row[1]
		var n := int((x1 - x0 - 1.0) / stall_w)
		var start := x0 + (x1 - x0 - float(n) * stall_w) * 0.5
		for i in range(n + 1):
			var lx := start + float(i) * stall_w
			line(lx, zr + sgn * 0.3, lx, zr + sgn * stall_d)
		for i in n:
			if rng.randf() > fill:
				continue
			var cx := start + (float(i) + 0.5) * stall_w
			var cz := zr + sgn * (stall_d * 0.5 + 0.3)
			parking_spots.append({"pos": Vector3(cx, CityLayout.CURB_H, cz), "yaw": 0.0 if sgn < 0.0 else PI, "kind": kind})

func spawn_vehicle(id: String, pos: Vector3, yaw: float, tag := "") -> void:
	vehicle_spawns.append({"id": id, "pos": pos, "yaw": yaw, "tag": tag})

func fence_run(id: String, a: Vector2, b: Vector2, y: float, seg := 2.0, skip_from := -1.0, skip_to := -1.0) -> void:
	## fence / wall modules between two points (modules run along local X)
	var total := a.distance_to(b)
	var n := int(round(total / seg))
	if n < 1:
		return
	var dirv := (b - a) / total
	var yaw := atan2(-dirv.y, dirv.x)
	for i in n:
		var t := (float(i) + 0.5) * seg
		if skip_from >= 0.0 and t > skip_from and t < skip_to:
			continue
		var p := a + dirv * t
		prop(id, Vector3(p.x, y, p.y), yaw)

# ---------------------------------------------------------------- street furniture
func _street_furniture() -> void:
	var lamp_ok := PropFactory.exists("street_lamp")
	for road in layout.roads:
		var kind: String = road["kind"]
		if kind == "hill":
			_hill_road_furniture(road)
			continue
		var pts: PackedVector3Array = road["pts"]
		var a := pts[0]
		var b := pts[pts.size() - 1]
		var length := a.distance_to(b)
		var d := (b - a) / length
		var r := Vector3(-d.z, 0.0, d.x)
		var hw: float = road["hw"]
		var y := CityLayout.CURB_H
		var idx: int = road["id"]
		# lamps: staggered left/right
		var spacing := 30.0 if kind == "street" else 34.0
		var s := 9.0
		var side := 1.0 if idx % 2 == 0 else -1.0
		while s < length - 8.0:
			var p := a + d * s + r * side * (hw + 0.75)
			if lamp_ok:
				prop("street_lamp", Vector3(p.x, y, p.z), yaw_to(-r * side))
			side = -side
			s += spacing * 0.5
		# one hydrant, bins, the odd bench / newsbox depending on the road index
		var ph := a + d * (length * 0.3) + r * (hw + 1.0)
		prop("prop_hydrant", Vector3(ph.x, y, ph.z), yaw_to(-r))
		var pb := a + d * (length * 0.62) - r * (hw + 1.1)
		prop("prop_bin", Vector3(pb.x, y, pb.z), yaw_to(r))
		if idx % 3 == 0:
			var pbe := a + d * (length * 0.45) + r * (hw + 2.6)
			prop("prop_bench", Vector3(pbe.x, y, pbe.z), yaw_to(-r))
		if idx % 4 == 1:
			var pn := a + d * 7.5 - r * (hw + 1.2)
			prop("prop_newsbox", Vector3(pn.x, y, pn.z), yaw_to(r), {"tint_a": pick(C_MID_B)})
		if idx % 5 == 2:
			var pm := a + d * (length - 7.5) + r * (hw + 1.2)
			prop("prop_mailbox", Vector3(pm.x, y, pm.z), yaw_to(-r))
		# kerb-side parking spots (both sides, with gaps)
		if kind == "street":
			for sgn: float in [1.0, -1.0]:
				var t := 16.0
				while t < length - 16.0:
					if rng.randf() < 0.42:
						var pp := a + d * t + r * sgn * (hw - 1.15)
						parking_spots.append({"pos": Vector3(pp.x, 0.0, pp.z), "yaw": yaw_to(d * sgn), "kind": "street"})
					t += 6.6
	# traffic lights
	var tl_ok := PropFactory.exists("traffic_light")
	for id in layout.nodes.keys():
		var nd: Dictionary = layout.nodes[id]
		if not nd["signal"]:
			continue
		for arm: String in ["N", "S", "E", "W"]:
			if int(nd["arms"][arm]) < 0:
				continue
			# traffic arriving from this arm travels toward the junction centre
			var d: Vector3
			var half: float
			match arm:
				"N": d = Vector3(0, 0, 1); half = nd["hz"]
				"S": d = Vector3(0, 0, -1); half = nd["hz"]
				"E": d = Vector3(-1, 0, 0); half = nd["hx"]
				_: d = Vector3(1, 0, 0); half = nd["hx"]
			var r := Vector3(-d.z, 0.0, d.x)
			var road: Dictionary = layout.roads[int(nd["arms"][arm])]
			var hw := float(road["hw"]) if road["kind"] != "hill" else CityLayout.STREET_HW
			var p: Vector3 = nd["pos"] - d * (half + 5.3) + r * (hw + 0.7)
			if not tl_ok:
				continue
			var tl := prop("traffic_light", Vector3(p.x, CityLayout.CURB_H if road["kind"] != "hill" else 0.0, p.z), atan2(d.x, d.z), {"static": true})
			if tl != null:
				signal_lights.append([Assets.find_meshes(tl), id, 0 if absf(d.z) > 0.5 else 1])

func _hill_road_furniture(road: Dictionary) -> void:
	var pts: PackedVector3Array = road["pts"]
	var i := 12
	var side := 1.0
	while i < pts.size() - 12:
		var d := (pts[i + 1] - pts[i - 1])
		d.y = 0.0
		d = d.normalized()
		var r := Vector3(-d.z, 0.0, d.x)
		var p := pts[i] + r * side * (CityLayout.HILL_HW + 1.6)
		prop("street_lamp", Vector3(p.x, Terrain.sample(p.x, p.z), p.z), yaw_to(-r * side))
		side = -side
		i += 19
