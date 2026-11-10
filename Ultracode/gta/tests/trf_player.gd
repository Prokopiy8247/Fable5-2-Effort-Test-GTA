extends Node
## TRAFFIC x the REAL player (headless, review test): the paths the implementer could only check with
## stand-ins, driven through the real Player (enter key via Input.action_press, PlayerStateVehicle,
## PlayerVehicleInteraction.pull_out -> TrafficSystem.release_vehicle) and the real peds system.
##
##   ride along   hold the enter key at a traffic car's passenger door -> the player sits in seat 1,
##                the AI keeps driving with the player aboard; clear_all() does NOT pull the car away
##                under the player (the driver gets out instead)
##   carjack      tap the enter key at the driver door of a waiting traffic car -> the driver is pulled
##                out as a real NPC ("carjacked"), the player drives, traffic lets go
##   moving car   tap the enter key while a traffic car rolls past at 5-9 m/s -> the driver brakes for
##                the entry (TrafficSystem._jack_watch) and the carjack succeeds (or, rarely, floors it)
##   aim          the real player aims a pistol at a waiting driver from 6 m -> surrender or flee
##   cut          teleport 250 m away -> the new place has traffic within a second, old cars despawn
##
## Run: tools\godot.ps1 -Mode headless -Frames 5400 -TimeoutSec 360 -UserArgs '--test=trf_player','--test-timeout=330',
##      '--disable=police,emergency,wildlife,shops,garage,transit,taxi,activities,radio,ambience,respawn,debug,pickups,interactions'

var sys: TrafficSystem = null
var L: TrafficLanes = null
var P: Node3D = null
var lane_a: int = -1


func _ready() -> void:
	await _run()


func _run() -> void:
	sys = Game.get_system("traffic") as TrafficSystem
	P = Game.player
	if not TestHarness.check(sys != null and sys.lanes != null and P != null, "traffic system + real player"):
		TestHarness.finish(false, "needs traffic and the player")
		return
	L = sys.lanes
	if WorldClock.has_method("set_hour"):
		WorldClock.set_hour(12.0)
	if "paused" in WorldClock:
		WorldClock.paused = true
	# the longest outer arterial lane: room for the scenes, no junction for a while
	var best := 0.0
	for i in L.count:
		if L.kind[i] == TrafficLanes.KIND_ARTERIAL and L.length[i] > best and L.index[i] == L.lanes_per_dir[i] - 1 and L.lanes_per_dir[i] >= 2:
			best = L.length[i]
			lane_a = i
	TestHarness.log_line("test lane %d length %.0f (lanes per dir %d)" % [lane_a, best, L.lanes_per_dir[lane_a]])
	# scenes 1-4 happen on lane_a, wherever the player stands when a scene starts: the focus stays
	# there so the scripted cars are never frozen / despawned (scene 5 uses the real player focus)
	sys.set_focus_override(L.lane_point(lane_a, best * 0.5))
	P.call("teleport", L.lane_point(lane_a, best * 0.5) + Vector3.UP * 0.2, 0.0)
	await TestHarness.wait_physics_frames(10)
	sys.set_density(0.0)
	sys.set_enabled(false)
	sys.set_enabled(true)
	# no parked cars in this test: the player is teleported to car doors at the kerb
	sys.parking.clear_all()
	sys.parking.bays.clear()
	await TestHarness.wait_physics_frames(5)
	await _test_ride_along()
	await _test_carjack_stopped()
	await _test_carjack_moving()
	await _test_aim()
	await _test_explosion()
	await _test_cut()
	TestHarness.log_line("stats: %s" % str(sys.get_debug_info()))
	_release_all()
	TestHarness.finish()


# --- helpers ---------------------------------------------------------------------------------------

func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "enter_vehicle", "aim", "fire"]:
		Input.action_release(a)


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if bool(cond.call()):
			return true
		await get_tree().physics_frame
		t += 1.0 / 60.0
	return bool(cond.call())


func _spawn(off: float, spec: String = "sedan") -> TrafficDriver:
	# spawn_traffic_vehicle refuses an occupied spot (the car the player took in an earlier scene stays
	# on the lane): try a bit further on
	for k in 4:
		var o := off + 7.0 * float(k)
		var v := sys.spawn_traffic_vehicle(lane_a, o, spec)
		if v == null:
			v = sys.spawn_traffic_vehicle(lane_a, o)
		if v != null:
			return sys.get_driver(v)
	return null


