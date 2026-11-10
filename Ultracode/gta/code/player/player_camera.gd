class_name PlayerCamera
extends Node3D
## Gameplay camera rig of the player (registered as Game.camera_rig).
##
## Modes (the rig picks one every frame from the player state; `set_mode()` forces one):
##   third     orbit behind the character, collision aware
##   aim       over-the-shoulder, zoomed (inventory.get_aim_fov() when available)
##   first     at the eyes of the character (camera_toggle cycles third <-> first); works in vehicles
##   vehicle   chase camera from vehicle.get_camera_params(), look-around, look_back, speed FOV
##   aircraft  chase camera with more distance that follows the pitch of the aircraft
##   scope     first-person view with the narrow weapon FOV (the UI draws the overlay)
##   photo     detached free-fly camera (WASD + mouse) for the photo mode screen
##
## Public: yaw, pitch (radians; yaw 0 looks at -Z, + = left; pitch + = up), mode, camera,
## add_trauma(amount), add_recoil(pitch_deg, yaw_deg), set_fov_override(fov, weight),
## set_mode(name), cycle_view(), snap_to(yaw), get_aim_origin(), get_aim_direction().
##
## The follow position is advanced in the physics tick (the bodies it follows only move there),
## the orientation in the render frame (mouse look stays crisp).
##
## Mouse mode is owned by the UI module. Fallback ONLY while the UI autoload does not handle it
## (ui_owns_mouse() is false): in windowed, non-test runs the rig captures the mouse itself when
## nothing else did (see _fallback_capture).

const MODES: PackedStringArray = ["third", "aim", "first", "vehicle", "aircraft", "scope", "photo"]

# --- tunables ---------------------------------------------------------------------------------
const THIRD_DISTANCE := 3.1
const THIRD_HEIGHT := 1.55             ## pivot above the feet
const THIRD_SIDE := 0.34               ## shoulder offset (+ = right)
const AIM_DISTANCE := 1.75
const AIM_HEIGHT := 1.66
const AIM_SIDE := 0.62
const AIM_FOV := 52.0
const CROUCH_DROP := 0.42
const SWIM_HEIGHT := 1.75
const PITCH_MIN := -1.25
const PITCH_MAX := 1.10
const FIRST_PITCH := 1.45
const DEFAULT_PITCH := -0.14
const PROBE_RADIUS := 0.2
const FOLLOW_RATE := 24.0              ## 1/s horizontal follow
const FOLLOW_RATE_Y := 9.0             ## 1/s vertical follow (smooths kerbs and steps)
const FOLLOW_RATE_VEHICLE := 38.0
const DISTANCE_RECOVER := 3.0          ## fraction / s the arm extends again after a collision
const VEHICLE_DEFAULTS := {"distance": 6.2, "height": 2.1, "fov": 72.0, "look_height": 1.0}
const AIRCRAFT_DISTANCE_MULT := 1.45
const AUTO_CENTER_DELAY := 1.3
const AUTO_CENTER_RATE := 2.4
const HINT_FOLLOW_DELAY := 0.9         ## state hint "follow_yaw": mouse idle this long -> swing in behind
const HINT_FOLLOW_RATE := 2.2
const HEADING_RATE := 5.5
const SPEED_FOV := 13.0                ## extra degrees at SPEED_FOV_AT
const SPEED_FOV_AT := 40.0             ## m/s
const SPRINT_FOV := 4.0
const FIRST_FOV_BONUS := 6.0
const FOV_RATE := 9.0
const TRAUMA_DECAY := 1.4
const SHAKE_ROT := Vector3(0.045, 0.045, 0.03)
const SHAKE_POS := 0.06
const RECOIL_RECOVERY := 7.0
const HIDE_BODY_DISTANCE := 0.55
const PHOTO_SPEED := 6.0
const PHOTO_RANGE := 80.0
const PAD_LOOK_SPEED := Vector2(2.7, 1.9)
# drive-by free aim (vehicle mode while the player aims from a seat)
const DRIVE_BY_DISTANCE_MULT := 0.5
const DRIVE_BY_DISTANCE_MAX := 2.4
const DRIVE_BY_RAISE := 0.35
const DRIVE_BY_HEAD := 1.3              ## pivot above the seat hip point while aiming from a seat
const DRIVE_BY_LEAD := 1.5              ## pivot moved this far along the view (camera ~0.9 m behind the head)
const DRIVE_BY_FOV_BONUS := 8.0
const DRIVE_BY_START_PITCH := -0.06
const DRIVE_BY_PITCH_MIN := -0.75
const DRIVE_BY_PITCH_MAX := 0.55
## Enclosed vehicles (cars, vans, trucks): the drive-by camera sits INSIDE the cabin, over the shooter's
## far shoulder, looking out of the window the gun points through (review fix: from above the roof the
## shooter, the arm and the gun were all hidden under the roof edge - only the roof filled the screen).
## Open vehicles (bikes, boats, aircraft) keep the orbit above the shooter's head.
const DRIVE_BY_CABIN_BACK := 0.8        ## m from the shooter's eyes, against the view (flat)
const DRIVE_BY_CABIN_SIDE := 0.34       ## m sideways (over the shoulder), towards the roomy middle of the cabin
const DRIVE_BY_CABIN_UP := 0.07         ## a little above the eyes: over the seat back onto the gun arm
const DRIVE_BY_CABIN_CLEAR := 0.55      ## another occupant's head closer than this to the point = no cabin view
const DRIVE_BY_CABIN_MAX_COS := -0.5    ## aims further back than 120 deg from the bonnet use the orbit camera
const DRIVE_BY_OPEN_CLASSES: PackedStringArray = ["bike", "bicycle", "boat", "heli", "plane"]
## Only bodies whose cabin was checked from inside (qa/screenshots/plr4_dbcam_<spec>.png) get the cabin
## view; the others keep the orbit (van / box truck: the camera point lands in the cab's back wall,
## sports: too low a roof).
const DRIVE_BY_CABIN_SPECS: PackedStringArray = ["sedan", "police_cruiser", "taxi", "compact", "suv", "muscle", "pickup"]

