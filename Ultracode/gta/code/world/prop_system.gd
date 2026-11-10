class_name PropSystem
extends Node3D
## "props" world system (WORLD DRESSING): street furniture, traffic and street lights, vegetation,
## physics props and set pieces. See docs/DRESSING.md.
##
## Data flow: placers (gta/code/world/dressing/prop_place_*.gd) call place(id, xform) for every
## piece of dressing. Each instance is one entry in parallel packed arrays; its visual is a slot in a
## MultiMesh bucket (one MultiMeshInstance3D per asset / LOD / chunk) and its collider a shape owner
## on a batched StaticBody3D (a few per chunk and surface). Nothing per instance runs a script.
##
## Instance classes:
##   STATIC     scenery (walls, trees, rocks, set pieces, traffic signals): never moves.
##   BREAKABLE  manifest physics "breakable" (+ heavy "dynamic"): idle = MultiMesh + light static
##              collider; a fast vehicle, an explosion or enough bullet damage turns the instance
##              into a pooled WorldProp rigid body (cap MAX_ACTIVE) which topples / flies.
##   LOOSE      light "dynamic" props (cones, crates, bins, barrels ...): like BREAKABLE, but within
##              LOOSE_RADIUS of the player they exist as sleeping rigid bodies (cap MAX_LOOSE).
## Broken / displaced instances respawn after RESPAWN_SECONDS when the spot is far and unseen.

const Catalog := preload("res://gta/code/world/dressing/prop_catalog.gd")
const HitProxy := preload("res://gta/code/world/dressing/prop_hit_proxy.gd")
const PlaceStreet := preload("res://gta/code/world/dressing/prop_place_street.gd")
const PlaceNature := preload("res://gta/code/world/dressing/prop_place_nature.gd")
const PlaceSets := preload("res://gta/code/world/dressing/prop_place_sets.gd")
const LENS_SHADER := preload("res://gta/code/world/dressing/prp_signal_lens.gdshader")

const CHUNK := 150.0                ## chunk size of props / collision bodies
const TREE_CELL := 75.0             ## tree MultiMesh cell (LOD switch is per cell)
const SMALL_CELL := 75.0            ## small props, flush plates, reef
const COVER_CELL := 60.0            ## ground cover (grass, ferns, flowers, reeds)
const WIDE_CELL := 300.0            ## reef and signal lenses: tiny / rarely seen, fewer nodes
const TREE_LOD_DIST := 85.0         ## cell-centre distance where trees switch to their LOD1 mesh
const GRID := 8.0                   ## spatial hash for breakable / loose lookups
const OCC := 4.0                    ## occupancy hash cell
const MAX_ACTIVE := 60              ## knocked-over rigid bodies (shared debris budget)
const MAX_LOOSE := 64               ## sleeping loose bodies near the player
const LOOSE_RADIUS := 60.0
const LOOSE_RELEASE := 78.0
const RESPAWN_SECONDS := 150.0      ## game seconds before a broken prop may come back
const RESPAWN_MIN_DIST := 70.0
const CLEANUP_AGE := 25.0           ## a fallen prop may be cleaned up after this (if asleep / unseen)
const CLEANUP_MAX_AGE := 90.0
const CRIME_COOLDOWN := 8.0
const VEHICLE_MIN_SPEED := 3.0
const MOMENTUM_PER_KG := 25.0       ## vehicle mass * speed needed per kg of prop to knock it over in passing
const LOOKAHEAD := 0.12             ## seconds of vehicle travel checked ahead of the body
const DEFAULT_BOX := AABB(Vector3(-0.9, 0.2, -2.2), Vector3(1.8, 1.2, 4.4))
const HIDDEN_BASIS := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
const LAMP_COLOR := Color(1.0, 0.82, 0.56)

enum Cls { STATIC, BREAKABLE, LOOSE }
enum St { IDLE, ACTIVE, BROKEN, LIVE }

var catalog: RefCounted               ## prop_catalog.gd
var world: Node = null
var roads: Object = null
var enabled := true
## Game seconds before a broken / displaced prop may come back (admin / tests may shorten it).
var respawn_seconds := RESPAWN_SECONDS
var stats := {}                       ## build statistics
var missing_assets: PackedStringArray = []
var rejected := {}                    ## reason -> count (placements refused by the safety checks)

# --- types --------------------------------------------------------------------------------------
var _types: Array[Dictionary] = []
var _type_of: Dictionary = {}          ## asset id -> type index

# --- instances (parallel arrays) ----------------------------------------------------------------
var _i_type := PackedInt32Array()
var _i_xf: Array[Transform3D] = []
var _i_state := PackedByteArray()
var _i_cls := PackedByteArray()
var _i_slots: Array[PackedInt32Array] = []    ## [bucket, slot, bucket, slot ...]
var _i_body: Array = []                       ## StaticBody3D or null
var _i_owner := PackedInt32Array()            ## shape owner id on that body, -1 = none
var _i_hp := PackedFloat32Array()
var _i_t := PackedFloat32Array()              ## game time of the last state change
var _i_prop: Array = []                       ## WorldProp currently standing in for the instance
var _i_tag := PackedStringArray()             ## placement group (for counts / tests)

var _grid: Dictionary = {}             ## Vector2i -> PackedInt32Array (breakable + loose)
var _loose_grid: Dictionary = {}       ## Vector2i (30 m) -> PackedInt32Array (loose only)
var _occ: Dictionary = {}              ## Vector2i -> PackedFloat32Array [x, z, r ...]
var _owner_map: Dictionary = {}        ## body instance id -> {owner id: instance}

# --- render buckets -----------------------------------------------------------------------------
var _buckets: Array[Dictionary] = []
var _bucket_key: Dictionary = {}

# --- collision ----------------------------------------------------------------------------------
var _bodies: Dictionary = {}           ## "cx|cz|kind|surface" -> StaticBody3D

# --- scene roots --------------------------------------------------------------------------------
var _vis_root: Node3D
var _solid_root: Node3D
var _proxy: Node3D
var _pool_root: Node3D
var _light_root: Node3D
var _ladder_root: Node3D
var _scene_root: Node3D

# --- runtime ------------------------------------------------------------------------------------
var _now := 0.0
var _tick := 0.0
var _slow_tick := 0.0
var _anim_tick := 0.0
var _free_bodies: Array[WorldProp] = []
var _active: Array[WorldProp] = []
var _loose_live: Array[WorldProp] = []
var _spawned: Array = []
var _broken: PackedInt32Array = PackedInt32Array()
var _vehicles: Array = []
var _vehicles_t := 0.0
var _fuses: Array = []                 ## [time, instance or -1, WorldProp or null, instigator]
var _jets: Array = []                  ## [until, position, next]
var _last_crime := -100.0
var _lights: Dictionary = {}           ## instance -> light anchor Node3D
var _light_params: Dictionary = {}     ## instance -> [color, range, energy]
var _heads: Array[Dictionary] = []     ## traffic signal heads
var _peds: Array[Dictionary] = []      ## pedestrian signals
var _animated: Array[Dictionary] = []  ## {node, kind, part}
var _ladders: Array[Node3D] = []
var _setup_done := false
var _counts_cache := {}
var _exc_serial := 0                   ## tags the vehicle collision exception of a body (pool reuse safe)
var _ibox := PackedFloat32Array()      ## junction boxes [cx, cz, half x, half z ...] for on_carriageway()
var _phase_ms := {}                    ## placer phase -> ms (boot profile, get_debug_report().stats.phase_ms)
var _phase_t := 0
var _anim_acc := 0.0
var _respawn_q: PhysicsShapeQueryParameters3D = null


# =================================================================================================
# boot
# =================================================================================================

func _ready() -> void:
	process_physics_priority = 5


