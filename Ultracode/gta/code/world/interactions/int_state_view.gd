extends PlayerState
## Player state "int_view" (interactions system): looking through the coin-op viewpoint
## binoculars. The player stands at the binoculars' `Use` marker; the camera is forced into the
## "scope" mode (body hidden, view from the eyes) with a FOV override that the mouse wheel / aim
## button zooms through ZOOM_FOVS. Mouse look stays free but is clamped to a cone around the
## binoculars' direction. Registered at runtime like int_state_sit.gd.
##
## enter args: {"stand": Transform3D (Use marker, -Z = looking direction), "point": int}
## Leaves on: the "Step away" use prompt (the system calls change_state("on_foot")), movement input
## held for a moment, any damage.

const ZOOM_FOVS: Array[float] = [34.0, 20.0, 11.0, 6.5]
const YAW_LIMIT := 1.25                 ## rad either side of the binoculars' direction
const PITCH_MIN := -0.45
const PITCH_MAX := 0.35
const LEAVE_INPUT_TIME := 0.25

var look_yaw: float = 0.0
var zoom_index: int = 1
var point_index: int = -1
var view_time: float = 0.0

var _leave_t: float = 0.0


func _init() -> void:
	public_name = "binoculars"


func enter(_previous: String, args: Dictionary) -> void:
	var p := player
	var stand: Transform3D = args.get("stand", p.global_transform)
	point_index = int(args.get("point", -1))
	zoom_index = 1
	view_time = 0.0
	_leave_t = 0.0
	p.is_sprinting = false
	p.set_aiming(false)
	p.release_trigger()
	if p.is_crouching:
		p.set_crouching(false, true)
	var f := -stand.basis.z
	f.y = 0.0
	look_yaw = atan2(-f.x, -f.z) if f.length_squared() > 0.0001 else p.global_rotation.y
	p.velocity = Vector3.ZERO
	p.global_position = stand.origin + Vector3(0.0, 0.03, 0.0)
	p.global_rotation = Vector3(0.0, look_yaw, 0.0)
	p.set_anim_state("idle", 0.2)
	var cam: Variant = p.camera
	if cam != null and is_instance_valid(cam):
		cam.call("snap_to", look_yaw)
		cam.set("pitch", -0.05)
		cam.call("set_mode", "scope")
		cam.call("set_fov_override", ZOOM_FOVS[zoom_index], 1.0)
	Audio.play("camera_shutter", -14.0, 0.7, "SFX")


func exit(_next: String) -> void:
	var cam: Variant = player.camera
	if cam != null and is_instance_valid(cam):
		cam.call("set_mode", "")
		cam.call("set_fov_override", 70.0, 0.0)
		# no snap: stepping away keeps the view direction, and a teleport already snapped the camera
	point_index = -1


func physics_update(delta: float) -> void:
	var p := player
	view_time += delta
	p.velocity.x = 0.0
	p.velocity.z = 0.0
	p.set_anim_state("idle")
	var mv: Vector2 = p.get_move_input()
	if mv.length() > 0.5 or p.pressed(&"jump"):
		_leave_t += delta
		if _leave_t >= LEAVE_INPUT_TIME and view_time > 0.4:
			p.change_state("on_foot", {})
			return
	else:
		_leave_t = 0.0
	# RMB / left trigger cycles the zoom; the mouse wheel steps it (interaction_system._unhandled_input)
	if p.just_pressed(&"aim"):
		set_zoom((zoom_index + 1) % ZOOM_FOVS.size())
	var cam: Variant = p.camera
	if cam != null and is_instance_valid(cam):
		var cy := float(cam.get("yaw"))
		var off := clampf(angle_difference(look_yaw, cy), -YAW_LIMIT, YAW_LIMIT)
		cam.set("yaw", wrapf(look_yaw + off, -PI, PI))
		cam.set("pitch", clampf(float(cam.get("pitch")), PITCH_MIN, PITCH_MAX))
		# the body turns with the view so the eye point stays behind the eyepieces
		p.global_rotation = Vector3(0.0, wrapf(look_yaw + off, -PI, PI), 0.0)


## 0 = widest .. ZOOM_FOVS.size() - 1 = strongest.
func set_zoom(i: int) -> void:
	var n := clampi(i, 0, ZOOM_FOVS.size() - 1)
	if n == zoom_index:
		return
	zoom_index = n
	var cam: Variant = player.camera
	if cam != null and is_instance_valid(cam):
		cam.call("set_fov_override", ZOOM_FOVS[zoom_index], 1.0)
	Audio.play("ui_tab", -12.0, 1.2 + 0.08 * zoom_index, "UI")


func get_fov() -> float:
	return ZOOM_FOVS[zoom_index]


func on_damage(_info: Dictionary, _amount: float) -> void:
	if player.state == self:
		player.change_state("on_foot", {})
