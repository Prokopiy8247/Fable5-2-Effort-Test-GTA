extends Node
## trn_taxi (headless, full game with traffic): the taxi passenger service with the REAL player.
##   A. call_taxi(player position) -> a cab of the traffic system drives to the kerb (<= 60 s)
##   B. "Get in the cab" (interact) -> the player sits in a rear seat, the taxi screen opens
##   C. a destination 250-550 m away chosen programmatically (TaxiSystem.choose_destination)
##   D. the cab drives there through traffic (traffic driver logic), stops at the kerb point, the
##      fare is charged (Game.spend), the passenger gets out
##   E. second ride, far destination, "skip" (Enter): fade, the cab is at the drop-off, clock advanced,
##      fare charged
##   F. no money -> the driver refuses the destination; leaving the waiting cab costs nothing
##   G. "Stop here" (enter-vehicle key) during a ride: pulls over, pays the distance so far
## Run:
##   tools\godot.ps1 -Mode headless -Frames 26000 -TimeoutSec 420 -UserArgs '--test=trn_taxi','--test-timeout=400','--disable=police,emergency,wildlife,activities,transit'

var T: Node
var sys: Node
var P: Node3D


func _ready() -> void:
	T = TestHarness
	await T.wait_physics_frames(30)
	sys = Game.get_system("taxi")
	P = Game.player
	if not T.check(sys != null and P != null and Game.get_system("traffic") != null, "taxi + traffic systems and the player exist"):
		T.finish(false, "missing systems")
		return
	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--trn_only="):
			only = a.substr(11)
	Game.money = 5000
	# start on the Cannery Street sidewalk at the taxi stand (downtown / midtown border)
	var stand: Transform3D = Game.get_location("taxi_stand")
	P.call("teleport", stand.origin + Vector3.UP * 0.1, 0.0)
	await T.wait_seconds(3.0)
	if only == "" or only.contains("drive"):
		await _ride(false, 250.0, 550.0)
	if only == "" or only.contains("skip"):
		await _ride(true, 500.0, 2000.0)
	if only == "" or only.contains("refuse"):
		await _refuse()
	if only == "" or only.contains("stop"):
		await _early_stop()
	T.log_line("TAXI END " + str(sys.call("get_debug_info")))
	T.finish()


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if bool(cond.call()):
			return true
		await T.wait_seconds(0.1)
		t += 0.1
	return bool(cond.call())


func _tap(action: String) -> void:
	await get_tree().physics_frame
	Input.action_press(action)
	await T.wait_physics_frames(3)
	Input.action_release(action)
	await T.wait_physics_frames(2)


func _state() -> String:
	return str(sys.call("get_state_name"))


## Calls a cab, waits for it, gets in through the interactable. Returns the cab or null.
func _get_cab(tag: String) -> Node3D:
	var t0 := Time.get_ticks_msec()
	var here := P.global_position
	var ok := bool(sys.call("call_taxi", here))
	T.check(ok, "%s: call_taxi() accepted" % tag)
	if not ok:
		return null
	var cab: Node3D = sys.call("get_taxi")
	T.log_line("%s: cab %s at %.0f m" % [tag, str(cab.name) if cab != null else "-", cab.global_position.distance_to(here) if cab != null else -1.0])
	var game_t := 0.0
	var arrived := false
	while game_t < 60.0:
		if _state() == "waiting":
			arrived = true
			break
		if _state() == "idle":
			break
		await T.wait_seconds(0.5)
		game_t += 0.5
		if int(game_t * 2.0) % 10 == 0:
			T.log_line("%s: t=%.0f %s" % [tag, game_t, str(sys.call("get_job_info"))])
	cab = sys.call("get_taxi")
	var d := cab.global_position.distance_to(here) if cab != null else 999.0
	T.check(arrived and d < 16.0, "%s: the cab arrived at the kerb in %.0f s (%.1f m from the caller)" % [tag, game_t, d])
	if not arrived or cab == null:
		return null
	var spd := absf(float(cab.call("get_forward_speed")))
	T.check(spd < 1.0 and cab.get("driver") != null and str(cab.get("spec_id")) == "taxi",
			"%s: a taxi with its driver waits at the kerb (%.2f m/s, driver %s)" % [tag, spd, str(cab.get("driver"))])
	# walk up to it and use "Get in the cab"
	var door: Vector3 = cab.call("get_door_position", 3) if int(cab.call("get_seat_count")) > 3 else cab.call("get_door_position", 1)
	var out := door + (door - cab.global_position).normalized() * 0.8
	out.y = Game.ground_height(out.x, out.z) + 0.05
	P.call("teleport", out, 0.0)
	await T.wait_seconds(0.5)
	var prompt := str(UI.call("get_prompt_text")) if UI.has_method("get_prompt_text") else ""
	await _tap("interact")
	var seated := await _until(func() -> bool: return Game.get_player_vehicle() == cab, 6.0)
	var seat := int(cab.call("get_seat_of", P))
	T.check(seated and seat >= 1, "%s: 'Get in the cab' (prompt '%s') -> passenger seat %d" % [tag, prompt, seat])
	if not seated:
		return null
	var scr := await _until(func() -> bool: return UI.is_screen_open("taxi"), 2.0)
	T.check(scr and _state() == "choosing", "%s: the taxi screen opened (state %s)" % [tag, _state()])
	T.log_line("%s: boarding took %.1f s real" % [tag, float(Time.get_ticks_msec() - t0) / 1000.0])
	return cab


