extends UiScreen
## Full island map (north up). Drag / WASD to pan, wheel or + / - to zoom, hover for names,
## left click to set a waypoint (click it again or right click to clear). Shows the GPS route,
## the player, named places, district names and - while wanted - police units.
## UI.open_screen("map")   |   UI.open_screen("map", {"focus": "player", "zoom": 2.0})
## No mission markers: the only marker a player can place is the waypoint.

const PAUSES_GAME := true
const TIME_SCALE := 1.0
const LOCKS_INPUT := true
const SHOWS_MOUSE := true
const HIDES_HUD := true

const LEGEND_W := 470.0
const MAX_ZOOM := 6.0
const PAN_SPEED := 520.0           ## logical px per second with the keyboard
const CLICK_SLOP := 7.0

var data: UiMapData = null
var nav: UiNav = null

var _view: Control                 ## clipped map viewport
var _world: MinimapWorldLayer
var _over: UiCanvas
var _legend: UiCanvas
var _info: Label
var _zoom: float = 1.0             ## logical px per metre
var _min_zoom: float = 0.5
var _center: Vector2 = Vector2.ZERO  ## map-space point at the centre of the view
var _touched: bool = false          ## the user panned / zoomed (stop auto-fitting)
var _dragging: bool = false
var _drag_moved: float = 0.0
var _drag_button: int = 0
var _hover_pos: Vector2 = Vector2(-1, -1)
var _hover_text: String = ""
var _blink: float = 0.0
var _redraw_timer: float = 0.0
var _legend_items: Array[Dictionary] = []
var _open_args: Dictionary = {}
var _police: Array = []


func _init() -> void:
	super()
	backdrop_alpha = 0.86


func _ready() -> void:
	data = UI.map_data
	nav = UI.nav
	if data != null and (data.source != "world" or not data.has_map()):
		data.refresh()
	var margin := UiKit.margin(null, 56, 44, 56, 92)
	UiKit.fill(margin)
	add_child(margin)
	var row := UiKit.hbox(28)
	margin.add_child(row)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiStyle.box(Color(MinimapWorldLayer.SEA, 0.98), UiStyle.RADIUS, UiStyle.LINE_STRONG, 3, 18, 6, 6))
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(frame)
	_view = Control.new()
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.mouse_default_cursor_shape = Control.CURSOR_CROSS
	frame.add_child(_view)
	_world = MinimapWorldLayer.new()
	_world.detail = true
	_world.set_data(data)
	_view.add_child(_world)
	_over = UiCanvas.new(_draw_overlay)
	_view.add_child(_over)
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.gui_input.connect(_on_view_input)
	_view.resized.connect(_on_view_resized)
	_view.mouse_exited.connect(_on_view_mouse_exit)

	var side := UiPanel.new(&"GlassPanel", 10)
	side.custom_minimum_size.x = LEGEND_W
	row.add_child(side)
	var head := UiKit.header("Map", "Halcyon Bay")
	side.add(head)
	_info = UiKit.paragraph("", &"SmallLabel", LEGEND_W - 60.0)
	side.add(_info)
	side.add(UiKit.separator())
	side.add(UiKit.label("LEGEND", &"SectionLabel"))
	_legend = UiCanvas.new(_draw_legend)
	_legend.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_legend.custom_minimum_size = Vector2(LEGEND_W - 60.0, 300.0)
	side.add(_legend)
	var clear_btn := UiKit.button("Clear waypoint", _clear_waypoint)
	clear_btn.focus_mode = Control.FOCUS_NONE
	side.add(clear_btn)

	var hints := UiKeyHints.new([
		{"key": "LMB", "text": "Set waypoint"}, {"key": "RMB", "text": "Clear"}, {"key": "Drag", "text": "Pan"},
		{"key": "Wheel", "text": "Zoom"}, {"action": "pause", "text": "Close"},
	])
	add_child(hints)
	hints.anchor_left = 0.0
	hints.anchor_right = 1.0
	hints.anchor_top = 1.0
	hints.anchor_bottom = 1.0
	hints.offset_left = 60.0
	hints.offset_right = -60.0
	hints.offset_top = -78.0
	hints.offset_bottom = -32.0
	_build_legend()
	_refresh_info()


func open(args: Dictionary) -> void:
	_open_args = args
	_touched = false
	_fit.call_deferred()


func regain_focus() -> void:
	pass


# --- view transform --------------------------------------------------------------------------------

func to_view(p: Vector2) -> Vector2:
	return (p - _center) * _zoom + _view.size * 0.5


