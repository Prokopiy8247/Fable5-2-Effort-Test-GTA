extends Node3D
## Rigged low-poly human (Blender-authored, rigid skinned) with fully procedural animation.
## Model faces -Z. Pose values are model-space euler deltas per bone (x: swing forward +).

const Defs := preload("res://gta/code/core/defs.gd")
const BONE_NAMES := ["Hips", "Spine", "Head", "UpperArm.R", "LowerArm.R", "Hand.R", "UpperArm.L", "LowerArm.L", "Hand.L",
	"UpperLeg.R", "LowerLeg.R", "UpperLeg.L", "LowerLeg.L"]

var skel: Skeleton3D
var idx := {}
var rest_g := {}
var rest_l := {}
var cur := {}
var hips_rest := Vector3.ZERO
var hips_y := 0.0
var look := {}
var attach: BoneAttachment3D
var weapon_node: Node3D
var weapon_id := ""
var flashlight: SpotLight3D

# animation inputs (set by owner)
var state := "idle"        # idle, move, crouch, air, swim, tread, sit, bike, climb, cover_low, cover_high, handsup, chute, cower, phone, dead, limp
var speed := 0.0
var aiming := false
var aim_pitch := 0.0
var two_hand := false
var action := ""
var action_t := 0.0
var action_len := 0.4
var phase := 0.0
var lod := false
var _t := 0.0


func _ready() -> void:
	var m = G.model("characters/human")
	add_child(m)
	skel = m.find_children("*", "Skeleton3D", true, false)[0]
	for bn in BONE_NAMES:
		var i = skel.find_bone(bn)
		if i < 0:
			i = skel.find_bone(bn.replace(".", "_"))
		if i < 0:
			i = skel.find_bone(bn.replace(".", ""))
		idx[bn] = i
		if i >= 0:
			rest_g[bn] = skel.get_bone_global_rest(i).basis.get_rotation_quaternion()
			rest_l[bn] = skel.get_bone_rest(i).basis.get_rotation_quaternion()
			cur[bn] = Vector3.ZERO
	hips_rest = skel.get_bone_rest(idx["Hips"]).origin
	attach = BoneAttachment3D.new()
	skel.add_child(attach)
	attach.bone_name = skel.get_bone_name(idx["Hand.R"])
	if look.is_empty():
		look = random_look()
	apply_look(look)


static func random_look(role := "ped") -> Dictionary:
	var r = RandomNumberGenerator.new()
	r.randomize()
	var cols: Array = Defs.CLOTH_COLORS.values()
	var female = r.randf() < 0.48
	var l = {"female": female, "skin": r.randi() % 5, "hair_col": r.randi() % 6,
		"hair": (["Hair_Long", "Hair_Bun", "Hair_Short", "Hair_Long"] if female else ["Hair_Short", "Hair_Short", "Hair_Mohawk", "Bald", "Hair_Short"])[r.randi() % (4 if female else 5)],
		"beard": (not female) and r.randf() < 0.25, "hat": ["None", "None", "None", "Cap", "Beanie"][r.randi() % 5], "hat_col": cols[r.randi() % cols.size()],
		"glasses": r.randf() < 0.18, "shirt": cols[r.randi() % cols.size()], "long_sleeve": r.randf() < 0.45, "pants": cols[r.randi() % cols.size()].darkened(0.25),
		"shorts": r.randf() < 0.25, "shoes": [Color(0.1, 0.1, 0.1), Color(0.9, 0.9, 0.9), Color(0.4, 0.25, 0.15)][r.randi() % 3], "jacket": r.randf() < 0.2,
		"vest": false, "pack": false, "scuba": false}
	match role:
		"cop":
			l.merge({"shirt": Color(0.13, 0.19, 0.36), "long_sleeve": r.randf() < 0.5, "pants": Color(0.08, 0.1, 0.18), "shorts": false, "hat": "PoliceCap", "jacket": false,
				"shoes": Color(0.05, 0.05, 0.05), "glasses": r.randf() < 0.4}, true)
		"swat":
			l.merge({"shirt": Color(0.1, 0.11, 0.13), "long_sleeve": true, "pants": Color(0.09, 0.1, 0.11), "shorts": false, "hat": "Helmet", "vest": true, "jacket": false,
				"shoes": Color(0.05, 0.05, 0.05), "glasses": false, "beard": false}, true)
		"gang":
			l.merge({"shirt": Color(0.5, 0.1, 0.5), "hat": ["Beanie", "Cap", "None"][r.randi() % 3], "hat_col": Color(0.5, 0.1, 0.5), "jacket": r.randf() < 0.5}, true)
		"medic":
			l.merge({"shirt": Color(0.9, 0.9, 0.92), "pants": Color(0.2, 0.35, 0.5), "long_sleeve": false, "shorts": false, "hat": "None", "jacket": false}, true)
		"fire":
			l.merge({"shirt": Color(0.75, 0.6, 0.1), "pants": Color(0.75, 0.6, 0.1), "long_sleeve": true, "shorts": false, "hat": "Helmet", "jacket": true}, true)
		"clerk":
			l.merge({"shirt": Color(0.2, 0.5, 0.35), "long_sleeve": false, "shorts": false, "hat": "None", "jacket": false}, true)
	return l


