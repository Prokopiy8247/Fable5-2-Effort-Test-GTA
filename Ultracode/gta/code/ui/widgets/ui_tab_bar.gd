class_name UiTabBar
extends Control
## Horizontal caps tab strip with a coral underline on the current tab. Click a tab, or press
## Q / E (pad: LB / RB) while `active` is true, to switch.
##     var tabs := UiTabBar.new(["WEAPONS", "AMMO", "ATTACHMENTS"])
##     tabs.tab_changed.connect(_show_page)

signal tab_changed(index: int)

var tabs: Array = []
var current: int = 0
var active: bool = true          ## listen for Q / E / shoulder buttons
var show_key_hints: bool = true
var _rects: Array[Rect2] = []
var _hover: int = -1


func _init(p_tabs: Array = [], p_current: int = 0) -> void:
	tabs = p_tabs
	current = p_current
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(300.0, 58.0)


func set_tabs(p_tabs: Array, p_current: int = 0) -> void:
	tabs = p_tabs
	current = clampi(p_current, 0, maxi(tabs.size() - 1, 0))
	queue_redraw()


func select(index: int, emit: bool = true) -> void:
	if tabs.is_empty():
		return
	index = posmod(index, tabs.size())
	if index == current:
		return
	current = index
	UiKit.sfx("ui_tab")
	queue_redraw()
	if emit:
		tab_changed.emit(current)


func _unhandled_input(event: InputEvent) -> void:
	if not active or not is_visible_in_tree() or tabs.size() < 2:
		return
	var dir := 0
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).physical_keycode:
			KEY_Q: dir = -1
			KEY_E: dir = 1
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_LEFT_SHOULDER: dir = -1
			JOY_BUTTON_RIGHT_SHOULDER: dir = 1
	if dir != 0:
		select(current + dir)
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _tab_at((event as InputEventMouseMotion).position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var t := _tab_at(mb.position)
			if t >= 0:
				select(t)
				accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


func _tab_at(p: Vector2) -> int:
	for i in _rects.size():
		if _rects[i].has_point(p):
			return i
	return -1


func _draw() -> void:
	var head := UiStyle.font(&"head")
	var fs := UiStyle.FS_LARGE
	_rects.clear()
	var x := 0.0
	var hints := show_key_hints and active and tabs.size() > 1
	if hints:
		x += UiStyle.draw_keycap(self, Vector2(0.0, (size.y - UiStyle.FS_TINY - 16.0) * 0.5 - 2.0), "Q", UiStyle.FS_TINY) + 16.0
	for i in tabs.size():
		var txt := str(tabs[i]).to_upper()
		var w := UiStyle.text_width(head, txt, fs) + 44.0
		var r := Rect2(x, 0.0, w, size.y - 6.0)
		_rects.append(r)
		var is_cur := i == current
		if is_cur:
			draw_style_box(UiStyle.cached_box(&"chip"), r)
			draw_style_box(UiStyle._fill_box(UiStyle.CORAL), Rect2(x + 14.0, size.y - 8.0, w - 28.0, 5.0))
		elif i == _hover:
			draw_style_box(UiStyle.cached_box(&"hover"), r)
		UiStyle.text_in(self, head, r, txt, fs, UiStyle.TEXT if is_cur else UiStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		x += w + 8.0
	if hints:
		UiStyle.draw_keycap(self, Vector2(x + 8.0, (size.y - UiStyle.FS_TINY - 16.0) * 0.5 - 2.0), "E", UiStyle.FS_TINY)
	draw_line(Vector2(0.0, size.y - 1.0), Vector2(size.x, size.y - 1.0), UiStyle.LINE, 2.0)
