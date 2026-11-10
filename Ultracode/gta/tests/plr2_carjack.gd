extends Node
## plr2_carjack - headless test of the vehicle interactions of the player against the REAL vehicle
## module (W2.1): carjacking a sedan driven by a dummy AI (ai_controller.release_vehicle("carjacked"),
## EventBus.vehicle_stolen, vehicle_theft crime, the player ends up driving), riding along as a
## passenger (hold the key, the driver stays), shoving a rider off a motorcycle, stealing an empty
## police cruiser (police_vehicle_theft), an empty civilian car (no crime) and the Wave 1 entry
## threshold bug (car centre < 8 m, door > 8 m).
##
##   tools\godot.ps1 -Mode headless -Frames 4800 -TimeoutSec 300 `
##       -UserArgs '--test=plr2_carjack','--disable=traffic,peds,police','--test-timeout=240'

const Arena := preload("res://gta/tests/plr_arena.gd")


## Stand-in AI driver (test equipment): NpcBase-compatible bits the player touches.
class DummyNpc extends CharacterBody3D:
	var is_dead: bool = false
	var faction: String = "civilian"
	var knockdowns: int = 0
	var current_vehicle: Node3D = null

	func _init() -> void:
		add_to_group("npc")
		collision_layer = 0
		collision_mask = Layers.WORLD

	func knock_down(_impulse: Vector3) -> void:
		knockdowns += 1

	func get_target_position() -> Vector3:
		return global_position + Vector3(0.0, 1.2, 0.0)


## Stand-in AI controller implementing the W2.1 release_vehicle contract.
class DummyController extends Node:
	var calls: Array = []
	var npc: DummyNpc = null

	func drive(vehicle: Node3D, who: DummyNpc) -> void:
		npc = who
		vehicle.set_meta("ai_controller", self)
		vehicle.call("occupant_enter", who, 0)
		who.current_vehicle = vehicle
		var seat: Variant = vehicle.call("get_seat_node", 0)
		if seat is Node3D:
			who.global_transform = (seat as Node3D).global_transform

	func release_vehicle(vehicle: Node3D, reason: String) -> Node3D:
		calls.append(reason)
		var xf: Transform3D = vehicle.call("occupant_exit", 0)
		if vehicle.has_meta("ai_controller"):
			vehicle.remove_meta("ai_controller")
		npc.current_vehicle = null
		npc.global_transform = xf
		return npc


var P: Player = null
var arena: Arena = null
var T: Node = null
var stolen: Array = []           # [vehicle, thief, had_driver]
var crimes: Array = []           # crime ids
var skipped: PackedStringArray = []


func _ready() -> void:
	T = TestHarness
	await _run()


func _run() -> void:
	P = Game.player as Player
	if not T.check(P != null, "Game.player is a Player"):
		T.finish(false, "no player")
		return
	if not T.check(Game.get_system("vehicles") != null, "vehicles system present"):
		T.finish(false, "needs the vehicle module")
		return
	arena = Arena.new()
	Game.main.add_child(arena)
	EventBus.vehicle_stolen.connect(func(v: Node3D, thief: Node, had: bool) -> void: stolen.append([v, thief, had]))
	EventBus.crime_committed.connect(func(id: String, _pos: Vector3, _who: Node) -> void: crimes.append(id))
	await T.wait_physics_frames(5)
	await _test_carjack()
	await _test_no_controller()
	await _test_passenger()
	await _test_bike_shove()
	await _test_police_cruiser()
	await _test_empty_civilian()
	await _test_threshold_bug()
	_release_all()
	var note := "carjack"
	if not skipped.is_empty():
		note += " | SKIPPED: " + ", ".join(skipped)
	T.finish(true, note)


# --- helpers ---------------------------------------------------------------------------------------

func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "enter_vehicle", "aim", "fire"]:
		Input.action_release(a)


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	while t < timeout:
		if bool(cond.call()):
			return true
		await get_tree().physics_frame
		t += step
	return bool(cond.call())


func _spawn(id: String, local: Vector3, owner: String) -> Node3D:
	var v := Game.spawn_vehicle(id, Transform3D(Basis.IDENTITY, arena.at(local) + Vector3(0.0, 0.6, 0.0)), {"owner_tag": owner})
	if v == null:
		return null
	await T.wait_physics_frames(45)        # settle on the suspension
	return v


