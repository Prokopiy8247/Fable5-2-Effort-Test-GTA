class_name PlayerCamera
extends Node3D
## Third-person orbit camera with collision avoidance, shoulder aim, scope, first-person toggle,
## vehicle / aircraft chase modes, look-back, shake and speed FOV.

var cam: Camera3D
var yaw := 0.0
var pitch := -0.18
var dist := 3.8
var target_dist := 3.8
var shoulder := 0.0
var height := 1.55
var fov := 68.0
var first_person := false
var scoped := false
var scope_fov := 12.0
var trauma := 0.0
var kick_pitch := 0.0
var kick_yaw := 0.0
var idle_t := 0.0
var pivot := Vector3.ZERO
var look_back := false
var photo_mode := false
var _noise_t := 0.0
var cinematic_target: Node3D = null


func _ready() -> void:
	cam = Camera3D.new()
	cam.far = 2200.0
	cam.near = 0.08
	cam.fov = fov
	add_child(cam)
	cam.make_current()
	top_level = true
	G.cam = self
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(ev: InputEvent) -> void:
	if G.ui_blocking > 0:
		return
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s: float = G.settings.mouse_sens * (cam.fov / 68.0)
		yaw -= ev.relative.x * s
		pitch -= ev.relative.y * s * (-1.0 if G.settings.invert_y else 1.0)
		pitch = clampf(pitch, -1.35, 1.25)
		idle_t = 0.0


func make_current_cam() -> void:
	cam.make_current()


