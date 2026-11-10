class_name CameraRig
extends Node3D
## Third-person orbit camera with SpringArm collision, shoulder aim, vehicle/aircraft chase, first person, scope and shake.

var cam: Camera3D
var arm: SpringArm3D
var pitch_pivot: Node3D
var yaw := 0.0
var pitch := -0.2
var first_person := false
var trauma := 0.0
var _recoil := 0.0
var _recover := 0.0
var _mouse_idle := 0.0
var _dist := 3.6
var _shoulder := 0.5
var _height := 1.55
var _fov := 70.0
var scoped := false
var photo_mode := false
var _photo_pos := Vector3.ZERO
var look_back := false
var underwater := false


func _ready() -> void:
	process_priority = 100
	pitch_pivot = Node3D.new()
	add_child(pitch_pivot)
	arm = SpringArm3D.new()
	arm.collision_mask = Game.L_WORLD
	arm.margin = 0.12
	var sp := SphereShape3D.new()
	sp.radius = 0.22
	arm.shape = sp
	arm.spring_length = _dist
	pitch_pivot.add_child(arm)
	cam = Camera3D.new()
	cam.fov = _fov
	cam.near = 0.08
	cam.far = 2200.0
	arm.add_child(cam)
	cam.current = true
	Game.cam = self


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (photo_mode or not Game.ui_blocked()):
		var sens: float = Game.settings.mouse_sens * (cam.fov / 70.0)
		yaw -= ev.relative.x * sens
		pitch -= ev.relative.y * sens * (-1.0 if Game.settings.invert_y else 1.0)
		pitch = clampf(pitch, -1.35, 1.2)
		_mouse_idle = 0.0


func shake(amount: float) -> void:
	trauma = minf(trauma + amount, 1.2)


func recoil(deg: float) -> void:
	_recoil += deg_to_rad(deg)
	_recover += deg_to_rad(deg) * 0.65


func aim_origin() -> Vector3:
	return cam.global_position


func aim_dir() -> Vector3:
	return -cam.global_transform.basis.z


func aim_point(max_dist: float = 300.0, exclude: Array = []) -> Vector3:
	var o := aim_origin()
	var d := aim_dir()
	var hit := Game.ray(o + d * 0.5, o + d * max_dist, Game.MASK_SHOT, exclude)
	if hit.is_empty():
		return o + d * max_dist
	return hit.position


