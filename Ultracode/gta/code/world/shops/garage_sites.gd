extends RefCounted
## Landmark marker resolver for the garage system (Economy B). Static helpers, no state but a
## manifest cache. Order of truth:
##   1. the city builder (`Game.get_system("city")`, ARCHITECTURE_WAVE2 W2.4): the real building,
##   2. the reserved World lot of the landmark + the marker table of the landmark manifests
##      (`models/buildings/manifest*.json`, Godot local coordinates) - same numbers the city
##      builder uses, so positions agree with the GLB even before the city exists,
##   3. a named World location (`Game.get_location`).
## Loaded by path (no class_name):  const Sites := preload("res://gta/code/world/shops/garage_sites.gd")

const MANIFEST_DIR := "res://gta/generated/models/buildings/"

static var _markers: Dictionary = {}        ## building id / landmark -> {"markers": {}, "yaw": {}}
static var _loaded: bool = false


static func clear_cache() -> void:
	_markers.clear()
	_loaded = false


static func _load_manifests() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(MANIFEST_DIR)
	if dir == null:
		return
	for f: String in dir.get_files():
		if not (f.begins_with("manifest") and f.ends_with(".json")):
			continue
		var txt := FileAccess.get_file_as_string(MANIFEST_DIR + f)
		var parsed: Variant = JSON.parse_string(txt)
		if not (parsed is Dictionary):
			continue
		for b: Variant in (parsed as Dictionary).get("buildings", []):
			if not (b is Dictionary):
				continue
			var bd := b as Dictionary
			if not bd.has("markers"):
				continue
			var entry := {"markers": bd.get("markers", {}), "yaw": bd.get("marker_yaw", {})}
			_markers[str(bd.get("id", ""))] = entry
			var lm := str(bd.get("landmark", ""))
			if lm != "" and not _markers.has(lm):
				_markers[lm] = entry


static func _city() -> Node:
	var c := Game.get_system("city")
	if c != null and c.has_method("get_landmark_marker"):
		return c
	return null


## True if the city builder actually placed the landmark building.
static func city_has_landmark(landmark: String) -> bool:
	var c := _city()
	return c != null and c.has_method("has_landmark") and bool(c.call("has_landmark", landmark))


## The landmark building node from the city builder (null without a city).
static func landmark_node(landmark: String) -> Node3D:
	var c := _city()
	if c == null or not c.has_method("get_landmark_node"):
		return null
	var n: Variant = c.call("get_landmark_node", landmark)
	if n != null and is_instance_valid(n) and n is Node3D:
		return n
	return null


## World transform of the landmark building origin: {"ok", "xform", "source"}.
static func landmark_transform(landmark: String) -> Dictionary:
	var c := _city()
	if c != null and city_has_landmark(landmark) and c.has_method("get_landmark_transform"):
		return {"ok": true, "xform": c.call("get_landmark_transform", landmark), "source": "city"}
	var w := Game.world
	if w != null and w.has_method("get_landmark_lot"):
		var lot: Variant = w.call("get_landmark_lot", landmark)
		if lot is Dictionary and not (lot as Dictionary).is_empty() and (lot as Dictionary).has("center"):
			var center: Vector3 = (lot as Dictionary)["center"]
			var yaw := float((lot as Dictionary).get("yaw", 0.0))
			return {"ok": true, "xform": Transform3D(Basis(Vector3.UP, yaw), center), "source": "lot"}
	return {"ok": false, "xform": Transform3D.IDENTITY, "source": ""}


## Local marker of the landmark manifest as a Transform3D (yaw from marker_yaw). {} if unknown.
static func manifest_marker(landmark: String, marker: String) -> Dictionary:
	_load_manifests()
	var e: Variant = _markers.get(landmark, null)
	if not (e is Dictionary):
		return {}
	var mk: Dictionary = (e as Dictionary)["markers"]
	if not mk.has(marker):
		return {}
	var p: Variant = mk[marker]
	if not (p is Array) or (p as Array).size() < 3:
		return {}
	var yaw := float(((e as Dictionary)["yaw"] as Dictionary).get(marker, 0.0))
	return {"xform": Transform3D(Basis(Vector3.UP, yaw), Vector3(float(p[0]), float(p[1]), float(p[2])))}


