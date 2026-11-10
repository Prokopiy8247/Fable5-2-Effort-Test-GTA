extends Node
## Activities API test (headless, full game, real player + inventory + Combat + vehicles).
##   tools\godot.ps1 -Mode headless -Frames 30000 -TimeoutSec 420 -UserArgs '--test=act_api','--test-timeout=400'
## Optional: '--act_only=setup,range,stunt,race,abort,save' runs a subset.
## Covers: registry defs, activity points (Interactables + flags + blips), routes (lengths, no
## reversals, sea points in deep water); the handgun course started with the real interact key,
## scripted Combat.fire_hitscan hits on every exposed target + a few misses -> score / accuracy /
## medal / reward / shooting XP / best record, inventory + Wanted restored, no wanted stars;
## a scripted launch off stunt_ramp_1 counts as a jump (slow motion, safe landing, reward once);
## the street race started on foot spawns its car, checkpoints register when the car rolls
## through them, it finishes with a time + record; aborting a course restores everything;
## save data round trip through JSON.

var sys = null
var player = null
var started: Array = []
var finished: Array = []
var only: PackedStringArray = PackedStringArray()


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--act_only="):
			only = a.substr(11).split(",", false)
	_run()


func _want(part: String) -> bool:
	return only.is_empty() or only.has(part)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	await TestHarness.wait_frames(30)
	sys = Game.get_system("activities")
	if not TestHarness.check(sys != null, "activities system registered"):
		TestHarness.finish(false, "no activities system")
		return
	player = Game.player if Game.has_player() else null
	if not TestHarness.check(player != null, "player present"):
		TestHarness.finish(false, "no player")
		return
	EventBus.activity_started.connect(func(id: String) -> void: started.append(id))
	EventBus.activity_finished.connect(func(id: String, r: Dictionary) -> void: finished.append([id, r]))
	Game.set_money(10000)
	if _want("setup"):
		await _test_setup()
	if _want("range"):
		await _test_range()
	if _want("stunt"):
		await _test_stunt()
	if _want("race"):
		await _test_race()
	if _want("abort"):
		await _test_abort()
	if _want("save"):
		_test_save()
	TestHarness.finish()


func _finished_for(id: String) -> Dictionary:
	for i in range(finished.size() - 1, -1, -1):
		if str(finished[i][0]) == id:
			return finished[i][1]
	return {}


func _close_result() -> void:
	if UI.is_screen_open("activity_result"):
		UI.close_screen("activity_result")
	await _frames(2)


