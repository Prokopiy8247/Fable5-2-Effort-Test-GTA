class_name UiIcons
extends RefCounted
## Original glyph set drawn in code (no icon files). Every icon fits a square of side `s`
## centred on `c`:   UiIcons.draw(self, &"heart", Vector2(20, 20), 28.0, UiStyle.CORAL)
## Must be called from inside a CanvasItem._draw(). Unknown ids draw a small dot.
## Icons never touch draw_set_transform(), so callers may set their own transform first.

## Normalised polygons (x right, y down, -1..1), flat x,y lists.
const POLY := {
	&"shield": [-0.8, -0.75, 0.0, -1.0, 0.8, -0.75, 0.8, 0.1, 0.45, 0.7, 0.0, 1.0, -0.45, 0.7, -0.8, 0.1],
	&"bolt": [0.25, -1.0, -0.65, 0.12, -0.08, 0.12, -0.3, 1.0, 0.65, -0.18, 0.08, -0.18],
	&"house": [0.0, -0.95, 0.95, -0.1, 0.68, -0.1, 0.68, 0.9, 0.2, 0.9, 0.2, 0.3, -0.2, 0.3, -0.2, 0.9, -0.68, 0.9, -0.68, -0.1, -0.95, -0.1],
	&"cross": [-0.33, -1.0, 0.33, -1.0, 0.33, -0.33, 1.0, -0.33, 1.0, 0.33, 0.33, 0.33, 0.33, 1.0, -0.33, 1.0, -0.33, 0.33, -1.0, 0.33, -1.0, -0.33, -0.33, -0.33],
	&"shirt": [-0.45, -0.9, -0.15, -0.9, 0.0, -0.7, 0.15, -0.9, 0.45, -0.9, 1.0, -0.45, 0.72, -0.05, 0.5, -0.25, 0.5, 0.9, -0.5, 0.9, -0.5, -0.25, -0.72, -0.05, -1.0, -0.45],
	&"bag_body": [-0.7, -0.3, 0.7, -0.3, 0.85, 0.9, -0.85, 0.9],
	&"plane": [0.0, -1.0, 0.14, -0.6, 0.14, -0.2, 1.0, 0.25, 1.0, 0.45, 0.14, 0.25, 0.1, 0.7, 0.4, 0.9, 0.4, 1.0, 0.0, 0.9, -0.4, 1.0, -0.4, 0.9, -0.1, 0.7, -0.14, 0.25, -1.0, 0.45, -1.0, 0.25, -0.14, -0.2, -0.14, -0.6],
	&"arrow": [0.0, -1.0, 0.72, 0.85, 0.0, 0.45, -0.72, 0.85],
	&"pin_tip": [-0.5, 0.0, 0.5, 0.0, 0.0, 1.0],
	&"flag_cloth": [-0.6, -0.9, 0.85, -0.5, -0.6, -0.05],
	&"ramp": [-1.0, 0.7, 1.0, 0.7, 1.0, -0.55],
	&"tower": [-0.26, -0.35, 0.26, -0.35, 0.45, 0.95, -0.45, 0.95],
	&"tower_lamp": [-0.36, -0.72, 0.0, -1.0, 0.36, -0.72, 0.36, -0.42, -0.36, -0.42],
	&"mountain": [-1.0, 0.8, -0.3, -0.7, 0.1, 0.05, 0.42, -0.3, 1.0, 0.8],
	&"handgun": [-0.9, -0.5, 0.9, -0.5, 0.9, -0.12, -0.15, -0.12, -0.25, 0.1, -0.35, 0.8, -0.85, 0.8, -0.7, -0.05, -0.9, -0.12],
	&"smg": [-0.9, -0.45, 0.75, -0.45, 0.75, -0.3, 1.0, -0.3, 1.0, -0.14, 0.75, -0.14, 0.75, 0.0, 0.3, 0.0, 0.3, 0.75, 0.02, 0.75, 0.02, 0.0, -0.3, 0.0, -0.42, 0.6, -0.75, 0.6, -0.62, 0.0, -0.9, 0.0],
	&"shotgun": [-1.0, -0.28, 1.0, -0.28, 1.0, -0.1, 0.72, -0.1, 0.72, 0.12, 0.18, 0.12, 0.18, -0.06, -0.3, -0.06, -0.55, 0.02, -0.95, 0.4, -1.0, 0.1],
	&"rifle": [-1.0, -0.3, -0.45, -0.3, -0.45, -0.4, 0.55, -0.4, 0.55, -0.3, 1.0, -0.3, 1.0, -0.17, 0.55, -0.17, 0.55, -0.05, 0.15, -0.05, 0.28, 0.55, 0.02, 0.6, -0.08, -0.05, -0.3, -0.05, -0.4, 0.42, -0.62, 0.42, -0.55, 0.0, -1.0, 0.22],
	&"sniper": [-1.0, -0.1, -0.5, -0.2, 1.0, -0.2, 1.0, -0.08, 0.2, -0.08, 0.2, 0.04, -0.25, 0.04, -0.35, 0.4, -0.55, 0.4, -0.5, 0.07, -1.0, 0.28],
	&"sniper_scope": [-0.35, -0.5, 0.3, -0.5, 0.3, -0.3, -0.35, -0.3],
	&"heavy": [-1.0, -0.3, -0.8, -0.22, 0.6, -0.22, 0.6, -0.36, 1.0, -0.42, 1.0, 0.22, 0.6, 0.16, 0.6, 0.02, -0.1, 0.02, -0.18, 0.55, -0.4, 0.55, -0.36, 0.02, -0.8, 0.02, -1.0, 0.1],
	&"grenade_cap": [-0.24, -0.78, 0.24, -0.78, 0.24, -0.4, -0.24, -0.4],
	&"bat": [-0.86, 0.7, -0.7, 0.86, 0.9, -0.5, 0.5, -0.9],
	&"fists": [-0.6, -0.55, 0.6, -0.55, 0.78, -0.2, 0.78, 0.3, 0.5, 0.75, -0.5, 0.75, -0.78, 0.4, -0.78, -0.2],
	&"car_body": [-1.0, 0.1, -0.85, -0.2, -0.4, -0.25, -0.15, -0.7, 0.5, -0.7, 0.75, -0.25, 1.0, -0.15, 1.0, 0.35, -1.0, 0.35],
	&"boat_hull": [-1.0, 0.05, 1.0, 0.05, 0.7, 0.6, -0.7, 0.6],
	&"boat_sail": [-0.05, -0.95, -0.05, -0.1, 0.7, -0.1],
	&"person_body": [-0.5, 0.95, -0.5, 0.1, -0.25, -0.22, 0.25, -0.22, 0.5, 0.1, 0.5, 0.95],
	&"play": [-0.6, -0.85, 0.85, 0.0, -0.6, 0.85],
	&"save": [-0.85, -0.85, 0.55, -0.85, 0.85, -0.55, 0.85, 0.85, -0.85, 0.85],
	&"load": [-0.9, -0.6, -0.2, -0.6, 0.0, -0.35, 0.9, -0.35, 0.9, 0.7, -0.9, 0.7],
	&"map": [-0.95, -0.6, -0.32, -0.85, 0.32, -0.6, 0.95, -0.85, 0.95, 0.6, 0.32, 0.85, -0.32, 0.6, -0.95, 0.85],
	&"warn": [0.0, -0.95, 1.0, 0.8, -1.0, 0.8],
	&"tram_body": [-0.62, -0.62, -0.5, -0.78, 0.5, -0.78, 0.62, -0.62, 0.62, 0.55, -0.62, 0.55],
	&"radio_body": [-0.9, -0.3, 0.9, -0.3, 0.9, 0.8, -0.9, 0.8],
	&"lock_body": [-0.7, -0.1, 0.7, -0.1, 0.7, 0.9, -0.7, 0.9],
	&"cloud_base": [-0.8, 0.1, 0.8, 0.1, 0.8, 0.5, -0.8, 0.5],
	&"hat_crown": [-0.52, 0.22, -0.48, -0.42, -0.3, -0.66, 0.0, -0.72, 0.3, -0.66, 0.48, -0.42, 0.52, 0.22],
	&"hat_brim": [-1.0, 0.32, -0.86, 0.18, 0.86, 0.18, 1.0, 0.32, 0.86, 0.48, -0.86, 0.48],
	&"shoe": [-0.95, 0.55, -0.95, -0.3, -0.45, -0.3, -0.38, -0.05, 0.25, 0.08, 0.82, 0.22, 0.98, 0.42, 0.95, 0.55],
	&"camera_body": [-0.95, -0.45, -0.4, -0.45, -0.28, -0.7, 0.28, -0.7, 0.4, -0.45, 0.95, -0.45, 0.95, 0.75, -0.95, 0.75],
	&"medal_ribbon_l": [-0.62, -1.0, -0.22, -1.0, 0.12, -0.25, -0.28, -0.25],
	&"medal_ribbon_r": [0.22, -1.0, 0.62, -1.0, 0.28, -0.25, -0.12, -0.25],
	&"trophy_cup": [-0.68, -0.85, 0.68, -0.85, 0.6, -0.3, 0.32, 0.05, 0.12, 0.15, 0.12, 0.5, -0.12, 0.5, -0.12, 0.15, -0.32, 0.05, -0.6, -0.3],
	&"trophy_base": [-0.48, 0.62, 0.48, 0.62, 0.55, 0.92, -0.55, 0.92],
	&"note_flag": [-0.02, -0.95, 0.62, -0.62, 0.62, -0.32, -0.02, -0.62],
	&"handset": [-0.9, -0.9, -0.35, -0.9, -0.28, -0.48, -0.14, -0.3, -0.02, -0.13, 0.13, 0.02, 0.3, 0.14, 0.48, 0.28,
		0.9, 0.32, 0.9, 0.9, 0.59, 0.87, 0.28, 0.79, 0.0, 0.66, -0.37, 0.37, -0.66, 0.0, -0.84, -0.43],
}

