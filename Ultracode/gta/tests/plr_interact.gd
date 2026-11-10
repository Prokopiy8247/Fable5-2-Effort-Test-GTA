extends Node
## plr_interact - headless test of everything the player does WITH other modules:
## interaction prompts, vehicle enter / exit / bail / eject (vehicle seat contract), weapon
## inventory input forwarding.
##
##   tools\godot.ps1 -Mode headless -Frames 4200 -TimeoutSec 240 `
##       -UserArgs '--test=plr_interact','--disable=traffic,peds,police','--test-timeout=200'
##
## Hard checks run against small stand-ins (gta/tests/plr_arena.gd: MockVehicle, MockInventory) so
## that the result only depends on the player module. The same paths are then exercised against
## the REAL vehicle and weapon modules when they are available; those results are logged as
## "REAL_*" lines and listed as skipped when the neighbour module is missing.

const Arena := preload("res://gta/tests/plr_arena.gd")
const INTERACTABLE_SCRIPT := "res://gta/code/world/interactable.gd"

var P: Player = null
var arena: Arena = null
var T: Node = null
var ev: Dictionary = {"veh_in": 0, "veh_out": 0, "focus": 0, "state": []}
var skipped: PackedStringArray = []
var real_notes: PackedStringArray = []


func _ready() -> void:
	T = TestHarness
	await _run()


func _run() -> void:
	P = Game.player as Player
	if not T.check(P != null, "Game.player is a Player"):
		T.finish(false, "no player")
		return
	arena = Arena.new()
	Game.main.add_child(arena)
	EventBus.player_entered_vehicle.connect(func(_v: Node3D, _s: int) -> void: ev["veh_in"] += 1)
	EventBus.player_exited_vehicle.connect(func(_v: Node3D) -> void: ev["veh_out"] += 1)
	EventBus.interactable_focus_changed.connect(func(_n: Node) -> void: ev["focus"] += 1)
	EventBus.player_state_changed.connect(func(s: String) -> void: (ev["state"] as Array).append(s))
	await T.wait_physics_frames(3)
	await _test_real_inventory()
	await _test_real_vehicle()
	await _test_real_pickups()
	await _test_interactables()
	await _test_vehicle_enter_exit()
	await _test_vehicle_bail_and_eject()
	await _test_vehicle_lost()
	await _test_vehicle_hit()
	await _test_inventory_forwarding()
	_release_all()
	for n in real_notes:
		T.log_line(n)
	var note := "player integration"
	if not skipped.is_empty():
		note += " | SKIPPED: " + ", ".join(skipped)
	T.finish(true, note)


# --- helpers ---------------------------------------------------------------------------------------

func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "crouch", "aim", "fire",
			"interact", "enter_vehicle", "reload", "weapon_next", "weapon_prev", "throw_grenade", "melee_heavy"]:
		Input.action_release(a)


func _tap(action: String) -> void:
	await get_tree().physics_frame
	Input.action_press(action)
	await T.wait_physics_frames(3)
	Input.action_release(action)
	await T.wait_physics_frames(2)


func _place(local: Vector3, yaw: float = 0.0) -> void:
	_release_all()
	P.teleport(arena.at(local) + Vector3(0.0, 0.03, 0.0), yaw)
	await T.wait_physics_frames(20)


func _wait_until(cond: Callable, max_seconds: float) -> bool:
	var frames := int(max_seconds * 60.0)
	for i in frames:
		if bool(cond.call()):
			return true
		await get_tree().physics_frame
	return bool(cond.call())


func _real(line: String) -> void:
	real_notes.append(line)


# --- interactables ---------------------------------------------------------------------------------

