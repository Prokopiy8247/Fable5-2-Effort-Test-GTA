extends CanvasLayer
## Fallback activity tracker of the activities module. The real HUD widget belongs to the UI
## module (it polls activity_system.get_hud_info()); this small panel is only created when no
## such widget exists (no node in group "hud_activity_widget" and no activity script in the HUD),
## so a running race / course always shows its clock. Polls at 10 Hz, rebuilds strings only when
## the shown values change. Colours follow the project UI identity (navy glass, coral / sun accents).

const POLL := 0.1
const NAVY_GLASS := Color(0.043, 0.086, 0.149, 0.86)
const CORAL := Color(0.933, 0.494, 0.392)
const SUN := Color(0.969, 0.788, 0.282)
const CREAM := Color(0.965, 0.937, 0.878)
const MUTED := Color(0.655, 0.722, 0.8)

var sys: Node = null
var panel: PanelContainer = null
var _title: Label = null
var _big: Label = null
var _line: Label = null
var _hint: Label = null
var _t: float = 0.0
var _last_big: String = ""
var _last_line: String = ""
var _last_hint: String = ""
var _last_title: String = ""


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	panel = PanelContainer.new()
	panel.name = "ActivityPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = NAVY_GLASS
	sb.set_corner_radius_all(14)
	sb.border_color = CORAL
	sb.border_width_bottom = 3
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -170.0
	panel.offset_right = 170.0
	panel.offset_top = 34.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	_title = _label(box, 17, CORAL)
	_big = _label(box, 44, CREAM)
	_line = _label(box, 20, SUN)
	_hint = _label(box, 17, MUTED)
	panel.visible = false


func _label(parent: Control, size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = POLL
	if sys == null or not is_instance_valid(sys) or not sys.has_method("get_hud_info"):
		panel.visible = false
		return
	var info: Dictionary = sys.call("get_hud_info")
	if not bool(info.get("active", false)):
		panel.visible = false
		return
	panel.visible = true
	_apply_text(_title, str(info.get("title", "")).to_upper(), "_last_title")
	var t := float(info.get("timer", 0.0))
	var m := int(t / 60.0)
	_apply_text(_big, "%d:%04.1f" % [m, t - m * 60.0], "_last_big")
	var line := ""
	var total := int(info.get("total", 0))
	if str(info.get("kind", "")) == "race" and total > 0:
		line = "CHECKPOINT %d / %d" % [mini(int(info.get("checkpoint", 0)) + 1, total), total]
	elif str(info.get("kind", "")) == "shooting_range":
		line = "SCORE %d   ROUND %d / %d" % [int(info.get("score", 0)), maxi(int(info.get("lap", 1)), 1), total]
	else:
		line = "%d m" % int(info.get("score", 0))
	_apply_text(_line, line, "_last_line")
	_apply_text(_hint, str(info.get("hint", "")), "_last_hint")


func _apply_text(l: Label, s: String, cache: String) -> void:
	if str(get(cache)) == s:
		return
	set(cache, s)
	l.text = s
