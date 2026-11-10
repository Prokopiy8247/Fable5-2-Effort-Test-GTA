class_name PlayerStateCover
extends PlayerStateOnFoot
## Contextual cover (spec 10A "Cover system"). Entered with the `cover` key from the ground states
## when PlayerCover.probe() finds a wall, barrier, low object or vehicle body (Layers.WORLD |
## VEHICLE | PROP, no markers).
##
##   glide       the body runs (up to 3 m) to the stand point in front of the surface and turns its
##               back to it; low cover (top 0.85 - 1.45 m) = crouched, high cover = standing
##   move        left / right along the surface (camera-relative stick), stops EDGE_STOP before an
##               edge; the face is re-traced every tick (curved / angled walls, vehicles)
##   aim         low cover: rise over it; high cover near an edge (EDGE_NEAR): lean out PEEK_PAST
##               beyond the corner and face the crosshair; the camera moves to the open side.
##               Mid-wall in high cover the aim is held but the trigger stays up (nothing to shoot
##               round). Fire while aimed = normal weapon fire.
##   blind fire  fire without aim: the gun over the low cover / round the corner of high cover
##               (the body slides to the edge), hip spread + BLIND_SPREAD_DEG, no zoom
##   corner      at an edge, stick towards it + cover (or jump): swing round a compatible outside
##               corner (the end face must be ~0.9 m deep) onto the next face
##   leave       cover key again, pull away from the wall, sprint, jump (vault / mantle over the
##               cover through Player.try_traversal), enter a vehicle; automatically when the
##               surface disappears or the covering vehicle moves
##   damage      hits from the covered side: x DAMAGE_MULT_HIDDEN while hunkered, x DAMAGE_MULT_EXPOSED
##               while exposed (modify_damage)
## The camera reads get_camera_hint() (shoulder on the open side, pivot pushed out of the wall,
## vehicle / prop bodies added to its collision probe so it never clips into the cover).
## Animator: "cover_low" / "cover_high" + cover_side / cover_peek / cover_blind + the aim layer.
## EventBus.player_state_changed("cover") when entered.

const CoverScript := preload("res://gta/code/player/player_cover.gd")

enum Phase { GLIDE, COVER, SWING }
enum Peek { NONE, RISE, LEAN, IN_PLACE }

const GLIDE_SPEED := 5.5
const GLIDE_MAX_TIME := 1.0
const MOVE_SPEED_HIGH := 2.0
const MOVE_SPEED_LOW := 1.6
const EDGE_STOP := 0.18                 ## the body centre stops this far inside an edge
const EDGE_NEAR := 0.62                 ## within this of an edge the aim key leans out past it
const PEEK_PAST := 0.45                 ## the centre ends this far beyond the edge when leaning out
const PEEK_SPEED := 4.2
const SLIDE_GAIN := 14.0                ## 1/s: scripted slides (lean out, blind fire, back) close in exponentially
const RISE_TIME := 0.16
const BLIND_PAST := 0.12                ## high cover blind fire: the centre slides this far past the edge
const BLIND_SPREAD_DEG := 6.5           ## extra random cone on top of the weapon's hip spread
const BLIND_READY := 0.14               ## s before the first blind shot (the arm goes up / round)
const BLIND_HOLD := 0.45                ## s the blind pose stays after the trigger is released
const BLIND_SHOOT_HEIGHT := 1.55        ## low-cover blind fire: shots start at the standing eye height (Player.get_shoot_origin)
const PULL_AWAY_TIME := 0.18
const SWING_TIME := 0.5
const WALL_LOST_TICKS := 4
const VEHICLE_MOVE_SPEED := 1.2         ## m/s: a covering vehicle faster than this throws us off
const VEHICLE_MOVE_DIST := 0.35
const DAMAGE_MULT_HIDDEN := 0.3
const DAMAGE_MULT_EXPOSED := 0.8
const RECHECK_TIME := 0.15
const CAMERA_PIVOT_OUT := 0.3           ## camera pivot pushed this far out of the wall while hunkered
const SLIDE_GIVE_UP := 0.8              ## s: a scripted slide (back from a lean, out to blind fire) that is
                                        ## blocked (an NPC, a prop) ends where it is instead of locking the stick

