extends Node
## trn_tram (headless, full game): the Bay Tram loop with the REAL player.
##   1. data: trams on the loop, 3 stops, junction stop lines, the rails mesh of the world
##   2. tram 1 dwells at stop 1 with the right doors open; the player walks up to door 1 and presses
##      interact ("Board the tram"), sits down ("Sit down", vehicle-seat contract), rides seated,
##      stands up while moving (enter-vehicle key), rides standing (stays inside the moving car,
##      sampled every 0.25 s), gets off at stop 2 ("Get off")
##   3. the tram completes the loop (every stop served, loop counter) - also the second tram
##   4. obstacle on the rails: a parked sedan ahead -> the tram stops behind it (gap, the car is not
##      pushed), the car is removed -> the tram goes on; a sedan driven into the side of a waiting
##      tram takes damage, the tram does not move
## Run:
##   tools\godot.ps1 -Mode headless -Frames 30000 -TimeoutSec 420 -UserArgs '--test=trn_tram','--test-timeout=400','--disable=police,emergency,wildlife,activities'

var T: Node
var sys: Node
var P: Node3D


func _ready() -> void:
	T = TestHarness
	await T.wait_physics_frames(20)
	sys = Game.get_system("transit")
	P = Game.player
	if not T.check(sys != null and P != null, "transit system and player exist"):
		T.finish(false, "no transit system / player")
		return
	var info: Dictionary = sys.call("get_debug_info")
	T.log_line("TRANSIT " + str(info))
	T.check(int(info["trams"]) >= 1, "trams on the loop (%d)" % int(info["trams"]))
	T.check(int(info["stops"]) == 3, "three tram stops (%d)" % int(info["stops"]))
	T.check(float(info["loop_m"]) > 700.0, "loop length %.0f m" % float(info["loop_m"]))
	T.check(int(info["lines"]) >= 6, "junction stop lines found along the rails (%d)" % int(info["lines"]))
	var trams: Array = sys.call("get_trams")
	var tram: Node3D = trams[0]

	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--trn_only="):
			only = a.substr(11)
	if only == "" or only.contains("ride"):
		await _ride_test(tram)
	if only == "" or only.contains("loop"):
		await _loop_test(trams)
	if only == "" or only.contains("obstacle"):
		await _obstacle_test(trams)
	if only == "" or only.contains("side"):
		await _side_hit_test(trams)
	T.log_line("TRANSIT END " + str(sys.call("get_debug_info")))
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


