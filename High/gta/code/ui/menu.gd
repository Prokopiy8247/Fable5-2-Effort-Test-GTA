class_name GameMenu
extends Control
## Generic stacked list menu (shops, pause, phone, benchmark menu). Built from Containers + a shared Theme.
## Items: {text, right, cb, disabled, color, info}. A builder Callable is re-run after every action to refresh.

signal closed

var _stack: Array = []        # [{title, builder, focus}]
var _panel: PanelContainer
var _title: Label
var _sub: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _hint: Label
var id := ""
var pauses := false
var on_close: Callable

static var theme_res: Theme


static func make_theme() -> Theme:
	if theme_res != null:
		return theme_res
	var t := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.08, 0.11, 0.93)
	panel.border_color = Color(1.0, 0.56, 0.3, 0.9)
	panel.border_width_left = 4
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(18)
	t.set_stylebox("panel", "PanelContainer", panel)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.16, 0.2, 0.9)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(8)
	normal.content_margin_left = 14
	var hover := normal.duplicate()
	hover.bg_color = Color(1.0, 0.56, 0.3, 0.95)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.9, 0.42, 0.2, 1.0)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.1, 0.11, 0.13, 0.6)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("focus", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", Color(0.92, 0.93, 0.95))
	t.set_color("font_hover_color", "Button", Color(0.06, 0.07, 0.09))
	t.set_color("font_focus_color", "Button", Color(0.06, 0.07, 0.09))
	t.set_color("font_pressed_color", "Button", Color(0.06, 0.07, 0.09))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.52, 0.56))
	t.set_font_size("font_size", "Button", 18)
	t.set_font_size("font_size", "Label", 18)
	t.set_color("font_color", "Label", Color(0.92, 0.93, 0.95))
	theme_res = t
	return t


func _ready() -> void:
	theme = make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 60)
	margin.custom_minimum_size = Vector2(560, 0)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	_panel = PanelContainer.new()
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_panel.add_child(vb)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color(1.0, 0.66, 0.4))
	vb.add_child(_title)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 15)
	_sub.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_sub)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(500, 420)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.6, 0.64, 0.7))
	_hint.text = "Mouse / arrows + Enter   -   Esc / right-click: back"
	vb.add_child(_hint)


func is_open() -> bool:
	return visible


func open(p_id: String, title: String, builder: Callable, p_pauses: bool = false, sub: String = "") -> void:
	if visible:
		close()
	id = p_id
	pauses = p_pauses
	_stack = [{"title": title, "builder": builder, "focus": 0, "sub": sub}]
	visible = true
	Game.ui_open("menu")
	if pauses:
		get_tree().paused = true
	_rebuild()
	Sfx.ui("click")


func push(title: String, builder: Callable, sub: String = "") -> void:
	if not _stack.is_empty():
		_stack[-1].focus = _focus_index()
	_stack.append({"title": title, "builder": builder, "focus": 0, "sub": sub})
	_rebuild()
	Sfx.ui("click")


func back() -> void:
	if _stack.size() <= 1:
		close()
		return
	_stack.pop_back()
	_rebuild()
	Sfx.ui("move")


func close() -> void:
	if not visible:
		return
	visible = false
	_stack.clear()
	if pauses:
		get_tree().paused = false
	Game.ui_close("menu")
	closed.emit()
	if on_close.is_valid():
		var cb := on_close
		on_close = Callable()
		cb.call()


func refresh() -> void:
	if visible and not _stack.is_empty():
		_stack[-1].focus = _focus_index()
		_rebuild()


func _focus_index() -> int:
	var i := 0
	for c in _list.get_children():
		if c is Button and c.has_focus():
			return i
		i += 1
	return 0


func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var top: Dictionary = _stack[-1]
	_title.text = top.title
	_sub.text = top.sub
	_sub.visible = top.sub != ""
	var items: Array = top.builder.call()
	var idx := 0
	var first_btn: Button = null
	var focus_btn: Button = null
	for it in items:
		if it.get("info", false):
			var l := Label.new()
			l.text = it.text
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.add_theme_font_size_override("font_size", 16)
			l.add_theme_color_override("font_color", it.get("color", Color(0.78, 0.82, 0.88)))
			_list.add_child(l)
			idx += 1
			continue
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = it.text
		b.disabled = it.get("disabled", false)
		b.focus_mode = Control.FOCUS_ALL
		if it.has("color"):
			b.add_theme_color_override("font_color", it.color)
		if it.has("right") and it.right != "":
			var r := Label.new()
			r.text = it.right
			r.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
			r.offset_left = -220
			r.offset_right = -12
			r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.add_theme_font_size_override("font_size", 16)
			r.add_theme_color_override("font_color", it.get("right_color", Color(0.75, 0.95, 0.75)))
			b.add_child(r)
		if it.has("cb"):
			var cb: Callable = it.cb
			var keep: bool = it.get("keep", true)
			b.pressed.connect(func():
				cb.call()
				if keep and visible:
					refresh())
		b.mouse_entered.connect(func(): b.grab_focus())
		_list.add_child(b)
		if first_btn == null and not b.disabled:
			first_btn = b
		if idx == int(top.focus) and not b.disabled:
			focus_btn = b
		idx += 1
	await get_tree().process_frame
	if not visible:
		return
	if focus_btn and is_instance_valid(focus_btn):
		focus_btn.grab_focus()
	elif first_btn and is_instance_valid(first_btn):
		first_btn.grab_focus()


func _input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev.is_action_pressed("pause") or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT):
		back()
		get_viewport().set_input_as_handled()
