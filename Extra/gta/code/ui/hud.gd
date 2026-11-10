extends CanvasLayer
## HUD: health / armor / breath / stamina, weapon + ammo, wanted stars, money, clock, minimap & full map
## with waypoint + GPS route, speedometer, prompts, notifications, crosshair, scope, weapon wheel,
## damage feedback, big messages and screen fades. Original Cinder Bay styling.

const ICONS := {"hospital": ["+", Color("ff5a4a")], "police": ["P", Color("5a8cff")], "gun": ["G", Color("ffb347")], "shirt": ["C", Color("3fe0c5")],
	"scissors": ["B", Color("ff7ad9")], "wrench": ["M", Color("ffd23e")], "home": ["H", Color("7dff8a")], "garage": ["V", Color("7dff8a")],
	"store": ["S", Color("ffd23e")], "fuel": ["F", Color("ff9a3c")], "plane": ["A", Color("c9d6ff")], "anchor": ["D", Color("6fd0ff")],
	"target": ["R", Color("ff6b4a")], "train": ["T", Color("d9d9d9")], "tower": ["^", Color("ffffff")], "view": ["*", Color("9fe07a")],
	"park": ["*", Color("9fe07a")], "beach": ["~", Color("ffe9a8")], "lighthouse": ["L", Color("ffffff")], "wreck": ["W", Color("6fd0ff")],
	"parking": ["p", Color("b0b6c0")]}