## World transform of a landmark marker: {"ok", "xform", "source"} (source "city" / "lot" /
## "location" / ""). `fallback_location` is used when neither the city nor the lot knows it.
static func marker(landmark: String, marker_name: String, fallback_location: String = "") -> Dictionary:
	var c := _city()
	if c != null and c.has_method("has_landmark_marker") and bool(c.call("has_landmark_marker", landmark, marker_name)):
		var xf: Variant = c.call("get_landmark_marker", landmark, marker_name)
		if xf is Transform3D:
			return {"ok": true, "xform": _level(xf), "source": "city"}
	var local := manifest_marker(landmark, marker_name)
	if not local.is_empty():
		var b := landmark_transform(landmark)
		if bool(b["ok"]):
			var world_xf: Transform3D = (b["xform"] as Transform3D) * (local["xform"] as Transform3D)
			return {"ok": true, "xform": _level(world_xf), "source": str(b["source"])}
	if fallback_location != "" and has_location(fallback_location):
		return {"ok": true, "xform": _level(Game.get_location(fallback_location)), "source": "location"}
	return {"ok": false, "xform": Transform3D.IDENTITY, "source": ""}


static func has_location(location_name: String) -> bool:
	var w := Game.world
	if w == null:
		return false
	if w.has_method("has_location"):
		return bool(w.call("has_location", location_name))
	return w.has_method("get_location")


## Keeps only the yaw of a transform (markers stand upright).
static func _level(xf: Transform3D) -> Transform3D:
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		return Transform3D(Basis.IDENTITY, xf.origin)
	var yaw := atan2(-fwd.x, -fwd.z)
	return Transform3D(Basis(Vector3.UP, yaw), xf.origin)


static func yaw_of(xf: Transform3D) -> float:
	var fwd := -xf.basis.z
	return atan2(-fwd.x, -fwd.z)


## Spawn points of a World kind sorted by distance to `near` (within max_dist).
static func spawn_points_near(kind: String, near: Vector3, max_dist: float = 1.0e9) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var w := Game.world
	if w == null or not w.has_method("get_spawn_points"):
		return out
	var pts: Variant = w.call("get_spawn_points", kind)
	if not (pts is Array):
		return out
	var keyed: Array = []
	for p: Variant in pts:
		if p is Transform3D:
			var d := (p as Transform3D).origin.distance_to(near)
			if d <= max_dist:
				keyed.append([d, p])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for k: Array in keyed:
		out.append(k[1])
	return out


## Free spawn transforms around `center` (rings `step` m apart up to `max_r`): ground (or water)
## at about the centre's height and a box of half extents `half` (lifted 0.3 m) touching nothing
## on WORLD | VEHICLE | PROP. Used when every authored spawn point is taken (parked aircraft ...).
static func free_spots(space: PhysicsDirectSpaceState3D, center: Vector3, yaw: float, half: Vector3,
		max_r: float, step: float, water: bool = false, max_count: int = 6) -> Array:
	var out: Array = []
	if space == null:
		return out
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = half * 2.0
	q.shape = box
	q.collision_mask = Layers.WORLD | Layers.VEHICLE | Layers.PROP
	q.collide_with_areas = false
	var basis := Basis(Vector3.UP, yaw)
	var rings := int(max_r / step)
	for ring in rings + 1:
		var n := 1 if ring == 0 else ring * 8
		for k in n:
			var a := TAU * float(k) / float(n)
			var p := center + Vector3(cos(a), 0.0, sin(a)) * (float(ring) * step)
			var y := 0.0
			if water:
				var w := Game.world
				if w == null or not w.has_method("get_water_depth") or float(w.call("get_water_depth", p.x, p.z)) < 1.4:
					continue
				y = Game.WATER_LEVEL
			else:
				if Game.is_in_water(Vector3(p.x, Game.WATER_LEVEL - 0.3, p.z)):
					continue
				y = Game.ground_height(p.x, p.z)
				if absf(y - center.y) > 1.2:
					continue
			q.transform = Transform3D(basis, Vector3(p.x, y + half.y + 0.3, p.z))
			if space.intersect_shape(q, 1).is_empty():
				out.append(Transform3D(basis, Vector3(p.x, y, p.z)))
				if out.size() >= max_count:
					return out
	return out


## True if no vehicle (other than `ignore`) has its centre within `radius` of `pos`.
static func is_spot_clear(pos: Vector3, radius: float, ignore: Node = null) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return true
	for n: Node in tree.get_nodes_in_group("vehicle"):
		if n == ignore or not (n is Node3D) or not is_instance_valid(n) or not (n as Node3D).is_inside_tree():
			continue
		var p := (n as Node3D).global_position
		if Vector2(p.x - pos.x, p.z - pos.z).length() < radius and absf(p.y - pos.y) < 6.0:
			return false
	return true
