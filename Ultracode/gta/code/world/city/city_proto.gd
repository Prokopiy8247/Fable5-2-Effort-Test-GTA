extends RefCounted
## City builder helper (module-private, no class_name): one prototype per building type.
## The GLB is loaded once; its meshes, collision shapes and occluder boxes are shared resources that
## every placed copy references (no per-instance copies, no per-instance material overrides).
##
## Part kinds (by node name, see docs/BUILDING_KIT.md / LANDMARKS.md):
##   shell (Building), glass (Building_Glass), detail (Building_Detail), neon (Building_Neon),
##   interior (Building_Interior), door (MeshInstance3D Door_*), pump (Pump_*), extra (anything else),
##   helper (Col_* / *Collision* meshes: never shown).

const NO_HOOK_GROUP := &"env_no_night_hook"

var id := ""
var def: Dictionary = {}
var ok := false
var error := ""
## {name, kind, mesh: Mesh, xform: Transform3D (relative to the asset root), aabb: AABB (mesh local)}
var parts: Array[Dictionary] = []
## marker name -> Transform3D in building-local space (manifest values win over GLB empties)
var markers: Dictionary = {}
## [Shape3D, Transform3D] pairs of the building body
var shapes: Array = []
## [name, Shape3D, Transform3D] small colliders of separate objects (gas pumps)
var object_shapes: Array = []
## [Occluder3D, Transform3D] pairs (only big "box" buildings)
var occluders: Array = []
var surface := "concrete"
var swapped := 0
var tris := 0
var walk_in := false

## visibility_range_end per kind (0 = always visible) and shadow casting per kind
var vis_end: Dictionary = {}
var shadows: Dictionary = {}
## Ground-floor room light of a walk-in building: {"pos": Vector3 (building-local), "range": float};
## empty when the building has no interior. Derived from its warm ceiling lamps (P_LampWarm).
var interior_light: Dictionary = {}
## Collision ramp under a stair flight (manifest "stair"): {"from": Vector3, "to": Vector3, "width"} building-local.
var stair_ramp: Dictionary = {}


func build(d: Dictionary, packed: PackedScene, env: Node) -> bool:
	def = d
	id = String(d["id"])
	if packed == null:
		error = "GLB failed to load: " + String(d["path"])
		return false
	var inst := packed.instantiate()
	if inst == null:
		error = "GLB failed to instantiate"
		return false
	var root: Node = inst.find_child(id, true, false)
	if root == null:
		root = inst
	_walk(root, Transform3D.IDENTITY)
	inst.free()
	if parts.is_empty():
		error = "no meshes in " + String(d["path"])
		return false
	_manifest_markers()
	_find_interior_light()
	_split_interior_glass()
	_swap_night_materials(env)
	_build_shapes()
	_build_occluders()
	_lod_rules()
	walk_in = String(d["collision"]) == "trimesh" and _has_use_marker()
	if (d["tags"] as Array).has("pier"):
		surface = "wood"
	ok = true
	return true


func _walk(node: Node, acc: Transform3D) -> void:
	for c in node.get_children():
		var n3 := c as Node3D
		if n3 == null:
			continue
		var t := acc * n3.transform
		var mi := n3 as MeshInstance3D
		if mi != null:
			if mi.mesh != null:
				var kind := _kind(String(mi.name))
				parts.append({"name": String(mi.name), "kind": kind, "mesh": mi.mesh, "xform": t, "aabb": mi.mesh.get_aabb()})
				if kind != "helper":
					tris += _tri_count(mi.mesh)
		else:
			markers[String(n3.name)] = t
		_walk(c, t)


static func _tri_count(mesh: Mesh) -> int:
	var am := mesh as ArrayMesh
	if am == null:
		return 0
	var n := 0
	for s in am.get_surface_count():
		var idx := am.surface_get_array_index_len(s)
		n += (idx if idx > 0 else am.surface_get_array_len(s)) / 3
	return n


