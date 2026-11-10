extends SubViewportContainer
## Small 3D preview for the shop screens (ECONOMY A).
##
## A SubViewport (<= 512 px, own_world_3d, transparent background) with its own camera, two
## directional lights and an environment, so it never renders the city. It lives inside the screen
## and is freed with it, i.e. it only renders while a shop screen is open. Shows
##   * show_weapon(id, attachments)   the Blender weapon GLB through WeaponModel (loaded softly),
##                                    attachment meshes + finish applied by WeaponModel itself
##   * show_model(path)               any GLB (pickup props: medkit, armour vest, parachute pack ...)
##   * show_character(appearance, focus) a CharacterVisual clone (humanoid.tscn) in a relaxed pose,
##                                    "full" body or "head" close-up
## The content turns slowly (turntable); dragging with the left mouse button rotates it.

const WEAPON_MODEL_SCRIPT := "res://gta/code/weapons/weapon_model.gd"
const HUMANOID_SCENE := "res://gta/scenes/characters/humanoid.tscn"
const MAX_PX := 512

var viewport: SubViewport
var camera: Camera3D
var pivot: Node3D
var content: Node3D = null
var mode: String = ""                 ## "", "weapon", "model", "character"
var spin_base: float = 0.0
var spin_amp: float = 0.55
var spin_speed: float = 0.55
var auto_spin: bool = true

var _key: String = ""
var _t: float = 0.0
var _drag: float = 0.0
var _dragging: bool = false
var _center: Vector3 = Vector3.ZERO
var _view_dir: Vector3 = Vector3(1, 0.2, 0)
var _radius: float = 0.5


func _init(px_size: Vector2i = Vector2i(440, 440)) -> void:
	var px := Vector2i(mini(px_size.x, MAX_PX), mini(px_size.y, MAX_PX))
	stretch = true
	custom_minimum_size = Vector2(px)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.name = "PreviewViewport"
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.size = px
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.handle_input_locally = false
	add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.78)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.94, 0.86)
	key.light_energy = 1.35
	key.shadow_enabled = false
	key.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(42.0), 0.0)
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.78, 1.0)
	fill.light_energy = 0.55
	fill.shadow_enabled = false
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(-140.0), 0.0)
	viewport.add_child(fill)
	pivot = Node3D.new()
	pivot.name = "Pivot"
	viewport.add_child(pivot)
	camera = Camera3D.new()
	camera.fov = 28.0
	camera.near = 0.02
	camera.far = 60.0
	camera.current = true
	viewport.add_child(camera)


func _process(delta: float) -> void:
	if content == null:
		return
	var real := delta / maxf(Engine.time_scale, 0.05)
	if auto_spin and not _dragging:
		_t += real
	pivot.rotation.y = spin_base + (sin(_t * spin_speed) * spin_amp if auto_spin else 0.0) + _drag


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag += (event as InputEventMouseMotion).relative.x * 0.012
		accept_event()


func clear() -> void:
	if content != null and is_instance_valid(content):
		content.queue_free()
	content = null
	mode = ""
	_key = ""


func has_content() -> bool:
	return content != null and is_instance_valid(content)


# --- weapons ---------------------------------------------------------------------------------

## Returns false when the weapon has no model (nothing is shown then - no stand-in).
func show_weapon(weapon_id: String, attachments: Array = []) -> bool:
	var key := "weapon:" + weapon_id
	if mode == "weapon" and _key == key and has_content():
		if content.has_method("set_attachments"):
			content.call("set_attachments", attachments)
		return bool(content.call("has_model")) if content.has_method("has_model") else true
	clear()
	if not ResourceLoader.exists(WEAPON_MODEL_SCRIPT):
		return false
	var scr := load(WEAPON_MODEL_SCRIPT) as Script
	if scr == null:
		return false
	var m: Variant = scr.call("create", weapon_id, attachments)
	if not (m is Node3D):
		return false
	var node := m as Node3D
	if node.has_method("has_model") and not bool(node.call("has_model")):
		node.free()
		return false
	_set_content(node, "weapon", key)
	_view_dir = Vector3(1.0, 0.16, 0.12).normalized()
	spin_base = 0.0
	spin_amp = 0.45
	_frame(1.0)
	return true


# --- any GLB ---------------------------------------------------------------------------------

