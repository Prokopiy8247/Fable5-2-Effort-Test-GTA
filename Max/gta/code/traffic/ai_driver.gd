class_name AIDriver
extends Node
## Lane-following driver for civilian traffic, taxis and emergency vehicles. It drives the
## same physics model as the player through throttle / steer / brake inputs:
## pure-pursuit steering on the lane graph, kinematic speed planning for bends, stop lines,
## traffic signals, junction reservations and vehicles / people ahead, plus panic, pursuit
## and "drive to" behaviour for the police and service vehicles.

enum Mode { CRUISE, PANIC, GOTO, CHASE, HOLD }

const A_BRAKE := 4.0
const TURN_SPEED := 6.0

var veh: Car = null
var graph: RoadGraph = null
var mgr: Node = null                 # TrafficManager (junction claims, signal clock)
var mode: int = Mode.CRUISE
var lane := -1
var s := 0.0
var next_lane := -1
var route: PackedInt32Array = PackedInt32Array()
var route_i := 0
var dest := Vector3.ZERO
var dest_lane := -1
var dest_s := 0.0
var arrived := false
var target: Node3D = null
var emergency := false               # ignores signals, drives fast
var aggression := 0.5                # pursuit: 0 = follow, 1 = ram
var cruise_mul := 1.0
var panic_time := 0.0
var threat := Vector3.ZERO
var blocked := 0.0                   # seconds stopped behind something
var stuck := 0.0                     # seconds wanting to move but not moving
var dead_end := false
var direct := false                  # pursuit: currently steering straight at the target
var waiting := false                 # stopped for a signal / junction, or queued behind someone who is
var _blocker: Vehicle = null
var _yield_t := 0.0                  # pulling over for an emergency vehicle
var _reverse := 0.0
var _sense_cd := 0.0
var _gap := 999.0
var _gap_v := 0.0
var _ped_ahead := false
var _horn := 0.0
var _swerve := 0.0
var _claim_node := ""
var _rng := RandomNumberGenerator.new()
var _reroute := 0.0
var _los_cd := 0.0
var _bail_cd := 0.0

static func attach(v: Car, manager: Node, lane_id: int, s0: float) -> AIDriver:
	var d := AIDriver.new()
	d.name = "AIDriver"
	d.veh = v
	d.mgr = manager
	d.graph = Game.world.graph
	d.lane = lane_id
	d.s = s0
	d._rng.seed = hash(v.get_instance_id())
	d.cruise_mul = d._rng.randf_range(0.82, 1.06)
	d._sense_cd = d._rng.randf() * 0.15
	v.add_child(d)
	v.ai = d
	v.in_handbrake = false
	if lane_id >= 0:
		d._pick_next()
	return d

# ---------------------------------------------------------------- public orders
func panic(from: Vector3) -> void:
	if emergency or mode == Mode.CHASE or mode == Mode.GOTO:
		return
	if mode != Mode.PANIC:
		panic_time = _rng.randf_range(12.0, 22.0)
	mode = Mode.PANIC
	threat = from

func on_attacked(source: Node) -> void:
	if source is Node3D:
		panic((source as Node3D).global_position)

## Drive along the road network to `pos`. Returns false when no route exists.
func drive_to(pos: Vector3, hurry := true) -> bool:
	var fwd := -veh.global_transform.basis.z
	var a := graph.nearest(veh.global_position, 70.0, fwd)
	var b := graph.nearest(pos, 90.0)
	if a.is_empty() or b.is_empty():
		return false
	var r := graph.route(int(a["lane"]), int(b["lane"]))
	if r.is_empty():
		return false
	_release_claim()
	route = r
	route_i = 0
	lane = int(a["lane"])
	s = float(a["s"])
	dest = pos
	dest_lane = int(b["lane"])
	dest_s = float(b["s"])
	arrived = false
	emergency = hurry
	if mode != Mode.CHASE:
		mode = Mode.GOTO
	_pick_next()
	return true

