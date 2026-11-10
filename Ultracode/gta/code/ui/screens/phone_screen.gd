extends UiScreen
## "Shoreline" - the player's smartphone (P key / d-pad up). An original handset that slides in on
## the right: status bar, sunset wallpaper, a 4 x 2 grid of apps and a "today" card.
##   Contacts  taxi (Game.get_system("taxi").call_taxi(pos)), mechanic (garage
##             deliver_personal_vehicle(pos)), ambulance / fire (emergency system, if it offers it)
##   Map       full map screen, clear waypoint, one-tap GPS to every named place (UI.set_waypoint)
##   Camera    photo mode            Radio   pick a station (radio system)
##   Garage    personal vehicle delivery + the stored vehicles (garage system)
##   Skills    status screen         Save    quick save / load       Settings  pause -> settings
## Every service degrades gracefully: a missing system shows the row greyed out ("Not in
## service"). The game keeps running while the phone is up (input is locked, mouse shown).
## Keyboard / pad: arrows or WASD move the focus, Enter selects, Esc goes back (home, then closes),
## P closes. UI.open_screen("phone", {"app": "contacts"}) opens straight into an app.

const PAUSES_GAME := false
const TIME_SCALE := 1.0
const LOCKS_INPUT := true
const SHOWS_MOUSE := true
const HIDES_HUD := false

const DEVICE := Vector2(470.0, 900.0)
const BEZEL := 15.0
const STATUS_H := 50.0
const FOOT_H := 34.0
const RIGHT_GAP := 150.0
const CALL_TIME := 0.9            ## "calling ..." before the service answers (real seconds)
const RESULT_TIME := 1.8

const APPS: Array[Dictionary] = [
	{"id": "contacts", "name": "Contacts", "icon": &"call", "color": Color(0.933, 0.494, 0.392)},
	{"id": "map", "name": "Map", "icon": &"map", "color": Color(0.133, 0.655, 0.627)},
	{"id": "camera", "name": "Camera", "icon": &"camera", "color": Color(0.36, 0.44, 0.62)},
	{"id": "radio", "name": "Radio", "icon": &"note", "color": Color(1.0, 0.36, 0.62)},
	{"id": "garage", "name": "Garage", "icon": &"car", "color": Color(0.969, 0.788, 0.282)},
	{"id": "skills", "name": "Skills", "icon": &"stats", "color": Color(0.373, 0.839, 0.8)},
	{"id": "save", "name": "Save", "icon": &"save", "color": Color(0.345, 0.839, 0.553)},
	{"id": "settings", "name": "Settings", "icon": &"gear", "color": Color(0.655, 0.722, 0.8)},
]
const CONTACTS: Array[Dictionary] = [
	{"id": "taxi", "name": "Bay Cabs", "sub": "A cab to where you stand", "icon": &"taxi", "color": Color(0.969, 0.788, 0.282)},
	{"id": "mechanic", "name": "Torque Garage", "sub": "Delivers your personal vehicle", "icon": &"wrench", "color": Color(0.373, 0.839, 0.8)},
	{"id": "ambulance", "name": "Halcyon Medical", "sub": "Ambulance to your location", "icon": &"hospital", "color": Color(1.0, 0.353, 0.322)},
	{"id": "fire", "name": "Bay Fire Dept", "sub": "Fire crew to your location", "icon": &"flame", "color": Color(1.0, 0.55, 0.2)},
]
const TAXI_METHODS: Array[String] = ["call_taxi", "request_taxi", "summon_taxi"]
const AMBULANCE_METHODS: Array[String] = ["call_ambulance", "request_ambulance", "dispatch_ambulance"]
const FIRE_METHODS: Array[String] = ["call_firetruck", "call_fire_truck", "request_firetruck", "dispatch_firetruck"]
const SERVICE_METHODS: Array[String] = ["call_service", "request_service", "dispatch_service", "dispatch"]

var page: String = "home"
var last_action: String = ""            ## tests: "taxi:ok", "mechanic:fail", "save:ok" ...

var _device: Control
var _body: UiCanvas
var _content: Control
var _page_root: Control = null
var _list: UiList = null
var _tiles: Array[Button] = []
var _slide: float = 1.0
var _base_top: float = 0.0
var _time: float = 0.0
var _clock_str: String = ""
var _clock_timer: float = 0.0
var _today: Label = null
var _home_clock: Label = null
var _home_date: Label = null
var _calling: Dictionary = {}           ## {id, name, icon, color, t, done, text, kind}
var _call_canvas: UiCanvas = null
var _focus_app: String = ""


func _init() -> void:
	super()
	backdrop_alpha = 0.22


