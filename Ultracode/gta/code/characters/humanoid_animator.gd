class_name HumanoidAnimator
extends Node
## Procedural animation driver for the shared humanoid skeleton (docs/ARCHITECTURE.md 6.3).
##
## One node per character. It is driven by PLAIN PARAMETERS only (speed, state, aim ...), so the
## player and every NPC use it in exactly the same way. Nothing here knows about Player.
##
## How it works
##   * Everything is computed in MODEL SPACE (skeleton space: +Y up, -Z forward, +X = character's
##     right) as rotation deltas over the rest pose, so the roll of the bones does not matter:
##         local_pose_rotation = rest_parent^-1 * (delta_parent^-1 * delta_bone) * rest_bone
##   * Spine chain = forward kinematics (pitch / yaw / roll per bone).
##   * Arms and legs = analytic two-bone IK towards a wrist / ankle target with a pole vector.
##     Knees and elbows therefore can never bend the wrong way, and planted feet stay planted
##     (the pelvis is lowered automatically when a planted foot would be out of reach).
##   * Three layers: base pose of the state -> upper-body weapon layer (weapon_pose, aim_weight,
##     aim_pitch) -> one-shot action layer (play_action).
##   * State changes cross-fade from a snapshot of the pose that is on the skeleton, so every
##     transition is smooth without evaluating two states.
##   * No allocations per evaluation. update_rate_hz throttles the evaluation for LOD.
##
## See docs/PLAYER.md ("Animator parameters") for the full parameter list.

signal footstep(foot: int, intensity: float)      ## foot: 0 = left, 1 = right; intensity 0..1 (walk..sprint)
signal action_finished(action_name: String)

enum {
	B_ROOT, B_HIPS, B_SPINE, B_CHEST, B_NECK, B_HEAD,
	B_SHOULDER_L, B_UPPERARM_L, B_LOWERARM_L, B_HAND_L,
	B_SHOULDER_R, B_UPPERARM_R, B_LOWERARM_R, B_HAND_R,
	B_UPPERLEG_L, B_LOWERLEG_L, B_FOOT_L,
	B_UPPERLEG_R, B_LOWERLEG_R, B_FOOT_R,
	B_COUNT
}

## Expected parent (contract index) of every contract bone; -1 = any.
const EXPECTED_PARENT: PackedInt32Array = [
	-1, 0, 1, 2, 3, 4,
	3, 6, 7, 8,
	3, 10, 11, 12,
	1, 14, 15,
	1, 17, 18,
]

const BONE_NAMES: PackedStringArray = [
	"Root", "Hips", "Spine", "Chest", "Neck", "Head",
	"Shoulder_L", "UpperArm_L", "LowerArm_L", "Hand_L",
	"Shoulder_R", "UpperArm_R", "LowerArm_R", "Hand_R",
	"UpperLeg_L", "LowerLeg_L", "Foot_L",
	"UpperLeg_R", "LowerLeg_R", "Foot_R",
]

enum {
	S_IDLE, S_LOCOMOTION, S_CROUCH, S_JUMP, S_FALL, S_LAND, S_SWIM, S_DIVE, S_TREAD,
	S_SEATED_CAR, S_SEATED_BIKE, S_AIM, S_MELEE, S_COVER_LOW, S_COVER_HIGH, S_CLIMB_LADDER,
	S_VAULT, S_ROLL, S_PARACHUTE, S_FREEFALL, S_DEAD, S_SURRENDER, S_COWER, S_TAKEDOWN, S_CARRIED
}

const STATE_IDS := {
	"idle": S_IDLE, "locomotion": S_LOCOMOTION, "crouch": S_CROUCH, "jump": S_JUMP, "fall": S_FALL,
	"land": S_LAND, "swim": S_SWIM, "dive": S_DIVE, "tread": S_TREAD, "seated_car": S_SEATED_CAR,
	"seated_bike": S_SEATED_BIKE, "aim": S_AIM, "melee": S_MELEE, "cover_low": S_COVER_LOW,
	"cover_high": S_COVER_HIGH, "climb_ladder": S_CLIMB_LADDER, "vault": S_VAULT, "roll": S_ROLL,
	"parachute": S_PARACHUTE, "freefall": S_FREEFALL, "dead": S_DEAD, "surrender": S_SURRENDER,
	"cower": S_COWER, "takedown": S_TAKEDOWN, "carried": S_CARRIED,
}

## Default cross-fade time (seconds) when ENTERING a state from another family.
const BLEND_IN := {
	S_IDLE: 0.24, S_LOCOMOTION: 0.22, S_CROUCH: 0.22, S_JUMP: 0.10, S_FALL: 0.24, S_LAND: 0.07,
	S_SWIM: 0.35, S_DIVE: 0.40, S_TREAD: 0.35, S_SEATED_CAR: 0.40, S_SEATED_BIKE: 0.40,
	S_AIM: 0.20, S_MELEE: 0.18, S_COVER_LOW: 0.25, S_COVER_HIGH: 0.25, S_CLIMB_LADDER: 0.25,
	S_VAULT: 0.12, S_ROLL: 0.10, S_PARACHUTE: 0.35, S_FREEFALL: 0.35, S_DEAD: 0.30,
	S_SURRENDER: 0.30, S_COWER: 0.25, S_TAKEDOWN: 0.15, S_CARRIED: 0.3,
}

const ACTIONS := {
	"reload": 1.5, "punch_l": 0.36, "punch_r": 0.36, "heavy": 0.70, "kick": 0.60,
	"hit_react": 0.38, "throw": 0.62, "pickup": 0.75, "enter_car": 0.55, "exit_car": 0.50,
	"fire": 0.14, "jack": 0.85, "shove": 0.50, "stomp": 0.62,
}
enum { A_NONE, A_RELOAD, A_PUNCH_L, A_PUNCH_R, A_HEAVY, A_KICK, A_HIT, A_THROW, A_PICKUP, A_ENTER, A_EXIT, A_FIRE,
	A_JACK, A_SHOVE, A_STOMP }
const ACTION_IDS := {
	"reload": A_RELOAD, "punch_l": A_PUNCH_L, "punch_r": A_PUNCH_R, "heavy": A_HEAVY, "kick": A_KICK,
	"hit_react": A_HIT, "throw": A_THROW, "pickup": A_PICKUP, "enter_car": A_ENTER,
	"exit_car": A_EXIT, "fire": A_FIRE, "jack": A_JACK, "shove": A_SHOVE, "stomp": A_STOMP,
}
## motion_style values
const MOTION_VAULT := 0         ## state "vault": one-hand side vault over a low obstacle
const MOTION_MANTLE := 1        ## state "vault": two-hand climb up onto a ledge
const MOTION_TD_KNIFE := 0      ## state "takedown": grab the head from behind, one stab
const MOTION_TD_CHOKE := 1      ## state "takedown": rear choke hold
const MOTION_TD_BLUNT := 2      ## state "takedown": grab the shoulder, blow to the back of the head
## How far behind the victim's origin the attacker stands per takedown style (m); the takedown
## state places the player there, the poses reach for the victim's neck at that distance.
const TAKEDOWN_GRAB := [0.38, 0.32, 0.62]
const SEATED_GUN_RAISE := 0.10  ## m: seated one-handed (drive-by) gun hand above the shoulder line
enum { W_NONE, W_PISTOL, W_RIFLE, W_MELEE, W_RPG, W_THROW }
const WEAPON_IDS := {"none": W_NONE, "": W_NONE, "pistol": W_PISTOL, "rifle": W_RIFLE, "melee": W_MELEE,
		"rpg": W_RPG, "throw": W_THROW}

# --- public parameters -------------------------------------------------------------------------
var skeleton: Skeleton3D = null
## Planar speed in m/s. Drives the gait (cadence, stride, arm swing, lean) and the swim stroke.
var speed: float = 0.0
## Direction of travel relative to the facing: x = right, y = forward. (0, 1) = straight ahead.
var move_dir_local: Vector2 = Vector2(0.0, 1.0)
## One of STATE_IDS. Assigning cross-fades with the default time; see set_state() for a custom time.
var state: String:
	get:
		return _state
	set(v):
		set_state(v, -1.0)
var aim_pitch: float = 0.0          ## radians, + = up (also the body pitch of "dive" / "freefall")
var aim_weight: float = 0.0         ## 0..1 upper-body aim layer
var weapon_pose: String = "none": set = _set_weapon_pose   ## none, pistol, rifle, melee, rpg, throw
var lean: float = 0.0               ## -1..1, + = lean right (turn lean on foot, bike lean)
var update_rate_hz: float = 0.0     ## 0 = every frame; e.g. 15 for distant NPCs
# extras (all optional)
var vertical_speed: float = 0.0     ## m/s, used by jump / fall / ladder
var accel_lean: float = 0.0         ## -1..1, + = accelerating forward (torso pitches into it)
var turn_rate: float = 0.0          ## rad/s; makes the feet shuffle when turning on the spot
var steer: float = 0.0              ## -1..1, + = right; turns the wheel / bars in the seated states
var look_yaw: float = 0.0           ## head look, radians, + = left
var look_pitch: float = 0.0         ## head look, radians, + = up
var sneak: float = 0.0              ## 0..1 stealth hunch on top of the ground states (a light crouch)
var flare: float = 0.0              ## 0..1 both parachute toggles pulled down (state "parachute"; steer pulls one)
var time_scale: float = 1.0         ## 0 freezes time (the pose is still evaluated)
var phase: float = 0.0              ## gait cycle 0..1 (0 = left heel strike). Writable.
var auto_process: bool = true       ## false: the owner calls advance(delta) itself
var hide_head: bool = false: set = _set_hide_head   ## first-person view: collapses the Head bone
## Seated tuning (model space; the character origin is the seat hip point).
var wheel_pos: Vector3 = Vector3(0.0, 0.33, -0.43)      ## steering wheel hub
var wheel_radius: float = 0.165
var bar_pos: Vector3 = Vector3(0.0, 0.31, -0.55)        ## handlebar centre (seated_bike)
var bar_half_width: float = 0.27
var peg_pos: Vector3 = Vector3(0.20, -0.43, 0.03)       ## right foot peg (mirrored for the left)
var pedal_pos: Vector3 = Vector3(0.115, -0.33, -0.60)   ## right ankle on the pedals (mirrored)
var bike_lean_fwd: float = 0.32     ## torso pitch on a bike, radians
## Height of the water surface above the character origin while swimming at the surface.
var swim_depth: float = 1.42
## Optional hand IK override (model space wrist targets). Weight 0 = off.
var hand_target_l: Vector3 = Vector3.ZERO
var hand_target_r: Vector3 = Vector3.ZERO
var hand_target_weight_l: float = 0.0
var hand_target_weight_r: float = 0.0
## Aim yaw relative to the body facing (radians, + = left). The weapon layer twists the torso and
## swings the gun arm by it (drive-by out of a side window). 0 on foot, where the body faces the aim.
var aim_yaw: float = 0.0
## Where the last hit came FROM in the body frame (x = right, y = front) and how hard it was; read by
## the "hit_react" action: front = rocks back, behind = stumbles forward, side = leans away.
var hit_dir: Vector2 = Vector2(0.0, 1.0)
var hit_strength: float = 1.0
## 0..1 raised block guard over the unarmed / melee aim pose (forearms up in front of the face).
var guard: float = 0.0
## Progress 0..1 of a timed full-body motion ("vault", "roll"); < 0 = derived from the state time.
var motion_t: float = -1.0
## "vault" state variant: MOTION_VAULT (one-hand side vault) or MOTION_MANTLE (climb up a ledge).
var motion_style: int = 0
## Obstacle / ledge top above the character origin (m): where vault / mantle plant the hands.
var motion_height: float = 0.0
## Cover ("cover_low" / "cover_high"): the character stands with its BACK to the surface.
## cover_side: the side it looks / leans along the wall (-1 = its left, +1 = its right).
## cover_peek: 0 = hunkered (back flat to the wall, weapon held high-ready) .. 1 = risen over low
## cover / leaned out past a corner, i.e. the plain ground + aim pose (low cover stands up).
## cover_blind: 0..1 blind-fire overlay: the gun held over low cover (behind the head) or round the
## corner of high cover on cover_side, its barrel along aim_yaw / aim_pitch (relative to the body).
var cover_side: float = 1.0
var cover_peek: float = 0.0
var cover_blind: float = 0.0
var cover_height: float = 1.0       ## top of the cover above the origin (informative)

# --- skeleton data (filled by setup) -----------------------------------------------------------
var _ok: bool = false
var _idx: PackedInt32Array = PackedInt32Array()
var _par: PackedInt32Array = PackedInt32Array()      # contract index of the real parent bone, -1
var _pre: Array[Quaternion] = []                     # rest_parent^-1
var _post: Array[Quaternion] = []                    # rest_bone
var _rest_o: PackedVector3Array = PackedVector3Array()
var _from_q: Array[Quaternion] = []
var _from_hp: Vector3 = Vector3.ZERO
var _hips_parent_inv: Transform3D = Transform3D.IDENTITY