# ---------------------------------------------------------------------------------------------
func _test_setup() -> void:
	var ids: Array = Registry.ids("activities")
	TestHarness.check(ids.size() >= 8, "registry kind 'activities' has %d defs (>= 8)" % ids.size())
	TestHarness.log_line("setup %.1f ms, points %d" % [float(sys.setup_ms), (sys.points as Array).size()])
	TestHarness.check(float(sys.setup_ms) < 120.0, "setup took %.1f ms (< 120)" % float(sys.setup_ms))
	var n_it := 0
	for it: Node in get_tree().get_nodes_in_group("interactable"):
		if it.has_meta(&"activity_id"):
			n_it += 1
	TestHarness.check(n_it >= 5, "activity Interactables in group (%d >= 5: 2 range courses + 3 races)" % n_it)
	for id: String in ["range_handgun", "range_carbine", "race_coral_loop", "race_harbor_sprint", "race_hill_trail"]:
		var p: Dictionary = sys.get_point(id)
		TestHarness.check(not p.is_empty(), "activity point for %s" % id)
		if not p.is_empty():
			TestHarness.log_line("point %s at %s" % [id, str((p["xform"] as Transform3D).origin)])
	var rs: Array = sys.stunts.ramps
	TestHarness.check(rs.size() == 3, "3 stunt ramps resolved (%d)" % rs.size())
	for r: Dictionary in rs:
		TestHarness.log_line("ramp %s lip %s entry %s" % [str(r["id"]), str(r["lip_world"]), str(r["entry_world"])])
	# routes
	for id: String in ["race_coral_loop", "race_harbor_sprint", "race_hill_trail"]:
		var d: Dictionary = Registry.get_def("activities", id)
		var r: Dictionary = sys.race_ctl.get_route(d)
		if not TestHarness.check(bool(r.get("ok", false)), "route of %s built (%s)" % [id, str(r.get("why", ""))]):
			continue
		var cps: Array = r["cps"]
		TestHarness.log_line("route %s: %.0f m, %d checkpoints, grid %s" % [id, float(r["length"]), cps.size(), str((r["grid"] as Transform3D).origin)])
		TestHarness.check(float(r["length"]) > 250.0, "%s route length %.0f m (> 250)" % [id, float(r["length"])])
		TestHarness.check(cps.size() >= 4, "%s has %d checkpoints (>= 4)" % [id, cps.size()])
		var route0: PackedVector3Array = r["route"]
		TestHarness.log_line("  first points %s" % str(route0.slice(0, 4)))
		var worst := 0.0
		var worst_at := Vector3.ZERO
		var prev: Vector3 = (r["grid"] as Transform3D).origin
		var prev_dir := Vector3.ZERO
		for c: Dictionary in cps:
			var dv: Vector3 = (c["pos"] as Vector3) - prev
			dv.y = 0.0
			if prev_dir != Vector3.ZERO and dv.length() > 1.0 and rad_to_deg(prev_dir.angle_to(dv.normalized())) > worst:
				worst = rad_to_deg(prev_dir.angle_to(dv.normalized()))
				worst_at = c["pos"]
			if dv.length() > 1.0:
				prev_dir = dv.normalized()
			prev = c["pos"]
		if bool(d.get("trail_return", false)):
			TestHarness.log_line("%s turns back at the hill top (sharpest turn %.0f deg at %s) - intended" % [id, worst, str(worst_at)])
		else:
			TestHarness.check(worst < 150.0, "%s: no reversal between checkpoints (sharpest turn %.0f deg at %s)" % [id, worst, str(worst_at)])

		if str(d.get("mode", "")) == "water":
			var shallow := 0
			for c: Dictionary in cps:
				var p: Vector3 = c["pos"]
				if float(Game.world.get_water_depth(p.x, p.z)) < 2.4:
					shallow += 1
			TestHarness.check(shallow == 0, "sea race checkpoints in >= 2.4 m deep water (%d shallow)" % shallow)
			# legs over land?
			var landed := 0
			var route: PackedVector3Array = r["route"]
			for k in range(1, route.size()):
				for s in 20:
					var q := route[k - 1].lerp(route[k], float(s) / 20.0)
					if float(Game.world.get_water_depth(q.x, q.z)) < 0.8:
						landed += 1
			TestHarness.check(landed == 0, "sea race legs stay on water (%d samples on the shore)" % landed)