static func _kind(n: String) -> String:
	match n:
		"Building":
			return "shell"
		"Building_Glass":
			return "glass"
		"Building_Detail":
			return "detail"
		"Building_Neon":
			return "neon"
		"Building_Interior":
			return "interior"
	if n.begins_with("Col_") or n.contains("Collision") or n.begins_with("Helper"):
		return "helper"
	if n.begins_with("Door_"):
		return "door"
	if n.begins_with("Pump_"):
		return "pump"
	return "extra"


## Manifest "markers" ({name: [x, y, z]}, Godot building-local) + "marker_yaw" are the documented
## source; GLB empties fill in anything the manifest does not list. Adds "Entrance" (on the doorway,
## -Z pointing into the building) and "Helipad" (roof pad, hospital) when the manifest has them.
func _manifest_markers() -> void:
	var mk: Variant = def.get("markers", {})
	var yaws: Variant = def.get("marker_yaw", {})
	if mk is Dictionary:
		for k: String in (mk as Dictionary):
			var v: Variant = (mk as Dictionary)[k]
			if not (v is Array) or (v as Array).size() < 3:
				continue
			var yaw := 0.0
			if yaws is Dictionary and (yaws as Dictionary).has(k):
				yaw = float((yaws as Dictionary)[k])
			elif markers.has(k):
				yaw = (markers[k] as Transform3D).basis.get_euler().y
			markers[k] = Transform3D(Basis(Vector3.UP, yaw), Vector3(float(v[0]), float(v[1]), float(v[2])))
	var ent: Variant = def.get("entrance")
	if ent is Array and (ent as Array).size() >= 2 and not markers.has("Entrance"):
		var e := Vector2(float(ent[0]), float(ent[1]))
		var fp: Vector2 = def["fp"]
		var co: Vector2 = def["co"]
		var rel := e - co
		# which footprint edge is the doorway on? -Z of the marker points into the building
		var dx := fp.x * 0.5 - absf(rel.x)
		var dz := fp.y * 0.5 - absf(rel.y)
		var inward := Vector3(0, 0, 1) if rel.y < 0.0 else Vector3(0, 0, -1)
		if dx < dz:
			inward = Vector3(1, 0, 0) if rel.x < 0.0 else Vector3(-1, 0, 0)
		if minf(dx, dz) > 1.5:
			# a door well inside the footprint (gas-station kiosk behind its forecourt): it faces the
			# street side (-Z) like every front, so walking in means walking +Z
			inward = Vector3(0, 0, 1)
		var yaw := atan2(-inward.x, -inward.z)
		markers["Entrance"] = Transform3D(Basis(Vector3.UP, yaw), Vector3(e.x, 0.0, e.y))
	var hp: Variant = def.get("helipad")
	if hp is Array and (hp as Array).size() >= 3:
		markers["Helipad"] = Transform3D(Basis.IDENTITY, Vector3(float(hp[0]), float(hp[1]), float(hp[2])))


## Centre of the ground-floor ceiling lamps (P_LampWarm / M_LampGlow surfaces between 1.8 m and 6 m)
## of buildings that have a Building_Interior part. Must run before the night-material swap.
func _find_interior_light() -> void:
	var has_interior := false
	for p: Dictionary in parts:
		if String(p["kind"]) == "interior":
			has_interior = true
	if not has_interior:
		return
	var fp: Vector2 = def["fp"]
	var co: Vector2 = def["co"]
	var box := AABB()
	var n := 0
	for p: Dictionary in parts:
		if not String(p["kind"]) in ["interior", "detail", "shell"]:
			continue
		var mesh: Mesh = p["mesh"]
		var t: Transform3D = p["xform"]
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m == null:
				continue
			var mn := String(m.resource_name)
			if not (mn.begins_with("P_LampWarm") or mn.begins_with("M_LampGlow")):
				continue
			var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var w := t * v
				if w.y < 1.8 or w.y > 6.0 or absf(w.x - co.x) > fp.x * 0.5 - 0.2 or absf(w.z - co.y) > fp.y * 0.5 - 0.2:
					continue
				if n == 0:
					box = AABB(w, Vector3.ZERO)
				else:
					box = box.expand(w)
				n += 1
	if n == 0:
		return
	var c := box.get_center()
	interior_light = {"pos": Vector3(c.x, maxf(box.position.y - 0.9, 1.9), c.z),
			"range": clampf(maxf(box.size.x, box.size.z) * 0.6 + 4.0, 6.0, 12.0)}


