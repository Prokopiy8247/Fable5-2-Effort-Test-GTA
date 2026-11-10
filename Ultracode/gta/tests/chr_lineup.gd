extends Node
## CHARACTER module test: a line-up of the shared modular humanoid in every archetype.
##
##   tools\godot.ps1 -Mode headless -Frames 600 -UserArgs '--test=chr_lineup','--no_player','--disable=world,traffic,peds,police'
##   tools\godot.ps1 -Mode window   -Frames 240 -UserArgs '--test=chr_lineup','--no_player','--disable=world,traffic,peds,police'
##
## The windowed run saves qa/screenshots/chr_lineup.png (+ _close, _close2, _back, _poses, _clips,
## _variety, _faces, _faces2, _grip).
## The stage (floor, backdrop, lights, camera) is test scaffolding, not game content.

const SCENE := "res://gta/scenes/characters/humanoid.tscn"
const ORIGIN := Vector3(0.0, 300.0, 0.0)
const LINEUP := [
	["player_default", 0], ["civilian_m", 11], ["civilian_f", 7], ["police", 3], ["tactical", 5], ["medic", 2],
	["firefighter", 4], ["staff", 9], ["gang", 6], ["business", 8], ["beach", 12], ["civilian_f", 21],
]
const BONES := ["Root", "Hips", "Spine", "Chest", "Neck", "Head",
	"Shoulder_L", "UpperArm_L", "LowerArm_L", "Hand_L", "Shoulder_R", "UpperArm_R", "LowerArm_R", "Hand_R",
	"UpperLeg_L", "LowerLeg_L", "Foot_L", "UpperLeg_R", "LowerLeg_R", "Foot_R"]

# hand-made poses (model axes: X right, F forward, U up; degrees), applied in order
const POSES := {
	"walk": {"UpperArm_R": [["F", 76], ["X", 28]], "UpperArm_L": [["F", -76], ["X", -28]],
		"LowerArm_R": [["U", 20]], "LowerArm_L": [["U", -38]],
		"UpperLeg_R": [["X", -24]], "LowerLeg_R": [["X", -30]], "UpperLeg_L": [["X", 30]], "LowerLeg_L": [["X", -12]],
		"Foot_L": [["X", 10]], "Foot_R": [["X", -20]], "Spine": [["X", 4]]},
	"seated": {"UpperLeg_R": [["X", 88]], "UpperLeg_L": [["X", 88]], "LowerLeg_R": [["X", -86]], "LowerLeg_L": [["X", -86]],
		"UpperArm_R": [["F", 50], ["U", 40]], "UpperArm_L": [["F", -50], ["U", -40]],
		"LowerArm_R": [["U", 45]], "LowerArm_L": [["U", -45]], "Spine": [["X", -4]]},
	"aim": {"UpperArm_R": [["U", 82], ["F", 4]], "UpperArm_L": [["U", -62], ["F", -6]],
		"LowerArm_R": [["U", 8]], "LowerArm_L": [["U", -48]], "Head": [["X", 3]], "Chest": [["U", -8]]},
	"crouch": {"UpperLeg_R": [["X", 70]], "UpperLeg_L": [["X", 40]], "LowerLeg_R": [["X", -110]], "LowerLeg_L": [["X", -100]],
		"Spine": [["X", 18]], "UpperArm_R": [["F", 70]], "UpperArm_L": [["F", -70]]},
}