func to_map(v: Vector2) -> Vector2:
	return (v - _view.size * 0.5) / maxf(_zoom, 0.001) + _center


func get_zoom() -> float:
	return _zoom


func get_center() -> Vector2:
	return _center


## Centre the view on a map-space point (x = world X, y = world Z) at an optional zoom.
func focus_on(p: Vector2, zoom: float = -1.0) -> void:
	_touched = true
	if zoom > 0.0:
		_zoom = clampf(zoom, _min_zoom, MAX_ZOOM)
	_center = p
	_apply()


## Set the waypoint from a view-space position (what a left click does). Returns the world position.
func click_at(view_pos: Vector2) -> Vector3:
	var m := to_map(view_pos)
	if nav != null and nav.has_waypoint:
		var wv := to_view(Vector2(nav.waypoint.x, nav.waypoint.z))
		if wv.distance_to(view_pos) < 18.0:
			_clear_waypoint()
			return Vector3.INF
	var place := data.place_at(m, 18.0 / maxf(_zoom, 0.001), _zoom > 1.6) if data != null else {}
	if not place.is_empty():
		m = place["pos"]
	var pos := Vector3(m.x, Game.ground_height(m.x, m.y), m.y)
	if nav != null:
		nav.set_waypoint(pos)
	UiKit.sfx("ui_click")
	_refresh_info()
	_over.queue_redraw()
	return pos


func _fit() -> void:
	if _view == null or _view.size.x < 10.0:
		return
	var b: Rect2 = data.bounds if data != null else Rect2(-300, -300, 600, 600)
	_min_zoom = minf(_view.size.x / b.size.x, _view.size.y / b.size.y) * 0.8
	if not _touched:
		_zoom = _min_zoom / 0.8 * 0.96
		_center = b.get_center()
		if str(_open_args.get("focus", "")) == "player" and Game.has_player():
			var p := Game.get_player_position()
			_center = Vector2(p.x, p.z)
			_zoom = maxf(_zoom, 2.0)
		if _open_args.has("zoom"):
			_zoom = clampf(float(_open_args["zoom"]), _min_zoom, MAX_ZOOM)
		if _open_args.has("center"):
			_center = UiMapData.to_v2(_open_args["center"])
	_apply()


func _apply() -> void:
	var b: Rect2 = data.bounds if data != null else Rect2(-300, -300, 600, 600)
	_zoom = clampf(_zoom, _min_zoom, MAX_ZOOM)
	_center.x = clampf(_center.x, b.position.x, b.end.x)
	_center.y = clampf(_center.y, b.position.y, b.end.y)
	_world.scale = Vector2(_zoom, _zoom)
	_world.position = _view.size * 0.5 - _center * _zoom
	_over.queue_redraw()


func _on_view_resized() -> void:
	_fit()


func _zoom_at(view_pos: Vector2, factor: float) -> void:
	_touched = true
	var before := to_map(view_pos)
	_zoom = clampf(_zoom * factor, _min_zoom, MAX_ZOOM)
	_center = before - (view_pos - _view.size * 0.5) / _zoom
	_apply()


# --- input -----------------------------------------------------------------------------------------

func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(mb.position, 1.18)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(mb.position, 1.0 / 1.18)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_dragging = true
					_drag_moved = 0.0
					_drag_button = mb.button_index
				elif _dragging and mb.button_index == _drag_button:
					_dragging = false
					if _drag_moved < CLICK_SLOP:
						if mb.button_index == MOUSE_BUTTON_LEFT:
							click_at(mb.position)
						elif mb.button_index == MOUSE_BUTTON_RIGHT:
							_clear_waypoint()
		_view.accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_drag_moved += mm.relative.length()
			if _drag_moved >= CLICK_SLOP:
				_touched = true
				_center -= mm.relative / maxf(_zoom, 0.001)
				_apply()
		_hover_pos = mm.position
		_update_hover()