var _hips_rest: Vector3
var _o_spine: Vector3
var _o_chest: Vector3
var _o_neck: Vector3
var _o_head: Vector3
var _o_ua_l: Vector3
var _o_ua_r: Vector3
var _o_shc: Vector3            # chest -> midpoint between the shoulder joints
var _o_ul_l: Vector3
var _o_ul_r: Vector3
var _rd_ua_l: Vector3
var _rd_ua_r: Vector3
var _rd_la_l: Vector3
var _rd_la_r: Vector3
var _rd_ul_l: Vector3
var _rd_ul_r: Vector3
var _rd_ll_l: Vector3
var _rd_ll_r: Vector3
var _apex_arm_l: Vector3
var _apex_arm_r: Vector3
var _apex_leg_l: Vector3
var _apex_leg_r: Vector3
var _l_uarm: float = 0.28
var _l_farm: float = 0.27
var _l_thigh: float = 0.42
var _l_shin: float = 0.42
var _arm_len: float = 0.55
var _leg_len: float = 0.84
var _ankle_h: float = 0.09
var _hip_x: float = 0.09
var _sh_x: float = 0.19
var _grip_inv: Quaternion = Quaternion.IDENTITY     # maps the rest right hand to "weapon forward"
var _carry_q: Quaternion = Quaternion.IDENTITY

# --- runtime -----------------------------------------------------------------------------------
var _state: String = "idle"
var _state_id: int = S_IDLE
var _weapon_id: int = W_NONE
var _time: float = 0.0
var _accum: float = 0.0
var _state_time: float = 0.0
var _land_t: float = 10.0
var _xf_t: float = 1.0
var _xf_dur: float = 0.0
var _xf_k: float = 1.0
var _speed_s: float = 0.0
var _dir_s: Vector2 = Vector2(0.0, 1.0)
var _lean_s: float = 0.0
var _accel_s: float = 0.0
var _aim_s: float = 0.0
var _pitch_s: float = 0.0
var _crouch_s: float = 0.0
var _steer_s: float = 0.0
var _flare_s: float = 0.0
var _turn_s: float = 0.0
var _carry_s: float = 0.0
var _aim_yaw_s: float = 0.0
var _guard_s: float = 0.0
var _cside_s: float = 1.0
var _cpeek_s: float = 0.0
var _cblind_s: float = 0.0
var _sneak_s: float = 0.0
var _seated: bool = false
var _w_yaw: float = 0.0
var _prev_phase: float = 0.0
var _swim_phase: float = 0.0
var _act: int = A_NONE
var _act_name: String = ""
var _act_t: float = 0.0
var _act_dur: float = 0.0
var _snap_next: bool = true
var _warned_state: bool = false

# --- pose scratch (reset on every evaluation) -----------------------------------------------------
var _hp: Vector3
var _hips_abs: bool
var _auto_hip: bool
var _h_pitch: float
var _h_yaw: float
var _h_roll: float
var _s_pitch: float
var _s_yaw: float
var _s_roll: float
var _c_pitch: float
var _c_yaw: float
var _c_roll: float
var _head_pitch: float
var _head_yaw: float
var _head_stab: float
var _al_t: Vector3
var _al_p: Vector3
var _al_abs: bool
var _al_tw: float
var _ar_t: Vector3
var _ar_p: Vector3
var _ar_abs: bool
var _ar_tw: float
var _ll_t: Vector3
var _ll_p: Vector3
var _ll_abs: bool
var _ll_plant: bool
var _fl_pitch: float
var _fl_yaw: float
var _fl_abs: float
var _lr_t: Vector3
var _lr_p: Vector3
var _lr_abs: bool
var _lr_plant: bool
var _fr_pitch: float
var _fr_yaw: float
var _fr_abs: float
# weapon layer (offsets from the shoulder centre, model axes, rotated by the aim pitch)
var _wl_t: Vector3
var _wl_p: Vector3
var _wl_w: float
var _wr_t: Vector3
var _wr_p: Vector3
var _wr_w: float
var _w_pitch: float
var _hr_q: Quaternion
var _hr_w: float
# action layer (offsets from the shoulder centre, model axes; *_abs = model space)
var _xl_t: Vector3
var _xl_p: Vector3
var _xl_w: float
var _xl_abs: bool
var _xr_t: Vector3
var _xr_p: Vector3
var _xr_w: float
var _xr_abs: bool
var _xleg_t: Vector3       # right leg action target, hips relative
var _xleg_w: float
var _upper_ok: float       # how much the weapon layer may act in the current state
# results that owners may read
var _p_head: Vector3
var _g_head: Quaternion = Quaternion.IDENTITY
var _p_hand_r: Vector3
var _p_hand_l: Vector3
var _p_chest: Vector3
# limb solver outputs
var _lq1: Quaternion
var _lq2: Quaternion
var _l_end: Vector3
var _fp_f: float
var _fp_y: float
var _fp_pitch: float
var _fp_stance: bool
var _ah_pole: Vector3
var _plant_until: float = 1.0


func _init() -> void:
	_idx.resize(B_COUNT)
	_par.resize(B_COUNT)
	_rest_o.resize(B_COUNT)
	_pre.resize(B_COUNT)
	_post.resize(B_COUNT)
	_from_q.resize(B_COUNT)
	for i in B_COUNT:
		_pre[i] = Quaternion.IDENTITY
		_post[i] = Quaternion.IDENTITY
		_from_q[i] = Quaternion.IDENTITY
	phase = randf()
	_time = randf() * 20.0


## Binds the animator to a skeleton that follows the bone contract. Returns false (and stays
## inert) when a contract bone is missing.
func setup(skel: Skeleton3D) -> bool:
	skeleton = skel
	_ok = false
	if skel == null:
		return false
	for i in B_COUNT:
		var bi := skel.find_bone(BONE_NAMES[i])
		if bi < 0:
			push_warning("HumanoidAnimator: bone '%s' missing in %s" % [BONE_NAMES[i], str(skel.get_path()) if skel.is_inside_tree() else skel.name])
			return false
		_idx[i] = bi
	for i in B_COUNT:
		var gr := skel.get_bone_global_rest(_idx[i])
		_rest_o[i] = gr.origin
		_post[i] = gr.basis.get_rotation_quaternion()
		var pb := skel.get_bone_parent(_idx[i])
		_par[i] = -1
		if pb >= 0:
			_pre[i] = skel.get_bone_global_rest(pb).basis.get_rotation_quaternion().inverse()
			for j in B_COUNT:
				if _idx[j] == pb:
					_par[i] = j
					break
		else:
			_pre[i] = Quaternion.IDENTITY
		if EXPECTED_PARENT[i] >= 0 and _par[i] != EXPECTED_PARENT[i]:
			push_warning("HumanoidAnimator: bone '%s' has an unexpected parent (wanted '%s')" % [BONE_NAMES[i], BONE_NAMES[EXPECTED_PARENT[i]]])
	var hips_parent := skel.get_bone_parent(_idx[B_HIPS])
	_hips_parent_inv = skel.get_bone_global_rest(hips_parent).affine_inverse() if hips_parent >= 0 else Transform3D.IDENTITY
	_hips_rest = _rest_o[B_HIPS]
	_o_spine = _rest_o[B_SPINE] - _rest_o[B_HIPS]
	_o_chest = _rest_o[B_CHEST] - _rest_o[B_SPINE]
	_o_neck = _rest_o[B_NECK] - _rest_o[B_CHEST]
	_o_head = _rest_o[B_HEAD] - _rest_o[B_NECK]
	_o_ua_l = _rest_o[B_UPPERARM_L] - _rest_o[B_CHEST]
	_o_ua_r = _rest_o[B_UPPERARM_R] - _rest_o[B_CHEST]
	_o_shc = (_o_ua_l + _o_ua_r) * 0.5
	_o_ul_l = _rest_o[B_UPPERLEG_L] - _rest_o[B_HIPS]
	_o_ul_r = _rest_o[B_UPPERLEG_R] - _rest_o[B_HIPS]
	_l_uarm = maxf(_rest_o[B_LOWERARM_L].distance_to(_rest_o[B_UPPERARM_L]), 0.05)
	_l_farm = maxf(_rest_o[B_HAND_L].distance_to(_rest_o[B_LOWERARM_L]), 0.05)
	_l_thigh = maxf(_rest_o[B_LOWERLEG_L].distance_to(_rest_o[B_UPPERLEG_L]), 0.05)
	_l_shin = maxf(_rest_o[B_FOOT_L].distance_to(_rest_o[B_LOWERLEG_L]), 0.05)
	_arm_len = _l_uarm + _l_farm
	_leg_len = _l_thigh + _l_shin
	_ankle_h = maxf(_rest_o[B_FOOT_L].y, 0.02)
	_hip_x = maxf(absf(_rest_o[B_UPPERLEG_L].x), 0.04)
	_sh_x = maxf(absf(_rest_o[B_UPPERARM_L].x), 0.08)
	_rd_ua_l = _dir(_rest_o[B_UPPERARM_L], _rest_o[B_LOWERARM_L], Vector3.LEFT)
	_rd_ua_r = _dir(_rest_o[B_UPPERARM_R], _rest_o[B_LOWERARM_R], Vector3.RIGHT)
	_rd_la_l = _dir(_rest_o[B_LOWERARM_L], _rest_o[B_HAND_L], Vector3.LEFT)
	_rd_la_r = _dir(_rest_o[B_LOWERARM_R], _rest_o[B_HAND_R], Vector3.RIGHT)
	_rd_ul_l = _dir(_rest_o[B_UPPERLEG_L], _rest_o[B_LOWERLEG_L], Vector3.DOWN)
	_rd_ul_r = _dir(_rest_o[B_UPPERLEG_R], _rest_o[B_LOWERLEG_R], Vector3.DOWN)
	_rd_ll_l = _dir(_rest_o[B_LOWERLEG_L], _rest_o[B_FOOT_L], Vector3.DOWN)
	_rd_ll_r = _dir(_rest_o[B_LOWERLEG_R], _rest_o[B_FOOT_R], Vector3.DOWN)
	# Elbows point backwards (+Z) and knees forwards (-Z) in the T-pose.
	_apex_arm_l = _perp(Vector3(0.0, 0.0, 1.0), _rd_ua_l)
	_apex_arm_r = _perp(Vector3(0.0, 0.0, 1.0), _rd_ua_r)
	_apex_leg_l = _perp(Vector3(0.0, 0.0, -1.0), _rd_ul_l)
	_apex_leg_r = _perp(Vector3(0.0, 0.0, -1.0), _rd_ul_r)
	# Canonical grip: a weapon (x right, y up, -z barrel) rigidly held by the T-posed right hand
	# has its barrel along the hand (+X), its top towards the thumb (-Z) and its right side
	# towards the back of the hand (+Y).  _grip_inv turns "weapon basis in model space" into the
	# model-space delta of the Hand_R bone.
	var w_rest := Basis(Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(-1.0, 0.0, 0.0))
	_grip_inv = w_rest.get_rotation_quaternion().inverse()
	_carry_q = Basis.looking_at(Vector3(-0.62, -0.30, -0.72).normalized(), Vector3.UP).get_rotation_quaternion() * _grip_inv
	_ok = true
	_snap_next = true
	return true


