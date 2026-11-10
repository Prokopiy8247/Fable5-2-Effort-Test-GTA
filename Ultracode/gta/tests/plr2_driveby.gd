extends Node
## plr2_driveby - headless test of drive-by combat with the REAL sedan, WeaponInventory and Combat:
## the pistol from the driver's seat hits a target on the left (free-aim camera, shots leave from the
## window, one-handed seated aim pose, steering keeps working while aiming), a target on the right is
## outside the driver's arc (no shot), a fire bottle is dropped out of the window without aiming and
## lobbed while aiming, motorcycle arcs (forward and sides).
##
##   tools\godot.ps1 -Mode headless -Frames 3600 -TimeoutSec 300 `
##       -UserArgs '--test=plr2_driveby','--disable=traffic,peds,police','--test-timeout=240'

const Arena := preload("res://gta/tests/plr_arena.gd")
const CAR_SPOT := Vector3(0.0, 0.0, 50.0)


class Target extends CharacterBody3D:
	var is_dead: bool = false
	var hits: Array = []

	func _init() -> void:
		add_to_group("npc")
		collision_layer = Layers.NPC
		collision_mask = 0
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.8
		cs.shape = cap
		cs.position = Vector3(0.0, 0.9, 0.0)
		add_child(cs)

	func apply_damage(info: Dictionary) -> void:
		hits.append(info)

	func get_target_position() -> Vector3:
		return global_position + Vector3(0.0, 1.2, 0.0)


var P: Player = null
var arena: Arena = null
var T: Node = null
var inv: Node = null
var car: Node3D = null
var shots: Array = []            # [origin, direction]
var thrown: Array = []           # projectiles


func _ready() -> void:
	T = TestHarness
	await _run()


func _run() -> void:
	P = Game.player as Player
	if not T.check(P != null, "Game.player is a Player"):
		T.finish(false, "no player")
		return
	inv = P.inventory
	if not T.check(inv != null and inv.has_method("equip") and Game.get_system("vehicles") != null, "real inventory + vehicles present"):
		T.finish(false, "needs the weapons and vehicle modules")
		return
	arena = Arena.new()
	Game.main.add_child(arena)
	EventBus.weapon_fired.connect(_on_fired)
	if inv.has_signal("thrown"):
		inv.connect("thrown", func(_id: String, pr: Node3D) -> void: thrown.append(pr))
	car = Game.spawn_vehicle("sedan", Transform3D(Basis.IDENTITY, arena.at(CAR_SPOT) + Vector3(0.0, 0.6, 0.0)), {"owner_tag": "parked"})
	if not T.check(car != null, "spawn a sedan"):
		T.finish(false, "no sedan")
		return
	await T.wait_physics_frames(60)
	P.teleport(arena.at(CAR_SPOT + Vector3(-3.0, 0.0, 0.0)), 0.0)
	await T.wait_physics_frames(10)
	P.enter_vehicle(car, 0, true)
	await T.wait_physics_frames(20)
	T.check(P.current_vehicle == car and P.state_id == "vehicle", "seated in the sedan (driver)")
	await _test_left_target()
	await _test_steer_while_aiming()
	await _test_right_side_blocked()
	await _test_throwables()
	await _test_bike_arcs()
	_release_all()
	T.finish(true, "drive-by")


# --- helpers ---------------------------------------------------------------------------------------

func _on_fired(_id: String, shooter: Node, origin: Vector3, dir: Vector3) -> void:
	if shooter == P:
		shots.append([origin, dir])


func _release_all() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back", "aim", "fire", "enter_vehicle", "handbrake"]:
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


func _spawn_target(world: Vector3) -> Target:
	var t := Target.new()
	t.name = "DriveByTarget"
	arena.add_child(t)
	t.global_position = world
	return t


