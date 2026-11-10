class_name CharacterVisual
extends Node3D
## Visual of the shared modular humanoid (docs/ARCHITECTURE.md 6.3, docs/CHARACTERS.md).
##
## One rigged body for the player and every human NPC:
##     res://gta/generated/models/characters/humanoid.glb   (Blender: tools/blender/assets/characters.py)
## The GLB holds ~64 skinned REPLACEMENT parts (Head_M, Hair_Short, Top_Tee_M, Bottom_Jeans_F,
## Outfit_Police_M ...). It is instantiated ONCE into a shared part library; every character then
## gets its own 20-bone Skeleton3D plus MeshInstance3Ds for the parts it actually wears, so parts
## that are not worn do not exist for that character (no hidden skinned instances to update).
## Colours are applied as surface override materials keyed by the contract material names
## (M_Skin, M_Hair, M_Top, M_Top_Accent, M_Bottom, M_Shoes, M_Hat, M_Eyes, M_Mouth); materials are
## cached and shared between all characters that use the same colour.
##
## Typical use:
##     var v := preload("res://gta/scenes/characters/humanoid.tscn").instantiate()
##     add_child(v)
##     v.randomize_appearance("civilian_f", my_seed)        # or v.apply_appearance({...})
##     animator.setup(v.get_skeleton())
##     gun.reparent(v.get_bone_attachment("Hand_R"))
##
## Scene tree of one character:  <this> / Armature (Node3D) / Skeleton3D / <part MeshInstance3Ds>

signal appearance_changed(appearance: Dictionary)

const MODEL_PATH := "res://gta/generated/models/characters/humanoid.glb"
const HEIGHT := 1.80
## Blender actions of this rig are named "Humanoid_<Clip>"; the game sees them as "<Clip>".
const CLIP_PREFIX := "Humanoid_"

const ARCHETYPES: PackedStringArray = [
	"player_default", "civilian_m", "civilian_f", "police", "tactical", "medic", "firefighter",
	"staff", "gang", "business", "beach",
]

## Appearance dictionary (all keys optional in apply_appearance; colours are "#rrggbb" strings or Colors).
const DEFAULT_APPEARANCE := {
	"body": "m",                 # "m" / "f"
	"skin": "#dda77b",
	"hair": "short",             # short, buzz, slick, curly, long, ponytail, bob, bun, mohawk, bald
	"hair_color": "#3a2a1e",
	"beard": "",                 # "", full, goatee, mustache
	"top": "tee",                # tee, shirt, hoodie, jacket, tank, suit, vest
	"top_color": "#3f7fc8",
	"top_accent_color": "",      # "" = automatic (trim / inner shirt / apron)
	"bottom": "jeans",           # jeans, shorts, cargo, slacks, skirt
	"bottom_color": "#3f5f8f",
	"shoes": "sneakers",         # sneakers, boots, dress
	"shoes_color": "#2a2a2e",
	"hat": "",                   # "", cap, beanie, brim, bandana (+ police, helmet, firehelmet)
	"hat_color": "#c8443a",
	"glasses": "",               # "", shades, round (+ goggles)
	"outfit": "",                # "", police, tactical, medic, firefighter, staff
	"eye_color": "#2a1c14",
	"gloves": "",                # "" = bare hands, else glove colour
}

## Full outfits replace top + bottom. The other entries are DEFAULTS that apply when the caller
## does not pass that key explicitly (so {"outfit": "police", "hat": ""} is an officer without a cap).
const OUTFITS := {
	"police": {"hat": "police", "shoes": "boots", "shoes_color": "#1c1e23", "glasses": ""},
	"tactical": {"hat": "helmet", "glasses": "goggles", "shoes": "boots", "shoes_color": "#1c1e23", "gloves": "#202328", "beard": ""},
	"medic": {"hat": "", "shoes": "sneakers", "shoes_color": "#e9e7e1", "gloves": "#8fcae8", "glasses": ""},
	"firefighter": {"hat": "firehelmet", "shoes": "boots", "shoes_color": "#1c1e23", "gloves": "#4a3426", "glasses": ""},
	"staff": {"hat": "", "shoes": "sneakers", "shoes_color": "#2a2a2e"},
}

## Ids that only make sense as part of a uniform (left out of get_part_options() by default).
const UNIFORM_ONLY := {"hat": ["police", "helmet", "firehelmet"], "glasses": ["goggles"]}

