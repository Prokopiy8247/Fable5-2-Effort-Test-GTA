class_name HudVehicle
extends Control
## Vehicle cluster (bottom-right, above the weapon card): arc speedometer with the speed in
## km/h, vehicle name, a condition bar and - for aircraft - the altitude (altitude_agl: above
## ground / water when the aircraft provides it, else above sea level).
## Shown only while the player sits in a vehicle. Numbers are re-formatted only when they change.

const SIZE := Vector2(336.0, 232.0)
const GAUGE_R := 96.0
const ARC_FROM := 150.0
const ARC_SWEEP := 240.0

var active: bool = false
var title: String = ""
var is_aircraft: bool = false
var max_speed: float = 200.0
var speed: float = 0.0
var health_frac: float = 1.0
var altitude: float = 0.0

var _speed_int: int = -1
var _speed_str: String = "0"
var _alt_int: int = -99999
var _alt_str: String = ""
var _health_q: int = -1
var _alpha: float = 0.0
var _needle: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE
	modulate.a = 0.0


func set_vehicle(p_active: bool, p_title: String = "", vehicle_class: String = "car") -> void:
	active = p_active
	if not p_active:
		return
	title = p_title.to_upper()
	is_aircraft = vehicle_class == "heli" or vehicle_class == "plane"
	match vehicle_class:
		"plane": max_speed = 400.0
		"heli": max_speed = 260.0
		"boat": max_speed = 140.0
		"bicycle": max_speed = 60.0
		"bike": max_speed = 240.0
		_: max_speed = 220.0
	_speed_int = -1
	_alt_int = -99999
	queue_redraw()


func update_values(speed_kmh: float, p_health_frac: float, p_altitude: float) -> void:
	speed = absf(speed_kmh)
	var si := int(round(speed))
	if si != _speed_int:
		_speed_int = si
		_speed_str = str(si)
		queue_redraw()
	health_frac = clampf(p_health_frac, 0.0, 1.0)
	var hq := int(health_frac * 100.0)
	if hq != _health_q:
		_health_q = hq
		queue_redraw()
	altitude = p_altitude
	if is_aircraft:
		var ai := int(round(maxf(altitude, 0.0)))
		if ai != _alt_int:
			_alt_int = ai
			_alt_str = "ALT %d m" % ai
			queue_redraw()


func _process(delta: float) -> void:
	var target := 1.0 if active else 0.0
	if _alpha != target:
		_alpha = move_toward(_alpha, target, delta * 4.0)
		modulate.a = _alpha
	if _alpha <= 0.0:
		return
	var nf := clampf(speed / max_speed, 0.0, 1.0)
	if absf(nf - _needle) > 0.002:
		_needle = lerpf(_needle, nf, 1.0 - exp(-12.0 * delta))
		queue_redraw()


func _draw() -> void:
	if _alpha <= 0.0 and not active:
		return
	var c := Vector2(SIZE.x - GAUGE_R - 22.0, GAUGE_R + 16.0)
	draw_circle(c, GAUGE_R + 14.0, UiStyle.GLASS, true, -1.0, true)
	draw_arc(c, GAUGE_R + 14.0, 0.0, TAU, 72, UiStyle.LINE, 2.0, true)
	var a0 := deg_to_rad(ARC_FROM)
	var a1 := deg_to_rad(ARC_FROM + ARC_SWEEP)
	draw_arc(c, GAUGE_R - 4.0, a0, a1, 48, Color(1, 1, 1, 0.13), 11.0, true)
	var frac := clampf(_needle, 0.0, 1.0)
	if frac > 0.004:
		var col: Color = UiStyle.TEAL_LIGHT.lerp(UiStyle.SUN, clampf(frac * 2.0 - 0.6, 0.0, 1.0))
		if frac > 0.82:
			col = UiStyle.SUN.lerp(UiStyle.CORAL_HOT, (frac - 0.82) / 0.18)
		draw_arc(c, GAUGE_R - 4.0, a0, a0 + deg_to_rad(ARC_SWEEP) * frac, maxi(int(48.0 * frac), 4), col, 11.0, true)
		var tip := a0 + deg_to_rad(ARC_SWEEP) * frac
		draw_circle(c + Vector2(cos(tip), sin(tip)) * (GAUGE_R - 4.0), 8.5, Color.WHITE, true, -1.0, true)
	for i in 9:
		var ta := a0 + deg_to_rad(ARC_SWEEP) * float(i) / 8.0
		var dir := Vector2(cos(ta), sin(ta))
		draw_line(c + dir * (GAUGE_R - 20.0), c + dir * (GAUGE_R - 14.0), Color(1, 1, 1, 0.3), 2.0, true)
	var num := UiStyle.font(&"num")
	var head := UiStyle.font(&"head")
	UiStyle.text(self, num, Vector2(c.x - 90.0, c.y + 20.0), _speed_str, 70, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 180.0, false)
	UiStyle.text(self, head, Vector2(c.x - 90.0, c.y + 46.0), "KM/H", UiStyle.FS_TINY, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 180.0, false)
	if title != "":
		UiStyle.text(self, head, Vector2(c.x - 70.0, c.y - 44.0), title, UiStyle.FS_TINY, UiStyle.TEAL_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, 140.0, false)
	# condition bar in the open bottom of the gauge
	var hc: Color = UiStyle.GOOD
	if health_frac < 0.3:
		hc = UiStyle.BAD
	elif health_frac < 0.6:
		hc = UiStyle.SUN
	UiIcons.draw(self, &"wrench", Vector2(c.x - 48.0, c.y + 74.0), 20.0, hc)
	var bar := Rect2(c.x - 30.0, c.y + 69.0, 84.0, 10.0)
	draw_style_box(UiStyle.cached_box(&"track_dark"), bar)
	if health_frac > 0.01:
		draw_style_box(UiStyle._fill_box(hc), Rect2(bar.position, Vector2(maxf(bar.size.x * health_frac, 10.0), bar.size.y)))
	if is_aircraft and _alt_str != "":
		var w := UiStyle.text_width(num, _alt_str, UiStyle.FS_BODY) + 36.0
		var pill := Rect2(c.x - GAUGE_R - 30.0 - w, c.y + 40.0, w, 44.0)
		draw_style_box(UiStyle.cached_box(&"pill"), pill)
		UiStyle.text_in(self, num, pill, _alt_str, UiStyle.FS_BODY, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
