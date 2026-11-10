extends Node
## TRAFFIC junction stress (headless, review test): the right-of-way permit rule at UNSIGNALISED
## junctions and stationary foreign vehicles inside a junction box.
##
##   1. stress   the busiest unsignalised junction (most legs) gets a new car on every approach lane
##               every 2.5 s for 50 s (only scripted cars, no ambient traffic): cars keep crossing,
##               nobody waits for ever (deadlock freedom), no collisions
##   2. blocked  an abandoned van stands in the junction box (off-centre, like a car left after a crash,
##               across the far half of one leg's mouth): cars whose path it blocks take another exit
##               (reroute) or go when a physical sweep says they fit past; the junction keeps working.
##               A van dead in the centre of a small T junction blocks every movement: then the cars wait
##               and honk (and are despawned when unseen), which is checked too.
##   3. signal   the same stress at the nearest signalised junction: crossings, no red violations
##
## Run: tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 420 -UserArgs '--test=trf_junction','--test-timeout=400','--no_player',
##      '--disable=peds,props,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug,pickups,interactions'

var sys: TrafficSystem = null
var L: TrafficLanes = null
var crossed: Dictionary = {}           ## uid -> true once it entered the junction box
var wait_max: float = 0.0
var wait_info: String = ""
var still: Dictionary = {}
var still_max: float = 0.0
var still_info: String = ""
var veh_sec: float = 0.0              ## active vehicle-seconds of the current stress phase (impact rate)
var moto: TrafficDriver = null
var moto_tilt: float = 0.0
var moto_xt: float = 0.0


func _ready() -> void:
	await _run()