func setup() -> void:
	if _setup_done:
		return
	_setup_done = true
	var t0 := Time.get_ticks_msec()
	_make_roots()
	catalog = Catalog.new()
	catalog.call("load_manifests")
	for e: String in catalog.get("errors"):
		push_warning("[PropSystem] " + e)
	var t1 := Time.get_ticks_msec()
	world = Game.world if Game.world != null and is_instance_valid(Game.world) else Game.get_system("world")
	if world != null:
		roads = world.get("roads")
	var tp := {}
	if world != null and world.has_method("get_spawn_points"):
		var ta := Time.get_ticks_msec()
		mark_phase("")
		PlaceStreet.new().run(self)
		var tb := Time.get_ticks_msec()
		PlaceSets.new().run(self)
		var tc := Time.get_ticks_msec()
		PlaceNature.new().run(self)
		var td := Time.get_ticks_msec()
		tp = {"street_ms": tb - ta, "sets_ms": tc - tb, "nature_ms": td - tc}
	else:
		push_warning("[PropSystem] no world system: only spawn_prop() is available")
	var t2 := Time.get_ticks_msec()
	_build_buckets()
	_attach_bodies()
	_register_lights()
	# rigid-body hulls of everything that can be knocked over, built now instead of on the first crash
	var hull_max := 0
	for t: Dictionary in _types:
		if int(t["cls"]) != Cls.STATIC:
			for s: Array in catalog.call("rigid_shapes", t["id"]):
				if s[0] is ConvexPolygonShape3D:
					hull_max = maxi(hull_max, (s[0] as ConvexPolygonShape3D).points.size())
	var t3 := Time.get_ticks_msec()
	if not EventBus.explosion.is_connected(_on_explosion):
		EventBus.explosion.connect(_on_explosion)
	_update_signals(true)
	stats = {
		"setup_ms": Time.get_ticks_msec() - t0, "catalog_ms": t1 - t0, "place_ms": t2 - t1,
		"build_ms": t3 - t2, "instances": _i_type.size(), "buckets": _buckets.size(),
		"bodies": _bodies.size(), "types": _types.size(), "heads": _heads.size(),
		"ped_signals": _peds.size(), "ladders": _ladders.size(), "lights": _lights.size(),
	}
	stats.merge(tp)
	stats["phase_ms"] = _phase_ms
	stats["glb_load_ms"] = int(catalog.get("load_ms"))
	stats["rigid_hull_max_points"] = hull_max
	_counts_cache = {}
	print("[PropSystem] built in %d ms (catalog %d, place %d, build %d) | %d instances, %d types, %d multimesh nodes, %d static bodies, %d signal heads, %d ped signals, %d lamps, %d ladders" % [
			stats["setup_ms"], stats["catalog_ms"], stats["place_ms"], stats["build_ms"], _i_type.size(),
			_types.size(), _buckets.size(), _bodies.size(), _heads.size(), _peds.size(), _lights.size(), _ladders.size()])
	if not missing_assets.is_empty():
		push_warning("[PropSystem] missing assets (not placed): " + ", ".join(missing_assets))
	if not rejected.is_empty():
		var summary := {}
		for k: String in rejected:
			if not k.contains(":"):
				summary[k] = rejected[k]
		print("[PropSystem] placements refused by the safety checks (details: get_debug_report()): ", summary)


func _make_roots() -> void:
	_vis_root = _node("Visuals", self)
	_solid_root = _node("Solid", self)
	_proxy = HitProxy.new()
	_proxy.name = "Breakables"
	_proxy.set("system", weakref(self))
	add_child(_proxy)
	_pool_root = _node("Bodies", self)
	_light_root = _node("LightAnchors", self)
	_ladder_root = _node("Ladders", self)
	_scene_root = _node("SetPieces", self)


func _node(n: String, parent: Node) -> Node3D:
	var x := Node3D.new()
	x.name = n
	parent.add_child(x)
	return x


# =================================================================================================
# public API (ARCHITECTURE_WAVE2 W2.4 + admin / tests)
# =================================================================================================

