extends Node
## Windowed screenshots of the two-wheelers and boats in the real world (short run).
##   tools\godot.ps1 -Mode window -Frames 600 -TimeoutSec 120 -UserArgs '--test=bkb_shots','--test-timeout=100','--disable=traffic,peds,police,emergency,wildlife,props'
## -> qa/screenshots/bkb_moto_lean.png (player on the motorcycle leaning into a right turn),
##    bkb_bicycle_ride.png (pedalling rider, side view), bkb_boat_planing.png (speedboat on the
##    plane with its wake), bkb_marina.png (moored boats). Headless: no images, checks only.

var _cam: Camera3D = null
var _only: PackedStringArray = PackedStringArray()   ## --bkb_only=moto,bicycle,marina,boat (default: all)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--bkb_only="):
			_only = a.substr(11).split(",", false)
	Game.invulnerable = true
	WorldClock.set_hour(10.5)
	if Weather.has_method("set_weather"):
		Weather.set_weather("clear", 0.0)
	_cam = Camera3D.new()
	_cam.name = "BkbShotCam"
	_cam.fov = 60.0
	_cam.far = 2000.0
	add_child(_cam)
	await TestHarness.wait_frames(5)
	await _run()


func _run() -> void:
	var pl := Game.player
	var vm := Game.get_system("vehicles")
	if pl == null or vm == null:
		TestHarness.check(false, "player and vehicles present")
		TestHarness.finish(false)
		return
	vm.set("detail_override", 0)
	TestHarness.log_line("shots start at frame %d" % Engine.get_frames_drawn())

	# --- motorcycle: right turn on the runway, front-quarter view
	var rw := Game.get_location("airport_runway_start")
	var start := rw.origin + Vector3.UP * 0.05
	var moto: Bike = null
	if _want("moto"):
		moto = Game.spawn_vehicle("motorcycle", Transform3D(rw.basis, start), {"color": Color("#D8342C")}) as Bike
	if _want("moto") and TestHarness.check(moto != null, "motorcycle spawned on the runway"):
		pl.call("enter_vehicle", moto, 0, true)
		await TestHarness.wait_physics_frames(3)
		Input.action_press("move_forward")
		await _wait_until(func() -> bool: return moto.get_forward_speed() > 14.0, 4.0)
		Input.action_press("move_right")
		await TestHarness.wait_seconds(0.75)
		var gt := moto.global_transform
		var f := -gt.basis.z
		f.y = 0.0
		f = f.normalized()
		var r := f.cross(Vector3.UP)
		_aim(gt.origin + f * 2.2 - r * 1.9 + Vector3.UP * 1.05, gt.origin + Vector3.UP * 0.7 - f * 1.5)
		await TestHarness.shot("bkb_moto_lean")
		TestHarness.log_line("moto lean %.1f deg at %.1f m/s" % [moto.get_lean_degrees(), moto.get_forward_speed()])
		TestHarness.check(absf(moto.get_lean_degrees()) > 15.0, "motorcycle visibly leaned (%.1f deg)" % moto.get_lean_degrees())
		Input.action_release("move_right")
		Input.action_release("move_forward")
		pl.call("exit_vehicle")
		await TestHarness.wait_physics_frames(2)
		_cam.current = false

	# --- bicycle: side view of the rider pedalling
	var bstart := rw.origin + rw.basis.x * 12.0 + Vector3.UP * 0.05
	var bici: Bike = null
	if _want("bicycle"):
		bici = Game.spawn_vehicle("bicycle", Transform3D(rw.basis, bstart), {"color": Color("#2F9E5C")}) as Bike
	if _want("bicycle") and TestHarness.check(bici != null, "bicycle spawned"):
		pl.call("enter_vehicle", bici, 0, true)
		await TestHarness.wait_physics_frames(3)
		Input.action_press("move_forward")
		await TestHarness.wait_seconds(2.2)
		var gt2 := bici.global_transform
		var f2 := -gt2.basis.z
		f2.y = 0.0
		f2 = f2.normalized()
		var r2 := f2.cross(Vector3.UP)
		_aim(gt2.origin - r2 * 3.6 + f2 * 1.6 + Vector3.UP * 1.1, gt2.origin + Vector3.UP * 0.75 + f2 * 0.6)
		await TestHarness.shot("bkb_bicycle_ride")
		Input.action_release("move_forward")
		pl.call("exit_vehicle")
		await TestHarness.wait_physics_frames(2)
		_cam.current = false

	# --- marina: the moored boats
	var bs := Game.get_location("boat_spawn")
	if _want("marina"):
		_aim(bs.origin + Vector3(14.0, 7.0, 16.0), bs.origin + Vector3(-6.0, 0.0, -2.0))
		await TestHarness.wait_frames(2)
		await TestHarness.shot("bkb_marina")
		_cam.current = false

	# --- speedboat on the plane with its wake
	var boat: Boat = null
	var moor: Node = Game.get_entities_root().get_node_or_null("BoatMoorings")
	if moor != null:
		boat = moor.call("get_slip_vehicle", 0) as Boat
	if boat == null:
		boat = Game.spawn_vehicle("speedboat", bs, {}) as Boat
	if _want("boat") and TestHarness.check(boat != null, "speedboat available"):
		TestHarness.log_line("boat stage at frame %d" % Engine.get_frames_drawn())
		pl.call("enter_vehicle", boat, 0, true)
		await TestHarness.wait_physics_frames(3)
		Input.action_press("move_forward")
		await _wait_until(func() -> bool: return boat.get_forward_speed() > 15.0, 9.0)
		TestHarness.log_line("boat at %.1f m/s at frame %d" % [boat.get_forward_speed(), Engine.get_frames_drawn()])
		Input.action_press("move_left")
		await TestHarness.wait_seconds(0.5)
		var gt3 := boat.global_transform
		var f3 := -gt3.basis.z
		f3.y = 0.0
		f3 = f3.normalized()
		var r3 := f3.cross(Vector3.UP)
		_aim(gt3.origin - f3 * 15.0 + r3 * 11.0 + Vector3.UP * 6.5, gt3.origin + f3 * 1.5)
		await TestHarness.shot("bkb_boat_planing")
		TestHarness.log_line("boat %.1f m/s trim %.1f bank %.1f wakes %d" % [boat.get_forward_speed(), boat.trim_deg, boat.bank_deg, boat._wake_handles.size()])
		TestHarness.check(boat.get_forward_speed() > 12.0, "speedboat planing for the shot (%.1f m/s)" % boat.get_forward_speed())
		Input.action_release("move_left")
		Input.action_release("move_forward")
		pl.call("exit_vehicle")
		await TestHarness.wait_physics_frames(2)
	TestHarness.finish()


func _aim(from: Vector3, to: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(to, Vector3.UP)
	_cam.make_current()


func _wait_until(cond: Callable, max_seconds: float) -> void:
	var t := 0.0
	while t < max_seconds and not bool(cond.call()):
		await get_tree().physics_frame
		t += 1.0 / 60.0
