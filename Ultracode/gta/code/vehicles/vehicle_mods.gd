class_name VehicleMods
extends RefCounted
## Applies installed mods (Registry kind "vehicle_mods", see
## res://gta/resources/registries/vehicle_mods_registry.gd) to a vehicle:
##   * performance effects are accumulated into vehicle.mod_stats and picked up by the physics
##     (Car._refresh_tuning) - they change real forces, not just numbers on a screen,
##   * visual mods show the matching Blender-authored `Mod_*` part, swap the wheels for one of
##     the shared wheel GLBs, recolour rims / plate, tint the glass, change the paint finish
##     and the horn.
## `vehicle.mods` is a Dictionary slot -> mod id; a slot that is absent is stock.

const PERFORMANCE_SLOTS: Array[String] = ["engine", "brakes", "suspension", "transmission", "turbo", "armor", "tires"]
const VISUAL_SLOTS: Array[String] = ["spoiler", "bumper_f", "bumper_r", "hood", "skirts", "roof", "exhaust", "grille",
		"wheels", "wheel_color", "paint_finish", "tint", "lights", "plate", "horn"]
const SLOT_NAMES := {
	"engine": "Engine", "brakes": "Brakes", "suspension": "Suspension", "transmission": "Transmission",
	"turbo": "Turbo", "armor": "Armor", "tires": "Tires", "spoiler": "Spoiler", "bumper_f": "Front Bumper",
	"bumper_r": "Rear Bumper", "hood": "Hood", "skirts": "Side Skirts", "roof": "Roof", "exhaust": "Exhaust",
	"grille": "Grille", "wheels": "Wheels", "wheel_color": "Wheel Colour", "paint_finish": "Paint Finish",
	"tint": "Window Tint", "lights": "Headlights", "plate": "Plate", "horn": "Horn",
}
## Baseline of vehicle.mod_stats. Numbers multiply unless listed in ADDITIVE.
const DEFAULT_STATS := {
	"power": 1.0, "drive": 1.0, "top_speed": 1.0, "brake": 1.0, "grip": 1.0, "stiffness": 1.0,
	"anti_roll": 1.0, "shift_time": 1.0, "damage_taken": 1.0,
	"ride_drop": 0.0, "mass_add": 0.0, "downforce_add": 0.0,
	"bulletproof_tires": false,
}
const ADDITIVE: Array[String] = ["ride_drop", "mass_add", "downforce_add"]
const WHEEL_PART_DIR := "res://gta/generated/models/vehicles/parts/"
const MOD_WHEEL_NAME := "ModWheel"
## Which way the outer face of the shared wheel GLBs points in their own space (-1 = -X).
const PART_WHEEL_OUTER_X := -1.0

static var _wheel_scene_cache: Dictionary = {}


static func clear_static_caches() -> void:
	_wheel_scene_cache.clear()


static func all_slots() -> Array[String]:
	var out: Array[String] = []
	out.append_array(PERFORMANCE_SLOTS)
	out.append_array(VISUAL_SLOTS)
	return out


static func get_def(mod_id: String) -> Dictionary:
	var d: Variant = Registry.get_def("vehicle_mods", mod_id)
	if d is Dictionary:
		return d
	return {}


static func slot_name(slot: String) -> String:
	return str(SLOT_NAMES.get(slot, slot.capitalize()))


## True if this vehicle can install the mod (slot allowed by the spec and present on the model).
static func supports(vehicle: VehicleBase, def: Dictionary) -> bool:
	if def.is_empty() or vehicle.spec == null:
		return false
	var slot := str(def.get("slot", ""))
	if slot == "" or not vehicle.spec.allows_mod_slot(slot):
		return false
	var node := str(def.get("node", ""))
	if node != "" and not vehicle.has_part(node):
		return false
	match slot:
		"wheels":
			return vehicle.get_wheel_count() > 0 and ResourceLoader.exists(str(def.get("wheel_model", "")))
		"wheel_color":
			return vehicle.has_material("M_Rim")
		"tint":
			return vehicle.has_material("M_Glass")
		"plate":
			return vehicle.has_material("M_Plate")
		"lights":
			return vehicle.has_material("M_Headlight")
		"paint_finish":
			return vehicle.has_material("M_Paint_Primary")
		"horn":
			return true
	if PERFORMANCE_SLOTS.has(slot):
		return vehicle.get_wheel_count() > 0
	return node != ""


