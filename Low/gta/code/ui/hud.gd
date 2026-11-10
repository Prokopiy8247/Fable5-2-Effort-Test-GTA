class_name HUD
extends CanvasLayer
# Original HUD: health/armor, ammo, wanted stars, money, radar minimap with GPS route,
# vehicle gauges, weapon wheel, full-screen map, notifications, scope overlay.

var root: Control
var mini: Control
var fade_rect: ColorRect
var font: Font
var dmg_flash := 0.0
var big := ""
var big_col := Color.WHITE
var big_t := 0.0
var wheel_vec := Vector2.ZERO
var wheel_slot := -1
var wheel_choice: Dictionary = {}
var map_open := false
var hidden := false
var activity_text := ""
var fps_smooth := 60.0
var checkpoint = null


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.draw.connect(_draw_hud)
	mini = Control.new()
	mini.clip_contents = true
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mini)
	mini.draw.connect(_draw_mini)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_rect)


func fade() -> void:
	fade_rect.color = Color(0, 0, 0, 1)
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(fade_rect, "color", Color(0, 0, 0, 0), 0.7)


func flash_damage(a: float) -> void:
	dmg_flash = max(dmg_flash, a)


func big_text(t: String, c: Color) -> void:
	big = t
	big_col = c
	big_t = 3.5


