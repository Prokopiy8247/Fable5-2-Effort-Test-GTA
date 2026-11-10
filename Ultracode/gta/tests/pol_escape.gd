extends Node
## POLICE search / escape test (headless): real world, vehicles, peds, police, real player.
##   1. 2 stars downtown: the dispatched units find the player (police sightings -> PURSUIT)
##   2. the player is teleported far away out of every unit's sight -> SEARCH; the units search
##      around Wanted.search_center (vehicle AI "search" / officer brains "search")
##   3. with Wanted.debug_time_scale the escape timer runs out -> cleared ("escaped"), units stand down
##   4. a new episode, lost again -> SEARCH; an officer placed in front of the player sees him ->
##      PURSUIT resumes and the escape progress is reset
## The player is invulnerable and keeps a pistol raised (not arrestable) so the episode is not ended
## by an arrest or death.
##   tools\godot.ps1 -Mode headless -Frames 9000 -TimeoutSec 400 -UserArgs '--test=pol_escape','--test-timeout=380','--seed=5','--disable=traffic,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug'

var T: Node
var pol: Node
var _cleared: Array[String] = []


func _ready() -> void:
	T = TestHarness
	EventBus.wanted_cleared.connect(func(r: String) -> void: _cleared.append(r))
	await T.wait_seconds(1.0)
	await _run()
	Input.action_release("aim")
	Game.invulnerable = false
	Wanted.debug_time_scale = 1.0
	Wanted.clear("cheat")
	T.finish()


func _run() -> void:
	pol = Game.get_system("police")
	var p := Game.player
	if not T.check(pol != null and p != null and is_instance_valid(p), "police system + player present"):
		return
	Game.invulnerable = true
	var inv: Node = p.get("inventory")
	if inv != null:
		inv.call("give_weapon", "pistol", 200)
		inv.call("equip", "pistol")
	var plaza := Game.get_location("downtown_plaza")
	var far := Game.get_location("beach")
	T.log_line("plaza %s beach %s distance %.0f" % [str(plaza.origin.round()), str(far.origin.round()), plaza.origin.distance_to(far.origin)])

	# --- 1. found at 2 stars
	if not await _get_found(p, plaza):
		return

	# --- 2. lost: teleport away
	p.call("teleport", far.origin, 0.0)
	Input.action_release("aim")
	var t := 0.0
	while t < 12.0 and Wanted.state != Wanted.State.SEARCH:
		await T.wait_seconds(0.25)
		t += 0.25
	T.check(Wanted.state == Wanted.State.SEARCH, "out of sight -> SEARCH after %.1f s (grace %.1f s)" % [t,
			float(Wanted.get_level_config(2)["lost_contact_grace"])])
	var center: Vector3 = Wanted.search_center
	T.check(center.distance_to(plaza.origin) < 60.0, "search centred near the last known position (%.0f m)" % center.distance_to(plaza.origin))
	var searching := 0
	var near_center := 0
	t = 0.0
	while t < 14.0:
		await T.wait_seconds(0.5)
		t += 0.5
		var info: Dictionary = pol.call("get_debug_info")
		var um: Dictionary = info.get("unit_modes", {})
		var om: Dictionary = info.get("officer_modes", {})
		searching = maxi(searching, int(um.get("search", 0)) + int(om.get("search", 0)))
		near_center = 0
		for u: Variant in pol.call("get_units"):
			if u is Node3D and is_instance_valid(u) and (u as Node3D).global_position.distance_to(center) < float(Wanted.search_radius) + 30.0:
				near_center += 1
		if int(t * 2.0) % 6 == 0:
			T.log_line("search t=%.1f radius=%.0f progress=%.2f units=%s officers=%s near=%d" % [t, Wanted.search_radius,
					Wanted.escape_progress, str(um), str(om), near_center])
	T.check(searching >= 2, "units search (%d units / officers in search mode)" % searching)
	T.check(near_center >= 1, "units stay in the search area (%d)" % near_center)
	T.check(Wanted.state == Wanted.State.SEARCH and Wanted.escape_progress > 0.0, "still unseen: escape progress %.2f" % Wanted.escape_progress)
	T.check(_nearest_police(p.global_position) > 80.0, "no unit near the hidden player (%.0f m)" % _nearest_police(p.global_position))

	# --- 3. escape
	Wanted.debug_time_scale = 4.0
	t = 0.0
	while t < 30.0 and Wanted.level > 0:
		await T.wait_seconds(0.5)
		t += 0.5
	Wanted.debug_time_scale = 1.0
	T.check(Wanted.level == 0 and _cleared.has("escaped"), "escaped: level cleared after the escape time (%.1f s at x4)" % t)
	await T.wait_seconds(3.0)
	var info2: Dictionary = pol.call("get_debug_info")
	var um2: Dictionary = info2.get("unit_modes", {})
	T.check(not um2.has("pursuit") and not um2.has("search"), "units stand down after the escape (%s)" % str(um2))

	# --- 4. lost again, then seen -> PURSUIT
	if not await _get_found(p, plaza):
		return
	p.call("teleport", far.origin, 0.0)
	Input.action_release("aim")
	t = 0.0
	while t < 12.0 and Wanted.state != Wanted.State.SEARCH:
		await T.wait_seconds(0.25)
		t += 0.25
	T.check(Wanted.state == Wanted.State.SEARCH, "lost again -> SEARCH")
	Wanted.debug_time_scale = 3.0
	await T.wait_seconds(3.0)
	var prog := float(Wanted.escape_progress)
	Wanted.debug_time_scale = 1.0
	T.check(prog > 0.05, "escape progress grows while unseen (%.2f)" % prog)
	# an officer walks round the corner right in front of the player
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	var spot := p.global_position + fwd.normalized() * 9.0
	var o: Node3D = pol.call("spawn_unit_at", "officer", Transform3D(Basis.IDENTITY, spot))
	if not T.check(o != null, "officer placed in front of the player"):
		return
	o.call("face_position", p.global_position)
	t = 0.0
	while t < 8.0 and Wanted.state != Wanted.State.PURSUIT:
		await T.wait_seconds(0.2)
		t += 0.2
	T.check(Wanted.state == Wanted.State.PURSUIT, "a sighting resumed PURSUIT after %.1f s (recognition delay %.2f s)" % [t, Wanted.get_recognition_delay()])
	T.check(Wanted.escape_progress == 0.0, "escape progress reset by the sighting")
	var info3: Dictionary = pol.call("get_debug_info")
	T.log_line("POLICE_STATS %s" % str(info3))


## Downtown at 2 stars until the police have seen the player (PURSUIT with a recent sighting).
func _get_found(p: Node3D, at: Transform3D) -> bool:
	Wanted.clear("cheat")
	p.call("teleport", at.origin, at.basis.get_euler().y)
	await T.wait_seconds(0.5)
	Input.action_press("aim")
	Wanted.set_level(2)
	var t := 0.0
	var seen := false
	while t < 45.0:
		await T.wait_seconds(0.5)
		t += 0.5
		if Wanted.state == Wanted.State.PURSUIT and Wanted.player_visible_to_police and Wanted.time_in_state > 1.0:
			seen = true
			break
	T.check(seen, "2 stars: the police found the player downtown (%.1f s)" % t)
	return seen


func _nearest_police(pos: Vector3) -> float:
	var best := INF
	for n in get_tree().get_nodes_in_group("police"):
		if n is Node3D and is_instance_valid(n) and not bool(n.get("is_dead")):
			best = minf(best, (n as Node3D).global_position.distance_to(pos))
	return best
