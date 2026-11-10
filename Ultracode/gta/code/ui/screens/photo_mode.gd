extends UiScreen
## Photo mode (F2, or the phone's Camera app). Pauses the game, hides the HUD and flies a free
## camera of its own (the gameplay rig does not run while paused) within RANGE metres of the
## player. Keys: WASD move, Space / C up / down, Shift faster, mouse or right stick look,
## Q / E roll, Z / X or the mouse wheel zoom (FOV), F / Shift+F or Left / Right filter, T focus
## (depth of field), G thirds grid, H hide the panel, R reset, Enter or left click take a photo,
## Esc / F2 leave. Photos are PNGs in user://photos/ (camera_shutter sound + toast).
## Filters are presets of one full-screen grade shader (shaders/photo_filter.gdshader).
## UI.open_screen("photo")  ->  get_screen("photo").take_photo()   (awaitable, returns the path)

signal photo_taken(path: String)

const PAUSES_GAME := true
const TIME_SCALE := 1.0
const LOCKS_INPUT := true
const SHOWS_MOUSE := false
const HIDES_HUD := true

const RANGE := 25.0
const FOV_MIN := 15.0
const FOV_MAX := 100.0
const ROLL_MAX := 45.0
const SPEED := 5.0
const PHOTO_DIR := "user://photos"
const FILTER_SHADER := "res://gta/code/ui/shaders/photo_filter.gdshader"
const PANEL_SIZE := Vector2(460.0, 476.0)

## Filter presets (original names). Keys are uniforms of photo_filter.gdshader.
const FILTERS: Array[Dictionary] = [
	{"name": "Natural"},
	{"name": "Golden Hour", "saturation": 1.15, "contrast": 1.06, "tint": Vector3(1.08, 0.98, 0.84), "highlight_tint": Vector3(0.06, 0.03, 0.0), "vignette": 0.35},
	{"name": "Harbour Noir", "mono": 1.0, "contrast": 1.35, "brightness": -0.02, "vignette": 0.6, "grain": 0.07},
	{"name": "Postcard", "saturation": 0.82, "lift": 0.09, "tint": Vector3(1.05, 1.0, 0.9), "shadow_tint": Vector3(0.0, 0.03, 0.06), "vignette": 0.3, "grain": 0.03},
	{"name": "Neon Nights", "saturation": 1.3, "contrast": 1.14, "shadow_tint": Vector3(0.0, 0.1, 0.14), "highlight_tint": Vector3(0.12, 0.0, 0.1), "vignette": 0.4},
	{"name": "Tropic Pop", "saturation": 1.5, "contrast": 1.1, "brightness": 0.02, "tint": Vector3(0.98, 1.02, 1.04)},
	{"name": "Low Tide", "saturation": 0.72, "tint": Vector3(0.9, 0.98, 1.08), "lift": 0.05, "shadow_tint": Vector3(0.0, 0.03, 0.07)},
	{"name": "Old Pier", "mono": 1.0, "mono_tint": Vector3(1.1, 0.92, 0.7), "contrast": 1.12, "lift": 0.06, "vignette": 0.7, "grain": 0.09},
]
const UNIFORM_DEFAULTS := {
	"saturation": 1.0, "contrast": 1.0, "brightness": 0.0, "lift": 0.0, "tint": Vector3.ONE,
	"shadow_tint": Vector3.ZERO, "highlight_tint": Vector3.ZERO, "mono": 0.0, "mono_tint": Vector3.ONE,
	"vignette": 0.0, "grain": 0.0,
}
const FOCUS_NAMES: Array[String] = ["Off", "Portrait", "Deep"]

var fov: float = 60.0
var roll: float = 0.0                ## degrees
var yaw: float = 0.0                 ## radians (0 looks at -Z)
var pitch: float = 0.0
var filter_index: int = 0
var dof_mode: int = 0              ## 0 off, 1 portrait (blur behind the subject), 2 deep (blur near + far)
var grid_on: bool = false
var ui_visible: bool = true
var photos_taken: int = 0
var last_photo_path: String = ""