var yaw: float = 0.0
var pitch: float = DEFAULT_PITCH
var mode: String = "third"
var camera: Camera3D = null
var player: Node3D = null
var first_person: bool = false          ## the user's view preference (camera_toggle)
var require_capture: bool = true        ## mouse motion only counts while the mouse is captured
var trauma: float = 0.0

var _forced_mode: String = ""
var _follow: Vector3 = Vector3.ZERO
var _follow_valid: bool = false
var _dist_frac: float = 1.0
var _fov: float = 70.0
var _fov_override: float = 70.0
var _fov_override_w: float = 0.0
var _recoil: Vector2 = Vector2.ZERO     ## x = pitch, y = yaw offsets (radians)
var _shake_t: float = 0.0
var _aim_origin: Vector3 = Vector3.ZERO
var _aim_basis: Basis = Basis.IDENTITY
var _blend: Vector3 = Vector3(THIRD_SIDE, THIRD_HEIGHT, THIRD_DISTANCE)   ## side, height, distance (smoothed)
var _veh_yaw_off: float = 0.0
var _veh_pitch: float = -0.2
var _veh_heading: float = 0.0
var _veh_pitch_follow: float = 0.0
var _look_idle: float = 10.0
var _last_vehicle: Node3D = null
var _eye_local: Vector3 = Vector3(0.0, 1.66, -0.1)
var _photo_pos: Vector3 = Vector3.ZERO
var _body_hidden: bool = false
var _head_hidden: bool = false
var _query: PhysicsShapeQueryParameters3D = null
var _probe: SphereShape3D = null
var _self_captured: bool = false
var _capture_wait: float = 0.0
var _capture_checked: bool = false
var _drive_by: bool = false
var _db_blend: float = 0.0
var _db_cabin: bool = false               ## the drive-by camera is inside the cabin this frame
var _cab_w: float = 0.0                   ## smoothed weight of the cabin view (switches never snap)
var _cab_last: Vector3 = Vector3.INF     ## last cabin point, in the vehicle's local frame
var _cab_vehicle: Node3D = null
var _pivot_off: Vector3 = Vector3.ZERO    ## smoothed state hint "pivot_offset" (cover)
var _hint_mask: int = 0                   ## extra collision layers of the state hint (cover)


## True while the vehicle camera is in drive-by free aim.
func is_drive_by_aiming() -> bool:
	return _drive_by and (mode == "vehicle" or mode == "aircraft")


func _ready() -> void:
	top_level = true
	process_priority = 60
	process_physics_priority = 60
	camera = get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	camera.near = 0.08
	camera.far = 3000.0
	_fov = float(Settings.get_value("fov"))
	camera.fov = _fov
	_probe = SphereShape3D.new()
	_probe.radius = PROBE_RADIUS
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = _probe
	_query.collision_mask = Layers.CAMERA_MASK
	_query.collide_with_areas = false
	if not Fx.camera_shake_requested.is_connected(add_trauma):
		Fx.camera_shake_requested.connect(add_trauma)
	EventBus.ui_screen_opened.connect(_on_screen_opened)
	EventBus.ui_screen_closed.connect(_on_screen_closed)