const SKIN_TONES: PackedStringArray = ["#f2c9a5", "#e8b88f", "#dda77b", "#c98f63", "#b97c54", "#8a5636", "#5e3a26"]
const HAIR_COLORS: PackedStringArray = ["#22201f", "#3a2a1e", "#5a3a25", "#8a5a34", "#d9b56a", "#a6452a", "#9a9a98", "#e6e2d8"]
const HAIR_COLORS_FUN: PackedStringArray = ["#22a7a0", "#b7a6e0", "#e89aae", "#2c6fd9"]
const TOP_COLORS: PackedStringArray = [
	"#efede6", "#c8443a", "#3f7fc8", "#4e9a63", "#e8c24a", "#ee7e64", "#22a7a0", "#27405f", "#3b404b",
	"#b7a6e0", "#e89aae", "#f0802f", "#8a9a5b", "#7a50d0", "#8fcae8", "#1c1e23", "#a2d9c2", "#b35a42",
]
const BOTTOM_COLORS: PackedStringArray = [
	"#3f5f8f", "#27405f", "#1c1e23", "#bfa77a", "#3b404b", "#8d887f", "#5f6b45", "#7b5637", "#efede6", "#6b88b5",
]
const SHOE_COLORS: PackedStringArray = ["#2a2a2e", "#e9e7e1", "#4a3426", "#c8443a", "#27405f", "#1c1e23", "#7a5a3c", "#22a7a0"]
const HAT_COLORS: PackedStringArray = ["#c8443a", "#27405f", "#1c1e23", "#efede6", "#22a7a0", "#e2b13c", "#4e9a63", "#3b404b", "#ee7e64", "#bfa77a"]
const SUIT_COLORS: PackedStringArray = ["#27405f", "#3b404b", "#1c1e23", "#5b6470", "#7b5637", "#8d887f"]
const EYE_COLORS: PackedStringArray = ["#2a1c14", "#3b2a1c", "#2e4a63", "#3d5a3a", "#1c1e23"]
const GANG_COLORS: PackedStringArray = ["#7a50d0", "#2f9e5c"]

const _CONTRACT_BONES: PackedStringArray = [
	"Root", "Hips", "Spine", "Chest", "Neck", "Head",
	"Shoulder_L", "UpperArm_L", "LowerArm_L", "Hand_L", "Shoulder_R", "UpperArm_R", "LowerArm_R", "Hand_R",
	"UpperLeg_L", "LowerLeg_L", "Foot_L", "UpperLeg_R", "LowerLeg_R", "Foot_R",
]
const _HEAD_SLOTS := ["head", "hair", "beard", "hat", "glasses"]
const _BIG_SLOTS := ["head", "top", "bottom", "outfit", "hair", "hat"]

## Appearance stored with the scene / duplicated nodes (applied in _ready when not empty).
@export var appearance: Dictionary = {}
## Archetype used in _ready when no appearance was given ("" = build nothing until asked).
@export var default_archetype: String = "player_default"

# --- shared part library (built once from the GLB) ---------------------------------------------
static var _lib_state: int = 0                 # 0 not built, 1 ok, -1 failed
static var _lib: Dictionary = {}               # part name -> {"mesh": Mesh, "skin": Skin, "slot": String, "surfaces": Array}
static var _index: Dictionary = {}             # slot -> id -> variant ("", "m", "f", "hat") -> part name
static var _bones: Array = []                  # [{"name", "parent", "rest"}]
static var _skel_xform: Transform3D = Transform3D.IDENTITY
static var _base_mats: Dictionary = {}         # contract material name -> imported Material
static var _mat_cache: Dictionary = {}         # "M_Top3f7fc8" -> Material
static var _anims: Dictionary = {}             # animation name -> Animation (optional Blender clips)

var _skeleton: Skeleton3D = null
var _armature: Node3D = null
var _parts: Dictionary = {}                    # part name -> MeshInstance3D
var _current: Dictionary = {}                  # normalised appearance in use
var _attachments: Dictionary = {}              # bone -> BoneAttachment3D
var _lod: int = 0
var _head_visible: bool = true
var _applied: bool = false
var _anim_player: AnimationPlayer = null


func _ready() -> void:
	_build()
	if _applied:
		return
	if not appearance.is_empty():
		apply_appearance(appearance)
	elif default_archetype != "":
		# Deferred to the end of this frame (still before it is drawn): spawners normally call
		# randomize_appearance() / apply_appearance() right after add_child(), so building the
		# default look first would only create parts that are thrown away immediately.
		_apply_default_look.call_deferred()


func _apply_default_look() -> void:
	if not _applied and default_archetype != "":
		randomize_appearance(default_archetype, 0)


# =================================================================================================
# public API (docs/ARCHITECTURE.md 6.3)
# =================================================================================================

## The character's Skeleton3D (20 contract bones, T-pose rest). Null only if the GLB is missing.
func get_skeleton() -> Skeleton3D:
	_build()
	return _skeleton


## Sets the whole look. Missing keys fall back to DEFAULT_APPEARANCE (and to the outfit's defaults
## when an outfit is given). Unknown part ids are ignored with a warning.
func apply_appearance(a: Dictionary) -> void:
	_build()
	_current = normalize_appearance(a)
	appearance = _current.duplicate()
	_applied = true
	if _skeleton == null:
		return
	_rebuild_parts()
	appearance_changed.emit(get_appearance())


## Changes only the given keys and keeps the rest of the current look (wardrobe / barber UIs).
func update_appearance(partial: Dictionary) -> void:
	var a := get_appearance()
	for k: Variant in partial.keys():
		a[k] = partial[k]
	apply_appearance(a)


## The current look as a plain, JSON-friendly Dictionary (colours are "#rrggbb" strings).
func get_appearance() -> Dictionary:
	if _current.is_empty():
		return normalize_appearance(appearance)
	return _current.duplicate()


