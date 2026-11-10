extends UiScreen
## F1 admin / benchmark menu (spec section 38) - a testing tool for video demos, not a mission system.
## Thin UI over the cheat API of the debug system (`Game.get_system("debug")`,
## gta/code/debug/debug_system.gd); docs/ADMIN.md lists every control and the call behind it.
## It does not pause the game (time, weather and spawns change live behind it), locks gameplay
## input and shows the mouse. The panel docks left; the HUD stays visible on the right.
##     UI.open_screen("admin", {"tab": "vehicles"})        tabs: teleport vehicles weapons player
##                                                          wanted world services debug
## Missing features are shown disabled with a "not available" hint (the next waves fill them).

const PAUSES_GAME := false
const TIME_SCALE := 1.0
const LOCKS_INPUT := true
const SHOWS_MOUSE := true
const HIDES_HUD := false

const PANEL_WIDTH := 1120.0
const SIDEBAR_WIDTH := 240.0
const OVERLAY_SIZE := Vector2(560.0, 454.0)   ## debug system overlay panel (placed beside this panel)
const LIVE_REFRESH := 0.25
const TABS := [
	{"id": "teleport", "name": "Teleport", "icon": &"pin", "sub": "Districts and every named place - lands on free ground"},
	{"id": "vehicles", "name": "Vehicles", "icon": &"car", "sub": "Spawn any vehicle on a suitable surface"},
	{"id": "weapons", "name": "Weapons", "icon": &"rifle", "sub": "Arsenal, ammunition and attachments"},
	{"id": "player", "name": "Player", "icon": &"person", "sub": "Vitals, money, equipment, skills, looks"},
	{"id": "wanted", "name": "Wanted", "icon": &"star", "sub": "Wanted level and police response"},
	{"id": "world", "name": "World", "icon": &"sun", "sub": "Time, weather and the living city"},
	{"id": "services", "name": "Services", "icon": &"taxi", "sub": "Taxi, garage and other city services"},
	{"id": "debug", "name": "Debug", "icon": &"stats", "sub": "Performance, time scale and clean-up"},
]
const VEHICLE_FILTERS := ["All", "Cars", "Service", "Bikes", "Boats", "Helicopters", "Planes"]
const VEHICLE_FILTER_IDS := ["", "car", "service", "bike", "boat", "heli", "plane"]
const GROUP_ICONS := {"car": &"car", "service": &"police", "bike": &"speed", "boat": &"boat", "heli": &"heli", "plane": &"plane"}
const GROUP_LABELS := {"car": "Car", "service": "Service", "bike": "Bike", "boat": "Boat", "heli": "Helicopter", "plane": "Plane"}
const TIME_PRESETS := [["Dawn", 6.0], ["Morning", 9.0], ["Noon", 12.0], ["Sunset", 19.5], ["Dusk", 20.75], ["Midnight", 0.0]]
const SYSTEM_TOGGLES := [["Traffic", "traffic"], ["Pedestrians", "peds"], ["Wildlife", "wildlife"], ["Police", "police"],
		["Emergency services", "emergency"], ["Trams", "transit"]]
const SLOT_LABELS := {"melee": "Melee", "handgun": "Handgun", "smg": "SMG", "shotgun": "Shotgun", "rifle": "Rifle",
		"sniper": "Sniper", "heavy": "Heavy", "thrown": "Thrown"}
## Names / icons for named locations the map legend does not cover (UiMapData.place_defs() has the rest).
const EXTRA_PLACES := {
	"spawn_start": ["Spawn Point", &"flag"],
	"safehouse_garage": ["Safehouse Garage", &"parking"],
	"downtown_plaza": ["Downtown Plaza", &"pin"],
	"industrial_yard": ["Industrial Yard", &"wrench"],
	"residential_park": ["Residential Park", &"umbrella"],
	"hill_top": ["Signal Hill Summit", &"mountain"],
	"boat_spawn": ["Boat Slip", &"boat"],
	"airport_runway_start": ["Runway - West End", &"plane"],
	"airport_runway_end": ["Runway - East End", &"plane"],
	"shipwreck": ["Shipwreck", &"anchor"],
	"airport_tower": ["Control Tower", &"plane"],
	"radio_mast": ["Radio Mast", &"radio"],
	"harbor_helipad": ["Harbour Helipad", &"helipad"],
}
const SERVICES := [
	{"id": "taxi", "text": "Call a taxi", "sub": "A cab drives to your position", "icon": &"taxi", "feature": "taxi"},
	{"id": "deliver", "text": "Deliver personal vehicle", "sub": "Your stored car is brought to you", "icon": &"car", "feature": "garage_delivery"},
	{"id": "store", "text": "Store vehicle in garage", "sub": "Current / nearest vehicle", "icon": &"parking", "feature": "garage_store"},
	{"id": "customise", "text": "Customise vehicle here", "sub": "Mod garage screen, anywhere", "icon": &"wrench", "feature": "customise"},
	{"id": "phone", "text": "Phone", "sub": "Open the phone", "icon": &"radio", "feature": "screen:phone"},
	{"id": "garage", "text": "Garage", "sub": "Stored vehicles", "icon": &"parking", "feature": "screen:garage"},
	{"id": "wardrobe", "text": "Wardrobe", "sub": "Outfits", "icon": &"shirt", "feature": "screen:wardrobe"},
	{"id": "quick_save", "text": "Quick save", "sub": "Slot 'quick' (F5)", "icon": &"save", "feature": ""},
	{"id": "quick_load", "text": "Quick load", "sub": "Slot 'quick' (F9)", "icon": &"load", "feature": ""},
]

static var _last_tab: int = 0

var _dbg: Node = null
var _tab: int = 0
var _cur_page: String = ""
var _tab_buttons: Array[Button] = []
var _tab_marks: Array[ColorRect] = []
var _header: UiHeader
var _pages_host: MarginContainer
var _status: UiCanvas
var _pages: Dictionary = {}          ## tab id -> Control
var _first_focus: Dictionary = {}    ## tab id -> Control
var _live: Dictionary = {}           ## tab id -> Array[Callable] (4 Hz while that page is shown)
var _avail: Dictionary = {}          ## tab id -> Array of [Control, feature, label]
var _hints: Dictionary = {}          ## tab id -> Label listing what is not available
var _live_t: float = 0.0