func setup(p: Node3D) -> void:
	player = p
	Game.camera_rig = self
	yaw = p.rotation.y
	_follow_valid = false
	if camera != null:
		camera.make_current()


# --- public API ---------------------------------------------------------------------------------

## Camera shake, 0..1 (squared for the actual amplitude). Fx.shake_camera() lands here.
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## View kick from a shot, in degrees. The kick recovers on its own.
func add_recoil(pitch_deg: float, yaw_deg: float) -> void:
	_recoil.x = clampf(_recoil.x + deg_to_rad(pitch_deg), -0.5, 0.5)
	_recoil.y = clampf(_recoil.y + deg_to_rad(yaw_deg), -0.5, 0.5)


## Blend the field of view towards `fov` by `weight` (0 = off, 1 = fully overridden).
func set_fov_override(fov: float, weight: float) -> void:
	_fov_override = fov
	_fov_override_w = clampf(weight, 0.0, 1.0)


## Force a mode ("photo", "scope", "first", "third" ...). "" returns to automatic selection.
func set_mode(new_mode: String) -> void:
	if new_mode != "" and not MODES.has(new_mode):
		return
	if new_mode == "photo" and _forced_mode != "photo" and camera != null:
		_photo_pos = camera.global_position
	_forced_mode = new_mode


func get_forced_mode() -> String:
	return _forced_mode


## third <-> first.
func cycle_view() -> void:
	first_person = not first_person


## Put the camera behind a new facing immediately (teleport, respawn).
func snap_to(new_yaw: float) -> void:
	yaw = new_yaw
	pitch = DEFAULT_PITCH
	_follow_valid = false
	_dist_frac = 1.0
	_veh_yaw_off = 0.0
	_recoil = Vector2.ZERO


func get_aim_origin() -> Vector3:
	return _aim_origin


func get_aim_direction() -> Vector3:
	return -_aim_basis.z


## Rotate the view (radians). Mouse and game-pad look end up here; tests may call it directly.
func apply_look(d_yaw: float, d_pitch: float) -> void:
	_look_idle = 0.0
	if mode == "vehicle" or mode == "aircraft" or (mode == "first" and _vehicle() != null):
		_veh_yaw_off = wrapf(_veh_yaw_off + d_yaw, -PI, PI)
		_veh_pitch = clampf(_veh_pitch + d_pitch, PITCH_MIN, 0.9)
	else:
		yaw = wrapf(yaw + d_yaw, -PI, PI)
		var limit := FIRST_PITCH if (mode == "first" or mode == "scope" or mode == "photo") else PITCH_MAX
		pitch = clampf(pitch + d_pitch, -limit if limit > PITCH_MAX else PITCH_MIN, limit)


# --- input ---------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Game.is_input_locked() and mode != "photo":
			return
		if require_capture and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		var mm := event as InputEventMouseMotion
		var sens := float(Settings.get_value("mouse_sensitivity"))
		if camera != null:
			sens *= clampf(camera.fov / maxf(float(Settings.get_value("fov")), 1.0), 0.2, 1.2)
		var inv := -1.0 if bool(Settings.get_value("invert_y")) else 1.0
		# screen_relative is not scaled by the window stretch, so the sensitivity is the same at
		# every window size (relative is the fallback for synthetic events)
		var rel := mm.screen_relative
		if rel == Vector2.ZERO:
			rel = mm.relative
		apply_look(-rel.x * sens, -rel.y * sens * inv)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if _self_captured or not _capture_checked:
			_fallback_capture()


func _poll_input(delta: float) -> void:
	if player == null:
		return
	var locked := Game.is_input_locked()
	if not locked or mode == "photo":
		var lx := Input.get_axis(&"look_left", &"look_right")
		var ly := Input.get_axis(&"look_down", &"look_up")
		if absf(lx) > 0.05 or absf(ly) > 0.05:
			var inv := -1.0 if bool(Settings.get_value("invert_y")) else 1.0
			apply_look(-lx * PAD_LOOK_SPEED.x * delta, ly * PAD_LOOK_SPEED.y * delta * inv)
	if not locked and _forced_mode == "" and Input.is_action_just_pressed(&"camera_toggle"):
		cycle_view()