func _run() -> void:
	sys = Game.get_system("traffic") as TrafficSystem
	if not TestHarness.check(sys != null and sys.lanes != null, "traffic system with lanes"):
		TestHarness.finish(false, "no traffic")
		return
	L = sys.lanes
	if WorldClock.has_method("set_hour"):
		WorldClock.set_hour(12.0)
	if "paused" in WorldClock:
		WorldClock.paused = true
	# the unsignalised junction with the most approach lanes (spawnable ones)
	var node := _pick_junction(false)
	if not TestHarness.check(node >= 0, "an unsignalised 3+ leg junction exists"):
		TestHarness.finish(false, "no junction")
		return
	var approaches := _approaches(node)
	TestHarness.log_line("unsignalised junction %d at %s: %d legs, approach lanes %s (yield %s)" % [node, str(L.node_pos[node]),
			L.node_legs[node], str(approaches), str(Array(approaches).map(func(a: int) -> int: return L.yields[a]))])
	sys.set_focus_override(L.node_pos[node])
	sys.set_density(0.0)
	sys.set_enabled(false)
	sys.set_enabled(true)
	sys.parking.clear_all()
	await TestHarness.wait_physics_frames(5)

	# ---------------------------------------------------------------- 1. stress
	var c0 := int(sys.stats["collisions"])
	await _stress(node, approaches, 50.0)
	var n1 := crossed.size()
	TestHarness.log_line("stress: %d cars crossed, longest wait %.1f s (%s), longest standstill %.1f s (%s), collisions %d | %s" % [
			n1, wait_max, wait_info, still_max, still_info, int(sys.stats["collisions"]) - c0, str(sys.get_debug_info())])
	TestHarness.check(n1 >= 20, "unsignalised stress: cars keep crossing (%d in 50 s)" % n1)
	TestHarness.check(wait_max < 20.0, "unsignalised stress: no deadlock - longest wait at the line %.1f s (< 20)" % wait_max)
	TestHarness.check(still_max < 30.0, "unsignalised stress: nobody stands still for long (%.1f s)" % still_max)
	TestHarness.check(_impact_rate(c0) < 0.35, "unsignalised stress: few impacts (%d in %.0f vehicle-minutes, < 0.35 / veh-min like trf_flow)" % [int(sys.stats["collisions"]) - c0, veh_sec / 60.0])

	# ---------------------------------------------------------------- 2. abandoned van in the box
	sys.clear_all()
	await TestHarness.wait_physics_frames(5)
	crossed.clear()
	wait_max = 0.0
	still.clear()
	still_max = 0.0
	var c := L.node_pos[node]
	# beside the mouth of one leg: on the exit-side half of approaches[0]'s road, at the box edge
	var a0 := approaches[0]
	var axis := L.lane_end_dir(a0)
	var end0 := L.lane_point(a0, L.length[a0])
	var into := (c - end0)
	into.y = 0.0
	var van_pos := end0 + into.normalized() * 2.5 + Vector3(axis.z, 0.0, -axis.x) * 1.8   # 1.8 m left of that lane: the opposite lane
	var van := Game.spawn_vehicle("van", Transform3D(Basis(Vector3.UP, atan2(-axis.x, -axis.z)), van_pos + Vector3.UP * 0.3),
			{"owner_tag": "civilian", "engine_on": false})
	await TestHarness.wait_physics_frames(60)
	TestHarness.check(van != null, "an abandoned van stands in the junction box")
	var rr0 := int(sys.stats.get("reroutes", 0))
	c0 = int(sys.stats["collisions"])
	await _stress(node, approaches, 45.0)
	var n2 := crossed.size()
	TestHarness.log_line("blocked box: %d crossed, reroutes %d, longest wait %.1f s (%s), longest standstill %.1f s (%s), collisions %d" % [
			n2, int(sys.stats.get("reroutes", 0)) - rr0, wait_max, wait_info, still_max, still_info, int(sys.stats["collisions"]) - c0])
	TestHarness.check(n2 >= 8, "van in the box: the junction keeps working (%d crossings in 45 s)" % n2)
	TestHarness.check(int(sys.stats.get("reroutes", 0)) > rr0 or n2 >= 15, "van in the box: blocked cars turn elsewhere (%d reroutes)" % (int(sys.stats.get("reroutes", 0)) - rr0))
	TestHarness.check(still_max < 40.0, "van in the box: nobody waits for ever (longest standstill %.1f s)" % still_max)
	if van != null and is_instance_valid(van):
		sys.despawn_vehicle_node(van)
	# a van dead in the centre: nothing fits past - the head cars honk instead of waiting silently
	sys.clear_all()
	await TestHarness.wait_physics_frames(5)
	var van2 := Game.spawn_vehicle("van", Transform3D(Basis(Vector3.UP, atan2(-axis.x, -axis.z)), c + Vector3.UP * 0.3),
			{"owner_tag": "civilian", "engine_on": false})
	await TestHarness.wait_physics_frames(60)
	var h0 := int(sys.stats["honks"])
	crossed.clear()
	await _stress(node, approaches, 15.0)
	TestHarness.log_line("van in the centre: %d crossed, honks %d, reroutes %d" % [crossed.size(), int(sys.stats["honks"]) - h0, int(sys.stats.get("reroutes", 0)) - rr0])
	TestHarness.check(int(sys.stats["honks"]) > h0, "van in the centre: the waiting drivers honk (%d)" % (int(sys.stats["honks"]) - h0))
	if van2 != null and is_instance_valid(van2):
		sys.despawn_vehicle_node(van2)

	# ---------------------------------------------------------------- 3. a signalised junction
	sys.clear_all()
	await TestHarness.wait_physics_frames(5)
	var sn := _pick_junction(true)
	if TestHarness.check(sn >= 0, "a signalised junction exists"):
		var sa := _approaches(sn)
		_log_lane_spacing(sn, sa)
		sys.set_focus_override(L.node_pos[sn])
		crossed.clear()
		wait_max = 0.0
		still.clear()
		still_max = 0.0
		var red0 := int(sys.stats["red_violations"])
		c0 = int(sys.stats["collisions"])
		# a motorcycle among them (two-wheeler pursuit / balance in traffic)
		moto = null
		var mv := sys.spawn_traffic_vehicle(sa[0], maxf(L.length[sa[0]] - 60.0, 6.0), "motorcycle")
		if mv != null and str(mv.get("spec_id")) == "motorcycle":
			moto = sys.get_driver(mv)
		await _stress(sn, sa, 40.0)
		if moto != null:
			TestHarness.log_line("motorcycle: max lean %.0f deg, max cross-track %.2f m, still driven %s, crossed %s" % [moto_tilt, moto_xt,
					str(moto.is_valid() and sys.get_driver(moto.body) == moto), str(crossed.has(moto.uid))])
			TestHarness.check(moto_tilt < 50.0, "motorcycle in traffic stays up (max lean %.0f deg)" % moto_tilt)
			TestHarness.check(moto_xt < 1.6, "motorcycle in traffic keeps its lane (max %.2f m off)" % moto_xt)
		else:
			TestHarness.log_line("motorcycle: spec not spawnable here - skipped")
		TestHarness.log_line("signalised junction %d: %d crossed, longest wait %.1f s, standstill %.1f s, collisions %d, red violations %d" % [
				sn, crossed.size(), wait_max, still_max, int(sys.stats["collisions"]) - c0, int(sys.stats["red_violations"]) - red0])
		TestHarness.check(crossed.size() >= 15, "signalised stress: cars cross on green (%d in 40 s)" % crossed.size())
		TestHarness.check(int(sys.stats["red_violations"]) == red0, "signalised stress: no red light violations")
		TestHarness.check(still_max < 45.0, "signalised stress: no gridlock (longest standstill %.1f s)" % still_max)
		TestHarness.check(_impact_rate(c0) < 0.35, "signalised stress: few impacts (%d in %.0f vehicle-minutes, < 0.35 / veh-min like trf_flow)" % [int(sys.stats["collisions"]) - c0, veh_sec / 60.0])
	TestHarness.finish()


