class_name CharacterVisual
extends Node3D
## Visual side of every humanoid (player, pedestrians, police): Blender-authored skinned
## model, shared animation library, region-coloured clothing, accessories, hand attachments
## and a procedural pose layer (PoseModifier) for aiming, IK and missing clips.
## If the character GLB has not been exported yet a generated mannequin with the same
## skeleton is used, so gameplay code never depends on asset availability.

const BONES := [
	["Hips", "", Vector3(0, 0.96, 0)], ["Spine", "Hips", Vector3(0, 1.08, 0)], ["Chest", "Spine", Vector3(0, 1.26, 0)],
	["Neck", "Chest", Vector3(0, 1.48, 0)], ["Head", "Neck", Vector3(0, 1.56, 0)],
	["UpperArm_L", "Chest", Vector3(-0.20, 1.43, 0)], ["LowerArm_L", "UpperArm_L", Vector3(-0.235, 1.15, 0)],
	["Hand_L", "LowerArm_L", Vector3(-0.265, 0.89, 0)], ["Prop_L", "Hand_L", Vector3(-0.275, 0.80, -0.03)],
	["UpperArm_R", "Chest", Vector3(0.20, 1.43, 0)], ["LowerArm_R", "UpperArm_R", Vector3(0.235, 1.15, 0)],
	["Hand_R", "LowerArm_R", Vector3(0.265, 0.89, 0)], ["Prop_R", "Hand_R", Vector3(0.275, 0.80, -0.03)],
	["UpperLeg_L", "Hips", Vector3(-0.095, 0.93, 0)], ["LowerLeg_L", "UpperLeg_L", Vector3(-0.095, 0.51, 0)],
	["Foot_L", "LowerLeg_L", Vector3(-0.095, 0.09, 0)],
	["UpperLeg_R", "Hips", Vector3(0.095, 0.93, 0)], ["LowerLeg_R", "UpperLeg_R", Vector3(0.095, 0.51, 0)],
	["Foot_R", "LowerLeg_R", Vector3(0.095, 0.09, 0)],
]
const UPPER := ["Spine", "Chest", "Neck", "Head", "UpperArm_L", "LowerArm_L", "Hand_L", "UpperArm_R", "LowerArm_R", "Hand_R"]
const ARMS := ["UpperArm_L", "LowerArm_L", "Hand_L", "UpperArm_R", "LowerArm_R", "Hand_R"]
const CLIP := {
	&"idle": "Idle", &"walk": "Walk", &"run": "Run", &"sprint": "Sprint", &"crouch_idle": "CrouchIdle",
	&"crouch_walk": "CrouchWalk", &"jump": "Jump", &"fall": "Fall", &"land": "Land", &"swim_idle": "SwimIdle",
	&"swim": "Swim", &"dive": "Dive", &"ladder": "ClimbLadder", &"sit_car": "SitCar", &"sit_bike": "SitBike",
	&"sit_passenger": "SitPassenger", &"cover_low": "CoverLow", &"cover_high": "CoverHigh", &"hands_up": "HandsUp",
	&"cower": "Cower", &"surrender": "Surrender", &"parachute": "Parachute", &"freefall": "Freefall",
	&"phone": "PhoneUse", &"phone_call": "PhoneCall", &"talk": "Talk", &"sit": "Sit", &"dead": "Death_Back", &"block": "Block",
}
const LOOPS := ["Idle", "Walk", "Run", "Sprint", "CrouchIdle", "CrouchWalk", "Fall", "SwimIdle", "Swim", "Dive",
	"ClimbLadder", "SitCar", "SitPassenger", "SitBike", "AimPistol", "AimRifle", "HoldRifle", "Block", "CoverLow",
	"CoverHigh", "HandsUp", "Cower", "Surrender", "PhoneCall", "PhoneUse", "Talk", "Sit", "Parachute", "Freefall"]
## Gait speed of each clip at 1x playback (measured on the Blender clips, see manifests/characters.json)
const NOMINAL_SPEED := {"Walk": 1.41, "Run": 4.11, "Sprint": 6.82, "CrouchWalk": 1.27, "Swim": 2.2, "Dive": 2.0, "ClimbLadder": 1.08}

static var _library: AnimationLibrary = null
static var _library_checked := false
static var _pose_cache: Dictionary = {}