func _leave_vehicle() -> void:
	if P.current_vehicle != null or P.state_id == "vehicle":
		P.exit_vehicle()
		await _until(func() -> bool: return P.state_id != "vehicle", 2.0)
	_release_all()
	await T.wait_physics_frames(10)


func _stand_at_door(v: Node3D, seat: int, out: float = 0.9) -> void:
	var door: Vector3 = v.call("get_door_position", seat) if v.has_method("get_door_position") else v.global_position
	var away := door - v.global_position
	away.y = 0.0
	away = away.normalized()
	var spot := door + away * out
	spot.y = arena.at(Vector3.ZERO).y + 0.03
	var to := v.global_position - spot
	P.teleport(spot, atan2(-to.x, -to.z))
	await T.wait_physics_frames(15)


func _tap(action: String) -> void:
	Input.action_press(action)
	await T.wait_physics_frames(2)
	Input.action_release(action)


func _despawn(v: Node3D) -> void:
	if v == null or not is_instance_valid(v):
		return
	var vm := Game.get_system("vehicles")
	if vm != null and vm.has_method("despawn_vehicle"):
		vm.call("despawn_vehicle", v)
	else:
		v.queue_free()
	await T.wait_physics_frames(5)


# --- tests ----------------------------------------------------------------------------------------

func _test_carjack() -> void:
	var v := await _spawn("sedan", Vector3(-30.0, 0.0, 50.0), "civilian")
	if not T.check(v != null, "spawn a sedan"):
		return
	var npc := DummyNpc.new()
	npc.name = "JackVictim"
	arena.add_child(npc)
	var ctrl := DummyController.new()
	ctrl.name = "DummyController"
	arena.add_child(ctrl)
	ctrl.drive(v, npc)
	await T.wait_physics_frames(5)
	T.check(v.get("driver") == npc, "the dummy AI drives the sedan")
	await _stand_at_door(v, 0)
	await T.wait_physics_frames(12)
	var prompt := P.interaction.get_prompt_text()
	T.check(prompt.begins_with("Steal"), "the prompt offers to steal it ('%s')" % prompt)
	stolen.clear()
	crimes.clear()
	await _tap("enter_vehicle")
	var st := P.states["vehicle"] as PlayerStateVehicle
	var walking := await _until(func() -> bool: return P.state_id == "vehicle", 0.6)
	T.check(walking and st.jacking, "tapping the enter key starts a carjack (state %s, jacking %s)" % [P.state_id, str(st.jacking)])
	var jack := await _until(func() -> bool: return st.phase == PlayerStateVehicle.JACK, 1.5)
	T.check(jack, "the player reaches the door and plays the jack transition (phase %d)" % st.phase)
	await T.wait_physics_frames(3)
	T.check(P.animator.get_action() == "jack", "animator action 'jack' (%s)" % P.animator.get_action())
	var seated := await _until(func() -> bool: return st.phase == PlayerStateVehicle.SEATED, 3.0)
	T.check(ctrl.calls == ["carjacked"], "controller.release_vehicle(vehicle, 'carjacked') called once (%s)" % str(ctrl.calls))
	T.check(not v.has_meta("ai_controller"), "the vehicle has no ai_controller afterwards")
	T.check(npc.knockdowns >= 1, "the pulled-out driver is thrown to the ground (%d knock-downs)" % npc.knockdowns)
	var got := false
	for s: Array in stolen:
		if s[0] == v and s[1] == P and bool(s[2]):
			got = true
	T.check(got, "EventBus.vehicle_stolen(vehicle, player, true) (%s)" % str(stolen.size()))
	T.check(crimes.has("vehicle_theft"), "Wanted.report_crime('vehicle_theft') (%s)" % str(crimes))
	T.check(seated and P.current_vehicle == v and v.get("driver") == P and bool(v.get("is_player_driven")),
			"the player ends up driving (seated %s, driver ok %s)" % [str(seated), str(v.get("driver") == P)])
	T.check(str(v.get("owner_tag")) == "player", "the vehicle is now the player's (owner_tag %s)" % str(v.get("owner_tag")))
	await _leave_vehicle()
	await _despawn(v)
	npc.queue_free()
	ctrl.queue_free()