func _ready() -> void:
	_device = Control.new()
	_device.name = "Device"
	_device.mouse_filter = Control.MOUSE_FILTER_STOP
	_device.anchor_left = 1.0
	_device.anchor_right = 1.0
	_device.anchor_top = 0.5
	_device.anchor_bottom = 0.5
	_device.offset_left = -RIGHT_GAP - DEVICE.x
	_device.offset_right = -RIGHT_GAP
	_base_top = -DEVICE.y * 0.5
	_device.offset_top = _base_top
	_device.offset_bottom = _base_top + DEVICE.y
	add_child(_device)
	_body = UiCanvas.new(_draw_body)
	_body.size = DEVICE
	_device.add_child(_body)
	_content = Control.new()
	_content.name = "Content"
	_content.clip_contents = true
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.position = Vector2(BEZEL, BEZEL + STATUS_H)
	_content.size = Vector2(DEVICE.x - BEZEL * 2.0, DEVICE.y - BEZEL * 2.0 - STATUS_H - FOOT_H)
	_device.add_child(_content)
	_call_canvas = UiCanvas.new(_draw_call)
	_call_canvas.position = _content.position
	_call_canvas.size = _content.size
	_call_canvas.visible = false
	_call_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_device.add_child(_call_canvas)
	_update_clock()


func open(args: Dictionary) -> void:
	_slide = 1.0
	_apply_slide()
	UiKit.sfx("phone_open", -3.0)
	var app := str(args.get("app", ""))
	if app != "" and _is_page_app(app):
		show_page(app)
	else:
		show_page("home")


func close() -> void:
	_calling.clear()


func regain_focus() -> void:
	# a screen opened from the phone (map, status, settings) closed: refresh and refocus
	show_page(page)


func handle_back() -> bool:
	if super.handle_back():
		return true
	if not _calling.is_empty():
		return true
	if page != "home":
		var from := page
		show_page("home")
		_focus_tile(from)
		UiKit.sfx("ui_close", -6.0)
		return true
	return false


# --- public API (tests, gamepad glue) ------------------------------------------------------------------

func get_page() -> String:
	return page


func get_app_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for a in APPS:
		out.append(str(a["id"]))
	return out


## Launch an app by id (same as selecting its tile).
func launch(app_id: String) -> void:
	_focus_app = app_id
	match app_id:
		"camera":
			last_action = "camera:ok"
			close_self()
			UI.call_deferred("open_screen", "photo", {})
		"skills":
			last_action = "skills:ok" if UI.open_screen("status") != null else "skills:fail"
		"settings":
			last_action = "settings:ok" if UI.open_screen("pause", {"page": "settings"}) != null else "settings:fail"
		_:
			if _is_page_app(app_id):
				show_page(app_id)
				UiKit.sfx("ui_tab", -6.0)


func get_list() -> UiList:
	return _list


## Activate row `index` of the current app list (tests).
func activate_row(index: int) -> void:
	if _list == null:
		return
	var it := _list.get_item(index)
	if it.is_empty():
		return
	if bool(it.get("disabled", false)):
		UiKit.sfx("ui_error")
		return
	_on_row(index, it)


## Index of the row whose item "id" equals `id` (-1 if none).
func find_row(id: Variant) -> int:
	if _list == null:
		return -1
	for i in _list.get_count():
		var v: Variant = _list.get_item(i).get("id")
		if typeof(v) == typeof(id) and v == id:
			return i
	return -1


func is_calling() -> bool:
	return not _calling.is_empty()


## Contacts availability (also used to grey the rows): "" when the service can be called,
## otherwise the reason shown under the contact.
func service_status(contact_id: String) -> String:
	match contact_id:
		"taxi":
			return "" if _method_of(Game.get_system("taxi"), TAXI_METHODS) != "" else "Not in service"
		"mechanic":
			var g := Game.get_system("garage")
			if g == null or not g.has_method("deliver_personal_vehicle"):
				return "Not in service"
			return ""
		"ambulance":
			return "" if _emergency_method("ambulance") != "" else "Not in service"
		"fire":
			return "" if _emergency_method("fire") != "" else "Not in service"
	return "Unknown"


# --- pages ---------------------------------------------------------------------------------------------

func _is_page_app(id: String) -> bool:
	return id in ["home", "contacts", "map", "radio", "garage", "save"]


func show_page(p: String) -> void:
	page = p
	_list = null
	_tiles.clear()
	_today = null
	_home_clock = null
	_home_date = null
	if _page_root != null:
		_content.remove_child(_page_root)
		_page_root.queue_free()
		_page_root = null
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 10)
	UiKit.fill(margin)
	_content.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_root = margin
	match p:
		"home": _build_home(margin)
		"contacts": _build_contacts(margin)
		"map": _build_map(margin)
		"radio": _build_radio(margin)
		"garage": _build_garage(margin)
		"save": _build_save(margin)
	_body.queue_redraw()


