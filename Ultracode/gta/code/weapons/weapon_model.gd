class_name WeaponModel
extends Node3D
## Visual of one weapon: instances the Blender-authored GLB, exposes its markers, shows the
## attachment meshes that are installed, applies the finish tint and sits in the owner's hand.
##
## GLB contract (docs/ARCHITECTURE.md 8.3): origin at the right-hand grip, barrel along -Z in
## Godot (+Y in Blender), up +Y; children `Body`, markers `Muzzle`, `Eject`, `Grip_L`, optional
## `Mag`, hidden-by-default attachment meshes `Att_Suppressor`, `Att_Scope`, `Att_Flashlight`,
## `Att_Grip`, `Att_ExtMag`; the recolourable material is named `M_Weapon_Finish`.
## Optional extra markers of the weapon artist (docs/WEAPON_ASSETS.md): `Muzzle_Suppressed`
## (the muzzle while the suppressor is fitted) and `Flashlight` (lens centre of the weapon light).
##
## A missing GLB is not replaced by anything: the model node simply stays empty (has_model()
## is false) and the weapon keeps working logically.
##
## Hand attachment: see attach_to_holder() and docs/WEAPONS.md "Hold-offset tuning".

const HAND_BONE := "Hand_R"
## Script that owns the canonical grip (HumanoidAnimator.get_grip_transform); used when present.
const ANIMATOR_SCRIPT := "res://gta/code/characters/humanoid_animator.gd"
## Fallback when that script is missing: where the grip sits relative to the Hand_R bone origin
## (the wrist), in the weapon's own frame (x right, y up, -z barrel): 7.5 cm along the hand into
## the palm, 3 cm towards the palm side. Mirrors the animator's canonical grip.
const DEFAULT_GRIP_OFFSET := Vector3(-0.03, 0.0, -0.075)
## Used when the holder has no CharacterVisual (test dummies): model floats at the right hip.
const FALLBACK_OFFSET := Vector3(0.24, 1.25, -0.35)

## Global integration knobs (all weapons at once); per-weapon values live in the WeaponSpec.
static var global_hold_offset: Vector3 = Vector3.ZERO
static var global_hold_rotation: Vector3 = Vector3.ZERO      ## degrees
## Fallback orientation of the weapon in CHARACTER space while the skeleton is in its rest (T)
## pose: columns = weapon right, weapon up, weapon back. Same canonical grip as the animator:
## barrel along the right hand (+X), top of the weapon towards the thumb (-Z), right side towards
## the back of the hand (+Y). Derived from the bone's rest pose, so bone roll does not matter.
static var rest_basis: Basis = Basis(Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0))
static var _animator_script: Script = null
static var _animator_checked: bool = false

static var _scene_cache: Dictionary = {}       ## path -> PackedScene or null
static var _finish_cache: Dictionary = {}      ## "<material id>:<color html>" -> Material

var spec: WeaponSpec = null
var muzzle: Node3D = null
var eject: Node3D = null
var grip_l: Node3D = null
var light: SpotLight3D = null
var attached_to_hand: bool = false

var mag: Node3D = null                         ## the Mag mesh (hidden while Att_ExtMag is shown)

var _content: Node3D = null
var _muzzle_plain: Node3D = null               ## `Muzzle`
var _muzzle_suppressed: Node3D = null          ## `Muzzle_Suppressed` (tip of the suppressor) or null
var _light_marker: Node3D = null               ## `Flashlight` (lens centre) or null
var _attachment_nodes: Dictionary = {}         ## node name -> Node3D
var _ext_mag_shown: bool = false
var _mag_loaded: bool = true
var _finish_color: Color = Color(0, 0, 0, 0)
var _installed: Array = []


## Build a model for a spec (or weapon id). Returns a WeaponModel even when the GLB is missing.
static func create(spec_or_id: Variant, installed_attachments: Array = []) -> WeaponModel:
	var m := WeaponModel.new()
	m.build(WeaponSpec.resolve(spec_or_id), installed_attachments)
	return m