func chase(what: Node3D, how_hard := 0.5) -> void:
	target = what
	aggression = how_hard
	emergency = true
	mode = Mode.CHASE
	arrived = false
	_reroute = 0.0

func hold() -> void:
	mode = Mode.HOLD
	_release_claim()

func cruise() -> void:
	mode = Mode.CRUISE
	emergency = false
	arrived = false
	route = PackedInt32Array()
	var a := graph.nearest(veh.global_position, 60.0, -veh.global_transform.basis.z)
	if not a.is_empty():
		lane = int(a["lane"])
		s = float(a["s"])
		_pick_next()

func release() -> void:
	_release_claim()
	if veh != null and is_instance_valid(veh):
		if veh.ai == self:
			veh.ai = null
		veh.in_throttle = 0.0
		veh.in_brake = 0.0
		veh.in_steer = 0.0
		veh.in_handbrake = true
		veh.horn(false)
	queue_free()

func _exit_tree() -> void:
	_release_claim()

func _release_claim() -> void:
	if _claim_node != "" and mgr != null and is_instance_valid(mgr):
		mgr.release_claim(_claim_node, self)
	_claim_node = ""

# ---------------------------------------------------------------- lane bookkeeping
func _pick_next() -> void:
	next_lane = -1
	if lane < 0:
		return
	var l := graph.lanes[lane]
	if not route.is_empty():
		# keep the route index in step with the lane we are actually on
		for i in range(route_i, mini(route_i + 3, route.size())):
			if route[i] == lane:
				route_i = i
				break
		if route_i + 1 < route.size() and route[route_i] == lane:
			next_lane = route[route_i + 1]
			return
	if l.next.is_empty():
		return
	if l.is_connector:
		next_lane = l.next[0]
		return
	var best_w := -1.0
	for c in l.next:
		var cl := graph.lanes[c]
		var w := _rng.randf() * (2.2 if cl.turn == 0 else 1.0)
		if not cl.next.is_empty() and graph.lanes[cl.next[0]].kind == "hill":
			w *= 0.3
		if w > best_w:
			best_w = w
			next_lane = c

## Point `ahead` metres further along the planned path (current lane, then the next ones).
func _point_ahead(ahead: float) -> Vector3:
	var l := graph.lanes[lane]
	var d := s + ahead
	if d <= l.length or next_lane < 0:
		return graph.sample(lane, d)
	d -= l.length
	var nl := graph.lanes[next_lane]
	if d <= nl.length or nl.next.is_empty():
		return graph.sample(next_lane, d)
	d -= nl.length
	return graph.sample(nl.next[0], d)

func _advance() -> void:
	var l := graph.lanes[lane]
	if l.is_connector:
		_release_claim()
	lane = next_lane
	s = 0.0
	_pick_next()

# ---------------------------------------------------------------- sensing
func _sense() -> void:
	_gap = 999.0
	_gap_v = 0.0
	_ped_ahead = false
	_blocker = null
	var xf := veh.global_transform
	var fwd := -xf.basis.z
	var right := xf.basis.x
	var pos := xf.origin
	var reach := clampf(absf(veh.speed) * 2.4 + 8.0, 10.0, 48.0)
	for n in get_tree().get_nodes_in_group(&"vehicles"):
		var o := n as Vehicle
		if o == veh or o == target:
			continue
		var rel := o.global_position - pos
		if o.siren_on and not emergency and mode != Mode.CHASE:
			var fb := rel.dot(fwd)
			if fb < 0.0 and fb > -32.0 and absf(rel.dot(right)) < 4.5 and o.linear_velocity.dot(fwd) > 3.0:
				_yield_t = 3.0
		if absf(rel.y) > 3.0:
			continue
		var f := rel.dot(fwd)
		if f < 0.0 or f > reach + 4.0:
			continue
		var al := absf((-o.global_transform.basis.z).dot(fwd))
		var o_len := lerpf(o.half_width, o.half_length, al)
		var o_wid := lerpf(o.half_length, o.half_width, al)
		# parked / stopped cars at the kerb only count when they really overlap our path
		var parked := o.ai == null and o.linear_velocity.length() < 0.5
		if absf(rel.dot(right)) > veh.half_width + o_wid + (-0.15 if parked else 0.3):
			continue
		var gap := f - veh.half_length - o_len
		if gap < -1.0:
			continue          # alongside us, not ahead (physics deals with actual contact)
		if gap < _gap:
			_gap = gap
			_gap_v = o.linear_velocity.dot(fwd)
			_blocker = o
	var ped_reach := minf(reach, 24.0)
	for n in get_tree().get_nodes_in_group(&"npcs"):
		_sense_person(n as Character, pos, fwd, right, ped_reach)
	if Game.player != null and target != Game.player:
		_sense_person(Game.player, pos, fwd, right, ped_reach)

