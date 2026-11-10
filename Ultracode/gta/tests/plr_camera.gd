extends Node
## plr_camera - headless test of the gameplay camera rig (PlayerCamera, Game.camera_rig).
##
##   tools\godot.ps1 -Mode headless -Frames 2400 -TimeoutSec 240 `
##       -UserArgs '--test=plr_camera','--disable=traffic,peds,police','--test-timeout=200'
##
## Covers: registration, third / aim / first / vehicle / aircraft / scope-less photo mode switching,
## orbit distance in the open, collision against a wall, aim ray == camera view, aim point,
## look input (direct, mouse event, input lock, invert), FOV (settings, aim zoom, override,
## speed), trauma shake + Fx hook, recoil, look_back, first-person head hiding, smooth follow.

const Arena := preload("res://gta/tests/plr_arena.gd")

var P: Player = null
var C: PlayerCamera = null
var arena: Arena = null
var T: Node = null
var modes_seen: PackedStringArray = []


func _ready() -> void:
	T = TestHarness
	await _run()


func _run() -> void:
	P = Game.player as Player
	if not T.check(P != null, "Game.player is a Player"):
		T.finish(false, "no player")
		return
	C = Game.camera_rig as PlayerCamera
	if not T.check(C != null and C == P.camera, "Game.camera_rig is the player's PlayerCamera"):
		T.finish(false, "no camera rig")
		return
	arena = Arena.new()
	Game.main.add_child(arena)
	EventBus.camera_mode_changed.connect(func(m: String) -> void: modes_seen.append(m))
	await T.wait_physics_frames(3)
	await _test_orbit()
	await _test_look_input()
	await _test_collision()
	await _test_aim()
	await _test_first_person()
	await _test_fov_shake_recoil()
	await _test_vehicle_modes()
	await _test_photo()
	_release_all()
	T.log_line("camera modes seen: " + ", ".join(modes_seen))
	T.finish(true, "camera rig")


func _release_all() -> void:
	for a in ["move_forward", "sprint", "aim", "fire", "camera_toggle", "look_back", "jump", "crouch"]:
		Input.action_release(a)


func _tap(action: String) -> void:
	await get_tree().process_frame
	Input.action_press(action)
	await T.wait_frames(3)
	Input.action_release(action)
	await T.wait_frames(2)


func _place(local: Vector3, yaw: float = 0.0) -> void:
	_release_all()
	P.teleport(arena.at(local) + Vector3(0.0, 0.03, 0.0), yaw)
	await T.wait_seconds(0.8)


func _cam() -> Camera3D:
	return C.camera


func _pivot() -> Vector3:
	return P.global_position + Vector3(0.0, PlayerCamera.THIRD_HEIGHT, 0.0)


func _test_orbit() -> void:
	await _place(Arena.STAGE + Vector3(0.0, 0.0, 30.0), 0.0)
	T.check(C.mode == "third", "default mode is 'third' (%s)" % C.mode)
	T.check(_cam().current, "the rig's Camera3D is the current camera")
	T.check(get_viewport().get_camera_3d() == _cam(), "viewport renders through the rig camera")
	var d := _cam().global_position.distance_to(_pivot())
	var want := Vector2(PlayerCamera.THIRD_DISTANCE, PlayerCamera.THIRD_SIDE).length()
	T.check(absf(d - want) < 0.12, "orbit distance in the open %.2f m (want %.2f)" % [d, want])
	var behind := _cam().global_position.z - P.global_position.z
	T.check(behind > 3.0, "camera sits behind a player facing -Z (%.2f m)" % behind)
	var fwd := -_cam().global_basis.z
	T.check(fwd.z < -0.95, "camera looks along the player's facing (%.2f)" % fwd.z)
	T.check(absf(_cam().fov - float(Settings.get_value("fov"))) < 0.5, "FOV comes from Settings (%.1f)" % _cam().fov)
	# smooth follow while running
	Input.action_press("move_forward")
	var max_lag := 0.0
	for i in 90:
		await get_tree().process_frame
		max_lag = maxf(max_lag, _cam().global_position.distance_to(_pivot()))
	Input.action_release("move_forward")
	T.check(max_lag < want + 0.6, "camera follows a running player (max distance %.2f m)" % max_lag)
	await T.wait_seconds(0.5)


