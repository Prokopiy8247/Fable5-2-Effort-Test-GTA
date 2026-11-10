extends Control
## Binocular mask for the viewpoint binoculars (interactions system): two overlapping round
## eyepieces (canvas shader, one draw call), a thin range reticle, the zoom level and the key hints.
## Shown while the player is in state "int_view" (the HUD is hidden meanwhile).

const MASK_SHADER := """
shader_type canvas_item;
uniform float aspect = 1.7778;
uniform float radius = 0.43;
uniform float sep = 0.27;
uniform float soft = 0.025;
void fragment() {
	vec2 p = vec2((UV.x - 0.5) * aspect, UV.y - 0.5);
	float d1 = length(p - vec2(-sep, 0.0));
	float d2 = length(p - vec2(sep, 0.0));
	float d = min(d1, d2);
	float inside = 1.0 - smoothstep(radius - soft, radius, d);
	float rim = smoothstep(radius - 0.10, radius, d) * inside;
	COLOR = vec4(0.012, 0.02, 0.04, max(1.0 - inside, rim * 0.55));
}
"""

var zoom_text: String = ""
var hint_text: String = "Mouse: look   Wheel / RMB: zoom   E or move: step away"

var _mask: ColorRect = null
var _mat: ShaderMaterial = null
var _font: Font = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask = ColorRect.new()
	_mask.name = "Mask"
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = MASK_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mask.material = _mat
	add_child(_mask)
	_font = ThemeDB.fallback_font
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	if _mat != null:
		_mat.set_shader_parameter(&"aspect", size.x / maxf(size.y, 1.0))
	queue_redraw()


func set_zoom_text(t: String) -> void:
	if t != zoom_text:
		zoom_text = t
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var col := Color(0.95, 0.85, 0.55, 0.55)
	# range reticle: a horizontal scale with ticks in the middle of the view
	var w := size.y * 0.16
	draw_line(c - Vector2(w, 0.0), c + Vector2(w, 0.0), col, 1.5)
	for i in range(-4, 5):
		var x := c.x + float(i) * w / 4.0
		var h := 9.0 if i % 2 == 0 else 5.0
		draw_line(Vector2(x, c.y - h), Vector2(x, c.y + h), col, 1.5)
	draw_line(c - Vector2(0.0, w * 0.35), c + Vector2(0.0, w * 0.35), col, 1.0)
	if _font != null:
		var fs := int(maxf(14.0, size.y * 0.024))
		if zoom_text != "":
			draw_string(_font, Vector2(c.x - size.y * 0.42, c.y + size.y * 0.30), zoom_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.85, 0.55, 0.9))
		draw_string(_font, Vector2(0.0, size.y - size.y * 0.045), hint_text, HORIZONTAL_ALIGNMENT_CENTER,
				size.x, fs, Color(1, 1, 1, 0.75))
