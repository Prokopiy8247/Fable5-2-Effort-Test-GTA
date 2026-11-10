extends Control
## Radar / full map drawing (roads, blocks, water, icons, police blips, waypoint + GPS route).

var full := false
var scale_px := 1.0          # pixels per metre
var waypoint = null          # Vector3 or null
var route_pts: PackedVector3Array = PackedVector3Array()
var _route_t := 0.0
var cursor := Vector2.ZERO   # full map cursor (metres)

const ICON_COL := {"gun": Color(1, 0.6, 0.2), "clothes": Color(0.9, 0.5, 0.9), "food": Color(0.5, 0.9, 0.4), "hospital": Color(1, 0.3, 0.3), "police": Color(0.3, 0.5, 1.0),
	"home": Color(0.3, 1.0, 0.6), "garage": Color(0.4, 0.9, 0.9), "mods": Color(1.0, 0.8, 0.2), "gas": Color(0.9, 0.9, 0.3), "air": Color(0.8, 0.8, 1.0),
	"boat": Color(0.4, 0.7, 1.0), "metro": Color(0.3, 0.9, 0.9), "atm": Color(0.5, 0.8, 0.5), "barber": Color(0.9, 0.7, 0.9), "stunt": Color(1.0, 0.5, 0.1),
	"elevator": Color(0.9, 0.9, 0.9), "activity": Color(1.0, 0.4, 0.7)}
const ICON_CH := {"gun": "G", "clothes": "C", "food": "F", "hospital": "+", "police": "P", "home": "H", "garage": "V", "mods": "M", "gas": "$", "air": "A", "boat": "B",
	"metro": "T", "atm": "$", "barber": "S", "stunt": "!", "elevator": "E", "activity": "*"}


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	if not visible or G.player == null:
		return
	_route_t -= dt
	if waypoint != null and _route_t <= 0.0 and G.traffic:
		_route_t = 1.0
		var pp = G.player_pos()
		route_pts = PackedVector3Array([pp])
		for n in G.traffic.route(pp, waypoint):
			route_pts.append(G.traffic.node_pos(n))
		route_pts.append(waypoint)
		if G.dist2d(pp, waypoint) < 12.0:
			waypoint = null
			route_pts = PackedVector3Array()
			G.notify("Destination reached", 2.0)
	queue_redraw()


func set_waypoint(p) -> void:
	waypoint = p
	_route_t = 0.0
	if p == null:
		route_pts = PackedVector3Array()


func _xf() -> Transform2D:
	var pp = G.player_pos()
	var c = size * 0.5
	if full:
		var s: float = min(size.x, size.y) / 760.0
		scale_px = s
		return Transform2D(0.0, Vector2(s, s), 0.0, c - Vector2(0, -43) * s)
	scale_px = size.x / 190.0
	var yaw: float = G.cam.yaw if G.cam else 0.0
	var t = Transform2D.IDENTITY
	t = t.translated(-Vector2(pp.x, pp.z))
	t = Transform2D(yaw, Vector2.ZERO) * t
	t = Transform2D(0.0, Vector2(scale_px, scale_px), 0.0, Vector2.ZERO) * t
	t = Transform2D(0.0, c + Vector2(0, size.y * 0.18)) * t
	return t


func map_to_world(p: Vector2) -> Vector3:
	var w = _xf().affine_inverse() * p
	return Vector3(w.x, 0, w.y)