## Deterministic random look for an archetype (see ARCHETYPES). The same archetype + seed always
## gives the same character.
func randomize_appearance(archetype: String, rng_seed: int = 0) -> void:
	apply_appearance(make_appearance(archetype, rng_seed))


## A BoneAttachment3D that follows `bone` (created on first use, then cached). Returns null for
## unknown bones. Parent weapons / props to it.
func get_bone_attachment(bone: String) -> Node3D:
	_build()
	if _skeleton == null:
		return null
	var existing: Variant = _attachments.get(bone, null)
	if existing != null and is_instance_valid(existing):
		return existing as Node3D
	var idx := _skeleton.find_bone(bone)
	if idx < 0:
		push_warning("CharacterVisual: unknown bone '%s'" % bone)
		return null
	var att := BoneAttachment3D.new()
	att.name = "Attach_" + bone
	_skeleton.add_child(att)
	att.bone_name = bone
	att.bone_idx = idx
	_attachments[bone] = att
	return att


## 0 = full detail, 1 = medium (small accessories hidden, only big parts cast shadows),
## 2 = far (no shadows, accessories hidden).
func set_lod(level: int) -> void:
	_lod = clampi(level, 0, 2)
	_refresh_visibility()


## slot -> available ids, plus colour palettes, for wardrobe / barber / shop UIs:
## {"body", "hair", "beard", "top", "bottom", "shoes", "hat", "glasses", "outfit",
##  "skin", "hair_color", "top_color", "bottom_color", "shoes_color", "hat_color"}.
func get_part_options(include_uniform_parts: bool = false) -> Dictionary:
	_ensure_library()
	var out: Dictionary = {"body": ["m", "f"]}
	for slot: String in ["hair", "beard", "top", "bottom", "shoes", "hat", "glasses", "outfit"]:
		var ids: Array = []
		if slot == "hair":
			ids.append("bald")
		elif slot in ["beard", "hat", "glasses", "outfit"]:
			ids.append("")
		var found: Array = (_index.get(slot, {}) as Dictionary).keys()
		found.sort()
		for id: String in found:
			if not include_uniform_parts and (UNIFORM_ONLY.get(slot, []) as Array).has(id):
				continue
			ids.append(id)
		out[slot] = ids
	out["skin"] = Array(SKIN_TONES)
	out["hair_color"] = Array(HAIR_COLORS) + Array(HAIR_COLORS_FUN)
	out["top_color"] = Array(TOP_COLORS)
	out["bottom_color"] = Array(BOTTOM_COLORS)
	out["shoes_color"] = Array(SHOE_COLORS)
	out["hat_color"] = Array(HAT_COLORS)
	return out


# =================================================================================================
# extras
# =================================================================================================

## Hides / shows everything on the head (first-person camera). Hidden head parts keep casting shadows.
func set_head_visible(on: bool) -> void:
	_head_visible = on
	_refresh_visibility()