## Walk-in buildings (trimesh + Building_Interior): their window panes are double ("one pane faces out,
## one in", LANDMARKS.md). The lit-window shader is opaque, so from inside a shop the player looked at
## solid blue panels. The inward-facing M_Window triangles get a shared, lightly tinted transparent glass;
## the outward ones keep M_Window (-> lit-window hook, cull_back), whose back faces are culled, so from
## inside you see the street and from outside nothing changes (reflective by day, lit panes at night).
## Builds a NEW mesh for this type (the cached GLB mesh is not modified). Must run before the swap.
var glass_split := 0                     ## inward-facing window triangles made transparent
## Shared by every prototype of one city: the builder passes its instance in before build() (no static
## cache, so nothing outlives the city).
var glass_material: StandardMaterial3D


static func make_interior_glass_material() -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	g.resource_name = "City_InteriorGlass"
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.albedo_color = Color(0.62, 0.78, 0.88, 0.16)
	g.metallic = 0.0
	g.roughness = 0.06
	g.cull_mode = BaseMaterial3D.CULL_BACK
	return g


func interior_glass_material() -> StandardMaterial3D:
	if glass_material == null:
		glass_material = make_interior_glass_material()
	return glass_material


func _split_interior_glass() -> void:
	if String(def["collision"]) != "trimesh":
		return
	var has_interior := false
	for p: Dictionary in parts:
		if String(p["kind"]) == "interior":
			has_interior = true
	if not has_interior:
		return
	var co: Vector2 = def["co"]
	for i in parts.size():
		var p: Dictionary = parts[i]
		if String(p["kind"]) != "glass":
			continue
		var src := p["mesh"] as ArrayMesh
		if src == null:
			continue
		var t: Transform3D = p["xform"]
		var out := ArrayMesh.new()
		out.resource_name = String(src.resource_name) + "_split"
		var changed := false
		for s in src.get_surface_count():
			var mat := src.surface_get_material(s)
			var arrays := src.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
			var is_window := mat != null and String(mat.resource_name).begins_with("M_Window")
			if not is_window or not (normals is PackedVector3Array) or (normals as PackedVector3Array).size() != verts.size():
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				out.surface_set_material(out.get_surface_count() - 1, mat)
				continue
			var nrm: PackedVector3Array = normals
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				idx.resize(verts.size())
				for k in verts.size():
					idx[k] = k
			var inner := PackedInt32Array()
			var outer := PackedInt32Array()
			for k in range(0, idx.size() - 2, 3):
				var a := idx[k]
				var b := idx[k + 1]
				var c := idx[k + 2]
				var cen := t * ((verts[a] + verts[b] + verts[c]) / 3.0)
				var n := t.basis * (nrm[a] + nrm[b] + nrm[c])
				var to_mid := Vector2(co.x - cen.x, co.y - cen.z)
				if Vector2(n.x, n.z).dot(to_mid) > 0.0:
					inner.append_array([a, b, c])
				else:
					outer.append_array([a, b, c])
			if inner.is_empty():
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				out.surface_set_material(out.get_surface_count() - 1, mat)
				continue
			changed = true
			glass_split += inner.size() / 3
			if not outer.is_empty():
				var ao := arrays.duplicate()
				ao[Mesh.ARRAY_INDEX] = outer
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ao)
				out.surface_set_material(out.get_surface_count() - 1, mat)
			var ai := arrays.duplicate()
			ai[Mesh.ARRAY_INDEX] = inner
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ai)
			out.surface_set_material(out.get_surface_count() - 1, interior_glass_material())
		if changed:
			p["mesh"] = out


func _has_use_marker() -> bool:
	for k: String in markers:
		if k.begins_with("Use_"):
			return true
	return false


