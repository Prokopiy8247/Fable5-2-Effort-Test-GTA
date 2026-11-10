class_name UiList
extends ScrollContainer
## Scrolling list with selection. Rows are UiListRow (see there for the item dictionary keys).
## Keyboard / gamepad: ui_up / ui_down (arrows, W/S, d-pad) move the focus, ui_accept activates;
## mouse: hover selects, click activates.
##     var list := UiList.new()
##     list.set_items([{"text": "Pistol", "price": 450, "icon": &"handgun", "id": "pistol"}])
##     list.item_activated.connect(func(i, item): buy(item["id"]))
##     list.grab()

signal item_selected(index: int, item: Dictionary)
signal item_activated(index: int, item: Dictionary)

var selected: int = -1
var _box: VBoxContainer
var _rows: Array[UiListRow] = []


func _init() -> void:
	follow_focus = true
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_box)


func get_count() -> int:
	return _rows.size()


func clear_items() -> void:
	for r in _rows:
		_box.remove_child(r)
		r.queue_free()
	_rows.clear()
	selected = -1


func set_items(items: Array, keep_selection: bool = false) -> void:
	var prev := selected
	var had_focus := has_focus_inside()
	clear_items()
	for it in items:
		if it is Dictionary:
			add_item(it)
	if keep_selection and prev >= 0 and not _rows.is_empty():
		select(clampi(prev, 0, _rows.size() - 1), had_focus)


func add_item(item: Dictionary) -> int:
	var row := UiListRow.new(item)
	var index := _rows.size()
	_rows.append(row)
	_box.add_child(row)
	row.focus_entered.connect(_on_row_focus.bind(row))
	row.activated.connect(_on_row_activated.bind(row))
	return index


func get_item(index: int) -> Dictionary:
	if index < 0 or index >= _rows.size():
		return {}
	return _rows[index].item


func get_row(index: int) -> UiListRow:
	if index < 0 or index >= _rows.size():
		return null
	return _rows[index]


## Replace the data of one row (redraws it).
func update_item(index: int, item: Dictionary) -> void:
	if index >= 0 and index < _rows.size():
		_rows[index].set_item(item)


func refresh() -> void:
	for r in _rows:
		r.queue_redraw()


func select(index: int, grab_focus_too: bool = true) -> void:
	if index < 0 or index >= _rows.size():
		return
	_set_selected(index)
	if grab_focus_too and _rows[index].is_inside_tree():
		_rows[index].grab_focus()


## Give keyboard focus to the selected row (or the first enabled one).
func grab() -> void:
	if _rows.is_empty():
		return
	var idx := selected
	if idx < 0:
		idx = 0
		for i in _rows.size():
			if not _rows[i].is_disabled():
				idx = i
				break
	select(idx, true)


func has_focus_inside() -> bool:
	for r in _rows:
		if r.has_focus():
			return true
	return false


func _set_selected(index: int) -> void:
	if selected == index:
		return
	if selected >= 0 and selected < _rows.size():
		_rows[selected].selected = false
	selected = index
	_rows[index].selected = true
	item_selected.emit(index, _rows[index].item)


func _on_row_focus(row: UiListRow) -> void:
	var idx := _rows.find(row)
	if idx >= 0:
		if idx != selected:
			UiKit.sfx("ui_hover", -10.0)
		_set_selected(idx)


func _on_row_activated(row: UiListRow) -> void:
	var idx := _rows.find(row)
	if idx >= 0:
		_set_selected(idx)
		item_activated.emit(idx, row.item)