var cover: CoverScript = null
var phase: int = Phase.GLIDE
var normal: Vector3 = Vector3.BACK      ## wall normal (out of the wall), horizontal
var low: bool = false                   ## low cover (crouched, rise to aim)
var cover_height: float = 1.0           ## top of the cover above the floor
var collider: Object = null
var cover_vehicle: Node3D = null        ## the vehicle we hide behind (or null)
var edge_neg: bool = false              ## at the edge towards -s / +s (movement stops)
var edge_pos: bool = false
var near_neg: bool = false              ## within EDGE_NEAR of that edge (peek / blind fire possible)
var near_pos: bool = false
var side: float = 1.0                   ## side the character looks along the wall (+1 = along s)
var peek: float = 0.0                   ## 0 hunkered .. 1 risen / leaned out (exposure)
var peek_kind: int = Peek.NONE
var peek_side: float = 1.0
var blind: float = 0.0                  ## 0..1 blind-fire pose
var blind_firing: bool = false
var leave_reason: String = ""           ## why the last cover ended (tests / debugging)

var _t: float = 0.0
var _anchor: Vector3 = Vector3.ZERO     ## stand point (glide target / where a peek returns to)
var _peek_target: Vector3 = Vector3.ZERO
var _returning: bool = false
var _slide_t: float = 0.0               ## how long the current scripted slide has been running
var _rise_t: float = 0.0
var _blind_t: float = 0.0
var _blind_hold: float = 0.0
var _blind_side: float = 1.0
var _blind_target: Vector3 = Vector3.INF
var _blind_flag: bool = false
var _pull_t: float = 0.0
var _lost: int = 0
var _recheck_t: float = 0.0
var _wall_dist: float = CoverScript.STAND_OFF
var _veh_start: Vector3 = Vector3.ZERO
var _stuck_t: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _sw_from: Vector3
var _sw_to: Vector3
var _sw_corner: Vector3
var _sw_n0: Vector3
var _sw_n1: Vector3
var _sw_data: Dictionary = {}
var _air_t: float = 0.0


func _init() -> void:
	public_name = "cover"


func setup(p: Player, state_id: String) -> void:
	super.setup(p, state_id)
	cover = CoverScript.new()
	cover.setup(p)


## Cover in front of the player right now (stick direction, else the camera direction), {} = none.
func find_cover() -> Dictionary:
	var p := player
	var mv := p.get_move_input()
	var pref := Vector3.ZERO
	if mv.length() > 0.3:
		pref = p.get_wish_dir(mv)
	else:
		var yaw := p.get_view_yaw()
		pref = Vector3(-sin(yaw), 0.0, -cos(yaw))
	return cover.probe(pref)


func enter(previous: String, args: Dictionary) -> void:
	super.enter(previous, {})
	var p := player
	var d: Dictionary = args.get("cover", {})
	if d.is_empty():
		d = find_cover()
	if d.is_empty():
		p.change_state("on_foot", {})
		return
	_apply(d)
	phase = Phase.GLIDE
	_t = 0.0
	_stuck_t = 0.0
	_last_pos = p.global_position
	_anchor = d["point"]
	peek = 0.0
	peek_kind = Peek.NONE
	blind = 0.0
	blind_firing = false
	_blind_hold = 0.0
	_blind_t = 0.0
	_pull_t = 0.0
	_lost = 0
	_returning = false
	leave_reason = ""
	p.in_cover = true
	p.is_sprinting = false
	p.set_aiming(false)
	p.release_trigger()
	# look along the wall towards the side the camera looks at
	var s := Vector3.UP.cross(normal)
	var yaw := p.get_view_yaw()
	var look := Vector3(-sin(yaw), 0.0, -cos(yaw))
	side = 1.0 if look.dot(s) >= 0.0 else -1.0


