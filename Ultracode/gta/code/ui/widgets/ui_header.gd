class_name UiHeader
extends Control
## Screen / panel header: coral accent bar, bold condensed caps title, optional muted subtitle and
## an optional right-aligned value (money, counter ...).

var title: String = "":
	set(v):
		title = v.to_upper()
		queue_redraw()
var subtitle: String = "":
	set(v):
		subtitle = v
		_resize()
var right_text: String = "":
	set(v):
		right_text = v
		queue_redraw()
var accent: Color = UiStyle.CORAL:
	set(v):
		accent = v
		queue_redraw()
var right_color: Color = UiStyle.SUN:
	set(v):
		right_color = v
		queue_redraw()
var title_size: int = UiStyle.FS_H2:
	set(v):
		title_size = v
		_resize()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resize()


func _resize() -> void:
	custom_minimum_size = Vector2(200.0, title_size + 14.0 + (UiStyle.FS_SMALL + 8.0 if subtitle != "" else 0.0))
	queue_redraw()


func _draw() -> void:
	var head := UiStyle.font(&"head")
	var bar := Rect2(0.0, 2.0, 8.0, size.y - 4.0)
	draw_style_box(UiStyle._fill_box(accent), bar)
	var x := 26.0
	var base := head.get_ascent(title_size) + 2.0
	draw_string(head, Vector2(x, base), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_size, UiStyle.TEXT)
	if subtitle != "":
		draw_string(UiStyle.font(&"body"), Vector2(x, size.y - 8.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - x, UiStyle.FS_SMALL, UiStyle.MUTED)
	if right_text != "":
		var num := UiStyle.font(&"num")
		draw_string(num, Vector2(0.0, base - 4.0), right_text, HORIZONTAL_ALIGNMENT_RIGHT, size.x, UiStyle.FS_H3, right_color)
