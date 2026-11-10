extends Control
## Row(s) of colour chips for the clothing store, wardrobe and barber (ECONOMY A).
## Mouse: click a chip. Keyboard: the owning screen calls step(-1 / +1) on ui_left / ui_right (A / D).

signal changed(index: int)

const CHIP := 40.0
const GAP := 11.0

var colors: Array = []               ## "#rrggbb" strings
var selected: int = 0
var current: int = -1                ## the colour worn right now (small dot under the chip)
var _hover: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(200.0, CHIP + 14.0)


func set_colors(p_colors: Array, p_selected: int = 0, p_current: int = -1) -> void:
	colors = p_colors
	selected = clampi(p_selected, 0, maxi(colors.size() - 1, 0))
	current = p_current
	_update_height()
	queue_redraw()


func get_color() -> String:
	if colors.is_empty():
		return ""
	return str(colors[selected])


func step(dir: int) -> void:
	if colors.size() < 2:
		return
	selected = posmod(selected + dir, colors.size())
	queue_redraw()
	changed.emit(selected)


func select(index: int, emit: bool = true) -> void:
	if colors.is_empty():
		return
	index = clampi(index, 0, colors.size() - 1)
	if index == selected:
		return
	selected = index
	queue_redraw()
	if emit:
		changed.emit(selected)


func _per_row() -> int:
	return maxi(int((maxf(size.x, CHIP) + GAP) / (CHIP + GAP)), 1)


func _update_height() -> void:
	var rows_n := int(ceil(float(colors.size()) / float(_per_row()))) if not colors.is_empty() else 1
	custom_minimum_size.y = rows_n * (CHIP + GAP) + 2.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_height()
	elif what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


func _chip_center(i: int) -> Vector2:
	var per := _per_row()
	return Vector2(float(i % per) * (CHIP + GAP) + CHIP * 0.5 + 4.0, float(i / per) * (CHIP + GAP) + CHIP * 0.5 + 4.0)


func _index_at(p: Vector2) -> int:
	for i in colors.size():
		if _chip_center(i).distance_to(p) <= CHIP * 0.5 + 2.0:
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _index_at((event as InputEventMouseMotion).position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var i := _index_at(mb.position)
			if i >= 0:
				UiKit.sfx("ui_click")
				select(i)
				accept_event()


func _draw() -> void:
	for i in colors.size():
		var c := _chip_center(i)
		var col := Color.html(str(colors[i])) if Color.html_is_valid(str(colors[i])) else Color.MAGENTA
		if i == selected:
			draw_circle(c, CHIP * 0.5 + 3.0, UiStyle.SUN)
			draw_circle(c, CHIP * 0.5 - 1.0, UiStyle.NAVY_DEEP)
		elif i == _hover:
			draw_circle(c, CHIP * 0.5 + 1.0, Color(1, 1, 1, 0.45))
		draw_circle(c, CHIP * 0.5 - 4.0, col)
		draw_arc(c, CHIP * 0.5 - 4.0, 0.0, TAU, 32, Color(1, 1, 1, 0.22), 1.5, true)
		if i == current:
			draw_circle(c, 5.0, UiStyle.NAVY_DEEP if col.get_luminance() > 0.55 else Color.WHITE)
