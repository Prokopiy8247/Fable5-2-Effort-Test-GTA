class_name MenuList
extends Control
## Reusable list menu (pause menu, shops, phone, admin menu). Pages are built from plain
## row dictionaries so every menu in the game is data:
##   text, right, desc           labels
##   fn: Callable                confirm action
##   page: Callable -> Array     opens a sub page (title = text, or "page_title"); on_leave: Callable runs when it closes
##   opts: Array, idx, on_opt    left / right cycling with live preview (on_opt(idx))
##   slider: {min, max, step, value, on_change}
##   swatch: Color               colour chip on the right
##   off: bool                   greyed out, not selectable
##   info: bool                  plain read-only line (stats, key bindings)
##   header: bool                section heading
## Keyboard: W/S or arrows, A/D or arrows, Enter/E/Space, Esc/Backspace. Mouse: hover, click, wheel.

signal closed()

const ROW_H := 34.0
const PAD := 18.0

var accent := Color(0.18, 0.9, 1.0)
var accent2 := Color(1.0, 0.25, 0.63)
var panel_w := 560.0
var align_right := false           # phone-style panel on the right edge
var pages: Array = []              # {title, subtitle, build: Callable, sel, scroll, rows}
var footer := ""
var font: Font
var _hover := -1
var _repeat := 0.0
var _repeat_dir := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	visible = false

# ---------------------------------------------------------------- pages
func open(title: String, subtitle: String, build: Callable) -> void:
	pages.clear()
	push_page(title, subtitle, build)
	visible = true
	queue_redraw()

func push_page(title: String, subtitle: String, build: Callable, on_leave := Callable()) -> void:
	var page := {"title": title, "subtitle": subtitle, "build": build, "sel": 0, "scroll": 0, "rows": [], "leave": on_leave}
	pages.append(page)
	_rebuild(page)
	page["sel"] = _next_selectable(page, -1, 1)
	Audio.play_ui(&"ui_select", -10.0)

func back() -> void:
	if pages.size() <= 1:
		close()
		return
	var leaving: Dictionary = pages.pop_back()
	if (leaving["leave"] as Callable).is_valid():
		(leaving["leave"] as Callable).call()
	_rebuild(pages.back())
	Audio.play_ui(&"ui_back", -10.0)
	queue_redraw()

func close() -> void:
	while not pages.is_empty():
		var leaving: Dictionary = pages.pop_back()
		if (leaving["leave"] as Callable).is_valid():
			(leaving["leave"] as Callable).call()
	visible = false
	closed.emit()

func refresh() -> void:
	if pages.is_empty():
		return
	_rebuild(pages.back())
	queue_redraw()

func _rebuild(page: Dictionary) -> void:
	var rows: Array = (page["build"] as Callable).call()
	page["rows"] = rows
	page["sel"] = clampi(int(page["sel"]), 0, maxi(rows.size() - 1, 0))
	if not rows.is_empty() and not _selectable(rows[int(page["sel"])]):
		page["sel"] = _next_selectable(page, int(page["sel"]), 1)

static func _selectable(row: Dictionary) -> bool:
	return not row.get("header", false) and not row.get("off", false) and not row.get("info", false)

func _next_selectable(page: Dictionary, from: int, dir: int) -> int:
	var rows: Array = page["rows"]
	var n := rows.size()
	if n == 0:
		return 0
	var i := from
	for step in n:
		i = posmod(i + dir, n)
		if _selectable(rows[i]):
			return i
	return maxi(from, 0)

func current_row() -> Dictionary:
	if pages.is_empty():
		return {}
	var page: Dictionary = pages.back()
	var rows: Array = page["rows"]
	if rows.is_empty():
		return {}
	return rows[clampi(int(page["sel"]), 0, rows.size() - 1)]

# ---------------------------------------------------------------- layout
func _panel_rect() -> Rect2:
	var s := size
	var w := minf(panel_w, s.x - 40.0)
	var x := s.x - w - 56.0 if align_right else 56.0
	return Rect2(x, 70.0, w, s.y - 140.0)

