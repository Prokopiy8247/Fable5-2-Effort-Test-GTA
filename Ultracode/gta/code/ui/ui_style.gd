class_name UiStyle
extends RefCounted
## HALCYON BAY UI identity: palette, type scale, cached fonts / style boxes and small draw helpers.
##
## The logical canvas is 1920x1080 (stretch mode canvas_items, aspect expand), so every size in the
## UI module is in LOGICAL pixels: at 1280x720 everything is drawn at 2/3 size, at 4K at 2x.
## Look: deep navy translucent "glass" panels, rounded corners, coral / teal / sun-yellow accents,
## bold condensed caps for headings. No font or icon files: fonts are FontVariations of the engine
## font, icons are drawn in code (see UiIcons).

# --- palette (matches tools/blender/gta_bl.py PALETTE: Navy, Coral, Teal, Mustard / NeonYellow, Cream) ---
const NAVY_DEEP := Color(0.035, 0.07, 0.125)
const NAVY := Color(0.075, 0.137, 0.227)
const NAVY_MID := Color(0.114, 0.2, 0.322)
const NAVY_LIGHT := Color(0.173, 0.29, 0.44)
const CORAL := Color(0.933, 0.494, 0.392)
const CORAL_HOT := Color(1.0, 0.365, 0.302)
const TEAL := Color(0.133, 0.655, 0.627)
const TEAL_LIGHT := Color(0.373, 0.839, 0.8)
const SUN := Color(0.969, 0.788, 0.282)
const CREAM := Color(0.965, 0.937, 0.878)
const TEXT := Color(0.961, 0.953, 0.933)
const MUTED := Color(0.655, 0.722, 0.8)
const DIM := Color(0.42, 0.49, 0.58)
const GOOD := Color(0.345, 0.839, 0.553)
const BAD := Color(1.0, 0.353, 0.322)
const POLICE_BLUE := Color(0.231, 0.51, 1.0)
const POLICE_RED := Color(1.0, 0.231, 0.231)
const GLASS := Color(0.043, 0.086, 0.149, 0.84)
const GLASS_LIGHT := Color(0.09, 0.16, 0.26, 0.88)
const GLASS_SOLID := Color(0.05, 0.098, 0.168, 0.97)
const LINE := Color(1, 1, 1, 0.12)
const LINE_STRONG := Color(1, 1, 1, 0.24)
const SHADOW := Color(0, 0, 0, 0.5)
const CLEAR := Color(0, 0, 0, 0)

# --- type scale (logical px) ---
const FS_TINY := 17
const FS_SMALL := 20
const FS_BODY := 24
const FS_LARGE := 29
const FS_H3 := 33
const FS_H2 := 42
const FS_H1 := 62
const FS_HUGE := 132

const MARGIN := 40.0        ## screen-safe margin
const RADIUS := 18          ## default panel corner radius
const RADIUS_SMALL := 10

## toast / notify kinds -> accent colour
const KIND_COLORS := {
	"info": TEAL_LIGHT, "good": GOOD, "warn": SUN, "bad": BAD, "money": SUN, "skill": TEAL_LIGHT,
	"radio": CORAL, "district": CREAM,
}
const KIND_ICONS := {
	"info": &"info", "good": &"check", "warn": &"warn", "bad": &"close", "money": &"dollar",
	"skill": &"stats", "radio": &"radio", "district": &"pin",
}

static var _fonts: Dictionary = {}
static var _boxes: Dictionary = {}
static var _tabular_tag: int = -1


# --- fonts -----------------------------------------------------------------------------------------

## kinds: "body", "bold", "head" (condensed heavy caps), "num" (bold, tabular digits).
static func font(kind: StringName = &"body") -> Font:
	var cached: Variant = _fonts.get(kind)
	if cached != null:
		return cached as Font
	var f := make_font(kind, true)
	_fonts[kind] = f
	return f