# teleport
var _district_list: UiList
var _place_list: UiList
var _keep_vehicle: UiOptionRow
# vehicles
var _veh_list: UiList
var _veh_filter: UiOptionRow
var _veh_mode: UiOptionRow
var _veh_current: Label
# weapons
var _wpn_list: UiList
# wanted
var _stars: UiCanvas
var _star_hover: int = -1
var _wanted_state: Label
# services
var _svc_list: UiList


func _init() -> void:
	super()
	backdrop_alpha = 0.0


func _ready() -> void:
	_dbg = Game.get_system("debug")
	var panel := UiPanel.new(&"SolidPanel", 10)
	panel.name = "Panel"
	add_child(panel)
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = UiStyle.MARGIN
	panel.offset_right = UiStyle.MARGIN + PANEL_WIDTH
	panel.offset_top = UiStyle.MARGIN
	panel.offset_bottom = -UiStyle.MARGIN
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(UiStyle.GLASS_SOLID, 1.0), UiStyle.RADIUS, UiStyle.LINE, 2, 22, 28, 24))
	panel.clip_contents = true

	var top := UiKit.hbox(18)
	var titles := UiKit.vbox(0)
	var title := UiKit.label("ADMIN MENU", &"HeaderLabel")
	titles.add_child(title)
	var sub := UiKit.label("BENCHMARK & TEST TOOLS", &"SectionLabel")
	sub.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
	sub.add_theme_color_override("font_color", UiStyle.CORAL)
	titles.add_child(sub)
	top.add_child(titles)
	_status = UiCanvas.new(_draw_status)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.custom_minimum_size = Vector2(420.0, 72.0)
	top.add_child(_status)
	panel.add(top)
	panel.add(UiKit.separator())

	var main := UiKit.hbox(18)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add(main)
	var side := UiKit.vbox(2)
	side.custom_minimum_size.x = SIDEBAR_WIDTH
	main.add_child(side)
	for i in TABS.size():
		side.add_child(_make_tab_button(i))
	side.add_child(UiKit.spacer())
	var note := UiKit.paragraph("A testing tool, not a mission system. The game keeps running behind this menu.", &"MutedLabel", SIDEBAR_WIDTH)
	note.add_theme_font_size_override("font_size", UiStyle.FS_TINY)
	side.add_child(note)
	main.add_child(VSeparator.new())

	var content := UiKit.vbox(12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(content)
	_header = UiKit.header("", "")
	_header.title_size = UiStyle.FS_H3
	content.add_child(_header)
	_pages_host = MarginContainer.new()
	_pages_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_pages_host)

	panel.add(UiKit.separator())
	panel.add(UiKeyHints.new([
		{"keys": ["Q", "E"], "text": "Tabs"}, {"keys": ["W", "S"], "text": "Navigate"}, {"keys": ["A", "D"], "text": "Adjust"},
		{"key": "Enter", "text": "Select"}, {"key": "F1", "text": "Close"},
	]))


func open(args: Dictionary) -> void:
	if _dbg != null and is_instance_valid(_dbg) and _dbg.has_method("set_overlay_origin"):
		# right edge, above the HUD weapon / vehicle card, clear of the money pill and the toasts
		var vp := get_viewport_rect().size
		_dbg.call("set_overlay_origin", Vector2(maxf(vp.x - UiStyle.MARGIN - OVERLAY_SIZE.x, UiStyle.MARGIN + PANEL_WIDTH + 24.0),
				maxf(vp.y - UiStyle.MARGIN - 170.0 - OVERLAY_SIZE.y, 150.0)))
	var t: Variant = args.get("tab", _last_tab)
	select_tab(t)


func close() -> void:
	if _dbg != null and is_instance_valid(_dbg) and _dbg.has_method("set_overlay_origin"):
		_dbg.call("set_overlay_origin", Vector2(UiStyle.MARGIN, UiStyle.MARGIN))


func regain_focus() -> void:
	_focus_page()


## Shows a tab by index or id ("teleport", "vehicles" ...).
func select_tab(tab: Variant) -> void:
	var i := 0
	if tab is int:
		i = clampi(tab, 0, TABS.size() - 1)
	else:
		for k in TABS.size():
			if str(TABS[k]["id"]) == str(tab):
				i = k
	_tab = i
	_last_tab = i
	for k in _tab_buttons.size():
		_tab_marks[k].visible = k == i
		_tab_buttons[k].add_theme_color_override("font_color", UiStyle.TEXT if k == i else UiStyle.MUTED)
	var id: String = TABS[i]["id"]
	_header.right_text = ""
	_header.title = str(TABS[i]["name"])
	_header.subtitle = str(TABS[i]["sub"])
	if not _pages.has(id):
		var page := _build_page(id)
		page.name = id.to_pascal_case()
		_pages[id] = page
		_pages_host.add_child(page)
	for pid: String in _pages:
		(_pages[pid] as Control).visible = pid == id
	_refresh_page(id)
	_focus_page()


func get_tab_id() -> String:
	return str(TABS[_tab]["id"])


func get_page(id: String) -> Control:
	return _pages.get(id, null)


## Focus the first control of the page once the new rows have been laid out.
func _focus_page() -> void:
	var want := get_tab_id()
	await get_tree().process_frame
	if not is_inside_tree() or get_tab_id() != want:
		return
	var c: Variant = _first_focus.get(want, null)
	if c is UiList:
		var l := c as UiList
		l.grab()
		if l.selected <= 2:
			l.scroll_vertical = 0
	elif c is UiSliderRow:
		(c as UiSliderRow).grab()
	elif c is Control and is_instance_valid(c):
		(c as Control).grab_focus()
	var sc := _page_scroll_of(want)
	if sc != null:
		sc.scroll_vertical = 0


func _page_scroll_of(id: String) -> ScrollContainer:
	var page: Variant = _pages.get(id, null)
	return page as ScrollContainer if page is ScrollContainer else null


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var dir := 0
		match (event as InputEventKey).physical_keycode:
			KEY_Q: dir = -1
			KEY_E: dir = 1
		if dir != 0:
			UiKit.sfx("ui_tab")
			select_tab(posmod(_tab + dir, TABS.size()))
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var jd := 0
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_LEFT_SHOULDER: jd = -1
			JOY_BUTTON_RIGHT_SHOULDER: jd = 1
		if jd != 0:
			select_tab(posmod(_tab + jd, TABS.size()))
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_live_t += delta / maxf(Engine.time_scale, 0.05)
	if _live_t < LIVE_REFRESH:
		return
	_live_t = 0.0
	_status.queue_redraw()
	for f: Callable in _live.get(get_tab_id(), []):
		f.call()