var _cam: Camera3D = null
var _prev_cam: Camera3D = null
var _attrs: CameraAttributesPractical = null
var _start_pos: Vector3 = Vector3.ZERO
var _start_yaw: float = 0.0
var _start_pitch: float = 0.0
var _start_fov: float = 60.0
var _filter_rect: ColorRect = null
var _filter_mat: ShaderMaterial = null
var _grid: UiCanvas
var _ui_root: Control
var _panel: UiCanvas
var _flash: ColorRect
var _flash_a: float = 0.0
var _busy: bool = false
var _seed_t: float = 0.0
var _toast_hint: float = 0.0


func _init() -> void:
	super()
	backdrop_alpha = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_filter_rect = ColorRect.new()
	_filter_rect.name = "Filter"
	_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter_rect.color = Color.WHITE
	UiKit.fill(_filter_rect)
	if ResourceLoader.exists(FILTER_SHADER):
		var sh := load(FILTER_SHADER) as Shader
		if sh != null:
			_filter_mat = ShaderMaterial.new()
			_filter_mat.shader = sh
			_filter_rect.material = _filter_mat
	_filter_rect.visible = false
	add_child(_filter_rect)
	_grid = UiCanvas.new(_draw_grid)
	UiKit.fill(_grid)
	_grid.visible = false
	add_child(_grid)
	_ui_root = Control.new()
	_ui_root.name = "PhotoUi"
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.fill(_ui_root)
	add_child(_ui_root)
	_panel = UiCanvas.new(_draw_panel)
	_panel.position = Vector2(UiStyle.MARGIN, UiStyle.MARGIN)
	_panel.size = PANEL_SIZE
	_ui_root.add_child(_panel)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.GLASS, 16, UiStyle.LINE, 2, 0, 22, 8))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = UiStyle.MARGIN
	bar.offset_right = -UiStyle.MARGIN
	bar.offset_top = -UiStyle.MARGIN - 120.0
	bar.offset_bottom = -UiStyle.MARGIN
	_ui_root.add_child(bar)
	var rows := UiKit.vbox(2)
	bar.add_child(rows)
	rows.add_child(UiKeyHints.new([{"keys": ["W", "A", "S", "D"], "text": "Move"}, {"keys": ["Space", "C"], "text": "Up / down"},
			{"key": "Shift", "text": "Fast"}, {"key": "Mouse", "text": "Look"}, {"keys": ["Q", "E"], "text": "Roll"},
			{"keys": ["Z", "X"], "text": "Zoom"}, {"key": "R", "text": "Reset"}]))
	rows.add_child(UiKeyHints.new([{"key": "F", "text": "Filter"}, {"key": "T", "text": "Focus"}, {"key": "G", "text": "Grid"},
			{"key": "H", "text": "Hide panel"}, {"key": "Enter", "text": "Take photo"}, {"action": "pause", "text": "Exit"}]))
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.fill(_flash)
	_flash.visible = false
	add_child(_flash)


func open(args: Dictionary) -> void:
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.name = "PhotoCamera"
	_cam.near = 0.05
	_cam.far = 3000.0
	_attrs = CameraAttributesPractical.new()
	_cam.attributes = _attrs
	var host: Node = Game.get_entities_root()
	if host == null or not is_instance_valid(host):
		host = get_tree().root
	host.add_child(_cam)
	var start := Transform3D(Basis.IDENTITY, Game.get_player_position() + Vector3(0.0, 2.0, 4.0))
	if _prev_cam != null and is_instance_valid(_prev_cam):
		start = _prev_cam.global_transform
		fov = _prev_cam.fov
	var fwd := -start.basis.z
	yaw = atan2(-fwd.x, -fwd.z)
	pitch = asin(clampf(fwd.y, -1.0, 1.0))
	fov = clampf(float(args.get("fov", fov)), FOV_MIN, FOV_MAX)
	roll = 0.0
	_start_pos = _clamp_position(start.origin, start.origin)
	_start_yaw = yaw
	_start_pitch = pitch
	_start_fov = fov
	_cam.global_position = _start_pos
	_apply_camera()
	_cam.make_current()
	set_filter(int(args.get("filter", 0)))
	set_dof_mode(0)
	_panel.queue_redraw()


