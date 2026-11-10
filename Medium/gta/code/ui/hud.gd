extends CanvasLayer
## Original HUD: vitals, money, weapon/ammo, wanted stars, minimap, speedometer, prompts, weapon wheel, scope, messages.

const Defs := preload("res://gta/code/core/defs.gd")
const Minimap := preload("res://gta/code/ui/minimap.gd")

var root: Control
var minimap: Control
var notes: Array = []
var _hint := ""
var _hint_t := 0.0
var _big := ""
var _big_col := Color.WHITE
var _big_t := 0.0
var _fade := 0.0
var _hurt := 0.0
var _money_d := 0
var _money_t := 0.0
var wheel_sel := -1
var _wheel_vec := Vector2.ZERO
var _wheel_items := {}
var _fps_t := 0.0
var _fps := 0.0
var show_hud := true
var activity_text := ""


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.draw.connect(_draw_hud)
	minimap = Control.new()
	minimap.set_script(Minimap)
	root.add_child(minimap)


func notify(t: String, dur := 3.0) -> void:
	for n in notes:
		if n.t == t:
			n.d = dur
			return
	notes.append({"t": t, "d": dur})
	if notes.size() > 5:
		notes.pop_front()


func hint(t: String) -> void:
	_hint = t
	_hint_t = 0.25


func big_message(t: String, c: Color) -> void:
	_big = t
	_big_col = c
	_big_t = 4.2


func fade_in() -> void:
	_fade = 1.0


func hurt(a: float, _pos: Vector3) -> void:
	_hurt = clamp(_hurt + a / 40.0, 0.0, 1.0)


func money_flash(n: int) -> void:
	_money_d = n
	_money_t = 2.0
	if n > 0 and G.audio:
		G.audio.play("cash", -10.0)


func _input(ev: InputEvent) -> void:
	if G.player and G.player.wheel_open and ev is InputEventMouseMotion:
		_wheel_vec = (_wheel_vec + ev.relative * 0.02).limit_length(1.0)


func _process(dt: float) -> void:
	var p = G.player
	if p == null:
		return
	for n in notes.duplicate():
		n.d -= dt / max(Engine.time_scale, 0.05)
		if n.d <= 0.0:
			notes.erase(n)
	_hint_t -= dt
	_big_t -= dt
	if p.state in ["dead", "busted"]:
		_fade = clamp(p._state_t - 3.2, 0.0, 1.0)
	else:
		_fade = max(0.0, _fade - dt * 0.8)
	_hurt = max(0.0, _hurt - dt * 1.2)
	_money_t -= dt
	_fps_t += dt
	if _fps_t > 0.5:
		_fps_t = 0.0
		_fps = Engine.get_frames_per_second()
	# weapon wheel
	var can_wheel: bool = not (G.menus and G.menus.is_open()) and p.state not in ["dead", "busted"]
	if Input.is_action_pressed("wheel") and can_wheel:
		if not p.wheel_open:
			p.wheel_open = true
			_wheel_vec = Vector2.ZERO
			wheel_sel = -1
			Engine.time_scale = 0.2
			_wheel_items = {}
			for id in p.weapons.owned():
				var cls: String = Defs.WEAPONS[id].cls
				if not _wheel_items.has(cls) or id == p.weapons.cur:
					_wheel_items[cls] = id
		if _wheel_vec.length() > 0.45:
			var a = fposmod(atan2(_wheel_vec.y, _wheel_vec.x) + PI / 2 + PI / 8, TAU)
			wheel_sel = int(a / (TAU / 8.0)) % 8
	elif p.wheel_open:
		p.wheel_open = false
		Engine.time_scale = G.time_scale
		if wheel_sel >= 0:
			var cls2: String = Defs.WHEEL_CLASSES[wheel_sel]
			if _wheel_items.has(cls2):
				p.select_weapon(_wheel_items[cls2])
	var vs: Vector2 = root.size
	var ms: float = clamp(vs.y * 0.24, 150.0, 260.0)
	minimap.size = Vector2(ms, ms)
	minimap.position = Vector2(22, vs.y - ms - 22)
	minimap.visible = show_hud and not (G.menus and G.menus.map_open)
	root.queue_redraw()