## Local transform for a weapon node parented to a BoneAttachment3D of Hand_R so that it sits in
## the canonical grip this animator aims with (barrel = -Z of the weapon, up = +Y).
static func get_grip_transform(skel: Skeleton3D, bone_name: String = "Hand_R") -> Transform3D:
	if skel == null:
		return Transform3D.IDENTITY
	var bi := skel.find_bone(bone_name)
	if bi < 0:
		return Transform3D.IDENTITY
	var rest := skel.get_bone_global_rest(bi)
	var side := -1.0 if bone_name.ends_with("_L") else 1.0
	var w_rest := Basis(Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(-1.0, 0.0, 0.0))
	if side < 0.0:
		w_rest = Basis(Vector3(0.0, -1.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(1.0, 0.0, 0.0))
	# grip point: in the palm, a little in front of the wrist
	var grip_model := rest.origin + Vector3(0.075 * side, -0.03, 0.0)
	return rest.affine_inverse() * Transform3D(w_rest, grip_model)


func is_ready() -> bool:
	return _ok


## Change the state with an explicit cross-fade time (seconds).
func set_state(new_state: String, blend_time: float = -1.0) -> void:
	if new_state == _state:
		return
	var id: int = STATE_IDS.get(new_state, -1)
	if id < 0:
		if not _warned_state:
			_warned_state = true
			push_warning("HumanoidAnimator: unknown state '%s'" % new_state)
		id = S_IDLE
		new_state = "idle"
		if _state == "idle":
			return
	var was_ground := _is_ground(_state_id)
	var now_ground := _is_ground(id)
	_state = new_state
	_state_id = id
	_state_time = 0.0
	if id == S_LAND:
		_land_t = 0.0
	if was_ground and now_ground and id != S_LAND and blend_time < 0.0:
		return      # continuous inside the ground family
	_begin_crossfade(blend_time if blend_time >= 0.0 else float(BLEND_IN.get(id, 0.25)))


## One-shot action on top of the current state. duration <= 0 uses the default length.
func play_action(action_name: String, duration: float = -1.0) -> void:
	var id: int = ACTION_IDS.get(action_name, A_NONE)
	if id == A_NONE:
		return
	if _act != A_NONE and _act != A_FIRE and id == A_FIRE:
		return      # recoil never interrupts a real action
	_act = id
	_act_name = action_name
	_act_t = 0.0
	_act_dur = duration if duration > 0.0 else float(ACTIONS[action_name])


func stop_action() -> void:
	_act = A_NONE
	_act_name = ""


func get_action() -> String:
	return _act_name if _act != A_NONE else ""


func is_action_playing() -> bool:
	return _act != A_NONE and _act != A_FIRE


## Cross-fade from whatever pose is on the skeleton right now (for example a pose copied from a
## ragdoll) to the animated pose over `duration` seconds.
func crossfade_from_current(duration: float) -> void:
	_snap_next = false
	_begin_crossfade(duration)


## Skip all smoothing / cross-fades on the next evaluation (teleports, respawns, test shots).
func snap() -> void:
	_snap_next = true


## Eye position in skeleton space (first-person camera).
func get_eye_position() -> Vector3:
	return _p_head + _g_head * Vector3(0.0, 0.085, -0.10)


func get_head_rotation() -> Quaternion:
	return _g_head


## Wrist positions in skeleton space after the last evaluation.
func get_hand_position(right: bool = true) -> Vector3:
	return _p_hand_r if right else _p_hand_l


func get_chest_position() -> Vector3:
	return _p_chest


func _process(delta: float) -> void:
	if auto_process:
		advance(delta)


## Advances time and writes the pose. Called from _process unless auto_process is false.
func advance(delta: float) -> void:
	if not _ok or not is_instance_valid(skeleton):
		return
	if update_rate_hz > 0.0 and not _snap_next:
		_accum += delta
		var step := 1.0 / update_rate_hz
		if _accum < step:
			return
		delta = _accum
		_accum = 0.0
	if not _snap_next and not skeleton.is_visible_in_tree():
		return
	_evaluate(minf(delta, 0.25) * time_scale)


# =================================================================================================
# evaluation
# =================================================================================================

func _evaluate(dt: float) -> void:
	_time += dt
	_state_time += dt
	_land_t += dt
	if _snap_next:
		_speed_s = speed
		_dir_s = move_dir_local if move_dir_local.length_squared() > 0.01 else Vector2(0.0, 1.0)
		_lean_s = lean
		_accel_s = accel_lean
		_aim_s = _aim_target()
		_pitch_s = aim_pitch
		_crouch_s = _crouch_target()
		_steer_s = steer
		_flare_s = clampf(flare, 0.0, 1.0)
		_turn_s = turn_rate
		_carry_s = _carry_target()
		_aim_yaw_s = aim_yaw
		_guard_s = clampf(guard, 0.0, 1.0)
		_cside_s = clampf(cover_side, -1.0, 1.0)
		_cpeek_s = clampf(cover_peek, 0.0, 1.0)
		_cblind_s = clampf(cover_blind, 0.0, 1.0)
		_sneak_s = clampf(sneak, 0.0, 1.0)
		_xf_t = 1.0
		_xf_dur = 0.0
		_land_t = 10.0
		_snap_next = false
	else:
		_speed_s = lerpf(_speed_s, speed, 1.0 - exp(-10.0 * dt))
		if move_dir_local.length_squared() > 0.01:
			_dir_s = _dir_s.lerp(move_dir_local, 1.0 - exp(-9.0 * dt))
		_lean_s = lerpf(_lean_s, clampf(lean, -1.0, 1.0), 1.0 - exp(-6.0 * dt))
		_accel_s = lerpf(_accel_s, clampf(accel_lean, -1.0, 1.0), 1.0 - exp(-5.0 * dt))
		_aim_s = lerpf(_aim_s, _aim_target(), 1.0 - exp(-11.0 * dt))
		_pitch_s = lerpf(_pitch_s, aim_pitch, 1.0 - exp(-18.0 * dt))
		_crouch_s = lerpf(_crouch_s, _crouch_target(), 1.0 - exp(-9.0 * dt))
		_steer_s = lerpf(_steer_s, clampf(steer, -1.0, 1.0), 1.0 - exp(-9.0 * dt))
		_flare_s = lerpf(_flare_s, clampf(flare, 0.0, 1.0), 1.0 - exp(-9.0 * dt))
		_turn_s = lerpf(_turn_s, turn_rate, 1.0 - exp(-8.0 * dt))
		_carry_s = lerpf(_carry_s, _carry_target(), 1.0 - exp(-8.0 * dt))
		_aim_yaw_s = lerp_angle(_aim_yaw_s, aim_yaw, 1.0 - exp(-14.0 * dt))
		_guard_s = lerpf(_guard_s, clampf(guard, 0.0, 1.0), 1.0 - exp(-12.0 * dt))
		_cside_s = lerpf(_cside_s, clampf(cover_side, -1.0, 1.0), 1.0 - exp(-6.0 * dt))
		_cpeek_s = lerpf(_cpeek_s, clampf(cover_peek, 0.0, 1.0), 1.0 - exp(-14.0 * dt))
		_cblind_s = lerpf(_cblind_s, clampf(cover_blind, 0.0, 1.0), 1.0 - exp(-16.0 * dt))
		_sneak_s = lerpf(_sneak_s, clampf(sneak, 0.0, 1.0), 1.0 - exp(-6.0 * dt))
	if _xf_t < 1.0:
		_xf_t = 1.0 if _xf_dur <= 0.0001 else minf(_xf_t + dt / _xf_dur, 1.0)
		_xf_k = _xf_t * _xf_t * (3.0 - 2.0 * _xf_t)
	else:
		_xf_k = 1.0

	_reset_pose()
	match _state_id:
		S_IDLE, S_LOCOMOTION, S_CROUCH, S_AIM, S_MELEE, S_LAND:
			_pose_ground(dt)
		S_COVER_LOW, S_COVER_HIGH:
			_pose_ground(dt)
			_pose_cover()
		S_JUMP, S_FALL:
			_pose_air()
		S_SWIM:
			_pose_swim(dt)
		S_TREAD:
			_pose_tread()
		S_DIVE:
			_pose_dive(dt)
		S_SEATED_CAR:
			_pose_seated_car()
		S_SEATED_BIKE:
			_pose_seated_bike()
		S_DEAD, S_CARRIED:
			_pose_dead()
		S_SURRENDER:
			_pose_ground(dt)
			_pose_surrender()
		S_COWER:
			_pose_ground(dt)
			_pose_cower()
		S_CLIMB_LADDER:
			_pose_ladder(dt)
		S_VAULT:
			_pose_vault()
		S_ROLL:
			_pose_roll()
		S_PARACHUTE:
			_pose_parachute()
		S_FREEFALL:
			_pose_freefall()
		S_TAKEDOWN:
			_pose_ground(dt)
			_pose_takedown()
		_:
			_pose_ground(dt)
	_layer_weapon()
	if _state_id == S_COVER_LOW or _state_id == S_COVER_HIGH:
		_layer_cover()
	if _act != A_NONE:
		_layer_action(dt)
	_solve()


func _aim_target() -> float:
	if _state_id == S_AIM or _state_id == S_MELEE:
		return maxf(aim_weight, 1.0)
	return clampf(aim_weight, 0.0, 1.0)


func _crouch_target() -> float:
	if _state_id == S_CROUCH:
		return 1.0
	if _state_id == S_COVER_LOW:
		return 1.0 - clampf(cover_peek, 0.0, 1.0)
	if _state_id == S_TAKEDOWN:
		return 0.06
	return clampf(sneak, 0.0, 1.0) * 0.46


func _carry_target() -> float:
	return 1.0 if (_weapon_id == W_RIFLE or _weapon_id == W_RPG) else 0.0


func _is_ground(id: int) -> bool:
	return id == S_IDLE or id == S_LOCOMOTION or id == S_CROUCH or id == S_AIM or id == S_MELEE \
			or id == S_LAND or id == S_COVER_LOW or id == S_COVER_HIGH


func _reset_pose() -> void:
	_hp = Vector3.ZERO
	_hips_abs = false
	_auto_hip = false
	_h_pitch = 0.0
	_h_yaw = 0.0
	_h_roll = 0.0
	_s_pitch = 0.0
	_s_yaw = 0.0
	_s_roll = 0.0
	_c_pitch = 0.0
	_c_yaw = 0.0
	_c_roll = 0.0
	_head_pitch = -look_pitch
	_head_yaw = look_yaw
	_head_stab = 0.75
	_al_t = Vector3(-0.05, -_arm_len * 0.97, 0.0)
	_al_p = Vector3(-0.3, -0.1, 1.0)
	_al_abs = false
	_al_tw = 0.0
	_ar_t = Vector3(0.05, -_arm_len * 0.97, 0.0)
	_ar_p = Vector3(0.3, -0.1, 1.0)
	_ar_abs = false
	_ar_tw = 0.0
	_ll_t = Vector3(0.0, -_leg_len * 0.98, 0.0)
	_ll_p = Vector3(-0.08, 0.0, -1.0)
	_ll_abs = false
	_ll_plant = false
	_fl_pitch = 0.0
	_fl_yaw = 0.0
	_fl_abs = 0.0
	_lr_t = Vector3(0.0, -_leg_len * 0.98, 0.0)
	_lr_p = Vector3(0.08, 0.0, -1.0)
	_lr_abs = false
	_lr_plant = false
	_fr_pitch = 0.0
	_fr_yaw = 0.0
	_fr_abs = 0.0
	_wl_w = 0.0
	_wr_w = 0.0
	_w_pitch = 0.0
	_w_yaw = 0.0
	_seated = false
	_hr_w = 0.0
	_xl_w = 0.0
	_xr_w = 0.0
	_xl_abs = false
	_xr_abs = false
	_xleg_w = 0.0
	_upper_ok = 0.0


# --- ground family: idle / walk / run / sprint / crouch / strafe / land ----------------------------

func _pose_ground(dt: float) -> void:
	var L := _leg_len
	var v := _speed_s
	var cr := _crouch_s
	var gw := clampf(v / 0.5, 0.0, 1.0)
	var run := smoothstep(2.0, 3.6, v)
	var spr := smoothstep(5.0, 6.8, v)
	var turning := clampf(absf(_turn_s) / 2.5, 0.0, 1.0) * (1.0 - gw)
	var dx := _dir_s.x
	var dy := _dir_s.y
	var dl := sqrt(dx * dx + dy * dy)
	if dl > 0.001:
		dx /= dl
		dy /= dl
	else:
		dx = 0.0
		dy = 1.0
	var fwdness := maxf(dy, 0.0)                    # 1 forward, 0 sideways / backwards
	var side_scale := lerpf(0.62, 1.0, fwdness)
	var steady := 1.0 - 0.7 * _aim_s                # aiming calms the body down

	# cadence (cycles per second; one cycle = two steps)
	var freq := lerpf(0.9, 1.35, clampf(v / 1.9, 0.0, 1.0))
	freq = lerpf(freq, 1.55, run)
	freq = lerpf(freq, 2.1, spr)
	freq *= 1.0 + 0.25 * cr + 0.25 * (1.0 - fwdness) * gw
	var adv := maxf(gw, turning * 0.8)
	_prev_phase = phase
	phase = fposmod(phase + freq * dt * adv, 1.0)
	if adv > 0.3 and dt > 0.0:
		if phase < _prev_phase:
			footstep.emit(0, 0.35 + 0.3 * run + 0.35 * spr)
		elif _prev_phase < 0.5 and phase >= 0.5:
			footstep.emit(1, 0.35 + 0.3 * run + 0.35 * spr)

	var duty := lerpf(lerpf(0.62, 0.31, run), 0.24, spr)
	var n_f := lerpf(0.34, 0.32, run)
	var n_r := lerpf(lerpf(0.59, 0.62, run), 0.64, spr)
	var cr_amp := lerpf(1.0, 0.95, cr)
	# The stride follows the ground speed so that planted feet do not skate: a foot has to travel
	# v * duty / freq in the model while it stands on the ground (minus the roll over the toes).
	var amp := gw * side_scale * cr_amp
	var need := v * duty / freq - 0.05
	amp *= clampf(need / maxf(L * (n_f + n_r) * side_scale * cr_amp, 0.01), 0.45, 1.12)
	var a_f := L * n_f * amp
	var a_r := L * n_r * amp
	var lift := L * lerpf(lerpf(0.10, 0.30, run), 0.40, spr) * maxf(gw, turning * 0.45)
	var rise := L * lerpf(0.13, 0.17, run) * amp
	_plant_until = lerpf(0.85, 0.8, run)            # push-off: the foot peels off the ground at the end
	var toe_dn := lerpf(0.85, 1.0, run) * amp
	var stand := 1.0 - gw
	var stance := _aim_s * stand                    # standing with a weapon up: feet apart, knees soft
	var width := lerpf(lerpf(_hip_x * 1.25, _hip_x * 1.05, gw), _hip_x * 0.55, run) + 0.02 * cr + 0.04 * stance
	width += 0.11 * absf(dx) * gw                   # side-steps: feet apart so the legs never cross
	var stagger := (0.09 * stance + 0.11 * cr) * stand   # left foot forward, right foot back
	var zb := 0.02 * L * run        # runners land with the foot a little further back
	var toe_out := lerpf(0.16, 0.05, gw)

	# left leg (phase), right leg (phase + 0.5)
	_foot_path(phase, duty, a_f, a_r, lift, rise, toe_dn, gw)
	_ll_t = Vector3(-width + dx * _fp_f, _ankle_h + _fp_y, -dy * _fp_f + zb - stagger)
	_ll_abs = true
	_ll_plant = _fp_stance
	_fl_pitch = _fp_pitch
	_fl_yaw = toe_out
	_fl_abs = 1.0
	_foot_path(fposmod(phase + 0.5, 1.0), duty, a_f, a_r, lift, rise, toe_dn, gw)
	_lr_t = Vector3(width + dx * _fp_f, _ankle_h + _fp_y, -dy * _fp_f + zb + stagger)
	_lr_abs = true
	_lr_plant = _fp_stance
	_fr_pitch = _fp_pitch
	_fr_yaw = -toe_out
	_fr_abs = 1.0
	_ll_p = Vector3(-0.10 - 0.25 * cr, 0.0, -1.0)
	_lr_p = Vector3(0.10 + 0.25 * cr, 0.0, -1.0)

	# pelvis
	var c2 := cos(TAU * phase)
	var s2 := sin(TAU * phase)
	var breath := sin(_time * 1.9)
	var bob_phase := lerpf(0.0, 0.18, run)
	var bob := -cos(2.0 * TAU * (phase - bob_phase)) * lerpf(0.016, 0.034, run) * L * gw
	var land := 0.0
	if _land_t < 0.6:
		var lt := _land_t / 0.6
		land = (1.0 - lt) * (1.0 - lt) * smoothstep(0.0, 0.12, lt + 0.06)
	_auto_hip = true
	_hp = Vector3(
			-s2 * lerpf(0.022, 0.008, run) * gw * steady + sin(_time * 0.55) * 0.008 * (1.0 - gw),
			-L * (0.016 + 0.045 * run + 0.42 * cr + 0.24 * land + 0.03 * stance) + bob + breath * 0.003 * (1.0 - gw),
			0.05 * cr + 0.015 * run)
	var fwd_lean := (0.035 * gw + 0.11 * run + 0.10 * spr) * (0.4 + 0.6 * fwdness) + 0.30 * cr + 0.04 * stance \
			+ 0.10 * _accel_s * gw + 0.16 * land
	_h_pitch = fwd_lean * 0.75 * dy + 0.05 * (1.0 - absf(dy)) * gw
	_h_roll = _lean_s * 0.15 + dx * fwd_lean * 0.5 - s2 * 0.03 * gw * steady
	_h_yaw = -c2 * lerpf(0.08, 0.13, run) * gw * steady * fwdness
	_s_pitch = fwd_lean * 0.2 + 0.07 * cr
	_s_roll = _lean_s * 0.05
	_c_pitch = fwd_lean * 0.25 + breath * 0.012 * (1.0 - 0.6 * gw) + 0.06 * cr
	_c_yaw = c2 * lerpf(0.13, 0.26, run) * gw * steady * fwdness
	_c_roll = s2 * 0.03 * gw * steady
	_head_stab = 0.8
	_head_pitch += 0.03 * run

	# arms: swing against the legs
	var sw := lerpf(lerpf(0.42, 0.56, run), 0.82, spr) * gw * (0.35 + 0.65 * fwdness) * lerpf(1.0, 0.5, cr)
	var bend := lerpf(lerpf(0.26, 1.42, run), 1.58, spr) * maxf(gw, 0.0) + 0.24 * (1.0 - gw) + 0.5 * cr
	var bias := lerpf(0.04, -0.05, run) + 0.25 * cr
	var c_arm := cos(TAU * (phase - 0.04))
	var th_l := bias - sw * c_arm
	var th_r := bias + sw * c_arm
	var inward := lerpf(0.05, 0.30, run)
	var br := breath * 0.006
	# the elbow closes a little on the forward swing and opens on the back swing
	_al_t = _arm_hang(-1.0, th_l, 0.13 + 0.05 * run, bend + (0.25 * maxf(th_l, 0.0) - 0.45 * maxf(-th_l, 0.0)) * gw, inward) + Vector3(0.0, br, 0.0)
	_al_p = _ah_pole
	_ar_t = _arm_hang(1.0, th_r, 0.13 + 0.05 * run, bend + (0.25 * maxf(th_r, 0.0) - 0.45 * maxf(-th_r, 0.0)) * gw, inward) + Vector3(0.0, br, 0.0)
	_ar_p = _ah_pole
	_upper_ok = 1.0
	if _sneak_s > 0.001 and _state_id != S_COVER_LOW and _state_id != S_COVER_HIGH:
		# sneaking: torso bent forward, head up to watch ahead, hands carried in front at the hips,
		# short careful arm swing
		var sk := _sneak_s * (1.0 - _aim_s)
		_s_pitch += 0.10 * sk
		_c_pitch += 0.10 * sk
		_h_pitch += 0.06 * sk
		_head_pitch -= 0.22 * sk
		var sw2 := sin(TAU * (phase - 0.04)) * 0.04 * gw
		_al_t = _al_t.lerp(Vector3(-0.07, -_arm_len * 0.56 - sw2, -0.24 + sw2), 0.75 * sk)
		_ar_t = _ar_t.lerp(Vector3(0.07, -_arm_len * 0.56 + sw2, -0.24 - sw2), 0.75 * sk)
		_al_p = _al_p.lerp(Vector3(-0.8, -0.6, 0.6), sk)
		_ar_p = _ar_p.lerp(Vector3(0.8, -0.6, 0.6), sk)


func _foot_path(p: float, duty: float, a_f: float, a_r: float, lift: float, rise: float, toe_dn: float, gw: float) -> void:
	if p < duty:
		var u := p / duty
		var hr := smoothstep(0.5, 1.0, u)
		_fp_f = lerpf(a_f, -a_r, u)
		_fp_y = rise * hr * hr
		_fp_pitch = toe_dn * hr * hr - 0.24 * gw * (1.0 - smoothstep(0.0, 0.2, u))
		_fp_stance = u < _plant_until
	else:
		var s := (p - duty) / (1.0 - duty)
		var e := s * s * (3.0 - 2.0 * s)
		_fp_f = lerpf(-a_r, a_f, e)
		_fp_y = rise * (1.0 - s) * (1.0 - s) + lift * sin(PI * pow(s, 0.75))
		_fp_pitch = toe_dn * (1.0 - smoothstep(0.0, 0.55, s)) - 0.24 * gw * smoothstep(0.7, 1.0, s)
		_fp_stance = false


## Hand offset from the shoulder joint (chest frame) for a hanging arm.
## swing: + forward, abduct: + away from the body, bend: elbow flexion, inward: forearm to centre.
## Also writes _ah_pole: the direction of the upper arm, so that the IK puts the elbow exactly
## where this forward-kinematic description has it (elbows point down / back, never sideways).
func _arm_hang(side: float, swing: float, abduct: float, bend: float, inward: float) -> Vector3:
	var ca := cos(abduct)
	var sa := sin(abduct)
	var t := swing + bend
	var ci := cos(inward)
	_ah_pole = Vector3(side * sa + side * 0.07, -ca * cos(swing) - 0.04, -ca * sin(swing) + 0.15)
	return Vector3(side * sa * _l_uarm + side * (sa - sin(inward)) * _l_farm,
			-ca * cos(swing) * _l_uarm - cos(t) * ci * _l_farm,
			-ca * sin(swing) * _l_uarm - sin(t) * ci * _l_farm)


# --- air ---------------------------------------------------------------------------------------------

func _pose_air() -> void:
	var L := _leg_len
	var A := _arm_len
	var up := clampf(vertical_speed / 5.0, -1.0, 1.0)      # +1 rising fast, -1 falling fast
	var k := 0.5 - 0.5 * up                                 # 0 rising .. 1 falling
	if _state_id == S_FALL:
		k = maxf(k, 0.55)
	var fl := sin(_time * 7.5) * k
	var fl2 := cos(_time * 6.1) * k
	_hp = Vector3(0.0, -0.02 * L, 0.0)
	_h_pitch = lerpf(0.16, 0.04, k)
	_s_pitch = 0.05
	_c_pitch = lerpf(0.06, -0.04, k)
	_head_stab = 0.7
	# legs relative to the pelvis: leading knee up while rising, both legs loose while falling
	_ll_t = Vector3(-0.02, -L * lerpf(0.62, 0.86, k), -L * lerpf(0.34, 0.14, k) + fl * 0.05)
	_lr_t = Vector3(0.02, -L * lerpf(0.90, 0.80, k), L * lerpf(0.26, 0.10, k) - fl * 0.05)
	_ll_p = Vector3(-0.12, 0.0, -1.0)
	_lr_p = Vector3(0.12, 0.0, -1.0)
	_fl_pitch = 0.35
	_fr_pitch = 0.45
	# arms: one forward, one back while rising; both out and up while falling
	_al_t = Vector3(-A * lerpf(0.30, 0.72, k), A * lerpf(-0.55, 0.10, k) + fl2 * 0.05, -A * lerpf(-0.25, 0.20, k) + fl * 0.04)
	_ar_t = Vector3(A * lerpf(0.30, 0.72, k), A * lerpf(-0.25, 0.14, k) - fl2 * 0.05, -A * lerpf(0.55, 0.20, k) - fl * 0.04)
	_al_p = Vector3(-0.5, -0.6, 0.8)
	_ar_p = Vector3(0.5, -0.6, 0.8)
	_upper_ok = 1.0


# --- water -------------------------------------------------------------------------------------------

func _pose_tread() -> void:
	var L := _leg_len
	var A := _arm_len
	var t := _time * 3.1
	_hp = Vector3(0.0, sin(_time * 2.0) * 0.02, 0.02)
	_h_pitch = 0.10
	_c_pitch = 0.04
	_head_stab = 0.8
	_al_t = Vector3(-A * 0.62 + cos(t) * 0.07, -A * 0.22, -A * 0.30 + sin(t) * 0.10)
	_ar_t = Vector3(A * 0.62 - cos(t + 0.6) * 0.07, -A * 0.22, -A * 0.30 + sin(t + 0.6) * 0.10)
	_al_p = Vector3(-0.6, -0.7, 0.6)
	_ar_p = Vector3(0.6, -0.7, 0.6)
	var k := sin(_time * 3.6)
	_ll_t = Vector3(-_hip_x * 0.5, -L * 0.84, -L * 0.16 * k - 0.04)
	_lr_t = Vector3(_hip_x * 0.5, -L * 0.84, L * 0.16 * k - 0.04)
	_fl_pitch = 0.5
	_fr_pitch = 0.5


func _pose_swim(dt: float) -> void:
	var L := _leg_len
	var A := _arm_len
	var rate := lerpf(0.55, 0.95, clampf(_speed_s / 3.3, 0.0, 1.0))
	_swim_phase = fposmod(_swim_phase + rate * dt, 1.0)
	var roll := sin(TAU * _swim_phase)
	_hips_abs = true
	_hp = Vector3(0.0, swim_depth - 0.13 + sin(TAU * _swim_phase * 2.0) * 0.012, 0.30)
	_h_pitch = 1.34
	_h_roll = roll * 0.16
	_s_pitch = 0.04
	_c_pitch = -0.10
	_c_roll = roll * 0.14
	_head_stab = 0.62
	_head_pitch = -0.15
	# front crawl: each hand runs an ellipse in the chest frame (y = towards the head)
	var a_l := TAU * _swim_phase
	var a_r := a_l + PI
	_al_t = Vector3(-0.07 - 0.12 * absf(sin(a_l)), A * 0.93 * cos(a_l), -A * 0.50 * sin(a_l) - 0.03)
	_ar_t = Vector3(0.07 + 0.12 * absf(sin(a_r)), A * 0.93 * cos(a_r), -A * 0.50 * sin(a_r) - 0.03)
	_al_p = Vector3(-1.0, -0.2, 0.5)
	_ar_p = Vector3(1.0, -0.2, 0.5)
	# flutter kick
	var kick := sin(TAU * _swim_phase * 3.0)
	_ll_t = Vector3(-0.01, -L * 0.965, L * 0.13 * kick - 0.02)
	_lr_t = Vector3(0.01, -L * 0.965, -L * 0.13 * kick - 0.02)
	_fl_pitch = 0.9
	_fr_pitch = 0.9


func _pose_dive(dt: float) -> void:
	var L := _leg_len
	var A := _arm_len
	var rate := lerpf(0.35, 0.62, clampf(_speed_s / 2.4, 0.0, 1.0))
	_swim_phase = fposmod(_swim_phase + rate * dt, 1.0)
	var a := TAU * _swim_phase
	var ext := 0.5 + 0.5 * cos(a)                     # 1 = glide (arms extended)
	var sweep := maxf(sin(a), 0.0)                    # pull: hands sweep out
	_hips_abs = true
	_hp = Vector3(0.0, _hips_rest.y - 0.04, 0.16)
	_h_pitch = clampf(1.42 - _pitch_s, 0.25, 2.6)
	_c_pitch = -0.08
	_head_stab = 0.0
	_head_pitch = -0.42            # relative to the chest when stab = 0: look along the body
	_al_t = Vector3(-0.07 - A * 0.62 * sweep, lerpf(A * 0.18, A * 0.95, ext), -0.05 - A * 0.25 * (1.0 - ext))
	_ar_t = Vector3(0.07 + A * 0.62 * sweep, lerpf(A * 0.18, A * 0.95, ext), -0.05 - A * 0.25 * (1.0 - ext))
	_al_p = Vector3(-1.0, -0.5, -0.2)
	_ar_p = Vector3(1.0, -0.5, -0.2)
	# frog kick, half a cycle behind the arms
	var lk := 0.5 + 0.5 * cos(a + 2.3)                # 1 = legs straight
	var spread := maxf(sin(a + 2.3), 0.0)
	_ll_t = Vector3(-0.02 - 0.24 * spread - 0.10 * (1.0 - lk), -L * lerpf(0.56, 0.975, lk), -0.05 * (1.0 - lk))
	_lr_t = Vector3(0.02 + 0.24 * spread + 0.10 * (1.0 - lk), -L * lerpf(0.56, 0.975, lk), -0.05 * (1.0 - lk))
	_ll_p = Vector3(-0.9, 0.0, -0.6)
	_lr_p = Vector3(0.9, 0.0, -0.6)
	_fl_pitch = 0.8
	_fr_pitch = 0.8


# --- seated ------------------------------------------------------------------------------------------

func _pose_seated_car() -> void:
	_hips_abs = true
	_hp = Vector3(0.0, 0.05, 0.02)
	_h_pitch = -0.26
	_s_pitch = 0.04
	_c_pitch = 0.14
	_c_roll = -_steer_s * 0.05
	_head_stab = 0.85
	_head_yaw += -_steer_s * 0.18
	_ll_t = Vector3(-pedal_pos.x, pedal_pos.y, pedal_pos.z + 0.05)
	_lr_t = Vector3(pedal_pos.x, pedal_pos.y, pedal_pos.z)
	_ll_abs = true
	_lr_abs = true
	_ll_p = Vector3(-0.30, 1.0, -0.5)
	_lr_p = Vector3(0.30, 1.0, -0.5)
	_fl_abs = 1.0
	_fr_abs = 1.0
	_fl_pitch = -0.45
	_fr_pitch = -0.45
	# hands at 9 and 3 on a wheel that is tilted back by ~22 degrees
	var a := _steer_s * 1.0
	var ca := cos(a)
	var sa := sin(a)
	var up := Vector3(0.0, 0.927, -0.375)
	var r := wheel_radius
	var back := Vector3(0.0, -0.02, 0.055)       # wrist sits behind the rim
	_al_t = wheel_pos + Vector3(-r * ca, 0.0, 0.0) + up * (r * sa) + back
	_ar_t = wheel_pos + Vector3(r * ca, 0.0, 0.0) - up * (r * sa) + back
	_al_abs = true
	_ar_abs = true
	_al_p = Vector3(-0.7, -1.0, 0.35)
	_ar_p = Vector3(0.7, -1.0, 0.35)
	_seated_aim_ok()


## Seated states: the weapon layer only runs while aiming (drive-by), one-handed, the other hand
## stays on the wheel / bar (see _layer_weapon).
func _seated_aim_ok() -> void:
	_seated = true
	_upper_ok = 1.0 if (aim_weight > 0.001 or _aim_s > 0.01) else 0.0


func _pose_seated_bike() -> void:
	_hips_abs = true
	_hp = Vector3(0.0, 0.07, 0.03)
	_h_pitch = bike_lean_fwd
	_h_roll = _lean_s * 0.12
	_s_pitch = 0.10
	_c_pitch = 0.10
	_head_stab = 0.9
	_ll_t = Vector3(-peg_pos.x, peg_pos.y, peg_pos.z)
	_lr_t = Vector3(peg_pos.x, peg_pos.y, peg_pos.z)
	_ll_abs = true
	_lr_abs = true
	_ll_p = Vector3(-0.45, 0.35, -1.0)
	_lr_p = Vector3(0.45, 0.35, -1.0)
	_fl_abs = 1.0
	_fr_abs = 1.0
	_fl_pitch = 0.15
	_fr_pitch = 0.15
	var a := -_steer_s * 0.38
	var ca := cos(a)
	var sa := sin(a)
	var w := bar_half_width
	var back := Vector3(0.0, 0.015, 0.05)
	_al_t = bar_pos + Vector3(-w * ca, 0.0, w * sa) + back
	_ar_t = bar_pos + Vector3(w * ca, 0.0, -w * sa) + back
	_al_abs = true
	_ar_abs = true
	_al_p = Vector3(-0.8, -0.8, 0.4)
	_ar_p = Vector3(0.8, -0.8, 0.4)
	_seated_aim_ok()


# --- lying / special ----------------------------------------------------------------------------------

func _pose_dead() -> void:
	var L := _leg_len
	var A := _arm_len
	_hips_abs = true
	_hp = Vector3(0.0, 0.115, 0.0)
	_h_pitch = -1.50
	_h_yaw = 0.0
	_s_pitch = -0.03
	_c_pitch = -0.02
	_c_roll = 0.05
	_head_stab = 0.0
	_head_yaw = 0.45
	_head_pitch = 0.0
	# chest frame: +z = the back of the chest = towards the ground
	_al_t = Vector3(-A * 0.78, -A * 0.42, 0.045)
	_ar_t = Vector3(A * 0.55, -A * 0.74, 0.04)
	_al_p = Vector3(-0.3, -1.0, 0.25)
	_ar_p = Vector3(1.0, -0.2, 0.25)
	_ll_t = Vector3(-_hip_x * 0.9, -L * 0.97, 0.03)
	_lr_t = Vector3(_hip_x * 0.7, -L * 0.86, -L * 0.07)
	_ll_p = Vector3(-0.6, 0.0, -1.0)
	_lr_p = Vector3(0.7, 0.0, -1.0)
	_fl_pitch = 0.5
	_fr_pitch = 0.45


func _pose_surrender() -> void:
	var A := _arm_len
	var tr := sin(_time * 21.0) * 0.004
	_al_t = Vector3(-A * 0.42, A * 0.40 + tr, -0.07)
	_ar_t = Vector3(A * 0.42, A * 0.40 - tr, -0.07)
	_al_p = Vector3(-1.0, -0.8, 0.1)
	_ar_p = Vector3(1.0, -0.8, 0.1)
	_c_pitch -= 0.04
	_upper_ok = 0.0


func _pose_cower() -> void:
	var A := _arm_len
	var tr := sin(_time * 24.0) * 0.006
	_hp.y -= _leg_len * 0.34
	_hp.z += 0.04
	_h_pitch += 0.38
	_s_pitch += 0.20
	_c_pitch += 0.22
	_head_stab = 0.15
	_head_pitch += 0.35
	_al_t = Vector3(0.02, A * 0.44 + tr, -A * 0.26)
	_ar_t = Vector3(-0.02, A * 0.44 - tr, -A * 0.26)
	_al_p = Vector3(-1.0, -0.5, -0.3)
	_ar_p = Vector3(1.0, -0.5, -0.3)
	_ll_p = Vector3(-0.4, 0.0, -1.0)
	_lr_p = Vector3(0.4, 0.0, -1.0)
	_upper_ok = 0.0


## Stealth takedown from behind (motion_t = progress, motion_style = MOTION_TD_*). The victim's
## neck is TAKEDOWN_GRAB[style] in front of the origin at about 1.45 m; hands are placed in model
## space on top of the standing ground pose (legs planted, knees a little bent by _crouch_target).
func _pose_takedown() -> void:
	var u := motion_t if motion_t >= 0.0 else clampf(_state_time / 1.0, 0.0, 1.0)
	var st := clampi(motion_style, 0, 2)
	var g: float = TAKEDOWN_GRAB[st]
	var neck := Vector3(0.0, 1.45, -g)
	var rest_l := Vector3(-0.22, 0.98, -0.12)
	var rest_r := Vector3(0.22, 0.98, -0.12)
	var tl := rest_l
	var tr := rest_r
	var pl := Vector3(-0.8, -0.6, 0.3)
	var pr := Vector3(0.8, -0.6, 0.3)
	var release := smoothstep(0.80, 1.0, u)
	match st:
		MOTION_TD_KNIFE:
			# left hand over the mouth, the knife hand cocks back and drives into the neck
			var reach := smoothstep(0.0, 0.25, u)
			var cock := smoothstep(0.10, 0.34, u) * (1.0 - smoothstep(0.36, 0.48, u))
			var stab := smoothstep(0.38, 0.52, u)
			tl = rest_l.lerp(neck + Vector3(-0.02, 0.08, -0.10), reach)
			tr = rest_r.lerp(Vector3(0.30, 1.22, 0.02), cock)
			tr = tr.lerp(neck + Vector3(0.10, -0.04, 0.04), stab)
			pl = Vector3(-1.0, -0.4, 0.2)
			pr = Vector3(1.0, -0.6, 0.4)
			_h_pitch += 0.10 * reach + 0.08 * stab
			_c_pitch += 0.10 * reach
			_c_yaw += -0.14 * cock + 0.20 * stab
		MOTION_TD_CHOKE:
			# right forearm round the throat, the left hand locks it; lean back and squeeze
			var grab := smoothstep(0.0, 0.18, u)
			var hold := smoothstep(0.15, 0.30, u) * (1.0 - release)
			var squeeze := sin(u * 38.0) * 0.012 * hold
			tr = rest_r.lerp(neck + Vector3(-0.13, -0.04 + squeeze, -0.12), grab)
			tl = rest_l.lerp(neck + Vector3(-0.17, 0.07, 0.06 + squeeze), grab)
			pr = Vector3(1.0, -0.6, 0.1)
			pl = Vector3(-1.0, -0.6, 0.2)
			# pressed against the victim's back, chin over its shoulder, the squeeze arches the back
			_h_pitch += 0.08 * grab - 0.03 * hold
			_s_pitch += 0.02 * hold
			_c_pitch += 0.06 * grab - 0.05 * hold
			_hp.y -= 0.02 * hold
			_hp.z -= 0.04 * grab
			_head_yaw -= 0.25 * hold
			_head_pitch += 0.10 * hold
		_:
			# grab the shoulder, overhead blow to the back of the head (bat / crowbar / gun butt)
			var grab2 := smoothstep(0.0, 0.2, u)
			var wind := smoothstep(0.05, 0.36, u) * (1.0 - smoothstep(0.38, 0.52, u))
			var hit := smoothstep(0.40, 0.55, u)
			tl = rest_l.lerp(Vector3(-0.12, 1.40, -g + 0.10), grab2)
			tr = rest_r.lerp(Vector3(0.24, 1.88, 0.06), wind)
			tr = tr.lerp(neck + Vector3(0.06, 0.10, 0.10), hit)
			pl = Vector3(-1.0, -0.6, 0.2)
			pr = Vector3(1.0, -0.2, 0.5)
			_c_yaw += -0.25 * wind + 0.30 * hit
			_c_pitch += -0.08 * wind + 0.18 * hit
			_h_pitch += 0.10 * hit
	tl = tl.lerp(rest_l, release)
	tr = tr.lerp(rest_r, release)
	_al_t = tl
	_ar_t = tr
	_al_abs = true
	_ar_abs = true
	_al_p = pl
	_ar_p = pr
	_head_stab = 0.5
	_upper_ok = 0.0


## Cover: the surface is BEHIND the character (+Z). Hips and back against it, torso upright, head and
## shoulders turned towards cover_side; cover_peek blends back to the plain ground (/ aim) pose.
func _pose_cover() -> void:
	var k := 1.0 - _cpeek_s
	if k <= 0.001:
		return
	var A := _arm_len
	var sd := clampf(_cside_s, -1.0, 1.0)
	var low := _state_id == S_COVER_LOW
	_hp.z += (0.05 if low else 0.035) * k
	_h_pitch -= (0.17 * _crouch_s if low else 0.03) * k
	_s_pitch -= 0.05 * k
	_c_pitch -= (0.10 if low else 0.07) * k
	_s_yaw += -sd * 0.10 * k
	_c_yaw += -sd * 0.26 * k
	_head_yaw += -sd * 0.72 * k
	_head_stab = lerpf(_head_stab, 0.6, k)
	if low:
		# knees closer together, the leg on the look side a little out to the side
		_ll_t.x = lerpf(_ll_t.x, _ll_t.x - 0.03 + minf(sd, 0.0) * 0.05, k)
		_lr_t.x = lerpf(_lr_t.x, _lr_t.x + 0.03 + maxf(sd, 0.0) * 0.05, k)
	if _weapon_id == W_NONE or _weapon_id == W_MELEE:
		# empty hands / a melee weapon: forearms in front of the belly, close to the body
		_al_t = _al_t.lerp(Vector3(-0.05, -A * 0.66, -0.17), k)
		_ar_t = _ar_t.lerp(Vector3(0.06, -A * 0.64, -0.18), k)


## Cover weapon layer (after _layer_weapon): the gun held high-ready while hunkered, and the blind-fire
## arm (over low cover behind the head / round the corner of high cover on cover_side) with the barrel
## along aim_yaw / aim_pitch. Targets are offsets from the shoulder centre in model axes.
func _layer_cover() -> void:
	_w_yaw = 0.0                        # cover never twists the aim layer: peeking turns the body
	var k := 1.0 - _cpeek_s
	var b := _cblind_s
	var armed := _weapon_id != W_NONE and _weapon_id != W_MELEE
	if not armed or (k <= 0.001 and b <= 0.001):
		return
	var sd := clampf(_cside_s, -1.0, 1.0)
	var low := _state_id == S_COVER_LOW
	# high-ready: muzzle up in front of the chest
	var tr := Vector3(0.10, 0.03, -0.22)
	var tl := Vector3(0.035, -0.02, -0.24)
	var pr := Vector3(0.7, -1.0, 0.2)
	var pl := Vector3(-0.7, -1.0, 0.2)
	var q := Quaternion(Vector3.RIGHT, 1.25) * _grip_inv
	var lw := 1.0
	if _weapon_id == W_RIFLE or _weapon_id == W_RPG:
		tr = Vector3(0.14, -0.21, -0.17)
		tl = Vector3(-0.07, 0.05, -0.30)
		q = Quaternion(Vector3.UP, 0.5) * Quaternion(Vector3.RIGHT, 1.05) * _grip_inv
	elif _weapon_id == W_THROW:
		tl = Vector3(-0.12, -0.10, -0.22)
		lw = 0.5
	if b > 0.001:
		var qb := Quaternion(Vector3.UP, _aim_yaw_s) * Quaternion(Vector3.RIGHT, clampf(_pitch_s, -0.5, 0.6)) * _grip_inv
		var btr: Vector3
		var btl: Vector3
		var bpr: Vector3
		var bpl := Vector3(-0.7, -1.0, 0.2)
		if low:
			# over the top: the gun hand up behind the head, the other hand braced on the knee
			btr = Vector3(0.16, 0.42, 0.11)
			bpr = Vector3(1.0, 0.25, 0.2)
			btl = Vector3(-0.08, -0.30, -0.24)
			_head_pitch += 0.24 * b
			_c_pitch += 0.08 * b
		elif sd >= 0.0:
			# round the corner on the character's right: arm out to the side, head away from it
			btr = Vector3(0.52, 0.07, 0.07)
			bpr = Vector3(0.2, -1.0, 0.4)
			btl = Vector3(-0.05, -0.15, -0.22)
			_c_yaw -= 0.12 * b
			_head_yaw += 0.35 * b
		else:
			# round the corner on the left: the torso twists and leans so the gun hand reaches
			# across the chest and out past the corner
			btr = Vector3(-0.47, 0.08, -0.08)
			bpr = Vector3(0.2, -1.0, -0.6)
			btl = Vector3(-0.12, -0.17, -0.18)
			_c_yaw += 0.80 * b
			_s_yaw += 0.25 * b
			_c_roll -= 0.10 * b
			_head_yaw -= 0.30 * b
		_head_pitch += 0.10 * b
		tr = tr.lerp(btr, b)
		tl = tl.lerp(btl, b)
		pr = pr.lerp(bpr, b)
		pl = pl.lerp(bpl, b)
		q = q.slerp(qb, b)
	var w := maxf(k, b)
	_w_pitch *= 1.0 - w
	_wr_t = tr if _wr_w <= 0.001 else _wr_t.lerp(tr, w)
	_wl_t = tl if _wl_w <= 0.001 else _wl_t.lerp(tl, w)
	_wr_p = pr if _wr_w <= 0.001 else _wr_p.lerp(pr, w)
	_wl_p = pl if _wl_w <= 0.001 else _wl_p.lerp(pl, w)
	_wr_w = lerpf(_wr_w, 1.0, w)
	_wl_w = lerpf(_wl_w, lw, w)
	_hr_q = q if _hr_w <= 0.001 else _hr_q.slerp(q, w)
	_hr_w = lerpf(_hr_w, 1.0, w)


func _pose_ladder(dt: float) -> void:
	var L := _leg_len
	var A := _arm_len
	_swim_phase = fposmod(_swim_phase + absf(vertical_speed) * 1.25 * dt, 1.0)
	var s := sin(TAU * _swim_phase)
	_hp = Vector3(0.0, -0.03 * L, 0.06)
	_h_pitch = 0.08
	_c_pitch = 0.05
	_head_stab = 0.6
	_head_pitch = -0.2
	_al_t = Vector3(-0.02, A * 0.30 + s * 0.16, -A * 0.66)
	_ar_t = Vector3(0.02, A * 0.30 - s * 0.16, -A * 0.66)
	_al_p = Vector3(-0.8, -0.9, 0.2)
	_ar_p = Vector3(0.8, -0.9, 0.2)
	_ll_t = Vector3(-0.02, -L * (0.78 + 0.13 * s), -L * 0.22)
	_lr_t = Vector3(0.02, -L * (0.78 - 0.13 * s), -L * 0.22)
	_fl_pitch = 0.1
	_fr_pitch = 0.1


## Side vault (motion_style MOTION_VAULT) or mantle (MOTION_MANTLE). motion_t = progress, motion_height =
## obstacle top above the character origin (the hands are planted there).
func _pose_vault() -> void:
	var u := motion_t if motion_t >= 0.0 else clampf(_state_time / 0.65, 0.0, 1.0)
	if motion_style == MOTION_MANTLE:
		_pose_mantle(u)
		return
	var L := _leg_len
	var A := _arm_len
	# approach 0-0.3: reach down to the top / over 0.3-0.7: legs tucked and swung through on the
	# right / land 0.7-1: legs reach down, torso comes up
	var plant := smoothstep(0.05, 0.28, u) * (1.0 - smoothstep(0.60, 0.80, u))
	var tuck := smoothstep(0.14, 0.40, u) * (1.0 - smoothstep(0.66, 0.92, u))
	var land := smoothstep(0.74, 1.0, u)
	_hp = Vector3(0.08 * tuck, 0.04 - 0.10 * land, 0.0)
	_h_pitch = 0.18 + 0.38 * tuck - 0.08 * land
	_h_roll = 0.38 * tuck
	_h_yaw = -0.22 * tuck
	_s_pitch = 0.06 + 0.06 * tuck
	_c_pitch = 0.08 + 0.16 * tuck
	_c_roll = -0.24 * tuck
	_head_stab = 0.7
	# free arms: left reaching for the top, right out to the side for balance
	_al_t = Vector3(-0.04, -A * 0.70, -A * 0.50)
	_ar_t = Vector3(A * 0.52, -A * 0.18, A * 0.12).lerp(Vector3(A * 0.20, -A * 0.80, -A * 0.10), land)
	_al_p = Vector3(-0.6, -0.6, 0.5)
	_ar_p = Vector3(0.8, -0.6, 0.3)
	# the left hand is planted on the obstacle (model space) while the body passes over it
	var h := clampf(motion_height, 0.25, 1.7)
	if plant > 0.001:
		_xl_t = Vector3(-0.20, h + 0.02, -0.16 + 0.30 * smoothstep(0.25, 0.7, u))
		_xl_abs = true
		_xl_p = Vector3(-0.9, 0.3, 0.4)
		_xl_w = plant
	# legs (hips frame): straight -> tucked to the right -> reaching for the ground
	var lt := Vector3(-0.04, -L * 0.94, -L * 0.04)
	var rt := Vector3(0.05, -L * 0.94, L * 0.04)
	lt = lt.lerp(Vector3(0.14, -L * 0.52, -L * 0.34), tuck)
	rt = rt.lerp(Vector3(0.28, -L * 0.60, -L * 0.14), tuck)
	lt = lt.lerp(Vector3(-0.05, -L * 0.90, -L * 0.12), land)
	rt = rt.lerp(Vector3(0.06, -L * 0.94, L * 0.06), land)
	_ll_t = lt
	_lr_t = rt
	_ll_p = Vector3(-0.1, 0.25, -1.0)
	_lr_p = Vector3(0.5, 0.25, -1.0)
	_fl_pitch = 0.25 * tuck
	_fr_pitch = 0.30 * tuck


## Mantle: both hands on the ledge, pull up (0-0.62), knee / foot onto the top and stand (0.62-1).
func _pose_mantle(u: float) -> void:
	var L := _leg_len
	var A := _arm_len
	var h := clampf(motion_height, 0.0, 2.2)
	var hang := 1.0 - smoothstep(0.0, 0.62, u)          # 1 while hanging low on the wall
	var over := smoothstep(0.55, 0.85, u)               # torso tips over the edge
	var stand := smoothstep(0.80, 1.0, u)
	_hp = Vector3(0.0, -0.04 * hang, 0.04 * hang - 0.05 * over)
	_h_pitch = 0.10 + 0.10 * hang + 0.40 * over * (1.0 - stand)
	_s_pitch = 0.06 + 0.10 * over * (1.0 - stand)
	_c_pitch = 0.04 + 0.22 * over * (1.0 - stand) - 0.10 * hang
	_head_stab = 0.6
	_head_pitch = -0.25 * hang
	# hanging arms as fallback; the plant below pins the hands to the ledge
	_al_t = Vector3(-0.10, -A * 0.80, -A * 0.30)
	_ar_t = Vector3(0.10, -A * 0.80, -A * 0.30)
	_al_p = Vector3(-0.8, -0.7, 0.4)
	_ar_p = Vector3(0.8, -0.7, 0.4)
	var plant := 1.0 - smoothstep(0.78, 0.95, u)
	if plant > 0.001 and h > 0.05:
		_xl_t = Vector3(-0.22, h + 0.03, -0.30)
		_xr_t = Vector3(0.22, h + 0.03, -0.30)
		_xl_abs = true
		_xr_abs = true
		_xl_p = Vector3(-0.9, -0.5, 0.5)
		_xr_p = Vector3(0.9, -0.5, 0.5)
		_xl_w = plant
		_xr_w = plant
	# legs: scrambling against the wall, then the right foot steps onto the top
	var k := sin(u * TAU * 1.5) * hang
	_ll_t = Vector3(-0.06, -L * (0.70 + 0.10 * k), -L * 0.26)
	_lr_t = Vector3(0.06, -L * (0.80 - 0.10 * k), -L * 0.16)
	_ll_t = _ll_t.lerp(Vector3(-0.05, -L * 0.95, 0.02), stand)
	_lr_t = _lr_t.lerp(Vector3(0.06, -L * 0.95, -0.02), stand)
	_ll_p = Vector3(-0.2, 0.3, -1.0)
	_lr_p = Vector3(0.2, 0.3, -1.0)
	var step := smoothstep(0.50, 0.70, u) * (1.0 - stand)
	if step > 0.001:
		_lr_t = _lr_t.lerp(Vector3(0.10, -L * 0.40, -L * 0.42), step)
	_fl_pitch = 0.2 * hang
	_fr_pitch = 0.2 * hang


## Forward roll: a curled body rolling over its own centre (motion_t = progress).
func _pose_roll() -> void:
	var L := _leg_len
	var A := _arm_len
	var u := motion_t if motion_t >= 0.0 else minf(_state_time / 0.55, 1.0)
	var a := u * TAU
	var curl := smoothstep(0.0, 0.18, u) * (1.0 - smoothstep(0.86, 1.0, u))
	# ball centre: lower while rolling; hips sit behind / below it and travel around it
	var centre := Vector3(0.0, lerpf(0.62, 0.40, curl), 0.0)
	var off := Basis(Vector3.RIGHT, -a) * Vector3(0.0, -0.20, 0.0)
	_hips_abs = true
	_hp = centre + off
	_h_pitch = a + 0.35 * curl
	_s_pitch = 0.45 * curl + 0.05
	_c_pitch = 0.40 * curl + 0.05
	_head_stab = 0.0
	_head_pitch = 0.5 * curl
	_al_t = Vector3(0.03, -A * 0.35, -A * 0.55)
	_ar_t = Vector3(-0.03, -A * 0.35, -A * 0.55)
	# tucked legs (at the start / end this is a squat with the feet on the ground)
	_ll_t = Vector3(-0.05, -L * 0.42, -L * lerpf(0.22, 0.36, curl))
	_lr_t = Vector3(0.05, -L * 0.42, -L * lerpf(0.22, 0.36, curl))
	_ll_p = Vector3(-0.3, 0.3, -1.0)
	_lr_p = Vector3(0.3, 0.3, -1.0)


func _pose_parachute() -> void:
	var L := _leg_len
	var A := _arm_len
	var sway := sin(_time * 1.3) * 0.04
	# toggles: `flare` pulls both hands down in front of the chest, `steer` the hand of the turn side
	var pull_l := clampf(_flare_s + maxf(-_steer_s, 0.0) * 0.8, 0.0, 1.0)
	var pull_r := clampf(_flare_s + maxf(_steer_s, 0.0) * 0.8, 0.0, 1.0)
	_hp = Vector3(0.0, 0.0, 0.0)
	_h_pitch = -0.10 + _accel_s * 0.12 - _flare_s * 0.10
	_h_roll = _lean_s * 0.30 + sway
	_c_pitch = 0.06 + _flare_s * 0.06
	_head_stab = 0.6
	_head_pitch = 0.2 - _flare_s * 0.15
	_al_t = Vector3(-A * lerpf(0.38, 0.30, pull_l), A * lerpf(0.62, -0.10, pull_l), lerpf(-0.03, -A * 0.30, pull_l))
	_ar_t = Vector3(A * lerpf(0.38, 0.30, pull_r), A * lerpf(0.62, -0.10, pull_r), lerpf(-0.03, -A * 0.30, pull_r))
	_al_p = Vector3(-1.0, -0.6, 0.3)
	_ar_p = Vector3(1.0, -0.6, 0.3)
	# legs: hanging, swinging forward together for the landing while flaring
	_ll_t = Vector3(-0.03, -L * lerpf(0.90, 0.84, _flare_s), lerpf(-L * 0.20 + sway, -L * 0.36, _flare_s))
	_lr_t = Vector3(0.03, -L * lerpf(0.93, 0.84, _flare_s), lerpf(-L * 0.12 - sway, -L * 0.34, _flare_s))
	_fl_pitch = 0.3
	_fr_pitch = 0.3


func _pose_freefall() -> void:
	var L := _leg_len
	var A := _arm_len
	var fl := sin(_time * 9.0) * 0.03
	_hips_abs = true
	_hp = Vector3(0.0, _hips_rest.y, 0.1)
	_h_pitch = clampf(1.30 - _pitch_s, 0.2, 2.6)
	_h_roll = _lean_s * 0.35
	_c_pitch = -0.22
	_head_stab = 0.0
	_head_pitch = -0.45
	_al_t = Vector3(-A * 0.80, A * 0.40 + fl, -A * 0.10)
	_ar_t = Vector3(A * 0.80, A * 0.40 - fl, -A * 0.10)
	_al_p = Vector3(-0.3, -1.0, 0.5)
	_ar_p = Vector3(0.3, -1.0, 0.5)
	_ll_t = Vector3(-_hip_x * 2.4, -L * 0.74, L * 0.30 + fl)
	_lr_t = Vector3(_hip_x * 2.4, -L * 0.74, L * 0.30 - fl)
	_ll_p = Vector3(-0.5, 0.0, -1.0)
	_lr_p = Vector3(0.5, 0.0, -1.0)
	_fl_pitch = 0.8
	_fr_pitch = 0.8


# --- weapon / aim layer ----------------------------------------------------------------------------------

func _layer_weapon() -> void:
	if _upper_ok <= 0.0:
		return
	var A := _arm_len
	var aim := _aim_s * _upper_ok
	var carry := 0.0 if _seated else _carry_s * _upper_ok * (1.0 - aim)
	if aim <= 0.001 and carry <= 0.001:
		return
	var pose := _weapon_id
	if _seated and pose != W_THROW:
		pose = W_PISTOL         # one-handed out of the window, whatever the weapon
	_w_pitch = _pitch_s * aim
	_w_yaw = _aim_yaw_s
	# the torso takes part of the pitch, the arms the rest (targets are in model space)
	_s_pitch -= _pitch_s * 0.18 * aim
	_c_pitch -= _pitch_s * 0.22 * aim
	_head_pitch -= _pitch_s * 0.55 * aim
	if absf(_aim_yaw_s) > 0.0001:
		# aiming sideways (drive-by): the torso turns part of the way, the arm and head the rest
		var tw := clampf(_aim_yaw_s, -1.3, 1.3)
		_c_yaw += tw * 0.40 * aim
		_s_yaw += tw * 0.15 * aim
		_head_yaw += _aim_yaw_s * 0.35 * aim
		if _seated:
			# lean towards the window the gun points out of
			var side := clampf(sin(_aim_yaw_s) * 1.2, -1.0, 1.0)
			_c_roll -= side * 0.22 * aim
			_s_roll -= side * 0.10 * aim
	var tl: Vector3
	var tr: Vector3
	var pl := Vector3(-0.55, -1.0, 0.25)
	var pr := Vector3(0.55, -1.0, 0.25)
	var hand_w := aim
	var w_l := aim
	var w_r := aim
	match pose:
		W_PISTOL:
			# in front of the right eye; the support hand cups the grip from below
			tr = Vector3(0.095, 0.035, -A * 0.84)
			tl = Vector3(0.045, -0.005, -A * 0.81)
			if _seated:
				# drive-by: the gun hand up in the window opening instead of on the sill (review: from
				# inside the cabin and from outside the gun read as hidden behind the door line)
				tr.y += SEATED_GUN_RAISE
		W_RIFLE:
			_h_yaw -= 0.20 * aim
			_c_yaw -= 0.32 * aim
			tr = Vector3(0.115, -0.075, -0.17)
			tl = Vector3(0.105, -0.060, -0.17 - A * 0.58)
			pr = Vector3(0.9, -0.8, 0.3)
			pl = Vector3(-0.4, -1.0, 0.1)
		W_RPG:
			_h_yaw -= 0.12 * aim
			_c_yaw -= 0.22 * aim
			tr = Vector3(0.175, -0.01, -0.20)
			tl = Vector3(0.13, -0.03, -0.20 - A * 0.42)
			pr = Vector3(1.0, -0.6, 0.3)
			pl = Vector3(-0.5, -1.0, 0.1)
		W_THROW:
			_c_yaw -= 0.30 * aim
			tr = Vector3(0.27, 0.20, 0.14)
			tl = Vector3(-0.10, -0.06, -A * 0.80)
			pr = Vector3(1.0, -0.4, 0.4)
			hand_w = 0.0
		_:
			# W_MELEE and bare hands: guard, left side a little forward; `guard` raises a block
			# (forearms up in front of the face, chin tucked)
			var g := _guard_s
			_h_yaw -= 0.16 * aim
			_c_yaw -= 0.20 * aim * (1.0 - 0.5 * g)
			_c_pitch += (0.06 + 0.06 * g) * aim
			_head_pitch += 0.14 * g * aim
			tr = Vector3(0.13, -0.11, -A * 0.50).lerp(Vector3(0.075, 0.11, -A * 0.40), g)
			tl = Vector3(-0.10, -0.07, -A * 0.64).lerp(Vector3(-0.085, 0.14, -A * 0.44), g)
			pr = pr.lerp(Vector3(0.7, -1.0, 0.1), g)
			pl = pl.lerp(Vector3(-0.7, -1.0, 0.1), g)
			hand_w = 0.0
	if carry > 0.001:
		# low-ready two-hand carry for long guns; blends into the aim pose
		var cb := sin(TAU * phase * 2.0) * 0.012 * clampf(_speed_s / 3.0, 0.0, 1.0)
		var cr_t := Vector3(0.150, -0.300 + cb, -0.115)
		var cl_t := Vector3(-0.075, -0.385 + cb, -0.355)
		if aim > 0.001:
			tr = cr_t.lerp(tr, aim)
			tl = cl_t.lerp(tl, aim)
		else:
			tr = cr_t
			tl = cl_t
			pr = Vector3(1.0, -0.5, 0.5)
			pl = Vector3(-0.8, -0.7, 0.3)
		w_l = _carry_s * _upper_ok
		w_r = w_l
		hand_w = w_r
		_hr_q = _carry_q.slerp(Quaternion(Vector3.UP, _w_yaw) * Quaternion(Vector3.RIGHT, _w_pitch) * _grip_inv, aim)
	else:
		_hr_q = Quaternion(Vector3.UP, _w_yaw) * Quaternion(Vector3.RIGHT, _w_pitch) * _grip_inv
	if _seated:
		w_l = 0.0               # the other hand keeps steering
		if pose == W_THROW:
			hand_w = 0.0
	_wl_t = tl
	_wr_t = tr
	_wl_p = pl
	_wr_p = pr
	_wl_w = w_l
	_wr_w = w_r
	_hr_w = hand_w


# --- one-shot actions --------------------------------------------------------------------------------------

func _layer_action(dt: float) -> void:
	_act_t += dt
	var u := clampf(_act_t / maxf(_act_dur, 0.01), 0.0, 1.0)
	var A := _arm_len
	var L := _leg_len
	var env := smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.82, 1.0, u))
	match _act:
		A_FIRE:
			var k := (1.0 - u) * (1.0 - u)
			_wr_t += Vector3(0.0, 0.012, 0.035) * k
			_wl_t += Vector3(0.0, 0.010, 0.030) * k
			_w_pitch += 0.07 * k * _wr_w
			_c_pitch -= 0.015 * k
		A_PUNCH_R, A_PUNCH_L:
			var k := smoothstep(0.0, 0.32, u) * (1.0 - smoothstep(0.42, 0.95, u))
			var s := 1.0 if _act == A_PUNCH_R else -1.0
			var guard_near := Vector3(0.13 * s, -0.11, -A * 0.50)
			var hit := Vector3(0.015 * s, -0.02, -A * 0.93)
			var other := Vector3(-0.11 * s, -0.07, -A * 0.52)
			if s > 0.0:
				_xr_t = guard_near.lerp(hit, k)
				_xl_t = other
			else:
				_xl_t = guard_near.lerp(hit, k)
				_xr_t = other
			_xl_p = Vector3(-0.6, -1.0, 0.3)
			_xr_p = Vector3(0.6, -1.0, 0.3)
			_xl_w = env
			_xr_w = env
			_c_yaw += s * 0.42 * k
			_h_yaw += s * 0.14 * k
			_c_pitch += 0.08 * k
			_hp.z -= 0.035 * k
		A_HEAVY:
			var wind := smoothstep(0.0, 0.30, u) * (1.0 - smoothstep(0.30, 0.48, u))
			var strike := smoothstep(0.32, 0.52, u) * (1.0 - smoothstep(0.62, 1.0, u))
			_xr_t = Vector3(0.13, -0.11, -A * 0.50).lerp(Vector3(0.36, 0.12, 0.20), wind).lerp(Vector3(-0.12, -0.06, -A * 0.90), strike)
			_xl_t = Vector3(-0.12, -0.10, -A * 0.46)
			_xr_p = Vector3(1.0, -0.5, 0.4)
			_xl_p = Vector3(-0.6, -1.0, 0.3)
			_xr_w = env
			_xl_w = env
			_c_yaw += -0.55 * wind + 0.62 * strike
			_h_yaw += -0.18 * wind + 0.22 * strike
			_c_pitch += 0.16 * strike
			_hp.z -= 0.06 * strike
		A_KICK:
			var chamber := smoothstep(0.0, 0.30, u) * (1.0 - smoothstep(0.70, 1.0, u))
			var snap_k := smoothstep(0.28, 0.46, u) * (1.0 - smoothstep(0.52, 0.80, u))
			_xleg_t = Vector3(0.03, -L * 0.55, -L * 0.42).lerp(Vector3(0.02, -L * 0.30, -L * 0.90), snap_k)
			_xleg_w = chamber
			_h_pitch -= 0.20 * chamber
			_c_pitch += 0.10 * chamber
			_xr_t = Vector3(0.20, -0.16, -A * 0.30)
			_xl_t = Vector3(-0.16, -0.10, -A * 0.44)
			_xr_p = Vector3(0.6, -1.0, 0.3)
			_xl_p = Vector3(-0.6, -1.0, 0.3)
			_xr_w = env * 0.8
			_xl_w = env * 0.8
		A_HIT:
			# directional: hit_dir = where the blow came FROM (x right, y front)
			var k := smoothstep(0.0, 0.14, u) * (1.0 - u) * (1.0 - u) * 1.5 * clampf(hit_strength, 0.0, 2.0)
			var hd := hit_dir.normalized() if hit_dir.length_squared() > 0.0001 else Vector2(0.0, 1.0)
			var f := hd.y
			var s := hd.x
			_c_pitch -= 0.26 * k * f
			_s_pitch -= 0.10 * k * f
			_h_pitch -= 0.05 * k * f
			_head_pitch -= 0.20 * k * f
			_c_roll -= 0.30 * k * s
			_h_roll -= 0.08 * k * s
			_head_yaw -= 0.25 * k * s
			_c_yaw += 0.10 * k * f - 0.22 * k * s
			_hp.z += 0.05 * k * f
			_hp.x -= 0.05 * k * s
			_hp.y -= 0.03 * k
			if not _al_abs:
				_al_t += Vector3(-0.05 - 0.04 * s, 0.05, -0.08 * f) * k
			if not _ar_abs:
				_ar_t += Vector3(0.05 - 0.04 * s, 0.05, -0.08 * f) * k
		A_JACK:
			# reach into the car with both hands, grab, yank the occupant out
			var reach := smoothstep(0.0, 0.32, u) * (1.0 - smoothstep(0.40, 0.62, u))
			var yank := smoothstep(0.36, 0.58, u) * (1.0 - smoothstep(0.80, 1.0, u))
			var rest_l := Vector3(-0.14, -0.10, -A * 0.40)
			var rest_r := Vector3(0.14, -0.10, -A * 0.40)
			_xl_t = rest_l.lerp(Vector3(-0.12, 0.02, -A * 0.98), reach).lerp(Vector3(-0.20, -0.12, -A * 0.22), yank)
			_xr_t = rest_r.lerp(Vector3(0.12, 0.04, -A * 0.98), reach).lerp(Vector3(0.20, -0.10, -A * 0.22), yank)
			_xl_p = Vector3(-0.8, -0.8, 0.3)
			_xr_p = Vector3(0.8, -0.8, 0.3)
			_xl_w = env
			_xr_w = env
			_c_pitch += 0.22 * reach - 0.20 * yank
			_s_pitch += 0.10 * reach - 0.08 * yank
			_c_yaw += 0.25 * yank
			_hp.z += -0.06 * reach + 0.08 * yank
			_hp.y -= 0.04 * yank
		A_SHOVE:
			# two-hand push (rider off a bike, a pedestrian out of the way)
			var push := smoothstep(0.12, 0.34, u) * (1.0 - smoothstep(0.55, 0.95, u))
			_xl_t = Vector3(-0.12, -0.04, -A * 0.36).lerp(Vector3(-0.13, 0.0, -A * 0.98), push)
			_xr_t = Vector3(0.12, -0.04, -A * 0.36).lerp(Vector3(0.13, 0.0, -A * 0.98), push)
			_xl_p = Vector3(-0.8, -0.9, 0.3)
			_xr_p = Vector3(0.8, -0.9, 0.3)
			_xl_w = env
			_xr_w = env
			_c_pitch += 0.16 * push
			_h_pitch += 0.06 * push
			_hp.z -= 0.08 * push
		A_STOMP:
			# finisher on somebody on the ground: knee up, stamp down in front, arms out for balance
			var lift := smoothstep(0.0, 0.34, u) * (1.0 - smoothstep(0.34, 0.50, u))
			var down := smoothstep(0.36, 0.50, u) * (1.0 - smoothstep(0.70, 1.0, u))
			_xleg_t = Vector3(0.04, -L * 0.48, -L * 0.40).lerp(Vector3(0.05, -L * 0.97, -L * 0.34), down)
			_xleg_w = maxf(lift, down)
			_h_pitch += 0.10 * lift + 0.18 * down
			_c_pitch += 0.10 * down
			_head_pitch += 0.30 * maxf(lift, down)
			_xl_t = Vector3(-A * 0.55, -A * 0.30, -A * 0.10)
			_xr_t = Vector3(A * 0.50, -A * 0.35, A * 0.05)
			_xl_p = Vector3(-0.6, -1.0, 0.3)
			_xr_p = Vector3(0.6, -1.0, 0.3)
			_xl_w = env * 0.8
			_xr_w = env * 0.8
		A_THROW:
			var wind := smoothstep(0.0, 0.30, u) * (1.0 - smoothstep(0.34, 0.50, u))
			var rel := smoothstep(0.36, 0.54, u) * (1.0 - smoothstep(0.66, 1.0, u))
			_xr_t = Vector3(0.20, -0.20, -0.15).lerp(Vector3(0.30, 0.24, 0.20), wind).lerp(Vector3(0.06, 0.16, -A * 0.92), rel)
			_xl_t = Vector3(-0.12, -0.04, -A * 0.70).lerp(Vector3(-0.22, -0.30, 0.05), rel)
			_xr_p = Vector3(1.0, -0.3, 0.5)
			_xl_p = Vector3(-0.6, -1.0, 0.3)
			_xr_w = env
			_xl_w = env * 0.8
			_c_yaw += -0.45 * wind + 0.48 * rel
			_h_yaw += -0.12 * wind + 0.15 * rel
			_c_pitch += -0.10 * wind + 0.20 * rel
		A_PICKUP:
			var k := sin(PI * u)
			k = k * k * (3.0 - 2.0 * k)
			_hp.y -= L * 0.36 * k
			_hp.z += 0.06 * k
			_h_pitch += 0.62 * k
			_s_pitch += 0.20 * k
			_c_pitch += 0.20 * k
			_head_pitch += 0.25 * k
			_xr_t = Vector3(0.14, _ankle_h + 0.06, -0.36)
			_xr_abs = true
			_xr_p = Vector3(0.8, 0.2, 0.6)
			_xr_w = k
		A_RELOAD:
			# the left hand drops to the belt for a fresh magazine and comes back to the weapon
			var down := smoothstep(0.10, 0.36, u) * (1.0 - smoothstep(0.46, 0.74, u))
			var ready := Vector3(0.105, -0.26, -0.27)
			_xr_t = ready
			_xr_p = Vector3(1.0, -0.6, 0.4)
			_xr_w = env * (1.0 - _wr_w)
			var gun := _wr_t if _wr_w > 0.5 else ready
			var mag := gun + (Vector3(-0.01, -0.07, -0.16) if _carry_s > 0.5 else Vector3(-0.03, -0.085, -0.03))
			_xl_t = mag.lerp(Vector3(-0.17, -0.50, -0.02), down)
			_xl_p = Vector3(-0.8, -0.6, 0.4)
			_xl_w = env
			_c_pitch += 0.05 * env
			_head_pitch += 0.12 * env * (1.0 - _aim_s)
			if _hr_w < env and _weapon_id != W_NONE and _weapon_id != W_MELEE:
				_hr_q = Quaternion(Vector3.RIGHT, 0.35) * _grip_inv if _hr_w <= 0.001 else _hr_q
				_hr_w = maxf(_hr_w, env * 0.85)
		A_ENTER, A_EXIT:
			var k := sin(PI * u)
			var amt := 1.0 if _act == A_ENTER else 0.75
			_s_pitch += 0.16 * k * amt
			_c_pitch += 0.22 * k * amt
			_head_pitch += 0.25 * k * amt
			_h_roll += (0.10 if _act == A_ENTER else -0.10) * k
	if u >= 1.0:
		var finished := _act_name
		_act = A_NONE
		_act_name = ""
		action_finished.emit(finished)