func _test_look_input() -> void:
	await _place(Arena.STAGE + Vector3(0.0, 0.0, 30.0), 0.0)
	var y0 := C.yaw
	var p0 := C.pitch
	C.apply_look(0.4, 0.2)
	T.check(absf(angle_difference(y0, C.yaw) - 0.4) < 0.001 and absf(C.pitch - p0 - 0.2) < 0.001, "apply_look rotates yaw / pitch")
	C.apply_look(0.0, 5.0)
	T.check(absf(C.pitch - PlayerCamera.PITCH_MAX) < 0.001, "pitch is clamped upwards (%.2f)" % C.pitch)
	C.apply_look(0.0, -9.0)
	T.check(absf(C.pitch - PlayerCamera.PITCH_MIN) < 0.001, "pitch is clamped downwards (%.2f)" % C.pitch)
	C.snap_to(0.0)
	await T.wait_frames(3)
	# real mouse events (the rig only listens while the mouse is captured; tests switch that off)
	C.require_capture = false
	var sens := float(Settings.get_value("mouse_sensitivity"))
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(100.0, 0.0)
	mm.screen_relative = mm.relative
	Input.parse_input_event(mm)
	await T.wait_frames(3)
	T.check(absf(C.yaw - (-100.0 * sens)) < 0.02, "mouse motion turns the view by the Settings sensitivity (yaw %.3f)" % C.yaw)
	var yaw_before := C.yaw
	Game.lock_input()
	var mm2 := InputEventMouseMotion.new()
	mm2.relative = Vector2(150.0, 40.0)
	mm2.screen_relative = mm2.relative
	Input.parse_input_event(mm2)
	await T.wait_frames(3)
	Game.unlock_input()
	T.check(absf(C.yaw - yaw_before) < 0.0001, "mouse look is ignored while Game.is_input_locked()")
	var was_inv := bool(Settings.get_value("invert_y"))
	Settings.set_value("invert_y", true, false)
	var pitch0 := C.pitch
	var mm3 := InputEventMouseMotion.new()
	mm3.relative = Vector2(0.0, 50.0)
	mm3.screen_relative = mm3.relative
	Input.parse_input_event(mm3)
	await T.wait_frames(3)
	T.check(C.pitch > pitch0 + 0.01, "invert_y flips the vertical look")
	Settings.set_value("invert_y", was_inv, false)
	C.require_capture = true
	C.snap_to(0.0)
	await T.wait_frames(3)


func _test_collision() -> void:
	await _place(Arena.WALL_SPOT, 0.0)
	await T.wait_seconds(0.6)
	var wall_z := arena.at(Arena.WALL_SPOT).z + Arena.WALL_FACE_Z
	var cz := _cam().global_position.z
	T.check(cz < wall_z - 0.1, "camera stays in front of the wall behind the player (cam z %.2f, wall face %.2f)" % [cz - arena.at(Arena.WALL_SPOT).z, Arena.WALL_FACE_Z])
	var d := _cam().global_position.distance_to(_pivot())
	T.check(d < PlayerCamera.THIRD_DISTANCE * 0.55, "the boom is shortened by the collision (%.2f m)" % d)
	# line of sight from the pivot to the camera is free
	var q := PhysicsRayQueryParameters3D.create(_pivot(), _cam().global_position, Layers.CAMERA_MASK)
	var hit := P.get_world_3d().direct_space_state.intersect_ray(q)
	T.check(hit.is_empty(), "nothing between the character and the camera")
	# turn the camera away from the wall: the boom extends again
	C.apply_look(PI, 0.0)
	await T.wait_seconds(1.0)
	var d2 := _cam().global_position.distance_to(_pivot())
	var full := Vector2(PlayerCamera.THIRD_DISTANCE, PlayerCamera.THIRD_SIDE).length()
	T.check(d2 > full - 0.15, "the boom extends again when the view is clear (%.2f m of %.2f)" % [d2, full])
	C.snap_to(0.0)