func _sense_person(c: Character, pos: Vector3, fwd: Vector3, right: Vector3, reach: float) -> void:
	if c.vehicle != null or not c.alive:
		return
	var rel := c.global_position - pos
	if absf(rel.y) > 2.5:
		return
	var f := rel.dot(fwd)
	if f < 0.0 or f > reach:
		return
	if absf(rel.dot(right)) > veh.half_width + 0.6:
		return
	var gap := f - veh.half_length - 0.4
	if gap < _gap:
		_gap = gap
		_gap_v = c.velocity.dot(fwd)
		_ped_ahead = true
		_blocker = null

# ---------------------------------------------------------------- main loop
func _physics_process(delta: float) -> void:
	if veh == null or not is_instance_valid(veh):
		queue_free()
		return
	if veh.destroyed:
		release()
		return
	var drv := veh.driver()
	if drv == null or not drv.alive or drv.is_player:
		release()
		return
	_sense_cd -= delta
	if _sense_cd <= 0.0:
		_sense_cd = 0.11
		_sense()
	if _horn > 0.0:
		_horn -= delta
		if _horn <= 0.0:
			veh.horn(false)
	match mode:
		Mode.HOLD:
			_apply(0.0, 0.0, delta)
		Mode.CHASE:
			_chase(delta)
		_:
			_follow(delta)

