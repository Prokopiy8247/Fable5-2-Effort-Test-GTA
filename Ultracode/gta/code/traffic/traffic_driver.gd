class_name TrafficDriver
extends RefCounted
## Plain per-vehicle state of one AI traffic driver (no node, no _process): the lane cursor on the
## RoadGraph (lane -> junction connection -> next lane), the personality, the reaction / recovery
## timers and the last decision. TrafficSystem owns every instance and runs all decisions in one
## manager loop; this class only knows how to follow its own path.

enum Block { NONE, WAIT, QUEUE, BLOCKED }

var uid: int = 0
var body: RigidBody3D = null          ## the vehicle (VehicleBase, accessed through `veh` for its API)
var veh: Variant = null               ## same object, untyped: set_inputs(), honk() ... (soft dependency)
var dummy: TrafficDummy = null         ## sitting in the driver seat (= vehicle.driver)
var spec_id: String = ""
var archetype: String = "civilian_m"  ## npc archetype used when the driver leaves the car
var personality: int = 0              ## 0 normal, 1 timid, 2 aggressive
var speed_factor: float = 1.0
var headway: float = 1.3              ## seconds
var max_throttle: float = 0.68        ## calm launches (panic overrides to 1.0)
var half_len: float = 2.3
var half_w: float = 0.9
var wheelbase: float = 2.6
var max_steer: float = 0.6            ## rad
var pursuit_ref: float = 1.3          ## metres from the body origin back to the pure-pursuit reference point
var two_wheeler: bool = false
var prog_pos: Vector3 = Vector3.ZERO  ## last place where real progress was made
var prog_t: float = 0.0               ## seconds without progress (hopeless check)
var steer_slip: float = 0.05          ## rad (spec.high_speed_steer_slip)
var grip: float = 1.0

# --- lane cursor --------------------------------------------------------------------------------
var lane: int = -1
var s: float = 0.0
var seg_i: int = 0
var next_lane: int = -1
var in_conn: bool = false
var conn: Array = []                  ## TrafficLanes.get_conn() record of lane -> next_lane
var conn_s: float = 0.0
var conn_i: int = 0
var lateral: float = 0.0              ## current smoothed lateral offset (m, + = right)
var lateral_target: float = 0.0
var offset_now: float = 0.0           ## where the car really is: cross-track from the path centre (m, + = right)

# --- decision state -------------------------------------------------------------------------------
var tier: int = 0                     ## 0 near (15 Hz), 1 mid (5 Hz), 2 far (frozen)
var think_t: float = 0.0
var since: float = 0.0                ## seconds since the last decision
var age: float = 0.0
var speed: float = 0.0                ## forward m/s at the last decision
var target_speed: float = 0.0
var throttle: float = 0.0
var brake: float = 0.0
var steer: float = 0.0
var block: int = Block.NONE
var block_root: int = Block.NONE      ## what the head of the queue is doing (for "is traffic flowing")
var lead_uid: int = -1                ## uid of the traffic driver ahead (-1 none / foreign)
var lead_gap: float = INF
var lead_v: float = 0.0
var lead_legit: bool = false          ## the (foreign) car ahead waits at a light
var obs_gap: float = INF              ## box cast: free distance ahead of the front bumper
var obs_v: float = 0.0
var obs_kind: int = 0                 ## 1 person, 2 vehicle, 3 prop / other
var obs_uid: int = -1
var obs_legit: bool = false
var obs_name: String = ""
var stop_dist: float = INF            ## distance to the point where the car must stand still
var permit: bool = false              ## right of way granted for the junction at the end of `lane`
var permit_signal: int = 0            ## signal state when the permit was granted
var ready: bool = false               ## signal + room allow entry (others give way only to ready cars)
var jn_node: int = -1                 ## junction approached / crossed (-1 none)
var d_line: float = INF               ## front bumper to the stop line
var eta: float = INF                  ## seconds to the stop line
var rank: int = 2
var wait_t: float = 0.0               ## waiting at a junction line
var blocked_t: float = 0.0            ## blocked by an obstacle
var stuck_t: float = 0.0              ## wants to move, does not
var honk_t: float = 0.0
var honk_cd: float = 0.0
var brake_t: float = 0.0              ## reaction brake (bump)
var panic_t: float = 0.0
var panic_from: Vector3 = Vector3.INF
var siren_t: float = 0.0
var lc_t: float = 0.0                 ## lane change blend time left
var lc_from: int = -1
var lc_cd: float = 0.0
var lc_age: float = -100.0            ## age at the last lane change (tracking metric skips the merge)
var lc_forced: bool = false           ## the lane change goes around an obstacle (its old lane is blocked on purpose)
var bypass_t: float = 0.0
var bypass_stall_t: float = 0.0       ## standing still during a bypass (head-on with oncoming traffic)
var jn_foreign: bool = false          ## waits because a STATIONARY foreign vehicle is in the junction box
var path_clear_ok: bool = false       ## a physical sweep found the junction path clear past that vehicle
var reroute_cd: float = 0.0
var reverse_t: float = 0.0
var reverse_steer: float = 0.0
var release_reason: String = ""       ## pending: leave the car when stopped
var release_t: float = 0.0
var threat_pos: Vector3 = Vector3.INF
var threat_node: Node = null
var aimed_t: float = 0.0
var reacted_aim: bool = false
var crash_reacted: bool = false
var frozen: bool = false
var frozen_speed: float = 0.0
var visible_driver: bool = false
var indicator: int = 0
var spawn_pos: Vector3 = Vector3.ZERO
var red_violation: bool = false