func _visible_rows() -> int:
	return maxi(4, int((_panel_rect().size.y - 78.0 - 96.0) / ROW_H))

func _row_at(p: Vector2) -> int:
	if pages.is_empty():
		return -1
	var r := _panel_rect()
	var y0 := r.position.y + 78.0
	if p.x < r.position.x or p.x > r.end.x or p.y < y0:
		return -1
	var i := int((p.y - y0) / ROW_H) + int(pages.back()["scroll"])
	var rows: Array = pages.back()["rows"]
	if i < 0 or i >= rows.size() or int((p.y - y0) / ROW_H) >= _visible_rows():
		return -1
	return i

# ---------------------------------------------------------------- input
func _move(dir: int) -> void:
	var page: Dictionary = pages.back()
	page["sel"] = _next_selectable(page, int(page["sel"]), dir)
	_keep_visible(page)
	_preview()
	Audio.play_ui(&"ui_move", -14.0)
	queue_redraw()

func _keep_visible(page: Dictionary) -> void:
	var vis := _visible_rows()
	var sel := int(page["sel"])
	var sc := int(page["scroll"])
	if sel < sc:
		sc = sel
	elif sel >= sc + vis:
		sc = sel - vis + 1
	# keep a heading above the first row visible when possible
	if sc > 0 and sel == sc and (page["rows"] as Array)[sc - 1].get("header", false):
		sc -= 1
	page["scroll"] = clampi(sc, 0, maxi((page["rows"] as Array).size() - vis, 0))

## Rows with a "hover" Callable get it called when highlighted (live previews).
func _preview() -> void:
	var row := current_row()
	if row.has("hover"):
		(row["hover"] as Callable).call()

func _change(dir: int) -> void:
	var row := current_row()
	if row.is_empty():
		return
	if row.has("opts"):
		var opts: Array = row["opts"]
		if opts.is_empty():
			return
		row["idx"] = posmod(int(row.get("idx", 0)) + dir, opts.size())
		if row.has("on_opt"):
			(row["on_opt"] as Callable).call(int(row["idx"]))
		Audio.play_ui(&"ui_move", -12.0)
	elif row.has("slider"):
		var sl: Dictionary = row["slider"]
		var v := clampf(float(sl["value"]) + float(sl.get("step", 0.1)) * float(dir), float(sl["min"]), float(sl["max"]))
		sl["value"] = v
		(sl["on_change"] as Callable).call(v)
		Audio.play_ui(&"ui_move", -12.0)
	queue_redraw()

func _activate() -> void:
	var row := current_row()
	if row.is_empty() or not _selectable(row):
		return
	if row.has("page"):
		push_page(String(row.get("page_title", row.get("text", ""))), String(row.get("page_sub", "")), row["page"], row.get("on_leave", Callable()))
		queue_redraw()
		return
	if row.has("fn"):
		Audio.play_ui(&"ui_select", -8.0)
		(row["fn"] as Callable).call()
		if visible and not pages.is_empty():
			refresh()
		return
	if row.has("opts") or row.has("slider"):
		_change(1)

