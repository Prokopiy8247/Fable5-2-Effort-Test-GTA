class_name AnimalRig
extends RefCounted
## Procedural animation of one rigid-part animal (docs/NATURE_ANIMALS.md section 3).
##
## The GLB parts (Body, Head, Leg_FL/FR/RL/RR, Tail, Wing_L/R, Legs, Fin_L/R) are SIBLINGS under the
## asset root with their origins on the joints, so the rig only rotates parts and moves the visual
## root (bob, slope pitch, bank, death roll). Everything is driven by plain parameters on the body
## (AnimalBody): anim_speed, anim_pose, look_yaw, wag, alert, flap, glide, fold, action, death_t.
##
## Gaits (land): walk = 4-beat lateral sequence, trot = diagonal pairs, gallop = rotary sequence,
## hop = rabbit bound (front pair / hind pair). Leg swing about X (+ = foot forward), body drops by the
## rigid-leg height loss so the feet stay on the ground, head nods at twice the stride frequency.

const DEG := PI / 180.0
const WALK_OFF := [0.25, 0.75, 0.0, 0.5]       ## FL, FR, RL, RR
const TROT_OFF := [0.0, 0.5, 0.5, 0.0]
const GALLOP_OFF := [0.0, 0.12, 0.6, 0.48]
const LEG_NAMES := ["Leg_FL", "Leg_FR", "Leg_RL", "Leg_RR"]

var visual: Node3D = null            ## the FileRoot instance (child of the body); gets bob / pitch / roll
var parts: Dictionary = {}           ## part name -> Node3D
var rest_pos: Dictionary = {}        ## part name -> Vector3
var rest_scale: Dictionary = {}      ## part name -> Vector3
var kind := "land"
var style := "quad"
var leg_len := 0.5
var shoulder := 0.6
var body_y := 0.5                    ## rest height of the Body part (death roll pivot)
var lie_h := 0.15                    ## body centre height when lying on its side
var length := 1.0
var graze_pitch := -65.0
var stride := PackedFloat32Array([1.0, 1.6, 3.0])
var speeds := PackedFloat32Array([1.0, 2.5, 6.0])   ## walk / trot / run
var flap_hz := 5.0
var folded: Dictionary = {}          ## bird wing pose: part -> [rot_deg Vector3, scale Vector3]
var flight_legs := Vector3(-80.0, 0.0, 0.0)

var phase := 0.0
var t := 0.0
var head_pitch := 0.0
var head_yaw := 0.0
var tail_lift := 0.0
var flap_phase := 0.0
var fold_cur := 1.0
var tuck_cur := 0.0
var _gait_w := Vector3(1.0, 0.0, 0.0)  ## walk / trot / gallop weights (smoothed)
var _amp := 0.0
var _peck := 0.0
var _hop := 0.0


func setup(vis: Node3D, def: Dictionary) -> void:
	visual = vis
	kind = String(def.get("kind", "land"))
	style = String(def.get("gait_style", "quad"))
	var root := vis
	var named := vis.find_child(String(def.get("id", "")), true, false) as Node3D
	if named != null:
		root = named
	for c: Node in root.get_children():
		if c is Node3D:
			var n := c as Node3D
			parts[String(n.name)] = n
			rest_pos[String(n.name)] = n.position
			rest_scale[String(n.name)] = n.scale
	var sz: Vector3 = def.get("size_v", Vector3(0.5, 0.5, 0.5))
	leg_len = maxf(float(def.get("leg_length", 0.4)), 0.05)
	shoulder = maxf(float(def.get("shoulder_height", 0.4)), 0.05)
	length = maxf(float(def.get("length", sz.z)), 0.1)
	graze_pitch = float(def.get("graze_head_pitch_deg", -65.0))
	if parts.has("Body"):
		body_y = (rest_pos["Body"] as Vector3).y
	lie_h = clampf(minf(sz.x, sz.y) * 0.32, 0.03, 0.4)
	if def.has("body_radius"):
		lie_h = clampf(float(def["body_radius"]) * 0.42, 0.03, 0.42)
	stride = PackedFloat32Array([float(def.get("stride_walk", length * 0.9)), float(def.get("stride_trot", length * 1.5)),
			float(def.get("stride_run", length * 2.8))])
	speeds = PackedFloat32Array([float(def.get("walk_speed", 1.0)),
			float(def.get("trot_speed", float(def.get("walk_speed", 1.0)) * 2.5)), float(def.get("run_speed", 5.0))])
	flap_hz = float(def.get("flap_hz", 5.0))
	var poses: Dictionary = def.get("poses", {})
	var fp: Dictionary = poses.get("folded", {})
	for part: String in fp:
		var p: Dictionary = fp[part]
		folded[part] = [_v3(p.get("rotation_degrees", [0, 0, 0])), _v3(p.get("scale", [1, 1, 1]))]
	var fl: Dictionary = poses.get("flight", {})
	if fl.has("Legs"):
		flight_legs = _v3((fl["Legs"] as Dictionary).get("rotation_degrees", [-80, 0, 0]))
	phase = randf()
	t = randf() * 10.0


