extends Control
## Before / after stat bars for the weapon shop and the workbench (ECONOMY A).
## rows: [{"label": String, "value": 0..1, "after": 0..1 or -1 (no comparison), "text": String,
##         "after_text": String, "invert": bool (lower is better: the colours swap)}]
## A gain is drawn as a GOOD-coloured extension past the current value, a loss as a BAD tail.

const ROW_H := 34.0
const LABEL_W := 190.0
const VALUE_W := 150.0

var rows: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_rows(p_rows: Array) -> void:
	rows = p_rows
	custom_minimum_size = Vector2(360.0, ROW_H * float(rows.size()))
	queue_redraw()


func _draw() -> void:
	var body := UiStyle.font(&"body")
	var num := UiStyle.font(&"num")
	var x0 := LABEL_W
	var x1 := maxf(size.x - VALUE_W, x0 + 60.0)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var y := float(i) * ROW_H
		UiStyle.text_in(self, body, Rect2(0.0, y, LABEL_W - 12.0, ROW_H), str(r.get("label", "")), UiStyle.FS_SMALL, UiStyle.MUTED)
		var bar := Rect2(x0, y + ROW_H * 0.5 - 7.0, x1 - x0, 14.0)
		draw_style_box(UiStyle.cached_box(&"track_dark"), bar)
		var v := clampf(float(r.get("value", 0.0)), 0.0, 1.0)
		var a := float(r.get("after", -1.0))
		var invert := bool(r.get("invert", false))
		var txt := str(r.get("text", ""))
		var txt_col := UiStyle.TEXT
		if a >= 0.0 and absf(a - v) > 0.002:
			a = clampf(a, 0.0, 1.0)
			var better := (a > v) != invert
			var col := UiStyle.GOOD if better else UiStyle.BAD
			_pill(Rect2(bar.position, Vector2(bar.size.x * maxf(a, v), bar.size.y)), col)
			_pill(Rect2(bar.position, Vector2(bar.size.x * minf(a, v), bar.size.y)), UiStyle.TEAL)
			var at := str(r.get("after_text", ""))
			if at != "":
				txt = at
			txt_col = col
		else:
			_pill(Rect2(bar.position, Vector2(bar.size.x * v, bar.size.y)), UiStyle.TEAL)
		UiStyle.text_in(self, num, Rect2(x1 + 10.0, y, VALUE_W - 10.0, ROW_H), txt, UiStyle.FS_SMALL, txt_col, HORIZONTAL_ALIGNMENT_RIGHT)


func _pill(r: Rect2, col: Color) -> void:
	if r.size.x <= 0.5:
		return
	r.size.x = maxf(r.size.x, r.size.y)
	draw_style_box(UiStyle._fill_box(col), r)