func _on_view_mouse_exit() -> void:
	_hover_pos = Vector2(-1, -1)
	_hover_text = ""
	_dragging = false
	_over.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).physical_keycode:
			KEY_EQUAL, KEY_KP_ADD:
				_zoom_at(_view.size * 0.5, 1.25)
				get_viewport().set_input_as_handled()
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom_at(_view.size * 0.5, 0.8)
				get_viewport().set_input_as_handled()
			KEY_SPACE:
				if Game.has_player():
					var p := Game.get_player_position()
					focus_on(Vector2(p.x, p.z), maxf(_zoom, 2.0))
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var pan := Vector2(Input.get_axis(&"ui_left", &"ui_right"), Input.get_axis(&"ui_up", &"ui_down"))
	if pan.length_squared() > 0.01 and not has_dialog():
		_touched = true
		_center += pan * PAN_SPEED * delta / maxf(_zoom, 0.001)
		_apply()
	_blink += delta
	_redraw_timer += delta
	if _redraw_timer >= 0.2:
		_redraw_timer = 0.0
		_police = get_tree().get_nodes_in_group("police")
		_world.check_version()
		_refresh_info()
		_over.queue_redraw()


func _clear_waypoint() -> void:
	if nav != null and nav.has_waypoint:
		nav.clear_waypoint()
		UiKit.sfx("ui_close")
	_refresh_info()
	_over.queue_redraw()


func _update_hover() -> void:
	var txt := ""
	if data != null and _hover_pos.x >= 0.0:
		var m := to_map(_hover_pos)
		var place := data.place_at(m, 16.0 / maxf(_zoom, 0.001), _zoom > 1.6)
		if not place.is_empty():
			txt = str(place["name"])
		else:
			txt = _road_at(m)
	if txt != _hover_text:
		_hover_text = txt
	_over.queue_redraw()


func _road_at(m: Vector2) -> String:
	var best := ""
	var best_d := 1e9
	for road in data.roads:
		var road_name := str(road["name"])
		if road_name == "":
			continue
		var pts: PackedVector2Array = road["pts"]
		var limit := float(road["width"]) * 0.5 + 3.0 / maxf(_zoom, 0.001)
		for i in pts.size() - 1:
			var d := Geometry2D.get_closest_point_to_segment(m, pts[i], pts[i + 1]).distance_to(m)
			if d < limit and d < best_d:
				best_d = d
				best = road_name
	return best


func _refresh_info() -> void:
	if _info == null:
		return
	var txt := ""
	if data == null or not data.has_map():
		txt = "Map data is not available yet. The radar still tracks you and your waypoint."
	elif nav != null and nav.has_waypoint:
		txt = "Waypoint set  -  %d m by road." % int(nav.route_length)
	else:
		txt = "Click anywhere to drop a waypoint. The GPS route follows the road network."
	if txt != _info.text:
		_info.text = txt


# --- legend ----------------------------------------------------------------------------------------

func _build_legend() -> void:
	_legend_items.clear()
	_legend_items.append({"icon": &"arrow", "color": UiStyle.SUN, "name": "You"})
	_legend_items.append({"icon": &"pin", "color": UiStyle.CORAL, "name": "Waypoint + route"})
	_legend_items.append({"icon": &"circle", "color": UiStyle.POLICE_BLUE, "name": "Police"})
	var seen: Dictionary = {}
	if data != null:
		for pl in data.places:
			var key := str(pl["icon"])
			if seen.has(key):
				continue
			seen[key] = true
			var nm := str(pl["name"])
			if bool(pl["minor"]) and (nm.begins_with("Tram") or nm.begins_with("Stunt") or nm.contains("Helipad")):
				nm = nm.trim_suffix(" 1")
			_legend_items.append({"icon": pl["icon"], "color": pl["color"], "name": nm})
	if _legend != null:
		_legend.queue_redraw()


func _draw_legend(c: UiCanvas) -> void:
	var body := UiStyle.font(&"body")
	var n := _legend_items.size()
	if n == 0:
		return
	var two_cols := n > 12
	var rows := int(ceil(n / 2.0)) if two_cols else n
	var row_h := clampf(c.size.y / float(maxi(rows, 1)), 26.0, 40.0)
	var col_w := c.size.x * (0.5 if two_cols else 1.0)
	for i in n:
		@warning_ignore("integer_division")
		var col := (i / rows) if two_cols else 0
		var r := (i % rows) if two_cols else i
		var it: Dictionary = _legend_items[i]
		var y := r * row_h + row_h * 0.5
		var x := col * col_w
		c.draw_circle(Vector2(x + 16.0, y), 15.0, Color(UiStyle.NAVY_DEEP, 0.9), true, -1.0, true)
		UiIcons.draw(c, it["icon"], Vector2(x + 16.0, y), 19.0, it["color"])
		var fs := UiStyle.FS_TINY if two_cols else UiStyle.FS_SMALL
		var nm := str(it["name"])
		var avail := col_w - 48.0
		if UiStyle.text_width(body, nm, fs) > avail:
			while nm.length() > 3 and UiStyle.text_width(body, nm + "...", fs) > avail:
				nm = nm.substr(0, nm.length() - 1)
			nm = nm.strip_edges() + "..."
		UiStyle.text_in(c, body, Rect2(x + 42.0, y - row_h * 0.5, avail, row_h), nm, fs, UiStyle.TEXT)