const WEAPON_SLOT_ICONS := {
	"melee": &"bat", "handgun": &"handgun", "smg": &"smg", "shotgun": &"shotgun", "rifle": &"rifle",
	"sniper": &"sniper", "heavy": &"heavy", "thrown": &"grenade",
}
const WEATHER_ICONS := {"clear": &"sun", "cloudy": &"cloud", "rain": &"rain", "fog": &"fog", "storm": &"storm"}
const SKILL_ICONS := {
	"stamina": &"bolt", "shooting": &"target", "strength": &"fists", "stealth": &"person",
	"driving": &"car", "flying": &"plane", "lung": &"bubbles",
}

static var _shapes: Dictionary = {}


static func weapon_slot_icon(slot: String) -> StringName:
	return WEAPON_SLOT_ICONS.get(slot, &"handgun")


static func weather_icon(weather_id: String, night: bool = false) -> StringName:
	if night and weather_id == "clear":
		return &"moon"
	return WEATHER_ICONS.get(weather_id, &"sun")


static func skill_icon(skill: String) -> StringName:
	return SKILL_ICONS.get(skill, &"stats")


static func _shape(key: StringName) -> PackedVector2Array:
	var cached: Variant = _shapes.get(key)
	if cached != null:
		return cached as PackedVector2Array
	var out := PackedVector2Array()
	match key:
		&"heart":
			for i in 28:
				var t := TAU * float(i) / 28.0
				out.append(Vector2(16.0 * pow(sin(t), 3.0), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))) / 17.0 + Vector2(0, -0.12))
		&"star":
			for i in 10:
				var a := -PI * 0.5 + TAU * float(i) / 10.0
				out.append(Vector2(cos(a), sin(a)) * (1.0 if i % 2 == 0 else 0.44))
		&"drop":
			out.append(Vector2(0, -1.0))
			for i in 11:
				var a2 := deg_to_rad(-35.0 + 25.0 * float(i))
				out.append(Vector2(0, 0.32) + Vector2(cos(a2), sin(a2)) * 0.68)
		&"moon":
			for i in 13:
				var a3 := deg_to_rad(60.0 + 240.0 * float(i) / 12.0)
				out.append(Vector2(cos(a3), sin(a3)) * 0.9)
			for i in 9:
				var a4 := deg_to_rad(285.0 - 210.0 * float(i) / 8.0)
				out.append(Vector2(0.42, 0.0) + Vector2(cos(a4), sin(a4)) * 0.72)
		&"umbrella":
			for i in 13:
				var a5 := PI + PI * float(i) / 12.0
				out.append(Vector2(0, -0.05) + Vector2(cos(a5), sin(a5)) * 0.95)
		&"canopy":
			# parachute canopy: an elliptic dome with a scalloped lower edge
			for i in 15:
				var a6 := PI + PI * float(i) / 14.0
				out.append(Vector2(cos(a6) * 0.98, -0.3 + sin(a6) * 0.66))
			for k in 4:
				var x0 := 0.98 - 0.49 * float(k)
				out.append(Vector2(x0 - 0.245, -0.16))
				if k < 3:
					out.append(Vector2(x0 - 0.49, -0.3))
		&"flame":
			for i in 17:
				var t := float(i) / 16.0
				var a7 := lerpf(-0.15 * PI, 1.15 * PI, t)
				out.append(Vector2(cos(a7) * 0.62, 0.3 + sin(a7) * 0.62))
			out.append(Vector2(-0.5, -0.2))
			out.append(Vector2(-0.18, -0.55))
			out.append(Vector2(-0.12, -0.25))
			out.append(Vector2(0.05, -1.0))
			out.append(Vector2(0.45, -0.38))
			out.append(Vector2(0.58, -0.05))
		&"eye":
			for i in 13:
				var a8 := PI + PI * float(i) / 12.0
				out.append(Vector2(cos(a8) * 1.0, sin(a8) * 0.62))
			for i in range(1, 12):
				var a9 := PI * float(i) / 12.0
				out.append(Vector2(cos(a9) * 1.0, sin(a9) * 0.62))
		_:
			var flat: Array = POLY.get(key, [])
			for i in range(0, flat.size() - 1, 2):
				out.append(Vector2(float(flat[i]), float(flat[i + 1])))
	_shapes[key] = out
	return out


