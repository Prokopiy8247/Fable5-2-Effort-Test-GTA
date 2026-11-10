class_name PropFactory
extends RefCounted
## Spawns Blender-authored props with physics according to the asset manifests
## (res://gta/resources/data/manifests/*.json written by the asset pipeline).

const MANIFEST_DIR := "res://gta/resources/data/manifests/"

static var manifest: Dictionary = {}
static var _loaded := false
static var lamps: Array = []          # Light3D nodes switched on at night
static var _shape_cache: Dictionary = {}
static var _aabb_cache: Dictionary = {}

static func load_manifests(force := false) -> void:
	if _loaded and not force:
		return
	_loaded = true
	manifest.clear()
	var dir := DirAccess.open(MANIFEST_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var fa := FileAccess.open(MANIFEST_DIR + f, FileAccess.READ)
		if fa == null:
			continue
		var data: Variant = JSON.parse_string(fa.get_as_text())
		if typeof(data) != TYPE_DICTIONARY:
			push_warning("PropFactory: bad manifest " + f)
			continue
		for a in (data as Dictionary).get("assets", []):
			if typeof(a) == TYPE_DICTIONARY and a.has("id"):
				manifest[String(a["id"])] = a

static func entry(id: String) -> Dictionary:
	load_manifests()
	return manifest.get(id, {})

static func exists(id: String) -> bool:
	var e := entry(id)
	return Assets.has_model(String(e.get("glb", "props/" + id)))

## Blender (x, y, z) -> Godot (x, z, -y)
static func b2g(v: Variant) -> Vector3:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[2]), -float(v[1]))
	return Vector3.ZERO

static func b2g_size(v: Variant) -> Vector3:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[2]), float(v[1]))
	return Vector3.ONE

## Node below `root` whose name ends with "__<part>" (asset part / marker lookup).
static func part(root: Node, part_name: String) -> Node3D:
	var suffix := "__" + part_name
	return _find_suffix(root, suffix)

static func _find_suffix(n: Node, suffix: String) -> Node3D:
	if n is Node3D and String(n.name).ends_with(suffix):
		return n
	for c in n.get_children():
		var r := _find_suffix(c, suffix)
		if r != null:
			return r
	return null

