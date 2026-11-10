class_name Scatter
extends RefCounted
## Batches many static instances of the same asset (trees, bushes, rocks, grass, clutter)
## into MultiMeshInstance3D nodes, grouped by 100 m sector so culling and visibility ranges
## stay effective. Trunk / rock colliders go into one shared StaticBody3D.

const SECTOR := 100.0

var _items: Dictionary = {}      # rel -> Array[Transform3D]
var _colliders: Array = []       # [Shape3D, Transform3D]
var _ranges: Dictionary = {}     # rel -> visibility range end
var count := 0

func add(rel: String, xf: Transform3D, vis_range := 0.0) -> void:
	if not _items.has(rel):
		_items[rel] = []
	(_items[rel] as Array).append(xf)
	if vis_range > 0.0:
		_ranges[rel] = vis_range
	count += 1

## Convenience for manifest-driven props: adds the visual and (optionally) its collider.
func add_prop(id: String, pos: Vector3, yaw := 0.0, scale := 1.0, with_collider := true, vis_range := 0.0) -> bool:
	var e := PropFactory.entry(id)
	var rel := String(e.get("glb", "nature/" + id))
	if not Assets.has_model(rel):
		rel = "props/" + id
		if not Assets.has_model(rel):
			return false
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos)
	add(rel, xf, vis_range)
	if with_collider:
		var col: Variant = e.get("col", "none")
		if typeof(col) == TYPE_DICTIONARY:
			var cd: Dictionary = col
			var center := PropFactory.b2g(cd.get("center", [0, 0, 0])) * scale
			if String(cd.get("shape", "box")) == "cyl":
				var cyl := CylinderShape3D.new()
				cyl.radius = maxf(float(cd.get("r", 0.25)) * scale, 0.1)
				cyl.height = float(cd.get("h", 2.0)) * scale
				_colliders.append([cyl, Transform3D(Basis(Vector3.UP, yaw), pos + Basis(Vector3.UP, yaw) * center)])
			else:
				var bs := BoxShape3D.new()
				bs.size = PropFactory.b2g_size(cd.get("size", [1, 1, 1])) * scale
				_colliders.append([bs, Transform3D(Basis(Vector3.UP, yaw), pos + Basis(Vector3.UP, yaw) * center)])
		elif String(col) == "bbox":
			var sz := PropFactory.b2g_size(e.get("size", [1, 1, 1])) * scale
			var bs2 := BoxShape3D.new()
			bs2.size = sz
			_colliders.append([bs2, Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, sz.y * 0.5, 0))])
	return true

func add_collider(shape: Shape3D, xf: Transform3D) -> void:
	_colliders.append([shape, xf])

func commit(parent: Node3D, group_name := "Scatter") -> void:
	var root := Node3D.new()
	root.name = group_name
	parent.add_child(root)
	for rel in _items.keys():
		var parts: Array = Assets.mesh_parts(rel)
		if parts.is_empty():
			continue
		var by_sector := {}
		for xf in _items[rel]:
			var o: Vector3 = (xf as Transform3D).origin
			var key := Vector2i(int(floor(o.x / SECTOR)), int(floor(o.z / SECTOR)))
			if not by_sector.has(key):
				by_sector[key] = []
			(by_sector[key] as Array).append(xf)
		for key in by_sector.keys():
			var list: Array = by_sector[key]
			var center := Vector3((float(key.x) + 0.5) * SECTOR, 0.0, (float(key.y) + 0.5) * SECTOR)
			for p in parts:
				var pname: String = p[2]
				if pname.ends_with("__col") or pname.ends_with("__lod1"):
					continue
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = p[0]
				mm.instance_count = list.size()
				var local: Transform3D = p[1]
				for i in list.size():
					var t: Transform3D = (list[i] as Transform3D) * local
					t.origin -= center
					mm.set_instance_transform(i, t)
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "%s_%d_%d" % [rel.get_file(), key.x, key.y]
				mmi.multimesh = mm
				mmi.position = center
				var r := float(_ranges.get(rel, 0.0))
				if r > 0.0:
					mmi.visibility_range_end = r + SECTOR * 0.7
				if r > 0.0 and r < 130.0:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(mmi)
	if not _colliders.is_empty():
		var body := StaticBody3D.new()
		body.name = "ScatterColliders"
		body.collision_layer = Phys.WORLD
		body.collision_mask = 0
		body.set_meta("surface", &"wood")
		for c in _colliders:
			var cs := CollisionShape3D.new()
			cs.shape = c[0]
			cs.transform = c[1]
			body.add_child(cs)
		root.add_child(body)
	_items.clear()
	_colliders.clear()