## Spawns a standalone prop owned by the caller. Dynamic / breakable assets come back as a sleeping
## WorldProp (RigidBody3D, group "prop"); static assets as a Node3D with the mesh and a StaticBody3D.
## Returns null for unknown ids.
func spawn_prop(prop_id: String, xform: Transform3D) -> Node3D:
	if catalog == null:
		catalog = Catalog.new()
		catalog.call("load_manifests")
	var ti := _type_index(prop_id)
	if ti < 0:
		return null
	var t: Dictionary = _types[ti]
	var parent: Node = Game.get_entities_root()
	if parent == null:
		parent = self
	if int(t["cls"]) == Cls.STATIC:
		var root := Node3D.new()
		root.name = "Prop_" + prop_id
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = t["vis"]["mesh"]
		mi.transform = t["vis"]["xf"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if t["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var shapes: Array = t["shapes"]
		if not shapes.is_empty():
			var body := StaticBody3D.new()
			body.name = "Body"
			body.collision_layer = Layers.WORLD
			body.collision_mask = 0
			body.set_meta(&"surface", t["surface"])
			for s: Array in shapes:
				var cs := CollisionShape3D.new()
				cs.shape = s[0]
				cs.transform = s[1]
				body.add_child(cs)
			root.add_child(body)
		root.add_to_group("prop")
		root.set_meta(&"prop_id", prop_id)
		parent.add_child(root)
		root.global_transform = xform
		_spawned.append(root)
		return root
	var wp := _new_body()
	wp.configure(self, prop_id, t["vis"], catalog.call("rigid_shapes", prop_id), t["mass"], t["surface"], t["shadow"])
	wp.role = "spawned"
	wp.hp = t["hp"]
	wp.explosive = t["explosive"]
	wp.name = "Prop_" + prop_id
	parent.add_child(wp)
	wp.global_transform = xform
	wp.set_in_use(true)
	wp.sleeping = true
	wp.activated_at = _now
	_spawned.append(wp)
	return wp


## Merged manifest entry (+ "source", "path", "size_v", "center_v", "class") or {}.
func get_prop_def(prop_id: String) -> Dictionary:
	if catalog == null:
		return {}
	var d: Dictionary = catalog.call("get_def", prop_id)
	if d.is_empty():
		return {}
	var out := d.duplicate()
	var ti: int = _type_of.get(prop_id, -1)
	if ti >= 0:
		out["class"] = ["static", "breakable", "loose"][int(_types[ti]["cls"])]
	return out


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	# pooled night lights belong to the lamps: off with them, back with them
	for i: int in _light_params:
		_set_light(i, on and _i_state[i] == St.IDLE)


## Counts for the admin menu / tests.
func get_counts() -> Dictionary:
	var by_cat := {}
	var by_tag := {}
	var by_id := {}
	var states := [0, 0, 0, 0]
	for i in _i_type.size():
		var t: Dictionary = _types[_i_type[i]]
		var cat: String = t["group"]
		by_cat[cat] = int(by_cat.get(cat, 0)) + 1
		by_tag[_i_tag[i]] = int(by_tag.get(_i_tag[i], 0)) + 1
		by_id[t["id"]] = int(by_id.get(t["id"], 0)) + 1
		states[_i_state[i]] += 1
	var nodes := 0
	for b: Dictionary in _buckets:
		if b.get("node") != null:
			nodes += 1
	return {
		"instances": _i_type.size(), "by_category": by_cat, "by_tag": by_tag, "by_id": by_id,
		"idle": states[St.IDLE], "active": _active.size(), "broken": states[St.BROKEN],
		"loose_live": _loose_live.size(), "spawned": _spawned.size(), "multimesh_nodes": nodes,
		"static_bodies": _bodies.size(), "pooled_bodies": _free_bodies.size() + _active.size() + _loose_live.size(),
		"signal_heads": _heads.size(), "ped_signals": _peds.size(), "lamps": _lights.size(),
		"ladders": _ladders.size(), "set_piece_nodes": _scene_root.get_child_count() if _scene_root != null else 0,
	}


## Diagnostics: MultiMesh nodes per asset, timings, refused placements, missing assets.
func get_debug_report() -> Dictionary:
	var nodes_by_id := {}
	for b: Dictionary in _buckets:
		if b.get("node") == null:
			continue
		var k := String(b["key"]).get_slice("@", 0)
		nodes_by_id[k] = int(nodes_by_id.get(k, 0)) + 1
	return {"stats": stats, "nodes_by_asset": nodes_by_id, "rejected": rejected, "missing": missing_assets,
			"hill_fill_trees": get_meta(&"hill_fill_trees", 0)}


func get_instance_count() -> int:
	return _i_type.size()


func get_instance_id_of(i: int) -> String:
	return String(_types[_i_type[i]]["id"]) if i >= 0 and i < _i_type.size() else ""


func get_instance_transform(i: int) -> Transform3D:
	return _i_xf[i] if i >= 0 and i < _i_xf.size() else Transform3D.IDENTITY


## "idle", "active", "broken", "live".
func get_instance_state(i: int) -> String:
	if i < 0 or i >= _i_state.size():
		return ""
	return ["idle", "active", "broken", "live"][_i_state[i]]


func get_instance_tag(i: int) -> String:
	return _i_tag[i] if i >= 0 and i < _i_tag.size() else ""


func get_instance_body(i: int) -> WorldProp:
	if i < 0 or i >= _i_prop.size():
		return null
	var p: Variant = _i_prop[i]
	return p as WorldProp if p != null and is_instance_valid(p) else null


## Instances of an asset id (all when near == INF) within radius of `near`, nearest first.
func find_instances(prop_id: String, near: Vector3 = Vector3.INF, radius: float = INF) -> PackedInt32Array:
	var ti: int = _type_of.get(prop_id, -1)
	var out := PackedInt32Array()
	if ti < 0:
		return out
	var pairs: Array = []
	for i in _i_type.size():
		if _i_type[i] != ti:
			continue
		var d := 0.0 if near == Vector3.INF else _i_xf[i].origin.distance_to(near)
		if d <= radius:
			pairs.append([d, i])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for p: Array in pairs:
		out.append(int(p[1]))
	return out


## Knocks an instance over (admin / tests). Returns the rigid body or null.
func break_instance(i: int, impulse: Vector3 = Vector3.ZERO, instigator: Node = null) -> WorldProp:
	if i < 0 or i >= _i_type.size():
		return null
	var at := _i_xf[i].origin + Vector3(0.0, 0.6, 0.0)
	return _activate(i, impulse, at, instigator, "debug")


## Traffic head data for tests: Array of {position, lane_id, state, intersection_id}.
func get_signal_heads_info() -> Array:
	var out: Array = []
	for h: Dictionary in _heads:
		out.append({"position": h["pos"], "lane_id": h["lane"], "state": h["state"], "intersection_id": h["node"]})
	return out


## Pedestrian signals for tests / shots: Array of {position, facing, lane_id, walk, instance}.
func get_ped_signals_info() -> Array:
	var out: Array = []
	for h: Dictionary in _peds:
		var i := int(h["inst"])
		out.append({"position": _i_xf[i].origin, "facing": -_i_xf[i].basis.z, "lane_id": h["lane"],
				"walk": int(h["state"]) == 1, "instance": i})
	return out


## Lit lens per head as the GPU sees it: 0 green, 1 yellow, 2 red, -1 none / mixed.
func get_head_lit_state(k: int) -> int:
	if k < 0 or k >= _heads.size():
		return -1
	var h: Dictionary = _heads[k]
	if DisplayServer.get_name() == "headless":
		return int(h.get("lit", -1))     # the dummy renderer keeps no instance data
	var lit := -1
	for c in 3:
		var bs: PackedInt32Array = h["lens"][c]
		if bs.is_empty():
			continue
		var b: Dictionary = _buckets[bs[0]]
		var mm: MultiMesh = b.get("mm")
		if mm == null:
			continue
		if mm.get_instance_custom_data(bs[1]).r > 0.5:
			if lit >= 0:
				return -1
			lit = 2 - c
	return lit


## Seconds of game time since boot (the manager clock).
func get_time() -> float:
	return _now


func get_ladders() -> Array[Node3D]:
	return _ladders


# =================================================================================================
# placement API (used by the placers)
# =================================================================================================

func _type_index(id: String) -> int:
	if _type_of.has(id):
		return _type_of[id]
	if catalog == null or not catalog.call("has", id):
		if not missing_assets.has(id):
			missing_assets.append(id)
		return -1
	var d: Dictionary = catalog.call("get_def", id)
	var vis: Dictionary = catalog.call("visual_except", id, _excluded_parts(id))
	if vis.is_empty():
		if not missing_assets.has(id):
			missing_assets.append(id)
		_type_of[id] = -1
		return -1
	var size: Vector3 = d["size_v"]
	var physics: String = d["physics"]
	var mass: float = d["mass"]
	var cls := Cls.STATIC
	if physics == "breakable":
		cls = Cls.BREAKABLE
	elif physics == "dynamic":
		cls = Cls.LOOSE if mass <= 160.0 else Cls.BREAKABLE
	# (traffic_light_ped stays breakable: hiding an instance collapses all of its slots, lenses included)
	var source: String = d["source"]
	var cat: String = d["category"]
	var group := cat
	if source == "nature":
		group = "vegetation" if cat in ["tree", "shrub", "groundcover"] else ("underwater" if cat == "underwater" else "rocks")
	elif source == "misc":
		group = "set_piece"
	var vis_end: float = d["vis"]
	var cell := CHUNK
	if source == "nature" and cat == "tree":
		cell = TREE_CELL
	elif cat == "groundcover":
		cell = COVER_CELL
	elif cat == "underwater":
		cell = WIDE_CELL      # reef: only seen from the water, cheap meshes, coarse cells
	elif size.y <= 0.12:
		cell = CHUNK          # flush plates
	elif vis_end <= 90.0:
		cell = SMALL_CELL
	var t := {
		"id": id, "def": d, "cls": cls, "vis": vis, "lod1": catalog.call("lod1", id),
		# no shadows from small props; thin 3 m poles (signs, ped signals) cast none worth drawing either
		"shadow": size.y >= 2.4 and cat != "groundcover" and cat != "underwater" 				and not (Catalog.POLES.has(id) and size.y < 4.0),
		"vis_end": vis_end, "cell": cell, "shapes": catalog.call("static_shapes", id),
		"mass": mass, "surface": d["surface"], "group": group,
		"occ_r": clampf(maxf(size.x, size.z) * 0.5, 0.15, 6.0),
		"hp": 15.0 if (id == "barrel_explosive" or id == "gas_canister") else clampf(mass * 1.2, 25.0, 500.0),
		"explosive": id == "barrel_explosive" or id == "gas_canister",
		"v_min": clampf(2.5 + mass / 45.0, VEHICLE_MIN_SPEED, 14.0),
		"pole": Catalog.POLES.has(id), "height": size.y,
		# lateral reach of the idle collider for the vehicle sweep (pole radius, else half the smaller side)
		"hit_r": (float(Catalog.POLES[id]) if Catalog.POLES.has(id) else minf(size.x, size.z) * 0.5) + 0.06,
	}
	var ti := _types.size()
	_types.append(t)
	_type_of[id] = ti
	return ti


func _excluded_parts(id: String) -> Array:
	match id:
		"traffic_light":
			return ["Lamp_Red", "Lamp_Yellow", "Lamp_Green"]
		"traffic_light_ped":
			return ["Lamp_Stop", "Lamp_Walk"]
	return []


## True if `p` is clear of every reserved / placed footprint within `r`.
func is_free(p: Vector3, r: float) -> bool:
	var c0 := Vector2i(floori((p.x - r - 6.0) / OCC), floori((p.z - r - 6.0) / OCC))
	var c1 := Vector2i(floori((p.x + r + 6.0) / OCC), floori((p.z + r + 6.0) / OCC))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var a: Variant = _occ.get(Vector2i(cx, cz))
			if a == null:
				continue
			var arr: PackedFloat32Array = a
			var k := 0
			while k < arr.size():
				var dx := arr[k] - p.x
				var dz := arr[k + 1] - p.z
				var rr := arr[k + 2] + r
				if dx * dx + dz * dz < rr * rr:
					return false
				k += 3
	return true


## Marks a disc as taken (no dressing will be placed there).
func reserve(p: Vector3, r: float) -> void:
	var cell := Vector2i(floori(p.x / OCC), floori(p.z / OCC))
	var arr: PackedFloat32Array = _occ.get(cell, PackedFloat32Array())
	arr.append(p.x)
	arr.append(p.z)
	arr.append(r)
	_occ[cell] = arr


## True when the point lies on a carriageway (road / junction box / runway / taxiway / dirt track).
func on_carriageway(p: Vector3, margin: float = 0.0) -> bool:
	if roads == null:
		return false
	if int(roads.call("get_segment_at", p)) >= 0:
		return true
	if margin > 0.0:
		for o: Vector3 in [Vector3(margin, 0, 0), Vector3(-margin, 0, 0), Vector3(0, 0, margin), Vector3(0, 0, -margin)]:
			if int(roads.call("get_segment_at", p + o)) >= 0:
				return true
	if _ibox.is_empty():
		# junction boxes packed once: this runs for every one of the ~8000 placements
		for n: Dictionary in roads.get("intersections"):
			var c: Vector3 = n["position"]
			var bx: Vector2 = n["box"]
			_ibox.append_array(PackedFloat32Array([c.x, c.z, bx.x, bx.y]))
		if _ibox.is_empty():
			_ibox.append_array(PackedFloat32Array([INF, INF, 0.0, 0.0]))
	var k := 0
	var sz := _ibox.size()
	while k < sz:
		if absf(p.x - _ibox[k]) <= _ibox[k + 2] + margin and absf(p.z - _ibox[k + 1]) <= _ibox[k + 3] + margin:
			return true
		k += 4
	return false


func ground(x: float, z: float) -> float:
	if world != null and world.has_method("get_height"):
		return float(world.call("get_height", x, z))
	return Game.ground_height(x, z)


func surface_at(x: float, z: float) -> String:
	if world != null and world.has_method("get_surface_at"):
		return String(world.call("get_surface_at", Vector3(x, 50.0, z)))
	return "grass"


func spawn_points(kind: String) -> Array:
	if world == null:
		return []
	return world.call("get_spawn_points", kind)


## Places one instance. opts: "r" occupancy radius (default from the asset; <= 0 = no check),
## "no_occ" skip the occupancy test and do not reserve, "road_ok" allow on carriageways,
## "tag" placement group, "cls" force a class, "no_collision", "lod" (false = no LOD1).
## Returns the instance index or -1.
func place(id: String, xf: Transform3D, opts: Dictionary = {}) -> int:
	var ti := _type_index(id)
	if ti < 0:
		return -1
	var t: Dictionary = _types[ti]
	var r: float = float(opts.get("r", t["occ_r"]))
	var no_occ := bool(opts.get("no_occ", false)) or r <= 0.0
	var p := xf.origin
	if not no_occ and not is_free(p, r):
		_reject("occupied")
		_reject("occupied:" + id)
		return -1
	var shapes: Array = [] if bool(opts.get("no_collision", false)) else t["shapes"]
	if not bool(opts.get("road_ok", false)) and float(t["height"]) > 0.12 and on_carriageway(p):
		_reject("carriageway")
		_reject("carriageway:" + id)
		return -1
	var i := _i_type.size()
	_i_type.append(ti)
	_i_xf.append(xf)
	_i_state.append(St.IDLE)
	var cls := int(opts.get("cls", t["cls"]))
	_i_cls.append(cls)
	_i_hp.append(float(t["hp"]))
	_i_t.append(0.0)
	_i_prop.append(null)
	_i_tag.append(String(opts.get("tag", t["group"])))
	var slots := PackedInt32Array()
	var vis: Dictionary = t["vis"]
	var lod: Dictionary = t["lod1"]
	if not lod.is_empty() and bool(opts.get("lod", true)):
		_add_slot(slots, t["id"] + "|0", vis, xf, t, float(t["cell"]), 0.0, TREE_LOD_DIST)
		_add_slot(slots, t["id"] + "|1", lod, xf, t, float(t["cell"]), TREE_LOD_DIST, t["vis_end"])
	else:
		_add_slot(slots, t["id"], vis, xf, t, float(t["cell"]), 0.0, t["vis_end"])
	_i_slots.append(slots)
	# collider
	var body: StaticBody3D = null
	var owner := -1
	if not shapes.is_empty():
		var light := cls != Cls.STATIC
		body = _body_for(p, "light" if light else "solid", t["surface"])
		for s: Array in shapes:
			var o := body.create_shape_owner(body)
			body.shape_owner_add_shape(o, s[0])
			body.shape_owner_set_transform(o, xf * (s[1] as Transform3D))
			if owner < 0:
				owner = o
			_map_owner(body, o, i)
	_i_body.append(body)
	_i_owner.append(owner)
	if cls != Cls.STATIC:
		_grid_add(_grid, GRID, p, i)
		if cls == Cls.LOOSE:
			_grid_add(_loose_grid, 30.0, p, i)
	if not no_occ:
		reserve(p, r)
	_counts_cache = {}
	return i


## Boot profile helper for the placers: records the time since the previous mark under `phase`.
func mark_phase(phase: String) -> void:
	var now := Time.get_ticks_usec()
	if phase != "":
		_phase_ms[phase] = snappedf(float(now - _phase_t) / 1000.0, 0.1)
	_phase_t = now


func _reject(reason: String) -> void:
	rejected[reason] = int(rejected.get(reason, 0)) + 1


func _grid_add(g: Dictionary, cell: float, p: Vector3, i: int) -> void:
	var c := Vector2i(floori(p.x / cell), floori(p.z / cell))
	var arr: PackedInt32Array = g.get(c, PackedInt32Array())
	arr.append(i)
	g[c] = arr


func _map_owner(body: StaticBody3D, owner: int, i: int) -> void:
	var bid := body.get_instance_id()
	var m: Dictionary = _owner_map.get(bid, {})
	m[owner] = i
	_owner_map[bid] = m


## Extra render slot that belongs to an instance (traffic signal lenses ...). Returns [bucket, slot].
func add_extra_slot(i: int, key: String, vis: Dictionary, xf: Transform3D, opts: Dictionary = {}) -> PackedInt32Array:
	var t: Dictionary = _types[_i_type[i]]
	var slots: PackedInt32Array = _i_slots[i]
	var before := slots.size()
	_add_slot(slots, key, vis, xf, t, float(opts.get("cell", t["cell"])), 0.0, float(opts.get("vis_end", t["vis_end"])), opts)
	_i_slots[i] = slots
	return slots.slice(before, before + 2)


func _add_slot(slots: PackedInt32Array, key: String, vis: Dictionary, xf: Transform3D, t: Dictionary,
		cell: float, vis_begin: float, vis_end: float, opts: Dictionary = {}) -> void:
	var p := xf.origin
	var c := Vector2i(floori(p.x / cell), floori(p.z / cell))
	var full_key := "%s@%d,%d" % [key, c.x, c.y]
	var bi: int = _bucket_key.get(full_key, -1)
	if bi < 0:
		bi = _buckets.size()
		_bucket_key[full_key] = bi
		var fresh: Array[Transform3D] = []
		_buckets.append({
			"key": full_key, "mesh": vis["mesh"], "mesh_xf": vis["xf"], "xfs": fresh,
			"custom": bool(opts.get("custom", false)), "material": opts.get("material", null),
			"shadow": bool(opts.get("shadow", t["shadow"])), "vis_begin": vis_begin, "vis_end": vis_end,
			"cell": cell, "center": Vector3((c.x + 0.5) * cell, 0.0, (c.y + 0.5) * cell), "mm": null, "node": null,
		})
	var b: Dictionary = _buckets[bi]
	var xfs: Array[Transform3D] = b["xfs"]
	slots.append(bi)
	slots.append(xfs.size())
	xfs.append(xf * (vis["xf"] as Transform3D))


func _body_for(p: Vector3, kind: String, surface: String) -> StaticBody3D:
	var c := Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))
	var key := "%d|%d|%s|%s" % [c.x, c.y, kind, surface]
	var b: StaticBody3D = _bodies.get(key)
	if b == null:
		b = StaticBody3D.new()
		b.name = "Body_%s_%s_%d_%d" % [kind, surface, c.x, c.y]
		b.collision_layer = Layers.PROP if kind == "light" else Layers.WORLD
		b.collision_mask = 0
		b.set_meta(&"surface", surface)
		if kind == "light":
			b.set_meta(&"thin", true)
		_bodies[key] = b
	return b


