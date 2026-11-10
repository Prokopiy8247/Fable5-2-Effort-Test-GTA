class_name CharVisual
extends Node3D
## Skinned low-poly human with a fully procedural pose/animation layer, two-bone arm IK for weapons,
## customisable look (materials + bone attachments). Shared by the player and every NPC.

const PARTS := "characters/char_parts"
const HEAD_PARTS := ["Hair_Short", "Hair_Quiff", "Hair_Long", "Hair_Pony", "Hair_Mohawk", "Hair_Afro", "Hair_Bun", "Beard", "Mustache",
	"Hat_Cap", "Hat_Beanie", "Hat_Police", "Hat_Helmet", "Hat_Hard", "Hat_Fedora", "Hat_Mask", "Glasses", "Shades", "Scuba_Mask"]
const SKINS := ["f2c9a5", "d9a27a", "c08a5c", "9a6a44", "6b452b", "4a2f1d"]
const HAIRS := ["2b1d14", "111111", "5a3a22", "8a5a2b", "c9a25a", "7a7a7a", "a83a2a", "e8e0d0"]
const CLOTH := ["3d7ea6", "b03a2e", "2f6b4f", "f2b705", "e9e4d8", "2d3142", "7d2a8c", "e9792a", "4c5a36", "c9b28a", "1b1d21", "d9d9d9", "2f9c95", "8a94a0", "e3a58c"]
const PANTS := ["2d3142", "1b1d21", "4a5a7a", "6b5a45", "8a8f96", "3a3f2c", "c9b28a", "20252e"]

var skel: Skeleton3D
var meshes: Array = []
var bone := {}
var pre := {}
var post := {}
var rest_pos := {}
var rest_gpos := {}
var cur := {}
var look := {}
var S := 1.0
var attach := {}
var weapon_mount: Node3D
var weapon_node: Node3D = null
var two_handed := false

# --- animation inputs (set by the owning controller)
var speed := 0.0
var strafe := Vector2.ZERO
var grounded := true
var crouch := 0.0
var aim := 0.0
var aim_pitch := 0.0
var wtype := "none"
var mode := "foot"
var recline := 0.25
var sprinting := false
var action := ""
var action_t := 0.0
var action_len := 0.5
var recoil := 0.0
var reload_t := 0.0
var hands_up := 0.0
var phone := 0.0
var limp := 0.0
var lean := 0.0
var phase := 0.0
var idle_t := 0.0
var lod_skip := 0
var _skip_counter := 0
var hips_drop := 0.0
var blend_rate := 14.0
var injured := 0.0


static func random_look(r: RandomNumberGenerator, kind: String = "civ") -> Dictionary:
	var female := r.randf() < 0.47
	var d := {"sex": "f" if female else "m", "skin": Color(SKINS[r.randi() % SKINS.size()]), "hair_color": Color(HAIRS[r.randi() % HAIRS.size()]),
		"shirt": Color(CLOTH[r.randi() % CLOTH.size()]), "pants": Color(PANTS[r.randi() % PANTS.size()]),
		"shoes": Color(["1d1b1a", "e8e4da", "5a3a22", "b03a2e", "2d3142"][r.randi() % 5]), "long_sleeve": r.randf() < 0.5, "shorts": r.randf() < 0.22,
		"hair": "", "hat": "", "glasses": "", "beard": "", "vest": false, "pack": "", "hat_color": Color(CLOTH[r.randi() % CLOTH.size()])}
	if female:
		d.hair = ["Hair_Long", "Hair_Pony", "Hair_Bun", "Hair_Short", "Hair_Afro", "Hair_Long"][r.randi() % 6]
	else:
		d.hair = ["Hair_Short", "Hair_Quiff", "Hair_Short", "", "Hair_Mohawk", "Hair_Afro", "Hair_Quiff"][r.randi() % 7]
		if r.randf() < 0.28:
			d.beard = "Beard" if r.randf() < 0.6 else "Mustache"
	if r.randf() < 0.2:
		d.hat = ["Hat_Cap", "Hat_Beanie", "Hat_Fedora", "Hat_Cap"][r.randi() % 4]
	if r.randf() < 0.18:
		d.glasses = "Glasses" if r.randf() < 0.5 else "Shades"
	match kind:
		"cop":
			d.merge({"shirt": Color("1c2740"), "pants": Color("161d30"), "shoes": Color("101010"), "long_sleeve": false, "shorts": false,
				"hat": "Hat_Police", "glasses": "Shades" if r.randf() < 0.4 else "", "badge": true}, true)
		"swat":
			d.merge({"shirt": Color("1a1d22"), "pants": Color("1a1d22"), "shoes": Color("0c0c0c"), "long_sleeve": true, "shorts": false,
				"hat": "Hat_Helmet", "glasses": "", "vest": true, "hair": "", "beard": ""}, true)
		"medic":
			d.merge({"shirt": Color("f1f1ec"), "pants": Color("c8201c"), "long_sleeve": false, "shorts": false, "hat": ""}, true)
		"fire":
			d.merge({"shirt": Color("d9a21c"), "pants": Color("3a3320"), "long_sleeve": true, "shorts": false, "hat": "Hat_Hard", "hat_color": Color("c21a14")}, true)
		"gang":
			d.merge({"shirt": Color("7d2a8c") if r.randf() < 0.5 else Color("1b1d21"), "hat": "Hat_Beanie" if r.randf() < 0.5 else ("Hat_Mask" if r.randf() < 0.3 else ""),
				"hat_color": Color("1b1d21"), "shorts": false}, true)
		"clerk":
			d.merge({"apron": true, "long_sleeve": false, "shorts": false, "hat": ""}, true)
	return d


