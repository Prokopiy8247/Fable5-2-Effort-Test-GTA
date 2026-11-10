class_name PlayerStateFreefall
extends PlayerState
## Skydiving freefall (spec 29A, docs/PLAYER.md section 14). Entered from the air state when the drop
## below a falling player is more than Player.FREEFALL_MIN_AGL, or when the player leaves a vehicle /
## aircraft higher than Player.BAIL_FREEFALL_AGL (enter_vehicle key while flying).
##
##   steer     move_left / move_right turn the body; move_forward = head-down dive (faster, tracks
##             forward), move_back = flat arch (slower); the camera swings in behind
##   deploy    jump (only with Player.has_parachute) -> PlayerStateParachute. There is NO automatic
##             opening: without deploying the impact is lethal (air-state fall damage formula)
##   water     -> swim (big splash; harm above WATER_HARM_SPEED)
## Without a parachute the same physics run with the flailing "fall" pose and public name "falling"
## (the HUD altimeter only shows for "freefall" / "parachute").

const TERMINAL := 46.0              ## m/s, belly to earth
const TERMINAL_DIVE := 58.0         ## head-down dive (move_forward)
const TERMINAL_ARCH := 38.0         ## flat arch (move_back)
const TRACK_SPEED := 17.0           ## horizontal speed of a full forward track
const TRACK_ACCEL := 5.0            ## m/s^2 towards the track speed
const AIR_DRAG := 0.55              ## 1/s decay of horizontal speed beyond the track (inherited aircraft speed)
const TURN_RATE := 1.8              ## rad/s at full stick
const DEPLOY_DELAY := 0.12          ## s after entering before the canopy may open (an earlier press is kept)
const WATER_HARM_SPEED := 30.0      ## entering water faster than this hurts
const WATER_HARM_PER_MS := 3.0
const WALL_HIT_SPEED := 9.0         ## horizontal speed into a wall that knocks the skydiver out of control
const VEHICLE_GRACE := 1.5          ## s without collision against the vehicle that was just left
const FLY_XP := 0.004               ## flying skill per second of controlled freefall
const ANIM_DIVE_PITCH := 0.45       ## animator body pitch for a full dive / arch

var time: float = 0.0
var has_chute: bool = false
var exit_vehicle: Node3D = null      ## vehicle the player bailed out of (collision exception)

var _input: Vector2 = Vector2.ZERO
var _pitch_anim: float = 0.0
var _grace_t: float = 0.0
var _deploy_queued: bool = false
var _hint: Dictionary = {"side": 0.0, "height": 1.0, "distance": 5.2, "follow_yaw": 0.0, "follow_pitch": -0.42,
		"rigid": true, "fov_add": 9.0, "mask": 0}


func _init() -> void:
	public_name = "freefall"


func enter(_previous: String, args: Dictionary) -> void:
	var p := player
	time = 0.0
	has_chute = p.has_parachute
	public_name = "freefall" if has_chute else "falling"
	p.is_sprinting = false
	p.noise_radius = 0.0
	p.set_aiming(false)
	p.release_trigger()
	if p.is_crouching:
		p.set_crouching(false, true)
	p.set_collision_enabled(true)
	p.is_swimming = false
	p.is_underwater = false
	_input = Vector2.ZERO
	_pitch_anim = 0.0
	_deploy_queued = false
	exit_vehicle = args.get("from_vehicle", null) as Node3D
	_grace_t = 0.0
	if exit_vehicle != null and is_instance_valid(exit_vehicle) and exit_vehicle is PhysicsBody3D:
		p.add_collision_exception_with(exit_vehicle)
		_grace_t = VEHICLE_GRACE
	p.set_anim_state("freefall" if has_chute else "fall", 0.3)
	p.altitude_agl = p.measure_agl()
	if p.chute != null:
		p.chute.set_wind(0.3)
	if p.interaction != null:
		p.interaction.clear()


func exit(_next: String) -> void:
	var p := player
	_end_grace()
	if p.chute != null:
		p.chute.set_wind(0.0)
	p.anim_dive_pitch = 0.0


func _end_grace() -> void:
	if exit_vehicle != null and is_instance_valid(exit_vehicle) and exit_vehicle is PhysicsBody3D:
		player.remove_collision_exception_with(exit_vehicle)
	exit_vehicle = null
	_grace_t = 0.0


func allows_weapons() -> bool:
	return false


func get_camera_hint() -> Dictionary:
	_hint["follow_yaw"] = player.rotation.y
	return _hint