static func load_scene(path: String) -> PackedScene:
	if path == "":
		return null
	if _scene_cache.has(path):
		return _scene_cache[path]
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = load(path) as PackedScene
	_scene_cache[path] = scene
	return scene


## Forget cached scenes (after new GLBs were imported at runtime; tests).
static func clear_cache() -> void:
	_scene_cache.clear()


func build(p_spec: WeaponSpec, installed_attachments: Array = []) -> void:
	spec = p_spec
	name = "WeaponModel"
	if _content != null:
		_content.queue_free()
		_content = null
	_attachment_nodes.clear()
	muzzle = null
	eject = null
	grip_l = null
	light = null
	mag = null
	_muzzle_plain = null
	_muzzle_suppressed = null
	_light_marker = null
	if spec == null:
		return
	name = "Weapon_%s" % spec.id
	var scene := load_scene(spec.model_path)
	if scene != null:
		_content = scene.instantiate() as Node3D
	if _content != null:
		_content.name = "Model"
		add_child(_content)
		muzzle = _content.find_child("Muzzle", true, false) as Node3D
		eject = _content.find_child("Eject", true, false) as Node3D
		grip_l = _content.find_child("Grip_L", true, false) as Node3D
		mag = _content.find_child("Mag", true, false) as Node3D
		_muzzle_suppressed = _content.find_child("Muzzle_Suppressed", true, false) as Node3D
		_light_marker = _content.find_child("Flashlight", true, false) as Node3D
		for n in _content.find_children("*", "Node3D", true, false):
			var n3 := n as Node3D
			if n3.name.begins_with("Att_"):
				_attachment_nodes[str(n3.name)] = n3
				n3.visible = false
			elif n3.name.begins_with("Col_"):
				n3.visible = false
		for g in _content.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).visibility_range_end = 120.0
	# markers always exist so that FX and aiming code never has to null-check
	if muzzle == null:
		muzzle = _make_marker("Muzzle", Vector3(0.0, 0.05, -_fallback_length()))
	if eject == null:
		eject = _make_marker("Eject", Vector3(0.03, 0.06, -0.08))
	_muzzle_plain = muzzle
	set_attachments(installed_attachments)


func has_model() -> bool:
	return _content != null


func get_muzzle_position() -> Vector3:
	if muzzle != null and muzzle.is_inside_tree():
		return muzzle.global_position
	return global_position if is_inside_tree() else Vector3.ZERO


## Names of the attachment meshes this GLB offers ("Att_Suppressor", ...).
func get_attachment_node_names() -> Array:
	var out: Array = _attachment_nodes.keys()
	out.sort()
	return out


## Show the meshes of the installed attachments, hide the others, apply the finish.
func set_attachments(installed: Array) -> void:
	_installed = installed.duplicate()
	var wanted: Dictionary = {}
	var finish := Color(0, 0, 0, 0)
	var finish_metallic := -1.0
	var finish_roughness := -1.0
	var wants_light := false
	for att_id: Variant in installed:
		var def: Variant = Registry.get_def("attachments", str(att_id))
		if not (def is AttachmentSpec):
			continue
		var a := def as AttachmentSpec
		if a.node_name != "":
			wanted[a.node_name] = true
		if a.is_finish():
			finish = a.color
			finish_metallic = a.finish_metallic
			finish_roughness = a.finish_roughness
		if a.is_light:
			wants_light = true
	if spec != null:
		for builtin in spec.builtin_nodes:
			wanted[builtin] = true
	for node_name: String in _attachment_nodes:
		(_attachment_nodes[node_name] as Node3D).visible = wanted.has(node_name)
	# flash, tracers and the shot sound start at the tip of the suppressor while one is fitted
	var suppressor_shown := wanted.has("Att_Suppressor") and _attachment_nodes.has("Att_Suppressor")
	muzzle = _muzzle_suppressed if (suppressor_shown and _muzzle_suppressed != null) else _muzzle_plain
	# the extended magazine replaces the standard one
	_ext_mag_shown = wanted.has("Att_ExtMag") and _attachment_nodes.has("Att_ExtMag")
	_apply_mag_visibility()
	set_finish(finish, finish_metallic, finish_roughness)
	_ensure_light(wants_light)


