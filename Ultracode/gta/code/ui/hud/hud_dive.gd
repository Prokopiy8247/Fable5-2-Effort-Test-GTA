class_name HudDive
extends Control
## Breath / scuba gauge (right edge, centred) while the player is under water: a ring with the
## remaining breath, the depth below the surface and a SCUBA tag when the player wears a tank
## (player.has_scuba). Low breath pulses coral. Replaces the thin breath bar of HudVitals while shown.

const SIZE := Vector2(210.0, 262.0)
const RING_R := 70.0
const BREATH_COLOR := Color(0.56, 0.79, 0.91)

var active: bool = false
var breath: float = 1.0
var depth: float = 0.0
var scuba: bool = false

var _alpha: float = 0.0
var _shown: float = 1.0
var _pct: int = -1
var _pct_str: String = "100"
var _depth_tenths: int = -1
var _depth_str: String = "0.0 m"
var _pulse: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE
	modulate.a = 0.0
	visible = false


func set_active(on: bool) -> void:
	if on and not active:
		visible = true
		_shown = breath
	active = on


func set_values(p_breath: float, p_depth: float, p_scuba: bool) -> void:
	breath = clampf(p_breath, 0.0, 1.0)
	depth = maxf(p_depth, 0.0)
	if p_scuba != scuba:
		scuba = p_scuba
		queue_redraw()
	var pct := int(ceil(breath * 100.0))
	if pct != _pct:
		_pct = pct
		_pct_str = str(pct)
		queue_redraw()
	var dt := int(round(depth * 10.0))
	if dt != _depth_tenths:
		_depth_tenths = dt
		_depth_str = "%.1f m" % (dt / 10.0)
		queue_redraw()


func _process(delta: float) -> void:
	var target := 1.0 if active else 0.0
	if _alpha != target:
		_alpha = move_toward(_alpha, target, delta * 5.0)
		modulate.a = _alpha
		if _alpha <= 0.0:
			visible = false
			return
	if absf(_shown - breath) > 0.001:
		_shown = move_toward(_shown, breath, delta * 1.5)
		queue_redraw()
	if breath < 0.25:
		_pulse += delta * 7.0
		queue_redraw()


func _draw() -> void:
	var head := UiStyle.font(&"head")
	var num := UiStyle.font(&"num")
	draw_style_box(UiStyle.cached_box(&"glass"), Rect2(Vector2.ZERO, SIZE))
	var c := Vector2(SIZE.x * 0.5, 104.0)
	var col: Color = BREATH_COLOR
	if breath < 0.25:
		col = UiStyle.CORAL_HOT.lerp(Color.WHITE, 0.2 + 0.2 * sin(_pulse))
	elif breath < 0.5:
		col = UiStyle.SUN
	var a0 := deg_to_rad(135.0)
	var sweep := deg_to_rad(270.0)
	draw_arc(c, RING_R, a0, a0 + sweep, 64, Color(0, 0, 0, 0.45), 14.0, true)
	var f := clampf(_shown, 0.0, 1.0)
	if f > 0.003:
		draw_arc(c, RING_R, a0, a0 + sweep * f, maxi(int(64.0 * f), 3), col, 14.0, true)
	UiIcons.draw(self, &"bubbles", c + Vector2(0, -26.0), 30.0, col)
	var tw := UiStyle.text_width(num, _pct_str, 46)
	UiStyle.text(self, num, Vector2(c.x - (tw + 18.0) * 0.5, c.y + 26.0), _pct_str, 46, UiStyle.CREAM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
	draw_string(head, Vector2(c.x - (tw + 18.0) * 0.5 + tw + 3.0, c.y + 26.0), "%", HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiStyle.FS_SMALL, UiStyle.MUTED)
	draw_string(head, Vector2(0.0, c.y + RING_R + 6.0), "BREATH", HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, UiStyle.FS_TINY, UiStyle.MUTED)
	# depth
	var dr := Rect2(20.0, SIZE.y - 58.0, SIZE.x - 40.0, 40.0)
	draw_style_box(UiStyle.cached_box(&"chip"), dr)
	UiStyle.text_in(self, head, Rect2(dr.position.x + 14.0, dr.position.y, 80.0, dr.size.y), "DEPTH", UiStyle.FS_TINY, UiStyle.MUTED)
	UiStyle.text_in(self, num, Rect2(dr.position.x, dr.position.y, dr.size.x - 14.0, dr.size.y), _depth_str, UiStyle.FS_SMALL, UiStyle.TEXT,
			HORIZONTAL_ALIGNMENT_RIGHT)
	if scuba:
		var sr := Rect2(SIZE.x - 92.0, 12.0, 78.0, 28.0)
		draw_style_box(UiStyle._fill_box(UiStyle.TEAL), sr)
		UiStyle.text_in(self, head, sr, "SCUBA", UiStyle.FS_TINY, UiStyle.NAVY_DEEP, HORIZONTAL_ALIGNMENT_CENTER)
