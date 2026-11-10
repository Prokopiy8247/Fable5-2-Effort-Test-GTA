class_name HudCaption
extends Control
## Top-centre caption that fades in and out: district name on entering a district, radio station
## on a station change. One at a time (the newest replaces the current one).

var _title: String = ""
var _sub: String = ""
var _icon: StringName = &""
var _color: Color = UiStyle.CREAM
var _t: float = 0.0
var _life: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(900.0, 110.0)
	size = custom_minimum_size
	modulate.a = 0.0


func show_caption(title: String, sub: String = "", icon: StringName = &"", color: Color = UiStyle.CREAM, duration: float = 3.5) -> void:
	_title = title.to_upper()
	_sub = sub
	_icon = icon
	_color = color
	_t = 0.0
	_life = maxf(duration, 0.6)
	queue_redraw()


func is_showing() -> bool:
	return _life > 0.0 and _t < _life


func get_title() -> String:
	return _title if is_showing() else ""


func _process(delta: float) -> void:
	if _life <= 0.0:
		return
	_t += delta
	var a := clampf(_t / 0.3, 0.0, 1.0) * clampf((_life - _t) / 0.6, 0.0, 1.0)
	modulate.a = a
	if _t >= _life:
		_life = 0.0
		modulate.a = 0.0


func _draw() -> void:
	if _title == "":
		return
	var head := UiStyle.font(&"head")
	var fs := UiStyle.FS_H2
	var tw := UiStyle.text_width(head, _title, fs)
	var icon_w := 52.0 if _icon != &"" else 0.0
	var x := (size.x - tw - icon_w) * 0.5
	if _icon != &"":
		UiIcons.draw(self, _icon, Vector2(x + 18.0, 30.0) + Vector2(0, 2), 38.0, Color(0, 0, 0, 0.5))
		UiIcons.draw(self, _icon, Vector2(x + 18.0, 30.0), 38.0, _color)
		x += icon_w
	UiStyle.text_outlined(self, head, Vector2(x, 44.0), _title, fs, UiStyle.TEXT, 8, Color(0.02, 0.05, 0.1, 0.75))
	var line_w := minf(tw + icon_w, 420.0)
	draw_style_box(UiStyle._fill_box(_color), Rect2((size.x - line_w) * 0.5, 58.0, line_w, 5.0))
	if _sub != "":
		UiStyle.text(self, UiStyle.font(&"body"), Vector2(0.0, 92.0), _sub, UiStyle.FS_SMALL, UiStyle.CREAM, HORIZONTAL_ALIGNMENT_CENTER, size.x)
