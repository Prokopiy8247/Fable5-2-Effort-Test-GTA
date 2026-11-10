class_name UiCanvas
extends Control
## Tiny helper: a Control whose _draw() is delegated to a Callable `draw_fn(canvas: UiCanvas)`.
## Lets one script own several independently redrawn / transformed layers without a file each.

var draw_fn: Callable = Callable()


func _init(p_draw_fn: Callable = Callable(), p_mouse_filter: int = Control.MOUSE_FILTER_IGNORE) -> void:
	draw_fn = p_draw_fn
	mouse_filter = p_mouse_filter as Control.MouseFilter


func _draw() -> void:
	if draw_fn.is_valid():
		draw_fn.call(self)