## Returns true when the event was consumed.
func handle_input(event: InputEvent) -> bool:
	if not visible or pages.is_empty():
		return false
	if event is InputEventKey and event.pressed:
		var k := (event as InputEventKey).keycode
		match k:
			KEY_UP, KEY_W:
				_move(-1)
				_repeat_dir = -1
				_repeat = 0.35
			KEY_DOWN, KEY_S:
				_move(1)
				_repeat_dir = 1
				_repeat = 0.35
			KEY_LEFT, KEY_A:
				_change(-1)
			KEY_RIGHT, KEY_D:
				_change(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_SPACE:
				if not (event as InputEventKey).echo:
					_activate()
			KEY_ESCAPE, KEY_BACKSPACE:
				if not (event as InputEventKey).echo:
					back()
			KEY_PAGEDOWN:
				for i in 8:
					_move(1)
			KEY_PAGEUP:
				for i in 8:
					_move(-1)
			_:
				return false
		return true
	if event is InputEventMouseMotion:
		var i := _row_at((event as InputEventMouseMotion).position)
		if i != _hover:
			_hover = i
			if i >= 0 and _selectable((pages.back()["rows"] as Array)[i]) and i != int(pages.back()["sel"]):
				pages.back()["sel"] = i
				_preview()
				queue_redraw()
		return true
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				var i2 := _row_at(mb.position)
				if i2 >= 0 and _selectable((pages.back()["rows"] as Array)[i2]):
					pages.back()["sel"] = i2
					var row: Dictionary = (pages.back()["rows"] as Array)[i2]
					if (row.has("opts") or row.has("slider")) and not row.has("fn") and not row.has("page"):
						# clicking the left / right half of the value steps it
						_change(-1 if mb.position.x < _panel_rect().position.x + _panel_rect().size.x * 0.72 else 1)
					else:
						_activate()
			MOUSE_BUTTON_RIGHT:
				back()
			MOUSE_BUTTON_WHEEL_DOWN:
				_move(1)
			MOUSE_BUTTON_WHEEL_UP:
				_move(-1)
		return true
	return false

func _process(delta: float) -> void:
	if not visible or pages.is_empty():
		return
	# held up / down auto-repeat (key echo is unreliable while the tree is paused)
	if _repeat_dir != 0:
		var held := Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S) if _repeat_dir > 0 else Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)
		if not held:
			_repeat_dir = 0
		else:
			_repeat -= delta / maxf(Engine.time_scale, 0.05)
			if _repeat <= 0.0:
				_repeat = 0.07
				_move(_repeat_dir)

# ---------------------------------------------------------------- drawing
func _txt(pos: Vector2, s: String, px: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos, s, align, width, px, col)

