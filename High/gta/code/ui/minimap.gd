class_name MiniMap
extends Control
## Custom-drawn radar / full map: roads, coast, districts, POIs, police, search area, waypoint and GPS route.

signal map_clicked(world_pos: Vector3)

var big := false
var scale_px := 1.15         # pixels per metre
var route: PackedVector3Array = PackedVector3Array()
var _route_t := 0.0
var _font: Font

const ICON_COL := {"home": Color("5fd38a"), "police": Color("5a9bff"), "hospital": Color("ff6b6b"), "gun": Color("ffb347"),
	"wrench": Color("ff7ad9"), "gas": Color("ffa24d"), "shirt": Color("c9a6ff"), "scissors": Color("c9a6ff"), "food": Color("ffe07a"),
	"plane": Color("9ad7ff"), "heli": Color("9ad7ff"), "boat": Color("6fe3e0"), "beach": Color("ffe8a3"), "view": Color("b8e986"),
	"tree": Color("7fd36b"), "target": Color("ff8a65"), "parking": Color("aab4c8"), "train": Color("6fe3e0")}
const ICON_CHR := {"home": "H", "police": "P", "hospital": "+", "gun": "G", "wrench": "M", "gas": "F", "shirt": "C", "scissors": "B",
	"food": "E", "plane": "A", "heli": "h", "boat": "~", "beach": "b", "view": "^", "tree": "t", "target": "R", "parking": "p", "train": "S"}


func _ready() -> void:
	clip_contents = true
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP if big else Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_route_t -= delta
	if _route_t <= 0.0:
		_route_t = 1.0
		route = PackedVector3Array()
		if Game.waypoint != null and Game.player:
			var wp: Vector3 = Game.waypoint
			if wp.distance_to(Game.player.global_position) < 14.0:
				Game.waypoint = null
				Game.say("Destination reached", Color(0.6, 1.0, 0.6))
			else:
				route = City.route(Game.player.global_position, wp)
				route.insert(0, Game.player.global_position)
				route.append(wp)
	queue_redraw()


func _to_map(w: Vector3, centre: Vector3, yaw: float) -> Vector2:
	var dx := (w.x - centre.x) * scale_px
	var dz := (w.z - centre.z) * scale_px
	if big:
		return size * 0.5 + Vector2(dx, dz)
	var c := cos(yaw)
	var s := sin(yaw)
	return size * 0.5 + Vector2(dx * c - dz * s, dx * s + dz * c)


func _gui_input(ev: InputEvent) -> void:
	if big and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var m: Vector2 = (ev.position - size * 0.5) / scale_px
		map_clicked.emit(Vector3(m.x, 0, m.y))
	elif big and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		Game.waypoint = null