var _pi: int = 0


func is_valid() -> bool:
	return body != null and is_instance_valid(body) and not body.is_queued_for_deletion()


func full_length() -> float:
	return half_len * 2.0


# ---------------------------------------------------------------------------------------------
# path
# ---------------------------------------------------------------------------------------------

## Places the cursor on `p_lane` at `p_s` and picks the next lane.
func place(L: TrafficLanes, p_lane: int, p_s: float, rng: RandomNumberGenerator) -> void:
	lane = p_lane
	s = p_s
	seg_i = TrafficLanes.poly_index(L.cum[lane], clampf(s, 0.0, L.length[lane]))
	in_conn = false
	conn = []
	conn_s = 0.0
	conn_i = 0
	permit = false
	next_lane = -1
	choose_next(L, rng)


## Random next lane at the end of `lane`: straight preferred, dead ends / dirt avoided, panicking
## drivers turn away from the threat.
func choose_next(L: TrafficLanes, rng: RandomNumberGenerator) -> void:
	var opts: PackedInt32Array = L.next[lane]
	next_lane = -1
	path_clear_ok = false
	jn_foreign = false
	if opts.is_empty():
		return
	if opts.size() == 1:
		next_lane = opts[0]
	else:
		var total := 0.0
		var weights := PackedFloat32Array()
		weights.resize(opts.size())
		for i in opts.size():
			var o := opts[i]
			var w := 1.0
			var turn := L.conn_turn(lane, o)
			match turn:
				0:
					w = 1.6
				1:
					w = 0.75
				-1:
					w = 0.6
				2:
					w = 0.05
			if L.dead_end[o] == 1:
				w *= 0.02
			match L.kind[o]:
				TrafficLanes.KIND_ARTERIAL:
					w *= 1.3
				TrafficLanes.KIND_ALLEY:
					w *= 0.3
				TrafficLanes.KIND_DIRT:
					w *= 0.03
				TrafficLanes.KIND_OTHER:
					w *= 0.01
			if panic_t > 0.0 and panic_from != Vector3.INF:
				var away := L.lane_point(o, L.length[o]) - panic_from
				away.y = 0.0
				var here := L.lane_point(o, 0.0) - panic_from
				here.y = 0.0
				if away.length() > here.length():
					w *= 3.0
			weights[i] = w
			total += w
		var roll := rng.randf() * total
		for i in opts.size():
			roll -= weights[i]
			if roll <= 0.0:
				next_lane = opts[i]
				break
		if next_lane < 0:
			next_lane = opts[opts.size() - 1]
	conn = L.get_conn(lane, next_lane)


## Projects the vehicle position onto the current path element and advances lane / connection.
func track(L: TrafficLanes, pos: Vector3, rng: RandomNumberGenerator) -> void:
	for step in 3:
		if in_conn:
			var cp: PackedVector3Array = conn[0]
			var cc: PackedFloat32Array = conn[1]
			conn_s = _project(cp, cc, pos, conn_i)
			conn_i = _pi
			var clen: float = conn[2]
			if conn_s < clen - 0.01:
				return
			_enter_next(L, conn_s - clen, rng)
		else:
			s = _project(L.pts[lane], L.cum[lane], pos, seg_i)
			seg_i = _pi
			var llen := L.length[lane]
			if s < llen - 0.01:
				return
			if next_lane < 0:
				choose_next(L, rng)
				if next_lane < 0:
					return
			if conn.is_empty():
				conn = L.get_conn(lane, next_lane)
			var clen2: float = conn[2]
			if clen2 > 0.3:
				in_conn = true
				conn_i = 0
				conn_s = s - llen
				on_enter_junction(L)
			else:
				_enter_next(L, s - llen, rng)