func setup(lk: Dictionary) -> void:
	look = lk.duplicate()
	var female: bool = look.get("sex", "m") == "f"
	var rel := "characters/human_f" if female else "characters/human_m"
	var root := Assets.inst(rel, "human_f_" if female else "human_m_")
	add_child(root)
	skel = _find_skel(root)
	S = 0.94 if female else 1.0
	for c in skel.get_children():
		if c is MeshInstance3D:
			meshes.append(c)
			if String(c.name).contains("LOD1"):
				c.visibility_range_begin = 32.0
				c.visibility_range_end = 150.0
			else:
				c.visibility_range_end = 32.0
	for i in skel.get_bone_count():
		var nm := skel.get_bone_name(i)
		bone[nm] = i
		var par := skel.get_bone_parent(i)
		var gr := skel.get_bone_global_rest(i)
		var pgr := skel.get_bone_global_rest(par).basis if par >= 0 else Basis()
		pre[nm] = Quaternion(pgr.orthonormalized().inverse())
		post[nm] = Quaternion(gr.basis.orthonormalized())
		rest_pos[nm] = skel.get_bone_rest(i).origin
		rest_gpos[nm] = gr.origin
		cur[nm] = Quaternion.IDENTITY
	weapon_mount = Node3D.new()
	weapon_mount.name = "WeaponMount"
	add_child(weapon_mount)
	apply_look(look)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null


func apply_look(lk: Dictionary) -> void:
	look = lk
	var skin: Color = lk.get("skin", Color(SKINS[1]))
	var shirt: Color = lk.get("shirt", Color("3d7ea6"))
	var pants: Color = lk.get("pants", Color("2d3142"))
	var colors := {"Skin": skin, "Shirt": shirt, "Sleeve": shirt if lk.get("long_sleeve", true) else skin, "Pants": pants,
		"Shin": skin if lk.get("shorts", false) else pants, "Shoes": lk.get("shoes", Color("1d1b1a")), "Hair": lk.get("hair_color", Color("2b1d14")),
		"Eye": Color("101010"), "Mouth": skin.darkened(0.35), "Sole": Color("e8e4da")}
	for m in meshes:
		var mi: MeshInstance3D = m
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat and colors.has(mat.resource_name):
				mi.set_surface_override_material(i, Assets.color_mat(colors[mat.resource_name], 0.82))
	for k in attach.keys():
		attach[k].queue_free()
	attach.clear()
	var hair_m := Assets.color_mat(colors["Hair"], 0.8)
	for slot in ["hair", "beard", "hat", "glasses", "mask"]:
		var pn: String = lk.get(slot, "")
		if slot == "hair" and lk.get("hat", "") in ["Hat_Helmet", "Hat_Beanie", "Hat_Mask", "Hat_Police", "Hat_Hard", "Hat_Cap", "Hat_Fedora"] and pn in ["Hair_Afro", "Hair_Mohawk", "Hair_Quiff", "Hair_Bun"]:
			pn = "Hair_Short"
		if pn != "" and Assets.has(PARTS, pn):
			_attach(slot, pn, "Head", {"Hair": hair_m, "HatMain": Assets.color_mat(lk.get("hat_color", Color("c9302a")), 0.8), "Skin": Assets.color_mat(skin, 0.8)})
	if lk.get("vest", false):
		_attach("vest", "Vest", "Chest", {})
	if lk.get("apron", false):
		_attach("apron", "Apron", "Chest", {"Apron": Assets.color_mat(lk.get("apron_color", Color("2f8f5b")), 0.85)})
	if lk.get("pack", "") != "":
		_attach("pack", lk.pack, "Chest", {})