func _stand_at_door(v: Node3D, seat: int, out: float = 0.9) -> void:
	var door: Vector3 = v.call("get_door_position", seat)
	var away := door - v.global_position
	away.y = 0.0
	away = away.normalized()
	var spot := door + away * out
	spot.y = v.global_position.y + 0.1
	var to := v.global_position - spot
	P.call("teleport", spot, atan2(-to.x, -to.z))
	await TestHarness.wait_physics_frames(15)


func _leave_vehicle() -> void:
	if P.get("current_vehicle") != null or str(P.call("get_state_name")) == "vehicle":
		P.call("exit_vehicle")
		await _until(func() -> bool: return str(P.call("get_state_name")) != "vehicle", 3.0)
	_release_all()
	await TestHarness.wait_physics_frames(20)


func _clear() -> void:
	await _leave_vehicle()
	sys.clear_all()
	await TestHarness.wait_physics_frames(5)


func _npc_near(pos: Vector3, reason: String) -> Node3D:
	for n: Node in get_tree().get_nodes_in_group("npc"):
		var n3 := n as Node3D
		if n3 != null and n3.has_meta("left_vehicle_reason") and str(n3.get_meta("left_vehicle_reason")) == reason \
				and n3.global_position.distance_to(pos) < 12.0:
			return n3
	return null


# --- scenes ----------------------------------------------------------------------------------------

func _test_ride_along() -> void:
	var d := _spawn(60.0)
	if not TestHarness.check(d != null, "ride along: traffic car spawned"):
		return
	var v := d.body
	d.brake_t = 30.0                      # waits (like at a light) while the player gets in
	await TestHarness.wait_seconds(2.0)
	await _stand_at_door(v, 1)
	Input.action_press("enter_vehicle")
	await TestHarness.wait_seconds(0.6)     # hold = ride along as a passenger
	Input.action_release("enter_vehicle")
	var seated := await _until(func() -> bool: return P.get("current_vehicle") == v, 4.0)
	TestHarness.check(seated and int(v.call("get_seat_of", P)) == 1, "ride along: the player sits in the passenger seat (seat %d)" % int(v.call("get_seat_of", P)))
	TestHarness.check(sys.get_driver(v) == d and v.get("driver") == d.dummy, "ride along: the traffic driver stays in control")
	d.brake_t = 0.0
	var p0 := v.global_position
	await TestHarness.wait_seconds(7.0)
	var moved := v.global_position.distance_to(p0)
	TestHarness.check(is_instance_valid(v) and sys.get_driver(v) == d and moved > 15.0, "ride along: the AI drives on with the player aboard (%.0f m)" % moved)
	d.brake_t = 6.0
	await _until(func() -> bool: return absf(float(v.call("get_forward_speed"))) < 0.5, 5.0)
	sys.clear_all()
	await TestHarness.wait_physics_frames(5)
	TestHarness.check(is_instance_valid(v) and not v.is_queued_for_deletion() and P.get("current_vehicle") == v,
			"ride along: clear_all() keeps the car the player sits in")
	TestHarness.check(is_instance_valid(v) and v.get("driver") == null and not v.has_meta("ai_controller") and sys.get_driver(v) == null,
			"ride along: ... its driver got out instead (driver null, no ai_controller)")
	await _clear()


func _test_carjack_stopped() -> void:
	var d := _spawn(110.0)
	if not TestHarness.check(d != null, "carjack: traffic car spawned"):
		return
	var v := d.body
	d.brake_t = 30.0
	await TestHarness.wait_seconds(2.0)
	await _stand_at_door(v, 0)
	var npcs0 := int(sys.stats["npcs_spawned"])
	Input.action_press("enter_vehicle")
	await TestHarness.wait_physics_frames(2)
	Input.action_release("enter_vehicle")
	var drove := await _until(func() -> bool: return P.get("current_vehicle") == v and v.get("driver") == P, 5.0)
	TestHarness.check(drove, "carjack (real player): the player ends up driving the traffic car")
	TestHarness.check(sys.get_driver(v) == null and not v.has_meta("ai_controller"), "carjack: traffic let go (no driver record, no ai_controller)")
	if Game.get_system("peds") != null:
		var victim := _npc_near(v.global_position, "carjacked")
		TestHarness.check(int(sys.stats["npcs_spawned"]) > npcs0 and victim != null, "carjack: the driver is a real NPC beside the car (meta left_vehicle_reason 'carjacked')")
		if victim != null:
			await TestHarness.wait_seconds(1.0)
			var b: Variant = victim.get("brain")
			var mode := str(b.call("get_mode_name")) if b != null and is_instance_valid(b) and (b as Object).has_method("get_mode_name") else "?"
			TestHarness.log_line("carjacked %s: brain mode %s, state %s" % [str(victim.get("archetype_id")), mode, str(victim.get("state_tag"))])
	await _clear()