func exit(next: String) -> void:
	var p := player
	_set_blind_flag(false)
	p.in_cover = false
	p.aim_spread_extra_deg = 0.0
	p.set_collision_enabled(true)
	if p.is_crouching and p.can_stand():
		p.set_crouching(false)
	if peek_kind != Peek.NONE and not p.pressed("aim"):
		p.set_aiming(false)
	peek = 0.0
	peek_kind = Peek.NONE
	blind = 0.0
	blind_firing = false
	cover_vehicle = null
	collider = null
	if p.animator != null:
		p.animator.cover_peek = 0.0
		p.animator.cover_blind = 0.0
	super.exit(next)


func allows_weapons() -> bool:
	return phase != Phase.SWING and super.allows_weapons()


func allows_vehicle_entry() -> bool:
	return phase == Phase.COVER and super.allows_vehicle_entry()


func is_exposed() -> bool:
	return peek >= 0.5 or blind > 0.5


func _apply(d: Dictionary) -> void:
	normal = d["normal"]
	low = bool(d.get("low", false))
	cover_height = float(d.get("height", 1.0))
	collider = d.get("collider", null)
	var v: Variant = d.get("vehicle", null)
	cover_vehicle = v as Node3D if (v is Node3D and is_instance_valid(v)) else null
	if cover_vehicle != null:
		_veh_start = cover_vehicle.global_position


# =================================================================================================
# tick
# =================================================================================================

func physics_update(delta: float) -> void:
	var p := player
	_land_lock = maxf(_land_lock - delta, 0.0)
	if _land_lock <= 0.0:
		_staggering = false
	match phase:
		Phase.GLIDE:
			_glide(delta)
		Phase.SWING:
			_swing(delta)
		_:
			_in_cover(delta)
	if p.state != self:
		return
	# noise of the feet (quiet: crouched / sneaking along the wall)
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	if speed < 0.4:
		p.noise_radius = 0.0
	elif p.is_crouching or p.in_stealth or phase == Phase.COVER:
		p.noise_radius = p.get_stealth_noise_radius() if (p.is_crouching or p.in_stealth) else Player.NOISE_WALK * 0.7
	else:
		p.noise_radius = Player.NOISE_RUN
	if not p.has_animator_footsteps():
		_step_dist += speed * delta
		if _step_dist > 0.9:
			_step_dist = 0.0
			p.on_footstep(0, 0.3)


func _gravity_and_move(delta: float) -> bool:
	var p := player
	if p.grounded:
		p.velocity.y = minf(p.velocity.y, 0.0)
	else:
		p.velocity.y = maxf(p.velocity.y - Player.GRAVITY * delta, -Player.TERMINAL_SPEED)
	p.move_body(delta)
	if p.grounded:
		_air_t = 0.0
	else:
		_air_t += delta
		if _air_t > 0.2:
			leave_reason = "fell"
			p.change_state("air", {})
			return false
	if p.water_depth > Player.SWIM_ENTER_DEPTH:
		p.change_state("swim", {"entry_speed": 0.0})
		return false
	return true


