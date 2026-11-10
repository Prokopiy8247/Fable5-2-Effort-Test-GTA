class_name CityBuilder
extends Node3D
## "city" world system (BootManifest): fills every lot of Game.world with the Blender-authored
## buildings of gta/generated/models/buildings, adds their collision, night materials, occluders,
## landmark markers, ladders, automatic landmark doors and the GLB visitor pier of the marina.
## Contract: docs/ARCHITECTURE_WAVE2.md W2.4. Details: docs/CITY.md.
##
##     var city := Game.get_system("city")
##     if city != null and city.has_landmark("gun_shop"):
##         var counter: Transform3D = city.get_landmark_marker("gun_shop", "Use_Counter")
##
## Soft dependencies only: the world (lots, heights, navigation) through Game.world, the night-light
## materials through Game.get_system("environment"), Audio through /root/Audio.

signal city_built

const Planner := preload("res://gta/code/world/city/city_planner.gd")
const Proto := preload("res://gta/code/world/city/city_proto.gd")

const NO_HOOK_GROUP := &"env_no_night_hook"     ## environment: "materials already handled"
const BUILDING_GROUP := &"city_building"
const LADDER_GROUP := &"ladder"
const DOOR_RADIUS := 2.5                         ## a character this close opens a landmark door
const DOOR_SPEED := 3.2                          ## 1 / seconds for a full swing
const DOOR_SCAN_INTERVAL := 0.1
const DOOR_ACTIVE_RANGE := 60.0                  ## NPCs are only looked at when the player is this close to a door
const DOOR_SWING_DEG := 100.0
const PLINTH_DROP := 0.6                         ## ground lower than this under the footprint -> plinth
const PLINTH_COLOR := Color(0.64, 0.62, 0.58)
## Visitor pier made of the GLB marina kit (pier_ramp + pier_straight x2 + pier_end), placed where
## WORLD has no procedural pier (docs/INTEGRATION_WAVE1.md: never stack them on the procedural ones).
const PIER_PIECES: Array[String] = ["pier_ramp", "pier_straight", "pier_end"]
const PIER_X_CANDIDATES: Array[float] = [-45.0, -120.0, -180.0, -240.0]
const PIER_FALLBACK := {"QUAY_Z": 252.0, "PIER_DECK_Y": 1.15, "PIER_X": [-210.0, -150.0, -90.0], "PIER_RAMP_Z": 260.0}
const LANDMARK_ALIASES := {"hill_top": "radio_mast", "tram_stop": "tram_stop_1"}
## One pooled warm room light (no shadows) for the walk-in landmark nearest to the camera, so shop
## interiors do not look like the cool sky ambient only. 1 positional light of the shared budget.
const ROOM_LIGHT_REACH := 24.0
const ROOM_LIGHT_COLOR := Color(1.0, 0.86, 0.68)
const ROOM_LIGHT_ENERGY := 1.4
## Lots of these kinds stay open for pedestrians in the navigation mesh.
const NAV_OPEN_IDS: Array[String] = ["gas_station", "parking_a", "tram_stop", "pier_ramp", "pier_straight", "pier_end"]
## Ladder lines measured on the GLB rails (building-local; reviewer, 2026-11-10). The Ladder_Bottom marker is
## where a climber STANDS, but the player module (PlayerStateLadder) puts the body STAND_OFF = 0.36 m behind
## the node origin and climbs straight up, so the node must sit on the rail line:
##   radio_mast  rails at z -1.36 (foot) .. -0.66 (platform, y 26): the caged ladder leans 0.7 m with the
##               tapering mast. "node" is the vertical best fit (body inside the cage at the foot, clear of
##               the 2.8 m platform slab at the top, top exit 0.55 m in = on the platform);
##               metas line_bottom / line_top give the real leaning line to a player module that can lean.
##   pier_end    swim ladder rails at z 3.0 .. 3.17 (deck end 3.0): node on z 3.12, so the body hangs in the
##               water at 3.48 and the top exit (3.12 - 0.55) lands ON the deck instead of past its edge.
## Building types set slightly into the ground (metres). The tram-stop platform has a sharp 0.30 m edge
## above its (sidewalk-level) lot: the real player could not step onto it from the front (city_play:
## Player._try_step_up lifts the capsule only onto the edge, then it slides back; a 0.12 m edge falls in
## the gap between its step-up (contact normal y < 0.55) and the floor angle (46 deg, normal y > 0.695);
## the world's own kerbs are 0.15 m with a sloped run for that reason). At 0.08 m the capsule simply rolls
## over the edge. The concrete body reaches 0.4 m below the origin; the end ramps start ~0.9 m later.
const SINK := {"tram_stop": 0.22}
const LADDER_FIT := {
	"radio_mast": {"node": Vector3(0.0, 0.15, -1.15), "line_bottom": Vector3(0.0, 0.15, -1.36), "line_top": Vector3(0.0, 26.0, -0.66)},
	"pier_end": {"node": Vector3(0.0, -1.2, 3.12), "line_bottom": Vector3(0.0, -1.2, 3.12), "line_top": Vector3(0.0, 0.0, 3.12)},
}