var root: Control
var mini: MapView
var full: MapView
var full_wrap: PanelContainer
var bars := {}
var money_l: Label
var time_l: Label
var weapon_l: Label
var ammo_l: Label
var veh_l: Label
var speed_l: Label
var prompt_l: Label
var district_l: Label
var big_l: Label
var info_l: Label
var hint_l: Label
var radio_l: Label
var notes: VBoxContainer
var stars: Control
var cross: Control
var fade_r: ColorRect
var tint_r: ColorRect
var veh_bar: ProgressBar
var wheel: WeaponWheel
var waypoint = null
var route := PackedVector3Array()
var _district := ""
var _district_t := 0.0
var _dmg := 0.0
var _dmg_dir := 0.0
var _hit := 0.0
var _hit_kill := false
var _big_t := 0.0
var _route_t := 0.0
var prompt_text := ""
var alt_text := ""


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	tint_r = ColorRect.new()
	tint_r.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint_r.color = Color(0, 0, 0, 0)
	tint_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tint_r)
	cross = Crosshair.new()
	cross.hud = self
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)
	# --- bottom left: minimap + bars
	var bl := VBoxContainer.new()
	bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl.position = Vector2(28, -330)
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bl.add_theme_constant_override("separation", 5)
	root.add_child(bl)
	mini = MapView.new()
	mini.hud = self
	mini.custom_minimum_size = Vector2(230, 230)
	mini.mini = true
	bl.add_child(mini)
	for b in [["health", Color("5fd35f")], ["armor", Color("4aa8ff")], ["stamina", Color("ffd23e")], ["breath", Color("7ae0ff")]]:
		var pb := UIKit.bar(b[1], 230, 11 if b[0] in ["health", "armor"] else 6)
		bl.add_child(pb)
		bars[b[0]] = pb
	# --- top right: stars, money, clock
	var tr := VBoxContainer.new()
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.position = Vector2(-330, 22)
	tr.custom_minimum_size = Vector2(300, 0)
	tr.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(tr)
	stars = Stars.new()
	stars.custom_minimum_size = Vector2(300, 44)
	tr.add_child(stars)
	money_l = UIKit.label("$0", 30, Color("8fe38f"))
	money_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(money_l)
	time_l = UIKit.label("", 16, UIKit.DIM)
	time_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(time_l)
	info_l = UIKit.label("", 14, UIKit.TEAL)
	info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(info_l)
	# --- bottom right: weapon / vehicle
	var br := VBoxContainer.new()
	br.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br.position = Vector2(-330, -190)
	br.custom_minimum_size = Vector2(300, 0)
	br.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(br)
	speed_l = UIKit.label("", 40, UIKit.TEXT)
	speed_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(speed_l)
	veh_l = UIKit.label("", 16, UIKit.DIM)
	veh_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(veh_l)
	veh_bar = UIKit.bar(Color("ff9a3c"), 200, 7)
	veh_bar.size_flags_horizontal = Control.SIZE_SHRINK_END
	br.add_child(veh_bar)
	radio_l = UIKit.label("", 14, UIKit.GOLD)
	radio_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(radio_l)
	weapon_l = UIKit.label("", 20, UIKit.TEXT)
	weapon_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(weapon_l)
	ammo_l = UIKit.label("", 32, UIKit.GOLD)
	ammo_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(ammo_l)
	# --- centre texts
	prompt_l = UIKit.label("", 20, UIKit.TEXT)
	prompt_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_l.position = Vector2(-300, -170)
	prompt_l.custom_minimum_size = Vector2(600, 0)
	prompt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt_l)
	hint_l = UIKit.label("", 14, UIKit.DIM)
	hint_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_l.position = Vector2(-450, -44)
	hint_l.custom_minimum_size = Vector2(900, 0)
	hint_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint_l)
	district_l = UIKit.label("", 26, UIKit.TEXT)
	district_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	district_l.position = Vector2(-300, -120)
	district_l.custom_minimum_size = Vector2(600, 0)
	district_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	district_l.modulate.a = 0.0
	root.add_child(district_l)
	big_l = UIKit.label("", 84, UIKit.CORAL)
	big_l.set_anchors_preset(Control.PRESET_CENTER)
	big_l.position = Vector2(-600, -90)
	big_l.custom_minimum_size = Vector2(1200, 0)
	big_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_l.add_theme_constant_override("outline_size", 12)
	big_l.modulate.a = 0.0
	root.add_child(big_l)
	notes = VBoxContainer.new()
	notes.set_anchors_preset(Control.PRESET_TOP_LEFT)
	notes.position = Vector2(28, 26)
	notes.custom_minimum_size = Vector2(520, 0)
	root.add_child(notes)
	# --- full map
	full_wrap = PanelContainer.new()
	full_wrap.set_anchors_preset(Control.PRESET_CENTER)
	full_wrap.custom_minimum_size = Vector2(820, 820)
	full_wrap.position = Vector2(-410, -410)
	full_wrap.visible = false
	root.add_child(full_wrap)
	var fv := VBoxContainer.new()
	full_wrap.add_child(fv)
	fv.add_child(UIKit.label("CINDER BAY", 26, UIKit.CORAL))
	full = MapView.new()
	full.hud = self
	full.custom_minimum_size = Vector2(780, 700)
	full.mouse_filter = Control.MOUSE_FILTER_STOP
	fv.add_child(full)
	fv.add_child(UIKit.label("Left click: set waypoint    Right click: clear    M / Esc: close", 14, UIKit.DIM))
	wheel = WeaponWheel.new()
	wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	wheel.visible = false
	root.add_child(wheel)
	fade_r = ColorRect.new()
	fade_r.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_r.color = Color(0, 0, 0, 0)
	fade_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade_r)
	_pin(bl, Control.PRESET_BOTTOM_LEFT, 24)
	_pin(tr, Control.PRESET_TOP_RIGHT, 22)
	_pin(br, Control.PRESET_BOTTOM_RIGHT, 24)
	G.notify.connect(_notify)
	G.money_changed.connect(func(_m): pass)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _pin(c: Control, preset: int, margin: int) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, margin)
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT] else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT] else Control.GROW_DIRECTION_END


func _notify(text: String, color: Color) -> void:
	var l := UIKit.label(text, 17, color)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UIKit.box(Color(0.04, 0.05, 0.07, 0.72), 6, Color(color.r, color.g, color.b, 0.5), 1, 7))
	pc.add_child(l)
	notes.add_child(pc)
	if notes.get_child_count() > 6:
		notes.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(pc, "modulate:a", 0.0, 0.6)
	tw.tween_callback(pc.queue_free)


func big_message(text: String, col: Color) -> void:
	big_l.text = text
	big_l.add_theme_color_override("font_color", col)
	_big_t = 3.5


func fade(to_black: bool, dur: float) -> void:
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(fade_r, "color:a", 1.0 if to_black else 0.0, dur)
	await tw.finished


