extends Node
## plr4_review - review test of the PLAYER module (Wave 2 review): the paths the implementers did not
## run, the fixes of the review, and the REAL neighbours.
##
##   respawn   death during the arrest hold -> still respawned at the hospital (watchdog); the death
##             hold waits while the game is paused; respawn system disabled -> the dead state's own
##             fallback; arrest() without the respawn flow -> released by the busted fallback; after
##             every flow the player has control and walks (camera "third", input not locked)
##   save      load_save_data with garbage values (null / strings / arrays) -> no script error, the
##             position is kept, numbers are clamped; digit strings are accepted
##   pending   tap / hold decision on a driven car, then a teleport far away -> no warp into the car
##   driveby   the drive-by camera looks out from inside the sedan's cabin (crosshair on the target), the
##             rendered camera is exactly on the aim origin (also while driving), the motorcycle keeps
##             the orbit camera
##   dbcam     (windowed, review tooling) drive-by camera framing study: qa/screenshots/plr4_dbcam_*.png
##   dbcars    (windowed, review tooling, '--specs=a,b') the in-cabin drive-by view in other car bodies
##   traffic   REAL traffic + peds: carjack of a waiting traffic car (jack phase, the driver comes out
##             as a real NPC and goes down, the player drives); screenshots in a windowed run
##   police    REAL police + respawn: 1 star, an officer arrests the idle player (Wanted.bust) ->
##             hands up -> released at the police station with control
##
## Commands (see docs/PLAYER.md section 10):
##   tools\godot.ps1 -Mode headless -Frames 7000 -TimeoutSec 300 -UserArgs '--test=plr4_review','--only=respawn,save,pending,driveby','--disable=traffic,peds,police','--test-timeout=280'
##   tools\godot.ps1 -Mode headless -Frames 3000 -TimeoutSec 300 -UserArgs '--test=plr4_review','--only=traffic','--disable=police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,debug,pickups,interactions','--test-timeout=240'
##   tools\godot.ps1 -Mode window   -Frames 600  -TimeoutSec 150 -UserArgs '--test=plr4_review','--only=traffic','--disable=police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,debug,pickups,interactions','--test-timeout=140'
##   tools\godot.ps1 -Mode headless -Frames 7200 -TimeoutSec 400 -UserArgs '--test=plr4_review','--only=police','--seed=21','--disable=traffic,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,debug','--test-timeout=380'

const Arena := preload("res://gta/tests/plr_arena.gd")


## Stand-in AI driver (test equipment) for the pending-entry scene.
class DummyNpc extends CharacterBody3D:
	var is_dead: bool = false
	var faction: String = "civilian"
	var current_vehicle: Node3D = null

	func _init() -> void:
		add_to_group("npc")
		collision_layer = 0
		collision_mask = 0

	func knock_down(_impulse: Vector3) -> void:
		pass


var P: Player = null
var R: Node = null
var T: Node = null
var arena: Arena = null
var parts: PackedStringArray = ["respawn", "save", "pending", "driveby", "traffic", "police"]
var busted_count: int = 0
var died_count: int = 0
var cam: Camera3D = null


func _ready() -> void:
	T = TestHarness
	process_mode = Node.PROCESS_MODE_ALWAYS          # the pause scene drives the tree from here
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			parts = a.substr(7).split(",")
	await _run()


func _run() -> void:
	P = Game.player as Player
	R = Game.get_system("respawn")
	if not T.check(P != null, "Game.player is a Player"):
		T.finish(false, "no player")
		return
	EventBus.player_busted.connect(func() -> void: busted_count += 1)
	EventBus.player_died.connect(func(_c: String) -> void: died_count += 1)
	await T.wait_physics_frames(5)
	if parts.has("respawn") or parts.has("save") or parts.has("pending") or parts.has("dbcam") or parts.has("driveby") or parts.has("dbcars"):
		arena = Arena.new()
		Game.main.add_child(arena)
		await T.wait_physics_frames(5)
	if parts.has("respawn"):
		await _test_respawn()
	if parts.has("save"):
		await _test_save()
	if parts.has("pending"):
		await _test_pending()
	if parts.has("traffic"):
		await _test_traffic()
	if parts.has("police"):
		await _test_police()
	if parts.has("driveby"):
		await _test_driveby_camera()
	if parts.has("dbcam"):
		await _study_driveby_camera()
	if parts.has("dbcars"):
		await _study_cabins()
	_release_all()
	T.finish(true, "review: " + ",".join(parts))