func _follow(delta: float) -> void:
	if lane < 0:
		_apply(0.0, 0.0, delta)
		return
	var pos := veh.global_position
	var pr := graph.project(lane, pos)
	if float(pr[0]) > s:
		s = float(pr[0])
	var l := graph.lanes[lane]
	if s >= l.length - 0.7:
		if next_lane < 0:
			dead_end = true
			_apply(0.0, 0.0, delta)
			return
		_advance()
		l = graph.lanes[lane]
		pr = graph.project(lane, pos)
		s = maxf(s, float(pr[0]))
	var speed := veh.speed
	var is_panic := mode == Mode.PANIC
	var hurry := is_panic or emergency
	if is_panic:
		panic_time -= delta
		if panic_time <= 0.0:
			mode = Mode.CRUISE
	# --- how fast may we go
	var top := float(veh.def.get("top", 45.0))
	var v_max := l.speed * cruise_mul
	if emergency:
		v_max = minf(maxf(l.speed * 1.9, 22.0), top * 0.82)
	elif is_panic:
		v_max = minf(l.speed * 1.7, top * 0.75)
	elif Game.weather != null:
		v_max *= lerpf(1.0, 0.82, clampf(Game.weather.rain * 1.5, 0.0, 1.0))
	var turn_v := TURN_SPEED * (1.45 if hurry else 1.0)
	var d_end := l.length - s
	if l.is_connector:
		if l.turn != 0:
			v_max = minf(v_max, turn_v)
		elif emergency:
			v_max = minf(v_max, 15.0)
	elif next_lane >= 0:
		var nl := graph.lanes[next_lane]
		if nl.turn != 0:
			v_max = minf(v_max, sqrt(turn_v * turn_v + 2.0 * A_BRAKE * maxf(d_end, 0.0)))
			if d_end < 32.0:
				veh._indicator = nl.turn
		else:
			veh._indicator = 0
			if emergency:
				v_max = minf(v_max, sqrt(225.0 + 2.0 * A_BRAKE * maxf(d_end, 0.0)))
	if l.pts.size() > 3 and not l.is_connector:
		# winding road: slow down for the bend ahead
		var bend := graph.direction(lane, s).angle_to(graph.direction(lane, minf(s + 11.0, l.length)))
		v_max = minf(v_max, l.speed * lerpf(1.0, 0.5, clampf(bend / 0.6, 0.0, 1.0)) * (1.3 if hurry else 1.0))
	# --- junction: signal, reservation, stop line
	var stop_d := 1.0e9
	if not l.is_connector and next_lane >= 0:
		var d_line := d_end - RoadGraph.STOP_SETBACK - veh.half_length
		var node_id := l.node_end
		if d_line < 60.0:
			var need := false
			var signalled: bool = graph.node_signal.get(node_id, false)
			var committed := d_line < -2.0
			if signalled and not hurry and not committed:
				var st := graph.signal_state(node_id, l.axis, mgr.clock())
				if st == 2:
					need = true
				elif st == 1:
					need = d_line > speed * 1.1
			if not need:
				if d_line < maxf(11.0, speed * 1.7):
					if mgr.claim(node_id, next_lane, self, hurry or committed):
						_claim_node = node_id
					else:
						need = true
				elif not signalled and not hurry:
					v_max = minf(v_max, sqrt(30.0 + 2.0 * A_BRAKE * maxf(d_line, 0.0)))
			if need:
				stop_d = maxf(d_line, 0.0)
	if mode == Mode.GOTO and lane == dest_lane:
		var d_dest := dest_s - s
		if d_dest < 7.0 or veh.global_position.distance_to(dest) < 9.0:
			arrived = true
			mode = Mode.HOLD
			_apply(0.0, 0.0, delta)
			return
		v_max = minf(v_max, sqrt(4.0 + 2.0 * A_BRAKE * maxf(d_dest - 7.0, 0.0)))
	if stop_d < 1.0e8:
		v_max = minf(v_max, sqrt(2.0 * A_BRAKE * maxf(stop_d - 0.4, 0.0)))
		if stop_d < 0.6:
			v_max = 0.0
	# --- traffic and people ahead
	var signal_stop := stop_d < 6.0
	var queued := false
	if _gap < 7.0 and _blocker != null and is_instance_valid(_blocker) and _blocker.ai is AIDriver:
		queued = (_blocker.ai as AIDriver).waiting
	waiting = stop_d < 1.0e8 or queued
	if _gap < 900.0:
		var min_gap := 1.3 if hurry else 2.5
		if _swerve > 0.0:
			min_gap = 0.7
		var v_o := maxf(_gap_v, 0.0)
		var allowed := v_o + sqrt(2.0 * 3.6 * maxf(_gap - min_gap, 0.0)) if _gap > min_gap else maxf(v_o - 1.5, 0.0)
		v_max = minf(v_max, allowed)
	# --- stuck / blocked bookkeeping
	if absf(speed) < 0.5:
		if v_max > 1.0 and _reverse <= 0.0:
			stuck += delta
		else:
			stuck = maxf(0.0, stuck - delta)
		if _gap < 4.5 and _gap_v < 0.5 and not signal_stop and not queued:
			blocked += delta
		else:
			blocked = maxf(0.0, blocked - delta)
	else:
		stuck = 0.0
		blocked = maxf(0.0, blocked - delta * 2.0)
	if blocked > 2.6 and _horn <= 0.0 and _rng.randf() < delta * (1.2 if _ped_ahead or is_panic else 0.45):
		veh.horn(true)
		_horn = _rng.randf_range(0.3, 0.9)
	if is_panic and blocked > 2.2 and veh.global_position.distance_to(threat) < 40.0:
		_bail()
		return
	# emergency vehicles go round stopped traffic almost at once, everybody else waits a while
	if blocked > (1.5 if emergency else 8.0) and _swerve <= 0.0 and not l.is_connector and not _ped_ahead:
		_swerve = 5.0
		blocked = 3.0
		if _gap < 1.6:
			_reverse = 1.1
	if stuck > 3.5 and _reverse <= 0.0:
		_reverse = 1.3
		stuck = 0.0
	# --- pull over for sirens behind us
	var pull := 0.0
	if _yield_t > 0.0:
		_yield_t -= delta
		if not l.is_connector:
			v_max = minf(v_max, 2.5)
			pull = 1.6
	# --- steering target
	var look := clampf(3.2 + absf(speed) * 0.5, 4.2, 13.0)
	var tp := _point_ahead(look)
	if pull > 0.0:
		var dd := graph.direction(lane, s)
		tp += Vector3(-dd.z, 0.0, dd.x) * pull
	if _swerve > 0.0:
		_swerve -= delta
		var dirv := graph.direction(lane, s)
		tp += Vector3(dirv.z, 0.0, -dirv.x) * 3.3 * clampf(_swerve, 0.0, 1.0)      # pass on the left
		v_max = minf(v_max, 4.5)
	_apply(v_max, _steer_to(tp), delta)

