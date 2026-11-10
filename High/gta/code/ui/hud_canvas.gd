class_name HudCanvas
extends Control
## Immediate-mode HUD drawing: vitals, wanted stars, money, weapon, speedo, prompts, toasts, banner, overlays.

var toasts: Array = []       # {text, color, t}
var banner := {"title": "", "sub": "", "color": Color.WHITE, "t": 0.0}
var prompt := ""
var hint := ""
var hint_t := 0.0
var dmg_flash := 0.0
var dmg_dir := Vector3.ZERO
var hit_t := 0.0
var hit_kill := false
var underwater := false
var district := ""
var district_t := 0.0
var _font: Font
var _money_shown := 0.0
var _fps_t := 0.0
var _fps := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_money_shown = Game.money


func _process(delta: float) -> void:
	var i := 0
	while i < toasts.size():
		toasts[i].t -= delta
		if toasts[i].t <= 0.0:
			toasts.remove_at(i)
		else:
			i += 1
	banner.t = maxf(0.0, banner.t - delta)
	hint_t = maxf(0.0, hint_t - delta)
	dmg_flash = maxf(0.0, dmg_flash - delta * 1.6)
	hit_t = maxf(0.0, hit_t - delta * 4.0)
	district_t = maxf(0.0, district_t - delta)
	_money_shown = lerpf(_money_shown, float(Game.money), clampf(delta * 8.0, 0.0, 1.0))
	_fps_t -= delta
	if _fps_t <= 0.0:
		_fps_t = 0.25
		_fps = int(Engine.get_frames_per_second())
		if Game.player:
			var d := City.district_name(Game.player.global_position)
			if d != district:
				district = d
				district_t = 4.0
	queue_redraw()


func _text(pos: Vector2, s: String, size_px: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, shadow: bool = true) -> void:
	if shadow:
		draw_string(_font, pos + Vector2(1.5, 1.5), s, align, width, size_px, Color(0, 0, 0, 0.75 * col.a))
	draw_string(_font, pos, s, align, width, size_px, col)


func _bar(r: Rect2, v: float, col: Color, back: Color = Color(0.05, 0.06, 0.08, 0.75)) -> void:
	draw_rect(r, back)
	draw_rect(Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * clampf(v, 0.0, 1.0), r.size.y - 4)), col)


func _star(c: Vector2, r: float, col: Color, filled: bool) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var a := -PI * 0.5 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	if filled:
		draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, Color(0.05, 0.06, 0.08, 0.9) if filled else col, 1.5)