static func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


func reset_pose() -> void:
	for n: String in parts:
		var p := parts[n] as Node3D
		if is_instance_valid(p):
			p.position = rest_pos[n]
			p.rotation = Vector3.ZERO
			p.scale = rest_scale[n]
	if visual != null:
		visual.transform = Transform3D.IDENTITY
	head_pitch = 0.0
	head_yaw = 0.0
	fold_cur = 1.0
	tuck_cur = 0.0


func _rot(part: String, deg: Vector3) -> void:
	var n: Node3D = parts.get(part, null)
	if n != null:
		n.rotation = deg * DEG


## One animation step. `b` is the AnimalBody (duck-typed: only plain members are read).
func update(b: Object, dt: float) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	t += dt
	match kind:
		"bird":
			_update_bird(b, dt)
		"fish":
			_update_fish(b, dt)
		_:
			_update_land(b, dt)


# =================================================================================================
# land
# =================================================================================================

func _update_land(b: Object, dt: float) -> void:
	var death_t: float = b.death_t
	var pose: String = b.anim_pose
	var sp: float = absf(float(b.anim_speed))
	var k := 1.0 - exp(-dt * 8.0)
	# --- gait weights ------------------------------------------------------------------------
	var w := Vector3(1.0, 0.0, 0.0)
	if sp > speeds[1] * 1.15:
		w = Vector3(0.0, 0.0, 1.0)
	elif sp > speeds[0] * 1.35:
		w = Vector3(0.0, 1.0, 0.0)
	_gait_w = _gait_w.lerp(w, 1.0 - exp(-dt * 5.0))
	var st := stride[0] * _gait_w.x + stride[1] * _gait_w.y + stride[2] * _gait_w.z
	var freq := minf(sp / maxf(st, 0.05), 5.5)
	phase = fmod(phase + freq * dt, 1.0)
	var amp_target := (22.0 * _gait_w.x + 30.0 * _gait_w.y + 44.0 * _gait_w.z) * smoothstep(0.03, speeds[0] * 0.55, sp)
	if death_t > 0.0:
		amp_target = 0.0
	_amp = lerpf(_amp, amp_target, k)
	var tau := TAU * phase
	var bob := 0.0
	var body_pitch := 0.0
	var leg_a := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	if style == "hop":
		# bound: hind pair pushes, front pair reaches; the body arcs through the air
		var hop_w := smoothstep(0.05, speeds[0] * 0.8, sp)
		var s1 := sin(tau)
		leg_a[0] = (18.0 + 26.0 * _gait_w.z) * s1 * hop_w
		leg_a[1] = leg_a[0]
		leg_a[2] = -(26.0 + 30.0 * _gait_w.z) * sin(tau + 1.9) * hop_w
		leg_a[3] = leg_a[2]
		_hop = maxf(0.0, sin(tau + 0.4)) * (0.03 + 0.12 * _gait_w.z + 0.04 * _gait_w.y) * hop_w
		bob = _hop
		body_pitch = 9.0 * cos(tau + 0.4) * hop_w
	else:
		var max_cos := 0.0
		for i in 4:
			var a := _gait_w.x * sin(TAU * (phase + float(WALK_OFF[i]))) \
					+ _gait_w.y * sin(TAU * (phase + float(TROT_OFF[i]))) \
					+ _gait_w.z * sin(TAU * (phase + float(GALLOP_OFF[i])))
			# hind legs swing a little less and further back (hock silhouette)
			var leg := a * _amp * (1.0 if i < 2 else 0.9)
			leg_a[i] = leg
			max_cos = maxf(max_cos, cos(leg * DEG))
		# the most vertical leg carries the body: drop by the rigid-leg height loss
		bob = -leg_len * (1.0 - max_cos)
		bob += sin(2.0 * tau) * shoulder * (0.008 * _gait_w.x + 0.02 * _gait_w.y)
		bob += maxf(0.0, sin(tau + 0.8)) * shoulder * 0.07 * _gait_w.z * smoothstep(speeds[1], speeds[2], sp)
		body_pitch = 5.0 * sin(tau + 0.6) * _gait_w.z * smoothstep(speeds[1], speeds[2], sp)
	# --- action overlays ---------------------------------------------------------------------
	var action: String = b.action
	var at: float = b.action_t
	var ad: float = maxf(float(b.action_dur), 0.01)
	var act_u := clampf(at / ad, 0.0, 1.0)
	var act_w := sin(act_u * PI) if action != "" else 0.0
	# --- head -------------------------------------------------------------------------------
	var hp := 0.0
	match pose:
		"graze":
			hp = graze_pitch
		"sniff":
			hp = -34.0
		"alert":
			hp = 10.0
		"bark":
			hp = 8.0
		"stalk":
			hp = -16.0
		"sit":
			hp = 4.0
	if sp > speeds[1] * 1.2 and pose != "stalk":
		hp = -7.0
	head_pitch = lerpf(head_pitch, hp, 1.0 - exp(-dt * 5.0))
	head_yaw = lerpf(head_yaw, clampf(float(b.look_yaw), -1.05, 1.05) / DEG, 1.0 - exp(-dt * 6.0))
	var nod := sin(2.0 * tau) * (4.0 * _gait_w.x + 2.0 * _gait_w.y) * smoothstep(0.05, 0.6, sp) \
			+ sin(tau + 1.0) * 6.0 * _gait_w.z * smoothstep(speeds[1], speeds[2], sp)
	var chew := sin(t * 9.0) * 2.5 if pose == "graze" and sp < 0.1 else 0.0
	if pose == "sniff" and sp < 0.2:
		chew = sin(t * 13.0) * 3.0
	var act_pitch := 0.0
	match action:
		"bite":
			act_pitch = -22.0 * act_w + 10.0 * sin(act_u * TAU) * act_w
		"bark":
			act_pitch = 14.0 * act_w
		"flinch":
			act_pitch = 12.0 * act_w
		"shake":
			act_pitch = 0.0
	var hy := head_yaw
	if action == "shake":
		hy += sin(act_u * TAU * 3.0) * 30.0 * act_w
	if death_t > 0.0:
		_rot("Head", Vector3(lerpf(head_pitch, -6.0, death_t), lerpf(hy, 0.0, death_t), 0.0))
	else:
		_rot("Head", Vector3(head_pitch + nod + chew + act_pitch, hy, 0.0))
	# --- legs -------------------------------------------------------------------------------
	var sit := 1.0 if pose == "sit" else 0.0
	for i in 4:
		var a: float = leg_a[i]
		if death_t > 0.0:
			a = lerpf(a, (24.0 if i < 2 else -24.0), death_t)
		elif sit > 0.0 and i >= 2:
			a = 70.0
		_rot(LEG_NAMES[i], Vector3(a, 0.0, 0.0))
	# --- tail -------------------------------------------------------------------------------
	var wag: float = b.wag
	var alert: float = b.alert
	var lift_target := -38.0 * alert * smoothstep(speeds[1] * 0.6, speeds[2] * 0.6, sp)
	if wag > 0.0:
		lift_target = minf(lift_target, -14.0 * wag)
	tail_lift = lerpf(tail_lift, lift_target, 1.0 - exp(-dt * 4.0))
	var tail_yaw := sin(t * 1.4) * 7.0 + sin(t * 31.0) * 30.0 * wag
	tail_yaw += sin(tau) * 8.0 * smoothstep(0.1, speeds[0], sp)
	if death_t > 0.0:
		_rot("Tail", Vector3(lerpf(tail_lift, 8.0, death_t), 0.0, 0.0))
	else:
		_rot("Tail", Vector3(tail_lift, tail_yaw, 0.0))
	# --- visual root: slope pitch, bob, sit, flinch, death roll ------------------------------
	var slope: float = b.slope_pitch
	var pitch := slope + body_pitch * DEG
	var off := Vector3(0.0, bob, 0.0)
	if sit > 0.0:
		pitch += 16.0 * DEG
		off.y -= shoulder * 0.18
	if action == "flinch":
		off += Vector3(0.0, 0.0, 0.06 * act_w * shoulder)
		pitch += 5.0 * DEG * act_w
	if action == "bite":
		off.z -= 0.08 * act_w * shoulder
	_apply_root(pitch, 0.0, off, death_t, float(b.death_side))


