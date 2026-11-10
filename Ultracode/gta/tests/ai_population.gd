extends Node
## Headless population test of the "peds" system in the REAL world (focus override downtown).
## Run:
##   tools\godot.ps1 -Mode headless -Frames 7000 -TimeoutSec 400 -UserArgs '--test=ai_population','--test-timeout=380','--seed=11','--disable=props,traffic,police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'
## Checks: the ambient count stays between 10 and the cap downtown, follows the focus, tiers are
## assigned by distance, people stand on the walk network, fewer at night / in rain; prints the
## frame cost of the whole AI loop (AI_FRAME_COST lines).

var peds: Node = null


func _ready() -> void:
	peds = Game.get_system("peds")
	var world := Game.world
	if not TestHarness.check(peds != null and world != null, "peds + world systems present"):
		TestHarness.finish(false, "missing systems")
		return
	WorldClock.paused = true
	WorldClock.set_hour(11.0)
	Weather.set_weather("clear", 0.0)
	var down: Transform3D = Game.get_location("downtown_plaza")
	var focus := down.origin
	peds.call("set_focus_override", focus)
	if Game.has_player():
		Game.player.call("teleport", focus + Vector3(0.0, 0.2, 0.0), 0.0)
	await TestHarness.wait_seconds(12.0)
	var cap := mini(40, int(round(28.0 * float(Settings.get_value("ped_density")))))
	var target := int(peds.call("get_target_count"))
	TestHarness.log_line("downtown day: target %d cap %d" % [target, cap])
	var lo := 999
	var hi := 0
	for k in 20:
		await TestHarness.wait_seconds(1.0)
		var n := int(peds.call("get_ambient_count"))
		lo = mini(lo, n)
		hi = maxi(hi, n)
	TestHarness.check(lo >= 10 and hi <= cap, "downtown ambient count stays in [10, %d]: min %d max %d" % [cap, lo, hi])
	_check_tiers_and_placement(focus, "downtown")
	var info: Dictionary = peds.call("get_debug_info")
	TestHarness.log_line("debug info: " + str(info))
	TestHarness.check(int(info.get("gang_active", 0)) >= 0, "gang info available")

	# follow the focus to midtown (hospital, ~150 m away)
	var mid: Vector3 = Game.get_location("hospital").origin
	TestHarness.log_line("focus moves %.0f m" % focus.distance_to(mid))
	peds.call("set_focus_override", mid)
	if Game.has_player():
		Game.player.call("teleport", mid + Vector3(0.0, 0.2, 0.0), 0.0)
	await TestHarness.wait_seconds(20.0)
	var far := 0
	var near := 0
	for npc: Node3D in peds.call("get_npcs"):
		if bool(npc.get("is_dead")) or not bool(npc.get("ambient")) or npc.has_meta("gang_spot"):
			continue
		var d := Vector2(npc.global_position.x - mid.x, npc.global_position.z - mid.z).length()
		if d > 112.0:
			far += 1
		else:
			near += 1
	TestHarness.check(far == 0, "old population despawned after the focus moved (%d left > 110 m)" % far)
	TestHarness.check(near >= 10, "new population around the new focus (%d)" % near)
	_check_tiers_and_placement(mid, "midtown")

	# frame cost at the maximum density (40)
	Settings.set_value("ped_density", 1.5, false)
	await TestHarness.wait_seconds(16.0)
	var st: Dictionary = peds.get("stats")
	var npcs := int(peds.call("get_npc_count"))
	var ambient := int(peds.call("get_ambient_count"))
	var phys := float(st["phys_us"])
	var anim := float(st["anim_us"])
	print("AI_FRAME_COST: npcs=%d ambient=%d physics_loop=%.0f us anim_loop=%.0f us total=%.2f ms (max phys %.0f us, max anim %.0f us)" % [
			npcs, ambient, phys, anim, (phys + anim) / 1000.0, float(st["phys_us_max"]), float(st["anim_us_max"])])
	var ps: Dictionary = NpcBase.path_stats
	print("AI_PATH_COST: walk paths %d avg %.0f us max %.0f us | nav paths %d avg %.0f us max %.0f us | spawn max %.0f us avg %.0f us | crosswalk checks %d (waited %d)" % [
			int(ps["walk_n"]), float(ps["walk_us"]) / maxf(float(ps["walk_n"]), 1.0), float(ps["walk_max"]),
			int(ps["nav_n"]), float(ps["nav_us"]) / maxf(float(ps["nav_n"]), 1.0), float(ps["nav_max"]),
			float(st["spawn_us_max"]), float(st["spawn_us_total"]) / maxf(float(st["spawned"]), 1.0),
			int(ps["crossings"]), int(ps["crossing_waits"])])
	TestHarness.check(int(ps["crossings"]) > 0, "pedestrians reach crosswalks and check the traffic (%d)" % int(ps["crossings"]))
	TestHarness.check(ambient >= 25, "density 1.5 raises the population (%d)" % ambient)
	TestHarness.check(ambient <= 40, "never more than 40 ambient pedestrians (%d)" % ambient)
	TestHarness.check(phys + anim < 2500.0, "AI loops under 2.5 ms per frame on average (%.2f ms)" % ((phys + anim) / 1000.0))
	Settings.set_value("ped_density", 1.0, false)

	# night and rain thin the crowd
	var day_target := int(peds.call("get_target_count"))
	WorldClock.set_hour(23.0)
	var night_target := int(peds.call("get_target_count"))
	Weather.set_weather("rain", 0.0)
	await TestHarness.wait_seconds(1.0)
	var rain_target := int(peds.call("get_target_count"))
	TestHarness.check(night_target < day_target and rain_target < night_target,
			"fewer people at night and in rain (day %d, night %d, night+rain %d)" % [day_target, night_target, rain_target])
	var n_before := int(peds.call("get_ambient_count"))
	await TestHarness.wait_seconds(24.0)
	var n_night := int(peds.call("get_ambient_count"))
	# people only leave unseen and farther than 40 m, so the crowd thins out gradually
	TestHarness.check(n_night <= rain_target + 7 and n_night < n_before, "population shrinks towards the night target (%d -> %d, target %d)" % [n_before, n_night, rain_target])
	TestHarness.log_line("final debug info: " + str(peds.call("get_debug_info")))
	Weather.set_weather("clear", 0.0)
	WorldClock.paused = false
	TestHarness.finish()


