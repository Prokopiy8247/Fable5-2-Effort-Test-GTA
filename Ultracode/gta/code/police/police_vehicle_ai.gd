class_name PoliceVehicleAi
extends RefCounted
## Driving brain of ONE police vehicle (police_cruiser / swat_van). Plain state object: the police
## system's single manager loop calls tick() (15 Hz near the player, 6 Hz far), nothing here has its
## own _process. Implements the W2.1 `ai_controller` contract: the vehicle carries
## set_meta("ai_controller", <this object>) and release_vehicle(vehicle, reason).
##
## Modes (`mode`, get_mode_name()):
##   patrol    0 stars, ambient: random lane walk on the RoadGraph, obeys signals, no siren
##   pursuit   wanted + target known: lane route (A* on the RoadGraph) while far, direct predictive
##             pursuit when near with tactics: "chase" (close follow with lead), "pit" (line up
##             beside the rear wheel at medium speed, then steer into the quarter panel), "ram" (side
##             exposed, 3 stars+), "box" (low speed: units take front / left / right / rear slots)
##   search    wanted, contact lost: slow cruise to lane points inside Wanted.search_radius
##   deploy    stopping near a target on foot / a stopped vehicle -> the crew gets out
##   deployed  parked with the siren on while the crew works on foot; recalls the crew when the
##             player drives away (or the level clears) -> board
##   board     waiting for the crew to get back in; then the mode follows the wanted state again
##   leave     stand down: drive away; the system despawns the unit out of view
##   hold      no usable driver (crew dead / carjacked): brakes
## Shared: stuck recovery (reverse with opposite lock, give-up -> system relocates / despawns),
## obstacle rays (pedestrians -> brake, slow vehicles -> follow, blockers -> swerve), sightings for
## the seated crew (360 deg through the windows, recognition delay from Wanted).

enum Mode { PATROL, PURSUIT, SEARCH, DEPLOY, DEPLOYED, BOARD, LEAVE, HOLD }
const MODE_NAMES: Array[String] = ["patrol", "pursuit", "search", "deploy", "deployed", "board", "leave", "hold"]

const DIRECT_DIST := 60.0           ## direct approach to a target on foot inside this distance (clear line)
const DIRECT_CLOSE := 30.0          ## direct pursuit of a driving target inside this distance (clear line)
const FOOT_DIRECT := 20.0           ## off-road approach to a suspect on foot only for the last metres
const TRAIL_DIST := 140.0           ## follow the player's trail when he is closer than this
const TRAIL_JOIN := 18.0            ## ... and the car is this close to a trail point
const ROUTE_REPLAN := 3.5           ## seconds between route plans towards a moving target
const SIGHT_INTERVAL := 0.2
const SIGHT_RANGE := 72.0
const DEPLOY_FOOT_DIST := 34.0      ## stop and get out when the target on foot is this close
const DEPLOY_STOPPED_DIST := 22.0   ## ... or the target's vehicle stands still this close for STOPPED_TIME
const STOPPED_TIME := 1.2
const RECALL_DIST := 18.0           ## deployed crew re-boards when the player drives off beyond this
const BOARD_TIMEOUT := 14.0
const A_LAT_FAST := 6.8             ## lateral acceleration used in pursuit corners (m/s^2)
const A_LAT_CALM := 3.4
const B_FAST := 6.5                 ## braking used for speed planning
const B_CALM := 2.6
const STUCK_TIME := 1.6
const KTURN_ANGLE := 2.0            ## aim this far behind (rad) -> three-point turn
const HOT_SEARCH := 12.0           ## first seconds of a search: rush to the last known area
const REVERSE_TIME := 1.4
const CUT_TOLERANCE := 1.4          ## max corner cut (m) of the straight line to the steering aim point
const PERSON_BOX_WIDTH := 3.0       ## width of the swept box checked for people (car + margin)
const SWERVE := 2.2                 ## lateral offset of the aim point when swerving round a blocker
const LANE_CHANGE_COST := 12.0      ## route planning: metres a lane change at the start costs
const UTURN_COST := 45.0            ## ... and turning round on the spot (three-point turn)

var system: Node = null
var vehicle: RigidBody3D = null
var kind: String = "cruiser"        ## "cruiser" | "swat"
var crew: Array[Node3D] = []        ## officers of this car (seated or on foot nearby)
var ambient: bool = false           ## patrol unit at 0 stars (returns to patrol after an episode)
var standing_down: bool = false     ## the system sends this unit home
var mode: int = Mode.PATROL
var mode_t: float = 0.0
var slot: int = 0                   ## spread / box slot assigned by the system
var tactic: String = ""
var tactic_t: float = 0.0
var sees_target: bool = false
var seen_t: float = 0.0             ## continuous line of sight (recognition delay)
var unseen_t: float = 999.0
var last_seen_pos: Vector3 = Vector3.INF
var released: bool = false
var think_acc: float = 0.0          ## system scheduling
var dest: Vector3 = Vector3.INF
var stats := {"plans": 0, "recoveries": 0, "deploys": 0, "pits": 0, "rams": 0, "boxes": 0}

# route ------------------------------------------------------------------------------------------
var route := PackedVector3Array()
var route_cum := PackedFloat32Array()
var route_vmax := PackedFloat32Array()
var route_stop_s := PackedFloat32Array()   ## arc length of the stop lines along the route
var route_stop_lane := PackedInt32Array()  ## lane whose signal governs that stop
var route_i: int = 0
var route_s: float = 0.0
var route_final: bool = true               ## the route ends at the destination (slow down there)
var replan_t: float = 0.0
var _last_lane: int = -1

# driving state ----------------------------------------------------------------------------------
var throttle: float = 0.0
var steer: float = 0.0
var brake: float = 0.0
var handbrake: bool = false
var wheelbase: float = 2.8
var max_steer: float = deg_to_rad(34.0)
var grip: float = 1.1
var half_len: float = 2.4
var _stuck_t: float = 0.0
var _reverse_t: float = 0.0
var _reverse_steer: float = 0.0
var _reverse_age: float = 0.0
var _recoveries: Array[float] = []
var _flip_t: float = 0.0
var _avoid: float = 0.0                    ## lateral offset of the aim point (m, + = right)
var _avoid_t: float = 0.0
var _target_stopped_t: float = 0.0
var _sight_acc: float = 0.0
var _board_t: float = 0.0
var _driver_seated_t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _ray: PhysicsRayQueryParameters3D = null
var _ray_self: PhysicsRayQueryParameters3D = null
var _ray_tgt: PhysicsRayQueryParameters3D = null
var _ray_tgt_id: int = 0
var _person_q: PhysicsShapeQueryParameters3D = null
var _emergency_stop: bool = false          ## a person in the path, too close for gentle braking
var _person_wait_since: float = -1.0
var _dbg_off: String = ""                  ## debug: last "car -> route start" when the car was off its route
var _person_box := BoxShape3D.new()
var _clock: float = 0.0
var _hopeless: bool = false                ## the system relocates / despawns this unit (out of view)
var last_block: String = ""                ## debug: what the obstacle ray saw last
var _kturn_t: float = 0.0
var _slow_t: float = 0.0
var _was_hot: bool = false
var _kturn_dir: float = 1.0
var _clear_t: float = -10.0
var _clear_cached: bool = false
var _slot_t: float = -10.0
var _slot_ok: bool = true


func setup(p_system: Node, v: RigidBody3D, p_kind: String, p_crew: Array, is_ambient: bool) -> void:
	system = p_system
	vehicle = v
	kind = p_kind
	ambient = is_ambient
	crew.clear()
	for c: Variant in p_crew:
		if c is Node3D and is_instance_valid(c):
			crew.append(c as Node3D)
	_rng.seed = v.get_instance_id() ^ 0x5bd1e995
	think_acc = _rng.randf() * 0.06
	var wb: Variant = v.get("wheelbase")
	if (wb is float or wb is int) and float(wb) > 0.8:
		wheelbase = float(wb)
	var spec: Variant = v.get("spec")
	if spec is Object and spec != null:
		var ms: Variant = (spec as Object).get("max_steer_angle")
		if ms is float or ms is int:
			max_steer = deg_to_rad(clampf(float(ms), 15.0, 50.0))
		var gf: Variant = (spec as Object).get("grip_front")
		if gf is float or gf is int:
			grip = clampf(float(gf), 0.6, 1.8)
	var aabb: Variant = v.get("body_aabb")
	if aabb is AABB:
		half_len = maxf((aabb as AABB).size.z * 0.5, 1.5)
	mode = Mode.PATROL
	mode_t = 0.0