# --- update ----------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	var target := _focus()
	if not _follow_valid:
		_follow = target
		_follow_valid = true
		return
	var veh := _vehicle()
	if veh == null and bool(_state_hint().get("rigid", false)):
		_follow = target            # skydiving: no lag at 50 m/s (the pivot would trail metres behind)
		return
	if veh != null:
		_follow = _follow.lerp(target, 1.0 - exp(-FOLLOW_RATE_VEHICLE * delta))
	else:
		var kh := 1.0 - exp(-FOLLOW_RATE * delta)
		var kv := 1.0 - exp(-FOLLOW_RATE_Y * delta)
		_follow.x = lerpf(_follow.x, target.x, kh)
		_follow.z = lerpf(_follow.z, target.z, kh)
		_follow.y = lerpf(_follow.y, target.y, kv)
	if _follow.distance_squared_to(target) > 400.0:
		_follow = target        # teleported


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or camera == null or not player.is_inside_tree():
		return
	_poll_input(delta)
	_update_capture(delta)
	if not _follow_valid:
		_follow = _focus()
		_follow_valid = true

	var new_mode := _resolve_mode()
	if new_mode != mode:
		_on_mode_changed(mode, new_mode)
		mode = new_mode
		EventBus.camera_mode_changed.emit(mode)

	_look_idle += delta
	_recoil = _recoil.lerp(Vector2.ZERO, 1.0 - exp(-RECOIL_RECOVERY * delta))
	trauma = maxf(trauma - TRAUMA_DECAY * delta, 0.0)
	_shake_t += delta

	var target_fov := float(Settings.get_value("fov"))
	var pos: Vector3
	var rot: Basis
	var hide_body := false
	var hide_head := false
	match mode:
		"photo":
			_update_photo(delta)
			pos = _photo_pos
			rot = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		"first", "scope":
			var veh := _vehicle()
			_update_eye(delta)
			var body_xf: Transform3D = player.global_transform
			pos = body_xf * _eye_local
			if veh != null:
				_idle_center(delta, veh, 0.0)
				rot = veh.global_basis.orthonormalized() * Basis(Vector3.UP, _veh_yaw_off) * Basis(Vector3.RIGHT, clampf(_veh_pitch + 0.2, -1.0, 1.0) + _recoil.x)
				var f := -rot.z
				yaw = atan2(-f.x, -f.z)
				pitch = asin(clampf(f.y, -1.0, 1.0))
			else:
				rot = Basis(Vector3.UP, yaw + _recoil.y) * Basis(Vector3.RIGHT, pitch + _recoil.x)
			hide_head = true
			hide_body = mode == "scope"
			target_fov = _aim_fov() if (mode == "scope" or bool(player.get("is_aiming"))) else target_fov + FIRST_FOV_BONUS
			_dist_frac = 1.0
		"vehicle", "aircraft":
			var veh2 := _vehicle()
			var params: Dictionary = VEHICLE_DEFAULTS
			if veh2 != null and veh2.has_method("get_camera_params"):
				var pv: Variant = veh2.call("get_camera_params")
				if pv is Dictionary:
					params = pv
			var dist := float(params.get("distance", VEHICLE_DEFAULTS["distance"]))
			var height := float(params.get("height", VEHICLE_DEFAULTS["height"]))
			var look_h := float(params.get("look_height", VEHICLE_DEFAULTS["look_height"]))
			target_fov = float(params.get("fov", VEHICLE_DEFAULTS["fov"]))
			var speed := 0.0
			if veh2 is RigidBody3D:
				speed = (veh2 as RigidBody3D).linear_velocity.length()
			# drive-by: free aim closer to the car, crosshair level with the horizon, no re-centring
			var drive_by := bool(player.get("is_aiming"))
			if drive_by and not _drive_by:
				_veh_pitch = maxf(_veh_pitch, DRIVE_BY_START_PITCH)
			_drive_by = drive_by
			if drive_by:
				_look_idle = 0.0
				dist = minf(dist * DRIVE_BY_DISTANCE_MULT, DRIVE_BY_DISTANCE_MAX)
				look_h += DRIVE_BY_RAISE
				target_fov = _aim_fov() + DRIVE_BY_FOV_BONUS
			else:
				target_fov += SPEED_FOV * clampf(speed / SPEED_FOV_AT, 0.0, 1.0)
			var base_pitch := -atan2(maxf(height - look_h, 0.0), maxf(dist, 0.5))
			var vf := -veh2.global_basis.z if veh2 != null else Vector3.FORWARD
			var heading := atan2(-vf.x, -vf.z)
			var rate := HEADING_RATE
			if mode == "aircraft":
				dist *= AIRCRAFT_DISTANCE_MULT
				rate = HEADING_RATE * 0.6
				_veh_pitch_follow = lerpf(_veh_pitch_follow, asin(clampf(vf.y, -1.0, 1.0)) * 0.55, 1.0 - exp(-3.0 * delta))
			else:
				_veh_pitch_follow = lerpf(_veh_pitch_follow, asin(clampf(vf.y, -1.0, 1.0)) * 0.35, 1.0 - exp(-3.0 * delta))
			_veh_heading = lerp_angle(_veh_heading, heading, 1.0 - exp(-rate * delta))
			_idle_center(delta, veh2, base_pitch)
			var back := PI if (not Game.is_input_locked() and Input.is_action_pressed(&"look_back") and not drive_by) else 0.0
			yaw = wrapf(_veh_heading + _veh_yaw_off + back, -PI, PI)
			if drive_by:
				pitch = clampf(_veh_pitch, DRIVE_BY_PITCH_MIN, DRIVE_BY_PITCH_MAX)
			else:
				pitch = clampf(_veh_pitch + _veh_pitch_follow, PITCH_MIN, 1.0)
			rot = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
			_blend = _blend.lerp(Vector3(0.0, look_h, dist), 1.0 - exp(-6.0 * delta))
			var origin := _follow + Vector3(0.0, _blend.y, 0.0)
			# drive-by: orbit the shooter's head instead of the vehicle centre, so the camera sits just
			# above the roof line on the far side and looks over the car out of the shooter's window
			_db_blend = lerpf(_db_blend, 1.0 if drive_by else 0.0, 1.0 - exp(-8.0 * delta))
			if _db_blend > 0.001:
				# lead along the view so the camera ends up just behind / above the shooter's head
				var lead := Vector3(-sin(yaw), 0.0, -cos(yaw)) * DRIVE_BY_LEAD
				origin = origin.lerp(player.global_position + Vector3(0.0, DRIVE_BY_HEAD, 0.0) + lead, _db_blend)
			pos = _collide(origin, origin + rot * Vector3(_blend.x, 0.0, _blend.z), delta)
			_db_cabin = false
			if veh2 != _cab_vehicle:
				_cab_vehicle = veh2
				_cab_w = 0.0
				_cab_last = Vector3.INF
			var cab := _drive_by_cabin_point(veh2, yaw) if _db_blend > 0.001 else Vector3.INF
			if cab.is_finite():
				_cab_last = veh2.global_transform.affine_inverse() * cab
				_db_cabin = drive_by
			_cab_w = lerpf(_cab_w, 1.0 if (cab.is_finite() and drive_by) else 0.0, 1.0 - exp(-10.0 * delta))
			if _cab_w > 0.001 and _cab_last.is_finite() and veh2 != null:
				pos = pos.lerp(veh2.global_transform * _cab_last, _cab_w * _db_blend)
		_:
			# third / aim
			var aiming := mode == "aim"
			var crouch := bool(player.get("is_crouching"))
			var swimming := bool(player.get("is_swimming"))
			var want := Vector3(THIRD_SIDE, THIRD_HEIGHT, THIRD_DISTANCE)
			if aiming:
				want = Vector3(AIM_SIDE, AIM_HEIGHT, AIM_DISTANCE)
				target_fov = _aim_fov()
			elif bool(player.get("is_sprinting")):
				target_fov += SPRINT_FOV
			if crouch:
				want.y -= CROUCH_DROP
			if swimming:
				want.y = SWIM_HEIGHT
			if bool(player.get("is_dead")) or str(player.get("state_id")) == "ragdoll":
				want = Vector3(0.0, 0.9, THIRD_DISTANCE + 0.8)
			# the active player state may override the framing (cover: shoulder on the open side,
			# pivot pushed out of the wall, vehicles / props added to the collision probe)
			var hint := _state_hint()
			var piv := Vector3.ZERO
			_hint_mask = 0
			if not hint.is_empty():
				want.x = float(hint.get("side", want.x))
				want.y = float(hint.get("height", want.y))
				want.z = float(hint.get("distance", want.z))
				piv = hint.get("pivot_offset", Vector3.ZERO)
				_hint_mask = int(hint.get("mask", 0))
			# skydiving: swing in behind the heading when the mouse rests, wider view
			if not hint.is_empty():
				if hint.has("follow_yaw") and _look_idle > HINT_FOLLOW_DELAY:
					var kf := 1.0 - exp(-HINT_FOLLOW_RATE * delta)
					yaw = lerp_angle(yaw, float(hint["follow_yaw"]), kf)
					if hint.has("follow_pitch"):
						pitch = lerpf(pitch, float(hint["follow_pitch"]), kf)
				target_fov += float(hint.get("fov_add", 0.0))
			_pivot_off = _pivot_off.lerp(piv, 1.0 - exp(-8.0 * delta))
			_blend = _blend.lerp(want, 1.0 - exp(-10.0 * delta))
			rot = Basis(Vector3.UP, yaw + _recoil.y) * Basis(Vector3.RIGHT, pitch + _recoil.x)
			var origin2 := _follow + Vector3(0.0, _blend.y, 0.0) + _pivot_off
			pos = _collide(origin2, origin2 + rot * Vector3(_blend.x, 0.0, _blend.z), delta)
			_hint_mask = 0
			hide_body = pos.distance_to(origin2) < HIDE_BODY_DISTANCE

	_aim_origin = pos
	_aim_basis = rot

	# field of view
	target_fov = lerpf(target_fov, _fov_override, _fov_override_w)
	_fov = lerpf(_fov, target_fov, 1.0 - exp(-FOV_RATE * delta))
	camera.fov = clampf(_fov, 5.0, 120.0)
	camera.near = 0.05 if (mode == "first" or mode == "scope") else 0.08

	# shake (never moves the aim)
	if trauma > 0.001:
		var s := trauma * trauma
		var t := _shake_t
		var rx := (sin(t * 37.1 + 1.3) * 0.6 + sin(t * 71.7 + 4.1) * 0.4) * SHAKE_ROT.x * s
		var ry := (sin(t * 41.3 + 2.7) * 0.6 + sin(t * 63.9 + 0.4) * 0.4) * SHAKE_ROT.y * s
		var rz := (sin(t * 33.7 + 5.1) * 0.6 + sin(t * 79.3 + 3.3) * 0.4) * SHAKE_ROT.z * s
		rot = rot * Basis.from_euler(Vector3(rx, ry, rz))
		pos += rot * Vector3(sin(t * 47.0) * SHAKE_POS * s, cos(t * 53.0) * SHAKE_POS * s, 0.0)
	# the rig first, THEN the camera (review fix: the Camera3D is a child of this rig, so moving the rig
	# after placing the camera shifted the rendered camera by one frame of follow motion - up to ~1 m
	# at speed in a vehicle, varying with the physics ticks per frame (jitter) and off the aim ray)
	global_position = _follow
	camera.global_transform = Transform3D(rot, pos)

	_apply_body_visibility(hide_body, hide_head)


