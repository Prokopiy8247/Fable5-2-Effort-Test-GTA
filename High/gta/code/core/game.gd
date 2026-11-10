extends Node
## Global game state, input map, UI focus stack and shared helpers (autoload "Game").

const WATER_Y := -0.9
const L_WORLD := 1
const L_VEHICLE := 2
const L_CHAR := 4
const L_PROP := 8
const L_TRIGGER := 16
const L_RAGDOLL := 32
const L_SOFT := 64
const MASK_SOLID := L_WORLD | L_VEHICLE | L_PROP | L_SOFT
const MASK_SHOT := L_WORLD | L_VEHICLE | L_CHAR | L_PROP | L_SOFT

signal toast(text: String, color: Color)
signal big_text(title: String, sub: String, color: Color)
signal money_changed(amount: int)
signal noise_event(pos: Vector3, radius: float, kind: String)

var player = null
var world = null
var hud = null
var cam = null
var traffic = null
var peds = null
var wildlife = null
var daynight = null
var money: int = 2500
var vehicles: Array = []
var npcs: Array = []
var ui_stack: Array[String] = []
var flags := {"invuln": false, "traffic": true, "peds": true, "wildlife": true, "show_fps": false, "show_coords": false,
	"unlock_all": false, "scuba": false}
var settings := {"mouse_sens": 0.0025, "master_volume": 0.8, "max_fps": 60, "vsync": true, "render_scale": 1.0,
	"invert_y": false, "radio_station": 0, "shadows": true, "fov": 70.0}
var skills := {"stamina": 20.0, "shooting": 20.0, "strength": 20.0, "stealth": 20.0, "driving": 20.0, "flying": 20.0, "lung": 20.0}
var stats := {"kills": 0, "vehicles_destroyed": 0, "distance_driven": 0.0, "stunt_jumps": 0, "best_range_score": 0, "busted": 0, "deaths": 0,
	"best_trial": 0.0, "stunts_found": []}
var waypoint = null  # Vector3 or null
var rng := RandomNumberGenerator.new()
var autotest := ""
var slowmo := 1.0


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	RenderingServer.global_shader_parameter_add("wetness", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	_setup_input()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			autotest = a.substr(11)
	apply_settings()


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()


func apply_settings() -> void:
	Engine.max_fps = clampi(int(settings.max_fps), 30, 144)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(settings.master_volume, 0.0, 1.0)))
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = clampf(settings.render_scale, 0.5, 1.0)


func _key(action: String, keys: Array, mouse: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.3)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in mouse:
		var mb := InputEventMouseButton.new()
		mb.button_index = b
		InputMap.action_add_event(action, mb)


func _pad(action: String, button: int = -1, axis: int = -1, axis_val: float = 0.0) -> void:
	if button >= 0:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		InputMap.action_add_event(action, e)
	if axis >= 0:
		var m := InputEventJoypadMotion.new()
		m.axis = axis
		m.axis_value = axis_val
		InputMap.action_add_event(action, m)