func _apply_root(pitch: float, roll: float, off: Vector3, death_t: float, side: float) -> void:
	if death_t <= 0.0:
		visual.transform = Transform3D(Basis.from_euler(Vector3(pitch, 0.0, roll)), off)
		return
	# tip over onto one side around the body centre: centre ends at lie_h above the ground
	var e := death_t * death_t * (3.0 - 2.0 * death_t)
	var a := e * PI * 0.5
	var s := signf(side) if side != 0.0 else 1.0
	var c := body_y
	var yt := lerpf(c, lie_h, e)
	var o := Vector3(s * c * sin(a), yt - c * cos(a), 0.0)
	var keep := 1.0 - e
	visual.transform = Transform3D(Basis.from_euler(Vector3(pitch * keep, 0.0, s * a)), o + off * keep)


# =================================================================================================
# birds
# =================================================================================================

func _update_bird(b: Object, dt: float) -> void:
	var death_t: float = b.death_t
	var pose: String = b.anim_pose
	var flap: float = b.flap
	var fold_target: float = b.fold
	fold_cur = move_toward(fold_cur, fold_target, dt * 4.5)
	var tuck_target := 1.0 if pose in ["fly", "glide", "takeoff"] and fold_target < 0.5 else 0.0
	if pose == "land":
		tuck_target = 0.0
	tuck_cur = move_toward(tuck_cur, tuck_target, dt * 3.0)
	var hz := flap_hz * (1.0 + 0.45 * flap * float(pose == "takeoff" or pose == "land"))
	flap_phase = fmod(flap_phase + hz * dt * (1.0 if flap > 0.02 else 0.35), 1.0)
	var amp := 52.0 * flap
	if pose == "takeoff" or pose == "land":
		amp = 64.0 * maxf(flap, 0.6)
	var dihedral := 7.0 + 3.0 * sin(t * 1.7)
	var wing := dihedral * (1.0 - flap) + amp * sin(TAU * flap_phase) + 8.0 * flap
	if death_t > 0.0:
		wing = lerpf(wing, -10.0, death_t)
	# wings: spread (rest) <-> folded pose
	for side: String in ["Wing_R", "Wing_L"]:
		var n: Node3D = parts.get(side, null)
		if n == null:
			continue
		var sgn := 1.0 if side == "Wing_R" else -1.0
		var spread_rot := Vector3(0.0, 0.0, sgn * wing) * DEG
		var fold_rot := spread_rot
		var fold_scale: Vector3 = rest_scale[side]
		if folded.has(side):
			fold_rot = (folded[side][0] as Vector3) * DEG
			fold_scale = folded[side][1]
		var f := fold_cur * (1.0 - death_t * 0.6)
		n.rotation = spread_rot.lerp(fold_rot, f)
		n.scale = (rest_scale[side] as Vector3).lerp(fold_scale, f)
	# legs tucked in flight
	_rot("Legs", flight_legs * tuck_cur)
	# head: peck dips, look around, pigeon walking bob
	var action: String = b.action
	var act_u := clampf(float(b.action_t) / maxf(float(b.action_dur), 0.01), 0.0, 1.0)
	_peck = sin(act_u * PI) if action == "peck" else move_toward(_peck, 0.0, dt * 6.0)
	var hp := -55.0 * _peck
	if pose == "fly" or pose == "glide":
		hp = 6.0
	head_pitch = lerpf(head_pitch, hp, 1.0 - exp(-dt * 14.0))
	head_yaw = lerpf(head_yaw, clampf(float(b.look_yaw), -1.3, 1.3) / DEG, 1.0 - exp(-dt * 9.0))
	_rot("Head", Vector3(head_pitch, head_yaw, 0.0))
	var head: Node3D = parts.get("Head", null)
	if head != null:
		var sp: float = absf(float(b.anim_speed))
		var walk_bob := 0.0
		if pose == "walk" and sp > 0.05:
			phase = fmod(phase + sp / 0.12 * dt, 1.0)
			walk_bob = (fmod(phase, 1.0) - 0.5) * 0.04 * length
		head.position = (rest_pos["Head"] as Vector3) + Vector3(0.0, 0.0, walk_bob)
	var tail_pitch := -10.0 if pose in ["fly", "glide"] else 0.0
	if pose == "land":
		tail_pitch = -26.0
	_rot("Tail", Vector3(tail_pitch, sin(t * 2.0) * 3.0, 0.0))
	# root: bank in flight, little hop when walking, flare pitch on landing
	var bank: float = b.bank
	var pitch: float = b.slope_pitch
	var off := Vector3.ZERO
	if pose == "walk":
		off.y = absf(sin(phase * TAU)) * 0.02 * length
	if pose == "fly" or pose == "glide" or pose == "takeoff" or pose == "land":
		off.y = -sin(TAU * flap_phase) * 0.03 * length * flap
	_apply_root(pitch, bank, off, death_t, float(b.death_side))