func close() -> void:
	var toasts: Control = UI.toasts
	if toasts != null:
		toasts.visible = true
	if _cam != null and is_instance_valid(_cam):
		_cam.clear_current(false)
		_cam.queue_free()
	_cam = null
	if _prev_cam != null and is_instance_valid(_prev_cam) and _prev_cam.is_inside_tree():
		_prev_cam.make_current()


func handle_back() -> bool:
	return _busy            # never leave in the middle of a capture


# --- public API (tests, phone) -----------------------------------------------------------------------

func get_camera() -> Camera3D:
	return _cam


func get_filter_name() -> String:
	return str(FILTERS[filter_index]["name"])


func set_filter(index: int) -> void:
	filter_index = posmod(index, FILTERS.size())
	var preset: Dictionary = FILTERS[filter_index]
	_filter_rect.visible = filter_index != 0 and _filter_mat != null
	if _filter_mat != null:
		for key: String in UNIFORM_DEFAULTS:
			_filter_mat.set_shader_parameter(key, preset.get(key, UNIFORM_DEFAULTS[key]))
	_panel.queue_redraw()


func cycle_filter(dir: int) -> void:
	set_filter(filter_index + dir)
	UiKit.sfx("ui_tab")


func set_dof_mode(mode: int) -> void:
	dof_mode = posmod(mode, FOCUS_NAMES.size())
	_update_focus()
	_panel.queue_redraw()


func set_fov(value: float) -> void:
	fov = clampf(value, FOV_MIN, FOV_MAX)
	_apply_camera()


func set_roll(deg: float) -> void:
	roll = clampf(deg, -ROLL_MAX, ROLL_MAX)
	_apply_camera()


func set_ui_visible(on: bool) -> void:
	ui_visible = on
	_ui_root.visible = on
	var toasts: Control = UI.toasts
	if toasts != null:
		toasts.visible = on            # "hide panel" = a clean frame, toasts included


func set_grid(on: bool) -> void:
	grid_on = on
	_grid.visible = on
	_panel.queue_redraw()


## Move the camera (clamped to RANGE around the player, kept above the ground, stopped by walls).
func move_camera_to(pos: Vector3) -> void:
	if _cam == null:
		return
	_cam.global_position = _clamp_position(_cam.global_position, pos)
	_update_focus()
	_panel.queue_redraw()


func get_subject_point() -> Vector3:
	return Game.get_player_position() + Vector3(0.0, 1.2, 0.0)


func distance_to_subject() -> float:
	return _cam.global_position.distance_to(get_subject_point()) if _cam != null else 0.0


func reset_camera() -> void:
	yaw = _start_yaw
	pitch = _start_pitch
	roll = 0.0
	fov = _start_fov
	if _cam != null:
		_cam.global_position = _start_pos
	_apply_camera()


## Capture the frame (without the photo-mode panel) to user://photos/. Awaitable; returns the
## saved path, or "" when nothing could be captured (headless runs have no frame to read).
func take_photo() -> String:
	if _busy:
		return ""
	_busy = true
	var keep_ui := ui_visible
	var keep_grid := grid_on
	_ui_root.visible = false
	_grid.visible = false
	var toasts: Control = UI.toasts
	var toasts_vis := toasts != null and toasts.visible
	if toasts != null:
		toasts.visible = false
	var path := ""
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return ""
		var img := get_viewport().get_texture().get_image()
		if img != null and not img.is_empty():
			path = save_image(img)
	_ui_root.visible = keep_ui
	_grid.visible = keep_grid
	if toasts != null:
		toasts.visible = toasts_vis
	_flash_a = 1.0
	_flash.visible = true
	UiKit.sfx("camera_shutter", 0.0)
	last_photo_path = path
	if path != "":
		photos_taken += 1
		UI.notify("Photo saved  -  photos/%s" % path.get_file(), "good", 3.0)
	elif DisplayServer.get_name() == "headless":
		photos_taken += 1          # the state machine ran; there is just no frame to save
	else:
		UI.notify("The photo could not be saved", "bad", 3.0)
	_busy = false
	_panel.queue_redraw()
	photo_taken.emit(path)
	return path


