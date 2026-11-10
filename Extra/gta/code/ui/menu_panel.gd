class_name MenuPanel
extends CanvasLayer
## Generic data-driven list menu (shops, garage, wardrobe, phone, pause, admin). Built from Control /
## Container nodes with the shared Theme; keyboard, mouse and gamepad navigation; nested pages.
## Item: {"text", "right", "fn": Callable, "adjust": Callable(dir), "disabled", "color", "swatch", "keep": bool}

var root: Control
var panel: PanelContainer
var title_l: Label
var sub_l: Label
var list: VBoxContainer
var scroll: ScrollContainer
var footer: Label
var stack: Array = []
var builder: Callable
var is_open := false
var pause_game := false
var on_close: Callable
var side := "left"
var _focus_idx := 0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(470, 0)
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	title_l = UIKit.label("", 28, UIKit.CORAL)
	vb.add_child(title_l)
	sub_l = UIKit.label("", 15, UIKit.DIM)
	sub_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub_l)
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(450, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	vb.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	footer = UIKit.label("W/S or mouse: select    Enter / E: confirm    A/D: change    Esc: back", 13, UIKit.DIM)
	vb.add_child(footer)
	visible = false


func open(title: String, build: Callable, opts: Dictionary = {}) -> void:
	## build(menu) must call menu.set_items(...) and is re-run after every action to refresh values.
	if not is_open:
		G.ui_blocking += 1
		is_open = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		pause_game = opts.get("pause", false)
		if pause_game:
			get_tree().paused = true
		stack.clear()
		_focus_idx = 0
	else:
		stack.append({"title": title_l.text, "builder": builder, "focus": _focus_idx, "sub": sub_l.text})
		_focus_idx = 0
	side = opts.get("side", side)
	title_l.text = title
	sub_l.text = opts.get("sub", "")
	builder = build
	on_close = opts.get("on_close", on_close if stack.size() > 0 else Callable())
	visible = true
	Sfx.ui("open")
	refresh()


func refresh() -> void:
	if builder.is_valid():
		builder.call(self)


func set_items(items: Array) -> void:
	for c in list.get_children():
		c.queue_free()
	var idx := 0
	var first: Button = null
	var want: Button = null
	for it in items:
		if it.has("header"):
			var h := UIKit.label(String(it.header).to_upper(), 13, UIKit.TEAL)
			list.add_child(h)
			continue
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 36)
		b.text = "  " + String(it.get("text", ""))
		b.disabled = it.get("disabled", false)
		b.focus_mode = Control.FOCUS_ALL
		if it.has("color"):
			b.add_theme_color_override("font_color", it.color)
		var right := UIKit.label(String(it.get("right", "")), 16, it.get("right_color", UIKit.GOLD))
		right.set_anchors_preset(Control.PRESET_FULL_RECT)
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		right.offset_right = -14
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(right)
		if it.has("swatch"):
			var sw := ColorRect.new()
			sw.color = it.swatch
			sw.custom_minimum_size = Vector2(22, 22)
			sw.size = Vector2(22, 22)
			sw.set_anchors_preset(Control.PRESET_CENTER_LEFT)
			sw.position = Vector2(8, -11)
			sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(sw)
			b.text = "        " + String(it.get("text", ""))
		var my_idx := idx
		var item: Dictionary = it
		b.pressed.connect(func(): _activate(item, my_idx))
		b.focus_entered.connect(func(): _focused(item, my_idx))
		b.mouse_entered.connect(func(): if not b.disabled: b.grab_focus())
		b.gui_input.connect(func(ev: InputEvent): _item_input(ev, item, my_idx))
		list.add_child(b)
		if first == null and not b.disabled:
			first = b
		if idx == _focus_idx and not b.disabled:
			want = b
		idx += 1
	await get_tree().process_frame
	if not is_open:
		return
	if want != null and is_instance_valid(want):
		want.grab_focus()
	elif first != null and is_instance_valid(first):
		first.grab_focus()
	_layout()


func _layout() -> void:
	var vs := root.size
	var ps := panel.get_combined_minimum_size()
	scroll.custom_minimum_size.y = clampf(vs.y - 260.0, 240.0, 560.0)
	var x := 48.0 if side == "left" else (vs.x - ps.x - 48.0 if side == "right" else (vs.x - ps.x) * 0.5)
	panel.position = Vector2(x, maxf((vs.y - panel.size.y) * 0.5, 30.0))


func _focused(item: Dictionary, idx: int) -> void:
	_focus_idx = idx
	if item.has("hover") and (item.hover as Callable).is_valid():
		item.hover.call()
	if item.has("desc"):
		footer.text = String(item.desc)
	else:
		footer.text = "W/S or mouse: select    Enter / E: confirm    A/D: change    Esc: back"


func _activate(item: Dictionary, idx: int) -> void:
	_focus_idx = idx
	if item.has("fn") and (item.fn as Callable).is_valid():
		Sfx.ui("select")
		item.fn.call()
		if is_open and not item.get("no_refresh", false):
			refresh()
	elif item.has("adjust"):
		item.adjust.call(1)
		refresh()


func _item_input(ev: InputEvent, item: Dictionary, idx: int) -> void:
	if item.has("adjust") and (ev.is_action_pressed("ui_left") or ev.is_action_pressed("ui_right") or ev.is_action_pressed("move_left") or ev.is_action_pressed("move_right")):
		_focus_idx = idx
		item.adjust.call(-1 if (ev.is_action_pressed("ui_left") or ev.is_action_pressed("move_left")) else 1)
		Sfx.ui("tick")
		root.get_viewport().set_input_as_handled()
		refresh()


func _input(ev: InputEvent) -> void:
	if not is_open:
		return
	if ev.is_action_pressed("ui_cancel") or ev.is_action_pressed("pause") or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT):
		back()
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("move_forward") or ev.is_action_pressed("move_back"):
		var e := InputEventAction.new()
		e.action = "ui_up" if ev.is_action_pressed("move_forward") else "ui_down"
		e.pressed = true
		Input.parse_input_event(e)
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("interact"):
		var f := root.get_viewport().gui_get_focus_owner()
		if f is Button and not (f as Button).disabled:
			(f as Button).pressed.emit()
		get_viewport().set_input_as_handled()


func back() -> void:
	Sfx.ui("back")
	if stack.is_empty():
		close()
		return
	var s: Dictionary = stack.pop_back()
	title_l.text = s.title
	sub_l.text = s.sub
	builder = s.builder
	_focus_idx = s.focus
	refresh()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	stack.clear()
	G.ui_blocking = maxi(G.ui_blocking - 1, 0)
	if pause_game:
		get_tree().paused = false
	if G.ui_blocking == 0:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for c in list.get_children():
		c.queue_free()
	var cb := on_close
	on_close = Callable()
	if cb.is_valid():
		cb.call()