func _update_photo(delta: float) -> void:
	var mv := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var up := 0.0
	if Input.is_action_pressed(&"jump"):
		up += 1.0
	if Input.is_action_pressed(&"crouch"):
		up -= 1.0
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var sp := PHOTO_SPEED * (3.0 if Input.is_action_pressed(&"sprint") else 1.0)
	_photo_pos += (b * Vector3(mv.x, 0.0, mv.y) + Vector3(0.0, up, 0.0)) * sp * delta
	var centre := _focus() + Vector3(0.0, 1.2, 0.0)
	if _photo_pos.distance_to(centre) > PHOTO_RANGE:
		_photo_pos = centre + (_photo_pos - centre).normalized() * PHOTO_RANGE


func _update_eye(delta: float) -> void:
	var target := Vector3(0.0, 1.66, -0.10)
	var anim: Variant = player.get("animator")
	if anim is HumanoidAnimator and (anim as HumanoidAnimator).is_ready():
		var a := anim as HumanoidAnimator
		var skel := a.skeleton
		if skel != null and skel.is_inside_tree():
			var world := skel.global_transform * a.get_eye_position()
			target = player.global_transform.affine_inverse() * world
			target.x *= 0.3
	_eye_local = _eye_local.lerp(target, 1.0 - exp(-14.0 * delta))