## Write an image as a PNG into user://photos/ ("halcyon_<date>_<time>_<n>.png"). "" on failure.
func save_image(img: Image) -> String:
	if img == null or img.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(PHOTO_DIR)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_").replace("-", "")
	var path := "%s/halcyon_%s_%03d.png" % [PHOTO_DIR, stamp, photos_taken + 1]
	var n := 1
	while FileAccess.file_exists(path) and n < 50:
		n += 1
		path = "%s/halcyon_%s_%03d_%d.png" % [PHOTO_DIR, stamp, photos_taken + 1, n]
	return path if img.save_png(path) == OK else ""


func is_busy() -> bool:
	return _busy


# --- input / frame -------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var sens := float(Settings.get_value("mouse_sensitivity"))
		if sens <= 0.0:
			sens = 0.0025
		sens *= clampf(fov / 70.0, 0.25, 1.2)
		var inv := -1.0 if bool(Settings.get_value("invert_y")) else 1.0
		var rel := mm.screen_relative if mm.screen_relative != Vector2.ZERO else mm.relative
		yaw = wrapf(yaw - rel.x * sens, -PI, PI)
		pitch = clampf(pitch - rel.y * sens * inv, deg_to_rad(-85.0), deg_to_rad(85.0))
		_apply_camera()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_fov(fov - 2.5)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_fov(fov + 2.5)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			take_photo()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := event as InputEventKey
		var used := true
		match k.physical_keycode:
			KEY_F:
				cycle_filter(-1 if k.shift_pressed else 1)
			KEY_RIGHT:
				cycle_filter(1)
			KEY_LEFT:
				cycle_filter(-1)
			KEY_T:
				set_dof_mode(dof_mode + 1)
				UiKit.sfx("ui_tab")
			KEY_G:
				set_grid(not grid_on)
				UiKit.sfx("ui_click")
			KEY_H:
				set_ui_visible(not ui_visible)
			KEY_R:
				reset_camera()
				UiKit.sfx("ui_click")
			KEY_ENTER, KEY_KP_ENTER:
				take_photo()
			_:
				used = false
		if used:
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _flash_a > 0.0:
		_flash_a = maxf(_flash_a - delta * 3.2, 0.0)
		_flash.color.a = _flash_a * 0.85
		_flash.visible = _flash_a > 0.0
	if _filter_rect.visible and _filter_mat != null:
		_seed_t += delta
		_filter_mat.set_shader_parameter(&"grain_seed", floorf(_seed_t * 24.0))
	if _cam == null or _busy:
		return
	var dirty := false
	# look with the right stick
	var lx := Input.get_axis(&"look_left", &"look_right")
	var ly := Input.get_axis(&"look_down", &"look_up")
	if absf(lx) > 0.05 or absf(ly) > 0.05:
		yaw = wrapf(yaw - lx * 2.2 * delta, -PI, PI)
		pitch = clampf(pitch + ly * 1.6 * delta, deg_to_rad(-85.0), deg_to_rad(85.0))
		dirty = true
	# roll / zoom (held keys)
	var r_in := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	if r_in != 0.0:
		roll = clampf(roll + r_in * 40.0 * delta, -ROLL_MAX, ROLL_MAX)
		dirty = true
	var z_in := float(Input.is_physical_key_pressed(KEY_X)) - float(Input.is_physical_key_pressed(KEY_Z))
	if z_in != 0.0:
		fov = clampf(fov + z_in * 30.0 * delta, FOV_MIN, FOV_MAX)
		dirty = true
	# fly
	var mv := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var up := float(Input.is_action_pressed(&"jump")) - float(Input.is_action_pressed(&"crouch"))
	if mv != Vector2.ZERO or up != 0.0:
		var sp := SPEED * (3.0 if Input.is_action_pressed(&"sprint") else 1.0)
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		var step := (b * Vector3(mv.x, 0.0, mv.y) + Vector3(0.0, up, 0.0)) * sp * delta
		_cam.global_position = _clamp_position(_cam.global_position, _cam.global_position + step)
		_update_focus()
		dirty = true
	if dirty:
		_apply_camera()
		_panel.queue_redraw()