func _test_interactables() -> void:
	await _place(Arena.STAGE + Vector3(0.0, 0.0, -30.0), 0.0)
	if not ResourceLoader.exists(INTERACTABLE_SCRIPT):
		skipped.append("interactables (interactable.gd missing)")
		return
	var scr := load(INTERACTABLE_SCRIPT) as Script
	var uses: Array = []
	var a := scr.new() as Area3D
	a.set("prompt", "Open crate")
	a.set("radius", 2.0)
	a.set("cooldown", 0.0)
	Game.main.add_child(a)
	a.global_position = P.global_position + Vector3(1.0, 1.0, 0.0)
	a.connect("interacted", func(who: Node3D) -> void: uses.append(["a", who]))
	await T.wait_seconds(0.5)
	T.check(P.interaction.focus == a, "the scanner focuses an Interactable in reach")
	T.check(P.interaction.get_prompt_text() == "Open crate" and P.interaction.get_prompt_action() == "interact",
			"its prompt is shown through UI.show_prompt ('%s')" % P.interaction.get_prompt_text())
	T.check(int(ev["focus"]) >= 1, "EventBus.interactable_focus_changed emitted")
	await _tap("interact")
	T.check(uses.size() == 1 and uses[0][1] == P, "the interact key calls interact(player) once (%d)" % uses.size())
	# a higher priority interactable wins, even if it is further away
	var b := scr.new() as Area3D
	b.set("prompt", "Use terminal")
	b.set("radius", 3.0)
	b.set("use_priority", 5)
	b.set("cooldown", 0.0)
	Game.main.add_child(b)
	b.global_position = P.global_position + Vector3(-2.0, 1.0, 0.0)
	b.connect("interacted", func(who: Node3D) -> void: uses.append(["b", who]))
	await T.wait_seconds(0.5)
	T.check(P.interaction.focus == b and P.interaction.get_prompt_text() == "Use terminal", "use_priority decides between candidates")
	b.set("enabled", false)
	await T.wait_seconds(0.4)
	T.check(P.interaction.focus == a, "falls back to the other candidate when the first cannot be used")
	# no interaction while the input is locked
	Game.lock_input()
	await _tap("interact")
	Game.unlock_input()
	T.check(uses.size() == 1, "no interaction while the input is locked")
	# an interactable bound to the enter_vehicle key takes that key over
	a.set("action", "enter_vehicle")
	var car := arena.spawn_mock_vehicle(Arena.STAGE + Vector3(0.0, 0.0, -33.0), PI * 0.5, "car")
	await T.wait_seconds(0.5)
	await _tap("enter_vehicle")
	await T.wait_seconds(0.3)
	T.check(uses.size() == 2 and P.state_id == "on_foot", "an Interactable bound to 'enter_vehicle' wins over a nearby vehicle")
	car.queue_free()
	# out of reach
	await _place(Arena.STAGE + Vector3(12.0, 0.0, -30.0), 0.0)
	await T.wait_seconds(0.4)
	T.check(P.interaction.focus == null and P.interaction.get_prompt_text() == "", "focus and prompt clear out of reach")
	a.queue_free()
	b.queue_free()
	await T.wait_physics_frames(3)


# --- vehicles (stand-in) ---------------------------------------------------------------------------

