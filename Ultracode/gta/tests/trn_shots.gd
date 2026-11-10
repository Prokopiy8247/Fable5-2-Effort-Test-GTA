extends Node
## trn_shots (windowed, short): screenshots of the transit features -> qa/screenshots/trn_*.png
##   --trn_only=tram : trn_tram_doors (stop 1, doors open, from the platform), trn_tram_inside (gameplay
##                     camera, standing rider), trn_tram_interior (aisle view), trn_tram_seated (gameplay
##                     camera, seated rider), trn_tram_corner (a 14 m corner from above), trn_tram_night
##   --trn_only=taxi : trn_taxi_screen (destination picker in the cab), trn_taxi_ride (riding in the back)
## The scene is staged through the public APIs (tram held at its stop, cab spawned beside the player).
## Run (one part per run, each well under 20 s of rendering):
##   tools\godot.ps1 -Mode window -Frames 560 -TimeoutSec 200 -UserArgs '--test=trn_shots','--test-timeout=180','--trn_only=tram','--disable=police,emergency,wildlife,activities'
##   tools\godot.ps1 -Mode window -Frames 560 -TimeoutSec 200 -UserArgs '--test=trn_shots','--test-timeout=180','--trn_only=taxi','--disable=police,emergency,wildlife,activities'

var T: Node
var P: Node3D
var cam: Camera3D = null


func _ready() -> void:
	T = TestHarness
	await T.wait_physics_frames(10)
	P = Game.player
	var only := "tram"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--trn_only="):
			only = a.substr(11)
	WorldClock.set_hour(13.0)
	if Weather.has_method("set_weather"):
		Weather.set_weather("clear", 0.0)
	if only.contains("tram"):
		await _tram_shots()
	if only.contains("taxi"):
		await _taxi_shots()
	T.finish()


func _own_cam(pos: Vector3, look: Vector3) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 62.0
		add_child(cam)
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.make_current()


func _game_cam() -> void:
	if cam != null:
		cam.clear_current(false)
	var rig: Variant = Game.camera_rig
	if rig != null and rig is Node:
		var found := (rig as Node).find_children("*", "Camera3D", true, false)
		if not found.is_empty():
			(found[0] as Camera3D).make_current()


func _tram_shots() -> void:
	var sys := Game.get_system("transit")
	if not T.check(sys != null, "transit system"):
		return
	var tram: Node3D = (sys.call("get_trams") as Array)[0]
	var stops: Array = sys.call("get_stops")
	# hold tram 1 at stop 1 with the doors open
	tram.set("s", float(stops[0]["s"]))
	tram.set("phase", 1)
	tram.set("dwell_t", 2.0)
	tram.set("dwell_len", 90.0)
	tram.set("last_stop", 0)
	tram.set("next_stop", 1)
	var plat: Transform3D = stops[0]["platform"]
	P.call("teleport", plat.origin + Vector3.UP * 0.1, PI)
	await T.wait_seconds(2.5)
	var xf: Transform3D = tram.global_transform
	_own_cam(xf * Vector3(9.0, 1.9, 1.5), xf * Vector3(0.0, 1.2, -3.0))
	await T.wait_frames(3)
	await T.shot("trn_tram_doors")
	T.check(bool(tram.call("is_door_open")), "doors open at the stop")
	# board and stand inside (gameplay camera)
	sys.call("board", tram, 0)
	await T.wait_seconds(0.3)
	_game_cam()
	if Game.camera_rig != null and Game.camera_rig.has_method("snap_to"):
		var f: Vector3 = -xf.basis.z
		Game.camera_rig.call("snap_to", atan2(-f.x, -f.z))
	await T.wait_seconds(1.0)
	await T.shot("trn_tram_inside")
	T.check(sys.call("get_player_tram") == tram, "player aboard (standing)")
	_own_cam(xf * Vector3(-0.35, 1.75, 6.9), xf * Vector3(0.2, 1.1, -4.0))
	await T.wait_frames(3)
	await T.shot("trn_tram_interior")
	# sit down (gameplay vehicle camera)
	sys.call("sit", tram, 3)
	await T.wait_seconds(1.2)
	_game_cam()
	await T.wait_seconds(0.8)
	await T.shot("trn_tram_seated")
	T.check(Game.get_player_vehicle() == tram, "player seated")
	# a corner from above: put tram 2 into the 14 m corner at Marlin Avenue / Foundry Street
	var trams: Array = sys.call("get_trams")
	if trams.size() > 1:
		var t2: Node3D = trams[1]
		var path: Object = sys.get("path")
		var corner := Vector3(-118.25, 2.53, -103.25)
		var cs := float(path.call("project", corner))
		t2.set("s", cs)
		t2.set("phase", 1)
		t2.set("dwell_t", 2.0)
		t2.set("dwell_len", 90.0)
		t2.set("door_target", 0.0)
		await T.wait_seconds(0.5)
		_own_cam(corner + Vector3(16.0, 22.0, 16.0), corner + Vector3(3.0, 0.0, 3.0))
		await T.wait_frames(4)
		await T.shot("trn_tram_corner")
	# night look of tram 1
	WorldClock.set_hour(22.3)
	await T.wait_seconds(1.6)
	_own_cam(xf * Vector3(7.0, 2.4, -16.0), xf * Vector3(0.0, 1.3, -2.0))
	await T.wait_frames(6)
	await T.shot("trn_tram_night")
	WorldClock.set_hour(13.0)


func _taxi_shots() -> void:
	var sys := Game.get_system("taxi")
	var tr := Game.get_system("traffic")
	if not T.check(sys != null and tr != null and Game.world != null, "taxi + traffic"):
		return
	var stand: Transform3D = Game.get_location("taxi_stand")
	P.call("teleport", stand.origin + Vector3.UP * 0.1, 0.0)
	await T.wait_seconds(1.5)
	var roads: Variant = Game.world.get("roads")
	var lanes: Variant = tr.get("lanes")
	var helper := TaxiDestinations.new()
	helper.setup(roads, lanes)
	var pk := helper.drop_point(P.global_position, 30.0)
	if not T.check(not pk.is_empty(), "kerb lane next to the stand"):
		return
	var cab: Node3D = tr.call("spawn_traffic_vehicle", int(pk["lane"]), maxf(float(pk["s"]) - 3.0, 6.0), "taxi")
	if not T.check(cab != null, "cab spawned beside the player"):
		return
	P.call("enter_vehicle", cab, 3, true)
	await T.wait_seconds(1.0)
	T.check(UI.is_screen_open("taxi"), "taxi screen open")
	await T.shot("trn_taxi_screen")
	var best: Dictionary = {}
	for e: Dictionary in (sys.call("get_destinations") as Array):
		var d := float(e["distance"])
		if not bool(e.get("disabled", false)) and d > 300.0 and d < 700.0 and str(e["id"]) != "waypoint":
			best = e
			break
	T.check(not best.is_empty() and bool(sys.call("choose_destination", str(best["id"]))), "ride started")
	await T.wait_seconds(5.0)
	await T.shot("trn_taxi_ride")
	await T.wait_seconds(3.0)
	await T.shot("trn_taxi_ride2")
