extends Node3D
## Third-person / first-person / vehicle chase / scope camera with collision, recoil kick and shake.

const Defs := preload("res://gta/code/core/defs.gd")

var camera: Camera3D
var arm: SpringArm3D
var yaw := 0.0
var pitch := -0.15
var first_person := false
var trauma := 0.0
var scoped := false
var sens := 0.0026
var _idle_t := 0.0
var _kick := 0.0
var _dist := 3.6
var _fov := 70.0
var _excluded = null
var photo := false
var photo_pos := Vector3.ZERO


func _ready() -> void:
	arm = SpringArm3D.new()
	arm.collision_mask = G.L_WORLD
	arm.margin = 0.25
	var sp = SphereShape3D.new()
	sp.radius = 0.22
	arm.shape = sp
	add_child(arm)
	camera = Camera3D.new()
	camera.far = 1600.0
	camera.near = 0.08
	camera.fov = 70.0
	arm.add_child(camera)
	camera.make_current()
	var al = AudioListener3D.new()
	camera.add_child(al)
	al.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	process_priority = 10


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s = sens * (camera.fov / 70.0)
		yaw -= ev.relative.x * s
		pitch = clamp(pitch - ev.relative.y * s, -1.35, 1.25)
		_idle_t = 0.0


func kick(amount: float) -> void:
	_kick += amount * 0.006
	pitch = clamp(pitch + amount * 0.0045, -1.35, 1.25)
	yaw += G.rng.randf_range(-1.0, 1.0) * amount * 0.0016
	trauma = min(1.0, trauma + amount * 0.035)


func shake(a: float) -> void:
	trauma = clamp(trauma + a, 0.0, 1.2)


func forward() -> Vector3:
	return -Basis.from_euler(Vector3(pitch, yaw, 0)).z


func aim_point(max_d := 400.0) -> Vector3:
	var from = camera.global_position
	var dir = -camera.global_basis.z
	var ex = [G.player.get_rid()]
	if G.player.vehicle:
		ex.append(G.player.vehicle.get_rid())
	# start the ray a little ahead so the shoulder camera does not hit things behind the player
	var start = from + dir * max(0.0, (G.player.global_position - from).dot(dir))
	var h = G.ray(start, from + dir * max_d, G.L_SHOT, ex)
	return h.position if h else from + dir * max_d


func _process(dt: float) -> void:
	var p = G.player
	if p == null:
		return
	if photo:
		_photo(dt)
		return
	var jx = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var jy = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if abs(jx) > 0.15 or abs(jy) > 0.15:
		yaw -= jx * dt * 2.6
		pitch = clamp(pitch - jy * dt * 1.8, -1.35, 1.25)
		_idle_t = 0.0
	_idle_t += dt
	var target: Vector3 = p.global_position + Vector3(0, 1.55, 0)
	var dist = 3.6
	var side = 0.5
	var fov = 70.0
	scoped = false
	var veh = p.vehicle
	if veh and is_instance_valid(veh):
		var sz: float = veh._half.length()
		dist = clamp(sz * 2.2 + 2.0, 4.5, 20.0)
		target = veh.global_position + Vector3(0, clamp(veh._half.y * 1.6, 1.2, 3.2), 0)
		side = 0.0
		fov = 70.0 + clamp(abs(veh.speed) / 60.0, 0.0, 1.0) * 14.0
		var look_back = Input.is_action_pressed("lookback")
		if (_idle_t > 1.4 or look_back) and not p.aiming:
			var vy: float = veh.global_rotation.y + (PI if look_back or veh.speed < -2.0 else 0.0)
			yaw = lerp_angle(yaw, vy, clamp(dt * (8.0 if look_back else 2.2), 0.0, 1.0))
			if veh.kind in ["heli", "plane"]:
				pitch = lerpf(pitch, -0.22 + veh.global_rotation.x * 0.5, clamp(dt * 2.0, 0.0, 1.0))
			else:
				pitch = lerpf(pitch, -0.2, clamp(dt * 1.5, 0.0, 1.0))
		if first_person:
			dist = 0.0
			target = veh.seat_pos() + Vector3(0, 0.75, 0)
		if p.aiming:
			fov = 55.0
	else:
		if p.crouching or p.stealth or p.state == "cover" and p.cover.get("low", false):
			target.y -= 0.45
		if p.state == "swim":
			target.y -= 0.5
		if p.aiming and p.state != "vehicle":
			var w: Dictionary = p.weapons.d()
			dist = 2.5
			side = 0.8
			target.y += 0.12
			fov = 52.0
			if w.has("zoom"):
				fov = w.zoom
				if p.weapons.inv[p.weapons.cur].mods.has("Scope"):
					fov *= 0.8
				if w.get("scope", false):
					scoped = true
					dist = 0.0
					side = 0.0
					target = p.global_position + Vector3(0, 1.62, 0)
			elif p.weapons.inv[p.weapons.cur].mods.has("Scope"):
				fov = 36.0
		elif p.sprinting:
			fov = 76.0
		if first_person and not scoped:
			dist = 0.0
			side = 0.0
			target = p.global_position + Vector3(0, 1.66 - (0.45 if p.crouching or p.stealth else 0.0), 0)
		if p.state == "chute":
			dist = 6.5
	_dist = lerpf(_dist, dist, clamp(dt * 9.0, 0.0, 1.0))
	_fov = lerpf(_fov, fov, clamp(dt * 9.0, 0.0, 1.0))
	camera.fov = _fov
	global_position = global_position.lerp(target, clamp(dt * 22.0, 0.0, 1.0)) if global_position.distance_to(target) < 12.0 else target
	_kick = lerpf(_kick, 0.0, clamp(dt * 7.0, 0.0, 1.0))
	rotation = Vector3(pitch, yaw, 0)
	arm.position = Vector3(side, 0, 0)
	arm.spring_length = _dist
	# exclusions
	var want_ex = veh if veh else null
	if want_ex != _excluded:
		arm.clear_excluded_objects()
		arm.add_excluded_object(p.get_rid())
		if want_ex:
			arm.add_excluded_object(want_ex.get_rid())
		_excluded = want_ex
	trauma = max(0.0, trauma - dt * 1.6)
	var t2 = trauma * trauma
	camera.h_offset = (G.rng.randf() - 0.5) * 0.25 * t2
	camera.v_offset = (G.rng.randf() - 0.5) * 0.25 * t2
	camera.rotation.z = (G.rng.randf() - 0.5) * 0.06 * t2
	var hide_model: bool = (first_person or scoped) and _dist < 0.6
	if p.model:
		p.model.visible = not hide_model and p.model_visible


func _photo(dt: float) -> void:
	var v = Input.get_vector("left", "right", "fwd", "back")
	var b = Basis.from_euler(Vector3(pitch, yaw, 0))
	var sp = 12.0 if Input.is_action_pressed("sprint") else 4.0
	photo_pos += (b * Vector3(v.x, 0, v.y)) * dt * sp / max(Engine.time_scale, 0.05)
	if Input.is_action_pressed("jump"):
		photo_pos.y += dt * sp
	if Input.is_action_pressed("stealth"):
		photo_pos.y -= dt * sp
	global_position = photo_pos
	rotation = Vector3(pitch, yaw, 0)
	arm.spring_length = 0.0
	arm.position = Vector3.ZERO


func set_photo(on: bool) -> void:
	photo = on
	photo_pos = camera.global_position
	if G.hud:
		G.hud.visible = not on