static func _poly(ci: CanvasItem, key: StringName, c: Vector2, h: float, col: Color) -> void:
	var src := _shape(key)
	if src.size() < 3:
		return
	var pts := PackedVector2Array()
	pts.resize(src.size())
	for i in src.size():
		pts[i] = c + src[i] * h
	ci.draw_colored_polygon(pts, col)


static func _outline(ci: CanvasItem, key: StringName, c: Vector2, h: float, col: Color, w: float) -> void:
	var src := _shape(key)
	if src.size() < 3:
		return
	var pts := PackedVector2Array()
	pts.resize(src.size() + 1)
	for i in src.size():
		pts[i] = c + src[i] * h
	pts[src.size()] = pts[0]
	ci.draw_polyline(pts, col, w, true)


static func _ln(ci: CanvasItem, c: Vector2, h: float, x0: float, y0: float, x1: float, y1: float, col: Color, w: float) -> void:
	ci.draw_line(c + Vector2(x0, y0) * h, c + Vector2(x1, y1) * h, col, w, true)


static func _dot(ci: CanvasItem, c: Vector2, h: float, x: float, y: float, r: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(x, y) * h, r * h, col, true, -1.0, true)


static func _arc(ci: CanvasItem, c: Vector2, h: float, x: float, y: float, r: float, a0: float, a1: float, col: Color, w: float) -> void:
	ci.draw_arc(c + Vector2(x, y) * h, r * h, deg_to_rad(a0), deg_to_rad(a1), 24, col, w, true)