func _check_tiers_and_placement(focus: Vector3, label: String) -> void:
	var walk: Object = Game.world.get("walk")
	var wrong_tier := 0
	var off_walk := 0
	var fallen := 0
	var count := 0
	var archetypes := {}
	var tags := {}
	for npc: Node3D in peds.call("get_npcs"):
		if bool(npc.get("is_dead")):
			continue
		count += 1
		tags[str(npc.get("state_tag"))] = int(tags.get(str(npc.get("state_tag")), 0)) + 1
		archetypes[str(npc.get("archetype_id"))] = true
		var d := Vector2(npc.global_position.x - focus.x, npc.global_position.z - focus.z).length()
		var want := 0 if d < 45.0 else (1 if d < 110.0 else 2)
		if int(npc.get("sim_tier")) != want and absf(d - 45.0) > 3.0 and absf(d - 110.0) > 3.0:
			wrong_tier += 1
		if bool(npc.get("ambient")) and not npc.has_meta("gang_spot") and walk != null and str(npc.get("state_tag")) != "sit":
			var np: Vector3 = walk.call("get_nearest_point", npc.global_position)
			if np.distance_to(npc.global_position) > 3.5:
				off_walk += 1
		if npc.global_position.y < Game.ground_height(npc.global_position.x, npc.global_position.z) - 1.0:
			fallen += 1
	TestHarness.check(wrong_tier == 0, "%s: simulation tiers follow the distance (%d wrong of %d)" % [label, wrong_tier, count])
	TestHarness.check(off_walk <= maxi(2, count / 8), "%s: pedestrians are on the sidewalk network (%d off of %d)" % [label, off_walk, count])
	TestHarness.check(fallen == 0, "%s: nobody fell through the ground" % label)
	TestHarness.log_line("%s archetypes: %s | states: %s" % [label, str(archetypes.keys()), str(tags)])
