class_name UiBar
extends Control
## Rounded progress bar with an optional icon on the left and value text on the right.
##     var bar := UiBar.new(UiStyle.TEAL, &"bolt"); bar.value = 0.6; bar.value_text = "60"

var value: float = 1.0:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if not is_equal_approx(v, value):
			value = v
			queue_redraw()
var color: Color = UiStyle.TEAL:
	set(v):
		color = v
		queue_redraw()
var icon: StringName = &"":
	set(v):
		icon = v
		queue_redraw()
var value_text: String = "":
	set(v):
		if v != value_text:
			value_text = v
			queue_redraw()
var bar_height: float = 14.0
var dark_track: bool = false
var value_width: float = 64.0


func _init(p_color: Color = UiStyle.TEAL, p_icon: StringName = &"", p_height: float = 14.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = p_color
	icon = p_icon
	bar_height = p_height
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(120.0, maxf(p_height, 30.0))


func _draw() -> void:
	var x0 := 0.0
	var x1 := size.x
	if icon != &"":
		UiIcons.draw(self, icon, Vector2(15.0, size.y * 0.5), 26.0, color)
		x0 = 40.0
	if value_text != "":
		x1 -= value_width
		UiStyle.text_in(self, UiStyle.font(&"num"), Rect2(x1, 0.0, value_width, size.y), value_text, UiStyle.FS_BODY, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	UiStyle.draw_bar(self, Rect2(x0, (size.y - bar_height) * 0.5, maxf(x1 - x0, 8.0), bar_height), value, color, dark_track)