# =================================================================================================
# shell helpers
# =================================================================================================

func _make_tab_button(i: int) -> Button:
	var t: Dictionary = TABS[i]
	var b := UiKit.button("      " + str(t["name"]).to_upper(), _on_tab_pressed.bind(i), &"MenuEntryButton")
	b.add_theme_font_size_override("font_size", UiStyle.FS_LARGE)
	b.custom_minimum_size.y = 58.0
	var ic := UiIconRect.new(t["icon"], 28.0, UiStyle.TEAL_LIGHT)
	ic.position = Vector2(22.0, 15.0)
	ic.size = Vector2(28.0, 28.0)
	b.add_child(ic)
	var mark := ColorRect.new()
	mark.color = UiStyle.CORAL
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.position = Vector2(0.0, 12.0)
	mark.size = Vector2(6.0, 34.0)
	mark.visible = false
	b.add_child(mark)
	_tab_buttons.append(b)
	_tab_marks.append(mark)
	return b


func _on_tab_pressed(i: int) -> void:
	select_tab(i)


## Calls the debug system (null when it is missing).
func _d(method: String, args: Array = []) -> Variant:
	if _dbg == null or not is_instance_valid(_dbg):
		_dbg = Game.get_system("debug")
	if _dbg == null or not _dbg.has_method(method):
		return null
	return _dbg.callv(method, args)


func _db(method: String, args: Array = []) -> bool:
	var r: Variant = _d(method, args)
	return r is bool and r


func _df(method: String, args: Array = [], fallback: float = 0.0) -> float:
	var r: Variant = _d(method, args)
	return float(r) if (r is float or r is int) else fallback


func _reason(feature: String) -> String:
	if feature == "":
		return ""
	if _dbg == null or not is_instance_valid(_dbg):
		return "debug system not loaded"
	return str(_d("unavailable_reason", [feature]))


func _scroll_page() -> Array:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var m := UiKit.margin(null, 0, 0, 18, 8)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	var v := UiKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	return [sc, v]


func _section(parent: Control, text: String) -> Label:
	var l := UiKit.label(text.to_upper(), &"SectionLabel")
	l.add_theme_font_size_override("font_size", UiStyle.FS_BODY)
	parent.add_child(UiKit.spacer(Vector2(0, 2), false))
	parent.add_child(l)
	return l


## Row of equally wide buttons. defs: [text, callable, feature ("" = always), variation].
func _buttons(parent: Control, defs: Array) -> HBoxContainer:
	var h := UiKit.hbox(10)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for d: Array in defs:
		var b := UiKit.button(str(d[0]), d[1], d[3] if d.size() > 3 else &"")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(60.0, 50.0)
		b.clip_text = true
		if defs.size() >= 3:
			b.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
		if d.size() > 2 and str(d[2]) != "":
			_bind_avail(b, str(d[2]))
		h.add_child(b)
	parent.add_child(h)
	return h


func _option(parent: Control, label: String, options: Array, index: int, cb: Callable, feature: String = "") -> UiOptionRow:
	var row := UiOptionRow.new(label, options, index)
	row.custom_minimum_size.x = 260.0
	row.changed.connect(cb)
	parent.add_child(row)
	if feature != "":
		_bind_avail(row, feature)
	return row


func _slider(parent: Control, label: String, lo: float, hi: float, step: float, value: float, fmt: String, cb: Callable,
		feature: String = "") -> UiSliderRow:
	var row := UiSliderRow.new(label, lo, hi, step, value, fmt)
	row.slider.custom_minimum_size.x = 160.0
	for ch: Node in row.get_children():
		if ch is Label and (ch as Label).theme_type_variation != &"ValueLabel":
			(ch as Label).custom_minimum_size.x = 236.0
	row.value_changed.connect(cb)
	parent.add_child(row)
	if feature != "":
		_bind_avail(row, feature)
	return row


func _note(parent: Control, text: String) -> Label:
	var l := UiKit.paragraph(text, &"MutedLabel", 300.0)
	parent.add_child(l)
	return l


func _hint_label(parent: Control) -> void:
	var l := UiKit.paragraph("", &"MutedLabel", 300.0)
	l.add_theme_color_override("font_color", UiStyle.DIM)
	l.visible = false
	parent.add_child(UiKit.spacer(Vector2(0, 4), false))
	parent.add_child(l)
	_hints[_cur_page] = l


func _bind_avail(c: Control, feature: String, label: String = "") -> void:
	if not _avail.has(_cur_page):
		_avail[_cur_page] = []
	if label == "":
		if c is Button:
			label = (c as Button).text.strip_edges()
		elif c is UiOptionRow:
			label = (c as UiOptionRow).label
		else:
			label = feature.capitalize()
	(_avail[_cur_page] as Array).append([c, feature, label])


func _bind_live(f: Callable) -> void:
	if not _live.has(_cur_page):
		_live[_cur_page] = []
	(_live[_cur_page] as Array).append(f)


## Greys out what is not available and lists it in the page hint; then refreshes live values.
func _refresh_page(id: String) -> void:
	var by_reason: Dictionary = {}       ## reason -> PackedStringArray of control labels
	for entry: Array in _avail.get(id, []):
		var c: Control = entry[0]
		if not is_instance_valid(c):
			continue
		var reason := _reason(str(entry[1]))
		_set_control_enabled(c, reason == "", reason)
		if reason != "":
			if not by_reason.has(reason):
				by_reason[reason] = PackedStringArray()
			var labels: PackedStringArray = by_reason[reason]
			if not labels.has(str(entry[2])):
				labels.append(str(entry[2]))
			by_reason[reason] = labels
	var lines: PackedStringArray = []
	for r: String in by_reason:
		lines.append("%s: %s" % [", ".join(by_reason[r]), r])
	var hint: Variant = _hints.get(id, null)
	if hint is Label:
		(hint as Label).visible = not lines.is_empty()
		(hint as Label).text = "Not available yet - " + ".  ".join(lines) + "."
	for f: Callable in _live.get(id, []):
		f.call()
	match id:
		"teleport":
			_fill_teleport()
		"vehicles":
			_fill_vehicles()
		"weapons":
			_fill_weapons()
		"services":
			_fill_services()


