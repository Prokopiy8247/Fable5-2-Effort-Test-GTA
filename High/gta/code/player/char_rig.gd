class_name CharRig
extends Node3D
## Blender-authored humanoid + fully procedural animation (FK layers + 2-bone arm IK). Shared by player and NPCs.

enum {HIPS, SPINE, CHEST, NECK, HEAD, UA_L, LA_L, HAND_L, UA_R, LA_R, HAND_R, UL_L, LL_L, FOOT_L, UL_R, LL_R, FOOT_R, NB}
const BONE_NAMES := ["Hips", "Spine", "Chest", "Neck", "Head", "UpperArm_L", "LowerArm_L", "Hand_L", "UpperArm_R", "LowerArm_R", "Hand_R",
	"UpperLeg_L", "LowerLeg_L", "Foot_L", "UpperLeg_R", "LowerLeg_R", "Foot_R"]

static var _mat_cache: Dictionary = {}

var skel: Skeleton3D
var model: Node3D
var look: Dictionary = {}
var bone: PackedInt32Array = PackedInt32Array()
var _rest_local: Array[Basis] = []
var _gr: Array[Basis] = []
var _a: Array[Basis] = []
var _cur: Array[Vector3] = []
var _tgt: Array[Vector3] = []
var _hips_rest := Vector3.ZERO
var _hips_off := Vector3.ZERO
var _arm_len := Vector2(0.28, 0.26)
var height_scale := 1.0

# animation inputs (set by owner)
var speed := 0.0
var phase := 0.0
var crouch := 0.0
var aim := 0.0
var aim_pitch := 0.0
var hold := "none"
var sit := 0.0
var bike := 0.0
var swim := 0.0
var fall := 0.0
var limp := 0.0
var hands_up := 0.0
var cower := 0.0
var phone := 0.0
var climb := 0.0
var chute := 0.0
var dead := 0.0
var attack_t := -1.0       # 0..1 while a melee swing plays
var attack_kind := 0       # 0 right jab, 1 left jab, 2 heavy, 3 weapon swing, 4 throw
var hit_t := 0.0
var steer := 0.0
var block := 0.0
var lean := 0.0
var look_yaw := 0.0
var blind_fire := 0.0
var time := 0.0
var lod_skip := 0
var _frame := 0

# weapon
var weapon_node: Node3D
var weapon_model: Node3D
var weapon_def: WeaponDef
var muzzle: Node3D
var flashlight: SpotLight3D
var recoil_kick := 0.0


func setup(p_look: Dictionary, npc: bool = false) -> void:
	look = p_look
	var asset := "char_female" if look.get("gender", "male") == "female" else "char_male"
	model = Assets.inst(asset)
	add_child(model)
	skel = _find_skel(model)
	height_scale = look.get("scale", 1.0)
	model.scale = Vector3.ONE * height_scale
	bone.resize(NB)
	_rest_local.resize(NB)
	_gr.resize(NB)
	_a.resize(NB)
	_cur.resize(NB)
	_tgt.resize(NB)
	for i in range(NB):
		var b := skel.find_bone(BONE_NAMES[i])
		bone[i] = b
		_rest_local[i] = skel.get_bone_rest(b).basis.orthonormalized()
		_gr[i] = skel.get_bone_global_rest(b).basis.orthonormalized()
		_a[i] = _rest_local[i] * _gr[i].inverse()
		_cur[i] = Vector3.ZERO
		_tgt[i] = Vector3.ZERO
	_hips_rest = skel.get_bone_rest(bone[HIPS]).origin
	var s := skel.get_bone_global_rest(bone[UA_R]).origin
	var e := skel.get_bone_global_rest(bone[LA_R]).origin
	var w := skel.get_bone_global_rest(bone[HAND_R]).origin
	_arm_len = Vector2(s.distance_to(e), e.distance_to(w))
	weapon_node = Node3D.new()
	model.add_child(weapon_node)
	apply_look(npc)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null


