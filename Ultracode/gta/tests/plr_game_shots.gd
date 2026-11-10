extends Node
## plr_game_shots - windowed screenshots of the REAL player through the REAL gameplay camera.
##
##   tools\godot.ps1 -Mode window -Frames 420 -UserArgs '--test=plr_game_shots','--disable=traffic,peds,police','--part=1'
##   (same with --part=2 and --part=3; every part stays under the 20 s windowed limit)
##
## part 1 (on foot): third person idle / run / sprint, crouch.
## part 2 (weapons): aim + fire pistol, first person, rifle carry + aim.
## part 3 (car): real car - walking to the door, chase camera, first person at the wheel, exit.
## part 4 (world): swimming, diving, death ragdoll.
## part 5 (city): the player at the real spawn point / beach of the island (needs the world system).
## PNGs: qa/screenshots/plr_game_<name>.png. Uses the test arena (gta/tests/plr_arena.gd).

const Arena := preload("res://gta/tests/plr_arena.gd")

var P: Player = null
var C: PlayerCamera = null
var arena: Arena = null
var T: Node = null
var notes: PackedStringArray = []


func _ready() -> void:
	T = TestHarness
	await _run()


func _run() -> void:
	P = Game.player as Player
	C = Game.camera_rig as PlayerCamera
	if not T.check(P != null and C != null, "player and camera rig exist"):
		T.finish(false, "no player")
		return
	arena = Arena.new()
	Game.main.add_child(arena)
	arena.ensure_light()
	var part := 1
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--part="):
			part = int(a.substr(7))
	P.teleport(arena.at(Vector3(0.0, 0.05, 2.0)), 0.0)
	await T.wait_seconds(1.6)            # let the boot overlay of the UI fade away
	if part == 1:
		await _part_on_foot()
	elif part == 2:
		await _part_weapons()
	elif part == 3:
		await _part_car()
	elif part == 4:
		await _part_water_and_ragdoll()
	else:
		await _part_real_world()
	_release()
	for n in notes:
		T.log_line(n)
	T.finish(true, "game shots part %d" % part)


func _release() -> void:
	for a in ["move_forward", "move_left", "move_right", "sprint", "aim", "fire", "crouch", "jump"]:
		Input.action_release(a)


func _tap(action: String) -> void:
	await get_tree().physics_frame
	Input.action_press(action)
	await T.wait_physics_frames(3)
	Input.action_release(action)
	await T.wait_physics_frames(2)


func _part_on_foot() -> void:
	# idle, camera swung to the front-left so the character is seen from the front
	C.yaw = 2.5
	C.pitch = -0.12
	await T.wait_seconds(0.5)
	await T.shot("plr_game_idle_front")
	# default view from behind
	C.snap_to(0.0)
	await T.wait_seconds(0.4)
	await T.shot("plr_game_idle_back")
	# run (camera to the side, body runs along -Z)
	P.teleport(arena.at(Vector3(0.0, 0.05, 30.0)), 0.0)
	await T.wait_seconds(0.2)
	Input.action_press("move_forward")
	await T.wait_seconds(0.9)
	await T.shot("plr_game_run_back")
	Input.action_press("sprint")
	await T.wait_seconds(0.8)
	await T.shot("plr_game_sprint_back")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await T.wait_seconds(0.4)
	# crouch
	P.teleport(arena.at(Vector3(0.0, 0.05, 2.0)), 0.0)
	await _tap("crouch")
	C.yaw = 0.9
	await T.wait_seconds(0.6)
	await T.shot("plr_game_crouch")
	await _tap("crouch")


