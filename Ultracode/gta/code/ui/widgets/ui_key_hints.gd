class_name UiKeyHints
extends Control
## Footer strip of "[key] text" hints.
##     var hints := UiKeyHints.new([{"action": "pause", "text": "Back"}, {"key": "Enter", "text": "Select"}])
## Each hint has either "action" (label looked up with InputSetup.label) or "key" (literal label;
## may also be an Array of labels: {"keys": ["W", "S"], "text": "Navigate"}).

var hints: Array = []
var align_right: bool = false


func _init(p_hints: Array = [], p_align_right: bool = false) -> void:
	hints = p_hints
	align_right = p_align_right
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(200.0, 46.0)


func set_hints(p_hints: Array) -> void:
	hints = p_hints
	queue_redraw()


static func labels_of(hint: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if hint.has("keys"):
		for k in hint["keys"]:
			out.append(str(k))
	elif hint.has("key"):
		out.append(str(hint["key"]))
	elif hint.has("action"):
		var l := InputSetup.label(str(hint["action"]))
		out.append("Esc" if l == "Escape" else l)
	return out


func _measure() -> float:
	var body := UiStyle.font(&"body")
	var w := 0.0
	for h in hints:
		if not (h is Dictionary):
			continue
		for l in labels_of(h):
			w += UiStyle.keycap_width(l, UiStyle.FS_SMALL) + 6.0
		w += UiStyle.text_width(body, str(h.get("text", "")), UiStyle.FS_SMALL) + 10.0 + 30.0
	return w - 30.0


func _draw() -> void:
	var body := UiStyle.font(&"body")
	var x := 0.0
	if align_right:
		x = maxf(size.x - _measure(), 0.0)
	var cap_h := UiStyle.FS_SMALL + 16.0
	var y := (size.y - cap_h) * 0.5
	for h in hints:
		if not (h is Dictionary):
			continue
		for l in labels_of(h):
			x += UiStyle.draw_keycap(self, Vector2(x, y), l, UiStyle.FS_SMALL) + 6.0
		x += 4.0
		var txt := str(h.get("text", ""))
		UiStyle.text_in(self, body, Rect2(x, y, 600.0, cap_h - 2.0), txt, UiStyle.FS_SMALL, UiStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
		x += UiStyle.text_width(body, txt, UiStyle.FS_SMALL) + 36.0