func physics_update(delta: float) -> void:
	var p := player
	time += delta
	if _grace_t > 0.0:
		_grace_t -= delta
		if _grace_t <= 0.0:
			_end_grace()
	var input := p.get_move_input()
	_input = _input.lerp(input, 1.0 - exp(-6.0 * delta))

	# --- deploy (no auto-deploy: the jump key, and only with a pack)
	if has_chute and p.just_pressed("jump"):
		_deploy_queued = true
	if _deploy_queued and time > DEPLOY_DELAY and p.has_parachute and p.states.has("parachute"):
		p.change_state("parachute", {"deploy": true})
		return

	# --- heading: the stick turns the body (camera independent, the camera swings in behind)
	p.rotation.y = wrapf(p.rotation.y - _input.x * TURN_RATE * delta, -PI, PI)
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3.FORWARD

	# --- vertical: gravity against a quadratic drag towards the posture's terminal speed
	var dive := maxf(_input.y, 0.0)
	var arch := maxf(-_input.y, 0.0)
	var term := TERMINAL
	if dive > 0.0:
		term = lerpf(TERMINAL, TERMINAL_DIVE, dive)
	elif arch > 0.0:
		term = lerpf(TERMINAL, TERMINAL_ARCH, arch)
	var vy := p.velocity.y - Player.GRAVITY * delta
	if vy < 0.0:
		vy += Player.GRAVITY * (vy * vy) / (term * term) * delta
		vy = maxf(vy, -term * 1.25)
	# --- horizontal: inherited speed bleeds off, a forward dive tracks
	var h := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var track := fwd * TRACK_SPEED * dive
	h = track + (h - track) * exp(-AIR_DRAG * delta)
	h = h.move_toward(track, TRACK_ACCEL * delta * (0.3 if h.length() > TRACK_SPEED else 1.0))
	p.velocity = Vector3(h.x, vy, h.z)
	var vy_before := vy
	var h_before := h.length()
	p.move_body(delta, false)
	p.update_water()
	p.altitude_agl = p.measure_agl()

	if p.global_position.y < Player.VOID_Y:
		p.recover_from_void()
		return
	# --- water
	if p.water_depth > 0.6:
		var speed := Vector3(h.x, vy_before, h.z).length()
		var harm := (speed - WATER_HARM_SPEED) * WATER_HARM_PER_MS
		if harm > 0.0:
			p.apply_damage(Dmg.make(harm, "fall", null, p.global_position, Vector3.DOWN, {"no_ragdoll": true}))
			if p.is_dead:
				return
		p.change_state("swim", {"entry_speed": -vy_before})
		return
	# --- ground: the air state's fall damage (lethal from ~26 m/s)
	if p.grounded and vy_before <= 0.5:
		_impact(-vy_before)
		return
	# --- slammed into a wall / roof edge at speed
	if p.is_on_wall() and h_before > WALL_HIT_SPEED:
		var dmg := (h_before - WALL_HIT_SPEED) * Player.FALL_DAMAGE_PER_MS * 0.8
		p.apply_damage(Dmg.make(dmg, "fall", null, p.global_position, -fwd, {"no_ragdoll": true}))
		if not p.is_dead:
			p.ragdoll(Vector3(h.x, vy_before, h.z) * 20.0, 2.0)
		return

	# --- skill + presentation
	if has_chute and p.altitude_agl > 8.0:
		Skills.add_xp("flying", delta * FLY_XP)
	if p.chute != null:
		p.chute.set_wind(clampf(-vy_before / TERMINAL, 0.15, 1.0))
	_pitch_anim = lerpf(_pitch_anim, (-_input.y) * ANIM_DIVE_PITCH, 1.0 - exp(-5.0 * delta))
	p.set_anim_state("freefall" if has_chute else "fall")


func _impact(speed: float) -> void:
	var p := player
	Fx.dust(p.global_position, 2.0)
	Audio.play_at("body_fall", p.global_position, 0.0, 0.9, 50.0)
	p.shake_camera(0.7)
	if speed > Player.FALL_SAFE_SPEED:
		var dmg := (speed - Player.FALL_SAFE_SPEED) * Player.FALL_DAMAGE_PER_MS
		p.apply_damage(Dmg.make(dmg, "fall", null, p.global_position, Vector3.DOWN))
		if p.is_dead:
			return
	if speed > Player.RAGDOLL_LAND_SPEED:
		p.ragdoll(Vector3(p.velocity.x, 0.0, p.velocity.z) * 30.0, 1.8)
		return
	p.change_state("on_foot", {"land_lock": 0.4, "landed": speed})


func update_animator(a: HumanoidAnimator) -> void:
	# body pitch of the freefall pose (aim_pitch: + = arch / head up, - = head-down dive), roll into turns
	a.aim_pitch = _pitch_anim
	a.aim_weight = 0.0
	a.lean = clampf(_input.x * 0.9, -1.0, 1.0)
