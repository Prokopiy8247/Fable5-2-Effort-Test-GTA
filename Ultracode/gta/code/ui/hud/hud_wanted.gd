class_name HudWanted
extends Control
## Wanted strip (top-centre): five stars on a glass pill, hidden at level 0.
## PURSUIT: solid stars, flashing red / blue edge.  SEARCH: stars blink, the label changes to
## "SEARCHING" and a thin bar shows the escape progress (it only fills while unseen).

const STAR := 40.0
const STAR_GAP := 12.0
const PILL_W := 5 * 40.0 + 4 * 12.0 + 56.0
const PILL_H := 64.0

var level: int = 0
var state: int = 0
var escape: float = 0.0
var _shown_level: int = 0
var _alpha: float = 0.0
var _time: float = 0.0
var _pop: float = 0.0
var _pop_index: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(760.0, 128.0)
	size = custom_minimum_size


func set_wanted(p_level: int, p_state: int, p_escape: float) -> void:
	p_level = clampi(p_level, 0, 5)
	if p_level > level:
		_pop = 1.0
		_pop_index = p_level - 1
	if p_level != level or p_state != state:
		queue_redraw()
	level = p_level
	state = p_state
	escape = clampf(p_escape, 0.0, 1.0)
	if level > 0:
		_shown_level = level


func is_active() -> bool:
	return level > 0 or _alpha > 0.01


func _process(delta: float) -> void:
	var target := 1.0 if level > 0 else 0.0
	if _alpha == target and level == 0:
		return
	_alpha = move_toward(_alpha, target, delta * 3.5)
	modulate.a = _alpha
	_time += delta
	if _pop > 0.0:
		_pop = maxf(_pop - delta * 2.5, 0.0)
	if _alpha <= 0.0:
		_shown_level = 0
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.01:
		return
	var a := 1.0
	var searching := state == 2 and level > 0
	var pill := Rect2((size.x - PILL_W) * 0.5, 0.0, PILL_W, PILL_H)
	draw_set_transform(Vector2(0, -12.0 * (1.0 - _alpha)), 0.0, Vector2.ONE)
	draw_style_box(UiStyle.cached_box(&"pill"), pill)
	# flashing edge while in pursuit
	if level > 0 and not searching:
		var blink := int(_time * 4.0) % 2 == 0
		var edge: Color = UiStyle.POLICE_RED if blink else UiStyle.POLICE_BLUE
		var r := PILL_H * 0.5
		draw_arc(pill.position + Vector2(r, r), r - 2.0, PI * 0.5, PI * 1.5, 16, Color(edge, 0.9 * a), 3.5, true)
		var edge2: Color = UiStyle.POLICE_BLUE if blink else UiStyle.POLICE_RED
		draw_arc(pill.end - Vector2(r, r), r - 2.0, -PI * 0.5, PI * 0.5, 16, Color(edge2, 0.9 * a), 3.5, true)
	var blink_a := 1.0
	if searching:
		blink_a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_time * 7.0))
	var x := pill.position.x + 28.0 + STAR * 0.5
	var cy := PILL_H * 0.5
	for i in 5:
		var c := Vector2(x + i * (STAR + STAR_GAP), cy)
		if i < _shown_level and (i < level or level == 0):
			var s := STAR
			if i == _pop_index and _pop > 0.0:
				s *= 1.0 + 0.6 * _pop
			UiIcons.draw(self, &"star", c, s, Color(UiStyle.SUN, a * blink_a))
		else:
			UiIcons.draw(self, &"star", c, STAR, Color(1, 1, 1, 0.1 * a))
			UiIcons.draw_star_outline(self, c, STAR, Color(1, 1, 1, 0.28 * a), 2.0)
	# state line under the pill
	var head := UiStyle.font(&"head")
	var label := "SEARCHING - STAY OUT OF SIGHT" if searching else "WANTED"
	var lc: Color = UiStyle.TEAL_LIGHT if searching else UiStyle.CORAL
	var lw := UiStyle.text_width(head, label, UiStyle.FS_SMALL)
	UiStyle.text_outlined(self, head, Vector2((size.x - lw) * 0.5, PILL_H + 30.0), label, UiStyle.FS_SMALL, Color(lc, a), 8, Color(0.02, 0.05, 0.1, 0.8))
	if searching:
		var bar := Rect2((size.x - 220.0) * 0.5, PILL_H + 42.0, 220.0, 8.0)
		draw_style_box(UiStyle.cached_box(&"track_dark"), bar)
		if escape > 0.01:
			draw_style_box(UiStyle._fill_box(UiStyle.TEAL_LIGHT), Rect2(bar.position, Vector2(maxf(bar.size.x * escape, 8.0), bar.size.y)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