func _apply_camera() -> void:
	if _cam == null:
		return
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, deg_to_rad(roll))
	_cam.global_transform = Transform3D(b.orthonormalized(), _cam.global_position)
	_cam.fov = fov
	_panel.queue_redraw()


## Keep `to` inside the sphere around the player, above the terrain and on this side of walls.
func _clamp_position(from: Vector3, to: Vector3) -> Vector3:
	var centre := get_subject_point()
	var p := to
	if p.distance_to(centre) > RANGE:
		p = centre + (p - centre).normalized() * RANGE
	if _cam != null and _cam.is_inside_tree() and from.distance_squared_to(p) > 0.0001:
		var space := _cam.get_world_3d().direct_space_state
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(from, p, Layers.CAMERA_MASK)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				p = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.25
	var g := Game.ground_height(p.x, p.z)
	if p.y < g + 0.3:
		p.y = g + 0.3
	return p


func _update_focus() -> void:
	if _attrs == null:
		return
	var d := distance_to_subject()
	match dof_mode:
		1:
			_attrs.dof_blur_far_enabled = true
			_attrs.dof_blur_far_distance = d + 2.5
			_attrs.dof_blur_far_transition = maxf(d * 0.8, 4.0)
			_attrs.dof_blur_near_enabled = false
			_attrs.dof_blur_amount = 0.12
		2:
			_attrs.dof_blur_far_enabled = true
			_attrs.dof_blur_far_distance = d + 12.0
			_attrs.dof_blur_far_transition = 30.0
			_attrs.dof_blur_near_enabled = true
			_attrs.dof_blur_near_distance = maxf(d - 1.5, 0.5)
			_attrs.dof_blur_near_transition = maxf(d * 0.5, 1.0)
			_attrs.dof_blur_amount = 0.09
		_:
			_attrs.dof_blur_far_enabled = false
			_attrs.dof_blur_near_enabled = false


# --- drawing -------------------------------------------------------------------------------------------

func _draw_grid(c: UiCanvas) -> void:
	var sz := c.size
	var col := Color(1, 1, 1, 0.32)
	for i in [1, 2]:
		c.draw_line(Vector2(sz.x * i / 3.0, 0.0), Vector2(sz.x * i / 3.0, sz.y), col, 2.0)
		c.draw_line(Vector2(0.0, sz.y * i / 3.0), Vector2(sz.x, sz.y * i / 3.0), col, 2.0)
	var m := 60.0
	var l := 70.0
	var fc := Color(1, 1, 1, 0.75)
	for corner: Vector2 in [Vector2(m, m), Vector2(sz.x - m, m), Vector2(m, sz.y - m), Vector2(sz.x - m, sz.y - m)]:
		var dx := 1.0 if corner.x < sz.x * 0.5 else -1.0
		var dy := 1.0 if corner.y < sz.y * 0.5 else -1.0
		c.draw_line(corner, corner + Vector2(l * dx, 0.0), fc, 3.0)
		c.draw_line(corner, corner + Vector2(0.0, l * dy), fc, 3.0)
	var ctr := sz * 0.5
	c.draw_line(ctr - Vector2(14, 0), ctr + Vector2(14, 0), fc, 2.0)
	c.draw_line(ctr - Vector2(0, 14), ctr + Vector2(0, 14), fc, 2.0)