## Tint every surface that uses M_Weapon_Finish. Alpha 0 restores the factory colour.
func set_finish(color: Color, metallic: float = -1.0, roughness: float = -1.0) -> void:
	_finish_color = color
	if _content == null:
		return
	for n in _content.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(s)
			if base == null or not _is_finish_material(base):
				continue
			if color.a <= 0.0:
				mi.set_surface_override_material(s, null)
			else:
				mi.set_surface_override_material(s, _tinted(base, color, metallic, roughness))


func get_finish() -> Color:
	return _finish_color


## Show / hide the Mag mesh (e.g. the rocket sitting in the launcher while it is loaded).
func set_mag_loaded(loaded: bool) -> void:
	_mag_loaded = loaded
	_apply_mag_visibility()


## World position for the support (left) hand, or Vector3.INF when the model has no Grip_L.
func get_support_hand_position() -> Vector3:
	if grip_l != null and grip_l.is_inside_tree():
		return grip_l.global_position
	return Vector3.INF


## Flashlight attachment: a SpotLight3D at Att_Flashlight (or the muzzle). No shadows (light budget).
func set_light_on(on: bool, energy_scale: float = 1.0) -> void:
	if light == null:
		return
	light.visible = on
	light.light_energy = 5.0 * energy_scale


func has_light() -> bool:
	return light != null


## Put the weapon into the holder's right hand. Returns true when a hand bone was used.
## Order: holder.visual.get_bone_attachment("Hand_R") -> holder itself at a hip offset.
func attach_to_holder(holder: Node) -> bool:
	attached_to_hand = false
	if holder == null or not is_instance_valid(holder):
		return false
	var visual: Variant = holder.get("visual")
	if visual != null and is_instance_valid(visual) and visual is Node3D and (visual as Node3D).has_method("get_bone_attachment"):
		var socket: Variant = (visual as Node3D).call("get_bone_attachment", HAND_BONE)
		if socket != null and is_instance_valid(socket) and socket is Node3D:
			_reparent_to(socket as Node3D)
			transform = compute_hand_transform(visual as Node3D, socket as Node3D)
			attached_to_hand = true
			return true
	if holder is Node3D:
		_reparent_to(holder as Node3D)
		transform = Transform3D(Basis.IDENTITY, FALLBACK_OFFSET) * _spec_tune()
	return false


## Local transform of the weapon under the hand socket (bone attachment) =
## canonical grip (HumanoidAnimator.get_grip_transform when that script exists, otherwise the
## same thing derived here from the bone's rest pose) * per-weapon tuning in the weapon's frame.
func compute_hand_transform(visual: Node3D, _socket: Node3D) -> Transform3D:
	var tune := _spec_tune()
	var skeleton: Skeleton3D = null
	if visual.has_method("get_skeleton"):
		skeleton = visual.call("get_skeleton") as Skeleton3D
	if skeleton == null or not is_instance_valid(skeleton):
		return Transform3D(Basis.IDENTITY, DEFAULT_GRIP_OFFSET) * tune
	var bone := skeleton.find_bone(HAND_BONE)
	if bone < 0:
		return Transform3D(Basis.IDENTITY, DEFAULT_GRIP_OFFSET) * tune
	var animator := _get_animator_script()
	if animator != null:
		var grip: Variant = animator.call("get_grip_transform", skeleton, HAND_BONE)
		if grip is Transform3D:
			return (grip as Transform3D) * tune
	var desired := Transform3D(rest_basis, rest_basis * DEFAULT_GRIP_OFFSET)
	# bone rest expressed in the visual's (character) space, including any armature scale
	var skel_rel := Transform3D.IDENTITY
	if visual.is_inside_tree() and skeleton.is_inside_tree():
		skel_rel = visual.global_transform.affine_inverse() * skeleton.global_transform
	else:
		var n: Node = skeleton
		while n != null and n != visual:
			if n is Node3D:
				skel_rel = (n as Node3D).transform * skel_rel
			n = n.get_parent()
	var rest_basis_char := (skel_rel.basis * skeleton.get_bone_global_rest(bone).basis)
	return Transform3D(rest_basis_char.inverse() * desired.basis, rest_basis_char.inverse() * desired.origin) * tune