## Vehicle look-around drifts back behind the vehicle when the mouse rests and the vehicle moves.
func _idle_center(delta: float, veh: Node3D, base_pitch: float) -> void:
	if _look_idle < AUTO_CENTER_DELAY:
		return
	var moving := true
	if veh is RigidBody3D:
		moving = (veh as RigidBody3D).linear_velocity.length() > 1.5
	if not moving:
		return
	var k := 1.0 - exp(-AUTO_CENTER_RATE * delta)
	_veh_yaw_off = lerp_angle(_veh_yaw_off, 0.0, k)
	_veh_pitch = lerpf(_veh_pitch, base_pitch, k)


## Sphere cast from `origin` to `desired` on Layers.CAMERA_MASK (+ the state hint's extra layers);
## pulls in at once, eases back out.
func _collide(origin: Vector3, desired: Vector3, delta: float) -> Vector3:
	var motion := desired - origin
	var frac := 1.0
	if motion.length_squared() > 0.0001 and is_inside_tree():
		_query.transform = Transform3D(Basis.IDENTITY, origin)
		_query.motion = motion
		_query.collision_mask = Layers.CAMERA_MASK | _hint_mask
		var res := get_world_3d().direct_space_state.cast_motion(_query)
		if res.size() >= 1:
			frac = clampf(float(res[0]), 0.0, 1.0)
	if frac < _dist_frac:
		_dist_frac = frac
	else:
		_dist_frac = minf(_dist_frac + DISTANCE_RECOVER * delta, frac)
	return origin + motion * _dist_frac


