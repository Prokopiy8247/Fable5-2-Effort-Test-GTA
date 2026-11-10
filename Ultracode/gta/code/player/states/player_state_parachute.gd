class_name PlayerStateParachute
extends PlayerState
## Flying under the canopy (spec 29A, docs/PLAYER.md section 14). Entered from PlayerStateFreefall with
## the jump key; uses up the pack (Player.has_parachute = false).
##
##   OPEN      OPEN_TIME of inflation: the fall is braked from freefall speed to the canopy's sink
##   FLY       ram-air glide ~2.9:1 (FWD_SPEED / SINK); move_left / move_right = toggles (turn, banks
##             the canopy, costs height); move_forward = front risers (faster, steeper);
##             move_back or sprint = FLARE: brakes the canopy - for FLARE_RESERVE seconds the flare
##             turns forward speed into lift (sink drops to SINK_FLARE), held longer the canopy runs
##             out of speed and sinks again (SINK_STALL); the reserve recharges in normal flight
##   LANDED    touchdown is judged on the vertical / horizontal speed at contact:
##               good (sink <= GOOD_SINK, speed <= GOOD_FWD)   run-out on the feet, no damage
##               medium (<= BAD_SINK / BAD_FWD)                 stumble (lost control) + small damage
##               hard                                           ragdoll + damage
##             landing in water -> swim; flying into a wall fast -> ragdoll + damage
##   enter_vehicle in the air = cut away (the canopy flies off, the player falls)
## Altitude above ground: Player.altitude_agl every tick (HUD altimeter), public name "parachute".

enum { OPEN, FLY, LANDED }

const OPEN_TIME := 0.9              ## canopy inflation (same as the gear's animation)
const OPEN_DECEL := 46.0            ## m/s^2 of braking at full inflation
const FWD_SPEED := 10.5             ## m/s cruise airspeed
const FWD_FAST := 13.5              ## front risers (move_forward)
const FWD_BRAKE := 4.0              ## full brakes
const SINK := 3.6                   ## cruise sink -> glide ratio ~2.9 : 1
const SINK_FAST := 5.4
const SINK_FLARE := 0.9             ## sink of a full flare with a full reserve
const SINK_STALL := 5.0             ## brakes held after the reserve ran out
const FLARE_RESERVE := 2.4          ## s of full flare from a full reserve
const FLARE_RECHARGE := 3.0         ## s of normal flight to refill the reserve
const BRAKE_RATE := 3.5             ## toggle travel per second
const TURN_RATE := 1.15             ## rad/s at a full toggle
const TURN_SINK := 1.6              ## extra sink at a full toggle
const H_ACCEL := 6.0                ## m/s^2 airspeed changes
const V_ACCEL := 5.0                ## m/s^2 sink changes (after the opening)
const GOOD_SINK := 2.8
const GOOD_FWD := 8.5
const BAD_SINK := 4.8
const BAD_FWD := 12.0
const STUMBLE_TIME := 0.6
const RUN_OUT_TIME := 0.7
const RUN_OUT_DECEL := 7.0
const WALL_HIT_SPEED := 6.5
const FLY_XP := 0.006               ## flying skill per second under the canopy
const LAND_XP := 0.25               ## a good landing
const BANK_MAX := 0.42              ## rad of canopy bank at a full toggle
const FLARE_PITCH := 0.32           ## rad of canopy pitch at full brakes

var phase: int = OPEN
var brakes: float = 0.0             ## 0..1 both toggles down (flare)
var steer: float = 0.0              ## -1..1 toggle difference (+ = right)
var reserve: float = 1.0            ## 0..1 flare reserve
var airspeed: float = 0.0
var sink: float = 0.0               ## m/s, + = down
var landing: String = ""            ## "good" / "stumble" / "hard" / "water" / "wall" after touchdown
var landing_sink: float = 0.0       ## vertical speed at touchdown (m/s)
var landing_speed: float = 0.0      ## horizontal speed at touchdown (m/s)
var landing_damage: float = 0.0
var time: float = 0.0

var _t: float = 0.0
var _fast: float = 0.0
var _hint: Dictionary = {"side": 0.0, "height": 2.3, "distance": 7.2, "follow_yaw": 0.0, "follow_pitch": -0.16,
		"rigid": true, "fov_add": 6.0, "mask": 0}


func _init() -> void:
	public_name = "parachute"


func enter(_previous: String, _args: Dictionary) -> void:
	var p := player
	public_name = "parachute"
	phase = OPEN
	_t = 0.0
	time = 0.0
	brakes = 0.0
	steer = 0.0
	_fast = 0.0
	reserve = 1.0
	landing = ""
	landing_sink = 0.0
	landing_speed = 0.0
	landing_damage = 0.0
	var h := Vector3(p.velocity.x, 0.0, p.velocity.z)
	airspeed = h.length()
	sink = -p.velocity.y
	p.has_parachute = false             # the pack is used up
	p.is_sprinting = false
	p.noise_radius = 0.0
	p.set_aiming(false)
	p.release_trigger()
	p.set_collision_enabled(true)
	if p.chute != null:
		p.chute.open_canopy()
		p.chute.set_wind(0.0)
	p.set_anim_state("parachute", 0.45)
	p.emit_noise(25.0, "parachute")
	p.altitude_agl = p.measure_agl()