func _bar(pos: Vector2, sz: Vector2, frac: float, col: Color) -> void:
	root.draw_rect(Rect2(pos, sz), Color(0, 0, 0, 0.55))
	root.draw_rect(Rect2(pos + Vector2(2, 2), Vector2((sz.x - 4) * clamp(frac, 0.0, 1.0), sz.y - 4)), col)


func _txt(pos: Vector2, s: String, size := 18, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f = root.get_theme_default_font()
	root.draw_string_outline(f, pos, s, align, width, size, 4, Color(0, 0, 0, 0.8))
	root.draw_string(f, pos, s, align, width, size, col)


func _draw_hud() -> void:
	var p = G.player
	if p == null:
		return
	var vs: Vector2 = root.size
	var f = root.get_theme_default_font()
	# full-screen feedback
	if _hurt > 0.01 or p.health < 30.0:
		var a: float = max(_hurt * 0.5, (0.25 + 0.1 * sin(Time.get_ticks_msec() * 0.008)) if p.health < 30.0 and p.health > 0.0 else 0.0)
		var w = vs.x * 0.14
		root.draw_rect(Rect2(0, 0, w, vs.y), Color(0.7, 0, 0, a * 0.6))
		root.draw_rect(Rect2(vs.x - w, 0, w, vs.y), Color(0.7, 0, 0, a * 0.6))
		root.draw_rect(Rect2(0, 0, vs.x, w * 0.6), Color(0.7, 0, 0, a * 0.5))
		root.draw_rect(Rect2(0, vs.y - w * 0.6, vs.x, w * 0.6), Color(0.7, 0, 0, a * 0.5))
	if G.env and G.env.underwater:
		root.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.25, 0.4, 0.28))
	if G.cam and G.cam.scoped:
		var r = vs.y * 0.46
		var c = vs * 0.5
		root.draw_rect(Rect2(0, 0, c.x - r, vs.y), Color.BLACK)
		root.draw_rect(Rect2(c.x + r, 0, c.x - r, vs.y), Color.BLACK)
		root.draw_rect(Rect2(0, 0, vs.x, c.y - r), Color.BLACK)
		root.draw_rect(Rect2(0, c.y + r, vs.x, c.y - r), Color.BLACK)
		for i in 48:
			var a0 = i * TAU / 48
			var a1 = (i + 1) * TAU / 48
			root.draw_colored_polygon(PackedVector2Array([c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r,
				c + Vector2(cos(a1), sin(a1)) * r * 1.5, c + Vector2(cos(a0), sin(a0)) * r * 1.5]), Color.BLACK)
		root.draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0, 0, 0, 0.9), 1.5)
		root.draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0, 0, 0, 0.9), 1.5)
		root.draw_arc(c, r, 0, TAU, 64, Color.BLACK, 4.0)
	if not show_hud:
		_draw_fade(vs)
		return
	# ---- top-right cluster: wanted, money, weapon
	var x = vs.x - 26.0
	var y = 44.0
	var stars: int = G.wanted.stars if G.wanted else 0
	var searching: bool = G.wanted != null and G.wanted.state == "search"
	var blink = sin(Time.get_ticks_msec() * 0.012) > 0.0
	for i in 5:
		var on = i < stars
		var c = Color(1.0, 0.85, 0.2) if on else Color(0, 0, 0, 0.45)
		if on and searching and not blink:
			c = Color(1.0, 0.85, 0.2, 0.3)
		_star(Vector2(x - 150 + i * 34 + 14, y - 8), 14.0, c)
	y += 34
	_txt(Vector2(x - 260, y), "$%s" % _commas(G.money), 26, Color(0.55, 0.95, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, 260)
	if _money_t > 0.0:
		_txt(Vector2(x - 260, y + 24), ("+$%d" if _money_d > 0 else "-$%d") % abs(_money_d), 18, Color(0.6, 1.0, 0.6) if _money_d > 0 else Color(1.0, 0.5, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, 260)
	y += 34
	var w: Dictionary = p.weapons.d()
	_txt(Vector2(x - 300, y + 20), w.name, 18, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 300)
	var at: String = p.weapons.ammo_text()
	if at != "":
		_txt(Vector2(x - 300, y + 44), at + ("  (reloading)" if p.weapons.reload_t > 0.0 else ""), 20, Color(1.0, 0.9, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 300)
	# clock / district
	if G.env:
		_txt(Vector2(x - 300, vs.y - 24), "%s  ·  %s  ·  %s" % [G.world.district(G.player_pos()), G.env.time_string(), G.env.weather.capitalize()], 15, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, 300)
	# ---- vitals above minimap
	var mp: Vector2 = minimap.position
	var mw: float = minimap.size.x
	_bar(mp + Vector2(0, -18), Vector2(mw * 0.5 - 2, 12), p.health / p.max_health, Color(0.35, 0.8, 0.35) if p.health > 30.0 else Color(0.9, 0.2, 0.15))
	_bar(mp + Vector2(mw * 0.5 + 2, -18), Vector2(mw * 0.5 - 2, 12), p.armor / 100.0, Color(0.35, 0.6, 0.95))
	if p.stamina < 0.99:
		_bar(mp + Vector2(0, -30), Vector2(mw, 8), p.stamina, Color(0.95, 0.8, 0.25))
	if p.state == "swim" and (p.breath < 0.99 or p.head_underwater()):
		_bar(mp + Vector2(0, -42), Vector2(mw, 8), p.breath, Color(0.4, 0.85, 0.95))
		_txt(mp + Vector2(mw + 8, -34), "AIR" + ("  (scuba)" if p.scuba else ""), 13)
	if p.stealth:
		_txt(mp + Vector2(mw + 10, -8), "STEALTH", 14, Color(0.6, 0.8, 1.0))
	# ---- vehicle cluster
	if p.state == "vehicle" and p.vehicle and is_instance_valid(p.vehicle):
		var v = p.vehicle
		var bx = vs.x * 0.5
		var by = vs.y - 60.0
		_txt(Vector2(bx - 100, by), "%d km/h" % int(abs(v.linear_velocity.length()) * 3.6), 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 200)
		_bar(Vector2(bx - 90, by + 10), Vector2(180, 10), v.health / v.max_health, Color(0.9, 0.6, 0.2))
		_txt(Vector2(bx - 150, by + 38), v.def.name, 14, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 300)
		if v.kind in ["heli", "plane"]:
			_txt(Vector2(bx + 110, by), "ALT %d m" % int(v.global_position.y), 18)
			if v.kind == "plane":
				_bar(Vector2(bx - 90, by + 24), Vector2(180, 8), v.throttle_state, Color(0.4, 0.8, 1.0))
				if v.grounded == 0 and v.speed < v.def.get("stall", 24.0) * 0.9:
					_txt(Vector2(bx - 100, by - 34), "STALL", 22, Color(1, 0.3, 0.2), HORIZONTAL_ALIGNMENT_CENTER, 200)
		if G.audio and G.audio.radio_on and G.audio.station > 0:
			_txt(Vector2(bx - 150, 30), "♪ " + G.audio.STATIONS[G.audio.station], 14, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 300)
	if p.state == "chute":
		_txt(Vector2(vs.x * 0.5 - 100, vs.y - 60), "ALT %d m" % int(p.global_position.y - G.ground_y(p.global_position.x, p.global_position.z, p.global_position.y)), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 200)
	# ---- crosshair
	if p.state in ["ground", "cover", "vehicle"] and not (G.cam and G.cam.scoped) and (p.aiming or p.weapons.is_gun()) and not p.wheel_open:
		var c2 = vs * 0.5
		var gap: float = 5.0 + p.weapons.bloom * 6.0 + (0.0 if p.aiming else 5.0)
		var cc = Color(1, 1, 1, 0.9 if p.aiming else 0.45)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			root.draw_line(c2 + d * gap, c2 + d * (gap + 7.0), Color(0, 0, 0, cc.a), 3.5)
			root.draw_line(c2 + d * gap, c2 + d * (gap + 7.0), cc, 1.6)
		root.draw_circle(c2, 1.5, cc)
	# ---- prompts
	var py = vs.y * 0.72
	if p.interact_cur != null:
		_txt(Vector2(0, py), "[E]  " + p.interact_cur.text, 19, Color(1.0, 0.92, 0.6), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		py += 26
	if p.near_vehicle != null and p.state in ["ground", "cover"] and is_instance_valid(p.near_vehicle):
		var nv = p.near_vehicle
		var verb = "Enter"
		if nv.has_ai_driver():
			verb = "Hijack"
		elif nv.kind == "bike":
			verb = "Ride"
		_txt(Vector2(0, py), "[F]  %s %s" % [verb, nv.def.name], 17, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		py += 24
	if _hint_t > 0.0:
		_txt(Vector2(0, py), _hint, 17, Color(0.8, 0.95, 1.0), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if activity_text != "":
		_txt(Vector2(0, 70), activity_text, 22, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	# ---- notifications (top-left)
	var ny = 40.0
	for n in notes:
		var tw: float = f.get_string_size(n.t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		root.draw_rect(Rect2(18, ny - 18, tw + 20, 26), Color(0, 0, 0, 0.5 * clamp(n.d, 0.0, 1.0)))
		root.draw_string(f, Vector2(28, ny), n.t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, clamp(n.d, 0.0, 1.0)))
		ny += 30
	# ---- debug readouts
	if G.cheats.fps:
		_txt(Vector2(vs.x * 0.5 - 60, 22), "%d FPS" % int(_fps), 16, Color(0.6, 1.0, 0.6))
	if G.cheats.coords:
		var pp = G.player_pos()
		_txt(Vector2(vs.x * 0.5 + 40, 22), "X %.0f  Y %.1f  Z %.0f   %s" % [pp.x, pp.y, pp.z, G.world.district(pp)], 15)
	if G.cheats.god:
		_txt(Vector2(22, vs.y - 6), "INVULNERABLE", 12, Color(1, 0.8, 0.3))
	# ---- weapon wheel
	if p.wheel_open:
		_draw_wheel(vs)
	if _big_t > 0.0:
		var a2: float = clamp(_big_t, 0.0, 1.0)
		_txt(Vector2(0, vs.y * 0.42), _big, 84, Color(_big_col.r, _big_col.g, _big_col.b, a2), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	_draw_fade(vs)


func _draw_fade(vs: Vector2) -> void:
	if _fade > 0.01:
		root.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, _fade))


func _draw_wheel(vs: Vector2) -> void:
	var p = G.player
	var c = vs * 0.5
	var r0 = vs.y * 0.14
	var r1 = vs.y * 0.33
	root.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.35))
	for i in 8:
		var a0 = i * TAU / 8 - PI / 2 - PI / 8
		var pts = PackedVector2Array()
		for k in 9:
			var a = a0 + (TAU / 8 - 0.04) * k / 8.0 + 0.02
			pts.append(c + Vector2(cos(a), sin(a)) * r1)
		for k in 9:
			var a = a0 + (TAU / 8 - 0.04) * (8 - k) / 8.0 + 0.02
			pts.append(c + Vector2(cos(a), sin(a)) * r0)
		var cls: String = Defs.WHEEL_CLASSES[i]
		var has: bool = _wheel_items.has(cls)
		var col = Color(0.1, 0.12, 0.15, 0.82)
		if i == wheel_sel:
			col = Color(0.95, 0.75, 0.25, 0.9) if has else Color(0.4, 0.3, 0.3, 0.8)
		root.draw_colored_polygon(pts, col)
		var am = a0 + TAU / 16
		var tp = c + Vector2(cos(am), sin(am)) * (r0 + r1) * 0.5
		var tc = Color.WHITE if has else Color(1, 1, 1, 0.3)
		if i == wheel_sel and has:
			tc = Color(0.05, 0.05, 0.05)
		var f = root.get_theme_default_font()
		root.draw_string(f, tp + Vector2(-80, -6), cls.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 160, 13, tc)
		if has:
			var id: String = _wheel_items[cls]
			root.draw_string(f, tp + Vector2(-80, 12), Defs.WEAPONS[id].name, HORIZONTAL_ALIGNMENT_CENTER, 160, 14, tc)
			var e: Dictionary = p.weapons.inv[id]
			if Defs.WEAPONS[id].has("clip"):
				root.draw_string(f, tp + Vector2(-80, 30), "%d / %d" % [e.clip, e.res], HORIZONTAL_ALIGNMENT_CENTER, 160, 13, tc)
	_txt(Vector2(c.x - 150, c.y + 4), "WEAPONS", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 300)
	_txt(Vector2(c.x - 150, c.y + 24), "move mouse · release TAB", 12, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 300)


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts = PackedVector2Array()
	for i in 10:
		var a = -PI / 2 + i * TAU / 10
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	root.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	root.draw_polyline(pts, Color(0, 0, 0, 0.8), 1.5)


func _commas(n: int) -> String:
	var s = str(n)
	var out = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
