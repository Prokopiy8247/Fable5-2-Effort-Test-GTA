extends SceneTree
# Dev helper: prints the node tree of imported GLB files.  godot --headless -s tools/dump.gd -- <rel> [depth]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var depth := 3
	for a in args:
		if a.is_valid_int():
			depth = int(a)
	for a in args:
		if a.is_valid_int():
			continue
		var s: Node = load("res://gta/generated/models/%s.glb" % a).instantiate()
		_dump(s, 0, depth)
		s.free()
	quit()


func _dump(n: Node, d: int, maxd: int) -> void:
	var extra := ""
	if n is MeshInstance3D:
		var names := []
		for i in n.mesh.get_surface_count():
			var m: Material = n.mesh.surface_get_material(i)
			names.append(m.resource_name if m else "-")
		extra = " surfaces=%s aabb=%s skin=%s" % [names, n.mesh.get_aabb().size, n.skin != null]
	if n is Skeleton3D:
		var bn := []
		for i in n.get_bone_count():
			bn.append(n.get_bone_name(i))
		extra = " bones=%s" % [bn]
	if n is Node3D:
		extra += " pos=%s" % [n.position.snapped(Vector3(0.01, 0.01, 0.01))]
	print("  ".repeat(d) + String(n.name) + " [" + n.get_class() + "]" + extra)
	if d < maxd:
		for c in n.get_children():
			_dump(c, d + 1, maxd)