func _set_control_enabled(c: Control, on: bool, reason: String) -> void:
	c.tooltip_text = "" if on else "Not available: " + reason
	if c is BaseButton:
		(c as BaseButton).disabled = not on
		c.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	elif c is UiSliderRow:
		(c as UiSliderRow).slider.editable = on
		(c as UiSliderRow).slider.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
		c.modulate.a = 1.0 if on else 0.4
	else:
		c.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
		c.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
		c.modulate.a = 1.0 if on else 0.4


func _build_page(id: String) -> Control:
	_cur_page = id
	_live[id] = []
	_avail[id] = []
	if _dbg == null:
		var v := UiKit.vbox(10)
		_note(v, "The debug system (gta/code/debug/debug_system.gd) is not loaded in this session, so the admin tools are not available.")
		return v
	match id:
		"teleport":
			return _page_teleport()
		"vehicles":
			return _page_vehicles()
		"weapons":
			return _page_weapons()
		"player":
			return _page_player()
		"wanted":
			return _page_wanted()
		"world":
			return _page_world()
		"services":
			return _page_services()
		_:
			return _page_debug()


# =================================================================================================
# status strip (money, stars, clock, weather)
# =================================================================================================

func _draw_status(c: UiCanvas) -> void:
	var num := UiStyle.font(&"num")
	var head := UiStyle.font(&"head")
	var h := c.size.y
	var xr := c.size.x
	var money := UiStyle.money(Game.money)
	var mw := UiStyle.text_width(num, money, UiStyle.FS_LARGE)
	UiStyle.text_in(c, num, Rect2(xr - mw, 0.0, mw, h), money, UiStyle.FS_LARGE, UiStyle.SUN)
	xr -= mw + 30.0
	var lvl := int(Wanted.level)
	for i in 5:
		var cx := xr - 14.0 - float(4 - i) * 30.0
		UiIcons.draw(c, &"star", Vector2(cx, h * 0.5), 26.0, UiStyle.SUN if i < lvl else Color(1, 1, 1, 0.16))
	xr -= 5.0 * 30.0 + 26.0
	var clock := WorldClock.get_time_string()
	var cw := UiStyle.text_width(num, clock, UiStyle.FS_LARGE)
	UiStyle.text_in(c, num, Rect2(xr - cw, 0.0, cw, h), clock, UiStyle.FS_LARGE, UiStyle.TEXT)
	xr -= cw + 26.0
	UiIcons.draw(c, UiIcons.weather_icon(str(Weather.current), WorldClock.is_night()), Vector2(xr - 6.0, h * 0.5), 30.0, UiStyle.TEAL_LIGHT)
	if Game.invulnerable:
		xr -= 52.0
		UiIcons.draw(c, &"shield", Vector2(xr - 6.0, h * 0.5), 28.0, UiStyle.CORAL)
	if Engine.time_scale < 0.99 or Engine.time_scale > 1.01:
		xr -= 30.0
		var ts := "x%.2f" % Engine.time_scale
		var tw := UiStyle.text_width(head, ts, UiStyle.FS_SMALL)
		UiStyle.text_in(c, head, Rect2(xr - tw - 10.0, 0.0, tw, h), ts, UiStyle.FS_SMALL, UiStyle.CORAL)


# =================================================================================================
# TELEPORT
# =================================================================================================

func _page_teleport() -> Control:
	var page := UiKit.vbox(10)
	var top := UiKit.hbox(14)
	var wp := UiKit.button("Go to map waypoint", _tp_waypoint)
	wp.custom_minimum_size = Vector2(290.0, 50.0)
	top.add_child(wp)
	_bind_avail(wp, "teleport")
	_keep_vehicle = UiOptionRow.new("Bring vehicle", ["No", "Yes"], 1)
	_keep_vehicle.custom_minimum_size.x = 260.0
	top.add_child(_keep_vehicle)
	page.add_child(top)
	_bind_live(func() -> void: wp.disabled = not UI.has_waypoint() or _reason("teleport") != "")
	var cols := UiKit.hbox(16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(cols)
	var left := UiKit.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.85
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	_section(left, "Districts")
	_district_list = UiList.new()
	_district_list.item_activated.connect(_on_teleport)
	left.add_child(_district_list)
	var right := UiKit.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	_section(right, "Places")
	_place_list = UiList.new()
	_place_list.item_activated.connect(_on_teleport)
	right.add_child(_place_list)
	_hint_label(page)
	_first_focus["teleport"] = _district_list
	return page


func _fill_teleport() -> void:
	if _district_list == null:
		return
	var targets: Variant = _d("get_teleport_targets")
	if not (targets is Array):
		return
	var here := Game.get_player_position()
	var places := UiMapData.place_defs()
	var districts: Array = []
	var locs: Array = []
	var dup: Dictionary = {}
	for t: Dictionary in targets:
		var pos: Vector3 = t["position"]
		var dist := Vector2(pos.x - here.x, pos.z - here.z).length()
		var dist_txt := "%d m" % int(dist) if dist < 1000.0 else "%.1f km" % (dist / 1000.0)
		if str(t["kind"]) == "district":
			var did := str(t["district"])
			districts.append({"text": UiMapData.district_name(did), "sub": "%s  -  %s" % [did.capitalize(), dist_txt],
					"icon": &"map", "icon_color": UiStyle.TEAL_LIGHT, "id": t["id"]})
			continue
		var lid := str(t["id"])
		var nm := lid.capitalize()
		var icon: StringName = &"pin"
		var col: Color = UiStyle.MUTED
		if places.has(lid):
			nm = str(places[lid][0])
			icon = places[lid][1]
			col = places[lid][2]
		elif EXTRA_PLACES.has(lid):
			nm = str(EXTRA_PLACES[lid][0])
			icon = EXTRA_PLACES[lid][1]
		if lid.ends_with("_1") or lid.ends_with("_2") or lid.ends_with("_3"):
			nm += " " + lid.substr(lid.length() - 1)
		var count := int(dup.get(nm, 0))
		dup[nm] = count + 1
		var dname := UiMapData.district_name(str(t["district"])) if str(t["district"]) != "" else ""
		var item := {"text": nm, "sub": "%s  -  %s" % [dname, dist_txt], "icon": icon, "icon_color": col, "id": lid}
		if bool(t["water"]):
			item["badge"] = "WATER"
		locs.append(item)
	locs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["text"]) < str(b["text"]))
	_district_list.set_items(districts, true)
	_place_list.set_items(locs, true)


func _on_teleport(_i: int, item: Dictionary) -> void:
	var keep := _keep_vehicle == null or _keep_vehicle.index == 1
	if _db("teleport_player", [item["id"], keep]):
		_fill_teleport.call_deferred()