func _build_home(root: Control) -> void:
	var col := UiKit.vbox(6)
	root.add_child(col)
	var brand := UiKit.label("S H O R E L I N E", &"", HORIZONTAL_ALIGNMENT_CENTER)
	brand.add_theme_font_override("font", UiStyle.font(&"head"))
	brand.add_theme_font_size_override("font_size", UiStyle.FS_TINY)
	brand.add_theme_color_override("font_color", Color(UiStyle.CREAM, 0.55))
	col.add_child(brand)
	_home_clock = UiKit.label(_clock_str, &"", HORIZONTAL_ALIGNMENT_CENTER)
	_home_clock.add_theme_font_override("font", UiStyle.font(&"num"))
	_home_clock.add_theme_font_size_override("font_size", 96)
	_home_clock.add_theme_color_override("font_color", UiStyle.CREAM)
	_home_clock.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	_home_clock.add_theme_constant_override("shadow_offset_y", 3)
	col.add_child(_home_clock)
	_home_date = UiKit.label("", &"", HORIZONTAL_ALIGNMENT_CENTER)
	_home_date.add_theme_font_override("font", UiStyle.font(&"head"))
	_home_date.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
	_home_date.add_theme_color_override("font_color", Color(UiStyle.CREAM, 0.9))
	col.add_child(_home_date)
	col.add_child(UiKit.spacer(Vector2(0, 10), true))
	var grid := UiKit.grid(4, 12, 14)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(grid)
	for a in APPS:
		var tile := AppTile.new(str(a["id"]), str(a["name"]), a["icon"], a["color"])
		tile.pressed.connect(launch.bind(str(a["id"])))
		grid.add_child(tile)
		_tiles.append(tile)
	col.add_child(UiKit.spacer(Vector2(0, 12), false))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.box(Color(0.02, 0.05, 0.1, 0.62), 18, UiStyle.LINE, 2, 0, 18, 12))
	col.add_child(card)
	_today = UiKit.label("", &"")
	_today.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
	_today.add_theme_color_override("font_color", UiStyle.CREAM)
	_today.add_theme_constant_override("line_spacing", 4)
	card.add_child(_today)
	_refresh_home()
	_focus_tile(_focus_app if _focus_app != "" else "contacts")


func _app_header(root: Control, title: String, sub: String, col: Color) -> VBoxContainer:
	var v := UiKit.vbox(10)
	root.add_child(v)
	var h := UiKit.hbox(10)
	v.add_child(h)
	var back := UiKit.button("", func() -> void: handle_back(), &"GhostButton")
	back.custom_minimum_size = Vector2(46, 46)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.focus_mode = Control.FOCUS_NONE
	var chev := UiKit.icon(&"chev_left", 22.0, UiStyle.CREAM)
	chev.position = Vector2(12, 12)
	back.add_child(chev)
	h.add_child(back)
	var hd := UiKit.header(title, sub)
	hd.accent = col
	hd.title_size = UiStyle.FS_H3
	h.add_child(hd)
	return v


func _build_contacts(root: Control) -> void:
	var v := _app_header(root, "Contacts", "Services around the bay", APPS[0]["color"])
	_list = UiList.new()
	_list.item_activated.connect(_on_row)
	v.add_child(_list)
	var items: Array = []
	for c in CONTACTS:
		var status := service_status(str(c["id"]))
		var sub := str(c["sub"]) if status == "" else status
		if str(c["id"]) == "mechanic" and status == "":
			sub = _personal_vehicle_line()
		items.append({"text": str(c["name"]), "sub": sub, "icon": c["icon"], "icon_color": c["color"], "id": str(c["id"]),
				"disabled": status != ""})
	_list.set_items(items)
	_list.grab()


func _build_map(root: Control) -> void:
	var v := _app_header(root, "Map", "GPS to anywhere on the island", APPS[1]["color"])
	_list = UiList.new()
	_list.item_activated.connect(_on_row)
	v.add_child(_list)
	var items: Array = [{"text": "Open full map", "sub": "Pan, zoom, place a waypoint", "icon": &"map", "icon_color": UiStyle.TEAL_LIGHT, "id": "open_map"}]
	if UI.has_waypoint():
		items.append({"text": "Clear waypoint", "sub": _waypoint_line(), "icon": &"close", "icon_color": UiStyle.CORAL, "id": "clear_wp"})
	var data: UiMapData = UI.map_data
	if data != null:
		if data.places.is_empty():
			data.refresh()
		var me := Game.get_player_position()
		var me2 := Vector2(me.x, me.z)
		var places: Array = []
		for pl in data.places:
			if bool(pl.get("minor", false)):
				continue
			places.append(pl)
		places.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return me2.distance_squared_to(a["pos"]) < me2.distance_squared_to(b["pos"]))
		var wp := Vector2(UI.nav.waypoint.x, UI.nav.waypoint.z) if UI.has_waypoint() else Vector2.INF
		for pl: Dictionary in places:
			var pos: Vector2 = pl["pos"]
			var set_here := wp != Vector2.INF and wp.distance_to(pos) < 3.0
			items.append({"text": str(pl["name"]), "icon": pl["icon"], "icon_color": pl["color"], "id": pos,
					"right": _dist_text(me2.distance_to(pos)), "right_color": UiStyle.MUTED, "badge": "SET" if set_here else ""})
	_list.set_items(items)
	_list.grab()