# =================================================================================================
# helpers
# =================================================================================================

func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "enter_vehicle", "aim", "fire", "sprint"]:
		Input.action_release(a)


## Waits (physics frames, game time) until cond() or `timeout` game seconds.
func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	while t < timeout:
		if bool(cond.call()):
			return true
		await get_tree().physics_frame
		t += step * Engine.time_scale
	return bool(cond.call())


func _settle_ui() -> void:
	await _until(func() -> bool: return float(UI.call("get_fade_alpha")) < 0.05 if UI.has_method("get_fade_alpha") else true, 4.0)


## After a flow: control, input, camera, and a real walk with the move key.
func _check_control(tag: String) -> void:
	await _settle_ui()
	await T.wait_physics_frames(10)
	T.check(P.state_id == "on_foot" and P.has_control() and not Game.is_input_locked(),
			"%s: the player is on foot with control (state %s, control %s, locked %s)" % [tag, P.state_id, str(P.has_control()), str(Game.is_input_locked())])
	T.check(P.camera != null and P.camera.mode == "third", "%s: gameplay camera back in 'third' (%s)" % [tag, P.camera.mode if P.camera != null else "?"])
	var p0 := P.global_position
	Input.action_press("move_forward")
	await T.wait_seconds(1.0)
	Input.action_release("move_forward")
	var moved := Vector2(P.global_position.x - p0.x, P.global_position.z - p0.z).length()
	T.check(moved > 1.2, "%s: walking forward works right away (%.2f m in 1 s)" % [tag, moved])


func _arena_spot(local: Vector3) -> Vector3:
	return arena.at(local) + Vector3(0.0, 0.03, 0.0)


# =================================================================================================
# respawn edge cases
# =================================================================================================

func _test_respawn() -> void:
	if not T.check(R != null, "respawn system registered"):
		return
	# --- 1) killed while the arrest flow holds (the flow used to swallow the death)
	P.teleport(_arena_spot(Vector3(0.0, 0.0, 50.0)), 0.0)
	await T.wait_physics_frames(10)
	Wanted.set_level(1)
	Wanted.bust()
	await T.wait_physics_frames(3)
	T.check(P.state_id == "busted" and str(R.get("flow")) == "busted", "arrest flow running (state %s, flow %s)" % [P.state_id, str(R.get("flow"))])
	await T.wait_seconds(1.0)
	P.apply_damage(Dmg.make(500.0, "bullet", null, P.global_position + Vector3(0.0, 1.2, -3.0), Vector3(0.0, 0.0, 1.0)))
	await T.wait_physics_frames(3)
	T.check(P.is_dead and P.state_id == "dead", "killed with the hands up (state %s)" % P.state_id)
	var back := await _until(func() -> bool: return not P.is_dead and not bool(R.get("busy")), 16.0)
	T.check(back, "death during the arrest: the death flow still runs and the player respawns (dead %s, flow '%s')" % [str(P.is_dead), str(R.get("flow"))])
	var want: Transform3D = R.call("respawn_transform", "hospital")
	T.check(P.global_position.distance_to(want.origin) < 1.5, "... at the hospital (%.2f m)" % P.global_position.distance_to(want.origin))
	await _check_control("death during arrest")

	# --- 2) the death hold waits while the game is paused
	P.teleport(_arena_spot(Vector3(4.0, 0.0, 50.0)), 0.0)
	await T.wait_physics_frames(10)
	P.kill("fall")
	await T.wait_seconds(0.3)
	get_tree().paused = true
	for i in 420:                                    # 7 s of frames with the tree paused
		await get_tree().process_frame
	var still := P.is_dead
	get_tree().paused = false
	T.check(still, "death hold: no respawn behind the pause (7 s paused, still dead %s)" % str(still))
	back = await _until(func() -> bool: return not P.is_dead and not bool(R.get("busy")), 12.0)
	T.check(back, "death hold: the respawn follows after the pause")
	await _check_control("death after pause")

	# --- 3) respawn system disabled (admin): the dead state's own fallback brings the player back
	P.teleport(_arena_spot(Vector3(8.0, 0.0, 50.0)), 0.0)
	await T.wait_physics_frames(10)
	R.call("set_enabled", false)
	P.kill("generic")
	back = await _until(func() -> bool: return not P.is_dead, 9.0)
	var fb := Game.get_location("hospital").origin
	T.check(back and P.global_position.distance_to(fb) < 3.0, "respawn system disabled: fallback respawn at the hospital location (%s, %.2f m)" % [str(back), P.global_position.distance_to(fb)])
	R.call("set_enabled", true)
	await _check_control("fallback respawn")

	# --- 4) arrest() that the respawn flow does not handle: released by the busted fallback
	P.teleport(_arena_spot(Vector3(12.0, 0.0, 50.0)), 0.0)
	await T.wait_physics_frames(10)
	P.arrest()
	await T.wait_physics_frames(3)
	T.check(P.state_id == "busted", "direct arrest(): hands up")
	back = await _until(func() -> bool: return P.state_id == "on_foot", 8.0)
	var ps := Game.get_location("police_station").origin
	T.check(back and P.global_position.distance_to(ps) < 3.0, "direct arrest(): released at the police station by the fallback (%.2f m)" % P.global_position.distance_to(ps))
	await _check_control("arrest fallback")
	Wanted.clear("cheat")