func show_model(path: String) -> bool:
	var key := "model:" + path
	if mode == "model" and _key == key and has_content():
		return true
	clear()
	if path == "" or not ResourceLoader.exists(path):
		return false
	var ps := load(path) as PackedScene
	if ps == null:
		return false
	var node := ps.instantiate() as Node3D
	if node == null:
		return false
	_set_content(node, "model", key)
	_view_dir = Vector3(0.7, 0.55, -0.9).normalized()
	spin_base = 0.0
	spin_amp = 0.9
	_frame(1.25)
	return true


# --- characters ------------------------------------------------------------------------------

## focus: "full" (whole body) or "head" (barber close-up).
func show_character(appearance: Dictionary, focus: String = "full") -> bool:
	var key := "character:" + focus
	if mode == "character" and _key.begins_with("character:") and has_content():
		if content.has_method("apply_appearance"):
			content.call("apply_appearance", appearance)
		if _key != key:
			_key = key
			_frame_character(focus)
		return true
	clear()
	if not ResourceLoader.exists(HUMANOID_SCENE):
		return false
	var ps := load(HUMANOID_SCENE) as PackedScene
	if ps == null:
		return false
	var node := ps.instantiate() as Node3D
	if node == null:
		return false
	pivot.add_child(node)
	content = node
	mode = "character"
	_key = key
	if node.has_method("apply_appearance"):
		node.call("apply_appearance", appearance)
	if node.has_method("set_static_pose"):
		node.call("set_static_pose", "relaxed")
	_frame_character(focus)
	return true


func _frame_character(focus: String) -> void:
	content.position = Vector3.ZERO
	spin_base = 0.0
	if focus == "head":
		_center = Vector3(0.0, 1.57, 0.0)
		_radius = 0.37
		_view_dir = Vector3(0.0, 0.05, -1.0).normalized()
		spin_amp = 0.75
	else:
		_center = Vector3(0.0, 0.93, 0.0)
		_radius = 0.88
		_view_dir = Vector3(0.0, 0.1, -1.0).normalized()
		spin_amp = 0.6
	_place_camera(1.0)


# --- framing ---------------------------------------------------------------------------------

func _set_content(node: Node3D, p_mode: String, key: String) -> void:
	pivot.add_child(node)
	content = node
	mode = p_mode
	_key = key


## Centres the content's bounds on the pivot and places the camera so the box fills the view
## (projected on the camera's right / up axes, both field-of-view directions respected).
func _frame(margin: float) -> void:
	if not has_content():
		return
	content.position = Vector3.ZERO
	var box := _bounds(content)
	if box.size.length() < 0.001:
		box = AABB(Vector3(-0.25, -0.25, -0.25), Vector3(0.5, 0.5, 0.5))
	content.position = -box.get_center()
	_center = Vector3.ZERO
	_radius = maxf(box.size.length() * 0.5, 0.05)
	var fwd := -_view_dir
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd).normalized()
	var hx := 0.0
	var hy := 0.0
	var hz := 0.0
	var half := box.size * 0.5
	for i in 8:
		var corner := Vector3(half.x * (1.0 if i & 1 else -1.0), half.y * (1.0 if i & 2 else -1.0), half.z * (1.0 if i & 4 else -1.0))
		hx = maxf(hx, absf(corner.dot(right)))
		hy = maxf(hy, absf(corner.dot(up)))
		hz = maxf(hz, absf(corner.dot(fwd)))
	var vfov := deg_to_rad(camera.fov) * 0.5
	var aspect := float(viewport.size.x) / maxf(float(viewport.size.y), 1.0)
	var hfov := atan(tan(vfov) * aspect)
	var dist := maxf(hx / tan(hfov), hy / tan(vfov)) * margin + hz
	camera.position = _center + _view_dir * dist
	camera.look_at(_center, Vector3.UP)


func _place_camera(margin: float) -> void:
	var dist := _radius / sin(deg_to_rad(camera.fov * 0.5)) * margin
	camera.position = _center + _view_dir * dist
	camera.look_at(_center, Vector3.UP)


func _bounds(root: Node3D) -> AABB:
	var inv := pivot.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for n in root.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if not vi.is_visible_in_tree() or vi is Light3D:
			continue
		var b := (inv * vi.global_transform) * vi.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out