# =================================================================================================
# solver
# =================================================================================================

func _solve() -> void:
	var sk := skeleton
	var ident := Quaternion.IDENTITY
	var g_hips := Quaternion.from_euler(Vector3(-_h_pitch, _h_yaw, -_h_roll))
	var g_spine := g_hips * Quaternion.from_euler(Vector3(-_s_pitch, _s_yaw, -_s_roll))
	var g_chest := g_spine * Quaternion.from_euler(Vector3(-_c_pitch, _c_yaw, -_c_roll))
	var p_hips := _hp if _hips_abs else _hips_rest + _hp

	# --- leg targets (model space)
	var hip_l := g_hips * _o_ul_l
	var hip_r := g_hips * _o_ul_r
	var tl := _ll_t if _ll_abs else p_hips + hip_l + g_hips * _ll_t
	var tr := _lr_t if _lr_abs else p_hips + hip_r + g_hips * _lr_t
	if _xleg_w > 0.0:
		tr = tr.lerp(p_hips + hip_r + g_hips * _xleg_t, _xleg_w)
	if _auto_hip:
		# lower the pelvis until every planted foot is within reach (feet never float)
		var maxl := _leg_len * 0.995
		var drop := 0.0
		if _ll_plant:
			var ax := tl.x - (p_hips.x + hip_l.x)
			var az := tl.z - (p_hips.z + hip_l.z)
			var need := (p_hips.y + hip_l.y - tl.y) - sqrt(maxf(maxl * maxl - ax * ax - az * az, 0.0004))
			if need > drop:
				drop = need
		if _lr_plant and _xleg_w <= 0.0:
			var bx := tr.x - (p_hips.x + hip_r.x)
			var bz := tr.z - (p_hips.z + hip_r.z)
			var need2 := (p_hips.y + hip_r.y - tr.y) - sqrt(maxf(maxl * maxl - bx * bx - bz * bz, 0.0004))
			if need2 > drop:
				drop = need2
		p_hips.y -= drop

	# --- torso chain
	var p_spine := p_hips + g_hips * _o_spine
	var p_chest := p_spine + g_spine * _o_chest
	var p_neck := p_chest + g_chest * _o_neck
	var g_look := Quaternion.from_euler(Vector3(-_head_pitch, _head_yaw, 0.0))
	var g_head: Quaternion
	if _head_stab <= 0.0:
		g_head = g_chest * g_look
	else:
		g_head = g_chest.slerp(g_look, _head_stab)
	var g_neck := g_chest.slerp(g_head, 0.5)
	_p_head = p_neck + g_neck * _o_head
	_g_head = g_head
	_p_chest = p_chest

	# --- hips position (local to the parent of the Hips bone)
	var hp_local := _hips_parent_inv * p_hips
	if _xf_k < 1.0:
		hp_local = _from_hp.lerp(hp_local, _xf_k)
	sk.set_bone_pose_position(_idx[B_HIPS], hp_local)

	_put(B_HIPS, ident, g_hips)
	_put(B_SPINE, g_hips, g_spine)
	_put(B_CHEST, g_spine, g_chest)
	_put(B_NECK, g_chest, g_neck)
	_put(B_HEAD, g_neck, g_head)
	_put(B_SHOULDER_L, g_chest, g_chest)
	_put(B_SHOULDER_R, g_chest, g_chest)

	# --- arms: base -> weapon layer -> action layer -> external hand IK
	var c := p_chest + g_chest * _o_shc
	var sh_l := p_chest + g_chest * _o_ua_l
	var sh_r := p_chest + g_chest * _o_ua_r
	var al := _al_t if _al_abs else sh_l + g_chest * _al_t
	var apl := _al_p if _al_abs else g_chest * _al_p
	var ar := _ar_t if _ar_abs else sh_r + g_chest * _ar_t
	var apr := _ar_p if _ar_abs else g_chest * _ar_p
	if _wl_w > 0.0 or _wr_w > 0.0:
		var qa := Quaternion(Vector3.UP, _w_yaw) * Quaternion(Vector3.RIGHT, _w_pitch)
		if _wl_w > 0.0:
			al = al.lerp(c + qa * _wl_t, _wl_w)
			apl = apl.lerp(qa * _wl_p, _wl_w)
		if _wr_w > 0.0:
			ar = ar.lerp(c + qa * _wr_t, _wr_w)
			apr = apr.lerp(qa * _wr_p, _wr_w)
	if _xl_w > 0.0:
		al = al.lerp(_xl_t if _xl_abs else c + _xl_t, _xl_w)
		apl = apl.lerp(_xl_p, _xl_w)
	if _xr_w > 0.0:
		ar = ar.lerp(_xr_t if _xr_abs else c + _xr_t, _xr_w)
		apr = apr.lerp(_xr_p, _xr_w)
	if hand_target_weight_l > 0.0:
		al = al.lerp(hand_target_l, clampf(hand_target_weight_l, 0.0, 1.0))
	if hand_target_weight_r > 0.0:
		ar = ar.lerp(hand_target_r, clampf(hand_target_weight_r, 0.0, 1.0))

	_limb(sh_l, al, apl, _l_uarm, _l_farm, g_chest, _rd_ua_l, _rd_la_l, _apex_arm_l, _al_tw)
	_put(B_UPPERARM_L, g_chest, _lq1)
	_put(B_LOWERARM_L, _lq1, _lq2)
	_put(B_HAND_L, _lq2, _lq2)
	_p_hand_l = _l_end
	_limb(sh_r, ar, apr, _l_uarm, _l_farm, g_chest, _rd_ua_r, _rd_la_r, _apex_arm_r, _ar_tw)
	_put(B_UPPERARM_R, g_chest, _lq1)
	_put(B_LOWERARM_R, _lq1, _lq2)
	if _hr_w > 0.0:
		_put(B_HAND_R, _lq2, _lq2.slerp(_hr_q, _hr_w) if _hr_w < 1.0 else _hr_q)
	else:
		_put(B_HAND_R, _lq2, _lq2)
	_p_hand_r = _l_end

	# --- legs
	var pole_l := _ll_p if _ll_abs else g_hips * _ll_p
	var pole_r := _lr_p if _lr_abs else g_hips * _lr_p
	_limb(p_hips + hip_l, tl, pole_l, _l_thigh, _l_shin, g_hips, _rd_ul_l, _rd_ll_l, _apex_leg_l, 0.0)
	_put(B_UPPERLEG_L, g_hips, _lq1)
	_put(B_LOWERLEG_L, _lq1, _lq2)
	_put(B_FOOT_L, _lq2, _foot_q(_lq2, _fl_pitch, _fl_yaw, _fl_abs))
	_limb(p_hips + hip_r, tr, pole_r, _l_thigh, _l_shin, g_hips, _rd_ul_r, _rd_ll_r, _apex_leg_r, 0.0)
	_put(B_UPPERLEG_R, g_hips, _lq1)
	_put(B_LOWERLEG_R, _lq1, _lq2)
	_put(B_FOOT_R, _lq2, _foot_q(_lq2, _fr_pitch, _fr_yaw, _fr_abs if _xleg_w <= 0.0 else _fr_abs * (1.0 - _xleg_w)))


