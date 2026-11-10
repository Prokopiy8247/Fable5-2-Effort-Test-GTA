class_name HUD
extends Control
## Original in-game HUD: rotating minimap with blips and GPS route, health / armour /
## stamina / breath, cash, wanted stars, weapon + ammo, clock + district, vehicle speed,
## crosshair + sniper scope, prompts, toasts, banners, damage vignette, fade, altimeter.

const ACCENT := Color(0.18, 0.9, 1.0)
const PINK := Color(1.0, 0.25, 0.63)
const PANEL := Color(0.04, 0.05, 0.07, 0.72)
const MAP_SIZE := 210.0

var font: Font
var prompt_text := ""
var toasts: Array = []             # [text, kind, time left]
var banner_title := ""
var banner_sub := ""
var banner_color := Color.WHITE
var banner_time := 0.0
var banner_total := 1.0
var flash := 0.0
var fade := 0.0
var fade_target := 0.0
var radio_text := ""
var radio_time := 0.0
var district := ""
var district_time := 0.0
var cash_delta := 0
var cash_delta_time := 0.0
var show_hud := true
var info_text := ""                # persistent status line (taxi fare, range score, stunt info)
var waypoint: Variant = null       # Vector3 or null
var route: PackedVector3Array = PackedVector3Array()
var _route_cd := 0.0
var _star_blink := 0.0
var _fps_text := ""
var _fps_cd := 0.0

func _ready() -> void:
	name = "HUD"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	Events.notify.connect(_on_notify)
	Events.banner.connect(_on_banner)
	Events.cash_changed.connect(_on_cash)
	Events.player_died.connect(func(_c: String) -> void: fade_to(1.0, 3.2))
	Events.player_busted.connect(func() -> void: fade_to(1.0, 2.6))
	Events.player_respawned.connect(func() -> void: fade_to(0.0, 1.2))

var _fade_speed := 1.0
func fade_to(target: float, seconds: float) -> void:
	fade_target = target
	_fade_speed = 1.0 / maxf(seconds, 0.05)

func set_prompt(t: String) -> void:
	prompt_text = t

func damage_flash(amount: float) -> void:
	flash = clampf(flash + amount, 0.0, 1.0)

func show_radio(t: String) -> void:
	radio_text = t
	radio_time = 3.0

func set_waypoint(pos: Variant) -> void:
	waypoint = pos
	route = PackedVector3Array()
	_route_cd = 0.0
	if pos != null:
		Audio.play_ui(&"ui_map_ping", -6.0)

func _on_notify(text: String, kind: String) -> void:
	toasts.append([text, kind, 5.0])
	if toasts.size() > 5:
		toasts.pop_front()
	Audio.play_ui(&"ui_notify", -14.0)

func _on_banner(title: String, subtitle: String, color: Color, seconds: float) -> void:
	banner_title = title
	banner_sub = subtitle
	banner_color = color
	banner_time = seconds
	banner_total = seconds

func _on_cash(_total: int, delta_v: int) -> void:
	if delta_v != 0:
		cash_delta = delta_v
		cash_delta_time = 2.5

func _process(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 1.6)
	fade = move_toward(fade, fade_target, delta * _fade_speed)
	banner_time = maxf(0.0, banner_time - delta)
	radio_time = maxf(0.0, radio_time - delta)
	cash_delta_time = maxf(0.0, cash_delta_time - delta)
	district_time = maxf(0.0, district_time - delta)
	_star_blink += delta
	for t in toasts:
		t[2] -= delta
	toasts = toasts.filter(func(t: Array) -> bool: return t[2] > 0.0)
	var p: Player = Game.player
	if p != null:
		var d := Game.district_at(p.global_position)
		if d != district:
			district = d
			district_time = 4.0
			Events.district_changed.emit(d)
		_route_cd -= delta
		if waypoint != null and _route_cd <= 0.0 and Game.world != null and Game.world.graph != null:
			_route_cd = 1.2
			var wpos: Vector3 = waypoint
			if p.global_position.distance_to(wpos) < 14.0:
				set_waypoint(null)
				Game.notify("Destination reached", "good")
			else:
				var heading := Vector3.ZERO
				if p.vehicle != null and is_instance_valid(p.vehicle):
					heading = -(p.vehicle as Node3D).global_transform.basis.z
				route = Game.world.graph.route_points(p.global_position, wpos, heading)
	_fps_cd -= delta
	if _fps_cd <= 0.0:
		_fps_cd = 0.4
		_fps_text = "%d FPS" % Engine.get_frames_per_second()
	queue_redraw()