func _build_radio(root: Control) -> void:
	var radio := Game.get_system("radio")
	var listening := radio != null and radio.has_method("is_listening") and bool(radio.call("is_listening"))
	var v := _app_header(root, "Radio", "On air now" if listening else "Plays when you sit in a vehicle", APPS[3]["color"])
	_list = UiList.new()
	_list.item_activated.connect(_on_row)
	v.add_child(_list)
	var items: Array = []
	if radio == null or not radio.has_method("get_stations"):
		items.append({"text": "Radio unavailable", "sub": "No signal", "icon": &"radio", "disabled": true, "id": ""})
	else:
		var cur := str(radio.call("get_station")) if radio.has_method("get_station") else "off"
		var list: Variant = radio.call("get_stations", true) if radio.get_method_argument_count("get_stations") > 0 else radio.call("get_stations")
		if list is Array:
			for e: Variant in list:
				if not (e is Dictionary):
					continue
				var d: Dictionary = e
				var id := str(d.get("id", ""))
				var col: Variant = d.get("color", UiStyle.CORAL)
				var sub := str(d.get("genre", ""))
				if str(d.get("frequency", "")) != "":
					sub += ("  -  " if sub != "" else "") + str(d.get("frequency")) + " FM"
				items.append({"text": str(d.get("name", id)) if id != "off" else "Radio Off", "sub": sub,
						"icon": &"power" if id == "off" else &"note", "icon_color": col if (col is Color and id != "off") else UiStyle.MUTED,
						"id": id, "badge": "ON AIR" if id == cur and listening and id != "off" else ("SELECTED" if id == cur else "")})
	_list.set_items(items)
	_list.grab()


func _build_garage(root: Control) -> void:
	var g := Game.get_system("garage")
	var v := _app_header(root, "Garage", "Your vehicles", APPS[4]["color"])
	_list = UiList.new()
	_list.item_activated.connect(_on_row)
	v.add_child(_list)
	var items: Array = []
	if g == null:
		items.append({"text": "Garage unavailable", "sub": "Not in service", "icon": &"car", "disabled": true, "id": ""})
	else:
		var ok := g.has_method("deliver_personal_vehicle")
		items.append({"text": "Deliver personal vehicle", "sub": _personal_vehicle_line() if ok else "Not in service", "icon": &"wrench",
				"icon_color": UiStyle.TEAL_LIGHT, "id": "deliver", "disabled": not ok})
		var stored: Array = []
		if g.has_method("get_stored"):
			var s: Variant = g.call("get_stored")
			if s is Array:
				stored = s
		var cap := int(g.call("get_capacity")) if g.has_method("get_capacity") else stored.size()
		for i in stored.size():
			var d: Variant = stored[i]
			if not (d is Dictionary):
				continue
			var nm := str((d as Dictionary).get("name", str((d as Dictionary).get("spec_id", "Vehicle")).capitalize()))
			var hp := float((d as Dictionary).get("health", -1.0))
			var mhp := float((d as Dictionary).get("max_health", 1000.0))
			var sub := "Stored at the safehouse"
			if hp >= 0.0:
				sub = "Condition %d%%" % int(clampf(hp / maxf(mhp, 1.0), 0.0, 1.0) * 100.0)
			items.append({"text": nm, "sub": sub, "icon": &"car", "icon_color": UiStyle.SUN, "id": "stored_%d" % i,
					"badge": "PERSONAL" if bool((d as Dictionary).get("personal", false)) else "", "right": "%d/%d" % [i + 1, cap],
					"right_color": UiStyle.MUTED})
		if stored.is_empty():
			items.append({"text": "No stored vehicles", "sub": "Store one at the safehouse garage", "icon": &"info", "disabled": true, "id": ""})
	_list.set_items(items)
	_list.grab()


func _build_save(root: Control) -> void:
	var v := _app_header(root, "Save", "Quick slot", APPS[6]["color"])
	_list = UiList.new()
	_list.item_activated.connect(_on_row)
	v.add_child(_list)
	var has := SaveSystem.has_save(UI.QUICK_SLOT)
	var items: Array = [
		{"text": "Quick save", "sub": "Overwrites the quick slot (F5)", "icon": &"save", "icon_color": UiStyle.GOOD, "id": "save"},
		{"text": "Load quick save", "sub": _save_age_line() if has else "No quick save yet", "icon": &"load", "icon_color": UiStyle.TEAL_LIGHT,
				"id": "load", "disabled": not has},
	]
	_list.set_items(items)
	_list.grab()


# --- actions -------------------------------------------------------------------------------------------

func _on_row(_index: int, item: Dictionary) -> void:
	if not _calling.is_empty():
		return
	var id: Variant = item.get("id")
	match page:
		"contacts":
			_start_call(str(id))
		"map":
			if id is Vector2:
				var p2: Vector2 = id
				UI.set_waypoint(Vector3(p2.x, Game.ground_height(p2.x, p2.y), p2.y))
				last_action = "waypoint:ok"
				UI.notify("Waypoint set  -  %s" % str(item.get("text", "")), "info", 2.6)
				UiKit.sfx("ui_click")
				show_page("map")
				_list.select(find_row(id))
			elif str(id) == "open_map":
				last_action = "map:ok" if UI.open_screen("map") != null else "map:fail"
			elif str(id) == "clear_wp":
				UI.clear_waypoint()
				last_action = "waypoint:clear"
				show_page("map")
		"radio":
			var radio := Game.get_system("radio")
			if radio != null and radio.has_method("set_station") and str(id) != "":
				radio.call("set_station", str(id))
				last_action = "radio:" + str(id)
				var sel := _list.selected
				show_page("radio")
				_list.select(sel)
		"garage":
			if str(id) == "deliver":
				_start_call("mechanic")
		"save":
			if str(id) == "save":
				var ok := UI.quick_save()
				last_action = "save:ok" if ok else "save:fail"
				show_page("save")
			elif str(id) == "load":
				var dlg := confirm("Load quick save?", "Progress since that save is lost.", "Load", "Cancel", true)
				dlg.confirmed.connect(func() -> void:
					last_action = "load:ok" if UI.quick_load() else "load:fail"
					close_self())