# =================================================================================================
# save data JSON safety
# =================================================================================================

func _test_save() -> void:
	P.teleport(_arena_spot(Vector3(-6.0, 0.0, 50.0)), 0.0)
	await T.wait_physics_frames(10)
	var before := P.global_position
	P.has_scuba = false
	P.load_save_data({"position": [null, "x", 3], "yaw": "abc", "health": null, "armor": [1, 2],
			"has_parachute": "yes", "has_scuba": true, "appearance": "none"})
	await T.wait_physics_frames(3)
	T.check(P.has_scuba, "garbage save: the whole dictionary was read (no script error half-way)")
	T.check(P.global_position.distance_to(before) < 0.6 and P.global_position.is_finite(), "garbage save: unusable position ignored (%.2f m)" % P.global_position.distance_to(before))
	T.check(is_finite(P.health) and P.health >= 1.0 and P.health <= P.max_health and P.armor == 0.0, "garbage save: health / armor stay valid (%.0f / %.0f)" % [P.health, P.armor])
	T.check(not P.has_parachute, "garbage save: 'yes' is not a bool -> no parachute")
	var target := before + Vector3(3.0, 0.1, 0.0)
	P.load_save_data({"position": [str(target.x), str(target.y), str(target.z)], "yaw": 1.0, "health": "55"})
	await T.wait_physics_frames(3)
	T.check(P.global_position.distance_to(target) < 0.6 and is_equal_approx(P.health, 55.0), "save with digit strings: position and health applied (%.2f m, %.0f hp)" % [P.global_position.distance_to(target), P.health])
	P.has_scuba = false
	P.heal(100.0)


# =================================================================================================
# pending tap / hold decision + teleport
# =================================================================================================

func _test_pending() -> void:
	var xf := Transform3D(Basis.IDENTITY, arena.at(Vector3(-30.0, 0.0, 60.0)) + Vector3(0.0, 0.6, 0.0))
	var v := Game.spawn_vehicle("sedan", xf, {"owner_tag": "civilian"})
	if v == null:
		T.log_line("SKIP pending: no sedan")
		return
	await T.wait_physics_frames(45)
	var npc := DummyNpc.new()
	Game.get_entities_root().add_child(npc)
	v.call("occupant_enter", npc, 0)
	npc.current_vehicle = v
	var door: Vector3 = v.call("get_door_position", 0)
	var away := door - v.global_position
	away.y = 0.0
	var spot := door + away.normalized() * 0.9
	spot.y = arena.at(Vector3.ZERO).y + 0.03
	var to := v.global_position - spot
	P.teleport(spot, atan2(-to.x, -to.z))
	await T.wait_physics_frames(15)
	Input.action_press("enter_vehicle")
	await T.wait_physics_frames(6)
	var deciding: bool = P.vehicle_ix.is_deciding()
	T.check(deciding, "pending: a driven car with a free seat waits for tap / hold")
	P.teleport(_arena_spot(Vector3(40.0, 0.0, 60.0)), 0.0)
	await T.wait_physics_frames(30)
	Input.action_release("enter_vehicle")
	await T.wait_physics_frames(60)
	T.check(P.state_id == "on_foot" and P.current_vehicle == null and v.get("driver") == npc,
			"pending + teleport: no warp into the far car (state %s, driver kept %s)" % [P.state_id, str(v.get("driver") == npc)])
	if is_instance_valid(v):
		v.queue_free()
	npc.queue_free()
	await T.wait_physics_frames(5)


