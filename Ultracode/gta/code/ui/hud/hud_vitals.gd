class_name HudVitals
extends Control
## Health / armor bars (+ thin stamina and breath bars that only appear while not full) on a
## glass card that grows upwards from the bottom of this control. Armor row is hidden at 0.

const CARD_W := 336.0
const ROW_H := 36.0
const THIN_H := 17.0
const BREATH_COLOR := Color(0.56, 0.79, 0.91)

var health: float = 100.0
var max_health: float = 100.0
var armor: float = 0.0
var max_armor: float = 100.0
var stamina: float = 1.0
var breath: float = 1.0
## false while the dive gauge (HudDive) shows the breath instead of the thin bar
var show_breath: bool = true:
	set(v):
		if v != show_breath:
			show_breath = v
			queue_redraw()

var _h: float = 1.0            ## displayed health fraction
var _h_ghost: float = 1.0      ## trailing "damage taken" fraction
var _a: float = 0.0
var _h_int: int = -1
var _a_int: int = -1
var _h_str: String = "100"
var _a_str: String = "0"
var _pulse: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(CARD_W, 150.0)
	size = custom_minimum_size


func set_vitals(p_health: float, p_max_health: float, p_armor: float, p_max_armor: float) -> void:
	health = maxf(p_health, 0.0)
	max_health = maxf(p_max_health, 1.0)
	armor = maxf(p_armor, 0.0)
	max_armor = maxf(p_max_armor, 1.0)
	var hi := int(ceil(health))
	if hi != _h_int:
		_h_int = hi
		_h_str = str(hi)
		queue_redraw()
	var ai := int(ceil(armor))
	if ai != _a_int:
		_a_int = ai
		_a_str = str(ai)
		queue_redraw()


func set_extra(p_stamina: float, p_breath: float) -> void:
	p_stamina = clampf(p_stamina, 0.0, 1.0)
	p_breath = clampf(p_breath, 0.0, 1.0)
	if absf(p_stamina - stamina) > 0.004 or absf(p_breath - breath) > 0.004 \
			or (p_stamina >= 0.995) != (stamina >= 0.995) or (p_breath >= 0.995) != (breath >= 0.995):
		stamina = p_stamina
		breath = p_breath
		queue_redraw()


## Jump straight to the current values (no animation) - used on spawn / respawn.
func snap() -> void:
	_h = clampf(health / max_health, 0.0, 1.0)
	_h_ghost = _h
	_a = clampf(armor / max_armor, 0.0, 1.0)
	queue_redraw()


func _process(delta: float) -> void:
	var th := clampf(health / max_health, 0.0, 1.0)
	var ta := clampf(armor / max_armor, 0.0, 1.0)
	var changed := false
	if absf(_h - th) > 0.0005:
		_h = move_toward(_h, th, delta * 1.6)
		changed = true
	if _h_ghost > _h + 0.0005:
		_h_ghost = move_toward(_h_ghost, _h, delta * 0.3)
		changed = true
	elif _h_ghost < _h:
		_h_ghost = _h
	if absf(_a - ta) > 0.0005:
		_a = move_toward(_a, ta, delta * 1.6)
		changed = true
	if th < 0.26 and health > 0.0:
		_pulse += delta * 6.0
		changed = true
	if changed:
		queue_redraw()


func _draw() -> void:
	var show_armor := armor > 0.5 or _a > 0.004
	var breath_bar := show_breath and breath < 0.995
	var thin := (1 if stamina < 0.995 else 0) + (1 if breath_bar else 0)
	var h := 20.0 + ROW_H * (2.0 if show_armor else 1.0) + THIN_H * thin + (6.0 if thin > 0 else 0.0)
	var card := Rect2(0.0, size.y - h, CARD_W, h)
	draw_style_box(UiStyle.cached_box(&"glass"), card)
	var y := card.position.y + 10.0
	if stamina < 0.995:
		_thin(y, stamina, UiStyle.SUN, &"bolt")
		y += THIN_H
	if breath_bar:
		_thin(y, breath, BREATH_COLOR if breath > 0.25 else UiStyle.BAD, &"bubbles")
		y += THIN_H
	if thin > 0:
		y += 6.0
	if show_armor:
		_row(y, &"shield", _a, -1.0, UiStyle.TEAL_LIGHT, _a_str)
		y += ROW_H
	var hc: Color = UiStyle.CORAL
	if health / max_health < 0.26:
		hc = UiStyle.BAD.lerp(Color.WHITE, 0.25 + 0.25 * sin(_pulse))
	_row(y, &"heart", _h, _h_ghost, hc, _h_str)


func _row(y: float, icon: StringName, frac: float, ghost: float, col: Color, value: String) -> void:
	var mid := y + ROW_H * 0.5
	UiIcons.draw(self, icon, Vector2(32.0, mid), 25.0, col)
	var bar := Rect2(56.0, mid - 8.0, CARD_W - 56.0 - 76.0, 16.0)
	draw_style_box(UiStyle.cached_box(&"track_dark"), bar)
	if ghost > frac + 0.002:
		draw_style_box(UiStyle._fill_box(Color(1, 1, 1, 0.6)), Rect2(bar.position, Vector2(maxf(bar.size.x * ghost, 16.0), bar.size.y)))
	if frac > 0.002:
		draw_style_box(UiStyle._fill_box(col), Rect2(bar.position, Vector2(maxf(bar.size.x * frac, 16.0), bar.size.y)))
	UiStyle.text_in(self, UiStyle.font(&"num"), Rect2(CARD_W - 76.0, y, 58.0, ROW_H), value, UiStyle.FS_LARGE, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)


func _thin(y: float, frac: float, col: Color, icon: StringName) -> void:
	var mid := y + THIN_H * 0.5
	UiIcons.draw(self, icon, Vector2(32.0, mid), 15.0, col)
	var bar := Rect2(56.0, mid - 3.5, CARD_W - 56.0 - 20.0, 7.0)
	draw_style_box(UiStyle.cached_box(&"track_dark"), bar)
	if frac > 0.01:
		draw_style_box(UiStyle._fill_box(col), Rect2(bar.position, Vector2(maxf(bar.size.x * frac, 7.0), bar.size.y)))
