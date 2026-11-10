extends UiScreen
## Pause menu: resume, map, status, settings, save, load, quit.
## UI.open_screen("pause")            -> home page
## UI.open_screen("pause", {"page": "settings", "tab": 2})   -> straight into a settings tab
## Settings are applied live through Settings.set_value() and written to disk when the page / the
## menu closes. Safe-by-default GPU policy (spec 3A): FPS cap list is 30 / 60 / 120, render scale
## never above 100 %, V-Sync on by default (the clamps themselves live in core/settings.gd).

const PAUSES_GAME := true
const TIME_SCALE := 1.0
const LOCKS_INPUT := true
const SHOWS_MOUSE := true
const HIDES_HUD := true

const MANUAL_SLOT := "manual"
const QUICK_SLOT := "quick"
const SETTINGS_TABS := ["Controls", "Audio", "Display", "World"]
const FPS_CAPS := [30, 60, 120]
const SHADOW_NAMES := ["Off", "Low", "Medium", "High"]
const CONTROLS_HELP := [
	["W A S D", "Move / drive"], ["Mouse", "Look / aim"], ["Shift", "Sprint"], ["Space", "Jump / handbrake"],
	["C", "Crouch"], ["Ctrl", "Stealth"], ["Q", "Take cover"], ["F", "Enter / exit vehicle"],
	["E", "Interact"], ["LMB", "Fire / punch"], ["RMB", "Aim"], ["R", "Reload"],
	["Tab", "Weapon wheel"], ["1-8", "Weapon slots"], ["G", "Throw grenade"], ["V", "Camera view"],
	["M", "Map"], ["P", "Phone"], ["H", "Horn"], ["L", "Headlights"],
	["F5", "Quick save"], ["F9", "Quick load"], ["F3", "Debug overlay"], ["Esc", "Pause"],
]

var _buttons: Dictionary = {}          ## id -> Button
var _right: UiPanel
var _page: String = ""
var _tab: int = 0
var _tabs: UiTabBar
var _settings_body: VBoxContainer
var _first_row: Control = null
var _last_button: String = "resume"
var _dirty: bool = false
var _info_rows: Dictionary = {}
var _info_timer: float = 0.0


func _init() -> void:
	super()
	backdrop_alpha = 0.72


func _ready() -> void:
	var margin := UiKit.margin(null, 80, 64, 80, 96)
	UiKit.fill(margin)
	add_child(margin)
	var row := UiKit.hbox(36)
	margin.add_child(row)

	var left := UiPanel.new(&"GlassPanel", 6)
	left.custom_minimum_size.x = 480.0
	row.add_child(left)
	var title := UiKit.label("HALCYON BAY", &"HeaderLabel")
	left.add(title)
	var paused := UiKit.label("GAME PAUSED", &"SectionLabel")
	paused.add_theme_color_override("font_color", UiStyle.CORAL)
	left.add(paused)
	left.add(UiKit.separator())
	_add_entry(left, "resume", "Resume", &"play")
	_add_entry(left, "map", "Map", &"map")
	_add_entry(left, "status", "Status", &"stats")
	_add_entry(left, "settings", "Settings", &"gear")
	_add_entry(left, "save", "Save Game", &"save")
	_add_entry(left, "load", "Load Game", &"load")
	_add_entry(left, "quit", "Quit", &"power")
	left.add(UiKit.spacer())
	left.add(UiKit.separator())
	var money := UiKit.label(UiStyle.money(Game.money), &"MoneyLabel")
	left.add(money)
	left.add(UiKit.label("No missions. No objectives. The city is yours.", &"MutedLabel"))

	_right = UiPanel.new(&"GlassPanel", 14)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_right)

	var hints := UiKeyHints.new([
		{"keys": ["W", "S"], "text": "Navigate"}, {"keys": ["A", "D"], "text": "Adjust"},
		{"key": "Enter", "text": "Select"}, {"action": "pause", "text": "Back"},
	])
	add_child(hints)
	hints.anchor_left = 0.0
	hints.anchor_right = 1.0
	hints.anchor_top = 1.0
	hints.anchor_bottom = 1.0
	hints.offset_left = 84.0
	hints.offset_right = -84.0
	hints.offset_top = -80.0
	hints.offset_bottom = -34.0
	_show_home()


