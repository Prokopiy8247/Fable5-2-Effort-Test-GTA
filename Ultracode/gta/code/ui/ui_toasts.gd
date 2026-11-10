class_name UiToasts
extends Control
## Notification stack (top-right, under the money pill). Each toast is a small custom-drawn glass
## card (kind coloured stripe + icon + text) that slides in, restacks smoothly and fades out.
## Runs on real time (works while paused and during slow motion). An identical message refreshes
## the toast that is already showing and adds an "x2" counter instead of stacking.

const MAX_VISIBLE := 5
const MIN_H := 54.0
const GAP := 10.0
const MAX_TEXT_W := 520.0
const FONT_SIZE := 22

var _items: Array[Dictionary] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(640.0, 400.0)
	size = custom_minimum_size


func push(text: String, kind: String = "info", duration: float = 3.5, icon: StringName = &"") -> void:
	if text.strip_edges() == "":
		return
	for it in _items:
		if str(it["text"]) == text and str(it["kind"]) == kind and float(it["t"]) < float(it["life"]):
			it["life"] = float(it["t"]) + maxf(duration, 1.0)
			it["count"] = int(it["count"]) + 1
			it["bump"] = 1.0
			(it["node"] as UiCanvas).queue_redraw()
			return
	var f := UiStyle.font(&"bold")
	var one := UiStyle.text_width(f, text, FONT_SIZE)
	var th := f.get_height(FONT_SIZE)
	if one > MAX_TEXT_W:
		th = f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, MAX_TEXT_W, FONT_SIZE, 3).y
	var item := {
		"text": text, "kind": kind, "t": 0.0, "life": maxf(duration, 0.8), "count": 1, "bump": 0.0,
		"w": minf(one, MAX_TEXT_W) + 88.0, "h": maxf(MIN_H, th + 22.0), "y": -1.0, "multi": one > MAX_TEXT_W,
		"icon": icon if icon != &"" else UiStyle.kind_icon(kind), "col": UiStyle.kind_color(kind),
	}
	var node := UiCanvas.new(_draw_item.bind(item))
	node.size = Vector2(float(item["w"]), float(item["h"]))
	node.modulate.a = 0.0
	add_child(node)
	item["node"] = node
	_items.append(item)
	while _items.size() > MAX_VISIBLE:
		_remove(0)


func clear() -> void:
	while not _items.is_empty():
		_remove(0)


func get_count() -> int:
	return _items.size()


func get_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for it in _items:
		out.append(str(it["text"]))
	return out


func _remove(index: int) -> void:
	var node: Variant = _items[index].get("node")
	if node != null and is_instance_valid(node):
		(node as Node).queue_free()
	_items.remove_at(index)


func _process(delta: float) -> void:
	if _items.is_empty():
		return
	var dt := delta / maxf(Engine.time_scale, 0.05)
	var y := 0.0
	var i := 0
	while i < _items.size():
		var it: Dictionary = _items[i]
		var t := float(it["t"]) + dt
		var life := float(it["life"])
		it["t"] = t
		if t >= life + 0.35:
			_remove(i)
			continue
		if float(it["y"]) < 0.0:
			it["y"] = y
		else:
			it["y"] = lerpf(float(it["y"]), y, 1.0 - exp(-14.0 * dt))
		var node := it["node"] as UiCanvas
		var a_in := clampf(t / 0.22, 0.0, 1.0)
		var a_out := 1.0 - clampf((t - life) / 0.35, 0.0, 1.0)
		node.modulate.a = a_in * a_out
		node.position = Vector2(size.x - float(it["w"]) + (1.0 - ease(a_in, 0.35)) * 70.0, float(it["y"]))
		if float(it["bump"]) > 0.0:
			it["bump"] = maxf(float(it["bump"]) - dt * 3.0, 0.0)
			node.queue_redraw()
		y += float(it["h"]) + GAP
		i += 1


func _draw_item(c: UiCanvas, it: Dictionary) -> void:
	var f := UiStyle.font(&"bold")
	var w := float(it["w"])
	var h := float(it["h"])
	var col: Color = it["col"]
	c.draw_style_box(UiStyle.cached_box(&"toast"), Rect2(0.0, 0.0, w, h))
	c.draw_style_box(UiStyle._fill_box(col), Rect2(10.0, 12.0, 5.0, h - 24.0))
	UiIcons.draw(c, it["icon"], Vector2(42.0, h * 0.5), 26.0 + 8.0 * float(it["bump"]), col)
	if bool(it["multi"]):
		c.draw_multiline_string(f, Vector2(68.0, 11.0 + f.get_ascent(FONT_SIZE)), str(it["text"]),
				HORIZONTAL_ALIGNMENT_LEFT, MAX_TEXT_W, FONT_SIZE, 3, UiStyle.TEXT)
	else:
		UiStyle.text_in(c, f, Rect2(68.0, 0.0, w - 80.0, h), str(it["text"]), FONT_SIZE, UiStyle.TEXT)
	var count := int(it["count"])
	if count > 1:
		var badge := Rect2(-16.0, -8.0, 46.0, 28.0)
		c.draw_style_box(UiStyle._fill_box(col), badge)
		UiStyle.text_in(c, UiStyle.font(&"num"), badge, "x%d" % count, UiStyle.FS_TINY, UiStyle.NAVY_DEEP, HORIZONTAL_ALIGNMENT_CENTER)
