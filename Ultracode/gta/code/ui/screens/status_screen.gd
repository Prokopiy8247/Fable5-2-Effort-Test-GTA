extends UiScreen
## Status screen (spec 46A): the seven use-based skills with bars, session info and free-roam
## statistics. Read-only; skills grow by doing the activity, nothing here gates anything.
## UI.open_screen("status")

const PAUSES_GAME := true
const TIME_SCALE := 1.0
const LOCKS_INPUT := true
const SHOWS_MOUSE := true
const HIDES_HUD := true

const SKILL_NOTES := {
	"stamina": "Sprint, cycle and swim for longer",
	"shooting": "Steadier recoil, quicker reloads",
	"strength": "Harder melee hits, tougher in a fight",
	"stealth": "Quieter movement, harder to spot",
	"driving": "Better grip and recovery at the limit",
	"flying": "Less turbulence, crisper aircraft control",
	"lung": "Longer breath underwater",
}
const SKILL_COLORS := [UiStyle.SUN, UiStyle.CORAL, UiStyle.CORAL_HOT, UiStyle.TEAL_LIGHT, UiStyle.TEAL, Color(0.56, 0.79, 0.91), Color(0.72, 0.65, 0.88)]

var _skills_canvas: UiCanvas
var _session_rows: Dictionary = {}
var _stat_rows: Dictionary = {}
var _header: UiHeader
var _timer: float = 0.0
var _levels: Dictionary = {}


func _init() -> void:
	super()
	backdrop_alpha = 0.78