# =================================================================================================
# REAL traffic carjack
# =================================================================================================

func _test_traffic() -> void:
	var sys: Node = Game.get_system("traffic")
	if sys == null or sys.get("lanes") == null:
		T.log_line("SKIP traffic: no traffic system")
		return
	var L: Object = sys.get("lanes")
	if WorldClock.has_method("set_hour"):
		WorldClock.set_hour(15.5)
	if "paused" in WorldClock:
		WorldClock.paused = true
	var lane := -1
	var best := 0.0
	var count := int(L.get("count"))
	var kinds: Variant = L.get("kind")
	var lengths: Variant = L.get("length")
	var idx: Variant = L.get("index")
	var per_dir: Variant = L.get("lanes_per_dir")
	for i in count:
		if int(kinds[i]) == 0 and float(lengths[i]) > best and int(idx[i]) == int(per_dir[i]) - 1 and int(per_dir[i]) >= 2:
			best = float(lengths[i])
			lane = i
	if not T.check(lane >= 0, "traffic: an arterial test lane (%d, %.0f m)" % [lane, best]):
		return
	var mid: Vector3 = L.call("lane_point", lane, best * 0.5)
	sys.call("set_focus_override", mid)
	P.teleport(mid + Vector3.UP * 0.2, 0.0)
	await T.wait_physics_frames(10)
	sys.call("set_density", 0.0)
	sys.call("set_enabled", false)
	sys.call("set_enabled", true)
	var parking: Variant = sys.get("parking")
	if parking is Object and (parking as Object).has_method("clear_all"):
		(parking as Object).call("clear_all")
	await T.wait_physics_frames(5)
	var v: Node3D = null
	for k in 4:
		v = sys.call("spawn_traffic_vehicle", lane, 70.0 + 7.0 * float(k), "sedan")
		if v != null:
			break
	if not T.check(v != null, "traffic: a sedan with an AI driver spawned"):
		return
	var d: Object = sys.call("get_driver", v)
	if d != null:
		d.set("brake_t", 30.0)
	await T.wait_seconds(2.0)
	var dummy: Variant = v.get("driver")
	T.check(dummy != null and is_instance_valid(dummy) and v.has_meta("ai_controller"), "traffic: seated AI driver + ai_controller meta")
	# stand at the driver door, facing the car
	var door: Vector3 = v.call("get_door_position", 0)
	var away := door - v.global_position
	away.y = 0.0
	var spot := door + away.normalized() * 0.9
	spot.y = v.global_position.y + 0.1
	var to := v.global_position - spot
	P.teleport(spot, atan2(-to.x, -to.z))
	if P.camera != null:
		P.camera.snap_to(atan2(-to.x, -to.z) + 0.55)
		P.camera.pitch = -0.18
	await T.wait_physics_frames(20)
	var npcs_before := _npcs_with_reason("carjacked").size()
	await T.wait_physics_frames(12)
	var prompt := str(P.interaction.call("get_prompt_text"))
	T.check(prompt.begins_with("Steal"), "traffic: the prompt offers to steal the car ('%s')" % prompt)
	Input.action_press("enter_vehicle")
	await T.wait_physics_frames(2)
	Input.action_release("enter_vehicle")
	var vs := P.states["vehicle"] as PlayerStateVehicle
	var jacked := await _until(func() -> bool: return P.state_id == "vehicle" and vs.phase == PlayerStateVehicle.JACK, 3.0)
	T.check(jacked and vs.jacking, "traffic carjack: walk to the door, then the JACK phase (phase %d)" % vs.phase)
	# reach in (before the pull)
	await _until(func() -> bool: return vs.phase == PlayerStateVehicle.JACK and vs.get("_t") >= 0.30, 2.0)
	await _shot("plr4_carjack_reach", v, 0)
	var pulled := await _until(func() -> bool: return bool(vs.get("_pulled")), 2.0)
	T.check(pulled, "traffic carjack: the driver is pulled out")
	await T.wait_physics_frames(12)
	var victims := _npcs_with_reason("carjacked")
	var victim: Node3D = victims[0] if victims.size() > npcs_before else null
	if Game.get_system("peds") != null:
		T.check(victim != null, "traffic carjack: the driver came out as a real NPC (%d)" % victims.size())
	if victim != null:
		await _shot("plr4_carjack_pull", v, 1)
		var down := await _until(func() -> bool: return is_instance_valid(victim) and victim.get("is_down") == true, 1.5)
		T.check(down, "traffic carjack: the pulled-out driver is knocked to the ground (is_down)")
	var drove := await _until(func() -> bool: return P.current_vehicle == v and v.get("driver") == P, 4.0)
	T.check(drove and not v.has_meta("ai_controller") and sys.call("get_driver", v) == null,
			"traffic carjack: the player drives, traffic let go (no ai_controller, no driver record)")
	T.check(str(v.get("owner_tag")) == "player", "traffic carjack: owner_tag 'player' (%s)" % str(v.get("owner_tag")))
	await T.wait_seconds(1.2)
	if victim != null and is_instance_valid(victim):
		T.log_line("victim after 1.2 s: state_tag %s is_down %s pos %s" % [str(victim.get("state_tag")), str(victim.get("is_down")), str(victim.global_position)])
	await _shot("plr4_carjack_seated", v, 2)
	# drive off a little, then leave
	Input.action_press("move_forward")
	await T.wait_seconds(1.5)
	Input.action_release("move_forward")
	await T.wait_seconds(1.0)
	P.exit_vehicle()
	var out := await _until(func() -> bool: return P.state_id == "on_foot", 4.0)
	T.check(out, "traffic carjack: the player gets out again (%s)" % P.state_id)
	sys.call("clear_focus_override")
	if "paused" in WorldClock:
		WorldClock.paused = false