func _foot_q(g_shin: Quaternion, pitch: float, yaw: float, abs_w: float) -> Quaternion:
	if abs_w >= 1.0:
		return Quaternion.from_euler(Vector3(-pitch, yaw, 0.0))
	if abs_w <= 0.0:
		return g_shin * Quaternion(Vector3.RIGHT, -pitch)
	return (g_shin * Quaternion(Vector3.RIGHT, -pitch)).slerp(Quaternion.from_euler(Vector3(-pitch, yaw, 0.0)), abs_w)


## Analytic two-bone IK. Writes the model-space rotation deltas of the upper / lower bone to
## _lq1 / _lq2 and the reached end position to _l_end.
func _limb(a: Vector3, t: Vector3, pole: Vector3, l1: float, l2: float, base: Quaternion,
		rd1: Vector3, rd2: Vector3, apex: Vector3, twist: float) -> void:
	var at := t - a
	var d := at.length()
	var n: Vector3
	if d < 0.0001:
		n = Vector3(0.0, -1.0, 0.0)
	else:
		n = at / d
	d = clampf(d, absf(l1 - l2) + 0.02, (l1 + l2) * 0.999)
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var p := pole - n * pole.dot(n)
	var pl := p.length()
	if pl < 0.0001:
		p = n.cross(Vector3.RIGHT)
		pl = p.length()
		if pl < 0.0001:
			p = n.cross(Vector3.UP)
			pl = p.length()
	p /= pl
	var mid := n * (l1 * cos_a) + p * (l1 * sin_a)
	var d1 := mid / l1
	var d2 := ((n * d - mid) / l2).normalized()
	# upper bone: swing to the direction, then twist so its apex (elbow / knee) faces the pole
	var q1 := Quaternion(base * rd1, d1) * base
	var f := q1 * apex
	var want := p - d1 * p.dot(d1)
	var wl := want.length()
	if wl > 0.0001:
		want /= wl
		var ang := atan2(d1.dot(f.cross(want)), f.dot(want))
		q1 = Quaternion(d1, ang) * q1
	if twist != 0.0:
		_lq2 = Quaternion(d2, twist) * (Quaternion(q1 * rd2, d2) * q1)
	else:
		_lq2 = Quaternion(q1 * rd2, d2) * q1
	_lq1 = q1
	_l_end = a + n * d