func get_mode_name() -> String:
	return MODE_NAMES[mode]


func is_valid() -> bool:
	return not released and vehicle != null and is_instance_valid(vehicle) and vehicle.is_inside_tree() \
			and not vehicle.is_queued_for_deletion()


func is_destroyed() -> bool:
	return vehicle == null or not is_instance_valid(vehicle) or bool(vehicle.get("destroyed"))


func get_position() -> Vector3:
	return vehicle.global_position if vehicle != null and is_instance_valid(vehicle) else Vector3.INF


## Living crew members (seated or not).
func living_crew() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in crew:
		if is_instance_valid(c) and not bool(c.get("is_dead")):
			out.append(c)
	return out


func seated_crew() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in crew:
		if is_instance_valid(c) and not bool(c.get("is_dead")) and c.get("current_vehicle") == vehicle:
			out.append(c)
	return out


## The officer in the driver seat (null when nobody of ours sits there).
func seated_driver() -> Node3D:
	if vehicle == null or not is_instance_valid(vehicle):
		return null
	var d: Variant = vehicle.get("driver")
	if d is Node3D and is_instance_valid(d) and crew.has(d) and not bool((d as Node3D).get("is_dead")):
		return d as Node3D
	return null


func remove_crew(npc: Node3D) -> void:
	crew.erase(npc)


# =================================================================================================
# W2.1 ai_controller contract
# =================================================================================================

## Stop controlling `v`. "carjacked" / "abandon" / "crash": the driver leaves beside the door as a
## real NPC (returned) and the other seated officers get out too; "despawn" / "destroyed": clean-up.
## Afterwards the vehicle has no ai_controller meta and driver == null.
func release_vehicle(v: Node3D, reason: String) -> Node3D:
	if v == null or not is_instance_valid(v) or v != vehicle:
		return null
	var out: Node3D = null
	released = true
	var drv := seated_driver()
	if reason in ["carjacked", "abandon", "crash"]:
		for c in seated_crew():
			if c.has_method("exit_vehicle"):
				c.call("exit_vehicle")
			_brain_event(c, "vehicle_released", {"vehicle": v, "reason": reason})
		out = drv
	elif system != null and is_instance_valid(system) and system.has_method("_free_officer"):
		# "despawn" / "destroyed": officers still seated must not stay behind in seats the vehicle
		# forgets (they would ride along invisibly inside somebody else's car)
		for c in seated_crew():
			system.call("_free_officer", c)
		drv = null
	if v.has_method("release_inputs"):
		v.call("release_inputs")
	if v.has_meta("ai_controller") and v.get_meta("ai_controller") == self:
		v.remove_meta("ai_controller")
	if v.get("driver") != null and v.get("driver") == drv and v.has_method("occupant_exit"):
		v.call("occupant_exit", 0)
	if system != null and is_instance_valid(system) and system.has_method("_on_unit_released"):
		system.call("_on_unit_released", self, reason)
	return out


# =================================================================================================
# tick (called by the police system)
# =================================================================================================

func tick(dt: float) -> void:
	if not is_valid():
		return
	_clock += dt
	mode_t += dt
	tactic_t += dt
	if _avoid_t > 0.0:
		_avoid_t -= dt
		if _avoid_t <= 0.0:
			_avoid = 0.0
	if bool(vehicle.get("destroyed")):
		return
	_sight(dt)
	if absf(_fwd_speed()) < 1.0:
		_slow_t += dt
	else:
		_slow_t = 0.0
	var drv := seated_driver()
	_update_mode(drv, dt)
	match mode:
		Mode.DEPLOY:
			_do_deploy()
		Mode.DEPLOYED:
			_do_deployed()
		Mode.BOARD:
			_do_board(dt, drv)
		Mode.HOLD:
			_hold_brake()
		_:
			if drv == null:
				_hold_brake()
				_no_driver()
				return
			if _flip_check(dt):
				return
			if _reverse_t > 0.0:
				_reverse_t -= dt
				_reverse_age += dt
				if _rear_blocked(vehicle.global_transform):
					_reverse_t = 0.0          # somebody / something right behind: do not back into it
					_hold_brake()
					return
				if _reverse_age > 0.7 and absf(_fwd_speed()) < 0.3:
					# wedged both ways: backing up does nothing either -> counts double towards
					# "hopeless" (the system replaces the unit out of view sooner)
					_reverse_t = 0.0
					_recoveries.append(_clock)
					if _recoveries.size() >= 4:
						_hopeless = true
					return
				_apply(-0.75, _reverse_steer, 0.0, false)
				return
			match mode:
				Mode.PATROL:
					_do_patrol(dt)
				Mode.PURSUIT:
					_do_pursuit(dt)
				Mode.SEARCH:
					_do_search(dt)
				Mode.LEAVE:
					_do_leave(dt)
			_stuck_check(dt)


func _set_mode(m: int) -> void:
	if m == mode:
		return
	mode = m
	mode_t = 0.0
	tactic = ""
	tactic_t = 0.0
	route.clear()
	replan_t = 0.0
	_avoid = 0.0
	match m:
		Mode.PATROL, Mode.LEAVE:
			_set_siren(false)
		Mode.PURSUIT, Mode.SEARCH, Mode.DEPLOY, Mode.DEPLOYED:
			_set_siren(true)


func _update_mode(drv: Node3D, dt: float) -> void:
	if mode == Mode.DEPLOY or mode == Mode.DEPLOYED or mode == Mode.BOARD:
		return
	if mode == Mode.HOLD:
		if drv != null:
			_set_mode(Mode.PATROL)
		else:
			_no_driver()
			return
	var want := _wanted_mode()
	if want != mode:
		_set_mode(want)
	if mode == Mode.PURSUIT and drv != null and _should_deploy(dt):
		_set_mode(Mode.DEPLOY)
		stats["deploys"] = int(stats["deploys"]) + 1


## Nobody of ours in the driver seat: crew on foot -> deployed (recalls them later); a passenger
## aboard -> slides over to the wheel; nobody left -> hold (the system abandons the car).
func _no_driver() -> void:
	if living_crew().is_empty():
		_set_mode(Mode.HOLD)
		return
	var seated := seated_crew()
	if seated.is_empty():
		_set_mode(Mode.DEPLOYED)
		return
	var c0: Node3D = seated[0]
	if _seat_taken(0):
		_set_mode(Mode.HOLD)
		return
	if c0.has_method("exit_vehicle"):
		c0.call("exit_vehicle")
	if c0.has_method("enter_vehicle"):
		c0.call("enter_vehicle", vehicle, 0, true)


func _wanted_mode() -> int:
	if standing_down or Wanted.level <= 0:
		return Mode.PATROL if ambient and not standing_down else Mode.LEAVE
	if Wanted.state == Wanted.State.PURSUIT or unseen_t < 3.0:
		return Mode.PURSUIT
	return Mode.SEARCH


func _should_deploy(dt: float) -> bool:
	if not Game.has_player() or bool(Game.player.get("is_dead")):
		return false
	var tpos := Game.get_player_position()
	var d := _flat(vehicle.global_position, tpos)
	var pv := Game.get_player_vehicle()
	if pv == null:
		_target_stopped_t = 0.0
		if bool(Game.player.get("is_swimming")):
			return false
		if d < DEPLOY_FOOT_DIST and (sees_target or d < 14.0 or Wanted.player_visible_to_police):
			return true
		# held up by people in the street close to him: quicker on foot than manoeuvring between them
		if d < 70.0 and _person_wait_since >= 0.0 and _clock - _person_wait_since > 0.6:
			return true
		# stopped near him (end of the road route, blocked, kerbs / bollards): go on foot
		return (d < 60.0 and _slow_t > 2.0) or (d < 100.0 and _slow_t > 4.5)
	var tspd := Game.get_player_velocity().length()
	if tspd < 1.5 and d < DEPLOY_STOPPED_DIST:
		_target_stopped_t += dt
	else:
		_target_stopped_t = 0.0
	if _target_stopped_t >= STOPPED_TIME:
		return true
	# stuck close to the target (boxed in, wedged): get out and go on foot
	return d < 16.0 and tspd < 3.0 and absf(_fwd_speed()) < 0.8 and mode_t > 4.0 and _stuck_t > 1.0


# =================================================================================================
# modes
# =================================================================================================

func _do_patrol(dt: float) -> void:
	if route.size() < 2 or route_s > _route_len() - 18.0:
		if not _plan_patrol():
			_hold_brake()
			return
	_follow_route(dt, true, 13.0)