func _draw_panel(c: UiCanvas) -> void:
	var sz := c.size
	c.draw_style_box(UiStyle.cached_box(&"glass"), Rect2(Vector2.ZERO, sz))
	var head := UiStyle.font(&"head")
	var num := UiStyle.font(&"num")
	var body := UiStyle.font(&"body")
	UiIcons.draw(c, &"camera", Vector2(46.0, 46.0), 40.0, UiStyle.CORAL)
	c.draw_string(head, Vector2(80.0, 58.0), "PHOTO MODE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiStyle.FS_H3, UiStyle.TEXT)
	c.draw_style_box(UiStyle._fill_box(UiStyle.CORAL), Rect2(24.0, 84.0, 64.0, 5.0))
	var y := 112.0
	var lx := 26.0
	var rx := sz.x - 26.0
	# sliders
	y = _slider_row(c, y, "FIELD OF VIEW", "%d°" % int(round(fov)), inverse_lerp(FOV_MIN, FOV_MAX, fov), UiStyle.TEAL_LIGHT, false)
	y = _slider_row(c, y, "ROLL", "%+d°" % int(round(roll)) if absf(roll) >= 0.5 else "0°", inverse_lerp(-ROLL_MAX, ROLL_MAX, roll), UiStyle.SUN, true)
	var dist := distance_to_subject()
	y = _slider_row(c, y, "RANGE", "%d / %d m" % [int(round(dist)), int(RANGE)], dist / RANGE,
			UiStyle.CORAL if dist > RANGE - 1.5 else UiStyle.CREAM, false)
	# option rows
	y += 4.0
	y = _option_row(c, y, "FILTER", get_filter_name(), true)
	y = _option_row(c, y, "FOCUS", FOCUS_NAMES[dof_mode], false)
	y = _option_row(c, y, "GRID", "On" if grid_on else "Off", false)
	c.draw_line(Vector2(lx, y + 4.0), Vector2(rx, y + 4.0), UiStyle.LINE, 2.0)
	UiStyle.text(c, body, Vector2(lx, y + 34.0), "Photos this session", UiStyle.FS_SMALL, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
	UiStyle.text(c, num, Vector2(lx, y + 34.0), str(photos_taken), UiStyle.FS_BODY, UiStyle.SUN, HORIZONTAL_ALIGNMENT_RIGHT, rx - lx, false)


func _slider_row(c: CanvasItem, y: float, label: String, value: String, frac: float, col: Color, centred: bool) -> float:
	var head := UiStyle.font(&"head")
	var num := UiStyle.font(&"num")
	var w := PANEL_SIZE.x - 52.0
	c.draw_string(head, Vector2(26.0, y + 16.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiStyle.FS_TINY, UiStyle.MUTED)
	c.draw_string(num, Vector2(26.0, y + 16.0), value, HORIZONTAL_ALIGNMENT_RIGHT, w, UiStyle.FS_SMALL, UiStyle.TEXT)
	var bar := Rect2(26.0, y + 26.0, w, 8.0)
	if centred:
		c.draw_style_box(UiStyle.cached_box(&"track_dark"), bar)
		var mid := bar.position.x + bar.size.x * 0.5
		var px := bar.position.x + bar.size.x * clampf(frac, 0.0, 1.0)
		c.draw_rect(Rect2(minf(mid, px), bar.position.y, absf(px - mid), bar.size.y), col)
		c.draw_circle(Vector2(px, bar.get_center().y), 8.0, UiStyle.CREAM, true, -1.0, true)
	else:
		UiStyle.draw_bar(c, bar, frac, col)
	return y + 50.0


func _option_row(c: CanvasItem, y: float, label: String, value: String, arrows: bool) -> float:
	var head := UiStyle.font(&"head")
	var bold := UiStyle.font(&"bold")
	var w := PANEL_SIZE.x - 52.0
	var r := Rect2(18.0, y, w + 16.0, 40.0)
	c.draw_style_box(UiStyle.cached_box(&"chip"), r)
	UiStyle.text_in(c, head, Rect2(32.0, y, 160.0, 40.0), label, UiStyle.FS_TINY, UiStyle.MUTED)
	var vx := r.end.x - 14.0
	if arrows:
		UiIcons.draw(c, &"chev_right", Vector2(vx - 8.0, y + 20.0), 16.0, UiStyle.CORAL)
		vx -= 26.0
	var tw := UiStyle.text_width(bold, value, UiStyle.FS_SMALL)
	UiStyle.text_in(c, bold, Rect2(vx - tw, y, tw, 40.0), value, UiStyle.FS_SMALL, UiStyle.TEXT)
	if arrows:
		UiIcons.draw(c, &"chev_left", Vector2(vx - tw - 18.0, y + 20.0), 16.0, UiStyle.CORAL)
	return y + 48.0
