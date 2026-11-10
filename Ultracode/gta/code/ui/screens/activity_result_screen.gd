extends UiScreen
## Generic result panel for free-roam activities (races, range, stunt jumps, hobbies ... - never a
## mission). Opened by the UI autoload on EventBus.activity_finished(id, result) (deferred, so an
## activity system that opens it itself wins), or directly:
##     UI.open_screen("activity_result", {
##         "id": "street_race_1", "title": "Harbour Sprint", "subtitle": "Street race - 3 laps",
##         "passed": true, "medal": "gold",                  # gold | silver | bronze | "" (none)
##         "lines": [{"label": "Time", "value": "1:42.35", "best": true}, {"label": "Position", "value": "1st / 6"}],
##         "time": 102.35, "best_time": 99.8,                # optional; added as lines when present
##         "score": 4200, "reward": 500, "xp": {"driving": 4},
##         "new_record": true, "can_retry": true, "retry": Callable(),
##     })
## Unknown / missing keys are skipped; "stats" (Dictionary label -> value) is accepted as lines too.
## Retry: args.retry (Callable) if valid, else the activities system's retry_activity(id) /
## retry(id) / start_activity(id) / start(id) - the button is hidden when none exists.
## Pauses the game, hides the HUD; Enter retries (when possible), Esc / Close closes.

const PAUSES_GAME := true
const TIME_SCALE := 1.0
const LOCKS_INPUT := true
const SHOWS_MOUSE := true
const HIDES_HUD := true

const PANEL_W := 760.0
const MEDAL_COLORS := {
	"gold": Color(0.98, 0.78, 0.26), "silver": Color(0.8, 0.85, 0.9), "bronze": Color(0.86, 0.55, 0.32),
}
const MEDAL_NAMES := {"gold": "GOLD", "silver": "SILVER", "bronze": "BRONZE"}

var args: Dictionary = {}
var _medal: UiCanvas
var _header: UiHeader
var _status: Label
var _lines_box: VBoxContainer
var _reward_box: HBoxContainer
var _retry_btn: Button
var _close_btn: Button
var _hints: UiKeyHints
var _panel: UiPanel
var _t: float = 0.0
var _retried: bool = false
var _retry_path: String = ""       ## "callable" | method name on the activities system | ""


func _init() -> void:
	super()
	backdrop_alpha = 0.7


