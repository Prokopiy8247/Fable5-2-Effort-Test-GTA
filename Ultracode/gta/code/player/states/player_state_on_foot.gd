class_name PlayerStateOnFoot
extends PlayerState
## Ground locomotion: idle / walk / run / sprint (stamina), crouch, sneak, aim-strafe, wading in
## shallow water, vehicle entry (tap = drive / steal, hold = ride along), footstep noise,
## hard-landing stagger and hit staggers.
##
## The jump key is context sensitive (in this order): a ladder right in front -> climb it; an
## obstacle in front -> vault (<= 1.1 m) or mantle (<= 2.0 m); aiming + a direction -> dodge roll;
## otherwise a plain jump. Fists / a melee weapon + fire, melee_heavy or aim -> the melee stance.
##
## EXTENSION POINTS - a ground state that walks, aims and shoots should extend this class and
## override only what differs (PlayerStateMelee does; the cover / stealth state of the next wave
## should too). Every hook is called once per physics tick, in this order:
##   _wants_other_state() -> bool              switch state before anything moves (true = switched)
##   _handle_combat(delta) -> bool             aim + weapon input; returns "face the camera / target"
##   _target_speed(mag, combat) -> float       top speed of this tick
##   _target_velocity(wish, mag, max_speed) -> Vector3   planar velocity to accelerate towards
##   _update_facing(delta, wish, mag, combat)
##   _try_jump_actions(wish, mag) -> bool      consume a jump press (true = the state changed)
##   _update_anim(speed)                       animator state of this tick
## plus modify_damage() / on_damage() from PlayerState and stagger() below.

const STAGGER_DECEL := 7.0           ## m/s^2 while stumbling (hard landing at speed, heavy hit)
## Next states that keep sneaking (stealth) on: every other state (vehicle, swim, ladder, ragdoll,
## dead, busted ...) ends it.
const STEALTH_KEEP_STATES: PackedStringArray = ["on_foot", "air", "melee", "roll", "vault", "cover", "takedown"]

var _air_time: float = 0.0
var _land_lock: float = 0.0
var _land_anim: float = 0.0
var _exhausted: bool = false
var _step_dist: float = 0.0
var _staggering: bool = false
var _wading: float = 0.0


func _init() -> void:
	public_name = "on_foot"


func enter(_previous: String, args: Dictionary) -> void:
	_air_time = 0.0
	_land_lock = float(args.get("land_lock", 0.0))
	_land_anim = 0.0
	_staggering = false
	var impact := float(args.get("landed", 0.0))
	if impact > 4.0:
		_land_anim = maxf(_land_lock, 0.16)
		player.set_anim_state("land")
	# a hard landing while running: stumble forward instead of stopping dead
	var planar := Vector2(player.velocity.x, player.velocity.z).length()
	if impact > Player.HARD_LAND_SPEED and planar > 2.5:
		_staggering = true
		player.play_hit_react(Vector2(0.0, -1.0), 1.2)
	player.is_swimming = false
	player.is_underwater = false
	player.altitude_agl = 0.0
	player.set_collision_enabled(true)


func exit(_next: String) -> void:
	player.is_sprinting = false
	player.noise_radius = 0.0
	if not STEALTH_KEEP_STATES.has(_next):
		player.set_stealth(false)


func allows_weapons() -> bool:
	return _land_lock <= 0.0


func allows_vehicle_entry() -> bool:
	return _land_lock <= 0.0


## Lose control for `duration` seconds and slide with `push` (m/s, planar): heavy hits, blocked
## guard breaks, explosions that do not knock down.
func stagger(push: Vector3, duration: float) -> void:
	_land_lock = maxf(_land_lock, duration)
	_staggering = true
	player.velocity.x += push.x
	player.velocity.z += push.z


func is_staggering() -> bool:
	return _staggering and _land_lock > 0.0


