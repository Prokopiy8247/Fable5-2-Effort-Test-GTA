class_name UiConfirmDialog
extends Control
## Modal confirm dialog (dims its parent, traps focus, Esc cancels).
##     var dlg := UiConfirmDialog.ask(self, "Quit game?", "Unsaved progress will be lost.", "Quit", "Stay")
##     dlg.confirmed.connect(get_tree().quit)
## The dialog frees itself after either button. `await dlg.closed` gives the result (true = confirmed).

signal confirmed()
signal cancelled()
signal closed(accepted: bool)

var _done: bool = false
var _confirm_btn: Button
var _cancel_btn: Button


static func ask(parent: Control, title: String, text: String = "", confirm_text: String = "Confirm",
		cancel_text: String = "Cancel", danger: bool = false) -> UiConfirmDialog:
	var d := UiConfirmDialog.new()
	d._build(title, text, confirm_text, cancel_text, danger)
	parent.add_child(d)
	return d


func _build(title: String, text: String, confirm_text: String, cancel_text: String, danger: bool) -> void:
	name = "ConfirmDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.03, 0.07, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := UiPanel.new(&"SolidPanel", 18)
	panel.custom_minimum_size = Vector2(620.0, 0.0)
	center.add_child(panel)
	var head := UiHeader.new()
	head.title = title
	head.accent = UiStyle.BAD if danger else UiStyle.CORAL
	panel.add(head)
	if text != "":
		panel.add(UiKit.paragraph(text, &"", 560.0))
	panel.add(UiKit.spacer(Vector2(0, 6), false))
	var row := UiKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_END
	_cancel_btn = UiKit.button(cancel_text, _finish.bind(false))
	_cancel_btn.custom_minimum_size.x = 180.0
	_confirm_btn = UiKit.button(confirm_text, _finish.bind(true), &"AccentButton")
	_confirm_btn.custom_minimum_size.x = 180.0
	row.add_child(_cancel_btn)
	row.add_child(_confirm_btn)
	panel.add(row)


func _ready() -> void:
	_cancel_btn.focus_neighbor_right = _cancel_btn.get_path_to(_confirm_btn)
	_confirm_btn.focus_neighbor_left = _confirm_btn.get_path_to(_cancel_btn)
	_cancel_btn.focus_neighbor_left = _cancel_btn.get_path_to(_confirm_btn)
	_confirm_btn.focus_neighbor_right = _confirm_btn.get_path_to(_cancel_btn)
	for b: Button in [_cancel_btn, _confirm_btn]:
		b.focus_neighbor_top = NodePath(".")
		b.focus_neighbor_bottom = NodePath(".")
	_cancel_btn.grab_focus.call_deferred()
	UiKit.sfx("ui_open")


func is_open() -> bool:
	return not _done


## Cancel from outside (used by UiScreen.handle_back()).
func cancel() -> void:
	_finish(false)


func accept() -> void:
	_finish(true)


func _input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_finish(false)


func _finish(ok: bool) -> void:
	if _done:
		return
	_done = true
	if ok:
		confirmed.emit()
	else:
		cancelled.emit()
	closed.emit(ok)
	queue_free()