static func color_mat(c: Color, rough: float = 0.85) -> StandardMaterial3D:
	var key := c.to_html(false) + str(int(rough * 10))
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic_specular = 0.3
	_mat_cache[key] = m
	return m


func apply_look(npc: bool = false) -> void:
	var extras: Array = look.get("extras", [])
	var want := {}
	for k in ["hair", "hat", "glasses", "beard"]:
		var v: String = look.get(k, "none")
		if v != "none":
			want[v] = true
	for ex in extras:
		want[ex] = true
	var skin: Color = look.get("skin", Color("d9a27e"))
	var shirt: Color = look.get("shirt", Color.WHITE)
	var pants: Color = look.get("pants", Color("30384f"))
	var cols := {
		"M_Skin": skin, "M_Shirt": shirt, "M_Sleeve": shirt if int(look.get("sleeves", 0)) == 1 else skin,
		"M_Pants": pants, "M_Shin": skin if int(look.get("shorts", 0)) == 1 else pants, "M_Shoes": look.get("shoes", Color("26221f")),
		"M_Hair": look.get("hair_color", Color("3a2a1e")), "M_Hat": look.get("hat_color", Color("c8382b")),
	}
	for c in skel.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi: MeshInstance3D = c
		var nm := String(mi.name)
		var is_att := nm.contains("_att_")
		if is_att:
			var an := nm.substr(nm.find("_att_") + 5)
			var on: bool = want.has(an)
			if npc and not on:
				mi.queue_free()
				continue
			mi.visible = on
			if an == "jacket":
				cols["M_Hat"] = look.get("jacket_color", look.get("hat_color", Color("c8382b")))
		for si in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(si)
			if m and cols.has(m.resource_name):
				var col: Color = cols[m.resource_name]
				if is_att and m.resource_name == "M_Hat" and not nm.ends_with("jacket"):
					col = look.get("hat_color", col)
				mi.set_surface_override_material(si, color_mat(col))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.extra_cull_margin = 1.0


func set_extra(extra: String, on: bool) -> void:
	var ex: Array = look.get("extras", [])
	if on and not ex.has(extra):
		ex.append(extra)
	elif not on:
		ex.erase(extra)
	look["extras"] = ex
	for c in skel.get_children():
		if c is MeshInstance3D and String(c.name).ends_with("_att_" + extra):
			c.visible = on


# ------------------------------------------------------------------ weapon visuals
func set_weapon(def: WeaponDef, mods: Array = [], tint: Color = Color(0.16, 0.17, 0.19)) -> void:
	weapon_def = def
	if weapon_model:
		weapon_model.queue_free()
		weapon_model = null
	muzzle = null
	flashlight = null
	hold = "none"
	if def == null:
		return
	hold = def.hold
	if def.model == "":
		return
	weapon_model = Assets.inst(def.model)
	weapon_node.add_child(weapon_model)
	muzzle = Assets.find(weapon_model, "_muzzle")
	var fin := color_mat(tint, 0.45)
	for n in Assets.find_all(weapon_model, "w_"):
		if n is MeshInstance3D:
			var nm := String(n.name)
			if nm.contains("_att_"):
				var an := nm.substr(nm.find("_att_") + 5)
				n.visible = mods.has(an)
				if an == "flashlight" and mods.has(an):
					flashlight = SpotLight3D.new()
					flashlight.light_energy = 6.0
					flashlight.spot_range = 38.0
					flashlight.spot_angle = 22.0
					flashlight.shadow_enabled = false
					flashlight.visible = false
					n.add_child(flashlight)
					flashlight.position = Vector3(0, 0.03, -0.3)
			for si in range(n.mesh.get_surface_count()):
				var m: Material = n.mesh.surface_get_material(si)
				if m and m.resource_name == "M_Finish":
					n.set_surface_override_material(si, fin)


func muzzle_pos() -> Vector3:
	if muzzle and is_instance_valid(muzzle):
		return muzzle.global_position
	return global_transform * Vector3(0.2, 1.4 * height_scale, -0.5)