static func _get_animator_script() -> Script:
	if not _animator_checked:
		_animator_checked = true
		if ResourceLoader.exists(ANIMATOR_SCRIPT):
			var s := load(ANIMATOR_SCRIPT) as Script
			if s != null:
				for m: Dictionary in s.get_script_method_list():
					if m.get("name", "") == "get_grip_transform":
						_animator_script = s
						break
	return _animator_script


func detach() -> void:
	if get_parent() != null:
		get_parent().remove_child(self)
	attached_to_hand = false


# --- internals ----------------------------------------------------------------------------------

func _spec_tune() -> Transform3D:
	var rot := global_hold_rotation
	var off := global_hold_offset
	if spec != null:
		rot += spec.hold_rotation
		off += spec.hold_offset
	var b := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	return Transform3D(b, off)


func _reparent_to(new_parent: Node3D) -> void:
	if get_parent() == new_parent:
		return
	if get_parent() != null:
		get_parent().remove_child(self)
	new_parent.add_child(self)


func _apply_mag_visibility() -> void:
	if mag != null:
		mag.visible = _mag_loaded and not _ext_mag_shown
	if _ext_mag_shown and spec != null and spec.hide_mag_when_empty:
		(_attachment_nodes["Att_ExtMag"] as Node3D).visible = _mag_loaded


func _make_marker(marker_name: String, at: Vector3) -> Node3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = at
	add_child(m)
	return m


func _fallback_length() -> float:
	if spec == null:
		return 0.3
	match spec.weapon_pose:
		"pistol": return 0.2
		"rifle": return 0.6
		"rpg": return 0.7
	return 0.3


func _is_finish_material(mat: Material) -> bool:
	return mat.resource_name == AttachmentSpec.FINISH_MATERIAL or mat.resource_name.begins_with(AttachmentSpec.FINISH_MATERIAL + ".")


func _tinted(base: Material, color: Color, metallic: float, roughness: float) -> Material:
	var key := "%d:%s:%.2f:%.2f" % [base.get_instance_id(), color.to_html(false), metallic, roughness]
	if _finish_cache.has(key):
		return _finish_cache[key]
	var mat := base.duplicate() as Material
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		bm.albedo_color = color
		if metallic >= 0.0:
			bm.metallic = metallic
		if roughness >= 0.0:
			bm.roughness = roughness
	elif mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("albedo", color)
	mat.resource_name = AttachmentSpec.FINISH_MATERIAL
	_finish_cache[key] = mat
	return mat


func _ensure_light(wanted: bool) -> void:
	if not wanted:
		if light != null:
			light.queue_free()
			light = null
		return
	if light != null or _muzzle_plain == null:
		return
	light = SpotLight3D.new()
	light.name = "FlashlightBeam"
	light.spot_range = 30.0
	light.spot_angle = 24.0
	light.spot_angle_attenuation = 0.8
	light.spot_attenuation = 1.2
	light.light_color = Color(1.0, 0.96, 0.86)
	light.light_energy = 5.0
	light.shadow_enabled = false
	light.visible = false
	# lens marker of the model when it has one, else the attachment mesh, else under the muzzle
	var anchor: Node3D = _light_marker if _light_marker != null else (_attachment_nodes.get("Att_Flashlight", null) as Node3D)
	if anchor != null:
		add_child(light)
		var ahead := -0.02 if anchor == _light_marker else -0.06
		light.transform = Transform3D(Basis.IDENTITY, _content.transform * _relative_position(anchor) + Vector3(0.0, 0.0, ahead))
	else:
		_muzzle_plain.add_child(light)
		light.position = Vector3(0.0, -0.03, 0.0)


## Position of a descendant of _content in _content space.
func _relative_position(node: Node3D) -> Vector3:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != _content:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf.origin