# ---------------------------------------------------------------- drawing helpers
func _text(pos: Vector2, s: String, size_px: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := true) -> void:
	if outline:
		draw_string_outline(font, pos, s, align, width, size_px, 5, Color(0, 0, 0, 0.75 * col.a))
	draw_string(font, pos, s, align, width, size_px, col)

func _bar(r: Rect2, frac: float, col: Color, back := Color(0, 0, 0, 0.55)) -> void:
	draw_rect(r, back)
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)

func _star(c: Vector2, r: float, col: Color, filled: bool) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	if filled:
		draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, col if filled else Color(col, 0.35), 1.5, true)

func _draw() -> void:
	var p: Player = Game.player
	var s := size
	if p != null and show_hud and fade < 0.98:
		_draw_minimap(p, Vector2(26.0, s.y - MAP_SIZE - 58.0))
		_draw_vitals(p, Vector2(26.0, s.y - 46.0))
		_draw_top_right(p, s)
		_draw_vehicle(p, s)
		_draw_crosshair(p, s)
		_draw_misc(p, s)
	# damage / low-health vignette
	var low := 0.0
	if p != null and p.alive and p.health < 30.0:
		low = (1.0 - p.health / 30.0) * (0.35 + 0.2 * sin(Time.get_ticks_msec() * 0.008))
	var v := maxf(flash * 0.55, low)
	if v > 0.01:
		var w := 140.0
		draw_rect(Rect2(0, 0, s.x, w), Color(0.8, 0.05, 0.05, v * 0.55))
		draw_rect(Rect2(0, s.y - w, s.x, w), Color(0.8, 0.05, 0.05, v * 0.55))
		draw_rect(Rect2(0, 0, w, s.y), Color(0.8, 0.05, 0.05, v * 0.55))
		draw_rect(Rect2(s.x - w, 0, w, s.y), Color(0.8, 0.05, 0.05, v * 0.55))
	if fade > 0.005:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, fade))
	# banner on top of the fade
	if banner_time > 0.0:
		var k := clampf(minf(banner_time, banner_total - banner_time) * 2.5, 0.0, 1.0)
		var col := Color(banner_color, k)
		_text(Vector2(0, s.y * 0.42), banner_title, 84, col, HORIZONTAL_ALIGNMENT_CENTER, s.x)
		if banner_sub != "":
			_text(Vector2(0, s.y * 0.42 + 44.0), banner_sub, 26, Color(1, 1, 1, k), HORIZONTAL_ALIGNMENT_CENTER, s.x)

func _draw_minimap(p: Player, origin: Vector2) -> void:
	var rect := Rect2(origin, Vector2(MAP_SIZE, MAP_SIZE))
	draw_rect(rect.grow(4.0), PANEL)
	if _mini == null:
		_mini = MiniMapView.new()
		_mini.hud = self
		_mini.clip_contents = true
		_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mini.show_behind_parent = false
		add_child(_mini)
	_mini.position = origin
	_mini.size = rect.size
	_mini.visible = show_hud
	_mini.queue_redraw()

var _mini: MiniMapView = null