func _do_pursuit(dt: float) -> void:
	if not Game.has_player():
		_hold_brake()
		return
	var known := sees_target or Wanted.player_visible_to_police
	var tpos := Game.get_player_position() if known else Wanted.last_known_position
	var tvel := Game.get_player_velocity() if known else Vector3.ZERO
	var d := _flat(vehicle.global_position, tpos)
	var pv := Game.get_player_vehicle()
	# close with a clear straight line: direct predictive pursuit + tactics (a suspect on foot is
	# approached along the road; the car only leaves it for the last metres)
	if known and d < (FOOT_DIRECT if pv == null else DIRECT_CLOSE) and _direct_clear(tpos):
		route.clear()
		_drive_direct(tpos, tvel, d, dt)
		return
	# behind a driving player: follow his trail (the road he actually took, corners included)
	if known and pv != null and d < TRAIL_DIST and _follow_trail(dt):
		route.clear()
		return
	tactic = ""
	replan_t -= dt
	if route.size() < 2 or replan_t <= 0.0 or (dest != Vector3.INF and _flat(dest, tpos) > 25.0):
		if _can_plan():
			replan_t = ROUTE_REPLAN + _rng.randf() * 0.8
			if not _plan_to(tpos):
				route.clear()
	if route.size() < 2:
		_drive_direct(tpos, tvel, d, dt)
		return
	_follow_route(dt, false, 45.0)


## True when nothing static stands between the car and the target at bumper height (re-checked
## at most 5 times per second).
func _direct_clear(tpos: Vector3) -> bool:
	if _clock - _clear_t < 0.2:
		return _clear_cached
	_clear_t = _clock
	var from := vehicle.global_position + Vector3.UP * 0.5
	var to := Vector3(tpos.x, from.y if absf(tpos.y - vehicle.global_position.y) < 3.0 else tpos.y + 0.5, tpos.z)
	_clear_cached = system != null and is_instance_valid(system) and bool(system.call("los_static", from, to))
	return _clear_cached


## Pure pursuit along the player's recent trail (police system breadcrumbs, one point per 2.5 m
## while he drives). False when the car is not near the trail.
func _follow_trail(dt: float) -> bool:
	var tr: PackedVector3Array = system.get("trail")
	var n := tr.size()
	if n < 3:
		return false
	var pos := vehicle.global_position
	var best_i := -1
	var best_d := TRAIL_JOIN * TRAIL_JOIN
	for i in range(n - 1, -1, -1):
		var dd := Vector2(tr[i].x - pos.x, tr[i].z - pos.z).length_squared()
		if dd < best_d:
			best_d = dd
			best_i = i
	if best_i < 0:
		return false
	if best_d > 16.0:
		# not on the trail yet: join only heading the same way with a clear line (no corner cutting
		# across a junction; the lane route handles turns properly)
		if best_i >= n - 1:
			return false
		var tdir := tr[best_i + 1] - tr[best_i]
		tdir.y = 0.0
		var cf := -vehicle.global_basis.z
		cf.y = 0.0
		if tdir.length() < 0.1 or cf.normalized().dot(tdir.normalized()) < 0.75:
			return false
		if not bool(system.call("los_static", pos + Vector3.UP * 0.5, tr[best_i] + Vector3.UP * 0.5)):
			return false
	# skip trail points that are already behind us
	var fwd := -vehicle.global_basis.z
	while best_i < n - 1 and (tr[best_i] - pos).dot(fwd) < 0.0:
		best_i += 1
	var xf := vehicle.global_transform
	var spd := _fwd_speed()
	var look := clampf(absf(spd) * 0.7 + 6.0, 7.0, 22.0)
	var pp := Game.get_player_position()
	var aim := _trail_point_at(tr, best_i, pos, look, pp)
	# shorter look-ahead in bends: the straight line to the aim point must not cut the corner (kerb
	# posts, lamp and signal poles on the inside of junctions wedged cruisers before)
	for _k in 3:
		if look <= 6.5 or _seg_dev(pos, aim, _trail_point_at(tr, best_i, pos, look * 0.5, pp)) <= CUT_TOLERANCE:
			break
		look *= 0.65
		aim = _trail_point_at(tr, best_i, pos, look, pp)
	# distance to the player along the trail
	var behind := _flat(pos, tr[best_i])
	for k in range(best_i + 1, n):
		behind += _flat(tr[k - 1], tr[k])
	behind += _flat(tr[n - 1], pp)
	var tspd := Game.get_player_velocity().length()
	var vt := maxf(tspd + clampf((behind - 10.0) * 0.75, -6.0, 18.0), 4.0)
	vt = minf(vt, _trail_curve_speed(tr, best_i))
	tactic = "trail"
	if _kturn(xf, aim, spd, dt):
		return true
	vt = minf(vt, _turn_speed(xf, aim, false))
	vt = _obstacles(xf, spd, vt, false, aim)
	if _avoid != 0.0:
		var side := xf.basis.x
		side.y = 0.0
		aim += side.normalized() * _avoid
	var st := _pursuit_steer(xf, aim, spd)
	_pedals(vt, spd, true)
	_apply(throttle, st, brake, false)
	return true


## Point `dist` metres along the trail, starting at the car (`pos`) via trail point `i0`; the player
## himself when the trail is shorter.
static func _trail_point_at(tr: PackedVector3Array, i0: int, pos: Vector3, dist: float, pp: Vector3) -> Vector3:
	var acc := _flat(pos, tr[i0])
	var prev := tr[i0]
	if acc >= dist:
		return prev
	for k in range(i0 + 1, tr.size()):
		var seg := _flat(prev, tr[k])
		if acc + seg >= dist and seg > 0.01:
			return prev.lerp(tr[k], (dist - acc) / seg)
		acc += seg
		prev = tr[k]
	return pp


