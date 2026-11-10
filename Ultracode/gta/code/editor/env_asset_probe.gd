extends SceneTree
## ENVIRONMENT headless tool: reports how imported GLBs meet the night-light hook contract
## (docs/ENVIRONMENT.md section 4): which surfaces are named M_Window / M_LampGlow / P_LampWarm /
## P_Neon*, whether the window surfaces carry the building-kit UV cells (one integer UV cell per
## pane) and where the "Light" markers of lamp props sit.
## Run:  tools\godot.ps1 -Mode script -Script res://gta/code/editor/env_asset_probe.gd
##       -UserArgs '--scenes=res://gta/generated/models/buildings/office_a.glb,res://...glb'
## Without --scenes it probes a default set of buildings and lamp / neon props.

const NightMaterials := preload("res://gta/code/world/env/env_night_materials.gd")

const DEFAULT_SCENES: Array[String] = [
	"res://gta/generated/models/buildings/office_a.glb",
	"res://gta/generated/models/buildings/office_b.glb",
	"res://gta/generated/models/buildings/apartment_a.glb",
	"res://gta/generated/models/buildings/storefront_d.glb",
	"res://gta/generated/models/buildings/house_a.glb",
	"res://gta/generated/models/buildings/warehouse_a.glb",
	"res://gta/generated/models/props/street_lamp_a.glb",
	"res://gta/generated/models/props/street_lamp_b.glb",
	"res://gta/generated/models/props/wall_lamp.glb",
	"res://gta/generated/models/props/neon_sign_a.glb",
	"res://gta/generated/models/props/billboard.glb",
]


func _initialize() -> void:
	var scenes: Array[String] = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scenes="):
			for s in a.substr(9).split(",", false):
				scenes.append(s.strip_edges())
	if scenes.is_empty():
		scenes = DEFAULT_SCENES
	var hooks := NightMaterials.new()
	var total_hooks := 0
	for path in scenes:
		if not ResourceLoader.exists(path):
			print("ENV_PROBE missing ", path)
			continue
		var ps := load(path) as PackedScene
		if ps == null:
			print("ENV_PROBE not a scene ", path)
			continue
		var root := ps.instantiate()
		print("ENV_PROBE ", path)
		_dump(root, hooks)
		var n := hooks.apply_to(root)
		total_hooks += n
		print("  apply_to -> ", n, " surfaces swapped")
		root.free()
	print("ENV_PROBE_DONE scenes=%d hooks=%d" % [scenes.size(), total_hooks])
	quit(0)


func _dump(root: Node, hooks: RefCounted) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node3D and (n.name == "Light" or String(n.name).begins_with("Light")) and not (n is MeshInstance3D):
			var xf := _to_root(n as Node3D, root)
			print("  marker ", n.name, " at (%.2f, %.2f, %.2f)" % [xf.origin.x, xf.origin.y, xf.origin.z])
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			var mname := mat.resource_name if mat != null else "<none>"
			var kind: String = hooks.call("hook_kind", mname)
			if kind == "":
				continue
			var line := "  %s surface %d %s -> %s" % [mi.name, s, mname, kind]
			var am := mi.mesh as ArrayMesh
			if am != null:
				var fmt := am.surface_get_format(s)
				var has_uv := (fmt & Mesh.ARRAY_FORMAT_TEX_UV) != 0
				line += " uv=%s" % str(has_uv)
				var arrays := am.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				line += " verts=%d" % verts.size()
				if has_uv:
					var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
					var lo := Vector2(INF, INF)
					var hi := Vector2(-INF, -INF)
					var cells := {}
					for uv in uvs:
						lo = lo.min(uv)
						hi = hi.max(uv)
					# Cell id of each triangle = floor of its UV centroid.
					var idx: Variant = arrays[Mesh.ARRAY_INDEX]
					if idx != null and (idx as PackedInt32Array).size() >= 3:
						var ia: PackedInt32Array = idx
						for t in range(0, ia.size() - 2, 3):
							var c := (uvs[ia[t]] + uvs[ia[t + 1]] + uvs[ia[t + 2]]) / 3.0
							cells[Vector2i(floori(c.x), floori(c.y))] = true
					line += " uv_range=(%.2f, %.2f)..(%.2f, %.2f) cells=%d" % [lo.x, lo.y, hi.x, hi.y, cells.size()]
			var bm := mat as BaseMaterial3D
			if bm != null:
				line += " albedo=%s emission=%s e=%.1f" % [bm.albedo_color.to_html(false),
						bm.emission.to_html(false) if bm.emission_enabled else "off", bm.emission_energy_multiplier]
			print(line)


func _to_root(n: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	if root is Node3D:
		xf = (root as Node3D).transform * xf
	return xf
