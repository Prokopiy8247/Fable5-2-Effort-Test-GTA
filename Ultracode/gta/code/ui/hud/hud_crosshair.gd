class_name HudCrosshair
extends Control
## Centre-screen crosshair. style: 0 hidden, 1 dot, 2 four-tick cross whose gap follows the
## weapon spread (degrees, converted to pixels with the active camera FOV). Hit marker on hit().
## blocked = true (drive-by aim outside the seat's firing arc) swaps the reticle for a dim
## "no shot" ring with a slash.

var style: int = 1:
	set(v):
		if v != style:
			style = v
			queue_redraw()
var spread_deg: float = 0.0
var blocked: bool = false:
	set(v):
		if v != blocked:
			blocked = v
			queue_redraw()
var _gap: float = 8.0
var _hit_t: float = 0.0
var _hit_kill: bool = false
const HIT_TIME := 0.24


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_spread(deg: float) -> void:
	spread_deg = maxf(deg, 0.0)
	var fov := 70.0
	var cam: Camera3D = null
	if is_inside_tree():
		cam = get_viewport().get_camera_3d()
	if cam != null:
		fov = cam.fov
	var px := tan(deg_to_rad(spread_deg)) / maxf(tan(deg_to_rad(fov * 0.5)), 0.05) * size.y * 0.5
	var gap := clampf(px, 7.0, 160.0)
	if absf(gap - _gap) > 0.4:
		_gap = gap
		queue_redraw()


func hit(kill: bool = false) -> void:
	_hit_t = HIT_TIME
	_hit_kill = kill
	queue_redraw()


func _process(delta: float) -> void:
	if _hit_t > 0.0:
		_hit_t = maxf(_hit_t - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var c := (size * 0.5).round()
	var dark := Color(0, 0, 0, 0.55)
	var light := Color(1, 1, 1, 0.92)
	if blocked and style != 0:
		var bc := Color(UiStyle.CORAL, 0.85)
		draw_arc(c, 17.0, 0.0, TAU, 32, dark, 6.0, true)
		draw_arc(c, 17.0, 0.0, TAU, 32, bc, 3.0, true)
		draw_line(c + Vector2(-11.0, 11.0), c + Vector2(11.0, -11.0), dark, 6.0, true)
		draw_line(c + Vector2(-11.0, 11.0), c + Vector2(11.0, -11.0), bc, 3.0, true)
	elif style == 2:
		var g := _gap
		var l := 13.0
		for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * (g - 1.5), c + d * (g + l + 1.5), dark, 6.5)
			draw_line(c + d * g, c + d * (g + l), light, 3.5)
		draw_circle(c, 4.0, dark)
		draw_circle(c, 2.4, light)
	elif style == 1:
		draw_circle(c, 3.6, dark)
		draw_circle(c, 2.0, Color(1, 1, 1, 0.8))
	if _hit_t > 0.0:
		var a := _hit_t / HIT_TIME
		var col: Color = UiStyle.CORAL_HOT if _hit_kill else Color.WHITE
		col.a = a
		var inner := 9.0 + 6.0 * (1.0 - a)
		var outer := inner + 13.0
		for d2: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n := d2.normalized()
			draw_line(c + n * inner, c + n * outer, Color(0, 0, 0, 0.5 * a), 5.0)
			draw_line(c + n * inner, c + n * outer, col, 2.6)