# ---------------------------------------------------------------------------------------------
# night materials: swapped ONCE on the shared mesh resources (never per instance)
# ---------------------------------------------------------------------------------------------

func _swap_night_materials(env: Node) -> void:
	if env == null or not is_instance_valid(env):
		return
	for p: Dictionary in parts:
		if String(p["kind"]) == "helper":
			continue
		var mesh: Mesh = p["mesh"]
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m == null:
				continue
			var hook := _hook_for(env, mesh, s, String(m.resource_name), m)
			if hook != null and hook != m:
				mesh.surface_set_material(s, hook)
				swapped += 1


static func _hook_for(env: Node, mesh: Mesh, s: int, n: String, src: Material) -> Material:
	if n.begins_with("M_Window"):
		var am := mesh as ArrayMesh
		var has_uv := am != null and (am.surface_get_format(s) & Mesh.ARRAY_FORMAT_TEX_UV) != 0
		if env.has_method("get_window_material_mode"):
			return env.call("get_window_material_mode", 1 if has_uv else 2) as Material
		if env.has_method("get_window_material"):
			return env.call("get_window_material") as Material
	elif n.begins_with("M_LampGlow") or n.begins_with("P_LampWarm"):
		if env.has_method("get_lamp_material"):
			return env.call("get_lamp_material") as Material
	elif n.begins_with("P_Neon"):
		if env.has_method("get_neon_material"):
			return env.call("get_neon_material", _source_color(src)) as Material
	return null


static func _source_color(src: Material) -> Color:
	var bm := src as BaseMaterial3D
	if bm == null:
		return Color(1.0, 0.3, 0.6)
	if bm.emission_enabled and bm.emission.get_luminance() > 0.02:
		return bm.emission
	return bm.albedo_color


# ---------------------------------------------------------------------------------------------
# collision (created once per building type, shared by every copy)
# ---------------------------------------------------------------------------------------------

func _build_shapes() -> void:
	if String(def["collision"]) == "trimesh":
		var names: Array = def.get("collision_nodes", ["Building"])
		var faces := PackedVector3Array()
		for p: Dictionary in parts:
			if not names.has(p["name"]):
				continue
			var f := (p["mesh"] as Mesh).get_faces()
			var t: Transform3D = p["xform"]
			if t != Transform3D.IDENTITY:
				for i in f.size():
					f[i] = t * f[i]
			faces.append_array(f)
		if not faces.is_empty():
			var sh := ConcavePolygonShape3D.new()
			sh.backface_collision = true
			sh.set_faces(faces)
			shapes.append([sh, Transform3D.IDENTITY])
		_build_stair_ramp()
	else:
		var boxes: Variant = def.get("collision_boxes", [])
		if boxes is Array and not (boxes as Array).is_empty():
			for b: Variant in boxes:
				if b is Array and (b as Array).size() >= 6:
					var sh := BoxShape3D.new()
					sh.size = Vector3(maxf(float(b[3]), 0.05), maxf(float(b[4]), 0.05), maxf(float(b[5]), 0.05))
					shapes.append([sh, Transform3D(Basis.IDENTITY, Vector3(float(b[0]), float(b[1]), float(b[2])))])
		if shapes.is_empty():
			var fp: Vector2 = def["fp"]
			var co: Vector2 = def["co"]
			var h: float = maxf(float(def["roof"]), 1.0)
			var sh := BoxShape3D.new()
			sh.size = Vector3(fp.x, h, fp.y)
			shapes.append([sh, Transform3D(Basis.IDENTITY, Vector3(co.x, h * 0.5, co.y))])
	# separate objects (gas pumps): a box each, from their mesh bounds
	for p: Dictionary in parts:
		if String(p["kind"]) != "pump":
			continue
		var ab: AABB = p["aabb"]
		var sh := BoxShape3D.new()
		sh.size = ab.size.max(Vector3(0.1, 0.1, 0.1))
		object_shapes.append([String(p["name"]), sh, (p["xform"] as Transform3D) * Transform3D(Basis.IDENTITY, ab.get_center())])