## All nodes whose part name starts with a prefix, e.g. "light" -> light, light_1, light_a...
static func parts_with_prefix(root: Node, prefix: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	_collect_prefix(root, "__" + prefix, out)
	return out

static func _collect_prefix(n: Node, needle: String, out: Array[Node3D]) -> void:
	if n is Node3D:
		var nm := String(n.name)
		var i := nm.rfind("__")
		if i >= 0 and nm.substr(i).begins_with(needle):
			out.append(n)
	for c in n.get_children():
		_collect_prefix(c, needle, out)

static func visual_aabb(root: Node3D) -> AABB:
	var have := false
	var box := AABB()
	for mi in Assets.find_meshes(root):
		if String(mi.name).ends_with("__col") or String(mi.name).ends_with("__lod1"):
			continue
		var xf := _rel(mi, root)
		var a := xf * mi.get_aabb()
		box = a if not have else box.merge(a)
		have = true
	return box

static func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

static func _shapes_for(id: String, e: Dictionary, visual: Node3D) -> Array:
	# returns [[Shape3D, Transform3D], ...] in the prop's local space
	var col: Variant = e.get("col", "bbox")
	var out: Array = []
	if typeof(col) == TYPE_DICTIONARY:
		var cd: Dictionary = col
		var center := b2g(cd.get("center", [0, 0, 0]))
		if String(cd.get("shape", "box")) == "cyl":
			var cyl := CylinderShape3D.new()
			cyl.radius = maxf(float(cd.get("r", 0.2)), 0.08)
			cyl.height = float(cd.get("h", 1.0))
			out.append([cyl, Transform3D(Basis.IDENTITY, center)])
		else:
			var bs := BoxShape3D.new()
			bs.size = b2g_size(cd.get("size", [1, 1, 1]))
			out.append([bs, Transform3D(Basis.IDENTITY, center)])
		return out
	var mode := String(col)
	if mode == "none":
		return out
	if mode == "mesh":
		var faces := PackedVector3Array()
		var col_part := part(visual, "col")
		var sources: Array[MeshInstance3D] = []
		if col_part is MeshInstance3D:
			sources.append(col_part)
		else:
			sources = Assets.find_meshes(visual)
		for mi in sources:
			if mi.mesh == null:
				continue
			var xf := _rel(mi, visual) if mi != visual else Transform3D.IDENTITY
			faces.append_array(xf * mi.mesh.get_faces())
		if not faces.is_empty():
			var cps := ConcavePolygonShape3D.new()
			cps.set_faces(faces)
			out.append([cps, Transform3D.IDENTITY])
		return out
	# bbox
	var box := visual_aabb(visual)
	if box.size.length() > 0.01:
		var bs2 := BoxShape3D.new()
		bs2.size = Vector3(maxf(box.size.x, 0.08), maxf(box.size.y, 0.08), maxf(box.size.z, 0.08))
		out.append([bs2, Transform3D(Basis.IDENTITY, box.get_center())])
	return out

## Spawn one prop. opts: static(bool), tint_a, tint_b, scale(float), no_light(bool), range(float)
static func spawn(parent: Node3D, id: String, pos: Vector3, yaw := 0.0, opts: Dictionary = {}) -> Node3D:
	var e := entry(id)
	var rel := String(e.get("glb", "props/" + id))
	if not Assets.has_model(rel):
		return null
	var visual := Assets.instance(rel)
	var col_part := part(visual, "col")
	if col_part != null:
		col_part.visible = false
	var lod_part := part(visual, "lod1")
	if lod_part != null:
		lod_part.visible = false
	var shapes := _shapes_for(id, e, visual)
	var dynamic: bool = bool(e.get("dynamic", false)) and not bool(opts.get("static", false)) and not shapes.is_empty()
	var root: Node3D
	if shapes.is_empty():
		root = Node3D.new()
	elif dynamic:
		var rb := Prop.new()
		rb.prop_id = id
		rb.mass = float(e.get("mass", 20.0))
		rb.explosive = id.contains("explosive") or id.begins_with("prop_gas_tank")
		rb.is_hydrant = id == "prop_hydrant"
		rb.wake_speed = 2.0 if rb.mass < 20.0 else (4.0 if rb.mass < 70.0 else 7.0)
		root = rb
	else:
		var sb := StaticBody3D.new()
		sb.collision_layer = Phys.WORLD
		sb.collision_mask = 0
		root = sb
	root.name = id
	root.set_meta("prop_id", id)
	for sh in shapes:
		var cs := CollisionShape3D.new()
		cs.shape = sh[0]
		cs.transform = sh[1]
		root.add_child(cs)
	root.add_child(visual)
	root.position = pos
	root.rotation.y = yaw
	if opts.has("scale"):
		visual.scale = Vector3.ONE * float(opts["scale"])
	var box := visual_aabb(visual)
	var vis_range := float(opts.get("range", clampf(box.size.length() * 28.0, 70.0, 420.0)))
	for mi in Assets.find_meshes(visual):
		mi.visibility_range_end = vis_range
		if opts.has("tint_a"):
			mi.set_instance_shader_parameter(&"tint_a", (opts["tint_a"] as Color).srgb_to_linear())
		if opts.has("tint_b"):
			mi.set_instance_shader_parameter(&"tint_b", (opts["tint_b"] as Color).srgb_to_linear())
	if not bool(opts.get("no_light", false)):
		for m in parts_with_prefix(visual, "light"):
			var sp := SpotLight3D.new()
			sp.light_color = Color(1.0, 0.86, 0.62)
			sp.light_energy = 3.2
			sp.spot_range = 17.0
			sp.spot_angle = 64.0
			sp.spot_attenuation = 0.8
			sp.shadow_enabled = false
			sp.distance_fade_enabled = true
			sp.distance_fade_begin = 75.0
			sp.distance_fade_length = 25.0
			sp.rotation_degrees = Vector3(-90, 0, 0)
			sp.visible = false
			m.add_child(sp)
			lamps.append(sp)
			if root is Prop:
				(root as Prop).light = sp
	parent.add_child(root)
	return root

## Switch every registered lamp (street lamps, park lamps, flood lights) for day/night.
static func set_lamps(on: bool) -> void:
	var alive: Array = []
	for l in lamps:
		if is_instance_valid(l):
			alive.append(l)
			(l as Light3D).visible = on and not bool((l as Light3D).get_meta("broken", false))
	lamps = alive