func _ride_test(tram: Node3D) -> void:
	var ok := await _until(func() -> bool: return bool(tram.call("is_door_open")) and int(tram.get("last_stop")) == 0, 25.0)
	T.check(ok, "tram 1 dwells at stop 1 with the doors open (door %.2f)" % float(tram.get("door")))
	# door leaves really slid open
	var leaf := (tram.get("model") as Node3D).find_child("Door_R1_A", true, false) as Node3D
	T.check(leaf != null and leaf.position.z < -4.5, "door leaf Door_R1_A slid open (z %.2f)" % (leaf.position.z if leaf != null else 0.0))
	# walk up to door 1 (outside, on the road)
	var out: Vector3 = tram.call("door_point", 0, 0.9)
	var r: Vector3 = (tram as Node3D).global_basis.x
	P.call("teleport", Vector3(out.x, Game.ground_height(out.x, out.z) + 0.05, out.z), atan2(r.x, r.z))
	await T.wait_seconds(0.5)
	var prompt := str(UI.call("get_prompt_text")) if UI.has_method("get_prompt_text") else ""
	T.log_line("prompt at the door: '%s'" % prompt)
	await _tap("interact")
	await T.wait_seconds(0.3)
	var aboard: bool = sys.call("get_player_tram") == tram
	T.check(aboard, "boarded through the 'Board the tram' interactable (prompt '%s')" % prompt)
	if not aboard:
		sys.call("board", tram, 0)
		await T.wait_seconds(0.3)
	# sit down at seat 3
	var aisle: Transform3D = tram.call("get_exit_transform", 3)
	P.call("teleport", aisle.origin + Vector3.UP * 0.05, P.global_rotation.y)
	await T.wait_seconds(0.4)
	await _tap("interact")
	var seated := await _until(func() -> bool: return Game.get_player_vehicle() == tram, 3.0)
	T.check(seated, "sat down through the 'Sit down' interactable (seat %d)" % int(tram.call("get_seat_of", P)))
	if not seated:
		sys.call("sit", tram, 3)
		await T.wait_seconds(1.0)
	var moving := await _until(func() -> bool: return float(tram.get("v")) > 5.0, 40.0)
	T.check(moving, "the tram departed and runs (%.1f m/s)" % float(tram.get("v")))
	var seat_node: Node3D = tram.call("get_seat_node", maxi(int(tram.call("get_seat_of", P)), 1))
	var glued := seat_node != null and P.global_position.distance_to(seat_node.global_position) < 0.3
	T.check(Game.get_player_vehicle() == tram and glued, "seated rider rides along on the seat marker")
	T.check(float(tram.get("door")) < 0.05, "doors closed while moving")
	# stand up while moving (enter-vehicle key -> 'Stand up')
	await _tap("enter_vehicle")
	await T.wait_seconds(0.4)
	T.check(Game.get_player_vehicle() == null and sys.call("get_player_tram") == tram,
			"stood up while moving: on foot inside the tram")
	# standing ride until stop 2
	var lost := false
	var max_lat := 0.0
	var max_v := 0.0
	var min_y := 99.0
	var tt := 0.0
	var log_t := 0.0
	while tt < 120.0:
		if int(tram.get("phase")) == 1 and int(tram.get("last_stop")) == 1:
			break
		await T.wait_seconds(0.25)
		tt += 0.25
		log_t += 0.25
		if log_t >= 4.0:
			log_t = 0.0
			T.log_line("ride t=%.0f %s" % [tt, str(sys.call("get_tram_info", 0))])
		var l: Vector3 = tram.call("to_local_point", P.global_position)
		max_lat = maxf(max_lat, absf(l.x))
		min_y = minf(min_y, l.y)
		max_v = maxf(max_v, float(tram.get("v")))
		if not bool(tram.call("contains_point", P.global_position, 0.3)):
			lost = true
	T.check(not lost, "standing rider stayed inside the moving tram (max |x| %.2f m, min floor y %.2f, top speed %.1f m/s)" % [max_lat, min_y, max_v])
	var at2 := await _until(func() -> bool: return bool(tram.call("is_door_open")) and int(tram.get("last_stop")) == 1, 15.0)
	T.check(at2, "tram 1 arrived at stop 2 and opened the doors")
	# get off at door 1
	var sp: Vector3 = tram.call("stand_point", 0)
	P.call("teleport", sp + Vector3.UP * 0.05, P.global_rotation.y)
	await T.wait_seconds(0.4)
	await _tap("interact")
	await T.wait_seconds(0.5)
	var stops: Array = sys.call("get_stops")
	var st2: Vector3 = stops[1]["position"]
	var off_ok: bool = sys.call("get_player_tram") == null and Game.get_player_vehicle() == null
	T.check(off_ok and P.global_position.distance_to(st2) < 14.0,
			"got off at stop 2 ('Get off'), %.1f m from the stop" % P.global_position.distance_to(st2))
	await T.wait_seconds(1.0)
	T.check(absf(P.global_position.y - Game.ground_height(P.global_position.x, P.global_position.z)) < 0.4,
			"standing on the street after getting off")
	# walk away from the rails so the tram is free to go
	var plat: Transform3D = stops[1]["platform"]
	P.call("teleport", plat.origin + Vector3.UP * 0.1, 0.0)


func _loop_test(trams: Array) -> void:
	var tram: Node3D = trams[0]
	var done := await _until(func() -> bool: return int(tram.get("loops")) >= 1, 230.0)
	var vis: PackedInt32Array = tram.get("visits")
	T.check(done, "tram 1 completed the loop (loops %d, odometer %.0f m)" % [int(tram.get("loops")), float(tram.get("odometer"))])
	T.check(vis.size() == 3 and vis[0] >= 1 and vis[1] >= 1 and vis[2] >= 1, "tram 1 stopped at all three stops %s" % str(vis))
	if trams.size() > 1:
		var t2: Node3D = trams[1]
		var v2: PackedInt32Array = t2.get("visits")
		T.check(v2.size() == 3 and v2[0] + v2[1] + v2[2] >= 3, "tram 2 serves the stops too %s (odometer %.0f m)" % [str(v2), float(t2.get("odometer"))])
	var d: Dictionary = sys.call("get_debug_info")
	T.log_line("after loop: " + str(d))
	T.check(float(d.get("top_speed", 0.0)) > 9.5 and float(d.get("top_speed", 0.0)) <= 11.05,
			"trams reach their cruise speed on the long straights (top %.1f m/s, cap 11)" % float(d.get("top_speed", 0.0)))
	T.check(int(d.get("signal_holds", 0)) >= 0, "signal holds %d, obstacle holds %d, emergency brakes %d" % [int(d.get("signal_holds", 0)),
			int(d.get("obstacle_holds", 0)), int(d.get("emergency_brakes", 0))])