## Fresh FontVariation. with_base = false leaves base_font empty (the engine falls back to the
## project default font) so that a saved Theme does not embed the whole font file.
static func make_font(kind: StringName, with_base: bool = true) -> FontVariation:
	var f := FontVariation.new()
	if with_base:
		f.base_font = ThemeDB.fallback_font
	match kind:
		&"head":
			f.variation_embolden = 1.05
			f.variation_transform = Transform2D(Vector2(0.86, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
			f.spacing_glyph = 2
		&"bold":
			f.variation_embolden = 0.75
		&"num":
			f.variation_embolden = 0.85
			f.variation_transform = Transform2D(Vector2(0.94, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
			var ts := TextServerManager.get_primary_interface()
			if ts != null:
				f.opentype_features = {ts.name_to_tag("tnum"): 1}
		_:
			f.variation_embolden = 0.25
	return f


# --- style boxes -----------------------------------------------------------------------------------

static func box(bg: Color, radius: int = RADIUS, border: Color = CLEAR, border_w: int = 0,
		shadow: int = 0, pad_x: float = 0.0, pad_y: float = 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 10
	sb.anti_aliasing = true
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border
	if shadow > 0:
		sb.shadow_color = Color(0, 0, 0, 0.32)
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, shadow * 0.3)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


## Shared (do not mutate) style boxes for custom _draw code: "glass", "glass_light", "pill",
## "track", "key", "toast", "select", "select_dim", "chip", "solid".
static func cached_box(key: StringName) -> StyleBoxFlat:
	var cached: Variant = _boxes.get(key)
	if cached != null:
		return cached as StyleBoxFlat
	var sb: StyleBoxFlat
	match key:
		&"glass": sb = box(GLASS, RADIUS, LINE, 2, 14)
		&"glass_light": sb = box(GLASS_LIGHT, 14, LINE, 2)
		&"solid": sb = box(GLASS_SOLID, RADIUS, LINE, 2, 18)
		&"pill": sb = box(GLASS, 100, LINE, 2, 10)
		&"track": sb = box(Color(1, 1, 1, 0.14), 100)
		&"track_dark": sb = box(Color(0, 0, 0, 0.45), 100)
		&"key":
			sb = box(CREAM, 8)
			sb.border_width_bottom = 4
			sb.border_color = Color(0.62, 0.6, 0.55)
		&"toast": sb = box(GLASS, 14, LINE, 2, 10)
		&"select":
			sb = box(Color(1, 1, 1, 0.13), 12)
			sb.border_width_left = 6
			sb.border_color = CORAL
		&"select_dim":
			sb = box(Color(1, 1, 1, 0.07), 12)
			sb.border_width_left = 6
			sb.border_color = Color(CORAL, 0.45)
		&"hover": sb = box(Color(1, 1, 1, 0.06), 12)
		&"chip": sb = box(Color(1, 1, 1, 0.1), 8)
		_: sb = box(GLASS, RADIUS, LINE, 2)
	_boxes[key] = sb
	return sb


# --- text helpers (for custom _draw) ---------------------------------------------------------------

## Draw a string with its BASELINE at pos (optional soft drop shadow for text over the 3D world).
static func text(ci: CanvasItem, f: Font, pos: Vector2, s: String, size: int, col: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, shadow: bool = true) -> void:
	if shadow:
		ci.draw_string(f, pos + Vector2(0.0, 2.0), s, align, width, size, Color(0, 0, 0, 0.6 * col.a))
	ci.draw_string(f, pos, s, align, width, size, col)


## Draw a string vertically centred inside rect.
static func text_in(ci: CanvasItem, f: Font, rect: Rect2, s: String, size: int, col: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, shadow: bool = false) -> void:
	var y := rect.position.y + (rect.size.y + f.get_ascent(size) - f.get_descent(size)) * 0.5
	text(ci, f, Vector2(rect.position.x, y), s, size, col, align, rect.size.x, shadow)


static func text_width(f: Font, s: String, size: int) -> float:
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x


## Outlined text (banners, big numbers over the world).
static func text_outlined(ci: CanvasItem, f: Font, pos: Vector2, s: String, size: int, col: Color,
		outline: int, outline_col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	ci.draw_string_outline(f, pos, s, align, width, size, outline, outline_col)
	ci.draw_string(f, pos, s, align, width, size, col)


static func keycap_width(label: String, size: int = FS_SMALL) -> float:
	return maxf(text_width(font(&"bold"), label, size) + 22.0, size + 20.0)


## Draws a keyboard key cap with its top-left corner at pos; returns the width used.
static func draw_keycap(ci: CanvasItem, pos: Vector2, label: String, size: int = FS_SMALL) -> float:
	var w := keycap_width(label, size)
	var r := Rect2(pos, Vector2(w, size + 16.0))
	ci.draw_style_box(cached_box(&"key"), r)
	text_in(ci, font(&"bold"), Rect2(r.position, r.size - Vector2(0, 4)), label, size, NAVY_DEEP, HORIZONTAL_ALIGNMENT_CENTER)
	return w


## Rounded progress bar: track + fill (frac 0..1).
static func draw_bar(ci: CanvasItem, rect: Rect2, frac: float, col: Color, dark: bool = true) -> void:
	ci.draw_style_box(cached_box(&"track_dark" if dark else &"track"), rect)
	var f := clampf(frac, 0.0, 1.0)
	if f <= 0.001:
		return
	var w := maxf(rect.size.x * f, minf(rect.size.y, rect.size.x))
	var sb := _fill_box(col)
	ci.draw_style_box(sb, Rect2(rect.position, Vector2(w, rect.size.y)))


static func _fill_box(col: Color) -> StyleBoxFlat:
	var key := col.to_rgba32()
	var cached: Variant = _boxes.get(key)
	if cached != null:
		return cached as StyleBoxFlat
	var sb := box(col, 100)
	_boxes[key] = sb
	return sb


# --- formatting ------------------------------------------------------------------------------------

static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-$" if n < 0 else "$") + out


static func duration(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	var h := total / 3600
	var m := (total % 3600) / 60
	var s := total % 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm %02ds" % [m, s]


static func kind_color(kind: String) -> Color:
	return KIND_COLORS.get(kind, TEAL_LIGHT)


static func kind_icon(kind: String) -> StringName:
	return KIND_ICONS.get(kind, &"info")


# --- procedural textures (theme icons) -------------------------------------------------------------

## Anti-aliased disc texture (slider grabbers ...).
static func disc_texture(diameter: int, fill: Color, ring: Color = CLEAR, ring_w: float = 0.0) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var c := Vector2(diameter, diameter) * 0.5
	var r := diameter * 0.5 - 1.0
	for y in diameter:
		for x in diameter:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			var col := fill
			if ring_w > 0.0 and d > r - ring_w:
				col = ring
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a))
	return ImageTexture.create_from_image(img)


## Rounded square check box texture.
static func check_texture(size: int, on: bool) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	var rad := size * 0.22
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var q := (p - Vector2(size, size) * 0.5).abs() - Vector2(size * 0.5 - rad - 1.0, size * 0.5 - rad - 1.0)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - rad
			var a := clampf(0.5 - d, 0.0, 1.0)
			var col := Color(1, 1, 1, 0.16)
			if d > -2.5:
				col = TEAL_LIGHT if on else Color(1, 1, 1, 0.5)
			elif on and d < -5.5:
				col = TEAL
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a))
	return ImageTexture.create_from_image(img)
