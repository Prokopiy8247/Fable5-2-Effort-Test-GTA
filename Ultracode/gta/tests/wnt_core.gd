extends Node
## Wanted system core test (headless). No real player / world: a dummy Node3D in group "player"
## is registered with Game.set_player(). Timers are sped up with Wanted.debug_time_scale.
##   tools\godot.ps1 -Mode headless -Frames 12000 -TimeoutSec 300 -UserArgs '--test=wnt_core','--no_player','--disable=world,environment,city,props,interactions,vehicles,pickups,traffic,peds,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug','--test-timeout=240'
## Covers: tables, unwitnessed crime in a deserted place, direct witness stars per the tables,
## non-violent cap, witness-report path (+ duplicates, dead witness, call grace, late call),
## police-sighting window, loud indirect report (+ deserted / suppressed), pending expiry,
## PURSUIT -> SEARCH -> escape for every level, sighting resumes pursuit, vehicle / appearance
## benefit, bust flow + arrestability, set_level / clear / enabled, resisting escalation,
## force_pursuit, stinger routing, every signal fired exactly once.

const DESERTED := Vector3(40.0, 2.0, -900.0)   ## far from anything
const FAR := Vector3(900.0, 0.0, 0.0)          ## offset that puts the player outside any search circle

var T: Node
var _dummy: Node3D
var _ev_level: Array = []        ## [level, previous]
var _ev_state: Array = []        ## state ints
var _ev_cleared: Array = []      ## reasons
var _ev_reported: Array = []     ## crime ids (EventBus.crime_reported)
var _ev_expired: Array = []      ## crime ids (Wanted.crime_expired)
var _ev_busted: int = 0
var _ev_disguise: Array = []
var _extra: Array[Node] = []


func _ready() -> void:
	T = TestHarness
	await T.wait_frames(5)
	_setup()
	await _test_tables()
	await _test_deserted()
	await _test_direct_witness()
	await _test_witness_reports()
	await _test_sighting_window()
	await _test_loud_indirect()
	await _test_escape_per_level()
	await _test_resume_pursuit()
	await _test_disguise()
	await _test_bust()
	await _test_level_api()
	await _test_resisting()
	await _test_misc()
	_teardown()
	T.finish()


# --- helpers -----------------------------------------------------------------------------------

func _setup() -> void:
	_dummy = Node3D.new()
	_dummy.name = "WntDummyPlayer"
	add_child(_dummy)
	_dummy.add_to_group("player")
	_dummy.global_position = DESERTED
	Game.set_player(_dummy)
	EventBus.wanted_level_changed.connect(func(l: int, p: int) -> void: _ev_level.append([l, p]))
	EventBus.wanted_state_changed.connect(func(s: int) -> void: _ev_state.append(s))
	EventBus.wanted_cleared.connect(func(r: String) -> void: _ev_cleared.append(r))
	EventBus.crime_reported.connect(func(id: String, _p: Vector3) -> void: _ev_reported.append(id))
	EventBus.player_busted.connect(func() -> void: _ev_busted += 1)
	Wanted.crime_expired.connect(func(id: String, _p: Vector3) -> void: _ev_expired.append(id))
	Wanted.disguise_applied.connect(func(k: String, _e: float, _r: float) -> void: _ev_disguise.append(k))


func _teardown() -> void:
	Wanted.clear("cheat")
	Wanted.debug_time_scale = 1.0
	Wanted.enabled = true
	for n in _extra:
		if is_instance_valid(n):
			n.queue_free()
	Game.player = null


## Clean slate between scenarios: not wanted, no records, events cleared.
func _reset(scale: float = 1.0) -> void:
	Wanted.enabled = true
	Wanted.clear("cheat")
	Wanted.debug_time_scale = scale
	Wanted.time_since_player_attack = 9999.0
	_dummy.global_position = DESERTED
	_ev_level.clear()
	_ev_state.clear()
	_ev_cleared.clear()
	_ev_reported.clear()
	_ev_expired.clear()
	_ev_disguise.clear()
	_ev_busted = 0


## Advance the Wanted clock by `sec` Wanted-seconds (game time x debug_time_scale).
func _adv(sec: float) -> void:
	var target: float = Wanted._clock + sec
	var guard := 0
	while Wanted._clock < target - 0.0001 and guard < 30000:
		await get_tree().process_frame
		guard += 1


