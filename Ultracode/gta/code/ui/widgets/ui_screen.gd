class_name UiScreen
extends Control
## Optional base class for screens opened through UI.open_screen() (a screen only has to extend
## Control - this class just removes boilerplate). It does NOT declare the per-screen constants;
## declare the ones you need in your own script:
##     const PAUSES_GAME := true      # default false
##     const TIME_SCALE := 1.0        # default 1.0 (weapon wheel: 0.15)
##     const LOCKS_INPUT := true      # default true
##     const SHOWS_MOUSE := true      # default true
##     const HIDES_HUD := true        # default false (full-screen menus hide the HUD)
## Provides: full-rect layout, a dim backdrop (set `backdrop_alpha` before the node enters the
## tree, 0 = none), a fade-in, close_self(), handle_back() and a slot for one confirm dialog.

var screen_id: String = ""           ## set by the UI manager before open()
var backdrop_alpha: float = 0.6
var _backdrop: ColorRect = null
var _dialog: UiConfirmDialog = null


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _enter_tree() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if backdrop_alpha > 0.0 and _backdrop == null:
		_backdrop = ColorRect.new()
		_backdrop.name = "Backdrop"
		_backdrop.color = Color(0.015, 0.04, 0.085, backdrop_alpha)
		_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_backdrop)
		move_child(_backdrop, 0)
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if tw.has_method("set_ignore_time_scale"):
		tw.call("set_ignore_time_scale", true)
	tw.tween_property(self, "modulate:a", 1.0, 0.12)


## Called by the UI manager right after the screen entered the tree.
func open(_args: Dictionary) -> void:
	pass


## Called by the UI manager right before the screen is freed.
func close() -> void:
	pass


## Esc / back handling. Return true when the screen consumed it (sub-page closed, dialog
## cancelled ...); false lets the UI manager close the screen.
func handle_back() -> bool:
	if _dialog != null and is_instance_valid(_dialog) and _dialog.is_open():
		_dialog.cancel()
		return true
	return false


func close_self() -> void:
	UI.close_screen(screen_id)


## Opens a modal confirm dialog on top of this screen (only one at a time).
func confirm(title: String, text: String = "", confirm_text: String = "Confirm", cancel_text: String = "Cancel",
		danger: bool = false) -> UiConfirmDialog:
	if _dialog != null and is_instance_valid(_dialog) and _dialog.is_open():
		_dialog.cancel()
	_dialog = UiConfirmDialog.ask(self, title, text, confirm_text, cancel_text, danger)
	return _dialog


func has_dialog() -> bool:
	return _dialog != null and is_instance_valid(_dialog) and _dialog.is_open()