var skeleton: Skeleton3D
var anim: AnimationPlayer
var modifier: PoseModifier
var body_material: ShaderMaterial
var hand_r: BoneAttachment3D
var hand_l: BoneAttachment3D
var head_attach: BoneAttachment3D
var chest_attach: BoneAttachment3D
var is_mannequin := false
var female := false
var state: StringName = &""
var move_speed := 0.0
var upper: StringName = &""          # "", "aim_pistol", "aim_rifle", "hold_rifle", "aim_one"
var aim_pitch := 0.0                 # radians, + = looking up
var lean := 0.0                      # radians, body roll into turns
var recoil := 0.0
var look_yaw := 0.0
var _clock := 0.0
var _action := ""
var _action_left := 0.0
var _overlay_clip := ""
var _overlay_time := 0.0
var _overlay_len := 0.0
var _overlay_bones: Array = []
var _upper_w := 0.0
var _colors := PackedColorArray()
var _accessories: Dictionary = {}
var _mannequin_meshes: Dictionary = {}
var _flash := 0.0
var _model: Node3D

# ---------------------------------------------------------------- construction
func build(body := "male") -> void:
	female = body == "female"
	var rel := "characters/human_female" if female else "characters/human_male"
	if not Assets.has_model(rel):
		rel = "characters/human_male"
	if Assets.has_model(rel):
		_model = Assets.instance(rel)
		add_child(_model)
		skeleton = _find_skeleton(_model)
	if skeleton == null:
		if _model:
			_model.queue_free()
			_model = null
		_build_mannequin()
	else:
		var old := _find_anim(_model)
		if old:
			old.get_parent().remove_child(old)
			old.queue_free()
		body_material = Assets.new_character_material()
		for mi in Assets.find_meshes(_model):
			var nm := String(mi.name)
			var k := nm.rfind("__acc_")
			if k >= 0:
				_accessories[nm.substr(k + 6)] = mi
				mi.visible = false
			for s in mi.get_surface_override_material_count():
				var m := mi.mesh.surface_get_material(s)
				if m == Assets.mat("Character") or (m != null and String(m.resource_name).begins_with("Character")):
					mi.set_surface_override_material(s, body_material)
		if female:
			_model.scale = Vector3.ONE * 0.94
	modifier = PoseModifier.new()
	modifier.name = "PoseModifier"
	skeleton.add_child(modifier)
	modifier.setup(skeleton)
	hand_r = _attach("Prop_R")
	hand_l = _attach("Prop_L")
	head_attach = _attach("Head")
	chest_attach = _attach("Chest")
	var lib := shared_library()
	if lib != null:
		anim = AnimationPlayer.new()
		anim.name = "Anim"
		skeleton.get_parent().add_child(anim)
		anim.root_node = anim.get_path_to(skeleton.get_parent())
		anim.add_animation_library("", lib)
		anim.playback_default_blend_time = 0.18
	if _colors.is_empty():
		set_appearance(Appearance.default_player())
	set_state(&"idle")

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null

