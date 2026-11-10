class_name PlayerStateTakedown
extends PlayerState
## Silent stealth takedown from behind (spec 10A "Stealth mode").
##
## Offered while sneaking (Player.in_stealth) when an NPC stands within RANGE, the player is inside
## its rear arc (REAR_ARC_COS) and it is not alerted (is_alerted / get_awareness read defensively).
## The scanner lives in player_stealth.gd (Player.takedown_target); the ground states start this
## state on melee_heavy, or on fire with fists / a melee weapon in hand (Player.try_takedown()).
##
##   knife        grab the head, one stab                      -> kill
##   fists        rear choke hold                              -> knock-out
##   bat, crowbar, a firearm (pistol-whip)   blow to the head  -> knock-out
## The damage goes through the Dmg contract straight to the victim with silent = true, takedown =
## true (+ knockout / knockout_seconds for the knock-outs, knockdown so a body without knock-out
## support still goes down). No EventBus.noise_emitted is sent: a takedown is only a crime when
## somebody sees it (NpcBase reports the harm; Wanted keeps it pending until a witness calls it in).
## Animator: state "takedown", motion_style TD_* below, motion_t = progress.

const RANGE := 1.6                      ## victim origin within this (planar)
const MAX_DY := 0.7
const REAR_ARC_COS := -0.34             ## the player must be inside the victim's rear 140 deg
const AWARE_LIMIT := 0.6                ## get_awareness() at or above this = noticed
const GRAB_TIME := 0.16                 ## s to slide into the grab position
## victim origin -> attacker origin: HumanoidAnimator.TAKEDOWN_GRAB[style] (the poses reach that far)
const KILL_DAMAGE := 400.0
const KO_DAMAGE := 25.0
const KO_IMPULSE := 120.0
const KO_SECONDS := 30.0                ## how long a knocked-out NPC should stay down (AI may honour it)
const XP := 0.4                         ## Stealth skill points per takedown
## motion_style values of the animator's "takedown" state
const TD_KNIFE := 0
const TD_CHOKE := 1
const TD_BLUNT := 2
const TIMES := {TD_KNIFE: Vector2(0.95, 0.48), TD_CHOKE: Vector2(1.25, 0.78), TD_BLUNT: Vector2(0.85, 0.5)}  ## duration, hit

var target: Node3D = null
var kind: String = "knockout"           ## "kill" | "knockout"
var style: int = TD_CHOKE
var weapon_id: String = ""
var last_info: Dictionary = {}          ## Dmg info of the last takedown blow (tests, HUD)

var _t: float = 0.0
var _dur: float = 1.0
var _hit_at: float = 0.5
var _done: bool = false
var _start_pos: Vector3 = Vector3.ZERO
var _start_yaw: float = 0.0
var _grab: float = 0.5


func _init() -> void:
	public_name = "takedown"


# =================================================================================================
# rules (shared with the stealth scanner)
# =================================================================================================

## Could `p` take `n` down right now? (geometry + awareness; stealth mode is checked by the caller)
static func can_take_down(p: Node3D, n: Node3D) -> bool:
	if p == null or n == null or not is_instance_valid(n) or not n.is_inside_tree() or n == p:
		return false
	if n.get("is_dead") == true or PlayerStateMelee._is_down(n):
		return false
	var veh: Variant = n.get("current_vehicle")
	if veh != null and is_instance_valid(veh):
		return false
	var to := p.global_position - n.global_position
	if absf(to.y) > MAX_DY:
		return false
	to.y = 0.0
	var d := to.length()
	if d > RANGE or d < 0.05:
		return false
	var f := -n.global_basis.z
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return false
	if f.normalized().dot(to / d) > REAR_ARC_COS:
		return false                    # not behind it
	return not is_aware(n)


## Has this NPC noticed the player? (is_alerted, else get_awareness() >= AWARE_LIMIT)
static func is_aware(n: Node) -> bool:
	if n.get("is_alerted") == true:
		return true
	if n.has_method("get_awareness"):
		return float(n.call("get_awareness")) >= AWARE_LIMIT
	return false


# =================================================================================================
# state
# =================================================================================================