func exit(_next: String) -> void:
	var p := player
	if p.chute != null:
		p.chute.set_flap(0.0)
		if p.chute.is_open():
			# leaving without a landing (death, teleport, respawn, a knock-down): the canopy goes - folds
			# down near the ground, is carried off higher up, vanishes with a dead pilot
			var kind := "reset"
			if p.is_inside_tree() and not p.is_dead:
				kind = "land" if p.altitude_agl < 3.0 else "cut"
			p.chute.release_canopy(kind, p.velocity)
	if p.animator != null:
		p.animator.flare = 0.0


func allows_weapons() -> bool:
	return false


func get_camera_hint() -> Dictionary:
	_hint["follow_yaw"] = player.rotation.y
	return _hint


func physics_update(delta: float) -> void:
	var p := player
	time += delta
	_t += delta
	if phase == LANDED:
		_run_out(delta)
		return
	var input := p.get_move_input()
	# --- cut away (enter_vehicle in the air)
	if p.just_pressed("enter_vehicle") and phase == FLY and p.altitude_agl > 3.0:
		if p.chute != null:
			p.chute.release_canopy("cut", p.velocity + Vector3(0.0, 4.0, 0.0))
		p.change_state("air", {})
		return

	# --- toggles
	var want_brakes := 1.0 if (input.y < -0.3 or p.pressed("sprint")) else 0.0
	brakes = move_toward(brakes, want_brakes, BRAKE_RATE * delta)
	steer = move_toward(steer, clampf(input.x, -1.0, 1.0), BRAKE_RATE * delta)
	_fast = move_toward(_fast, 1.0 if input.y > 0.3 else 0.0, 2.0 * delta)
	if brakes > 0.4:
		reserve = maxf(reserve - delta * brakes / FLARE_RESERVE, 0.0)
	else:
		reserve = minf(reserve + delta / FLARE_RECHARGE, 1.0)

	# --- heading
	var turn := steer * TURN_RATE * lerpf(1.0, 0.7, brakes)
	p.rotation.y = wrapf(p.rotation.y - turn * delta, -PI, PI)
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3.FORWARD

	# --- targets of the wing
	var fwd_target := lerpf(FWD_SPEED, FWD_FAST, _fast)
	fwd_target = lerpf(fwd_target, FWD_BRAKE, brakes)
	var sink_target := lerpf(SINK, SINK_FAST, _fast)
	sink_target = lerpf(sink_target, SINK_FLARE, brakes * reserve) + brakes * (1.0 - reserve) * (SINK_STALL - SINK)
	sink_target += absf(steer) * TURN_SINK * (1.0 - brakes * 0.5)

	var v := p.velocity
	var h := Vector3(v.x, 0.0, v.z)
	if phase == OPEN:
		# inflation: drag grows with the canopy, braking the freefall towards the canopy's own speeds
		var k := clampf(_t / OPEN_TIME, 0.0, 1.0)
		var decel := OPEN_DECEL * k * k
		var vy := v.y - Player.GRAVITY * delta * (1.0 - k)
		vy = move_toward(vy, -sink_target, decel * delta)
		h = h.move_toward(fwd * fwd_target, (decel * 0.6 + H_ACCEL) * delta)
		v = Vector3(h.x, vy, h.z)
		if _t >= OPEN_TIME and absf(vy + sink_target) < 2.0:
			phase = FLY
	else:
		# the wing flies along its heading: steer the velocity onto it, settle the sink
		var along := h.dot(fwd)
		# the brakes bleed the speed off quickly (a flare stops the canopy within ~0.6 s)
		along = move_toward(along, fwd_target, H_ACCEL * (1.0 + brakes) * delta)
		var side := h - fwd * h.dot(fwd)
		side = side.move_toward(Vector3.ZERO, 8.0 * delta)
		h = fwd * along + side
		var vy2 := move_toward(v.y, -sink_target, V_ACCEL * delta)
		v = Vector3(h.x, vy2, h.z)
	airspeed = h.length()
	sink = -v.y
	p.velocity = v
	var h_before := h
	var vy_before := v.y
	p.move_body(delta, false)
	p.update_water()
	p.altitude_agl = p.measure_agl()

	if p.global_position.y < Player.VOID_Y:
		p.recover_from_void()
		return
	# --- water landing: swim, the canopy settles on the surface
	if p.water_depth > 0.6:
		landing = "water"
		landing_sink = -vy_before
		landing_speed = h_before.length()
		if p.chute != null:
			p.chute.release_canopy("water", h_before)
		p.change_state("swim", {"entry_speed": -vy_before})
		return
	# --- touchdown
	if p.grounded and vy_before <= 0.5:
		_touchdown(-vy_before, h_before)
		return
	# --- flew into a wall
	if p.is_on_wall():
		var into := 0.0
		for i in p.get_slide_collision_count():
			var n := p.get_slide_collision(i).get_normal()
			if absf(n.y) < 0.5:
				into = maxf(into, -h_before.dot(Vector3(n.x, 0.0, n.z).normalized()))
		if into > WALL_HIT_SPEED:
			landing = "wall"
			landing_speed = into
			landing_damage = 10.0 + (into - WALL_HIT_SPEED) * 6.0
			if p.chute != null:
				p.chute.release_canopy("land", Vector3.ZERO)
			p.apply_damage(Dmg.make(landing_damage, "fall", null, p.global_position, -fwd, {"no_ragdoll": true}))
			if not p.is_dead:
				p.ragdoll(-fwd * 120.0 + Vector3(0.0, -40.0, 0.0), 2.0)
			return

	# --- presentation, skill
	if phase == FLY and p.altitude_agl > 4.0:
		Skills.add_xp("flying", delta * FLY_XP)
	if p.chute != null:
		p.chute.set_attitude(steer * BANK_MAX * (1.0 - brakes * 0.4), brakes * FLARE_PITCH * (0.5 + 0.5 * reserve) - _fast * 0.12)
		p.chute.set_flap(clampf(0.35 + airspeed / FWD_FAST * 0.65, 0.0, 1.0))
	if p.animator != null:
		p.animator.flare = brakes
	p.set_anim_state("parachute")


