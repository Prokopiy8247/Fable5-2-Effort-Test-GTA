class_name MapScreen
extends Control
## Full-screen city map: pan (drag / WASD), zoom (wheel), location legend, district names,
## click to set a GPS waypoint (right click clears it). North is up.

signal closed()

var zoom := 1.25
var centre := Vector2.ZERO          # world (x, z) at the middle of the screen
var font: Font
var _drag := false
var _hover_name := ""
var _icons: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	visible = false

func open() -> void:
	zoom = clampf(size.y / 640.0, 0.8, 2.2)
	centre = Vector2(0.0, 10.0)
	visible = true
	queue_redraw()

func close() -> void:
	visible = false
	closed.emit()

func _xf() -> Transform2D:
	var xf := Transform2D(0.0, Vector2.ZERO).scaled(Vector2(zoom, zoom))
	xf.origin = size * 0.5 - xf.basis_xform(centre)
	return xf

func handle_input(event: InputEvent) -> bool:
	if not visible:
		return false
	if event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE or k == KEY_M or k == KEY_BACKSPACE:
			close()
			return true
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom = minf(zoom * 1.15, 6.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom = maxf(zoom / 1.15, 0.6)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var wp := _xf().affine_inverse() * mb.position
			# snap to a location icon when one is clicked
			for ic in _icons:
				if (ic[0] as Vector2).distance_to(mb.position) < 16.0:
					var loc: Dictionary = Game.world.city.locations[ic[1]]
					var lp: Vector3 = loc["pos"]
					wp = Vector2(lp.x, lp.z)
					break
			if Game.hud != null:
				Game.hud.set_waypoint(Vector3(wp.x, maxf(Game.ground_y(wp.x, wp.y), 0.0), wp.y))
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if Game.hud != null:
				Game.hud.set_waypoint(null)
		queue_redraw()
		return true
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag or (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and mm.relative.length() > 0.0 and Input.is_key_pressed(KEY_SHIFT):
			centre -= mm.relative / zoom
		_hover_name = ""
		for ic in _icons:
			if (ic[0] as Vector2).distance_to(mm.position) < 16.0:
				var loc2: Dictionary = Game.world.city.locations[ic[1]]
				_hover_name = String(MapDraw.ICON_NAMES.get(String(loc2.get("id", ic[1])), ""))
		queue_redraw()
		return true
	return true

func _process(delta: float) -> void:
	if not visible:
		return
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.y += 1.0
	if pan != Vector2.ZERO:
		centre += pan * 260.0 / zoom * delta / maxf(Engine.time_scale, 0.05)
		centre = centre.clamp(Vector2(-320, -320), Vector2(320, 340))
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), MapDraw.C_WATER)
	var xf := _xf()
	MapDraw.draw(self, xf, true, font)
	var world: World = Game.world
	# district names
	if world != null and world.layout != null:
		for zn in world.layout.zones:
			var r: Rect2 = zn["rect"]
			var c := r.get_center().clamp(Vector2(-285, -285), Vector2(285, 262))
			var sp := xf * c
			var nm := String(zn["name"]).to_upper()
			var ts := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
			draw_string(font, sp - Vector2(ts.x * 0.5, 0.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.42))
	var hud: HUD = Game.hud
	if hud != null and hud.route.size() >= 2:
		var line := PackedVector2Array()
		for rp in hud.route:
			line.append(xf * Vector2(rp.x, rp.z))
		draw_polyline(line, HUD.PINK, 4.0, true)
	_icons = MapDraw.draw_icons(self, xf, font, 17.0)
	if hud != null and hud.waypoint != null:
		var w3: Vector3 = hud.waypoint
		var wp := xf * Vector2(w3.x, w3.z)
		draw_circle(wp, 9.0, HUD.PINK)
		draw_circle(wp, 4.0, Color.WHITE)
	# wanted search area + police blips
	if Game.wanted != null and Game.wanted.level > 0:
		var w: Node = Game.wanted
		if w.state == 2:
			var lk: Vector3 = w.last_known
			draw_circle(xf * Vector2(lk.x, lk.z), w.search_radius * zoom, Color(0.3, 0.5, 1.0, 0.2))
		for unit in get_tree().get_nodes_in_group(&"police_units"):
			var up: Vector3 = (unit as Node3D).global_position
			draw_circle(xf * Vector2(up.x, up.z), 5.0, Color(0.3, 0.5, 1.0))
	var p: Player = Game.player
	if p != null:
		var heading := p.face_yaw
		if p.vehicle != null and is_instance_valid(p.vehicle):
			heading = (p.vehicle as Node3D).global_rotation.y
		var c2 := xf * Vector2(p.global_position.x, p.global_position.z)
		var fwd := Vector2(-sin(heading), -cos(heading))
		var side := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([c2 + fwd * 13.0, c2 - fwd * 8.0 + side * 8.0, c2 - fwd * 4.0, c2 - fwd * 8.0 - side * 8.0]), Color.WHITE)
		draw_arc(c2, 17.0, 0.0, TAU, 28, HUD.ACCENT, 1.5)
	# frame: title, legend, hints
	draw_rect(Rect2(0, 0, size.x, 54.0), Color(0.03, 0.04, 0.06, 0.88))
	draw_string(font, Vector2(28, 36), "VESPER BAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	draw_string(font, Vector2(210, 36), Game.district_at(p.global_position) if p != null else "", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, HUD.ACCENT)
	var lw := 290.0
	var names: Array = []
	if world != null and world.city != null:
		for key in world.city.locations.keys():
			var lid := String(world.city.locations[key].get("id", key))
			if MapDraw.ICONS.has(lid) and not names.has(lid):
				names.append(lid)
	var lh := 24.0 * float(names.size()) + 46.0
	var lr := Rect2(size.x - lw - 20.0, 70.0, lw, lh)
	draw_rect(lr, Color(0.03, 0.04, 0.06, 0.82))
	draw_string(font, lr.position + Vector2(14, 24), "LEGEND", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HUD.ACCENT)
	var y := lr.position.y + 48.0
	for lid2 in names:
		var ic: Array = MapDraw.ICONS[lid2]
		draw_circle(Vector2(lr.position.x + 24.0, y - 5.0), 9.0, Color(0.05, 0.06, 0.08))
		draw_arc(Vector2(lr.position.x + 24.0, y - 5.0), 9.0, 0.0, TAU, 16, ic[1], 1.5)
		draw_string(font, Vector2(lr.position.x + 19.5, y), String(ic[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ic[1])
		draw_string(font, Vector2(lr.position.x + 44.0, y), String(MapDraw.ICON_NAMES.get(lid2, lid2)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.86, 0.9, 0.94))
		y += 24.0
	draw_rect(Rect2(0, size.y - 40.0, size.x, 40.0), Color(0.03, 0.04, 0.06, 0.88))
	draw_string(font, Vector2(28, size.y - 14.0), "Left click  set waypoint      Right click  clear      Wheel  zoom      WASD / middle drag  pan      M / Esc  close",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.76, 0.82))
	if _hover_name != "":
		var mp := get_local_mouse_position()
		var ts2 := font.get_string_size(_hover_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
		draw_rect(Rect2(mp + Vector2(14, -24), ts2 + Vector2(16, 10)), Color(0.03, 0.04, 0.06, 0.92))
		draw_string(font, mp + Vector2(22, -6), _hover_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
