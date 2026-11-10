class_name HudTaxiMeter
extends Control
## Taxi fare meter (top-left, under the activity card) while the player rides in a taxi.
## HudRoot polls Game.get_system("taxi").get_fare() at 4 Hz and calls set_fare(): the value may
## be a number (dollars) or a Dictionary {fare, distance (m), destination, eta (s)}.

const SIZE := Vector2(400.0, 112.0)

var active: bool = false
var fare: int = 0
var destination: String = ""
var distance: float = -1.0
var quote: int = 0                ## fixed price of the ride (0 = unknown), shown in the title row

var _alpha: float = 0.0
var _shown: float = 0.0
var _str: String = "$0"
var _bump: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE
	modulate.a = 0.0
	visible = false


func set_active(on: bool) -> void:
	if on and not active:
		visible = true
		_shown = float(fare)
	active = on


func set_fare(v: Variant) -> void:
	var f := fare
	var dest := destination
	var dist := distance
	if v is Dictionary:
		var d: Dictionary = v
		f = int(round(float(d.get("fare", d.get("amount", fare)))))
		dest = str(d.get("destination", d.get("destination_name", "")))
		dist = float(d.get("distance", d.get("distance_left", -1.0)))
		var q := int(d.get("quote", 0))
		if q != quote:
			quote = q
			queue_redraw()
	elif v is float or v is int:
		f = int(round(float(v)))
	if f > fare:
		_bump = 1.0
	if f != fare or dest != destination or absf(dist - distance) > 5.0:
		fare = f
		destination = dest
		distance = dist
		queue_redraw()


func _process(delta: float) -> void:
	var target := 1.0 if active else 0.0
	if _alpha != target:
		_alpha = move_toward(_alpha, target, delta * 4.0)
		modulate.a = _alpha
		if _alpha <= 0.0:
			visible = false
			return
	if absf(_shown - float(fare)) > 0.01 or _bump > 0.0:
		_shown = move_toward(_shown, float(fare), maxf(absf(float(fare) - _shown) * 6.0, 4.0) * delta)
		_bump = maxf(_bump - delta * 3.0, 0.0)
		var s := UiStyle.money(int(round(_shown)))
		if s != _str or _bump > 0.0:
			_str = s
			queue_redraw()


func _draw() -> void:
	var head := UiStyle.font(&"head")
	var num := UiStyle.font(&"num")
	var body := UiStyle.font(&"body")
	draw_style_box(UiStyle.cached_box(&"glass"), Rect2(Vector2.ZERO, SIZE))
	var tile := Rect2(18.0, 18.0, 76.0, 76.0)
	draw_style_box(UiStyle._fill_box(UiStyle.SUN), Rect2(tile.position, Vector2(76.0, 76.0)))
	UiIcons.draw(self, &"car", tile.get_center() + Vector2(0, 2.0), 48.0, UiStyle.NAVY_DEEP)
	var head_txt := "BAY CABS  -  FARE" if quote <= 0 else "BAY CABS  -  QUOTE %s" % UiStyle.money(quote)
	draw_string(head, Vector2(112.0, 40.0), head_txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiStyle.FS_TINY, UiStyle.MUTED)
	var fs := int(46.0 + 8.0 * _bump)
	draw_string(num, Vector2(110.0, 86.0), _str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, UiStyle.SUN)
	var line := destination
	if distance >= 0.0:
		var dt := ("%.1f km" % (distance / 1000.0)) if distance >= 1000.0 else ("%d m" % int(distance))
		line = (line + "  -  " if line != "" else "") + dt
	if line != "":
		draw_string(body, Vector2(SIZE.x - 20.0 - 170.0, 84.0), line, HORIZONTAL_ALIGNMENT_RIGHT, 170.0, UiStyle.FS_TINY, UiStyle.CREAM)
