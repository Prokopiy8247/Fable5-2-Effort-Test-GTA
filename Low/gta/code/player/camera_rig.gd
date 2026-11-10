class_name CameraRig
extends Node3D
# Third-person orbit camera with collision (SpringArm3D), shoulder aim, scope, vehicle chase,
# optional first-person, FOV kick and trauma shake.

var yaw := 0.0
var pitch := -0.2
var cam: Camera3D
var arm: SpringArm3D
var trauma := 0.0
var first_person := false
var last_mouse := -10.0
var sens := 0.0026
var scoped := false
var photo := false
var focus := Vector3.ZERO


func _ready() -> void:
	arm = SpringArm3D.new()
	arm.spring_length = 3.8
	arm.collision_mask = G.L_WORLD
	arm.margin = 0.25
	var s := SphereShape3D.new()
	s.radius = 0.22
	arm.shape = s
	add_child(arm)
	cam = Camera3D.new()
	cam.far = 1800.0
	cam.near = 0.08
	cam.fov = 70.0
	arm.add_child(cam)
	cam.make_current()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var k: float = sens * cam.fov / 70.0
		yaw -= e.relative.x * k
		pitch = clamp(pitch - e.relative.y * k, -1.45, 1.35)
		last_mouse = G.time_now


func shake(amount: float) -> void:
	trauma = min(1.0, trauma + amount)


func kick(deg: float) -> void:
	pitch = clamp(pitch + deg_to_rad(deg), -1.45, 1.35)
	yaw += deg_to_rad(randf_range(-deg, deg) * 0.3)


func aim_dir() -> Vector3:
	return -cam.global_basis.z


func aim_origin() -> Vector3:
	return cam.global_position + aim_dir() * (cam.global_position.distance_to(focus) + 0.2)


func _process(dt: float) -> void:
	var p = G.player
	if p == null:
		return
	var d := 3.8
	var fov := 70.0
	var side := 0.0
	var f: Vector3 = p.global_position + Vector3.UP * (1.15 if p.crouching else 1.6)
	scoped = false
	var hide_model := false
	if p.vehicle != null and p.state == "vehicle":
		var v = p.vehicle
		f = v.global_position + v.global_basis.y * (v.def.H * 0.6 + 0.7)
		d = v.def.L * 1.2 + 3.2 + (5.0 if v.kind in ["heli", "plane"] else 0.0)
		fov = 70.0 + clamp(v.linear_velocity.length() / 50.0, 0.0, 1.0) * 14.0
		if G.time_now - last_mouse > 1.6 and v.linear_velocity.length() > 3.0 and not p.aiming:
			var vy: float = v.global_rotation.y
			if v.fspeed < -2.0 and v.kind == "car":
				vy += PI
			yaw = lerp_angle(yaw, vy, dt * 2.2)
			var tp := -0.2 + (asin(clamp((-v.global_basis.z).y, -1.0, 1.0)) * 0.7 if v.kind in ["heli", "plane"] else 0.0)
			pitch = lerp(pitch, tp, dt * 1.5)
		if p.aiming:
			d *= 0.75
			fov = 58.0
		if first_person:
			f = v.seat_transform().origin + v.global_basis.y * 1.05
			d = 0.0
			hide_model = true
	else:
		if p.aiming and p.state in ["normal", "cover"]:
			d = 2.1
			side = 0.55
			fov = 52.0
			var wd: Dictionary = p.wdef()
			if "scope" in p.atts.get(p.weapon, []):
				fov = 36.0
			if wd.has("zoom") and p.zoomed:
				fov = wd.zoom
				scoped = true
		if p.state == "chute":
			d = 7.0
		if first_person or scoped:
			d = 0.0
			side = 0.0
			f = p.global_position + Vector3.UP * (1.2 if p.crouching else 1.68) + (-p.global_basis.z) * 0.12
			hide_model = true
	if photo:
		d = 5.0
		hide_model = false
	focus = f
	global_position = global_position.lerp(f, min(1.0, dt * 22.0)) if global_position.distance_to(f) < 12.0 else f
	rotation = Vector3(pitch, yaw, 0)
	arm.position.x = lerp(arm.position.x, side, min(1.0, dt * 10.0))
	arm.spring_length = lerp(arm.spring_length, d, min(1.0, dt * 9.0))
	cam.fov = lerp(cam.fov, fov, min(1.0, dt * 10.0))
	p.body.visible = not hide_model
	trauma = max(0.0, trauma - dt * 1.4)
	var sh := trauma * trauma
	cam.h_offset = randf_range(-1, 1) * sh * 0.25
	cam.v_offset = randf_range(-1, 1) * sh * 0.25