var catalog: BuildingCatalog
var stats: Dictionary = {}
var built := false
var enabled := true

var _protos: Dictionary = {}                 ## def id -> Proto
var _buildings: Array[Dictionary] = []
var _landmarks: Dictionary = {}              ## landmark name -> building record
var _doors: Array[Dictionary] = []
var _ladders: Array[Node3D] = []
var _root: Node3D
var _door_timer := 0.0
var _plinth_mat: StandardMaterial3D
var _nodes := 0
var _tris := 0
var _planner: RefCounted
var _rooms: Array[Dictionary] = []           ## {pos: Vector3 world, range, landmark}
var _room_light: OmniLight3D
var _room_idx := -1
var _room_fade := 0.0
var _room_timer := 0.0


# ---------------------------------------------------------------------------------------------
# boot
# ---------------------------------------------------------------------------------------------

func setup() -> void:
	if built:
		return
	var t0 := Time.get_ticks_usec()
	var world: Node = Game.world
	if world == null or not is_instance_valid(world) or not world.has_method("get_lots"):
		push_warning("[City] no world system: nothing to build")
		return
	catalog = BuildingCatalog.new()
	catalog.load_all()
	for e in catalog.errors:
		push_warning("[City] catalogue: " + e)
	var lots: Array = world.call("get_lots")
	var planner := Planner.new()
	planner.plan(lots, catalog)
	_planner = planner
	for n in planner.notes:
		print("[City] note: ", n)
	var placements: Array[Dictionary] = planner.placements.duplicate()
	placements.append_array(_plan_pier(world))
	var t1 := Time.get_ticks_usec()

	var need: Array[String] = []
	for pl in placements:
		if not need.has(String(pl["def_id"])):
			need.append(String(pl["def_id"]))
	_load_protos(need)
	var t2 := Time.get_ticks_usec()

	_root = Node3D.new()
	_root.name = "Buildings"
	for pl in placements:
		_place(pl, world)
	add_child(_root)
	var t3 := Time.get_ticks_usec()

	_after_build(world)
	if not _rooms.is_empty():
		_room_light = OmniLight3D.new()
		_room_light.name = "RoomLight"
		_room_light.light_color = ROOM_LIGHT_COLOR
		_room_light.light_energy = 0.0
		_room_light.shadow_enabled = false
		_room_light.omni_attenuation = 0.8
		_room_light.visible = false
		add_child(_room_light)
	built = true
	set_process(not _doors.is_empty() or not _rooms.is_empty())
	var t4 := Time.get_ticks_usec()

	var roles := {}
	for b in _buildings:
		roles[b["role"]] = int(roles.get(b["role"], 0)) + 1
	var empty: Array = []
	for e: Dictionary in planner.empty_lots:
		empty.append(e)
	stats = {
		"setup_ms": (t4 - t0) / 1000.0, "plan_ms": (t1 - t0) / 1000.0, "load_ms": (t2 - t1) / 1000.0,
		"place_ms": (t3 - t2) / 1000.0, "post_ms": (t4 - t3) / 1000.0, "buildings": _buildings.size(),
		"roles": roles, "types": _protos.size(), "catalogue": catalog.defs.size(), "landmarks": _landmarks.size(),
		"nodes": _nodes, "doors": _doors.size(), "ladders": _ladders.size(), "rooms": _rooms.size(), "tris": _tris, "merged_units": planner.merged_units,
		"empty_lots": empty, "usage": planner.usage.duplicate(), "swapped_surfaces": _swapped_total(),
		"interior_glass_tris": _glass_split_total(),
		"manifests": catalog.manifests,
	}
	print("[City] built %d buildings (%s) from %d of %d catalogue types in %.0f ms (plan %.0f, load %.0f, place %.0f, post %.0f) | %d landmarks, %d nodes, %d tris, %d doors, %d ladders, %d room lights, %d merged units, %d empty lots" % [
			_buildings.size(), str(roles), _protos.size(), catalog.defs.size(), stats["setup_ms"], stats["plan_ms"],
			stats["load_ms"], stats["place_ms"], stats["post_ms"], _landmarks.size(), _nodes, _tris, _doors.size(),
			_ladders.size(), _rooms.size(), planner.merged_units, empty.size()])
	city_built.emit()