func on_enter_junction(L: TrafficLanes) -> void:
	# a car whose permit was granted at red (panic) or that never had one at red runs the light
	if L.sig[lane] >= 0 and L.signal_state(lane) == 2 and (not permit or permit_signal == 2):
		red_violation = true


func _enter_next(L: TrafficLanes, overshoot: float, rng: RandomNumberGenerator) -> void:
	lane = next_lane
	s = overshoot
	seg_i = 0
	in_conn = false
	conn_s = 0.0
	conn_i = 0
	permit = false
	wait_t = 0.0
	jn_node = -1
	next_lane = -1
	choose_next(L, rng)


func _project(p: PackedVector3Array, c: PackedFloat32Array, pos: Vector3, hint: int) -> float:
	var n := p.size()
	if n < 2:
		_pi = 0
		return 0.0
	var i := clampi(hint, 0, n - 2)
	var t := 0.0
	var moved_fwd := false
	for it in 96:
		var a := p[i]
		var b := p[i + 1]
		var abx := b.x - a.x
		var abz := b.z - a.z
		var l2 := abx * abx + abz * abz
		t = 0.0 if l2 < 0.000001 else ((pos.x - a.x) * abx + (pos.z - a.z) * abz) / l2
		if t > 1.0 and i < n - 2:
			i += 1
			moved_fwd = true
			continue
		if t < 0.0 and i > 0 and not moved_fwd:
			i -= 1
			continue
		break
	_pi = i
	var seg_len := c[i + 1] - c[i]
	if i < n - 2:
		t = minf(t, 1.0)
	if i > 0:
		t = maxf(t, 0.0)
	return c[i] + maxf(t * seg_len, -6.0)


## Lateral distance (m, + = right of the path) of `pos` from the current path element.
func cross_track(L: TrafficLanes, pos: Vector3) -> float:
	var p0 := point_ahead(L, 0.0)
	var dir := point_ahead(L, 1.0) - p0
	dir.y = 0.0
	if dir.length_squared() < 0.000001:
		return 0.0
	dir = dir.normalized()
	var w := pos - p0
	return w.x * -dir.z + w.z * dir.x


## World point `dist` metres ahead of the cursor along lane -> connection -> next lane.
func point_ahead(L: TrafficLanes, dist: float) -> Vector3:
	if in_conn:
		var clen: float = conn[2]
		var rem := clen - conn_s
		if dist <= rem:
			return TrafficLanes.poly_point(conn[0], conn[1], conn_s + dist)
		return L.lane_point(next_lane, dist - rem)
	var llen := L.length[lane]
	var rem2 := llen - s
	if dist <= rem2 or next_lane < 0:
		return L.lane_point(lane, s + dist)
	var d := dist - rem2
	var clen2: float = conn[2] if not conn.is_empty() else 0.0
	if d <= clen2 and clen2 > 0.0:
		return TrafficLanes.poly_point(conn[0], conn[1], d)
	return L.lane_point(next_lane, d - clen2)


## Distance from the cursor to the end of the connection after the current lane (0 when inside it).
func dist_to_next_lane(L: TrafficLanes) -> float:
	if in_conn:
		return maxf(float(conn[2]) - conn_s, 0.0)
	var clen: float = conn[2] if not conn.is_empty() else 0.0
	return maxf(L.length[lane] - s, 0.0) + clen


## The movement (from lane -> to lane) this driver makes at the junction it approaches / crosses.
func movement_from() -> int:
	return lane


func movement_to() -> int:
	return next_lane


func current_limit(L: TrafficLanes) -> float:
	if in_conn and next_lane >= 0:
		return minf(L.limit[lane], L.limit[next_lane])
	return L.limit[lane]


## Lane change onto the neighbouring lane of the same direction (arterial). Returns success.
## `forced`: going around something that blocks the old lane (no leader check there while blending).
func change_lane(L: TrafficLanes, to_lane: int, pos: Vector3, rng: RandomNumberGenerator, forced: bool = false) -> bool:
	if to_lane < 0 or in_conn:
		return false
	var ratio := s / maxf(L.length[lane], 0.1)
	lc_from = lane
	lc_forced = forced
	lane = to_lane
	seg_i = TrafficLanes.poly_index(L.cum[lane], clampf(ratio * L.length[lane], 0.0, L.length[lane]))
	s = _project(L.pts[lane], L.cum[lane], pos, seg_i)
	seg_i = _pi
	permit = false
	next_lane = -1
	choose_next(L, rng)
	lc_t = 2.6
	lc_age = age
	# the path jumps sideways by the lane spacing: start from the old position and blend in
	lateral = cross_track(L, pos)
	return true