func set_pack(pn: String) -> void:
	look["pack"] = pn
	if attach.has("pack"):
		attach["pack"].queue_free()
		attach.erase("pack")
	if pn != "":
		_attach("pack", pn, "Chest", {})


func set_part(slot: String, pn: String, bone_name: String = "Head") -> void:
	if attach.has(slot):
		attach[slot].queue_free()
		attach.erase(slot)
	if pn != "" and Assets.has(PARTS, pn):
		_attach(slot, pn, bone_name, {})


func _attach(slot: String, part: String, bone_name: String, overrides: Dictionary) -> void:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone_name
	skel.add_child(ba)
	var mi := MeshInstance3D.new()
	mi.mesh = Assets.mesh(PARTS, part)
	var inv := Basis(post[bone_name]).inverse()
	mi.transform = Transform3D(inv.scaled(Vector3(S, S, S)), Vector3.ZERO)
	mi.visibility_range_end = 70.0
	for i in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(i)
		if mat and overrides.has(mat.resource_name):
			mi.set_surface_override_material(i, overrides[mat.resource_name])
	ba.add_child(mi)
	attach[slot] = ba


func set_weapon(node: Node3D, wt: String, two_hand: bool) -> void:
	if weapon_node and is_instance_valid(weapon_node):
		weapon_node.queue_free()
	weapon_node = node
	wtype = wt
	two_handed = two_hand
	if node:
		weapon_mount.add_child(node)
		node.transform = Transform3D.IDENTITY


func play(act: String, length: float = 0.5) -> void:
	action = act
	action_t = 0.0
	action_len = length


func bone_pos(nm: String) -> Vector3:
	## Current global position of a bone origin.
	return skel.global_transform * skel.get_bone_global_pose(bone[nm]).origin


func head_pos() -> Vector3:
	return bone_pos("Head") + global_transform.basis.y * 0.12 * S


func e(x: float, y: float = 0.0, z: float = 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(deg_to_rad(x), deg_to_rad(y), deg_to_rad(z)))


