class_name HudPrompt
extends Control
## Bottom-centre interaction prompt: "[F] Enter vehicle" on a glass pill.

var text: String = ""
var key_label: String = ""
var _want: bool = false
var _alpha: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(900.0, 64.0)
	size = custom_minimum_size
	modulate.a = 0.0


func show_prompt(p_text: String, p_key: String) -> void:
	if p_text != text or p_key != key_label:
		text = p_text
		key_label = "Esc" if p_key == "Escape" else p_key
		queue_redraw()
	_want = p_text != ""


func hide_prompt() -> void:
	_want = false


func is_showing() -> bool:
	return _want


func _process(delta: float) -> void:
	var target := 1.0 if _want else 0.0
	if _alpha != target:
		_alpha = move_toward(_alpha, target, delta * 8.0)
		modulate.a = _alpha


func _draw() -> void:
	if text == "":
		return
	var body := UiStyle.font(&"bold")
	var tw := UiStyle.text_width(body, text, UiStyle.FS_BODY)
	var kw := UiStyle.keycap_width(key_label, UiStyle.FS_BODY) if key_label != "" else 0.0
	var w := tw + kw + (16.0 if kw > 0.0 else 0.0) + 52.0
	var pill := Rect2((size.x - w) * 0.5, 0.0, w, size.y)
	draw_style_box(UiStyle.cached_box(&"pill"), pill)
	var x := pill.position.x + 24.0
	if kw > 0.0:
		UiStyle.draw_keycap(self, Vector2(x, (size.y - UiStyle.FS_BODY - 16.0) * 0.5), key_label, UiStyle.FS_BODY)
		x += kw + 16.0
	UiStyle.text_in(self, body, Rect2(x, 0.0, tw + 8.0, size.y), text, UiStyle.FS_BODY, UiStyle.TEXT)