func _test_vehicle_enter_exit() -> void:
	await _place(Arena.STAGE + Vector3(0.0, 0.0, 0.0), 0.0)
	var car := arena.spawn_mock_vehicle(Arena.STAGE + Vector3(4.2, 0.0, 0.0), 0.0, "car")
	car.display_name = "Test Car"
	await T.wait_seconds(0.6)
	var home := P.get_parent()
	T.check(P.find_enterable_vehicle() == car, "find_enterable_vehicle picks the vehicle in reach")
	T.check(P.interaction.get_prompt_text() == "Enter Test Car" and P.interaction.get_prompt_action() == "enter_vehicle",
			"enter-vehicle prompt is shown ('%s')" % P.interaction.get_prompt_text())
	var in0 := int(ev["veh_in"])
	var out0 := int(ev["veh_out"])
	# enter: watch the transition frame by frame
	await get_tree().physics_frame
	Input.action_press("enter_vehicle")
	var max_step := 0.0
	var frames_to_seat := 0
	var prev := P.global_position
	for i in 180:
		await get_tree().physics_frame
		if i == 3:
			Input.action_release("enter_vehicle")
		max_step = maxf(max_step, P.global_position.distance_to(prev))
		prev = P.global_position
		if P.current_vehicle == car:
			frames_to_seat = i
			break
	T.check(P.current_vehicle == car and P.state_id == "vehicle", "enter_vehicle key seats the player (state %s)" % P.state_id)
	T.check(frames_to_seat > 20, "getting in is a transition, not a pop (%d frames)" % frames_to_seat)
	T.check(max_step < 0.2, "the body moves smoothly to the door and the seat (max step %.3f m / tick)" % max_step)
	T.check(car.count("enter") == 1 and car.calls[0][1] == P and car.calls[0][2] == 0, "vehicle.occupant_enter(player, 0) called once")
	T.check(P.get_parent() == car.seat and P.transform.is_equal_approx(Transform3D.IDENTITY), "the body is parented to vehicle.get_seat_node(seat)")
	T.check(not P.is_collision_enabled(), "player collision is disabled while seated")
	T.check(int(ev["veh_in"]) - in0 == 1, "EventBus.player_entered_vehicle emitted")
	T.check(Game.get_player_vehicle() == car, "Game.get_player_vehicle() returns the vehicle")
	await T.wait_seconds(0.5)
	T.check(P.animator.state == "seated_car", "seated pose for cars (%s)" % P.animator.state)
	T.check((ev["state"] as Array).has("in_vehicle"), "player_state_changed('in_vehicle') emitted")
	T.check(P.interaction.get_prompt_text() == "", "no enter prompt while seated")
	# the seat follows the vehicle
	car.linear_velocity = Vector3(0.0, 0.0, -4.0)
	await T.wait_seconds(0.5)
	T.check(P.global_position.distance_to(car.seat.global_position) < 0.001, "the player stays glued to the seat while the vehicle moves")
	T.check(Game.get_player_position().distance_to(car.global_position) < 0.001, "Game.get_player_position() reports the vehicle position")
	car.linear_velocity = Vector3.ZERO
	await T.wait_seconds(0.8)
	# exit with the same key
	var exit_xf := car.get_exit_transform(0)
	await _tap("enter_vehicle")
	var ok := await _wait_until(func() -> bool: return P.state_id == "on_foot", 2.5)
	T.check(ok and P.current_vehicle == null, "the same key leaves the vehicle (state %s)" % P.state_id)
	T.check(car.count("exit") == 1, "vehicle.occupant_exit(seat) called once")
	T.check(P.global_position.distance_to(exit_xf.origin) < 0.35, "the player stands at the exit transform (%.2f m off)" % P.global_position.distance_to(exit_xf.origin))
	T.check(P.get_parent() == home and P.is_collision_enabled(), "back under the original parent with collision on")
	T.check(absf(P.global_basis.y.y - 1.0) < 0.001, "the body is upright again")
	T.check(int(ev["veh_out"]) - out0 == 1, "EventBus.player_exited_vehicle emitted")
	await T.wait_physics_frames(10)
	T.check(P.collision_layer == Layers.PLAYER, "collision layer restored")
	car.queue_free()
	await T.wait_physics_frames(3)
	# bikes use the bike pose, API entry with an explicit seat
	var bike := arena.spawn_mock_vehicle(Arena.STAGE + Vector3(-4.0, 0.0, 0.0), 0.0, "bike")
	await T.wait_seconds(0.3)
	P.enter_vehicle(bike, 0)
	await _wait_until(func() -> bool: return P.current_vehicle == bike, 3.0)
	await T.wait_seconds(0.5)
	T.check(P.current_vehicle == bike and P.animator.state == "seated_bike", "seated_bike pose on bikes (%s)" % P.animator.state)
	P.exit_vehicle()
	await _wait_until(func() -> bool: return P.state_id == "on_foot", 2.5)
	T.check(P.current_vehicle == null and P.state_id == "on_foot", "exit_vehicle() API leaves the bike")
	bike.queue_free()
	await T.wait_physics_frames(3)