func physics_update(delta: float) -> void:
	var p := player
	_land_lock = maxf(_land_lock - delta, 0.0)
	_land_anim = maxf(_land_anim - delta, 0.0)
	if _land_lock <= 0.0:
		_staggering = false
	var input := p.get_move_input()
	if _land_lock > 0.0:
		input = Vector2.ZERO
	var mag := minf(input.length(), 1.0)
	var wish := p.get_wish_dir(input)

	# --- crouch toggle
	if p.just_pressed("crouch") and _land_lock <= 0.0:
		if p.is_crouching:
			if p.can_stand():
				p.set_crouching(false)
		else:
			p.set_crouching(true)

	# --- stealth toggle (sneak)
	if InputMap.has_action(&"stealth") and p.just_pressed(&"stealth") and _land_lock <= 0.0:
		p.set_stealth(not p.in_stealth)

	if _try_takedown():
		return
	if _wants_other_state():
		return

	# --- cover key
	if InputMap.has_action(&"cover") and p.just_pressed(&"cover") and _land_lock <= 0.0 and p.grounded:
		if p.try_take_cover():
			return

	# --- aim + weapons
	var combat := _handle_combat(delta)

	# --- sprint / stamina
	if p.stamina <= 0.0:
		_exhausted = true
	elif p.stamina > 0.22:
		_exhausted = false
	_wading = clampf((p.water_depth - 0.25) / 0.9, 0.0, 1.0)
	p.is_sprinting = p.pressed("sprint") and mag > 0.5 and not p.is_crouching and not p.is_aiming \
			and not _exhausted and _wading < 0.3 and _sprint_allowed()
	p.update_stamina(delta, p.is_sprinting)
	if p.is_sprinting and p.in_stealth:
		p.set_stealth(false)

	# --- velocity
	var max_speed := _target_speed(mag, combat)
	var target := _target_velocity(wish, mag, max_speed)
	var rate := Player.ACCEL_GROUND if target.length_squared() > 0.0064 else Player.DECEL_GROUND
	if _staggering and _land_lock > 0.0:
		rate = STAGGER_DECEL
	p.accelerate_planar(target, rate, delta)

	# --- facing
	_update_facing(delta, wish, mag, combat)

	# --- jump (context sensitive)
	if p.just_pressed("jump") and _land_lock <= 0.0 and p.grounded:
		if _try_jump_actions(wish, mag):
			return
		if p.is_crouching:
			if p.can_stand():
				p.set_crouching(false)
		else:
			p.velocity.y = p.get_jump_speed()
			p.emit_noise(4.0, "footstep")
			p.change_state("air", {"jumped": true})
			return

	# --- move
	if p.grounded:
		p.velocity.y = minf(p.velocity.y, 0.0)
	else:
		p.velocity.y = maxf(p.velocity.y - Player.GRAVITY * delta, -Player.TERMINAL_SPEED)
	p.move_body(delta)
	if p.grounded:
		_air_time = 0.0
	else:
		_air_time += delta
		if _air_time > 0.14:
			p.change_state("air", {})
			return

	# --- water
	if p.water_depth > Player.SWIM_ENTER_DEPTH:
		p.change_state("swim", {"entry_speed": 0.0})
		return

	# --- vehicles (tap = drive / steal, hold = passenger)
	if p.process_vehicle_entry_input(delta, _land_lock <= 0.0):
		return

	# --- noise + animation
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	if speed < 0.4:
		p.noise_radius = 0.0
	elif p.is_crouching or p.in_stealth:
		p.noise_radius = p.get_stealth_noise_radius() * (0.8 if speed < Player.WALK_SPEED + 0.1 else 1.0)
	elif p.is_sprinting:
		p.noise_radius = Player.NOISE_SPRINT
	elif speed > Player.WALK_SPEED + 0.6:
		p.noise_radius = Player.NOISE_RUN
	else:
		p.noise_radius = Player.NOISE_WALK
	if not p.has_animator_footsteps():
		# distance based fallback when no animator drives the feet
		_step_dist += speed * delta
		if _step_dist > lerpf(0.8, 1.6, clampf(speed / Player.SPRINT_SPEED, 0.0, 1.0)):
			_step_dist = 0.0
			p.on_footstep(0, clampf(speed / Player.SPRINT_SPEED, 0.2, 1.0))
	_update_anim(speed)


