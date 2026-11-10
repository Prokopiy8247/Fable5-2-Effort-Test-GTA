class_name UiListRow
extends Control
## One focusable, custom-drawn row (used by UiList, usable on its own).
## item keys (all optional):
##   text: String            main label
##   sub: String             second line (muted)
##   icon: StringName        UiIcons id drawn on the left;  icon_color: Color
##   right: String           right-aligned value;           right_color: Color
##   price: int              right-aligned price (sun yellow, red when Game.money is too low)
##   owned: bool             shows "OWNED" instead of the price
##   badge: String           small chip after the label ("NEW", "EQUIPPED" ...)
##   disabled: bool          greyed out, cannot be activated
##   id: Variant             free payload for the caller

signal activated()

var item: Dictionary = {}
var selected: bool = false:
	set(v):
		if selected != v:
			selected = v
			queue_redraw()
var _hover: bool = false


func _init(p_item: Dictionary = {}) -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_item(p_item)


func set_item(d: Dictionary) -> void:
	item = d
	custom_minimum_size = Vector2(240.0, 76.0 if str(d.get("sub", "")) != "" else 54.0)
	queue_redraw()


func is_disabled() -> bool:
	return bool(item.get("disabled", false))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if not has_focus():
			grab_focus()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			grab_focus()
			_activate()
			accept_event()
	elif event.is_action_pressed("ui_accept"):
		_activate()
		accept_event()


func _activate() -> void:
	if is_disabled():
		UiKit.sfx("ui_error")
		return
	UiKit.sfx("ui_click")
	activated.emit()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT:
			queue_redraw()
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var focused := has_focus()
	if focused:
		draw_style_box(UiStyle.cached_box(&"select"), r)
	elif selected:
		draw_style_box(UiStyle.cached_box(&"select_dim"), r)
	elif _hover:
		draw_style_box(UiStyle.cached_box(&"hover"), r)
	var disabled := is_disabled()
	var col: Color = UiStyle.DIM if disabled else (Color.WHITE if focused else UiStyle.TEXT)
	var x := 22.0
	var icon_id: StringName = item.get("icon", &"")
	if icon_id != &"":
		var ic: Color = item.get("icon_color", col)
		if disabled:
			ic = UiStyle.DIM
		UiIcons.draw(self, icon_id, Vector2(x + 16.0, size.y * 0.5), 30.0, ic)
		x += 46.0
	# right side first (so the label can be clipped against it)
	var right_w := 0.0
	var num := UiStyle.font(&"num")
	var right_text := str(item.get("right", ""))
	var right_col: Color = item.get("right_color", UiStyle.MUTED if not focused else UiStyle.TEXT)
	if item.has("price"):
		if bool(item.get("owned", false)):
			right_text = "OWNED"
			right_col = UiStyle.TEAL_LIGHT
		else:
			var price := int(item["price"])
			right_text = "FREE" if price <= 0 else UiStyle.money(price)
			right_col = UiStyle.SUN if Game.money >= price else UiStyle.BAD
	if disabled and not item.has("price"):
		right_col = UiStyle.DIM
	if right_text != "":
		right_w = UiStyle.text_width(num, right_text, UiStyle.FS_BODY) + 18.0
		UiStyle.text_in(self, num, Rect2(0.0, 0.0, size.x - 20.0, size.y), right_text, UiStyle.FS_BODY, right_col, HORIZONTAL_ALIGNMENT_RIGHT)
	var body := UiStyle.font(&"bold")
	var label_text := str(item.get("text", ""))
	var avail := maxf(size.x - x - right_w - 24.0, 40.0)
	var sub := str(item.get("sub", ""))
	var text_rect := Rect2(x, 0.0, avail, size.y)
	if sub != "":
		text_rect = Rect2(x, 6.0, avail, size.y * 0.5)
		UiStyle.text_in(self, UiStyle.font(&"body"), Rect2(x, size.y * 0.5 - 2.0, avail, size.y * 0.5 - 6.0), sub, UiStyle.FS_SMALL,
				UiStyle.DIM if disabled else UiStyle.MUTED)
	UiStyle.text_in(self, body, text_rect, label_text, UiStyle.FS_BODY, col)
	var badge := str(item.get("badge", ""))
	if badge != "":
		var bx := x + minf(UiStyle.text_width(body, label_text, UiStyle.FS_BODY), avail) + 14.0
		var bw := UiStyle.text_width(body, badge, UiStyle.FS_TINY) + 20.0
		if bx + bw < size.x - right_w - 20.0:
			var br := Rect2(bx, text_rect.position.y + text_rect.size.y * 0.5 - 14.0, bw, 28.0)
			draw_style_box(UiStyle._fill_box(Color(UiStyle.TEAL, 0.85)), br)
			UiStyle.text_in(self, body, br, badge, UiStyle.FS_TINY, UiStyle.NAVY_DEEP, HORIZONTAL_ALIGNMENT_CENTER)