func apply_look(l: Dictionary) -> void:
	look = l
	if skel == null:
		return
	var female: bool = l.get("female", false)
	var show = {"Body_M": not female, "Body_F": female, "Hair_Short": false, "Hair_Long": false, "Hair_Bun": false, "Hair_Mohawk": false,
		"Beard": l.get("beard", false), "Cap": false, "Beanie": false, "PoliceCap": false, "Helmet": false, "Glasses": l.get("glasses", false),
		"Vest": l.get("vest", false), "Pack": l.get("pack", false), "Scuba": l.get("scuba", false), "Jacket": l.get("jacket", false)}
	var hat: String = l.get("hat", "None")
	if show.has(hat):
		show[hat] = true
	var hair: String = l.get("hair", "Hair_Short")
	if show.has(hair) and hat != "Helmet":
		show[hair] = true
	if hat in ["Cap", "Beanie", "PoliceCap"] and hair == "Hair_Mohawk":
		show[hair] = false
	var skin: Color = Defs.SKIN_TONES[int(l.get("skin", 1)) % 5]
	var shirt: Color = l.get("shirt", Color(0.2, 0.4, 0.7))
	var pants: Color = l.get("pants", Color(0.15, 0.17, 0.22))
	var map = {
		"Skin": _m(skin), "Shirt": _m(shirt), "Sleeve": _m(shirt if l.get("long_sleeve", false) or l.get("jacket", false) else skin),
		"Pants": _m(pants), "Leg": _m(skin if l.get("shorts", false) else pants), "Shoes": _m(l.get("shoes", Color(0.1, 0.1, 0.1))),
		"Hair": _m(Defs.HAIR_COLORS[int(l.get("hair_col", 0)) % 6]), "Hat": _m(l.get("hat_col", Color(0.7, 0.2, 0.15))),
	}
	for mi in skel.get_children():
		if mi is MeshInstance3D:
			var key = String(mi.name).replace("human_", "")
			if show.has(key):
				mi.visible = show[key]
	G.remat(skel, map)


func _m(c: Color) -> StandardMaterial3D:
	return G.cmat("cloth_%s" % c.to_html(false), c, 0.85)


func set_weapon(id: String, mods: Array = [], tint = null) -> void:
	if weapon_node:
		weapon_node.queue_free()
		weapon_node = null
		flashlight = null
	weapon_id = id
	var d: Dictionary = Defs.WEAPONS.get(id, {})
	two_hand = d.get("two", false)
	var mdl: String = d.get("model", "")
	if mdl == "":
		return
	weapon_node = G.model("weapons/" + mdl)
	attach.add_child(weapon_node)
	var gh: Basis = skel.get_bone_global_rest(idx["Hand.R"]).basis.orthonormalized()
	var w = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	weapon_node.transform = Transform3D(gh.inverse() * w, gh.inverse() * Vector3(0.0, -0.06, -0.03))
	for p in G.parts(weapon_node, "_Att_"):
		var an = String(p.name).split("_Att_")[1]
		p.visible = mods.has(an)
	if tint != null:
		var tm = G.cmat("tint_%s" % (tint as Color).to_html(false), tint, 0.4, 0.5)
		G.remat(weapon_node, {"Gunmetal": tm, "Polymer": tm, "Olive": tm})
	if mods.has("Flashlight"):
		flashlight = SpotLight3D.new()
		flashlight.spot_range = 40.0
		flashlight.spot_angle = 22.0
		flashlight.light_energy = 0.0
		flashlight.position = G.v3(G.info(mdl).get("muzzle", [0, 0, 0]))
		weapon_node.add_child(flashlight)