## Local transform for an item parented to get_bone_attachment("Hand_R" / "Hand_L") so that it sits
## in the grip: item -Z (barrel) along the fingers, item +Y towards the thumb, origin in the palm.
func get_grip_transform(bone: String = "Hand_R") -> Transform3D:
	_build()
	if _skeleton == null:
		return Transform3D.IDENTITY
	var bi := _skeleton.find_bone(bone)
	if bi < 0:
		return Transform3D.IDENTITY
	var rest := _skeleton.get_bone_global_rest(bi)
	var side := -1.0 if bone.ends_with("_L") else 1.0
	var w := Basis(Vector3(0.0, side, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(-side, 0.0, 0.0))
	return rest.affine_inverse() * Transform3D(w, rest.origin + Vector3(0.075 * side, -0.03, 0.0))


## Names of the part meshes this character currently wears (debug / tests).
func get_active_parts() -> PackedStringArray:
	var out: PackedStringArray = []
	for k: String in _parts.keys():
		out.append(k)
	out.sort()
	return out


## The MeshInstance3D of a worn part (or null).
func get_part_node(part_name: String) -> MeshInstance3D:
	return _parts.get(part_name, null) as MeshInstance3D


## Simple fixed poses for characters without an animator (mannequins, UI previews, tests):
## "relaxed" (arms at the sides), "tpose" (rest).
func set_static_pose(pose: String = "relaxed") -> void:
	_build()
	if _skeleton == null:
		return
	_skeleton.reset_bone_poses()
	if pose == "relaxed":
		pose_bone_model("UpperArm_R", Basis(Vector3.BACK, deg_to_rad(-76.0)))
		pose_bone_model("UpperArm_L", Basis(Vector3.BACK, deg_to_rad(76.0)))
		pose_bone_model("LowerArm_R", Basis(Vector3.UP, deg_to_rad(14.0)))
		pose_bone_model("LowerArm_L", Basis(Vector3.UP, deg_to_rad(-14.0)))


## Rotates one bone by `rot`, a rotation expressed in MODEL axes of the rest pose (x right, y up,
## -z forward) relative to its parent - independent of bone roll. Handy for hand-made poses.
func pose_bone_model(bone: String, rot: Basis) -> void:
	if _skeleton == null:
		return
	var i := _skeleton.find_bone(bone)
	if i < 0:
		return
	var parent := _skeleton.get_bone_parent(i)
	var pr := Basis.IDENTITY
	if parent >= 0:
		pr = _skeleton.get_bone_global_rest(parent).basis
	var local := pr.inverse() * rot * pr * _skeleton.get_bone_rest(i).basis
	_skeleton.set_bone_pose_rotation(i, local.get_rotation_quaternion())


## Optional Blender-authored clips that were exported inside the GLB ([] when there are none).
static func get_clip_names() -> PackedStringArray:
	_ensure_library()
	var out: PackedStringArray = []
	for k: String in _anims.keys():
		out.append(k)
	out.sort()
	return out


## AnimationPlayer with the GLB clips bound to this skeleton (created on demand; null when the GLB
## has no clips). The game's main animation is the procedural HumanoidAnimator - this is an extra.
func get_animation_player() -> AnimationPlayer:
	_build()
	if _skeleton == null or _anims.is_empty():
		return null
	if _anim_player != null and is_instance_valid(_anim_player):
		return _anim_player
	_anim_player = AnimationPlayer.new()
	_anim_player.name = "ClipPlayer"
	add_child(_anim_player)
	_anim_player.root_node = _anim_player.get_path_to(self)
	var lib := AnimationLibrary.new()
	for k: String in _anims.keys():
		lib.add_animation(k, _anims[k])
	_anim_player.add_animation_library("", lib)
	return _anim_player


static func to_color(v: Variant, fallback: Color = Color.MAGENTA) -> Color:
	if v is Color:
		return v
	if v is String or v is StringName:
		var s := str(v)
		if s != "" and Color.html_is_valid(s):
			return Color.html(s)
	return fallback


static func color_to_str(c: Color) -> String:
	return "#" + c.to_html(false)


## Fills in defaults / outfit defaults and converts colours to "#rrggbb" strings.
static func normalize_appearance(a: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULT_APPEARANCE.duplicate()
	var outfit := str(a.get("outfit", "")).to_lower()
	if outfit != "" and OUTFITS.has(outfit):
		var od: Dictionary = OUTFITS[outfit]
		for k: String in od.keys():
			out[k] = od[k]
	for k: Variant in a.keys():
		var key := str(k)
		var v: Variant = a[k]
		if v == null:
			continue
		if key.ends_with("_color") or key == "skin" or key == "gloves":
			if v is Color:
				out[key] = color_to_str(v)
			else:
				var s := str(v)
				if s == "" or Color.html_is_valid(s):
					out[key] = ("#" + Color.html(s).to_html(false)) if s != "" else ""
		else:
			out[key] = str(v).to_lower()
	if str(out["body"]) != "f":
		out["body"] = "m"
	if str(out["hair"]) == "":
		out["hair"] = "bald"
	if str(out["skin"]) == "":
		out["skin"] = DEFAULT_APPEARANCE["skin"]
	return out


## Deterministic appearance for an archetype without needing a visual (spawners, save data, UI).
static func make_appearance(archetype: String, rng_seed: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(rng_seed) ^ 0x5bd1e995
	var raw := archetype.to_lower()
	var arch := resolve_archetype(raw)
	if arch == "civilian":
		arch = "civilian_m" if rng.randf() < 0.5 else "civilian_f"
	var gang_variant := 0
	if arch == "gang" and (raw.ends_with("_b") or raw.ends_with("2")):
		gang_variant = 1
	if arch == "player_default":
		return normalize_appearance({
			"body": "m", "skin": "#dda77b", "hair": "short", "hair_color": "#3a2a1e", "beard": "",
			"top": "jacket", "top_color": "#22a7a0", "top_accent_color": "#f5f3ee",
			"bottom": "jeans", "bottom_color": "#27405f", "shoes": "sneakers", "shoes_color": "#e9e7e1",
		})
	var a: Dictionary = {}
	var female := false
	match arch:
		"civilian_f":
			female = true
		"civilian_m":
			female = false
		_:
			female = rng.randf() < 0.42
	if arch == "gang":
		female = rng.randf() < 0.25
	a["body"] = "f" if female else "m"
	a["skin"] = _pick(rng, SKIN_TONES)
	a["hair_color"] = _pick(rng, HAIR_COLORS_FUN) if rng.randf() < 0.05 else _pick(rng, HAIR_COLORS)
	a["eye_color"] = _pick(rng, EYE_COLORS)
	if female:
		a["hair"] = _weighted(rng, {"long": 25, "ponytail": 19, "bob": 17, "bun": 11, "curly": 12, "short": 9, "slick": 2, "buzz": 3, "mohawk": 2})
		a["beard"] = ""
	else:
		a["hair"] = _weighted(rng, {"short": 27, "buzz": 16, "slick": 15, "curly": 12, "bald": 10, "long": 6, "ponytail": 5, "bun": 5, "mohawk": 4})
		a["beard"] = _weighted(rng, {"": 62, "full": 14, "goatee": 12, "mustache": 12})
	# uniformed services and office workers keep it tidy
	if arch in ["police", "tactical", "medic", "firefighter", "business"] and str(a["hair"]) == "mohawk":
		a["hair"] = "bun" if female else "buzz"
	match arch:
		"police":
			a["outfit"] = "police"
			a["hat"] = "police" if rng.randf() < 0.85 else ""
			a["glasses"] = "shades" if rng.randf() < 0.3 else ""
			if not female and str(a["hair"]) in ["long", "curly", "bun"]:
				a["hair"] = "short"
		"tactical":
			a["outfit"] = "tactical"
			a["hat"] = "helmet"
			a["glasses"] = "goggles" if rng.randf() < 0.75 else ""
			a["beard"] = ""
		"medic":
			a["outfit"] = "medic"
			a["glasses"] = "round" if rng.randf() < 0.2 else ""
		"firefighter":
			a["outfit"] = "firefighter"
			a["hat"] = "firehelmet" if rng.randf() < 0.9 else ""
		"staff":
			a["outfit"] = "staff"
			a["top_color"] = _pick(rng, ["#efede6", "#3b404b", "#27405f", "#c8443a", "#8fcae8", "#1c1e23"])
			a["top_accent_color"] = _pick(rng, ["#22a7a0", "#ee7e64", "#e2b13c", "#27405f", "#4e9a63", "#3b404b", "#b35a42"])
			a["bottom_color"] = _pick(rng, ["#1c1e23", "#3b404b", "#27405f", "#bfa77a"])
			a["shoes"] = "sneakers" if rng.randf() < 0.7 else "dress"
			a["shoes_color"] = _pick(rng, ["#2a2a2e", "#e9e7e1", "#4a3426"])
			if rng.randf() < 0.25:
				a["hat"] = "cap"
				a["hat_color"] = a["top_accent_color"]
			a["glasses"] = "round" if rng.randf() < 0.18 else ""
		"gang":
			var gc: String = GANG_COLORS[gang_variant % GANG_COLORS.size()]
			a["top"] = _weighted(rng, {"vest": 40, "hoodie": 24, "tank": 20, "tee": 16})
			a["top_color"] = _pick(rng, ["#1c1e23", "#3b404b", "#2a2a2e", "#4a3426"])
			a["top_accent_color"] = gc if str(a["top"]) != "vest" or rng.randf() < 0.5 else "#efede6"
			a["bottom"] = _weighted(rng, {"jeans": 50, "cargo": 35, "shorts": 15})
			a["bottom_color"] = _pick(rng, ["#1c1e23", "#27405f", "#3b404b", "#3f5f8f"])
			a["shoes"] = _weighted(rng, {"boots": 55, "sneakers": 45})
			a["shoes_color"] = _pick(rng, ["#1c1e23", "#2a2a2e", "#e9e7e1"])
			a["hat"] = _weighted(rng, {"bandana": 44, "beanie": 12, "cap": 10, "": 34})
			a["hat_color"] = gc
			if str(a["hat"]) == "" and rng.randf() < 0.45:
				a["hair"] = "mohawk"            # the crest only shows without headgear
				if rng.randf() < 0.5:
					a["hair_color"] = gc
			a["glasses"] = "shades" if rng.randf() < 0.3 else ""
		"business":
			a["top"] = "suit"
			a["top_color"] = _pick(rng, SUIT_COLORS)
			a["top_accent_color"] = _pick(rng, ["#f5f3ee", "#f5f3ee", "#8fcae8", "#e89aae"])
			a["bottom"] = "skirt" if (female and rng.randf() < 0.35) else "slacks"
			a["bottom_color"] = a["top_color"]
			a["shoes"] = "dress"
			a["shoes_color"] = _pick(rng, ["#1c1e23", "#4a3426", "#2a2a2e"])
			a["glasses"] = _weighted(rng, {"": 60, "round": 22, "shades": 18})
			if not female and str(a["hair"]) in ["long", "ponytail"]:
				a["hair"] = "slick"
		"beach":
			a["top"] = _weighted(rng, {"tank": 55, "tee": 45})
			a["top_color"] = _pick(rng, ["#ee7e64", "#22a7a0", "#e8c24a", "#efede6", "#e89aae", "#8fcae8", "#f0802f"])
			a["bottom"] = "shorts" if not female or rng.randf() < 0.6 else "skirt"
			a["bottom_color"] = _pick(rng, ["#22a7a0", "#c8443a", "#27405f", "#e8c24a", "#efede6", "#3f7fc8"])
			a["shoes"] = "sneakers"
			a["shoes_color"] = _pick(rng, ["#e9e7e1", "#c8443a", "#22a7a0"])
			a["hat"] = _weighted(rng, {"": 45, "cap": 25, "brim": 30})
			a["hat_color"] = _pick(rng, HAT_COLORS)
			a["glasses"] = "shades" if rng.randf() < 0.5 else ""
		_:
			# civilians
			var tops := {"tee": 30, "shirt": 18, "hoodie": 15, "jacket": 14, "tank": 9, "suit": 8, "vest": 2}
			a["top"] = _weighted(rng, tops)
			a["top_color"] = _pick(rng, TOP_COLORS)
			var top := str(a["top"])
			if top == "suit":
				a["top_color"] = _pick(rng, SUIT_COLORS)
				a["top_accent_color"] = _pick(rng, ["#f5f3ee", "#f5f3ee", "#8fcae8"])
				a["bottom"] = "skirt" if (female and rng.randf() < 0.3) else "slacks"
				a["bottom_color"] = a["top_color"] if rng.randf() < 0.75 else _pick(rng, SUIT_COLORS)
				a["shoes"] = "dress"
				a["shoes_color"] = _pick(rng, ["#1c1e23", "#4a3426", "#2a2a2e"])
			else:
				if female:
					a["bottom"] = _weighted(rng, {"jeans": 36, "shorts": 20, "skirt": 24, "slacks": 12, "cargo": 8})
				else:
					a["bottom"] = _weighted(rng, {"jeans": 44, "shorts": 22, "cargo": 20, "slacks": 14})
				a["bottom_color"] = _pick(rng, BOTTOM_COLORS)
				var bottom := str(a["bottom"])
				if bottom == "slacks":
					a["shoes"] = _weighted(rng, {"dress": 60, "sneakers": 40})
				elif bottom == "cargo":
					a["shoes"] = _weighted(rng, {"boots": 55, "sneakers": 45})
				else:
					a["shoes"] = _weighted(rng, {"sneakers": 72, "boots": 20, "dress": 8})
				a["shoes_color"] = _pick(rng, SHOE_COLORS)
				if top in ["jacket", "vest"]:
					a["top_accent_color"] = _pick(rng, ["#f5f3ee", "#efede6", "#1c1e23", "#3b404b", "#e8c24a", "#c8443a"])
			a["hat"] = _weighted(rng, {"": 76, "cap": 12, "beanie": 6, "brim": 6})
			a["hat_color"] = _pick(rng, HAT_COLORS)
			a["glasses"] = _weighted(rng, {"": 80, "shades": 11, "round": 9})
	return normalize_appearance(a)


## Maps any archetype-like id of another module ("swat", "police_officer", "shopkeeper", "gang_b",
## "taxi_driver", "civilian_female" ...) to one of ARCHETYPES, or to "civilian" (either gender) when
## nothing more specific matches. Never fails: unknown ids become ordinary civilians.
static func resolve_archetype(archetype: String) -> String:
	var a := archetype.to_lower()
	if ARCHETYPES.has(a):
		return a
	if a == "player":
		return "player_default"
	for rule: Array in [
			[["swat", "tactical", "armed", "soldier", "riot"], "tactical"],
			[["police", "cop", "officer", "sheriff", "patrol"], "police"],
			[["medic", "doctor", "nurse", "ambulance"], "medic"],
			[["fire"], "firefighter"],
			[["staff", "shop", "clerk", "vendor", "cashier", "keeper", "mechanic", "barber", "waiter", "bartender"], "staff"],
			[["gang", "thug", "criminal", "dealer", "hostile"], "gang"],
			[["business", "office", "suit", "banker"], "business"],
			[["beach", "tourist", "surfer", "swim"], "beach"],
			[["female", "woman", "_f"], "civilian_f"],
			[["male", "man", "_m"], "civilian_m"]]:
		for key: String in rule[0]:
			if key.begins_with("_"):
				if a.ends_with(key):
					return str(rule[1])
			elif a.contains(key):
				return str(rule[1])
	return "civilian"


# =================================================================================================
# internals
# =================================================================================================

static func _pick(rng: RandomNumberGenerator, list: Variant) -> String:
	var n: int = list.size()
	return str(list[rng.randi() % n])


static func _weighted(rng: RandomNumberGenerator, table: Dictionary) -> String:
	var total := 0.0
	for k: Variant in table.keys():
		total += float(table[k])
	var r := rng.randf() * total
	for k: Variant in table.keys():
		r -= float(table[k])
		if r <= 0.0:
			return str(k)
	return str(table.keys()[0])


static func _ensure_library() -> bool:
	if _lib_state == 1:
		return true
	if _lib_state == -1:
		return false
	_lib_state = -1
	if not ResourceLoader.exists(MODEL_PATH):
		push_error("CharacterVisual: character model missing: " + MODEL_PATH)
		return false
	var ps := load(MODEL_PATH) as PackedScene
	if ps == null:
		push_error("CharacterVisual: could not load " + MODEL_PATH)
		return false
	var inst := ps.instantiate()
	var skel := _find_skeleton_in(inst)
	if skel == null:
		push_error("CharacterVisual: no Skeleton3D in " + MODEL_PATH)
		inst.free()
		return false
	_bones.clear()
	for i in skel.get_bone_count():
		_bones.append({"name": skel.get_bone_name(i), "parent": skel.get_bone_parent(i), "rest": skel.get_bone_rest(i)})
	for b: String in _CONTRACT_BONES:
		if skel.find_bone(b) < 0:
			push_error("CharacterVisual: contract bone '%s' missing in %s" % [b, MODEL_PATH])
	var xf := Transform3D.IDENTITY
	var n: Node = skel
	while n != null and n != inst:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	_skel_xform = xf
	var meshes: Array[Node] = inst.find_children("*", "MeshInstance3D", true, false)
	for node: Node in meshes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var part_name := String(mi.name)
		var surfaces: Array = []
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			var mname := mat.resource_name if mat != null else ""
			if mname.begins_with("M_"):
				surfaces.append([s, mname])
				if not _base_mats.has(mname):
					_base_mats[mname] = mat
		var tokens := part_name.split("_")
		var slot := tokens[0].to_lower()
		var id := tokens[1].to_lower() if tokens.size() > 1 else ""
		var variant := tokens[2].to_lower() if tokens.size() > 2 else ""
		_lib[part_name] = {"mesh": mi.mesh, "skin": mi.skin, "slot": slot, "surfaces": surfaces}
		if not _index.has(slot):
			_index[slot] = {}
		if not (_index[slot] as Dictionary).has(id):
			_index[slot][id] = {}
		_index[slot][id][variant] = part_name
	# optional Blender clips: retarget the track paths to <visual>/Armature/Skeleton3D
	var players: Array[Node] = inst.find_children("*", "AnimationPlayer", true, false)
	for pn: Node in players:
		var ap := pn as AnimationPlayer
		for anim_name: StringName in ap.get_animation_list():
			var src := ap.get_animation(anim_name)
			if src == null:
				continue
			var anim := src.duplicate() as Animation
			for t in anim.get_track_count():
				var path := anim.track_get_path(t)
				if path.get_subname_count() > 0:
					anim.track_set_path(t, NodePath("Armature/Skeleton3D:" + path.get_concatenated_subnames()))
			var clean := String(anim_name)
			if clean.contains("/"):
				clean = clean.get_slice("/", clean.get_slice_count("/") - 1)
			if not clean.begins_with(CLIP_PREFIX):
				continue            # not one of ours (foreign action that leaked into the export)
			clean = clean.trim_prefix(CLIP_PREFIX)
			anim.loop_mode = Animation.LOOP_LINEAR
			_anims[clean] = anim
	inst.free()
	_lib_state = 1
	return true


static func _find_skeleton_in(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var s := _find_skeleton_in(c)
		if s != null:
			return s
	return null


static func _resolve_part(slot: String, id: String, body: String, prefer: String = "") -> String:
	var by_slot: Dictionary = _index.get(slot, {})
	if not by_slot.has(id):
		return ""
	var by_var: Dictionary = by_slot[id]
	if prefer != "" and by_var.has(prefer):
		return by_var[prefer]
	if by_var.has(body):
		return by_var[body]
	if by_var.has(""):
		return by_var[""]
	for v: String in ["f", "m"]:
		if by_var.has(v):
			return by_var[v]
	return ""


static func _material_for(base_name: String, color: Color, cache_tag: String = "") -> Material:
	var key := base_name + cache_tag + color.to_html(false)
	var cached: Variant = _mat_cache.get(key, null)
	if cached != null:
		return cached as Material
	var base: Variant = _base_mats.get(base_name, null)
	var m: Material = null
	if base is BaseMaterial3D:
		var d := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
		d.albedo_color = color
		m = d
	else:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = color
		sm.roughness = 0.8
		m = sm
	m.resource_name = base_name
	_mat_cache[key] = m
	return m


func _build() -> void:
	if _skeleton != null:
		return
	# adopt an existing rig (this node was duplicated together with its children)
	var existing := get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if existing != null:
		_armature = get_node("Armature") as Node3D
		_skeleton = existing
		_ensure_library()
		for c in _skeleton.get_children():
			if c is MeshInstance3D:
				_parts[String(c.name)] = c
			elif c is BoneAttachment3D:
				_attachments[String((c as BoneAttachment3D).bone_name)] = c
		return
	if not _ensure_library():
		return
	_armature = Node3D.new()
	_armature.name = "Armature"
	add_child(_armature)
	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton3D"
	_armature.add_child(_skeleton)
	_skeleton.transform = _skel_xform
	for b: Dictionary in _bones:
		_skeleton.add_bone(str(b["name"]))
	for i in _bones.size():
		var b: Dictionary = _bones[i]
		_skeleton.set_bone_parent(i, int(b["parent"]))
		_skeleton.set_bone_rest(i, b["rest"])
	_skeleton.reset_bone_poses()


func _wanted_parts() -> Dictionary:
	# part name -> slot
	var want: Dictionary = {}
	var a := _current
	var body := str(a.get("body", "m"))
	var outfit := str(a.get("outfit", ""))
	var hat := str(a.get("hat", ""))
	# "Head_M" / "Head_F" are indexed as slot "head", id = body; "Hands" as slot "hands", id ""
	var head := _resolve_part("head", body, body)
	if head != "":
		want[head] = "head"
	var hands := _resolve_part("hands", "", body)
	if hands != "":
		want[hands] = "hands"
	var hair := str(a.get("hair", "bald"))
	if hair != "" and hair != "bald":
		var hat_part := _resolve_part("hat", hat, body) if hat != "" else ""
		if hat_part != "":
			# under a hat only the "<Hair>_Hat" variant (hair below the hat rim) is shown
			var by_var: Dictionary = ((_index.get("hair", {}) as Dictionary).get(hair, {}) as Dictionary)
			if by_var.is_empty():
				push_warning("CharacterVisual: no part for hair '%s'" % hair)
			elif by_var.has("hat"):
				want[by_var["hat"]] = "hair"
		else:
			_want(want, "hair", hair, body)
	_want(want, "beard", str(a.get("beard", "")), body)
	if outfit != "" and _resolve_part("outfit", outfit, body) != "":
		_want(want, "outfit", outfit, body)
	else:
		if outfit != "":
			push_warning("CharacterVisual: unknown outfit '%s'" % outfit)
		_want(want, "top", str(a.get("top", "tee")), body)
		_want(want, "bottom", str(a.get("bottom", "jeans")), body)
	_want(want, "shoes", str(a.get("shoes", "sneakers")), body)
	_want(want, "hat", hat, body)
	_want(want, "glasses", str(a.get("glasses", "")), body)
	return want


func _want(want: Dictionary, slot: String, id: String, body: String) -> void:
	if id == "":
		return
	var part := _resolve_part(slot, id, body)
	if part == "":
		push_warning("CharacterVisual: no part for %s '%s'" % [slot, id])
		return
	want[part] = slot


func _rebuild_parts() -> void:
	var want := _wanted_parts()
	for part_name: String in _parts.keys():
		if not want.has(part_name):
			var old: MeshInstance3D = _parts[part_name]
			_parts.erase(part_name)
			if is_instance_valid(old):
				if old.get_parent() != null:
					old.get_parent().remove_child(old)
				old.queue_free()
	for part_name: String in want.keys():
		if _parts.has(part_name) and is_instance_valid(_parts[part_name]):
			continue
		var entry: Dictionary = _lib.get(part_name, {})
		if entry.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = part_name
		mi.mesh = entry["mesh"]
		mi.skin = entry["skin"]
		_skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
		mi.set_meta("slot", want[part_name])
		_parts[part_name] = mi
	_apply_colors()
	_refresh_visibility()


func _apply_colors() -> void:
	var a := _current
	var skin := to_color(a.get("skin"), Color.html("#dda77b"))
	var hair := to_color(a.get("hair_color"), Color.html("#3a2a1e"))
	var top := to_color(a.get("top_color"), Color.html("#3f7fc8"))
	var accent := _accent_color(a, top)
	var colors: Dictionary = {
		"M_Skin": skin,
		"M_Hair": hair,
		"M_Top": top,
		"M_Top_Accent": accent,
		"M_Bottom": to_color(a.get("bottom_color"), Color.html("#3f5f8f")),
		"M_Shoes": to_color(a.get("shoes_color"), Color.html("#2a2a2e")),
		"M_Hat": to_color(a.get("hat_color"), Color.html("#c8443a")),
		"M_Eyes": to_color(a.get("eye_color"), Color.html("#2a1c14")),
		"M_Mouth": skin.lerp(Color.html("#9a3d3d"), 0.5 if str(a.get("body", "m")) == "f" else 0.38),
	}
	var gloves := str(a.get("gloves", ""))
	for part_name: String in _parts.keys():
		var mi: MeshInstance3D = _parts[part_name]
		var entry: Dictionary = _lib.get(part_name, {})
		if entry.is_empty():
			continue
		var is_hands := str(entry["slot"]) == "hands"
		for sm: Array in entry["surfaces"]:
			var s_idx: int = sm[0]
			var mname: String = sm[1]
			if not colors.has(mname):
				continue
			if is_hands and mname == "M_Skin" and gloves != "":
				mi.set_surface_override_material(s_idx, _material_for("M_Top", to_color(gloves, Color.html("#202328")), "glove"))
			else:
				mi.set_surface_override_material(s_idx, _material_for(mname, colors[mname]))


func _accent_color(a: Dictionary, top: Color) -> Color:
	var given := str(a.get("top_accent_color", ""))
	if given != "" and Color.html_is_valid(given):
		return Color.html(given)
	if str(a.get("outfit", "")) == "staff":
		return Color.html("#22a7a0")
	match str(a.get("top", "tee")):
		"jacket", "vest", "suit":
			return Color.html("#f5f3ee") if top.get_luminance() < 0.6 else Color.html("#3b404b")
		"shirt":
			return top.lightened(0.22)
		"hoodie":
			return Color.html("#efede6") if top.get_luminance() < 0.55 else top.darkened(0.45)
		_:
			return top.darkened(0.28) if top.get_luminance() > 0.6 else top.lightened(0.5)


func _refresh_visibility() -> void:
	for part_name: String in _parts.keys():
		var mi: MeshInstance3D = _parts[part_name]
		if not is_instance_valid(mi):
			continue
		var slot := str(mi.get_meta("slot", ""))
		var small := slot == "glasses" or slot == "beard"
		var is_head := _HEAD_SLOTS.has(slot)
		mi.visible = not (small and _lod >= 1)
		var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if _lod >= 2 or (_lod == 1 and not _BIG_SLOTS.has(slot)) or small:
			shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if is_head and not _head_visible:
			shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if not small else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visible = not small
		mi.cast_shadow = shadow