func _attach(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.name = "Attach_" + bone
	skeleton.add_child(ba)
	ba.bone_name = bone
	return ba

## The animation clips authored in Blender (human_male.glb), re-targeted to "Skeleton3D:<bone>"
## so one library drives every character regardless of its scene root name.
static func shared_library() -> AnimationLibrary:
	if _library_checked:
		return _library
	_library_checked = true
	var ps := Assets.scene("characters/human_male")
	if ps == null:
		return null
	var inst := ps.instantiate()
	var src := _find_anim(inst)
	if src != null:
		var lib := AnimationLibrary.new()
		for nm in src.get_animation_list():
			var a: Animation = src.get_animation(nm).duplicate(true)
			for t in range(a.get_track_count() - 1, -1, -1):
				var path := a.track_get_path(t)
				var sub := path.get_concatenated_subnames()
				if sub == "":
					a.remove_track(t)
				else:
					a.track_set_path(t, NodePath("Skeleton3D:" + sub))
			var clean := String(nm)
			a.loop_mode = Animation.LOOP_LINEAR if LOOPS.has(clean) else Animation.LOOP_NONE
			lib.add_animation(clean, a)
		if lib.get_animation_list().size() > 0:
			_library = lib
	inst.free()
	return _library

func has_clip(clip: String) -> bool:
	return anim != null and anim.has_animation(clip)

# ---------------------------------------------------------------- mannequin fallback
func _build_mannequin() -> void:
	is_mannequin = true
	var holder := Node3D.new()
	holder.name = "Mannequin"
	add_child(holder)
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	holder.add_child(skeleton)
	var pos := {}
	for b in BONES:
		var i := skeleton.add_bone(b[0])
		pos[b[0]] = b[2]
		var parent_pos := Vector3.ZERO
		if b[1] != "":
			skeleton.set_bone_parent(i, skeleton.find_bone(b[1]))
			parent_pos = pos[b[1]]
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, (b[2] as Vector3) - parent_pos))
	skeleton.reset_bone_poses()
	# simple blocky body parts: [bone, size, offset, region]
	var parts := [
		["Hips", Vector3(0.34, 0.2, 0.2), Vector3(0, 0.0, 0), 5], ["Spine", Vector3(0.32, 0.2, 0.19), Vector3(0, 0.09, 0), 1],
		["Chest", Vector3(0.4, 0.26, 0.22), Vector3(0, 0.1, 0), 1], ["Head", Vector3(0.2, 0.24, 0.22), Vector3(0, 0.12, 0), 0],
		["UpperArm_L", Vector3(0.1, 0.28, 0.1), Vector3(-0.015, -0.14, 0), 2], ["LowerArm_L", Vector3(0.09, 0.26, 0.09), Vector3(-0.015, -0.13, 0), 3],
		["Hand_L", Vector3(0.08, 0.14, 0.05), Vector3(0, -0.07, 0), 4],
		["UpperArm_R", Vector3(0.1, 0.28, 0.1), Vector3(0.015, -0.14, 0), 2], ["LowerArm_R", Vector3(0.09, 0.26, 0.09), Vector3(0.015, -0.13, 0), 3],
		["Hand_R", Vector3(0.08, 0.14, 0.05), Vector3(0, -0.07, 0), 4],
		["UpperLeg_L", Vector3(0.15, 0.42, 0.16), Vector3(0, -0.21, 0), 6], ["LowerLeg_L", Vector3(0.13, 0.42, 0.14), Vector3(0, -0.21, 0), 7],
		["Foot_L", Vector3(0.12, 0.09, 0.27), Vector3(0, -0.045, -0.06), 8],
		["UpperLeg_R", Vector3(0.15, 0.42, 0.16), Vector3(0, -0.21, 0), 6], ["LowerLeg_R", Vector3(0.13, 0.42, 0.14), Vector3(0, -0.21, 0), 7],
		["Foot_R", Vector3(0.12, 0.09, 0.27), Vector3(0, -0.045, -0.06), 8],
	]
	for p in parts:
		var ba := BoneAttachment3D.new()
		skeleton.add_child(ba)
		ba.bone_name = p[0]
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[1]
		mi.mesh = bm
		mi.position = p[2]
		var sm := StandardMaterial3D.new()
		sm.roughness = 0.85
		mi.material_override = sm
		ba.add_child(mi)
		if not _mannequin_meshes.has(p[3]):
			_mannequin_meshes[p[3]] = []
		(_mannequin_meshes[p[3]] as Array).append(sm)

# ---------------------------------------------------------------- appearance
func set_appearance(ap: Dictionary) -> void:
	_colors = Appearance.region_colors(ap)
	if body_material:
		body_material.set_shader_parameter("colors", _colors)
	for region in _mannequin_meshes.keys():
		for sm in _mannequin_meshes[region]:
			(sm as StandardMaterial3D).albedo_color = _colors[region]
	var wanted: Array = Appearance.accessories(ap)
	for nm in _accessories.keys():
		(_accessories[nm] as MeshInstance3D).visible = wanted.has(nm)

func set_accessory(acc: String, on: bool) -> void:
	if _accessories.has(acc):
		(_accessories[acc] as MeshInstance3D).visible = on

func flash_hit() -> void:
	_flash = 1.0

# ---------------------------------------------------------------- animation
func set_state(s: StringName, speed := 0.0) -> void:
	move_speed = speed
	if s == state and _action == "":
		_sync_speed()
		return
	state = s
	if _action != "":
		return
	_play_state()

func _play_state() -> void:
	var clip: String = CLIP.get(state, "")
	if has_clip(clip):
		modifier.base_weight = 0.0
		modifier.hips_weight = 0.0
		if anim.current_animation != clip:
			anim.play(clip, 0.2)
		_sync_speed()
	else:
		if anim != null and anim.is_playing() and anim.has_animation("Idle") and state != &"idle":
			anim.play("Idle", 0.2)
		elif anim != null and not anim.has_animation("Idle"):
			anim.stop()

func _sync_speed() -> void:
	if anim == null:
		return
	var clip: String = CLIP.get(state, "")
	if NOMINAL_SPEED.has(clip) and anim.current_animation == clip:
		anim.speed_scale = clampf(move_speed / float(NOMINAL_SPEED[clip]), 0.45, 1.8)
	elif _action == "":
		anim.speed_scale = 1.0

## Full-body one-shot (Roll, Vault, Punch, GetUp...). Returns its duration (0 when missing).
func play_action(clip: String, speed := 1.0, blend := 0.1) -> float:
	if not has_clip(clip):
		return 0.0
	_action = clip
	anim.speed_scale = speed
	anim.play(clip, blend)
	_action_left = anim.get_animation(clip).length / maxf(speed, 0.05)
	modifier.base_weight = 0.0
	return _action_left

