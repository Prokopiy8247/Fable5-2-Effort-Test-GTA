class_name HudWeapon
extends Control
## Weapon card (bottom-right): class icon, weapon name, ammo in mag / reserve, reload bar.
## Hidden while unarmed. Text is rebuilt only when a number actually changes.

const CARD := Vector2(336.0, 96.0)

var weapon_id: String = ""
var weapon_name: String = ""
var slot: String = ""
var in_mag: int = -1
var reserve: int = -1
var mag_size: int = 0

var _mag_str: String = ""
var _res_str: String = ""
var _alpha: float = 0.0
var _reload_left: float = 0.0
var _reload_total: float = 0.0
var _swap: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = CARD
	size = CARD
	modulate.a = 0.0


func is_shown() -> bool:
	return weapon_id != "" and weapon_id != "fists"


func set_weapon(id: String, display_name: String, p_slot: String, p_mag_size: int) -> void:
	if id != weapon_id:
		_swap = 1.0
		_reload_left = 0.0
	weapon_id = id
	weapon_name = display_name.to_upper()
	slot = p_slot
	mag_size = p_mag_size
	queue_redraw()


func set_ammo(p_in_mag: int, p_reserve: int) -> void:
	if p_in_mag != in_mag:
		in_mag = p_in_mag
		_mag_str = str(maxi(in_mag, 0))
		queue_redraw()
	if p_reserve != reserve:
		reserve = p_reserve
		_res_str = str(maxi(reserve, 0))
		queue_redraw()


func start_reload(duration: float) -> void:
	_reload_total = maxf(duration, 0.05)
	_reload_left = _reload_total
	queue_redraw()


func _process(delta: float) -> void:
	var target := 1.0 if is_shown() else 0.0
	if _alpha != target:
		_alpha = move_toward(_alpha, target, delta * 5.0)
		modulate.a = _alpha
	if _swap > 0.0:
		_swap = maxf(_swap - delta * 4.0, 0.0)
		queue_redraw()
	if _reload_left > 0.0:
		_reload_left = maxf(_reload_left - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	if weapon_id == "" or weapon_id == "fists":
		return
	var card := Rect2(Vector2.ZERO, CARD)
	draw_style_box(UiStyle.cached_box(&"glass"), card)
	# accent stripe on the right edge
	draw_style_box(UiStyle._fill_box(UiStyle.CORAL), Rect2(CARD.x - 10.0, 18.0, 5.0, CARD.y - 36.0))
	var icon_col: Color = UiStyle.CREAM.lerp(UiStyle.SUN, _swap)
	UiIcons.draw(self, UiIcons.weapon_slot_icon(slot), Vector2(60.0, CARD.y * 0.5), 64.0 + 10.0 * _swap, icon_col)
	var head := UiStyle.font(&"head")
	var num := UiStyle.font(&"num")
	var right := CARD.x - 28.0
	UiStyle.text(self, head, Vector2(110.0, 36.0), weapon_name, UiStyle.FS_SMALL, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, right - 110.0, false)
	if in_mag >= 0:
		var low := mag_size > 0 and in_mag <= int(ceil(mag_size * 0.25))
		var mag_col: Color = UiStyle.CORAL_HOT if (low or in_mag == 0) else UiStyle.TEXT
		if mag_size > 0 or reserve > 0:
			var res_w := UiStyle.text_width(num, _res_str, UiStyle.FS_LARGE)
			UiStyle.text(self, num, Vector2(right - res_w, 78.0), _res_str, UiStyle.FS_LARGE, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
			var slash_x := right - res_w - 22.0
			UiStyle.text(self, num, Vector2(slash_x, 78.0), "/", UiStyle.FS_LARGE, UiStyle.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
			var mag_w := UiStyle.text_width(num, _mag_str, UiStyle.FS_H2)
			UiStyle.text(self, num, Vector2(slash_x - mag_w - 10.0, 80.0), _mag_str, UiStyle.FS_H2, mag_col, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
		else:
			# thrown weapons: pieces left
			var txt := "x" + _mag_str
			UiStyle.text(self, num, Vector2(110.0, 80.0), txt, UiStyle.FS_H2, mag_col, HORIZONTAL_ALIGNMENT_RIGHT, right - 110.0, false)
	else:
		UiStyle.text(self, head, Vector2(110.0, 76.0), "MELEE", UiStyle.FS_LARGE, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, right - 110.0, false)
	if _reload_left > 0.0:
		var bar := Rect2(18.0, CARD.y - 13.0, CARD.x - 46.0, 6.0)
		draw_style_box(UiStyle.cached_box(&"track_dark"), bar)
		var f := 1.0 - _reload_left / _reload_total
		draw_style_box(UiStyle._fill_box(UiStyle.SUN), Rect2(bar.position, Vector2(maxf(bar.size.x * f, 6.0), bar.size.y)))
