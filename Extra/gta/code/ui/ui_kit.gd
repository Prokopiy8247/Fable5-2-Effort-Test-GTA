class_name UIKit
## Shared UI theme for Cinder Bay: dark glass panels, coral + teal accents.

const BG := Color(0.05, 0.065, 0.09, 0.82)
const BG2 := Color(0.10, 0.12, 0.16, 0.9)
const CORAL := Color("ff6b4a")
const TEAL := Color("3fe0c5")
const GOLD := Color("ffd23e")
const TEXT := Color("f2f4f7")
const DIM := Color(0.72, 0.76, 0.82)

static var _theme: Theme


static func box(c: Color, radius: int = 8, border: Color = Color(0, 0, 0, 0), bw: int = 0, pad: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	t.set_stylebox("panel", "PanelContainer", box(BG, 12, Color(1, 1, 1, 0.08), 1, 14))
	t.set_stylebox("panel", "Panel", box(BG, 12))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.75))
	t.set_constant("outline_size", "Label", 4)
	t.set_stylebox("normal", "Button", box(Color(1, 1, 1, 0.04), 6, Color(0, 0, 0, 0), 0, 7))
	t.set_stylebox("hover", "Button", box(Color(1, 1, 1, 0.12), 6, Color(0, 0, 0, 0), 0, 7))
	t.set_stylebox("pressed", "Button", box(CORAL.darkened(0.2), 6, Color(0, 0, 0, 0), 0, 7))
	t.set_stylebox("focus", "Button", box(Color(CORAL.r, CORAL.g, CORAL.b, 0.9), 6, Color(1, 1, 1, 0.5), 1, 7))
	t.set_stylebox("disabled", "Button", box(Color(1, 1, 1, 0.02), 6, Color(0, 0, 0, 0), 0, 7))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.52, 0.56))
	t.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.55), 4, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(TEAL, 4, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("slider", "HSlider", box(Color(0, 0, 0, 0.6), 4, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("grabber_area", "HSlider", box(TEAL, 4, Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(TEAL.lightened(0.2), 4, Color(0, 0, 0, 0), 0, 4))
	_theme = t
	return t


static func label(text: String, size: int = 18, col: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


static func bar(col: Color, w: float, h: float = 10.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	b.max_value = 1.0
	b.step = 0.001
	b.add_theme_stylebox_override("fill", box(col, 4, Color(0, 0, 0, 0), 0, 0))
	return b