## Pure-pursuit steering input (-1..1, + = right) toward a world point.
func _steer_to(tp: Vector3) -> float:
	var xf := veh.global_transform
	var local := xf.basis.transposed() * (tp - xf.origin)
	var ld := maxf(Vector2(local.x, local.z).length(), 0.5)
	var alpha := atan2(local.x, -local.z)
	var wheelbase := veh.half_length * 1.25
	var steer_angle := atan(2.0 * wheelbase * sin(alpha) / ld)
	return clampf(steer_angle / maxf(veh.max_steer(), 0.05), -1.0, 1.0)

func _apply(v_target: float, steer: float, delta: float) -> void:
	var speed := veh.speed
	if _reverse > 0.0:
		_reverse -= delta
		veh.in_throttle = -0.8
		veh.in_brake = 0.0
		veh.in_steer = -steer
		veh.in_handbrake = false
		return
	var err := v_target - speed
	var thr := 0.0
	var brk := 0.0
	var hb := false
	if v_target < 0.3:
		brk = 1.0 if absf(speed) > 0.25 else 0.4
		hb = absf(speed) < 0.8
	elif err > 0.0:
		thr = clampf(err * 0.42 + 0.06, 0.0, 1.0 if (emergency or mode == Mode.PANIC) else 0.72)
	elif err < -0.7:
		brk = clampf(-err * 0.3, 0.12, 1.0)
	else:
		thr = 0.04
	veh.in_throttle = thr
	veh.in_brake = brk
	veh.in_steer = steer
	veh.in_handbrake = hb

## Panicking driver abandons the car and runs.
func _bail() -> void:
	var from := threat
	for i in veh.seat_count():
		var c: Character = veh.seats[i]["occupant"]
		if c == null or c.is_player:
			continue
		veh.unseat(i)
		if c is NPC:
			(c as NPC).ambient = true
			(c as NPC).flee(from)
	release()