func _start_call(contact_id: String) -> void:
	var c: Dictionary = {}
	for e in CONTACTS:
		if str(e["id"]) == contact_id:
			c = e
	if c.is_empty():
		return
	if service_status(contact_id) != "":
		UiKit.sfx("ui_error")
		last_action = contact_id + ":unavailable"
		return
	_calling = {"id": contact_id, "name": str(c["name"]), "icon": c["icon"], "color": c["color"], "t": 0.0, "done": false,
			"text": "", "kind": "info"}
	_call_canvas.visible = true
	_content.visible = false
	UiKit.sfx("ui_click")


## Runs the service call (after the short "calling" animation). Returns [text, kind].
func _perform_call(contact_id: String) -> Array:
	var pos := Game.get_player_position()
	match contact_id:
		"taxi":
			var t := Game.get_system("taxi")
			var m := _method_of(t, TAXI_METHODS)
			if m == "":
				return ["Bay Cabs is not answering", "warn"]
			var r: Variant = t.call(m) if t.get_method_argument_count(m) == 0 else t.call(m, pos)
			var ok: bool = r != null and not (r is bool and not bool(r))
			last_action = "taxi:" + ("ok" if ok else "fail")
			var err := UiKit.text_of(t, &"last_error", "")
			return ["A cab is on its way", "good"] if ok else [err if err != "" else "No cab available right now", "warn"]
		"mechanic":
			var g := Game.get_system("garage")
			if g == null or not g.has_method("deliver_personal_vehicle"):
				return ["Torque Garage is closed", "warn"]
			var v: Variant = g.call("deliver_personal_vehicle", pos)
			var ok2: bool = v is Node3D and is_instance_valid(v)
			last_action = "mechanic:" + ("ok" if ok2 else "fail")
			if ok2:
				return ["%s delivered nearby" % _vehicle_name(v as Node3D), "good"]
			var err2 := UiKit.text_of(g, &"last_error", "")
			return [err2 if err2 != "" else "No personal vehicle to deliver", "warn"]
		"ambulance", "fire":
			var ok3 := _call_emergency(contact_id, pos)
			last_action = contact_id + ":" + ("ok" if ok3 else "fail")
			if contact_id == "ambulance":
				return ["An ambulance is on its way", "good"] if ok3 else ["No ambulance available", "warn"]
			return ["A fire crew is on its way", "good"] if ok3 else ["No fire crew available", "warn"]
	return ["Call failed", "bad"]


func _call_emergency(kind: String, pos: Vector3) -> bool:
	var e := Game.get_system("emergency")
	if e == null:
		return false
	var direct := _method_of(e, AMBULANCE_METHODS if kind == "ambulance" else FIRE_METHODS)
	var r: Variant = null
	if direct != "":
		r = e.call(direct) if e.get_method_argument_count(direct) == 0 else e.call(direct, pos)
	else:
		var generic := _method_of(e, SERVICE_METHODS)
		if generic == "":
			return false
		# the emergency system's incident kinds are "medical" / "fire"; vehicle names as a fallback
		var kinds: Array[String] = ["medical", "ambulance"] if kind == "ambulance" else ["fire", "firetruck"]
		for k in kinds:
			r = e.call(generic, k, pos)
			if r != null and not (r is bool and not bool(r)):
				return true
		return false
	return r != null and not (r is bool and not bool(r))


func _emergency_method(kind: String) -> String:
	var e := Game.get_system("emergency")
	if e == null:
		return ""
	var m := _method_of(e, AMBULANCE_METHODS if kind == "ambulance" else FIRE_METHODS)
	if m != "":
		return m
	return _method_of(e, SERVICE_METHODS)


func _method_of(obj: Object, names: Array[String]) -> String:
	if obj == null or not is_instance_valid(obj):
		return ""
	for m in names:
		if obj.has_method(m):
			return m
	return ""


# --- text helpers --------------------------------------------------------------------------------------

func _personal_vehicle_line() -> String:
	var g := Game.get_system("garage")
	if g == null:
		return "Delivers your personal vehicle"
	var pv: Variant = g.call("get_personal_vehicle") if g.has_method("get_personal_vehicle") else null
	if pv is Node3D and is_instance_valid(pv):
		var d := (pv as Node3D).global_position.distance_to(Game.get_player_position())
		return "%s  -  %s away" % [_vehicle_name(pv as Node3D), _dist_text(d)]
	if g.has_method("get_stored"):
		var s: Variant = g.call("get_stored")
		if s is Array:
			for e: Variant in s:
				if e is Dictionary and bool((e as Dictionary).get("personal", false)):
					return "%s  -  in the garage" % str((e as Dictionary).get("name", "Vehicle"))
	return "No personal vehicle yet"


func _vehicle_name(v: Node3D) -> String:
	var spec := UiKit.text_of(v, &"spec_id", "")
	var def: Variant = Registry.get_def("vehicles", spec) if spec != "" else null
	var dn := str(HudRoot._def_get(def, "display_name", ""))
	return dn if dn != "" else (spec.capitalize() if spec != "" else "Vehicle")