func _target_pose(delta: float) -> Dictionary:
	var P := {}
	hips_drop = 0.0
	var run_t := clampf((speed - 2.0) / 4.0, 0.0, 1.0)
	var mv := clampf(speed / 1.2, 0.0, 1.0)
	var stride := lerpf(1.5, 3.0, run_t)
	if mode == "foot" or mode == "cover":
		phase += speed / stride * TAU * delta
	idle_t += delta
	var s := sin(phase)
	var c := cos(phase)
	var breath := sin(idle_t * 1.6)
	match mode:
		"foot", "cover":
			var At := lerpf(26.0, 46.0, run_t) * mv
			var K := lerpf(38.0, 82.0, run_t) * mv
			var Aa := lerpf(20.0, 46.0, run_t) * mv
			var El := lerpf(12.0, 68.0, run_t)
			var back := 1.0 if strafe.y <= 0.3 else -0.6
			P["UpperLeg_L"] = e(At * s * back + K * 0.22 * maxf(c, 0.0), 0, strafe.x * -8.0 * mv)
			P["UpperLeg_R"] = e(-At * s * back + K * 0.22 * maxf(-c, 0.0), 0, strafe.x * -8.0 * mv)
			P["LowerLeg_L"] = e(-K * maxf(c, 0.0) - 6.0 * mv)
			P["LowerLeg_R"] = e(-K * maxf(-c, 0.0) - 6.0 * mv)
			P["Foot_L"] = e(8.0 * maxf(-s, 0.0) * mv)
			P["Foot_R"] = e(8.0 * maxf(s, 0.0) * mv)
			P["UpperArm_L"] = e(-Aa * s, 0, -4.0 - breath * 0.6)
			P["UpperArm_R"] = e(Aa * s, 0, 4.0 + breath * 0.6)
			P["LowerArm_L"] = e(El + Aa * 0.3 * maxf(-s, 0.0))
			P["LowerArm_R"] = e(El + Aa * 0.3 * maxf(s, 0.0))
			P["Spine"] = e(-lerpf(2.0, 10.0, run_t) * mv + breath * 0.6, 5.0 * s * mv, lean * 6.0)
			P["Chest"] = e(breath * 0.8, 4.0 * s * mv, lean * 4.0)
			P["Hips"] = e(0, -4.0 * s * mv, 0)
			P["Head"] = e(lerpf(1.0, 5.0, run_t) * mv)
			hips_drop = absf(s) * 0.035 * mv + (0.02 if sprinting else 0.0)
			if crouch > 0.01:
				var cs := s * mv
				P["UpperLeg_L"] = P["UpperLeg_L"].slerp(e(62.0 + 16.0 * cs, 0, -6.0), crouch)
				P["UpperLeg_R"] = P["UpperLeg_R"].slerp(e(62.0 - 16.0 * cs, 0, 6.0), crouch)
				P["LowerLeg_L"] = P["LowerLeg_L"].slerp(e(-98.0 - 10.0 * maxf(c, 0.0) * mv), crouch)
				P["LowerLeg_R"] = P["LowerLeg_R"].slerp(e(-98.0 - 10.0 * maxf(-c, 0.0) * mv), crouch)
				P["Foot_L"] = P["Foot_L"].slerp(e(30.0), crouch)
				P["Foot_R"] = P["Foot_R"].slerp(e(30.0), crouch)
				P["Spine"] = P["Spine"].slerp(e(-22.0, 4.0 * cs), crouch)
				hips_drop = lerpf(hips_drop, 0.36, crouch)
			if not grounded:
				P["UpperLeg_L"] = e(28.0, 0, -5.0)
				P["UpperLeg_R"] = e(-12.0, 0, 5.0)
				P["LowerLeg_L"] = e(-48.0)
				P["LowerLeg_R"] = e(-22.0)
				P["UpperArm_L"] = e(-25.0, 0, -42.0 + sin(idle_t * 9.0) * 8.0)
				P["UpperArm_R"] = e(-25.0, 0, 42.0 - sin(idle_t * 9.0) * 8.0)
			if injured > 0.01:
				P["Spine"] = P["Spine"] * e(-14.0 * injured)
		"sit", "bike":
			var bk := mode == "bike"
			P["Hips"] = e(rad_to_deg(recline) * 0.6 if not bk else -12.0)
			P["Spine"] = e(rad_to_deg(recline) * 0.25 if not bk else -16.0, lean * -6.0, lean * 5.0)
			P["Chest"] = e(-4.0 if not bk else -8.0)
			P["Head"] = e(-rad_to_deg(recline) * 0.6 if not bk else 22.0)
			P["UpperLeg_L"] = e(82.0 + rad_to_deg(recline) * 0.5 if not bk else 62.0, 0, -9.0 if not bk else -18.0)
			P["UpperLeg_R"] = e(82.0 + rad_to_deg(recline) * 0.5 if not bk else 62.0, 0, 9.0 if not bk else 18.0)
			P["LowerLeg_L"] = e(-70.0 if not bk else -88.0)
			P["LowerLeg_R"] = e(-62.0 if not bk else -88.0)
			P["Foot_L"] = e(-10.0)
			P["Foot_R"] = e(-10.0)
			P["UpperArm_L"] = e(52.0 if not bk else 60.0, 0, -8.0 - lean * 10.0)
			P["UpperArm_R"] = e(52.0 if not bk else 60.0, 0, 8.0 - lean * 10.0)
			P["LowerArm_L"] = e(38.0 if not bk else 18.0, 12.0)
			P["LowerArm_R"] = e(38.0 if not bk else 18.0, -12.0)
		"passenger":
			P["Hips"] = e(10.0)
			P["UpperLeg_L"] = e(84.0, 0, -6.0)
			P["UpperLeg_R"] = e(84.0, 0, 6.0)
			P["LowerLeg_L"] = e(-80.0)
			P["LowerLeg_R"] = e(-80.0)
			P["UpperArm_L"] = e(18.0, 0, -6.0)
			P["UpperArm_R"] = e(18.0, 0, 6.0)
			P["LowerArm_L"] = e(55.0)
			P["LowerArm_R"] = e(55.0)
		"swim":
			phase += (1.6 + speed * 1.2) * delta
			var st := clampf(speed / 1.5, 0.0, 1.0)
			P["Spine"] = e(-6.0)
			P["Head"] = e(38.0 * st)
			P["UpperArm_L"] = e(lerpf(40.0, 150.0 + 35.0 * sin(phase), st), 0, lerpf(-55.0 + 12.0 * sin(phase * 0.8), -18.0, st))
			P["UpperArm_R"] = e(lerpf(40.0, 150.0 - 35.0 * sin(phase), st), 0, lerpf(55.0 - 12.0 * sin(phase * 0.8), 18.0, st))
			P["LowerArm_L"] = e(lerpf(40.0, 12.0 + 12.0 * cos(phase), st))
			P["LowerArm_R"] = e(lerpf(40.0, 12.0 - 12.0 * cos(phase), st))
			P["UpperLeg_L"] = e(lerpf(10.0, 4.0, st) + 16.0 * sin(phase * 2.0))
			P["UpperLeg_R"] = e(lerpf(10.0, 4.0, st) - 16.0 * sin(phase * 2.0))
			P["LowerLeg_L"] = e(-14.0 - 14.0 * maxf(sin(phase * 2.0), 0.0))
			P["LowerLeg_R"] = e(-14.0 - 14.0 * maxf(-sin(phase * 2.0), 0.0))
			P["Foot_L"] = e(-40.0 * st)
			P["Foot_R"] = e(-40.0 * st)
		"ladder":
			phase += speed * 3.5 * delta
			var ls := sin(phase)
			P["UpperArm_L"] = e(128.0 + 22.0 * ls, 0, -6.0)
			P["UpperArm_R"] = e(128.0 - 22.0 * ls, 0, 6.0)
			P["LowerArm_L"] = e(26.0 - 14.0 * ls)
			P["LowerArm_R"] = e(26.0 + 14.0 * ls)
			P["UpperLeg_L"] = e(38.0 - 26.0 * ls)
			P["UpperLeg_R"] = e(38.0 + 26.0 * ls)
			P["LowerLeg_L"] = e(-58.0 + 26.0 * ls)
			P["LowerLeg_R"] = e(-58.0 - 26.0 * ls)
		"fall":
			var fl := sin(idle_t * 11.0)
			P["UpperArm_L"] = e(-10.0 + 20.0 * fl, 0, -78.0)
			P["UpperArm_R"] = e(-10.0 - 20.0 * fl, 0, 78.0)
			P["LowerArm_L"] = e(25.0)
			P["LowerArm_R"] = e(25.0)
			P["UpperLeg_L"] = e(18.0 + 14.0 * fl, 0, -14.0)
			P["UpperLeg_R"] = e(18.0 - 14.0 * fl, 0, 14.0)
			P["LowerLeg_L"] = e(-40.0)
			P["LowerLeg_R"] = e(-40.0)
		"chute":
			P["UpperArm_L"] = e(150.0, 0, -22.0 - lean * 16.0)
			P["UpperArm_R"] = e(150.0, 0, 22.0 - lean * 16.0)
			P["LowerArm_L"] = e(22.0)
			P["LowerArm_R"] = e(22.0)
			P["UpperLeg_L"] = e(22.0 + 4.0 * breath, 0, -5.0)
			P["UpperLeg_R"] = e(16.0 - 4.0 * breath, 0, 5.0)
			P["LowerLeg_L"] = e(-34.0)
			P["LowerLeg_R"] = e(-26.0)
			P["Spine"] = e(-4.0, 0, lean * 10.0)
		"dead":
			P["Spine"] = e(4.0, 6.0, 0)
			P["Head"] = e(10.0, 25.0, 0)
			P["UpperArm_L"] = e(-12.0, 0, -62.0)
			P["UpperArm_R"] = e(20.0, 0, 38.0)
			P["LowerArm_L"] = e(42.0)
			P["LowerArm_R"] = e(18.0)
			P["UpperLeg_L"] = e(8.0, 0, -12.0)
			P["UpperLeg_R"] = e(-6.0, 0, 9.0)
			P["LowerLeg_L"] = e(-28.0)
			P["LowerLeg_R"] = e(-6.0)
	if hands_up > 0.01:
		P["UpperArm_L"] = P.get("UpperArm_L", Quaternion.IDENTITY).slerp(e(165.0, 0, -18.0), hands_up)
		P["UpperArm_R"] = P.get("UpperArm_R", Quaternion.IDENTITY).slerp(e(165.0, 0, 18.0), hands_up)
		P["LowerArm_L"] = P.get("LowerArm_L", Quaternion.IDENTITY).slerp(e(20.0), hands_up)
		P["LowerArm_R"] = P.get("LowerArm_R", Quaternion.IDENTITY).slerp(e(20.0), hands_up)
	if phone > 0.01:
		P["UpperArm_R"] = P.get("UpperArm_R", Quaternion.IDENTITY).slerp(e(48.0, 0, 24.0), phone)
		P["LowerArm_R"] = P.get("LowerArm_R", Quaternion.IDENTITY).slerp(e(132.0, 30.0), phone)
		P["Head"] = P.get("Head", Quaternion.IDENTITY).slerp(e(4.0, 0, -8.0), phone)
	if aim > 0.01 and mode != "dead":
		var ap := rad_to_deg(aim_pitch)
		P["Spine"] = P.get("Spine", Quaternion.IDENTITY).slerp(e(ap * 0.25, 0, 0), aim * 0.8)
		P["Chest"] = P.get("Chest", Quaternion.IDENTITY).slerp(e(ap * 0.25, 0, 0), aim * 0.8)
		P["Head"] = P.get("Head", Quaternion.IDENTITY).slerp(e(ap * 0.4, 0, 0), aim)
	if action != "":
		action_t += delta / maxf(action_len, 0.05)
		var t := clampf(action_t, 0.0, 1.0)
		var w := sin(t * PI)
		match action:
			"punch_r", "swing":
				var k := smoothstep(0.0, 0.45, t) - smoothstep(0.55, 1.0, t) * 0.0
				var arc := lerpf(-55.0, 95.0, smoothstep(0.15, 0.6, t))
				P["UpperArm_R"] = e(arc, -20.0 * w, 20.0 + 30.0 * (1.0 - k))
				P["LowerArm_R"] = e(lerpf(95.0, 12.0, smoothstep(0.25, 0.6, t)))
				P["Chest"] = e(-6.0 * w, lerpf(-28.0, 30.0, smoothstep(0.1, 0.6, t)) * w, 0)
				P["UpperArm_L"] = e(40.0, 0, -14.0)
				P["LowerArm_L"] = e(95.0)
			"punch_l":
				var arc2 := lerpf(-40.0, 92.0, smoothstep(0.1, 0.55, t))
				P["UpperArm_L"] = e(arc2, 20.0 * w, -18.0)
				P["LowerArm_L"] = e(lerpf(95.0, 10.0, smoothstep(0.2, 0.55, t)))
				P["Chest"] = e(-4.0 * w, lerpf(22.0, -26.0, smoothstep(0.1, 0.55, t)) * w, 0)
				P["UpperArm_R"] = e(42.0, 0, 14.0)
				P["LowerArm_R"] = e(100.0)
			"heavy":
				var arc3 := lerpf(175.0, 40.0, smoothstep(0.35, 0.7, t))
				P["UpperArm_R"] = e(arc3, 0, 10.0)
				P["UpperArm_L"] = e(arc3, 0, -10.0)
				P["LowerArm_R"] = e(lerpf(70.0, 10.0, smoothstep(0.35, 0.7, t)))
				P["LowerArm_L"] = e(lerpf(70.0, 10.0, smoothstep(0.35, 0.7, t)))
				P["Spine"] = e(lerpf(14.0, -30.0, smoothstep(0.35, 0.7, t)) * w)
			"kick":
				P["UpperLeg_R"] = e(lerpf(-10.0, 88.0, smoothstep(0.15, 0.5, t)) * w)
				P["LowerLeg_R"] = e(lerpf(-90.0, -5.0, smoothstep(0.3, 0.55, t)))
				P["Spine"] = e(10.0 * w)
			"throw":
				P["UpperArm_R"] = e(lerpf(-70.0, 130.0, smoothstep(0.2, 0.6, t)), 0, 25.0)
				P["LowerArm_R"] = e(lerpf(100.0, 15.0, smoothstep(0.3, 0.6, t)))
				P["Chest"] = e(-8.0 * w, lerpf(-25.0, 25.0, smoothstep(0.2, 0.6, t)) * w)
			"block":
				P["UpperArm_L"] = e(88.0, 30.0, -10.0)
				P["LowerArm_L"] = e(115.0)
				P["UpperArm_R"] = e(88.0, -30.0, 10.0)
				P["LowerArm_R"] = e(115.0)
			"hit":
				P["Spine"] = P.get("Spine", Quaternion.IDENTITY) * e(16.0 * w, 12.0 * w, 0)
				P["Head"] = e(14.0 * w, 10.0 * w, 0)
			"wave":
				P["UpperArm_R"] = e(150.0, 0, 30.0 + 18.0 * sin(t * 22.0))
				P["LowerArm_R"] = e(30.0)
			"use":
				P["UpperArm_R"] = e(70.0 * w, 0, 6.0)
				P["LowerArm_R"] = e(40.0 * w)
			"climb":
				P["UpperArm_L"] = e(lerpf(160.0, 30.0, t), 0, -10.0)
				P["UpperArm_R"] = e(lerpf(160.0, 30.0, t), 0, 10.0)
				P["LowerArm_L"] = e(lerpf(20.0, 80.0, w))
				P["LowerArm_R"] = e(lerpf(20.0, 80.0, w))
				P["UpperLeg_L"] = e(lerpf(10.0, 95.0, w))
				P["LowerLeg_L"] = e(-100.0 * w)
				P["UpperLeg_R"] = e(-10.0 * w)
			"roll":
				P["Spine"] = e(-48.0)
				P["Chest"] = e(-22.0)
				P["Head"] = e(-30.0)
				P["UpperLeg_L"] = e(112.0)
				P["UpperLeg_R"] = e(112.0)
				P["LowerLeg_L"] = e(-125.0)
				P["LowerLeg_R"] = e(-125.0)
				P["UpperArm_L"] = e(62.0, 0, -10.0)
				P["UpperArm_R"] = e(62.0, 0, 10.0)
				P["LowerArm_L"] = e(110.0)
				P["LowerArm_R"] = e(110.0)
				hips_drop = 0.42
		if action_t >= 1.0 and action != "block":
			action = ""
	return P