func _swapped_total() -> int:
	var n := 0
	for id: String in _protos:
		n += int((_protos[id] as Proto).swapped)
	return n


func _glass_split_total() -> int:
	var n := 0
	for id: String in _protos:
		n += int((_protos[id] as Proto).glass_split)
	return n


## Loads every needed GLB once and builds one prototype per building type.
## (Synchronous on purpose: threaded loading of the imported scenes raced on material RIDs in the
## renderer - "Initializing already initialized RID" - and the whole load costs only ~0.1 s.)
func _load_protos(ids: Array[String]) -> void:
	var env: Node = Game.get_system("environment")
	var glass := Proto.make_interior_glass_material()
	for id in ids:
		var d := catalog.get_def(id)
		var packed := load(String(d["path"])) as PackedScene
		var pr := Proto.new()
		pr.glass_material = glass
		if pr.build(d, packed, env):
			_protos[id] = pr
		else:
			push_warning("[City] %s: %s" % [id, pr.error])


# ---------------------------------------------------------------------------------------------
# placement
# ---------------------------------------------------------------------------------------------

func _place(pl: Dictionary, world: Node) -> void:
	var id := String(pl["def_id"])
	var pr: Proto = _protos.get(id)
	if pr == null:
		return
	var xf: Transform3D = pl["xform"]
	var d: Dictionary = pr.def
	var fp: Vector2 = d["fp"]
	var co: Vector2 = d["co"]
	# ground fit: never sunken, a plinth where the ground falls away (hill side)
	var lo := INF
	var hi := -INF
	if String(pl["role"]) != "pier":
		for q: Vector2 in [Vector2(0, 0), Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5),
				Vector2(0, -0.5), Vector2(0, 0.5), Vector2(-0.5, 0), Vector2(0.5, 0)]:
			var p := xf * Vector3(co.x + q.x * fp.x * 0.96, 0.0, co.y + q.y * fp.y * 0.96)
			var h := float(world.call("get_height", p.x, p.z))
			lo = minf(lo, h)
			hi = maxf(hi, h)
		if hi > xf.origin.y + 0.2:
			xf.origin.y = hi
		xf.origin.y -= float(SINK.get(id, 0.0))
	var idx := _buildings.size()
	_tris += pr.tris
	var node := _instance(pr, xf, "%s_%03d" % [id, idx])
	var plinth := false
	if String(pl["role"]) != "pier" and lo < xf.origin.y - PLINTH_DROP:
		_add_plinth(node, pr, xf.origin.y - lo + 0.4)
		plinth = true
	_root.add_child(node)
	var rect := _footprint_rect(xf, fp, co)
	var rec := {"id": id, "lot_id": int(pl.get("lot_id", -1)), "category": String(d["category"]), "transform": xf,
			"footprint": fp, "height": float(d["h"]), "landmark": String(pl.get("landmark", "")),
			"role": String(pl["role"]), "lot_ids": pl.get("lot_ids", []), "node": node, "rect": rect,
			"zone": String(pl.get("zone", "")), "district": String(pl.get("district", "")),
			"collision": String(d["collision"]), "walk_in": pr.walk_in, "plinth": plinth, "markers": pr.markers}
	_buildings.append(rec)
	var lm := String(rec["landmark"])
	if lm != "":
		_landmarks[lm] = rec
		if not pr.interior_light.is_empty():
			_rooms.append({"pos": xf * (pr.interior_light["pos"] as Vector3), "range": float(pr.interior_light["range"]), "landmark": lm})
	if pr.markers.has("Ladder_Bottom") and pr.markers.has("Ladder_Top"):
		_add_ladder(node, pr, xf)