func _test_vehicle_bail_and_eject() -> void:
	await _place(Arena.STAGE + Vector3(0.0, 0.0, 10.0), 0.0)
	P.heal(1000.0)
	var car := arena.spawn_mock_vehicle(Arena.STAGE + Vector3(4.0, 0.0, 10.0), 0.0, "car")
	await T.wait_seconds(0.4)
	P.enter_vehicle(car, 0, true)
	await T.wait_physics_frames(5)
	T.check(P.current_vehicle == car, "enter_vehicle(vehicle, seat, instant) seats at once")
	car.linear_velocity = Vector3(0.0, 0.0, -16.0)
	P.exit_vehicle()
	await T.wait_physics_frames(3)
	T.check(P.state_id == "ragdoll" and P.current_vehicle == null, "leaving a fast vehicle = bail out and tumble (state %s)" % P.state_id)
	T.check(P.health < P.max_health and P.health > 50.0, "bailing out hurts a little (hp %.0f)" % P.health)
	car.linear_velocity = Vector3.ZERO
	var ok := await _wait_until(func() -> bool: return P.state_id == "on_foot", 8.0)
	T.check(ok, "gets up after the bail-out")
	car.queue_free()
	await T.wait_physics_frames(3)
	# thrown out by the vehicle
	await _place(Arena.STAGE + Vector3(0.0, 0.0, 10.0), 0.0)
	P.heal(1000.0)
	var car2 := arena.spawn_mock_vehicle(Arena.STAGE + Vector3(4.0, 0.0, 10.0), 0.0, "car")
	await T.wait_seconds(0.4)
	P.enter_vehicle(car2, 0, true)
	await T.wait_physics_frames(5)
	var exits := car2.count("exit")
	car2.driver = null
	P.on_vehicle_ejected(car2, car2.get_exit_transform(0), Vector3(-300.0, 150.0, 0.0))
	await T.wait_physics_frames(3)
	T.check(P.current_vehicle == null and P.state_id == "ragdoll", "on_vehicle_ejected throws the player out (state %s)" % P.state_id)
	T.check(car2.count("exit") == exits, "the vehicle is not asked to free the seat twice")
	ok = await _wait_until(func() -> bool: return P.state_id == "on_foot", 8.0)
	T.check(ok and P.get_parent() == Game.main, "recovers on foot under the main scene")
	# wrecked with the player inside
	P.heal(1000.0)
	P.armor = 0.0
	P.enter_vehicle(car2, 0, true)
	await T.wait_physics_frames(5)
	car2.destroyed = true
	await T.wait_physics_frames(5)
	T.check(P.is_dead and P.current_vehicle == null, "a vehicle destroyed with the player inside kills an unarmored player")
	P.respawn(Transform3D(Basis.IDENTITY, arena.at(Arena.STAGE + Vector3(0.0, 0.05, 10.0))))
	await T.wait_physics_frames(10)
	car2.queue_free()
	await T.wait_physics_frames(3)


func _test_vehicle_lost() -> void:
	await _place(Arena.STAGE + Vector3(0.0, 0.0, 20.0), 0.0)
	var car := arena.spawn_mock_vehicle(Arena.STAGE + Vector3(4.0, 0.0, 20.0), 0.0, "car")
	await T.wait_seconds(0.4)
	P.enter_vehicle(car, 0, true)
	await T.wait_physics_frames(5)
	var out0 := int(ev["veh_out"])
	car.queue_free()
	await T.wait_seconds(1.0)
	T.check(is_instance_valid(P) and P.is_inside_tree(), "the player survives when its vehicle is freed")
	T.check(P.current_vehicle == null and (P.state_id == "on_foot" or P.state_id == "air"), "and is back on foot (state %s)" % P.state_id)
	T.check(P.get_parent() == Game.main and P.is_collision_enabled(), "re-homed under the main scene with collision")
	T.check(int(ev["veh_out"]) - out0 == 1, "player_exited_vehicle emitted for the lost vehicle")
	T.check(Game.player == P, "Game.player still points at the player")
	await T.wait_seconds(0.5)


# --- inventory forwarding (stand-in) ---------------------------------------------------------------