func _npcs_with_reason(reason: String) -> Array:
	var out: Array = []
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if n is Node3D and n.has_meta("left_vehicle_reason") and str(n.get_meta("left_vehicle_reason")) == reason:
			out.append(n)
	return out


## Windowed runs only: a side view of the car (kind 0 reach, 1 pull, 2 seated) through a test camera.
func _shot(shot_name: String, v: Node3D, kind: int) -> void:
	if T.is_headless():
		return
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 55.0
		Game.main.add_child(cam)
	var side := (P.global_position - v.global_position)
	side.y = 0.0
	side = side.normalized() if side.length_squared() > 0.01 else v.global_basis.x
	var fwd := -v.global_basis.z
	var focus := v.global_position + Vector3(0.0, 1.0, 0.0) + side * 0.6
	var eye := focus + side * 4.6 + fwd * (2.6 if kind != 2 else 3.4) + Vector3(0.0, 0.9, 0.0)
	var ts := Engine.time_scale
	Engine.time_scale = 0.0
	cam.global_position = eye
	cam.look_at(focus, Vector3.UP)
	cam.make_current()
	await T.wait_frames(3)
	await T.shot(shot_name)
	if P.camera != null and P.camera.camera != null:
		P.camera.camera.make_current()
	Engine.time_scale = ts


# =================================================================================================
# REAL police arrest -> respawn arrest flow
# =================================================================================================

