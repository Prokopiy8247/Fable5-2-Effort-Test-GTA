class_name UiIconRect
extends Control
## A Control that draws one UiIcons glyph centred in its rect.

var icon: StringName = &"circle":
	set(v):
		icon = v
		queue_redraw()
var color: Color = UiStyle.TEXT:
	set(v):
		color = v
		queue_redraw()
var icon_size: float = 28.0:
	set(v):
		icon_size = v
		custom_minimum_size = Vector2(v, v)
		queue_redraw()


func _init(p_icon: StringName = &"circle", p_size: float = 28.0, p_color: Color = UiStyle.TEXT) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon = p_icon
	color = p_color
	icon_size = p_size
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	UiIcons.draw(self, icon, size * 0.5, icon_size, color)