static func _glyph(ci: CanvasItem, c: Vector2, s: float, ch: String, col: Color) -> void:
	var f := UiStyle.font(&"head")
	var size := int(maxf(s * 0.82, 8.0))
	var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	ci.draw_string(f, c + Vector2(-w * 0.5, (f.get_ascent(size) - f.get_descent(size)) * 0.5), ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, col)


## Empty star outline (unfilled wanted star).
static func draw_star_outline(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float = 2.0) -> void:
	_outline(ci, &"star", c, s * 0.5, col, w)


static func draw(ci: CanvasItem, id: StringName, c: Vector2, s: float, col: Color) -> void:
	var h := s * 0.5
	var w := maxf(1.5, s * 0.1)
	# detail colour: navy on light glyphs, cream on dark ones (e.g. navy glyphs on coloured tiles)
	var ink := Color(UiStyle.NAVY_DEEP, col.a) if col.get_luminance() > 0.3 else Color(UiStyle.CREAM, col.a)
	match id:
		&"heart", &"shield", &"star", &"bolt", &"house", &"cross", &"shirt", &"plane", &"arrow", &"ramp":
			_poly(ci, id, c, h, col)
		&"mountain", &"handgun", &"smg", &"shotgun", &"rifle", &"heavy", &"play", &"load", &"drop", &"moon":
			_poly(ci, id, c, h, col)
		&"fists":
			_poly(ci, &"fists", c, h, col)
			for i in 3:
				_ln(ci, c, h, -0.36 + 0.36 * i, -0.52, -0.36 + 0.36 * i, -0.12, ink, w * 0.55)
			_ln(ci, c, h, -0.74, 0.12, 0.74, 0.12, ink, w * 0.55)
		&"bat", &"melee":
			_poly(ci, &"bat", c, h, col)
			_dot(ci, c, h, -0.8, 0.8, 0.16, col)
		&"sniper":
			_poly(ci, &"sniper", c, h, col)
			_poly(ci, &"sniper_scope", c, h, col)
		&"grenade", &"thrown":
			_dot(ci, c, h, 0.0, 0.25, 0.62, col)
			_poly(ci, &"grenade_cap", c, h, col)
			_ln(ci, c, h, 0.2, -0.72, 0.62, -0.3, col, w)
			_arc(ci, c, h, -0.45, -0.6, 0.2, 0.0, 360.0, col, w * 0.7)
		&"police":
			_poly(ci, &"shield", c, h, col)
			_poly(ci, &"star", c + Vector2(0, -0.05) * h, h * 0.45, ink)
		&"hospital":
			_poly(ci, &"cross", c, h * 0.9, col)
		&"gun_shop":
			_poly(ci, &"handgun", c, h, col)
		&"bag":
			_poly(ci, &"bag_body", c, h, col)
			_arc(ci, c, h, 0.0, -0.3, 0.42, 180.0, 360.0, col, w)
		&"pin":
			_dot(ci, c, h, 0.0, -0.32, 0.62, col)
			_poly(ci, &"pin_tip", c + Vector2(0, 0.0) * h, h, col)
			_dot(ci, c, h, 0.0, -0.32, 0.24, ink)
		&"flag":
			_ln(ci, c, h, -0.6, -1.0, -0.6, 1.0, col, w)
			_poly(ci, &"flag_cloth", c, h, col)
		&"umbrella":
			_poly(ci, &"umbrella", c, h, col)
			_ln(ci, c, h, 0.0, -0.05, 0.0, 0.95, col, w)
		&"lighthouse":
			_poly(ci, &"tower", c, h, col)
			_poly(ci, &"tower_lamp", c, h, col)
			_ln(ci, c, h, 0.45, -0.58, 1.0, -0.85, col, w * 0.7)
			_ln(ci, c, h, 0.45, -0.52, 1.0, -0.3, col, w * 0.7)
			_ln(ci, c, h, -0.45, -0.58, -1.0, -0.85, col, w * 0.7)
			_ln(ci, c, h, -0.45, -0.52, -1.0, -0.3, col, w * 0.7)
		&"anchor":
			_arc(ci, c, h, 0.0, -0.74, 0.2, 0.0, 360.0, col, w)
			_ln(ci, c, h, 0.0, -0.52, 0.0, 0.88, col, w)
			_ln(ci, c, h, -0.45, -0.25, 0.45, -0.25, col, w)
			_arc(ci, c, h, 0.0, 0.15, 0.72, 15.0, 165.0, col, w)
		&"target":
			_arc(ci, c, h, 0.0, 0.0, 0.88, 0.0, 360.0, col, w)
			_arc(ci, c, h, 0.0, 0.0, 0.5, 0.0, 360.0, col, w)
			_dot(ci, c, h, 0.0, 0.0, 0.17, col)
		&"tram":
			_poly(ci, &"tram_body", c, h, col)
			_ln(ci, c, h, -0.4, -1.0, 0.4, -1.0, col, w * 0.8)
			_ln(ci, c, h, 0.0, -1.0, 0.0, -0.78, col, w * 0.8)
			_dot(ci, c, h, -0.35, 0.78, 0.17, col)
			_dot(ci, c, h, 0.35, 0.78, 0.17, col)
			_ln(ci, c, h, -0.42, -0.35, 0.42, -0.35, ink, w * 1.6)
		&"scissors":
			_ln(ci, c, h, -0.5, -0.92, 0.36, 0.38, col, w)
			_ln(ci, c, h, 0.5, -0.92, -0.36, 0.38, col, w)
			_arc(ci, c, h, 0.5, 0.64, 0.28, 0.0, 360.0, col, w)
			_arc(ci, c, h, -0.5, 0.64, 0.28, 0.0, 360.0, col, w)
		&"wrench":
			_ln(ci, c, h, -0.78, 0.78, 0.18, -0.18, col, w * 1.7)
			_arc(ci, c, h, 0.42, -0.42, 0.4, 5.0, 265.0, col, w * 1.5)
		&"gear":
			_arc(ci, c, h, 0.0, 0.0, 0.5, 0.0, 360.0, col, w * 1.9)
			for i in 8:
				var a := TAU * float(i) / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * h * 0.62, c + Vector2(cos(a), sin(a)) * h * 0.98, col, w * 1.7, true)
		&"car":
			_poly(ci, &"car_body", c, h, col)
			_dot(ci, c, h, -0.55, 0.42, 0.25, col)
			_dot(ci, c, h, 0.55, 0.42, 0.25, col)
		&"boat":
			_poly(ci, &"boat_hull", c, h, col)
			_poly(ci, &"boat_sail", c, h, col)
		&"heli":
			_dot(ci, c, h, -0.15, 0.15, 0.45, col)
			_ln(ci, c, h, 0.2, 0.1, 0.95, -0.05, col, w * 1.3)
			_ln(ci, c, h, 0.95, -0.3, 0.95, 0.2, col, w)
			_ln(ci, c, h, -0.95, -0.55, 0.65, -0.55, col, w)
			_ln(ci, c, h, -0.15, -0.55, -0.15, -0.25, col, w)
			_ln(ci, c, h, -0.6, 0.85, 0.35, 0.85, col, w * 0.8)
		&"person":
			_dot(ci, c, h, 0.0, -0.62, 0.3, col)
			_poly(ci, &"person_body", c, h, col)
		&"radio":
			_poly(ci, &"radio_body", c, h, col)
			_ln(ci, c, h, -0.5, -0.3, 0.55, -0.95, col, w * 0.8)
			_dot(ci, c, h, 0.38, 0.25, 0.3, ink)
			_ln(ci, c, h, -0.65, 0.05, -0.1, 0.05, ink, w * 0.8)
			_ln(ci, c, h, -0.65, 0.4, -0.1, 0.4, ink, w * 0.8)
		&"save":
			_poly(ci, &"save", c, h, col)
			ci.draw_rect(Rect2(c + Vector2(-0.45, 0.15) * h, Vector2(0.9, 0.7) * h), ink)
			ci.draw_rect(Rect2(c + Vector2(-0.4, -0.85) * h, Vector2(0.7, 0.45) * h), ink)
		&"map":
			_poly(ci, &"map", c, h, col)
			_ln(ci, c, h, -0.32, -0.85, -0.32, 0.6, ink, w * 0.6)
			_ln(ci, c, h, 0.32, -0.6, 0.32, 0.85, ink, w * 0.6)
		&"power":
			_arc(ci, c, h, 0.0, 0.05, 0.78, 305.0, 595.0, col, w * 1.2)
			_ln(ci, c, h, 0.0, -1.0, 0.0, -0.1, col, w * 1.2)
		&"stats":
			ci.draw_rect(Rect2(c + Vector2(-0.85, 0.1) * h, Vector2(0.42, 0.8) * h), col)
			ci.draw_rect(Rect2(c + Vector2(-0.21, -0.4) * h, Vector2(0.42, 1.3) * h), col)
			ci.draw_rect(Rect2(c + Vector2(0.43, -0.9) * h, Vector2(0.42, 1.8) * h), col)
		&"check":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.8, 0.05) * h, c + Vector2(-0.25, 0.6) * h, c + Vector2(0.85, -0.6) * h]), col, w * 1.5, true)
		&"close":
			_ln(ci, c, h, -0.7, -0.7, 0.7, 0.7, col, w * 1.5)
			_ln(ci, c, h, 0.7, -0.7, -0.7, 0.7, col, w * 1.5)
		&"chev_left":
			ci.draw_polyline(PackedVector2Array([c + Vector2(0.35, -0.75) * h, c + Vector2(-0.4, 0.0) * h, c + Vector2(0.35, 0.75) * h]), col, w * 1.4, true)
		&"chev_right":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.35, -0.75) * h, c + Vector2(0.4, 0.0) * h, c + Vector2(-0.35, 0.75) * h]), col, w * 1.4, true)
		&"chev_up":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.75, 0.35) * h, c + Vector2(0.0, -0.4) * h, c + Vector2(0.75, 0.35) * h]), col, w * 1.4, true)
		&"chev_down":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.75, -0.35) * h, c + Vector2(0.0, 0.4) * h, c + Vector2(0.75, -0.35) * h]), col, w * 1.4, true)
		&"lock":
			_poly(ci, &"lock_body", c, h, col)
			_arc(ci, c, h, 0.0, -0.15, 0.45, 180.0, 360.0, col, w * 1.2)
		&"info":
			_arc(ci, c, h, 0.0, 0.0, 0.85, 0.0, 360.0, col, w)
			_dot(ci, c, h, 0.0, -0.42, 0.13, col)
			_ln(ci, c, h, 0.0, -0.1, 0.0, 0.5, col, w * 1.2)
		&"warn":
			_outline(ci, &"warn", c, h, col, w)
			_ln(ci, c, h, 0.0, -0.35, 0.0, 0.25, col, w * 1.1)
			_dot(ci, c, h, 0.0, 0.52, 0.11, col)
		&"sun":
			_dot(ci, c, h, 0.0, 0.0, 0.46, col)
			for i in 8:
				var a2 := TAU * float(i) / 8.0
				ci.draw_line(c + Vector2(cos(a2), sin(a2)) * h * 0.66, c + Vector2(cos(a2), sin(a2)) * h * 0.98, col, w, true)
		&"cloud":
			_cloud(ci, c, h, col)
		&"rain":
			_cloud(ci, c + Vector2(0, -0.25) * h, h * 0.9, col)
			for i in 3:
				_ln(ci, c, h, -0.42 + 0.45 * i, 0.45, -0.6 + 0.45 * i, 0.95, col, w * 0.9)
		&"storm":
			_cloud(ci, c + Vector2(0, -0.3) * h, h * 0.9, col)
			_poly(ci, &"bolt", c + Vector2(0.0, 0.52) * h, h * 0.5, UiStyle.SUN if col.a > 0.5 else col)
		&"fog":
			for i in 4:
				var inset := 0.15 if i % 2 == 0 else 0.0
				_ln(ci, c, h, -0.9 + inset, -0.6 + 0.4 * i, 0.9 - (0.15 - inset), -0.6 + 0.4 * i, col, w * 1.1)
		&"bubbles":
			_arc(ci, c, h, -0.3, 0.38, 0.45, 0.0, 360.0, col, w)
			_arc(ci, c, h, 0.45, -0.2, 0.32, 0.0, 360.0, col, w)
			_arc(ci, c, h, -0.2, -0.65, 0.2, 0.0, 360.0, col, w)
		&"speed":
			_arc(ci, c, h, 0.0, 0.3, 0.9, 180.0, 360.0, col, w * 1.2)
			_ln(ci, c, h, 0.0, 0.3, 0.5, -0.35, col, w * 1.2)
			_dot(ci, c, h, 0.0, 0.3, 0.14, col)
		&"dollar":
			_glyph(ci, c, s * 1.15, "$", col)
		&"parking":
			ci.draw_style_box(UiStyle._fill_box(col), Rect2(c - Vector2(h, h) * 0.95, Vector2(s, s) * 0.95))
			_glyph(ci, c, s * 0.9, "P", ink)
		&"taxi":
			ci.draw_style_box(UiStyle._fill_box(col), Rect2(c - Vector2(h, h) * 0.95, Vector2(s, s) * 0.95))
			_glyph(ci, c, s * 0.9, "T", ink)
		&"helipad":
			_arc(ci, c, h, 0.0, 0.0, 0.88, 0.0, 360.0, col, w)
			_glyph(ci, c, s * 0.8, "H", col)
		&"north":
			_glyph(ci, c, s, "N", col)
		# --- wave 3: lifestyle / phone / activities -----------------------------------------------
		&"parachute":
			_poly(ci, &"canopy", c, h, col)
			for x: float in [-0.86, -0.3, 0.3, 0.86]:
				_ln(ci, c, h, x, -0.2, 0.0, 0.46, col, w * 0.55)
			_dot(ci, c, h, 0.0, 0.56, 0.17, col)
			_ln(ci, c, h, 0.0, 0.66, 0.0, 0.98, col, w * 1.1)
		&"hat":
			_poly(ci, &"hat_crown", c, h, col)
			_poly(ci, &"hat_brim", c, h, col)
			_ln(ci, c, h, -0.5, 0.04, 0.5, 0.04, ink, w * 1.1)
		&"glasses":
			_arc(ci, c, h, -0.5, 0.1, 0.36, 0.0, 360.0, col, w * 1.1)
			_arc(ci, c, h, 0.5, 0.1, 0.36, 0.0, 360.0, col, w * 1.1)
			_arc(ci, c, h, 0.0, 0.16, 0.16, 200.0, 340.0, col, w)
			_ln(ci, c, h, -0.86, 0.02, -1.0, -0.3, col, w)
			_ln(ci, c, h, 0.86, 0.02, 1.0, -0.3, col, w)
		&"shoes":
			_poly(ci, &"shoe", c, h, col)
			_ln(ci, c, h, -0.95, 0.38, 0.95, 0.38, ink, w * 0.7)
			_ln(ci, c, h, -0.25, -0.05, -0.05, 0.2, ink, w * 0.5)
			_ln(ci, c, h, -0.05, 0.02, 0.15, 0.25, ink, w * 0.5)
		&"phone":
			ci.draw_style_box(UiStyle._fill_box(col), Rect2(c + Vector2(-0.56, -0.98) * h, Vector2(1.12, 1.96) * h))
			ci.draw_rect(Rect2(c + Vector2(-0.42, -0.72) * h, Vector2(0.84, 1.3) * h), ink)
			_dot(ci, c, h, 0.0, 0.79, 0.09, ink)
		&"call":
			# telephone handset (earpiece top-left, mouthpiece bottom-right) + two sound waves
			_poly(ci, &"handset", c + Vector2(-0.06, 0.06) * h, h * 0.92, col)
			_arc(ci, c, h, -0.1, 0.1, 0.62, 285.0, 345.0, col, w * 0.75)
			_arc(ci, c, h, -0.1, 0.1, 0.92, 285.0, 345.0, col, w * 0.75)
		&"camera":
			_poly(ci, &"camera_body", c, h, col)
			_dot(ci, c, h, 0.0, 0.18, 0.42, ink)
			_dot(ci, c, h, 0.0, 0.18, 0.25, col)
			_dot(ci, c, h, 0.66, -0.22, 0.09, ink)
		&"flame", &"fire":
			_poly(ci, &"flame", c, h, col)
			_dot(ci, c, h, 0.0, 0.48, 0.3, ink)
		&"medal":
			_poly(ci, &"medal_ribbon_l", c, h, col)
			_poly(ci, &"medal_ribbon_r", c, h, col)
			_dot(ci, c, h, 0.0, 0.32, 0.6, col)
			_arc(ci, c, h, 0.0, 0.32, 0.42, 0.0, 360.0, ink, w * 0.7)
		&"trophy":
			_poly(ci, &"trophy_cup", c, h, col)
			_poly(ci, &"trophy_base", c, h, col)
			_arc(ci, c, h, -0.68, -0.48, 0.3, 90.0, 270.0, col, w)
			_arc(ci, c, h, 0.68, -0.48, 0.3, -90.0, 90.0, col, w)
		&"timer", &"stopwatch":
			_arc(ci, c, h, 0.0, 0.12, 0.78, 0.0, 360.0, col, w * 1.2)
			ci.draw_rect(Rect2(c + Vector2(-0.18, -1.0) * h, Vector2(0.36, 0.18) * h), col)
			_ln(ci, c, h, 0.0, -0.82, 0.0, -0.66, col, w)
			_ln(ci, c, h, 0.0, 0.12, 0.0, -0.36, col, w * 1.1)
			_ln(ci, c, h, 0.0, 0.12, 0.32, 0.3, col, w * 1.1)
			_ln(ci, c, h, 0.62, -0.62, 0.78, -0.78, col, w)
		&"note", &"music":
			_poly(ci, &"note_flag", c, h, col)
			_ln(ci, c, h, 0.0, -0.95, 0.0, 0.55, col, w * 1.1)
			_dot(ci, c, h, -0.26, 0.62, 0.3, col)
		&"eye":
			_poly(ci, &"eye", c, h, col)
			_dot(ci, c, h, 0.0, 0.0, 0.42, ink)
			_dot(ci, c, h, 0.0, 0.0, 0.2, col)
		&"eye_off":
			_outline(ci, &"eye", c, h, col, w)
			_dot(ci, c, h, 0.0, 0.0, 0.26, col)
			_ln(ci, c, h, -0.85, 0.8, 0.85, -0.8, col, w * 1.1)
		&"filter":
			_arc(ci, c, h, -0.3, -0.22, 0.48, 0.0, 360.0, col, w)
			_arc(ci, c, h, 0.3, -0.22, 0.48, 0.0, 360.0, col, w)
			_arc(ci, c, h, 0.0, 0.3, 0.48, 0.0, 360.0, col, w)
		&"signal":
			for i in 4:
				var bh := 0.35 + 0.42 * float(i)
				ci.draw_rect(Rect2(c + Vector2(-0.9 + 0.48 * float(i), 0.9 - bh) * h, Vector2(0.3, bh) * h), col)
		&"battery":
			ci.draw_rect(Rect2(c + Vector2(-0.95, -0.45) * h, Vector2(1.7, 0.9) * h), col, false, w)
			ci.draw_rect(Rect2(c + Vector2(0.78, -0.2) * h, Vector2(0.17, 0.4) * h), col)
			ci.draw_rect(Rect2(c + Vector2(-0.78, -0.28) * h, Vector2(1.1, 0.56) * h), col)
		&"ambulance":
			_poly(ci, &"car_body", c + Vector2(0, -0.05) * h, h, col)
			_dot(ci, c, h, -0.55, 0.38, 0.22, col)
			_dot(ci, c, h, 0.55, 0.38, 0.22, col)
			_poly(ci, &"cross", c + Vector2(-0.12, -0.12) * h, h * 0.24, ink)
		&"altimeter":
			_arc(ci, c, h, 0.0, 0.0, 0.86, 0.0, 360.0, col, w)
			for i in 8:
				var a3 := TAU * float(i) / 8.0
				ci.draw_line(c + Vector2(cos(a3), sin(a3)) * h * 0.6, c + Vector2(cos(a3), sin(a3)) * h * 0.78, col, w * 0.7, true)
			_ln(ci, c, h, 0.0, 0.0, 0.3, -0.5, col, w * 1.2)
			_dot(ci, c, h, 0.0, 0.0, 0.12, col)
		&"circle":
			_dot(ci, c, h, 0.0, 0.0, 0.8, col)
		&"ring":
			_arc(ci, c, h, 0.0, 0.0, 0.8, 0.0, 360.0, col, w)
		_:
			_dot(ci, c, h, 0.0, 0.0, 0.4, col)


static func _cloud(ci: CanvasItem, c: Vector2, h: float, col: Color) -> void:
	_dot(ci, c, h, -0.42, 0.12, 0.4, col)
	_dot(ci, c, h, 0.05, -0.2, 0.52, col)
	_dot(ci, c, h, 0.5, 0.15, 0.36, col)
	_poly(ci, &"cloud_base", c, h, col)