# explicit looks: every hair style + the reworked tops (second little stage, 40 m to the side)
const VARIETY := [
	{"body": "m", "skin": "#b97c54", "hair": "short", "hair_color": "#22201f", "top": "tank", "top_color": "#ee7e64",
		"bottom": "shorts", "bottom_color": "#27405f", "shoes": "sneakers", "shoes_color": "#e9e7e1"},
	{"body": "f", "skin": "#f2c9a5", "hair": "bob", "hair_color": "#a6452a", "top": "jacket", "top_color": "#e2b13c",
		"top_accent_color": "#1c1e23", "bottom": "skirt", "bottom_color": "#3b404b", "shoes": "boots", "shoes_color": "#1c1e23"},
	{"body": "m", "skin": "#dda77b", "hair": "mohawk", "hair_color": "#22a7a0", "beard": "goatee", "top": "vest", "top_color": "#1c1e23",
		"top_accent_color": "#7a50d0", "bottom": "cargo", "bottom_color": "#3b404b", "shoes": "boots", "shoes_color": "#1c1e23"},
	{"body": "f", "skin": "#8a5636", "hair": "bun", "hair_color": "#22201f", "top": "tank", "top_color": "#22a7a0",
		"bottom": "shorts", "bottom_color": "#efede6", "shoes": "sneakers", "shoes_color": "#c8443a", "glasses": "shades"},
	{"body": "m", "skin": "#f2c9a5", "hair": "slick", "hair_color": "#3a2a1e", "top": "suit", "top_color": "#3b404b",
		"top_accent_color": "#f5f3ee", "bottom": "slacks", "bottom_color": "#3b404b", "shoes": "dress", "shoes_color": "#1c1e23", "glasses": "round"},
	{"body": "f", "skin": "#e8b88f", "hair": "long", "hair_color": "#d9b56a", "top": "shirt", "top_color": "#efede6",
		"top_accent_color": "#8fcae8", "bottom": "jeans", "bottom_color": "#3f5f8f", "shoes": "sneakers", "shoes_color": "#e9e7e1"},
	{"body": "m", "skin": "#5e3a26", "hair": "bun", "hair_color": "#22201f", "beard": "full", "top": "hoodie", "top_color": "#7a50d0",
		"top_accent_color": "#e8c24a", "bottom": "jeans", "bottom_color": "#1c1e23", "shoes": "sneakers", "shoes_color": "#e9e7e1"},
	{"body": "f", "skin": "#c98f63", "hair": "ponytail", "hair_color": "#5a3a25", "top": "tee", "top_color": "#e89aae",
		"bottom": "cargo", "bottom_color": "#bfa77a", "shoes": "boots", "shoes_color": "#4a3426", "hat": "cap", "hat_color": "#22a7a0"},
	{"body": "m", "skin": "#c98f63", "hair": "curly", "hair_color": "#3a2a1e", "beard": "mustache", "top": "shirt", "top_color": "#4e9a63",
		"bottom": "slacks", "bottom_color": "#bfa77a", "shoes": "dress", "shoes_color": "#4a3426"},
]
const VARIETY_X := 40.0
const WEAPON_DIR := "res://gta/generated/models/weapons/"
const ANIMATOR_SCRIPT := "res://gta/code/characters/humanoid_animator.gd"

var _stage: Node3D
var _variety: Array[Node3D] = []
var _grip: Array[Node3D] = []
var _cam: Camera3D
var _wall: MeshInstance3D
var _sun: DirectionalLight3D
var _chars: Array[Node3D] = []
var _extras: Array[Node3D] = []
var _clip_chars: Array[Node3D] = []