## Walkable ramp under a stair flight given by the manifest key "stair" {bottom: [x, y, z], top: [x, y, z],
## width} (safehouse: the treads to the mezzanine bedroom are Building_Detail = no collision, so Use_Bed
## was unreachable). The ramp's top surface runs STAIR_LIFT above the line bottom -> top (= through the
## middle of the 0.18 m risers) and is clipped to the floor and the landing heights, so the feet stay
## within half a riser of the visible treads. 29.6 deg on the safehouse: under the player's 46 deg.
const STAIR_LIFT := 0.09
const STAIR_THICK := 0.25


func _build_stair_ramp() -> void:
	var st: Variant = def.get("stair")
	if not (st is Dictionary):
		return
	var b: Variant = (st as Dictionary).get("bottom")
	var t: Variant = (st as Dictionary).get("top")
	if not (b is Array and t is Array and (b as Array).size() >= 3 and (t as Array).size() >= 3):
		return
	var p0 := Vector3(float(b[0]), float(b[1]), float(b[2]))
	var p1 := Vector3(float(t[0]), float(t[1]), float(t[2]))
	var width := float((st as Dictionary).get("width", 1.2))
	var flat := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z)
	var run := flat.length()
	var rise := p1.y - p0.y
	if run < 0.5 or rise < 0.3:
		return
	var dir := flat / run
	var slope := rise / run
	# surface line y(s) = p0.y + STAIR_LIFT + slope * s, clipped to [p0.y, p1.y]
	var s0 := -STAIR_LIFT / slope
	var s1 := (rise - STAIR_LIFT) / slope
	var a := p0 + dir * s0                                  # toe on the floor (y = p0.y)
	var c := p0 + dir * s1 + Vector3(0.0, rise, 0.0)        # meets the landing (y = p1.y)
	a.y = p0.y
	var along := c - a
	var length := along.length()
	var fwd := along / length                               # up the slope (box local +Z)
	var normal := (Vector3.UP - fwd * fwd.dot(Vector3.UP)).normalized()   # surface normal (box local +Y)
	var basis := Basis(normal.cross(fwd), normal, fwd)      # right-handed, orthonormal
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, STAIR_THICK, length)
	var centre := (a + c) * 0.5 - normal * (STAIR_THICK * 0.5)
	shapes.append([sh, Transform3D(basis, centre)])
	stair_ramp = {"from": a, "to": c, "width": width}


## Occluder boxes inside big solid ("box" collision) buildings, inset so they never poke out.
func _build_occluders() -> void:
	if String(def["collision"]) != "box":
		return
	for pair: Array in shapes:
		var bs := pair[0] as BoxShape3D
		if bs == null:
			continue
		var sz := bs.size
		if sz.x < 7.0 or sz.z < 7.0 or sz.y < 5.0:
			continue
		var occ := BoxOccluder3D.new()
		occ.size = Vector3(sz.x - 1.2, sz.y - 1.0, sz.z - 1.2)
		occluders.append([occ, pair[1]])


## Distance culling (GeometryInstance3D.visibility_range_end, 0 = always) and shadow casting per kind.
## Big towers are always visible, small buildings fade out far away, interiors only near the camera.
func _lod_rules() -> void:
	var h: float = def["h"]
	var fp: Vector2 = def["fp"]
	var big := h >= 18.0 or fp.x * fp.y >= 500.0
	var small := h < 9.0 and fp.x * fp.y < 160.0
	vis_end = {
		"shell": 0.0 if big else (520.0 if small else 900.0),
		"glass": 0.0 if big else (380.0 if small else 700.0),
		"detail": 160.0 if small else (230.0 if not big else 320.0),
		"neon": 420.0 if not big else 0.0,
		"interior": 55.0,
		"door": 140.0,
		"pump": 160.0,
		"extra": 200.0,
	}
	shadows = {"shell": true, "glass": false, "detail": h >= 30.0, "neon": false, "interior": false,
			"door": false, "pump": false, "extra": false}