func head_pos() -> Vector3:
	return global_transform * Vector3(0, 1.66 * height_scale, 0)


# ------------------------------------------------------------------ animation
func tick(delta: float, visible_hint: bool = true) -> void:
	time += delta
	_frame += 1
	if lod_skip > 0 and (_frame % (lod_skip + 1)) != 0:
		return
	if not visible_hint:
		return
	var dt := delta * float(lod_skip + 1)
	_compute_targets()
	var k := 1.0 - exp(-14.0 * dt)
	for i in range(NB):
		_cur[i] = _cur[i].lerp(_tgt[i], k)
		var d := Basis.from_euler(_cur[i])
		skel.set_bone_pose_rotation(bone[i], (_a[i] * d * _gr[i]).get_rotation_quaternion())
	var ho := _hips_target()
	_hips_off = _hips_off.lerp(ho, k)
	skel.set_bone_pose_position(bone[HIPS], _hips_rest + _hips_off)
	recoil_kick = move_toward(recoil_kick, 0.0, dt * 6.0)
	_update_weapon()


func _hips_target() -> Vector3:
	var o := Vector3.ZERO
	if sit > 0.5 or bike > 0.5:
		return o
	o.y -= crouch * 0.36
	o.y -= cower * 0.42
	if speed > 0.3 and swim < 0.5 and fall < 0.5:
		o.y -= absf(sin(phase)) * 0.035 * clampf(speed / 3.0, 0.3, 1.6)
	if dead > 0.5:
		o.y = 0.0
	return o


