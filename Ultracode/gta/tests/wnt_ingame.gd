extends Node
## Wanted system in the real game: real player, real Combat gunfire, real vehicle entry, HUD.
## Pedestrians / police / traffic are disabled, so the island is "deserted" except for the
## dummy listeners this test places. Headless (checks) or a short windowed run (screenshots):
##   tools\godot.ps1 -Mode headless -Frames 4000 -TimeoutSec 240 -UserArgs '--test=wnt_ingame','--disable=traffic,peds,police,emergency,wildlife,radio,ambience,debug','--test-timeout=150'
##   tools\godot.ps1 -Mode window   -Frames 600  -TimeoutSec 120 -UserArgs '--test=wnt_ingame','--disable=traffic,peds,police,emergency,wildlife,radio,ambience,debug','--test-timeout=60'
## Screenshots: qa/screenshots/wnt_search.png (flashing stars + search circle), wnt_pursuit.png.

var T: Node
var _crimes: Array = []
var _disguise: Array = []
var _busted: int = 0
var _cleared: Array = []
var _peds: Array[Node3D] = []


func _ready() -> void:
	T = TestHarness
	EventBus.crime_committed.connect(func(id: String, _p: Vector3, _w: Node) -> void: _crimes.append(id))
	EventBus.player_busted.connect(func() -> void: _busted += 1)
	EventBus.wanted_cleared.connect(func(r: String) -> void: _cleared.append(r))
	Wanted.disguise_applied.connect(func(k: String, _e: float, _r: float) -> void: _disguise.append(k))
	await T.wait_seconds(1.0)
	await _run()
	Wanted.debug_time_scale = 1.0
	Wanted.clear("cheat")
	for p in _peds:
		if is_instance_valid(p):
			p.queue_free()
	T.finish()


func _player() -> Node3D:
	return Game.player if Game.has_player() else null


func _fire_once(inv: Node) -> void:
	Input.action_press("aim")
	await T.wait_seconds(0.5)
	Input.action_press("fire")
	await T.wait_seconds(0.12)
	Input.action_release("fire")
	await T.wait_seconds(0.2)
	Input.action_release("aim")
	if inv != null:
		inv.call("holster")


func _run() -> void:
	var p := _player()
	if not T.check(p != null, "real player present"):
		return
	var xf := Game.get_location("downtown_plaza")
	p.call("teleport", xf.origin, xf.basis.get_euler().y)
	await T.wait_seconds(1.0)
	var inv: Node = p.get("inventory")
	if not T.check(inv != null, "player has an inventory"):
		return
	inv.call("give_weapon", "pistol", 60)
	inv.call("equip", "pistol")
	await T.wait_seconds(0.6)

	# windowed runs (GPU budget <= 20 s) only take the two screenshots
	if T.is_headless():
		await _deserted_part(inv)
	await _listeners_part(p, inv)
	if T.is_headless():
		await _vehicle_and_bust_part(p)


func _deserted_part(inv: Node) -> void:
	# 1. real gunfire with nobody around: pending, then forgotten
	Wanted.debug_time_scale = 10.0
	await _fire_once(inv)
	var recs: Array[Dictionary] = Wanted.get_crime_records()
	T.check(_crimes.has("gunfire"), "Combat reported the player's gunfire to Wanted (%s)" % str(_crimes))
	T.check(Wanted.level == 0 and recs.size() >= 1 and str(recs.back()["status"]) == "pending",
			"gunfire with nobody around stays pending (no stars)")
	if not recs.is_empty():
		T.check(float(recs.back()["loud"]) > 10.0 and int(recs.back()["listeners"]) == 0,
				"earshot radius taken from the shot's noise (%.0f m), 0 listeners" % float(recs.back()["loud"]))
	await T.wait_seconds(Wanted.Config.PENDING_TTL / 10.0 + 0.4)
	T.check(Wanted.level == 0 and Wanted.get_pending_count() == 0, "deserted gunfire expired without stars")
	inv.call("equip", "pistol")
	await T.wait_seconds(1.7)                       # Combat throttles gunfire reports (90 frames)