func tick(delta: float) -> void:
	## Advance and apply the procedural animation. Call once per frame from the owner.
	if skel == null:
		return
	if lod_skip > 0:
		_skip_counter += 1
		if _skip_counter % (lod_skip + 1) != 0:
			phase += speed / 2.2 * TAU * delta
			return
		delta *= (lod_skip + 1)
	var P := _target_pose(delta)
	var k := clampf(delta * blend_rate, 0.0, 1.0)
	for nm in cur.keys():
		var tq: Quaternion = P.get(nm, Quaternion.IDENTITY)
		var q: Quaternion = cur[nm]
		q = q.slerp(tq, k)
		cur[nm] = q
		skel.set_bone_pose_rotation(bone[nm], pre[nm] * q * post[nm])
	var hp: Vector3 = rest_pos["Hips"]
	skel.set_bone_pose_position(bone["Hips"], hp - Vector3(0, hips_drop * S, 0))
	recoil = move_toward(recoil, 0.0, delta * 7.0)
	if weapon_node != null and mode != "dead":
		_update_weapon(delta)


func _update_weapon(_delta: float) -> void:
	var a := aim
	var drop := hips_drop * S
	var relaxed: Transform3D
	var aimed: Transform3D
	var melee := wtype in ["melee", "throw", "knife"]
	if melee:
		# rigid in the right hand
		var hb: Transform3D = skel.get_bone_global_pose(bone["Hand_R"])
		var grip := Basis(Vector3(1, 0, 0), Vector3(0, 0.34, -0.94), Vector3(0, 0.94, 0.34))
		var t := Transform3D(hb.basis * Basis(post["Hand_R"]).inverse() * grip, hb.origin + hb.basis * Basis(post["Hand_R"]).inverse() * Vector3(0.0, -0.085, -0.02) * S)
		weapon_mount.transform = t
		return
	var pitch := aim_pitch
	match wtype:
		"pistol":
			relaxed = Transform3D(Basis.from_euler(Vector3(-1.15, 0.0, 0.0)), Vector3(0.265, 0.90 - drop, -0.06) * S)
			aimed = Transform3D(Basis.from_euler(Vector3(pitch + recoil * 0.35, 0, 0)), Vector3(0.11, 1.44 - drop + sin(pitch) * 0.18, -0.46 + recoil * 0.05) * S)
		"rpg":
			relaxed = Transform3D(Basis.from_euler(Vector3(-0.5, 0.3, 0.0)), Vector3(0.2, 1.05 - drop, -0.12) * S)
			aimed = Transform3D(Basis.from_euler(Vector3(pitch + recoil * 0.2, 0, 0)), Vector3(0.2, 1.50 - drop, -0.12 + recoil * 0.08) * S)
		_:
			relaxed = Transform3D(Basis.from_euler(Vector3(-0.62, 0.42, 0.0)), Vector3(0.13, 1.04 - drop, -0.20) * S)
			aimed = Transform3D(Basis.from_euler(Vector3(pitch + recoil * 0.22, 0, 0)), Vector3(0.15, 1.40 - drop + sin(pitch) * 0.14, -0.24 + recoil * 0.07) * S)
	var t2 := relaxed.interpolate_with(aimed, a)
	if reload_t > 0.0:
		t2 = t2 * Transform3D(Basis.from_euler(Vector3(0.25 * sin(reload_t * PI), 0, -0.3 * sin(reload_t * PI))), Vector3.ZERO)
	if mode == "sit" or mode == "bike":
		t2.origin += Vector3(0.0, -0.12, 0.0)
	weapon_mount.transform = t2
	# IK both hands onto the weapon
	var rt := t2 * Vector3(0, -0.035, 0.02)
	_arm_ik("R", rt, Vector3(0.6, -0.8, 0.2))
	if two_handed or (wtype == "pistol" and a > 0.5):
		var fore := Vector3(0.0, 0.01, -0.30) if two_handed else Vector3(-0.03, -0.05, 0.0)
		if reload_t > 0.0:
			fore += Vector3(0, -0.14 * sin(reload_t * PI), 0.12 * sin(reload_t * PI))
		_arm_ik("L", t2 * fore, Vector3(-0.6, -0.8, 0.1))