func damage_flash(from: Vector3, amount: float) -> void:
	_dmg = clampf(_dmg + amount * 0.03 + 0.2, 0.0, 1.0)
	if G.cam and G.player:
		var to := G.flat(from - G.player.global_position_now())
		var f := G.flat(G.cam.forward())
		_dmg_dir = atan2(f.cross(to).y, f.dot(to))


func hit_marker(kill: bool) -> void:
	_hit = 0.22
	_hit_kill = kill


func weapon_changed() -> void:
	pass


func vehicle_entered(_v) -> void:
	pass


func set_waypoint(p) -> void:
	waypoint = p
	_route_t = 0.0
	if p == null:
		route = PackedVector3Array()
		G.say("Waypoint cleared", UIKit.DIM)
	else:
		G.say("Waypoint set", UIKit.TEAL)


func _compute_route() -> void:
	route = PackedVector3Array()
	if waypoint == null or G.player == null:
		return
	var from: Vector3 = G.player.global_position_now()
	var to: Vector3 = waypoint
	var a := WorldLayout.nearest_inter(from)
	var b := WorldLayout.nearest_inter(to)
	var prev := {a: a}
	var q: Array = [a]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == b:
			break
		for n in WorldLayout.neighbors(c):
			if not prev.has(n):
				prev[n] = c
				q.append(n)
	var pts: Array = [to]
	var c2 := b
	while prev.has(c2):
		pts.push_front(WorldLayout.inter_pos(c2))
		if c2 == a:
			break
		c2 = prev[c2]
	pts.push_front(from)
	if pts.size() > 3 and (pts[1] as Vector3).distance_to(pts[2]) > from.distance_to(pts[2]):
		pts.remove_at(1)
	for p in pts:
		route.append(p)
	if from.distance_to(to) < 14.0:
		set_waypoint(null)
		G.say("Destination reached", UIKit.TEAL)


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("map") and (G.ui_blocking == 0 or full_wrap.visible):
		_toggle_map()
	elif full_wrap.visible and ev.is_action_pressed("pause"):
		_toggle_map()
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("weapon_wheel") and G.ui_blocking == 0 and G.player and not G.player.dead:
		wheel.open()
	elif ev.is_action_released("weapon_wheel") and wheel.visible:
		wheel.close()