## Planar distance of `m` from the segment a-b (how far a straight drive a -> b leaves the path
## through m).
static func _seg_dev(a: Vector3, b: Vector3, m: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var am := Vector2(m.x - a.x, m.z - a.z)
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return am.length()
	var t := clampf(am.dot(ab) / l2, 0.0, 1.0)
	return (am - ab * t).length()


func _trail_curve_speed(tr: PackedVector3Array, from_i: int) -> float:
	var best := INF
	var a_lat := A_LAT_FAST * _weather_grip()
	var dist := 0.0
	var last := mini(tr.size() - 2, from_i + 12)
	for k in range(maxi(from_i, 1), last + 1):
		var a := Vector2(tr[k].x - tr[k - 1].x, tr[k].z - tr[k - 1].z)
		var b := Vector2(tr[k + 1].x - tr[k].x, tr[k + 1].z - tr[k].z)
		var la := a.length()
		var lb := b.length()
		dist += la
		if la < 0.3 or lb < 0.3:
			continue
		var ang := absf(a.angle_to(b))
		if ang < 0.05:
			continue
		var kappa := ang / (0.5 * (la + lb))
		var vc := sqrt(a_lat / kappa)
		best = minf(best, sqrt(vc * vc + 2.0 * B_FAST * maxf(dist - 3.0, 0.0)))
	return maxf(best, 5.0) if best < INF else INF


func _do_search(dt: float) -> void:
	# just lost contact: rush to the last known area first, then comb the streets slowly
	var hot := float(Wanted.time_in_state) < HOT_SEARCH and mode_t < HOT_SEARCH
	replan_t -= dt
	if route.size() < 2 or route_s > _route_len() - 10.0 or replan_t <= 0.0 or (_was_hot and not hot):
		if _can_plan():
			replan_t = 22.0
			_was_hot = hot
			var p: Vector3 = Wanted.search_center
			if not hot and system != null and system.has_method("get_search_lane_point"):
				p = system.call("get_search_lane_point", self)
			if not _plan_to(p):
				route.clear()
	if route.size() < 2:
		_hold_brake()
		return
	_follow_route(dt, not hot, 24.0 if hot else 10.0, not hot)


func _do_leave(dt: float) -> void:
	if route.size() < 2 or route_s > _route_len() - 20.0:
		if not _plan_patrol():
			_hold_brake()
			return
	_follow_route(dt, true, 14.0)


func _do_deploy() -> void:
	var spd := absf(_fwd_speed())
	_apply(0.0, 0.0, 1.0, spd < 6.0)
	if spd > 1.2 and mode_t < 3.5:
		return
	for c in seated_crew():
		if c.has_method("exit_vehicle"):
			c.call("exit_vehicle")
		_brain_event(c, "deployed", {"vehicle": vehicle})
	vehicle.call("release_inputs")
	_set_mode(Mode.DEPLOYED)


func _do_deployed() -> void:
	# parked: the car brakes itself without a driver (VehicleBase); just decide when to recall
	var alive := living_crew()
	if alive.is_empty():
		_set_mode(Mode.HOLD)
		return
	if mode_t < 2.0:
		return
	var recall := false
	if standing_down or Wanted.level <= 0:
		recall = true
	elif Game.has_player():
		var pv := Game.get_player_vehicle()
		var d := _flat(vehicle.global_position, Game.get_player_position())
		if pv != null and pv != vehicle and Game.get_player_velocity().length() > 5.0 and d > RECALL_DIST:
			recall = true
		elif d > 80.0 and Wanted.state == Wanted.State.PURSUIT:
			recall = true
		elif Wanted.state == Wanted.State.SEARCH and mode_t > 30.0 and d > 40.0:
			recall = true
	if recall:
		_recall_crew()


func _recall_crew() -> void:
	var seat := 0
	var n := 0
	for c in living_crew():
		if c.get("current_vehicle") == vehicle:
			n += 1
			continue
		if _flat(c.global_position, vehicle.global_position) > 45.0:
			_unlink(c)
			continue
		var b: Variant = c.get("brain")
		if b is Node and is_instance_valid(b) and (b as Node).has_method("board"):
			while seat < 4 and _seat_taken(seat):
				seat += 1
			(b as Node).call("board", vehicle, seat)
			seat += 1
			n += 1
	if n == 0:
		_set_mode(Mode.HOLD)
		return
	_board_t = 0.0
	_driver_seated_t = 0.0
	_set_mode(Mode.BOARD)


func _do_board(dt: float, drv: Node3D) -> void:
	_hold_brake()
	_board_t += dt
	if drv != null:
		_driver_seated_t += dt
		var waiting := false
		for c in living_crew():
			if c.get("current_vehicle") != vehicle and _brain_bool(c, "is_boarding"):
				waiting = true
		if not waiting or _driver_seated_t > 6.0:
			for c in living_crew():
				if c.get("current_vehicle") != vehicle:
					_unlink(c)
			_set_mode(_wanted_mode())
		return
	if _board_t > BOARD_TIMEOUT:
		for c in living_crew():
			if c.get("current_vehicle") != vehicle:
				_unlink(c)
		if seated_crew().is_empty():
			_set_mode(Mode.HOLD)
		else:
			# a passenger got in but nobody drives: move to the driver seat
			var c0: Node3D = seated_crew()[0]
			if c0.has_method("exit_vehicle"):
				c0.call("exit_vehicle")
			if c0.has_method("enter_vehicle"):
				c0.call("enter_vehicle", vehicle, 0, true)
			_board_t = 0.0


func _seat_taken(seat: int) -> bool:
	if vehicle.has_method("get_occupant"):
		var o: Variant = vehicle.call("get_occupant", seat)
		return o != null and is_instance_valid(o)
	return false


func _unlink(c: Node3D) -> void:
	crew.erase(c)
	var b: Variant = c.get("brain")
	if b is Node and is_instance_valid(b) and (b as Node).has_method("unlink"):
		(b as Node).call("unlink")


# =================================================================================================
# direct pursuit + tactics
# =================================================================================================

func _drive_direct(tpos: Vector3, tvel: Vector3, d: float, dt: float) -> void:
	var xf := vehicle.global_transform
	var pos := xf.origin
	var spd := _fwd_speed()
	var pv := Game.get_player_vehicle()
	var aim := tpos
	var vt := 30.0
	var exclude_target := false
	if pv == null or not is_instance_valid(pv):
		# target on foot: drive up and stop short of him (deploy takes over)
		var to := tpos - pos
		to.y = 0.0
		if to.length() > 0.1:
			aim = tpos - to.normalized() * 7.0
		vt = clampf(sqrt(2.0 * B_FAST * maxf(d - 9.0, 0.0)), 0.0, 22.0)
		tactic = "approach"
	else:
		var tb := (pv as Node3D).global_basis
		var tf := -tb.z
		tf.y = 0.0
		tf = tf.normalized() if tf.length_squared() > 0.001 else Vector3.FORWARD
		var tr := Vector3(-tf.z, 0.0, tf.x)     # right of the target's heading
		var rel := pos - tpos
		rel.y = 0.0
		var along := rel.dot(tf)                 # > 0: we are ahead of the target
		var lateral := rel.dot(tr)               # > 0: we are on its right
		var tspd := Vector2(tvel.x, tvel.z).length()
		var lead := clampf(d / maxf(absf(spd), 10.0), 0.0, 1.4)
		var pred := tpos + Vector3(tvel.x, 0.0, tvel.z) * lead
		_choose_tactic(along, lateral, tspd, d, pos, tpos)
		match tactic:
			"pit":
				var sgn := signf(lateral) if absf(lateral) > 0.4 else (1.0 if slot % 2 == 0 else -1.0)
				if along < -2.6:
					# line up beside the rear wheel on our side
					aim = pred - tf * 1.6 + tr * sgn * 2.1
					vt = tspd + clampf(-along * 0.7, 2.0, 9.0)
				else:
					# alongside the rear quarter: steer into it
					aim = pred - tf * 1.4 - tr * sgn * 1.2
					vt = tspd + 3.5
				exclude_target = true
			"ram":
				aim = pred
				vt = 40.0
				exclude_target = true
			"box":
				var off := _box_offset()
				aim = tpos + tr * off.x + tf * off.y + Vector3(tvel.x, 0.0, tvel.z) * 0.6
				# a slot behind a wall / bollards / on the far side of a kerb post line is not
				# reachable: close in from behind instead (cruisers wedged on pavements before)
				if not _slot_reachable(tpos, aim):
					aim = tpos - tf * 6.5 + Vector3(tvel.x, 0.0, tvel.z) * 0.6
				var dd := _flat(pos, aim)
				vt = clampf(tspd + (dd - 1.5) * 0.9, 0.0, 14.0)
				exclude_target = true
			_:
				aim = pred
				vt = clampf(tspd + clampf((d - 8.0) * 0.9, -8.0, 16.0), 3.0, 46.0)
	if _kturn(xf, aim, spd, dt):
		return
	var st := _pursuit_steer(xf, aim, spd)
	if tactic != "ram" and tactic != "pit":
		vt = minf(vt, _turn_speed(xf, aim, false))
	vt = _obstacles(xf, spd, vt, exclude_target, aim)
	if _avoid != 0.0:
		var side := xf.basis.x
		side.y = 0.0
		st = _pursuit_steer(xf, aim + side.normalized() * _avoid, spd)
	_pedals(vt, spd, true)
	_apply(throttle, st, brake, handbrake)


func _choose_tactic(along: float, lateral: float, tspd: float, d: float, pos: Vector3, tpos: Vector3) -> void:
	var lvl := Wanted.level
	var want := "chase"
	if tspd < 6.0 and d < 24.0:
		want = "box"
	elif lvl >= 2 and tspd >= 7.0 and tspd <= 24.0 and along < 1.0 and along > -14.0 and absf(lateral) < 5.0 and d < 15.0:
		want = "pit"
	elif lvl >= 3 and tspd < 16.0 and d < 26.0 and d > 5.0:
		# ram when the target's side faces us (we come in roughly at right angles)
		var to := tpos - pos
		to.y = 0.0
		var my_f := -vehicle.global_basis.z
		my_f.y = 0.0
		if to.length() > 0.1 and my_f.length() > 0.1 and absf(along) < 4.5 and absf(lateral) > 4.0 \
				and my_f.normalized().dot(to.normalized()) > 0.8:
			want = "ram"
	if want != tactic:
		if tactic_t < 1.2 and tactic != "":
			return            # hysteresis
		tactic = want
		tactic_t = 0.0
		match want:
			"pit":
				stats["pits"] = int(stats["pits"]) + 1
			"ram":
				stats["rams"] = int(stats["rams"]) + 1
			"box":
				stats["boxes"] = int(stats["boxes"]) + 1


## Nothing static between the target and its box slot (re-checked at most 4 times per second).
func _slot_reachable(tpos: Vector3, slot: Vector3) -> bool:
	if _clock - _slot_t < 0.25:
		return _slot_ok
	_slot_t = _clock
	_slot_ok = system != null and is_instance_valid(system) and bool(system.call("los_static", tpos + Vector3.UP * 0.6, Vector3(slot.x, tpos.y + 0.6, slot.z)))
	return _slot_ok


## Box-in slot in the target frame: x = right, y = forward (metres).
func _box_offset() -> Vector2:
	match slot % 4:
		0:
			return Vector2(0.0, 6.5)      # in front
		1:
			return Vector2(-3.4, 0.5)     # left
		2:
			return Vector2(3.4, 0.5)      # right
	return Vector2(0.0, -6.5)             # behind


# =================================================================================================
# route following
# =================================================================================================

func _follow_route(dt: float, calm: bool, vcap: float, final_stop: bool = true) -> void:
	var xf := vehicle.global_transform
	var pos := xf.origin
	var spd := _fwd_speed()
	if not _advance_cursor(pos):
		stats["off_route"] = int(stats.get("off_route", 0)) + 1
		_dbg_off = "%s->%s" % [str(pos.round()), str(route[0].round()) if route.size() > 0 else "-"]
		route.clear()            # far off the route: plan again next tick
		_hold_brake()
		return
	var look := clampf(absf(spd) * 0.7 + 5.5, 6.5, 22.0)
	var aim := _route_point_at(route_s + look)
	for _k in 3:
		if look <= 6.5 or _seg_dev(pos, aim, _route_point_at(route_s + look * 0.5)) <= CUT_TOLERANCE:
			break
		look *= 0.65
		aim = _route_point_at(route_s + look)
	var vt := minf(vcap, _route_vmax_ahead(calm))
	vt = minf(vt, _curve_speed(spd, calm))
	vt = minf(vt, _signal_speed(calm))
	if final_stop and route_final:
		var left := _route_len() - route_s
		vt = minf(vt, sqrt(2.0 * (B_CALM if calm else B_FAST) * maxf(left - 3.0, 0.0)) + 1.0)
	if _kturn(xf, aim, spd, dt):
		return
	vt = minf(vt, _turn_speed(xf, aim, calm))
	vt = _obstacles(xf, spd, vt, false, aim)
	if _avoid != 0.0:
		var side := xf.basis.x
		side.y = 0.0
		aim += side.normalized() * _avoid
	var st := _pursuit_steer(xf, aim, spd)
	_pedals(vt, spd, not calm)
	_apply(throttle, st, brake, false)


func _route_len() -> float:
	return route_cum[route_cum.size() - 1] if route_cum.size() > 0 else 0.0


## Moves the cursor to the closest route point ahead. False when the car is far from the route.
func _advance_cursor(pos: Vector3) -> bool:
	var n := route.size()
	if n < 2:
		return false
	var best_d := INF
	var best_i := route_i
	var best_s := route_s
	var last := mini(route_i + 14, n - 2)
	for i in range(route_i, last + 1):
		var a := route[i]
		var b := route[i + 1]
		var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var l2 := ab.length_squared()
		var t := 0.0
		if l2 > 0.0001:
			t = clampf(Vector3(pos.x - a.x, 0.0, pos.z - a.z).dot(ab) / l2, 0.0, 1.0)
		var q := a + (b - a) * t
		var dd := Vector2(pos.x - q.x, pos.z - q.z).length_squared()
		if dd < best_d:
			best_d = dd
			best_i = i
			best_s = route_cum[i] + (route_cum[i + 1] - route_cum[i]) * t
	route_i = best_i
	route_s = maxf(best_s, route_s - 2.0)
	return best_d < 16.0 * 16.0


func _route_point_at(s: float) -> Vector3:
	var n := route.size()
	if s >= route_cum[n - 1]:
		return route[n - 1]
	var i := route_i
	while i < n - 2 and route_cum[i + 1] < s:
		i += 1
	var seg := route_cum[i + 1] - route_cum[i]
	var t := 0.0 if seg < 0.0001 else clampf((s - route_cum[i]) / seg, 0.0, 1.0)
	return route[i].lerp(route[i + 1], t)


func _route_vmax_ahead(calm: bool) -> float:
	var v := INF
	var n := route.size()
	var i := route_i
	while i < n and route_cum[i] < route_s + 25.0:
		v = minf(v, route_vmax[i])
		i += 1
	if v == INF:
		v = 14.0
	return v * (0.82 if calm else 1.9)


func _curve_speed(spd: float, calm: bool) -> float:
	var a_lat := (A_LAT_CALM if calm else A_LAT_FAST) * _weather_grip()
	var b := B_CALM if calm else B_FAST
	var step := 5.0
	var horizon := clampf(spd * spd / (2.0 * b) + 14.0, 20.0, 60.0)
	var n := int(horizon / step)
	var best := INF
	var prev := _route_point_at(route_s)
	var cur := _route_point_at(route_s + step)
	for k in range(1, n):
		var nxt := _route_point_at(route_s + step * float(k + 1))
		var a := Vector2(cur.x - prev.x, cur.z - prev.z)
		var c := Vector2(nxt.x - cur.x, nxt.z - cur.z)
		var la := a.length()
		var lc := c.length()
		if la > 0.05 and lc > 0.05:
			var ang := absf(a.angle_to(c))
			if ang > 0.03:
				var kappa := ang / (0.5 * (la + lc))
				var vc := sqrt(a_lat / kappa)
				var dd := maxf(step * float(k) - 3.0, 0.0)
				best = minf(best, sqrt(vc * vc + 2.0 * b * dd))
		prev = cur
		cur = nxt
	return maxf(best, 4.0)


## Calm driving stops at red / yellow lights; pursuits slow down through red junctions.
func _signal_speed(calm: bool) -> float:
	var roads: Object = _roads()
	if roads == null:
		return INF
	for k in route_stop_s.size():
		var ds := route_stop_s[k] - route_s
		if ds < -1.0:
			continue
		if ds > 55.0:
			break
		var st := int(roads.call("get_signal_state", route_stop_lane[k]))
		if st == 0:
			return INF
		var b := B_CALM if calm else B_FAST
		if calm:
			var spd := absf(_fwd_speed())
			if st == 1 and spd * spd / (2.0 * 4.5) > maxf(ds, 0.0) + 1.0:
				return INF        # too late to stop on yellow
			return sqrt(2.0 * b * maxf(ds - 1.2, 0.0))
		# emergency vehicles cross red at a careful speed (about 9 m/s at the line)
		if st == 2:
			return sqrt(81.0 + 2.0 * b * maxf(ds, 0.0))
		return INF
	return INF


# =================================================================================================
# route planning (RoadGraph)
# =================================================================================================

func _roads() -> Object:
	if system != null and is_instance_valid(system):
		var r: Variant = system.get("roads")
		if r is Object and r != null:
			return r as Object
	return null


func _can_plan() -> bool:
	if system != null and is_instance_valid(system) and system.has_method("take_plan_token"):
		return bool(system.call("take_plan_token"))
	return true


## [lane_id, offset] of the lane under the car whose travel direction matches our heading.
func _start_lane() -> Array:
	var roads := _roads()
	if roads == null:
		return []
	var pos := vehicle.global_position
	var near: Dictionary = roads.call("get_nearest_lane", pos, 40.0)
	if near.is_empty():
		return []
	var id := int(near["lane_id"])
	var off := float(near["offset"])
	var fwd := -vehicle.global_basis.z
	fwd.y = 0.0
	var lxf: Transform3D = roads.call("sample_lane", id, off)
	var ldir := -lxf.basis.z
	if ldir.dot(fwd) >= -0.2:
		return [id, off]
	var lanes: Array = roads.get("lanes")
	var segs: Array = roads.get("segments")
	var lane: Dictionary = lanes[id]
	var seg: Dictionary = segs[int(lane["segment_id"])]
	var others: PackedInt32Array = seg["lanes_back"] if int(lane["direction"]) == 1 else seg["lanes_fwd"]
	var best := -1
	var best_d := INF
	var best_off := 0.0
	for o in others:
		var r := _project_on_lane(lanes[o], pos)
		if r.y < best_d:
			best_d = r.y
			best = o
			best_off = r.x
	if best >= 0:
		return [best, best_off]
	return [id, off]


## Start options: the lane under the car (heading-matched) plus the other lanes of the same
## direction on that road segment (a lane change makes turns reachable that the current lane
## does not allow: 2 -> 1 lane junctions only turn right from the outer lane).
func _start_options() -> Array:
	var st := _start_lane()
	if st.is_empty():
		return []
	var out: Array = [[st[0], st[1], 0.0]]
	var roads := _roads()
	var lanes: Array = roads.get("lanes")
	var segs: Array = roads.get("segments")
	var lane: Dictionary = lanes[int(st[0])]
	var seg: Dictionary = segs[int(lane["segment_id"])]
	var same: PackedInt32Array = seg["lanes_fwd"] if int(lane["direction"]) == 1 else seg["lanes_back"]
	for o in same:
		if o == int(st[0]):
			continue
		var r := _project_on_lane(lanes[o], vehicle.global_position)
		if r.y < 8.0:
			out.append([o, r.x + 6.0, LANE_CHANGE_COST])      # merge a little further on
	# turning round (three-point turn) instead of a loop round the block / half the island: the
	# nearest lane of the other direction, at a price
	var back: PackedInt32Array = seg["lanes_back"] if int(lane["direction"]) == 1 else seg["lanes_fwd"]
	var best_b := -1
	var best_bd := INF
	var best_bo := 0.0
	for o in back:
		var r2 := _project_on_lane(lanes[o], vehicle.global_position)
		if r2.y < best_bd:
			best_bd = r2.y
			best_b = o
			best_bo = r2.x
	if best_b >= 0 and best_bd < 12.0:
		out.append([best_b, best_bo + 4.0, UTURN_COST])
	return out


## Vector2(offset along the lane, horizontal distance) of `pos` projected on a lane polyline.
static func _project_on_lane(lane: Dictionary, pos: Vector3) -> Vector2:
	var pts: PackedVector3Array = lane["points"]
	var cum: PackedFloat32Array = lane["cum"]
	var best_d := INF
	var best_s := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var l2 := ab.length_squared()
		var t := 0.0
		if l2 > 0.0001:
			t = clampf(Vector2(pos.x - a.x, pos.z - a.z).dot(ab) / l2, 0.0, 1.0)
		var qx := a.x + (b.x - a.x) * t
		var qz := a.z + (b.z - a.z) * t
		var dd := Vector2(pos.x - qx, pos.z - qz).length()
		if dd < best_d:
			best_d = dd
			best_s = cum[i] + (cum[i + 1] - cum[i]) * t
	return Vector2(best_s, best_d)


## Route along the road graph to `target` (A* over lanes). False when no route exists.
func _plan_to(target: Vector3) -> bool:
	var roads := _roads()
	if roads == null:
		return false
	var starts := _start_options()
	if starts.is_empty():
		return false
	var near: Dictionary = roads.call("get_nearest_lane", target, 60.0)
	if near.is_empty():
		return false
	# arrive on either side of the target's road: whichever lane gives the shorter route (the
	# nearest lane alone may force a loop round the block to enter it in its direction)
	var options: Array = [[int(near["lane_id"]), float(near["offset"])]]
	var lanes: Array = roads.get("lanes")
	var segs: Array = roads.get("segments")
	var nl: Dictionary = lanes[int(near["lane_id"])]
	var seg: Dictionary = segs[int(nl["segment_id"])]
	var others: PackedInt32Array = seg["lanes_back"] if int(nl["direction"]) == 1 else seg["lanes_fwd"]
	var best_od := INF
	for o in others:
		var pr := _project_on_lane(lanes[o], target)
		if pr.y < best_od:
			best_od = pr.y
			options.append([o, pr.x])
	if options.size() > 2:
		options = [options[0], options[options.size() - 1]]
	var best_ids := PackedInt32Array()
	var best_cost := INF
	var best_ob := 0.0
	var best_oa := 0.0
	var direct := _flat(vehicle.global_position, target)
	for k in starts.size():
		var a := int((starts[k] as Array)[0])
		var oa := float((starts[k] as Array)[1])
		for opt: Array in options:
			var b := int(opt[0])
			var ob := float(opt[1])
			var ids := PackedInt32Array()
			if a == b and ob >= oa - 1.0:
				ids.append(a)
			else:
				ids = roads.call("find_lane_route", a, b)
			if ids.is_empty():
				continue
			var cost := 0.0
			for i in ids.size():
				var l: Dictionary = lanes[ids[i]]
				var s0 := oa if i == 0 else 0.0
				var s1 := ob if i == ids.size() - 1 else float(l["length"])
				cost += maxf(s1 - s0, 0.0) + 8.0
			cost += float((starts[k] as Array)[2])   # lane change / turning round
			if cost < best_cost:
				best_cost = cost
				best_ids = ids
				best_ob = ob
				best_oa = oa
		# good enough from the lane we are on: skip the lane-change alternatives (A* is not free)
		if k == 0 and best_cost < direct * 1.5 + 60.0:
			break
	if best_ids.is_empty():
		return false
	stats["plans"] = int(stats["plans"]) + 1
	_build_route(best_ids, best_oa, best_ob, true)
	dest = target
	return route.size() >= 2


## Random lane walk of about 450 m (patrol, leave): prefers going straight, avoids dirt and dead ends.
func _plan_patrol() -> bool:
	var roads := _roads()
	if roads == null:
		return false
	var st := _start_lane()
	if st.is_empty():
		return false
	var lanes: Array = roads.get("lanes")
	var ids := PackedInt32Array([int(st[0])])
	var total := float((lanes[int(st[0])] as Dictionary)["length"]) - float(st[1])
	var cur := int(st[0])
	var guard := 0
	while total < 450.0 and guard < 24:
		guard += 1
		var nxt: PackedInt32Array = roads.call("get_next_lanes", cur)
		if nxt.is_empty():
			break
		var cur_dir := _lane_end_dir(lanes[cur])
		var best := -1
		var best_w := -1.0
		for id in nxt:
			var l: Dictionary = lanes[id]
			var w := 1.0
			var turn := cur_dir.dot(_lane_start_dir(l))
			if turn > 0.85:
				w = 1.8
			elif turn > -0.5:
				w = 0.8
			else:
				w = 0.05
			var k := str(l.get("kind", ""))
			if k == "dirt":
				w *= 0.03
			elif k == "alley":
				w *= 0.35
			if (roads.call("get_next_lanes", id) as PackedInt32Array).size() <= 1 and float(l["length"]) < 60.0:
				w *= 0.3
			if ambient and kind == "cruiser" and k == "arterial":
				w *= 1.2
			w *= _rng.randf_range(0.4, 1.0)
			if w > best_w:
				best_w = w
				best = id
		if best < 0:
			break
		ids.append(best)
		total += float((lanes[best] as Dictionary)["length"])
		cur = best
	var last_len := float((lanes[ids[ids.size() - 1]] as Dictionary)["length"])
	_build_route(ids, float(st[1]), last_len, false)
	dest = route[route.size() - 1] if route.size() > 0 else Vector3.INF
	return route.size() >= 2


static func _lane_end_dir(l: Dictionary) -> Vector2:
	var p: PackedVector3Array = l["points"]
	var n := p.size()
	var d := Vector2(p[n - 1].x - p[n - 2].x, p[n - 1].z - p[n - 2].z)
	return d.normalized() if d.length_squared() > 0.0001 else Vector2.UP


static func _lane_start_dir(l: Dictionary) -> Vector2:
	var p: PackedVector3Array = l["points"]
	var d := Vector2(p[1].x - p[0].x, p[1].z - p[0].z)
	return d.normalized() if d.length_squared() > 0.0001 else Vector2.UP


func _build_route(ids: PackedInt32Array, s_first: float, s_last: float, final: bool) -> void:
	var roads := _roads()
	route.clear()
	route_vmax.clear()
	route_stop_s.clear()
	route_stop_lane.clear()
	route_cum.clear()
	route_i = 0
	route_s = 0.0
	route_final = final
	var lanes: Array = roads.get("lanes")
	var acc := 0.0
	for i in ids.size():
		var id := ids[i]
		var lane: Dictionary = lanes[id]
		var vlim := float(lane.get("speed_limit", 14.0))
		if i > 0:
			var conn: PackedVector3Array = roads.call("get_connection", ids[i - 1], id)
			for p in conn:
				acc = _route_add(p, minf(vlim, 11.0), acc)
		var length := float(lane["length"])
		var s0 := clampf(s_first, 0.0, length) if i == 0 else 0.0
		var s1 := clampf(s_last, 0.0, length) if i == ids.size() - 1 else length
		if s1 < s0:
			s1 = s0
		var pts: PackedVector3Array = lane["points"]
		var cum: PackedFloat32Array = lane["cum"]
		acc = _route_add(_lane_point(pts, cum, s0), vlim, acc)
		for k in pts.size():
			if cum[k] > s0 + 0.2 and cum[k] < s1 - 0.2:
				acc = _route_add(pts[k], vlim, acc)
		acc = _route_add(_lane_point(pts, cum, s1), vlim, acc)
		if i < ids.size() - 1 and s1 >= length - 0.5:
			route_stop_s.append(acc)
			route_stop_lane.append(id)
	_last_lane = ids[ids.size() - 1] if ids.size() > 0 else -1


func _route_add(p: Vector3, vmax: float, acc: float) -> float:
	var n := route.size()
	if n > 0:
		var d := route[n - 1].distance_to(p)
		if d < 0.3:
			route_vmax[n - 1] = minf(route_vmax[n - 1], vmax)
			return acc
		acc += d
	route.append(p)
	route_vmax.append(vmax)
	route_cum.append(acc)
	return acc


static func _lane_point(pts: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Vector3:
	var n := pts.size()
	if s <= 0.0:
		return pts[0]
	for i in n - 1:
		if cum[i + 1] >= s:
			var seg := cum[i + 1] - cum[i]
			var t := 0.0 if seg < 0.0001 else (s - cum[i]) / seg
			return pts[i].lerp(pts[i + 1], t)
	return pts[n - 1]


# =================================================================================================
# steering, pedals, obstacles, recovery
# =================================================================================================

func _pursuit_steer(xf: Transform3D, tgt: Vector3, spd: float) -> float:
	var lp := xf.affine_inverse() * tgt
	var fwd := -lp.z + wheelbase * 0.5
	var side := lp.x
	var delta := 0.0
	if fwd < 0.5:
		delta = (1.0 if side >= 0.0 else -1.0) * max_steer
	else:
		delta = atan(2.0 * wheelbase * side / maxf(fwd * fwd + side * side, 0.01))
	var limit := max_steer
	var sp := absf(spd)
	if sp > 4.0:
		limit = minf(max_steer, atan(wheelbase * grip * _weather_grip() * 9.81 / (sp * sp)) + deg_to_rad(4.0))
	return clampf(delta / maxf(limit, 0.05), -1.0, 1.0)


func _pedals(vt: float, spd: float, aggressive: bool) -> void:
	var err := vt - spd
	handbrake = false
	if _emergency_stop:
		throttle = 0.0
		brake = 1.0
		return
	if vt < 0.3:
		throttle = 0.0
		brake = 1.0 if spd < 2.5 else clampf(0.35 + 0.1 * spd, 0.35, 1.0)
	elif err > 0.4:
		throttle = clampf(0.35 + 0.2 * err, 0.3, 1.0 if aggressive else 0.72)
		brake = 0.0
	elif err < -1.0:
		# brake about as hard as the speed planning assumes (B_FAST / B_CALM): the old 0.1 per m/s
		# gain arrived too gently and cruisers ran wide in tight junctions
		throttle = 0.0
		brake = clampf((0.15 + 0.16 * (-err)) if aggressive else (0.08 + 0.11 * (-err)), 0.0, 1.0)
	else:
		throttle = clampf(0.15 + 0.012 * vt + 0.15 * err, 0.0, 0.7)
		brake = 0.0


## One ray towards the aim point (+ two side rays when blocked). Returns the allowed speed and may
## set a swerve offset (_avoid). Pedestrians -> brake, slower cars -> follow / pass, stopped cars
## and close static obstacles -> swerve and slow down.
func _obstacles(xf: Transform3D, spd: float, vt: float, exclude_target: bool, aim: Vector3 = Vector3.INF) -> float:
	last_block = ""
	_emergency_stop = false
	if not vehicle.is_inside_tree() or spd < -0.5:
		return vt
	var space := vehicle.get_world_3d().direct_space_state
	_ray = _query(exclude_target)
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var from := xf.origin + fwd * (half_len - 0.2) + Vector3.UP * 0.75
	var dir := fwd
	if aim != Vector3.INF:
		var aim_s := aim + right * _avoid          # where the car really steers (swerve included)
		var to_aim := Vector3(aim_s.x - from.x, 0.0, aim_s.z - from.z)
		if to_aim.length() > 2.0 and to_aim.normalized().dot(fwd) > 0.2:
			dir = to_aim.normalized()
	var length := clampf(4.0 + absf(spd) * 1.25, 6.0, 34.0)
	# people anywhere in the swept path (the centre ray alone misses somebody standing at the
	# kerb beside the bumper line: a cruiser ran over a gang member and started a shoot-out)
	var pl := _person_speed(space, xf, spd, dir)
	if pl < 0.5 and absf(spd) < 1.0:
		# somebody stands right in front of the bumper and does not move (frozen pedestrian): wait a
		# moment, then back up a little and steer round him (never push through)
		if _person_wait_since < 0.0:
			_person_wait_since = _clock
		elif _clock - _person_wait_since > (1.2 if mode == Mode.PURSUIT else 2.5):
			_person_wait_since = -1.0
			_avoid_t = 0.0
			_pick_swerve(space, from, fwd, right, length)
			_avoid *= 1.4
			_avoid_t = 3.2
			if not _rear_blocked(xf):
				_reverse_t = 0.9
				_reverse_age = 0.0
				_reverse_steer = 0.0
	else:
		_person_wait_since = -1.0
	vt = minf(vt, pl)
	_ray = _query(exclude_target)                  # (_rear_blocked above may have switched it)
	_ray.from = from
	_ray.to = from + dir * length
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		return vt
	var col: Object = hit.get("collider")
	var hd := from.distance_to(hit["position"])
	var nrm: Vector3 = hit.get("normal", Vector3.UP)
	if absf(nrm.y) > 0.8:
		return vt                 # ground / ramp
	if col is Node and ((col as Node).is_in_group("npc") or (col as Node).is_in_group("player")):
		last_block = "person %.1f" % hd
		if (col as Node).is_in_group("police"):
			return minf(vt, maxf(hd - 3.0, 0.0) * 0.8)
		# pedestrians (and the player on foot): never run them over on purpose
		return minf(vt, sqrt(2.0 * 7.0 * maxf(hd - 3.5, 0.0)))
	if col is RigidBody3D and (col as Node).is_in_group("vehicle"):
		var ov := (col as RigidBody3D).linear_velocity
		var along := ov.dot(fwd)
		last_block = "vehicle %.1f v=%.1f" % [hd, along]
		if along > 2.0:
			# a slower car ahead: follow it, and try to pass if we are in a hurry
			var follow := along + maxf(hd - 6.0, 0.0) * 0.6
			if follow < vt - 3.0 and mode == Mode.PURSUIT:
				_pick_swerve(space, from, fwd, right, length)
			return minf(vt, maxf(follow, vt * 0.7 if _avoid != 0.0 else follow))
		_pick_swerve(space, from, fwd, right, length)
		if hd < 7.0:
			return minf(vt, 3.0)
		return minf(vt, maxf(hd * 0.7, 6.0))
	# static obstacle (building, wall, post): only a problem when it is close; the path bends away
	# from far ones by itself
	if hd > clampf(absf(spd) * 0.9, 6.0, 15.0):
		return vt
	last_block = "static %.1f %s" % [hd, (col as Node).name if col is Node else "?"]
	_pick_swerve(space, from, fwd, right, length)
	if hd < 5.0:
		return minf(vt, 3.0)
	return minf(vt, maxf(hd * 0.8, 5.0))


## Speed limit for the people (NPCs, the player on foot) standing in the box the car sweeps over the
## next stopping distance (car width + margin): brake to stop in front of them. INF when clear.
func _person_speed(space: PhysicsDirectSpaceState3D, xf: Transform3D, spd: float, dir: Vector3) -> float:
	if spd < -0.5:
		return INF
	var length := clampf(3.0 + spd * spd / 12.0 + spd * 0.35, 4.0, 32.0)
	if _person_q == null:
		_person_q = PhysicsShapeQueryParameters3D.new()
		_person_q.collision_mask = Layers.NPC | Layers.PLAYER
		_person_q.collide_with_areas = false
		_person_q.shape = _person_box
	_person_box.size = Vector3(PERSON_BOX_WIDTH, 1.6, length)
	var front := xf.origin + dir * half_len
	_person_q.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), front + dir * (length * 0.5) + Vector3.UP * 1.0)
	var hits := space.intersect_shape(_person_q, 6)
	var best := INF
	for h: Dictionary in hits:
		var c: Variant = h.get("collider")
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var along := ((c as Node3D).global_position - front).dot(dir)
		var lim := sqrt(2.0 * 6.0 * maxf(along - 3.5, 0.0))
		if lim < best:
			best = lim
			last_block = "person-box %.1f" % along
	# too fast for the remaining distance: full brakes (the pedal controller alone brakes gently)
	if spd > best + 0.5:
		_emergency_stop = true
	return best