func _ready() -> void:
	var center := CenterContainer.new()
	UiKit.fill(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = UiPanel.new(&"SolidPanel", 14)
	_panel.custom_minimum_size = Vector2(PANEL_W, 0.0)
	center.add_child(_panel)
	_medal = UiCanvas.new(_draw_medal)
	_medal.custom_minimum_size = Vector2(PANEL_W - 60.0, 196.0)
	_panel.add(_medal)
	_header = UiKit.header("Activity", "")
	_header.title_size = UiStyle.FS_H1
	_panel.add(_header)
	_status = UiKit.label("", &"SectionLabel")
	_panel.add(_status)
	_lines_box = UiKit.vbox(4)
	_panel.add(_lines_box)
	_reward_box = UiKit.hbox(14)
	_panel.add(_reward_box)
	_panel.add(UiKit.spacer(Vector2(0, 6), false))
	var buttons := UiKit.hbox(16)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	_panel.add(buttons)
	_retry_btn = UiKit.button("Retry", retry, &"AccentButton")
	_retry_btn.custom_minimum_size = Vector2(200.0, 0.0)
	buttons.add_child(_retry_btn)
	_close_btn = UiKit.button("Continue", close_self)
	_close_btn.custom_minimum_size = Vector2(200.0, 0.0)
	buttons.add_child(_close_btn)
	_hints = UiKeyHints.new([{"key": "Enter", "text": "Select"}, {"action": "pause", "text": "Close"}], true)
	_panel.add(_hints)


func open(p_args: Dictionary) -> void:
	args = p_args.duplicate()
	_t = 0.0
	_retried = false
	var id := str(args.get("id", ""))
	var title := str(args.get("title", ""))
	if title == "" and id != "":
		var def: Variant = Registry.get_def("activities", id)
		title = str(HudRoot._def_get(def, "display_name", HudRoot._def_get(def, "name", id.capitalize())))
	_header.title = title if title != "" else "Activity"
	_header.subtitle = str(args.get("subtitle", ""))
	var passed := is_passed()
	var medal := get_medal()
	_header.accent = MEDAL_COLORS.get(medal, UiStyle.TEAL) if passed else UiStyle.BAD
	if bool(args.get("new_record", false)) and passed:
		_status.text = "NEW PERSONAL BEST"
		_status.add_theme_color_override("font_color", UiStyle.SUN)
	elif passed:
		_status.text = ("%s MEDAL" % MEDAL_NAMES[medal]) if MEDAL_NAMES.has(medal) else "COMPLETE"
		_status.add_theme_color_override("font_color", UiStyle.TEAL_LIGHT)
	else:
		_status.text = str(args.get("fail_reason", "NOT THIS TIME")).to_upper()
		_status.add_theme_color_override("font_color", UiStyle.CORAL)
	_build_lines()
	_build_rewards()
	_retry_path = _find_retry()
	_retry_btn.visible = _retry_path != "" and bool(args.get("can_retry", true))
	_retry_btn.text = "Try again" if not passed else "Retry"
	var hints: Array = []
	if _retry_btn.visible:
		hints.append({"key": "Enter", "text": "Select"})
	hints.append({"action": "pause", "text": "Close"})
	_hints.set_hints(hints)
	if _retry_btn.visible:
		_retry_btn.grab_focus()
	else:
		_close_btn.grab_focus()
	UiKit.sfx("activity_win" if passed else "ui_error", -2.0)
	_medal.queue_redraw()


func regain_focus() -> void:
	if _retry_btn.visible:
		_retry_btn.grab_focus()
	else:
		_close_btn.grab_focus()


func is_passed() -> bool:
	return bool(args.get("passed", args.get("success", true)))


func get_medal() -> String:
	var m := str(args.get("medal", "")).to_lower()
	return m if MEDAL_COLORS.has(m) else ""


func can_retry() -> bool:
	return _retry_btn != null and _retry_btn.visible


func get_line_count() -> int:
	return _lines_box.get_child_count() if _lines_box != null else 0


## Restart the activity (button / Enter). Closes the panel first so pause and input lock are
## released before the activity system takes over.
func retry() -> void:
	if _retried or _retry_path == "":
		return
	_retried = true
	var id := str(args.get("id", ""))
	var cb: Variant = args.get("retry", null)
	var path := _retry_path
	close_self()
	if path == "callable" and cb is Callable:
		(cb as Callable).call_deferred()
		return
	var acts := Game.get_system("activities")
	if acts != null and acts.has_method(path):
		acts.call_deferred(path, id)


func _find_retry() -> String:
	var cb: Variant = args.get("retry", null)
	if cb is Callable and (cb as Callable).is_valid():
		return "callable"
	if str(args.get("id", "")) == "":
		return ""
	var acts := Game.get_system("activities")
	if acts == null:
		return ""
	for m: String in ["retry_activity", "retry", "start_activity", "start"]:
		if acts.has_method(m):
			return m
	return ""


# --- content -----------------------------------------------------------------------------------------

func _build_lines() -> void:
	for ch in _lines_box.get_children():
		_lines_box.remove_child(ch)
		ch.queue_free()
	var rows: Array = []
	var src: Variant = args.get("lines", args.get("score_lines", null))
	if src is Array:
		for e: Variant in src:
			if e is Dictionary:
				rows.append(e)
	elif src is Dictionary:
		for k: Variant in src:
			rows.append({"label": str(k), "value": str(src[k])})
	var stats: Variant = args.get("stats", null)
	if stats is Dictionary:
		for k2: Variant in stats:
			rows.append({"label": str(k2), "value": str(stats[k2])})
	var labels: Array = []
	for r: Dictionary in rows:
		labels.append(str(r.get("label", "")).to_lower())
	if args.has("time") and not labels.has("time"):
		var best_t: float = float(args.get("best_time", -1.0))
		var tv := float(args["time"])
		rows.append({"label": "Time", "value": format_time(tv), "best": best_t > 0.0 and tv <= best_t + 0.001})
		if best_t > 0.0:
			rows.append({"label": "Previous best" if tv < best_t - 0.001 else "Best time", "value": format_time(best_t),
					"color": UiStyle.MUTED})
	if args.has("score") and not labels.has("score"):
		rows.append({"label": "Score", "value": _fmt_num(args["score"]), "best": bool(args.get("new_record", false)) and not args.has("time")})
	for r: Dictionary in rows:
		_lines_box.add_child(_line_row(r))


func _line_row(r: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UiStyle.box(Color(1, 1, 1, 0.05), 10, UiStyle.CLEAR, 0, 0, 18, 8))
	var h := UiKit.hbox(12)
	row.add_child(h)
	var n := UiKit.label(str(r.get("label", "")), &"MutedLabel")
	n.add_theme_font_size_override("font_size", UiStyle.FS_BODY)
	h.add_child(n)
	h.add_child(UiKit.spacer(Vector2.ZERO, true))
	if bool(r.get("best", false)):
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.SUN, 8, UiStyle.CLEAR, 0, 0, 10, 2))
		var cl := UiKit.label("BEST", &"SmallLabel")
		cl.add_theme_color_override("font_color", UiStyle.NAVY_DEEP)
		cl.add_theme_font_override("font", UiStyle.font(&"head"))
		chip.add_child(cl)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(chip)
	var v := UiKit.label(str(r.get("value", "")), &"ValueLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	var vc: Variant = r.get("color", UiStyle.TEXT)
	v.add_theme_color_override("font_color", vc if vc is Color else UiStyle.TEXT)
	v.add_theme_font_override("font", UiStyle.font(&"num"))
	v.add_theme_font_size_override("font_size", UiStyle.FS_LARGE)
	h.add_child(v)
	return row


func _build_rewards() -> void:
	for ch in _reward_box.get_children():
		_reward_box.remove_child(ch)
		ch.queue_free()
	var reward := int(args.get("reward", args.get("money", 0)))
	if reward != 0:
		_reward_box.add_child(_chip(&"dollar", ("+" if reward > 0 else "") + UiStyle.money(reward), UiStyle.SUN))
	var xp: Variant = args.get("xp", null)
	if xp is Dictionary:
		for skill: Variant in xp:
			var nice := str(Skills.DISPLAY_NAMES.get(str(skill), str(skill).capitalize()))
			_reward_box.add_child(_chip(UiIcons.skill_icon(str(skill)), "%s +%s" % [nice, _fmt_num(xp[skill])], UiStyle.TEAL_LIGHT))
	elif args.has("skill"):
		var sk := str(args["skill"])
		var sk_nice := str(Skills.DISPLAY_NAMES.get(sk, sk.capitalize()))
		_reward_box.add_child(_chip(UiIcons.skill_icon(sk), "%s +%s" % [sk_nice, _fmt_num(args.get("skill_xp", 1))], UiStyle.TEAL_LIGHT))
	_reward_box.visible = _reward_box.get_child_count() > 0


func _chip(icon: StringName, text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(Color(col, 0.14), 12, Color(col, 0.6), 2, 0, 14, 6))
	var h := UiKit.hbox(8)
	p.add_child(h)
	h.add_child(UiKit.icon(icon, 26.0, col))
	var l := UiKit.label(text, &"ValueLabel")
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", UiStyle.FS_BODY)
	h.add_child(l)
	return p


static func format_time(sec: float) -> String:
	var s := maxf(sec, 0.0)
	var m := int(s / 60.0)
	var rest := s - m * 60.0
	return "%d:%05.2f" % [m, rest]


static func _fmt_num(v: Variant) -> String:
	if v is float:
		return str(int(round(v))) if absf(v - round(v)) < 0.01 else "%.1f" % v
	return str(v)


# --- frame / drawing ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _t < 2.0:
		_t += delta
		_medal.queue_redraw()
	elif is_passed() and get_medal() != "":
		_t += delta
		_medal.queue_redraw()


func _draw_medal(c: UiCanvas) -> void:
	var ctr := Vector2(c.size.x * 0.5, 98.0)
	var pop := clampf(_t / 0.35, 0.0, 1.0)
	var sc := 1.0 + 0.18 * sin(pop * PI) if pop < 1.0 else 1.0
	sc *= ease(pop, 0.4)
	var passed := is_passed()
	var medal := get_medal()
	var col: Color = MEDAL_COLORS.get(medal, UiStyle.TEAL) if passed else UiStyle.DIM
	# rays
	if passed:
		var spin := _t * 0.35
		for i in 12:
			var a := spin + TAU * float(i) / 12.0
			var d := Vector2(cos(a), sin(a))
			c.draw_line(ctr + d * 92.0 * sc, ctr + d * 118.0 * sc, Color(col, 0.35), 5.0, true)
	if sc <= 0.01:
		return
	c.draw_set_transform(ctr, 0.0, Vector2(sc, sc))
	if passed and medal != "":
		# ribbon
		c.draw_colored_polygon(PackedVector2Array([Vector2(-52, -96), Vector2(-14, -96), Vector2(18, -40), Vector2(-20, -40)]), UiStyle.CORAL)
		c.draw_colored_polygon(PackedVector2Array([Vector2(14, -96), Vector2(52, -96), Vector2(20, -40), Vector2(-18, -40)]), UiStyle.TEAL)
	c.draw_circle(Vector2(0, 6), 74.0, Color(0, 0, 0, 0.35), true, -1.0, true)
	c.draw_circle(Vector2.ZERO, 72.0, col, true, -1.0, true)
	c.draw_circle(Vector2.ZERO, 58.0, col.darkened(0.18), true, -1.0, true)
	c.draw_arc(Vector2.ZERO, 66.0, 0.0, TAU, 64, Color(1, 1, 1, 0.45), 3.0, true)
	var glyph: StringName = &"star"
	if not passed:
		glyph = &"close"
	elif medal == "":
		glyph = &"check"
	UiIcons.draw(c, glyph, Vector2(0, 3), 70.0, Color(UiStyle.NAVY_DEEP, 0.55))
	UiIcons.draw(c, glyph, Vector2.ZERO, 70.0, UiStyle.CREAM if passed else UiStyle.TEXT)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