func _draw() -> void:
	if G.world == null or G.player == null:
		return
	var W = G.world
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.2, 0.3, 0.92 if full else 0.8))
	var xf = _xf()
	draw_set_transform_matrix(xf)
	draw_rect(Rect2(-300, -300, 600, 514), Color(0.2, 0.22, 0.24))
	draw_rect(Rect2(-300, 214, 300, 30), Color(0.75, 0.68, 0.48))
	for b in W.blocks:
		var col = Color(0.34, 0.36, 0.38)
		match b.district:
			"residential", "park", "hill": col = Color(0.24, 0.42, 0.25)
			"industrial": col = Color(0.36, 0.33, 0.3)
			"southshore": col = Color(0.33, 0.4, 0.36)
		draw_rect(b.rect, col)
	draw_rect(Rect2(-300, -300, 600, 93), Color(0.3, 0.31, 0.33))
	draw_rect(Rect2(-290, W.RUNWAY_Z - 15, 580, 30), Color(0.14, 0.14, 0.16))
	draw_rect(Rect2(-300, -207, 53, 414), Color(0.2, 0.38, 0.22))
	draw_rect(Rect2(247, -207, 53, 414), Color(0.36, 0.32, 0.26))
	for o in W.occupied:
		draw_rect(o, Color(0.52, 0.54, 0.57))
	for k in 4:
		draw_rect(Rect2(37, 214, 6, 48), Color(0.5, 0.4, 0.28))
		draw_rect(Rect2(97, 214, 6, 48), Color(0.5, 0.4, 0.28))
	draw_rect(Rect2(-83, 220, 6, 72), Color(0.5, 0.4, 0.28))
	draw_line(Vector2(-225, 0), Vector2(225, 0), Color(0.3, 0.9, 0.9, 0.5), 1.5)
	if route_pts.size() > 1:
		var pts = PackedVector2Array()
		for p in route_pts:
			pts.append(Vector2(p.x, p.z))
		draw_polyline(pts, Color(0.85, 0.3, 0.95), 3.0 / scale_px * 1.4)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var font = get_theme_default_font()
	# icons
	for ic in W.map_icons:
		var p: Vector2 = xf * Vector2(ic.pos.x, ic.pos.z)
		if not full and (p - size * 0.5).length() > size.x * 0.75:
			continue
		var c: Color = ICON_COL.get(ic.kind, Color.WHITE)
		draw_circle(p, 7.0 if full else 6.0, Color(0, 0, 0, 0.7))
		draw_circle(p, 5.5 if full else 4.6, c)
		draw_string(font, p + Vector2(-3.5, 4), ICON_CH.get(ic.kind, "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0))
	if G.extras:
		for a in G.extras.map_blips():
			var p2: Vector2 = xf * Vector2(a.pos.x, a.pos.z)
			draw_circle(p2, 4.5, a.col)
	# police / search feedback
	if G.wanted:
		var t = Time.get_ticks_msec() * 0.006
		for u in G.wanted.unit_blips():
			var p3: Vector2 = xf * Vector2(u.pos.x, u.pos.z)
			var fl = sin(t) > 0.0
			draw_circle(p3, 4.5, Color(1, 0.2, 0.2) if fl else Color(0.25, 0.4, 1.0))
			if u.has("dir") and G.wanted.state == "search":
				var d2: Vector2 = (xf.basis_xform(Vector2(u.dir.x, u.dir.z))).normalized()
				var cone = PackedVector2Array([p3, p3 + d2.rotated(0.5) * 26.0, p3 + d2.rotated(-0.5) * 26.0])
				draw_colored_polygon(cone, Color(0.3, 0.5, 1.0, 0.22))
		if G.wanted.state == "search" and G.wanted.stars > 0:
			var lk: Vector2 = xf * Vector2(G.wanted.last_known.x, G.wanted.last_known.z)
			draw_arc(lk, G.wanted.search_radius * scale_px, 0, TAU, 40, Color(1, 0.3, 0.3, 0.5 + 0.3 * sin(t)), 2.0)
	if waypoint != null:
		var wp: Vector2 = xf * Vector2(waypoint.x, waypoint.z)
		wp = _clamp_edge(wp)
		draw_circle(wp, 6.0, Color(0.85, 0.3, 0.95))
		draw_circle(wp, 2.5, Color.WHITE)
	# player arrow
	var pp = G.player_pos()
	var pc: Vector2 = xf * Vector2(pp.x, pp.z)
	var heading: float = G.player.facing if G.player.state != "vehicle" else G.player.vehicle.global_rotation.y
	var fw = xf.basis_xform(Vector2(-sin(heading), -cos(heading))).normalized()
	var rt = Vector2(-fw.y, fw.x)
	draw_colored_polygon(PackedVector2Array([pc + fw * 9.0, pc - fw * 6.0 + rt * 6.0, pc - fw * 3.0, pc - fw * 6.0 - rt * 6.0]), Color.WHITE)
	if full:
		for name in W.locations:
			var lp: Vector3 = W.locations[name]
			if name in ["SafehouseInside", "Spire Roof", "Runway West", "Hangar", "Helipad"]:
				continue
			var sp: Vector2 = xf * Vector2(lp.x, lp.z)
			draw_string(font, sp + Vector2(8, 4), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.85))
		var cp: Vector2 = xf * cursor
		draw_line(cp - Vector2(10, 0), cp + Vector2(10, 0), Color.WHITE, 2.0)
		draw_line(cp - Vector2(0, 10), cp + Vector2(0, 10), Color.WHITE, 2.0)
	else:
		# north marker
		var n: Vector2 = size * 0.5 + Vector2(0, size.y * 0.18) + xf.basis_xform(Vector2(0, -1)).normalized() * size.x * 0.44
		draw_string(font, _clamp_edge(n) + Vector2(-4, 4), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.9), false, 3.0)


func _clamp_edge(p: Vector2) -> Vector2:
	return Vector2(clamp(p.x, 8.0, size.x - 8.0), clamp(p.y, 8.0, size.y - 8.0))