## Upper-body one-shot blended over whatever the legs are doing (reload, punch while moving, throw).
func play_upper(clip: String, speed := 1.0, bones: Array = UPPER) -> float:
	if not has_clip(clip):
		return 0.0
	_overlay_clip = clip
	_overlay_time = 0.0
	_overlay_len = anim.get_animation(clip).length
	_overlay_bones = bones
	set_meta("overlay_speed", speed)
	return _overlay_len / maxf(speed, 0.05)

func stop_action() -> void:
	_action = ""
	_action_left = 0.0
	_play_state()

func is_busy() -> bool:
	return _action != ""

## Bone rotations of a clip at a given time (cached for time 0 = static poses).
func sample_clip(clip: String, time: float, bones: Array) -> Dictionary:
	var out := {}
	if not has_clip(clip):
		return out
	var key := clip
	if time == 0.0 and _pose_cache.has(key):
		var cached: Dictionary = _pose_cache[key]
		for b in bones:
			if cached.has(b) and modifier.idx.has(b):
				out[modifier.idx[b]] = cached[b]
		return out
	var a := anim.get_animation(clip)
	var all := {}
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := a.track_get_path(t).get_concatenated_subnames()
		all[bone] = a.rotation_track_interpolate(t, time)
	if time == 0.0:
		_pose_cache[key] = all
	for b in bones:
		if all.has(b) and modifier.idx.has(b):
			out[modifier.idx[b]] = all[b]
	return out

static func _q(x: float, y: float, z: float) -> Quaternion:
	return Quaternion.from_euler(Vector3(deg_to_rad(x), deg_to_rad(y), deg_to_rad(z)))

func _named(pose: Dictionary) -> Dictionary:
	var out := {}
	for b in pose.keys():
		if modifier.idx.has(b):
			out[modifier.idx[b]] = pose[b]
	return out

