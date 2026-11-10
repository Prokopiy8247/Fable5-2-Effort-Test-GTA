class_name UiThemeBuilder
extends RefCounted
## Builds the one game Theme in code (single source of truth). The UI autoload calls build() at
## boot; gta/code/ui/tools/ui_gen_theme.gd exports the same theme to
## res://gta/resources/themes/game_theme.tres for scenes that want to reference a file.
##
## Type variations (set `theme_type_variation` on a node):
##   Label:          TitleLabel, HeaderLabel, SectionLabel, ValueLabel, MutedLabel, SmallLabel,
##                   MoneyLabel, AccentLabel
##   Button:         AccentButton, MenuEntryButton, GhostButton
##   PanelContainer: GlassPanel, SolidPanel, LightPanel, AccentPanel, FlatPanel

static func build(embed_fonts: bool = true) -> Theme:
	var t := Theme.new()
	var f_body := UiStyle.make_font(&"body", embed_fonts)
	var f_bold := UiStyle.make_font(&"bold", embed_fonts)
	var f_head := UiStyle.make_font(&"head", embed_fonts)
	var f_num := UiStyle.make_font(&"num", embed_fonts)
	t.default_font = f_body
	t.default_font_size = UiStyle.FS_BODY

	# --- labels ---
	t.set_color("font_color", "Label", UiStyle.TEXT)
	t.set_constant("line_spacing", "Label", 4)
	_label_var(t, "TitleLabel", f_head, UiStyle.FS_H1, UiStyle.CREAM)
	_label_var(t, "HeaderLabel", f_head, UiStyle.FS_H2, UiStyle.TEXT)
	_label_var(t, "SectionLabel", f_head, UiStyle.FS_LARGE, UiStyle.TEAL_LIGHT)
	_label_var(t, "ValueLabel", f_num, UiStyle.FS_BODY, UiStyle.TEXT)
	_label_var(t, "MutedLabel", f_body, UiStyle.FS_SMALL, UiStyle.MUTED)
	_label_var(t, "SmallLabel", f_body, UiStyle.FS_SMALL, UiStyle.TEXT)
	_label_var(t, "MoneyLabel", f_num, UiStyle.FS_LARGE, UiStyle.SUN)
	_label_var(t, "AccentLabel", f_bold, UiStyle.FS_BODY, UiStyle.CORAL)

	# --- buttons ---
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_font("font", type, f_bold)
		t.set_font_size("font_size", type, UiStyle.FS_BODY)
		t.set_color("font_color", type, UiStyle.TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, UiStyle.NAVY_DEEP)
		t.set_color("font_hover_pressed_color", type, UiStyle.NAVY_DEEP)
		t.set_color("font_disabled_color", type, UiStyle.DIM)
		t.set_stylebox("normal", type, UiStyle.box(Color(1, 1, 1, 0.07), 12, UiStyle.LINE, 2, 0, 24, 12))
		t.set_stylebox("hover", type, UiStyle.box(Color(1, 1, 1, 0.15), 12, UiStyle.TEAL_LIGHT, 2, 0, 24, 12))
		t.set_stylebox("pressed", type, UiStyle.box(UiStyle.SUN, 12, UiStyle.SUN, 2, 0, 24, 12))
		t.set_stylebox("disabled", type, UiStyle.box(Color(1, 1, 1, 0.03), 12, Color(1, 1, 1, 0.05), 2, 0, 24, 12))
		t.set_stylebox("focus", type, UiStyle.box(Color(1, 1, 1, 0.05), 12, UiStyle.SUN, 3, 0, 24, 12))
		t.set_constant("h_separation", type, 10)

	t.set_type_variation("AccentButton", "Button")
	t.set_color("font_color", "AccentButton", UiStyle.NAVY_DEEP)
	t.set_color("font_hover_color", "AccentButton", UiStyle.NAVY_DEEP)
	t.set_color("font_focus_color", "AccentButton", UiStyle.NAVY_DEEP)
	t.set_stylebox("normal", "AccentButton", UiStyle.box(UiStyle.CORAL, 12, UiStyle.CLEAR, 0, 0, 26, 12))
	t.set_stylebox("hover", "AccentButton", UiStyle.box(UiStyle.CORAL.lightened(0.18), 12, UiStyle.CLEAR, 0, 0, 26, 12))
	t.set_stylebox("pressed", "AccentButton", UiStyle.box(UiStyle.SUN, 12, UiStyle.CLEAR, 0, 0, 26, 12))
	t.set_stylebox("focus", "AccentButton", UiStyle.box(Color(1, 1, 1, 0.12), 12, UiStyle.CREAM, 3, 0, 26, 12))

	t.set_type_variation("MenuEntryButton", "Button")
	t.set_font("font", "MenuEntryButton", f_head)
	t.set_font_size("font_size", "MenuEntryButton", UiStyle.FS_H3)
	t.set_color("font_color", "MenuEntryButton", UiStyle.MUTED)
	t.set_color("font_pressed_color", "MenuEntryButton", UiStyle.SUN)
	t.set_color("font_hover_pressed_color", "MenuEntryButton", UiStyle.SUN)
	t.set_stylebox("normal", "MenuEntryButton", _entry_box(UiStyle.CLEAR, UiStyle.CLEAR))
	t.set_stylebox("hover", "MenuEntryButton", _entry_box(Color(1, 1, 1, 0.08), Color(UiStyle.CORAL, 0.6)))
	t.set_stylebox("pressed", "MenuEntryButton", _entry_box(Color(1, 1, 1, 0.16), UiStyle.SUN))
	t.set_stylebox("focus", "MenuEntryButton", _entry_box(Color(1, 1, 1, 0.12), UiStyle.CORAL))
	t.set_stylebox("disabled", "MenuEntryButton", _entry_box(UiStyle.CLEAR, UiStyle.CLEAR))

	t.set_type_variation("GhostButton", "Button")
	t.set_stylebox("normal", "GhostButton", UiStyle.box(UiStyle.CLEAR, 10, UiStyle.LINE_STRONG, 2, 0, 14, 8))
	t.set_stylebox("hover", "GhostButton", UiStyle.box(Color(1, 1, 1, 0.1), 10, UiStyle.LINE_STRONG, 2, 0, 14, 8))
	t.set_stylebox("pressed", "GhostButton", UiStyle.box(Color(1, 1, 1, 0.2), 10, UiStyle.CLEAR, 0, 0, 14, 8))
	t.set_stylebox("focus", "GhostButton", UiStyle.box(UiStyle.CLEAR, 10, UiStyle.SUN, 2, 0, 14, 8))
	t.set_color("font_pressed_color", "GhostButton", UiStyle.SUN)

	# --- panels ---
	var glass := UiStyle.box(UiStyle.GLASS, UiStyle.RADIUS, UiStyle.LINE, 2, 16, 26, 22)
	t.set_stylebox("panel", "PanelContainer", glass)
	t.set_stylebox("panel", "Panel", UiStyle.box(UiStyle.GLASS, UiStyle.RADIUS, UiStyle.LINE, 2, 16))
	_panel_var(t, "GlassPanel", glass)
	_panel_var(t, "SolidPanel", UiStyle.box(UiStyle.GLASS_SOLID, UiStyle.RADIUS, UiStyle.LINE, 2, 22, 28, 24))
	_panel_var(t, "LightPanel", UiStyle.box(UiStyle.GLASS_LIGHT, 14, UiStyle.LINE, 2, 0, 18, 14))
	_panel_var(t, "AccentPanel", UiStyle.box(UiStyle.GLASS, UiStyle.RADIUS, UiStyle.TEAL, 3, 16, 26, 22))
	_panel_var(t, "FlatPanel", UiStyle.box(UiStyle.CLEAR, 0))

	# --- sliders / progress ---
	var track := UiStyle.box(Color(1, 1, 1, 0.14), 6)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := UiStyle.box(UiStyle.TEAL, 6)
	var fill_hi := UiStyle.box(UiStyle.TEAL_LIGHT, 6)
	var knob := UiStyle.disc_texture(30, UiStyle.CREAM, UiStyle.NAVY_DEEP, 3.0)
	var knob_hi := UiStyle.disc_texture(34, UiStyle.SUN, UiStyle.NAVY_DEEP, 3.0)
	for type in ["HSlider", "VSlider"]:
		t.set_stylebox("slider", type, track)
		t.set_stylebox("grabber_area", type, fill)
		t.set_stylebox("grabber_area_highlight", type, fill_hi)
		t.set_icon("grabber", type, knob)
		t.set_icon("grabber_highlight", type, knob_hi)
		t.set_icon("grabber_disabled", type, knob)
	t.set_stylebox("background", "ProgressBar", UiStyle.box(Color(1, 1, 1, 0.12), 8))
	t.set_stylebox("fill", "ProgressBar", UiStyle.box(UiStyle.TEAL, 8))
	t.set_font("font", "ProgressBar", f_num)
	t.set_font_size("font_size", "ProgressBar", UiStyle.FS_SMALL)

	# --- check boxes ---
	var chk_on := UiStyle.check_texture(32, true)
	var chk_off := UiStyle.check_texture(32, false)
	for type in ["CheckBox", "CheckButton"]:
		for n in ["checked", "checked_disabled", "radio_checked", "radio_checked_disabled"]:
			t.set_icon(n, type, chk_on)
		for n in ["unchecked", "unchecked_disabled", "radio_unchecked", "radio_unchecked_disabled"]:
			t.set_icon(n, type, chk_off)
		t.set_font("font", type, f_body)
		t.set_color("font_color", type, UiStyle.TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, UiStyle.TEXT)
		t.set_stylebox("normal", type, UiStyle.box(UiStyle.CLEAR, 8, UiStyle.CLEAR, 0, 0, 8, 6))
		t.set_stylebox("hover", type, UiStyle.box(Color(1, 1, 1, 0.07), 8, UiStyle.CLEAR, 0, 0, 8, 6))
		t.set_stylebox("pressed", type, UiStyle.box(Color(1, 1, 1, 0.07), 8, UiStyle.CLEAR, 0, 0, 8, 6))
		t.set_stylebox("focus", type, UiStyle.box(UiStyle.CLEAR, 8, UiStyle.SUN, 2, 0, 8, 6))

	# --- text input ---
	t.set_stylebox("normal", "LineEdit", UiStyle.box(Color(0, 0, 0, 0.35), 10, UiStyle.LINE, 2, 0, 14, 10))
	t.set_stylebox("focus", "LineEdit", UiStyle.box(Color(0, 0, 0, 0.35), 10, UiStyle.TEAL_LIGHT, 2, 0, 14, 10))
	t.set_stylebox("read_only", "LineEdit", UiStyle.box(Color(0, 0, 0, 0.2), 10, UiStyle.LINE, 2, 0, 14, 10))
	t.set_color("font_color", "LineEdit", UiStyle.TEXT)
	t.set_color("font_placeholder_color", "LineEdit", UiStyle.DIM)
	t.set_color("caret_color", "LineEdit", UiStyle.SUN)
	t.set_color("selection_color", "LineEdit", Color(UiStyle.TEAL, 0.55))

	# --- scrolling ---
	var s_track := UiStyle.box(Color(1, 1, 1, 0.05), 5)
	s_track.content_margin_left = 5
	s_track.content_margin_right = 5
	s_track.content_margin_top = 5
	s_track.content_margin_bottom = 5
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, s_track)
		t.set_stylebox("scroll_focus", type, s_track)
		t.set_stylebox("grabber", type, UiStyle.box(Color(1, 1, 1, 0.3), 5))
		t.set_stylebox("grabber_highlight", type, UiStyle.box(UiStyle.TEAL_LIGHT, 5))
		t.set_stylebox("grabber_pressed", type, UiStyle.box(UiStyle.CORAL, 5))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())

	# --- separators / containers ---
	var sep := StyleBoxLine.new()
	sep.color = UiStyle.LINE
	sep.thickness = 2
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 18)
	var vsep := StyleBoxLine.new()
	vsep.color = UiStyle.LINE
	vsep.thickness = 2
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 14)
	t.set_constant("h_separation", "GridContainer", 18)
	t.set_constant("v_separation", "GridContainer", 10)

	# --- popups / tooltips / lists ---
	t.set_stylebox("panel", "TooltipPanel", UiStyle.box(UiStyle.GLASS_SOLID, 8, UiStyle.LINE, 2, 0, 12, 8))
	t.set_color("font_color", "TooltipLabel", UiStyle.TEXT)
	t.set_font_size("font_size", "TooltipLabel", UiStyle.FS_SMALL)
	t.set_stylebox("panel", "PopupMenu", UiStyle.box(UiStyle.GLASS_SOLID, 12, UiStyle.LINE, 2, 0, 10, 10))
	t.set_stylebox("hover", "PopupMenu", UiStyle.box(Color(UiStyle.TEAL, 0.6), 8))
	t.set_color("font_color", "PopupMenu", UiStyle.TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_constant("v_separation", "PopupMenu", 10)
	for type in ["ItemList", "Tree"]:
		t.set_stylebox("panel", type, UiStyle.box(Color(0, 0, 0, 0.25), 12, UiStyle.LINE, 2, 0, 10, 10))
		t.set_stylebox("focus", type, UiStyle.box(UiStyle.CLEAR, 12, Color(UiStyle.SUN, 0.5), 2))
		t.set_stylebox("selected", type, UiStyle.box(Color(UiStyle.TEAL, 0.45), 8))
		t.set_stylebox("selected_focus", type, UiStyle.box(Color(UiStyle.TEAL, 0.7), 8))
		t.set_stylebox("hovered", type, UiStyle.box(Color(1, 1, 1, 0.08), 8))
		t.set_stylebox("cursor", type, UiStyle.box(UiStyle.CLEAR, 8, UiStyle.SUN, 2))
		t.set_stylebox("cursor_unfocused", type, UiStyle.box(UiStyle.CLEAR, 8, UiStyle.LINE_STRONG, 2))
		t.set_color("font_color", type, UiStyle.TEXT)
		t.set_color("font_selected_color", type, Color.WHITE)
		t.set_color("font_hovered_color", type, Color.WHITE)
	t.set_constant("v_separation", "ItemList", 8)
	t.set_constant("v_separation", "Tree", 8)

	# --- tabs ---
	for type in ["TabContainer", "TabBar"]:
		t.set_font("font", type, f_head)
		t.set_font_size("font_size", type, UiStyle.FS_LARGE)
		t.set_color("font_selected_color", type, UiStyle.TEXT)
		t.set_color("font_unselected_color", type, UiStyle.MUTED)
		t.set_color("font_hovered_color", type, Color.WHITE)
		var sel := UiStyle.box(Color(1, 1, 1, 0.1), 10, UiStyle.CLEAR, 0, 0, 20, 10)
		sel.border_width_bottom = 4
		sel.border_color = UiStyle.CORAL
		t.set_stylebox("tab_selected", type, sel)
		t.set_stylebox("tab_unselected", type, UiStyle.box(UiStyle.CLEAR, 10, UiStyle.CLEAR, 0, 0, 20, 10))
		t.set_stylebox("tab_hovered", type, UiStyle.box(Color(1, 1, 1, 0.06), 10, UiStyle.CLEAR, 0, 0, 20, 10))
		t.set_stylebox("tab_focus", type, UiStyle.box(UiStyle.CLEAR, 10, UiStyle.SUN, 2))
	t.set_stylebox("panel", "TabContainer", UiStyle.box(UiStyle.GLASS, UiStyle.RADIUS, UiStyle.LINE, 2, 0, 22, 20))

	# --- rich text ---
	t.set_color("default_color", "RichTextLabel", UiStyle.TEXT)
	t.set_font("normal_font", "RichTextLabel", f_body)
	t.set_font("bold_font", "RichTextLabel", f_bold)
	t.set_font_size("normal_font_size", "RichTextLabel", UiStyle.FS_BODY)
	t.set_font_size("bold_font_size", "RichTextLabel", UiStyle.FS_BODY)
	return t


static func _label_var(t: Theme, type_name: String, f: Font, size: int, col: Color) -> void:
	t.set_type_variation(type_name, "Label")
	t.set_font("font", type_name, f)
	t.set_font_size("font_size", type_name, size)
	t.set_color("font_color", type_name, col)


static func _panel_var(t: Theme, type_name: String, sb: StyleBox) -> void:
	t.set_type_variation(type_name, "PanelContainer")
	t.set_stylebox("panel", type_name, sb)


static func _entry_box(bg: Color, bar: Color) -> StyleBoxFlat:
	var sb := UiStyle.box(bg, 12, UiStyle.CLEAR, 0, 0, 26, 12)
	sb.border_width_left = 6
	sb.border_color = bar
	return sb