func _glide(delta: float) -> void:
	var p := player
	_t += delta
	if p.just_pressed("cover") and _t > 0.1:
		_leave("cancel")
		return
	var to := _anchor - p.global_position
	to.y = 0.0
	var d := to.length()
	var turned := absf(angle_difference(p.rotation.y, _yaw_of(normal))) < 0.25
	if (d < 0.05 and turned) or _t > GLIDE_MAX_TIME:
		if d > 0.45:
			_leave("glide_blocked")
			return
		_begin_cover()
		return
	var v := Vector3.ZERO
	if d >= 0.05:
		v = to / d * minf(GLIDE_SPEED, d / maxf(delta, 0.001) * 0.9)
	p.velocity.x = v.x
	p.velocity.z = v.z
	if d > 0.8:
		p.turn_toward(atan2(-to.x, -to.z), 12.0, delta)
	else:
		p.turn_toward(_yaw_of(normal), 22.0, delta)
	if low and d < 1.2 and not p.is_crouching:
		p.set_crouching(true)
	elif not low and p.is_crouching and p.can_stand():
		p.set_crouching(false)
	if not _gravity_and_move(delta):
		return
	# blocked on the way (a prop, an NPC ...): give up
	var moved := Vector2(p.global_position.x - _last_pos.x, p.global_position.z - _last_pos.z).length()
	_last_pos = p.global_position
	if moved < GLIDE_SPEED * delta * 0.25 and d > 0.3 and v != Vector3.ZERO:
		_stuck_t += delta
		if _stuck_t > 0.25:
			_leave("glide_blocked")
			return
	else:
		_stuck_t = 0.0
	if d < 0.7:
		p.set_anim_state("cover_low" if low else "cover_high")
	elif p.is_crouching:
		p.set_anim_state("crouch")
	else:
		p.set_anim_state("locomotion")


func _begin_cover() -> void:
	var p := player
	phase = Phase.COVER
	_t = 0.0
	_recheck_t = 0.0
	_lost = 0
	if low:
		p.set_crouching(true)
	elif p.is_crouching and p.can_stand():
		p.set_crouching(false)
	p.set_anim_state("cover_low" if low else "cover_high")
	_update_edges()