## Procedural full-body pose for states that have no authored clip (yet).
func _procedural(t: float) -> Array:
	var p := {}
	var hips := Vector3.ZERO
	var sp := move_speed
	match state:
		&"walk", &"run", &"sprint", &"crouch_walk":
			var k := clampf((sp - 1.4) / 5.6, 0.0, 1.0)
			var f := lerpf(0.95, 1.75, k)
			var ph := t * f * TAU
			var a := lerpf(26.0, 56.0, k)
			var kn := lerpf(34.0, 96.0, k)
			var s := sin(ph)
			var c := cos(ph)
			p["UpperLeg_L"] = _q(a * s, 0, 0)
			p["UpperLeg_R"] = _q(-a * s, 0, 0)
			p["LowerLeg_L"] = _q(-kn * maxf(0.0, c) - 6.0, 0, 0)
			p["LowerLeg_R"] = _q(-kn * maxf(0.0, -c) - 6.0, 0, 0)
			p["UpperArm_L"] = _q(-a * 0.8 * s, 0, -6)
			p["UpperArm_R"] = _q(a * 0.8 * s, 0, 6)
			var el := lerpf(14.0, 78.0, k)
			p["LowerArm_L"] = _q(el, 0, 0)
			p["LowerArm_R"] = _q(el, 0, 0)
			p["Spine"] = _q(-lerpf(2.0, 12.0, k), 0, 0)
			p["Chest"] = _q(-lerpf(1.0, 6.0, k), 4.0 * s, 0)
			hips = Vector3(0, -absf(s) * lerpf(0.02, 0.05, k), 0)
			if state == &"crouch_walk":
				hips.y -= 0.3
				p["Spine"] = _q(-28, 0, 0)
				p["UpperLeg_L"] = _q(55 + a * 0.5 * s, 0, 0)
				p["UpperLeg_R"] = _q(55 - a * 0.5 * s, 0, 0)
				p["LowerLeg_L"] = _q(-95, 0, 0)
				p["LowerLeg_R"] = _q(-95, 0, 0)
		&"crouch_idle", &"cover_low", &"cower":
			hips = Vector3(0, -0.36, 0)
			p["UpperLeg_L"] = _q(78, 0, -6); p["UpperLeg_R"] = _q(60, 0, 6)
			p["LowerLeg_L"] = _q(-118, 0, 0); p["LowerLeg_R"] = _q(-112, 0, 0)
			p["Foot_L"] = _q(30, 0, 0); p["Foot_R"] = _q(40, 0, 0)
			p["Spine"] = _q(-22, 0, 0)
			if state == &"cower":
				p["UpperArm_L"] = _q(150, 0, -30); p["UpperArm_R"] = _q(150, 0, 30)
				p["LowerArm_L"] = _q(110, 0, 0); p["LowerArm_R"] = _q(110, 0, 0)
				p["Head"] = _q(-30, 0, 0)
		&"jump", &"fall", &"freefall":
			p["UpperLeg_L"] = _q(28, 0, -6); p["UpperLeg_R"] = _q(-8, 0, 6)
			p["LowerLeg_L"] = _q(-48, 0, 0); p["LowerLeg_R"] = _q(-30, 0, 0)
			p["UpperArm_L"] = _q(20, 0, -55 + 6.0 * sin(t * 9.0)); p["UpperArm_R"] = _q(20, 0, 55 + 6.0 * sin(t * 9.0 + 1.0))
			p["LowerArm_L"] = _q(30, 0, 0); p["LowerArm_R"] = _q(30, 0, 0)
		&"swim", &"dive", &"swim_idle":
			if state == &"swim_idle":
				var w := sin(t * 3.0)
				p["UpperArm_L"] = _q(30, 0, -60 + 20 * w); p["UpperArm_R"] = _q(30, 0, 60 - 20 * w)
				p["LowerArm_L"] = _q(40, 0, 0); p["LowerArm_R"] = _q(40, 0, 0)
				p["UpperLeg_L"] = _q(18 * w, 0, -8); p["UpperLeg_R"] = _q(-18 * w, 0, 8)
				p["LowerLeg_L"] = _q(-25, 0, 0); p["LowerLeg_R"] = _q(-25, 0, 0)
			else:
				var ph2 := t * 5.2
				p["Hips"] = _q(-78, 0, 0)
				p["Neck"] = _q(40, 0, 0)
				p["Head"] = _q(25, 0, 0)
				p["UpperArm_L"] = _q(170 + 0.0, 0, -20 - 60.0 * maxf(0.0, sin(ph2))); p["UpperArm_R"] = _q(170, 0, 20 + 60.0 * maxf(0.0, -sin(ph2)))
				p["LowerArm_L"] = _q(15, 0, 0); p["LowerArm_R"] = _q(15, 0, 0)
				p["UpperLeg_L"] = _q(14 * sin(ph2 * 2.0), 0, 0); p["UpperLeg_R"] = _q(-14 * sin(ph2 * 2.0), 0, 0)
				p["LowerLeg_L"] = _q(-12, 0, 0); p["LowerLeg_R"] = _q(-12, 0, 0)
		&"sit_car", &"sit_passenger", &"sit", &"sit_bike":
			p["UpperLeg_L"] = _q(84, 0, -5); p["UpperLeg_R"] = _q(84, 0, 5)
			p["LowerLeg_L"] = _q(-78, 0, 0); p["LowerLeg_R"] = _q(-78, 0, 0)
			p["Spine"] = _q(4, 0, 0)
			if state == &"sit_car" or state == &"sit_bike":
				p["UpperArm_L"] = _q(62, 0, 8); p["UpperArm_R"] = _q(62, 0, -8)
				p["LowerArm_L"] = _q(28, 0, 0); p["LowerArm_R"] = _q(28, 0, 0)
			else:
				p["UpperArm_L"] = _q(25, 0, -4); p["UpperArm_R"] = _q(25, 0, 4)
				p["LowerArm_L"] = _q(60, 0, 0); p["LowerArm_R"] = _q(60, 0, 0)
			if state == &"sit_bike":
				p["Spine"] = _q(-24, 0, 0)
				p["Neck"] = _q(18, 0, 0)
		&"hands_up", &"surrender":
			p["UpperArm_L"] = _q(20, 0, -150); p["UpperArm_R"] = _q(20, 0, 150)
			p["LowerArm_L"] = _q(30, 0, 0); p["LowerArm_R"] = _q(30, 0, 0)
			if state == &"surrender":
				hips = Vector3(0, -0.42, 0)
				p["UpperLeg_L"] = _q(8, 0, 0); p["UpperLeg_R"] = _q(8, 0, 0)
				p["LowerLeg_L"] = _q(-100, 0, 0); p["LowerLeg_R"] = _q(-100, 0, 0)
		&"parachute":
			p["UpperArm_L"] = _q(10, 0, -155); p["UpperArm_R"] = _q(10, 0, 155)
			p["UpperLeg_L"] = _q(22, 0, -4); p["UpperLeg_R"] = _q(26, 0, 4)
			p["LowerLeg_L"] = _q(-30, 0, 0); p["LowerLeg_R"] = _q(-36, 0, 0)
		&"ladder":
			var w2 := sin(t * 6.0)
			p["UpperArm_L"] = _q(120 + 30 * w2, 0, -8); p["UpperArm_R"] = _q(120 - 30 * w2, 0, 8)
			p["LowerArm_L"] = _q(50, 0, 0); p["LowerArm_R"] = _q(50, 0, 0)
			p["UpperLeg_L"] = _q(45 - 30 * w2, 0, 0); p["UpperLeg_R"] = _q(45 + 30 * w2, 0, 0)
			p["LowerLeg_L"] = _q(-70 + 30 * w2, 0, 0); p["LowerLeg_R"] = _q(-70 - 30 * w2, 0, 0)
		&"dead":
			p["Hips"] = _q(86, 0, 0)
			hips = Vector3(0, -0.82, 0)
			p["UpperArm_L"] = _q(0, 0, -50); p["UpperArm_R"] = _q(0, 0, 70)
			p["UpperLeg_R"] = _q(-14, 0, 8)
		&"phone", &"phone_call":
			p["UpperArm_R"] = _q(60, 0, 10); p["LowerArm_R"] = _q(95, 0, 0)
			p["Head"] = _q(-14, 0, 0)
		&"talk":
			p["UpperArm_R"] = _q(30 + 10 * sin(t * 2.3), 0, 8); p["LowerArm_R"] = _q(70 + 15 * sin(t * 3.1), 0, 0)
		&"block":
			p["UpperArm_L"] = _q(80, 0, 10); p["UpperArm_R"] = _q(80, 0, -10)
			p["LowerArm_L"] = _q(110, 0, 0); p["LowerArm_R"] = _q(110, 0, 0)
		_:
			var br := sin(t * 1.6)
			p["Chest"] = _q(-1.0 + br, 0, 0)
			p["UpperArm_L"] = _q(2, 0, -5 - br); p["UpperArm_R"] = _q(2, 0, 5 + br)
			p["LowerArm_L"] = _q(8, 0, 0); p["LowerArm_R"] = _q(8, 0, 0)
	return [p, hips]