## Three-point turn when the aim point lies far behind the car (passed the target, wrong way on a
## route): reverse with the opposite lock until the nose points roughly at the aim, then go on.
## True while it drives the car.
func _kturn(xf: Transform3D, aim: Vector3, spd: float, dt: float) -> bool:
	var lp := xf.affine_inverse() * aim
	var ang := atan2(lp.x, -lp.z)
	if _kturn_t > 0.0:
		_kturn_t -= dt
		if absf(ang) < 1.25 or spd < -7.0 or _rear_blocked(xf):
			_kturn_t = 0.0
			return false
		_apply(-0.8, -_kturn_dir, 0.0, false)
		return true
	if absf(ang) < KTURN_ANGLE or absf(spd) > 4.5 or Vector2(lp.x, lp.z).length() > 70.0:
		return false
	if _rear_blocked(xf):
		return false             # no room behind: full lock forward instead
	_kturn_dir = 1.0 if lp.x >= 0.0 else -1.0
	_kturn_t = 1.9
	_apply(-0.8, -_kturn_dir, 0.0, false)
	return true


func _rear_blocked(xf: Transform3D) -> bool:
	if not vehicle.is_inside_tree():
		return false
	var back := xf.basis.z
	back.y = 0.0
	back = back.normalized()
	var from := xf.origin + back * (half_len - 0.3) + Vector3.UP * 0.7
	_ray = _query(false)
	_ray.from = from
	_ray.to = from + back * 3.5
	return not vehicle.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


