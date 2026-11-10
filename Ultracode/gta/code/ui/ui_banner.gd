class_name UiBanner
extends Control
## Big centre banner ("DOWN", "ARRESTED", activity results ...): a dark band across the screen
## with two accent lines, huge condensed caps and an optional sub line. Original styling.
## Runs on real time so it also animates while the game is paused or in slow motion.

var _text: String = ""
var _sub: String = ""
var _color: Color = Color.WHITE
var _t: float = 0.0
var _life: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func show_banner(text: String, sub: String = "", color: Color = Color.WHITE, duration: float = 4.0) -> void:
	_text = text.to_upper()
	_sub = sub
	_color = color
	_t = 0.0
	_life = maxf(duration, 0.5)
	visible = _text != ""
	queue_redraw()


func hide_banner() -> void:
	_life = 0.0
	visible = false


func is_showing() -> bool:
	return visible and _t < _life


func get_text() -> String:
	return _text if is_showing() else ""


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta / maxf(Engine.time_scale, 0.05)
	if _t >= _life:
		visible = false
		return
	queue_redraw()


func _draw() -> void:
	if _text == "":
		return
	var a_in := clampf(_t / 0.35, 0.0, 1.0)
	var a := a_in * clampf((_life - _t) / 0.6, 0.0, 1.0)
	var e := ease(a_in, 0.3)
	var cy := size.y * 0.4
	var band_h := 190.0 if _sub != "" else 150.0
	var band := Rect2(0.0, cy - band_h * 0.5, size.x, band_h * e)
	band.position.y = cy - band.size.y * 0.5
	draw_rect(band, Color(0.015, 0.04, 0.085, 0.72 * a))
	var line_w := size.x * e
	draw_rect(Rect2((size.x - line_w) * 0.5, band.position.y, line_w, 5.0), Color(_color, a))
	draw_rect(Rect2((size.x - line_w) * 0.5, band.end.y - 5.0, line_w, 5.0), Color(_color, a))
	var head := UiStyle.font(&"head")
	var fs := UiStyle.FS_HUGE
	var spread := 1.0 + 0.18 * (1.0 - e)
	var tw := UiStyle.text_width(head, _text, fs)
	var base := Vector2(size.x * 0.5, cy + (26.0 if _sub != "" else 44.0))
	draw_set_transform(base, 0.0, Vector2(spread, spread))
	UiStyle.text_outlined(self, head, Vector2(-tw * 0.5, 0.0), _text, fs, Color(_color, a), 14, Color(0.01, 0.03, 0.07, 0.85 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _sub != "":
		UiStyle.text(self, UiStyle.font(&"bold"), Vector2(0.0, cy + 74.0), _sub, UiStyle.FS_LARGE, Color(UiStyle.CREAM, a), HORIZONTAL_ALIGNMENT_CENTER, size.x)