func _in_cover(delta: float) -> void:
	var p := player
	_t += delta
	var input := p.get_move_input()
	if _land_lock > 0.0:
		input = Vector2.ZERO
	var mag := minf(input.length(), 1.0)
	var wish := p.get_wish_dir(input)
	var s := Vector3.UP.cross(normal)

	# --- stealth toggle (allowed in cover)
	if InputMap.has_action(&"stealth") and p.just_pressed(&"stealth"):
		p.set_stealth(not p.in_stealth)

	# --- the surface behind us
	var w := cover.wall_at(p.global_position, normal)
	if w.is_empty():
		_lost += 1
		if _lost >= WALL_LOST_TICKS and peek_kind != Peek.LEAN and _blind_target == Vector3.INF and not _returning:
			_leave("lost")
			return
	else:
		_lost = 0
		_wall_dist = float(w["distance"])
		var nn: Vector3 = w["normal"]
		if nn.dot(normal) > 0.5:
			normal = normal.slerp(nn, 0.35).normalized()
			normal.y = 0.0
			normal = normal.normalized()
			s = Vector3.UP.cross(normal)
	if cover_vehicle != null:
		if not is_instance_valid(cover_vehicle) or not cover_vehicle.is_inside_tree():
			_leave("vehicle_gone")
			return
		var vel := Vector3.ZERO
		if cover_vehicle is RigidBody3D:
			vel = (cover_vehicle as RigidBody3D).linear_velocity
		if vel.length() > VEHICLE_MOVE_SPEED or cover_vehicle.global_position.distance_to(_veh_start) > VEHICLE_MOVE_DIST:
			_leave("vehicle_moved")
			if p.state != self:
				p.velocity += normal * 1.5
				if p.state.has_method("stagger"):
					p.state.call("stagger", normal * 1.8, 0.35)
			return
	_recheck_t -= delta
	if _recheck_t <= 0.0 and peek_kind == Peek.NONE and _blind_target == Vector3.INF and not _returning:
		_recheck_t = RECHECK_TIME
		var cls := cover.classify(p.global_position, normal)
		if cls.is_empty():
			if w.is_empty():
				_leave("lost")
				return
		else:
			cover_height = float(cls["height"])
			var now_low := bool(cls["low"])
			if now_low != low:
				low = now_low
				if low:
					p.set_crouching(true)
				elif p.can_stand():
					p.set_crouching(false)
	_update_edges()

	# --- leaving / context keys
	var along := wish.dot(s)
	var toward := 0.0
	if mag > 0.4 and absf(along) > 0.5 * mag:
		toward = signf(along)
	var at_edge_toward := (toward > 0.0 and edge_pos) or (toward < 0.0 and edge_neg)
	if p.just_pressed("cover"):
		if at_edge_toward and _try_swing(toward):
			return
		_leave("key")
		return
	var aim_held := p.pressed("aim") and _land_lock <= 0.0
	if p.pressed("sprint") and mag > 0.5 and not aim_held:
		_leave("sprint")
		return
	if mag > 0.5 and wish.normalized().dot(normal) > 0.6 and not aim_held:
		_pull_t += delta
		if _pull_t >= PULL_AWAY_TIME:
			_leave("pull_away")
			return
	else:
		_pull_t = 0.0
	if p.just_pressed("jump") and p.grounded and _land_lock <= 0.0:
		if at_edge_toward and _try_swing(toward):
			return
		if p.try_traversal(-normal, false):
			return
	if p.process_vehicle_entry_input(delta, allows_vehicle_entry()):
		return

	# --- weapons: peek / rise, blind fire
	_combat(delta, aim_held, s)

	# --- movement along the surface
	var target := Vector3.ZERO
	var direct := false                     # scripted slides set the velocity (no overshoot)
	if _returning and peek_kind == Peek.NONE and _blind_target == Vector3.INF:
		_slide_t += delta
		if _slide_t > SLIDE_GIVE_UP:
			_returning = false              # blocked on the way back: stay here (review fix)
			_anchor = p.global_position
	else:
		_slide_t = 0.0
	if peek_kind == Peek.LEAN or (_returning and peek_kind == Peek.NONE):
		direct = true
		var goal := _peek_target if peek_kind == Peek.LEAN else _anchor
		var to := goal - p.global_position
		to.y = 0.0
		var dl := to.length()
		if dl > 0.01:
			target = to * minf(PEEK_SPEED / dl, SLIDE_GAIN)
		elif peek_kind == Peek.NONE:
			_returning = false
	elif _blind_target != Vector3.INF:
		direct = true
		var tb := _blind_target - p.global_position
		tb.y = 0.0
		var db := tb.length()
		if db > 0.01:
			target = tb * minf(PEEK_SPEED / db, SLIDE_GAIN)
	elif peek_kind == Peek.NONE and blind <= 0.05:
		var mv := along
		if (mv > 0.0 and edge_pos) or (mv < 0.0 and edge_neg):
			mv = 0.0
		if absf(mv) > 0.15:
			side = signf(mv)
		var sp := MOVE_SPEED_LOW if low else MOVE_SPEED_HIGH
		if p.is_walk_held() or mag < Player.WALK_INPUT_THRESHOLD:
			sp = minf(sp, Player.WALK_SPEED)
		target = s * clampf(mv, -1.0, 1.0) * sp
		if absf(mv) < 0.15:
			target = Vector3.ZERO
		# hold the stand-off distance from the face
		if not w.is_empty():
			target += normal * clampf((CoverScript.STAND_OFF - _wall_dist) * 8.0, -1.5, 1.5)
	if direct:
		p.velocity.x = target.x
		p.velocity.z = target.z
	else:
		var rate := Player.ACCEL_GROUND if target.length_squared() > 0.0064 else Player.DECEL_GROUND
		if _staggering and _land_lock > 0.0:
			rate = STAGGER_DECEL
		p.accelerate_planar(target, rate, delta)

	# --- facing: the back to the wall; the crosshair while exposed
	if (peek_kind == Peek.RISE or peek_kind == Peek.LEAN) and p.is_aiming:
		p.turn_toward(p.get_view_yaw(), Player.TURN_RATE_AIM, delta)
	else:
		p.turn_toward(_yaw_of(normal), 12.0, delta)

	if not _gravity_and_move(delta):
		return
	p.set_anim_state("cover_low" if low else "cover_high")


func _update_edges() -> void:
	var p := player
	var feet := p.global_position
	edge_pos = not cover.surface_continues(feet, normal, 1.0, EDGE_STOP)
	edge_neg = not cover.surface_continues(feet, normal, -1.0, EDGE_STOP)
	near_pos = edge_pos or not cover.surface_continues(feet, normal, 1.0, EDGE_NEAR)
	near_neg = edge_neg or not cover.surface_continues(feet, normal, -1.0, EDGE_NEAR)