func _upper_pose() -> Dictionary:
	var p := {}
	match upper:
		&"aim_pistol":
			if has_clip("AimPistol"):
				return sample_clip("AimPistol", 0.0, UPPER)
			p["UpperArm_R"] = _q(84, -18, 0); p["LowerArm_R"] = _q(6, 0, 0)
			p["UpperArm_L"] = _q(80, 26, 0); p["LowerArm_L"] = _q(14, 0, 0)
			p["Spine"] = _q(-3, 0, 0); p["Chest"] = _q(-3, 0, 0); p["Head"] = _q(0, 0, 0)
		&"aim_one":
			p["UpperArm_R"] = _q(86, -6, 0); p["LowerArm_R"] = _q(4, 0, 0)
		&"aim_rifle":
			if has_clip("AimRifle"):
				return sample_clip("AimRifle", 0.0, UPPER)
			p["UpperArm_R"] = _q(46, -12, 22); p["LowerArm_R"] = _q(88, 0, 0)
			p["UpperArm_L"] = _q(76, 34, 0); p["LowerArm_L"] = _q(34, 0, 0)
			p["Spine"] = _q(-4, -8, 0); p["Chest"] = _q(-3, -10, 0); p["Head"] = _q(0, 14, 0)
		&"hold_rifle":
			if has_clip("HoldRifle"):
				return sample_clip("HoldRifle", 0.0, ARMS)
			p["UpperArm_R"] = _q(18, 0, 12); p["LowerArm_R"] = _q(72, 0, 0)
			p["UpperArm_L"] = _q(42, 30, 0); p["LowerArm_L"] = _q(62, 0, 0)
		&"hold_pistol":
			p["UpperArm_R"] = _q(8, 0, 6); p["LowerArm_R"] = _q(22, 0, 0)
	return _named(p)