func _listeners_part(p: Node3D, inv: Node) -> void:
	# 2. the same with three people nearby: indirect report after 6-10 s -> SEARCH
	var c := p.global_position
	for i in 3:
		var n := Node3D.new()
		n.name = "WntListener%d" % i
		add_child(n)
		n.add_to_group("ped")
		n.global_position = c + Vector3(cos(float(i) * 2.1) * 25.0, 0.0, sin(float(i) * 2.1) * 25.0)
		_peds.append(n)
	Wanted.debug_time_scale = 4.0
	var n_crimes := _crimes.size()
	await _fire_once(inv)
	T.check(_crimes.size() > n_crimes and Wanted.level == 0, "second shot reported, still no stars right away")
	var t0 := Time.get_ticks_msec()
	var guard := 0
	while Wanted.level == 0 and guard < 600:
		await get_tree().physics_frame
		guard += 1
	T.check(Wanted.level == 1 and Wanted.state == Wanted.State.SEARCH, "people within earshot called it in -> 1 star, SEARCH")
	T.check(Wanted.last_known_position.distance_to(c) < 30.0, "search centred near the shots (%.1f m)" % Wanted.last_known_position.distance_to(c))
	Wanted.debug_time_scale = 0.0                   # freeze for the screenshot
	await T.wait_seconds(0.4)
	var hud: Variant = UI.get("hud")
	if hud != null and is_instance_valid(hud) and (hud as Object).has_method("get_state"):
		var st: Dictionary = (hud as Object).call("get_state")
		T.check(int(st["wanted_level"]) == 1 and int(st["wanted_state"]) == Wanted.State.SEARCH, "HUD shows 1 star in SEARCH")
	await T.shot("wnt_search")

	# 3. police spot the player: PURSUIT
	Wanted.debug_time_scale = 1.0
	Wanted.set_level(3)
	Wanted.police_sighting(null, p.global_position)
	await T.wait_seconds(0.3)
	T.check(Wanted.level == 3 and Wanted.state == Wanted.State.PURSUIT, "sighting -> PURSUIT at 3 stars")
	await T.shot("wnt_pursuit")


func _vehicle_and_bust_part(p: Node3D) -> void:
	# 4. contact lost, then the player takes a car while unseen: vehicle-change benefit
	Wanted.debug_time_scale = 4.0
	var guard := 0
	while Wanted.state != Wanted.State.SEARCH and guard < 600:
		await get_tree().physics_frame
		guard += 1
	await T.wait_seconds(0.5)
	T.check(Wanted.state == Wanted.State.SEARCH, "contact lost -> SEARCH")
	var fwd := -p.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var car_pos := p.global_position + fwd * 5.0
	car_pos.y = Game.ground_height(car_pos.x, car_pos.z) + 0.6
	var car: Node3D = Game.spawn_vehicle("sedan", Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), car_pos), {"owner_tag": "parked"})
	if T.check(car != null, "sedan spawned"):
		Wanted.debug_time_scale = 1.0
		var rd0: float = Wanted.get_recognition_delay()
		await T.wait_seconds(0.8)
		p.call("enter_vehicle", car, 0)
		guard = 0
		while p.get("current_vehicle") != car and guard < 400:
			await get_tree().physics_frame
			guard += 1
		await T.wait_seconds(0.3)
		T.check(p.get("current_vehicle") == car, "player entered the sedan")
		T.check(_disguise == ["vehicle"] and Wanted.get_recognition_delay() > rd0 and Wanted.level == 3,
				"entering a new car while unseen: one vehicle credit, recognition delay %.2f -> %.2f s, still 3 stars" % [rd0, Wanted.get_recognition_delay()])

		# 5. stopped in the car, calm: arrestable -> bust
		Wanted.debug_time_scale = 10.0
		await T.wait_seconds(0.5)
		Wanted.debug_time_scale = 1.0
		T.check(Wanted.is_player_arrestable(), "stopped car, no recent attack -> arrestable")
		Wanted.bust()
		T.check(_busted == 1 and _cleared.back() == "busted" and Wanted.level == 0, "bust(): player_busted + cleared('busted')")
		if p.has_method("exit_vehicle"):
			p.call("exit_vehicle")
		await T.wait_seconds(1.0)