func _ready() -> void:
	var t := TestHarness
	await t.wait_frames(4)
	if not t.check(ResourceLoader.exists(SCENE), "humanoid.tscn exists"):
		t.finish(false, "humanoid scene missing")
		return
	var ps := load(SCENE) as PackedScene
	if not t.check(ps != null, "humanoid.tscn loads"):
		t.finish(false, "humanoid scene does not load")
		return
	_build_stage()

	# --- spawn the line-up -------------------------------------------------------------------
	var t0 := Time.get_ticks_usec()
	for i in LINEUP.size():
		var arch: String = LINEUP[i][0]
		var v := ps.instantiate() as Node3D
		v.name = "Char_%02d_%s" % [i, arch]
		_stage.add_child(v)
		var row := i / 6
		var colm := i % 6
		v.position = Vector3((colm - 2.5) * 0.98 + (0.3 if row == 1 else 0.0), 0.55 * row, 1.55 * row)
		v.call("randomize_appearance", arch, int(LINEUP[i][1]))
		v.call("set_static_pose", "relaxed")
		_chars.append(v)
	var spawn_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t.log_line("spawned %d characters in %.2f ms (first one builds the shared part library)" % [_chars.size(), spawn_ms])
	await t.wait_frames(3)

	# --- per character checks -----------------------------------------------------------------
	var skins: Dictionary = {}
	var total_parts := 0
	for i in _chars.size():
		var v := _chars[i]
		var arch: String = LINEUP[i][0]
		var skel := v.call("get_skeleton") as Skeleton3D
		var ok := skel != null and skel.get_bone_count() == BONES.size()
		if ok:
			for b in BONES.size():
				if skel.get_bone_name(b) != BONES[b]:
					ok = false
		t.check(ok, "%s: skeleton has the 20 contract bones in order" % v.name)
		if skel == null:
			continue
		var parts: PackedStringArray = v.call("get_active_parts")
		total_parts += parts.size()
		var meshes := 0
		var colored := true
		for c in skel.get_children():
			if c is MeshInstance3D:
				meshes += 1
				var mi := c as MeshInstance3D
				if mi.mesh == null or mi.skin == null:
					colored = false
					continue
				skins[mi.skin] = true
				for s in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(s)
					if m != null and m.resource_name.begins_with("M_") and mi.get_surface_override_material(s) == null:
						colored = false
		t.check(parts.size() >= 5 and parts.size() <= 10 and meshes == parts.size(),
				"%s: wears %d parts %s" % [v.name, parts.size(), str(parts)])
		t.check(colored, "%s: every part is skinned and every contract material is recoloured" % v.name)
		var app: Dictionary = v.call("get_appearance")
		if arch in ["police", "tactical", "medic", "firefighter", "staff"]:
			t.check(str(app.get("outfit", "")) == arch and _has_prefix(parts, "Outfit_"), "%s: full outfit '%s' is worn" % [v.name, arch])
		else:
			t.check(_has_prefix(parts, "Top_") and _has_prefix(parts, "Bottom_"), "%s: has a top and a bottom" % v.name)
		t.check(_has_prefix(parts, "Head_") and _has_prefix(parts, "Shoes_") and parts.has("Hands"), "%s: head, hands and shoes present" % v.name)
	t.log_line("average parts per character: %.1f, distinct Skin resources in use: %d" % [float(total_parts) / maxf(1.0, _chars.size()), skins.size()])
	t.check(skins.size() == 1, "all parts share one Skin resource (one skeleton binding per character)")

	# --- API checks on one extra character ---------------------------------------------------
	var probe := ps.instantiate() as Node3D
	probe.name = "Probe"
	_stage.add_child(probe)
	probe.position = Vector3(0.0, 0.0, 6.0)
	var a1: Dictionary = CharacterVisual.make_appearance("civilian_m", 5)
	var a2: Dictionary = CharacterVisual.make_appearance("civilian_m", 5)
	var a3: Dictionary = CharacterVisual.make_appearance("civilian_m", 6)
	t.check(a1 == a2, "make_appearance is deterministic for the same seed")
	t.check(a1 != a3, "different seeds give different looks")
	var alias_ok := true
	for pair: Array in [["swat", "tactical"], ["police_officer", "police"], ["shopkeeper", "staff"], ["gang_b", "gang"],
			["paramedic", "medic"], ["fireman", "firefighter"], ["office_worker", "business"], ["civilian_female", "civilian_f"],
			["taxi_driver", "civilian"], ["player", "player_default"], ["tactical", "tactical"]]:
		if CharacterVisual.resolve_archetype(pair[0]) != pair[1]:
			alias_ok = false
			t.log_line("archetype alias %s -> %s (expected %s)" % [pair[0], CharacterVisual.resolve_archetype(pair[0]), pair[1]])
	t.check(alias_ok, "foreign archetype ids map onto the visual archetypes")
	t.check(str(CharacterVisual.make_appearance("swat", 1).get("outfit", "")) == "tactical"
			and str(CharacterVisual.make_appearance("some_unknown_id", 1).get("outfit", "x")) == "", "aliases and unknown ids produce valid looks")
	probe.call("apply_appearance", {"body": "f", "hair": "long", "top": "hoodie", "top_color": Color(0.9, 0.2, 0.2),
		"bottom": "skirt", "shoes": "boots", "hat": "beanie", "glasses": "round"})
	var parts_a: PackedStringArray = probe.call("get_active_parts")
	t.check(parts_a.has("Top_Hoodie_F") and parts_a.has("Bottom_Skirt_F") and parts_a.has("Hat_Beanie")
			and parts_a.has("Hair_Long_Hat") and parts_a.has("Glasses_Round") and parts_a.has("Head_F"),
			"explicit appearance picks the right part variants: " + str(parts_a))
	var got: Dictionary = probe.call("get_appearance")
	t.check(str(got.get("top_color", "")) == "#e63333", "colours come back as html strings (%s)" % str(got.get("top_color", "")))
	probe.call("apply_appearance", got)
	t.check(probe.call("get_active_parts") == parts_a, "apply_appearance(get_appearance()) is a no-op round trip")
	probe.call("update_appearance", {"hat": "", "top": "tank"})
	var parts_b: PackedStringArray = probe.call("get_active_parts")
	t.check(parts_b.has("Hair_Long") and not parts_b.has("Hat_Beanie") and parts_b.has("Top_Tank_F"), "update_appearance swaps single parts: " + str(parts_b))
	var att := probe.call("get_bone_attachment", "Hand_R") as Node3D
	t.check(att is BoneAttachment3D and att == probe.call("get_bone_attachment", "Hand_R"), "get_bone_attachment returns a cached BoneAttachment3D")
	probe.call("update_appearance", {"glasses": "shades"})
	probe.call("set_lod", 2)
	var gl := probe.call("get_part_node", "Glasses_Shades") as MeshInstance3D
	t.check(gl != null and not gl.visible, "set_lod(2) hides small accessories")
	probe.call("set_lod", 0)
	t.check(gl != null and gl.visible, "set_lod(0) shows them again")
	var opts: Dictionary = probe.call("get_part_options")
	t.check(opts.has("hair") and (opts["hair"] as Array).size() >= 7 and (opts["top"] as Array).size() >= 6
			and (opts["bottom"] as Array).size() >= 4 and (opts["shoes"] as Array).size() >= 3
			and (opts["hat"] as Array).size() >= 4 and (opts["glasses"] as Array).size() >= 3 and (opts["outfit"] as Array).size() >= 6,
			"get_part_options lists every slot: " + str(opts.get("top", [])) + str(opts.get("hair", [])))
	# shared materials
	var p2 := ps.instantiate() as Node3D
	_stage.add_child(p2)
	p2.position = Vector3(1.0, 0.0, 6.0)
	p2.call("apply_appearance", probe.call("get_appearance"))
	var h1 := probe.call("get_part_node", "Head_F") as MeshInstance3D
	var h2 := p2.call("get_part_node", "Head_F") as MeshInstance3D
	t.check(h1 != null and h2 != null and h1.get_surface_override_material(0) == h2.get_surface_override_material(0),
			"characters with the same colours share the same material instances")
	# duplicate() keeps working (ragdoll fallback path)
	var dup := probe.duplicate() as Node3D
	_stage.add_child(dup)
	dup.position = Vector3(2.0, 0.0, 6.0)
	var dskel := dup.call("get_skeleton") as Skeleton3D
	t.check(dskel != null and dskel.get_bone_count() == 20 and (dup.call("get_active_parts") as PackedStringArray).size() == (probe.call("get_active_parts") as PackedStringArray).size(),
			"a duplicated visual adopts its copied rig")
	t.check(Registry.count("clothing") >= 20 and Registry.count("hair") >= 10, "appearance registry registered clothing (%d) and hair (%d)" % [Registry.count("clothing"), Registry.count("hair")])
	_extras = [probe, p2, dup]
	# a visual that nobody dresses gets the default look by itself (deferred to the end of the frame)
	var lazy := ps.instantiate() as Node3D
	_stage.add_child(lazy)
	lazy.position = Vector3(3.0, 0.0, 6.0)
	_extras.append(lazy)
	t.check(lazy.call("get_skeleton") != null and (lazy.call("get_active_parts") as PackedStringArray).is_empty(),
			"an undressed visual has its skeleton immediately (parts follow deferred)")
	await t.wait_frames(2)
	t.check((lazy.call("get_active_parts") as PackedStringArray).has("Top_Jacket_M"), "... and wears the default player look one frame later")

	# --- optional Blender-authored clips (Idle / Walk / Run) ------------------------------------
	var clip_names := CharacterVisual.get_clip_names()
	t.log_line("GLB clips: " + str(clip_names))
	if clip_names.size() > 0:
		t.check(clip_names.has("Idle") and clip_names.has("Walk") and clip_names.has("Run"), "the GLB carries the Idle, Walk and Run clips")
		# [archetype, seed, clip, time]
		var plan := [["civilian_m", 31, "Idle", 0.75], ["civilian_f", 32, "Walk", 0.0], ["player_default", 0, "Walk", 0.25],
			["business", 33, "Walk", 0.5], ["police", 34, "Run", 0.1667], ["beach", 35, "Run", 0.5]]
		for i in plan.size():
			var cv := ps.instantiate() as Node3D
			cv.name = "Clip_%d_%s" % [i, plan[i][2]]
			_stage.add_child(cv)
			cv.position = Vector3((i - 2.5) * 1.25, 0.0, 7.5)
			cv.rotation.y = -PI * 0.5            # face +X: the camera sees the gait from the side
			cv.call("randomize_appearance", plan[i][0], plan[i][1])
			var apl := cv.call("get_animation_player") as AnimationPlayer
			if not t.check(apl != null and apl.has_animation(plan[i][2]), "%s: clip '%s' is available through get_animation_player()" % [cv.name, plan[i][2]]):
				continue
			apl.play(plan[i][2])
			apl.seek(float(plan[i][3]), true)
			apl.pause()
			_clip_chars.append(cv)
		await t.wait_frames(2)
		if _clip_chars.size() == plan.size():
			var walk_a := _clip_chars[2].call("get_skeleton") as Skeleton3D      # Walk @ 0.25 s: right leg forward
			var walk_b := _clip_chars[3].call("get_skeleton") as Skeleton3D      # Walk @ 0.50 s: legs passing
			var leg := walk_a.find_bone("UpperLeg_R")
			var qa := walk_a.get_bone_pose_rotation(leg)
			var qb := walk_b.get_bone_pose_rotation(leg)
			var rest_q := walk_a.get_bone_rest(leg).basis.get_rotation_quaternion()
			t.check(rad_to_deg(qa.angle_to(rest_q)) > 15.0 and rad_to_deg(qa.angle_to(qb)) > 15.0,
					"Walk clip moves the legs (UpperLeg_R %.1f deg from rest at 0.25 s, %.1f deg between 0.25 s and 0.5 s)" % [rad_to_deg(qa.angle_to(rest_q)), rad_to_deg(qa.angle_to(qb))])
			var foot_y := walk_a.global_transform * walk_a.get_bone_global_pose(walk_a.find_bone("Foot_R")).origin
			var hips_y := walk_a.get_bone_pose_position(walk_a.find_bone("Hips")).y
			t.check(hips_y > 0.80 and hips_y < 0.96, "Walk clip keeps the hips at a sane height (%.3f m)" % hips_y)
			t.check(foot_y.y - _stage.global_position.y > -0.02, "Walk clip keeps the feet above the ground (ankle %.3f m)" % (foot_y.y - _stage.global_position.y))
			var apl2 := _clip_chars[2].call("get_animation_player") as AnimationPlayer
			var walk_anim := apl2.get_animation("Walk")
			t.check(absf(walk_anim.length - 1.0) < 0.05 and walk_anim.loop_mode == Animation.LOOP_LINEAR, "Walk is a 1.0 s loop (length %.3f)" % walk_anim.length)

	# --- every option of every slot, on both bodies, through apply_appearance ---------------------
	var sweep := ps.instantiate() as Node3D
	sweep.name = "Sweep"
	_stage.add_child(sweep)
	sweep.position = Vector3(4.0, 0.0, 6.0)
	_extras.append(sweep)
	var all_opts: Dictionary = sweep.call("get_part_options", true)
	var applied := 0
	for body: String in ["m", "f"]:
		for slot: String in ["hair", "beard", "top", "bottom", "shoes", "hat", "glasses", "outfit"]:
			var bad: Array = []
			var ids: Array = all_opts.get(slot, [])
			for id: Variant in ids:
				var sid := str(id)
				var look := {"body": body, "hair": "short", "top": "tee", "bottom": "jeans", "shoes": "sneakers"}
				look[slot] = sid
				sweep.call("apply_appearance", look)
				applied += 1
				var act: PackedStringArray = sweep.call("get_active_parts")
				var none := sid == "" or sid == "bald"
				var any_of_slot := false
				var exact := false
				for pn in act:
					var low := pn.to_lower()
					if low.begins_with(slot + "_"):
						any_of_slot = true
						if low == slot + "_" + sid or low.begins_with(slot + "_" + sid + "_"):
							exact = true
				if (none and any_of_slot) or (not none and not exact):
					bad.append(sid)
				var smi := sweep.call("get_part_node", "Hands") as MeshInstance3D
				if smi == null or smi.mesh == null:
					bad.append(sid + ":hands")
			t.check(bad.is_empty() and ids.size() >= 3, "body %s: every '%s' option builds its part (%d ids%s)" % [body, slot, ids.size(), "" if bad.is_empty() else ", FAILED " + str(bad)])
	t.log_line("slot sweep applied %d looks" % applied)

	# --- variety row: every hair style, reworked tops, hands holding weapons ---------------------
	_build_variety_stage()
	var hair_seen: Dictionary = {}
	for i in VARIETY.size():
		var vv := ps.instantiate() as Node3D
		vv.name = "Variety_%02d" % i
		_stage.add_child(vv)
		vv.position = Vector3(VARIETY_X + (i - 4) * 0.9, 0.0, 0.0)
		vv.call("apply_appearance", VARIETY[i])
		vv.call("set_static_pose", "relaxed")
		_variety.append(vv)
		var want := "Hair_" + str(VARIETY[i]["hair"]).capitalize() + ("_Hat" if str(VARIETY[i].get("hat", "")) != "" else "")
		var vparts: PackedStringArray = vv.call("get_active_parts")
		hair_seen[str(VARIETY[i]["hair"])] = vparts.has(want)
		if not vparts.has(want):
			t.log_line("%s: expected %s in %s" % [vv.name, want, str(vparts)])
	var all_hair := true
	for k: String in ["short", "bob", "mohawk", "bun", "slick", "long", "ponytail", "curly"]:
		all_hair = all_hair and bool(hair_seen.get(k, false))
	t.check(all_hair, "every hair style of the variety row resolves to its part " + str(hair_seen))
	var hair_opts: Array = (probe.call("get_part_options") as Dictionary).get("hair", [])
	t.check(hair_opts.has("bob") and hair_opts.has("bun") and hair_opts.has("mohawk") and hair_opts.size() >= 10,
			"new hair styles are offered by get_part_options: " + str(hair_opts))
	t.check(Registry.get_def("hair", "hair_bob") != null and Registry.get_def("hair", "hair_mohawk") != null,
			"registry sells the new hair styles")
	var hands := _variety[0].call("get_part_node", "Hands") as MeshInstance3D
	t.check(hands != null and hands.mesh != null and hands.mesh.get_surface_count() == 1,
			"hands are one skin surface (gloves recolour them as a whole)")
	# three armed characters (weapon models are a soft dependency on the WEAPONS art set)
	var armed := [["player_default", 0, "pistol"], ["police", 3, "carbine"], ["gang", 6, "smg"]]
	var aim_pose := {"UpperArm_R": [["U", 78]], "LowerArm_R": [["X", 90]], "UpperArm_L": [["F", -76]], "LowerArm_L": [["U", -14]]}
	var side_pose := {"UpperArm_R": [["F", 76]], "LowerArm_R": [["U", 14]], "UpperArm_L": [["F", -76]], "LowerArm_L": [["U", -14]]}
	for i in armed.size():
		var gv := ps.instantiate() as Node3D
		gv.name = "Grip_%d_%s" % [i, armed[i][2]]
		_stage.add_child(gv)
		gv.position = Vector3(VARIETY_X + (i - 1) * 1.15, 0.0, -14.0)
		gv.rotation.y = deg_to_rad(-38.0)
		gv.call("randomize_appearance", armed[i][0], int(armed[i][1]))
		_apply_named_pose(gv, aim_pose if i < 2 else side_pose)
		var wpath := WEAPON_DIR + str(armed[i][2]) + ".glb"
		if ResourceLoader.exists(wpath):
			var wps := load(wpath) as PackedScene
			var socket := gv.call("get_bone_attachment", "Hand_R") as Node3D
			if wps != null and socket != null:
				var w := wps.instantiate() as Node3D
				socket.add_child(w)
				w.transform = _grip_transform(gv)
				for c in w.find_children("Att_*", "", true, false) + w.find_children("Col_*", "", true, false):
					if c is Node3D:
						(c as Node3D).visible = false
		else:
			t.log_line("weapon model missing (not an error for this test): " + wpath)
		_grip.append(gv)
	var g_att := _grip[0].call("get_grip_transform", "Hand_R") as Transform3D
	t.check(g_att.origin.length() > 0.03 and g_att.origin.length() < 0.2, "get_grip_transform puts the grip in the palm (%.3f m from the wrist)" % g_att.origin.length())
	_grip[0].call("set_head_visible", false)
	var head0 := _grip[0].call("get_part_node", "Head_M") as MeshInstance3D
	t.check(head0 != null and head0.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
			"set_head_visible(false) turns the head into a shadow-only mesh (first person)")
	_grip[0].call("set_head_visible", true)
	t.check(head0 != null and head0.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "set_head_visible(true) restores it")

	# --- screenshots (windowed only) ----------------------------------------------------------
	await t.wait_frames(6)
	_look(Vector3(0.0, 1.55, -5.9), Vector3(0.15, 1.12, 0.6), 39.0)
	await t.wait_frames(6)
	await t.shot("chr_lineup")
	_look(Vector3(-1.45, 1.52, -2.3), Vector3(-1.45, 1.22, 0.0), 40.0)
	await t.wait_frames(4)
	await t.shot("chr_lineup_close")
	_look(Vector3(1.5, 1.52, -2.3), Vector3(1.5, 1.22, 0.0), 40.0)
	await t.wait_frames(4)
	await t.shot("chr_lineup_close2")
	# backs: the backdrop wall and the extra characters behind it are hidden for this one
	_wall.visible = false
	_sun.rotation_degrees = Vector3(-42.0, 25.0, 0.0)      # light the side the camera now looks at
	for e in _extras:
		e.visible = false
	for e in _clip_chars:
		e.visible = false
	_look(Vector3(0.9, 2.5, 7.4), Vector3(0.15, 1.05, 0.9), 39.0)
	await t.wait_frames(4)
	await t.shot("chr_lineup_back")
	_wall.visible = true
	# Blender clips, seen from the side (Idle | Walk x3 | Run x2), in front of the wall's back side
	if _clip_chars.size() > 0:
		for e in _clip_chars:
			e.visible = true
		_look(Vector3(0.0, 1.35, 14.4), Vector3(0.0, 0.92, 7.5), 39.0)
		await t.wait_frames(4)
		await t.shot("chr_lineup_clips")
	_sun.rotation_degrees = Vector3(-42.0, 205.0, 0.0)
	# posed characters
	var pose_names := ["walk", "seated", "aim", "crouch", "walk", "seated"]
	for i in 6:
		_apply_pose(_chars[i], pose_names[i])
		if pose_names[i] == "seated":
			_chars[i].position.y -= 0.42
		elif pose_names[i] == "crouch":
			_chars[i].position.y -= 0.30
	for i in range(6, _chars.size()):
		_apply_pose(_chars[i], pose_names[(i + 2) % 6])
	_look(Vector3(-3.4, 1.5, -5.0), Vector3(0.0, 0.95, 0.4), 39.0)
	await t.wait_frames(4)
	await t.shot("chr_lineup_poses")
	# variety row (hair styles, reworked tops), face close-ups, hands on weapons
	for e in _grip:
		e.visible = false
	_look(Vector3(VARIETY_X, 1.45, -6.6), Vector3(VARIETY_X, 0.98, 0.0), 39.0)
	await t.wait_frames(4)
	await t.shot("chr_lineup_variety")
	_look(Vector3(VARIETY_X - 2.6, 1.66, -1.75), Vector3(VARIETY_X - 2.7, 1.60, 0.0), 34.0)
	await t.wait_frames(4)
	await t.shot("chr_lineup_faces")
	_look(Vector3(VARIETY_X + 1.0, 1.66, -1.75), Vector3(VARIETY_X + 0.9, 1.60, 0.0), 34.0)
	await t.wait_frames(4)
	await t.shot("chr_lineup_faces2")
	for e in _variety:
		e.visible = false
	for e in _grip:
		e.visible = true
	_look(Vector3(VARIETY_X + 0.2, 1.35, -16.6), Vector3(VARIETY_X + 0.1, 1.12, -14.0), 36.0)
	await t.wait_frames(4)
	await t.shot("chr_lineup_grip")
	t.finish()


