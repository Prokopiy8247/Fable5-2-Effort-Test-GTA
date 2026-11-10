extends Node
## Activities screenshots (windowed, one short run per part; LOOK at the PNGs afterwards).
##   tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 220 -UserArgs '--test=act_shots','--act_only=range','--test-timeout=200','--hour=13','--freeze-time','--weather=clear','--disable=traffic,peds,police,emergency,wildlife,taxi,transit'
## parts (--act_only=): range | stunt | race   -> qa/screenshots/act_*.png
##   range: act_range_popups (handgun course, steel plates up, aiming), act_range_turners (ring faces)
##   stunt: act_stunt_air (sports car mid-air off stunt_ramp_1, slow motion)
##   race:  act_race_start (countdown on the grid under the arch), act_race_checkpoint (next column)
##   sea:   act_sea_start (speedboat on the grid by the marina pier)
##   trail: act_trail_start (motorcycle under the arch at the foot of Signal Hill Road)

var sys = null
var player = null
var part: String = "range"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--act_only="):
			part = a.substr(11)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	await TestHarness.wait_frames(10)
	sys = Game.get_system("activities")
	player = Game.player if Game.has_player() else null
	if not TestHarness.check(sys != null and player != null, "activities system + player"):
		TestHarness.finish(false, "missing")
		return
	sys.show_results = false
	match part:
		"range":
			await _range()
		"stunt":
			await _stunt()
		"race":
			await _race()
		"sea":
			await _race_start_only("race_harbor_sprint", "act_sea_start")
		"trail":
			await _race_start_only("race_hill_trail", "act_trail_start")
	TestHarness.finish()


func _range() -> void:
	var p: Dictionary = sys.get_point("range_handgun")
	player.teleport((p["xform"] as Transform3D).origin + Vector3.UP * 0.05, 0.0)
	await _frames(5)
	var ok: bool = await sys.start_activity("range_handgun")
	if not TestHarness.check(ok, "course started"):
		return
	var rc = sys.range_ctl
	rc.debug_lower_all("turner", true)
	rc.debug_raise_all("popup")
	Input.action_press("aim")
	await TestHarness.wait_seconds(0.9)
	await TestHarness.shot("act_range_popups")
	rc.debug_lower_all("popup")
	rc.debug_raise_all("turner")
	await TestHarness.wait_seconds(1.3)
	await TestHarness.shot("act_range_turners")
	Input.action_release("aim")
	TestHarness.check(sys.get_active_id() == "range_handgun", "course still running during the shots")
	sys.abort_activity("shots")


func _stunt() -> void:
	var r: Dictionary = sys.stunts.get_ramp("stunt_foundry")
	var xf: Transform3D = r["xf"]
	var start := xf * Vector3(0.0, 0.0, float(r["entry_z"]) + 24.0)
	start.y = Game.ground_height(start.x, start.z) + 0.05
	var car = Game.spawn_vehicle("sports", Transform3D(xf.basis, start), {"owner_tag": "player", "engine_on": true, "color": Color(0.93, 0.35, 0.25)})
	if not TestHarness.check(car != null, "car spawned"):
		return
	await _frames(5)
	player.enter_vehicle(car, 0, true)
	await _frames(30)
	(car as RigidBody3D).linear_velocity = -xf.basis.z * 16.5
	Input.action_press("move_forward")
	var f := 0
	while f < 400 and not (int(sys.stunts.state) == 2 and float(sys.stunts.air_t) > 0.32):
		await _frames(1)
		f += 1
	TestHarness.check(int(sys.stunts.state) == 2, "car in the air off the ramp")
	await TestHarness.shot("act_stunt_air")
	Input.action_release("move_forward")


func _race_start_only(id: String, shot_name: String) -> void:
	var p: Dictionary = sys.get_point(id)
	player.teleport((p["xform"] as Transform3D).origin + Vector3.UP * 0.05, 0.0)
	await _frames(5)
	var ok: bool = await sys.start_activity(id)
	if not TestHarness.check(ok, "%s started" % id):
		return
	await TestHarness.wait_seconds(1.6)
	await TestHarness.shot(shot_name)
	sys.abort_activity("shots")


func _race() -> void:

	var p: Dictionary = sys.get_point("race_coral_loop")
	player.teleport((p["xform"] as Transform3D).origin + Vector3.UP * 0.05, 0.0)
	await _frames(5)
	var ok: bool = await sys.start_activity("race_coral_loop")
	if not TestHarness.check(ok, "race started"):
		return
	await TestHarness.wait_seconds(1.25)
	await TestHarness.shot("act_race_start")
	var rc = sys.race_ctl
	var w := 0
	while int(rc.phase) != 3 and w < 300:
		await _frames(1)
		w += 1
	# roll towards checkpoint 2 to show the next column ahead
	var cp: Dictionary = rc.get_checkpoint(1)
	var car = Game.get_player_vehicle()
	if car != null and not cp.is_empty():
		rc.cp_index = 1
		rc.call("_update_rings")
		var dir: Vector3 = cp["dir"]
		var pos: Vector3 = (cp["pos"] as Vector3) - dir * 38.0
		pos.y = Game.ground_height(pos.x, pos.z) + 0.1
		car.teleport(Transform3D(Basis.looking_at(dir, Vector3.UP), pos))
		var cam: Node = Game.camera_rig
		if cam != null and cam.has_method("snap_to"):
			cam.call("snap_to", atan2(-dir.x, -dir.z))
		await _frames(2)
		(car as RigidBody3D).linear_velocity = dir * 9.0
		await TestHarness.wait_seconds(1.2)
		await TestHarness.shot("act_race_checkpoint")
	sys.abort_activity("shots")