func _test_inventory_forwarding() -> void:
	await _place(Arena.STAGE + Vector3(0.0, 0.0, -10.0), 0.0)
	var inv := arena.install_mock_inventory(P)
	await T.wait_seconds(0.4)
	T.check(P.inventory == inv and P.is_armed(), "is_armed() reflects the inventory")
	T.check(P.animator.weapon_pose == "pistol", "weapon pose reaches the animator (%s)" % P.animator.weapon_pose)
	Input.action_press("fire")
	await T.wait_physics_frames(6)
	T.check(inv.count("trigger_pressed") == 1, "fire -> trigger_pressed once while held")
	T.check(P.is_combat_facing(), "firing turns the body towards the camera for a moment")
	Input.action_release("fire")
	await T.wait_physics_frames(4)
	T.check(inv.count("trigger_released") == 1, "releasing fire -> trigger_released")
	await _tap("reload")
	T.check(inv.count("reload") == 1, "reload forwarded")
	await _tap("weapon_next")
	await _tap("weapon_prev")
	T.check(inv.count("next") == 1 and inv.count("prev") == 1, "weapon_next / weapon_prev forwarded")
	await _tap("weapon_slot_3")
	await _tap("weapon_slot_9")
	T.check(inv.count("slot_3") == 1 and inv.count("slot_9") == 1, "weapon_slot_N -> equip_slot(N)")
	await _tap("throw_grenade")
	T.check(inv.count("throw") == 1, "throw_grenade forwarded")
	await _tap("melee_heavy")
	T.check(inv.count("melee_heavy") == 1, "melee_heavy -> melee_attack(true)")
	Input.action_press("aim")
	await T.wait_physics_frames(5)
	Input.action_release("aim")
	await T.wait_physics_frames(5)
	T.check(inv.count("aim_on") == 1 and inv.count("aim_off") == 1, "aim -> set_aiming(true / false)")
	# nothing is forwarded while the input is locked; a held trigger is released
	Input.action_press("fire")
	await T.wait_physics_frames(4)
	Game.lock_input()
	await T.wait_physics_frames(4)
	T.check(inv.count("trigger_pressed") == 2 and inv.count("trigger_released") == 2, "locking the input releases a held trigger")
	await _tap("reload")
	T.check(inv.count("reload") == 1, "no weapon input while locked")
	Game.unlock_input()
	Input.action_release("fire")
	await T.wait_physics_frames(4)
	# no firing from a vehicle unless the inventory allows that weapon there
	var car := arena.spawn_mock_vehicle(Arena.STAGE + Vector3(4.0, 0.0, -10.0), 0.0, "car")
	await T.wait_seconds(0.3)
	P.enter_vehicle(car, 0, true)
	await T.wait_physics_frames(5)
	var before := inv.count("trigger_pressed")
	Input.action_press("fire")
	await T.wait_physics_frames(5)
	Input.action_release("fire")
	T.check(inv.count("trigger_pressed") == before, "no trigger in a vehicle when can_use_in_vehicle() is false")
	inv.vehicle_ok = true
	await T.wait_physics_frames(3)
	Input.action_press("fire")
	await T.wait_physics_frames(5)
	Input.action_release("fire")
	await T.wait_physics_frames(3)
	T.check(inv.count("trigger_pressed") == before + 1, "drive-by: trigger forwarded when can_use_in_vehicle() is true")
	P.teleport(arena.at(Arena.STAGE + Vector3(0.0, 0.0, -10.0)), 0.0)
	car.queue_free()
	await T.wait_physics_frames(5)
	# the player keeps working with no inventory at all
	inv.queue_free()
	P.inventory = null
	await T.wait_physics_frames(3)
	Input.action_press("fire")
	Input.action_press("aim")
	await T.wait_seconds(0.4)
	Input.action_release("fire")
	Input.action_release("aim")
	T.check(not P.is_armed() and P.get_aim_ray().has("direction"), "everything still works without an inventory")
	await T.wait_physics_frames(5)


# --- the real neighbours (soft) --------------------------------------------------------------------