func muzzle() -> Vector3:
	if weapon_node == null:
		return global_position + Vector3(0, 1.4, 0)
	var d: Dictionary = Defs.WEAPONS.get(weapon_id, {})
	return weapon_node.global_transform * G.v3(G.info(d.get("model", "")).get("muzzle", [0, 0, -0.3]))


func play(a: String, length := 0.4) -> void:
	action = a
	action_t = 0.0
	action_len = length


func _process(dt: float) -> void:
	if lod or skel == null:
		return
	_t += dt
	var T = {}
	for bn in cur:
		T[bn] = Vector3.ZERO
	var hy = 0.0
	var moving = speed > 0.3
	var run: float = clamp((speed - 2.0) / 4.0, 0.0, 1.0)
	if moving and state in ["move", "idle", "crouch", "cover_low", "cover_high"]:
		phase += dt * speed * (4.6 if state != "crouch" else 6.0)
	var s = sin(phase)
	var c = cos(phase)
	var A: float = (0.38 + 0.09 * speed) if moving else 0.0
	A = min(A, 0.95)
	T["UpperArm.R"] = Vector3(0, 0, 0.07)
	T["UpperArm.L"] = Vector3(0, 0, -0.07)
	match state:
		"idle", "move":
			T["UpperLeg.R"] = Vector3(A * s, 0, 0)
			T["UpperLeg.L"] = Vector3(-A * s, 0, 0)
			T["LowerLeg.R"] = Vector3(-(0.12 + A * 1.1 * max(0.0, c)), 0, 0)
			T["LowerLeg.L"] = Vector3(-(0.12 + A * 1.1 * max(0.0, -c)), 0, 0)
			T["UpperArm.R"] = Vector3(-A * 0.8 * s, 0, 0.07)
			T["UpperArm.L"] = Vector3(A * 0.8 * s, 0, -0.07)
			T["LowerArm.R"] = Vector3(0.15 + run * 0.9 + A * 0.2, 0, 0)
			T["LowerArm.L"] = Vector3(0.15 + run * 0.9 + A * 0.2, 0, 0)
			T["Spine"] = Vector3(-0.05 - 0.2 * run + sin(_t * 1.6) * 0.012, 0, 0)
			hy = -0.035 * abs(s) * (1.0 if moving else 0.0)
		"crouch", "cover_low", "cower":
			hy = -0.34
			T["UpperLeg.R"] = Vector3(1.15 + A * 0.5 * s, 0, 0)
			T["UpperLeg.L"] = Vector3(0.85 - A * 0.5 * s, 0, 0)
			T["LowerLeg.R"] = Vector3(-1.9, 0, 0)
			T["LowerLeg.L"] = Vector3(-1.75, 0, 0)
			T["Spine"] = Vector3(-0.38, 0, 0)
			T["Head"] = Vector3(0.3, 0, 0)
			T["LowerArm.R"] = Vector3(0.8, 0, 0)
			T["LowerArm.L"] = Vector3(0.8, 0, 0)
			if state == "cower":
				T["UpperArm.R"] = Vector3(2.6, 0.4, 0)
				T["UpperArm.L"] = Vector3(2.6, -0.4, 0)
				T["LowerArm.R"] = Vector3(1.4, 0, 0)
				T["LowerArm.L"] = Vector3(1.4, 0, 0)
				T["Spine"] = Vector3(-0.7, 0, 0)
		"cover_high":
			T["UpperArm.R"] = Vector3(0.3, 0, 0.1)
			T["LowerArm.R"] = Vector3(1.7, 0, 0)
			T["UpperArm.L"] = Vector3(0.3, 0, -0.1)
			T["LowerArm.L"] = Vector3(1.2, 0, 0)
			T["UpperLeg.R"] = Vector3(A * 0.5 * s, 0, 0)
			T["UpperLeg.L"] = Vector3(-A * 0.5 * s, 0, 0)
		"air", "chute":
			T["UpperArm.R"] = Vector3(0.4, 0, 1.1) if state == "air" else Vector3(2.75, 0, 0.35)
			T["UpperArm.L"] = Vector3(0.4, 0, -1.1) if state == "air" else Vector3(2.75, 0, -0.35)
			T["UpperLeg.R"] = Vector3(0.5, 0, 0)
			T["UpperLeg.L"] = Vector3(0.15, 0, 0)
			T["LowerLeg.R"] = Vector3(-0.8, 0, 0)
			T["LowerLeg.L"] = Vector3(-0.4, 0, 0)
		"swim":
			phase += dt * (3.0 + speed * 1.2)
			T["UpperArm.R"] = Vector3(2.6 + 0.7 * sin(phase), 0, 0.2)
			T["UpperArm.L"] = Vector3(2.6 - 0.7 * sin(phase), 0, -0.2)
			T["UpperLeg.R"] = Vector3(0.35 * sin(phase * 2.0), 0, 0)
			T["UpperLeg.L"] = Vector3(-0.35 * sin(phase * 2.0), 0, 0)
			T["Head"] = Vector3(0.9, 0, 0)
		"tread":
			phase += dt * 3.0
			T["UpperArm.R"] = Vector3(0.6, 0, 1.0 + 0.3 * sin(phase))
			T["UpperArm.L"] = Vector3(0.6, 0, -1.0 - 0.3 * sin(phase))
			T["UpperLeg.R"] = Vector3(0.3 * sin(phase), 0, 0)
			T["UpperLeg.L"] = Vector3(-0.3 * sin(phase), 0, 0)
		"sit", "bike":
			hy = -0.5 if state == "sit" else -0.15
			T["UpperLeg.R"] = Vector3(1.45 if state == "sit" else 1.0, 0, 0.12)
			T["UpperLeg.L"] = Vector3(1.45 if state == "sit" else 1.0, 0, -0.12)
			T["LowerLeg.R"] = Vector3(-1.2, 0, 0)
			T["LowerLeg.L"] = Vector3(-1.2, 0, 0)
			T["UpperArm.R"] = Vector3(1.05, 0.15, 0)
			T["UpperArm.L"] = Vector3(1.05, -0.15, 0)
			T["LowerArm.R"] = Vector3(0.35, 0, 0)
			T["LowerArm.L"] = Vector3(0.35, 0, 0)
			if state == "bike":
				T["Spine"] = Vector3(-0.45, 0, 0)
				T["Head"] = Vector3(0.4, 0, 0)
		"climb":
			phase += dt * 7.0 * clamp(speed, 0.0, 1.0)
			T["UpperArm.R"] = Vector3(2.5 + 0.4 * sin(phase), 0, 0)
			T["UpperArm.L"] = Vector3(2.5 - 0.4 * sin(phase), 0, 0)
			T["UpperLeg.R"] = Vector3(0.7 - 0.5 * sin(phase), 0, 0)
			T["UpperLeg.L"] = Vector3(0.7 + 0.5 * sin(phase), 0, 0)
			T["LowerLeg.R"] = Vector3(-0.9, 0, 0)
			T["LowerLeg.L"] = Vector3(-0.9, 0, 0)
		"handsup":
			T["UpperArm.R"] = Vector3(2.9, 0, 0.35)
			T["UpperArm.L"] = Vector3(2.9, 0, -0.35)
		"phone":
			T["UpperArm.R"] = Vector3(0.7, 0.2, 0.1)
			T["LowerArm.R"] = Vector3(2.2, 0, 0)
		"dead", "limp":
			T["UpperArm.R"] = Vector3(0.4, 0, 1.2)
			T["UpperArm.L"] = Vector3(-0.2, 0, -1.0)
			T["UpperLeg.R"] = Vector3(0.25, 0, 0.15)
			T["LowerLeg.L"] = Vector3(-0.5, 0, 0)
			if state == "limp":
				T["UpperArm.R"] = Vector3(sin(_t * 9.0), 0, 1.2)
				T["UpperLeg.L"] = Vector3(sin(_t * 8.0 + 1.0) * 0.8, 0, 0)
	if aiming and not state in ["dead", "limp", "swim", "climb", "handsup", "cower"]:
		var p = aim_pitch
		T["Spine"] = Vector3(T["Spine"].x * 0.4 + p * 0.5, 0, 0)
		T["Head"] = Vector3(p * 0.2, 0, 0)
		if two_hand:
			T["UpperArm.R"] = Vector3(1.25 + p * 0.5, 0.2, 0.05)
			T["LowerArm.R"] = Vector3(0.35, 0.0, 0)
			T["UpperArm.L"] = Vector3(1.35 + p * 0.5, -0.5, 0)
			T["LowerArm.L"] = Vector3(0.45, -0.25, 0)
		else:
			T["UpperArm.R"] = Vector3(1.5 + p * 0.5, 0.12, 0)
			T["LowerArm.R"] = Vector3(0.05, 0, 0)
			if weapon_node:
				T["UpperArm.L"] = Vector3(1.4 + p * 0.5, -0.5, 0)
				T["LowerArm.L"] = Vector3(0.35, -0.3, 0)
	if action != "":
		action_t += dt
		var k: float = clamp(action_t / action_len, 0.0, 1.0)
		var bell = sin(k * PI)
		match action:
			"punch":
				T["UpperArm.R"] = Vector3(1.5 * bell + 0.3, 0.25 * bell, 0)
				T["LowerArm.R"] = Vector3(1.6 * (1.0 - bell), 0, 0)
				T["UpperArm.L"] = Vector3(0.9, -0.4, 0)
				T["LowerArm.L"] = Vector3(1.7, 0, 0)
				T["Spine"] = Vector3(-0.15 * bell, 0.35 * bell, 0)
			"swing":
				T["UpperArm.R"] = Vector3(2.6 - 2.2 * k, 0.5 * bell, 0.3)
				T["LowerArm.R"] = Vector3(0.6, 0, 0)
				T["Spine"] = Vector3(-0.25 * bell, 0.5 * (k - 0.5), 0)
			"kick":
				T["UpperLeg.R"] = Vector3(1.5 * bell, 0, 0)
				T["LowerLeg.R"] = Vector3(-0.9 * (1.0 - bell), 0, 0)
				T["Spine"] = Vector3(0.25 * bell, 0, 0)
			"block":
				T["UpperArm.R"] = Vector3(1.3, 0.5, 0)
				T["LowerArm.R"] = Vector3(1.9, 0, 0)
				T["UpperArm.L"] = Vector3(1.3, -0.5, 0)
				T["LowerArm.L"] = Vector3(1.9, 0, 0)
			"reload":
				T["UpperArm.L"] = Vector3(1.0, -0.6, 0)
				T["LowerArm.L"] = Vector3(1.3 + 0.4 * sin(k * TAU * 2.0), -0.3, 0)
				T["UpperArm.R"] = Vector3(0.9, 0.2, 0)
				T["LowerArm.R"] = Vector3(0.9, 0, 0)
			"throw":
				T["UpperArm.R"] = Vector3(3.0 - 2.2 * k, 0, 0.2)
				T["LowerArm.R"] = Vector3(1.2 * (1.0 - k), 0, 0)
				T["Spine"] = Vector3(0.2 - 0.5 * k, 0, 0)
			"hit":
				T["Spine"] = Vector3(0.35 * bell, 0, 0.2 * bell)
				T["Head"] = Vector3(0.3 * bell, 0, 0)
			"grab":
				T["UpperArm.R"] = Vector3(1.3, 0.3, 0)
				T["UpperArm.L"] = Vector3(1.3, -0.3, 0)
				T["LowerArm.R"] = Vector3(0.6 * bell, 0, 0)
				T["LowerArm.L"] = Vector3(0.6 * bell, 0, 0)
		if action_t >= action_len:
			action = ""
	var bl: float = clamp(dt * 14.0, 0.0, 1.0)
	for bn in cur:
		var v: Vector3 = cur[bn].lerp(T[bn], bl)
		cur[bn] = v
		var i: int = idx[bn]
		if bn == "Hips":
			continue
		var q = Basis.from_euler(v).get_rotation_quaternion()
		var g: Quaternion = rest_g[bn]
		skel.set_bone_pose_rotation(i, rest_l[bn] * (g.inverse() * q * g))
	hips_y = lerpf(hips_y, hy, bl)
	skel.set_bone_pose_position(idx["Hips"], hips_rest + Vector3(0, hips_y, 0))
	if flashlight:
		flashlight.light_energy = 3.0 if aiming else 0.0