func _draw() -> void:
	var p = Game.player
	if p == null:
		return
	var W := size.x
	var H := size.y
	var t := Time.get_ticks_msec() * 0.001
	# ---- overlays first
	if underwater:
		draw_rect(Rect2(0, 0, W, H), Color(0.05, 0.35, 0.45, 0.28))
	var low := 1.0 - clampf(p.health / (p.max_health * 0.35), 0.0, 1.0)
	if low > 0.0 and p.alive():
		var pulse := 0.5 + 0.5 * sin(t * 6.0)
		_vignette(Color(0.7, 0.0, 0.0, 0.32 * low * (0.6 + 0.4 * pulse)))
	if dmg_flash > 0.0:
		_vignette(Color(0.85, 0.05, 0.05, 0.4 * dmg_flash))
	if Game.cam and Game.cam.scoped:
		_scope()
	# ---- vitals under the minimap (bottom-left)
	var mx := 28.0
	var my := H - 250.0
	var mw := 210.0
	_bar(Rect2(mx, my + 214, mw * 0.56, 14), p.health / p.max_health, Color(0.36, 0.83, 0.42) if low < 0.5 else Color(0.9, 0.3, 0.25))
	_bar(Rect2(mx + mw * 0.58, my + 214, mw * 0.42, 14), p.armor / 100.0, Color(0.35, 0.62, 1.0))
	if p.stamina < 0.98:
		_bar(Rect2(mx, my + 231, mw, 7), p.stamina, Color(1.0, 0.85, 0.35))
	if p.underwater or p.breath < 0.99:
		_bar(Rect2(mx, my + 241, mw, 7), p.breath, Color(0.45, 0.9, 1.0))
		_text(Vector2(mx + mw + 8, my + 249), "O2", 13, Color(0.45, 0.9, 1.0))
	_text(Vector2(mx + mw + 10, my + 16), Game.daynight.clock_text() if Game.daynight else "", 18, Color(0.95, 0.95, 0.9))
	if district_t > 0.0:
		_text(Vector2(mx + mw + 10, my + 204), district, 22, Color(1, 1, 1, clampf(district_t, 0.0, 1.0)))
	# ---- top-right: wanted, money, weapon
	var rx := W - 30.0
	var search := Wanted.state == "search"
	for i in range(5):
		var on := i < Wanted.level
		var col := Color(1.0, 0.85, 0.3)
		if on and search and fmod(t * 2.5, 1.0) < 0.45:
			col = Color(1.0, 0.85, 0.3, 0.25)
		elif on and Wanted.state == "pursuit" and fmod(t * 4.0, 1.0) < 0.5:
			col = Color(1.0, 0.45, 0.3) if i % 2 == 0 else Color(0.4, 0.6, 1.0)
		if Wanted.level > 0 or on:
			_star(Vector2(rx - 18.0 - (4 - i) * 36.0, 44.0), 15.0, col if on else Color(1, 1, 1, 0.25), on)
	if search and Wanted.level > 0:
		_bar(Rect2(rx - 180.0, 64.0, 180.0, 6.0), 1.0 - Wanted.escape_progress(), Color(1.0, 0.85, 0.3, 0.8))
	_text(Vector2(rx - 300.0, 100.0), "$%s" % _commas(int(round(_money_shown))), 30, Color(0.55, 0.95, 0.55), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	var d: WeaponDef = p.inv.def()
	_text(Vector2(rx - 300.0, 134.0), d.name, 20, Color(0.95, 0.95, 0.95), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	if d.kind != "melee":
		var e: Dictionary = p.inv.entry()
		var ammo := "%d / %d" % [e.mag, e.reserve]
		if p._reload_t > 0.0:
			ammo = "RELOADING"
		_text(Vector2(rx - 300.0, 160.0), ammo, 22, Color(1.0, 0.9, 0.55) if e.mag > 0 else Color(1.0, 0.4, 0.35), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
		var mods: Array = e.mods
		if not mods.is_empty():
			_text(Vector2(rx - 300.0, 180.0), " + ".join(PackedStringArray(mods)), 13, Color(0.7, 0.8, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	if p.has_parachute:
		_text(Vector2(rx - 300.0, 200.0), "PARACHUTE", 13, Color(1.0, 0.7, 0.45), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	if p.scuba or Game.flags.scuba:
		_text(Vector2(rx - 300.0, 216.0), "SCUBA", 13, Color(0.45, 0.9, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	# ---- vehicle cluster (bottom-right)
	if p.in_vehicle():
		var v: Vehicle = p.vehicle
		var kmh := absf(v.linear_velocity.length()) * 3.6
		_text(Vector2(rx - 260.0, H - 86.0), "%d" % int(kmh), 54, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT, 200.0)
		_text(Vector2(rx - 54.0, H - 86.0), "km/h", 16, Color(0.8, 0.85, 0.9))
		_text(Vector2(rx - 300.0, H - 60.0), v.def.name, 18, Color(1.0, 0.75, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
		var hp := v.health / v.max_health
		_bar(Rect2(rx - 220.0, H - 50.0, 220.0, 12.0), hp, Color(0.36, 0.83, 0.42).lerp(Color(0.9, 0.3, 0.25), 1.0 - hp))
		if v.is_air() or v.global_position.y > 30.0:
			var alt := v.global_position.y - maxf(City.terrain_height(v.global_position.x, v.global_position.z), Game.WATER_Y)
			_text(Vector2(rx - 300.0, H - 150.0), "ALT %d m" % int(alt), 20, Color(0.6, 0.9, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
			if v.def.kind == "plane":
				_text(Vector2(rx - 300.0, H - 126.0), "THR %d%%" % int(v.plane_throttle * 100.0), 18, Color(0.6, 0.9, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
				if v.grounded_wheels == 0 and v.linear_velocity.dot(-v.global_basis.z) < v.def.takeoff_speed * 0.8:
					_text(Vector2(W * 0.5 - 200.0, H * 0.3), "STALL", 34, Color(1.0, 0.35, 0.3), HORIZONTAL_ALIGNMENT_CENTER, 400.0)
	elif p.state == Player.St.CHUTE or (p.state == Player.St.FOOT and p._air_time > 0.8):
		var alt2: float = p._height_above_ground() if p.state == Player.St.CHUTE else 0.0
		if p.state == Player.St.CHUTE:
			_text(Vector2(rx - 300.0, H - 100.0), "ALT %d m   SINK %.1f m/s" % [int(alt2), -p.velocity.y], 20, Color(0.6, 0.9, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	# ---- crosshair / hit marker
	var c := Vector2(W, H) * 0.5
	var show_cross: bool = (p.aiming or (p.state == Player.St.COVER and d.kind == "hitscan") or (p.in_vehicle() and d.driveby and p.aiming)) and not (Game.cam and Game.cam.scoped)
	if show_cross and d.kind != "melee":
		var gap: float = 6.0 + p._bloom * 6.0 + (4.0 if p.move_speed > 1.0 else 0.0)
		for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + dir * gap, c + dir * (gap + 7.0), Color(0, 0, 0, 0.6), 3.5)
			draw_line(c + dir * gap, c + dir * (gap + 7.0), Color(1, 1, 1, 0.95), 1.6)
		draw_circle(c, 1.4, Color(1, 1, 1, 0.9))
	elif not p.in_vehicle() and p.alive():
		draw_circle(c, 1.6, Color(1, 1, 1, 0.35))
	if hit_t > 0.0:
		var hc := Color(1.0, 0.3, 0.25, hit_t) if hit_kill else Color(1, 1, 1, hit_t)
		for dir2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + dir2 * 7.0, c + dir2 * 14.0, hc, 2.4)
	# ---- prompt / hint
	if prompt != "":
		var tw := _font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_rect(Rect2(W * 0.5 - tw * 0.5 - 14.0, H - 142.0, tw + 28.0, 34.0), Color(0.05, 0.06, 0.08, 0.72))
		_text(Vector2(W * 0.5 - tw * 0.5, H - 118.0), prompt, 20, Color(1.0, 0.92, 0.75))
	if hint_t > 0.0 and hint != "":
		var a := clampf(hint_t, 0.0, 1.0)
		_text(Vector2(W * 0.5 - 500.0, H - 70.0), hint, 16, Color(0.85, 0.9, 0.95, a), HORIZONTAL_ALIGNMENT_CENTER, 1000.0)
	# ---- toasts
	var ty := H * 0.34
	for i in range(mini(toasts.size(), 7)):
		var to: Dictionary = toasts[toasts.size() - 1 - i]
		var al := clampf(to.t, 0.0, 1.0)
		var col2: Color = to.color
		_text(Vector2(34.0, ty + i * 26.0), to.text, 18, Color(col2.r, col2.g, col2.b, al))
	# ---- banner
	if banner.t > 0.0:
		var ba := clampf(banner.t, 0.0, 1.0)
		var bc: Color = banner.color
		draw_rect(Rect2(0, H * 0.2 - 54.0, W, 104.0), Color(0.03, 0.04, 0.06, 0.55 * ba))
		_text(Vector2(0, H * 0.2), banner.title, 56, Color(bc.r, bc.g, bc.b, ba), HORIZONTAL_ALIGNMENT_CENTER, W)
		_text(Vector2(0, H * 0.2 + 34.0), banner.sub, 20, Color(0.92, 0.93, 0.95, ba), HORIZONTAL_ALIGNMENT_CENTER, W)
	# ---- debug
	var dy := 24.0
	if Game.flags.show_fps:
		_text(Vector2(W * 0.5 - 60.0, dy), "%d FPS" % _fps, 18, Color(0.6, 1.0, 0.6))
		dy += 22.0
	if Game.flags.show_coords:
		_text(Vector2(W * 0.5 - 220.0, dy), "X %.1f  Y %.1f  Z %.1f   %s   veh %d  npc %d" % [p.global_position.x, p.global_position.y, p.global_position.z,
			City.district_name(p.global_position), Game.vehicles.size(), Game.npcs.size()], 16, Color(0.9, 0.95, 1.0))
	if Game.flags.invuln:
		_text(Vector2(mx, my - 12.0), "INVULNERABLE", 13, Color(1.0, 0.8, 0.4))


func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _vignette(col: Color) -> void:
	var W := size.x
	var H := size.y
	var b := 90.0
	var clear := Color(col.r, col.g, col.b, 0.0)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, b), Vector2(0, b)]), PackedColorArray([col, col, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(0, H - b), Vector2(W, H - b), Vector2(W, H), Vector2(0, H)]), PackedColorArray([clear, clear, col, col]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(b, 0), Vector2(b, H), Vector2(0, H)]), PackedColorArray([col, clear, clear, col]))
	draw_polygon(PackedVector2Array([Vector2(W - b, 0), Vector2(W, 0), Vector2(W, H), Vector2(W - b, H)]), PackedColorArray([clear, col, col, clear]))


func _scope() -> void:
	var W := size.x
	var H := size.y
	var c := Vector2(W, H) * 0.5
	var r := H * 0.44
	var black := Color(0, 0, 0, 1)
	draw_rect(Rect2(0, 0, c.x - r, H), black)
	draw_rect(Rect2(c.x + r, 0, W - c.x - r, H), black)
	var seg := 48
	for q in range(seg):
		var a0 := q * TAU / seg
		var a1 := (q + 1) * TAU / seg
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		var e0 := c + Vector2(cos(a0), sin(a0)) * r * 2.2
		var e1 := c + Vector2(cos(a1), sin(a1)) * r * 2.2
		draw_colored_polygon(PackedVector2Array([p0, p1, e1, e0]), black)
	draw_arc(c, r, 0, TAU, 64, Color(0.1, 0.1, 0.1), 4.0)
	draw_line(c - Vector2(r, 0), c - Vector2(14, 0), Color(0, 0, 0, 0.9), 2.0)
	draw_line(c + Vector2(14, 0), c + Vector2(r, 0), Color(0, 0, 0, 0.9), 2.0)
	draw_line(c - Vector2(0, r), c - Vector2(0, 14), Color(0, 0, 0, 0.9), 2.0)
	draw_line(c + Vector2(0, 14), c + Vector2(0, r), Color(0, 0, 0, 0.9), 2.0)
	draw_circle(c, 1.5, Color(1.0, 0.2, 0.2))