func _test_police() -> void:
	var pol: Node = Game.get_system("police")
	if pol == null or R == null:
		T.log_line("SKIP police: police %s respawn %s" % [str(pol != null), str(R != null)])
		return
	Wanted.clear("cheat")
	if pol.has_method("reset_for_respawn"):
		pol.call("reset_for_respawn")
	var xf := Game.get_location("downtown_plaza")
	P.teleport(xf.origin, xf.basis.get_euler().y)
	var inv: Node = P.inventory
	if inv != null and inv.has_method("holster"):
		inv.call("holster")
	await T.wait_seconds(1.0)
	busted_count = 0
	Wanted.set_level(1)
	var hands_up := false
	var got := await _until(func() -> bool:
		if busted_count > 0 and P.state_id == "busted":
			hands_up = true
		return busted_count > 0, 75.0)
	T.check(got, "police: an officer arrested the idle player at 1 star (busts %d)" % busted_count)
	if not got:
		return
	await T.wait_physics_frames(2)
	T.check(hands_up or P.state_id == "busted", "police: hands up after Wanted.bust (state %s)" % P.state_id)
	var released := await _until(func() -> bool: return P.state_id == "on_foot" and not bool(R.get("busy")), 15.0)
	var ps: Transform3D = R.call("respawn_transform", "police_station")
	T.check(released and P.global_position.distance_to(ps.origin) < 1.5,
			"police: released at the police station (%.2f m, state %s)" % [P.global_position.distance_to(ps.origin), P.state_id])
	T.check(Wanted.level == 0, "police: wanted level cleared (%d)" % Wanted.level)
	await _check_control("real arrest")


# =================================================================================================
# drive-by camera framing study (windowed, review tooling): the rig's view + candidate placements
# =================================================================================================

func _study_driveby_camera() -> void:
	if T.is_headless():
		T.log_line("SKIP dbcam: windowed only")
		return
	var car := Game.spawn_vehicle("sedan", Transform3D(Basis.IDENTITY, arena.at(Vector3(0.0, 0.6, 52.0))), {"owner_tag": "parked"})
	if car == null:
		return
	await T.wait_physics_frames(20)
	# a target 10 m to the left, 3 m ahead
	var left := -car.global_basis.x
	var goal_feet := car.global_position + left * 10.0 - car.global_basis.z * 3.0
	goal_feet.y = arena.at(Vector3.ZERO).y
	var foe := Node3D.new()
	arena.add_child(foe)
	foe.global_transform = Transform3D(Basis(Vector3.UP, atan2(left.x, left.z)), goal_feet)
	var vis := (load("res://gta/scenes/characters/humanoid.tscn") as PackedScene).instantiate() as Node3D
	foe.add_child(vis)
	P.teleport(arena.at(Vector3(-3.0, 0.03, 52.0)), 0.0)
	await T.wait_physics_frames(4)
	P.enter_vehicle(car, 0, true)
	await T.wait_physics_frames(10)
	if P.inventory != null:
		P.inventory.call("equip", "pistol")
	await T.wait_physics_frames(16)
	Input.action_press("aim")
	await T.wait_frames(12)
	var goal := goal_feet + Vector3(0.0, 1.2, 0.0)
	for i in 6:
		await T.wait_frames(2)
		var o := P.camera.get_aim_origin()
		var d := P.camera.get_aim_direction()
		var want := (goal - o).normalized()
		P.camera.apply_look(angle_difference(atan2(-d.x, -d.z), atan2(-want.x, -want.z)), asin(want.y) - asin(d.y))
	await T.wait_frames(20)
	var hand := P.visual.global_transform * P.animator.get_hand_position(true)
	var w := P.drive_by_window
	T.log_line("dbcam: seat %s window %s hand %s cam %s pitch %.2f" % [str(P.global_position), str(w), str(hand), str(P.camera.get_aim_origin()), P.camera.pitch])
	await _snap_dbcam("plr4_dbcam_rig", Vector3.INF, Vector3.ZERO)
	# inside the cabin, over the shooter's far shoulder (camera candidates for a pure side aim)
	var eye_w := P.visual.global_transform * P.animator.get_eye_position()
	var view := (goal - eye_w)
	view.y = 0.0
	view = view.normalized()
	await _snap_dbcam("plr4_dbcam_in55", eye_w - view * 0.55 + Vector3(0.0, 0.10, 0.0), goal)
	await _snap_dbcam("plr4_dbcam_in85", eye_w - view * 0.85 + Vector3(0.0, 0.04, 0.0) + car.global_basis.z * 0.25, goal)
	# the rig aiming forward-left (35 deg), the common chase case
	var goal2 := car.global_position - car.global_basis.z * 16.0 + left * 11.0 + Vector3(0.0, 1.0, 0.0)
	foe.global_position = Vector3(goal2.x, goal_feet.y, goal2.z)
	for i in 6:
		await T.wait_frames(2)
		var o2 := P.camera.get_aim_origin()
		var d2 := P.camera.get_aim_direction()
		var want2 := (goal2 - o2).normalized()
		P.camera.apply_look(angle_difference(atan2(-d2.x, -d2.z), atan2(-want2.x, -want2.z)), asin(want2.y) - asin(d2.y))
	await T.wait_frames(20)
	await _snap_dbcam("plr4_dbcam_rig35", Vector3.INF, Vector3.ZERO)
	Input.action_release("aim")
	P.exit_vehicle()
	await _until(func() -> bool: return P.state_id == "on_foot", 2.0)
	foe.queue_free()
	car.queue_free()