func _waypoint_line() -> String:
	if not UI.has_waypoint():
		return ""
	var me := Game.get_player_position()
	var wp: Vector3 = UI.nav.waypoint
	var name := ""
	if UI.map_data != null:
		var pl := UI.map_data.place_at(Vector2(wp.x, wp.z), 6.0)
		name = str(pl.get("name", ""))
	var d := _dist_text(Vector2(me.x, me.z).distance_to(Vector2(wp.x, wp.z)))
	return ("%s  -  %s" % [name, d]) if name != "" else d + " away"


func _save_age_line() -> String:
	var path := ""
	if SaveSystem.has_method("slot_path"):
		path = str(SaveSystem.call("slot_path", UI.QUICK_SLOT))
	if path == "" or not FileAccess.file_exists(path):
		return "Quick save available"
	var age := int(Time.get_unix_time_from_system()) - int(FileAccess.get_modified_time(path))
	if age < 60:
		return "Saved just now"
	if age < 3600:
		return "Saved %d min ago" % (age / 60)
	if age < 86400:
		return "Saved %d h ago" % (age / 3600)
	return "Saved %d days ago" % (age / 86400)


static func _dist_text(m: float) -> String:
	if m >= 1000.0:
		return "%.1f km" % (m / 1000.0)
	return "%d m" % int(round(m / 10.0) * 10.0) if m >= 20.0 else "here"


func _refresh_home() -> void:
	if _home_clock != null:
		_home_clock.text = _clock_str
	if _home_date != null:
		var district := ""
		var w := Game.world
		if w != null and is_instance_valid(w) and w.has_method("get_district"):
			district = UiMapData.district_name(str(w.call("get_district", Game.get_player_position())))
		var weather := str(Weather.current).capitalize()
		var day := int(WorldClock.get_day()) if WorldClock.has_method("get_day") else 1
		var parts := PackedStringArray(["DAY %d" % day, weather.to_upper()])
		if district != "":
			parts.append(district.to_upper())
		_home_date.text = "  -  ".join(parts)
	if _today != null:
		var lines := PackedStringArray()
		lines.append("Cash  %s" % UiStyle.money(Game.money))
		if Wanted.level > 0:
			lines.append("Police: %d star%s  -  %s" % [Wanted.level, "" if Wanted.level == 1 else "s",
					"searching" if Wanted.state == Wanted.State.SEARCH else "in pursuit"])
		if UI.has_waypoint():
			lines.append("Waypoint  %s" % _waypoint_line())
		else:
			lines.append("No waypoint  -  set one in Map")
		_today.text = "\n".join(lines)


func _focus_tile(app_id: String) -> void:
	for t in _tiles:
		if (t as AppTile).app_id == app_id:
			t.grab_focus()
			return
	if not _tiles.is_empty():
		_tiles[0].grab_focus()


# --- frame ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var dt := delta / maxf(Engine.time_scale, 0.05)
	_time += dt
	if _slide > 0.0:
		_slide = maxf(_slide - dt * 5.0, 0.0)
		_apply_slide()
	_clock_timer += dt
	if _clock_timer >= 0.5:
		_clock_timer = 0.0
		_update_clock()
		if page == "home":
			_refresh_home()
	if not _calling.is_empty():
		_calling["t"] = float(_calling["t"]) + dt
		if not bool(_calling["done"]) and float(_calling["t"]) >= CALL_TIME:
			var res := _perform_call(str(_calling["id"]))
			_calling["done"] = true
			_calling["text"] = str(res[0])
			_calling["kind"] = str(res[1])
			UiKit.sfx("ui_buy" if str(res[1]) == "good" else "ui_error", -4.0)
			UI.notify("%s: %s" % [str(_calling["name"]), str(res[0])], str(res[1]), 3.2)
		elif bool(_calling["done"]) and float(_calling["t"]) >= CALL_TIME + RESULT_TIME:
			_calling.clear()
			_call_canvas.visible = false
			_content.visible = true
			show_page(page)
		_call_canvas.queue_redraw()


func _apply_slide() -> void:
	var k := ease(_slide, 2.2)
	var off := k * (DEVICE.y * 0.5 + 640.0)
	_device.offset_top = _base_top + off
	_device.offset_bottom = _base_top + DEVICE.y + off
	_device.rotation = deg_to_rad(4.0 * k)
	_device.pivot_offset = DEVICE * 0.5


func _update_clock() -> void:
	var t := WorldClock.get_time_string()
	if t != _clock_str:
		_clock_str = t
		_body.queue_redraw()


# --- drawing -------------------------------------------------------------------------------------------