func _compute_targets() -> void:
	for i in range(NB):
		_tgt[i] = Vector3.ZERO
	var run := clampf((speed - 1.6) / 4.0, 0.0, 1.0)
	var mv := clampf(speed / 1.4, 0.0, 1.0)
	var sp := sin(phase)
	var cp := cos(phase)
	# ---- base idle
	_tgt[UA_L] = Vector3(0, 0, -0.07)
	_tgt[UA_R] = Vector3(0, 0, 0.07)
	_tgt[LA_L] = Vector3(0.12, 0, 0)
	_tgt[LA_R] = Vector3(0.12, 0, 0)
	_tgt[CHEST].x = sin(time * 1.6) * 0.015
	# ---- locomotion
	if mv > 0.01:
		var amp := lerpf(0.42, 0.85, run) * mv
		var knee := lerpf(0.8, 1.5, run) * mv
		_tgt[UL_L].x = amp * sp
		_tgt[UL_R].x = -amp * sp
		_tgt[LL_L].x = -(0.1 + knee * maxf(0.0, cp))
		_tgt[LL_R].x = -(0.1 + knee * maxf(0.0, -cp))
		_tgt[FOOT_L].x = 0.25 * maxf(0.0, -sp) * mv
		_tgt[FOOT_R].x = 0.25 * maxf(0.0, sp) * mv
		var aa := lerpf(0.35, 0.9, run) * mv
		_tgt[UA_L].x = -aa * sp
		_tgt[UA_R].x = aa * sp
		_tgt[LA_L].x = 0.2 + run * 1.0
		_tgt[LA_R].x = 0.2 + run * 1.0
		_tgt[SPINE].x = -0.04 - run * 0.16
		_tgt[CHEST].y = 0.09 * sp * mv
		_tgt[HIPS].y = -0.06 * sp * mv
	# ---- crouch / cower
	var cr := maxf(crouch, cower)
	if cr > 0.01:
		_tgt[UL_L].x += 1.0 * cr
		_tgt[UL_R].x += 0.75 * cr
		_tgt[LL_L].x -= 1.55 * cr
		_tgt[LL_R].x -= 1.7 * cr
		_tgt[SPINE].x -= 0.3 * cr
		_tgt[HEAD].x += 0.22 * cr
	if cower > 0.01:
		_tgt[UA_L] = Vector3(2.5, -0.4, 0) * cower
		_tgt[UA_R] = Vector3(2.5, 0.4, 0) * cower
		_tgt[LA_L].x = 2.0 * cower
		_tgt[LA_R].x = 2.0 * cower
		_tgt[SPINE].x -= 0.35 * cower
	if hands_up > 0.01:
		_tgt[UA_L] = Vector3(2.7, 0, -0.25) * hands_up
		_tgt[UA_R] = Vector3(2.7, 0, 0.25) * hands_up
		_tgt[LA_L].x = 0.3
		_tgt[LA_R].x = 0.3
	if phone > 0.01:
		_tgt[UA_R] = Vector3(1.0, 0.0, 0.5) * phone
		_tgt[LA_R].x = 2.3 * phone
		_tgt[HEAD].z = -0.15 * phone
	# ---- seated
	if sit > 0.01:
		_tgt[UL_L] = Vector3(1.45, 0, -0.08)
		_tgt[UL_R] = Vector3(1.45, 0, 0.08)
		_tgt[LL_L].x = -1.25
		_tgt[LL_R].x = -1.25
		_tgt[FOOT_L].x = 0.3
		_tgt[FOOT_R].x = 0.3
		_tgt[SPINE].x = 0.06
		_tgt[UA_L] = Vector3(0.95 + steer * 0.25, -0.25, 0)
		_tgt[UA_R] = Vector3(0.95 - steer * 0.25, 0.25, 0)
		_tgt[LA_L].x = 0.55
		_tgt[LA_R].x = 0.55
		_tgt[CHEST].y = 0.0
	if bike > 0.01:
		_tgt[UL_L] = Vector3(1.15, 0, -0.32)
		_tgt[UL_R] = Vector3(1.15, 0, 0.32)
		_tgt[LL_L].x = -1.5
		_tgt[LL_R].x = -1.5
		_tgt[SPINE].x = -0.42
		_tgt[HEAD].x = 0.35
		_tgt[UA_L] = Vector3(1.15, -0.1 + steer * 0.2, -0.25)
		_tgt[UA_R] = Vector3(1.15, 0.1 + steer * 0.2, 0.25)
		_tgt[LA_L].x = 0.3
		_tgt[LA_R].x = 0.3
	# ---- swim / fall / parachute / climb
	if swim > 0.01:
		var st := sin(time * 5.0)
		if speed > 0.6:
			_tgt[UA_L] = Vector3(2.7 + 0.5 * sin(time * 5.0), 0, -0.2)
			_tgt[UA_R] = Vector3(2.7 + 0.5 * sin(time * 5.0 + PI), 0, 0.2)
			_tgt[LA_L].x = 0.25
			_tgt[LA_R].x = 0.25
			_tgt[UL_L].x = 0.3 * st
			_tgt[UL_R].x = -0.3 * st
			_tgt[LL_L].x = -0.25 - 0.2 * st
			_tgt[LL_R].x = -0.25 + 0.2 * st
			_tgt[HEAD].x = 0.9
		else:
			_tgt[UA_L] = Vector3(0.6, 0, -1.0 - 0.2 * st)
			_tgt[UA_R] = Vector3(0.6, 0, 1.0 + 0.2 * st)
			_tgt[LA_L].x = 0.5
			_tgt[LA_R].x = 0.5
			_tgt[UL_L].x = 0.35 * st
			_tgt[UL_R].x = -0.35 * st
			_tgt[LL_L].x = -0.5
			_tgt[LL_R].x = -0.5
	if fall > 0.01:
		var fl := sin(time * 11.0) * 0.25
		_tgt[UA_L] = Vector3(0.6 + fl, 0, -1.5)
		_tgt[UA_R] = Vector3(0.6 - fl, 0, 1.5)
		_tgt[LA_L].x = 0.5
		_tgt[LA_R].x = 0.5
		_tgt[UL_L].x = 0.5 + fl
		_tgt[UL_R].x = 0.2 - fl
		_tgt[LL_L].x = -0.8
		_tgt[LL_R].x = -0.5
	if chute > 0.01:
		_tgt[UA_L] = Vector3(2.6, 0, -0.45 - steer * 0.3)
		_tgt[UA_R] = Vector3(2.6, 0, 0.45 - steer * 0.3)
		_tgt[LA_L].x = 0.5
		_tgt[LA_R].x = 0.5
		_tgt[UL_L].x = 0.35
		_tgt[UL_R].x = 0.25
		_tgt[LL_L].x = -0.5
		_tgt[LL_R].x = -0.4
	if climb > 0.01:
		var cs := sin(phase)
		_tgt[UA_L] = Vector3(2.2 + 0.5 * cs, 0, -0.1)
		_tgt[UA_R] = Vector3(2.2 - 0.5 * cs, 0, 0.1)
		_tgt[LA_L].x = 0.9 - 0.4 * cs
		_tgt[LA_R].x = 0.9 + 0.4 * cs
		_tgt[UL_L].x = 0.7 - 0.5 * cs
		_tgt[UL_R].x = 0.7 + 0.5 * cs
		_tgt[LL_L].x = -1.0 + 0.5 * cs
		_tgt[LL_R].x = -1.0 - 0.5 * cs
	# ---- upper body weapon poses (FK fallback; IK refines hands while aiming)
	if aim > 0.01 and sit < 0.5:
		var p := aim_pitch
		if hold == "pistol" or hold == "thrown":
			_tgt[UA_R] = Vector3(1.45 + p, 0.22, 0)
			_tgt[LA_R].x = 0.1
			_tgt[UA_L] = Vector3(1.38 + p, -0.42, 0)
			_tgt[LA_L].x = 0.25
		elif hold == "rifle" or hold == "launcher":
			_tgt[UA_R] = Vector3(1.05 + p * 0.9, 0.1, 0.25)
			_tgt[LA_R].x = 1.1
			_tgt[UA_L] = Vector3(1.35 + p, -0.6, 0)
			_tgt[LA_L].x = 0.4
		_tgt[SPINE].x += -p * 0.25
		_tgt[CHEST].y += 0.25 if hold != "pistol" else 0.0
		_tgt[HEAD].y -= 0.2 if hold != "pistol" else 0.0
	elif sit > 0.5 and aim > 0.01:
		_tgt[UA_R] = Vector3(1.4 + aim_pitch, look_yaw, 0)
		_tgt[LA_R].x = 0.15
	elif (hold == "rifle" or hold == "launcher") and sit < 0.5 and swim < 0.5 and climb < 0.5:
		_tgt[UA_R] = Vector3(0.25, 0.0, 0.3)
		_tgt[LA_R].x = 1.45
		_tgt[UA_L] = Vector3(0.9, -0.75, 0)
		_tgt[LA_L].x = 1.0
	if blind_fire > 0.01:
		_tgt[UA_R] = Vector3(2.3, 0.1, 0.3)
		_tgt[LA_R].x = 0.6
	# ---- melee / throw
	if attack_t >= 0.0:
		var a := attack_t
		var strike := sin(clampf(a, 0.0, 1.0) * PI)
		match attack_kind:
			0:
				_tgt[UA_R] = Vector3(0.5 + 1.0 * strike, 0.3 * strike, 0.2)
				_tgt[LA_R].x = 1.9 - 1.8 * strike
				_tgt[CHEST].y = 0.45 * strike
				_tgt[UA_L] = Vector3(0.7, -0.3, 0)
				_tgt[LA_L].x = 1.9
			1:
				_tgt[UA_L] = Vector3(0.5 + 1.0 * strike, -0.3 * strike, -0.2)
				_tgt[LA_L].x = 1.9 - 1.8 * strike
				_tgt[CHEST].y = -0.45 * strike
				_tgt[UA_R] = Vector3(0.7, 0.3, 0)
				_tgt[LA_R].x = 1.9
			2:
				_tgt[UA_R] = Vector3(lerpf(-0.6, 1.7, a), 0.5 * strike, 0.5)
				_tgt[LA_R].x = lerpf(1.6, 0.2, a)
				_tgt[CHEST].y = lerpf(-0.6, 0.7, a)
				_tgt[SPINE].x = -0.25 * strike
			3:
				_tgt[UA_R] = Vector3(lerpf(2.7, 0.5, a), lerpf(-0.3, 0.7, a), 0.3)
				_tgt[LA_R].x = lerpf(1.0, 0.3, a)
				_tgt[CHEST].y = lerpf(-0.5, 0.6, a)
			4:
				_tgt[UA_R] = Vector3(lerpf(3.0, 1.2, a), 0.0, 0.4)
				_tgt[LA_R].x = lerpf(1.4, 0.1, a)
				_tgt[CHEST].y = lerpf(-0.5, 0.4, a)
	if block > 0.01:
		_tgt[UA_L] = Vector3(1.3, -0.5, 0)
		_tgt[LA_L].x = 2.0
		_tgt[UA_R] = Vector3(1.3, 0.5, 0)
		_tgt[LA_R].x = 2.0
	# ---- reactions
	if hit_t > 0.01:
		_tgt[SPINE].x += 0.4 * hit_t
		_tgt[HEAD].x += 0.3 * hit_t
		_tgt[CHEST].y += 0.5 * hit_t * sin(time * 30.0)
	if limp > 0.01 or dead > 0.01:
		var w := maxf(limp, dead)
		var wob := sin(time * 9.0) * 0.4 * limp
		_tgt[UA_L] = Vector3(0.4 + wob, 0, -1.3) * w
		_tgt[UA_R] = Vector3(0.2 - wob, 0, 1.1) * w
		_tgt[LA_L].x = 0.6 * w
		_tgt[LA_R].x = 0.9 * w
		_tgt[UL_L] = Vector3(0.3 + wob, 0, -0.25) * w
		_tgt[UL_R] = Vector3(-0.1 - wob, 0, 0.3) * w
		_tgt[LL_L].x = -0.7 * w
		_tgt[LL_R].x = -0.3 * w
		_tgt[HEAD] = Vector3(0.2, 0.5, 0) * w
		_tgt[SPINE].x = 0.1
	_tgt[SPINE].z += lean * 0.5
	_tgt[HEAD].y += look_yaw * 0.6
	_tgt[NECK].y += look_yaw * 0.3