## slot -> Array of mod ids (cheapest first) that this vehicle can install.
static func options_for(vehicle: VehicleBase) -> Dictionary:
	var out := {}
	for def: Variant in Registry.all("vehicle_mods"):
		if not (def is Dictionary) or not supports(vehicle, def):
			continue
		var slot := str(def["slot"])
		if not out.has(slot):
			out[slot] = []
		(out[slot] as Array).append(def)
	for slot: String in out:
		var defs: Array = out[slot]
		# order by level, then price (plain integer keys: no callables needed)
		var keys: Array[int] = []
		var by_key := {}
		var n := 0
		for d: Dictionary in defs:
			var key := int(d.get("level", 0)) * 100000000 + clampi(int(d.get("price", 0)), 0, 999999) * 100 + n
			keys.append(key)
			by_key[key] = str(d["id"])
			n += 1
		keys.sort()
		var ids: Array = []
		for key: int in keys:
			ids.append(by_key[key])
		out[slot] = ids
	return out


## Drops unknown / unsupported entries and returns a clean slot -> id dictionary.
static func sanitize(vehicle: VehicleBase, mods: Dictionary) -> Dictionary:
	var out := {}
	for slot: Variant in mods:
		var id := str(mods[slot])
		if id == "":
			continue
		var def := get_def(id)
		if def.is_empty() or str(def.get("slot", "")) != str(slot):
			continue
		if supports(vehicle, def):
			out[str(slot)] = id
	return out


static func price_of(mods: Dictionary) -> int:
	var total := 0
	for slot: Variant in mods:
		total += int(get_def(str(mods[slot])).get("price", 0))
	return total


## Install one mod (replaces whatever is in its slot). Returns false if unsupported.
static func install(vehicle: VehicleBase, mod_id: String) -> bool:
	var def := get_def(mod_id)
	if not supports(vehicle, def):
		return false
	var m := vehicle.mods.duplicate()
	m[str(def["slot"])] = mod_id
	vehicle.apply_mods(m)
	return true


## Back to stock for one slot.
static func remove(vehicle: VehicleBase, slot: String) -> void:
	if vehicle.mods.has(slot):
		var m := vehicle.mods.duplicate()
		m.erase(slot)
		vehicle.apply_mods(m)


## Rebuild mod_stats and all visual state from vehicle.mods (called by VehicleBase.apply_mods).
static func apply(vehicle: VehicleBase) -> void:
	var stats := DEFAULT_STATS.duplicate()
	for part_name: String in vehicle._nodes:
		if part_name.begins_with("Mod_"):
			var n := vehicle.get_part(part_name)
			if n != null:
				n.visible = false
	var finish := ""
	var tint := 0.0
	var rim: Variant = null
	var plate: Variant = null
	var head: Variant = null
	var wheel_model := ""
	var horn_sound := ""
	var horn_pitch := 1.0
	for slot: String in vehicle.mods:
		var def := get_def(str(vehicle.mods[slot]))
		if def.is_empty():
			continue
		var fx: Dictionary = def.get("effects", {})
		for k: String in fx:
			if not stats.has(k):
				continue
			if stats[k] is bool:
				stats[k] = bool(fx[k])
			elif ADDITIVE.has(k):
				stats[k] = float(stats[k]) + float(fx[k])
			else:
				stats[k] = float(stats[k]) * float(fx[k])
		var node := str(def.get("node", ""))
		if node != "":
			var part := vehicle.get_part(node)
			if part != null and not vehicle.destroyed:
				part.visible = true
		match slot:
			"paint_finish":
				finish = str(def.get("finish", ""))
			"tint":
				tint = float(def.get("tint", 0.0))
			"wheel_color":
				rim = def.get("color", null)
			"plate":
				plate = def.get("color", null)
			"lights":
				head = def.get("color", null)
			"wheels":
				wheel_model = str(def.get("wheel_model", ""))
			"horn":
				horn_sound = str(def.get("horn_sound", ""))
				horn_pitch = float(def.get("horn_pitch", 1.0))
	vehicle.mod_stats = stats
	vehicle.paint_finish = finish
	_apply_color(vehicle, "M_Rim", rim)
	_apply_color(vehicle, "M_Plate", plate)
	_apply_tint(vehicle, tint)
	if vehicle.lights != null:
		vehicle.lights.set_head_color(head)
	_apply_wheels(vehicle, wheel_model)
	if vehicle.audio != null and (vehicle.audio.horn_sound != horn_sound or vehicle.audio.horn_pitch != horn_pitch):
		vehicle.audio.horn_sound = horn_sound
		vehicle.audio.horn_pitch = horn_pitch
		vehicle.audio.reset_horn()


