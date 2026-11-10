extends SceneTree
## Headless inspection tool: prints the node tree of any imported scene (GLB / tscn), with
## types, local positions, mesh surface material names, skeleton bones and animation names.
## Run:  tools\godot.ps1 -Mode script -Script res://gta/code/editor/print_scene_tree.gd -UserArgs '--scene=res://gta/generated/models/vehicles/sedan.glb'
## Optional: --bones (list every bone), --depth=N


func _initialize() -> void:
	var path := ""
	var show_bones := false
	var max_depth := 12
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			path = a.substr(8)
		elif a == "--bones":
			show_bones = true
		elif a.begins_with("--depth="):
			max_depth = int(a.substr(8))
	if path == "" or not ResourceLoader.exists(path):
		print("TREE_ERROR: scene not found: ", path)
		quit(1)
		return
	var ps := load(path) as PackedScene
	if ps == null:
		print("TREE_ERROR: not a PackedScene: ", path)
		quit(1)
		return
	var root := ps.instantiate()
	print("TREE_OF ", path)
	_dump(root, 0, max_depth, show_bones)
	root.free()
	quit(0)


func _dump(n: Node, depth: int, max_depth: int, show_bones: bool) -> void:
	var line := "  ".repeat(depth) + n.name + " [" + n.get_class() + "]"
	if n is Node3D:
		var p := (n as Node3D).position
		line += " pos=(%.3f, %.3f, %.3f)" % [p.x, p.y, p.z]
		var r := (n as Node3D).rotation_degrees
		if r.length() > 0.01:
			line += " rot=(%.1f, %.1f, %.1f)" % [r.x, r.y, r.z]
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m := (n as MeshInstance3D).mesh
		var mats: PackedStringArray = []
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			mats.append(mat.resource_name if mat != null else "<none>")
		var aabb := m.get_aabb()
		line += " surfaces=%d mats=%s aabb_size=(%.2f, %.2f, %.2f)" % [m.get_surface_count(), str(mats), aabb.size.x, aabb.size.y, aabb.size.z]
	if n is Skeleton3D:
		var sk := n as Skeleton3D
		line += " bones=%d" % sk.get_bone_count()
		if show_bones:
			for b in sk.get_bone_count():
				var rest := sk.get_bone_global_rest(b)
				print("  ".repeat(depth + 1), "bone ", b, " ", sk.get_bone_name(b), " parent=", sk.get_bone_parent(b),
						" rest_origin=(%.3f, %.3f, %.3f)" % [rest.origin.x, rest.origin.y, rest.origin.z],
						" y_axis=(%.2f, %.2f, %.2f)" % [rest.basis.y.x, rest.basis.y.y, rest.basis.y.z])
	if n is AnimationPlayer:
		line += " anims=" + str((n as AnimationPlayer).get_animation_list())
	if not n.get_meta_list().is_empty():
		line += " meta=" + str(n.get_meta_list())
	print(line)
	if depth >= max_depth:
		return
	for c in n.get_children():
		_dump(c, depth + 1, max_depth, show_bones)