func _has_prefix(parts: PackedStringArray, prefix: String) -> bool:
	for p in parts:
		if p.begins_with(prefix):
			return true
	return false


func _grip_transform(v: Node3D) -> Transform3D:
	# the same canonical grip the weapons module uses (HumanoidAnimator, PLAYER module) when present
	if ResourceLoader.exists(ANIMATOR_SCRIPT):
		var scr := load(ANIMATOR_SCRIPT) as Script
		if scr != null:
			for m: Dictionary in scr.get_script_method_list():
				if m.get("name", "") == "get_grip_transform":
					var g: Variant = scr.call("get_grip_transform", v.call("get_skeleton"), "Hand_R")
					if g is Transform3D:
						return g
	return v.call("get_grip_transform", "Hand_R") as Transform3D


func _build_variety_stage() -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#cfc8b8")
	floor_mat.roughness = 0.95
	var floor_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(18.0, 0.2, 30.0)
	floor_mesh.mesh = bm
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(VARIETY_X, -0.1, -6.0)
	_stage.add_child(floor_mesh)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color("#f3e7d0")
	wall_mat.roughness = 1.0
	for z: float in [2.2, -11.6]:
		var wall := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(18.0, 7.0, 0.3)
		wall.mesh = wb
		wall.material_override = wall_mat
		wall.position = Vector3(VARIETY_X, 3.0, z)
		_stage.add_child(wall)