## Side (+1 / -1 along s) the camera's crosshair points to, for ties between two edges.
func _view_side(s: Vector3) -> float:
	var yaw := player.get_view_yaw()
	var look := Vector3(-sin(yaw), 0.0, -cos(yaw))
	return 1.0 if look.dot(s) >= 0.0 else -1.0


func _edge_side(s: Vector3) -> float:
	if near_pos and near_neg:
		return _view_side(s)
	if near_pos:
		return 1.0
	if near_neg:
		return -1.0
	return 0.0


# =================================================================================================
# combat: peek / rise, blind fire
# =================================================================================================

func _combat(delta: float, aim_held: bool, s: Vector3) -> void:
	var p := player
	var ok := allows_weapons() and p.has_control()
	var want_peek := aim_held and ok
	if want_peek and peek_kind == Peek.NONE:
		_start_peek(s)
	elif not want_peek and peek_kind != Peek.NONE:
		_end_peek()
	p.set_aiming(want_peek)

	# exposure (animator cover_peek, trigger gate, damage)
	match peek_kind:
		Peek.RISE:
			if p.is_crouching and p.can_stand():
				p.set_crouching(false)
			if not p.is_crouching:
				_rise_t += delta
			peek = clampf(_rise_t / RISE_TIME, 0.0, 1.0)
		Peek.LEAN:
			var total := maxf(_anchor.distance_to(_peek_target), 0.01)
			var left := Vector2(_peek_target.x - p.global_position.x, _peek_target.z - p.global_position.z).length()
			peek = clampf(1.0 - left / total, 0.0, 1.0)
		_:
			peek = maxf(peek - delta / 0.2, 0.0)

	# blind fire: fire without aiming, over low cover / round the corner of high cover
	var fire_held := p.pressed("fire") and ok
	var blind_ok := fire_held and not aim_held and _blind_possible()
	if blind_ok:
		if _blind_hold <= 0.0:
			_start_blind(s)
		_blind_hold = BLIND_HOLD
		_blind_t += delta
	else:
		_blind_hold = maxf(_blind_hold - delta, 0.0)
		if _blind_hold <= 0.0 and _blind_t > 0.0:
			_end_blind()
	blind_firing = _blind_hold > 0.0
	blind = move_toward(blind, 1.0 if blind_firing else 0.0, delta / 0.12)
	p.aim_spread_extra_deg = BLIND_SPREAD_DEG if blind_firing else 0.0
	_set_blind_flag(blind_firing and low)

	# trigger gate: never into our own cover
	var blocked := false
	if peek_kind == Peek.RISE or peek_kind == Peek.LEAN:
		blocked = peek < 0.8
	elif peek_kind == Peek.IN_PLACE:
		blocked = true                      # mid-wall in high cover: nothing to shoot round
	elif fire_held:
		# (a blind slide that cannot reach its spot fires from where it got to after SLIDE_GIVE_UP)
		blocked = not blind_ok or _blind_t < BLIND_READY or (_blind_target != Vector3.INF and _blind_left() > 0.08 and _blind_t < SLIDE_GIVE_UP)
	p.process_fire_input(delta, blocked)
	p.process_weapon_select_input(true)


func _start_peek(s: Vector3) -> void:
	var p := player
	_set_blind_flag(false)
	if not _returning and _blind_target == Vector3.INF:
		_anchor = p.global_position
	_returning = false
	_blind_target = Vector3.INF
	_rise_t = 0.0
	if low:
		peek_kind = Peek.RISE
		if p.can_stand():
			p.set_crouching(false)
		return
	var sd := _edge_side(s)
	if sd != 0.0:
		var de := cover.edge_distance(p.global_position, normal, sd, EDGE_NEAR + 0.05)
		if de == INF:
			de = EDGE_NEAR
		var goal := _anchor + s * sd * (de + PEEK_PAST + (p.global_position - _anchor).dot(s * sd))
		goal.y = p.global_position.y
		peek_kind = Peek.LEAN
		peek_side = sd
		side = sd
		_peek_target = goal
		return
	peek_kind = Peek.IN_PLACE