func open(args: Dictionary) -> void:
	_refresh_load_button()
	if str(args.get("page", "")) == "settings":
		_tab = clampi(int(args.get("tab", 0)), 0, SETTINGS_TABS.size() - 1)
		_show_settings()
	else:
		_focus_button(str(args.get("focus", "resume")))


func close() -> void:
	_flush_settings()


func regain_focus() -> void:
	_refresh_load_button()
	_focus_button(_last_button)


func handle_back() -> bool:
	if super():
		return true
	if _page == "settings":
		_flush_settings()
		_show_home()
		_focus_button("settings")
		return true
	return false


func _process(delta: float) -> void:
	if _page != "home":
		return
	_info_timer += delta
	if _info_timer >= 0.5:
		_info_timer = 0.0
		_refresh_info()


# --- left menu -------------------------------------------------------------------------------------

func _add_entry(panel: UiPanel, id: String, text: String, icon: StringName) -> void:
	var b := UiKit.button("      " + text.to_upper(), _on_entry.bind(id), &"MenuEntryButton")
	b.custom_minimum_size.y = 64.0
	var ic := UiIconRect.new(icon, 30.0, UiStyle.TEAL_LIGHT)
	ic.position = Vector2(26.0, 17.0)
	ic.size = Vector2(30.0, 30.0)
	b.add_child(ic)
	panel.add(b)
	_buttons[id] = b


func _focus_button(id: String) -> void:
	var b: Button = _buttons.get(id, _buttons["resume"])
	if b.disabled:
		b = _buttons["resume"]
	b.grab_focus.call_deferred()


func _refresh_load_button() -> void:
	var has := SaveSystem.has_save(MANUAL_SLOT) or SaveSystem.has_save(QUICK_SLOT)
	(_buttons["load"] as Button).disabled = not has
	(_buttons["load"] as Button).focus_mode = Control.FOCUS_ALL if has else Control.FOCUS_NONE


func _on_entry(id: String) -> void:
	_last_button = id
	match id:
		"resume":
			close_self()
		"map":
			UI.open_screen("map")
		"status":
			UI.open_screen("status")
		"settings":
			_show_settings()
		"save":
			var ok: bool = SaveSystem.save_game(MANUAL_SLOT)
			UI.notify("Game saved" if ok else "Save failed", "good" if ok else "bad")
			_refresh_load_button()
		"load":
			var dlg := confirm("Load game?", "Progress since the last save will be lost.", "Load", "Cancel")
			dlg.confirmed.connect(_do_load)
			dlg.closed.connect(_after_dialog)
		"quit":
			var dlg2 := confirm("Quit Halcyon Bay?", "Unsaved progress will be lost.", "Quit", "Stay", true)
			dlg2.confirmed.connect(_do_quit)
			dlg2.closed.connect(_after_dialog)


func _after_dialog(_accepted: bool) -> void:
	if is_inside_tree() and visible:
		_focus_button(_last_button)


func _newest_slot() -> String:
	var best := ""
	var best_time := -1
	for slot: String in [MANUAL_SLOT, QUICK_SLOT]:
		if SaveSystem.has_save(slot):
			var t := int(FileAccess.get_modified_time(SaveSystem.slot_path(slot)))
			if t > best_time:
				best_time = t
				best = slot
	return best


func _do_load() -> void:
	var slot := _newest_slot()
	if slot == "":
		UI.notify("No save found", "warn")
		return
	close_self()
	var ok: bool = SaveSystem.load_game(slot)
	UI.notify("Game loaded" if ok else "Load failed", "good" if ok else "bad")


func _do_quit() -> void:
	_flush_settings()
	get_tree().quit()


# --- home page -------------------------------------------------------------------------------------

