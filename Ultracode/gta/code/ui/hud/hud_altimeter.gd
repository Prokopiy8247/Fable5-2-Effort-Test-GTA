class_name HudAltimeter
extends Control
## Skydiving altimeter (right edge, centred) while the player is in the "freefall" or "parachute"
## state: height above ground / water, vertical speed, a square-root altitude tape and - in
## freefall below PULL_ALT - a blinking "open the canopy" cue with the deploy key.
## HudRoot calls set_values() every frame while active (plain float reads, no allocations).

const SIZE := Vector2(210.0, 472.0)
const TAPE_TOP := 190.0
const TAPE_BOTTOM := 440.0
const TAPE_MAX := 1000.0
const PULL_ALT := 140.0
const TICKS: Array[float] = [0.0, 50.0, 100.0, 200.0, 400.0, 700.0, 1000.0]

var active: bool = false
var altitude: float = 0.0          ## metres above ground / water
var vspeed: float = 0.0            ## m/s, negative = falling
var canopy: bool = false           ## false = freefall, true = parachute open
var deploy_key: String = "Space"

var _alpha: float = 0.0
var _alt_int: int = -99999
var _alt_str: String = "0"
var _vs_int: int = -99999
var _vs_str: String = ""
var _blink: float = 0.0
var _marker: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE
	modulate.a = 0.0
	visible = false


func set_active(on: bool) -> void:
	if on and not active:
		visible = true
		_marker = _tape_frac(altitude)
	active = on


func set_values(p_altitude: float, p_vspeed: float, p_canopy: bool) -> void:
	altitude = maxf(p_altitude, 0.0)
	vspeed = p_vspeed
	if p_canopy != canopy:
		canopy = p_canopy
		queue_redraw()
	var ai := int(round(altitude))
	if ai != _alt_int:
		_alt_int = ai
		_alt_str = str(ai)
		queue_redraw()
	var vi := int(round(vspeed))
	if vi != _vs_int:
		_vs_int = vi
		_vs_str = "%d m/s" % absi(vi)
		queue_redraw()


func is_pull_warning() -> bool:
	return active and not canopy and altitude < PULL_ALT


func _process(delta: float) -> void:
	var target := 1.0 if active else 0.0
	if _alpha != target:
		_alpha = move_toward(_alpha, target, delta * 5.0)
		modulate.a = _alpha
		if _alpha <= 0.0:
			visible = false
			return
	var mf := _tape_frac(altitude)
	if absf(mf - _marker) > 0.0005:
		_marker = lerpf(_marker, mf, 1.0 - exp(-14.0 * delta))
		queue_redraw()
	if is_pull_warning():
		_blink += delta
		queue_redraw()


static func _tape_frac(alt: float) -> float:
	return sqrt(clampf(alt / TAPE_MAX, 0.0, 1.0))


func _danger_color() -> Color:
	if canopy:
		return UiStyle.TEAL_LIGHT
	if altitude < PULL_ALT:
		return UiStyle.CORAL_HOT
	if altitude < PULL_ALT * 2.0:
		return UiStyle.SUN
	return UiStyle.GOOD


func _draw() -> void:
	var head := UiStyle.font(&"head")
	var num := UiStyle.font(&"num")
	var body := UiStyle.font(&"body")
	draw_style_box(UiStyle.cached_box(&"glass"), Rect2(Vector2.ZERO, SIZE))
	var col := _danger_color()
	# state line
	UiIcons.draw(self, &"parachute" if canopy else &"person", Vector2(38.0, 40.0), 34.0, col)
	draw_string(head, Vector2(64.0, 49.0), "CANOPY" if canopy else "FREEFALL", HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiStyle.FS_SMALL, UiStyle.TEXT)
	# big readout
	var tw := UiStyle.text_width(num, _alt_str, 60)
	var x0 := (SIZE.x - tw - 30.0) * 0.5
	UiStyle.text(self, num, Vector2(x0, 128.0), _alt_str, 60, UiStyle.CREAM)
	draw_string(head, Vector2(x0 + tw + 6.0, 128.0), "M", HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiStyle.FS_SMALL, UiStyle.MUTED)
	draw_string(head, Vector2(0.0, 150.0), "ABOVE GROUND", HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, UiStyle.FS_TINY, UiStyle.MUTED)
	if _vs_str != "":
		UiIcons.draw(self, &"chev_down" if vspeed <= 0.0 else &"chev_up", Vector2(62.0, 172.0), 16.0, col)
		draw_string(num, Vector2(78.0, 179.0), _vs_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiStyle.FS_SMALL, UiStyle.TEXT)
	# tape
	var tx := 58.0
	var track := Rect2(tx, TAPE_TOP, 10.0, TAPE_BOTTOM - TAPE_TOP)
	draw_style_box(UiStyle.cached_box(&"track_dark"), track)
	var pull_y := lerpf(TAPE_BOTTOM, TAPE_TOP, _tape_frac(PULL_ALT))
	draw_style_box(UiStyle._fill_box(Color(UiStyle.CORAL_HOT, 0.55)), Rect2(tx, pull_y, 10.0, TAPE_BOTTOM - pull_y))
	for t in TICKS:
		var ty := lerpf(TAPE_BOTTOM, TAPE_TOP, _tape_frac(t))
		draw_line(Vector2(tx + 14.0, ty), Vector2(tx + 26.0, ty), Color(1, 1, 1, 0.45), 2.0)
		draw_string(num, Vector2(tx + 32.0, ty + 7.0), str(int(t)), HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiStyle.FS_TINY, UiStyle.MUTED)
	var my := lerpf(TAPE_BOTTOM, TAPE_TOP, clampf(_marker, 0.0, 1.0))
	draw_colored_polygon(PackedVector2Array([Vector2(tx - 6.0, my), Vector2(tx - 26.0, my - 12.0), Vector2(tx - 26.0, my + 12.0)]), col)
	draw_line(Vector2(tx - 4.0, my), Vector2(tx + 14.0, my), col, 4.0)
	if altitude > TAPE_MAX:
		UiIcons.draw(self, &"chev_up", Vector2(tx + 5.0, TAPE_TOP - 14.0), 16.0, UiStyle.CREAM)
	# pull cue
	if is_pull_warning():
		var r := Rect2(14.0, SIZE.y * 0.5 - 4.0, SIZE.x - 28.0, 56.0)
		var k := 0.5 + 0.5 * sin(_blink * 9.0)
		draw_style_box(UiStyle.box(Color(1, 1, 1, 0.0), 30, Color(UiStyle.CREAM, 0.35 + 0.5 * k), 3), r.grow(4.0 + 3.0 * k))
		draw_style_box(UiStyle._fill_box(UiStyle.CORAL_HOT.lerp(UiStyle.SUN, 0.35 * k)), Rect2(r.position, r.size))
		var kw := UiStyle.keycap_width(deploy_key, UiStyle.FS_TINY)
		var total := kw + 10.0 + UiStyle.text_width(head, "OPEN", UiStyle.FS_BODY)
		var kx := r.get_center().x - total * 0.5
		UiStyle.draw_keycap(self, Vector2(kx, r.position.y + 12.0), deploy_key, UiStyle.FS_TINY)
		UiStyle.text_in(self, head, Rect2(kx + kw + 10.0, r.position.y, 200.0, r.size.y), "OPEN", UiStyle.FS_BODY, UiStyle.NAVY_DEEP)
