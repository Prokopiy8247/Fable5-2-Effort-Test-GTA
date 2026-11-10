extends Node
## Autoload "InputSetup" (first autoload). Registers every input action in code so that no
## manual editor work is ever required. Keyboard + mouse first, basic gamepad second.
## RULE: gameplay code must use these action names; add new actions here only (append).

const KEYS := {
	# --- on foot ---
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"crouch": [KEY_C],
	"stealth": [KEY_CTRL],
	"cover": [KEY_Q],
	"interact": [KEY_E],
	"enter_vehicle": [KEY_F],
	"reload": [KEY_R],
	"throw_grenade": [KEY_G],
	"melee_heavy": [KEY_X],
	"holster": [KEY_Z],
	"weapon_wheel": [KEY_TAB],
	"weapon_flashlight": [KEY_B],
	"camera_toggle": [KEY_V],
	"walk": [KEY_ALT],
	"radio_wheel": [KEY_Y],
	# --- weapon slots ---
	"weapon_slot_1": [KEY_1],
	"weapon_slot_2": [KEY_2],
	"weapon_slot_3": [KEY_3],
	"weapon_slot_4": [KEY_4],
	"weapon_slot_5": [KEY_5],
	"weapon_slot_6": [KEY_6],
	"weapon_slot_7": [KEY_7],
	"weapon_slot_8": [KEY_8],
	"weapon_slot_9": [KEY_9],
	# --- ground / water vehicles (throttle/steer reuse move_* actions) ---
	"handbrake": [KEY_SPACE],
	"horn": [KEY_H],
	"headlights": [KEY_L],
	"siren": [KEY_T],
	"look_back": [KEY_C],
	"radio_next": [KEY_PERIOD],
	"radio_prev": [KEY_COMMA],
	"vehicle_roof": [KEY_K],
	# --- aircraft (see docs/ARCHITECTURE.md "Controls") ---
	"air_throttle_up": [KEY_W],
	"air_throttle_down": [KEY_S],
	"air_yaw_left": [KEY_A],
	"air_yaw_right": [KEY_D],
	"air_pitch_down": [KEY_UP, KEY_KP_8],
	"air_pitch_up": [KEY_DOWN, KEY_KP_5],
	"air_roll_left": [KEY_LEFT, KEY_KP_4],
	"air_roll_right": [KEY_RIGHT, KEY_KP_6],
	"air_gear": [KEY_G],
	# --- meta ---
	"map": [KEY_M],
	"phone": [KEY_P],
	"pause": [KEY_ESCAPE],
	"admin_menu": [KEY_F1],
	"photo_mode": [KEY_F2],
	"debug_overlay": [KEY_F3],
	"quick_save": [KEY_F5],
	"quick_load": [KEY_F9],
	"skip": [KEY_ENTER],
}

const MOUSE := {
	"fire": [MOUSE_BUTTON_LEFT],
	"aim": [MOUSE_BUTTON_RIGHT],
	"weapon_next": [MOUSE_BUTTON_WHEEL_DOWN],
	"weapon_prev": [MOUSE_BUTTON_WHEEL_UP],
}

const JOY_BUTTONS := {
	"jump": [JOY_BUTTON_A],
	"handbrake": [JOY_BUTTON_A],
	"crouch": [JOY_BUTTON_RIGHT_STICK],
	"enter_vehicle": [JOY_BUTTON_Y],
	"interact": [JOY_BUTTON_DPAD_RIGHT],
	"reload": [JOY_BUTTON_X],
	"cover": [JOY_BUTTON_RIGHT_SHOULDER],
	"weapon_wheel": [JOY_BUTTON_LEFT_SHOULDER],
	"sprint": [JOY_BUTTON_LEFT_STICK],
	"pause": [JOY_BUTTON_START],
	"map": [JOY_BUTTON_BACK],
	"horn": [JOY_BUTTON_DPAD_DOWN],
	"phone": [JOY_BUTTON_DPAD_UP],
	"camera_toggle": [JOY_BUTTON_DPAD_LEFT],
	"melee_heavy": [JOY_BUTTON_B],
}

## action -> [axis, sign]
const JOY_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"fire": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	"aim": [JOY_AXIS_TRIGGER_LEFT, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
}


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_all()


func _register_all() -> void:
	for action in KEYS:
		_ensure(action)
		for keycode in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	for action in MOUSE:
		_ensure(action)
		for button in MOUSE[action]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)
	for action in JOY_BUTTONS:
		_ensure(action)
		for button in JOY_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)
	for action in JOY_AXES:
		_ensure(action)
		var ev := InputEventJoypadMotion.new()
		ev.axis = JOY_AXES[action][0]
		ev.axis_value = JOY_AXES[action][1]
		InputMap.action_add_event(action, ev)


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.3)


## Human readable key label for HUD prompts, e.g. InputSetup.label("enter_vehicle") -> "F".
func label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
		if ev is InputEventMouseButton:
			match (ev as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
				MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
				MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
	return "?"