func _process(delta: float) -> void:
	if skeleton == null:
		return
	_clock += delta
	if _action != "":
		_action_left -= delta
		if _action_left <= 0.0:
			_action = ""
			# a finished death clip holds its last frame instead of restarting the "dead" state clip
			if state != &"dead":
				_play_state()
	# --- base layer: authored clip or procedural fallback
	var clip: String = CLIP.get(state, "")
	if _action == "" and not has_clip(clip):
		var res := _procedural(_clock)
		modifier.base = _named(res[0])
		# bones not mentioned return to rest
		for b in modifier.idx.keys():
			var bi: int = modifier.idx[b]
			if not modifier.base.has(bi) and not String(b).begins_with("Prop"):
				modifier.base[bi] = Quaternion.IDENTITY
		modifier.base_weight = move_toward(modifier.base_weight, 1.0, delta * 8.0)
		modifier.hips_offset = modifier.hips_offset.lerp(res[1], clampf(delta * 10.0, 0.0, 1.0))
		modifier.hips_weight = modifier.base_weight
	else:
		modifier.base_weight = move_toward(modifier.base_weight, 0.0, delta * 8.0)
		modifier.hips_weight = modifier.base_weight
	# --- upper-body overlay: timed clip (reload, punch...) has priority over the held pose
	var target_w := 0.0
	if _overlay_clip != "":
		_overlay_time += delta * float(get_meta("overlay_speed", 1.0))
		if _overlay_time >= _overlay_len:
			_overlay_clip = ""
		else:
			modifier.overlay = sample_clip(_overlay_clip, _overlay_time, _overlay_bones)
			target_w = 1.0
	if _overlay_clip == "" and upper != &"":
		modifier.overlay = _upper_pose()
		target_w = 1.0
	_upper_w = move_toward(_upper_w, target_w, delta * 9.0)
	modifier.overlay_weight = _upper_w
	# --- additive: aim pitch across the spine, turn lean, recoil kick
	modifier.add.clear()
	var aiming := upper == &"aim_pistol" or upper == &"aim_rifle" or upper == &"aim_one"
	var pitch := aim_pitch if aiming else 0.0
	if modifier.idx.has("Spine"):
		modifier.add[modifier.idx["Spine"]] = Quaternion(Vector3.RIGHT, pitch * 0.45 + recoil * 0.05) * Quaternion(Vector3.BACK, lean)
		modifier.add[modifier.idx["Chest"]] = Quaternion(Vector3.RIGHT, pitch * 0.45 + recoil * 0.08)
		if absf(look_yaw) > 0.01 or (not aiming and absf(aim_pitch) > 0.01):
			modifier.add[modifier.idx["Head"]] = Quaternion(Vector3.UP, look_yaw) * Quaternion(Vector3.RIGHT, 0.0 if aiming else aim_pitch * 0.5)
	recoil = move_toward(recoil, 0.0, delta * 9.0)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		if body_material:
			body_material.set_shader_parameter("flash", _flash * 0.6)

# ---------------------------------------------------------------- queries
func head_position() -> Vector3:
	var i := skeleton.find_bone("Head")
	if i < 0:
		return global_position + Vector3(0, 1.62, 0)
	return skeleton.global_transform * (skeleton.get_bone_global_pose(i).origin + Vector3(0, 0.1, 0))

func bone_position(bone: String) -> Vector3:
	var i := skeleton.find_bone(bone)
	if i < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin

## Skeleton-space position of a world point (for IK targets).
func to_skeleton(world_pos: Vector3) -> Vector3:
	return skeleton.global_transform.affine_inverse() * world_pos

func set_ik_hands(left: Variant, right: Variant, weight := 1.0) -> void:
	modifier.ik_hand_l = to_skeleton(left) if left != null else null
	modifier.ik_hand_r = to_skeleton(right) if right != null else null
	modifier.ik_weight = weight

func set_anim_active(on: bool) -> void:
	if anim:
		anim.active = on
	modifier.active = on
	set_process(on)

# ---------------------------------------------------------------- ragdoll
## Physical ragdoll built on demand (12 capsule / sphere bodies with cone joints on the shared
## skeleton). Used for violent deaths and hard knockdowns; bodies collide with the world,
## vehicles and props, and bullets shove them.
const RAG := [
	# bone, child bone (segment end) or "", radius, mass
	["Hips", "Spine", 0.14, 10.0], ["Spine", "Chest", 0.13, 8.0], ["Chest", "Neck", 0.16, 12.0], ["Head", "", 0.12, 5.0],
	["UpperArm_L", "LowerArm_L", 0.055, 2.5], ["LowerArm_L", "Hand_L", 0.048, 1.8],
	["UpperArm_R", "LowerArm_R", 0.055, 2.5], ["LowerArm_R", "Hand_R", 0.048, 1.8],
	["UpperLeg_L", "LowerLeg_L", 0.075, 7.0], ["LowerLeg_L", "Foot_L", 0.06, 4.0],
	["UpperLeg_R", "LowerLeg_R", 0.075, 7.0], ["LowerLeg_R", "Foot_R", 0.06, 4.0],
]

var ragdolling := false
var _sim: PhysicalBoneSimulator3D = null
var _pbones: Dictionary = {}