func _end_peek() -> void:
	var p := player
	var was := peek_kind
	peek_kind = Peek.NONE
	_rise_t = 0.0
	if was == Peek.LEAN:
		_returning = true                   # slide back to the stand point behind the cover
	if low:
		p.set_crouching(true)


func _blind_possible() -> bool:
	var p := player
	if not p.is_armed() or p.has_melee_weapon():
		return false
	if low:
		return true
	return near_pos or near_neg


func _start_blind(s: Vector3) -> void:
	var p := player
	_blind_t = 0.0
	_blind_target = Vector3.INF
	if low:
		return
	var sd := _edge_side(s)
	if sd == 0.0:
		return
	_blind_side = sd
	side = sd
	if not _returning:
		_anchor = p.global_position
	_returning = false
	var de := cover.edge_distance(p.global_position, normal, sd, EDGE_NEAR + 0.05)
	if de == INF:
		de = EDGE_NEAR
	_blind_target = p.global_position + s * sd * (de + BLIND_PAST)
	_blind_target.y = p.global_position.y


func _blind_left() -> float:
	var p := player
	return Vector2(_blind_target.x - p.global_position.x, _blind_target.z - p.global_position.z).length()


func _end_blind() -> void:
	_blind_t = 0.0
	if _blind_target != Vector3.INF:
		_blind_target = Vector3.INF
		_returning = true


## Blind fire over low cover: the inventory shoots from the standing eye height while the body stays
## crouched - through the holder hook Player.get_shoot_origin (shoot_height_override). Wave 2 faked
## is_crouching = false for the inventory instead (the AI then saw a standing player, too).
func _set_blind_flag(on: bool) -> void:
	var p := player
	if on == _blind_flag:
		return
	if on:
		if not p.is_crouching:
			return
		_blind_flag = true
		p.shoot_height_override = BLIND_SHOOT_HEIGHT
	else:
		_blind_flag = false
		p.shoot_height_override = -1.0


# =================================================================================================
# corner swing
# =================================================================================================

func _try_swing(sd: float) -> bool:
	var p := player
	if peek_kind != Peek.NONE or blind > 0.05:
		return false
	var c := cover.find_corner(p.global_position, normal, sd)
	if c.is_empty():
		return false
	phase = Phase.SWING
	_t = 0.0
	_sw_from = p.global_position
	_sw_to = c["point"]
	_sw_corner = c["corner"]
	_sw_n0 = normal
	_sw_n1 = c["normal"]
	_sw_data = c
	p.velocity = Vector3.ZERO
	p.set_collision_enabled(false)
	return true


