extends Node
## Integration smoke test of the vehicle framework inside the REAL game boot (world, environment,
## player - whatever exists): cars spawned on the island's parking bays rest on the real ground,
## the real Player enters through its own enter_vehicle() path, drives with the input actions,
## brakes, leaves, and a carjack-style eject works. Soft on every neighbour: parts whose module
## is missing are logged and skipped, never faked.
##
## Run: tools\godot.ps1 -Mode headless -Frames 2400 -TimeoutSec 300 -UserArgs '--test=veh_ingame'
## Optional: --veh=sedan  (car used for the driving part)

var mgr: Node = null


func _ready() -> void:
	await _run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ground_xf(xf: Transform3D) -> Transform3D:
	var p := xf.origin
	var y := Game.ground_height(p.x, p.z)
	# a ray is more exact than the height field where roads / decks sit above the terrain
	var space := get_viewport().get_world_3d().direct_space_state if get_viewport() != null else null
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, y + 30.0, p.z), Vector3(p.x, y - 5.0, p.z), Layers.WORLD)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			y = (hit["position"] as Vector3).y
	var f := -xf.basis.z
	f.y = 0.0
	var yaw := atan2(-f.x, -f.z) if f.length() > 0.01 else 0.0
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y + 0.03, p.z))


func _run() -> void:
	mgr = Game.get_system("vehicles")
	if not TestHarness.check(mgr != null, "vehicles system is registered in the real boot"):
		TestHarness.finish(false, "no vehicles system")
		return
	var ids: Array[String] = []
	for id: Variant in Registry.ids("vehicles"):
		if mgr.can_spawn(str(id)):
			ids.append(str(id))
	if not TestHarness.check(not ids.is_empty(), "spawnable vehicle specs: %s" % str(ids)):
		TestHarness.finish(false, "no models")
		return
	var hero := "sedan" if ids.has("sedan") else ids[0]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--veh=") and ids.has(a.substr(6)):
			hero = a.substr(6)
	print("VEH_INGAME: systems = ", Game.systems.keys(), " player = ", Game.has_player(), " world = ", Game.world != null)
	await _frames(30)

	# ---------------------------------------------------------------- where to put the cars
	var origin := Game.get_location("spawn_start")
	var bays: Array[Transform3D] = []
	if Game.world != null and Game.world.has_method("get_spawn_points"):
		var pts: Variant = Game.world.call("get_spawn_points", "parking")
		if pts is Array:
			for p: Variant in pts:
				if p is Transform3D:
					bays.append(p)
	print("VEH_INGAME: parking bays from the world = ", bays.size())
	if bays.is_empty():
		TestHarness.log_line("world offers no 'parking' spawn points - using a row beside spawn_start")
		for i in ids.size() + 1:
			bays.append(origin * Transform3D(Basis.IDENTITY, Vector3(5.0 + float(i) * 4.5, 0.0, -4.0)))
	# nearest bays first
	var keyed: Array = []
	for b: Transform3D in bays:
		keyed.append([b.origin.distance_to(origin.origin), b])
	keyed.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))

	# ---------------------------------------------------------------- every car rests on the real ground
	var parked: Array = []
	var start_pos: Array[Vector3] = []
	for i in mini(ids.size(), keyed.size()):
		var xf := _ground_xf(keyed[i][1])
		var v: Variant = Game.spawn_vehicle(ids[i], xf, {})
		if TestHarness.check(v != null, "%s spawns at a parking bay (%.0f, %.1f, %.0f)" % [ids[i], xf.origin.x, xf.origin.y, xf.origin.z]):
			parked.append(v)
			start_pos.append(xf.origin)
	await _frames(240)
	for i in parked.size():
		var v: Variant = parked[i]
		if not is_instance_valid(v):
			TestHarness.check(false, "parked vehicle %d vanished" % i)
			continue
		var drift: float = (v.global_position - start_pos[i]).length()
		TestHarness.check(drift < 0.6 and v.global_transform.basis.y.y > 0.93,
				"%s settles on the island ground (moved %.2f m, up.y %.3f, asleep=%s, wheels on ground %d)" % [
				v.spec_id, drift, v.global_transform.basis.y.y, str(v.sleeping), int(v.get("grounded_wheels"))])

	# ---------------------------------------------------------------- the real player drives
	var car: Variant = null
	for v: Variant in parked:
		if is_instance_valid(v) and v.spec_id == hero:
			car = v
	if car == null and not parked.is_empty():
		car = parked[0]
	if car == null:
		TestHarness.finish(false, "nothing to drive")
		return
	var player := Game.player
	if Game.has_player() and player.has_method("enter_vehicle") and player.has_method("exit_vehicle"):
		TestHarness.check(car.can_enter(player), "can_enter(player) on the parked %s" % car.spec_id)
		player.call("enter_vehicle", car, 0, true)
		await _frames(30)
		TestHarness.check(car.driver == player and car.is_player_driven and Game.get_player_vehicle() == car,
				"Player.enter_vehicle() seats the player: driver set, is_player_driven, Game.get_player_vehicle()")
		TestHarness.check(car.engine_on and car.owner_tag == "player", "engine running, owner_tag 'player'")
		var seat: Node3D = car.get_seat_node(0)
		TestHarness.check(seat != null and player.global_position.distance_to(seat.global_position) < 0.6,
				"the player sits at Seat_Driver (%.2f m away)" % player.global_position.distance_to(seat.global_position))
		var p0: Vector3 = car.global_position
		Input.action_press("move_forward")
		await _frames(180)
		var sp: float = car.get_forward_speed()
		TestHarness.check(sp > 3.0 and car.global_position.distance_to(p0) > 4.0,
				"move_forward drives the car in the real world (%.1f m/s, %.1f m travelled)" % [sp, car.global_position.distance_to(p0)])
		TestHarness.check(car.global_transform.basis.y.y > 0.85, "still upright while driving (up.y %.3f)" % car.global_transform.basis.y.y)
		TestHarness.check(player.global_position.distance_to(car.get_seat_node(0).global_position) < 0.6, "the player stays glued to the seat at speed")
		Input.action_release("move_forward")
		Input.action_press("handbrake")
		var hb_frames := 0
		var hb_v0: float = car.get_forward_speed()
		while hb_frames < 240 and absf(car.get_forward_speed()) > 0.5:
			await get_tree().physics_frame
			hb_frames += 1
		await _frames(30)
		Input.action_release("handbrake")
		var hb_t := float(hb_frames) / 60.0
		TestHarness.check(absf(car.get_forward_speed()) < 1.0 and hb_t < 3.6,
				"a held handbrake stops the car (%.1f m/s -> 0.5 m/s in %.2f s = %.1f m/s^2)" % [hb_v0, hb_t, (hb_v0 - 0.5) / maxf(hb_t, 0.01)])
		player.call("exit_vehicle")
		await _frames(120)
		TestHarness.check(not car.is_player_driven and car.driver == null, "Player.exit_vehicle() frees the driver seat")
		TestHarness.check(player.get("current_vehicle") == null, "the player is on foot again")
		var local: Vector3 = car.global_transform.affine_inverse() * player.global_position
		TestHarness.check(Vector2(local.x, local.z).length() < 6.0 and absf(local.x) > 0.6,
				"the player stands beside the car after leaving (local %.1f, %.1f, %.1f)" % [local.x, local.y, local.z])
		# thrown out by the vehicle (police drag-out / wreck path)
		player.call("enter_vehicle", car, 0, true)
		await _frames(20)
		car.eject_occupants(Vector3.ZERO)
		await _frames(90)
		TestHarness.check(car.get_occupants().is_empty() and player.get("current_vehicle") == null,
				"eject_occupants() throws the real player out cleanly")
	else:
		TestHarness.log_line("no Player (or it lacks enter_vehicle) - driving through set_inputs() instead")
		var p1: Vector3 = car.global_position
		car.set_inputs(1.0, 0.0, 0.0)
		await _frames(180)
		TestHarness.check(car.get_forward_speed() > 3.0, "set_inputs() drives the car in the real world (%.1f m/s, %.1f m)" % [car.get_forward_speed(), car.global_position.distance_to(p1)])
		car.set_inputs(0.0, 0.0, 1.0)
		await _frames(150)

	# ---------------------------------------------------------------- save provider round trip
	if is_instance_valid(car) and not car.destroyed:
		mgr.set_personal_vehicle(car)
		var data: Dictionary = mgr.get_save_data()
		TestHarness.check(data.has("personal") and str((data["personal"] as Dictionary).get("spec_id", "")) == car.spec_id,
				"VehicleManager.get_save_data() carries the personal vehicle")
	mgr.clear_all(true)
	await _frames(5)
	TestHarness.check(mgr.get_vehicle_count() == 0, "clear_all(true) leaves no vehicles")
	TestHarness.finish()