func _toggle_map() -> void:
	full_wrap.visible = not full_wrap.visible
	if full_wrap.visible:
		G.ui_blocking += 1
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		G.ui_blocking = maxi(G.ui_blocking - 1, 0)
		if G.ui_blocking == 0:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var p: Node = G.player
	if p == null:
		return
	bars.health.value = p.health / p.max_health
	bars.armor.value = p.armor / 100.0
	bars.armor.visible = p.armor > 0.5
	bars.stamina.value = p.stamina
	bars.stamina.visible = p.stamina < 0.99
	bars.breath.value = p.breath
	bars.breath.visible = p.breath < 0.99
	money_l.text = G.fmt_money(p.money)
	if G.timew:
		time_l.text = "%s   %s" % [G.timew.time_string(), String(G.timew.weather).capitalize()]
	var extra := ""
	if G.flags.show_fps:
		extra += "%d FPS   " % Engine.get_frames_per_second()
	if G.flags.show_coords:
		var pp: Vector3 = p.global_position_now()
		var blk := WorldLayout.block_of(pp)
		extra += "X %.0f  Y %.1f  Z %.0f   sector %d,%d" % [pp.x, pp.y, pp.z, blk.x, blk.y]
	if G.flags.god:
		extra += "   GOD"
	info_l.text = extra + (("   " + alt_text) if alt_text != "" else "")
	# weapon / vehicle
	var wd: Dictionary = p.wdef()
	var veh: Vehicle = p.vehicle
	if veh != null and not p.can_use_weapon_in_vehicle():
		weapon_l.text = ""
		ammo_l.text = ""
	else:
		weapon_l.text = wd.name
		if wd.has("ammo"):
			ammo_l.text = ("%d" % p.inv.in_clip(p.inv.current)) if wd.type == "throw" else "%d / %d" % [p.inv.in_clip(p.inv.current), p.inv.reserve(p.inv.current)]
			if p.reloading > 0.0:
				ammo_l.text = "reloading"
		else:
			ammo_l.text = ""
	if veh != null:
		speed_l.text = "%d km/h" % int(veh.speed * 3.6)
		veh_l.text = veh.def.name
		veh_bar.visible = true
		veh_bar.value = veh.health / veh.max_health
		if veh.kind in ["heli", "plane"]:
			speed_l.text = "%d km/h   ALT %d m" % [int(veh.speed * 3.6), int(veh.global_position.y)]
	else:
		speed_l.text = ""
		veh_l.text = ""
		veh_bar.visible = false
		if p.st == p.St.CHUTE or (p.air_t > 1.0 and p.st == p.St.FOOT):
			speed_l.text = "ALT %d m" % int(p._height_above_ground())
	radio_l.text = Sfx.radio_label() if (veh != null and Sfx.has_method("radio_label")) else ""
	# prompt / hints
	prompt_l.text = prompt_text
	hint_l.text = _hints(p, veh)
	# district banner
	var dn := WorldLayout.district_at(p.global_position_now())
	if dn != _district:
		_district = dn
		_district_t = 3.5
		district_l.text = dn
	_district_t = maxf(_district_t - delta, 0.0)
	district_l.modulate.a = clampf(_district_t, 0.0, 1.0)
	_big_t = maxf(_big_t - delta, 0.0)
	big_l.modulate.a = clampf(_big_t, 0.0, 1.0)
	# damage / low health / underwater tint
	_dmg = maxf(_dmg - delta * 0.9, 0.0)
	_hit = maxf(_hit - delta, 0.0)
	var low := clampf(1.0 - p.health / 35.0, 0.0, 1.0) * (0.25 + 0.12 * sin(Time.get_ticks_msec() * 0.008))
	var under: bool = G.timew != null and G.timew.underwater
	if under:
		tint_r.color = Color(0.0, 0.25, 0.35, 0.32)
	else:
		tint_r.color = Color(0.7, 0.0, 0.0, clampf(_dmg * 0.4 + low, 0.0, 0.6))
	cross.queue_redraw()
	stars.queue_redraw()
	mini.queue_redraw()
	if full_wrap.visible:
		full.queue_redraw()
	_route_t -= delta
	if waypoint != null and _route_t <= 0.0:
		_route_t = 0.7
		_compute_route()


func _hints(p: Node, veh: Vehicle) -> String:
	if G.ui_blocking > 0:
		return ""
	if veh != null:
		match veh.kind:
			"heli": return "W/S pitch   A/D roll   Q/E yaw   Space up   C down   F exit   V camera"
			"plane": return "Shift/Ctrl throttle   S pull up   W nose down   A/D roll   Q/E rudder   Space brake   F bail out"
			"boat": return "W/S throttle   A/D steer   F exit   RMB aim   H horn"
		return "W/S drive   A/D steer   Space handbrake   F exit   RMB aim   H horn   L lights   N radio" + ("   Q siren" if veh.is_emergency else "") + ("   K roof" if veh.parts.has("Roof") else "")
	if p.st == p.St.SWIM:
		return "WASD swim   Space up   C dive   Shift fast"
	if p.st == p.St.CHUTE:
		return "A/D steer   W dive   S flare   F cut away"
	if p.in_cover:
		return "A/D move along cover   RMB peek & aim   LMB blind fire   Q leave cover"
	return ""


class Stars:
	extends Control

	func _draw() -> void:
		var w: Node = G.wanted
		var lvl: int = w.level if w else 0
		if lvl == 0 and (w == null or w.pending.is_empty()):
			return
		var flash: bool = w != null and w.stars_flash() and int(Time.get_ticks_msec() / 280.0) % 2 == 0
		for i in 5:
			var c := Vector2(size.x - 24.0 - (4 - i) * 44.0, 22.0)
			var on := i < lvl
			var col := Color(1.0, 0.82, 0.2) if on else Color(1, 1, 1, 0.16)
			if on and flash:
				col = Color(1, 1, 1, 0.35)
			var pts := PackedVector2Array()
			for k in 10:
				var a := -PI * 0.5 + k * PI / 5.0
				var r := 19.0 if k % 2 == 0 else 8.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, col)
			if on:
				draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.2, 0.12, 0.0, 0.8), 1.5)
		if w != null and w.state == "search" and lvl > 0:
			var pr: float = w.escape_progress()
			draw_rect(Rect2(size.x - 220.0, 44.0, 216.0, 4.0), Color(0, 0, 0, 0.5))
			draw_rect(Rect2(size.x - 220.0, 44.0, 216.0 * pr, 4.0), Color(0.5, 0.9, 1.0))