func _process(delta: float) -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return
	_mouse_idle += delta
	if photo_mode:
		_photo(delta)
		return
	# gamepad look
	var lx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ly := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(lx) > 0.15 or absf(ly) > 0.15:
		yaw -= lx * delta * 2.6
		pitch = clampf(pitch - ly * delta * 1.8, -1.35, 1.2)
		_mouse_idle = 0.0
	if _recoil > 0.0001:
		var step := _recoil * minf(1.0, delta * 18.0)
		pitch = clampf(pitch + step, -1.35, 1.2)
		_recoil -= step
	elif _recover > 0.0001:
		var back := minf(_recover, delta * 0.35)
		pitch = clampf(pitch - back, -1.35, 1.2)
		_recover -= back
	var target: Vector3 = p.global_position
	var want_dist := 3.6
	var want_sh := 0.5
	var want_h := 1.55
	var want_fov: float = Game.settings.fov
	var fp := first_person
	scoped = false
	var v: Vehicle = p.vehicle if p.in_vehicle() else null
	if v != null and is_instance_valid(v):
		target = v.global_position
		var size := maxf(v._half.z * 2.0, 3.0)
		want_dist = 4.2 + size * 0.75
		want_h = 1.3 + v._half.y * 1.3
		want_sh = 0.0
		if v.is_air():
			want_dist = 9.0 + size * 0.7
			want_h = 2.6
		want_fov += clampf(absf(v.speed) / maxf(v.def.max_speed, 1.0), 0.0, 1.0) * 12.0
		look_back = Input.is_action_pressed("look_back") and not Game.ui_blocked()
		var aiming_in_car: bool = p.aiming
		if _mouse_idle > 1.6 and not aiming_in_car and v.linear_velocity.length() > 3.0:
			var fwd := -v.global_basis.z
			var vy := atan2(-fwd.x, -fwd.z)
			yaw = lerp_angle(yaw, vy, clampf(delta * 2.5, 0.0, 1.0))
			pitch = lerpf(pitch, -0.22 if not v.is_air() else -0.12 + asin(clampf(fwd.y, -1.0, 1.0)) * 0.6, clampf(delta * 2.0, 0.0, 1.0))
		if fp:
			target = v.seat_global(p.seat).origin + v.global_basis.y * 0.62
	else:
		look_back = false
		if p.is_swimming():
			want_h = 1.2
		elif p.crouching:
			want_h = 1.1
		if p.state == Player.St.CHUTE:
			want_dist = 6.5
			want_h = 2.0
		if p.aiming:
			var wd: WeaponDef = p.inv.def()
			want_dist = 1.9
			want_sh = 0.62
			want_fov = 52.0
			if wd.zoom_fov > 0.0:
				want_fov = wd.zoom_fov
				if wd.scoped:
					fp = true
					scoped = true
			elif p.inv.has_mod("scope"):
				want_fov = 36.0
		if p.state == Player.St.COVER:
			want_sh = 0.75 * p.cover_side
		if fp:
			target = p.global_position + Vector3(0, 1.62 * p.rig.height_scale - (0.5 if p.crouching else 0.0), 0)
	if fp:
		want_dist = 0.0
		want_sh = 0.0
		want_h = 0.0
	var k := clampf(delta * 10.0, 0.0, 1.0)
	_dist = lerpf(_dist, want_dist, k)
	_shoulder = lerpf(_shoulder, want_sh, k)
	_height = lerpf(_height, want_h, k)
	_fov = lerpf(_fov, want_fov, clampf(delta * 9.0, 0.0, 1.0))
	global_position = target + Vector3(0, _height, 0)
	rotation = Vector3(0, yaw + (PI if look_back else 0.0), 0)
	pitch_pivot.rotation = Vector3(pitch, 0, 0)
	arm.position = Vector3(_shoulder, 0, 0)
	arm.spring_length = _dist
	cam.fov = _fov
	# shake
	trauma = maxf(0.0, trauma - delta * 1.6)
	var s := trauma * trauma
	cam.rotation = Vector3(randf_range(-1, 1) * 0.05 * s, randf_range(-1, 1) * 0.05 * s, randf_range(-1, 1) * 0.04 * s)
	p.rig.visible = not (fp and v == null) or p.state == Player.St.RAGDOLL or p.state == Player.St.DEAD
	if fp and v != null:
		p.rig.visible = false
	# underwater presentation
	var uw := cam.global_position.y < Game.WATER_Y - 0.05 and City.terrain_height(cam.global_position.x, cam.global_position.z) < Game.WATER_Y
	if uw != underwater:
		underwater = uw
		Sfx.set_underwater(uw)
		if Game.daynight:
			Game.daynight.underwater = uw
		if Game.hud:
			Game.hud.set_underwater(uw)


func _photo(delta: float) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var mv := Vector3(Input.get_axis("move_left", "move_right"), Input.get_axis("crouch", "jump"), Input.get_axis("move_fwd", "move_back"))
	_photo_pos += b * mv * delta * (14.0 if Input.is_action_pressed("sprint") else 5.0)
	arm.spring_length = 0.0
	arm.position = Vector3.ZERO
	global_position = _photo_pos
	rotation = Vector3(0, yaw, 0)
	pitch_pivot.rotation = Vector3(pitch, 0, 0)
	cam.rotation = Vector3.ZERO


func set_photo(on: bool) -> void:
	photo_mode = on
	if on:
		_photo_pos = cam.global_position
	if Game.hud:
		Game.hud.visible = not on


func snap_behind(yaw_: float) -> void:
	yaw = yaw_
	pitch = -0.2