func enter(_previous: String, args: Dictionary) -> void:
	var p := player
	target = args.get("target", null) as Node3D
	if target == null or not is_instance_valid(target):
		p.change_state("on_foot", {})
		return
	weapon_id = ""
	if p.inventory != null and is_instance_valid(p.inventory):
		weapon_id = str(p.inventory.get("current_id"))
		if weapon_id == "<null>":
			weapon_id = ""
	if weapon_id == "knife":
		kind = "kill"
		style = TD_KNIFE
	elif weapon_id == "" or weapon_id == "fists":
		kind = "knockout"
		style = TD_CHOKE
	else:
		kind = "knockout"
		style = TD_BLUNT                    # bat / crowbar / pistol-whip
	_grab = float(HumanoidAnimator.TAKEDOWN_GRAB[style])
	var tv: Vector2 = TIMES[style]
	_dur = tv.x
	_hit_at = tv.x * tv.y
	_t = 0.0
	_done = false
	_start_pos = p.global_position
	_start_yaw = p.rotation.y
	last_info = {}
	p.release_trigger()
	p.set_aiming(false)
	p.is_sprinting = false
	p.noise_radius = 0.0
	p.velocity = Vector3.ZERO
	p.set_collision_enabled(false)
	if target.has_method("stop_moving"):
		target.call("stop_moving")
	if p.animator != null:
		p.animator.motion_style = style
		p.animator.motion_t = 0.0
	p.set_anim_state("takedown", 0.12)
	Audio.play_at("melee_swing", p.get_target_position(), -16.0, 0.9, 8.0)


func exit(_next: String) -> void:
	var p := player
	p.set_collision_enabled(true)
	if p.animator != null:
		p.animator.motion_t = -1.0
	p.takedown_target = null
	target = null


func physics_update(delta: float) -> void:
	var p := player
	_t += delta
	var u := clampf(_t / maxf(_dur, 0.01), 0.0, 1.0)
	if target != null and is_instance_valid(target) and not _done:
		# stay glued behind the victim (it may still drift a little)
		var f := -target.global_basis.z
		f.y = 0.0
		if f.length_squared() > 0.0001:
			f = f.normalized()
			var goal := target.global_position - f * _grab
			var k := clampf(_t / GRAB_TIME, 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			p.global_position = _start_pos.lerp(goal, k)
			p.rotation.y = lerp_angle(_start_yaw, atan2(-f.x, -f.z), k)
		if target.has_method("stop_moving") and _t < _hit_at:
			target.call("stop_moving")
	p.velocity = Vector3.ZERO
	if p.animator != null:
		p.animator.motion_t = u
	if not _done and _t >= _hit_at:
		_done = true
		_strike()
	if _t >= _dur:
		p.change_state("on_foot", {})


func _strike() -> void:
	var p := player
	var t := target
	if t == null or not is_instance_valid(t) or not t.has_method("apply_damage") or t.get("is_dead") == true:
		return
	var f := -t.global_basis.z
	f.y = 0.0
	f = f.normalized() if f.length_squared() > 0.0001 else -p.global_basis.z
	var pos := PlayerStateMelee._aim_point_of(t)
	var ko := kind == "knockout"
	var dir := (f * 0.35 + Vector3.DOWN).normalized() if ko else f
	var info := Dmg.make(KO_DAMAGE if ko else KILL_DAMAGE, "melee", p, pos, dir, {
		"weapon_id": weapon_id if weapon_id != "" else "fists",
		"silent": true, "takedown": true, "stealth": true,
		"knockout": ko, "knockout_seconds": KO_SECONDS if ko else 0.0,
		"knockdown": ko, "impulse": KO_IMPULSE if ko else 30.0,
		"zone": "head" if style == TD_BLUNT else "torso",
	})
	var was_dead: bool = t.get("is_dead") == true
	t.call("apply_damage", info)
	info["killed"] = (not was_dead) and is_instance_valid(t) and t.get("is_dead") == true
	last_info = info
	EventBus.hit_confirmed.emit(t if is_instance_valid(t) else null, info)
	Skills.add_xp("stealth", XP)
	# a quiet thud for the player's ears only: no AI noise event
	var snd := "knife_hit" if style == TD_KNIFE else "punch_hit"
	Audio.play_at(snd, pos, -12.0, 0.9, 10.0)
