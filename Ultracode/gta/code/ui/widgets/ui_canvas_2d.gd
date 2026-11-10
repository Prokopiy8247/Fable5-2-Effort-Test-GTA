class_name UiCanvas2D
extends Node2D
## Node2D twin of UiCanvas: _draw() is delegated to a Callable `draw_fn(canvas: UiCanvas2D)`.
## Use it (not a Control) for layers that are moved / rotated / scaled far away from their own
## origin: a Control is culled by its own rect (position + size), so a zero-size Control layer
## vanishes as soon as its origin leaves the screen; a Node2D is culled by what it draws.

var draw_fn: Callable = Callable()


func _init(p_draw_fn: Callable = Callable()) -> void:
	draw_fn = p_draw_fn


func _draw() -> void:
	if draw_fn.is_valid():
		draw_fn.call(self)