func _build_ragdoll() -> bool:
	if _sim != null:
		return true
	if skeleton == null or skeleton.find_bone("Hips") < 0:
		return false
	_sim = PhysicalBoneSimulator3D.new()
	_sim.name = "Ragdoll"
	skeleton.add_child(_sim)
	for spec in RAG:
		var bone := String(spec[0])
		var bi := skeleton.find_bone(bone)
		if bi < 0:
			continue
		var a := skeleton.get_bone_global_rest(bi).origin
		var b := a + Vector3(0, 0.24, 0)
		var child := String(spec[1])
		if child != "" and skeleton.find_bone(child) >= 0:
			b = skeleton.get_bone_global_rest(skeleton.find_bone(child)).origin
		if bone.begins_with("LowerArm"):
			b += (b - a).normalized() * 0.08
		var seg := b - a
		var r := float(spec[2])
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + bone
		_sim.add_child(pb)
		pb.bone_name = bone
		var cs := CollisionShape3D.new()
		if bone == "Head":
			var sph := SphereShape3D.new()
			sph.radius = r
			cs.shape = sph
			pb.body_offset = Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0))
		else:
			var cap := CapsuleShape3D.new()
			cap.radius = r
			cap.height = maxf(seg.length() + r * 0.6, r * 2.05)
			cs.shape = cap
			var dirv := seg.normalized()
			var basis := Basis.IDENTITY
			if absf(dirv.dot(Vector3.UP)) < 0.999:
				basis = Basis(Quaternion(Vector3.UP, dirv))
			elif dirv.y < 0.0:
				basis = Basis(Vector3.RIGHT, PI)
			pb.body_offset = Transform3D(basis, seg * 0.5)
		pb.add_child(cs)
		pb.joint_offset = Transform3D(Basis.IDENTITY, pb.body_offset.affine_inverse() * Vector3.ZERO)
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE if bone == "Hips" else PhysicalBone3D.JOINT_TYPE_CONE
		if bone != "Hips":
			var swing := 35.0 if (bone == "Spine" or bone == "Chest" or bone == "Head") else 70.0
			pb.set("joint_constraints/swing_span", swing)
			pb.set("joint_constraints/twist_span", 20.0)
			pb.set("joint_constraints/softness", 0.9)
			pb.set("joint_constraints/relaxation", 1.0)
		pb.mass = float(spec[3])
		pb.friction = 0.85
		pb.bounce = 0.0
		pb.linear_damp = 0.15
		pb.angular_damp = 1.2
		pb.collision_layer = Phys.RAGDOLL
		pb.collision_mask = Phys.WORLD | Phys.VEHICLE | Phys.PROP
		_pbones[bone] = pb
	return not _pbones.is_empty()

## Go limp. `impulse` pushes the torso; `vel` is the body's current velocity.
func start_ragdoll(impulse := Vector3.ZERO, vel := Vector3.ZERO) -> bool:
	if ragdolling:
		_push(impulse)
		return true
	if not _build_ragdoll():
		return false
	_action = ""
	upper = &""
	set_ik_hands(null, null)
	set_anim_active(false)
	_sim.active = true
	# place every body on its bone's current (animated) pose before simulation starts
	var sk_xf := skeleton.global_transform
	for bone: String in _pbones.keys():
		var pb: PhysicalBone3D = _pbones[bone]
		var bi := skeleton.find_bone(bone)
		pb.global_transform = (sk_xf * skeleton.get_bone_global_pose(bi) * pb.body_offset).orthonormalized()
	_sim.physical_bones_start_simulation()
	ragdolling = true
	for pb: PhysicalBone3D in _pbones.values():
		pb.linear_velocity = vel
	_push(impulse)
	return true

func _push(impulse: Vector3) -> void:
	if impulse.length() < 0.01:
		return
	for nm: String in ["Chest", "Spine", "Hips"]:
		if _pbones.has(nm):
			(_pbones[nm] as PhysicalBone3D).apply_central_impulse(impulse * (8.0 if nm == "Chest" else 6.0))

func stop_ragdoll() -> void:
	if not ragdolling:
		return
	ragdolling = false
	_sim.physical_bones_stop_simulation()
	_sim.active = false
	set_anim_active(true)

## World position of the pelvis while ragdolling (the character root follows it).
func ragdoll_hips() -> Vector3:
	if _pbones.has("Hips"):
		return (_pbones["Hips"] as PhysicalBone3D).global_position
	return global_position

func ragdoll_face_down() -> bool:
	if not _pbones.has("Chest"):
		return false
	return (_pbones["Chest"] as PhysicalBone3D).global_transform.basis.z.y > 0.0

func ragdoll_settled() -> bool:
	for pb: PhysicalBone3D in _pbones.values():
		if pb.linear_velocity.length() > 0.35:
			return false
	return true