# ---------------------------------------------------------------- pursuit
func _chase(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		hold()
		return
	var pos := veh.global_position
	var tpos := target.global_position
	var d := pos.distance_to(tpos)
	var tv := Vector3.ZERO
	if target is RigidBody3D:
		tv = (target as RigidBody3D).linear_velocity
	elif target is CharacterBody3D:
		tv = (target as CharacterBody3D).velocity
	_los_cd -= delta
	if _los_cd <= 0.0:
		_los_cd = 0.3
		direct = d < 60.0 and absf(tpos.y - pos.y) < 6.0 and Game.ray(pos + Vector3(0, 1.0, 0), tpos + Vector3(0, 1.0, 0), Phys.WORLD).is_empty()
	if not direct:
		# out of sight: use the road network toward the lane nearest to the target
		_reroute -= delta
		if _reroute <= 0.0 or route.is_empty() or dead_end:
			_reroute = 1.8
			dead_end = false
			var heading := tv.normalized() if tv.length() > 3.0 else Vector3.ZERO
			var b := graph.nearest(tpos, 90.0, heading)
			var a := graph.nearest(pos, 70.0, -veh.global_transform.basis.z)
			if not a.is_empty() and not b.is_empty():
				var r := graph.route(int(a["lane"]), int(b["lane"]))
				if not r.is_empty():
					route = r
					route_i = 0
					dest_lane = -1
					if lane != int(a["lane"]):
						_release_claim()
						lane = int(a["lane"])
						s = float(a["s"])
					_pick_next()
		if lane >= 0:
			_follow(delta)
		else:
			_apply(0.0, 0.0, delta)
		return
	# --- direct pursuit
	_release_claim()
	var speed := veh.speed
	var on_foot := target is Character
	var top := float(veh.def.get("top", 45.0))
	var lead := clampf(d / maxf(absf(speed) + 8.0, 8.0), 0.0, 1.1)
	var aim := tpos + tv * lead
	var t_speed := tv.length()
	var keep := 9.0 if on_foot else lerpf(7.0, 0.0, aggression)
	var v_des := clampf(t_speed + (d - keep) * 0.9, 0.0, top * 0.9)
	if on_foot and d < 11.0:
		v_des = 0.0
		arrived = true
	else:
		arrived = not on_foot and d < 12.0 and t_speed < 2.0 and absf(speed) < 2.5
	# whiskers: steer around walls and traffic
	var xf := veh.global_transform
	var fwd := -xf.basis.z
	var right := xf.basis.x
	var o := pos + Vector3(0, 0.7, 0)
	var reach := 5.0 + absf(speed) * 0.7
	var ex: Array[RID] = [veh.get_rid()]
	if target is CollisionObject3D:
		ex.append((target as CollisionObject3D).get_rid())
	var mask := Phys.WORLD | Phys.VEHICLE
	var hc := Game.ray(o, o + fwd * reach, mask, ex)
	var hl := Game.ray(o - right * 0.7, o + (fwd - right * 0.55).normalized() * reach * 0.8, mask, ex)
	var hr := Game.ray(o + right * 0.7, o + (fwd + right * 0.55).normalized() * reach * 0.8, mask, ex)
	var steer := _steer_to(aim)
	if not hl.is_empty() and hr.is_empty():
		steer = clampf(steer + 0.7, -1.0, 1.0)
	elif not hr.is_empty() and hl.is_empty():
		steer = clampf(steer - 0.7, -1.0, 1.0)
	if not hc.is_empty():
		var hd := o.distance_to(hc["position"])
		v_des = minf(v_des, maxf(hd - 2.5, 0.0) * 1.6)
		if hd < 3.4 and absf(speed) < 1.5:
			stuck += delta
		if hl.is_empty() == hr.is_empty():
			steer = 1.0 if steer >= 0.0 else -1.0
	else:
		stuck = maxf(0.0, stuck - delta)
	# slow down for sharp heading errors at speed
	var local := xf.basis.transposed() * (aim - pos)
	var alpha := absf(atan2(local.x, -local.z))
	if alpha > 0.6:
		v_des = minf(v_des, lerpf(14.0, 6.0, clampf((alpha - 0.6) / 1.2, 0.0, 1.0)))
	if absf(speed) < 0.5 and v_des > 2.0:
		stuck += delta
	if stuck > 1.6 and _reverse <= 0.0:
		_reverse = 1.2
		stuck = 0.0
	_apply(v_des, steer, delta)
	_reroute = 0.0        # re-route immediately when the target drops out of sight