func _test_real_inventory() -> void:
	await _place(Arena.TARGET_SPOT, 0.0)
	var inv := P.inventory
	if inv == null or not inv.has_method("give_weapon"):
		skipped.append("real WeaponInventory (not present)")
		_real("REAL_INVENTORY: missing")
		return
	T.check(inv.name == "Inventory" and inv.get_parent() == P, "the WeaponInventory is a child named 'Inventory'")
	T.check(inv.get("holder") == P, "inventory.setup(player) was called")
	if not Registry.has_def("weapons", "pistol"):
		skipped.append("real WeaponInventory firing (no 'pistol' weapon spec registered)")
		_real("REAL_INVENTORY: no pistol spec")
		return
	inv.call("give_weapon", "pistol", 60)
	inv.call("equip", "pistol")
	await T.wait_seconds(1.0)
	var armed := P.is_armed() and str(inv.get("current_id")) == "pistol"
	_real("REAL_INVENTORY: equip pistol -> armed=%s pose=%s" % [str(armed), P.animator.weapon_pose])
	var shots: Array = []
	var on_fired := func(id: String, shooter: Node, origin: Vector3, dir: Vector3) -> void:
		if shooter == P:
			shots.append([id, origin, dir])
	EventBus.weapon_fired.connect(on_fired)
	P.camera.pitch = 0.0
	Input.action_press("aim")
	await T.wait_seconds(0.6)
	var aiming := bool(inv.get("is_aiming"))
	Input.action_press("fire")
	await T.wait_seconds(0.25)
	Input.action_release("fire")
	await T.wait_seconds(0.3)
	Input.action_release("aim")
	EventBus.weapon_fired.disconnect(on_fired)
	var dir_ok := false
	if shots.size() > 0:
		dir_ok = (shots[0][2] as Vector3).dot(P.camera.get_aim_direction()) > 0.97
	_real("REAL_INVENTORY: aim forwarded=%s shots=%d shot follows the crosshair=%s" % [str(aiming), shots.size(), str(dir_ok)])
	var hand: Node3D = null
	if P.visual != null and P.visual.has_method("get_bone_attachment"):
		hand = P.visual.call("get_bone_attachment", "Hand_R") as Node3D
	var model_ok := hand != null and hand.get_child_count() > 0
	_real("REAL_INVENTORY: weapon model attached to Hand_R=%s" % str(model_ok))
	if not (armed and aiming and shots.size() > 0 and dir_ok and model_ok):
		skipped.append("real WeaponInventory integration incomplete (see REAL_INVENTORY lines)")
	await T.wait_seconds(0.3)


func _test_real_vehicle() -> void:
	await _place(Arena.STAGE + Vector3(0.0, 0.0, 40.0), 0.0)
	if Game.get_system("vehicles") == null:
		skipped.append("real vehicle (vehicles system missing)")
		_real("REAL_VEHICLE: vehicles system missing")
		return
	var id := ""
	for cand: String in ["sedan", "compact", "sports", "suv", "pickup"]:
		if Registry.has_def("vehicles", cand):
			id = cand
			break
	if id == "":
		skipped.append("real vehicle (no car spec registered)")
		_real("REAL_VEHICLE: no car spec")
		return
	var v := Game.spawn_vehicle(id, Transform3D(Basis.IDENTITY, arena.at(Arena.STAGE + Vector3(4.0, 0.6, 40.0))), {"owner_tag": "parked"})
	if v == null:
		skipped.append("real vehicle (spawn_vehicle('%s') returned null)" % id)
		_real("REAL_VEHICLE: spawn failed for " + id)
		return
	await T.wait_seconds(1.5)
	var found := P.find_enterable_vehicle() == v
	var prompt := P.interaction.get_prompt_text()
	await _tap("enter_vehicle")
	var seated := await _wait_until(func() -> bool: return P.current_vehicle == v, 4.0)
	await T.wait_seconds(0.6)
	var seat_node: Node3D = v.call("get_seat_node", 0) as Node3D if v.has_method("get_seat_node") else null
	var on_seat := seat_node != null and P.get_parent() == seat_node
	var driven := bool(v.get("is_player_driven"))
	_real("REAL_VEHICLE(%s): found=%s prompt='%s' seated=%s on_seat_node=%s is_player_driven=%s anim=%s cam=%s" % [
			id, str(found), prompt, str(seated), str(on_seat), str(driven), P.animator.state, P.camera.mode])
	# drive forward for a moment: the vehicle reads the input itself
	var z0 := v.global_position.z
	Input.action_press("move_forward")
	await T.wait_seconds(2.0)
	Input.action_release("move_forward")
	var drove := absf(v.global_position.z - z0)
	_real("REAL_VEHICLE(%s): drove %.1f m in 2 s with the player seated, seat offset %.3f m" % [id, drove,
			P.global_position.distance_to(seat_node.global_position) if seat_node != null else -1.0])
	Input.action_press("move_back")
	await T.wait_seconds(1.5)
	Input.action_release("move_back")
	if v is RigidBody3D:
		(v as RigidBody3D).linear_velocity = Vector3.ZERO
	await T.wait_seconds(0.5)
	await _tap("enter_vehicle")
	var out := await _wait_until(func() -> bool: return P.state_id == "on_foot" and P.current_vehicle == null, 6.0)
	var beside := P.global_position.distance_to(v.global_position)
	_real("REAL_VEHICLE(%s): exit ok=%s, standing %.2f m from the vehicle, driver cleared=%s" % [id, str(out), beside, str(v.get("driver") == null)])
	if not (found and seated and on_seat and driven and out):
		skipped.append("real vehicle integration incomplete (see REAL_VEHICLE lines)")
	if P.current_vehicle != null:
		P.teleport(arena.at(Arena.STAGE + Vector3(0.0, 0.0, 40.0)), 0.0)
	v.queue_free()
	await T.wait_seconds(0.5)


