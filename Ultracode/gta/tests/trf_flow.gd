extends Node
## TRAFFIC flow test (headless, real world + vehicles boot).
##
## Phase 1 - focus override downtown, ~60 simulated seconds sampled every 0.5 s:
##   * at least 8 traffic vehicles present, most moving or legitimately waiting (no gridlock),
##   * nobody upside down, nobody runs a red light, cars waiting at a red stop behind the line,
##   * few collisions, lane keeping, manager cost.
## Phase M - the focus drives along a RoadGraph route (~13 m/s, like a player in a car): the population
##   stays up around the moving focus.
## Phase 2 - the focus jumps across the map (a teleport cut): the new area is filled at once, the old
##   cars despawn, the population is rebuilt there.
## Whole run (review additions): longest standstill of any car (true gridlock detector - a car that
##   waits forever at a junction counts as "flowing" in the phase 1 metric), longest wait at an
##   UNSIGNALISED junction (deadlock freedom of the permit rule), heading along the lane direction,
##   calm drivers within the speed limit, no active car held up by a frozen far car, every lane of
##   the graph on the right-hand side of its road.
## Then: release_vehicle() contract; parked cars exist near the focus and stay asleep.
##
## Run: tools\godot.ps1 -Mode headless -Frames 8000 -TimeoutSec 480 -UserArgs '--test=trf_flow','--test-timeout=460','--disable=police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug,pickups,interactions'
## Options: --trf_secs=60 (phase 1 length), --trf_hour=11, --seed=N (Game.rng: spawns, turns, personalities)

var sys: Node = null
var L: TrafficLanes = null
var samples: int = 0
var count_sum: int = 0
var count_min: int = 999
var flow_sum: float = 0.0
var moving_sum: float = 0.0
var upside_max: int = 0
var red_waiters: int = 0
var red_over: int = 0
var red_over_log: PackedStringArray = []
var not_flowing: Dictionary = {}       ## uid -> consecutive seconds
var worst_block: float = 0.0
var worst_info: String = ""
var speed_sum: float = 0.0
var speed_n: int = 0
# whole-run metrics (all phases)
var still: Dictionary = {}             ## uid -> consecutive seconds standing (|v| < 0.5)
var still_max: float = 0.0
var still_info: String = ""
var uwait: Dictionary = {}             ## uid -> consecutive seconds waiting at an unsignalised junction
var uwait_max: float = 0.0
var uwait_info: String = ""
var uwait_samples: int = 0
var speed_ratio_max: float = 0.0
var speed_info: String = ""
var heading_bad: int = 0
var heading_n: int = 0
var heading_info: String = ""
var ring_stall: int = 0


func _ready() -> void:
	await _run()


