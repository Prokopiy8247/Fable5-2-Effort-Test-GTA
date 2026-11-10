class_name HudMoney
extends Control
## Money pill (top-right, right-aligned inside this control) with a counting animation and
## fading +/- deltas to its left.

const PILL_H := 58.0
const DELTA_LIFE := 2.4

var amount: int = 0
var _shown: float = 0.0
var _shown_int: int = -1
var _text: String = "$0"
var _deltas: Array[Dictionary] = []      ## {text, col, t}
var _bump: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(760.0, 62.0)
	size = custom_minimum_size


func set_money(new_amount: int, delta_amount: int = 0, animate: bool = true) -> void:
	amount = new_amount
	if not animate:
		_shown = float(new_amount)
	if delta_amount != 0 and animate:
		var txt := ("+" if delta_amount > 0 else "-") + UiStyle.money(absi(delta_amount))
		_deltas.append({"text": txt, "col": UiStyle.GOOD if delta_amount > 0 else UiStyle.CORAL_HOT, "t": 0.0})
		if _deltas.size() > 4:
			_deltas.pop_front()
		_bump = 1.0
	_sync_text()
	queue_redraw()


func _sync_text() -> void:
	var si := int(round(_shown))
	if si != _shown_int:
		_shown_int = si
		_text = UiStyle.money(si)


func _process(delta: float) -> void:
	var dirty := false
	var target := float(amount)
	if _shown != target:
		var rate := maxf(absf(target - _shown) * 5.0, 240.0)
		_shown = move_toward(_shown, target, rate * delta)
		_sync_text()
		dirty = true
	if _bump > 0.0:
		_bump = maxf(_bump - delta * 3.0, 0.0)
		dirty = true
	if not _deltas.is_empty():
		for d in _deltas:
			d["t"] = float(d["t"]) + delta
		while not _deltas.is_empty() and float(_deltas[0]["t"]) > DELTA_LIFE:
			_deltas.pop_front()
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var num := UiStyle.font(&"num")
	var fs := UiStyle.FS_H3
	var tw := UiStyle.text_width(num, _text, fs)
	var w := tw + 44.0
	var pill := Rect2(size.x - w, 0.0, w, PILL_H)
	draw_style_box(UiStyle.cached_box(&"pill"), pill)
	var col: Color = UiStyle.SUN.lerp(Color.WHITE, _bump * 0.6)
	UiStyle.text_in(self, num, Rect2(pill.position.x, 0.0, w - 22.0, PILL_H), _text, fs, col, HORIZONTAL_ALIGNMENT_RIGHT)
	# deltas run to the left of the pill, newest first
	var x := pill.position.x - 18.0
	for i in _deltas.size():
		var d: Dictionary = _deltas[_deltas.size() - 1 - i]
		var t := float(d["t"])
		var a := clampf(t / 0.15, 0.0, 1.0) * clampf((DELTA_LIFE - t) / 0.6, 0.0, 1.0)
		var dc: Color = d["col"]
		var txt := str(d["text"])
		var dw := UiStyle.text_width(num, txt, UiStyle.FS_LARGE)
		var y := PILL_H * 0.5 + 10.0 - minf(t * 14.0, 6.0)
		UiStyle.text_outlined(self, num, Vector2(x - dw, y), txt, UiStyle.FS_LARGE, Color(dc, a), 8, Color(0.02, 0.05, 0.1, 0.8 * a))
		x -= dw + 22.0