func _apply_pose(v: Node3D, pose_name: String) -> void:
	_apply_named_pose(v, POSES[pose_name])


func _apply_named_pose(v: Node3D, pose: Dictionary) -> void:
	v.call("set_static_pose", "tpose")
	for bone: String in pose.keys():
		var q := Basis.IDENTITY
		for step: Array in pose[bone]:
			var axis := Vector3.RIGHT
			if step[0] == "F":
				axis = Vector3.FORWARD
			elif step[0] == "U":
				axis = Vector3.UP
			q = Basis(axis, deg_to_rad(float(step[1]))) * q
		v.call("pose_bone_model", bone, q)


func _look(from: Vector3, at: Vector3, fov: float) -> void:
	_cam.position = from
	_cam.look_at(_stage.to_global(at), Vector3.UP)
	_cam.fov = fov
	_cam.make_current()


func _build_stage() -> void:
	_stage = Node3D.new()
	_stage.name = "ChrLineupStage"
	add_child(_stage)
	_stage.global_position = ORIGIN
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#cfc8b8")
	floor_mat.roughness = 0.95
	var floor_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(26.0, 0.2, 22.0)
	floor_mesh.mesh = bm
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(0.0, -0.1, 2.0)
	_stage.add_child(floor_mesh)
	var step_mesh := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(7.6, 0.55, 1.5)
	step_mesh.mesh = sb
	var step_mat := StandardMaterial3D.new()
	step_mat.albedo_color = Color("#a9a292")
	step_mat.roughness = 0.95
	step_mesh.material_override = step_mat
	step_mesh.position = Vector3(0.3, 0.275, 1.75)
	_stage.add_child(step_mesh)
	var wall := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(26.0, 9.0, 0.3)
	wall.mesh = wb
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color("#8fcae8")
	wall_mat.roughness = 1.0
	wall.material_override = wall_mat
	wall.position = Vector3(0.0, 4.0, 4.6)
	_stage.add_child(wall)
	_wall = wall
	var sun := DirectionalLight3D.new()
	sun.name = "TestSun"
	sun.light_color = Color("#fff1dc")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	_stage.add_child(sun)
	sun.rotation_degrees = Vector3(-42.0, 205.0, 0.0)
	_sun = sun
	var fill := DirectionalLight3D.new()
	fill.name = "TestFill"
	fill.light_color = Color("#bcd8ff")
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	_stage.add_child(fill)
	fill.rotation_degrees = Vector3(-20.0, 140.0, 0.0)
	_cam = Camera3D.new()
	_cam.name = "LineupCamera"
	_cam.near = 0.1
	_cam.far = 200.0
	_stage.add_child(_cam)
	# own environment only when the game's environment system is not running
	var has_env := Game.get_system("environment") != null or not get_tree().root.find_children("*", "WorldEnvironment", true, false).is_empty()
	if not has_env:
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("#8fcae8")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("#c9d8ea")
		env.ambient_light_energy = 0.55
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.ssao_enabled = true
		var we := WorldEnvironment.new()
		we.name = "TestEnvironment"
		we.environment = env
		_stage.add_child(we)
	_look(Vector3(0.0, 1.55, -5.9), Vector3(0.15, 1.12, 0.6), 39.0)