func _put(b: int, g_parent: Quaternion, g: Quaternion) -> void:
	var q: Quaternion = _pre[b] * (g_parent.inverse() * g) * _post[b]
	if _xf_k < 1.0:
		q = _from_q[b].slerp(q.normalized(), _xf_k)
	skeleton.set_bone_pose_rotation(_idx[b], q)


func _begin_crossfade(duration: float) -> void:
	if not _ok or not is_instance_valid(skeleton) or _snap_next:
		return
	for i in B_COUNT:
		_from_q[i] = skeleton.get_bone_pose_rotation(_idx[i]).normalized()
	_from_hp = skeleton.get_bone_pose_position(_idx[B_HIPS])
	_xf_t = 0.0
	_xf_k = 0.0
	_xf_dur = maxf(duration, 0.0)
	if _xf_dur <= 0.0001:
		_xf_t = 1.0
		_xf_k = 1.0


func _set_weapon_pose(v: String) -> void:
	weapon_pose = v
	_weapon_id = int(WEAPON_IDS.get(v, W_NONE))


func _set_hide_head(v: bool) -> void:
	hide_head = v
	if _ok and is_instance_valid(skeleton):
		skeleton.set_bone_pose_scale(_idx[B_HEAD], Vector3.ONE * (0.001 if v else 1.0))


static func _dir(a: Vector3, b: Vector3, fallback: Vector3) -> Vector3:
	var d := b - a
	if d.length_squared() < 0.000001:
		return fallback
	return d.normalized()


static func _perp(v: Vector3, axis: Vector3) -> Vector3:
	var p := v - axis * v.dot(axis)
	if p.length_squared() < 0.000001:
		p = axis.cross(Vector3.UP)
		if p.length_squared() < 0.000001:
			p = axis.cross(Vector3.RIGHT)
	return p.normalized()