class Crosshair:
	extends Control
	var hud: Node

	func _draw() -> void:
		var p: Node = G.player
		if p == null or p.dead or G.ui_blocking > 0:
			return
		var c := size * 0.5
		if G.cam and G.cam.scoped:
			var r := size.y * 0.46
			var col := Color(0, 0, 0, 1)
			draw_rect(Rect2(0, 0, c.x - r, size.y), col)
			draw_rect(Rect2(c.x + r, 0, size.x - c.x - r, size.y), col)
			draw_arc(c, r + 300.0, 0, TAU, 96, col, 600.0)
			draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0, 0, 0, 0.9), 1.5)
			draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0, 0, 0, 0.9), 1.5)
			for i in range(1, 5):
				draw_line(c + Vector2(-6, i * 28.0), c + Vector2(6, i * 28.0), Color(0, 0, 0, 0.9), 1.5)
			return
		var show: bool = p.aiming or p.last_shot < 1.0 or (p.vehicle == null and not p.melee_equipped())
		if p.vehicle != null and not p.aiming:
			show = false
		if show:
			var gap := 7.0 + (10.0 if not p.aiming else 0.0) + clampf((1.0 - p.last_shot * 4.0), 0.0, 1.0) * 8.0
			var col2 := Color(1, 1, 1, 0.9)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_line(c + d * gap, c + d * (gap + 9.0), Color(0, 0, 0, 0.6), 4.0)
				draw_line(c + d * gap, c + d * (gap + 9.0), col2, 2.0)
			draw_circle(c, 1.6, col2)
		if hud._hit > 0.0:
			var hc := Color(1.0, 0.25, 0.2) if hud._hit_kill else Color(1, 1, 1)
			for d2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + d2 * 7.0, c + d2 * 15.0, hc, 2.5)
		if hud._dmg > 0.02:
			var a: float = hud._dmg_dir
			var dirv := Vector2(sin(a), -cos(a))
			var base := c + dirv * 150.0
			var side := Vector2(-dirv.y, dirv.x)
			draw_colored_polygon(PackedVector2Array([base + dirv * 30.0, base + side * 34.0, base - side * 34.0]), Color(1, 0.15, 0.1, clampf(hud._dmg, 0.0, 0.85)))