func _test_aim() -> void:
	var inv := arena.install_mock_inventory(P)
	await _place(Arena.TARGET_SPOT, 0.0)
	C.pitch = 0.0
	await T.wait_frames(5)
	# aim ray == what the camera looks at
	var ray: Dictionary = P.get_aim_ray()
	var o: Vector3 = ray["origin"]
	var d: Vector3 = ray["direction"]
	var cam_fwd := -_cam().global_basis.z
	T.check(d.dot(cam_fwd) > 0.9999, "aim ray direction == camera forward (dot %.5f)" % d.dot(cam_fwd))
	var centre := get_viewport().get_visible_rect().size * 0.5
	var proj := _cam().project_ray_normal(centre)
	T.check(d.dot(proj) > 0.9998, "aim ray goes through the screen centre (dot %.5f)" % d.dot(proj))
	var off := (o - _cam().global_position).cross(cam_fwd).length()
	T.check(off < 0.01, "aim ray origin lies on the camera axis (%.4f m off)" % off)
	T.check((o - _cam().global_position).dot(cam_fwd) > 2.5, "aim ray starts at the player, not behind it")
	var point := P.get_aim_point()
	var face_z := arena.at(Arena.TARGET_SPOT).z + Arena.TARGET_FACE_Z
	T.check(absf(point.z - face_z) < 0.05, "get_aim_point hits the target in front (z %.2f, face %.2f)" % [point.z - arena.at(Arena.TARGET_SPOT).z, Arena.TARGET_FACE_Z])
	# aim mode
	var fov0 := _cam().fov
	Input.action_press("aim")
	await T.wait_seconds(0.7)
	T.check(P.is_aiming and C.mode == "aim", "holding aim switches to the over-the-shoulder mode (%s)" % C.mode)
	T.check(inv.count("aim_on") == 1, "aim is forwarded to inventory.set_aiming(true)")
	T.check(absf(_cam().fov - inv.aim_fov) < 2.0, "aim FOV follows inventory.get_aim_fov() (%.1f, was %.1f)" % [_cam().fov, fov0])
	var right := _cam().global_basis.x
	var side := (_cam().global_position - P.global_position).dot(right)
	T.check(side > 0.3, "camera sits over the right shoulder while aiming (%.2f m)" % side)
	var d_aim := _cam().global_position.distance_to(_pivot())
	T.check(d_aim < 2.0, "camera moves in while aiming (%.2f m)" % d_aim)
	var point2 := P.get_aim_point()
	T.check(absf(point2.z - face_z) < 0.05, "crosshair point still on the target while aiming")
	T.check(absf(angle_difference(P.rotation.y, C.yaw)) < 0.1, "the body faces where the camera aims")
	# aiming up moves the aim point off the target
	C.apply_look(0.0, 0.6)
	await T.wait_frames(4)
	var point3 := P.get_aim_point()
	T.check(point3.y > point2.y + 3.0, "aim point follows the camera pitch")
	T.check(P.animator.aim_pitch > 0.4 and P.animator.aim_weight > 0.9, "aim pitch / weight reach the animator (%.2f / %.2f)" % [P.animator.aim_pitch, P.animator.aim_weight])
	Input.action_release("aim")
	await T.wait_seconds(0.6)
	T.check(not P.is_aiming and C.mode == "third" and inv.count("aim_off") >= 1, "releasing aim returns to 'third'")
	C.snap_to(0.0)


func _test_first_person() -> void:
	await _place(Arena.STAGE + Vector3(0.0, 0.0, 30.0), 0.0)
	await _tap("camera_toggle")
	await T.wait_seconds(0.4)
	T.check(C.mode == "first" and C.first_person, "camera_toggle switches to first person (%s)" % C.mode)
	T.check(P.is_head_hidden(), "the head is hidden in first person")
	var eye := P.global_position + Vector3(0.0, 1.62, 0.0)
	var de := _cam().global_position.distance_to(eye)
	T.check(de < 0.3, "camera sits at the eyes (%.2f m from the eye point)" % de)
	C.apply_look(0.9, 0.0)
	await T.wait_seconds(0.5)
	T.check(absf(angle_difference(P.rotation.y, C.yaw)) < 0.12, "in first person the body turns with the view")
	var ray: Dictionary = P.get_aim_ray()
	T.check((ray["direction"] as Vector3).dot(-_cam().global_basis.z) > 0.9999, "aim ray matches the view in first person")
	await _tap("camera_toggle")
	await T.wait_seconds(0.4)
	T.check(C.mode == "third" and not P.is_head_hidden(), "camera_toggle returns to third person, head visible again")
	C.snap_to(0.0)