class MiniMapView:
	extends Control
	var hud: HUD

	func _draw() -> void:
		var p: Player = Game.player
		if p == null or hud == null:
			return
		var msize := size.x
		draw_rect(Rect2(Vector2.ZERO, size), MapDraw.C_WATER)
		var center := size * 0.5
		var cam_yaw: float = Game.cam.yaw if Game.cam else 0.0
		var in_air := p.vehicle is Heli or p.vehicle is Airplane
		var scale_v := 0.95
		if in_air:
			scale_v = 0.5
		elif p.vehicle != null:
			scale_v = 0.75
		var pp := Vector2(p.global_position.x, p.global_position.z)
		# world (x,z) -> minimap pixels, rotated so the camera direction points up
		var xf := Transform2D(cam_yaw, Vector2.ZERO).scaled(Vector2(scale_v, scale_v))
		xf.origin = center - xf.basis_xform(pp)
		MapDraw.draw(self, xf, true, hud.font)
		if hud.route.size() >= 2:
			var line := PackedVector2Array()
			for rp in hud.route:
				line.append(xf * Vector2(rp.x, rp.z))
			draw_polyline(line, HUD.PINK, 4.0, true)
		if hud.waypoint != null:
			var w3: Vector3 = hud.waypoint
			var wp2 := xf * Vector2(w3.x, w3.z)
			wp2 = center + (wp2 - center).limit_length(msize * 0.47)
			draw_circle(wp2, 6.0, HUD.PINK)
			draw_circle(wp2, 2.5, Color.WHITE)
		MapDraw.draw_icons(self, xf, hud.font, 13.0, msize * 0.47, center)
		# police blips + search area
		if Game.wanted != null and Game.wanted.level > 0:
			var w: Node = Game.wanted
			if w.state == 2:
				var lk: Vector3 = w.last_known
				draw_circle(xf * Vector2(lk.x, lk.z), w.search_radius * scale_v, Color(0.3, 0.5, 1.0, 0.18))
			for unit in get_tree().get_nodes_in_group(&"police_units"):
				var up: Vector3 = (unit as Node3D).global_position
				var sp := xf * Vector2(up.x, up.z)
				sp = center + (sp - center).limit_length(msize * 0.47)
				var blink := fmod(hud._star_blink * 2.0, 1.0) < 0.5
				draw_circle(sp, 4.5, Color(1.0, 0.2, 0.2) if blink else Color(0.25, 0.45, 1.0))
		# player arrow (always centred)
		var heading := p.face_yaw
		if p.vehicle != null and is_instance_valid(p.vehicle):
			heading = (p.vehicle as Node3D).global_rotation.y
		var fwd := xf.basis_xform(Vector2(-sin(heading), -cos(heading))).normalized()
		var side := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([center + fwd * 9.0, center - fwd * 6.0 + side * 6.0, center - fwd * 3.0, center - fwd * 6.0 - side * 6.0]), Color.WHITE)
		var nd := xf.basis_xform(Vector2(0, -1)).normalized()
		draw_string(hud.font, center + nd * (msize * 0.5 - 12.0) + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HUD.ACCENT)

func _draw_vitals(p: Player, at: Vector2) -> void:
	var w := MAP_SIZE
	_bar(Rect2(at, Vector2(w * 0.5 - 3.0, 9.0)), p.health / p.max_health, Color(0.35, 0.85, 0.4) if p.health > 30.0 else Color(0.9, 0.25, 0.2))
	_bar(Rect2(at + Vector2(w * 0.5 + 3.0, 0), Vector2(w * 0.5 - 3.0, 9.0)), p.armor / 100.0, Color(0.3, 0.62, 1.0))
	if p.stamina < p.max_stamina() - 1.0 or p.state == Player.St.SWIM:
		_bar(Rect2(at + Vector2(0, 13.0), Vector2(w, 5.0)), p.stamina / p.max_stamina(), Color(1.0, 0.85, 0.3))
	if p.state == Player.St.SWIM and (p.breath < 0.999 or p.diving):
		_bar(Rect2(at + Vector2(0, 21.0), Vector2(w, 5.0)), p.breath, ACCENT)