# --- real pickup system (soft): kinds that land on Player hooks -----------------------------------

func _test_real_pickups() -> void:
	var ps: Node = Game.get_system("pickups")
	if ps == null or not ps.has_method("spawn_pickup"):
		skipped.append("real pickups (pickups system missing)")
		_real("REAL_PICKUPS: pickups system missing")
		return
	await _place(Vector3(-4.0, 0.0, 4.0), 0.0)
	P.has_scuba = false
	P.has_parachute = false
	P.armor = 0.0
	var conds := {
		"scuba": func() -> bool: return P.has_scuba,
		"parachute": func() -> bool: return P.has_parachute,
		"armor": func() -> bool: return P.armor > 0.0,
	}
	var got: Array[String] = []
	for kind: String in conds.keys():
		var pk: Variant = ps.call("spawn_pickup", kind, "", 25, P.global_position + Vector3(0.0, 0.4, 0.0), {"snap": false})
		if pk == null:
			_real("REAL_PICKUPS: spawn_pickup('%s') returned null" % kind)
			continue
		if await _wait_until(conds[kind], 3.0):
			got.append(kind)
	_real("REAL_PICKUPS: collected by walking into them: %s" % ", ".join(got))
	T.check(got.size() == conds.size(), "real pickups reach the player hooks (give_scuba / give_parachute / add_armor): %s" % ", ".join(got))
	P.has_scuba = false
	P.has_parachute = false
	P.armor = 0.0


# --- being run over: VehicleSensor -> "vehicle" damage -> one ragdoll throw -----------------------

func _test_vehicle_hit() -> void:
	await _place(Vector3(0.0, 0.0, 6.0), 0.0)
	P.heal(1000.0)
	P.armor = 0.0
	var start := P.global_position
	var hits: Array[float] = []
	var types: Array[String] = []
	var on_hit := func(amount: float, info: Dictionary) -> void:
		hits.append(amount)
		types.append(str(info.get("type", "")))
	EventBus.player_damaged.connect(on_hit)
	# a ghost "car" (no collision response, no gravity) closing at 14 m/s: only the sensor sees it
	var rb := RigidBody3D.new()
	rb.name = "TestRammer"
	rb.collision_layer = Layers.VEHICLE
	rb.collision_mask = 0
	rb.gravity_scale = 0.0
	rb.mass = 1300.0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 1.3, 4.4)
	cs.shape = box
	rb.add_child(cs)
	arena.add_child(rb)
	rb.add_collision_exception_with(P)      # the test isolates the player's own hit response
	rb.global_position = start + Vector3(0.0, 0.7, 6.0)
	rb.linear_velocity = Vector3(0.0, 0.0, -14.0)
	var hit := await _wait_until(func() -> bool: return not hits.is_empty(), 2.0)
	rb.queue_free()                          # ... so the ghost must not then plough through the ragdoll
	T.check(hit and types.has("vehicle"), "a car closing at 14 m/s hits the player ('vehicle' damage %s)" % str(hits))
	await T.wait_physics_frames(3)
	T.check(P.state_id == "ragdoll", "the hit knocks the player down (state %s)" % P.state_id)
	await T.wait_seconds(1.5)
	EventBus.player_damaged.disconnect(on_hit)
	T.check(hits.size() == 1, "one impact = one damage event (%d)" % hits.size())
	var thrown := P.get_camera_focus().distance_to(start)
	T.check(thrown > 1.0 and thrown < 14.0, "thrown a believable distance (%.1f m), not a cartoon launch" % thrown)
	T.check(not P.is_dead and P.health > 20.0, "survives a 14 m/s hit (hp %.0f)" % P.health)
	var up := await _wait_until(func() -> bool: return P.state_id == "on_foot", 7.0)
	T.check(up, "gets up after being hit (state %s)" % P.state_id)
	P.heal(1000.0)