func _setup_input() -> void:
	_key("move_fwd", [KEY_W])
	_key("move_back", [KEY_S])
	_key("move_left", [KEY_A])
	_key("move_right", [KEY_D])
	_key("sprint", [KEY_SHIFT])
	_key("jump", [KEY_SPACE])
	_key("crouch", [KEY_C, KEY_CTRL])
	_key("enter_vehicle", [KEY_F])
	_key("interact", [KEY_E])
	_key("fire", [], [MOUSE_BUTTON_LEFT])
	_key("aim", [], [MOUSE_BUTTON_RIGHT])
	_key("reload", [KEY_R])
	_key("cover", [KEY_Q])
	_key("weapon_wheel", [KEY_TAB])
	_key("weapon_next", [], [MOUSE_BUTTON_WHEEL_DOWN])
	_key("weapon_prev", [], [MOUSE_BUTTON_WHEEL_UP])
	_key("map", [KEY_M])
	_key("pause", [KEY_ESCAPE])
	_key("camera_toggle", [KEY_V])
	_key("horn", [KEY_H])
	_key("headlights", [KEY_L])
	_key("phone", [KEY_UP, KEY_P])
	_key("admin", [KEY_F1])
	_key("radio_next", [KEY_PERIOD])
	_key("radio_prev", [KEY_COMMA])
	_key("look_back", [KEY_B])
	_key("handbrake", [KEY_SPACE])
	_key("melee_alt", [], [MOUSE_BUTTON_MIDDLE])
	_key("roll_left", [KEY_Q])
	_key("roll_right", [KEY_E])
	_key("siren", [KEY_G])
	_key("flip", [KEY_T])
	_key("quicksave", [KEY_F5])
	_key("quickload", [KEY_F9])
	_key("photo", [KEY_F12])
	_key("fullscreen", [KEY_F11])
	_key("pitch_up", [KEY_DOWN])
	_key("pitch_down", [KEY_UP])
	_key("skip", [KEY_ENTER])
	for i in range(10):
		_key("slot_%d" % i, [KEY_0 + i])
	# basic controller support
	_pad("move_fwd", -1, JOY_AXIS_LEFT_Y, -1.0)
	_pad("move_back", -1, JOY_AXIS_LEFT_Y, 1.0)
	_pad("move_left", -1, JOY_AXIS_LEFT_X, -1.0)
	_pad("move_right", -1, JOY_AXIS_LEFT_X, 1.0)
	_pad("jump", JOY_BUTTON_A)
	_pad("enter_vehicle", JOY_BUTTON_Y)
	_pad("interact", JOY_BUTTON_X)
	_pad("crouch", JOY_BUTTON_LEFT_STICK)
	_pad("sprint", JOY_BUTTON_B)
	_pad("fire", -1, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_pad("aim", -1, JOY_AXIS_TRIGGER_LEFT, 1.0)
	_pad("reload", JOY_BUTTON_RIGHT_SHOULDER)
	_pad("weapon_wheel", JOY_BUTTON_LEFT_SHOULDER)
	_pad("pause", JOY_BUTTON_START)
	_pad("map", JOY_BUTTON_BACK)


# ------------------------------------------------------------------ UI focus
func ui_open(id: String) -> void:
	if not ui_stack.has(id):
		ui_stack.append(id)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func ui_close(id: String) -> void:
	ui_stack.erase(id)
	if ui_stack.is_empty() and autotest == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func ui_blocked() -> bool:
	return not ui_stack.is_empty()


# ------------------------------------------------------------------ economy / feedback
func add_money(n: int) -> void:
	money = max(0, money + n)
	money_changed.emit(money)


func spend(n: int) -> bool:
	if flags.unlock_all:
		return true
	if money < n:
		say("Not enough cash ($%d needed)" % n, Color(1, 0.45, 0.4))
		Sfx.ui("deny")
		return false
	add_money(-n)
	Sfx.ui("buy")
	return true


func say(text: String, color: Color = Color.WHITE) -> void:
	toast.emit(text, color)


func banner(title: String, sub: String = "", color: Color = Color.WHITE) -> void:
	big_text.emit(title, sub, color)


func skill_up(id: String, amount: float) -> void:
	var before: float = skills[id]
	skills[id] = clampf(before + amount, 0.0, 100.0)
	if int(skills[id] / 10.0) > int(before / 10.0):
		say("%s skill improved: %d%%" % [id.capitalize(), int(skills[id])], Color(0.5, 0.9, 1.0))


func skill(id: String) -> float:
	return skills[id] / 100.0


# ------------------------------------------------------------------ world helpers
func noise(pos: Vector3, radius: float, kind: String = "gunshot") -> void:
	noise_event.emit(pos, radius, kind)


func ray(from: Vector3, to: Vector3, mask: int = MASK_SOLID, exclude: Array = [], areas: bool = false) -> Dictionary:
	if world == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	var ex: Array[RID] = []
	for e in exclude:
		if e != null and is_instance_valid(e) and e is CollisionObject3D:
			ex.append(e.get_rid())
	q.exclude = ex
	q.collide_with_areas = areas
	return world.get_world_3d().direct_space_state.intersect_ray(q)


func los(a: Vector3, b: Vector3, exclude: Array = []) -> bool:
	return ray(a, b, L_WORLD, exclude).is_empty()


func ground_y(x: float, z: float) -> float:
	var hit := ray(Vector3(x, 200.0, z), Vector3(x, -50.0, z), L_WORLD)
	if hit.is_empty():
		return 0.0
	return hit.position.y


func in_water(p: Vector3) -> bool:
	return p.y < WATER_Y and City.terrain_height(p.x, p.z) < WATER_Y - 0.2


func district(p: Vector3) -> String:
	return City.district_name(p)


func screenshot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var dir := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(path)
