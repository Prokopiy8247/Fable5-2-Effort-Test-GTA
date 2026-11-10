class_name InputSetup
extends RefCounted
## Builds the InputMap in code so the project needs no manual Input Map editing.
## Keyboard/mouse first; a basic gamepad layout is added on top.

const K := "k"   # physical key
const M := "m"   # mouse button
const JB := "jb" # joypad button
const JA := "ja" # joypad axis [axis, sign]

static var ACTIONS := {
	# --- on foot / shared movement
	"move_forward": [[K, KEY_W], [JA, JOY_AXIS_LEFT_Y, -1.0]],
	"move_back": [[K, KEY_S], [JA, JOY_AXIS_LEFT_Y, 1.0]],
	"move_left": [[K, KEY_A], [JA, JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [[K, KEY_D], [JA, JOY_AXIS_LEFT_X, 1.0]],
	"sprint": [[K, KEY_SHIFT], [JB, JOY_BUTTON_LEFT_STICK]],
	"jump": [[K, KEY_SPACE], [JB, JOY_BUTTON_A]],
	"crouch": [[K, KEY_C], [K, KEY_CTRL], [JB, JOY_BUTTON_B]],
	"cover": [[K, KEY_Q], [JB, JOY_BUTTON_RIGHT_SHOULDER]],
	"interact": [[K, KEY_E], [JB, JOY_BUTTON_DPAD_RIGHT]],
	"enter_vehicle": [[K, KEY_F], [JB, JOY_BUTTON_Y]],
	# --- combat
	"fire": [[M, MOUSE_BUTTON_LEFT], [JA, JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"aim": [[M, MOUSE_BUTTON_RIGHT], [JA, JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"melee_heavy": [[M, MOUSE_BUTTON_MIDDLE], [K, KEY_X]],
	"reload": [[K, KEY_R], [JB, JOY_BUTTON_X]],
	"grenade": [[K, KEY_G]],
	"weapon_wheel": [[K, KEY_TAB], [JB, JOY_BUTTON_LEFT_SHOULDER]],
	"weapon_next": [[M, MOUSE_BUTTON_WHEEL_DOWN]],
	"weapon_prev": [[M, MOUSE_BUTTON_WHEEL_UP]],
	"weapon_1": [[K, KEY_1]], "weapon_2": [[K, KEY_2]], "weapon_3": [[K, KEY_3]],
	"weapon_4": [[K, KEY_4]], "weapon_5": [[K, KEY_5]], "weapon_6": [[K, KEY_6]],
	"weapon_7": [[K, KEY_7]], "weapon_8": [[K, KEY_8]], "weapon_9": [[K, KEY_9]],
	"holster": [[K, KEY_0]],
	# --- vehicles
	"handbrake": [[K, KEY_SPACE], [JB, JOY_BUTTON_RIGHT_SHOULDER]],
	"horn": [[K, KEY_H], [JB, JOY_BUTTON_LEFT_STICK]],
	"headlights": [[K, KEY_L]],
	"siren": [[K, KEY_J]],
	"radio_next": [[K, KEY_PERIOD]],
	"radio_prev": [[K, KEY_COMMA]],
	"roof": [[K, KEY_K]],
	"look_behind": [[K, KEY_B]],
	"air_up": [[K, KEY_SHIFT], [JA, JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"air_down": [[K, KEY_CTRL], [JA, JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"yaw_left": [[K, KEY_Q]],
	"yaw_right": [[K, KEY_E]],
	# --- interface
	"camera_toggle": [[K, KEY_V], [JB, JOY_BUTTON_BACK]],
	"map": [[K, KEY_M]],
	"pause": [[K, KEY_ESCAPE], [JB, JOY_BUTTON_START]],
	"phone": [[K, KEY_UP], [K, KEY_P], [JB, JOY_BUTTON_DPAD_UP]],
	"debug_menu": [[K, KEY_F1]],
	"toggle_fps": [[K, KEY_F3]],
	"quick_save": [[K, KEY_F5]],
	"quick_load": [[K, KEY_F9]],
	"photo_mode": [[K, KEY_F8]],
	"ui_back": [[K, KEY_BACKSPACE]],
}

static func install() -> void:
	for action in ACTIONS.keys():
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.35)
		for e in ACTIONS[action]:
			var ev: InputEvent = null
			match e[0]:
				K:
					var k := InputEventKey.new()
					k.physical_keycode = e[1]
					ev = k
				M:
					var m := InputEventMouseButton.new()
					m.button_index = e[1]
					ev = m
				JB:
					var b := InputEventJoypadButton.new()
					b.button_index = e[1]
					ev = b
				JA:
					var a := InputEventJoypadMotion.new()
					a.axis = e[1]
					a.axis_value = e[2]
					ev = a
			if ev != null:
				InputMap.action_add_event(action, ev)

## Human readable label of the first keyboard/mouse binding (for prompts: "[F] Enter").
static func label(action: String) -> String:
	if not ACTIONS.has(action):
		return "?"
	var e: Array = ACTIONS[action][0]
	if e[0] == K:
		return OS.get_keycode_string(e[1])
	if e[0] == M:
		match e[1]:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			_: return "Wheel"
	return "?"