static func _apply_color(vehicle: VehicleBase, mat_name: String, color: Variant) -> void:
	var orig := vehicle.get_original_material(mat_name) as BaseMaterial3D
	if orig == null:
		return
	if color == null and not vehicle._inst_mats.has(mat_name):
		return
	var m := vehicle.get_instance_material(mat_name) as BaseMaterial3D
	if m == null:
		return
	m.albedo_color = (color as Color) if color is Color else orig.albedo_color


static func _apply_tint(vehicle: VehicleBase, tint: float) -> void:
	var orig := vehicle.get_original_material("M_Glass") as BaseMaterial3D
	if orig == null:
		return
	if tint <= 0.0 and not vehicle._inst_mats.has("M_Glass"):
		return
	var m := vehicle.get_instance_material("M_Glass") as BaseMaterial3D
	if m == null:
		return
	var c := orig.albedo_color
	var dark := Color(c.r * 0.12, c.g * 0.14, c.b * 0.16)
	var out := Color(c.r, c.g, c.b).lerp(dark, clampf(tint, 0.0, 1.0))
	out.a = lerpf(c.a, 0.94, clampf(tint, 0.0, 1.0))
	m.albedo_color = out


static func _wheel_scene(path: String) -> PackedScene:
	if _wheel_scene_cache.has(path):
		return _wheel_scene_cache[path]
	var ps: PackedScene = null
	if path != "" and ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	_wheel_scene_cache[path] = ps
	return ps


static func _apply_wheels(vehicle: VehicleBase, model_path: String) -> void:
	var count := vehicle.get_wheel_count()
	if count == 0:
		return
	var current := str(vehicle.get_meta("mod_wheel_model", ""))
	if current == model_path:
		return
	vehicle.set_meta("mod_wheel_model", model_path)
	var scene := _wheel_scene(model_path)
	for i in count:
		var node := vehicle.get_wheel_node(i)
		if node == null or not is_instance_valid(node):
			continue
		var old := node.get_node_or_null(MOD_WHEEL_NAME)
		if old != null:
			vehicle._unindex_surfaces(old)
			node.remove_child(old)
			old.queue_free()
		_set_stock_wheel_visible(node, scene == null)
		if scene == null:
			continue
		var part := scene.instantiate() as Node3D
		if part == null:
			continue
		part.name = MOD_WHEEL_NAME
		node.add_child(part)
		var box := AABB()
		var first := true
		for c: Node in part.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			var t := Transform3D.IDENTITY
			var cur: Node = mi
			while cur != null and cur != part:
				if cur is Node3D:
					t = (cur as Node3D).transform * t
				cur = cur.get_parent()
			var a := t * mi.get_aabb()
			box = a if first else box.merge(a)
			first = false
		var part_r := maxf(maxf(box.size.y, box.size.z) * 0.5, 0.05)
		var s := vehicle.get_wheel_radius(i) / part_r
		var rest := vehicle.get_wheel_rest_basis(i)
		var body_x := (vehicle.xform_in_body(node).origin.x) if vehicle.is_ancestor_of(node) else 0.0
		var want_outer := -1.0 if body_x < 0.0 else 1.0
		var desired := Basis.IDENTITY if want_outer == PART_WHEEL_OUTER_X else Basis(Vector3.UP, PI)
		part.transform = Transform3D(rest.inverse() * desired.scaled(Vector3(s, s, s)), Vector3.ZERO)
		vehicle._index_surfaces(part)
	# re-apply per-instance materials (rim colour, burnt look) on the new meshes
	for mat_name: String in vehicle._inst_mats:
		vehicle.set_material_override(mat_name, vehicle._inst_mats[mat_name])


static func _set_stock_wheel_visible(wheel_node: Node3D, on: bool) -> void:
	var list: Array[Node] = [wheel_node]
	list.append_array(wheel_node.find_children("*", "VisualInstance3D", true, false))
	for c: Node in list:
		var vi := c as VisualInstance3D
		if vi == null:
			continue
		var in_mod := false
		var cur: Node = vi
		while cur != null and cur != wheel_node:
			if cur.name == MOD_WHEEL_NAME:
				in_mod = true
				break
			cur = cur.get_parent()
		if not in_mod:
			vi.layers = 1 if on else 0
