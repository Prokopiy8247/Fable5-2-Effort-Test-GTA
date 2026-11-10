class_name UiSliderRow
extends HBoxContainer
## "Label ───●──── value" settings row. Focus the slider with ui_up / ui_down, change it with
## ui_left / ui_right or the mouse.
##     var row := UiSliderRow.new("Master volume", 0.0, 1.0, 0.05, 0.8, "percent")
##     row.value_changed.connect(func(v): Settings.set_value("master_volume", v))
## format: "percent" (0..1 -> 80%), "int", "float1", "float2", "deg" or a printf string ("%.0f km").

signal value_changed(value: float)

var slider: HSlider
var _name_label: Label
var _value_label: Label
var _format: String = "float2"
var _scale: float = 1.0
var _focused: bool = false


func _init(p_label: String = "", p_min: float = 0.0, p_max: float = 1.0, p_step: float = 0.01,
		p_value: float = 0.0, p_format: String = "percent", p_display_scale: float = 1.0) -> void:
	_format = p_format
	_scale = p_display_scale
	add_theme_constant_override("separation", 18)
	custom_minimum_size.y = 54.0
	var inset := Control.new()
	inset.custom_minimum_size.x = 4.0
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inset)
	_name_label = Label.new()
	_name_label.text = p_label
	_name_label.custom_minimum_size.x = 300.0
	_name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_name_label)
	slider = HSlider.new()
	slider.min_value = p_min
	slider.max_value = p_max
	slider.step = p_step
	slider.value = p_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(240.0, 34.0)
	slider.focus_mode = Control.FOCUS_ALL
	add_child(slider)
	_value_label = Label.new()
	_value_label.theme_type_variation = &"ValueLabel"
	_value_label.custom_minimum_size.x = 96.0
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_value_label)
	slider.value_changed.connect(_on_value)
	slider.focus_entered.connect(_on_focus.bind(true))
	slider.focus_exited.connect(_on_focus.bind(false))
	slider.mouse_entered.connect(_on_hover)
	var outset := Control.new()
	outset.custom_minimum_size.x = 2.0
	outset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(outset)
	_refresh()


func get_value() -> float:
	return slider.value


func set_value_silent(v: float) -> void:
	slider.set_value_no_signal(v)
	_refresh()


func grab() -> void:
	slider.grab_focus()


func _on_hover() -> void:
	if slider.is_visible_in_tree() and not slider.has_focus():
		slider.grab_focus()


func _on_focus(on: bool) -> void:
	_name_label.add_theme_color_override("font_color", Color.WHITE if on else UiStyle.TEXT)
	_value_label.add_theme_color_override("font_color", UiStyle.SUN if on else UiStyle.TEXT)
	_focused = on
	queue_redraw()
	if on:
		UiKit.sfx("ui_hover", -10.0)


func _draw() -> void:
	if _focused:
		draw_style_box(UiStyle.cached_box(&"select"), Rect2(Vector2.ZERO, size))


func _on_value(v: float) -> void:
	_refresh()
	value_changed.emit(v)


func _refresh() -> void:
	var v := slider.value * _scale
	match _format:
		"percent": _value_label.text = "%d%%" % int(round(slider.value * 100.0))
		"int": _value_label.text = str(int(round(v)))
		"float1": _value_label.text = "%.1f" % v
		"float2": _value_label.text = "%.2f" % v
		"deg": _value_label.text = "%d°" % int(round(v))
		_: _value_label.text = _format % v