func _test_fov_shake_recoil() -> void:
	await _place(Arena.STAGE + Vector3(0.0, 0.0, 30.0), 0.0)
	var base := float(Settings.get_value("fov"))
	C.set_fov_override(35.0, 1.0)
	await T.wait_seconds(0.8)
	T.check(absf(_cam().fov - 35.0) < 1.0, "set_fov_override(35, 1) (%.1f)" % _cam().fov)
	C.set_fov_override(35.0, 0.0)
	await T.wait_seconds(0.8)
	T.check(absf(_cam().fov - base) < 1.0, "FOV returns when the override weight is 0 (%.1f)" % _cam().fov)
	# trauma
	C.trauma = 0.0
	C.add_trauma(0.6)
	T.check(absf(C.trauma - 0.6) < 0.001, "add_trauma accumulates")
	var max_dev := 0.0
	var aim_stable := true
	for i in 12:
		await get_tree().process_frame
		var aim_dir := C.get_aim_direction()
		max_dev = maxf(max_dev, (-_cam().global_basis.z).angle_to(aim_dir))
		if (P.get_aim_ray()["direction"] as Vector3).dot(aim_dir) < 0.99999 or absf(aim_dir.y - sin(C.pitch)) > 0.001:
			aim_stable = false
	T.check(max_dev > 0.004, "trauma shakes the rendered camera (%.2f deg)" % rad_to_deg(max_dev))
	T.check(aim_stable, "the shake never moves the aim ray")
	await T.wait_seconds(1.0)
	T.check(C.trauma <= 0.001, "trauma decays")
	Fx.shake_camera(0.5, P.global_position, 30.0)
	T.check(C.trauma > 0.05, "Fx.shake_camera reaches the rig through camera_shake_requested (%.2f)" % C.trauma)
	await T.wait_seconds(0.6)
	# recoil
	var pitch_before := asin(clampf(C.get_aim_direction().y, -1.0, 1.0))
	P.add_recoil(4.0, 0.0)
	await T.wait_frames(2)
	var pitch_kick := asin(clampf(C.get_aim_direction().y, -1.0, 1.0))
	T.check(pitch_kick > pitch_before + deg_to_rad(2.0), "add_recoil kicks the view up (%.1f deg)" % rad_to_deg(pitch_kick - pitch_before))
	await T.wait_seconds(1.0)
	var pitch_after := asin(clampf(C.get_aim_direction().y, -1.0, 1.0))
	T.check(absf(pitch_after - pitch_before) < deg_to_rad(0.3), "recoil recovers")
	# sprint widens the view a little
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await T.wait_seconds(1.2)
	T.check(_cam().fov > base + 2.0, "sprinting widens the FOV (%.1f)" % _cam().fov)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await T.wait_seconds(0.6)