func _tp_waypoint() -> void:
	var keep := _keep_vehicle == null or _keep_vehicle.index == 1
	_d("teleport_player", ["waypoint", keep])


# =================================================================================================
# VEHICLES
# =================================================================================================

func _page_vehicles() -> Control:
	var page := UiKit.vbox(8)
	_veh_filter = _option(page, "Class", VEHICLE_FILTERS, 0, func(_i: int) -> void: _fill_vehicles(), "vehicles")
	_veh_mode = _option(page, "On select", ["Spawn + drive", "Spawn only"], 0, func(_i: int) -> void: pass, "vehicles")
	_veh_list = UiList.new()
	_veh_list.item_activated.connect(_on_vehicle)
	page.add_child(_veh_list)
	_veh_current = UiKit.label("", &"MutedLabel")
	page.add_child(_veh_current)
	_bind_live(_update_current_vehicle)
	_buttons(page, [["Repair", func() -> void: _d("repair_current_vehicle"), "vehicles"],
			["Flip upright", func() -> void: _d("flip_current_vehicle"), "vehicles"],
			["Customise", func() -> void: _d("open_customisation"), "customise"],
			["Despawn", func() -> void: _d("clear_admin_vehicles"), "vehicles"]])
	var unlock := _option(page, "Unlock all mods (free)", ["Off", "On"], 1 if _db("get", ["mods_unlocked"]) else 0,
			func(i: int) -> void: _d("set_mods_unlocked", [i == 1]), "vehicles")
	_bind_live(func() -> void: unlock.set_index_silent(1 if _db("get", ["mods_unlocked"]) else 0))
	_hint_label(page)
	_first_focus["vehicles"] = _veh_list
	return page


func _fill_vehicles() -> void:
	if _veh_list == null:
		return
	var filter: String = VEHICLE_FILTER_IDS[_veh_filter.index] if _veh_filter != null else ""
	var specs: Variant = _d("get_vehicle_specs", [filter])
	if not (specs is Array):
		return
	var items: Array = []
	var ready := 0
	for s: Dictionary in specs:
		var group := str(s["group"])
		var ok := bool(s["can_spawn"])
		var sub := ""
		if ok:
			ready += 1
			sub = "%s  -  %d seats  -  %d km/h" % [GROUP_LABELS.get(group, group), int(s["seats"]), int(round(float(s["top_speed_kmh"])))]
		else:
			sub = "Not available - %s" % str(s["reason"])
		items.append({"text": str(s["name"]), "sub": sub, "icon": GROUP_ICONS.get(group, &"car"),
				"icon_color": UiStyle.TEAL_LIGHT if ok else UiStyle.DIM, "right": str(s["id"]), "disabled": not ok, "id": s["id"]})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (not bool(a["disabled"]) and bool(b["disabled"])) or (bool(a["disabled"]) == bool(b["disabled"]) and str(a["text"]) < str(b["text"])))
	_veh_list.set_items(items, true)
	_header.right_text = "%d / %d" % [ready, items.size()]


func _on_vehicle(_i: int, item: Dictionary) -> void:
	var enter := _veh_mode == null or _veh_mode.index == 0
	var v: Variant = _d("spawn_vehicle_for_player", [item["id"], enter])
	if v != null and enter:
		close_self()


func _update_current_vehicle() -> void:
	if _veh_current == null:
		return
	var v: Variant = _d("get_target_vehicle")
	if is_instance_valid(v) and v is Node3D:
		var vn := v as Node3D
		var mine := vn == Game.get_player_vehicle()
		var hp := UiKit.num(vn, &"health", 0.0) / maxf(UiKit.num(vn, &"max_health", 1.0), 1.0)
		var nm := str(vn.get("spec_id")).capitalize()
		var spec: Variant = vn.get("spec")
		if spec is Object and str((spec as Object).get("display_name")) != "":
			nm = str((spec as Object).get("display_name"))
		_veh_current.text = "%s: %s  -  condition %d %%  -  %d km/h" % ["Driving" if mine else "Nearest", nm, int(hp * 100.0),
				int(UiKit.num(vn, &"speed_kmh", 0.0))]
	else:
		_veh_current.text = "On foot - repair / flip / customise act on a vehicle within 10 m."


# =================================================================================================
# WEAPONS
# =================================================================================================

func _page_weapons() -> Control:
	var page := UiKit.vbox(8)
	_buttons(page, [["Give all weapons", _weapon_action.bind("give_all_weapons"), "weapons", &"AccentButton"],
			["Refill ammo", _weapon_action.bind("refill_ammo"), "weapons"],
			["All attachments", _weapon_action.bind("give_all_attachments"), "weapons"]])
	var inf := _option(page, "Infinite ammunition", ["Off", "On"], 0, func(i: int) -> void: _d("set_infinite_ammo", [i == 1]), "weapons")
	_bind_live(func() -> void: inf.set_index_silent(1 if _db("is_infinite_ammo") else 0))
	_wpn_list = UiList.new()
	_wpn_list.item_activated.connect(func(_i: int, item: Dictionary) -> void:
		_d("give_weapon", [item["id"], true])
		_fill_weapons())
	page.add_child(_wpn_list)
	_note(page, "Select a weapon to receive it with full ammunition and draw it.")
	_hint_label(page)
	_first_focus["weapons"] = _wpn_list
	return page


func _weapon_action(method: String) -> void:
	_d(method)
	_fill_weapons()


func _fill_weapons() -> void:
	if _wpn_list == null:
		return
	var list: Variant = _d("get_weapon_list")
	if not (list is Array):
		return
	var items: Array = []
	var owned_n := 0
	for w: Dictionary in list:
		var owned := bool(w["owned"])
		if owned:
			owned_n += 1
		var slot := str(w["slot"])
		var sub := str(SLOT_LABELS.get(slot, slot.capitalize()))
		if owned and bool(w["uses_ammo"]):
			sub += "  -  %d / %d" % [maxi(int(w["in_mag"]), 0), maxi(int(w["reserve"]), 0)] if int(w["in_mag"]) >= 0 else "  -  %d" % maxi(int(w["reserve"]), 0)
		elif not owned:
			sub += "  -  not owned"
		items.append({"text": str(w["name"]), "sub": sub, "icon": UiIcons.weapon_slot_icon(slot),
				"icon_color": UiStyle.TEAL_LIGHT if owned else UiStyle.MUTED, "right": "OWNED" if owned else "GIVE",
				"right_color": UiStyle.TEAL_LIGHT if owned else UiStyle.SUN, "id": w["id"]})
	_wpn_list.set_items(items, true)
	_header.right_text = "%d / %d" % [owned_n, items.size()]