func _test_no_controller() -> void:
	# a driver put in by a module without an ai_controller: the player still pulls it out
	var v := await _spawn("sedan", Vector3(-30.0, 0.0, 65.0), "civilian")
	if v == null:
		skipped.append("no-controller jack (no sedan)")
		return
	var npc := DummyNpc.new()
	arena.add_child(npc)
	v.call("occupant_enter", npc, 0)
	await T.wait_physics_frames(5)
	await _stand_at_door(v, 0)
	stolen.clear()
	await _tap("enter_vehicle")
	var st := P.states["vehicle"] as PlayerStateVehicle
	await _until(func() -> bool: return st.phase == PlayerStateVehicle.JACK, 1.5)
	var out := await _until(func() -> bool: return int(v.call("get_seat_of", npc)) < 0, 1.0)
	var seated := await _until(func() -> bool: return st.phase == PlayerStateVehicle.SEATED, 3.0)
	T.check(out and npc.knockdowns >= 1, "without an ai_controller the driver is still pulled out and thrown down (%s, %d)" % [str(out), npc.knockdowns])
	T.check(seated and v.get("driver") == P and not stolen.is_empty() and bool(stolen[0][2]), "... and the player drives off with it")
	await _leave_vehicle()
	await _despawn(v)
	npc.queue_free()


func _test_passenger() -> void:
	var v := await _spawn("sedan", Vector3(-15.0, 0.0, 50.0), "civilian")
	if v == null:
		skipped.append("passenger (no sedan)")
		return
	var npc := DummyNpc.new()
	arena.add_child(npc)
	var ctrl := DummyController.new()
	arena.add_child(ctrl)
	ctrl.drive(v, npc)
	await T.wait_physics_frames(5)
	await _stand_at_door(v, 1)
	stolen.clear()
	crimes.clear()
	Input.action_press("enter_vehicle")
	await T.wait_seconds(0.6)
	Input.action_release("enter_vehicle")
	var st := P.states["vehicle"] as PlayerStateVehicle
	var seated := await _until(func() -> bool: return P.state_id == "vehicle" and st.phase == PlayerStateVehicle.SEATED, 3.0)
	T.check(seated and P.seat_index > 0, "holding the enter key rides along as a passenger (seat %d)" % P.seat_index)
	T.check(v.get("driver") == npc and ctrl.calls.is_empty(), "the driver stays (driver ok %s, release calls %s)" % [str(v.get("driver") == npc), str(ctrl.calls)])
	T.check(stolen.is_empty() and crimes.is_empty(), "riding along is not theft (%d stolen, crimes %s)" % [stolen.size(), str(crimes)])
	await T.wait_physics_frames(30)
	T.check(P.current_vehicle == v and P.state_id == "vehicle", "the passenger stays seated (%s)" % P.state_id)
	await _leave_vehicle()
	T.check(P.state_id == "on_foot" and v.get("driver") == npc, "the passenger gets out, the driver remains")
	ctrl.release_vehicle(v, "despawn")
	await _despawn(v)
	npc.queue_free()
	ctrl.queue_free()


func _test_bike_shove() -> void:
	var v := await _spawn("motorcycle", Vector3(0.0, 0.0, 50.0), "civilian")
	if v == null:
		skipped.append("bike shove (no motorcycle)")
		return
	var npc := DummyNpc.new()
	arena.add_child(npc)
	var ctrl := DummyController.new()
	arena.add_child(ctrl)
	ctrl.drive(v, npc)
	await T.wait_physics_frames(10)
	if not bool(v.call("can_enter", P)):
		skipped.append("bike shove (the motorcycle cannot be entered: upright %.2f)" % v.global_basis.y.y)
		ctrl.release_vehicle(v, "despawn")
		await _despawn(v)
		return
	await _stand_at_door(v, 0, 0.6)
	stolen.clear()
	await _tap("enter_vehicle")
	var st := P.states["vehicle"] as PlayerStateVehicle
	await _until(func() -> bool: return st.phase == PlayerStateVehicle.JACK, 1.5)
	await T.wait_physics_frames(3)
	T.check(P.animator.get_action() == "shove", "a rider is shoved off a motorcycle (action '%s')" % P.animator.get_action())
	var seated := await _until(func() -> bool: return st.phase == PlayerStateVehicle.SEATED, 3.0)
	T.check(ctrl.calls == ["carjacked"] and npc.knockdowns >= 1, "the rider comes off and falls (%s, %d)" % [str(ctrl.calls), npc.knockdowns])
	T.check(seated and v.get("driver") == P and P.animator.state == "seated_bike", "the player rides the motorcycle (%s)" % P.animator.state)
	T.check(not stolen.is_empty() and bool(stolen[0][2]), "vehicle_stolen with had_driver = true")
	await _leave_vehicle()
	await _despawn(v)
	npc.queue_free()
	ctrl.queue_free()