func _swing(delta: float) -> void:
	var p := player
	_t += delta
	var u := clampf(_t / SWING_TIME, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var a := _sw_from - _sw_corner
	var b := _sw_to - _sw_corner
	a.y = 0.0
	b.y = 0.0
	var ang := atan2(a.cross(b).y, a.dot(b))
	var r := lerpf(a.length(), b.length(), e)
	var dir := a.normalized().rotated(Vector3.UP, ang * e) if a.length_squared() > 0.0001 else b.normalized()
	var pos := _sw_corner + dir * r
	pos.y = lerpf(_sw_from.y, _sw_to.y, e)
	var prev := p.global_position
	p.global_position = pos
	p.velocity = (pos - prev) / maxf(delta, 0.001)
	p.rotation.y = lerp_angle(_yaw_of(_sw_n0), _yaw_of(_sw_n1), e)
	p.set_anim_state("cover_low" if low else "cover_high")
	if u >= 1.0:
		p.velocity = Vector3.ZERO
		p.set_collision_enabled(true)
		_apply(_sw_data)
		_anchor = _sw_to
		# the corner we came round is now on this side of the new face
		var s2 := Vector3.UP.cross(normal)
		side = 1.0 if (_sw_corner - _sw_to).dot(s2) >= 0.0 else -1.0
		phase = Phase.COVER
		_t = 0.0
		_update_edges()


# =================================================================================================
# leaving
# =================================================================================================

func _leave(reason: String) -> void:
	leave_reason = reason
	player.change_state("on_foot", {})


static func _yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


# =================================================================================================
# damage, camera, animation hooks
# =================================================================================================

func modify_damage(info: Dictionary, amount: float) -> float:
	if phase != Phase.COVER:
		return amount
	var type := str(info.get("type", ""))
	if type != "bullet" and type != "explosion" and type != "fire":
		return amount
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	if dir.length_squared() < 0.0001:
		var pos: Vector3 = info.get("position", Vector3.ZERO)
		if pos == Vector3.ZERO:
			return amount
		dir = player.global_position - pos
	dir.y = 0.0
	if dir.length_squared() < 0.0001 or dir.normalized().dot(normal) < 0.25:
		return amount                       # from the open side: no protection
	info["cover"] = true
	var m := DAMAGE_MULT_EXPOSED if is_exposed() else DAMAGE_MULT_HIDDEN
	if type == "explosion":
		m = maxf(m, 0.5)
	return amount * m


func get_camera_hint() -> Dictionary:
	var p := player
	if phase == Phase.GLIDE:
		return NO_HINT
	var s := Vector3.UP.cross(normal)
	var open := side
	if peek_kind == Peek.LEAN:
		open = peek_side
	elif _blind_target != Vector3.INF:
		open = _blind_side
	else:
		var es := _edge_side(s)
		if es != 0.0:
			open = es
	var yaw := p.get_view_yaw()
	var cam_right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var sgn := 1.0 if (s * open).dot(cam_right) >= 0.0 else -1.0
	var aiming := p.is_aiming
	var hint := {"mask": Layers.VEHICLE | Layers.PROP}
	if aiming:
		hint["side"] = PlayerCamera.AIM_SIDE * sgn
		hint["height"] = PlayerCamera.AIM_HEIGHT if (not low or peek_kind == Peek.RISE) else 1.3
		hint["distance"] = PlayerCamera.AIM_DISTANCE
	else:
		hint["side"] = (PlayerCamera.THIRD_SIDE + 0.16) * sgn
		hint["height"] = 1.38 if low else 1.62
		hint["distance"] = 2.9
	hint["pivot_offset"] = normal * CAMERA_PIVOT_OUT * (1.0 - peek)
	return hint


func update_animator(a: HumanoidAnimator) -> void:
	var p := player
	var s := Vector3.UP.cross(normal)
	var look_side := side
	if peek_kind == Peek.LEAN:
		look_side = peek_side
	elif _blind_target != Vector3.INF:
		look_side = _blind_side
	elif phase == Phase.COVER:
		var es := _edge_side(s)
		if es != 0.0 and absf(Vector2(p.velocity.x, p.velocity.z).length()) < 0.3:
			look_side = es
	# s is the character's LEFT (it faces the wall normal): animator side + = its right
	a.cover_side = -look_side
	a.cover_peek = peek
	a.cover_blind = blind
	a.cover_height = cover_height
	if peek_kind == Peek.RISE or peek_kind == Peek.LEAN:
		a.aim_weight = peek
		a.aim_pitch = p.get_view_pitch()
		a.aim_yaw = 0.0
	elif blind > 0.0:
		a.aim_weight = 0.0
		# the gun points along the crosshair: yaw relative to the body (+ = left)
		var body_yaw := p.global_rotation.y
		a.aim_yaw = angle_difference(body_yaw, p.get_view_yaw())
		a.aim_pitch = p.get_view_pitch()
	else:
		a.aim_weight = 0.0
		a.aim_yaw = 0.0
		a.aim_pitch = 0.0