func _input(e: InputEvent) -> void:
	var p = G.player
	if p == null:
		return
	if e is InputEventKey and not e.echo:
		if e.physical_keycode == KEY_TAB and not G.menus.blocking() and not map_open:
			if e.pressed and not p.dead:
				p.wheel_open = true
				wheel_vec = Vector2.ZERO
				wheel_slot = Defs.WEAPONS[p.weapon].slot
				Engine.time_scale = 0.25
			elif p.wheel_open:
				_close_wheel(true)
		if e.pressed and e.physical_keycode == KEY_M and not G.menus.blocking():
			map_open = not map_open
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if map_open else Input.MOUSE_MODE_CAPTURED
		if e.pressed and e.physical_keycode == KEY_ESCAPE and map_open:
			map_open = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
	if p.wheel_open:
		if e is InputEventMouseMotion:
			wheel_vec = (wheel_vec + e.relative).limit_length(120.0)
			if wheel_vec.length() > 30.0:
				wheel_slot = wrapi(int(round(wheel_vec.angle() / (TAU / 8.0))) + 2, 0, 8)
			get_viewport().set_input_as_handled()
		elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var list := _slot_list(wheel_slot)
			if list.size() > 0:
				var cur: String = wheel_choice.get(wheel_slot, list[0])
				var i := list.find(cur)
				wheel_choice[wheel_slot] = list[wrapi(i + (1 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, list.size())]
			get_viewport().set_input_as_handled()
	elif map_open and e is InputEventMouseButton and e.pressed:
		var wp := _map_to_world(e.position)
		if e.button_index == MOUSE_BUTTON_LEFT:
			G.waypoint = wp
			G.audio.ui("click")
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			G.waypoint = null
		get_viewport().set_input_as_handled()


func _slot_list(slot: int) -> Array:
	var out: Array = []
	for w in Defs.WEAPON_ORDER:
		if w in G.player.owned and Defs.WEAPONS[w].slot == slot and G.player._allowed(w):
			out.append(w)
	return out


func _close_wheel(apply: bool) -> void:
	var p = G.player
	p.wheel_open = false
	Engine.time_scale = 1.0
	if apply and wheel_slot >= 0:
		var list := _slot_list(wheel_slot)
		if list.size() > 0:
			var c: String = wheel_choice.get(wheel_slot, list[0])
			if not c in list:
				c = list[0]
			p.equip(c)


func _process(dt: float) -> void:
	var s: float = root.size.y / 720.0
	mini.position = Vector2(24, root.size.y - 24 - 172 * s)
	mini.size = Vector2(172, 172) * s
	dmg_flash = max(0.0, dmg_flash - dt * 1.5)
	big_t = max(0.0, big_t - dt)
	fps_smooth = lerp(fps_smooth, float(Engine.get_frames_per_second()), 0.1)
	if G.player and G.player.wheel_open and (G.player.dead or G.menus.blocking()):
		_close_wheel(false)
	root.queue_redraw()
	mini.queue_redraw()


func txt(c: Control, pos: Vector2, t: String, size: float, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	c.draw_string(font, pos + Vector2(1.5, 1.5), t, align, width, int(size), Color(0, 0, 0, 0.7))
	c.draw_string(font, pos, t, align, width, int(size), col)


func bar(pos: Vector2, size: Vector2, frac: float, col: Color) -> void:
	root.draw_rect(Rect2(pos, size), Color(0, 0, 0, 0.55))
	root.draw_rect(Rect2(pos + Vector2(2, 2), Vector2((size.x - 4) * clamp(frac, 0.0, 1.0), size.y - 4)), col)


func star(center: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + i * TAU / 10.0
		pts.append(center + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	root.draw_colored_polygon(pts, col)


func _draw_hud() -> void:
	var p = G.player
	if p == null:
		return
	var W: float = root.size.x
	var H: float = root.size.y
	var s: float = H / 720.0
	mini.visible = not hidden and not map_open
	if G.cam.cam.global_position.y < G.WATER_Y:
		root.draw_rect(Rect2(0, 0, W, H), Color(0.0, 0.25, 0.4, 0.28))
	if dmg_flash > 0.0:
		root.draw_rect(Rect2(0, 0, W, H), Color(0.8, 0.0, 0.0, 0.35 * dmg_flash))
	if p.health < 30.0 and not p.dead:
		var pulse: float = 0.12 + 0.1 * sin(Time.get_ticks_msec() / 150.0)
		for i in 4:
			root.draw_rect(Rect2(i * 12 * s, i * 12 * s, W - i * 24 * s, H - i * 24 * s), Color(0.8, 0, 0, pulse * 0.4), false, 14 * s)
	if G.cam.scoped:
		var cc := Vector2(W, H) / 2
		var R := H * 0.42
		root.draw_arc(cc, R + W, 0, TAU, 64, Color.BLACK, W * 2.0)
		root.draw_arc(cc, R, 0, TAU, 96, Color.BLACK, 6 * s)
		root.draw_line(cc - Vector2(R, 0), cc + Vector2(R, 0), Color(0, 0, 0, 0.9), 1.5)
		root.draw_line(cc - Vector2(0, R), cc + Vector2(0, R), Color(0, 0, 0, 0.9), 1.5)
	if big_t > 0.0:
		txt(root, Vector2(0, H * 0.45), big, 84 * s, big_col, HORIZONTAL_ALIGNMENT_CENTER, W)
	if hidden:
		return
	if map_open:
		_draw_map(W, H, s)
		return
	# --- top right: stars, money, time
	var wn = G.wanted
	var x := W - 30 * s
	if wn:
		for i in 5:
			var on: bool = i < wn.stars
			var col := Color(1.0, 0.82, 0.15) if on else Color(0, 0, 0, 0.4)
			if on and wn.state == "search" and fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.4:
				col = Color(1.0, 0.82, 0.15, 0.35)
			star(Vector2(x - (4 - i) * 34 * s - 14 * s, 38 * s), 15 * s, col)
	txt(root, Vector2(W - 330 * s, 88 * s), "$%s" % _money(G.money), 30 * s, Color(0.55, 0.95, 0.55), HORIZONTAL_ALIGNMENT_RIGHT, 300 * s)
	if G.sky:
		txt(root, Vector2(W - 330 * s, 114 * s), "%s  %s" % [G.sky.time_text(), G.sky.weather.capitalize()], 17 * s, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, 300 * s)
	txt(root, Vector2(W - 330 * s, 136 * s), G.district_at(p.global_position), 16 * s, Color(0.75, 0.85, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 300 * s)
	# --- weapon / ammo
	var wd: Dictionary = p.wdef()
	txt(root, Vector2(W - 330 * s, H - 64 * s), wd.name, 20 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 300 * s)
	if wd.has("mag"):
		var at := "%d / %d" % [p.clip.get(p.weapon, 0), p.reserve.get(p.weapon, 0)]
		if p.reload_t > 0.0:
			at = "RELOADING"
		txt(root, Vector2(W - 330 * s, H - 30 * s), at, 30 * s, Color(1, 0.95, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 300 * s)
	# --- bars
	var bx := 24.0
	var by := H - 24 - 172 * s - 34 * s
	bar(Vector2(bx, by), Vector2(110 * s, 12 * s), p.health / p.max_health, Color(0.3, 0.85, 0.35) if p.health > 30 else Color(0.9, 0.2, 0.2))
	bar(Vector2(bx + 114 * s, by), Vector2(58 * s, 12 * s), p.armor / 100.0, Color(0.3, 0.6, 1.0))
	if p.stamina < 99.0:
		bar(Vector2(bx, by - 12 * s), Vector2(172 * s, 8 * s), p.stamina / 100.0, Color(1.0, 0.85, 0.3))
	if p.state == "swim":
		bar(Vector2(bx, by - 24 * s), Vector2(172 * s, 8 * s), p.breath / p.max_breath(), Color(0.4, 0.85, 1.0))
		txt(root, Vector2(bx, by - 30 * s), "AIR" + (" (scuba)" if p.has_scuba else ""), 13 * s)
	# --- vehicle
	if p.vehicle != null and p.state == "vehicle":
		var v = p.vehicle
		var vx := W / 2 - 110 * s
		var vy := H - 70 * s
		txt(root, Vector2(vx, vy), "%d km/h" % int(v.linear_velocity.length() * 3.6), 30 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 220 * s)
		bar(Vector2(vx, vy + 10 * s), Vector2(220 * s, 10 * s), v.health / v.max_health, Color(0.9, 0.6, 0.2))
		var extra: String = v.def.name
		if v.kind in ["heli", "plane"] or p.state == "chute":
			extra += "   ALT %d m" % int(v.global_position.y - max(G.height(v.global_position.x, v.global_position.z), G.WATER_Y))
		if v.kind == "plane":
			extra += "   THR %d%%" % int(v.plane_throttle * 100.0)
			if v.grounded == 0 and v.fspeed < v.def.stall:
				txt(root, Vector2(0, H * 0.3), "STALL", 36 * s, Color(1, 0.3, 0.2), HORIZONTAL_ALIGNMENT_CENTER, W)
		if G.audio.station > 0 and not v.def.get("pedal", false):
			extra += "   Radio: " + G.audio.stations[G.audio.station]
		txt(root, Vector2(vx - 140 * s, vy + 40 * s), extra, 15 * s, Color(0.85, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 500 * s)
	elif p.state == "chute":
		txt(root, Vector2(0, H - 70 * s), "ALT %d m   W dive / S flare / A-D steer / F cut away" % int(p.global_position.y - max(G.height(p.global_position.x, p.global_position.z), G.WATER_Y)), 18 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, W)
	# --- crosshair
	if not p.dead and not G.cam.scoped and (p.aiming or (p.weapon != "fists" and p.state in ["normal", "cover", "vehicle"])):
		var c := Vector2(W, H) / 2
		var g: float = (6.0 if p.zoomed else 11.0) * s
		var col2 := Color(1, 1, 1, 0.85)
		root.draw_circle(c, 1.6 * s, col2)
		if not p.wdef().get("melee", false):
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				root.draw_line(c + d * g, c + d * (g + 7 * s), col2, 2.0)
	# --- prompt, notes, activity
	if p.prompt != "":
		var tw := 620 * s
		root.draw_rect(Rect2(W / 2 - tw / 2, H - 150 * s, tw, 30 * s), Color(0, 0, 0, 0.5))
		txt(root, Vector2(W / 2 - tw / 2, H - 129 * s), p.prompt, 17 * s, Color(1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, tw)
	var now := Time.get_ticks_msec() / 1000.0
	var ny := 40.0 * s
	for n in G._notes:
		if n.until > now:
			root.draw_rect(Rect2(20, ny - 18 * s, min(560 * s, 14 * s + n.t.length() * 9.6 * s), 25 * s), Color(0, 0, 0, 0.5))
			txt(root, Vector2(28, ny), n.t, 16 * s)
			ny += 28 * s
	if activity_text != "":
		txt(root, Vector2(0, 70 * s), activity_text, 24 * s, Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER, W)
	if G.show_fps:
		txt(root, Vector2(W / 2 - 60 * s, 22 * s), "FPS %d" % int(fps_smooth), 16 * s, Color(0.6, 1, 0.6))
	if G.show_coords:
		var pp: Vector3 = p.global_position
		txt(root, Vector2(W / 2 - 200 * s, 42 * s), "X %.1f  Y %.1f  Z %.1f   %s   NPC %d  VEH %d" % [pp.x, pp.y, pp.z, G.district_at(pp), G.humanoids.size(), G.vehicles.size()], 14 * s, Color(0.8, 0.9, 1))
	if G.invulnerable:
		txt(root, Vector2(W / 2 + 40 * s, 22 * s), "GOD", 16 * s, Color(1, 0.8, 0.2))
	if p.wheel_open:
		_draw_wheel(W, H, s)


func _money(n: int) -> String:
	var st := str(n)
	var out := ""
	while st.length() > 3:
		out = "," + st.substr(st.length() - 3) + out
		st = st.substr(0, st.length() - 3)
	return st + out


func _draw_wheel(W: float, H: float, s: float) -> void:
	var p = G.player
	var c := Vector2(W, H) / 2
	root.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.35))
	var R := 210.0 * s
	for i in 8:
		var a := (i - 2) * TAU / 8.0
		var pos := c + Vector2(cos(a), sin(a)) * R
		var list := _slot_list(i)
		var sel := i == wheel_slot
		var col := Color(0.15, 0.65, 0.75, 0.9) if sel else Color(0.05, 0.07, 0.1, 0.8)
		if list.is_empty():
			col.a = 0.35
		root.draw_circle(pos, 62 * s, col)
		root.draw_arc(pos, 62 * s, 0, TAU, 32, Color(1, 1, 1, 0.5 if sel else 0.15), 2.0)
		txt(root, pos + Vector2(-60 * s, -22 * s), Defs.SLOT_NAMES[i], 13 * s, Color(0.7, 0.85, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 120 * s)
		if not list.is_empty():
			var w: String = wheel_choice.get(i, list[0])
			if not w in list:
				w = list[0]
			var d: Dictionary = Defs.WEAPONS[w]
			txt(root, pos + Vector2(-60 * s, 2 * s), d.name, 13 * s, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 120 * s)
			if d.has("mag"):
				txt(root, pos + Vector2(-60 * s, 22 * s), "%d / %d" % [p.clip.get(w, 0), p.reserve.get(w, 0)], 13 * s, Color(1, 0.95, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 120 * s)
			if list.size() > 1:
				txt(root, pos + Vector2(-60 * s, 40 * s), "scroll: %d more" % (list.size() - 1), 10 * s, Color(0.7, 0.7, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 120 * s)
	root.draw_line(c, c + wheel_vec * s, Color(1, 1, 1, 0.5), 2.0)
	txt(root, c + Vector2(-150 * s, 6 * s), "WEAPON WHEEL", 16 * s, Color(0.8, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 300 * s)


# ---------------------------------------------------------------- minimap
func _map_shapes(c: Control, f: Callable, zoom: float) -> void:
	# f maps world Vector3 -> control Vector2
	var land := PackedVector2Array([f.call(Vector3(-289, 0, -293)), f.call(Vector3(289, 0, -293)), f.call(Vector3(289, 0, 212)), f.call(Vector3(-289, 0, 212))])
	c.draw_colored_polygon(land, Color(0.3, 0.47, 0.3))
	var sand := PackedVector2Array([f.call(Vector3(-289, 0, 172)), f.call(Vector3(289, 0, 172)), f.call(Vector3(289, 0, 212)), f.call(Vector3(-289, 0, 212))])
	c.draw_colored_polygon(sand, Color(0.8, 0.74, 0.55))
	var plate := PackedVector2Array([f.call(Vector3(-209, 0, -209)), f.call(Vector3(129, 0, -209)), f.call(Vector3(129, 0, 170)), f.call(Vector3(-209, 0, 170))])
	c.draw_colored_polygon(plate, Color(0.2, 0.21, 0.24))
	var ap := PackedVector2Array([f.call(Vector3(129, 0, -215)), f.call(Vector3(290, 0, -215)), f.call(Vector3(290, 0, 200)), f.call(Vector3(129, 0, 200))])
	c.draw_colored_polygon(ap, Color(0.42, 0.42, 0.44))
	var rw := PackedVector2Array([f.call(Vector3(227, 0, -210)), f.call(Vector3(253, 0, -210)), f.call(Vector3(253, 0, 196)), f.call(Vector3(227, 0, 196))])
	c.draw_colored_polygon(rw, Color(0.2, 0.21, 0.24))
	for i in 4:
		for j in 4:
			var r: Rect2 = G.world.block_rect(i, j)
			var d: String = Defs.DISTRICTS[i][j]
			var col := Color(0.5, 0.5, 0.52)
			if d == "park": col = Color(0.3, 0.6, 0.3)
			elif d == "residential": col = Color(0.5, 0.56, 0.46)
			elif d == "industrial": col = Color(0.45, 0.43, 0.4)
			elif d == "downtown": col = Color(0.5, 0.54, 0.62)
			c.draw_colored_polygon(PackedVector2Array([f.call(Vector3(r.position.x, 0, r.position.y)), f.call(Vector3(r.end.x, 0, r.position.y)), f.call(Vector3(r.end.x, 0, r.end.y)), f.call(Vector3(r.position.x, 0, r.end.y))]), col)
	var prom := PackedVector2Array([f.call(Vector3(-209, 0, 129)), f.call(Vector3(129, 0, 129)), f.call(Vector3(129, 0, 170)), f.call(Vector3(-209, 0, 170))])
	c.draw_colored_polygon(prom, Color(0.6, 0.56, 0.48))
	# GPS route
	if G.waypoint != null:
		var g = G.roads
		var pth: Array = g.path(g.nearest(G.player.global_position), g.nearest(G.waypoint))
		var pts := PackedVector2Array([f.call(G.player.global_position)])
		for n in pth:
			pts.append(f.call(g.nodes[n]))
		pts.append(f.call(G.waypoint))
		c.draw_polyline(pts, Color(0.9, 0.3, 0.9), 3.0 * zoom)
		c.draw_circle(f.call(G.waypoint), 5.0 * zoom, Color(0.95, 0.3, 0.95))
	if checkpoint != null:
		c.draw_circle(f.call(checkpoint), 6.0 * zoom, Color(1.0, 0.9, 0.2))
	for ic in G.map_icons:
		var ip: Vector2 = f.call(ic.pos)
		c.draw_circle(ip, 5.0 * zoom, Color(0, 0, 0, 0.7))
		c.draw_circle(ip, 3.8 * zoom, ic.color)


func _draw_mini() -> void:
	var p = G.player
	if p == null or G.world == null:
		return
	var sz: Vector2 = mini.size
	var c := sz / 2
	var yaw: float = G.cam.yaw
	var ppos: Vector3 = p.global_position
	var scale: float = sz.x / 230.0
	if p.vehicle != null:
		scale = sz.x / (230.0 + clamp(p.vehicle.linear_velocity.length() * 4.0, 0.0, 200.0))
	var f := func(w: Vector3) -> Vector2:
		return c + Vector2(w.x - ppos.x, w.z - ppos.z).rotated(yaw) * scale
	mini.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.12, 0.3, 0.45, 0.92))
	_map_shapes(mini, f, 1.0)
	_blips(mini, f, 1.0)
	# player arrow
	var a: float = -(p.global_rotation.y if p.vehicle == null else p.vehicle.global_rotation.y) + yaw
	var tri := PackedVector2Array([c + Vector2(0, -8).rotated(a), c + Vector2(5.5, 6).rotated(a), c + Vector2(-5.5, 6).rotated(a)])
	mini.draw_colored_polygon(tri, Color.WHITE)
	var north := c + Vector2(0, -sz.y * 0.44).rotated(yaw)
	txt(mini, north + Vector2(-5, 5), "N", 14, Color(1, 0.9, 0.6))
	mini.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.8), false, 3.0)


func _blips(c: Control, f: Callable, zoom: float) -> void:
	var wn = G.wanted
	var blink: bool = fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.3
	for h in G.humanoids:
		if h is NPC and not h.dead and h.role in ["cop", "swat"] and h.state != "vehicle":
			var hp: Vector2 = f.call(h.global_position)
			if wn and wn.stars > 0:
				var fa: Vector2 = (f.call(h.global_position - h.global_basis.z * 30.0) - hp)
				var ang := fa.angle()
				var cone := PackedVector2Array([hp])
				for k in 7:
					cone.append(hp + Vector2.from_angle(ang - 0.6 + k * 0.2) * fa.length())
				c.draw_colored_polygon(cone, Color(0.3, 0.5, 1.0, 0.22))
			c.draw_circle(hp, 3.2 * zoom, Color(0.3, 0.5, 1.0))
		elif h is NPC and not h.dead and h.role == "gang":
			c.draw_circle(f.call(h.global_position), 2.6 * zoom, Color(0.75, 0.3, 0.9))
	for v in G.vehicles:
		if v.wrecked:
			continue
		if v.owner_tag == "police":
			c.draw_circle(f.call(v.global_position), 4.5 * zoom, Color(1, 0.2, 0.2) if (blink and wn and wn.stars > 0) else Color(0.3, 0.5, 1.0))
		elif v.owner_tag == "taxi":
			c.draw_circle(f.call(v.global_position), 4.0 * zoom, Color(1.0, 0.85, 0.2))
		elif v.owner_tag == "ems":
			c.draw_circle(f.call(v.global_position), 4.0 * zoom, Color(1, 1, 1))
	if wn and wn.stars > 0 and not wn.seen:
		c.draw_arc(f.call(wn.last_known), (14.0 + min(wn.unseen_t * 2.2, 55.0)) * (c.size.x / 230.0 if c == mini else zoom * 1.0), 0, TAU, 32, Color(1, 0.3, 0.3, 0.7), 2.0)


func _map_rect() -> Rect2:
	var H: float = root.size.y
	var W: float = root.size.x
	var side: float = H * 0.9
	return Rect2((W - side) / 2, H * 0.05, side, side)


func _map_to_world(sp: Vector2) -> Vector3:
	var r := _map_rect()
	var u := (sp - r.position) / r.size
	return Vector3(-330.0 + u.x * 660.0, 0.3, -330.0 + u.y * 660.0)


func _draw_map(W: float, H: float, s: float) -> void:
	var r := _map_rect()
	root.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.6))
	root.draw_rect(r, Color(0.12, 0.3, 0.45))
	var k: float = r.size.x / 660.0
	var f := func(w: Vector3) -> Vector2:
		return r.position + Vector2(w.x + 330.0, w.z + 330.0) * k
	_map_shapes(root, f, 1.6)
	_blips(root, f, 1.5)
	for ic in G.map_icons:
		txt(root, f.call(ic.pos) + Vector2(8, 5), ic.label, 13 * s)
	var p = G.player
	var pc: Vector2 = f.call(p.global_position)
	var a: float = -p.global_rotation.y
	root.draw_colored_polygon(PackedVector2Array([pc + Vector2(0, -11).rotated(a), pc + Vector2(7, 8).rotated(a), pc + Vector2(-7, 8).rotated(a)]), Color.WHITE)
	txt(root, Vector2(r.position.x, r.position.y - 8), "MAP   left click: set waypoint   right click: clear   M / Esc: close", 16 * s)