## Obstacle ray query excluding our own body (and the target's vehicle when asked). Built once per
## exclusion set: assigning `exclude` copies the array, so it is not done per tick.
func _query(exclude_target: bool) -> PhysicsRayQueryParameters3D:
	if _ray_self == null:
		var ex1: Array[RID] = [vehicle.get_rid()]
		_ray_self = _new_ray(ex1)
	if not exclude_target:
		return _ray_self
	var pv := Game.get_player_vehicle()
	if pv == null or not (pv is CollisionObject3D):
		return _ray_self
	var id := pv.get_instance_id()
	if _ray_tgt == null or id != _ray_tgt_id:
		var ex2: Array[RID] = [vehicle.get_rid(), (pv as CollisionObject3D).get_rid()]
		_ray_tgt = _new_ray(ex2)
		_ray_tgt_id = id
	return _ray_tgt


static func _new_ray(ex: Array[RID]) -> PhysicsRayQueryParameters3D:
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = Layers.VEHICLE | Layers.NPC | Layers.PLAYER | Layers.PROP | Layers.WORLD
	q.hit_back_faces = false
	q.exclude = ex
	return q


## Speed at which the car can still turn onto `aim` (pure-pursuit curvature 2 sin(a) / d).
func _turn_speed(xf: Transform3D, aim: Vector3, calm: bool) -> float:
	var lp := xf.affine_inverse() * aim
	var d := Vector2(lp.x, lp.z).length()
	if d < 0.5:
		return INF
	var ang := absf(atan2(lp.x, -lp.z))
	if ang < 0.25:
		return INF
	if ang > KTURN_ANGLE and d < 70.0:
		return 3.0
	var kappa := 2.0 * sin(minf(ang, PI * 0.5)) / d
	var a_lat := (A_LAT_CALM if calm else A_LAT_FAST) * _weather_grip()
	return maxf(sqrt(a_lat / maxf(kappa, 0.001)), 3.5)


