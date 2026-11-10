class_name HudStealth
extends Control
## Sneak indicator under the crosshair while the player is in stealth (EventBus.player_state_changed
## "stealth" / player.in_stealth): an eye glyph, "STEALTH" or "HIDDEN" and a small visibility bar
## from player.visibility_factor (0 = invisible .. 1 = fully exposed). The noise ring is drawn by
## the minimap (player.noise_radius).

const SIZE := Vector2(200.0, 96.0)

var active: bool = false
var visibility: float = 1.0

var _alpha: float = 0.0
var _vis_q: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE
	modulate.a = 0.0
	visible = false


func set_active(on: bool) -> void:
	if on and not active:
		visible = true
	active = on


func set_visibility(v: float) -> void:
	visibility = clampf(v, 0.0, 1.0)
	var q := int(visibility * 40.0)
	if q != _vis_q:
		_vis_q = q
		queue_redraw()


func is_hidden() -> bool:
	return visibility < 0.35


func _process(delta: float) -> void:
	var target := 1.0 if active else 0.0
	if _alpha != target:
		_alpha = move_toward(_alpha, target, delta * 6.0)
		modulate.a = _alpha
		if _alpha <= 0.0:
			visible = false


func _draw() -> void:
	var head := UiStyle.font(&"head")
	var c := Vector2(SIZE.x * 0.5, 26.0)
	var col: Color = UiStyle.TEAL_LIGHT
	if visibility > 0.7:
		col = UiStyle.CORAL
	elif visibility > 0.35:
		col = UiStyle.SUN
	draw_circle(c, 23.0, Color(UiStyle.NAVY_DEEP, 0.72), true, -1.0, true)
	draw_arc(c, 23.0, 0.0, TAU, 40, Color(col, 0.85), 2.5, true)
	UiIcons.draw(self, &"eye_off" if is_hidden() else &"eye", c, 30.0, col)
	var label := "HIDDEN" if is_hidden() else "STEALTH"
	UiStyle.text_outlined(self, head, Vector2(0.0, 72.0), label, UiStyle.FS_TINY, UiStyle.CREAM, 5, Color(0.02, 0.05, 0.1, 0.7),
			HORIZONTAL_ALIGNMENT_CENTER, SIZE.x)
	var bar := Rect2(SIZE.x * 0.5 - 50.0, 84.0, 100.0, 6.0)
	UiStyle.draw_bar(self, bar, visibility, col)