func shake(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func kick(p: float, y: float) -> void:
	kick_pitch += deg_to_rad(p)
	kick_yaw += deg_to_rad(y)


func forward() -> Vector3:
	return -cam.global_transform.basis.z


func aim_point(max_dist: float = 400.0, exclude: Array = []) -> Vector3:
	## World point under the crosshair.
	var from := cam.global_position
	var to := from + forward() * max_dist
	var h := G.ray(from + forward() * 0.6, to, 1 | 2 | 4 | 8 | 32, exclude)
	return h.position if not h.is_empty() else to


func _process(delta: float) -> void:
	var p: Node = G.player
	if p == null:
		return
	idle_t += delta
	# controller look
	var lx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ly := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(lx) > 0.15 or absf(ly) > 0.15:
		yaw -= lx * delta * 2.6
		pitch = clampf(pitch - ly * delta * 1.8, -1.35, 1.25)
		idle_t = 0.0
	var veh: Vehicle = p.vehicle
	var aiming: bool = p.aiming
	var tgt_fov: float = G.settings.fov
	var tgt_shoulder := 0.0
	var tgt_height := 1.55
	var focus: Vector3 = p.global_position
	var fp := first_person
	look_back = Input.is_action_pressed("look_back") and G.ui_blocking == 0
	if p.ragdoll != null:
		focus = p.ragdoll.global_position - Vector3(0, 0.6, 0)
		fp = false
	if veh != null:
		focus = veh.global_position
		var sz := maxf(veh.half.z, veh.half.x)
		target_dist = 3.2 + sz * 2.1
		tgt_height = veh.half.y * 2.0 + 0.5
		if veh.kind in ["heli", "plane"]:
			target_dist = 6.0 + sz * 1.9
			tgt_height = veh.half.y + 1.6
		tgt_fov += clampf(veh.speed * 0.22, 0.0, 14.0)
		# auto centre behind the vehicle when the mouse rests
		if idle_t > 1.6 and veh.speed > 3.0 and not aiming:
			var vy := atan2(-veh.linear_velocity.x, -veh.linear_velocity.z) if veh.fwd_speed > 0.0 or veh.kind != "car" else veh.rotation.y
			if veh.kind in ["heli"]:
				vy = veh.rotation.y
			yaw = lerp_angle(yaw, vy, clampf(delta * 2.2, 0.0, 1.0))
			pitch = lerpf(pitch, -0.2 if veh.kind == "car" else -0.14, clampf(delta * 1.5, 0.0, 1.0))
		if aiming:
			target_dist = 2.6 + sz
			tgt_fov = 55.0
		if fp:
			focus = p.vis.head_pos() if p.vis else focus
	elif aiming and not p.melee_equipped():
		target_dist = 1.55
		tgt_shoulder = 0.52
		tgt_fov = p.aim_fov()
		tgt_height = 1.52 - p.vis.hips_drop * 0.8
	else:
		target_dist = 3.9 if not p.crouching else 3.2
		tgt_height = 1.58 - (0.38 if p.crouching or p.in_cover_low() else 0.0)
		if p.st == p.St.SWIM:
			tgt_height = 1.2
		if p.st == p.St.CHUTE:
			target_dist = 6.5
			tgt_fov += 6.0
	scoped = aiming and veh == null and p.weapon_scoped()
	if scoped:
		tgt_fov = p.aim_fov()
	shoulder = lerpf(shoulder, tgt_shoulder, clampf(delta * 10.0, 0.0, 1.0))
	height = lerpf(height, tgt_height, clampf(delta * 8.0, 0.0, 1.0))
	dist = lerpf(dist, target_dist, clampf(delta * 7.0, 0.0, 1.0))
	kick_pitch = lerpf(kick_pitch, 0.0, clampf(delta * 9.0, 0.0, 1.0))
	kick_yaw = lerpf(kick_yaw, 0.0, clampf(delta * 9.0, 0.0, 1.0))
	pitch = clampf(pitch + kick_pitch * delta * 9.0, -1.35, 1.25)
	yaw += kick_yaw * delta * 9.0
	var want := focus + Vector3(0, height, 0)
	var k := clampf(delta * (18.0 if veh == null else 14.0), 0.0, 1.0)
	pivot = pivot.lerp(want, k) if pivot.distance_to(want) < 12.0 else want
	var yy := yaw + (PI if look_back else 0.0)
	var bas := Basis.from_euler(Vector3(pitch, yy, 0.0))
	var right := bas.x
	var back := bas.z
	var origin := pivot + right * shoulder
	var pos: Vector3
	if scoped or (fp and p.ragdoll == null):
		var hp: Vector3 = p.vis.head_pos() if p.vis else pivot
		pos = hp + (-back) * 0.12
		if veh != null and fp:
			pos = hp + Vector3(0, 0.08, 0)
	else:
		var desired := origin + back * dist
		var excl: Array = [p.get_rid()]
		if veh != null:
			excl.append(veh.get_rid())
		var h := G.ray(origin, desired + back * 0.25, G.L_WORLD, excl)
		var dd := dist
		if not h.is_empty():
			dd = maxf(origin.distance_to(h.position) - 0.28, 0.35)
		if shoulder > 0.05:
			var hs := G.ray(pivot, origin, G.L_WORLD, excl)
			if not hs.is_empty():
				origin = pivot + right * maxf(pivot.distance_to(hs.position) - 0.2, 0.0)
		pos = origin + back * dd
		if pos.y < G.WATER_LEVEL + 0.25 and pivot.y > G.WATER_LEVEL and p.st != p.St.SWIM:
			pos.y = G.WATER_LEVEL + 0.25
	# shake
	trauma = maxf(trauma - delta * 1.4, 0.0)
	_noise_t += delta * 34.0
	var sh := trauma * trauma
	var shake_rot := Vector3(sin(_noise_t * 1.3) * 0.035, sin(_noise_t * 1.7 + 2.0) * 0.035, sin(_noise_t * 2.1 + 4.0) * 0.02) * sh
	global_position = pos
	cam.global_transform = Transform3D(bas * Basis.from_euler(shake_rot), pos)
	cam.fov = lerpf(cam.fov, tgt_fov, clampf(delta * 9.0, 0.0, 1.0))
	if p.vis:
		p.vis.visible = not (scoped or (fp and p.ragdoll == null and veh == null and p.st != p.St.DEAD))