func _pick_swerve(space: PhysicsDirectSpaceState3D, from: Vector3, fwd: Vector3, right: Vector3, length: float) -> void:
	if _avoid_t > 0.0:
		return
	var free_l := _side_free(space, from, (fwd - right * 0.45).normalized(), length * 0.8)
	var free_r := _side_free(space, from, (fwd + right * 0.45).normalized(), length * 0.8)
	# pass on the left (right-hand traffic: the right side is the kerb with its posts and bollards,
	# which the side rays easily miss) unless the left is clearly more blocked
	if free_l + 2.0 >= free_r:
		_avoid = -SWERVE
	else:
		_avoid = SWERVE
	_avoid_t = 1.3


func _side_free(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, length: float) -> float:
	_ray.from = from
	_ray.to = from + dir * length
	var h := space.intersect_ray(_ray)
	if h.is_empty():
		return length
	return from.distance_to(h["position"])


func _stuck_check(dt: float) -> void:
	var spd := absf(_fwd_speed())
	if throttle > 0.25 and spd < 0.8 and brake < 0.1:
		_stuck_t += dt
	else:
		_stuck_t = maxf(_stuck_t - dt * 2.0, 0.0)
	if _stuck_t < STUCK_TIME:
		return
	_stuck_t = 0.0
	_reverse_t = REVERSE_TIME + _rng.randf() * 0.5
	_reverse_age = 0.0
	_reverse_steer = -steer if absf(steer) > 0.2 else (1.0 if _rng.randf() < 0.5 else -1.0)
	stats["recoveries"] = int(stats["recoveries"]) + 1
	_recoveries.append(_clock)
	while not _recoveries.is_empty() and _clock - _recoveries[0] > 30.0:
		_recoveries.remove_at(0)
	if _recoveries.size() >= 4:
		_hopeless = true          # the system relocates / despawns us when nobody sees it
	route.clear()


