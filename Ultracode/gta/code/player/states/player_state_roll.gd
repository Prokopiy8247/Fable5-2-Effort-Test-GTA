class_name PlayerStateRoll
extends PlayerState
## Combat roll and melee dodge step.
##
##   kind "roll"  aiming + jump + a direction: a forward roll along that direction (the body turns
##                into the roll, animator "roll" with motion_t), aim resumes afterwards
##   kind "step"  melee guard + jump + a direction: a quick crouched side / back step, the body keeps
##                facing the opponent (animator "crouch" strafing)
## Melee blows that land during the first DODGE_WINDOW of the motion miss (modify_damage); bullets
## still hit (no invulnerability frames against gunfire).

const ROLL_TIME := 0.62
const ROLL_DISTANCE := 3.2
const STEP_TIME := 0.30
const STEP_DISTANCE := 1.45
const DODGE_WINDOW := 0.75              ## fraction of the motion that avoids melee hits
const STEP_STAMINA := 0.06

var kind: String = "roll"
var dir: Vector3 = Vector3.FORWARD
var resume: String = "on_foot"

var _t: float = 0.0
var _dur: float = ROLL_TIME
var _speed: float = 5.0
var _face_yaw: float = 0.0
var _air: float = 0.0


func _init() -> void:
	public_name = "roll"


func enter(_previous: String, args: Dictionary) -> void:
	var p := player
	kind = str(args.get("kind", "roll"))
	resume = str(args.get("resume", "on_foot"))
	if not p.states.has(resume):
		resume = "on_foot"
	dir = args.get("dir", -p.global_basis.z)
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else -p.global_basis.z
	_t = 0.0
	_air = 0.0
	p.is_sprinting = false
	p.release_trigger()
	if kind == "step":
		_dur = STEP_TIME
		_speed = STEP_DISTANCE / STEP_TIME
		_face_yaw = p.rotation.y
		p.stamina = maxf(p.stamina - STEP_STAMINA, 0.0)
		p.set_anim_state("crouch", 0.06)
		Audio.play_at("footstep_concrete", p.global_position, -8.0, 1.2, 20.0)
	else:
		_dur = ROLL_TIME
		_speed = ROLL_DISTANCE / ROLL_TIME
		_face_yaw = atan2(-dir.x, -dir.z)
		p.rotation.y = _face_yaw
		if p.is_crouching:
			p.set_crouching(false, true)
		if p.animator != null:
			p.animator.motion_t = 0.0
		p.set_anim_state("roll", 0.08)
		Audio.play_at("body_fall", p.global_position, -12.0, 1.3, 20.0)
	p.emit_noise(3.0, "footstep")


func exit(_next: String) -> void:
	var p := player
	if p.animator != null:
		p.animator.motion_t = -1.0


## A melee blow in the dodge window misses; everything else lands normally.
func modify_damage(info: Dictionary, amount: float) -> float:
	var type := str(info.get("type", ""))
	if (type == "melee" or type == "bite") and _t < _dur * DODGE_WINDOW:
		info["dodged"] = true
		return 0.0
	return amount


func is_dodging() -> bool:
	return _t < _dur * DODGE_WINDOW


func physics_update(delta: float) -> void:
	var p := player
	_t += delta
	var u := clampf(_t / _dur, 0.0, 1.0)
	# speed profile: burst out, ease to a stop
	var prof := 1.35 - 0.9 * u if kind == "roll" else 1.6 * (1.0 - u * u)
	var v := dir * _speed * prof
	p.velocity.x = v.x
	p.velocity.z = v.z
	if p.grounded:
		p.velocity.y = minf(p.velocity.y, 0.0)
	else:
		p.velocity.y = maxf(p.velocity.y - Player.GRAVITY * delta, -Player.TERMINAL_SPEED)
	p.move_body(delta)
	if kind == "step":
		p.rotation.y = _face_yaw
		var target := p.melee_target
		if target != null and is_instance_valid(target):
			var to := target.global_position - p.global_position
			if Vector2(to.x, to.z).length() > 0.2:
				p.turn_toward(atan2(-to.x, -to.z), Player.TURN_RATE_AIM, delta)
				_face_yaw = p.rotation.y
	else:
		p.rotation.y = _face_yaw
		if p.animator != null:
			p.animator.motion_t = u
	if not p.grounded:
		_air += delta
		if _air > 0.2:
			p.change_state("air", {})
			return
	else:
		_air = 0.0
	p.update_water()
	if p.water_depth > Player.SWIM_ENTER_DEPTH:
		p.change_state("swim", {"entry_speed": 1.0})
		return
	if u >= 1.0:
		p.change_state(resume, {})