func _aim_basis() -> Basis:
	return Basis(Vector3.RIGHT, aim_pitch + recoil_kick * 0.12)


func _update_weapon() -> void:
	if weapon_model == null or not is_instance_valid(weapon_model):
		return
	var inv := model.global_transform.affine_inverse() * skel.global_transform
	var aiming := aim > 0.5 or blind_fire > 0.5
	if hold == "melee" or hold == "thrown" or (not aiming and hold == "pistol") or sit > 0.5 or swim > 0.5 or climb > 0.5 or chute > 0.5 or dead > 0.5 or limp > 0.5:
		# follow the right hand
		var hg := skel.get_bone_global_pose(bone[HAND_R])
		var hp: Vector3 = inv * (hg.origin + hg.basis.orthonormalized() * Vector3(0, 0.07, 0))
		weapon_node.position = hp
		var b := Basis.IDENTITY
		if hold == "melee":
			var fore: Vector3 = (hg.basis.orthonormalized() * Vector3(0, 1, 0)).normalized()
			var fwd: Vector3 = (Vector3(0, 0.55, -0.85) + fore * 0.9).normalized()
			if attack_t >= 0.0:
				fwd = (fore + Vector3(0, 0.3, -0.5)).normalized()
			b = _basis_fwd(fwd)
		elif sit > 0.5 and aim > 0.5:
			b = Basis(Vector3.UP, look_yaw) * Basis(Vector3.RIGHT, aim_pitch)
		elif hold == "pistol":
			b = Basis(Vector3.RIGHT, -1.15)
		elif hold == "thrown":
			b = Basis.IDENTITY
		else:
			b = Basis(Vector3.RIGHT, -0.9)
		weapon_node.basis = b
		weapon_node.visible = not (swim > 0.5 or climb > 0.5 or chute > 0.5)
		if flashlight:
			flashlight.visible = false
		return
	weapon_node.visible = true
	var chest := skel.get_bone_global_pose(bone[CHEST])
	var sh: Vector3 = inv * (chest.origin + Vector3(0, 0.17 * height_scale, 0))
	var ab := _aim_basis()
	var grip_pos: Vector3
	var wb: Basis
	if aiming:
		wb = ab
		if blind_fire > 0.5:
			grip_pos = sh + Vector3(0.28, 0.42, -0.25)
		elif hold == "pistol":
			grip_pos = sh + ab * Vector3(0.1, -0.03, -0.5 + recoil_kick * 0.05)
		else:
			grip_pos = sh + ab * Vector3(0.17, -0.1, -0.26 + recoil_kick * 0.05)
	else:
		wb = Basis(Vector3.UP, 0.75) * Basis(Vector3.RIGHT, -0.5)
		grip_pos = sh + Vector3(0.16, -0.32, -0.2)
	weapon_node.position = grip_pos
	weapon_node.basis = wb
	if flashlight:
		flashlight.visible = aim > 0.5
	# IK both hands onto the weapon (skeleton space == model space for this rig)
	var to_skel := inv.affine_inverse()
	var rt: Vector3 = to_skel * (grip_pos + wb * Vector3(0, -0.02, 0.02))
	_ik_arm(UA_R, LA_R, rt, Vector3(0.6, -1.0, 0.2))
	if blind_fire < 0.5:
		var fore_off := Vector3(0, 0.0, -0.3) if hold != "pistol" else Vector3(-0.03, -0.04, 0.0)
		var lt: Vector3 = to_skel * (grip_pos + wb * fore_off)
		_ik_arm(UA_L, LA_L, lt, Vector3(-0.7, -1.0, 0.2))


