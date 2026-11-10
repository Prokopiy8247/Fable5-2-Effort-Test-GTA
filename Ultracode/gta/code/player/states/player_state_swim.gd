class_name PlayerStateSwim
extends PlayerState
## Swimming: floating / stroking at the surface, diving (crouch = down, jump = up, forward follows
## the camera pitch), breath and drowning, boarding boats from the water.

var _underwater: bool = false
var _drown_t: float = 0.0
var _stroke_t: float = 0.0
var _exhausted: bool = false
var _time: float = 0.0


func _init() -> void:
	public_name = "swimming"


func enter(_previous: String, args: Dictionary) -> void:
	var p := player
	_underwater = false
	_drown_t = 0.0
	_stroke_t = 0.4
	_time = 0.0
	p.is_swimming = true
	p.is_sprinting = false
	p.noise_radius = 0.0
	if p.is_crouching:
		p.set_crouching(false, true)
	p.set_aiming(false)
	p.release_trigger()
	p.set_collision_enabled(true)
	var entry := float(args.get("entry_speed", 0.0))
	var surface := Vector3(p.global_position.x, p.water_surface_y, p.global_position.z)
	if entry > 5.0:
		Fx.splash(surface, clampf(entry / 8.0, 1.0, 2.5))
		Audio.play_at("splash_large", surface, 0.0, 1.0)
		p.emit_noise(18.0, "crash")
	else:
		Fx.splash(surface, 0.7)
		Audio.play_at("splash_small", surface, -4.0, 1.0)
	p.velocity.y *= 0.4
	p.velocity.x *= 0.6
	p.velocity.z *= 0.6
	p.set_anim_state("tread")
	EventBus.player_entered_water.emit()


func exit(_next: String) -> void:
	var p := player
	p.is_swimming = false
	_set_underwater(false)
	EventBus.player_exited_water.emit()


func allows_vehicle_entry() -> bool:
	return not _underwater


func physics_update(delta: float) -> void:
	var p := player
	_time += delta
	var surf := p.water_surface_y
	var float_y := surf - Player.FLOAT_DEPTH
	var y := p.global_position.y
	var input := p.get_move_input()
	var mag := minf(input.length(), 1.0)
	var wish := p.get_wish_dir(input)
	var up := p.pressed("jump")
	var down := p.pressed("crouch")
	var below := float_y - y                         # > 0 when under the floating line
	var diving := below > 0.15 or down

	if p.stamina <= 0.0:
		_exhausted = true
	elif p.stamina > 0.22:
		_exhausted = false
	var fast := p.pressed("sprint") and mag > 0.5 and not _exhausted
	p.update_stamina(delta, fast)

	var sp := Player.SWIM_FAST_SPEED if fast else Player.SWIM_SPEED
	var target := Vector3.ZERO
	var vy := 0.0
	if diving:
		sp = Player.DIVE_SPEED * (1.3 if fast else 1.0)
		if mag > 0.08:
			target = wish.normalized() * sp
		if down:
			vy = -Player.DIVE_VERTICAL_SPEED
		elif up:
			vy = Player.DIVE_VERTICAL_SPEED * Player.SURFACE_SPEED_MULT
		elif input.y > 0.3:
			# swim where the camera looks
			var pitch := p.get_view_pitch()
			vy = sin(pitch) * sp
			target *= maxf(cos(pitch), 0.25)
		else:
			vy = Player.BUOYANCY_SPEED
		if below <= 0.15 and vy > 0.0:
			vy = clampf(below * 5.0, -2.5, 2.5)        # back at the surface
		p.velocity.y = move_toward(p.velocity.y, vy, 7.0 * delta)
	else:
		if mag > 0.08:
			target = wish.normalized() * sp
		# spring to the floating line (follows the waves)
		p.velocity.y = lerpf(p.velocity.y, clampf(below * 6.0, -3.0, 3.0), 1.0 - exp(-10.0 * delta))
	p.accelerate_planar(target, Player.ACCEL_SWIM, delta)
	if mag > 0.08:
		p.turn_toward(atan2(-wish.x, -wish.z), Player.TURN_RATE_SWIM, delta)

	p.move_body(delta, false)
	p.update_water()

	# --- leaving the water (wading ashore, climbing a slope, being lifted out)
	if p.water_depth < Player.SWIM_EXIT_DEPTH and (p.is_on_floor() or p.water_depth <= 0.02):
		p.change_state("on_foot" if p.is_on_floor() else "air", {})
		return

	# --- breath
	var submerged := p.global_position.y < p.water_surface_y - Player.SUBMERGE_DEPTH
	_set_underwater(submerged)
	if submerged:
		var lungs := Player.BREATH_SECONDS * Skills.get_multiplier("lung", 0.8, 2.2)
		if p.has_scuba:
			lungs *= Player.SCUBA_BREATH_MULT
		p.breath = maxf(p.breath - delta / lungs, 0.0)
		Skills.add_xp("lung", delta * 0.05)
		if p.breath <= 0.0:
			_drown_t += delta
			if _drown_t >= 1.0:
				_drown_t = 0.0
				p.apply_damage(Dmg.make(Player.DROWN_DAMAGE, "drown", null, p.global_position))
				if p.is_dead:
					return
	else:
		_drown_t = 0.0

	# --- boats (tap = take the helm / steal, hold = ride along)
	if p.process_vehicle_entry_input(delta, not _underwater):
		return

	# --- harbour ladders: swim up to one and press jump (or interact at the prompt)
	if p.just_pressed("jump") and not _underwater and p.try_start_ladder_from_jump():
		return

	# --- presentation
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	if speed > 0.6:
		Skills.add_xp("stamina", delta * 0.012)
		_stroke_t -= delta
		if _stroke_t <= 0.0:
			_stroke_t = 0.85 if not fast else 0.6
			if not submerged:
				Audio.play_at("swim_stroke", p.global_position + Vector3(0.0, Player.FLOAT_DEPTH, 0.0), -6.0, randf_range(0.92, 1.08), 30.0)
				p.emit_noise(5.0, "footstep")
	if submerged or below > 0.55:
		p.set_anim_state("dive")
		var planar := maxf(speed, 0.4)
		p.anim_dive_pitch = clampf(atan2(p.velocity.y, planar), -1.2, 1.2)
	elif speed > 0.5:
		p.set_anim_state("swim")
	else:
		p.set_anim_state("tread")


func _set_underwater(on: bool) -> void:
	if on == _underwater:
		return
	_underwater = on
	player.is_underwater = on
	EventBus.player_submerged.emit(on)
	if not on and player.breath < 0.6 and not player.is_dead:
		Audio.play_at("breath_gasp", player.global_position + Vector3(0.0, 1.6, 0.0), -3.0)
