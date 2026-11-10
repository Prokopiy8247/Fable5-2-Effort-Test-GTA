class_name UiKit
extends RefCounted
## Static factory helpers for building screens in code with the Halcyon Bay look.
## See docs/UI.md ("Widget kit"). Everything returns ordinary Controls styled by the game Theme
## (the UI autoload puts the Theme on the root of every screen, so it is inherited automatically).

static func label(text: String, variation: StringName = &"", align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Wrapping paragraph label.
static func paragraph(text: String, variation: StringName = &"MutedLabel", min_width: float = 200.0) -> Label:
	var l := label(text, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = min_width
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Themed button. variation: "" (default), "AccentButton", "MenuEntryButton", "GhostButton".
static func button(text: String, on_pressed: Callable = Callable(), variation: StringName = &"") -> Button:
	var b := Button.new()
	b.text = text
	if variation != &"":
		b.theme_type_variation = variation
	if variation == &"MenuEntryButton":
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void: UiKit.sfx("ui_click"))
	b.focus_entered.connect(func() -> void: UiKit.sfx("ui_hover", -10.0))
	b.mouse_entered.connect(func() -> void: UiKit._focus_on_hover(b))
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


static func _focus_on_hover(b: Control) -> void:
	if is_instance_valid(b) and b.is_visible_in_tree() and b.focus_mode != Control.FOCUS_NONE and not b.has_focus():
		if b is BaseButton and (b as BaseButton).disabled:
			return
		b.grab_focus()


static func vbox(separation: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation: int = 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func grid(columns: int, h_sep: int = 18, v_sep: int = 10) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", h_sep)
	g.add_theme_constant_override("v_separation", v_sep)
	return g


## Wraps `child` in a MarginContainer.
static func margin(child: Control, left: int = 24, top: int = 24, right: int = -1, bottom: int = -1) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", left if right < 0 else right)
	m.add_theme_constant_override("margin_bottom", top if bottom < 0 else bottom)
	if child != null:
		m.add_child(child)
	return m


## Expanding spacer (or fixed size when min_size is given).
static func spacer(min_size: Vector2 = Vector2.ZERO, expand: bool = true) -> Control:
	var c := Control.new()
	c.custom_minimum_size = min_size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func separator() -> HSeparator:
	return HSeparator.new()


static func panel(variation: StringName = &"GlassPanel", separation: int = 12) -> UiPanel:
	return UiPanel.new(variation, separation)


static func header(title: String, subtitle: String = "", right_text: String = "") -> UiHeader:
	var h := UiHeader.new()
	h.title = title
	h.subtitle = subtitle
	h.right_text = right_text
	return h


static func icon(id: StringName, size: float = 28.0, color: Color = UiStyle.TEXT) -> UiIconRect:
	return UiIconRect.new(id, size, color)


## "name ........ value" stat line (Label pair in an HBox). Returns the HBox; the value Label is
## child 2 (use set_stat_value()).
static func stat_row(name_text: String, value_text: String, value_color: Color = UiStyle.TEXT) -> HBoxContainer:
	var h := hbox(12)
	var n := label(name_text, &"MutedLabel")
	n.add_theme_font_size_override("font_size", UiStyle.FS_BODY)
	h.add_child(n)
	h.add_child(spacer(Vector2.ZERO, true))
	var v := label(value_text, &"ValueLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	v.add_theme_color_override("font_color", value_color)
	h.add_child(v)
	return h


static func set_stat_value(row: HBoxContainer, value_text: String) -> void:
	if row != null and row.get_child_count() >= 3:
		(row.get_child(2) as Label).text = value_text


## Full-rect anchors helper.
static func fill(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


## Safe numeric property read across module boundaries (missing property / null -> fallback).
static func num(obj: Object, prop: StringName, fallback: float = 0.0) -> float:
	if obj == null or not is_instance_valid(obj):
		return fallback
	var v: Variant = obj.get(prop)
	if v is float or v is int:
		return float(v)
	return fallback


## Safe string property read across module boundaries.
static func text_of(obj: Object, prop: StringName, fallback: String = "") -> String:
	if obj == null or not is_instance_valid(obj):
		return fallback
	var v: Variant = obj.get(prop)
	if v is String or v is StringName:
		return str(v)
	return fallback


## Safe bool property read across module boundaries.
static func flag(obj: Object, prop: StringName, fallback: bool = false) -> bool:
	if obj == null or not is_instance_valid(obj):
		return fallback
	var v: Variant = obj.get(prop)
	if v is bool:
		return v
	return fallback


## UI sound (ids from ARCHITECTURE 6.11: ui_click, ui_hover, ui_open, ui_close, ui_error, ui_buy, ui_tab).
static func sfx(id: String, volume_db: float = -4.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var audio := tree.root.get_node_or_null("Audio")
	if audio != null and audio.has_method("play"):
		audio.call("play", id, volume_db, 1.0, "UI")