func _draw_body(c: UiCanvas) -> void:
	var r := Rect2(Vector2.ZERO, DEVICE)
	# shadow + shell
	c.draw_style_box(UiStyle.box(Color(0, 0, 0, 0.4), 56), r.grow(6.0))
	c.draw_style_box(UiStyle.box(Color(0.05, 0.08, 0.13), 54, UiStyle.CORAL, 3), r)
	c.draw_style_box(UiStyle.box(Color(1, 1, 1, 0.06), 52, UiStyle.CLEAR, 0), r.grow(-4.0))
	# side buttons
	c.draw_rect(Rect2(DEVICE.x - 1.0, 170.0, 5.0, 70.0), UiStyle.CORAL.darkened(0.25))
	c.draw_rect(Rect2(-4.0, 150.0, 5.0, 46.0), UiStyle.CORAL.darkened(0.25))
	c.draw_rect(Rect2(-4.0, 206.0, 5.0, 46.0), UiStyle.CORAL.darkened(0.25))
	var scr := Rect2(BEZEL, BEZEL, DEVICE.x - BEZEL * 2.0, DEVICE.y - BEZEL * 2.0)
	if page == "home":
		_draw_wallpaper(c, scr)
	else:
		c.draw_style_box(UiStyle.box(Color(0.045, 0.085, 0.15), 40), scr)
		c.draw_style_box(UiStyle.box(Color(1, 1, 1, 0.03), 40), Rect2(scr.position, Vector2(scr.size.x, STATUS_H + 70.0)))
	# status bar
	var num := UiStyle.font(&"num")
	var head := UiStyle.font(&"head")
	UiStyle.text(c, num, Vector2(scr.position.x + 34.0, scr.position.y + 34.0), _clock_str, UiStyle.FS_SMALL, UiStyle.CREAM)
	# camera notch
	var notch := Rect2(scr.get_center().x - 46.0, scr.position.y + 12.0, 92.0, 26.0)
	c.draw_style_box(UiStyle.box(Color(0.02, 0.03, 0.05), 13), notch)
	c.draw_circle(Vector2(notch.end.x - 16.0, notch.get_center().y), 5.0, Color(0.12, 0.2, 0.32), true, -1.0, true)
	UiIcons.draw(c, &"signal", Vector2(scr.end.x - 88.0, scr.position.y + 26.0), 20.0, UiStyle.CREAM)
	UiIcons.draw(c, &"battery", Vector2(scr.end.x - 50.0, scr.position.y + 26.0), 26.0, UiStyle.CREAM)
	# home indicator
	var hb := Rect2(scr.get_center().x - 70.0, scr.end.y - 18.0, 140.0, 6.0)
	c.draw_style_box(UiStyle._fill_box(Color(1, 1, 1, 0.55)), hb)


## Original wallpaper: sunset over the bay - gradient sky, sun, hill silhouettes and water lines.
func _draw_wallpaper(c: CanvasItem, scr: Rect2) -> void:
	var top := Color(0.09, 0.12, 0.3)
	var mid := Color(0.93, 0.42, 0.38)
	var low := Color(0.98, 0.74, 0.36)
	var horizon := scr.position.y + scr.size.y * 0.56
	var x0 := scr.position.x
	var x1 := scr.end.x
	# sky (two gradient quads); the rounded corners are covered by the frame drawn on top
	c.draw_style_box(UiStyle.box(top, 40), scr)
	c.draw_polygon(PackedVector2Array([Vector2(x0, scr.position.y + 40.0), Vector2(x1, scr.position.y + 40.0),
			Vector2(x1, scr.position.y + scr.size.y * 0.34), Vector2(x0, scr.position.y + scr.size.y * 0.34)]),
			PackedColorArray([top, top, mid.lerp(top, 0.35), mid.lerp(top, 0.35)]))
	c.draw_polygon(PackedVector2Array([Vector2(x0, scr.position.y + scr.size.y * 0.34), Vector2(x1, scr.position.y + scr.size.y * 0.34),
			Vector2(x1, horizon), Vector2(x0, horizon)]), PackedColorArray([mid.lerp(top, 0.35), mid.lerp(top, 0.35), low, low]))
	# sun
	var sun_c := Vector2(scr.get_center().x + 60.0, horizon - 20.0)
	c.draw_circle(sun_c, 92.0, Color(1.0, 0.85, 0.5, 0.16), true, -1.0, true)
	c.draw_circle(sun_c, 62.0, Color(1.0, 0.9, 0.62), true, -1.0, true)
	# hills (Signal Hill silhouette + the city line)
	var hill := PackedVector2Array([Vector2(x0, horizon), Vector2(x0, horizon - 70.0), Vector2(x0 + 70.0, horizon - 120.0),
			Vector2(x0 + 150.0, horizon - 84.0), Vector2(x0 + 200.0, horizon - 40.0), Vector2(x0 + 230.0, horizon)])
	c.draw_colored_polygon(hill, Color(0.27, 0.16, 0.33))
	var city := PackedVector2Array([Vector2(x1 - 230.0, horizon)])
	var bx := x1 - 230.0
	var heights: Array[float] = [34.0, 62.0, 48.0, 90.0, 56.0, 74.0, 40.0, 28.0]
	for hgt in heights:
		city.append(Vector2(bx, horizon - hgt))
		bx += 27.0
		city.append(Vector2(bx, horizon - hgt))
	city.append(Vector2(x1, horizon - 20.0))
	city.append(Vector2(x1, horizon))
	c.draw_colored_polygon(city, Color(0.22, 0.13, 0.3))
	# sea
	var sea_top := Color(0.13, 0.36, 0.5)
	var sea_low := Color(0.04, 0.1, 0.2)
	var bottom := scr.end.y - 40.0
	c.draw_polygon(PackedVector2Array([Vector2(x0, horizon), Vector2(x1, horizon), Vector2(x1, bottom), Vector2(x0, bottom)]),
			PackedColorArray([sea_top, sea_top, sea_low, sea_low]))
	c.draw_style_box(UiStyle.box(sea_low, 40), Rect2(x0, bottom - 40.0, scr.size.x, scr.end.y - bottom + 40.0))
	for i in 7:
		var y := horizon + 10.0 + i * i * 7.0
		var w := 60.0 + i * 26.0
		c.draw_line(Vector2(sun_c.x - w * 0.5, y), Vector2(sun_c.x + w * 0.5, y), Color(1.0, 0.85, 0.55, 0.5 - i * 0.06), 3.0)
	# soft dark veil so text and tiles stay readable
	c.draw_style_box(UiStyle.box(Color(0.02, 0.04, 0.09, 0.28), 40), scr)