func _basis_fwd(fwd: Vector3) -> Basis:
	var up := Vector3.UP
	if absf(fwd.dot(up)) > 0.98:
		up = Vector3.BACK
	var z := -fwd
	var xx := up.cross(z).normalized()
	var yy := z.cross(xx).normalized()
	return Basis(xx, yy, z)


func _ik_arm(ua: int, la: int, target: Vector3, pole: Vector3) -> void:
	var ub := bone[ua]
	var lb := bone[la]
	var parent_g := skel.get_bone_global_pose(skel.get_bone_parent(ub)).basis.orthonormalized()
	var s := skel.get_bone_global_pose(ub).origin
	var l1 := _arm_len.x * 1.0
	var l2 := _arm_len.y * 1.25  # include part of the hand
	var to := target - s
	var dist := clampf(to.length(), 0.08, l1 + l2 - 0.005)
	var dir := to.normalized()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var a := acos(cos_a)
	var bend := pole - dir * pole.dot(dir)
	if bend.length() < 0.001:
		bend = Vector3.DOWN
	bend = bend.normalized()
	var elbow := s + (dir * cos(a) + bend * sin(a)) * l1
	var d1 := (elbow - s).normalized()
	var d2 := (s + dir * dist - elbow).normalized()
	var rest1: Vector3 = (_gr[ua] * Vector3.UP).normalized()
	var g1 := Basis(Quaternion(rest1, d1)) * _gr[ua]
	skel.set_bone_pose_rotation(ub, (parent_g.inverse() * g1).get_rotation_quaternion())
	var rest2: Vector3 = (_gr[la] * Vector3.UP).normalized()
	var g2 := Basis(Quaternion(rest2, d2)) * _gr[la]
	skel.set_bone_pose_rotation(lb, (g1.inverse() * g2).get_rotation_quaternion())
	_cur[ua] = _tgt[ua]
	_cur[la] = _tgt[la]


func hand_pos(right: bool = true) -> Vector3:
	return skel.global_transform * skel.get_bone_global_pose(bone[HAND_R if right else HAND_L]).origin


func snap() -> void:
	## Jump straight to the target pose (after teleports / state switches).
	_compute_targets()
	for i in range(NB):
		_cur[i] = _tgt[i]