func _resolve_mode() -> String:
	if _forced_mode != "":
		return _forced_mode
	var veh := _vehicle()
	if veh != null:
		if first_person:
			return "first"
		var cls := str(veh.get("vehicle_class"))
		return "aircraft" if (cls == "heli" or cls == "plane") else "vehicle"
	if bool(player.get("is_dead")) or str(player.get("state_id")) == "ragdoll":
		return "third"
	if bool(player.get("is_aiming")):
		if _weapon_scoped():
			return "scope"
		return "first" if first_person else "aim"
	return "first" if first_person else "third"


func _on_mode_changed(from: String, to: String) -> void:
	var was_veh := from == "vehicle" or from == "aircraft"
	var is_veh := to == "vehicle" or to == "aircraft"
	var veh := _vehicle()
	if is_veh and not was_veh and veh != null:
		# keep looking where we looked; the idle centring then swings the camera behind the car
		var vf := -veh.global_basis.z
		_veh_heading = atan2(-vf.x, -vf.z)
		if from == "first" and _last_vehicle == veh:
			pass
		else:
			_veh_yaw_off = angle_difference(_veh_heading, yaw)
			_veh_pitch = clampf(pitch, PITCH_MIN, 0.6)
		_veh_pitch_follow = 0.0
		_look_idle = 0.0
	elif to == "first" and veh != null and not was_veh:
		_veh_yaw_off = 0.0
		_veh_pitch = -0.2
	if to == "third" or to == "aim":
		pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)
	_last_vehicle = veh


func _apply_body_visibility(hide_body: bool, hide_head: bool) -> void:
	if hide_body != _body_hidden:
		_body_hidden = hide_body
		if player.has_method("set_visual_hidden"):
			player.call("set_visual_hidden", "camera", hide_body)
	if hide_head != _head_hidden:
		_head_hidden = hide_head
		if player.has_method("set_head_hidden"):
			player.call("set_head_hidden", hide_head)