# =================================================================================================
# PLAYER
# =================================================================================================

func _page_player() -> Control:
	var sp := _scroll_page()
	var v: VBoxContainer = sp[1]
	_section(v, "Vitals")
	var hp_bar := UiBar.new(UiStyle.CORAL, &"heart", 14.0)
	var ar_bar := UiBar.new(UiStyle.TEAL, &"shield", 14.0)
	var br_bar := UiBar.new(UiStyle.TEAL_LIGHT, &"bubbles", 14.0)
	var bars := UiKit.hbox(24)
	for b: UiBar in [hp_bar, ar_bar, br_bar]:
		b.value_width = 70.0
		bars.add_child(b)
	v.add_child(bars)
	var hp := _slider(v, "Health", 1.0, 100.0, 1.0, 100.0, "int", func(x: float) -> void: _d("set_health", [x]), "player")
	var ar := _slider(v, "Armour", 0.0, 100.0, 1.0, 0.0, "int", func(x: float) -> void: _d("set_armor", [x]), "player")
	_buttons(v, [["Heal + armour", func() -> void: _d("heal_full"), "player", &"AccentButton"],
			["Refill lungs", func() -> void: _d("refill_breath"), "breath"],
			["Kill player", _confirm_kill, "player", &"GhostButton"]])
	var god := _option(v, "Invulnerable", ["Off", "On"], 1 if Game.invulnerable else 0,
			func(i: int) -> void: _d("set_invulnerable", [i == 1]))
	_bind_live(func() -> void:
		var p: Node3D = Game.player if Game.has_player() else null
		var h := UiKit.num(p, &"health", 0.0)
		var a := UiKit.num(p, &"armor", 0.0)
		var br := UiKit.num(p, &"breath", 1.0)
		hp_bar.value = h / maxf(UiKit.num(p, &"max_health", 100.0), 1.0)
		hp_bar.value_text = str(int(ceil(h)))
		ar_bar.value = a / maxf(UiKit.num(p, &"max_armor", 100.0), 1.0)
		ar_bar.value_text = str(int(ceil(a)))
		br_bar.value = br
		br_bar.value_text = "%d%%" % int(br * 100.0)
		if not hp.slider.has_focus():
			hp.set_value_silent(h)
		if not ar.slider.has_focus():
			ar.set_value_silent(a)
		god.set_index_silent(1 if Game.invulnerable else 0))

	_section(v, "Money")
	var mrow := UiKit.hbox(10)
	var edit := LineEdit.new()
	edit.placeholder_text = "Amount"
	edit.custom_minimum_size = Vector2(150.0, 50.0)
	edit.max_length = 10
	edit.text_submitted.connect(func(t: String) -> void: _set_money_text(t, edit))
	mrow.add_child(edit)
	var set_b := UiKit.button("Set", func() -> void: _set_money_text(edit.text, edit))
	set_b.custom_minimum_size = Vector2(76.0, 50.0)
	mrow.add_child(set_b)
	for pair: Array in [["+ $10K", 10000], ["+ $100K", 100000], ["+ $1M", 1000000]]:
		var amt: int = pair[1]
		var b := UiKit.button(str(pair[0]), func() -> void: _d("add_money", [amt]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(60.0, 50.0)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
		mrow.add_child(b)
	v.add_child(mrow)

	_section(v, "Equipment")
	_buttons(v, [["Give parachute", func() -> void: _d("give_parachute"), "parachute"],
			["Random appearance", func() -> void: _d("randomize_appearance"), "appearance"]])
	var scuba := _option(v, "Scuba gear", ["Off", "On"], 0, func(i: int) -> void: _d("set_scuba", [i == 1]), "scuba")
	var chute := UiKit.label("", &"MutedLabel")
	v.add_child(chute)
	_bind_live(func() -> void:
		scuba.set_index_silent(1 if _db("has_scuba") else 0)
		var p: Node3D = Game.player if Game.has_player() else null
		chute.text = "Parachute: %s" % ("equipped" if UiKit.flag(p, &"has_parachute") else "none"))

	_section(v, "Skills")
	var grid := UiKit.grid(2, 24, 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var skill_bars: Dictionary = {}
	for s: String in Skills.SKILLS:
		var col := UiKit.vbox(0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l := UiKit.label(str(Skills.DISPLAY_NAMES.get(s, s.capitalize())), &"SmallLabel")
		col.add_child(l)
		var bar := UiBar.new(UiStyle.SUN, UiIcons.skill_icon(s), 10.0)
		bar.value_width = 54.0
		col.add_child(bar)
		grid.add_child(col)
		skill_bars[s] = bar
	v.add_child(grid)
	_bind_live(func() -> void:
		for s: String in skill_bars:
			var lv := Skills.get_level(s)
			(skill_bars[s] as UiBar).value = lv / 100.0
			(skill_bars[s] as UiBar).value_text = str(int(lv)))
	_buttons(v, [["Max all skills", func() -> void: _d("max_skills"), ""],
			["Reset skills", func() -> void: _d("reset_skills"), ""]])
	_hint_label(v)
	_first_focus["player"] = hp
	return sp[0]


func _set_money_text(t: String, edit: LineEdit) -> void:
	var digits := ""
	for ch in t:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits == "":
		UiKit.sfx("ui_error")
		return
	_d("set_money", [int(digits)])
	edit.text = ""
	edit.release_focus()


func _confirm_kill() -> void:
	var dlg := confirm("Kill the player?", "Tests the death and respawn flow.", "Kill", "Cancel", true)
	if dlg != null:
		dlg.confirmed.connect(func() -> void:
			close_self()
			_d("kill_player"))


# =================================================================================================
# WANTED
# =================================================================================================

func _page_wanted() -> Control:
	var sp := _scroll_page()
	var v: VBoxContainer = sp[1]
	_section(v, "Wanted level")
	_stars = UiCanvas.new(_draw_stars, Control.MOUSE_FILTER_STOP)
	_stars.focus_mode = Control.FOCUS_ALL
	_stars.custom_minimum_size = Vector2(560.0, 92.0)
	_stars.gui_input.connect(_on_stars_input)
	_stars.focus_entered.connect(_stars.queue_redraw)
	_stars.focus_exited.connect(_stars.queue_redraw)
	_stars.mouse_exited.connect(func() -> void:
		_star_hover = -1
		_stars.queue_redraw())
	v.add_child(_stars)
	_wanted_state = UiKit.label("", &"SmallLabel")
	v.add_child(_wanted_state)
	var esc := UiBar.new(UiStyle.TEAL_LIGHT, &"", 10.0)
	esc.value_width = 70.0
	v.add_child(esc)
	_bind_live(func() -> void:
		_stars.queue_redraw()
		var st := int(Wanted.state)
		var txt := "Calm - no police interest"
		if int(Wanted.level) > 0:
			txt = "PURSUIT - police know where you are" if st == 1 else ("SEARCHING - stay out of sight" if st == 2 else "Wanted")
		_wanted_state.text = txt
		esc.visible = st == 2
		esc.value = float(Wanted.escape_progress)
		esc.value_text = "%d%%" % int(float(Wanted.escape_progress) * 100.0))
	_buttons(v, [["Clear wanted level", func() -> void: _d("clear_wanted"), "wanted", &"AccentButton"],
			["Arrest me", _arrest, "bust"]])
	var never := _option(v, "Never wanted", ["Off", "On"], 1 if _db("is_never_wanted") else 0,
			func(i: int) -> void: _d("set_never_wanted", [i == 1]), "never_wanted")
	_bind_live(func() -> void: never.set_index_silent(1 if _db("is_never_wanted") else 0))
	_section(v, "Police units")
	_buttons(v, [["Officer", func() -> void: _d("spawn_police", ["officer"]), "police_units"],
			["Cruiser", func() -> void: _d("spawn_police", ["cruiser"]), "police_units"],
			["SWAT", func() -> void: _d("spawn_police", ["swat"]), "police_units"]])
	_buttons(v, [["Helicopter", func() -> void: _d("spawn_police", ["heli"]), "police_units"],
			["Roadblock", func() -> void: _d("spawn_police", ["roadblock"]), "police_units"],
			["Clear units", func() -> void: _d("clear_police"), "clear_police"]])
	var units := UiKit.label("", &"MutedLabel")
	v.add_child(units)
	_bind_live(func() -> void: units.text = "Police in the city: %d" % get_tree().get_node_count_in_group(&"police"))
	_hint_label(v)
	_first_focus["wanted"] = _stars
	return sp[0]


func _arrest() -> void:
	close_self()
	_d("bust_player")


func _draw_stars(c: UiCanvas) -> void:
	var focused := c.has_focus()
	if focused:
		c.draw_style_box(UiStyle.cached_box(&"select"), Rect2(Vector2.ZERO, c.size))
	var lvl := int(Wanted.level)
	var cell := 86.0
	var x0 := 22.0
	var cy := c.size.y * 0.5
	for i in 6:
		var r := Rect2(x0 + float(i) * cell, 8.0, cell - 8.0, c.size.y - 16.0)
		if i == _star_hover:
			c.draw_style_box(UiStyle.cached_box(&"hover"), r)
		if i == 0:
			var col0: Color = UiStyle.TEAL_LIGHT if lvl == 0 else UiStyle.MUTED
			UiIcons.draw(c, &"close", Vector2(r.get_center().x, cy), 30.0, col0)
		else:
			var on := i <= lvl
			UiIcons.draw(c, &"star", Vector2(r.get_center().x, cy), 46.0, UiStyle.SUN if on else Color(1, 1, 1, 0.16))
	var txt := "%d / 5" % lvl
	UiStyle.text_in(c, UiStyle.font(&"num"), Rect2(0.0, 0.0, c.size.x - 22.0, c.size.y), txt, UiStyle.FS_H3,
			UiStyle.SUN if lvl > 0 else UiStyle.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)


func _on_stars_input(event: InputEvent) -> void:
	var cell := 86.0
	if event is InputEventMouseMotion:
		var h := int(floor(((event as InputEventMouseMotion).position.x - 22.0) / cell))
		h = h if h >= 0 and h < 6 else -1
		if h != _star_hover:
			_star_hover = h
			_stars.queue_redraw()
		if not _stars.has_focus():
			_stars.grab_focus()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var i := int(floor((mb.position.x - 22.0) / cell))
			if i >= 0 and i < 6:
				UiKit.sfx("ui_click")
				_d("set_wanted", [i])
				_stars.queue_redraw()
			_stars.accept_event()
	elif event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_right", true):
		var dir := -1 if event.is_action_pressed("ui_left", true) else 1
		var lvl := clampi(int(Wanted.level) + dir, 0, 5)
		if lvl != int(Wanted.level):
			UiKit.sfx("ui_tab")
			_d("set_wanted", [lvl])
		_stars.queue_redraw()
		_stars.accept_event()


# =================================================================================================
# WORLD
# =================================================================================================

func _page_world() -> Control:
	var sp := _scroll_page()
	var v: VBoxContainer = sp[1]
	_section(v, "Time of day")
	var clock := UiKit.label("", &"HeaderLabel")
	v.add_child(clock)
	var hour := _slider(v, "Hour", 0.0, 24.0, 0.25, float(WorldClock.hour), "%.2f h", func(x: float) -> void: _d("set_time", [x]))
	_bind_live(func() -> void:
		clock.text = "%s   %s" % [WorldClock.get_time_string(), WorldClock.get_phase().to_upper()]
		if not hour.slider.has_focus():
			hour.set_value_silent(float(WorldClock.hour)))
	var defs1: Array = []
	var defs2: Array = []
	for i in TIME_PRESETS.size():
		var pr: Array = TIME_PRESETS[i]
		var h: float = pr[1]
		var d := ["%s  %02d:%02d" % [pr[0], int(h), int(round(fposmod(h, 1.0) * 60.0))], func() -> void: _d("set_time", [h]), ""]
		if i < 3:
			defs1.append(d)
		else:
			defs2.append(d)
	_buttons(v, defs1)
	_buttons(v, defs2)
	var paused := _option(v, "Clock", ["Running", "Paused"], 1 if WorldClock.paused else 0,
			func(i: int) -> void: _d("set_clock_paused", [i == 1]))
	_bind_live(func() -> void: paused.set_index_silent(1 if WorldClock.paused else 0))

	_section(v, "Weather")
	var wdefs: Array = []
	for id: String in Weather.TYPES:
		wdefs.append([str(Weather.DISPLAY_NAMES.get(id, id.capitalize())), func() -> void: _d("set_weather", [id, false]), ""])
	var wrow := _buttons(v, wdefs)
	for b: Node in wrow.get_children():
		(b as Button).custom_minimum_size.x = 80.0
	var auto := _option(v, "Automatic weather changes", ["Off", "On"], 1 if Weather.auto_cycle else 0,
			func(i: int) -> void: _d("set_auto_weather", [i == 1]))
	var wnow := UiKit.label("", &"MutedLabel")
	v.add_child(wnow)
	_bind_live(func() -> void:
		auto.set_index_silent(1 if Weather.auto_cycle else 0)
		wnow.text = "Now: %s%s" % [str(Weather.DISPLAY_NAMES.get(Weather.current, Weather.current)),
				"  (changing)" if Weather.transition < 0.999 else ""])

	_section(v, "City simulation")
	for pair: Array in SYSTEM_TOGGLES:
		var sys_name: String = pair[1]
		var row := _option(v, str(pair[0]), ["Off", "On"], 1, func(i: int) -> void: _d("toggle_system", [sys_name, i == 1]), sys_name)
		_bind_live(func() -> void:
			if Game.has_system(sys_name):
				row.set_index_silent(1 if _db("is_system_enabled", [sys_name]) else 0))
	_slider(v, "Traffic density", 0.0, 1.5, 0.1, float(Settings.get_value("traffic_density")), "percent",
			func(x: float) -> void: _d("set_density", ["traffic", x]))
	_slider(v, "Pedestrian density", 0.0, 1.5, 0.1, float(Settings.get_value("ped_density")), "percent",
			func(x: float) -> void: _d("set_density", ["peds", x]))
	_hint_label(v)
	_first_focus["world"] = hour
	return sp[0]


# =================================================================================================
# SERVICES
# =================================================================================================

func _page_services() -> Control:
	var page := UiKit.vbox(8)
	_svc_list = UiList.new()
	_svc_list.item_activated.connect(_on_service)
	page.add_child(_svc_list)
	_note(page, "Services come online as their systems are built; unavailable ones are greyed out.")
	_first_focus["services"] = _svc_list
	return page


func _fill_services() -> void:
	if _svc_list == null:
		return
	var items: Array = []
	for s: Dictionary in SERVICES:
		var reason := _reason(str(s["feature"]))
		items.append({"text": s["text"], "sub": s["sub"] if reason == "" else "Not available - " + reason, "icon": s["icon"],
				"icon_color": UiStyle.TEAL_LIGHT if reason == "" else UiStyle.DIM, "disabled": reason != "", "id": s["id"]})
	_svc_list.set_items(items, true)


func _on_service(_i: int, item: Dictionary) -> void:
	match str(item["id"]):
		"taxi":
			_d("call_taxi")
		"deliver":
			_d("deliver_personal_vehicle")
		"store":
			_d("store_current_vehicle")
		"customise":
			_d("open_customisation")
		"phone", "garage", "wardrobe":
			var sid := str(item["id"])
			close_self()
			UI.open_screen(sid)
		"quick_save":
			UI.quick_save()
		"quick_load":
			close_self()
			UI.quick_load()


# =================================================================================================
# DEBUG
# =================================================================================================

func _page_debug() -> Control:
	var sp := _scroll_page()
	var v: VBoxContainer = sp[1]
	var ov := _option(v, "Performance overlay (F3)", ["Off", "On"], 1 if _db("is_overlay_visible") else 0,
			func(i: int) -> void: _d("set_overlay_visible", [i == 1]))
	var hud := _option(v, "HUD", ["Hidden", "Visible"], 1, func(i: int) -> void: UI.set_hud_visible(i == 1))
	var ts := _slider(v, "Time scale", 0.25, 2.0, 0.05, _df("get", ["time_scale"], 1.0), "x%.2f",
			func(x: float) -> void: _d("set_time_scale", [x]))
	_buttons(v, [["x0.25", func() -> void: _d("set_time_scale", [0.25]), ""], ["x0.5", func() -> void: _d("set_time_scale", [0.5]), ""],
			["x1", func() -> void: _d("set_time_scale", [1.0]), ""], ["x2", func() -> void: _d("set_time_scale", [2.0]), ""]])
	_section(v, "Live")
	var rows := {}
	for key: String in ["FPS", "Frame time", "Rendering", "Position", "District / sector", "Entities", "Scene"]:
		var r := UiKit.stat_row(key, "-")
		v.add_child(r)
		rows[key] = r
	_bind_live(func() -> void:
		ov.set_index_silent(1 if _db("is_overlay_visible") else 0)
		hud.set_index_silent(1 if UI.hud == null or UI.hud.visible or not Game.is_ready else 0)
		if not ts.slider.has_focus():
			ts.set_value_silent(_df("get", ["time_scale"], 1.0))
		var s: Variant = _d("refresh_stats")
		if not (s is Dictionary):
			return
		var d: Dictionary = s
		var p: Vector3 = d.get("position", Vector3.ZERO)
		UiKit.set_stat_value(rows["FPS"], "%d   avg %.1f   1%% low %.1f" % [int(d["fps"]), float(d["avg_fps"]), float(d["low_1_fps"])])
		UiKit.set_stat_value(rows["Frame time"], "%.1f ms   worst %.1f ms" % [float(d["avg_ms"]), float(d["worst_ms"])])
		UiKit.set_stat_value(rows["Rendering"], "%d draws   %.2f M prims" % [int(d["draw_calls"]), float(d["primitives"]) / 1000000.0])
		UiKit.set_stat_value(rows["Position"], "%.1f   %.1f   %.1f" % [p.x, p.y, p.z])
		UiKit.set_stat_value(rows["District / sector"], "%s   %s" % [UiMapData.district_name(str(d["district"])) if str(d["district"]) != "" else "-", str(d["sector"])])
		UiKit.set_stat_value(rows["Entities"], "%d veh   %d peds   %d police   %d animals" % [int(d["vehicles"]), int(d["peds"]), int(d["police"]), int(d["animals"])])
		UiKit.set_stat_value(rows["Scene"], "%d nodes   %d objects" % [int(d["nodes"]), int(d["objects"])]))
	_section(v, "Clean up")
	_buttons(v, [["Clear spawned vehicles", func() -> void: _d("clear_admin_vehicles"), "vehicles"],
			["Repair all vehicles", func() -> void: _d("repair_all_vehicles"), "vehicles"],
			["Respawn pickups", func() -> void: _d("respawn_pickups"), ""]])
	_hint_label(v)
	_first_focus["debug"] = ov
	return sp[0]