# =================================================================================================
# fish (shark): tail beat about Y, counter-sway of the body, pectoral fins about Z
# =================================================================================================

func _update_fish(b: Object, dt: float) -> void:
	var death_t: float = b.death_t
	var sp: float = absf(float(b.anim_speed))
	var hz := 0.45 + sp * 0.32
	phase = fmod(phase + hz * dt, 1.0)
	var amp := (16.0 + sp * 3.0) * (1.0 - death_t)
	var s := sin(TAU * phase)
	_rot("Tail", Vector3(0.0, amp * s, 0.0))
	_rot("Fin_L", Vector3(0.0, 0.0, -6.0 + sin(t * 1.3) * 7.0 * (1.0 - death_t)))
	_rot("Fin_R", Vector3(0.0, 0.0, 6.0 - sin(t * 1.3) * 7.0 * (1.0 - death_t)))
	var action: String = b.action
	var act_u := clampf(float(b.action_t) / maxf(float(b.action_dur), 0.01), 0.0, 1.0)
	var bite_pitch := 0.0
	if action == "bite":
		bite_pitch = sin(act_u * PI) * 14.0 * DEG
	var pitch: float = b.slope_pitch
	var bank: float = b.bank
	if death_t > 0.0:
		var e := death_t * death_t * (3.0 - 2.0 * death_t)
		visual.transform = Transform3D(Basis.from_euler(Vector3(pitch * (1.0 - e), 0.0, PI * e)), Vector3.ZERO)
		return
	var sway := -s * 4.0 * DEG * (1.0 - death_t)
	visual.transform = Transform3D(Basis.from_euler(Vector3(pitch + bite_pitch, sway, bank)), Vector3.ZERO)