func _pick(min_d: float, max_d: float) -> Dictionary:
	var best: Dictionary = {}
	for e: Dictionary in (sys.call("get_destinations") as Array):
		if bool(e.get("disabled", false)) or str(e["id"]) == "waypoint":
			continue
		var d := float(e["distance"])
		if d >= min_d and d <= max_d and (best.is_empty() or d < float(best["distance"])):
			best = e
	return best


func _ride(skip: bool, min_d: float, max_d: float) -> void:
	var tag := "skip ride" if skip else "ride"
	var cab := await _get_cab(tag)
	if cab == null:
		return
	var dests: Array = sys.call("get_destinations")
	T.check(dests.size() >= 12, "%s: destinations listed (%d)" % [tag, dests.size()])
	var e := _pick(min_d, max_d)
	if not T.check(not e.is_empty(), "%s: a destination %d-%d m away" % [tag, int(min_d), int(max_d)]):
		return
	var money0 := Game.money
	var hour0 := WorldClock.hour + float(WorldClock.get("day")) * 24.0
	var ok := bool(sys.call("choose_destination", str(e["id"])))
	var fare := int(sys.get("fare_quote"))
	T.check(ok and _state() == "ride" and not UI.is_screen_open("taxi"), "%s: destination '%s' (%s, %.0f m) chosen, fare $%d" % [tag,
			str(e["label"]), str(e["district_label"]), float(e["distance"]), fare])
	if not ok:
		return
	var drop: Vector3 = (e["drop"] as Dictionary)["pos"]
	var start := cab.global_position
	var took := 0.0
	var max_speed := 0.0
	if skip:
		await T.wait_seconds(4.0)
		T.check(cab.global_position.distance_to(start) > 5.0, "skip ride: the cab drives off before the skip")
		await _tap("skip")
		await T.wait_seconds(3.5)
		took = 7.5
	else:
		while took < 150.0:
			if _state() == "arrived" or _state() == "idle":
				break
			await T.wait_seconds(0.5)
			took += 0.5
			max_speed = maxf(max_speed, absf(float(cab.call("get_forward_speed"))) if is_instance_valid(cab) else 0.0)
			if int(took * 2.0) % 20 == 0:
				T.log_line("%s: t=%.0f %s" % [tag, took, str(sys.call("get_job_info"))])
	var at_d := cab.global_position.distance_to(drop) if is_instance_valid(cab) else 999.0
	T.check(_state() == "arrived" or _state() == "idle", "%s: arrived (state %s after %.0f s, top speed %.1f m/s)" % [tag, _state(), took, max_speed])
	T.check(at_d < 7.0, "%s: the cab stopped %.1f m from the drop-off point" % [tag, at_d])
	await _until(func() -> bool: return _state() == "idle", 6.0)
	var paid := money0 - Game.money
	T.check(paid == fare and fare > 0, "%s: fare charged ($%d paid, quote $%d)" % [tag, paid, fare])
	T.check(Game.get_player_vehicle() == null and P.global_position.distance_to(drop) < 8.0,
			"%s: the passenger got out at the kerb (%.1f m from the drop-off)" % [tag, P.global_position.distance_to(drop)])
	if skip:
		var hour1 := WorldClock.hour + float(WorldClock.get("day")) * 24.0
		T.check(hour1 - hour0 > 0.25, "skip ride: the clock moved on by the trip time (%.2f h)" % (hour1 - hour0))
	else:
		T.check(cab.global_position.distance_to(start) > 100.0 or took > 20.0, "ride: the cab really drove (%.0f m from the pickup)" % cab.global_position.distance_to(start))
	await T.wait_seconds(2.0)
	T.check(not is_instance_valid(cab) or cab.get("taxi_for_hire") == true, "%s: the cab is for hire again afterwards" % tag)


func _refuse() -> void:
	var cab := await _get_cab("refuse")
	if cab == null:
		return
	var keep := Game.money
	Game.money = 0
	var e := _pick(250.0, 2000.0)
	var ok := bool(sys.call("choose_destination", str(e.get("id", ""))))
	T.check(not ok and _state() == "choosing", "no money: the driver refuses (state %s)" % _state())
	Game.money = keep
	UI.close_screen("taxi")
	await T.wait_seconds(0.3)
	await _tap("enter_vehicle")
	var out := await _until(func() -> bool: return Game.get_player_vehicle() == null, 4.0)
	await T.wait_seconds(0.5)
	T.check(out and _state() == "idle" and Game.money == keep, "leaving the waiting cab ends the job without a fare")


func _early_stop() -> void:
	var cab := await _get_cab("stop")
	if cab == null:
		return
	var e := _pick(400.0, 2000.0)
	var money0 := Game.money
	if not T.check(bool(sys.call("choose_destination", str(e.get("id", "")))), "stop: ride started"):
		return
	var fare := int(sys.get("fare_quote"))
	await T.wait_seconds(9.0)
	var prompt := str(UI.call("get_prompt_text")) if UI.has_method("get_prompt_text") else ""
	await _tap("enter_vehicle")
	var stopped := await _until(func() -> bool: return _state() == "arrived" or _state() == "idle", 25.0)
	await _until(func() -> bool: return _state() == "idle", 6.0)
	var paid := money0 - Game.money
	T.check(stopped and Game.get_player_vehicle() == null, "stop: '%s' -> the cab pulled over and the passenger got out" % prompt)
	T.check(paid > 0 and paid < fare, "stop: paid $%d for %.0f m (full quote $%d)" % [paid, float(sys.get("ride_m")), fare])