func _test_carjack_moving() -> void:
	var success := false
	var fled := 0
	var tap_speed := 0.0
	var stops0 := int(sys.stats["jack_stops"])
	for attempt in 3:
		var d := _spawn(15.0)
		if d == null:
			continue
		var v := d.body
		d.personality = 1
		d.speed_factor = 7.5 / L.limit[lane_a]   # ~7.5 m/s (27 km/h, a car rolling through town; the ring arterial allows 22 m/s)
		d.archetype = "civilian_m"
		# the player stands in the inner lane, 45 m ahead, 2.5 m left of the car's path
		var s_at := minf(15.0 + 45.0, L.length[lane_a] - 20.0)
		var lp := L.lane_point(lane_a, s_at)
		var ldir := L.lane_dir(lane_a, s_at)
		var left := Vector3(ldir.z, 0.0, -ldir.x)
		P.call("teleport", lp + left * 2.5 + Vector3.UP * 0.1, atan2(ldir.x, ldir.z))   # facing the car
		await TestHarness.wait_physics_frames(10)
		var tapped := await _until(func() -> bool:
			return is_instance_valid(v) and absf(float(v.call("get_forward_speed"))) > 4.0 and P.call("find_enterable_vehicle") == v, 14.0)
		if not tapped:
			TestHarness.log_line("moving carjack attempt %d: the car never came in reach (speed %.1f)" % [attempt, absf(float(v.call("get_forward_speed")))])
			await _clear()
			continue
		tap_speed = absf(float(v.call("get_forward_speed")))
		TestHarness.log_line("tap: target %.1f limit %.1f factor %.2f panic %.1f frozen %s" % [d.target_speed, L.limit[d.lane], d.speed_factor, d.panic_t, str(d.frozen)])
		Input.action_press("enter_vehicle")
		await TestHarness.wait_physics_frames(2)
		Input.action_release("enter_vehicle")
		var got := await _until(func() -> bool: return P.get("current_vehicle") == v and v.get("driver") == P, 5.0)
		TestHarness.log_line("moving carjack attempt %d: tap at %.1f m/s -> %s (jack_stops %d escapes %d)" % [attempt, tap_speed,
				"jacked" if got else "failed", int(sys.stats["jack_stops"]), int(sys.stats["jack_escapes"])])
		if got:
			success = true
			await _clear()
			break
		fled += 1
		await _clear()
	TestHarness.check(int(sys.stats["jack_stops"]) > stops0, "moving car: the driver brakes for the player getting in (jack_stops %d)" % (int(sys.stats["jack_stops"]) - stops0))
	TestHarness.check(success, "moving car: carjack of a car tapped at %.1f m/s succeeds (%d failed attempts)" % [tap_speed, fled])


func _test_aim() -> void:
	var inv: Variant = P.get("inventory")
	if inv == null or not (inv as Object).has_method("give_weapon"):
		TestHarness.log_line("aim: no player inventory - skipped")
		return
	inv.call("give_weapon", "pistol", 60)
	inv.call("equip", "pistol")
	var d := _spawn(140.0)
	if not TestHarness.check(d != null, "aim: traffic car spawned"):
		return
	var v := d.body
	d.brake_t = 30.0
	await TestHarness.wait_seconds(2.0)
	var head := d.dummy.global_position + Vector3.UP * 0.55
	var side := -v.global_transform.basis.x          # the driver's (left) side
	side.y = 0.0
	var spot := head + side.normalized() * 6.0
	spot.y = v.global_position.y + 0.1
	var to := head - spot
	P.call("teleport", spot, atan2(-to.x, -to.z))
	await TestHarness.wait_physics_frames(10)
	Input.action_press("aim")
	var rig: Variant = Game.camera_rig
	for i in 90:                                      # keep the crosshair on the driver's head for 1.5 s
		await get_tree().physics_frame
		if rig != null and is_instance_valid(rig) and P.has_method("get_aim_ray"):
			var ray: Dictionary = P.call("get_aim_ray")
			var w: Vector3 = head - (ray["origin"] as Vector3)
			rig.set("yaw", atan2(-w.x, -w.z))
			rig.set("pitch", atan2(w.y, Vector2(w.x, w.z).length()))
		if d.reacted_aim:
			break
	var aiming := bool(P.get("is_aiming"))
	Input.action_release("aim")
	TestHarness.log_line("aim: is_aiming %s armed %s reacted %s release '%s' panic %.1f" % [str(aiming), str(P.call("is_armed")),
			str(d.reacted_aim), d.release_reason, d.panic_t])
	TestHarness.check(d.reacted_aim and (d.release_reason == "surrender" or d.panic_t > 0.0),
			"aim (real player): a gun pointed at a waiting driver -> surrender or flee (release '%s', panic %.1f)" % [d.release_reason, d.panic_t])
	await TestHarness.wait_seconds(2.0)
	await _clear()


