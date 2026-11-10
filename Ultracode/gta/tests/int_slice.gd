extends Node
## Lead integration test: plays through the vertical slice with the REAL systems and takes
## gameplay-camera screenshots (windowed). Headless runs still check the gameplay path.
##   tools\godot.ps1 -Mode window -Frames 2400 -TimeoutSec 240 -UserArgs '--test=int_slice','--test-timeout=200'


func _ready() -> void:
	await TestHarness.wait_frames(20)
	var p: Node3D = Game.player
	TestHarness.check(p != null, "player spawned")
	if p == null:
		TestHarness.finish(false, "no player")
		return
	if Weather.has_method("snap_weather"):
		Weather.call("snap_weather", "clear")
	Weather.auto_cycle = false
	WorldClock.set_hour(11.0)
	WorldClock.paused = true
	await TestHarness.wait_seconds(1.5)
	await TestHarness.shot("int_01_spawn")

	# --- on foot downtown ----------------------------------------------------------------
	_tp("downtown_plaza")
	await TestHarness.wait_seconds(1.5)
	Input.action_press("move_forward")
	await TestHarness.wait_seconds(1.2)
	await TestHarness.shot("int_02_walk_downtown")
	Input.action_release("move_forward")
	var start_pos := p.global_position

	# --- weapon -----------------------------------------------------------------------------
	var inv: Node = p.get("inventory")
	TestHarness.check(inv != null, "player has an inventory")
	if inv != null:
		inv.call("give_weapon", "assault_rifle", 120)
		inv.call("equip", "assault_rifle")
		await TestHarness.wait_seconds(0.6)
		Input.action_press("aim")
		await TestHarness.wait_seconds(0.8)
		await TestHarness.shot("int_03_aim_rifle")
		Input.action_press("fire")
		await TestHarness.wait_seconds(0.25)
		await TestHarness.shot("int_04_fire_rifle")
		Input.action_release("fire")
		Input.action_release("aim")
		var ammo: Dictionary = inv.call("get_ammo", "assault_rifle")
		TestHarness.check(int(ammo.get("in_mag", 999)) < 30 or int(ammo.get("reserve", 999)) < 120, "rifle consumed ammo: %s" % str(ammo))
		inv.call("holster")

	# --- car ----------------------------------------------------------------------------------
	var fwd := -p.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var car_pos := p.global_position + fwd * 6.0
	car_pos.y = Game.ground_height(car_pos.x, car_pos.z) + 0.6
	var xf := Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), car_pos)
	var car: Node3D = Game.spawn_vehicle("sports", xf, {"owner_tag": "parked"})
	TestHarness.check(car != null, "sports car spawned")
	if car != null:
		await TestHarness.wait_seconds(1.0)
		p.call("enter_vehicle", car, 0)
		await TestHarness.wait_seconds(3.0)
		TestHarness.check(p.get("current_vehicle") == car, "player is in the car")
		var c0 := car.global_position
		Input.action_press("move_forward")
		await TestHarness.wait_seconds(3.5)
		await TestHarness.shot("int_05_drive")
		Input.action_press("move_right")
		await TestHarness.wait_seconds(1.0)
		await TestHarness.shot("int_06_drive_turn")
		Input.action_release("move_right")
		Input.action_release("move_forward")
		Input.action_press("move_back")
		await TestHarness.wait_seconds(1.5)
		Input.action_release("move_back")
		var moved := car.global_position.distance_to(c0)
		TestHarness.check(moved > 8.0, "car moved %.1f m" % moved)
		WorldClock.set_hour(21.5)
		await TestHarness.wait_seconds(1.0)
		await TestHarness.shot("int_07_car_night")
		WorldClock.set_hour(11.0)
		p.call("exit_vehicle")
		await TestHarness.wait_seconds(2.0)
		TestHarness.check(p.get("current_vehicle") == null, "player left the car")

	# --- tour -----------------------------------------------------------------------------
	var tour := [["hill_viewpoint", "int_08_hill"], ["beach", "int_09_beach"], ["marina_dock", "int_10_marina"],
			["industrial_yard", "int_11_industrial"], ["airport_runway_start", "int_12_airport"],
			["residential_park", "int_13_residential"]]
	for t in tour:
		_tp(t[0])
		await TestHarness.wait_seconds(1.6)
		await TestHarness.shot(t[1])

	# --- wanted HUD + map ------------------------------------------------------------------
	_tp("downtown_plaza")
	await TestHarness.wait_seconds(1.0)
	Wanted.set_level(3)
	await TestHarness.wait_seconds(0.8)
	await TestHarness.shot("int_14_wanted_hud")
	TestHarness.check(Wanted.level == 3, "wanted level set")
	Wanted.clear("cheat")
	var map: Control = UI.open_screen("map")
	await TestHarness.wait_seconds(0.8)
	await TestHarness.shot("int_15_map")
	if map != null:
		UI.close_screen("map")
	TestHarness.check(p.global_position.distance_to(start_pos) < 2000.0, "player still on the island")
	TestHarness.finish()


func _tp(loc: String) -> void:
	var xf := Game.get_location(loc)
	if Game.player.has_method("teleport"):
		Game.player.teleport(xf.origin, xf.basis.get_euler().y)
	else:
		Game.player.global_transform = xf