## Turn the vehicle camera until the crosshair ray points at `world_point`.
func _aim_camera_at(world_point: Vector3) -> void:
	for i in 6:
		await T.wait_frames(3)
		var o := P.camera.get_aim_origin()
		var d := P.camera.get_aim_direction()
		var want := (world_point - o).normalized()
		var dyaw := angle_difference(atan2(-d.x, -d.z), atan2(-want.x, -want.z))
		var dpitch := asin(clampf(want.y, -1.0, 1.0)) - asin(clampf(d.y, -1.0, 1.0))
		P.camera.apply_look(dyaw, dpitch)
	await T.wait_frames(3)


func _fire_taps(n: int) -> void:
	for i in n:
		Input.action_press("fire")
		await T.wait_physics_frames(3)
		Input.action_release("fire")
		await T.wait_seconds(0.35)


# --- tests ----------------------------------------------------------------------------------------

func _test_left_target() -> void:
	inv.call("equip", "pistol")
	if inv.has_method("refill_all"):
		inv.call("refill_all")
	await T.wait_physics_frames(30)
	T.check(str(inv.get("current_id")) == "pistol", "the pistol can be drawn in the driver's seat (%s)" % str(inv.get("current_id")))
	var left := -car.global_basis.x
	var target := _spawn_target(car.global_position + left * 8.0 - Vector3(0.0, car.global_position.y - arena.at(Vector3.ZERO).y, 0.0))
	Input.action_press("aim")
	await T.wait_seconds(0.8)
	T.check(P.is_aiming and P.camera.is_drive_by_aiming(), "aim in the seat = drive-by free aim (aiming %s, camera %s)" % [str(P.is_aiming), str(P.camera.is_drive_by_aiming())])
	await _aim_camera_at(target.get_target_position())
	await T.wait_physics_frames(4)
	var st := P.states["vehicle"] as PlayerStateVehicle
	T.check(st.drive_by_in_arc, "a target on the left is inside the driver's arc")
	T.check(P.animator.state == "seated_car" and P.animator.aim_weight > 0.9 and P.animator.aim_yaw > 1.2,
			"the animator aims one-handed out of the left window (state %s, weight %.1f, yaw %.0f deg)" % [P.animator.state, P.animator.aim_weight, rad_to_deg(P.animator.aim_yaw)])
	shots.clear()
	await _fire_taps(3)
	T.check(shots.size() >= 3, "three trigger pulls = three shots (%d)" % shots.size())
	T.check(target.hits.size() >= 2, "the pistol from the driver's seat hits the target on the left (%d of %d)" % [target.hits.size(), shots.size()])
	if not shots.is_empty():
		var o: Vector3 = shots[0][0]
		var local := car.global_transform.affine_inverse() * o
		T.check(local.x < -0.6, "shots leave from the driver's window (local x %.2f, y %.2f)" % [local.x, local.y])
	var spread := float(inv.call("get_current_spread")) if inv.has_method("get_current_spread") else 0.0
	T.check(spread > 0.0, "drive-by spread is reported for the crosshair (%.2f deg)" % spread)
	target.queue_free()


func _test_steer_while_aiming() -> void:
	# still aiming from the previous test
	Input.action_press("move_right")
	await T.wait_physics_frames(6)
	var steer := float(car.get("in_steer"))
	T.check(P.is_aiming and steer > 0.3, "steering keeps working while aiming (in_steer %.2f)" % steer)
	Input.action_release("move_right")
	await T.wait_physics_frames(4)


func _test_right_side_blocked() -> void:
	var right := car.global_basis.x
	var target := _spawn_target(car.global_position + right * 8.0 - Vector3(0.0, car.global_position.y - arena.at(Vector3.ZERO).y, 0.0))
	await _aim_camera_at(target.get_target_position())
	await T.wait_physics_frames(4)
	var st := P.states["vehicle"] as PlayerStateVehicle
	T.check(not st.drive_by_in_arc, "a target on the right is outside the driver's arc")
	shots.clear()
	await _fire_taps(2)
	T.check(shots.is_empty() and target.hits.is_empty(), "no shot leaves across the passenger seat (%d shots)" % shots.size())
	Input.action_release("aim")
	await T.wait_seconds(0.4)
	T.check(not P.is_aiming and not P.camera.is_drive_by_aiming(), "releasing aim returns to the chase camera")
	target.queue_free()