func _test_explosion() -> void:
	# the car blows up with its (visible) driver aboard: a real NPC takes the lethal blast
	var s0 := 40.0
	var lp := L.lane_point(lane_a, s0)
	var ldir := L.lane_dir(lane_a, s0)
	var right := Vector3(-ldir.z, 0.0, ldir.x)
	P.call("teleport", lp + right * 7.0 + Vector3.UP * 0.2, atan2(ldir.x, ldir.z))
	await TestHarness.wait_physics_frames(10)
	var d := _spawn(s0 + 24.0)
	if not TestHarness.check(d != null, "explosion: traffic car spawned"):
		return
	var v := d.body
	d.brake_t = 30.0
	await _until(func() -> bool: return d.visible_driver, 3.0)
	TestHarness.check(d.visible_driver, "explosion: the seated driver is drawn near the camera")
	var n0 := int(sys.stats["npcs_spawned"])
	v.call("explode", P)
	await TestHarness.wait_seconds(0.6)
	TestHarness.check(sys.get_driver(v) == null and (not is_instance_valid(v) or (v.get("driver") == null and not v.has_meta("ai_controller"))),
			"explosion: the wreck has no driver / ai_controller")
	var corpse: Node3D = null
	for n: Node in get_tree().get_nodes_in_group("npc"):
		if n is Node3D and n.has_meta("left_vehicle_reason") and str(n.get_meta("left_vehicle_reason")) == "killed":
			corpse = n
	if Game.get_system("peds") != null:
		TestHarness.check(int(sys.stats["npcs_spawned"]) > n0 and corpse != null and bool(corpse.get("is_dead")),
				"explosion: the driver's body is a real NPC killed by the blast (%s)" % (str(corpse.get("is_dead")) if corpse != null else "none"))
	await TestHarness.wait_seconds(1.0)


func _test_cut() -> void:
	sys.clear_focus_override()
	sys.set_density(1.0)
	var here := P.global_position
	await TestHarness.wait_seconds(3.0)               # some ambient traffic around the player
	# teleport ~250 m away onto a road
	var far := here + Vector3(-250.0, 0.0, 0.0) if here.x > 0.0 else here + Vector3(250.0, 0.0, 0.0)
	var nl: Dictionary = L.roads.get_nearest_lane(far, 120.0)
	if not TestHarness.check(not nl.is_empty(), "cut: a road 250 m away"):
		return
	var dest: Vector3 = nl["point"]
	P.call("teleport", dest + Vector3.UP * 0.2, 0.0)
	await TestHarness.wait_seconds(1.0)
	var near := 0
	for d: TrafficDriver in sys.get_drivers():
		if d.is_valid() and not d.frozen and Vector2(d.body.global_position.x - dest.x, d.body.global_position.z - dest.z).length() < 175.0:
			near += 1
	TestHarness.check(near >= 10, "teleport cut (real player): traffic around the new place after 1 s (%d cars)" % near)
	sys.reset_for_respawn()
	await TestHarness.wait_seconds(1.0)
	var far_left := 0
	for d: TrafficDriver in sys.get_drivers():
		if d.is_valid() and Vector2(d.body.global_position.x - dest.x, d.body.global_position.z - dest.z).length() > TrafficSystem.DESPAWN_DIST + 5.0 \
				and not sys.is_seen(d.body.global_position):
			far_left += 1
	TestHarness.check(far_left == 0, "teleport cut: cars left behind were despawned (%d left)" % far_left)