## A sedan parked on the rails ahead of a running tram: the tram stops behind it without pushing it.
func _obstacle_test(trams: Array) -> void:
	var tram: Node3D = trams[0]
	# wait until the tram is running on a straight away from stops
	await _until(func() -> bool: return int(tram.get("phase")) == 0 and float(tram.get("v")) > 4.0, 40.0)
	var path: Object = sys.get("path")
	var s0 := float(tram.get("s"))
	# put the car 45 m ahead of the nose, on a straight piece of the rails
	var put := 45.0
	for k in 12:
		var r := float(path.call("radius_at", s0 + 9.2 + put))
		if r > 200.0:
			break
		put += 8.0
	var ps: Vector3 = path.call("sample", s0 + 9.2 + put)
	var tg: Vector3 = path.call("tangent", s0 + 9.2 + put)
	P.call("teleport", ps + Vector3(0.0, 0.2, 0.0) - tg * 30.0 + Vector3(tg.z, 0.0, -tg.x) * 6.0, 0.0)
	var xf := Transform3D(Basis.looking_at(tg, Vector3.UP), ps + Vector3.UP * 0.1)
	var car: Node3D = Game.spawn_vehicle("sedan", xf, {"owner_tag": "civilian", "engine_on": false})
	if not T.check(car != null, "test sedan spawned on the rails"):
		return
	await T.wait_seconds(1.0)
	var car_p0 := car.global_position
	var held := await _until(func() -> bool: return tram.get("obs_node") == car and float(tram.get("v")) < 0.1, 60.0)
	await T.wait_seconds(1.5)
	var gap := float(path.call("ahead", float(tram.get("s")) + 9.19, float(path.call("project", car.global_position)))) - 2.3
	T.check(held, "tram stopped for the car on the rails (hold '%s', v %.2f)" % [str(tram.get("hold")), float(tram.get("v"))])
	T.check(gap > 0.8, "standstill gap to the car %.1f m (no contact)" % gap)
	T.check(car.global_position.distance_to(car_p0) < 0.3, "the car was not pushed (%.2f m)" % car.global_position.distance_to(car_p0))
	var vm := Game.get_system("vehicles")
	if vm != null and vm.has_method("despawn_vehicle"):
		vm.call("despawn_vehicle", car)
	else:
		car.queue_free()
	var went := await _until(func() -> bool: return float(tram.get("v")) > 2.0, 8.0)
	T.check(went, "tram continued after the rails were cleared")


## A sedan driven into the side of a waiting tram: the car takes damage, the tram does not move.
func _side_hit_test(trams: Array) -> void:
	var tram: Node3D = trams[0]
	var at := await _until(func() -> bool: return int(tram.get("phase")) == 1 and float(tram.get("dwell_t")) < 6.0, 90.0)
	if not T.check(at, "tram waiting at a stop for the side impact test"):
		return
	var txf := tram.global_transform
	var left := -txf.basis.x
	var start := txf.origin + left * 14.0 + txf.basis.z * 1.0
	var face := -left
	var xf := Transform3D(Basis.looking_at(face, Vector3.UP), start + Vector3.UP * 0.2)
	var stops: Array = sys.call("get_stops")
	var plat: Transform3D = stops[clampi(int(tram.get("last_stop")), 0, stops.size() - 1)]["platform"]
	P.call("teleport", plat.origin + Vector3.UP * 0.1, 0.0)
	var car: Node3D = Game.spawn_vehicle("sedan", xf, {"owner_tag": "civilian", "engine_on": true, "velocity": face * 13.0})
	if not T.check(car != null, "side impact sedan spawned"):
		return
	var hp0 := float(car.get("health"))
	var s_before := float(tram.get("s"))
	await T.wait_seconds(2.5)
	var hp1 := float(car.get("health")) if is_instance_valid(car) else 0.0
	T.check(hp1 < hp0, "the car that hit the tram took damage (%.0f -> %.0f)" % [hp0, hp1])
	T.check(tram.global_transform.origin.distance_to(txf.origin) < 0.05 and absf(float(tram.get("s")) - s_before) < 0.01,
			"the tram was not moved by the impact")
	if is_instance_valid(car):
		var vm := Game.get_system("vehicles")
		if vm != null and vm.has_method("despawn_vehicle"):
			vm.call("despawn_vehicle", car)