func _arm_ik(side: String, target: Vector3, pole: Vector3) -> void:
	## Analytic two-bone IK in skeleton space, then converted into the local-delta pose convention.
	var up_n := "UpperArm_" + side
	var lo_n := "LowerArm_" + side
	var hand_n := "Hand_" + side
	var sh: Vector3 = skel.get_bone_global_pose(bone[up_n]).origin
	var l1: float = (rest_gpos[lo_n] - rest_gpos[up_n]).length()
	var l2: float = (rest_gpos[hand_n] - rest_gpos[lo_n]).length()
	var to := target - sh
	var d := clampf(to.length(), 0.05, l1 + l2 - 0.005)
	var dir := to.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var ang := acos(cos_a)
	var axis := dir.cross(pole).normalized()
	if axis.length() < 0.01:
		axis = Vector3(1, 0, 0)
	var up_dir := dir.rotated(axis, ang)
	var elbow := sh + up_dir * l1
	var lo_dir := (sh + dir * d - elbow).normalized()
	# parent (Chest) global delta
	var chest_g: Basis = skel.get_bone_global_pose(bone["Chest"]).basis.orthonormalized()
	var chest_delta := Quaternion(chest_g) * Quaternion(Basis(post["Chest"])).inverse()
	var rest_up_dir: Vector3 = (rest_gpos[lo_n] - rest_gpos[up_n]).normalized()
	var rest_lo_dir: Vector3 = (rest_gpos[hand_n] - rest_gpos[lo_n]).normalized()
	var g_up := Quaternion(rest_up_dir, up_dir)
	var q_up := chest_delta.inverse() * g_up
	var g_lo := Quaternion(rest_lo_dir, lo_dir)
	var q_lo := g_up.inverse() * g_lo
	cur[up_n] = q_up
	cur[lo_n] = q_lo
	skel.set_bone_pose_rotation(bone[up_n], pre[up_n] * q_up * post[up_n])
	skel.set_bone_pose_rotation(bone[lo_n], pre[lo_n] * q_lo * post[lo_n])