func _draw() -> void:
	var p = Game.player
	if p == null:
		return
	var centre: Vector3 = Vector3.ZERO if big else p.global_position
	var yaw: float = 0.0 if big else (Game.cam.yaw if Game.cam else 0.0)
	if big:
		scale_px = minf(size.x, size.y) / 700.0
	# sea + land
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.27, 0.36, 0.92))
	var land := PackedVector2Array()
	var pts := [Vector3(-300, 0, -300), Vector3(300, 0, -300), Vector3(300, 0, 208), Vector3(104, 0, 208)]
	for i in range(11):
		var x := 100.0 - i * 40.0
		pts.append(Vector3(x, 0, 200.0 + 3.0 * sin(x * 0.035)))
	pts.append(Vector3(-300, 0, 197))
	for w in pts:
		land.append(_to_map(w, centre, yaw))
	draw_colored_polygon(land, Color(0.2, 0.23, 0.22, 0.95))
	# district tints
	_poly([Vector3(-300, 0, -190), Vector3(-208, 0, -190), Vector3(-208, 0, 8), Vector3(-300, 0, 8)], Color(0.2, 0.36, 0.2), centre, yaw)
	_poly([Vector3(-195, 0, -85), Vector3(-105, 0, -85), Vector3(-105, 0, 5), Vector3(-195, 0, 5)], Color(0.22, 0.4, 0.22), centre, yaw)
	_poly([Vector3(-300, 0, -300), Vector3(300, 0, -300), Vector3(300, 0, -203), Vector3(-300, 0, -203)], Color(0.24, 0.3, 0.24), centre, yaw)
	_poly([Vector3(-205, 0, 188), Vector3(102, 0, 188), Vector3(102, 0, 197), Vector3(-205, 0, 197)], Color(0.6, 0.55, 0.38), centre, yaw)
	_line(Vector3(-282, 0, -272), Vector3(282, 0, -272), Color(0.36, 0.38, 0.42), 9.0 * scale_px, centre, yaw)
	# roads
	for s in City.segs:
		var a: Vector3 = City.nodes[s.a].pos
		var b: Vector3 = City.nodes[s.b].pos
		_line(a, b, Color(0.5, 0.52, 0.56), maxf(2.0, s.half * 1.7 * scale_px), centre, yaw)
	for sb in City.stubs():
		_line(sb.p0, sb.p1, Color(0.5, 0.52, 0.56), maxf(2.0, sb.half * 1.6 * scale_px), centre, yaw)
	_line(Vector3(60, 0, 190), Vector3(60, 0, 254), Color(0.55, 0.42, 0.28), 3.0, centre, yaw)
	_line(Vector3(-190, 0, 189.6), Vector3(90, 0, 189.6), Color(0.3, 0.8, 0.78, 0.7), 1.5, centre, yaw)
	# GPS route
	if route.size() > 1:
		for i in range(route.size() - 1):
			_line(route[i], route[i + 1], Color(0.75, 0.4, 1.0, 0.9), 3.0, centre, yaw)
	# wanted search area
	if Wanted.level > 0:
		var lk := _to_map(Wanted.last_known, centre, yaw)
		if Wanted.state == "search":
			draw_circle(lk, Wanted.search_radius() * scale_px, Color(1.0, 0.3, 0.25, 0.16))
			draw_arc(lk, Wanted.search_radius() * scale_px, 0, TAU, 40, Color(1.0, 0.35, 0.3, 0.7), 1.5)
	# POIs
	if Game.world:
		for poi in Game.world.pois:
			var mp := _to_map(poi.pos, centre, yaw)
			if not big:
				var d := mp - size * 0.5
				var lim := size.x * 0.5 - 9.0
				if absf(d.x) > lim or absf(d.y) > lim:
					continue
			var col: Color = ICON_COL.get(poi.icon, Color.WHITE)
			draw_circle(mp, 7.0 if big else 6.0, Color(0.05, 0.06, 0.08, 0.9))
			draw_circle(mp, 5.5 if big else 4.6, col)
			draw_string(_font, mp + Vector2(-3.5, 4.0), ICON_CHR.get(poi.icon, "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.05, 0.06, 0.08))
			if big:
				draw_string(_font, mp + Vector2(9, 4), poi.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.92, 0.93, 0.95, 0.9))
	# vehicles of interest + police
	var flash := fmod(Time.get_ticks_msec() * 0.004, 1.0) < 0.5
	for v in Game.vehicles:
		if not is_instance_valid(v) or v.dead:
			continue
		if v.def.tag == "police" and v.has_occupant() and Wanted.level > 0:
			draw_circle(_to_map(v.global_position, centre, yaw), 4.0, Color(1, 0.25, 0.25) if flash else Color(0.3, 0.5, 1))
		elif v.owner_is_player and v.driver == null:
			draw_rect(Rect2(_to_map(v.global_position, centre, yaw) - Vector2(3, 3), Vector2(6, 6)), Color(0.5, 1.0, 0.6))
	if Wanted.level > 0:
		for n in Game.npcs:
			if is_instance_valid(n) and n.is_law() and not n.dead:
				var mp2 := _to_map(n.global_position, centre, yaw)
				draw_circle(mp2, 3.0, Color(0.35, 0.55, 1.0))
				if Wanted.state == "search":
					var f: Vector3 = -n.global_basis.z
					var tip := _to_map(n.global_position + f * 18.0, centre, yaw)
					draw_line(mp2, tip, Color(0.4, 0.6, 1.0, 0.35), 5.0)
	if Game.waypoint != null:
		var wm := _to_map(Game.waypoint, centre, yaw)
		draw_circle(wm, 6.0, Color(0.75, 0.4, 1.0))
		draw_circle(wm, 3.0, Color.WHITE)
	# player arrow
	var pm := _to_map(p.global_position, centre, yaw)
	var heading: float = p.facing
	if p.in_vehicle():
		heading = p.vehicle.global_rotation.y
	var ang := -(heading - yaw) if not big else -heading
	var tri := PackedVector2Array([pm + Vector2(0, -8).rotated(ang), pm + Vector2(5.5, 6).rotated(ang), pm + Vector2(0, 3).rotated(ang), pm + Vector2(-5.5, 6).rotated(ang)])
	draw_colored_polygon(tri, Color(1, 1, 1))
	draw_polyline(tri + PackedVector2Array([tri[0]]), Color(0.05, 0.06, 0.08), 1.2)
	if not big:
		# north marker
		var nd := Vector2(0, -1).rotated(0.0)
		var c := cos(yaw)
		var s := sin(yaw)
		nd = Vector2(0.0 * c - (-1.0) * s, 0.0 * s + (-1.0) * c)
		var np := size * 0.5 + nd * (size.x * 0.5 - 12.0)
		draw_string(_font, np + Vector2(-4, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.92, 0.95, 0.55), false, 2.0)


func _line(a: Vector3, b: Vector3, col: Color, width: float, centre: Vector3, yaw: float) -> void:
	draw_line(_to_map(a, centre, yaw), _to_map(b, centre, yaw), col, width)


func _poly(pts: Array, col: Color, centre: Vector3, yaw: float) -> void:
	var pv := PackedVector2Array()
	for w in pts:
		pv.append(_to_map(w, centre, yaw))
	draw_colored_polygon(pv, Color(col.r, col.g, col.b, 0.9))