# --- map overlay (view space) ----------------------------------------------------------------------

func _draw_overlay(c: UiCanvas) -> void:
	var vs := _view.size
	var head := UiStyle.font(&"head")
	var body := UiStyle.font(&"bold")
	# the player marker wins over district names: a label under it fades out
	var me_v := Vector2(-1.0e6, -1.0e6)
	if Game.has_player():
		var me3 := Game.get_player_position()
		me_v = to_view(Vector2(me3.x, me3.z))
	if data != null:
		# district names
		for lab in data.labels:
			var lp := to_view(lab["pos"])
			if lp.x < -200.0 or lp.y < -40.0 or lp.x > vs.x + 200.0 or lp.y > vs.y + 40.0:
				continue
			if str(lab["kind"]) != "district":
				# area names from the world (plazas, parks ...): small, only when zoomed in
				if _zoom > 1.5:
					var st := str(lab["text"])
					var sw := UiStyle.text_width(body, st, UiStyle.FS_TINY)
					UiStyle.text_outlined(c, body, lp + Vector2(-sw * 0.5, 6.0), st, UiStyle.FS_TINY, Color(UiStyle.CREAM, 0.85), 5, Color(0.02, 0.06, 0.11, 0.8))
				continue
			var txt := str(lab["text"]).to_upper()
			var fs := UiStyle.FS_SMALL if _zoom < 1.5 else UiStyle.FS_BODY
			var tw := UiStyle.text_width(head, txt, fs)
			var under_me := Rect2(lp + Vector2(-tw * 0.5, -fs * 0.65), Vector2(tw, fs)).grow(24.0).has_point(me_v)
			var la := 0.28 if under_me else 0.9
			UiStyle.text_outlined(c, head, lp + Vector2(-tw * 0.5, fs * 0.35), txt, fs, Color(UiStyle.CREAM, la), 6, Color(0.02, 0.06, 0.11, 0.8 * la))
	# GPS route
	if nav != null and nav.has_waypoint and nav.route.size() >= 2:
		var pts := PackedVector2Array()
		pts.resize(nav.route.size())
		for i in nav.route.size():
			pts[i] = to_view(nav.route[i])
		c.draw_polyline(pts, Color(UiStyle.NAVY_DEEP, 0.9), 9.0, true)
		c.draw_polyline(pts, UiStyle.CORAL, 5.0, true)
	if data != null:
		for pl in data.places:
			if bool(pl["minor"]) and _zoom <= 1.6:
				continue
			var pv := to_view(pl["pos"])
			if pv.x < -20.0 or pv.y < -20.0 or pv.x > vs.x + 20.0 or pv.y > vs.y + 20.0:
				continue
			var r := 17.0 if not bool(pl["minor"]) else 13.0
			var pc: Color = pl["color"]
			c.draw_circle(pv, r, Color(UiStyle.NAVY_DEEP, 0.92), true, -1.0, true)
			c.draw_arc(pv, r, 0.0, TAU, 28, Color(pc, 0.8), 2.0, true)
			UiIcons.draw(c, pl["icon"], pv, r * 1.25, pc)
	# police (only meaningful while wanted)
	if Wanted.level > 0:
		var blink := int(_blink * 4.0) % 2 == 0
		var helis: Array[int] = []
		for n in _police:
			if not is_instance_valid(n) or not (n is Node3D) or not (n as Node3D).is_inside_tree():
				continue
			var node := n as Node3D
			var cv: Variant = node.get(&"current_vehicle")
			if not Minimap.is_heli(node) and cv is Node3D and is_instance_valid(cv) and Minimap.is_heli(cv as Node3D):
				node = cv as Node3D
			var g := node.global_position
			var gv := to_view(Vector2(g.x, g.z))
			var pcol: Color = UiStyle.POLICE_RED if blink else UiStyle.POLICE_BLUE
			if Minimap.is_heli(node):
				if helis.has(node.get_instance_id()):
					continue
				helis.append(node.get_instance_id())
				c.draw_circle(gv, 18.0, Color(UiStyle.NAVY_DEEP, 0.9), true, -1.0, true)
				UiIcons.draw(c, &"heli", gv, 26.0, pcol)
				continue
			c.draw_circle(gv, 8.0, Color(0, 0, 0, 0.6), true, -1.0, true)
			c.draw_circle(gv, 6.0, pcol, true, -1.0, true)
		if Wanted.state == Wanted.State.SEARCH:
			var sc3 := Minimap.search_center()
			var lk := to_view(Vector2(sc3.x, sc3.z))
			c.draw_circle(lk, Wanted.search_radius * _zoom, Color(UiStyle.CORAL_HOT, 0.15), true, -1.0, true)
			c.draw_arc(lk, Wanted.search_radius * _zoom, 0.0, TAU, 64, Color(UiStyle.CORAL_HOT, 0.85), 2.5, true)
	# waypoint
	if nav != null and nav.has_waypoint:
		var wv := to_view(Vector2(nav.waypoint.x, nav.waypoint.z))
		var bob := 3.0 * sin(_blink * 4.0)
		UiIcons.draw(c, &"pin", wv + Vector2(0, -20.0 + bob), 44.0, UiStyle.NAVY_DEEP)
		UiIcons.draw(c, &"pin", wv + Vector2(0, -20.0 + bob), 36.0, UiStyle.CORAL)
	# player
	if Game.has_player():
		var p3 := Game.get_player_position()
		var pv2 := to_view(Vector2(p3.x, p3.z))
		var node: Node3D = Game.get_player_vehicle()
		if node == null:
			node = Game.player
		var fwd := -node.global_transform.basis.z
		var heading := atan2(-fwd.x, -fwd.z)
		c.draw_circle(pv2, 22.0, Color(UiStyle.SUN, 0.16 + 0.08 * sin(_blink * 5.0)), true, -1.0, true)
		c.draw_set_transform(pv2, -heading, Vector2.ONE)
		UiIcons.draw(c, &"arrow", Vector2.ZERO, 34.0, UiStyle.NAVY_DEEP)
		UiIcons.draw(c, &"arrow", Vector2(0, 0.5), 24.0, UiStyle.SUN)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# compass + scale bar
	var nc := Vector2(vs.x - 44.0, 44.0)
	c.draw_circle(nc, 26.0, Color(UiStyle.NAVY_DEEP, 0.9), true, -1.0, true)
	c.draw_arc(nc, 26.0, 0.0, TAU, 32, UiStyle.LINE_STRONG, 2.0, true)
	UiIcons.draw(c, &"north", nc + Vector2(0, 5.0), 24.0, UiStyle.CORAL)
	UiIcons.draw(c, &"chev_up", nc + Vector2(0, -15.0), 12.0, UiStyle.CORAL)
	var metres := 100.0
	if _zoom * metres > 260.0:
		metres = 50.0
	elif _zoom * metres < 70.0:
		metres = 200.0
	var bar_w := metres * _zoom
	var bo := Vector2(24.0, vs.y - 30.0)
	var scale_txt := "%d m" % int(metres)
	var stw := UiStyle.text_width(body, scale_txt, UiStyle.FS_TINY)
	c.draw_style_box(UiStyle.cached_box(&"solid"), Rect2(bo + Vector2(-12.0, -17.0), Vector2(bar_w + stw + 38.0, 34.0)))
	c.draw_line(bo, bo + Vector2(bar_w, 0), UiStyle.CREAM, 3.0)
	c.draw_line(bo + Vector2(0, -7), bo + Vector2(0, 7), UiStyle.CREAM, 3.0)
	c.draw_line(bo + Vector2(bar_w, -7), bo + Vector2(bar_w, 7), UiStyle.CREAM, 3.0)
	UiStyle.text(c, body, bo + Vector2(bar_w + 12.0, 7.0), scale_txt, UiStyle.FS_TINY, UiStyle.CREAM)
	# hover tooltip
	if _hover_text != "" and _hover_pos.x >= 0.0:
		var tw2 := UiStyle.text_width(body, _hover_text, UiStyle.FS_SMALL) + 28.0
		var tip := Rect2(_hover_pos + Vector2(18.0, -46.0), Vector2(tw2, 38.0))
		if tip.end.x > vs.x - 6.0:
			tip.position.x = _hover_pos.x - 18.0 - tw2
		if tip.position.y < 6.0:
			tip.position.y = _hover_pos.y + 22.0
		c.draw_style_box(UiStyle.cached_box(&"solid"), tip)
		UiStyle.text_in(c, body, tip, _hover_text, UiStyle.FS_SMALL, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