func _test_throwables() -> void:
	if not bool(inv.call("give_weapon", "molotov", 3)) and not bool(inv.call("has_weapon", "molotov")):
		T.check(false, "molotov available")
		return
	inv.call("equip", "molotov")
	await T.wait_physics_frames(30)
	T.check(str(inv.get("current_id")) == "molotov", "a fire bottle can be held in the seat (%s)" % str(inv.get("current_id")))
	# drop: fire without aiming
	thrown.clear()
	await _fire_taps(1)
	await _until(func() -> bool: return not thrown.is_empty(), 0.6)
	if T.check(not thrown.is_empty(), "fire without aiming drops the fire bottle"):
		var pr := thrown[0] as Node3D
		var p0 := pr.global_position
		var local0 := car.global_transform.affine_inverse() * p0
		var lowest := p0.y
		for i in 6:
			await get_tree().physics_frame
			if is_instance_valid(pr):
				lowest = minf(lowest, pr.global_position.y)
		var floor_y := arena.at(Vector3.ZERO).y
		var broke: bool = not is_instance_valid(pr) or pr.get("exploded") == true
		T.check(local0.x < -0.5 and (lowest < p0.y - 0.05 or broke) and lowest < floor_y + 1.2,
				"... out of the window, down onto the road beside the car (spawn local x %.2f y %.2f, lowest %.2f m above the road, broke %s)" % [
				local0.x, local0.y, lowest - floor_y, str(broke)])
		if is_instance_valid(pr):
			pr.queue_free()
	await T.wait_seconds(1.2)
	# lob: aim at a point 12 m to the left and fire
	thrown.clear()
	Input.action_press("aim")
	await T.wait_seconds(0.6)
	var left := -car.global_basis.x
	await _aim_camera_at(car.global_position + left * 12.0 + Vector3(0.0, 3.5, 0.0))
	await _fire_taps(1)
	await _until(func() -> bool: return not thrown.is_empty(), 0.6)
	if T.check(not thrown.is_empty(), "aim + fire lobs the fire bottle"):
		var pr2 := thrown[0] as Node3D
		var q0 := pr2.global_position
		await T.wait_physics_frames(3)
		var mv := pr2.global_position - q0 if is_instance_valid(pr2) else Vector3.ZERO
		var lateral := mv.dot(left)
		T.check(lateral > 0.3 and mv.y > 0.0, "... towards the crosshair, upwards (%.2f m left, dy %.2f)" % [lateral, mv.y])
		if is_instance_valid(pr2):
			pr2.queue_free()
	Input.action_release("aim")
	inv.call("equip", "pistol")
	await T.wait_seconds(0.5)


func _test_bike_arcs() -> void:
	var bike := Game.spawn_vehicle("motorcycle", Transform3D(Basis.IDENTITY, arena.at(CAR_SPOT + Vector3(12.0, 0.0, 0.0)) + Vector3(0.0, 0.5, 0.0)), {"owner_tag": "parked"})
	if bike == null:
		T.log_line("SKIP bike arcs: no motorcycle")
		return
	await T.wait_physics_frames(5)
	var ix := P.vehicle_ix
	var fwd := -bike.global_basis.z
	var side := bike.global_basis.x
	T.check(ix.in_arc(bike, 0, fwd) and ix.in_arc(bike, 0, side) and ix.in_arc(bike, 0, -side) and not ix.in_arc(bike, 0, -fwd),
			"motorcycle riders fire forward and to both sides, not backwards")
	bike.queue_free()