## Drive-by camera point inside an enclosed vehicle (see DRIVE_BY_CABIN_*), or Vector3.INF when the
## vehicle is open (bike, boat, aircraft) or another occupant's head is in the way (riding along as a
## passenger next to an AI driver: the camera would sit in the driver's head).
func _drive_by_cabin_point(veh: Node3D, view_yaw: float) -> Vector3:
	if veh == null or not is_instance_valid(veh) or DRIVE_BY_OPEN_CLASSES.has(str(veh.get("vehicle_class"))) or not DRIVE_BY_CABIN_SPECS.has(str(veh.get("spec_id"))):
		return Vector3.INF
	var eye := player.global_position + Vector3(0.0, 0.68, 0.0)
	var vis: Variant = player.get("visual")
	var anim: Variant = player.get("animator")
	if vis is Node3D and anim is Object and is_instance_valid(anim) and (anim as Object).has_method("get_eye_position"):
		var ep: Variant = (anim as Object).call("get_eye_position")
		if ep is Vector3:
			eye = (vis as Node3D).global_transform * (ep as Vector3)
	var back := Vector3(sin(view_yaw), 0.0, cos(view_yaw))     # flat, against the view
	var fwd := -veh.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.0001 and (-back).dot(fwd.normalized()) < DRIVE_BY_CABIN_MAX_COS:
		return Vector3.INF          # aiming out of the rear: the camera would end up in the dashboard
	var perp := Vector3(back.z, 0.0, -back.x)                  # flat, across the view
	# over the shoulder that faces the middle of the cabin (behind the front seats): the head stays off
	# the crosshair and the camera keeps clear of the doors / dashboard
	var rear := veh.global_basis.z
	rear.y = 0.0
	rear = rear.normalized() if rear.length_squared() > 0.0001 else Vector3.ZERO
	var mid := veh.global_position + rear * 0.5
	var to_mid := Vector3(mid.x - eye.x, 0.0, mid.z - eye.z)
	if to_mid.dot(perp) < 0.0:
		perp = -perp
	var p := eye + back * DRIVE_BY_CABIN_BACK + perp * DRIVE_BY_CABIN_SIDE + Vector3(0.0, DRIVE_BY_CABIN_UP, 0.0)
	if veh.has_method("get_occupants"):
		var occ: Variant = veh.call("get_occupants")
		if occ is Array:
			for o: Variant in (occ as Array):
				if o is Node3D and is_instance_valid(o) and o != player:
					var head := (o as Node3D).global_position + Vector3(0.0, 0.68, 0.0)
					if head.distance_to(p) < DRIVE_BY_CABIN_CLEAR:
						return Vector3.INF
	return p


## True while the drive-by camera looks out from inside the cabin (tests / HUD).
func is_drive_by_cabin() -> bool:
	return _db_cabin and is_drive_by_aiming()


## Camera hint of the active player state ({} = none; see PlayerState.get_camera_hint).
func _state_hint() -> Dictionary:
	var st: Variant = player.get("state")
	if st is Object and is_instance_valid(st) and (st as Object).has_method("get_camera_hint"):
		var h: Variant = (st as Object).call("get_camera_hint")
		if h is Dictionary:
			return h
	return {}


func _focus() -> Vector3:
	if player.has_method("get_camera_focus"):
		return player.call("get_camera_focus")
	return Game.get_player_position()


func _vehicle() -> Node3D:
	var v: Variant = player.get("current_vehicle")
	if v != null and is_instance_valid(v):
		return v as Node3D
	return null


func _aim_fov() -> float:
	var inv: Variant = player.get("inventory")
	if inv != null and is_instance_valid(inv):
		var n := inv as Node
		if n.has_method("get_aim_fov"):
			var f := float(n.call("get_aim_fov"))
			if f > 1.0:
				return f
		if n.has_method("get_current_spec"):
			var spec: Variant = n.call("get_current_spec")
			if spec is Object and spec != null:
				var af: Variant = (spec as Object).get("aim_fov")
				if (af is float or af is int) and float(af) > 1.0:
					return float(af)
	return AIM_FOV


func _weapon_scoped() -> bool:
	var inv: Variant = player.get("inventory")
	if inv == null or not is_instance_valid(inv):
		return false
	var n := inv as Node
	if n.has_method("is_scoped"):
		return bool(n.call("is_scoped"))
	if n.has_method("get_current_spec"):
		var spec: Variant = n.call("get_current_spec")
		if spec is Object and spec != null:
			return bool((spec as Object).get("scoped"))
	return false


# --- mouse capture fallback (the UI module owns the mouse mode; see the header) -------------------

func _may_capture() -> bool:
	if DisplayServer.get_name() == "headless" or TestHarness.is_testing():
		return false
	if ui_owns_mouse():
		return false
	if not Game.is_ready or Game.is_input_locked() or UI.is_screen_open(""):
		return false
	return true


## True when the UI module manages Input.mouse_mode itself (the real UI module does; the lead's
## first stub did not). The rig then never touches the mouse mode.
static func ui_owns_mouse() -> bool:
	return ("mouse_capture_enabled" in UI) or UI.has_method("_update_mouse_mode") or UI.has_method("set_mouse_capture")


func _fallback_capture() -> void:
	if _may_capture() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_self_captured = true


func _update_capture(delta: float) -> void:
	if _capture_checked or not Game.is_ready:
		return
	_capture_wait += delta
	if _capture_wait > 0.5:
		_capture_checked = true
		_fallback_capture()


func _on_screen_opened(_id: String) -> void:
	if _self_captured and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_screen_closed(_id: String) -> void:
	if _self_captured and not UI.is_screen_open(""):
		_fallback_capture.call_deferred()