# =================================================================================================
# hooks (override in subclasses)
# =================================================================================================

## Stealth takedown (Player.takedown_target, set by the stealth scanner while sneaking): melee_heavy,
## or fire with fists / a melee weapon in hand, not while aiming. True = the state changed.
func _try_takedown() -> bool:
	var p := player
	if p.takedown_target == null or _land_lock > 0.0 or p.pressed("aim"):
		return false
	var heavy := p.just_pressed("melee_heavy")
	var fire := p.fire_pressed_edge and (p.has_melee_weapon() or not p.is_armed())
	if not (heavy or fire):
		return false
	return p.try_takedown()


## Switch to another state before anything moves this tick. Base: fists / melee weapon + fire,
## melee_heavy or aim -> the melee stance (the press is handed over so it is not lost).
func _wants_other_state() -> bool:
	var p := player
	if _land_lock > 0.0 or not p.states.has("melee") or not p.has_melee_weapon():
		return false
	var press := ""
	if p.just_pressed("fire"):
		press = "fire"
	elif p.just_pressed("melee_heavy"):
		press = "heavy"
	elif p.pressed("aim"):
		press = "guard"
	if press == "":
		return false
	p.change_state("melee", {"press": press})
	return true


## Aim + weapon input. Returns true when the body should face the camera (combat facing).
func _handle_combat(delta: float) -> bool:
	var p := player
	p.set_aiming(p.pressed("aim") and _land_lock <= 0.0)
	p.process_weapon_input(delta)
	return p.is_aiming or p.is_combat_facing()


func _sprint_allowed() -> bool:
	return true


func _target_speed(mag: float, combat: bool) -> float:
	var p := player
	var max_speed := Player.RUN_SPEED
	if p.is_sprinting:
		max_speed = Player.SPRINT_SPEED
	elif p.is_crouching:
		max_speed = Player.CROUCH_SPEED
	elif combat:
		max_speed = Player.AIM_SPEED
	elif p.in_stealth:
		max_speed = Player.STEALTH_SPEED
	if not p.is_sprinting and (mag < Player.WALK_INPUT_THRESHOLD or p.is_walk_held()):
		max_speed = minf(max_speed, Player.WALK_SPEED)
	return max_speed * lerpf(1.0, 0.45, _wading)


func _target_velocity(wish: Vector3, mag: float, max_speed: float) -> Vector3:
	if mag > 0.08:
		return wish.normalized() * max_speed
	return Vector3.ZERO


func _update_facing(delta: float, wish: Vector3, mag: float, combat: bool) -> void:
	var p := player
	# first person always looks where the camera looks
	if combat or p.is_first_person():
		p.turn_toward(p.get_view_yaw(), Player.TURN_RATE_AIM, delta)
	elif mag > 0.08:
		var rate := Player.TURN_RATE_SPRINT if p.is_sprinting else Player.TURN_RATE
		p.turn_toward(atan2(-wish.x, -wish.z), rate, delta)


## Context actions of the jump key. Returns true when one started (the state changed).
func _try_jump_actions(wish: Vector3, mag: float) -> bool:
	var p := player
	if p.is_crouching:
		return false
	if p.try_start_ladder_from_jump():
		return true
	var dir := wish if mag > 0.2 else -p.global_basis.z
	dir.y = 0.0
	if dir.length_squared() > 0.0001 and p.try_traversal(dir.normalized(), false):
		return true
	if p.is_aiming and mag > 0.3 and p.states.has("roll"):
		p.change_state("roll", {"kind": "roll", "dir": wish.normalized(), "resume": id})
		return true
	return false


func _update_anim(speed: float) -> void:
	var p := player
	if _land_anim > 0.0:
		p.set_anim_state("land")
	elif p.is_crouching:
		p.set_anim_state("crouch")
	elif speed > 0.15:
		p.set_anim_state("locomotion")
	else:
		p.set_anim_state("idle")