func _draw() -> void:
	if pages.is_empty():
		return
	var page: Dictionary = pages.back()
	var rows: Array = page["rows"]
	var r := _panel_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.02, 0.38))
	draw_rect(r, Color(0.035, 0.045, 0.065, 0.93))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 62.0)), Color(0.06, 0.08, 0.11, 0.98))
	draw_rect(Rect2(r.position, Vector2(5.0, 62.0)), accent)
	draw_rect(Rect2(r.position + Vector2(0, 62.0), Vector2(r.size.x, 2.0)), accent2)
	_txt(r.position + Vector2(PAD + 4.0, 30.0), String(page["title"]).to_upper(), 24, Color.WHITE)
	var crumb := String(page["subtitle"])
	if crumb == "" and pages.size() > 1:
		var parts: PackedStringArray = []
		for i in pages.size() - 1:
			parts.append(String(pages[i]["title"]))
		crumb = " / ".join(parts)
	_txt(r.position + Vector2(PAD + 4.0, 52.0), crumb, 13, Color(0.62, 0.7, 0.78))
	_txt(r.position + Vector2(0, 30.0), "$" + HUD._commas(Game.cash), 18, Color(0.55, 1.0, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - PAD)
	var vis := _visible_rows()
	var sc := int(page["scroll"])
	var y := r.position.y + 78.0
	for i in range(sc, mini(rows.size(), sc + vis)):
		var row: Dictionary = rows[i]
		var rr := Rect2(r.position.x + 8.0, y, r.size.x - 16.0, ROW_H - 3.0)
		var selected := i == int(page["sel"])
		if row.get("header", false):
			_txt(Vector2(rr.position.x + 6.0, y + 23.0), String(row.get("text", "")).to_upper(), 13, accent)
			draw_rect(Rect2(rr.position.x + 6.0, y + ROW_H - 5.0, rr.size.x - 12.0, 1.0), Color(accent, 0.35))
			y += ROW_H
			continue
		if selected:
			draw_rect(rr, Color(accent, 0.2))
			draw_rect(Rect2(rr.position, Vector2(4.0, rr.size.y)), accent)
		var off: bool = row.get("off", false)
		var col := Color(0.45, 0.48, 0.52) if off else (Color.WHITE if selected else Color(0.86, 0.89, 0.93))
		_txt(Vector2(rr.position.x + 14.0, y + 22.0), String(row.get("text", "")), 17, col)
		var right := String(row.get("right", ""))
		var right_col := Color(0.6, 0.95, 0.65) if right.begins_with("$") else Color(0.7, 0.76, 0.84)
		if row.has("right_color"):
			right_col = row["right_color"]
		var rx := rr.end.x - 12.0
		if row.has("swatch"):
			draw_rect(Rect2(rx - 22.0, y + 6.0, 22.0, ROW_H - 15.0), row["swatch"])
			draw_rect(Rect2(rx - 22.0, y + 6.0, 22.0, ROW_H - 15.0), Color(1, 1, 1, 0.5), false, 1.0)
			rx -= 32.0
		if row.has("opts"):
			var opts: Array = row["opts"]
			var label := String(opts[clampi(int(row.get("idx", 0)), 0, opts.size() - 1)]) if not opts.is_empty() else "-"
			_txt(Vector2(rr.position.x, y + 22.0), "<  %s  >" % label, 16, accent if selected else Color(0.7, 0.76, 0.84), HORIZONTAL_ALIGNMENT_RIGHT, rx - rr.position.x)
		elif row.has("slider"):
			var sl: Dictionary = row["slider"]
			var frac := inverse_lerp(float(sl["min"]), float(sl["max"]), float(sl["value"]))
			var bw := 150.0
			var bx := rx - bw
			draw_rect(Rect2(bx, y + 13.0, bw, 7.0), Color(1, 1, 1, 0.14))
			draw_rect(Rect2(bx, y + 13.0, bw * clampf(frac, 0.0, 1.0), 7.0), accent)
			var shown := String(sl.get("fmt", "%.2f")) % float(sl["value"])
			_txt(Vector2(rr.position.x, y + 22.0), shown, 14, Color(0.7, 0.76, 0.84), HORIZONTAL_ALIGNMENT_RIGHT, bx - 10.0 - rr.position.x)
		elif right != "":
			_txt(Vector2(rr.position.x, y + 22.0), right, 16, right_col if not off else Color(0.45, 0.48, 0.52), HORIZONTAL_ALIGNMENT_RIGHT, rx - rr.position.x)
		elif row.has("page"):
			_txt(Vector2(rr.position.x, y + 22.0), ">", 16, Color(0.6, 0.66, 0.74), HORIZONTAL_ALIGNMENT_RIGHT, rx - rr.position.x)
		y += ROW_H
	# scroll hints
	if sc > 0:
		_txt(Vector2(r.position.x, r.position.y + 76.0), "more above", 11, accent, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if sc + vis < rows.size():
		_txt(Vector2(r.position.x, r.end.y - 98.0), "%d more below" % (rows.size() - sc - vis), 11, accent, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	# description + key hints
	var dy := r.end.y - 88.0
	draw_rect(Rect2(r.position.x, dy, r.size.x, 88.0), Color(0.055, 0.07, 0.095, 0.98))
	draw_rect(Rect2(r.position.x, dy, r.size.x, 1.0), Color(accent, 0.5))
	var desc := String(current_row().get("desc", ""))
	if desc != "":
		draw_multiline_string(font, Vector2(r.position.x + PAD, dy + 24.0), desc, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - PAD * 2.0, 14, 3, Color(0.82, 0.86, 0.9))
	var hint := footer if footer != "" else "W/S  select     A/D  change     Enter  confirm     Esc  back"
	_txt(Vector2(r.position.x + PAD, r.end.y - 10.0), hint, 12, Color(0.5, 0.56, 0.62))
