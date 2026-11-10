class_name CameraRig
extends Node3D
## Third-person camera: orbit, collision avoidance, shoulder aim, sniper scope, vehicle /
## aircraft chase with auto-centering and look-behind, first-person toggle, recoil kick,
## trauma shake, speed FOV and underwater detection.

var cam: Camera3D
var yaw := 0.0
var pitch := -0.18
var dist := 3.4
var first_person := false
var far_view := false
var scoped := false
var trauma := 0.0
var photo_mode := false
var _fov := 70.0
var _shoulder := 0.55
var _idle_time := 0.0
var _kick := 0.0
var _underwater := false
var _last_target: Node3D = null
var _pivot := Vector3.ZERO
var _look_back := false

func _ready() -> void:
	name = "CameraRig"
	cam = Camera3D.new()
	cam.near = 0.08
	cam.far = 3200.0
	cam.fov = float(Settings.get_v("fov", 70.0))
	add_child(cam)
	cam.make_current()
	process_priority = 100
	set_as_top_level(true)

func forward() -> Vector3:
	return -cam.global_transform.basis.z

func kick(amount: float) -> void:
	_kick += amount
	pitch = clampf(pitch + amount * 0.35, -1.35, 1.2)

func shake(amount: float) -> void:
	trauma = clampf(trauma + amount * float(Settings.get_v("camera_shake", 1.0)), 0.0, 1.0)

func snap() -> void:
	_last_target = null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Game.ui_blocked():
		var sens := 0.0026 * float(Settings.get_v("mouse_sensitivity", 1.0))
		if scoped:
			sens *= 0.3
		elif _is_aiming():
			sens *= 0.7
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * sens
		var inv := -1.0 if bool(Settings.get_v("invert_y", false)) else 1.0
		pitch = clampf(pitch - mm.relative.y * sens * inv, -1.35, 1.2)
		_idle_time = 0.0
	if event.is_action_pressed("camera_toggle") and not Game.ui_blocked():
		if first_person:
			first_person = false
			far_view = false
		elif not far_view:
			far_view = true
		else:
			first_person = true
		_apply_fp_visibility()

func _is_aiming() -> bool:
	var p: Player = Game.player
	return p != null and p.alive and p.aiming and (p.state == Player.St.FOOT or p.state == Player.St.MOVE or p.state == Player.St.VEHICLE)

func _apply_fp_visibility() -> void:
	var p: Player = Game.player
	if p != null and p.visual != null:
		p.visual.visible = not (first_person and p.state != Player.St.VEHICLE) or p.state == Player.St.DEAD

## World point under the crosshair (used by every weapon so bullets go where the player looks).
func aim_point(max_range := 400.0) -> Vector3:
	var from := cam.global_position
	var dirv := forward()
	var ex: Array[RID] = []
	var p: Player = Game.player
	if p != null:
		ex.append(p.get_rid())
		if p.vehicle != null and is_instance_valid(p.vehicle):
			ex.append((p.vehicle as CollisionObject3D).get_rid())
	# start past the player so things between camera and character are ignored
	var skip := 0.0
	if p != null:
		skip = maxf(0.0, (p.global_position + Vector3(0, 1.4, 0) - from).dot(dirv))
	var hit := Game.ray(from + dirv * skip, from + dirv * max_range, Phys.SHOOTABLE, ex)
	if hit.is_empty():
		return from + dirv * max_range
	return hit["position"]

