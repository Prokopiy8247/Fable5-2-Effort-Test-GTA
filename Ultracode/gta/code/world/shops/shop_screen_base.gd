extends UiScreen
## Shared layout + behaviour of the ECONOMY screens (weapon shop / workbench, clothing store,
## wardrobe, barber, general store). Each screen script at its UI.SCREENS path extends this file.
##
##   +------------------------------------------------------------------------------------------+
##   | ##  SHOP NAME                                                               $ 4,350       |
##   |     tagline                                                                               |
##   | [Q] TAB  TAB  TAB  TAB [E]                                                                |
##   | +-- list panel ----------------------+  +-- preview panel --------------------------------+ |
##   | | SECTION                            |  |              ( 3D preview )                      | |
##   | | > row                     $ price  |  |  NAME                                            | |
##   | |   row                     OWNED    |  |  description / stat bars / swatches / buttons    | |
##   | | feedback line                      |  |                                                  | |
##   | +------------------------------------+  +--------------------------------------------------+ |
##   | [W][S] Navigate  [Enter] Buy  [Esc] Back                                                   |
##   +------------------------------------------------------------------------------------------+
##
## Keyboard: W/S or arrows move, Enter / Space activates, Q / E switch tabs, Esc backs out (the UI
## manager calls handle_back() first). Mouse: hover selects, click activates, click tabs.
## Sounds: the widgets play ui_click / ui_hover / ui_tab; purchases play ui_buy, refusals ui_error.
## The screen does not pause the world (shops are in-world); it closes itself when the player is
## hurt. Test helpers: get_items(), select_tab(), select_index(), activate_index().

const Catalog := preload("res://gta/code/world/shops/shop_catalog.gd")
const PreviewScript := preload("res://gta/code/world/shops/shop_preview.gd")
const StatBarsScript := preload("res://gta/code/world/shops/shop_stat_bars.gd")
const SwatchesScript := preload("res://gta/code/world/shops/shop_swatches.gd")

const PAUSES_GAME := false
const TIME_SCALE := 1.0
const LOCKS_INPUT := true
const SHOWS_MOUSE := true
const HIDES_HUD := true

const LEFT_W := 800.0
const FEEDBACK_SECONDS := 3.5

var shop_id: String = ""
var shop_def: Dictionary = {}
var default_shop_id: String = ""

var _header: UiHeader
var _tabs: UiTabBar = null
var _list: UiList
var _list_title: Label
var _feedback: Label
var _feedback_t: float = 0.0
var _right: UiPanel
var _preview: SubViewportContainer = null
var _preview_note: Label
var _detail: VBoxContainer
var _hints: UiKeyHints
var _items: Array = []
var _title_text: String = ""
var _subtitle_text: String = ""
var _keep_selection: bool = false


func _init() -> void:
	super()
	backdrop_alpha = 0.55