# ---------------------------------------------------------------------------------------------
func _test_range() -> void:
	var inv = player.get("inventory")
	if not TestHarness.check(inv != null, "player inventory present"):
		return
	var before: Dictionary = inv.get_save_data()
	var had_pistol: bool = inv.has_weapon("pistol")
	var money0 := Game.money
	var xp0 := Skills.get_level("shooting")
	var p: Dictionary = sys.get_point("range_handgun")
	if not TestHarness.check(not p.is_empty(), "range point exists"):
		return
	var it = p["interactable"]
	var stand: Vector3 = (p["xform"] as Transform3D).origin
	player.teleport(stand + Vector3.UP * 0.05, 0.0)
	await _frames(30)
	var prompt := str(UI.get_prompt_text()) if UI.has_method("get_prompt_text") else ""
	TestHarness.log_line("prompt at the range counter: '%s'" % prompt)
	TestHarness.check(bool(it.call("can_interact", player)), "range Interactable usable at Use_Start")
	TestHarness.check(prompt.to_lower().contains("shooting range"), "prompt shows the range course ('%s')" % prompt)
	Input.action_press("interact")
	await _frames(3)
	Input.action_release("interact")
	var waited := 0
	while not sys.is_active() and waited < 240:
		await _frames(1)
		waited += 1
	if not TestHarness.check(sys.get_active_id() == "range_handgun", "interact key started the handgun course"):
		return
	TestHarness.check(started.has("range_handgun"), "EventBus.activity_started('range_handgun')")
	var lane: Transform3D = sys.range_ctl.get_lane_transform()
	TestHarness.check(player.global_position.distance_to(lane.origin) < 1.0, "player moved onto the firing position (%.2f m)" % player.global_position.distance_to(lane.origin))
	TestHarness.check(str(inv.get("current_id")) == "pistol", "course weapon equipped (%s)" % str(inv.get("current_id")))
	TestHarness.check(Wanted.enabled == false, "Wanted paused for the lawful range session")
	var info: Dictionary = sys.get_hud_info()
	TestHarness.check(bool(info.get("active", false)) and str(info.get("title", "")) != "", "get_hud_info active with a title ('%s')" % str(info.get("title", "")))
	for k: String in ["title", "timer", "score", "checkpoint", "total"]:
		TestHarness.check(info.has(k), "hud info has key '%s'" % k)
	TestHarness.check(sys.hud_fallback == null, "the UI HUD activity card exists, no fallback tracker created")

	# shoot every exposed target once (aim at its centre) + a miss into the berm now and then
	var eye := lane.origin + Vector3.UP * 1.55
	var shot_at: Dictionary = {}
	var fired := 0
	var scripted_hits := 0
	var misses := 0
	var frames := 0
	var saw_kinds: Dictionary = {}
	while sys.get_active_id() == "range_handgun" and frames < 60 * 150:
		var open: PackedInt32Array = sys.range_ctl.get_open_targets()
		for i in open:
			var t = sys.range_ctl.targets[i]
			var key := "%d:%d" % [i, int(sys.range_ctl.exposures)]
			if shot_at.has(key):
				continue
			shot_at[key] = true
			saw_kinds[t.kind] = true
			var aim: Vector3 = sys.range_ctl.get_target_aim_point(i)
			var hits_before: int = sys.range_ctl.hits
			var res: Dictionary = Combat.fire_hitscan(eye, (aim - eye).normalized(), "pistol", player, {"spread_deg": 0.0})
			fired += 1
			if sys.range_ctl.hits > hits_before:
				scripted_hits += 1
			else:
				TestHarness.log_line("shot at %s target %d missed: hit %s collider %s" % [t.kind, i, str(res.get("position")), str(res.get("collider"))])
			if fired % 6 == 0:
				Combat.fire_hitscan(eye, (-lane.basis.z + Vector3(0.05, 0.12, 0.0)).normalized(), "pistol", player, {"spread_deg": 0.0})
				fired += 1
				misses += 1
		await _frames(4)
		frames += 4
	TestHarness.log_line("range: fired %d, scripted hits %d, misses %d, %d frames, kinds %s" % [fired, scripted_hits, misses, frames, str(saw_kinds.keys())])
	TestHarness.check(sys.get_active_id() == "", "course finished on its own")
	var r := _finished_for("range_handgun")
	if not TestHarness.check(not r.is_empty() and not bool(r.get("aborted", false)), "activity_finished with a result"):
		return
	TestHarness.log_line("range result: %s" % str(r))
	TestHarness.check(saw_kinds.has("turner") and saw_kinds.has("popup") and saw_kinds.has("mover"), "all three target types appeared (%s)" % str(saw_kinds.keys()))
	TestHarness.check(scripted_hits >= int(fired - misses) - 1, "scripted shots hit their targets (%d / %d)" % [scripted_hits, fired - misses])
	TestHarness.check(int(r.get("hits", 0)) == scripted_hits, "result hits = scripted hits (%d / %d)" % [int(r.get("hits", 0)), scripted_hits])
	TestHarness.check(int(r.get("shots", 0)) == fired, "every shot counted (%d / %d)" % [int(r.get("shots", 0)), fired])
	TestHarness.check(int(r.get("score", 0)) > 0, "score %d > 0" % int(r.get("score", 0)))
	TestHarness.check(float(r.get("accuracy", 0.0)) > 0.6 and float(r.get("accuracy", 0.0)) < 1.0, "accuracy %.2f reflects the misses" % float(r.get("accuracy", 0.0)))
	TestHarness.check(str(r.get("medal_id", "none")) != "none" and str(r.get("medal", "")) == str(r.get("medal_id", "")), "a medal was earned (%s)" % str(r.get("medal_id", "")))
	var reward := int(r.get("reward", 0))
	TestHarness.check(reward > 0 and Game.money == money0 + reward, "cash reward paid (+$%d, money %d -> %d)" % [reward, money0, Game.money])
	TestHarness.check(Skills.get_level("shooting") > xp0, "shooting skill rose (%.2f -> %.2f)" % [xp0, Skills.get_level("shooting")])
	TestHarness.check(int(sys.get_record("range_handgun")["best_score"]) == int(r.get("score", 0)), "best score stored")
	TestHarness.check((r.get("lines", []) as Array).size() >= 3 and r.has("retry") and r.has("medal"), "result args carry lines / medal / retry")
	TestHarness.check(Wanted.enabled and Wanted.level == 0, "Wanted back on, no stars after range gunfire")
	TestHarness.check(inv.has_weapon("pistol") == had_pistol, "pistol ownership restored")
	var after: Dictionary = inv.get_save_data()
	TestHarness.check(str(after.get("ammo", {})) == str(before.get("ammo", {})), "ammo pools restored (%s)" % str(after.get("ammo", {})))
	TestHarness.check(UI.is_screen_open("activity_result") or UI.is_banner_showing(), "result shown (screen or banner)")
	await _close_result()