func _part_weapons() -> void:
	C.snap_to(0.0)
	var inv := P.inventory
	if inv != null and inv.has_method("give_weapon") and Registry.has_def("weapons", "pistol"):
		inv.call("give_weapon", "pistol", 60)
		inv.call("equip", "pistol")
		await T.wait_seconds(0.7)
		Input.action_press("aim")
		C.pitch = 0.0
		await T.wait_seconds(0.6)
		await T.shot("plr_game_aim_pistol")
		Input.action_press("fire")
		await T.wait_seconds(0.12)
		await T.shot("plr_game_fire_pistol")
		Input.action_release("fire")
		# first person, still aiming
		await _tap("camera_toggle")
		await T.wait_seconds(0.4)
		await T.shot("plr_game_first_person_aim")
		Input.action_release("aim")
		await T.wait_seconds(0.3)
		await T.shot("plr_game_first_person")
		await _tap("camera_toggle")
		await T.wait_seconds(0.2)
		if Registry.has_def("weapons", "assault_rifle"):
			inv.call("give_weapon", "assault_rifle", 120)
			inv.call("equip", "assault_rifle")
			await T.wait_seconds(0.8)
			C.yaw = 0.7
			await T.wait_seconds(0.3)
			await T.shot("plr_game_rifle_carry")
			C.snap_to(0.0)
			Input.action_press("aim")
			C.pitch = 0.0
			await T.wait_seconds(0.6)
			await T.shot("plr_game_aim_rifle")
			Input.action_release("aim")
		else:
			notes.append("no assault_rifle spec: rifle shots skipped")
	else:
		notes.append("no weapon inventory / pistol spec: weapon shots skipped")


func _part_car() -> void:
	var v: Node3D = null
	if Game.get_system("vehicles") != null and Registry.has_def("vehicles", "sedan"):
		v = Game.spawn_vehicle("sedan", Transform3D(Basis.IDENTITY, arena.at(Vector3(4.0, 0.6, 2.0))), {"owner_tag": "parked"})
	if v != null:
		await T.wait_seconds(1.0)
		await _tap("enter_vehicle")
		await T.wait_seconds(0.75)
		await T.shot("plr_game_car_enter")           # mid transition
		await T.wait_seconds(1.2)
		C.apply_look(0.9, 0.05)
		await T.wait_seconds(0.5)
		await T.shot("plr_game_car_chase")
		C.apply_look(-0.9, -0.05)
		await _tap("camera_toggle")
		await T.wait_seconds(0.5)
		await T.shot("plr_game_car_first_person")
		await _tap("camera_toggle")
		await T.wait_seconds(0.2)
		await _tap("enter_vehicle")
		await T.wait_seconds(0.3)
		await T.shot("plr_game_car_exit")            # mid transition
		await T.wait_seconds(0.6)
	else:
		notes.append("no sedan available: car shots skipped")


func _part_water_and_ragdoll() -> void:
	var spot: Vector3 = arena.ensure_water()
	if spot.is_finite():
		P.teleport(spot, 0.0)
		await T.wait_seconds(1.6)
		Input.action_press("move_forward")
		C.yaw = 0.8
		C.pitch = -0.25
		await T.wait_seconds(1.3)
		await T.shot("plr_game_swim")
		Input.action_press("crouch")
		await T.wait_seconds(1.6)
		await T.shot("plr_game_dive")
		Input.action_release("crouch")
		Input.action_release("move_forward")
	else:
		notes.append("no deep water: swim shots skipped")
	# death ragdoll
	P.teleport(arena.at(Vector3(0.0, 0.05, 2.0)), 0.0)
	await T.wait_seconds(0.4)
	C.yaw = 0.6
	P.apply_damage(Dmg.make(400.0, "bullet", null, P.get_target_position(), Vector3(0.3, 0.0, -1.0).normalized(), {"impulse": 260.0}))
	await T.wait_seconds(1.5)
	await T.shot("plr_game_dead_ragdoll")
	arena.remove_stub_world()


func _part_real_world() -> void:
	if Game.world == null or not Game.world.has_method("get_location"):
		notes.append("no world system: city shots skipped")
		return
	var spawn: Transform3D = Game.world.call("get_location", "spawn_start")
	var yaw := spawn.basis.get_euler().y
	P.teleport(spawn.origin + Vector3(0.0, 0.3, 0.0), yaw)
	await T.wait_seconds(1.0)
	await T.shot("plr_game_city_spawn")
	Input.action_press("move_forward")
	await T.wait_seconds(1.3)
	C.apply_look(0.7, 0.0)
	await T.wait_seconds(0.5)
	await T.shot("plr_game_city_run")
	Input.action_release("move_forward")
	var beach: Transform3D = Game.world.call("get_location", "beach")
	P.teleport(beach.origin + Vector3(0.0, 0.3, 0.0), beach.basis.get_euler().y)
	await T.wait_seconds(0.9)
	C.apply_look(2.4, 0.05)
	await T.wait_seconds(0.4)
	await T.shot("plr_game_beach_front")