func _test_vehicle_modes() -> void:
	await _place(Arena.STAGE + Vector3(0.0, 0.0, 30.0), 0.0)
	var car := arena.spawn_mock_vehicle(Arena.STAGE + Vector3(4.0, 0.0, 30.0), 0.0, "car")
	await T.wait_seconds(0.5)
	P.enter_vehicle(car, 0, true)
	await T.wait_seconds(1.6)
	T.check(P.current_vehicle == car and C.mode == "vehicle", "sitting in a car uses the 'vehicle' chase mode (%s)" % C.mode)
	var look_at := car.global_position + Vector3(0.0, float(car.camera_params["look_height"]), 0.0)
	var dist := _cam().global_position.distance_to(look_at)
	T.check(absf(dist - float(car.camera_params["distance"])) < 0.5, "chase distance from vehicle.get_camera_params() (%.2f m)" % dist)
	T.check(absf(_cam().fov - float(car.camera_params["fov"])) < 1.5, "chase FOV from vehicle.get_camera_params() (%.1f)" % _cam().fov)
	# speed widens the FOV, the camera follows the vehicle
	car.linear_velocity = Vector3(0.0, 0.0, -30.0)
	await T.wait_seconds(0.6)
	T.check(_cam().fov > float(car.camera_params["fov"]) + 4.0, "speed based FOV (%.1f at %.0f m/s)" % [_cam().fov, car.linear_velocity.length()])
	var lag := _cam().global_position.distance_to(car.global_position + Vector3(0.0, 1.0, 0.0))
	T.check(lag < float(car.camera_params["distance"]) + 2.5, "chase camera keeps up with a fast vehicle (%.2f m)" % lag)
	car.linear_velocity = Vector3.ZERO
	await T.wait_seconds(0.5)
	# look around with the mouse + look back
	var yaw0 := C.yaw
	C.apply_look(0.8, 0.0)
	await T.wait_frames(3)
	T.check(absf(angle_difference(yaw0, C.yaw) - 0.8) < 0.05, "mouse look-around in the vehicle camera")
	C.apply_look(-0.8, 0.0)
	await T.wait_frames(3)
	var fwd0 := -_cam().global_basis.z
	Input.action_press("look_back")
	await T.wait_frames(4)
	var fwd1 := -_cam().global_basis.z
	Input.action_release("look_back")
	T.check(Vector2(fwd0.x, fwd0.z).normalized().dot(Vector2(fwd1.x, fwd1.z).normalized()) < -0.9, "look_back looks behind the vehicle")
	await T.wait_frames(4)
	# first person inside the vehicle
	await _tap("camera_toggle")
	await T.wait_seconds(0.4)
	T.check(C.mode == "first", "first person works in a vehicle (%s)" % C.mode)
	var head := P.global_position + Vector3(0.0, 0.62, 0.0)
	T.check(_cam().global_position.distance_to(head) < 0.45, "first-person camera is at the driver's head (%.2f m)" % _cam().global_position.distance_to(head))
	await _tap("camera_toggle")
	await T.wait_seconds(0.3)
	P.teleport(arena.at(Arena.STAGE + Vector3(0.0, 0.0, 30.0)), 0.0)
	await T.wait_seconds(0.4)
	T.check(P.current_vehicle == null and C.mode == "third", "leaving the vehicle returns to 'third'")
	car.queue_free()
	# aircraft variant
	var heli := arena.spawn_mock_vehicle(Arena.STAGE + Vector3(4.0, 0.0, 36.0), 0.0, "heli")
	await T.wait_seconds(0.4)
	P.enter_vehicle(heli, 0, true)
	await T.wait_seconds(1.8)
	T.check(C.mode == "aircraft", "helicopters / planes use the 'aircraft' mode (%s)" % C.mode)
	var look2 := heli.global_position + Vector3(0.0, float(heli.camera_params["look_height"]), 0.0)
	var dist2 := _cam().global_position.distance_to(look2)
	T.check(dist2 > float(heli.camera_params["distance"]) * 1.3, "aircraft camera keeps more distance (%.2f m)" % dist2)
	P.teleport(arena.at(Arena.STAGE + Vector3(0.0, 0.0, 30.0)), 0.0)
	await T.wait_seconds(0.4)
	heli.queue_free()


func _test_photo() -> void:
	await _place(Arena.STAGE + Vector3(0.0, 0.0, 30.0), 0.0)
	var start := _cam().global_position
	C.set_mode("photo")
	await T.wait_frames(4)
	T.check(C.mode == "photo", "set_mode('photo') forces the free camera")
	Game.lock_input()                       # what the photo-mode screen does while it is open
	var body := P.global_position
	Input.action_press("move_forward")
	await T.wait_seconds(0.6)
	Input.action_release("move_forward")
	T.check(_cam().global_position.distance_to(start) > 1.5, "photo camera flies with the move keys (%.2f m)" % _cam().global_position.distance_to(start))
	T.check(P.global_position.distance_to(body) < 0.01, "the character stays put while the photo camera flies")
	var y0 := C.yaw
	C.apply_look(0.5, 0.0)
	T.check(absf(angle_difference(y0, C.yaw) - 0.5) < 0.001, "photo camera can look around while the input is locked")
	Game.unlock_input()
	C.set_mode("")
	await T.wait_seconds(0.5)
	T.check(C.mode == "third", "set_mode('') returns to automatic mode selection")
	C.set_mode("nonsense")
	await T.wait_frames(3)
	T.check(C.mode == "third", "unknown modes are ignored")
	var missing: PackedStringArray = []
	for m in ["third", "aim", "first", "vehicle", "aircraft", "scope", "photo"]:
		if not PlayerCamera.MODES.has(m):
			missing.append(m)
	T.check(missing.is_empty(), "all contract modes exist (third, aim, first, vehicle, aircraft, scope, photo)")