func _pick_junction(signalled: bool) -> int:
	var best := -1
	var best_score := -1
	for k in L.node_count:
		if L.node_legs[k] < 3 or (L.node_signal[k] == 1) != signalled:
			continue
		var score := _approaches(k).size() * 10 + L.node_legs[k]
		if score > best_score:
			best_score = score
			best = k
	return best


## Approach lanes into junction `k` that are long enough to place cars on.
func _approaches(k: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in L.count:
		if L.end_node[i] == k and L.length[i] > 30.0 and L.kind[i] <= TrafficLanes.KIND_ALLEY and not L.next[i].is_empty():
			out.append(i)
	return out


func _stress(node: int, approaches: PackedInt32Array, secs: float) -> void:
	veh_sec = 0.0
	var t := 0.0
	var spawn_t := 0.0
	while t < secs:
		if spawn_t <= 0.0:
			spawn_t = 2.5
			for a in approaches:
				var off := maxf(L.length[a] - 32.0, 6.0)
				var p := L.lane_point(a, off)
				var busy := false
				for d: TrafficDriver in sys.get_drivers():
					if d.is_valid() and Vector2(d.body.global_position.x - p.x, d.body.global_position.z - p.z).length() < 11.0:
						busy = true
						break
				if not busy:
					sys.spawn_traffic_vehicle(a, off)
		await TestHarness.wait_seconds(0.25)
		t += 0.25
		spawn_t -= 0.25
		if moto != null and moto.is_valid() and sys.get_driver(moto.body) == moto:
			moto_tilt = maxf(moto_tilt, rad_to_deg(acos(clampf(moto.body.global_transform.basis.y.y, -1.0, 1.0))))
			if not moto.in_conn and moto.s > 8.0 and moto.lc_t <= 0.0:
				moto_xt = maxf(moto_xt, absf(moto.cross_track(L, moto.body.global_position)))
		for d: TrafficDriver in sys.get_drivers():
			if not d.is_valid():
				continue
			if not d.frozen:
				veh_sec += 0.25
			if d.in_conn and L.end_node[d.lane] == node:
				crossed[d.uid] = true
			if not d.in_conn and L.end_node[d.lane] == node and d.wait_t > wait_max:
				wait_max = d.wait_t
				wait_info = "uid %d lane %d next %d turn %d rank %d ready %s permit %s jn_foreign %s" % [d.uid, d.lane, d.next_lane,
						L.conn_turn(d.lane, d.next_lane) if d.next_lane >= 0 else 9, d.rank, str(d.ready), str(d.permit), str(d.jn_foreign)]
			if absf(d.speed) < 0.5 and not d.frozen:
				var ts := float(still.get(d.uid, 0.0)) + 0.25
				still[d.uid] = ts
				if ts > still_max:
					still_max = ts
					still_info = "uid %d lane %d s %.1f/%.0f block %d obs %s gap %.1f lead %d %.1f in_conn %s" % [d.uid, d.lane, d.s, L.length[d.lane],
							d.block, d.obs_name, d.obs_gap, d.lead_uid, d.lead_gap, str(d.in_conn)]
			else:
				still.erase(d.uid)


## Diagnostic (log only - the lane geometry is the WORLD module's): how far each approach lane is from
## the opposite-direction lane of its road over the last 40 m before the junction, and how far a lane
## polyline jogs sideways (max lateral distance of a point from the chord of its neighbours).
func _log_lane_spacing(k: int, approaches: PackedInt32Array) -> void:
	for a in approaches:
		var mind := INF
		var at := 0.0
		for o in L.opposite[a]:
			var s := maxf(L.length[a] - 40.0, 0.0)
			while s <= L.length[a]:
				var p := L.lane_point(a, s)
				var op: PackedVector3Array = L.pts[o]
				for i in range(1, op.size()):
					var c := Geometry3D.get_closest_point_to_segment(p, op[i - 1], op[i])
					var dd := Vector2(c.x - p.x, c.z - p.z).length()
					if dd < mind:
						mind = dd
						at = s
				s += 2.0
		var jog := 0.0
		var pts: PackedVector3Array = L.pts[a]
		for i in range(1, pts.size() - 1):
			var q := Geometry3D.get_closest_point_to_segment(pts[i], pts[i - 1], pts[i + 1])
			jog = maxf(jog, Vector2(q.x - pts[i].x, q.z - pts[i].z).length())
		TestHarness.log_line("junction %d approach lane %d (len %.0f, %d pts): min distance to the opposite lane %.2f m at s %.0f, max polyline jog %.2f m, opposite %s" % [
				k, a, L.length[a], pts.size(), mind, at, jog, str(L.opposite[a])])


## Impacts per vehicle-minute since `c0` (the collision counter counts each car of a contact).
func _impact_rate(c0: int) -> float:
	return float(int(sys.stats["collisions"]) - c0) / maxf(veh_sec / 60.0, 1.0)