# ---------------------------------------------------------------------------------------------
func _test_stunt() -> void:
	var r: Dictionary = sys.stunts.get_ramp("stunt_foundry")
	if not TestHarness.check(not r.is_empty(), "stunt_foundry ramp known"):
		return
	var money0 := Game.money
	var xf: Transform3D = r["xf"]
	var fwd := -xf.basis.z
	var start := xf * Vector3(0.0, 0.0, float(r["entry_z"]) + 26.0)
	start.y = Game.ground_height(start.x, start.z) + 0.05
	var car = Game.spawn_vehicle("sports", Transform3D(xf.basis, start), {"owner_tag": "player", "engine_on": true})
	if not TestHarness.check(car != null, "sports car spawned on the run-up"):
		return
	await _frames(10)
	player.enter_vehicle(car, 0, true)
	await _frames(40)
	if not TestHarness.check(Game.get_player_vehicle() == car, "player drives the car"):
		return
	(car as RigidBody3D).linear_velocity = fwd * 19.0
	Input.action_press("move_forward")
	var f := 0
	var saw_air := false
	var min_scale := 1.0
	while f < 900 and _finished_for("stunt_foundry").is_empty():
		await _frames(1)
		f += 1
		if int(sys.stunts.state) == 2:
			saw_air = true
			min_scale = minf(min_scale, Engine.time_scale)
			var info: Dictionary = sys.get_hud_info()
			if f % 20 == 0:
				TestHarness.log_line("air %.2f s hud '%s' %s" % [float(sys.stunts.air_t), str(info.get("title", "")), str(info.get("hint", ""))])
	Input.action_release("move_forward")
	Input.action_press("move_back")
	await _frames(40)
	Input.action_release("move_back")
	var res := _finished_for("stunt_foundry")
	TestHarness.log_line("stunt result: %s (log %s)" % [str(res), str(sys.stunts.debug_log)])
	TestHarness.check(started.has("stunt_foundry"), "activity_started('stunt_foundry') on launch")
	TestHarness.check(saw_air, "launch off the lip detected")
	TestHarness.check(min_scale < 0.6, "slow motion during the launch (time scale %.2f)" % min_scale)
	TestHarness.check(bool(res.get("success", false)), "jump counted (safe landing %s, %.1f m, %.2f s)" % [str(res.get("safe_landing")), float(res.get("distance", 0.0)), float(res.get("airtime", 0.0))])
	TestHarness.check(float(res.get("distance", 0.0)) >= 16.0, "distance %.1f m >= 16" % float(res.get("distance", 0.0)))
	TestHarness.check(float(res.get("airtime", 0.0)) >= 0.9, "airtime %.2f s >= 0.9" % float(res.get("airtime", 0.0)))
	TestHarness.check(bool(sys.get_record("stunt_foundry")["done"]), "jump marked as completed")
	TestHarness.check(Game.money == money0 + 500, "first-time reward paid (%d -> %d)" % [money0, Game.money])
	TestHarness.check(sys.get_stunt_progress() == Vector2i(1, 3), "progress 1 / 3 (%s)" % str(sys.get_stunt_progress()))
	TestHarness.check(is_equal_approx(Engine.time_scale, 1.0), "time scale restored (%.2f)" % Engine.time_scale)
	TestHarness.log_line("after the jump: car at %s, wanted %d, crimes %s" % [str(car.global_position), Wanted.level, str(Wanted.get_crime_records())])
	if Wanted.level > 0:
		Wanted.clear("cheat")