func _process(delta: float) -> void:
	var p: Player = Game.player
	if p == null or not is_instance_valid(p):
		return
	if photo_mode:
		return
	var joy := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if joy.length() > 0.2 and not Game.ui_blocked():
		yaw -= joy.x * 2.6 * delta
		pitch = clampf(pitch - joy.y * 1.8 * delta, -1.35, 1.2)
		_idle_time = 0.0
	_idle_time += delta
	var veh: Vehicle = p.vehicle as Vehicle if (p.state == Player.St.VEHICLE and p.vehicle != null and is_instance_valid(p.vehicle)) else null
	var target: Node3D = veh if veh != null else p
	var aiming := _is_aiming()
	var gun_zoom := p.gunner.zoom_fov() if (aiming and p.gunner != null and p.gunner.is_gun()) else 0.0
	scoped = aiming and veh == null and bool(p.gunner.data.get("scoped", false))
	var base_fov := float(Settings.get_v("fov", 70.0))
	var want_fov := base_fov
	var want_dist := 3.4
	var height := 1.55
	var shoulder := 0.5
	var exclude: Array[RID] = [p.get_rid()]
	_look_back = veh != null and not Game.ui_blocked() and Input.is_action_pressed("look_behind")
	if veh != null:
		exclude.append(veh.get_rid())
		var sp := veh.linear_velocity.length()
		want_dist = float(veh.def.get("cam", 6.5)) * (1.25 if far_view else 1.0)
		height = veh.body_height * 0.75 + 0.6
		shoulder = 0.0
		want_fov = base_fov + clampf(sp * 0.22, 0.0, 14.0)
		# auto-centre behind the vehicle when the mouse is left alone
		if _idle_time > 1.4 and sp > 3.0 and not aiming:
			var vyaw := veh.global_rotation.y
			if veh.speed < -2.0 and veh is Car:
				vyaw += PI
			yaw = lerp_angle(yaw, vyaw, clampf(delta * 2.2, 0.0, 1.0))
			var want_pitch := -0.2 if not (veh is Heli or veh is Airplane) else -0.12 - veh.linear_velocity.normalized().y * 0.5
			pitch = lerpf(pitch, want_pitch, clampf(delta * 1.5, 0.0, 1.0))
		if aiming:
			want_fov = base_fov - 12.0
		if first_person:
			want_dist = 0.0
	else:
		if p.crouched:
			height = 1.15
		if far_view:
			want_dist = 5.2
		if aiming:
			want_dist = 1.7
			shoulder = 0.62
			want_fov = gun_zoom if gun_zoom > 0.0 else base_fov - 14.0
		if p.state == Player.St.MOVE and p.moves and (p.moves.mode == PlayerMoves.Mode.FREEFALL or p.moves.mode == PlayerMoves.Mode.CHUTE):
			want_dist = 7.0
			shoulder = 0.0
		if p.state == Player.St.SWIM:
			height = 1.35
		if first_person or scoped:
			want_dist = 0.0
	_apply_fp_visibility()
	if scoped and p.visual:
		p.visual.visible = false
	# --- pivot
	var pivot := target.global_position + Vector3(0, height, 0)
	if veh == null and (first_person or scoped):
		pivot = p.visual.head_position() if p.visual else pivot
	elif veh != null and first_person:
		pivot = p.global_position + veh.global_transform.basis.y * 0.72 - veh.global_transform.basis.z * 0.1
	if _last_target != target:
		_last_target = target
		_pivot = pivot
		if veh != null:
			yaw = veh.global_rotation.y
	_pivot = _pivot.lerp(pivot, clampf(delta * (22.0 if veh == null else 16.0), 0.0, 1.0))
	if first_person or scoped:
		_pivot = pivot
	var use_yaw := yaw + (PI if _look_back else 0.0)
	var basis := Basis(Vector3.UP, use_yaw) * Basis(Vector3.RIGHT, pitch)
	_shoulder = lerpf(_shoulder, shoulder, clampf(delta * 8.0, 0.0, 1.0))
	var side := basis.x * _shoulder
	# keep the shoulder offset out of walls
	if _shoulder > 0.05:
		var sh := Game.ray(_pivot, _pivot + side * 1.6, Phys.CAMERA_BLOCK | Phys.VEHICLE, exclude)
		if not sh.is_empty():
			side = side.normalized() * maxf(0.0, _pivot.distance_to(sh["position"]) - 0.25)
	var origin := _pivot + side
	var back := basis.z
	var d := want_dist
	if want_dist > 0.05:
		var q := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.22
		q.shape = sphere
		q.collision_mask = Phys.CAMERA_BLOCK | (Phys.VEHICLE if veh == null else 0)
		q.exclude = exclude
		q.transform = Transform3D(Basis.IDENTITY, origin)
		q.motion = back * want_dist
		var res := get_world_3d().direct_space_state.cast_motion(q)
		if res.size() == 2 and res[0] < 1.0:
			d = maxf(want_dist * float(res[0]) - 0.05, 0.25)
	# pull in instantly, ease back out
	dist = d if d < dist else lerpf(dist, d, clampf(delta * 5.0, 0.0, 1.0))
	if want_dist <= 0.05:
		dist = 0.0
	var pos := origin + back * dist
	# --- shake + recoil recovery
	trauma = maxf(0.0, trauma - delta * 1.4)
	var sh_amt := trauma * trauma
	var t := Time.get_ticks_msec() * 0.001
	var shake_rot := Vector3(sin(t * 37.0) * 0.022, sin(t * 43.0 + 1.3) * 0.022, sin(t * 29.0 + 2.1) * 0.03) * sh_amt
	_kick = lerpf(_kick, 0.0, clampf(delta * 9.0, 0.0, 1.0))
	global_transform = Transform3D(basis, pos)
	cam.transform = Transform3D(Basis.from_euler(shake_rot + Vector3(_kick * 0.5, 0, 0)), Vector3.ZERO)
	if scoped:
		want_fov = gun_zoom
	_fov = lerpf(_fov, want_fov, clampf(delta * 9.0, 0.0, 1.0))
	cam.fov = clampf(_fov, 6.0, 100.0)
	# --- underwater presentation
	var uw := Game.water_depth(cam.global_position) > 0.05
	if uw != _underwater:
		_underwater = uw
		Audio.set_underwater(uw)
		if Game.weather:
			Game.weather.set_underwater(uw)