func _show_home() -> void:
	_page = "home"
	_right.clear()
	_first_row = null
	_right.add(UiKit.header("Session", "Free roam in Halcyon Bay"))
	var grid := UiKit.grid(2, 48, 6)
	_right.add(grid)
	_info_rows.clear()
	for key: String in ["Location", "Time", "Weather", "Wanted", "Play time", "Health"]:
		var r := UiKit.stat_row(key, "-")
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(r)
		_info_rows[key] = r
	_refresh_info()
	_right.add(UiKit.separator())
	_right.add(UiKit.label("CONTROLS", &"SectionLabel"))
	var help := UiCanvas.new(_draw_controls)
	help.custom_minimum_size = Vector2(600.0, 8.0 * 46.0)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add(help)


func _refresh_info() -> void:
	if _info_rows.is_empty():
		return
	var district := "-"
	var w := Game.world
	if w != null and is_instance_valid(w) and w.has_method("get_district") and Game.has_player():
		district = UiMapData.district_name(str(w.call("get_district", Game.get_player_position())))
	UiKit.set_stat_value(_info_rows["Location"], district)
	UiKit.set_stat_value(_info_rows["Time"], "Day %d, %s" % [int(UiKit.num(WorldClock, &"day", 1.0)), WorldClock.get_time_string()])
	UiKit.set_stat_value(_info_rows["Weather"], str(Weather.current).capitalize())
	UiKit.set_stat_value(_info_rows["Wanted"], "Clean" if Wanted.level <= 0 else "%d / 5" % Wanted.level)
	UiKit.set_stat_value(_info_rows["Play time"], UiStyle.duration(Game.playtime_seconds))
	var hp := "-"
	if Game.has_player():
		hp = "%d  +%d armor" % [int(ceil(UiKit.num(Game.player, &"health", 0.0))), int(ceil(UiKit.num(Game.player, &"armor", 0.0)))]
	UiKit.set_stat_value(_info_rows["Health"], hp)


func _draw_controls(c: UiCanvas) -> void:
	var cols := 3 if c.size.x >= 900.0 else 2
	var rows := int(ceil(float(CONTROLS_HELP.size()) / float(cols)))
	var col_w := c.size.x / float(cols)
	var row_h := minf(50.0, maxf(c.size.y / float(rows), 36.0))
	var body := UiStyle.font(&"body")
	for i in CONTROLS_HELP.size():
		@warning_ignore("integer_division")
		var col := i / rows
		var r := i % rows
		var x := col * col_w
		var y := r * row_h
		var entry: Array = CONTROLS_HELP[i]
		var kw := UiStyle.draw_keycap(c, Vector2(x, y + 4.0), str(entry[0]), UiStyle.FS_TINY)
		UiStyle.text_in(c, body, Rect2(x + maxf(kw, 112.0) + 14.0, y + 2.0, col_w - maxf(kw, 112.0) - 18.0, UiStyle.FS_TINY + 16.0), str(entry[1]), UiStyle.FS_SMALL, UiStyle.TEXT)


# --- settings page ---------------------------------------------------------------------------------

func _show_settings() -> void:
	_page = "settings"
	_right.clear()
	_right.add(UiKit.header("Settings", "Changes apply immediately"))
	_tabs = UiTabBar.new(SETTINGS_TABS, _tab)
	_tabs.tab_changed.connect(_on_tab)
	_right.add(_tabs)
	_settings_body = UiKit.vbox(8)
	_settings_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add(_settings_body)
	_fill_tab()
	_focus_first_row()


func _on_tab(index: int) -> void:
	_tab = index
	_fill_tab()
	_focus_first_row()


func _focus_first_row() -> void:
	if _first_row != null and is_instance_valid(_first_row):
		if _first_row is UiSliderRow:
			(_first_row as UiSliderRow).grab.call_deferred()
		else:
			_first_row.grab_focus.call_deferred()