## Advance until `cond` is true (Wanted-seconds limit). Returns the Wanted-seconds waited.
func _adv_until(cond: Callable, limit: float) -> float:
	var start: float = Wanted._clock
	var guard := 0
	while not bool(cond.call()) and Wanted._clock - start < limit and guard < 30000:
		await get_tree().process_frame
		guard += 1
	return Wanted._clock - start


func _scripted(source: String) -> Node3D:
	var gs := GDScript.new()
	gs.source_code = source
	gs.reload()
	var n := Node3D.new()
	n.set_script(gs)
	add_child(n)
	_extra.append(n)
	return n


func _peds_at(center: Vector3, count: int, spread: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for i in count:
		var p := Node3D.new()
		p.name = "WntPed%d" % i
		add_child(p)
		p.add_to_group("ped")
		p.global_position = center + Vector3(cos(float(i)) * spread, 0.0, sin(float(i)) * spread)
		out.append(p)
		_extra.append(p)
	return out


func _free_all(nodes: Array[Node3D]) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.remove_from_group("ped")
			n.queue_free()


func _near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


# --- tests -------------------------------------------------------------------------------------

func _test_tables() -> void:
	var ok_keys := true
	for id: String in Wanted.CRIME_HEAT:
		if not Wanted.Config.CRIMES.has(id):
			ok_keys = false
	for id: String in Wanted.Config.CRIMES:
		if not Wanted.CRIME_HEAT.has(id):
			ok_keys = false
	T.check(ok_keys and Wanted.CRIME_HEAT.size() >= 16, "tables: CRIME_HEAT and CRIMES list the same %d crime ids" % Wanted.CRIME_HEAT.size())
	T.check(Wanted.HEAT_THRESHOLDS.size() == 5 and Wanted.ESCAPE_SECONDS.size() == 5, "tables: 5 heat thresholds / escape times")
	var need := ["officers", "cruisers", "swat_vans", "heli", "roadblocks", "lethal", "respawn_interval", "search_radius", "escape_seconds"]
	var keys_ok := true
	var caps_ok := true
	var mono_ok := true
	var prev_escape := 0.0
	var prev_radius := 0.0
	for lvl in range(1, 6):
		var c: Dictionary = Wanted.get_level_config(lvl)
		for k: String in need:
			if not c.has(k):
				keys_ok = false
		if int(c["officers"]) > 16 or int(c["cruisers"]) + int(c["swat_vans"]) > 8 or int(c["heli"]) > 1:
			caps_ok = false
		if float(c["escape_seconds"]) <= prev_escape or float(c["search_radius"]) <= prev_radius:
			mono_ok = false
		prev_escape = float(c["escape_seconds"])
		prev_radius = float(c["search_radius"])
	T.check(keys_ok, "get_level_config(1..5) has every W2.3 key")
	T.check(caps_ok, "level configs respect the unit caps (<= 16 officers, <= 8 vehicles, <= 1 heli)")
	T.check(mono_ok, "escape time and search radius grow with the level")
	T.check(not bool(Wanted.get_level_config(1)["lethal"]) and bool(Wanted.get_level_config(2)["lethal"])
			and int(Wanted.get_level_config(3)["heli"]) == 1 and int(Wanted.get_level_config(3)["roadblocks"]) > 0
			and int(Wanted.get_level_config(4)["swat_vans"]) > 0,
			"level intent: 1 star non-lethal, 2 lethal, 3 heli + roadblocks, 4 SWAT")
	T.check(is_equal_approx(Wanted.get_escape_time_required(), float(Wanted.ESCAPE_SECONDS[0])), "get_escape_time_required() at 0 stars = 1-star time")
	await T.wait_frames(1)


func _test_deserted() -> void:
	_reset(10.0)
	Wanted.report_crime("gunfire", DESERTED, {"instigator": _dummy})
	Wanted.report_crime("assault", DESERTED + Vector3(2, 0, 0), {"instigator": _dummy, "victim": null})
	T.check(Wanted.level == 0 and Wanted.get_pending_count() == 2, "deserted: unwitnessed crimes stay pending (%d), no stars" % Wanted.get_pending_count())
	T.check(int(Wanted.get_crime_records()[0]["listeners"]) == 0, "deserted: nobody within earshot of the gunfire")
	await _adv(Wanted.Config.PENDING_TTL + 1.0)
	T.check(Wanted.level == 0 and _ev_level.is_empty() and _ev_reported.is_empty(), "deserted: still no stars after the pending window")
	T.check(Wanted.get_pending_count() == 0 and _ev_expired.size() == 2, "deserted: both pending crimes expired (%s)" % str(_ev_expired))
	T.check(Wanted.time_since_last_crime > Wanted.Config.PENDING_TTL, "time_since_last_crime counts up (%.1f)" % Wanted.time_since_last_crime)


func _test_direct_witness() -> void:
	_reset()
	Wanted.report_crime("assault", DESERTED, {"direct_police_witness": true, "instigator": _dummy})
	T.check(Wanted.level == 1 and Wanted.state == Wanted.State.PURSUIT, "direct witness: assault -> 1 star, PURSUIT")
	T.check(_near(Wanted.heat, 0.6, 0.001), "direct witness: heat = CRIME_HEAT.assault (%.2f)" % Wanted.heat)
	T.check(_ev_level == [[1, 0]] and _ev_state == [Wanted.State.PURSUIT] and _ev_reported == ["assault"],
			"direct witness: level / state / crime_reported signals fired once each")
	T.check(Wanted.last_known_position.is_equal_approx(DESERTED) and Wanted.player_visible_to_police, "direct witness: last known position = crime position, visible")
	Wanted.clear("cheat")
	T.check(_ev_cleared == ["cheat"] and _ev_level.back() == [0, 1] and Wanted.state == Wanted.State.NONE, "clear: wanted_cleared once, level 0, NONE")

	_reset()
	Wanted.report_crime("murder", DESERTED, {"direct_police_witness": true})
	T.check(Wanted.level == 2, "direct witness: murder -> 2 stars (min_level)")
	Wanted.report_crime("murder", DESERTED, {"direct_police_witness": true})
	# the first murder lifted heat to the 2-star threshold (1.6), the second adds 1.4
	T.check(Wanted.level == 2 and _near(Wanted.heat, 3.0, 0.01), "two murders -> heat 3.0, still 2 stars (%.2f)" % Wanted.heat)
	Wanted.report_crime("cop_murder", DESERTED, {"direct_police_witness": true})
	T.check(Wanted.level == 3, "+ cop murder -> 3 stars (heat %.2f)" % Wanted.heat)
	Wanted.report_crime("explosion", DESERTED, {"direct_police_witness": true})
	T.check(Wanted.level == 4, "+ explosion -> 4 stars (heat %.2f)" % Wanted.heat)
	T.check(_ev_level == [[2, 0], [3, 2], [4, 3]], "escalation emitted one level signal per step (%s)" % str(_ev_level))

	_reset()
	for i in 6:
		Wanted.report_crime("police_vehicle_theft", DESERTED, {"direct_police_witness": true})
	T.check(Wanted.level == 3 and not Wanted.episode_violent, "non-violent crimes are capped at 3 stars (heat %.2f)" % Wanted.heat)
	Wanted.report_crime("assault", DESERTED, {"direct_police_witness": true})
	T.check(Wanted.level == 4 and Wanted.episode_violent, "a violent crime lifts the cap: 4 stars, not 5 (no banked heat)")

	_reset()
	Wanted.report_crime("assault", DESERTED, {"direct_police_witness": true, "severity": 3.0})
	T.check(Wanted.level == 2, "severity 3 assault -> heat 1.8 -> 2 stars")
	_reset()
	Wanted.report_crime("disturbance", DESERTED, {"force": true})
	T.check(Wanted.level == 1 and Wanted.state == Wanted.State.PURSUIT, "opts.force skips witness logic")
	_reset()
	Wanted.report_crime("jaywalking_custom", DESERTED, {"direct_police_witness": true})
	T.check(Wanted.level == 1, "unknown crime id uses the default row")
	_reset()
	Wanted.report_crime("cop_murder", DESERTED, {})
	T.check(Wanted.level == 3 and Wanted.state == Wanted.State.SEARCH, "cop murder is known without witnesses (radio) -> 3 stars, SEARCH at the scene")
	_reset()
	var cop := _scripted("extends Node3D\nvar is_dead := false\n")
	cop.add_to_group("police")
	Wanted.report_crime("cop_assault", DESERTED, {"victim": cop})
	T.check(Wanted.level == 2 and Wanted.state == Wanted.State.PURSUIT, "assaulting a living officer: he saw it -> 2 stars, PURSUIT")
	cop.remove_from_group("police")
	_reset()
	await T.wait_frames(1)


func _test_witness_reports() -> void:
	_reset(4.0)
	var witness := _scripted("extends Node3D\nvar is_dead := false\n")
	var p := DESERTED + Vector3(10, 0, 10)
	Wanted.report_crime("assault", p, {"instigator": _dummy})
	T.check(Wanted.level == 0 and Wanted.get_pending_count() == 1, "witness: crime pending before the call")
	await _adv(3.0)
	Wanted.report_witnessed("assault", p + Vector3(3, 0, -2), witness)
	T.check(Wanted.level == 1 and Wanted.state == Wanted.State.SEARCH, "witness report -> 1 star, SEARCH (police have not seen the player)")
	T.check(Wanted.last_known_position.is_equal_approx(p) and Wanted.search_center.is_equal_approx(p), "witness report: search starts at the crime scene")
	T.check(_ev_reported == ["assault"] and _ev_level == [[1, 0]] and _ev_state == [Wanted.State.SEARCH], "witness report: signals once")
	var h: float = Wanted.heat
	Wanted.report_witnessed("assault", p, witness)
	T.check(is_equal_approx(Wanted.heat, h) and _ev_reported.size() == 1, "a second call about the same crime is a duplicate")

	_reset(4.0)
	var dead := _scripted("extends Node3D\nvar is_dead := true\n")
	Wanted.report_crime("robbery", p, {})
	Wanted.report_witnessed("robbery", p, dead)
	T.check(Wanted.level == 0 and Wanted.get_pending_count() == 1, "a dead witness cannot call it in")

	_reset(10.0)
	Wanted.report_crime("vehicle_theft", p, {})
	await _adv(Wanted.Config.PENDING_TTL + 0.5)
	T.check(_ev_expired == ["vehicle_theft"], "pending crime expired after PENDING_TTL")
	Wanted.report_witnessed("vehicle_theft", p, witness)
	T.check(Wanted.level == 0, "a call about an expired crime comes too late: no stars")

	_reset(10.0)
	Wanted.report_crime("assault", p, {})
	EventBus.crime_witnessed.emit("assault", p, witness)
	await _adv(Wanted.Config.PENDING_TTL + 5.0)
	T.check(Wanted.get_pending_count() == 1 and _ev_expired.is_empty(), "crime_witnessed (call in progress) keeps the crime pending longer")
	Wanted.report_witnessed("assault", p, witness)
	T.check(Wanted.level == 1, "the slow call still completes -> 1 star")

	_reset()
	Wanted.report_witnessed("disturbance", p, witness)
	T.check(Wanted.level == 1 and Wanted.state == Wanted.State.SEARCH, "an independent witness observation (no report_crime) is accepted")
	_reset()


func _test_sighting_window() -> void:
	_reset()
	Wanted.police_sighting(null, DESERTED)
	T.check(Wanted.level == 0 and Wanted.state == Wanted.State.NONE, "a sighting alone does not make the player wanted")
	Wanted.report_crime("assault", DESERTED, {})
	T.check(Wanted.level == 1 and Wanted.state == Wanted.State.PURSUIT, "crime right after a police sighting is known at once")

	_reset()
	Wanted.report_crime("assault", DESERTED, {})
	await _adv(0.5)
	T.check(Wanted.level == 0, "sighting window: still pending before the sighting")
	Wanted.police_sighting(null, DESERTED + Vector3(1, 0, 0))
	T.check(Wanted.level == 1 and Wanted.state == Wanted.State.PURSUIT, "police sighting 0.5 s after the crime -> known, PURSUIT")

	_reset()
	Wanted.report_crime("assault", DESERTED, {})
	await _adv(2.0)
	Wanted.police_sighting(null, DESERTED)
	T.check(Wanted.level == 0 and Wanted.get_pending_count() == 1, "police sighting 2 s after the crime: they did not see it")
	await _adv(1.0)
	T.check(not Wanted.player_visible_to_police, "player_visible_to_police times out without new sightings")
	_reset()


func _test_loud_indirect() -> void:
	_reset(4.0)
	var c := DESERTED + Vector3(0, 0, 300)
	var peds := _peds_at(c, 3, 20.0)
	Wanted.report_crime("gunfire", c, {"instigator": _dummy})
	Wanted.report_crime("gunfire", c + Vector3(4, 0, 0), {"instigator": _dummy})
	var recs: Array[Dictionary] = Wanted.get_crime_records()
	T.check(Wanted.get_pending_count() == 1 and recs.size() == 1 and int(recs[0]["events"]) == 2,
			"loud: a second burst close by merges into the same pending report")
	T.check(int(recs[0]["listeners"]) == 3, "loud: 3 people within earshot (%d)" % int(recs[0]["listeners"]))
	var due: float = float(recs[0]["due_in"])
	T.check(due >= Wanted.Config.INDIRECT_DELAY_MIN - 0.01 and due <= Wanted.Config.INDIRECT_DELAY_MAX + 0.01, "loud: indirect report due in %.1f s (6-10)" % due)
	await _adv(5.8)
	T.check(Wanted.level == 0, "loud: no stars before 6 s")
	var waited := await _adv_until(func() -> bool: return Wanted.level > 0, 6.0)
	T.check(Wanted.level == 1 and Wanted.state == Wanted.State.SEARCH, "loud: indirect report after %.1f s more -> 1 star, SEARCH" % waited)
	T.check(Wanted.last_known_position.distance_to(c) <= Wanted.Config.INDIRECT_POSITION_ERROR * 1.5 + 5.0, "loud: search centred near the shots (%.1f m off)" % Wanted.last_known_position.distance_to(c))
	T.check(_ev_reported == ["gunfire"] and Wanted.get_pending_count() == 0, "loud: one report for the merged bursts")
	# a gunshot heard while searching re-centres the search
	await _adv(4.0)
	var c2 := c + Vector3(10, 0, 20)
	Wanted.report_crime("gunfire", c2, {"instigator": _dummy})
	var last_prog: float = Wanted.escape_progress
	var guard := 0
	while _ev_reported.size() < 2 and guard < 3000:
		last_prog = Wanted.escape_progress
		await get_tree().process_frame
		guard += 1
	T.check(_ev_reported.size() == 2 and Wanted.last_known_position.distance_to(c2) < 25.0
			and last_prog > 0.1 and Wanted.escape_progress <= last_prog * (1.0 - Wanted.Config.REPORT_PROGRESS_LOSS) + 0.02,
			"loud: shots during SEARCH re-centre the search and cost escape progress (%.2f -> %.2f)" % [last_prog, Wanted.escape_progress])

	# suppressed shot: the noise radius (12 m) is the earshot radius -> the peds 20 m away hear nothing
	_reset(10.0)
	EventBus.noise_emitted.emit(c, 12.0, "suppressed_gunshot", _dummy)
	Wanted.report_crime("gunfire", c, {"instigator": _dummy})
	recs = Wanted.get_crime_records()
	T.check(recs.size() == 1 and int(recs[0]["listeners"]) == 0, "loud: a suppressed shot (12 m noise) is not heard 20 m away")
	await _adv(Wanted.Config.PENDING_TTL + 1.0)
	T.check(Wanted.level == 0, "loud: unheard suppressed shot -> no stars")
	_free_all(peds)
	await T.wait_frames(2)
	_reset()


func _test_escape_per_level() -> void:
	var ok_times := true
	var details := PackedStringArray()
	for lvl in range(1, 6):
		_reset(20.0)
		var cfg: Dictionary = Wanted.get_level_config(lvl)
		Wanted.set_level(lvl)
		Wanted.police_sighting(null, DESERTED)
		var ok_start: bool = Wanted.level == lvl and Wanted.state == Wanted.State.PURSUIT
		await _adv(float(cfg["lost_contact_grace"]) - 0.5)
		var still_pursuit: bool = Wanted.state == Wanted.State.PURSUIT
		await _adv_until(func() -> bool: return Wanted.state == Wanted.State.SEARCH, 2.0)
		var searching: bool = Wanted.state == Wanted.State.SEARCH and _near(Wanted.search_radius, float(cfg["search_radius"]), 0.5)
		var t_search: float = Wanted._clock - Wanted.time_in_state
		_dummy.global_position = DESERTED + FAR
		await _adv(float(cfg["escape_seconds"]) * 0.5)
		var half_ok: bool = _near(Wanted.escape_progress, 0.5, 0.03) and Wanted.level == lvl
		var grown: bool = Wanted.search_radius > float(cfg["search_radius"]) and Wanted.search_radius <= float(cfg["search_radius_max"])
		await _adv_until(func() -> bool: return Wanted.level == 0, float(cfg["escape_seconds"]))
		var took: float = Wanted._clock - t_search
		var escaped: bool = Wanted.level == 0 and _ev_cleared == ["escaped"] and _near(took, float(cfg["escape_seconds"]), 0.6)
		var sig_ok: bool = _ev_level.back() == [0, lvl] and _ev_state == [Wanted.State.PURSUIT, Wanted.State.SEARCH, Wanted.State.NONE]
		details.append("%d*: %.1fs/%.0fs" % [lvl, took, float(cfg["escape_seconds"])])
		if not (ok_start and still_pursuit and searching and half_ok and grown and escaped and sig_ok):
			ok_times = false
			T.log_line("escape lvl %d: start %s grace %s search %s half %s (%.2f) grown %s escaped %s sig %s %s" % [lvl, ok_start, still_pursuit, searching, half_ok, Wanted.escape_progress, grown, escaped, sig_ok, str(_ev_state)])
	T.check(ok_times, "PURSUIT -> SEARCH after the grace -> escaped after the level's escape time, 1..5 stars (%s)" % ", ".join(details))

	# inside the search circle the escape is slower (hiding vs leaving the area)
	_reset(20.0)
	Wanted.set_level(2)
	Wanted.police_sighting(null, DESERTED)
	await _adv_until(func() -> bool: return Wanted.state == Wanted.State.SEARCH, 6.0)
	await _adv(10.0)
	var expect := 10.0 * Wanted.Config.INSIDE_SEARCH_RATE / float(Wanted.get_level_config(2)["escape_seconds"])
	T.check(_near(Wanted.escape_progress, expect, 0.03), "inside the search circle escape runs at %.0f%% (%.3f ~ %.3f)" % [Wanted.Config.INSIDE_SEARCH_RATE * 100.0, Wanted.escape_progress, expect])
	var hud: Variant = UI.get("hud") if UI != null else null
	if hud != null and is_instance_valid(hud) and (hud as Object).has_method("get_state"):
		await T.wait_frames(3)
		T.check(int((hud as Object).call("get_state")["wanted_state"]) == Wanted.State.SEARCH, "HUD shows the SEARCH (flashing) state")
	_reset()


func _test_resume_pursuit() -> void:
	_reset(20.0)
	Wanted.set_level(2)
	Wanted.police_sighting(null, DESERTED)
	await _adv_until(func() -> bool: return Wanted.state == Wanted.State.SEARCH, 6.0)
	_dummy.global_position = DESERTED + FAR
	await _adv(9.0)
	var p_before: float = Wanted.escape_progress
	_ev_state.clear()
	Wanted.police_sighting(null, _dummy.global_position)
	T.check(p_before > 0.2 and Wanted.state == Wanted.State.PURSUIT and Wanted.escape_progress == 0.0 and Wanted.level == 2,
			"a sighting during SEARCH resumes PURSUIT and resets the escape progress (was %.2f)" % p_before)
	T.check(_ev_state == [Wanted.State.PURSUIT] and Wanted.last_known_position.is_equal_approx(_dummy.global_position), "resume: one state signal, last known position updated")
	await _adv_until(func() -> bool: return Wanted.state == Wanted.State.SEARCH, 6.0)
	T.check(Wanted.state == Wanted.State.SEARCH and Wanted.escape_progress < 0.05, "contact lost again -> SEARCH starts from zero")
	_reset()


func _test_disguise() -> void:
	_reset(20.0)
	Wanted.set_level(2)
	Wanted.police_sighting(null, DESERTED)          # seen on foot
	await _adv_until(func() -> bool: return Wanted.state == Wanted.State.SEARCH, 6.0)
	await _adv(3.0)
	var p0: float = Wanted.escape_progress
	var rem0: float = Wanted.get_escape_time_remaining()
	var rd0: float = Wanted.get_recognition_delay()
	var car_a := Node3D.new()
	var car_b := Node3D.new()
	var car_c := Node3D.new()
	for n in [car_a, car_b, car_c]:
		add_child(n)
		_extra.append(n)
	Wanted.note_vehicle_change(car_a)
	var p1: float = Wanted.escape_progress
	T.check(_near(p1, p0 + (1.0 - p0) * Wanted.Config.VEHICLE_CHANGE_CUT, 0.002) and Wanted.get_escape_time_remaining() < rem0 * 0.8,
			"vehicle change while unseen: remaining escape time -25%% (%.1f -> %.1f s)" % [rem0, Wanted.get_escape_time_remaining()])
	T.check(_near(Wanted.get_recognition_delay(), rd0 + Wanted.Config.RECOGNITION_PER_VEHICLE, 0.001) and rd0 > 0.0,
			"vehicle change: recognition delay %.2f -> %.2f s" % [rd0, Wanted.get_recognition_delay()])
	T.check(Wanted.level == 2 and Wanted.state == Wanted.State.SEARCH, "vehicle change is not an instant clear")
	Wanted.note_vehicle_change(car_a)
	T.check(is_equal_approx(Wanted.escape_progress, p1), "the same vehicle only counts once")
	Wanted.note_vehicle_change(car_b)
	var p2: float = Wanted.escape_progress
	Wanted.note_vehicle_change(car_c)
	T.check(p2 > p1 and is_equal_approx(Wanted.escape_progress, p2), "at most %d vehicle credits per unseen episode" % Wanted.Config.MAX_VEHICLE_CREDITS)
	Wanted.note_appearance_change()
	Wanted.note_appearance_change()
	T.check(Wanted.escape_progress <= Wanted.Config.CHANGE_PROGRESS_CAP + 0.0001 and Wanted.level == 2
			and Wanted.get_recognition_delay() <= Wanted.Config.RECOGNITION_MAX + 0.0001,
			"appearance change helps once; progress capped at %.2f (%.2f), delay %.2f s" % [Wanted.Config.CHANGE_PROGRESS_CAP, Wanted.escape_progress, Wanted.get_recognition_delay()])
	T.check(_ev_disguise == ["vehicle", "vehicle", "appearance"], "disguise_applied fired per credit (%s)" % str(_ev_disguise))
	# while the police watch, changes give nothing
	Wanted.police_sighting(null, DESERTED)
	var car_d := Node3D.new()
	add_child(car_d)
	_extra.append(car_d)
	Wanted.note_vehicle_change(car_d)
	Wanted.note_appearance_change()
	T.check(Wanted.escape_progress == 0.0 and Wanted.get_recognition_delay() == 0.0 and _ev_disguise.size() == 3,
			"changes in plain sight give no benefit")
	_reset()


func _test_bust() -> void:
	_reset(20.0)
	T.check(not Wanted.is_player_arrestable(), "not wanted -> not arrestable")
	Wanted.set_level(1)
	T.check(Wanted.is_player_arrestable(), "1 star, on foot, calm -> arrestable")
	T.check(not Wanted.is_lethal_force_authorized(), "1 star, calm player -> no lethal force")
	EventBus.weapon_fired.emit("pistol", _dummy, DESERTED, Vector3.FORWARD)
	T.check(not Wanted.is_player_arrestable() and Wanted.is_lethal_force_authorized(), "player fired -> not arrestable, lethal force authorized")
	await _adv(Wanted.Config.ARREST_CALM_SECONDS + 0.5)
	T.check(Wanted.is_player_arrestable(), "arrestable again after %.0f s without attacking" % Wanted.Config.ARREST_CALM_SECONDS)
	await _adv(Wanted.Config.LETHAL_AFTER_ATTACK_SECONDS)
	T.check(not Wanted.is_lethal_force_authorized(), "lethal authorization at 1 star expires")
	_ev_cleared.clear()
	Wanted.bust()
	T.check(_ev_busted == 1 and _ev_cleared == ["busted"] and Wanted.level == 0 and Wanted.state == Wanted.State.NONE,
			"bust(): player_busted once, then wanted_cleared('busted')")
	Wanted.bust()
	T.check(_ev_busted == 1 and _ev_cleared.size() == 1, "bust() when not wanted does nothing")
	Wanted.set_level(2)
	Wanted.note_player_attack()
	T.check(not Wanted.is_player_arrestable(), "note_player_attack() blocks the arrest")
	_reset()


func _test_level_api() -> void:
	_reset()
	Wanted.set_level(4)
	T.check(Wanted.level == 4 and Wanted.state == Wanted.State.PURSUIT and _ev_level == [[4, 0]] and _ev_state == [Wanted.State.PURSUIT], "set_level(4): one level + one state signal")
	Wanted.set_level(4)
	T.check(_ev_level.size() == 1 and _ev_state.size() == 1, "set_level to the same level emits nothing")
	Wanted.set_level(2)
	T.check(Wanted.level == 2 and _ev_level.back() == [2, 4] and is_equal_approx(Wanted.heat, Wanted.HEAT_THRESHOLDS[1]), "set_level(2) lowers, heat at the 2-star threshold")
	Wanted.set_level(0)
	T.check(Wanted.level == 0 and _ev_cleared == ["cheat"] and _ev_level.back() == [0, 2] and _ev_state.back() == Wanted.State.NONE, "set_level(0) clears once")
	Wanted.clear("cheat")
	T.check(_ev_cleared.size() == 1 and _ev_level.size() == 3, "clear() while not wanted emits nothing")
	Wanted.add_stars(1)
	Wanted.add_stars(1)
	T.check(Wanted.level == 2, "add_stars")
	Wanted.enabled = false
	T.check(Wanted.level == 0 and _ev_cleared.back() == "cheat", "enabled = false clears the current level")
	Wanted.report_crime("murder", DESERTED, {"direct_police_witness": true})
	Wanted.set_level(3)
	Wanted.force_pursuit(DESERTED)
	Wanted.police_sighting(null, DESERTED)
	T.check(Wanted.level == 0 and Wanted.get_pending_count() == 0, "never wanted: crimes, set_level and force_pursuit are ignored")
	Wanted.enabled = true
	_reset()
	var p := DESERTED + Vector3(5, 0, 5)
	Wanted.force_pursuit(p)
	T.check(Wanted.level == 1 and Wanted.state == Wanted.State.PURSUIT and Wanted.last_known_position.is_equal_approx(p), "force_pursuit: 1 star, PURSUIT at the position")
	await _adv(1.0)
	T.check(Wanted.time_in_state >= 0.99 and Wanted.time_in_state < 1.2, "time_in_state counts game time (%.2f)" % Wanted.time_in_state)
	Wanted.reset_for_respawn()
	T.check(Wanted.level == 0 and _ev_cleared.back() == "died", "reset_for_respawn clears with 'died'")
	T.check(Wanted.get_save_data().is_empty(), "wanted state is not saved")
	_reset()


func _test_resisting() -> void:
	_reset(20.0)
	Wanted.report_crime("vehicle_theft", DESERTED, {"direct_police_witness": true})
	T.check(Wanted.level == 1, "resisting: start at 1 star (non-violent)")
	var max_level := 1
	var level_at_20 := -1
	var start: float = Wanted._clock
	var guard := 0
	while Wanted._clock - start < 240.0 and guard < 30000:
		Wanted.police_sighting(null, _dummy.global_position)   # the police never lose the player
		await get_tree().process_frame
		guard += 1
		max_level = maxi(max_level, Wanted.level)
		if level_at_20 < 0 and Wanted._clock - start >= 20.0:
			level_at_20 = Wanted.level
	T.check(level_at_20 == 1, "resisting: escalation is slow (still 1 star after 20 s of pursuit)")
	T.check(Wanted.level == 3 and max_level == 3, "resisting: a long pursuit escalates to 3 stars and stops there without violence")
	T.check(Wanted.state == Wanted.State.PURSUIT, "resisting: still in pursuit")
	_reset()


func _test_misc() -> void:
	_reset()
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.get("auto_event_sounds") != null:
		var was: bool = bool(audio.get("auto_event_sounds"))
		audio.set("auto_event_sounds", true)
		T.check(Wanted._audio_for_stinger() == null, "stingers: Audio's EventBus glue plays them (no doubles)")
		audio.set("auto_event_sounds", false)
		T.check(Wanted._audio_for_stinger() == audio, "stingers: Wanted plays them itself when the glue is off")
		audio.set("auto_event_sounds", was)
	var info: Dictionary = Wanted.get_debug_info()
	T.check(info.has("level") and info.has("recognition_delay") and info.has("pending"), "get_debug_info() snapshot")
	var d: Dictionary = Wanted.get_crime_def("murder")
	T.check(is_equal_approx(float(d["heat"]), float(Wanted.CRIME_HEAT["murder"])) and bool(d["violent"]), "get_crime_def merges heat + attributes")
	await T.wait_frames(1)