# ---------------------------------------------------------------------------------------------
func _test_race() -> void:
	var id := "race_coral_loop"
	var p: Dictionary = sys.get_point(id)
	if not TestHarness.check(not p.is_empty(), "race point exists"):
		return
	var money0 := Game.money
	var stand: Vector3 = (p["xform"] as Transform3D).origin
	player.teleport(stand + Vector3.UP * 0.05, 0.0)
	await _frames(30)
	var it = p["interactable"]
	TestHarness.check(bool(it.call("can_interact", player)), "race Interactable usable on foot")
	Input.action_press("interact")
	await _frames(3)
	Input.action_release("interact")
	var waited := 0
	while not sys.is_active() and waited < 240:
		await _frames(1)
		waited += 1
	if not TestHarness.check(sys.get_active_id() == id, "interact key started the street race (refusal '%s')" % str(sys.last_refusal)):
		return
	var rc = sys.race_ctl
	var car = Game.get_player_vehicle()
	TestHarness.check(car != null and bool(rc.spawned_vehicle) and str(car.get("spec_id")) == "sports", "race car spawned and entered (%s)" % (str(car.get("spec_id")) if car != null else "none"))
	TestHarness.check(Game.is_input_locked(), "input locked during the countdown")
	TestHarness.check((rc._props as Array).size() == 1, "checkpoint arch spawned over the start line")
	TestHarness.check((rc._rings as Array).size() == 2 and (rc._rings[0] as Node3D).visible, "checkpoint columns shown")
	var w := 0
	while int(rc.phase) != 3 and w < 400:
		await _frames(1)
		w += 1
	TestHarness.check(int(rc.phase) == 3 and not Game.is_input_locked(), "GO after the countdown, input unlocked")
	var total: int = (rc.cps as Array).size()
	var guard := 0
	while sys.get_active_id() == id and guard < total + 3:
		guard += 1
		var k: int = rc.cp_index
		var cp: Dictionary = rc.get_checkpoint(k)
		if cp.is_empty():
			break
		var dir: Vector3 = cp["dir"]
		var registered := false
		for attempt in 3:
			var back: float = [12.0, 7.0, 3.0][attempt]
			var pos: Vector3 = (cp["pos"] as Vector3) - dir * back
			pos.y = Game.ground_height(pos.x, pos.z) + 0.1
			car.teleport(Transform3D(Basis.looking_at(dir, Vector3.UP), pos))
			await _frames(2)
			(car as RigidBody3D).linear_velocity = dir * 12.0
			var f := 0
			while rc.cp_index == k and sys.get_active_id() == id and f < 100:
				await _frames(1)
				f += 1
			if rc.cp_index != k or sys.get_active_id() != id:
				registered = true
				break
			TestHarness.log_line("checkpoint %d attempt %d: car %s (%.1f km/h) cp %s" % [k, attempt, str(car.global_position),
					float(car.get("speed_kmh")), str(cp["pos"])])
		if not registered:
			break

	var r := _finished_for(id)
	TestHarness.log_line("race result: %s" % str(r))
	TestHarness.check(not r.is_empty() and not bool(r.get("aborted", false)), "race finished after all %d checkpoints" % total)
	TestHarness.check(float(r.get("time", 0.0)) > 1.0, "race time %.2f s (teleported through the checkpoints)" % float(r.get("time", 0.0)))
	TestHarness.check(float(sys.get_record(id)["best_time"]) > 0.0, "best time stored (%.2f)" % float(sys.get_record(id)["best_time"]))
	TestHarness.check(Game.money == money0 + int(r.get("reward", 0)), "race reward matches the medal (%s, +$%d)" % [str(r.get("medal", "")), int(r.get("reward", 0))])
	TestHarness.check((rc._props as Array).is_empty(), "arch removed after the race")
	TestHarness.check(not (rc._rings[0] as Node3D).visible, "checkpoint columns hidden after the race")
	TestHarness.check(not Game.is_input_locked() or UI.is_screen_open("activity_result"), "input free (or only the result screen holds it)")
	await _close_result()
	TestHarness.check(not Game.is_input_locked(), "input unlocked after closing the result")
	if sys.get_active_id() != "":
		sys.abort_activity("test cleanup")