class MapView:
	extends Control
	var hud: Node
	var mini := false
	var zoom := 1.0

	func _ready() -> void:
		clip_contents = true

	func _gui_input(ev: InputEvent) -> void:
		if mini:
			return
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_LEFT:
				hud.set_waypoint(_to_world(ev.position))
			elif ev.button_index == MOUSE_BUTTON_RIGHT:
				hud.set_waypoint(null)

	func _scale() -> float:
		return (size.x / 150.0) if mini else (minf(size.x, size.y) / 700.0)

	func _to_world(p: Vector2) -> Vector3:
		var s := _scale()
		var c := size * 0.5
		return Vector3((p.x - c.x) / s, 0.0, (p.y - c.y) / s + 10.0)

	func _draw() -> void:
		var pl: Node = G.player
		if pl == null:
			return
		var s := _scale()
		var c := size * 0.5
		var pp: Vector3 = pl.global_position_now()
		var rot := 0.0
		var origin := Vector3(0, 0, 10)
		if mini:
			origin = pp
			rot = G.cam.yaw if G.cam else 0.0
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.10, 0.13, 0.88))
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.10, 0.13, 0.95))
		var xf := Transform2D(rot, Vector2.ZERO)
		var f := func(w: Vector3) -> Vector2: return c + xf * (Vector2(w.x - origin.x, w.z - origin.z) * s)
		var clip_r := size.x * 0.5 - 2.0
		var L := WorldLayout
		# water + land
		if not mini:
			draw_rect(Rect2(f.call(Vector3(-340, 0, 186)), Vector2(680, 160) * s), Color(0.10, 0.30, 0.42))
			draw_rect(Rect2(f.call(Vector3(-300, 0, -300)), Vector2(600, 486) * s), Color(0.13, 0.17, 0.15))
		# blocks
		var bcol := {"res": Color(0.24, 0.33, 0.24), "apt": Color(0.27, 0.33, 0.28), "safe": Color(0.24, 0.33, 0.24), "beachres": Color(0.3, 0.34, 0.25),
			"park": Color(0.2, 0.42, 0.22), "towers": Color(0.3, 0.33, 0.4), "hotel": Color(0.36, 0.33, 0.3), "civic": Color(0.3, 0.32, 0.36),
			"hospital": Color(0.34, 0.3, 0.32), "shops": Color(0.36, 0.32, 0.28), "gas": Color(0.32, 0.3, 0.26), "ind": Color(0.28, 0.27, 0.26),
			"yard": Color(0.28, 0.27, 0.26), "docks": Color(0.26, 0.27, 0.29)}
		for bj in 4:
			for bi in 6:
				var r := L.block_rect(bi, bj)
				var pts := PackedVector2Array([f.call(Vector3(r.position.x, 0, r.position.y)), f.call(Vector3(r.end.x, 0, r.position.y)),
					f.call(Vector3(r.end.x, 0, r.end.y)), f.call(Vector3(r.position.x, 0, r.end.y))])
				if mini and (pts[0] - c).length() > clip_r * 1.9:
					continue
				draw_colored_polygon(pts, bcol[L.BLOCKS[bj][bi]])
		# roads
		var rc := Color(0.55, 0.58, 0.62)
		for i in L.NX:
			draw_line(f.call(Vector3(L.VX[i], 0, L.HZ[0])), f.call(Vector3(L.VX[i], 0, L.HZ[L.NZ - 1])), rc, L.v_hw(i) * 2.0 * s * 0.8)
		for j in L.NZ:
			draw_line(f.call(Vector3(L.VX[0], 0, L.HZ[j])), f.call(Vector3(L.VX[L.NX - 1], 0, L.HZ[j])), rc, L.h_hw(j) * 2.0 * s * 0.8)
		draw_line(f.call(Vector3(L.RUNWAY.x0, 0, L.RUNWAY.z)), f.call(Vector3(L.RUNWAY.x1, 0, L.RUNWAY.z)), Color(0.42, 0.44, 0.48), 30.0 * s)
		draw_line(f.call(Vector3(-40, 0, 184)), f.call(Vector3(-40, 0, 264)), Color(0.6, 0.45, 0.28), 5.0 * s)
		for px in [110.0, 170.0, 230.0]:
			draw_line(f.call(Vector3(px, 0, 194)), f.call(Vector3(px, 0, 242)), Color(0.6, 0.45, 0.28), 5.0 * s)
		for k in L.HILL_PATH.size() - 1:
			draw_line(f.call(Vector3(L.HILL_PATH[k].x, 0, L.HILL_PATH[k].y)), f.call(Vector3(L.HILL_PATH[k + 1].x, 0, L.HILL_PATH[k + 1].y)), Color(0.5, 0.42, 0.3), 5.0 * s)
		# rail loop
		if G.world and G.world.spawns.has("rail"):
			var rp: PackedVector3Array = G.world.spawns.rail.points
			var prev := f.call(rp[rp.size() - 1]) as Vector2
			for k in range(0, rp.size(), 4):
				var cur := f.call(rp[k]) as Vector2
				draw_line(prev, cur, Color(0.85, 0.85, 0.9, 0.55), 1.5)
				prev = cur
		# GPS route
		if hud.route.size() >= 2:
			var rpts := PackedVector2Array()
			for wp in hud.route:
				rpts.append(f.call(wp))
			draw_polyline(rpts, Color(0.75, 0.35, 1.0, 0.95), maxf(3.0, 5.0 * s), true)
		# wanted search area
		var w: Node = G.wanted
		if w != null and w.level > 0:
			var sc := f.call(w.last_known) as Vector2
			var col := Color(1, 0.2, 0.2, 0.16) if w.state == "pursuit" else Color(0.3, 0.5, 1.0, 0.18 + 0.08 * sin(Time.get_ticks_msec() * 0.006))
			draw_circle(sc, w.search_radius() * s, col)
		# POIs
		var font := get_theme_default_font()
		if G.world:
			for id in G.world.pois.keys():
				var poi: Dictionary = G.world.pois[id]
				var sp := f.call(poi.pos) as Vector2
				if mini:
					var off := sp - c
					if off.length() > clip_r - 9.0:
						if id in ["safehouse", "hospital", "modshop", "gunshop"]:
							sp = c + off.normalized() * (clip_r - 9.0)
						else:
							continue
				var ic: Array = hud.ICONS.get(poi.icon, ["?", Color.WHITE])
				draw_circle(sp, 9.0 if mini else 11.0, Color(0.03, 0.04, 0.06, 0.9))
				draw_arc(sp, 9.0 if mini else 11.0, 0, TAU, 20, ic[1], 1.5)
				draw_string(font, sp + Vector2(-5.0, 5.0), ic[0], HORIZONTAL_ALIGNMENT_CENTER, 10, 13, ic[1])
				if not mini:
					draw_string(font, sp + Vector2(14.0, 5.0), poi.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.75))
		# police blips + vision cones
		var blink := int(Time.get_ticks_msec() / 250.0) % 2 == 0
		for v in get_tree().get_nodes_in_group("vehicles"):
			var veh := v as Vehicle
			if veh == null or veh.dead:
				continue
			var vp := f.call(veh.global_position) as Vector2
			if mini and (vp - c).length() > clip_r - 4.0:
				continue
			if veh.def.get("emergency", "") == "police" and (veh.driver != null or veh.siren) and not veh.has_player():
				draw_circle(vp, 5.0, Color(1, 0.2, 0.2) if blink else Color(0.25, 0.45, 1.0))
				if w != null and w.level > 0 and w.state == "search":
					var hd := xf * Vector2(-veh.global_transform.basis.z.x, -veh.global_transform.basis.z.z)
					var cone := PackedVector2Array([vp, vp + hd.rotated(0.45) * 34.0 * s, vp + hd.rotated(-0.45) * 34.0 * s])
					draw_colored_polygon(cone, Color(0.4, 0.6, 1.0, 0.22))
			elif veh == pl.last_vehicle and not veh.has_player():
				draw_circle(vp, 3.5, Color(0.6, 1.0, 0.6))
		if w != null and w.level > 0 and G.peds:
			for n in G.peds.npcs:
				if is_instance_valid(n) and n.is_police and not n.dead and n.vehicle == null:
					var np := f.call(n.global_position_now()) as Vector2
					if not mini or (np - c).length() < clip_r - 4.0:
						draw_circle(np, 3.5, Color(0.35, 0.55, 1.0) if blink else Color(1, 0.3, 0.3))
		# waypoint
		if hud.waypoint != null:
			var wp2 := f.call(hud.waypoint) as Vector2
			if mini and (wp2 - c).length() > clip_r - 8.0:
				wp2 = c + (wp2 - c).normalized() * (clip_r - 8.0)
			draw_circle(wp2, 7.0, Color(0.75, 0.35, 1.0))
			draw_circle(wp2, 3.0, Color.WHITE)
		# player arrow
		var ppos := f.call(pp) as Vector2
		var yaw: float = pl.vehicle.rotation.y if pl.vehicle != null else pl.rotation.y
		var dirv := xf * Vector2(-sin(yaw), -cos(yaw))
		var sd := Vector2(-dirv.y, dirv.x)
		draw_colored_polygon(PackedVector2Array([ppos + dirv * 11.0, ppos - dirv * 7.0 + sd * 7.0, ppos - dirv * 3.0, ppos - dirv * 7.0 - sd * 7.0]), Color.WHITE)
		if mini:
			draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), Color(1, 1, 1, 0.35), false, 2.0)
			var nd := xf * Vector2(0, -1)
			draw_string(font, c + nd * (clip_r - 12.0) + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_CENTER, 10, 14, UIKit.CORAL)