func _flip_check(dt: float) -> bool:
	if vehicle.global_basis.y.y < 0.35:
		_flip_t += dt
		_hold_brake()
		if _flip_t > 7.0:
			_hopeless = true
		return true
	_flip_t = 0.0
	return false


func is_hopeless() -> bool:
	return _hopeless


func clear_hopeless() -> void:
	_hopeless = false
	_recoveries.clear()
	_flip_t = 0.0


func _hold_brake() -> void:
	_apply(0.0, 0.0, 1.0, absf(_fwd_speed()) < 3.0)


func _apply(t: float, s: float, b: float, hb: bool) -> void:
	throttle = t
	steer = s
	brake = b
	handbrake = hb
	if vehicle.has_method("set_inputs"):
		vehicle.call("set_inputs", t, s, b, hb)


func _set_siren(on: bool) -> void:
	if vehicle != null and is_instance_valid(vehicle) and vehicle.has_method("set_siren") and bool(vehicle.get("siren_on")) != on:
		vehicle.call("set_siren", on)


func _fwd_speed() -> float:
	if vehicle.has_method("get_forward_speed"):
		return float(vehicle.call("get_forward_speed"))
	return vehicle.linear_velocity.dot(-vehicle.global_basis.z)


func _weather_grip() -> float:
	if Weather.has_method("get_grip_multiplier"):
		return clampf(float(Weather.get_grip_multiplier()), 0.5, 1.2)
	return 1.0


# =================================================================================================
# sight (seated crew)
# =================================================================================================

func _sight(dt: float) -> void:
	_sight_acc += dt
	if _sight_acc < SIGHT_INTERVAL:
		return
	var step := _sight_acc
	_sight_acc = 0.0
	var p := Game.player
	var ok := false
	if p != null and is_instance_valid(p) and not bool(p.get("is_dead")) and not seated_crew().is_empty():
		var eye := vehicle.global_position + Vector3.UP * 1.3
		var tp: Vector3 = p.call("get_target_position") if p.has_method("get_target_position") else p.global_position + Vector3.UP
		var rng := SIGHT_RANGE
		if system != null and is_instance_valid(system):
			rng *= float(system.get("sight_factor"))
		if eye.distance_to(tp) <= rng and system != null and is_instance_valid(system):
			ok = bool(system.call("los", eye, tp, [vehicle, p, Game.get_player_vehicle()]))
	sees_target = ok
	if ok:
		seen_t += step
		unseen_t = 0.0
		last_seen_pos = Game.get_player_position()
		if seen_t >= float(Wanted.get_recognition_delay()):
			var obs: Node = seated_driver()
			if obs == null:
				obs = seated_crew()[0]
			system.call("report_sighting", obs, last_seen_pos)
	else:
		seen_t = 0.0
		unseen_t += step


# =================================================================================================
# helpers
# =================================================================================================

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _brain_event(npc: Node, ev: String, data: Dictionary) -> void:
	var b: Variant = npc.get("brain")
	if b is Node and is_instance_valid(b) and (b as Node).has_method("on_event"):
		(b as Node).call("on_event", npc, ev, data)


func _brain_bool(npc: Node, prop: String) -> bool:
	var b: Variant = npc.get("brain")
	if b is Node and is_instance_valid(b):
		return bool((b as Node).get(prop))
	return false


func get_debug_info() -> Dictionary:
	return {"kind": kind, "mode": get_mode_name(), "tactic": tactic, "ambient": ambient,
			"speed": _fwd_speed() if is_valid() else 0.0, "crew": living_crew().size(),
			"seated": seated_crew().size() if is_valid() else 0, "sees": sees_target,
			"route_pts": route.size(), "route_s": route_s, "block": last_block, "thr": throttle,
			"brk": brake, "steer": steer, "stats": stats, "off": _dbg_off,
			"r0": str(route[0].round()) if route.size() > 0 else "-"}