func _ready() -> void:
	var margin := UiKit.margin(null, 80, 56, 80, 96)
	UiKit.fill(margin)
	add_child(margin)
	var col := UiKit.vbox(22)
	margin.add_child(col)
	_header = UiKit.header("Status", "Skills improve by doing - nothing here is ever required", UiStyle.money(Game.money))
	_header.title_size = UiStyle.FS_H1
	col.add_child(_header)
	var row := UiKit.hbox(30)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	var left := UiPanel.new(&"GlassPanel", 10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	row.add_child(left)
	left.add(UiKit.label("SKILLS", &"SectionLabel"))
	_skills_canvas = UiCanvas.new(_draw_skills)
	_skills_canvas.custom_minimum_size = Vector2(520.0, 7.0 * 84.0)
	_skills_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skills_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add(_skills_canvas)

	var right := UiKit.vbox(24)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var session := UiPanel.new(&"GlassPanel", 6)
	right.add_child(session)
	session.add(UiKit.label("SESSION", &"SectionLabel"))
	var sgrid := UiKit.grid(2, 44, 4)
	session.add(sgrid)
	for key: String in ["Play time", "Location", "Time", "Weather", "Health", "Armor", "Wanted", "Weapons"]:
		var r := UiKit.stat_row(key, "-")
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sgrid.add_child(r)
		_session_rows[key] = r
	var stats_panel := UiPanel.new(&"GlassPanel", 6)
	stats_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(stats_panel)
	stats_panel.add(UiKit.label("STATISTICS", &"SectionLabel"))
	var grid := UiKit.grid(2, 44, 4)
	stats_panel.add(grid)
	for key: String in UiStats.ORDER:
		var r2 := UiKit.stat_row(str(UiStats.LABELS.get(key, key)), "0")
		r2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(r2)
		_stat_rows[key] = r2

	var hints := UiKeyHints.new([{"action": "pause", "text": "Back"}, {"action": "map", "text": "Map"}])
	add_child(hints)
	hints.anchor_left = 0.0
	hints.anchor_right = 1.0
	hints.anchor_top = 1.0
	hints.anchor_bottom = 1.0
	hints.offset_left = 84.0
	hints.offset_right = -84.0
	hints.offset_top = -80.0
	hints.offset_bottom = -34.0
	_refresh()


func open(_args: Dictionary) -> void:
	_refresh()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		_refresh()


func _refresh() -> void:
	_header.right_text = UiStyle.money(Game.money)
	var changed := false
	for s: String in Skills.SKILLS:
		var lvl := Skills.get_level(s)
		if not _levels.has(s) or absf(float(_levels[s]) - lvl) > 0.01:
			_levels[s] = lvl
			changed = true
	if changed and _skills_canvas != null:
		_skills_canvas.queue_redraw()
	var pl: Node3D = Game.player if Game.has_player() else null
	var district := "-"
	var w := Game.world
	if w != null and is_instance_valid(w) and w.has_method("get_district") and pl != null:
		district = UiMapData.district_name(str(w.call("get_district", Game.get_player_position())))
	_set_row(_session_rows, "Play time", UiStyle.duration(Game.playtime_seconds))
	_set_row(_session_rows, "Location", district)
	_set_row(_session_rows, "Time", "Day %d, %s" % [int(UiKit.num(WorldClock, &"day", 1.0)), WorldClock.get_time_string()])
	_set_row(_session_rows, "Weather", str(Weather.current).capitalize())
	_set_row(_session_rows, "Health", "%d / %d" % [int(ceil(UiKit.num(pl, &"health", 0.0))), int(UiKit.num(pl, &"max_health", 100.0))] if pl != null else "-")
	_set_row(_session_rows, "Armor", "%d / %d" % [int(ceil(UiKit.num(pl, &"armor", 0.0))), int(UiKit.num(pl, &"max_armor", 100.0))] if pl != null else "-")
	_set_row(_session_rows, "Wanted", "Clean" if Wanted.level <= 0 else "%d / 5" % Wanted.level)
	var weapons := "-"
	if pl != null:
		var inv: Variant = pl.get(&"inventory")
		if inv is Object and is_instance_valid(inv) and (inv as Object).has_method("get_weapons"):
			var list: Variant = (inv as Object).call("get_weapons")
			if list is Array:
				weapons = str((list as Array).size())
	_set_row(_session_rows, "Weapons", weapons)
	var st: UiStats = UI.stats
	if st != null:
		for key: String in _stat_rows:
			UiKit.set_stat_value(_stat_rows[key], st.format(key))


func _set_row(rows: Dictionary, key: String, value: String) -> void:
	if rows.has(key):
		UiKit.set_stat_value(rows[key], value)


func _draw_skills(c: UiCanvas) -> void:
	var skills: Array[String] = Skills.SKILLS
	var n := skills.size()
	if n == 0:
		return
	var row_h := minf(c.size.y / float(n), 96.0)
	var bold := UiStyle.font(&"bold")
	var body := UiStyle.font(&"body")
	var num := UiStyle.font(&"num")
	for i in n:
		var s := skills[i]
		var y := i * row_h
		var lvl := Skills.get_level(s)
		var col: Color = SKILL_COLORS[i % SKILL_COLORS.size()]
		# icon disc
		var ic := Vector2(34.0, y + row_h * 0.5 - 4.0)
		c.draw_circle(ic, 29.0, Color(1, 1, 1, 0.07), true, -1.0, true)
		c.draw_arc(ic, 29.0, 0.0, TAU, 40, Color(col, 0.7), 2.0, true)
		UiIcons.draw(c, UiIcons.skill_icon(s), ic, 30.0, col)
		var x := 84.0
		var name_text := str(Skills.DISPLAY_NAMES.get(s, s.capitalize()))
		UiStyle.text(c, bold, Vector2(x, y + 28.0), name_text, UiStyle.FS_BODY, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
		var name_w := UiStyle.text_width(bold, name_text, UiStyle.FS_BODY)
		UiStyle.text(c, body, Vector2(x + name_w + 18.0, y + 28.0), str(SKILL_NOTES.get(s, "")), UiStyle.FS_TINY, UiStyle.MUTED,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
		UiStyle.text(c, num, Vector2(c.size.x - 130.0, y + 30.0), "%d" % int(lvl), UiStyle.FS_LARGE, col, HORIZONTAL_ALIGNMENT_RIGHT, 82.0, false)
		UiStyle.text(c, num, Vector2(c.size.x - 44.0, y + 30.0), "/100", UiStyle.FS_TINY, UiStyle.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
		var bar := Rect2(x, y + 42.0, c.size.x - x - 6.0, 14.0)
		UiStyle.draw_bar(c, bar, lvl / 100.0, col, false)
		# quarter ticks
		for k in range(1, 4):
			var tx := bar.position.x + bar.size.x * 0.25 * k
			c.draw_line(Vector2(tx, bar.position.y), Vector2(tx, bar.end.y), Color(UiStyle.NAVY_DEEP, 0.55), 2.0)