## Builds the common frame. `tabs` empty = no tab strip. preview_px (0, 0) = no 3D preview.
func _build_layout(title: String, subtitle: String, tabs: Array, preview_px: Vector2i = Vector2i(420, 420)) -> void:
	_title_text = title
	_subtitle_text = subtitle
	var margin := UiKit.margin(null, 60, 36, 60, 24)
	UiKit.fill(margin)
	add_child(margin)
	var col := UiKit.vbox(14)
	margin.add_child(col)
	_header = UiKit.header(title, subtitle, UiStyle.money(Game.money))
	_header.title_size = UiStyle.FS_H1
	col.add_child(_header)
	if not tabs.is_empty():
		_tabs = UiTabBar.new(tabs, 0)
		_tabs.tab_changed.connect(_on_tab_changed)
		col.add_child(_tabs)
	var row := UiKit.hbox(26)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	var left := UiPanel.new(&"GlassPanel", 8)
	left.custom_minimum_size = Vector2(LEFT_W, 0.0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	_list_title = UiKit.label("", &"SectionLabel")
	left.add(_list_title)
	_list = UiList.new()
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(_on_item_activated)
	left.add(_list)
	_feedback = UiKit.label("", &"ValueLabel")
	_feedback.custom_minimum_size.y = 36.0
	_feedback.add_theme_font_size_override("font_size", UiStyle.FS_BODY)
	left.add(_feedback)

	_right = UiPanel.new(&"GlassPanel", 10)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_right)
	if preview_px.x > 0 and preview_px.y > 0:
		var stage := Control.new()
		stage.custom_minimum_size = Vector2(0.0, float(preview_px.y))
		stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_right.add(stage)
		var glow := UiCanvas.new(_draw_stage)
		UiKit.fill(glow)
		stage.add_child(glow)
		var center := CenterContainer.new()
		UiKit.fill(center)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(center)
		_preview = PreviewScript.new(preview_px)
		center.add_child(_preview)
		_preview_note = UiKit.label("", &"MutedLabel", HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.fill(_preview_note)
		_preview_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stage.add_child(_preview_note)
	_detail = UiKit.vbox(8)
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add(_detail)

	_hints = UiKeyHints.new(_hint_list())
	col.add_child(_hints)
	_refresh_header()
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.player_damaged.connect(_on_player_damaged)


func _draw_stage(c: Control) -> void:
	var ctr := c.size * 0.5
	var r := minf(c.size.x, c.size.y) * 0.5
	for i in 6:
		var f := 1.0 - float(i) / 6.0
		c.draw_circle(ctr, r * f, Color(UiStyle.TEAL, 0.035 + 0.02 * float(i)))
	c.draw_arc(ctr + Vector2(0.0, r * 0.78), r * 0.62, PI * 1.12, PI * 1.88, 48, Color(UiStyle.TEAL_LIGHT, 0.25), 3.0, true)


## Key hints of the footer (override).
func _hint_list() -> Array:
	return [{"keys": ["W", "S"], "text": "Navigate"}, {"key": "Enter", "text": "Buy"}, {"action": "pause", "text": "Back"}]


func _resolve_shop(args: Dictionary) -> void:
	shop_id = str(args.get("shop_id", default_shop_id))
	shop_def = Catalog.shop_def(shop_id)
	if shop_def.is_empty() and default_shop_id != "":
		shop_id = default_shop_id
		shop_def = Catalog.shop_def(shop_id)
	if not shop_def.is_empty():
		_title_text = str(shop_def.get("display_name", _title_text))
		_subtitle_text = str(shop_def.get("tagline", _subtitle_text))
	_refresh_header()


func _refresh_header() -> void:
	if _header == null:
		return
	_header.title = _title_text
	_header.subtitle = _subtitle_text + ("   |   FREE SHOPPING" if Catalog.is_free() else "")
	_header.right_text = UiStyle.money(Game.money)


func _process(delta: float) -> void:
	if _feedback_t > 0.0:
		_feedback_t -= delta / maxf(Engine.time_scale, 0.05)
		if _feedback_t <= 0.6:
			_feedback.modulate.a = clampf(_feedback_t / 0.6, 0.0, 1.0)
		if _feedback_t <= 0.0:
			_feedback.text = ""


func _set_feedback(text: String, good: bool) -> void:
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", UiStyle.GOOD if good else UiStyle.BAD)
	_feedback.modulate.a = 1.0
	_feedback_t = FEEDBACK_SECONDS


## Feedback + sound for a Catalog result. Returns the result.
func _report(res: Dictionary, purchase: bool = true) -> Dictionary:
	var ok := bool(res.get("ok", false))
	_set_feedback(str(res.get("message", "")), ok)
	if ok:
		UiKit.sfx("ui_buy" if purchase and int(res.get("price", 0)) > 0 else "ui_click")
	else:
		UiKit.sfx("ui_error")
	return res


func _on_money_changed(_amount: int, _delta: int) -> void:
	_refresh_header()
	if _list != null:
		_list.refresh()


func _on_player_damaged(amount: float, _info: Dictionary) -> void:
	if amount > 0.5 and is_inside_tree():
		UI.notify("Interrupted", "warn", 2.0)
		close_self()


func _on_tab_changed(index: int) -> void:
	_show_tab(index)


## Override: fill the list for tab `index`.
func _show_tab(_index: int) -> void:
	pass


func _set_items(items: Array, title: String, keep: bool = false) -> void:
	_items = items
	_list_title.text = title.to_upper()
	_list.set_items(items, keep or _keep_selection)
	if _items.is_empty():
		_on_item_selected(-1, {})
	elif _list.selected < 0:
		_list.select(0, true)


## Rebuild the current list keeping the selection (after a purchase).
func _refill() -> void:
	_keep_selection = true
	_show_tab(_tabs.current if _tabs != null else 0)
	_keep_selection = false


func _on_item_selected(_index: int, _item: Dictionary) -> void:
	pass


func _on_item_activated(_index: int, item: Dictionary) -> void:
	_activate(item)


## Override: perform the row's action; return a Catalog result.
func _activate(_item: Dictionary) -> Dictionary:
	return {"ok": false, "message": ""}


func regain_focus() -> void:
	if _list != null:
		_list.grab()


func close() -> void:
	if EventBus.money_changed.is_connected(_on_money_changed):
		EventBus.money_changed.disconnect(_on_money_changed)
	if EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.disconnect(_on_player_damaged)
	if _preview != null and is_instance_valid(_preview):
		_preview.call("clear")


# --- detail helpers --------------------------------------------------------------------------

func _clear_detail() -> void:
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()


func _detail_title(text: String, sub: String = "") -> void:
	var t := UiKit.label(text.to_upper(), &"HeaderLabel")
	t.add_theme_font_size_override("font_size", UiStyle.FS_H3)
	_detail.add_child(t)
	if sub != "":
		var s := UiKit.paragraph(sub, &"MutedLabel", 300.0)
		s.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
		_detail.add_child(s)


func _detail_button_row(buttons: Array) -> HBoxContainer:
	var row := UiKit.hbox(14)
	for b: Variant in buttons:
		if b is Control:
			row.add_child(b as Control)
	_detail.add_child(row)
	return row


func _preview_none(text: String) -> void:
	if _preview != null:
		_preview.call("clear")
	if _preview_note != null:
		_preview_note.text = text


func _preview_shown() -> void:
	if _preview_note != null:
		_preview_note.text = ""


# --- test helpers ----------------------------------------------------------------------------

func get_items() -> Array:
	return _items


func get_selected_item() -> Dictionary:
	return _list.get_item(_list.selected) if _list != null else {}


func select_tab(index: int) -> void:
	if _tabs != null:
		_tabs.select(index)
	else:
		_show_tab(index)


func get_tab() -> int:
	return _tabs.current if _tabs != null else 0


func select_index(index: int) -> void:
	_list.select(index, true)


func activate_index(index: int) -> Dictionary:
	if index < 0 or index >= _items.size():
		return {"ok": false, "message": "no such row"}
	_list.select(index, true)
	return _activate(_items[index])


func find_index(key: String, value: Variant) -> int:
	for i in _items.size():
		if (_items[i] as Dictionary).get(key) == value:
			return i
	return -1