func _draw_call(c: UiCanvas) -> void:
	if _calling.is_empty():
		return
	var sz := c.size
	c.draw_style_box(UiStyle.box(Color(0.03, 0.06, 0.12), 30), Rect2(Vector2.ZERO, sz))
	var col: Color = _calling["color"]
	var ctr := Vector2(sz.x * 0.5, sz.y * 0.36)
	var t := float(_calling["t"])
	var done := bool(_calling["done"])
	if not done:
		for k in 3:
			var ph := fmod(t * 1.2 + k / 3.0, 1.0)
			c.draw_arc(ctr, 70.0 + ph * 90.0, 0.0, TAU, 64, Color(col, 0.5 * (1.0 - ph)), 4.0, true)
	c.draw_circle(ctr, 70.0, col, true, -1.0, true)
	var ok := str(_calling["kind"]) == "good"
	var glyph: StringName = _calling["icon"]
	if glyph == &"taxi":
		glyph = &"car"
	if done:
		glyph = &"check" if ok else &"close"
	UiIcons.draw(c, glyph, ctr, 70.0, UiStyle.NAVY_DEEP)
	var head := UiStyle.font(&"head")
	var body := UiStyle.font(&"body")
	UiStyle.text(c, head, Vector2(0.0, ctr.y + 130.0), str(_calling["name"]).to_upper(), UiStyle.FS_H3, UiStyle.TEXT,
			HORIZONTAL_ALIGNMENT_CENTER, sz.x, false)
	var line := "Calling" + ".".repeat(1 + int(t * 3.0) % 3)
	var lc: Color = UiStyle.MUTED
	if done:
		line = str(_calling["text"])
		lc = UiStyle.GOOD if ok else UiStyle.SUN
	UiStyle.text(c, body, Vector2(16.0, ctr.y + 176.0), line, UiStyle.FS_BODY, lc, HORIZONTAL_ALIGNMENT_CENTER, sz.x - 32.0, false)
	# hang-up button look
	var hb := Vector2(sz.x * 0.5, sz.y - 90.0)
	c.draw_circle(hb, 36.0, UiStyle.BAD if not done else Color(1, 1, 1, 0.12), true, -1.0, true)
	UiIcons.draw(c, &"call" if not done else &"check", hb, 34.0, UiStyle.CREAM)


# --- app tile ------------------------------------------------------------------------------------------

## One home-screen app: rounded tile in the app colour with a glyph, caption under it.
class AppTile extends Button:
	var app_id: String
	var caption: String
	var glyph: StringName
	var tint: Color
	var _box: StyleBoxFlat

	func _init(p_id: String, p_caption: String, p_glyph: StringName, p_tint: Color) -> void:
		app_id = p_id
		caption = p_caption
		glyph = p_glyph
		tint = p_tint
		text = ""
		flat = true
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(88.0, 116.0)
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(s, empty)
		_box = UiStyle.box(tint, 24)
		pressed.connect(func() -> void: UiKit.sfx("ui_click"))
		focus_entered.connect(func() -> void:
			UiKit.sfx("ui_hover", -10.0)
			queue_redraw())
		focus_exited.connect(queue_redraw)
		mouse_entered.connect(func() -> void: UiKit._focus_on_hover(self))

	func _draw() -> void:
		var tile := Rect2((size.x - 80.0) * 0.5, 4.0, 80.0, 80.0)
		var focused := has_focus()
		if focused:
			draw_style_box(UiStyle.box(UiStyle.CLEAR, 28, UiStyle.CREAM, 4), tile.grow(6.0))
		draw_style_box(UiStyle.box(Color(0, 0, 0, 0.3), 24), Rect2(tile.position + Vector2(0, 4), tile.size))
		draw_style_box(_box, tile)
		draw_style_box(UiStyle.box(Color(1, 1, 1, 0.16), 24), Rect2(tile.position, Vector2(tile.size.x, tile.size.y * 0.45)))
		UiIcons.draw(self, glyph, tile.get_center(), 42.0, UiStyle.NAVY_DEEP)
		var f := UiStyle.font(&"bold")
		UiStyle.text(self, f, Vector2(0.0, size.y - 6.0), caption, UiStyle.FS_TINY, UiStyle.CREAM if focused else Color(UiStyle.CREAM, 0.92),
				HORIZONTAL_ALIGNMENT_CENTER, size.x, true)