func _arg(name: String, def: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return def


func _run() -> void:
	sys = Game.get_system("traffic")
	if not TestHarness.check(sys != null and sys is TrafficSystem, "traffic system is registered"):
		TestHarness.finish(false, "no traffic system")
		return
	L = (sys as TrafficSystem).lanes
	if not TestHarness.check(L != null and L.count > 0, "lane cache built from the RoadGraph (%d lanes)" % (L.count if L != null else 0)):
		TestHarness.finish(false, "no lanes")
		return
	TestHarness.log_line("seed %s" % _arg("seed", "(default)"))
	_check_right_hand()
	var secs := float(_arg("trf_secs", "60"))
	var hour := float(_arg("trf_hour", "11"))
	if WorldClock.has_method("set_hour"):
		WorldClock.set_hour(hour)
	if "paused" in WorldClock:
		WorldClock.paused = true
	var focus := Vector3(0.0, 2.6, -60.0)       # Meridian Avenue, downtown
	sys.set_focus_override(focus)
	sys.set_enabled(false)                      # drop what spawned around the player at boot
	sys.set_enabled(true)                       # initial fill around the downtown focus
	await TestHarness.wait_physics_frames(10)
	var info: Dictionary = sys.get_debug_info()
	TestHarness.log_line("after initial fill: %s" % str(info))
	# 8 cars by day; at night the target is ~5 (time of day factor 0.32)
	var need := mini(8, maxi(int(float(info["target"]) * 0.6), 2))
	TestHarness.check(int(info["active"]) >= need, "initial fill spawns >= %d vehicles (%d, target %d)" % [need, int(info["active"]), int(info["target"])])

	# ---------------------------------------------------------------- phase 1: downtown flow
	var steps := int(secs / 0.5)
	for i in steps:
		await TestHarness.wait_seconds(0.5)
		_sample(0.5, true)
		if i % 20 == 19:
			TestHarness.log_line("t=%.0fs %s" % [float(i + 1) * 0.5, _brief()])
	var avg_count := float(count_sum) / maxf(float(samples), 1.0)
	var flow := flow_sum / maxf(float(samples), 1.0)
	var moving := moving_sum / maxf(float(samples), 1.0)
	var st: Dictionary = sys.get_debug_info()
	TestHarness.log_line("phase1: samples %d avg count %.1f min %d flowing %.2f moving %.2f avg speed %.1f m/s" % [samples, avg_count, count_min, flow, moving, speed_sum / maxf(float(speed_n), 1.0)])
	TestHarness.log_line("phase1 stats: %s" % str(st))
	TestHarness.log_line("worst non-flowing stretch %.1f s: %s" % [worst_block, worst_info])
	TestHarness.check(count_min >= need, "at least %d vehicles present the whole time (min %d, avg %.1f)" % [need, count_min, avg_count])
	TestHarness.check(flow >= 0.8, "traffic flows: %.0f %% of the cars move or wait legitimately (>= 80 %%)" % (flow * 100.0))
	TestHarness.check(moving >= 0.45, "most cars move: %.0f %% moving on average (>= 45 %%)" % (moving * 100.0))
	TestHarness.check(worst_block < 30.0, "no gridlock: longest non-flowing stretch of one car %.1f s (< 30 s)" % worst_block)
	TestHarness.check(upside_max == 0, "no vehicle upside down (max seen %d)" % upside_max)
	TestHarness.check(int(st["red_violations"]) == 0, "no red light violations (%d)" % int(st["red_violations"]))
	TestHarness.check(red_waiters > 0, "cars were seen waiting at red signals (%d samples)" % red_waiters)
	TestHarness.check(red_over == 0, "cars waiting at red stop behind the stop line (%d over: %s)" % [red_over, ", ".join(red_over_log)])
	var veh_minutes := avg_count * secs / 60.0
	var coll_rate := float(int(st["collisions"])) / maxf(veh_minutes, 1.0)
	TestHarness.check(coll_rate < 0.35, "few collisions: %d impacts in %.0f vehicle-minutes (%.2f / veh-min < 0.35)" % [int(st["collisions"]), veh_minutes, coll_rate])
	TestHarness.check(float(st.get("track_err_avg", 9.0)) < 0.25 and float(st.get("track_err_max", 9.0)) < 1.6,
			"cars keep their lane: cross-track error avg %.2f m, max %.2f m (< 0.25 / 1.6)" % [float(st.get("track_err_avg", 9.0)), float(st.get("track_err_max", 9.0))])
	TestHarness.check(float(st.get("think_ms_avg", 0.0)) < 1.5, "manager loop cost %.3f ms per physics frame (< 1.5)" % float(st.get("think_ms_avg", 0.0)))

	# ---------------------------------------------------------------- phase M: the focus drives across town
	var dest := _road_point(Vector3(120.0, 2.6, 70.0))
	var route: PackedVector3Array = L.roads.find_route(focus, dest) if L.roads.has_method("find_route") else PackedVector3Array()
	if route.size() < 2:
		route = PackedVector3Array([focus, dest])
	var cum := PackedFloat32Array([0.0])
	for i in range(1, route.size()):
		cum.append(cum[i - 1] + route[i].distance_to(route[i - 1]))
	var total := cum[cum.size() - 1]
	var near_sum := 0.0
	var near_min := 999
	var m_samples := 0
	var m_active_min := 999
	var dist_done := 0.0
	var m_spawned0 := int(sys.get_debug_info()["spawned"])
	while dist_done < total:
		for f in 15:
			await get_tree().physics_frame
			dist_done = minf(dist_done + 13.0 / 60.0, total)
			sys.set_focus_override(TrafficLanes.poly_point(route, cum, dist_done))
		_sample(0.25, false)
		var fp: Vector3 = sys.get_focus()
		var near := 0
		var active := 0
		for d: TrafficDriver in sys.get_drivers():
			if d.is_valid() and not d.frozen:
				active += 1
				if Vector2(d.body.global_position.x - fp.x, d.body.global_position.z - fp.z).length() < 110.0:
					near += 1
		m_samples += 1
		near_sum += near
		if m_samples > 8:          # the first 2 s: still the downtown population
			near_min = mini(near_min, near)
		m_active_min = mini(m_active_min, active)
	var stm: Dictionary = sys.get_debug_info()
	TestHarness.log_line("phase M: route %.0f m in %d samples, cars within 110 m avg %.1f min %d, active min %d, spawned %d during the drive | %s" % [
			total, m_samples, near_sum / maxf(float(m_samples), 1.0), near_min, m_active_min, int(stm["spawned"]) - m_spawned0, _brief()])
	var tgt := int(stm["target"])
	TestHarness.check(m_active_min >= mini(10, tgt - 2), "moving focus: the population stays up (active min %d, target %d)" % [m_active_min, tgt])
	TestHarness.check(near_sum / maxf(float(m_samples), 1.0) >= float(tgt) * 0.3, "moving focus: cars around the moving focus (avg %.1f within 110 m, target %d)" % [near_sum / maxf(float(m_samples), 1.0), tgt])

	# ---------------------------------------------------------------- phase 2: the focus jumps across the map (cut)
	var focus2 := _road_point(Vector3(-120.0, 2.6, 150.0))
	TestHarness.log_line("jump %.0f m to %s" % [Vector2(focus2.x - dest.x, focus2.z - dest.z).length(), str(focus2)])
	sys.set_focus_override(focus2)
	await TestHarness.wait_seconds(1.0)
	var near_cut := 0
	for d: TrafficDriver in sys.get_drivers():
		if d.is_valid() and not d.frozen and Vector2(d.body.global_position.x - focus2.x, d.body.global_position.z - focus2.z).length() < 175.0:
			near_cut += 1
	TestHarness.check(near_cut >= mini(10, int(sys.get_debug_info()["target"]) - 1), "teleport cut: the new place is filled at once (%d cars within 175 m after 1 s)" % near_cut)
	var far_left := 0
	var new_near := 0
	for i in 38:
		await TestHarness.wait_seconds(0.5)
		_sample(0.5, false)
	for d: TrafficDriver in sys.get_drivers():
		if not d.is_valid():
			continue
		var p := d.body.global_position
		if Vector2(p.x - focus2.x, p.z - focus2.z).length() > TrafficSystem.DESPAWN_DIST + 5.0 and not sys.is_seen(p):
			far_left += 1
		if Vector2(p.x - focus2.x, p.z - focus2.z).length() < 175.0 and not d.frozen:
			new_near += 1
	var st2: Dictionary = sys.get_debug_info()
	TestHarness.log_line("phase2: %s" % str(st2))
	TestHarness.check(far_left == 0, "cars left far behind (> %.0f m, unseen) were despawned (%d left)" % [TrafficSystem.DESPAWN_DIST, far_left])
	TestHarness.check(int(st2["red_violations"]) == 0, "still no red light violations after the moves (%d)" % int(st2["red_violations"]))
	TestHarness.check(new_near >= need, "population rebuilt around the new focus within 20 s (%d near, %d active)" % [new_near, int(st2["active"])])
	var mix := {}
	var lit := 0
	for d: TrafficDriver in sys.get_drivers():
		if d.is_valid():
			mix[d.spec_id] = int(mix.get(d.spec_id, 0)) + 1
			if int(d.veh.get("headlight_mode")) > 0:
				lit += 1
	TestHarness.log_line("spec mix now: %s | headlights on: %d of %d (hour %.1f)" % [str(mix), lit, sys.get_drivers().size(), float(WorldClock.hour)])
	if WorldClock.get_daylight() < 0.3:
		TestHarness.check(lit >= sys.get_drivers().size() - 1, "night: traffic drives with headlights (%d of %d)" % [lit, sys.get_drivers().size()])

	# ---------------------------------------------------------------- whole run
	TestHarness.log_line("whole run: longest standstill %.1f s (%s) | longest unsignalised wait %.1f s (%s), %d waiting samples | max speed / limit %.2f (%s) | heading off %d of %d (%s) | ring stalls %d, frozen blockers removed %d, reroutes %d, bypass aborts %d" % [
			still_max, still_info, uwait_max, uwait_info, uwait_samples, speed_ratio_max, speed_info, heading_bad, heading_n, heading_info,
			ring_stall, int(st2.get("frozen_blockers", 0)), int(st2.get("reroutes", 0)), int(st2.get("bypass_aborts", 0))])
	TestHarness.check(still_max < 50.0, "no car stands still for 50 s anywhere (longest %.1f s)" % still_max)
	TestHarness.check(uwait_max < 20.0, "unsignalised junctions never deadlock: longest wait %.1f s (< 20 s)" % uwait_max)
	TestHarness.check(speed_ratio_max < 1.2, "calm drivers keep to the limit: max speed %.2f x limit (< 1.2)" % speed_ratio_max)
	TestHarness.check(heading_n > 100 and float(heading_bad) / float(heading_n) < 0.01, "cars drive along their lane direction (%d of %d samples off)" % [heading_bad, heading_n])
	TestHarness.check(ring_stall <= 2, "no driving car is held up by a frozen far car (%d samples)" % ring_stall)

	# ---------------------------------------------------------------- release_vehicle
	var pick: TrafficDriver = null
	for d: TrafficDriver in sys.get_drivers():
		if d.is_valid() and not d.frozen:
			pick = d
			break
	if TestHarness.check(pick != null, "a driver to release"):
		var v := pick.body
		var before: int = sys.get_vehicle_count()
		TestHarness.check(v.has_meta("ai_controller") and v.get_meta("ai_controller") == sys, "ai_controller meta is set on traffic vehicles")
		TestHarness.check(v.get("driver") == pick.dummy and pick.dummy != null, "vehicle.driver is the seated dummy")
		var npc: Node3D = sys.release_vehicle(v, "abandon")
		await TestHarness.wait_physics_frames(2)
		TestHarness.check(is_instance_valid(v) and not v.has_meta("ai_controller"), "release_vehicle removes the ai_controller meta")
		TestHarness.check(is_instance_valid(v) and v.get("driver") == null, "release_vehicle leaves driver == null")
		TestHarness.check(sys.get_vehicle_count() == before - 1, "released car is no longer simulated (%d -> %d)" % [before, sys.get_vehicle_count()])
		if Game.get_system("peds") != null:
			TestHarness.check(npc != null and is_instance_valid(npc), "the driver got out as a real NPC")
		else:
			TestHarness.log_line("peds system not running: release_vehicle returned %s (no NPC possible)" % str(npc))
		TestHarness.check(sys.release_vehicle(v, "abandon") == null, "releasing an uncontrolled vehicle is a no-op")

	# ---------------------------------------------------------------- parked cars
	var parked: int = sys.get_parked_count()
	var asleep: int = sys.parking.asleep_count()
	TestHarness.log_line("parked %d asleep %d spawned_total %d released %d bays %d (skipped near junctions %d)" % [parked, asleep,
			sys.parking.spawned_total, sys.parking.released_total, sys.parking.bays.size(), sys.parking.skipped_near_junction])
	TestHarness.check(parked >= 5, "parked cars exist near the focus (%d)" % parked)
	TestHarness.check(parked > 0 and float(asleep) >= float(parked) * 0.9, "parked cars stay asleep (%d of %d)" % [asleep, parked])
	var tag_ok := true
	for e: Array in sys.parking.parked:
		var pv: Variant = e[1]
		if is_instance_valid(pv) and (str(pv.get("owner_tag")) != "parked" or bool(pv.get("engine_on"))):
			tag_ok = false
	TestHarness.check(tag_ok, "parked cars: owner_tag 'parked', engine off")
	TestHarness.finish()


## Nearest lane point to `p` (so a focus is always on a road).
func _road_point(p: Vector3) -> Vector3:
	var nl: Dictionary = L.roads.get_nearest_lane(p, 80.0)
	if nl.is_empty():
		return p
	return nl["point"]


## Every drivable lane lies on the right-hand side of its road's centre line.
func _check_right_hand() -> void:
	var segs: Array = L.roads.get("segments")
	var bad := 0
	var n := 0
	var info := ""
	for i in L.count:
		if L.kind[i] > TrafficLanes.KIND_ALLEY or L.length[i] < 4.0:
			continue
		var sd: Dictionary = segs[L.seg[i]]
		var cp: PackedVector3Array = sd["points"]
		if cp.size() < 2:
			continue
		var mid := L.lane_point(i, L.length[i] * 0.5)
		var dir := L.lane_dir(i, L.length[i] * 0.5)
		# nearest point of the road centre line
		var best := INF
		var bc := Vector3.ZERO
		for k in range(1, cp.size()):
			var c := Geometry3D.get_closest_point_to_segment(mid, cp[k - 1], cp[k])
			var dd := Vector2(c.x - mid.x, c.z - mid.z).length()
			if dd < best:
				best = dd
				bc = c
		var right := Vector3(-dir.z, 0.0, dir.x)
		n += 1
		if (mid - bc).dot(right) <= 0.05:
			bad += 1
			if info == "":
				info = "lane %d seg %d" % [i, L.seg[i]]
	TestHarness.log_line("right-hand lanes: %d checked, %d not right of the centre line %s" % [n, bad, info])
	TestHarness.check(n > 50 and bad == 0, "right-hand traffic: every lane is right of its road centre line (%d / %d)" % [bad, n])


func _brief() -> String:
	var i: Dictionary = sys.get_debug_info()
	return "active %d mov %d wait %d queue %d blocked %d frozen %d coll %d lc %d byp %d rev %d honk %d stuck_desp %d frz_blk %d ms %.3f" % [
		int(i["active"]), int(i["moving"]), int(i["waiting"]), int(i["queue"]), int(i["blocked"]),
		int(i["frozen"]), int(i["collisions"]), int(i["lane_changes"]), int(i["bypasses"]),
		int(i["reverses"]), int(i["honks"]), int(i["stuck_despawns"]), int(i.get("frozen_blockers", 0)), float(i.get("think_ms_avg", 0.0))]


func _describe(d: TrafficDriver) -> String:
	return "uid %d %s lane %d s %.1f/%.1f block %d wait %.1f obs %s kind %d gap %.1f lead %d %.1f pos %s" % [d.uid, d.spec_id, d.lane, d.s,
			L.length[d.lane], d.block, d.wait_t, d.obs_name, d.obs_kind, d.obs_gap, d.lead_uid, d.lead_gap,
			str(d.body.global_position.snapped(Vector3.ONE * 0.1))]


func _sample(dt: float, phase1: bool) -> void:
	var ds: Array[TrafficDriver] = sys.get_drivers()
	var n := 0
	var flowing := 0
	var moving := 0
	var upside := 0
	var seen: Dictionary = {}
	for d: TrafficDriver in ds:
		if not d.is_valid() or d.frozen:
			continue
		n += 1
		seen[d.uid] = true
		var spd := absf(d.speed)
		if spd > 1.0:
			moving += 1
			speed_sum += spd
			speed_n += 1
		var ok: bool = sys.is_flowing(d)
		if ok:
			flowing += 1
			not_flowing.erase(d.uid)
		elif phase1:
			var t := float(not_flowing.get(d.uid, 0.0)) + dt
			not_flowing[d.uid] = t
			if t > worst_block:
				worst_block = t
				worst_info = _describe(d)
		# true standstill, whatever the classification says
		if spd < 0.5:
			var ts := float(still.get(d.uid, 0.0)) + dt
			still[d.uid] = ts
			if ts > still_max:
				still_max = ts
				still_info = _describe(d)
		else:
			still.erase(d.uid)
		# waiting at an unsignalised junction (right-of-way permits only)
		if d.block == TrafficDriver.Block.WAIT and not d.in_conn and L.sig[d.lane] < 0:
			uwait_samples += 1
			var tw := float(uwait.get(d.uid, 0.0)) + dt
			uwait[d.uid] = tw
			if tw > uwait_max:
				uwait_max = tw
				uwait_info = _describe(d)
		else:
			uwait.erase(d.uid)
		# calm drivers within the limit (a few metres into a new lane: the junction is behind them)
		if d.panic_t <= 0.0 and spd > 3.0 and not d.in_conn and d.s > 8.0:
			var r := spd / maxf(L.limit[d.lane], 1.0)
			if r > speed_ratio_max:
				speed_ratio_max = r
				speed_info = "uid %d %s v %.1f limit %.1f factor %.2f s %.1f" % [d.uid, d.spec_id, spd, L.limit[d.lane], d.speed_factor, d.s]
		# heading along the lane (not in a junction curve, not mid lane change / bypass / reversing)
		if not d.in_conn and spd > 3.0 and d.lc_t <= 0.0 and d.bypass_t <= 0.0 and d.reverse_t <= 0.0 and d.s > 3.0:
			heading_n += 1
			var f := -d.body.global_transform.basis.z
			f.y = 0.0
			if f.normalized().dot(L.lane_dir(d.lane, d.s)) < 0.7:
				heading_bad += 1
				if heading_info == "":
					heading_info = _describe(d)
		# held up by a frozen car (the 170 m ring)
		if spd < 0.5 and d.lead_uid >= 0 and d.lead_gap < 40.0:
			for k: TrafficDriver in ds:
				if k.uid == d.lead_uid and k.frozen:
					ring_stall += 1
					break
		if d.body.global_transform.basis.y.y < 0.3:
			upside += 1
		if not d.in_conn and d.lane >= 0 and L.sig[d.lane] >= 0 and L.signal_state(d.lane) == 2 and spd < 0.3:
			var front := d.s + d.half_len
			if L.length[d.lane] - front < 10.0:
				red_waiters += 1
				if front - L.length[d.lane] > 0.8:
					red_over += 1
					if red_over_log.size() < 6:
						red_over_log.append("uid %d over %.1f m" % [d.uid, front - L.length[d.lane]])
	for k: Variant in not_flowing.keys():
		if not seen.has(k):
			not_flowing.erase(k)
	for k: Variant in still.keys():
		if not seen.has(k):
			still.erase(k)
	for k: Variant in uwait.keys():
		if not seen.has(k):
			uwait.erase(k)
	if not phase1:
		return
	samples += 1
	count_sum += n
	count_min = mini(count_min, n)
	if n > 0:
		flow_sum += float(flowing) / float(n)
		moving_sum += float(moving) / float(n)
	upside_max = maxi(upside_max, upside)