func _test_police_cruiser() -> void:
	var v := await _spawn("police_cruiser", Vector3(15.0, 0.0, 50.0), "police")
	if v == null:
		skipped.append("police cruiser (no spec)")
		return
	await _stand_at_door(v, 0)
	stolen.clear()
	crimes.clear()
	await _tap("enter_vehicle")
	var st := P.states["vehicle"] as PlayerStateVehicle
	var seated := await _until(func() -> bool: return P.state_id == "vehicle" and st.phase == PlayerStateVehicle.SEATED, 3.0)
	T.check(seated and not st.jacking, "an empty cruiser is entered normally")
	T.check(crimes.has("police_vehicle_theft"), "taking a police vehicle is a crime (%s)" % str(crimes))
	T.check(not stolen.is_empty() and not bool(stolen[0][2]), "vehicle_stolen(cruiser, player, false)")
	await _leave_vehicle()
	await _despawn(v)


func _test_empty_civilian() -> void:
	var v := await _spawn("compact", Vector3(30.0, 0.0, 50.0), "parked")
	if v == null:
		skipped.append("empty civilian (no compact)")
		return
	await _stand_at_door(v, 0)
	stolen.clear()
	crimes.clear()
	await _tap("enter_vehicle")
	var st := P.states["vehicle"] as PlayerStateVehicle
	var seated := await _until(func() -> bool: return P.state_id == "vehicle" and st.phase == PlayerStateVehicle.SEATED, 3.0)
	T.check(seated, "an empty parked car is entered")
	T.check(crimes.is_empty(), "taking an empty civilian car is no crime (%s)" % str(crimes))
	T.check(stolen.size() == 1, "... but vehicle_stolen(car, player, false) is announced once (%d)" % stolen.size())
	await _leave_vehicle()
	# entering again: already the player's, nothing new
	stolen.clear()
	await _stand_at_door(v, 0)
	await _tap("enter_vehicle")
	await _until(func() -> bool: return P.state_id == "vehicle" and st.phase == PlayerStateVehicle.SEATED, 3.0)
	T.check(stolen.is_empty(), "re-entering the player's own car announces nothing (%d)" % stolen.size())
	await _leave_vehicle()
	await _despawn(v)


func _test_threshold_bug() -> void:
	# Wave 1 bug: car centre < 8 m away but its driver door > 8-9 m away -> the entry aborted silently
	var v := await _spawn("sedan", Vector3(-30.0, 0.0, 20.0), "parked")
	if v == null:
		skipped.append("threshold (no sedan)")
		return
	var door: Vector3 = v.call("get_door_position", 0)
	var away := v.global_position - door
	away.y = 0.0
	away = away.normalized()
	var spot := v.global_position + away * 7.6
	spot.y = arena.at(Vector3.ZERO).y + 0.03
	P.teleport(spot, 0.0)
	await T.wait_physics_frames(10)
	var centre_d := Vector2(spot.x - v.global_position.x, spot.z - v.global_position.z).length()
	var door_d := Vector2(spot.x - door.x, spot.z - door.z).length()
	P.enter_vehicle(v, 0)
	var st := P.states["vehicle"] as PlayerStateVehicle
	var seated := await _until(func() -> bool: return P.state_id == "vehicle" and st.phase == PlayerStateVehicle.SEATED, 2.0)
	T.check(centre_d < 8.0 and door_d > 8.0 and seated,
			"enter_vehicle with the centre %.1f m and the door %.1f m away no longer aborts (seated %s)" % [centre_d, door_d, str(seated)])
	await _leave_vehicle()
	await _despawn(v)