func _touchdown(vsink: float, h: Vector3) -> void:
	var p := player
	landing_sink = vsink
	landing_speed = h.length()
	var fwd := h.normalized() if h.length_squared() > 0.01 else -p.global_basis.z
	if p.chute != null:
		p.chute.set_flap(0.0)
		p.chute.release_canopy("land", h)
	public_name = "on_foot"
	p.notify_state_changed("on_foot")
	if landing_sink <= GOOD_SINK and landing_speed <= GOOD_FWD:
		# good flare: run it out on the feet
		landing = "good"
		landing_damage = 0.0
		Skills.add_xp("flying", LAND_XP)
		Audio.play_at("jump_land", p.global_position, -6.0, 1.05, 30.0)
		p.emit_noise(5.0, "footstep")
		phase = LANDED
		_t = 0.0
		p.velocity = Vector3(h.x, 0.0, h.z)
		p.set_anim_state("locomotion", 0.25)
		return
	if landing_sink <= BAD_SINK and landing_speed <= BAD_FWD:
		landing = "stumble"
		landing_damage = 4.0 + maxf(landing_sink - GOOD_SINK, 0.0) * 5.0 + maxf(landing_speed - GOOD_FWD, 0.0) * 2.0
		Audio.play_at("jump_land", p.global_position, -2.0, 0.92, 35.0)
		Fx.dust(p.global_position, 1.0)
		p.apply_damage(Dmg.make(landing_damage, "fall", null, p.global_position, fwd, {"no_ragdoll": true}))
		if p.is_dead:
			return
		p.change_state("on_foot", {"land_lock": STUMBLE_TIME, "landed": landing_sink})
		if p.state_id == "on_foot" and p.state.has_method("stagger"):
			p.state.call("stagger", Vector3.ZERO, STUMBLE_TIME)
			p.play_hit_react(Vector2(0.0, -1.0), 1.3)
		return
	landing = "hard"
	landing_damage = 12.0 + maxf(landing_sink - BAD_SINK, 0.0) * 10.0 + maxf(landing_speed - BAD_FWD, 0.0) * 4.0
	Audio.play_at("body_fall", p.global_position, 0.0, 1.0, 40.0)
	Fx.dust(p.global_position, 1.6)
	p.shake_camera(0.45)
	p.apply_damage(Dmg.make(landing_damage, "fall", null, p.global_position, fwd, {"no_ragdoll": true}))
	if p.is_dead:
		return
	p.ragdoll(Vector3(h.x, 0.0, h.z) * 26.0 + Vector3(0.0, 30.0, 0.0), 1.6)


## Good landing: a few running steps that bleed off the speed, then normal control.
func _run_out(delta: float) -> void:
	var p := player
	var h := Vector3(p.velocity.x, 0.0, p.velocity.z)
	h = h.move_toward(Vector3.ZERO, RUN_OUT_DECEL * delta)
	p.velocity = Vector3(h.x, -1.0, h.z)
	p.move_body(delta, true)
	p.set_anim_state("locomotion" if h.length() > 0.6 else "idle")
	if _t >= RUN_OUT_TIME or h.length() < 0.5 or not p.grounded:
		p.change_state("on_foot", {})       # (on_foot itself falls into the air state off an edge)


func update_animator(a: HumanoidAnimator) -> void:
	if phase == LANDED:
		return
	a.aim_weight = 0.0
	a.aim_pitch = 0.0
	a.steer = steer
	a.flare = brakes
	a.lean = clampf(steer * 0.8, -1.0, 1.0)
