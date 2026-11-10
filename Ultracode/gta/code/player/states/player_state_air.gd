class_name PlayerStateAir
extends PlayerState
## Jumping and falling: air control, fall damage, hard-landing reaction, water entry.

var _jumped: bool = false
var _time: float = 0.0
var _peak_fall: float = 0.0
var _ledge_t: float = 0.0
var _agl_t: float = 0.0

const AGL_INTERVAL := 0.1           ## s between ground probes while falling (freefall trigger)


func _init() -> void:
	public_name = "on_foot"


func enter(_previous: String, args: Dictionary) -> void:
	_jumped = bool(args.get("jumped", false))
	_time = 0.0
	_peak_fall = 0.0
	_agl_t = 0.0
	player.is_sprinting = false
	player.noise_radius = 0.0
	if player.is_crouching:
		player.set_crouching(false, true)
	player.set_collision_enabled(true)
	player.set_anim_state("jump" if _jumped else "fall")


func allows_weapons() -> bool:
	return true


func physics_update(delta: float) -> void:
	var p := player
	_time += delta
	var input := p.get_move_input()
	var mag := minf(input.length(), 1.0)
	var wish := p.get_wish_dir(input)

	p.set_aiming(p.pressed("aim"))
	p.process_weapon_input(delta)
	p.update_stamina(delta, false)

	# --- air control: steer, never brake
	if mag > 0.08:
		var planar := Vector3(p.velocity.x, 0.0, p.velocity.z)
		var top := maxf(planar.length(), Player.AIR_SPEED)
		p.accelerate_planar(wish.normalized() * top, Player.ACCEL_AIR, delta)
	if p.is_aiming or p.is_combat_facing():
		p.turn_toward(p.get_view_yaw(), Player.TURN_RATE_AIM, delta)
	elif mag > 0.08:
		p.turn_toward(atan2(-wish.x, -wish.z), Player.TURN_RATE * 0.5, delta)

	p.velocity.y = maxf(p.velocity.y - Player.GRAVITY * delta, -Player.TERMINAL_SPEED)
	var vy_before := p.velocity.y
	_peak_fall = maxf(_peak_fall, -vy_before)
	p.move_body(delta)

	if vy_before < -1.5 or not _jumped:
		p.set_anim_state("fall")
	else:
		p.set_anim_state("jump")

	# --- a jump that carries the player against a ledge: grab it and mantle up (checked a few
	# times per second, only while pushing towards it near the top of the jump)
	_ledge_t -= delta
	if _jumped and _ledge_t <= 0.0 and _time > 0.08 and mag > 0.3 and p.velocity.y < 2.5 and p.is_on_wall():
		_ledge_t = 0.06
		if p.try_traversal(wish.normalized(), true):
			return

	# --- a long drop below: skydive (freefall state; deploy with jump when a parachute is packed)
	_agl_t -= delta
	if _agl_t <= 0.0 and vy_before < -2.0 and p.states.has("freefall"):
		_agl_t = AGL_INTERVAL
		p.altitude_agl = p.measure_agl()
		if p.altitude_agl > Player.FREEFALL_MIN_AGL:
			p.change_state("freefall", {})
			return

	# --- into the water
	if p.water_depth > 0.9 and vy_before <= 0.5:
		p.change_state("swim", {"entry_speed": -vy_before})
		return

	# --- landing
	if p.grounded and vy_before <= 0.5:
		_land(-vy_before)
		return

	if p.global_position.y < Player.VOID_Y:
		p.recover_from_void()


func _land(impact: float) -> void:
	var p := player
	var lock := 0.0
	if impact > Player.HARD_LAND_SPEED:
		lock = lerpf(0.22, 0.65, clampf(inverse_lerp(Player.HARD_LAND_SPEED, Player.RAGDOLL_LAND_SPEED, impact), 0.0, 1.0))
		p.shake_camera(clampf(impact / 40.0, 0.12, 0.6))
		Audio.play_at("jump_land", p.global_position, 0.0, 0.9)
		Fx.dust(p.global_position, 1.0)
		p.emit_noise(7.0, "footstep")
	elif impact > 3.0:
		Audio.play_at("jump_land", p.global_position, -9.0, 1.1)
		p.emit_noise(4.0, "footstep")
	if impact > Player.FALL_SAFE_SPEED:
		var dmg := (impact - Player.FALL_SAFE_SPEED) * Player.FALL_DAMAGE_PER_MS
		p.apply_damage(Dmg.make(dmg, "fall", null, p.global_position, Vector3.DOWN))
		if p.is_dead:
			return
	if impact > Player.RAGDOLL_LAND_SPEED:
		p.ragdoll(Vector3(p.velocity.x, 0.0, p.velocity.z) * 30.0, 1.5)
		return
	p.change_state("on_foot", {"land_lock": lock, "landed": impact})