func _fill_tab() -> void:
	for ch in _settings_body.get_children():
		_settings_body.remove_child(ch)
		ch.queue_free()
	_first_row = null
	match _tab:
		0:
			_slider("Mouse sensitivity", "mouse_sensitivity", 0.0005, 0.006, 0.0001, "float1", 1000.0)
			_toggle("Invert Y axis", "invert_y")
			_slider("Field of view", "fov", 55.0, 100.0, 1.0, "deg")
			_slider("Camera shake", "camera_shake", 0.0, 1.0, 0.05, "percent")
			_note("Sensitivity and FOV apply to the on-foot, aiming and vehicle cameras.")
		1:
			_slider("Master volume", "master_volume", 0.0, 1.0, 0.05, "percent")
			_slider("Effects volume", "sfx_volume", 0.0, 1.0, 0.05, "percent")
			_slider("Music / radio volume", "music_volume", 0.0, 1.0, 0.05, "percent")
			_slider("Ambience volume", "ambience_volume", 0.0, 1.0, 0.05, "percent")
			_toggle("Subtitles", "subtitles")
		2:
			_toggle("V-Sync", "vsync")
			var cap := int(Settings.get_value("max_fps"))
			var cap_idx := maxi(FPS_CAPS.find(cap), 0) if FPS_CAPS.has(cap) else 1
			_option("Max FPS", ["30", "60", "120"], cap_idx, func(i: int) -> void: _apply_setting("max_fps", FPS_CAPS[i]))
			_slider("Render scale", "render_scale", 0.5, 1.0, 0.05, "percent")
			_option("Shadow quality", SHADOW_NAMES, clampi(int(Settings.get_value("shadows")), 0, 3), func(i: int) -> void: _apply_setting("shadows", i))
			_toggle("Performance overlay (F3)", "show_fps")
			_note("V-Sync and the FPS cap keep GPU load bounded. Render scale never exceeds 100 %.")
		3:
			_slider("Traffic density", "traffic_density", 0.0, 1.5, 0.1, "percent")
			_slider("Pedestrian density", "ped_density", 0.0, 1.5, 0.1, "percent")
			_note("Density changes take effect as the streets repopulate around you.")
	var reset := UiKit.button("Reset this page to defaults", _reset_tab, &"GhostButton")
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_settings_body.add_child(UiKit.spacer(Vector2(0, 4), false))
	_settings_body.add_child(reset)


func _register_row(row: Control) -> void:
	_settings_body.add_child(row)
	if _first_row == null:
		_first_row = row


func _slider(label: String, key: String, lo: float, hi: float, step: float, fmt: String, display_scale: float = 1.0) -> void:
	var row := UiSliderRow.new(label, lo, hi, step, clampf(float(Settings.get_value(key)), lo, hi), fmt, display_scale)
	row.value_changed.connect(func(v: float) -> void: _apply_setting(key, v))
	_register_row(row)


func _toggle(label: String, key: String) -> void:
	var row := UiOptionRow.new(label, ["Off", "On"], 1 if bool(Settings.get_value(key)) else 0)
	row.changed.connect(func(i: int) -> void: _apply_setting(key, i == 1))
	_register_row(row)


func _option(label: String, options: Array, index: int, on_changed: Callable) -> void:
	var row := UiOptionRow.new(label, options, index)
	row.wrap = false
	row.changed.connect(on_changed)
	_register_row(row)


func _note(text: String) -> void:
	_settings_body.add_child(UiKit.paragraph(text, &"MutedLabel", 300.0))


func _apply_setting(key: String, value: Variant) -> void:
	Settings.set_value(key, value, false)
	_dirty = true
	if key == "show_fps":
		UI.set_debug_overlay(bool(value))


func _flush_settings() -> void:
	if _dirty:
		_dirty = false
		Settings.save_settings()


func _reset_tab() -> void:
	var keys: Array = []
	match _tab:
		0: keys = ["mouse_sensitivity", "invert_y", "fov", "camera_shake"]
		1: keys = ["master_volume", "sfx_volume", "music_volume", "ambience_volume", "subtitles"]
		2: keys = ["vsync", "max_fps", "render_scale", "shadows", "show_fps"]
		3: keys = ["traffic_density", "ped_density"]
	for k: String in keys:
		_apply_setting(k, Settings.DEFAULTS[k])
	UiKit.sfx("ui_click")
	_fill_tab()
	_focus_first_row()