func _snap_dbcam(shot_name: String, eye: Vector3, at: Vector3) -> void:
	if cam == null:
		cam = Camera3D.new()
		Game.main.add_child(cam)
	Engine.time_scale = 0.0
	if eye.is_finite():
		cam.fov = P.camera.camera.fov
		cam.global_position = eye
		cam.look_at(at, Vector3.UP)
		cam.make_current()
	await T.wait_frames(3)
	await T.shot(shot_name)
	if P.camera != null and P.camera.camera != null:
		P.camera.camera.make_current()
	Engine.time_scale = 1.0


# =================================================================================================
# drive-by camera inside the cabin (cars) / above the rider (bikes)
# =================================================================================================

func _test_driveby_camera() -> void:
	for spec: String in ["sedan", "motorcycle"]:
		var xf := Transform3D(Basis.IDENTITY, arena.at(Vector3(-45.0, 0.0, 30.0)) + Vector3(0.0, 0.6, 0.0))
		var v := Game.spawn_vehicle(spec, xf, {"owner_tag": "parked"})
		if v == null:
			T.log_line("SKIP driveby %s: not spawned" % spec)
			continue
		await T.wait_physics_frames(30)
		P.teleport(arena.at(Vector3(-48.0, 0.03, 30.0)), 0.0)
		await T.wait_physics_frames(4)
		P.enter_vehicle(v, 0, true)
		await T.wait_physics_frames(10)
		if P.inventory != null:
			P.inventory.call("give_weapon", "pistol")
			P.inventory.call("equip", "pistol")
		await T.wait_physics_frames(16)
		Input.action_press("aim")
		await T.wait_physics_frames(30)
		var left := -v.global_basis.x
		var goal := v.global_position + left * 10.0 - v.global_basis.z * 3.0 + Vector3(0.0, 1.0, 0.0)
		for i in 6:
			await T.wait_frames(2)
			var o := P.camera.get_aim_origin()
			var d := P.camera.get_aim_direction()
			var want := (goal - o).normalized()
			P.camera.apply_look(angle_difference(atan2(-d.x, -d.z), atan2(-want.x, -want.z)), asin(want.y) - asin(d.y))
		await T.wait_frames(30)
		var cam_pos := P.camera.get_aim_origin()
		var local := v.global_transform.affine_inverse() * cam_pos
		var eye_w := P.visual.global_transform * P.animator.get_eye_position()
		T.log_line("driveby %s: seat local %s eye local %s cam local %s yaw %.2f pitch %.2f anim %s" % [spec,
				str(v.global_transform.affine_inverse() * P.global_position), str(v.global_transform.affine_inverse() * eye_w),
				str(local), P.camera.yaw, P.camera.pitch, P.animator.state])
		var off := P.camera.get_aim_origin().distance_to(P.camera.camera.global_position)
		T.check(off < 0.02, "drive-by (%s): the rendered camera sits on the aim ray origin (%.3f m)" % [spec, off])
		if spec == "sedan":
			T.check(P.camera.is_drive_by_aiming() and P.camera.is_drive_by_cabin(), "drive-by (sedan): the camera looks out from inside the cabin")
			T.check(absf(local.x) < 0.75 and local.y < 1.45 and absf(local.z) < 1.6, "drive-by (sedan): camera point inside the body (local %s)" % str(local))
			var to_goal := (goal - cam_pos).normalized()
			T.check(P.camera.get_aim_direction().dot(to_goal) > 0.995, "drive-by (sedan): the crosshair stays on the target")
		else:
			T.check(P.camera.is_drive_by_aiming() and not P.camera.is_drive_by_cabin(), "drive-by (motorcycle): open vehicle keeps the orbit camera")
		Input.action_release("aim")
		await T.wait_physics_frames(20)
		T.check(not P.camera.is_drive_by_cabin(), "drive-by (%s): releasing aim leaves the cabin view" % spec)
		if spec == "sedan":
			# driving: the rendered chase camera must not lead / lag the aim origin by a frame of motion
			Input.action_press("move_forward")
			await T.wait_seconds(2.0)
			var spd := (v as RigidBody3D).linear_velocity.length() if v is RigidBody3D else 0.0
			var off2 := P.camera.get_aim_origin().distance_to(P.camera.camera.global_position)
			Input.action_release("move_forward")
			T.check(spd > 4.0 and off2 < 0.02, "driving at %.1f m/s: rendered camera on the aim origin (%.3f m)" % [spd, off2])
			Input.action_press("move_back")
			await T.wait_seconds(1.5)
			Input.action_release("move_back")
		P.exit_vehicle()
		await _until(func() -> bool: return P.state_id == "on_foot", 3.0)
		v.queue_free()
		await T.wait_physics_frames(5)