# ---------------------------------------------------------------------------------------------
func _test_abort() -> void:
	var inv = player.get("inventory")
	var had_carbine: bool = inv.has_weapon("carbine")
	var before: Dictionary = inv.get_save_data()
	var p: Dictionary = sys.get_point("range_carbine")
	if not TestHarness.check(not p.is_empty(), "carbine course point exists"):
		return
	player.teleport((p["xform"] as Transform3D).origin + Vector3.UP * 0.05, 0.0)
	await _frames(20)
	var ok: bool = await sys.start_activity("range_carbine")
	TestHarness.check(ok and sys.get_active_id() == "range_carbine", "carbine course started through the API (refusal '%s')" % str(sys.last_refusal))

	TestHarness.check(inv.has_weapon("carbine") and str(inv.get("current_id")) == "carbine", "carbine handed out")
	await _frames(90)
	player.teleport((p["xform"] as Transform3D).origin + Vector3(0, 0.05, 0) + (p["xform"] as Transform3D).basis.z * 12.0, 0.0)
	await _frames(10)
	var r := _finished_for("range_carbine")
	TestHarness.check(not r.is_empty() and bool(r.get("aborted", false)), "walking away aborts the course (%s)" % str(r.get("reason", "")))
	TestHarness.check(sys.get_active_id() == "", "nothing active after the abort")
	TestHarness.check(inv.has_weapon("carbine") == had_carbine, "carbine taken back")
	TestHarness.check(str(inv.get_save_data().get("ammo", {})) == str(before.get("ammo", {})), "ammo restored after the abort")
	TestHarness.check(Wanted.enabled, "Wanted re-enabled after the abort")
	var hidden := true
	for t in sys.range_ctl.targets:
		if (t.node as Node3D).visible:
			hidden = false
	TestHarness.check(hidden, "range targets packed away")


# ---------------------------------------------------------------------------------------------
func _test_save() -> void:
	var d: Dictionary = sys.get_save_data()
	var json := JSON.stringify(d)
	var back: Variant = JSON.parse_string(json)
	TestHarness.check(back is Dictionary, "save data survives JSON")
	var snap: Dictionary = (sys.records as Dictionary).duplicate(true)
	sys.reset_records()
	TestHarness.check((sys.records as Dictionary).is_empty(), "records cleared")
	sys.load_save_data(back)
	var same := true
	for id: String in snap:
		var a: Dictionary = snap[id]
		var b: Dictionary = sys.get_record(id)
		for k: String in ["best_score", "best_medal", "done", "plays"]:
			if a.has(k) and str(a[k]) != str(b[k]):
				same = false
				TestHarness.log_line("record %s.%s %s != %s" % [id, k, str(a[k]), str(b[k])])
		if a.has("best_time") and absf(float(a["best_time"]) - float(b["best_time"])) > 0.001:
			same = false
	TestHarness.check(same and not snap.is_empty(), "records restored from save data (%d)" % snap.size())
	sys.load_save_data({"records": {"bogus": "x", "range_handgun": {"best_score": "12", "done": 1}}})
	TestHarness.check(int(sys.get_record("range_handgun")["best_score"]) == 12, "garbage-tolerant load")
	sys.load_save_data(back)
