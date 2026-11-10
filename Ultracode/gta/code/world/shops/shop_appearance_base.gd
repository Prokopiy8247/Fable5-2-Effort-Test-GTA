extends "res://gta/code/world/shops/shop_screen_base.gd"
## Shared base of the appearance screens (clothing store, wardrobe, barber) - ECONOMY A.
## One tab per appearance slot, a list of items, colour swatches (A / D or arrows, or click) and a
## live preview: a dressed clone of the player (CharacterVisual) in the preview viewport, so the real
## player only changes when you buy / wear something. Applying goes through
## Catalog.apply_player_appearance(): Player.set_appearance (-> CharacterVisual.apply_appearance +
## EventBus.player_appearance_changed) + Wanted.note_appearance_change().

const SLOT_ICONS := {"top": &"shirt", "bottom": &"person", "shoes": &"person", "hat": &"person", "glasses": &"person",
	"hair": &"scissors", "beard": &"scissors"}

var _slots: Array = []
var _registry_kind: String = "clothing"   ## "clothing" | "hair"
var _focus: String = "full"
var _swatches: Control = null
var _color_label: Label = null
var _status_label: Label = null
var _primary_btn: Button = null
var _cur_def: Dictionary = {}


func _build_appearance(title: String, subtitle: String, tab_names: Array, slots: Array, focus: String,
		preview_size: Vector2i = Vector2i(400, 420)) -> void:
	_slots = slots
	_focus = focus
	_build_layout(title, subtitle, tab_names, preview_size)
	_swatches = SwatchesScript.new()
	_swatches.connect("changed", _on_swatch_changed)


func _hint_list() -> Array:
	return [{"keys": ["W", "S"], "text": "Item"}, {"keys": ["A", "D"], "text": "Colour"}, {"key": "Enter", "text": _verb()},
		{"keys": ["Q", "E"], "text": "Category"}, {"action": "pause", "text": "Back"}]


## Verb of the primary action (override).
func _verb() -> String:
	return "Buy"


func open(args: Dictionary) -> void:
	_resolve_shop(args)
	var w := Catalog.wardrobe()
	if w != null:
		w.call("ensure_seeded", Catalog.player_appearance())
	var start := clampi(int(args.get("tab", 0)), 0, maxi(_slots.size() - 1, 0))
	if _tabs != null:
		_tabs.select(start, false)
	_show_tab(start)
	_list.grab()


func _show_tab(index: int) -> void:
	var slot: String = _slots[clampi(index, 0, _slots.size() - 1)]
	var rows := _rows_for(slot)
	_set_items(rows, _section_title(slot, rows))
	if not _keep_selection:
		for i in rows.size():
			if str((rows[i] as Dictionary).get("badge", "")) == _wearing_badge():
				_list.select(i, true)
				break


func _wearing_badge() -> String:
	return "WEARING"


func _section_title(slot: String, _rows: Array) -> String:
	return slot


## Rows for one slot (override).
func _rows_for(_slot: String) -> Array:
	return []


func _defs_for(slot: String) -> Array:
	var body := Catalog.player_body()
	return Catalog.hair_defs(slot, body) if _registry_kind == "hair" else Catalog.clothing_defs(slot, body)


# --- selection / preview ---------------------------------------------------------------------

func _on_item_selected(_index: int, item: Dictionary) -> void:
	_cur_def = item.get("def", {}) as Dictionary
	_clear_detail()
	_primary_btn = null
	if _cur_def.is_empty():
		_preview_none("")
		return
	var a := Catalog.player_appearance()
	var colors: Array = _cur_def.get("colors", []) as Array
	var key := str(_cur_def.get("color_key", ""))
	var worn := str(a.get(key, "")).to_lower() if key != "" else ""
	var cur_idx := -1
	for i in colors.size():
		if str(colors[i]).to_lower() == worn:
			cur_idx = i
	var sel := cur_idx
	if sel < 0:
		sel = maxi(colors.find(str(_cur_def.get("default_color", ""))), 0)
	_swatches.call("set_colors", colors, sel, cur_idx)
	_detail_title(str(item.get("text", "")), _describe(_cur_def))
	if colors.is_empty():
		var note := UiKit.label(_no_colour_note(), &"MutedLabel")
		note.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
		_detail.add_child(note)
	else:
		_color_label = UiKit.label("", &"SectionLabel")
		_detail.add_child(_color_label)
		if _swatches.get_parent() != null:
			_swatches.get_parent().remove_child(_swatches)
		_detail.add_child(_swatches)
	_status_label = UiKit.label("", &"ValueLabel")
	_status_label.add_theme_font_size_override("font_size", UiStyle.FS_BODY)
	_detail.add_child(_status_label)
	_primary_btn = UiKit.button(_verb(), _on_primary, &"AccentButton")
	_primary_btn.custom_minimum_size.x = 260.0
	_detail_button_row([_primary_btn])
	_update_selection_state()


## Removes the swatches from the detail box before it is cleared (they are reused).
func _clear_detail() -> void:
	if _swatches != null and _swatches.get_parent() != null:
		_swatches.get_parent().remove_child(_swatches)
	_color_label = null
	_status_label = null
	super._clear_detail()


func _describe(def: Dictionary) -> String:
	var n := (def.get("colors", []) as Array).size()
	return "%d colours" % n if n > 1 else "One style"


func _no_colour_note() -> String:
	return "No colour options"


func _selected_color() -> String:
	return str(_swatches.call("get_color")) if _swatches != null else ""


func _preview_look() -> Dictionary:
	var a := Catalog.player_appearance()
	if _cur_def.is_empty():
		return a
	var partial := Catalog.appearance_partial(_cur_def, _selected_color())
	for k: Variant in partial.keys():
		a[k] = partial[k]
	return a


func _update_selection_state() -> void:
	if _preview != null:
		if bool(_preview.call("show_character", _preview_look(), _focus)):
			_preview_shown()
		else:
			_preview_none("No character model")
	if _color_label != null:
		var colors: Array = _cur_def.get("colors", []) as Array
		_color_label.text = "COLOUR %d / %d" % [int(_swatches.get("selected")) + 1, colors.size()]
	_update_status()


## Price / ownership line + button state (override).
func _update_status() -> void:
	pass


func _on_swatch_changed(_index: int) -> void:
	_update_selection_state()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or has_dialog() or _swatches == null or _swatches.get_parent() == null:
		return
	if event.is_action_pressed("ui_left", true):
		_swatches.call("step", -1)
		UiKit.sfx("ui_hover", -8.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right", true):
		_swatches.call("step", 1)
		UiKit.sfx("ui_hover", -8.0)
		get_viewport().set_input_as_handled()


func _on_primary() -> void:
	var item := get_selected_item()
	if not item.is_empty():
		_activate(item)


## Test helper: pick a colour by index (as A / D or a click would).
func select_color(index: int) -> void:
	if _swatches != null:
		_swatches.call("select", index)


func get_color() -> String:
	return _selected_color()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _swatches != null and is_instance_valid(_swatches) and _swatches.get_parent() == null:
		_swatches.free()