## Windowed (`--only=dbcars`): the in-cabin drive-by camera in other enclosed vehicles
## (qa/screenshots/plr4_dbcam_<spec>.png) - do their interiors hold up from inside?
func _study_cabins() -> void:
	if T.is_headless():
		T.log_line("SKIP dbcars: windowed only")
		return
	var specs: PackedStringArray = ["taxi", "compact", "suv", "muscle", "pickup"]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--specs="):
			specs = a.substr(8).split(",")
	for spec: String in specs:
		var car := Game.spawn_vehicle(spec, Transform3D(Basis.IDENTITY, arena.at(Vector3(0.0, 0.6, 52.0))), {"owner_tag": "parked"})
		if car == null:
			T.log_line("dbcars: %s not spawned" % spec)
			continue
		await T.wait_physics_frames(25)
		var left := -car.global_basis.x
		var goal_feet := car.global_position + left * 10.0 - car.global_basis.z * 3.0
		goal_feet.y = arena.at(Vector3.ZERO).y
		var foe := (load("res://gta/scenes/characters/humanoid.tscn") as PackedScene).instantiate() as Node3D
		arena.add_child(foe)
		foe.global_transform = Transform3D(Basis(Vector3.UP, atan2(left.x, left.z)), goal_feet)
		P.teleport(arena.at(Vector3(-4.0, 0.03, 52.0)), 0.0)
		await T.wait_physics_frames(4)
		P.enter_vehicle(car, 0, true)
		await T.wait_physics_frames(10)
		if P.inventory != null:
			P.inventory.call("give_weapon", "pistol")
			P.inventory.call("equip", "pistol")
		await T.wait_physics_frames(16)
		Input.action_press("aim")
		await T.wait_frames(12)
		var goal := goal_feet + Vector3(0.0, 1.2, 0.0)
		for i in 6:
			await T.wait_frames(2)
			var o := P.camera.get_aim_origin()
			var d := P.camera.get_aim_direction()
			var want := (goal - o).normalized()
			P.camera.apply_look(angle_difference(atan2(-d.x, -d.z), atan2(-want.x, -want.z)), asin(want.y) - asin(d.y))
		await T.wait_frames(20)
		T.log_line("dbcars %s: cabin %s" % [spec, str(P.camera.is_drive_by_cabin())])
		await _snap_dbcam("plr4_dbcam_" + spec, Vector3.INF, Vector3.ZERO)
		Input.action_release("aim")
		P.exit_vehicle()
		await _until(func() -> bool: return P.state_id == "on_foot", 2.0)
		foe.queue_free()
		car.queue_free()
		await T.wait_physics_frames(5)
