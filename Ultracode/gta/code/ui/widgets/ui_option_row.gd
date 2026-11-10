class_name UiOptionRow
extends Control
## "Label            < value >" row that cycles through a fixed list of options (toggles, quality
## levels, FPS caps ...). ui_left / ui_right or a click on the arrows changes it; ui_accept / a
## click on the value steps forward.
##     var row := UiOptionRow.new("V-Sync", ["Off", "On"], 1)
##     row.changed.connect(func(i): Settings.set_value("vsync", i == 1))

signal changed(index: int)

var label: String = ""
var options: Array = []
var index: int = 0
var wrap: bool = true
var _hover: bool = false


func _init(p_label: String = "", p_options: Array = [], p_index: int = 0) -> void:
	label = p_label
	options = p_options
	index = clampi(p_index, 0, maxi(options.size() - 1, 0))
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(420.0, 54.0)


func get_text() -> String:
	if index < 0 or index >= options.size():
		return ""
	return str(options[index])


func set_index_silent(i: int) -> void:
	index = clampi(i, 0, maxi(options.size() - 1, 0))
	queue_redraw()


func step(dir: int) -> void:
	if options.is_empty():
		return
	var n := options.size()
	var next := index + dir
	if wrap:
		next = posmod(next, n)
	else:
		next = clampi(next, 0, n - 1)
	if next == index:
		return
	index = next
	UiKit.sfx("ui_tab")
	queue_redraw()
	changed.emit(index)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if not has_focus():
			grab_focus()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			grab_focus()
			var zone := _value_rect()
			step(-1 if mb.position.x < zone.position.x + 56.0 and mb.position.x >= zone.position.x else 1)
			accept_event()
	elif event.is_action_pressed("ui_left", true):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right", true) or event.is_action_pressed("ui_accept"):
		step(1)
		accept_event()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_FOCUS_ENTER:
			UiKit.sfx("ui_hover", -10.0)
			queue_redraw()
		NOTIFICATION_FOCUS_EXIT:
			queue_redraw()
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()


func _value_rect() -> Rect2:
	var w := minf(360.0, size.x * 0.5)
	return Rect2(size.x - w, 4.0, w, size.y - 8.0)


func _draw() -> void:
	var focused := has_focus()
	if focused:
		draw_style_box(UiStyle.cached_box(&"select"), Rect2(Vector2.ZERO, size))
	elif _hover:
		draw_style_box(UiStyle.cached_box(&"hover"), Rect2(Vector2.ZERO, size))
	UiStyle.text_in(self, UiStyle.font(&"body"), Rect2(22.0, 0.0, size.x * 0.5, size.y), label, UiStyle.FS_BODY,
			Color.WHITE if focused else UiStyle.TEXT)
	var zone := _value_rect()
	draw_style_box(UiStyle.cached_box(&"chip"), zone)
	var arrow_col: Color = UiStyle.SUN if focused else UiStyle.MUTED
	UiIcons.draw(self, &"chev_left", Vector2(zone.position.x + 26.0, zone.get_center().y), 20.0, arrow_col)
	UiIcons.draw(self, &"chev_right", Vector2(zone.end.x - 26.0, zone.get_center().y), 20.0, arrow_col)
	UiStyle.text_in(self, UiStyle.font(&"bold"), zone, get_text(), UiStyle.FS_BODY, UiStyle.SUN if focused else UiStyle.TEXT,
			HORIZONTAL_ALIGNMENT_CENTER)