func _draw_top_right(p: Player, s: Vector2) -> void:
	var x := s.x - 30.0
	var y := 46.0
	_text(Vector2(x - 400.0, y), "$%s" % _commas(Game.cash), 34, Color(0.45, 0.95, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, 400.0)
	if cash_delta_time > 0.0:
		var c := Color(0.45, 0.95, 0.5, cash_delta_time / 2.5) if cash_delta > 0 else Color(1.0, 0.4, 0.35, cash_delta_time / 2.5)
		_text(Vector2(x - 400.0, y + 26.0), ("+$%s" if cash_delta > 0 else "-$%s") % _commas(absi(cash_delta)), 20, c, HORIZONTAL_ALIGNMENT_RIGHT, 400.0)
	# wanted stars
	var lvl: int = Game.wanted.level if Game.wanted != null else 0
	var searching: bool = Game.wanted != null and Game.wanted.state == 2
	var blink := searching and fmod(_star_blink * 2.2, 1.0) < 0.45
	for i in 5:
		var c2 := Vector2(x - 14.0 - float(4 - i) * 30.0, y + 52.0)
		var on := i < lvl
		if on and not blink:
			_star(c2, 12.0, Color(1.0, 0.92, 0.35), true)
		else:
			_star(c2, 12.0, Color(1, 1, 1, 0.5), false)
	# weapon + ammo
	var g := p.gunner
	if g != null:
		var wname := String(g.data.get("name", ""))
		_text(Vector2(x - 400.0, y + 100.0), wname, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 400.0)
		if g.is_gun():
			var txt := "%d / %d" % [p.inventory.mag(g.weapon_id), p.inventory.reserve(g.weapon_id)]
			var colr := Color.WHITE if p.inventory.mag(g.weapon_id) > 0 else Color(1.0, 0.4, 0.35)
			if g.reload_left > 0.0:
				txt = "RELOADING"
				colr = ACCENT
			_text(Vector2(x - 400.0, y + 128.0), txt, 26, colr, HORIZONTAL_ALIGNMENT_RIGHT, 400.0)
		elif p.inventory.has(&"grenade") and g.weapon_id == &"grenade":
			_text(Vector2(x - 400.0, y + 128.0), "x%d" % p.inventory.reserve(&"grenade"), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 400.0)
	# clock + district
	if Game.time != null:
		_text(Vector2(26.0, 40.0), Game.time.clock_text(), 24, Color.WHITE)
		_text(Vector2(100.0, 40.0), String(Game.time.weather).capitalize(), 16, Color(1, 1, 1, 0.7))
	if district_time > 0.0:
		_text(Vector2(0, s.y - 96.0), district, 30, Color(1, 1, 1, clampf(district_time, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_RIGHT, s.x - 30.0)

func _draw_vehicle(p: Player, s: Vector2) -> void:
	var v := p.vehicle as Vehicle
	if v == null or not is_instance_valid(v) or p.state != Player.St.VEHICLE:
		return
	var x := s.x - 30.0
	var y := s.y - 40.0
	var kmh := absf(v.linear_velocity.length()) * 3.6
	_text(Vector2(x - 300.0, y), "%d" % int(kmh), 54, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	_text(Vector2(x - 300.0, y + 22.0), "km/h   " + String(v.def.get("name", "")), 16, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	_bar(Rect2(Vector2(x - 180.0, y - 70.0), Vector2(180.0, 7.0)), v.health / v.max_health, Color(1.0, 0.6, 0.2) if v.health / v.max_health > 0.35 else Color(0.95, 0.25, 0.2))
	if v is Heli or v is Airplane:
		var alt := maxf(0.0, v.global_position.y)
		_text(Vector2(x - 300.0, y - 84.0), "ALT %d m" % int(alt), 18, ACCENT, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
		if v is Airplane:
			_text(Vector2(x - 300.0, y - 106.0), "THR %d%%%s" % [int((v as Airplane).throttle * 100.0), "   STALL" if (v as Airplane).stalled else ""], 18,
				Color(1.0, 0.4, 0.3) if (v as Airplane).stalled else ACCENT, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	if radio_time > 0.0:
		_text(Vector2(0, 92.0), radio_text, 24, Color(1, 1, 1, clampf(radio_time, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, s.x)

func _draw_crosshair(p: Player, s: Vector2) -> void:
	var c := s * 0.5
	var g := p.gunner
	if g == null or not p.alive:
		return
	var cam: CameraRig = Game.cam
	if cam != null and cam.scoped:
		# sniper scope mask
		var r := s.y * 0.44
		var pts := 64
		for side in 2:
			var poly := PackedVector2Array()
			if side == 0:
				poly.append(Vector2(0, 0)); poly.append(Vector2(c.x, 0))
				for i in range(pts / 2 + 1):
					var a := -PI * 0.5 - PI * float(i) / float(pts / 2)
					poly.append(c + Vector2(cos(a), sin(a)) * r)
				poly.append(Vector2(c.x, s.y)); poly.append(Vector2(0, s.y))
			else:
				poly.append(Vector2(s.x, 0)); poly.append(Vector2(c.x, 0))
				for i in range(pts / 2 + 1):
					var a2 := -PI * 0.5 + PI * float(i) / float(pts / 2)
					poly.append(c + Vector2(cos(a2), sin(a2)) * r)
				poly.append(Vector2(c.x, s.y)); poly.append(Vector2(s.x, s.y))
			draw_colored_polygon(poly, Color(0, 0, 0, 1))
		draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0, 0, 0, 0.9), 1.5)
		draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0, 0, 0, 0.9), 1.5)
		draw_arc(c, r, 0.0, TAU, 96, Color(0, 0, 0, 1), 4.0)
		return
	var armed = g.is_gun() or g.data["cls"] == &"thrown"
	var show = armed and (p.aiming or p.combat_timer > 0.0 or p.state == Player.St.VEHICLE and p.aiming)
	if not show:
		if p.state == Player.St.FOOT and not armed:
			draw_circle(c, 1.6, Color(1, 1, 1, 0.35))
		return
	var gap := 5.0 + g.current_spread() * 4.2
	var col := Color(1, 1, 1, 0.92)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(c + d * gap, c + d * (gap + 8.0), Color(0, 0, 0, 0.6), 4.0)
		draw_line(c + d * gap, c + d * (gap + 8.0), col, 2.0)
	draw_circle(c, 1.4, col)

func _draw_misc(p: Player, s: Vector2) -> void:
	if info_text != "":
		var iw := font.get_string_size(info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_rect(Rect2(s.x * 0.5 - iw * 0.5 - 14.0, s.y - 196.0, iw + 28.0, 32.0), PANEL)
		draw_rect(Rect2(s.x * 0.5 - iw * 0.5 - 14.0, s.y - 196.0, 3.0, 32.0), Color(1.0, 0.8, 0.1))
		_text(Vector2(0, s.y - 174.0), info_text, 18, Color(1.0, 0.92, 0.6), HORIZONTAL_ALIGNMENT_CENTER, s.x, false)
	if prompt_text != "":
		var tw := font.get_string_size(prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_rect(Rect2(s.x * 0.5 - tw * 0.5 - 16.0, s.y - 150.0, tw + 32.0, 38.0), PANEL)
		_text(Vector2(0, s.y - 123.0), prompt_text, 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, s.x, false)
	var y := 96.0
	for t in toasts:
		var a := clampf(float(t[2]), 0.0, 1.0)
		var col := Color(1, 1, 1, a)
		match String(t[1]):
			"good": col = Color(0.5, 1.0, 0.6, a)
			"bad": col = Color(1.0, 0.5, 0.45, a)
			"money": col = Color(0.5, 0.95, 0.5, a)
			"wanted": col = Color(1.0, 0.9, 0.4, a)
		var tw2 := font.get_string_size(String(t[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_rect(Rect2(22.0, y - 20.0, tw2 + 20.0, 28.0), Color(PANEL, PANEL.a * a))
		draw_rect(Rect2(22.0, y - 20.0, 3.0, 28.0), Color(ACCENT, a))
		_text(Vector2(34.0, y), String(t[0]), 18, col, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
		y += 32.0
	if p.state == Player.St.MOVE and p.moves != null and (p.moves.mode == PlayerMoves.Mode.FREEFALL or p.moves.mode == PlayerMoves.Mode.CHUTE):
		_text(Vector2(0, s.y * 0.5 + 90.0), "ALT %d m" % int(p.moves.agl), 30, ACCENT, HORIZONTAL_ALIGNMENT_CENTER, s.x)
		if p.moves.mode == PlayerMoves.Mode.FREEFALL and p.parachute:
			_text(Vector2(0, s.y * 0.5 + 124.0), "[Space] deploy parachute", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, s.x)
	if Game.flags["show_fps"] or bool(Settings.get_v("show_fps", false)):
		_text(Vector2(s.x * 0.5 - 60.0, 26.0), _fps_text, 18, Color(0.6, 1.0, 0.6))
	if Game.flags["show_coords"]:
		var pos := p.global_position
		_text(Vector2(s.x * 0.5 - 200.0, 50.0), "X %.1f  Y %.1f  Z %.1f   sector %s" % [pos.x, pos.y, pos.z, Game.sector_of(pos)], 16, Color(0.8, 0.95, 1.0))
	if Game.cheats["invulnerable"]:
		_text(Vector2(26.0, 64.0), "GOD MODE", 14, PINK)

static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