func _instance(pr: Proto, xf: Transform3D, node_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.transform = xf
	root.add_to_group(BUILDING_GROUP)
	_nodes += 1
	for p: Dictionary in pr.parts:
		var kind := String(p["kind"])
		if kind == "helper":
			continue
		var mi := MeshInstance3D.new()
		mi.name = String(p["name"])
		mi.mesh = p["mesh"]
		mi.transform = p["xform"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(pr.shadows.get(kind, false)) \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ve := float(pr.vis_end.get(kind, 0.0))
		if ve > 0.0:
			mi.visibility_range_end = ve
			mi.visibility_range_end_margin = ve * 0.08
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mi.add_to_group(NO_HOOK_GROUP)
		root.add_child(mi)
		_nodes += 1
		if kind == "door":
			_register_door(mi, p, xf)
	if not pr.shapes.is_empty():
		var body := StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.set_meta("surface", pr.surface)
		body.set_meta("building_id", pr.id)
		for pair: Array in pr.shapes:
			var cs := CollisionShape3D.new()
			cs.shape = pair[0]
			cs.transform = pair[1]
			body.add_child(cs)
			_nodes += 1
		root.add_child(body)
		_nodes += 1
	for o: Array in pr.object_shapes:
		var ob := StaticBody3D.new()
		ob.name = String(o[0]) + "_Body"
		ob.collision_layer = Layers.WORLD
		ob.collision_mask = 0
		ob.set_meta("surface", "metal")
		ob.set_meta("explosive_object", String(o[0]))
		var cs := CollisionShape3D.new()
		cs.shape = o[1]
		cs.transform = o[2]
		ob.add_child(cs)
		root.add_child(ob)
		_nodes += 2
	for o: Array in pr.occluders:
		var oi := OccluderInstance3D.new()
		oi.name = "Occluder"
		oi.occluder = o[0]
		oi.transform = o[1]
		root.add_child(oi)
		_nodes += 1
	return root


## World-space rectangle (x / z) of the solid footprint.
static func _footprint_rect(xf: Transform3D, fp: Vector2, co: Vector2) -> Rect2:
	var r := Rect2()
	var first := true
	for q: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		var p := xf * Vector3(co.x + q.x * fp.x, 0.0, co.y + q.y * fp.y)
		if first:
			r = Rect2(Vector2(p.x, p.z), Vector2.ZERO)
			first = false
		else:
			r = r.expand(Vector2(p.x, p.z))
	return r


## Concrete plinth under a building whose ground falls away (flat-shaded box, shared material).
func _add_plinth(node: Node3D, pr: Proto, depth: float) -> void:
	var fp: Vector2 = pr.def["fp"]
	var co: Vector2 = pr.def["co"]
	var hx := fp.x * 0.5 + 0.35
	var hz := fp.y * 0.5 + 0.35
	var y0 := -depth
	var y1 := 0.03
	if _plinth_mat == null:
		_plinth_mat = StandardMaterial3D.new()
		_plinth_mat.albedo_color = PLINTH_COLOR
		_plinth_mat.roughness = 0.95
		_plinth_mat.resource_name = "City_Plinth"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(co.x, 0.0, co.y)
	var v := [Vector3(-hx, y0, -hz), Vector3(hx, y0, -hz), Vector3(hx, y0, hz), Vector3(-hx, y0, hz),
			Vector3(-hx, y1, -hz), Vector3(hx, y1, -hz), Vector3(hx, y1, hz), Vector3(-hx, y1, hz)]
	var quads := [[4, 5, 6, 7, Vector3.UP], [0, 1, 5, 4, Vector3.FORWARD], [1, 2, 6, 5, Vector3.RIGHT],
			[2, 3, 7, 6, Vector3.BACK], [3, 0, 4, 7, Vector3.LEFT]]
	for q: Array in quads:
		st.set_normal(q[4])
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(c + (v[int(q[k])] as Vector3))
	var mesh := st.commit()
	mesh.surface_set_material(0, _plinth_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Plinth"
	mi.mesh = mesh
	node.add_child(mi)
	var body := node.get_node_or_null("Body") as StaticBody3D
	if body != null:
		var sh := BoxShape3D.new()
		sh.size = Vector3(hx * 2.0, depth, hz * 2.0)
		var cs := CollisionShape3D.new()
		cs.shape = sh
		cs.position = c + Vector3(0.0, (y0 + y1) * 0.5, 0.0)
		body.add_child(cs)
	_nodes += 2


## Ladder node (ARCHITECTURE_WAVE2 W2.4): group "ladder", origin at the foot of the rail line (see
## LADDER_FIT), climber facing -Z (the Ladder_Bottom marker yaw), meta "height" (top marker y - foot y).
## Extra metas: "top" (world position of the Ladder_Top marker = where a climber steps off), "building",
## "line_bottom" / "line_top" (world points of the real, possibly leaning, rail line).
func _add_ladder(node: Node3D, pr: Proto, xf: Transform3D) -> void:
	var bot: Transform3D = pr.markers["Ladder_Bottom"]
	var top: Transform3D = pr.markers["Ladder_Top"]
	var fit: Dictionary = LADDER_FIT.get(pr.id, {})
	var foot: Vector3 = fit.get("node", bot.origin)
	var lad := Node3D.new()
	lad.name = "Ladder"
	lad.transform = Transform3D(bot.basis, foot)
	lad.add_to_group(LADDER_GROUP)
	lad.set_meta("height", maxf(top.origin.y - foot.y, 0.1))
	lad.set_meta("top", xf * top.origin)
	lad.set_meta("building", pr.id)
	lad.set_meta("line_bottom", xf * (fit.get("line_bottom", foot) as Vector3))
	lad.set_meta("line_top", xf * (fit.get("line_top", Vector3(foot.x, top.origin.y, foot.z)) as Vector3))
	node.add_child(lad)
	_ladders.append(lad)
	_nodes += 1


# ---------------------------------------------------------------------------------------------
# GLB visitor pier (marina kit)
# ---------------------------------------------------------------------------------------------

func _layout_consts() -> Dictionary:
	var out := PIER_FALLBACK.duplicate()
	var path := "res://gta/code/world/world_layout.gd"
	if ResourceLoader.exists(path):
		var sc := load(path) as Script
		if sc != null:
			var cm := sc.get_script_constant_map()
			for k: String in out:
				if cm.has(k):
					out[k] = cm[k]
	return out


func _plan_pier(world: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in PIER_PIECES:
		if not catalog.has_def(id):
			return out
	var k := _layout_consts()
	var qz := float(k["QUAY_Z"])
	var deck := float(k["PIER_DECK_Y"])
	var existing: Array = k["PIER_X"]
	var ramp_len: float = (catalog.get_def("pier_ramp")["fp"] as Vector2).y
	var str_len: float = (catalog.get_def("pier_straight")["fp"] as Vector2).y
	var end_len: float = (catalog.get_def("pier_end")["fp"] as Vector2).y
	var z_ramp := qz + ramp_len * 0.5
	var z_s1 := qz + ramp_len + str_len * 0.5
	var z_s2 := z_s1 + str_len
	var z_end := z_s2 + str_len * 0.5 + end_len * 0.5
	for x: float in PIER_X_CANDIDATES:
		var clear := true
		for px: Variant in existing:
			if absf(float(px) - x) < 14.0:
				clear = false
		if not clear:
			continue
		# the ramp must start on the quay deck and the rest must stand in water
		var quay_h := float(world.call("get_height", x, qz - 1.5))
		if absf(quay_h - (deck + 1.37)) > 0.35:
			continue
		var wet := true
		for z: float in [qz + ramp_len + 1.0, z_s1, z_s2, z_end, z_end + end_len * 0.5]:
			for dx: float in [-3.0, 0.0, 3.0]:
				if float(world.call("get_water_depth", x + dx, z)) < 1.2:
					wet = false
		if not wet:
			continue
		var b := Basis.IDENTITY
		var pieces := [["pier_ramp", z_ramp], ["pier_straight", z_s1], ["pier_straight", z_s2], ["pier_end", z_end]]
		for pc: Array in pieces:
			out.append({"def_id": String(pc[0]), "role": "pier", "lot_id": -1, "lot_ids": [], "zone": "pier",
					"district": "waterfront", "landmark": "marina_pier" if String(pc[0]) == "pier_end" else "",
					"xform": Transform3D(b, Vector3(x, deck, float(pc[1])))})
		print("[City] visitor pier at x = %.0f, z %.0f..%.0f (deck y %.2f)" % [x, qz, z_end + end_len * 0.5, deck])
		return out
	push_warning("[City] no free deep-water spot for the GLB visitor pier")
	return out


# ---------------------------------------------------------------------------------------------
# after placement: navigation, roof helipad, extra spawn points
# ---------------------------------------------------------------------------------------------

func _after_build(world: Node) -> void:
	# real footprints instead of whole lots for the pedestrian navigation mesh
	if not Game.flags.has("city_keep_nav") and world.has_method("rebuild_navigation"):
		var rects: Array = []
		for b in _buildings:
			if NAV_OPEN_IDS.has(String(b["id"])):
				continue
			var r: Rect2 = b["rect"]
			rects.append([r.position.x, r.position.y, r.end.x, r.end.y])
		world.call("rebuild_navigation", rects, false)
	# the hospital roof pad is the real rooftop helipad
	if has_landmark_marker("hospital", "Helipad") and world.has_method("set_location"):
		var hp := get_landmark_marker("hospital", "Helipad")
		world.call("set_location", "rooftop_helipad", hp)
		if world.has_method("add_spawn_point"):
			world.call("add_spawn_point", "heli", hp)
	if has_landmark_marker("radio_mast", "Parachute_Spot") and world.has_method("add_spawn_point"):
		world.call("add_spawn_point", "parachute", get_landmark_marker("radio_mast", "Parachute_Spot"))


# ---------------------------------------------------------------------------------------------
# landmark doors: one manager loop, no script per door
# ---------------------------------------------------------------------------------------------

func _register_door(mi: MeshInstance3D, part: Dictionary, building_xf: Transform3D) -> void:
	var t: Transform3D = part["xform"]
	var yaw := t.basis.get_euler().y
	var sc := t.basis.get_scale()
	var closed := yaw
	var opened := yaw - deg_to_rad(DOOR_SWING_DEG)
	if absf(yaw) > 0.35:
		closed = 0.0                    # exported standing open (safehouse Door_1 at -100 deg)
		opened = yaw
	mi.basis = Basis(Vector3.UP, closed).scaled(sc)
	var ab: AABB = part["aabb"]
	var centre := building_xf * (Transform3D(Basis(Vector3.UP, closed), t.origin) * ab.get_center())
	_doors.append({"node": mi, "closed": closed, "open": opened, "scale": sc, "t": 0.0, "target": 0.0,
			"centre": centre})


func _process(delta: float) -> void:
	if _doors.is_empty() and _rooms.is_empty():
		set_process(false)
		return
	if _room_light != null:
		_update_room_light(delta)
	if _doors.is_empty():
		return
	_door_timer -= delta
	if _door_timer <= 0.0:
		_door_timer = DOOR_SCAN_INTERVAL
		_scan_doors()
	for d: Dictionary in _doors:
		var t := float(d["t"])
		var tgt := float(d["target"])
		if t == tgt:
			continue
		t = move_toward(t, tgt, delta * DOOR_SPEED)
		d["t"] = t
		var nv: Variant = d["node"]
		if nv == null or not is_instance_valid(nv):
			continue
		var mi := nv as MeshInstance3D
		if mi != null:
			var e := t * t * (3.0 - 2.0 * t)
			mi.basis = Basis(Vector3.UP, lerpf(float(d["closed"]), float(d["open"]), e)).scaled(d["scale"])


func _scan_doors() -> void:
	var chars: Array[Vector3] = []
	var focus := Vector3.INF
	if Game.has_player():
		var veh: Variant = Game.player.get("current_vehicle")
		focus = Game.player.global_position
		if veh == null or not is_instance_valid(veh):
			chars.append(focus)
	else:
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam != null:
			focus = cam.global_position
	var near_any := false
	for d: Dictionary in _doors:
		if (d["centre"] as Vector3).distance_squared_to(focus) < DOOR_ACTIVE_RANGE * DOOR_ACTIVE_RANGE:
			near_any = true
			break
	if near_any:
		for n: Node in get_tree().get_nodes_in_group("npc"):
			var n3 := n as Node3D
			if n3 == null or not n3.is_inside_tree() or n3.get("is_dead") == true:
				continue
			chars.append(n3.global_position)
	for d: Dictionary in _doors:
		var c: Vector3 = d["centre"]
		var want := 0.0
		if near_any:
			for p in chars:
				var dx := p.x - c.x
				var dz := p.z - c.z
				if dx * dx + dz * dz < DOOR_RADIUS * DOOR_RADIUS and absf(p.y - c.y) < 2.5:
					want = 1.0
					break
		if want != float(d["target"]):
			d["target"] = want
			_door_sound("door_open" if want > 0.5 else "door_close", c)


func _update_room_light(delta: float) -> void:
	_room_timer -= delta
	if _room_timer <= 0.0:
		_room_timer = 0.25
		var cam := get_viewport().get_camera_3d()
		var best := -1
		if cam != null:
			var cp := cam.global_position
			var best_d := ROOM_LIGHT_REACH * ROOM_LIGHT_REACH
			for i in _rooms.size():
				var d := (_rooms[i]["pos"] as Vector3).distance_squared_to(cp)
				if d < best_d:
					best_d = d
					best = i
		if best != _room_idx:
			if _room_fade <= 0.02 or best < 0:
				_room_idx = best
				if best >= 0:
					_room_light.global_position = _rooms[best]["pos"]
					_room_light.omni_range = float(_rooms[best]["range"])
			else:
				_room_idx = -2                  # fade out first, switch on the next scan
	var target := 1.0 if _room_idx >= 0 else 0.0
	if _room_fade != target:
		_room_fade = move_toward(_room_fade, target, delta * 2.5)
		_room_light.light_energy = ROOM_LIGHT_ENERGY * _room_fade
		_room_light.visible = _room_fade > 0.01


func _door_sound(id: String, pos: Vector3) -> void:
	var au := get_node_or_null("/root/Audio")
	if au != null and au.has_method("play_at"):
		au.call("play_at", id, pos, -6.0, 1.0, 25.0, "SFX")


# ---------------------------------------------------------------------------------------------
# public API (ARCHITECTURE_WAVE2 W2.4)
# ---------------------------------------------------------------------------------------------

func _lm(landmark: String) -> String:
	if _landmarks.has(landmark):
		return landmark
	return String(LANDMARK_ALIASES.get(landmark, landmark))


func has_landmark(landmark: String) -> bool:
	return _landmarks.has(_lm(landmark))


func get_landmark_node(landmark: String) -> Node3D:
	var r: Dictionary = _landmarks.get(_lm(landmark), {})
	if r.is_empty():
		return null
	var n: Variant = r["node"]
	if n != null and is_instance_valid(n):
		return n as Node3D
	return null


## Building origin in world space (footprint centre on the ground, -Z = front). Falls back to the
## world's named location when the landmark has no building.
func get_landmark_transform(landmark: String) -> Transform3D:
	var r: Dictionary = _landmarks.get(_lm(landmark), {})
	if not r.is_empty():
		return r["transform"]
	var w: Node = Game.world
	if w != null and w.has_method("has_location") and bool(w.call("has_location", landmark)):
		return w.call("get_location", landmark)
	return Transform3D.IDENTITY


func has_landmark_marker(landmark: String, marker: String) -> bool:
	var r: Dictionary = _landmarks.get(_lm(landmark), {})
	return not r.is_empty() and (r["markers"] as Dictionary).has(marker)


## World transform of a marker (manifest "markers" + "marker_yaw"; -Z = the marker's facing).
## Falls back to the landmark transform when the marker does not exist.
func get_landmark_marker(landmark: String, marker: String) -> Transform3D:
	var r: Dictionary = _landmarks.get(_lm(landmark), {})
	if r.is_empty():
		return get_landmark_transform(landmark)
	var mk: Dictionary = r["markers"]
	if not mk.has(marker):
		return r["transform"]
	return (r["transform"] as Transform3D) * (mk[marker] as Transform3D)


## marker name -> world Transform3D
func get_landmark_markers(landmark: String) -> Dictionary:
	var out := {}
	var r: Dictionary = _landmarks.get(_lm(landmark), {})
	if r.is_empty():
		return out
	var xf: Transform3D = r["transform"]
	var mk: Dictionary = r["markers"]
	for k: String in mk:
		out[k] = xf * (mk[k] as Transform3D)
	return out


## {id, lot_id, category, transform, footprint: Vector2, height} + extras: landmark, role
## ("landmark" | "building" | "filler" | "pier"), lot_ids, node, rect (Rect2 world x/z of the solid
## footprint), zone, district, collision, walk_in, plinth, markers (building-local).
func get_buildings() -> Array[Dictionary]:
	return _buildings


# --- additions ---------------------------------------------------------------------------------

func is_built() -> bool:
	return built


func get_landmark_names() -> PackedStringArray:
	var out := PackedStringArray(_landmarks.keys())
	out.sort()
	return out


func get_landmark_building(landmark: String) -> Dictionary:
	return _landmarks.get(_lm(landmark), {})


## The building whose solid footprint contains the x / z of `pos` ({} if none).
func get_building_at(pos: Vector3) -> Dictionary:
	var q := Vector2(pos.x, pos.z)
	for b in _buildings:
		if (b["rect"] as Rect2).has_point(q):
			return b
	return {}


func get_ladders() -> Array[Node3D]:
	return _ladders


## Door state for tests / debug: [{name, open (0..1), centre}]
func get_doors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in _doors:
		var nv: Variant = d["node"]
		var mi: MeshInstance3D = nv as MeshInstance3D if nv != null and is_instance_valid(nv) else null
		out.append({"name": String(mi.name) if mi != null else "", "open": float(d["t"]), "target": float(d["target"]),
				"centre": d["centre"], "node": mi})
	return out


func get_debug_info() -> Dictionary:
	return stats


func set_enabled(on: bool) -> void:
	enabled = on
	visible = on
	# the door loop AND the pooled room light (both run in _process)
	set_process(on and built and (not _doors.is_empty() or not _rooms.is_empty()))
	if not on and _room_light != null:
		_room_light.visible = false
		_room_fade = 0.0
		_room_idx = -1