## Adds a group "ladder" node (W2.4): origin at the foot, the climber faces local -Z.
func add_ladder(foot: Transform3D, height: float, top_exit: Vector3 = Vector3.INF) -> Node3D:
	var n := Node3D.new()
	n.name = "Ladder_%d" % _ladders.size()
	n.set_meta(&"height", height)
	if top_exit != Vector3.INF:
		n.set_meta(&"top_exit", top_exit)
	n.add_to_group("ladder")
	_ladder_root.add_child(n)
	n.global_transform = foot
	_ladders.append(n)
	return n


## Animated set piece (windsock sock, radar dish, helipad beacon): instantiated scene + collider.
func add_scene_piece(id: String, xf: Transform3D, anim_part: String, anim_kind: String, tag: String = "set_piece") -> Node3D:
	var ti := _type_index(id)
	if ti < 0:
		return null
	var t: Dictionary = _types[ti]
	var path: String = t["def"]["path"]
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return null
	inst.name = "%s_%d" % [id, _scene_root.get_child_count()]
	_scene_root.add_child(inst)
	inst.global_transform = xf
	for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if t["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mi as MeshInstance3D).visibility_range_end = float(t["vis_end"]) + 40.0
	var shapes: Array = t["shapes"]
	if not shapes.is_empty():
		var body := _body_for(xf.origin, "solid", t["surface"])
		for s: Array in shapes:
			var o := body.create_shape_owner(body)
			body.shape_owner_add_shape(o, s[0])
			body.shape_owner_set_transform(o, xf * (s[1] as Transform3D))
	if anim_part != "":
		var part := inst.find_child(anim_part, true, false) as Node3D
		if part != null:
			_animated.append({"node": part, "kind": anim_kind, "base": part.transform, "phase": randf() * TAU, "root": inst})
	reserve(xf.origin, float(t["occ_r"]))
	return inst


## Registers a street lamp light (pooled real light at night) for an instance.
func add_lamp_light(i: int, local_marker: Transform3D, color: Color = LAMP_COLOR, light_range: float = 16.0, energy: float = 3.0) -> void:
	var n := Node3D.new()
	n.name = "L%d" % i
	n.position = (_i_xf[i] * local_marker).origin
	_lights[i] = n
	_light_params[i] = [color, light_range, energy]


## Traffic head registration (street placer).
func add_signal_head(i: int, lane_id: int, node_id: int, lens: Array) -> void:
	_heads.append({"inst": i, "lane": lane_id, "node": node_id, "lens": lens, "state": -1, "pos": _i_xf[i].origin})


func add_ped_signal(i: int, lane_id: int, lens: Array) -> void:
	_peds.append({"inst": i, "lane": lane_id, "lens": lens, "state": -1})


func get_type_visual(id: String) -> Dictionary:
	var ti := _type_index(id)
	return _types[ti]["vis"] if ti >= 0 else {}


# =================================================================================================
# build
# =================================================================================================

func _build_buckets() -> void:
	# lamp lenses / neon / windows on the (merged) meshes -> the environment's night hook materials
	var env := Game.get_system("environment")
	var hooked := {}
	for b: Dictionary in _buckets:
		var m: Mesh = b["mesh"]
		if m == null or hooked.has(m.get_instance_id()) or b["material"] != null:
			continue
		hooked[m.get_instance_id()] = true
		if env != null and env.has_method("apply_night_materials_to_mesh"):
			env.call("apply_night_materials_to_mesh", m)
	for bi in _buckets.size():
		var b: Dictionary = _buckets[bi]
		var xfs: Array[Transform3D] = b["xfs"]
		if xfs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = bool(b["custom"])
		mm.mesh = b["mesh"]
		mm.instance_count = xfs.size()
		for k in xfs.size():
			mm.set_instance_transform(k, xfs[k])
			if mm.use_custom_data:
				mm.set_instance_custom_data(k, Color(0, 0, 0, 0))
		var node := MultiMeshInstance3D.new()
		node.name = "MM_" + String(b["key"]).replace("|", "_").replace("@", "_").replace(",", "_")
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if b["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var half_diag := float(b["cell"]) * 0.7072
		var ve := float(b["vis_end"])
		if float(b["vis_begin"]) > 0.0:
			# LOD1 of a tree cell: takes over where the LOD0 node of the same cell stops
			node.visibility_range_begin = float(b["vis_begin"])
			node.visibility_range_begin_margin = 4.0
			node.visibility_range_end = ve + half_diag
		elif String(b["key"]).contains("|0@"):
			node.visibility_range_end = ve
			node.visibility_range_end_margin = 4.0
		elif ve > 0.0 and ve < 5000.0:
			# the range is measured to the node's AABB centre: never cull the cell the camera stands in
			node.visibility_range_end = ve if float(b["cell"]) <= COVER_CELL else ve + half_diag * 0.6
			node.visibility_range_end_margin = 6.0
		if b["material"] != null:
			node.material_override = b["material"]
		_vis_root.add_child(node)
		b["mm"] = mm
		b["node"] = node


func _attach_bodies() -> void:
	for key: String in _bodies:
		var b: StaticBody3D = _bodies[key]
		if b.get_parent() != null:
			continue
		if (b.collision_layer & Layers.PROP) != 0:
			_proxy.add_child(b)
		else:
			_solid_root.add_child(b)


func _register_lights() -> void:
	for i: int in _lights:
		var n: Node3D = _lights[i]
		if n.get_parent() == null:
			_light_root.add_child(n)
	var env := Game.get_system("environment")
	if env == null or not env.has_method("register_light_points"):
		return
	# one call per parameter set (lamp_a / lamp_b ...)
	var groups := {}
	for i: int in _lights:
		var prm: Array = _light_params[i]
		var key := "%s|%s|%s" % [str(prm[0]), str(prm[1]), str(prm[2])]
		if not groups.has(key):
			groups[key] = [prm, []]
		(groups[key][1] as Array).append(_lights[i])
	for key: String in groups:
		var g: Array = groups[key]
		env.call("register_light_points", g[1], g[0][0], g[0][1], g[0][2])


# =================================================================================================
# visibility of instance slots
# =================================================================================================

func _set_visual(i: int, on: bool) -> void:
	var slots: PackedInt32Array = _i_slots[i]
	var k := 0
	while k < slots.size():
		var b: Dictionary = _buckets[slots[k]]
		var mm: MultiMesh = b["mm"]
		if mm != null:
			var xf: Transform3D = (b["xfs"] as Array[Transform3D])[slots[k + 1]]
			mm.set_instance_transform(slots[k + 1], xf if on else Transform3D(HIDDEN_BASIS, xf.origin))
		k += 2


func _set_collider(i: int, on: bool) -> void:
	var body: Variant = _i_body[i]
	if body == null:
		return
	var sb := body as StaticBody3D
	var owner := _i_owner[i]
	if owner < 0:
		return
	var m: Dictionary = _owner_map.get(sb.get_instance_id(), {})
	for o: int in m:
		if int(m[o]) == i:
			sb.shape_owner_set_disabled(o, not on)


func _set_light(i: int, on: bool) -> void:
	if not _light_params.has(i):
		return
	var cur: Variant = _lights.get(i)
	if not on:
		if cur != null and is_instance_valid(cur):
			(cur as Node).queue_free()
		_lights.erase(i)
		return
	if cur != null and is_instance_valid(cur):
		return
	var t: Dictionary = _types[_i_type[i]]
	var mk: Variant = catalog.call("marker", t["id"], "Light")
	var local: Transform3D = mk if mk != null else Transform3D(Basis.IDENTITY, Vector3(0, float(t["height"]) - 0.3, 0))
	var n := Node3D.new()
	n.name = "L%d" % i
	_light_root.add_child(n)
	n.global_position = (_i_xf[i] * local).origin
	_lights[i] = n
	var prm: Array = _light_params[i]
	var env := Game.get_system("environment")
	if env != null and env.has_method("register_light_points"):
		env.call("register_light_points", [n], prm[0], prm[1], prm[2])


# =================================================================================================
# runtime
# =================================================================================================

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_now += delta
	_sweep_vehicles(delta)
	if not _fuses.is_empty():
		_update_fuses()
	if not _jets.is_empty():
		_update_jets()


func _process(delta: float) -> void:
	if not enabled or not _setup_done:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.25
		_update_signals(false)
		_update_loose()
		_update_active()
	_slow_tick -= delta
	if _slow_tick <= 0.0:
		_slow_tick = 2.0
		_update_respawn()
	if not _animated.is_empty():
		# 30 Hz updates with the real elapsed time (no slow motion below 30 fps)
		_anim_acc += delta
		_anim_tick -= delta
		if _anim_tick <= 0.0:
			_anim_tick = 1.0 / 30.0
			_update_animated(minf(_anim_acc, 0.25))
			_anim_acc = 0.0


func _focus() -> Vector3:
	if Game.has_player():
		return Game.get_player_position()
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		return cam.global_position
	return Vector3.INF


func _camera() -> Camera3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


# --- vehicles -----------------------------------------------------------------------------------

func _sweep_vehicles(delta: float) -> void:
	_vehicles_t -= delta
	if _vehicles_t <= 0.0:
		_vehicles_t = 0.5
		_vehicles = get_tree().get_nodes_in_group("vehicle")
	for v: Variant in _vehicles:
		if v == null or not is_instance_valid(v):
			continue
		var rb := v as RigidBody3D
		if rb == null or rb.freeze or not rb.is_inside_tree():
			continue
		var vel := rb.linear_velocity
		var sp2 := vel.length_squared()
		if sp2 < VEHICLE_MIN_SPEED * VEHICLE_MIN_SPEED:
			continue
		var box: AABB = DEFAULT_BOX
		var bv: Variant = rb.get("body_aabb")
		if bv is AABB:
			box = bv
		var gt := rb.global_transform
		var speed := sqrt(sp2)
		var center := gt * box.get_center()
		var reach := box.size.length() * 0.5 + speed * LOOKAHEAD + 1.5
		var inv := gt.affine_inverse()
		var lvel := inv.basis * vel
		var c0 := Vector2i(floori((center.x - reach) / GRID), floori((center.z - reach) / GRID))
		var c1 := Vector2i(floori((center.x + reach) / GRID), floori((center.z + reach) / GRID))
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var a: Variant = _grid.get(Vector2i(cx, cz))
				if a == null:
					continue
				for i: int in (a as PackedInt32Array):
					if _i_state[i] != St.IDLE:
						continue
					var t: Dictionary = _types[_i_type[i]]
					if speed < float(t["v_min"]):
						continue
					# momentum: a bicycle / motorbike does not mow down a lamp post (it hits the idle collider)
					if rb.mass * speed < float(t["mass"]) * MOMENTUM_PER_KG:
						continue
					var p := _i_xf[i].origin + Vector3(0.0, 0.5, 0.0)
					if p.distance_squared_to(center) > reach * reach:
						continue
					var lp := inv * p
					var pr: float = t["hit_r"]
					var hit := false
					for step in 3:
						var q := lp - lvel * (LOOKAHEAD * 0.5 * step)
						if q.x > box.position.x - pr and q.x < box.end.x + pr and q.z > box.position.z - pr \
								and q.z < box.end.z + pr and q.y > box.position.y - 1.2 and q.y < box.end.y + 0.6:
							hit = true
							break
					if not hit:
						continue
					var imp := vel.normalized() * float(t["mass"]) * speed * 0.55 + Vector3.UP * float(t["mass"]) * 1.2
					var body := _activate(i, imp, _i_xf[i].origin + Vector3(0.0, 0.7, 0.0), rb, "vehicle")
					if body != null:
						body.add_collision_exception_with(rb)
						body.set_meta(&"exc_rid", rb.get_rid())
						_exc_serial += 1
						body.set_meta(&"exc_serial", _exc_serial)
						_drop_exception_later(body, _exc_serial)
						Audio.play_at("crash_small" if float(t["mass"]) < 120.0 else "crash_large", p, -2.0, randf_range(0.9, 1.1), 60.0)
						Fx.sparks(p, -vel.normalized(), 0.6)


## The car passes "through" the first contact frame (no dead stop on a lamp post); the exception
## is removed again a moment later so the car can still hit the prop when it lands. `serial` guards
## against a pooled body that was retired and re-used for another prop (with a newer exception) since.
func _drop_exception_later(body: WorldProp, serial: int) -> void:
	await get_tree().create_timer(0.18, false, true).timeout
	if not is_instance_valid(body) or not body.has_meta(&"exc_rid"):
		return
	if int(body.get_meta(&"exc_serial", -1)) != serial:
		return
	PhysicsServer3D.body_remove_collision_exception(body.get_rid(), body.get_meta(&"exc_rid"))
	body.remove_meta(&"exc_rid")
	body.remove_meta(&"exc_serial")


# --- activation -----------------------------------------------------------------------------------

func _new_body() -> WorldProp:
	var wp := WorldProp.new()
	return wp


func _acquire(role: String) -> WorldProp:
	if role == "loose":
		if _loose_live.size() >= MAX_LOOSE:
			return null
	elif _active.size() >= MAX_ACTIVE:
		# recycle the oldest knocked-over prop (preferably one the camera cannot see)
		var cam := _camera()
		var pick: WorldProp = null
		for b: WorldProp in _active:
			if not is_instance_valid(b):
				continue
			if cam == null or not cam.is_position_in_frustum(b.global_position):
				pick = b
				break
		if pick == null and not _active.is_empty():
			pick = _active[0]
		if pick == null:
			return null
		_retire(pick, true)
	var wp: WorldProp = _free_bodies.pop_back() if not _free_bodies.is_empty() else null
	if wp == null or not is_instance_valid(wp):
		wp = _new_body()
		_pool_root.add_child(wp)
	return wp


## Turns instance `i` into a rigid body and applies `impulse` at the world point `at`.
func _activate(i: int, impulse: Vector3, at: Vector3, instigator: Node, reason: String) -> WorldProp:
	if i < 0 or i >= _i_type.size():
		return null
	var st := _i_state[i]
	var t: Dictionary = _types[_i_type[i]]
	if st == St.LIVE:
		var live := get_instance_body(i)
		if live != null:
			live.sleeping = false
			live.apply_impulse(impulse, at - live.global_position)
			if instigator != null:
				live.instigator = instigator
		return live
	if st != St.IDLE:
		return null
	if _i_cls[i] == Cls.STATIC:
		return null
	var body := _acquire("active")
	if body == null:
		return null
	_set_visual(i, false)
	_set_collider(i, false)
	_set_light(i, false)
	_configure_body(body, i, t, "active")
	body.instigator = instigator
	_active.append(body)
	_i_state[i] = St.ACTIVE
	_i_t[i] = _now
	if impulse != Vector3.ZERO:
		body.apply_impulse(impulse, at - body.global_position)
	_on_broken(i, body, instigator, reason)
	return body


func _configure_body(body: WorldProp, i: int, t: Dictionary, role: String) -> void:
	var id: String = t["id"]
	body.configure(self, id, t["vis"], catalog.call("rigid_shapes", id), t["mass"], t["surface"], t["shadow"])
	body.role = role
	body.source_index = i
	body.hp = _i_hp[i]
	body.explosive = bool(t["explosive"])
	body.activated_at = _now
	_i_prop[i] = body
	body.set_in_use(true)
	body.global_transform = _i_xf[i]
	if bool(t["pole"]) or float(t["height"]) > 2.5:
		body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		body.center_of_mass = Vector3(0.0, float(t["height"]) * 0.32, 0.0)
	else:
		body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_AUTO
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = role == "loose"


## Side effects of a breakage: signal, sound, water jet, crime.
func _on_broken(i: int, body: WorldProp, instigator: Node, reason: String) -> void:
	var t: Dictionary = _types[_i_type[i]]
	var id: String = t["id"]
	var p := _i_xf[i].origin
	if _i_cls[i] == Cls.BREAKABLE:
		EventBus.prop_broken.emit(body, instigator)
		var snd := "impact_metal"
		match String(t["surface"]):
			"wood":
				snd = "impact_wood"
			"concrete":
				snd = "impact_concrete"
		Audio.play_at(snd, p + Vector3.UP * 0.6, 0.0, randf_range(0.85, 1.05), 50.0)
		EventBus.noise_emitted.emit(p, 25.0, "crash", instigator)
		if id == "hydrant":
			_jets.append([_now + 6.0, p + Vector3(0.0, 0.25, 0.0), 0.0])
		elif id == "bus_stop":
			Audio.play_at("glass_break", p + Vector3.UP * 1.5, 0.0, 1.0, 50.0)
			Fx.glass_shatter(p + Vector3.UP * 1.5, Vector3.UP, 1.4)
		if reason != "debug" and instigator != null and _now - _last_crime > CRIME_COOLDOWN \
				and _player_caused(instigator):
			_last_crime = _now
			var wanted := get_node_or_null("/root/Wanted")
			if wanted != null and wanted.has_method("report_crime"):
				wanted.call("report_crime", "property_damage", p, {"instigator": instigator})
	if not _broken.has(i):
		_broken.append(i)


## Takes a body out of the world. `keep_broken` = the instance stays broken (respawns later).
func _retire(body: WorldProp, keep_broken: bool) -> void:
	if body == null or not is_instance_valid(body):
		return
	var i := body.source_index
	_active.erase(body)
	_loose_live.erase(body)
	if i >= 0 and i < _i_prop.size() and _i_prop[i] == body:
		_i_prop[i] = null
		if keep_broken:
			_i_state[i] = St.BROKEN
			_i_t[i] = _now
			if not _broken.has(i):
				_broken.append(i)
	if body.has_meta(&"exc_rid"):
		# by RID: the vehicle may already be freed
		PhysicsServer3D.body_remove_collision_exception(body.get_rid(), body.get_meta(&"exc_rid"))
		body.remove_meta(&"exc_rid")
	if body.has_meta(&"exc_serial"):
		body.remove_meta(&"exc_serial")
	body.set_in_use(false)
	if body.get_parent() != _pool_root:
		body.get_parent().remove_child(body)
		_pool_root.add_child(body)
	_free_bodies.append(body)


# --- loose props near the player ---------------------------------------------------------------

func _update_loose() -> void:
	var f := _focus()
	if f == Vector3.INF:
		return
	# release loose bodies that are far away
	for k in range(_loose_live.size() - 1, -1, -1):
		var b: WorldProp = _loose_live[k]
		if not is_instance_valid(b):
			_loose_live.remove_at(k)
			continue
		var i := b.source_index
		if b.global_position.y < -40.0:
			_retire(b, true)
			continue
		if b.global_position.distance_to(f) < LOOSE_RELEASE and (i < 0 or _i_xf[i].origin.distance_to(f) < LOOSE_RELEASE):
			continue
		var home := _i_xf[i] if i >= 0 else b.global_transform
		var moved := b.global_position.distance_to(home.origin) > 0.3 or b.global_basis.y.dot(home.basis.y.normalized()) < 0.97
		if moved:
			_retire(b, true)
		else:
			_retire(b, false)
			if i >= 0:
				_i_state[i] = St.IDLE
				_set_visual(i, true)
				_set_collider(i, true)
	# spawn sleeping bodies for idle loose instances in range
	var c0 := Vector2i(floori((f.x - LOOSE_RADIUS) / 30.0), floori((f.z - LOOSE_RADIUS) / 30.0))
	var c1 := Vector2i(floori((f.x + LOOSE_RADIUS) / 30.0), floori((f.z + LOOSE_RADIUS) / 30.0))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var a: Variant = _loose_grid.get(Vector2i(cx, cz))
			if a == null:
				continue
			for i: int in (a as PackedInt32Array):
				if _i_state[i] != St.IDLE or _i_cls[i] != Cls.LOOSE:
					continue
				if _i_xf[i].origin.distance_to(f) > LOOSE_RADIUS:
					continue
				var body := _acquire("loose")
				if body == null:
					return
				_set_visual(i, false)
				_set_collider(i, false)
				_configure_body(body, i, _types[_i_type[i]], "loose")
				_loose_live.append(body)
				_i_state[i] = St.LIVE
				_i_t[i] = _now


# --- knocked-over props: cleanup ----------------------------------------------------------------

func _update_active() -> void:
	for k in range(_spawned.size() - 1, -1, -1):
		if not is_instance_valid(_spawned[k]):
			_spawned.remove_at(k)
	if _active.is_empty():
		return
	var f := _focus()
	var cam := _camera()
	for k in range(_active.size() - 1, -1, -1):
		var b: WorldProp = _active[k]
		if not is_instance_valid(b):
			_active.remove_at(k)
			continue
		var age := _now - b.activated_at
		if b.global_position.y < -40.0:
			_retire(b, true)
			continue
		if age < CLEANUP_AGE:
			continue
		var far := f == Vector3.INF or b.global_position.distance_to(f) > 45.0
		var unseen := cam == null or not cam.is_position_in_frustum(b.global_position) \
				or cam.global_position.distance_to(b.global_position) > 90.0
		if (b.sleeping or age > CLEANUP_MAX_AGE) and (far or unseen) and (unseen or age > CLEANUP_MAX_AGE * 2.0):
			_retire(b, true)


# --- respawn ------------------------------------------------------------------------------------

func _update_respawn() -> void:
	if _broken.is_empty():
		return
	var f := _focus()
	var cam := _camera()
	for k in range(_broken.size() - 1, -1, -1):
		var i := _broken[k]
		if _i_state[i] == St.IDLE:
			_broken.remove_at(k)
			continue
		if _now - _i_t[i] < respawn_seconds:
			continue
		var p := _i_xf[i].origin
		if f != Vector3.INF and p.distance_to(f) < RESPAWN_MIN_DIST:
			continue
		if cam != null and cam.is_position_in_frustum(p) and cam.global_position.distance_to(p) < 160.0:
			continue
		var body := get_instance_body(i)
		if body != null:
			if cam != null and cam.is_position_in_frustum(body.global_position) and cam.global_position.distance_to(body.global_position) < 160.0:
				continue
		if _spot_occupied(i, body):
			_i_t[i] = _now - respawn_seconds + 10.0      # a car / person stands there: try again in 10 s
			continue
		if body != null:
			_retire(body, false)
		_respawn(i)
		_broken.remove_at(k)


## True when a vehicle, character or another loose body overlaps the home spot of instance `i`
## (its static collider would appear inside it). `own` = the instance's current body, ignored.
func _spot_occupied(i: int, own: WorldProp) -> bool:
	if not is_inside_tree():
		return false
	var t: Dictionary = _types[_i_type[i]]
	var d: Dictionary = t["def"]
	var size: Vector3 = d.get("size_v", Vector3.ONE)
	if _respawn_q == null:
		_respawn_q = PhysicsShapeQueryParameters3D.new()
		_respawn_q.shape = BoxShape3D.new()
		_respawn_q.collision_mask = Layers.VEHICLE | Layers.PLAYER | Layers.NPC | Layers.RAGDOLL | Layers.PROP
	var bx := _respawn_q.shape as BoxShape3D
	# poles: the footprint of the pole, not of the arm over the road
	var r := float(t["hit_r"]) if bool(t["pole"]) else 0.0
	bx.size = Vector3(maxf(r * 2.0, size.x * 0.9), maxf(size.y * 0.9, 0.2), maxf(r * 2.0, size.z * 0.9))
	var c: Vector3 = Vector3(0.0, bx.size.y * 0.5 + 0.05, 0.0) if r > 0.0 else d.get("center_v", Vector3(0.0, size.y * 0.5, 0.0))
	_respawn_q.transform = _i_xf[i] * Transform3D(Basis.IDENTITY, c)
	_respawn_q.exclude = [own.get_rid()] if own != null else []
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(_respawn_q, 4):
		var col: Object = hit.get("collider")
		if col is StaticBody3D:
			continue        # idle colliders of the neighbouring dressing (batched static bodies)
		return true
	return false


func _respawn(i: int) -> void:
	_i_state[i] = St.IDLE
	_i_hp[i] = float(_types[_i_type[i]]["hp"])
	_i_t[i] = _now
	_i_prop[i] = null
	_set_visual(i, true)
	_set_collider(i, true)
	_set_light(i, true)


## Puts every broken / displaced prop back at once (admin "repair city" / tests).
func respawn_all() -> int:
	var n := 0
	for b: WorldProp in _active.duplicate():
		_retire(b, true)
	for i in _i_state.size():
		if _i_state[i] == St.BROKEN:
			_respawn(i)
			n += 1
	_broken.clear()
	return n


# --- damage -------------------------------------------------------------------------------------

## A bullet / melee hit / vehicle bump on an idle collider (through prop_hit_proxy.gd).
func _on_static_prop_damage(info: Dictionary) -> void:
	var type := String(info.get("type", ""))
	if type == "explosion":
		return          # handled with the exact blast centre in _on_explosion
	var i := -1
	var col: Variant = info.get("collider", null)
	if col != null and is_instance_valid(col) and col is StaticBody3D and info.has("shape"):
		var sb := col as StaticBody3D
		var o := sb.shape_find_owner(int(info["shape"]))
		var m: Dictionary = _owner_map.get(sb.get_instance_id(), {})
		i = int(m.get(o, -1))
	var pos: Vector3 = info.get("position", Vector3.INF)
	if i < 0 and pos != Vector3.INF:
		i = _nearest(pos, 1.8)
	if i < 0 or _i_state[i] != St.IDLE:
		return
	var t: Dictionary = _types[_i_type[i]]
	var amount := float(info.get("amount", 0.0))
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	if dir == Vector3.ZERO:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var who := _valid_node(info.get("instigator", null))
	if bool(t["explosive"]):
		_i_hp[i] -= amount
		if _i_hp[i] <= 0.0:
			_light_fuse(i, null, who)
		return
	if type == "vehicle":
		# VehicleBase sends amount = dv * 14 and impulse = dv * mass * 0.4 (mass capped at 2 t): scale the
		# bump by the vehicle mass so a bicycle does not floor a lamp post but a car does
		var imp_v := float(info.get("impulse", 0.0))
		var mass_f := 1.0
		if imp_v > 0.0 and amount > 0.0:
			mass_f = clampf(35.0 * imp_v / amount / 1200.0, 0.08, 1.6)
		amount *= 2.5 * mass_f
	_i_hp[i] -= amount
	if _i_hp[i] > 0.0 and _i_cls[i] != Cls.LOOSE:
		return
	var imp := dir * clampf(float(info.get("impulse", 0.0)), float(t["mass"]) * 1.5, float(t["mass"]) * 7.0)
	_activate(i, imp, pos if pos != Vector3.INF else _i_xf[i].origin + Vector3.UP * 0.6, who, type)


## Damage on a live rigid prop (bullets, blasts, fire).
func _on_world_prop_damage(body: WorldProp, info: Dictionary) -> void:
	var type := String(info.get("type", ""))
	var amount := float(info.get("amount", 0.0))
	var who := _valid_node(info.get("instigator", null))
	if who != null:
		body.instigator = who
	if type != "explosion":
		var dir: Vector3 = info.get("direction", Vector3.ZERO)
		var imp := float(info.get("impulse", 0.0))
		if dir != Vector3.ZERO and imp > 0.0:
			var at: Vector3 = info.get("position", body.global_position)
			body.apply_impulse(dir.normalized() * minf(imp, body.mass * 6.0), at - body.global_position)
	if body.explosive:
		body.hp -= amount
		if body.hp <= 0.0:
			_light_fuse(body.source_index, body, who)


## Dmg.caused_by_player without its bool(null) trap for vehicle-group bodies lacking is_player_driven.
static func _player_caused(who: Node) -> bool:
	if who == null or not is_instance_valid(who):
		return false
	if who.is_in_group("player"):
		return true
	if who.is_in_group("vehicle"):
		return who.get("is_player_driven") == true
	return false


static func _valid_node(v: Variant) -> Node:
	if v == null or not is_instance_valid(v) or not (v is Node):
		return null
	return v as Node


func _nearest(pos: Vector3, max_d: float) -> int:
	var best := -1
	var bd := max_d * max_d
	var c0 := Vector2i(floori((pos.x - max_d) / GRID), floori((pos.z - max_d) / GRID))
	var c1 := Vector2i(floori((pos.x + max_d) / GRID), floori((pos.z + max_d) / GRID))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var a: Variant = _grid.get(Vector2i(cx, cz))
			if a == null:
				continue
			for i: int in (a as PackedInt32Array):
				var q := _i_xf[i].origin
				var d := Vector2(q.x - pos.x, q.z - pos.z).length_squared()
				if d < bd:
					bd = d
					best = i
	return best


func _on_explosion(pos: Vector3, radius: float, instigator: Node) -> void:
	if not enabled:
		return
	var r := radius * 1.1
	var c0 := Vector2i(floori((pos.x - r) / GRID), floori((pos.z - r) / GRID))
	var c1 := Vector2i(floori((pos.x + r) / GRID), floori((pos.z + r) / GRID))
	var who: Node = instigator if instigator != null and is_instance_valid(instigator) else null
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var a: Variant = _grid.get(Vector2i(cx, cz))
			if a == null:
				continue
			for i: int in (a as PackedInt32Array):
				var st := _i_state[i]
				if st != St.IDLE:
					continue
				var t: Dictionary = _types[_i_type[i]]
				var c: Vector3 = _i_xf[i].origin + Vector3(0.0, minf(float(t["height"]) * 0.5, 1.0), 0.0)
				var d := c.distance_to(pos)
				if d > r:
					continue
				var f := clampf(1.0 - d / r, 0.0, 1.0)
				if bool(t["explosive"]):
					_light_fuse(i, null, who)
					continue
				if f * 220.0 < float(_i_hp[i]) * 0.5 and _i_cls[i] != Cls.LOOSE:
					continue
				var dir := (c - pos).normalized() + Vector3.UP * 0.6
				var m := float(t["mass"])
				var imp := dir.normalized() * (m * (4.0 + 10.0 * f) / (1.0 + m / 400.0))
				_activate(i, imp, c, who, "explosion")


# --- explosives ---------------------------------------------------------------------------------

func _light_fuse(i: int, body: WorldProp, who: Node) -> void:
	for fz: Array in _fuses:
		if (i >= 0 and int(fz[1]) == i) or (body != null and fz[2] == body):
			return
	if body != null:
		body.explosive = false      # never twice
	_fuses.append([_now + randf_range(0.18, 0.42), i, body, who])
	var p := body.global_position if body != null and is_instance_valid(body) else _i_xf[i].origin
	Fx.sparks(p + Vector3.UP * 0.6, Vector3.UP, 0.5)
	Fx.smoke_puff(p + Vector3.UP * 0.8, "black", 0.6)


func _update_fuses() -> void:
	for k in range(_fuses.size() - 1, -1, -1):
		var fz: Array = _fuses[k]
		if _now < float(fz[0]):
			continue
		_fuses.remove_at(k)
		var i := int(fz[1])
		var bv: Variant = fz[2]
		var body: WorldProp = bv as WorldProp if bv != null and is_instance_valid(bv) else null
		var who := _valid_node(fz[3])
		var id := ""
		var p := Vector3.INF
		if body != null and body.visible:
			p = body.global_position
			id = body.prop_id
			if body.role == "spawned":
				_spawned.erase(body)
				body.queue_free()
			else:
				_retire(body, true)
		elif i >= 0 and i < _i_type.size():
			if _i_state[i] == St.IDLE:
				p = _i_xf[i].origin
				id = String(_types[_i_type[i]]["id"])
				_set_visual(i, false)
				_set_collider(i, false)
				_i_state[i] = St.BROKEN
				_i_t[i] = _now
				if not _broken.has(i):
					_broken.append(i)
			elif get_instance_body(i) != null:
				var b2 := get_instance_body(i)
				p = b2.global_position
				id = b2.prop_id
				_retire(b2, true)
		if p == Vector3.INF:
			continue
		var big := id == "barrel_explosive"
		Fx.explosion(p + Vector3.UP * 0.45, 5.5 if big else 3.8, 170.0 if big else 110.0, who, {"fire": big})


## Spawned explosive WorldProps also chain: called through _on_world_prop_damage.


# --- hydrant water jets -------------------------------------------------------------------------

func _update_jets() -> void:
	for k in range(_jets.size() - 1, -1, -1):
		var j: Array = _jets[k]
		if _now > float(j[0]):
			_jets.remove_at(k)
			continue
		if _now < float(j[2]):
			continue
		j[2] = _now + 0.14
		var p: Vector3 = j[1]
		Fx.splash(p + Vector3(randf_range(-0.1, 0.1), 0.0, randf_range(-0.1, 0.1)), randf_range(0.9, 1.25))
		if randf() < 0.35:
			Fx.smoke_puff(p + Vector3.UP * randf_range(1.2, 2.2), "steam", 0.8)


func _on_world_prop_contact(body: WorldProp, _other: Node) -> void:
	if body.role == "loose":
		return
	var snd := "impact_metal"
	match body.surface:
		"wood":
			snd = "impact_wood"
		"concrete":
			snd = "impact_concrete"
		"rubber", "foliage":
			snd = "impact_dirt"
	Audio.play_at(snd, body.global_position, -3.0, randf_range(0.8, 1.0), 40.0)
	Fx.dust(body.global_position, 0.8)


# --- traffic signals ----------------------------------------------------------------------------

func _update_signals(force: bool) -> void:
	if roads == null:
		return
	for h: Dictionary in _heads:
		var s := int(roads.call("get_signal_state", int(h["lane"])))
		if s == int(h["state"]) and not force:
			continue
		h["state"] = s
		var inst := int(h["inst"])
		var shown := _i_state[inst] == St.IDLE
		# lens index 0 red, 1 yellow, 2 green
		h["lit"] = s if shown else -1
		for c in 3:
			var on := shown and ((c == 0 and s == 2) or (c == 1 and s == 1) or (c == 2 and s == 0))
			_set_custom(h["lens"][c], 1.0 if on else 0.0)
	for h: Dictionary in _peds:
		var s := int(roads.call("get_signal_state", int(h["lane"])))
		var walk := 1 if s == 2 else 0
		if walk == int(h["state"]) and not force:
			continue
		h["state"] = walk
		_set_custom(h["lens"][0], 0.0 if walk == 1 else 1.0)
		_set_custom(h["lens"][1], 1.0 if walk == 1 else 0.0)


func _set_custom(bs: PackedInt32Array, v: float) -> void:
	if bs.is_empty():
		return
	var b: Dictionary = _buckets[bs[0]]
	var mm: MultiMesh = b.get("mm")
	if mm != null:
		mm.set_instance_custom_data(bs[1], Color(v, 0.0, 0.0, 0.0))


## Lens material per colour (shared by every head).
var _lens_mats := {}


func lens_material(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if _lens_mats.has(key):
		return _lens_mats[key]
	var m := ShaderMaterial.new()
	m.shader = LENS_SHADER
	m.set_shader_parameter(&"lens_color", color)
	_lens_mats[key] = m
	return m


# --- animated set pieces ------------------------------------------------------------------------

func _update_animated(dt: float) -> void:
	var cam := _camera()
	var cp := cam.global_position if cam != null else Vector3.ZERO
	var wind := Vector3(1, 0, 0)
	var ws := 0.3
	if Weather != null and Weather.has_method("get_wind_vector"):
		var wv: Vector3 = Weather.call("get_wind_vector")
		if wv.length() > 0.01:
			wind = wv.normalized()
			ws = wv.length()
	for a: Dictionary in _animated:
		var n: Node3D = a["node"]
		if not is_instance_valid(n):
			continue
		if cam != null and n.global_position.distance_to(cp) > 300.0:
			continue
		var base: Transform3D = a["base"]
		match String(a["kind"]):
			"spin":
				a["phase"] = fposmod(float(a["phase"]) + dt * 1.6, TAU)
				n.transform = Transform3D(base.basis.rotated(Vector3.UP, float(a["phase"])), base.origin)
			"beacon":
				a["phase"] = fposmod(float(a["phase"]) + dt * 3.2, TAU)
				n.transform = Transform3D(base.basis.rotated(Vector3.UP, float(a["phase"])), base.origin)
			"wind":
				# the sock points downwind (-Z of the part); world yaw of the wind, relative to the root
				var root: Node3D = a["root"]
				var local_dir := root.global_basis.inverse() * wind
				var yaw := atan2(-local_dir.x, -local_dir.z)
				a["phase"] = float(a["phase"]) + dt * (2.0 + ws * 6.0)
				yaw += sin(float(a["phase"])) * 0.12 * (1.0 - clampf(ws, 0.0, 1.0) * 0.5)
				var droop := (1.0 - clampf(ws * 1.4, 0.0, 1.0)) * 0.6
				n.transform = Transform3D(base.basis.rotated(Vector3.RIGHT, -droop).rotated(Vector3.UP, yaw), base.origin)
